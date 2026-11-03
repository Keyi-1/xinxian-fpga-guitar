import sys,json,hashlib
import numpy as np
from check_karplus_strong import ROOT,run
dest=ROOT/'build/karplus_strong'/sys.argv[1];dest.mkdir(parents=True,exist_ok=False)
paths=['rtl/control/phase_slide_smoother.v','sim/reference/ks/phase_slide_before.v','sim/tb/tb_ks_slide_equivalence.sv']
for name in paths:
    p=ROOT/name;body=p.read_text().replace('../config/',(ROOT/'rtl/config').as_posix()+'/')
    (dest/p.name).write_text(body)
run('vlib.log',['vlib.exe','work'],dest)
run('compile.log',['vlog.exe','-sv',*[p.split('/')[-1] for p in paths]],dest)
log=run('simulation.log',['vsim.exe','-c','work.tb_ks_slide_equivalence','-do','run -all; quit -f'],dest)
assert 'PASS:' in log
for bits in (21,22,27):
    for start in range(0,1<<bits,1<<20):
        x=np.arange(start,min(start+(1<<20),1<<bits),dtype=np.uint64)
        q=(x>>1)+(x>>5);q=q+(q>>8);q=q+(q>>16);q=q>>3
        remainder=((x&31)+(q&31)-((q&1)<<4))&31
        assert np.array_equal(q+(remainder>=15),x//15),(bits,start)
(dest/'verification.json').write_text(json.dumps({'result':'PASS','exact_div15_exhaustive_widths':[21,22,27],
    'frozen_steps':240000,'source_sha256':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in paths}},indent=2))
print('PASS: 240000 frozen steps and exhaustive shift/add division for21/22/27-bit input domains')
