"""Verify the implemented device/pins/timing and simulation before delivery."""
from pathlib import Path
import hashlib
import html
import json
import re
from collections import Counter

project = Path(__file__).resolve().parent
repo = project.parent.parent
pnr = project / "impl/pnr"
report = (pnr / "neo_lcd_lissajous.rpt.txt").read_text(encoding="utf-8")
timing = (pnr / "neo_lcd_lissajous_tr_content.html").read_text(encoding="utf-8")
simulation = (project / "simulation_console.log").read_text(encoding="utf-8")
build = (project / "build_console.log").read_text(encoding="utf-8")
cst = (repo / "constraints/neo_lcd_lissajous.cst").read_text(encoding="utf-8")
cfg = (pnr / "device.cfg").read_text(encoding="utf-8")
assert "GW5AT-LV60PG484AC1/I0" in report and "Device Version>: B" in report
assert "Bitstream generation completed" in build and "ERROR" not in build
assert "PASS: LISSAJOUS 13 full frames" in simulation
assert not re.search(r"FAIL:|\*\* (Error|Fatal|Warning):", simulation)

# Inspect implemented ports, not only the input constraint file.
expected = dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+);', cst))
assert len(expected) == 27 and len(set(expected.values())) == 27
implemented = {}
for line in report.splitlines():
    fields = [field.strip() for field in line.split("|")]
    if len(fields) > 8 and fields[0] in expected:
        implemented[fields[0]] = fields
for name, ball in expected.items():
    fields = implemented[name]
    assert fields[2].split("/")[0] == ball and fields[3] == "Y", (name, fields)
    expected_type = "LVCMOS15" if name in {"sys_rst_n", "key_pattern_n", "key_pause_n"} else "LVCMOS33"
    assert fields[7] == expected_type, (name, fields)
assert "set JTAG regular_io = false" in cfg
assert "set SSPI regular_io = true" in cfg and "set I2C regular_io = true" in cfg

def violations(kind):
    match = re.search(rf"Numbers of {kind} Violated Endpoints</td>\s*<td>(\d+)</td>", timing)
    assert match, kind
    return int(match[1])

setup, hold = violations("Setup"), violations("Hold")
assert setup == hold == 0
fmax = re.search(r"<td>sys_clk</td>\s*<td>50\.000\(MHz\)</td>\s*<td>([\d.]+)\(MHz\)</td>", timing)
assert fmax and float(fmax[1]) >= 50
resources = {}
for label in ("Logic", "Register", "BSRAM", "DSP"):
    match = re.search(rf"^\s+{label}\s+\|\s+(\d+)/(\d+)", report, re.M)
    assert match, label
    resources[label] = {"used": int(match[1]), "available": int(match[2])}

regression_names = ["tb_rgb_spectrum_timing", "tb_spectrum_display_top", "tb_full_guitar_top",
                    "tb_neo_full_guitar_top", "tb_rgb_panel_defaults"]
for name in regression_names:
    log = (repo / "sim/temp" / f"{name}.log").read_text(encoding="utf-8")
    assert "PASS:" in log and not re.search(r"FAIL:|\*\* (Error|Fatal|Warning):", log), name

source_names = ["rtl/top/neo_lcd_lissajous_top.v", "rtl/display/lcd_rgb_scan_480x272.v",
                "rtl/display/lcd_lissajous_renderer.v", "rtl/display/lcd_lissajous_ram.v",
                "rtl/display/lcd_lissajous_sine.v", "rtl/display/lcd_neon_palette.v",
                "constraints/neo_lcd_lissajous.cst", "constraints/neo_lcd_lissajous.sdc",
                "gowin/neo_lcd_lissajous/build.tcl", "sim/tb/tb_neo_lcd_lissajous.sv",
                "sim/tb/tb_rgb_panel_defaults.sv", "rtl/display/rgb_spectrum_timing.v",
                "rtl/display/spectrum_display_top.v", "rtl/top/full_guitar_top.v",
                "rtl/top/neo_full_guitar_top.v"]
bitstream = pnr / "neo_lcd_lissajous.fs"
result = {
    "device": "GW5AT-LV60PG484AC1/I0", "device_version": "B",
    "implemented_ports_checked": len(implemented), "pin_voltage_check": "PASS",
    "board_clock_mhz": 50, "pixel_clock_mhz": 50/6,
    "horizontal_total": 531, "vertical_total": 292, "active_size": [480,272],
    "refresh_hz": (50_000_000/6)/(531*292), "setup_violations": setup,
    "hold_violations": hold, "actual_fmax_mhz": float(fmax[1]), "resources": resources,
    "demo_simulation": "PASS: 13 complete frames, keys, pause/resume, reset, bank/write safety",
    "simulation_control_parameters": {"STARTUP_CYCLES":16,"KEY_DEBOUNCE_CYCLES":8,"AUTO_MODE_FRAMES":4},
    "hardware_control_parameters": {"STARTUP_CYCLES":65536,"KEY_DEBOUNCE_CYCLES":1000000,"AUTO_MODE_FRAMES":512},
    "existing_display_regressions": regression_names,
    "warning_codes": dict(Counter(re.findall(r"WARN\s+\((\w+)\)", build))),
    "warnings_notes": ["PR1014: V22 board oscillator uses generic input routing; implemented internal STA passes",
                       "EX3791: intentional modulo-256 color hue additions; PA1001: unused synthesized arithmetic outputs"],
    "external_panel_setup_hold": "Not specified; 60 ns settling checked in RTL, no invented panel delay constraint",
    "hardware_status": "New demo awaits user download; original timing/pin map was physically verified by user",
    "bitstream_bytes": bitstream.stat().st_size,
    "bitstream_sha256": hashlib.sha256(bitstream.read_bytes()).hexdigest(),
    "source_sha256": {name: hashlib.sha256((repo/name).read_bytes()).hexdigest() for name in source_names},
}
(project/"verification.json").write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
try:
    from PIL import Image
    for ppm in (project/"temp/simulation").glob("*.ppm"):
        Image.open(ppm).save(ppm.with_suffix(".png"))
except ImportError:
    pass
print(json.dumps({key:result[key] for key in ["implemented_ports_checked","actual_fmax_mhz",
    "setup_violations","hold_violations","resources","bitstream_sha256"]},ensure_ascii=False,indent=2))
