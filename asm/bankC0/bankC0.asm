arch snes.cpu
hirom
incsrc "../hardware.inc"

; ============================================================
; Bank $C0 — Engine Core / Main Game Loop
; File offset 0x000000 (bank $C0 maps directly to ROM start)
;
; CPU state on entry from MainInit ($FD:C000):
;   native mode, M=1 (A 8-bit), X=0 (X/Y 16-bit)
;   DP=$2100, DB=$00, S=$06FF
; ============================================================

; ============================================================
; $C0:B309 — Sub_B309 (1016 bytes, $B309–$B700)
; Sprite descriptor → OAM buffer + WRAM palette copy.
; Called from PostVBlank's sprite loop for each active descriptor.
; Dispatches on sprite type (bits 0-1 of $1201,X):
;   type 0 = 1 tile  (1 OAM byte,  ADC #$0010, 4  palette iters)
;   type 1 = 2 tiles (2 OAM bytes, ADC #$0020, 8  palette iters)
;   type 2 = 3 tiles (3 OAM bytes, ADC #$0030, 12 palette iters)
;   type 3+ = 6 tiles (6 OAM bytes, ADC #$0060, 24 palette iters)
; Each type has 3 range paths (flag bits 2-3 of $0F80,X) selecting
;   OAM write-head ($0181/$0185/$0189) and WRAM dest ($01DB/$01DD/$01DF).
; On entry: M=1, X=0 (16-bit), DP=$0100, $6D = sprite descriptor index.
; Sets DP=$2100 internally (PPU register aliasing trick), restores via PLD.
; ============================================================
org $C0B309
Sub_B309:
    JSR Sub_B701            ; sprite state gate; C=0 proceed, C=1 skip
    BCC .proceed
    RTS
.proceed:
    LDX $6D                 ; sprite descriptor index
    LDA $1201,X             ; sprite type byte
    AND #$03                ; isolate type 0-3
    BEQ .type0              ; type 0 → $B329
    CMP #$01
    BNE .chk_t2
    BRL .type1              ; type 1 → $B3DF
.chk_t2:
    CMP #$02
    BNE .type3plus_jmp
    BRL .type2              ; type 2 → $B4B8
.type3plus_jmp:
    BRL .type3plus          ; type 3+ → $B5AF

; ============================================================
; TYPE 0 — 1 OAM byte per range, ADC #$0010, palette loop ×4
; ============================================================
.type0:                     ; $B329
    LDX $6D
    PHD
    REP #$20                ; A → 16-bit
    LDA #$2100
    TCD                     ; DP = $2100 (PPU register alias base)
    SEP #$20                ; A → 8-bit
    LDA $0F80,X             ; sprite flags (abs,X since DP≠$0100)
    AND #$0C                ; range selection bits 2-3
    BEQ .t0r1               ; no bits → range 1
    BIT #$04                ; test bit 2
    BNE .t0r2               ; bit 2 → range 2
    BRA .t0r3               ; bit 3 only → range 3

.t0r1:                      ; $B341 — range 1 ($0181 / $01DB)
    LDA.l $7F4F00,X
    LDX $0181
    STA.w $0000,X           ; .w: abs,X not dp,X
    INX
    STX $0181
    LDX $01DB
    STX $81                 ; DP+$81 = $2181 = WMADDL/H (16-bit X write)
    LDX $016D               ; abs: sprite index (DP=$2100, not $0100)
    REP #$20
    LDA $01DB
    CLC
    ADC #$0010
    STA $01DB
.t0_gfx:                    ; $B363 — shared sprite-gfx + palette loop (type 0)
    LDA $1700,X             ; sprite gfx table index (16-bit, M=0)
    TAX
    SEP #$20
    LDA #$04
    STA $01C9               ; palette loop counter
.t0_pal:                    ; $B36E
    LDA.l $7F4BC0,X
    STA $80                 ; DP+$80 = $2180 = WMDATA (auto-increments WRAM addr)
    LDA.l $7F4BC1,X
    STA $80
    LDA.l $7F4BC6,X
    STA $80
    LDA.l $7F4BC7,X
    STA $80
    REP #$20
    TXA
    CLC
    ADC #$0008
    TAX
    SEP #$20
    DEC $01C9
    BNE .t0_pal
    PLD
    RTS

.t0r2:                      ; $B397 — range 2 ($0185 / $01DD)
    LDA.l $7F4F00,X
    LDX $0185
    STA.w $0000,X
    INX
    STX $0185
    LDX $01DD
    STX $81
    LDX $016D
    REP #$20
    LDA $01DD
    CLC
    ADC #$0010
    STA $01DD
    BRA .t0_gfx

.t0r3:                      ; $B3BB — range 3 ($0189 / $01DF)
    LDA.l $7F4F00,X
    LDX $0189
    STA.w $0000,X
    INX
    STX $0189
    LDX $01DF
    STX $81
    LDX $016D
    REP #$20
    LDA $01DF
    CLC
    ADC #$0010
    STA $01DF
    BRA .t0_gfx

; ============================================================
; TYPE 1 — 2 OAM bytes per range (PHA/PLA), ADC #$0020, ×8
; ============================================================
.type1:                     ; $B3DF
    LDX $6D
    PHD
    REP #$20
    LDA #$2100
    TCD
    SEP #$20
    LDA $0F80,X
    AND #$0C
    BEQ .t1r1
    BIT #$04
    BNE .t1r2_tramp         ; bit 2: conditional long branch via trampoline
    BRL .t1r3               ; bit 3 only → long branch to range 3
.t1r2_tramp:
    BRL .t1r2               ; trampoline: range 2

.t1r1:                      ; $B3FB — range 1 ($0181 / $01DB)
    LDA.l $7F4F01,X
    PHA
    LDA.l $7F4F00,X
    LDX $0181
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    STX $0181
    LDX $01DB
    STX $81
    LDX $016D
    REP #$20
    LDA $01DB
    CLC
    ADC #$0020
    STA $01DB
.t1_gfx:                    ; shared gfx+palette loop (type 1)
    LDA $1700,X
    TAX
    SEP #$20
    LDA #$08
    STA $01C9
.t1_pal:
    LDA.l $7F4BC0,X
    STA $80
    LDA.l $7F4BC1,X
    STA $80
    LDA.l $7F4BC6,X
    STA $80
    LDA.l $7F4BC7,X
    STA $80
    REP #$20
    TXA
    CLC
    ADC #$0008
    TAX
    SEP #$20
    DEC $01C9
    BNE .t1_pal
    PLD
    RTS

.t1r3:                      ; $B45B — range 3 ($0189 / $01DF)
    LDA.l $7F4F01,X
    PHA
    LDA.l $7F4F00,X
    LDX $0189
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    STX $0189
    LDX $01DF
    STX $81
    LDX $016D
    REP #$20
    LDA $01DF
    CLC
    ADC #$0020
    STA $01DF
    BRA .t1_gfx             ; within BRA range (-98)

.t1r2:                      ; $B489 — range 2 ($0185 / $01DD)
    LDA.l $7F4F01,X
    PHA
    LDA.l $7F4F00,X
    LDX $0185
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    STX $0185
    LDX $01DD
    STX $81
    LDX $016D
    REP #$20
    LDA $01DD
    CLC
    ADC #$0020
    STA $01DD
    BRL .t1_gfx             ; too far for BRA (-145)

; ============================================================
; TYPE 2 — 3 OAM bytes per range (2×PHA/PLA), ADC #$0030, ×12
; ============================================================
.type2:                     ; $B4B8
    LDX $6D
    PHD
    REP #$20
    LDA #$2100
    TCD
    SEP #$20
    LDA $0F80,X
    AND #$0C
    BEQ .t2r1
    BIT #$04
    BNE .t2r2_tramp
    BRL .t2r3
.t2r2_tramp:
    BRL .t2r2

.t2r1:                      ; range 1 ($0181 / $01DB)
    LDA.l $7F4B40,X
    PHA
    LDA.l $7F4F01,X
    PHA
    LDA.l $7F4F00,X
    LDX $0181
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    STX $0181
    LDX $01DB
    STX $81
    LDX $016D
    REP #$20
    LDA $01DB
    CLC
    ADC #$0030
    STA $01DB
.t2_gfx:                    ; shared gfx+palette loop (type 2)
    LDA $1700,X
    TAX
    SEP #$20
    LDA #$0C
    STA $01C9
.t2_pal:
    LDA.l $7F4BC0,X
    STA $80
    LDA.l $7F4BC1,X
    STA $80
    LDA.l $7F4BC6,X
    STA $80
    LDA.l $7F4BC7,X
    STA $80
    REP #$20
    TXA
    CLC
    ADC #$0008
    TAX
    SEP #$20
    DEC $01C9
    BNE .t2_pal
    PLD
    RTS

.t2r3:                      ; range 3 ($0189 / $01DF)
    LDA.l $7F4B40,X
    PHA
    LDA.l $7F4F01,X
    PHA
    LDA.l $7F4F00,X
    LDX $0189
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    STX $0189
    LDX $01DF
    STX $81
    LDX $016D
    REP #$20
    LDA $01DF
    CLC
    ADC #$0030
    STA $01DF
    BRA .t2_gfx             ; within BRA range (-108)

.t2r2:                      ; range 2 ($0185 / $01DD)
    LDA.l $7F4B40,X
    PHA
    LDA.l $7F4F01,X
    PHA
    LDA.l $7F4F00,X
    LDX $0185
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    STX $0185
    LDX $01DD
    STX $81
    LDX $016D
    REP #$20
    LDA $01DD
    CLC
    ADC #$0030
    STA $01DD
    BRL .t2_gfx             ; too far for BRA (-165)

; ============================================================
; TYPE 3+ — 6 OAM bytes per range (5×PHA/PLA), ADC #$0060, ×24
; ============================================================
.type3plus:                 ; $B5AF
    LDX $6D
    PHD
    REP #$20
    LDA #$2100
    TCD
    SEP #$20
    LDA $0F80,X
    AND #$0C
    BEQ .t3r1
    BIT #$04
    BNE .t3r2_tramp
    BRL .t3r3
.t3r2_tramp:
    BRL .t3r2

.t3r1:                      ; range 1 ($0181 / $01DB)
    LDA.l $7F4F81,X
    PHA
    LDA.l $7F4F80,X
    PHA
    LDA.l $7F4B41,X
    PHA
    LDA.l $7F4B40,X
    PHA
    LDA.l $7F4F01,X
    PHA
    LDA.l $7F4F00,X
    LDX $0181
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    STX $0181
    LDX $01DB
    STX $81
    LDX $016D
    REP #$20
    LDA $01DB
    CLC
    ADC #$0060
    STA $01DB
.t3_gfx:                    ; shared gfx+palette loop (type 3+)
    LDA $1700,X
    TAX
    SEP #$20
    LDA #$18
    STA $01C9
.t3_pal:
    LDA.l $7F4BC0,X
    STA $80
    LDA.l $7F4BC1,X
    STA $80
    LDA.l $7F4BC6,X
    STA $80
    LDA.l $7F4BC7,X
    STA $80
    REP #$20
    TXA
    CLC
    ADC #$0008
    TAX
    SEP #$20
    DEC $01C9
    BNE .t3_pal
    PLD
    RTS

.t3r3:                      ; range 3 ($0189 / $01DF)
    LDA.l $7F4F81,X
    PHA
    LDA.l $7F4F80,X
    PHA
    LDA.l $7F4B41,X
    PHA
    LDA.l $7F4B40,X
    PHA
    LDA.l $7F4F01,X
    PHA
    LDA.l $7F4F00,X
    LDX $0189
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    STX $0189
    LDX $01DF
    STX $81
    LDX $016D
    REP #$20
    LDA $01DF
    CLC
    ADC #$0060
    STA $01DF
    BRL .t3_gfx             ; -226, must use BRL

.t3r2:                      ; range 2 ($0185 / $01DD)
    LDA.l $7F4F81,X
    PHA
    LDA.l $7F4F80,X
    PHA
    LDA.l $7F4B41,X
    PHA
    LDA.l $7F4B40,X
    PHA
    LDA.l $7F4F01,X
    PHA
    LDA.l $7F4F00,X
    LDX $0185
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    PLA
    STA.w $0000,X
    INX
    STX $0185
    LDX $01DD
    STX $81
    LDX $016D
    REP #$20
    LDA $01DD
    CLC
    ADC #$0060
    STA $01DD
    BRL .t3_gfx             ; -139, must use BRL


; ============================================================
; $C0:B701 — Sub_B701 (171 bytes, $B701–$B7AB)
; Sprite state gate called from Sub_B309.
; Returns C=0 (proceed to render), C=1 (skip).
; Sub_B788 at $B788 is a secondary entry used by the type 0 negative path.
; ============================================================
org $C0B701
Sub_B701:
    LDX $6D
    LDA $1201,X
    AND #$03
    BEQ .t0
    CMP #$01
    BNE .chk2
    BRA .t1
.chk2:
    CMP #$02
    BNE .t3plus
    BRA .t2

.t0:
    LDA $1B00,X
    BNE .t0_nz
    SEC
    RTS
.t0_nz:
    BMI .t0_neg
.t0_init:
    JSR Sub_B8CA
    JSR Sub_E9E2
    LDX $6D
    LDA #$80
    STA $1B00,X
    CLC
    RTS
.t0_neg:
    AND #$7F
    BNE .t0_init
    JSR Sub_B788
    CLC
    RTS

.t1:
    LDA $1B00,X
    BNE .t1_nz
.t1_abort:
    SEC
    RTS
.t1_nz:
    BMI .t1_neg
    CMP #$02
    BCC .t1_abort
.t1_init:
    JSR Sub_BCDC
    JSR Sub_E9FF
    LDX $6D
    LDA #$80
    STA $1B00,X
    CLC
    RTS
.t1_neg:
    AND #$7F
    CMP #$02
    BCS .t1_init
    JSR Sub_BA65
    CLC
    RTS

.t2:
    LDA $1B00,X
    BNE .t2_nz
.t2_abort:
    SEC
    RTS
.t2_nz:
    BMI .t2_neg
    CMP #$03
    BCC .t2_abort
.t2_init:
    JSR Sub_C2BF
    JSR Sub_EA1F
    LDX $6D
    LDA #$80
    STA $1B00,X
    CLC
    RTS
.t2_neg:
    AND #$7F
    CMP #$03
    BCS .t2_init
    JSR Sub_BFF2
    CLC
    RTS

.t3plus:
    BRL Sub_C73A            ; type 3+ delegates to full renderer at $C73A

org $C0B788
Sub_B788:
    PHB
    LDA #$7F
    PHA
    PLB                     ; DB = $7F — bank $7F staging data now addressable via abs
    REP #$20                ; M→0 (16-bit A)
    LDA.l $000A80,X         ; 9-bit X/flip flags (long: DB=$7F doesn't reach bank $00)
    AND #$01FF
    STA $C5                 ; dp: C5=lo byte, C6=hi bit (bit 8 of 9-bit value)
    LDA.l $000A00,X         ; base X coordinate
    STA $C3                 ; dp: C3=lo, C4=hi
    STZ $E5
    LDA.l $001700,X         ; sprite gfx index (16-bit)
    STA $D9                 ; dp: D9=lo, DA=hi
    CLC
    ADC #$0018              ; start loop at gfx_index + $18 (3 tiles above base)
.b788_loop:
    TAX
    LDA.w $4BC2,X           ; raw X offset from pre-built table
    CLC
    ADC $C3                 ; add base X
    SEP #$20                ; M→1 (8-bit A)
    STA.w $4BC0,X           ; write X position low byte
    XBA                     ; get high byte (bit 8 of sum = X overflow bit)
    AND #$01
    STA $E6
    LDA $E5
    ASL A
    ASL A
    ORA $E6                 ; pack flip/overflow bits
    CPX $D9                 ; reached base gfx index?
    BEQ .b788_post
    STA $E5
    REP #$20                ; M→0
    TXA
    SEC
    SBC #$0008              ; step back one tile
    BRA .b788_loop
.b788_post:
    ORA #$AA                ; set high attribute bits
    LDX $6D                 ; sprite descriptor index
    STA.w $4F00,X           ; write to OAM slot
    LDX $D9                 ; restore gfx base index
    LDA $C6                 ; check bit 8 of position
    BEQ .b788_no_c6         ; = 0: dispatch on C5 sign
    ; C6 != 0: 5-tile Y-clamp (BCC→clamp, BCS→keep)
    LDA.w $4BC4,X
    CLC
    ADC $C5
    BCC .b788_c6_cl1
    CMP #$E0
    BCS .b788_c6_st1
.b788_c6_cl1:
    LDA #$E0
.b788_c6_st1:
    STA.w $4BC1,X
    LDA.w $4BCC,X
    CLC
    ADC $C5
    BCC .b788_c6_cl2
    CMP #$E0
    BCS .b788_c6_st2
.b788_c6_cl2:
    LDA #$E0
.b788_c6_st2:
    STA.w $4BC9,X
    LDA.w $4BD4,X
    CLC
    ADC $C5
    BCC .b788_c6_cl3
    CMP #$E0
    BCS .b788_c6_st3
.b788_c6_cl3:
    LDA #$E0
.b788_c6_st3:
    STA.w $4BD1,X
    LDA.w $4BDC,X
    CLC
    ADC $C5
    BCC .b788_c6_cl4
    CMP #$E0
    BCS .b788_c6_st4
.b788_c6_cl4:
    LDA #$E0
.b788_c6_st4:
    STA.w $4BD9,X
    LDA.w $4BE4,X
    CLC
    ADC $C5
    BCC .b788_c6_cl5
    CMP #$E0
    BCS .b788_c6_st5
.b788_c6_cl5:
    LDA #$E0
.b788_c6_st5:
    STA.w $4BE1,X
    SEP #$20
    PLB
    RTS
.b788_no_c6:
    LDA $C5
    BPL .b788_pos_c5        ; C5 bit 7 = 0: positive path
    ; negative C5: 4-tile Y-clamp (BCC+BCC→keep, else clamp)
    LDA.w $4BC4,X
    CLC
    ADC $C5
    BCC .b788_n1
    CMP #$E0
    BCC .b788_n1
    LDA #$E0
.b788_n1:
    STA.w $4BC1,X
    LDA.w $4BCC,X
    CLC
    ADC $C5
    BCC .b788_n2
    CMP #$E0
    BCC .b788_n2
    LDA #$E0
.b788_n2:
    STA.w $4BC9,X
    LDA.w $4BD4,X
    CLC
    ADC $C5
    BCC .b788_n3
    CMP #$E0
    BCC .b788_n3
    LDA #$E0
.b788_n3:
    STA.w $4BD1,X
    LDA.w $4BDC,X
    CLC
    ADC $C5
    BCC .b788_n4
    CMP #$E0
    BCC .b788_n4
    LDA #$E0
.b788_n4:
    STA.w $4BD9,X
    SEP #$20
    PLB
    RTS
.b788_pos_c5:
    ; positive C5: 4-tile Y-clamp (BPL+BCS→keep, else clamp)
    LDA.w $4BC4,X
    CLC
    ADC $C5
    BPL .b788_p1
    CMP #$E0
    BCS .b788_p1
    LDA #$E0
.b788_p1:
    STA.w $4BC1,X
    LDA.w $4BCC,X
    CLC
    ADC $C5
    BPL .b788_p2
    CMP #$E0
    BCS .b788_p2
    LDA #$E0
.b788_p2:
    STA.w $4BC9,X
    LDA.w $4BD4,X
    CLC
    ADC $C5
    BPL .b788_p3
    CMP #$E0
    BCS .b788_p3
    LDA #$E0
.b788_p3:
    STA.w $4BD1,X
    LDA.w $4BDC,X
    CLC
    ADC $C5
    BPL .b788_p4
    CMP #$E0
    BCS .b788_p4
    LDA #$E0
.b788_p4:
    STA.w $4BD9,X
    SEP #$20
    PLB
    RTS

org $C0C6E7
Sub_C6E7:
    ; Called from Sub_C73A 6 times, X = gfx index for current 4-tile group.
    ; Computes X positions for 4 sprite tiles from $4BC2/CA/D2/DA into $4BC0/C8/D0/D8,
    ; packs their X-overflow bits, and returns the OAM high-table byte in A.
    ; Entry: M=0 (16-bit A), X = gfx index.  Exit: M=1, A = packed OAM attr byte.
    LDA.w $4BC2,X
    CLC
    ADC $C3                 ; add base X (16-bit)
    SEP #$20                ; M→1
    STA.w $4BC0,X           ; store tile 0 X low byte
    XBA
    AND #$01
    STA $E5                 ; tile 0 X overflow bit

    REP #$20                ; M→0
    LDA.w $4BCA,X
    CLC
    ADC $C3
    SEP #$20
    STA.w $4BC8,X
    XBA
    AND #$01
    STA $E6                 ; tile 1 X overflow bit

    REP #$20
    LDA.w $4BD2,X
    CLC
    ADC $C3
    SEP #$20
    STA.w $4BD0,X
    XBA
    AND #$01
    STA $E7                 ; tile 2 X overflow bit

    REP #$20
    LDA.w $4BDA,X
    CLC
    ADC $C3
    SEP #$20
    STA.w $4BD8,X
    XBA
    AND #$01                ; tile 3 X overflow bit in A[0]
    ASL A
    ASL A
    ORA $E7                 ; pack: (bit3<<2) | bit2
    ASL A
    ASL A
    ORA $E6                 ; pack: (bit3<<4) | (bit2<<2) | bit1
    ASL A
    ASL A
    ORA $E5                 ; pack: (bit3<<6) | (bit2<<4) | (bit1<<2) | bit0
    ORA #$AA                ; set size bits (SNES OAM: bit pairs = [xhi, size])
    RTS

org $C0C73A
Sub_C73A:
    ; 592 bytes ($C73A-$C989). Entry M=1, X=1 (from Sub_B701 type-3+ BRL).
    ; DB=$7F prologue, 6× JSR Sub_C6E7 for OAM X-bits, then 3-way 24-tile Y-clamp.

    ; ── Prologue: DB=$7F ────────────────────────────────────────────────────────
    PHB
    LDA #$7F
    PHA
    PLB                         ; DB=$7F

    ; ── Load sprite params ───────────────────────────────────────────────────────
    REP #$20                    ; M→0
    LDX $6D                     ; sprite/OAM slot index (8-bit X)
    LDA.l $000A80,X             ; 9-bit Y position value
    AND #$01FF
    STA $C5                     ; C5=lo byte, C6=hi bit (bit 8)
    LDA.l $000A00,X             ; base X coordinate
    STA $C3
    LDA.l $001700,X             ; gfx index
    TAX                         ; X = gfx_index (8-bit capture)

    ; ── 6× JSR Sub_C6E7 ─────────────────────────────────────────────────────────
    ; Each call: entry M=0, X=gfx_index; exit M=1, A=packed OAM byte.
    ; After each call (except last): save X, load OAM slot, write OAM byte,
    ;   restore X, REP, TXA+ADC #$20+TAX to advance gfx_index by $20.
    JSR Sub_C6E7                ; call 1 — gfx_index
    STX $D9
    LDX $6D
    STA.w $4F00,X
    LDX $D9
    REP #$20
    TXA
    CLC
    ADC #$0020
    TAX
    JSR Sub_C6E7                ; call 2 — gfx_index+$20
    STX $D9
    LDX $6D
    STA.w $4F01,X
    LDX $D9
    REP #$20
    TXA
    CLC
    ADC #$0020
    TAX
    JSR Sub_C6E7                ; call 3 — gfx_index+$40
    STX $D9
    LDX $6D
    STA.w $4B40,X
    LDX $D9
    REP #$20
    TXA
    CLC
    ADC #$0020
    TAX
    JSR Sub_C6E7                ; call 4 — gfx_index+$60
    STX $D9
    LDX $6D
    STA.w $4B41,X
    LDX $D9
    REP #$20
    TXA
    CLC
    ADC #$0020
    TAX
    JSR Sub_C6E7                ; call 5 — gfx_index+$80
    STX $D9
    LDX $6D
    STA.w $4F80,X
    LDX $D9
    REP #$20
    TXA
    CLC
    ADC #$0020
    TAX
    JSR Sub_C6E7                ; call 6 — gfx_index+$A0
    STX $D9
    LDX $6D
    STA.w $4F81,X
    LDX $6D                     ; reload OAM slot (not $D9) for gfx_index lookup
    REP #$20
    LDA.l $001700,X             ; reload original gfx_index for Y-clamp pass
    TAX
    SEP #$20                    ; M→1

    ; ── Y-position 3-way dispatch ────────────────────────────────────────────────
    LDA $C6
    BEQ .c73a_chk_c5            ; C6=0: check C5 next
    BRL .c73a_c6nz                   ; C6≠0: → .c73a_c6nz
.c73a_chk_c5:
    LDA $C5
    BMI .c73a_large_c5          ; C5≥$80: no-clamp path
    BRL .c73a_small_c5                   ; C5<$80: clamp path → .c73a_small_c5

    ; ── C6=0, C5≥$80: 24-tile add with no clamping ───────────────────────────────
.c73a_large_c5:
    LDA #$18
    STA $C9                     ; counter = 24
.c73a_large_loop:
    LDA.w $4BC4,X
    CLC
    ADC $C5
    STA.w $4BC1,X               ; store Y (no clamp; overflow wraps)
    REP #$20
    TXA
    CLC
    ADC #$0008
    TAX
    SEP #$20
    DEC $C9
    BNE .c73a_large_loop
    PLB
    RTS

    ; ── C6=0, C5<$80: 24-tile add, clamp $80–$DF to $E0 ─────────────────────────
.c73a_small_c5:
    LDA #$18
    STA $C9
.c73a_small_loop:
    LDA.w $4BC4,X
    CLC
    ADC $C5
    BPL .c73a_small_store       ; 0–$7F: store as-is
    CMP #$E0
    BCS .c73a_small_store       ; $E0–$FF: already off-screen, store as-is
    LDA #$E0                    ; $80–$DF: clamp to $E0
.c73a_small_store:
    STA.w $4BC1,X
    REP #$20
    TXA
    CLC
    ADC #$0008
    TAX
    SEP #$20
    DEC $C9
    BNE .c73a_small_loop
    PLB
    RTS

    ; ── C6≠0: unrolled 24-tile Y-clamp (BCS→clamp, BMI→clamp, else store) ────────
    ; Clamp fires if: sum overflows (BCS) or result is $80–$FF with no overflow (BMI).
    ; Only 0–$7F passes through unclamped.
.c73a_c6nz:
    LDA.w $4BC4,X
    CLC
    ADC $C5
    BCS .c73a_cl00
    BPL .c73a_st00
.c73a_cl00: LDA #$E0
.c73a_st00: STA.w $4BC1,X
    LDA.w $4BCC,X
    CLC
    ADC $C5
    BCS .c73a_cl01
    BPL .c73a_st01
.c73a_cl01: LDA #$E0
.c73a_st01: STA.w $4BC9,X
    LDA.w $4BD4,X
    CLC
    ADC $C5
    BCS .c73a_cl02
    BPL .c73a_st02
.c73a_cl02: LDA #$E0
.c73a_st02: STA.w $4BD1,X
    LDA.w $4BDC,X
    CLC
    ADC $C5
    BCS .c73a_cl03
    BPL .c73a_st03
.c73a_cl03: LDA #$E0
.c73a_st03: STA.w $4BD9,X
    LDA.w $4BE4,X
    CLC
    ADC $C5
    BCS .c73a_cl04
    BPL .c73a_st04
.c73a_cl04: LDA #$E0
.c73a_st04: STA.w $4BE1,X
    LDA.w $4BEC,X
    CLC
    ADC $C5
    BCS .c73a_cl05
    BPL .c73a_st05
.c73a_cl05: LDA #$E0
.c73a_st05: STA.w $4BE9,X
    LDA.w $4BF4,X
    CLC
    ADC $C5
    BCS .c73a_cl06
    BPL .c73a_st06
.c73a_cl06: LDA #$E0
.c73a_st06: STA.w $4BF1,X
    LDA.w $4BFC,X
    CLC
    ADC $C5
    BCS .c73a_cl07
    BPL .c73a_st07
.c73a_cl07: LDA #$E0
.c73a_st07: STA.w $4BF9,X
    LDA.w $4C04,X
    CLC
    ADC $C5
    BCS .c73a_cl08
    BPL .c73a_st08
.c73a_cl08: LDA #$E0
.c73a_st08: STA.w $4C01,X
    LDA.w $4C0C,X
    CLC
    ADC $C5
    BCS .c73a_cl09
    BPL .c73a_st09
.c73a_cl09: LDA #$E0
.c73a_st09: STA.w $4C09,X
    LDA.w $4C14,X
    CLC
    ADC $C5
    BCS .c73a_cl10
    BPL .c73a_st10
.c73a_cl10: LDA #$E0
.c73a_st10: STA.w $4C11,X
    LDA.w $4C1C,X
    CLC
    ADC $C5
    BCS .c73a_cl11
    BPL .c73a_st11
.c73a_cl11: LDA #$E0
.c73a_st11: STA.w $4C19,X
    LDA.w $4C24,X
    CLC
    ADC $C5
    BCS .c73a_cl12
    BPL .c73a_st12
.c73a_cl12: LDA #$E0
.c73a_st12: STA.w $4C21,X
    LDA.w $4C2C,X
    CLC
    ADC $C5
    BCS .c73a_cl13
    BPL .c73a_st13
.c73a_cl13: LDA #$E0
.c73a_st13: STA.w $4C29,X
    LDA.w $4C34,X
    CLC
    ADC $C5
    BCS .c73a_cl14
    BPL .c73a_st14
.c73a_cl14: LDA #$E0
.c73a_st14: STA.w $4C31,X
    LDA.w $4C3C,X
    CLC
    ADC $C5
    BCS .c73a_cl15
    BPL .c73a_st15
.c73a_cl15: LDA #$E0
.c73a_st15: STA.w $4C39,X
    LDA.w $4C44,X
    CLC
    ADC $C5
    BCS .c73a_cl16
    BPL .c73a_st16
.c73a_cl16: LDA #$E0
.c73a_st16: STA.w $4C41,X
    LDA.w $4C4C,X
    CLC
    ADC $C5
    BCS .c73a_cl17
    BPL .c73a_st17
.c73a_cl17: LDA #$E0
.c73a_st17: STA.w $4C49,X
    LDA.w $4C54,X
    CLC
    ADC $C5
    BCS .c73a_cl18
    BPL .c73a_st18
.c73a_cl18: LDA #$E0
.c73a_st18: STA.w $4C51,X
    LDA.w $4C5C,X
    CLC
    ADC $C5
    BCS .c73a_cl19
    BPL .c73a_st19
.c73a_cl19: LDA #$E0
.c73a_st19: STA.w $4C59,X
    LDA.w $4C64,X
    CLC
    ADC $C5
    BCS .c73a_cl20
    BPL .c73a_st20
.c73a_cl20: LDA #$E0
.c73a_st20: STA.w $4C61,X
    LDA.w $4C6C,X
    CLC
    ADC $C5
    BCS .c73a_cl21
    BPL .c73a_st21
.c73a_cl21: LDA #$E0
.c73a_st21: STA.w $4C69,X
    LDA.w $4C74,X
    CLC
    ADC $C5
    BCS .c73a_cl22
    BPL .c73a_st22
.c73a_cl22: LDA #$E0
.c73a_st22: STA.w $4C71,X
    LDA.w $4C7C,X
    CLC
    ADC $C5
    BCS .c73a_cl23
    BPL .c73a_st23
.c73a_cl23: LDA #$E0
.c73a_st23: STA.w $4C79,X
    PLB
    RTS

; ============================================================
; $C0:C98A — Obj_AnimTickAndQueue (236 bytes, $C98A–$CA75)
; Per-frame animation tick and sprite-frame queuer.
; Called once per slot from the main entity loop ($C0:A832, $C0:A878).
; Decrements the per-slot animation timer ($1601,X). When it expires,
; arbitrates which entity slot becomes the primary/secondary "focus"
; (tracked in $76/$77), computes the animation frame-entry address from
; $1580,X + row*4 + column, reads the frame-step byte from bank $E4,
; stores it back as the new timer, and adjusts $1681,X (column counter).
; Entry: M=1 (A 8-bit), X=1 (X/Y 8-bit). $6D = current entity slot.
; Modifies: $76, $77, $78, $C1, $1081,X, $1601,X, $1681,X.
; ============================================================
org $C0C98A
Obj_AnimTickAndQueue:
    LDX $6D               ; current entity slot index
    LDA $1601,X           ; per-slot animation timer
    BEQ .tick_done        ; already zero → execute now
    DEC $1601,X           ; count down
    BEQ .tick_done        ; just expired → execute
.rts:
    RTS                   ; $C996 — timer still running, early exit
.tick_done:               ; $C997
    LDA $1100,X           ; sprite state flags
    BEQ .no_type          ; 0 → slot has no type/owner
    BMI .rts              ; bit7 set → inactive slot, return
    CMP #$01
    BEQ .type_1_or_2      ; type 1
    CMP #$02
    BEQ .type_1_or_2      ; type 2
    CPX $77               ; is this slot already the secondary focus?
    BEQ .rts              ; yes → no change needed
    LDA $77               ; load secondary focus slot index
    BMI .promote_sec      ; negative ($80) = no secondary → promote
    LDA $1081,X           ; shadow field of current slot
    BPL .rts              ; non-negative → slot occupied, skip
.promote_sec:             ; $C9B3
    TXA                   ; A = current slot index
    LDX $77               ; X = current secondary focus slot
    CPX #$80              ; secondary empty ($80)?
    BPL .set_both2        ; yes → A already holds current slot, set both
    STA.w $1081,X         ; link old secondary's shadow → current slot
    STA $77               ; secondary focus = current slot (A)
    TAX                   ; X = current slot
    INC $1681,X           ; advance animation column counter
    BRA .do_anim
.set_both1:               ; $C9C5 — from .no_type when primary is negative
    TXA                   ; A = current slot (X = current, A was primary)
.set_both2:               ; $C9C6 — from .promote_sec / .promote_sec2 when slot empty
    STA $77               ; secondary focus = current slot
    STA $76               ; primary focus = current slot
    TAX                   ; X = current slot
    INC $1681,X
    BRA .do_anim
.no_type:                 ; $C9D0
    CPX $76               ; is this slot already the primary focus?
    BEQ .rts              ; yes → no change
    LDA $76               ; load primary focus slot index
    BMI .set_both1        ; negative → no primary, set this as both
    STA.w $1081,X         ; link primary into current's shadow
    STX $76               ; primary focus = current slot
    INC $1681,X
    BRA .do_anim
.type_1_or_2:             ; $C9E2
    LDA $78               ; tertiary mode flag
    CMP #$02
    BNE .type_sec         ; not 2 → check secondary
    STZ $78               ; reset tertiary mode
    BRA .no_type          ; re-run as type-0 path
.type_sec:                ; $C9EC
    CPX $77               ; is this slot already the secondary focus?
    BEQ .rts              ; yes → no change
    LDA $77
    BMI .promote_sec2     ; negative → no secondary, promote
    LDA $1081,X           ; shadow field
    BPL .rts              ; occupied → skip
.promote_sec2:            ; $C9F9
    TXA
    LDX $77
    CPX #$80
    BPL .set_both2        ; empty secondary → set both (skip TXA)
    STA.w $1081,X
    STA $77
    TAX
    INC $1681,X
.do_anim:                 ; $CA09 — fall-through from .promote_sec2 and BRAs above
    LDX $6D               ; reload entity slot
    LDA $1780,X           ; animation mode byte
    BEQ .use_primary_row  ; mode 0 → use primary row
    DEC                   ; mode - 1
    BEQ .use_primary_row  ; mode 1 → use primary row
    LDA $1781,X           ; mode >= 2 → use secondary row byte
    BRA .got_row
.use_primary_row:         ; $CA18
    LDA $1680,X           ; primary animation row byte
.got_row:                 ; $CA1B
    REP #$20              ; A=16-bit
    AND #$00FF            ; zero high byte
    ASL                   ; row × 2
    ASL                   ; row × 4 (frame row offset)
    CLC
    ADC $1580,X           ; + slot base pointer → frame row address
    STA $C1               ; save frame row address (16-bit)
    LDA $1681,X           ; animation column counter (16-bit)
    AND #$00FF            ; zero high byte
    ADC $C1               ; + frame row = frame-entry address (carry from ADC above)
    REP #$10              ; X=16-bit
    TAX                   ; X = 16-bit frame-entry address
    SEP #$20              ; A=8-bit
    LDA $E40000,X         ; read frame-step byte from bank $E4 sprite table
    BNE .got_frame        ; nonzero → use as timer
    LDX $C1               ; X = frame row base address (16-bit)
    LDA $E40000,X         ; read row-base frame value from bank $E4
    SEP #$10              ; X=8-bit
    LDX $6D               ; reload entity slot
    STA.w $1601,X         ; store row-base byte as new timer
    LDA $1780,X           ; check animation mode
    CMP #$02
    BNE .mode_simple      ; mode != 2 → simple clear and return
    LDA $7F0B01,X         ; long: loop-count byte for this slot ($7F:0B01+X)
    DEC
    BEQ .loop_end         ; hit 0 → decrement column counter
    DEC
    BEQ .loop_one         ; hit 0 (was 2) → bump counter then decrement column
    STA $7F0B01,X         ; store updated loop count
    STZ.w $1681,X         ; reset animation column counter
    RTS
.loop_one:                ; $CA61
    INC
    STA $7F0B01,X
.loop_end:                ; $CA66
    DEC $1681,X           ; decrement animation column counter
    RTS
.mode_simple:             ; $CA6A
    STZ.w $1681,X         ; clear animation column counter
    RTS
.got_frame:               ; $CA6E — A = nonzero frame-step byte, X still 16-bit
    SEP #$10              ; X=8-bit
    LDX $6D               ; reload entity slot
    STA.w $1601,X         ; store frame-step byte as new animation timer
    RTS

; ============================================================
; $C0:CA76 — Field_ProcessAnimQueue (99 bytes, $CA76–$CAD8)
; VBlank-time sprite animation queue processor.
; Called from VBlankHandler ($C0:00BF). Guards against $09A0 being
; nonzero (already processing). Latches the H/V scanline counter and
; checks the current vertical position: exits if too far into the
; active display ($6B ≤ V < $F0). If within the safe window, iterates
; through the focus-slot chain ($76/$77), calling Obj_BuildSpriteFrameStep
; for each slot. When a step completes (carry clear), the slot's
; shadow ($1081,X) is marked invalid ($80) and focus variables are
; updated. Loops back to re-latch V and process the next slot.
; Entry: M=1 (A 8-bit), X=1 (X/Y 8-bit).
; Modifies: $6D, $76, $77, $79, $1081,X. Reads: $09A0, $6B, $213D.
; ============================================================
org $C0CA76
Field_ProcessAnimQueue:
    LDA $09A0             ; animation-queue busy / processed flag
    BEQ .proceed          ; zero → proceed
    RTS                   ; nonzero → already done this frame, exit
.proceed:                 ; $CA7C
    REP #$10              ; X=16-bit (NOP: immediately reset below)
    SEP #$10              ; X=8-bit
    STZ $79               ; clear scratch byte
    LDA $213F             ; STAT78: read PPU status (arms latch)
.latch:                   ; $CA85 — loop re-entry point for each slot step
    LDA $2137             ; SLHV:  software-latch H/V counters
    LDA $213D             ; OPVCT: read vertical counter (low byte)
    XBA                   ; save low byte in B
    LDA $213D             ; OPVCT: read vertical counter (high bit)
    AND #$01              ; keep only bit 0 (9th bit of V)
    XBA                   ; restore low byte (B = high bit)
    REP #$20              ; A=16-bit: A[7:0]=V_low, A[15:8]=V_high_bit
    CMP #$00F0            ; compare with scanline 240 (vblank)
    BPL .in_window        ; V >= 240 → safe window, proceed
    CMP $6B               ; compare with threshold
    BCS .exit_sep         ; V >= $6B → too close to display, exit
.in_window:               ; $CA9D
    LDA #$0000            ; clear A (16-bit zero)
    SEP #$20              ; A=8-bit
    LDA $76               ; primary focus slot index
    BMI .exit_rts         ; negative ($80) = no valid slot, exit
    STA $6D               ; current slot = primary focus
    LDA $76
    CMP $77               ; primary == secondary?
    BEQ .same_slot        ; yes → single-slot path
    JSR Obj_BuildSpriteFrameStep  ; process primary slot step
    BCS .latch            ; carry set → step not complete, re-latch
    LDA $76               ; update primary focus via shadow chain
    TAX
    LDA $1081,X           ; next slot in shadow chain
    STA $76               ; advance primary focus
    LDA #$80
    STA.w $1081,X         ; mark old primary as invalid ($80)
    BRA .latch            ; re-latch and continue
.same_slot:               ; $CAC2 — $76 == $77
    JSR Obj_BuildSpriteFrameStep
    BCS .latch            ; not complete, retry
    LDA $76
    TAX
    LDA #$80
    STA.w $1081,X         ; mark slot invalid
    STA $76               ; primary focus = invalid ($80)
    STA $77               ; secondary focus = invalid ($80)
    BRA .latch            ; re-latch
.exit_rts:                ; $CAD5
    RTS
.exit_sep:                ; $CAD6
    SEP #$20              ; A=8-bit
    RTS

; ============================================================
; $C0:CAD9 — Obj_BuildSpriteFrameStep (49 bytes, $CAD9–$CB09)
; Single sprite-frame build step for the current slot ($6D).
; Validates the slot: skips if $1100,X bit7 set, $1A81,X is zero
; or negative, or $0F00,X is zero. Then dispatches on bits 0-1 of
; $1201,X (sprite type/pass index) to the matching frame-builder:
;   0 → BRL Sub_CBDC (single-slot frame builder)
;   1 → BRL Sub_CEF5 (8-slot frame builder)
;   2 → BRL Sub_D4F7 (12-slot frame builder)
;   3 → CLC + RTS (unrecognised type, no-op)
; Returns carry set if a frame was produced, carry clear otherwise.
; Called by: Field_ProcessAnimQueue ($CA76), map-load pass ($C0:B109).
; Entry: M=1 (A 8-bit), X=1 (X/Y 8-bit). $6D = entity slot.
; ============================================================
org $C0CAD9
Obj_BuildSpriteFrameStep:
    LDX $6D               ; entity slot index
    LDA $1100,X           ; sprite state flags
    BPL .active           ; bit7 clear → slot active
.no_carry_rts:            ; $CAE0 — shared CLC+RTS exit
    CLC
    RTS
.active:                  ; $CAE2
    LDA $1A81,X           ; timer/state byte
    BEQ .no_carry_rts     ; zero → not ready
    BMI .no_carry_rts     ; negative → not ready
    LDA $0F00,X           ; animation type byte
    BEQ .no_carry_rts     ; zero → no animation
    LDA $1201,X           ; sprite pass/type flags
    AND #$03              ; isolate bits 0-1
    BEQ .type0            ; 0 → single-slot builder
    CMP #$01
    BNE .check2
    BRA .type1            ; 1 → 8-slot builder
.check2:
    CMP #$02
    BEQ .type2            ; 2 → 12-slot builder
    CLC
    RTS                   ; 3 → unhandled, no-op
.type0:
    BRL Sub_CBDC             ; tail-call Sub_CBDC ($CB04 + $00D8 = $CBDC)
.type1:
    BRL Sub_CEF5             ; tail-call Sub_CEF5 ($CB07 + $03EE = $CEF5)
.type2:
    BRL Sub_D4F7             ; tail-call Sub_D4F7 ($CB0A + $09ED = $D4F7)

org $C0B8CA
Sub_B8CA:
    ; 411 bytes ($B8CA-$BA64). Entry M=1, X=1 (X=gfx_index from caller).
    ; Packs X-overflow bits into OAM attribute byte, copies raw Y-source table
    ; ($7F:480X) into staging buf ($7F:4BCX), then dispatches Y-clamp on $C6:$C5.
    PHB
    LDA #$7F
    PHA
    PLB
    REP #$20
    LDA.l $000A80,X
    AND #$01FF
    STA $C5
    LDA.l $000A00,X
    STA $C3
    STZ $E5
    LDA.l $001700,X
    STA $D9
    CLC
    ADC #$0018              ; A = gfx_index + $18 (first tile is highest)

    ; ── X-init loop: copy $7F:4802,X → $7F:4BC2,X; pack 1 overflow bit per tile ─
.b8ca_x_loop:
    TAX                     ; X = decremented tile pointer (or gfx+$18 on first pass)
    LDA.w $4802,X           ; M=0: 16-bit raw X offset
    STA.w $4BC2,X           ; copy to staging buf
    CLC
    ADC $C3                 ; add base X coordinate
    SEP #$20                ; M=1
    STA.w $4BC0,X           ; store X low byte
    XBA
    AND #$01                ; extract X bit 8 (overflow)
    STA $E6
    LDA $E5
    ASL A
    ASL A
    ORA $E6
    CPX $D9
    BEQ .b8ca_x_done        ; exit when X reaches gfx_index (lowest tile)
    STA $E5
    REP #$20                ; M=0
    TXA
    SEC
    SBC #$0008              ; step to next lower tile
    BRA .b8ca_x_loop

    ; ── Finalize OAM byte, dispatch on $C6 ────────────────────────────────────
.b8ca_x_done:
    ORA #$AA                ; M=1: set OAM size bits; merge last overflow bit
    LDX $6D
    STA.w $4F00,X           ; OAM high-table byte for this sprite slot
    LDX $D9                 ; restore X = gfx_index for Y-clamp pass
    LDA $C6
    BEQ .b8ca_c6_zero

    ; ── C6≠0: 5-tile unrolled, BCC→clamp / carry+CMP/BCS→store ─────────────
    ; Logic: only carry-set results ≥$E0 pass through; everything else → $E0.
    LDA.w $4804,X
    STA.w $4BC4,X           ; copy raw Y-source to staging
    CLC
    ADC $C5
    BCC .b8ca_nz_cl0
    CMP #$E0
    BCS .b8ca_nz_st0
.b8ca_nz_cl0:
    LDA #$E0
.b8ca_nz_st0:
    STA.w $4BC1,X

    LDA.w $480C,X
    STA.w $4BCC,X
    CLC
    ADC $C5
    BCC .b8ca_nz_cl1
    CMP #$E0
    BCS .b8ca_nz_st1
.b8ca_nz_cl1:
    LDA #$E0
.b8ca_nz_st1:
    STA.w $4BC9,X

    LDA.w $4814,X
    STA.w $4BD4,X
    CLC
    ADC $C5
    BCC .b8ca_nz_cl2
    CMP #$E0
    BCS .b8ca_nz_st2
.b8ca_nz_cl2:
    LDA #$E0
.b8ca_nz_st2:
    STA.w $4BD1,X

    LDA.w $481C,X
    STA.w $4BDC,X
    CLC
    ADC $C5
    BCC .b8ca_nz_cl3
    CMP #$E0
    BCS .b8ca_nz_st3
.b8ca_nz_cl3:
    LDA #$E0
.b8ca_nz_st3:
    STA.w $4BD9,X

    LDA.w $4BE4,X           ; tile 4: read from staging (no raw-table copy)
    CLC
    ADC $C5
    BCC .b8ca_nz_cl4
    CMP #$E0
    BCS .b8ca_nz_st4
.b8ca_nz_cl4:
    LDA #$E0
.b8ca_nz_st4:
    STA.w $4BE1,X

    REP #$20                ; 16-bit epilogue: copy raw 16-bit Y-source → staging
    LDA.w $4806,X
    STA.w $4BC6,X
    LDA.w $480E,X
    STA.w $4BCE,X
    LDA.w $4816,X
    STA.w $4BD6,X
    LDA.w $481E,X
    STA.w $4BDE,X
    SEP #$20
    PLB
    RTS                     ; C6≠0 path exit

    ; ── C6=0 dispatch on C5 bit 7 ─────────────────────────────────────────────
.b8ca_c6_zero:
    LDA $C5
    BPL .b8ca_pos_c5        ; bit7=0: positive path

    ; ── C6=0 negative path (C5≥$80): 4 tiles, BCC+6/BCC+2 clamp ─────────────
    LDA.w $4804,X
    STA.w $4BC4,X
    CLC
    ADC $C5
    BCC .b8ca_neg_st0
    CMP #$E0
    BCC .b8ca_neg_st0
    LDA #$E0
.b8ca_neg_st0:
    STA.w $4BC1,X

    LDA.w $480C,X
    STA.w $4BCC,X
    CLC
    ADC $C5
    BCC .b8ca_neg_st1
    CMP #$E0
    BCC .b8ca_neg_st1
    LDA #$E0
.b8ca_neg_st1:
    STA.w $4BC9,X

    LDA.w $4814,X
    STA.w $4BD4,X
    CLC
    ADC $C5
    BCC .b8ca_neg_st2
    CMP #$E0
    BCC .b8ca_neg_st2
    LDA #$E0
.b8ca_neg_st2:
    STA.w $4BD1,X

    LDA.w $481C,X
    STA.w $4BDC,X
    CLC
    ADC $C5
    BCC .b8ca_neg_st3
    CMP #$E0
    BCC .b8ca_neg_st3
    LDA #$E0
.b8ca_neg_st3:
    STA.w $4BD9,X
    BRA .b8ca_epilogue

    ; ── C6=0 positive path (C5<$80): 4 tiles, BPL+6/BCS+2 clamp ─────────────
.b8ca_pos_c5:
    LDA.w $4804,X
    STA.w $4BC4,X
    CLC
    ADC $C5
    BPL .b8ca_pos_st0
    CMP #$E0
    BCS .b8ca_pos_st0
    LDA #$E0
.b8ca_pos_st0:
    STA.w $4BC1,X

    LDA.w $480C,X
    STA.w $4BCC,X
    CLC
    ADC $C5
    BPL .b8ca_pos_st1
    CMP #$E0
    BCS .b8ca_pos_st1
    LDA #$E0
.b8ca_pos_st1:
    STA.w $4BC9,X

    LDA.w $4814,X
    STA.w $4BD4,X
    CLC
    ADC $C5
    BPL .b8ca_pos_st2
    CMP #$E0
    BCS .b8ca_pos_st2
    LDA #$E0
.b8ca_pos_st2:
    STA.w $4BD1,X

    LDA.w $481C,X
    STA.w $4BDC,X
    CLC
    ADC $C5
    BPL .b8ca_pos_st3
    CMP #$E0
    BCS .b8ca_pos_st3
    LDA #$E0
.b8ca_pos_st3:
    STA.w $4BD9,X
    ; fall through to shared epilogue

    ; ── Shared epilogue: 16-bit Y-source copies + PLB + RTS ───────────────────
.b8ca_epilogue:
    REP #$20
    LDA.w $4806,X
    STA.w $4BC6,X
    LDA.w $480E,X
    STA.w $4BCE,X
    LDA.w $4816,X
    STA.w $4BD6,X
    LDA.w $481E,X
    STA.w $4BDE,X
    SEP #$20
    PLB
    RTS

org $C0BA65
Sub_BA65:
    ; 631 bytes ($BA65-$BCDB). Entry M=1, X=1. Type 1 low-state init.
    ; Reads X offsets from staging buf ($4BC2,X) — not raw table.
    ; Two X-loops (gfx_index and gfx_index+$20 slots), then 3-way Y-clamp.
    PHB
    LDA #$7F
    PHA
    PLB
    REP #$20
    LDX $6D
    LDA.l $000A80,X
    AND #$01FF
    STA $C5
    LDA.l $000A00,X
    STA $C3
    STZ $E5
    LDA.l $001700,X
    STA $D9
    CLC
    ADC #$0018

    ; ── X-loop 1: staging $4BC2 → $4BC0, ORA#$AA → $4F00 ───────────────────
.b65_x1_loop:
    TAX
    LDA.w $4BC2,X
    CLC
    ADC $C3
    SEP #$20
    STA.w $4BC0,X
    XBA
    AND #$01
    STA $E6
    LDA $E5
    ASL A
    ASL A
    ORA $E6
    CPX $D9
    BEQ .b65_x1_done
    STA $E5
    REP #$20
    TXA
    SEC
    SBC #$0008
    BRA .b65_x1_loop
.b65_x1_done:
    ORA #$AA
    LDX $6D
    STA.w $4F00,X
    STZ $E5
    REP #$20
    LDA $D9
    CLC
    ADC #$0020
    STA $E7
    CLC
    ADC #$0018

    ; ── X-loop 2: same as loop 1 but compare $E7 → $4F01 ────────────────────
.b65_x2_loop:
    TAX
    LDA.w $4BC2,X
    CLC
    ADC $C3
    SEP #$20
    STA.w $4BC0,X
    XBA
    AND #$01
    STA $E6
    LDA $E5
    ASL A
    ASL A
    ORA $E6
    CPX $E7
    BEQ .b65_x2_done
    STA $E5
    REP #$20
    TXA
    SEC
    SBC #$0008
    BRA .b65_x2_loop
.b65_x2_done:
    ORA #$AA
    LDX $6D
    STA.w $4F01,X
    LDX $D9
    LDA $C6
    BEQ .b65_c6_zero
    BRL .b65_c6nz               ; C6≠0 → $BC50

    ; ── C6=0 dispatch on C5 sign ──────────────────────────────────────────────
.b65_c6_zero:
    LDA $C5
    BPL .b65_pos_c5

    ; ── C6=0 negative (C5≥$80): 8 tiles, CMP#$E0/BCC clamp ─────────────────
    LDA.w $4BC4,X
    CLC
    ADC $C5
    CMP #$E0
    BCC .b65_neg_st0
    LDA #$E0
.b65_neg_st0:
    STA.w $4BC1,X

    LDA.w $4BCC,X
    CLC
    ADC $C5
    CMP #$E0
    BCC .b65_neg_st1
    LDA #$E0
.b65_neg_st1:
    STA.w $4BC9,X

    LDA.w $4BD4,X
    CLC
    ADC $C5
    CMP #$E0
    BCC .b65_neg_st2
    LDA #$E0
.b65_neg_st2:
    STA.w $4BD1,X

    LDA.w $4BDC,X
    CLC
    ADC $C5
    CMP #$E0
    BCC .b65_neg_st3
    LDA #$E0
.b65_neg_st3:
    STA.w $4BD9,X

    LDA.w $4BE4,X
    CLC
    ADC $C5
    CMP #$E0
    BCC .b65_neg_st4
    LDA #$E0
.b65_neg_st4:
    STA.w $4BE1,X

    LDA.w $4BEC,X
    CLC
    ADC $C5
    CMP #$E0
    BCC .b65_neg_st5
    LDA #$E0
.b65_neg_st5:
    STA.w $4BE9,X

    LDA.w $4BF4,X
    CLC
    ADC $C5
    CMP #$E0
    BCC .b65_neg_st6
    LDA #$E0
.b65_neg_st6:
    STA.w $4BF1,X

    LDA.w $4BFC,X
    CLC
    ADC $C5
    CMP #$E0
    BCC .b65_neg_st7
    LDA #$E0
.b65_neg_st7:
    STA.w $4BF9,X
    SEP #$20
    PLB
    RTS

    ; ── C6=0 positive (C5<$80): 8 tiles, BMI-split BPL/CMP/BCS clamp ────────
    ; Source sign check on staging Y-src: <$80 uses CLC/ADC/BCC path;
    ; ≥$80 uses CLC/ADC/BPL/CMP/BCS path. Both converge at store label.
.b65_pos_c5:
    LDA.w $4BC4,X
    BMI .b65_pos_b0
    CLC
    ADC $C5
    BCC .b65_pos_st0
    BRA .b65_pos_p0
.b65_pos_b0:
    CLC
    ADC $C5
.b65_pos_p0:
    BPL .b65_pos_st0
    CMP #$E0
    BCS .b65_pos_st0
    LDA #$E0
.b65_pos_st0:
    STA.w $4BC1,X

    LDA.w $4BCC,X
    BMI .b65_pos_b1
    CLC
    ADC $C5
    BCC .b65_pos_st1
    BRA .b65_pos_p1
.b65_pos_b1:
    CLC
    ADC $C5
.b65_pos_p1:
    BPL .b65_pos_st1
    CMP #$E0
    BCS .b65_pos_st1
    LDA #$E0
.b65_pos_st1:
    STA.w $4BC9,X

    LDA.w $4BD4,X
    BMI .b65_pos_b2
    CLC
    ADC $C5
    BCC .b65_pos_st2
    BRA .b65_pos_p2
.b65_pos_b2:
    CLC
    ADC $C5
.b65_pos_p2:
    BPL .b65_pos_st2
    CMP #$E0
    BCS .b65_pos_st2
    LDA #$E0
.b65_pos_st2:
    STA.w $4BD1,X

    LDA.w $4BDC,X
    BMI .b65_pos_b3
    CLC
    ADC $C5
    BCC .b65_pos_st3
    BRA .b65_pos_p3
.b65_pos_b3:
    CLC
    ADC $C5
.b65_pos_p3:
    BPL .b65_pos_st3
    CMP #$E0
    BCS .b65_pos_st3
    LDA #$E0
.b65_pos_st3:
    STA.w $4BD9,X

    LDA.w $4BE4,X
    BMI .b65_pos_b4
    CLC
    ADC $C5
    BCC .b65_pos_st4
    BRA .b65_pos_p4
.b65_pos_b4:
    CLC
    ADC $C5
.b65_pos_p4:
    BPL .b65_pos_st4
    CMP #$E0
    BCS .b65_pos_st4
    LDA #$E0
.b65_pos_st4:
    STA.w $4BE1,X

    LDA.w $4BEC,X
    BMI .b65_pos_b5
    CLC
    ADC $C5
    BCC .b65_pos_st5
    BRA .b65_pos_p5
.b65_pos_b5:
    CLC
    ADC $C5
.b65_pos_p5:
    BPL .b65_pos_st5
    CMP #$E0
    BCS .b65_pos_st5
    LDA #$E0
.b65_pos_st5:
    STA.w $4BE9,X

    LDA.w $4BF4,X
    BMI .b65_pos_b6
    CLC
    ADC $C5
    BCC .b65_pos_st6
    BRA .b65_pos_p6
.b65_pos_b6:
    CLC
    ADC $C5
.b65_pos_p6:
    BPL .b65_pos_st6
    CMP #$E0
    BCS .b65_pos_st6
    LDA #$E0
.b65_pos_st6:
    STA.w $4BF1,X

    LDA.w $4BFC,X
    BMI .b65_pos_b7
    CLC
    ADC $C5
    BCC .b65_pos_st7
    BRA .b65_pos_p7
.b65_pos_b7:
    CLC
    ADC $C5
.b65_pos_p7:
    BPL .b65_pos_st7
    CMP #$E0
    BCS .b65_pos_st7
    LDA #$E0
.b65_pos_st7:
    STA.w $4BF9,X
    SEP #$20
    PLB
    RTS

    ; ── C6≠0 path: 8 tiles from staging, BCC→$E0, CMP/BCS→store ────────────
.b65_c6nz:
    LDA.w $4BC4,X
    CLC
    ADC $C5
    BCC .b65_nz_cl0
    CMP #$E0
    BCS .b65_nz_st0
.b65_nz_cl0:
    LDA #$E0
.b65_nz_st0:
    STA.w $4BC1,X

    LDA.w $4BCC,X
    CLC
    ADC $C5
    BCC .b65_nz_cl1
    CMP #$E0
    BCS .b65_nz_st1
.b65_nz_cl1:
    LDA #$E0
.b65_nz_st1:
    STA.w $4BC9,X

    LDA.w $4BD4,X
    CLC
    ADC $C5
    BCC .b65_nz_cl2
    CMP #$E0
    BCS .b65_nz_st2
.b65_nz_cl2:
    LDA #$E0
.b65_nz_st2:
    STA.w $4BD1,X

    LDA.w $4BDC,X
    CLC
    ADC $C5
    BCC .b65_nz_cl3
    CMP #$E0
    BCS .b65_nz_st3
.b65_nz_cl3:
    LDA #$E0
.b65_nz_st3:
    STA.w $4BD9,X

    LDA.w $4BE4,X
    CLC
    ADC $C5
    BCC .b65_nz_cl4
    CMP #$E0
    BCS .b65_nz_st4
.b65_nz_cl4:
    LDA #$E0
.b65_nz_st4:
    STA.w $4BE1,X

    LDA.w $4BEC,X
    CLC
    ADC $C5
    BCC .b65_nz_cl5
    CMP #$E0
    BCS .b65_nz_st5
.b65_nz_cl5:
    LDA #$E0
.b65_nz_st5:
    STA.w $4BE9,X

    LDA.w $4BF4,X
    CLC
    ADC $C5
    BCC .b65_nz_cl6
    CMP #$E0
    BCS .b65_nz_st6
.b65_nz_cl6:
    LDA #$E0
.b65_nz_st6:
    STA.w $4BF1,X

    LDA.w $4BFC,X
    CLC
    ADC $C5
    BCC .b65_nz_cl7
    CMP #$E0
    BCS .b65_nz_st7
.b65_nz_cl7:
    LDA #$E0
.b65_nz_st7:
    STA.w $4BF9,X
    SEP #$20
    PLB
    RTS

org $C0BCDC
Sub_BCDC:
    ; 790 bytes ($BCDC-$BFF1). Entry M=1, X=1. Type 1 high-state init.
    ; Reads X offsets from raw table ($4802,X) AND writes to staging ($4BC2,X).
    ; Two X-loops (gfx_index and gfx_index+$20), then 3-way Y-clamp (8 tiles).
    ; Positive path uses BPL/CMP/BCS — no BMI-split (unlike Sub_BA65).
    PHB
    LDA #$7F
    PHA
    PLB
    REP #$20
    LDX $6D
    LDA.l $000A80,X
    AND #$01FF
    STA $C5
    LDA.l $000A00,X
    STA $C3
    STZ $E5
    LDA.l $001700,X
    STA $D9
    CLC
    ADC #$0018

    ; ── X-loop 1: raw $4802 → staging $4BC2 → $4BC0, pack OAM → $4F00 ─────────
.bcdc_x1_loop:
    TAX
    LDA.w $4802,X
    STA.w $4BC2,X
    CLC
    ADC $C3
    SEP #$20
    STA.w $4BC0,X
    XBA
    AND #$01
    STA $E6
    LDA $E5
    ASL A
    ASL A
    ORA $E6
    CPX $D9
    BEQ .bcdc_x1_done
    STA $E5
    REP #$20
    TXA
    SEC
    SBC #$0008
    BRA .bcdc_x1_loop
.bcdc_x1_done:
    ORA #$AA
    LDX $6D
    STA.w $4F00,X
    STZ $E5
    REP #$20
    LDA $D9
    CLC
    ADC #$0020
    STA $E7
    CLC
    ADC #$0018

    ; ── X-loop 2: same, compare $E7 → $4F01 ─────────────────────────────────
.bcdc_x2_loop:
    TAX
    LDA.w $4802,X
    STA.w $4BC2,X
    CLC
    ADC $C3
    SEP #$20
    STA.w $4BC0,X
    XBA
    AND #$01
    STA $E6
    LDA $E5
    ASL A
    ASL A
    ORA $E6
    CPX $E7
    BEQ .bcdc_x2_done
    STA $E5
    REP #$20
    TXA
    SEC
    SBC #$0008
    BRA .bcdc_x2_loop
.bcdc_x2_done:
    ORA #$AA
    LDX $6D
    STA.w $4F01,X
    LDX $D9
    LDA $C6
    BEQ .bcdc_c6_zero
    BRL .bcdc_nz               ; C6≠0 → $BF1C

    ; ── C6=0 dispatch on C5 sign ──────────────────────────────────────────────
.bcdc_c6_zero:
    LDA $C5
    BMI .bcdc_neg
    BRL .bcdc_pos               ; C5<$80 → $BE46 positive path

    ; ── C6=0 negative (C5≥$80): CMP#$E0/BCC clamp ────────────────────────────
.bcdc_neg:
    LDA.w $4804,X
    STA.w $4BC4,X
    CLC
    ADC $C5
    CMP #$E0
    BCC .bcdc_neg_st0
    LDA #$E0
.bcdc_neg_st0:
    STA.w $4BC1,X
    LDA.w $480C,X
    STA.w $4BCC,X
    CLC
    ADC $C5
    CMP #$E0
    BCC .bcdc_neg_st1
    LDA #$E0
.bcdc_neg_st1:
    STA.w $4BC9,X
    LDA.w $4814,X
    STA.w $4BD4,X
    CLC
    ADC $C5
    CMP #$E0
    BCC .bcdc_neg_st2
    LDA #$E0
.bcdc_neg_st2:
    STA.w $4BD1,X
    LDA.w $481C,X
    STA.w $4BDC,X
    CLC
    ADC $C5
    CMP #$E0
    BCC .bcdc_neg_st3
    LDA #$E0
.bcdc_neg_st3:
    STA.w $4BD9,X
    LDA.w $4824,X
    STA.w $4BE4,X
    CLC
    ADC $C5
    CMP #$E0
    BCC .bcdc_neg_st4
    LDA #$E0
.bcdc_neg_st4:
    STA.w $4BE1,X
    LDA.w $482C,X
    STA.w $4BEC,X
    CLC
    ADC $C5
    CMP #$E0
    BCC .bcdc_neg_st5
    LDA #$E0
.bcdc_neg_st5:
    STA.w $4BE9,X
    LDA.w $4834,X
    STA.w $4BF4,X
    CLC
    ADC $C5
    CMP #$E0
    BCC .bcdc_neg_st6
    LDA #$E0
.bcdc_neg_st6:
    STA.w $4BF1,X
    LDA.w $483C,X
    STA.w $4BFC,X
    CLC
    ADC $C5
    CMP #$E0
    BCC .bcdc_neg_st7
    LDA #$E0
.bcdc_neg_st7:
    STA.w $4BF9,X
    REP #$20
    LDA.w $4806,X
    STA.w $4BC6,X
    LDA.w $480E,X
    STA.w $4BCE,X
    LDA.w $4816,X
    STA.w $4BD6,X
    LDA.w $481E,X
    STA.w $4BDE,X
    LDA.w $4826,X
    STA.w $4BE6,X
    LDA.w $482E,X
    STA.w $4BEE,X
    LDA.w $4836,X
    STA.w $4BF6,X
    LDA.w $483E,X
    STA.w $4BFE,X
    SEP #$20
    PLB
    RTS

    ; ── C6=0 positive (C5<$80): BPL/CMP/BCS clamp (no BMI-split) ────────────
.bcdc_pos:
    LDA.w $4804,X
    STA.w $4BC4,X
    CLC
    ADC $C5
    BPL .bcdc_pos_st0
    CMP #$E0
    BCS .bcdc_pos_st0
    LDA #$E0
.bcdc_pos_st0:
    STA.w $4BC1,X
    LDA.w $480C,X
    STA.w $4BCC,X
    CLC
    ADC $C5
    BPL .bcdc_pos_st1
    CMP #$E0
    BCS .bcdc_pos_st1
    LDA #$E0
.bcdc_pos_st1:
    STA.w $4BC9,X
    LDA.w $4814,X
    STA.w $4BD4,X
    CLC
    ADC $C5
    BPL .bcdc_pos_st2
    CMP #$E0
    BCS .bcdc_pos_st2
    LDA #$E0
.bcdc_pos_st2:
    STA.w $4BD1,X
    LDA.w $481C,X
    STA.w $4BDC,X
    CLC
    ADC $C5
    BPL .bcdc_pos_st3
    CMP #$E0
    BCS .bcdc_pos_st3
    LDA #$E0
.bcdc_pos_st3:
    STA.w $4BD9,X
    LDA.w $4824,X
    STA.w $4BE4,X
    CLC
    ADC $C5
    BPL .bcdc_pos_st4
    CMP #$E0
    BCS .bcdc_pos_st4
    LDA #$E0
.bcdc_pos_st4:
    STA.w $4BE1,X
    LDA.w $482C,X
    STA.w $4BEC,X
    CLC
    ADC $C5
    BPL .bcdc_pos_st5
    CMP #$E0
    BCS .bcdc_pos_st5
    LDA #$E0
.bcdc_pos_st5:
    STA.w $4BE9,X
    LDA.w $4834,X
    STA.w $4BF4,X
    CLC
    ADC $C5
    BPL .bcdc_pos_st6
    CMP #$E0
    BCS .bcdc_pos_st6
    LDA #$E0
.bcdc_pos_st6:
    STA.w $4BF1,X
    LDA.w $483C,X
    STA.w $4BFC,X
    CLC
    ADC $C5
    BPL .bcdc_pos_st7
    CMP #$E0
    BCS .bcdc_pos_st7
    LDA #$E0
.bcdc_pos_st7:
    STA.w $4BF9,X
    REP #$20
    LDA.w $4806,X
    STA.w $4BC6,X
    LDA.w $480E,X
    STA.w $4BCE,X
    LDA.w $4816,X
    STA.w $4BD6,X
    LDA.w $481E,X
    STA.w $4BDE,X
    LDA.w $4826,X
    STA.w $4BE6,X
    LDA.w $482E,X
    STA.w $4BEE,X
    LDA.w $4836,X
    STA.w $4BF6,X
    LDA.w $483E,X
    STA.w $4BFE,X
    SEP #$20
    PLB
    RTS

    ; ── C6≠0: BCC→clamp, CMP/BCS→store ──────────────────────────────────────
.bcdc_nz:
    LDA.w $4804,X
    STA.w $4BC4,X
    CLC
    ADC $C5
    BCC .bcdc_nz_cl0
    CMP #$E0
    BCS .bcdc_nz_st0
.bcdc_nz_cl0:
    LDA #$E0
.bcdc_nz_st0:
    STA.w $4BC1,X
    LDA.w $480C,X
    STA.w $4BCC,X
    CLC
    ADC $C5
    BCC .bcdc_nz_cl1
    CMP #$E0
    BCS .bcdc_nz_st1
.bcdc_nz_cl1:
    LDA #$E0
.bcdc_nz_st1:
    STA.w $4BC9,X
    LDA.w $4814,X
    STA.w $4BD4,X
    CLC
    ADC $C5
    BCC .bcdc_nz_cl2
    CMP #$E0
    BCS .bcdc_nz_st2
.bcdc_nz_cl2:
    LDA #$E0
.bcdc_nz_st2:
    STA.w $4BD1,X
    LDA.w $481C,X
    STA.w $4BDC,X
    CLC
    ADC $C5
    BCC .bcdc_nz_cl3
    CMP #$E0
    BCS .bcdc_nz_st3
.bcdc_nz_cl3:
    LDA #$E0
.bcdc_nz_st3:
    STA.w $4BD9,X
    LDA.w $4824,X
    STA.w $4BE4,X
    CLC
    ADC $C5
    BCC .bcdc_nz_cl4
    CMP #$E0
    BCS .bcdc_nz_st4
.bcdc_nz_cl4:
    LDA #$E0
.bcdc_nz_st4:
    STA.w $4BE1,X
    LDA.w $482C,X
    STA.w $4BEC,X
    CLC
    ADC $C5
    BCC .bcdc_nz_cl5
    CMP #$E0
    BCS .bcdc_nz_st5
.bcdc_nz_cl5:
    LDA #$E0
.bcdc_nz_st5:
    STA.w $4BE9,X
    LDA.w $4834,X
    STA.w $4BF4,X
    CLC
    ADC $C5
    BCC .bcdc_nz_cl6
    CMP #$E0
    BCS .bcdc_nz_st6
.bcdc_nz_cl6:
    LDA #$E0
.bcdc_nz_st6:
    STA.w $4BF1,X
    LDA.w $483C,X
    STA.w $4BFC,X
    CLC
    ADC $C5
    BCC .bcdc_nz_cl7
    CMP #$E0
    BCS .bcdc_nz_st7
.bcdc_nz_cl7:
    LDA #$E0
.bcdc_nz_st7:
    STA.w $4BF9,X
    REP #$20
    LDA.w $4806,X
    STA.w $4BC6,X
    LDA.w $480E,X
    STA.w $4BCE,X
    LDA.w $4816,X
    STA.w $4BD6,X
    LDA.w $481E,X
    STA.w $4BDE,X
    LDA.w $4826,X
    STA.w $4BE6,X
    LDA.w $482E,X
    STA.w $4BEE,X
    LDA.w $4836,X
    STA.w $4BF6,X
    LDA.w $483E,X
    STA.w $4BFE,X
    SEP #$20
    PLB
    RTS

org $C0BFF2
Sub_BFF2:
    ; 717 bytes ($BFF2–$C2BE). Entry M=1, X=1. Types 2/3+ low-state init.
    ; Reads X coords from staging ($4BC2,X) directly (no raw-table copy).
    ; Three backward X-loops pack OAM high bits → $4F00, $4F01, $4B40.
    ; Then 3-way Y dispatch: C6≠0 → type-3+ (BCS/BPL clamp, 12 tiles),
    ;   C6=0 C5<0 → negative (direct add, 12 tiles),
    ;   C6=0 C5≥0 → positive (BMI-split BPL/CMP/BCS clamp, 12 tiles).
    ; BMI-split IS present here — not isolated to Sub_BA65.
    PHB
    LDA #$7F
    PHA
    PLB
    REP #$20
    LDX $6D
    LDA.l $000A80,X
    AND #$01FF
    STA $C5
    LDA.l $000A00,X
    STA $C3
    STZ $E5
    LDA.l $001700,X
    STA $D9
    CLC
    ADC #$0018

    ; ── X-loop 1: staging $4BC2 → $4BC0, pack OAM high → $4F00 ─────────────
.bff2_x1_loop:
    TAX
    LDA.w $4BC2,X
    CLC
    ADC $C3
    SEP #$20
    STA.w $4BC0,X
    XBA
    AND #$01
    STA $E6
    LDA $E5
    ASL A
    ASL A
    ORA $E6
    CPX $D9
    BEQ .bff2_x1_done
    STA $E5
    REP #$20
    TXA
    SEC
    SBC #$0008
    BRA .bff2_x1_loop
.bff2_x1_done:
    ORA #$AA
    LDX $6D
    STA.w $4F00,X
    STZ $E5
    REP #$20
    LDA $D9
    CLC
    ADC #$0020
    STA $E7
    CLC
    ADC #$0018

    ; ── X-loop 2: same, compare $E7 → $4F01 ─────────────────────────────────
.bff2_x2_loop:
    TAX
    LDA.w $4BC2,X
    CLC
    ADC $C3
    SEP #$20
    STA.w $4BC0,X
    XBA
    AND #$01
    STA $E6
    LDA $E5
    ASL A
    ASL A
    ORA $E6
    CPX $E7
    BEQ .bff2_x2_done
    STA $E5
    REP #$20
    TXA
    SEC
    SBC #$0008
    BRA .bff2_x2_loop
.bff2_x2_done:
    ORA #$AA
    LDX $6D
    STA.w $4F01,X
    STZ $E5
    REP #$20
    LDA $D9
    CLC
    ADC #$0040
    STA $E7
    CLC
    ADC #$0018

    ; ── X-loop 3: same, compare $E7 → $4B40 ─────────────────────────────────
.bff2_x3_loop:
    TAX
    LDA.w $4BC2,X
    CLC
    ADC $C3
    SEP #$20
    STA.w $4BC0,X
    XBA
    AND #$01
    STA $E6
    LDA $E5
    ASL A
    ASL A
    ORA $E6
    CPX $E7
    BEQ .bff2_x3_done
    STA $E5
    REP #$20
    TXA
    SEC
    SBC #$0008
    BRA .bff2_x3_loop
.bff2_x3_done:
    ORA #$AA
    LDX $6D
    STA.w $4B40,X

    ; ── Dispatch ──────────────────────────────────────────────────────────────
    LDX $D9
    LDA $C6
    BEQ .bff2_c6_zero
    BRL .bff2_t3               ; C6≠0 → $C209 type-3+ path

.bff2_c6_zero:
    LDA $C5
    BMI .bff2_neg
    BRL .bff2_pos               ; C5≥0 → $C13B positive path

    ; ── Negative (C5<0): direct add, no clamp, 12 tiles ─────────────────────
.bff2_neg:
    LDA.w $4BC4,X
    CLC
    ADC $C5
    STA.w $4BC1,X
    LDA.w $4BCC,X
    CLC
    ADC $C5
    STA.w $4BC9,X
    LDA.w $4BD4,X
    CLC
    ADC $C5
    STA.w $4BD1,X
    LDA.w $4BDC,X
    CLC
    ADC $C5
    STA.w $4BD9,X
    LDA.w $4BE4,X
    CLC
    ADC $C5
    STA.w $4BE1,X
    LDA.w $4BEC,X
    CLC
    ADC $C5
    STA.w $4BE9,X
    LDA.w $4BF4,X
    CLC
    ADC $C5
    STA.w $4BF1,X
    LDA.w $4BFC,X
    CLC
    ADC $C5
    STA.w $4BF9,X
    LDA.w $4C04,X
    CLC
    ADC $C5
    STA.w $4C01,X
    LDA.w $4C0C,X
    CLC
    ADC $C5
    STA.w $4C09,X
    LDA.w $4C14,X
    CLC
    ADC $C5
    STA.w $4C11,X
    LDA.w $4C1C,X
    CLC
    ADC $C5
    STA.w $4C19,X
    PLB
    RTS

    ; ── Positive (C5≥0): BMI-split BPL/CMP #$E0/BCS clamp, 12 tiles ─────────
    ; Same 3-instruction clamp as Sub_BA65 positive path.
.bff2_pos:
    LDA.w $4BC4,X
    CLC
    ADC $C5
    BPL .bff2_pos_st0
    CMP #$E0
    BCS .bff2_pos_st0
    LDA #$E0
.bff2_pos_st0:
    STA.w $4BC1,X
    LDA.w $4BCC,X
    CLC
    ADC $C5
    BPL .bff2_pos_st1
    CMP #$E0
    BCS .bff2_pos_st1
    LDA #$E0
.bff2_pos_st1:
    STA.w $4BC9,X
    LDA.w $4BD4,X
    CLC
    ADC $C5
    BPL .bff2_pos_st2
    CMP #$E0
    BCS .bff2_pos_st2
    LDA #$E0
.bff2_pos_st2:
    STA.w $4BD1,X
    LDA.w $4BDC,X
    CLC
    ADC $C5
    BPL .bff2_pos_st3
    CMP #$E0
    BCS .bff2_pos_st3
    LDA #$E0
.bff2_pos_st3:
    STA.w $4BD9,X
    LDA.w $4BE4,X
    CLC
    ADC $C5
    BPL .bff2_pos_st4
    CMP #$E0
    BCS .bff2_pos_st4
    LDA #$E0
.bff2_pos_st4:
    STA.w $4BE1,X
    LDA.w $4BEC,X
    CLC
    ADC $C5
    BPL .bff2_pos_st5
    CMP #$E0
    BCS .bff2_pos_st5
    LDA #$E0
.bff2_pos_st5:
    STA.w $4BE9,X
    LDA.w $4BF4,X
    CLC
    ADC $C5
    BPL .bff2_pos_st6
    CMP #$E0
    BCS .bff2_pos_st6
    LDA #$E0
.bff2_pos_st6:
    STA.w $4BF1,X
    LDA.w $4BFC,X
    CLC
    ADC $C5
    BPL .bff2_pos_st7
    CMP #$E0
    BCS .bff2_pos_st7
    LDA #$E0
.bff2_pos_st7:
    STA.w $4BF9,X
    LDA.w $4C04,X
    CLC
    ADC $C5
    BPL .bff2_pos_st8
    CMP #$E0
    BCS .bff2_pos_st8
    LDA #$E0
.bff2_pos_st8:
    STA.w $4C01,X
    LDA.w $4C0C,X
    CLC
    ADC $C5
    BPL .bff2_pos_st9
    CMP #$E0
    BCS .bff2_pos_st9
    LDA #$E0
.bff2_pos_st9:
    STA.w $4C09,X
    LDA.w $4C14,X
    CLC
    ADC $C5
    BPL .bff2_pos_st10
    CMP #$E0
    BCS .bff2_pos_st10
    LDA #$E0
.bff2_pos_st10:
    STA.w $4C11,X
    LDA.w $4C1C,X
    CLC
    ADC $C5
    BPL .bff2_pos_st11
    CMP #$E0
    BCS .bff2_pos_st11
    LDA #$E0
.bff2_pos_st11:
    STA.w $4C19,X
    PLB
    RTS

    ; ── Type 3+ (C6≠0): BCS/BPL clamp (carry-overflow → $E0), 12 tiles ──────
.bff2_t3:
    LDA.w $4BC4,X
    CLC
    ADC $C5
    BCS .bff2_t3_st0
    BPL .bff2_t3_skip0
.bff2_t3_st0:
    LDA #$E0
.bff2_t3_skip0:
    STA.w $4BC1,X
    LDA.w $4BCC,X
    CLC
    ADC $C5
    BCS .bff2_t3_st1
    BPL .bff2_t3_skip1
.bff2_t3_st1:
    LDA #$E0
.bff2_t3_skip1:
    STA.w $4BC9,X
    LDA.w $4BD4,X
    CLC
    ADC $C5
    BCS .bff2_t3_st2
    BPL .bff2_t3_skip2
.bff2_t3_st2:
    LDA #$E0
.bff2_t3_skip2:
    STA.w $4BD1,X
    LDA.w $4BDC,X
    CLC
    ADC $C5
    BCS .bff2_t3_st3
    BPL .bff2_t3_skip3
.bff2_t3_st3:
    LDA #$E0
.bff2_t3_skip3:
    STA.w $4BD9,X
    LDA.w $4BE4,X
    CLC
    ADC $C5
    BCS .bff2_t3_st4
    BPL .bff2_t3_skip4
.bff2_t3_st4:
    LDA #$E0
.bff2_t3_skip4:
    STA.w $4BE1,X
    LDA.w $4BEC,X
    CLC
    ADC $C5
    BCS .bff2_t3_st5
    BPL .bff2_t3_skip5
.bff2_t3_st5:
    LDA #$E0
.bff2_t3_skip5:
    STA.w $4BE9,X
    LDA.w $4BF4,X
    CLC
    ADC $C5
    BCS .bff2_t3_st6
    BPL .bff2_t3_skip6
.bff2_t3_st6:
    LDA #$E0
.bff2_t3_skip6:
    STA.w $4BF1,X
    LDA.w $4BFC,X
    CLC
    ADC $C5
    BCS .bff2_t3_st7
    BPL .bff2_t3_skip7
.bff2_t3_st7:
    LDA #$E0
.bff2_t3_skip7:
    STA.w $4BF9,X
    LDA.w $4C04,X
    CLC
    ADC $C5
    BCS .bff2_t3_st8
    BPL .bff2_t3_skip8
.bff2_t3_st8:
    LDA #$E0
.bff2_t3_skip8:
    STA.w $4C01,X
    LDA.w $4C0C,X
    CLC
    ADC $C5
    BCS .bff2_t3_st9
    BPL .bff2_t3_skip9
.bff2_t3_st9:
    LDA #$E0
.bff2_t3_skip9:
    STA.w $4C09,X
    LDA.w $4C14,X
    CLC
    ADC $C5
    BCS .bff2_t3_st10
    BPL .bff2_t3_skip10
.bff2_t3_st10:
    LDA #$E0
.bff2_t3_skip10:
    STA.w $4C11,X
    LDA.w $4C1C,X
    CLC
    ADC $C5
    BCS .bff2_t3_st11
    BPL .bff2_t3_skip11
.bff2_t3_st11:
    LDA #$E0
.bff2_t3_skip11:
    STA.w $4C19,X
    PLB
    RTS

org $C0C2BF
Sub_C2BF:
    ; 1064 bytes ($C2BF-$C6E6). Entry M=1, X=1. Types 2/3+ high-state init.
    ; Reads X offsets from raw table ($4802,X) AND writes to staging ($4BC2,X).
    ; Three backward X-loops (D9+$18 down, D9+$20+$18 down, D9+$40+$18 down).
    ; Then 3-way Y dispatch: C6≠0 → BCS/BPL clamp (12 tiles, raw copy),
    ;   C6=0 C5≥$80 → negative (raw copy, direct add, no clamp),
    ;   C6=0 C5<$80 → positive (raw copy, BPL/CMP/BCS clamp, no BMI-split).
    ; High-state indicator: raw $4802→$4BC2 in X-loops AND $4804→$4BC4 in Y paths.
    ; Mirrors Sub_BCDC (type 1 high-state) structure, scaled to 12 tiles.
    PHB
    LDA #$7F
    PHA
    PLB
    REP #$20
    LDX $6D
    LDA.l $000A80,X
    AND #$01FF
    STA $C5
    LDA.l $000A00,X
    STA $C3
    STZ $E5
    LDA.l $001700,X
    STA $D9
    CLC
    ADC #$0018

    ; ── X-loop 1: raw $4802,X → staging $4BC2,X, pack OAM high → $4F00 ──────
.c2bf_x1_loop:
    TAX
    LDA.w $4802,X
    STA.w $4BC2,X
    CLC
    ADC $C3
    SEP #$20
    STA.w $4BC0,X
    XBA
    AND #$01
    STA $E6
    LDA $E5
    ASL A
    ASL A
    ORA $E6
    CPX $D9
    BEQ .c2bf_x1_done
    STA $E5
    REP #$20
    TXA
    SEC
    SBC #$0008
    BRA .c2bf_x1_loop
.c2bf_x1_done:
    ORA #$AA
    LDX $6D
    STA.w $4F00,X
    STZ $E5
    REP #$20
    LDA $D9
    CLC
    ADC #$0020
    STA $E7
    CLC
    ADC #$0018

    ; ── X-loop 2: raw $4802,X → staging $4BC2,X, pack OAM high → $4F01 ──────
.c2bf_x2_loop:
    TAX
    LDA.w $4802,X
    STA.w $4BC2,X
    CLC
    ADC $C3
    SEP #$20
    STA.w $4BC0,X
    XBA
    AND #$01
    STA $E6
    LDA $E5
    ASL A
    ASL A
    ORA $E6
    CPX $E7
    BEQ .c2bf_x2_done
    STA $E5
    REP #$20
    TXA
    SEC
    SBC #$0008
    BRA .c2bf_x2_loop
.c2bf_x2_done:
    ORA #$AA
    LDX $6D
    STA.w $4F01,X
    LDX $D9                     ; extra LDX vs Sub_BFF2 (dead code quirk)
    STZ $E5
    REP #$20
    LDA $D9
    CLC
    ADC #$0040
    STA $E7
    CLC
    ADC #$0018

    ; ── X-loop 3: raw $4802,X → staging $4BC2,X, pack OAM high → $4B40 ──────
.c2bf_x3_loop:
    TAX
    LDA.w $4802,X
    STA.w $4BC2,X
    CLC
    ADC $C3
    SEP #$20
    STA.w $4BC0,X
    XBA
    AND #$01
    STA $E6
    LDA $E5
    ASL A
    ASL A
    ORA $E6
    CPX $E7
    BEQ .c2bf_x3_done
    STA $E5
    REP #$20
    TXA
    SEC
    SBC #$0008
    BRA .c2bf_x3_loop
.c2bf_x3_done:
    ORA #$AA
    LDX $6D
    STA.w $4B40,X
    LDX $D9
    LDA $C6
    BEQ .c2bf_c6_zero
    BRL .c2bf_nz               ; C6≠0 → $C5C1

    ; ── C6=0 dispatch on C5 sign ──────────────────────────────────────────────
.c2bf_c6_zero:
    LDA $C5
    BMI .c2bf_neg
    BRL .c2bf_pos               ; C5<$80 → $C483 positive path

    ; ── C6=0 negative (C5≥$80): raw copy + direct add, no clamp, 12 tiles ────
.c2bf_neg:
    LDA.w $4804,X
    STA.w $4BC4,X
    CLC
    ADC $C5
    STA.w $4BC1,X
    LDA.w $480C,X
    STA.w $4BCC,X
    CLC
    ADC $C5
    STA.w $4BC9,X
    LDA.w $4814,X
    STA.w $4BD4,X
    CLC
    ADC $C5
    STA.w $4BD1,X
    LDA.w $481C,X
    STA.w $4BDC,X
    CLC
    ADC $C5
    STA.w $4BD9,X
    LDA.w $4824,X
    STA.w $4BE4,X
    CLC
    ADC $C5
    STA.w $4BE1,X
    LDA.w $482C,X
    STA.w $4BEC,X
    CLC
    ADC $C5
    STA.w $4BE9,X
    LDA.w $4834,X
    STA.w $4BF4,X
    CLC
    ADC $C5
    STA.w $4BF1,X
    LDA.w $483C,X
    STA.w $4BFC,X
    CLC
    ADC $C5
    STA.w $4BF9,X
    LDA.w $4844,X
    STA.w $4C04,X
    CLC
    ADC $C5
    STA.w $4C01,X
    LDA.w $484C,X
    STA.w $4C0C,X
    CLC
    ADC $C5
    STA.w $4C09,X
    LDA.w $4854,X
    STA.w $4C14,X
    CLC
    ADC $C5
    STA.w $4C11,X
    LDA.w $485C,X
    STA.w $4C1C,X
    CLC
    ADC $C5
    STA.w $4C19,X
    REP #$20
    LDA.w $4806,X
    STA.w $4BC6,X
    LDA.w $480E,X
    STA.w $4BCE,X
    LDA.w $4816,X
    STA.w $4BD6,X
    LDA.w $481E,X
    STA.w $4BDE,X
    LDA.w $4826,X
    STA.w $4BE6,X
    LDA.w $482E,X
    STA.w $4BEE,X
    LDA.w $4836,X
    STA.w $4BF6,X
    LDA.w $483E,X
    STA.w $4BFE,X
    LDA.w $4846,X
    STA.w $4C06,X
    LDA.w $484E,X
    STA.w $4C0E,X
    LDA.w $4856,X
    STA.w $4C16,X
    LDA.w $485E,X
    STA.w $4C1E,X
    SEP #$20
    PLB
    RTS

    ; ── C6=0 positive (C5<$80): raw copy + BPL/CMP/BCS clamp, 12 tiles ───────
    ; Same tile structure as Sub_BCDC positive path — no BMI-split.
    ; Reads $4804,X → $4BC4,X (raw→staging) before computing Y clamp.
.c2bf_pos:
    LDA.w $4804,X
    STA.w $4BC4,X
    CLC
    ADC $C5
    BPL .c2bf_pos_st0
    CMP #$E0
    BCS .c2bf_pos_st0
    LDA #$E0
.c2bf_pos_st0:
    STA.w $4BC1,X
    LDA.w $480C,X
    STA.w $4BCC,X
    CLC
    ADC $C5
    BPL .c2bf_pos_st1
    CMP #$E0
    BCS .c2bf_pos_st1
    LDA #$E0
.c2bf_pos_st1:
    STA.w $4BC9,X
    LDA.w $4814,X
    STA.w $4BD4,X
    CLC
    ADC $C5
    BPL .c2bf_pos_st2
    CMP #$E0
    BCS .c2bf_pos_st2
    LDA #$E0
.c2bf_pos_st2:
    STA.w $4BD1,X
    LDA.w $481C,X
    STA.w $4BDC,X
    CLC
    ADC $C5
    BPL .c2bf_pos_st3
    CMP #$E0
    BCS .c2bf_pos_st3
    LDA #$E0
.c2bf_pos_st3:
    STA.w $4BD9,X
    LDA.w $4824,X
    STA.w $4BE4,X
    CLC
    ADC $C5
    BPL .c2bf_pos_st4
    CMP #$E0
    BCS .c2bf_pos_st4
    LDA #$E0
.c2bf_pos_st4:
    STA.w $4BE1,X
    LDA.w $482C,X
    STA.w $4BEC,X
    CLC
    ADC $C5
    BPL .c2bf_pos_st5
    CMP #$E0
    BCS .c2bf_pos_st5
    LDA #$E0
.c2bf_pos_st5:
    STA.w $4BE9,X
    LDA.w $4834,X
    STA.w $4BF4,X
    CLC
    ADC $C5
    BPL .c2bf_pos_st6
    CMP #$E0
    BCS .c2bf_pos_st6
    LDA #$E0
.c2bf_pos_st6:
    STA.w $4BF1,X
    LDA.w $483C,X
    STA.w $4BFC,X
    CLC
    ADC $C5
    BPL .c2bf_pos_st7
    CMP #$E0
    BCS .c2bf_pos_st7
    LDA #$E0
.c2bf_pos_st7:
    STA.w $4BF9,X
    LDA.w $4844,X
    STA.w $4C04,X
    CLC
    ADC $C5
    BPL .c2bf_pos_st8
    CMP #$E0
    BCS .c2bf_pos_st8
    LDA #$E0
.c2bf_pos_st8:
    STA.w $4C01,X
    LDA.w $484C,X
    STA.w $4C0C,X
    CLC
    ADC $C5
    BPL .c2bf_pos_st9
    CMP #$E0
    BCS .c2bf_pos_st9
    LDA #$E0
.c2bf_pos_st9:
    STA.w $4C09,X
    LDA.w $4854,X
    STA.w $4C14,X
    CLC
    ADC $C5
    BPL .c2bf_pos_st10
    CMP #$E0
    BCS .c2bf_pos_st10
    LDA #$E0
.c2bf_pos_st10:
    STA.w $4C11,X
    LDA.w $485C,X
    STA.w $4C1C,X
    CLC
    ADC $C5
    BPL .c2bf_pos_st11
    CMP #$E0
    BCS .c2bf_pos_st11
    LDA #$E0
.c2bf_pos_st11:
    STA.w $4C19,X
    REP #$20
    LDA.w $4806,X
    STA.w $4BC6,X
    LDA.w $480E,X
    STA.w $4BCE,X
    LDA.w $4816,X
    STA.w $4BD6,X
    LDA.w $481E,X
    STA.w $4BDE,X
    LDA.w $4826,X
    STA.w $4BE6,X
    LDA.w $482E,X
    STA.w $4BEE,X
    LDA.w $4836,X
    STA.w $4BF6,X
    LDA.w $483E,X
    STA.w $4BFE,X
    LDA.w $4846,X
    STA.w $4C06,X
    LDA.w $484E,X
    STA.w $4C0E,X
    LDA.w $4856,X
    STA.w $4C16,X
    LDA.w $485E,X
    STA.w $4C1E,X
    SEP #$20
    PLB
    RTS

    ; ── C6≠0: raw copy + BCS/BPL clamp (carry first, sign second), 12 tiles ──
    ; Same BCS/BPL ordering as Sub_BFF2 C6≠0 path.
.c2bf_nz:
    LDA.w $4804,X
    STA.w $4BC4,X
    CLC
    ADC $C5
    BCS .c2bf_nz_cl0
    BPL .c2bf_nz_st0
.c2bf_nz_cl0:
    LDA #$E0
.c2bf_nz_st0:
    STA.w $4BC1,X
    LDA.w $480C,X
    STA.w $4BCC,X
    CLC
    ADC $C5
    BCS .c2bf_nz_cl1
    BPL .c2bf_nz_st1
.c2bf_nz_cl1:
    LDA #$E0
.c2bf_nz_st1:
    STA.w $4BC9,X
    LDA.w $4814,X
    STA.w $4BD4,X
    CLC
    ADC $C5
    BCS .c2bf_nz_cl2
    BPL .c2bf_nz_st2
.c2bf_nz_cl2:
    LDA #$E0
.c2bf_nz_st2:
    STA.w $4BD1,X
    LDA.w $481C,X
    STA.w $4BDC,X
    CLC
    ADC $C5
    BCS .c2bf_nz_cl3
    BPL .c2bf_nz_st3
.c2bf_nz_cl3:
    LDA #$E0
.c2bf_nz_st3:
    STA.w $4BD9,X
    LDA.w $4824,X
    STA.w $4BE4,X
    CLC
    ADC $C5
    BCS .c2bf_nz_cl4
    BPL .c2bf_nz_st4
.c2bf_nz_cl4:
    LDA #$E0
.c2bf_nz_st4:
    STA.w $4BE1,X
    LDA.w $482C,X
    STA.w $4BEC,X
    CLC
    ADC $C5
    BCS .c2bf_nz_cl5
    BPL .c2bf_nz_st5
.c2bf_nz_cl5:
    LDA #$E0
.c2bf_nz_st5:
    STA.w $4BE9,X
    LDA.w $4834,X
    STA.w $4BF4,X
    CLC
    ADC $C5
    BCS .c2bf_nz_cl6
    BPL .c2bf_nz_st6
.c2bf_nz_cl6:
    LDA #$E0
.c2bf_nz_st6:
    STA.w $4BF1,X
    LDA.w $483C,X
    STA.w $4BFC,X
    CLC
    ADC $C5
    BCS .c2bf_nz_cl7
    BPL .c2bf_nz_st7
.c2bf_nz_cl7:
    LDA #$E0
.c2bf_nz_st7:
    STA.w $4BF9,X
    LDA.w $4844,X
    STA.w $4C04,X
    CLC
    ADC $C5
    BCS .c2bf_nz_cl8
    BPL .c2bf_nz_st8
.c2bf_nz_cl8:
    LDA #$E0
.c2bf_nz_st8:
    STA.w $4C01,X
    LDA.w $484C,X
    STA.w $4C0C,X
    CLC
    ADC $C5
    BCS .c2bf_nz_cl9
    BPL .c2bf_nz_st9
.c2bf_nz_cl9:
    LDA #$E0
.c2bf_nz_st9:
    STA.w $4C09,X
    LDA.w $4854,X
    STA.w $4C14,X
    CLC
    ADC $C5
    BCS .c2bf_nz_cl10
    BPL .c2bf_nz_st10
.c2bf_nz_cl10:
    LDA #$E0
.c2bf_nz_st10:
    STA.w $4C11,X
    LDA.w $485C,X
    STA.w $4C1C,X
    CLC
    ADC $C5
    BCS .c2bf_nz_cl11
    BPL .c2bf_nz_st11
.c2bf_nz_cl11:
    LDA #$E0
.c2bf_nz_st11:
    STA.w $4C19,X
    REP #$20
    LDA.w $4806,X
    STA.w $4BC6,X
    LDA.w $480E,X
    STA.w $4BCE,X
    LDA.w $4816,X
    STA.w $4BD6,X
    LDA.w $481E,X
    STA.w $4BDE,X
    LDA.w $4826,X
    STA.w $4BE6,X
    LDA.w $482E,X
    STA.w $4BEE,X
    LDA.w $4836,X
    STA.w $4BF6,X
    LDA.w $483E,X
    STA.w $4BFE,X
    LDA.w $4846,X
    STA.w $4C06,X
    LDA.w $484E,X
    STA.w $4C0E,X
    LDA.w $4856,X
    STA.w $4C16,X
    LDA.w $485E,X
    STA.w $4C1E,X
    SEP #$20
    PLB
    RTS

; ============================================================
; $C0:E12A — Sub_E12A (1034 bytes, $E12A–$E533)
; Sprite init pass: fills WRAM staging buffer at $7F:3800 from scene
; data, DMAs it to VRAM (destination word-addr $0400), then populates
; the OAM staging buffer at $7F:4BC2+X with palette values, tile
; indices, and attribute bytes for 24 sprite sub-slots (stride $08).
;
; On entry: X = sprite-slot index (16-bit), M=1 (8-bit A), DP=$0100.
; Source arrays (indexed by slot):
;   $1200+slot  → dp:$CF  (sprite type/bank byte)
;   $1280+slot  → dp:$CD/$CE  (sprite-data ptr offset; bank=$7F via $D2)
;   $1300+slot  → dp:$D5  (scene-data bank for [$D3] pointer)
;   $1380+slot  → dp:$D3/$D4  (scene-data ptr offset)
;   $1700+slot  → X (OAM staging buffer X offset for $7F:4BC2 writes)
; Calls Sub_E534 (bit 14 of scene word set: multi-tile WRAM fill)
;   and Sub_E687 (bit 14 clear: single WMDATA write per entry).
; ============================================================
org $C0E12A
Sub_E12A:
; Phase 1: Load descriptor arrays, set up [$CD] and [$D3] pointers.
    LDA $1200,X             ; sprite type byte for this slot
    STA $CF                 ; dp:$CF = sprite type
    LDA #$7F
    STA $D2                 ; dp:$D2 = $7F (bank byte for [$CD] pointer)
    REP #$20                ; A → 16-bit
    LDA $1280,X             ; sprite data pointer offset (bank $7F)
    STA $CD                 ; dp:$CD/$CE; [$CD] → $7F:XXXX
    SEP #$20                ; A → 8-bit
    REP #$20                ; A → 16-bit
    LDX $6D                 ; X = slot index (re-read; was unchanged)
    LDA #$3800              ; WRAM staging buffer base
    STA $0D80,X             ; $0D80+slot = $3800 (chunk base address)
    STA $D0                 ; dp:$D0 = $3800 (running WMADDL pointer)
    SEP #$20                ; A → 8-bit
    LDA #$00
    STA $0F01,X             ; $0F01+slot = 0 (clear sprite-state flag)
    LDA $1300,X             ; scene-data bank byte for this slot
    STA $D5                 ; dp:$D5 = bank for [$D3] pointer
    REP #$20                ; A → 16-bit
    LDA $1380,X             ; scene-data pointer offset
    STA $D3                 ; dp:$D3/$D4; [$D3] → $D5:XXXX (scene data)
; Phase 2: Set WRAM address registers, then loop 96× dispatching scene
; data words.  Bit 14 of each word: 0 → Sub_E687 (WMDATA write),
;                                    1 → Sub_E534 (multi-tile fill).
; WRAM address advances by $0020 per iteration.
    SEP #$30                ; A,X,Y → 8-bit (for 1-byte WMADDH write)
    LDA #$01
    STA $2183               ; WMADDH = $01 (WRAM address high byte)
    REP #$30                ; A,X,Y → 16-bit
    LDA $D0
    STA $2181               ; WMADDL = $3800 (full WRAM addr: $01:3800)
    LDA #$0060              ; loop counter = 96 entries
    STA $C9                 ; dp:$C9 = $60
    LDY #$0000              ; Y = scene-data word table index
    BRA .first_iter         ; skip address advance on first iteration
.next_iter:
    LDA $D0                 ; advance running WRAM write address
    CLC
    ADC #$0020
    STA $D0
.first_iter:
    LDA [$D3],Y             ; read 16-bit scene-data word
    BIT #$4000              ; test bit 14
    BNE .big_fill           ; set → multi-tile WRAM fill
    JSR Sub_E687               ; clear → single WMDATA write
    INY
    INY                     ; Y += 2 (advance to next 16-bit entry)
    DEC $C9
    BNE .next_iter
    BRA .dma
.big_fill:
    JSR Sub_E534               ; multi-tile WRAM fill
    INY
    INY
    DEC $C9
    BNE .next_iter
; Phase 3: DMA $0C00 bytes from $7F:3800 → VRAM at word-addr $0400.
.dma:
    SEP #$20                ; A → 8-bit
    LDA #$80
    STA $2115               ; VMAIN = $80 (word-addr, inc after high byte)
    LDA #$18
    STA $4371               ; BBAD7 = $18 (VMDATA port)
    LDA #$01
    STA $4370               ; DMAP7 = $01 (CPU→PPU, auto-inc, word)
    LDA #$7F
    STA $4374               ; A1B7 = $7F (source bank)
    LDY #$0400
    STY $2116               ; VMADDL = $0400 (VRAM destination)
    LDY #$3800
    STY $4372               ; A1T7L = $3800 (DMA source offset)
    LDY #$0C00
    STY $4375               ; DAS7L = $0C00 (transfer byte count)
    LDA #$80
    STA $420B               ; MDMAEN = $80 (trigger DMA channel 7)
; Phase 4: Populate OAM staging buffer $7F:4BC2+X.
; X is loaded from $1700+slot and used as the long-indexed X offset.
; 24 groups of 8 bytes (stride $08, bases $4BC2/$4BCA/$4BD2/…/$4C7A).
; Each group: [+0] = signed value, [+1] = sign-ext, [+2] = raw value.
; Scene data read from [$D3]+$C0 onward, 2 bytes consumed per group.
    REP #$20                ; A → 16-bit
    LDX $6D                 ; X = slot index
    LDA $1700,X             ; OAM staging buffer X offset for this slot
    REP #$10                ; X → 16-bit (ensure width)
    TAX                     ; X = OAM staging offset
    SEP #$20                ; A → 8-bit
    LDY #$00C0              ; Y = scene-data palette section start
; 24 palette groups (each: signed+sign-ext at base+0/1, raw at base+2)
    LDA [$D3],Y             ; group 1 signed value
    STA.l $7F4BC2,X
    BPL .sp01
    LDA #$FF
    BRA .se01
.sp01:
    LDA #$00
.se01:
    STA.l $7F4BC3,X
    INY
    LDA [$D3],Y
    STA.l $7F4BC4,X         ; group 1 raw value
    INY
    LDA [$D3],Y             ; group 2 signed value
    STA.l $7F4BCA,X
    BPL .sp02
    LDA #$FF
    BRA .se02
.sp02:
    LDA #$00
.se02:
    STA.l $7F4BCB,X
    INY
    LDA [$D3],Y
    STA.l $7F4BCC,X         ; group 2 raw
    INY
    LDA [$D3],Y             ; group 3 signed
    STA.l $7F4BD2,X
    BPL .sp03
    LDA #$FF
    BRA .se03
.sp03:
    LDA #$00
.se03:
    STA.l $7F4BD3,X
    INY
    LDA [$D3],Y
    STA.l $7F4BD4,X         ; group 3 raw
    INY
    LDA [$D3],Y             ; group 4 signed
    STA.l $7F4BDA,X
    BPL .sp04
    LDA #$FF
    BRA .se04
.sp04:
    LDA #$00
.se04:
    STA.l $7F4BDB,X
    INY
    LDA [$D3],Y
    STA.l $7F4BDC,X         ; group 4 raw
    INY
    LDA [$D3],Y             ; group 5 signed
    STA.l $7F4BE2,X
    BPL .sp05
    LDA #$FF
    BRA .se05
.sp05:
    LDA #$00
.se05:
    STA.l $7F4BE3,X
    INY
    LDA [$D3],Y
    STA.l $7F4BE4,X         ; group 5 raw
    INY
    LDA [$D3],Y             ; group 6 signed
    STA.l $7F4BEA,X
    BPL .sp06
    LDA #$FF
    BRA .se06
.sp06:
    LDA #$00
.se06:
    STA.l $7F4BEB,X
    INY
    LDA [$D3],Y
    STA.l $7F4BEC,X         ; group 6 raw
    INY
    LDA [$D3],Y             ; group 7 signed
    STA.l $7F4BF2,X
    BPL .sp07
    LDA #$FF
    BRA .se07
.sp07:
    LDA #$00
.se07:
    STA.l $7F4BF3,X
    INY
    LDA [$D3],Y
    STA.l $7F4BF4,X         ; group 7 raw
    INY
    LDA [$D3],Y             ; group 8 signed
    STA.l $7F4BFA,X
    BPL .sp08
    LDA #$FF
    BRA .se08
.sp08:
    LDA #$00
.se08:
    STA.l $7F4BFB,X
    INY
    LDA [$D3],Y
    STA.l $7F4BFC,X         ; group 8 raw
    INY
    LDA [$D3],Y             ; group 9 signed
    STA.l $7F4C02,X
    BPL .sp09
    LDA #$FF
    BRA .se09
.sp09:
    LDA #$00
.se09:
    STA.l $7F4C03,X
    INY
    LDA [$D3],Y
    STA.l $7F4C04,X         ; group 9 raw
    INY
    LDA [$D3],Y             ; group 10 signed
    STA.l $7F4C0A,X
    BPL .sp10
    LDA #$FF
    BRA .se10
.sp10:
    LDA #$00
.se10:
    STA.l $7F4C0B,X
    INY
    LDA [$D3],Y
    STA.l $7F4C0C,X         ; group 10 raw
    INY
    LDA [$D3],Y             ; group 11 signed
    STA.l $7F4C12,X
    BPL .sp11
    LDA #$FF
    BRA .se11
.sp11:
    LDA #$00
.se11:
    STA.l $7F4C13,X
    INY
    LDA [$D3],Y
    STA.l $7F4C14,X         ; group 11 raw
    INY
    LDA [$D3],Y             ; group 12 signed
    STA.l $7F4C1A,X
    BPL .sp12
    LDA #$FF
    BRA .se12
.sp12:
    LDA #$00
.se12:
    STA.l $7F4C1B,X
    INY
    LDA [$D3],Y
    STA.l $7F4C1C,X         ; group 12 raw
    INY
    LDA [$D3],Y             ; group 13 signed
    STA.l $7F4C22,X
    BPL .sp13
    LDA #$FF
    BRA .se13
.sp13:
    LDA #$00
.se13:
    STA.l $7F4C23,X
    INY
    LDA [$D3],Y
    STA.l $7F4C24,X         ; group 13 raw
    INY
    LDA [$D3],Y             ; group 14 signed
    STA.l $7F4C2A,X
    BPL .sp14
    LDA #$FF
    BRA .se14
.sp14:
    LDA #$00
.se14:
    STA.l $7F4C2B,X
    INY
    LDA [$D3],Y
    STA.l $7F4C2C,X         ; group 14 raw
    INY
    LDA [$D3],Y             ; group 15 signed
    STA.l $7F4C32,X
    BPL .sp15
    LDA #$FF
    BRA .se15
.sp15:
    LDA #$00
.se15:
    STA.l $7F4C33,X
    INY
    LDA [$D3],Y
    STA.l $7F4C34,X         ; group 15 raw
    INY
    LDA [$D3],Y             ; group 16 signed
    STA.l $7F4C3A,X
    BPL .sp16
    LDA #$FF
    BRA .se16
.sp16:
    LDA #$00
.se16:
    STA.l $7F4C3B,X
    INY
    LDA [$D3],Y
    STA.l $7F4C3C,X         ; group 16 raw
    INY
    LDA [$D3],Y             ; group 17 signed
    STA.l $7F4C42,X
    BPL .sp17
    LDA #$FF
    BRA .se17
.sp17:
    LDA #$00
.se17:
    STA.l $7F4C43,X
    INY
    LDA [$D3],Y
    STA.l $7F4C44,X         ; group 17 raw
    INY
    LDA [$D3],Y             ; group 18 signed
    STA.l $7F4C4A,X
    BPL .sp18
    LDA #$FF
    BRA .se18
.sp18:
    LDA #$00
.se18:
    STA.l $7F4C4B,X
    INY
    LDA [$D3],Y
    STA.l $7F4C4C,X         ; group 18 raw
    INY
    LDA [$D3],Y             ; group 19 signed
    STA.l $7F4C52,X
    BPL .sp19
    LDA #$FF
    BRA .se19
.sp19:
    LDA #$00
.se19:
    STA.l $7F4C53,X
    INY
    LDA [$D3],Y
    STA.l $7F4C54,X         ; group 19 raw
    INY
    LDA [$D3],Y             ; group 20 signed
    STA.l $7F4C5A,X
    BPL .sp20
    LDA #$FF
    BRA .se20
.sp20:
    LDA #$00
.se20:
    STA.l $7F4C5B,X
    INY
    LDA [$D3],Y
    STA.l $7F4C5C,X         ; group 20 raw
    INY
    LDA [$D3],Y             ; group 21 signed
    STA.l $7F4C62,X
    BPL .sp21
    LDA #$FF
    BRA .se21
.sp21:
    LDA #$00
.se21:
    STA.l $7F4C63,X
    INY
    LDA [$D3],Y
    STA.l $7F4C64,X         ; group 21 raw
    INY
    LDA [$D3],Y             ; group 22 signed
    STA.l $7F4C6A,X
    BPL .sp22
    LDA #$FF
    BRA .se22
.sp22:
    LDA #$00
.se22:
    STA.l $7F4C6B,X
    INY
    LDA [$D3],Y
    STA.l $7F4C6C,X         ; group 22 raw
    INY
    LDA [$D3],Y             ; group 23 signed
    STA.l $7F4C72,X
    BPL .sp23
    LDA #$FF
    BRA .se23
.sp23:
    LDA #$00
.se23:
    STA.l $7F4C73,X
    INY
    LDA [$D3],Y
    STA.l $7F4C74,X         ; group 23 raw
    INY
    LDA [$D3],Y             ; group 24 signed (last group)
    STA.l $7F4C7A,X
    BPL .sp24
    LDA #$FF
    BRA .se24
.sp24:
    LDA #$00
.se24:
    STA.l $7F4C7B,X
    INY
    LDA [$D3],Y
    STA.l $7F4C7C,X         ; group 24 raw (no trailing INY)
; Phase 5: Write tile-index bytes to [+4] of each of the 24 groups.
; Groups 1-8:  $40,$42,$44,$46,$48,$4A,$4C,$4E
; Groups 9-16: $60,$62,$64,$66,$68,$6A,$6C,$6E
; Groups 17-24:$80,$82,$84,$86,$88,$8A,$8C,$8E
    LDA #$40
    STA.l $7F4BC6,X
    LDA #$42
    STA.l $7F4BCE,X
    LDA #$44
    STA.l $7F4BD6,X
    LDA #$46
    STA.l $7F4BDE,X
    LDA #$48
    STA.l $7F4BE6,X
    LDA #$4A
    STA.l $7F4BEE,X
    LDA #$4C
    STA.l $7F4BF6,X
    LDA #$4E
    STA.l $7F4BFE,X
    LDA #$60
    STA.l $7F4C06,X
    LDA #$62
    STA.l $7F4C0E,X
    LDA #$64
    STA.l $7F4C16,X
    LDA #$66
    STA.l $7F4C1E,X
    LDA #$68
    STA.l $7F4C26,X
    LDA #$6A
    STA.l $7F4C2E,X
    LDA #$6C
    STA.l $7F4C36,X
    LDA #$6E
    STA.l $7F4C3E,X
    LDA #$80
    STA.l $7F4C46,X
    LDA #$82
    STA.l $7F4C4E,X
    LDA #$84
    STA.l $7F4C56,X
    LDA #$86
    STA.l $7F4C5E,X
    LDA #$88
    STA.l $7F4C66,X
    LDA #$8A
    STA.l $7F4C6E,X
    LDA #$8C
    STA.l $7F4C76,X
    LDA #$8E
    STA.l $7F4C7E,X
; Phase 6: Write attribute byte $22 to [+5] of each of the 24 groups.
    LDA #$22                ; OAM attribute byte
    STA.l $7F4BC7,X
    STA.l $7F4BCF,X
    STA.l $7F4BD7,X
    STA.l $7F4BDF,X
    STA.l $7F4BE7,X
    STA.l $7F4BEF,X
    STA.l $7F4BF7,X
    STA.l $7F4BFF,X
    STA.l $7F4C07,X
    STA.l $7F4C0F,X
    STA.l $7F4C17,X
    STA.l $7F4C1F,X
    STA.l $7F4C27,X
    STA.l $7F4C2F,X
    STA.l $7F4C37,X
    STA.l $7F4C3F,X
    STA.l $7F4C47,X
    STA.l $7F4C4F,X
    STA.l $7F4C57,X
    STA.l $7F4C5F,X
    STA.l $7F4C67,X
    STA.l $7F4C6F,X
    STA.l $7F4C77,X
    STA.l $7F4C7F,X
    RTS

; ============================================================
; $C0:E534 — Sub_E534 (339 bytes, $C0:E534–$E686)
; FD00-table WRAM fill: reads 32 sprite-data bytes through a palette-like
; lookup table at bank $FD ($FD00,X) and streams them to WRAM via WMDATA.
;
; On entry (from Sub_E12A Phase 2, bit 14 of scene word set):
;   A = 16-bit scene-data word, Y = scene-data table index,
;   dp:$0A = base offset, dp:$CD/$CE = sprite-data ptr (bank $7F),
;   WMADDL/WMADDH already set for current WRAM position.
; Computes byte index = ((A & $FF) | [$0A]) << 4 (M=1 encoding):
; reads 32 bytes from [$CD]+index, looks each up in $FD00, writes to WMDATA.
; Note: the header bytes 29 FF 07 0A*4 are a byte-identity shared with
; Sub_E687 — valid as M=1 "AND #$FF / ORA[$0A] / 4×ASL" or M=0 "AND #$07FF / 5×ASL".
; Returns with 16-bit A restored, Y restored from dp:$C5.
; ============================================================
org $C0E534
Sub_E534:
    AND #$FF                ; mask low byte (M=1 encoding: 29 FF)
    ORA [$0A]               ; merge with dp:[$0A] indirect long
    ASL
    ASL
    ASL
    ASL                     ; × 16: sprite-data byte index
    STY $C5                 ; save Y
    TAY                     ; Y = sprite-data byte index
    SEP #$20                ; A → 8-bit
    TDC                     ; A = DP (clears A)
    XBA                     ; ensure A high byte = 0
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 1)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 2)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 3)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 4)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 5)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 6)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 7)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 8)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 9)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 10)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 11)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 12)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 13)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 14)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 15)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 16)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 17)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 18)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 19)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 20)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 21)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 22)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 23)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 24)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 25)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 26)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 27)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 28)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 29)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 30)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 31)
    INY
    LDA [$CD],Y
    TAX
    LDA $FD00,X
    STA $2180               ; WMDATA (byte 32 — no INY)
    REP #$20                ; A → 16-bit
    LDY $C5                 ; restore Y
    RTS

