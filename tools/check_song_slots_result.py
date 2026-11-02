"""Bind this repair to fresh original-project synthesis, gate tests and STA."""
import argparse
from collections import Counter
from datetime import datetime
import json
from pathlib import Path
import re
import shutil
import zipfile
import hashlib
import xml.etree.ElementTree as ET
from bs4 import BeautifulSoup
from build_song_slots import ROOT, BASE, PROJECT, NAME, guard, sha, load, save
from check_ks_pipeline_equivalence import verify as pipeline_equivalence, KS

SYN = BASE/'synth_02'
PNR = BASE/'route_03'
IMPL = PROJECT.parent/'impl'
OLD_SYN = ROOT/'build/input_rotation_imu/synth_02'
GATE = BASE/'full_gate_03'
KS_GATE = GATE


def text(p):
    return p.read_text(encoding='utf-8-sig')


def receipt(folder):
    record = load(folder/'verification.json')
    assert record.get('status', record.get('result')) == 'PASS', folder
    for p, digest in record['source_sha256'].items():
        if sha(ROOT/p) != digest:
            assert folder == BASE/'rtl_03' and p == KS, (folder, p)
            proof = pipeline_equivalence()
            assert digest == proof['old_source_sha256']
            # These completed tests elaborate catalog/UI/font/UART only.
            # The formerly compiled KS declarations are outside their cones.
            for name in record['log_sha256']:
                assert not re.search(r'Loading work\.(?:karplus_strong_voice|ks_string_lane|ks_period_pipeline)', text(folder/(name+'.log')))
    for b, digest in record['log_sha256'].items():
        log = folder/(b+'.log')
        assert sha(log) == digest
        assert 'PASS:' in text(log) and not re.search(r'FAIL:|\*\* (Error|Fatal):', text(log))
    return record


def completed(folder):
    rec = load(folder/'process.json')
    assert rec['status'] == 'EXITED' and rec['exit_code'] == 0
    assert not text(folder/'stderr.log').strip()
    log = text(folder/'stdout.log')
    assert 'SLOTS_BUILD_FINISHED' in log and not re.search(r'^\s*ERROR|\bPR0004\b', log, re.M)
    return rec


def review():
    manifest = guard()
    synth_manifest = load(SYN/'source_manifest.json')
    assert manifest == synth_manifest
    pipeline_equivalence()
    process = completed(SYN)
    for n in ('rtl_03',):
        receipt(BASE/n)
    old = ET.parse(OLD_SYN/f'{NAME}_syn_rsc.xml').getroot().attrib
    new = ET.parse(IMPL/f'gwsynthesis/{NAME}_syn_rsc.xml').getroot().attrib
    dsp = lambda d: {k: v for k, v in d.items() if k.startswith('T_MULT')}
    assert dsp(old) == dsp(new)
    assert old['T_Bsram'] == new['T_Bsram']
    number = lambda k: int(re.match(r'\d+', new['T_'+k])[0])
    resources = {k: number(v) for k, v in [('LUT', 'Lut'), ('ALU', 'Alu'), ('Register', 'Register'), ('BSRAM_logical', 'Bsram')]}
    assert resources['LUT']+resources['ALU'] <= 59904 and resources['Register'] <= 60780
    def warnings(log):
        return Counter(re.sub(r'":\d+\)', '":LINE)', s) for s in text(log).splitlines() if s.startswith('WARN'))
    before_warn, after_warn = warnings(OLD_SYN/'stdout.log'), warnings(SYN/'stdout.log')
    assert not (after_warn-before_warn), list((after_warn-before_warn).elements())
    vg = IMPL/f'gwsynthesis/{NAME}.vg'
    assert sha(vg) == sha(SYN/vg.name)
    assert vg.stat().st_mtime >= datetime.fromisoformat(process['started']).timestamp()
    record = {'result': 'PASS', 'netlist_sha256': sha(vg), 'source_sha256': manifest,
              'resources_synthesis': resources, 'logic_synthesis': resources['LUT']+resources['ALU'],
              'dsp_primitives': dsp(new), 'warnings': 'No new warnings after source-line normalization',
              'warning_count_before': sum(before_warn.values()), 'warning_count_after': sum(after_warn.values()),
              'removed_warnings': list((before_warn-after_warn).elements()),
              'scope': 'Same original project/config/device. Final physical resources and timing require P&R.'}
    record['synthesis_source_sha256'] = synth_manifest
    record['constraint_delta'] = 'Original SDC restored exactly after failed guard-only retry'
    save(SYN/'resource_review.json', record)
    print(json.dumps({k: record[k] for k in ('result', 'netlist_sha256', 'resources_synthesis', 'logic_synthesis', 'warning_count_after')}, indent=2))
    return record


