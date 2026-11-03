"""Real UART pins of the complete production VG versus complete current RTL."""
import sys,shutil,re
from pathlib import Path
from build_dual_score_transport import ROOT,BASE,guard,sha,save
from check_karplus_strong import run
from check_ks_result import review_vendor_warnings
from compare_synth_graph import parse

dest=BASE/sys.argv[1];dest.mkdir(parents=True,exist_ok=False)
manifest=guard()
vg=ROOT/'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
assert sha(vg)==sha(BASE/'synth_04/neo_guitar_touch_game.vg')
shutil.copy2(vg,dest/'actual.vg')
# Reuse only the already-prepared, exact current RTL namespace translation;
# compile and execute this independent UART scenario in its own library.
source=BASE/'full_gate_03/sources'
assert len(list(source.glob('*.v')))==len(list((ROOT/'rtl').rglob('*.v')))
shutil.copytree(source,dest/'sources')
src=dest/'sources'
for p in src.glob('*.v'):
    # Includes in the prepared files still identify the first source cache.
    # Both directories contain identical, unchanged header bytes.
    for h in re.findall(r'`include\s+"([^"]+)"',p.read_text(encoding='utf-8')):
        assert h.startswith(source.as_posix()+'/') and sha(Path(h))==sha(src/Path(h).name)
mods=parse(vg.read_text())
# Preserve the complete netlist. Force only the high countdown Q outputs;
# source data, FSMs, FIFO, commands, RAM, CRC and commit state remain untouched.
# Modulo periods are chosen so both full-bit and half-bit reloads agree.
service=[(name,pins) for kind,name,pins in mods['neo_guitar_touch_game_top']['cells'] if kind=='game_p3_dual_service']
assert len(service)==1
escape=lambda name:name+(' ' if name.startswith('\\') else '')
prefix='gate.'+escape(service[0][0])
forces=[];countdown_audit={}
for link,period,keep in [(0,5208,5),(1,434,6)]:
    links=[(kind,name) for kind,name,pins in mods['game_p3_dual_service']['cells'] if kind.startswith('game_p3_uart') and name==f'\\link[{link}].uart']
    assert len(links)==1
    kind,instance=links[0];q={}
    for cell,name,pins in mods[kind]['cells']:
        hit=re.fullmatch(r'(rx_count|tx_count)\[(\d+)\]',pins.get('Q',''))
        if cell.startswith('DFF') and hit:
            key=(hit[1],int(hit[2]));assert key not in q
            assert pins['CLK']=='sys_clk_50m_d',(kind,name,pins)
            q[key]={'cell':cell,'instance':name,'pins':pins}
    assert set(q)=={(counter,bit) for counter in ('rx_count','tx_count') for bit in range(16)}
    full=period % (1<<keep);half=(period//2) % (1<<keep)
    assert full==2*half and full>=8
    for (counter,bit),row in sorted(q.items()):
        if bit>=keep:forces.append(f"force {prefix}.{escape(instance)}.{escape(row['instance'])}.Q=1'b0;")
    for counter in ('rx_count','tx_count'):
        forces.append(f"force reference.p3.service.link[{link}].uart.{counter}[15:{keep}]=0;")
    countdown_audit[str(link)]={'nominal_cycles':period,'kept_bits':keep,'accelerated_cycles':full,'half_cycles':half,'all_32_q':{f'{a}[{b}]':row for (a,b),row in q.items()}}
assert len(forces)==46
(dest/'dual_uart_countdown.vh').write_text('\n'.join(forces)+'\n')

assert mods['gt911_touch']['ports']['touch_ready']==('output',[None])
for name,direction in [('song_uart_rx','input'),('song_uart_tx','output'),('usb_song_uart_rx','input'),('usb_song_uart_tx','output')]:
    assert mods['neo_guitar_touch_game_top']['ports'][name]==(direction,[None])
bench=ROOT/'sim/tb/tb_dual_uart_gate_accelerated.sv';shutil.copy2(bench,dest/bench.name)
paths=list((ROOT/'rtl').rglob('*.v'))+list((ROOT/'rtl/config').glob('*.vh'))+list((ROOT/'mem').glob('*'))
paths += [bench,ROOT/'tools/check_dual_uart_gate_accelerated.py',ROOT/'tools/check_dual_transport_full_gate.py']
inputs={p.relative_to(ROOT).as_posix():sha(p) for p in paths}
save(dest/'mapping.json',dict(result='PASS',scope='Only registered touch readiness and the enumerated UART countdown high-bit Q outputs are forced in the two complete tops. All serial bytes use physical top pins. No FIFO, importer, RAM, CRC, catalog or audio result forcing.',
    force_gate="gate.u_touch.touch_ready=1'b1",force_reference="reference.u_touch.ready=1'b1",countdown_audit=countdown_audit,countdown_forces=forces,
    translated_sources_sha256={p.name:sha(p) for p in src.iterdir() if p.is_file()}))
run('vlib.log',['vlib.exe','work'],dest)
run('compile.log',['vlog.exe','-sv','+incdir+'+src.as_posix()+'+'+dest.as_posix(),
    'S:/BaiduNetdiskDownload/GOWIN/Gowin_V1.9.12.03_x64/IDE/simlib/gw5a/prim_sim.v',
    'actual.vg',*[str(p) for p in src.glob('*.v')],bench.name],dest)
assert '** Warning:' not in (dest/'compile.log').read_text()
log=run('simulation.log',['vsim.exe','-c','-onfinish','stop','work.tb_dual_uart_gate_accelerated','-do','run -all; quit -code 0 -f'],dest)
assert 'PASS:' in log and 'FAIL:' not in log
review_vendor_warnings(dest)
assert guard()==manifest
for name,h in inputs.items():assert sha(ROOT/name)==h,name
assert sha(vg)==sha(dest/'actual.vg')
save(dest/'verification.json',dict(result='PASS',netlist_sha256=sha(vg),source_sha256=inputs,
    log_sha256={'simulation':sha(dest/'simulation.log')},mapping_sha256=sha(dest/'mapping.json'),
    physical_hardware_tested=False,scope='15 complete UART requests/ACKs through both actual top pins, cross-port atomic imports/queries, owner BUSY and retry cache; complete current VG/RTL outputs every clock. Only audited high countdown-Q bits forced: BLE5208->24, USB434->50 cycles. Full real-baud RTL validated separately. No SDF.'))
print('\n'.join(line for line in log.splitlines() if 'PASS:' in line))
