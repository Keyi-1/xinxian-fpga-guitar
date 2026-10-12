"""Check implemented device/pins/clocks, audio integrity and final RTL evidence."""
from pathlib import Path
from collections import Counter
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET

project = Path(__file__).resolve().parent
repo = project.parent.parent
pnr = project / 'impl/pnr'
name = 'neo_guitar_radial'
report = (pnr/f'{name}.rpt.txt').read_text(encoding='utf-8')
timing = (pnr/f'{name}_tr_content.html').read_text(encoding='utf-8')
build = (project/'build_console.log').read_text(encoding='utf-8')
cfg = (pnr/'device.cfg').read_text(encoding='utf-8')
cst = (repo/'constraints'/f'{name}.cst').read_text(encoding='utf-8')
assert 'GW5AT-LV60PG484AC1/I0' in report and 'Device Version>: B' in report
assert re.search(r'Logic Register as Latch\s*\|\s*0/', report)
assert re.search(r'I/O Register as Latch\s*\|\s*0/', report)
assert 'Bitstream generation completed' in build and 'ERROR' not in build
expected = dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+);', cst))
assert len(expected) == 52 and len(set(expected.values())) == 52
implemented = {}
for line in report.splitlines():
    fields = [part.strip() for part in line.split('|')]
    if len(fields) > 8 and fields[0] in expected:
        implemented[fields[0]] = fields
for port, ball in expected.items():
    fields = implemented[port]
    assert fields[2].split('/')[0] == ball and fields[3] == 'Y', (port, fields)
    voltage = 'LVCMOS15' if port.startswith('USER_BUTTON') else 'LVCMOS33'
    assert fields[7] == voltage, (port, fields)
assert 'set JTAG regular_io = false' in cfg
assert 'set SSPI regular_io = true' in cfg and 'set I2C regular_io = true' in cfg
hierarchy = ET.parse(project/'impl/gwsynthesis'/f'{name}_syn_rsc.xml').getroot()
modules = {module.get('name'): module for module in hierarchy.iter()}
assert modules['u_audio'].get('T_Bsram').startswith('112(')
assert modules['u_display'].get('T_Bsram').startswith('6(')
assert modules['u_fft'].get('T_Bsram').startswith('3(')
assert modules['u_arcsine'].get('T_Bsram', '0').split('(')[0] == '0'
for voice in range(4):
    assert modules[f'voice[{voice}].u_voice'].get('T_Bsram').startswith('24(')

violations = {}
for kind in ('Setup', 'Hold'):
    match = re.search(rf'Numbers of {kind} Violated Endpoints</td>\s*<td>(\d+)</td>', timing)
    assert match and int(match[1]) == 0, kind
    violations[kind.lower()] = int(match[1])
clocks = {}
for clock, required in [('audio_clk_12m288', 12.288), ('sys_clk_50m', 50.0)]:
    match = re.search(rf'<td>{clock}</td>\s*<td>([\d.]+)\(MHz\)</td>\s*<td>([\d.]+)\(MHz\)</td>', timing)
    assert match, clock
    actual = float(match[2])
    assert actual >= required, (clock, actual)
    clocks[clock] = {'required_mhz': required, 'actual_fmax_mhz': actual}
resources = {}
for label in ('Logic', 'Register', 'BSRAM', 'DSP'):
    match = re.search(rf'^\s+{label}\s+\|\s+([\d.]+)/([\d.]+)', report, re.M)
    assert match, label
    used, available = [float(value) if '.' in value else int(value) for value in match.groups()]
    assert used <= available
    resources[label] = {'used': used, 'available': available}

