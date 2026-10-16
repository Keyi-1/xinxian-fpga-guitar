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
from datetime import datetime

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
    compile_log=directory/'compile.log'
    assert 'Errors: 0, Warnings: 0' in read(compile_log),compile_log
    assert not re.search(r'\*\* (Error|Fatal|Warning):',read(compile_log)),compile_log
    for name,field in [('compile.log','compile_log_sha256'),('python.log','python_log_sha256')]:
        if field in data:assert digest(directory/name)==data[field],directory/name
    return data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--build-dir', type=Path, required=True)
    parser.add_argument('--gate-dir', type=Path, required=True)
    parser.add_argument('--digital-only', action='store_true',
                        help='Audit completed RTL/gate hashes; print PNR_PENDING and never write a release certificate')
    parser.add_argument('--output', type=Path, default=PROJECT/'p2_integration_verification.json')
    args = parser.parse_args()
    manifest_path = args.build_dir/'source_manifest.json'
    manifest = json.loads(read(manifest_path))
    for path, value in manifest['source_sha256'].items():
        assert digest(ROOT/path) == value, ('changed since synthesis started', path)
    synthesis_origin=args.build_dir
    option_change=manifest.get('authorized_option_change')
    clock_change=manifest.get('authorized_clock_order_change')
    if 'synthesis_origin' in manifest:
        # A route-only retry must preserve the exact previously verified VG.
        # The only accepted source-manifest difference is the explicit user
        # authorization below; never relabel a changed RTL as an old synthesis.
        synthesis_origin=ROOT/manifest['synthesis_origin']
        origin_path=synthesis_origin/'source_manifest.json'
        assert digest(origin_path)==manifest['synthesis_origin_manifest_sha256']
        origin=json.loads(read(origin_path))
        assert origin['synthesized_netlist_sha256']==manifest.get('gate_netlist_sha256',manifest['synthesized_netlist_sha256'])
        assert origin['validated_source_commit']==manifest['validated_source_commit']
        assert option_change and option_change['key']=='Route_Maxfan'
        assert option_change['before']==23 and option_change['after']==32
        assert option_change['path']=='gowin/neo_guitar_touch_game/impl/neo_guitar_touch_game_process_config.json'
        assert option_change['user_authorization']=='2026-10-16 explicit reply: allow only Route_Maxfan and preserve all other user content'
        if clock_change:
            assert clock_change['path']==option_change['path']
            assert clock_change['key']=='Clock_Route_Order' and clock_change['before']==1 and clock_change['after']==0
            assert clock_change['before_sha256']==option_change['after_sha256']
            assert clock_change['user_authorization']=='2026-10-16 explicit reply: allow only Clock_Route_Order to 0'
            previous_path=ROOT/manifest['previous_route_attempt']/'source_manifest.json'
            assert digest(previous_path)==manifest['previous_route_manifest_sha256']
        for path,value in origin['source_sha256'].items():
            config_hash=clock_change['after_sha256'] if clock_change else option_change['after_sha256']
            expected=config_hash if path==option_change['path'] else value
            assert manifest['source_sha256'][path]==expected,path
        assert set(origin['source_sha256'])==set(manifest['source_sha256'])
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
    evidence(ROOT/'sim/temp/p2_button_compat', ['tb_guitar_effect_buttons','tb_guitar_effect_buttons_defaults'])
    evidence(ROOT/'sim/temp/game_p2/explicit_dpb_final', ['tb_game_p2_window', 'tb_game_p2_legacy_equivalence',
             'tb_game_p2_static_bank', 'tb_game_p2_judgement'], 'status')
    for path in ['sim/temp/touch_game/fingering.log','sim/temp/game_p2/explicit_dpb_final/python.log']:
        text=read(ROOT/path)
        assert 'Ran 5 tests' in text and re.search(r'^OK\s*$',text,re.M),path
    audio = read(ROOT/'sim/temp/p2_final_audio/tb_game_p2_audio_preservation.log')
    assert '2097153 cycles / 8192 samples identical to accepted master' in audio
    assert 'sustain exit 1452 samples' in audio
    display = read(ROOT/'sim/temp/p2_final_connection/tb_game_p2_display.log')
    assert '2636 complete P2 layouts' in display and 'max 445 clocks' in display
    from check_game_p2_font import check as check_font
    font_preservation=check_font()
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
    assert gate['netlist_sha256'] == digest(args.gate_dir/'compiled.vg')
    assert digest(vg)==manifest['synthesized_netlist_sha256'], 'netlist differs from the reviewed synthesis'
    graph_proof=None
    if digest(vg)!=gate['netlist_sha256']:
        from compare_synth_graph import compare
        proof_path=args.build_dir/'netlist_graph_equivalence.json'
        assert digest(proof_path)==manifest['netlist_graph_equivalence_sha256']
        graph_proof=json.loads(read(proof_path))
        assert graph_proof['checker_sha256']==digest(ROOT/'tools/compare_synth_graph.py')
        # Recompute exact connectivity/parameters from BOTH raw files. The old
        # logs alone do not certify a regenerated VG with a different hash.
        recomputed=compare(args.gate_dir/'compiled.vg',vg)
        assert all(graph_proof[k]==value for k,value in recomputed.items())
        assert graph_proof['before_sha256']==gate['netlist_sha256']==manifest['gate_netlist_sha256']
        assert graph_proof['after_sha256']==digest(vg)
        sensitivity=read(args.build_dir/'graph_checker_tests.log')
        assert 'Ran 6 tests' in sensitivity and re.search(r'^OK\s*$',sensitivity,re.M)
    syn = read(PROJECT/f'impl/gwsynthesis/{NAME}.log')
    assert 'GowinSynthesis finish' in syn
    assert not re.search(r'inferr?ed.*latch|latch.*inferr?ed', syn, re.I)
    netlist = read(vg)
    assert not re.search(r'^\s*(?:DLCE|DLPE)\s+\w+\s*\(', netlist, re.M)
    assert 'module game_p2_mode_router ' in netlist and 'module game_p2_window_controller ' in netlist
    if args.digital_only:
        print(json.dumps(dict(result='DIGITAL_PASS_PNR_PENDING',netlist_sha256=digest(vg),
            rtl_and_gate_hashes_verified=True,gate_pixels=1305600,gate_layouts=1865,
            release_certificate_written=False),indent=2))
        return
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
    for option, value in [('place_option', '4'), ('route_option', '2'),
                          ('clock_route_order', '0' if clock_change else '1'), ('correct_hold', '1')]:
        assert re.search(rf'^-{option}\s+{value}\s*$', command, re.M), option
    expected_fanout='32' if option_change else '23'
    assert re.search(rf'^-route_maxfan\s+{expected_fanout}\s*$',command,re.M)
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
        if option_change and path==option_change['path']:
            before=args.build_dir/'process_config.before.json'
            after=args.build_dir/'process_config.after.json'
            assert digest(before)==record['sha256']==option_change['before_sha256']
            raw=before.read_bytes()
            assert raw.count(b'"Route_Maxfan": 23')==1
            expected=raw.replace(b'"Route_Maxfan": 23',b'"Route_Maxfan": 32')
            final_hash=option_change['after_sha256']
            if clock_change:
                previous=args.build_dir/'previous_config_route32.json'
                assert previous.read_bytes()==expected
                assert digest(previous)==clock_change['before_sha256']
                assert expected.count(b'"Clock_Route_Order": 1')==1
                expected=expected.replace(b'"Clock_Route_Order": 1',b'"Clock_Route_Order": 0')
                final_hash=clock_change['after_sha256']
            assert digest(after)==digest(ROOT/path)==final_hash
            assert expected==after.read_bytes()
        else:
            assert digest(ROOT/path)==record['sha256'], ('protected user content changed',path)
        index=subprocess.check_output(['git','ls-files','-s','--',path],cwd=ROOT).decode().strip()
        assert index==record['index_line'], ('protected user index changed',path)
    fs = pnr/f'{NAME}.fs'
    assert fs.stat().st_size > 10000000
    process=json.loads(read(args.build_dir/'build_process.json'))
    route_started=datetime.fromisoformat(process['started']).timestamp()
    actual_syn=ROOT/manifest['actual_synthesis_run'] if 'actual_synthesis_run' in manifest else synthesis_origin
    syn_process=json.loads(read(actual_syn/'build_process.json'))
    syn_started=datetime.fromisoformat(syn_process['started']).timestamp()
    for path in [vg,PROJECT/f'impl/gwsynthesis/{NAME}.log',PROJECT/f'impl/gwsynthesis/{NAME}_syn_rsc.xml']:
        assert path.stat().st_mtime>=syn_started,('old synthesis artifact cannot certify this build',path)
    for path in [fs,pnr/f'{NAME}.log',pnr/f'{NAME}.rpt.txt',pnr/f'{NAME}_tr_content.html',pnr/'cmd.do']:
        assert path.stat().st_mtime>=route_started,('old routing artifact cannot certify this build',path)
    artifacts = [vg, fs, pnr/f'{NAME}.log', pnr/f'{NAME}.rpt.txt', pnr/f'{NAME}_tr_content.html',
                 pnr/'cmd.do', pnr/'device.cfg', PROJECT/f'impl/gwsynthesis/{NAME}.log',
                 PROJECT/f'impl/gwsynthesis/{NAME}_syn_rsc.xml', manifest_path,protected_path,
                 args.build_dir/'build_process.json']
    if option_change:
        artifacts.extend([args.build_dir/'process_config.before.json',args.build_dir/'process_config.after.json',
                          synthesis_origin/'source_manifest.json',synthesis_origin/'build_process.json',
                          synthesis_origin/'failed.json',synthesis_origin/'failed_pnr.log',
                          synthesis_origin/'failed_pnr.rpt.txt',synthesis_origin/'failed_pnr_cmd.do'])
    if graph_proof:
        artifacts.extend([args.build_dir/'netlist_graph_equivalence.json',
                          args.build_dir/'graph_checker_tests.log',args.build_dir/'netlist.diff.txt'])
    if clock_change:
        previous=ROOT/manifest['previous_route_attempt']
        artifacts.extend([args.build_dir/'previous_config_route32.json',previous/'source_manifest.json',
                          previous/'build_process.json',previous/'failed.json',previous/'failed_pnr.log',
                          previous/'failed_pnr.rpt.txt',previous/'failed_pnr_cmd.do'])
    result = dict(result='PASS', artifact_scope=dict(kind='original_gprj_integrated_p2',
                  project=str(PROJECT/f'{NAME}.gprj'), implementation=str(PROJECT/'impl')),
                  source_sha256=manifest['source_sha256'], preserved_assets_sha256=preserved,
                  validated_source_commit=manifest['validated_source_commit'],
                  authorized_option_change=option_change,
                  authorized_clock_order_change=clock_change,
                  actual_synthesis_run=str(actual_syn.relative_to(ROOT)).replace('\\','/'),
                  regenerated_netlist_graph_equivalence=graph_proof,
                  rtl_evidence_sha256={p:digest(ROOT/p) for p in [
                      'sim/temp/touch_game/verification.json','sim/temp/p2_final_connection/verification.json',
                      'sim/temp/p2_final_audio/verification.json','sim/temp/p2_button_compat/verification.json',
                      'sim/temp/game_p2/explicit_dpb_final/verification.json','sim/temp/p2_bank_gate_r1/verification.json']},
                  supplemental_evidence_sha256={p:digest(ROOT/p) for p in [
                      'sim/temp/touch_game/fingering.log','sim/temp/game_p2/explicit_dpb_final/python.log',
                      *[f'sim/temp/{name}/compile.log' for name in ['touch_game','p2_final_connection',
                          'p2_final_audio','p2_button_compat','game_p2/explicit_dpb_final']]]},
                  gate_evidence_sha256=digest(args.gate_dir/'verification.json'),
                  artifacts_sha256={str(p.relative_to(ROOT)).replace('\\', '/'): digest(p) for p in artifacts},
                  bitstream_sha256=digest(fs), netlist_sha256=digest(vg), resources=resources, clocks=clocks,
                  score_bank=dict(implementation='explicit 16-bit true dual-port DPB slices',blocks=int(score_banks[0].attrib['Bsram']),logical_records=2048,record_bits=96,unit_verification=bank_check),
                  violations=dict(setup=0, hold=0, latch=0, unrouted=0, score_deadline=0, layout_deadline=0),
                  audio_baseline='655458f32ba4f7e06403fd6c5c4da0b6f0dad8a7', audio_equivalent_samples=8192,
                  font_preservation=font_preservation,
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
        'tools/archive_game_p2_integration.py','tools/continue_game_p2_gate.ps1','tools/check_game_p2_font.py',
        'tools/compare_synth_graph.py','tools/test_compare_synth_graph.py']}
    args.output.write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k: result[k] for k in ['result', 'resources', 'clocks', 'bitstream_sha256', 'margin_targets_met']}, indent=2))


if __name__ == '__main__':
    main()