; ============================================================
; $C0:E687 — Sub_E687 (178 bytes, $C0:E687–$E738)
; Bank-switched tile-data WRAM copy: copies 32 bytes (16 words) from a ROM
; graphics bank into WRAM at the address in dp:$D0.
;
; On entry (from Sub_E12A Phase 2, bit 14 of scene word clear):
;   A = 16-bit scene-data word, Y = scene-data table index,
;   dp:$0A = base offset, dp:$CD = sprite-data byte base,
;   dp:$CF = graphics bank selector, dp:$D0 = WRAM write address.
; Header (M=0 encoding here: AND #$07FF / 5×ASL ≡ same bytes as Sub_E534's header)
; computes source byte offset X = ((A & $07FF) << 5) + dp:$CD,
; loads WRAM address Y = dp:$D0, dispatches on dp:$CF:
;   $7F → Sub_E8C2, $D2 → Sub_E7BC, $D3 → Sub_E83F, $D4 → Sub_E739,
;   else → inline $D5 copy below.
; After copy: WMADDL = old_Y + $20, Y restored. Returns 16-bit A.
; ============================================================
org $C0E687
Sub_E687:
    AND #$07FF              ; (M=0: 29 FF 07) same bytes as Sub_E534's AND #$FF/ORA[$0A]
    ASL
    ASL
    ASL
    ASL
    ASL                     ; 5×ASL (same byte sequence as 4×ASL in M=1 above)
    STY $C5                 ; save Y
    CLC
    ADC $CD                 ; X = shifted offset + dp:$CD base
    TAX
    LDY $D0                 ; Y = WRAM write address
    SEP #$20                ; A → 8-bit for bank-selector dispatch
    LDA $CF                 ; graphics bank selector
    CMP #$7F
    BNE .not7f
    BRL Sub_E8C2               ; → Sub_E8C2 ($E8C2): copy from $7F using abs,X
.not7f:
    SEC
    SBC #$D2
    BNE .notd2
    BRL Sub_E7BC               ; → Sub_E7BC ($E7BC): copy from bank $D2
.notd2:
    DEC
    BNE .notd3
    BRL Sub_E83F               ; → Sub_E83F ($E83F): copy from bank $D3
.notd3:
    DEC
    BNE .d5copy             ; else → inline $D5 copy
    BRL Sub_E739               ; → Sub_E739 ($E739): copy from bank $D4
.d5copy:                    ; dp:$CF = $D5 (or unrecognised) → read from bank $D5
    PHB
    LDA #$7F                ; (M=1 after SEP above)
    PHA
    PLB                     ; DB = $7F
    REP #$20                ; A → 16-bit
    LDA $D50000,X
    STA.w $0000,Y
    LDA $D50002,X
    STA.w $0002,Y
    LDA $D50004,X
    STA.w $0004,Y
    LDA $D50006,X
    STA.w $0006,Y
    LDA $D50008,X
    STA.w $0008,Y
    LDA $D5000A,X
    STA.w $000A,Y
    LDA $D5000C,X
    STA.w $000C,Y
    LDA $D5000E,X
    STA.w $000E,Y
    LDA $D50010,X
    STA.w $0010,Y
    LDA $D50012,X
    STA.w $0012,Y
    LDA $D50014,X
    STA.w $0014,Y
    LDA $D50016,X
    STA.w $0016,Y
    LDA $D50018,X
    STA.w $0018,Y
    LDA $D5001A,X
    STA.w $001A,Y
    LDA $D5001C,X
    STA.w $001C,Y
    LDA $D5001E,X
    STA.w $001E,Y
    PLB
    TYA
    CLC
    ADC #$0020
    STA.w $2181             ; WMADDL = old_Y + $20
    LDY $C5                 ; restore Y
    RTS

; ============================================================
; $C0:E739 — Sub_E739 (131 bytes, $C0:E739–$E7BB)
; Bank-$D4 tile-data WRAM copy: 16 words from $D4:index → $7F:Y.
; Tail-called via BRL from Sub_E687 when dp:$CF = $D4.
; X = source byte offset, Y = WRAM write address (both from Sub_E687).
; ============================================================
org $C0E739
Sub_E739:
    PHB
    db $A9,$7F              ; LDA #$7F (db: M=1 byte encoding in M=0 asar context)
    PHA
    PLB                     ; DB = $7F
    REP #$20                ; A → 16-bit
    LDA $D40000,X
    STA.w $0000,Y
    LDA $D40002,X
    STA.w $0002,Y
    LDA $D40004,X
    STA.w $0004,Y
    LDA $D40006,X
    STA.w $0006,Y
    LDA $D40008,X
    STA.w $0008,Y
    LDA $D4000A,X
    STA.w $000A,Y
    LDA $D4000C,X
    STA.w $000C,Y
    LDA $D4000E,X
    STA.w $000E,Y
    LDA $D40010,X
    STA.w $0010,Y
    LDA $D40012,X
    STA.w $0012,Y
    LDA $D40014,X
    STA.w $0014,Y
    LDA $D40016,X
    STA.w $0016,Y
    LDA $D40018,X
    STA.w $0018,Y
    LDA $D4001A,X
    STA.w $001A,Y
    LDA $D4001C,X
    STA.w $001C,Y
    LDA $D4001E,X
    STA.w $001E,Y
    PLB
    TYA
    CLC
    ADC #$0020
    STA.w $2181             ; WMADDL = old_Y + $20
    LDY $C5
    RTS

; ============================================================
; $C0:E7BC — Sub_E7BC (131 bytes, $C0:E7BC–$E83E)
; Bank-$D2 tile-data WRAM copy: 16 words from $D2:index → $7F:Y.
; Tail-called via BRL from Sub_E687 when dp:$CF = $D2.
; ============================================================
org $C0E7BC
Sub_E7BC:
    PHB
    db $A9,$7F              ; LDA #$7F
    PHA
    PLB                     ; DB = $7F
    REP #$20
    LDA $D20000,X
    STA.w $0000,Y
    LDA $D20002,X
    STA.w $0002,Y
    LDA $D20004,X
    STA.w $0004,Y
    LDA $D20006,X
    STA.w $0006,Y
    LDA $D20008,X
    STA.w $0008,Y
    LDA $D2000A,X
    STA.w $000A,Y
    LDA $D2000C,X
    STA.w $000C,Y
    LDA $D2000E,X
    STA.w $000E,Y
    LDA $D20010,X
    STA.w $0010,Y
    LDA $D20012,X
    STA.w $0012,Y
    LDA $D20014,X
    STA.w $0014,Y
    LDA $D20016,X
    STA.w $0016,Y
    LDA $D20018,X
    STA.w $0018,Y
    LDA $D2001A,X
    STA.w $001A,Y
    LDA $D2001C,X
    STA.w $001C,Y
    LDA $D2001E,X
    STA.w $001E,Y
    PLB
    TYA
    CLC
    ADC #$0020
    STA.w $2181
    LDY $C5
    RTS

; ============================================================
; $C0:E83F — Sub_E83F (131 bytes, $C0:E83F–$E8C1)
; Bank-$D3 tile-data WRAM copy: 16 words from $D3:index → $7F:Y.
; Tail-called via BRL from Sub_E687 when dp:$CF = $D3.
; ============================================================
org $C0E83F
Sub_E83F:
    PHB
    db $A9,$7F              ; LDA #$7F
    PHA
    PLB                     ; DB = $7F
    REP #$20
    LDA $D30000,X
    STA.w $0000,Y
    LDA $D30002,X
    STA.w $0002,Y
    LDA $D30004,X
    STA.w $0004,Y
    LDA $D30006,X
    STA.w $0006,Y
    LDA $D30008,X
    STA.w $0008,Y
    LDA $D3000A,X
    STA.w $000A,Y
    LDA $D3000C,X
    STA.w $000C,Y
    LDA $D3000E,X
    STA.w $000E,Y
    LDA $D30010,X
    STA.w $0010,Y
    LDA $D30012,X
    STA.w $0012,Y
    LDA $D30014,X
    STA.w $0014,Y
    LDA $D30016,X
    STA.w $0016,Y
    LDA $D30018,X
    STA.w $0018,Y
    LDA $D3001A,X
    STA.w $001A,Y
    LDA $D3001C,X
    STA.w $001C,Y
    LDA $D3001E,X
    STA.w $001E,Y
    PLB
    TYA
    CLC
    ADC #$0020
    STA.w $2181
    LDY $C5
    RTS

; ============================================================
; $C0:E8C2 — Sub_E8C2 (115 bytes, $C0:E8C2–$E934)
; Bank-$7F tile-data WRAM copy: 16 words from $7F:index → $7F:Y.
; Tail-called via BRL from Sub_E687 when dp:$CF = $7F.
; Uses absolute,X (BD) rather than long,X (BF): DB is already $7F after PLB.
; ============================================================
org $C0E8C2
Sub_E8C2:
    PHB
    db $A9,$7F              ; LDA #$7F
    PHA
    PLB                     ; DB = $7F
    REP #$20
    LDA.w $0000,X           ; BD: abs,X (DB=$7F → reads $7F:0000+X)
    STA.w $0000,Y
    LDA.w $0002,X
    STA.w $0002,Y
    LDA.w $0004,X
    STA.w $0004,Y
    LDA.w $0006,X
    STA.w $0006,Y
    LDA.w $0008,X
    STA.w $0008,Y
    LDA.w $000A,X
    STA.w $000A,Y
    LDA.w $000C,X
    STA.w $000C,Y
    LDA.w $000E,X
    STA.w $000E,Y
    LDA.w $0010,X
    STA.w $0010,Y
    LDA.w $0012,X
    STA.w $0012,Y
    LDA.w $0014,X
    STA.w $0014,Y
    LDA.w $0016,X
    STA.w $0016,Y
    LDA.w $0018,X
    STA.w $0018,Y
    LDA.w $001A,X
    STA.w $001A,Y
    LDA.w $001C,X
    STA.w $001C,Y
    LDA.w $001E,X
    STA.w $001E,Y
    PLB
    TYA
    CLC
    ADC #$0020
    STA.w $2181
    LDY $C5
    RTS

; ============================================================
; $C0:E935 — Sub_E935 (29 bytes, $E935–$E951)
; Initialize 8 sprite-slot "uninitialized" flags at $0BC0-$0BC7 to $80.
; Sets DP=$0B00, stores LDA #$80 to dp:$C0-$C7 (= abs $0BC0-$0BC7),
; then PLD / RTS.
; Tail-called via BRL from Obj_ResetStates at end of sprite table clear.
; $80 in these slots means "no sprite assigned" (tested in Sub_E9E2/E9FF).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP restored by PLD before call.
; ============================================================
org $C0E935
Sub_E935:
    PHD
    REP #$20                ; A → 16-bit
    LDA #$0B00
    TCD                     ; DP = $0B00
    SEP #$20                ; A → 8-bit
    LDA #$80                ; "uninitialized" sentinel
    STA $C0                 ; dp:$C0 = $0BC0
    STA $C1
    STA $C2
    STA $C3
    STA $C4
    STA $C5
    STA $C6
    STA $C7                 ; dp:$C7 = $0BC7
    PLD
    RTS

; ============================================================
; $C0:E952 — Sub_E952 (40 bytes, $E952–$E979)
; Sprite slot allocator — single-slot variant.
; Scans $0BC0[0..3] for the first entry whose value is negative
; ($80 = free sentinel set by Sub_E935).  Claims the entry by
; writing dp:$6D there, then computes the WRAM staging-buffer base
; address for that sprite slot: $3800 + slotIndex×$0200 (so entries
; 0–3 map to $3800/$3A00/$3C00/$3E00) and stores the result in
; $0D80+dp:$6D.
; Returns: SEC on success (slot allocated), CLC if table is full.
; On entry: M=1 (8-bit A), X=0 (8-bit X/Y), DP=$0100.
; Called from: $CC0D.
; ============================================================
org $C0E952
Sub_E952:
    LDX #$00
.e952_loop:
    LDA $0BC0,X          ; read slot entry X
    BPL .e952_next       ; $00–$7F = occupied → skip
    LDA $6D              ; $80+ = free → claim: store slot id
    STA $0BC0,X
    TXA                  ; A.lo = table index (0–3)
    XBA                  ; A.hi ← index; A.lo ← 0
    REP #$20             ; A → 16-bit
    AND #$FF00           ; isolate high byte (= index × $0100)
    ASL                  ; × 2  → index × $0200
    CLC
    ADC #$3800           ; WRAM base: $3800 + index × $0200
    LDX $6D              ; X = sprite slot id
    STA $0D80,X          ; $0D80+slot ← staging-buffer base
    SEP #$20             ; A → 8-bit
    SEC                  ; success
    RTS
.e952_next:
    INX
    CPX #$04
    BMI .e952_loop       ; loop for entries 0–3
    CLC                  ; table full — no slot found
    RTS

; ============================================================
; $C0:E97A — Sub_E97A (48 bytes, $E97A–$E9A9)
; Sprite slot allocator — dual-slot variant.
; Like Sub_E952 but requires BOTH $0BC0[X] and $0BC1[X] to be free.
; Claims both entries with dp:$6D; WRAM base computation is identical.
; Searches entries 0–2 (CPX #$03) since adjacent pairs overlap:
; position 0 → ($0BC0,$0BC1), position 1 → ($0BC1,$0BC2), etc.
; Returns: SEC on success, CLC on failure.
; On entry: M=1 (8-bit A), X=0 (8-bit X/Y), DP=$0100.
; Called from: $CF2D, $D299.
; ============================================================
org $C0E97A
Sub_E97A:
    LDX #$00
.e97a_loop:
    LDA $0BC0,X          ; check first sub-slot
    BPL .e97a_next       ; occupied → skip
    LDA $0BC1,X          ; check second sub-slot
    BPL .e97a_next       ; occupied → skip
    LDA $6D              ; both free → claim both
    STA $0BC0,X
    STA $0BC1,X
    TXA
    XBA
    REP #$20
    AND #$FF00
    ASL
    CLC
    ADC #$3800
    LDX $6D
    STA $0D80,X
    SEP #$20
    SEC
    RTS
.e97a_next:
    INX
    CPX #$03             ; search entries 0–2 (3 positions)
    BMI .e97a_loop
    CLC
    RTS

; ============================================================
; $C0:E9AA — Sub_E9AA (56 bytes, $E9AA–$E9E1)
; Sprite slot allocator — triple-slot variant.
; Requires $0BC0[X], $0BC1[X], and $0BC2[X] all free; searches only
; entries 0–1 (CPX #$02) since three consecutive sub-slots fit in two
; starting positions.  Claims all three with dp:$6D; same WRAM base.
; Returns: SEC on success, CLC on failure.
; On entry: M=1 (8-bit A), X=0 (8-bit X/Y), DP=$0100.
; Called from: $D555, $D617.
; ============================================================
org $C0E9AA
Sub_E9AA:
    LDX #$00
.e9aa_loop:
    LDA $0BC0,X
    BPL .e9aa_next
    LDA $0BC1,X
    BPL .e9aa_next
    LDA $0BC2,X
    BPL .e9aa_next
    LDA $6D              ; all three free → claim
    STA $0BC0,X
    STA $0BC1,X
    STA $0BC2,X
    TXA
    XBA
    REP #$20
    AND #$FF00
    ASL
    CLC
    ADC #$3800
    LDX $6D
    STA $0D80,X
    SEP #$20
    SEC
    RTS
.e9aa_next:
    INX
    CPX #$02             ; only entries 0–1 for triple allocation
    BMI .e9aa_loop
    CLC
    RTS

org $C0E9E2
Sub_E9E2:
    ; 29 bytes ($E9E2-$E9FE). Entry M=1, X=1.
    ; Searches 4-entry table at $0BC0 for the current sprite slot ($6D),
    ; then marks the matching entry with $80.
    SEP #$10
    LDX $6D
    LDX #$00
.e9e2_loop:
    LDA.w $0BC0,X
    CMP $6D
    BEQ .e9e2_found
    INX
    CPX #$04
    BNE .e9e2_loop
    REP #$10
    RTS
.e9e2_found:
    LDA #$80
    STA.w $0BC0,X
    REP #$10
    RTS

org $C0E9FF
Sub_E9FF:
    ; 32 bytes ($E9FF-$EA1E). Entry M=1, X=1.
    ; Searches 3-entry table at $0BC0 for slot $6D; marks match with $80 in
    ; both $0BC0,X and $0BC1,X (two entries). Loop limit CPX #$03 vs Sub_E9E2's #$04.
    SEP #$10
    LDX $6D
    LDX #$00
.e9ff_loop:
    LDA.w $0BC0,X
    CMP $6D
    BEQ .e9ff_found
    INX
    CPX #$03
    BNE .e9ff_loop
    REP #$10
    RTS
.e9ff_found:
    LDA #$80
    STA.w $0BC0,X
    STA.w $0BC1,X
    REP #$10
    RTS

org $C0EA1F
Sub_EA1F:
    ; 35 bytes ($EA1F–$EA41). Entry M=1, X=0 (16-bit).
    ; Types 2/3+ init pass 2: searches 2-entry table at $0BC0 for sprite
    ; slot $6D; marks $0BC0,X $0BC1,X $0BC2,X with $80 (3 OAM slots).
    SEP #$10                ; X → 8-bit
    LDX $6D                 ; (discarded; immediately overwritten)
    LDX #$00                ; X = 0 (loop counter)
.ea1f_loop:
    LDA.w $0BC0,X           ; table entry X
    CMP $6D                 ; match sprite slot?
    BEQ .ea1f_found
    INX
    CPX #$02                ; 2-entry table (0,1)
    BNE .ea1f_loop
    REP #$10                ; X → 16-bit (no match)
    RTS
.ea1f_found:
    LDA #$80
    STA.w $0BC0,X           ; mark slot (byte 0)
    STA.w $0BC1,X           ; mark slot (byte 1)
    STA.w $0BC2,X           ; mark slot (byte 2)
    REP #$10                ; X → 16-bit
    RTS

; ============================================================
; $C0:0000 — ReentryVectors (14 bytes)
; Mid-game JSL re-entry vector table.  Other banks JSL into one of
; these entries; the BRA/BRL tail-dispatches to the target routine,
; and its RTL returns directly to the JSL caller.
;   [0] $0000  BRA → GameLoop_Main  (warm restart; no RTL return)
;   [1] $0002  JSL → ScrollStepAccum  ($C0:2C41)
;   [2] $0005  JSL → AudioDrvSync     ($C0:0AFF)
;   [3] $0008  JSL → MusicCueDispatch ($C0:1BAB)
;   [4] $000B  JSL → AudioFadeDispatch($C0:1BE6)
; ============================================================
org $C00000

ReentryVectors:
    BRA GameLoop_Main       ; [0] warm restart — skip init, enter frame loop
    BRL ScrollStepAccum     ; [1] $C0:2C41
    BRL AudioDrvSync        ; [2] $C0:0AFF
    BRL MusicCueDispatch    ; [3] $C0:1BAB
    BRL AudioFadeDispatch   ; [4] $C0:1BE6

; ============================================================
; $C0:000E — GameLoop: one-time startup init (from MainInit)
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$2100, DB=$00
; ============================================================
GameLoop:
    SEP #$20                ; M=1: A → 8-bit (safety)
    REP #$10                ; X=0: X/Y → 16-bit

    ; Install RAM-resident interrupt handlers first — they live at
    ; $7E:0500/$7E:0504, which are deliberately NOT cleared below.
    JSR InstallNMI          ; JML NmiHandler at $7E:0500
    JSR InstallIRQ          ; JML IrqHandler at $7E:0504

    REP #$20                ; A → 16-bit for TCD
    LDA.w #!DP_Field
    TCD                     ; DP = $0100 (WRAM variable page)
    SEP #$20                ; A → 8-bit

    JSR InitHW              ; disable hardware (SEI, forced blank, no NMI/DMA)

    ; Clear WRAM block 1: $7E:0000-04FF (1280 bytes, stops before handlers)
    LDX.w #!Boot_ClearLowSize
    STX.b !DmaFill_Size
    LDX #$0000
    STX.b !DmaFill_Dest
    LDA.b #!Bank7E
    STA.b !DmaFill_Bank
    JSR ClearRAMDMA         ; DMA fill with 0

    ; Clear WRAM block 2: $7E:0700-FFFF (59648 bytes)
    LDX.w #!Boot_ClearMainSize
    STX.b !DmaFill_Size
    LDX.w #!Boot_ClearMainStart
    STX.b !DmaFill_Dest
    LDA.b #!Bank7E
    STA.b !DmaFill_Bank
    JSR ClearRAMDMA

    ; Clear WRAM block 3: $7F:5080-A0FF (20608 bytes)
    LDX.w #!Boot_Clear7FStart
    STX.b !DmaFill_Size
    STX.b !DmaFill_Dest     ; count == dest addr (both $5080)
    LDA.b #!Bank7F
    STA.b !DmaFill_Bank
    JSR ClearRAMDMA

    JSL Audio_DriverInit    ; sound driver init (bank $C7)
    LDA.b #!BankC2_BootArg
    JSL BankC2_Entry8004

GameLoop_Main:
    JSR InitHW              ; forced blank, disable NMI/DMA
    JSR InstallNMI          ; reinstall NMI handler
    JSR InstallIRQ          ; reinstall IRQ handler

    ; Dispatch on the location index (Loc_Id, WRAM $0100, 16-bit)
    LDX.w !DP_Field+!Loc_Id
    CPX.w #!Loc_FirstBankC2
    BMI GL_ModeOk1
    JML BankC2_Entry0000    ; Loc_Id >= $01F0 → handled in bank $C2

GL_ModeOk1:
    CPX.w #!Loc_LoadSave
    BMI GL_ModeOk2
    LDX.w #!LoadSave_EntryX
    BRL LoadSavePath               ; → LoadSavePath ($2E1E)

GL_ModeOk2:
    REP #$20
    LDA.w #!DP_Field
    TCD                     ; DP = $0100
    SEP #$20

    JSR FrameStateInit      ; reset the field page for this location
    JSR LoadLocation        ; location-load steps (10 JSR + 2 JSL)
    JSR Obj_ResetStates     ; clear Obj_State, then Sub_E935
    JSR Scene_PostLoadInit
    JSR TileAnimList_Clear
    JSR Scene_SettleFrames  ; run frames until the new scene reports ready

GameLoop_FrameBody:
    LDA.w !Pad_Pressed
    TSB.b !Pad_PressedLatch ; accumulate newly pressed buttons
    LDA.w !Pad_Unk00F6
    TSB.b !Pad_Unk00F6Latch ; accumulate Pad_Unk00F6
    JSR Field_PauseAndMenuInput
    JSR Field_SceneChangeTick
    JSR Field_FrameUpdate
    JSR Field_Unk1AAC
    JSL Field_Unk1F87
    JSR Field_EventHookDispatch
    JSR Field_Unk274D
    JSR VBlankHandler       ; sync to VBlank (tail-jumps via BRL to PostVBlank)
    JSR Sub_EC60
    BRA GameLoop_FrameBody

; ============================================================
; $C0:00BF — VBlankHandler
; End-of-frame work, called once per frame from GameLoop_FrameBody
; (not an interrupt handler despite the name): Vblank_* helpers,
; EngFD_UnkC2C1, FdVec_FFF7 (earlier notes: waits for VBlank),
; Field_ProcessAnimQueue, then tail-jumps to PostVBlank, whose RTS
; returns to this routine's caller.
; ============================================================
VBlankHandler:
    SEP #$10                ; X/Y → 8-bit
    JSR Vblank_Unk59D9
    JSR Vblank_ReadScanlineCounters
    JSL EngFD_UnkC2C1
    REP #$10                ; X/Y → 16-bit
    JSL FdVec_FFF7
    SEP #$10
    JSR Vblank_UnkA810
    JSR Field_ProcessAnimQueue
    REP #$10
    BRL PostVBlank-!BankWrap ; offset wraps around the bank to $B271

; VBlankHandlerShort: the EngFD_UnkC2C1 + FdVec_FFF7 part only.
VBlankHandlerShort:
    SEP #$10
    JSL EngFD_UnkC2C1
    REP #$10
    JSL FdVec_FFF7
    RTS

; Field_IdleFrame (was Sub_00EB): one frame of field upkeep without
; game logic: Field_FrameUpdate, VBlankHandlerShort, Sub_EC60.
Field_IdleFrame:
    JSR Field_FrameUpdate
    JSR VBlankHandlerShort
    BRL Sub_EC60-!BankWrap  ; offset wraps around the bank to $EC60

; ============================================================
; $C0:00F4 — LoadLocation (39 bytes, $00F4–$011A)
; One-time location-load called once per scene entry from GameLoop_Main.
; Calls 10 location-load steps (JSR) and two bank-$FD service vectors.
; NOT called per frame — only when entering a new location/map.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; ============================================================
LoadLocation:
    JSR LocLoad_Unk092B
    JSR LocLoad_AudioSetup
    JSR LocLoad_Unk0960
    JSR LocLoad_Unk6DCF
    JSR LocLoad_Unk7084
    JSR LocLoad_ClearPage1D00
    JSR LocLoad_UnkA33B
    JSR LocLoad_Unk09DD
    JSR LocLoad_Unk0A14
    JSR LocLoad_Unk56D4
    JSL FdVec_FFFA
    JSL FdVec_FFF4
    RTS

; ============================================================
; $C0:011B — Field_SaveState (138 bytes, $011B–$01A4)
; (was Sub_011B.) Saves the field before handing control to bank $C2
; (BankC2_Entry8000), so Field_RestoreState can rebuild it after:
;   - if Field_Unk29 is set, force it to 1 and clear Field_Unk26/27;
;   - copy Field_SaveBlock to SceneSave_Buffer (Field_StashSaveBlock);
;   - the leader's tile X/Y and facing become the entry point
;     (Loc_EntryX/Y/Facing);
;   - each party member's Obj_PosX/PosY/Unk0C00 → SceneSave_Party*;
;   - Field_UnkAB-AD, Map_ScrollA-D and Field_Unk1DF9 → SceneSave_*.
; Called from Field_SceneChangeTick, Field_PauseAndMenuInput and
; Field_FadeToBankC2Mode5.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; ============================================================
org $C0011B
Field_SaveState:
    LDA.b !Field_Unk29
    BEQ .call_mvn
    LDA #$01
    STA.b !Field_Unk29
    LDA #$00
    STA.b !Field_Unk26
    STZ.b !Field_Unk27
.call_mvn:
    JSR Field_StashSaveBlock ; Field_SaveBlock → SceneSave_Buffer
    LDY.b !Party_ObjSlot    ; leader's object (16-bit)
    LDA.w !Obj_TileX,Y
    STA.b !Loc_EntryX
    LDA.w !Obj_TileY,Y
    STA.b !Loc_EntryY
    LDA.w !Obj_Facing,Y
    STA.b !Loc_EntryFacing
    LDX #$0000              ; party member x 2
.slot_loop:
    TDC                     ; C = D = $0100
    XBA                     ; B = 0 for the TAY below
    LDA.b !Party_ObjSlot,X
    BMI .next_slot          ; Obj_None
    TAY                     ; Y = member's object
    REP #$20                ; A → 16-bit
    LDA.w !Obj_PosX,Y
    STA.l !SceneSave_PartyPosX,X
    LDA.w !Obj_PosY,Y
    STA.l !SceneSave_PartyPosY,X
    LDA.w !Obj_Unk0C00,Y
    STA.l !SceneSave_PartyUnk0C00,X
    SEP #$20                ; A → 8-bit
.next_slot:
    INX
    INX                     ; next member
    CPX #$0006              ; 3 members
    BNE .slot_loop
    LDA.b !Field_UnkAB
    STA.l !SceneSave_UnkAB
    LDA.b !Field_UnkAC
    STA.l !SceneSave_UnkAB+1
    LDA.b !Field_UnkAD
    STA.l !SceneSave_UnkAB+2
    REP #$20                ; A → 16-bit
    LDA.l !Map_ScrollA
    STA.l !SceneSave_Scroll
    LDA.l !Map_ScrollB
    STA.l !SceneSave_Scroll+2
    LDA.l !Map_ScrollC
    STA.l !SceneSave_Scroll+4
    LDA.l !Map_ScrollD
    STA.l !SceneSave_Scroll+6
    SEP #$20                ; A → 8-bit
    LDA.w !Field_Unk1DF9
    STA.l !SceneSave_Unk1DF9
    RTS

; ============================================================
; $C0:01A5 — Field_RestoreState (167 bytes, $01A5–$024B)
; (was Sub_01A5.) Rebuilds the field after a bank-$C2 round trip:
; 1. Field_RestoreSaveBlock (SceneSave_Buffer → Field_SaveBlock).
; 2. EngFD_UnkC2C1 (8-bit X), Hdma_InitChannelsFD.
; 3. Previous-frame OAM range ends = full limits.
; 4. Re-run eight location-load steps (LoadLocation's list without
;    LocLoad_Unk092B / LocLoad_AudioSetup).
; 5. Restore Map_ScrollA-D and Field_Unk1DF9 from SceneSave_*.
; 6. Evt_RunObj0Func1.
; 7. If Field_UnkAEObj names an object, run Sub_E12A on it.
; 8. If Field_Unk7F03FE is 1 or 2: put party members 2 and 3 on the
;    leader's position, enable control, set Field_Unk7F03FE = 3.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; ============================================================
org $C001A5
Field_RestoreState:
    JSR Field_RestoreSaveBlock ; SceneSave_Buffer → Field_SaveBlock
    SEP #$10                ; X,Y → 8-bit
    JSL EngFD_UnkC2C1
    REP #$10                ; X,Y → 16-bit
    JSL Hdma_InitChannelsFD
    LDX.w #!Oam_Range2Limit
    STX.b !Oam_Range2PrevEnd
    LDX.w #!Oam_Range3Limit
    STX.b !Oam_Range3PrevEnd
    LDX.w #!Oam_Range1Limit
    STX.b !Oam_Range1PrevEnd
    JSR LocLoad_Unk0960
    JSR LocLoad_Unk6DCF
    JSR LocLoad_Unk7084
    JSR LocLoad_ClearPage1D00
    JSR LocLoad_UnkA33B
    JSR LocLoad_Unk09DD
    JSR LocLoad_Unk0A14
    JSR LocLoad_Unk56D4
    REP #$20                ; A → 16-bit
    LDA.l !SceneSave_Scroll
    STA.l !Map_ScrollA
    LDA.l !SceneSave_Scroll+2
    STA.l !Map_ScrollB
    LDA.l !SceneSave_Scroll+4
    STA.l !Map_ScrollC
    LDA.l !SceneSave_Scroll+6
    STA.l !Map_ScrollD
    SEP #$20                ; A → 8-bit
    LDA.l !SceneSave_Unk1DF9
    STA.w !Field_Unk1DF9
    JSR Evt_RunObj0Func1
    TDC                     ; C = D = $0100
    XBA                     ; B = 0 for the TAX below
    LDA.b !Field_UnkAEObj
    BMI .no_e12a            ; Obj_None
    TAX
    STX.b !Obj_Cur          ; 16-bit store
    JSR Sub_E12A
.no_e12a:
    LDA.l !Field_Unk7F03FE
    BEQ .done               ; 0 → skip
    CMP #$03
    BCS .done               ; ≥ 3 → skip
    REP #$20                ; A → 16-bit
    LDX.b !Party_ObjSlot    ; leader
    LDA.w !Obj_PosX,X
    LDX.b !Party_ObjSlot1
    STA.w !Obj_PosX,X
    LDX.b !Party_ObjSlot2
    STA.w !Obj_PosX,X
    LDX.b !Party_ObjSlot
    LDA.w !Obj_PosY,X
    LDX.b !Party_ObjSlot1
    STA.w !Obj_PosY,X
    LDX.b !Party_ObjSlot2
    STA.w !Obj_PosY,X
    SEP #$20                ; A → 8-bit
    LDA #$01
    STA.b !Field_ControlEnabled
    LDA #$03
    STA.l !Field_Unk7F03FE
.done:
    RTS

; ============================================================
; $C0:0905 — Field_RestoreSaveBlock (19 bytes, $0905–$0917)
; (was Sub_0905.) Copies SceneSave_Buffer ($7F:2000) back over
; Field_SaveBlock ($7E:0920, $14E0 bytes). Reverse of
; Field_StashSaveBlock; called first thing in Field_RestoreState.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; ============================================================
org $C00905
Field_RestoreSaveBlock:
    LDY.w #!Field_SaveBlock ; destination (bank $00 mirror of $7E)
    LDX.w #!SceneSave_Buffer ; source (bank $7F)
    REP #$20                ; A → 16-bit
    LDA.w #!Field_SaveBlockSize-1 ; MVN count - 1
    PHB
    MVN !Bank00,!Bank7F     ; $7F:2000 → $00:0920  lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    SEP #$20                ; A → 8-bit
    RTS

; ============================================================
; $C0:0918 — Field_StashSaveBlock (19 bytes, $0918–$092A)
; (was Sub_0918.) Copies Field_SaveBlock ($7E:0920, $14E0 bytes) to
; SceneSave_Buffer ($7F:2000). Called from Field_SaveState.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; ============================================================
org $C00918
Field_StashSaveBlock:
    LDX.w #!Field_SaveBlock ; source (bank $00 mirror of $7E)
    LDY.w #!SceneSave_Buffer ; destination (bank $7F)
    REP #$20                ; A → 16-bit
    LDA.w #!Field_SaveBlockSize-1 ; MVN count - 1
    PHB
    MVN !Bank7F,!Bank00     ; $00:0920 → $7F:2000  lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    SEP #$20                ; A → 8-bit
    RTS

; ============================================================
; $C0:0B4E — InitHW (22 bytes)
; Disables interrupts, enables forced blank, clears NMI/DMA/HDMA.
; Called with M=1, X=0.
; ============================================================
org $C00B4E
InitHW:
    SEI
    LDA #$00
    PHA
    PLB                     ; DB = $00
    LDA.b #!INIDISP_ForcedBlank
    STA.w INIDISP           ; forced blank on, brightness 0
    LDA #$00
    STA.w NMITIMEN          ; disable NMI, IRQ, joypad auto-read
    STA.w MDMAEN            ; disable all DMA channels
    STA.w HDMAEN            ; disable all HDMA channels
    RTS

; ============================================================
; $C0:0B64 — InstallNMI (17 bytes)
; Writes JML NmiHandler ($C0:EA63) into the RAM trampoline at $7E:0500.
; Called with M=1 (8-bit A), X=0 (16-bit X).
; ============================================================
InstallNMI:
    LDA.b #!Op_JML          ; JML opcode
    STA.w !NmiTrampolineOp
    LDX.w #NmiHandler       ; low 16 bits of the target
    STX.w !NmiTrampolineAddr
    LDA.b #bank(NmiHandler) ; bank byte
    STA.w !NmiTrampolineBank
    RTS

; ============================================================
; $C0:0B75 — InstallIRQ (17 bytes)
; Writes JML IrqHandler ($C0:ECCC) into the RAM trampoline at $7E:0504.
; ============================================================
InstallIRQ:
    LDA.b #!Op_JML
    STA.w !IrqTrampolineOp
    LDX.w #IrqHandler
    STX.w !IrqTrampolineAddr
    LDA.b #bank(IrqHandler)
    STA.w !IrqTrampolineBank
    RTS

; ============================================================
; $C0:0B86 — FrameStateInit (240 bytes)
; Called once per location load from GameLoop_Main (not per frame,
; despite the name). Remembers where the location was entered, then
; resets the field direct page to its load-time defaults.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100
; ============================================================
FrameStateInit:
    ; Remember the location and entry point this load started from
    LDX.b !Loc_Id
    STX.b !Loc_PrevId
    LDX.b !Loc_EntryX        ; 16-bit: entry X and Y
    STX.b !Loc_PrevX
    LDA.b !Loc_EntryFacing
    STA.b !Loc_PrevFacing
    ; Clear scene/fade request flags
    STZ.b !Field_Unk10
    STZ.b !Field_Unk11
    STZ.b !Field_SceneFlags
    STZ.b !Field_FadeFlags
    STZ.b !Field_Unk38
    STZ.b !Field_Unk0F
    ; Fixed colour starts at all channels / intensity 0, screen dark
    LDA.b #!Fade_FixedColorInit
    STA.b !Fade_FixedColor
    STZ.b !Fade_Brightness
    STZ.b !Field_UnkBC
    LDA #$02
    STA.w !Field_Unk0BDE
    ; Previous-frame OAM range ends = full range limits
    LDX.w #!Oam_Range2Limit
    STX.b !Oam_Range2PrevEnd
    LDX.w #!Oam_Range3Limit
    STX.b !Oam_Range3PrevEnd
    LDX.w #!Oam_Range1Limit
    STX.b !Oam_Range1PrevEnd
    ; Bank bytes of the four bank-$E4 pointers
    LDA.b #!BankE4
    STA.b !Field_E4Ptr0+2
    STA.b !Field_E4Ptr1+2
    STA.b !Field_E4Ptr2+2
    STA.b !Field_E4Ptr3+2
    LDA #$01
    STA.b !Field_ControlEnabled
    STA.b !Field_Unk20
    LDA #$05
    STA.b !Field_Unk68
    LDA.b #!Field_Unk28Init
    STA.b !Field_Unk28
    STZ.b !Field_Unk53
    STZ.b !Field_Unk26
    STZ.b !Field_Unk29
    STZ.b !Field_Unk2F
    STZ.b !Field_Unk2D
    STZ.b !Field_Unk30
    STZ.b !Field_Unk44
    STZ.b !Field_MapRedrawSel
    STZ.b !Field_MapRedrawDone
    STZ.b !Field_VramQueueFlags
    STZ.b !Obj_FocusMode3
    STZ.b !Field_UnkBB
    STZ.b !Field_Unk62
    LDA.b #!Field_Unk63Idle
    STA.b !Field_Unk63
    STZ.b !Field_EventHook
    STZ.b !Field_Unk54
    REP #$20                ; M=0: A -> 16-bit
    STZ.b !Field_Unk2B
    ; Low words of the four bank-$E4 pointers from the ROM table
    LDA.l !RomE4_PtrInit
    STA.b !Field_E4Ptr0
    LDA.l !RomE4_PtrInit+2
    STA.b !Field_E4Ptr1
    LDA.l !RomE4_PtrInit+4
    STA.b !Field_E4Ptr2
    LDA.l !RomE4_PtrInit+6
    STA.b !Field_E4Ptr3
    STZ.w !DP_Field+!Pad_Unk00F6Latch ; both latches (abs addressing in the original)
    LDA #$0000
    STA.l !Field_Unk7E2000
    STZ.b !Field_Unk58
    SEP #$20                ; M=1: A -> 8-bit
    ; No party/character objects yet
    LDA.b #!Obj_None
    STA.b !Party_ObjSlot
    STA.b !Party_ObjSlot1
    STA.b !Party_ObjSlot2
    STA.b !Chr_ObjSlot
    STA.b !Chr_ObjSlot+1
    STA.b !Chr_ObjSlot+2
    STA.b !Chr_ObjSlot+4
    STA.b !Chr_ObjSlot+3
    STA.b !Chr_ObjSlot+5
    STA.b !Chr_ObjSlot+6
    ; Snapshot the party so Party_ReinitIfChanged can tell when it changes
    LDA.l !Party_Members
    STA.b !Party_MembersCache
    LDA.l !Party_Members+1
    STA.b !Party_MembersCache+1
    LDA.l !Party_Members+2
    STA.b !Party_MembersCache+2
    LDA.b #!Field_UnkEBInit
    STA.b !Field_UnkEB
    STA.b !Field_UnkAEObj   ; = Obj_None
    LDA #$01
    STA.b !Field_Unk55
    LDA.b #!Audio_SfxDefaultA
    STA.b !Audio_SfxTileAnimA
    LDA.b #!Audio_SfxDefaultB
    STA.b !Audio_SfxTileAnimB
    LDA.b #!Audio_SfxDefaultFA
    STA.b !Audio_SfxUnkFA
    LDA #$00
    STA.l !Field_Unk7E2989
    LDA #$00
    STA.w !Field_Unk0BD9
    STA.w !Field_Unk0BDA
    STA.w !Field_Unk0BDB
    STA.w !Field_Unk0BE9
    LDA.w !Eng_Unk0400
    STA.b !Field_Unk0400Copy
    RTS

; ============================================================
; $C0:0C76 — Field_SceneChangeTick (258 bytes, $0C76–$0D77)
; (was Field_SceneChangeTick.) Runs every frame from GameLoop_FrameBody.
; Steps the two fades requested in Field_FadeFlags, then acts on
; Field_SceneFlags:
;   0           nothing to do.
;   bit 7       count Fade_Brightness down to 0, then warp: remember the
;               current location as the return point, copy Loc_Dest* into
;               Loc_Id/Loc_Entry*, reset the stack and restart through
;               ReentryVectors.
;   bit 6       count Fade_Brightness down (one frame per step, with
;               Field_FrameUpdate), save the field state and call
;               BankC2_Entry8000 with an argument chosen by
;               Field_ExitMenuArg, then restore the field and fade in.
;   bit 4       run the tile-animation handler for the mode byte at
;               Map_TileProps[Field_TileAnimX/Y] (ModeE6..ModeFC_Handler);
;               any other mode goes to DefaultHandler.
;   otherwise   DefaultHandler.
; ============================================================
org $C00C76
Field_SceneChangeTick:
    ; --- Step the fades requested in Field_FadeFlags ---
    LDA.b !Field_FadeFlags
    BEQ .chk_transition      ; no fade running
    BIT.b #!FadeFlag_Brightness
    BEQ .chk_flag8
    JSR Fade_StepBrightness
    LDA.b !Field_FadeFlags
.chk_flag8:
    BIT.b #!FadeFlag_FixedColor
    BEQ .chk_transition
    JSR Fade_StepFixedColor

.chk_transition:
    LDA.b !Field_SceneFlags
    BNE .has_transition
    RTS                      ; nothing pending — fast exit

.has_transition:
    BPL .positive_17         ; bit 7 clear → bits 6/4 paths

    ; --- Bit 7: fade out, then warp to Loc_Dest* ---
    LDA.b !Fade_Brightness
    BEQ .hard_restart        ; dark → warp now
    BMI .hard_restart
    DEC.b !Fade_Brightness
    RTS

.hard_restart:
    JSR InitHW                ; SEI + forced blank
    LDX.b !Loc_Id
    STX.b !Loc_ReturnId
    LDY.b !Party_ObjSlot
    LDA.w !Obj_TileX,Y
    STA.b !Loc_ReturnX
    LDA.w !Obj_TileY,Y
    STA.b !Loc_ReturnY
    LDA.w !Obj_Facing,Y
    EOR #$01
    STA.b !Loc_ReturnFacing
    LDX.b !Loc_DestId
    STX.b !Loc_Id
    LDX.b !Loc_DestX
    STX.b !Loc_EntryX
    LDA.b !Loc_DestFacing
    STA.b !Loc_EntryFacing
    LDX.w #!StackTop         ; reset the stack (earlier listings split
    TXS                      ; these 4 bytes as LDX #$FF / ASL $9A)
    BRL ReentryVectors       ; → GameLoop_Main (warm restart into the new location)

    ; --- Positive $17 path ---
.positive_17:
    BIT.b #!SceneFlag_Reload
    BNE .run_fade_loop       ; bit 6 set → fade out and reload
    BRL .chk_bit10           ; bit 6 clear → check bit 4

.run_fade_loop:
    ; Fade out one brightness step per frame, input disabled
    LDA.b !Fade_Brightness
    BEQ .enter_transition
    BMI .enter_transition
    DEC.b !Fade_Brightness
    LDA.b !Field_ControlEnabled
    PHA
    STZ.b !Field_ControlEnabled
    JSR Field_FrameUpdate
    PLA
    STA.b !Field_ControlEnabled
    JSL FdVec_FFF7
    JSR Sub_EC60
    BRA .run_fade_loop

.enter_transition:
    ; Dark: save the field and hand over to bank $C2
    JSR InitHW
    JSR Field_SaveState
    TDC
    XBA                      ; B = 0 (dp high byte)
    LDA.b !Field_ExitMenuArg
    BEQ .mode_5_setup        ; 0 → argument 5 via Field_RunBankC2Mode5
    BMI .negative_25         ; bit 7 → argument from bits 7-6

    ; $25 positive: choose mode 0 or 6 based on bit 0
    BIT #$01
    BNE .lda_0
    LDA.b #!ExitMenu_Mode6
    BRA .do_jsl_c28000

.lda_0:
    LDA #$00
    BRA .do_jsl_c28000

.mode_5_setup:
    LDA.b #!ExitMenu_Mode5
    BRL Field_RunBankC2Mode5                ; → $19C7 (special warm-restart path)

.negative_25:
    REP #$20                 ; A → 16-bit
    AND.w #!Field_ExitArgXMask ; bits 5-0 of Field_ExitMenuArg → X
    TAX
    SEP #$20                 ; A → 8-bit
    LDA.b !Field_ExitMenuArg
    ROL
    ROL
    ROL
    AND #$03                 ; bits 7-6 of Field_ExitMenuArg → A

.do_jsl_c28000:
    JSL BankC2_Entry8000     ; A = argument (callers once guessed "set BG mode")
    JSR InitHW
    JSR InstallNMI
    JSR InstallIRQ
    REP #$20
    LDA.w #!DP_Field
    TCD                      ; DP = $0100
    SEP #$20
    JSR Field_RestoreState   ; reload the location around the saved state
    JSR Obj_ResetStates      ; clear Obj_State, then Sub_E935
    LDA.b #!SceneFlag_Reload
    TRB.b !Field_SceneFlags
    LDA.b #!FadeFlag_Reloaded
    TSB.b !Field_FadeFlags
    BRL Field_FadeInAfterReload

    ; --- Bit 4: tile-animation mode handlers ---
.chk_bit10:
    BIT.b #!SceneFlag_TileAnim
    BNE .handle_bit10
    BRL DefaultHandler

.handle_bit10:
    LDA.b #!SceneFlag_TileAnim
    TRB.b !Field_SceneFlags
    JSR TileAnimList_AddCurrent ; remember this tile in the $7F:1CC8 list
    LDX.b !Field_TileAnimX   ; 16-bit: row*256 + column
    LDA.l !Map_TileProps,X   ; mode byte of the tile
    CMP.b #!TileAnim_ModeE6
    BNE .chk_ec
    BRL ModeE6_Handler                ; → mode-E6 handler ($0D78)

.chk_ec:
    CMP.b #!TileAnim_ModeEC
    BNE .chk_ee
    BRL ModeEC_Handler                ; → mode-EC handler ($0E5F)

.chk_ee:
    CMP.b #!TileAnim_ModeEE
    BNE .chk_fa
    BRL ModeEE_Handler                ; → mode-EE handler ($1014)

.chk_fa:
    CMP.b #!TileAnim_ModeFA
    BNE .chk_fc
    BRL ModeFA_Handler                ; → mode-FA handler ($11C9)

.chk_fc:
    CMP.b #!TileAnim_ModeFC
    BNE .default_mode
    BRL ModeFC_Handler                ; → mode-FC handler ($1454)

.default_mode:
    BRL DefaultHandler

; ============================================================
; $C0:1F24 — Fade_StepBrightness (54 bytes, $1F24–$1F59)
; (was Sub_1F24.) Brightness fade: steps Fade_Brightness one unit
; toward Fade_BrightnessTarget every Fade_BrightnessDelay+1 frames and
; clears FadeFlag_Brightness when it gets there (or reaches 0 going down).
; Called from Field_SceneChangeTick while that flag is set. Earlier notes
; read this as a scroll tracker; the 0-15 range, the fade-in to 15 in
; Field_FadeInAfterReload and the pause dimming in
; Field_PauseAndMenuInput point to screen brightness.
; ============================================================
org $C01F24
Fade_StepBrightness:
    LDA.b !Fade_Brightness
    AND.b #!INIDISP_BrightnessMask ; brightness bits only
    CMP.b !Fade_BrightnessTarget
    BEQ .x_at_target         ; equal → done
    BCS .x_above             ; above → count down

    ; below target: wait out the delay, then step up
    LDA.b !Fade_BrightnessTimer
    BEQ .x_reload_up         ; delay exhausted → reload and step
    DEC.b !Fade_BrightnessTimer
    RTS

.x_reload_up:
    LDA.b !Fade_BrightnessDelay
    STA.b !Fade_BrightnessTimer ; reload the delay
    LDA.b !Fade_Brightness
    AND.b #!INIDISP_BrightnessMask
    INC.b !Fade_Brightness   ; step up
    RTS

.x_above:
    ; above target: wait out the delay, then step down
    LDA.b !Fade_BrightnessTimer
    BEQ .x_reload_dn
    DEC.b !Fade_BrightnessTimer
    RTS

.x_reload_dn:
    LDA.b !Fade_BrightnessDelay
    STA.b !Fade_BrightnessTimer
    LDA.b !Fade_Brightness
    DEC
    BEQ .x_at_target_store   ; reached 0 → also done
    STA.b !Fade_Brightness
    RTS

.x_at_target_store:
    STA.b !Fade_Brightness

.x_at_target:
    LDA.b #!FadeFlag_Brightness
    TRB.b !Field_FadeFlags   ; brightness fade done
    RTS

; ============================================================
; $C0:1F5A — Fade_StepFixedColor (45 bytes, $1F5A–$1F86)
; (was Sub_1F5A.) Fixed-colour fade: steps Fade_FixedColor one unit
; toward Fade_FixedColorTarget every Fade_FixedColorDelay+1 frames and
; clears FadeFlag_FixedColor when it gets there. Called from
; Field_SceneChangeTick while that flag is set. (Earlier notes read
; this as a scroll-Y tracker; its load value $E0 is a COLDATA value.)
; ============================================================
org $C01F5A
Fade_StepFixedColor:
    LDA.b !Fade_FixedColor
    CMP.b !Fade_FixedColorTarget
    BEQ .y_at_target         ; equal → done
    BCS .y_above             ; above → count down

    ; below target
    LDA.b !Fade_FixedColorTimer
    BEQ .y_reload_up
    DEC.b !Fade_FixedColorTimer
    RTS

.y_reload_up:
    LDA.b !Fade_FixedColorDelay
    STA.b !Fade_FixedColorTimer
    LDA.b !Fade_FixedColor
    INC.b !Fade_FixedColor   ; step up
    RTS

.y_above:
    LDA.b !Fade_FixedColorTimer
    BEQ .y_reload_dn
    DEC.b !Fade_FixedColorTimer
    RTS

.y_reload_dn:
    LDA.b !Fade_FixedColorDelay
    STA.b !Fade_FixedColorTimer
    LDA.b !Fade_FixedColor
    DEC.b !Fade_FixedColor   ; step down
    RTS

.y_at_target:
    LDA.b #!FadeFlag_FixedColor
    TRB.b !Field_FadeFlags   ; fixed-colour fade done
    RTS

; ============================================================
; $C0:2DF1 — ClearRAMDMA (45 bytes)
; Zeros a WRAM region via DMA channel 7, sourcing from MPYL (always 0
; since M7A=M7B=0). Caller sets DmaFill_Dest / DmaFill_Bank /
; DmaFill_Size first.
; ============================================================
org $C02DF1
ClearRAMDMA:
    LDA #$00
    STA.w M7A                 ; $211B: clear Mode-7 operand A (write twice per spec)
    STA.w M7A
    STA.w M7B                 ; $211C: clear Mode-7 operand B (write twice)
    STA.w M7B                 ; -> MPYL ($2134) = 0*0 = 0 (DMA source byte)
    LDA.b #!DMAP_BtoA
    STA.w DMAP7               ; $4370: B->A direction, byte unit, increment A-bus
    LDA.b #!BBAD_MPYL       ; B-bus $34 = $2134 = MPYL
    STA.w BBAD7               ; $4371: B-bus source = MPYL
    LDX.b !DmaFill_Dest
    STX.w A1T7L             ; $4372: A-bus (WRAM) destination address
    LDA.b !DmaFill_Bank
    STA.w A1B7                ; $4374: A-bus destination bank
    LDX.b !DmaFill_Size
    STX.w DAS7L             ; $4375: byte count
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN              ; $420B: enable DMA channel 7 (auto-clears when done)
    RTS

; ============================================================
; $C0:B192 — Obj_ResetStates (30 bytes, $B192–$B1B1)
; (was Sub_B192.) Clears Obj_State for every object the location
; defines (count in Evt_ObjCount), pointing DP at the Obj_State table
; so each clear is a 2-byte dp store, then tail-jumps to Sub_E935
; (which sets $0BC0-$0BC7 to $80). Called at the end of every reload.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; ============================================================
org $C0B192
Obj_ResetStates:
    PHD
    REP #$20                ; A → 16-bit
    LDA.w #!Obj_State
    TCD                     ; DP = Obj_State table
    SEP #$20                ; A → 8-bit
    SEP #$10                ; X,Y → 8-bit
    LDA.l !Evt_ObjCount     ; objects in this location
    LDX #$00                ; value to store
    LDY #$00                ; object offset
.zero_loop:
    STX.b !Dp_TableStart,Y  ; Obj_State[Y] = 0
    INY
    INY                     ; Y += 2
    DEC                     ; A-- (count)
    BNE .zero_loop
    REP #$10                ; X,Y → 16-bit
    PLD
    BRL Sub_E935            ; sets $0BC0-$0BC7 to $80

; ============================================================
; $C0:B271 — PostVBlank (152 bytes)
; Rebuilds the OAM shadow ($0700 low table, $0900 high table) for
; the frame. The shadow is split into three ranges, each with a
; low-table pointer (Oam_RangeNLoPtr) and a high-table pointer
; (Oam_RangeNHiPtr); Sub_B309 appends each object's tiles to the range
; chosen by its flags. Objects are visited bucket by bucket from
; Obj_DrawBucket (last bucket first), following Obj_DrawNext chains.
; Afterwards, entries between each range's new end and last frame's
; end (Oam_RangeNPrevEnd) are parked off screen with Y = $E0.
;
; Entered via BRL tail-call from VBlankHandler ($C0:00BF), DP=$0100.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y).
; RTS returns to VBlankHandler's caller.
; ============================================================
org $C0B271
PostVBlank:
    LDX.w #!Oam_Range3HiStart
    STX.b !Oam_Range3HiPtr
    LDX #$0000
    STX.b !Oam_Range3HiUnk
    LDX.w #!Oam_Range1HiStart
    STX.b !Oam_Range1HiPtr
    LDX #$0000
    STX.b !Oam_Range1HiUnk
    LDX.w #!Oam_Range2HiStart
    STX.b !Oam_Range2HiPtr
    LDX #$0000
    STX.b !Oam_Range2HiUnk
    LDX.w #!Oam_Range3Start
    STX.b !Oam_Range3LoPtr
    LDX.w #!Oam_Range1Start
    STX.b !Oam_Range1LoPtr
    LDA #$00
    STA.w WMADDH              ; WMDATA writes go to bank $7E
    STA.b !Obj_CurHi        ; keep Obj_Cur's high byte 0
    LDX.w #!Oam_Range2Start
    STX.b !Oam_Range2LoPtr
    LDY.w #!Obj_DrawBucketLast ; 64 buckets x 2, last first
PV_SpriteLoop:
    LDA.w !Obj_DrawBucket,Y
    BMI PV_NextSprite       ; bit 7: empty bucket
    STA.b !Obj_Cur          ; first object in the bucket
    JSR Sub_B309
PV_CheckChain:
    LDX.b !Obj_Cur
    LDA.w !Obj_DrawNext,X   ; next object in the same bucket
    BMI PV_NextSprite
    STA.b !Obj_Cur
    JSR Sub_B309
    BRA PV_CheckChain
PV_NextSprite:
    DEY
    DEY
    BPL PV_SpriteLoop
    LDX.b !Oam_Range1LoPtr
    LDA.b #!Oam_HiddenY     ; Y=$E0 parks the entry below the screen
PV_FillRange1:
    CPX.b !Oam_Range1PrevEnd
    BCS PV_EndRange1
    STA.w OamEntry.Y,X        ; X = entry address
    INX
    INX
    INX
    INX
    CPX.w #!Oam_Range1Limit
    BCC PV_FillRange1
PV_EndRange1:
    LDX.b !Oam_Range1LoPtr
    STX.b !Oam_Range1PrevEnd
    LDX.b !Oam_Range2LoPtr
PV_FillRange2:
    CPX.b !Oam_Range2PrevEnd
    BCS PV_EndRange2
    STA.w OamEntry.Y,X
    INX
    INX
    INX
    INX
    CPX.w #!Oam_Range2Limit
    BCC PV_FillRange2
PV_EndRange2:
    LDX.b !Oam_Range2LoPtr
    STX.b !Oam_Range2PrevEnd
    LDX.b !Oam_Range3LoPtr
PV_FillRange3:
    CPX.b !Oam_Range3PrevEnd
    BCS PV_EndRange3
    STA.w OamEntry.Y,X
    INX
    INX
    INX
    INX
    CPX.w #!Oam_Range3Limit
    BCC PV_FillRange3
PV_EndRange3:
    LDX.b !Oam_Range3LoPtr
    STX.b !Oam_Range3PrevEnd
    RTS

; ============================================================
; $C0:1B90 — Audio_PlayTileSfxA (23 bytes, $1B90–$1BA6)
; (was Sub_1B90.) Plays sound effect Audio_SfxTileAnimA through the
; sound driver: Audio_CmdId = $19 (play effect), Arg0 = effect id,
; Arg1 = the party leader's Obj_SfxArg. Called from the Mode*_Handler
; tile animations. Audio_PlaySfxAtLeader (was Sub_1B90_body) is the
; shared tail, entered by Audio_PlayTileSfxB with its own effect id.
; On entry: M=1 (A=8-bit), X/Y=16-bit.
; ============================================================
org $C01B90
Audio_PlayTileSfxA:
    LDA.b !Audio_SfxTileAnimA
Audio_PlaySfxAtLeader:   ; ← entry for Audio_PlayTileSfxB, A = effect id
    STA.w !Audio_CmdArg0
    LDY.b !Party_ObjSlot ; leader's object
    LDA.w !Obj_SfxArg,Y
    STA.w !Audio_CmdArg1
    LDA.b #!Audio_CmdPlaySfx
    STA.w !Audio_CmdId
    JSL Audio_DriverCommand
    RTS

; ============================================================
; $C0:2824 — Field_FadeInAfterReload (36 bytes, $2824–$2847)
; (was Sub_2824.) Fade-in after a reload: unless Scene_ReloadStep
; returns nonzero, raises Fade_Brightness one step per frame (input
; disabled around Field_FrameUpdate) until it reaches full brightness.
; Clears Field_Unk1E and Field_FadeBusy on exit. Tail of
; Field_SceneChangeTick's reload path; also called after the
; bank-$C2 round trips.
; On entry: M=1 (A=8-bit), X/Y=16-bit.
; ============================================================
org $C02824
Field_FadeInAfterReload:
    JSR Scene_ReloadStep
    BNE .done            ; nonzero → skip the fade-in
.loop:
    INC.b !Fade_Brightness
    LDA.b !Field_ControlEnabled
    PHA
    STZ.b !Field_ControlEnabled ; no input during the fade
    JSR Field_FrameUpdate
    PLA
    STA.b !Field_ControlEnabled
    JSR VBlankHandlerShort
    JSR Sub_EC60
    LDA.b !Fade_Brightness
    CMP.b #!Fade_BrightnessMax
    BMI .loop            ; until full brightness
.done:
    STZ.b !Field_Unk1E
    STZ.w !Field_FadeBusy
    RTS

; ============================================================
; $C0:18D9 — Field_PauseAndMenuInput (172 bytes, $18D9–$1984)
; (was Sub_18D9.) Per-frame pause and menu input, called from
; GameLoop_FrameBody before Field_SceneChangeTick.
; On entry: M=1 (A 8-bit), X/Y 16-bit, DP=$0100.
;
; Pause: when Start is newly pressed (Pad_Pressed bit 0) with
;   Field_Unk11 = 0 and Field_ControlEnabled set, halve the brightness
;   and loop (Sub_EC60 + EngFD_UnkC2C1 each frame) until Start is
;   pressed again, then restore the brightness. (Earlier notes read
;   this as a VBlank-sync wait and had the exit test inverted.)
; Then Pad_Unk00F6: bit 0 → Field_FadeToBankC2Mode5; bit 6 (X in the
;   Pad_Pressed layout) → if control is enabled and Field_Unk62 /
;   Field_Unk10 are 0, fade out, save the field, call
;   BankC2_Entry8000 with A = 1 (TDC/XBA leaves DP's high byte in A;
;   very likely the main menu), and reload; otherwise run Sub_1ADF
;   when Field_Unk62 is set.
; ============================================================
org $C018D9
Field_PauseAndMenuInput:
    LDA.w !Pad_Pressed
    BIT.b #!Pad_Start
    BEQ .after_wait      ; Start not pressed
    LDA.b !Field_Unk11
    BNE .after_wait
    LDA.b !Field_ControlEnabled
    BEQ .after_wait
    ; Pause: dim to half brightness until Start is pressed again
    LDA.b !Fade_Brightness
    STA.b !Fade_BrightnessSaved
    LSR                  ; halve
    STA.b !Fade_Brightness
    LDA.b #!Field_FadeBusyOn
    STA.w !Field_FadeBusy
.wait_loop:
    JSR Sub_EC60
    LDA.w !Pad_Pressed
    BIT.b #!Pad_Start
    BNE .wait_exit       ; Start pressed again → resume
    LDA.b !Fade_BrightnessSaved
    LSR
    STA.b !Fade_Brightness
    SEP #$10
    JSL EngFD_UnkC2C1
    STZ.b !Field_Unk53
    REP #$10
    BRA .wait_loop
.wait_exit:
    LDA.b !Fade_BrightnessSaved
    STA.b !Fade_Brightness
    STZ.w !Field_FadeBusy
.after_wait:
    LDA.w !Pad_Unk00F6
    BIT.b #!Pad_Unk00F6Mode5
    BEQ .no_mode5
    JSR Field_FadeToBankC2Mode5
    LDA.w !Pad_Unk00F6
.no_mode5:
    BIT.b #!Pad_Unk00F6Menu
    BNE .bit6_set
    LDA.b !Field_Unk62
    BEQ .done
    JSR Sub_1ADF
.done:
    RTS
.bit6_set:
    LDA.b !Field_ControlEnabled
    BNE .chk_62
    RTS
.chk_62:
    LDA.b !Field_Unk62
    BEQ .chk_10
    RTS
.chk_10:
    LDA.b !Field_Unk10
    BEQ .do_reinit
    RTS
.do_reinit:
.fade_loop:
    LDA.b #!Field_FadeBusyOn
    STA.w !Field_FadeBusy ; (set again every frame)
    LDA.b !Fade_Brightness
    BEQ .fade_done
    BMI .fade_done
    DEC.b !Fade_Brightness
    SEP #$10
    JSL EngFD_UnkC2C1
    REP #$10
    JSR Sub_EC60
    BRA .fade_loop
.fade_done:
    JSR InitHW
    JSR Field_SaveState
    TDC                  ; C = D = $0100
    XBA                  ; A = $01 (DP high byte), B = $00
    JSL BankC2_Entry8000
    JSR InitHW
    JSR InstallNMI
    JSR InstallIRQ
    REP #$20             ; A → 16-bit
    LDA.w #!DP_Field
    TCD                  ; DP = $0100
    SEP #$20             ; A → 8-bit
    JSR Field_RestoreState
    JSR Party_ReinitIfChanged ; party may have changed in the menu
    JSR Obj_ResetStates
    JSR Field_FadeInAfterReload
    STZ.w !Field_FadeBusy
    RTS

; ============================================================
; $C0:1985 — Field_FadeToBankC2Mode5 (66 bytes, $1985–$19C6)
; (was Sub_1985.) Called from Field_PauseAndMenuInput when
; Pad_Unk00F6 bit 0 is set. If Field_Unk26 is nonzero it only toggles
; its bits 0-1. Otherwise, if Eng_Unk7F0000 >= $49, control is enabled
; and Field_Unk62 / Field_Unk10 are 0, it fades out (one step per
; frame), saves the field and falls through to Field_RunBankC2Mode5.
; On entry: M=1 (A 8-bit), X/Y 16-bit, DP=$0100.
; ============================================================
org $C01985
Field_FadeToBankC2Mode5:
    LDA.b !Field_Unk26
    BEQ .continue
    EOR #$03             ; toggle bits 0-1
    STA.b !Field_Unk26
    RTS
.continue:
    LDA.l !Eng_Unk7F0000
    SEC
    SBC.b #!Eng_Unk7F0000Min
    BCS .chk_1F          ; ≥ $49 → continue
    RTS
.chk_1F:
    LDA.b !Field_ControlEnabled
    BNE .chk_62          ; non-zero → continue
    RTS
.chk_62:
    LDA.b !Field_Unk62
    BEQ .chk_10          ; zero → continue
    RTS
.chk_10:
    LDA.b !Field_Unk10
    BEQ .do_fade         ; zero → proceed
    RTS
.do_fade:
.fade_loop:
    LDA.b #!Field_FadeBusyOn
    STA.w !Field_FadeBusy ; (set again every frame)
    LDA.b !Fade_Brightness
    BEQ .fade_done
    BMI .fade_done
    DEC.b !Fade_Brightness
    SEP #$10
    JSL EngFD_UnkC2C1
    REP #$10
    JSR Sub_EC60
    BRA .fade_loop
.fade_done:
    JSR InitHW
    JSR Field_SaveState
    ; fall through to Field_RunBankC2Mode5

; ============================================================
; $C0:19C7 — Field_RunBankC2Mode5 (60 bytes, $19C7–$1A02)
; (was Sub_19C7.) Calls BankC2_Entry8000 with A = 5, X = 0 (meaning
; of 5 unverified; earlier notes called it "BG mode 5"), then reloads
; the field: restore state, re-init changed party members, move a
; pending SceneFlag_Reload over to FadeFlag_Reloaded, reset object
; states and fade in. Reached from Field_SceneChangeTick (when
; Field_ExitMenuArg is 0) and by fall-through from
; Field_FadeToBankC2Mode5. On entry: M=1 (A=8-bit), X/Y=16-bit.
; ============================================================
org $C019C7
Field_RunBankC2Mode5:
    LDX #$0000
    TDC                  ; C = D = $0100
    XBA                  ; B = $00 (A is reloaded next)
    LDA.b #!ExitMenu_Mode5
    JSL BankC2_Entry8000
    JSR InitHW
    JSR InstallNMI
    JSR InstallIRQ
    REP #$20             ; A → 16-bit
    LDA.w #!DP_Field
    TCD                  ; DP = $0100
    SEP #$20             ; A → 8-bit
    JSR Field_RestoreState
    JSR Party_ReinitIfChanged
    REP #$10             ; ensure X/Y 16-bit
    LDA.b !Field_SceneFlags
    BIT.b #!SceneFlag_Reload
    BEQ .no_bit6
    LDA.b #!SceneFlag_Reload
    TRB.b !Field_SceneFlags
    LDA.b #!FadeFlag_Reloaded
    TSB.b !Field_FadeFlags
.no_bit6:
    JSR Obj_ResetStates
    JSR Field_FadeInAfterReload
    STZ.w !Field_FadeBusy
    RTS

; ============================================================
; $C0:1A03 — Party_ReinitIfChanged (169 bytes, $1A03–$1AAB)
; (was Sub_1A03.) After a bank-$C2 round trip: if Party_Members no
; longer matches the copy taken at load (Party_MembersCache), re-run
; the init function of every character object that exists
; (Chr_ObjSlot, order $8D $8E $8F $91 $90 $92 $93) and refresh the
; copy. Earlier notes read $7E:2980-2982 as palette colours; they are
; the party's character ids. Either way, then put the party members
; back where Field_SaveState left them (SceneSave_Party*) and restore
; Field_UnkAB-AD — the second half of Field_SaveState's work.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; ============================================================
org $C01A03
Party_ReinitIfChanged:
    LDA.l !Party_Members
    CMP.b !Party_MembersCache
    BNE .colors_changed
    LDA.l !Party_Members+1
    CMP.b !Party_MembersCache+1
    BNE .colors_changed
    LDA.l !Party_Members+2
    CMP.b !Party_MembersCache+2
    BNE .colors_changed
    RTS                     ; party unchanged → nothing to do

.colors_changed:
    STZ.b !Obj_CurHi        ; keep Obj_Cur's high byte 0
    LDA.b !Chr_ObjSlot
    BMI .chk_8E             ; Obj_None
    STA.b !Obj_Cur
    JSR Evt_RunObjInit
.chk_8E:
    LDA.b !Chr_ObjSlot+1
    BMI .chk_8F
    STA.b !Obj_Cur
    JSR Evt_RunObjInit
.chk_8F:
    LDA.b !Chr_ObjSlot+2
    BMI .chk_91
    STA.b !Obj_Cur
    JSR Evt_RunObjInit
.chk_91:
    LDA.b !Chr_ObjSlot+4
    BMI .chk_90
    STA.b !Obj_Cur
    JSR Evt_RunObjInit
.chk_90:
    LDA.b !Chr_ObjSlot+3
    BMI .chk_92
    STA.b !Obj_Cur
    JSR Evt_RunObjInit
.chk_92:
    LDA.b !Chr_ObjSlot+5
    BMI .chk_93
    STA.b !Obj_Cur
    JSR Evt_RunObjInit
.chk_93:
    LDA.b !Chr_ObjSlot+6
    BMI .update_cache
    STA.b !Obj_Cur
    JSR Evt_RunObjInit

.update_cache:
    LDA.l !Party_Members    ; refresh the copy
    STA.b !Party_MembersCache
    LDA.l !Party_Members+1
    STA.b !Party_MembersCache+1
    LDA.l !Party_Members+2
    STA.b !Party_MembersCache+2

    LDX #$0000              ; party member x 2
.restore_loop:
    TDC                     ; C = D = $0100
    XBA                     ; B = 0 for the TAY below
    LDA.b !Party_ObjSlot,X
    BMI .next_restore       ; Obj_None
    TAY                     ; Y = member's object
    REP #$20                ; A → 16-bit
    LDA.l !SceneSave_PartyPosX,X
    STA.w !Obj_PosX,Y
    LDA.l !SceneSave_PartyPosY,X
    STA.w !Obj_PosY,Y
    LDA.l !SceneSave_PartyUnk0C00,X
    STA.w !Obj_Unk0C00,Y
    SEP #$20                ; A → 8-bit
.next_restore:
    INX
    INX                     ; X += 2
    CPX #$0006              ; 3 iterations
    BNE .restore_loop

    LDA.l !SceneSave_UnkAB
    STA.b !Field_UnkAB
    LDA.l !SceneSave_UnkAB+1
    STA.b !Field_UnkAC
    LDA.l !SceneSave_UnkAB+2
    STA.b !Field_UnkAD
    RTS

; ============================================================
; $C0:595C — Evt_RunObj0Func1 (33 bytes, $595C–$597C)
; (was Sub_595C.) Runs one event-script function of object 0: the
; offset stored at Evt_Data+2 (object 0's second function pointer),
; executing opcodes through Evt_OpcodeTable until opcode $00. Each
; opcode handler gets Y = the opcode's offset and must return with X
; at the next opcode. (Earlier notes called the opcodes "entity type
; bytes".) Called from Field_RestoreState.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; ============================================================
org $C0595C
Evt_RunObj0Func1:
    REP #$20                ; A → 16-bit
    STZ.b !Obj_Cur          ; object 0 (16-bit store clears Obj_CurHi too)
    LDA.l !Evt_Data+2       ; object 0, function 1 offset
    TAX
    SEP #$20                ; A → 8-bit
.dispatch_loop:
    LDA.l !Evt_Data,X       ; opcode
    BEQ .done               ; $00 = return
    TXY                     ; Y = opcode's offset
    REP #$20                ; A → 16-bit
    AND.w #!Eng_LowByteMask
    ASL                     ; word table index
    TAX
    SEP #$20                ; A → 8-bit
    JSR (Evt_OpcodeTable,X) ; handler returns X = next opcode
    BRA .dispatch_loop
.done:
    RTS

; ============================================================
; $C0:597D — Evt_RunObjInit (92 bytes, $597D–$59D8)
; (was Sub_597D.) Runs object Obj_Cur's init function: the first of
; its 16 function offsets (Evt_Data + Obj_Cur*16, i.e. 32 bytes per
; object) is executed through Evt_OpcodeTable until opcode $00. Then
; Obj_ScriptPos = the offset after that $00, eight per-object words in
; bank $7F are cleared and Obj_Unk1C00 = 7.
; Called from Party_ReinitIfChanged for each character object.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100.
; ============================================================
org $C0597D
Evt_RunObjInit:
    LDA.b !Obj_Cur          ; object x 2
    REP #$20                ; A → 16-bit
    AND.w #!Eng_LowByteMask
    ASL
    ASL
    ASL
    ASL                     ; x 16 = object x 32: its function table
    TAX
    LDA.l !Evt_Data,X       ; function 0 (init) offset
    TAX
    SEP #$20                ; A → 8-bit
.inner_loop:
    LDA.l !Evt_Data,X       ; opcode
    BEQ .list_done          ; $00 = return
    TXY                     ; Y = opcode's offset
    REP #$20                ; A → 16-bit
    AND.w #!Eng_LowByteMask
    ASL                     ; word table index
    TAX
    SEP #$20                ; A → 8-bit
    JSR (Evt_OpcodeTable,X) ; handler returns X = next opcode
    BRA .inner_loop
.list_done:
    REP #$20                ; A → 16-bit
    INX                     ; past the $00
    TXA
    LDX.b !Obj_Cur          ; 16-bit; Obj_CurHi is 0
    STA.w !Obj_ScriptPos,X  ; where the object's script continues
    LDA #$0000
    STA.l !ObjX_Unk7F0580,X ; clear the object's bank-$7F words
    STA.l !ObjX_Unk7F0600,X
    STA.l !ObjX_Unk7F0680,X
    STA.l !ObjX_Unk7F0700,X
    STA.l !ObjX_Unk7F0780,X
    STA.l !ObjX_Unk7F0800,X
    STA.l !ObjX_Unk7F0880,X
    STA.l !ObjX_Unk7F0900,X
    SEP #$20                ; A → 8-bit
    LDA.b #!Obj_Unk1C00Init
    STA.w !Obj_Unk1C00,X
    RTS

; ============================================================
; $C0:1ADF — Sub_1ADF (87 bytes, $1ADF–$1B35)
; Leaf routine run by Field_PauseAndMenuInput when Field_Unk62 is set
; (and Pad_Unk00F6 bit 6 is clear); A = Field_Unk62.
; On entry: M=1, X/Y 16-bit, DP=$0100.
;
; A=1    → if Pad_Unk00F6 bit 7 is set, clear Field_Unk34.
; A=2    → Pad_Unk00F7 bit 2 steps Field_Unk63 up (wrapping from
;          Field_Unk65 to Field_Unk64), bit 3 steps it down (wrapping
;          the other way); else Pad_Unk00F8 bit 7 sets Field_Unk62 = 3.
;          (Bits 2/3 are Down/Up in the Pad_Pressed layout: a list
;          cursor is likely.)
; other  → save Field_Unk63 in Field_Unk66 and force it to 4 (unless it
;          is negative or already 4), then as A=1.
; ============================================================
org $C01ADF
Sub_1ADF:
    CMP #$01
    BEQ .chk_flags       ; A=1
    CMP #$02
    BNE .update_mode63   ; A≠1,2
    ; A=2
    LDA.w !Pad_Unk00F7
    BIT.b #!Pad_HiDown
    BNE .inc_mode63
    BIT.b #!Pad_HiUp
    BNE .dec_mode63
    LDA.w !Pad_Unk00F8
    BIT.b #!Pad_Unk00F8Bit7
    BEQ .rts2
    LDA #$03
    STA.b !Field_Unk62
    RTS
.update_mode63:          ; A≠1,2
    LDA.b !Field_Unk63
    BMI .chk_flags       ; negative → leave it
    CMP #$04
    BEQ .chk_flags       ; already 4
    STA.b !Field_Unk66
    LDA #$04
    STA.b !Field_Unk63
.chk_flags:
    LDA.w !Pad_Unk00F6
    BIT.b #!Pad_Unk00F6Bit7
    BEQ .rts2            ; bit 7 clear → leave Field_Unk34
    LDX #$0000
    STX.b !Field_Unk34
.rts2:                   ; $1B18
    RTS
.inc_mode63:             ; $1B19
    LDA.b !Field_Unk63
    INC A
    CMP.b !Field_Unk65
    BEQ .store_63
    BCS .use_64_val
.store_63:               ; $1B22
    STA.b !Field_Unk63
    RTS
.use_64_val:             ; $1B25
    LDA.b !Field_Unk64
    BRA .store_63
.dec_mode63:             ; $1B29
    LDA.b !Field_Unk63
    BEQ .use_65_val
    DEC A
    CMP.b !Field_Unk64
    BCS .store_63
.use_65_val:             ; $1B32
    LDA.b !Field_Unk65
    BRA .store_63

; ============================================================
; $C0:0D78 — ModeE6_Handler (231 bytes, $0D78–$0E5E)
; Tile animation for map-tile state $E6: a 1x2 column, the tile at
; (Field_TileAnimX, Field_TileAnimY) and the one above it.
; BRL target from Field_SceneChangeTick (Field_SceneFlags bit 4).
; On entry: A = $E6, X = Map_TileProps index of (col, row), M=1, X/Y 16-bit.
;
; The general shape, shared by all five Mode*_Handlers:
;  1. Advance the state byte of each affected map tile in
;     Map_TileProps by one ($E6 → $E7 here), set TileAnim_PairCount
;     and play Audio_SfxTileAnimA.
;  2. For each affected map tile ("pass"), compute the VRAM word
;     address of its four 8x8 tiles in the 64x32 BG tilemap
;     (Bg_TilemapIndex64x32 + Map_TilemapVram) into TileAnim_VramAddrs,
;     4 words per map tile in TL, TR, BL, BR order.
;  3. Set VramQueue_TileAnim in Field_VramQueueFlags and continue in
;     DefaultHandler.
; Earlier comments here swapped rows and columns: Field_TileAnimX
; ($5B) is the map column, Field_TileAnimY ($5C) the row.
; ============================================================
org $C00D78
ModeE6_Handler:
    INC                  ; tile state $E6 → $E7
    STA.l !Map_TileProps,X ; tile (col, row)
    REP #$20             ; A → 16-bit
    TXA
    SEC
    SBC.w #!Map_RowStride ; index of (col, row-1)
    TAX
    LDA.l !Map_TileProps,X ; 16-bit: (col, row-1) and its right neighbour
    INC                  ; +1 lands in (col, row-1)
    STA.l !Map_TileProps,X
    SEP #$20             ; A → 8-bit
    STZ.b !TileAnim_PairCount ; one pair of tiles
    JSR Audio_PlayTileSfxA
    REP #$20             ; A → 16-bit
    LDA.w !Map_TileOriginX
    STA.b !TileAnim_OriginX
    LDA.w !Map_TileOriginY
    STA.b !TileAnim_OriginY

    ; --- Pass 1: map tile (col, row) → TileAnim_VramAddrs+0..+6 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs   ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+2 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+4 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+6 ; bottom-right 8x8 tile
    ; --- Pass 2: map tile (col, row-1) → TileAnim_VramAddrs+8..+14 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+8 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+10 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+12 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+14 ; bottom-right 8x8 tile
    SEP #$20             ; A → 8-bit
    LDA.b #!VramQueue_TileAnim
    TSB.b !Field_VramQueueFlags ; TileAnim_VramAddrs ready
    BRL DefaultHandler

; ============================================================
; $C0:1B36 — Bg_TilemapIndex64x32 (29 bytes, $1B36–$1B52)
; (was Sub_1B36.) Word offset of an 8x8 tile in a 64x32 BG tilemap
; made of two 32x32 screens side by side.
; On entry (M=0): A = tile row (0-31), Y = tile column (0-63).
; Returns A = row*32 + column for columns 0-31, or
;             row*32 + (column-32) + $0400 for columns 32-63.
; (Earlier comments had the row and column inputs swapped.)
; Called by the Mode*_Handlers and DefaultHandler; uses Eng_Scratch.
; ============================================================
org $C01B36
Bg_TilemapIndex64x32:
    ASL
    ASL
    ASL
    ASL
    ASL                  ; row × 32
    STA.b !Bg_RowWordOfs
    TYA                  ; A = column
    CMP.w #!Bg_ScreenWidth
    BCS .rowhi           ; right-hand screen
    CLC
    ADC.b !Bg_RowWordOfs ; row*32 + column
    RTS
.rowhi:
    SEC
    SBC.w #!Bg_ScreenWidth ; column - 32
    CLC
    ADC.b !Bg_RowWordOfs
    CLC
    ADC.w #!Bg_ScreenWords ; + the left screen's $400 words
    RTS

; ============================================================
; $C0:0E5F — ModeEC_Handler (437 bytes, $0E5F–$1013)
; Tile animation for map-tile state $EC: a 2x2 block, columns
; col..col+1, rows row-1..row. Same shape as ModeE6_Handler; 4 passes.
; On entry: A = $EC, X = Map_TileProps index of (col, row), M=1, X/Y 16-bit.
; ============================================================
org $C00E5F
ModeEC_Handler:
    INC A                   ; $EC → $ED
    STA.l !Map_TileProps,X  ; tile (col, row)
    INX                     ; X = tile (col+1, row)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col+1, row)
    REP #$20                ; M → 0 (16-bit A)
    TXA
    SEC
    SBC.w #!Map_RowStride   ; A = index of (col+1, row-1)
    TAX
    SEP #$20                ; M → 1 (8-bit A)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X
    DEX                     ; (col, row-1)
    LDA.l !Map_TileProps,X  ; load entry at (col, row-1)
    INC A
    STA.l !Map_TileProps,X
    LDA #$01
    STA.b !TileAnim_PairCount ; 1 + 1 pairs of tiles
    JSR Audio_PlayTileSfxA
    ; --- VRAM addresses of the 8x8 tiles ---
    REP #$20                ; M → 0 (16-bit A)
    LDA.w !Map_TileOriginX
    STA.b !TileAnim_OriginX
    LDA.w !Map_TileOriginY
    STA.b !TileAnim_OriginY
    ; --- Pass 1: map tile (col, row) → TileAnim_VramAddrs+0..+6 ---
    LDX.b !Field_TileAnimX      ; LDX+TXA here, LDA in the other passes
    TXA
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs   ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+2 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+4 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+6 ; bottom-right 8x8 tile
    ; --- Pass 2: map tile (col, row-1) → TileAnim_VramAddrs+8..+14 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+8 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+10 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+12 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+14 ; bottom-right 8x8 tile
    ; --- Pass 3: map tile (col+1, row) → TileAnim_VramAddrs+16..+22 ---
    LDA.b !Field_TileAnimX
    INC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+16 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+18 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+20 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+22 ; bottom-right 8x8 tile
    ; --- Pass 4: map tile (col+1, row-1) → TileAnim_VramAddrs+24..+30 ---
    LDA.b !Field_TileAnimX
    INC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+24 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+26 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+28 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+30 ; bottom-right 8x8 tile
    SEP #$20                ; A → 8-bit
    LDA.b #!VramQueue_TileAnim
    TSB.b !Field_VramQueueFlags ; TileAnim_VramAddrs ready
    BRL DefaultHandler

; ============================================================
; $C0:1014 — ModeEE_Handler (437 bytes, $1014–$11C8)
; Tile animation for map-tile state $EE: a 2x2 block, columns
; col-1..col, rows row-1..row (ModeEC_Handler mirrored). 4 passes.
; On entry: A = $EE, X = Map_TileProps index of (col, row), M=1, X/Y 16-bit.
; ============================================================
org $C01014
ModeEE_Handler:
    ; --- Advance the state of the 4 tiles ---
    INC A                   ; tile state $EE → $EF
    STA.l !Map_TileProps,X  ; tile (col, row)
    DEX                     ; X = tile (col-1, row)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col-1, row)
    REP #$20                ; M → 0 (16-bit A)
    TXA
    SEC
    SBC.w #!Map_RowStride   ; A = index of (col-1, row-1)
    TAX
    SEP #$20                ; M → 1 (8-bit A)
    LDA.l !Map_TileProps,X  ; tile (col-1, row-1)
    INC A
    STA.l !Map_TileProps,X  ; tile (col-1, row-1)
    INX                     ; X = tile (col, row-1)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col, row-1)
    JSR Audio_PlayTileSfxA            ; (before setting TileAnim_PairCount here)
    LDA #$01
    STA.b !TileAnim_PairCount ; 1 + 1 pairs of tiles

    ; --- VRAM addresses of the 8x8 tiles ---
    REP #$20                ; M → 0 (16-bit A)
    LDA.w !Map_TileOriginX
    STA.b !TileAnim_OriginX
    LDA.w !Map_TileOriginY
    STA.b !TileAnim_OriginY

    ; --- Pass 1: map tile (col-1, row) → TileAnim_VramAddrs+0..+6 ---
    LDX.b !Field_TileAnimX      ; LDX+TXA here, LDA in the other passes
    TXA
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs   ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+2 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+4 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+6 ; bottom-right 8x8 tile

    ; --- Pass 2: map tile (col-1, row-1) → TileAnim_VramAddrs+8..+14 ---
    LDA.b !Field_TileAnimX
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+8 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+10 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+12 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+14 ; bottom-right 8x8 tile

    ; --- Pass 3: map tile (col, row) → TileAnim_VramAddrs+16..+22 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+16 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+18 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+20 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+22 ; bottom-right 8x8 tile

    ; --- Pass 4: map tile (col, row-1) → TileAnim_VramAddrs+24..+30 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+24 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+26 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+28 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+30 ; bottom-right 8x8 tile


    SEP #$20                ; A → 8-bit
    LDA.b #!VramQueue_TileAnim
    TSB.b !Field_VramQueueFlags ; TileAnim_VramAddrs ready
    BRL DefaultHandler

; ============================================================
; $C0:11C9 — ModeFA_Handler (651 bytes, $11C9–$1453)
; Tile animation for map-tile state $FA: a 2-wide, 3-tall block,
; columns col..col+1, rows row-2..row. 6 passes.
; On entry: A = $FA, X = Map_TileProps index of (col, row), M=1, X/Y 16-bit.
; ============================================================
org $C011C9
ModeFA_Handler:
    ; --- Advance the state of the 6 tiles ---
    INC A                   ; tile state $FA → $FB
    STA.l !Map_TileProps,X  ; tile (col, row)
    INX                     ; X = tile (col+1, row)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col+1, row)
    REP #$20
    TXA
    SEC
    SBC.w #!Map_RowStride   ; A = index of (col+1, row-1)
    TAX
    SEP #$20
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col+1, row-1)
    DEX                     ; X = tile (col, row-1)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col, row-1)
    REP #$20
    TXA
    SEC
    SBC.w #!Map_RowStride   ; A = index of (col, row-2)
    TAX
    SEP #$20
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col, row-2)
    INX                     ; X = tile (col+1, row-2)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col+1, row-2)
    JSR Audio_PlayTileSfxA
    LDA #$02
    STA.b !TileAnim_PairCount ; 2 + 1 pairs of tiles

    ; --- VRAM addresses of the 8x8 tiles ---
    REP #$20
    LDA.w !Map_TileOriginX
    STA.b !TileAnim_OriginX
    LDA.w !Map_TileOriginY
    STA.b !TileAnim_OriginY

    ; --- Pass 1: map tile (col, row) → TileAnim_VramAddrs+0..+6 ---
    LDX.b !Field_TileAnimX      ; LDX+TXA here, LDA in the other passes
    TXA
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs   ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+2 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+4 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+6 ; bottom-right 8x8 tile

    ; --- Pass 2: map tile (col, row-1) → TileAnim_VramAddrs+8..+14 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+8 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+10 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+12 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+14 ; bottom-right 8x8 tile

    ; --- Pass 3: map tile (col, row-2) → TileAnim_VramAddrs+16..+22 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+16 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+18 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+20 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+22 ; bottom-right 8x8 tile

    ; --- Pass 4: map tile (col+1, row) → TileAnim_VramAddrs+24..+30 ---
    LDA.b !Field_TileAnimX
    INC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+24 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+26 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+28 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+30 ; bottom-right 8x8 tile

    ; --- Pass 5: map tile (col+1, row-1) → TileAnim_VramAddrs+32..+38 ---
    LDA.b !Field_TileAnimX
    INC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+32 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+34 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+36 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+38 ; bottom-right 8x8 tile

    ; --- Pass 6: map tile (col+1, row-2) → TileAnim_VramAddrs+40..+46 ---
    LDA.b !Field_TileAnimX
    INC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+40 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+42 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+44 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+46 ; bottom-right 8x8 tile


    SEP #$20
    LDA.b #!VramQueue_TileAnim
    TSB.b !Field_VramQueueFlags
    BRL DefaultHandler

