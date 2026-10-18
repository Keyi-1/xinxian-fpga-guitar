"""Bind P3 evidence to this original-project build; historical checks stay intact."""
from pathlib import Path
from datetime import datetime
import argparse
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT/'gowin/neo_guitar_touch_game'
NAME = 'neo_guitar_touch_game'
BASE = 'cc8dbb7bd0d14be19c136d68f8d16679e823c0e9'
RUN = ROOT/'build/p3_import/impl_c7_shared_state'
VENDOR = re.compile(r'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)')
ALLOWED = {'rtl/game/'+s+'.v' for s in ['game_p2_chart_layout', 'game_p2_mode_router',
    'game_p2_static_engine', 'guitar_touch_game_audio', 'guitar_touch_game_display',
    'touch_game_renderer', 'touch_game_ui']}
ALLOWED |= {'rtl/top/neo_guitar_touch_game_top.v', 'rtl/config/game_ui_messages.vh',
    'mem/game_message_index.mem', 'constraints/'+NAME+'.cst',
    'gowin/neo_guitar_touch_game/'+NAME+'.gprj', 'rtl/synth/piano_voice_core.v'}
NEW = {'rtl/game/game_p3_'+s+'.v' for s in ['catalog', 'catalog_cdc', 'default_catalog',
    'import', 'protocol', 'score_bank', 'service', 'uart']}
NEW |= {'rtl/config/game_p3_bsram_init.vh', 'mem/game_p3_initial.mem',
        'rtl/config/piano_rock_gain_init.vh', 'rtl/synth/piano_rock_gain_rom.v', 'rtl/synth/piano_mode_state_ram.v'}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return Path(path).read_text(encoding='utf-8-sig')


def load(path):
    return json.loads(read(path))


def rel(path):
    return Path(path).relative_to(ROOT).as_posix()


def old(path):
    return subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT).replace(b'\r\n', b'\n')


def hashes_current(values):
    for path, value in values.items():
        assert digest(ROOT/path) == value, ('changed verified file', path)


