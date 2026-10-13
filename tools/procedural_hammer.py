"""Independent sample-domain integer noise/resonator model for RTL verification."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]


def random_step(x):
    x ^= (x << 13) & 0xffffffff
    x ^= x >> 17
    x ^= (x << 5) & 0xffffffff
    return x & 0xffffffff


class HammerModel:
    def __init__(self, seed=0x6d2b79f5, coefficients=None):
        self.coefficients=coefficients or json.loads((ROOT/'mem/piano_hammer_model.json').read_text())
        self.random=seed or 1
        self.y1=[0]*3
        self.y2=[0]*3
        self.lowpass=[[0]*4 for _ in range(3)]
        self.slow=self.fast=0

    def sample(self, on, active, age, bank):
        noises=[]
        for band in range(3):
            self.random=random_step(self.random)
            noise=self.random >> 16
            raw=noise-65536 if noise>=32768 else noise
            previous=raw
            filtered=[]
            noises.append(self.lowpass[band][-1])
            for old in self.lowpass[band]:
                filtered.append(old+((previous-old)>>2))
                previous=old
            self.lowpass[band]=filtered
        p=self.coefficients['profiles'][bank]
        if on:
            self.y1=[0]*3;self.y2=[0]*3
            self.slow=self.fast=p['envelope_start_q24']
        else:
            self.slow=max(0,self.slow-(self.slow>>10)-(self.slow>>11)
                          -((self.slow>>6) if age>=1664 else 0))
            self.fast=max(0,self.fast-(self.fast>>5)-(self.fast>>6))
        total=0
        for band in range(3):
            y=(noises[band]>>p['noise_shifts'][band])-((p['a1_q14'][band]*self.y1[band]+p['a2_q14'][band]*self.y2[band])>>14)
            y=min(max(y,-131072),131071) if active and age<2048 else 0
            total += y-self.y2[band]
            self.y2[band],self.y1[band]=self.y1[band],y
        # The 18-bit shared multiplier takes a bounded filter sum.
        total=min(max(total,-131072),131071)
        envelope=max(0,self.slow-self.fast)>>9
        value=(total*envelope)>>15
        return min(max(value,-2048),2048) if active and age<2048 else 0
