"""CPU opponent vs a passive player and vs a scripted player, per arena."""
import sys
sys.path.insert(0, 'tools')
from harness import Game

def setarena(g, a):
    rom = g.e.cart.data
    g.w('arena', a)
    lo = rom[g.s['MazePtrLo'] - 0xF000 + a]; hi = rom[g.s['MazePtrHi'] - 0xF000 + a]
    g.w('mazePtr', lo); g.w('mazePtr', hi, 1)
    base = (hi << 8 | lo) - 0xF000
    g.e.cart.scram[g.s['SC_PF0']:g.s['SC_PF0'] + 63] = rom[base:base + 63]

def run(game, arena, hard, frames, bot=False):
    g = Game(render=False)
    g.frame(3)
    if hard: g.e.swchb |= 0x80
    else: g.e.swchb &= ~0x80
    g.set_game(game)
    setarena(g, arena)
    hits = []
    last = 0
    for f in range(frames):
        if bot:
            # scripted player: drive in a loop, fire every half second
            ph = (f // 60) % 4
            g.joy(0, up=ph != 3, left=ph == 1 and f % 60 < 16, fire=(f % 30 == 0))
        g.frame()
        sc = g.r('score', 1)
        if sc != last: hits.append(f); last = sc
        if g.r('arenaPts') == 0 and g.r('arena') != arena and not bot:
            setarena(g, arena)  # keep testing the same arena
        if g.r('state') == 3: break
    return hits, g.r('score'), g.r('score', 1), set(g.lines[5:])

if __name__ == '__main__':
    mode = sys.argv[1] if len(sys.argv) > 1 else 'passive'
    for arena in range(8):
        hits, s0, s1, lines = run(1, arena, mode != 'easy', 1200, bot=(mode == 'bot'))
        print("arena %d %s: CPU hits at frames %s, score %X-%X, frame lines %s" % (arena, mode, hits, s0, s1, lines))