def source_guard():
    from generate_game_p3_bsram import writable, initial_bank
    manifest = {k.replace('\\', '/'): v for k, v in load(RUN/'source_manifest.json').items()}
    hashes_current(manifest)
    changed = set()
    for path in manifest:
        if path in NEW:
            continue
        if (ROOT/path).read_bytes().replace(b'\r\n', b'\n') != old(path):
            changed.add(path)
    assert changed == ALLOWED, ('review exact P3 source boundary', changed ^ ALLOWED)
    assert NEW <= manifest.keys()
    original_voice = old('rtl/synth/piano_voice_core.v').decode()
    expected_voice = original_voice.replace('    reg [27:0] rock_amplitude_product;',
        '    reg [27:0] rock_amplitude_product;\n    wire [15:0] rock_gain_read;')
    assert expected_voice != original_voice
    anchor="    wire [4:0] local_mode = harmony_mode ? mode_index-5'd16 : mode_index;"
    expected_voice = expected_voice.replace(anchor, anchor+'''
    generate if(ROCK_ENABLE!=0)begin:rock_gain_storage
        piano_rock_gain_rom gain(.clk(clk),.read_enable(state==LOAD),
            .address({profile,local_mode}),.data(rock_gain_read));
    end else begin:no_rock_gain_storage
        assign rock_gain_read=16'd0;
    end endgenerate''')
    expected_voice = expected_voice.replace('rock_env_product[16:5]*rock_gain_for(profile,local_mode)',
        'rock_env_product[16:5]*rock_gain_read')
    spec=load(ROOT/'sim/reference/game_p3/piano_shared_state_edit_spec.json')
    assert spec['base_commit']=='9ace08c' and len(spec['changes'])==10
    assert hashlib.sha256(expected_voice.encode()).hexdigest()==spec['base_normalized_sha256']
    lines=expected_voice.splitlines(keepends=True)
    for edit in reversed(spec['changes']):
        assert ''.join(lines[edit['start']:edit['end']])==edit['before']
        lines[edit['start']:edit['end']]=edit['after'].splitlines(keepends=True)
    expected_voice=''.join(lines)
    assert hashlib.sha256(expected_voice.encode()).hexdigest()==spec['candidate_normalized_sha256']
    assert read(ROOT/'rtl/synth/piano_voice_core.v') == expected_voice, 'Only sealed independently verified gain/mode RAM edits may change in audio'
    frozen_voice = read(ROOT/'sim/reference/game_p3/piano_voice_core_before_p3_rom.v')
    assert frozen_voice == original_voice.replace('module piano_voice_core #(', 'module accepted_p3_source_voice #(')
    from generate_piano_rock_gain_rom import build as gain_rom
    assert (ROOT/'rtl/config/piano_rock_gain_init.vh').read_bytes() == gain_rom()
    # Freeze every allowed change to the reviewed synthesis snapshot, rather
    # than treating a module name as permission for arbitrary future edits.
    for path in ALLOWED | NEW:
        assert digest(RUN/'source_archive'/path) == manifest[path]
    protected = load(RUN/'protected_user_files.json')
    for path, record in protected.items():
        assert digest(ROOT/path) == record['sha256'], ('protected bytes', path)
        index = subprocess.check_output(['git', 'ls-files', '--stage', '--', path], cwd=ROOT, text=True).strip()
        assert index == record['index'], ('protected index', path)
    cst = read(ROOT/'constraints'/f'{NAME}.cst')
    assert cst.startswith(old(f'constraints/{NAME}.cst').decode())
    additions = cst[len(old(f'constraints/{NAME}.cst').decode()):]
    assert dict(re.findall(r'IO_LOC "([^"]+)" (\w+);', additions)) == {'song_uart_tx': 'U15', 'song_uart_rx': 'V14'}
    assert len(re.findall(r'^IO_PORT ', additions, re.M)) == 2
    for node in ['Device', 'Template', 'Version']:
        previous = ET.fromstring(old(f'gowin/{NAME}/{NAME}.gprj')).find(node)
        current = ET.parse(PROJECT/f'{NAME}.gprj').find(node)
        assert current.text == previous.text and current.attrib == previous.attrib
    previous = ET.fromstring(old(f'gowin/{NAME}/{NAME}.gprj')).find('FileList')
    current = ET.parse(PROJECT/f'{NAME}.gprj').find('FileList')
    before = {tuple(sorted(n.attrib.items())) for n in previous}
    after = {tuple(sorted(n.attrib.items())) for n in current}
    assert before <= after and len(after-before) == 13
    font = load(ROOT/'scores/game_font.json')
    frozen = json.loads(old('scores/game_font.json'))
    assert font['characters'] == frozen['characters'] and font['stage_title'] == frozen['stage_title']
    assert font['messages'] == frozen['messages'] + [f'USER {i}' for i in range(1, 6)] + ['RAM']
    indices = [int(x, 16) for x in read(ROOT/'mem/game_message_index.mem').split()]
    expected = [font['characters'].index(' ')]*2048
    for i, message in enumerate(font['messages']):
        for j, char in enumerate(message):
            expected[i*32+j] = font['characters'].index(char)
    assert indices == expected
    assert (ROOT/'rtl/config/game_p3_bsram_init.vh').read_bytes() == writable()
    assert (ROOT/'mem/game_p3_initial.mem').read_bytes() == initial_bank()[1]
    return manifest


