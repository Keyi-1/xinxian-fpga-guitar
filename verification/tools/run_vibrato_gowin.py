"""Run the already prepared original-project Tcl with reliable PID/exit receipts."""
import argparse
import hashlib
import json
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--stage',choices=('Synthesis','Route'),required=True)
    parser.add_argument('--run',required=True)
    args=parser.parse_args()
    assert re.fullmatch(r'[A-Za-z0-9_-]+',args.run)
    root=Path(__file__).resolve().parents[1]
    run=root/'build/vibrato'/args.run
    project=root/'gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj'
    prefix='build' if args.stage=='Synthesis' else 'route'
    receipt=run/('process.json' if args.stage=='Synthesis' else 'route_process.json')
    assert not receipt.exists(),'Inspect previous process evidence first'
    tool=Path('S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/bin/gw_sh.exe')
    started=datetime.now().astimezone().isoformat()
    with (run/(prefix+'.stdout.log')).open('xb') as output,(run/(prefix+'.stderr.log')).open('xb') as error:
        proc=subprocess.Popen([str(tool),str(run/(prefix+'.tcl'))],cwd=project.parent,
            stdout=output,stderr=error,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        record={'status':'RUNNING','stage':args.stage,'pid':proc.pid,'started':started,
            'source_commit':subprocess.check_output(['git','-C',str(root),'rev-parse','HEAD'],text=True).strip(),
            'scope':'Original gprj/impl; protected settings retained; reliable subprocess exit code',
            'project':str(project),'log':str(run/(prefix+'.stdout.log')),
            'launcher_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
        receipt.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
        print(f'Original guitar {args.stage} PID={proc.pid}; logs {run}',flush=True)
        code=proc.wait()
        record.update(status='EXITED',exit_code=code,finished=datetime.now().astimezone().isoformat())
        receipt.write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    raise SystemExit(code)


if __name__=='__main__':main()
