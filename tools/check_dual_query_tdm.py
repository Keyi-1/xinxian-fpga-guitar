"""Exercise independent physical UARTs against the production shared bank."""
import sys,re,shutil
from pathlib import Path
from check_karplus_strong import run
from build_dual_score_transport import ROOT,BASE,guard,sha,save

def check(name):
    manifest=guard();dest=BASE/name;dest.mkdir(parents=True,exist_ok=False)
    src=dest/'sources';src.mkdir()
    modules=['game_p3_dual_service','game_p3_uart','game_p3_protocol','game_p3_import',
             'game_p3_catalog','game_p3_default_catalog','game_p3_catalog_cdc','game_p3_score_bank']
    paths=[ROOT/f'rtl/game/{m}.v' for m in modules]+list((ROOT/'rtl/config').glob('*.vh'))
    paths+=[ROOT/'sim/tb/tb_dual_query_tdm.sv',ROOT/'tools/check_dual_query_tdm.py']
    for p in paths:
        if p.suffix not in ('.v','.vh','.sv'):continue
        body=p.read_text(encoding='utf-8-sig').replace('../config/',src.as_posix()+'/')
        name=p.name
        (src/name).write_text(body,encoding='utf-8')
    run('vlib.log',['vlib.exe','work'],dest)
    vendor=Path('S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v')
    run('compile.log',['vlog.exe','-sv','+incdir+'+src.as_posix(),str(vendor),
                      *[str(p) for p in src.iterdir() if p.suffix in ('.v','.sv')]],dest)
    assert '** Warning:' not in (dest/'compile.log').read_text()
    log=run('query_tdm.log',['vsim.exe','-c','-onfinish','stop','work.tb_dual_query_tdm','-do','run -all; quit -code 0 -f'],dest)
    assert 'PASS:' in log and not re.search(r'FAIL:|\*\* Warning:',log)
    logs={'query_tdm':sha(dest/'query_tdm.log')}
    print('\n'.join(x for x in log.splitlines() if 'PASS:' in x),flush=True)
    assert guard()==manifest
    save(dest/'verification.json',dict(result='PASS',source_sha256={p.relative_to(ROOT).as_posix():sha(p) for p in paths},
        log_sha256=logs,vendor_library_sha256=sha(vendor),physical_hardware_tested=False,
        scope='Both UARTs use an accelerated eight-clock bit period to align independent QUERY frames. Actual production shared decoder; all metadata and reply-cache/CRC isolation checked. Real-baud tests are separate.'))

if __name__=='__main__':check(sys.argv[1])
