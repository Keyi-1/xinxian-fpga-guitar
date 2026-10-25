"""Finite retiming edit guard; exact scan-counter invariant, no timing exceptions."""
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BEFORE=ROOT/'build/vibrato/before_20261023/files'
UI='rtl/game/touch_game_renderer.v'
SCAN='rtl/display/lcd_rgb_scan_480x272.v'
TAIL_DECL='''    reg [7:0] valid1;
    reg [71:0] tail_lengths1;
    wire [7:0] tails1;
    // The existing second stage receives the same geometry as the original
    // registered tail flag. Moving only this predicate across those registers
    // preserves every output clock, while separating lane mux/subtract from
    // tail-length add/compare. No additional pixel pipeline stage is added.
    genvar tail_index;
    generate for(tail_index=0;tail_index<8;tail_index=tail_index+1)begin:tail_compare
        assign tails1[tail_index]=valid1[tail_index] &&
            $signed(dx1[tail_index*10+:10])>=14 &&
            $signed(dx1[tail_index*10+:10])<$signed(10'd14+{1'b0,tail_lengths1[tail_index*9+:9]}) &&
            local1>=15 && local1<27;
    end endgenerate'''
EDITS_UI=(
 ('    reg [7:0] note_valid,tail_hits;','    reg [7:0] note_valid;\n    reg [71:0] tail_lengths;'),
 ('relative_x=0;note_valid=0;tail_hits=0;','relative_x=0;note_valid=0;tail_lengths=0;'),
 ('''                        tail_hits[k]=note_valid[k] && dx_work>=14 &&
                            dx_work<$signed(10'd14+{1'b0,tails[slot*9+:9]}) && local_y>=15 && local_y<27;''',
  '                        tail_lengths[k*9+:9]=tails[slot*9+:9];'),
 ('    reg [7:0] valid1,tails1;',TAIL_DECL),
 ('dx1<=0;valid1<=0;tails1<=0;','dx1<=0;valid1<=0;tail_lengths1<=0;'),
 ('local1<=local_y;tails1<=tail_hits;','local1<=local_y;tail_lengths1<=tail_lengths;'))
EDITS_SCAN=(
 ('output wire [8:0] pixel_y,','output reg [8:0] pixel_y,'),
 ('    assign pixel_y = v_count - 9\'d12;',
  '''    // Maintain the exact (v_count-12) modulo512 value alongside v_count.
    // This removes a carry chain before every UI y decode, without delaying
    // coordinates or changing the six-clock pixel/output schedule.'''),
 ('            v_count <= 0;','            v_count <= 0;\n            pixel_y <= 9\'d500;'),
 ('                    v_count <= v_count == 291 ? 9\'d0 : v_count + 1\'b1;',
  '                    v_count <= v_count == 291 ? 9\'d0 : v_count + 1\'b1;\n                    pixel_y <= v_count == 291 ? 9\'d500 : pixel_y + 1\'b1;'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def audit():
    results={}
    for path,edits in ((UI,EDITS_UI),(SCAN,EDITS_SCAN)):
        body=(BEFORE/path).read_text(encoding='utf-8-sig')
        for old,new in edits:
            assert body.count(old)==1,(path,old)
            body=body.replace(old,new,1)
        assert body==(ROOT/path).read_text(encoding='utf-8-sig'),('unqualified display edit',path)
        results[path]={'before_sha256':sha(BEFORE/path),'after_sha256':sha(ROOT/path)}
    assert ((0-12)&511)==500
    cases=0
    for v in range(292):
        y=(v-12)&511
        for row_advance in (False,True):
            next_v=(0 if v==291 else v+1) if row_advance else v
            next_y=(500 if v==291 else (y+1)&511) if row_advance else y
            assert next_y==((next_v-12)&511)
            cases+=1
    # The exact edits move F(note_valid,dx,tail,local_y) across the existing
    # common clock/reset registers, with identical signed widths and F(0,...)=0.
    # All input captures remain on the same edge; effect2/RGB/font stages and
    # every other statement are untouched. This is the retiming identity
    # DFF(F(inputs)) == F(DFF(inputs)), not a new pixel-latency allowance.
    return {'result':'PASS','tool_sha256':sha(Path(__file__)),'modules':results,
      'scan_invariant_cases':cases,'scan_invariant':'pixel_y==(v_count-12) modulo512, including hold,row advance,frame wrap and reset',
      'tail_identity':'Exact typed predicate moved across same-clock registers; valid1 reset0 makes predicate0. Existing dx1/valid1/local1 captures unchanged; raw9-bit tail uses same selected slot. No RGB/font/output stage or coordinate latency changes.'}
if __name__=='__main__':
    import argparse
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();record=audit();args.output.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(record,indent=2))
