"""Bind the complete guitar build to the one independently tested MPU change."""
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
RUN=ROOT/'build/imu_id70/v1'
BEFORE=ROOT/'build/imu_id70/before_20261023'
PROJECT=ROOT/'gowin/neo_guitar_touch_game'
NAME='neo_guitar_touch_game'
READER='rtl/input/mpu6050_reader.v'


def read(p):return p.read_text(encoding='utf-8-sig')
def load(p):return json.loads(read(p))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,data):p.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
def rel(p):return p.relative_to(ROOT).as_posix()
def git(*args):return subprocess.check_output(['git','-C',str(ROOT),*args],text=True,encoding='utf-8')


def runtime_guard():
    saved=load(BEFORE/'snapshot.json')
    assert git('rev-parse','HEAD').strip()==saved['head']
    assert git('ls-files','--stage')==saved['index'], 'Existing index changed'
    manifest=load(RUN/'source_manifest.json')
    changed=set()
    for path,digest in manifest.items():
        assert sha(ROOT/path)==digest==sha(RUN/'source_archive'/path),path
        if digest!=saved['hashes'][path]:changed.add(path)
    assert changed=={READER},('unrelated runtime changed',changed)
    frozen=read(ROOT/'sim/reference/imu_id70/mpu6050_reader_before_id70.v')
    assert frozen==read(BEFORE/'files'/READER).replace('module mpu6050_reader #(','module accepted_mpu6050_reader #(')
    for path,item in load(RUN/'protected_user_files.json').items():
        assert sha(ROOT/path)==item['sha256']==saved['hashes'][path]
        assert git('ls-files','--stage','--',path).strip()==item['index']
    return manifest,saved


def receipt(name):
    folder=ROOT/'sim/temp'/name
    record=load(folder/'verification.json')
    assert record.get('status',record.get('result'))=='PASS',name
    for path,digest in record['source_sha256'].items():assert sha(ROOT/path)==digest,(name,path)
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


def review():
    manifest,saved=runtime_guard()
    components=receipt('imu_id70_components_02')
    assert components['source_sha256'][READER]==manifest[READER]
    log=read(RUN/'build.stdout.log')
    process=load(RUN/'process.json')
    assert process['exit_code']==0 and 'SYNTHESIS_TCL_FINISHED' in log
    assert not read(RUN/'build.stderr.log').strip()
    assert not re.search(r'^\s*ERROR|inferr?ed.*latch|latch.*inferr?ed',log,re.I|re.M)
    resource=PROJECT/f'impl/gwsynthesis/{NAME}_syn_rsc.xml'
    current=ET.parse(resource).getroot().attrib
    old=ET.parse(BEFORE/'files'/rel(resource)).getroot().attrib
    dsp={k:v for k,v in current.items() if k.startswith('T_MULT')}
    assert dsp=={k:v for k,v in old.items() if k.startswith('T_MULT')}
    number=lambda key:int(re.match(r'\d+',current['T_'+key])[0])
    resources={k:number(v) for k,v in [('Register','Register'),('LUT','Lut'),('ALU','Alu'),('BSRAM_logical','Bsram')]}
    assert resources['LUT']+resources['ALU']<=59904 and resources['Register']<=60780 and resources['BSRAM_logical']<=118
    vg=PROJECT/f'impl/gwsynthesis/{NAME}.vg'
    started=datetime.fromisoformat(process['started']).timestamp()
    for p in (vg,resource,PROJECT/f'impl/gwsynthesis/{NAME}.log'):assert p.stat().st_mtime>=started
    before_modules=parse(read(BEFORE/'files'/rel(vg)))
    after_modules=parse(read(vg))
    graphs={}
    for module in ('guitar_touch_game_audio','guitar_touch_game_display','game_p3_score_bank','mcp3208_pluck_frontend'):
        old_graph=Graph(before_modules,module).signature()
        new_graph=Graph(after_modules,module).signature()
        # Same RTL can legally receive a different LUT mapping. Do not call
        # that structural equality; final verification requires fresh actual
        # VG simulations for all four areas, including the dedicated ADC.
        graphs[module]={'exact_graph_equal':old_graph==new_graph,'before':old_graph,'after':new_graph}
    record={'result':'PASS','source_commit':saved['head'],'source_state':'one local runtime edit, not committed by this task',
      'netlist_sha256':sha(vg),'source_manifest_sha256':sha(RUN/'source_manifest.json'),
      'resources_synthesis':resources,'logic_synthesis':resources['LUT']+resources['ALU'],'dsp_primitive_counts':dsp,
      'runtime_exception':READER,'component_receipt_sha256':sha(ROOT/'sim/temp/imu_id70_components_02/verification.json'),
      'netlist_mapping_comparison':graphs,'generated_at':datetime.now(timezone.utc).isoformat()}
    save(RUN/'synthesis_review.json',record)
    print(json.dumps({k:record[k] for k in ('result','netlist_sha256','resources_synthesis','logic_synthesis')},indent=2))
    print('PASS: only MPU runtime source changed, resources legal. Differently mapped modules require fresh actual VG tests before publication.')


