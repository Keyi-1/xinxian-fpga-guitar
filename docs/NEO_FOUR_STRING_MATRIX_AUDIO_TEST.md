# NEO Dock four-string matrix audio test

This is an independent board test.  It does not replace the verified
`neo_minimal_audio` project or the existing FULL implementation baseline.

## Purpose

The test proves that:

- the 4x8 diode matrix selects one highest pressed fret per string;
- all four strings can remain active at the same time;
- matrix row scanning never gates, mutes, or retriggers an audio voice;
- a fret change on an already active string changes frequency without a new
  Attack event;
- releasing one string does not affect the other three;
- equal notes use exactly the same phase increment;
- contacts that settle inside a 30 ms capture window launch together on one
  audio event, rather than producing several almost-simultaneous Attacks;
- newly launched voices are dynamically assigned to the less-loaded PT8211
  channel and keep that position for their complete lifetime;
- the first two active voices use opposite hard-separated PT8211 channels;
  each side is divided by two, preserving four-voice headroom without
  reintroducing electrical beating through crossfeed;
- after reset, the analogue amplifier stays enabled between notes so every
  new Attack does not create another amplifier startup transient.

This test intentionally starts one fixed-velocity pluck when a new fret contact
becomes stable.  Its multiplier-free envelope has a 2 ms Attack, a 200 ms
initial decay, and a slower natural tail with no constant Sustain plateau.  Its
decay time constants are approximately twice those of the first pluck test. A held
fret does not retrigger; releasing it applies faster damping, and it must be
pressed again before another test pluck can occur.  It does not use MCP3208
sensing, so the 30 ms capture window remains a code-only test approximation
rather than the final playing policy.  In the final instrument, the matrix
selects pitch and the separate pluck sensor should generate `note_on`.

## Files

- `rtl/top/neo_four_string_matrix_audio_test_top.v`
- `constraints/neo_four_string_matrix_audio_test.cst`
- `constraints/neo_four_string_matrix_audio_test.sdc`
- `sim/tb/tb_neo_four_string_matrix_audio_test.sv`

The top module is `neo_four_string_matrix_audio_test_top`.

## J13 wiring

The current dedicated constraint uses NEO Dock J13 (`SDRAM0 CONN.`, close to
the PCIe connector).  It leaves the PMOD1 data pins available for the later
MCP3208 test.

| Matrix PCB | H1 | J13 | Dock net | FPGA ball |
|---|---:|---:|---|---:|
| ROW0 | 3 | 1 | SDRAM0_D0 | E14 |
| ROW1 | 4 | 2 | SDRAM0_D1 | E13 |
| ROW2 | 5 | 3 | SDRAM0_D2 | C15 |
| ROW3 | 6 | 4 | SDRAM0_D3 | C14 |
| COL0 | 7 | 5 | SDRAM0_D4 | B13 |
| COL1 | 8 | 6 | SDRAM0_D5 | C13 |
| COL2 | 9 | 7 | SDRAM0_D6 | A14 |
| COL3 | 10 | 8 | SDRAM0_D7 | A13 |
| COL4 | 11 | 18 | SDRAM0_D8 | B21 |
| COL5 | 12 | 17 | SDRAM0_D9 | A21 |
| COL6 | 13 | 16 | SDRAM0_D10 | B20 |
| COL7 | 14 | 15 | SDRAM0_D11 | A20 |

Power must be connected separately:

```text
H1-1 / 3V3 -> J8-1 or J9-1 3.3 V
H1-2 / GND -> J13-12 GND or a PMOD GND
```

Do not connect H1-1 to J13-11.  J13-11 is `5V_Peripheral`, not 3.3 V.

Do not connect an SDRAM0 module or another peripheral to J13 at the same time.

## Gowin project

Create a new independent project, for example `neo_four_string_matrix_audio_test`:

```text
Device family:   GW5AT-60B
Part:            GW5AT-LV60PG484AC1/I0
Package:         PG484A
Device Version:  B
Top module:      neo_four_string_matrix_audio_test_top
```

Add these Verilog sources:

