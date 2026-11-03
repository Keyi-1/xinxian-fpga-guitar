"""Build a portable Windows x64 folder/ZIP without touching FPGA outputs."""
import hashlib
import importlib.metadata
import json
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from windows_score_uploader import VERSION


def sources():
    files = [Path('tools/run_windows_score_uploader.py'), Path('tools/build_windows_score_uploader.py'),
             Path('docs/WINDOWS_SCORE_UPLOADER.md')]
    files += [Path('tools')/name for name in ('game_score_upload.py', 'game_score_v2.py', 'game_fingering.py')]
    files += [p.relative_to(ROOT) for p in (ROOT/'tools/windows_score_uploader').rglob('*')
              if p.is_file() and '__pycache__' not in p.parts]
    return sorted(set(files))


def main():
    if sys.platform != 'win32' or sys.maxsize < 2**32:
        raise SystemExit('Build on Windows x64 with the pinned build requirements.')
    out = ROOT/'build/releases/windows'/f'FPGA_Guitar_Uploader_{VERSION}'
    work = ROOT/'build/windows_uploader/pyinstaller'/VERSION
    out.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)
    with (work/'build.log').open('w', encoding='utf-8') as log:
        subprocess.run([sys.executable, '-m', 'PyInstaller', '--noconfirm',
            '--distpath', str(out), '--workpath', str(work),
            str(ROOT/'tools/windows_score_uploader/uploader.spec')],
            cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    app = out/'FPGA_Guitar_Uploader'
    shutil.copytree(ROOT/'tools/windows_score_uploader/examples', app/'示例曲谱', dirs_exist_ok=True)
    shutil.copy2(ROOT/'docs/WINDOWS_SCORE_UPLOADER.md', app/'使用说明.md')
    shutil.copy2(ROOT/'tools/windows_score_uploader/开始使用.txt', app/'开始使用.txt')
    shutil.copy2(ROOT/'tools/windows_score_uploader/THIRD_PARTY_NOTICES.txt', app/'THIRD_PARTY_NOTICES.txt')
    licenses = app/'licenses'
    licenses.mkdir(exist_ok=True)
    for name in ('PyQt5-Qt5', 'PyQt5-sip'):
        dist = importlib.metadata.distribution(name)
        for file in dist.files:
            if 'LICENSE' in file.name:
                shutil.copy2(dist.locate_file(file), licenses/(name+'_'+file.name))
    # GPL text supplied by the installed PyQt5-sip distribution, also applicable
    # to the PyQt5 open source license identified in its package metadata.
    shutil.copy2(licenses/'PyQt5-sip_LICENSE-GPL3', licenses/'PyQt5_LICENSE-GPL3.txt')
    python_license = next((Path(sys.base_prefix)/name for name in ('LICENSE.txt', 'LICENSE_PYTHON.txt')
                           if (Path(sys.base_prefix)/name).exists()), None)
    if python_license is None:
        raise FileNotFoundError('Python runtime license not found; preserve its license in the portable build.')
    shutil.copy2(python_license, licenses/'Python_LICENSE.txt')
    source_hashes = {}
    with zipfile.ZipFile(app/'对应源代码.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for relative in sources():
            raw = (ROOT/relative).read_bytes()
            source_hashes[relative.as_posix()] = hashlib.sha256(raw).hexdigest()
            archive.writestr(relative.as_posix(), raw)
    manifest = dict(version=VERSION, platform='Windows x64',
        source_head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
        source_hashes=source_hashes,
        dependencies={name:importlib.metadata.version(name) for name in
                      ('PyQt5', 'PyQt5-Qt5', 'PyQt5-sip', 'pyserial', 'pyinstaller', 'pyinstaller-hooks-contrib')},
        files={p.relative_to(app).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
               for p in sorted(app.rglob('*')) if p.is_file() and p.name != 'manifest.json'})
    (app/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    zip_path = out.parent / (out.name + '.zip')
    with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(app.rglob('*')):
            if path.is_file():
                archive.write(path, path.relative_to(out))
    print(json.dumps(dict(folder=str(app), zip=str(zip_path),
        sha256=hashlib.sha256(zip_path.read_bytes()).hexdigest()), ensure_ascii=False))


if __name__ == '__main__':
    main()
