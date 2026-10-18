"""Check the supplied-image transcription, exact timing, and game-only range."""
from fractions import Fraction
import json
from pathlib import Path
import unittest

from game_score_v2 import Event, allocate, from_binary, payload_info, phase, validate
from qing_ge_user_score import compile_score, SOURCE, ROOT


class QingGeScoreTests(unittest.TestCase):
    def test_all_bars_rhythm_ties_and_full_duration(self):
        events,duration,report=compile_score()
        self.assertEqual((report['measures'],report['total_quarter_beats'],len(events),duration),(38,'152',212,7296000))
        self.assertEqual(report['tie_continuations'],30)
        self.assertEqual(report['rest_tokens'],13)
        self.assertEqual([x['bar'] for x in report['rhythm_revisions']],[10,10,18,18])
        self.assertEqual(report['output_midi_range'],[50,79])
        self.assertEqual(report['source_midi_range'],[62,91])
        for note in report['printed_note_tokens']:
            self.assertEqual(note['output_midi'],note['source_midi']-12)
        # Bar 5's final B is tied into bar 6, no second launch at the barline.
        b=[e for e in events if e.onset==round(Fraction(39,2)*48000)]
        self.assertEqual(len(b),1)
        self.assertEqual((b[0].midi,b[0].duration),(59,48000))
        self.assertFalse(any(e.onset==20*48000 for e in events))
        # Last G lasts the complete four-beat final measure.
        self.assertEqual((events[-1].onset,events[-1].duration,events[-1].midi),(148*48000,4*48000,67))
        # The printed double upper tonic in bar 36 must not be silently folded.
        high=[e for e in events if e.midi==79]
        self.assertEqual([(e.onset,e.duration) for e in high],[(round(Fraction(285,2)*48000),24000)])

    def test_confirmed_bar_grid_and_every_other_event_unchanged(self):
        from preview_qing_ge_rhythm import baseline_score,candidate
        before,total=baseline_score()
        expected,changes=candidate(before,total)
        actual,duration,_=compile_score()
        self.assertEqual(duration,total)
        self.assertEqual(actual,expected)
        self.assertEqual(len(changes),4)
        for bar in (10,18):
            start=(bar-1)*4*48000
            selected=[e for e in actual if start<=e.onset<start+4*48000]
            self.assertEqual([e.onset-start for e in selected],[0,24000,36000,60000,84000,144000,160000,176000])
            self.assertEqual([e.duration for e in selected],[24000,12000,24000,24000,60000,16000,16000,16000])

    def test_explicit_profile_preserves_physical_default(self):
        high=Event(0,48000,79,0)
        with self.assertRaises(ValueError):validate([high])
        with self.assertRaises(ValueError):phase(79)
        self.assertGreater(phase(79,profile='game_extended'),2**26)
        self.assertLess(phase(79,profile='game_extended'),2**27)
        validate([high],profile='game_extended')
        with self.assertRaises(ValueError):validate([Event(0,1,80,0)],profile='game_extended')
        with self.assertRaises(ValueError):validate([high],profile='unknown')
        for midi in range(50,73):self.assertEqual(phase(midi),phase(midi,profile='game_extended'))

    def test_extended_allocation_and_binary_keep_every_event(self):
        notes=[Event(i*12000,12000,79,0) for i in range(16)]
        allocated=allocate(notes,profile='game_extended')
        self.assertEqual([(e.onset,e.duration,e.midi) for e in allocated],[(e.onset,e.duration,e.midi) for e in notes])
        # Nearby-string preference is a cost, as in the accepted allocator;
        # pitch/fret comfort can outweigh it. It must distribute this dense run.
        self.assertGreater(len({e.lane for e in allocated}),1)
        for lane in range(4):
            chosen=[e for e in allocated if e.lane==lane]
            self.assertTrue(all(a.onset+a.duration<=b.onset for a,b in zip(chosen,chosen[1:])))
        payload,_=payload_info(allocated)
        self.assertEqual(from_binary(payload,profile='game_extended'),allocated)
        with self.assertRaises(ValueError):from_binary(payload)

    def test_generated_production_mapping_and_unchanged_other_songs(self):
        from generate_p2_static_scores import build
        import subprocess
        outputs,manifest=build()
        for path,value in outputs.items():self.assertEqual((ROOT/path).read_bytes(),value,path)
        self.assertEqual(manifest['total_events'],959)
        self.assertEqual(manifest['slots'][3]['count'],212)
        self.assertEqual(manifest['slots'][4]['offset'],703)
        for alias in ['jasmine','slow_arpeggio','seven_nation_riff','time_10min']:
            for suffix in ['csv','bin']:
                path=f'scores/p2/{alias}.{suffix}'
                self.assertEqual((ROOT/path).read_bytes(),subprocess.check_output(['git','show',f'5b13b5d:{path}'],cwd=ROOT))


if __name__=='__main__':unittest.main()
