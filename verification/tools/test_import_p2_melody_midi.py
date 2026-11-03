"""Synthetic MIDI fixtures only; no commercial song transcription or production writes."""
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from game_score_v2 import from_binary, read_csv
from import_p2_melody_midi import MidiError, convert, parse, streams, write_outputs

ROOT=Path(__file__).resolve().parent.parent


def vlq(value):
    out=[value&127]
    while value>>7:
        value>>=7;out.insert(0,128|(value&127))
    return bytes(out)


def message(delta,data):return vlq(delta)+bytes(data)


def track(body,end_delta=0):
    raw=body+message(end_delta,[255,47,0])
    return b'MTrk'+struct.pack('>I',len(raw))+raw


def midi(*tracks,ppq=480,kind=None):
    if kind is None:kind=1 if len(tracks)>1 else 0
    return b'MThd'+struct.pack('>IHHH',6,kind,len(tracks),ppq)+b''.join(tracks)


def simple(pitch=64,channel=0,on=0,off=480):
    return track(message(on,[0x90|channel,pitch,90])+message(off,[0x80|channel,pitch,0]))


class MelodyImportTests(unittest.TestCase):
    def setUp(self):
        self.temp_root=ROOT/'sim/temp/p2_midi_tests'
        self.temp_root.mkdir(parents=True,exist_ok=True)

    def test_long_melody_all_notes_rests_timbre_and_round_trip(self):
        body=b'';previous=0
        for i in range(400):
            onset=(i+1)*480;pitch=(60,62,64,65)[i%4]
            body+=message(onset-previous,[144,pitch,1+i%127])+message(240,[128,pitch,0])
            previous=onset+240
        raw=midi(track(body,960));out,meta=convert(raw,title='Synthetic 400-note melody')
        events=from_binary(out['.bin'])
        self.assertEqual(len(events),400)
        self.assertEqual(meta['duration_samples'],19320000)
        self.assertGreater(meta['duration_samples'],2**24)
        self.assertEqual(meta['recommended_timbre'],1)
        self.assertFalse(meta['production_modified'])
        for i,e in enumerate(events):
            self.assertEqual((e.onset,e.duration,e.midi,e.velocity),((i+1)*48000,24000,(60,62,64,65)[i%4],2))
        with tempfile.TemporaryDirectory(dir=self.temp_root) as folder:
            prefix=Path(folder)/'melody';write_outputs(prefix,out)
            self.assertEqual(read_csv(prefix.with_suffix('.csv')),events)
            self.assertEqual([int(x,16) for x in out['.mem'].decode().splitlines()],[e.word() for e in events])
            report=json.loads(prefix.with_suffix('.json').read_text(encoding='utf-8'))
            self.assertEqual(report['source_sha256'],hashlib.sha256(raw).hexdigest())
            for suffix,value in report['output_sha256'].items():
                self.assertEqual(hashlib.sha256(prefix.with_suffix(suffix).read_bytes()).hexdigest(),value)

    def test_track_channel_selection_does_not_guess_melody_or_drum(self):
        raw=midi(simple(64,0),simple(59,1),simple(35,9))
        self.assertEqual(len(streams(parse(raw)[2])),3)
        with self.assertRaises(MidiError):convert(raw)
        out,meta=convert(raw,track=1,channel=1)
        self.assertEqual(from_binary(out['.bin'])[0].midi,59)
        self.assertEqual(meta['selected_stream']['track'],1)
        with self.assertRaises(MidiError):convert(raw,track=2,channel=9)
        with self.assertRaises(MidiError):convert(raw,track=30)

    def test_running_status_zero_velocity_and_fractional_sample_rounding(self):
        # Explicit note-on, implicit zero-velocity note-off, then another pair.
        raw=midi(track(message(1,[144,64,100])+message(2,[64,0])+
                       message(1,[64,100])+message(2,[64,0])),ppq=7)
        events=from_binary(convert(raw)[0]['.bin'])
        self.assertEqual(events[0].onset,round(Fraction(48000,7)))
        self.assertEqual(events[0].duration,round(Fraction(3*48000,7))-events[0].onset)
        self.assertEqual(events[1].onset,round(Fraction(4*48000,7)))
        self.assertNotEqual(events[0].lane,events[1].lane)

    def test_fixed_slow_tempo_retains_note_ticks_and_reports_original_map(self):
        conductor=track(message(0,[255,81,3,7,161,32])+message(480,[255,81,3,15,66,64]))
        raw=midi(conductor,simple())
        out,meta=convert(raw,bpm=60)
        self.assertEqual(from_binary(out['.bin'])[0].duration,48000)
        self.assertEqual(meta['source_tempos'][0]['events'],[[0,500000],[480,1000000]])
        self.assertEqual(meta['bpm'],60)

    def test_reject_polyphony_bad_note_pairs_and_unsupported_expression(self):
        bad=[message(0,[144,64,90])+message(120,[144,67,90]),
             message(0,[128,64,0]),message(0,[144,64,90]),
             message(0,[144,64,90])+message(0,[128,64,0]),
             message(0,[224,0,65])+message(0,[144,64,90])+message(480,[128,64,0]),
             message(0,[176,64,127])+message(0,[144,64,90])+message(480,[128,64,0])]
        for body in bad:
            with self.subTest(body=body):
                with self.assertRaises(MidiError):convert(midi(track(body)))
        with self.assertRaises(MidiError):convert(midi(track(message(0,[240,1,247])),simple()))

    def test_pitch_range_requires_explicit_uniform_transpose(self):
        raw=midi(simple(76))
        with self.assertRaisesRegex(MidiError,'no pitch was folded'):convert(raw)
        out,meta=convert(raw,transpose=-12)
        self.assertEqual(from_binary(out['.bin'])[0].midi,64)
        self.assertEqual(meta['transpose_semitones'],-12)

    def test_reject_unsupported_timing_truncation_missing_end_and_bad_status(self):
        bad=[b'',midi(simple(),ppq=0),midi(simple(),ppq=0xe728),midi(simple(),kind=2),
             midi(simple())[:-1],midi(simple())+b'garbage',
             midi(track(message(0,[64,90]))),midi(track(message(0,[0xf1,0]))),
             midi(track(b'\x81\x80\x80\x80\x00\x90\x40\x40')),
             midi(track(message(0,[144,128,90]))),
             midi(track(message(0,[255,81,1,4])))]
        # Valid MTrk length but no end-of-track marker.
        body=message(0,[144,64,90])+message(480,[128,64,0])
        bad.append(midi(b'MTrk'+struct.pack('>I',len(body))+body))
        for raw in bad:
            with self.subTest(raw=raw[:20]):
                with self.assertRaises(MidiError):parse(raw)

    def test_limits_density_and_rounding_are_rejected_without_dropping(self):
        with self.assertRaisesRegex(MidiError,'ten-minute'):convert(midi(simple(off=480*601)))
        for bpm in (0,241):
            with self.assertRaises(MidiError):convert(midi(simple()),bpm=bpm)
        # A dense single-string C5 line must not be thinned to fit the UI.
        body=b''
        for _ in range(9):body+=message(0,[144,72,90])+message(120,[128,72,0])
        with self.assertRaises(ValueError):convert(midi(track(body)))
        body=b''
        for _ in range(2049):body+=message(0,[144,64,90])+message(480,[128,64,0])
        with self.assertRaisesRegex(MidiError,'2048'):convert(midi(track(body)))

    def test_cli_inspect_and_refuse_existing_outputs(self):
        with tempfile.TemporaryDirectory(dir=self.temp_root) as folder:
            source=Path(folder)/'source.mid';source.write_bytes(midi(simple()))
            prefix=Path(folder)/'new_score'
            command=[sys.executable,str(ROOT/'tools/import_p2_melody_midi.py'),str(source)]
            result=subprocess.run(command+['--inspect'],capture_output=True,check=True)
            self.assertEqual(json.loads(result.stdout)['streams'][0]['note_count'],1)
            self.assertFalse(prefix.with_suffix('.mem').exists())
            subprocess.run(command+[str(prefix)],capture_output=True,check=True)
            before={p:p.read_bytes() for p in Path(folder).iterdir()}
            result=subprocess.run(command+[str(prefix)],capture_output=True)
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(before,{p:p.read_bytes() for p in Path(folder).iterdir()})

    def test_partial_write_cleanup_and_production_file_refusal(self):
        out,_=convert(midi(simple()))
        with tempfile.TemporaryDirectory(dir=self.temp_root) as folder:
            prefix=Path(folder)/'partial';sentinel=Path(folder)/'user.txt'
            sentinel.write_text('preserve user content')
            original=Path.open
            def fail_second(path,*args,**kwargs):
                if path==prefix.with_suffix('.mem'):raise OSError('injected write failure')
                return original(path,*args,**kwargs)
            with patch.object(Path,'open',fail_second):
                with self.assertRaises(OSError):write_outputs(prefix,out)
            self.assertEqual(list(Path(folder).iterdir()),[sentinel])
            self.assertEqual(sentinel.read_text(),'preserve user content')
        production=ROOT/'mem/game_p2_static.mem';before=production.read_bytes()
        with self.assertRaises(MidiError):write_outputs(production.with_suffix(''),out)
        self.assertEqual(production.read_bytes(),before)


if __name__=='__main__':unittest.main()
