"""Certify the approved fifth V2 against its own build and simulation evidence.

The earlier KS certificate/release remains immutable. Never programs or pushes.
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
F = ROOT / 'build/ks_fifth'
P = ROOT / 'gowin/neo_guitar_touch_game/impl'
NAME = 'neo_guitar_touch_game'
APPROVED = '30bd6704a113577063d462b1e1ef3f7dcfd903ed9578e34d80eb1968c09c4c8b'
ROLLBACK = '2d4700d60754a51d8e4c5fe19ddc50fb233ca0848c410352b01dd92555913c41'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def text(path):
    return path.read_text(encoding='utf-8-sig')


def check_log(folder):
    log = text(folder / 'simulation.log')
    assert 'PASS:' in log and not re.search(r'\*\* (Error|Fatal):', log), folder
    return log


def verify():
    assert subprocess.check_output(['git', 'rev-parse', '--short=7', 'HEAD'], cwd=ROOT, text=True).strip() == 'd5d8599'
    assert sha(ROOT / 'rtl/synth/karplus_strong_voice.v') == APPROVED
    state = load(F / 'CURRENT_STATE.json')
    assert state['user_approval'] == '我觉得推荐版可以'
    for path, record in load(F / 'before/protected.json').items():
        assert sha(ROOT / path) == record['sha256'], path
        assert subprocess.check_output(['git', 'ls-files', '--stage', '--', path], cwd=ROOT, text=True) == record['index'], path
    # The previous successful publication and its certificate stay unchanged.
    assert sha(E / 'verification.json') == sha(F / 'before/verification.json')
    old_release = ROOT / 'build/releases/touch_game/ks_tdm_32_20261101'
    assert sha(old_release / 'verification.json') == sha(F / 'before/verification.json')
    for path in (F / 'before/known_good_ks32.fs', old_release / (NAME + '_ks_tdm_32.fs')):
        assert sha(path) == ROLLBACK

    synth, route = E / 'fifth_synth_01', E / 'fifth_route_01'
    manifest = load(synth / 'source_manifest.json')
    assert manifest == load(route / 'source_manifest.json')
    for path, digest in manifest.items():
        assert sha(ROOT / path) == digest, path
    before = load(F / 'before/source_manifest.json')
    assert set(before) == set(manifest)
    assert [p for p in before if before[p] != manifest[p]] == ['rtl/synth/karplus_strong_voice.v']
    for folder in (synth, route):
        proc = load(folder / 'process.json')
        assert proc['status'] == 'EXITED' and proc['exit_code'] == 0, proc
        log = text(folder / 'stdout.log')
        assert 'KS_BUILD_FINISHED' in log and not re.search(r'^ERROR|\bPR0004\b', log, re.M)
        assert not text(folder / 'stderr.log').strip()

    vg = P / 'gwsynthesis' / (NAME + '.vg')
    tested = E / 'fifth_full_gate_01/actual.vg'
    assert sha(tested) == sha(synth / (NAME + '.vg'))
    if sha(tested) == sha(vg):
        proof = {'result': 'PASS', 'method': 'Byte-identical tested/current netlist', 'sha256': sha(vg)}
    elif re.sub(r'//[^\n]*', '', text(tested)) == re.sub(r'//[^\n]*', '', text(vg)):
        proof = {'result': 'PASS', 'method': 'Only generated comments differ', 'tested_sha256': sha(tested), 'current_sha256': sha(vg)}
    else:
        proof = compare(tested, vg)
        proof['checker_sha256'] = sha(ROOT / 'tools/compare_synth_graph.py')
    (F / 'netlist_binding.json').write_text(json.dumps(proof, indent=2))

    gate = E / 'fifth_full_gate_01'
    record = load(gate / 'verification.json')
    assert record['result'] == 'PASS' and record['netlist_sha256'] == sha(tested)
    for path, digest in record['source_sha256'].items():
        assert sha(ROOT / path) == digest, path
    assert sha(gate / 'tb_ks_fifth_full_gate.sv') == sha(ROOT / 'sim/tb/tb_ks_fifth_full_gate.sv')
    log = check_log(gate)
    coverage = re.search(r'harmony coverage: on=(\d+) off=(\d+)', log)
    assert coverage and int(coverage[1]) >= 500 and int(coverage[2]) >= 1000
    review_vendor_warnings(gate)

    audition = F / 'audition_v2'
    record = load(audition / 'verification.json')
    assert record['result'] == 'PASS_AWAITING_LISTENING_CONFIRMATION'
    assert record['rtl_off_exact_samples'] == record['rtl_mix_identity_samples'] == 288256
    assert 'fifths80,16,8,4' in record['gain']
    for path, digest in record['source_sha256'].items():
        assert sha(ROOT / path) == digest
    assert record['reference_kernel_sha256'] == sha(F / 'before/source/rtl/synth/karplus_strong_voice.v')
    normalized = text(ROOT / 'rtl/synth/karplus_strong_voice.v').replace('../config/', (ROOT / 'rtl/config').as_posix() + '/')
    assert text(audition / 'candidate.v') == normalized
    assert sha(audition / 'tb_ks_fifth_audition.sv') == sha(ROOT / 'sim/tb/tb_ks_fifth_audition.sv')
    assert sha(audition / 'generator.py') == sha(ROOT / 'tools/check_ks_fifth_audition.py')
    for path, digest in record['wav_sha256'].items():
        assert sha(audition / path) == digest
    assert sha(audition / 'range_report.json') == record['range_report_sha256']
    ranges = load(audition / 'range_report.json')
    assert ranges['on']['words_per_voice'] == 1024 and ranges['off']['words_per_voice'] == 1020
    assert ranges['delay_bsrams_before'] == ranges['delay_bsrams_after'] == 4
    for mode in ('on', 'off'):
        for model in ranges[mode]['models']:
            assert model['minimum_required_capacity'] <= model['capacity']
    assert 'maxbusy=176' in check_log(audition)
    for note in record['notes'].values():
        assert abs(note['fifth_pitch_error_cents']) < 0.2
        assert note['mixed_peak_pcm16'] < 32768 and note['root_body_rms'] > note['fifth_body_rms'] > 0

    tdm = E / 'fifth_tdm_v2'
    record = load(tdm / 'verification.json')
    assert record['result'] == 'PASS'
    for path, digest in record['source_sha256'].items():
        source = ROOT / 'rtl' / path
        assert sha(source) == digest
        expected = text(source).replace('../config/', (ROOT / 'rtl/config').as_posix() + '/').replace('../../mem/', (ROOT / 'mem').as_posix() + '/')
        assert text(tdm / Path(path).name) == expected
    assert '55996 four-voice samples' in check_log(tdm)
    review_vendor_warnings(tdm)
    assert load(F / 'preservation_check.json')['tdm_bench_sha256'] == sha(ROOT / 'sim/tb/tb_ks_tdm.sv')

    # Reuse earlier pure piano/wah and slide results only where source bytes
    # remain identical. No earlier KS numerical-equivalence result certifies V2.
    reused = {}
    for name in ('integration_final_01', 'slide_distance_01'):
        rec = load(E / name / 'verification.json')
        assert rec['result'] == 'PASS'
        for path, digest in rec['source_sha256'].items():
            if path != 'rtl/synth/karplus_strong_voice.v':
                assert sha(ROOT / path) == digest
        reused[name] = sha(E / name / 'verification.json')

    report = text(P / 'pnr' / (NAME + '.rpt.txt'))
    timing = text(P / 'pnr' / (NAME + '_tr_content.html'))
    resources = {}
    for name in ('Logic', 'Register', 'CLS', 'BSRAM', 'DSP'):
        match = re.search(rf'^\s*{name}\s*\|\s*([\d.]+)/([\d.]+)', report, re.M)
        assert match, name
        used, total = map(float, match.groups())
        assert used <= total
        resources[name] = {'used': used, 'available': total}
    assert resources['BSRAM']['used'] == 118
    rows = [[td.get_text(strip=True) for td in tr.find_all('td', recursive=False)] for tr in BeautifulSoup(timing, 'html.parser').find_all('tr')]
    clocks = {}
    for clock, required in [('sys_clk_50m', 50), ('audio_clk_12m288', 12.288), ('ks_compute_clk', 100)]:
        matches = [r for r in rows if len(r) >= 4 and r[1] == clock and r[2].endswith('(MHz)') and r[3].endswith('(MHz)')]
        assert len(matches) == 1
        requested, actual = [float(v.replace('(MHz)', '')) for v in matches[0][2:4]]
        assert requested == required and actual >= required, (clock, requested, actual)
        clocks[clock] = {'required_mhz': required, 'fmax_mhz': actual}
    for kind in ('Setup', 'Hold'):
        matches = [r for r in rows if len(r) == 2 and r[0] == 'Numbers of ' + kind + ' Violated Endpoints']
        assert len(matches) == 1 and int(matches[0][1]) == 0
    latches = re.findall(r'Register as Latch\s*\|\s*(\d+)/', report)
    assert len(latches) == 2 and all(int(n) == 0 for n in latches)
    log = text(route / 'stdout.log')
    assert 'Placement and routing completed' in log and 'Bitstream generation completed' in log
    assert not re.search(r'\b[1-9]\d*\s+(?:unrouted|unconnected)\b', log, re.I)
    fs = P / 'pnr' / (NAME + '.fs')
    assert fs.stat().st_mtime >= datetime.fromisoformat(load(route / 'process.json')['started']).timestamp()
    assert sha(fs) == sha(route / fs.name)
    for name in (NAME + '.rpt.txt', NAME + '_tr_content.html'):
        assert sha(P / 'pnr' / name) == sha(route / name)

    artifacts = [ROOT / 'tools/check_ks_fifth_result.py', ROOT / 'tools/check_ks_fifth_full_gate.py', ROOT / 'sim/tb/tb_ks_fifth_full_gate.sv', ROOT / 'docs/KS_FIFTH_AUDITION.md', ROOT / 'README.md', ROOT / 'AGENTS.md', F / 'netlist_binding.json']
    for folder in (synth, route, gate, audition, tdm):
        artifacts += [p for p in folder.iterdir() if p.is_file() and p.suffix in ('.json', '.log', '.tcl', '.sv', '.py', '.txt', '.wav')]
    result = {'result': 'PASS', 'created': datetime.now().astimezone().isoformat(), 'baseline': 'd5d8599', 'user_approval': state['user_approval'],
              'polyphony': 4, 'models_per_voice': 8, 'model_states': 32, 'physical_compute_lanes': 2, 'sample_rate_hz': 48000,
              'source_sha256': manifest, 'netlist_sha256': sha(vg), 'tested_netlist_sha256': sha(tested), 'netlist_binding': proof,
              'bitstream_sha256': sha(fs), 'rollback_bitstream_sha256': ROLLBACK, 'resources': resources, 'clocks': clocks,
              'violations': {'setup': 0, 'hold': 0, 'latch': 0, 'unrouted': 0, 'tested_sample_deadline': 0},
              'reused_unchanged_paths': reused, 'artifacts_sha256': {p.relative_to(ROOT).as_posix(): sha(p) for p in artifacts},
              'scope': 'Approved V2 RTL audition/range/all8 state checks, actualPLL fourvoiceTDM, complete current synthesis VG vs RTL with harmony on/off; registered touch/ADC/button harmony outputs are input stimuli, no note/phase/audio-result forcing. No SDF; separate complete post-route STA.',
              'hardware_status': 'Not programmed; user approved RTL audition, physical board output not yet checked. No COM or Git push.'}
    (F / 'verification.json').write_text(json.dumps(result, indent=2))
    return result, fs


def publish(result, fs):
    dest = ROOT / 'build/releases/touch_game/ks_fifth_v2_20261101'
    dest.mkdir(parents=True, exist_ok=False)
    shutil.copy2(fs, dest / (NAME + '_ks_fifth_v2.fs'))
    for source, name in [(F / 'verification.json', 'verification.json'), (ROOT / 'docs/KS_FIFTH_AUDITION.md', 'DESIGN.md'),
                         (P / 'pnr' / (NAME + '.rpt.txt'), 'resource_report.txt'), (P / 'pnr' / (NAME + '_tr_content.html'), 'timing_report.html'),
                         (E / 'fifth_synth_01/source_manifest.json', 'source_manifest.json'), (F / 'audition_v2/range_report.json', 'range_report.json'),
                         (F / 'audition_v2/root_fifth_together.wav', 'root_fifth_together.wav'), (F / 'audition_v2/off_vs_new_mix.wav', 'off_vs_new_mix.wav')]:
        shutil.copy2(source, dest / name)
    clocks = result['clocks']
    readme = f'''# KS 五度和声 V2（用户已确认试听，2026-11-01）

本包位流来自用户原工程 `gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj` 的原 impl 正式综合、布局布线。使用 Gowin Programmer 选择本目录 `{NAME}_ks_fifth_v2.fs`；本次未自动烧录或打开实物串口，板上输出及启动仍待实测。

保持4独立声部、每声部8个物理模型状态、共32状态；实际两条并行 KS 运算通路配合 TDM 和流水线，内部100MHz、音频48kHz。约1.4983倍频五度模型拥有独立延迟/低通/DC/指针状态；五度主模型容量224字，八区域合计1024字/声部，不新增 BSRAM。音域覆盖现有D3～G5及颤音。主模型混合系数根音128、五度80。

完整 P&R/STA 通过，系统/音频/KS Fmax 为 {clocks['sys_clk_50m']['fmax_mhz']} / {clocks['audio_clk_12m288']['fmax_mhz']} / {clocks['ks_compute_clk']['fmax_mhz']} MHz；实际要求50/12.288/100MHz，setup/hold/latch/未布通均0。[资源报告](resource_report.txt)、[时序报告](timing_report.html)、[哈希绑定验证](verification.json)、[源文件清单](source_manifest.json)。

关闭五度与此前成功版288256个 PCM 逐值一致；实际 PLL 四声部 TDM 比较55996个声部 PCM，无截止时间溢出；本次实际综合网表与完整 RTL 比较覆盖五度开/关、四路同时发声及独立拨弦。触控、ADC、按钮和声命令的寄存输出仅作明确登记的输入刺激；音频/频率/演奏事件结果未被强制。网表仿真无 SDF，另通过实际布线 STA。

试听：[根音单独→五度单独→两者合奏](root_fifth_together.wav)，[原关闭五度→新合奏](off_vs_new_mix.wav)。D3/A3/A4/G5，统一固定增益的真实 RTL KS 干声，非板上 DAC 录音；无分段归一化或软件合成。用户已确认推荐版听感。

本位流 SHA256：`{result['bitstream_sha256']}`。

旧成功位流另保留于仓库 `build/ks_fifth/before/known_good_ks32.fs` 和固定发布 `build/releases/touch_game/ks_tdm_32_20261101/`，SHA256 `{ROLLBACK}`。本包不覆盖旧发布。`DESIGN.md` 是仓库设计记录，其中仓库相对链接请在原工作区访问。
'''
    (dest / 'README.md').write_text(readme, encoding='utf-8')
    files = {p.name: sha(p) for p in dest.iterdir() if p.is_file()}
    (dest / 'release_manifest.json').write_text(json.dumps({'result': 'PASS', 'bitstream_sha256': result['bitstream_sha256'], 'files_sha256': files}, indent=2))
    archive = shutil.make_archive(str(dest), 'zip', root_dir=dest.parent, base_dir=dest.name)
    print(json.dumps({'release': str(dest), 'zip_sha256': sha(Path(archive))}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    result, fs = verify()
    if args.publish:
        publish(result, fs)
    print(json.dumps({k: result[k] for k in ('result', 'resources', 'clocks', 'bitstream_sha256')}, indent=2))
