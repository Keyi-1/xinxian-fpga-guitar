"""Compile the supplied 38-bar upper staff, with explicit reviewed edits.

This is a transformation of the two user-supplied images. It does not infer
missing original-recording sections or copy music from an external website.
"""
from dataclasses import replace
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import re

from game_score_v2 import Event, SAMPLE_RATE, allocate, validate

ROOT=Path(__file__).resolve().parent.parent
SOURCE=ROOT/'scores/p2/source/qing_ge_user_melody.json'
DEGREES=(0,2,4,5,7,9,11)


def compile_score(path=SOURCE):
    source=json.loads(path.read_text(encoding='utf-8'))
    assert source['time_signature']==[4,4] and len(source['measures'])==38
    assert source['transpose_semitones']==-12 and source['pitch_profile']=='game_extended'
    for page in source['source_pages']:
        assert hashlib.sha256((ROOT/page['path']).read_bytes()).hexdigest()==page['sha256']
    review=source['rhythm_review']
    assert review['bars']==[10,18]
    if review['status']=='USER_ACCEPTED_TRIAL':
        # Preserve the earlier explicit trial for reproducible historical audio.
        assert review['proposed_override']['token_index_zero_based']==4
        assert review['user_authorization']=='2026-10-16 explicit reply: two bar-10/18 degree-5 half beats become one beat for listening review'
        overrides={4:('5',Fraction(1,2),Fraction(1))}
    else:
        assert review['status']=='USER_CONFIRMED_BEAT_GRID', 'Rhythm revision needs user acceptance'
        assert review['user_notation']=='1_11|(1)5_3|(3)___|345'
        assert review['user_authorization']=='2026-10-18 explicit listening reply: rhythm correct, adopt this version in production score'
        overrides={5:('3',Fraction(1,2),Fraction(1,4)),6:('~3',Fraction(1,4),Fraction(1))}
    scale=Fraction(SAMPLE_RATE*60,source['practice_bpm'])
    cursor=Fraction(0);notes=[];rows=[];ties=0;rests=0;revisions=[]
    for number,measure in enumerate(source['measures'],1):
        assert measure['number']==number
        bar_start=cursor
        for index,token in enumerate(measure['tokens']):
            value=token['pitch'];duration=Fraction(token['beats'])
            assert duration>0
            if number in review['bars'] and index in overrides:
                symbol,old,new=overrides[index]
                assert value==symbol and duration==old
                duration=new;revisions.append(dict(bar=number,token=index,pitch=value,from_beats=str(old),to_beats=str(new)))
            match=re.fullmatch(r'(~)?([+]*|[-]*)([0-7])',value)
            assert match,token
            tied,octaves,degree=match.groups();degree=int(degree)
            onset=round(cursor*scale);end=round((cursor+duration)*scale)
            if degree==0:
                assert not tied and not octaves
                rests+=1
            else:
                octave=octaves.count('+')-octaves.count('-')
                original=source['source_tonic_midi']+DEGREES[degree-1]+12*octave
                midi=original+source['transpose_semitones']
                if tied:
                    assert notes and notes[-1].midi==midi and notes[-1].onset+notes[-1].duration==onset,('invalid tie',number,index)
                    notes[-1]=replace(notes[-1],duration=end-notes[-1].onset);ties+=1
                else:notes.append(Event(onset,end-onset,midi,0))
                rows.append(dict(bar=number,token=index,printed_pitch=value,beats=str(duration),
                    beat=str(cursor),source_midi=original,output_midi=midi,tied=bool(tied)))
            cursor+=duration
        assert cursor-bar_start==4,('bar is not four beats',number,cursor-bar_start)
    if review['status']=='USER_CONFIRMED_BEAT_GRID':
        # This timing-only repair keeps the already accepted string choices.
        # The complete new timeline is still checked for every lane conflict.
        lane_map=json.loads((ROOT/'scores/p2/source/qing_ge_accepted_lanes.json').read_text(encoding='utf-8'))
        assert lane_map['baseline_commit']=='7837a24837de29454f0da28f413bdd48abd5a592'
        assert hashlib.sha256(bytes(e.midi for e in notes)).hexdigest()==lane_map['midi_sequence_sha256']
        assert len(lane_map['lanes'])==len(notes)
        events=[replace(e,lane=lane) for e,lane in zip(notes,lane_map['lanes'])]
    else:events=allocate(notes,profile='game_extended')
    total=round(cursor*scale)
    validate(events,total,profile='game_extended')
    report=dict(title=source['title'],measures=38,total_quarter_beats=str(cursor),
        practice_bpm=source['practice_bpm'],duration_samples=total,duration_seconds=total/SAMPLE_RATE,
        note_events=len(events),tie_continuations=ties,rest_tokens=rests,
        output_midi_range=[min(e.midi for e in events),max(e.midi for e in events)],
        source_midi_range=[min(r['source_midi'] for r in rows),max(r['source_midi'] for r in rows)],
        transpose_semitones=-12,pitch_profile='game_extended',rhythm_revisions=revisions,
        scope=source['scope'],source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        source_pages=source['source_pages'],printed_note_tokens=rows)
    return events,total,report
