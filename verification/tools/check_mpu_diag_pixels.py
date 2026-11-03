"""Compare actual LCD pin capture against a separately rasterized ASCII page."""
import argparse
import json
from pathlib import Path
from PIL import Image
from generate_mpu_diag_screen import FONT, LINES, STATUS


def main():
    p=argparse.ArgumentParser()
    p.add_argument('run',type=Path)
    args=p.parse_args()
    values=[int(x,16) for x in (args.run/'lcd_top_snapshot.txt').read_text().split()]
    (a68,a69,v68,v69,i68,i69,addr,e68,e69,stat,err,step,regno,
     expected,actual,count,faults,age,iscl,isda,chip)=values
    lines=dict(LINES)
    lines.update({2:f'IDLE SCL:{iscl} SDA:{isda}   100KHZ',
      3:f'68 ACK:{a68} ID:{i68:02X}' if v68 else f'68 ACK:{a68} ID:--',
      4:f'69 ACK:{a69} ID:{i69:02X}' if v69 else f'69 ACK:{a69} ID:--',
      5:'STATUS: '+STATUS[stat],6:f'STEP:{step:02X} REG:{regno:02X} ADDR:{addr:02X}',
      7:f'CHECK EXP:{expected:02X} GOT:{actual:02X} E:{err:X}',
      8:f'FAULT:{faults:08X} AGE:{age:04X}',9:f'COUNT HEX:{count:08X}',
      10:'AX:-02048 AY:+01024',11:'AZ:+08192   1G=8192',
      12:'GX:+00257 GY:-04321',13:'GZ:+00000   CHIP:'+{0x68:'6050',0x70:'6500'}.get(chip,'----')})
    lines[3]+=f' ERR:{e68:X}'
    lines[4]+=f' ERR:{e69:X}'
    expected_image=Image.new('RGB',(480,272))
    pix=expected_image.load()
    for y in range(272):
        row,ly=divmod(y,16)
        text=lines.get(row,'').ljust(30)
        for x in range(480):
            col,lx=divmod(x,16)
            bg=(24,60,84) if row==0 else (12,24,36)
            color=bg
            glyph=FONT.get(text[col])
            if glyph and 3<=lx<13 and 1<=ly<15 and glyph[(ly-1)//2][(lx-3)//2]=='1':
                color=((48,240,104) if stat==7 else (240,192,48) if stat in (0,3,6) else (252,72,56)) if row==5 else (224,236,244)
            pix[x,y]=color
    captured=Image.open(args.run/'lcd_diag_top.ppm').convert('RGB')
    mismatches=sum(a!=b for a,b in zip(captured.getdata(),expected_image.getdata()))
    assert captured.size==(480,272) and mismatches==0, f'{mismatches} mismatched LCD pixels'
    captured.save(args.run/'lcd_diag_top.png')
    expected_image.save(args.run/'lcd_diag_expected.png')
    record={'result':'PASS','active_pixels':480*272,'mismatches':mismatches,
            'scope':'RTL top actual LCD rising-edge output versus independent font rasterization',
            'snapshot':dict(zip(('ack68','ack69','id68_valid','id69_valid','id68','id69','address',
             'error68','error69','status','error','step','register','expected','actual','count',
             'faults','age','idle_scl','idle_sda','chip'),values))}
    (args.run/'pixels.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8')
    print(f'PASS: {480*272} actual LCD pin pixels match, including RGB/coordinate pipeline alignment')


if __name__=='__main__':main()