def verify():
    reviewed = review()
    manifest = guard()
    assert manifest == load(PNR/'source_manifest.json')
    process = completed(PNR)
    vg = IMPL/f'gwsynthesis/{NAME}.vg'
    assert sha(vg) == reviewed['netlist_sha256'] == sha(SYN/vg.name)
    gate = receipt(GATE)
    assert gate['netlist_sha256'] == sha(vg) == sha(GATE/'actual.vg')
    assert gate['mapping_sha256'] == sha(GATE/'mapping.json')
    rec = load(KS_GATE/'verification.json')
    assert rec['result'] == 'PASS' and rec['netlist_sha256'] == sha(vg) == sha(KS_GATE/'actual.vg')
    for p, digest in rec['source_sha256'].items():
        assert sha(ROOT/p) == digest
    from check_ks_result import review_vendor_warnings
    review_vendor_warnings(KS_GATE)
    kslog = text(KS_GATE/'simulation.log')
    coverage = re.search(r'coverage: sample=(\d+) PCM=(\d+) attacks=(\d+) pixels=(\d+)', kslog)
    assert coverage and all(int(n) >= v for n, v in zip(coverage.groups(), (3000, 3000, 7, 100000)))
    slots_coverage = re.search(r'slots coverage: unique_menu_pixels=(\d+) builtin_previews=(\d+) pending_blocked=(\d+)', kslog)
    assert slots_coverage and int(slots_coverage[1]) >= 130560 and tuple(map(int, slots_coverage.groups()[1:])) == (3, 2)
    assert 'PASS:' in kslog and not re.search(r'\*\* (Error|Fatal):', kslog)
    # Reuse listening/TDM inputs unchanged, except the precisely bound,
    # output/cycle-equivalent KS substitution proved independently.
    audio = {}
    for folder in (ROOT/'build/ks_fifth/audition_v2', ROOT/'build/karplus_strong/fifth_tdm_v2'):
        r = load(folder/'verification.json')
        assert r['result'].startswith('PASS')
        for p, digest in r['source_sha256'].items():
            p = p if p.startswith(('rtl/', 'sim/')) else 'rtl/'+p
            if sha(ROOT/p) != digest:
                assert p == KS
                assert digest == pipeline_equivalence()['old_source_sha256']
        audio[folder.name] = sha(folder/'verification.json')
    report = IMPL/f'pnr/{NAME}.rpt.txt'
    timing = IMPL/f'pnr/{NAME}_tr_content.html'
    fs = IMPL/f'pnr/{NAME}.fs'
    for p in (report, timing, fs):
        assert sha(p) == sha(PNR/p.name)
        assert p.stat().st_mtime >= datetime.fromisoformat(process['started']).timestamp()
    resources = {}
    for key in ('Logic', 'Register', 'CLS', 'BSRAM', 'DSP'):
        m = re.search(rf'^\s*{key}\s*\|\s*([\d.]+)/([\d.]+)', text(report), re.M)
        assert m
        used, available = map(float, m.groups())
        assert used <= available
        resources[key] = {'used': used, 'available': available}
    assert resources['BSRAM']['used'] == 118 and resources['DSP']['used'] == 106.5
    rows = [[td.get_text(strip=True) for td in tr.find_all('td', recursive=False)]
            for tr in BeautifulSoup(text(timing), 'html.parser').find_all('tr')]
    clocks = {}
    for name, required in [('sys_clk_50m', 50), ('audio_clk_12m288', 12.288), ('ks_compute_clk', 100)]:
        found = [r for r in rows if len(r) >= 4 and r[1] == name and r[2].endswith('(MHz)') and r[3].endswith('(MHz)')]
        assert len(found) == 1
        requested, actual = [float(v.replace('(MHz)', '')) for v in found[0][2:4]]
        assert requested == required and actual >= required, (name, requested, actual)
        clocks[name] = {'required_mhz': required, 'fmax_mhz': actual}
    for kind in ('Setup', 'Hold'):
        found = [r for r in rows if len(r) == 2 and r[0] == 'Numbers of '+kind+' Violated Endpoints']
        assert len(found) == 1 and int(found[0][1]) == 0
    latches = re.findall(r'Register as Latch\s*\|\s*(\d+)/', text(report))
    assert len(latches) == 2 and all(int(n) == 0 for n in latches)
    route = text(PNR/'stdout.log')
    assert 'Placement and routing completed' in route and 'Bitstream generation completed' in route
    assert not re.search(r'\b[1-9]\d*\s+(unrouted|unconnected)\b', route, re.I)
    assert len(re.findall(r'WARN\s*\(PR1014\)', route)) == 2
    before = load(BASE/'before/snapshot.json')
    assert sha(fs) != before['bitstream_sha256']
    for name, digest in {
        'ks_fifth_v2_lcd180_inputfix_20261101.zip': '487ec2a753a214832db193a172fe88ecfcbf5d3e9083ad1d180645ff209a9d8b',
        'ks_tdm_32_20261101.zip': 'e4b763427fdc69d10be3d14d17941435fc2e2f351cb9209b45c5f136b7b816fa',
        'ks_fifth_v2_20261101.zip': '2f6b402edbf48a3c34a0ee5d18f5594977680a1ac51cacbb87a77621f10231a8',
        'ks_fifth_v2_lcd180_20261101.zip': 'b146c1eba470dc596be88e06fdac3a7031267319a9d08ce8d7990fce40bfd13c',
    }.items():
        assert sha(ROOT/'build/releases/touch_game'/name) == digest, name
    receipts = {n: sha(BASE/n/'verification.json') for n in ('rtl_03', 'full_gate_03')}
    receipts['ks_exact_pipeline_equivalence'] = sha(BASE/'ks_pipeline_equivalence.json')
    receipts['ks_current_vg'] = sha(KS_GATE/'verification.json')
    receipts.update(audio)
    artifacts = [ROOT/'tools/build_song_slots.py', ROOT/'tools/check_song_slots.py', ROOT/'tools/check_ks_pipeline_equivalence.py', BASE/'ks_pipeline_equivalence.json',
                 ROOT/'tools/check_song_slots_result.py', ROOT/'docs/SONG_SLOT_LAYOUT_123.md', BASE/'before/snapshot.json']
    for folder in (SYN, PNR, GATE, KS_GATE, BASE/'rtl_03'):
        artifacts += [p for p in folder.iterdir() if p.is_file() and p.suffix in ('.json', '.log', '.tcl', '.sv', '.vh')]
    result = {'result': 'PASS', 'created': datetime.now().astimezone().isoformat(),
              'source_sha256': manifest, 'netlist_sha256': sha(vg), 'bitstream_sha256': sha(fs),
              'fallback_bitstream_sha256': before['bitstream_sha256'], 'resources': resources, 'clocks': clocks,
              'polyphony': 4, 'model_states': 32, 'physical_compute_lanes': 2, 'sample_rate_hz': 48000,
              'rotate_display_and_touch_180': True, 'bidirectional_neck_inclination': True, 'builtin_slots': [1,2,3], 'pending_import_slots': [4,5],
              'violations': dict(setup=0, hold=0, latch=0, unrouted=0, tested_sample_deadline=0),
              'additional_setup_guard_ns': {'sys_clk_50m': 0, 'ks_compute_clk': 0},
              'test_receipts': receipts, 'artifacts_sha256': {p.relative_to(ROOT).as_posix(): sha(p) for p in artifacts},
              'scope': 'Fresh full VG vs RTL menu/three builtin previews/empty4-5 guards, physical timbre key/matrix/four-voice KS/harmony/LCD. Registered gesture/ADC/harmony commands plus audited countdown waiting only. Complete renderer pixels vs accepted source, UART import separately to4/5. Prior user-accepted touch/MPU code is byte-identical. No SDF; actual postroute STA. Listening/TDM inputs unchanged except independently proved exact KS output/latency substitution; unrelated GUI tests reuse their closed dependency cones.',
              'hardware_status': 'New slot-layout bitstream not programmed; previous inputfix was user-accepted. No COM/commit/push.'}
    save(BASE/'verification.json', result)
    return result, fs


