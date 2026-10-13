"""Identify the approved modal body's parameters; never store recorded PCM.

Only offline parameter identification needs NumPy and reference analysis files.
The FPGA calculates sinusoids/envelopes and a procedural noise-filter hammer.
The envelopes are observations of wet recordings, not identified dry damping.
"""
from pathlib import Path
import hashlib
import json
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
FS = 48000
ENV_FRAMES = 256
ENV_STEP = 512


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
        provenance.append({"file_label":note["label"],"source_sha256":meta["sha256"],
                           "reference_fundamental_hz":float(f1),
                           "usage":"Modal frequency/amplitude parameter identification only"})

    # Convex interpolation bounds every bank's sum of modal amplitudes.
    # Modes <= 0.5 PCM full scale, hammer <= 0.0625; stereo /2 stays below unity
    # even with four identical full-velocity voices aligned in phase.
    envelope_gain = 16384 / np.max(envelopes.sum(axis=1))
    quantized_env = np.rint(envelopes*envelope_gain).astype(np.int64)
    assert quantized_env.min() >= 0 and quantized_env.sum(axis=1).max() <= 16388
    assert np.all(quantized_env[:,:,0]==0) and np.all(quantized_env[:,:,-1]==0)
    mem = ROOT / "mem"
    save_hex(mem/"piano_envelope.mem",quantized_env,16)
    save_hex(mem/"piano_ratio.mem",ratios,24)
    rng = np.random.default_rng(23)
    phases = np.zeros((3,8),dtype=np.int64)
    phases[:,1:] = rng.integers(0,2**32,size=(3,7),dtype=np.int64)
    save_hex(mem/"piano_phase.mem",phases,32)
    metadata = {"sample_rate":FS,"profiles":provenance,"partials":8,
                "envelope_frames":ENV_FRAMES,"envelope_step_samples":ENV_STEP,
                "hammer_model":"piano_hammer_model.json; real-time noise-excited resonators; no PCM ROM",
                "ratio_fraction_bits":20,"envelope_gain":envelope_gain,
                "modal_sum_bound_pcm16":int(quantized_env.sum(axis=1).max()),
                "hammer_peak_bound_pcm16":2048,
                "hardware_profile_centers_hz":[261.625565,329.627557,391.995436],
                "profile_mapping":"Initial octave transfer of C/E/G timbre, clamped below/above this register; fundamental pitch never transposed",
                "limitations":"Wet observed modal parameters; procedural attack is approximate; no complete velocity/register calibration"}
    for name in ("piano_envelope.mem","piano_ratio.mem","piano_phase.mem"):
        metadata[name+"_sha256"] = hashlib.sha256((mem/name).read_bytes()).hexdigest()
    (mem/"piano_profile.json").write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps(metadata,ensure_ascii=False,indent=2))
    print("Profile midpoint increments:",[round(np.sqrt(a*b)*2**32/FS) for a,b in [(261.625565,329.627557),(329.627557,391.995436)]])


if __name__ == "__main__":
    main()
