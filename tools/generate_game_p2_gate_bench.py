"""Expose only synthesized module ports and the countdown test counter.

Optimization shares ROM/catalog decode across module boundaries. Therefore the
tests keep the complete synthesized top and its actual bank-to-layout wiring.
No guessed predecode term is driven. The audio test shortens only the countdown
counter, then compares real serial output at the unchanged 256-clock cadence.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent


def main():
    vg, directory = Path(sys.argv[1]), Path(sys.argv[2])
    source = vg.read_text(encoding='utf-8')

    def body(name):
        a = source.index(f'module {name} (')
        return source[a:source.index('endmodule', a)]

    def ports(name):
        return re.findall(r'^(input|output)\s+(?:\[([^]]+)\]\s+)?(\w+);', body(name), re.M)

    assert re.search(r'^input \[2:0\] page_Z;', body('guitar_touch_game_display'), re.M)
    lines = ['force gate.u_display.page_Z=test_page;', 'force reference.u_display.page=test_page;',
             'force reference.u_display.selected_slot=test_selected;',
             'force reference.u_display.u_game_cdc.dst_snapshot=test_snapshot;',
             'force reference.u_display.u_game_cdc.dst_update=test_update;']
    selected_ports = [p for p in ports('guitar_touch_game_display') if p[0] == 'input' and p[2].startswith('selected_slot')]
    assert selected_ports == [('input', '1:0', 'selected_slot_Z')], selected_ports
    lines += ['force gate.u_display.selected_slot_Z=test_selected[1:0];']
    found = set()
    for direction, width, name in ports('game_snapshot_cdc'):
        if direction != 'output':
            continue
        if name == 'chart_update':
            lines.append(f'force gate.u_display.u_game_cdc.{name}=test_update;')
        else:
            m = re.fullmatch(r'ui_game_snapshot_(\d+)', name)
            assert m and not width, ('inspect changed CDC output', name, width)
            bit = int(m[1]);found.add(bit)
            lines.append(f'force gate.u_display.u_game_cdc.{name}=test_snapshot[{bit}];')
    required = set(range(64)) | set(range(64, 192)) | set(range(208, 228)) | {229,230,231,233,235,236} | set(range(238,256))
    assert required <= found, ('inspect missing snapshot bits', required-found)
    for module, instance, prefix, value, size in [
            ('guitar_visual_cdc', 'u_cdc', 'snapshot', 'test_visual', 400),
            ('guitar_radial_bands', 'u_bands', 'targets', 'test_targets', 160)]:
        observed = set()
        for direction, width, name in ports(module):
            if direction != 'output':
                continue
            if name == prefix:
                hi, lo = map(int, width.split(':'));observed.update(range(lo, hi+1))
                expression = f'{value}[{hi}:{lo}]'
            elif name.startswith(prefix+'_'):
                bit = int(name.rsplit('_', 1)[1]);assert not width and bit<size
                observed.add(bit);expression=f'{value}[{bit}]'
            else:
                continue
            lines.append(f'force gate.u_display.{instance}.{name}={expression};')
        expected = set(range(size)) if size == 160 else (
            set(range(272,400)) | {i*32+j for i in range(4) for j in range(16,32)} |
            {128+i*32+j for i in range(4) for j in range(27)})
        assert observed == expected, ('changed visual fields', observed^expected)
    lines += ['force reference.u_display.u_cdc.dst_snapshot=test_visual;',
              'force reference.u_display.u_bands.targets=test_targets;']
    (directory/'stage_force.vh').write_text('\n'.join(lines)+'\n')
    chart_path = r'gate.u_display.\p2.u_chart '
    connections = []
    observed = set()
    for direction, width, name in ports('game_p2_chart_layout'):
        m = re.fullmatch(r'centres_(\d+)', name)
        if direction == 'output' and m:
            bit = int(m[1]);observed.add(bit)
            connections.append(f'assign g_centres[{bit}]={chart_path}.{name};')
    assert observed == {i*12+j for i in range(32) for j in range(9)}, 'inspect eliminated coordinate bits'
    for bit in set(range(384))-observed:
        connections.append(f"assign g_centres[{bit}]=1'b0;")
    connections += [f'assign g_blocks={chart_path}.valid_blocks;',f'assign g_tails={chart_path}.tails;',
                    f'assign g_overflow={chart_path}.chart_overflow;', f'assign g_deadline={chart_path}.chart_deadline;']
    (directory/'chart_outputs.vh').write_text('\n'.join(connections)+'\n')
    assert re.search(r'^wire \[31:0\] countdown_left;', body('game_p2_window_controller'), re.M)
    assert re.search(r'^output \[3:0\] dst_command;', body('mode_command_cdc'), re.M)
    assert re.search(r'^output dst_command_valid;', body('mode_command_cdc'), re.M)
    for n in ['game_p2_static_engine engine (', 'game_p2_window_controller controller (']:
        assert n in source
    (directory/'engine_force.vh').write_text(
        '`define GCORE gate.u_audio.\\p2.u_router .engine.controller\n'
        '`define RCORE reference.u_audio.p2.u_router.engine.controller\n'
        'force gate.u_mode_cdc.dst_command=inject_command[3:0];\n'
        'force gate.u_mode_cdc.dst_command_valid=inject_valid;\n'
        'force reference.u_mode_cdc.dst_mode=inject_command;\n'
        'force reference.u_mode_cdc.dst_valid=inject_valid;\n')
    top = (ROOT/'sim/tb/tb_game_p2_top_gate.sv').read_text()
    a = top.index('    reg audio_clk=');b = top.index('    reg [2:0] test_page=', a)
    pair = top[a:b].replace('always #40.690104 audio_clk=~audio_clk;', 'always #40.690104 if(audio_run)audio_clk=~audio_clk;').replace(
        'always #10 sys_clk=~sys_clk;', 'always #10 if(sys_run)sys_clk=~sys_clk;')
    pair=pair.replace(".USER_BUTTON3_n(1'b1)",'.USER_BUTTON3_n(space_key)')
    (directory/'p2_gate_pair.vh').write_text('reg audio_run=1,sys_run=1,space_key=1;\n'+pair)
    for name in ['layout', 'engine']:
        (directory/f'tb_game_p2_{name}_gate.sv').write_text((ROOT/f'sim/tb/tb_game_p2_{name}_gate.sv').read_text())
    print('P2 gate mapping: complete top retained; checked CDC, visual ports, 288 live coordinate bits and countdown counter')


if __name__ == '__main__':
    main()
