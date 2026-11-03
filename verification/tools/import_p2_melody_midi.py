"""Convert a supplied SMF melody to P2 events; never modify the production bank.

Fixed quarter-note BPM deliberately replaces the file's tempo map, retaining
written rhythms, leading/trailing rests and every note. No melody guessing,
pitch folding, duration clipping, repetition or event dropping is performed.
SMF 0/1 with PPQ only; selected stream must be a monophonic notated melody.
Reference: https://midi.org/standard-midi-files-specification
"""
import argparse
from collections import Counter
from dataclasses import dataclass
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import struct

from game_score_v2 import Event, MAX_EVENTS, MAX_TIME, SAMPLE_RATE, allocate, payload_info, validate


class MidiError(ValueError):
    pass


class Reader:
    def __init__(self, raw):self.raw,self.pos=raw,0

    def take(self, length):
        if length<0 or self.pos+length>len(self.raw):raise MidiError('Truncated MIDI chunk/event')
        data=self.raw[self.pos:self.pos+length];self.pos+=length
        return data

    def byte(self):return self.take(1)[0]

    def vlq(self):
        result=0
        for _ in range(4):
            byte=self.byte();result=(result<<7)|(byte&127)
            if byte<128:return result
        raise MidiError('MIDI variable-length integer exceeds four bytes')

    def chunk(self):
        name=self.take(4);size=int.from_bytes(self.take(4),'big')
        return name,self.take(size)


@dataclass
class Track:
    name:str
    end:int
    messages:list
    tempos:list
    sysex:bool


def parse(raw):
    if len(raw)>8*1024*1024:raise MidiError('MIDI exceeds the 8 MiB import limit')
    reader=Reader(raw);name,header=reader.chunk()
    if name!=b'MThd' or len(header)<6:raise MidiError('Expected a standard MIDI MThd header')
    kind,track_count,ppq=struct.unpack('>HHH',header[:6])
    if kind not in (0,1) or track_count==0 or (kind==0 and track_count!=1):
        raise MidiError('Only synchronous SMF type 0 or 1 is supported')
    if ppq==0 or ppq&0x8000:raise MidiError('Expected PPQ timing; SMPTE timing is unsupported')
    tracks=[]
    for index in range(track_count):
        name,body=reader.chunk()
        if name!=b'MTrk':raise MidiError(f'Track {index}: expected MTrk')
        track=Reader(body);tick=0;running=None;ended=False
        messages=[];tempos=[];title='';sysex=False
        while track.pos<len(body):
            tick+=track.vlq();status=track.byte();first=[]
            if status<128:
                if running is None:raise MidiError('Running status without a channel status')
                first=[status];status=running
            if status==0xff:
                running=None;meta=track.byte();data=track.take(track.vlq())
                if meta==0x2f:
                    if data or track.pos!=len(body):raise MidiError('End-of-track must be empty and last')
                    ended=True;break
                if meta==3:title=data.decode('utf-8',errors='replace')
                if meta==0x51:
                    if len(data)!=3 or int.from_bytes(data,'big')==0:raise MidiError('Invalid tempo event')
                    tempos.append([tick,int.from_bytes(data,'big')])
            elif status in (0xf0,0xf7):
                running=None;track.take(track.vlq());sysex=True
            elif 0x80<=status<=0xef:
                running=status;length=1 if status>>4 in (0xc,0xd) else 2
                data=first+list(track.take(length-len(first)))
                if any(v>127 for v in data):raise MidiError('MIDI channel data byte exceeds 127')
                messages.append((tick,status,*data))
            else:raise MidiError(f'Unsupported SMF status 0x{status:02x}')
        if not ended:raise MidiError(f'Track {index}: missing end-of-track')
        tracks.append(Track(title,tick,messages,tempos,sysex))
    if reader.pos!=len(raw):raise MidiError('Unexpected data after declared MIDI tracks')
    return kind,ppq,tracks


def streams(tracks):
    result=[]
    for index,track in enumerate(tracks):
        counts=Counter(m[1]&15 for m in track.messages if m[1]>>4==9 and m[3]>0)
        for channel,count in sorted(counts.items()):
            result.append(dict(track=index,track_name=track.name,channel=channel,note_count=count,
                               percussion=channel==9,end_tick=track.end))
    return result


