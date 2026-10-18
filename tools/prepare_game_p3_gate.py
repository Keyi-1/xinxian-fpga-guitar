"""Audit the actual full VG, map registered touch outputs/countdown Q only.

No guessed predecode, ROM value, phase or note-launch injection. The complete
top and actual UART/manager/DPB/readback/CDC/UI/audio/LCD wiring stay in place.
"""
from pathlib import Path
import hashlib,json,re,sys
from compare_synth_graph import parse


def prepare(vg,out):
    text=vg.read_text(encoding='utf-8');modules=parse(text)
    required={'gt911_touch':{'touch_ready':('output',[None])},
              'touch_gesture':{'click_Z':('output',[None]),'double_click_Z':('output',[None]),
                  'click_x_Z':('output',list(range(8,-1,-1))),'click_y_Z':('output',list(range(8,-1,-1)))},
              'touch_game_ui':{'page_Z':('output',[2,1,0])}}
    for name,ports in required.items():
        for port,expected in ports.items():assert modules[name]['ports'][port]==expected,(name,port)
    force=["force gate.u_touch.touch_ready=1'b1;","force reference.u_touch.ready=1'b1;",
        'force gate.u_gesture.click_Z=click;','force reference.u_gesture.click=click;',
        'force gate.u_gesture.double_click_Z=dbl;','force reference.u_gesture.double_click=dbl;',
        'force gate.u_gesture.click_x_Z=cx;','force reference.u_gesture.click_x=cx;',
        'force gate.u_gesture.click_y_Z=cy;','force reference.u_gesture.click_y=cy;']
    (out/'p3_gate_touch.vh').write_text('\n'.join(force)+'\n')
    control=modules['game_p2_window_controller'];registers={}
    for kind,name,pins in control['cells']:
        if kind.startswith('DFF') and (m:=re.fullmatch(r'countdown_left\[(\d+)\]',pins.get('Q',''))):
            registers[int(m[1])]=(kind,name,pins)
    assert set(registers)==set(range(32)),('inspect countdown Q coverage',registers.keys())
    qforce=['force reference.u_audio.p2.u_router.engine.controller.countdown_left=32\'d0;']
    for bit,(kind,name,pins) in sorted(registers.items()):
        assert pins['CLK']=='audio_clk_12m288_d',(bit,pins)
        qforce.append(f"force gate.u_audio.\\p2.u_router .engine.controller.{name}.Q=1'b0;")
    (out/'p3_gate_countdown.vh').write_text('\n'.join(qforce)+'\n')
    bank=modules['game_p3_score_bank'];dpbs={n:p for k,n,p in bank['cells'] if k=='DPB'}
    assert set(dpbs)=={f'score_p{p}_b{c}' for p in range(2) for c in range(6)},dpbs.keys()
    words=[int(x,16) for x in (Path(__file__).resolve().parent.parent/'mem/game_p3_initial.mem').read_text().splitlines()]
    lib=Path('S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v')
    library=lib.read_text(encoding='latin1');a=library.index('module DPB (');b=library.index('endmodule',a)
    defaults=dict(re.findall(r"parameter\s+(INIT_RAM_[0-9A-F]{2})\s*=\s*(256'h[0-9a-fA-F]+)",library[a:b]))
    assert len(defaults)==64 and all(int(v.split("'h")[1],16)==0 for v in defaults.values())
    defaulted=0
    for page in range(2):
        for col in range(6):
            name=f'score_p{page}_b{col}';params=bank['params'][name]
            assert params['BIT_WIDTH_0']==params['BIT_WIDTH_1']=='16'
            assert params['READ_MODE0']==params['READ_MODE1']=="1'b0"
            for block in range(64):
                expected=sum(((words[page*1024+block*16+i]>>(col*16))&65535)<<(16*i) for i in range(16))
                key=f'INIT_RAM_{block:02X}'
                if key not in params:defaulted+=1
                actual=params.get(key,defaults[key])
                assert int(actual.split("'h")[1],16)==expected,(name,block)
    report=dict(result='PASS',scope='Actual full VG; registered touch stimulus and all32 countdown Q only; no score/phase/launch injection',
        netlist_sha256=hashlib.sha256(vg.read_bytes()).hexdigest(),bank_dpb16=12,initial_rows=2048,initial_bits=96,
        countdown_registers={str(k):v for k,v in registers.items()},touch_ports=required,
        zero_init_parameters_elided=defaulted,primitive_library_sha256=hashlib.sha256(lib.read_bytes()).hexdigest())
    (out/'mapping.json').write_text(json.dumps(report,indent=2))
    print('PASS: actual VG 12 DPB16 / all2048x96 initial rows; exact touch output ports; all32 countdown Q mapped, no ROM/phase injection')


if __name__=='__main__':prepare(Path(sys.argv[1]),Path(sys.argv[2]))
