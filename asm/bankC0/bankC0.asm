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
; $C0:0C76 — Sub_0C76 (258 bytes, $0C76–$0D77)
; Per-frame state-machine controller, called after FrameStateInit.
; Dispatches scroll/scene updates, handles mode transitions.
;
; dp:$18 = pending-transition flags (bits 1=$02, 3=$08)
; dp:$17 = active-transition flags (bit 7=negative; bit 6=$40; bit 4=$10)
; dp:$19 = countdown timer
; dp:$25 = scene/mode selector
; dp:$5B = current game mode value (indexed into $7E3000)
;
; Fast path (dp:$17 == 0): just service $18 flags and RTS.
; Negative-$17 path: decrement $19 or hard-restart GameLoop ($0000).
; Positive-$17 paths:
;   bit 6 = fade-in loop (calls $881E + EC60 each VBlank)
;   bit 4 = mode handler dispatch ($E6/$EC/$EE/$FA/$FC or default)
;   other = color-transition setup, then restart scene.
; ============================================================
org $C00C76
Sub_0C76:
    ; --- Check pending scroll/fade flags in dp:$18 ---
    LDA $18
    BEQ .chk_transition      ; $18=0 → skip, check $17
    BIT #$02
    BEQ .chk_flag8           ; bit 1 not set → skip Sub_1F24
    JSR $1F24                ; Sub_1F24: advance scroll target (scroll-X direction)
    LDA $18
.chk_flag8:
    BIT #$08
    BEQ .chk_transition      ; bit 3 not set → skip Sub_1F5A
    JSR $1F5A                ; Sub_1F5A: advance scroll target (scroll-Y direction)

.chk_transition:
    ; --- Check dp:$17 transition flags ---
    LDA $17
    BNE .has_transition
    RTS                      ; nothing pending — fast exit

.has_transition:
    BPL .positive_17         ; bit 7 clear → positive flags path

    ; --- Negative $17 path: countdown timer ---
    LDA $19
    BEQ .hard_restart        ; $19=0 → warmboot
    BMI .hard_restart        ; $19 negative → warmboot
    DEC $19
    RTS

.hard_restart:
    ; Full warmboot: disable hw, save dp state, jump back to GameLoop
    JSR $0B4E                ; InitHW: SEI + forced blank
    LDX $00
    STX $05
    LDY $97
    LDA $1801,Y
    STA $07
    LDA $1881,Y
    STA $08
    LDA $1600,Y
    EOR #$01
    STA $09
    LDX $12
    STX $00
    LDX $14
    STX $02
    LDA $16
    STA $04
    LDX #$FF
    ASL $9A
    BRL $F339                ; → GameLoop ($0000): restart engine

    ; --- Positive $17 path ---
.positive_17:
    BIT #$40
    BNE .run_fade_loop       ; bit 6 set → fade-in loop
    BRL .chk_bit10           ; bit 6 clear → check bit 4 ($0D3E)

.run_fade_loop:
    ; Fade-in loop: decrement $19, call $881E each VBlank until done
    LDA $19
    BEQ .enter_transition
    BMI .enter_transition
    DEC $19
    LDA $1F
    PHA
    STZ $1F
    JSR $881E                ; frame update (DMA/controller)
    PLA
    STA $1F
    JSL $FDFFF7              ; wait for VBlank
    JSR $EC60                ; post-VBlank work
    BRA .run_fade_loop

.enter_transition:
    ; Scene transition: reinit HW + set up new color/mode
    JSR $0B4E                ; InitHW
    JSR $011B                ; unknown scene-setup routine
    TDC
    XBA                      ; B = 0 (dp high byte)
    LDA $25
    BEQ .mode_5_setup        ; $25=0 → plain mode 5
    BMI .negative_25         ; $25 negative → extract mode bits

    ; $25 positive: choose mode 0 or 6 based on bit 0
    BIT #$01
    BNE .lda_0
    LDA #$06
    BRA .do_jsl_c28000

.lda_0:
    LDA #$00
    BRA .do_jsl_c28000

.mode_5_setup:
    LDA #$05
    BRL $0CBE                ; → $19C7 (special warm-restart path)

.negative_25:
    REP #$20                 ; A → 16-bit
    AND #$003F               ; isolate low 6 bits of $25
    TAX
    SEP #$20                 ; A → 8-bit
    LDA $25
    ROL
    ROL
    ROL
    AND #$03                 ; bits 7–6 of $25 → 2-bit mode

.do_jsl_c28000:
    JSL $C28000              ; set BG mode
    JSR $0B4E                ; InitHW
    JSR $0B64                ; InstallNMI
    JSR $0B75                ; InstallIRQ
    REP #$20
    LDA #$0100
    TCD                      ; DP = $0100
    SEP #$20
    JSR $01A5                ; unknown init
    JSR $B192                ; unknown init
    LDA #$40
    TRB $17                  ; clear bit 6 of $17
    LDA #$40
    TSB $18                  ; set bit 6 of $18
    BRL $1AE6                ; → $2824 (post-transition work)

    ; --- Bit 4 dispatch ($0D3E) ---
