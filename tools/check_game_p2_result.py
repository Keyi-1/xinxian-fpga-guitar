"""Certify an integrated P2 build from the original Gowin project, fail closed.

The P1 checker and its published records remain unchanged. Explicit P2 UI and
control exceptions require the dedicated regressions below; audio assets,
constraints, the P1 palette and all other existing RTL retain byte guards.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT/'gowin/neo_guitar_touch_game'
NAME = 'neo_guitar_touch_game'
P1 = '1b88992'
ALLOWED = {
    'rtl/control/guitar_effect_buttons.v', 'rtl/game/guitar_touch_game_audio.v',
    'rtl/game/guitar_touch_game_display.v', 'rtl/game/game_p2_score_bank.v', 'rtl/game/mode_command_cdc.v',
    'rtl/game/touch_game_ui.v', 'rtl/game/touch_game_renderer.v',
    'rtl/top/neo_guitar_touch_game_top.v', 'rtl/config/game_ui_messages.vh',
    'mem/game_font_16.mem', 'mem/game_message_index.mem',
}


def digest(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def read(p):
    return Path(p).read_text(encoding='utf-8-sig')


def evidence(directory, benches, status='result'):
    data = json.loads(read(directory/'verification.json'))
    assert data[status] == 'PASS', directory
    assert data['benches'] == benches, directory
    for path, value in data['source_sha256'].items():
        assert digest(ROOT/path) == value, ('changed since RTL verification', path)
    for bench in benches:
        p = directory/f'{bench}.log'
        assert digest(p) == data['log_sha256'][bench], p
        text = read(p)
        assert 'PASS:' in text and not re.search(r'FAIL:|\*\* (Error|Fatal|Warning):', text), p
    return data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-dir', type=Path, required=True)
    parser.add_argument('--gate-dir', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=PROJECT/'p2_integration_verification.json')
    args = parser.parse_args()
    manifest_path = args.build_dir/'source_manifest.json'
    manifest = json.loads(read(manifest_path))
    for path, value in manifest['source_sha256'].items():
        assert digest(ROOT/path) == value, ('changed since synthesis started', path)
    preserved = {}
    paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', P1], cwd=ROOT).decode().splitlines()
    for path in paths:
        if not (path.startswith(('rtl/', 'mem/', 'constraints/')) and path.endswith(('.v', '.vh', '.mem', '.sdc', '.cst'))):
            continue
        if path in ALLOWED:
            continue
        old = subprocess.check_output(['git', 'show', f'{P1}:{path}'], cwd=ROOT)
        current=(ROOT/path).read_bytes().replace(b'\r\n', b'\n')
        old=old.replace(b'\r\n', b'\n')
        if path in {'rtl/game/game_p2_static_engine.v','rtl/game/game_p2_window_controller.v'}:
            # Only stale standalone-prototype comments were updated here.
            # Every non-comment line must still equal the tested core commit.
            current=b'\n'.join(x for x in current.splitlines() if not x.lstrip().startswith(b'//'))
            old=b'\n'.join(x for x in old.splitlines() if not x.lstrip().startswith(b'//'))
        assert current == old, ('unapproved protected asset change', path)
        preserved[path] = digest(ROOT/path)
    legacy_benches = ['tb_i2c_fault_recovery', 'tb_gt911_touch', 'tb_touch_gesture_ui',
                      'tb_game_note_controller', 'tb_game_cdc', 'tb_game_chart_renderer',
                      'tb_game_audio_preservation', 'tb_game_miss_audio_cue', 'tb_game_competition_controls']
    evidence(ROOT/'sim/temp/touch_game', legacy_benches)
    evidence(ROOT/'sim/temp/p2_final_connection', ['tb_game_p2_connection', 'tb_game_p2_display'])
    evidence(ROOT/'sim/temp/p2_final_audio', ['tb_game_p2_audio_preservation'])
    evidence(ROOT/'sim/temp/game_p2/explicit_dpb_final', ['tb_game_p2_window', 'tb_game_p2_legacy_equivalence',
             'tb_game_p2_static_bank', 'tb_game_p2_judgement'], 'status')
    audio = read(ROOT/'sim/temp/p2_final_audio/tb_game_p2_audio_preservation.log')
    assert '2097153 cycles / 8192 samples identical to accepted master' in audio
    assert 'sustain exit 1452 samples' in audio
    display = read(ROOT/'sim/temp/p2_final_connection/tb_game_p2_display.log')
    assert '2636 complete P2 layouts' in display and 'max 445 clocks' in display
    gate = json.loads(read(args.gate_dir/'verification.json'))
    assert gate['result'] == 'PASS'
    assert set(gate['log_sha256'])=={'tb_game_p2_engine_gate.log','tb_game_p2_layout_gate.log','tb_game_p2_top_gate.log'}
    for path, value in gate['source_sha256'].items():
        assert digest(ROOT/path) == value, ('changed since gate verification', path)
    for name, value in gate['log_sha256'].items():
        p = args.gate_dir/name
        assert digest(p) == value
        text = read(p)
        assert 'PASS:' in text and not re.search(r'FAIL:|\*\* (Error|Fatal)', text), name
    assert '1305600 pixels' in read(args.gate_dir/'tb_game_p2_top_gate.log')
    assert '1865 consecutive layouts' in read(args.gate_dir/'tb_game_p2_layout_gate.log')
    assert 'four selected previews, actual three timbres' in read(args.gate_dir/'tb_game_p2_engine_gate.log')
    for name,value in gate['generated_sha256'].items():
        assert digest(args.gate_dir/name)==value, name
    if 'engine_origin_evidence_sha256' in gate:
        origin_path=args.gate_dir/'engine_origin.json'
        assert digest(origin_path)==gate['engine_origin_evidence_sha256']
        origin=json.loads(read(origin_path))
        assert origin['netlist_sha256']==gate['netlist_sha256']
        for path,value in origin['source_sha256'].items():
            assert gate['source_sha256'][path]==value==digest(ROOT/path),path
        assert 'Errors: 0, Warnings: 0' in read(args.gate_dir/'engine_origin.compile.log')
    if 'vendor_primitive_path' in gate:
        assert digest(Path(gate['vendor_primitive_path']))==gate['vendor_primitive_sha256']
    vg = PROJECT/f'impl/gwsynthesis/{NAME}.vg'
    assert digest(vg) == gate['netlist_sha256'] == digest(args.gate_dir/'compiled.vg')
    syn = read(PROJECT/f'impl/gwsynthesis/{NAME}.log')
    assert 'GowinSynthesis finish' in syn
    assert not re.search(r'inferr?ed.*latch|latch.*inferr?ed', syn, re.I)
    netlist = read(vg)
    assert not re.search(r'^\s*(?:DLCE|DLPE)\s+\w+\s*\(', netlist, re.M)
    assert 'module game_p2_mode_router ' in netlist and 'module game_p2_window_controller ' in netlist
    pnr = PROJECT/'impl/pnr'
    log = read(pnr/f'{NAME}.log')
    report = read(pnr/f'{NAME}.rpt.txt')
    timing = read(pnr/f'{NAME}_tr_content.html')
    assert 'Bitstream generation completed' in log and 'ERROR' not in log
    assert 'GW5AT-LV60PG484AC1/I0' in report and 'Device Version>: B' in report
    assert not re.search(r'\bPR0004\b|\b[1-9]\d*\s+(?:unrouted|unroute|unconnected)\b', log, re.I)
    resources = {}
    for name in ['Logic', 'Register', 'CLS', 'BSRAM', 'DSP']:
        m = re.search(rf'^\s+{name}\s+\|\s+([\d.]+)/([\d.]+)', report, re.M)
        assert m and float(m[1]) <= float(m[2]), name
        resources[name] = dict(used=float(m[1]), available=float(m[2]))
    assert resources['DSP']['used'] == 115.5
    # Check actual ROM mapping, not just a source declaration of a RAM.
    import xml.etree.ElementTree as ET
    synthesis_resources=ET.fromstring(read(PROJECT/f'impl/gwsynthesis/{NAME}_syn_rsc.xml'))
    score_banks=[n for n in synthesis_resources.iter('SubModule') if n.attrib.get('name')=='bank' and n.attrib.get('Bsram') in {'10','12'}]
    assert len(score_banks)==1, 'inspect explicit DPB score bank mapping (unused group slice may be swept)'
    bank_dir=ROOT/'sim/temp/p2_bank_gate_r1'
    bank_check=json.loads(read(bank_dir/'verification.json'))
    assert bank_check['result']=='PASS' and bank_check['reads']==4096
    for path,value in bank_check['source_sha256'].items():assert digest(ROOT/path)==value,path
    assert digest(bank_dir/'compiled.vg')==bank_check['netlist_sha256']
    assert digest(bank_dir/'run.log')==bank_check['log_sha256']
    assert '4096 exact reads' in read(bank_dir/'run.log')
    from generate_game_p2_bsram import build as pack_bsram
    assert (ROOT/'rtl/config/game_p2_bsram_init.vh').read_bytes()==pack_bsram()
    clocks = {}
    for clock, required in [('audio_clk_12m288', 12.288), ('sys_clk_50m', 50.0)]:
        m = re.search(rf'<td>{clock}</td>\s*<td>([\d.]+)\(MHz\)</td>\s*<td>([\d.]+)\(MHz\)</td>', timing)
        assert m and float(m[2]) >= required, clock
        clocks[clock] = dict(required_mhz=required, fmax_mhz=float(m[2]))
    for kind in ['Setup', 'Hold']:
        m = re.search(rf'Numbers of {kind} Violated Endpoints</td>\s*<td>(\d+)</td>', timing)
        assert m and int(m[1]) == 0, kind
    command = read(pnr/'cmd.do')
    design = re.search(r'^-d\s+(.+)$', command, re.M)
    assert design and Path(design[1].strip()).resolve() == vg.resolve()
    for option, value in [('place_option', '4'), ('route_option', '2'), ('clock_route_order', '1'), ('correct_hold', '1')]:
        assert re.search(rf'^-{option}\s+{value}\s*$', command, re.M), option
    pins=dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+);',read(ROOT/f'constraints/{NAME}.cst')))
    assert len(pins)==len(set(pins.values()))==59
    rows={}
    for line in report.splitlines():
        fields=[v.strip() for v in line.split('|')]
        if len(fields)>8 and fields[0] in pins:rows[fields[0]]=fields
    for port,ball in pins.items():
        assert rows[port][2].split('/')[0]==ball and rows[port][3]=='Y', port
        assert rows[port][7]==('LVCMOS15' if port.startswith('USER_BUTTON') else 'LVCMOS33'), port
    protected_path=args.build_dir.parent/'protected_user_files.json'
    protected=json.loads(read(protected_path))
    for path,record in protected.items():
        assert digest(ROOT/path)==record['sha256'], ('protected user content changed',path)
        index=subprocess.check_output(['git','ls-files','-s','--',path],cwd=ROOT).decode().strip()
        assert index==record['index_line'], ('protected user index changed',path)
    fs = pnr/f'{NAME}.fs'
    assert fs.stat().st_size > 10000000
    artifacts = [vg, fs, pnr/f'{NAME}.log', pnr/f'{NAME}.rpt.txt', pnr/f'{NAME}_tr_content.html',
                 pnr/'cmd.do', pnr/'device.cfg', PROJECT/f'impl/gwsynthesis/{NAME}.log',
                 PROJECT/f'impl/gwsynthesis/{NAME}_syn_rsc.xml', manifest_path,protected_path]
    result = dict(result='PASS', artifact_scope=dict(kind='original_gprj_integrated_p2',
                  project=str(PROJECT/f'{NAME}.gprj'), implementation=str(PROJECT/'impl')),
                  source_sha256=manifest['source_sha256'], preserved_assets_sha256=preserved,
                  artifacts_sha256={str(p.relative_to(ROOT)).replace('\\', '/'): digest(p) for p in artifacts},
                  bitstream_sha256=digest(fs), netlist_sha256=digest(vg), resources=resources, clocks=clocks,
                  score_bank=dict(implementation='explicit 16-bit true dual-port DPB slices',blocks=int(score_banks[0].attrib['Bsram']),logical_records=2048,record_bits=96,unit_verification=bank_check),
                  violations=dict(setup=0, hold=0, latch=0, unrouted=0, score_deadline=0, layout_deadline=0),
                  audio_baseline='655458f32ba4f7e06403fd6c5c4da0b6f0dad8a7', audio_equivalent_samples=8192,
                  sustain_exit_samples=1452, display_layout_passes=2636, max_layout_clocks=445,
                  gate=gate, prior_p1_resources=dict(Logic=50159,Register=22405,CLS=27943,BSRAM=95,DSP=115.5),
                  prior_p1_fmax_mhz=dict(sys=58.765,audio=14.442),
                  hardware_status='P1 user confirmed; integrated P2 awaits new on-board confirmation',
                  content_scope='Four static practice slots; Qing Ge four-bar intro harmony and Seven Nation Army riff loops, not complete songs',
                  training_defaults=dict(ALLOW_AUTOPLAY_PREVIEW=1,ENABLE_MISS_CUE=1),
                  margin_targets_met=resources['CLS']['used']/29952<=.95 and clocks['sys_clk_50m']['fmax_mhz']>=55 and clocks['audio_clk_12m288']['fmax_mhz']>=13.5)
    result['verification_tools_sha256'] = {p: digest(ROOT/p) for p in [
        'tools/check_game_p2_result.py', 'tools/run_game_p2_gate.ps1', 'tools/generate_game_p2_gate_bench.py',
        'tools/run_touch_game_checks.ps1', 'tools/run_game_p2_checks.ps1','tools/generate_game_p2_bsram.py',
        'tools/archive_game_p2_integration.py','tools/continue_game_p2_gate.ps1']}
    args.output.write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k: result[k] for k in ['result', 'resources', 'clocks', 'bitstream_sha256', 'margin_targets_met']}, indent=2))


if __name__ == '__main__':
    main()
