"""P2 note-event compiler. No audio/PCM, network access or hardware programming.

Runtime: 96 bits = onset32/duration32/MIDI7/lane2/velocity2/flags5/group16.
Transport v2: 16-byte little-endian records, reserved fields checked, CRC32.
"""
from dataclasses import dataclass, replace
from fractions import Fraction
import csv
import struct
import zlib
from game_fingering import Note, assign, candidates

SAMPLE_RATE = 48000
MAX_EVENTS = 2048
MAX_TIME = SAMPLE_RATE * 600
WINDOW_SIZE = 64
VISIBLE_SPAN = 101000 + 7200
RECORD = struct.Struct('<IIBBBBHH')


@dataclass(frozen=True)
class Event:
    onset: int
    duration: int
    midi: int
    lane: int
    velocity: int = 2
    flags: int = 0
    group: int = 0

    def word(self):
        return (self.onset | self.duration << 32 | self.midi << 64 |
                self.lane << 71 | self.velocity << 73 | self.flags << 75 | self.group << 80)

    def binary(self):
        return RECORD.pack(self.onset, self.duration, self.midi, self.lane,
                           self.velocity, self.flags, self.group, 0)


def phase(midi):
    if not 50 <= midi <= 72:
        raise ValueError('MIDI outside existing D3..C5 instrument')
    return round(440 * 2 ** ((midi - 69) / 12) * 2 ** 32 / SAMPLE_RATE)


def decode(word):
    return Event(word & 0xffffffff, word >> 32 & 0xffffffff,
                 word >> 64 & 127, word >> 71 & 3, word >> 73 & 3,
                 word >> 75 & 31, word >> 80 & 65535)


def from_binary(payload):
    if not payload or len(payload) % RECORD.size:
        raise ValueError('incomplete/empty v2 payload')
    events = []
    for onset, duration, midi, lane, velocity, flags, group, reserved in RECORD.iter_unpack(payload):
        if reserved:
            raise ValueError('reserved field must be zero')
        events.append(Event(onset, duration, midi, lane, velocity, flags, group))
    validate(events)
    return events


def validate(events, duration=None):
    if not 1 <= len(events) <= MAX_EVENTS:
        raise ValueError('event capacity must be 1..2048')
    last_onset = -1
    ends = [-1] * 4
    onsets = [[] for _ in range(4)]
    for i, event in enumerate(events):
        if not 0 <= event.onset <= MAX_TIME or not 1 <= event.duration <= MAX_TIME:
            raise ValueError(f'event {i}: invalid sample time')
        if event.onset + event.duration > MAX_TIME:
            raise ValueError(f'event {i}: end exceeds 10 minutes')
        if event.onset < last_onset:
            raise ValueError(f'event {i}: unsorted events')
        if not 0 <= event.lane < 4 or not any(lane == event.lane for lane, _ in candidates(event.midi)):
            raise ValueError(f'event {i}: unsupported lane/pitch')
        if not 0 <= event.velocity < 4 or event.flags or not 0 <= event.group <= 65535:
            raise ValueError(f'event {i}: invalid velocity/flags/group')
        lane = event.lane
        if ends[lane] > event.onset:
            raise ValueError(f'event {i}: overlapping notes on one string')
        if onsets[lane] and event.onset - onsets[lane][-1] < 12000:
            raise ValueError(f'event {i}: same-string onsets under 250 ms')
        ends[lane] = event.onset + event.duration
        onsets[lane].append(event.onset)
        last_onset = event.onset
    for lane in onsets:
        first = 0
        for last, onset in enumerate(lane):
            while onset - lane[first] > VISIBLE_SPAN:
                first += 1
            if last - first + 1 > 8:
                raise ValueError('more than eight visible blocks on a lane')
    if duration is not None and not max(ends) <= duration <= MAX_TIME:
        raise ValueError('invalid declared song duration')
    return events


def allocate(notes):
    """Use the accepted allocator: no overlap, nearby notes prefer another string."""
    positions = assign([Note(e.onset, e.duration, e.midi) for e in notes])
    result = [replace(e, lane=lane) for e, (lane, _) in zip(notes, positions)]
    validate(result)
    return result


def read_csv(path, bpm=60):
    """CSV uses exact beat fractions, or explicit 48 kHz sample timestamps."""
    events = []
    lanes = []
    if not 20 <= bpm <= 240:
        raise ValueError('BPM must be 20..240')
    with path.open(newline='', encoding='utf-8-sig') as stream:
        for row in csv.DictReader(stream):
            if 'onset_beats' in row:
                onset = round(Fraction(row['onset_beats']) * SAMPLE_RATE * 60 / bpm)
                duration = round(Fraction(row['duration_beats']) * SAMPLE_RATE * 60 / bpm)
            else:
                onset, duration = int(row['t_on_samples']), int(row['duration_samples'])
            lane = row.get('lane', '').strip()
            lanes.append(lane)
            events.append(Event(onset, duration, int(row['midi_note']), int(lane) if lane else 0,
                                int(row.get('velocity_hint', '') or 2),
                                int(row.get('flags', '') or 0), int(row.get('group_id', '') or 0)))
    if any(lanes) and not all(lanes):
        raise ValueError('specify every lane or let allocator choose every lane')
    return validate(events) if all(lanes) else allocate(events)


def payload_info(events):
    payload = b''.join(e.binary() for e in events)
    return payload, f'{zlib.crc32(payload):08x}'
