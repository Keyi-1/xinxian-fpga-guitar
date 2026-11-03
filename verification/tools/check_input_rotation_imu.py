"""Focused RTL and actual original-project netlist checks for rotated inputs."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
from datetime import datetime
from check_karplus_strong import run, ROOT

BASE = ROOT / 'build/input_rotation_imu'
VENDOR = 'S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v'


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def save(p, obj):
    p.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')


def prepare_top(dest, src, gate):
    paths = list((ROOT/'rtl').rglob('*.v')) + list((ROOT/'rtl/config').glob('*.vh'))
    paths += list((ROOT/'mem').glob('*'))
    benches = ['tb_input_rotation_imu_top']
    names = set()
    for p in paths:
        if p.suffix == '.v':
            names.update(re.findall(r'\bmodule\s+(\w+)', p.read_text(encoding='utf-8-sig')))
    pattern = re.compile(r'\b('+'|'.join(sorted(names, key=len, reverse=True))+r')\b')
    for p in paths:
        if p.suffix not in ('.v', '.vh'):
            continue
        body = p.read_text(encoding='utf-8-sig')
        if gate and p.suffix == '.v':
            body = pattern.sub(lambda m: 'rtlref_'+m[0], body)
            for h in (ROOT/'rtl/config').glob('*.vh'):
                body = body.replace('rtlref_'+h.name, h.name)
        body = body.replace('../config/', src.as_posix()+'/').replace('../../mem/', (ROOT/'mem').as_posix()+'/')
        (src/p.name).write_text(body, encoding='utf-8')
    reference = ["force reference.u_touch.ready=1'b1;",
                 'force reference.millisecond_count=accelerated_ms_count;',
                 'force reference.posture.sensor.reader.bus.divider=accelerated_i2c_count;']
    fields = {'frame_valid': 'raw_frame', 'touch_count': 'raw_count', 'touch_id': 'raw_id',
              'raw_x': 'raw_x', 'raw_y': 'raw_y', 'max_x': 'range_x', 'max_y': 'range_y'}
    reference += [f'force reference.u_touch.{port}={value};' for port, value in fields.items()]
    (dest/'input_reference_stimulus.vh').write_text('\n'.join(reference)+'\n')
    extras = []
    if gate:
        from compare_synth_graph import parse
        vg = ROOT/'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
        shutil.copy2(vg, dest/'actual.vg')
        mods = parse(vg.read_text(encoding='utf-8'))
        fields = {'touch_ready': (1, "1'b1"), 'raw_valid': (1, 'raw_frame'), 'raw_count': (4, 'raw_count'),
                  'raw_id': (8, 'raw_id'), 'raw_x_Z': (16, 'raw_x'), 'raw_y_Z': (16, 'raw_y'),
                  'max_x_Z': (16, 'range_x'), 'max_y_Z': (16, 'range_y')}
        force = []
        for port, (width, value) in fields.items():
            assert mods['gt911_touch']['ports'][port] == ('output', [None] if width == 1 else list(range(width-1, -1, -1)))
            force.append(f'force gate.u_touch.{port}={value};')
        top = mods['neo_guitar_touch_game_top']
        sensors = [(k, n) for k, n, _ in top['cells'] if k == 'mpu6050_posture']
        assert len(sensors) == 1
        sensor, instance = sensors[0]
        readers = [(k, n) for k, n, _ in mods[sensor]['cells'] if k == 'mpu6050_reader']
        assert readers == [('mpu6050_reader', 'reader')]
        buses = [(k, n) for k, n, _ in mods['mpu6050_reader']['cells'] if k.startswith('i2c_register_master')]
        assert len(buses) == 1 and buses[0][1] == 'bus'
        sensor_path = 'gate.' + instance + ' '
        audit = {}
        for module, prefix, width, hierarchy, value in [
            (top, 'millisecond_count', 16, 'gate', 'accelerated_ms_count'),
            (mods[buses[0][0]], 'divider', 32, sensor_path+'.reader.bus', 'accelerated_i2c_count')]:
            found = {}
            for kind, name, pins in module['cells']:
                m = re.fullmatch(re.escape(prefix)+r'\[(\d+)\]', pins.get('Q', ''))
                if kind.startswith('DFF') and m:
                    assert pins['CLK'] == 'sys_clk_50m_d'
                    bit = int(m[1]);assert bit not in found
                    found[bit] = {'kind': kind, 'name': name, 'pins': pins}
                    force.append(f'force {hierarchy}.{name}.Q={value}[{bit}];')
            assert set(found) == set(range(width)), (prefix, found.keys())
            audit[prefix] = found
        observe = []
        for port, expr in [('touch_x', 'touch_x'), ('touch_y', 'touch_y'), ('mapped_valid', 'mapped_valid')]:
            width = 1 if port == 'mapped_valid' else 9
            assert mods['touch_coordinate_mapper']['ports'][port] == ('output', [None] if width == 1 else list(range(8, -1, -1)))
            observe.append(f'if(gate.u_coordinates.{port}!==reference.{expr})$fatal(1,"FAIL: actual mapper {port}");')
        for port, expr in [('\\posture.stable_pose', 'stable_pose'), ('\\posture.calibrated', 'calibrated'), ('\\posture.healthy', 'healthy')]:
            assert mods[sensor]['ports'][port][0] == 'output'
            observe.append(f'if({sensor_path}.{port} !==reference.posture.{expr})$fatal(1,"FAIL: actual sensor {expr}");')
        assert mods['guitar_effect_buttons']['ports']['timbre_mode_Z'] == ('output', [1, 0])
        observe.append('if(gate.u_buttons.timbre_mode_Z!==reference.timbre_mode)$fatal(1,"FAIL: actual timbre");')
        (dest/'input_gate_stimulus.vh').write_text('\n'.join(force)+'\n')
        (dest/'input_gate_observe.vh').write_text('\n'.join(observe)+'\n')
        extras = ['actual.vg']
        save(dest/'mapping.json', {'result': 'PASS', 'counter_q_audit': audit, 'forces': force,
                                  'reference_forces': reference, 'observation': observe,
                                  'scope': 'GT911 raw registered packet outputs and timer Q only; real MPU pins; no mapper/gesture/pose/timbre/note/PCM forcing'})
    bench = ROOT/'sim/tb/tb_input_rotation_imu_top.sv'
    shutil.copy2(bench, dest/bench.name)
    paths += [bench, ROOT/'sim/models/mpu6050_test_slave.sv', ROOT/'tools/compare_synth_graph.py']
    shutil.copy2(ROOT/'sim/models/mpu6050_test_slave.sv', dest/'mpu6050_test_slave.sv')
    return [*(['+define+ACTUAL_GATE'] if gate else []), *extras,
            *[str(p) for p in src.glob('*.v')], str(bench.name), 'mpu6050_test_slave.sv'], benches, paths


def simulate(kind, name, sensor_id):
    dest = BASE / name
    dest.mkdir(parents=True, exist_ok=False)
    src = dest / 'sources'
    src.mkdir()
    record = {'status': 'RUNNING', 'kind': kind, 'sensor_id': sensor_id,
              'started': datetime.now().astimezone().isoformat()}
    save(dest / 'process.json', record)
    paths = [ROOT / 'tools/check_input_rotation_imu.py', ROOT / 'tools/check_karplus_strong.py']
    try:
        if kind == 'components':
            paths += [ROOT / ('rtl/input/' + n + '.v') for n in (
                'touch_coordinate_mapper', 'imu_serial_multiplier', 'imu_posture_classifier')]
            benches = ['tb_touch_rotation_mapper', 'tb_imu_bidirectional', 'tb_imu_posture_classifier']
            paths += [ROOT / ('sim/tb/' + b + '.sv') for b in benches]
            frozen = BASE / 'before/source/rtl/input/imu_posture_classifier.v'
            body = frozen.read_text(encoding='utf-8-sig').replace(
                'module imu_posture_classifier #(', 'module accepted_imu_posture_classifier #(')
            (src / 'accepted_imu_posture_classifier.v').write_text(body, encoding='utf-8')
            paths.append(frozen)
            for p in paths:
                if p.suffix in ('.v', '.sv') and p != frozen:
                    shutil.copy2(p, src / p.name)
            compile_files = [str(p) for p in src.iterdir()]
        else:
            compile_files, benches, extra = prepare_top(dest, src, kind == 'gate')
            paths += extra
        manifest = {p.relative_to(ROOT).as_posix(): sha(p) for p in paths}
        save(dest / 'source_manifest.json', manifest)
        run('vlib.log', ['vlib.exe', 'work'], dest)
        run('compile.log', ['vlog.exe', '-sv', '+incdir+' + src.as_posix()+'+'+dest.as_posix(),
                            *([] if kind == 'components' else [VENDOR]), *compile_files], dest)
        assert '** Warning:' not in (dest / 'compile.log').read_text(), 'Compile warning requires review'
        logs = {}
        for b, params in [(b, [] if kind == 'components' else ['-gSENSOR_ID='+str(sensor_id)]) for b in benches]:
            log = run(b+'.log', ['vsim.exe', '-c', '-onfinish', 'stop', *params, 'work.'+b,
                                  '-do', 'run -all; quit -code 0 -f'], dest)
            assert 'PASS:' in log and 'FAIL:' not in log
            warnings = [line for line in log.splitlines() if '** Warning:' in line]
            allowed = {2697: {1860,1864,1868,1884,1888,1893,3130,3134,3138,3142,3313,3317},
                       13162: {16253,16484,16579,16674,16769,16855,16941}}
            unexpected = []
            for line in warnings:
                m = re.search(r'prim_sim.v\((\d+)\): \(vopt-(\d+)\)', line)
                if not m or int(m[1]) not in allowed.get(int(m[2]), set()):
                    unexpected.append(line)
            assert not unexpected, unexpected
            logs[b] = sha(dest / (b+'.log'))
            print('\n'.join(line for line in log.splitlines() if 'PASS:' in line), flush=True)
        for p, digest in manifest.items():
            assert sha(ROOT / p) == digest, p
        record.update(status='PASS', source_sha256=manifest, log_sha256=logs,
                      vendor_library_sha256=sha(Path(VENDOR)),
                      scope='RTL component tests' if kind == 'components' else
                      'Production256 calibration and timing counts; real MPU GPIO; raw GT911 registered frames only; timer waiting accelerated; no pose/tone/note/PCM result forcing')
        if kind == 'gate':
            assert sha(dest/'actual.vg') == sha(ROOT/'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg')
            record['netlist_sha256'] = sha(dest/'actual.vg')
            record['mapping_sha256'] = sha(dest/'mapping.json')
    except BaseException as exc:
        record.update(status='FAIL', failure=str(exc))
        raise
    finally:
        record['finished'] = datetime.now().astimezone().isoformat()
        save(dest/'verification.json', record)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('kind', choices=('components', 'rtl_top', 'gate'))
    ap.add_argument('name')
    ap.add_argument('--sensor-id', type=lambda s: int(s, 0), choices=(0x68, 0x70), default=0x70)
    args = ap.parse_args()
    assert re.fullmatch(r'[A-Za-z0-9_]+', args.name)
    simulate(args.kind, args.name, args.sensor_id)
