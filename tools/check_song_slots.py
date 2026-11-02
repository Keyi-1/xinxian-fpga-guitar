"""Check the user-visible five-slot layout against the accepted source snapshot."""
import argparse
from pathlib import Path
import re
import shutil
from datetime import datetime
from check_karplus_strong import run
from build_song_slots import ROOT, BASE, sha, save, guard

VENDOR = Path('S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v')


def check(name):
    manifest = guard()
    dest = BASE/name
    dest.mkdir(parents=True, exist_ok=False)
    src = dest/'sources';src.mkdir()
    paths = list((ROOT/'rtl').rglob('*.v'))+list((ROOT/'rtl/config').glob('*.vh'))+list((ROOT/'mem').glob('*'))
    paths += [ROOT/'tools/check_song_slots.py', ROOT/'tools/check_karplus_strong.py']
    benches = ['tb_song_slots_catalog_ui', 'tb_song_slots_display', 'tb_song_slots_uart']
    paths += [ROOT/f'sim/tb/{n}.sv' for n in benches]+[ROOT/'sim/tb/game_p3_uart_host.vh']
    for p in paths:
        if p.suffix not in ('.v','.vh','.sv'):
            continue
        body=p.read_text(encoding='utf-8-sig').replace('../config/',src.as_posix()+'/').replace('../../mem/',(ROOT/'mem').as_posix()+'/')
        (src/p.name).write_text(body,encoding='utf-8')
    for n in ('game_p3_catalog','game_p3_default_catalog','touch_game_renderer'):
        p=BASE/f'before/source/rtl/game/{n}.v';paths.append(p)
        body=p.read_text(encoding='utf-8-sig')
        for old in ('game_p3_catalog','game_p3_default_catalog','touch_game_renderer'):
            body=re.sub(r'\b'+old+r'\b','frozen_'+old,body)
        body=body.replace('../config/',src.as_posix()+'/').replace('../../mem/',(ROOT/'mem').as_posix()+'/')
        (src/('frozen_'+n+'.v')).write_text(body,encoding='utf-8')
    rec={'status':'RUNNING','started':datetime.now().astimezone().isoformat(),
         'source_sha256':{p.relative_to(ROOT).as_posix():sha(p) for p in paths}}
    save(dest/'process.json',rec)
    try:
        run('vlib.log',['vlib.exe','work'],dest)
        run('compile.log',['vlog.exe','-sv','+incdir+'+src.as_posix(),str(VENDOR),
                          *[str(p) for p in src.iterdir() if p.suffix in ('.v','.sv')]],dest)
        assert '** Warning:' not in (dest/'compile.log').read_text()
        logs={}
        for bench,params,label in [(benches[0],[],benches[0]),(benches[1],[],benches[1]),
                                   (benches[2],['-gIMPORT_SLOT=3'],'uart_slot4'),(benches[2],['-gIMPORT_SLOT=4'],'uart_slot5')]:
            log=run(label+'.log',['vsim.exe','-c','-onfinish','stop',*params,'work.'+bench,'-do','run -all; quit -code 0 -f'],dest)
            assert 'PASS:' in log and 'FAIL:' not in log
            for line in log.splitlines():
                if '** Warning:' in line:
                    assert re.search(r'prim_sim.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)',line),line
            logs[label]=sha(dest/(label+'.log'))
            print('\n'.join(x for x in log.splitlines() if 'PASS:' in x),flush=True)
        assert guard()==manifest
        for p,h in rec['source_sha256'].items():assert sha(ROOT/p)==h,p
        rec.update(status='PASS',log_sha256=logs,vendor_library_sha256=sha(VENDOR),
                   scope='Catalog/UI all overlay masks, complete RTL pixel comparison against accepted renderer, real UART/DPB/CRC/CDC import independently into slots4/5; no hardware programming')
    except BaseException as exc:
        rec.update(status='FAIL',failure=str(exc));raise
    finally:
        rec['finished']=datetime.now().astimezone().isoformat();save(dest/'verification.json',rec)


if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('name');a=ap.parse_args()
    assert re.fullmatch(r'[A-Za-z0-9_]+',a.name)
    check(a.name)
