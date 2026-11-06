; ====================================================================
; COMBAT DX - an upgraded Combat for the Atari 2600
; 16K F6 cartridge with Superchip RAM (F6SC)
;
; Bank 0: tank logic (input, movement, missiles, CPU player), game select
; Bank 1: display (title and arena kernels, positioning, score digits,
;         sound, colours), power-ups, playfield and sprite data
; Bank 2: flight logic for the plane games
; Bank 3: free
;
; Build:  python3 gen.py && python3 tools/asm6502.py combatdx.asm combatdx.bin
; ====================================================================

        processor 6502
        include vcs.h
        include config.inc

; -------------------------------------------------------------- constants
VBL_TIME    = 44        ; TIM64T value for vertical blank
OS_TIME     = 35        ; TIM64T value for overscan
TURN_DELAY  = 7         ; frames between 22.5 degree turns
TURN_SLOW   = 11        ; easy CPU turning
MIS_LIFE    = 88        ; missile lifetime in frames
MIS_SHORT   = 52        ; with difficulty switch A
STIR_TIME   = 72        ; frames a hit tank spins
WIN_SCORE   = $10       ; BCD points to win
PU_SPEED    = 1
PU_SHIELD   = 2
PU_BOUNCE   = 3
PU_CLOAK    = 4
COL_P0      = $38
COL_P1      = $88

ST_TITLE    = 0
ST_SELECT   = 1
ST_PLAY     = 2
ST_OVER     = 3

; Superchip RAM (128 bytes): write at $F000, read at $F080
SCW         = $F000
SCR         = $F080
SC_SCORE    = 0         ; 10 bytes of score graphics
SC_LAST     = 10        ; 2 bytes: values the graphics were built from
SC_LOS      = 12        ; 8 bytes: line-of-sight sample position and step
SC_LOSK     = 20        ; samples taken in the current sweep
SC_HOLD     = 21        ; frames the CPU has held position
SC_ALT      = 22        ; line-up axis toggle
SC_FLR      = 23        ; plane round reset pending
SC_PF0      = 32        ; 63 bytes: current arena, PF0/PF1/PF2 by row
SC_PF1      = 53
SC_PF2      = 74

; -------------------------------------------------------------- zero page
        seg.u vars
        org $80
frame       ds 1
rand        ds 1
state       ds 1
gameNum     ds 1
gameBCD     ds 1
players     ds 1        ; 0 = one player vs CPU, 1 = two players
weapon      ds 1        ; 0 straight, 1 guided, 2 ricochet
amode       ds 1        ; 0 classic, 1 new arenas, 2 all arenas, 3 invisible
arena       ds 1
arenaPts    ds 1
score       ds 2
swPrev      ds 1
stirT       ds 1
stirWho     ds 1
stirMis     ds 1
flash       ds 1
winner      ds 1
curT        ds 1
; per tank (index 0 = left player, 1 = right player / CPU)
txl         ds 2
txh         ds 2
tyl         ds 2
tyh         ds 2
tdir        ds 2
tturn       ds 2
mxl         ds 2
mxh         ds 2
myl         ds 2
myh         ds 2
mvxl        ds 2
mvxh        ds 2
mvyl        ds 2
mvyh        ds 2
mlife       ds 2
mbnc        ds 2        ; 0 = no ricochet, 4 = 3 bounces left (1..3 = has bounced)
pu          ds 2        ; active power-up
put         ds 2        ; power-up time left (x4 frames)
vis         ds 2        ; visible-while-invisible timer
joy         ds 2        ; bit0 up, 1 down, 2 left, 3 right, 7 fire
moved       ds 2        ; 0 blocked, $80 not driving, else moved
snd         ds 2        ; offset into SndData, 0 = none
sndT        ds 2
; power-up box
boxX        ds 1
boxY        ds 1        ; 0 = no box
boxT        ds 1
; CPU player
aiJoy       ds 1
aiMode      ds 1
aiT         ds 1
aiHead      ds 1
aiWant      ds 1
aiLOS       ds 1
aiStuck     ds 1
aiAlign     ds 1
aiAX        ds 1
aiAY        ds 1
aiRY        ds 1
aiSX        ds 1
aiSY        ds 1
; temporaries
tmp         ds 6
tmp2        = tmp+4
tvxl        ds 1
tvxh        ds 1
tvyl        ds 1
tvyh        ds 1
mazePtr     ds 2
; display
dispL       ds 1
dispR       ds 1
col0        ds 1
col1        ds 1
bkCol       ds 1
pfCol       ds 1
m0y         ds 1
m1y         ds 1
bly         ds 1
gfx0        ds 1
gfx1        ds 1
p0ptr       ds 2
p1ptr       ds 2
saveSP      ds 1
vehicle     ds 1        ; 0 tank, 1 biplane, 2 jet
form        ds 1        ; plane formation: 0 1v1, 1 2v2, 2 1v3, 3 bomber v 3
spd         ds 2        ; plane speed level 0..2
varsEnd     ds 0
            echo "zero page used up to", varsEnd

        seg code

; ====================================================================
; BANK 0 - game logic
; ====================================================================
        org $0000
        rorg $F000
        ds 256, $FF             ; Superchip RAM window
        org $0100
        rorg $F100

Start:
        sei
        cld
        ldx #0
        txa
.clr    sta 0,x
        inx
        bne .clr
        dex
        txs
        lda #$A7
        sta rand
        lda #ST_TITLE
        sta state
        jsr DecodeGame
        jsr TitleSetup

MainLoop:
        lda #2
        sta WSYNC
        sta VBLANK
        sta VSYNC
        sta WSYNC
        sta WSYNC
        sta WSYNC
        lda #0
        sta VSYNC
        lda #VBL_TIME
        sta TIM64T

        inc frame
        jsr Random
        jsr Switches
        lda state
        cmp #ST_PLAY
        bne .noplay
        lda vehicle
        beq .tankp
        jsr CallFlight
        jmp .noplay
.tankp  jsr PlayLogic
.noplay
        jsr CallKernel          ; draws the screen, returns in overscan

        lda state
        cmp #ST_PLAY
        bne .noai
        lda vehicle
        bne .noai
        lda stirT
        bne .nomis
        ldx #0
        jsr Missile
        ldx #1
        jsr Missile
.nomis  jsr AI
.noai
.os     lda INTIM
        bne .os
        jmp MainLoop

; -------------------------------------------------------------- random
Random:
        lda rand
        lsr
        bcc .r1
        eor #$B4
.r1     sta rand
        rts

; -------------------------------------------------------------- switches
Switches:
        lda SWCHB
        eor #$FF
        and #3                  ; bit0 reset, bit1 select (pressed = 1)
        tay
        eor swPrev
        sty swPrev
        sta tmp
        tya
        and tmp                 ; newly pressed
        lsr
        bcc .noReset
        jmp StartGame
.noReset
        lsr
        bcc .noSel
        lda state
        cmp #ST_SELECT
        bne .toSel
        inc gameNum
        lda gameNum
        cmp #44
        bcc .toSel
        lda #0
        sta gameNum
.toSel  jmp EnterSelect
.noSel
        lda state
        bne .sw9
        lda INPT4               ; fire on the title screen -> game select
        bpl EnterSelect
.sw9    rts

EnterSelect:
        lda #ST_SELECT
        sta state
        jsr DecodeGame
        jsr FirstArena
        jsr ResetRound
        lda #0
        sta snd
        sta snd+1
        rts

DecodeGame:
        ldx gameNum
        lda GameBCD,x
        sta gameBCD
        lda #0
        sta vehicle
        sta form
        lda gameNum
        cmp #24
        bcc .tank
        sbc #24                 ; plane games 25-44
        ldx #0
        cmp #10
        bcc .p1
        sbc #10
        inx
.p1     stx players
        tax
        lda PlaneGames,x        ; bits 0-1 weapon, 2 open sky, 3-4 formation, 5 jet
        tay
        and #3
        sta weapon
        tya
        lsr
        lsr
        tay
        and #1
        ora #8
        sta arena               ; 8 clouds, 9 open sky
        tya
        lsr
        tay
        and #3
        sta form
        tya
        lsr
        lsr
        and #1
        clc
        adc #1
        sta vehicle
        lda #0
        sta amode
        rts
