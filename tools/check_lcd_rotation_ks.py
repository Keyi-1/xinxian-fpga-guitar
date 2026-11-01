"""Validate the remote LCD-only port onto the approved local KS V2 source.

Compiles current RTL and runs the two upstream display tests in ModelSim.
Does not synthesize, route, update Git refs, program hardware or touch audio.
"""
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

from check_karplus_strong import ROOT, run

E = ROOT / 'build/lcd_rotate_ks'
CHANGED = {'rtl/display/guitar_radial_curve_renderer.v',
           'rtl/display/lcd_rgb_scan_480x272.v',
           'rtl/game/guitar_touch_game_display.v'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_preservation():
    before = json.loads((E / 'before/source_manifest.json').read_text())
    assert {p for p, h in before.items() if sha(ROOT / p) != h} == CHANGED
    for p, record in json.loads((E / 'before/protected.json').read_text()).items():
        assert sha(ROOT / p) == record['sha256'], p
        assert subprocess.check_output(['git', 'ls-files', '--stage', '--', p], cwd=ROOT, text=True) == record['index'], p
    baseline = json.loads((E / 'before/baseline.json').read_text())
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == baseline['head']
    for p in (ROOT / 'gowin/neo_guitar_touch_game/impl/pnr/neo_guitar_touch_game.fs',
              ROOT / baseline['ks_fifth_release'] / 'neo_guitar_touch_game_ks_fifth_v2.fs'):
        assert sha(p) == baseline['ks_fifth_fs_sha256']
    remote = json.loads((E / 'remote_commit.json').read_text())
    for p, blob in remote['blob_sha1'].items():
        upstream = (E / 'remote_source' / p).read_text()
        data = upstream.encode()
        assert hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == blob, p
        assert (ROOT / p).read_text().rstrip('\n') == upstream.rstrip('\n'), p
    return before, baseline, remote


def main():
    before, baseline, remote = verify_preservation()
    dest = E / (sys.argv[1] if len(sys.argv) > 1 else 'rtl_01')
    dest.mkdir(parents=True, exist_ok=False)
    source = dest / 'sources'
    source.mkdir()
    files = list((ROOT / 'rtl').rglob('*.v'))
    assert len({p.name for p in files}) == len(files)
    manifest = {p.relative_to(ROOT).as_posix(): sha(p) for p in files}
    for path in files:
        code = path.read_text(encoding='utf-8-sig').replace('../config/', (ROOT / 'rtl/config').as_posix() + '/')
        code = code.replace('../../mem/', (ROOT / 'mem').as_posix() + '/')
        (source / path.name).write_text(code, encoding='utf-8')
    benches = ['tb_lcd_rotation', 'tb_lcd_rotation_curves']
    for bench in benches:
        path = ROOT / 'sim' / (bench + '.sv')
        shutil.copy2(path, dest / path.name)
        manifest[path.relative_to(ROOT).as_posix()] = sha(path)
    run('vlib.log', ['vlib.exe', 'work'], dest)
    run('compile.log', ['vlog.exe', '-sv',
        'S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v',
        *[str(p) for p in source.glob('*.v')], *[b + '.sv' for b in benches]], dest)
    logs = {}
    for bench in benches:
        log = run(bench + '.log', ['vsim.exe', '-c', 'work.' + bench,
                  '-l', bench + '.transcript', '-do', 'run -all; quit -f'], dest)
        assert 'PASS:' in log and 'Errors: 0, Warnings: 0' in log
        logs[bench] = log
    assert '261120 pixels' in logs['tb_lcd_rotation']
    counts = re.search(r'renderer (\d+) lines, worst (\d+)/3186 clocks', logs['tb_lcd_rotation_curves'])
    assert counts and int(counts[1]) == 2176 and int(counts[2]) < 3186
    verify_preservation()
    for p, digest in manifest.items():
        assert sha(ROOT / p) == digest, p
    result = {'result': 'PASS_SOURCE_AND_DISPLAY_RTL', 'upstream_commit': remote['sha'],
              'upstream_blob_match': 'Frozen upstream files match Git blob IDs; all three current display sources and both tests differ only in CRLF or trailing empty lines',
              'production_changes': sorted(CHANGED), 'source_sha256': manifest,
              'unchanged_build_inputs': {p: h for p, h in before.items() if p not in CHANGED},
              'audio': 'All other build inputs including approved KS V2, voices, control, ROMs, clocks and touch mapping unchanged byte-for-byte; audio simulations reused only for unchanged audio source, not rerun.',
              'scanner_active_pixels': 261120, 'curve_scanlines': int(counts[1]),
              'curve_worst_clocks': int(counts[2]), 'curve_budget_clocks': 3186,
              'protected_bytes_and_git_index': 'unchanged', 'prior_bitstream_sha256': baseline['ks_fifth_fs_sha256'],
              'log_sha256': {p.name: sha(p) for p in dest.glob('*.log')},
              'scope': 'Current entire RTL compiles; two focused display simulations pass. No new synthesis/P&R/STA or bitstream. Existing impl FS and fixed KS V2 release preserved; not a new combined hardware certification.'}
    (dest / 'verification.json').write_text(json.dumps(result, indent=2))
    print(json.dumps({k: result[k] for k in ('result', 'scanner_active_pixels', 'curve_scanlines', 'curve_worst_clocks', 'scope')}, indent=2))


if __name__ == '__main__':
    main()
