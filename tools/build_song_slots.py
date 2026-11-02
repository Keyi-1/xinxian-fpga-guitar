"""Use the original guitar .gprj/impl, preserving the accepted tone/settings."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT/'build/song_slots_123'
PROJECT = ROOT/'gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj'
NAME = 'neo_guitar_touch_game'
ALLOWED = {'rtl/game/game_p3_default_catalog.v','rtl/game/game_p3_catalog.v',
           'rtl/game/game_p2_mode_router.v','rtl/game/touch_game_ui.v',
           'rtl/game/touch_game_renderer.v','rtl/config/game_p3_slot_map.vh',
           'rtl/synth/karplus_strong_voice.v'}


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def load(p):
    return json.loads(p.read_text(encoding='utf-8-sig'))


def save(p, obj):
    p.write_text(json.dumps(obj, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')


def guard():
    before = load(BASE/'before/snapshot.json')
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT).decode().strip() == before['head']
    for p, item in before['protected'].items():
        assert sha(ROOT/p) == item['sha256'], p
        assert subprocess.check_output(['git', 'ls-files', '--stage', '--', p], cwd=ROOT).decode() == item['index'], p
    paths = set(before['source_sha256']) | {p.relative_to(ROOT).as_posix() for p in (ROOT/'rtl').rglob('*') if p.is_file()}
    manifest = {p: sha(ROOT/p) for p in sorted(paths)}
    changed = {p for p, digest in manifest.items() if digest != before['source_sha256'].get(p)}
    assert changed == ALLOWED, changed
    sdc = 'constraints/neo_guitar_touch_game.sdc'
    original = BASE/'before/source'/sdc
    assert sha(original) == before['source_sha256'][sdc]
    assert (ROOT/sdc).read_bytes() == original.read_bytes()
    assert sha(BASE/'before/known_good_inputfix.fs') == before['bitstream_sha256']
    return manifest


def build(stage, name):
    manifest = guard()
    active = subprocess.run(['powershell.exe', '-NoProfile', '-Command',
                             "@(Get-Process gw_sh,gw_synth,gw_pnr -ErrorAction SilentlyContinue).Count"],
                            capture_output=True, text=True, creationflags=subprocess.CREATE_NO_WINDOW)
    assert active.returncode == 0 and active.stdout.strip() == '0', 'Inspect existing Gowin processes first'
    if stage == 'pnr':
        review = load(BASE/'synth_02/resource_review.json')
        assert review['result'] == 'PASS'
        assert sha(PROJECT.parent/f'impl/gwsynthesis/{NAME}.vg') == review['netlist_sha256']
        assert manifest == load(BASE/'synth_02/source_manifest.json')
    dest = BASE/name
    dest.mkdir(parents=True, exist_ok=False)
    save(dest/'source_manifest.json', manifest)
    tcl = dest/'build.tcl'
    tcl.write_text(f'open_project {{{PROJECT.as_posix()}}}\nif {{[catch {{run {stage}}} message]}} {{puts stderr $message;exit 1}}\nputs SLOTS_BUILD_FINISHED\nexit\n')
    record = {'status': 'RUNNING', 'stage': stage, 'started': datetime.now().astimezone().isoformat(),
              'source_commit': load(BASE/'before/snapshot.json')['head'], 'project': PROJECT.as_posix()}
    with (dest/'stdout.log').open('xb') as out, (dest/'stderr.log').open('xb') as err:
        proc = subprocess.Popen(['S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe', str(tcl)],
                                cwd=PROJECT.parent, stdout=out, stderr=err, creationflags=subprocess.CREATE_NO_WINDOW)
        record['pid'] = proc.pid
        save(dest/'process.json', record)
        print(f'{stage} PID={proc.pid}; {dest}', flush=True)
        code = proc.wait()
    record.update(status='EXITED', exit_code=code, finished=datetime.now().astimezone().isoformat())
    save(dest/'process.json', record)
    assert guard() == manifest
    impl = PROJECT.parent/'impl'/('gwsynthesis' if stage == 'syn' else 'pnr')
    for pattern in (['*.vg', '*.xml', '*.html', '*.log'] if stage == 'syn' else ['*.fs', '*.log', '*.txt', '*.html', '*.timing_paths']):
        for p in impl.glob(pattern):
            shutil.copy2(p, dest/p.name)
    raise SystemExit(code)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('stage', choices=('syn', 'pnr'))
    ap.add_argument('name')
    args = ap.parse_args()
    assert re.fullmatch(r'[A-Za-z0-9_]+', args.name)
    build(args.stage, args.name)