.tank   ldx #0
        cmp #12
        bcc .d1
        sbc #12
        inx
.d1     stx players
        tay
        lsr
        lsr
        sta weapon
        tya
        and #3
        sta amode
        rts

TitleSetup:
        lda #44
        sta txh
        lda #108
        sta txh+1
        lda #0
        sta tdir
        sta mlife
        sta mlife+1
        sta boxY
        lda #8
        sta tdir+1
        lda #1
        sta tyh
        sta tyh+1
        rts

StartGame:
        jsr DecodeGame
        lda #0
        sta score
        sta score+1
        sta arenaPts
        sta stirT
        sta flash
        lda #ST_PLAY
        sta state
        jsr FirstArena
        jsr ResetRound
        ldx #0
        lda #SND_START
        jsr PlaySnd
        rts

FirstArena:
        lda vehicle
        bne .fa9
        ldx amode
        lda ArenaFirst,x
        sta arena
.fa9    rts

ResetRound:
        lda #0
        sta aiJoy
        sta boxY
        lda vehicle
        beq .tankr
        lda #1                  ; planes: bank 1 resets the sky in overscan
        sta SCW+SC_FLR
        rts
.tankr  ldx arena
        lda MazePtrLo,x
        sta mazePtr
        lda MazePtrHi,x
        sta mazePtr+1
        ldy #62
.cp     lda (mazePtr),y         ; arena playfield into Superchip RAM
        sta SCW+SC_PF0,y
        dey
        bpl .cp
        lda #START_X
        sta txh
        lda #152-START_X
        sta txh+1
        lda #START_Y
        sta tyh
        sta tyh+1
        lda #0
        ldx #1
.rr     sta txl,x
        sta tyl,x
        sta mlife,x
        sta pu,x
        sta vis,x
        sta tturn,x
        sta joy,x
        dex
        bpl .rr
        sta tdir
        sta boxY
        sta aiMode
        sta aiJoy
        sta aiStuck
        lda #8
        sta tdir+1
        lda #90
        sta boxT
        rts

; -------------------------------------------------------------- play logic
PlayLogic:
        lda stirT
        beq .pl1
        jmp Stir
.pl1
        lda SWCHA
        eor #$FF
        lsr
        lsr
        lsr
        lsr
        sta joy
        lda INPT4
        eor #$80
        and #$80
        ora joy
        sta joy
        lda players
        bne .human2
        lda aiJoy
        jmp .set2
.human2 lda SWCHA
        eor #$FF
        and #$0F
        sta joy+1
        lda INPT5
        eor #$80
        and #$80
        ora joy+1
.set2   sta joy+1

        ldx #0
        jsr TankControl
        ldx #1
        jmp TankControl

; X = tank
TankControl:
        stx curT
        lda joy,x
        and #$0C
        bne .turning
        sta tturn,x
        beq .move
.turning
        lda tturn,x
        beq .doTurn
        dec tturn,x
        jmp .move
.doTurn
        ldy #TURN_DELAY
        cpx #1
        bne .td
        lda players
        bne .td
        bit SWCHB               ; right difficulty B = easy CPU
        bmi .td
        ldy #TURN_SLOW
.td     sty tturn,x
        lda joy,x
        and #$04
        beq .right
        inc tdir,x
        jmp .wrap
.right  dec tdir,x
.wrap   lda tdir,x
        and #15
        sta tdir,x
.move
        lda joy,x
        lsr
        bcc .notFwd
        ldy #0
        lda pu,x
        cmp #PU_SPEED
        bne .go
        ldy #16
        bne .go
.notFwd lsr
        bcc .noMove
        ldy #32
.go     tya
        clc
        adc tdir,x
        tay
        lda VelXL,y
        sta tvxl
        lda VelXH,y
        sta tvxh
        lda VelYL,y
        sta tvyl
        lda VelYH,y
        sta tvyh
        jsr MoveTank
        ldx curT
        lda moved,x
        bne .fire
        lda #24                 ; bumping a wall shows an invisible tank
        sta vis,x
        bne .fire
.noMove lda #$80
        sta moved,x
.fire   lda joy,x
        bpl .tc9
        lda mlife,x
        bne .tc9
        jsr Launch
.tc9    rts

; Move tank curT by (tvx, tvy) with wall and tank collision, sliding.
MoveTank:
        ldx curT
        lda #0
        sta moved,x
        ; ---- X axis
        lda tvxl
        ora tvxh
        beq .xblk
        clc
        lda txl,x
        adc tvxl
        sta tmp
        lda txh,x
        adc tvxh
        sta tmp+1
        cmp txh,x
        beq .xok
        ldy #6
        bit tvxh
        bpl .xr
        ldy #1
.xr     tya
        clc
        adc tmp+1
        sta tmp2
        lda tyh,x
        jsr EdgeV
        bne .xblk
        ldx curT
        txa
        eor #1
        tay
        lda tmp+1
        sec
        sbc txh,y
        clc
        adc #6
        cmp #13
        bcs .xok
        lda tyh,x
        sec
        sbc tyh,y
        clc
        adc #6
        cmp #13
        bcc .xblk
.xok    ldx curT
        lda tmp
        sta txl,x
        lda tmp+1
        sta txh,x
        lda #1
        sta moved,x
.xblk
        ; ---- Y axis
        ldx curT
        lda tvyl
        ora tvyh
        beq .yblk
        clc
        lda tyl,x
        adc tvyl
        sta tmp
        lda tyh,x
        adc tvyh
        sta tmp+1
        cmp tyh,x
        beq .yok
        ldy #6
        bit tvyh
        bpl .yu
        ldy #1
.yu     tya
        clc
        adc tmp+1
        pha
        lda txh,x
        sta tmp2
        pla
        jsr EdgeH
        bne .yblk
        ldx curT
        txa
        eor #1
        tay
        lda tmp+1
        sec
        sbc tyh,y
        clc
        adc #6
        cmp #13
        bcs .yok
        lda txh,x
        sec
        sbc txh,y
        clc
        adc #6
        cmp #13
        bcc .yblk
.yok    ldx curT
        lda tmp
        sta tyl,x
        lda tmp+1
        sta tyh,x
        lda moved,x
        ora #2
        sta moved,x
.yblk   ldx curT
        rts

; vertical tank edge: column x = tmp2, pairs A+1, A+4, A+6.
; Returns A != 0 for a wall.  Clobbers X, Y, tmp+5.
EdgeV:
        and #$7F
        tay
        ldx tmp2
        cpx #176
        bcc .ev
        ldx #0
.ev     sty tmp+5
        lda RowOff+1,y
        clc
        adc ColByte,x
        tay
        lda (mazePtr),y
        and ColMask,x
        bne .ev9
        ldy tmp+5
        lda RowOff+4,y
        adc ColByte,x
        tay
        lda (mazePtr),y
        and ColMask,x
        bne .ev9
        ldy tmp+5
        lda RowOff+6,y
        adc ColByte,x
        tay
        lda (mazePtr),y
        and ColMask,x
.ev9    rts

; horizontal tank edge: pair A, columns tmp2+1, +4, +6.
EdgeH:
        and #$7F
        tay
        lda RowOff,y
        sta tmp+5
        ldx tmp2
        cpx #168
        bcc .eh
        ldx #0
.eh     clc
        adc ColByte+1,x
        tay
        lda (mazePtr),y
        and ColMask+1,x
        bne .eh9
        lda tmp+5
        adc ColByte+4,x
        tay
        lda (mazePtr),y
        and ColMask+4,x
        bne .eh9
        lda tmp+5
        adc ColByte+6,x
        tay
        lda (mazePtr),y
        and ColMask+6,x
.eh9    rts

; A = pair (y), tmp2 = pixel x. Returns A != 0 (Z clear) for a wall.
; Clobbers X and Y.
TestPt:
        and #$7F
        tay
        ldx tmp2
        cpx #176
        bcc .tp
        ldx #0
.tp     lda RowOff,y
        clc
        adc ColByte,x
        tay
        lda (mazePtr),y
        and ColMask,x
        rts

; X = tank: fire a missile
Launch:
        lda #MIS_LIFE
        cpx #0
        bne .l1
        bit SWCHB
        bvc .l2
        lda #MIS_SHORT
        bne .l2
