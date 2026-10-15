"""Create an immutable, separate Gowin workspace; never write the IDE's impl.

Run synthesis first, inspect resources, then invoke route.tcl in this workspace.
The manifest binds every RTL/ROM/constraint and the build scripts to this run.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
NAME = 'neo_guitar_touch_game'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    dest = args.destination.resolve()
    dest.relative_to(ROOT / 'build')
    assert not dest.exists(), 'Choose a new run directory; existing runs are preserved'
    workspace = dest / 'workspace'
    paths = [p for folder in ('rtl', 'mem', 'constraints') for p in (ROOT/folder).rglob('*')
             if p.is_file() and p.suffix in ('.v', '.vh', '.mem', '.json', '.sdc', '.cst')]
    paths += [ROOT/f'gowin/{NAME}/build.tcl', ROOT/f'gowin/{NAME}/{NAME}.gprj']
    hashes = {}
    for source in paths:
        relative = source.relative_to(ROOT)
        target = workspace/relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        hashes[relative.as_posix()] = digest(source)
    project = workspace/f'gowin/{NAME}'
    script = (project/'build.tcl').read_text()
    # Hold correction is a P&R default, verified from generated cmd.do.
    script = script.replace('run all', 'run syn')
    (project/'synth.tcl').write_text(script)
    (project/'route.tcl').write_text(script.replace('run syn', 'run pnr'))
    impl = project/'impl'
    impl.mkdir()
    # Read committed settings, never copy or change the user's local settings.
    config = f'gowin/{NAME}/impl/{NAME}_process_config.json'
    (impl/f'{NAME}_process_config.json').write_bytes(
        subprocess.check_output(['git', 'show', f'HEAD:{config}'], cwd=ROOT))
    protected = [config, 'docs/MPU6050_POSTURE_TIMBRE_DESIGN_PLAN.md']
    manifest = dict(base_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT).decode().strip(),
                    branch=subprocess.check_output(['git', 'branch', '--show-current'], cwd=ROOT).decode().strip(),
                    source_sha256=hashes,
                    build_scripts_sha256={p.name:digest(p) for p in [project/'synth.tcl', project/'route.tcl']},
                    protected_user_files_sha256={p:digest(ROOT/p) for p in protected},
                    project=str(project), status='prepared', processes=[])
    (dest/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(project)


if __name__ == '__main__':
    main()
