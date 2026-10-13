"""Listening files from actual full-chain RTL PCM16; no audio normalisation.

The old/new versions use identical commands, gain, modes and effects. Synthetic
hammer statistics separately quantify the short intended timbre difference.
"""
from pathlib import Path
import hashlib
import json
import wave
import numpy as np
from scipy import signal
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from procedural_hammer import HammerModel

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/procedural_piano'
FS=48000


def pcm(path):
    a=np.loadtxt(path,dtype=str)
    a=np.array([[int(v,16) for v in row] for row in a],dtype=np.int32)
    a[a>=32768]-=65536
    return a.astype(np.int16)


def save(name, a):
    with wave.open(str(OUT/name),'wb') as f:
        f.setnchannels(2);f.setsampwidth(2);f.setframerate(FS)
        f.writeframes(a.astype('<i2').tobytes())


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    old=pcm(ROOT/'sim/temp/procedural_ab_legacy_pcm16.txt')
    new=pcm(ROOT/'sim/temp/procedural_ab_new_pcm16.txt')
    assert old.shape==new.shape==(136000,2)
    assert abs(new.astype(np.int32)).max()<32767
    save('legacy_recorded_hammer.wav',old)
    save('procedural_hammer.wav',new)
    save('piano_ab_old_then_new.wav',np.concatenate([old,np.zeros((24000,2),np.int16),new]))
    # First 1.5 s: isolated notes at velocities 0 / 1 / 2, joint reset between.
    parts=[]
    for begin in (0,24000,48000,72000):
        parts.extend([old[begin:begin+24000],np.zeros((4800,2),np.int16),
                      new[begin:begin+24000],np.zeros((9600,2),np.int16)])
    save('piano_attack_ab_pairs.wav',np.concatenate(parts))
    legacy=np.array([int(v,16) for v in (ROOT/'sim/reference/piano_legacy/piano_hammer.mem').read_text().split()])
    legacy[legacy>=32768]-=65536;legacy=legacy.reshape(3,2048)
    models=[];statistics=[]
    seeds=[0x6d2b79f5,0x9e3779b9,0xa341316c,0xc8013ea4]
    fig,axes=plt.subplots(3,2,figsize=(12,9),layout='constrained')
    for b in range(3):
        variants=[]
        for seed in seeds:
            model=HammerModel(seed)
            variants.append(np.array([model.sample(n==0,True,n,b) for n in range(2048)]))
        models.append(variants[0])
        def measure(x):
            f,p=signal.welch(x.astype(float),FS,nperseg=512)
            return dict(rms_pcm16=float(np.sqrt(np.mean(x.astype(float)**2))),
                        peak_pcm16=int(abs(x).max()),
                        spectral_centroid_hz=float((f*p).sum()/p.sum()),
                        last_16_samples_peak=int(abs(x[-16:]).max()),
                        samples_at_bound=int((abs(x)==2048).sum()))
        stats=[measure(x) for x in variants]
        statistics.append(dict(profile=b,legacy=measure(legacy[b]),procedural_seeds=stats,
                               mean_rms_db_change=float(20*np.log10(np.sqrt(np.mean([s['rms_pcm16']**2 for s in stats]))/measure(legacy[b])['rms_pcm16']))))
        t=np.arange(2048)/FS*1000
        axes[b,0].plot(t,legacy[b],alpha=.65,label='old recorded residual')
        axes[b,0].plot(t,variants[0],alpha=.65,label='procedural noise + resonators')
        axes[b,0].set(xlabel='Time (ms)',ylabel='PCM16 units',title=f'Profile {b}: intended attack change')
        for x,label in [(legacy[b],'old'),(variants[0],'procedural')]:
            f,p=signal.welch(x.astype(float),FS,nperseg=512)
            axes[b,1].plot(f,10*np.log10(np.maximum(p,1e-9)),label=label)
        axes[b,1].set(xlim=(0,10000),xlabel='Frequency (Hz)',ylabel='PSD (dB / Hz)')
        axes[b,0].legend(fontsize=8);axes[b,1].legend(fontsize=8)
    fig.savefig(OUT/'hammer_comparison.png',dpi=150);plt.close(fig)
    save('hammer_only_ab_pairs.wav',np.concatenate([
        np.repeat(x[:,None],2,axis=1) for b in range(3)
        for x in (np.tile(legacy[b],8),np.zeros(4800,dtype=int),
                  np.tile(models[b],8),np.zeros(9600,dtype=int))]))
    evidence=dict(actual_rtl_frames_per_version=len(new),sample_rate_hz=FS,
        normalisation='none; identical gain and stereo board pipeline',
        segments=[dict(seconds=[0,.5],event='C-profile, velocity 0'),
                  dict(seconds=[.5,1.],event='E-profile single, velocity 1'),
                  dict(seconds=[1.,1.5],event='G-profile single, velocity 2'),
                  dict(seconds=[1.5,2.125],event='four-note chord; release frets; effects and rapid restrike'),
                  dict(seconds=[2.125,2.4167],event='bright-string crossfade and pluck'),
                  dict(seconds=[2.4167,2.8333],event='wah crossfade and pluck')],
        attack_statistics=statistics,
        listening_status='Listening artifacts generated; user listening/hardware acceptance pending',
        wav_sha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in OUT.glob('*.wav')},
        input_pcm_sha256={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in (ROOT/'sim/temp').glob('procedural_ab_*_pcm16.txt')})
    (OUT/'listening_evidence.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({'actual_rtl_frames_per_version':len(new),'statistics':statistics},indent=2))


if __name__=='__main__':main()
