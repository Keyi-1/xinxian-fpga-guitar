"""Bind the original complete guitar build to independently tested performance vibrato."""
import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path
from compare_synth_graph import Graph, parse

ROOT=Path(__file__).resolve().parents[1]
RUN=ROOT/'build/vibrato/v6'
BEFORE=ROOT/'build/vibrato/before_20261023'
PROJECT=ROOT/'gowin/neo_guitar_touch_game'
NAME='neo_guitar_touch_game'
DIVIDE_SOURCE='rtl/control/phase_slide_smoother.v'
MODIFIED={'rtl/audio_io/four_string_board_audio_chain.v','rtl/game/guitar_touch_game_audio.v','gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj','rtl/game/touch_game_renderer.v','rtl/display/lcd_rgb_scan_480x272.v',DIVIDE_SOURCE}
ADDED={'rtl/control/performance_vibrato_gesture.v','rtl/control/four_string_vibrato_serial.v'}


def read(p):return p.read_text(encoding='utf-8-sig')
def load(p):return json.loads(read(p))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,data):p.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
def rel(p):return p.relative_to(ROOT).as_posix()
def git(*args):return subprocess.check_output(['git','-C',str(ROOT),*args],text=True,encoding='utf-8')


def runtime_guard():
    saved=load(BEFORE/'snapshot.json')
    assert git('rev-parse','HEAD').strip()==saved['head']
    manifest=load(RUN/'source_manifest.json')
    changed=set();added=set()
    for path,digest in manifest.items():
        assert sha(ROOT/path)==digest==sha(RUN/'source_archive'/path),path
        if path not in saved['hashes']:added.add(path)
        elif digest!=saved['hashes'][path]:changed.add(path)
    assert changed==MODIFIED and added==ADDED,('unrelated runtime edit',changed,added)
    divide15_guard()
    from audit_vibrato_timing import audit
    assert load(RUN/'display_timing_audit.json')==audit()
    for name,path in (('four_string_board_audio_chain','rtl/audio_io/four_string_board_audio_chain.v'),
                      ('guitar_touch_game_audio','rtl/game/guitar_touch_game_audio.v'),
                      ('phase_vibrato_modulator','rtl/control/phase_vibrato_modulator.v'),
                      ('touch_game_renderer','rtl/game/touch_game_renderer.v'),
                      ('lcd_rgb_scan_480x272','rtl/display/lcd_rgb_scan_480x272.v')):
        expected=read(BEFORE/'files'/path).replace('module '+name+' ','module vibrato_before_'+name+' ',1)
        if name=='guitar_touch_game_audio':expected=expected.replace('four_string_board_audio_chain #','vibrato_before_four_string_board_audio_chain #',1)
        assert read(ROOT/'sim/reference/vibrato'/(name+'_before.v'))==expected,('frozen reference',name)
    gesture_v2=read(ROOT/'build/vibrato/v2/source_archive/rtl/control/performance_vibrato_gesture.v')
    assert read(ROOT/'sim/reference/vibrato/performance_vibrato_gesture_v2.v')==gesture_v2.replace('module performance_vibrato_gesture ','module vibrato_v2_performance_vibrato_gesture ',1)
    project='gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj'
    body=read(ROOT/project)
    for file in sorted(ADDED):
        line='        <File path="../../'+file+'" type="file.verilog" enable="1" />\n'
        assert body.count(line)==1
        body=body.replace(line,'',1)
    assert body==read(BEFORE/'files'/project),'Only two source-list additions are allowed'
    for path,item in load(RUN/'protected_user_files.json').items():
        assert sha(ROOT/path)==item['sha256']==saved['hashes'][path]
        assert git('ls-files','--stage','--',path).strip()==item['index'].strip()
    return manifest,saved