def publish(result, fs):
    dest = ROOT/'build/releases/touch_game/ks_fifth_v2_lcd180_slots123_20261102'
    dest.mkdir(parents=True, exist_ok=False)
    shutil.copy2(fs, dest/f'{NAME}_ks_fifth_v2_lcd180_slots123.fs')
    for p, name in [(BASE/'verification.json', 'verification.json'), (ROOT/'docs/SONG_SLOT_LAYOUT_123.md', 'DESIGN.md'),
                    (SYN/'source_manifest.json', 'source_manifest.json'), (IMPL/f'pnr/{NAME}.rpt.txt', 'resource_report.txt'),
                    (IMPL/f'pnr/{NAME}_tr_content.html', 'timing_report.html'),
                    (BASE/'rtl_03/song_slots_123.png', 'menu_preview.png')]:
        shutil.copy2(p, dest/name)
    (dest/'README.md').write_text(
        '# 连续三槽曲库 + LCD180/触控/姿态/KS V2\n\n'
        '原工程/原impl新位流，保持已确认音色及4声部32模型状态、显示和触控180度与MPU姿态修复。\n\n'
        '第1槽：茉莉花；第2槽：Seven Nation Army；第3槽：情歌。第4、5槽均显示待导入，未导入不可开始；'
        '成功导入后显示对应USER4/USER5及RAM，可以选择和演奏。断电后恢复默认目录。曲谱事件、节奏、推荐音色和1345条共享导入容量保持。\n\n'
        '为满足原100MHz计算时钟，KS加法链按原有状态拆分、周期运算显式限宽；32768次PCM和busy周期对照完全相同，最长仍176周期，32模型状态与延迟保持。\n\n'
        f'位流SHA256：`{result["bitstream_sha256"]}`。实际STA及当前网表仿真通过，详情见verification.json。'
        '原输入修复发布ks_fifth_v2_lcd180_inputfix_20261101.zip保留回退。本次未烧录/开COM/提交/推送。\n', encoding='utf-8')
    save(dest/'release_manifest.json', {'result': 'PASS', 'files_sha256': {p.name: sha(p) for p in dest.iterdir() if p.is_file()}})
    archive = Path(shutil.make_archive(str(dest), 'zip', root_dir=dest.parent, base_dir=dest.name))
    with zipfile.ZipFile(archive) as z:
        assert z.testzip() is None
        for p in dest.iterdir():
            if p.is_file():
                assert hashlib.sha256(z.read(dest.name+'/'+p.name)).hexdigest() == sha(p)
    # Derive the actual dependency closure directly; a previous source ZIP
    # is optional user output and must never be a packaging prerequisite.
    assert sha(PROJECT) == result['source_sha256'][PROJECT.relative_to(ROOT).as_posix()]
    pending = [(PROJECT.parent/node.attrib['path']).resolve()
               for node in ET.parse(PROJECT).findall('./FileList/File')
               if node.attrib.get('enable', '1') == '1']
    dependencies = set()
    while pending:
        p = pending.pop()
        assert p.is_relative_to(ROOT) and p.is_file(), p
        if p in dependencies:
            continue
        dependencies.add(p)
        if p.suffix not in ('.v', '.vh'):
            continue
        body = re.sub(r'/\*.*?\*/|//[^\n]*', '', text(p), flags=re.S)
        for m in re.finditer(r'`include\s+"([^"]+)"|\$readmem[hb]\s*\(\s*"([^"]+)"', body):
            pending.append((p.parent/(m[1] or m[2])).resolve())
    members = sorted(p.relative_to(ROOT).as_posix() for p in dependencies)
    assert len(members) == len(set(members)) == 138
    prefix = 'ks_fifth_v2_lcd180_slots123_code_only'
    code_zip = ROOT/'build/exports/neo_guitar_touch_game_ks_fifth_v2_lcd180_slots123_code_only_20261102.zip'
    code_zip.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(code_zip, 'x', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for p in members:
            assert Path(p).suffix in ('.v', '.vh', '.mem', '.cst', '.sdc')
            assert sha(ROOT/p) == result['source_sha256'][p], p
            z.write(ROOT/p, prefix+'/'+p)
    with zipfile.ZipFile(code_zip) as z:
        assert z.testzip() is None
        assert set(z.namelist()) == {prefix+'/'+p for p in members}
        for p in members:
            assert hashlib.sha256(z.read(prefix+'/'+p)).hexdigest() == result['source_sha256'][p]
    save(BASE/'source_package_manifest.json', {'result': 'PASS', 'project_sha256': sha(PROJECT),
        'method': 'All enabled original gprj inputs plus recursive literal include/readmem dependencies',
        'files_sha256': {p: result['source_sha256'][p] for p in members}, 'code_only_zip_sha256': sha(code_zip)})
    save(BASE/'release_check.json', {'result': 'PASS', 'zip': archive.relative_to(ROOT).as_posix(),
                                   'zip_sha256': sha(archive), 'bitstream_sha256': sha(fs),
                                   'code_only_zip': code_zip.relative_to(ROOT).as_posix(), 'code_only_files': len(members),
                                   'code_only_zip_sha256': sha(code_zip)})
    print(archive)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('command', choices=('review', 'verify', 'publish'))
    args = ap.parse_args()
    if args.command == 'review':
        review()
    else:
        result, fs = verify()
        if args.command == 'publish':
            publish(result, fs)
        print(json.dumps({k: result[k] for k in ('result', 'resources', 'clocks', 'bitstream_sha256')}, indent=2))
