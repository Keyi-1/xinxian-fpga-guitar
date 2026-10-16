"""Certify this supplied-score build without changing historical P1/P2 checks.

Only the reviewed range wiring, generated music/messages and slot-3 UI changes
may differ from the board-confirmed fragment release. Every receipt below must
bind the current sources and the actual original-project netlist/implementation.
"""
from pathlib import Path
import argparse
from datetime import datetime
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT/'gowin/neo_guitar_touch_game'
NAME = 'neo_guitar_touch_game'
BASE = '5b13b5d536bc8ddf40659a5444b92746560cdc21'
FROZEN_AUDIO = '655458f32ba4f7e06403fd6c5c4da0b6f0dad8a7'
CORE = ['tb_game_p2_window', 'tb_game_p2_legacy_equivalence',
        'tb_game_p2_static_bank', 'tb_game_p2_judgement', 'tb_game_p2_user_melody']
INTEGRATION = ['tb_game_p2_connection', 'tb_game_p2_display',
               'tb_game_p2_audio_preservation', 'tb_game_extended_audio']
LEGACY = ['tb_i2c_fault_recovery', 'tb_gt911_touch', 'tb_touch_gesture_ui',
          'tb_game_note_controller', 'tb_game_cdc', 'tb_game_chart_renderer',
          'tb_game_audio_preservation', 'tb_game_miss_audio_cue',
          'tb_game_competition_controls', 'tb_guitar_effect_buttons',
          'tb_guitar_effect_buttons_defaults']
VENDOR_WARNING = re.compile(r'prim_sim\.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)')


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
    return Path(path).read_text(encoding='utf-8-sig')


def load(path):
    return json.loads(read(path))


def relative(path):
    return Path(path).relative_to(ROOT).as_posix()


def old(path):
    return subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT).decode('utf-8').replace('\r\n', '\n')


def replace_once(text, before, after):
    assert text.count(before) == 1, ('inspect exact source exception', before)
    return text.replace(before, after)


def range_transform(path, text):
    """Exact finite exceptions, independently exercised by 27/32-bit tests."""
    if path == 'rtl/audio_io/four_string_board_audio_chain.v':
        text = replace_once(text, '    parameter integer SLIDE_SAMPLES = `SLIDE_SAMPLES,\n',
            '    parameter integer SLIDE_SAMPLES = `SLIDE_SAMPLES,\n'
            '    parameter integer CONTROL_PHASE_VALUE_BITS = `NOTE_PHASE_VALUE_BITS,\n')
        return replace_once(text, '.PHASE_VALUE_BITS(`NOTE_PHASE_VALUE_BITS)',
                             '.PHASE_VALUE_BITS(CONTROL_PHASE_VALUE_BITS)')
    if path == 'rtl/game/guitar_touch_game_audio.v':
        return replace_once(text, '        .PIANO_MODES(32),',
            '        .CONTROL_PHASE_VALUE_BITS(USE_P2 ? 27 : `NOTE_PHASE_VALUE_BITS),\n        .PIANO_MODES(32),')
    if path == 'rtl/game/game_p2_window_controller.v':
        for before, after in [
            ('    reg [25:0] best_phase[0:3],next_phase[0:3];',
             '    // The fretless game accepts D3..G5. The performance fret ROM is unchanged.\n'
             '    reg [26:0] best_phase[0:3],next_phase[0:3];'),
            ('midi>72', 'midi>79'), ('function [25:0] midi_phase;', 'function [26:0] midi_phase;'),
            ("{6'd0,best_phase[i]}", "{5'd0,best_phase[i]}"),
            ("{6'd0,next_phase[i]}", "{5'd0,next_phase[i]}")]:
            text = replace_once(text, before, after)
        return text
    raise AssertionError(('not a permitted range module', path))


