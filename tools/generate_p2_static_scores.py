"""Generate reproducible static P2 fixtures; never alter the accepted P1 score.

The arpeggio is an original exercise, not a transcription of Liang Jingru's song.
Seven Nation Army is a short seven-note riff practice loop, not the full song.
Qing Ge uses the complete upper staff of the two user-supplied pages (38 bars),
with explicitly accepted rhythm corrections; unprovided sections are not inferred.
"""
from pathlib import Path
from fractions import Fraction
import argparse
import csv
import hashlib
import json
from game_score_v2 import Event, MAX_EVENTS, allocate, phase, payload_info, validate
from qing_ge_user_score import compile_score

ROOT = Path(__file__).resolve().parent.parent


def build():
    legacy = [int(s, 16) for s in (ROOT/'mem/jasmine_game.mem').read_text().splitlines()]
    with (ROOT/'scores/jasmine.csv').open(encoding='utf-8-sig') as stream:
        source = list(csv.DictReader(stream))
    jasmine = []
    for old, row in zip(legacy, source):
        midi = int(row['midi_note'])
        assert phase(midi) == (old >> 48 & ((1 << 26) - 1))
        jasmine.append(Event(old & 0xffffff, old >> 24 & 0xffffff, midi, old >> 74 & 3))
    validate(jasmine, 1620000)
    # Original eight-chord exercise: quarter-note arpeggios, 60 BPM.
    chords = [(60,64,67,72), (59,62,67,71), (57,60,64,69), (55,59,64,67),
              (53,57,60,65), (55,60,64,67), (50,57,62,65), (55,59,62,67)]
    arpeggio = allocate([Event(i*48000, 36000, chords[(i//4)%8][i%4], 0)
                         for i in range(256)])
    # One short hook moved up an octave, repeated only as a slow drill.
    # Source: https://nationalguitaracademy.com/songs/how-to-play-seven-nation-army-on-guitar/
    notes = [64,64,67,64,62,60,59]
    beats = [Fraction(0),Fraction(3,2),Fraction(2),Fraction(3),Fraction(4),Fraction(5),Fraction(6)]
    durations = [Fraction(1),Fraction(1,2),Fraction(1,2),Fraction(1,2),Fraction(1,2),Fraction(1,2),Fraction(1)]
    riff = allocate([Event(round((repeat*8+b)*48000), round(d*48000), n, 0)
                     for repeat in range(24) for b,d,n in zip(beats,durations,notes)])
    # Only the upper staff supplied by the user; the lower accompaniment is
    # intentionally excluded from the already-selected melody gameplay.
    qing_melody,qing_duration,qing_report=compile_score()
    # Ten minutes, last onset beyond the old 24-bit boundary. Not a named song.
    boundary = allocate([Event(i*112500, 36000, (55,59,62,64)[i%4], 0)
                         for i in range(256)])
    entries = [
        dict(slot=0, alias='JASMINE', title='茉莉花', events=jasmine, duration=1620000,
             bpm=96, timbre=0, playable=True, test_only=False, provenance='Existing accepted P1 score; exact sample-time/DDS migration'),
        dict(slot=1, alias='SLOW_ARPEGGIO', title='原创慢速分解和弦练习', events=arpeggio, duration=256*48000,
             bpm=60, timbre=1, playable=True, test_only=False, provenance='Original technical exercise; not Qing Ge'),
        dict(slot=2, alias='SEVEN_NATION_RIFF', title='Seven Nation Army 短 riff 慢练', events=riff, duration=24*8*48000,
             bpm=60, timbre=2, playable=True, test_only=False, provenance='Short hook practice only, octave raised; newly arranged timing, not full original recording or score',
             reference='https://nationalguitaracademy.com/songs/how-to-play-seven-nation-army-on-guitar/'),
        dict(slot=3, alias='QING_GE_MELODY', title='情歌旋律（用户谱完整38小节）', events=qing_melody, duration=qing_duration,
             bpm=60, timbre=1, playable=True, test_only=False,
             pitch_profile='game_extended',transpose_semitones=-12,
             provenance='Complete 38-bar upper staff from two user-supplied images; 60 BPM, one octave down, no loop. Two explicitly accepted bar10/18 rhythm revisions await listening confirmation; not the full original-recording arrangement.',
             reference='scores/p2/source/qing_ge_user_melody.json'),
        dict(slot=4, alias='TIME_10MIN', title='十分钟边界测试', events=boundary, duration=600*48000,
             bpm=60, timbre=1, playable=False, test_only=True, provenance='Generated timing fixture, not a performance song'),
    ]
    words, rows = [], []
    for entry in entries:
        events = entry.pop('events')
        if events:
            validate(events, entry['duration'],profile=entry.get('pitch_profile','physical'))
        entry.update(offset=len(words), count=len(events), valid=bool(events))
        payload, crc = payload_info(events)
        entry['crc32'] = crc
        words.extend(e.word() for e in events)
        rows.append((entry['alias'].lower(), events, payload))
    assert len(words) <= MAX_EVENTS
    manifest = dict(format_version=2, sample_rate_hz=48000, event_bits=96,
                    event_bytes=16, total_events=len(words), capacity=MAX_EVENTS,
                    slots=entries, integration='Production touch UI/audio; Qing Ge user-score melody trial')
    outputs = {'mem/game_p2_static.mem': ''.join(f'{w:024x}\n' for w in words+[0]*(MAX_EVENTS-len(words))).encode()}
    for alias, events, payload in rows:
        if events:
            outputs[f'scores/p2/{alias}.bin'] = payload
            header = 't_on_samples,duration_samples,midi_note,lane,velocity_hint,flags,group_id\n'
            outputs[f'scores/p2/{alias}.csv'] = (header+''.join(f'{e.onset},{e.duration},{e.midi},{e.lane},{e.velocity},{e.flags},{e.group}\n' for e in events)).encode()
    manifest['bank_sha256'] = hashlib.sha256(outputs['mem/game_p2_static.mem']).hexdigest()
    outputs['scores/p2/catalog.json'] = (json.dumps(manifest, ensure_ascii=False, indent=2)+'\n').encode()
    catalog = ['// Generated by tools/generate_p2_static_scores.py. No audio data.', 'case(slot)']
    for e in entries:
        catalog.append(f"    3'd{e['slot']}:begin valid=1'b{int(e['valid'])};playable=1'b{int(e['playable'])};test_only=1'b{int(e['test_only'])};base=11'd{e['offset']};event_count=12'd{e['count']};duration=32'd{e['duration']};timbre=2'd{e['timbre']};end")
    catalog += ['    default:begin end', 'endcase', '']
    outputs['rtl/config/game_p2_catalog.vh'] = '\n'.join(catalog).encode()
    progress=['// Generated from the same catalogue; ceil(samples/480).',
        'function [31:0] game_p2_progress_step;', '    input [2:0] slot;', '    begin case(slot)']
    progress += [f"        3'd{e['slot']}:game_p2_progress_step=32'd{(e['duration']+479)//480};" for e in entries]
    progress += ["        default:game_p2_progress_step=32'd3375;",'    endcase end','endfunction','']
    outputs['rtl/config/game_p2_progress.vh']='\n'.join(progress).encode()
    table = ['// Generated exact DDS increments, accepted 48 kHz tuning.', 'case(midi)']
    table += [f"    7'd{n}:midi_phase=27'd{phase(n,profile='game_extended')};" for n in range(50,80)]
    table += ["    default:midi_phase=27'd0;",'endcase','']
    outputs['rtl/config/game_p2_phase.vh'] = '\n'.join(table).encode()
    outputs['scores/p2/qing_ge_transcription_audit.json']=(json.dumps(qing_report,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    return outputs, manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    outputs, manifest = build()
    for name, data in outputs.items():
        path = ROOT/name
        if args.check:
            assert path.exists() and path.read_bytes() == data, f'Stale generated file: {name}'
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    print(f"PASS: P2 static bank {manifest['total_events']}/{MAX_EVENTS} events; Jasmine exact, Qing Ge 38 bars/152s, short riff, 10 min fixture")


if __name__ == '__main__':
    main()