; ============================================================
; $C0:1454 — ModeFC_Handler (648 bytes, $1454–$16DB)
; Tile animation for map-tile state $FC: a 2-wide, 3-tall block,
; columns col-1..col, rows row-2..row (ModeFA_Handler mirrored).
; 6 passes; falls through into DefaultHandler.
; On entry: A = $FC, X = Map_TileProps index of (col, row), M=1, X/Y 16-bit.
; ============================================================
org $C01454
ModeFC_Handler:
    ; --- Advance the state of the 6 tiles ---
    INC A                   ; tile state $FC → $FD
    STA.l !Map_TileProps,X  ; tile (col, row)
    DEX                     ; X = tile (col-1, row)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col-1, row)
    REP #$20
    TXA
    SEC
    SBC.w #!Map_RowStride   ; A = index of (col-1, row-1)
    TAX
    SEP #$20
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col-1, row-1)
    INX                     ; X = tile (col, row-1)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col, row-1)
    REP #$20
    TXA
    SEC
    SBC.w #!Map_RowStride   ; A = index of (col, row-2)
    TAX
    SEP #$20
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col, row-2)
    DEX                     ; X = tile (col-1, row-2)
    LDA.l !Map_TileProps,X
    INC A
    STA.l !Map_TileProps,X  ; tile (col-1, row-2)
    JSR Audio_PlayTileSfxA
    LDA #$02
    STA.b !TileAnim_PairCount ; 2 + 1 pairs of tiles

    ; --- VRAM addresses of the 8x8 tiles ---
    REP #$20
    LDA.w !Map_TileOriginX
    STA.b !TileAnim_OriginX
    LDA.w !Map_TileOriginY
    STA.b !TileAnim_OriginY

    ; --- Pass 1: map tile (col-1, row) → TileAnim_VramAddrs+0..+6 ---
    LDX.b !Field_TileAnimX      ; LDX+TXA here, LDA in the other passes
    TXA
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs   ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+2 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+4 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+6 ; bottom-right 8x8 tile

    ; --- Pass 2: map tile (col-1, row-1) → TileAnim_VramAddrs+8..+14 ---
    LDA.b !Field_TileAnimX
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+8 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+10 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+12 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+14 ; bottom-right 8x8 tile

    ; --- Pass 3: map tile (col-1, row-2) → TileAnim_VramAddrs+16..+22 ---
    LDA.b !Field_TileAnimX
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+16 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+18 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+20 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+22 ; bottom-right 8x8 tile

    ; --- Pass 4: map tile (col, row) → TileAnim_VramAddrs+24..+30 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+24 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+26 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+28 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+30 ; bottom-right 8x8 tile

    ; --- Pass 5: map tile (col, row-1) → TileAnim_VramAddrs+32..+38 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+32 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+34 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+36 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+38 ; bottom-right 8x8 tile

    ; --- Pass 6: map tile (col, row-2) → TileAnim_VramAddrs+40..+46 ---
    LDA.b !Field_TileAnimX
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    LDA.b !Field_TileAnimY
    DEC
    DEC
    ASL                         ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+40 ; top-left 8x8 tile
    TYA
    PHA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+42 ; top-right 8x8 tile
    PLY
    TXA
    INC
    AND.w #!Bg_RowMask32
    TAX                         ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+44 ; bottom-left 8x8 tile
    TYA
    INC
    AND.w #!Bg_ColMask64
    TAY                         ; Y = tilemap column (0-63)
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_VramAddrs+46 ; bottom-right 8x8 tile


    SEP #$20
    LDA.b #!VramQueue_TileAnim
    TSB.b !Field_VramQueueFlags ; TileAnim_VramAddrs ready

