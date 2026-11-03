from pathlib import Path
import argparse

import matplotlib
matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import soundfile as sf


FS = 48000
FREQ = 329.6275569
DURATION_S = 2.0
AMPLITUDE = 0.8


def make_envelope(length: int, fs: int) -> np.ndarray:
    attack = int(0.005 * fs)
    decay = int(0.250 * fs)
    release = int(0.400 * fs)
    sustain = 0.72

    env = np.full(length, sustain, dtype=np.float64)

    attack_end = min(attack, length)
    env[:attack_end] = np.linspace(
        0.0, 1.0, attack_end, endpoint=False
    )

    decay_end = min(attack + decay, length)
    if decay_end > attack_end:
        env[attack_end:decay_end] = np.linspace(
            1.0,
            sustain,
            decay_end - attack_end,
            endpoint=False,
        )

    release_start = max(0, length - release)
    env[release_start:] = np.linspace(
        sustain,
        0.0,
        length - release_start,
    )

    return env


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--play",
        action="store_true",
        help="生成后播放 WAV",
    )
    args = parser.parse_args()

    project_root = Path(__file__).resolve().parents[1]
    build_dir = project_root / "build"
    build_dir.mkdir(parents=True, exist_ok=True)

    sample_count = int(FS * DURATION_S)
    time = np.arange(sample_count) / FS

    envelope = make_envelope(sample_count, FS)
    waveform = (
        AMPLITUDE
        * envelope
        * np.sin(2.0 * np.pi * FREQ * time)
    )

    waveform = np.clip(waveform, -1.0, 1.0)

    wav_path = build_dir / "reference_e4.wav"
    wave_plot_path = build_dir / "reference_e4_waveform.png"
    spectrum_plot_path = build_dir / "reference_e4_spectrum.png"

    sf.write(wav_path, waveform, FS, subtype="PCM_16")

    plt.figure(figsize=(12, 4))
    plt.plot(time[:2400], waveform[:2400])
    plt.xlabel("Time (s)")
    plt.ylabel("Amplitude")
    plt.title("Reference E4 waveform")
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(wave_plot_path, dpi=150)
    plt.close()

    spectrum = np.abs(np.fft.rfft(waveform))
    frequencies = np.fft.rfftfreq(sample_count, 1.0 / FS)

    plt.figure(figsize=(12, 4))
    plt.plot(frequencies, spectrum)
    plt.xlim(0, 2000)
    plt.xlabel("Frequency (Hz)")
    plt.ylabel("Magnitude")
    plt.title("Reference E4 spectrum")
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(spectrum_plot_path, dpi=150)
    plt.close()

    print(f"WAV: {wav_path}")
    print(f"Waveform plot: {wave_plot_path}")
    print(f"Spectrum plot: {spectrum_plot_path}")
    print(f"Sample rate: {FS} Hz")
    print(f"Frequency: {FREQ:.7f} Hz")
    print(f"Samples: {sample_count}")

    if args.play:
        import sounddevice as sd

        print("Playing reference E4...")
        sd.play(waveform.astype(np.float32), FS)
        sd.wait()
        print("Playback finished")


if __name__ == "__main__":
    main()