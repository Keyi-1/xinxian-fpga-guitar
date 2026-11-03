"""Build the user's original Gowin project, preserving protected settings/evidence."""
import subprocess,json,sys,hashlib,shutil
from pathlib import Path
from datetime import datetime
ROOT=Path(__file__).resolve().parents[1]
stage=sys.argv[1];name=sys.argv[2]
assert stage in ('syn','pnr') and name.replace('_','').isalnum()
dest=ROOT/'build/karplus_strong'/name
dest.mkdir(parents=True,exist_ok=False)
before=json.loads((ROOT/'build/karplus_strong/before/protected.json').read_text())
def protected():
    for p,v in before.items():
        assert hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==v['sha256'],p
        assert subprocess.check_output(['git','ls-files','--stage','--',p],cwd=ROOT).decode()==v['index'],p
protected()
project=ROOT/'gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj'
files=list((ROOT/'rtl').rglob('*'))+list((ROOT/'mem').glob('*'))+list((ROOT/'constraints').glob('*'))+[project]
manifest={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files if p.is_file()}
(dest/'source_manifest.json').write_text(json.dumps(manifest,indent=2))
script=dest/'build.tcl'
script.write_text(f'open_project {{{project.as_posix()}}}\nif {{[catch {{run {stage}}} message]}} {{puts stderr $message;exit 1}}\nputs KS_BUILD_FINISHED\nexit\n')
record={'stage':stage,'baseline':'d5d8599','started':datetime.now().isoformat(),'status':'RUNNING'}
with (dest/'stdout.log').open('xb') as out,(dest/'stderr.log').open('xb') as err:
    proc=subprocess.Popen(['S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe',str(script)],cwd=project.parent,stdout=out,stderr=err,creationflags=subprocess.CREATE_NO_WINDOW)
    record['pid']=proc.pid;(dest/'process.json').write_text(json.dumps(record,indent=2))
    print(f'{stage} PID {proc.pid}: {dest}',flush=True)
    code=proc.wait()
record.update(status='EXITED',exit_code=code,finished=datetime.now().isoformat())
(dest/'process.json').write_text(json.dumps(record,indent=2))
protected()
for p,digest in manifest.items():assert hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==digest,p
impl=project.parent/'impl'/('gwsynthesis' if stage=='syn' else 'pnr')
for pattern in (['*.vg','*.xml','*.html','*.log'] if stage=='syn' else ['*.fs','*.log','*.txt','*.html','*.timing_paths']):
    for p in impl.glob(pattern):shutil.copy2(p,dest/p.name)
raise SystemExit(code)
