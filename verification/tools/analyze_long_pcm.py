from pathlib import Path
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
VEC = ROOT / "sim" / "vectors"
BUILD = ROOT / "build"
BUILD.mkdir(exist_ok=True)

FS = 48000
N = 48800


def load_hex(path, bits):
    values = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if line:
            value = int(line.split()[0], 16)
            if value & (1 << (bits - 1)):
                value -= 1 << bits
            values.append(value)
    return np.asarray(values, dtype=np.int64)


golden = load_hex(VEC / "voice_e4_long_pcm16.mem", 16)
rtl = load_hex(VEC / "rtl_e4_long_pcm16.mem", 16)

assert len(golden) == N
assert len(rtl) == N

diff = np.abs(rtl - golden)

print(f"Samples: {N}")
print(f"Maximum absolute error: {diff.max()}")
print(f"RMS error: {np.sqrt(np.mean((rtl - golden) ** 2)):.6f}")

sections = [
    ("attack", 0, 32),
    ("decay", 32, 32 + 8192),
    ("sustain", 32 + 8192, 36000),
    ("release", 36000, 48000),
]

for name, start, end in sections:
    segment = rtl[start:end].astype(np.float64)
    print(
        f"{name}: "
        f"peak={np.max(np.abs(segment))}, "
        f"rms={np.sqrt(np.mean(segment ** 2)):.3f}"
    )

print(f"First sample: {rtl[0]}")
print(f"Sample at note_off: {rtl[36000]}")
print(f"Last sample: {rtl[-1]}")
print(f"Final 512 samples peak: {np.max(np.abs(rtl[-512:]))}")

sf.write(
    BUILD / "voice_e4_long_rtl.wav",
    rtl.astype(np.int16),
    FS,
    subtype="PCM_16",
)

sf.write(
    BUILD / "voice_e4_long_golden.wav",
    golden.astype(np.int16),
    FS,
    subtype="PCM_16",
)

if np.any(diff != 0):
    indices = np.flatnonzero(diff)
    print(f"FAIL: mismatches={len(indices)}")
    for index in indices[:10]:
        print(f"MISMATCH index={index} rtl={rtl[index]} golden={golden[index]}")
    raise SystemExit(1)

print("PASS: long RTL PCM16 matches Python golden vector")
print("WAV files generated successfully")