.chk_bit10:
    BIT #$10
    BNE .handle_bit10
    BRL $0997                ; bit 4 clear → default handler ($16DC)

.handle_bit10:
    LDA #$10
    TRB $17                  ; clear bit 4
    JSR $28C0                ; unknown per-mode init
    LDX $5B
    LDA $7E3000,X            ; load current mode byte from WRAM
    CMP #$E6
    BNE .chk_ec
    BRL $001F                ; → mode-E6 handler ($0D78)

.chk_ec:
    CMP #$EC
    BNE .chk_ee
    BRL $00FF                ; → mode-EC handler ($0E5F)

.chk_ee:
    CMP #$EE
    BNE .chk_fa
    BRL $02AD                ; → mode-EE handler ($1014)

.chk_fa:
    CMP #$FA
    BNE .chk_fc
    BRL $045B                ; → mode-FA handler ($11C9)

.chk_fc:
    CMP #$FC
    BNE .default_mode
    BRL $06DF                ; → mode-FC handler ($1454)

.default_mode:
    BRL $0964                ; → default handler ($16DC)

; ============================================================
; $C0:1F24 — Sub_1F24 (54 bytes, $1F24–$1F59)
; Scroll-X target tracker: moves dp:$19 (low nibble) toward dp:$1B.
; Uses dp:$1C as step delay and dp:$1D as delay counter.
; When dp:$19 reaches dp:$1B, clears bit 1 of dp:$18.
; Called from Sub_0C76 when dp:$18 bit 1 is set.
; ============================================================
org $C01F24
Sub_1F24:
    LDA $19
    AND #$0F                 ; low nibble of $19 = current scroll-X
    CMP $1B                  ; compare to target
    BEQ .x_at_target         ; equal → done
    BCS .x_above             ; above → count down

    ; $19 below target: decrement delay or step up
    LDA $1D
    BEQ .x_reload_up         ; delay exhausted → reload and step
    DEC $1D
    RTS

.x_reload_up:
    LDA $1C
    STA $1D                  ; reload delay
    LDA $19
    AND #$0F
    INC $19                  ; step up
    RTS

.x_above:
    ; $19 above target: decrement delay or step down
    LDA $1D
    BEQ .x_reload_dn
    DEC $1D
    RTS

.x_reload_dn:
    LDA $1C
    STA $1D
    LDA $19
    DEC                      ; DEC A ($3A)
    BEQ .x_at_target_store   ; reached 0 → also done
    STA $19
    RTS

.x_at_target_store:
    STA $19

.x_at_target:
    LDA #$02
    TRB $18                  ; clear bit 1 of $18 (X done)
    RTS

; ============================================================
; $C0:1F5A — Sub_1F5A (45 bytes, $1F5A–$1F86)
; Scroll-Y target tracker: moves dp:$21 toward dp:$22.
; Uses dp:$23/$24 for step delay. Clears bit 3 of dp:$18 when done.
; Called from Sub_0C76 when dp:$18 bit 3 is set.
; ============================================================
org $C01F5A
Sub_1F5A:
    LDA $21
    CMP $22                  ; compare current to target
    BEQ .y_at_target         ; equal → done
    BCS .y_above             ; above → count down

    ; below target
    LDA $24
    BEQ .y_reload_up
    DEC $24
    RTS

.y_reload_up:
    LDA $23
    STA $24
    LDA $21
    INC $21                  ; step up
    RTS

.y_above:
    LDA $24
    BEQ .y_reload_dn
    DEC $24
    RTS

.y_reload_dn:
    LDA $23
    STA $24
    LDA $21
    DEC $21                  ; step down
    RTS

.y_at_target:
    LDA #$08
    TRB $18                  ; clear bit 3 of $18 (Y done)
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

; ============================================================
; $C0:1B90 — Sub_1B90 (23 bytes, $1B90–$1BA6)
; SPC audio command dispatcher. Called from ModeE6_Handler.
; On entry: M=1 (A=8-bit), X/Y=16-bit.
; Sets command args at $1E00–$1E02 then calls SPC driver via JSL $C70004.
; Command $19 cues a sound effect; arg0=dp:$FC, arg1=$0A00+dp:$97 table.
; ============================================================
org $C01B90
Sub_1B90:
    LDA $FC              ; 8-bit arg 0 from dp:$FC
    STA $1E01
    LDY $97              ; 16-bit index from dp:$97
    LDA $0A00,Y          ; arg 1: sound-effect byte from $0A00 table
    STA $1E02
    LDA #$19             ; SPC command byte $19
    STA $1E00
    JSL $C70004          ; → SPC700 driver entry
    RTS

