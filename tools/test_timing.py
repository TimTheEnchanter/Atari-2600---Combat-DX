"""Random-input stress test: every frame must be 262 lines; report the
minimum timer slack when the kernel starts waiting (vblank) and when the
overscan wait loop starts."""
import sys, random
sys.path.insert(0, 'tools')
from harness import Game

VB = 44 * 64
OS = 35 * 64

def stress(game, frames, seed, hard=True):
    random.seed(seed)
    g = Game(render=False)
    g.frame(3)
    if hard: g.e.swchb |= 0xC0
    g.set_game(game)
    e = g.e
    k_wait = g.s['ArenaKernel']        # first instruction is the INTIM wait
    os_wait = g.s['MainLoop.os'] if 'MainLoop.os' in g.s else None
    vmin = 999; omin = 999
    j = 0
    for f in range(frames):
        if f % 8 == 0:
            j = random.randrange(256)
        g.joy(0, up=j & 1, down=(j & 6) == 6, left=j & 8, right=(j & 48) == 48, fire=j & 64)
        if g.r('players'):
            g.joy(1, up=j & 2, left=j & 16, right=j & 128, fire=j & 4)
        fr = e.frames
        seen_k = False; seen_o = False
        while e.frames == fr:
            pc = e.pc
            if pc == k_wait and e.cart.bank == 1 and not seen_k:
                vmin = min(vmin, VB - (e.cycles - e.tim_start)); seen_k = True
            if pc == os_wait and e.cart.bank == 0 and not seen_o:
                omin = min(omin, OS - (e.cycles - e.tim_start)); seen_o = True
            e.step()
        g.lines.append(e.last_frame_lines)
        if g.r('state') == 3:
            g.reset()
    bad = [n for n in g.lines[8:] if n != 262]
    return vmin, omin, len(bad), g.r('score'), g.r('score', 1)

if __name__ == '__main__':
    for game in (int(a) for a in sys.argv[1:]):
        for seed in (1, 2):
            vmin, omin, bad, s0, s1 = stress(game, 1500, seed)
            print("game %2d seed %d: vblank spare %d cycles, overscan spare %d cycles, bad frames %d, score %X-%X"
                  % (game, seed, vmin, omin, bad, s0, s1))
