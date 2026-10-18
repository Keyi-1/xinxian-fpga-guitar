"""Bind P4 rhythm/posture/centred UI proofs to the fresh original-project build.

Historical P3/P1 checkers and certificates are not weakened or overwritten.
A previous run may be reused only through the explicitly sealed renderer edit;
the current voice replay includes all ROM hashes.
"""
from pathlib import Path
from datetime import datetime
import argparse
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parent.parent
PROJECT=ROOT/'gowin/neo_guitar_touch_game'
NAME='neo_guitar_touch_game'
BASE='7837a24837de29454f0da28f413bdd48abd5a592'
RUNTIME='be885621daae47e73bbe6956256db95eb884b0d5'
RUN=ROOT/'build/p4_posture/impl_a2_centered'
VENDOR=re.compile(r'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)')
RENDERER='rtl/game/touch_game_renderer.v'


def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path):return Path(path).read_text(encoding='utf-8-sig')
def load(path):return json.loads(read(path))
def rel(path):return Path(path).relative_to(ROOT).as_posix()
def normalized(path):return read(path).replace('\r\n','\n')
def old(commit,path):return subprocess.check_output(['git','show',f'{commit}:{path}'],cwd=ROOT).replace(b'\r\n',b'\n').decode('utf-8')
def current_hashes(values):
    for path,value in values.items():assert digest(ROOT/path)==value,('source changed',path)


def sealed_edits(name):
    spec=load(ROOT/'sim/reference/posture'/name)
    for path,data in spec['files'].items():
        before=old(spec['base_commit'],path)
        assert hashlib.sha256(before.encode()).hexdigest()==data['base_normalized_sha256']
        lines=before.splitlines(keepends=True)
        for edit in reversed(data['changes']):
            assert ''.join(lines[edit['start']:edit['end']])==edit['before']
            lines[edit['start']:edit['end']]=edit['after'].splitlines(keepends=True)
        expected=''.join(lines)
        assert expected==normalized(ROOT/path),('unreviewed finite edit',path)
        assert hashlib.sha256(expected.encode()).hexdigest()==data['candidate_normalized_sha256']
    return spec


