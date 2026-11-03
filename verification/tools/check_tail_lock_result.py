"""Bind the scoped tail-lock change to current focused verification and STA."""
import argparse
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
from datetime import datetime,timezone
from pathlib import Path
from check_piano_hold_result import read,load,sha,save,rel,receipt

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'build/releases/touch_game/piano_short_hold_20261025'
RUN=ROOT/'build/vibrato/tail_lock_v1'
PROJECT=ROOT/'gowin/neo_guitar_touch_game';NAME='neo_guitar_touch_game'
HEAD='380312970eab0b455df1f8d80f055d47fdbc5324'
CHANGED={'rtl/control/guitar_play_control.v','rtl/input/matrix_scanner.v',
 'rtl/control/performance_vibrato_gesture.v','rtl/game/guitar_touch_game_audio.v',
 'rtl/game/game_p2_mode_router.v','rtl/game/audio_mode_router.v','rtl/audio_io/four_string_board_audio_chain.v'}
TESTS=('tail_lock_controls_01','tail_lock_audio_02')
GATE='tail_lock_audio_gate_02'

def source_guard():
    assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()==HEAD
    baseline=load(BASE/'verification.json');manifest=load(RUN/'source_manifest.json')
    assert baseline['result']=='PASS' and set(manifest)==set(baseline['source_sha256'])
    changed=set()
    for p,digest in manifest.items():
        assert sha(ROOT/p)==digest==sha(RUN/'source_archive'/p),p
        if digest!=baseline['source_sha256'][p]:changed.add(p)
    assert changed==CHANGED,changed
    for p,item in load(RUN/'protected_user_files.json').items():
        assert sha(ROOT/p)==item['sha256']
        assert subprocess.check_output(['git','ls-files','--stage','--',p],cwd=ROOT,text=True).strip()==item['index'].strip()
    for module,path in [('matrix_scanner','rtl/input/matrix_scanner.v'),('four_string_board_audio_chain','rtl/audio_io/four_string_board_audio_chain.v')]:
        frozen=BASE/'evidence'/path;assert sha(frozen)==baseline['source_sha256'][path]
        assert read(ROOT/'sim/reference/tail_lock'/(module+'_before.v'))==read(frozen).replace('module '+module+' ','module tail_before_'+module+' ',1)
    # Source-level noninterference: none of the natural piano, DDS, effects,
    # calibration, score, display or constraint bytes may change in this task.
    assert manifest['rtl/synth/piano_voice_core.v']==baseline['source_sha256']['rtl/synth/piano_voice_core.v']
    # The compatibility audio wrapper only adds an explicit disabled observer.
    p='rtl/audio_io/four_string_board_audio_chain.v'
    assert read(ROOT/p)==read(BASE/'evidence'/p).replace('    guitar_play_control u_play_control (',
        "    guitar_play_control u_play_control (\n        .fret_release(4'd0),",1)
    return manifest,baseline

def diagnostic():
    folder=ROOT/'sim/temp/tail_lock_matrix_baseline_01';record=load(folder/'verification.json')
    assert record['status']=='PASS'
    baseline=load(BASE/'verification.json')
    for p,digest in record['source_sha256'].items():
        norm=p.replace('\\','/')
        assert digest==(baseline['source_sha256'][norm] if norm in baseline['source_sha256'] else sha(ROOT/p)),p
    for bench,digest in record['log_sha256'].items():
        body=read(folder/(bench+'.log'))
        assert sha(folder/(bench+'.log'))==digest and '19 raw-observed releases merged' in body
        assert not re.search(r'FAIL:|\*\* (?:Error|Fatal|Warning):',body)

