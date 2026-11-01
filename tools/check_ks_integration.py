from pathlib import Path
import sys,json,hashlib
from check_karplus_strong import ROOT,run

dest=ROOT/'build/karplus_strong'/sys.argv[1]
dest.mkdir(parents=True,exist_ok=False)
files=['rtl/synth/karplus_strong_voice.v','rtl/synth/piano_voice_core.v','rtl/synth/piano_hammer_model.v','rtl/synth/piano_mode_state_ram.v','rtl/synth/piano_rock_gain_rom.v']
def prepare(text):
    return text.replace('../config/',(ROOT/'rtl/config').as_posix()+'/').replace('../../mem/',(ROOT/'mem').as_posix()+'/')
for name in files:(dest/Path(name).name).write_text(prepare((ROOT/name).read_text()))
import subprocess
old_text=subprocess.check_output(['git','show','d5d8599:rtl/synth/piano_voice_core.v'],cwd=ROOT).decode('utf-8')
(dest/'legacy.v').write_text(prepare(old_text).replace('module piano_voice_core','module legacy_piano_voice_core'))
run('vlib.log',['vlib.exe','work'],dest)
run('compile.log',['vlog.exe','-sv','S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v',*[Path(p).name for p in files],'legacy.v',str(ROOT/'sim/tb/tb_ks_integration.sv')],dest)
log=run('simulation.log',['vsim.exe','-c','work.tb_ks_integration','-do','run -all; quit -f'],dest)
assert 'PASS:' in log
(dest/'verification.json').write_text(json.dumps({'result':'PASS','baseline':'d5d8599','source_sha256':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in files}},indent=2))
print(log[-2000:])
