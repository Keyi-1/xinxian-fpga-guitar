"""Prove architectural elapsed Q nodes before accelerated actual-ROM coverage."""
from pathlib import Path
import re
import sys
from compare_synth_graph import parse


def generate(vg, output):
    module = parse(vg.read_text(encoding='utf-8'))['game_p2_window_controller']
    registers = [(kind, pins) for kind, name, pins in module['cells']
                 if re.fullmatch(r'elapsed\[\d+\]', pins.get('Q', ''))]
    assert len(registers) == 25
    assert {pins['Q'] for kind, pins in registers} == {f'elapsed[{bit}]' for bit in range(25)}
    assert all(kind == 'DFFRE' and pins['CLK'] == 'audio_clk_12m288_d' for kind, pins in registers)
    bits = {int(m[1]) for name, (kind, width) in module['ports'].items()
            if kind == 'output' and (m := re.fullmatch(r'game_phase_(\d+)', name)) and width == [None]}
    assert bits == {lane*32+bit for lane in range(4) for bit in range(27)}
    assert module['ports']['launch'] == ('output', [3, 2, 1, 0])
    assert module['ports']['fault_Z'] == ('output', [None])
    lines = [f'assign g_phase[{bit}]=`GCORE.game_phase_{bit};' for bit in sorted(bits)]
    lines += [f"assign g_phase[{bit}]=1'b0;" for bit in sorted(set(range(128))-bits)]
    (output/'seek_actual_map.vh').write_text('\n'.join(lines)+'\n')
    print('PASS: all 25 elapsed nodes are actual DFFRE Q outputs; all 108 used phase outputs mapped')


if __name__ == '__main__':
    generate(Path(sys.argv[1]), Path(sys.argv[2]))
