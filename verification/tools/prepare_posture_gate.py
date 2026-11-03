"""Audit the actual full P4 VG before any simulation timing acceleration.

Only registered touch/ADC event outputs and all Q bits of two explicitly
identified counters may be stimulated. No ROM, DDS or audio result forces.
"""
from pathlib import Path
import hashlib
import json
import re
import sys

from compare_synth_graph import parse
from prepare_game_p3_gate import prepare


def main(vg, out):
    prepare(vg, out)
    modules = parse(vg.read_text(encoding='utf-8'))
    top = modules['neo_guitar_touch_game_top']

    def counter(module, prefix, width, hierarchy, value):
        found = {}
        for kind, name, pins in module['cells']:
            hit = re.fullmatch(re.escape(prefix)+r'\[(\d+)\]', pins.get('Q',''))
            if kind.startswith('DFF') and hit:
                bit = int(hit[1])
                assert bit not in found and pins['CLK'] == 'sys_clk_50m_d'
                assert re.fullmatch(r'\w+', name), name
                found[bit] = dict(primitive=kind, instance=name, pins=pins)
        assert set(found) == set(range(width)), (prefix, found.keys())
        lines = [f'force {hierarchy}.{row["instance"]}.Q={value}[{bit}];'
                 for bit,row in sorted(found.items())]
        return found, lines

    ms, ms_lines = counter(top, 'millisecond_count', 16, 'gate', 'accelerated_ms_count')
    sensor = [(kind,name,pins) for kind,name,pins in top['cells'] if kind == 'mpu6050_posture']
    assert len(sensor) == 1
    sensor_kind, sensor_name, _ = sensor[0]
    readers = [(k,n,p) for k,n,p in modules[sensor_kind]['cells'] if k == 'mpu6050_reader']
    assert len(readers) == 1 and readers[0][1] == 'reader'
    buses = [(k,n,p) for k,n,p in modules['mpu6050_reader']['cells'] if k.startswith('i2c_register_master')]
    assert len(buses) == 1 and buses[0][1] == 'bus'
    bus_kind = buses[0][0]
    path = 'gate.'+sensor_name+' .reader.bus'
    divider, divider_lines = counter(modules[bus_kind], 'divider', 32, path, 'accelerated_i2c_count')
    adc = modules['mcp3208_pluck_frontend']
    assert adc['ports']['pluck_valid_Z'] == ('output',[3,2,1,0])
    force = ms_lines+divider_lines+[
        'force reference.millisecond_count=accelerated_ms_count;',
        'force reference.posture.sensor.reader.bus.divider=accelerated_i2c_count;',
        'force gate.u_audio.u_adc.pluck_valid_Z=pluck;',
        'force reference.u_audio.u_adc.pluck_valid=pluck;']
    (out/'p4_gate_acceleration.vh').write_text('\n'.join(force)+'\n', encoding='utf-8')
    record = json.loads((out/'mapping.json').read_text(encoding='utf-8'))
    record['posture_acceleration'] = dict(millisecond_q=ms, mpu_divider_q=divider,
        actual_sensor_instance=sensor_name, actual_bus_module=bus_kind,
        mpu_source_register_bytes=1, production_quarter_clocks=125,
        simulated_quarter_schedule='Coherent counter pattern 0,1,2,3,124 (terminal compare unchanged)',
        simulated_ms_schedule='Coherent counter pattern 0..498,49999 (terminal compare unchanged)',
        registered_adc_output='u_audio.u_adc.pluck_valid_Z[3:0]',
        scope='Counter waiting only; all production calibration/stability/health counts, I2C states, GPIO reads, classifier, policy, audio sample clocks and outputs remain actual full VG',
        force_header_sha256=hashlib.sha256((out/'p4_gate_acceleration.vh').read_bytes()).hexdigest())
    (out/'mapping.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print('PASS: P4 actual16 ms-counter Q +32 MPU-divider Q audited; registered ADC event only, no score/DDS/audio injection')


if __name__ == '__main__':
    main(Path(sys.argv[1]), Path(sys.argv[2]))