.l1     bit SWCHB
        bpl .l2
        ldy players
        beq .l2                 ; CPU ignores the range switch
        lda #MIS_SHORT
.l2     sta mlife,x
        ldy tdir,x
        lda txh,x
        clc
        adc #3
        clc
        adc MisOfsX,y
        sta mxh,x
        lda tyh,x
        clc
        adc #4
        clc
        adc MisOfsY,y
        sta myh,x
        lda #$80
        sta mxl,x
        sta myl,x
        tya
        clc
        adc #48
        tay
        lda VelXL,y
        sta mvxl,x
        lda VelXH,y
        sta mvxh,x
        lda VelYL,y
        sta mvyl,x
        lda VelYH,y
        sta mvyh,x
        lda #0
        ldy weapon
        cpy #2
        beq .bnc
        ldy pu,x
        cpy #PU_BOUNCE
        bne .nb
.bnc    lda #4
.nb     sta mbnc,x
        lda #40
        sta vis,x
        lda #SND_SHOT
        jmp PlaySnd

; X = missile owner
Missile:
        stx curT
        lda mlife,x
        bne .m1
        rts
.m1     dec mlife,x
        bne .m2
        rts
.m2     lda weapon
        cmp #1
        bne .m3
        lda tdir,x              ; guided: follow the tank's heading
        clc
        adc #48
        tay
        lda VelXL,y
        sta mvxl,x
        lda VelXH,y
        sta mvxh,x
        lda VelYL,y
        sta mvyl,x
        lda VelYH,y
        sta mvyh,x
.m3     clc
        lda mxl,x
        adc mvxl,x
        sta tmp
        lda mxh,x
        adc mvxh,x
        sta tmp+1
        clc
        lda myl,x
        adc mvyl,x
        sta tmp+2
        lda myh,x
        adc mvyh,x
        sta tmp+3
        lda tmp+1
        sta tmp2
        lda tmp+3
        jsr TestPt
        ldx curT
        tay
        beq .free
        lda mbnc,x
        cmp #2
        bcs .bounce
        lda #0
        sta mlife,x
        rts
.bounce dec mbnc,x
        lda #SND_BOUNCE
        jsr PlaySnd
        ldx curT
        lda tmp+1               ; wall when only x changes?
        sta tmp2
        lda myh,x
        jsr TestPt
        sta tmp+5
        ldx curT
        lda mxh,x               ; wall when only y changes?
        sta tmp2
        lda tmp+3
        jsr TestPt
        ldx curT
        tay
        beq .bx
        jsr NegVY
.bx     lda tmp+5
        beq .by
        jsr NegVX
.by     tya
        ora tmp+5
        bne .b9
        jsr NegVX               ; corner: reverse both
        jsr NegVY
.b9     rts
.free   lda tmp
        sta mxl,x
        lda tmp+1
        sta mxh,x
        lda tmp+2
        sta myl,x
        lda tmp+3
        sta myh,x
        ldy #0
        jsr HitTest
        ldx curT
        lda mlife,x
        beq .f9
        ldy #1
        jsr HitTest
.f9     rts

NegVX:  lda #0
        sec
        sbc mvxl,x
        sta mvxl,x
        lda #0
        sbc mvxh,x
        sta mvxh,x
        rts
NegVY:  lda #0
        sec
        sbc mvyl,x
        sta mvyl,x
        lda #0
        sbc mvyh,x
        sta mvyh,x
        rts

; X = missile owner, Y = tank to test
HitTest:
        cpy curT
        bne .h1
        lda mbnc,x              ; own tank: only after a ricochet
        beq .h9
        cmp #4
        bcs .h9
.h1     lda stirT
        bne .h9
        lda mxh,x
        sec
        sbc txh,y
        cmp #7
        bcs .h9
        lda myh,x
        sec
        sbc tyh,y
        sec
        sbc #1
        cmp #6
        bcs .h9
        jmp TankHit
.h9     rts

; X = missile owner, Y = victim
TankHit:
        lda #0
        sta mlife,x
        sty stirWho
        stx stirMis
        lda pu,y
        cmp #PU_SHIELD
        bne .boom
        lda #0
        sta pu,y
        lda #4
        sta flash
        tya
        tax
        lda #SND_SHIELD
        jmp PlaySnd
.boom   tya
        eor #1
        tax
        sed
        lda score,x
        clc
        adc #1
        sta score,x
        cld
        lda #STIR_TIME
        sta stirT
        lda #12
        sta flash
        lda #0
        sta mlife
        sta mlife+1
        ldx stirWho
        lda #SND_BOOM
        jmp PlaySnd

; the hit tank spins and is pushed along the missile's path
Stir:
        dec stirT
        bne .s1
        jmp RoundOver
.s1     ldx stirWho
        stx curT
        lda stirT
        and #1
        beq .s2
        lda tdir,x
        clc
        adc #1
        and #15
        sta tdir,x
.s2     lda stirT
        cmp #STIR_TIME-16
        bcc .s9
        ldy stirMis
        lda mvxh,y
        cmp #$80
        ror
        sta tvxh
        lda mvxl,y
        ror
        sta tvxl
        lda mvyh,y
        cmp #$80
        ror
        sta tvyh
        lda mvyl,y
        ror
        sta tvyl
        jsr MoveTank
.s9     rts

RoundOver:
        lda stirWho
        eor #1
        tax
        lda score,x
        cmp #WIN_SCORE
        bcc .ro1
        stx winner
        lda #ST_OVER
        sta state
        lda #0
        sta snd+1
        ldx #0
        lda #SND_FANFARE
        jmp PlaySnd
.ro1    lda amode
        beq .ro0
        cmp #3
        bne .ro2
.ro0    ; fall through: every mode rotates arenas
.ro2    inc arenaPts
        lda arenaPts
        cmp #3
        bcc .ro9
        lda #0
        sta arenaPts
        inc arena
        ldx amode
        lda ArenaFirst,x
        clc
        adc ArenaCount,x
        cmp arena
        bne .ro3
        lda ArenaFirst,x
        sta arena
.ro3    jsr ResetRound
        ldx #1
        lda #SND_START
        jsr PlaySnd
.ro9    rts

; -------------------------------------------------------------- CPU player
AI:
        lda #0
        sta aiJoy
        lda players
        beq .ai0
        rts
.ai0    lda stirT
        beq .ai1
        rts
.ai1
        ; |dx| and sign
        lda txh
        sec
        sbc txh+1
        ldy #0
        bcs .a1
        eor #$FF
        adc #1
        iny
.a1     sta aiAX
        sty aiSX
        lda tyh
        sec
        sbc tyh+1
        ldy #0
        bcs .a2
        eor #$FF
        adc #1
        iny
.a2     sta aiRY
        sty aiSY
        lsr
        lsr
        clc
        adc aiRY
        sta aiAY
        ; scale down to < 32
        lda aiAX
        sta tmp
        lda aiAY
        sta tmp+1
.red    lda tmp
        cmp #32
        bcs .shr
        lda tmp+1
        cmp #32
        bcc .sect
.shr    lsr tmp
        lsr tmp+1
        jmp .red
.sect   ; tmp = a (x), tmp+1 = b (y)
        lda tmp
        asl
        sta tmp+2               ; a*2
        clc
        adc tmp
        sta tmp+3               ; a*3
        ldx #0
        lda tmp+1
        asl
        asl
        clc
        adc tmp+1               ; b*5
        cmp tmp
        bcc .sct
        inx
        lda tmp+1
        asl
        clc
        adc tmp+1               ; b*3
        cmp tmp+2
        bcc .sct
        inx
        lda tmp+1
        asl                     ; b*2
        cmp tmp+3
        bcc .sct
        inx
        lda tmp
        asl
        asl
        clc
        adc tmp                 ; a*5
        cmp tmp+1
        beq .s4
        bcs .sct
.s4     inx
.sct    stx tmp
        lda aiSX
        beq .q1
        lda aiSY
        bne .q3
        lda #8                  ; dx<0, dy>=0
        sec
        sbc tmp
        jmp .qd
.q3     lda #8                  ; dx<0, dy<0
        clc
        adc tmp
        jmp .qd
.q1     lda aiSY
        beq .q0
        lda #16                 ; dx>=0, dy<0
        sec
        sbc tmp
        jmp .qd
