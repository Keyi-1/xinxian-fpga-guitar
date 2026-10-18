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
    assert set(dpbs)=={f'score_p{p}_b{c}' for p in range(2) for c in range(5)},dpbs.keys()
    words=[int(x,16) for x in (Path(__file__).resolve().parent.parent/'mem/game_p3_initial.mem').read_text().splitlines()]
    packed=[]
    for word in words:
        physical=(word&((1<<25)-1)) | (((word>>32)&((1<<25)-1))<<25) | (((word>>64)&2047)<<50) | (((word>>80)&65535)<<61)
        restored=(physical&((1<<25)-1)) | (((physical>>25)&((1<<25)-1))<<32) | (((physical>>50)&2047)<<64) | (((physical>>61)&65535)<<80)
        assert restored==word
        packed.append(physical)
    lib=Path('S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v')
    library=lib.read_text(encoding='latin1');a=library.index('module DPB (');b=library.index('endmodule',a)
    defaults=dict(re.findall(r"parameter\s+(INIT_RAM_[0-9A-F]{2})\s*=\s*(256'h[0-9a-fA-F]+)",library[a:b]))
    assert len(defaults)==64 and all(int(v.split("'h")[1],16)==0 for v in defaults.values())
    defaulted=0
    for page in range(2):
        for col in range(5):
            name=f'score_p{page}_b{col}';params=bank['params'][name]
            assert params['BIT_WIDTH_0']==params['BIT_WIDTH_1']=='16'
            assert params['READ_MODE0']==params['READ_MODE1']=="1'b0"
            for block in range(64):
                expected=sum(((packed[page*1024+block*16+i]>>(col*16))&65535)<<(16*i) for i in range(16))
                key=f'INIT_RAM_{block:02X}'
                if key not in params:defaulted+=1
                actual=params.get(key,defaults[key])
                assert int(actual.split("'h")[1],16)==expected,(name,block)
    gain=modules['piano_rock_gain_rom'];gain_cells=[(n,p) for k,n,p in gain['cells'] if k=='DPB']
    assert len(gain_cells)==1
    from generate_piano_rock_gain_rom import values
    gains=values();gain_params=gain['params'][gain_cells[0][0]]
    assert gain_params['READ_MODE0']=="1'b0" and gain_params['BIT_WIDTH_0']=='16'
    for block in range(64):
        expected=sum(gains[block*16+i]<<(16*i) for i in range(16))
        key=f'INIT_RAM_{block:02X}';actual=gain_params.get(key,defaults[key])
        assert int(actual.split("'h")[1],16)==expected,('gain table',block)
    # Derive a component harness from actual DPB pin connectivity. Do not
    # guess synthesis-generated names or bypass any address/read/clock port.
    nets={name:{bit:(name if bit is None else f'{name}[{bit}]') for bit in bits}
          for name,bits in gain['declarations'].items()}
    def bits(expr):
        expr=expr.strip()
        if not expr:return []
        if expr.startswith('{'):
            assert expr.endswith('}')
            return [b for part in expr[1:-1].split(',') for b in bits(part)]
        m=re.fullmatch(r"(\d+)'([bdh])([0-9a-fA-F]+)",expr)
        if m:
            value=int(m[3],{'b':2,'d':10,'h':16}[m[2]])
            return [str((value>>i)&1) for i in reversed(range(int(m[1])))]
        m=re.fullmatch(r'(\w+)(?:\[(\d+)(?::(\d+))?\])?',expr)
        assert m and m[1] in nets,('gain pin expression',expr)
        if m[2] is None:return list(nets[m[1]].values())
        indices=[int(m[2])] if m[3] is None else list(range(int(m[2]),int(m[3])-1,-1))
        return [nets[m[1]][i] for i in indices]
    constants={}
    for kind,name,pins in gain['cells']:
        if kind in ['GND','VCC']:
            for expr in pins.values():
                for bit in bits(expr):constants[bit]='0' if kind=='GND' else '1'
    gp={p:[constants.get(b,b) for b in bits(expr)] for p,expr in gain_cells[0][1].items()}
    assert gp['ADA'][:3]==['0']*3 and gp['ADA'][-4:]==['0']*4
    drive={gp['CLKA'][0]:'clk',gp['CEA'][0]:'read_enable'}
    for index,bit in enumerate(reversed(gp['ADA'][3:10])):
        assert bit not in drive
        drive[bit]=f'address[{index}]'
    output={bit:f'gain_data[{index}]' for index,bit in enumerate(reversed(gp['DOA']))}
    connections=[];mapped_outputs=set()
    for port,(kind,indices) in gain['ports'].items():
        symbols=list(nets[port].values())
        if kind=='input':actual=[drive[b] for b in symbols]
        else:
            assert kind=='output'
            actual=[output[b] for b in symbols];mapped_outputs.update(actual)
        connections.append(f'.{port}('+ (actual[0] if len(actual)==1 else '{'+','.join(actual)+'}') +')')
    unmapped=[i for i in range(16) if f'gain_data[{i}]' not in mapped_outputs]
    assert all(all((v>>i)&1==0 for v in gains) for i in unmapped)
    harness=['piano_rock_gain_rom gain_dut('+','.join(connections)+');']
    harness += [f"assign gain_data[{i}]=1'b0;" for i in unmapped]
    (out/'p3_gate_gain.vh').write_text('\n'.join(harness)+'\n')
    report=dict(result='PASS',scope='Actual full VG; registered touch stimulus and all32 countdown Q only; no score/phase/launch injection',
        netlist_sha256=hashlib.sha256(vg.read_bytes()).hexdigest(),bank_dpb16=10,initial_rows=2048,initial_bits=96,physical_record_bits=77,
        gain_rom_entries=128,gain_rom_dpb16=1,
        gain_gate_connections=connections,gain_zero_output_bits=unmapped,
        countdown_registers={str(k):v for k,v in registers.items()},touch_ports=required,
        zero_init_parameters_elided=defaulted,primitive_library_sha256=hashlib.sha256(lib.read_bytes()).hexdigest())
    (out/'mapping.json').write_text(json.dumps(report,indent=2))
    print('PASS: actual VG 10 DPB16 / all2048 logical96-bit initial rows; exact gain ROM; touch ports/all32 countdown Q, no score/phase injection')


if __name__=='__main__':prepare(Path(sys.argv[1]),Path(sys.argv[2]))
