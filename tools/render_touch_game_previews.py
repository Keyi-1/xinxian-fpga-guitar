"""Convert actual RTL-generated PPM pixels; do not recreate the interface."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
NAMES = ['touch_home', 'touch_songs', 'touch_ready', 'touch_game', 'touch_result']


def main():
    out = ROOT/'build/touch_game/previews'
    out.mkdir(parents=True, exist_ok=True)
    sheet = Image.new('RGB', (960, 816), (5, 9, 16))
    for i, name in enumerate(NAMES):
        image = Image.open(ROOT/'sim/temp/touch_game'/f'{name}.ppm')
        assert image.size == (480, 272)
        image.save(out/f'{name}.png')
        sheet.paste(image, ((i % 2)*480, (i // 2)*272))
    sheet.save(out/'contact_sheet.png')
    print(out)


if __name__ == '__main__':
    main()