; ============================================================
; $C0:16DC — DefaultHandler (509 bytes, $16DC–$18D8)
; The rest of Field_SceneChangeTick's request handling: reached by BRL
; when Field_SceneFlags bit 4 is clear or the tile mode is not one of
; the five Mode*_Handlers, by BRL at the end of ModeE6-FA, and by
; fall-through from ModeFC_Handler. Three independent requests:
;   bit 1 (SceneFlag_TileStep)  advance the single map tile at
;         Field_TileStepX/Y if its state is $FE or $E0, play
;         Audio_SfxTileAnimB and queue its four 8x8-tile VRAM
;         addresses in TileAnim_StepVramAddrs (VramQueue_TileStep).
;   bit 5 (SceneFlag_MapRedraw) run Field_Unk885A + VBlankHandler
;         frames until Field_Unk38 clears, then redraw map layers
;         with the DP=$1D00 builders chosen by Field_MapRedrawSel and
;         tail into Sub_EC60.
;   bit 0 (SceneFlag_Battle)    unless Scene_Unk024C returns carry,
;         enter the battle engine (JSL EngCall_BattleMain), then
;         reinstall the interrupt handlers and rebuild the field;
;         either way set FadeFlag_AfterBattle and finish with
;         Field_IdleFrame.
; Earlier notes called bit 5 a "display-mode transition" and bit 0 a
; "scene swap"; the JSL into bank $C1 identifies bit 0 as the battle.
; On entry: M=1 (A 8-bit), X=0 (X/Y 16-bit), DP=$0100.
; ============================================================
org $C016DC
DefaultHandler:
    ; --- Bit 1: single-tile step ---
    LDA.b !Field_SceneFlags
    BIT.b #!SceneFlag_TileStep
    BNE .vram_update
    BRL .bit5_check

