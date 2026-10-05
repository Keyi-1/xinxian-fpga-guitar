"""Independent sample-domain integer reference for the three-timbre DDS voice."""
from gen_piano_golden import ROOT, read, pitch, MASK


def stimulus(n):
    if n>=20000:
        section=(n-20000)//64000
        return pitch((261.625565,329.627557,391.995436)[section]),3,int((n-20000)%64000==0),0,0,256,0,0
    inc = pitch(261.625565 if n < 4000 else 523.251131 if n < 8000 else
                659.255114 if n < 11000 else 783.990872 if n < 16000 else
                130.812783 if n < 17500 else 3000.0)
    rock = 0 if n < 1000 else min((n-1000)//4, 256) if n < 4000 else \
           max(256-(n-13000)//4, 0) if 13000 <= n < 15500 else 256
    bright = min(max((n-14000)//4, 0), 256) if 14000 <= n < 16000 else 0
    vel = 0 if n < 4000 else 1 if n < 8000 else 2 if n < 11000 else 3 if n < 16000 else 2
    on = n in (0, 4000, 8000, 11000, 12100, 16000)
    off = n in (7500, 10500, 12000, 12100, 18500)
    return inc, vel, int(on), int(off), bright, rock, int(7400 <= n < 9800), int(7800 <= n < 10800)


def main():
    lut=read('sine_lut.mem',True);ratios=read('piano_ratio.mem');env=read('piano_envelope.mem')
    seeds=read('piano_phase.mem');hammer=read('piano_hammer.mem',True)
    gains=read('piano_bright_gain.mem');decays=read('harmonic_decay_rock.mem')
    rock_gains=read('rock_gain.mem');rock_env=read('rock_envelope.mem');rock_seeds=read('rock_phase.mem');rock_ratios=read('rock_ratio.mem')
    phases=[0]*32;bright=[0]*32;age=0;active=False;releasing=False
    release=0;gain=0;profile=0;last=0;continuity=0;harmony=False
    age_phase=0;decay_phase=0;lines=[]
    for n in range(212000):
        inc,vel,on,off,blend,rock,sustain,harm=stimulus(n)
        frame_active=active or on;frame_age=age
        decay_step=decay_phase==0 if sustain else (decay_phase&3)==0
        if on:
            profile=0 if inc<26276679 else 1 if inc<32164062 else 2
            harmony=bool(harm);active=True;releasing=False;release=0xffffff
            gain=(112,160,208,256)[vel];age=0;frame_age=0;continuity=last
            age_phase=0;decay_phase=0;decay_step=True
            phases=[]
            for m in range(32):
                local=m-16 if harmony and m>=16 else m
                phases.append(rock_seeds[profile*32+local] if rock>=128 else seeds[profile*8+local] if local<8 else 0)
            bright=[gains[m-16 if harmony and m>=16 else m]<<8 for m in range(32)]
        else:
            old_phase=age_phase;age_phase=(age_phase+1)&3;decay_phase=(decay_phase+1)&15
            continuity=0 if -64<continuity<64 else continuity-(continuity>>6)
            if active:
                was_releasing=releasing
                if off:releasing=True
                if age>=131071 or (was_releasing and release<=256):active=False;release=0;continuity=0
                else:
                    if not sustain or age<2048 or old_phase==3:age+=1
                    if was_releasing and not sustain:release-=max(release>>10,1)
        total=bright_total=rock_total=body=0
        for mode in range(32):
            fifth=harmony and mode>=16;local=mode-16 if fifth else mode
            ratio=rock_ratios[local] if rock>=128 else ratios[profile*8+local] if local<8 else (local+1)<<20
            product=((inc*1571089)>>20 if fifth else inc)*ratio
            phases[mode]=(phases[mode]+(product>>20))&MASK
            address=(profile*8+(local%8))*256+(frame_age>>9)
            a=env[address];b=env[min(address+1,(profile*8+(local%8))*256+255)]
            observed=(a*(512-(frame_age&511))+b*(frame_age&511))>>9
            if local==0:body=observed
            enabled=frame_active and product<(1<<51)
            amp=observed if local<8 and enabled else 0
            bright_amp=(body*bright[mode])>>23 if enabled else 0
            wah_time=frame_age if frame_age<2048 else 2048+(frame_age-2048)//2
            word=rock_env[(profile*32+local)*32+min(wah_time//1024,31)]
            base=word>>13;delta=word&0x1fff
            if delta>=4096:delta-=8192
            level=0 if wah_time>=28800 else base+(delta*(wah_time%1024)//1024)
            level=level*min(frame_age,32)//32
            rock_amp=(level*rock_gains[profile*32+local])>>13 if enabled else 0
            if fifth:amp>>=1;bright_amp>>=1;rock_amp>>=1
            sine=lut[phases[mode]>>22]
            total+=(sine*amp)>>7;bright_total+=(sine*bright_amp)>>7;rock_total+=(sine*rock_amp)>>7
            if decay_step:bright[mode]=(bright[mode]*decays[local])>>15
        if frame_active and frame_age<2048:total+=hammer[profile*2048+frame_age]<<8
        total=(total*(256-blend)+bright_total*blend)>>8
        total=(total*(256-rock)+rock_total*rock)>>8
        if harmony:total=(total>>1)+(total>>2)
        output=(((total*gain)>>8)*(release>>8)>>16)+continuity
        last=min(max(output,-8388608),8388607)
        lines.append(f'{inc:08X} {vel} {on} {off} {blend} {rock} {sustain} {harm} {last&0xffffff:06X} {int(active)}\n')
    (ROOT/'sim/temp/rock_golden.txt').write_text(''.join(lines),encoding='ascii')
    print('Generated 212000 independent three-timbre samples, including all three complete extended dry-wah envelopes.')


if __name__=='__main__':main()
