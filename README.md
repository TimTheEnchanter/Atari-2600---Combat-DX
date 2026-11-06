# Combat DX

An upgraded Combat for the Atari 2600, rebuilt from the Combat disassembly.
It keeps Combat's tanks, biplanes, jets, digits and feel, and adds a
computer opponent, reverse gear, true ricochets, power-ups, eight tank
arenas, machine guns, formations and a title screen.

`combatdx.bin` is a 16K **F6SC** cartridge (F6 bank switching, four 4K
banks, plus 128 bytes of Superchip RAM). Stella usually detects it; if not,
set the cartridge type to **F6SC** in the game properties.

## Playing

* **Joystick (tanks):** left/right rotates, up drives forward, **down
  reverses**, the button fires.
* **Joystick (planes):** left/right turns. Planes always fly: up = fast,
  centre = normal, down = slow. The button fires.
* **Reset:** start the selected game.
* **Select:** step through games 1–44 (the number shows top left).
* **Difficulty switches:**
  * Left A: shorter missile range for the left player.
  * Right, one-player games: **A = hard CPU** (turns faster, fires sooner,
    backs away from close shots), **B = easy CPU**.
  * Right, two-player games: A = shorter missile range for the right player.
* **Colour / B&W:** B&W shows the tanks in grey.

First to **10** points wins. The winner's score flashes and a fanfare plays;
press Reset to play again. A hit tank spins and is knocked along the
missile's path. The arena changes every 3 points, and both tanks go back to
their start positions. A hit plane spins and drops; planes keep flying where
they are.

### Tank games (1–24)

Games 1–12 are one player against the CPU (the CPU drives the right tank).
Games 13–24 are the same twelve games for two players.

| 1P | 2P | Missiles | Arenas | Power-ups |
|---|---|---|---|---|
| 1 | 13 | Straight | Classic (1–3) | No |
| 2 | 14 | Straight | New (4–8) | Yes |
| 3 | 15 | Straight | All 8 | Yes |
| 4 | 16 | Straight | All 8, **invisible tanks** | Yes |
| 5–8 | 17–20 | **Guided** (steer with your tank) | as above | as above |
| 9–12 | 21–24 | **Ricochet** (3 bounces) | as above | as above |

Invisible tanks show up while their missile is in flight, when they bump a
wall, and while spinning after a hit.

Ricochet shots reflect properly off whichever wall face they hit (the
original guessed and retried). After a bounce, **your own shot can hit
you**, and the point goes to your opponent.

### Plane games (25–44)

Games 25–34 are one player against the CPU (the CPU flies the right side).
Games 35–44 are the same ten games for two players.

| 1P | 2P | Aircraft | Missiles | Sky | Formation |
|---|---|---|---|---|---|
| 25 | 35 | Biplane | Straight | Clouds | 1 v 1 |
| 26 | 36 | Biplane | Guided | Open | 1 v 1 |
| 27 | 37 | Biplane | **Machine gun** | Clouds | 1 v 1 |
| 28 | 38 | Biplane | Straight | Open | 2 v 2 |
| 29 | 39 | Biplane | Straight | Clouds | 1 v 3 |
| 30 | 40 | Jet | Straight | Clouds | 1 v 1 |
| 31 | 41 | Jet | Guided | Open | 1 v 1 |
| 32 | 42 | Jet | Machine gun | Clouds | 1 v 1 |
| 33 | 43 | Jet | Guided | Clouds | 2 v 2 |
| 34 | 44 | Jet | Straight | Open | **Bomber** v 3 |

* The screen wraps in both directions.
* Planes, missiles and bullets fly behind clouds and stay hidden there,
  but they can still hit and be hit.
* Biplanes are slower and turn tighter; jets are faster and turn wider.
* Machine guns fire short-range, fast bullets; hold the button for a stream.
* In formations every plane is a target, and missiles are copied along with
  the planes, so a squadron fires a volley. Hitting any plane in a
  formation scores. The bomber is four times as wide.
* `shots/planes.png` shows six of the plane games.

### Power-ups (tank games)

A blinking box appears every few seconds in power-up games. Drive over it
for a random effect lasting about 10 seconds:

| Effect | What it does | How the tank looks |
|---|---|---|
| Speed | Faster driving | Flickers bright |
| Shield | Absorbs the next hit | Brighter |
| Bounce | Your shots ricochet | Flashes yellow |
| Cloak | You are invisible until you fire or bump a wall | Gone |

### Arenas

1 Open Field, 2 Easy Maze, 3 Complex Maze (Combat-style), 4 Pillars,
5 Fortress, 6 Crossfire, 7 Bunkers, 8 Labyrinth. Each has its own colours.
`shots/arenas.png` shows all eight.

## How it works

