# SPDX-License-Identifier: Apache-2.0
"""Add licensing companions without altering accepted binaries or frozen archives."""
from pathlib import Path
import hashlib
import io
import json
import zipfile

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'releases/windows/FPGA_Guitar_Uploader_1.2.0.zip'
LICENSED=ROOT/'releases/windows/FPGA_Guitar_Uploader_1.2.0_licensed.zip'
NOTICES=ROOT/'releases/license_notices_20261104.zip'
BASE_SHA='6410a8ca7dc1b3f2a980dfe69185711e249beca9711b3bc64b15df6a4605437e'

def sha(raw):return hashlib.sha256(raw).hexdigest()

def legal_files():
    names=['LICENSE','LICENSING.md','COPYRIGHT.md','NOTICE','THIRD_PARTY_NOTICES.md',
           'tools/windows_score_uploader/LICENSE',
           'tools/windows_score_uploader/LICENSING.md',
           'tools/windows_score_uploader/THIRD_PARTY_NOTICES.txt']
    names += [p.relative_to(ROOT).as_posix() for p in (ROOT/'LICENSES').rglob('*') if p.is_file()]
    return {name:(ROOT/name).read_bytes() for name in sorted(names)}

def main():
    assert sha(BASE.read_bytes())==BASE_SHA,'Accepted Windows package differs'
    if LICENSED.exists() or NOTICES.exists():
        raise SystemExit('Licensing companions already exist; preserve them rather than overwrite.')
    legal=legal_files()
    published={}
    for line in (ROOT/'releases/SHA256SUMS').read_text(encoding='utf-8').splitlines():
        digest,name=line.split('  ',1)
        assert sha((ROOT/'releases'/name).read_bytes())==digest,name
        published[name]=digest
    with zipfile.ZipFile(NOTICES,'w',zipfile.ZIP_DEFLATED) as z:
        for name,raw in legal.items():z.writestr(name,raw)
        z.writestr('artifact_sha256.json',json.dumps(published,indent=2)+'\n')
    prefix='FPGA_Guitar_Uploader/'
    with zipfile.ZipFile(BASE) as old:
        original_source=old.read(prefix+'对应源代码.zip')
        buffer=io.BytesIO()
        with zipfile.ZipFile(io.BytesIO(original_source)) as src, zipfile.ZipFile(buffer,'w',zipfile.ZIP_DEFLATED) as licensed_src:
            for item in src.infolist():licensed_src.writestr(item,src.read(item.filename))
            present=set(src.namelist())
            for name,raw in legal.items():
                if name in present:
                    assert src.read(name)==raw,name
                else:licensed_src.writestr(name,raw)
        extras={prefix+'LICENSE.txt':legal['tools/windows_score_uploader/LICENSE'],
                prefix+'对应源代码-含许可.zip':buffer.getvalue()}
        for name in ('LICENSING.md','COPYRIGHT.md','NOTICE'):
            extras[prefix+name]=legal[name]
        extras[prefix+'THIRD_PARTY_COMPONENTS.md']=legal['THIRD_PARTY_NOTICES.md']
        for name,raw in legal.items():
            if name.startswith('LICENSES/'):
                extras[prefix+'project_licenses/'+name[len('LICENSES/'):]]=raw
        manifest=dict(date='2026-11-04',base_archive=BASE.name,base_sha256=BASE_SHA,
            original_files_sha256={n:sha(old.read(n)) for n in old.namelist() if not n.endswith('/')},
            added_files_sha256={n:sha(b) for n,b in extras.items()},runtime_rebuilt=False,
            scope='Original program and source ZIP bytes preserved; license notices added. Third-party asset/IP exceptions remain.')
        extras[prefix+'licensing_manifest.json']=(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
        assert not set(extras).intersection(old.namelist())
        with zipfile.ZipFile(LICENSED,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
            for item in old.infolist():z.writestr(item,old.read(item.filename))
            for name,raw in extras.items():z.writestr(name,raw)
    for path in (NOTICES,LICENSED):
        with zipfile.ZipFile(path) as z:assert z.testzip() is None,path.name
        published[path.relative_to(ROOT/'releases').as_posix()]=sha(path.read_bytes())
    (ROOT/'releases/SHA256SUMS').write_bytes(''.join(f'{h}  {n}\n' for n,h in sorted(published.items())).encode('utf-8'))
    print(json.dumps({'notices':NOTICES.name,'windows':LICENSED.name,'original_windows_unchanged':sha(BASE.read_bytes())==BASE_SHA,'release_hashes':len(published)}))

if __name__=='__main__':main()
