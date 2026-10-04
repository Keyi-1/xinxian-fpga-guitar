from hashlib import sha256
from pathlib import Path

from gen_voice_golden import (
    EnvelopeModel,
    LUT_ADDR_BITS,
    LUT_VALUE_BITS,
    PHASE_BITS,
    PCM_PRODUCT_SHIFT,
    load_mem,
    to_hex,
)


VECTOR_LENGTH = 48800
NOTE_OFF_INDEX = 36000


def main() -> None:
    project_root = Path(__file__).resolve().parents[1]

    sine_path = project_root / "mem" / "sine_lut.mem"
    phase_path = project_root / "mem" / "note_phase_inc.mem"

    vector_dir = project_root / "sim" / "vectors"
    evidence_dir = project_root / "docs" / "evidence"

    pcm24_path = vector_dir / "voice_e4_long_pcm24.mem"
    pcm16_path = vector_dir / "voice_e4_long_pcm16.mem"
    summary_path = evidence_dir / "voice_e4_long_summary.txt"

    sine_lut = load_mem(
        sine_path,
        bits=LUT_VALUE_BITS,
        signed=True,
    )

    phase_rom = load_mem(
        phase_path,
        bits=PHASE_BITS,
        signed=False,
    )

    phase_inc = phase_rom[0]
    phase_acc = 0
    envelope = EnvelopeModel()

    pcm24_values = []
    pcm16_values = []

    for sample_index in range(VECTOR_LENGTH):
        note_on = sample_index == 0
        note_off = sample_index == NOTE_OFF_INDEX

        phase_acc = (
            phase_acc + phase_inc
        ) & ((1 << PHASE_BITS) - 1)

        lut_addr = phase_acc >> (
            PHASE_BITS - LUT_ADDR_BITS
        )

        nco_sample = sine_lut[lut_addr]

        env_level, _ = envelope.step(
            note_on=note_on,
            note_off=note_off,
        )

        pcm24 = (nco_sample * env_level) >> PCM_PRODUCT_SHIFT

        if pcm24 < 0:
            magnitude = -pcm24
            pcm16 = -((magnitude + 128) >> 8)
        else:
            pcm16 = (pcm24 + 128) >> 8

        pcm16 = max(-32768, min(32767, pcm16))

        pcm24_values.append(pcm24)
        pcm16_values.append(pcm16)

    vector_dir.mkdir(parents=True, exist_ok=True)
    evidence_dir.mkdir(parents=True, exist_ok=True)

    pcm24_path.write_text(
        "\n".join(to_hex(value, 24) for value in pcm24_values)
        + "\n",
        encoding="ascii",
    )

    pcm16_path.write_text(
        "\n".join(to_hex(value, 16) for value in pcm16_values)
        + "\n",
        encoding="ascii",
    )

    summary_text = "\n".join(
        [
            "Xinxian FPGA Guitar - long E4 golden vector",
            f"Vector length: {VECTOR_LENGTH}",
            "Sample rate: 48000 Hz",
            "Nominal frequency: 329.6275569 Hz",
            f"note_on index: 0",
            f"note_off index: {NOTE_OFF_INDEX}",
            f"Phase increment: {to_hex(phase_inc, 32)}",
            f"Sine LUT SHA-256: {sha256(sine_path.read_bytes()).hexdigest()}",
            f"Phase ROM SHA-256: {sha256(phase_path.read_bytes()).hexdigest()}",
            f"PCM24 range: {min(pcm24_values)} .. {max(pcm24_values)}",
            f"PCM16 range: {min(pcm16_values)} .. {max(pcm16_values)}",
        ]
    )

    summary_path.write_text(
        summary_text + "\n",
        encoding="utf-8",
    )

    print(f"Generated: {pcm24_path}")
    print(f"Generated: {pcm16_path}")
    print(f"Generated: {summary_path}")
    print(f"Samples: {VECTOR_LENGTH}")
    print(f"note_off index: {NOTE_OFF_INDEX}")


if __name__ == "__main__":
    main()
