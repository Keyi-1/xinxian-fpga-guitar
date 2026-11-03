"""Freeze the accepted guitar and prepare only JDY-23 UART rate/pin changes."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

R = Path(__file__).resolve().parents[1]
E = R / 'build/jdy23/v1'
BASE = R / 'build/releases/touch_game/tail_lock_20261025'


def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()


def run():
    assert not E.exists(), 'Inspect existing run; never overwrite or restart it'
    baseline = json.loads((BASE / 'verification.json').read_text(encoding='utf-8-sig'))
    assert baseline['result'] == 'PASS'
    for name, digest in baseline['source_sha256'].items():
        assert sha(R / name) == digest, name
    assert not subprocess.check_output(['powershell', '-NoProfile', '-Command',
        "Get-Process gw_sh,gw_synth,gw_pnr -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id; exit 0"], text=True).strip()
    E.mkdir(parents=True)
    protected = {}
    for name in ('gowin/neo_guitar_touch_game/impl/neo_guitar_touch_game_process_config.json', 'docs/MPU6050_POSTURE_TIMBRE_DESIGN_PLAN.md'):
        protected[name] = {'sha256': sha(R / name), 'index': subprocess.check_output(['git', 'ls-files', '--stage', '--', name], cwd=R, text=True).strip()}
    (E / 'protected_user_files.json').write_text(json.dumps(protected, indent=2))
    changes = {
        'rtl/top/neo_guitar_touch_game_top.v': [(b'UART_CLKS_PER_BIT=434,', b'UART_CLKS_PER_BIT=5208,')],
        'constraints/neo_guitar_touch_game.cst': [
            (b'# NEO Dock 31005 DEBUG-USB2 / BL616 UART: J2-50 TX, J2-54 RX.', b'# JDY-23 dedicated UART: J8-9 / PMOD1_IO2 TX, J8-10 / PMOD1_IO3 RX.'),
            (b'# Verified against both 60K SOM schematics and the 31005 dock, not 31002 Y14.', b'# 31005 J2-9 -> 60K AB21; J2-7 -> AB22. 9600 8N1, independent of BL616.'),
            (b'IO_LOC "song_uart_tx" U15;', b'IO_LOC "song_uart_tx" AB21;'),
            (b'IO_LOC "song_uart_rx" V14;', b'IO_LOC "song_uart_rx" AB22;')]
    }
    for name, replacements in changes.items():
        p = R / name
        old = p.read_bytes()
        archive = E / 'before' / name
        archive.parent.mkdir(parents=True, exist_ok=True)
        archive.write_bytes(old)
        new = old
        for before, after in replacements:
            assert new.count(before) == 1, (name, before)
            new = new.replace(before, after, 1)
        p.write_bytes(new)
    manifest = {name: sha(R / name) for name in baseline['source_sha256']}
    (E / 'source_manifest.json').write_text(json.dumps(manifest, indent=2))
    (E / 'baseline.json').write_text(json.dumps({'source_sha256': baseline['source_sha256'],
        'baseline_certificate_sha256': sha(BASE / 'verification.json'),
        'baseline_fs_sha256': baseline['bitstream_sha256'], 'changed': list(changes)}, indent=2))
    project = str(R / 'gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj').replace('\\', '/')
    for prefix, command, label in [('build', 'syn', 'SYNTHESIS'), ('route', 'pnr', 'PNR')]:
        (E / (prefix + '.tcl')).write_text(f'open_project {project}\nif {{[catch {{run {command}}} message]}} {{puts stderr $message; exit 1}}\nputs {label}_TCL_FINISHED\nflush stdout\nexit\n')
    print('Prepared JDY-23: only UART divisor 434->5208 and pins U15/V14->AB21/AB22; baseline preserved')


if __name__ == '__main__': run()
