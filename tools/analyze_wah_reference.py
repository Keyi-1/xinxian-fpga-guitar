"""Measure the new dry C4/E4/G4 references; never read the heavy-metal WAVs."""
from pathlib import Path
import hashlib
import json
import warnings
import numpy as np
from scipy import signal, optimize
from scipy.io import wavfile
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from analyze_rock_reference import detect_onsets

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/wah_reference'
LABELS=('C4','E4','G4','chord')
EXPECTED=np.array([261.625565,329.627557,391.995436])
PATHS=[Path('T:/Downloads/'+s+'哇音.wav') for s in ('C4','E4','G4','合音')]
NFFT=262144


def read(path):
    with warnings.catch_warnings():
        warnings.simplefilter('ignore')
        fs,pcm=wavfile.read(path)
    if pcm.ndim==1:pcm=pcm[:,None]
    if np.issubdtype(pcm.dtype,np.integer):x=pcm.astype(float)/2**(8*pcm.dtype.itemsize-1)
    else:x=pcm.astype(float)
    return fs,x,pcm.dtype.name


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    recordings=[];metadata=[];hits=[]
    fig,axes=plt.subplots(4,1,figsize=(11,8),layout='constrained')
    for index,(path,label,ax) in enumerate(zip(PATHS,LABELS,axes)):
        fs,x,dtype=read(path)
        if x.shape[1]!=2:raise ValueError('Expected stereo reference')
        onsets,t,rms=detect_onsets(x,fs)
        metadata.append(dict(label=label,path=str(path),sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
            fs=fs,channels=x.shape[1],dtype=dtype,frames=len(x),duration_s=len(x)/fs,
            peak=float(abs(x).max()),onsets_s=onsets,stereo_correlation=float(np.corrcoef(x.T)[0,1])))
        ax.plot(t,20*np.log10(np.maximum(rms,1e-8)))
        for onset in onsets:ax.axvline(onset,color='r',ls='--')
        ax.set(title=label,ylabel='RMS dBFS',ylim=(-100,0));ax.grid(alpha=.2)
        recordings.append((fs,x,onsets))
        if index==3:continue
        for hit,onset in enumerate(onsets):
            seg=x[round((onset+.05)*fs):round((onset+.65)*fs)]
            win=np.hanning(len(seg));ft=np.fft.rfft(seg*win[:,None],n=NFFT,axis=0)
            f=np.fft.rfftfreq(NFFT,1/fs);p=np.mean(abs(ft)**2,axis=1)/win.sum()**2
            band=np.flatnonzero(abs(f-EXPECTED[index])<6)
            f0=float(f[band[np.argmax(p[band])]])
            # Refine harmonic pitch jointly; high-order peaks expose small
            # tuning errors that would otherwise look like broad-band noise.
            def cost(freq):
                centers=freq*np.arange(1,33)
                return -float(np.sum(np.interp(centers,f,p)))
            fitted=optimize.minimize_scalar(cost,bounds=(f0-1,f0+1),method='bounded')
            f0=float(fitted.x)
            harmonic_mask=np.zeros(len(f),bool);levels=[]
            for order in range(1,33):
                mask=abs(f-order*f0)<max(10,order*f0*.002)
                harmonic_mask|=mask;levels.append(float(np.sqrt(p[mask].sum())))
            peaks,_=signal.find_peaks(p,distance=round(15/(fs/NFFT)))
            strongest=sorted(peaks,key=lambda k:p[k],reverse=True)[:24]
            harmonic_mask_all=np.zeros(len(f),bool)
            for order in range(1,int(20000/f0)+1):harmonic_mask_all|=abs(f-order*f0)<max(10,order*f0*.002)
            region=(f>100)&(f<16000)
            hf=(f>3000)&(f<12000)
            family_levels=[];family_peaks=[];family_mask=np.zeros(len(f),bool)
            for ratio in np.arange(.5,32.01,.5):
                mask=abs(f-ratio*f0)<max(10,ratio*f0*.002)
                family_mask|=mask
                family_levels.append(float(np.sqrt(p[mask].sum())))
                where=np.flatnonzero(mask);family_peaks.append(float(f[where[np.argmax(p[where])]]))
            h=dict(label=label,hit=hit,onset_s=onset,fundamental_hz=f0,
                centroid_hz=float(np.sum(f*p)/p.sum()),
                power_above_3khz=float(p[hf].sum()/p[region].sum()),
                integer_grid_residual_fraction=float(p[region&~harmonic_mask_all].sum()/p[region].sum()),
                half_grid_residual_fraction=float(p[region&~family_mask].sum()/p[region].sum()),
                first32_power_fraction=float(p[harmonic_mask&region].sum()/p[region].sum()),
                levels=levels,family_levels=family_levels,family_peaks_hz=family_peaks,
                top_peaks_hz=[float(f[k]) for k in strongest])
            hits.append(h)
    axes[-1].set_xlabel('Source time (s)');fig.savefig(OUT/'onsets.png',dpi=160);plt.close(fig)
    if len({m['sha256'] for m in metadata})!=4:raise ValueError('Duplicate reference files')
    # Select at most 32 measured modal frequencies, including the half-grid,
    # over all six hits. Normalizing hits prevents stronger manual velocities
    # from silently defining the timbre. Root first; other modes by importance
    # so the optional 16+16 fifth retains the most audible source features.
    strengths=np.array([h['family_levels'] for h in hits])
    strengths/=np.linalg.norm(strengths,axis=1)[:,None]
    importance=np.median(strengths,axis=0)
    chosen=[1]+[int(i) for i in np.argsort(importance)[::-1] if i!=1][:31]
    ratios=(np.array(chosen)+1)/2
    times=np.arange(0,1.28,.01)
    curves=[];phases=[]
    for h in hits:
        index=LABELS.index(h['label']);fs,x,onsets=recordings[index]
        onset=h['onset_s'];f0=h['fundamental_hz']
        # Complex demodulation separates each mode at 18 Hz bandwidth. No
        # stationary spectrum averaging: preserve the wah formant motion.
        seconds=np.arange(len(x))/fs;one=[]
        filt=signal.butter(3,18,fs=fs,output='sos')
        for order in ratios:
            iq=2*x*np.exp(-2j*np.pi*order*f0*seconds[:,None])
            iq=signal.sosfiltfilt(filt,iq,axis=0)
            positions=np.minimum(np.rint((onset+times)*fs).astype(int),len(x)-1)
            one.append(np.sqrt(np.mean(abs(iq[positions])**2,axis=1)))
        curves.append(np.array(one))
        seg=x[round((onset+.08)*fs):round((onset+.16)*fs)]
        ch=int(np.argmax(np.mean(seg**2,axis=0)));t=np.arange(len(seg))/fs
        basis=np.column_stack([fn(2*np.pi*n*f0*t) for n in ratios for fn in (np.sin,np.cos)])
        coeff=np.linalg.lstsq(basis,seg[:,ch],rcond=None)[0].reshape(32,2)
        phase=np.arctan2(coeff[:,1],coeff[:,0]);phase-=ratios*phase[0]
        phases.append(phase)
    np.savez(OUT/'modal_curves.npz',times=times,curves=np.array(curves),phases=np.array(phases),ratios=ratios)
    power_bins=np.arange(100,16001,25)
    band_columns=[];chord_info=[]
    for index,(fs,x,onsets) in enumerate(recordings):
        bands=[]
        for onset in onsets:
            seg=x[round((onset+.05)*fs):round((onset+.65)*fs)]
            w=np.hanning(len(seg));f=np.fft.rfftfreq(NFFT,1/fs)
            power=np.mean(abs(np.fft.rfft(seg*w[:,None],n=NFFT,axis=0))**2,axis=1)/w.sum()**2
            bands.append(np.histogram(f,bins=power_bins,weights=power)[0])
            if index==3:
                peaks,_=signal.find_peaks(power,distance=round(15/(fs/NFFT)))
                strongest=sorted(peaks,key=lambda k:power[k],reverse=True)[:20]
                region=(f>100)&(f<16000);high=(f>3000)&(f<12000)
                chord_info.append(dict(onset_s=onset,power_above_3khz=float(power[high].sum()/power[region].sum()),
                    strongest_peaks_hz=[float(f[k]) for k in strongest]))
        band_columns.append(np.mean(bands,axis=0))
    mix,residual=optimize.nnls(np.array(band_columns[:3]).T,band_columns[3])
    data=dict(metadata=metadata,hits=hits,settings='compression/treble/bass/echo 0; reverb OFF',
        chord_hits=chord_info,chord_power_mix_fit=dict(band_width_hz=25,nonnegative_power_gains=mix.tolist(),
            relative_l2_residual=float(residual/np.linalg.norm(band_columns[3]))),
        modal_ratios=ratios.tolist(),modal_importance=importance[chosen].tolist(),
        selected_grid_power_fractions=[float(np.sum(np.array(h['family_levels'])[chosen]**2)/np.sum(np.array(h['family_levels'])**2)) for h in hits],
        analysis_window_s=[.05,.65],fft_window_resolution_hz=1/.6,fft_grid_hz=recordings[0][0]/NFFT)
    (OUT/'analysis.json').write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    fig,axes=plt.subplots(2,2,figsize=(12,8),layout='constrained')
    for index,label in enumerate(LABELS[:3]):
        one=[h for h in hits if h['label']==label]
        lev=np.median([h['levels'] for h in one],axis=0)
        axes[0,0].plot(np.arange(1,33),20*np.log10(np.maximum(lev/lev.max(),1e-6)),'o-',ms=3,label=label)
        curve=np.mean(np.array(curves)[index*2:index*2+2],axis=0)
        hf=np.sqrt(np.sum(curve[ratios*EXPECTED[index]>3000]**2,axis=0))
        axes[0,1].plot(times,20*np.log10(np.maximum(hf/np.maximum(np.linalg.norm(curve,axis=0),1e-9),1e-6)),label=label)
        axes[1,0].plot(times,20*np.log10(np.maximum(np.linalg.norm(curve,axis=0)/np.linalg.norm(curve,axis=0).max(),1e-6)),label=label)
    normalized=np.array(curves)/np.maximum(np.linalg.norm(np.array(curves)[:,:,5:35],axis=1).mean(axis=1)[:,None,None],1e-9)
    axes[1,1].imshow(np.mean(normalized,axis=0),origin='lower',aspect='auto',extent=[0,times[-1],1,32])
    axes[0,0].set(title='Dry harmonic amplitudes',xlabel='Order',ylabel='dB relative strongest',ylim=(-70,3))
    axes[0,1].set(title='High-frequency power motion (>3 kHz)',xlabel='Time after onset (s)',ylabel='Relative amplitude dB')
    axes[1,0].set(title='Modal energy: held then manually released',xlabel='Time after onset (s)',ylabel='Relative amplitude dB')
    axes[1,1].set(title='Measured moving modal profile (energy-ranked slots)',xlabel='Time after onset (s)',ylabel='Modal slot')
    for ax in axes.flat[:3]:ax.legend();ax.grid(alpha=.2)
    fig.savefig(OUT/'spectrum_motion.png',dpi=160);plt.close(fig)
    print(json.dumps(dict(metadata=metadata,modal_ratios=ratios.tolist(),selected_grid_power_fractions=data['selected_grid_power_fractions'],
        hits=[{k:v for k,v in h.items() if k not in ('levels','family_levels','family_peaks_hz','top_peaks_hz')} for h in hits]),ensure_ascii=False,indent=2))


if __name__=='__main__':main()
