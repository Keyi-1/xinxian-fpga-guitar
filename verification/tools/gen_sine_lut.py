from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path
import json
import math


LUT_SIZE = 1024
VALUE_BITS = 16
AMPLITUDE = (1 << (VALUE_BITS - 1)) - 1


def to_twos_complement(value: int, bits: int) -> int:
    return value & ((1 << bits) - 1)


def main() -> None:
    project_root = Path(__file__).resolve().parents[1]
    rom_path = project_root / "mem" / "sine_lut.mem"
    summary_path = (
        project_root
        / "docs"
        / "evidence"
        / "sine_lut_summary.txt"
    )

    inputs = {
        "lut_size": LUT_SIZE,
        "value_bits": VALUE_BITS,
        "amplitude": AMPLITUDE,
        "waveform": "full-cycle sine",
    }

    input_hash = sha256(
        json.dumps(inputs, sort_keys=True).encode("utf-8")
    ).hexdigest()

    values = []
    max_error_lsb = 0.0

    for index in range(LUT_SIZE):
        phase = 2.0 * math.pi * index / LUT_SIZE
        ideal = math.sin(phase) * AMPLITUDE
        quantized = int(round(ideal))
        max_error_lsb = max(max_error_lsb, abs(ideal - quantized))
        values.append(quantized)

    rom_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.parent.mkdir(parents=True, exist_ok=True)

    rom_lines = [
        f"{to_twos_complement(value, VALUE_BITS):04X}"
        for value in values
    ]

    rom_path.write_text(
        "\n".join(rom_lines) + "\n",
        encoding="ascii",
    )

    summary_lines = [
        "Xinxian FPGA Guitar - sine LUT summary",
        f"Generated UTC: {datetime.now(timezone.utc).isoformat()}",
        f"Input SHA-256: {input_hash}",
        f"LUT size: {LUT_SIZE}",
        f"Value width: {VALUE_BITS} bits signed",
        f"Amplitude: {AMPLITUDE}",
        f"Maximum quantization error: {max_error_lsb:.6f} LSB",
        "",
        "index, signed_value, hex_value",
    ]

    for index, value in enumerate(values):
        hex_value = to_twos_complement(value, VALUE_BITS)
        summary_lines.append(
            f"{index}, {value}, {hex_value:04X}"
        )

    summary_path.write_text(
        "\n".join(summary_lines) + "\n",
        encoding="utf-8",
    )

    print(f"Generated ROM: {rom_path}")
    print(f"Generated summary: {summary_path}")
    print(f"Entries: {len(values)}")
    print(f"Maximum quantization error: {max_error_lsb:.6f} LSB")


if __name__ == "__main__":
    main()