"""Verify bundled events with the actual Java parser; no Android device or port IO."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/companion_ui/checks'
APP = ROOT / 'mobile/android/app/src/main'
JDK = Path('S:/AndroidSoftWare/JDK_Version/bin')
PROBE = r'''package com.keyi.xinxian.guitar;
import java.io.*;
import java.nio.file.*;
import java.util.*;
public class LibraryProbe {
    public static void main(String[] args) throws Exception {
        for(ScoreLibrary.Entry entry:ScoreLibrary.ENTRIES) {
            byte[] bytes=Files.readAllBytes(Path.of(args[0],entry.file));
            Xg3Protocol.Song builtin=entry.read(new ByteArrayInputStream(bytes));
            Xg3Protocol.Song external=ScoreLibrary.read(new ByteArrayInputStream(bytes));
            assert builtin.crc32==external.crc32 && builtin.events.size()==external.events.size();
            for(int i=0;i<builtin.events.size();i++)assert Arrays.equals(builtin.events.get(i),external.events.get(i));
            for(int slot=0;slot<5;slot++)for(int timbre=0;timbre<3;timbre++) {
                byte[] begin=Xg3Protocol.beginPayload(slot,timbre,builtin);
                assert begin[0]==slot && begin[1]==timbre && Xg3Protocol.u16(begin,2)==entry.count;
            }
            bytes[11]^=1;
            try { entry.read(new ByteArrayInputStream(bytes));throw new AssertionError("tampering accepted"); }
            catch(IOException|IllegalArgumentException expected) {}
            System.out.println(entry.title+": "+entry.count+" events, CRC="+Long.toHexString(builtin.crc32));
        }
        for(int size:new int[]{0,17,2048*16+1}) {
            try { ScoreLibrary.read(new ByteArrayInputStream(new byte[size]));throw new AssertionError("bad size"); }
            catch(IOException|IllegalArgumentException expected) {}
        }
        String[] titles={"茉莉花","Seven Nation Army","情歌","待导入","待导入"};
        for(int i=0;i<5;i++)assert ScoreLibrary.slotTitle(i,null).equals(titles[i]);
        Xg3Protocol.SlotDescriptor seventh=new Xg3Protocol.SlotDescriptor(2,67,168,9216000L,2,true,true,false,false);
        assert ScoreLibrary.slotTitle(2,seventh).equals("Seven Nation Army");
        Xg3Protocol.SlotDescriptor imported=new Xg3Protocol.SlotDescriptor(3,703,168,9216000L,2,true,true,true,false);
        assert ScoreLibrary.slotTitle(3,imported).equals("USER 4");
        assert Arrays.equals(ScoreLibrary.TIMBRES,new String[]{"钢琴","明亮弦音","哇音"});
        assert ScoreLibrary.timbre(3).equals("未知音色");
        System.out.println("PASS: local/external identity, all 45 slot/timbre BEGIN combinations, bad files, CRC, old/new slot descriptors");
    }
}'''

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    probe=OUT/'LibraryProbe.java'
    probe.write_text(PROBE, encoding='utf-8')
    classes=OUT/'classes'
    classes.mkdir(exist_ok=True)
    java=APP/'java/com/keyi/xinxian/guitar'
    compile_result=subprocess.run([str(JDK/'javac.exe'),'--release','17','-encoding','UTF-8',
        '-d',str(classes),str(java/'ScoreLibrary.java'),str(java/'Xg3Protocol.java'),str(probe)],capture_output=True,text=True,encoding='utf-8',errors='replace')
    if compile_result.returncode: raise RuntimeError(compile_result.stdout+compile_result.stderr)
    result=subprocess.run([str(JDK/'java.exe'),'-Dfile.encoding=UTF-8','-ea','-cp',str(classes),'com.keyi.xinxian.guitar.LibraryProbe',str(APP/'assets/scores')],capture_output=True,text=True,encoding='utf-8',errors='strict')
    (OUT/'java.log').write_text(result.stdout+result.stderr,encoding='utf-8')
    if result.returncode: raise RuntimeError(result.stdout+result.stderr)
    for path in (APP/'res').rglob('*.xml'): ET.parse(path)
    inputs={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in APP.rglob('*') if p.is_file()}
    # Backend transport/protocol and every FPGA input must remain at this worktree's base.
    frozen=['Xg3Client.java','Xg3Protocol.java','BleUartClient.java','BleSerialProfile.java']
    for name in frozen:
        rel=(java/name).relative_to(ROOT).as_posix()
        original=subprocess.check_output(['git','show','HEAD:'+rel],cwd=ROOT)
        assert original.replace(b'\r\n',b'\n')==(java/name).read_bytes().replace(b'\r\n',b'\n'), rel
    assert not subprocess.check_output(['git','diff','HEAD','--','rtl','gowin','constraints','firmware'],cwd=ROOT).strip()
    (OUT/'verification.json').write_text(json.dumps(dict(result='PASS',source_sha256=inputs,
        backend_unchanged=True,hardware_sources_unchanged=True,android_os_tested=False),ensure_ascii=False,indent=2),encoding='utf-8')
    print('PASS: actual Java parser, three bundled scores, external file identity, 45 upload combinations, CRC and slot names')

if __name__=='__main__': main()
