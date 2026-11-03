"""Create listenable artifacts and envelope measurements from actual RTL exports.
Run sim/tb/tb_antibeat_pcm_compare.sv with sim/run_main_regression.ps1 first.
"""
from pathlib import Path
from datetime import date
import wave
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
FS = 48000
OUT = ROOT / "build" / "antibeat"
OUT.mkdir(parents=True, exist_ok=True)


def load_pcm(name):
    path = ROOT / "sim" / "temp" / f"antibeat_{name}_pcm16.txt"
    samples = np.array([[int(x, 16) for x in line.split()]
                        for line in path.read_text().splitlines()], dtype=np.int32)
    samples[samples >= 32768] -= 65536
    if samples.shape != (96000, 2):
        raise ValueError(f"{name}: expected 96000 stereo samples, got {samples.shape}")
    return samples


def write_wav(path, samples):
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(FS)
        output.writeframes(samples.astype("<i2").tobytes())


def analytic_envelope(signal):
    # Zero padding keeps the 40..160 ms measurement away from FFT end effects.
    n = 65536
    frequency = np.fft.fft(signal, n)
    weights = np.zeros(n)
    weights[0] = weights[n // 2] = 1
    weights[1:n // 2] = 2
    return np.abs(np.fft.ifft(frequency * weights))[:len(signal)]


def main():
    samples = {name: load_pcm(name) for name in ("before", "after")}
    for name, pcm in samples.items():
        write_wav(OUT / f"antibeat_{name}.wav", pcm)
    combined = np.concatenate((samples["before"], np.zeros((FS // 4, 2), dtype=np.int32),
                               samples["after"]))
    write_wav(OUT / "antibeat_comparison.wav", combined)
    report = [
        f"RTL anti-beat PCM comparison ({date.today().isoformat()})",
        "96,000 PCM16 stereo frames per variant; exported at the converter outputs.",
        "Playback: 48 kHz. No separate loudness normalization of the WAV files.",
        "Both use the same frets 0x8852 (F#4/E4/D#4/A#3), velocity 2 and plucks.",
        "First second: repeated 3-note chord; second second: repeated 4-note chord.",
        "Comparison WAV: before 2 s, silence 0.25 s, after 2 s.",
        "Bench asserts identical per-voice PCM, sample cadence and lifecycle.",
        "",
        "Envelope measurement: first 3-note chord, 40..160 ms after start.",
        "Hilbert envelope of the paired channel, divided by the solo-channel",
        "envelope to remove the common natural decay. Use its 5th/95th percentiles.",
        "Depth=(P95-P05)/(P95+P05). This is one constructed digital example,",
        "not a universal perceptual score or a physical-board measurement.",
    ]
    curves = {}
    for name, pcm in samples.items():
        segment = pcm[:24000]
        paired_side = 1 if name == "before" else 0
        paired = analytic_envelope(segment[:, paired_side])
        solo = analytic_envelope(segment[:, 1 - paired_side])
        ratio = paired[1920:7680] / np.maximum(solo[1920:7680], 1)
        low, high = np.percentile(ratio, (5, 95))
        depth = (high - low) / (high + low)
        report.append(f"{name}: P05={low:.6f}, P95={high:.6f}, depth={depth:.6f}, "
                      f"PCM16 peak={np.max(np.abs(pcm))}")
        curves[name] = ratio
    report.append("")
    report.append("The original verified flattened test sources were not modified.")
    evidence = ROOT / "docs" / "evidence" / "antibeat_pcm_comparison.txt"
    evidence.write_text("\n".join(report) + "\n", encoding="utf-8")
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        time = np.arange(1920, 7680) / FS * 1000
        fig, ax = plt.subplots(figsize=(9, 3.8), layout="constrained")
        ax.plot(time, curves["before"], color="#cf564c", label="Before")
        ax.plot(time, curves["after"], color="#3276c5", label="After")
        ax.set(xlabel="Time after pluck (ms)", ylabel="Normalized pair envelope",
               title="Actual RTL PCM: three-note example", ylim=(0, 2.15))
        ax.grid(alpha=0.2)
        ax.legend(loc="upper right")
        fig.savefig(OUT / "antibeat_envelope.png", dpi=160)
        plt.close(fig)
    except ImportError:
        pass  # Plot is optional; audio and numeric evidence require NumPy only.
    print("\n".join(report))
    print(f"Artifacts: {OUT}")


if __name__ == "__main__":
    main()
