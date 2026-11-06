"""Plane game checks: decode, wrap, speed, formation hits, CPU pilot."""
import sys
sys.path.insert(0, 'tools')
from harness import Game

def start(game, render=False):
    g = Game(render=render); g.frame(3)
    g.set_game(game); g.frame(3)
    return g

# speed control (game 35: 2P biplanes)
g = start(35)
for label, kw in (("slow", dict(down=True)), ("normal", {}), ("fast", dict(up=True))):
    g.w('txh', 20); g.w('tdir', 0); g.joy(0, **kw); g.frame(60)
    print("biplane %-6s: %d px in 60 frames" % (label, g.r('txh') - 20))
g.joy(0)

# wrap
g.w('txh', 155); g.w('tdir', 0); g.frame(20)
print("wrap right edge: x 155 ->", g.r('txh'))
g.w('tyh', 82); g.w('tdir', 4); g.frame(20)
print("wrap top: y 82 ->", g.r('tyh'))

# formation hit on a non-lead copy (game 38: 2P biplanes 2 v 2)
g = start(38)
g.w('txh', 100, 1); g.w('tyh', 40, 1); g.w('tdir', 8, 1)
g.w('txh', 10); g.w('tyh', 70)
# P0 missile placed so only its leader copy overlaps P1's *second* plane (x 116..123)
g.w('mlife', 30); g.w('mxh', 118); g.w('myh', 43)
for k in ('mvxl', 'mvxh', 'mvyl', 'mvyh'): g.w(k, 0)
g.frame(2)
print("2v2: hit on second plane ->", g.r('stirT') > 0, "score", g.r('score'))
g.frame(80)
# P0's second missile copy (+16) hitting P1's leader
g.w('txh', 100, 1); g.w('tyh', 40, 1)
g.w('mlife', 30); g.w('mxh', 86); g.w('myh', 43); g.frame(2)
print("2v2: hit by second missile copy ->", g.r('stirT') > 0, "score", g.r('score'))
g.frame(80)
g.w('mlife', 30); g.w('mxh', 60); g.w('myh', 43); g.frame(2)
print("2v2: clear miss ->", g.r('stirT') == 0)

# bomber is 32 pixels wide (game 44: P0 bomber)
g = start(44)
g.w('txh', 40); g.w('tyh', 40); g.w('txh', 120, 1); g.w('tyh', 10, 1)
g.w('mlife', 30, 1); g.w('mxh', 66, 1); g.w('myh', 43, 1)
for k in ('mvxl', 'mvxh', 'mvyl', 'mvyh'): g.w(k, 0, 1)
g.frame(2)
print("bomber hit 26 px from its nose ->", g.r('stirT') > 0)

# CPU pilot against a passive player, per plane game type
for game in (25, 26, 27, 28, 29, 30, 31, 32, 33, 34):
    g = start(game); g.e.swchb |= 0x80
    hits = []
    for f in range(1800):
        g.frame()
        if g.r('stirT') == 70: hits.append(f)
        if g.r('state') == 3: break
    print("game %d CPU vs passive (30 s): CPU score %X, first hits at %s, lines %s" %
          (game, g.r('score', 1), hits[:4], set(g.lines[5:])))
