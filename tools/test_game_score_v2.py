from pathlib import Path
from dataclasses import replace
import json
import struct
import tempfile
import unittest
from game_score_v2 import Event, allocate, decode, from_binary, payload_info, read_csv, validate, phase, MAX_TIME
from generate_p2_static_scores import build, ROOT


class ScoreV2Tests(unittest.TestCase):
    def test_exact_jasmine_migration_and_generated_outputs(self):
        outputs, manifest = build()
        for name, data in outputs.items():
            self.assertEqual((ROOT/name).read_bytes(), data, name)
        old = [int(s,16) for s in (ROOT/'mem/jasmine_game.mem').read_text().splitlines()]
        words = outputs['mem/game_p2_static.mem'].decode().splitlines()
        for before, line in zip(old[:67],words):
            e = decode(int(line,16))
            self.assertEqual(before, (e.lane<<74)|(phase(e.midi)<<48)|(e.duration<<24)|e.onset)
        self.assertEqual(manifest['slots'][3]['alias'], 'QING_GE_INTRO')
        self.assertTrue(manifest['slots'][3]['valid'])
        self.assertEqual(manifest['slots'][3]['count'],128)
        self.assertEqual(manifest['slots'][1]['timbre'],1)
        self.assertEqual(manifest['slots'][2]['timbre'],2)

    def test_wire_and_runtime_round_trip(self):
        events = [Event(1, 4000, 64, 0, 3, 0, 65535),Event(16000000, 10000, 50, 3)]
        payload,_ = payload_info(events)
        self.assertEqual(from_binary(payload),events)
        for e in events:
            self.assertEqual(decode(e.word()),e)
        broken=bytearray(payload);broken[14]=1
        with self.assertRaises(ValueError):from_binary(broken)
        for bad in [payload[:-1],b'']:
            with self.assertRaises(ValueError):from_binary(bad)

    def test_reject_invalid_pitch_flags_overlap_order_time(self):
        e=Event(0,24000,64,0)
        for invalid in [replace(e,midi=73),replace(e,lane=3),replace(e,onset=-1),replace(e,duration=0),
                        replace(e,onset=MAX_TIME,duration=1),replace(e,flags=1),replace(e,velocity=4),replace(e,group=65536)]:
            with self.assertRaises(ValueError):validate([invalid])
        for bad in [[e,replace(e,onset=12000)], [replace(e,onset=30000),e]]:
            with self.assertRaises(ValueError):validate(bad)

    def test_density_capacity_and_exact_limits(self):
        with self.assertRaises(ValueError):validate([])
        with self.assertRaises(ValueError):validate([Event(i*12000,1000,64,0) for i in range(9)])
        events=allocate([Event(i*14000,1000,59,0) for i in range(2048)])
        self.assertEqual(len(validate(events)),2048)
        with self.assertRaises(ValueError):validate(events+[Event(MAX_TIME-1,1,64,0)])
        validate([Event(MAX_TIME-1,1,64,0)],MAX_TIME)
        with self.assertRaises(ValueError):validate([Event(10,20,64,0)],29)

    def test_rational_beats_slow_tempo_and_auto_allocation(self):
        temp_root=ROOT/'sim/temp/p2_python'
        temp_root.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=temp_root) as folder:
            Path(folder).resolve().relative_to(temp_root.resolve())
            p=Path(folder)/'score.csv'
            p.write_text('onset_beats,duration_beats,midi_note\n0,1/3,59\n1/3,1/3,59\n2/3,1/3,59\n')
            events=read_csv(p,bpm=60)
            self.assertEqual([e.onset for e in events],[0,16000,32000])
            self.assertTrue(all(a.lane!=b.lane for a,b in zip(events,events[1:])))
            p.write_text('t_on_samples,duration_samples,midi_note,lane\n0,1000,64,0\n24000,1000,59,\n')
            with self.assertRaises(ValueError):read_csv(p)
            with self.assertRaises(ValueError):read_csv(p,bpm=0)


if __name__=='__main__':unittest.main()
