# NEO four-string matrix audio optimization handoff

Date: 2026-10-02

This note records the side-conversation work on the independent
`neo_four_string_matrix_audio_test` project.  It does not replace or modify the
verified `neo_minimal_audio` project or the existing FULL automatic-pin P&R
baseline.

## Scope and current status

The test combines the 4x8 fret matrix, four independent audio voices, PCM24 to
PCM16 conversion, PT8211 transmission, and NEO Dock analogue output.  It is a
temporary code-only playing test: a stable fret press approximates a pluck.
The final product must instead use the matrix only to select pitch and use the
MCP3208 pluck sensor to create `note_on` and velocity.

Before the latest changes, board testing found:

- strong pops at note onset;
- the 3:1 stereo crossfeed sounded worse than the earlier hard-separated
  string 0/1 or string 2/3 pairs;
- natural decay was too short.

The current RTL was subsequently rebuilt and verified on the physical FPGA
board on 2026-10-02.  This board-verified version includes the always-enabled
post-reset amplifier policy, dynamic hard-stereo allocation, removed
crossfeed, and doubled natural-decay parameters described below.  No separate
oscilloscope capture or quantitative audio measurement was supplied for this
listening verification, so do not invent additional numerical evidence.

## Latest design behaviour

### Chord capture

- A 30 ms window (`CHORD_CAPTURE_SAMPLES = 1440` at 48 kHz) collects newly
  stable contacts.
- Contacts collected inside one window produce one sample-aligned `note_on`
  batch.
- Presses separated by more than the window still produce separate attacks;
  this is expected and cannot be inferred as one chord without delaying input
  further or using a real pluck trigger.

### Dynamic hard stereo allocation

- Fixed string mapping (`0/2` left and `1/3` right) was removed.
- On `note_on`, new voices are assigned to the less-loaded primary channel.
- A voice keeps its assigned channel for its complete lifetime.
- The first two active voices are therefore placed on opposite channels,
  regardless of string number.
- Crossfeed was removed after listening tests.  Left and right are now fully
  separated, and each primary sum is divided by two.  This recreates the
  previously preferred hard-stereo pair behaviour for arbitrary first pairs
  while preserving four-voice headroom.

### Plucked envelope

`PLUCK_MODE` is optional and defaults to zero in the reusable audio modules, so
existing MINIMAL/FULL instances retain their original ADSR behaviour.

The matrix test enables pluck mode with:

- attack: 96 samples, approximately 2 ms;
- fast decay: 9600 samples, approximately 200 ms;
- fast exponential shift: 13;
- slow exponential shift: 16;
- release/damping shift: 10;
- idle threshold: 64.

Both natural-decay time constants are approximately twice those of the first
pluck attempt.  Physical fret release still applies the faster damping path.
The exponential decay uses shifts and subtraction and does not require an MCU,
soft CPU, or multiplier.

### Amplifier control

The earlier test tied `pa_en_n` to `voice_active`.  That power-cycled the
analogue amplifier at every transition from silence to a new note and was a
likely source of strong startup pops.

The latest test behaviour is:

```verilog
assign pa_en_n = audio_rst_n ? 1'b0 : 1'b1;
```

The amplifier is muted during reset and remains enabled after reset release.
One startup transient can still occur when releasing KEY0 or configuring the
FPGA, but ordinary notes no longer toggle amplifier power.

## Width-warning cleanup

The following explicit, range-proven selections replace implicit truncation:

- pluck attack step: `pluck_attack_step_wide[15:0]`;
- PCM product scaling: `pcm_product[30:7]`;
- separated channel scaling: `mix_left_primary[24:1]` and
  `mix_right_primary[24:1]`.

These selections are numerically equivalent to the earlier shifts for the
proven ranges and remove the reported `EX3791` warnings.

## Files changed

Repository sources:

- `rtl/control/voice_envelope.v`
- `rtl/audio_io/voice_audio_core.v`
- `rtl/audio_io/four_voice_audio_core.v`
- `rtl/top/neo_four_string_matrix_audio_test_top.v`
- `sim/tb/tb_neo_four_string_matrix_audio_test.sv`
- `docs/NEO_FOUR_STRING_MATRIX_AUDIO_TEST.md`