; ============================================================
; $C0:2824 — Sub_2824 (36 bytes, $2824–$2847)
; Post-transition setup/fade loop. BRL target from Sub_0C76 transition
; path (offset $1AE6) and called from Sub_19C7.
; Calls $286C (scene-init probe). If non-zero return, exits immediately.
; Otherwise loops up to 15 VBlanks (dp:$19 counter): calls $881E (frame
; DMA/controller update), $00DE (VBlankHandlerShort), and $EC60 (post-VBlank).
; Clears dp:$1E and abs:$0407 on exit.
; On entry: M=1 (A=8-bit), X/Y=16-bit.
; ============================================================
org $C02824
Sub_2824:
    JSR $286C            ; scene-init probe; sets Z if not ready
    BNE .done            ; non-zero (Z=0) → done, skip loop
.loop:
    INC $19              ; advance transition counter
    LDA $1F
    PHA                  ; save dp:$1F
    STZ $1F              ; clear $1F during update
    JSR $881E            ; frame DMA/controller update
    PLA
    STA $1F              ; restore dp:$1F
    JSR $00DE            ; VBlankHandlerShort (minimal VBlank)
    JSR $EC60            ; post-VBlank work
    LDA $19
    CMP #$0F
    BMI .loop            ; loop while dp:$19 < 15
.done:
    STZ $1E
    STZ $0407            ; abs zero: 9C 07 04
    RTS

; ============================================================
; $C0:19C7 — Sub_19C7 (60 bytes, $19C7–$1A02)
; Mode-5 warm-restart. BRL target from Sub_0C76 mode-5-setup path.
; On entry: M=1 (A=8-bit), X/Y=16-bit.
; Reinitialises hardware for BG mode 5, sets DP=$0100, calls two engine
; helpers, conditionally moves bit 6 from dp:$17 to dp:$18, calls $B192,
; then calls Sub_2824 for the post-transition fade. Clears $0407, returns.
; ============================================================
org $C019C7
Sub_19C7:
    LDX #$0000           ; clear X (16-bit: A2 00 00)
    TDC                  ; A = D register low byte
    XBA                  ; swap A/B: clears B accumulator
    LDA #$05             ; BG mode 5
    JSL $C28000          ; set BG mode
    JSR $0B4E            ; InitHW: SEI + forced blank + disable NMI/DMA
    JSR $0B64            ; InstallNMI
    JSR $0B75            ; InstallIRQ
    REP #$20             ; A → 16-bit
    LDA #$0100
    TCD                  ; DP = $0100
    SEP #$20             ; A → 8-bit
    JSR $01A5            ; engine init helper
    JSR $1A03            ; mode-5 scene helper (distinct from $B192 path)
    REP #$10             ; ensure X/Y 16-bit
    LDA $17              ; load dp:$17 transition flags
    BIT #$40             ; test bit 6
    BEQ .no_bit6
    LDA #$40
    TRB $17              ; clear bit 6 of dp:$17
    LDA #$40
    TSB $18              ; set bit 6 of dp:$18
.no_bit6:
    JSR $B192
    JSR Sub_2824         ; post-transition fade loop
    STZ $0407
    RTS

