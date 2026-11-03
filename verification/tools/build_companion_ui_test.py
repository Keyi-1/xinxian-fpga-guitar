"""Build an SDK-only instrumentation APK with the same local signing identity."""
from pathlib import Path
import json
import subprocess
import zipfile

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/companion_ui/instrumentation'
SDK=Path('S:/Software/AndroidSDK')
TOOLS=SDK/'build-tools/35.0.1'
JDK=Path('S:/AndroidSoftWare/JDK_Version/bin')
ANDROID=SDK/'platforms/android-35/android.jar'
OUT.mkdir(parents=True,exist_ok=True)
logs=[]
def run(*args):
    process=subprocess.run(list(map(str,args)),capture_output=True,text=True,encoding='utf-8',errors='replace')
    logs.append(process.stdout+process.stderr)
    (OUT/'build.log').write_text('\n'.join(logs),encoding='utf-8')
    if process.returncode:raise RuntimeError(logs[-1])

manifest=OUT/'AndroidManifest.xml'
manifest.write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.keyi.xinxian.guitar.uitest">
  <application android:label="Companion UI test" android:debuggable="true">
    <provider android:name="com.keyi.xinxian.uitest.TestFiles" android:authorities="com.keyi.xinxian.guitar.uitest.files" android:exported="true" android:grantUriPermissions="true"/>
  </application>
  <instrumentation android:name="com.keyi.xinxian.uitest.UiProbe" android:targetPackage="com.keyi.xinxian.guitar.jdy23"/>
</manifest>''',encoding='utf-8')
run(TOOLS/'aapt2.exe','link','-o',OUT/'unsigned.apk','--manifest',manifest,'-I',ANDROID,
    '--min-sdk-version','26','--target-sdk-version','35','-A',ROOT/'mobile/android/app/src/main/assets')
classes=OUT/'classes';classes.mkdir(exist_ok=True)
dex=OUT/'dex';dex.mkdir(exist_ok=True)
main_classes=ROOT/'build/releases/android/xinxian_jdy23_0.3.0/classes.jar'
run(JDK/'javac.exe','--release','17','-encoding','UTF-8','-cp',str(ANDROID)+';'+str(main_classes),'-d',classes,
    *sorted((ROOT/'mobile/android/app/src/androidTest/java').rglob('*.java')))
run(JDK/'jar.exe','cf',OUT/'classes.jar','-C',classes,'.')
run(JDK/'java.exe','-cp',TOOLS/'lib/d8.jar','com.android.tools.r8.D8','--release','--min-api','26',
    '--lib',ANDROID,'--classpath',main_classes,'--output',dex,OUT/'classes.jar')
with zipfile.ZipFile(OUT/'unsigned.apk','a') as z:
    for path in dex.glob('*.dex'):z.write(path,path.name)
run(TOOLS/'zipalign.exe','-f','4',OUT/'unsigned.apk',OUT/'aligned.apk')
apk=OUT/'companion_ui_test.apk'
run(JDK/'java.exe','-jar',TOOLS/'lib/apksigner.jar','sign','--ks',ROOT/'build/companion_ui/signing/jdy23-debug.jks',
    '--ks-pass','pass:android','--key-pass','pass:android','--out',apk,OUT/'aligned.apk')
run(JDK/'java.exe','-jar',TOOLS/'lib/apksigner.jar','verify',apk)
print('Instrumentation APK built and signature verified')