benches = ['tb_guitar_pcm_cdc','tb_guitar_radial_fft','tb_guitar_radial_bands','tb_guitar_radial_palette','tb_guitar_radial_renderer','tb_neo_guitar_radial','tb_guitar_visual_cdc','tb_guitar_visual_telemetry','tb_guitar_audio_top','tb_guitar_harmonic_audio_top','tb_guitar_audio_latency','tb_neo_guitar_main_equivalence','tb_piano_voice_core','tb_full_piano_voice','tb_rock_voice_core','tb_guitar_effect_buttons','tb_guitar_play_control','tb_antibeat_pcm_compare','tb_rgb_spectrum_timing','tb_spectrum_display_top','tb_full_guitar_top','tb_neo_full_guitar_top','tb_rgb_panel_defaults']
logs = {}
for bench in benches:
    log = (repo/'sim/temp'/f'{bench}.log').read_text(encoding='utf-8')
    assert 'PASS:' in log and not re.search(r'FAIL:|\*\* (Error|Fatal|Warning):', log), bench
    logs[bench] = re.findall(r'PASS: [^\r\n]+', log)
integration = '\n'.join(logs['tb_neo_guitar_radial'])
comparison = re.search(r'(\d+) audio clocks EXACTLY match FULL baseline', integration)
assert comparison and int(comparison[1]) > 6_000_000
line_match = re.search(r'(\d+) lines, worst (\d+)/3186 clocks', '\n'.join(logs['tb_guitar_radial_renderer']))
assert line_match and int(line_match[2]) < 3186
gate_dir = repo/'sim/temp/guitar_radial_gate'
gate = (gate_dir/'run.log').read_text(encoding='utf-8')
assert 'PASS: synthesized LCD' in gate and not re.search(r'FAIL:|MISMATCH|\*\* (Error|Fatal)', gate)
vendor_warning = r'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)'
for line in gate.splitlines():
    if line.startswith('# ** Warning:'):
        assert re.search(vendor_warning, line), line
gate_evidence = json.loads((gate_dir/'verification.json').read_text(encoding='utf-8-sig'))
netlist = project/'impl/gwsynthesis'/f'{name}.vg'
assert gate_evidence['result'] == 'PASS'
assert gate_evidence['netlist_sha256'] == hashlib.sha256(netlist.read_bytes()).hexdigest()
dac_frames = re.search(r'PASS: (\d+) actual DAC frames bit-identical', gate)
lcd_pixels = re.search(r'PASS: synthesized LCD (\d+) board clocks, (\d+) visible pixels EXACTLY match', gate)
assert dac_frames and int(dac_frames[1]) >= 6500
assert lcd_pixels and int(lcd_pixels[2]) > 900000

# Explicitly guard the timbre/effect arithmetic and ROM files, not just flags.
audio_files = [repo/path for path in [
    'rtl/synth/piano_voice_core.v','rtl/audio_io/four_voice_piano_audio_core.v',
    'rtl/audio_io/piano_stereo_effects.v','rtl/audio_io/piano_stereo_chorus.v',
    'rtl/audio_io/piano_stereo_room.v','rtl/audio_io/pt8211_tx.v',
    'rtl/control/guitar_play_control.v','rtl/control/phase_slide_smoother.v',
    'rtl/control/guitar_effect_buttons.v','rtl/config/guitar_config.vh','rtl/config/rock_coeffs.vh']]
audio_files += sorted((repo/'mem').glob('*.mem'))
audio_hashes = {}
for file in audio_files:
    relative = file.relative_to(repo).as_posix()
    baseline = subprocess.run(['git','show',f'HEAD:{relative}'], cwd=repo, check=True, capture_output=True).stdout
    # Git normalizes line endings; this check intentionally ignores CRLF.
    assert baseline.replace(b'\r\n', b'\n') == file.read_bytes().replace(b'\r\n', b'\n'), relative
    audio_hashes[relative] = hashlib.sha256(file.read_bytes()).hexdigest()
top = (repo/'rtl/top/neo_guitar_radial_top.v').read_text()
assert '.PIANO_MODES(32)' in top and '.PIANO_CONTROL_ENABLE(1)' in top and '.PIANO_ROCK_ENABLE(1)' in top