def source_guards():
    from generate_p2_static_scores import build
    from generate_game_p2_bsram import build as pack
    from qing_ge_user_score import compile_score
    from check_game_p2_font import check as check_font
    outputs, catalog = build()
    for path, value in outputs.items():
        assert (ROOT/path).read_bytes() == value, ('stale generated data', path)
    assert (ROOT/'rtl/config/game_p2_bsram_init.vh').read_bytes() == pack()
    events, duration, report = compile_score()
    assert (len(events), duration, report['measures'], report['output_midi_range']) == (212, 7296000, 38, [50, 79])
    assert report['tie_continuations'] == 30 and report['rest_tokens'] == 13
    assert catalog['total_events'] == 959 and catalog['capacity'] == 2048
    assert catalog['slots'][3]['timbre'] == 1 and catalog['slots'][4]['offset'] == 703
    source = load(ROOT/'scores/p2/source/qing_ge_user_melody.json')
    assert source['adaptation_authorization'] == '2026-10-16 user: preserve every interval; lower one octave and extend game range D3-G5, performance unchanged'
    for alias in ['jasmine', 'slow_arpeggio', 'seven_nation_riff', 'time_10min']:
        for suffix in ['csv', 'bin']:
            path = f'scores/p2/{alias}.{suffix}'
            assert (ROOT/path).read_bytes() == subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT)
    # Preserve the entire accepted font. Only append messages using its glyphs.
    meta = load(ROOT/'scores/game_font.json'); previous = json.loads(old('scores/game_font.json'))
    assert meta['characters'] == previous['characters'] and meta['stage_title'] == previous['stage_title']
    assert meta['messages'] == previous['messages'] + ['情歌旋律', 'MELODY']
    chars = meta['characters']; messages = meta['messages']
    header = ['// Generated fixed UI messages; not a complete Chinese font.',
              f'`define GAME_DIGIT_BASE {chars.index("0")}',
              f'`define GAME_TITLE_TILE_BASE {len(chars)}',
              'function [6:0] game_message_glyph;',
              '    input [5:0] message_id; input [4:0] character_index;',
              '    begin', '        case({message_id,character_index})']
    indices = [chars.index(' ')]*2048
    for i, message in enumerate(messages):
        for j, char in enumerate(message):
            indices[i*32+j] = chars.index(char)
            header.append(f"            11'd{i*32+j}:game_message_glyph=7'd{chars.index(char)};")
    header += [f"            default:game_message_glyph=7'd{chars.index(' ')};", '        endcase', '    end', 'endfunction', '']
    assert read(ROOT/'rtl/config/game_ui_messages.vh') == '\n'.join(header)
    assert read(ROOT/'mem/game_message_index.mem') == ''.join(f'{v:02x}\n' for v in indices)
    generated = {p for p in outputs if p.startswith(('rtl/', 'mem/'))} | {
        'rtl/config/game_p2_bsram_init.vh', 'rtl/config/game_ui_messages.vh', 'mem/game_message_index.mem'}
    exceptions = {'rtl/audio_io/four_string_board_audio_chain.v', 'rtl/game/guitar_touch_game_audio.v',
                  'rtl/game/game_p2_window_controller.v', 'rtl/game/touch_game_renderer.v'}
    before_paths = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASE], cwd=ROOT, text=True).splitlines()
    preserved = {}
    for path in before_paths:
        if not path.startswith(('rtl/', 'mem/', 'constraints/')) or path in generated:
            continue
        expected = old(path)
        if path in exceptions - {'rtl/game/touch_game_renderer.v'}:
            expected = range_transform(path, expected)
        elif path == 'rtl/game/touch_game_renderer.v':
            expected = replace_once(expected, '    `include "../config/game_score_config.vh"\n',
                '    `include "../config/game_score_config.vh"\n    `include "../config/game_p2_progress.vh"\n')
            before = ('    // Constants mirror the immutable catalog durations: ceil(samples/480).\n'
                '    // Verified against every catalog entry by the integrated display bench.\n'
                "    wire [31:0] progress_step=USE_P2 ? (active_slot==1 ? 32'd25600 : active_slot==2 ? 32'd19200 :\n"
                "        active_slot==3 ? 32'd12800 : active_slot==4 ? 32'd60000 : 32'd3375) : PROGRESS_STEP;")
            expected = replace_once(expected, before,
                '    // Generated from the immutable catalogue; no independently maintained times.\n'
                '    wire [31:0] progress_step=USE_P2 ? game_p2_progress_step(active_slot) : PROGRESS_STEP;')
            expected = replace_once(expected, '3:label(44,ox,oy,4,scale,0);', '3:label(56,ox,oy,4,scale,0);')
            expected = replace_once(expected, 'active_slot==2 ? 50 : 49,', 'active_slot==2 ? 50 : 57,')
        assert read(ROOT/path) == expected, ('unapproved runtime/source change', path)
        if path not in exceptions:
            preserved[path] = digest(ROOT/path)
    actual = {relative(p) for base in ['rtl', 'mem', 'constraints'] for p in (ROOT/base).rglob('*') if p.is_file()}
    assert actual <= set(before_paths) | generated, ('unexpected runtime files', actual-set(before_paths)-generated)
    gprj = f'gowin/neo_guitar_touch_game/{NAME}.gprj'
    expected = replace_once(old(gprj), '        <File path="../../rtl/config/game_p2_catalog.vh" type="file.other" enable="1" />\n',
        '        <File path="../../rtl/config/game_p2_catalog.vh" type="file.other" enable="1" />\n'
        '        <File path="../../rtl/config/game_p2_progress.vh" type="file.other" enable="1" />\n')
    assert read(ROOT/gprj) == expected
    return preserved, report, check_font()