def evidence():
    result = {}
    runs = ['p3_c7_final_rtl_01', 'p3_c7_final_twenty_01', 'p3_c7_mode_ram_proof_01',
            'p3_c7_full_gate_01', 'p3_c7_gain_gate_01', 'p3_c7_mode_gate_01']
    for name in runs:
        folder = ROOT/'sim/temp'/name
        receipt = folder/'verification.json'
        data = load(receipt)
        assert data.get('result', data.get('status')) == 'PASS', name
        hashes_current(data['source_sha256'])
        result[rel(receipt)] = digest(receipt)
        if isinstance(data['log_sha256'], dict):
            logs = {folder/(b+'.log'): h for b, h in data['log_sha256'].items()}
        else:
            bench = 'tb_game_p3_rock_gain_gate' if name == 'p3_c7_gain_gate_01' else 'tb_game_p3_mode_state_gate' if name=='p3_c7_mode_gate_01' else 'tb_game_p3_full_gate'
            logs = {folder/(bench+'.log'): data['log_sha256']}
            assert data['netlist_sha256'] == digest(PROJECT/'impl/gwsynthesis'/f'{NAME}.vg')
            assert digest(folder/'mapping.json') == data['mapping_sha256']
            mapping = load(folder/'mapping.json')
            assert mapping['bank_dpb16'] == 10 and mapping['initial_rows'] == 2048
            assert mapping['gain_rom_entries'] == 128 and mapping['gain_rom_dpb16'] == 1
            assert mapping['mode_state_sdpb_per_voice']==1 and mapping['mode_state_address_words']==64
            assert mapping['netlist_sha256'] == data['netlist_sha256']
        for path, value in logs.items():
            assert digest(path) == value
            body = read(path)
            assert 'PASS:' in body and not re.search(r'FAIL:|\*\* (Error|Fatal):', body)
            for line in body.splitlines():
                if '** Warning:' in line:
                    assert name in ['p3_c7_full_gate_01', 'p3_c7_gain_gate_01', 'p3_c7_mode_gate_01'] and VENDOR.search(line), (path, line)
            result[rel(path)] = value
        for path in folder.glob('*'):
            if path.is_file() and path.suffix in ['.json', '.sv', '.vh', '.log']:
                result[rel(path)] = digest(path)
    pc = ROOT/'build/p3_import/pc_checks_c5/verification.json'
    data = load(pc)
    assert data['result'] == 'PASS'
    hashes_current(data['source_sha256'])
    hashes_current(data['log_sha256'])
    result[rel(pc)] = digest(pc)
    result.update(data['log_sha256'])
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--preflight', action='store_true')
    args = parser.parse_args()
    manifest = source_guard()
    proof = evidence()
    if args.preflight:
        print('PASS: current C7 source/ROM/protected files, sealed audio storage edits/frozen mode proof, 20+6 RTL benches, actual full VG/gain/state memories and unchanged PC evidence; P&R not certified')
        return
    pnr = PROJECT/'impl/pnr'
    log = read(pnr/f'{NAME}.log')
    report = read(pnr/f'{NAME}.rpt.txt')
    timing = read(pnr/f'{NAME}_tr_content.html')
    stdout = read(RUN/'build.stdout.log')
    assert 'Bitstream generation completed' in log and 'ERROR' not in log
    assert 'PNR_TCL_FINISHED' in stdout and not read(RUN/'build.stderr.log').strip()
    assert not re.search(r'\bPR0004\b|\b[1-9]\d*\s+(?:unrouted|unroute|unconnected)\b', log, re.I)
    assert 'GW5AT-LV60PG484AC1/I0' in report and 'Device Version>: B' in report
    syn = PROJECT/'impl/gwsynthesis'/f'{NAME}.log'
    assert not re.search(r'inferr?ed.*latch|latch.*inferr?ed', read(syn), re.I)
    resources = {}
    for name in ['Logic', 'Register', 'CLS', 'BSRAM', 'DSP']:
        hit = re.search(rf'^\s+{name}\s+\|\s+([\d.]+)/([\d.]+)', report, re.M)
        assert hit and float(hit[1]) <= float(hit[2]), name
        resources[name] = dict(used=float(hit[1]), available=float(hit[2]))
    assert resources['DSP']['used'] == 115.5
    tree = ET.parse(PROJECT/'impl/gwsynthesis'/f'{NAME}_syn_rsc.xml')
    assert len([n for n in tree.iter('SubModule') if n.attrib.get('name') == 'bank' and n.attrib.get('Bsram') == '10']) == 1
    assert len([n for n in tree.iter('SubModule') if n.attrib.get('name')=='mode_state' and n.attrib.get('Bsram')=='1'])==4
    clocks = {}
    for name, required in [('audio_clk_12m288', 12.288), ('sys_clk_50m', 50.0)]:
        hit = re.search(rf'<td>{name}</td>\s*<td>([\d.]+)\(MHz\)</td>\s*<td>([\d.]+)\(MHz\)</td>', timing)
        assert hit and float(hit[1]) == required and float(hit[2]) >= required, name
        clocks[name] = dict(required_mhz=required, fmax_mhz=float(hit[2]))
    for kind in ['Setup', 'Hold']:
        hit = re.search(rf'Numbers of {kind} Violated Endpoints</td>\s*<td>(\d+)</td>', timing)
        assert hit and int(hit[1]) == 0, kind
    cmd = read(pnr/'cmd.do')
    hit = re.search(r'^-d\s+(.+)$', cmd, re.M)
    vg = PROJECT/'impl/gwsynthesis'/f'{NAME}.vg'
    assert hit and Path(hit[1].strip()).resolve() == vg.resolve()
    assert digest(vg) == load(RUN/'synthesis_review.json')['netlist_sha256']
    for key, value in [('place_option', 4), ('route_option', 2), ('route_maxfan', 32), ('clock_route_order', 0), ('correct_hold', 1)]:
        assert re.search(rf'^-{key}\s+{value}\s*$', cmd, re.M), key
    pins = dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+);', read(ROOT/f'constraints/{NAME}.cst')))
    assert len(pins) == len(set(pins.values())) == 61
    rows = {}
    for line in report.splitlines():
        fields = [v.strip() for v in line.split('|')]
        if len(fields) > 8 and fields[0] in pins:
            rows[fields[0]] = fields
    for port, ball in pins.items():
        assert rows[port][2].split('/')[0] == ball and rows[port][3] == 'Y'
        assert rows[port][7] == ('LVCMOS15' if port.startswith('USER_BUTTON') else 'LVCMOS33')
    fs = pnr/f'{NAME}.fs'
    assert fs.stat().st_size > 10000000
    started = datetime.fromisoformat(load(RUN/'process.json')['started']).timestamp()
    artifacts = [vg, fs, syn, PROJECT/'impl/gwsynthesis'/f'{NAME}_syn_rsc.xml',
        pnr/f'{NAME}.log', pnr/f'{NAME}.rpt.txt', pnr/f'{NAME}_tr_content.html', pnr/'cmd.do']
    for path in artifacts:
        assert path.stat().st_mtime >= started, ('stale implementation artifact', path)
    artifacts += [RUN/p for p in ['process.json', 'source_manifest.json', 'protected_user_files.json',
        'synthesis_review.json', 'build.tcl', 'build.stdout.log', 'build.stderr.log']]
    config_snapshot = RUN/'protected_process_config.snapshot.json'
    assert digest(config_snapshot) == load(RUN/'protected_user_files.json')['gowin/neo_guitar_touch_game/impl/neo_guitar_touch_game_process_config.json']['sha256']
    artifacts.append(config_snapshot)
    runtime = ROOT/'build/p3_import/pc_checks/runtime_environment.json'
    environment = load(runtime)
    assert environment['physical_port_opened'] is False and environment['system_python_changed'] is False
    wheel = ROOT/'build/p3_import/uploader_wheels/pyserial-3.5-py2.py3-none-any.whl'
    assert environment['wheel_sha256'] == digest(wheel) == 'c4451db6ba391ca6ca299fb3ec7bae67a5c55dde170964c7a14ceefec02f2cf0'
    artifacts += [runtime, wheel]
    artifacts += [ROOT/'build/p3_import/upload_example'/('qing_ge'+suffix) for suffix in ['.bin', '.json', '.mem']]
    prior = load(PROJECT/'p2_qing_ge_melody_verification.json')
    assert digest(ROOT/'build/releases/touch_game/neo_guitar_touch_game_qing_ge_melody.fs') == prior['bitstream_sha256']
    tools = [Path(__file__), ROOT/'tools/archive_game_p3.py', ROOT/'tools/prepare_game_p3_gate.py',
        ROOT/'tools/run_game_p3_checks.ps1', ROOT/'tools/run_game_p3_gate.ps1', ROOT/'tools/start_original_p3_build.ps1',
        ROOT/'tools/run_touch_game_checks.ps1', ROOT/'tools/continue_touch_game_checks.ps1',
        ROOT/'sim/reference/game_p3/piano_shared_state_edit_spec.json']
    gate_body=read(ROOT/'sim/temp/p3_c7_full_gate_01/tb_game_p3_full_gate.log')
    gate_counts=re.search(r'(\d+) audio samples and (\d+) LCD clock samples across (\d+) frames',gate_body)
    assert gate_counts
    record = dict(result='PASS', artifact_scope=dict(kind='original_gprj_p3_uart_writable_bank',
        project=rel(PROJECT/f'{NAME}.gprj'), implementation=rel(PROJECT/'impl')),
        previous_release_commit=BASE, validated_source_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        source_sha256=manifest, source_guard=dict(reviewed_changed_modules=sorted(ALLOWED), new_files=sorted(NEW),
            unchanged='All other RTL, tone parameters, ROM assets, scan timing and SDC equal board-confirmed M2; piano voice gain ROM and mode-state RAM edits are finite/sealed and independently compared to original arrays'),
        artifacts_sha256={rel(p): digest(p) for p in artifacts}, evidence_sha256=proof,
        verification_tools_sha256={rel(p): digest(p) for p in tools},
        resources=resources, clocks=clocks, previous_release_resources=prior['resources'], previous_release_clocks=prior['clocks'],
        margin_targets_met=(resources['CLS']['used']/resources['CLS']['available'] <= .95 and clocks['sys_clk_50m']['fmax_mhz'] >= 55 and clocks['audio_clk_12m288']['fmax_mhz'] >= 13.5),
        bitstream_sha256=digest(fs), netlist_sha256=digest(vg),
        violations=dict(setup=0, hold=0, latch=0, unrouted=0, tested_audio_deadline=0, tested_score_deadline=0, tested_layout_deadline=0),
        bank=dict(total_records=2048, logical_record_bits=96, stored_nonconstant_bits=77,
            reserved_initial_records=703, shared_import_records=1345, actual_dpb16_blocks=10,
            crc_readback='All96 logical bits/group retained exactly; full1345 RTL stress; actual full gate imports four-voice G5/D3/E4/C5 chord with all4 velocity metadata; existing preview fixed2 preserved'),
        audio=dict(frozen_baseline='655458f32ba4f7e06403fd6c5c4da0b6f0dad8a7', samples=8192, reference_clocks=2097153, sustained_exit_samples=1452,
            independent_frozen_voice_samples=45210, velocity_levels=4, timbres=3, pitch_profiles=3, exact_gain_rom_entries=128,
            mode_state_memory='All32 phase/gain state words compared before use to original arrays; frame-mid input changes and warm reset during operation',
            mode_state_unit_read_pairs=352,mode_state_unit_physical_reads=704,mode_state_unit_writes=384),
        display=dict(frozen_m2_effective_pixels=2715456, scenes=22, menu_exception='Removed slow practice row only',
            actual_full_gate_audio_samples=int(gate_counts[1]), actual_full_gate_lcd_clock_samples=int(gate_counts[2]), actual_full_gate_frames=int(gate_counts[3])),
        training_defaults=dict(ALLOW_AUTOPLAY_PREVIEW=1, ENABLE_MISS_CUE=1),
        hardware_status='P3 not board-tested; DEBUG-USB2 wiring checked against official schematics. No COM opened or hardware programmed.',
        excluded_validation=['Physical USB/UART/driver link', 'New acoustic measurements', 'Power/unplug endurance', 'Bluetooth', 'Flash persistence'],
        generated_at=datetime.now().astimezone().isoformat())
    output = PROJECT/'p3_import_verification.json'
    output.write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k: record[k] for k in ['result', 'resources', 'clocks', 'bitstream_sha256', 'margin_targets_met']}, indent=2))


if __name__ == '__main__':
    main()
