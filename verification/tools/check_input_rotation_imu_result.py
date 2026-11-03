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
from build_input_rotation_imu import ROOT, BASE, PROJECT, NAME, guard, sha, load, save

SYN = BASE/'synth_02'
PNR = BASE/'route_02'
IMPL = PROJECT.parent/'impl'
OLD_SYN = ROOT/'build/karplus_strong/lcd_rotate_synth_01'
GATE = BASE/'gate_02'
KS_GATE = ROOT/'build/karplus_strong/input_fix_full_gate_02'


def text(p):
    return p.read_text(encoding='utf-8-sig')


def receipt(folder):
    record = load(folder/'verification.json')
    assert record.get('status', record.get('result')) == 'PASS', folder
    for p, digest in record['source_sha256'].items():
        assert sha(ROOT/p) == digest, (folder, p)
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
    assert 'INPUT_BUILD_FINISHED' in log and not re.search(r'^\s*ERROR|\bPR0004\b', log, re.M)
    return rec


def review():
    manifest = guard()
    assert manifest == load(SYN/'source_manifest.json')
    process = completed(SYN)
    for n in ('components_03', 'rtl_top_68_02', 'rtl_top_70_02'):
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
    assert 'PASS:' in kslog and not re.search(r'\*\* (Error|Fatal):', kslog)
    # Reuse accepted listening/TDM evidence only with byte-identical inputs.
    audio = {}
    for folder in (ROOT/'build/ks_fifth/audition_v2', ROOT/'build/karplus_strong/fifth_tdm_v2'):
        r = load(folder/'verification.json')
        assert r['result'].startswith('PASS')
        for p, digest in r['source_sha256'].items():
            p = p if p.startswith(('rtl/', 'sim/')) else 'rtl/'+p
            assert sha(ROOT/p) == digest
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
        'ks_tdm_32_20261101.zip': 'e4b763427fdc69d10be3d14d17941435fc2e2f351cb9209b45c5f136b7b816fa',
        'ks_fifth_v2_20261101.zip': '2f6b402edbf48a3c34a0ee5d18f5594977680a1ac51cacbb87a77621f10231a8',
        'ks_fifth_v2_lcd180_20261101.zip': 'b146c1eba470dc596be88e06fdac3a7031267319a9d08ce8d7990fce40bfd13c',
    }.items():
        assert sha(ROOT/'build/releases/touch_game'/name) == digest, name
    receipts = {n: sha(BASE/n/'verification.json') for n in ('components_03', 'rtl_top_68_02', 'rtl_top_70_02', 'gate_02')}
    receipts['ks_current_vg'] = sha(KS_GATE/'verification.json')
    receipts.update(audio)
    artifacts = [ROOT/'tools/build_input_rotation_imu.py', ROOT/'tools/check_input_rotation_imu.py',
                 ROOT/'tools/check_input_rotation_imu_result.py', ROOT/'docs/LCD180_TOUCH_IMU_FIX.md', BASE/'before/snapshot.json']
    for folder in (SYN, PNR, GATE, KS_GATE, BASE/'components_03', BASE/'rtl_top_68_02', BASE/'rtl_top_70_02'):
        artifacts += [p for p in folder.iterdir() if p.is_file() and p.suffix in ('.json', '.log', '.tcl', '.sv', '.vh')]
    result = {'result': 'PASS', 'created': datetime.now().astimezone().isoformat(),
              'source_sha256': manifest, 'netlist_sha256': sha(vg), 'bitstream_sha256': sha(fs),
              'fallback_bitstream_sha256': before['bitstream_sha256'], 'resources': resources, 'clocks': clocks,
              'polyphony': 4, 'model_states': 32, 'physical_compute_lanes': 2, 'sample_rate_hz': 48000,
              'rotate_display_and_touch_180': True, 'bidirectional_neck_inclination': True,
              'violations': dict(setup=0, hold=0, latch=0, unrouted=0, tested_sample_deadline=0),
              'test_receipts': receipts, 'artifacts_sha256': {p.relative_to(ROOT).as_posix(): sha(p) for p in artifacts},
              'scope': 'Fresh actual production VG vs full RTL for raw-touch/calibration/AUTO/MPU GPIO and actual tone changes, plus four-voice KS/harmony/LCD regression. Production256 and time counts preserved; only explicit timer waiting and registered GT911/ADC/button commands stimulated. No SDF; actual postroute STA. Old listening/TDM reused with exact source hashes.',
              'hardware_status': 'Not programmed; board touch/MPU/audio/startup acceptance pending. No COM/commit/push.'}
    save(BASE/'verification.json', result)
    return result, fs


def publish(result, fs):
    dest = ROOT/'build/releases/touch_game/ks_fifth_v2_lcd180_inputfix_20261101'
    dest.mkdir(parents=True, exist_ok=False)
    shutil.copy2(fs, dest/f'{NAME}_ks_fifth_v2_lcd180_inputfix.fs')
    for p, name in [(BASE/'verification.json', 'verification.json'), (ROOT/'docs/LCD180_TOUCH_IMU_FIX.md', 'DESIGN.md'),
                    (SYN/'source_manifest.json', 'source_manifest.json'), (IMPL/f'pnr/{NAME}.rpt.txt', 'resource_report.txt'),
                    (IMPL/f'pnr/{NAME}_tr_content.html', 'timing_report.html')]:
        shutil.copy2(p, dest/name)
    (dest/'README.md').write_text(
        '# KS V2 + LCD180 触控/姿态修复\n\n原工程/原impl新位流，保持已确认音色及4声部32模型状态。'
        '显示与触控统一180°；MPU斜抱判定兼容正负琴颈方向。\n\n'
        '上电平放静止，点击旋转后主页CALIBRATE，约4秒后确认FLAT，再打开AUTO，进入演奏。'
        '向侧面或沿琴颈倾斜约45～55°并保持，应切换明亮弦音；更竖直的琴颈姿态仍为UPRIGHT。手动优先与尾音等待保留。'
        '本次未下板，传感器实物数据和模块接线需现场核对。\n\n'
        f'位流SHA256：`{result["bitstream_sha256"]}`。实际STA及当前网表仿真通过，详情见verification.json。'
        '旧固定发布ks_fifth_v2_lcd180_20261101.zip保留回退。\n', encoding='utf-8')
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
    assert len(members) == len(set(members)) == 137
    prefix = 'ks_fifth_v2_lcd180_inputfix_code_only'
    code_zip = ROOT/'build/exports/neo_guitar_touch_game_ks_fifth_v2_lcd180_inputfix_code_only_20261101.zip'
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
