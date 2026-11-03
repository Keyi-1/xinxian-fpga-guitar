"""WAVs and numeric evidence from actual board-chain RTL PCM16 exports.

Run sim/run_main_regression.ps1 -Benches tb_piano_pcm_export first.
No per-file normalization, resampling, or added effects: output bytes are the
samples delivered to the RTL PT8211 transmitter. Comparison inserts silence.
"""
from pathlib import Path
import hashlib
import json
import wave
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build'/'piano'
FS=48000


def load(name):
    a=np.array([[int(v,16) for v in line.split()] for line in
                (ROOT/'sim'/'temp'/f'piano_{name}_pcm16.txt').read_text().splitlines()],dtype=np.int32)
    a[a>=32768]-=65536
    if a.shape!=(288000,2):raise ValueError(f'Bad PCM dimensions: {a.shape}')
    return a.astype(np.int16)


def save(path,pcm):
    with wave.open(str(path),'wb') as output:
        output.setnchannels(2);output.setsampwidth(2);output.setframerate(FS)
        output.writeframes(pcm.astype('<i2').tobytes())


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    samples={name:load(name) for name in ('body','hammer')}
    evidence={'sample_rate':FS,'samples_per_variant':288000,'channels':2,
              'notes':'C4/E4/G4 singles, twice C4-E4-G4 triad, then G3-C4-E4-G4',
              'gain':'raw RTL PCM16; no normalization or extra effects',
              'simulation_dividers':'64/1 to accelerate playback export; same 48k sample equations; shipped 256/4 tested separately',
              'variants':{}}
    for name,x in samples.items():
        save(OUT/f'rtl_piano_{name}.wav',x)
        xi=x.astype(np.int32)
        assert np.max(np.abs(xi))<32767
        metrics={'peak_pcm16':int(np.max(np.abs(xi))),
                 'rms_pcm16':float(np.sqrt(np.mean(xi.astype(float)**2))),
                 'clipped_samples':int(np.sum((xi==32767)|(xi==-32768))),
                 'sha256':hashlib.sha256((OUT/f'rtl_piano_{name}.wav').read_bytes()).hexdigest()}
        evidence['variants'][name]=metrics
    combined=np.concatenate([samples['body'],np.zeros((19200,2),dtype=np.int16),samples['hammer']])
    save(OUT/'rtl_piano_hammer_comparison.wav',combined)
    evidence['comparison_order']='body 6s, gap 0.4s, hammer 6s'
    evidence['comparison_sha256']=hashlib.sha256((OUT/'rtl_piano_hammer_comparison.wav').read_bytes()).hexdigest()
    delta=samples['hammer'].astype(np.int32)-samples['body'].astype(np.int32)
    evidence['first_note_hammer_delta_peak_pcm16']=int(abs(delta[:2048]).max())
    # Actual base pitches in the 150..500ms body window, first three singles.
    peaks=[]
    for start,target in ((0,261.625565),(.8,329.627557),(1.6,391.995436)):
        segment=samples['hammer'][round((start+.15)*FS):round((start+.5)*FS)].astype(float)
        spectrum=np.fft.rfft(segment*np.hanning(len(segment))[:,None],n=262144,axis=0)
        power=np.mean(abs(spectrum)**2,axis=1)
        frequencies=np.fft.rfftfreq(262144,1/FS)
        region=np.flatnonzero((frequencies>target-5)&(frequencies<target+5))
        index=region[np.argmax(power[region])]
        peaks.append(float(frequencies[index]))
    evidence['single_note_fundamental_peaks_hz']=peaks
    for actual,target in zip(peaks,(261.625565,329.627557,391.995436)):
        assert abs(actual-target)<.5
    fig,axes=plt.subplots(2,1,figsize=(10,6),layout='constrained')
    step=48
    for name,x in samples.items():
        s=x[:FS//5].astype(float)/32768
        frames=len(s)//step
        rms=np.sqrt(np.mean(s[:frames*step].reshape(frames,step,2)**2,axis=(1,2)))
        axes[0].plot(np.arange(frames)*step/FS*1000,20*np.log10(np.maximum(rms,1e-6)),label=name)
    axes[0].set(title='Actual RTL: C4 attack with / without hammer residual',xlabel='Time after pluck (ms)',ylabel='RMS (dBFS)',ylim=(-75,-10))
    for name,x in samples.items():
        segment=x[round(.005*FS):round(.04*FS)].astype(float)/32768
        ft=np.fft.rfft(segment*np.hanning(len(segment))[:,None],n=8192,axis=0)
        power=np.mean(abs(ft)**2,axis=1)
        axes[1].plot(np.fft.rfftfreq(8192,1/FS),10*np.log10(np.maximum(power,1e-12)),label=name)
    axes[1].set(title='Attack spectrum, 5..40 ms',xlabel='Frequency (Hz)',ylabel='FFT power (dB, common scale)',xlim=(0,8000))
    for ax in axes:ax.legend();ax.grid(alpha=.2)
    fig.savefig(OUT/'rtl_piano_attack.png',dpi=170);plt.close(fig)
    (OUT/'rtl_piano_preview.json').write_text(json.dumps(evidence,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(evidence,indent=2))


if __name__=='__main__':main()