.q0     lda tmp
.qd     and #15
        sta aiWant

        ; line of sight, every 4th frame
        jsr LineOfSight
        ; behaviour
        lda aiMode
        beq .chase
        dec aiT
        beq .endm
        lda aiMode
        cmp #2
        bne .avoid
        lda aiHead              ; lining up: heading 4/12 matches y, 0/8 x
        and #4
        beq .alx
        lda aiRY
        jmp .alc
.alx    lda aiAX
.alc    cmp #2
        bcs .avoid
.endm   lda #0
        sta aiMode
        beq .chase
.avoid  lda aiHead
        jsr SteerTo
        jsr FwdIfAligned
        jmp .stuck
.chase  lda aiWant
        jsr SteerTo
        lda aiLOS
        beq .drive
        lda aiAX
        clc
        adc aiAY
        bcs .drive
        cmp #44
        bcc .hold               ; close with a clear shot: hold position
.drive  lda #0
        sta SCW+SC_HOLD
        jsr FwdIfAligned
        jmp .stuck
.hold   lda SCR+SC_HOLD         ; holding without scoring: line up instead
        clc
        adc #1
        sta SCW+SC_HOLD
        cmp #90
        bcc .stuck
        jsr StartAlign
.stuck
        lda moved+1
        bne .ns
        inc aiStuck
        lda aiStuck
        cmp #8
        bcc .fire
        jsr ChooseAvoid
        jmp .fire
.ns     lda #0
        sta aiStuck
.fire   lda aiLOS
        beq .nf0
        lda tdir+1
        cmp aiWant
        bne .nf0
        inc aiAlign
        ldx #3
        bit SWCHB
        bmi .hard
        ldx #14
.hard   cpx aiAlign
        bcs .dodge
        lda mlife+1
        bne .dodge
        lda aiJoy
        ora #$80
        sta aiJoy
        bne .dodge
.nf0    lda #0
        sta aiAlign
.dodge  bit SWCHB               ; hard CPU dodges close missiles
        bpl .ai9
        lda mlife
        beq .ai9
        lda mxh
        sec
        sbc txh+1
        clc
        adc #18
        cmp #30
        bcs .ai9
        lda myh
        sec
        sbc tyh+1
        clc
        adc #14
        cmp #24
        bcs .ai9
        lda aiJoy
        and #$FC
        ora #$02
        sta aiJoy
.ai9    rts

StartAlign:
        lda #0
        sta SCW+SC_HOLD
        lda SCR+SC_ALT          ; alternate the axis on each try
        eor #1
        sta SCW+SC_ALT
        lsr
        lda aiAX
        bcc .sa0
        lda aiAY
        cmp aiAX
        jmp .sa1
.sa0    cmp aiAY
.sa1    bcc .vx
        ldy #4                  ; mostly sideways: match height
        lda aiSY
        beq .sa
        ldy #12
        bne .sa
.vx     ldy #0                  ; mostly vertical: match x
        lda aiSX
        beq .sa
        ldy #8
.sa     sty aiHead
        lda #2
        sta aiMode
        lda #70
        sta aiT
        rts

; A = wanted heading; sets turn bits in aiJoy, leaves diff in tmp+5
SteerTo:
        sec
        sbc tdir+1
        and #15
        sta tmp+5
        beq .st9
        cmp #8
        lda #$04                ; left = counter-clockwise
        bcc .st1
        lda #$08
.st1    ora aiJoy
        sta aiJoy
.st9    rts

FwdIfAligned:
        lda tmp+5
        clc
        adc #2
        and #15
        cmp #5
        bcs .fa9
        lda aiJoy
        ora #$01
        sta aiJoy
.fa9    rts

ChooseAvoid:
        lda #0
        sta aiStuck
        lda aiMode              ; stuck again while avoiding: back out
        cmp #1
        bne .ca0
        lda rand
        and #2
        clc
        adc tdir+1
        adc #7
        and #15
        sta aiHead
        lda rand
        and #31
        adc #45
        sta aiT
        rts
.ca0
        lda tdir+1
        clc
        adc #4
        and #15
        jsr Probe
        sta tmp+5               ; left blocked?
        lda tdir+1
        sec
        sbc #4
        and #15
        jsr Probe
        ldx tmp+5
        bne .ca1
        tay
        bne .caL
        lda rand                ; both open: random side
        bmi .caL
        bpl .caR
.ca1    tay
        bne .caB
.caR    lda tdir+1
        sec
        sbc #4
        jmp .ca9
.caL    lda tdir+1
        clc
        adc #4
        jmp .ca9
.caB    lda tdir+1
        clc
        adc #8
.ca9    and #15
        sta aiHead
        lda #1
        sta aiMode
        lda rand
        and #31
        clc
        adc #20
        sta aiT
        rts

; A = heading: wall at a point ahead of the CPU tank in that direction?
Probe:
        tay
        lda txh+1
        clc
        adc #4
        clc
        adc ProbeX,y
        sta tmp2
        lda tyh+1
        clc
        adc #4
        clc
        adc ProbeY,y
        jmp TestPt

; Line of sight from the CPU tank's centre to the player, sampled at 16
; points, 2 per frame.  A wall clears aiLOS at once; a full clear sweep
; sets it.  Sweep state lives in Superchip RAM.
LineOfSight:
        lda SCR+SC_LOSK
        bne .step
        lda aiAX
        sta tvxl
        lda #0
        sta tvxh
        lda aiRY
        sta tvyl
        lda #0
        sta tvyh
        ldx #4                  ; 15 samples at 1/16 steps, one per frame
.sh     asl tvxl
        rol tvxh
        asl tvyl
        rol tvyh
        dex
        bne .sh
        lda aiSX
        beq .l1
        lda #0
        sec
        sbc tvxl
        sta tvxl
        lda #0
        sbc tvxh
        sta tvxh
.l1     lda aiSY
        beq .l2
        lda #0
        sec
        sbc tvyl
        sta tvyl
        lda #0
        sbc tvyh
        sta tvyh
.l2     lda tvxl
        sta SCW+SC_LOS+4
        lda tvxh
        sta SCW+SC_LOS+5
        lda tvyl
        sta SCW+SC_LOS+6
        lda tvyh
        sta SCW+SC_LOS+7
        lda #$80
        sta SCW+SC_LOS
        sta SCW+SC_LOS+2
        lda txh+1
        clc
        adc #4
        sta SCW+SC_LOS+1
        lda tyh+1
        clc
        adc #4
        sta SCW+SC_LOS+3
.step   lda #1
        sta tmp+5
.lp     clc
        lda SCR+SC_LOS
        adc SCR+SC_LOS+4
        sta SCW+SC_LOS
        lda SCR+SC_LOS+1
        adc SCR+SC_LOS+5
        sta SCW+SC_LOS+1
        sta tmp2
        clc
        lda SCR+SC_LOS+2
        adc SCR+SC_LOS+6
        sta SCW+SC_LOS+2
        lda SCR+SC_LOS+3
        adc SCR+SC_LOS+7
        sta SCW+SC_LOS+3
        jsr TestPt
        bne .blk
        lda SCR+SC_LOSK
        clc
        adc #1
        sta SCW+SC_LOSK
        cmp #15
        bcs .clear
        dec tmp+5
        bne .lp
        rts
.clear  lda #1
        sta aiLOS
        bne .reset
.blk    lda #0
        sta aiLOS
.reset  lda #0
        sta SCW+SC_LOSK
        rts

; -------------------------------------------------------------- sound
; X = channel, A = sound
PlaySnd:
        sta snd,x
        lda #1
        sta sndT,x
        rts

; -------------------------------------------------------------- tables
ArenaFirst  .byte 0, 3, 0, 0
; plane games 25-34 (one player) and 35-44 (two players)
PlaneGames  .byte $00, $05, $03, $0C, $10    ; biplane
            .byte $20, $25, $23, $29, $3C    ; jet
ArenaCount  .byte 3, 5, NUM_ARENAS, NUM_ARENAS

MazePtrLo
        .byte <(MazeMaps+0*63), <(MazeMaps+1*63), <(MazeMaps+2*63), <(MazeMaps+3*63)
        .byte <(MazeMaps+4*63), <(MazeMaps+5*63), <(MazeMaps+6*63), <(MazeMaps+7*63)
