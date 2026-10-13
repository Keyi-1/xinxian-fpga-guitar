"""Final experiment acceptance: pins, STA, resources, PCM audit and hash-bound gate."""
from pathlib import Path
import hashlib
import argparse
import json
import re
import subprocess
import xml.etree.ElementTree as ET

project=Path(__file__).resolve().parent
repo=project.parent.parent
name='neo_guitar_procedural'
baseline='fb574a4'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--implementation-root',type=Path,default=project/'impl',
    help='Implementation directory; permits checking an archived successful build without overwriting a later failed IDE run')
parser.add_argument('--build-log',type=Path,default=project/'build_console_shared_lp.log')
args=parser.parse_args()
implementation=args.implementation_root.resolve()
pnr=implementation/'pnr'
report=(pnr/f'{name}.rpt.txt').read_text(encoding='utf-8')
timing=(pnr/f'{name}_tr_content.html').read_text(encoding='utf-8')
build=args.build_log.read_text(encoding='utf-8')
assert 'GW5AT-LV60PG484AC1/I0' in report and 'Device Version>: B' in report
assert 'Bitstream generation completed' in build and 'ERROR' not in build
assert 'ERROR' not in report,'PnR report contains errors; this run is not a valid implementation'
ide_path=project/f'impl/{name}_process_config.json'
ide=json.loads(ide_path.read_text())
assert (ide['Place_Option'],ide['Route_Option'],ide['Clock_Route_Order'],ide['Correct_Hold_Violation'])==('4','2',1,True)
command=(pnr/'cmd.do').read_text()
for option,value in [('place_option','4'),('route_option','2'),('clock_route_order','1'),('correct_hold','1')]:
    assert re.search(rf'^-{option}\s+{value}\s*$',command,re.M),(option,value)
for label in ('Logic Register as Latch','I/O Register as Latch'):
    assert re.search(rf'{label}\s*\|\s*0/',report),label
cst=(repo/'constraints/neo_guitar_radial.cst').read_text()
pins=dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+);',cst))
assert len(pins)==52 and len(set(pins.values()))==52
rows={}
for line in report.splitlines():
    fields=[s.strip() for s in line.split('|')]
    if len(fields)>8 and fields[0] in pins:rows[fields[0]]=fields
for port,ball in pins.items():
    row=rows[port]
    assert row[2].split('/')[0]==ball and row[3]=='Y',port
    assert row[7]==('LVCMOS15' if port.startswith('USER_BUTTON') else 'LVCMOS33'),port
cfg=(pnr/'device.cfg').read_text()
assert 'set JTAG regular_io = false' in cfg
assert 'set SSPI regular_io = true' in cfg and 'set I2C regular_io = true' in cfg
violations={}
for kind in ('Setup','Hold'):
    m=re.search(rf'Numbers of {kind} Violated Endpoints</td>\s*<td>(\d+)</td>',timing)
    assert m and int(m[1])==0,kind
    violations[kind.lower()]=int(m[1])
clocks={}
for clock,required in [('audio_clk_12m288',12.288),('sys_clk_50m',50.)]:
    m=re.search(rf'<td>{clock}</td>\s*<td>([\d.]+)\(MHz\)</td>\s*<td>([\d.]+)\(MHz\)</td>',timing)
    assert m and float(m[2])>=required,(clock,m.groups() if m else 'missing')
    clocks[clock]=dict(required_mhz=required,actual_fmax_mhz=float(m[2]))
resources={}
for label in ('Logic','Register','BSRAM','DSP'):
    m=re.search(rf'^\s+{label}\s+\|\s+([\d.]+)/([\d.]+)',report,re.M)
    assert m,label
    used,total=map(float,m.groups());assert used<=total,label
    resources[label]=dict(used=used,available=total)
hierarchy=ET.parse(implementation/f'gwsynthesis/{name}_syn_rsc.xml').getroot()
def count(node,key):return int(node.get(key,'0').split('(')[0])
models=[x for x in hierarchy.iter() if x.get('name')=='procedural_hammer.u_hammer']
assert len(models)==4
for model in models:
    assert count(model,'T_Bsram')==0
    assert all(count(model,k)==0 for k in model.attrib if k.startswith('T_MULT')),model.attrib
