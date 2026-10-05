"""Actual FPGA RTL dry-wah audio, pitch/HF evidence and decay comparison."""
from pathlib import Path
import hashlib
import json
import wave
import warnings
import numpy as np
from scipy.io import wavfile
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/wah_reference'
FS=48000
TARGETS=(261.625565,329.627557,391.995436)


def load(name,frames):
    vals=np.fromiter((int(s,16) for s in (ROOT/f'sim/temp/rock_{name}_pcm16.txt').read_text().split()),dtype=np.int32)
    if vals.size!=frames*2:raise ValueError('Incomplete RTL export: '+name)
    vals[vals>=32768]-=65536
    return vals.reshape(-1,2).astype(np.int16)


def save(name,pcm):
    path=OUT/name
    with wave.open(str(path),'wb') as wav:
        wav.setnchannels(2);wav.setsampwidth(2);wav.setframerate(FS)
        wav.writeframes(pcm.astype('<i2').tobytes())
    return hashlib.sha256(path.read_bytes()).hexdigest()


def power_metrics(x,fs,begin,end,target):
    x=x[round(begin*fs):round(end*fs)].astype(float)
    if x.ndim==1:x=x[:,None]
    ft=np.fft.rfft(x*np.hanning(len(x))[:,None],n=262144,axis=0)
    f=np.fft.rfftfreq(262144,1/fs);p=np.mean(abs(ft)**2,axis=1)
    note=np.flatnonzero(abs(f-target)<3)
    region=(f>100)&(f<16000);high=(f>3000)&(f<12000)
    half=np.zeros(len(f),bool)
    for ratio in np.arange(.5,32.01,.5):half|=abs(f-ratio*target)<max(10,ratio*target*.002)
    return dict(note_peak_hz=float(f[note[np.argmax(p[note])]]),
        high_band_power_fraction=float(p[high].sum()/p[region].sum()),
        half_grid_power_fraction=float(p[half&region].sum()/p[region].sum()))


