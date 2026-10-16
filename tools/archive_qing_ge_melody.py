"""Archive the certified original-project melody without replacing releases."""
from pathlib import Path
import argparse
from datetime import datetime
import hashlib
import json
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT/'gowin/neo_guitar_touch_game'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--name', default='qing_ge_melody_20261016')
    args = parser.parse_args()
    assert re.fullmatch(r'[a-zA-Z0-9_-]+', args.name)
    cert = PROJECT/'p2_qing_ge_melody_verification.json'
    data = json.loads(cert.read_text(encoding='utf-8'))
    assert data['result'] == 'PASS' and data['artifact_scope']['kind'] == 'original_gprj_qing_ge_user_melody'
    all_sources = dict(data['source_sha256'])
    previous_sources = {}

    def merge_source(path, value):
        path = path.replace('\\', '/')
        if path in all_sources and all_sources[path] != value:
            assert path == data['ui_revision']['only_changed_runtime_source']
            original = subprocess.check_output(['git','show',f"{data['ui_revision']['reference_commit']}:{path}"],cwd=ROOT)
            assert hashlib.sha256(original).hexdigest() == value
            previous_sources[path] = original
        else:
            all_sources[path] = value
    for field in ['artifacts_sha256', 'evidence_sha256', 'verification_tools_sha256', 'preserved_assets_sha256']:
        for path, value in data[field].items():
            assert digest(ROOT/path) == value, ('changed certified artifact', path)
    for path in data['evidence_sha256']:
        if Path(path).name != 'verification.json':
            continue
        proof = json.loads((ROOT/path).read_text(encoding='utf-8-sig'))
        for source, value in proof.get('source_sha256', {}).items():
            merge_source(source, value)
    for key in ['standard_gate', 'extra_gate', 'seek_gate', 'title_pixel_proof']:
        for path, value in data[key]['source_sha256'].items():
            merge_source(path, value)
    all_sources.update(data['verification_tools_sha256'])
    for path, value in all_sources.items():
        assert digest(ROOT/path) == value, ('changed verified source', path)
    fs = PROJECT/'impl/pnr/neo_guitar_touch_game.fs'
    assert digest(fs) == data['bitstream_sha256']
    vg = PROJECT/'impl/gwsynthesis/neo_guitar_touch_game.vg'
    assert digest(vg) == data['netlist_sha256']
    releases = ROOT/'build/releases/touch_game'
    directory = releases/args.name
    output = releases/'neo_guitar_touch_game_qing_ge_melody.fs'
    assert not directory.exists() and not output.exists(), 'Never overwrite existing releases'
    directory.mkdir(parents=True)

    def copy(source, target):
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)

    copy(fs, output)
    assert digest(output) == data['bitstream_sha256']
    copy(cert, directory/'verification.json')
    copy(vg, directory/'netlist/neo_guitar_touch_game.vg')
    for path in all_sources:
        copy(ROOT/path, directory/'source'/path)
    for path, content in previous_sources.items():
        target = directory/'source_before_title'/path
        target.parent.mkdir(parents=True, exist_ok=True);target.write_bytes(content)
    for path in set(data['artifacts_sha256']) | set(data['evidence_sha256']):
        if Path(path).suffix not in ['.fs', '.vg']:
            copy(ROOT/path, directory/'evidence'/path)
    for base in ['scores/p2', 'build/qing_ge_melody/impl_m1', data['actual_synthesis_run']]:
        for path in (ROOT/base).rglob('*'):
            if path.is_file() and path.suffix in ['.json', '.jpg', '.png', '.csv', '.bin', '.log', '.tcl', '.ps1']:
                copy(path, directory/'supplemental'/path.relative_to(ROOT))
    started = datetime.fromisoformat(json.loads((ROOT/data['actual_synthesis_run']/'build_process.json').read_text(encoding='utf-8-sig'))['started']).timestamp()
    for path in (PROJECT/'impl/pnr').glob('*'):
        if path.is_file() and path.stat().st_mtime >= started and path.suffix in ['.html', '.txt', '.css', '.do', '.cfg']:
            copy(path, directory/'reports'/path.name)
    for relative in ['AGENTS.md', 'docs/QING_GE_USER_MELODY.md',
                     'gowin/neo_guitar_touch_game/README.md',
                     'gowin/neo_guitar_touch_game/hardware_acceptance.json']:
        copy(ROOT/relative, directory/'documentation'/relative)
    # Gate run/process records and previews are useful for interruption audit.
    proof_dirs = {Path(p).parent for p in data['evidence_sha256'] if Path(p).name == 'verification.json'}
    for folder in proof_dirs:
        for path in (ROOT/folder).glob('*'):
            if path.is_file() and path.suffix in ['.json', '.log', '.ppm', '.sv', '.vh']:
                copy(path, directory/'runs'/folder/path.name)
    record = dict(source_commit=data['validated_source_commit'],
        archival_commit_parent=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        artifact_scope=data['artifact_scope'], bitstream=str(output.relative_to(ROOT)).replace('\\', '/'),
        bitstream_sha256=digest(output), verification_sha256=digest(cert),
        source_sha256=all_sources,
        pre_title_source_sha256={path:hashlib.sha256(content).hexdigest() for path,content in previous_sources.items()},
        files_sha256={p.relative_to(directory).as_posix(): digest(p) for p in directory.rglob('*') if p.is_file()})
    (directory/'archive.json').write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k: record[k] for k in ['source_commit', 'bitstream', 'bitstream_sha256', 'verification_sha256']}, indent=2))


if __name__ == '__main__':
    main()
