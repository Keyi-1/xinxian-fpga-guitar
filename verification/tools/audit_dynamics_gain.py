"""Exhaustively check actual velocity DSP gain operands in all four voices.

The full-top gate traces also check DSP clocking/output, but use fixed preview
velocity2. This separate proof covers the newly changed level0, both source
selectors, and every nonselected input without forcing any netlist signal.
"""
from pathlib import Path
from itertools import product
import hashlib
import json
import re
from compare_synth_graph import parse

ROOT=Path(__file__).resolve().parent.parent
RUN=ROOT/'build/velocity_calibration/dynamics_v1'
OLD=ROOT/'build/releases/touch_game/p4_velocity_calibration_20261019/evidence/gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    vg=ROOT/'gowin/neo_guitar_touch_game/impl/gwsynthesis/neo_guitar_touch_game.vg'
    modules=parse(vg.read_text(encoding='utf-8'))
    before=parse(OLD.read_text(encoding='utf-8'))
    assert digest(OLD)=='f64a6960a33513f73e2c60006b31a0fdf18970cce2fd0a23a128eb81e816e3c2'
    voices={n:m for n,m in modules.items() if re.fullmatch(r'piano_voice_core(?:_[012])?',n)}
    assert len(voices)==4
    cases=0;proof={}
    for name,module in voices.items():
        nets={n:{i:n if i is None else f'{n}[{i}]' for i in indices} for n,indices in module['declarations'].items()}
        def bits(expr):
            expr=expr.strip()
            if expr.startswith('{'):
                return [b for part in expr[1:-1].split(',') for b in bits(part)]
            match=re.fullmatch(r'(\w+)(?:\[(\d+)(?::(\d+))?\])?',expr)
            assert match and match[1] in nets,expr
            if match[2] is None:return list(nets[match[1]].values())
            indexes=[int(match[2])] if match[3] is None else range(int(match[2]),int(match[3])-1,-1)
            return [nets[match[1]][i] for i in indexes]
        constants={};drivers={}
        for kind,instance,pins in module['cells']:
            if kind in ['GND','VCC']:
                for expr in pins.values():
                    for bit in bits(expr):constants[bit]=int(kind=='VCC')
            elif re.fullmatch(r'LUT[1-4]',kind):
                size=int(kind[3:]);init=module['params'][instance]['INIT']
                match=re.fullmatch(r"\d+'h([0-9a-fA-F]+)",init);assert match
                drivers[pins['F']]=(int(match[1],16),[pins[f'I{i}'] for i in range(size)])
        def evaluate(node,env,ancestors=()):
            assert node not in ancestors,('loop',node)
            if node in constants:return constants[node]
            if node in env:return env[node]
            assert node in drivers,('unsupported gain dependency',node)
            init,ports=drivers[node]
            return (init>>sum(evaluate(n,env,ancestors+(node,))<<i for i,n in enumerate(ports)))&1
        targets=[(k,n,p) for k,n,p in module['cells'] if k=='MULT27X36' and 'velocity_product' in p['DOUT'] and 'release_product' not in p['DOUT']]
        assert len(targets)==1
        _,instance,pins=targets[0]
        params=module['params'][instance]
        old_targets=[(k,n,p) for k,n,p in before[name]['cells'] if k=='MULT27X36' and 'velocity_product' in p['DOUT'] and 'release_product' not in p['DOUT']]
        assert len(old_targets)==1
        old_instance=old_targets[0][1]
        assert params==before[name]['params'][old_instance],'DSP input/output pipeline parameters changed'
        assert params['AREG_CLK']=='"CLK0"' and params['AREG_CE']=='"CE0"' and params['BREG_CLK']=='"BYPASS"'
        assert params['OREG_CLK']=='"CLK0"' and params['OREG_CE']=='"CE1"'
        assert pins['CLK']==old_targets[0][2]['CLK'] and pins['RESET']==old_targets[0][2]['RESET']
        operand=bits(pins['A']);assert len(operand)==27
        results=[]
        for mode,velocity,game_velocity in product([1,2],range(4),range(4)):
            env={f'mode_Z[{i}]':(mode>>i)&1 for i in range(2)}
            for p,value in [('velocity',velocity),('game_velocity',game_velocity)]:
                ix=list(reversed(module['ports'][p][1]));assert len(ix)==2
                env.update({f'{p}[{bit}]':(value>>i)&1 for i,bit in enumerate(ix)})
            observed=sum(evaluate(node,env)<<i for i,node in enumerate(reversed(operand)))
            expected=[64,160,208,256][game_velocity if mode==2 else velocity]
            assert observed==expected,(name,mode,velocity,game_velocity,observed,expected)
            results.append(observed);cases+=1
        proof[name]=dict(instance=instance,actual_operand_a=pins['A'],cases=len(results),
            values=sorted(set(results)),dsp_parameters_unchanged=True)
    record=dict(result='PASS',netlist_sha256=digest(vg),saved_netlist_sha256=digest(OLD),
        tool_sha256=digest(Path(__file__)),boolean_cases=cases,voices=proof,
        scope='All actual voice velocity DSP27-bit positive gain operands; every performance/game grade and nonselected input, both modes; original DSP clock/reset/input/output pipeline parameters retained. Static mapping proof, complemented by full-top gate timing traces; no forces.')
    (RUN/'gain_operand_audit.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print('PASS: all4 actual voice DSP gains64/160/208/256, performance/game selectors,',cases,'exhaustive combinations; original DSP pipeline retained')

if __name__=='__main__':main()
