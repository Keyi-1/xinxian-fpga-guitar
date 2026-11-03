"""Verify the organized checkout without rebuilding or touching hardware."""
from pathlib import Path
import hashlib
import json
import re
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def source_matches(path, expected):
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() == expected:
        return True
    # Historical client packages were built in a different Windows checkout.
    # Accept only an exact LF/CRLF conversion of text, never binary or other edits.
    if path.suffix not in ('.py', '.java', '.xml', '.xgscore', '.txt', '.spec'):
        return False
    lf = raw.replace(b'\r\n', b'\n')
    return expected in (hashlib.sha256(lf).hexdigest(),
                        hashlib.sha256(lf.replace(b'\n', b'\r\n')).hexdigest())

def main():
    frozen = json.loads((ROOT/'releases/fpga/source_manifest.json').read_text(encoding='utf-8'))['files']
    for name, expected in frozen.items():
        assert sha(ROOT/name) == expected, f'Production input differs: {name}'
    assert len(frozen) == 140
    for folder in ('rtl', 'constraints', 'mem'):
        actual = {p.relative_to(ROOT).as_posix() for p in (ROOT/folder).rglob('*') if p.is_file()}
        assert actual == {n for n in frozen if n.startswith(folder+'/')}, folder
    project = ROOT/'gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj'
    enabled = 0
    for item in ET.parse(project).findall('.//File'):
        if item.get('enable', '1') != '1':
            continue
        path = (project.parent/item.attrib['path']).resolve()
        assert path.is_relative_to(ROOT) and path.is_file(), item.attrib['path']
        assert path.relative_to(ROOT).as_posix() in frozen
        enabled += 1
    archive_count = 0
    relocation = json.loads((ROOT/'verification/organization/relocations.json').read_text(encoding='utf-8'))
    for entry in relocation['files']:
        assert sha(ROOT/entry['to']) == entry['sha256'], entry['to']
        archive_count += 1
    release_count = 0
    for line in (ROOT/'releases/SHA256SUMS').read_text(encoding='utf-8').splitlines():
        expected, name = line.split('  ', 1)
        assert sha(ROOT/'releases'/name) == expected, name
        release_count += 1
    assert sha(ROOT/'releases/fpga/neo_guitar_touch_game.fs') == 'd0b0cee2425e11b0b0ec6720132c80bdaf9b2a5224d5974e321e01db0bdcb763'
    with zipfile.ZipFile(ROOT/'releases/fpga/source_code_140_files.zip') as z:
        assert z.testzip() is None and set(z.namelist()) == set(frozen)
        for name, expected in frozen.items():
            assert hashlib.sha256(z.read(name)).hexdigest() == expected, name
    receipt = json.loads((ROOT/'verification/build/releases/android/xinxian_jdy23_0.3.0/verification.json').read_text(encoding='utf-8'))
    android_count = 0
    for name, expected in receipt['source_sha256'].items():
        assert source_matches(ROOT/name, expected), name
        android_count += 1
    with zipfile.ZipFile(ROOT/'releases/windows/FPGA_Guitar_Uploader_1.2.0.zip') as z:
        manifest = json.loads(z.read('FPGA_Guitar_Uploader/manifest.json'))
        runtime = {n: h for n, h in manifest['source_hashes'].items()
                   if n.startswith('tools/windows_score_uploader/') or n in (
                       'tools/run_windows_score_uploader.py', 'tools/game_fingering.py',
                       'tools/game_score_upload.py', 'tools/game_score_v2.py')}
        for name, expected in runtime.items():
            assert source_matches(ROOT/name, expected), name
    link_count = 0
    pages = [ROOT/'README.md', ROOT/'releases/README.md', ROOT/'mobile/android/README.md',
             ROOT/'gowin/neo_guitar_touch_game/README.md']
    pages += [p for p in (ROOT/'docs').glob('*.md') if p.name != 'MPU6050_POSTURE_TIMBRE_DESIGN_PLAN.md']
    for page in pages:
        content = page.read_text(encoding='utf-8')
        links = re.findall(r'\]\(([^)]+)\)', content) + re.findall(r'src="([^"]+)"', content)
        for target in links:
            if target.startswith(('http:', 'https:', '#')):
                continue
            assert (page.parent/target.split('#')[0]).resolve().exists(), (page.name, target)
            link_count += 1
    result = dict(result='PASS', fpga_inputs=len(frozen), enabled_gprj_entries=enabled,
                  relocated_files=archive_count, release_files=release_count,
                  android_runtime_inputs=android_count, windows_runtime_inputs=len(runtime), local_links=link_count)
    out = ROOT/'verification/results'
    out.mkdir(parents=True, exist_ok=True)
    (out/'repository_check.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result))

if __name__ == '__main__':
    main()
