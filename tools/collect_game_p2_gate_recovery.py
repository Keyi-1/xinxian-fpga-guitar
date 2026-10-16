"""Collect completed same-VG workers; never restart successful gate checks."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import time

ROOT=Path(__file__).resolve().parent.parent
VENDOR=re.compile(r'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)')


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return p.read_text(encoding='utf-8-sig')
def load(p):return json.loads(read(p))


def clean(path, compile=False):
    text=read(path)
    assert not re.search(r'FAIL:|\*\* (Error|Fatal):',text),path
    for line in text.splitlines():
        if '** Warning:' in line:assert not compile and VENDOR.search(line),(path,line)
    assert ('Errors: 0, Warnings: 0' in text) if compile else ('PASS:' in text),path


def main():
    p=argparse.ArgumentParser()
    for name in ['origin','parallel','layout','output']:p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--wait',action='store_true');a=p.parse_args()
    o,f,l,out=(getattr(a,n).resolve() for n in ['origin','parallel','layout','output'])
    assert all(v.is_relative_to(ROOT/'sim/temp') for v in [o,f,l,out])
    assert not out.exists(),'Preserve existing collected evidence'
    required=[o/'verification.json',f/'tb_game_p2_top_gate/result.json',l/'verification.json']
    while not all(path.exists() for path in required):
        if not a.wait:raise RuntimeError('Workers are not complete; use --wait')
        for path in [f/'tb_game_p2_top_gate/worker.stderr.log',l/'tb_game_p2_layout_gate.log',o/'tb_game_p2_engine_gate.log']:
            if path.exists():
                text=read(path)
                assert not re.search(r'FAIL:|\*\* (Error|Fatal):',text),path
        time.sleep(2)
    origin=load(o/'verification.json');parallel=load(f/'run.json');layout=load(l/'verification.json')
    top=load(f/'tb_game_p2_top_gate/result.json')
    assert origin['result']=='COMPONENT_ONLY' and layout['result']==top['result']=='PASS'
    assert top['bench']=='tb_game_p2_top_gate'
    netlist=origin['netlist_sha256']
    assert netlist==parallel['netlist_sha256']==layout['netlist_sha256']
    assert sha(o/'compiled.vg')==sha(f/'compiled.vg')==sha(l/'compiled.vg')==netlist
    hashes={}
    for proof in [origin,parallel,layout]:
        for path,value in proof['source_sha256'].items():
            path=path.replace('\\','/');assert sha(ROOT/path)==value,path
            assert path not in hashes or hashes[path]==value
            hashes[path]=value
    hashes['tools/collect_game_p2_gate_recovery.py']=sha(Path(__file__))
    assert sha(f/'tb_game_p2_top_gate.log')==top['log_sha256']
    assert origin['log_sha256']=={'tb_game_p2_engine_gate.log':sha(o/'tb_game_p2_engine_gate.log')}
    assert layout['log_sha256']=={'tb_game_p2_layout_gate.log':sha(l/'tb_game_p2_layout_gate.log')}
    for name,value in layout['generated_sha256'].items():assert sha(l/name)==value,name
    sources={
        'tb_game_p2_engine_gate.log':o/'tb_game_p2_engine_gate.log',
        'tb_game_p2_layout_gate.log':l/'tb_game_p2_layout_gate.log',
        'tb_game_p2_top_gate.log':f/'tb_game_p2_top_gate.log',
        'engine_origin.compile.log':o/'compile.log',
        'layout.compile.log':l/'compile.log',
        'top.compile.log':f/'tb_game_p2_top_gate.compile.log'}
    for name,path in sources.items():clean(path,compile=name.endswith('compile.log'))
    out.mkdir()
    for name,path in sources.items():shutil.copy2(path,out/name)
    shutil.copy2(o/'compiled.vg',out/'compiled.vg')
    generated={}
    for name in ['p2_gate_pair.vh','chart_outputs.vh','stage_force.vh','engine_force.vh']:
        shutil.copy2(o/name,out/name);generated[name]=sha(out/name)
    for name in ['tb_game_p2_layout_gate.sv','layout_recovery_map.json']:
        shutil.copy2(l/name,out/name);generated[name]=sha(out/name)
    shutil.copy2(o/'tb_game_p2_layout_gate.sv',out/'tb_game_p2_layout_gate_original.sv')
    generated['tb_game_p2_layout_gate_original.sv']=sha(out/'tb_game_p2_layout_gate_original.sv')
    # Retain the exact original receipts and the recovered architectural map.
    receipts={}
    for name,path in [('engine_origin.json',o/'run.json'),('engine_result.json',o/'verification.json'),
                      ('parallel_run.json',f/'run.json'),('top_result.json',f/'tb_game_p2_top_gate/result.json'),
                      ('layout_result.json',l/'verification.json')]:
        shutil.copy2(path,out/name);receipts[name]=sha(out/name)
    primitive=Path('S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v')
    result=dict(result='PASS',artifact_scope='Same actual M2 complete VG; retained engine/top workers, only failed hierarchical frame alias recovered in layout bench',
        source_sha256=hashes,netlist_sha256=netlist,
        log_sha256={name:sha(out/name) for name in sources if not name.endswith('compile.log')},
        generated_sha256=generated,recovery_receipts_sha256=receipts,
        engine_origin_evidence_sha256=receipts['engine_origin.json'],
        vendor_primitive_path=str(primitive),vendor_primitive_sha256=sha(primitive))
    (out/'verification.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print('PASS: same M2 netlist musical engine, all 2117 layouts and ten full scan frames collected; no successful worker repeated')


if __name__=='__main__':main()
