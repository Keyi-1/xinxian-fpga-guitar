from hashlib import sha256
from pathlib import Path
import json


FS = 48000
PHASE_BITS = 32
LUT_ADDR_BITS = 10
LUT_VALUE_BITS = 16
VECTOR_LENGTH = 48
PCM_PRODUCT_SHIFT = 7  # Q1.15 gain with eight fractional bits retained in PCM24.

ATTACK_SAMPLES = 32
DECAY_SAMPLES = 8192
RELEASE_SAMPLES = 12288
SUSTAIN_LEVEL = 24576
FULL_SCALE = 32767


STATE_IDLE = 0
STATE_ATTACK = 1
STATE_DECAY = 2
STATE_SUSTAIN = 3
STATE_RELEASE = 4


def load_mem(path: Path, bits: int, signed: bool) -> list[int]:
    values = []

    for line in path.read_text(encoding="ascii").splitlines():
        token = line.strip()

        if not token:
            continue

        value = int(token, 16)
        value &= (1 << bits) - 1

        if signed and (value & (1 << (bits - 1))):
            value -= 1 << bits

        values.append(value)

    return values


def to_hex(value: int, bits: int) -> str:
    digits = (bits + 3) // 4
    return f"{value & ((1 << bits) - 1):0{digits}X}"


def convert_pcm24_to_16(pcm24: int) -> int:
    if pcm24 < 0:
        magnitude = -pcm24
        scaled = -((magnitude + 128) >> 8)
    else:
        scaled = (pcm24 + 128) >> 8

    if scaled > 32767:
        return 32767

    if scaled < -32768:
        return -32768

    return scaled


class EnvelopeModel:
    def __init__(self) -> None:
        self.level = 0
        self.active = False
        self.state = STATE_IDLE

        self.attack_step = (
            FULL_SCALE + ATTACK_SAMPLES - 1
        ) // ATTACK_SAMPLES

        self.decay_step = (
            FULL_SCALE - SUSTAIN_LEVEL + DECAY_SAMPLES - 1
        ) // DECAY_SAMPLES

        self.release_step = (
            SUSTAIN_LEVEL + RELEASE_SAMPLES - 1
        ) // RELEASE_SAMPLES

    def step(self, note_on: bool, note_off: bool) -> tuple[int, bool]:
        if note_on:
            self.level = 0
            self.active = True
            self.state = STATE_ATTACK

        elif (
            note_off
            and self.state not in (STATE_IDLE, STATE_RELEASE)
        ):
            self.state = STATE_RELEASE
            self.active = True

        elif self.state == STATE_IDLE:
            self.level = 0
            self.active = False

        elif self.state == STATE_ATTACK:
            self.active = True

            if self.level + self.attack_step >= FULL_SCALE:
                self.level = FULL_SCALE
                self.state = STATE_DECAY
            else:
                self.level += self.attack_step

        elif self.state == STATE_DECAY:
            self.active = True

            if self.level <= SUSTAIN_LEVEL + self.decay_step:
                self.level = SUSTAIN_LEVEL
                self.state = STATE_SUSTAIN
            else:
                self.level -= self.decay_step

        elif self.state == STATE_SUSTAIN:
            self.level = SUSTAIN_LEVEL
            self.active = True

        elif self.state == STATE_RELEASE:
            if self.level <= self.release_step:
                self.level = 0
                self.active = False
                self.state = STATE_IDLE
            else:
                self.level -= self.release_step
                self.active = True

        else:
            self.level = 0
            self.active = False
            self.state = STATE_IDLE

        return self.level, self.active


