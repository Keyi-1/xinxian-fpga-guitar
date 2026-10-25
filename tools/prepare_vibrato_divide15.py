"""Exact bounded unsigned /15: preserve slide timing, remove long divider cone."""
import argparse
import hashlib
import json
from fractions import Fraction
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SOURCE='rtl/control/phase_slide_smoother.v'
BEFORE=ROOT/'build/vibrato/before_20261023/files'/SOURCE
FUNCTION='''
    // Exact unsigned /15 for5..33-bit inputs. The geometric reciprocal
    // underestimates the quotient by at most one; its remainder is0..29.
    // Only the low5 remainder bits are needed, with no DSP or new latency.
    function automatic [ROUND_BITS-DIV_POW2_SHIFT-1:0] divide15_exact;
        input [ROUND_BITS-DIV_POW2_SHIFT-1:0] dividend;
        reg [ROUND_BITS-DIV_POW2_SHIFT-1:0] q;
        reg [4:0] remainder;
        begin
            q=(dividend>>1)+(dividend>>5);
            q=q+(q>>8);
            q=q+(q>>16);
            q=q>>3;
            remainder=dividend[4:0]+q[4:0]-{q[0],4'b0};
            divide15_exact=q+(remainder>=5'd15);
        end
    endfunction
'''
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def expected_source():
    body=BEFORE.read_text(encoding='utf-8-sig')
    anchor='    localparam [ROUND_BITS-DIV_POW2_SHIFT-1:0] DIV_ODD_VALUE = DIV_ODD;\n'
    original='            step_size = reduced_difference / DIV_ODD_VALUE;'
    assert body.count(anchor)==body.count(original)==1
    return body.replace(anchor,anchor+FUNCTION,1).replace(original,
      '            if(DIV_ODD==15)step_size=divide15_exact(reduced_difference);\n'
      '            else step_size = reduced_difference / DIV_ODD_VALUE;',1)
def proof():
    # c/8 = n*(2^32-1)/(15*2^32) - accumulated truncation error/8.
    # Each shift's independent truncation error has this exact upper bound.
    reciprocal=Fraction(17,32)*Fraction(257,256)*Fraction(65537,65536)/8
    assert reciprocal==Fraction(2**32-1,15*2**32)
    error=((Fraction(47,32)*Fraction(257,256)+Fraction(255,256))*
      Fraction(65537,65536)+Fraction(65535,65536))/8
    total=Fraction(2**33-1,15*2**32)+error
    assert 0<total<1
    return {'result':'PASS','input_bits':'5..33','maximum_total_underestimate':str(total),
      'reciprocal':str(reciprocal),'remainder_range':[0,29],
      'proof':'All arithmetic nonnegative and intermediate q<0.54*n, so the input-width accumulator cannot overflow. Before final floor, approximation underestimates n/15 by less than1 for every n<2^33. Thus quotient is exact or1 low, true remainder0..29 fits5 bits; low5 modular remainder and >=15 correction are exact. All other slide arithmetic/state/latency remains byte-identical.',
      'before_sha256':sha(BEFORE),'tool_sha256':sha(Path(__file__))}
def audit_current():
    assert (ROOT/SOURCE).read_text(encoding='utf-8-sig')==expected_source()
    return {**proof(),'after_sha256':sha(ROOT/SOURCE)}
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--adopt',action='store_true')
    args=parser.parse_args();body=expected_source()
    candidate=ROOT/'sim/reference/vibrato/phase_slide_smoother_div15_candidate.v'
    expected=body.replace('module phase_slide_smoother ','module vibrato_div15_phase_slide_smoother ',1)
    if candidate.exists():assert candidate.read_text(encoding='utf-8-sig')==expected
    else:candidate.write_text(expected,encoding='utf-8')
    folder=ROOT/'build/vibrato/divide15_candidate';folder.mkdir(exist_ok=True)
    (folder/'proof.json').write_text(json.dumps(proof(),indent=2)+'\n',encoding='utf-8')
    if args.adopt:
        for run in ('vibrato_divide15_01','vibrato_gesture_gate_02'):
            record=json.loads((ROOT/'sim/temp'/run/'verification.json').read_text(encoding='utf-8-sig'))
            assert record['status']=='PASS',run
        assert (ROOT/SOURCE).read_text(encoding='utf-8-sig')==BEFORE.read_text(encoding='utf-8-sig')
        (ROOT/SOURCE).write_text(body,encoding='utf-8')
    print(json.dumps(proof(),indent=2))
if __name__=='__main__':main()
