"""Bind delivered app packages to the tested sources and actual emulator binary."""
from pathlib import Path
import hashlib
import json
import subprocess
import zipfile

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/companion_ui'
def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def main():
    android_dir=ROOT/'build/releases/android/xinxian_jdy23_0.3.0'
    apk=android_dir/'xinxian_jdy23_0.3.0.apk'
    android=read(android_dir/'verification.json')
    emulator=read(OUT/'android_os/verification.json')
    library=read(OUT/'checks/verification.json')
    ble=read(ROOT/'build/jdy23/v1/android_test/verification.json')
    assert digest(apk)==android['sha256']==emulator['installed_apk_sha256']
    for proof in (android,library):
        for relative,sha in proof['source_sha256'].items():assert digest(ROOT/relative)==sha,relative
    for relative,sha in emulator['test_source_sha256'].items():assert digest(ROOT/relative)==sha,relative
    java=ROOT/'mobile/android/app/src/main/java/com/keyi/xinxian/guitar'
    for name,sha in ble['actual_source_sha256'].items():assert digest(java/name)==sha,name
    assert all(v['result']=='PASS' for v in emulator['scenarios'].values())
    assert len(emulator['scenarios'])==5
    assert ble['result']==library['result']=='PASS'
    app_dir=ROOT/'build/releases/windows/FPGA_Guitar_Uploader_1.2.0/FPGA_Guitar_Uploader'
    windows_zip=ROOT/'build/releases/windows/FPGA_Guitar_Uploader_1.2.0.zip'
    manifest=read(app_dir/'manifest.json')
    for relative,sha in manifest['source_hashes'].items():assert digest(ROOT/relative)==sha,relative
    for relative,sha in manifest['files'].items():assert digest(app_dir/relative)==sha,relative
    with zipfile.ZipFile(windows_zip) as archive:
        assert archive.testzip() is None
        for relative,sha in manifest['files'].items():
            assert hashlib.sha256(archive.read('FPGA_Guitar_Uploader/'+relative)).hexdigest()==sha,relative
    smoke=read(OUT/'frozen_final/smoke.json')
    assert smoke['passed'] and smoke['frozen'] and not smoke['physical_com_opened']
    desktop_tests=read(OUT/'windows_checks/verification.json')
    assert desktop_tests['result']=='PASS' and desktop_tests['tests_run']>=34
    for relative,sha in desktop_tests['source_sha256'].items():assert digest(ROOT/relative)==sha,relative
    with zipfile.ZipFile(app_dir/'对应源代码.zip') as archive:
        assert archive.testzip() is None
        for relative,sha in manifest['source_hashes'].items():assert hashlib.sha256(archive.read(relative)).hexdigest()==sha
    assert not subprocess.check_output(['git','diff','HEAD','--','rtl','gowin','constraints','firmware'],cwd=ROOT).strip()
    assert subprocess.check_output(['git','branch','--show-current'],cwd=ROOT,text=True).strip()=='feat/companion-ui'
    signer=Path('S:/AndroidSoftWare/JDK_Version/bin/java.exe')
    sign_tool=Path('S:/Software/AndroidSDK/build-tools/35.0.1/lib/apksigner.jar')
    new_cert=subprocess.check_output([str(signer),'-jar',str(sign_tool),'verify','--print-certs',str(apk)],text=True,encoding='utf-8',errors='replace')
    (OUT/'android-signature.txt').write_text(new_cert,encoding='utf-8')
    old_apk=Path('T:/Documents/AMD/xinxian-fpga-guitar/build/p5_bluetooth/jdy23/v1/android/xinxian_jdy23.apk')
    compatible=None
    if old_apk.exists():
        old_cert=subprocess.check_output([str(signer),'-jar',str(sign_tool),'verify','--print-certs',str(old_apk)],text=True,encoding='utf-8',errors='replace')
        def fingerprint(text):return next(line for line in text.splitlines() if 'certificate SHA-256 digest:' in line)
        compatible=fingerprint(old_cert)==fingerprint(new_cert)
        assert compatible,'Signing identity changed'
    record=dict(result='PASS',branch='feat/companion-ui',android_apk=str(apk),android_sha256=digest(apk),
        android_api35_checks=sum(v['checks'] for v in emulator['scenarios'].values()),
        android_scenarios=list(emulator['scenarios']),android_same_signer_as_previous=compatible,
        windows_zip=str(windows_zip),windows_sha256=digest(windows_zip),
        windows_regression_cases=desktop_tests['tests_run'],windows_frozen_smoke=True,package_files_and_source_hashes_verified=True,
        fpga_sources_unchanged=True,physical_hardware_tested=False,committed=False,pushed=False)
    (OUT/'verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(record,ensure_ascii=False))

if __name__=='__main__':main()
