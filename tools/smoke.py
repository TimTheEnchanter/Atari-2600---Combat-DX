import sys
sys.path.insert(0,'tools')
from harness import Game
g=Game()
g.frame(30)
print("title lines", g.lines[-5:]); g.shot('shots/title.png')
g.select(); g.frame(10)
print("select lines", g.lines[-3:], "state", g.r('state'), "game", g.r('gameNum')); g.shot('shots/select.png')
g.reset(); g.frame(30)
print("play lines", g.lines[-3:], "state", g.r('state')); g.shot('shots/play.png')
