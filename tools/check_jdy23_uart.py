"""Focused new 9600 physical UART and actual XG3/BSRAM integration only."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

R=Path(__file__).resolve().parents[1]
E=R/'build/jdy23/v1/sim_9600_02'
BIN=Path('S:/BaiduNetdiskDownload/modelsim/win64')

def run():
    assert not E.exists(),'Inspect existing run, do not repeat completed tests'
    E.mkdir()
    sources=[*sorted((R/'rtl/game').glob('game_p3_*.v')),
        R/'rtl/config/game_p3_bsram_init.vh',R/'rtl/config/game_p2_progress.vh',
        R/'sim/tb/tb_jdy23_uart_9600.sv',R/'sim/tb/tb_jdy23_xg3.sv']
    hashes={p.relative_to(R).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    for p in sources:
        body=p.read_text(encoding='utf-8-sig').replace('"../config/','"').replace('"../../mem/','"'+str(R/'mem').replace('\\','/')+'/')
        (E/p.name).write_text(body,encoding='utf-8')
    helper=(R/'sim/tb/game_p3_uart_host.vh').read_text(encoding='utf-8')
    old='for(k=0;k<32;k=k+1)byte_send(frame[k],period);'
    assert helper.count(old)==1
    (E/'jdy23_uart_host.vh').write_text(helper.replace(old,'for(k=0;k<32;k=k+1)begin if(k==20)repeat(750000)@(negedge clk);byte_send(frame[k],period);end'),encoding='utf-8')
    def command(name,*args):
        result=subprocess.run([str(BIN/name),*map(str,args)],cwd=E,capture_output=True,text=True,errors='replace')
        (E/(name+'.console.log')).write_text(result.stdout+result.stderr,encoding='utf-8')
        assert result.returncode==0,(name,result.stdout[-2000:],result.stderr[-2000:])
        return result.stdout+result.stderr
    command('vlib.exe','work')
    log=command('vlog.exe','-sv','+incdir+.',
        'S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v',
        *sorted(p.name for p in E.iterdir() if p.suffix in ('.v','.sv')))
    assert not re.search(r'\*\* (?:Error|Fatal|Warning):',log)
    for bench in ('tb_jdy23_uart_9600','tb_jdy23_xg3'):
        log=command('vsim.exe','-c','-onfinish','stop','work.'+bench,'-l',bench+'.log','-do','run -all; quit -code 0 -f')
        assert 'PASS:' in log and not re.search(r'FAIL:|\*\* (?:Error|Fatal|Warning):',log),(bench,log[-3000:])
        print('\n'.join(line for line in log.splitlines() if 'PASS:' in line))
    for name,digest in hashes.items():assert hashlib.sha256((R/name).read_bytes()).hexdigest()==digest
    (E/'verification.json').write_text(json.dumps({'result':'PASS','source_sha256':hashes,'hardware_tested':False,
        'scope':'Focused actual 50MHz/9600 UART, paced fragments, XG3 and BSRAM; no repeat of old audio/display tests'},indent=2))

if __name__=='__main__':run()
