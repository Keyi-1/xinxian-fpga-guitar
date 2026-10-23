"""Verify and archive the independent diagnostic without touching guitar outputs."""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from bs4 import BeautifulSoup

ROOT=Path(__file__).resolve().parents[1]
NAME='neo_mpu6050_lcd_diagnostic'
PROJECT=ROOT/'gowin'/NAME
RUN=ROOT/'build/mpu_lcd_diagnostic'


def read(p):return p.read_text(encoding='utf-8-sig')
def load(p):return json.loads(read(p))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def git(*args):return subprocess.check_output(['git','-C',str(ROOT),*args],text=True,encoding='utf-8')
def save(p,data):p.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--build-run',default='impl_02')
    parser.add_argument('--rtl-run',default='rtl_01')
    parser.add_argument('--gate-run',default='gate_01')
    parser.add_argument('--release-name',default='mpu_lcd_diagnostic')
    parser.add_argument('--file-name',default=NAME+'.fs')
    args=parser.parse_args()
    for name in (args.build_run,args.rtl_run,args.gate_run,args.release_name):
        assert re.fullmatch(r'[A-Za-z0-9_-]+',name), 'Simple local directory name required'
    assert re.fullmatch(r'[A-Za-z0-9_-]+\.fs',args.file_name)
    before=load(RUN/'baseline.json')
    assert git('rev-parse','HEAD').strip()==before['head']
    assert git('ls-files','--stage')==before['index'], 'Existing index was changed'
    for path,digest in before['hashes'].items():
        assert sha(ROOT/path)==digest, f'Existing protected/baseline file changed: {path}'
    build=RUN/args.build_run
    rtl_dir=RUN/args.rtl_run
    gate_dir=RUN/args.gate_run
    process=load(build/'process.json')
    assert load(build/'completion.json')['exit_code']==0
    for path,digest in process['inputs_sha256'].items():
        assert sha(ROOT/path)==digest, f'Build input changed: {path}'
    log=read(build/'build.stdout.log')
    assert 'PNR_TCL_FINISHED' in log and 'GowinSynthesis finish' in log
    assert not re.search(r'\bERROR\b|\bPR0004\b|\b[1-9]\d*\s+(?:unrouted|unroute|unconnected)\b',log,re.I)
    assert not read(build/'build.stderr.log').strip()
    assert 'Placement and routing completed' in log and 'Bitstream generation completed' in log
    warning_lines=[line for line in log.splitlines() if 'WARN ' in line]
    assert len(warning_lines)==4 and all('EX3791' in x or 'PR1014' in x for x in warning_lines)
    vg=PROJECT/f'impl/gwsynthesis/{NAME}.vg'
    fs=PROJECT/f'impl/pnr/{NAME}.fs'
    assert fs.stat().st_size>100000
    gate=load(gate_dir/'verification.json')
    assert gate['status']=='PASS' and gate['inputs_sha256']['actual_vg']==sha(vg)
    for path,digest in gate['inputs_sha256'].items():
        if path not in ('actual_vg','gowin_prim_sim'):
            assert sha(ROOT/path)==digest, f'Tested source changed: {path}'
    if (rtl_dir/'verification.json').exists():
        rtl=load(rtl_dir/'verification.json')
        assert rtl['status']=='PASS'
        for path,digest in rtl['inputs_sha256'].items():
            assert sha(ROOT/path)==digest, f'RTL-tested source changed: {path}'
    messages={}
    rtl_logs=['reader.log','screen.log','top.log'] if (rtl_dir/'reader.log').exists() else ['tb_mpu_lcd_diag.log','tb_mpu_diag_screen.log','tb_mpu_diag_top.log']
    logs=[rtl_dir/name for name in rtl_logs]+[gate_dir/'tb_mpu_diag_gate.log']
    for path in logs:
        body=read(path)
        assert not re.search(r'FAIL:|\*\* (?:Error|Fatal|Warning)',body)
        passed=re.findall(r'^# PASS:.*',body,re.M)
        assert len(passed)==1
        messages[path.name]=passed[0][2:]
    pixels=load(rtl_dir/'pixels.json')
    assert pixels['result']=='PASS' and pixels['active_pixels']==130560 and pixels['mismatches']==0
    timing=PROJECT/f'impl/pnr/{NAME}_tr_content.html'
    soup=BeautifulSoup(read(timing),'html.parser')
    timing_text=soup.get_text(' ',strip=True)
    violations={}
    for kind in ('Setup','Hold'):
        m=re.search(rf'Numbers of {kind} Violated Endpoints\s+(\d+)',timing_text)
        assert m and int(m[1])==0
        violations[kind.lower()]=0
    fmax_match=re.search(r'sys_clk_50m\s+50\.000\(MHz\)\s+([\d.]+)\(MHz\)',timing_text)
    assert fmax_match and float(fmax_match[1])>=50
    report=read(PROJECT/f'impl/pnr/{NAME}.rpt.txt')
    resources={}
    for resource in ('Logic','Register','CLS','BSRAM','DSP'):
        m=re.search(rf'^\s*{resource}\s*\|\s*([\d.]+)/([\d.]+)',report,re.M)
        assert m
        used,total=map(float,m.groups())
        assert used<=total
        resources[resource]={'used':used,'total':total}
    latch_values=re.findall(r'--(?:Logic|I/O) Register as Latch\s*\|\s*(\d+)/',report)
    assert len(latch_values)==2 and all(int(x)==0 for x in latch_values)
    violations.update(latch=0,unrouted=0)
    result={'result':'PASS','created_utc':datetime.now(timezone.utc).isoformat(),
      'artifact_scope':'Independent minimal LCD/MPU6050/MPU6500 diagnostic only; not guitar firmware or hardware acceptance',
      'source_head':before['head'],'source_state':'new local uncommitted diagnostic files; existing tracked sources/index unchanged',
      'tool':'Gowin V1.9.12.03','device':'GW5AT-LV60PG484AC1/I0, Device B',
      'clock':{'required_mhz':50,'fmax_mhz':float(fmax_match[1])},
      'resources':resources,'violations':violations,'tests':messages,
      'netlist_scope':'Actual unmodified synthesis VG versus RTL, real production startup waits, ID70 MPU6500 profile including 1D readback, I2C pins and LCD outputs, dynamic signed data; no SDF back-annotation',
      'rtl_fault_scope':'ID68/ID70 at both bus addresses, absent/unknown ID, NACK stages, configuration mismatch, stale data, SCL/SDA stuck and recovery; wait-only parameters shortened in fault and RTL top benches',
      'user_hardware_observation':'Previous strict diagnostic: 68 ACK1 ID70 ERR0, 69 ACK0 ID-- ERR1, identity-fault counter retries. New compatible image has not yet been tested on hardware.',
      'warnings':warning_lines,
      'warning_review':'EX3791: intentional bounded BCD and font-coordinate truncation, checked at signed boundaries and every active LCD pixel. PR1014: existing board-clock routing constraint, actual route delay included in passing STA.',
      'hardware_status':'Not programmed or measured by this task. Actual module ID, tilt response, power/pullups, connection quality and long-term operation require user test.',
      'constraints_scope':'50MHz internal STA, asynchronous I2C input false paths; original LCD scan timing retained, external LCD delay not measured here',
      'original_guitar_files_preserved':True,
      'original_guitar_fs_sha256':before['hashes']['gowin/neo_guitar_touch_game/impl/pnr/neo_guitar_touch_game.fs'],
      'inputs_sha256':process['inputs_sha256'],
      'netlist_sha256':sha(vg),'bitstream_sha256':sha(fs)}
    artifacts={}
    for directory in (build,rtl_dir,gate_dir):
        for path in directory.iterdir():
            if path.is_file() and path.suffix in ('.log','.json','.tcl','.txt','.png'):
                artifacts[path.relative_to(ROOT).as_posix()]=sha(path)
    for pattern in ('impl/gwsynthesis/*.vg','impl/gwsynthesis/*.html','impl/gwsynthesis/*.log',
                    'impl/pnr/*.fs','impl/pnr/*.html','impl/pnr/*.txt','impl/pnr/*.log',
                    'impl/*_process_config.json'):
        for path in PROJECT.glob(pattern):artifacts[path.relative_to(ROOT).as_posix()]=sha(path)
    for directory in (ROOT/'rtl/diagnostics',ROOT/'sim/diagnostics/mpu_lcd'):
        for path in directory.iterdir():
            if path.is_file():artifacts[path.relative_to(ROOT).as_posix()]=sha(path)
    for path in [PROJECT/'README.md',ROOT/'tools/generate_mpu_diag_screen.py',ROOT/'tools/check_mpu_diag_pixels.py',
                 ROOT/'tools/run_mpu_lcd_diag_checks.ps1',ROOT/'tools/start_mpu_lcd_diag_build.ps1',Path(__file__)]:
        artifacts[path.relative_to(ROOT).as_posix()]=sha(path)
    result['artifacts_sha256']=artifacts
    result['baseline_receipt_sha256']=sha(RUN/'baseline.json')
    save(PROJECT/'verification.json',result)
    release=ROOT/'build/releases'/args.release_name
    assert not release.exists(), 'Do not overwrite an existing diagnostic release'
    release.mkdir(parents=True)
    shutil.copy2(fs,release/args.file_name)
    shutil.copy2(PROJECT/'README.md',release/'README.md')
    for path in set(artifacts)|set(process['inputs_sha256']):
        dest=release/'evidence'/path;dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT/path,dest)
        assert sha(dest)==sha(ROOT/path)
    shutil.copy2(RUN/'baseline.json',release/'evidence/baseline.json')
    shutil.copy2(PROJECT/'verification.json',release/'verification.json')
    assert sha(release/args.file_name)==result['bitstream_sha256']
    print(json.dumps({k:result[k] for k in ('result','clock','resources','violations','bitstream_sha256')},indent=2))
    print('Release: '+str(release))


if __name__=='__main__':main()
