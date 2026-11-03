#!/usr/bin/env python3
"""Generate Q1.15 Hann and 1024-point FFT twiddle ROMs."""

import argparse
import math
from pathlib import Path


def q15(value: float) -> int:
    return max(-32768, min(32767, round(value * 32767))) & 0xFFFF


def write_hex(path: Path, values: list[int]) -> None:
    path.write_text("".join(f"{value:04X}\n" for value in values), encoding="ascii")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=Path("mem"))
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    hann = [q15(0.5 - 0.5 * math.cos(2.0 * math.pi * n / 1023.0))
            for n in range(1024)]
    cos_table = [q15(math.cos(2.0 * math.pi * k / 1024.0))
                 for k in range(512)]
    sin_table = [q15(math.sin(2.0 * math.pi * k / 1024.0))
                 for k in range(512)]

    write_hex(args.output_dir / "hann1024_q15.mem", hann)
    write_hex(args.output_dir / "fft1024_cos_q15.mem", cos_table)
    write_hex(args.output_dir / "fft1024_sin_q15.mem", sin_table)
    print(f"generated 1024 Hann and 512 complex twiddle entries in {args.output_dir}")


if __name__ == "__main__":
    main()
