#!/usr/bin/env python3
"""Generates the data tables for Combat DX.

Writes:
  bank0_data.inc  maze collision maps, row/column lookup, velocity tables,
                  start positions, power-up spots, sound data, misc tables
  bank1_data.inc  expanded maze playfield columns, tank shapes, digits,
                  title logo
Arena grid: 40 x 21 cells (cell = 4 px wide x 4 line-pairs tall),
left half designed here and mirrored by the reflected playfield.
"""
import math

ARENAS = [
 ("Open Field", [
  "####################",
  "#...................",
  "#...................",
  "#...................",
  "#...................",
  "#...................",
  "#...................",
  "#...................",
  "#...................",
  "#...................",
  "#...................",
  "#...................",
  "#...................",
  "#...................",
  "#...................",
  "#...................",
  "#...................",
  "#...................",
  "#...................",
  "#...................",
  "####################"]),
 ("Easy Maze", [
  "####################",
  "#...................",
  "#...................",
  "#.....#####.........",
  "#.....#.............",
  "#.....#.............",
  "#...................",
  "#..........##.......",
  "#..........##.......",
  "#...................",
  "#..................#",
  "#...................",
  "#..........##.......",
  "#..........##.......",
  "#...................",
  "#.....#.............",
  "#.....#.............",
  "#.....#####.........",
  "#...................",
  "#...................",
  "####################"]),
 ("Complex Maze", [
  "####################",
  "#...................",
  "#...................",
  "#...#####......#####",
  "#...#...............",
  "#...#.......#.......",
  "#...........#.......",
  "#.......#####.......",
  "#...................",
  "#..................#",
  "#.......#..........#",
  "#..................#",
  "#...................",
  "#.......#####.......",
  "#...........#.......",
  "#...#.......#.......",
  "#...#...............",
  "#...#####......#####",
  "#...................",
  "#...................",
  "####################"]),
 ("Pillars", [
  "####################",
  "#...................",
  "#...................",
  "#.....##.....##.....",
  "#.....##.....##.....",
  "#...................",
  "#...................",
  "#.........##......##",
  "#.........##......##",
  "#...................",
  "#...................",
  "#...................",
  "#.........##......##",
  "#.........##......##",
  "#...................",
  "#...................",
  "#.....##.....##.....",
  "#.....##.....##.....",
  "#...................",
  "#...................",
  "####################"]),
 ("Fortress", [
  "####################",
  "#...................",
  "#...................",
  "#...................",
  "#.....######........",
  "#..........#........",
  "#..........#......##",
  "#...................",
  "#...................",
  "#...................",
  "#.......#...........",
  "#...................",
  "#...................",
  "#...................",
  "#..........#......##",
  "#..........#........",
  "#.....######........",
  "#...................",
  "#...................",
  "#...................",
  "####################"]),
 ("Crossfire", [
  "####################",
  "#...................",
  "#...................",
  "#...................",
  "#.....##############",
  "#...................",
  "#...................",
  "#...................",
  "#..........#........",
  "#..........#........",
  "#..........#........",
  "#..........#........",
  "#..........#........",
  "#...................",
  "#...................",
  "#...................",
  "#.....##############",
  "#...................",
  "#...................",
  "#...................",
  "####################"]),
 ("Bunkers", [
  "####################",
  "#...................",
  "#...................",
  "#....###.......###..",
  "#......#.........#..",
  "#......#.........#..",
  "#...................",
  "#..........###......",
  "#..........#........",
  "#..........#........",
  "#...................",
  "#..........#........",
  "#..........#........",
  "#..........###......",
  "#...................",
  "#......#.........#..",
  "#......#.........#..",
  "#....###.......###..",
  "#...................",
  "#...................",
  "####################"]),
 ("Labyrinth", [
  "####################",
  "#...................",
  "#...................",
  "#...................",
  "#....#######....####",
  "#....#..............",
  "#....#..............",
  "#....#..............",
  "#.........#.........",
  "#.........#.........",
  "#.........#.........",
  "#.........#.........",
  "#.........#.........",
  "#....#..............",
  "#....#..............",
  "#....#..............",
  "#....#######....####",
  "#...................",
  "#...................",
  "#...................",
  "####################"]),
]

NA = len(ARENAS)
ROWS = 21
START_X, START_Y = 9, 39          # P0 start (P1 mirrored)

def grid(rows):
    g = []
    for r in rows:
        assert len(r) == 20, r
        full = r + r[::-1]
        g.append([c == '#' for c in full])
    assert len(g) == ROWS
    return g

