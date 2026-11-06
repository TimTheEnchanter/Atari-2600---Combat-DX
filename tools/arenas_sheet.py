"""Render every arena (play state, power-up box visible) into one sheet."""
import sys
sys.path.insert(0, 'tools')
from harness import Game
from test_ai import setarena
from emu2600 import PALETTE
from PIL import Image, ImageDraw
names = ["Open Field", "Easy Maze", "Complex Maze", "Pillars", "Fortress", "Crossfire", "Bunkers", "Labyrinth"]
tiles = []
for a in range(8):
    g = Game(); g.frame(3); g.set_game(13); setarena(g, a)
    g.w('frame', 0)
    rom = g.e.cart.data
    sx = rom[g.s['SpotX'] - 0xF000 + 0x1000 + a * 4]; sy = rom[g.s['SpotY'] - 0xF000 + 0x1000 + a * 4]
    g.w('boxX', sx); g.w('boxY', sy); g.w('boxT', 200)
    g.w('frame', 14); g.frame(2)
    f = g.e.frame[40:232]
    im = Image.fromarray(PALETTE[f], 'RGB').resize((320, 192 * 2 // 2 * 2 // 2 * 1 + 0), Image.NEAREST)
    im = Image.fromarray(PALETTE[f], 'RGB').resize((320, 192), Image.NEAREST)
    tiles.append((names[a], im))
sheet = Image.new('RGB', (4 * 330, 2 * 215), (30, 30, 30))
d = ImageDraw.Draw(sheet)
for i, (n, im) in enumerate(tiles):
    x = (i % 4) * 330 + 5; y = (i // 4) * 215 + 18
    sheet.paste(im, (x, y)); d.text((x, y - 14), "%d  %s" % (i + 1, n), fill=(230, 230, 230))
sheet.save('shots/arenas.png')
print("ok")