* **Banks** (hotspots `$1FF6`–`$1FF9` select banks 0–3; every bank's
  reset stub switches to bank 0):
  * Bank 0: tank logic (input, movement, missiles, CPU player) and the
    game select.
  * Bank 1: display (title and arena kernels, object positioning, score
    digits, sound, colour setup) and the power-ups.
  * Bank 2: flight logic for the plane games and their tables.
  * Bank 3: empty, for new features.
  * Trampolines: bank 0 calls the kernel at `$FFE0` and the flight logic at
    `$FFD0`; bank 1 calls the plane overscan work in bank 2 at `$FFC0`.
* **Planes:** the same arena kernel draws the sky. The playfield comes
  from a cloud map (or nothing) in Superchip RAM, with playfield priority
  set so clouds cover planes. Formations are NUSIZ copies (two close,
  three close, quad-width bomber), and hit tests check every missile copy
  against every target copy. Flight velocities are stored as signed bytes
  (1/32 pixel) and widened to 8.8 when used. The CPU pilot finds the
  bearing across the wrapping screen, flies fast until close, and when it is
  lined up on an axis but off the line, angles one step toward the line
  before firing.
* **Arena kernel:** 84 line pairs. Line A writes both tank sprites, then
  the ball and missile enables with Combat's stack trick (`PHP` into
  ENABL/ENAM1/ENAM0). Line B writes the playfield from Superchip RAM.
  Every write lands inside its timing window.
* **Arenas:** 40×21 cells (4 pixels × 4 line pairs), mirrored left to
  right. Each is stored once, as 63 bytes of PF0/PF1/PF2 by row. The same
  bytes serve wall collision and, copied into Superchip RAM when the arena
  changes, the display.
* **Movement:** 16 headings, 8.8 fixed-point positions, axis-separated
  moves so tanks slide along walls. Only the leading edge of the tank box
  is tested, with one column lookup per edge.
* **CPU player:** bearing from an octant/ratio test, a line-of-sight
  sweep (15 samples, one per frame), wall avoidance that turns toward the
  open side and backs out of dead ends, and a "line up" move: if it holds a
  clear shot for 1.5 s without scoring, it drives to match the player's
  row or column (alternating) and shoots straight.
* **Frame budget:** the logic is split between vertical blank (tank
  control) and overscan (missiles, CPU, display setup, sound, power-ups).
  Score digits are rebuilt only when they change.
* **Superchip RAM:** score graphics, the line-of-sight sweep, CPU
  counters, a plane-reset flag and the current arena or sky playfield
  (95 of 128 bytes).

## Testing

* The 16K build boots correctly whichever bank the cartridge powers up in.
* Every frame is exactly **262 lines** on the title, select and play
  screens. 1,500-frame random-input runs (two seeds each) over tank games
  1, 6, 11, 14 and 24 and plane games 25, 27, 29, 31, 33, 34, 38 and 44:
  worst case 324 spare cycles in vertical blank and 134 in overscan.
* `tools/test_basic.py`: driving, wall blocking, reverse, a hit and the score.
* `tools/test_planes.py`: speed control, wrapping, a hit on the second
  plane of a 2 v 2 formation, a hit by a second missile copy, a clear miss,
  the bomber's width, and the hard CPU pilot against a passive player in
  all ten one-player plane games (it reaches 10 in each within 30 s).
* `tools/test_features.py`: game select, ricochet reflection, guided
  steering, power-up spawn and pickup, all four effects, shield absorbing
  a hit, invisible tanks, and victory with the fanfare.
* `tools/test_ai.py`: the hard CPU against a stationary player and against
  a scripted moving player, 20 s per arena. It scores against the
  stationary player in all 8 arenas (2–7 hits) and against the moving one
  in 7 of 8; in Bunkers the scripted player won 1–0.
* The emulator was checked first on the original Combat: it assembles,
  plays, and scores hits through the collision registers.
* **The 8K build (tank games 1–24) was confirmed running well in Stella**
  (2026-11-06). The 16K build and the plane games haven't been tried in
  Stella yet. Nothing has been tried on real hardware.

## Building

```
python3 gen.py                      # arenas, tables, sprites, sounds
python3 tools/asm6502.py combatdx.asm combatdx.bin -s combatdx.sym
```

`gen.py` checks every arena: both start positions clear, the tanks able to
reach each other, and power-up spots reachable. `tools/asm6502.py` is a
small DASM-syntax assembler; the source should also build with DASM
(`dasm combatdx.asm -f3 -ocombatdx.bin`). `tools/emu2600.py` is the test
emulator.

## Space and ideas

* Free: 16 bytes in bank 0, 1.5K in bank 1, 2.2K in bank 2, 3.8K in
  bank 3, 33 bytes of Superchip RAM and 14 bytes of stack headroom in zero
  page.
* Bank 0 is still full. New tank-side logic should go in bank 3; moving the
  tank CPU player there (with copies of the wall-test tables) would free
  about 1K in bank 0.
* Ideas: CPU difficulty that adapts to the score, mines, a round timer
  mode, more arenas (63 bytes each), power-ups for plane games.
