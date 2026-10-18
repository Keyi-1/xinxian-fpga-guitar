"""Exhaustive Boolean audit of actual VG write-page/address/byte/data wiring.

Complements the full1345 RTL stress and actual whole-top UART gate trace;
does not rerun a build or inject values into the implementation.
"""
from pathlib import Path
from itertools import product
import hashlib
import json
import re
from compare_synth_graph import parse

ROOT=Path(__file__).resolve().parent.parent


def main():
    vg=ROOT/'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
    module=parse(vg.read_text())['game_p3_score_bank']
    nets={name:{i:name if i is None else f'{name}[{i}]' for i in indices}
          for name,indices in module['declarations'].items()}
    inputs={b for p,(kind,indices) in module['ports'].items() if kind=='input' for b in nets[p].values()}
    def bits(expr):
        expr=expr.strip()
        if expr.startswith('{'):
            return [b for part in expr[1:-1].split(',') for b in bits(part)]
        m=re.fullmatch(r'(\w+)(?:\[(\d+)(?::(\d+))?\])?',expr)
        assert m and m[1] in nets, expr
        if m[2] is None:return list(nets[m[1]].values())
        ix=[int(m[2])] if m[3] is None else range(int(m[2]),int(m[3])-1,-1)
        return [nets[m[1]][i] for i in ix]
    constants={};drivers={};banks={}
    for kind,name,pins in module['cells']:
        if kind in ['GND','VCC']:
            for expr in pins.values():
                for bit in bits(expr):constants[bit]=int(kind=='VCC')
        elif kind.startswith('LUT'):
            size=int(kind[3:]);assert size in range(2,5)
            drivers[pins['F']]=(int(module['params'][name]['INIT'].split("'h")[1],16),[pins[f'I{i}'] for i in range(size)])
        elif kind=='DPB':banks[name]=pins
    assert set(banks)=={f'score_p{p}_b{c}' for p in range(2) for c in range(5)}
    dependencies={}
    def deps(node):
        if node not in dependencies:
            if node in constants:value=set()
            elif node in inputs:value={node}
            else:
                assert node in drivers, ('unsupported combinational dependency',node)
                value=set().union(*(deps(n) for n in drivers[node][1]))
            dependencies[node]=value
        return dependencies[node]
    def evaluate(node,env):
        if node in constants:return constants[node]
        if node in env:return env[node]
        init,ports=drivers[node]
        return (init>>sum(evaluate(n,env)<<i for i,n in enumerate(ports)))&1
    cases=0
    def environments(nodes,extra=()):
        nonlocal cases
        names=sorted(set().union(*(deps(n) for n in nodes))|set(extra))
        assert len(names)<=12, ('inspect expanded proof domain',names)
        for values in product(range(2),repeat=len(names)):
            env=dict(zip(names,values))
            if env.get('score_write')==1:
                cases+=1;yield env
    logical_bits=list(range(25))+list(range(32,57))+list(range(64,75))+list(range(80,96))
    assert len(logical_bits)==77
    for page in range(2):
        first=banks[f'score_p{page}_b0']
        for col in range(5):
            pins=banks[f'score_p{page}_b{col}']
            assert all(pins[k]==first[k] for k in ['WREB','CEB','ADB','CLKB','RESETB'])
            for i,node in enumerate(reversed(bits(pins['DIB']))):
                bit=col*16+i
                if bit<77:assert node==f'score_write_data_{logical_bits[bit]}',(page,col,i,node)
                else:assert constants[node]==0
        adb=bits(first['ADB']);assert adb[-2:]==['score_write']*2
        assert all(constants[n]==0 for n in adb[-4:-2])
        for env in environments([first['WREB'],first['CEB']],['score_write','score_write_address[10]']):
            expected=int(env['score_write_address[10]']==page)
            assert evaluate(first['WREB'],env)==expected and evaluate(first['CEB'],env)==expected,env
        for i,node in enumerate(reversed(adb[:10])):
            for env in environments([node],['score_write',f'score_write_address[{i}]']):
                assert evaluate(node,env)==env[f'score_write_address[{i}]'],(i,env)
    record=dict(result='PASS',netlist_sha256=hashlib.sha256(vg.read_bytes()).hexdigest(),
        tool_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        scope='Actual complete VG bank module; exhaustive write-domain truth tables, all reader controls unconstrained',
        boolean_cases=cases,pages=2,dpb16=10,logical_bits=96,stored_meaningful_bits=77,
        proven=['Only target page written/enabled','All10 word-address bits equal write address during write',
                'Both16-bit byte enables asserted on write','All77 time/MIDI/lane/velocity/group bits wired in exact packed order'])
    output=ROOT/'build/p4_posture/impl_a2_centered/bank_write_audit.json'
    output.write_text(json.dumps(record,indent=2)+'\n')
    print('PASS: actual VG two-page write isolation/all10 address bits/all77 data bits/both byte enables;',cases,'exhaustive Boolean cases')


if __name__=='__main__':main()