def row_of_pair(p):
    if 1 <= p <= 84:
        return (84 - p) // 4
    return 0

def col_of_x(x):
    if x >= 160:
        return 0
    return x // 4

def wall(g, x, p):
    return g[row_of_pair(p)][col_of_x(x)]

def tank_clear(g, x, y):
    for px in (x + 1, x + 4, x + 6):
        for py in (y + 1, y + 4, y + 6):
            if wall(g, px, py):
                return False
    return True

def reachable(g, sx, sy):
    from collections import deque
    seen = {(sx, sy)}; q = deque([(sx, sy)])
    while q:
        x, y = q.popleft()
        for dx, dy in ((2, 0), (-2, 0), (0, 2), (0, -2)):
            n = (x + dx, y + dy)
            if n in seen or not (0 <= n[0] < 152 and 1 <= n[1] < 80):
                continue
            if tank_clear(g, *n):
                seen.add(n); q.append(n)
    return seen

def lohi(v):
    v &= 0xFFFF
    return v & 0xFF, v >> 8

def byte_rows(name, vals, per=16):
    out = []
    for i in range(0, len(vals), per):
        out.append("    .byte " + ",".join("$%02X" % (v & 0xFF) for v in vals[i:i + per]))
    return name + "\n" + "\n".join(out) + "\n"

b0 = []
b1 = []
b2 = []

# ------------------------------------------------------------ arenas
spots_all = []
starts = []
print("Arena checks:")
for ai, (name, rows) in enumerate(ARENAS):
    g = grid(rows)
    x0, y0 = START_X, START_Y
    x1 = 152 - x0
    assert tank_clear(g, x0, y0), name + " P0 start blocked"
    assert tank_clear(g, x1, y0), name + " P1 start blocked"
    reach = reachable(g, x0 - (x0 % 2), y0 - (y0 % 2) + 1)
    assert (x1 - x1 % 2, y0 - (y0 % 2) + 1) in reach, name + ": players can't reach each other"
    # power-up spots: open 3x3 cell neighbourhoods near anchors
    anchors = [(78, 44), (40, 76), (116, 12), (78, 20)] if ai % 2 == 0 else \
              [(78, 44), (116, 76), (40, 12), (78, 68)]
    spots = []
    for ax, ay in anchors:
        best = None
        for c in range(1, 39):
            for r in range(1, 20):
                if all(not g[r + dr][c + dc] for dr in (-1, 0, 1) for dc in (-1, 0, 1)):
                    bx, by = c * 4, 84 - r * 4 - 3      # ball lower pair
                    # must be reachable by a tank touching it
                    ok = any((tx, ty) in reach for tx in range(bx - 6, bx + 4) for ty in range(by - 6, by + 4))
                    if not ok:
                        continue
                    d = (bx - ax) ** 2 + ((by - ay) * 1.25) ** 2
                    if best is None or d < best[0]:
                        best = (d, bx, by)
        spots.append(best[1:])
    spots_all.append(spots)
    print("  %-12s ok, reachable positions %4d, spots %s" % (name, len(reach), spots))

# arena maps in playfield format, column-major: 21 PF0 bytes, 21 PF1, 21 PF2.
# Used for collision (bank 0) and copied to Superchip RAM for the kernel.
def pfrow(bits):
    v0 = sum(1 << (4 + i) for i in range(4) if bits[i])
    v1 = sum(1 << (7 - i) for i in range(8) if bits[4 + i])
    v2 = sum(1 << i for i in range(8) if bits[12 + i])
    return v0, v1, v2
maze = []
for name, rows in ARENAS:
    g = grid(rows)
    cols3 = [pfrow(g[r][:20]) for r in range(ROWS)]
    for k in range(3):
        maze += [c[k] for c in cols3]
b0.append(byte_rows("MazeMaps", maze, 21))

rowoff = [row_of_pair(p) for p in range(128)]
colbyte = []; colmask = []
for x in range(176):
    c = col_of_x(x)
    if c >= 20:
        c = 39 - c
    if c < 4:
        colbyte.append(0); colmask.append(1 << (4 + c))
    elif c < 12:
        colbyte.append(21); colmask.append(0x80 >> (c - 4))
    else:
        colbyte.append(42); colmask.append(1 << (c - 12))
b0.append(byte_rows("RowOff", rowoff))
b0.append(byte_rows("ColByte", colbyte))
b0.append(byte_rows("ColMask", colmask))

