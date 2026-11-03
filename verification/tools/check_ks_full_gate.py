"""Full actual production VG versus full RTL; documented registered stimuli only."""
import sys,json,hashlib,re,shutil
from check_karplus_strong import ROOT,run
from compare_synth_graph import parse
dest=ROOT/'build/karplus_strong'/sys.argv[1];dest.mkdir(parents=True,exist_ok=False)
src=dest/'sources';src.mkdir()
vg=ROOT/'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
shutil.copy2(vg,dest/'actual.vg')
rtl=list((ROOT/'rtl').rglob('*.v'));headers=list((ROOT/'rtl/config').glob('*.vh'))
names=set()
for p in rtl:names.update(re.findall(r'\bmodule\s+(\w+)',p.read_text(encoding='utf-8-sig')))
pattern=re.compile(r'\b('+'|'.join(sorted(names,key=len,reverse=True))+r')\b')
manifest={}
for p in rtl:
    text=pattern.sub(lambda m:'rtlref_'+m[0],p.read_text(encoding='utf-8-sig'))
    for h in headers:text=text.replace('rtlref_'+h.name,h.name)
    text=text.replace('../config/',src.as_posix()+'/').replace('../../mem/',(ROOT/'mem').as_posix()+'/')
    (src/p.name).write_text(text,encoding='utf-8')
    manifest[p.relative_to(ROOT).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
for p in headers:
    shutil.copy2(p,src/p.name);manifest[p.relative_to(ROOT).as_posix()]=hashlib.sha256(p.read_bytes()).hexdigest()
mods=parse(vg.read_text());audit={}
for mod,expected in [('gt911_touch',{'touch_ready':('output',[None])}),('touch_gesture',{
    'click_Z':('output',[None]),'double_click_Z':('output',[None]),'click_x_Z':('output',list(range(8,-1,-1))),
    'click_y_Z':('output',list(range(8,-1,-1)))}),('mcp3208_pluck_frontend',{
    'pluck_valid_Z':('output',[3,2,1,0]),'velocity':('output',list(range(7,-1,-1)))})]:
    for port,value in expected.items():assert mods[mod]['ports'][port]==value,(mod,port)
    audit[mod]=expected
forces=["force gate.u_touch.touch_ready=1'b1;","force reference.u_touch.ready=1'b1;",
    'force gate.u_gesture.click_Z=click;','force reference.u_gesture.click=click;',
    'force gate.u_gesture.double_click_Z=dbl;','force reference.u_gesture.double_click=dbl;',
    'force gate.u_gesture.click_x_Z=cx;','force reference.u_gesture.click_x=cx;',
    'force gate.u_gesture.click_y_Z=cy;','force reference.u_gesture.click_y=cy;',
    'force gate.u_audio.u_adc.pluck_valid_Z=pluck;','force reference.u_audio.u_adc.pluck_valid=pluck;',
    'force gate.u_audio.u_adc.velocity=velocity;','force reference.u_audio.u_adc.velocity_level=velocity;']
(dest/'ks_gate_stimulus.vh').write_text('\n'.join(forces))
bench=ROOT/'sim/tb/tb_ks_full_gate.sv';shutil.copy2(bench,dest/bench.name)
(dest/'mapping.json').write_text(json.dumps({'ports':audit,'forces':forces,'scope':'No ROM/phase/note/audio-result forcing; full top, matrix columns and physical key'},indent=2))
run('vlib.log',['vlib.exe','work'],dest)
run('compile.log',['vlog.exe','-sv','+incdir+'+dest.as_posix()+'+'+src.as_posix(),
    'S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v',
    'actual.vg',*[str(p) for p in src.glob('*.v')],bench.name],dest)
log=run('simulation.log',['vsim.exe','-c','work.tb_ks_full_gate','-do','run -all; quit -f'],dest)
assert 'PASS:' in log
for p,digest in manifest.items():assert hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==digest,p
(dest/'verification.json').write_text(json.dumps({'result':'PASS','netlist_sha256':hashlib.sha256(vg.read_bytes()).hexdigest(),
    'source_sha256':manifest,'mapping':audit,'scope':'Complete actual production VG and complete RTL; registered touch/ADC stimuli only'},indent=2))
print(log[-1600:])