.vram_update:
    STZ.b !TileAnim_StepKind
    LDA.b #!SceneFlag_TileStep
    TRB.b !Field_SceneFlags
    JSR Audio_PlayTileSfxB
    LDX.b !Field_TileStepX  ; 16-bit: Map_TileProps index
    LDA.l !Map_TileProps,X
    CMP.b #!TileAnim_StateFE
    BEQ .do_advance
    INC.b !TileAnim_StepKind ; 1 = the $E0 kind
    CMP.b #!TileAnim_StateE0
    BEQ .do_advance
    BRA .bit5_check         ; any other state: nothing to do

.do_advance:
    INC A                   ; $FE → $FF, $E0 → $E1
    STA.l !Map_TileProps,X

    ; --- VRAM addresses of the tile's four 8x8 tiles (as Mode*_Handler) ---
    REP #$20
    LDA.w !Map_TileOriginX
    STA.b !TileAnim_OriginX
    LDA.w !Map_TileOriginY
    STA.b !TileAnim_OriginY
    TXA                     ; index: low byte = column
    ASL                     ; map tiles are 2x2 8x8 tiles
    SEC
    SBC.b !TileAnim_OriginX
    CLC
    ADC.w !Map_BgColBias
    AND.w #!Bg_ColMask64
    TAY                     ; Y = tilemap column (0-63)
    LDA.b !Field_TileStepY
    ASL
    SEC
    SBC.b !TileAnim_OriginY
    CLC
    ADC.w !Map_BgRowBias
    AND.w #!Bg_RowMask32
    TAX                     ; X = tilemap row (0-31)
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_StepVramAddrs ; top-left 8x8 tile
    TYA
    PHA
    INC A
    AND.w #!Bg_ColMask64
    TAY                     ; column + 1
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_StepVramAddrs+2 ; top-right
    PLY                     ; column
    TXA
    INC A
    AND.w #!Bg_RowMask32
    TAX                     ; row + 1
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_StepVramAddrs+4 ; bottom-left
    TYA
    INC A
    AND.w #!Bg_ColMask64
    TAY                     ; column + 1
    TXA
    JSR Bg_TilemapIndex64x32
    CLC
    ADC.w !Map_TilemapVram
    STA.w !TileAnim_StepVramAddrs+6 ; bottom-right
    SEP #$20                ; M=1 (8-bit A)
    LDA.b #!VramQueue_TileStep
    TSB.b !Field_VramQueueFlags ; TileAnim_StepVramAddrs ready
