"""Worst/average cycle cost per routine under random play."""
import sys, random
sys.path.insert(0, 'tools')
from harness import Game
ROUT0 = ['PlayLogic', 'TankControl', 'MoveTank', 'Missile', 'AI', 'LineOfSight', 'PowerUps', 'Launch', 'TestPt']
ROUT1 = ['Sound', 'SetupDisplay', 'Digits5', 'PosObj']
def prof(game, frames, seed):
    random.seed(seed)
    g = Game(render=False); g.frame(3); g.e.swchb |= 0xC0; g.set_game(game)
    e = g.e
    targets = {(g.s[n], 0): n for n in ROUT0}
    targets.update({(g.s[n], 1): n for n in ROUT1})
    stats = {n: [0, 0, 0] for n in ROUT0 + ROUT1}   # max, total, count
    stack = []
    j = 0
    for f in range(frames):
        if f % 8 == 0: j = random.randrange(256)
        g.joy(0, up=j & 1, down=(j & 6) == 6, left=j & 8, right=(j & 48) == 48, fire=j & 64)
        g.joy(1, up=j & 2, left=j & 16, right=j & 128, fire=j & 4)
        fr = e.frames
        while e.frames == fr:
            op = e.read(e.pc) if False else None
            pc = e.pc; sp = e.sp
            e.step()
            key = (e.pc, e.cart.bank)
            if key in targets and e.sp == ((sp - 2) & 0xFF):
                stack.append((targets[key], e.cycles, e.sp))
            while stack and e.sp > stack[-1][2]:
                n, c0, _ = stack.pop()
                d = e.cycles - c0
                st = stats[n]; st[0] = max(st[0], d); st[1] += d; st[2] += 1
        if g.r('state') == 3: g.reset()
    return stats
for game in (int(a) for a in sys.argv[1:]):
    st = prof(game, 900, 3)
    print("game", game)
    for n, (mx, tot, cnt) in st.items():
        if cnt: print("  %-12s max %5d  avg %6.0f  calls/frame %.1f" % (n, mx, tot / cnt, cnt / 900))
