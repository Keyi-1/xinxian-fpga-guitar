"""Audit scoped JDY-23 changes and original-project implementation."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import shutil
import xml.etree.ElementTree as ET
import zipfile

R=Path(__file__).resolve().parents[1]
E=R/'build/jdy23/v1'
P=R/'gowin/neo_guitar_touch_game'
NAME='neo_guitar_touch_game'
BASE=R/'build/releases/touch_game/tail_lock_20261025'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return p.read_text(encoding='utf-8-sig',errors='replace')
def load(p):return json.loads(read(p))
def save(p,v):p.write_text(json.dumps(v,indent=2)+'\n')

def guard():
    manifest=load(E/'source_manifest.json'); baseline=load(E/'baseline.json')
    changed=set()
    for name,digest in manifest.items():
        assert sha(R/name)==digest,name
        if digest!=baseline['source_sha256'][name]:changed.add(name)
    assert changed==set(baseline['changed'])=={'constraints/neo_guitar_touch_game.cst','rtl/top/neo_guitar_touch_game_top.v'}
    old=(E/'before/rtl/top/neo_guitar_touch_game_top.v').read_bytes()
    assert (R/'rtl/top/neo_guitar_touch_game_top.v').read_bytes()==old.replace(b'UART_CLKS_PER_BIT=434,',b'UART_CLKS_PER_BIT=5208,',1)
    cst=read(R/'constraints/neo_guitar_touch_game.cst')
    pins=dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+);',cst))
    before=dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+);',read(E/'before/constraints/neo_guitar_touch_game.cst')))
    assert {k for k in pins if pins[k]!=before[k]}=={'song_uart_tx','song_uart_rx'}
    assert pins['song_uart_tx']=='AB21' and pins['song_uart_rx']=='AB22'
    assert len(pins)==len(set(pins.values()))==63
    for name,item in load(E/'protected_user_files.json').items():
        assert sha(R/name)==item['sha256'],name
        assert subprocess.check_output(['git','ls-files','--stage','--',name],cwd=R,text=True).strip()==item['index']
    assert sha(P/f'{NAME}.gprj')==manifest[f'gowin/{NAME}/{NAME}.gprj']
    return manifest,pins

def synthesis():
    manifest,pins=guard()
    receipt=load(E/'process.json'); log=read(E/'build.stdout.log')
    assert receipt['status']=='EXITED' and receipt['exit_code']==0
    assert 'SYNTHESIS_TCL_FINISHED' in log and 'GowinSynthesis finish' in log
    assert not read(E/'build.stderr.log').strip()
    assert not re.search(r'^ERROR|inferr?ed.*latch|latch.*inferr?ed',log,re.I|re.M)
    old=read(BASE/'evidence'/f'gowin/{NAME}/impl/gwsynthesis/{NAME}.log')
    normalize=lambda s:s.split('("',1)[0].strip()
    allowed={normalize(s) for s in old.splitlines() if s.startswith('WARN ')}
    assert all(normalize(s) in allowed for s in log.splitlines() if s.startswith('WARN '))
    resource=ET.parse(P/f'impl/gwsynthesis/{NAME}_syn_rsc.xml').getroot().attrib
    prior=ET.parse(BASE/'evidence'/f'gowin/{NAME}/impl/gwsynthesis/{NAME}_syn_rsc.xml').getroot().attrib
    assert {k:v for k,v in resource.items() if k.startswith('T_MULT')}=={k:v for k,v in prior.items() if k.startswith('T_MULT')}
    n=lambda key:int(re.match(r'\d+',resource['T_'+key])[0])
    resources={'Logic':n('Lut')+n('Alu'),'Register':n('Register'),'BSRAM_logical':n('Bsram')}
    assert resources['Logic']<=59904 and resources['Register']<=60780 and resources['BSRAM_logical']<=118
    vg=P/f'impl/gwsynthesis/{NAME}.vg'
    assert vg.stat().st_mtime>=datetime.fromisoformat(receipt['started']).timestamp()
    result={'result':'PASS','netlist_sha256':sha(vg),'resources':resources,
        'source_manifest_sha256':sha(E/'source_manifest.json'),'pins':{k:pins[k] for k in ('song_uart_tx','song_uart_rx')},
        'unchanged_runtime_sources':len(manifest)-2}
    save(E/'synthesis_review.json',result);print(json.dumps(result))

def route_result():
    manifest,pins=guard()
    review=load(E/'synthesis_review.json')
    vg=P/f'impl/gwsynthesis/{NAME}.vg'
    assert review['result']=='PASS' and review['netlist_sha256']==sha(vg)
    receipt=load(E/'route_process.json');body=read(E/'route.stdout.log')
    assert receipt['status']=='EXITED' and receipt['exit_code']==0,'Existing routing is incomplete/failed; do not publish or restart it'
    assert Path(receipt['project']).resolve()==(P/f'{NAME}.gprj').resolve()
    assert not read(E/'route.stderr.log').strip()
    assert all(marker in body for marker in ('PNR_TCL_FINISHED','Placement and routing completed','Bitstream generation completed'))
    assert not re.search(r'\bERROR\b|\bPR0004\b|\b[1-9]\d*\s+(?:unrouted|unroute|unconnected)\b',body,re.I)
    previous=read(BASE/'evidence'/f'gowin/{NAME}/impl/pnr/{NAME}.log')
    assert sorted(line for line in body.splitlines() if line.startswith('WARN '))==sorted(line for line in previous.splitlines() if line.startswith('WARN '))
    pnr=P/'impl/pnr';report=read(pnr/f'{NAME}.rpt.txt');timing=read(pnr/f'{NAME}_tr_content.html')
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
    assert len(latches)==2 and all(int(n)==0 for n in latches)
    cmd=read(pnr/'cmd.do')
    assert Path(re.search(r'^-d\s+(.+)$',cmd,re.M)[1].strip()).resolve()==vg.resolve()
    for key,value in [('place_option',4),('route_option',2),('route_maxfan',32),('clock_route_order',0),('correct_hold',1)]:
        assert re.search(rf'^-{key}\s+{value}\s*$',cmd,re.M),key
    rows={}
    for line in report.splitlines():
        fields=[v.strip() for v in line.split('|')]
        if len(fields)>8 and fields[0] in pins:rows[fields[0]]=fields
    for port,ball in pins.items():
        assert rows[port][2].split('/')[0]==ball and rows[port][3]=='Y',port
        assert rows[port][7]==('LVCMOS15' if port.startswith('USER_BUTTON') else 'LVCMOS33'),port
    fs=pnr/f'{NAME}.fs';assert fs.stat().st_size>10000000
    for file in (fs,pnr/f'{NAME}.rpt.txt',pnr/f'{NAME}_tr_content.html',pnr/f'{NAME}.log'):
        assert file.stat().st_mtime>=datetime.fromisoformat(receipt['started']).timestamp()
    result={'result':'PASS','resources':resources,'clocks':clocks,'setup_violations':0,'hold_violations':0,
        'latches':0,'unrouted':0,'bitstream_sha256':sha(fs),'netlist_sha256':sha(vg),
        'pins_checked':len(pins),'original_project':str(P/f'{NAME}.gprj')}
    save(E/'route_review.json',result)
    return result

def package():
    implementation=route_result();manifest,pins=guard()
    tests={}
    for key,path in [('rtl',E/'sim_9600_02/verification.json'),('gate_rx',E/'uart_rx_gate/verification.json'),
        ('android',E/'android_test/verification.json'),('config',E/'config_verification.json')]:
        record=load(path);assert record['result']=='PASS';tests[key]={'path':str(path.relative_to(R)),'sha256':sha(path)}
        if key=='gate_rx':assert record['netlist_sha256']==implementation['netlist_sha256']
        if key=='rtl':
            for name,digest in record['source_sha256'].items():assert sha(R/name)==digest,name
    android=load(R/'build/p5_bluetooth/jdy23/v1/android/verification.json')
    apk=Path(android['apk']);assert android['compiled'] and android['signature_verified'] and sha(apk)==android['sha256']
    assert android['compiled_resources_and_dex_match'] and android['test_source_sha256_verified']
    for name,digest in android['source_sha256'].items():assert sha(R/name)==digest,name
    assert load(E/'config_verification.json')['source_sha256']==sha(R/'firmware/jdy23/configure_jdy23.ps1')
    reference=R/'build/p5_bluetooth/diagnostic_v2_clock_20261026/reference_clock_restore_v2.bin'
    assert sha(reference)=='79ac33d154ebe64a7df91fcfa4f76df3f466ca2685d78c1f5f48e4250b8761b3'
    example=R/'build/p5_bluetooth/example/qing_ge.bin'
    import zlib
    assert len(example.read_bytes())==212*16 and zlib.crc32(example.read_bytes())==0xc3451bbc
    release=R/'build/releases/touch_game/jdy23_20261027'
    assert not release.exists(),'Never overwrite a published release'
    release.mkdir()
    files={
        'neo_guitar_touch_game_jdy23_9600.fs':P/f'impl/pnr/{NAME}.fs',
        'xinxian_jdy23.apk':apk,'README.md':R/'firmware/jdy23/README.md',
        'configure_jdy23.ps1':R/'firmware/jdy23/configure_jdy23.ps1',
        'example/qing_ge.bin':example,'example/qing_ge.json':example.with_suffix('.json'),
        'optional_clock_restore/xinxian_clock_restore_bl616_secondary_0x40000_v2.bin':reference}
    for name,source in files.items():
        target=release/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
        assert target.read_bytes()==source.read_bytes()
    for name in manifest:
        target=E/'source_archive'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(R/name,target)
    record={'result':'PASS','date':'2026-10-27','hardware_tested':False,'flash_performed':False,
        'protocol':'XG3 raw 32-byte frames over JDY-23 FFE0/FFE1','uart':{'baud':9600,'divisor':5208,'format':'8N1','tx':'AB21 / J8-9','rx':'AB22 / J8-10'},
        'baseline_fs_sha256':load(E/'baseline.json')['baseline_fs_sha256'],'source_sha256':manifest,
        'scope':'Only FPGA UART divider and two pin mappings changed; unchanged source reuse, no repeat of old full-chip/audio tests',
        'tests':tests,'implementation':implementation,'android':android,
        'files':{name:{'sha256':sha(release/name),'bytes':(release/name).stat().st_size} for name in files}}
    save(release/'verification.json',record);save(E/'verification.json',record)
    (release/'SHA256SUMS.txt').write_text('\n'.join(sha(p)+'  '+p.relative_to(release).as_posix() for p in sorted(release.rglob('*')) if p.is_file())+'\n')
    archive=release.with_suffix('.zip')
    with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as out:
        for p in sorted(release.rglob('*')):
            if p.is_file():out.write(p,'xinxian_jdy23/'+p.relative_to(release).as_posix())
    with zipfile.ZipFile(archive) as out:
        for p in release.rglob('*'):
            if p.is_file():assert out.read('xinxian_jdy23/'+p.relative_to(release).as_posix())==p.read_bytes()
    save(E/'archive_verification.json',{'result':'PASS','zip':str(archive),'sha256':sha(archive)})
    print(json.dumps({'release':str(release),'zip':str(archive),'bitstream_sha256':implementation['bitstream_sha256'],'clocks':implementation['clocks'],'hardware_tested':False},indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('stage',choices=('synthesis','route','package'))
    args=parser.parse_args()
    if args.stage=='synthesis':synthesis()
    elif args.stage=='route':print(json.dumps(route_result()))
    else:package()