.bit5_check:
    ; --- Bit 5: map layer redraw ---
    LDA.b !Field_SceneFlags
    BIT.b #!SceneFlag_MapRedraw
    BNE .bit5_set
    BRL .bit0_check

.bit5_set:
    LDA.b #!SceneFlag_MapRedraw
    TRB.b !Field_SceneFlags

    ; Run Field_Unk885A + VBlankHandler frames until it clears Field_Unk38
    LDA #$01
    STA.b !Field_Unk38

.loop_885A:
    JSR Field_Unk885A
    JSR VBlankHandler
    LDA.b !Field_Unk38
    BEQ .loop_done
    JSR Sub_EC60
    BRA .loop_885A

.loop_done:
    JSR Field_UnkAF4E
    JSL FdVec_FFF7
    JSR Sub_EC60

    ; --- Redraw per Field_MapRedrawSel (1-4) ---
    LDA.b !Field_MapRedrawSel
    CMP #$01
    BNE .not_mode1

    ; 1: Field_BuildC800Mode1
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD                     ; DP = $1D00 for the builders
    SEP #$20
    JSR Field_BuildC800Mode1
    PLD
    JSR Field_Unk74D4
    JSR VBlankHandlerShort
    LDA #$01
    STA.b !Field_MapRedrawDone
    STZ.b !Field_MapRedrawSel
    JSR Sub_EC60
    JSR VBlankHandlerShort
    JSR Field_Unk87F1
    BRL Sub_EC60-!BankWrap  ; offset wraps around the bank to $EC60

.not_mode1:
    CMP #$02
    BNE .not_mode2

    ; 2: Field_BuildC800Mode2
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    SEP #$20
    JSR Field_BuildC800Mode2
    PLD
    JSR Field_Unk74E8
    JSR VBlankHandlerShort
    LDA #$02
    STA.b !Field_MapRedrawDone
    STZ.b !Field_MapRedrawSel
    JSR Sub_EC60
    JSR VBlankHandlerShort
    JSR Field_Unk87F1
    BRL Sub_EC60-!BankWrap  ; offset wraps around the bank to $EC60

.not_mode2:
    CMP #$03
    BEQ .mode3
    BRL .chk_mode4

.mode3:
    ; 3: Mode1, then Mode2 and Mode1 again with the two tilemap bases
    ;    swapped around each (so both tilemaps get drawn)
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    SEP #$20
    JSR Field_BuildC800Mode1
    PLD
    JSR VBlankHandlerShort
    LDA #$03
    STA.b !Field_MapRedrawDone
    STZ.b !Field_MapRedrawSel
    JSR Sub_EC60

    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    SEP #$20
    JSR Field_BuildC800Mode2
    LDX.b !Map_TilemapVram-!DP_Map ; swap the two tilemap bases (DP=$1D00)
    PHX
    LDX.b !Map_TilemapVram2-!DP_Map
    STX.b !Map_TilemapVram-!DP_Map
    PLX
    STX.b !Map_TilemapVram2-!DP_Map
    PLD
    JSR Field_Unk74D4
    JSR Field_Unk74E8
    JSR VBlankHandlerShort
    LDA #$02
    STA.b !Field_MapRedrawDone
    JSR Sub_EC60

    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    SEP #$20
    JSR Field_BuildC800Mode1
    LDX.b !Map_TilemapVram-!DP_Map ; swap them back
    PHX
    LDX.b !Map_TilemapVram2-!DP_Map
    STX.b !Map_TilemapVram-!DP_Map
    PLX
    STX.b !Map_TilemapVram2-!DP_Map
    PLD
    JSR Field_Unk74D4
    JSR VBlankHandlerShort
    LDA #$01
    STA.b !Field_MapRedrawDone
    JSR Sub_EC60
    JSR VBlankHandlerShort
    JSR Field_Unk87F1
    BRL Sub_EC60-!BankWrap  ; offset wraps around the bank to $EC60

.chk_mode4:
    CMP #$04
    BNE .exit               ; none of 1-4

    ; 4: Field_BuildC800Mode4
    PHD
    REP #$20
    LDA.w #!DP_Map
    TCD
    SEP #$20
    JSR Field_BuildC800Mode4
    PLD
    JSR Field_Unk74F7
    JSR VBlankHandlerShort
    LDA #$04
    STA.b !Field_MapRedrawDone
    STZ.b !Field_MapRedrawSel
    JSR Sub_EC60
    JSR VBlankHandlerShort
    JSR Field_Unk87F1
    JSR Sub_EC60

.exit:
    RTS

    ; --- Bit 0: battle ---
.bit0_check:
    ; A still holds Field_SceneFlags from .bit5_check
    BIT.b #!SceneFlag_Battle
    BEQ .exit2
    JSR Scene_Unk024C
    BCS .clear_bit0         ; carry set → no battle after all

    JSL ScrollStepAccum
    LDA.b #!Field_Unk53Bit7
    TSB.b !Field_Unk53
    JSR VBlankHandlerShort
    LDA.b #!Field_Unk53Bit7
    TRB.b !Field_Unk53
    JSR Sub_EC60
    JSL EngCall_BattleMain  ; the battle (bank $C1)
    JSR InstallNMI          ; back in the field: reinstall our handlers
    JSR InstallIRQ
    REP #$20
    LDA.w #!DP_Field
    TCD                     ; DP = $0100
    SEP #$20
    LDA.b #!SceneFlag_Battle
    TRB.b !Field_SceneFlags
    LDA.b #!FadeFlag_AfterBattle
    TSB.b !Field_FadeFlags
    JSR Scene_Unk0283       ; rebuild the field
    JSR TileAnimList_ApplyAll
    JSR Sub_E935
    JSR Field_IdleFrame

.exit2:
    RTS

.clear_bit0:
    LDA.b #!SceneFlag_Battle
    TRB.b !Field_SceneFlags
    LDA.b #!FadeFlag_AfterBattle
    TSB.b !Field_FadeFlags
    BRL Field_IdleFrame

; ============================================================
; $C0:1BA7 — Audio_PlayTileSfxB (4 bytes, $1BA7–$1BAA)
; (was Sub_1BA7.) Plays sound effect Audio_SfxTileAnimB: same as
; Audio_PlayTileSfxA with the other effect id, sharing its tail
; Audio_PlaySfxAtLeader. Called from DefaultHandler.
; On entry: M=1 (A 8-bit), X=0 (X/Y 16-bit).
; ============================================================
org $C01BA7
Audio_PlayTileSfxB:
    LDA.b !Audio_SfxTileAnimB ; effect id (Audio_PlayTileSfxA uses Audio_SfxTileAnimA)
    BRA Audio_PlaySfxAtLeader ; shared tail

; ============================================================
; $C0:CB0A — Sub_CB0A (48 bytes, $CB0A–$CB39)
; Top-level sprite-slot init dispatcher.
; Validates the current entity (slot $6D): skips if $1100,X bit7
; set, $1A81,X is zero or negative, or $0F00,X is zero.
; Then reads bits 0-1 of $1201,X (sprite type/pass index) and
; tail-calls the matching initializer:
;   0 → BRL Sub_CDC8 (single-slot)
;   1 → BRL Sub_D124 (8-slot OAM init)
;   2 → BRL Sub_DD28 (12-slot OAM init)
;   other → CLC + RTS
; Entry: M=1 (A 8-bit), X/Y=16-bit.
; ============================================================
org $C0CB0A
Sub_CB0A:
    LDX $6D                  ; entity slot index
    LDA $1100,X              ; sprite state flag
    BPL .cb0a_active         ; bit7 clear → entity active
.cb0a_exit:
    RTS                      ; shared early-exit RTS at $CB11
.cb0a_active:                ; $CB12
    LDA $1A81,X              ; timer/state byte
    BEQ .cb0a_exit           ; zero → early exit (back to $CB11)
    BMI .cb0a_exit           ; negative → early exit (back to $CB11)
    LDA $0F00,X              ; animation type
    BEQ .cb0a_exit           ; zero → early exit (back to $CB11)
    LDA $1201,X              ; sprite pass/type flags
    AND #$03                 ; isolate bits 0-1
    BEQ .cb0a_type0          ; == 0: single-slot
    CMP #$01
    BNE .cb0a_check2
    BRA .cb0a_type1          ; == 1: dual-slot
.cb0a_check2:
    CMP #$02
    BEQ .cb0a_type2          ; == 2: 12-slot
    CLC
    RTS                      ; other: CLC + RTS
.cb0a_type0:
    BRL Sub_CDC8                ; tail-call Sub_CDC8 ($CDC8)
.cb0a_type1:
    BRL Sub_D124                ; tail-call Sub_D124 ($D124)
.cb0a_type2:
    BRL Sub_DD28                ; tail-call Sub_DD28 ($DD28)

; ============================================================
; $C0:CB3A — Sub_CB3A (162 bytes, $CB3A–$CBDB)
; Animation-frame gate for sprite-slot init routines.
; Computes a frame-data pointer into dp:$D6 from entity animation
; state ($1600,X), sprite width ($1480,X), and sprite base offset
; ($1500,X):
;   state = 0  → $D6 = $1500,X
;   state = 2  → $D6 = 2×$1480,X + $1500,X
;   state > 0  → $D6 = 3×$1480,X + $1500,X
;   state < 0  → $D6 = $1480,X + $1500,X
; Then adjusts $D6 by (animType×4 + animRowHi) to reach the
; current frame entry, and reads the frame byte via [$D6]:
;   • If byte ≠ $FF: SEC + RTS (caller should init this sprite).
;   • If byte = $FF and anim type = 2: decrement $7F0B01,X timer;
;     return CLC + RTS (skip until timer hits 0, then CLC + RTS).
;   • If byte = $FF and other type: wrap $D6 back by animRowHi,
;     store $FF into $1681,X, re-read wrapped frame byte; SEC + RTS.
; Entry: M=1 (A 8-bit), X=0 (X/Y 16-bit); X = entity slot.
; Exit:  SEC = proceed; CLC = skip this frame.
; Modifies: dp:$D6 (frame ptr, 16-bit), dp:$D9 (scratch, 16-bit), A.
; Preserves X (entity slot).
; Called by: Sub_CBDC ($CBFE), Sub_D28A ($D28C), …
; ============================================================
org $C0CB3A
Sub_CB3A:
    LDA $1600,X             ; animation state byte
    BEQ .zero               ; state = 0 → base path
    CMP #$02
    BEQ .two                ; state = 2 → double path
    BPL .plus               ; state > 0, != 2 → triple path
.neg:                       ; state < 0 (bit 7 set) → single-add path
    REP #$20
    LDA $1480,X             ; sprite width
    CLC
    ADC $1500,X             ; + base offset
    STA $D6
    BRA .common
.zero:
    REP #$20
    LDA $1500,X             ; base offset only
    STA $D6
    BRA .common
.plus:                      ; state > 0, not 2 → triple-add
    REP #$20
    LDA $1480,X
    STA $D9                 ; save width
    CLC
    ADC $D9                 ; 2× width
    ADC $D9                 ; 3× width
    ADC $1500,X             ; + base offset
    STA $D6
    BRA .common
.two:                       ; state = 2 → double-add
    REP #$20
    LDA $1480,X
    ASL                     ; 2× width
    CLC
    ADC $1500,X             ; + base offset
    STA $D6
    ; fall through to .common (M=0)
.common:
    LDA $1681,X             ; animation row high byte (zero-extended)
    AND #$00FF
    STA $D9                 ; save as animRowHi
    LDA $1780,X             ; animation type field
    AND #$00FF
    CMP #$0002              ; type == 2?
    BNE .not_two
.type_two:
    LDA $1781,X             ; type-2 subfield
    AND #$00FF
    ASL                     ; × 2
    ASL                     ; × 4
    CLC
    ADC $D9                 ; + animRowHi
    ADC $D6                 ; + base pointer
    STA $D6                 ; → adjusted frame pointer
    SEP #$20
    LDA [$D6]               ; read frame data byte
    CMP #$FF
    BNE .proceed            ; not $FF → sprite is ready
    LDA $7F0B01,X           ; countdown timer (WRAM)
    DEC
    BEQ .skip_store         ; timer hit 0: just clear carry and return
    STA $7F0B01,X           ; store decremented timer
.skip_store:
    CLC
    RTS                     ; not ready this frame
.not_two:
    LDA $1680,X             ; standard anim frame field
    AND #$00FF
    ASL                     ; × 2
    ASL                     ; × 4
    CLC
    ADC $D9                 ; + animRowHi
    ADC $D6                 ; + base pointer
    STA $D6                 ; → adjusted frame pointer
    SEP #$20
    LDA [$D6]               ; read frame data byte
    CMP #$FF
    BNE .proceed            ; not $FF → sprite is ready
    REP #$20
    LDA $D6                 ; current frame pointer
    SEC
    SBC $D9                 ; subtract animRowHi → row start
    STA $D6
    SEP #$20
    LDA #$FF
    STA $1681,X             ; mark frame row as exhausted
    LDA [$D6]               ; re-read wrapped frame byte
.proceed:
    SEC
    RTS

; ============================================================
; $C0:CBDC — Sub_CBDC (492 bytes, $CBDC–$CDC7)
; Single-slot, animation-gated, 16-tile sprite-slot init.
; Sets up dp:$CF/$D2 (tile bank ptr) and dp:$CD (table ptr),
; then either uses $1301,X directly (type-3: $1780,X==$03) or
; calls Sub_CB3A for the animation gate.  Allocates one VRAM
; slot via Sub_E952; if same frame as last call (CMP $0F01,X),
; returns CLC with no work.  On new frame: copies 16 tile
; entries ($0010 iterations) through Sub_E687/Sub_E534 into
; WRAM via WMDATA; writes 4-entry (Y/X/attr) OAM staging data
; to $7F:4802+slot and the DMA descriptor to $09xx; CLC RTS.
; Entry: M=1, X/Y=16-bit; X = entity slot index.
; Exit:  CLC always (caller checks separately if needed).
; ============================================================
org $C0CBDC
Sub_CBDC:
    LDA $1200,X             ; tile-data bank byte
    STA $CF
    LDA #$7F
    STA $D2                 ; dp:$D2 = $7F (pointer bank)
    REP #$20
    LDA $1280,X             ; 16-bit tile-table base address
    STA $CD
    SEP #$20
    LDA #$E4
    STA $D8                 ; palette/attr byte
    LDA $1780,X             ; animation type field
    CMP #$03
    BNE .run_gate           ; not type-3: use animation gate
    LDA $1301,X             ; type-3: use $1301,X directly as frame byte
    BRA .frame_check
.run_gate:
    JSR Sub_CB3A               ; animation-frame gate (Sub_CB3A)
    BCS .frame_check        ; gate passed (SEC) → proceed
    RTS                     ; gate failed (CLC) → skip
.frame_check:
    CMP $0F01,X             ; same frame as last?
    BNE .new_frame
.no_work:
    CLC
    RTS                     ; same frame → no work
.new_frame:
    STA $EE                 ; save frame byte
    JSR Sub_E952               ; single-slot allocator
    BCC .no_work            ; allocation failed → backward branch to CLC+RTS
    LDA $EE
    STA $0F01,X             ; record current frame
    REP #$20
    LDX $6D
    LDA $0D80,X             ; VRAM base for allocated slot
    STA $D0
    SEP #$20
    LDA $0F01,X             ; frame# for multiplier
    STA $4202               ; WRMPYA
    LDA #$28
    STA $4203               ; WRMPYB = 40 (16 tiles × 2.5 bytes)
    LDA $1300,X
    STA $D5
    REP #$20
    LDA $4216               ; RDMPYL = frame# × 40
    CLC
    ADC $1380,X             ; + tile-row base → tile data pointer
    STA $D3
    SEP #$30
    LDA #$01
    STA $2183               ; WMADDH = bank 1
    REP #$30
    LDA $D0
    STA $2181               ; WMADDL = VRAM target
    LDA #$0010              ; loop count = 16 tiles
    STA $C9
    LDY #$0000
    BRA .check              ; enter loop at condition check
