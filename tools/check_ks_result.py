"""Strict, hash-bound local KS release gate. Never programs hardware or pushes Git."""
import argparse,hashlib,json,re,subprocess,shutil
from bs4 import BeautifulSoup
from pathlib import Path
from datetime import datetime
ROOT=Path(__file__).resolve().parents[1]
E=ROOT/'build/karplus_strong'
P=ROOT/'gowin/neo_guitar_touch_game'
NAME='neo_guitar_touch_game'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def text(p):return p.read_text(encoding='utf-8-sig')
def review_vendor_warnings(folder):
    # Exact vendor source sites reviewed against the installed simulation model.
    # RAM warnings arise in inactive wider-width branches; PLL warnings describe
    # suppression of sensitivity-list self-triggering. Reject every other site.
    allowed={2697:{1860,1864,1868,1884,1888,1893,3130,3134,3138,3142,3313,3317},
             13162:{16253,16484,16579,16674,16769,16855,16941}}
    warnings=[line for line in text(folder/'simulation.log').splitlines() if '** Warning:' in line]
    for line in warnings:
        match=re.search(r'prim_sim.v\((\d+)\): \(vopt-(\d+)\)',line)
        assert match and int(match[1]) in allowed.get(int(match[2]),set()),line
    library=Path('S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v')
    review={'result':'PASS','warning_count':len(warnings),'unique_warnings':sorted(set(warnings)),
            'simulation_sha256':sha(folder/'simulation.log'),'library_sha256':sha(library),
            'review':'Exact reviewed vendor RAM-width/PLLA sensitivity sites only; no application warning.'}
    (folder/'warning_review.json').write_text(json.dumps(review,indent=2))