voices=[x for x in hierarchy.iter() if re.fullmatch(r'voice\[[0-3]\]\.u_voice',x.get('name',''))]
assert len(voices)==4 and all(count(x,'T_Bsram')==16 for x in voices)
assert resources['BSRAM']['used']==86
assert resources['DSP']['used']<=115.5
files=ET.parse(project/f'{name}.gprj').getroot().find('FileList')
assert files is not None
assert all('piano_legacy' not in f.get('path','') and not f.get('path','').endswith('/piano_hammer.mem') for f in files)
core=(repo/'rtl/synth/piano_voice_core.v').read_text()
assert 'hammer_rom' not in core and 'piano_hammer.mem' not in core
assert 'shared_operand_a*shared_operand_b' in core
model=(repo/'rtl/synth/piano_hammer_model.v').read_text()
assert '$readmem' not in model and 'random_step' in model
assert not (repo/'mem/piano_hammer.mem').exists()
parameters=json.loads((repo/'mem/piano_hammer_model.json').read_text())
for bank in parameters['profiles']:
    for a1,a2 in zip(bank['a1_q14'],bank['a2_q14']):
        # Exact integer Schur conditions for 1+a1*z^-1+a2*z^-2 (Q14).
        assert 0<=a2<16384 and 16384+a1+a2>0 and 16384-a1+a2>0
legacy=(repo/'sim/reference/piano_legacy/piano_hammer.mem').read_text().split()
original=subprocess.run(['git','show',f'{baseline}:mem/piano_hammer.mem'],cwd=repo,check=True,capture_output=True).stdout.decode().split()
assert legacy==original,'A/B reference differs from accepted residual'
unchanged=[
    'rtl/audio_io/piano_stereo_effects.v','rtl/audio_io/piano_stereo_chorus.v',
    'rtl/audio_io/piano_stereo_room.v','rtl/audio_io/pt8211_tx.v',
    'rtl/audio_io/four_string_board_audio_chain.v','rtl/control/phase_slide_smoother.v',
    'rtl/control/guitar_play_control.v','rtl/control/guitar_effect_buttons.v',
    'rtl/top/guitar_audio_top.v','rtl/top/neo_guitar_radial_top.v',
    'rtl/config/rock_coeffs.vh','rtl/config/piano_bright_coeffs.vh','rtl/config/guitar_config.vh',
    'constraints/neo_guitar_radial.cst','constraints/neo_guitar_radial.sdc']
unchanged += [str(p.relative_to(repo).as_posix()) for p in (repo/'mem').glob('*.mem')]
unchanged += [str(p.relative_to(repo).as_posix()) for p in (repo/'rtl/display').glob('*.v')]
hashes={}
for path in unchanged:
    before=subprocess.run(['git','show',f'{baseline}:{path}'],cwd=repo,check=True,capture_output=True).stdout
    after=(repo/path).read_bytes()
    assert before.replace(b'\r\n',b'\n')==after.replace(b'\r\n',b'\n'),path
    hashes[path]=hashlib.sha256(after).hexdigest()
benches=['tb_piano_voice_core','tb_full_piano_voice','tb_full_piano_budget','tb_rock_voice_core',
         'tb_procedural_piano_ab','tb_procedural_hammer_properties','tb_guitar_open_release',
         'tb_neo_guitar_radial','tb_guitar_radial_fade_integration','tb_guitar_radial_fft',
         'tb_guitar_curve_fade','tb_guitar_visual_tail','tb_guitar_audio_latency',
         'tb_full_realtime_acceptance','tb_piano_stereo_room','tb_piano_stereo_chorus',
         'tb_piano_room_control','tb_rock_dry_sustain','tb_guitar_effect_buttons',
         'tb_pt8211_tx','tb_guitar_pcm_cdc','tb_rock_envelope_lifetime','tb_guitar_radial_renderer']
logs={}
for bench in benches:
    log=(repo/f'sim/temp/{bench}.log').read_text()
    assert 'PASS:' in log and not re.search(r'FAIL:|\*\* (Error|Fatal|Warning):',log),bench
    logs[bench]=re.findall(r'PASS: [^\r\n]+',log)
assert '233 / 256' in '\n'.join(logs['tb_full_piano_budget'])
simulation=json.loads((repo/'sim/temp/procedural_piano/verification.json').read_text(encoding='utf-8-sig'))
assert simulation['result']=='PASS'
assert simulation['hammer_coefficients_sha256']==hashlib.sha256((repo/'rtl/config/piano_hammer_coeffs.vh').read_bytes()).hexdigest()
for path,digest in simulation['source_sha256'].items():
    assert hashlib.sha256((repo/path).read_bytes()).hexdigest()==digest,path
