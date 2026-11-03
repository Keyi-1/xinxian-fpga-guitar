"""Exact full-design pin graph with ONLY the requested renderer cut out.

The renderer's declared pins stay in the graph as an opaque primitive, so this
proves every other primitive, parameter, clock and boundary connection intact.
The changed renderer needs independent pixel checks and fresh top-level gates.
"""
from pathlib import Path
import argparse
import json
from compare_synth_graph import Graph, parse, sha


def compare(before, after):
    signatures=[];boundary=None
    for path in [before, after]:
        modules=parse(Path(path).read_text(encoding='utf-8-sig'))
        renderer=modules.pop('touch_game_renderer')
        if boundary is None:boundary=renderer['ports']
        else:assert renderer['ports']==boundary,'Renderer boundary changed; cannot reuse surrounding proof'
        signatures.append(Graph(modules,'neo_guitar_touch_game_top').signature())
    assert signatures[0]==signatures[1],('Primitive/pin graph outside changed renderer differs',signatures)
    return dict(result='PASS',before_sha256=sha(before),after_sha256=sha(after),
        excluded_module='touch_game_renderer',excluded_module_ports={name:[kind,bits] for name,(kind,bits) in boundary.items()},
        scope='Exact entire production graph, with only renderer body opaque; renderer pins, all remaining primitives/parameters/connections retained',
        checker_sha256=sha(__file__),graph_checker_sha256=sha(Path(__file__).with_name('compare_synth_graph.py')),
        **signatures[0])


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('before',type=Path);p.add_argument('after',type=Path);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();proof=compare(a.before,a.after);a.output.write_text(json.dumps(proof,indent=2)+'\n',encoding='utf-8')
    print('PASS: exact complete graph outside renderer; renderer boundary retained')
