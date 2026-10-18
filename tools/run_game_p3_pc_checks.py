"""File-only Python regression evidence. This runner never opens a COM port."""
from pathlib import Path
from datetime import datetime
import hashlib
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    folder = ROOT/'build/p3_import/pc_checks'
    assert not folder.exists(), 'Preserve completed evidence'
    folder.mkdir(parents=True)
    sources = list((ROOT/'tools').glob('*.py'))
    sources += [p for p in (ROOT/'scores/p2').rglob('*') if p.is_file()]
    hashes = {p.relative_to(ROOT).as_posix(): digest(p) for p in sources}
    commands = [
        ['-m', 'unittest', 'test_game_fingering', 'test_game_score_v2',
         'test_qing_ge_user_score', 'test_import_p2_melody_midi', 'test_game_score_upload', '-v'],
        ['generate_game_p3_bsram.py', '--check']]
    logs = {}
    for i, command in enumerate(commands):
        result = subprocess.run([sys.executable]+command, cwd=ROOT/'tools', capture_output=True,
            env={**os.environ, 'PYTHONIOENCODING': 'utf-8'})
        log = folder/f'check_{i}.log'
        log.write_bytes(result.stdout+result.stderr)
        assert result.returncode == 0, log
        logs[log.relative_to(ROOT).as_posix()] = digest(log)
        print(log.read_text(encoding='utf-8').splitlines()[-1])
    for path, value in hashes.items():
        assert digest(ROOT/path) == value, path
    receipt = dict(result='PASS', scope='Python score/assignment/import/protocol files only; no hardware access',
        commands=commands, python=sys.executable, source_sha256=hashes, log_sha256=logs,
        generated_at=datetime.now().astimezone().isoformat())
    (folder/'verification.json').write_text(json.dumps(receipt, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
