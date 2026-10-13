"""32-mode numerical oracle using unbounded integers and sample-domain state."""
from gen_piano_golden import ROOT,read,pitch,MASK
from procedural_hammer import HammerModel

def stimulus(n):
    inc=pitch((261.625565,329.627557,391.995436)[min(n//4000,2)])
    # Exercise both timbres and their crossfade, with fifth mode split, release,
    # sustain removal and re-strike. On/off coincidence retains pluck priority.
    blend=0 if n<1000 else min((n-1000)//4,256) if n<2400 else 256 if n<8000 else 0
    return inc,n//3000, int(n in (0,2400,4000,8000)),int(n in (1800,2400,5000,9000)),blend,int(4000<=n<6500),int(n>=4000)

def main():
    lut=read('sine_lut.mem',True);ratios=read('piano_ratio.mem');env=read('piano_envelope.mem')
    seeds=read('piano_phase.mem');hammer=HammerModel()
    gains=read('piano_bright_gain.mem');decays=read('harmonic_decay_rock.mem')
    phases=[0]*32;bright=[0]*32;age=0;active=False;releasing=False
    release=0;gain=0;profile=0;last=0;continuity=0;harmony=False;shift=10
    age_phase=0;decay_phase=0
    lines=[]
    for n in range(12000):
        inc,vel,on,off,blend,sustain,harm=stimulus(n)
        frame_active=active or on;frame_age=age
        decay_step=decay_phase==0 if sustain else (decay_phase&3)==0
        if on:
            profile=0 if inc<26276679 else 1 if inc<32164062 else 2
            harmony=bool(harm);active=True;releasing=False;release=0xffffff
            gain=(112,160,208,256)[vel];age=0;frame_age=0;continuity=last;shift=10
            age_phase=0;decay_phase=0;decay_step=True
            phases=[seeds[profile*8+(m-16 if harmony and 16<=m<24 else m)] if m<8 or (harmony and 16<=m<24) else 0 for m in range(32)]
            bright=[gains[m-16 if harmony and m>=16 else m]<<8 for m in range(32)]
        else:
            old_age_phase=age_phase;age_phase=(age_phase+1)&3;decay_phase=(decay_phase+1)&15
            continuity=0 if -64<continuity<64 else continuity-(continuity>>6)
            if active:
                old_releasing=releasing;old_shift=shift;shift=10
                if off:releasing=True
                if age>=131071 or (old_releasing and release<=256):active=False;release=0;continuity=0
                else:
                    if not sustain or age<2048 or old_age_phase==3:age+=1
                    if old_releasing and not sustain:release-=max(release>>old_shift,1)
        total=bright_total=0
        body=0
        for mode in range(32):
            fifth=harmony and mode>=16;local=mode-16 if fifth else mode
            ratio=ratios[profile*8+local] if local<8 else (local+1)<<20
            product=((inc*1571089)>>20 if fifth else inc)*ratio
            phases[mode]=(phases[mode]+(product>>20))&MASK
            address=(profile*8+(local%8))*256+(frame_age>>9)
            a=env[address];b=env[min(address+1,(profile*8+(local%8))*256+255)]
            observed=(a*(512-(frame_age&511))+b*(frame_age&511))>>9
            if local==0:body=observed
            enabled=frame_active and product<(1<<51)
            amp=observed if local<8 and enabled else 0
            bright_amp=(body*bright[mode])>>23 if enabled else 0
            if fifth:amp>>=1;bright_amp>>=1
            sine=lut[phases[mode]>>22]
            total+=(sine*amp)>>7;bright_total+=(sine*bright_amp)>>7
            if decay_step:bright[mode]=(bright[mode]*decays[local])>>15
        total+=hammer.sample(bool(on),frame_active,frame_age,profile)<<8
        total=(total*(256-blend)+bright_total*blend)>>8
        if harmony:total=(total>>1)+(total>>2)
        output=(((total*gain)>>8)*(release>>8)>>16)+continuity
        last=min(max(output,-8388608),8388607)
        lines.append(f'{inc:08X} {vel} {on} {off} {blend} {sustain} {harm} {last&0xffffff:06X} {int(active)}\n')
    (ROOT/'sim/temp/full_piano_golden.txt').write_text(''.join(lines),encoding='ascii')
    print('Generated 12000 independent full-piano reference samples.')
if __name__=='__main__':main()