def source_hashes(data):
    for path, value in data['source_sha256'].items():
        assert digest(ROOT/path) == value, ('source changed since proof', path)


def clean_log(path, vendor=False, success=True):
    text = read(path)
    assert not re.search(r'FAIL:|\*\* (Error|Fatal):', text), path
    for line in text.splitlines():
        if re.search(r'\*\* Warning:', line):
            assert vendor and VENDOR_WARNING.search(line), (path, line)
    if success:
        assert 'PASS:' in text, path
    return text


def rtl_proof(directory, benches, evidence_files):
    p = directory/'verification.json'; data = load(p)
    assert data.get('result', data.get('status')) == 'PASS' and data['benches'] == benches
    source_hashes(data); evidence_files.add(p)
    normalized = {v.replace('\\', '/') for v in data['source_sha256']}
    for bench in benches:
        assert f'sim/tb/{bench}.sv' in normalized, ('missing bench binding', bench)
        log = directory/f'{bench}.log'
        assert digest(log) == data['log_sha256'][bench]
        clean_log(log); evidence_files.add(log)
    compile_log = directory/'compile.log'
    clean_log(compile_log, success=False)
    assert 'Errors: 0, Warnings: 0' in read(compile_log)
    evidence_files.add(compile_log)
    for name, field in [('compile.log', 'compile_log_sha256'), ('python.log', 'python_log_sha256')]:
        if field in data:
            assert digest(directory/name) == data[field]; evidence_files.add(directory/name)
    return data


def require_terms(path, terms):
    text = read(path)
    for term in terms:
        assert term in text, (path, term)


def python_log(path, count):
    text = read(path)
    assert f'Ran {count} tests' in text and re.search(r'^OK\s*$', text, re.M), path
    assert not re.search(r'^FAILED|^ERROR:|^FAIL:', text, re.M), path


