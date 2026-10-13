"""Small fixed interface font; includes only the prototype's visible glyphs."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parent.parent
MESSAGES=['模式选择','演奏模式','游戏模式','曲目选择','茉莉花','待导入','准备演奏',
          '开始','试听','高音','低音','演奏结束','重玩','选曲','主页','触控未连接',
          '双击返回','返回','切换中','SCORE','COMBO','MAX','HIT','MISS','教学单旋律','拨弦跟随滑块',
          '自由演奏','节奏挑战','PERFECT','GOOD','BAD','WRONG']

def main():
    chinese=''.join(dict.fromkeys(''.join(s for s in MESSAGES if not s.isascii())))
    characters=chinese+'ABCDEFGHIJKLMNOPQRSTUVWXYZ'+'0123456789'+' -/.'
    assert len(characters)<=128
    font=ImageFont.truetype('C:/Windows/Fonts/simhei.ttf',16)
    rows=[]
    for char in characters:
        glyph=Image.new('L',(16,16));ImageDraw.Draw(glyph).text((0,-2),char,font=font,fill=255)
        rows.extend(sum((1<<(15-x)) for x in range(16) if glyph.getpixel((x,y))>=100) for y in range(16))
    rows += [0]*(2048-len(rows))
    (ROOT/'mem/game_font_16.mem').write_text(''.join(f'{r:04x}\n' for r in rows),encoding='ascii')
    lines=['// Generated fixed UI messages; not a complete Chinese font.',
           f'`define GAME_DIGIT_BASE {characters.index("0")}',
           'function [6:0] game_message_glyph;', '    input [4:0] message_id; input [4:0] character_index;',
           '    begin', '        case({message_id,character_index})']
    for msg_id,msg in enumerate(MESSAGES):
        for i,char in enumerate(msg):
            lines.append(f"            10'd{msg_id*32+i}:game_message_glyph=7'd{characters.index(char)};")
    lines+= [f"            default:game_message_glyph=7'd{characters.index(' ')};",'        endcase','    end','endfunction']
    (ROOT/'rtl/config/game_ui_messages.vh').write_text('\n'.join(lines)+'\n',encoding='ascii')
    indices=[characters.index(' ')]*1024
    for msg_id,msg in enumerate(MESSAGES):
        for i,char in enumerate(msg):indices[msg_id*32+i]=characters.index(char)
    (ROOT/'mem/game_message_index.mem').write_text(''.join(f'{v:02x}\n' for v in indices),encoding='ascii')
    (ROOT/'scores/game_font.json').write_text(json.dumps(dict(size=16,characters=characters,messages=MESSAGES),
        ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'Fixed UI font: {len(characters)} glyphs, 2048 x 16-bit rows')

if __name__=='__main__':main()
