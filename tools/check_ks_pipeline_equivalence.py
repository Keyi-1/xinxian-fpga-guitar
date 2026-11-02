"""Bind the finite, tested KS timing edits to the accepted tone implementation."""
import re
from build_song_slots import ROOT, BASE, sha, load, save

KS = 'rtl/synth/karplus_strong_voice.v'


def verify():
    original = BASE/'before/source'/KS
    assert sha(original) == load(BASE/'before/snapshot.json')['source_sha256'][KS]
    expected = original.read_text(encoding='utf-8-sig')
    edits = [
        ('wire signed [18:0] filter_sum=$signed(interpolated)+$signed(previous);',
         'reg signed [18:0] filter_base,filter_total;\n    wire signed [18:0] filter_sum=filter_total;'),
        ('period_q8<=0;', 'period_q8<=0;filter_base<=0;filter_total<=0;'),
        ('8: begin difference<=$signed(read_data)-$signed(first);stage<=28;end',
         '8: begin difference<=$signed(read_data)-$signed(first);filter_base<=$signed(first)+$signed(previous);stage<=28;end'),
        ('10:begin interpolated<=first+interpolation_delta;stage<=11;end',
         '10:begin interpolated<=first+interpolation_delta;filter_total<=filter_base+interpolation_delta;stage<=11;end'),
        ('reg [16:0] period_q8;',
         "reg [16:0] period_q8;\n    wire [8:0] period_integer=period_q8[16:8]-{8'd0,!period_q8[7]};\n    wire [8:0] capacity_last=current_capacity-9'd1;\n    wire period_too_long=current_capacity!=0 && (period_q8<17'd128 || period_integer>=capacity_last);"),
        ("delay_integer<=(period_q8-17'd128)>>8;", 'delay_integer<=period_integer;'),
        ("if(((period_q8-17'd128)>>8)>=current_capacity-1)run_frame<=0;", 'if(period_too_long)run_frame<=0;'),
    ]
    for old, new in edits:
        assert old in expected, old
        expected = expected.replace(old, new, 1)
    assert (ROOT/KS).read_text(encoding='utf-8-sig') == expected
    folder = BASE/'ks_pipeline_probe2'
    probe = (folder/'candidate.v').read_text(encoding='utf-8-sig')
    for name in ('karplus_strong_voice', 'ks_string_lane', 'ks_period_pipeline'):
        probe = re.sub(r'\bprobe_'+name+r'\b', name, probe)
    probe = probe.replace((ROOT/'rtl/config/ks_reciprocal.vh').as_posix(), '../config/ks_reciprocal.vh')
    assert probe == expected
    preparation = load(folder/'preparation.json')
    assert preparation['period_capacity_cases'] == 67108864 and preparation['integer_period_cases'] == 131072
    assert preparation['candidate_sha256'] == sha(folder/'candidate.v')
    rec = load(folder/'verification.json')
    assert rec['result'] == 'PASS_PROTOTYPE_ONLY' and rec['production_source_sha256'] == sha(original)
    for p, h in rec['files_sha256'].items():
        assert sha(folder/p) == h, p
    log = (folder/'simulation.log').read_text()
    assert '32768 exact PCM updates/32 model states' in log and 'maxbusy176' in log
    assert not re.search(r'FAIL:|\*\* (Error|Fatal):', log)
    record = {'result': 'PASS', 'old_source_sha256': sha(original), 'new_source_sha256': sha(ROOT/KS),
              'finite_edits': edits, 'exact_pcm_updates': 32768, 'model_states': 32, 'max_busy_cycles': 176,
              'period_capacity_cases': 67108864, 'integer_period_cases': 131072,
              'probe_verification_sha256': sha(folder/'verification.json'),
              'scope': 'Same states and cycle count. Convex interpolation stays in signed18 bits, so reassociating first+delta+previous in signed19 bits is exact; rounding/loss/DC/gains/delays/state layout remain unchanged. Period arithmetic includes all zero/underflow inputs.'}
    save(BASE/'ks_pipeline_equivalence.json', record)
    return record


if __name__ == '__main__':
    import json
    print(json.dumps(verify(), indent=2))
