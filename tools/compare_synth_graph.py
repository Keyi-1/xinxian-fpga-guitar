"""Fail-closed pin graph comparison for Gowin's structural Verilog subset.

Ignore comments, hierarchy and net/instance names only. Preserve every reachable
primitive, parameter, top-level port, literal constant and pin-bit connection.
No Boolean rewriting, simulation assumptions or timing exceptions are allowed.
Unsupported Verilog fails rather than being skipped. Port splitting is resolved
by exact scalar aliases at the parent/child boundary.
"""
from pathlib import Path
from collections import Counter
import argparse
import hashlib
import json
import re

NAME=r'(?:\\[^\s]+|[A-Za-z_$][\w$]*)'
DECL=re.compile(rf'(input|output|inout|wire)\s+(?:\[(\d+):(\d+)\]\s*)?({NAME})\s*;')
CELL=re.compile(rf'({NAME})\s+({NAME})\s*\((.*?)\)\s*;',re.S)
PARAM=re.compile(rf'defparam\s+({NAME})\s*\.\s*(\w+)\s*=\s*([^;]+);')
PIN=re.compile(rf'\.({NAME})\s*\(([^()]*)\)')
REF=re.compile(rf'({NAME})\s*(?:\[\s*(\d+)\s*(?::\s*(\d+)\s*)?\])?\s*$')
SPACE=re.compile(r'\s*')
HEADER=re.compile(r'\s*module\s+(\w+)\s*\((.*?)\)\s*;',re.S)


def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def parse(text):
    # The emitted netlist contains no string literals with comment delimiters.
    # Reject those rather than accidentally interpreting their contents.
    assert not re.search(r'"[^"\n]*(?://|/\*)[^"\n]*"',text)
    text=re.sub(r'/\*.*?\*/','',text,flags=re.S)
    text=re.sub(r'//[^\n]*','',text)
    scales=re.findall(r'^`timescale[^\n]*',text,re.M)
    assert scales==['`timescale 100 ps/100 ps'],('unexpected timescale',scales)
    text=re.sub(r'^`timescale 100 ps/100 ps\s*$', '', text,flags=re.M)
    modules={};pos=0
    while pos<len(text):
        m=HEADER.match(text,pos)
        if not m:
            assert not text[pos:].strip(),('unsupported outside module',text[pos:pos+100])
            break
        name=m[1];header_ports=[p.strip() for p in m[2].split(',')]
        assert all(re.fullmatch(NAME,p) for p in header_ports)
        assert len(header_ports)==len(set(header_ports))
        pos=m.end();end=text.index('endmodule',pos)
        body=text[pos:end];pos=end+len('endmodule')
        declarations={};ports={};cells=[];params={};cursor=0
        while cursor<len(body):
            cursor=SPACE.match(body,cursor).end()
            if cursor==len(body):break
            d=DECL.match(body,cursor)
            if d:
                kind,hi,lo,net=d.groups();net=net.strip()
                bits=list(range(int(hi),int(lo)-1,-1)) if hi is not None else [None]
                assert net not in declarations,(name,'duplicate declaration',net)
                declarations[net]=bits
                if kind!='wire':ports[net]=(kind,bits)
                cursor=d.end();continue
            p=PARAM.match(body,cursor)
            if p:
                key=(p[1].strip(),p[2]);assert key not in params
                params[key]=p[3].strip();cursor=p.end();continue
            c=CELL.match(body,cursor)
            assert c,('unsupported structural statement',name,body[cursor:cursor+120])
            kind,instance,connections=c.groups();pins={};pin_cursor=0
            for pin in PIN.finditer(connections):
                assert re.fullmatch(r'[\s,]*',connections[pin_cursor:pin.start()]),(name,instance,connections[pin_cursor:pin.start()])
                assert pin[1] not in pins,(name,instance,pin[1])
                pins[pin[1]]=pin[2].strip();pin_cursor=pin.end()
            assert re.fullmatch(r'[\s,]*',connections[pin_cursor:])
            cells.append((kind.strip(),instance.strip(),pins));cursor=c.end()
        names=[c[1] for c in cells];name_set=set(names);assert len(names)==len(name_set)
        assert all(i in name_set for i,p in params),(name,'orphan defparam')
        assert set(header_ports)==set(ports),(name,'header/declaration mismatch')
        assert name not in modules
        by_instance={}
        for (instance,param),value in params.items():by_instance.setdefault(instance,{})[param]=value
        modules[name]=dict(declarations=declarations,ports=ports,cells=cells,params=by_instance)
    return modules


