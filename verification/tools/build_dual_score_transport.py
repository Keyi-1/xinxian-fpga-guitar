"""Build the original project with independent USB/BLE score transports."""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'build/dual_score_transport'
PROJECT=ROOT/'gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj'
NAME='neo_guitar_touch_game'
ALLOWED={'rtl/game/game_p3_dual_service.v','rtl/game/game_p3_protocol.v','rtl/game/game_p3_service.v',
         'rtl/top/neo_guitar_touch_game_top.v','constraints/neo_guitar_touch_game.cst',
         'gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj'}

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def save(p,obj):p.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def guard():
    before=load(BASE/'before/snapshot.json')
    assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT).decode().strip()==before['head']
    for name,item in before['protected'].items():
        assert sha(ROOT/name)==item['sha256'],name
        assert subprocess.check_output(['git','ls-files','--stage','--',name],cwd=ROOT).decode()==item['index'],name
    paths=set(before['source_sha256'])|{p.relative_to(ROOT).as_posix() for p in (ROOT/'rtl').rglob('*') if p.is_file()}
    manifest={n:sha(ROOT/n) for n in sorted(paths)}
    changed={n for n,h in manifest.items() if before['source_sha256'].get(n)!=h}
    assert changed==ALLOWED,changed
    assert sha(BASE/'before/known_good_slots123.fs')==before['bitstream_sha256']
    return manifest

def build(stage,name):
    manifest=guard()
    active=subprocess.run(['powershell.exe','-NoProfile','-Command',
        '@(Get-Process gw_sh,gw_synth,gw_pnr -ErrorAction SilentlyContinue).Count'],capture_output=True,text=True,
        creationflags=subprocess.CREATE_NO_WINDOW)
    assert active.returncode==0 and active.stdout.strip()=='0','Inspect active Gowin processes'
    if stage=='syn':
        assert load(BASE/'rtl_10/verification.json')['result']=='PASS'
    else:
        review=load(BASE/'synth_04/resource_review.json')
        assert review['result']=='PASS'
        assert sha(PROJECT.parent/f'impl/gwsynthesis/{NAME}.vg')==review['netlist_sha256']
        assert manifest==load(BASE/'synth_04/source_manifest.json')
    dest=BASE/name;dest.mkdir(parents=True,exist_ok=False)
    save(dest/'source_manifest.json',manifest)
    tcl=dest/'build.tcl'
    tcl.write_text(f'open_project {{{PROJECT.as_posix()}}}\nif {{[catch {{run {stage}}} message]}} {{puts stderr $message;exit 1}}\nputs DUAL_TRANSPORT_BUILD_FINISHED\nexit\n')
    rec=dict(status='RUNNING',stage=stage,started=datetime.now().astimezone().isoformat(),project=PROJECT.as_posix())
    with (dest/'stdout.log').open('xb') as out,(dest/'stderr.log').open('xb') as err:
        proc=subprocess.Popen(['S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe',str(tcl)],
            cwd=PROJECT.parent,stdout=out,stderr=err,creationflags=subprocess.CREATE_NO_WINDOW)
        rec['pid']=proc.pid;save(dest/'process.json',rec)
        print(f'{stage}: PID={proc.pid}; {dest}',flush=True);code=proc.wait()
    rec.update(status='EXITED',exit_code=code,finished=datetime.now().astimezone().isoformat());save(dest/'process.json',rec)
    assert guard()==manifest
    folder=PROJECT.parent/'impl'/('gwsynthesis' if stage=='syn' else 'pnr')
    for pattern in (['*.vg','*.xml','*.html','*.log'] if stage=='syn' else ['*.fs','*.log','*.txt','*.html','*.timing_paths']):
        for p in folder.glob(pattern):shutil.copy2(p,dest/p.name)
    raise SystemExit(code)

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('stage',choices=['syn','pnr']);ap.add_argument('name');a=ap.parse_args()
    assert re.fullmatch('[A-Za-z0-9_]+',a.name);build(a.stage,a.name)