def main() -> None:
    project_root = Path(__file__).resolve().parents[1]

    sine_path = project_root / "mem" / "sine_lut.mem"
    phase_path = project_root / "mem" / "note_phase_inc.mem"

    vector_path = (
        project_root
        / "sim"
        / "vectors"
        / "voice_e4_golden.csv"
    )
    pcm24_path = (
        project_root
        / "sim"
        / "vectors"
        / "voice_e4_pcm24.mem"
    )
    pcm16_path = (
        project_root
        / "sim"
        / "vectors"
        / "voice_e4_pcm16.mem"
    )
    summary_path = (
        project_root
        / "docs"
        / "evidence"
        / "voice_e4_golden_summary.txt"
    )

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

    if len(sine_lut) != 1 << LUT_ADDR_BITS:
        raise ValueError(
            f"Unexpected sine LUT size: {len(sine_lut)}"
        )

    if len(phase_rom) < 1:
        raise ValueError("Phase ROM is empty")

    phase_inc = phase_rom[0]
    phase_acc = 0
    envelope = EnvelopeModel()
    rows = []

    for sample_index in range(VECTOR_LENGTH):
        note_on = sample_index == 0
        note_off = sample_index == 24

        phase_acc = (
            phase_acc + phase_inc
        ) & ((1 << PHASE_BITS) - 1)

        lut_addr = phase_acc >> (
            PHASE_BITS - LUT_ADDR_BITS
        )
        nco_sample = sine_lut[lut_addr]

        env_level, active = envelope.step(
            note_on=note_on,
            note_off=note_off,
        )

        pcm24 = (nco_sample * env_level) >> PCM_PRODUCT_SHIFT
        pcm16 = convert_pcm24_to_16(pcm24)

        rows.append(
            {
                "sample_index": sample_index,
                "note_on": int(note_on),
                "note_off": int(note_off),
                "phase_acc_hex": to_hex(phase_acc, 32),
                "lut_addr": lut_addr,
                "nco_sample": nco_sample,
                "env_level": env_level,
                "active": int(active),
                "pcm24": pcm24,
                "pcm16": pcm16,
            }
        )

    vector_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.parent.mkdir(parents=True, exist_ok=True)

    csv_lines = [
        "sample_index,note_on,note_off,"
        "phase_acc_hex,lut_addr,nco_sample,"
        "env_level,active,pcm24,pcm16"
    ]

    for row in rows:
        csv_lines.append(
            f"{row['sample_index']},"
            f"{row['note_on']},"
            f"{row['note_off']},"
            f"{row['phase_acc_hex']},"
            f"{row['lut_addr']},"
            f"{row['nco_sample']},"
            f"{row['env_level']},"
            f"{row['active']},"
            f"{row['pcm24']},"
            f"{row['pcm16']}"
        )

    vector_path.write_text(
        "\n".join(csv_lines) + "\n",
        encoding="ascii",
    )

    pcm24_path.write_text(
        "\n".join(to_hex(row["pcm24"], 24) for row in rows)
        + "\n",
        encoding="ascii",
    )

    pcm16_path.write_text(
        "\n".join(to_hex(row["pcm16"], 16) for row in rows)
        + "\n",
        encoding="ascii",
    )

    inputs = {
        "sample_rate_hz": FS,
        "phase_bits": PHASE_BITS,
        "lut_addr_bits": LUT_ADDR_BITS,
        "vector_length": VECTOR_LENGTH,
        "note_on_index": 0,
        "note_off_index": 24,
        "pcm_product_shift": PCM_PRODUCT_SHIFT,
        "sine_lut_sha256": sha256(
            sine_path.read_bytes()
        ).hexdigest(),
        "phase_rom_sha256": sha256(
            phase_path.read_bytes()
        ).hexdigest(),
    }

    summary_lines = [
        "Xinxian FPGA Guitar - E4 golden vector",
        f"Configuration: {json.dumps(inputs, sort_keys=True)}",
        f"Phase increment: {to_hex(phase_inc, 32)}",
        f"Vector samples: {VECTOR_LENGTH}",
        f"Maximum PCM24: {max(row['pcm24'] for row in rows)}",
        f"Minimum PCM24: {min(row['pcm24'] for row in rows)}",
        f"Maximum PCM16: {max(row['pcm16'] for row in rows)}",
        f"Minimum PCM16: {min(row['pcm16'] for row in rows)}",
        "",
        "The CSV is the primary human-readable reference.",
        "The MEM files are intended for ModelSim scoreboards.",
    ]

    summary_path.write_text(
        "\n".join(summary_lines) + "\n",
        encoding="utf-8",
    )

    print(f"Generated: {vector_path}")
    print(f"Generated: {pcm24_path}")
    print(f"Generated: {pcm16_path}")
    print(f"Generated: {summary_path}")
    print(f"Samples: {VECTOR_LENGTH}")
    print(f"Phase increment: {to_hex(phase_inc, 32)}")
    print(
        "PCM16 range: "
        f"{min(row['pcm16'] for row in rows)} .. "
        f"{max(row['pcm16'] for row in rows)}"
    )


if __name__ == "__main__":
    main()