def gate_proof(directory, names, netlist_hash, evidence_files):
    p = directory/'verification.json'; data = load(p)
    assert data['result'] == 'PASS' and set(data['log_sha256']) == {f'{x}.log' for x in names}
    source_hashes(data)
    assert data['netlist_sha256'] == digest(directory/'compiled.vg') == netlist_hash
    evidence_files.add(p)
    for name, value in data['log_sha256'].items():
        log = directory/name
        assert digest(log) == value
        clean_log(log, vendor=True); evidence_files.add(log)
    for name, value in data['generated_sha256'].items():
        assert digest(directory/name) == value; evidence_files.add(directory/name)
    for path in directory.glob('*compile.log'):
        clean_log(path, success=False)
        assert 'Errors: 0, Warnings: 0' in read(path)
        evidence_files.add(path)
    if 'engine_origin_evidence_sha256' in data:
        origin = directory/'engine_origin.json'
        assert digest(origin) == data['engine_origin_evidence_sha256']
        o = load(origin); source_hashes(o)
        assert o['netlist_sha256'] == netlist_hash
        evidence_files.add(origin)
    for name, field in [('compile.log', 'compile_log_sha256'), ('mapping.log', 'mapping_log_sha256')]:
        if field in data:
            assert digest(directory/name) == data[field]; evidence_files.add(directory/name)
    return data


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--build-dir', type=Path, required=True)
    p.add_argument('--gate-dir', type=Path, required=True)
    p.add_argument('--extra-gate-dir', type=Path, required=True)
    p.add_argument('--seek-gate-dir', type=Path, required=True)
    p.add_argument('--source-rtl-only', action='store_true', help='No release certificate is written')
    p.add_argument('--output', type=Path, default=PROJECT/'p2_qing_ge_melody_verification.json')
    a = p.parse_args()
    b, g, x = (v.resolve() for v in [a.build_dir, a.gate_dir, a.extra_gate_dir])
    seek_dir = a.seek_gate_dir.resolve()
    m = load(b/'source_manifest.json'); source_hashes(m)
    previous_cert = PROJECT/'p2_integration_verification.json'
    assert read(previous_cert) == old(relative(previous_cert)), 'Historical P2 certificate changed'
    prior = load(previous_cert)
    assert digest(ROOT/'build/releases/touch_game/neo_guitar_touch_game_p2_static_songs.fs') == prior['bitstream_sha256']
    assert digest(ROOT/'build/releases/touch_game/neo_guitar_touch_game_p1_display_opt.fs') == 'e8ddbbc64dc81cf61c3037039b54752bf3a21ecca155264bfe6db907f9354c86'
    preserved, transcription, font = source_guards()
    proof_files = set()
    core = ROOT/m['core_evidence']; integration = ROOT/m['rtl_evidence']
    rtl_proof(core, CORE, proof_files)
    audio = rtl_proof(integration, INTEGRATION, proof_files)
    assert audio['baseline_commit'] == FROZEN_AUDIO
    rtl_proof(ROOT/'sim/temp/qing_ge_legacy_rtl', LEGACY, proof_files)
    python_log(core/'python.log', 5)
    fingering_log = ROOT/'sim/temp/qing_ge_legacy_rtl/fingering.log'
    python_log(fingering_log, 5); proof_files.add(fingering_log)
    require_terms(core/'tb_game_p2_user_melody.log', ['all 212 melody launches/27-bit phases', '212 Perfect hits', 'all MIDI50..79 exact DDS', '<=65 reads/131 busy clocks per256'])
    require_terms(integration/'tb_game_p2_audio_preservation.log', ['2097153 cycles / 8192 samples identical', 'sustain exit 1452 samples'])
    require_terms(integration/'tb_game_extended_audio.log', ['2312435 clocks/9032 samples', 'three timbres/all FX', 'G5 held bit26', 'zero deadlines'])
    require_terms(integration/'tb_game_p2_display.log', ['2888 complete P2 layouts', '445 clocks < 38226 blank clocks'])
    # This frozen proof covers ONLY the previous valid MIDI50..72 domain.
    domain = ROOT/m['legacy_domain_evidence']; d = load(domain/'verification.json')
    assert d['result'] == 'PASS' and d['reference_commit'] == 'a6009a3596d812402c06e7a2fadf8c6b881faae5'
    source_hashes(d)
    for name, field in [('compile.log', 'compile_log_sha256'), ('equivalence.log', 'log_sha256')]:
        assert digest(domain/name) == d[field]; clean_log(domain/name, success=name != 'compile.log')
        proof_files.add(domain/name)
    proof_files.add(domain/'verification.json')
    require_terms(domain/'equivalence.log', ['821642 clocks', '2753 snapshots', '2048 events/32 wraps', 'max busy 131'])
    python_dir = b/'python'
    py = load(python_dir/'verification.json'); assert py['result'] == 'PASS'; source_hashes(py)
    assert set(py['logs_sha256']) == {'test_qing_ge_user_score.log', 'test_import_p2_melody_midi.log'}
    python_log(python_dir/'test_qing_ge_user_score.log', 4)
    python_log(python_dir/'test_import_p2_melody_midi.log', 10)
    for name, value in py['logs_sha256'].items():
        assert digest(python_dir/name) == value
        proof_files.add(python_dir/name)
    proof_files.add(python_dir/'verification.json')
    protected = b/'protected_user_files.json'
    assert digest(protected) == m['protected_user_files_sha256']
    for path, rec in load(protected).items():
        assert digest(ROOT/path) == rec['sha256'], ('protected user bytes changed', path)
        assert subprocess.check_output(['git', 'ls-files', '-s', '--', path], cwd=ROOT, text=True).strip() == rec['index_line']
    vg = PROJECT/f'impl/gwsynthesis/{NAME}.vg'
    review = load(b/'synthesis_review.json')
    assert review['result'] == 'PASS' and review['source_manifest_sha256'] == digest(b/'source_manifest.json')
    assert digest(vg) == digest(b/f'{NAME}.vg') == review['netlist_sha256']
    syn = PROJECT/f'impl/gwsynthesis/{NAME}.log'
    assert 'GowinSynthesis finish' in read(syn)
    assert not re.search(r'inferr?ed.*latch|latch.*inferr?ed', read(syn), re.I)
    assert not re.search(r'^\s*(?:DLCE|DLPE)\s+\w+\s*\(', read(vg), re.M)
    if a.source_rtl_only:
        print('SOURCE_RTL_PASS_IMPLEMENTATION_PENDING: no release certificate written')
        return
    standard = gate_proof(g, ['tb_game_p2_engine_gate', 'tb_game_p2_layout_gate', 'tb_game_p2_top_gate'], digest(vg), proof_files)
    extra = gate_proof(x, ['tb_game_p2_actual_bank_gate', 'tb_game_p2_range_gate'], digest(vg), proof_files)
    seek = gate_proof(seek_dir, ['tb_game_p2_melody_seek_gate'], digest(vg), proof_files)
    assert digest(Path(standard['vendor_primitive_path'])) == standard['vendor_primitive_sha256']
    require_terms(g/'tb_game_p2_layout_gate.log', ['2117'])
    require_terms(g/'tb_game_p2_top_gate.log', ['1305600'])
    require_terms(x/'tb_game_p2_actual_bank_gate.log', ['4096 exact asynchronous reads', 'all2048 records/96bits', 'G5 MIDI79'])
    require_terms(x/'tb_game_p2_range_gate.log', ['G5 bit26 held', 'bidirectional slides', 'sustained exit'])
    require_terms(seek_dir/'tb_game_p2_melody_seek_gate.log', ['212 real-ROM attacks/precise DDS including G5 bit26', 'seek at proven elapsed DFF Q only'])
    from generate_game_p2_extra_gate import generate
    import tempfile
    with tempfile.TemporaryDirectory(dir=b) as temp:
        generate(vg, Path(temp))
        for name in ['bank_actual_map.vh', 'range_actual_force.vh', 'range_actual_observe.vh']:
            assert (Path(temp)/name).read_bytes() == (x/name).read_bytes()
        from generate_game_p2_seek_gate import generate as generate_seek
        generate_seek(vg, Path(temp))
        assert (Path(temp)/'seek_actual_map.vh').read_bytes() == (seek_dir/'seek_actual_map.vh').read_bytes()
    pnr = PROJECT/'impl/pnr'; log = read(pnr/f'{NAME}.log'); report = read(pnr/f'{NAME}.rpt.txt')
    timing = read(pnr/f'{NAME}_tr_content.html')
    assert 'Bitstream generation completed' in log and 'ERROR' not in log
    assert 'PNR_TCL_FINISHED' in read(b/'build.stdout.log') and not read(b/'build.stderr.log').strip()
    assert 'GW5AT-LV60PG484AC1/I0' in report and 'Device Version>: B' in report
    assert not re.search(r'\bPR0004\b|\b[1-9]\d*\s+(?:unrouted|unroute|unconnected)\b', log, re.I)
    resources = {}
    for name in ['Logic', 'Register', 'CLS', 'BSRAM', 'DSP']:
        hit = re.search(rf'^\s+{name}\s+\|\s+([\d.]+)/([\d.]+)', report, re.M)
        assert hit and float(hit[1]) <= float(hit[2]), name
        resources[name] = dict(used=float(hit[1]), available=float(hit[2]))
    assert resources['DSP']['used'] == 115.5
    tree = ET.fromstring(read(PROJECT/f'impl/gwsynthesis/{NAME}_syn_rsc.xml'))
    banks = [n for n in tree.iter('SubModule') if n.attrib.get('name') == 'bank' and n.attrib.get('Bsram') == '10']
    assert len(banks) == 1, 'Actual score bank must map to ten DPB16 blocks; zero group slice swept'
    clocks = {}
    for clock, required in [('audio_clk_12m288', 12.288), ('sys_clk_50m', 50.0)]:
        hit = re.search(rf'<td>{clock}</td>\s*<td>([\d.]+)\(MHz\)</td>\s*<td>([\d.]+)\(MHz\)</td>', timing)
        assert hit and float(hit[1]) == required and float(hit[2]) >= required, clock
        clocks[clock] = dict(required_mhz=required, fmax_mhz=float(hit[2]))
    for kind in ['Setup', 'Hold']:
        hit = re.search(rf'Numbers of {kind} Violated Endpoints</td>\s*<td>(\d+)</td>', timing)
        assert hit and int(hit[1]) == 0, kind
    cmd = read(pnr/'cmd.do')
    hit = re.search(r'^-d\s+(.+)$', cmd, re.M)
    assert hit and Path(hit[1].strip()).resolve() == vg.resolve()
    for key, value in [('place_option', 4), ('route_option', 2), ('route_maxfan', 32), ('clock_route_order', 0), ('correct_hold', 1)]:
        assert re.search(rf'^-{key}\s+{value}\s*$', cmd, re.M), key
    pins = dict(re.findall(r'IO_LOC\s+"([^"]+)"\s+(\w+);', read(ROOT/f'constraints/{NAME}.cst')))
    assert len(pins) == len(set(pins.values())) == 59
    rows = {}
    for line in report.splitlines():
        fields = [v.strip() for v in line.split('|')]
        if len(fields) > 8 and fields[0] in pins:
            rows[fields[0]] = fields
    for port, ball in pins.items():
        assert rows[port][2].split('/')[0] == ball and rows[port][3] == 'Y'
        assert rows[port][7] == ('LVCMOS15' if port.startswith('USER_BUTTON') else 'LVCMOS33')
    fs = pnr/f'{NAME}.fs'; assert fs.stat().st_size > 10000000
    started = datetime.fromisoformat(load(b/'build_process.json')['started']).timestamp()
    artifacts = {vg, fs, syn, PROJECT/f'impl/gwsynthesis/{NAME}_syn_rsc.xml',
        b/'source_manifest.json', b/'build_process.json', b/'synthesis_review.json', protected,
        b/'process_config.json', b/'build.stdout.log', b/'build.stderr.log',
        *[pnr/f'{NAME}{suffix}' for suffix in ['.log', '.rpt.txt', '_tr_content.html']],
        pnr/'cmd.do', pnr/'device.cfg', previous_cert}
    for path in [vg, fs, syn, pnr/f'{NAME}.log', pnr/f'{NAME}.rpt.txt', pnr/f'{NAME}_tr_content.html', pnr/'cmd.do']:
        assert path.stat().st_mtime >= started, ('old build result', path)
    margins = resources['CLS']['used']/resources['CLS']['available'] <= .95 and clocks['sys_clk_50m']['fmax_mhz'] >= 55 and clocks['audio_clk_12m288']['fmax_mhz'] >= 13.5
    tools = [Path(__file__), ROOT/'tools/archive_qing_ge_melody.py']
    certificate = dict(result='PASS', artifact_scope=dict(kind='original_gprj_qing_ge_user_melody',
        project=relative(PROJECT/f'{NAME}.gprj'), implementation=relative(PROJECT/'impl')),
        validated_source_commit=m['validated_source_commit'], previous_release_commit=BASE,
        source_sha256=m['source_sha256'], preserved_assets_sha256=preserved,
        verification_tools_sha256={relative(v): digest(v) for v in tools},
        artifacts_sha256={relative(v): digest(v) for v in sorted(artifacts)},
        evidence_sha256={relative(v): digest(v) for v in sorted(proof_files)},
        resources=resources, clocks=clocks, margin_targets_met=margins,
        previous_release_resources=prior['resources'], previous_release_clocks=prior['clocks'],
        bitstream_sha256=digest(fs), netlist_sha256=digest(vg),
        violations=dict(setup=0, hold=0, latch=0, unrouted=0, score_deadline=0, layout_deadline=0, audio_deadline=0),
        score_bank=dict(logical_records=2048, record_bits=96, actual_dpb16_blocks=10, all_reads=4096),
        transcription=transcription, font_preservation=font,
        audio_baseline=FROZEN_AUDIO, audio_equivalent_samples=8192, reference_clocks=2097153,
        sustained_exit_samples=1452, extended_audio_oracle_samples=9032,
        rtl_layouts=2888, gate_layouts=2117, gate_effective_pixels=1305600,
        source_guard='Exact finite range/UI transforms against board-confirmed fragment release; all remaining runtime assets unchanged',
        legacy_equivalence_scope='Prior valid MIDI50..72 domain only; MIDI73..79 is intentional new behavior',
        standard_gate=standard, extra_gate=extra, seek_gate=seek,
        training_defaults=dict(ALLOW_AUTOPLAY_PREVIEW=1, ENABLE_MISS_CUE=1),
        hardware_status='Prior P1 and P2 fragments user-confirmed; this 38-bar melody and accepted bar10/18 rhythm revisions await listening/on-board confirmation',
        excluded_validation=['New hardware/analog measurements', 'Original-recording completeness', 'Accompaniment staff', 'Wall-clock full-song hardware endurance'],
        generated_at=datetime.now().astimezone().isoformat())
    a.output.write_text(json.dumps(certificate, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k: certificate[k] for k in ['result', 'resources', 'clocks', 'bitstream_sha256', 'margin_targets_met']}, indent=2))


if __name__ == '__main__':
    main()
