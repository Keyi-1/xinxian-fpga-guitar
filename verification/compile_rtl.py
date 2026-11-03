"""Compile/elaborate the current GPRJ sources in ModelSim; no full simulation."""
from pathlib import Path
import argparse
import os
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--modelsim-bin', default=os.environ.get('MODELSIM_BIN'))
    parser.add_argument('--gowin-ide', default=os.environ.get('GOWIN_IDE'))
    args = parser.parse_args()
    if not args.modelsim_bin or not args.gowin_ide:
        parser.error('Set MODELSIM_BIN and GOWIN_IDE or pass the corresponding options.')
    model = Path(args.modelsim_bin)
    primitive = Path(args.gowin_ide)/'simlib/gw5a/prim_sim.v'
    assert primitive.is_file(), primitive
    project = ROOT/'gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj'
    sources = [(project.parent/f.attrib['path']).resolve()
               for f in ET.parse(project).findall('.//File')
               if f.get('enable', '1') == '1' and f.get('type') == 'file.verilog']
    out = ROOT/'verification/results/hdl'
    out.mkdir(parents=True, exist_ok=True)
    work = out/'work'

    def run(tool, arguments, cwd=ROOT):
        exe = model/(tool+'.exe')
        assert exe.is_file(), exe
        # ModelSim's Tcl option parser needs forward slashes for absolute paths.
        argv = [a.as_posix() if isinstance(a, Path) else str(a) for a in arguments]
        result = subprocess.run([str(exe), *argv], cwd=cwd,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding='utf-8', errors='replace')
        (out/(tool+'.log')).write_text(result.stdout, encoding='utf-8')
        if result.returncode or '** Error' in result.stdout or '** Fatal' in result.stdout:
            raise RuntimeError(result.stdout[-6000:])
    if not work.exists():
        run('vlib', [work])
    ini = out/'modelsim.ini'
    if not ini.exists():
        run('vmap', ['-c'], cwd=out)
    run('vmap', ['-modelsimini', ini, 'work', work])
    includes = ['+incdir+'+str(p) for p in sorted({ROOT, *(p.parent for p in sources)})]
    run('vlog', ['-sv', '-work', work, *includes, primitive, *sources])
    # Gowin RAM/PLL models resolve the global GSR.GSRO simulation net.
    run('vsim', ['-c', '-modelsimini', ini, 'work.neo_guitar_touch_game_top', 'work.GSR', '-do', 'quit -f'])
    print(f'PASS: compiled {len(sources)} GPRJ Verilog entries and elaborated production top; no full simulation.')

if __name__ == '__main__':
    main()