def source_guard():
    manifest={k.replace('\\','/'):v for k,v in load(RUN/'source_manifest.json').items()}
    current_hashes(manifest)
    # Every runtime byte has a saved build snapshot and an explicit reviewed commit.
    for path,value in manifest.items():
        assert digest(RUN/'source_archive'/path)==value,path
        assert normalized(ROOT/path)==old(RUNTIME,path),('runtime differs from reviewed implementation',path)
    sealed_edits('audio_observation_edit_spec.json')
    sealed_edits('renderer_centering_edit_spec.json')
    # Audio except the three observation-only interfaces must exactly equal P3.
    observations={'rtl/audio_io/four_string_board_audio_chain.v','rtl/control/guitar_effect_buttons.v','rtl/game/guitar_touch_game_audio.v'}
    audio_dirs=('rtl/synth/','rtl/audio_io/','rtl/control/')
    additions={'rtl/control/posture_timbre_policy.v','rtl/control/posture_touch_controls.v'}
    for path in manifest:
        if path.startswith(audio_dirs) and path not in observations|additions:
            assert normalized(ROOT/path)==old(BASE,path),('protected audio',path)
        if path.startswith('mem/') and path not in {'mem/game_p2_static.mem','mem/game_p3_initial.mem'}:
            assert normalized(ROOT/path)==old(BASE,path),('protected ROM',path)
    assert normalized(ROOT/f'constraints/{NAME}.sdc')==old(BASE,f'constraints/{NAME}.sdc')
    cst=normalized(ROOT/f'constraints/{NAME}.cst');before=old(BASE,f'constraints/{NAME}.cst')
    assert cst.startswith(before)
    extra=cst[len(before):]
    assert dict(re.findall(r'IO_LOC "([^"]+)" (\w+);',extra))=={'imu_scl':'Y21','imu_sda':'Y22'}
    assert len(re.findall(r'^IO_PORT ',extra,re.M))==2
    assert all('IO_TYPE=LVCMOS33 PULL_MODE=UP' in line for line in extra.splitlines() if line.startswith('IO_PORT '))
    a=ET.fromstring(old(BASE,f'gowin/{NAME}/{NAME}.gprj'));b=ET.parse(PROJECT/f'{NAME}.gprj').getroot()
    for key in ['Device','Template','Version']:
        assert a.find(key).text==b.find(key).text and a.find(key).attrib==b.find(key).attrib
    prev={tuple(sorted(n.attrib.items())) for n in a.find('FileList')}
    now={tuple(sorted(n.attrib.items())) for n in b.find('FileList')}
    assert prev<=now and len(now-prev)==7
    for path,data in load(RUN/'protected_user_files.json').items():
        assert digest(ROOT/path)==data['sha256'],('protected bytes',path)
        index=subprocess.check_output(['git','ls-files','--stage','--',path],cwd=ROOT,text=True).strip()
        assert index==data['index'],('protected index',path)
    from generate_game_p3_bsram import writable,initial_bank
    from generate_game_p2_bsram import build as p2build
    assert (ROOT/'rtl/config/game_p3_bsram_init.vh').read_bytes()==writable()
    assert (ROOT/'mem/game_p3_initial.mem').read_bytes()==initial_bank()[1]
    assert (ROOT/'rtl/config/game_p2_bsram_init.vh').read_bytes()==p2build()
    approval=load(ROOT/'scores/p2/review/qing_ge_rhythm_10_18_v1.json')
    assert approval['status']=='USER_CONFIRMED_FOR_PRODUCTION'
    assert digest(ROOT/'build/releases/touch_game/neo_guitar_touch_game_p3_uart_import.fs')=='57f0860227ba6b4c0010bebbaca829dfeea4799289ff3f47f8bf3e328afca4e1'
    return manifest


def check_log(path,value,gate=False):
    assert digest(path)==value,('log hash',path)
    body=read(path)
    assert 'PASS:' in body and not re.search(r'FAIL:|\*\* (Error|Fatal):',body),path
    for line in body.splitlines():
        if '** Warning:' in line:assert gate and VENDOR.search(line),(path,line)