# start positions and power-up spots
b1.append(byte_rows("SpotX", [s[0] for sp in spots_all for s in sp]))
b1.append(byte_rows("SpotY", [s[1] for sp in spots_all for s in sp]))

# ------------------------------------------------------------ velocity tables
ASPECT = 0.8
def vel_table(speed):
    xs, ys = [], []
    for d in range(16):
        a = d * math.pi / 8
        xs.append(int(round(math.cos(a) * speed * 256)))
        ys.append(int(round(math.sin(a) * speed * ASPECT * 256)))
    return xs, ys
SPEEDS = [0.40, 0.62, -0.25, 1.30]   # tank, tank fast, reverse, missile
vxl = []; vxh = []; vyl = []; vyh = []
for s in SPEEDS:
    xs, ys = vel_table(s)
    for v in xs: l, h = lohi(v); vxl.append(l); vxh.append(h)
    for v in ys: l, h = lohi(v); vyl.append(l); vyh.append(h)
b0.append(byte_rows("VelXL", vxl)); b0.append(byte_rows("VelXH", vxh))
b0.append(byte_rows("VelYL", vyl)); b0.append(byte_rows("VelYH", vyh))

def offs(rx, ry):
    xs, ys = [], []
    for d in range(16):
        a = d * math.pi / 8
        xs.append(int(round(math.cos(a) * rx)) & 0xFF)
        ys.append(int(round(math.sin(a) * ry)) & 0xFF)
    return xs, ys
mx, my = offs(6, 5)
b0.append(byte_rows("MisOfsX", mx)); b0.append(byte_rows("MisOfsY", my))
px, py = offs(13, 11)
b0.append(byte_rows("ProbeX", px)); b0.append(byte_rows("ProbeY", py))

b0.append(byte_rows("GameBCD", [int(str(n + 1), 16) for n in range(44)]))

# ------------------------------------------------------------ sounds
# each step: byte (vol<<4 | audc), byte audf ; step lasts 2 frames; $00 ends
def snd(steps):
    out = []
    for c, f, v in steps:
        out += [(v << 4) | c, f]
    return out + [0]
SOUNDS = {
  'Shot':    snd([(8, 4, 12), (8, 6, 10), (8, 8, 8), (8, 10, 6), (8, 12, 4), (8, 14, 2)]),
  'Bounce':  snd([(12, 6, 10), (12, 4, 8), (12, 6, 4)]),
  'Boom':    snd([(8, 28, 15)] * 3 + [(8, 30, 14)] * 3 + [(8, 31, 12)] * 4 + [(8, 31, 10)] * 4 +
                 [(8, 31, 8)] * 4 + [(8, 31, 6)] * 4 + [(8, 31, 4)] * 4 + [(8, 31, 2)] * 4),
  'Pickup':  snd([(4, 20, 10), (4, 15, 10), (4, 12, 10), (4, 9, 10), (4, 7, 8), (4, 7, 4)]),
  'Shield':  snd([(12, 3, 12), (8, 4, 10), (12, 5, 8), (8, 6, 6), (12, 8, 4)]),
  'Bump':    snd([(15, 28, 6), (15, 30, 3)]),
  'Fizzle':  snd([(8, 16, 5), (8, 20, 3)]),
  'Fanfare': snd([(4, 23, 10)] * 3 + [(4, 17, 10)] * 3 + [(4, 14, 10)] * 3 + [(4, 11, 10)] * 6 +
                 [(4, 14, 8)] * 2 + [(4, 11, 10)] * 8 + [(4, 11, 6)] * 3 + [(4, 11, 3)] * 3),
  'Start':   snd([(12, 19, 8)] * 3 + [(12, 15, 8)] * 3 + [(12, 12, 8)] * 3 + [(12, 9, 8)] * 5 + [(12, 9, 4)] * 2),
}
sdata = [0]          # offset 0 = silence
sidx = {}
for k, v in SOUNDS.items():
    sidx[k] = len(sdata); sdata += v
assert len(sdata) < 256
b1.append(byte_rows("SndData", sdata))
consts = ["SND_%s = %d" % (k.upper(), v) for k, v in sidx.items()]

# ------------------------------------------------------------ bank 1 data
# kernel row index: RowIdx[next] = arena row shown for pair next+1
b1.append(byte_rows("RowIdx", [row_of_pair(n + 1) for n in range(84)]))

