"""Export every enabled project input and literal HDL dependency, code only."""
import hashlib,re,zipfile
import xml.etree.ElementTree as ET
from build_dual_score_transport import ROOT,BASE,PROJECT,guard,sha,load,save

manifest=guard()
assert manifest==load(BASE/'synth_04/source_manifest.json')
pending=[PROJECT]+[(PROJECT.parent/n.attrib['path']).resolve() for n in ET.parse(PROJECT).findall('./FileList/File') if n.attrib.get('enable','1')=='1']
files=set()
while pending:
    p=pending.pop().resolve()
    assert p.is_relative_to(ROOT) and p.is_file(),p
    if p in files:continue
    files.add(p)
    assert p.suffix.lower() in {'.v','.vh','.mem','.gprj','.cst','.sdc'},p
    assert sha(p)==manifest[p.relative_to(ROOT).as_posix()],p
    if p.suffix.lower() in {'.v','.vh'}:
        body=p.read_text(encoding='utf-8-sig')
        for include,mem in re.findall(r'`include\s+"([^"]+)"|\$(?:readmemh|readmemb)\s*\(\s*"([^"]+)"',body):
            pending.append((p.parent/(include or mem)).resolve())
out=ROOT/'build/exports/neo_guitar_touch_game_ks_fifth_v2_lcd180_slots123_dual_uart_code_only_20261102.zip'
out.parent.mkdir(parents=True,exist_ok=True)
assert not out.exists(),out
members={p.relative_to(ROOT).as_posix():sha(p) for p in sorted(files)}
with zipfile.ZipFile(out,'x',zipfile.ZIP_DEFLATED) as z:
    for name in members:z.write(ROOT/name,name)
with zipfile.ZipFile(out) as z:
    assert z.testzip() is None and set(z.namelist())==set(members)
    for name,h in members.items():assert hashlib.sha256(z.read(name)).hexdigest()==h,name
assert guard()==manifest
save(BASE/'source_package_manifest.json',dict(result='PASS',archive=str(out),sha256=sha(out),files=len(members),
    source_sha256=members,scope='Enabled original GPRJ inputs plus transitive literal include/readmem closure; no README/reports/bitstreams/tests/app binaries. Source hashes match actual synthesis inputs.'))
print(f'PASS: {len(members)} code/input files, no README; {out}')
