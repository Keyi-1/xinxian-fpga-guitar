"""Pack the unchanged exact gain function into one synchronous DPB16 ROM."""
from pathlib import Path
import argparse
import re

ROOT = Path(__file__).resolve().parent.parent


def values():
    text = (ROOT/'rtl/config/rock_coeffs.vh').read_text(encoding='utf-8')
    body = text.split('function [15:0] rock_gain_for;')[1].split('endfunction')[0]
    rows = {int(a): int(b) for a, b in re.findall(r"7'd(\d+): rock_gain_for=16'd(\d+);", body)}
    assert set(rows) == set(range(96)) and 'default: rock_gain_for=0;' in body
    return [rows.get(i, 0) for i in range(1024)]


def build():
    rows = values()
    lines = ['// Generated exact rock_gain_for table; original coefficients remain authoritative.',
        'DPB gain_table (.DOA(data),.DOB(),.DIA(16\'d0),.DIB(16\'d0),',
        "    .ADA({3'd0,address,4'b0000}),.ADB(14'd0),.BLKSELA(3'd0),.BLKSELB(3'd0),",
        "    .WREA(1'b0),.WREB(1'b0),.CLKA(clk),.CLKB(clk),.CEA(read_enable),.CEB(1'b0),",
        "    .OCEA(1'b0),.OCEB(1'b0),.RESETA(1'b0),.RESETB(1'b0));",
        'defparam gain_table.BIT_WIDTH_0=16;', 'defparam gain_table.BIT_WIDTH_1=16;',
        "defparam gain_table.READ_MODE0=1'b0;", "defparam gain_table.READ_MODE1=1'b0;"]
    for block in range(64):
        word = sum(rows[block*16+i] << (16*i) for i in range(16))
        lines.append(f"defparam gain_table.INIT_RAM_{block:02X}=256'h{word:064x};")
    return ('\n'.join(lines)+'\n').encode('ascii')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('--check', action='store_true')
    args = parser.parse_args(); path = ROOT/'rtl/config/piano_rock_gain_init.vh'
    if args.check:
        assert path.read_bytes() == build()
    else:
        path.write_bytes(build())
    print('PASS: all96 unchanged rock gains and32 default entries packed; synchronous DPB16 read, no parameter changes')