# tank shapes from the original Combat, 8 headings, top row first
TANK = [
 [0x00,0xFC,0xFC,0x38,0x3F,0x38,0xFC,0xFC],
 [0x1C,0x78,0xFB,0x7C,0x1C,0x1F,0x3E,0x18],
 [0x19,0x3A,0x7C,0xFF,0xDF,0x0E,0x1C,0x18],
 [0x24,0x64,0x79,0xFF,0xFF,0x4E,0x0E,0x04],
 [0x08,0x08,0x6B,0x7F,0x7F,0x7F,0x63,0x63],
 [0x24,0x26,0x9E,0xFF,0xFF,0x72,0x70,0x20],
 [0x98,0x5C,0x3E,0xFF,0xFB,0x70,0x38,0x18],
 [0x38,0x1E,0xDF,0x3E,0x38,0xF8,0x7C,0x18],
]
def rev8(b): return int('{:08b}'.format(b)[::-1], 2)
shapes = []
for d in range(16):
    s = TANK[d] if d < 8 else [rev8(b) for b in TANK[d - 8][::-1]]
    shapes += s[::-1]           # kernel wants bottom row first
# biplane and jet shapes from the original Combat (8 headings, top row first)
PLANE = [
 [0x00,0x8E,0x84,0xFF,0xFF,0x04,0x0E,0x00],
 [0x00,0x0E,0x04,0x8F,0x7F,0x72,0x07,0x00],
 [0x10,0x36,0x2E,0x0C,0x1F,0xB2,0xE0,0x40],
 [0x24,0x2C,0x5D,0x1A,0x1A,0x30,0xF0,0x60],
 [0x18,0x5A,0x7E,0x5A,0x18,0x18,0x18,0x78],
 [0x34,0x36,0x5A,0x78,0x2C,0x0C,0x06,0x0C],
 [0x08,0x6C,0x70,0xB8,0xDC,0x4E,0x07,0x06],
 [0x38,0x10,0xF0,0x7C,0x4F,0xE3,0x02,0x00],
]
JET = [
 [0x60,0x70,0x78,0xFF,0x78,0x70,0x60,0x00],
 [0x00,0xC1,0xFE,0x7C,0x78,0x30,0x30,0x30],
 [0x00,0x03,0x06,0xFC,0xFC,0x3C,0x0C,0x0C],
 [0x02,0x04,0x0C,0x1C,0xFC,0xFC,0x1E,0x06],
 [0x10,0x10,0x10,0x38,0x7C,0xFE,0xFE,0x10],
 [0x40,0x20,0x30,0x38,0x3F,0x3F,0x78,0x60],
 [0x40,0x60,0x3F,0x1F,0x1E,0x1E,0x18,0x18],
 [0x00,0x83,0x7F,0x3E,0x1E,0x0C,0x0C,0x0C],
]
for src in (PLANE, JET):
    for d in range(16):
        sh = src[d] if d < 8 else [rev8(b) for b in src[d - 8][::-1]]
        shapes += sh[::-1]
shapes_inc = byte_rows("TankShapes", shapes) + "PlaneShapes = TankShapes + 128\nJetShapes = TankShapes + 256\n"

# flight velocities, signed 1/32 pixel units: biplane slow/normal/fast,
# jet slow/normal/fast, missile, machine-gun bullet
FSPEEDS = [0.35, 0.55, 0.80, 0.55, 0.90, 1.30, 1.90, 2.60]
fvx = []; fvy = []
for sp in FSPEEDS:
    for d in range(16):
        a = d * math.pi / 8
        fvx.append(int(round(math.cos(a) * sp * 32)) & 0xFF)
        fvy.append(int(round(math.sin(a) * sp * ASPECT * 32)) & 0xFF)
b2.append(byte_rows("FVelX", fvx)); b2.append(byte_rows("FVelY", fvy))

CLOUDS = [
  "....................",
  "....................",
  "....................",
  "....####............",
  "..########..........",
  "...######...........",
  "....................",
  "....................",
  "...............#####",
  ".............#######",
  "..............######",
  "...............#####",
  "....................",
  "....................",
  "....................",
  "...#####............",
  ".#########..........",
  "...######...........",
  "....................",
  "....................",
  "....................",
]
cg = grid(CLOUDS)
cl = [pfrow(cg[r][:20]) for r in range(ROWS)]
b2.append(byte_rows("CloudMap", [c[k] for k in range(3) for c in cl], 21))

