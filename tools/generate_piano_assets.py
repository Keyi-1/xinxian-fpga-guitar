"""Freeze the approved reference envelopes and short hammer residuals as FPGA ROMs.

Only this offline preparation needs SciPy and the supplied recordings. Playback
uses the committed .mem tables at 48 kHz, without a computer, CPU or sample files.
The envelopes are observations of wet recordings, not identified dry damping.
"""
from pathlib import Path
import hashlib
import json
import warnings
import numpy as np
from scipy import signal
from scipy.io import wavfile

ROOT = Path(__file__).resolve().parents[1]
FS = 48000
ENV_FRAMES = 256
ENV_STEP = 512
HAMMER_SAMPLES = 2048


def save_hex(path, values, bits):
    mask = (1 << bits) - 1
    path.write_text("".join(f"{int(v)&mask:0{(bits+3)//4}X}\n" for v in values.flat), encoding="ascii")


def main():
    directory = ROOT / "build" / "garageband_analysis"
    info = json.loads((directory / "analysis.json").read_text(encoding="utf-8"))
    curves = np.loadtxt(directory / "observed_wet_modal_envelopes.csv", delimiter=",", skiprows=1)
    t, observed = curves[:,0], curves[:,1:].T.reshape(3,8,-1)
    rom_time = np.arange(ENV_FRAMES) * ENV_STEP / FS
    envelopes = np.zeros((3,8,ENV_FRAMES))
    ratios = np.zeros((3,8), dtype=np.int64)
    hammer = np.zeros((3,HAMMER_SAMPLES))
    provenance = []
    for bank, note in enumerate(info["notes"]):
        hits = note["hits"]
        f1 = np.mean([h["dominant_fundamental_hz"] for h in hits])
        frequencies = []
        for n in range(8):
            freq = np.mean([h["partials"][n]["frequency_hz"] for h in hits])
            eligible = all(h["partials"][n]["relative_db"] >= -45 and
                           h["partials"][n]["local_snr_db"] >= 12 for h in hits)
            ratios[bank,n] = round((freq/f1 if eligible else n+1) * 2**20)
            if not eligible:
                continue
            frequencies.append(freq)
            # Preserve the approved observed body; smoothly retire its wet tail.
            env = np.interp(rom_time, t, observed[bank,n])
            tail_start = 1.6
            tail_value = np.interp(tail_start,t,observed[bank,n])
            tail = rom_time > tail_start
            env[tail] = tail_value * np.exp(-(rom_time[tail]-tail_start)/.18)
            env *= np.clip((rom_time[-1]-rom_time)/.05,0,1)
            env[0] = 0  # Hammer starts promptly; tonal body enters smoothly.
            envelopes[bank,n] = env

        meta = info["metadata"][bank]
        path = Path(meta["path"])
        assert hashlib.sha256(path.read_bytes()).hexdigest() == meta["sha256"]
        with warnings.catch_warnings():
            warnings.filterwarnings("ignore",category=wavfile.WavFileWarning)
            rate,pcm = wavfile.read(path)
        x = pcm.astype(float)/32768
        onset = hits[1]["onset_s"]  # First C attack is left-censored.
        begin = round(onset*rate)
        length = round(.065*rate)
        stereo = x[begin:begin+length]
        channel = int(np.argmax(np.mean(stereo**2,axis=0)))
        mono = stereo[:,channel]
        seconds = np.arange(len(mono))/rate
        # Remove fitted slowly varying sinusoids, then keep a short band-limited
        # residual. This approximates the transient; it is not perfect HPSS or
        # isolation of the real hammer/mechanical noise from the wet recording.
        columns = []
        for freq in frequencies:
            for basis in (np.sin(2*np.pi*freq*seconds), np.cos(2*np.pi*freq*seconds)):
                columns.extend([basis,basis*seconds/.065,basis*(seconds/.065)**2])
        basis = np.column_stack(columns)
        residual = mono - basis @ np.linalg.lstsq(basis,mono,rcond=None)[0]
        residual = signal.sosfiltfilt(signal.butter(3,[600,7500],btype="bandpass",fs=rate,output="sos"),residual)
        residual = signal.resample_poly(residual,160,147) if rate==44100 else signal.resample(residual,round(len(residual)*FS/rate))
        residual = residual[:HAMMER_SAMPLES]
        ht = np.arange(len(residual))/FS
        residual *= np.clip(ht/.001,0,1) * np.exp(-ht/.014)
        residual *= np.clip((ht[-1]-ht)/.008,0,1)
        hammer[bank,:len(residual)] = residual
        provenance.append({"file_label":note["label"],"source_sha256":meta["sha256"],
                           "reference_fundamental_hz":float(f1),"hammer_source_hit":2,
                           "hammer_source_channel":channel,"hammer_source_onset_s":onset})

    # Convex interpolation bounds every bank's sum of modal amplitudes.
    # Modes <= 0.5 PCM full scale, hammer <= 0.0625; stereo /2 stays below unity
    # even with four identical full-velocity voices aligned in phase.
    envelope_gain = 16384 / np.max(envelopes.sum(axis=1))
    quantized_env = np.rint(envelopes*envelope_gain).astype(np.int64)
    hammer_gain = 2048 / max(np.max(np.abs(hammer)),1e-12)
    quantized_hammer = np.rint(hammer*hammer_gain).astype(np.int64)
    assert quantized_env.min() >= 0 and quantized_env.sum(axis=1).max() <= 16388
    assert abs(quantized_hammer).max() <= 2048
    assert np.all(quantized_env[:,:,0]==0) and np.all(quantized_env[:,:,-1]==0)
    assert np.all(quantized_hammer[:,0]==0) and np.all(quantized_hammer[:,-1]==0)
    mem = ROOT / "mem"
    save_hex(mem/"piano_envelope.mem",quantized_env,16)
    save_hex(mem/"piano_ratio.mem",ratios,24)
    save_hex(mem/"piano_hammer.mem",quantized_hammer,16)
    rng = np.random.default_rng(23)
    phases = np.zeros((3,8),dtype=np.int64)
    phases[:,1:] = rng.integers(0,2**32,size=(3,7),dtype=np.int64)
    save_hex(mem/"piano_phase.mem",phases,32)
    metadata = {"sample_rate":FS,"profiles":provenance,"partials":8,
                "envelope_frames":ENV_FRAMES,"envelope_step_samples":ENV_STEP,
                "hammer_samples":HAMMER_SAMPLES,"ratio_fraction_bits":20,
                "envelope_gain":envelope_gain,"hammer_gain":hammer_gain,
                "modal_sum_bound_pcm16":int(quantized_env.sum(axis=1).max()),
                "hammer_peak_pcm16":int(abs(quantized_hammer).max()),
                "hardware_profile_centers_hz":[261.625565,329.627557,391.995436],
                "profile_mapping":"Initial octave transfer of C/E/G timbre, clamped below/above this register; fundamental pitch never transposed",
                "limitations":"Wet observed envelopes; residual transient is approximate; no complete velocity/register calibration"}
    for name in ("piano_envelope.mem","piano_ratio.mem","piano_hammer.mem","piano_phase.mem"):
        metadata[name+"_sha256"] = hashlib.sha256((mem/name).read_bytes()).hexdigest()
    (mem/"piano_profile.json").write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    out = ROOT / "build" / "piano"
    out.mkdir(parents=True,exist_ok=True)
    wavfile.write(out/"extracted_hammer_residuals.wav",FS,np.concatenate([np.column_stack([h,h]) for h in quantized_hammer]).astype(np.int16))
    print(json.dumps(metadata,ensure_ascii=False,indent=2))
    print("Profile midpoint increments:",[round(np.sqrt(a*b)*2**32/FS) for a,b in [(261.625565,329.627557),(329.627557,391.995436)]])


if __name__ == "__main__":
    main()