def divide15_guard():
    from prepare_vibrato_divide15 import audit_current
    proof=audit_current()
    stored=load(ROOT/'build/vibrato/divide15_candidate/proof.json')
    assert all(proof[key]==value for key,value in stored.items()),'Stored /15 proof changed'
    record=load(ROOT/'sim/temp/vibrato_divide15_06/verification.json')
    assert record['status']=='PASS'
    for path,digest in record['source_sha256'].items():
        assert sha(ROOT/path)==digest,path
    for bench,digest in record['log_sha256'].items():
        log=ROOT/'sim/temp/vibrato_divide15_06'/(bench+'.log')
        assert sha(log)==digest
        body=read(log)
        assert 'PASS:' in body and not re.search(r'FAIL:|\*\* (?:Error|Fatal|Warning):',body)
    return proof


def receipt(name):
    folder=ROOT/'sim/temp'/name
    record=load(folder/'verification.json')
    assert record.get('status',record.get('result'))=='PASS',name
    for path,digest in record['source_sha256'].items():
        if sha(ROOT/path)!=digest:
            if path.replace('\\','/')==DIVIDE_SOURCE:
                allow_verified_divide(name,digest)
            else:
                allow_unelaborated_display(name,record,path,digest)
    logs=record['log_sha256']
    if isinstance(logs,str):logs={record['bench']:logs}
    for bench,digest in logs.items():
        path=folder/(bench+'.log')
        assert sha(path)==digest,(name,bench)
        body=read(path)
        assert 'PASS:' in body and not re.search(r'FAIL:|\*\* (?:Error|Fatal):',body),(name,bench)
        warnings=[line for line in body.splitlines() if line.startswith('# ** Warning:')]
        # Same precise vendor-library exception as run_velocity_gate.ps1.
        # No warning from project HDL, and no other primitive warning, passes.
        unexpected=[line for line in warnings if not re.search(
          r"prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)",line)]
        assert not unexpected,(name,bench,unexpected)
    if 'mapping_sha256' in record:assert sha(folder/'mapping.json')==record['mapping_sha256']
    if 'netlist_sha256' in record:assert sha(folder/'compiled.vg')==record['netlist_sha256']
    return record


def allow_verified_divide(name,digest):
    assert name in ('vibrato_components_09','vibrato_audio_05','vibrato_top_04',
      'vibrato_legacy_05','vibrato_physical_top_04','vibrato_display_timing_02',
      'vibrato_full_gate_02',
      'vibrato_posture_gate_02','vibrato_adc_gate_02','vibrato_gesture_gate_02'),name
    proof=divide15_guard()
    assert digest==proof['before_sha256']


