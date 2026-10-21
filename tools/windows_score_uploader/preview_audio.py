"""Sample-aligned reference synthesis for PC audition, not an FPGA audio model.

Streams bounded blocks to PCM WAV: no numpy, recorded samples or device IO.
The score remains immutable; pauses/ties are represented by its existing events.
"""
from array import array
from functools import lru_cache
import math
from pathlib import Path
import sys
import threading
import wave

from game_score_v2 import validate
from .core import Cancelled

RATE = 48000
TABLE_BITS = 12
TABLE_SIZE = 1 << TABLE_BITS
MASK = (1 << 32) - 1
VELOCITIES = (.25, .5, .75, 1.0)


@lru_cache(maxsize=3)
def tables(timbre):
    # All partial weights sum to one; 0.18 per voice leaves four-voice headroom.
    weights = ((1, .36, .15, .07), (1, .65, .34, .2, .12, .07),
               (1, .15, .8, .1, .48, .08, .2))[timbre]
    norm = sum(weights)
    bright, soft = [], []
    for i in range(TABLE_SIZE):
        angle = math.tau * i / TABLE_SIZE
        bright.append(round(32767 * .18 * sum(w * math.sin((h+1)*angle)
                            for h,w in enumerate(weights)) / norm))
        soft.append(round(32767 * .18 * math.sin(angle)))
    lfo = tuple((1 + math.sin(math.tau*i/TABLE_SIZE)) / 2 for i in range(TABLE_SIZE))
    return tuple(bright), tuple(soft), lfo


def render_preview(score, destination, cancel=None, progress=None, block_size=8192):
    """Write exactly score.duration frames. A cancelled render leaves no WAV."""
    validate(score.events, score.duration, profile="game_extended")
    if score.timbre not in range(3) or not 1 <= block_size <= 65536:
        raise ValueError("试听音色或缓冲区大小无效。")
    destination = Path(destination)
    cancel = cancel or threading.Event()
    if cancel.is_set():
        raise Cancelled("已取消生成电脑试听。")
    bright, soft, lfo = tables(score.timbre)
    tau = (1.8, 1.1, 1.5)[score.timbre]
    decay_rate = 1 / (RATE * tau)
    steps = [round(440 * 2**((e.midi-69)/12) * (1 << 32) / RATE) for e in score.events]
    lfo_step = round(1.6 * (1 << 32) / RATE)
    active, cursor = [], 0
    created = False
    try:
        # Never overwrite a preexisting path, including a user's audio file.
        with destination.open('xb') as stream:
            created = True
            with wave.open(stream, 'wb') as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(RATE)
                for start in range(0, score.duration, block_size):
                    if cancel.is_set():
                        raise Cancelled("已取消生成电脑试听。")
                    end = min(start+block_size, score.duration)
                    while cursor < len(score.events) and score.events[cursor].onset < end:
                        active.append(cursor)
                        cursor += 1
                    active = [i for i in active if score.events[i].onset+score.events[i].duration > start]
                    mix = array('i', [0]) * (end-start)
                    for i in active:
                        e = score.events[i]
                        first, last = max(start,e.onset), min(end,e.onset+e.duration)
                        attack = min(240, max(1, e.duration//4))
                        release = min(1200, max(1, e.duration//3))
                        age = first-e.onset
                        phase = age*steps[i] & MASK
                        for absolute in range(first, last):
                            index = phase >> (32-TABLE_BITS)
                            value = bright[index]
                            if score.timbre == 2:
                                opening = lfo[(age*lfo_step & MASK) >> (32-TABLE_BITS)]
                                value = soft[index] + opening*(value-soft[index])
                            envelope = (.2 + .8*math.exp(-age*decay_rate))
                            envelope *= min(1, age/attack, (e.duration-1-age)/release)
                            mix[absolute-start] += round(value*VELOCITIES[e.velocity]*envelope)
                            age += 1
                            phase = (phase+steps[i]) & MASK
                    # validate() guarantees <=4 non-overlapping voices, so the
                    # normalized per-voice bound makes int16 conversion safe.
                    pcm = array('h', mix)
                    if sys.byteorder != 'little':
                        pcm.byteswap()
                    wav.writeframesraw(pcm.tobytes())
                    if progress:
                        progress(end, score.duration)
                if cancel.is_set():
                    raise Cancelled("已取消生成电脑试听。")
    except Exception:
        if created:
            destination.unlink(missing_ok=True)
        raise
    return destination
