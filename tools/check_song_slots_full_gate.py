"""Fresh complete production netlist vs RTL, including menu and real playback."""
import sys,json,hashlib,re,shutil
from check_karplus_strong import ROOT,run
from build_song_slots import BASE,sha,save,guard
from compare_synth_graph import parse

dest=BASE/sys.argv[1];dest.mkdir(parents=True,exist_ok=False)
src=dest/'sources';src.mkdir()
vg=ROOT/'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
shutil.copy2(vg,dest/'actual.vg')
rtl=list((ROOT/'rtl').rglob('*.v'));headers=list((ROOT/'rtl/config').glob('*.vh'))
names=set()
for p in rtl:names.update(re.findall(r'\bmodule\s+(\w+)',p.read_text(encoding='utf-8-sig')))
pattern=re.compile(r'\b('+'|'.join(sorted(names,key=len,reverse=True))+r')\b')
manifest={}
for p in rtl:
    body=pattern.sub(lambda m:'rtlref_'+m[0],p.read_text(encoding='utf-8-sig'))
    for h in headers:body=body.replace('rtlref_'+h.name,h.name)
    body=body.replace('../config/',src.as_posix()+'/').replace('../../mem/',(ROOT/'mem').as_posix()+'/')
    (src/p.name).write_text(body,encoding='utf-8');manifest[p.relative_to(ROOT).as_posix()]=sha(p)
for p in headers:shutil.copy2(p,src/p.name);manifest[p.relative_to(ROOT).as_posix()]=sha(p)
for p in (ROOT/'mem').glob('*'):manifest[p.relative_to(ROOT).as_posix()]=sha(p)
for name in ('tools/check_song_slots_full_gate.py','tools/check_karplus_strong.py','tools/compare_synth_graph.py'):
    manifest[name]=sha(ROOT/name)
mods=parse(vg.read_text());audit={}
for mod,expected in [('guitar_effect_buttons',{'harmony_enable_Z':('output',[None])}),('gt911_touch',{'touch_ready':('output',[None])}),('touch_gesture',{
    'click_Z':('output',[None]),'double_click_Z':('output',[None]),'click_x_Z':('output',list(range(8,-1,-1))),
    'click_y_Z':('output',list(range(8,-1,-1)))}),('mcp3208_pluck_frontend',{
    'pluck_valid_Z':('output',[3,2,1,0]),'velocity':('output',list(range(7,-1,-1)))}),
    ('touch_game_ui',{'page_Z':('output',[2,1,0]),'selected_slot_Z':('output',[2,1,0])})]:
    for port,value in expected.items():assert mods[mod]['ports'][port]==value,(mod,port)
    audit[mod]=expected
forces=["force gate.u_buttons.harmony_enable_Z=harmony_command;","force reference.u_buttons.harmony_enable=harmony_command;","force gate.u_touch.touch_ready=1'b1;","force reference.u_touch.ready=1'b1;",
    'force gate.u_gesture.click_Z=click;','force reference.u_gesture.click=click;',
    'force gate.u_gesture.double_click_Z=dbl;','force reference.u_gesture.double_click=dbl;',
    'force gate.u_gesture.click_x_Z=cx;','force reference.u_gesture.click_x=cx;',
    'force gate.u_gesture.click_y_Z=cy;','force reference.u_gesture.click_y=cy;',
    'force gate.u_audio.u_adc.pluck_valid_Z=pluck;','force reference.u_audio.u_adc.pluck_valid=pluck;',
    'force gate.u_audio.u_adc.velocity=velocity;','force reference.u_audio.u_adc.velocity_level=velocity;']
(dest/'ks_gate_stimulus.vh').write_text('\n'.join(forces))
def child(parent,kind):
    hits=[(k,n) for k,n,_ in mods[parent]['cells'] if k==kind]
    assert len(hits)==1,(parent,kind,hits)
    return hits[0]
hierarchy=[];parent='neo_guitar_touch_game_top'
for kind in ('guitar_touch_game_audio','game_p2_mode_router','game_p2_static_engine','game_p2_window_controller'):
    parent,name=child(parent,kind);hierarchy.append(name+(' ' if name.startswith('\\') else ''))
