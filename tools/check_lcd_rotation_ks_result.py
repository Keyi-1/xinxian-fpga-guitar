"""Certify the original-project KS V2 + LCD180 build against its own evidence.

Previous fixed certificates/releases are read-only. No programming or Git writes.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

from bs4 import BeautifulSoup
from check_ks_result import review_vendor_warnings
from compare_synth_graph import compare

ROOT = Path(__file__).resolve().parents[1]
E = ROOT / 'build/karplus_strong'
F = ROOT / 'build/lcd_rotate_ks'
P = ROOT / 'gowin/neo_guitar_touch_game/impl'
NAME = 'neo_guitar_touch_game'
CHANGED = {'rtl/display/guitar_radial_curve_renderer.v', 'rtl/display/lcd_rgb_scan_480x272.v', 'rtl/game/guitar_touch_game_display.v'}


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def load(p):
    return json.loads(p.read_text(encoding='utf-8-sig'))


def text(p):
    return p.read_text(encoding='utf-8-sig')


def verify():
    state = load(F / 'CURRENT_STATE.json')
    assert state['request'] == '你试着编译布线看看呢，能不能成功布线，生成新的位流'
    baseline = load(F / 'before/baseline.json')
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == baseline['head']
    for p, rec in load(F / 'before/protected.json').items():
        assert sha(ROOT / p) == rec['sha256'], p
        assert subprocess.check_output(['git', 'ls-files', '--stage', '--', p], cwd=ROOT, text=True) == rec['index'], p
    previous = load(F / 'formal_before/ks_fifth_verification.json')
    old_release = ROOT / baseline['ks_fifth_release']
    assert sha(old_release / 'verification.json') == sha(F / 'formal_before/ks_fifth_verification.json') == sha(ROOT / 'build/ks_fifth/verification.json')
    for p in (old_release / (NAME + '_ks_fifth_v2.fs'), F / 'formal_before/known_good_ks_fifth_v2.fs'):
        assert sha(p) == baseline['ks_fifth_fs_sha256'] == previous['bitstream_sha256']

    synth, route, gate = E / 'lcd_rotate_synth_01', E / 'lcd_rotate_route_01', E / 'lcd_rotate_full_gate_01'
    manifest = load(synth / 'source_manifest.json')
    assert manifest == load(route / 'source_manifest.json')
    before = load(F / 'before/source_manifest.json')
    assert set(before) == set(manifest)
    assert {p for p in before if before[p] != manifest[p]} == CHANGED
    for p, digest in manifest.items():
        assert sha(ROOT / p) == digest, p
    assert manifest['rtl/synth/karplus_strong_voice.v'] == '30bd6704a113577063d462b1e1ef3f7dcfd903ed9578e34d80eb1968c09c4c8b'
    for folder in (synth, route):
        rec = load(folder / 'process.json')
        assert rec['status'] == 'EXITED' and rec['exit_code'] == 0, rec
        log = text(folder / 'stdout.log')
        assert 'KS_BUILD_FINISHED' in log and not re.search(r'^ERROR|\bPR0004\b', log, re.M)
        assert not text(folder / 'stderr.log').strip()

    tests = {}
    display = F / 'rtl_clean_01'
    rec = load(display / 'verification.json')
    assert rec['result'] == 'PASS_SOURCE_AND_DISPLAY_RTL'
    assert rec['scanner_active_pixels'] == 261120 and rec['curve_scanlines'] == 2176
    assert rec['curve_worst_clocks'] < rec['curve_budget_clocks'] == 3186
    for p, digest in rec['source_sha256'].items():
        assert sha(ROOT / p) == digest
    for p, digest in rec['log_sha256'].items():
        assert sha(display / p) == digest
    remote = load(F / 'remote_commit.json')
    assert remote['sha'] == rec['upstream_commit'] == '42f9c1fb73ba1e2260f889d4ba14fbfab07fc318'
    for p, blob in remote['blob_sha1'].items():
        original = text(F / 'remote_source' / p)
        raw = original.encode()
        assert hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest() == blob
        assert text(ROOT / p).rstrip('\n') == original.rstrip('\n')
    tests['display_rtl'] = sha(display / 'verification.json')

    vg = P / 'gwsynthesis' / (NAME + '.vg')
    tested = gate / 'actual.vg'
    assert sha(tested) == sha(synth / (NAME + '.vg'))
    if sha(tested) == sha(vg):
        proof = {'result': 'PASS', 'method': 'Byte-identical current/tested netlist', 'sha256': sha(vg)}
    elif re.sub(r'//[^\n]*', '', text(tested)) == re.sub(r'//[^\n]*', '', text(vg)):
        proof = {'result': 'PASS', 'method': 'Only generated comments differ', 'tested_sha256': sha(tested), 'current_sha256': sha(vg)}
    else:
        proof = compare(tested, vg)
        proof['checker_sha256'] = sha(ROOT / 'tools/compare_synth_graph.py')
    (F / 'netlist_binding.json').write_text(json.dumps(proof, indent=2))
    rec = load(gate / 'verification.json')
    assert rec['result'] == 'PASS' and rec['netlist_sha256'] == sha(tested)
    for p, digest in rec['source_sha256'].items():
        assert sha(ROOT / p) == digest
    assert sha(gate / 'tb_ks_fifth_full_gate.sv') == sha(ROOT / 'sim/tb/tb_ks_fifth_full_gate.sv')
    log = text(gate / 'simulation.log')
    assert 'PASS:' in log and not re.search(r'\*\* (Error|Fatal):', log)
    coverage = re.search(r'coverage: sample=(\d+) PCM=(\d+) attacks=(\d+) pixels=(\d+)', log)
    assert coverage and int(coverage[1]) >= 3000 and int(coverage[2]) >= 3000 and int(coverage[3]) >= 7 and int(coverage[4]) >= 100000
    harmony = re.search(r'harmony coverage: on=(\d+) off=(\d+)', log)
    assert harmony and int(harmony[1]) >= 500 and int(harmony[2]) >= 1000
    review_vendor_warnings(gate)
    tests['current_vg_vs_rtl'] = sha(gate / 'verification.json')
    # The old audio tests are reused only where their inputs still match.
    # Old LCD/full-chip output comparisons are not used to certify the rotation.
    for folder in (ROOT / 'build/ks_fifth/audition_v2', E / 'fifth_tdm_v2'):
        rec = load(folder / 'verification.json')
        assert rec['result'].startswith('PASS')
        for p, digest in rec['source_sha256'].items():
            p = p if p.startswith('rtl/') or p.startswith('sim/') else 'rtl/' + p
            assert sha(ROOT / p) == digest
        rel = (folder / 'verification.json').relative_to(ROOT).as_posix()
        assert previous['artifacts_sha256'][rel] == sha(folder / 'verification.json')
        tests[folder.name + '_unchanged_audio'] = sha(folder / 'verification.json')

    report_path = P / 'pnr' / (NAME + '.rpt.txt')
    timing_path = P / 'pnr' / (NAME + '_tr_content.html')
    report = text(report_path)
    rows = [[td.get_text(strip=True) for td in tr.find_all('td', recursive=False)] for tr in BeautifulSoup(text(timing_path), 'html.parser').find_all('tr')]
    resources, clocks = {}, {}
    for name in ('Logic', 'Register', 'CLS', 'BSRAM', 'DSP'):
        match = re.search(rf'^\s*{name}\s*\|\s*([\d.]+)/([\d.]+)', report, re.M)
        assert match, name
        used, available = map(float, match.groups())
        assert used <= available
        resources[name] = {'used': used, 'available': available}
    assert resources['BSRAM']['used'] == 118 and resources['DSP']['used'] == 106.5
    for clock, required in [('sys_clk_50m', 50), ('audio_clk_12m288', 12.288), ('ks_compute_clk', 100)]:
        matches = [r for r in rows if len(r) >= 4 and r[1] == clock and r[2].endswith('(MHz)') and r[3].endswith('(MHz)')]
        assert len(matches) == 1
        requested, actual = [float(v.replace('(MHz)', '')) for v in matches[0][2:4]]
        assert requested == required and actual >= required, (clock, requested, actual)
        clocks[clock] = {'required_mhz': required, 'fmax_mhz': actual}
    for kind in ('Setup', 'Hold'):
        matches = [r for r in rows if len(r) == 2 and r[0] == 'Numbers of ' + kind + ' Violated Endpoints']
        assert len(matches) == 1 and int(matches[0][1]) == 0, (kind, matches)
    latches = re.findall(r'Register as Latch\s*\|\s*(\d+)/', report)
    assert len(latches) == 2 and all(int(n) == 0 for n in latches)
    log = text(route / 'stdout.log')
    assert 'Placement and routing completed' in log and 'Bitstream generation completed' in log
    assert not re.search(r'\b[1-9]\d*\s+(?:unrouted|unconnected)\b', log, re.I)
    assert len(re.findall(r'WARN\s*\(PR1014\)', log)) == 2
    fs = P / 'pnr' / (NAME + '.fs')
    assert fs.stat().st_mtime >= datetime.fromisoformat(load(route / 'process.json')['started']).timestamp()
    assert sha(fs) == sha(route / fs.name) != baseline['ks_fifth_fs_sha256']
    for p in (report_path, timing_path):
        assert sha(p) == sha(route / p.name)
    artifacts = [ROOT / 'tools/check_lcd_rotation_ks_result.py', ROOT / 'tools/check_lcd_rotation_ks.py', ROOT / 'tools/check_ks_fifth_full_gate.py',
                 ROOT / 'docs/LCD_ROTATION_180_KS.md', ROOT / 'README.md', ROOT / 'AGENTS.md', F / 'netlist_binding.json', F / 'remote_commit.json']
    for folder in (synth, route, gate, display):
        artifacts += [p for p in folder.iterdir() if p.is_file() and p.suffix in ('.json', '.log', '.tcl', '.sv', '.vh')]
    result = {'result': 'PASS', 'created': datetime.now().astimezone().isoformat(), 'source_sha256': manifest, 'production_changes_vs_ks_v2': sorted(CHANGED),
              'polyphony': 4, 'model_states': 32, 'physical_compute_lanes': 2, 'sample_rate_hz': 48000, 'rotate_180': True,
              'netlist_sha256': sha(vg), 'tested_netlist_sha256': sha(tested), 'netlist_binding': proof, 'bitstream_sha256': sha(fs),
              'fallback_bitstream_sha256': baseline['ks_fifth_fs_sha256'], 'resources': resources, 'clocks': clocks,
              'violations': {'setup': 0, 'hold': 0, 'latch': 0, 'unrouted': 0, 'tested_sample_deadline': 0},
              'test_receipts': tests, 'artifacts_sha256': {p.relative_to(ROOT).as_posix(): sha(p) for p in artifacts},
              'scope': 'Originalproject currentVG vscomplete RTL includingLCD/KS/harmony on-off; focused fullpixel/curve RTL checks; actualpostrouteSTA. NoSDF. Oldaudio tests reused only forbyte-identical audio inputs. Registered touch/ADC/button harmony command stimuli only; no note/frequency/audio-result forcing.',
              'hardware_status': 'Not programmed, board display/audio/startup not yet checked. No COM/commit/push.'}
    (F / 'verification.json').write_text(json.dumps(result, indent=2))
    return result, fs


def publish(result, fs):
    dest = ROOT / 'build/releases/touch_game/ks_fifth_v2_lcd180_20261101'
    dest.mkdir(parents=True, exist_ok=False)
    shutil.copy2(fs, dest / (NAME + '_ks_fifth_v2_lcd180.fs'))
    for source, name in [(F / 'verification.json', 'verification.json'), (ROOT / 'docs/LCD_ROTATION_180_KS.md', 'DESIGN.md'),
                         (P / 'pnr' / (NAME + '.rpt.txt'), 'resource_report.txt'), (P / 'pnr' / (NAME + '_tr_content.html'), 'timing_report.html'),
                         (E / 'lcd_rotate_synth_01/source_manifest.json', 'source_manifest.json'), (F / 'rtl_clean_01/verification.json', 'display_rtl_verification.json')]:
        shutil.copy2(source, dest / name)
    clock = result['clocks']
    readme = f'''# KS 五度 V2 + LCD 180°（2026-11-01）

在 Gowin Programmer 中选择 `{NAME}_ks_fifth_v2_lcd180.fs`。本位流来自原工程及原 impl，保留已确认 KS 推荐音色（根音/五度主系数128/80，4独立声部、32模型状态，两条并行运算通路+TDM，48kHz音频/100MHz内部计算）。整屏文字、游戏、频谱及曲线统一旋转180°，触控映射与远端保持原配置。

正式综合、布局布线、STA及当前综合网表对照通过；系统/音频/KS Fmax为 {clock['sys_clk_50m']['fmax_mhz']} / {clock['audio_clk_12m288']['fmax_mhz']} / {clock['ks_compute_clk']['fmax_mhz']} MHz，要求50/12.288/100MHz；setup/hold/latch/未布通/已测deadline均0。两条原PR1014警告计入实际STA。详见[验证](verification.json)、[资源](resource_report.txt)、[时序](timing_report.html)、[源清单](source_manifest.json)。

本位流SHA256：`{result['bitstream_sha256']}`。此前未翻转KS V2固定发布仍保留于仓库 `build/releases/touch_game/ks_fifth_v2_20261101/`，SHA256 `{result['fallback_bitstream_sha256']}`，可回退。

本次未烧录/访问实物串口/提交/推送，板上显示、触控、音频和启动仍待实测。`DESIGN.md` 是仓库记录，其中仓库相对链接需在原工作区访问。无SDF仿真，另通过完整实际布线STA。
'''
    (dest / 'README.md').write_text(readme, encoding='utf-8')
    (dest / 'release_manifest.json').write_text(json.dumps({'result': 'PASS', 'files_sha256': {p.name: sha(p) for p in dest.iterdir() if p.is_file()}}, indent=2))
    archive = Path(shutil.make_archive(str(dest), 'zip', root_dir=dest.parent, base_dir=dest.name))
    print(json.dumps({'release': str(dest), 'zip_sha256': sha(archive)}, indent=2))


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--publish', action='store_true')
    args = ap.parse_args()
    result, fs = verify()
    if args.publish:
        publish(result, fs)
    print(json.dumps({k: result[k] for k in ('result', 'resources', 'clocks', 'bitstream_sha256')}, indent=2))
