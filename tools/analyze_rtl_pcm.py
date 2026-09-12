from pathlib import Path

import matplotlib
matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import soundfile as sf


FS = 48000
VECTOR_LENGTH = 48


def load_signed_mem(path: Path, bits: int) -> np.ndarray:
    values = []

    for line in path.read_text(encoding="ascii").splitlines():
        token = line.strip()

        if not token:
            continue

        value = int(token, 16)
        value &= (1 << bits) - 1

        if value & (1 << (bits - 1)):
            value -= 1 << bits

        values.append(value)

    return np.asarray(values, dtype=np.int32)


def rms(values: np.ndarray) -> float:
    values_float = values.astype(np.float64)
    return float(np.sqrt(np.mean(values_float ** 2)))


def main() -> None:
    project_root = Path(__file__).resolve().parents[1]
    vector_dir = project_root / "sim" / "vectors"
    build_dir = project_root / "build"
    build_dir.mkdir(parents=True, exist_ok=True)

    golden_path = vector_dir / "voice_e4_pcm16.mem"
    rtl_path = vector_dir / "rtl_voice_e4_pcm16.mem"

    golden = load_signed_mem(golden_path, 16)
    rtl = load_signed_mem(rtl_path, 16)

    if len(golden) != VECTOR_LENGTH:
        raise ValueError(f"Golden vector length: {len(golden)}")

    if len(rtl) != VECTOR_LENGTH:
        raise ValueError(f"RTL vector length: {len(rtl)}")

    diff = rtl - golden

    max_abs_error = int(np.max(np.abs(diff)))
    rms_error = rms(diff)
    rtl_peak = int(np.max(np.abs(rtl)))
    rtl_rms = rms(rtl)
    golden_rms = rms(golden)

    window = np.hanning(VECTOR_LENGTH)
    rtl_spectrum = np.abs(
        np.fft.rfft(rtl.astype(np.float64) * window, n=1024)
    )
    golden_spectrum = np.abs(
        np.fft.rfft(golden.astype(np.float64) * window, n=1024)
    )
    spectrum_error = float(
        np.max(np.abs(rtl_spectrum - golden_spectrum))
    )

    rtl_wav_path = build_dir / "rtl_voice_e4_vector.wav"
    golden_wav_path = build_dir / "golden_voice_e4_vector.wav"
    plot_path = build_dir / "rtl_vs_golden_pcm16.png"

    sf.write(
        rtl_wav_path,
        rtl.astype(np.int16),
        FS,
        subtype="PCM_16",
    )

    sf.write(
        golden_wav_path,
        golden.astype(np.int16),
        FS,
        subtype="PCM_16",
    )

    time = np.arange(VECTOR_LENGTH) / FS

    plt.figure(figsize=(12, 4))
    plt.plot(time, golden, "o-", label="Python golden")
    plt.plot(time, rtl, "x--", label="RTL export")
    plt.xlabel("Time (s)")
    plt.ylabel("PCM16")
    plt.title("RTL PCM16 versus Python golden vector")
    plt.grid(True)
    plt.legend()
    plt.tight_layout()
    plt.savefig(plot_path, dpi=150)
    plt.close()

    print(f"Samples: {VECTOR_LENGTH}")
    print(f"Nominal frequency: 329.6275569 Hz")
    print(f"RTL peak: {rtl_peak}")
    print(f"RTL RMS: {rtl_rms:.6f}")
    print(f"Golden RMS: {golden_rms:.6f}")
    print(f"Maximum absolute error: {max_abs_error}")
    print(f"RMS error: {rms_error:.6f}")
    print(f"Maximum spectrum difference: {spectrum_error:.6f}")
    print(f"RTL WAV: {rtl_wav_path}")
    print(f"Golden WAV: {golden_wav_path}")
    print(f"Plot: {plot_path}")

    if max_abs_error != 0:
        raise SystemExit("FAIL: RTL PCM differs from golden vector")

    print("PASS: exported RTL PCM matches golden vector")


if __name__ == "__main__":
    main()