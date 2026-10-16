"""Map explicit bank/registered controller boundaries in the ACTUAL full VG.

No guessed predecode net is forced. Bank reads start at its declared inputs;
range injection starts at registered controller phase/launch output ports so
all router and audio-chain combinational logic recomputes normally.
"""
from pathlib import Path
import re
import sys
from compare_synth_graph import parse

ROOT=Path(__file__).resolve().parent.parent


def generate(vg,directory):
    modules=parse(vg.read_text(encoding='utf-8'))
    bank=modules['game_p2_score_bank']
    inputs={k:bits for k,(kind,bits) in bank['ports'].items() if kind=='input'}
    required={'audio_clk_12m288_d':[None],'sys_clk_50m_d':[None],
        'read_enable_Z':[None],'display_read':[None],
        'address':list(range(10,-1,-1)),'display_address':list(range(10,-1,-1))}
    assert inputs==required,('inspect bank architectural inputs',inputs)
    cells={name:(kind,pins) for kind,name,pins in bank['cells']}
    expected={f'score_p{page}_b{block}' for page in range(2) for block in range(5)}
    assert {name for name,(kind,pins) in cells.items() if kind=='DPB'}==expected
    words=[int(x,16) for x in (ROOT/'mem/game_p2_static.mem').read_text().splitlines()]
    assert len(words)==2048 and all(word>>80==0 for word in words), 'Pruned group bits must be proven zero'
    # Explicitly terminate swept/split result ports too. We observe all raw
    # DPB bits below; leaving output names absent hides mapping diagnostics.
    outputs={name for name,(kind,bits) in bank['ports'].items() if kind=='output'}
    assert {'audio_page','display_page'}<=outputs
    connections=['.audio_clk_12m288_d(ac)','.sys_clk_50m_d(dc)',
        '.read_enable_Z(ar)','.display_read(dr)','.address(aa)',
        '.display_address(da)','.audio_page(ap)','.display_page(dp)']
    connections += [f'.{name}()' for name in sorted(outputs-{'audio_page','display_page'})]
    lines=['game_p2_score_bank dut('+',\n    '.join(connections)+');']
    for page in range(2):
        for block in range(5):
            name=f'score_p{page}_b{block}';kind,pins=cells[name]
            parameters=bank['params'][name]
            assert parameters['BIT_WIDTH_0']==parameters['BIT_WIDTH_1']=='16'
            assert parameters['READ_MODE0']==parameters['READ_MODE1']=="1'b0"
            assert pins['CLKA']=='audio_clk_12m288_d' and pins['CLKB']=='sys_clk_50m_d'
            assert pins['CEA']=='read_enable_Z' and pins['CEB']=='display_read'
            assert pins['ADA']=='{address[9:0],GND,GND,GND,GND}'
            assert pins['ADB']=='{display_address[9:0],GND,GND,GND,GND}'
            for port in ['A','B']:
                stem='a' if port=='A' else 'd'
                lines.append(f'assign {stem}{page}[{block*16}+:16]=dut.{name}.DO{port};')
        lines += [f"assign a{page}[95:80]=16'd0;",f"assign d{page}[95:80]=16'd0;"]
    (directory/'bank_actual_map.vh').write_text('\n'.join(lines)+'\n')

    control=modules['game_p2_window_controller'];ports=control['ports']
    phase_bits={int(m[1]) for name,(kind,bits) in ports.items()
        if kind=='output' and (m:=re.fullmatch(r'game_phase_(\d+)',name)) and bits==[None]}
    wanted={lane*32+bit for lane in range(4) for bit in range(27)}
    assert phase_bits==wanted,('inspect reachable 27-bit phase outputs',phase_bits^wanted)
    assert ports['launch']==('output',list(range(3,-1,-1)))
    velocity={int(m[1]) for name,(kind,bits) in ports.items()
        if kind=='output' and (m:=re.fullmatch(r'game_velocity_(\d+)',name)) and bits==[None]}
    assert velocity=={1,3,5,7},('inspect fixed velocity ports',velocity)
    lines=['force `RCORE.target_phase=inject_phase;','force `RCORE.launch=inject_launch;',
        "force `RCORE.note_velocity=8'haa;",'force `GCORE.launch=inject_launch;']
    lines += [f'force `GCORE.game_phase_{bit}=inject_phase[{bit}];' for bit in sorted(phase_bits)]
    lines += [f"force `GCORE.game_velocity_{bit}=1'b1;" for bit in sorted(velocity)]
    chain=modules['four_string_board_audio_chain']
    audible={int(m[1]) for name,(kind,bits) in chain['ports'].items()
        if kind=='output' and (m:=re.fullmatch(r'audible_phase_(\d+)',name)) and bits==[None]}
    assert audible==wanted,('inspect 27-bit audible phase outputs',audible^wanted)
    (directory/'range_actual_force.vh').write_text('\n'.join(lines)+'\n')
    observations=[f'assign g_audible[{bit}]=gate.u_audio.u_chain.audible_phase_{bit};' for bit in sorted(audible)]
    observations += [f"assign g_audible[{bit}]=1'b0;" for bit in sorted(set(range(128))-audible)]
    (directory/'range_actual_observe.vh').write_text('\n'.join(observations)+'\n')
    for bench in ['tb_game_p2_actual_bank_gate','tb_game_p2_range_gate']:
        (directory/f'{bench}.sv').write_bytes((ROOT/f'sim/tb/{bench}.sv').read_bytes())
    print('PASS: actual VG bank input/DPB map and registered 27-bit controller/audio output map; no predecode forcing')


if __name__=='__main__':generate(Path(sys.argv[1]),Path(sys.argv[2]))
