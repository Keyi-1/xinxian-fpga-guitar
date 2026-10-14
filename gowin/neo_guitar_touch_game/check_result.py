"""Check current RTL evidence and, separately, routed implementation evidence."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

PROJECT = Path(__file__).resolve().parent
REPO = PROJECT.parent.parent
NAME = 'neo_guitar_touch_game'
BASELINE = '655458f32ba4f7e06403fd6c5c4da0b6f0dad8a7'
BENCHES = ['tb_i2c_fault_recovery', 'tb_gt911_touch', 'tb_touch_gesture_ui',
           'tb_game_note_controller', 'tb_game_cdc', 'tb_game_chart_renderer',
           'tb_game_audio_preservation', 'tb_game_miss_audio_cue', 'tb_game_competition_controls']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--rtl-only', action='store_true', help='does not approve a bitstream')
    args = parser.parse_args()
    directory = REPO/'sim/temp/touch_game'
    evidence = json.loads((directory/'verification.json').read_text(encoding='utf-8-sig'))
    assert evidence['result'] == 'PASS' and evidence['baseline_commit'] == BASELINE
    assert evidence['benches'] == BENCHES, 'run the complete touch/game bench suite'
    for path, expected in evidence['source_sha256'].items():
        assert digest(REPO/path) == expected, ('source/ROM changed after simulation', path)
    for bench in BENCHES:
        path = directory/f'{bench}.log'
        body = path.read_text(encoding='utf-8')
        assert 'PASS:' in body and not re.search(r'FAIL:|\*\* (Error|Fatal|Warning):', body), bench
        assert digest(path) == evidence['log_sha256'][bench], bench
    audio_log = (directory/'tb_game_audio_preservation.log').read_text()
    assert '2097153 cycles / 8192 samples identical to accepted master' in audio_log
    match = re.search(r'sustain exit (\d+) samples', audio_log)
    assert match and int(match[1]) <= 1920

    # The arithmetic changes are limited to the optional force-release hook.
    # All prior oscillator/filter coefficients, tone/effect/control/display
    # modules and production assets must still match the accepted source tree.
    paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASELINE], cwd=REPO).decode().splitlines()
    preserved = {}
    exceptions = {'rtl/synth/piano_voice_core.v', 'rtl/audio_io/four_voice_piano_audio_core.v',
                  'rtl/audio_io/four_string_board_audio_chain.v'}
    for relative in paths:
        if not (relative.startswith(('rtl/', 'mem/')) and relative.endswith(('.v', '.vh', '.mem', '.json'))):
            continue
        if relative in exceptions:
            continue
        original = subprocess.check_output(['git', 'show', f'{BASELINE}:{relative}'], cwd=REPO)
        current = (REPO/relative).read_bytes()
        assert current.replace(b'\r\n', b'\n') == original.replace(b'\r\n', b'\n'), relative
        preserved[relative] = digest(REPO/relative)
    cst = (REPO/f'constraints/{NAME}.cst').read_text()
    pins = dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+);', cst))
    old_cst = subprocess.check_output(['git', 'show', f'{BASELINE}:constraints/neo_guitar_i2s.cst'], cwd=REPO).decode()
    old_pins = dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+);', old_cst))
    assert len(pins) == len(set(pins.values())) == 59
    assert all(pins[key] == value for key, value in old_pins.items())
    assert {p: pins[p] for p in ['ctp_rst_n', 'ctp_int', 'ctp_sda', 'ctp_scl']} == dict(
        ctp_rst_n='T15', ctp_int='T16', ctp_sda='U16', ctp_scl='W16')
    result = dict(result='RTL_PASS', baseline_commit=BASELINE, benches=BENCHES,
                  audio_equivalence_samples=8192, forced_exit_samples=int(match[1]),
                  touch_connection=dict(connector='J6', native_six_pin=True,
                      fpga_pins={p: pins[p] for p in ['ctp_rst_n', 'ctp_int', 'ctp_sda', 'ctp_scl']},
                      voltage_confirmation='User confirmed J6-compatible IO voltage'),
                  source_sha256=evidence['source_sha256'], preserved_assets_sha256=preserved,
                  rtl_evidence_sha256=digest(directory/'verification.json'),
                  hardware_status='Original menus and preview tested by user; missing game guidance reproduced and fixed in gate simulation; this bugfix awaits hardware acceptance; native J6 INT=T16')
    if args.rtl_only:
        (PROJECT/'verification.json').write_text(json.dumps(result, indent=2)+'\n')
        print(f'RTL_PASS: {len(BENCHES)} benches; bitstream/routing/timing not approved by --rtl-only')
        return

    pnr = PROJECT/'impl/pnr'
    log = (pnr/f'{NAME}.log').read_text(encoding='utf-8')
    report = (pnr/f'{NAME}.rpt.txt').read_text(encoding='utf-8')
    timing = (pnr/f'{NAME}_tr_content.html').read_text(encoding='utf-8')
    assert 'Bitstream generation completed' in log and 'ERROR' not in log
    assert 'ERROR' not in report and 'GW5AT-LV60PG484AC1/I0' in report
    assert 'Device Version>: B' in report
    command = (pnr/'cmd.do').read_text()
    for option, value in [('place_option', '4'), ('route_option', '2'), ('clock_route_order', '1'), ('correct_hold', '1')]:
        assert re.search(rf'^-{option}\s+{value}\s*$', command, re.M), option
    device = (pnr/'device.cfg').read_text()
    for option in ['CPU', 'SSPI', 'I2C']:
        assert f'set {option} regular_io = true' in device, option
    ide = json.loads((PROJECT/f'impl/{NAME}_process_config.json').read_text())
    assert ide['TopModule'] == 'neo_guitar_touch_game_top'
    assert ide['OUTPUT_BASE_NAME'] == NAME
    assert (ide['Place_Option'], ide['Route_Option'], ide['Clock_Route_Order']) == ('4', '2', 1)
    assert ide['Correct_Hold_Violation'] is True
    resources = {}
    for label in ['Logic', 'Register', 'CLS', 'BSRAM', 'DSP']:
        m = re.search(rf'^\s+{label}\s+\|\s+([\d.]+)/([\d.]+)', report, re.M)
        assert m and float(m[1]) <= float(m[2]), label
        resources[label] = dict(used=float(m[1]), available=float(m[2]))
    assert resources['DSP']['used'] == 115.5, 'touch/game must not add DSP or simplify the accepted tone engine'
    clocks = {}
    for clock, required in [('audio_clk_12m288', 12.288), ('sys_clk_50m', 50.0)]:
        m = re.search(rf'<td>{clock}</td>\s*<td>([\d.]+)\(MHz\)</td>\s*<td>([\d.]+)\(MHz\)</td>', timing)
        assert m and float(m[2]) >= required, clock
        clocks[clock] = dict(required_mhz=required, fmax_mhz=float(m[2]))
    violations = {}
    for kind in ['Setup', 'Hold']:
        m = re.search(rf'Numbers of {kind} Violated Endpoints</td>\s*<td>(\d+)</td>', timing)
        assert m and int(m[1]) == 0, kind
        violations[kind.lower()] = int(m[1])
    rows = {}
    for line in report.splitlines():
        fields = [v.strip() for v in line.split('|')]
        if len(fields) > 8 and fields[0] in pins:
            rows[fields[0]] = fields
    for port, ball in pins.items():
        assert rows[port][2].split('/')[0] == ball and rows[port][3] == 'Y', port
        assert rows[port][7] == ('LVCMOS15' if port.startswith('USER_BUTTON') else 'LVCMOS33'), port
    fs = pnr/f'{NAME}.fs'
    assert fs.stat().st_size > 10000000
    gate_dir = REPO/'sim/temp/touch_game_gate'
    gate_evidence = json.loads((gate_dir/'verification.json').read_text(encoding='utf-8-sig'))
    assert gate_evidence['result'] == 'PASS'
    for path, expected in gate_evidence['source_sha256'].items():
        assert digest(REPO/path) == expected, ('source/ROM changed after gate simulation', path)
    netlist_hash = digest(PROJECT/f'impl/gwsynthesis/{NAME}.vg')
    assert netlist_hash == gate_evidence['netlist_sha256'] == digest(gate_dir/'compiled.vg')
    assert digest(gate_dir/'run.log') == gate_evidence['log_sha256']
    gate_log = (gate_dir/'run.log').read_text()
    assert 'PASS: synthesized menu LCD' in gate_log and 'FAIL:' not in gate_log
    assert digest(gate_dir/'chart_run.log') == gate_evidence['chart_log_sha256']
    assert digest(gate_dir/'tb_game_chart_gate.sv') == gate_evidence['chart_bench_sha256']
    chart_log = (gate_dir/'chart_run.log').read_text()
    assert 'PASS: synthesized chart' in chart_log and not re.search(r'FAIL:|\*\* (Error|Fatal)', chart_log)
    result.update(result='PASS', clocks=clocks, violations=violations, resources=resources,
                  bitstream_sha256=digest(fs),
                  netlist_sha256=netlist_hash,
                  gate_evidence_sha256=digest(gate_dir/'verification.json'),
                  implementation_evidence_sha256={p.name: digest(p) for p in [pnr/f'{NAME}.log',
                      pnr/f'{NAME}.rpt.txt', pnr/f'{NAME}_tr_content.html', pnr/'cmd.do']},
                  gate_simulation='Home-menu LCD/touch/silent audio plus full-score consecutive synthesized moving chart; musical/control behavior covered by RTL benches')
    (PROJECT/'verification.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k: result[k] for k in ['result', 'clocks', 'violations', 'resources', 'bitstream_sha256']}, indent=2))


if __name__ == '__main__':
    main()