def synthesis():
    manifest,baseline=source_guard();diagnostic()
    for name in TESTS:receipt(name)
    p=load(RUN/'process.json');body=read(RUN/'build.stdout.log')
    assert p['status']=='EXITED' and p['exit_code']==0 and p['source_commit']==HEAD
    assert p['launcher_sha256']==sha(ROOT/'tools/run_vibrato_gowin.py')
    assert 'SYNTHESIS_TCL_FINISHED' in body and 'GowinSynthesis finish' in body
    assert not read(RUN/'build.stderr.log').strip()
    assert not re.search(r'^ERROR|inferr?ed.*latch|latch.*inferr?ed',body,re.I|re.M)
    oldlog=read(BASE/'evidence'/f'gowin/neo_guitar_touch_game/impl/gwsynthesis/{NAME}.log')
    norm=lambda x:x.split('("',1)[0].strip()
    allowed={norm(x) for x in oldlog.splitlines() if x.startswith('WARN ')}
    warnings=[x for x in body.splitlines() if x.startswith('WARN ')]
    assert all(norm(x) in allowed for x in warnings),('new synthesis warning',warnings)
    resource=PROJECT/f'impl/gwsynthesis/{NAME}_syn_rsc.xml'
    attrs=ET.parse(resource).getroot().attrib
    old=ET.parse(BASE/'evidence'/rel(resource)).getroot().attrib
    assert {k:v for k,v in attrs.items() if k.startswith('T_MULT')}=={k:v for k,v in old.items() if k.startswith('T_MULT')}
    n=lambda k:int(re.match(r'\d+',attrs['T_'+k])[0])
    resources={'Logic':n('Lut')+n('Alu'),'Register':n('Register'),'BSRAM_logical':n('Bsram')}
    assert resources['Logic']<=59904 and resources['Register']<=60780 and resources['BSRAM_logical']<=118
    vg=PROJECT/f'impl/gwsynthesis/{NAME}.vg';assert vg.stat().st_mtime>=datetime.fromisoformat(p['started']).timestamp()
    record={'result':'PASS','netlist_sha256':sha(vg),'source_manifest_sha256':sha(RUN/'source_manifest.json'),
        'resources_synthesis':resources,'source_commit':HEAD,'runtime_changes':sorted(CHANGED),
        'scope':'Production tail lock and qualified short-release observer only; piano half-duration and all other runtime source hashes retained'}
    save(RUN/'synthesis_review.json',record);print(record)

def route_result():
    route=load(RUN/'route_process.json');body=read(RUN/'route.stdout.log')
    assert route['status']=='EXITED' and route['exit_code']==0 and route['source_commit']==HEAD
    assert Path(route['project']).resolve()==(PROJECT/f'{NAME}.gprj').resolve()
    assert route['launcher_sha256']==sha(ROOT/'tools/run_vibrato_gowin.py')
    assert not read(RUN/'route.stderr.log').strip()
    assert all(x in body for x in ('PNR_TCL_FINISHED','Placement and routing completed','Bitstream generation completed'))
    assert not re.search(r'\bERROR\b|\bPR0004\b|\b[1-9]\d*\s+(?:unrouted|unroute|unconnected)\b',body,re.I)
    previous=read(BASE/'evidence'/f'gowin/neo_guitar_touch_game/impl/pnr/{NAME}.log')
    assert sorted(x for x in body.splitlines() if x.startswith('WARN '))==sorted(x for x in previous.splitlines() if x.startswith('WARN '))
    pnr=PROJECT/'impl/pnr';report=read(pnr/f'{NAME}.rpt.txt');timing=read(pnr/f'{NAME}_tr_content.html')
    clocks={};resources={}
    for clock,required in [('sys_clk_50m',50),('audio_clk_12m288',12.288)]:
        hit=re.search(rf'<td>{clock}</td>\s*<td>([\d.]+)\(MHz\)</td>\s*<td>([\d.]+)\(MHz\)</td>',timing)
        assert hit and float(hit[1])==required and float(hit[2])>=required,clock
        clocks[clock]={'required_mhz':required,'fmax_mhz':float(hit[2])}
    for kind in ('Setup','Hold'):
        hit=re.search(rf'Numbers of {kind} Violated Endpoints</td>\s*<td>(\d+)</td>',timing)
        assert hit and int(hit[1])==0,kind
    for name in ('Logic','Register','CLS','BSRAM','DSP'):
        hit=re.search(rf'^\s*{name}\s*\|\s*([\d.]+)/([\d.]+)',report,re.M);assert hit
        used,total=map(float,hit.groups());assert used<=total;resources[name]={'used':used,'available':total}
    assert resources['DSP']['used']==115.5
    latches=re.findall(r'--(?:Logic|I/O) Register as Latch\s*\|\s*(\d+)/',report)
    assert len(latches)==2 and all(int(x)==0 for x in latches)
    cmd=read(pnr/'cmd.do');vg=PROJECT/f'impl/gwsynthesis/{NAME}.vg'
    assert Path(re.search(r'^-d\s+(.+)$',cmd,re.M)[1].strip()).resolve()==vg.resolve()
    for k,v in [('place_option',4),('route_option',2),('route_maxfan',32),('clock_route_order',0),('correct_hold',1)]:
        assert re.search(rf'^-{k}\s+{v}\s*$',cmd,re.M),k
    pins=dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+);',read(ROOT/f'constraints/{NAME}.cst')))
    assert len(pins)==len(set(pins.values()))==63
    rows={}
    for line in report.splitlines():
        fields=[x.strip() for x in line.split('|')]
        if len(fields)>8 and fields[0] in pins:rows[fields[0]]=fields
    for port,ball in pins.items():
        assert rows[port][2].split('/')[0]==ball and rows[port][3]=='Y'
        assert rows[port][7]==('LVCMOS15' if port.startswith('USER_BUTTON') else 'LVCMOS33')
    fs=pnr/f'{NAME}.fs';assert fs.stat().st_size>10000000
    for file in (fs,pnr/f'{NAME}.rpt.txt',pnr/f'{NAME}_tr_content.html',pnr/f'{NAME}.log'):
        assert file.stat().st_mtime>=datetime.fromisoformat(route['started']).timestamp()
    return resources,clocks,sha(fs)