def verify():
    assert subprocess.check_output(['git','rev-parse','--short=7','HEAD'],cwd=ROOT,text=True).strip()=='d5d8599'
    protected=load(E/'before/protected.json')
    for p,v in protected.items():
        assert sha(ROOT/p)==v['sha256'],p
        assert subprocess.check_output(['git','ls-files','--stage','--',p],cwd=ROOT).decode()==v['index'],p
    synth=E/'synth_distance_01';route=E/'route_distance_01'
    manifest=load(synth/'source_manifest.json')
    assert manifest==load(route/'source_manifest.json')
    for p,v in manifest.items():assert sha(ROOT/p)==v,p
    for folder in (synth,route):
        proc=load(folder/'process.json');assert proc['status']=='EXITED' and proc['exit_code']==0,proc
        log=text(folder/'stdout.log')
        assert 'KS_BUILD_FINISHED' in log and not re.search(r'^ERROR|\bPR0004\b',log,re.M),folder
        assert not text(folder/'stderr.log').strip(),folder
    vg=P/f'impl/gwsynthesis/{NAME}.vg';tested_vg=synth/f'{NAME}.vg'
    code=lambda p:re.sub(r'//[^\n]*','',text(p))
    if sha(vg)==sha(tested_vg):
        proof={'result':'PASS','method':'Byte-identical netlist','before_sha256':sha(tested_vg),'after_sha256':sha(vg)}
    else:
        # Only a generated comment may differ; functional changes fail closed.
        assert code(vg)==code(tested_vg)
        proof=load(route/'auto_graph_equivalence.json')
        assert proof['result']=='PASS' and proof['before_sha256']==sha(tested_vg)
        assert proof['after_sha256']==sha(vg)==sha(route/'auto_synthesis.vg')
        assert proof['checker_sha256']==sha(ROOT/'tools/compare_synth_graph.py')
    tests={}
    for name in ('tdm_shared_ram_01','full_gate_distance_01'):
        folder=E/name;record=load(folder/'verification.json');assert record['result']=='PASS'
        for p,v in record['source_sha256'].items():
            p=p.replace('\\','/');p=p if p.startswith('rtl/') else 'rtl/'+p
            assert sha(ROOT/p)==v,(name,p)
        if name.startswith('full_gate'):
            assert record['netlist_sha256']==sha(tested_vg)==sha(folder/'actual.vg')
            assert code(folder/'actual.vg')==code(vg)
            assert sha(folder/'tb_ks_full_gate.sv')==sha(ROOT/'sim/tb/tb_ks_full_gate.sv')
            review_vendor_warnings(folder)
        log=text(folder/'simulation.log');assert 'PASS:' in log and not re.search(r'\*\* (Error|Fatal):',log)
        tests[name]=sha(folder/'verification.json')
    slide=load(E/'slide_distance_01/verification.json');assert slide['result']=='PASS' and slide['frozen_steps']==240000
    for p,v in slide['source_sha256'].items():assert sha(ROOT/p)==v,p
    expected=subprocess.check_output(['git','show','d5d8599:rtl/control/phase_slide_smoother.v'],cwd=ROOT).decode().replace('module phase_slide_smoother','module ks_before_phase_slide_smoother')
    assert text(ROOT/'sim/reference/ks/phase_slide_before.v')==expected
    tests['slide_distance_01']=sha(E/'slide_distance_01/verification.json')
    basis=load(E/'lfsr_basis_proof.json');assert basis['result']=='PASS'
    assert basis['adopted_source_sha256']==sha(ROOT/'rtl/synth/karplus_strong_voice.v')
    metrics=load(E/'rtl_shared_ram_01/verification.json')
    for p,v in metrics['source_sha256'].items():assert sha(ROOT/p.replace('\\','/'))==v,p
    assert 'all32 regions independent, each144000 updates/nonzero energy' in text(E/'rtl_shared_ram_01/simulation.log')
    equivalence=load(E/'rtl_shared_ram_01/numeric_equivalence.json')
    assert equivalence['result']=='PASS' and equivalence['samples']==576000
    assert equivalence['old_sha256']==equivalence['new_sha256']==sha(E/'rtl_shared_ram_01/ks_pcm.txt')
    # This frozen comparison is deliberately reused only for unchanged pure
    # piano/wah paths. Its former local KS RAM implementation is not certified.
    frozen=load(E/'integration_final_01/verification.json');assert frozen['result']=='PASS'
    for p,v in frozen['source_sha256'].items():
        if p!='rtl/synth/karplus_strong_voice.v':assert sha(ROOT/p)==v,p
    assert '32000 unchanged piano/wah PCM' in text(E/'integration_final_01/simulation.log')
    tests['rtl_shared_ram_01']=sha(E/'rtl_shared_ram_01/verification.json')
    tests['numeric_equivalence']=sha(E/'rtl_shared_ram_01/numeric_equivalence.json')
    tests['lfsr_basis']=sha(E/'lfsr_basis_proof.json')
    tests['frozen_piano_wah_only']=sha(E/'integration_final_01/verification.json')
    report=text(P/f'impl/pnr/{NAME}.rpt.txt');timing=text(P/f'impl/pnr/{NAME}_tr_content.html')
    resources={}
    for n in ('Logic','Register','CLS','BSRAM','DSP'):
        m=re.search(rf'^\s*{n}\s*\|\s*([\d.]+)/([\d.]+)',report,re.M);assert m,n
        used,total=map(float,m.groups());assert used<=total,(n,used,total)
        resources[n]={'used':used,'available':total}
    clocks={}
    rows=[[td.get_text(strip=True) for td in tr.find_all('td',recursive=False)]
          for tr in BeautifulSoup(timing,'html.parser').find_all('tr')]
    for clock,required in [('sys_clk_50m',50),('audio_clk_12m288',12.288),('ks_compute_clk',100)]:
        matches=[r for r in rows if len(r)>=4 and r[1]==clock and r[2].endswith('(MHz)') and r[3].endswith('(MHz)')]
        assert len(matches)==1,(clock,matches)
        requested,actual=[float(v.replace('(MHz)','')) for v in matches[0][2:4]]
        assert requested==required and actual>=required,(clock,requested,actual)
        clocks[clock]={'required_mhz':required,'fmax_mhz':actual}
    for kind in ('Setup','Hold'):
        matches=[r for r in rows if len(r)==2 and r[0]=='Numbers of '+kind+' Violated Endpoints']
        assert len(matches)==1 and int(matches[0][1])==0,(kind,matches)
    latches=re.findall(r'Register as Latch\s*\|\s*(\d+)/',report)
    assert len(latches)==2 and all(int(n)==0 for n in latches)
    log=text(route/'stdout.log')
    assert 'Placement and routing completed' in log and 'Bitstream generation completed' in log
    assert not re.search(r'\b[1-9]\d*\s+(?:unrouted|unconnected)\b',log,re.I)
    fs=P/f'impl/pnr/{NAME}.fs'
    assert fs.stat().st_mtime>=datetime.fromisoformat(load(route/'process.json')['started']).timestamp()
    artifacts=[ROOT/'AGENTS.md',ROOT/'tools/generate_ks_reciprocal.py',E/'lfsr_basis_proof.json',ROOT/'tools/compare_synth_graph.py',ROOT/'docs/BRIGHT_KARPLUS_STRONG.md',ROOT/'README.md',vg,fs,P/f'impl/pnr/{NAME}.rpt.txt',P/f'impl/pnr/{NAME}_tr_content.html']
    artifacts += list((ROOT/'tools').glob('*karplus_strong.py'))+list((ROOT/'tools').glob('check_ks_*.py'))
    artifacts += list((ROOT/'sim/tb').glob('tb_ks*.sv'))+[ROOT/'sim/tb/tb_karplus_strong.sv']
    artifacts += list((ROOT/'sim/reference/ks').glob('*'))
    artifacts += [ROOT/p for p in subprocess.check_output(['git','diff','--name-only','--','*.gprj'],cwd=ROOT,text=True).splitlines()]
    artifacts += [E/'rtl_shared_ram_01'/n for n in ('normal_vs_sustain.wav','harmony_and_slide.wav','ks_pcm.txt')]
    for folder in (synth,route,E/'tdm_shared_ram_01',E/'full_gate_distance_01',E/'rtl_shared_ram_01',E/'slide_distance_01',E/'integration_final_01'):
        artifacts += [p for p in folder.iterdir() if p.is_file() and p.suffix in ('.json','.log','.tcl','.sv','.vh')]
    result={'result':'PASS','baseline':'d5d8599','created':datetime.now().astimezone().isoformat(),
        'polyphony':4,'models_per_voice':8,'model_states':32,'physical_compute_lanes':2,
        'synthesis_clock_mhz':100,'sample_rate_hz':48000,'source_sha256':manifest,
        'netlist_sha256':sha(vg),'tested_netlist_sha256':sha(tested_vg),'netlist_graph_equivalence':proof,'bitstream_sha256':sha(fs),'resources':resources,'clocks':clocks,
        'violations':{'setup':0,'hold':0,'latch':0,'unrouted':0,'tested_sample_deadline':0},
        'test_receipts':tests,'artifacts_sha256':{p.relative_to(ROOT).as_posix():sha(p) for p in artifacts},
        'scope':'FPGA real-time KS/TDM; complete production VG vs full RTL plus independent32-model state/audio/PCM checks and exact numerical state-compression proof; no SDF, separate complete post-route STA. Frozen reuse is pure piano/wah only.',
        'hardware_status':'Not programmed or board-listened; digital verification only; no COM or Git push.'}
    (E/'verification.json').write_text(json.dumps(result,indent=2))
    return result,fs
if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--publish',action='store_true');args=ap.parse_args()
    result,fs=verify()
    if args.publish:
        release=ROOT/'build/releases/touch_game/ks_tdm_32_20261101';release.mkdir(parents=True,exist_ok=False)
        shutil.copy2(fs,release/'neo_guitar_touch_game_ks_tdm_32.fs')
        shutil.copy2(E/'verification.json',release/'verification.json')
        shutil.copy2(ROOT/'docs/BRIGHT_KARPLUS_STRONG.md',release/'README.md')
        shutil.copy2(P/f'impl/pnr/{NAME}.rpt.txt',release/'resource_report.txt')
        shutil.copy2(P/f'impl/pnr/{NAME}_tr_content.html',release/'timing_report.html')
        shutil.copy2(E/'synth_distance_01/source_manifest.json',release/'source_manifest.json')
        for name in ('normal_vs_sustain.wav','harmony_and_slide.wav'):
            shutil.copy2(E/'rtl_shared_ram_01'/name,release/name)
        print(release)
    print(json.dumps({'result':'PASS','resources':result['resources'],'clocks':result['clocks'],'bitstream_sha256':result['bitstream_sha256']},indent=2))
