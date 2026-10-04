"""Analyze the four supplied GarageBand exports without modifying the originals.

Requires NumPy, SciPy and Matplotlib. Outputs are local analysis artifacts,
not recordings of the FPGA or a bitstream. Defaults match the supplied paths.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import warnings

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scipy import optimize, signal
from scipy.io import wavfile

ROOT = Path(__file__).resolve().parents[1]
NFFT = 262144
LABELS = ("C4", "E4", "G4", "chord")
# These are approximate search centers, NOT asserted sample-accurate onsets.
ONSET_HINTS = ((0.0, 2.53), (0.18, 2.71), (0.29, 3.90), (0.45, 4.43))
EXPECTED_LOW = (261.625565, 329.627557, 391.995436)


def db(value):
    return 20 * np.log10(np.maximum(np.asarray(value), 1e-12))


def read_audio(path):
    with warnings.catch_warnings():
        # GarageBand adds metadata chunks that SciPy does not decode.
        warnings.filterwarnings("ignore", category=wavfile.WavFileWarning,
                                message="Chunk.*not understood.*")
        fs, pcm = wavfile.read(path)
    if pcm.dtype != np.int16 or pcm.ndim != 2 or pcm.shape[1] != 2:
        raise ValueError(f"Expected stereo PCM16: {path}, {pcm.dtype}, {pcm.shape}")
    return fs, pcm.astype(np.float64) / 32768


def refine_onset(x, fs, hint):
    if hint == 0:
        return 0.0  # The first C attack is at the file boundary.
    a = max(0, int((hint - 0.06) * fs))
    b = min(len(x), int((hint + 0.09) * fs))
    # First 1-ms energy block above both background and 3% of local peak.
    hop = round(fs * 0.001)
    blocks = x[a:b][:((b - a) // hop) * hop].reshape(-1, hop, 2)
    rms = np.sqrt(np.mean(blocks * blocks, axis=(1, 2)))
    background = np.median(rms[:max(3, int(0.02 * fs / hop))])
    threshold = max(0.03 * rms.max(), 8 * background, 1e-4)
    crossing = np.flatnonzero(rms > threshold)
    return (a + int(crossing[0]) * hop) / fs if len(crossing) else hint


def spectrum(x, fs, onset, start=0.08, end=0.70):
    segment = x[round((onset + start) * fs):round((onset + end) * fs)]
    window = signal.windows.hann(len(segment), sym=False)
    ft = np.fft.rfft(segment * window[:, None], n=NFFT, axis=0)
    # Averaging POWER avoids stereo phase cancellation from a mono downmix.
    power = np.mean(np.abs(ft) ** 2, axis=1) / window.sum() ** 2
    return np.fft.rfftfreq(NFFT, 1 / fs), power


def spectral_peak(f, p, lo, hi):
    candidates = np.flatnonzero((f >= lo) & (f <= hi))
    k = candidates[np.argmax(p[candidates])]
    offset = 0.0
    if 0 < k < len(p) - 1:
        v = np.log(np.maximum(p[k-1:k+2], 1e-30))
        denom = v[0] - 2 * v[1] + v[2]
        if abs(denom) > 1e-12:
            offset = np.clip(0.5 * (v[0] - v[2]) / denom, -0.5, 0.5)
    return float(f[k] + offset * (f[1] - f[0])), float(p[k])


def modal_envelope(x, fs, frequency):
    # Stereo energy envelope of a +/-24-Hz band around one detected partial.
    t = np.arange(len(x)) / fs
    iq = 2 * x * np.exp(-2j * np.pi * frequency * t[:, None])
    sos = signal.butter(4, 24, fs=fs, output="sos")
    iq = signal.sosfiltfilt(sos, iq, axis=0)
    return np.sqrt(np.mean(np.abs(iq) ** 2, axis=1))


def fit_decay(t, amplitude):
    # Observed wet envelope only. Key release/reverb cannot be disentangled.
    select = (t >= 0.04) & (t <= 0.70)
    tx = t[select]
    ay = amplitude[select]
    scale = max(ay.max(), 1e-9)
    ay = ay / scale
    def model(v):
        return v[0] * np.exp(-tx / v[1]) + v[2] * np.exp(-tx / v[3])
    result = optimize.least_squares(
        lambda v: (model(v) - ay) / np.sqrt(np.maximum(ay, 0.05)),
        [1.0, 0.15, 0.12, 0.8],
        bounds=([0, 0.015, 0, 0.25], [3, 0.5, 3, 3.0]), max_nfev=1000)
    a, fast, b, slow = result.x
    return {"fast_amplitude": float(a * scale), "fast_tau_s": float(fast),
            "slow_amplitude": float(b * scale), "slow_tau_s": float(slow),
            "relative_rmse": float(np.sqrt(np.mean((model(result.x)-ay)**2)))}


def summarize_note(x, fs, onsets, label, low):
    hits = []
    envelope_curves = []
    times = np.arange(0, 1.8, 0.005)
    for onset in onsets:
        f, power = spectrum(x, fs, onset)
        f1, p1 = spectral_peak(f, power, 1.8 * low, 2.2 * low)
        partials = []
        envelopes = []
        for n in range(1, 9):
            fn, pn = spectral_peak(f, power, n*f1*0.992, n*f1*1.08)
            near = (f > fn + 8) & (f < fn + 25)
            floor = float(np.median(power[near]))
            relative = 10*np.log10(max(pn/p1, 1e-15))
            snr = 10*np.log10(max(pn/max(floor, 1e-30), 1e-15))
            env = modal_envelope(x, fs, fn)
            positions = np.clip(np.rint((onset + times) * fs).astype(int), 0, len(x)-1)
            curves = env[positions]
            decay = fit_decay(times, curves)
            partials.append({"order": n, "frequency_hz": fn,
                             "relative_db": float(relative), "local_snr_db": float(snr),
                             "observed_decay_fit": decay})
            envelopes.append(curves)
        # Restrict the frequency-stretch fit to reliable first six partials.
        reliable = [v for v in partials[:6] if v["relative_db"] > -38 and v["local_snr_db"] > 12]
        orders = np.array([v["order"] for v in reliable])
        measured = np.array([v["frequency_hz"] for v in reliable])
        stretch = optimize.least_squares(
            lambda v: orders*v[0]*np.sqrt((1+v[1]*orders**2)/(1+v[1]))-measured,
            [f1, 0.001], bounds=([f1*0.99, 0], [f1*1.01, 0.02]))
        fitted = orders*stretch.x[0]*np.sqrt((1+stretch.x[1]*orders**2)/(1+stretch.x[1]))
        ranges = ((0.03,0.08), (0.08,0.20), (0.20,0.50), (0.50,1.0), (1.0,1.5))
        rms = []
        for a,b in ranges:
            y = x[round((onset+a)*fs):round((onset+b)*fs)]
            rms.append(float(db(np.sqrt(np.mean(y*y)))))
        low_freq, low_power = spectral_peak(f, power, low*0.985, low*1.015)
        hits.append({"onset_s": onset, "dominant_fundamental_hz": f1,
                     "half_frequency_hz": low_freq,
                     "half_frequency_relative_db": float(10*np.log10(low_power/p1)),
                     "partials": partials, "stretch_B": float(stretch.x[1]),
                     "stretch_fit_rmse_hz": float(np.sqrt(np.mean((fitted-measured)**2))),
                     "stretch_fit_partial_count": len(reliable), "rms_windows_dbfs": rms})
        envelope_curves.append(envelopes)
    return {"label": label, "hits": hits}, times, np.mean(envelope_curves, axis=0)


def crop(x, fs, onset, seconds):
    out = np.zeros((round(seconds*fs), 2))
    a = round(onset*fs)
    available = x[a:a+len(out)]
    out[:len(available)] = available
    return out


def write_wav(path, x, fs):
    if not np.isfinite(x).all() or np.max(np.abs(x)) >= 1:
        raise ValueError(f"Invalid/unclipped headroom required: {path}")
    wavfile.write(path, fs, np.rint(x*32767).astype(np.int16))


def match_body_rms(x, fs, target=0.10):
    y = x[round(fs*.04):round(fs*.45)]
    return x * target / max(np.sqrt(np.mean(y*y)), 1e-9)


def shared_reverb(x, fs):
    # A deliberately small, fixed synthetic room, not a fitted GarageBand IR.
    wet = np.zeros_like(x)
    for channel in range(2):
        source = x.mean(axis=1)
        for milliseconds in ((31, 43, 59, 73) if channel == 0 else (37, 47, 61, 79)):
            delay = round(milliseconds * fs / 1000)
            tail = np.zeros(len(source))
            for echo in range(1, 24):
                shift = delay*echo
                if shift >= len(source):
                    break
                tail[shift:] += (0.74**(echo-1)) * source[:-shift]
            wet[:, channel] += signal.sosfilt(signal.butter(1, 4200, fs=fs, output="sos"), tail) / 4
    return x * .84 + wet * .16


def additive_preview(notes, curves, times, fs, mode="measured"):
    length = 2.0
    t = np.arange(round(length*fs))/fs
    rng = np.random.default_rng(23)
    voices = []
    for i, note in enumerate(notes):
        out = np.zeros((len(t), 2))
        hit = note["hits"][0]
        left, right = ((.78,.62),(.707,.707),(.62,.78))[i]
        for n, partial in enumerate(hit["partials"]):
            if n > 0 and mode == "sine":
                break
            if partial["relative_db"] < -45 or partial["local_snr_db"] < 12:
                continue
            # Smooth measured stereo-energy modal envelope, not PCM sampling.
            env = np.interp(t, times, curves[i][n], left=0, right=curves[i][n][-1])
            env *= np.clip(t/.003, 0, 1)
            frequency = partial["frequency_hz"] if mode == "measured" else (n+1)*hit["dominant_fundamental_hz"]
            phase = rng.uniform(-np.pi, np.pi) if n else 0
            mono = env * np.sin(2*np.pi*frequency*t+phase)
            out[:, 0] += left*mono
            out[:, 1] += right*mono
        # Fix the end smoothly; no click from truncating the captured tail.
        out[-round(.08*fs):] *= np.linspace(1,0,round(.08*fs))[:,None]
        voices.append(out)
    return voices


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--files", nargs=4, type=Path, default=[
        Path("T:/Downloads/C4.wav/C4.wav"), Path("T:/Downloads/E4.wav/E4.wav"),
        Path("T:/Downloads/G4.wav/G4.wav"), Path("T:/Downloads/合音.wav/合音.wav")])
    parser.add_argument("--output", type=Path, default=ROOT/"build"/"garageband_analysis")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    audio = []
    onsets = []
    metadata = []
    rates = []
    for label, path, hints in zip(LABELS, args.files, ONSET_HINTS):
        fs,x = read_audio(path)
        rates.append(fs)
        audio.append(x)
        onset = [refine_onset(x,fs,h) for h in hints]
        onsets.append(onset)
        mid = x.mean(axis=1)
        side = (x[:,0]-x[:,1])/2
        metadata.append({"label":label, "path":str(path), "sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
                         "sample_rate":fs, "channels":2, "sample_bits":16,
                         "frames":len(x), "duration_s":len(x)/fs,
                         "peak":float(np.max(np.abs(x))), "rms_dbfs":float(db(np.sqrt(np.mean(x*x)))),
                         "lr_correlation":float(np.corrcoef(x.T)[0,1]),
                         "side_mid_energy_db":float(10*np.log10(np.sum(side*side)/np.sum(mid*mid))),
                         "onsets_s":onset})
    if len(set(rates)) != 1:
        raise ValueError("All reference files must have the same sample rate")
    fs = rates[0]
    notes = []
    all_curves = []
    for label,x,ons,low in zip(LABELS[:3],audio[:3],onsets[:3],EXPECTED_LOW):
        note,times,curves = summarize_note(x,fs,ons,label,low)
        notes.append(note)
        all_curves.append(curves)
    # Inspectable parameter exports for a future scheduled FPGA oscillator.
    # The frequency ratio multiplies the increment of an INDEPENDENT phase
    # accumulator, never the wrapped phase of the fundamental oscillator.
    modal_rows = ["file,partial,frequency_hz,ratio_q20,relative_db,local_snr_db,eligible_for_preview,stretch_B"]
    for note in notes:
        for n in range(8):
            freq = np.mean([hit["partials"][n]["frequency_hz"] for hit in note["hits"]])
            f1 = np.mean([hit["dominant_fundamental_hz"] for hit in note["hits"]])
            relative = np.mean([hit["partials"][n]["relative_db"] for hit in note["hits"]])
            snr = np.mean([hit["partials"][n]["local_snr_db"] for hit in note["hits"]])
            eligible = relative >= -45 and snr >= 12
            stretch = np.mean([hit["stretch_B"] for hit in note["hits"]])
            modal_rows.append(f"{note['label']},{n+1},{freq:.6f},{round(freq/f1*2**20)},{relative:.4f},{snr:.4f},{int(eligible)},{stretch:.8f}")
    (args.output/"piano_reference_modes.csv").write_text("\n".join(modal_rows)+"\n",encoding="utf-8")
    columns = [f"{label}_partial_{n+1}" for label in LABELS[:3] for n in range(8)]
    np.savetxt(args.output/"observed_wet_modal_envelopes.csv",
               np.column_stack([times,np.concatenate(all_curves,axis=0).T]),
               delimiter=",",header="time_s,"+",".join(columns),comments="",fmt="%.8f")

    # Nonnegative POWER-spectrum combination: free gains account for export
    # normalization/velocity. This is not waveform cancellation or proof of FX.
    f, chord_power = spectrum(audio[3],fs,onsets[3][0])
    solo_powers = np.stack([spectrum(x,fs,ons[0])[1] for x,ons in zip(audio[:3],onsets[:3])],axis=1)
    bands = (f > 350) & (f < 5000)
    weights, residual = optimize.nnls(solo_powers[bands], chord_power[bands])
    combined_power = solo_powers @ weights
    spectral_error = float(residual/np.linalg.norm(chord_power[bands]))
    chord_peaks = []
    for onset in onsets[3]:
        cf,cp = spectrum(audio[3],fs,onset)
        row = []
        for note in notes:
            center = note["hits"][0]["dominant_fundamental_hz"]
            freq,power = spectral_peak(cf,cp,center-5,center+5)
            row.append({"frequency_hz":freq,"power":power})
        reference_power = row[0]["power"]
        for v in row:
            v["relative_db"] = float(10*np.log10(v["power"]/reference_power))
            del v["power"]
        chord_peaks.append(row)

    findings = {"metadata":metadata, "analysis_window_s":[.08,.70],
                "window_resolution_hz":1/.62, "zero_padded_grid_hz":fs/NFFT,
                "modal_band_half_width_hz":24, "notes":notes,
                "chord_fundamentals":chord_peaks,
                "power_mix_nonnegative_weights":weights.tolist(),
                "power_mix_relative_l2_error":spectral_error,
                "cautions":["Wet piano reference; key durations and exact velocities unknown.",
                            "Identical peaks suggest per-file normalization, but do not prove it.",
                            "First C attack is left-censored by the recording boundary.",
                            "Partial envelope estimates include room tails and nearby modes.",
                            "Three notes in one register cannot calibrate the complete instrument.",
                            "Offline previews are not FPGA output or a perceptual validation score."]}
    (args.output/"analysis.json").write_text(json.dumps(findings,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

    plt.rcParams.update({"axes.spines.top":False,"axes.spines.right":False,"font.size":10})
    fig,axes = plt.subplots(4,1,figsize=(11,8),layout="constrained")
    for ax,x,meta in zip(axes,audio,metadata):
        hop=round(fs*.01)
        frames=len(x)//hop
        rms=np.sqrt(np.mean(x[:frames*hop].reshape(frames,hop,2)**2,axis=(1,2)))
        ax.plot(np.arange(frames)*hop/fs,db(rms),color="#326d9d")
        for onset in meta["onsets_s"]:
            ax.axvline(onset,color="#dc684d",ls="--",lw=1)
        ax.set(title=f"{meta['label']} | two attacks | L/R corr {meta['lr_correlation']:.2f}",
               ylabel="RMS (dBFS)",ylim=(-85,0))
        ax.grid(alpha=.18)
    axes[-1].set_xlabel("Time in source file (s)")
    fig.savefig(args.output/"recordings_and_onsets.png",dpi=170)
    plt.close(fig)

    fig,axes=plt.subplots(2,2,figsize=(12,8),layout="constrained")
    colors=("#3274ab","#d88827","#669745")
    for note,x,ons,color in zip(notes,audio,onsets,colors):
        nf,p=spectrum(x,fs,ons[0])
        axes[0,0].plot(nf,10*np.log10(np.maximum(p/p.max(),1e-12)),color=color,label=note["label"],lw=1)
    axes[0,0].set(xlim=(400,4500),ylim=(-65,3),title="Single-note spectra (power average of L/R)",xlabel="Frequency (Hz)",ylabel="Relative level (dB)")
    for i,note in enumerate(notes):
        levels=np.mean([[p["relative_db"] for p in h["partials"]] for h in note["hits"]],axis=0)
        axes[0,1].plot(np.arange(1,9),levels,"o-",color=colors[i],label=note["label"])
        base=all_curves[i][0]
        axes[1,0].plot(times,db(base/base.max()),color=colors[i],label=f"{note['label']} partial 1")
        axes[1,0].plot(times,db(all_curves[i][1]/all_curves[i][1].max()),color=colors[i],ls="--",alpha=.7,label=f"{note['label']} partial 2")
    axes[0,1].plot(np.arange(1,9),-6.0206*np.arange(8),":",color="gray",label="Existing classic table")
    axes[0,1].set(ylim=(-60,3),title="Measured partial levels vs current table",xlabel="Partial order",ylabel="Relative level (dB)")
    axes[1,0].set(xlim=(0,1.2),ylim=(-55,3),title="Observed wet partial envelopes",xlabel="Time after attack (s)",ylabel="Normalized amplitude (dB)")
    norm=chord_power.max()
    axes[1,1].plot(f,10*np.log10(np.maximum(chord_power/norm,1e-12)),label="Recorded chord",lw=1)
    axes[1,1].plot(f,10*np.log10(np.maximum(combined_power/norm,1e-12)),label="Weighted single spectra",lw=1,alpha=.7)
    axes[1,1].set(xlim=(400,3000),ylim=(-55,3),title="Chord preserves three note frequencies",xlabel="Frequency (Hz)",ylabel="Relative level (dB)")
    for ax in axes.flat:
        ax.grid(alpha=.18)
        ax.legend(fontsize=8)
    fig.savefig(args.output/"spectra_and_envelopes.png",dpi=180)
    plt.close(fig)

    fig,axes=plt.subplots(1,2,figsize=(12,4),layout="constrained")
    for ax,index in zip(axes,(0,3)):
        y=crop(audio[index],fs,onsets[index][0],1.8)
        _,_,z0=signal.stft(y[:,0],fs,nperseg=2048,noverlap=1607)
        sf,st,z1=signal.stft(y[:,1],fs,nperseg=2048,noverlap=1607)
        power=(abs(z0)**2+abs(z1)**2)/2
        ax.pcolormesh(st,sf,10*np.log10(np.maximum(power/power.max(),1e-12)),vmin=-65,vmax=0,cmap="magma",shading="auto")
        ax.set(ylim=(0,4000),xlim=(0,1.6),title=f"{LABELS[index]}: onset, body and tail",xlabel="Time after attack (s)",ylabel="Frequency (Hz)")
    fig.savefig(args.output/"spectrograms.png",dpi=180)
    plt.close(fig)

    original_chord=match_body_rms(crop(audio[3],fs,onsets[3][0],2),fs)
    linear_sum=sum(np.sqrt(w)*crop(x,fs,ons[0],2) for w,x,ons in zip(weights,audio[:3],onsets[:3]))
    linear_sum=match_body_rms(linear_sum,fs)
    fade_samples = round(fs*.02)
    for comparison_segment in (original_chord, linear_sum):
        comparison_segment[:round(fs*.003)] *= np.linspace(0,1,round(fs*.003))[:,None]
        comparison_segment[-fade_samples:] *= np.linspace(1,0,fade_samples)[:,None]
    # Same room, panning, gain and measured fundamental envelope in all three
    # additive variants. Only partial count/frequency structure is changed.
    variants={}
    for mode in ("sine","harmonic","measured"):
        voices=additive_preview(notes,all_curves,times,fs,mode)
        phrase=[]
        for voice in voices:
            single = voice[:round(fs*.85)].copy()
            fade_samples = round(fs*.02)
            single[-fade_samples:] *= np.linspace(1,0,fade_samples)[:,None]
            phrase.append(single)
            phrase.append(np.zeros((round(fs*.15),2)))
        phrase.extend([sum(voices),np.zeros((round(fs*.3),2)),sum(voices)])
        phrase=shared_reverb(np.concatenate(phrase),fs)
        phrase[-fade_samples:] *= np.linspace(1,0,fade_samples)[:,None]
        variants[mode]=phrase
    # A common gain for additive variants preserves relative levels/headroom.
    measured_body = variants["measured"][round(fs*3.04):round(fs*3.45)]
    gain=min(.10/max(np.sqrt(np.mean(measured_body**2)),1e-9),
             .88/max(np.max(np.abs(x)) for x in variants.values()))
    for mode,x in variants.items():
        write_wav(args.output/f"additive_{mode}.wav",x*gain,fs)
    sep=np.zeros((round(fs*.4),2))
    comparison=np.concatenate([variants["sine"]*gain,sep,variants["harmonic"]*gain,sep,variants["measured"]*gain])
    write_wav(args.output/"additive_comparison.wav",comparison,fs)
    ref_gain=min(1,.88/max(np.max(np.abs(original_chord)),np.max(np.abs(linear_sum))))
    write_wav(args.output/"reference_chord_vs_single_sum.wav",np.concatenate([original_chord,sep,linear_sum])*ref_gain,fs)
    findings["preview"]={"additive_common_gain":gain,"reference_comparison_common_gain":ref_gain,
                         "additive_sequence":"C, E, G individually (0.85s + 0.15s gap), then two 2s chords separated by 0.3s",
                         "comparison_variant_order":["sine","integer harmonics","measured stretched partials"],
                         "reference_comparison_order":["recorded chord first hit","onset-aligned weighted sum of first single hits"],
                         "reference_body_rms_matching_range_s":[.04,.45],
                         "additive_gain_target":"measured-partial chord body RMS=0.10, same target as reference comparison; headroom may reduce it",
                         "additive_room":"fixed synthetic room, NOT an identified GarageBand impulse response",
                         "partial_envelopes":"measured wet energy envelopes, common to all additive variants"}
    (args.output/"analysis.json").write_text(json.dumps(findings,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Sources unchanged. All previews PCM16 stereo, 44100 Hz, unclipped.")
    for meta in metadata:
        print(f"{meta['label']}: {meta['duration_s']:.3f}s, onsets {meta['onsets_s']}, peak {meta['peak']:.6f}")
    for note in notes:
        hit=note["hits"][0]
        print(f"{note['label']}: {hit['dominant_fundamental_hz']:.2f} Hz, B={hit['stretch_B']:.6f}, fit RMSE={hit['stretch_fit_rmse_hz']:.3f} Hz")
        print("  partials:",[(p['order'],round(p['frequency_hz'],2),round(p['relative_db'],1)) for p in hit['partials']])
    print(f"Chord power-spectrum mix weights {weights}; relative residual {spectral_error:.4f}")
    print(f"Artifacts: {args.output}")


if __name__ == "__main__":
    main()