```text
rtl/input/matrix_scanner.v
rtl/audio_io/sample_tick_gen.v
rtl/control/voice_envelope.v
rtl/synth/sine_nco.v
rtl/audio_io/voice_audio_core.v
rtl/audio_io/pcm24_mixer.v
rtl/audio_io/four_voice_audio_core.v
rtl/audio_io/pcm24_to_16.v
rtl/audio_io/pt8211_tx.v
rtl/control/note_phase_table.v
rtl/top/neo_four_string_matrix_audio_test_top.v
```

Add the dedicated CST and SDC listed above.  Also add:

```text
mem/note_phase_inc.mem
mem/sine_lut.mem
```

If Gowin copies and flattens every source into its project `src` directory,
copy `guitar_config.vh` there and make the two memory initializers use:

```verilog
$readmemh("note_phase_inc.mem", phase_rom);
$readmemh("sine_lut.mem", sine_lut);
```

Do not overwrite the existing MINIMAL or FULL projects.

Before programming SRAM, require:

- synthesis success;
- Place & Route success;
- zero setup violations;
- zero hold violations;
- Pin Report matches the dedicated CST exactly;
- no P&R warning indicating an unusable or dedicated pin;
- the generated bitstream belongs to this independent test project.

## ModelSim regression

Run from a writable directory directly below `sim`, so that `../../mem` points
to the repository memory files.  For example, from
`sim/modelsim_matrix_audio`:

```bash
vlib work
vlog -sv +incdir+../../rtl/config ../../rtl/input/matrix_scanner.v ../../rtl/audio_io/sample_tick_gen.v ../../rtl/control/voice_envelope.v ../../rtl/synth/sine_nco.v ../../rtl/audio_io/voice_audio_core.v ../../rtl/audio_io/pcm24_mixer.v ../../rtl/audio_io/four_voice_audio_core.v ../../rtl/audio_io/pcm24_to_16.v ../../rtl/audio_io/pt8211_tx.v ../../rtl/control/note_phase_table.v ../../rtl/top/neo_four_string_matrix_audio_test_top.v ../tb/tb_neo_four_string_matrix_audio_test.sv
vsim -c work.tb_neo_four_string_matrix_audio_test -do "run -all; quit -f"
```

Required output:

```text
PASS: 4x8 matrix selects four continuous simultaneous voices without scan-rate retrigger or gating
PASS: equal F4 selections share one exact phase increment; only physical beat frequencies remain
PASS: contacts inside the capture window launch on one audio event
PASS: arbitrary first-pair voices use opposite hard-separated primary channels
PASS: amplifier remains enabled between notes, avoiding per-note analogue startup pops
PASS: held frets generate one fixed-velocity pluck with doubled natural decay and no sustain plateau
```

The regression must also finish with zero ModelSim errors and warnings.

## Hardware acceptance

Status: the current version, including persistent post-reset PA enable,
dynamic hard-stereo voice allocation, no crossfeed, and doubled natural decay,
was confirmed on the physical FPGA board on 2026-10-02.  The checklist below
is retained for reproducing that result after future RTL changes.

1. Power off before changing wiring.
2. Check continuity from every H1 signal to its intended J13 pin.
3. Check that H1-1 is 3.3 V relative to H1-2 before attaching the matrix PCB.
4. Download only to FPGA SRAM for the first test.
5. Press one fret on each string separately and confirm the expected pitch.
6. Press one fret on all four strings within approximately 30 ms and confirm
   that all four notes start as one chord, then decay naturally.
7. Use string 0 fret 1 and string 1 fret 6 for an exact F4/F4 test.  These two
   voices use the same phase increment and must not exhibit scan-rate tremolo.
8. Change a fret on one held string.  The other three voices must remain
   continuous.
9. Press strings 0 and 2, then strings 1 and 3.  In both cases the first two
   active voices should be separated primarily left/right rather than fixed to
   the same channel.
10. Release the four strings at different times.  Each release must apply
    independent fast damping.

Two deliberately different close frequencies can produce a real acoustic beat
at their frequency difference.  That slow beat is not a matrix failure.  A
fault is indicated by periodic muting locked to the row scan rate, repeated
Attack transients, or another string stopping when the selected scan row
changes.
