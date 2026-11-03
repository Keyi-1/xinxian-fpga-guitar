"""Analyze the supplied GarageBand heavy-metal recordings, without editing them.

Stereo power is retained when estimating harmonics; source reverb and manual
velocity/key duration are observations, not identified dry synthesis parameters.
"""
from pathlib import Path
import argparse
import hashlib
import json
import warnings

import numpy as np
from scipy import signal, optimize
from scipy.io import wavfile
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parents[1]
LABELS = ('C5', 'E5', 'G5', 'chord')
EXPECTED = (523.251131, 659.255114, 783.990872)
NFFT = 262144


def read(path):
    with warnings.catch_warnings():
        warnings.filterwarnings('ignore', category=wavfile.WavFileWarning)
        fs, pcm = wavfile.read(path)
    if pcm.dtype != np.int16 or pcm.ndim != 2 or pcm.shape[1] != 2:
        raise ValueError(f'Expected stereo PCM16: {path}: {pcm.dtype}/{pcm.shape}')
    return fs, pcm.astype(float) / 32768


def detect_onsets(x, fs):
    hop = round(fs * .005)
    blocks = len(x) // hop
    rms = np.sqrt(np.mean(x[:blocks*hop].reshape(blocks, hop, 2)**2, axis=(1, 2)))
    floor = max(rms.max() * 1e-4, 1e-6)
    log_energy = 20*np.log10(np.maximum(rms, floor))
    rise = log_energy - np.r_[np.full(8, log_energy[0]), log_energy[:-8]]
    rise[rms < .06*rms.max()] = 0
    peaks, _ = signal.find_peaks(rise, prominence=6, distance=round(.8*fs/hop))
    first = int(np.flatnonzero(rms > .05*rms.max())[0])
    candidates = [first] + [int(p) for p in peaks if abs(p-first)*hop/fs > .15]
    if len(candidates) < 2:
        raise ValueError(f'Need two attacks; candidates={candidates}')
    chosen = sorted(sorted(candidates, key=lambda p: (100 if p == first else rise[p]), reverse=True)[:2])
    # Refine each rough energy-rise peak back to the local attack threshold.
    onsets = []
    for p in chosen:
        begin = max(0, p-round(.06*fs/hop))
        end = min(blocks, p+4)
        background = np.median(rms[max(0, begin-8):max(1, begin)])
        threshold = max(background*3, rms[begin:end].max()*.08, floor)
        crossings = np.flatnonzero(rms[begin:end] > threshold)
        start = begin+int(crossings[0]) if len(crossings) else p
        onsets.append(start*hop/fs)
    return onsets, np.arange(blocks)*hop/fs, rms


def spectrum(x, fs, onset, start=.08, end=.55):
    seg = x[round((onset+start)*fs):round((onset+end)*fs)]
    w = signal.windows.hann(len(seg), sym=False)
    ft = np.fft.rfft(seg*w[:, None], n=NFFT, axis=0)
    p = np.mean(abs(ft)**2, axis=1)/w.sum()**2
    return np.fft.rfftfreq(NFFT, 1/fs), p


def peak(f, p, center, tolerance=.018):
    region = np.flatnonzero(abs(f-center) < center*tolerance)
    k = region[np.argmax(p[region])]
    return float(f[k]), float(p[k])