def verify():
    manifest,saved=runtime_guard()
    review_record=load(RUN/'synthesis_review.json')
    vg=PROJECT/f'impl/gwsynthesis/{NAME}.vg'
    assert review_record['result']=='PASS' and sha(vg)==review_record['netlist_sha256']
    tests=('imu_id70_components_02','imu_id70_top_01','imu_id70_legacy_02',
           'imu_id70_full_gate_01','imu_id70_posture_gate_01','imu_id70_adc_gate_01')
    test_records={name:receipt(name) for name in tests}
    for name,record in test_records.items():
        for path,digest in record['source_sha256'].items():
            norm=path.replace('\\','/')
            if norm in manifest:assert digest==manifest[norm],(name,norm)
        if 'netlist_sha256' in record:assert record['netlist_sha256']==sha(vg)
    gate=test_records['imu_id70_posture_gate_01']
    assert gate['bench']=='tb_posture_id70_full_gate'
    for filename,script,cases in (('bank_write_audit.json','audit_quarter_bank.py',384),
                                   ('gain_operand_audit.json','audit_quarter_gain.py',128)):
        audit=load(RUN/filename)
        assert audit['result']=='PASS' and audit['netlist_sha256']==sha(vg)
        assert audit['boolean_cases']==cases and audit['tool_sha256']==sha(RUN/script)
    route=load(RUN/'route_process.json')
    assert route['exit_code']==0
    assert not read(RUN/'route.stderr.log').strip()
    log=read(RUN/'route.stdout.log')
    assert 'PNR_TCL_FINISHED' in log and 'Placement and routing completed' in log and 'Bitstream generation completed' in log
    assert not re.search(r'\bERROR\b|\bPR0004\b|\b[1-9]\d*\s+(?:unrouted|unroute|unconnected)\b',log,re.I)
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
    old_record=load(BEFORE/'files/gowin/neo_guitar_touch_game/quarter_dynamics_verification.json')
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
    for p in (Path(__file__),ROOT/'tools/start_original_imu_id70_build.ps1',
              ROOT/'docs/IMU_ID70_COMPATIBILITY.md',ROOT/'sim/reference/imu_id70/mpu6050_reader_before_id70.v'):
        artifacts[rel(p)]=sha(p)
    for path in load(RUN/'protected_user_files.json'):
        artifacts[path]=sha(ROOT/path)
    record={'result':'PASS','generated_at':datetime.now(timezone.utc).isoformat(),
      'artifact_scope':{'kind':'original_gprj_complete_guitar_id70_compatibility','project':rel(PROJECT/f'{NAME}.gprj'),'implementation':rel(PROJECT/'impl')},
      'validated_source_head':saved['head'],'source_state':'local uncommitted repair; existing index preserved',
      'runtime_changes':[READER],'source_sha256':manifest,'artifacts_sha256':artifacts,
      'resources':resources,'clocks':clocks,'previous_release_resources':old_record['resources'],'previous_release_clocks':old_record['clocks'],
      'bitstream_sha256':sha(fs),'netlist_sha256':sha(vg),
      'violations':{'setup':0,'hold':0,'latch':0,'unrouted':0,'tested_audio_deadline':0,'tested_score_deadline':0,'tested_posture_deadline':0},
      'netlist_mapping_comparison':review_record['netlist_mapping_comparison'],
      'tests':test_summaries,'test_receipts':{name:sha(ROOT/'sim/temp'/name/'verification.json') for name in tests},
      'exhaustive_audits':{'score_bank_boolean_cases':384,'four_voice_gain_operand_cases':128},
      'verification_scope':'ID70 component GPIO and complete production RTL/VG posture integration, ID68 frozen cycle equality; UART/game/audio/LCD actual full VG; unchanged 6050 profile and all non-MPU runtime bytes guarded.',
      'gate_limitations':'Whole-top posture bench accelerates audited millisecond/I2C divider waiting and stimulates registered touch/ADC events. Production256 calibration and real audio clocks retained. UART bench retains real115200 timing. No SDF back-annotation; post-route timing checked separately.',
      'adc_verification':'Fresh dedicated actual VG ADC test plus whole-top UART and ID70 posture gate tests. Unchanged RTL received different LUT mapping, so old netlist structural equality is not claimed or used instead of these fresh simulations.',
      'warnings':[line for line in log.splitlines() if 'WARN ' in line],
      'simulation_warning_policy':'Retain the existing run_velocity_gate exception only: prim_sim.v lines1860/1864/1868/1884/1888/1893/3130/3134/3138/3142/3313/3317, vopt-2697. All project warnings, other primitive warnings, errors and failed assertions reject publication.',
      'simulation_warning_counts':{name:sum(line.startswith('# ** Warning:') for line in
        read(ROOT/'sim/temp'/name/(record['bench']+'.log')).splitlines())
        for name,record in test_records.items() if 'netlist_sha256' in record},
      'hardware_status':'User confirmed separate ID70 diagnostic PASS LIVE, incrementing count and tilt response. New complete guitar image has not been programmed or board tested by this task.',
      'publication':{'authorized_same_name_overwrite':True,'path':'build/releases/touch_game/neo_guitar_touch_game_p4_posture.fs','old_bitstream_sha256':old_record['bitstream_sha256'],'saved_before':rel(BEFORE)},
      'protected_files_and_index_preserved':True,
      'tool_fingerprints':{str(p):sha(p) for p in (
        Path('S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe'),
        Path('S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v'),
        Path('S:/BaiduNetdiskDownload/modelsim/win64/vlog.exe'),
        Path('S:/BaiduNetdiskDownload/modelsim/win64/vsim.exe'))},
      'margin_targets_met':resources['CLS']['used']/resources['CLS']['available']<=.95 and clocks['sys_clk_50m']['fmax_mhz']>=55 and clocks['audio_clk_12m288']['fmax_mhz']>=13.5}
    save(PROJECT/'imu_id70_verification.json',record)
    print(json.dumps({k:record[k] for k in ('result','resources','clocks','violations','bitstream_sha256')},indent=2))
    return record