; ============================================================
; $C0:0D78 — ModeE6_Handler header ($0D78–$0DA0)
; Mode-$E6 scroll-map update. BRL target from Sub_0C76 bit-4 dispatch
; (mode $E6 case, raw offset $001F from $0D5C).
; On entry: A=$E6 (current mode), X=layer index, M=1, X/Y=16-bit.
;
; This block increments both the current and previous layer modes in
; the $7E:3000 mode table (current: $E6→$E7; previous: whatever→+1).
; Then triggers an SPC audio command via Sub_1B90, loads two 16-bit
; scroll base registers ($1D0A→dp:$DB, $1D0E→dp:$DD), and falls into
; the computation block (org $C00DA1 below) to compute 8 VRAM indices.
;
; [Split into two org blocks so Sub_1B36 (which needs M=0) can appear
;  between them in file order, inheriting the REP #$20 state.]
; ============================================================
org $C00D78
ModeE6_Handler:
    INC                  ; A = $E7 (current mode $E6 + 1)
    STA.l $7E3000,X      ; update current layer: $E6 → $E7
    REP #$20             ; A → 16-bit
    TXA                  ; A = current layer index (16-bit)
    SEC
    SBC #$0100           ; A = previous layer index
    TAX                  ; X = previous layer
    LDA.l $7E3000,X      ; load previous layer mode (16-bit)
    INC                  ; advance previous mode
    STA.l $7E3000,X      ; write back
    SEP #$20             ; A → 8-bit
    STZ $60              ; clear dp:$60 (layer-loop counter)
    JSR Sub_1B90         ; trigger SPC audio command
    REP #$20             ; A → 16-bit
    LDA $1D0A            ; scroll X base (abs 16-bit)
    STA $DB              ; dp:$DB/$DC = scroll X base
    LDA $1D0E            ; scroll Y base
    STA $DD              ; dp:$DD/$DE = scroll Y base
    ; [M=0 here — Sub_1B36 follows in file order with correct M=0 state]

; ============================================================
; $C0:1B36 — Sub_1B36 (29 bytes, $1B36–$1B52)
; VRAM tilemap word-index calculator.
; On entry (M=0 = 16-bit A): A=tile col (0–31), Y=tile row (0–63).
; Returns: A = VRAM word index = col*32 + (row<32 ? row : row-32+$0400).
; Encodes a 32-col × 64-row BG tilemap split across two VRAM pages
; ($0000 for rows 0–31, $0400 for rows 32–63).
; Called from ModeE6_Handler computation block to build scroll table.
; [M=0 (16-bit A) inherited from ModeE6_Handler header above]
; ============================================================
org $C01B36
Sub_1B36:
    ASL                  ; col × 2
    ASL                  ; col × 4
    ASL                  ; col × 8
    ASL                  ; col × 16
    ASL                  ; col × 32
    STA $D9              ; dp:$D9/$DA = col*32 (16-bit store)
    TYA                  ; A = row
    CMP #$0020           ; row ≥ 32?
    BCS .rowhi
    CLC
    ADC $D9              ; A = row + col*32
    RTS
.rowhi:
    SEC
    SBC #$0020           ; row -= 32
    CLC
    ADC $D9              ; A = (row-32) + col*32
    CLC
    ADC #$0400           ; + $0400 (second tilemap VRAM page)
    RTS
    ; [M=0 here — ModeE6_Handler computation block continues below]

; ============================================================
; $C0:0DA1 — ModeE6_Handler computation block ($0DA1–$0E5E)
; Computes 8 VRAM scroll-map word indices (2 passes of 4 corners each)
; and stores to $09CA–$09D8. Pass 1 uses col derived from dp:$5C;
; pass 2 uses (dp:$5C - 1). Ends by setting bit 4 of dp:$5F and
; tail-jumping to the default mode handler via BRL $087D (→ $16DC).
; [M=0 (16-bit A) inherited from Sub_1B36 above]
; ============================================================
org $C00DA1
    ; --- Pass 1: 4-corner VRAM indices at (col, row) + neighbours ---
    LDA $5B              ; scroll row base (16-bit dp load)
    ASL
    SEC
    SBC $DB              ; subtract scroll X base
    CLC
    ADC $1D99            ; add row adjustment
    AND #$003F           ; wrap to 64 rows
    TAY                  ; Y = tile row (0–63)
    LDA $5C              ; scroll col base (16-bit dp load)
    ASL
    SEC
    SBC $DD              ; subtract scroll Y base
    CLC
    ADC $1D9A            ; add col adjustment
    AND #$001F           ; wrap to 32 cols
    TAX                  ; X = col (A = col too; TAX doesn't modify A)
    JSR Sub_1B36         ; → A = VRAM index(col, row)
    CLC
    ADC $1D7C            ; add VRAM base
    STA $09CA            ; BG scroll VRAM word 0
    TYA                  ; A = row
    PHA                  ; save row on stack
    INC                  ; row + 1
    AND #$003F
    TAY                  ; Y = (row+1) wrapped
    TXA                  ; A = col (X unchanged by Sub_1B36)
    JSR Sub_1B36         ; → A = VRAM index(col, row+1)
    CLC
    ADC $1D7C
    STA $09CC            ; BG scroll VRAM word 1
    PLY                  ; Y = original row
    TXA                  ; A = col
    INC                  ; col + 1
    AND #$001F
    TAX                  ; X = (col+1) wrapped
    JSR Sub_1B36         ; → A = VRAM index(col+1, row)
    CLC
    ADC $1D7C
    STA $09CE            ; BG scroll VRAM word 2
    TYA                  ; A = original row
    INC                  ; row + 1
    AND #$003F
    TAY                  ; Y = (row+1) wrapped
    TXA                  ; A = col+1
    JSR Sub_1B36         ; → A = VRAM index(col+1, row+1)
    CLC
    ADC $1D7C
    STA $09D0            ; BG scroll VRAM word 3
    ; --- Pass 2: same 4-corner pattern, col base decremented by 1 ---
    LDA $5B
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY                  ; Y = tile row (same formula)
    LDA $5C
    DEC                  ; DEC A (opcode 3A): col base − 1
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36         ; → A = VRAM index(col', row)
    CLC
    ADC $1D7C
    STA $09D2            ; BG scroll VRAM word 4
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36         ; → A = VRAM index(col', row+1)
    CLC
    ADC $1D7C
    STA $09D4            ; BG scroll VRAM word 5
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36         ; → A = VRAM index(col'+1, row)
    CLC
    ADC $1D7C
    STA $09D6            ; BG scroll VRAM word 6
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36         ; → A = VRAM index(col'+1, row+1)
    CLC
    ADC $1D7C
    STA $09D8            ; BG scroll VRAM word 7
    SEP #$20             ; A → 8-bit
    LDA #$10
    TSB $5F              ; set bit 4 of dp:$5F (scroll-update trigger)
    BRL $087D            ; → $16DC (default mode handler)

; ============================================================
; $C0:0E5F — ModeEC_Handler (437 bytes, $0E5F–$1013)
; Mode-$EC scroll-map update. BRL target from Sub_0C76 bit-4 dispatch
; (mode $EC case, raw offset $00FF from $0D5D).
; On entry: A=$EC (current mode), X=layer index, M=1, X/Y=16-bit.
;
; Prologue: updates 4 entries in the $7E:3000 mode table
; (current, current+1, current-$100, current-$101), each incremented
; by 1. Sets dp:$60=$01 (vs STZ in ModeE6_Handler), then calls
; Sub_1B90 (SPC audio). Confirmed: both Sub_1B36 and Sub_1B90 reused.
;
; Computation: 4 passes × 4 VRAM corner indices = 16 JSR Sub_1B36 calls,
; storing to $09CA–$09E8 (vs 8 calls/$09CA–$09D8 in mode $E6).
; Pass 1: row=$5B,   col=$5C   (note: uses LDX $5B; TXA anomaly)
; Pass 2: row=$5B,   col=$5C−1
; Pass 3: row=$5B+1, col=$5C
; Pass 4: row=$5B+1, col=$5C−1
; Ends by setting bit 4 of dp:$5F and BRL to $16DC (default handler).
; ============================================================
org $C00E5F
ModeEC_Handler:
    INC A                   ; $EC → $ED
    STA.l $7E3000,X         ; update current layer entry
    INX                     ; advance to next layer entry
    LDA.l $7E3000,X         ; load next entry (M=1, byte load)
    INC A
    STA.l $7E3000,X         ; update next entry
    REP #$20                ; M → 0 (16-bit A)
    TXA                     ; A = X (16-bit layer index)
    SEC
    SBC #$0100              ; A = X − $0100
    TAX                     ; X = previous block
    SEP #$20                ; M → 1 (8-bit A)
    LDA.l $7E3000,X         ; load entry at X−$100
    INC A
    STA.l $7E3000,X         ; update it
    DEX                     ; X = X − 1
    LDA.l $7E3000,X         ; load entry at X−$101
    INC A
    STA.l $7E3000,X         ; update it
    LDA #$01
    STA $60                 ; dp:$60 = $01 (vs STZ in ModeE6_Handler)
    JSR Sub_1B90            ; SPC audio command $19
    ; --- Computation block: 4 passes × 4 VRAM corner indices ---
    REP #$20                ; M → 0 (16-bit A)
    LDA $1D0A               ; scroll X base (abs 16-bit)
    STA $DB                 ; dp:$DB/$DC
    LDA $1D0E               ; scroll Y base
    STA $DD                 ; dp:$DD/$DE
    ; --- Pass 1: row=$5B, col=$5C → $09CA–$09D0 ---
    ; (anomaly: uses LDX $5B / TXA instead of LDA $5B)
    LDX $5B                 ; X = dp:$5B (row base, 16-bit X load)
    TXA                     ; A = row base (16-bit)
    ASL                     ; A = row*2
    SEC
    SBC $DB                 ; A = row*2 − $DB
    CLC
    ADC $1D99               ; + row adjustment
    AND #$003F              ; wrap to 64 rows
    TAY                     ; Y = tile row
    LDA $5C                 ; A = col base
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F              ; wrap to 32 cols
    TAX                     ; X = tile col
    JSR Sub_1B36            ; A = VRAM index(col, row)
    CLC
    ADC $1D7C               ; + VRAM base
    STA $09CA               ; VRAM word 0
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36            ; A = VRAM index(col, row+1)
    CLC
    ADC $1D7C
    STA $09CC               ; VRAM word 1
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36            ; A = VRAM index(col+1, row)
    CLC
    ADC $1D7C
    STA $09CE               ; VRAM word 2
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36            ; A = VRAM index(col+1, row+1)
    CLC
    ADC $1D7C
    STA $09D0               ; VRAM word 3
    ; --- Pass 2: row=$5B, col=$5C−1 → $09D2–$09D8 ---
    LDA $5B                 ; A = row base (normal LDA this time)
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    DEC                     ; col − 1 (DEC A = 3A)
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36            ; A = VRAM index(col−1, row)
    CLC
    ADC $1D7C
    STA $09D2               ; VRAM word 4
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36            ; A = VRAM index(col−1, row+1)
    CLC
    ADC $1D7C
    STA $09D4               ; VRAM word 5
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36            ; A = VRAM index(col, row)
    CLC
    ADC $1D7C
    STA $09D6               ; VRAM word 6
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36            ; A = VRAM index(col, row+1)
    CLC
    ADC $1D7C
    STA $09D8               ; VRAM word 7
    ; --- Pass 3: row=$5B+1, col=$5C → $09DA–$09E0 ---
    LDA $5B
    INC                     ; row + 1 (INC A = 1A)
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    ASL                     ; col unchanged (no DEC)
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36            ; A = VRAM index(col, row+1)
    CLC
    ADC $1D7C
    STA $09DA               ; VRAM word 8
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36            ; A = VRAM index(col, row+2)
    CLC
    ADC $1D7C
    STA $09DC               ; VRAM word 9
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36            ; A = VRAM index(col+1, row+1)
    CLC
    ADC $1D7C
    STA $09DE               ; VRAM word 10
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36            ; A = VRAM index(col+1, row+2)
    CLC
    ADC $1D7C
    STA $09E0               ; VRAM word 11
    ; --- Pass 4: row=$5B+1, col=$5C−1 → $09E2–$09E8 ---
    LDA $5B
    INC                     ; row + 1
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    DEC                     ; col − 1
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36            ; A = VRAM index(col−1, row+1)
    CLC
    ADC $1D7C
    STA $09E2               ; VRAM word 12
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36            ; A = VRAM index(col−1, row+2)
    CLC
    ADC $1D7C
    STA $09E4               ; VRAM word 13
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36            ; A = VRAM index(col, row+1)
    CLC
    ADC $1D7C
    STA $09E6               ; VRAM word 14
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36            ; A = VRAM index(col, row+2)
    CLC
    ADC $1D7C
    STA $09E8               ; VRAM word 15
    SEP #$20                ; A → 8-bit
    LDA #$10
    TSB $5F                 ; set bit 4 of dp:$5F (scroll-update trigger)
    BRL $06C8               ; → $16DC (default mode handler)

; ============================================================
; $C0:1014 — ModeEE_Handler (437 bytes, $1014–$11C8)
;
; Scroll mode $EE handler: updates 4 entries in the $7E:3000
; layer table, then computes VRAM word-indices for 16 tilemap
; corners (4 passes × 4 corners), storing to $09CA–$09E8.
;
; Row range: $5B−1, $5B  (negative direction vs Mode-EC)
; Col range: $5C, $5C−1
;
; Differences from ModeEC_Handler:
;   - Step 2 uses DEX (not INX) → updates current−1 (not +1)
;   - Step 4 uses INX (not DEX) → lands at current−$100
;   - JSR Sub_1B90 is called BEFORE STA $60 (reversed from EC)
;   - Pass 1 row: LDX $5B; TXA; DEC; ASL (row−1, LDX anomaly)
;   - Pass 2 row: LDA $5B; DEC; ASL  (row−1 without LDX)
;   - Passes 3–4 row: LDA $5B; ASL   (row, no dec/inc)
;   - Passes 1,3 col: LDA $5C; ASL   (col, no dec)
;   - Passes 2,4 col: LDA $5C; DEC; ASL (col−1)
;   - Tail BRL: raw offset $0513 → $16DC
; ============================================================
org $C01014
ModeEE_Handler:
    ; --- Prologue: update 4 mode-table entries (51 bytes) ---
    INC A                   ; mode byte $EE → $EF
    STA.l $7E3000,X         ; update current entry
    DEX                     ; X → current−1
    LDA.l $7E3000,X
    INC A
    STA.l $7E3000,X         ; update current−1
    REP #$20                ; M → 0 (16-bit A)
    TXA
    SEC
    SBC #$0100              ; A = current−1−$100 = current−$101
    TAX
    SEP #$20                ; M → 1 (8-bit A)
    LDA.l $7E3000,X         ; load current−$101
    INC A
    STA.l $7E3000,X         ; update current−$101
    INX                     ; X → current−$100
    LDA.l $7E3000,X
    INC A
    STA.l $7E3000,X         ; update current−$100
    JSR Sub_1B90            ; SPC audio command $19 (called BEFORE STA $60)
    LDA #$01
    STA $60                 ; dp:$60 = $01

    ; --- Computation header: load scroll bases (12 bytes) ---
    REP #$20                ; M → 0 (16-bit A for all computation below)
    LDA $1D0A               ; scroll X base
    STA $DB                 ; dp:$DB/$DC
    LDA $1D0E               ; scroll Y base
    STA $DD                 ; dp:$DD/$DE

    ; --- Pass 1: row = ($5B−1)×2, col = $5C×2 → $09CA–$09D0 ---
    ; (LDX $5B anomaly: uses LDX+TXA instead of LDA, same as ModeEC pass 1)
    LDX $5B                 ; X = dp:$5B (16-bit, row base)
    TXA                     ; A = row base
    DEC                     ; A = row−1
    ASL                     ; A = (row−1)×2
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C                 ; A = col base (16-bit load from dp:$5C/$5D)
    ASL                     ; A = col×2
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36            ; A = VRAM index(row−1, col)
    CLC
    ADC $1D7C
    STA $09CA               ; corner (0,0)
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36            ; A = VRAM index(row, col)
    CLC
    ADC $1D7C
    STA $09CC               ; corner (1,0)
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36            ; A = VRAM index(row−1, col+1)
    CLC
    ADC $1D7C
    STA $09CE               ; corner (0,1)
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36            ; A = VRAM index(row, col+1)
    CLC
    ADC $1D7C
    STA $09D0               ; corner (1,1)

    ; --- Pass 2: row = ($5B−1)×2, col = ($5C−1)×2 → $09D2–$09D8 ---
    LDA $5B
    DEC                     ; row−1
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    DEC                     ; col−1
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09D2               ; corner (0,0)
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09D4               ; corner (1,0)
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09D6               ; corner (0,1)
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09D8               ; corner (1,1)

    ; --- Pass 3: row = $5B×2, col = $5C×2 → $09DA–$09E0 ---
    LDA $5B
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09DA               ; corner (0,0)
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09DC               ; corner (1,0)
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09DE               ; corner (0,1)
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09E0               ; corner (1,1)

    ; --- Pass 4: row = $5B×2, col = ($5C−1)×2 → $09E2–$09E8 ---
    LDA $5B
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    DEC                     ; col−1
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09E2               ; corner (0,0)
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09E4               ; corner (1,0)
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09E6               ; corner (0,1)
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09E8               ; corner (1,1)

    ; --- Tail (9 bytes) ---
    SEP #$20                ; A → 8-bit
    LDA #$10
    TSB $5F                 ; set bit 4 of dp:$5F
    BRL $0513               ; raw offset → $16DC (default mode handler)

; ============================================================
; $C0:11C9 — ModeFA_Handler (651 bytes, $11C9–$1453)
;
; Scroll mode $FA handler: updates 6 entries in the $7E:3000
; layer table, then computes VRAM word-indices for 24 tilemap
; corners (6 passes × 4 corners), storing to $09CA–$09F8.
;
; Row range: $5B, $5B+1  (positive direction, same as EC)
; Col range: $5C, $5C−1, $5C−2  (3 columns)
;
; dp:$60 set to $02 (vs $01 for EC/EE)
; JSR Sub_1B90 called before STA $60 (same as EE)
; Pass 1 uses LDX $5B anomaly (no DEC/INC, same as EC/EC)
; Passes 3,6 use double DEC for col (col−2)
; ============================================================
org $C011C9
ModeFA_Handler:
    ; --- Prologue: update 6 mode-table entries (80 bytes) ---
    INC A                   ; mode byte $FA → $FB
    STA.l $7E3000,X         ; update current
    INX                     ; X → current+1
    LDA.l $7E3000,X
    INC A
    STA.l $7E3000,X         ; update current+1
    REP #$20
    TXA
    SEC
    SBC #$0100              ; A = current+1−$100 = current−$FF
    TAX
    SEP #$20
    LDA.l $7E3000,X
    INC A
    STA.l $7E3000,X         ; update current−$FF
    DEX                     ; X → current−$100
    LDA.l $7E3000,X
    INC A
    STA.l $7E3000,X         ; update current−$100
    REP #$20
    TXA
    SEC
    SBC #$0100              ; A = current−$200
    TAX
    SEP #$20
    LDA.l $7E3000,X
    INC A
    STA.l $7E3000,X         ; update current−$200
    INX                     ; X → current−$1FF
    LDA.l $7E3000,X
    INC A
    STA.l $7E3000,X         ; update current−$1FF
    JSR Sub_1B90            ; SPC audio command $19
    LDA #$02
    STA $60                 ; dp:$60 = $02

    ; --- Computation header (12 bytes) ---
    REP #$20
    LDA $1D0A
    STA $DB
    LDA $1D0E
    STA $DD

    ; --- Pass 1: row = $5B×2, col = $5C×2 → $09CA–$09D0 ---
    ; (LDX $5B anomaly: no DEC/INC on row)
    LDX $5B
    TXA
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09CA
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09CC
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09CE
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09D0

    ; --- Pass 2: row = $5B×2, col = ($5C−1)×2 → $09D2–$09D8 ---
    LDA $5B
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    DEC                     ; col−1
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09D2
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09D4
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09D6
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09D8

    ; --- Pass 3: row = $5B×2, col = ($5C−2)×2 → $09DA–$09E0 ---
    LDA $5B
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    DEC                     ; col−1
    DEC                     ; col−2
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09DA
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09DC
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09DE
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09E0

    ; --- Pass 4: row = ($5B+1)×2, col = $5C×2 → $09E2–$09E8 ---
    LDA $5B
    INC                     ; row+1
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09E2
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09E4
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09E6
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09E8

    ; --- Pass 5: row = ($5B+1)×2, col = ($5C−1)×2 → $09EA–$09F0 ---
    LDA $5B
    INC                     ; row+1
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    DEC                     ; col−1
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09EA
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09EC
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09EE
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09F0

    ; --- Pass 6: row = ($5B+1)×2, col = ($5C−2)×2 → $09F2–$09F8 ---
    LDA $5B
    INC                     ; row+1
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    DEC                     ; col−1
    DEC                     ; col−2
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09F2
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09F4
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09F6
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09F8

    ; --- Tail (9 bytes) ---
    SEP #$20
    LDA #$10
    TSB $5F
    BRL $0288               ; raw offset → $16DC (default mode handler)

; ============================================================
; $C0:1454 — ModeFC_Handler (648 bytes, $1454–$16DB)
;
; Scroll mode $FC handler: updates 6 entries in the $7E:3000
; layer table, then computes VRAM word-indices for 24 tilemap
; corners (6 passes × 4 corners), storing to $09CA–$09F8.
;
; Row range: $5B−1, $5B  (negative direction, like EE)
; Col range: $5C, $5C−1, $5C−2  (3 columns)
;
; dp:$60 set to $02 (same as FA)
; JSR Sub_1B90 called before STA $60 (same as EE/FA)
; Pass 1 uses LDX $5B anomaly WITH DEC (like ModeEE pass 1)
; Passes 3,6 use double DEC for col (col−2)
; NO tail BRL — falls through directly to $16DC (DefaultModeHandler)
; ============================================================
org $C01454
ModeFC_Handler:
    ; --- Prologue: update 6 mode-table entries (80 bytes) ---
    INC A                   ; mode byte $FC → $FD
    STA.l $7E3000,X         ; update current
    DEX                     ; X → current−1
    LDA.l $7E3000,X
    INC A
    STA.l $7E3000,X         ; update current−1
    REP #$20
    TXA
    SEC
    SBC #$0100              ; A = current−1−$100 = current−$101
    TAX
    SEP #$20
    LDA.l $7E3000,X
    INC A
    STA.l $7E3000,X         ; update current−$101
    INX                     ; X → current−$100
    LDA.l $7E3000,X
    INC A
    STA.l $7E3000,X         ; update current−$100
    REP #$20
    TXA
    SEC
    SBC #$0100              ; A = current−$200
    TAX
    SEP #$20
    LDA.l $7E3000,X
    INC A
    STA.l $7E3000,X         ; update current−$200
    DEX                     ; X → current−$201
    LDA.l $7E3000,X
    INC A
    STA.l $7E3000,X         ; update current−$201
    JSR Sub_1B90            ; SPC audio command $19
    LDA #$02
    STA $60                 ; dp:$60 = $02

    ; --- Computation header (12 bytes) ---
    REP #$20
    LDA $1D0A
    STA $DB
    LDA $1D0E
    STA $DD

    ; --- Pass 1: row = ($5B−1)×2, col = $5C×2 → $09CA–$09D0 ---
    ; (LDX $5B anomaly WITH DEC, same as ModeEE pass 1)
    LDX $5B
    TXA
    DEC                     ; row−1
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09CA
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09CC
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09CE
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09D0

    ; --- Pass 2: row = ($5B−1)×2, col = ($5C−1)×2 → $09D2–$09D8 ---
    LDA $5B
    DEC                     ; row−1
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    DEC                     ; col−1
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09D2
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09D4
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09D6
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09D8

    ; --- Pass 3: row = ($5B−1)×2, col = ($5C−2)×2 → $09DA–$09E0 ---
    LDA $5B
    DEC                     ; row−1
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    DEC                     ; col−1
    DEC                     ; col−2
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09DA
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09DC
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09DE
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09E0

    ; --- Pass 4: row = $5B×2, col = $5C×2 → $09E2–$09E8 ---
    LDA $5B
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09E2
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09E4
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09E6
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09E8

    ; --- Pass 5: row = $5B×2, col = ($5C−1)×2 → $09EA–$09F0 ---
    LDA $5B
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    DEC                     ; col−1
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09EA
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09EC
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09EE
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09F0

    ; --- Pass 6: row = $5B×2, col = ($5C−2)×2 → $09F2–$09F8 ---
    LDA $5B
    ASL
    SEC
    SBC $DB
    CLC
    ADC $1D99
    AND #$003F
    TAY
    LDA $5C
    DEC                     ; col−1
    DEC                     ; col−2
    ASL
    SEC
    SBC $DD
    CLC
    ADC $1D9A
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09F2
    TYA
    PHA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09F4
    PLY
    TXA
    INC
    AND #$001F
    TAX
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09F6
    TYA
    INC
    AND #$003F
    TAY
    TXA
    JSR Sub_1B36
    CLC
    ADC $1D7C
    STA $09F8

    ; --- Tail (6 bytes, no BRL — falls through to $16DC) ---
    SEP #$20
    LDA #$10
    TSB $5F                 ; set bit 4 of dp:$5F
