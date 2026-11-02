"""Fresh synthesis/STA/netlist binding for the dual-interface bitstream."""
import argparse
from collections import Counter
from datetime import datetime
from pathlib import Path
import re,shutil,hashlib,zipfile
import xml.etree.ElementTree as ET
from bs4 import BeautifulSoup
from build_dual_score_transport import ROOT,BASE,PROJECT,NAME,guard,sha,load,save

IMPL=PROJECT.parent/'impl'
SYN=BASE/'synth_04'
PNR=BASE/'route_03'

def text(p):return p.read_text(encoding='utf-8-sig')
def completed(folder):
    r=load(folder/'process.json');assert r['status']=='EXITED' and r['exit_code']==0,r
    assert not text(folder/'stderr.log').strip()
    assert 'DUAL_TRANSPORT_BUILD_FINISHED' in text(folder/'stdout.log')
    assert not re.search(r'^\s*ERROR|\bPR0004\b',text(folder/'stdout.log'),re.M)
    return r

def receipt(folder):
    r=load(folder/'verification.json');assert r.get('result',r.get('status'))=='PASS',folder
    for p,h in r['source_sha256'].items():assert sha(ROOT/p)==h,(folder,p)
    for label,h in r['log_sha256'].items():
        name='simulation.log' if label=='simulation' else label+'.log'
        log=folder/name;assert sha(log)==h
        assert 'PASS:' in text(log) and not re.search(r'FAIL:|\*\* (?:Error|Fatal):',text(log))
    return r

def review():
    manifest=guard();assert manifest==load(SYN/'source_manifest.json')
    process=completed(SYN);receipt(BASE/'rtl_10')
    old=ET.parse(ROOT/f'build/song_slots_123/synth_02/{NAME}_syn_rsc.xml').getroot().attrib
    new=ET.parse(IMPL/f'gwsynthesis/{NAME}_syn_rsc.xml').getroot().attrib
    dsp=lambda x:{k:v for k,v in x.items() if k.startswith('T_MULT')}
    assert dsp(old)==dsp(new) and old['T_Bsram']==new['T_Bsram']
    number=lambda k:int(re.match(r'\d+',new['T_'+k])[0])
    resources={k:number(v) for k,v in [('LUT','Lut'),('ALU','Alu'),('Register','Register'),('BSRAM_logical','Bsram')]}
    assert resources['LUT']+resources['ALU']<=59904 and resources['Register']<=60780
    def warnings(p):return Counter(re.sub(r'":\d+\)','":LINE)',s) for s in text(p).splitlines() if s.startswith('WARN'))
    before=warnings(ROOT/'build/song_slots_123/synth_02/stdout.log');after=warnings(SYN/'stdout.log')
    # Parallel frame receivers feed one context-switched protocol kernel.
    # No additional diagnostic is accepted.
    expected_added=Counter()
    assert after-before==expected_added,list((after-before).elements())
    vg=IMPL/f'gwsynthesis/{NAME}.vg';assert sha(vg)==sha(SYN/vg.name)
    assert vg.stat().st_mtime>=datetime.fromisoformat(process['started']).timestamp()
    result=dict(result='PASS',source_sha256=manifest,netlist_sha256=sha(vg),resources_synthesis=resources,
        logic_synthesis=resources['LUT']+resources['ALU'],dsp_primitives=dsp(new),
        warning_count_before=sum(before.values()),warning_count_after=sum(after.values()),
        removed_warnings=list((before-after).elements()),new_warnings=list(expected_added.elements()),
        new_warning_review='No additional diagnostic after line-number normalization; protocol compute kernel shared by two private endpoint contexts.')
    save(SYN/'resource_review.json',result)
    print('PASS: synthesis resources/warnings; logic='+str(result['logic_synthesis']),flush=True)
    return result