Actual flattened Gowin project copies:

- `gowin/neo_four_string_matrix_audio_test/src/voice_envelope.v`
- `gowin/neo_four_string_matrix_audio_test/src/voice_audio_core.v`
- `gowin/neo_four_string_matrix_audio_test/src/four_voice_audio_core.v`
- `gowin/neo_four_string_matrix_audio_test/src/neo_four_string_matrix_audio_test_top.v`

The dedicated CST/SDC were not changed.  The MINIMAL and FULL projects were
not changed.

## Simulation evidence

The updated matrix/audio regression passed with zero ModelSim errors and
warnings:

```text
PASS: 4x8 matrix selects four continuous simultaneous voices without scan-rate retrigger or gating
PASS: equal F4 selections share one exact phase increment; only physical beat frequencies remain
PASS: contacts inside the capture window launch on one audio event
PASS: arbitrary first-pair voices use opposite hard-separated primary channels
PASS: amplifier remains enabled between notes, avoiding per-note analogue startup pops
PASS: held frets generate one fixed-velocity pluck with doubled natural decay and no sustain plateau
```

Compatibility regressions also passed:

```text
PASS: attack, decay, sustain and release envelope
PASS: four-level velocity amplitude and release envelope
PASS: KEY3 sustain extends Release normal=7 extended=31
PASS: four-voice audio core, event hold and independent voices
```

The flattened Gowin source set also compiled in ModelSim with zero errors and
warnings.

## Completed board verification and reproduction steps

The user confirmed that the current code version has completed physical-board
verification.  Retain the following procedure when the bitstream must be
reproduced after any later RTL change.

Open:

```text
T:\Documents\AMD\xinxian-fpga-guitar\gowin\neo_four_string_matrix_audio_test\neo_four_string_matrix_audio_test.gprj
```

Then:

1. Run `Clean All`.
2. Run Synthesize.
3. Confirm the four earlier `EX3791` warnings are gone.
4. Run Place & Route.
5. Require zero setup and hold violations.
6. Generate a new `.fs`; never reuse a bitstream from before the related RTL
   change.
7. Program SRAM first, using a conservative JTAG frequency such as 2 MHz.
8. Test all six two-string combinations, especially 0+2 and 1+3.
9. Distinguish a single pop at FPGA configuration/KEY0 release from a pop at
   every ordinary note.
10. Record any new subjective or measured difference before changing the
    verified parameters again.

## Reusable harsh-sound and beat-frequency playbook

For future harsh, trembling, or popping audio, classify the symptom before
changing RTL:

1. **Scan-rate tremolo:** periodic muting locked to matrix row rate.  Verify
   that scanning only updates stable note state and never gates oscillator,
   envelope, PCM, or PT8211 slots.
2. **Physical beating:** two close but unequal frequencies create amplitude
   variation at their difference frequency.  Verify tuning and phase
   increments, then prefer dynamic stereo separation and natural decay.  Do
   not add chorus or detuning; those usually make beating worse.
3. **Analogue startup pop:** check whether PA enable toggles with each note.
   Keep PA enabled between notes or add a deliberately timed analogue mute
   sequence.
4. **Digital discontinuity:** inspect `note_on`, envelope level, each
   `voice_pcm`, PCM16 output, and PT8211 frame boundary.  A new `note_on` that
   forces a still-audible envelope instantly to zero can click.  If this is
   observed, the next candidate is a short retrigger crossfade or a restart
   from the current envelope level rather than zero.
5. **Clipping or truncation:** verify each channel's worst-case signed range
   before PCM24-to-PCM16 conversion.  Use explicit slices only after proving
   the discarded bits are sign extension.
6. **Unnatural sustained roughness:** remove fixed Sustain plateaus from
   code-only pluck tests and use a fast initial decay plus a slow tail.
7. **Near-simultaneous human presses:** use a bounded chord-capture window for
   testing.  In the final product, use the real pluck sensor as the shared
   musical trigger instead of treating fret contact as a pluck.

Hard stereo reduces electrical beating most effectively with headphones or a
true stereo output.  A downstream mono sum can reintroduce the same beating and
must not be mistaken for matrix-scan gating.
