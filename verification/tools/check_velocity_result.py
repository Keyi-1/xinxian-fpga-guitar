"""Certify the calibrated-velocity continuation; retain all old P4 evidence."""
from pathlib import Path
from datetime import datetime
import argparse
import csv
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parent.parent
PROJECT=ROOT/'gowin/neo_guitar_touch_game';NAME='neo_guitar_touch_game'
BASE='1bbab98c4231c4791226ea309e18667b3f5e449e'
RUNTIME='e5680ef3510581f6a4ed487f90656495fddb1a45'
RUN=ROOT/'build/velocity_calibration/synth_v1'
SAVED=ROOT/'build/releases/touch_game/p4_posture_20261018'
ALLOWED={'rtl/config/guitar_config.vh','rtl/input/four_string_pluck_detector.v','rtl/input/mcp3208_pluck_frontend.v','rtl/game/guitar_touch_game_audio.v','rtl/top/guitar_audio_top.v'}
VENDOR=re.compile(r'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)')


def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path):return Path(path).read_text(encoding='utf-8-sig')
def load(path):return json.loads(read(path))
def rel(path):return Path(path).relative_to(ROOT).as_posix()
def old(commit,path):return subprocess.check_output(['git','show',f'{commit}:{path}'],cwd=ROOT).replace(b'\r\n',b'\n').decode('utf-8')
def current(values):
    for p,v in values.items():assert digest(ROOT/p)==v,('changed verified input',p)


def source_guard():
    manifest={p.replace('\\','/'):v for p,v in load(RUN/'source_manifest.json').items()}
    current(manifest);changed=set()
    for p,v in manifest.items():
        assert digest(RUN/'source_archive'/p)==v
        assert read(ROOT/p)==old(RUNTIME,p),('unreviewed runtime',p)
        if read(ROOT/p)!=old(BASE,p):changed.add(p)
    assert changed==ALLOWED,changed^ALLOWED
    for p,v in load(RUN/'protected_user_files.json').items():
        assert digest(ROOT/p)==v['sha256']
        assert subprocess.check_output(['git','ls-files','--stage','--',p],cwd=ROOT,text=True).strip()==v['index']
    ref=ROOT/'sim/reference/velocity_teammate';info=load(ref/'reference.json')
    assert info['baseline_commit']==BASE and info['voice_envelope_identical_to_current'] is True
    for name,v in info['input_sha256'].items():assert digest(ref/'user_inputs'/name)==v
    assert read(ref/'user_inputs/voice_envelope.v')==read(ROOT/'rtl/control/voice_envelope.v')
    before=read(ref/'user_inputs/four_string_pluck_detector.v')
    expected=before.replace('output reg [31:0] event_timestamp\n','output reg [31:0] event_timestamp,\n    output wire [3:0] capture_pending\n').replace('    reg [3:0] capturing;','    reg [3:0] capturing;\n    assign capture_pending=capturing;')
    assert read(ROOT/'rtl/input/four_string_pluck_detector.v')==expected
    config=read(ref/'user_inputs/guitar_config.vh')
    config=config.replace('// 必须达到 100 个 ADC 相对基准码，才认定为一次有效拨弦','// CH0..CH3 trigger at the measured absolute deviations below (inclusive).')
    config=config.replace('// 信号回落到 30 以下，才允许该弦下一次触发','// All four channels must settle at deviation <=20 before rearming.')
    assert read(ROOT/'rtl/config/guitar_config.vh')==config
    # All other existing configuration values, not just audio parameters, stay.
    defs=lambda s:dict(re.findall(r'^`define[ \t]+(\w+)([^\n]*)',s,re.M))
    a=defs(old(BASE,'rtl/config/guitar_config.vh'));b=defs(config)
    mutable={'BOARD_FIXED_VELOCITY_ENABLE','ADC_BASELINE_CODE','PLUCK_TRIGGER_THRESHOLD','PLUCK_REARM_THRESHOLD','VELOCITY_LEVEL_1_THRESHOLD','VELOCITY_LEVEL_2_THRESHOLD','VELOCITY_LEVEL_3_THRESHOLD'}
    assert set(a)<=set(b)
    assert all(v==b[n] for n,v in a.items() if n not in mutable)
    old_fs=SAVED/'evidence/gowin/neo_guitar_touch_game/impl/pnr/neo_guitar_touch_game.fs'
    assert digest(old_fs)==info['baseline_fs_sha256']=='34f8a86e942e291453159655c654fc72e5424167686cb2200dd659d4daf7229c'
    assert load(SAVED/'verification.json')['bitstream_sha256']==digest(old_fs)
    return manifest