MazePtrHi
        .byte >(MazeMaps+0*63), >(MazeMaps+1*63), >(MazeMaps+2*63), >(MazeMaps+3*63)
        .byte >(MazeMaps+4*63), >(MazeMaps+5*63), >(MazeMaps+6*63), >(MazeMaps+7*63)

        include bank0_data.inc

Bank0End
        echo "bank 0 free:", $FFD0-Bank0End

; ---- bank switching: flight logic and kernel trampolines, reset
        org $0FD0
        rorg $FFD0
CallFlight:
        sta $1FF8               ; -> bank 2, which runs JSR FlightLogic at $FFD3
        nop
        nop
        nop
        nop
        nop
        nop
        rts                     ; $FFD9
        org $0FE0
        rorg $FFE0
CallKernel:
        sta $1FF7               ; -> bank 1, which runs JSR KernelMain at $FFE3
        nop
        nop
        nop
        nop
        nop
        nop
        rts                     ; $FFE9, reached after bank 1 switches back
        org $0FF0
        rorg $FFF0
        sta $1FF6
        jmp Start
        org $0FFA
        rorg $FFFA
        .word $FFF0, $FFF0, $FFF0

; ====================================================================
; BANK 1 - display
; ====================================================================
        org $1000
        rorg $F000
        ds 256, $FF
        org $1100
        rorg $F100
        include bank1_shapes.inc        ; 384 bytes, page aligned

KernelMain:
        tsx
        stx saveSP
        ldx #1
.my     lda #$FF
        ldy mlife,x
        beq .my1
        lda myh,x
.my1    sta m0y,x
        dex
        bpl .my
        lda txh
        ldx #0
        jsr PosObj
        lda txh+1
        ldx #1
        jsr PosObj
        lda mxh
        ldx #2
        jsr PosObj
        lda mxh+1
        ldx #3
        jsr PosObj
        lda boxX
        ldx #4
        jsr PosObj
        sta WSYNC
        sta HMOVE
        lda #$10                ; tanks: missiles 2 pixels wide
        sta NUSIZ0
        sta NUSIZ1
        lda #$21                ; reflect, ball 4 wide
        sta tmp+5
        ldx vehicle
        beq .nus
        ldy form                ; planes: formation copies, clouds in front
        ldx FS0,y
        lda NusTbl,x
        sta NUSIZ0
        ldx FS1,y
        lda NusTbl,x
        sta NUSIZ1
        lda #$25
        sta tmp+5
.nus
        lda #0
        sta REFP0
        sta REFP1
        sta VDELP0
        sta VDELP1
        sta VDELBL
        sta HMCLR
        ; sprite pointers: shape(vehicle, dir) - y
        ldx #2
.sp     ldy vehicle
        lda tdir-2,x            ; X = 2 for p0ptr, 4 for p1ptr
        asl
        asl
        asl
        clc
        adc ShapeLo,y
        sta p0ptr-2,x
        lda ShapeHi,y
        adc #0
        sta p0ptr-1,x
        txa
        lsr
        tay
        lda p0ptr-2,x
        sec
        sbc tyh-1,y
        sta p0ptr-2,x
        lda p0ptr-1,x
        sbc #0
        sta p0ptr-1,x
        inx
        inx
        cpx #6
        bne .sp
        lda state
        bne ArenaKernel
        jmp TitleKernel

; ---------------------------------------------------------- arena kernel
ArenaKernel:
.wt     lda INTIM
        bne .wt
        sta WSYNC
        sta VBLANK              ; line 0
        lda bkCol
        sta COLUBK
        lda col0
        sta COLUP0
        lda col1
        sta COLUP1
        lda #$02                ; score mode for the digits
        sta CTRLPF
        ldx #3
.top    sta WSYNC
        dex
        bne .top
        ; ---- score: 5 rows x 2 lines
        ldx #0
.sc     sta WSYNC               ; 0
        lda SCR+SC_SCORE,x      ; 4
        sta PF1                 ; 7
        ldy #6                  ; 9
.d1     dey
        bne .d1                 ; 38
        lda SCR+SC_SCORE+5,x    ; 42
        sta PF1                 ; 45
        sta WSYNC
        lda SCR+SC_SCORE,x
        sta PF1
        ldy #6
.d2     dey
        bne .d2
        lda SCR+SC_SCORE+5,x
        sta PF1
        inx
        cpx #5
        bne .sc
        sta WSYNC
        lda #0
        sta PF1
        lda tmp+5               ; reflect, ball 4 wide (+ priority for clouds)
        sta CTRLPF
        lda pfCol
        sta COLUPF
        ldx #8
.gap    sta WSYNC
        dex
        bne .gap
        ; ---- prepare the first pair (84)
        sta WSYNC
        lda SCR+SC_PF0
        sta PF0
        lda SCR+SC_PF1
        sta PF1
        lda SCR+SC_PF2
        sta PF2
        ldy #84
        tya
        sec
        sbc tyh
        cmp #8
        bcs .f0
        lda (p0ptr),y
        .byte $2C
.f0     lda #0
        sta gfx0
        tya
        sec
        sbc tyh+1
        cmp #8
        bcs .f1
        lda (p1ptr),y
        .byte $2C
.f1     lda #0
        sta gfx1

; 84 line pairs. Line A: sprites, missiles, ball.  Line B: playfield.
ArenaLoop:
        sta WSYNC               ; ---- line A
        lda gfx0                ; 3
        sta GRP0                ; 6
        lda gfx1                ; 9
        sta GRP1                ; 12
        ldx #ENABL              ; 14
        txs                     ; 16
        tya                     ; 18
        sec                     ; 20
        sbc bly                 ; 23
        and #$FC                ; 25
        php                     ; 28 ENABL
        cpy m1y                 ; 31
        php                     ; 34 ENAM1
        cpy m0y                 ; 37
        php                     ; 40 ENAM0
        dey                     ; 42
        tya                     ; 44
        sec                     ; 46
        sbc tyh                 ; 49
        cmp #8                  ; 51
        bcs .n0                 ; 53
        lda (p0ptr),y           ; 59
        .byte $2C               ; 63
.n0     lda #0
        sta gfx0                ; 66
        sta WSYNC               ; ---- line B
        ldx RowIdx,y            ; 4
        lda SCR+SC_PF0,x        ; 8
        sta PF0                 ; 11
        lda SCR+SC_PF1,x        ; 15
        sta PF1                 ; 18
        lda SCR+SC_PF2,x        ; 22
        sta PF2                 ; 25
        tya                     ; 27
        sec                     ; 29
        sbc tyh+1               ; 32
        cmp #8                  ; 34
        bcs .n1                 ; 36
        lda (p1ptr),y           ; 42
        .byte $2C               ; 46
.n1     lda #0
        sta gfx1                ; 49
        tya                     ; 51
        bne ArenaLoop           ; 54

        sta WSYNC
        lda #2
        sta VBLANK
        lda #0
        sta PF0
        sta PF1
        sta PF2
        sta GRP0
        sta GRP1
        sta ENAM0
        sta ENAM1
        sta ENABL
EndFrame:
        lda #2
        sta VBLANK
        lda #OS_TIME
        sta TIM64T
        ldx saveSP
        txs
        jsr Sound
        jsr SetupDisplay
        ; score graphics into Superchip RAM, only when they change
        lda dispL
        cmp SCR+SC_LAST
        bne .bs
        lda dispR
        cmp SCR+SC_LAST+1
        beq .bs9
.bs     lda dispL
        sta SCW+SC_LAST
        lda dispR
        sta SCW+SC_LAST+1
        ldy #SC_SCORE
        lda dispL
        jsr Digits5
        lda dispR
        jmp Digits5             ; busy frame: leave the rest for the next one
.bs9    lda vehicle
        bne .bsf
        jmp PowerUps
.bsf    jmp CallFlightOS        ; bank 2

; ---------------------------------------------------------- title kernel
TitleKernel:
.wt     lda INTIM
        bne .wt
        sta WSYNC
        sta VBLANK
        sta COLUBK
        sta CTRLPF
        lda col0
        sta COLUP0
        lda col1
        sta COLUP1
        ldx #34
