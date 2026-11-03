from pathlib import Path
import sys,json,hashlib
from check_karplus_strong import ROOT,run
dest=ROOT/'build/karplus_strong'/sys.argv[1];dest.mkdir(parents=True,exist_ok=False)
names=['synth/karplus_strong_voice.v','synth/ks_compute_pll.v','synth/ks_tdm_bank.v','synth/piano_voice_core.v','synth/piano_hammer_model.v','synth/piano_mode_state_ram.v','synth/piano_rock_gain_rom.v','audio_io/four_voice_piano_audio_core.v','control/reset_sync.v','control/timbre_blend_smoother.v','audio_io/sample_tick_gen.v']
for name in names:
    p=ROOT/'rtl'/name
    text=p.read_text(encoding='utf-8').replace('../config/',(ROOT/'rtl/config').as_posix()+'/').replace('../../mem/',(ROOT/'mem').as_posix()+'/')
    (dest/p.name).write_text(text,encoding='utf-8')
run('vlib.log',['vlib.exe','work'],dest)
run('compile.log',['vlog.exe','-sv','S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v',*[Path(n).name for n in names],str(ROOT/'sim/tb/tb_ks_tdm.sv')],dest)
log=run('simulation.log',['vsim.exe','-c','work.tb_ks_tdm','-do','run -all; quit -f'],dest)
assert 'PASS:' in log
(dest/'verification.json').write_text(json.dumps({'result':'PASS','source_sha256':{n:hashlib.sha256((ROOT/'rtl'/n).read_bytes()).hexdigest() for n in names}},indent=2))
print(log[-1500:])