path='gate.'+'.'.join(hierarchy)
q={}
for kind,name,pins in mods[parent]['cells']:
    m=re.fullmatch(r'countdown_left\[(\d+)\]',pins.get('Q',''))
    if kind.startswith('DFF') and m:
        bit=int(m[1]);assert bit not in q and pins['CLK']=='audio_clk_12m288_d'
        q[bit]={'kind':kind,'instance':name,'pins':pins}
assert set(q)==set(range(32))
countdown=["force reference.u_audio.p2.u_router.engine.controller.countdown_left=32'd0;"]
countdown += [f"force {path}.{row['instance']}.Q=1'b0;" for bit,row in sorted(q.items())]
(dest/'p3_gate_countdown.vh').write_text('\n'.join(countdown)+'\n')
# Verify every physical initialization word independently of the bank reader.
bank=mods['game_p3_score_bank'];cells={n:p for k,n,p in bank['cells'] if k=='DPB'}
assert set(cells)=={f'score_p{page}_b{col}' for page in range(2) for col in range(5)}
words=[int(x,16) for x in (ROOT/'mem/game_p3_initial.mem').read_text().split()]
packed=[(w&((1<<25)-1))|(((w>>32)&((1<<25)-1))<<25)|(((w>>64)&2047)<<50)|(((w>>80)&65535)<<61) for w in words]
lib=ROOT  # library contents are read explicitly below, never inferred defaults
from pathlib import Path
lib=Path('S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v')
body=lib.read_text(encoding='latin1');a=body.index('module DPB (');b=body.index('endmodule',a)
defaults=dict(re.findall(r"parameter\s+(INIT_RAM_[0-9A-F]{2})\s*=\s*(256'h[0-9a-fA-F]+)",body[a:b]))
assert len(defaults)==64 and all(int(v.split("'h")[1],16)==0 for v in defaults.values())
for page in range(2):
    for col in range(5):
        params=bank['params'][f'score_p{page}_b{col}']
        assert params['BIT_WIDTH_0']==params['BIT_WIDTH_1']=='16'
        for block in range(64):
            key=f'INIT_RAM_{block:02X}'
            expected=sum(((packed[page*1024+block*16+i]>>(col*16))&65535)<<(16*i) for i in range(16))
            assert int(params.get(key,defaults[key]).split("'h")[1],16)==expected,(page,col,block)
mapping={'result':'PASS','slots_stimulus':forces,'slots_ports':audit,'countdown_q':q,'countdown_forces':countdown,
         'score_initialization_640_blocks':'PASS','vendor_library_sha256':sha(lib)}
mapping['scope']='Complete original VG and complete RTL; registered gesture/ADC/harmony commands, audited countdown Q waiting only; no ROM/phase/note/audio result forcing. Real first events/metadata for3 builtin slots; pending4/5 cannot start.'
save(dest/'mapping.json',mapping)
(dest/'slots_gate_observe.vh').write_text('if(gate.u_ui.page_Z!==reference.page || gate.u_ui.selected_slot_Z!==reference.selected_slot)$fatal(1,"FAIL: actual UI slot/page differs");\n')
bench=ROOT/'sim/tb/tb_song_slots_full_gate.sv'
body=bench.read_text().replace('../../../../mem/',(ROOT/'mem').as_posix()+'/')
(dest/bench.name).write_text(body);manifest[bench.relative_to(ROOT).as_posix()]=sha(bench)
run('vlib.log',['vlib.exe','work'],dest)
run('compile.log',['vlog.exe','-sv','+incdir+'+dest.as_posix()+'+'+src.as_posix(),
    'S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v',
    'actual.vg',*[str(p) for p in src.glob('*.v')],bench.name],dest)
assert '** Warning:' not in (dest/'compile.log').read_text()
log=run('simulation.log',['vsim.exe','-c','-onfinish','stop','work.tb_song_slots_full_gate','-do','run -all; quit -code 0 -f'],dest)
assert 'PASS:' in log and 'FAIL:' not in log
from check_ks_result import review_vendor_warnings
review_vendor_warnings(dest)
for p,digest in manifest.items():assert sha(ROOT/p)==digest,p
guard()
save(dest/'verification.json',{'result':'PASS','status':'PASS','netlist_sha256':sha(vg),
    'source_sha256':manifest,'mapping_sha256':sha(dest/'mapping.json'),'log_sha256':{'simulation':sha(dest/'simulation.log')},'scope':mapping['scope']})
print('\n'.join(s for s in log.splitlines() if 'coverage:' in s or 'PASS:' in s))