def verify():
    manifest,baseline=source_guard();diagnostic()
    tests={n:receipt(n) for n in TESTS+(GATE,)}
    vg=PROJECT/f'impl/gwsynthesis/{NAME}.vg'
    review=load(RUN/'synthesis_review.json');assert review['result']=='PASS' and review['netlist_sha256']==sha(vg)
    mapping=load(ROOT/'sim/temp'/GATE/'mapping.json')
    assert mapping['result']=='PASS' and mapping['netlist_sha256']==sha(vg)
    assert mapping['tool_sha256']==sha(ROOT/'tools/prepare_tail_gate.py')
    assert mapping['wrapper_sha256']==sha(ROOT/'sim/temp'/GATE/'tail_gate_audio.sv')
    graph=load(RUN/'unchanged_graph_audit.json');assert graph['netlist_sha256']==sha(vg)
    assert graph['tool_sha256']==sha(ROOT/'tools/audit_tail_unchanged.py')
    assert graph['modules']['mcp3208_pluck_frontend']['equal']
    reuse=load(RUN/'source_reuse_audit.json')
    assert reuse['result']=='PASS' and reuse['netlist_sha256']==sha(vg)
    assert reuse['tool_sha256']==sha(ROOT/'tools/audit_tail_source_reuse.py')
    assert reuse['source_manifest_sha256']==sha(RUN/'source_manifest.json')
    assert reuse['baseline_verification_sha256']==sha(BASE/'verification.json')
    assert reuse['graph_diagnostic_sha256']==sha(RUN/'unchanged_graph_audit.json')
    assert reuse['unchanged_source_sha256']=={p:d for p,d in manifest.items() if p not in CHANGED}
    assert reuse['adc_exact_graph_equal'] and not reuse['other_graphs_equal']
    resources,clocks,bitstream=route_result()
    old=ROOT/'build/releases/touch_game/neo_guitar_touch_game_piano_short_hold.fs'
    assert sha(old)==baseline['bitstream_sha256']
    paths=set(manifest)|{'tools/check_tail_lock_result.py','tools/check_piano_hold_result.py',
        'tools/prepare_tail_lock.py','tools/audit_tail_unchanged.py','tools/audit_tail_source_reuse.py','docs/TAIL_PITCH_LOCK.md','README.md','AGENTS.md',
        'gowin/neo_guitar_touch_game/README.md','build/tail_lock/baseline.json',
        'sim/tb/tb_matrix_release_visibility.sv','tools/run_vibrato_checks.ps1',
        'sim/temp/tail_lock_matrix_baseline_01/matrix_release_baseline.csv'}
    for name in ('tail_lock_matrix_baseline_01','tail_lock_audio_01','tail_lock_audio_gate_01'):
        paths.update(rel(p) for p in (ROOT/'sim/temp'/name).iterdir() if p.is_file() and p.suffix in ('.log','.json'))
    for name,record in tests.items():
        paths.update(p.replace('\\','/') for p in record['source_sha256'])
        paths.update(rel(p) for p in (ROOT/'sim/temp'/name).iterdir() if p.is_file() and p.suffix in ('.log','.json','.sv','.vh'))
    for folder in (RUN,PROJECT/'impl/gwsynthesis',PROJECT/'impl/pnr'):
        paths.update(rel(p) for p in folder.iterdir() if p.is_file() and p.suffix in ('.json','.log','.tcl','.vg','.fs','.html','.txt','.xml','.do'))
    record={'result':'PASS','generated_at':datetime.now(timezone.utc).isoformat(),'pushed_baseline_commit':HEAD,
        'source_state':'Local tail-lock modifications; no new push or hardware programming',
        'source_sha256':manifest,'runtime_changes':sorted(CHANGED),'artifacts_sha256':{p:sha(ROOT/p) for p in sorted(paths)},
        'baseline_verification_sha256':sha(BASE/'verification.json'),'baseline_bitstream_sha256':baseline['bitstream_sha256'],
        'netlist_sha256':sha(vg),'bitstream_sha256':bitstream,'resources':resources,'clocks':clocks,
        'violations':{'setup':0,'hold':0,'latch':0,'unrouted':0,'tested_audio_deadline':0},
        'test_receipts':{n:sha(ROOT/'sim/temp'/n/'verification.json') for n in tests},
        'release_detection':'Separate per-string two-empty-row-sample observer, one1ms frame apart. Original five-frame row/raw/stable outputs frozen every clock. Gaps>=2ms observed in tested scan phases; subframe gaps cannot be guaranteed; single empty sample intentionally rejected.',
        'policy':'Release locks audible tail until the next real pluck; later contacts prepare only. Continuous contact changes retain slides. Real open plucks and same-fret three-tap vibrato preserved.',
        'verification_scope':'Changed complete production audio-child VG versus RTL and independent frozen-chain pitch-scenario oracle; physical columns/production sample and tap timing. Registered ADC event/velocity/pending boundary stimuli only, no matrix/note/DDS/audio forces. No SDF; separate full original-project post-route STA.',
        'reuse':'Unchanged source/ROM/project/constraint bytes retained, including half-duration piano. Only ADC exact primitive graph equality proven. Other source-unchanged modules were remapped, so no exact graph equivalence or fresh UI/UART/MPU functional certification claimed. Current complete audio-child gate and full original-project STA are fresh; unrelated simulations not repeated.',
        'hardware_status':'Not programmed or board tested; pending user listening and physical-hand release feedback.'}
    save(PROJECT/'tail_lock_verification.json',record)
    print({k:record[k] for k in ('result','resources','clocks','violations','bitstream_sha256')})
    return record

def publish():
    record=verify();folder=ROOT/'build/releases/touch_game/tail_lock_20261025'
    destination=ROOT/'build/releases/touch_game/neo_guitar_touch_game_tail_lock.fs'
    assert not folder.exists() and not destination.exists();folder.mkdir()
    for p in record['artifacts_sha256']:
        target=folder/'evidence'/p;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(ROOT/p,target)
        assert sha(target)==record['artifacts_sha256'][p]
    shutil.copy2(PROJECT/'tail_lock_verification.json',folder/'verification.json')
    shutil.copy2(PROJECT/f'impl/pnr/{NAME}.fs',destination);shutil.copy2(destination,folder/destination.name)
    assert sha(destination)==record['bitstream_sha256']
    save(folder/'archive.json',{'result':'PASS','published':rel(destination),'bitstream_sha256':sha(destination),
        'verification_sha256':sha(folder/'verification.json'),'pushed_baseline_commit':HEAD})
    print('Published local tail-lock artifact: '+str(destination))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('stage',choices=['synthesis','verify','publish'])
    a=p.parse_args();globals()[a.stage]()
