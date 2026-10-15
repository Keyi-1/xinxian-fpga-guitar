"""Physical allocation and unchanged-score regression, independent of RTL."""
from pathlib import Path
import csv
import json
import random
import subprocess
import unittest
from game_fingering import Note, OPEN_MIDI, FingeringError, assign, candidates

ROOT = Path(__file__).resolve().parent.parent


def legal(notes, positions):
    for i, (note, (lane, fret)) in enumerate(zip(notes, positions)):
        if OPEN_MIDI[lane]+fret != note.midi or not 0 <= fret <= 8:
            return False
        for other, (other_lane, _) in zip(notes[:i], positions[:i]):
            if lane == other_lane and max(note.onset, other.onset) < min(note.onset+note.duration, other.onset+other.duration):
                return False
    return True


def brute_possible(notes, positions=()):
    if len(positions) == len(notes):
        return legal(notes, positions)
    for position in candidates(notes[len(positions)].midi):
        trial = positions+(position,)
        if legal(notes[:len(trial)], trial) and brute_possible(notes, trial):
            return True
    return False


class FingeringTests(unittest.TestCase):
    def test_chords_and_exact_release_boundary(self):
        notes = [Note(0, 500, n) for n in OPEN_MIDI]
        positions = assign(notes)
        self.assertTrue(legal(notes, positions))
        self.assertEqual(len({lane for lane, _ in positions}), 4)
        self.assertEqual(assign([Note(0, 500, 50), Note(500, 500, 50)]), [(3, 0), (3, 0)])
        for notes in ([Note(0, 500, 50), Note(0, 500, 52)],
                      [Note(0, 1000, 50), Note(500, 100, 52)],
                      [Note(0, 500, 64)]*5, [Note(0, 100, 73)]):
            with self.assertRaises(FingeringError):
                assign(notes)

    def test_pruned_dead_end_is_not_reported_impossible(self):
        notes = [Note(0, 1000, 64), Note(500, 100, 68)]
        self.assertEqual(assign(notes, beam_width=1), [(1, 5), (0, 4)])

    def test_nearby_repeated_pitch_prefers_different_strings(self):
        notes = [Note(i*15000, 15000, 59) for i in range(8)]
        result = assign(notes)
        self.assertTrue(legal(notes, result))
        self.assertTrue(all(a[0] != b[0] for a, b in zip(result, result[1:])))

    def test_narrow_search_against_exhaustive_oracle(self):
        rng = random.Random(20261015)
        for _ in range(200):
            notes = [Note(rng.randrange(4)*100, rng.choice([100, 200, 400]), rng.randint(50, 72))
                     for _ in range(rng.randint(1, 7))]
            possible = brute_possible(notes)
            try:
                result = assign(notes, beam_width=1)
            except FingeringError:
                self.assertFalse(possible, notes)
            else:
                self.assertTrue(possible and legal(notes, result), notes)

    def test_current_jasmine_preserves_every_pitch_time_and_duration(self):
        old = subprocess.check_output(['git', 'show', 'a13fd79:mem/jasmine_game.mem'], cwd=ROOT).decode().splitlines()
        words = [int(s, 16) for s in (ROOT/'mem/jasmine_game.mem').read_text().splitlines()]
        self.assertEqual([int(s,16) & ~(3<<74) for s in old], [w & ~(3<<74) for w in words])
        manifest = json.loads((ROOT/'scores/jasmine.json').read_text(encoding='utf-8'))
        count = manifest['event_count']
        self.assertEqual(count, 67)
        with (ROOT/'scores/jasmine.csv').open(encoding='utf-8') as stream:
            rows = list(csv.DictReader(stream))
        notes = [Note(w & 0xffffff, (w>>24) & 0xffffff, row['midi_note'])
                 for w,row in zip(words, rows)]
        notes = [Note(n.onset, n.duration, int(n.midi)) for n in notes]
        positions = [(p['lane'], p['fret']) for p in manifest['fingering']]
        self.assertTrue(legal(notes, positions))
        self.assertEqual([(w>>74)&3 for w in words[:count]], [p[0] for p in positions])
        self.assertTrue(all(positions[i][0] != positions[i-1][0] for i in range(1, 8)))


if __name__ == '__main__':
    unittest.main()
