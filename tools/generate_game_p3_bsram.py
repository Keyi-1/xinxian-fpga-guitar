"""Writable DPB bank with exactly the accepted P2 initialization and latency."""
from pathlib import Path
import argparse
import hashlib
import re
from generate_game_p2_bsram import build, ROOT


def initial_bank():
    old=[int(x,16) for x in (ROOT/'mem/game_p2_static.mem').read_text().splitlines()]
    # User removed the original 256-event slow practice. Keep every other
    # event unchanged, including the disabled diagnostic, then reclaim space.
    words=old[:67]+old[323:959]+[0]*(2048-703)
    assert len(words)==2048
    return words,(''.join(f'{w:024x}\n' for w in words)).encode('ascii')


def writable():
    words,initial=initial_bank()
    text = build().decode('ascii').replace('tools/generate_game_p2_bsram.py',
                                           'tools/generate_game_p3_bsram.py')
    text = text.replace(".DIB(16'd0)", '.DIB(write_data[SLICE+:16])')
    text = text.replace('display_address[9:0]', 'system_address[9:0]')
    # DPB16 ADB[1:0] are byte write enables, not address bits.
    text = text.replace(".ADB({system_address[9:0],4'b0000})",
                        ".ADB({system_address[9:0],2'b00,{2{write_enable}}})")
    text = text.replace('.CEB(display_read)', '.CEB(display_read || write_enable)')
    # Select the write page explicitly. Enabling both pages on a write would
    # silently corrupt the other 1024 rows.
    lines = text.splitlines()
    lines[1]='// Canonical P3 bank SHA256: '+hashlib.sha256(initial).hexdigest()
    page = column = None
    for i, line in enumerate(lines):
        if line.startswith('DPB score_p'):
            page, column = map(int, line.split('score_p')[1].split(' (')[0].split('_b'))
        lines[i] = line.replace('SLICE', str(column * 16)) if column is not None else line
        if '.WREB(1\'b0)' in lines[i]:
            lines[i] = lines[i].replace(".WREB(1'b0)",
                f".WREB(write_enable && system_address[10]==1'b{page})")
        if '.CEB(display_read || write_enable)' in lines[i]:
            lines[i] = lines[i].replace('.CEB(display_read || write_enable)',
                f".CEB(!write_enable ? display_read : system_address[10]==1'b{page})")
        match=re.match(r'defparam (score_p\d_b\d)\.INIT_RAM_([0-9A-F]{2})=',line)
        if match:
            block=int(match[2],16)
            value=sum(((words[page*1024+block*16+k]>>(column*16))&65535)<<(16*k) for k in range(16))
            lines[i]=f"defparam {match[1]}.INIT_RAM_{match[2]}=256'h{value:064x};"
    return ('\n'.join(lines)+'\n').encode('ascii')


if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    outputs={ROOT/'rtl/config/game_p3_bsram_init.vh':writable(),ROOT/'mem/game_p3_initial.mem':initial_bank()[1]}
    for path,data in outputs.items():
        if args.check:assert path.read_bytes()==data, 'Stale writable DPB initializer/bank'
        else:path.write_bytes(data)
    print('PASS: 703 retained initial events, removed 256-event slow practice, 1345 import rows; 12 writable DPB16 slices, page-qualified byte writes')