.next:
    LDA $D0
    CLC
    ADC #$0020
    STA $D0
.check:
    LDA [$D3],Y
    BIT #$4000
    BNE .fd_path
    JSR Sub_E687               ; bank-switch tile copy
    INY
    INY
    DEC $C9
    BNE .next
    BRA .after_loop
.fd_path:
    JSR Sub_E534               ; FD00-table WRAM fill
    INY
    INY
    DEC $C9
    BNE .next
.after_loop:
    ; --- OAM staging: DMA descriptor into $09xx ---
    SEP #$10                ; X/Y → 8-bit
    LDX $6D
    LDA $0D00,X             ; entity tile VRAM index (16-bit A, 8-bit X)
    AND #$01FF              ; mask to 9-bit VRAM tile number
    ASL
    ASL
    ASL
    ASL                     ; × 16 = VRAM tile slot address
    LDX $79                 ; OAM buffer write pointer
    STA $0950,X             ; slot-A tile#
    CLC
    ADC #$0100
    STA $0970,X             ; slot-B tile# (+256)
    LDX $6D
    LDA $0D80,X             ; VRAM base
    LDX $79
    STA $0940,X             ; slot-A VRAM base
    CLC
    ADC #$0100
    STA $0960,X             ; slot-B VRAM base
    LDA #$0100
    STA $0980,X             ; slot-A size
    STA $0990,X             ; slot-B size
    INC $09A0,X             ; bump slot-A entry count
    INX
    INX
    STZ $09A0,X             ; zero slot-B
    STX $79                 ; save updated buffer ptr
    ; --- OAM Y / tile entry writes to $7F:4802+slot ---
    REP #$20
    LDX $6D
    LDA $1700,X             ; OAM slot base index (16-bit)
    REP #$10                ; X → 16-bit
    TAX                     ; X = OAM slot index
    SEP #$20
    LDY #$0020              ; offset into tile data for OAM entries
    ; tile 0 Y-pos
    LDA [$D3],Y
    STA $7F4802,X
    BPL .y0pos
    LDA #$FF
    BRA .y0hi
.y0pos:
    LDA #$00
.y0hi:
    STA $7F4803,X
    INY
    LDA [$D3],Y
    STA $7F4804,X
    ; tile 1 Y-pos
    INY
    LDA [$D3],Y
    STA $7F480A,X
    BPL .y1pos
    LDA #$FF
    BRA .y1hi
.y1pos:
    LDA #$00
.y1hi:
    STA $7F480B,X
    INY
    LDA [$D3],Y
    STA $7F480C,X
    ; tile 2 Y-pos
    INY
    LDA [$D3],Y
    STA $7F4812,X
    BPL .y2pos
    LDA #$FF
    BRA .y2hi
.y2pos:
    LDA #$00
.y2hi:
    STA $7F4813,X
    INY
    LDA [$D3],Y
    STA $7F4814,X
    ; tile 3 Y-pos
    INY
    LDA [$D3],Y
    STA $7F481A,X
    BPL .y3pos
    LDA #$FF
    BRA .y3hi
.y3pos:
    LDA #$00
.y3hi:
    STA $7F481B,X
    INY
    LDA [$D3],Y
    STA $7F481C,X
    ; --- OAM X-positions from entity table ---
    LDY $6D
    LDA $0D00,Y             ; entity X base
    STA $7F4806,X
    INC
    INC
    STA $7F480E,X
    INC
    INC
    STA $7F4816,X
    INC
    INC
    STA $7F481E,X
    ; --- OAM attribute/high bytes (palette + visibility) ---
    LDA $0F81,Y
    ORA $0D01,Y
    STA $D9                 ; palette + priority composite
    ; tile 0 attr
    LDA $7F4804,X
    CMP #$E8
    BCC .a0within
    LDA $D9
    ORA $0C01,Y
    STA $7F4807,X
    BRA .a1test
.a0within:
    LDA $D9
    ORA $0C00,Y
    STA $7F4807,X
    ; tile 1 attr
.a1test:
    LDA $7F480C,X
    CMP #$E8
    BCC .a1within
    LDA $D9
    ORA $0C01,Y
    STA $7F480F,X
    BRA .a2test
.a1within:
    LDA $D9
    ORA $0C00,Y
    STA $7F480F,X
    ; tile 2 attr
.a2test:
    LDA $7F4814,X
    CMP #$E8
    BCC .a2within
    LDA $D9
    ORA $0C01,Y
    STA $7F4817,X
    BRA .a3test
.a2within:
    LDA $D9
    ORA $0C00,Y
    STA $7F4817,X
    ; tile 3 attr
.a3test:
    LDA $7F481C,X
    CMP #$E8
    BCC .a3within
    LDA $D9
    ORA $0C01,Y
    STA $7F481F,X
    BRA .cbdc_done
.a3within:
    LDA $D9
    ORA $0C00,Y
    STA $7F481F,X
.cbdc_done:
    LDX $6D
    INC $1B00,X
    SEP #$10
    CLC
    RTS

; ============================================================
; $C0:CDC8 — Sub_CDC8 (301 bytes, $CDC8–$CEF4)
; Single-slot, no animation gate, OAM-update for $7F:4BC2+slot.
; Uses the current frame# from $0F01,X directly (no gate call).
; Computes tile-data pointer from frame# × $28 + $1380,X, then
; loads OAM slot index from $1700,X and writes 4 Y-entries
; (with sign-extension) and 4 X-entries (+2 step) to $7F:4BC2+.
; Sets $1B00,X = $80 (marks entry as "OAM-only updated").
; Entry: M=1, X/Y=16-bit; X = entity slot.
; ============================================================
org $C0CDC8
Sub_CDC8:
    LDX $6D
    LDA $0F01,X             ; current frame# (no gate)
    STA $4202               ; WRMPYA
    LDA #$28
    STA $4203               ; WRMPYB = 40
    LDA $1300,X
    STA $D5
    REP #$20
    LDA $4216               ; frame# × 40
    CLC
    ADC $1380,X
    STA $D3                 ; tile data pointer
    LDA $1700,X             ; OAM slot index (16-bit)
    REP #$10                ; X → 16-bit
    TAX                     ; X = OAM slot index
    SEP #$20
    LDY #$0020              ; offset to OAM position data in tile table
    ; tile 0 Y-pos → $7F:4BC2+X
    LDA [$D3],Y
    STA $7F4BC2,X
    BPL .y0pos
    LDA #$FF
    BRA .y0hi
.y0pos:
    LDA #$00
.y0hi:
    STA $7F4BC3,X
    INY
    LDA [$D3],Y
    STA $7F4BC4,X
    ; tile 1 Y-pos
    INY
    LDA [$D3],Y
    STA $7F4BCA,X
    BPL .y1pos
    LDA #$FF
    BRA .y1hi
.y1pos:
    LDA #$00
.y1hi:
    STA $7F4BCB,X
    INY
    LDA [$D3],Y
    STA $7F4BCC,X
    ; tile 2 Y-pos
    INY
    LDA [$D3],Y
    STA $7F4BD2,X
    BPL .y2pos
    LDA #$FF
    BRA .y2hi
.y2pos:
    LDA #$00
.y2hi:
    STA $7F4BD3,X
    INY
    LDA [$D3],Y
    STA $7F4BD4,X
    ; tile 3 Y-pos
    INY
    LDA [$D3],Y
    STA $7F4BDA,X
    BPL .y3pos
    LDA #$FF
    BRA .y3hi
.y3pos:
    LDA #$00
