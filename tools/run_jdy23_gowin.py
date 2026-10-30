"""Run the original guitar project once per stage; no flashing or config changes."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import subprocess

R = Path(__file__).resolve().parents[1]
E = R / 'build/jdy23/v1'
P = R / 'gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj'


def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--stage', choices=('Synthesis', 'Route'), required=True)
    stage = parser.parse_args().stage
    prefix = 'build' if stage == 'Synthesis' else 'route'
    receipt = E / ('process.json' if stage == 'Synthesis' else 'route_process.json')
    assert not receipt.exists(), 'Inspect previous attempt, never restart blindly'
    for name, digest in json.loads((E / 'source_manifest.json').read_text()).items():
        assert sha(R / name) == digest, name
    if stage == 'Route':
        check = json.loads((E / 'synthesis_review.json').read_text())
        assert check['result'] == 'PASS'
        assert sha(P.parent / 'impl/gwsynthesis/neo_guitar_touch_game.vg') == check['netlist_sha256']
    tool = 'S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe'
    with (E / (prefix + '.stdout.log')).open('xb') as out, (E / (prefix + '.stderr.log')).open('xb') as err:
        proc = subprocess.Popen([tool, str(E / (prefix + '.tcl'))], cwd=P.parent, stdout=out, stderr=err,
            creationflags=subprocess.CREATE_NO_WINDOW)
        record = {'status': 'RUNNING', 'stage': stage, 'pid': proc.pid,
            'started': datetime.now().astimezone().isoformat(), 'project': str(P),
            'launcher_sha256': sha(Path(__file__))}
        receipt.write_text(json.dumps(record, indent=2))
        print(f'JDY-23 original project {stage}: PID={proc.pid}', flush=True)
        code = proc.wait()
        record.update(status='EXITED', exit_code=code, finished=datetime.now().astimezone().isoformat())
        receipt.write_text(json.dumps(record, indent=2))
    raise SystemExit(code)


if __name__ == '__main__': main()
