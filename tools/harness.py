"""Test helpers for Combat DX: load ROM + symbols, drive inputs, read RAM."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from emu2600 import Emu, save_png

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def load_syms(path):
    syms = {}
    for ln in open(path):
        parts = ln.split()
        if len(parts) == 2 and parts[1].startswith('$'):
            syms[parts[0]] = int(parts[1][1:], 16)
    return syms

class Game:
    def __init__(self, rom=None, sym=None, render=True):
        rom = rom or os.path.join(ROOT, 'combatdx.bin')
        sym = sym or os.path.join(ROOT, 'combatdx.sym')
        self.e = Emu(open(rom, 'rb').read(), render=render)
        self.s = load_syms(sym)
        self.lines = []

    def r(self, name, i=0):
        return self.e.ram[(self.s[name] + i) & 0x7F]

    def w(self, name, v, i=0):
        self.e.ram[(self.s[name] + i) & 0x7F] = v & 0xFF

    def frame(self, n=1):
        for _ in range(n):
            self.lines.append(self.e.run_frame())
        return self.lines[-1]

    def press(self, bit, frames=3):
        self.e.swchb &= ~bit
        self.frame(frames)
        self.e.swchb |= bit
        self.frame(2)

    def reset(self): self.press(1)
    def select(self): self.press(2)

    def joy(self, p, up=False, down=False, left=False, right=False, fire=False):
        bits = (1 if up else 0) | (2 if down else 0) | (4 if left else 0) | (8 if right else 0)
        if p == 0:
            self.e.swcha = (self.e.swcha & 0x0F) | ((~bits & 15) << 4)
            self.e.inpt[4] = 0x00 if fire else 0x80
        else:
            self.e.swcha = (self.e.swcha & 0xF0) | (~bits & 15)
            self.e.inpt[5] = 0x00 if fire else 0x80

    def set_game(self, n):
        """select game number n (1..24) and start it"""
        self.select()
        while self.r('gameNum') != n - 1:
            self.select()
        self.reset()

    def shot(self, path):
        save_png(self.e.frame, path, lines=self.e.frame_lines)