def verify():
    synthesis=review();manifest=guard();assert manifest==load(PNR/'source_manifest.json')
    receipt(BASE/'query_tdm_02')
    process=completed(PNR);vg=IMPL/f'gwsynthesis/{NAME}.vg'
    assert sha(vg)==synthesis['netlist_sha256']
    audio=receipt(BASE/'full_gate_03');uart=receipt(BASE/'uart_gate_04')
    for folder,r in [(BASE/'full_gate_03',audio),(BASE/'uart_gate_04',uart)]:
        assert r['netlist_sha256']==sha(vg)==sha(folder/'actual.vg')
        assert r['mapping_sha256']==sha(folder/'mapping.json')
    mapping=load(BASE/'uart_gate_04/mapping.json')
    assert len(mapping['countdown_forces'])==46
    assert (BASE/'uart_gate_04/dual_uart_countdown.vh').read_text()=='\n'.join(mapping['countdown_forces'])+'\n'
    for link,period,kept,accelerated in [('0',5208,5,24),('1',434,6,50)]:
        row=mapping['countdown_audit'][link]
        assert (row['nominal_cycles'],row['kept_bits'],row['accelerated_cycles'])==(period,kept,accelerated)
        assert len(row['all_32_q'])==32
    coverage=re.search(r'coverage: sample=(\d+) PCM=(\d+) attacks=(\d+) pixels=(\d+)',text(BASE/'full_gate_03/simulation.log'))
    assert coverage and all(int(n)>=v for n,v in zip(coverage.groups(),(3000,3000,7,100000)))
    assert 'unique_menu_pixels=130560 builtin_previews=3 pending_blocked=2' in text(BASE/'full_gate_03/simulation.log')
    report=IMPL/f'pnr/{NAME}.rpt.txt';timing=IMPL/f'pnr/{NAME}_tr_content.html';fs=IMPL/f'pnr/{NAME}.fs'
    for p in [report,timing,fs]:
        assert sha(p)==sha(PNR/p.name)
        assert p.stat().st_mtime>=datetime.fromisoformat(process['started']).timestamp()
    resources={}
    for key in ['Logic','Register','CLS','BSRAM','DSP']:
        m=re.search(rf'^\s*{key}\s*\|\s*([\d.]+)/([\d.]+)',text(report),re.M);assert m
        used,available=map(float,m.groups());assert used<=available
        resources[key]=dict(used=used,available=available)
    assert resources['BSRAM']['used']==118 and resources['DSP']['used']==106.5
    rows=[[td.get_text(strip=True) for td in tr.find_all('td',recursive=False)] for tr in BeautifulSoup(text(timing),'html.parser').find_all('tr')]
    clocks={}
    for name,required in [('sys_clk_50m',50),('audio_clk_12m288',12.288),('ks_compute_clk',100)]:
        found=[r for r in rows if len(r)>=4 and r[1]==name and r[2].endswith('(MHz)') and r[3].endswith('(MHz)')];assert len(found)==1
        requested,actual=[float(v.replace('(MHz)','')) for v in found[0][2:4]]
        assert requested==required and actual>=required,(name,requested,actual)
        clocks[name]=dict(required_mhz=required,fmax_mhz=actual)
    for kind in ['Setup','Hold']:
        found=[r for r in rows if len(r)==2 and r[0]=='Numbers of '+kind+' Violated Endpoints']
        assert len(found)==1 and int(found[0][1])==0
    latches=re.findall(r'Register as Latch\s*\|\s*(\d+)/',text(report));assert len(latches)==2 and set(latches)=={'0'}
    route=text(PNR/'stdout.log')
    assert 'Placement and routing completed' in route and 'Bitstream generation completed' in route
    assert not re.search(r'\b[1-9]\d*\s+(?:unrouted|unconnected)\b',route,re.I)
    assert len(re.findall(r'WARN\s*\(PR1014\)',route))==2
    client=load(BASE/'client_release_audit.json');assert client['result']=='PASS'
    for name,key in [('android_apk','android_sha256'),('windows_zip','windows_sha256')]:assert sha(Path(client[name]))==client[key]
    before=load(BASE/'before/snapshot.json');assert sha(fs)!=before['bitstream_sha256']
    sources=load(BASE/'source_package_manifest.json');assert sources['result']=='PASS'
    assert sha(Path(sources['archive']))==sources['sha256']
    for name,h in sources['source_sha256'].items():assert manifest[name]==h
    assert sha(ROOT/'build/song_slots_123/verification.json')==before['previous_certificate_sha256']
    result=dict(result='PASS',created=datetime.now().astimezone().isoformat(),source_sha256=manifest,
        bitstream_sha256=sha(fs),netlist_sha256=sha(vg),fallback_bitstream_sha256=before['bitstream_sha256'],
        resources=resources,clocks=clocks,violations=dict(setup=0,hold=0,latch=0,unrouted=0),
        usb=dict(baudrate=115200,tx='U15',rx='V14',connector='DEBUG-USB2'),
        bluetooth=dict(baudrate=9600,tx='AB21',rx='AB22',connector='J8-9/10',module='JDY-23'),
        shared_import_capacity=1345,polyphony=4,model_states=32,sample_rate_hz=48000,builtin_slots=[1,2,3],pending_slots=[4,5],
        test_receipts={n:sha(BASE/n/'verification.json') for n in ['rtl_10','query_tdm_02','full_gate_03','uart_gate_04']},
        client_release_audit_sha256=sha(BASE/'client_release_audit.json'),physical_hardware_tested=False,
        baseline_snapshot_sha256=sha(BASE/'before/snapshot.json'),protected_files=before['protected'],
        source_package=dict(archive=sources['archive'],sha256=sources['sha256'],files=sources['files']),
        protocol_compute_kernels=1,private_context_bits=234,buffered_request_bytes_per_endpoint=28,
        scope='Parallel UART/frame receivers, one TDM protocol kernel and private session/ACK/cache/error contexts; shared importer BEGIN ownership; real-baud RTL BUSY/interleave/CRC/DPB/CDC. Complete current netlist UART integration uses audited high-counter-Q timing acceleration only (BLE5208->24 and USB434->50 cycles), plus registered touch readiness. Full current netlist audio/menu vs RTL and actual postroute STA. No SDF; no physical COM/BLE/programming.')
    save(BASE/'verification.json',result);return result,fs

