"""Create a separate, fixed-pin experimental build; keep accepted projects."""
from pathlib import Path
import json, re
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parent.parent
NAME='neo_guitar_touch_game'

def main():
    project=ROOT/'gowin'/NAME; (project/'impl').mkdir(parents=True,exist_ok=True)
    old=ROOT/'gowin/neo_guitar_i2s'
    new_files=sorted([p.relative_to(ROOT).as_posix() for p in (ROOT/'rtl/game').glob('*.v')])
    new_files += ['rtl/input/i2c_register_master.v','rtl/input/gt911_touch.v','rtl/input/touch_coordinate_mapper.v',
        'rtl/input/touch_gesture.v','rtl/top/neo_guitar_touch_game_top.v']
    build=(old/'build.tcl').read_text(encoding='utf-8').replace('neo_guitar_i2s',NAME)
    build=build.replace('rtl/top/neo_guitar_touch_game_top.v','\n'.join('    '+p for p in new_files).lstrip())
    (project/'build.tcl').write_text(build,encoding='utf-8')
    tree=ET.parse(old/'neo_guitar_i2s.gprj')
    for elem in tree.iter():
        if elem.text:elem.text=elem.text.replace('neo_guitar_i2s',NAME)
        for k,v in list(elem.attrib.items()):elem.set(k,v.replace('neo_guitar_i2s',NAME))
    files=tree.find('FileList')
    for elem in list(files):
        if elem.get('path')=='../../rtl/top/neo_guitar_touch_game_top.v':files.remove(elem)
    for p in new_files:ET.SubElement(files,'File',path='../../'+p,type='file.verilog',enable='1')
    ET.indent(tree,space='    ');tree.write(project/(NAME+'.gprj'),encoding='utf-8',xml_declaration=True)
    cfg=json.loads((old/'impl/neo_guitar_i2s_process_config.json').read_text(encoding='utf-8-sig').replace('neo_guitar_i2s',NAME))
    (project/'impl'/f'{NAME}_process_config.json').write_text(json.dumps(cfg,indent=2)+'\n',encoding='utf-8')
    (project/'configure_ide.ps1').write_text((old/'configure_ide.ps1').read_text(encoding='utf-8').replace('neo_guitar_i2s',NAME),encoding='utf-8')
    cst=(ROOT/'constraints/neo_guitar_i2s.cst').read_text(encoding='utf-8')
    cst += '\n// Native J6 touch connector; user confirmed the IO voltage is compatible.\n'
    for port,pin in [('ctp_rst_n','T15'),('ctp_int','T16'),('ctp_sda','U16'),('ctp_scl','W16')]:
        voltage=' BANK_VCCIO=3.3' if port=='ctp_int' else ''
        cst+=f'IO_LOC "{port}" {pin};\nIO_PORT "{port}" IO_TYPE=LVCMOS33 PULL_MODE=NONE DRIVE=4{voltage};\n'
    pins=re.findall(r'IO_LOC\s+"[^"]+"\s+(\w+)',cst);assert len(pins)==len(set(pins))==59
    (ROOT/'constraints'/f'{NAME}.cst').write_text(cst,encoding='utf-8')
    sdc=(ROOT/'constraints/neo_guitar_i2s.sdc').read_text(encoding='utf-8')
    sdc+='\n# Touch bus inputs are synchronized before state decisions.\nset_false_path -from [get_ports {ctp_scl ctp_sda ctp_int}]\n'
    (ROOT/'constraints'/f'{NAME}.sdc').write_text(sdc,encoding='utf-8')
    print(f'Created {project}: 59 unique pins; touch uses native J6, INT=J6-4/T16')

if __name__=='__main__':main()
