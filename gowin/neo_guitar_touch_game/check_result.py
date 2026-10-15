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
    parser.add_argument('--implementation-dir', type=Path, default=PROJECT)
    parser.add_argument('--gate-dir', type=Path, default=REPO/'sim/temp/touch_game_gate')
    parser.add_argument('--p1', action='store_true', help='require frozen display equivalence and isolated build binding')
    parser.add_argument('--output', type=Path, default=PROJECT/'verification.json')
    args = parser.parse_args()
    implementation = args.implementation_dir.resolve()
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
    p1_evidence = None
    if args.p1:
        p1_dir = REPO/'sim/temp/display_game_p1'
        p1_evidence = json.loads((p1_dir/'verification.json').read_text(encoding='utf-8-sig'))
        assert p1_evidence['result'] == 'PASS'
        frozen_commit = 'efdcf24277ab560b527ef1b24ab4348f77c9ae61'
        assert p1_evidence['frozen_commit'] == frozen_commit
        assert p1_evidence['benches'] == ['tb_radial_palette_equivalence', 'tb_display_game_p1_integration']
        frozen = REPO/'sim/reference/display_game_p1/guitar_radial_palette_frozen.v'
        original = subprocess.check_output(['git', 'show', f'{frozen_commit}:rtl/display/guitar_radial_palette.v'], cwd=REPO)
        assert frozen.read_bytes().replace(b'\r\n', b'\n') == original.replace(
            b'module guitar_radial_palette(', b'module guitar_radial_palette_frozen(').replace(b'\r\n', b'\n')
        wrapper = REPO/'sim/reference/display_game_p1/frozen_guitar_touch_game_display.v'
        expected_wrapper = (REPO/'rtl/game/guitar_touch_game_display.v').read_text().replace(
            'module guitar_touch_game_display #', 'module frozen_guitar_touch_game_display #').replace(
            'guitar_radial_palette u_palette', 'guitar_radial_palette_frozen u_palette')
        assert wrapper.read_text() == expected_wrapper
        for path, expected in p1_evidence['source_sha256'].items():
            assert digest(REPO/path) == expected, ('P1 source/ROM changed', path)
        for bench in p1_evidence['benches']:
            path = p1_dir/f'{bench}.log'
            assert digest(path) == p1_evidence['log_sha256'][bench]
            body = path.read_text()
            assert 'PASS:' in body and not re.search(r'FAIL:|\*\* (Error|Fatal|Warning):', body)
        assert '1108992 pixels equal' in (p1_dir/'tb_radial_palette_equivalence.log').read_text()
        assert '1958400 active pixels / 15 frames' in (p1_dir/'tb_display_game_p1_integration.log').read_text()
        # Only the independently checked display arithmetic is exempted.
        # Audio and every other accepted RTL/asset retain the existing guard.
        exceptions.add('rtl/display/guitar_radial_palette.v')
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
                  ui_style='full_width_stage',matrix_mode=False,polyline_effect=False,
                  hardware_status='See hardware_acceptance.json for user feedback and installed-image verification limits; native J6 INT=T16')
    if args.rtl_only:
        args.output.write_text(json.dumps(result, indent=2)+'\n')
        print(f'RTL_PASS: {len(BENCHES)} benches; bitstream/routing/timing not approved by --rtl-only')
        return

    pnr = implementation/'impl/pnr'
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
    ide = json.loads((implementation/f'impl/{NAME}_process_config.json').read_text())
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
    gate_dir = args.gate_dir.resolve()
    gate_evidence = json.loads((gate_dir/'verification.json').read_text(encoding='utf-8-sig'))
    assert gate_evidence['result'] == 'PASS'
    for path, expected in gate_evidence['source_sha256'].items():
        assert digest(REPO/path) == expected, ('source/ROM changed after gate simulation', path)
    netlist_hash = digest(implementation/f'impl/gwsynthesis/{NAME}.vg')
    assert netlist_hash == gate_evidence['netlist_sha256'] == digest(gate_dir/'compiled.vg')
    assert digest(gate_dir/'run.log') == gate_evidence['log_sha256']
    gate_log = (gate_dir/'run.log').read_text()
    assert 'PASS: synthesized menu LCD' in gate_log and 'FAIL:' not in gate_log
    assert 'full-width stage' in gate_log
    if args.p1:
        assert gate_evidence['p1_frozen_palette'] is True
        assert 'PASS: synthesized P1 frozen display' in gate_log and '2741760 pixels' in gate_log
    else:
        assert '783360 pixels' in gate_log
    assert digest(gate_dir/'stage_force.vh') == gate_evidence['stage_forces_sha256']
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
                  gate_simulation='Six full-top home/countdown/full-width game/result frames, touch/silent audio plus full-score consecutive moving chart; musical/control behavior covered by RTL benches')
    if args.p1:
        run_dir = implementation.parents[2]
        manifest = json.loads((run_dir/'manifest.json').read_text(encoding='utf-8-sig'))
        for path, expected in manifest['source_sha256'].items():
            assert digest(REPO/path) == expected == digest(run_dir/'workspace'/path), path
        for name, expected in manifest['build_scripts_sha256'].items():
            assert digest(implementation/name) == expected, name
        for path, expected in manifest['protected_user_files_sha256'].items():
            assert digest(REPO/path) == expected, ('protected user file changed', path)
        synthesis = implementation/f'impl/gwsynthesis/{NAME}.log'
        assert not re.search(r'inferr?ed.*latch|latch.*inferr?ed', synthesis.read_text(), re.I)
        assert not re.search(r'\bPR0004\b|\b[1-9]\d*\s+(?:unrouted|unroute|unconnected)\b', log, re.I)
        result.update(p1_evidence_sha256=digest(REPO/'sim/temp/display_game_p1/verification.json'),
                      p1_equivalence=p1_evidence,
                      build_manifest_sha256=digest(run_dir/'manifest.json'),
                      synthesis_log_sha256=digest(synthesis),
                      gate_simulation='21 full-top frames against frozen palette: original six game frames plus dynamic spectrum, mid-pass targets, peak decay, curve fade and page switches; silent audio/GPIO; 364 consecutive synthesized chart updates',
                      violations=dict(violations, unrouted=0, latch=0, display_deadline=0),
                      artifact_scope=dict(kind='isolated_p1_build', implementation=str(implementation)),
                      margin_targets=dict(cls_percent=95, sys_mhz=55, audio_mhz=13.5),
                      margin_targets_met=(resources['CLS']['used']/resources['CLS']['available']<=.95 and
                          clocks['sys_clk_50m']['fmax_mhz']>=55 and clocks['audio_clk_12m288']['fmax_mhz']>=13.5))
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k: result[k] for k in ['result', 'clocks', 'violations', 'resources', 'bitstream_sha256']}, indent=2))


if __name__ == '__main__':
    main()