def allow_unelaborated_display(name,record,path,digest):
    # These two isolated audio/gesture runs compiled all RTL, but never
    # instantiated either display module. Keep their completed results instead
    # of rerunning audio for unrelated compiled-only display files.
    assert name in ('vibrato_components_09','vibrato_audio_05'),(name,path)
    norm=path.replace('\\','/')
    assert norm in ('rtl/game/touch_game_renderer.v','rtl/display/lcd_rgb_scan_480x272.v')
    assert digest==sha(ROOT/'build/vibrato/v4/source_archive'/norm)
    from audit_vibrato_timing import audit
    proof=audit();assert proof['modules'][norm]['before_sha256']==digest
    receipt('vibrato_display_timing_02')
    modules={}
    for source in record['source_sha256']:
        p=ROOT/source
        if p.suffix not in ('.v','.sv'):continue
        body=re.sub(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"','',read(p),flags=re.S)
        for hit in re.finditer(r'\bmodule\s+(\w+)\b(.*?)\bendmodule\b',body,re.S):
            assert hit[1] not in modules,hit[1]
            modules[hit[1]]=hit[2]
    logs=record['log_sha256'];roots=list(logs) if isinstance(logs,dict) else [record['bench']]
    reached=set();pending=list(roots)
    while pending:
        module=pending.pop()
        if module in reached:continue
        assert module in modules,module
        reached.add(module)
        assert not re.search(r'\b(?:bind|config)\b',modules[module])
        pending.extend((set(re.findall(r'\b\w+\b',modules[module]))&set(modules))-reached)
    assert not any(m.endswith(('touch_game_renderer','lcd_rgb_scan_480x272')) for m in reached)
    for bench in roots:
        body=read(ROOT/'sim/temp'/name/(bench+'.log'))
        assert not re.search(r'^# Loading work\.\w*(?:touch_game_renderer|lcd_rgb_scan_480x272)\(',body,re.M)


def review():
    manifest,saved=runtime_guard()
    components=receipt('vibrato_components_09')
    audio=receipt('vibrato_audio_05')
    for record in (components,audio):
        for path,digest in record['source_sha256'].items():
            norm=path.replace('\\','/')
            if norm in manifest and norm not in ('rtl/game/touch_game_renderer.v','rtl/display/lcd_rgb_scan_480x272.v',DIVIDE_SOURCE):
                assert digest==manifest[norm],norm
    log=read(RUN/'build.stdout.log');process=load(RUN/'process.json')
    assert process['status']=='EXITED' and process['exit_code']==0
    assert 'SYNTHESIS_TCL_FINISHED' in log and 'GowinSynthesis finish' in log
    assert process['launcher_sha256']==sha(ROOT/'tools/run_vibrato_gowin.py')
    assert not read(RUN/'build.stderr.log').strip()
    assert not re.search(r'^\s*ERROR|inferr?ed.*latch|latch.*inferr?ed',log,re.I|re.M)
    resource=PROJECT/f'impl/gwsynthesis/{NAME}_syn_rsc.xml'
    current=ET.parse(resource).getroot().attrib
    old=ET.parse(BEFORE/'files'/rel(resource)).getroot().attrib
    dsp={k:v for k,v in current.items() if k.startswith('T_MULT')}
    assert dsp=={k:v for k,v in old.items() if k.startswith('T_MULT')},'Vibrato must add no DSP primitives'
    number=lambda key:int(re.match(r'\d+',current['T_'+key])[0])
    resources={k:number(v) for k,v in [('Register','Register'),('LUT','Lut'),('ALU','Alu'),('BSRAM_logical','Bsram')]}
    assert resources['LUT']+resources['ALU']<=59904 and resources['Register']<=60780 and resources['BSRAM_logical']<=118
    vg=PROJECT/f'impl/gwsynthesis/{NAME}.vg'
    started=datetime.fromisoformat(process['started']).timestamp()
    for p in (vg,resource,PROJECT/f'impl/gwsynthesis/{NAME}.log'):assert p.stat().st_mtime>=started
    previous_log=read(BEFORE/'files'/f'gowin/neo_guitar_touch_game/impl/gwsynthesis/{NAME}.log')
    normalize=lambda line:line.split('("',1)[0].strip()
    previous_warnings={normalize(x) for x in previous_log.splitlines() if x.startswith('WARN ')}
    warnings=[x for x in log.splitlines() if x.startswith('WARN ')]
    assert all(normalize(x) in previous_warnings for x in warnings),('new synthesis warning',warnings)
    before_modules=parse(read(BEFORE/'files'/rel(vg)));after_modules=parse(read(vg))
    graphs={}
    for module in ('guitar_touch_game_audio','guitar_touch_game_display','game_p3_score_bank','mcp3208_pluck_frontend'):
        old_graph=Graph(before_modules,module).signature();new_graph=Graph(after_modules,module).signature()
        graphs[module]={'exact_graph_equal':old_graph==new_graph,'before':old_graph,'after':new_graph}
    record={'result':'PASS','source_commit':saved['head'],'source_state':'local vibrato implementation; original release retained',
      'netlist_sha256':sha(vg),'source_manifest_sha256':sha(RUN/'source_manifest.json'),
      'resources_synthesis':resources,'logic_synthesis':resources['LUT']+resources['ALU'],'dsp_primitive_counts':dsp,
      'runtime_exceptions':sorted(MODIFIED|ADDED),'netlist_mapping_comparison':graphs,
      'component_receipt_sha256':sha(ROOT/'sim/temp/vibrato_components_09/verification.json'),
      'audio_receipt_sha256':sha(ROOT/'sim/temp/vibrato_audio_05/verification.json'),
      'retained_synthesis_warnings':warnings,'synthesis_os_exit_code':process['exit_code'],
      'synthesis_completion_evidence':'Caught-success Tcl marker, finished synthesis log, fresh VG/resource/log and full source hashes; original OS exit field retained verbatim','generated_at':datetime.now(timezone.utc).isoformat()}
    save(RUN/'synthesis_review.json',record)
    print(json.dumps({k:record[k] for k in ('result','netlist_sha256','resources_synthesis','logic_synthesis')},indent=2))
    print('PASS: qualified vibrato/display timing edits only, DSP unchanged, resources legal; fresh actual VG tests required before publication.')


def verify():
    manifest,saved=runtime_guard()
    review_record=load(RUN/'synthesis_review.json')
    vg=PROJECT/f'impl/gwsynthesis/{NAME}.vg'
    assert review_record['result']=='PASS' and sha(vg)==review_record['netlist_sha256']
    tests=('imu_id70_components_02','vibrato_components_09','vibrato_audio_05','vibrato_divide15_06','vibrato_display_timing_02','vibrato_top_04','vibrato_legacy_05','vibrato_physical_top_04',
           'vibrato_full_gate_03','vibrato_posture_gate_03','vibrato_adc_gate_03','vibrato_gesture_gate_03')
    test_records={name:receipt(name) for name in tests}
    for name,record in test_records.items():
        for path,digest in record['source_sha256'].items():
            norm=path.replace('\\','/')
            if norm in manifest and not (name in ('vibrato_components_09','vibrato_audio_05') and
                norm in ('rtl/game/touch_game_renderer.v','rtl/display/lcd_rgb_scan_480x272.v')) and norm!=DIVIDE_SOURCE:
                assert digest==manifest[norm],(name,norm)
        if 'netlist_sha256' in record:assert record['netlist_sha256']==sha(vg)
    gate=test_records['vibrato_posture_gate_03']
    assert gate['bench']=='tb_posture_id70_full_gate'
    for filename,script,cases in (('bank_write_audit.json','audit_vibrato_bank.py',384),
                                   ('gain_operand_audit.json','audit_vibrato_gain.py',128)):
        audit=load(RUN/filename)
        assert audit['result']=='PASS' and audit['netlist_sha256']==sha(vg)
        assert audit['boolean_cases']==cases and audit['tool_sha256']==sha(RUN/script)
    route=load(RUN/'route_process.json')
    assert route['status']=='EXITED' and route['exit_code']==0
    assert route['source_commit']==saved['head']
    assert route['launcher_sha256']==sha(ROOT/'tools/run_vibrato_gowin.py')
    assert Path(route['project']).resolve()==(PROJECT/f'{NAME}.gprj').resolve()
    assert not read(RUN/'route.stderr.log').strip()
    log=read(RUN/'route.stdout.log')
    assert 'PNR_TCL_FINISHED' in log and 'Placement and routing completed' in log and 'Bitstream generation completed' in log
    assert not re.search(r'\bERROR\b|\bPR0004\b|\b[1-9]\d*\s+(?:unrouted|unroute|unconnected)\b',log,re.I)
    route_warnings=[line for line in log.splitlines() if line.startswith('WARN ')]
    previous_route_log=read(BEFORE/'files'/f'gowin/neo_guitar_touch_game/impl/pnr/{NAME}.log')
    assert sorted(route_warnings)==sorted(line for line in previous_route_log.splitlines() if line.startswith('WARN ')),('new P&R warning',route_warnings)
    pnr=PROJECT/'impl/pnr'
    report=read(pnr/f'{NAME}.rpt.txt')
    timing=read(pnr/f'{NAME}_tr_content.html')
    resources={}
    for name in ('Logic','Register','CLS','BSRAM','DSP'):
        m=re.search(rf'^\s*{name}\s*\|\s*([\d.]+)/([\d.]+)',report,re.M)
        assert m
        used,total=map(float,m.groups());assert used<=total
        resources[name]={'used':used,'available':total}
    assert resources['DSP']['used']==115.5
    latches=re.findall(r'--(?:Logic|I/O) Register as Latch\s*\|\s*(\d+)/',report)
    assert len(latches)==2 and all(int(x)==0 for x in latches)
    clocks={}
    for clock,required in (('sys_clk_50m',50),('audio_clk_12m288',12.288)):
        hit=re.search(rf'<td>{clock}</td>\s*<td>([\d.]+)\(MHz\)</td>\s*<td>([\d.]+)\(MHz\)</td>',timing)
        assert hit and float(hit[1])==required and float(hit[2])>=required,clock
        clocks[clock]={'required_mhz':required,'fmax_mhz':float(hit[2])}
    for kind in ('Setup','Hold'):
        hit=re.search(rf'Numbers of {kind} Violated Endpoints</td>\s*<td>(\d+)</td>',timing)
        assert hit and int(hit[1])==0,kind
    cmd=read(pnr/'cmd.do')
    hit=re.search(r'^-d\s+(.+)$',cmd,re.M)
    assert hit and Path(hit[1].strip()).resolve()==vg.resolve()
    for key,value in (('place_option',4),('route_option',2),('route_maxfan',32),('clock_route_order',0),('correct_hold',1)):
        assert re.search(rf'^-{key}\s+{value}\s*$',cmd,re.M),key
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
    start=datetime.fromisoformat(load(RUN/'process.json')['started']).timestamp()
    route_start=datetime.fromisoformat(route['started']).timestamp()
    for p in (vg,PROJECT/f'impl/gwsynthesis/{NAME}.log',PROJECT/f'impl/gwsynthesis/{NAME}_syn_rsc.xml'):
        assert p.stat().st_mtime>=start,('stale synthesis',p)
    for p in (fs,pnr/f'{NAME}.log',pnr/f'{NAME}.rpt.txt',pnr/f'{NAME}_tr_content.html',pnr/'cmd.do'):
        assert p.stat().st_mtime>=route_start,('stale route artifact',p)
    assert sha(RUN/'protected_process_config.snapshot.json')==saved['hashes']['gowin/neo_guitar_touch_game/impl/neo_guitar_touch_game_process_config.json']
    old_record=load(BEFORE/'files/gowin/neo_guitar_touch_game/imu_id70_verification.json')
    assert old_record['bitstream_sha256']==saved['hashes'][f'gowin/neo_guitar_touch_game/impl/pnr/{NAME}.fs']
    test_summaries={}
    for name,record in test_records.items():
        logs=record['log_sha256']
        if isinstance(logs,str):logs={record['bench']:logs}
        test_summaries[name]=[line[2:] if line.startswith('# ') else line for bench in logs
           for line in read(ROOT/'sim/temp'/name/(bench+'.log')).splitlines() if 'PASS:' in line]
    artifacts={}
    for folder in (RUN,PROJECT/'impl/gwsynthesis',pnr):
        for p in folder.iterdir():
            if p.is_file() and p.suffix in ('.json','.log','.tcl','.vg','.fs','.html','.txt','.xml','.do','.py'):
                artifacts[rel(p)]=sha(p)
    for name in tests:
        for p in (ROOT/'sim/temp'/name).iterdir():
            if p.is_file() and p.suffix in ('.json','.log','.vh'):artifacts[rel(p)]=sha(p)
        for path in test_records[name]['source_sha256']:
            p=ROOT/path;artifacts[rel(p)]=sha(p)
    for p in (Path(__file__),ROOT/'tools/start_original_vibrato_build.ps1',
              ROOT/'docs/PERFORMANCE_VIBRATO.md',ROOT/'README.md',PROJECT/'README.md',ROOT/'tools/run_vibrato_gowin.py',ROOT/'tools/audit_vibrato_timing.py',
              ROOT/'sim/reference/vibrato/four_string_board_audio_chain_before.v'):
        artifacts[rel(p)]=sha(p)
    for path in load(RUN/'protected_user_files.json'):
        artifacts[path]=sha(ROOT/path)
    # Retain immutable old inputs required by the reference/unused-module
    # proofs. Baseline FS evidence is separate from the new bitstream.
    for p in BEFORE.rglob('*'):
        if p.is_file():artifacts[rel(p)]=sha(p)
    for path in ('build/vibrato/v2/source_archive/rtl/control/performance_vibrato_gesture.v',
                 'build/vibrato/v4/source_archive/rtl/game/touch_game_renderer.v',
                 'build/vibrato/v4/source_archive/rtl/display/lcd_rgb_scan_480x272.v'):
        artifacts[path]=sha(ROOT/path)
    record={'result':'PASS','generated_at':datetime.now(timezone.utc).isoformat(),
      'artifact_scope':{'kind':'original_gprj_performance_vibrato','project':rel(PROJECT/f'{NAME}.gprj'),'implementation':rel(PROJECT/'impl')},
      'validated_source_head':saved['head'],'source_state':'local vibrato implementation; protected user files preserved',
      'runtime_changes':sorted(MODIFIED|ADDED),'source_sha256':manifest,'artifacts_sha256':artifacts,
      'resources':resources,'clocks':clocks,'previous_release_resources':old_record['resources'],'previous_release_clocks':old_record['clocks'],
      'bitstream_sha256':sha(fs),'netlist_sha256':sha(vg),
      'violations':{'setup':0,'hold':0,'latch':0,'unrouted':0,'tested_audio_deadline':0,'tested_score_deadline':0,'tested_posture_deadline':0,'tested_vibrato_deadline':0},
      'netlist_mapping_comparison':review_record['netlist_mapping_comparison'],
      'reused_tests':{'imu_id70_components_02':'Unchanged reader/classifier/production256 calibration/I2C/touch closure, every declared input and tool hash checked against current files; not rerun'},
      'unelaborated_display_reuse':{'tests':['vibrato_components_09','vibrato_audio_05'],
        'compiled_only_changes':['rtl/game/touch_game_renderer.v','rtl/display/lcd_rgb_scan_480x272.v'],
        'proof':'Current static module dependency closure and original hash-bound ModelSim loading logs both exclude the two display modules. Original input hashes match archived V4 sources; every active audio/gesture/ROM/bench/tool byte unchanged. Independent frozen-display/scan every-clock proof qualifies the two edits. No actual VG run is reused from V2/V4.',
        'timing_edit_audit_sha256':sha(RUN/'display_timing_audit.json')},
      'tests':test_summaries,'test_receipts':{name:sha(ROOT/'sim/temp'/name/'verification.json') for name in tests},
      'exhaustive_audits':{'score_bank_boolean_cases':384,'four_voice_gain_operand_cases':128},
      'verification_scope':'Performance-only independent four-string three-tap recognition with immediate open-string release. Serial Q15 vibrato uses no added DSP and preserves every audio sample while inactive. Frozen production and independent active-modulation audio oracles; fresh actual full VG physical matrix/MPU/UART/game/audio/LCD.',
      'gate_limitations':'Only audited millisecond/I2C waiting counters and registered touch/ADC outputs are stimulated. Vibrato full VG bench drives physical matrix columns with production gesture/slide/sample timing; no fret/DDS/audio forces. Production256 IMU calibration and real115200 UART retained. No SDF; fresh post-route STA checked separately.',
      'adc_verification':'Fresh dedicated actual VG ADC test plus whole-top UART and ID70 posture gate tests. Unchanged RTL received different LUT mapping, so old netlist structural equality is not claimed or used instead of these fresh simulations.',
      'warnings':[line for line in log.splitlines() if 'WARN ' in line],
      'simulation_warning_policy':'Retain the existing run_velocity_gate exception only: prim_sim.v lines1860/1864/1868/1884/1888/1893/3130/3134/3138/3142/3313/3317, vopt-2697. All project warnings, other primitive warnings, errors and failed assertions reject publication.',
      'simulation_warning_counts':{name:sum(line.startswith('# ** Warning:') for line in
        read(ROOT/'sim/temp'/name/(record['bench']+'.log')).splitlines())
        for name,record in test_records.items() if 'netlist_sha256' in record},
      'hardware_status':'User accepted ID70 complete guitar and Flash power-cycle boot. New performance vibrato has not been board tested; no proxy programming or COM access.',
      'publication':{'authorized_same_name_overwrite':False,'path':'build/releases/touch_game/neo_guitar_touch_game_vibrato.fs','old_bitstream_sha256':old_record['bitstream_sha256'],'saved_before':rel(BEFORE)},
      'protected_files_and_index_preserved':True,
      'tool_fingerprints':{str(p):sha(p) for p in (
        Path('S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe'),
        Path('S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v'),
        Path('S:/BaiduNetdiskDownload/modelsim/win64/vlog.exe'),
        Path('S:/BaiduNetdiskDownload/modelsim/win64/vsim.exe'))},
      'margin_targets_met':resources['CLS']['used']/resources['CLS']['available']<=.95 and clocks['sys_clk_50m']['fmax_mhz']>=55 and clocks['audio_clk_12m288']['fmax_mhz']>=13.5}
    save(PROJECT/'vibrato_verification.json',record)
    print(json.dumps({k:record[k] for k in ('result','resources','clocks','violations','bitstream_sha256')},indent=2))
    return record


def publish(resume=False):
    assert not resume,'Inspect any interrupted archive explicitly'
    record=verify()
    release=ROOT/'build/releases/touch_game/p4_vibrato_20261023'
    destination=ROOT/record['publication']['path']
    assert not release.exists() and not destination.exists(),'Preserve existing release'
    release.mkdir(parents=True)
    for path in set(record['source_sha256'])|set(record['artifacts_sha256']):
        target=release/'evidence'/path;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/path,target);assert sha(target)==sha(ROOT/path)
    fs=PROJECT/f'impl/pnr/{NAME}.fs'
    shutil.copy2(fs,release/'neo_guitar_touch_game_vibrato.fs')
    shutil.copy2(PROJECT/'vibrato_verification.json',release/'verification.json')
    shutil.copy2(ROOT/'docs/PERFORMANCE_VIBRATO.md',release/'README.md')
    shutil.copy2(fs,destination)
    assert sha(destination)==sha(fs)==sha(release/'neo_guitar_touch_game_vibrato.fs')
    old=ROOT/'build/releases/touch_game/neo_guitar_touch_game_p4_posture.fs'
    assert sha(old)==record['publication']['old_bitstream_sha256'],'Keep accepted ID70 release unchanged'
    save(release/'archive.json',{'result':'PASS','published':rel(destination),'bitstream_sha256':sha(fs),
      'verification_sha256':sha(release/'verification.json'),'old_snapshot':rel(BEFORE),
      'generated_at':datetime.now(timezone.utc).isoformat()})
    print('Published original-project performance vibrato: '+str(destination))


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('stage',choices=('review','verify','publish','publish-resume'))
    args=parser.parse_args()
    if args.stage=='review':review()
    elif args.stage=='verify':verify()
    else:publish(resume=args.stage=='publish-resume')


if __name__=='__main__':main()
