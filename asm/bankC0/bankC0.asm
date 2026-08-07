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
; Label stubs — no bytes emitted; used for JSR/JSL/BRL targets
; ============================================================

; BRL targets (raw hex won't compute relative — must use labels)
org $C00AFF
AltEntry2:      ; alternate cold-start entry 2

org $C01BAB
AltEntry3:      ; alternate cold-start entry 3

org $C01BE6
AltEntry4:      ; alternate cold-start entry 4

org $C02C41
AltEntry1:      ; alternate cold-start entry 1

org $C02E1E
LoadSavePath:   ; entry for mode >= $01FF (load/save/transition)

org $C0EC60
Sub_EC60:       ; called from main frame loop after VBlankHandler

; Unmatched routines called from matched code


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
    BRL $0049                   ; C6≠0: → .c73a_c6nz [$C820; offset=$C820-$C7D7=$0049]
.c73a_chk_c5:
    LDA $C5
    BMI .c73a_large_c5          ; C5≥$80: no-clamp path
    BRL $001D                   ; C5<$80: clamp path → .c73a_small_c5 [$C7FB; offset=$C7FB-$C7DE=$001D]

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
    BRL $0154               ; C6≠0 → $BC50 (raw signed offset, asar BRL quirk)

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
    BRL $01A3               ; C6≠0 → $BF1C (raw signed offset, asar BRL quirk)

    ; ── C6=0 dispatch on C5 sign ──────────────────────────────────────────────
.bcdc_c6_zero:
    LDA $C5
    BMI .bcdc_neg
    BRL $00C6               ; C5<$80 → $BE46 positive path (raw signed offset)

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
    BRL $0143               ; C6≠0 → $C209 type-3+ path (raw signed offset)

.bff2_c6_zero:
    LDA $C5
    BMI .bff2_neg
    BRL $006E               ; C5≥0 → $C13B positive path (raw signed offset)

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
    BRL $0223               ; C6≠0 → $C5C1 (raw signed offset, asar BRL quirk)

    ; ── C6=0 dispatch on C5 sign ──────────────────────────────────────────────
.c2bf_c6_zero:
    LDA $C5
    BMI .c2bf_neg
    BRL $00DE               ; C5<$80 → $C483 positive path (raw signed offset)

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
; $C0:0000 — Entry jump table (5 entries, BRA/BRL)
; Entry 0 is warm restart (skip one-time init, enter frame loop).
; Entries 1-4 are alternate cold-start targets.
; ============================================================
org $C00000

EntryTable:
    BRA GameLoop_Main       ; [0] warm restart — skip init, enter frame loop
    BRL $2C3C               ; [1] → AltEntry1  ($2C41)
    BRL $0AF7               ; [2] → AltEntry2  ($0AFF)
    BRL $1BA0               ; [3] → AltEntry3  ($1BAB)
    BRL $1BD8               ; [4] → AltEntry4  ($1BE6)

; ============================================================
; $C0:000E — GameLoop: one-time startup init (from MainInit)
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$2100, DB=$00
; ============================================================
GameLoop:
    SEP #$20                ; M=1: A → 8-bit (safety)
    REP #$10                ; X=0: X/Y → 16-bit

    ; Install RAM-resident interrupt handlers first — they live at
    ; $7E:0500/$7E:0504, which are deliberately NOT cleared below.
    JSR InstallNMI          ; NMI handler: JML $C0:EA63 at $7E:0500
    JSR InstallIRQ          ; IRQ handler: JML $C0:ECCC at $7E:0504

    REP #$20                ; A → 16-bit for TCD
    LDA #$0100
    TCD                     ; DP = $0100 (WRAM variable page)
    SEP #$20                ; A → 8-bit

    JSR InitHW              ; disable hardware (SEI, forced blank, no NMI/DMA)

    ; Clear WRAM block 1: $7E:0000-04FF (1280 bytes, stops before handlers)
    LDX #$0500
    STX $4E                 ; ($014E-$014F) = byte count
    LDX #$0000
    STX $4B                 ; ($014B-$014C) = dest addr
    LDA #$7E
    STA $4D                 ; ($014D) = dest bank
    JSR ClearRAMDMA         ; DMA fill with 0

    ; Clear WRAM block 2: $7E:0700-FFFF (59648 bytes)
    LDX #$E900
    STX $4E
    LDX #$0700
    STX $4B
    LDA #$7E
    STA $4D
    JSR ClearRAMDMA

    ; Clear WRAM block 3: $7F:5080-A0FF (20608 bytes)
    LDX #$5080
    STX $4E
    STX $4B                 ; count == dest addr (both $5080)
    LDA #$7F
    STA $4D
    JSR ClearRAMDMA

    JSL $C70000             ; engine subsystem init
    LDA #$09
    JSL $C28004

GameLoop_Main:
    JSR InitHW              ; forced blank, disable NMI/DMA
    JSR InstallNMI          ; reinstall NMI handler
    JSR InstallIRQ          ; reinstall IRQ handler

    ; Dispatch on game mode index at WRAM $0100 (16-bit)
    LDX $0100
    CPX #$01F0
    BMI GL_ModeOk1
    JML $C20000             ; mode >= $01F0 → alternate handler in bank $C2

GL_ModeOk1:
    CPX #$01FF
    BMI GL_ModeOk2
    LDX #$7C00
    BRL $2DA1               ; → LoadSavePath ($2E1E)

GL_ModeOk2:
    REP #$20
    LDA #$0100
    TCD                     ; DP = $0100
    SEP #$20

    JSR FrameStateInit      ; save/reset per-frame state variables
    JSR FrameUpdate         ; per-frame logic dispatch
    JSR $B192
    JSR $56A6
    JSR $28AA
    JSR $2848               ; input polling

GameLoop_FrameBody:
    LDA.w $00F0
    TSB $51                 ; ($0151) |= [$00F0]
    LDA.w $00F6
    TSB $50                 ; ($0150) |= [$00F6]
    JSR $18D9
    JSR $0C76
    JSR $881E
    JSR $1AAC
    JSL $C01F87
    JSR $21E1
    JSR $274D
    JSR VBlankHandler       ; sync to VBlank (tail-jumps via BRL to PostVBlank)
    JSR $EC60
    BRA GameLoop_FrameBody

; ============================================================
; $C0:00BF — VBlankHandler
; Performs per-VBlank audio + DMA tasks; tail-jumps to PostVBlank.
; Caller's return addr stays on stack so PostVBlank's RTS resumes there.
; ============================================================
VBlankHandler:
    SEP #$10                ; X/Y → 8-bit
    JSR $59D9
    JSR $5A46
    JSL $FDC2C1
    REP #$10                ; X/Y → 16-bit
    JSL $FDFFF7
    SEP #$10
    JSR $A810
    JSR $CA76
    REP #$10
    BRL $B193               ; → PostVBlank ($B271), RTS returns to caller

VBlankHandlerShort:
    SEP #$10
    JSL $FDC2C1
    REP #$10
    JSL $FDFFF7
    RTS

Sub_00EB:
    JSR $881E
    JSR VBlankHandlerShort
    BRL $EB6C               ; → Sub_EC60 ($EC60)

FrameUpdate:
    JSR $092B
    JSR $1B53
    JSR $0960
    JSR $6DCF
    JSR $7084
    JSR $7F7E
    JSR $A33B
    JSR $09DD
    JSR $0A14
    JSR $56D4
    JSL $FDFFFA
    JSL $FDFFF4
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
    LDA #$80
    STA.w INIDISP             ; $2100: forced blank on, brightness 0
    LDA #$00
    STA.w NMITIMEN            ; $4200: disable NMI, IRQ, joypad auto-read
    STA.w MDMAEN              ; $420B: disable all DMA channels
    STA.w HDMAEN              ; $420C: disable all HDMA channels
    RTS

; ============================================================
; $C0:0B64 — InstallNMI (17 bytes)
; Writes JML $C0:EA63 (5C 63 EA C0) to WRAM $7E:0500.
; Called with M=1 (8-bit A), X=0 (16-bit X).
; ============================================================
InstallNMI:
    LDA #$5C                ; JML opcode
    STA $0500
    LDX #$EA63              ; low 16-bit of $C0:EA63 (little-endian)
    STX $0501
    LDA #$C0                ; bank byte
    STA $0503
    RTS

; ============================================================
; $C0:0B75 — InstallIRQ (17 bytes)
; Writes JML $C0:ECCC (5C CC EC C0) to WRAM $7E:0504.
; ============================================================
InstallIRQ:
    LDA #$5C
    STA $0504
    LDX #$ECCC
    STX $0505
    LDA #$C0
    STA $0507
    RTS

; ============================================================
; $C0:0B86 — FrameStateInit (240 bytes)
; Called from GameLoop_Main at the start of each scene iteration.
; Saves active sprite registers, zeros per-frame state, sets defaults.
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=$0100
; ============================================================
FrameStateInit:
    ; Save current sprite registers to "previous frame" slots
    LDX $00                  ; ($0100) active sprite X
    STX $0A                  ; ($010A) = saved X
    LDX $02                  ; ($0102) active sprite Y
    STX $0C                  ; ($010C) = saved Y
    LDA $04                  ; ($0104) sprite attribute
    STA $0E                  ; ($010E) = saved attribute
    ; Zero per-frame flags and counters
    STZ $10
    STZ $11
    STZ $17
    STZ $18
    STZ $38
    STZ $0F
    ; Default sprite Y = $E0 (off-screen, below NTSC visible area)
    LDA #$E0
    STA $21
    STZ $19
    STZ $BC
    ; WRAM scene state
    LDA #$02
    STA $0BDE               ; WRAM $0BDE = 2
    ; Reset OAM write-head end pointers to full-buffer limits
    LDX #$0900
    STX $7D                 ; ($017D) range-2 end = $0900
    LDX #$0770
    STX $7F                 ; ($017F) range-3 end = $0770
    LDX #$08A0
    STX $7B                 ; ($017B) range-1 end = $08A0
    ; Palette/color defaults
    LDA #$E4
    STA $B1
    STA $B4
    STA $B7
    STA $BA
    ; Per-frame mode flags
    LDA #$01
    STA $1F
    STA $20
    LDA #$05
    STA $68
    LDA #$5F
    STA $28
    ; Zero remaining per-frame variables
    STZ $53
    STZ $26
    STZ $29
    STZ $2F
    STZ $2D
    STZ $30
    STZ $44
    STZ $45
    STZ $46
    STZ $5F
    STZ $78
    STZ $BB
    STZ $62
    LDA #$80
    STA $63
    STZ $39
    STZ $54
    ; 16-bit section: initialize pointer/address variables
    REP #$20                ; M=0: A -> 16-bit
    STZ $2B                 ; ($012B-$012C) = 0
    ; Load 4 × 16-bit seeds from ROM table at $E4:FFE0-FFE7
    LDA.l $E4FFE0
    STA $AF                 ; ($01AF-$01B0)
    LDA.l $E4FFE2
    STA $B2
    LDA.l $E4FFE4
    STA $B5
    LDA.l $E4FFE6
    STA $B8
    STZ.w $0150             ; ($0150-$0151) = 0 (abs mode)
    LDA #$0000
    STA.l $7E2000           ; WRAM $7E:2000-2001 = 0
    STZ $58                 ; ($0158-$0159) = 0
    ; Back to 8-bit A
    SEP #$20                ; M=1: A -> 8-bit
    LDA #$80
    STA $97
    STA $99
    STA $9B
    STA $8D
    STA $8E
    STA $8F
    STA $91
    STA $90
    STA $92
    STA $93
    ; Copy dynamic color vars from WRAM $7E:2980-2982
    LDA.l $7E2980
    STA $94
    LDA.l $7E2981
    STA $95
    LDA.l $7E2982
    STA $96
    LDA #$80
    STA $EB
    STA $AE
    LDA #$01
    STA $55
    LDA #$53
    STA $FC
    LDA #$65
    STA $FB
    LDA #$45
    STA $FA
    ; Zero WRAM state
    LDA #$00
    STA.l $7E2989
    LDA #$00
    STA $0BD9
    STA $0BDA
    STA $0BDB
    STA $0BE9
    ; Load scene entry value from WRAM $0400
    LDA $0400
    STA $F8
    RTS

; ============================================================
; $C0:2DF1 — ClearRAMDMA (45 bytes)
; Zeros a WRAM region via DMA channel 7, sourcing from MPYL (always 0
; since M7A=M7B=0). Caller loads $4B/$4C=dest addr, $4D=dest bank,
; $4E/$4F=byte count before calling.
; ============================================================
org $C02DF1
ClearRAMDMA:
    LDA #$00
    STA.w M7A                 ; $211B: clear Mode-7 operand A (write twice per spec)
    STA.w M7A
    STA.w M7B                 ; $211C: clear Mode-7 operand B (write twice)
    STA.w M7B                 ; -> MPYL ($2134) = 0*0 = 0 (DMA source byte)
    LDA #$80
    STA.w DMAP7               ; $4370: B->A direction, byte unit, increment A-bus
    LDA #$34                ; $2100 + $34 = $2134 = MPYL
    STA.w BBAD7               ; $4371: B-bus source = MPYL
    LDX $4B
    STX $4372               ; $4372: A-bus (WRAM) destination address
    LDA $4D
    STA.w A1B7                ; $4374: A-bus destination bank
    LDX $4E
    STX $4375               ; $4375: byte count
    LDA #$80
    STA.w MDMAEN              ; $420B: enable DMA channel 7 (auto-clears when done)
    RTS

; ============================================================
; $C0:B271 — PostVBlank (152 bytes)
; OAM buffer culling routine. Processes sprite descriptors from the frame-
; built table at $7E:0E00, calls Sub_B309 to push each sprite into the OAM
; buffer, then pads any unused slots with $E0 (Y=$E0 places sprites below
; the visible area). Updates write-head pointers in DP so the next frame
; knows where to start writing.
;
; Entered via BRL tail-call from VBlankHandler ($C0:00BF).
; On entry: M=1 (8-bit A), X=0 (16-bit X/Y).
; RTS returns to VBlankHandler's caller ($C0:00BA = JSR $EC60).
; ============================================================
org $C0B271
PostVBlank:
    LDX #$0901
    STX $89                 ; ($0189): range-A write head
    LDX #$0000
    STX $8B                 ; ($018B): range-A end (empty)
    LDX #$0907
    STX $81                 ; ($0181): range-B write head
    LDX #$0000
    STX $83                 ; ($0183): range-B end
    LDX #$091A
    STX $85                 ; ($0185): range-C write head
    LDX #$0000
    STX $87                 ; ($0187): range-C end
    LDX #$0710
    STX $DF                 ; ($01DF): OAM lo-buf start, range 3
    LDX #$0770
    STX $DB                 ; ($01DB): OAM lo-buf start, range 1
    LDA #$00
    STA.w WMADDH              ; $2183 = $00: WRAM bank 0
    STA $6E                 ; ($016E) = 0
    LDX #$08A0
    STX $DD                 ; ($01DD): OAM lo-buf start, range 2
    LDY #$007E              ; iterate sprite descriptor table (63 slots * 2)
PV_SpriteLoop:
    LDA $0E00,Y
    BMI PV_NextSprite       ; bit 7: no sprite
    STA $6D                 ; ($016D): descriptor index
    JSR Sub_B309
PV_CheckChain:
    LDX $6D
    LDA $0E81,X             ; chained sprite-B descriptor
    BMI PV_NextSprite
    STA $6D
    JSR Sub_B309
    BRA PV_CheckChain
PV_NextSprite:
    DEY
    DEY
    BPL PV_SpriteLoop
    LDX $DB
    LDA #$E0                ; Y=$E0 hides sprite below NTSC scanlines
PV_FillRange1:
    CPX $7B
    BCS PV_EndRange1
    STA.w $0001,X             ; Y byte of 4-byte OAM entry
    INX
    INX
    INX
    INX
    CPX #$08A0
    BCC PV_FillRange1
PV_EndRange1:
    LDX $DB
    STX $7B                 ; ($017B): range-1 write pointer
    LDX $DD
PV_FillRange2:
    CPX $7D
    BCS PV_EndRange2
    STA.w $0001,X
    INX
    INX
    INX
    INX
    CPX #$0900
    BCC PV_FillRange2
PV_EndRange2:
    LDX $DD
    STX $7D                 ; ($017D): range-2 write pointer
    LDX $DF
PV_FillRange3:
    CPX $7F
    BCS PV_EndRange3
    STA.w $0001,X
    INX
    INX
    INX
    INX
    CPX #$0770
    BCC PV_FillRange3
PV_EndRange3:
    LDX $DF
    STX $7F                 ; ($017F): range-3 write pointer
    RTS