NUMBERS = [0x0E,0x0A,0x0A,0x0A,0x0E, 0x22,0x22,0x22,0x22,0x22, 0xEE,0x22,0xEE,0x88,0xEE,
           0xEE,0x22,0x66,0x22,0xEE, 0xAA,0xAA,0xEE,0x22,0x22, 0xEE,0x88,0xEE,0x22,0xEE,
           0xEE,0x88,0xEE,0xAA,0xEE, 0xEE,0x22,0x22,0x22,0x22, 0xEE,0xAA,0xEE,0xAA,0xEE,
           0xEE,0xAA,0xEE,0x22,0xEE, 0,0,0,0,0]
b1.append(byte_rows("Digits", NUMBERS))
b1.append(byte_rows("Times5", [i * 5 for i in range(16)]))

# title logo: "COMBAT" (5x5 letters) and "DX" (letters doubled in width)
FONT = {
 'C': ["#####", "#....", "#....", "#....", "#####"],
 'O': ["#####", "#...#", "#...#", "#...#", "#####"],
 'M': ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
 'B': ["####.", "#...#", "####.", "#...#", "####."],
 'A': [".###.", "#...#", "#####", "#...#", "#...#"],
 'T': ["#####", "..#..", "..#..", "..#..", "..#.."],
 'D': ["####.", "#...#", "#...#", "#...#", "####."],
 'X': ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
}
def logo_rows(text, wide=1, gap=1):
    rows = []
    for r in range(5):
        line = ""
        for ch in text:
            line += "".join(c * wide for c in FONT[ch][r]) + "." * gap
        line = line[:-gap]
        pad = 40 - len(line)
        line = "." * (pad // 2) + line + "." * (pad - pad // 2)
        rows.append([c == '#' for c in line])
    return rows
title = logo_rows("COMBAT") + logo_rows("DX", wide=2, gap=2)
def pfbytes(bits):
    v0 = sum(1 << (4 + i) for i in range(4) if bits[i])
    v1 = sum(1 << (7 - i) for i in range(8) if bits[4 + i])
    v2 = sum(1 << i for i in range(8) if bits[12 + i])
    return v0, v1, v2
title.append([False] * 40)        # row 10: blank
cols = [[] for _ in range(6)]
for bits in title:
    a = pfbytes(bits[:20]); b = pfbytes(bits[20:])
    for k, v in enumerate(a + b):
        cols[k].append(v)
for k, nm in enumerate(["TPF0L", "TPF1L", "TPF2L", "TPF0R", "TPF1R", "TPF2R"]):
    b1.append(byte_rows(nm, cols[k]))

# per-line logo row index, indexed by the kernel's line counter (counts down)
lines = [r for r in range(5) for _ in range(6)] + [10] * 14 + [r for r in range(5, 10) for _ in range(8)]
LR = [0] + lines[::-1]
b1.append(byte_rows("TitleLR", LR))
b1.append(byte_rows("TitleCol", [0x1C, 0x2C, 0x3C, 0x4C, 0x5C, 0x0E, 0x0E, 0x0E, 0x0E, 0x0E, 0]))
consts.append("TITLE_LINES = %d" % len(lines))

# arena colours (background, walls) and names for docs
ACOL = [(0xD4, 0x2C), (0xC4, 0x3A), (0x14, 0x2C), (0xE2, 0x0C),
        (0x42, 0x3A), (0x02, 0x9A), (0xE4, 0x1A), (0x62, 0xDA)]
ACOL += [(0x84, 0x0E), (0x96, 0x00)]          # 8 cloudy sky, 9 open sky
b1.append(byte_rows("ArenaBK", [c[0] for c in ACOL]))
b1.append(byte_rows("ArenaPF", [c[1] for c in ACOL]))

with open("bank0_data.inc", "w") as f:
    f.write("; generated by gen.py\n" + "".join(b0))
with open("bank1_data.inc", "w") as f:
    f.write("; generated by gen.py\n" + "\n".join(consts) + "\n\n" + "".join(b1))
with open("bank2_data.inc", "w") as f:
    f.write("; generated by gen.py\n" + "".join(b2))
with open("bank1_shapes.inc", "w") as f:
    f.write("; generated by gen.py (must start on a page boundary)\n" + shapes_inc)
with open("config.inc", "w") as f:
    f.write("; generated by gen.py\nNUM_ARENAS = %d\nSTART_X = %d\nSTART_Y = %d\n" % (NA, START_X, START_Y))
print("wrote bank0_data.inc, bank1_data.inc, config.inc")
