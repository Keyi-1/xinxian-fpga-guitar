"""Independent sample-domain fixed-point oracle; no HDL scheduling or DSP pipeline.

Uses committed ROMs only and Python's unbounded integer arithmetic, so this
verification needs neither SciPy nor the user's original WAVs. Tests register
changes, four velocities, same-sample on/off, slides, damping and re-strikes.
"""
from pathlib import Path
import math

ROOT=Path(__file__).resolve().parents[1]
FS=48000
MASK=(1<<32)-1


def read(name,signed=False):
    data=[int(line,16) for line in (ROOT/'mem'/name).read_text().split()]
    return [v-65536 if v>=32768 else v for v in data] if signed else data


def pitch(f):
    return round(f*(1<<32)/FS)


def stimulus(frame):
    if frame<1024: f=261.625565;vel=0
    elif frame<4096:f=329.627557;vel=1
    elif frame<16384:
        f=391.995436*2**(min(max(frame-8192,0),960)/960/12);vel=2
    else:f=329.627557 if frame<17600 else 369.994423;vel=3
    return pitch(f),vel,int(frame in (0,1024,4096,16384,17600)),int(frame in (256,1024,3072,12288,18432))


def generate(hammer_on):
    lut=read('sine_lut.mem',True)
    ratios=read('piano_ratio.mem');envelopes=read('piano_envelope.mem')
    seeds=read('piano_phase.mem');hammers=read('piano_hammer.mem',True)
    phase=[0]*8;age=0;active=False;releasing=False;release=0;gain=0;profile=0;continuity=0;last_pcm=0
    rows=[]
    for frame in range(32000):
        increment,velocity,on,off=stimulus(frame)
        frame_active=active or bool(on)
        frame_age=age
        if on:
            profile=0 if increment<26276679 else 1 if increment<32164062 else 2
            phase=seeds[profile*8:profile*8+8].copy()
            active=True;releasing=False;release=0xffffff;gain=(112,160,208,256)[velocity]
            age=0;frame_age=0;continuity=last_pcm
        else:
            continuity=0 if -64<continuity<64 else continuity-(continuity>>6)
            if active:
                old_release=releasing
                if off:releasing=True
                if age>=131071 or (old_release and release<=256):
                    active=False;release=0;continuity=0
                else:
                    age+=1
                    if old_release:release-=max(release>>10,1)
        total=0
        env_index=frame_age>>9
        fraction=frame_age&511
        for mode in range(8):
            product=increment*ratios[profile*8+mode]
            phase[mode]=(phase[mode]+(product>>20))&MASK
            address=(profile*8+mode)*256+env_index
            a=envelopes[address];b=envelopes[min(address+1,(profile*8+mode)*256+255)]
            amplitude=a+((b-a)*fraction>>9) if frame_active and product<(1<<51) else 0
            total+=(lut[phase[mode]>>22]*amplitude)>>7
        if hammer_on and frame_active and frame_age<2048:
            total+=hammers[profile*2048+frame_age]<<8
        output=(((total*gain)>>8)*(release>>8)>>16)+continuity
        output=min(max(output,-8388608),8388607)
        last_pcm=output
        rows.append((output,int(active),profile))
    return rows


def main():
    with_hammer=generate(True);without=generate(False)
    out=ROOT/'sim'/'temp';out.mkdir(parents=True,exist_ok=True)
    with (out/'piano_voice_golden.txt').open('w',encoding='ascii') as f:
        for frame,(a,b) in enumerate(zip(with_hammer,without)):
            inc,vel,on,off=stimulus(frame)
            assert a[1:]==b[1:]
            f.write(f'{inc:08X} {vel} {on} {off} {a[0]&0xffffff:06X} {b[0]&0xffffff:06X} {a[1]} {a[2]}\n')
    assert with_hammer[-1][1]==0 and with_hammer[-1][0]==0
    assert all(abs(x[0])<8388607 for x in with_hammer)
    print('Generated 32000 sample-domain oracle frames, hammer on/off, three profiles and all velocities.')


if __name__=='__main__':main()
