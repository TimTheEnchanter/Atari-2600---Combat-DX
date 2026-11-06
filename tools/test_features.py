"""Feature checks: ricochet, guided missiles, power-ups, invisibility,
victory, game select."""
import sys
sys.path.insert(0, 'tools')
from harness import Game

def new(game, render=False):
    g = Game(render=render); g.frame(3); g.set_game(game); return g

# --- game select cycles 1..24 and back
g = Game(render=False); g.frame(3)
seen = []
for i in range(26):
    g.select(); seen.append(g.r('gameNum') + 1)
print("select sequence:", seen[:3], "...", seen[-3:], "BCD shown", hex(g.r('dispL')))

# --- ricochet (game 21: 2P, ricochet, classic): fire up into the top wall
g = new(21)
g.joy(0, left=True); g.frame(4 * 8 - 3); g.joy(0)       # face up (dir 4) -> turn to dir 3 (steep right-up)
g.joy(0, right=True); g.frame(2); g.joy(0)
d = g.r('tdir'); g.joy(0, fire=True); g.frame(2); g.joy(0)
b0 = g.r('mbnc'); vy0 = g.r('mvyh')
for i in range(80):
    g.frame()
    if g.r('mbnc') != b0: break
print("ricochet: dir %d, bounces left %d -> %d after %d frames, vy sign %s -> %s" %
      (d, b0, g.r('mbnc'), i, 'up' if vy0 < 128 else 'down', 'up' if g.r('mvyh') < 128 else 'down'))

# --- guided (game 17: 2P guided classic): missile turns with the tank
g = new(17)
g.joy(0, fire=True); g.frame(2); g.joy(0)
vy_before = g.r('mvyh'), g.r('mvyl')
g.joy(0, left=True); g.frame(18); g.joy(0)
print("guided: tank dir %d, missile vy %s -> %s (should point upward now)" %
      (g.r('tdir'), vy_before, (g.r('mvyh'), g.r('mvyl'))))

# --- power-ups (game 14: 2P straight, new arenas + power-ups)
g = new(14, render=True)
spawned = None
for f in range(800):
    g.frame()
    if g.r('boxY'): spawned = f; break
bx, by = g.r('boxX'), g.r('boxY')
print("power-up box spawned at frame", spawned, "pos", (bx, by))
g.frame(8); g.shot('shots/f_powerup_box.png')
# teleport P0 onto the box
g.w('txh', bx - 2); g.w('tyh', by - 2); g.frame(3)
print("picked up:", g.r('boxY') == 0, "P0 power-up type", g.r('pu'), "timer", g.r('put'))
for t in (1, 2, 3, 4):
    g.w('pu', t); g.w('put', 100); g.frame(2)
    print("  type %d -> P0 colour %02X (normal %02X)" % (t, g.r('col0'), 0x36))
g.w('pu', 2); g.w('put', 100)
# shield: hit P0 with P1's missile
g.w('txh', 60); g.w('tyh', 40); g.w('txh', 100, 1); g.w('tyh', 40, 1); g.w('tdir', 8, 1)
g.joy(1, fire=True); g.frame(2); g.joy(1)
for i in range(60):
    g.frame()
    if g.r('pu') == 0: break
print("shield absorbed hit:", g.r('pu') == 0 and g.r('score', 1) == 0, "stir", g.r('stirT'))

# --- invisible (game 16: 2P straight invisible)
g = new(16, render=True); g.frame(5)
print("invisible: P0 colour %02X, background %02X" % (g.r('col0'), g.r('bkCol')))
g.joy(0, fire=True); g.frame(3); g.joy(0)
print("  while firing: P0 colour %02X" % g.r('col0'))

# --- victory: give P0 9 points and score one more
g = new(13, render=True)
g.w('score', 0x09)
g.joy(0, up=True); g.frame(200); g.joy(0)
g.joy(0, fire=True); g.frame(2); g.joy(0)
for i in range(200):
    g.frame()
    if g.r('state') == 3: break
print("victory: state %d, winner %d, score %X-%X, fanfare playing %s" %
      (g.r('state'), g.r('winner'), g.r('score'), g.r('score', 1), g.r('snd') != 0))
g.frame(30); g.shot('shots/f_victory.png')
print("frame lines seen:", set(g.lines[5:]))
