"""Build the JDY-23 serial APK with installed Android SDK tools, no Gradle downloads."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "mobile/android/app/src/main"
OUT = ROOT / "build/releases/android/xinxian_jdy23_0.3.0"
SDK = Path("S:/Software/AndroidSDK")
TOOLS = SDK / "build-tools/35.0.1"
JDK = Path("S:/AndroidSoftWare/JDK_Version/bin")
ANDROID = SDK / "platforms/android-35/android.jar"
OUT.mkdir(parents=True, exist_ok=True)
LOG = []
SOURCE_INPUTS = sorted(p for p in APP.rglob('*') if p.is_file())
SOURCE_HASHES = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCE_INPUTS}


def run(*args):
    result = subprocess.run([str(x) for x in args], capture_output=True,
                            text=True, encoding="utf-8", errors="replace")
    LOG.append(result.stdout + result.stderr)
    (OUT / "build.log").write_text("\n".join(LOG), encoding="utf-8")
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


res = OUT / "res"
shutil.copytree(APP / "res", res, dirs_exist_ok=True)
(res / "values/scan_name.xml").write_text('<resources><string name="app_name">弦心</string></resources>', encoding="utf-8")
ET.register_namespace("android", "http://schemas.android.com/apk/res/android")
tree = ET.parse(APP / "AndroidManifest.xml")
tree.getroot().set("package", "com.keyi.xinxian.guitar.jdy23")
application = tree.getroot().find("application")
application.set("{http://schemas.android.com/apk/res/android}debuggable", "false")
application.find("activity").set("{http://schemas.android.com/apk/res/android}name", "com.keyi.xinxian.guitar.MainActivity")
manifest = OUT / "AndroidManifest.xml"
tree.write(manifest, encoding="utf-8", xml_declaration=True)
generated, classes, dex = OUT / "generated", OUT / "classes", OUT / "dex"
for folder in (generated, classes, dex):
    folder.mkdir(exist_ok=True)
run(TOOLS / "aapt2.exe", "compile", "--dir", res, "-o", OUT / "resources.zip")
run(TOOLS / "aapt2.exe", "link", "-o", OUT / "resources.apk", "--manifest", manifest,
    "-I", ANDROID, "--java", generated, "--custom-package", "com.keyi.xinxian.guitar",
    "--min-sdk-version", "26", "--target-sdk-version", "35", "--version-code", "3",
    "--version-name", "0.3.0", "-A", APP / "assets", OUT / "resources.zip")
run(JDK / "javac.exe", "--release", "17", "-encoding", "UTF-8", "-cp", ANDROID,
    "-d", classes, *sorted((APP / "java").rglob("*.java")), *sorted(generated.rglob("*.java")))
run(JDK / "jar.exe", "cf", OUT / "classes.jar", "-C", classes, ".")
run(JDK / "java.exe", "-cp", TOOLS / "lib/d8.jar", "com.android.tools.r8.D8", "--release",
    "--min-api", "26", "--lib", ANDROID, "--output", dex, OUT / "classes.jar")
shutil.copy2(OUT / "resources.apk", OUT / "unsigned.apk")
with zipfile.ZipFile(OUT / "unsigned.apk", "a", zipfile.ZIP_STORED) as z:
    for item in sorted(dex.glob("*.dex")):
        z.write(item, item.name)
run(TOOLS / "zipalign.exe", "-f", "4", OUT / "unsigned.apk", OUT / "aligned.apk")
keystore = ROOT / "build/companion_ui/signing/jdy23-debug.jks"
keystore.parent.mkdir(parents=True, exist_ok=True)
if not keystore.exists():
    run(JDK / "keytool.exe", "-genkeypair", "-keystore", keystore, "-storepass", "android",
        "-keypass", "android", "-alias", "androiddebugkey", "-dname", "CN=Android Debug,O=Android,C=US",
        "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000")
apk = OUT / "xinxian_jdy23_0.3.0.apk"
run(JDK / "java.exe", "-jar", TOOLS / "lib/apksigner.jar", "sign", "--ks", keystore,
    "--ks-pass", "pass:android", "--key-pass", "pass:android", "--out", apk, OUT / "aligned.apk")
run(JDK / "java.exe", "-jar", TOOLS / "lib/apksigner.jar", "verify", "--verbose", apk)
badging = run(TOOLS / "aapt2.exe", "dump", "badging", apk)
assert "com.keyi.xinxian.guitar.jdy23" in badging
assert "minSdkVersion:'26'" in badging
result = {"apk": str(apk), "sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
          "package": "com.keyi.xinxian.guitar.jdy23", "compiled": True,
          "signature_verified": True, "hardware_tested": False, "installed": False,
          "builder": "Android SDK aapt2/javac/D8/zipalign/apksigner; Gradle offline cache incomplete"}
with zipfile.ZipFile(apk) as package:
    for source in sorted((APP / "assets").rglob('*')):
        if source.is_file():
            assert package.read('assets/' + source.relative_to(APP / "assets").as_posix()) == source.read_bytes()
result["assets_verified"] = True
assert SOURCE_HASHES == {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCE_INPUTS}
result["source_sha256"] = SOURCE_HASHES
(OUT / "verification.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result))