source_files = [repo/'rtl/top/neo_guitar_radial_top.v',repo/'rtl/top/guitar_audio_top.v',
    repo/'rtl/audio_io/four_string_board_audio_chain.v',repo/'rtl/display/lcd_rgb_scan_480x272.v']
source_files += sorted((repo/'rtl/display').glob('guitar_*.v'))
source_files += [repo/'tools/gen_radial_display.py',repo/'tools/gen_radial_palette.py',repo/'tools/setup_radial_project.py']
source_files += [repo/'constraints'/f'{name}.{ext}' for ext in ['cst','sdc']]
source_files += [project/'build.tcl', project/f'{name}.gprj']
source_files += [project/'run_sim.ps1', project/'check_result.py']
source_files += [repo/'sim/tb'/f'{bench}.sv' for bench in benches[:8]]
source_files += [repo/'sim/tb/tb_neo_guitar_radial_gate.sv',project/'run_gate_check.ps1']
bitstream = pnr/f'{name}.fs'
result = {
    'device': 'GW5AT-LV60PG484AC1/I0', 'device_version': 'B',
    'implemented_ports_checked': len(implemented), 'pin_voltage_check': 'PASS',
    'clocks': clocks, 'violations': violations, 'resources': resources,
    'panel': {'active_size': [480,272], 'pixel_clock_mhz':50/6,
        'horizontal_total':531,'vertical_total':292,'refresh_hz':50_000_000/6/531/292,
        'curve_center':[343.5,135.5],'curve_radius':[74.5,74.5],'layout':[208,272],'spectrum_bars':64,'fft_size':1024,'fft_bands':32, 'native_pixel_rendering':True},
    'display_bsrams':int(modules['u_display'].get('T_Bsram').split('(')[0]), 'audio_configuration':{'voices':4,'modes_per_voice':32,'sample_rate_hz':48000},
    'audio_clocks_compared_exact':int(comparison[1]),
    'scanlines_checked':int(line_match[1]), 'worst_scanline_clocks':int(line_match[2]),
    'scanline_clock_budget':3186, 'bench_count':len(benches),'test_results':logs,
    'synthesized_dac_frames_exact':int(dac_frames[1]),'synthesized_lcd_pixels_exact':int(lcd_pixels[2]),
    'synthesized_netlist_sha256':gate_evidence['netlist_sha256'],
    'vendor_primitive_unused_width_warning_filter':vendor_warning,
    'unchanged_audio_sources_sha256':audio_hashes,
    'warning_codes':dict(Counter(re.findall(r'WARN\s+\((\w+)\)',build))),
    'warning_notes':[
        'PR1014: V13/V22 generic clock-input routing; both internal clock domains must pass STA',
        'EX3791: bounded integer/fraction extraction and modulo hue arithmetic',
        'EX2526: pre-existing rock_envelope ROM width diagnostic; audio ROMs/core unchanged',
        'PA1001: unused arithmetic outputs removed by synthesis'],
    'external_panel_timing':'60 ns RTL settling checked; external setup/hold unspecified',
    'hardware_status':'Integrated program awaits user download; original panel timing/pins physically verified',
    'bitstream_bytes':bitstream.stat().st_size,'bitstream_sha256':hashlib.sha256(bitstream.read_bytes()).hexdigest(),
    'source_sha256':{file.relative_to(repo).as_posix():hashlib.sha256(file.read_bytes()).hexdigest() for file in source_files},
}
(project/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
try:
    from PIL import Image
    for file in (repo/'sim/temp').glob('radial_*.ppm'):
        Image.open(file).save(file.with_suffix('.png'))
except ImportError:
    pass
print(json.dumps({key:result[key] for key in ['clocks','violations','resources','audio_clocks_compared_exact',
    'worst_scanline_clocks','bitstream_sha256']},ensure_ascii=False,indent=2))
