"""Adapt optimized Gowin chart ports to a repeat-update gate/RTL regression."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent

def main():
    netlist = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    source = netlist.read_text(encoding='utf-8')
    body = source[source.index('module game_chart_layout ('):]
    body = body[:body.index('endmodule')]
    ports = re.findall(r'^(input|output)\s+(?:\[([^]]+)\]\s+)?(\w+);', body, re.M)
    clock_nets = set(re.findall(r'\.CLK\((\w+)\)', body))
    reset_nets = set(re.findall(r'\.RESET\((\w+)\)', body))
    connections = []
    for direction, width, name in ports:
        if direction == 'input' and name in clock_nets:
            value = 'clk'
        elif direction == 'input' and name in reset_nets:
            value = '!rst_n'
        elif name == 'lcd_rst_n':
            value = 'rst_n'
        elif name == 'chart_update':
            value = 'snapshot_update'
        elif name == 'frame_start':
            value = 'frame_start'
        elif name.startswith('ui_game_snapshot_'):
            bit = int(name.rsplit('_', 1)[1])
            if bit >= 256 or width:
                raise ValueError(f'Unrecognized optimized snapshot port: {name} [{width}]')
            value = f'snapshot[{bit}]'
        elif direction == 'output' and name.startswith('valid_blocks'):
            if width != '31:0':
                raise ValueError(f'Unrecognized validity port: {name} [{width}]')
            value = 'g_blocks'
        elif name == 'centres':
            value = 'g_centres'
        elif name == 'tails':
            value = 'g_tails'
        elif direction == 'output' and name.startswith('chart_snapshot_'):
            bit = int(name.rsplit('_', 1)[1])
            if bit >= 256 or width:
                raise ValueError(f'Unrecognized optimized output: {name} [{width}]')
            value = f'g_snapshot[{bit}]'
        else:
            raise ValueError(f'Unsupported gate port: {direction} {name} [{width}]')
        connections.append(f'.{name}({value})')
    bench = r'''`timescale 1ns/1ps
`include "game_score_config.vh"
module tb_game_chart_gate;
GSR GSR (.GSRI(1'b1));
reg clk=0;always #10 clk=~clk;
reg rst_n=0,frame_start=0,snapshot_update=0;
reg [255:0] snapshot=0;
wire [31:0] g_blocks,r_blocks;
wire [383:0] g_centres,r_centres;
wire [287:0] g_tails,r_tails;
wire [255:0] g_snapshot,r_snapshot;
game_chart_layout gate(
''' + ',\n'.join(connections) + r''');
rtlref_game_chart_layout reference(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),.snapshot_update(snapshot_update),
.snapshot(snapshot),.centres(r_centres),.tails(r_tails),.valid_blocks(r_blocks),.display_snapshot(r_snapshot),
.overflow(),.deadline_miss());
integer i,t,passes=0;
task publish(input integer time_value);
 @(negedge clk);snapshot[159:128]=time_value;frame_start=1;
 @(negedge clk);frame_start=0;snapshot_update=1;
 @(negedge clk);snapshot_update=0;
 repeat(4000)@(negedge clk);
 if(reference.state!=0)$fatal(1,"FAIL: chart deadline");
 if(g_blocks!==r_blocks)$fatal(1,"FAIL: synthesized validity t=%0d gate=%h RTL=%h",time_value,g_blocks,r_blocks);
 for(i=0;i<32;i=i+1)if(r_blocks[i])begin
  if(g_centres[i*12+:12]!==r_centres[i*12+:12])$fatal(1,"FAIL: synthesized moving block t=%0d slot=%0d",time_value,i);
  if(g_tails[i*9+:9]!==r_tails[i*9+:9])$fatal(1,"FAIL: synthesized tail length");
 end
 passes=passes+1;
endtask
initial begin
 repeat(8)@(negedge clk);rst_n=1;
 publish(-96000);publish(-48000);publish(0);publish(24000);
 for(t=-96000;t<=`GAME_DURATION_SAMPLES;t=t+4800)publish(t);
 snapshot[0]=1;publish(0);snapshot[0]=0;publish(0);
 $display("PASS: synthesized chart %0d successive frames, countdown, moving blocks, per-lane reset and consumption match RTL",passes);
 $finish;
end
initial begin #100000000;$fatal(1,"FAIL: synthesized chart watchdog");end
endmodule
'''
    destination.write_text(bench, encoding='utf-8')
    print(f'Generated {destination.name}: {len(ports)} verified optimized ports')

if __name__ == '__main__':
    main()
