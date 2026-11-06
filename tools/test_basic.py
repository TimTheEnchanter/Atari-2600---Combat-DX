"""Basic gameplay checks in a 2-player game (game 13: 2P, straight, classic)."""
import sys
sys.path.insert(0, 'tools')
from harness import Game
g = Game()
g.frame(5)
g.set_game(13)
assert g.r('state') == 2 and g.r('players') == 1, "not in 2P play"
x0 = g.r('txh'); 
# drive P0 right for 120 frames
g.joy(0, up=True); g.frame(120); g.joy(0)
print("P0 moved x %d -> %d (expect ~ +48)" % (x0, g.r('txh')))
# turn left 4 steps -> facing up, drive into top wall
g.joy(0, left=True); g.frame(4*8); g.joy(0)
print("dir", g.r('tdir'))
g.joy(0, up=True); g.frame(250); g.joy(0)
print("after driving up: y", g.r('tyh'), "(top wall: tank top pair must stay below 81)")
g.shot('shots/t_wall.png')
# reverse
y1 = g.r('tyh'); g.joy(0, down=True); g.frame(60); g.joy(0)
print("reverse: y %d -> %d" % (y1, g.r('tyh')))
# reset and fire at P1 from close range
g.reset(); g.frame(2)
g.joy(0, up=True); g.frame(200); g.joy(0)
print("P0 x", g.r('txh'), "P1 x", g.r('txh',1), "y", g.r('tyh'), g.r('tyh',1))
g.joy(0, fire=True); g.frame(2); g.joy(0)
hit = None
for i in range(120):
    g.frame()
    if g.r('stirT') and hit is None: hit = i; g.shot('shots/t_hit.png')
print("hit after", hit, "frames; score", hex(g.r('score')), hex(g.r('score',1)), "lines", set(g.lines))
