from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path
import json
import math


SAMPLE_RATE_HZ = 48000
PHASE_BITS = 32
FRETS = 9

# 顺序：第1弦、第2弦、第3弦、第4弦
OPEN_STRING_HZ = [
    ("string_1_E4", 329.6275569),
    ("string_2_B3", 246.9416506),
    ("string_3_G3", 195.9977180),
    ("string_4_D3", 146.83238396),
]


def note_frequency(open_hz: float, fret: int) -> float:
    return open_hz * (2.0 ** (fret / 12.0))


def main() -> None:
    project_root = Path(__file__).resolve().parents[1]
    rom_path = project_root / "mem" / "note_phase_inc.mem"
    summary_path = (
        project_root
        / "docs"
        / "evidence"
        / "note_phase_inc_summary.txt"
    )

    inputs = {
        "sample_rate_hz": SAMPLE_RATE_HZ,
        "phase_bits": PHASE_BITS,
        "frets": FRETS,
        "open_strings_hz": OPEN_STRING_HZ,
    }
    input_hash = sha256(
        json.dumps(inputs, sort_keys=True).encode("utf-8")
    ).hexdigest()

    scale = 1 << PHASE_BITS
    rom_lines = []
    rows = []

    for string_name, open_hz in OPEN_STRING_HZ:
        for fret in range(FRETS):
            target_hz = note_frequency(open_hz, fret)
            phase_inc = int(round(target_hz * scale / SAMPLE_RATE_HZ))
            realized_hz = phase_inc * SAMPLE_RATE_HZ / scale
            error_pct = (realized_hz - target_hz) / target_hz * 100.0

            rom_lines.append(f"{phase_inc:08X}")
            rows.append(
                (
                    string_name,
                    fret,
                    target_hz,
                    phase_inc,
                    realized_hz,
                    error_pct,
                )
            )

    max_error = max(abs(row[5]) for row in rows)

    rom_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.parent.mkdir(parents=True, exist_ok=True)

    rom_path.write_text(
        "\n".join(rom_lines) + "\n",
        encoding="ascii",
    )

    summary = [
        "Xinxian FPGA Guitar - note phase increment summary",
        f"Generated UTC: {datetime.now(timezone.utc).isoformat()}",
        f"Input SHA-256: {input_hash}",
        f"Sample rate: {SAMPLE_RATE_HZ} Hz",
        f"Phase accumulator: {PHASE_BITS} bits",
        f"ROM entries: {len(rows)}",
        f"Maximum absolute frequency error: {max_error:.9f} %",
        "",
        "string, fret, target_hz, phase_inc_hex, realized_hz, error_pct",
    ]

    for string_name, fret, target_hz, phase_inc, realized_hz, error_pct in rows:
        summary.append(
            f"{string_name}, {fret}, {target_hz:.9f}, "
            f"{phase_inc:08X}, {realized_hz:.9f}, {error_pct:.9f}"
        )

    summary_path.write_text("\n".join(summary) + "\n", encoding="utf-8")

    print(f"Generated ROM: {rom_path}")
    print(f"Generated summary: {summary_path}")
    print(f"Entries: {len(rows)}")
    print(f"Maximum absolute frequency error: {max_error:.9f} %")


if __name__ == "__main__":
    main()