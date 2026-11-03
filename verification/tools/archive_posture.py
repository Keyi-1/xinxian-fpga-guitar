"""Archive the fresh original-project P4 release; never overwrite old releases."""
from pathlib import Path
from datetime import datetime
import argparse
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT/'gowin/neo_guitar_touch_game'


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--name', default='p4_posture_20261018')
    args = parser.parse_args()
    assert re.fullmatch(r'[a-zA-Z0-9_-]+', args.name)
    cert = PROJECT/'p4_posture_verification.json'
    data = json.loads(cert.read_text(encoding='utf-8'))
    assert data['result'] == 'PASS' and data['artifact_scope']['kind'] == 'original_gprj_p4_posture_confirmed_rhythm_centred_ui'
    files = {}
    for key in ['source_sha256', 'artifacts_sha256', 'evidence_sha256', 'verification_tools_sha256']:
        for path, value in data[key].items():
            assert digest(ROOT/path) == value, ('Changed certified file', path)
            assert path not in files or files[path] == value
            files[path] = value
    releases = ROOT/'build/releases/touch_game'
    target = releases/args.name
    fs = releases/'neo_guitar_touch_game_p4_posture.fs'
    assert not target.exists() and not fs.exists(), 'Preserve all existing archives'
    target.mkdir(parents=True)

    def copy(source, dest):
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, dest)

    original = PROJECT/'impl/pnr/neo_guitar_touch_game.fs'
    assert digest(original) == data['bitstream_sha256']
    copy(original, fs)
    copy(cert, target/'verification.json')
    for path in files:
        copy(ROOT/path, target/'evidence'/path)
    for folder in ['tools', 'docs', 'scores/p2', 'build/p3_import/board_evidence','build/p4_posture/board_evidence','sim/reference/posture']:
        for source in (ROOT/folder).rglob('*'):
            if source.is_file() and source.suffix in ['.py', '.ps1', '.md', '.json', '.csv', '.bin', '.pdf', '.cst']:
                copy(source, target/'supplemental'/source.relative_to(ROOT))
    # Save the exact transformed simulation sources, old renderer snapshot and
    # dependency proof inputs so reusing a narrow historical proof stays auditable.
    for evidence_path in data['evidence_sha256']:
        if Path(evidence_path).name == 'verification.json':
            folder=(ROOT/evidence_path).parent
            for source in (folder/'sources').glob('*'):
                if source.is_file() and source.suffix in ['.v','.vh','.sv']:
                    copy(source,target/'evidence'/source.relative_to(ROOT))
    for reused in data.get('explicit_evidence_reuse',[]):
        for path,value in reused.get('source_sha256',{}).items():
            assert digest(ROOT/path)==value
            copy(ROOT/path,target/'evidence'/path)
    for path in ['AGENTS.md', 'gowin/neo_guitar_touch_game/README.md', 'gowin/neo_guitar_touch_game/hardware_acceptance.json']:
        copy(ROOT/path, target/'documentation'/path)
    started = datetime.fromisoformat(json.loads((ROOT/'build/p4_posture/impl_a2_centered/process.json').read_text(encoding='utf-8-sig'))['started']).timestamp()
    for source in (PROJECT/'impl/pnr').glob('*'):
        if source.is_file() and source.stat().st_mtime >= started and source.suffix in ['.html', '.txt', '.css', '.do', '.cfg', '.log']:
            copy(source, target/'reports'/source.name)
    record = dict(source_commit=data['validated_source_commit'], bitstream=fs.relative_to(ROOT).as_posix(),
        bitstream_sha256=digest(fs), verification_sha256=digest(cert),
        files_sha256={p.relative_to(target).as_posix(): digest(p) for p in target.rglob('*') if p.is_file()})
    (target/'archive.json').write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k: record[k] for k in ['source_commit', 'bitstream', 'bitstream_sha256', 'verification_sha256']}, indent=2))


if __name__ == '__main__':
    main()