.y3hi:
    STA $7F4BDB,X
    INY
    LDA [$D3],Y
    STA $7F4BDC,X
    ; --- X-positions from entity table (Y still 8-bit from SEP#10 earlier? no) ---
    LDY $6D                 ; entity slot index (dp LDY)
    LDA $0D00,Y             ; entity X base
    STA $7F4BC6,X
    INC
    INC
    STA $7F4BCE,X
    INC
    INC
    STA $7F4BD6,X
    INC
    INC
    STA $7F4BDE,X
    ; --- OAM attribute/high bytes ---
    LDA $0F81,Y
    ORA $0D01,Y
    STA $D9
    ; tile 0 attr
    LDA $7F4BC4,X
    CMP #$E8
    BCC .a0within
    LDA $D9
    ORA $0C01,Y
    STA $7F4BC7,X
    BRA .a1test
.a0within:
    LDA $D9
    ORA $0C00,Y
    STA $7F4BC7,X
    ; tile 1 attr
.a1test:
    LDA $7F4BCC,X
    CMP #$E8
    BCC .a1within
    LDA $D9
    ORA $0C01,Y
    STA $7F4BCF,X
    BRA .a2test
.a1within:
    LDA $D9
    ORA $0C00,Y
    STA $7F4BCF,X
    ; tile 2 attr
.a2test:
    LDA $7F4BD4,X
    CMP #$E8
    BCC .a2within
    LDA $D9
    ORA $0C01,Y
    STA $7F4BD7,X
    BRA .a3test
.a2within:
    LDA $D9
    ORA $0C00,Y
    STA $7F4BD7,X
    ; tile 3 attr
.a3test:
    LDA $7F4BDC,X
    CMP #$E8
    BCC .a3within
    LDA $D9
    ORA $0C01,Y
    STA $7F4BDF,X
    BRA .cdc8_done
.a3within:
    LDA $D9
    ORA $0C00,Y
    STA $7F4BDF,X
.cdc8_done:
    LDX $6D
    LDA #$80
    STA $1B00,X
    SEP #$10
    CLC
    RTS

; ============================================================
; $C0:CEF5 — Sub_CEF5 (559 bytes, $CEF5–$D123)
; Complex sprite-slot dispatch with three paths:
;   type==3  ($1780,X==$03): full 32-tile dual-slot init via
;            Sub_E97A + 32-entry loop.
;   $1B00,X & $7F == 0: tail-call → Sub_D28A (first-pass,
;            16 tiles, Y=0).
;   $1B00,X & $7F != 0: tail-call → Sub_D30D (second-pass,
;            16 tiles, Y=$20, VRAM base+$200).
; On type-3 success: INC $1B00,X twice; CLC RTS.
; On dispatch path: returns whatever Sub_D28A / Sub_D30D returns.
; Entry: M=1, X/Y=16-bit; X = entity slot.
; ============================================================
org $C0CEF5
Sub_CEF5:
    LDA $1200,X
    STA $CF
    LDA #$7F
    STA $D2
    REP #$20
    LDA $1280,X
    STA $CD
    SEP #$20
    LDA #$E4
    STA $D8
    LDA $1780,X             ; animation type
    CMP #$03
    BNE .check_pass         ; not type-3 → check pass counter
    BRA .type3_path         ; type-3 → full 32-tile path
.check_pass:
    LDA $1B00,X
    AND #$7F
    BEQ .first_pass         ; pass counter == 0: first pass
    BRL Sub_D30D               ; pass counter != 0: tail-call Sub_D30D
.first_pass:
    BRL Sub_D28A               ; tail-call Sub_D28A
    ; ---- type-3 full 32-tile path ----
.type3_path:
    LDA $1301,X             ; use $1301,X directly as frame byte
    CMP $0F01,X
    BNE .t3_new_frame
.t3_nc_exit:
    CLC
    RTS                     ; same frame → no work
.t3_new_frame:
    STA $EE
    JSR Sub_E97A               ; dual-slot allocator
    BCC .t3_nc_exit         ; allocation failed → backward branch to CLC+RTS
    LDA $EE
    STA $0F01,X
    REP #$20
    LDX $6D
    LDA $0D80,X             ; VRAM base
    STA $D0
    SEP #$20
    LDA $0F01,X
    STA $4202               ; WRMPYA
    LDA #$50
    STA $4203               ; WRMPYB = 80
    LDA $1300,X
    STA $D5
    REP #$20
    LDA $4216               ; frame# × 80
    CLC
    ADC $1380,X
    STA $D3
    SEP #$20
    LDA #$01
    STA $2183               ; WMADDH
    REP #$30
    LDA $D0
    STA $2181               ; WMADDL
    LDA #$0020              ; 32 tiles
    STA $C9
    LDY #$0000
    BRA .t3_check
.t3_next:
    LDA $D0
    CLC
    ADC #$0020
    STA $D0
.t3_check:
    LDA [$D3],Y
    BIT #$4000
    BNE .t3_fd
    JSR Sub_E687
    INY
    INY
    DEC $C9
    BNE .t3_next
    BRA .t3_after_loop
.t3_fd:
    JSR Sub_E534
    INY
    INY
    DEC $C9
    BNE .t3_next
.t3_after_loop:
    ; --- OAM staging for 32-tile dual-slot ---
    SEP #$10
    LDX $6D
    LDA $0D00,X
    AND #$01FF
    ASL
    ASL
    ASL
    ASL
    LDX $79
    STA $0950,X
    CLC
    ADC #$0100
    STA $0970,X
    LDX $6D
    LDA $0D80,X
    LDX $79
    STA $0940,X
    CLC
    ADC #$0200
    STA $0960,X
    LDA #$0200
    STA $0980,X
    STA $0990,X
    INC $09A0,X
    INX
    INX
    STZ $09A0,X
    STX $79
    ; --- OAM Y/tile writes to $7F:4802+slot (Y from $40) ---
    REP #$20
    LDX $6D
    LDA.l $001700,X
    REP #$10
    TAX
    SEP #$20
    LDY #$0040              ; offset = 64 (8 tile-entry pairs × 2 bytes, after 32 tiles)
    ; entry 0 Y-pos
    LDA [$D3],Y
    STA $7F4802,X
    BPL .t3y0pos
    LDA #$FF
    BRA .t3y0hi
.t3y0pos:
    LDA #$00
.t3y0hi:
    STA $7F4803,X
    INY
    LDA [$D3],Y
    STA $7F4804,X
    ; entry 1
    INY
    LDA [$D3],Y
    STA $7F480A,X
    BPL .t3y1pos
    LDA #$FF
    BRA .t3y1hi
.t3y1pos:
    LDA #$00
.t3y1hi:
    STA $7F480B,X
    INY
    LDA [$D3],Y
    STA $7F480C,X
    ; entry 2
    INY
    LDA [$D3],Y
    STA $7F4812,X
    BPL .t3y2pos
    LDA #$FF
    BRA .t3y2hi
.t3y2pos:
    LDA #$00
.t3y2hi:
    STA $7F4813,X
    INY
    LDA [$D3],Y
    STA $7F4814,X
    ; entry 3
    INY
    LDA [$D3],Y
    STA $7F481A,X
    BPL .t3y3pos
    LDA #$FF
    BRA .t3y3hi
.t3y3pos:
    LDA #$00
.t3y3hi:
    STA $7F481B,X
    INY
    LDA [$D3],Y
    STA $7F481C,X
    ; entry 4
    INY
    LDA [$D3],Y
    STA $7F4822,X
    BPL .t3y4pos
    LDA #$FF
    BRA .t3y4hi
.t3y4pos:
    LDA #$00
.t3y4hi:
    STA $7F4823,X
    INY
    LDA [$D3],Y
    STA $7F4824,X
    ; entry 5
    INY
    LDA [$D3],Y
    STA $7F482A,X
    BPL .t3y5pos
    LDA #$FF
    BRA .t3y5hi
.t3y5pos:
    LDA #$00
.t3y5hi:
    STA $7F482B,X
    INY
    LDA [$D3],Y
    STA $7F482C,X
    ; entry 6
    INY
    LDA [$D3],Y
    STA $7F4832,X
    BPL .t3y6pos
    LDA #$FF
    BRA .t3y6hi
.t3y6pos:
    LDA #$00
.t3y6hi:
    STA $7F4833,X
    INY
    LDA [$D3],Y
    STA $7F4834,X
    ; entry 7
    INY
    LDA [$D3],Y
    STA $7F483A,X
    BPL .t3y7pos
    LDA #$FF
    BRA .t3y7hi
.t3y7pos:
    LDA #$00
.t3y7hi:
    STA $7F483B,X
    INY
    LDA [$D3],Y
    STA $7F483C,X
    ; --- X-positions (entity base + 2-step) ---
    LDY $6D
    LDA $0D00,Y
    STA $7F4806,X
    INC
    INC
    STA $7F480E,X
    INC
    INC
    STA $7F4816,X
    INC
    INC
    STA $7F481E,X
    INC
    INC
    STA $7F4826,X
    INC
    INC
    STA $7F482E,X
    INC
    INC
    STA $7F4836,X
    INC
    INC
    STA $7F483E,X
    ; --- attribute bytes ---
    LDA $0F81,Y
    ORA $0D01,Y
    STA $D9                 ; A still holds the composite value
    ORA $0C00,Y             ; no LDA $D9 needed: A unchanged since STA $D9
    STA $7F4807,X
    STA $7F480F,X
    STA $7F4817,X
    STA $7F481F,X
    LDA $D9                 ; reload for second group (A was modified by ORA $0C00)
    ORA $0C01,Y
    STA $7F4827,X
    STA $7F482F,X
    STA $7F4837,X
    STA $7F483F,X
    LDX $6D
    INC $1B00,X
    INC $1B00,X
    SEP #$10
    CLC
    RTS

; ============================================================
; $C0:D124 — Sub_D124 (358 bytes, $D124–$D289)
; 8-slot OAM buffer init, pass-1 path (sprite type 1).
; Called via BRL from Sub_CB0A when bits 0-1 of $1201,X == 1.
; Computes animation data pointer: frame# × $50 + $1380,X,
; using $1300,X as the data bank byte (dp:$D5/$D3).
; Reads OAM buffer index from WRAM table $001700,X (16-bit).
; Starting at animation data offset Y=$40, reads 8 tile-index/
; attribute pairs and writes them into the $7F4Bxx OAM staging
; buffer (8 groups at stride $08: C2–FC).
; Sets 8 X-position bytes (C6–FE) and priority/attribute bytes
; (C7/CF/D7/DF from $0C00; E7/EF/F7/FF from $0C01).
; On completion: sets $1B00,X = $80, SEP #$10, CLC, RTS.
; Entry: M=1, X/Y=16-bit; X = entity slot.
; ============================================================
org $C0D124
Sub_D124:
    LDA $0F01,X              ; current animation frame number
    STA $4202                ; WRMPYA
    LDA #$50                 ; multiply by $50 = 80 (bytes per frame entry)
    STA $4203                ; WRMPYB → triggers multiply
    LDA $1300,X              ; animation data bank byte
    STA $D5
    REP #$20                 ; A 16-bit
    LDA $4216                ; RDMPYL: result of frame# × $50
    CLC
    ADC $1380,X              ; add sprite base offset
    STA $D3                  ; dp:$D3 = animation data ptr (16-bit)
    REP #$20                 ; (already 16-bit; ensures A mode explicit)
    LDA.l $001700,X          ; OAM buffer index from WRAM table (16-bit)
    REP #$10                 ; X/Y 16-bit
    TAX                      ; X = OAM buffer index
    SEP #$20                 ; A 8-bit
    LDY #$0040               ; start at animation data offset $40
    ; --- 8 OAM tile-entry groups (stride $08) ---
    ; entry 0: OAM C2/C3/C4
    LDA [$D3],Y
    STA $7F4BC2,X
    BPL .d124_y0p
    LDA #$FF
    BRA .d124_y0h
.d124_y0p:
    LDA #$00
.d124_y0h:
    STA $7F4BC3,X
    INY
    LDA [$D3],Y
    STA $7F4BC4,X
    ; entry 1: OAM CA/CB/CC
    INY
    LDA [$D3],Y
    STA $7F4BCA,X
    BPL .d124_y1p
    LDA #$FF
    BRA .d124_y1h
.d124_y1p:
    LDA #$00
.d124_y1h:
    STA $7F4BCB,X
    INY
    LDA [$D3],Y
    STA $7F4BCC,X
    ; entry 2: OAM D2/D3/D4
    INY
    LDA [$D3],Y
    STA $7F4BD2,X
    BPL .d124_y2p
    LDA #$FF
    BRA .d124_y2h
.d124_y2p:
    LDA #$00
.d124_y2h:
    STA $7F4BD3,X
    INY
    LDA [$D3],Y
    STA $7F4BD4,X
    ; entry 3: OAM DA/DB/DC
    INY
    LDA [$D3],Y
    STA $7F4BDA,X
    BPL .d124_y3p
    LDA #$FF
    BRA .d124_y3h
.d124_y3p:
    LDA #$00
.d124_y3h:
    STA $7F4BDB,X
    INY
    LDA [$D3],Y
    STA $7F4BDC,X
    ; entry 4: OAM E2/E3/E4
    INY
    LDA [$D3],Y
    STA $7F4BE2,X
    BPL .d124_y4p
    LDA #$FF
    BRA .d124_y4h
.d124_y4p:
    LDA #$00
.d124_y4h:
    STA $7F4BE3,X
    INY
    LDA [$D3],Y
    STA $7F4BE4,X
    ; entry 5: OAM EA/EB/EC
    INY
    LDA [$D3],Y
    STA $7F4BEA,X
    BPL .d124_y5p
    LDA #$FF
    BRA .d124_y5h
.d124_y5p:
    LDA #$00
.d124_y5h:
    STA $7F4BEB,X
    INY
    LDA [$D3],Y
    STA $7F4BEC,X
    ; entry 6: OAM F2/F3/F4
    INY
    LDA [$D3],Y
    STA $7F4BF2,X
    BPL .d124_y6p
    LDA #$FF
    BRA .d124_y6h
.d124_y6p:
    LDA #$00
.d124_y6h:
    STA $7F4BF3,X
    INY
    LDA [$D3],Y
    STA $7F4BF4,X
    ; entry 7: OAM FA/FB/FC
    INY
    LDA [$D3],Y
    STA $7F4BFA,X
    BPL .d124_y7p
    LDA #$FF
    BRA .d124_y7h
.d124_y7p:
    LDA #$00
.d124_y7h:
    STA $7F4BFB,X
    INY
    LDA [$D3],Y
    STA $7F4BFC,X
    ; --- X-positions (8 slots, stride +2 each) ---
    LDY $6D
    LDA $0D00,Y              ; base X coordinate
    STA $7F4BC6,X
    INC
    INC
    STA $7F4BCE,X
    INC
    INC
    STA $7F4BD6,X
    INC
    INC
    STA $7F4BDE,X
    INC
    INC
    STA $7F4BE6,X
    INC
    INC
    STA $7F4BEE,X
    INC
    INC
    STA $7F4BF6,X
    INC
    INC
    STA $7F4BFE,X
    ; --- priority/attribute bytes ---
    LDA $0F81,Y
    ORA $0D01,Y
    STA $D9
    ORA $0C00,Y
    STA $7F4BC7,X
    STA $7F4BCF,X
    STA $7F4BD7,X
    STA $7F4BDF,X
    LDA $D9
    ORA $0C01,Y
    STA $7F4BE7,X
    STA $7F4BEF,X
    STA $7F4BF7,X
    STA $7F4BFF,X
    LDX $6D
    LDA #$80
    STA.w $1B00,X
    SEP #$10
    CLC
    RTS

; ============================================================
; $C0:D28A — Sub_D28A (131 bytes, $D28A–$D30C)
; Dual-slot, animation-gated, 16-tile sprite-slot init.
; Called directly and also as a tail-call target (BRL from
; Sub_CEF5 at $CF1E) for the first-pass case.
; Calls Sub_CB3A to check the animation gate; on pass, calls
; Sub_E97A to allocate two VRAM slots; copies 16 tile entries
; (frame# × $50 offset, 16 iterations via Sub_E687/E534) into
; WRAM.  Increments $1B00,X on success; SEC RTS.
; Entry: M=1, X/Y=16-bit; X = entity slot.
; ============================================================
org $C0D28A
Sub_D28A:
    JSR Sub_CB3A               ; animation-frame gate
    BCS .d28a_proceed
    RTS                     ; gate failed → CLC, skip
.d28a_proceed:
    CMP $0F01,X             ; same frame?
    BNE .d28a_new_frame
.d28a_nc_exit:
    CLC
    RTS
.d28a_new_frame:
    STA $EE
    JSR Sub_E97A               ; dual-slot allocator
    BCC .d28a_nc_exit       ; allocation failed → backward branch to CLC+RTS
    LDA $EE
    STA $0F01,X
    REP #$20
    LDX $6D
    LDA $0D80,X
    STA $D0
    SEP #$20
    LDA $0F01,X
    STA $4202               ; WRMPYA
    LDA #$50
    STA $4203               ; WRMPYB = 80
    LDA $1300,X
    STA $D5
    REP #$20
    LDA $4216               ; frame# × 80
    CLC
    ADC $1380,X
    STA $D3
    SEP #$30
    LDA #$01
    STA $2183               ; WMADDH
    REP #$30
    LDA $D0
    STA $2181               ; WMADDL
    LDA #$0010              ; 16 tiles
    STA $C9
    LDY #$0000
    BRA .d28a_check
.d28a_next:
    LDA $D0
    CLC
    ADC #$0020
    STA $D0
.d28a_check:
    LDA [$D3],Y
    BIT #$4000
    BNE .d28a_fd
    JSR Sub_E687
    INY
    INY
    DEC $C9
    BNE .d28a_next
    BRA .d28a_done
.d28a_fd:
    JSR Sub_E534
    INY
    INY
    DEC $C9
    BNE .d28a_next
.d28a_done:
    SEP #$30
    LDX $6D
    INC $1B00,X
    SEC
    RTS

; ============================================================
; $C0:D30D — Sub_D30D (490 bytes, $D30D–$D4F6)
; Dual-slot second-pass: 16 tiles from Y=$20 into VRAM base+$200.
; Tail-call target (BRL from Sub_CEF5 $CF1B) for pass counter != 0.
; Uses existing slot allocation ($0D80,X + $200 for second slot).
; Copies 16 tile entries starting at tile-data offset Y=$20 through
; Sub_E687/Sub_E534; writes 8-entry OAM staging to $7F:4802+slot
; (Y from $40); CLC RTS on success.
; Entry: M=1, X/Y=16-bit; X = entity slot (via $6D).
; ============================================================
org $C0D30D
Sub_D30D:
    REP #$20
    LDA $0D80,X
    CLC
    ADC #$0200              ; second-slot VRAM base
    STA $D0
    SEP #$20
    LDA $0F01,X
    STA $4202               ; WRMPYA
    LDA #$50
    STA $4203               ; WRMPYB = 80
    LDA $1300,X
    STA $D5
    REP #$20
    LDA $4216               ; frame# × 80
    CLC
    ADC $1380,X
    STA $D3
    SEP #$20
    LDA #$01
    STA $2183               ; WMADDH
    REP #$30
    LDA $D0
    STA $2181               ; WMADDL
    LDA #$0010              ; 16 tiles
    STA $C9
    LDY #$0020              ; start at tile-data offset 32 (second half)
    BRA .d30d_check
.d30d_next:
    LDA $D0
    CLC
    ADC #$0020
    STA $D0
.d30d_check:
    LDA [$D3],Y
    BIT #$4000
    BNE .d30d_fd
    JSR Sub_E687
    INY
    INY
    DEC $C9
    BNE .d30d_next
    BRA .d30d_after_loop
.d30d_fd:
    JSR Sub_E534
    INY
    INY
    DEC $C9
    BNE .d30d_next
.d30d_after_loop:
    ; --- OAM staging ---
    SEP #$10
    LDX $6D
    LDA $0D00,X
    AND #$01FF
    ASL
    ASL
    ASL
    ASL
    LDX $79
    STA $0950,X
    CLC
    ADC #$0100
    STA $0970,X
    LDX $6D
    LDA $0D80,X
    LDX $79
    STA $0940,X
    CLC
    ADC #$0200
    STA $0960,X
    LDA #$0200
    STA $0980,X
    STA $0990,X
    INC $09A0,X
    INX
    INX
    STZ $09A0,X
    STX $79
    ; --- OAM Y/tile writes (Y from $40) ---
    LDX $6D
    LDA.l $001700,X
    REP #$10
    TAX
    SEP #$20
    LDY #$0040
    ; entry 0
    LDA [$D3],Y
    STA $7F4802,X
    BPL .d30d_y0pos
    LDA #$FF
    BRA .d30d_y0hi
.d30d_y0pos:
    LDA #$00
.d30d_y0hi:
    STA $7F4803,X
    INY
    LDA [$D3],Y
    STA $7F4804,X
    ; entry 1
    INY
    LDA [$D3],Y
    STA $7F480A,X
    BPL .d30d_y1pos
    LDA #$FF
    BRA .d30d_y1hi
.d30d_y1pos:
    LDA #$00
.d30d_y1hi:
    STA $7F480B,X
    INY
    LDA [$D3],Y
    STA $7F480C,X
    ; entry 2
    INY
    LDA [$D3],Y
    STA $7F4812,X
    BPL .d30d_y2pos
    LDA #$FF
    BRA .d30d_y2hi
.d30d_y2pos:
    LDA #$00
.d30d_y2hi:
    STA $7F4813,X
    INY
    LDA [$D3],Y
    STA $7F4814,X
    ; entry 3
    INY
    LDA [$D3],Y
    STA $7F481A,X
    BPL .d30d_y3pos
    LDA #$FF
    BRA .d30d_y3hi
.d30d_y3pos:
    LDA #$00
.d30d_y3hi:
    STA $7F481B,X
    INY
    LDA [$D3],Y
    STA $7F481C,X
    ; entry 4
    INY
    LDA [$D3],Y
    STA $7F4822,X
    BPL .d30d_y4pos
    LDA #$FF
    BRA .d30d_y4hi
.d30d_y4pos:
    LDA #$00
.d30d_y4hi:
    STA $7F4823,X
    INY
    LDA [$D3],Y
    STA $7F4824,X
    ; entry 5
    INY
    LDA [$D3],Y
    STA $7F482A,X
    BPL .d30d_y5pos
    LDA #$FF
    BRA .d30d_y5hi
.d30d_y5pos:
    LDA #$00
.d30d_y5hi:
    STA $7F482B,X
    INY
    LDA [$D3],Y
    STA $7F482C,X
    ; entry 6
    INY
    LDA [$D3],Y
    STA $7F4832,X
    BPL .d30d_y6pos
    LDA #$FF
    BRA .d30d_y6hi
.d30d_y6pos:
    LDA #$00
.d30d_y6hi:
    STA $7F4833,X
    INY
    LDA [$D3],Y
    STA $7F4834,X
    ; entry 7
    INY
    LDA [$D3],Y
    STA $7F483A,X
    BPL .d30d_y7pos
    LDA #$FF
    BRA .d30d_y7hi
.d30d_y7pos:
    LDA #$00
.d30d_y7hi:
    STA $7F483B,X
    INY
    LDA [$D3],Y
    STA $7F483C,X
    ; --- X-positions ---
    LDY $6D
    LDA $0D00,Y
    STA $7F4806,X
    INC
    INC
    STA $7F480E,X
    INC
    INC
    STA $7F4816,X
    INC
    INC
    STA $7F481E,X
    INC
    INC
    STA $7F4826,X
    INC
    INC
    STA $7F482E,X
    INC
    INC
    STA $7F4836,X
    INC
    INC
    STA $7F483E,X
    ; --- attribute bytes (lower 4 use $0C00, upper 4 use $0C01) ---
    LDA $0F81,Y
    ORA $0D01,Y
    STA $D9                 ; A still holds composite
    ORA $0C00,Y             ; no reload needed: A unchanged since STA $D9
    STA $7F4807,X
    STA $7F480F,X
    STA $7F4817,X
    STA $7F481F,X
    LDA $D9                 ; reload for upper group
    ORA $0C01,Y
    STA $7F4827,X
    STA $7F482F,X
    STA $7F4837,X
    STA $7F483F,X
    LDX $6D
    INC $1B00,X
    SEP #$10
    CLC
    RTS

; ============================================================
; $C0:D4F7 — Sub_D4F7 (273 bytes, $D4F7–$D607)
; Triple-slot sprite-init dispatch; analogous to Sub_CEF5 (dual-slot).
; Sets up tile-bank / graphic-slot params, then dispatches on:
;   $1B00,X & $7F == 0: pass 0  → $D546 (non-$68) or Sub_D608 ($68)
;   $1B00,X & $7F == 1: pass 1  → Sub_D68B (non-$68) or Sub_D738 ($68)
;   $1B00,X & $7F >= 2: pass 2+ → Sub_D7E5 (non-$68) or Sub_DA69 ($68)
; Type-3 sprites ($1780,X==$03): RTS immediately (no re-init).
; Body at $D546 (pass 0, non-$68): triple-slot alloc via Sub_E9AA,
;   8-tile loop to WRAM base, then 8-tile loop to WRAM base+$200; SEC RTS.
; Called from: sprite-slot entity dispatcher table (entity type dispatch).
; ============================================================
org $C0D4F7
Sub_D4F7:
    LDA $1200,X             ; sprite graphic-bank id
    STA $CF
    LDA #$7F
    STA $D2
    REP #$20
    LDA $1280,X             ; sprite graphic-pointer
    STA $CD
    SEP #$20
    LDA #$E4
    STA $D8
    ; type-3 sprites bypass all init
    LDA $1780,X
    CMP #$03
    BNE .d4f7_check_pass
    RTS
.d4f7_check_pass:
    LDA $1B00,X
    AND #$7F                ; pass counter (low 7 bits)
    BEQ .d4f7_pass0
    CMP #$01
    BEQ .d4f7_pass1
    ; pass 2+: further dispatch on $0D00,X
    LDA $0D00,X
    CMP #$68
    BEQ .d4f7_p2_68
    BRL Sub_D7E5            ; pass 2+, non-$68
.d4f7_p2_68:
    BRL Sub_DA69            ; pass 2+, $68
.d4f7_pass0:
    LDA $0D00,X
    CMP #$68
    BEQ .d4f7_p0_68
    BRA Sub_D546            ; pass 0, non-$68 → tile DMA body below
.d4f7_p0_68:
    BRL Sub_D608            ; pass 0, $68 → 16-tile single-pass variant
.d4f7_pass1:
    LDA $0D00,X
    CMP #$68
    BEQ .d4f7_p1_68
    BRL Sub_D68B            ; pass 1, non-$68
.d4f7_p1_68:
    BRL Sub_D738            ; pass 1, $68

; ============================================================
; $C0:D546 — Sub_D546 (194 bytes, $D546–$D607)
; Triple-slot first-pass, non-$68 variant.
; Reached by BRA from Sub_D4F7 (pass 0, non-$68 path) — shares
; the same return stack as the caller.  Also the label used as
; anchor for the cluster tracking table.
; Algorithm: animation gate (Sub_CB3A) → triple-slot alloc (Sub_E9AA)
;   → 8 tiles Y=0..7 to WRAM base (bank $7F slot)
;   → 8 tiles Y=8..15 to WRAM base+$200
;   → INC $1B00,X; SEC RTS.
; ============================================================
Sub_D546:
    JSR Sub_CB3A
    BCS .d546_proceed
    RTS
.d546_proceed:
    CMP $0F01,X             ; same frame already loaded?
    BNE .d546_new_frame
.d546_cle_rts:              ; shared exit: CLC + RTS (same-frame skip / alloc fail)
    CLC
    RTS
.d546_new_frame:
    STA $EE                 ; save current frame type
    JSR Sub_E9AA            ; allocate three sprite slots
    BCC .d546_cle_rts       ; alloc failed → CLC RTS
    LDA $EE
    STA $0F01,X             ; mark frame type as loaded
    REP #$20
    LDX $6D
    LDA $0D80,X             ; WRAM base for this slot group
    STA $D0
    SEP #$20
    LDA $0F01,X             ; frame number → multiply by $78 (120 tiles per frame)
    STA $4202               ; WRMPYA
    LDA #$78
    STA $4203               ; WRMPYB
    LDA $1300,X             ; tile bank byte
    STA $D5
    REP #$20
    LDA $4216               ; RDMPYL — frame# × 120 product
    CLC
    ADC $1380,X             ; add sprite base offset → frame data pointer
    STA $D3
    ; set up WMADDR for WRAM writes (bank $7F = $01)
    SEP #$30
    LDA #$01
    STA $2183               ; WMADDH
    REP #$30
    LDA $D0
    STA $2181               ; WMADDL
    ; first 8-tile loop: Y=0..7 → WRAM base
    LDA #$0008
    STA $C9
    LDY #$0000
    BRA .d546_loop1_entry
.d546_loop1_top:
    LDA $D0
    CLC
    ADC #$0020
    STA $D0
.d546_loop1_entry:
    LDA [$D3],Y
    BIT #$4000
    BNE .d546_loop1_e534
    JSR Sub_E687
    INY
    INY
    DEC $C9
    BNE .d546_loop1_top
    BRA .d546_loop2_init
.d546_loop1_e534:
    JSR Sub_E534
    INY
    INY
    DEC $C9
    BNE .d546_loop1_top
.d546_loop2_init:
    ; second 8-tile loop: Y=8..15 → WRAM base+$200
    REP #$20
    LDX $6D
    LDA $0D80,X
    CLC
    ADC #$0200
    STA $D0
    STA $2181               ; WMADDL — advance WRAM dest to slot+$200
    REP #$10
    LDA #$0008
    STA $C9
    LDY #$0010              ; word 8 in frame data (Y=16 bytes in)
    BRA .d546_loop2_entry
.d546_loop2_top:
    LDA $D0
    CLC
    ADC #$0020
    STA $D0
.d546_loop2_entry:
    LDA [$D3],Y
    BIT #$4000
    BNE .d546_loop2_e534
    JSR Sub_E687
    INY
    INY
    DEC $C9
    BNE .d546_loop2_top
    BRA .d546_done
.d546_loop2_e534:
    JSR Sub_E534
    INY
    INY
    DEC $C9
    BNE .d546_loop2_top
.d546_done:
    SEP #$30
    LDX $6D
    INC $1B00,X
    SEC
    RTS

; ============================================================
; $C0:D608 — Sub_D608 (131 bytes, $D608–$D68A)
; Triple-slot first-pass, $68 variant (Obj_BuildFrameSize2_Start).
; Animation gate → triple-slot alloc → single 16-tile loop to
; WRAM base; INC $1B00,X; SEC RTS.
; Reached by BRL from Sub_D4F7 (pass 0, $68 path).
; ============================================================
org $C0D608
Sub_D608:
    JSR Sub_CB3A
    BCS .d608_proceed
    RTS
.d608_proceed:
    CMP $0F01,X             ; same frame already loaded?
    BNE .d608_new_frame
.d608_cle_rts:
    CLC
    RTS
.d608_new_frame:
    STA $EE
    JSR Sub_E9AA            ; triple-slot alloc
    BCC .d608_cle_rts
    LDA $EE
    STA $0F01,X
    REP #$20
    LDX $6D
    LDA $0D80,X
    STA $D0
    SEP #$20
    LDA $0F01,X             ; frame number
    STA $4202               ; WRMPYA
    LDA #$78
    STA $4203               ; WRMPYB
    LDA $1300,X
    STA $D5
    REP #$20
    LDA $4216               ; RDMPYL
    CLC
    ADC $1380,X
    STA $D3
    SEP #$30
    LDA #$01
    STA $2183               ; WMADDH
    REP #$30
    LDA $D0
    STA $2181               ; WMADDL
    ; 16-tile loop (single pass): Y=0..15 → WRAM base
    LDA #$0010
    STA $C9
    LDY #$0000
    BRA .d608_loop_entry
.d608_loop_top:
    LDA $D0
    CLC
    ADC #$0020
    STA $D0
.d608_loop_entry:
    LDA [$D3],Y
    BIT #$4000
    BNE .d608_e534
    JSR Sub_E687
    INY
    INY
    DEC $C9
    BNE .d608_loop_top
    BRA .d608_done
.d608_e534:
    JSR Sub_E534
    INY
    INY
    DEC $C9
    BNE .d608_loop_top
.d608_done:
    SEP #$30
    LDX $6D
    INC $1B00,X
    SEC
    RTS

; ============================================================
; $C0:D68B — Sub_D68B (173 bytes, $D68B–$D737)
; Triple-slot pass-1, non-$68 variant.
; Entry from BRL in Sub_D4F7 when $1B00,X&$7F == 1 and $0D00,X != $68.
; Copies 8 frame tiles at Y=$20–$2F to WRAM at VRAM base+$0100,
; then 8 tiles at Y=$30–$3F to VRAM base+$0300. INC $1B00,X; SEC RTS.
; ============================================================
org $C0D68B
Sub_D68B:
    REP #$20
    LDX $6D
    LDA $0D80,X
    CLC
    ADC #$0100
    STA $D0
    SEP #$20
    LDA $0F01,X
    STA $4202               ; WRMPYA
    LDA #$78
    STA $4203               ; WRMPYB = 120
    LDA $1300,X
    STA $D5
    REP #$20
    LDA $4216               ; RDMPYL (= frame# × 120)
    CLC
    ADC $1380,X
    STA $D3
    SEP #$30
    LDA #$01
    STA $2183               ; WMADDH
    REP #$30
    LDA $D0
    STA $2181               ; WMADDL
    LDA #$0008
    STA $C9
    LDY #$0020
    BRA .d68b_check
.d68b_next:
    LDA $D0
    CLC
    ADC #$0020
    STA $D0
.d68b_check:
    LDA [$D3],Y
    BIT #$4000
    BNE .d68b_fd
    JSR Sub_E687
    INY
    INY
    DEC $C9
    BNE .d68b_next
    BRA .d68b_loop2
.d68b_fd:
    JSR Sub_E534
    INY
    INY
    DEC $C9
    BNE .d68b_next
.d68b_loop2:
    REP #$20
    LDX $6D
    LDA $0D80,X
    CLC
    ADC #$0300
    STA $D0
    STA $2181               ; WMADDL
    REP #$10
    LDA #$0008
    STA $C9
    LDY #$0030
    BRA .d68b_check2
.d68b_next2:
    LDA $D0
    CLC
    ADC #$0020
    STA $D0
.d68b_check2:
    LDA [$D3],Y
    BIT #$4000
    BNE .d68b_fd2
    JSR Sub_E687
    INY
    INY
    DEC $C9
    BNE .d68b_next2
    BRA .d68b_done
.d68b_fd2:
    JSR Sub_E534
    INY
    INY
    DEC $C9
    BNE .d68b_next2
.d68b_done:
    SEP #$30
    LDX $6D
    INC $1B00,X
    SEC
    RTS

; ============================================================
; $C0:D738 — Sub_D738 (173 bytes, $D738–$D7E4)
; Triple-slot pass-1, $68 variant.
; Entry from BRL in Sub_D4F7 when $1B00,X&$7F == 1 and $0D00,X == $68.
; Copies 8 frame tiles at Y=$20–$2F to WRAM at VRAM base+$0200,
; then 8 tiles at Y=$30–$3F to VRAM base+$0400. INC $1B00,X; SEC RTS.
; ============================================================
org $C0D738
Sub_D738:
    REP #$20
    LDX $6D
    LDA $0D80,X
    CLC
    ADC #$0200
    STA $D0
    SEP #$20
    LDA $0F01,X
    STA $4202               ; WRMPYA
    LDA #$78
    STA $4203               ; WRMPYB = 120
    LDA $1300,X
    STA $D5
    REP #$20
    LDA $4216               ; RDMPYL (= frame# × 120)
    CLC
    ADC $1380,X
    STA $D3
    SEP #$30
    LDA #$01
    STA $2183               ; WMADDH
    REP #$30
    LDA $D0
    STA $2181               ; WMADDL
    LDA #$0008
    STA $C9
    LDY #$0020
    BRA .d738_check
.d738_next:
    LDA $D0
    CLC
    ADC #$0020
    STA $D0
.d738_check:
    LDA [$D3],Y
    BIT #$4000
    BNE .d738_fd
    JSR Sub_E687
    INY
    INY
    DEC $C9
    BNE .d738_next
    BRA .d738_loop2
.d738_fd:
    JSR Sub_E534
    INY
    INY
    DEC $C9
    BNE .d738_next
.d738_loop2:
    REP #$20
    LDX $6D
    LDA $0D80,X
    CLC
    ADC #$0400
    STA $D0
    STA $2181               ; WMADDL
    REP #$10
    LDA #$0008
    STA $C9
    LDY #$0030
    BRA .d738_check2
.d738_next2:
    LDA $D0
    CLC
    ADC #$0020
    STA $D0
.d738_check2:
    LDA [$D3],Y
    BIT #$4000
    BNE .d738_fd2
    JSR Sub_E687
    INY
    INY
    DEC $C9
    BNE .d738_next2
    BRA .d738_done
.d738_fd2:
    JSR Sub_E534
    INY
    INY
    DEC $C9
    BNE .d738_next2
.d738_done:
    SEP #$30
    LDX $6D
    INC $1B00,X
    SEC
    RTS

; ============================================================
; $C0:D7E5 — Sub_D7E5 (644 bytes, $D7E5–$DA68)
; Triple-slot pass-2+, non-$68 variant.
; Entry from BRL in Sub_D4F7 when $1B00,X&$7F >= 2 and $0D00,X != $68.
; Copies 16 frame tiles at Y=$40–$5F to WRAM at VRAM base+$0400, then
; stages 12-entry OAM descriptors (three 4-tile rows). CLC RTS.
; ============================================================
org $C0D7E5
Sub_D7E5:
    REP #$20
    LDA $0D80,X
    CLC
    ADC #$0400
    STA $D0
    SEP #$20
    LDA $0F01,X
    STA $4202               ; WRMPYA
    LDA #$78
    STA $4203               ; WRMPYB = 120
    LDA $1300,X
    STA $D5
    REP #$20
    LDA $4216               ; RDMPYL (= frame# × 120)
    CLC
    ADC $1380,X
    STA $D3
    SEP #$20
    LDA #$01
    STA $2183               ; WMADDH
    REP #$30
    LDA $D0
    STA $2181               ; WMADDL
    LDA #$0010              ; 16 tiles
    STA $C9
    LDY #$0040
    BRA .d7e5_check
.d7e5_next:
    LDA $D0
    CLC
    ADC #$0020
    STA $D0
.d7e5_check:
    LDA [$D3],Y
    BIT #$4000
    BNE .d7e5_fd
    JSR Sub_E687
    INY
    INY
    DEC $C9
    BNE .d7e5_next
    BRA .d7e5_oam
.d7e5_fd:
    JSR Sub_E534
    INY
    INY
    DEC $C9
    BNE .d7e5_next
.d7e5_oam:
    ; --- OAM slot descriptor setup ---
    SEP #$10                ; X/Y = 8-bit; A stays 16-bit
    LDX $6D
    LDA $0D00,X
    AND #$01FF
    ASL
    ASL
    ASL
    ASL
    LDX $79
    STA $0950,X
    CLC
    ADC #$0300
    STA $0970,X
    LDX $6D
    LDA $0D80,X
    LDX $79
    STA $0940,X
    CLC
    ADC #$0500
    STA $0960,X
    LDA #$0500
    STA $0980,X
    LDA #$0100
    STA $0990,X
    INC $09A0,X
    INX
    INX
    STZ $09A0,X
    STX $79
    LDX $6D
    LDA $1700,X
    REP #$10                ; X/Y = 16-bit
    TAX
    SEP #$20                ; A = 8-bit
    LDY #$0060
    ; --- 12 OAM Y/tile entries ---
    ; entry 0
    LDA [$D3],Y
    STA $7F4802,X
    BPL .d7e5_y0p
    LDA #$FF
    BRA .d7e5_y0h
.d7e5_y0p:
    LDA #$00
.d7e5_y0h:
    STA $7F4803,X
    INY
    LDA [$D3],Y
    STA $7F4804,X
    ; entry 1
    INY
    LDA [$D3],Y
    STA $7F480A,X
    BPL .d7e5_y1p
    LDA #$FF
    BRA .d7e5_y1h
.d7e5_y1p:
    LDA #$00
.d7e5_y1h:
    STA $7F480B,X
    INY
    LDA [$D3],Y
    STA $7F480C,X
    ; entry 2
    INY
    LDA [$D3],Y
    STA $7F4812,X
    BPL .d7e5_y2p
    LDA #$FF
    BRA .d7e5_y2h
.d7e5_y2p:
    LDA #$00
.d7e5_y2h:
    STA $7F4813,X
    INY
    LDA [$D3],Y
    STA $7F4814,X
    ; entry 3
    INY
    LDA [$D3],Y
    STA $7F481A,X
    BPL .d7e5_y3p
    LDA #$FF
    BRA .d7e5_y3h
.d7e5_y3p:
    LDA #$00
.d7e5_y3h:
    STA $7F481B,X
    INY
    LDA [$D3],Y
    STA $7F481C,X
    ; entry 4
    INY
    LDA [$D3],Y
    STA $7F4822,X
    BPL .d7e5_y4p
    LDA #$FF
    BRA .d7e5_y4h
.d7e5_y4p:
    LDA #$00
.d7e5_y4h:
    STA $7F4823,X
    INY
    LDA [$D3],Y
    STA $7F4824,X
    ; entry 5
    INY
    LDA [$D3],Y
    STA $7F482A,X
    BPL .d7e5_y5p
    LDA #$FF
    BRA .d7e5_y5h
.d7e5_y5p:
    LDA #$00
.d7e5_y5h:
    STA $7F482B,X
    INY
    LDA [$D3],Y
    STA $7F482C,X
    ; entry 6
    INY
    LDA [$D3],Y
    STA $7F4832,X
    BPL .d7e5_y6p
    LDA #$FF
    BRA .d7e5_y6h
.d7e5_y6p:
    LDA #$00
.d7e5_y6h:
    STA $7F4833,X
    INY
    LDA [$D3],Y
    STA $7F4834,X
    ; entry 7
    INY
    LDA [$D3],Y
    STA $7F483A,X
    BPL .d7e5_y7p
    LDA #$FF
    BRA .d7e5_y7h
.d7e5_y7p:
    LDA #$00
.d7e5_y7h:
    STA $7F483B,X
    INY
    LDA [$D3],Y
    STA $7F483C,X
    ; entry 8
    INY
    LDA [$D3],Y
    STA $7F4842,X
    BPL .d7e5_y8p
    LDA #$FF
    BRA .d7e5_y8h
.d7e5_y8p:
    LDA #$00
.d7e5_y8h:
    STA $7F4843,X
    INY
    LDA [$D3],Y
    STA $7F4844,X
    ; entry 9
    INY
    LDA [$D3],Y
    STA $7F484A,X
    BPL .d7e5_y9p
    LDA #$FF
    BRA .d7e5_y9h
.d7e5_y9p:
    LDA #$00
.d7e5_y9h:
    STA $7F484B,X
    INY
    LDA [$D3],Y
    STA $7F484C,X
    ; entry 10
    INY
    LDA [$D3],Y
    STA $7F4852,X
    BPL .d7e5_y10p
    LDA #$FF
    BRA .d7e5_y10h
.d7e5_y10p:
    LDA #$00
.d7e5_y10h:
    STA $7F4853,X
    INY
    LDA [$D3],Y
    STA $7F4854,X
    ; entry 11
    INY
    LDA [$D3],Y
    STA $7F485A,X
    BPL .d7e5_y11p
    LDA #$FF
    BRA .d7e5_y11h
.d7e5_y11p:
    LDA #$00
.d7e5_y11h:
    STA $7F485B,X
    INY
    LDA [$D3],Y
    STA $7F485C,X
    ; --- X-positions (8 sequential, gap at slot boundary, 4 more) ---
    LDY $6D
    LDA $0D00,Y
    STA $7F4806,X
    INC
    INC
    STA $7F480E,X
    INC
    INC
    STA $7F4816,X
    INC
    INC
    STA $7F481E,X
    INC
    INC
    STA $7F4826,X
    INC
    INC
    STA $7F482E,X
    INC
    INC
    STA $7F4836,X
    INC
    INC
    STA $7F483E,X
    INC
    INC
    CLC
    ADC #$10
    STA $7F4846,X
    INC
    INC
    STA $7F484E,X
    INC
    INC
    STA $7F4856,X
    INC
    INC
    STA $7F485E,X
    ; --- attribute bytes ---
    LDA $0F81,Y
    ORA $0D01,Y
    STA $D9
    ORA $0C00,Y
    STA $7F4807,X
    STA $7F480F,X
    STA $7F4817,X
    STA $7F481F,X
    LDA $D9
    ORA $0C01,Y
    STA $7F4827,X
    STA $7F482F,X
    STA $7F4837,X
    STA $7F483F,X
    LDA $D9
    ORA $0C01,Y
    STA $7F4847,X
    STA $7F484F,X
    STA $7F4857,X
    STA $7F485F,X
    LDX $6D
    INC $1B00,X
    SEP #$10
    CLC
    RTS

; ============================================================
; $C0:DA69 — Sub_DA69 (703 bytes, $DA69–$DD27)
; Triple-slot pass-2+, $68 variant.
; Entry from BRL in Sub_D4F7 when $1B00,X&$7F >= 2 and $0D00,X == $68.
; Two 8-tile loops: Y=$40 → VRAM base+$0300, Y=$50 → base+$0500;
; then 12-entry OAM staging for two 8-tile slots. CLC RTS.
; ============================================================
org $C0DA69
Sub_DA69:
    REP #$20
    LDA $0D80,X
    CLC
    ADC #$0300
    STA $D0
    SEP #$20
    LDA $0F01,X
    STA $4202               ; WRMPYA
    LDA #$78
    STA $4203               ; WRMPYB = 120
    LDA $1300,X
    STA $D5
    REP #$20
    LDA $4216               ; RDMPYL (= frame# × 120)
    CLC
    ADC $1380,X
    STA $D3
    SEP #$20
    LDA #$01
    STA $2183               ; WMADDH
    REP #$30
    LDA $D0
    STA $2181               ; WMADDL
    LDA #$0008              ; 8 tiles
    STA $C9
    LDY #$0040
    BRA .da69_check
.da69_next:
    LDA $D0
    CLC
    ADC #$0020
    STA $D0
.da69_check:
    LDA [$D3],Y
    BIT #$4000
    BNE .da69_fd
    JSR Sub_E687
    INY
    INY
    DEC $C9
    BNE .da69_next
    BRA .da69_loop2
.da69_fd:
    JSR Sub_E534
    INY
    INY
    DEC $C9
    BNE .da69_next
.da69_loop2:
    LDX $6D
    LDA $0D80,X
    CLC
    ADC #$0500
    STA $D0
    STA $2181               ; WMADDL
    LDA #$0008              ; 8 tiles
    STA $C9
    LDY #$0050
    BRA .da69_check2
.da69_next2:
    LDA $D0
    CLC
    ADC #$0020
    STA $D0
.da69_check2:
    LDA [$D3],Y
    BIT #$4000
    BNE .da69_fd2
    JSR Sub_E687
    INY
    INY
    DEC $C9
    BNE .da69_next2
    BRA .da69_oam
.da69_fd2:
    JSR Sub_E534
    INY
    INY
    DEC $C9
    BNE .da69_next2
.da69_oam:
    ; --- OAM slot descriptor setup ---
    SEP #$10                ; X/Y = 8-bit; A stays 16-bit
    LDX $6D
    LDA $0D00,X
    AND #$01FF
    ASL
    ASL
    ASL
    ASL
    LDX $79
    STA $0950,X
    CLC
    ADC #$0100
    STA $0970,X
    LDX $6D
    LDA $0D80,X
    LDX $79
    STA $0940,X
    CLC
    ADC #$0100
    STA $0960,X
    LDA #$0100
    STA $0980,X
    LDA #$0500
    STA $0990,X
    INC $09A0,X
    INX
    INX
    STZ $09A0,X
    STX $79
    LDX $6D
    LDA $1700,X
    REP #$10                ; X/Y = 16-bit
    TAX
    SEP #$20                ; A = 8-bit
    LDY #$0060
    ; --- 12 OAM Y/tile entries ---
    ; entry 0
    LDA [$D3],Y
    STA $7F4802,X
    BPL .da69_y0p
    LDA #$FF
    BRA .da69_y0h
.da69_y0p:
    LDA #$00
.da69_y0h:
    STA $7F4803,X
    INY
    LDA [$D3],Y
    STA $7F4804,X
    ; entry 1
    INY
    LDA [$D3],Y
    STA $7F480A,X
    BPL .da69_y1p
    LDA #$FF
    BRA .da69_y1h
.da69_y1p:
    LDA #$00
.da69_y1h:
    STA $7F480B,X
    INY
    LDA [$D3],Y
    STA $7F480C,X
    ; entry 2
    INY
    LDA [$D3],Y
    STA $7F4812,X
    BPL .da69_y2p
    LDA #$FF
    BRA .da69_y2h
.da69_y2p:
    LDA #$00
.da69_y2h:
    STA $7F4813,X
    INY
    LDA [$D3],Y
    STA $7F4814,X
    ; entry 3
    INY
    LDA [$D3],Y
    STA $7F481A,X
    BPL .da69_y3p
    LDA #$FF
    BRA .da69_y3h
.da69_y3p:
    LDA #$00
.da69_y3h:
    STA $7F481B,X
    INY
    LDA [$D3],Y
    STA $7F481C,X
    ; entry 4
    INY
    LDA [$D3],Y
    STA $7F4822,X
    BPL .da69_y4p
    LDA #$FF
    BRA .da69_y4h
.da69_y4p:
    LDA #$00
.da69_y4h:
    STA $7F4823,X
    INY
    LDA [$D3],Y
    STA $7F4824,X
    ; entry 5
    INY
    LDA [$D3],Y
    STA $7F482A,X
    BPL .da69_y5p
    LDA #$FF
    BRA .da69_y5h
.da69_y5p:
    LDA #$00
.da69_y5h:
    STA $7F482B,X
    INY
    LDA [$D3],Y
    STA $7F482C,X
    ; entry 6
    INY
    LDA [$D3],Y
    STA $7F4832,X
    BPL .da69_y6p
    LDA #$FF
    BRA .da69_y6h
.da69_y6p:
    LDA #$00
.da69_y6h:
    STA $7F4833,X
    INY
    LDA [$D3],Y
    STA $7F4834,X
    ; entry 7
    INY
    LDA [$D3],Y
    STA $7F483A,X
    BPL .da69_y7p
    LDA #$FF
    BRA .da69_y7h
.da69_y7p:
    LDA #$00
.da69_y7h:
    STA $7F483B,X
    INY
    LDA [$D3],Y
    STA $7F483C,X
    ; entry 8
    INY
    LDA [$D3],Y
    STA $7F4842,X
    BPL .da69_y8p
    LDA #$FF
    BRA .da69_y8h
.da69_y8p:
    LDA #$00
.da69_y8h:
    STA $7F4843,X
    INY
    LDA [$D3],Y
    STA $7F4844,X
    ; entry 9
    INY
    LDA [$D3],Y
    STA $7F484A,X
    BPL .da69_y9p
    LDA #$FF
    BRA .da69_y9h
.da69_y9p:
    LDA #$00
.da69_y9h:
    STA $7F484B,X
    INY
    LDA [$D3],Y
    STA $7F484C,X
    ; entry 10
    INY
    LDA [$D3],Y
    STA $7F4852,X
    BPL .da69_y10p
    LDA #$FF
    BRA .da69_y10h
.da69_y10p:
    LDA #$00
.da69_y10h:
    STA $7F4853,X
    INY
    LDA [$D3],Y
    STA $7F4854,X
    ; entry 11
    INY
    LDA [$D3],Y
    STA $7F485A,X
    BPL .da69_y11p
    LDA #$FF
    BRA .da69_y11h
.da69_y11p:
    LDA #$00
.da69_y11h:
    STA $7F485B,X
    INY
    LDA [$D3],Y
    STA $7F485C,X
    ; --- X-positions (4 sequential, gap at slot boundary, 8 more) ---
    LDY $6D
    LDA $0D00,Y
    STA $7F4806,X
    INC
    INC
    STA $7F480E,X
    INC
    INC
    STA $7F4816,X
    INC
    INC
    STA $7F481E,X
    INC
    INC
    CLC
    ADC #$10
    STA $7F4826,X
    INC
    INC
    STA $7F482E,X
    INC
    INC
    STA $7F4836,X
    INC
    INC
    STA $7F483E,X
    INC
    INC
    STA $7F4846,X
    INC
    INC
    STA $7F484E,X
    INC
    INC
    STA $7F4856,X
    INC
    INC
    STA $7F485E,X
    ; --- attribute bytes ---
    LDA $0F81,Y
    ORA $0D01,Y
    STA $D9
    ORA $0C00,Y
    STA $7F4807,X
    STA $7F480F,X
    STA $7F4817,X
    STA $7F481F,X
    LDA $D9
    ORA $0C01,Y
    STA $7F4827,X
    STA $7F482F,X
    STA $7F4837,X
    STA $7F483F,X
    LDA $D9
    ORA $0C01,Y
    STA $7F4847,X
    STA $7F484F,X
    STA $7F4857,X
    STA $7F485F,X
    LDX $6D
    INC $1B00,X
    SEP #$10
    CLC
    RTS

; ============================================================
; $C0:DD28 — Sub_DD28 (1026 bytes, $DD28–$E129)
; 12-slot OAM buffer init, pass-1 path (sprite type 2).
; Called via BRL from Sub_CB0A when bits 0-1 of $1201,X == 2.
; Two sub-paths selected by $0D00,X:
;   $0D00,X == $68 → BRL to alt path at $DF2F
;   otherwise      → main path at $DD34
; Both paths: multiply frame# × $78 for animation data offset;
; read 12 tile-entry pairs (Y starts at $60) into $7F4Bxx/$7F4Cxx
; OAM staging (groups at stride $08: C2–1C).
; X-positions differ between paths:
;   main: 8-slot block (C6–FE), gap +$10, 4-slot block (C06–C1E)
;   alt:  4-slot block (C6–DE), gap +$10, 8-slot block (E6–C1E)
; Attribute bytes: $0C00 → C7-DF; $0C01 → E7-FF and C07-C1F.
; On completion: $1B00,X = $80, SEP #$10, CLC, RTS.
; Entry: M=1, X/Y=16-bit; X = entity slot.
; ============================================================
org $C0DD28
Sub_DD28:
    LDA $0D00,X              ; sprite type/layout flag
    CMP #$68
    BEQ .dd28_alt_branch     ; == $68: use alt path
    BRA .dd28_main           ; else: main path
.dd28_alt_branch:
    BRL .dd28_alt                ; tail-call alt path at $DF2F
    ; ---- main path ----
.dd28_main:
    LDA $0F01,X              ; animation frame number
    STA $4202                ; WRMPYA
    LDA #$78                 ; multiply by $78 = 120
    STA $4203                ; WRMPYB → triggers multiply
    LDA $1300,X              ; animation data bank byte
    STA $D5
    REP #$20                 ; A 16-bit
    LDA $4216                ; RDMPYL: frame# × $78
    CLC
    ADC $1380,X              ; add sprite base offset
    STA $D3                  ; dp:$D3 = animation data ptr
    LDA $1700,X              ; OAM buffer index from ROM table ($C01700,X)
    REP #$10                 ; X/Y 16-bit
    TAX                      ; X = OAM buffer index
    SEP #$20                 ; A 8-bit
    LDY #$0060               ; animation data start offset
    ; --- 12 OAM tile-entry groups (stride $08) ---
    ; entry 0: OAM C2/C3/C4
    LDA [$D3],Y
    STA $7F4BC2,X
    BPL .dd28_y0p
    LDA #$FF
    BRA .dd28_y0h
.dd28_y0p:
    LDA #$00
.dd28_y0h:
    STA $7F4BC3,X
    INY
    LDA [$D3],Y
    STA $7F4BC4,X
    ; entry 1: OAM CA/CB/CC
    INY
    LDA [$D3],Y
    STA $7F4BCA,X
    BPL .dd28_y1p
    LDA #$FF
    BRA .dd28_y1h
.dd28_y1p:
    LDA #$00
.dd28_y1h:
    STA $7F4BCB,X
    INY
    LDA [$D3],Y
    STA $7F4BCC,X
    ; entry 2: OAM D2/D3/D4
    INY
    LDA [$D3],Y
    STA $7F4BD2,X
    BPL .dd28_y2p
    LDA #$FF
    BRA .dd28_y2h
.dd28_y2p:
    LDA #$00
.dd28_y2h:
    STA $7F4BD3,X
    INY
    LDA [$D3],Y
    STA $7F4BD4,X
    ; entry 3: OAM DA/DB/DC
    INY
    LDA [$D3],Y
    STA $7F4BDA,X
    BPL .dd28_y3p
    LDA #$FF
    BRA .dd28_y3h
.dd28_y3p:
    LDA #$00
.dd28_y3h:
    STA $7F4BDB,X
    INY
    LDA [$D3],Y
    STA $7F4BDC,X
    ; entry 4: OAM E2/E3/E4
    INY
    LDA [$D3],Y
    STA $7F4BE2,X
    BPL .dd28_y4p
    LDA #$FF
    BRA .dd28_y4h
.dd28_y4p:
    LDA #$00
.dd28_y4h:
    STA $7F4BE3,X
    INY
    LDA [$D3],Y
    STA $7F4BE4,X
    ; entry 5: OAM EA/EB/EC
    INY
    LDA [$D3],Y
    STA $7F4BEA,X
    BPL .dd28_y5p
    LDA #$FF
    BRA .dd28_y5h
.dd28_y5p:
    LDA #$00
.dd28_y5h:
    STA $7F4BEB,X
    INY
    LDA [$D3],Y
    STA $7F4BEC,X
    ; entry 6: OAM F2/F3/F4
    INY
    LDA [$D3],Y
    STA $7F4BF2,X
    BPL .dd28_y6p
    LDA #$FF
    BRA .dd28_y6h
.dd28_y6p:
    LDA #$00
.dd28_y6h:
    STA $7F4BF3,X
    INY
    LDA [$D3],Y
    STA $7F4BF4,X
    ; entry 7: OAM FA/FB/FC
    INY
    LDA [$D3],Y
    STA $7F4BFA,X
    BPL .dd28_y7p
    LDA #$FF
    BRA .dd28_y7h
.dd28_y7p:
    LDA #$00
.dd28_y7h:
    STA $7F4BFB,X
    INY
    LDA [$D3],Y
    STA $7F4BFC,X
    ; entry 8: OAM $4C02/03/04
    INY
    LDA [$D3],Y
    STA $7F4C02,X
    BPL .dd28_y8p
    LDA #$FF
    BRA .dd28_y8h
.dd28_y8p:
    LDA #$00
.dd28_y8h:
    STA $7F4C03,X
    INY
    LDA [$D3],Y
    STA $7F4C04,X
    ; entry 9: OAM $4C0A/0B/0C
    INY
    LDA [$D3],Y
    STA $7F4C0A,X
    BPL .dd28_y9p
    LDA #$FF
    BRA .dd28_y9h
.dd28_y9p:
    LDA #$00
.dd28_y9h:
    STA $7F4C0B,X
    INY
    LDA [$D3],Y
    STA $7F4C0C,X
    ; entry 10: OAM $4C12/13/14
    INY
    LDA [$D3],Y
    STA $7F4C12,X
    BPL .dd28_y10p
    LDA #$FF
    BRA .dd28_y10h
.dd28_y10p:
    LDA #$00
.dd28_y10h:
    STA $7F4C13,X
    INY
    LDA [$D3],Y
    STA $7F4C14,X
    ; entry 11: OAM $4C1A/1B/1C
    INY
    LDA [$D3],Y
    STA $7F4C1A,X
    BPL .dd28_y11p
    LDA #$FF
    BRA .dd28_y11h
.dd28_y11p:
    LDA #$00
.dd28_y11h:
    STA $7F4C1B,X
    INY
    LDA [$D3],Y
    STA $7F4C1C,X
    ; --- X-positions: 8-slot block, gap +$10, 4-slot block ---
    LDY $6D
    LDA $0D00,Y              ; base X coordinate
    STA $7F4BC6,X
    INC
    INC
    STA $7F4BCE,X
    INC
    INC
    STA $7F4BD6,X
    INC
    INC
    STA $7F4BDE,X
    INC
    INC
    STA $7F4BE6,X
    INC
    INC
    STA $7F4BEE,X
    INC
    INC
    STA $7F4BF6,X
    INC
    INC
    STA $7F4BFE,X
    INC
    INC
    CLC
    ADC #$10                 ; gap: skip $10 pixels
    STA $7F4C06,X
    INC
    INC
    STA $7F4C0E,X
    INC
    INC
    STA $7F4C16,X
    INC
    INC
    STA $7F4C1E,X
    ; --- attribute bytes ---
    LDA $0F81,Y
    ORA $0D01,Y
    STA $D9
    ORA $0C00,Y
    STA $7F4BC7,X
    STA $7F4BCF,X
    STA $7F4BD7,X
    STA $7F4BDF,X
    LDA $D9
    ORA $0C01,Y
    STA $7F4BE7,X
    STA $7F4BEF,X
    STA $7F4BF7,X
    STA $7F4BFF,X
    LDA $D9
    ORA $0C01,Y
    STA $7F4C07,X
    STA $7F4C0F,X
    STA $7F4C17,X
    STA $7F4C1F,X
    LDX $6D
    LDA #$80
    STA.w $1B00,X
    SEP #$10
    CLC
    RTS
    ; ---- alt path ($DF2F): for $0D00,X == $68 ----
.dd28_alt:
    LDA $0F01,X              ; animation frame number
    STA $4202                ; WRMPYA
    LDA #$78                 ; multiply by $78 = 120
    STA $4203                ; WRMPYB
    LDA $1300,X              ; animation data bank byte
    STA $D5
    REP #$20                 ; A 16-bit
    LDA $4216                ; RDMPYL: frame# × $78
    CLC
    ADC $1380,X
    STA $D3
    LDA $1700,X              ; OAM buffer index from ROM table
    REP #$10                 ; X/Y 16-bit
    TAX
    SEP #$20                 ; A 8-bit
    LDY #$0060               ; animation data start offset
    ; --- 12 OAM tile-entry groups (stride $08, same as main path) ---
    ; entry 0: OAM C2/C3/C4
    LDA [$D3],Y
    STA $7F4BC2,X
    BPL .dd28a_y0p
    LDA #$FF
    BRA .dd28a_y0h
.dd28a_y0p:
    LDA #$00
.dd28a_y0h:
    STA $7F4BC3,X
    INY
    LDA [$D3],Y
    STA $7F4BC4,X
    ; entry 1: OAM CA/CB/CC
    INY
    LDA [$D3],Y
    STA $7F4BCA,X
    BPL .dd28a_y1p
    LDA #$FF
    BRA .dd28a_y1h
.dd28a_y1p:
    LDA #$00
.dd28a_y1h:
    STA $7F4BCB,X
    INY
    LDA [$D3],Y
    STA $7F4BCC,X
    ; entry 2: OAM D2/D3/D4
    INY
    LDA [$D3],Y
    STA $7F4BD2,X
    BPL .dd28a_y2p
    LDA #$FF
    BRA .dd28a_y2h
.dd28a_y2p:
    LDA #$00
.dd28a_y2h:
    STA $7F4BD3,X
    INY
    LDA [$D3],Y
    STA $7F4BD4,X
    ; entry 3: OAM DA/DB/DC
    INY
    LDA [$D3],Y
    STA $7F4BDA,X
    BPL .dd28a_y3p
    LDA #$FF
    BRA .dd28a_y3h
.dd28a_y3p:
    LDA #$00
.dd28a_y3h:
    STA $7F4BDB,X
    INY
    LDA [$D3],Y
    STA $7F4BDC,X
    ; entry 4: OAM E2/E3/E4
    INY
    LDA [$D3],Y
    STA $7F4BE2,X
    BPL .dd28a_y4p
    LDA #$FF
    BRA .dd28a_y4h
.dd28a_y4p:
    LDA #$00
.dd28a_y4h:
    STA $7F4BE3,X
    INY
    LDA [$D3],Y
    STA $7F4BE4,X
    ; entry 5: OAM EA/EB/EC
    INY
    LDA [$D3],Y
    STA $7F4BEA,X
    BPL .dd28a_y5p
    LDA #$FF
    BRA .dd28a_y5h
.dd28a_y5p:
    LDA #$00
.dd28a_y5h:
    STA $7F4BEB,X
    INY
    LDA [$D3],Y
    STA $7F4BEC,X
    ; entry 6: OAM F2/F3/F4
    INY
    LDA [$D3],Y
    STA $7F4BF2,X
    BPL .dd28a_y6p
    LDA #$FF
    BRA .dd28a_y6h
.dd28a_y6p:
    LDA #$00
.dd28a_y6h:
    STA $7F4BF3,X
    INY
    LDA [$D3],Y
    STA $7F4BF4,X
    ; entry 7: OAM FA/FB/FC
    INY
    LDA [$D3],Y
    STA $7F4BFA,X
    BPL .dd28a_y7p
    LDA #$FF
    BRA .dd28a_y7h
.dd28a_y7p:
    LDA #$00
.dd28a_y7h:
    STA $7F4BFB,X
    INY
    LDA [$D3],Y
    STA $7F4BFC,X
    ; entry 8: OAM $4C02/03/04
    INY
    LDA [$D3],Y
    STA $7F4C02,X
    BPL .dd28a_y8p
    LDA #$FF
    BRA .dd28a_y8h
.dd28a_y8p:
    LDA #$00
.dd28a_y8h:
    STA $7F4C03,X
    INY
    LDA [$D3],Y
    STA $7F4C04,X
    ; entry 9: OAM $4C0A/0B/0C
    INY
    LDA [$D3],Y
    STA $7F4C0A,X
    BPL .dd28a_y9p
    LDA #$FF
    BRA .dd28a_y9h
.dd28a_y9p:
    LDA #$00
.dd28a_y9h:
    STA $7F4C0B,X
    INY
    LDA [$D3],Y
    STA $7F4C0C,X
    ; entry 10: OAM $4C12/13/14
    INY
    LDA [$D3],Y
    STA $7F4C12,X
    BPL .dd28a_y10p
    LDA #$FF
    BRA .dd28a_y10h
.dd28a_y10p:
    LDA #$00
.dd28a_y10h:
    STA $7F4C13,X
    INY
    LDA [$D3],Y
    STA $7F4C14,X
    ; entry 11: OAM $4C1A/1B/1C
    INY
    LDA [$D3],Y
    STA $7F4C1A,X
    BPL .dd28a_y11p
    LDA #$FF
    BRA .dd28a_y11h
.dd28a_y11p:
    LDA #$00
.dd28a_y11h:
    STA $7F4C1B,X
    INY
    LDA [$D3],Y
    STA $7F4C1C,X
    ; --- X-positions: 4-slot block, gap +$10, 8-slot block ---
    LDY $6D
    LDA $0D00,Y              ; base X coordinate
    STA $7F4BC6,X
    INC
    INC
    STA $7F4BCE,X
    INC
    INC
    STA $7F4BD6,X
    INC
    INC
    STA $7F4BDE,X
    INC
    INC
    CLC
    ADC #$10                 ; gap: skip $10 pixels after 4th slot
    STA $7F4BE6,X
    INC
    INC
    STA $7F4BEE,X
    INC
    INC
    STA $7F4BF6,X
    INC
    INC
    STA $7F4BFE,X
    INC
    INC
    STA $7F4C06,X
    INC
    INC
    STA $7F4C0E,X
    INC
    INC
    STA $7F4C16,X
    INC
    INC
    STA $7F4C1E,X
    ; --- attribute bytes ---
    LDA $0F81,Y
    ORA $0D01,Y
    STA $D9
    ORA $0C00,Y
    STA $7F4BC7,X
    STA $7F4BCF,X
    STA $7F4BD7,X
    STA $7F4BDF,X
    LDA $D9
    ORA $0C01,Y
    STA $7F4BE7,X
    STA $7F4BEF,X
    STA $7F4BF7,X
    STA $7F4BFF,X
    LDA $D9
    ORA $0C01,Y
    STA $7F4C07,X
    STA $7F4C0F,X
    STA $7F4C17,X
    STA $7F4C1F,X
    LDX $6D
    LDA #$80
    STA.w $1B00,X
    SEP #$10
    CLC
    RTS
