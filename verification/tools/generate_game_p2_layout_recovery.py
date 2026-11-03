"""Bind manual frame pulses to the actual declared scan output, fail closed."""
from pathlib import Path
import json
import sys
from compare_synth_graph import parse, sha


def generate(vg, origin, output):
    modules=parse(vg.read_text(encoding='utf-8-sig'))
    scans=[kind for kind,name,pins in modules['guitar_touch_game_display']['cells'] if name=='u_scan']
    assert len(scans)==1
    ports=modules[scans[0]]['ports']
    frames=[name for name,(direction,bits) in ports.items()
            if direction=='output' and bits==[None] and name in {'frame_start','frame_start_Z'}]
    assert len(frames)==1,('inspect architectural frame output',ports)
    source=origin/'tb_game_p2_layout_gate.sv';before=source.read_text(encoding='utf-8-sig')
    old='force gate.u_display.u_scan.frame_start=manual_frame;'
    new=f'force gate.u_display.u_scan.{frames[0]}=manual_frame;'
    assert before.count(old)==1
    (output/'tb_game_p2_layout_gate.sv').write_text(before.replace(old,new),encoding='utf-8')
    proof=dict(result='PASS',netlist_sha256=sha(vg),original_bench_sha256=sha(source),
        scan_module=scans[0],actual_output=frames[0],only_generated_change=dict(before=old,after=new),
        scope='Same architectural scan frame output; no derived predecode forced')
    (output/'layout_recovery_map.json').write_text(json.dumps(proof,indent=2)+'\n',encoding='utf-8')
    print('PASS: actual declared scan frame output mapped:',frames[0])


if __name__=='__main__': generate(*(Path(v) for v in sys.argv[1:]))