def harmonic_envelopes(x, fs, f0):
    curves = []
    for order in range(1, 33):
        center = order*f0
        if center > fs/2-100:
            curves.append(np.zeros(len(x)))
            continue
        t = np.arange(len(x))/fs
        iq = 2*x*np.exp(-2j*np.pi*center*t[:, None])
        filt = signal.butter(3, 30, fs=fs, output='sos')
        iq = signal.sosfiltfilt(filt, iq, axis=0)
        curves.append(np.sqrt(np.mean(abs(iq)**2, axis=1)))
    return np.array(curves)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--files', nargs=4, type=Path, default=[
        Path(f'T:/Downloads/{name}重金属.wav/{name}重金属.wav')
        for name in ('C5', 'E5', 'G5', '合音')])
    ap.add_argument('--output', type=Path, default=ROOT/'build'/'rock_reference')
    args = ap.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    recordings = []
    metadata = []
    fig, axes = plt.subplots(4, 1, figsize=(11, 8), layout='constrained')
    for ax, label, path in zip(axes, LABELS, args.files):
        fs, x = read(path)
        onsets, t, rms = detect_onsets(x, fs)
        f, p = spectrum(x, fs, onsets[0])
        peaks, _ = signal.find_peaks(p, distance=round(15/(fs/NFFT)))
        strongest = sorted(peaks, key=lambda k: p[k], reverse=True)[:16]
        m = {'label': label, 'path': str(path), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
             'sample_rate': fs, 'channels': 2, 'bits': 16, 'frames': len(x),
             'duration_s': len(x)/fs, 'peak': float(abs(x).max()),
             'onsets_s': onsets, 'stereo_correlation': float(np.corrcoef(x.T)[0, 1]),
             'strongest_peaks_hz': [float(f[k]) for k in strongest]}
        metadata.append(m)
        recordings.append((fs, x, onsets))
        ax.plot(t, 20*np.log10(np.maximum(rms, 1e-6)), lw=1)
        for onset in onsets:
            ax.axvline(onset, color='#bd532c', ls='--', lw=1)
        ax.set(title=label, ylabel='5 ms RMS (dBFS)', ylim=(-100, 0))
        ax.grid(alpha=.2)
    axes[-1].set_xlabel('Source time (s)')
    fig.savefig(args.output/'onsets.png', dpi=160)
    plt.close(fig)
    (args.output/'inspection.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    duplicate_g = metadata[1]['sha256'] == metadata[2]['sha256']
    measured = []
    amplitudes = []
    time = np.arange(0, 1.8, .005)
    curves = []
    for index in (0, 1) if duplicate_g else (0, 1, 2):
        fs, x, onsets = recordings[index]
        fundamental = []
        hits = []
        for onset in onsets:
            f, p = spectrum(x, fs, onset)
            f0, _ = peak(f, p, EXPECTED[index])
            fundamental.append(f0)
            levels = []
            for n in range(1, 33):
                band = abs(f-n*f0) < max(25, n*f0*.008)
                levels.append(np.sqrt(p[band].sum()))
            levels = np.array(levels)
            levels /= max(np.linalg.norm(levels), 1e-12)
            amplitudes.append(levels)
            hits.append({'onset_s': onset, 'fundamental_hz': f0,
                         'harmonic_amplitudes_unit_energy': levels.tolist(),
                         'harmonic_db_relative_root': (20*np.log10(np.maximum(levels/levels[0], 1e-8))).tolist(),
                         'centroid_hz': float(np.sum(f*p)/np.sum(p))})
        envelope = harmonic_envelopes(x, fs, np.mean(fundamental))
        hit_curves = []
        for onset in onsets:
            positions = np.minimum(np.rint((onset+time)*fs).astype(int), len(x)-1)
            hit_curves.append(envelope[:, positions])
        curves.append(np.mean(hit_curves, axis=0))
        measured.append({'label': LABELS[index], 'hits': hits})
    weights = np.median(amplitudes, axis=0)
    # Weak/high-order source floors are not tonal harmonics. Retain credible
    # harmonics; the hardware additionally mutes anything at/above Nyquist.
    weights[weights < weights.max()*.003] = 0
    weights /= weights.sum()
    chord_hits = []
    for onset in recordings[3][2]:
        f, p = spectrum(recordings[3][1], recordings[3][0], onset)
        chord_hits.append([{'label': label, 'frequency_hz': peak(f, p, center)[0]}
                           for label, center in zip(LABELS[:3], EXPECTED)])
    # Compare stereo POWER, with broad bins to tolerate the source's vibrato
    # and manual dynamics. Free gains do not identify a specific nonlinear FX.
    bins=np.arange(100, 12001, 25)
    solo_bands=[]
    for index in (0, 1) if duplicate_g else (0, 1, 2):
        fs,x,ons=recordings[index]
        powers=[]
        for onset in ons:
            f,p=spectrum(x,fs,onset)
            powers.append(np.histogram(f,bins=bins,weights=p)[0])
        solo_bands.append(np.mean(powers,axis=0))
    chord_bands=[]
    for onset in recordings[3][2]:
        f,p=spectrum(recordings[3][1],recordings[3][0],onset)
        chord_bands.append(np.histogram(f,bins=bins,weights=p)[0])
    matrix=np.array(solo_bands).T
    chord_power=np.mean(chord_bands,axis=0)
    mix_gains,residual=optimize.nnls(matrix,chord_power)
    groups = ((0,), (1, 2, 3), tuple(range(4, 32)))
    fits = []
    for group in groups:
        group_curve = np.mean([np.sqrt(np.sum(v[list(group)]**2, axis=0)) for v in curves], axis=0)
        selected = (time >= .12) & (time <= .70)
        slope = np.polyfit(time[selected], np.log(np.maximum(group_curve[selected], 1e-9)), 1)[0]
        observed_tau = float(-1/slope) if slope < -.05 else None
        # Reference keys are held, then manually released. The natural pluck
        # decay is a design adaptation, bounded to a playable finite duration.
        fallback = (1.8, 1.4, .9)[len(fits)]
        chosen = float(np.clip(observed_tau or fallback, .65, fallback))
        fits.append({'orders': [n+1 for n in group], 'observed_held_tau_s': observed_tau,
                     'chosen_pluck_tau_s': chosen})
    findings = {'metadata': metadata, 'g5_is_duplicate_e5': duplicate_g,
                'effective_solo_labels': [v['label'] for v in measured], 'notes': measured,
                'chord_fundamentals': chord_hits, 'harmonic_weights': weights.tolist(),
                'chord_power_mix_fit': {'band_width_hz':25,'nonnegative_power_gains':mix_gains.tolist(),
                                       'relative_l2_residual':float(residual/np.linalg.norm(chord_power))},
                'envelope_groups': fits,
                'source_settings': 'GarageBand heavy-metal; manual velocity; compression/treble/bass/echo 0; reverb enabled',
                'limitations': ['Wet recordings cannot identify the dry amp/preset or reverb independently.',
                               'Manual release produces a large envelope fall; it is not natural string decay.',
                               'Only three notes and uncontrolled manual dynamics; not a complete register/velocity calibration.',
                               'Initial harmonic-profile transfer to other registers; no octave or frequency-table change.']}
    (args.output/'analysis.json').write_text(json.dumps(findings, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    np.savetxt(args.output/'harmonic_envelopes.csv', np.column_stack([time, np.concatenate(curves).T]),
               delimiter=',', header='time_s,'+','.join(f'{v["label"]}_h{n+1}' for v in measured for n in range(32)), comments='')
    fig, axes = plt.subplots(2, 2, figsize=(12, 7), layout='constrained')
    for v, curve in zip(measured, curves):
        levels = np.median([h['harmonic_db_relative_root'] for h in v['hits']], axis=0)
        axes[0, 0].plot(np.arange(1, 33), levels, 'o-', ms=3, label=v['label'])
        axes[0, 1].plot(time, 20*np.log10(np.maximum(curve[0]/curve[0].max(), 1e-6)), label=v['label'])
    axes[0, 0].set(title='Measured harmonic levels', xlabel='Harmonic order', ylabel='Relative to fundamental (dB)', ylim=(-65, 12))
    axes[0, 1].set(title='Wet fundamental envelopes: held, then released', xlabel='Time after attack (s)', ylabel='Relative amplitude (dB)', ylim=(-70, 5))
    for index in (0, 3):
        fs, x, ons = recordings[index]
        f, p = spectrum(x, fs, ons[0])
        axes[1, 0].plot(f, 10*np.log10(np.maximum(p/p.max(), 1e-9)), label=LABELS[index], lw=1)
    axes[1, 0].set(title='Stereo power spectra', xlabel='Frequency (Hz)', ylabel='Relative power (dB)', xlim=(300, 6500), ylim=(-65, 3))
    axes[1, 1].stem(np.arange(1, 33), weights)
    axes[1, 1].set(title='Initial shared rock synthesis weights', xlabel='Harmonic order', ylabel='Normalized amplitude')
    for ax in axes.flat:
        ax.grid(alpha=.2)
    for ax in axes.flat[:3]:
        ax.legend()
    fig.savefig(args.output/'spectra_and_envelopes.png', dpi=160)
    plt.close(fig)
    print(json.dumps({'metadata': metadata, 'g5_is_duplicate_e5': duplicate_g,
                      'chord_fundamentals': chord_hits, 'envelope_groups': fits,
                      'first_12_weights': weights[:12].tolist()}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
