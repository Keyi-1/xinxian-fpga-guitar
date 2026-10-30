"""Exercise RX from the actual new synthesized UART, without repeating old full-chip tests."""
import hashlib
import argparse
import json
from pathlib import Path
import re
import subprocess

R=Path(__file__).resolve().parents[1]
E=R/'build/jdy23/v1/uart_rx_gate'
VG=R/'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
BIN=Path('S:/BaiduNetdiskDownload/modelsim/win64')

def run():
    assert not E.exists(),'Preserve completed/failed gate evidence'
    E.mkdir()
    text=VG.read_text(encoding='utf-8-sig')
    module=re.search(r'^module game_p3_uart \([\s\S]*?^endmodule',text,re.M)[0]
    inputs=re.findall(r'^input\s+(?:\[([^]]+)\]\s+)?(\w+);',module,re.M)
    signals={'sys_clk_50m_d':'clk','n562_6':'!rst_n','song_uart_rx_d':'rx'}
    connections=['.'+name+'('+signals.get(name,"'0")+')' for width,name in inputs]
    connections+=['.rx_valid_Z(rx_valid)','.rx_error(framing_error)','.rx_data_Z(rx_data)']
    # All three physical RX inputs are driven. Protocol/TX combinational inputs
    # are idle constants; no RX internal net is forced or replaced.
    bench='''`timescale 1ns/1ps
module tb_jdy23_uart_rx_gate;
 GSR GSR(.GSRI(1'b1));
 localparam BIT=5208;reg clk=0,rst_n=0,rx=1;
 wire rx_valid,framing_error;wire [7:0] rx_data;
 integer count=0,errors=0,i;reg [7:0] seen[0:63];
 always #10 clk=~clk;
 INSTANCE
 always @(posedge clk)begin if(rx_valid)begin seen[count]=rx_data;count=count+1;end if(framing_error)errors=errors+1;end
 task automatic send(input [7:0] value,input integer period=BIT,input bit stop=1);
 integer b;begin @(negedge clk);rx=0;repeat(period)@(negedge clk);
 for(b=0;b<8;b=b+1)begin rx=value[b];repeat(period)@(negedge clk);end
 rx=stop;repeat(period)@(negedge clk);rx=1;end endtask
 initial begin
 repeat(10)@(negedge clk);rst_n=1;
 for(i=0;i<20;i=i+1)send((i*37)^8'h58);
 repeat(750000)@(negedge clk);
 for(i=20;i<32;i=i+1)send((i*37)^8'h58);
 send(8'ha5,5104);send(8'h5a,5312);repeat(BIT)@(negedge clk);
 if(count!=34||errors)$fatal(1,"FAIL: actual synthesized RX count/errors");
 for(i=0;i<32;i=i+1)if(seen[i]!==(((i*37)^8'h58)&255))$fatal(1,"FAIL: gate RX data");
 if(seen[32]!==8'ha5||seen[33]!==8'h5a)$fatal(1,"FAIL: gate RX baud tolerance");
 send(8'hff,BIT,0);repeat(BIT)@(negedge clk);send(8'hc3);repeat(BIT)@(negedge clk);
 if(errors!=1||count!=35||seen[34]!==8'hc3)$fatal(1,"FAIL: gate RX framing recovery");
 $display("PASS: actual synthesized UART RX; 50MHz/9600; 20+12 stream; peer +/-2%%; framing/recovery; no internal RX force");$finish;
 end
 initial begin #100000000;$fatal(1,"FAIL: gate watchdog");end
endmodule
'''.replace('INSTANCE','game_p3_uart dut('+','.join(connections)+');')
    (E/'actual_uart.v').write_text(module,encoding='utf-8')
    (E/'tb.sv').write_text(bench,encoding='utf-8')
    def command(name,*args):
        p=subprocess.run([str(BIN/name),*args],cwd=E,capture_output=True,text=True,errors='replace')
        log=p.stdout+p.stderr;(E/(name+'.log')).write_text(log,encoding='utf-8')
        assert p.returncode==0 and not re.search(r'FAIL:|\*\* (?:Error|Fatal|Warning):',log),log[-2500:]
        return log
    command('vlib.exe','work')
    command('vlog.exe','-sv','S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v','actual_uart.v','tb.sv')
    log=command('vsim.exe','-c','-onfinish','stop','work.tb_jdy23_uart_rx_gate','-do','run -all; quit -code 0 -f')
    assert 'PASS:' in log
    (E/'verification.json').write_text(json.dumps({'result':'PASS','netlist_sha256':hashlib.sha256(VG.read_bytes()).hexdigest(),
        'module_sha256':hashlib.sha256(module.encode()).hexdigest(),'scope':'Actual new netlist RX only; TX/protocol inputs idle; no old audio gate tests repeated'},indent=2))
    print('\n'.join(line for line in log.splitlines() if 'PASS:' in line))

def finish_existing():
    # RX simulation completed successfully. Audit the simulator's intentionally
    # unconnected TX/protocol output warnings without repeating that test.
    module=(E/'actual_uart.v').read_text(encoding='utf-8')
    current=re.search(r'^module game_p3_uart \([\s\S]*?^endmodule',VG.read_text(encoding='utf-8-sig'),re.M)[0]
    assert module==current
    bench=(E/'tb.sv').read_text(encoding='utf-8')
    inputs={name for width,name in re.findall(r'^input\s+(?:\[([^]]+)\]\s+)?(\w+);',module,re.M)}
    outputs={name for width,name in re.findall(r'^output\s+(?:\[([^]]+)\]\s+)?(\w+);',module,re.M)}
    used=set(re.findall(r'\.(\w+)\(',bench.split('game_p3_uart dut(',1)[1].split(');',1)[0]))
    assert inputs<=used and used-inputs=={'rx_valid_Z','rx_error','rx_data_Z'}
    missing=outputs-used
    log=(E/'vsim.exe.log').read_text(encoding='utf-8')
    assert 'PASS: actual synthesized UART RX' in log and not re.search(r'FAIL:|\*\* (?:Error|Fatal):',log)
    warnings=[line for line in log.splitlines() if line.startswith('# ** Warning:')]
    assert len(warnings)==len(missing)+1
    assert {m[0] for line in warnings for m in [re.findall(r"Missing connection for port '([^']+)'",line)] if m}==missing
    generic=[line for line in warnings if 'Too few port connections' in line]
    assert len(generic)==1 and f'Expected {len(inputs)+len(outputs)}, found {len(used)}' in generic[0]
    assert all(('Missing connection for port' in line or 'Too few port connections' in line) for line in warnings)
    (E/'verification.json').write_text(json.dumps({'result':'PASS','netlist_sha256':hashlib.sha256(VG.read_bytes()).hexdigest(),
        'module_sha256':hashlib.sha256(module.encode()).hexdigest(),'scope':'Actual synthesized RX only; no internal RX force',
        'audited_model_warnings':'Only deliberately unconnected TX/protocol output ports; all input ports connected',
        'unused_outputs':sorted(missing),'simulation_not_repeated':True},indent=2))
    print('PASS: existing gate RX simulation; unused output warnings individually audited; no input left floating; no test repeated')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--finish-existing',action='store_true')
    if parser.parse_args().finish_existing:finish_existing()
    else:run()