def rms(pcm,begin,end):
    return float(np.sqrt(np.mean(pcm[round(begin*FS):round(end*FS)].astype(float)**2)))


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    source=json.loads((OUT/'analysis.json').read_text(encoding='utf-8'))
    clips={name:load(name,528000) for name in ('dry','room')}
    data=dict(version='dry_wah_v4_long_decay',sample_rate_hz=FS,frames=528000,velocity=2,
        events='C4 .15s, E4 1.65s, G4 3.15s, C4/E4/G4 4.85s and 6.65s, G3/C4/E4/G4 8.45s; no note-off',
        processing='Actual 256-clock RTL source, board panning, effects and PCM16; no normalization/software effects',variants={})
    fig,axes=plt.subplots(2,1,figsize=(11,7),layout='constrained')
    for name,pcm in clips.items():
        assert abs(pcm.astype(np.int32)).max()<32767
        notes=[power_metrics(pcm,FS,onset+.05,onset+.35,target) for onset,target in zip((.15,1.65,3.15),TARGETS)]
        for metrics,target in zip(notes,TARGETS):
            assert abs(metrics['note_peak_hz']-target)<.75
            assert metrics['high_band_power_fraction']>.005,('Missing measured HF band',name,metrics)
        data['variants'][name]=dict(peak_pcm16=int(abs(pcm.astype(np.int32)).max()),notes=notes,
            clipped_samples=0,sha256=save(f'rtl_wah_long_{name}.wav',pcm))
        blocks=np.sqrt(np.mean((pcm.astype(float)/32768).reshape(-1,480,2)**2,axis=(1,2)))
        axes[0].plot(np.arange(len(blocks))*.01,20*np.log10(np.maximum(blocks,1e-6)),label=name)
    pcm=clips['dry'][round(.20*FS):round(.50*FS)].astype(float)
    ft=np.fft.rfft(pcm*np.hanning(len(pcm))[:,None],n=262144,axis=0);p=np.mean(abs(ft)**2,axis=1)
    axes[1].plot(np.fft.rfftfreq(262144,1/FS),10*np.log10(np.maximum(p/p.max(),1e-9)),label='Actual RTL C4',lw=1)
    fs,ref=wavfile.read(source['metadata'][0]['path'])
    onset=source['metadata'][0]['onsets_s'][0]
    seg=ref[round((onset+.05)*fs):round((onset+.35)*fs)].astype(float)
    ft=np.fft.rfft(seg*np.hanning(len(seg))[:,None],n=262144,axis=0);p=np.mean(abs(ft)**2,axis=1)
    axes[1].plot(np.fft.rfftfreq(262144,1/fs),10*np.log10(np.maximum(p/p.max(),1e-9)),label='New C4 reference',lw=.8,alpha=.65)
    axes[0].set(title='Actual dry-wah output: singles, triads, four voices',xlabel='Time (s)',ylabel='10ms RMS (dBFS)',ylim=(-100,-5))
    axes[1].set(title='C4: integer and half-integer modes; high-frequency band retained',xlabel='Frequency (Hz)',ylabel='Relative power (dB)',xlim=(100,6500),ylim=(-70,3))
    for ax in axes:ax.legend();ax.grid(alpha=.2)
    fig.savefig(OUT/'rtl_wah_long_spectrum.png',dpi=160);plt.close(fig)
    c4={name:load('c4_'+name,240000) for name in ('dry','sustain')}
    assert np.array_equal(c4['dry'][:2048],c4['sustain'][:2048])
    assert not np.any(c4['dry'][55700:]) and not np.any(c4['sustain'][216500:])
    # A historical export is optional for fresh-clone reproducibility, but
    # when available it proves that the accepted V3 attack is bit-identical.
    previous={}
    for name in c4:
        path=OUT/'v3_before_long_decay'/f'rtl_wah_c4_{name}.wav'
        if path.exists():
            with wave.open(str(path),'rb') as wav:
                assert wav.getframerate()==FS and wav.getnchannels()==2
                previous[name]=np.frombuffer(wav.readframes(wav.getnframes()),dtype='<i2').reshape(-1,2)
            assert np.array_equal(previous[name][:2048],c4[name][:2048]),('V3 attack changed',name)
    data['v3_attack_identical_2048_samples']={name:True for name in previous}
    data['c4_decay']={}
    fig,ax=plt.subplots(figsize=(10,4),layout='constrained')
    for name,pcm in c4.items():
        nonzero=np.flatnonzero(np.any(pcm!=0,axis=1));early=rms(pcm,.05,.10);late=rms(pcm,1.,1.05)
        data['c4_decay'][name]=dict(early_rms_pcm16=early,late_rms_pcm16=late,
            late_window_s=[1.,1.05],late_vs_early_db=float(20*np.log10(max(late,1e-12)/early)),last_nonzero_s=float(nonzero[-1]/FS),
            sha256=save(f'rtl_wah_long_c4_{name}.wav',pcm))
        blocks=np.sqrt(np.mean((pcm.astype(float)/32768).reshape(-1,480,2)**2,axis=(1,2)))
        ax.plot(np.arange(len(blocks))*.01,20*np.log10(np.maximum(blocks,1e-6)),label=name)
    ax.set(title='Unreleased C4: dry vs sustain; measured wah envelopes',xlabel='Time (s)',ylabel='10ms RMS (dBFS)',ylim=(-100,-5));ax.grid(alpha=.2);ax.legend()
    if 'dry' in previous:
        pcm=previous['dry'];blocks=np.sqrt(np.mean((pcm.astype(float)/32768).reshape(-1,480,2)**2,axis=(1,2)))
        ax.plot(np.arange(len(blocks))*.01,20*np.log10(np.maximum(blocks,1e-6)),label='Previous V3 dry',ls='--',alpha=.7)
        ax.legend()
        save('rtl_wah_v3_v4_dry_comparison.wav',np.concatenate([pcm,np.zeros((12000,2),dtype=np.int16),c4['dry']]))
    fig.savefig(OUT/'rtl_wah_long_decay.png',dpi=160);plt.close(fig)
    save('rtl_wah_long_dry_sustain_comparison.wav',np.concatenate([c4['dry'],np.zeros((12000,2),dtype=np.int16),c4['sustain']]))
    reference_notes=[]
    for meta,target in zip(source['metadata'][:3],TARGETS):
        fs,pcm=wavfile.read(meta['path'])
        reference_notes.append([power_metrics(pcm,fs,onset+.05,onset+.35,target) for onset in meta['onsets_s']])
    data['new_reference_same_window']=reference_notes
    old_path=ROOT/'build/rock_reference/rtl_rock_c4_dry.wav'
    if old_path.exists():
        with wave.open(str(old_path),'rb') as wav:
            assert wav.getframerate()==FS
            old=np.frombuffer(wav.readframes(wav.getnframes()),dtype='<i2').reshape(-1,2)
        data['replaced_v2_c4_spectrum']=power_metrics(old,FS,.05,.35,TARGETS[0])
        data['new_c4_spectrum']=power_metrics(c4['dry'],FS,.05,.35,TARGETS[0])
    (OUT/'rtl_long_preview_metrics.json').write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(data,indent=2))


if __name__=='__main__':main()
