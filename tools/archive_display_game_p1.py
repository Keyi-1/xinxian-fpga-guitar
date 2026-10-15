"""Archive a checked isolated P1 implementation without replacing prior releases."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parent.parent
NAME = 'neo_guitar_touch_game'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('run_dir', type=Path)
    parser.add_argument('--gate-dir', type=Path, default=ROOT/'sim/temp/display_game_p1_gate')
    args = parser.parse_args()
    run = args.run_dir.resolve()
    run.relative_to(ROOT/'build')
    project = run/f'workspace/gowin/{NAME}'
    gate = args.gate_dir.resolve()
    verification = json.loads((run/'verification.json').read_text())
    assert verification['result'] == 'PASS' and verification['artifact_scope']['kind'] == 'isolated_p1_build'
    for path, expected in verification['source_sha256'].items():
        assert digest(ROOT/path) == expected, ('source changed after check', path)
    pnr = project/'impl/pnr'
    fs = pnr/f'{NAME}.fs'
    assert digest(fs) == verification['bitstream_sha256']
    assert digest(project/f'impl/gwsynthesis/{NAME}.vg') == verification['netlist_sha256']
    for name, expected in verification['implementation_evidence_sha256'].items():
        assert digest(pnr/name) == expected, name
    assert digest(run/'manifest.json') == verification['build_manifest_sha256']
    assert digest(gate/'verification.json') == verification['gate_evidence_sha256']
    baseline_path = ROOT/'build/releases/touch_game/full_width_verification.json'
    baseline = json.loads(baseline_path.read_text(encoding='utf-8-sig'))
    baseline_fs = ROOT/'build/releases/touch_game/neo_guitar_touch_game_full_width.fs'
    assert digest(baseline_fs) == baseline['bitstream_sha256'] == '9c161ac673cd1c081831075f4f84d4ff2067f6a20797119b9a65d9623b770883'
    for directory, expected in [(ROOT/'sim/temp/touch_game', verification['rtl_evidence_sha256']),
                                (ROOT/'sim/temp/display_game_p1', verification['p1_evidence_sha256'])]:
        assert digest(directory/'verification.json') == expected, directory
    release_root = ROOT/'build/releases/touch_game'
    release = release_root/'p1_display_opt'
    bitstream = release_root/f'{NAME}_p1_display_opt.fs'
    assert not release.exists() and not bitstream.exists(), 'Do not overwrite an existing release'
    release.mkdir(parents=True)
    shutil.copy2(fs, bitstream)
    files = [(run/'verification.json', 'build_verification.json'), (run/'manifest.json', 'build_manifest.json')]
    files.append((baseline_path, 'baseline_full_width_verification.json'))
    files += [(ROOT/'docs/DISPLAY_GAME_P1_RESOURCE_OPT.md', 'DISPLAY_GAME_P1_RESOURCE_OPT.md'),
              (ROOT/f'gowin/{NAME}/README.md', 'README.md'),
              (ROOT/f'gowin/{NAME}/hardware_acceptance.json', 'hardware_acceptance.json')]
    files += [(p, 'build/'+p.name) for p in run.glob('*.log')]
    files += [(p, 'synthesis/'+p.name) for p in (project/'impl/gwsynthesis').iterdir()
              if p.suffix in ('.vg', '.xml', '.html', '.prj')]
    files += [(p, 'pnr/'+p.name) for p in pnr.iterdir()
              if p.suffix in ('.log', '.txt', '.html', '.cfg', '.do', '.sdc')]
    for folder, label in [(ROOT/'sim/temp/touch_game', 'rtl'),
                          (ROOT/'sim/temp/display_game_p1', 'display_rtl'), (gate, 'gate')]:
        files += [(p, label+'/'+p.name) for p in folder.iterdir()
                  if p.suffix in ('.log', '.json', '.sv', '.vh')]
    for source, relative in files:
        target = release/relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    tracked = subprocess.check_output(['git', 'ls-files'], cwd=ROOT).decode().splitlines()
    selected = [p for p in tracked if p.startswith(('rtl/', 'mem/', 'constraints/', 'tools/', 'sim/tb/',
                 'sim/reference/display_game_p1/')) or p in (
                     'docs/DISPLAY_GAME_P1_RESOURCE_OPT.md', f'gowin/{NAME}/build.tcl',
                     f'gowin/{NAME}/{NAME}.gprj', f'gowin/{NAME}/run_gate_check.ps1',
                     f'gowin/{NAME}/check_result.py')]
    with zipfile.ZipFile(release/'source_snapshot.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for relative in selected:
            archive.write(ROOT/relative, relative)
        manifest = json.loads((run/'manifest.json').read_text(encoding='utf-8-sig'))
        for name in manifest['build_scripts_sha256']:
            archive.write(project/name, f'gowin/{NAME}/{name}')
        cfg = f'impl/{NAME}_process_config.json'
        archive.write(project/cfg, f'gowin/{NAME}/{cfg}')
    verification.update(source_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT).decode().strip(),
        stage_status='P1_MARGIN_TARGETS_MET' if verification['margin_targets_met'] else 'P1_STAGE_VALIDATED_MARGIN_TARGETS_PENDING',
        artifact_scope=dict(kind='archived_p1_release', reference_bitstream=bitstream.relative_to(ROOT).as_posix(),
                            reference_verification=(release/'verification.json').relative_to(ROOT).as_posix(),
                            note='Independent P1 release; original full-width release and user IDE impl preserved; hardware feedback pending'),
        comparison_to_archived_full_width=dict(
            verification_sha256=digest(baseline_path), bitstream_sha256=digest(baseline_fs),
            resources={key:dict(before=baseline['resources'][key], after=verification['resources'][key],
                               delta=verification['resources'][key]['used']-baseline['resources'][key]['used'])
                       for key in verification['resources']},
            clocks={key:dict(before=baseline['clocks'][key], after=verification['clocks'][key])
                    for key in verification['clocks']}),
        archived_evidence_sha256={p.relative_to(release).as_posix():digest(p) for p in release.rglob('*') if p.is_file()})
    (release/'verification.json').write_text(json.dumps(verification, indent=2)+'\n')
    shutil.copy2(release/'verification.json', ROOT/f'gowin/{NAME}/verification.json')
    print(json.dumps(dict(bitstream=str(bitstream), sha256=digest(bitstream), verification=str(release/'verification.json'),
                         margin_targets_met=verification['margin_targets_met']), indent=2))


if __name__ == '__main__':
    main()
