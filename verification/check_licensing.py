"""Check license scope, complete package overlays, and immutable accepted payloads."""
from pathlib import Path
import hashlib
import io
import json
import zipfile

ROOT=Path(__file__).resolve().parents[1]
def sha(raw):return hashlib.sha256(raw).hexdigest()

def main():
    assert (ROOT/'LICENSE').read_bytes()==(ROOT/'LICENSES/Apache-2.0.txt').read_bytes()
    assert (ROOT/'tools/windows_score_uploader/LICENSE').read_bytes()==(ROOT/'LICENSES/GPL-3.0-only.txt').read_bytes()
    scope=(ROOT/'LICENSING.md').read_text(encoding='utf-8')
    for marker in ['ks_compute_pll.v','game_font_16.mem','GPL-3.0-only','Apache-2.0']:
        assert marker in scope,marker
    base=ROOT/'releases/windows/FPGA_Guitar_Uploader_1.2.0.zip'
    assert sha(base.read_bytes())=='6410a8ca7dc1b3f2a980dfe69185711e249beca9711b3bc64b15df6a4605437e'
    prefix='FPGA_Guitar_Uploader/'
    with zipfile.ZipFile(base) as old, zipfile.ZipFile(ROOT/'releases/windows/FPGA_Guitar_Uploader_1.2.0_licensed.zip') as new:
        assert new.testzip() is None
        for name in old.namelist():assert old.read(name)==new.read(name),name
        record=json.loads(new.read(prefix+'licensing_manifest.json'))
        for name,digest in record['original_files_sha256'].items():assert sha(new.read(name))==digest,name
        for name,digest in record['added_files_sha256'].items():assert sha(new.read(name))==digest,name
        assert new.read(prefix+'LICENSE.txt')==(ROOT/'LICENSES/GPL-3.0-only.txt').read_bytes()
        with zipfile.ZipFile(io.BytesIO(old.read(prefix+'对应源代码.zip'))) as old_src, zipfile.ZipFile(io.BytesIO(new.read(prefix+'对应源代码-含许可.zip'))) as new_src:
            assert new_src.testzip() is None
            for name in old_src.namelist():assert old_src.read(name)==new_src.read(name),name
            for name in ('LICENSE','LICENSING.md','COPYRIGHT.md','NOTICE','THIRD_PARTY_NOTICES.md',
                         'tools/windows_score_uploader/LICENSE','LICENSES/third_party/source_downloads.json'):
                assert name in new_src.namelist(),name
            source_count=len(old_src.namelist())
        preserved=len(record['original_files_sha256'])
    with zipfile.ZipFile(ROOT/'releases/license_notices_20261104.zip') as z:
        assert z.testzip() is None
        for name,digest in json.loads(z.read('artifact_sha256.json')).items():
            assert sha((ROOT/'releases'/name).read_bytes())==digest,name
    result=dict(result='PASS',original_windows_members_preserved=preserved,
                original_source_members_preserved=source_count,executable_and_dlls_unchanged=True,
                standard_licenses_match=True,third_party_ip_music_font_exceptions_explicit=True)
    out=ROOT/'verification/results';out.mkdir(parents=True,exist_ok=True)
    (out/'licensing_check.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result))

if __name__=='__main__':main()
