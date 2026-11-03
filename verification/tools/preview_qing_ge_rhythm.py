"""Audition a narrowly scoped, unapproved score edit without changing FPGA assets.

WAV synthesis is a software plucked reference, not a bit-exact board audio
export. Both versions use the same instrument, levels and exact 48k timing.
"""
from dataclasses import replace
from fractions import Fraction
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import wave

import numpy as np

from game_score_v2 import SAMPLE_RATE, validate, from_binary
from qing_ge_user_score import ROOT, SOURCE, compile_score

REVIEW = ROOT/'scores/p2/review/qing_ge_rhythm_10_18_v1.json'
BASELINE_COMMIT = '7837a24837de29454f0da28f413bdd48abd5a592'


def baseline_score():
    payload = subprocess.check_output(['git','show',f'{BASELINE_COMMIT}:scores/p2/qing_ge_melody.bin'], cwd=ROOT)
    return from_binary(payload, profile='game_extended'), 7296000


def candidate(events, total, bpm=60):
    """Keep allocation and every other event byte; edit only 5 and tied 3."""
    out = list(events)
    quarter = Fraction(SAMPLE_RATE*60, bpm)
    changes = []
    for bar in (10, 18):
        start = (bar-1)*4*quarter
        for beat, midi, duration, new_beat, new_duration in (
                (Fraction(5, 4), 62, Fraction(1), Fraction(5, 4), Fraction(1, 2)),
                (Fraction(9, 4), 59, Fraction(3, 4), Fraction(7, 4), Fraction(5, 4))):
            matches = [i for i,e in enumerate(out)
                       if e.onset == round(start+beat*quarter) and e.midi == midi]
            assert len(matches) == 1, (bar, beat, matches)
            i = matches[0]
            assert out[i].duration == round(duration*quarter)
            old = out[i]
            out[i] = replace(old, onset=round(start+new_beat*quarter),
                             duration=round(new_duration*quarter))
            changes.append(dict(bar=bar, index=i, midi=midi,
                                old_onset=old.onset, onset=out[i].onset,
                                old_duration=old.duration, duration=out[i].duration))
    validate(out, total, profile='game_extended')
    return out, changes


def segment(events, first_bar, bars, bpm=60):
    quarter = Fraction(SAMPLE_RATE*60, bpm)
    begin = round((first_bar-1)*4*quarter)
    end = round((first_bar-1+bars)*4*quarter)
    result = []
    for e in events:
        lo, hi = max(begin, e.onset), min(end, e.onset+e.duration)
        if lo < hi:
            # These selected boundaries contain no incoming ties.
            assert lo == e.onset
            result.append(replace(e, onset=lo-begin, duration=hi-lo))
    return result, end-begin


def render(events, frames):
    """Approximate bright pluck. Event attacks/holds are exact, no tie attacks."""
    result = np.zeros((frames+SAMPLE_RATE//2, 2), dtype=np.float64)
    for e in events:
        n = min(e.duration+1440, len(result)-e.onset)
        t = np.arange(n)/SAMPLE_RATE
        f = 440*2**((e.midi-69)/12)
        voice = np.zeros(n)
        for harmonic in range(1, 33):
            if f*harmonic >= SAMPLE_RATE/2:
                break
            voice += (np.sin(2*np.pi*f*harmonic*t)/(harmonic**1.35)
                      *np.exp(-t*(.65+harmonic*.17)))
        attack = np.minimum(t/.003, 1)
        release = np.clip((e.duration+1440-np.arange(n))/1440, 0, 1)
        voice *= attack*release*.17
        result[e.onset:e.onset+n] += voice[:, None]
    return result


def clicks(frames, quarter=48000):
    out = np.zeros((frames, 2))
    for index, onset in enumerate(range(0, frames, quarter)):
        n = min(1440, frames-onset)
        t = np.arange(n)/SAMPLE_RATE
        tone = np.sin(2*np.pi*(1500 if index%4 == 0 else 1050)*t)*np.exp(-t*140)*.055
        out[onset:onset+n] += tone[:, None]
    return out


def counted(events, frames):
    intro = clicks(4*SAMPLE_RATE)
    notes = render(events, frames)
    notes[:frames] += clicks(frames)
    return np.concatenate([intro, notes])


def save(path, pcm):
    assert np.max(np.abs(pcm)) < .98, 'Common fixed gain must not clip'
    encoded = np.rint(pcm*32767).astype('<i2')
    with wave.open(str(path), 'wb') as out:
        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(SAMPLE_RATE)
        out.writeframes(encoded.tobytes())
    return dict(sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                samples=len(pcm), seconds=len(pcm)/SAMPLE_RATE,
                peak_pcm16=int(np.abs(encoded.astype(np.int32)).max()))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path,
                        default=ROOT/'build/qing_ge_rhythm_review/preview_v1')
    args = parser.parse_args()
    assert not args.output.exists(), 'Preserve existing listening evidence'
    baseline, total = baseline_score()
    proposed, changes = candidate(baseline, total)
    review = json.loads(REVIEW.read_text(encoding='utf-8'))
    expected_on = [round(Fraction(x)*SAMPLE_RATE) for x in review['attacks_in_quarter_beats']]
    expected_len = [round(Fraction(x)*SAMPLE_RATE) for x in review['durations_in_quarter_beats']]
    for bar in (10, 18):
        notes, length = segment(proposed, bar, 1)
        assert length == 4*SAMPLE_RATE
        assert [e.onset for e in notes] == expected_on
        assert [e.duration for e in notes] == expected_len
        assert [e.midi for e in notes] == [67, 67, 67, 62, 59, 59, 60, 62]
    assert len(proposed) == len(baseline) == 212 and len(changes) == 4
    changed = {r['index'] for r in changes}
    assert all(a == b for i,(a,b) in enumerate(zip(baseline, proposed)) if i not in changed)
    args.output.mkdir(parents=True)
    new, length = segment(proposed, 10, 1)
    old, _ = segment(baseline, 10, 1)
    repeated = new+[replace(e, onset=e.onset+length) for e in new]
    context, context_len = segment(proposed, 9, 3)
    files = {
        'corrected_bar10_twice_counted.wav': counted(repeated, 2*length),
        'corrected_bars9_11_clean.wav': render(context, context_len),
        'old_then_corrected_counted.wav': np.concatenate([
            counted(old, length), np.zeros((SAMPLE_RATE//2, 2)), counted(new, length)])}
    outputs = {name: save(args.output/name, pcm) for name,pcm in files.items()}
    report = dict(result='PASS', review_status=review['status'], bpm=60,
                  sample_rate=SAMPLE_RATE, changes=changes,
                  attack_offsets_seconds=[x/SAMPLE_RATE for x in expected_on],
                  durations_seconds=[x/SAMPLE_RATE for x in expected_len],
                  note_count=212, identical_bar10_bar18=True,
                  synthesis='Software bright pluck reference; 32 partials; not board PCM or a timbre equivalence proof',
                  comparison_order='Old first, corrected second; each has four count-in beats',
                  production_assets_modified=False,
                  source_sha256={str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in [SOURCE, REVIEW, Path(__file__), ROOT/'tools/qing_ge_user_score.py']},
                  outputs=outputs)
    (args.output/'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(dict(result='PASS', output=str(args.output), changes=changes, outputs=outputs), indent=2))


if __name__ == '__main__':
    main()
