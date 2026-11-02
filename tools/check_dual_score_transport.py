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
    paths+=[ROOT/'sim/tb/tb_dual_score_transport.sv',ROOT/'sim/tb/tb_protocol_fifo4.sv',
            ROOT/'sim/tb/tb_protocol_direct_input.sv',ROOT/'sim/tb/tb_game_p3_frame_rx.sv',ROOT/'tools/check_dual_score_transport.py']
    frozen=BASE/'candidate_01/source/rtl/game/game_p3_protocol.v';paths.append(frozen)
    for p in paths:
        if p.suffix not in ('.v','.vh','.sv'):continue
        body=p.read_text(encoding='utf-8-sig').replace('../config/',src.as_posix()+'/')
        name=p.name
        if p==frozen:
            body=body.replace('module game_p3_protocol','module fifo_reference_protocol');name='fifo_reference_protocol.v'
        (src/name).write_text(body,encoding='utf-8')
    run('vlib.log',['vlib.exe','work'],dest)
    vendor=Path('S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v')
    run('compile.log',['vlog.exe','-sv','+incdir+'+src.as_posix(),str(vendor),
                      *[str(p) for p in src.iterdir() if p.suffix in ('.v','.sv')]],dest)
    assert '** Warning:' not in (dest/'compile.log').read_text()
    logs={}
    log=run('fifo_equivalence.log',['vsim.exe','-c','-onfinish','stop','work.tb_protocol_fifo4',
        '-do','run -all; quit -code 0 -f'],dest)
    assert 'PASS:' in log and not re.search(r'FAIL:|\*\* Warning:',log)
    logs['fifo_equivalence']=sha(dest/'fifo_equivalence.log')
    print('\n'.join(x for x in log.splitlines() if 'PASS:' in x),flush=True)
    for label,bench in [('direct_equivalence','tb_protocol_direct_input'),('frame_receiver','tb_game_p3_frame_rx')]:
        log=run(label+'.log',['vsim.exe','-c','-onfinish','stop','work.'+bench,'-do','run -all; quit -code 0 -f'],dest)
        assert 'PASS:' in log and not re.search(r'FAIL:|\*\* Warning:',log)
        logs[label]=sha(dest/(label+'.log'))
        print('\n'.join(x for x in log.splitlines() if 'PASS:' in x),flush=True)
    for real in (0,1):
        label=f'physical_uart_{real}'
        log=run(label+'.log',['vsim.exe','-c','-onfinish','stop',f'-gREAL_BAUD={real}',
            '-wlf',label+'.wlf','work.tb_dual_score_transport','-do','run -all; quit -code 0 -f'],dest)
        assert 'PASS:' in log and 'FAIL:' not in log
        for line in log.splitlines():
            if '** Warning:' in line:
                assert re.search(r'prim_sim.v\((1860|1864|1868|1884|1888|1893|3130|3134|3138|3142|3313|3317)\): \(vopt-2697\)',line),line
        logs[label]=sha(dest/(label+'.log'))
        print('\n'.join(x for x in log.splitlines() if 'PASS:' in x),flush=True)
    assert guard()==manifest
    save(dest/'verification.json',dict(result='PASS',source_sha256={p.relative_to(ROOT).as_posix():sha(p) for p in paths},
        log_sha256=logs,vendor_library_sha256=sha(vendor),physical_hardware_tested=False,
        scope='Real 50MHz/12.288MHz clocks, USB115200 and BLE9600 physical UARTs; accelerated baud fixture additionally tests abandoned upload timeout. Actual DPB readback CRC, CDC and import ownership.'))

if __name__=='__main__':check(sys.argv[1])