.t1     sta WSYNC
        dex
        bne .t1
        ; logo: one table lookup per line keeps every write in its window
        lda frame
        asl
        asl
        and #$F0
        sta tmp
        ldy #TITLE_LINES
        ldx TitleLR,y
TLoop:  sta WSYNC               ; 0
        lda TitleCol,x          ; 4
        eor tmp                 ; 7
        sta COLUPF              ; 10
        lda TPF0L,x             ; 14
        sta PF0                 ; 17
        lda TPF1L,x             ; 21
        sta PF1                 ; 24
        lda TPF2L,x             ; 28
        sta PF2                 ; 31
        lda TPF0R,x             ; 35
        sta PF0                 ; 38
        lda TPF1R,x             ; 42
        sta PF1                 ; 45
        lda TPF2R,x             ; 49
        sta PF2                 ; 52
        ldx TitleLR-1,y         ; 56
        dey                     ; 58
        bne TLoop               ; 61
        jsr ClearPF
        ldy #24
.t3     sta WSYNC
        dey
        bne .t3
        ; two tanks facing off
        ldy #7
.tk     sta WSYNC
        lda TankShapes+0,y
        sta GRP0
        lda TankShapes+64,y
        sta GRP1
        sta WSYNC
        dey
        bpl .tk
        sta WSYNC
        lda #0
        sta GRP0
        sta GRP1
        ldy #32
.t4     sta WSYNC
        dey
        bne .t4
        jmp EndFrame

ClearPF:
        sta WSYNC
        lda #0
        sta PF0
        sta PF1
        sta PF2
        rts

; ---------------------------------------------------------- helpers
; A = x, X = object (0 P0, 1 P1, 2 M0, 3 M1, 4 BL)
PosObj:
        clc
        adc PosAdj,x
        cmp #160
        bcc .ok
        lda #0
.ok     sta WSYNC
        sec
.div    sbc #15
        bcs .div
        eor #7
        asl
        asl
        asl
        asl
        sta HMP0,x
        sta RESP0,x
        rts

; A = BCD value, Y = Superchip offset (advanced by 5)
Digits5:
        pha
        and #$0F
        tax
        lda Times5,x
        sta tmp
        pla
        lsr
        lsr
        lsr
        lsr
        tax
        lda Times5,x
        sta tmp+1
        lda #5
        sta tmp+2
.dl     ldx tmp+1
        lda Digits,x
        and #$F0
        sta tmp+3
        ldx tmp
        lda Digits,x
        and #$0F
        ora tmp+3
        sta SCW,y
        inc tmp
        inc tmp+1
        iny
        dec tmp+2
        bne .dl
        rts

; -------------------------------------------------------------- power-ups
PowerUps:
        lda state
        cmp #ST_PLAY
        bne .pu8
        lda amode
        bne .pu0
.pu8    rts
.pu0    lda stirT
        beq .pu1
        rts
.pu1    lda frame
        and #3
        bne .pubox
        ldx #1
.ptim   lda pu,x
        beq .pt1
        dec put,x
        bne .pt1
        lda #0
        sta pu,x
.pt1    dex
        bpl .ptim
.pubox  lda boxY
        bne .present
        lda frame
        and #3
        bne .pu9
        dec boxT
        bne .pu9
        lda arena
        asl
        asl
        sta tmp
        lda rand
        and #3
        ora tmp
        tax
        lda SpotX,x
        sta boxX
        lda SpotY,x
        sta boxY
        lda #200
        sta boxT
.pu9    rts
.present
        lda frame
        and #3
        bne .pk0
        dec boxT
        bne .pk0
        lda #0
        sta boxY
        lda #60
        sta boxT
        rts
.pk0    ldx #1
.pk     lda boxX
        sec
        sbc txh,x
        clc
        adc #3
        cmp #11
        bcs .np
        lda boxY
        sec
        sbc tyh,x
        clc
        adc #3
        cmp #11
        bcs .np
        lda rand
        and #3
        clc
        adc #1
        sta pu,x
        lda #150
        sta put,x
        lda #0
        sta boxY
        lda #75
        sta boxT
        lda #SND_PICKUP
        sta snd,x
        lda #1
        sta sndT,x
        rts
.np     dex
        bpl .pk
        rts


PosAdj  .byte $FD, $FD, $FE, $FE, $FE    ; -3 players, -2 missiles and ball

; -------------------------------------------------------------- display prep
SetupDisplay:
        ldx arena
        lda ArenaBK,x
        sta bkCol
        lda ArenaPF,x
        sta pfCol
        lda state
        bne .sd0
        lda #$00                ; title screen: black
        sta bkCol
.sd0    lda flash
        beq .sd1
        dec flash
        and #2
        beq .sd1
        lda #$46
        sta bkCol
.sd1
        ldx #1
.sdl    lda vehicle
        beq .sdt
        lda FlyCol,x
        bne .sd2
.sdt    lda #COL_P0
        cpx #0
        beq .sd2
        lda #COL_P1
.sd2    sta tmp
        lda pu,x
        cmp #PU_SPEED
        bne .sd3
        lda frame
        and #4
        beq .sd6
        lda tmp
        ora #$0E
        sta tmp
        bne .sd6
.sd3    cmp #PU_SHIELD
        bne .sd4
        lda tmp
        and #$F0
        ora #$0C
        sta tmp
        bne .sd6
.sd4    cmp #PU_BOUNCE
        bne .sd6
        lda frame
        and #8
        beq .sd6
        lda #$1E
        sta tmp
.sd6    ; invisibility
        lda vis,x
        beq .sd7
        dec vis,x
        bne .shown
.sd7    lda amode
        cmp #3
        beq .inv
        lda pu,x
        cmp #PU_CLOAK
        bne .shown
.inv    lda state
        cmp #ST_PLAY
        bne .shown
        lda mlife,x
        bne .shown
        lda stirT
        beq .hide
        cpx stirWho
        beq .shown
.hide   lda bkCol
        sta tmp
.shown  lda SWCHB
        and #8
        bne .col
        lda tmp
        and #$0F
        sta tmp
.col    lda tmp
        sta col0,x
        dex
        bmi .sd9
        jmp .sdl
.sd9
        ; power-up box (blinks)
        lda #$F0
        ldy boxY
        beq .sd10
        ldy frame
        cpy #0
        tya
        and #8
        beq .sdb
        lda boxY
        bne .sd10
.sdb    lda #$F0
.sd10   sta bly
        ; scores
        lda #$AA                ; $AA = blank digits
        sta dispL
        sta dispR
        lda state
        cmp #ST_SELECT
        bne .sd11
        lda gameBCD
        sta dispL
        rts
.sd11   cmp #ST_PLAY
        beq .sd12
        cmp #ST_OVER
        bne .sd13
.sd12   lda score
        sta dispL
        lda score+1
        sta dispR
        lda state
        cmp #ST_OVER
        bne .sd13
        lda frame
        and #16
        beq .sd13
        lda #$AA
        ldx winner
        sta dispL,x
.sd13   rts


Sound:
        ldx #1
.sn     lda snd,x
        beq .engine
        dec sndT,x
        bne .snx
        ldy snd,x
        lda SndData,y
        beq .send
        sta AUDC0,x
        lsr
        lsr
        lsr
        lsr
        sta AUDV0,x
        lda SndData+1,y
        sta AUDF0,x
        iny
        iny
        sty snd,x
        lda #2
        sta sndT,x
        bne .snx
.send   sta snd,x
.engine lda #0
        ldy state
        cpy #ST_PLAY
        bne .eng1
        ldy stirT
        bne .eng1
        ldy vehicle
        beq .tnk
        lda EngC-1,y            ; planes: engine always on, pitch by speed
        sta AUDC0,x
        lda spd,x
        asl
        asl
        eor #$FF
        sec
        adc EngF-1,y
        sta AUDF0,x
        lda #3
        bne .eng1
.tnk    lda joy,x
        and #3
        beq .eng1
        lda #2
        sta AUDC0,x
        lda #$1C
        ldy pu,x
        cpy #PU_SPEED
        bne .eng0
        lda #$14
.eng0   sta AUDF0,x
        lda #5
.eng1   sta AUDV0,x
.snx    dex
        bpl .sn
        rts