for entry in simulation['test_results_sha256']:
    assert hashlib.sha256((repo/f"sim/temp/{entry['bench']}.log").read_bytes()).hexdigest()==entry['sha256'],entry['bench']
gate_dir=repo/'sim/temp/guitar_procedural_gate_place4'
gate=(gate_dir/'run.log').read_text()
assert not re.search(r'FAIL:|MISMATCH|\*\* (Error|Fatal)',gate)
warning=r'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)'
for line in gate.splitlines():
    if line.startswith('# ** Warning:'):assert re.search(warning,line),line
netlist=implementation/f'gwsynthesis/{name}.vg'
evidence=json.loads((gate_dir/'verification.json').read_text(encoding='utf-8-sig'))
assert evidence['result']=='PASS' and evidence['netlist_sha256']==hashlib.sha256(netlist.read_bytes()).hexdigest()
for artifact in [pnr/f'{name}.fs',pnr/f'{name}.rpt.txt',pnr/f'{name}_tr_content.html']:
    assert artifact.stat().st_mtime>=netlist.stat().st_mtime,('stale build artifact',artifact)
dac=re.search(r'PASS: (\d+) actual DAC frames bit-identical',gate)
lcd=re.search(r'PASS: synthesized LCD (\d+) board clocks, (\d+) visible pixels EXACTLY match',gate)
assert dac and int(dac[1])>=6500 and lcd and int(lcd[2])>900000
listening=json.loads((repo/'build/procedural_piano/listening_evidence.json').read_text())
assert listening['actual_rtl_frames_per_version']==136000
assert all(abs(x['mean_rms_db_change'])<.03 for x in listening['attack_statistics'])
for path,digest in listening['input_pcm_sha256'].items():
    assert hashlib.sha256((repo/path).read_bytes()).hexdigest()==digest,path
for path,digest in listening['wav_sha256'].items():
    assert hashlib.sha256((repo/'build/procedural_piano'/path).read_bytes()).hexdigest()==digest,path
fs=pnr/f'{name}.fs'
changed=[repo/'rtl/synth/piano_voice_core.v',repo/'rtl/synth/piano_hammer_model.v',
         repo/'rtl/config/piano_hammer_coeffs.vh',repo/'rtl/audio_io/four_voice_piano_audio_core.v',
         repo/'mem/piano_hammer_model.json',project/'build.tcl',project/f'{name}.gprj']
result=dict(branch='experiment/procedural-piano-hammer',baseline_commit=baseline,
    device='GW5AT-LV60PG484AC1/I0',device_version='B',pins_checked=len(pins),
    clocks=clocks,violations=violations,resources=resources,
    audio=dict(voices=4,modes_per_voice=32,sample_rate_hz=48000,synthesis_cycles=233,budget_cycles=256),
    hammer=dict(recorded_pcm_in_production=False,ram_saved_blocks=118-resources['BSRAM']['used'],
        additional_model_bsrams=0,additional_model_dsps=0,shared_modal_dsp=True,
        duration_ms=2048/48,peak_bound_pcm16=2048,per_voice_independent_noise=True),
    test_results=logs,final_simulation_evidence=simulation,
    unchanged_stage_test_evidence_note='Display/control/FX tests retained from the initial procedural implementation; their sources and all ROMs match fb574a4. Final hash-bound core/A-B and full gate checks cover the final hammer parameters.',
    synthesized_dac_frames_exact=int(dac[1]),synthesized_lcd_pixels_exact=int(lcd[2]),
    netlist_sha256=evidence['netlist_sha256'],unchanged_sources_sha256=hashes,
    implementation_root=str(implementation),
    ide_configuration=dict(place=4,route=2,clock_route_order=1,correct_hold=True,
        sha256=hashlib.sha256(ide_path.read_bytes()).hexdigest()),
    implementation_reports_sha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in
        [pnr/f'{name}.rpt.txt',pnr/f'{name}_tr_content.html',args.build_log]},
    changed_sources_sha256={str(p.relative_to(repo)):hashlib.sha256(p.read_bytes()).hexdigest() for p in changed},
    bitstream_bytes=fs.stat().st_size,bitstream_sha256=hashlib.sha256(fs.read_bytes()).hexdigest(),
    listening=listening,hardware_status='Experimental procedural attack awaits user listening and physical acceptance',
    contest_scope='Recorded-PCM playback removed from this production path; interpretation based on provided guide pages 13-14, not a certification of every contest requirement')
(project/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:result[k] for k in ['clocks','violations','resources','hammer','bitstream_sha256']},indent=2))
