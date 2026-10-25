"""Certify only piano envelope compression and fret-release pitch retention."""
import argparse
import hashlib
import json
import re
import shutil
import xml.etree.ElementTree as ET
from datetime import datetime,timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
RUN=ROOT/'build/vibrato/piano_short_hold_v3'
PROJECT=ROOT/'gowin/neo_guitar_touch_game'
NAME='neo_guitar_touch_game'
BASE=ROOT/'build/releases/touch_game/p4_vibrato_20261023'
PIANO='rtl/synth/piano_voice_core.v'
PLAY='rtl/control/guitar_play_control.v'
RTL_TESTS=('piano_hold_audio_v3_01','piano_hold_control_01','piano_hold_physical_v3_01')
GATES=('piano_hold_adc_gate_02','piano_hold_full_gate_02','piano_hold_posture_gate_02','piano_hold_gesture_gate_02')
def read(p):return p.read_text(encoding='utf-8-sig')
def load(p):return json.loads(read(p))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,x):p.write_text(json.dumps(x,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def rel(p):return p.relative_to(ROOT).as_posix()
def code(s):return re.sub(r'/\*.*?\*/|//[^\n]*','',s,flags=re.S)

def source_guard():
    baseline=load(BASE/'verification.json');manifest=load(RUN/'source_manifest.json')
    assert baseline['result']=='PASS'
    assert set(manifest)==set(baseline['source_sha256'])
    changed=set()
    for p,digest in manifest.items():
        assert sha(ROOT/p)==digest==sha(RUN/'source_archive'/p),p
        if digest!=baseline['source_sha256'][p]:changed.add(p)
    assert changed=={PIANO,PLAY},changed
    # All piano logic outside these explicit substitutions remains frozen.
    assert sha(BASE/'evidence'/PIANO)==baseline['source_sha256'][PIANO]
    assert sha(BASE/'evidence'/PLAY)==baseline['source_sha256'][PLAY]
    expected=read(BASE/'evidence'/PIANO)
    current=read(ROOT/PIANO)
    replacements=[
      ('    reg [16:0] frame_age;','    reg [16:0] frame_age;\n    reg short_piano_note;'),
      ('    wire signed [17:0] hammer_operand_a;', '''    // Choose once at the strike so a timbre crossfade cannot jump the
    // envelope clock. Pure piano plays its measured body at twice the rate;
    // oscillator phase and the procedural hammer keep their original time.
    wire strike_is_piano=CONTROL_ENABLE==0 ||
        (timbre_blend==0 && (ROCK_ENABLE==0 || rock_blend==0));
    // Natural-end gating bounds a short note to age<=65535, including
    // inactive frames. Thus the doubled age cannot overflow 17 bits.
    wire [16:0] envelope_age=short_piano_note ?
        {frame_age[15:0],1'b0} : frame_age;
    wire natural_end=short_piano_note ? age>=(MAX_SAMPLES+1)/2-1 : age>=MAX_SAMPLES-1;

    wire signed [17:0] hammer_operand_a;'''),
      ('wire [7:0] frame = frame_age[16:9];','wire [7:0] frame = envelope_age[16:9];'),
      ("wire [9:0] envelope_fraction = {1'b0,frame_age[8:0]};",
       "wire [9:0] envelope_fraction = {1'b0,envelope_age[8:0]};"),
      ('            state<=IDLE; mode_index<=0; age<=0; frame_age<=0;',
       '            state<=IDLE; mode_index<=0; age<=0; frame_age<=0;\n            short_piano_note<=0;'),
      ('                        profile<=selected_profile; age<=0; frame_age<=0;',
       '                        profile<=selected_profile; age<=0; frame_age<=0;\n                        short_piano_note<=strike_is_piano;'),
      ('if(age >= MAX_SAMPLES-1 ||','if(natural_end ||')]
    for before,after in replacements:
        assert expected.count(before)==1,before
        expected=expected.replace(before,after,1)
    compact=lambda s:re.sub(r'\s+','',code(s))
    assert compact(expected)==compact(current),'Unscoped piano logic edit'
    old_play=code(read(BASE/'evidence'/PLAY))
    assert compact(read(ROOT/PLAY))==compact(old_play.replace('if (stable_valid || note_on[i])',
        'if ((stable_valid && stable_fret_id[i*4 +: 4]!=0) || note_on[i])',1))
    reference=ROOT/'sim/reference/vibrato/piano_short_before.v'
    assert read(reference)==read(BASE/'evidence'/PIANO).replace('module piano_voice_core #(',
        'module short_before_piano_voice_core #(',1)
    for p,item in load(RUN/'protected_user_files.json').items():
        assert sha(ROOT/p)==item['sha256']
        import subprocess
        assert subprocess.check_output(['git','ls-files','--stage','--',p],cwd=ROOT,text=True).strip()==item['index'].strip()
    return manifest,baseline

def receipt(name):
    folder=ROOT/'sim/temp'/name;record=load(folder/'verification.json')
    assert record['status']=='PASS',name
    logs=record['log_sha256'];logs=logs if isinstance(logs,dict) else {record['bench']:logs}
    for p,digest in record['source_sha256'].items():
        assert sha(ROOT/p)==digest,(name,p)
    for bench,digest in logs.items():
        file=folder/(bench+'.log');body=read(file)
        assert sha(file)==digest and 'PASS:' in body
        assert not re.search(r'FAIL:|\*\* (?:Error|Fatal):',body)
        warnings=[x for x in body.splitlines() if x.startswith('# ** Warning:')]
        assert all(re.search(r'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)',x) for x in warnings),warnings
    if 'netlist_sha256' in record:
        assert sha(folder/'compiled.vg')==record['netlist_sha256']==sha(PROJECT/f'impl/gwsynthesis/{NAME}.vg')
        assert sha(folder/'mapping.json')==record['mapping_sha256']
    return record

def synthesis():
    manifest,baseline=source_guard()
    for name in RTL_TESTS:receipt(name)
    process=load(RUN/'process.json');body=read(RUN/'build.stdout.log')
    assert process['status']=='EXITED' and process['exit_code']==0
    assert 'SYNTHESIS_TCL_FINISHED' in body and 'GowinSynthesis finish' in body
    assert not read(RUN/'build.stderr.log').strip()
    assert not re.search(r'^ERROR|inferr?ed.*latch|latch.*inferr?ed',body,re.I|re.M)
    oldlog=read(BASE/'evidence'/f'gowin/neo_guitar_touch_game/impl/gwsynthesis/{NAME}.log')
    norm=lambda x:x.split('("',1)[0].strip()
    allowed={norm(x) for x in oldlog.splitlines() if x.startswith('WARN ')}
    assert all(norm(x) in allowed for x in body.splitlines() if x.startswith('WARN '))
    attrs=ET.parse(PROJECT/f'impl/gwsynthesis/{NAME}_syn_rsc.xml').getroot().attrib
    old=ET.parse(BASE/'evidence'/f'gowin/neo_guitar_touch_game/impl/gwsynthesis/{NAME}_syn_rsc.xml').getroot().attrib
    assert {k:v for k,v in attrs.items() if k.startswith('T_MULT')}=={k:v for k,v in old.items() if k.startswith('T_MULT')}
    n=lambda k:int(re.match(r'\d+',attrs['T_'+k])[0])
    resources={'Logic':n('Lut')+n('Alu'),'Register':n('Register'),'BSRAM_logical':n('Bsram')}
    assert resources['Logic']<=59904 and resources['Register']<=60780 and resources['BSRAM_logical']<=118
    vg=PROJECT/f'impl/gwsynthesis/{NAME}.vg'
    assert vg.stat().st_mtime>=datetime.fromisoformat(process['started']).timestamp()
    record={'result':'PASS','netlist_sha256':sha(vg),'source_manifest_sha256':sha(RUN/'source_manifest.json'),
        'resources_synthesis':resources,'scope':'Only piano duration/body clock and fret-release held pitch; current RTL tests bound; unchanged DSP count'}
    save(RUN/'synthesis_review.json',record)
    print(json.dumps(record,indent=2))

def audits():
    source_guard()
    import audit_vibrato_bank,audit_vibrato_gain
    audit_vibrato_bank.main(RUN/'bank_write_audit.json')
    audit_vibrato_gain.main(RUN)

def verify():
    manifest,baseline=source_guard()
    review=load(RUN/'synthesis_review.json');vg=PROJECT/f'impl/gwsynthesis/{NAME}.vg'
    assert review['result']=='PASS' and review['netlist_sha256']==sha(vg)
    tests={name:receipt(name) for name in RTL_TESTS+GATES}
    for file,script,cases in [('bank_write_audit.json','audit_vibrato_bank.py',384),('gain_operand_audit.json','audit_vibrato_gain.py',128)]:
        audit=load(RUN/file)
        assert audit['result']=='PASS' and audit['netlist_sha256']==sha(vg)
        assert audit['boolean_cases']==cases and audit['tool_sha256']==sha(ROOT/'tools'/script)
    route=load(RUN/'route_process.json');body=read(RUN/'route.stdout.log')
    assert route['status']=='EXITED' and route['exit_code']==0
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
        used,total=map(float,hit.groups());assert used<=total
        resources[name]={'used':used,'available':total}
    assert resources['DSP']['used']==baseline['resources']['DSP']['used']
    latches=re.findall(r'--(?:Logic|I/O) Register as Latch\s*\|\s*(\d+)/',report)
    assert len(latches)==2 and all(int(x)==0 for x in latches)
    cmd=read(pnr/'cmd.do')
    for key,value in [('place_option',4),('route_option',2),('route_maxfan',32),('clock_route_order',0),('correct_hold',1)]:
        assert re.search(rf'^-{key}\s+{value}\s*$',cmd,re.M),key
    assert Path(re.search(r'^-d\s+(.+)$',cmd,re.M)[1].strip()).resolve()==vg.resolve()
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
    assert sha(ROOT/'build/releases/touch_game/neo_guitar_touch_game_p4_posture.fs')==baseline['publication']['old_bitstream_sha256']
    for file in (fs,pnr/f'{NAME}.rpt.txt',pnr/f'{NAME}_tr_content.html',pnr/f'{NAME}.log'):
        assert file.stat().st_mtime>=datetime.fromisoformat(route['started']).timestamp()
    paths={PIANO,PLAY,'tools/check_piano_hold_result.py','docs/PIANO_SHORT_HOLD.md'}
    paths.update({'tools/render_piano_short_ab.py','build/piano_short/audio/verification.json',
        'sim/temp/piano_hold_audio_v3_01/piano_decay_ab.txt'})
    paths.update(rel(p) for p in (ROOT/'build/piano_short/audio').glob('*.wav'))
    for folder in (RUN,PROJECT/'impl/gwsynthesis',pnr):
        paths.update(rel(p) for p in folder.iterdir() if p.is_file() and p.suffix in ('.json','.log','.tcl','.vg','.fs','.html','.txt','.xml','.do'))
    for name,record in tests.items():
        paths.update(p.replace('\\','/') for p in record['source_sha256'])
        folder=ROOT/'sim/temp'/name
        paths.update(rel(p) for p in folder.iterdir() if p.is_file() and p.suffix in ('.json','.log','.vh'))
    record={'result':'PASS','generated_at':datetime.now(timezone.utc).isoformat(),
        'source_sha256':manifest,'artifacts_sha256':{p:sha(ROOT/p) for p in sorted(paths)},
        'baseline_verification_sha256':sha(BASE/'verification.json'),'baseline_bitstream_sha256':baseline['bitstream_sha256'],
        'runtime_changes':[PIANO,PLAY],'resources':resources,'clocks':clocks,
        'violations':{'setup':0,'hold':0,'latch':0,'unrouted':0,'tested_deadline':0},
        'bitstream_sha256':sha(fs),'netlist_sha256':sha(vg),
        'test_receipts':{n:sha(ROOT/'sim/temp'/n/'verification.json') for n in tests},
        'piano_duration_samples':{'dry_before':131072,'dry_after':65536,'sustain_before':518141,'sustain_after':255997},
        'policy':'Fret release retains last pitch and natural envelope; real open pluck selects open. Three-tap vibrato remains performance-only.',
        'reuse':'Held-pitch/gesture control receipt reused because every declared input byte is unchanged; all other required receipts are current V3.',
        'hardware_status':'Not programmed or board tested; digital acceptance only. Effect reverberation tails retain original lengths.'}
    save(PROJECT/'piano_short_hold_verification.json',record)
    print(json.dumps({k:record[k] for k in ('result','resources','clocks','violations','bitstream_sha256')},indent=2))
    return record

def publish():
    record=verify();folder=ROOT/'build/releases/touch_game/piano_short_hold_20261025'
    destination=ROOT/'build/releases/touch_game/neo_guitar_touch_game_piano_short_hold.fs'
    assert not folder.exists() and not destination.exists()
    folder.mkdir()
    for p in set(record['source_sha256'])|set(record['artifacts_sha256']):
        target=folder/'evidence'/p;target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/p,target);assert sha(target)==sha(ROOT/p)
    shutil.copy2(PROJECT/'piano_short_hold_verification.json',folder/'verification.json')
    shutil.copy2(PROJECT/f'impl/pnr/{NAME}.fs',destination)
    shutil.copy2(destination,folder/destination.name)
    assert sha(destination)==record['bitstream_sha256']
    assert sha(ROOT/'build/releases/touch_game/neo_guitar_touch_game_vibrato.fs')==record['baseline_bitstream_sha256']
    save(folder/'archive.json',{'result':'PASS','published':rel(destination),'bitstream_sha256':sha(destination),
        'verification_sha256':sha(folder/'verification.json')})
    print('Published '+str(destination))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('stage',choices=['synthesis','audits','verify','publish'])
    args=parser.parse_args();globals()[args.stage]()