; formations: side codes 0 single, 1 two close, 2 three close, 3 bomber
FS0     .byte 0, 1, 0, 3
FS1     .byte 0, 1, 2, 2
NusTbl  .byte $10, $11, $13, $27
FlyCol  .byte $1C, $4A
EngC    .byte 3, 8
EngF    .byte $1E, $12
ShapeLo .byte <TankShapes, <PlaneShapes, <JetShapes
ShapeHi .byte >TankShapes, >PlaneShapes, >JetShapes

        include bank1_data.inc

Bank1End
        echo "bank 1 free:", $FFC0-Bank1End

        org $1FC0
        rorg $FFC0
CallFlightOS:
        sta $1FF8               ; -> bank 2, which runs JSR FlightOS at $FFC3
        nop
        nop
        nop
        nop
        nop
        nop
        rts                     ; $FFC9, reached after bank 2 switches back
        org $1FE3
        rorg $FFE3
        jsr KernelMain
        sta $1FF6               ; back to bank 0, which returns at $FFE9
        org $1FF0
        rorg $FFF0
        sta $1FF6
        org $1FFA
        rorg $FFFA
        .word $FFF0, $FFF0, $FFF0

; ====================================================================
; BANK 2 - flight logic for the plane games
; ====================================================================
        org $2000
        rorg $F000
        ds 256, $FF             ; Superchip RAM window
        org $2100
        rorg $F100

; ====================================================================
; FLIGHT - biplane and jet games (bank 2)
; ====================================================================
; called from bank 0 in vertical blank during play
FlightLogic:
        lda SCR+SC_FLR
        bne .fl9
        lda stirT
        beq .fl1
        jmp FStir
.fl1    lda SWCHA
        eor #$FF
        lsr
        lsr
        lsr
        lsr
        sta joy
        lda INPT4
        eor #$80
        and #$80
        ora joy
        sta joy
        lda players
        bne .h2
        lda aiJoy
        jmp .s2
.h2     lda SWCHA
        eor #$FF
        and #$0F
        sta joy+1
        lda INPT5
        eor #$80
        and #$80
        ora joy+1
.s2     sta joy+1
        ldx #0
        jsr FlyControl
        ldx #1
        jmp FlyControl
.fl9    rts

; X = plane
FlyControl:
        lda joy,x
        and #$0C
        bne .ft
        sta tturn,x
        beq .fspd
.ft     lda tturn,x
        beq .fdt
        dec tturn,x
        jmp .fspd
.fdt    ldy vehicle
        lda FTurn-1,y
        cpx #1
        bne .ftd
        ldy players
        bne .ftd
        bit SWCHB               ; easy CPU turns slower
        bmi .ftd
        clc
        adc #4
.ftd    sta tturn,x
        lda joy,x
        and #$04
        beq .fr
        inc tdir,x
        jmp .fw
.fr     dec tdir,x
.fw     lda tdir,x
        and #15
        sta tdir,x
.fspd   ldy #1                  ; speed: up = fast, down = slow
        lda joy,x
        lsr
        bcc .fs1
        iny
.fs1    lsr
        bcc .fs2
        dey
.fs2    tya
        sta spd,x
        ldy vehicle
        cpy #2
        bne .fs3
        clc
        adc #3
.fs3    asl
        asl
        asl
        asl
        clc
        adc tdir,x
        tay
        jsr LoadVel
        clc
        lda txl,x
        adc tvxl
        sta txl,x
        lda txh,x
        adc tvxh
        jsr WrapX
        sta txh,x
        clc
        lda tyl,x
        adc tvyl
        sta tyl,x
        lda tyh,x
        adc tvyh
        jsr WrapY
        sta tyh,x
        lda joy,x
        bpl .fc9
        lda mlife,x
        bne .fc9
        ; launch from the plane's centre
        lda #70
        ldy weapon
        cpy #3
        bne .fl2
        lda #22                 ; machine gun: short bursts
.fl2    sta mlife,x
        lda txh,x
        clc
        adc #3
        sta mxh,x
        lda tyh,x
        clc
        adc #4
        sta myh,x
        lda #$80
        sta mxl,x
        sta myl,x
        jsr MisVel
        lda #0
        sta mbnc,x
        lda #SND_SHOT
        sta snd,x
        lda #1
        sta sndT,x
.fc9    rts

; missile velocity from the owner's heading (X = owner)
MisVel: lda tdir,x
        clc
        adc #96                 ; row 6: missile
        ldy weapon
        cpy #3
        bne .mv1
        clc
        adc #16                 ; row 7: machine-gun bullet
.mv1    tay
        jsr LoadVel
        lda tvxl
        sta mvxl,x
        lda tvxh
        sta mvxh,x
        lda tvyl
        sta mvyl,x
        lda tvyh
        sta mvyh,x
        rts

; Y = row*16 + heading -> tvx, tvy (8.8)
LoadVel:
        lda FVelX,y
        jsr Ext
        sta tvxh
        lda tmp+3
        sta tvxl
        lda FVelY,y
        jsr Ext
        sta tvyh
        lda tmp+3
        sta tvyl
        rts
; signed 1/32 pixel -> 8.8: high byte in A, low byte in tmp+3
Ext:    sta tmp+3
        cmp #$80
        ror
        cmp #$80
        ror
        cmp #$80
        ror
        cmp #$80
        ror
        cmp #$80
        ror
        sta tmp+2
        lda tmp+3
        asl
        asl
        asl
        sta tmp+3
        lda tmp+2
        rts

WrapX:  cmp #160
        bcc .wx9
        cmp #208
        bcs .wxn
        sec
        sbc #160
        rts
.wxn    adc #159                ; carry set: +160
.wx9    rts

WrapY:  cmp #1
        bcc .wyu
        cmp #200
        bcs .wyu
        cmp #85
        bcc .wy9
        sbc #84
        rts
.wyu    clc
        adc #84
.wy9    rts

; X = missile owner
FlyMissile:
        lda mlife,x
        beq .fmr
        dec mlife,x
        bne .fm0
.fmr    rts
.fm0    lda weapon
        cmp #1
        bne .fm1
        jsr MisVel              ; guided
.fm1    clc
        lda mxl,x
        adc mvxl,x
        sta mxl,x
        lda mxh,x
        adc mvxh,x
        jsr WrapX
        sta mxh,x
        clc
        lda myl,x
        adc mvyl,x
        sta myl,x
        lda myh,x
        adc mvyh,x
        jsr WrapY
        sta myh,x
        ; hit test against every copy of the other formation, for every
        ; copy of this missile (missiles are copied along with players)
        lda stirT
        bne .fmr
        stx curT
        ldy form
        lda FF0,y
        cpx #0
        beq .fm2
        lda FF1,y
.fm2    sta tmp                 ; own side code
        lda FF1,y
        cpx #0
        beq .fm3
        lda FF0,y
.fm3    sta tmp+1               ; target side code
        txa
        eor #1
        tay                     ; target plane
        lda myh,x               ; vertical test first (all 8 rows)
        sec
        sbc tyh,y
        cmp #8
        bcs .fmr
        lda mxh,x
        sec
        sbc txh,y
        sta tmp+2               ; missile x - target x
        ldx tmp
        lda CopyN,x
        sta tmp+3
        txa
        asl
        asl
        sta tmp                 ; own copy offset index
.mc     ldx tmp
        lda tmp+2
        clc
        adc CopyOff,x
        sta tmp+4               ; this missile copy - target leader
        ldx tmp+1
        lda CopyN,x
        sta tmp+5
        txa
        asl
        asl
        tax
.tc     lda tmp+4
        sec
        sbc CopyOff,x
        stx tvyl                ; keep the copy index
        ldx tmp+1
        cmp CopyW,x
        ldx tvyl
        bcc .fhit
        inx
        dec tmp+5
        bne .tc
        inc tmp
        dec tmp+3
        bne .mc
        ldx curT
.fm9    rts
.fhit   ldx curT
        txa
        eor #1
        tay
        jmp FHit

; X = owner, Y = victim
FHit:   lda #0
        sta mlife
        sta mlife+1
        sty stirWho
        sed
        lda score,x
        clc
        adc #1
        sta score,x
        cld
        lda #STIR_TIME
        sta stirT
        lda #12
        sta flash
        ldx stirWho
        lda #SND_BOOM
        sta snd,x
        lda #1
        sta sndT,x
        rts

