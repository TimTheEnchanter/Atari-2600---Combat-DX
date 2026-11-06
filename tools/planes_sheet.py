"""Render plane games mid-flight into one sheet."""
import sys
sys.path.insert(0, 'tools')
from harness import Game
from emu2600 import PALETTE
from PIL import Image, ImageDraw
games = [(35, "35 Biplanes, clouds"), (38, "38 Biplanes 2 v 2"), (39, "39 Biplane v 3, clouds"),
         (40, "40 Jets, clouds"), (43, "43 Jets 2 v 2, guided"), (44, "44 Bomber v 3")]
tiles = []
for n, label in games:
    g = Game(); g.frame(3); g.set_game(n)
    for f in range(70):
        g.joy(0, left=(f // 20) % 2 == 0, fire=(f % 30 == 10))
        g.joy(1, right=(f // 25) % 2 == 0, fire=(f % 30 == 20))
        g.frame()
    tiles.append((label, Image.fromarray(PALETTE[g.e.frame[40:232]], 'RGB').resize((320, 192), Image.NEAREST)))
    print(label, "lines", set(g.lines[5:]))
sheet = Image.new('RGB', (3 * 330, 2 * 215), (30, 30, 30))
d = ImageDraw.Draw(sheet)
for i, (lab, im) in enumerate(tiles):
    x = (i % 3) * 330 + 5; y = (i // 3) * 215 + 18
    sheet.paste(im, (x, y)); d.text((x, y - 14), lab, fill=(230, 230, 230))
sheet.save('shots/planes.png')