def publish(result,fs):
    dest=ROOT/'build/releases/touch_game/ks_fifth_v2_lcd180_slots123_dual_uart_20261102'
    dest.mkdir(parents=True,exist_ok=False)
    shutil.copy2(fs,dest/f'{NAME}_ks_fifth_v2_lcd180_slots123_dual_uart.fs')
    for p,name in [(BASE/'verification.json','verification.json'),(BASE/'client_release_audit.json','client_release_audit.json'),
                   (ROOT/'docs/DUAL_SCORE_TRANSPORT.md','README.md'),(SYN/'source_manifest.json','source_manifest.json'),
                   (IMPL/f'pnr/{NAME}.rpt.txt','resource_report.txt'),(IMPL/f'pnr/{NAME}_tr_content.html','timing_report.html')]:shutil.copy2(p,dest/name)
    save(dest/'release_manifest.json',dict(result='PASS',files_sha256={p.name:sha(p) for p in dest.iterdir() if p.is_file()}))
    archive=Path(shutil.make_archive(str(dest),'zip',root_dir=dest.parent,base_dir=dest.name))
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for p in dest.iterdir():
            if p.is_file():assert hashlib.sha256(z.read(dest.name+'/'+p.name)).hexdigest()==sha(p)
    save(BASE/'release_check.json',dict(result='PASS',archive=str(archive),sha256=sha(archive),bitstream_sha256=result['bitstream_sha256']))
    print('PASS: published '+str(archive))

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('stage',choices=['review','verify','publish']);a=ap.parse_args()
    if a.stage=='review':review()
    else:
        r,fs=verify()
        if a.stage=='publish':publish(r,fs)