def evidence():
    result={}
    for name,bench in [('velocity_detector_01',None),('velocity_audio_02',None),('velocity_legacy_01',None),
        ('velocity_adc_gate_01','tb_velocity_adc_gate'),('velocity_full_gate_01','tb_game_p3_full_gate'),('velocity_posture_gate_01','tb_posture_full_gate')]:
        folder=ROOT/'sim/temp'/name;receipt=folder/'verification.json';data=load(receipt)
        assert data.get('result',data.get('status'))=='PASS',name
        current(data['source_sha256'])
        logs=data['log_sha256'];gate=bench is not None
        if gate:
            assert data['netlist_sha256']==digest(PROJECT/'impl/gwsynthesis'/f'{NAME}.vg')
            assert data['mapping_sha256']==digest(folder/'mapping.json')
            mapping=load(folder/'mapping.json')
            assert mapping['netlist_sha256']==data['netlist_sha256'] and mapping['bank_dpb16']==10 and mapping['initial_rows']==2048
            assert mapping['gain_rom_entries']==128 and mapping['mode_state_sdpb_per_voice']==1
            assert mapping['velocity_adc']['header_sha256']==digest(folder/'velocity_gate_adc.vh')
            logs={bench:logs}
        for b,v in logs.items():
            path=folder/(b+'.log');assert digest(path)==v
            body=read(path);assert 'PASS:' in body and not re.search(r'FAIL:|\*\* (Error|Fatal):',body)
            for line in body.splitlines():
                if '** Warning:' in line:assert gate and VENDOR.search(line),(path,line)
        for p in folder.glob('*'):
            if p.is_file() and p.suffix in ['.json','.sv','.vh','.log','.csv']:result[rel(p)]=digest(p)
        result[rel(receipt)]=digest(receipt)
    rows=list(csv.DictReader(read(ROOT/'sim/temp/velocity_audio_02/velocity_loudness.csv').splitlines()))
    assert len(rows)==12
    for t in range(3):
        group=[r for r in rows if int(r['timbre'])==t]
        assert [int(r['level']) for r in group]==list(range(4))
        full=int(group[-1]['voice_energy']);last=0
        for r,g in zip(group,[112,160,208,256]):
            e=int(r['voice_energy']);assert e>last;last=e
            assert int(r['gain_q8'])==g and int(r['samples'])==1024 and int(r['hard_rail_samples'])==0
            assert abs(e/full-(g/256)**2)<.001
    pc=ROOT/'build/p4_posture/pc_checks_a1/verification.json';d=load(pc)
    assert d['result']=='PASS';current(d['source_sha256']);current(d['log_sha256'])
    result[rel(pc)]=digest(pc);result.update(d['log_sha256'])
    audit=RUN/'bank_write_audit.json';d=load(audit)
    assert d['result']=='PASS' and d['boolean_cases']==384 and d['netlist_sha256']==digest(PROJECT/'impl/gwsynthesis'/f'{NAME}.vg')
    assert d['tool_sha256']==digest(ROOT/'tools/audit_velocity_bank.py')
    result[rel(audit)]=digest(audit)
    return result


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--preflight',action='store_true');args=parser.parse_args()
    manifest=source_guard();proof=evidence()
    if args.preflight:
        print('PASS exact5 runtime changes/user calibration/complete input hashes/RTL loudness/frozen audio/current full VG+actual ADC; P&R not certified');return
    pnr = PROJECT/'impl/pnr'
    log = read(pnr/f'{NAME}.log')
    report = read(pnr/f'{NAME}.rpt.txt')
    timing = read(pnr/f'{NAME}_tr_content.html')
    stdout = read(RUN/'route.stdout.log')
    assert 'Bitstream generation completed' in log and 'ERROR' not in log
    assert 'PNR_TCL_FINISHED' in stdout and not read(RUN/'route.stderr.log').strip()
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
    route_started = datetime.fromisoformat(load(RUN/'route_process.json')['started']).timestamp()
    artifacts = [vg, fs, syn, PROJECT/'impl/gwsynthesis'/f'{NAME}_syn_rsc.xml',
        pnr/f'{NAME}.log', pnr/f'{NAME}.rpt.txt', pnr/f'{NAME}_tr_content.html', pnr/'cmd.do']
    for path in artifacts:
        assert path.stat().st_mtime >= (route_started if path.parent==pnr else started), ('stale implementation artifact', path)
    artifacts += [RUN/p for p in ['process.json', 'source_manifest.json', 'protected_user_files.json',
        'synthesis_review.json', 'build.tcl', 'build.stdout.log', 'build.stderr.log', 'route.tcl', 'route.stdout.log', 'route.stderr.log', 'route_process.json']]
    config_snapshot = RUN/'protected_process_config.snapshot.json'
    assert digest(config_snapshot) == load(RUN/'protected_user_files.json')['gowin/neo_guitar_touch_game/impl/neo_guitar_touch_game_process_config.json']['sha256']
    artifacts.append(config_snapshot)
    prior=load(SAVED/'verification.json')
    artifacts+=[SAVED/'verification.json',ROOT/'sim/reference/velocity_teammate/reference.json']
    artifacts+=list((ROOT/'sim/reference/velocity_teammate/user_inputs').glob('*'))
    pc_inputs=load(ROOT/'build/p4_posture/pc_checks_a1/verification.json')['source_sha256']
    artifacts+=[ROOT/p for p in pc_inputs]
    tools=[Path(__file__)]+[ROOT/'tools'/n for n in ['archive_velocity.py','run_velocity_checks.ps1','run_velocity_gate.ps1',
        'prepare_velocity_gate.py','prepare_posture_gate.py','prepare_game_p3_gate.py','compare_synth_graph.py','audit_velocity_bank.py',
        'start_original_velocity_synthesis.ps1','route_original_velocity.ps1','run_touch_game_checks.ps1']]
    route=load(RUN/'route_process.json');route.update(status='COMPLETE_VERIFICATION_PASS',verified_at=datetime.now().astimezone().isoformat())
    (RUN/'route_process.json').write_text(json.dumps(route,indent=2)+'\n',encoding='utf-8')
    record=dict(result='PASS',artifact_scope=dict(kind='original_gprj_p4_teammate_velocity_calibration',project=rel(PROJECT/f'{NAME}.gprj'),implementation=rel(PROJECT/'impl')),
        previous_release_commit=BASE,validated_source_commit=RUNTIME,source_sha256=manifest,
        artifacts_sha256={rel(p):digest(p) for p in artifacts},evidence_sha256=proof,verification_tools_sha256={rel(p):digest(p) for p in tools},
        resources=resources,clocks=clocks,previous_release_resources=prior['resources'],previous_release_clocks=prior['clocks'],
        bitstream_sha256=digest(fs),netlist_sha256=digest(vg),
        margin_targets_met=(resources['CLS']['used']/resources['CLS']['available']<=.95 and clocks['sys_clk_50m']['fmax_mhz']>=55 and clocks['audio_clk_12m288']['fmax_mhz']>=13.5),
        violations=dict(setup=0,hold=0,latch=0,unrouted=0,tested_audio_deadline=0,tested_score_deadline=0,tested_posture_deadline=0),
        calibration=dict(baseline_codes=[2053]*4,trigger=[150,100,80,100],rearm=[20]*4,
            bin_boundaries=[[280,430,620],[250,400,600],[150,280,400],[220,380,600]],capture_subsequent_channel_samples=32,
            total_peak_observations=33,dead_channel_samples=400,settle_channel_samples=80,fixed_velocity_default=False,
            existing_voice_gain_q8=[112,160,208,256],voice_envelope_unchanged=True,
            scope='Measured per-string thresholds supplied by teammate; no independent raw ADC/acoustic measurement. Actual piano/bright/wah models,all FX/coefficients/sample clocks/master gain unchanged; game autoplay stays2.'),
        preserved_source='Every runtime file except5 reviewed files equals saved P4; exact teammate detector plus observation output; exact config values; no audio equations/ROM/score/display/MPU/pin/SDC/route-setting changes',
        regression=dict(detector_raw_cases=16384,peak_positions=132,physical_spi_cases=16,
            timbres=3,velocity_levels=4,measured_samples_per_level=1024,single_voice_dry_hard_rails=0,
            existing_pcm_pt8211_i2s_oracle=True,frozen_audio_samples=8192,frozen_audio_reference_clocks=2097153,
            extended_full32_oracle_samples=9032,sustain_exit_samples=1452,current_actual_vg_benches=3,
            actual_adc_gate_clocks=4739008,actual_adc_conversions=32238,bank_boolean_cases=384,
            unchanged_pc_tests_reused=33,unchanged_pc_scope='Exact complete PC source/input hashes; no Python score/protocol changes'),
        publication=dict(user_authorized_same_name_overwrite=True,path='build/releases/touch_game/neo_guitar_touch_game_p4_posture.fs',
            saved_old_archive=rel(SAVED),saved_old_sha256=prior['bitstream_sha256'],local_tag='snapshot/p4-posture-before-velocity-20261018'),
        hardware_status='Not board tested. No COM opened, no physical flashing or acoustic measurement; teammate thresholds are supplied values, not agent measurements.',
        pending_hardware=['Four strings/four strengths/noise and cross-trigger checks','Digital gain vs real loudness and clipping','Game judgement with capture latency','MPU+pending capture+sustain/manual interactions','Long-duration stability'],
        generated_at=datetime.now().astimezone().isoformat())
    (PROJECT/'velocity_calibration_verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:record[k] for k in ['result','resources','clocks','bitstream_sha256','margin_targets_met']},indent=2))


if __name__=='__main__':main()