; the hit plane spins and drops a little
FStir:  dec stirT
        bne .fs1
        lda stirWho             ; round over: check for a winner
        eor #1
        tax
        lda score,x
        cmp #WIN_SCORE
        bcc .fs9
        stx winner
        lda #ST_OVER
        sta state
        lda #0
        sta snd+1
        lda #SND_FANFARE
        sta snd
        lda #1
        sta sndT
.fs9    rts
.fs1    ldx stirWho
        lda stirT
        and #3
        bne .fs9
        lda tdir,x
        clc
        adc #1
        and #15
        sta tdir,x
        lda tyh,x
        sec
        sbc #1
        jsr WrapY
        sta tyh,x
        rts

; overscan, when a plane round starts: sky into Superchip RAM, positions
FlightReset:
        lda #0
        sta SCW+SC_FLR
        ldy #62
        ldx arena
        cpx #8
        bne .fr2
.fr1    lda CloudMap,y
        sta SCW+SC_PF0,y
        dey
        bpl .fr1
        bmi .fr4
.fr2    sta SCW+SC_PF0,y
        dey
        bpl .fr2
.fr4    ldx #1
        lda #0
.fr3    sta txl,x
        sta tyl,x
        sta mlife,x
        sta tturn,x
        sta joy,x
        sta pu,x
        sta vis,x
        dex
        bpl .fr3
        sta tdir
        lda #8
        sta tdir+1
        sta txh
        lda #62
        sta tyh
        lda #20
        sta tyh+1
        ldy form
        ldx FF1,y
        lda FStartX,x
        sta txh+1
        rts

; CPU pilot (overscan): head for the player across the wrapping screen
FlightAI:
        lda #0
        sta aiJoy
        lda state
        cmp #ST_PLAY
        bne .far
        lda players
        bne .far
        lda stirT
        beq .fa0
.far    rts
.fa0    lda txh
        sec
        sbc txh+1
        ldy #0
        bcs .fx1
        eor #$FF
        adc #1
        iny
.fx1    cmp #80
        bcc .fx2
        eor #$FF
        sec
        adc #160
        pha
        tya
        eor #1
        tay
        pla
.fx2    sta aiAX
        sty aiSX
        lda tyh
        sec
        sbc tyh+1
        ldy #0
        bcs .fy1
        eor #$FF
        adc #1
        iny
.fy1    cmp #42
        bcc .fy2
        eor #$FF
        sec
        adc #84
        pha
        tya
        eor #1
        tay
        pla
.fy2    sty aiSY
        sta aiRY
        lsr
        lsr
        clc
        adc aiRY
        sta aiAY
        jsr Bearing
        sta aiWant
        and #3                  ; along an axis but off the line:
        bne .nocor              ; angle one step toward it
        jsr OnLine
        bcs .nocor
        lda aiWant
        lsr
        lsr
        tay
        and #1
        eor #1
        tax
        lda aiSX,x              ; horizontal: aiSY (above/below), vertical: aiSX
        tax
        lda CorrTbl,y
        cpx #0
        beq .cr1
        eor #$FE                ; +1 <-> -1
.cr1    clc
        adc aiWant
        jmp .steer
.nocor  lda aiWant
.steer  sec
        sbc tdir+1
        and #15
        beq .fst
        cmp #8
        lda #$04
        bcc .fs0
        lda #$08
.fs0    sta aiJoy
.fst    ; speed: full unless close
        lda aiAX
        clc
        adc aiAY
        sta tmp+4
        cmp #24
        bcc .fsp1
        lda aiJoy
        ora #$01
        sta aiJoy
        bne .fire
.fsp1   lda aiJoy
        ora #$02
        sta aiJoy
.fire   lda mlife+1
        bne .fa9
        ldx #90
        lda weapon
        cmp #3
        bne .fr0
        ldx #48                 ; machine gun: get close first
.fr0    stx tmp+3
        lda tmp+4
        cmp tmp+3
        bcs .fa9
        lda tdir+1
        cmp aiWant
        bne .fa9
        and #3
        bne .fdg
        jsr OnLine
        bcc .fa9
        bcs .fez
.fdg    cmp #2                  ; diagonal: |dx - dy| small
        bne .fez
        lda aiAX
        sec
        sbc aiAY
        bcs .fd1
        eor #$FF
        adc #1
.fd1    cmp #10
        bcs .fa9
.fez    bit SWCHB               ; easy CPU hesitates
        bmi .fok
        lda rand
        and #3
        bne .fa9
.fok    lda aiJoy
        ora #$80
        sta aiJoy
.fa9    rts

; carry set when the target is close enough to the axis line of aiWant
OnLine: lda aiWant
        and #4
        bne .ol1
        lda aiRY                ; horizontal shot: height difference
        cmp #4
        jmp .ol2
.ol1    lda aiAX                ; vertical shot: x difference
        cmp #5
.ol2    bcs .ol0
        sec
        rts
.ol0    clc
        rts
CorrTbl .byte 1, $FF, $FF, 1          ; right, up, left, down

; aiAX, aiAY (aspect-corrected), aiSX, aiSY -> heading 0..15 in A
Bearing:
        lda aiAX
        sta tmp
        lda aiAY
        sta tmp+1
.br     lda tmp
        cmp #32
        bcs .bs
        lda tmp+1
        cmp #32
        bcc .bc
.bs     lsr tmp
        lsr tmp+1
        jmp .br
.bc     lda tmp
        asl
        sta tmp+2
        clc
        adc tmp
        sta tmp+3
        ldx #0
        lda tmp+1
        asl
        asl
        clc
        adc tmp+1
        cmp tmp
        bcc .bt
        inx
        lda tmp+1
        asl
        clc
        adc tmp+1
        cmp tmp+2
        bcc .bt
        inx
        lda tmp+1
        asl
        cmp tmp+3
        bcc .bt
        inx
        lda tmp
        asl
        asl
        clc
        adc tmp
        cmp tmp+1
        beq .b4
        bcs .bt
.b4     inx
.bt     stx tmp
        lda aiSX
        beq .bq1
        lda aiSY
        bne .bq3
        lda #8
        sec
        sbc tmp
        jmp .bqd
.bq3    lda #8
        clc
        adc tmp
        jmp .bqd
.bq1    lda aiSY
        beq .bq0
        lda #16
        sec
        sbc tmp
        jmp .bqd
.bq0    lda tmp
.bqd    and #15
        rts

FF0     .byte 0, 1, 0, 3                ; formation side codes (bank 2 copy)
FF1     .byte 0, 1, 2, 2
CopyN   .byte 1, 2, 3, 1
CopyOff .byte 0, 0, 0, 0,  0, 16, 0, 0,  0, 16, 32, 0,  0, 0, 0, 0
CopyW   .byte 7, 7, 7, 31
FStartX .byte 136, 120, 104
FTurn   .byte 5, 8                      ; biplane, jet

; overscan work for plane games (called from bank 1's EndFrame)
FlightOS:
        lda SCR+SC_FLR
        beq .os1
        jmp FlightReset
.os1    lda state               ; plane missiles move in overscan
        cmp #ST_PLAY
        bne .os2
        ldx #0
        jsr FlyMissile
        ldx #1
        jsr FlyMissile
.os2    jmp FlightAI


        include bank2_data.inc

Bank2End
        echo "bank 2 free:", $FFC0-Bank2End

        org $2FC3
        rorg $FFC3
        jsr FlightOS
        sta $1FF7               ; back to bank 1, which returns at $FFC9
        org $2FD3
        rorg $FFD3
        jsr FlightLogic
        sta $1FF6               ; back to bank 0, which returns at $FFD9
        org $2FF0
        rorg $FFF0
        sta $1FF6
        org $2FFA
        rorg $FFFA
        .word $FFF0, $FFF0, $FFF0

; ====================================================================
; BANK 3 - free for new features
; ====================================================================
        org $3000
        rorg $F000
        ds 256, $FF             ; Superchip RAM window
        org $3100
        rorg $F100
Bank3Start
        echo "bank 3 free:", $FFF0-Bank3Start

        org $3FF0
        rorg $FFF0
        sta $1FF6
        org $3FFA
        rorg $FFFA
        .word $FFF0, $FFF0, $FFF0