def convert(raw, *, track=None, channel=None, bpm=60, transpose=0, timbre=1, title='Imported melody'):
    if not 20<=bpm<=240:raise MidiError('BPM must be 20..240 quarter notes per minute')
    if timbre not in (0,1,2):raise MidiError('Timbre must be 0, 1 or 2')
    if not -127<=transpose<=127:raise MidiError('Transpose must be an explicit integer in -127..127')
    kind,ppq,tracks=parse(raw)
    choices=[s for s in streams(tracks) if (track is None or s['track']==track) and
             (channel is None or s['channel']==channel) and s['channel']!=9]
    if len(choices)!=1:raise MidiError('Select exactly one melody track/channel using --inspect, --track and --channel')
    selected=choices[0];source=tracks[selected['track']];channel=selected['channel']
    if any(t.sysex for t in tracks):raise MidiError('SysEx tuning/control data is unsupported; supply a notation-only MIDI')
    if selected['note_count']>MAX_EVENTS:raise MidiError('Selected melody exceeds 2048 events')
    scale=Fraction(SAMPLE_RATE*60,ppq*bpm)
    duration=round(source.end*scale)
    if not 0<duration<=MAX_TIME:raise MidiError('Melody including rests exceeds the ten-minute limit at this BPM')
    active=None;notes=[];ignored=Counter();source_pitches=[]
    for message in source.messages:
        tick,status,*data=message
        if status&15!=channel:continue
        command=status>>4
        if command==9 and data[1]>0:
            if active is not None:raise MidiError(f'tick {tick}: overlapping melody notes/chords; select a monophonic melody stream')
            active=(tick,data[0]);source_pitches.append(data[0])
        elif command==8 or (command==9 and data[1]==0):
            if active is None or active[1]!=data[0]:raise MidiError(f'tick {tick}: unmatched note-off')
            start,pitch=active;active=None
            onset=round(start*scale);end=round(tick*scale)
            if end<=onset:raise MidiError(f'tick {tick}: zero-length note after sample conversion')
            notes.append(Event(onset,end-onset,pitch+transpose,0))
        elif command==0xe:
            if data[0]+(data[1]<<7)!=8192:raise MidiError('Non-centred pitch bend cannot be represented by static MIDI notes')
            ignored['centred_pitch_bend']+=1
        elif command==0xb:
            if (data[0]==64 and data[1]>=64) or data[0] in (120,123):
                raise MidiError('Sustain/all-notes-off controls require an explicitly notated melody')
            ignored[f'cc_{data[0]}']+=1
        else:ignored[f'command_{command:x}']+=1
    if active is not None:raise MidiError('Unterminated note at end-of-track')
    low,high=min(source_pitches),max(source_pitches)
    if low+transpose<50 or high+transpose>72:
        allowed=f'{50-low}..{72-high}' if high-low<=22 else 'none (melody range is wider than D3..C5)'
        raise MidiError(f'MIDI range {low}..{high} does not fit D3..C5; uniform --transpose range: {allowed}; no pitch was folded or dropped')
    events=allocate(notes);validate(events,duration)
    payload,crc=payload_info(events)
    metadata=dict(status='READY_FOR_INTEGRATION',title=title,format_version=2,
        sample_rate_hz=SAMPLE_RATE,event_bits=96,event_bytes=16,event_count=len(events),
        duration_samples=duration,duration_seconds=duration/SAMPLE_RATE,
        bpm=bpm,tempo_policy='fixed quarter-note BPM; source tempo events reported, not applied',
        recommended_timbre=timbre,velocity_hint=2,transpose_semitones=transpose,
        midi_format=kind,ppq=ppq,selected_stream=selected,source_pitch_range=[low,high],
        output_pitch_range=[low+transpose,high+transpose],source_sha256=hashlib.sha256(raw).hexdigest(),
        source_tempos=[dict(track=i,events=t.tempos) for i,t in enumerate(tracks) if t.tempos],
        ignored_selected_channel_messages=dict(ignored),source_velocity_policy='fixed existing hardware velocity code 2',
        preserves='All selected notes, written rhythms, leading/trailing rests; no automatic repetition or clipping',
        crc32=crc,production_modified=False,hardware_verified=False)
    metadata['integration_required']=['combined bank capacity and catalogue',
        'generated BSRAM INIT', 'whole-song judgement/layout checks',
        'original-project synthesis, netlist regression and P&R/STA']
    header='t_on_samples,duration_samples,midi_note,lane,velocity_hint,flags,group_id\n'
    csv=header+''.join(f'{e.onset},{e.duration},{e.midi},{e.lane},{e.velocity},{e.flags},{e.group}\n' for e in events)
    outputs={'.csv':csv.encode(),'.mem':''.join(f'{e.word():024x}\n' for e in events).encode(),'.bin':payload}
    metadata['output_sha256']={suffix:hashlib.sha256(body).hexdigest() for suffix,body in outputs.items()}
    outputs['.json']=(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    return outputs,metadata


def write_outputs(prefix, outputs):
    paths={suffix:prefix.with_suffix(suffix) for suffix in outputs}
    if any(p.exists() for p in paths.values()):raise MidiError('Choose a new output prefix; existing files are preserved')
    prefix.parent.mkdir(parents=True,exist_ok=True);created=[]
    try:
        for suffix,path in paths.items():
            with path.open('xb') as stream:
                created.append(path);stream.write(outputs[suffix])
    except BaseException:
        for path in created:path.unlink()
        raise


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('midi',type=Path)
    parser.add_argument('output_prefix',type=Path,nargs='?')
    parser.add_argument('--inspect',action='store_true')
    parser.add_argument('--track',type=int,help='zero-based MIDI track index')
    parser.add_argument('--channel',type=int,help='zero-based MIDI channel, percussion channel 9 excluded')
    parser.add_argument('--bpm',type=int,default=60)
    parser.add_argument('--timbre',type=int,choices=[0,1,2],default=1)
    parser.add_argument('--transpose',type=int,default=0)
    parser.add_argument('--title',default='Imported melody')
    args=parser.parse_args()
    try:
        if args.midi.stat().st_size>8*1024*1024:raise MidiError('MIDI exceeds 8 MiB')
        raw=args.midi.read_bytes()
        if args.inspect:
            kind,ppq,tracks=parse(raw)
            print(json.dumps(dict(midi_format=kind,ppq=ppq,indices='zero-based',streams=streams(tracks)),ensure_ascii=True,indent=2))
            return
        if args.output_prefix is None:parser.error('output_prefix is required without --inspect')
        outputs,meta=convert(raw,track=args.track,channel=args.channel,bpm=args.bpm,
            timbre=args.timbre,transpose=args.transpose,title=args.title)
        write_outputs(args.output_prefix,outputs)
        print(f"PASS: {meta['event_count']} notes, {meta['duration_seconds']:.3f}s, {args.bpm} BPM; staged files only, production unchanged")
    except (ValueError,OSError) as error:raise SystemExit(str(error))


if __name__=='__main__':main()