class Graph:
    def __init__(self,modules,top):
        self.modules=modules;self.parent=[];self.leaves=[];self.constants={};self.instances=Counter()
        self.top=self.walk(top,{},set())

    def node(self):
        n=len(self.parent);self.parent.append(n);return n

    def find(self,n):
        p=self.parent
        while p[n]!=n:p[n]=p[p[n]];n=p[n]
        return n

    def union(self,a,b):
        a=self.find(a);b=self.find(b)
        if a!=b:self.parent[b]=a

    def expression(self,expr,nets):
        expr=expr.strip()
        if not expr:return []
        if expr.startswith('{'):
            assert expr.endswith('}')
            inside=expr[1:-1].strip()
            repeat=re.fullmatch(r'(\d+)\s*\{(.*)\}',inside,re.S)
            if repeat:return self.expression('{'+repeat[2]+'}',nets)*int(repeat[1])
            depth=0;parts=[];start=0
            for i,char in enumerate(inside):
                if char=='{':depth+=1
                elif char=='}':depth-=1
                elif char==',' and depth==0:parts.append(inside[start:i]);start=i+1
                assert depth>=0
            assert depth==0
            parts.append(inside[start:])
            return [n for p in parts for n in self.expression(p,nets)]
        literal=re.fullmatch(r"(\d+)'([bBoOdDhH])([0-9a-fA-F_xXzZ]+)",expr)
        if literal:
            width=int(literal[1]);digits=literal[3].replace('_','').lower();base=literal[2].lower()
            assert not re.search('[xz]',digits),'Unknown literals require explicit handling'
            value=int(digits,dict(b=2,o=8,d=10,h=16)[base])
            result=[]
            for bit in reversed(range(width)):
                v=(value>>bit)&1
                if v not in self.constants:self.constants[v]=self.node()
                result.append(self.constants[v])
            return result
        ref=REF.fullmatch(expr)
        assert ref,('unsupported pin expression',expr)
        name,hi,lo=ref.groups();name=name.strip();assert name in nets,('undeclared net',name)
        if hi is None:return list(nets[name].values())
        bits=[int(hi)] if lo is None else list(range(int(hi),int(lo)-1,-1))
        assert bits and all(i in nets[name] for i in bits),(name,bits,nets[name])
        return [nets[name][i] for i in bits]

    def walk(self,name,bindings,ancestors):
        assert name not in ancestors,('recursive module',name)
        module=self.modules[name];self.instances[name]+=1
        nets={net:{bit:self.node() for bit in bits} for net,bits in module['declarations'].items()}
        assert set(bindings)<=set(module['ports']),('unknown instance port',name,set(bindings)-set(module['ports']))
        for port,actual in bindings.items():
            formal=list(nets[port].values())
            if not actual:continue
            assert len(formal)==len(actual),('port width mismatch',name,port,len(formal),len(actual))
            for a,b in zip(formal,actual):self.union(a,b)
        for kind,instance,pins in module['cells']:
            resolved={p:self.expression(e,nets) for p,e in pins.items()}
            parameters=module['params'].get(instance,{})
            if kind in self.modules:
                assert not parameters,('hierarchical defparam not supported',kind,instance)
                self.walk(kind,resolved,ancestors|{name})
            else:
                self.leaves.append((kind,resolved,parameters))
        return {port:(kind,list(nets[port].values()),bits) for port,(kind,bits) in module['ports'].items()}

    def signature(self):
        ranks={};literal_roots={self.find(n):v for v,n in self.constants.items()}
        assert len(literal_roots)==len(self.constants),'Conflicting constant aliases'
        def net(n):
            root=self.find(n)
            if root not in ranks:ranks[root]=len(ranks)
            return [ranks[root],literal_roots.get(root)]
        h=hashlib.sha256();types=Counter();pin_bits=0
        def add(value):h.update(json.dumps(value,separators=(',',':')).encode());h.update(b'\n')
        for name,(kind,nodes,bits) in sorted(self.top.items()):
            add(['top',name,kind,bits,[net(n) for n in nodes]])
        for kind,pins,params in self.leaves:
            types[kind]+=1
            resolved=[]
            for name,nodes in sorted(pins.items()):
                pin_bits+=len(nodes);resolved.append([name,[net(n) for n in nodes]])
            add(['cell',kind,sorted(params.items()),resolved])
        return dict(graph_sha256=h.hexdigest(),primitive_count=len(self.leaves),pin_bits=pin_bits,
                    connected_nets=len(ranks),primitive_types=dict(sorted(types.items())),
                    module_instances=dict(sorted(self.instances.items())))


def compare(before,after,top='neo_guitar_touch_game_top'):
    signatures=[]
    for path in [before,after]:
        graph=Graph(parse(Path(path).read_text(encoding='utf-8-sig')),top)
        signatures.append(graph.signature())
        del graph
    assert signatures[0]==signatures[1],('structural pin graph changed',signatures)
    return dict(result='PASS',method='Exact flattened primitive/pin-bit connectivity and parameter equality; names/comments ignored',
                before_sha256=sha(before),after_sha256=sha(after),top=top,**signatures[0])


def main():
    p=argparse.ArgumentParser();p.add_argument('before',type=Path);p.add_argument('after',type=Path)
    p.add_argument('--top',default='neo_guitar_touch_game_top');p.add_argument('--output',type=Path)
    a=p.parse_args();result=compare(a.before,a.after,a.top)
    result['checker_sha256']=sha(__file__)
    if a.output:a.output.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))


if __name__=='__main__':main()
