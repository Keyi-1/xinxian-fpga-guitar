"""Actual UI smoke in the dedicated worktree AVD; never selects a physical device."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import time

ROOT=Path(__file__).resolve().parents[1]
ADB=Path('S:/Software/AndroidSDK/platform-tools/adb.exe')
APK=ROOT/'build/releases/android/xinxian_jdy23_0.3.0/xinxian_jdy23_0.3.0.apk'
TEST=ROOT/'build/companion_ui/instrumentation/companion_ui_test.apk'
PACKAGE='com.keyi.xinxian.guitar.jdy23'
OUT=ROOT/'build/companion_ui/android_os'
OUT.mkdir(parents=True,exist_ok=True)
def adb(*args,timeout=90):
    result=subprocess.run([str(ADB),'-P','5041','-s','emulator-5580',*args],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=timeout)
    if result.returncode:raise RuntimeError(result.stdout+result.stderr)
    return result.stdout

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--scenarios',default='normal,compact,large_font,landscape,cutout')
    scenarios=parser.parse_args().scenarios.split(',')
    assert adb('shell','getprop','ro.kernel.qemu').strip()=='1','Not an emulator'
    assert adb('shell','getprop','ro.build.version.sdk').strip()=='35','Wrong test OS'
    build=json.loads((APK.parent/'verification.json').read_text(encoding='utf-8'))
    for path,digest in build['source_sha256'].items():assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest,path
    print(adb('install','-r',str(APK)).strip(),flush=True)
    print(adb('install','-r',str(TEST)).strip(),flush=True)
    installed=adb('shell','pm','path',PACKAGE).strip().removeprefix('package:')
    installed_hash=adb('shell','sha256sum',installed).split()[0]
    assert installed_hash==hashlib.sha256(APK.read_bytes()).hexdigest()
    configs={'normal':('1080x2400','420','1.0'), 'compact':('720x1280','320','1.0'),
             'large_font':('1080x2400','420','1.5'), 'landscape':('1920x1080','320','1.0'),
             'cutout':('1080x2400','420','1.0')}
    results={}
    try:
        for name in scenarios:
            size,density,font=configs[name]
            adb('shell','am','force-stop',PACKAGE)
            adb('shell','wm','size',size);adb('shell','wm','density',density)
            adb('shell','settings','put','system','font_scale',font)
            adb('shell','cmd','overlay','disable','com.android.internal.display.cutout.emulation.hole')
            if name=='cutout':adb('shell','cmd','overlay','enable','com.android.internal.display.cutout.emulation.hole')
            adb('shell','wm','dismiss-keyguard');time.sleep(.4)
            log=adb('shell','am','instrument','-w','-r','-e','scenario',name,'com.keyi.xinxian.guitar.uitest/com.keyi.xinxian.uitest.UiProbe')
            (OUT/(name+'.log')).write_text(log,encoding='utf-8')
            assert 'INSTRUMENTATION_RESULT: result=PASS' in log,log
            checks=int(log.split('INSTRUMENTATION_RESULT: checks=')[1].splitlines()[0])
            for screen in ('library','upload'):
                adb('pull',f'/sdcard/Android/data/{PACKAGE}/files/{name}_{screen}.png',str(OUT/f'{name}_{screen}.png'))
            results[name]=dict(result='PASS',checks=checks,size=size,density=density,font_scale=font)
            print(name+': PASS, '+str(checks)+' checks',flush=True)
    finally:
        adb('shell','cmd','overlay','disable','com.android.internal.display.cutout.emulation.hole')
        adb('shell','wm','size','reset');adb('shell','wm','density','reset')
        adb('shell','settings','put','system','font_scale','1.0')
    record=dict(result='PASS',android_api=35,emulator='emulator-5580',adb_port=5041,
        installed_apk_sha256=installed_hash,scenarios=results,physical_hardware_tested=False,
        test_source_sha256={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in (ROOT/'mobile/android/app/src/androidTest').rglob('*.java')})
    (OUT/'verification.json').write_text(json.dumps(record,indent=2),encoding='utf-8')

if __name__=='__main__':main()