def publish(resume=False):
    record=verify()
    release=ROOT/'build/releases/touch_game/p4_imu_id70_20261023'
    if release.exists():
        assert resume and not (release/'archive.json').exists(),'Preserve completed release'
        assert sha(release/'neo_guitar_touch_game_p4_posture.fs')==record['bitstream_sha256']
    destination=ROOT/record['publication']['path']
    assert sha(destination)==record['publication']['old_bitstream_sha256'],'Published image changed since snapshot'
    release.mkdir(parents=True,exist_ok=resume)
    def copy_exact(source,target):
        if target.exists() and sha(source)==sha(target):return
        shutil.copy2(source,target)
        assert sha(target)==sha(source)
    for path in set(record['source_sha256'])|set(record['artifacts_sha256']):
        target=release/'evidence'/path;target.parent.mkdir(parents=True,exist_ok=True)
        copy_exact(ROOT/path,target)
    fs=PROJECT/f'impl/pnr/{NAME}.fs'
    copy_exact(fs,release/'neo_guitar_touch_game_p4_posture.fs')
    shutil.copy2(PROJECT/'imu_id70_verification.json',release/'verification.json')
    shutil.copy2(ROOT/'docs/IMU_ID70_COMPATIBILITY.md',release/'README.md')
    shutil.copy2(BEFORE/'snapshot.json',release/'baseline_snapshot.json')
    # Only replace the authorized same-name publication after all evidence exists.
    temporary=destination.with_suffix('.fs.id70_pending')
    if temporary.exists():
        assert resume and sha(temporary)==record['bitstream_sha256'],'Inspect previous pending image'
    else:shutil.copy2(fs,temporary)
    assert sha(temporary)==record['bitstream_sha256']
    # Gowin creates read-only FS files. The user explicitly authorized this
    # target's replacement; clear that attribute only for the atomic rename.
    previous_mode=destination.stat().st_mode
    os.chmod(destination,previous_mode|stat.S_IWRITE)
    try:os.replace(temporary,destination)
    except Exception:
        os.chmod(destination,previous_mode)
        raise
    os.chmod(destination,previous_mode)
    assert sha(destination)==sha(fs)==sha(release/'neo_guitar_touch_game_p4_posture.fs')
    save(release/'archive.json',{'result':'PASS','published':rel(destination),'bitstream_sha256':sha(fs),
      'verification_sha256':sha(release/'verification.json'),'old_snapshot':rel(BEFORE),
      'generated_at':datetime.now(timezone.utc).isoformat()})
    print('Published original guitar impl and same-name release: '+str(destination))


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('stage',choices=('review','verify','publish','publish-resume'))
    args=parser.parse_args()
    if args.stage=='review':review()
    elif args.stage=='verify':verify()
    else:publish(resume=args.stage=='publish-resume')


if __name__=='__main__':main()
