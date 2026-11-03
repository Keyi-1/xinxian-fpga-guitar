"""Prepare an isolated Android 15 AVD under this worktree; preserve installed AVDs."""
from pathlib import Path
import hashlib
import json
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/companion_ui/emulator'
OUT.mkdir(parents=True,exist_ok=True)
metadata=urllib.request.urlopen('https://dl.google.com/android/repository/sys-img/android/sys-img2-3.xml',timeout=30).read()
package=next(p for p in ET.fromstring(metadata).findall('remotePackage')
             if p.attrib['path']=='system-images;android-35;default;x86_64')
complete=package.find('archives/archive/complete')
expected_size=int(complete.findtext('size'))
expected_hash=complete.findtext('checksum')
url='https://dl.google.com/android/repository/sys-img/android/'+complete.findtext('url')
archive=OUT/'system-image.zip'
def valid(path):
    if not path.exists() or path.stat().st_size!=expected_size:return False
    digest=hashlib.sha1()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b''):digest.update(chunk)
    return digest.hexdigest()==expected_hash
if not valid(archive):
    partial=OUT/'system-image.zip.part'
    with urllib.request.urlopen(url,timeout=60) as response, partial.open('wb') as target:
        total=0; reported=-1
        while chunk:=response.read(1024*1024):
            target.write(chunk);total+=len(chunk)
            percent=total*100//expected_size
            if percent//10!=reported:
                reported=percent//10;print(f'download {percent}%',flush=True)
    assert valid(partial),'Official archive checksum/length mismatch'
    partial.replace(archive)
system=OUT/'image/x86_64'
if not (system/'system.img').exists():
    with zipfile.ZipFile(archive) as z:
        destination=(OUT/'image').resolve()
        for entry in z.infolist():
            assert (destination/entry.filename).resolve().is_relative_to(destination)
        z.extractall(destination)
assert (system/'system.img').exists()
home=OUT/'avds'
avd=home/'companion_api35.avd'
avd.mkdir(parents=True,exist_ok=True)
(home/'companion_api35.ini').write_text('avd.ini.encoding=UTF-8\npath='+avd.as_posix()+'\ntarget=android-35\n',encoding='utf-8')
(avd/'config.ini').write_text('\n'.join([
    'AvdId=companion_api35','avd.ini.displayname=Companion UI API 35','avd.ini.encoding=UTF-8',
    'abi.type=x86_64','hw.cpu.arch=x86_64','hw.cpu.ncore=2','hw.ramSize=2048',
    'hw.lcd.width=1080','hw.lcd.height=2400','hw.lcd.density=420','hw.gpu.enabled=yes',
    'hw.gpu.mode=software','hw.keyboard=yes','hw.mainKeys=no','hw.audioInput=no',
    'hw.camera.back=none','hw.camera.front=none','hw.sdCard=no','disk.dataPartition.size=2G',
    'image.sysdir.1='+system.as_posix()+'/','tag.id=default','target=android-35',
    'fastboot.forceColdBoot=yes'])+'\n',encoding='utf-8')
(OUT/'verification.json').write_text(json.dumps(dict(url=url,size=expected_size,sha1=expected_hash,
    checksum_verified=True,avd_home=str(home),system_dir=str(system)),indent=2),encoding='utf-8')
print('isolated Android 15 AVD prepared',flush=True)
