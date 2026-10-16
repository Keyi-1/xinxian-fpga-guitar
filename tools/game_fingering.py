"""Offline string/fret allocation, using sample times and unaltered pitches.

A beam ranks comfortable candidates first. If pruning reaches a dead end,
an exhaustive, memoized feasibility pass distinguishes that from a genuinely
unplayable score. Only the resulting event metadata is sent to the FPGA.
"""
from dataclasses import dataclass

OPEN_MIDI = (64, 59, 55, 50)


class FingeringError(ValueError):
    pass


@dataclass(frozen=True)
class Note:
    onset: int
    duration: int
    midi: int


def candidates(midi):
    return [(lane, midi-base) for lane, base in enumerate(OPEN_MIDI)
            if 0 <= midi-base <= 8]


def assign(notes, sample_rate=48000, beam_width=128, *, candidate_fn=candidates):
    if not notes:
        return []
    if beam_width < 1 or sample_rate < 1:
        raise ValueError('positive sample rate and beam width required')
    groups = {}
    for index, note in enumerate(notes):
        if note.onset < 0 or note.duration <= 0:
            raise FingeringError(f'event {index}: invalid onset/duration')
        choices = candidate_fn(note.midi)
        if not choices:
            raise FingeringError(f'event {index}: MIDI {note.midi} outside the 0..8-fret instrument')
        groups.setdefault(note.onset, []).append((index, note, choices))
    ordered = sorted(groups.items())
    for onset, group in ordered:
        if len(group) > 4:
            raise FingeringError(f't={onset}: {len(group)} simultaneous notes exceed four strings')

    def alternatives(group, ends):
        def visit(i, used, picks):
            if i == len(group):
                yield tuple(picks)
                return
            index, note, choices = group[i]
            for lane, fret in choices:
                if lane in used or ends[lane] > note.onset:
                    continue
                yield from visit(i+1, used | {lane}, picks+[(index, note, lane, fret)])
        yield from visit(0, set(), [])

    # cost, occupied-until, last onset, previous fret, assignment history
    initial = (0., (-1,)*4, (-100*sample_rate,)*4, (0,)*4, ())

    def extend(state, picks):
        cost, ends, last, frets, history = state
        ends, last, frets = list(ends), list(last), list(frets)
        for _, note, lane, fret in picks:
            gap = (note.onset-last[lane])/sample_rate
            cost += fret*.8 + abs(fret-frets[lane])*.3 + max(0., 1-gap/.75)*85
            ends[lane] = note.onset+note.duration
            last[lane], frets[lane] = note.onset, fret
        pressed = [p[3] for p in picks if p[3]]
        if pressed:
            cost += max(pressed)**2*.3 + (max(pressed)-min(pressed))**2*2
        return cost, tuple(ends), tuple(last), tuple(frets), history+picks

    beam = [initial]
    for _, group in ordered:
        expanded = [extend(state, picks) for state in beam
                    for picks in alternatives(group, state[1])]
        if not expanded:
            break
        expanded.sort(key=lambda state: state[0])
        unique = {}
        for state in expanded:
            unique.setdefault(state[1:4], state)
            if len(unique) == beam_width:
                break
        beam = list(unique.values())
    else:
        return _result(beam[0][4], len(notes))

    # Hard feasibility depends on occupied intervals, not cost or old frets.
    failed = set()

    def feasible(group_index, state):
        if group_index == len(ordered):
            return state
        onset, group = ordered[group_index]
        key = group_index, tuple(max(onset, end) for end in state[1])
        if key in failed:
            return None
        choices = [extend(state, p) for p in alternatives(group, state[1])]
        for next_state in sorted(choices, key=lambda s: s[0]):
            found = feasible(group_index+1, next_state)
            if found is not None:
                return found
        failed.add(key)
        return None

    found = feasible(0, initial)
    if found is None:
        raise FingeringError('no legal allocation: overlapping durations or simultaneous notes conflict')
    return _result(found[4], len(notes))


def _result(history, count):
    result = [None]*count
    for index, _, lane, fret in history:
        result[index] = lane, fret
    assert all(position is not None for position in result)
    return result
