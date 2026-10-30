"""Bind completed APK build to unchanged inputs; do not recompile verified code."""
import hashlib
import json
from pathlib import Path
import zipfile

R=Path(__file__).resolve().parents[1]
E=R/'build/p5_bluetooth/jdy23/v1/android'
APP=R/'mobile/android/app/src/main'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def run():
    record=json.loads((E/'verification.json').read_text())
    apk=E/'xinxian_jdy23.apk'
    assert record['compiled'] and record['signature_verified'] and record['sha256']==sha(apk)
    inputs=sorted(p for p in APP.rglob('*') if p.is_file())
    assert all(p.stat().st_mtime<=apk.stat().st_mtime for p in inputs),'Source newer than completed APK'
    for p in (APP/'res').rglob('*'):
        if p.is_file():assert p.read_bytes()==(E/'res'/p.relative_to(APP/'res')).read_bytes()
    with zipfile.ZipFile(apk) as archive:
        for p in (E/'dex').glob('*.dex'):assert archive.read(p.name)==p.read_bytes()
    tested=json.loads((R/'build/jdy23/v1/android_test/verification.json').read_text())
    for name,digest in tested['actual_source_sha256'].items():
        assert sha(APP/'java/com/keyi/xinxian/guitar'/name)==digest
    record['source_sha256']={p.relative_to(R).as_posix():sha(p) for p in inputs}
    record['completed_build_inputs_unchanged']=True
    record['compiled_resources_and_dex_match']=True
    record['test_source_sha256_verified']=True
    (E/'verification.json').write_text(json.dumps(record,indent=2)+'\n')
    print('PASS: existing signed APK resources/dex match completed build; source input timestamps and actual tested class hashes match; no compile or test repeated')

if __name__=='__main__':run()