def evidence():
    proof={};reuse=[]
    render_before=load(ROOT/'build/p4_posture/impl_a1/source_manifest.json')
    render_hash=render_before.get(RENDERER.replace('/','\\'),render_before.get(RENDERER))
    for name in ['p4_final_rtl_01','p4_twenty_01','p4_p3_rtl_01','p4_centered_display_01',
                 'p4_a2_full_gate_01','p4_a2_posture_gate_01','p4_a2_gain_gate_01','p4_a2_mode_gate_01',
                 'p4_audio_dependency_closure_01']:
        folder=ROOT/'sim/temp'/name;receipt=folder/'verification.json';data=load(receipt)
        assert data.get('result',data.get('status'))=='PASS',name
        drift=[]
        for path,value in data['source_sha256'].items():
            path=path.replace('\\','/')
            if digest(ROOT/path)!=value:
                if path==RENDERER and name in ['p4_final_rtl_01','p4_twenty_01','p4_p3_rtl_01']:
                    assert value==render_hash
                    assert digest(ROOT/'build/p4_posture/impl_a1/source_archive'/path)==value
                    drift.append(path)
                elif path=='sim/tb/tb_posture_display_equivalence.sv' and name=='p4_final_rtl_01':
                    # Superseded pixel bench is excluded, not presented as new pixel evidence.
                    assert value==hashlib.sha256(subprocess.check_output(['git','show',f'2e0a2b9:{path}'])).hexdigest() or normalized(ROOT/'sim/temp/p4_final_rtl_01/sources'/Path(path).name)==old('2e0a2b9',path)
                else:raise AssertionError(('unverified source drift',name,path))
        if drift:reuse.append(dict(run=name,sealed_exception=RENDERER,
            scope='Only centred enabled-IMU text/rectangle differs; new 12-scene pixel proof supersedes old display proof. Functional audio/input/CDC/game tests retain exact other sources. Disabled-IMU legacy renderer elaboration is unchanged.'))
        gate='netlist_sha256' in data
        logs=data['log_sha256']
        if gate:
            assert data['netlist_sha256']==digest(PROJECT/'impl/gwsynthesis'/f'{NAME}.vg')
            assert digest(folder/'mapping.json')==data['mapping_sha256']
            mapping=load(folder/'mapping.json')
            assert mapping['result']=='PASS' and mapping['bank_dpb16']==10 and mapping['initial_rows']==2048
            assert mapping['gain_rom_entries']==128 and mapping['mode_state_sdpb_per_voice']==1
            assert mapping['netlist_sha256']==data['netlist_sha256']
            if 'posture_gate' in name:
                accel=mapping['posture_acceleration']
                assert len(accel['millisecond_q'])==16 and len(accel['mpu_divider_q'])==32
                assert digest(folder/'p4_gate_acceleration.vh')==accel['force_header_sha256']
            bench={'p4_a2_full_gate_01':'tb_game_p3_full_gate','p4_a2_posture_gate_01':'tb_posture_full_gate',
                   'p4_a2_gain_gate_01':'tb_game_p3_rock_gain_gate','p4_a2_mode_gate_01':'tb_game_p3_mode_state_gate'}[name]
            logs={bench:logs}
        for bench,value in logs.items():
            if name=='p4_final_rtl_01' and bench=='tb_posture_display_equivalence':continue
            path=folder/(bench+'.log');check_log(path,value,gate);proof[rel(path)]=value
        proof[rel(receipt)]=digest(receipt)
        for path in folder.glob('*'):
            if path.is_file() and path.suffix in ['.json','.sv','.vh','.log']:
                proof[rel(path)]=digest(path)
    # The historical45210-sample run omitted per-run audio ROM hashes.
    # A focused current replay (not the full regression/build) binds the entire
    # unchanged voice/reference/RAM/coeff/ROM closure without an evidence gap.
    closed=load(ROOT/'sim/temp/p4_audio_dependency_closure_01/verification.json')
    assets={p.replace('\\','/'):v for p,v in closed['source_sha256'].items() if p.replace('\\','/').startswith('mem/')}
    assert all('mem/'+name+'.mem' in assets for name in ['sine_lut','piano_ratio','piano_phase','piano_envelope','harmonic_decay_rock','rock_envelope'])
    pc=ROOT/'build/p4_posture/pc_checks_a1/verification.json';data=load(pc)
    assert data['result']=='PASS';current_hashes(data['source_sha256']);current_hashes(data['log_sha256'])
    proof[rel(pc)]=digest(pc);proof.update(data['log_sha256'])
    audit=RUN/'bank_write_audit.json';data=load(audit)
    assert data['result']=='PASS' and data['boolean_cases']==384 and data['pages']==2
    assert data['netlist_sha256']==digest(PROJECT/'impl/gwsynthesis'/f'{NAME}.vg')
    assert data['tool_sha256']==digest(ROOT/'tools/audit_posture_bank.py')
    proof[rel(audit)]=digest(audit)
    return proof,reuse


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--preflight',action='store_true');args=parser.parse_args()
    manifest=source_guard();proof,reuse=evidence()
    if args.preflight:
        print('PASS: P4 exact source/protected files/finite audio edits/rhythm, current RTL/PC/pixels/full actual VG/physical memory proofs; P&R not yet certified');return
    pnr = PROJECT/'impl/pnr'
    log = read(pnr/f'{NAME}.log')
    report = read(pnr/f'{NAME}.rpt.txt')
    timing = read(pnr/f'{NAME}_tr_content.html')
    stdout = read(RUN/'build.stdout.log')
    assert 'Bitstream generation completed' in log and 'ERROR' not in log
    assert 'PNR_TCL_FINISHED' in stdout and not read(RUN/'build.stderr.log').strip()
    assert not re.search(r'\bPR0004\b|\b[1-9]\d*\s+(?:unrouted|unroute|unconnected)\b', log, re.I)
    assert 'GW5AT-LV60PG484AC1/I0' in report and 'Device Version>: B' in report
    syn = PROJECT/'impl/gwsynthesis'/f'{NAME}.log'
    assert not re.search(r'inferr?ed.*latch|latch.*inferr?ed', read(syn), re.I)
    resources = {}
    for name in ['Logic', 'Register', 'CLS', 'BSRAM', 'DSP']:
        hit = re.search(rf'^\s+{name}\s+\|\s+([\d.]+)/([\d.]+)', report, re.M)
        assert hit and float(hit[1]) <= float(hit[2]), name
        resources[name] = dict(used=float(hit[1]), available=float(hit[2]))
    assert resources['DSP']['used'] == 115.5
    tree = ET.parse(PROJECT/'impl/gwsynthesis'/f'{NAME}_syn_rsc.xml')
    assert len([n for n in tree.iter('SubModule') if n.attrib.get('name') == 'runtime_bank.bank' and n.attrib.get('Bsram') == '10']) == 1
    assert len([n for n in tree.iter('SubModule') if n.attrib.get('name')=='mode_state' and n.attrib.get('Bsram')=='1'])==4
    clocks = {}
    for name, required in [('audio_clk_12m288', 12.288), ('sys_clk_50m', 50.0)]:
        hit = re.search(rf'<td>{name}</td>\s*<td>([\d.]+)\(MHz\)</td>\s*<td>([\d.]+)\(MHz\)</td>', timing)
        assert hit and float(hit[1]) == required and float(hit[2]) >= required, name
        clocks[name] = dict(required_mhz=required, fmax_mhz=float(hit[2]))
    for kind in ['Setup', 'Hold']:
        hit = re.search(rf'Numbers of {kind} Violated Endpoints</td>\s*<td>(\d+)</td>', timing)
        assert hit and int(hit[1]) == 0, kind
    cmd = read(pnr/'cmd.do')
    hit = re.search(r'^-d\s+(.+)$', cmd, re.M)
    vg = PROJECT/'impl/gwsynthesis'/f'{NAME}.vg'
    assert hit and Path(hit[1].strip()).resolve() == vg.resolve()
    assert digest(vg) == load(RUN/'synthesis_review.json')['netlist_sha256']
    for key, value in [('place_option', 4), ('route_option', 2), ('route_maxfan', 32), ('clock_route_order', 0), ('correct_hold', 1)]:
        assert re.search(rf'^-{key}\s+{value}\s*$', cmd, re.M), key
    pins = dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+);', read(ROOT/f'constraints/{NAME}.cst')))
    assert len(pins) == len(set(pins.values())) == 63
    rows = {}
    for line in report.splitlines():
        fields = [v.strip() for v in line.split('|')]
        if len(fields) > 8 and fields[0] in pins:
            rows[fields[0]] = fields
    for port, ball in pins.items():
        assert rows[port][2].split('/')[0] == ball and rows[port][3] == 'Y'
        assert rows[port][7] == ('LVCMOS15' if port.startswith('USER_BUTTON') else 'LVCMOS33')
    fs = pnr/f'{NAME}.fs'
    assert fs.stat().st_size > 10000000
    started = datetime.fromisoformat(load(RUN/'process.json')['started']).timestamp()
    artifacts = [vg, fs, syn, PROJECT/'impl/gwsynthesis'/f'{NAME}_syn_rsc.xml',
        pnr/f'{NAME}.log', pnr/f'{NAME}.rpt.txt', pnr/f'{NAME}_tr_content.html', pnr/'cmd.do']
    for path in artifacts:
        assert path.stat().st_mtime >= started, ('stale implementation artifact', path)
    artifacts += [RUN/p for p in ['process.json', 'source_manifest.json', 'protected_user_files.json',
        'synthesis_review.json', 'build.tcl', 'build.stdout.log', 'build.stderr.log']]
    config_snapshot = RUN/'protected_process_config.snapshot.json'
    assert digest(config_snapshot) == load(RUN/'protected_user_files.json')['gowin/neo_guitar_touch_game/impl/neo_guitar_touch_game_process_config.json']['sha256']
    artifacts.append(config_snapshot)
    # Confirm every new posture subtree uses no DSP primitives, and the full
    # design retains the existing115.5 physical DSP budget.
    for node in tree.iter('SubModule'):
        if node.attrib.get('name','').startswith('posture.'):
            assert not any('MULT' in k for k in node.attrib),node.attrib
    prior_path=PROJECT/'p3_import_verification.json';prior=load(prior_path)
    assert prior['bitstream_sha256']=='57f0860227ba6b4c0010bebbaca829dfeea4799289ff3f47f8bf3e328afca4e1'
    artifacts.append(prior_path)
    artifacts += [ROOT/'build/p4_posture/impl_a1/source_manifest.json',
                  ROOT/'build/p4_posture/impl_a1/source_archive'/RENDERER]
    tools=[Path(__file__)]+[ROOT/'tools'/n for n in ['archive_posture.py','audit_posture_bank.py',
        'prepare_posture_gate.py','run_posture_gate.ps1','start_original_posture_build.ps1',
        'run_posture_checks.ps1','continue_posture_regression.ps1','run_posture_pc_checks.py',
        'prepare_game_p3_gate.py','compare_synth_graph.py']]
    tools+=list((ROOT/'sim/reference/posture').glob('*.json'))
    # Include source inputs and the approved software preview without treating
    # them as an FPGA waveform/acoustic acceptance.
    artifacts+=list((ROOT/'scores/p2').rglob('*.json'))+list((ROOT/'scores/p2').glob('*.bin'))
    artifacts+=list((ROOT/'scores/p2').glob('*.csv'))
    example=ROOT/'build/p4_posture/upload_example'
    from upload_game_score import load_score
    events,duration,timbre=load_score(example/'qing_ge.bin',example/'qing_ge.json')
    assert len(events)==212 and duration==7296000 and timbre==1
    assert (example/'qing_ge.bin').read_bytes()==(ROOT/'scores/p2/qing_ge_melody.bin').read_bytes()
    assert load(example/'qing_ge.json')['source_csv_sha256']==digest(ROOT/'scores/p2/qing_ge_melody.csv')
    artifacts+=list(example.glob('*'))
    artifacts+=list((ROOT/'build/p4_posture/rtl_previews_centered').glob('*.png'))
    for path in (ROOT/'build/qing_ge_rhythm_review/preview_v1').glob('*'):
        if path.is_file() and path.suffix in ['.wav','.json']:artifacts.append(path)
    posture_log=read(ROOT/'sim/temp/p4_a2_posture_gate_01/tb_posture_full_gate.log')
    posture_counts=re.search(r'(\d+) audio samples (\d+) LCD clock samples (\d+) MPU bursts (\d+) tone changes',posture_log)
    assert posture_counts
    import_log=read(ROOT/'sim/temp/p4_a2_full_gate_01/tb_game_p3_full_gate.log')
    import_counts=re.search(r'(\d+) audio samples and (\d+) LCD clock samples across (\d+) frames',import_log)
    assert import_counts
    process=load(RUN/'process.json')
    process.update(status='COMPLETE_VERIFICATION_PASS',verified_at=datetime.now().astimezone().isoformat())
    (RUN/'process.json').write_text(json.dumps(process,indent=2)+'\n',encoding='utf-8')
    record=dict(result='PASS',artifact_scope=dict(kind='original_gprj_p4_posture_confirmed_rhythm_centred_ui',
        project=rel(PROJECT/f'{NAME}.gprj'),implementation=rel(PROJECT/'impl')),
        previous_release_commit=BASE,validated_source_commit=RUNTIME,
        source_sha256=manifest,artifacts_sha256={rel(p):digest(p) for p in artifacts},
        evidence_sha256=proof,verification_tools_sha256={rel(p):digest(p) for p in tools},
        explicit_evidence_reuse=reuse,
        resources=resources,clocks=clocks,previous_release_resources=prior['resources'],previous_release_clocks=prior['clocks'],
        margin_targets_met=(resources['CLS']['used']/resources['CLS']['available']<=.95 and clocks['sys_clk_50m']['fmax_mhz']>=55 and clocks['audio_clk_12m288']['fmax_mhz']>=13.5),
        bitstream_sha256=digest(fs),netlist_sha256=digest(vg),
        violations=dict(setup=0,hold=0,latch=0,unrouted=0,tested_audio_deadline=0,tested_score_deadline=0,tested_layout_deadline=0,tested_posture_math_deadline=0),
        source_guard=dict(audio='P3-identical except three sealed observation/guard interfaces; no sample equations/parameters/FX changes',
            runtime='Every runtime source and ROM matches reviewed commit and build snapshot; SDC unchanged; only Y21/Y22 added; user-file bytes/index unchanged',
            display='IMU labels/status only; visible characters centred, new right status background, same four pipeline stages and six clocks/pixel'),
        regression=dict(legacy_rtl_benches=20,p3_rtl_benches=4,posture_component_top_benches=8,posture_pixel_scenes=12,
            frozen_p3_pixels=1566720,python_tests=33,frozen_audio_samples=8192,frozen_audio_reference_clocks=2097153,
            unchanged_voice_component_samples=45210,actual_vg_benches=4,bank_boolean_cases=384,
            actual_posture_gate=dict(audio_samples=int(posture_counts[1]),lcd_system_clock_samples=int(posture_counts[2]),
                mpu_bursts=int(posture_counts[3]),tone_changes=int(posture_counts[4])),
            actual_uart_gate=dict(audio_samples=int(import_counts[1]),lcd_clock_samples=int(import_counts[2]),frames=int(import_counts[3]))),
        rhythm=dict(bars=[10,18],beat_grid='1_11|(1)5_3|(3)___|345',user_listening_approved=True,
            exact_changed_events=4,all_original_lanes_preserved=True,total_attacks=212,total_seconds=152,bpm=60,recommended_timbre=1),
        posture=dict(default='manual',mpu_address='0x68',scl='J8-11/Y21',sda='J8-12/Y22',calibration_packets=256,
            sample_rate_hz=100,stable_ms=500,cooldown_ms=1000,recovery_ms=1000,math_max_tested_clocks=352,math_budget_clocks=1000,
            automatic_targets={'flat':'piano','guitar':'bright strings','upright':'unavailable, retain tone'},
            policy='Performance mode only, wait all old voices/queued note/pipeline idle, manual priority and cancellation; same pose/recovery preserve manual tone'),
        training_defaults=dict(ALLOW_AUTOPLAY_PREVIEW=1,ENABLE_MISS_CUE=1),
        hardware_status='P4 not board-tested. P3 general positive user feedback and software rhythm approval are separate. No COM opened, flashing or new physical measurements by agent.',
        excluded_validation=['Actual MPU supply/pull-up levels and mounting axes','Physical orientation/motion thresholds','Actual new rhythm listening on board','USB/UART physical endurance','Quantitative acoustics/long-duration stability','Bluetooth/Flash/PIPA/old-tail mixed-timbre isolation'],
        generated_at=datetime.now().astimezone().isoformat())
    output=PROJECT/'p4_posture_verification.json'
    output.write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:record[k] for k in ['result','resources','clocks','bitstream_sha256','margin_targets_met']},indent=2))


if __name__=='__main__':main()
