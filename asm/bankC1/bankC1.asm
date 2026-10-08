arch snes.cpu
hirom
incsrc "../hardware.inc"

; ============================================================
; Bank $C1 — Battle Engine
; File offset 0x010000 (bank $C1 = ROM offset $10000)
;
; CPU state on entry from field via JSL $C10000 (Battle_Main):
;   native mode, M=1 (A 8-bit), X=0 (X/Y 16-bit)
;   DP=0, DB=caller's bank
; ============================================================

; ============================================================
; Math Utility Cluster ($C1:0089–$C1:011E)
; ============================================================

; $C1:0089 — Battle_Mul8 (30 bytes, $0089–$00A6)
; 8×8→16 HW multiply via WRMPYA/WRMPYB/RDMPYL.
; In:  !Battle_Mul8A = multiplicand, !Battle_Mul8B = multiplier
; Out: !Battle_Mul8Product = 16-bit product; operands mirrored to
;      !Battle_MulMirrorA/B
; M=1 on entry; uses STA.l for HW regs (DB unknown, must be fully qualified)
org $C10089
Battle_Mul8:
    LDA.b !Battle_Mul8A
    STA.b !Battle_MulMirrorA
    STA.l WRMPYA            ; $004202 — load multiplicand (long: DB may be any)
    LDA.b !Battle_Mul8B
    STA.b !Battle_MulMirrorB
    STA.l WRMPYB            ; $004203 — load multiplier (triggers multiply)
    REP #$20                ; A → 16-bit
    NOP
    NOP
    LDA.l RDMPYL            ; $004216 — read 16-bit product
    STA.b !Battle_Mul8Product
    TDC
    SEP #$20                ; A → 8-bit
    RTS

; $C1:00A7 — Battle_Mul8x16 (48 bytes, $00A7–$00D6)
; 8×16→24 multiply in two hardware passes (the top byte of the product
; is zeroed first, so nothing from the caller is accumulated):
;   pass 1: Factor8 × low byte of Factor16  -> Product+0/+1
;   pass 2: Factor8 × high byte of Factor16 -> added at Product+1/+2
; In:  !Battle_MulFactor8 (8-bit), !Battle_MulFactor16 (16-bit)
; Out: !Battle_MulProduct = 24-bit product (Battle_SinLookup returns
;      its middle byte, i.e. product >> 8)
; Sets DB=0 itself (PHB/TDC/PHA/PLB) to safely use STA.w for HW regs.
org $C100A7
Battle_Mul8x16:
    PHB
    TDC
    PHA
    PLB                     ; DB = 0 (hardware regs accessible via absolute)
    LDA.b !Battle_MulFactor8
    STA.b !Battle_MulMirrorA
    STA.w WRMPYA            ; $4202 — first operand (DB=0 → $004202)
    LDA.b !Battle_MulFactor16
    STA.b !Battle_MulMirrorB
    STA.w WRMPYB            ; $4203 — triggers first multiply (Factor8 × Factor16 low)
    PHP
    LDA.b !Battle_MulFactor16+1
    STZ.b !Battle_MulProduct+2
    LDX.w RDMPYL            ; $4216 — first 16-bit partial product
    STA.b !Battle_MulMirrorB
    STA.w WRMPYB            ; $4203 — triggers second multiply (Factor8 × Factor16 high)
    STX.b !Battle_MulProduct ; save first product low word
    REP #$21                ; A → 16-bit, C=0 (clear carry for ADC)
    LDA.b !Battle_MulProduct+1
    ADC.w RDMPYL            ; $4216 — add second partial product, shifted up 8 bits
    STA.b !Battle_MulProduct+1
    TDC
    PLP
    SEP #$20                ; A → 8-bit
    PLB
    RTS

; $C1:00D7 — Battle_Divide (54 bytes, $00D7–$010C)
; 16÷8 HW divide via $4204/$4205/$4206/$4214.
; In:  !Battle_DivDividend (16-bit), !Battle_DivDivisor (8-bit)
; Out: !Battle_DivQuotient, !Battle_DivRemainder (16-bit each);
;      operands mirrored to !Battle_DivMirrorLo/Hi/Divisor
; Brackets the work with INC/STZ !Battle_DivBusy (busy flag in WRAM).
org $C100D7
Battle_Divide:
    INC.w !Battle_DivBusy   ; mark divider busy
    LDA.b !Battle_DivDividend
    STA.b !Battle_DivMirrorLo
    STA.l WRDIVL            ; $004204 — dividend low byte
    LDA.b !Battle_DivDividend+1
    STA.b !Battle_DivMirrorHi
    STA.l WRDIVH            ; $004205 — dividend high byte
    LDA.b !Battle_DivDivisor
    STA.b !Battle_DivMirrorDivisor
    STA.l WRDIVB            ; $004206 — divisor (triggers divide)
    REP #$20                ; A → 16-bit
    NOP                     ; 6 NOPs: hardware latency for divide result
    NOP
    NOP
    NOP
    NOP
    NOP
    LDA.l RDDIVL            ; $004214 — read 16-bit quotient
    STA.b !Battle_DivQuotient
    LDA.l RDMPYL            ; $004216 — read 16-bit remainder
    STA.b !Battle_DivRemainder
    TDC
    SEP #$20                ; A → 8-bit
    STZ.w !Battle_DivBusy   ; divider free
    RTS

; $C1:010D–$C1:011E — Shift helpers (18 bytes, $010D–$011E)
; Overlapping fall-through stubs for power-of-2 left/right shifts on A.
; They work at either accumulator width: some callers run them with M=1,
; others with M=0 (BattleUI_DrawSlotGaugeBar and the low-HP test in
; BattleUI_DrawPcNamePanel shift a 16-bit A). ASL A / LSR A = 1 byte each.
;
; Left-shift chain: ShiftLeft8 (8 ASL → *256) → ShiftLeft4 (4 ASL → *16)
;   → ShiftLeft3 (3 ASL → *8, RTS)
; Right-shift chain: Battle_ShiftRight8 (8 LSR → >>8) → ShiftRight6 (>>6)
;   → ShiftRight5 (>>5) → ShiftRight4 (>>4) → ShiftRight3 (>>3, RTS)
org $C1010D
Battle_ShiftLeft8:          ; A <<= 8 (4 here, then falls through ShiftLeft4's 1 + ShiftLeft3's 3)
    ASL A
    ASL A
    ASL A
    ASL A
Battle_ShiftLeft4:          ; A <<= 4 (falls through ShiftLeft3 chain)
    ASL A
Battle_ShiftLeft3:          ; A <<= 3
    ASL A
    ASL A
    ASL A
    RTS
Battle_ShiftRight8:         ; A >>= 8 (2 extra LSR before ShiftRight6 chain)
    LSR A
    LSR A
Battle_ShiftRight6:         ; A >>= 6
    LSR A
Battle_ShiftRight5:         ; A >>= 5
    LSR A
Battle_ShiftRight4:         ; A >>= 4
    LSR A
Battle_ShiftRight3:         ; A >>= 3
    LSR A
    LSR A
    LSR A
    RTS

; ============================================================
; Battle Message / Number Display Cluster ($C1:011F–$C1:01F8)
; ============================================================

; $C1:011F — BattleMsg_FormatNumberDigits (85 bytes, $011F–$0173)
; Format the 16-bit value in !BattleMsg_NumValue (0-999) into digit tiles:
;   !BattleMsg_Digit1000 = blank, Digit100 / Digit10 / Digit1 = digits,
;   tiles looked up in !BattleRom_DigitTiles. NumValue is consumed.
; Entry: M=0 (16-bit A), X=0 (16-bit), DB=$7E (WRAM accessible)
; Exit:  M=1 (8-bit A), X=0 (16-bit)
; Note: M=0 is established by the caller; no REP #$20 emitted here, so
;   the SBC/ADC immediates carry an explicit .w (asar does not track M).
; No JSR/JSL calls.
org $C1011F
BattleMsg_FormatNumberDigits:
    PHX
    TDC
    TAX
.hundreds_loop:
    SEC
    LDA.w !BattleMsg_NumValue
    SBC.w #!BattleMsg_Hundred   ; subtract 100
    STA.w !BattleMsg_NumValue
    INX
    BCS .hundreds_loop
    CLC
    LDA.w !BattleMsg_NumValue
    ADC.w #!BattleMsg_Hundred   ; restore overshoot
    STA.w !BattleMsg_NumValue
    DEX
    PHX                         ; push hundreds digit count
    TDC
    TAX
.tens_loop:
    SEC
    LDA.w !BattleMsg_NumValue
    SBC.w #!BattleMsg_Ten       ; subtract 10
    STA.w !BattleMsg_NumValue
    INX
    BCS .tens_loop
    CLC
    LDA.w !BattleMsg_NumValue
    ADC.w #!BattleMsg_Ten       ; restore overshoot; A = ones digit (not stored back)
    DEX
    PHX                         ; push tens digit count
    SEP #$20                    ; A → 8-bit
    TAX                         ; X = ones digit
    LDA.l !BattleRom_DigitTiles,X ; ones → digit tile glyph
    STA.w !BattleMsg_Digit1
    PLX                         ; X = tens count
    LDA.l !BattleRom_DigitTiles,X
    STA.w !BattleMsg_Digit10
    PLX                         ; X = hundreds count
    LDA.l !BattleRom_DigitTiles,X
    STA.w !BattleMsg_Digit100
    LDA.b #!BattleUI_TileBlank  ; thousands digit = blank ($FF)
    STA.w !BattleMsg_Digit1000
    PLX
    RTS

; $C1:0174 — BattleMsg_FormatTwoDigits (53 bytes, $0174–$01A8)
; Two-digit variant of BattleMsg_FormatNumberDigits: formats
; !BattleMsg_NumValue as tens+ones only. Digit1000/Digit100 = blank;
; Digit10 = tens, Digit1 = ones. Used for two-digit values (0–99).
; Entry: M=0 (16-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1 (8-bit A), X=0 (16-bit)
; Note: same explicit .w immediates as BattleMsg_FormatNumberDigits.
; No JSR/JSL calls.
org $C10174
BattleMsg_FormatTwoDigits:
    PHX
    TDC
    TAX
.tens_loop:
    SEC
    LDA.w !BattleMsg_NumValue
    SBC.w #!BattleMsg_Ten       ; subtract 10
    STA.w !BattleMsg_NumValue
    INX
    BCS .tens_loop
    CLC
    LDA.w !BattleMsg_NumValue
    ADC.w #!BattleMsg_Ten       ; restore overshoot; A = ones digit
    DEX
    PHX                         ; push tens digit count
    SEP #$20                    ; A → 8-bit
    TAX                         ; X = ones digit
    LDA.l !BattleRom_DigitTiles,X ; ones → digit tile glyph
    STA.w !BattleMsg_Digit1
    PLX                         ; X = tens count
    LDA.l !BattleRom_DigitTiles,X
    STA.w !BattleMsg_Digit10
    LDA.b #!BattleUI_TileBlank  ; hundreds = blank
    STA.w !BattleMsg_Digit100
    STA.w !BattleMsg_Digit1000  ; thousands = blank
    PLX
    RTS

; $C1:01A9 — BattleMsg_ReencodeTextBuffer (80 bytes, $01A9–$01F8)
; Back up the 16 raw text bytes the caller left in !BattleMsg_TextTiles
; to !BattleMsg_TextSource, blank both tile rows (TextTiles/TextTopTiles),
; then re-encode each text byte into a lower-row tile (TextTiles,X) and
; the tile above it (TextTopTiles,X):
;   $40–$68 → tile = byte + $40, upper tile = $71 (code set 1)
;   $69–$72 → tile = byte + $17, upper tile = $72 (code set 2)
;   $73+, < $40 → tile = byte unchanged, upper tile = $FF (blank)
;   $00     → stop early (the rest is already blank)
; What the two sets are is inferred, not checked against the font: set 1
; has 41 codes and set 2 has 10, the counts of Japanese kana that take a
; dakuten and a handakuten, so $71/$72 are probably those marks drawn
; above the base character (a leftover of the Japanese text code).
; Entry: M=1 (8-bit A), X=0 (16-bit); entry state from caller
; Exit:  M=1 (8-bit A); DB=$7E (set by the MVN)
; No JSR/JSL calls.
org $C101A9
BattleMsg_ReencodeTextBuffer:
    REP #$20                    ; A → 16-bit
    LDX.w #!BattleMsg_TextTiles ; MVN source
    LDY.w #!BattleMsg_TextSource ; MVN destination
    LDA.w #!BattleMsg_TextLen-1 ; count − 1 (copy 16 bytes)
    ; back up the raw text: TextTiles -> TextSource
    MVN !Battle_WramBank,!Battle_WramBank ; lint-ok: MVN takes bank bytes and has no width suffix
    LDX.w #!BattleMsg_TextBufBytes-2 ; last word of both tile rows (step −2)
.blank_loop:
    STA.w !BattleMsg_TextTiles,X ; MVN leaves A=$FFFF: blank two tiles
    DEX
    DEX
    BPL .blank_loop
    TDC                         ; A = 0
    TAX                         ; X = 0
    SEP #$20                    ; A → 8-bit
.char_loop:
    LDA.w !BattleMsg_TextSource,X ; read source char from backup
    BEQ .done                   ; $00 = end of string
    CMP.b #!BattleMsg_CharTileMin
    BCS .passthrough            ; $73+ → already a tile, nothing above
    CMP.b #!BattleMsg_CharSet2Min
    BCS .range69                ; $69–$72 → code set 2
    CMP.b #!BattleMsg_CharSet1Min
    BCC .passthrough            ; < $40 → already a tile
    ; $40–$68: code set 1
    CLC
    ADC.b #!BattleMsg_CharSet1TileAdd
    STA.w !BattleMsg_TextTiles,X
    LDA.b #!BattleMsg_CharSet1Top
    BRA .store_plane
.range69:
    ; $69–$72: code set 2
    CLC
    ADC.b #!BattleMsg_CharSet2TileAdd
    STA.w !BattleMsg_TextTiles,X
    LDA.b #!BattleMsg_CharSet2Top
    BRA .store_plane
.passthrough:
    STA.w !BattleMsg_TextTiles,X ; store tile unchanged
    LDA.b #!BattleUI_TileBlank  ; nothing above
.store_plane:
    STA.w !BattleMsg_TextTopTiles,X ; upper-row tile
    INX
    CPX.w #!BattleMsg_TextLen   ; processed all 16 chars?
    BNE .char_loop
.done:
    RTS

; ============================================================
; Trig / Geometry Cluster ($C1:01F9–$C1:0298)
; ============================================================

; $C1:01F9 — Battle_SinLookup (41 bytes, $01F9–$0221)
; Scaled sine: returns (sin(A) × !Battle_SinScale) >> 8 in A.
; A (8-bit) is an angle, 256 units per turn. !BattleRom_SineTable holds
; |sin| for 1024 steps per turn, one byte each ($00 at +$000 and +$200,
; $FF at +$100 and +$300); angle × 4 picks every fourth entry, and the
; value is negated for the second half turn (table offset $200 and up). The signed sine goes to !Battle_MulFactor16, the scale to
; !Battle_MulFactor8, and Battle_Mul8x16 multiplies them.
; Entry: M=1 (8-bit A), X=0 (16-bit); angle in A
; Exit:  M=1 (8-bit A); A = !Battle_MulProduct+1 (product >> 8)
; Calls: Battle_Mul8x16
!Battle_SinScale = !Battle_Mul8B          ; 1 B in: scale multiplied into the sine (Mul8's B slot)
org $C101F9
Battle_SinLookup:
    REP #$20                    ; A → 16-bit
    ASL A
    ASL A
    AND.w #!Battle_SineIndexMask ; angle × 4, wrapped to the 1024-entry table
    TAX                         ; X = table byte index
    LDA.l !BattleRom_SineTable,X
    AND.w #!Battle_LowByteMask  ; keep this entry (the 16-bit read also took the next)
    CPX.w #!Battle_SineHalfTable ; second half turn → negative
    BCC .first_half
    EOR.w #!Battle_Invert16
    INC A                       ; two's complement negate (EOR + INC)
.first_half:
    STA.b !Battle_MulFactor16   ; signed sine (16-bit store)
    LDA.b !Battle_SinScale      ; (16-bit read: also the next byte)
    AND.w #!Battle_LowByteMask  ; zero-extend the scale byte
    STA.b !Battle_MulFactor8    ; (16-bit store: also clears $A6)
    SEP #$20                    ; A → 8-bit
    JSR Battle_Mul8x16          ; Factor8 × Factor16 → 24-bit product
    LDA.b !Battle_MulProduct+1  ; return product >> 8
    RTS

; $C1:0222 — Battle_CalcAngle (119 bytes, $0222–$0298)
; Direction angle between two screen points (256 units per turn).
; Computes dx = OriginX − PointX and dy = OriginY − PointY as signed
; 16-bit values, takes |dx| and |dy|, looks up a base angle in
; !BattleRom_AngleTable at index (|dy| & ~7) × 4 + (|dx| >> 3), then
; places it in the right quadrant from the signs of dx and dy.
; Entry: M=1 (8-bit A), X=0 (16-bit); !Battle_GeoOriginX/Y, !Battle_GeoPointX/Y
; Exit:  M=1 (8-bit A); angle in A and !Battle_GeoAngle
; No JSR/JSL calls.
org $C10222
Battle_CalcAngle:
    ; --- Phase 1: dx = OriginX − PointX, dy = OriginY − PointY (16-bit) ---
    SEC
    LDA.b !Battle_GeoOriginX
    SBC.b !Battle_GeoPointX
    STA.b !Battle_GeoDeltaX
    LDA #$00
    SBC #$00                    ; propagate borrow → high byte (0 or $FF)
    STA.b !Battle_GeoDeltaX+1
    SEC
    LDA.b !Battle_GeoOriginY
    SBC.b !Battle_GeoPointY
    STA.b !Battle_GeoDeltaY
    LDA #$00
    SBC #$00                    ; propagate borrow
    STA.b !Battle_GeoDeltaY+1
    ; --- Phase 2: absolute values ---
    LDA.b !Battle_GeoDeltaX
    EOR.b !Battle_GeoDeltaX+1   ; XOR sign byte: if negative, flips bits
    SEC
    SBC.b !Battle_GeoDeltaX+1   ; subtract sign byte: two's complement abs
    STA.b !Battle_GeoAbsDeltaX
    STZ.b !Battle_GeoAbsDeltaX+1
    LDA.b !Battle_GeoDeltaY
    EOR.b !Battle_GeoDeltaY+1
    SEC
    SBC.b !Battle_GeoDeltaY+1
    STA.b !Battle_GeoAbsDeltaY
    STZ.b !Battle_GeoAbsDeltaY+1
    ; --- Phase 3: angle table index ---
    REP #$20                    ; A → 16-bit
    LDA.b !Battle_GeoAbsDeltaX  ; 16-bit |ΔX|
    LSR A
    LSR A
    LSR A                       ; |ΔX| >> 3
    STA.b !Battle_GeoTmp
    LDA.b !Battle_GeoAbsDeltaY  ; 16-bit |ΔY|
    AND.w #!Battle_GeoRowMask   ; mask lower 3 bits (align to 8)
    ASL A
    ASL A                       ; |ΔY| & $FFF8, × 4
    CLC
    ADC.b !Battle_GeoTmp        ; + (|ΔX| >> 3)
    STA.b !Battle_GeoAngleIndex
    ASL A                       ; × 2 (dead: X is reloaded from GeoAngleIndex below)
    TAX
    TDC                         ; A = 0
    SEP #$20                    ; A → 8-bit
    LDX.b !Battle_GeoAngleIndex ; X = table index (overrides dead TAX above)
    LDA.l !BattleRom_AngleTable,X ; base angle
    STA.b !Battle_GeoAngle
    ; --- Phase 4: quadrant adjustment of angle ---
    LDA.b !Battle_GeoDeltaX+1   ; check sign of ΔX (high byte)
    BMI .dx_negative            ; ΔX < 0
    LDA.b !Battle_GeoDeltaY+1   ; check sign of ΔY (high byte)
    BMI .dy_negative            ; ΔX ≥ 0, ΔY < 0
    ; ΔX ≥ 0, ΔY ≥ 0 → angle = $80 + base
    CLC
    LDA.b #!Battle_AngleHalfTurn
    ADC.b !Battle_GeoAngle
    STA.b !Battle_GeoAngle
    RTS
.dy_negative:                   ; ΔX ≥ 0, ΔY < 0 → angle = $80 − base
    SEC
    LDA.b #!Battle_AngleHalfTurn
    SBC.b !Battle_GeoAngle
    STA.b !Battle_GeoAngle
    RTS
.dx_negative:
    LDA.b !Battle_GeoDeltaY+1   ; check sign of ΔY
    BMI .both_negative          ; ΔX < 0, ΔY < 0
    ; ΔX < 0, ΔY ≥ 0 → angle = 0 − base (negate)
    TDC                         ; A = 0
    SEC
    SBC.b !Battle_GeoAngle
    STA.b !Battle_GeoAngle
.both_negative:                 ; ΔX < 0, ΔY < 0 → angle = base, unchanged
    LDA.b !Battle_GeoAngle
    RTS

; ============================================================
; Status-Bar UI Cluster ($C1:0299–$C1:05A6)
; ============================================================

; $C1:0299 — BattleUI_BuildStatusBarFrame (782 bytes, $0299–$05A6)
; Rebuilds the battle status-bar map (BattleUI_StatusTile, $0CC0):
;   1. Clears 192 entries (tile 0, palette 2).
;   2. Writes the "HP"/"MP" header glyphs where the current layout
;      (!BattleUI_GaugeLayout) puts them: 0 = name, HP/MaxHP, MP;
;      1 = HP, MP, name, ATB gauge; 2 = name, HP, MP, ATB gauge. Layouts
;      1 and 2 differ only in which side of HP/MP the name is on.
;   3. For each present PC (!Battler_Present, slots 0-2), from the line's
;      name cell (!BattleUI_PanelDest):
;      - the 10 name tiles from !Pc_NameTiles: 5 on the line, the next 5
;        on the tilemap row above it;
;      - HP digits (BattlerStats.CurHp; palette 3 when HP is 0, or when
;        it is at most MaxHP/8 and !BattleUI_UnkA110 is non-zero, see
;        !BattleUI_LowHp);
;      - layout 0: a separator tile and the MaxHP digits;
;      - MP digits (two digits); layouts 1/2: the end caps (cols 25 and
;        30) and the ATB gauge between them, cols 26-29
;        (BattleUI_DrawSlotGaugeBar).
;   4. For each used enemy-name line (!Enemy_NameLineUsed, 0-2): the 11
;      lower-row and 11 upper-row tiles from !Enemy_NameTiles.
;   5. If PCs are waiting for a command (!BattleMenu_ReadyCount):
;      - while targeting from a submenu (!BattleMenu_ReturnSubmenu != 0)
;        and the first selected target differs from !BattleUI_UnkA0D7:
;        force a window rebuild and tail-jump to
;        BattleUI_HighlightPcName with that target's slot;
;      - else, on the main menu only: latch !BattleUI_OtherReady, make
;        sure !BattleMenu_RosterIdx names a roster entry (first valid one
;        otherwise), set !BattleMenu_ActivePc, redraw every roster PC's
;        command list (BattleMenu_DrawCommandList) and the command-window
;        frames (BattleMenu_DrawCommandWindowFrames).
; Entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=0, DB=$7E
; Exit:  M=1; X, Y clobbered; DP $80/$84/$86/$8E/$A2 used as temporaries
; Calls: Battle_ShiftRight3, BattleMsg_FormatNumberDigits, BattleMsg_BlankLeadingZeros,
;        BattleMsg_FormatTwoDigits, BattleUI_DrawSlotGaugeBar, BattleUI_HighlightPcName,
;        BattleMenu_DrawCommandList, BattleMenu_DrawCommandWindowFrames
; Direct-page roles:
!BattleUI_Slot = !BattleTmp_80            ; 1-2 B: PC slot (or enemy-name line) being drawn; shared by the status-bar routines
!BattleUI_PanelDest = !BattleTmp_84       ; 2 B: map offset of the current line's name cell
!BattleUI_CharsLeft = !BattleTmp_8E       ; 1 B: name tiles left to copy
!BattleUI_StatsOffset = !BattleTmp_A2     ; 2 B: BattlerStats offset of the PC being drawn
!BattleUI_RefreshSlot = !BattleTmp_86     ; 1-2 B: PC slot of the command-list loop
org $C10299
BattleUI_BuildStatusBarFrame:
    TDC
    TAX
    TAY
.init_loop:
    TDC                             ; tile byte = 0
    STA.w BattleUI_StatusTile(0,0),Y
    LDA.b #!BattleUI_AttrPal2
    STA.w BattleUI_StatusAttr(0,0),Y
    INY
    INY
    INX
    CPX.w #!BattleUI_StatusEntries  ; all entries cleared?
    BNE .init_loop
    ; --- "HP" / "MP" header glyphs for the current layout ---
    LDA.w !BattleUI_GaugeLayout
    BNE .gauge_not0
    ; Layout 0: HP + MaxHP + MP
    LDA.b #!BattleUI_TileH
    STA.w BattleUI_StatusTile(0,20)
    LDA.b #!BattleUI_TileP
    STA.w BattleUI_StatusTile(0,21)
    STA.w BattleUI_StatusTile(0,30)
    LDA.b #!BattleUI_TileM
    STA.w BattleUI_StatusTile(0,29)
    BRA .gauge_dest_sel
.gauge_not0:
    DEC A
    BNE .gauge_type2
    ; Layout 1: HP, MP, name, ATB gauge
    LDA.b #!BattleUI_TileH
    STA.w BattleUI_StatusTile(0,13)
    LDA.b #!BattleUI_TileP
    STA.w BattleUI_StatusTile(0,14)
    STA.w BattleUI_StatusTile(0,18)
    LDA.b #!BattleUI_TileM
    STA.w BattleUI_StatusTile(0,17)
    BRA .gauge_dest_sel
.gauge_type2:
    ; Layout 2: name, HP, MP, ATB gauge
    LDA.b #!BattleUI_TileH
    STA.w BattleUI_StatusTile(0,19)
    LDA.b #!BattleUI_TileP
    STA.w BattleUI_StatusTile(0,20)
    STA.w BattleUI_StatusTile(0,24)
    LDA.b #!BattleUI_TileM
    STA.w BattleUI_StatusTile(0,23)
.gauge_dest_sel:
    ; First name cell: layout 1 → PanelDestL1, layouts 0/2 → PanelDestL02
    LDA.w !BattleUI_GaugeLayout
    BEQ .dest_l02
    DEC A
    BNE .dest_l02
    LDX.w #!BattleUI_PanelDestL1
    BRA .set_dest_base
.dest_l02:
    LDX.w #!BattleUI_PanelDestL02
.set_dest_base:
    STX.b !BattleUI_PanelDest
    TDC
    TAX
    STX.b !BattleUI_Slot            ; PC slot 0
    ; --- BattleUI_DrawPcNamePanel ---
    ; Writes one PC slot's name, HP/MP and ATB gauge into the status map. Loop body:
    ; BattleUI_NextNamePanel advances PanelDest/Slot and JMPs back here.
BattleUI_DrawPcNamePanel:
    LDY.b !BattleUI_PanelDest       ; Y = name cell
    LDX.b !BattleUI_Slot
    LDA.w !Battler_Present,X
    BNE .pc_present
    JMP.w BattleUI_NextNamePanel    ; no PC in this slot → next slot
.pc_present:
    LDA.l !BattleRom_PcNameOffset,X
    TAX                             ; X = offset into !Pc_NameTiles
    LDA.b #!Pc_NameRowLen
    STA.b !BattleUI_CharsLeft
.name_row1_loop:                    ; first 5 tiles on the name line
    LDA.w !Pc_NameTiles,X
    STA.w BattleUI_StatusTile(0,0),Y
    LDA.b #!BattleUI_AttrPal3       ; names use palette 3
    STA.w BattleUI_StatusAttr(0,0),Y
    INY
    INY
    INX
    DEC.b !BattleUI_CharsLeft
    BNE .name_row1_loop
    REP #$20                        ; M=0 (16-bit A)
    SEC
    LDA.b !BattleUI_PanelDest       ; (16-bit DP load)
    SBC.w #!BattleUI_MapRowBytes    ; the tilemap row above the name line
    TAY
    TDC
    SEP #$20                        ; M=1
    LDA.b #!Pc_NameRowLen
    STA.b !BattleUI_CharsLeft
.name_row2_loop:                    ; next 5 tiles (X runs on) on the row above
    LDA.w !Pc_NameTiles,X
    STA.w BattleUI_StatusTile(0,0),Y
    LDA.b #!BattleUI_AttrPal3
    STA.w BattleUI_StatusAttr(0,0),Y
    INY
    INY
    INX
    DEC.b !BattleUI_CharsLeft
    BNE .name_row2_loop
    ; --- Low-HP flag and HP digit formatting ---
    STZ.w !BattleUI_LowHp
    REP #$20                        ; M=0 (16-bit A)
    LDA.b !BattleUI_Slot            ; PC slot (zero-extended 16-bit)
    ASL A
    TAX                             ; X = slot × 2
    LDA.l !BattleRom_StatsOffset,X
    STA.b !BattleUI_StatsOffset     ; BattlerStats offset of this PC
    TAX
    LDA.w BattlerStats.CurHp,X      ; (16-bit)
    STA.w !BattleMsg_NumValue       ; → number formatter
    BEQ .lhp_set                    ; HP == 0 → low
    LDA.w BattlerStats.MaxHp,X      ; (16-bit)
    JSR Battle_ShiftRight3          ; MaxHP >> 3 (M=0: 16-bit shifts)
    CMP.w !BattleMsg_NumValue       ; MaxHP/8 vs HP
    BEQ .lhp_at_most_eighth         ; (redundant: equal falls through below anyway)
    BCC .lhp_ok                     ; MaxHP/8 < HP → not low
.lhp_at_most_eighth:                ; 0 < HP <= MaxHP/8: !BattleUI_UnkA110 decides
    LDA.w !BattleUI_UnkA110
    BEQ .lhp_ok
.lhp_set:
    INC.w !BattleUI_LowHp
.lhp_ok:
    ; --- HP digit cell for the layout ---
    LDA.w !BattleUI_GaugeLayout     ; (M=0: 16-bit read)
    BNE .hp_yoff_not0
    CLC
    LDA.b !BattleUI_PanelDest
    ADC.w #!BattleUI_HpOffsetL0     ; layout 0: after the name
    BRA .hp_fmt
.hp_yoff_not0:
    DEC A
    BNE .hp_yoff_type2
    SEC
    LDA.b !BattleUI_PanelDest
    SBC.w #!BattleUI_HpBackL1       ; layout 1: before the name
    BRA .hp_fmt
.hp_yoff_type2:
    CLC
    LDA.b !BattleUI_PanelDest
    ADC.w #!BattleUI_HpOffsetL2     ; layout 2: after the name
.hp_fmt:
    TAY
    JSR BattleMsg_FormatNumberDigits ; exits M=1
    JSR BattleMsg_BlankLeadingZeros
    LDA.w !BattleMsg_Digit100       ; (M=1)
    STA.w BattleUI_StatusTile(0,0),Y
    LDA.w !BattleMsg_Digit10
    STA.w BattleUI_StatusTile(0,1),Y
    LDA.w !BattleMsg_Digit1
    STA.w BattleUI_StatusTile(0,2),Y
    LDX.w #!BattleUI_AttrPal2
    LDA.w !BattleUI_LowHp
    BEQ .hp_attr_ok
    LDX.w #!BattleUI_AttrPal3       ; low HP
.hp_attr_ok:
    TXA
    STA.w BattleUI_StatusAttr(0,0),Y
    STA.w BattleUI_StatusAttr(0,1),Y
    STA.w BattleUI_StatusAttr(0,2),Y
    STA.w BattleUI_StatusAttr(0,3),Y
    LDA.w !BattleUI_GaugeLayout
    BNE .hp_bar_not0
    LDA.b #!BattleUI_TileHpSlash    ; layout 0: separator before MaxHP
    STA.w BattleUI_StatusTile(0,3),Y
    BRA .maxhp_fmt
.hp_bar_not0:
    LDA.b #!BattleUI_TileSpacer     ; other layouts
    STA.w BattleUI_StatusTile(0,3),Y
    BRA .mp_display                 ; no MaxHP
.maxhp_fmt:
    REP #$20                        ; M=0
    LDX.b !BattleUI_StatsOffset     ; (16-bit DP load)
    LDA.w BattlerStats.MaxHp,X      ; (16-bit)
    STA.w !BattleMsg_NumValue
    CLC
    LDA.b !BattleUI_PanelDest
    ADC.w #!BattleUI_MaxHpOffsetL0
    TAY
    JSR BattleMsg_FormatNumberDigits ; exits M=1
    JSR BattleMsg_BlankLeadingZeros
    LDA.w !BattleMsg_Digit100
    STA.w BattleUI_StatusTile(0,0),Y
    LDA.w !BattleMsg_Digit10
    STA.w BattleUI_StatusTile(0,1),Y
    LDA.w !BattleMsg_Digit1
    STA.w BattleUI_StatusTile(0,2),Y
    LDX.w #!BattleUI_AttrPal2
    LDA.w !BattleUI_LowHp
    BEQ .maxhp_attr_ok
    LDX.w #!BattleUI_AttrPal3
.maxhp_attr_ok:
    TXA
    STA.w BattleUI_StatusAttr(0,0),Y
    STA.w BattleUI_StatusAttr(0,1),Y
    STA.w BattleUI_StatusAttr(0,2),Y
.mp_display:
    REP #$20                        ; M=0
    LDX.b !BattleUI_StatsOffset
    LDA.w BattlerStats.CurMp,X      ; (16-bit)
    STA.w !BattleMsg_NumValue
    LDA.w !BattleUI_GaugeLayout     ; (M=0: 16-bit read)
    BNE .mp_yoff_not0
    CLC
    LDA.b !BattleUI_PanelDest
    ADC.w #!BattleUI_MpOffsetL0     ; layout 0
    BRA .mp_fmt
.mp_yoff_not0:
    DEC A
    BNE .mp_yoff_type2
    SEC
    LDA.b !BattleUI_PanelDest
    SBC.w #!BattleUI_MpBackL1       ; layout 1: before the name
    BRA .mp_fmt
.mp_yoff_type2:
    CLC
    LDA.b !BattleUI_PanelDest
    ADC.w #!BattleUI_MpOffsetL2     ; layout 2
.mp_fmt:
    TAY
    JSR BattleMsg_FormatTwoDigits   ; exits M=1
    LDA.w !BattleUI_GaugeLayout
    BNE .mp_blanking
    JSR BattleMsg_BlankLeadingZeros
    BRA .mp_place_0
.mp_blanking:
    JSR BattleMsg_BlankLeadingZeros
    LDA.w !BattleMsg_Digit10
    STA.w BattleUI_StatusTile(0,0),Y
    LDA.w !BattleMsg_Digit1
    STA.w BattleUI_StatusTile(0,1),Y
    LDX.w #!BattleUI_AttrPal2
    LDA.w !BattleUI_LowHp
    BEQ .mp_attr_ok
    LDX.w #!BattleUI_AttrPal3
.mp_attr_ok:
    TXA
    STA.w BattleUI_StatusAttr(0,0),Y
    STA.w BattleUI_StatusAttr(0,1),Y
    BRA .gauge_caps
.mp_place_0:                        ; layout 0: MP digits one cell further right
    LDA.w !BattleMsg_Digit10
    STA.w BattleUI_StatusTile(0,1),Y
    LDA.w !BattleMsg_Digit1
    STA.w BattleUI_StatusTile(0,2),Y
    LDX.w #!BattleUI_AttrPal2
    LDA.w !BattleUI_LowHp
    BEQ .mp_attr0_ok
    LDX.w #!BattleUI_AttrPal3
.mp_attr0_ok:
    TXA
    STA.w BattleUI_StatusAttr(0,1),Y
    STA.w BattleUI_StatusAttr(0,2),Y
.gauge_caps:
    LDA.w !BattleUI_GaugeLayout
    BEQ BattleUI_NextNamePanel      ; layout 0: no ATB gauge
    REP #$20                        ; M=0
    DEC A
    BNE .caps_layout2
    CLC
    LDA.b !BattleUI_PanelDest
    ADC.w #!BattleUI_GaugeCapOffsetL1     ; layout 1
    BRA .caps_draw
.caps_layout2:
    CLC
    LDA.b !BattleUI_PanelDest
    ADC.w #!BattleUI_GaugeCapOffsetL2     ; layout 2
.caps_draw:
    TAY
    TDC
    SEP #$20                        ; M=1
    LDA.b #!BattleUI_TileGaugeCapL
    STA.w BattleUI_StatusTile(0,0),Y
    LDA.b #!BattleUI_TileGaugeCapR
    STA.w BattleUI_StatusTile(0,5),Y
    LDA.b #!BattleUI_AttrPal2
    STA.w BattleUI_StatusAttr(0,0),Y
    STA.w BattleUI_StatusAttr(0,5),Y
    JSR BattleUI_DrawSlotGaugeBar
    BRA BattleUI_NextNamePanel
    ; --- Loop tail: next PC slot, then the enemy-name lines ---
BattleUI_NextNamePanel:
    REP #$21                        ; M=0, C=0
    LDA.b !BattleUI_PanelDest
    ADC.w #!BattleUI_PanelStride    ; next line
    STA.b !BattleUI_PanelDest
    TDC
    SEP #$20                        ; M=1
    INC.b !BattleUI_Slot
    LDA.b !BattleUI_Slot
    CMP.b #!Battle_NumPcSlots
    BEQ .enemy_section
    JMP.w BattleUI_DrawPcNamePanel
.enemy_section:
    ; Enemy-name lines 0-2 (!Enemy_NameLineUsed / !Enemy_NameTiles)
    LDX.w #!BattleUI_EnemyPanelDest
    STX.b !BattleUI_PanelDest
    TDC
    TAX
    STX.b !BattleUI_Slot
.enemy_loop:
    LDX.b !BattleUI_Slot
    LDA.w !Enemy_NameLineUsed,X
    BEQ .enemy_next
    ; name record offset = line × 24 (line × 8 + line × 16)
    LDA.b !BattleUI_Slot
    ASL A
    ASL A
    ASL A                           ; line × 8
    STA.b !BattleTmp_8E
    ASL A                           ; line × 16
    CLC
    ADC.b !BattleTmp_8E             ; line × 24
    TAX
    LDA.b #!Enemy_NameLen
    STA.b !BattleUI_CharsLeft
    LDY.b !BattleUI_PanelDest
.ename_row1_loop:                   ; 11 tiles on the name line
    LDA.w !Enemy_NameTiles,X
    STA.w BattleUI_StatusTile(0,0),Y
    LDA.b #!BattleUI_AttrPal2
    STA.w BattleUI_StatusAttr(0,0),Y
    INY
    INY
    INX
    DEC.b !BattleUI_CharsLeft
    BNE .ename_row1_loop
    REP #$20                        ; M=0
    SEC
    LDA.b !BattleUI_PanelDest
    SBC.w #!BattleUI_MapRowBytes    ; the row above
    TAY
    TDC
    SEP #$20                        ; M=1
    INX                             ; skip the gap byte between the two rows
    LDA.b #!Enemy_NameLen
    STA.b !BattleUI_CharsLeft
.ename_row2_loop:                   ; next 11 tiles on the row above
    LDA.w !Enemy_NameTiles,X
    STA.w BattleUI_StatusTile(0,0),Y
    LDA.b #!BattleUI_AttrPal2
    STA.w BattleUI_StatusAttr(0,0),Y
    INY
    INY
    INX
    DEC.b !BattleUI_CharsLeft
    BNE .ename_row2_loop
    REP #$21                        ; M=0, C=0
    LDA.b !BattleUI_PanelDest
    ADC.w #!BattleUI_PanelStride    ; next line
    STA.b !BattleUI_PanelDest
    TDC
    SEP #$20                        ; M=1
.enemy_next:
    INC.b !BattleUI_Slot
    LDA.b !BattleUI_Slot
    CMP.b #!Enemy_NameLines
    BNE .enemy_loop
    ; --- Command windows of the PCs waiting for a command ---
    LDA.w !BattleMenu_ReadyCount
    BEQ .buildbar_done              ; no PC waiting → done
    LDA.w !BattleMenu_ReturnSubmenu
    BEQ .check_slot_state           ; not targeting from a submenu
    LDA.w !BattleTgt_Selected
    CMP.w !BattleUI_UnkA0D7
    BEQ .buildbar_done              ; same first target → done
    LDA.b #!BattleMenu_RosterRedraw
    STA.w !BattleMenu_RosterIdxDrawn
    LDA.w !BattleTgt_Selected
    JMP.w BattleUI_HighlightPcName
.check_slot_state:
    LDA.w !BattleMenu_Submenu
    BEQ .do_slot_state
    RTS                             ; a submenu is open → leave the windows
.do_slot_state:
    LDA.w !BattleMenu_ReadyCount
    DEC A
    STA.w !BattleUI_OtherReady
    LDA.w !BattleMenu_RosterIdx
    TAX
    LDA.w !BattleMenu_Roster,X
    BPL .slot_search_done           ; entry valid → use it
    TDC
    TAX
.find_valid_slot:
    LDA.w !BattleMenu_Roster,X
    BPL .found_slot
    INX
    BRA .find_valid_slot
.found_slot:
    PHA
    TXA
    STA.w !BattleMenu_RosterIdx
    PLA
.slot_search_done:
    STA.w !BattleMenu_ActivePc
    TDC
    TAX
    STX.b !BattleUI_RefreshSlot
.slot_refresh_loop:
    LDX.b !BattleUI_RefreshSlot
    LDA.w !BattleMenu_Roster,X
    BMI .slot_skip
    JSR BattleMenu_DrawCommandList
.slot_skip:
    INC.b !BattleUI_RefreshSlot
    LDA.b !BattleUI_RefreshSlot
    CMP.b #!Battle_NumPcSlots
    BNE .slot_refresh_loop
    JSR BattleMenu_DrawCommandWindowFrames
.buildbar_done:
    RTS

; ============================================================
; BattleUI_UpdateNextPcPanel ($C1:05A7–$C1:06EF, 329 bytes)
; Per-frame peer of BattleUI_BuildStatusBarFrame: refreshes one PC's
; HP/MP digits per call (round robin through !BattleUI_NextPanelSlot),
; then redraws every present PC's ATB gauge (layouts 1/2).
; Logic:
;   1. The digit refresh is skipped (straight to the gauges) only when
;      PC slot 2 is in the roster, !BattleUI_ForceDigitRefresh is clear
;      and the layout is 1; every other case refreshes.
;   2. Advance !BattleUI_NextPanelSlot (wrap at 3); stop if no PC there.
;   3. HP cell from !BattleRom_HpCellL0/L1/L2 by layout.
;   4. HP digits, palette 3 when low (same test as BuildStatusBarFrame);
;      layout 0 also recolours the three MaxHP cells after them.
;   5. MP digits at HP cell + !BattleUI_MpCellL0 / L12.
;   6. Layouts 1/2: ATB gauges for all present PCs (BattleUI_DrawAtbGauges).
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0, DB=$7E
; Exit:  M=1; X, Y clobbered; DP $80/$86/$A2, !BattleUI_LowHp and
;        !BattleMsg_NumValue used as temporaries
; Calls: Battle_ShiftRight3, BattleMsg_FormatNumberDigits,
;        BattleMsg_BlankLeadingZeros, BattleMsg_FormatTwoDigits, BattleUI_DrawSlotGaugeBar
; Sub-entry: BattleUI_DrawAtbGauges ($06DB) — X = first PC slot; redraw the
;        ATB gauges from there to slot 2
!BattleUI_PanelBase = !BattleTmp_86      ; 2 B: map offset of the PC's HP cell
org $C105A7
BattleUI_UpdateNextPcPanel:
    LDA.w !BattleMenu_Roster+2      ; PC slot 2 in the roster?
    BMI .advance_panel              ; no → refresh digits
    LDA.w !BattleUI_ForceDigitRefresh
    BNE .advance_panel              ; forced → refresh digits
    LDA.w !BattleUI_GaugeLayout
    BEQ .advance_panel              ; layout 0 → refresh digits
    DEC A                           ; layout 1 → A=0; layout 2 → A=1
    BNE .advance_panel              ; layout 2 → refresh digits
    JMP .atb_gauges                 ; layout 1 → gauges only
.advance_panel:
    INC.w !BattleUI_NextPanelSlot   ; round robin 0-2
    LDA.w !BattleUI_NextPanelSlot
    CMP.b #!Battle_NumPcSlots
    BCC .slot_ok
    STZ.w !BattleUI_NextPanelSlot   ; wrap to 0
.slot_ok:
    LDA.w !BattleUI_NextPanelSlot
    TAX
    STX.b !BattleUI_Slot            ; (16-bit store)
    LDA.w !Battler_Present,X
    BNE .slot_present
    JMP BattleUI_UpdateNextPcPanel_Exit ; no PC in this slot
.slot_present:
    REP #$21                        ; M=0, C=0
    LDA.b !BattleUI_Slot            ; (16-bit DP load)
    ASL
    TAX                             ; X = slot * 2
    LDA.w !BattleUI_GaugeLayout     ; (16-bit read)
    BNE .type_not0_a
    LDA.l !BattleRom_HpCellL0,X     ; layout 0
    BRA .got_base_y
.type_not0_a:
    DEC A
    BNE .type_not1_a
    LDA.l !BattleRom_HpCellL1,X     ; layout 1
    BRA .got_base_y
.type_not1_a:
    LDA.l !BattleRom_HpCellL2,X     ; layout 2
.got_base_y:
    TAY
    STY.b !BattleUI_PanelBase       ; HP cell (16-bit)
    TDC
    SEP #$20                        ; M=1
    STZ.w !BattleUI_LowHp
    REP #$20                        ; M=0
    LDA.b !BattleUI_Slot
    ASL
    TAX                             ; X = slot * 2
    LDA.l !BattleRom_StatsOffset,X
    STA.b !BattleUI_StatsOffset     ; BattlerStats offset (16-bit)
    TAX
    LDA.w BattlerStats.CurHp,X      ; (16-bit)
    STA.w !BattleMsg_NumValue
    BEQ .set_low_hp                 ; HP == 0 → low
    LDA.w BattlerStats.MaxHp,X      ; (16-bit)
    JSR Battle_ShiftRight3          ; MaxHP >> 3
    CMP.w !BattleMsg_NumValue       ; MaxHP/8 vs HP
    BEQ .hp_at_most_eighth          ; (redundant: equal falls through below anyway)
    BCC .hp_ok                      ; MaxHP/8 < HP → not low
.hp_at_most_eighth:                 ; 0 < HP <= MaxHP/8: !BattleUI_UnkA110 decides
    LDA.w !BattleUI_UnkA110
    BEQ .hp_ok
.set_low_hp:
    INC.w !BattleUI_LowHp           ; (M=0 → 16-bit INC)
.hp_ok:
    JSR BattleMsg_FormatNumberDigits ; HP digits (exits M=1)
    JSR BattleMsg_BlankLeadingZeros
    LDA.w !BattleMsg_Digit100
    STA.w BattleUI_StatusTile(0,0),Y
    LDA.w !BattleMsg_Digit10
    STA.w BattleUI_StatusTile(0,1),Y
    LDA.w !BattleMsg_Digit1
    STA.w BattleUI_StatusTile(0,2),Y
    LDX.w #!BattleUI_AttrPal2
    LDA.w !BattleUI_LowHp
    BEQ .normal_attr
    LDX.w #!BattleUI_AttrPal3       ; low HP
.normal_attr:
    TXA
    STA.w BattleUI_StatusAttr(0,0),Y
    STA.w BattleUI_StatusAttr(0,1),Y
    STA.w BattleUI_StatusAttr(0,2),Y
    STA.w BattleUI_StatusAttr(0,3),Y
    LDA.w !BattleUI_GaugeLayout
    BNE .skip_type0_hp_extra        ; layouts 1/2: no MaxHP
    TXA                             ; layout 0: recolour the MaxHP cells too
    STA.w BattleUI_StatusAttr(0,4),Y
    STA.w BattleUI_StatusAttr(0,5),Y
    STA.w BattleUI_StatusAttr(0,6),Y
.skip_type0_hp_extra:
    REP #$20                        ; M=0
    LDX.b !BattleUI_StatsOffset     ; (16-bit DP load)
    LDA.w BattlerStats.CurMp,X      ; (16-bit)
    STA.w !BattleMsg_NumValue
    LDA.w !BattleUI_GaugeLayout     ; (16-bit read)
    BNE .mp_offset_short
    CLC
    LDA.b !BattleUI_PanelBase
    ADC.w #!BattleUI_MpCellL0
    TAY
    BRA .mp_dest_done
.mp_offset_short:
    CLC
    LDA.b !BattleUI_PanelBase
    ADC.w #!BattleUI_MpCellL12
.mp_dest_done:
    TAY
    JSR BattleMsg_FormatTwoDigits   ; MP digits (exits M=1)
    LDA.w !BattleUI_GaugeLayout
    BNE .mp_not_type0
    JSR BattleMsg_BlankLeadingZeros
    BRA .gauge0_mp_path
.mp_not_type0:
    JSR BattleMsg_BlankLeadingZeros
    LDA.w !BattleMsg_Digit10
    STA.w BattleUI_StatusTile(0,0),Y
    LDA.w !BattleMsg_Digit1
    STA.w BattleUI_StatusTile(0,1),Y
    LDX.w #!BattleUI_AttrPal2
    LDA.w !BattleUI_LowHp
    BEQ .mp_normal_attr
    LDX.w #!BattleUI_AttrPal3
.mp_normal_attr:
    TXA
    STA.w BattleUI_StatusAttr(0,0),Y
    STA.w BattleUI_StatusAttr(0,1),Y
    BRA .atb_gauges
.gauge0_mp_path:
    LDA.w !BattleMsg_Digit10
    STA.w BattleUI_StatusTile(0,1),Y
    LDA.w !BattleMsg_Digit1
    STA.w BattleUI_StatusTile(0,2),Y
    LDX.w #!BattleUI_AttrPal2
    LDA.w !BattleUI_LowHp
    BEQ .gauge0_normal_attr
    LDX.w #!BattleUI_AttrPal3
.gauge0_normal_attr:
    TXA
    STA.w BattleUI_StatusAttr(0,1),Y
    STA.w BattleUI_StatusAttr(0,2),Y
.atb_gauges:
    LDA.w !BattleUI_GaugeLayout
    BEQ BattleUI_UpdateNextPcPanel_Exit ; layout 0 has no ATB gauges
    TDC
    TAX                             ; X = 0 (first slot)
BattleUI_DrawAtbGauges:
    STX.b !BattleUI_Slot
.gauge_loop:
    LDX.b !BattleUI_Slot
    LDA.w !Battler_Present,X
    BEQ .next_slot
    JSR BattleUI_DrawSlotGaugeBar
.next_slot:
    INC.b !BattleUI_Slot
    LDA.b !BattleUI_Slot
    CMP.b #!Battle_NumPcSlots
    BNE .gauge_loop
BattleUI_UpdateNextPcPanel_Exit:
    RTS

; ============================================================
; Status-Bar UI Callees ($C1:06F0–$C1:095C)
; Called by BattleUI_BuildStatusBarFrame and its peers: the ATB gauge,
; the per-PC command windows and the name highlight.
; ============================================================

; $C1:06F0 — BattleUI_DrawSlotGaugeBar (149 bytes, $06F0–$0784)
; Draw the 4-tile ATB gauge of PC slot !BattleUI_Slot into the status map
; at BattleRom_HpCellL1[slot] + !BattleUI_GaugeCellOffset.
;   fill = (AtbCur * 256 / AtbMax) >> 3: 0-32 units of 32 (the quotient
;   is 256 when AtbCur = AtbMax, so a full gauge gives 32)
;   rest = 32 - fill; rest / 8 tiles get TileGauge8, then one tile gets
;   TileGauge0 + (rest mod 8); the remaining tiles keep TileGauge0.
; So the tiles drawn track the part of the gauge still to fill; what the
; tiles look like depends on the graphics, which were not checked.
; Attribute: palette 3 if AtbCur is non-zero, else palette 2.
; Entry: M=1, X=0 (16-bit), !BattleUI_Slot = PC slot (0–2)
; Exit:  M=1; Y = last map offset written; DP $79–$7B, $82/$83/$86,
;        $AD/$AE, $B1–$B7 clobbered
; Calls: Battle_ShiftLeft8, Battle_Divide, Battle_ShiftRight3
; Direct-page roles (!BattleUI_Slot is defined with BuildStatusBarFrame):
!BattleUI_AtbValue = !BattleTmp_AD        ; 2 B: AtbCur zero-extended
!BattleUI_GaugeRest = !BattleTmp_82       ; 1 B: 32 - filled units, then the units left after whole tiles
!BattleUI_GaugeRestTiles = !BattleTmp_83  ; 1 B: whole 8-unit tiles in GaugeRest
!BattleUI_GaugeTmp = !BattleTmp_86        ; 1 B: GaugeRestTiles * 8
org $C106F0
BattleUI_DrawSlotGaugeBar:
    REP #$21                    ; M=0, C=0
    LDA.b !BattleUI_Slot        ; PC slot (16-bit DP load; high byte = 0)
    ASL                         ; × 2 (table index)
    TAX
    LDA.l !BattleRom_HpCellL1,X ; map offset of the slot's HP cell
    ADC.w #!BattleUI_GaugeCellOffset ; gauge starts this far after it
    TAY                         ; Y = map destination
    TDC
    SEP #$20                    ; M=1
    LDX.b !BattleUI_Slot        ; X = slot (16-bit DP load)
    LDA.w !Pc_AtbCur,X
    STA.b !BattleUI_AtbValue
    STZ.b !BattleUI_AtbValue+1
    LDA.w !Pc_AtbMax,X
    STA.b !Battle_DivDivisor
    STZ.b !Battle_DivDivisor+1  ; (high byte not read by Battle_Divide)
    REP #$20                    ; M=0
    LDA.b !BattleUI_AtbValue
    JSR Battle_ShiftLeft8       ; A <<= 8 (× 256) — scale to fixed-point
    STA.b !Battle_DivDividend
    TDC
    SEP #$20                    ; M=1
    JSR Battle_Divide           ; quotient = AtbCur * 256 / AtbMax (0–256)
    REP #$20                    ; M=0
    LDA.b !Battle_DivQuotient   ; (16-bit read)
    JSR Battle_ShiftRight3      ; >> 3 → 0–32 gauge units
    STA.b !Battle_DivQuotient
    TDC
    SEP #$20                    ; M=1
    SEC
    LDA.b #!BattleUI_GaugeUnits
    SBC.b !Battle_DivQuotient   ; units not yet filled
    STA.b !BattleUI_GaugeRest
    LSR
    LSR
    LSR                         ; / 8 = whole tiles
    STA.b !BattleUI_GaugeRestTiles
    ASL
    ASL
    ASL                         ; × 8 = units in those tiles
    STA.b !BattleUI_GaugeTmp
    SEC
    LDA.b !BattleUI_GaugeRest
    SBC.b !BattleUI_GaugeTmp    ; units left over
    STA.b !BattleUI_GaugeRest
    ; Write 4 TileGauge0 tiles at the destination
    LDA.b #!BattleUI_TileGauge0
    STA.w BattleUI_StatusTile(0,0),Y
    STA.w BattleUI_StatusTile(0,1),Y
    STA.w BattleUI_StatusTile(0,2),Y
    STA.w BattleUI_StatusTile(0,3),Y
    LDX.b !BattleUI_Slot
    LDA.w !Pc_AtbCur,X
    BNE .has_atb
    LDA.b #!BattleUI_AttrPal2   ; empty gauge → palette 2
    BRA .set_attr
.has_atb:
    LDA.b #!BattleUI_AttrPal3   ; non-empty gauge → palette 3
.set_attr:
    STA.w BattleUI_StatusAttr(0,0),Y
    STA.w BattleUI_StatusAttr(0,1),Y
    STA.w BattleUI_StatusAttr(0,2),Y
    STA.w BattleUI_StatusAttr(0,3),Y
.full_tile_loop:
    LDA.b !BattleUI_GaugeRestTiles ; whole tiles left
    BEQ .partial_tile
    LDA.b #!BattleUI_TileGauge8
    STA.w BattleUI_StatusTile(0,0),Y
    INY
    INY
    DEC.b !BattleUI_GaugeRestTiles
    BRA .full_tile_loop
.partial_tile:
    CLC
    LDA.b !BattleUI_GaugeRest   ; units left over
    BEQ .done                   ; none → nothing to add
    ADC.b #!BattleUI_TileGauge0 ; TileGauge0 + units
    STA.w BattleUI_StatusTile(0,0),Y
.done:
    RTS

; $C1:0785 — BattleMenu_DrawCommandList (153 bytes, $0785–$081D)
; Draw the command list of PC slot A (6 rows × 7 columns) into the status
; map at offset slot × 12, from one of two ROM tile tables:
;   !BattleRom_CmdListTech  — "Attack", "Tech", "Item" on rows 1/3/5
;   !BattleRom_CmdListCombo — the same with "Comb" (Combo) for "Tech"
; ("Attack" is "Att" plus tile $E8, presumably an "ack" ligature.)
; The Combo list is chosen when !BattleUI_OtherReady (another PC is in the
; roster) and the slot's !Pc_Unk9F25|!Pc_Unk9F28 are non-zero, and then
; either !BattleUI_UnkA117 is zero, all three PCs are in the roster, or
; !BattleUI_UnkA115 names a different PC whose roster entry is negative.
; Attribute: palette 2. The window frame around it is drawn into
; !BattleMenu_WindowMap by BattleMenu_DrawCommandWindowFrames.
; Entry: M=1, X=0 (16-bit), A = PC slot (0–2)
; Exit:  M=1; DP $80-$83 clobbered; X/Y clobbered
; No calls.
; Direct-page roles (!BattleUI_Slot holds the slot until the drawing loops):
!BattleUI_RowsLeft = !BattleTmp_80        ; 1 B: command-list rows left to draw
!BattleUI_ColsLeft = !BattleTmp_81        ; 1 B: columns left in the row
!BattleUI_MapOffset = !BattleTmp_82       ; 2 B: map offset of the current row / window frame
org $C10785
BattleMenu_DrawCommandList:
    STA.b !BattleUI_Slot
    ASL
    ASL                         ; × 4
    STA.b !BattleUI_MapOffset
    ASL                         ; × 8
    CLC
    ADC.b !BattleUI_MapOffset   ; slot × 12
    TAX
    STX.b !BattleUI_MapOffset   ; 16-bit map offset of the list
    LDA.w !BattleUI_OtherReady
    BEQ .tech_list              ; no other PC in the roster → Tech
    LDA.b !BattleUI_Slot
    TAX
    LDA.w !Pc_Unk9F25,X
    ORA.w !Pc_Unk9F28,X
    BEQ .tech_list              ; both zero → Tech
    LDA.w !BattleUI_UnkA117
    BEQ .combo_list             ; zero → Combo
    LDA.w !BattleMenu_ReadyCount
    CMP.b #!Battle_NumPcSlots
    BEQ .combo_list             ; all three PCs in the roster → Combo
    LDA.b !BattleUI_Slot
    CMP.w !BattleUI_UnkA115
    BEQ .tech_list              ; same slot → Tech
    LDX.w !BattleUI_UnkA115
    LDA.w !BattleMenu_Roster,X
    BMI .combo_list             ; that PC not in the roster → Combo

.tech_list:
    TDC
    TAX                         ; X = table index (starts at 0)
    LDA.b #!BattleUI_CmdWindowRows
    STA.b !BattleUI_RowsLeft
.tech_row_start:
    LDA.b #!BattleUI_CmdWindowCols
    STA.b !BattleUI_ColsLeft
    LDY.b !BattleUI_MapOffset   ; Y = current row
.tech_col_loop:
    LDA.l !BattleRom_CmdListTech,X
    STA.w BattleUI_StatusTile(0,0),Y
    LDA.b #!BattleUI_AttrPal2
    STA.w BattleUI_StatusAttr(0,0),Y
    INY
    INY
    INX
    DEC.b !BattleUI_ColsLeft
    BNE .tech_col_loop
    REP #$21                    ; M=0, C=0
    LDA.b !BattleUI_MapOffset
    ADC.w #!BattleUI_MapRowBytes ; next tilemap row
    STA.b !BattleUI_MapOffset
    TDC
    SEP #$20                    ; M=1
    DEC.b !BattleUI_RowsLeft
    BNE .tech_row_start
    BRA .done

.combo_list:
    TDC
    TAX                         ; X = table index
    LDA.b #!BattleUI_CmdWindowRows
    STA.b !BattleUI_RowsLeft
.combo_row_start:
    LDA.b #!BattleUI_CmdWindowCols
    STA.b !BattleUI_ColsLeft
    LDY.b !BattleUI_MapOffset
.combo_col_loop:
    LDA.l !BattleRom_CmdListCombo,X
    STA.w BattleUI_StatusTile(0,0),Y
    LDA.b #!BattleUI_AttrPal2
    STA.w BattleUI_StatusAttr(0,0),Y
    INY
    INY
    INX
    DEC.b !BattleUI_ColsLeft
    BNE .combo_col_loop
    REP #$21                    ; M=0, C=0
    LDA.b !BattleUI_MapOffset
    ADC.w #!BattleUI_MapRowBytes ; next tilemap row
    STA.b !BattleUI_MapOffset
    TDC
    SEP #$20                    ; M=1
    DEC.b !BattleUI_RowsLeft
    BNE .combo_row_start
.done:
    RTS

; $C1:081E — BattleMenu_DrawCommandWindowFrames (202 bytes, $081E–$08E7)
; Draw the 7×6 command-window frame of every PC in the roster into
; !BattleMenu_WindowMap, then highlight the shown PC's name and fall into
; BattleUI_ClearActivePanelColumn. Slot 1's / slot 2's frame is drawn
; joined (!BattleUI_FrameJoined = 1: without its left border column, one
; cell further right) when the slot before it is also in the roster, so
; it shares that window's right border; else it is drawn whole.
; BattleUI_ClearActivePanelColumn ($0872) is also called on its own
; (BattleMenu_UpdateMainWindow) when only the cursor column needs redrawing.
; Entry: M=1, X=0 (16-bit)
; Exit:  M=1; DP $80/$82/$84 clobbered; X/Y clobbered
; Calls: BattleMenu_DrawCommandWindowFrame, BattleUI_HighlightPcName
!BattleUI_FrameJoined = !BattleTmp_84    ; 1 B: 0 = whole frame, else drop its left border column (DrawCommandWindowFrame input)
org $C1081E
BattleMenu_DrawCommandWindowFrames:
    STZ.b !BattleUI_FrameJoined ; whole frame
    LDA.w !BattleMenu_Roster    ; PC slot 0 in the roster?
    BMI .check_slot1            ; no → no window
    LDX.w #$0000                ; map offset 0
    STX.b !BattleUI_MapOffset
    JSR BattleMenu_DrawCommandWindowFrame
.check_slot1:
    LDA.w !BattleMenu_Roster+1  ; PC slot 1 in the roster?
    BMI .check_slot2            ; no → no window
    LDA.w !BattleMenu_Roster    ; slot 0 too?
    BMI .slot1_whole            ; no → whole frame
    LDA #$01
    STA.b !BattleUI_FrameJoined ; yes → joined to slot 0's window
    LDX.w #!BattleUI_FrameCol1Joined
    BRA .slot1_draw
.slot1_whole:
    LDX.w #!BattleUI_FrameCol1Full
.slot1_draw:
    STX.b !BattleUI_MapOffset
    JSR BattleMenu_DrawCommandWindowFrame
    STZ.b !BattleUI_FrameJoined ; back to whole frames
.check_slot2:
    LDA.w !BattleMenu_Roster+2  ; PC slot 2 in the roster?
    BMI .active_pc_section      ; no → no window
    LDA.w !BattleMenu_Roster+1  ; slot 1 too?
    BMI .slot2_whole            ; no → whole frame
    LDA #$01
    STA.b !BattleUI_FrameJoined ; yes → joined to slot 1's window
    LDX.w #!BattleUI_FrameCol2Joined
    BRA .slot2_draw
.slot2_whole:
    LDX.w #!BattleUI_FrameCol2Full
.slot2_draw:
    STX.b !BattleUI_MapOffset
    JSR BattleMenu_DrawCommandWindowFrame
.active_pc_section:
    LDA.w !BattleMenu_RosterIdx ; roster entry shown
    TAX
    LDA.w !BattleMenu_Roster,X  ; its PC slot
    JSR BattleUI_HighlightPcName
    INC.w !BattleUI_PanelRedraw ; redraw the command cursor below

; $C1:0872 — BattleUI_ClearActivePanelColumn (entry point within above body)
; Zero the two tile columns of the shown PC's command column (6 rows,
; offset !BattleMenu_ActivePc × 12) in the status map, then, if
; !BattleUI_PanelRedraw is set and no target selection is running, draw
; the 2×2 command cursor (tiles $60-$63) at the PC's !Pc_MenuRow, placed
; through !BattleRom_MenuCursorCell (the same cursor quad the tech and
; item lists use).
; Entry: M=1, X=0 (16-bit)
; Exit:  M=1; DP $80/$81, X/Y clobbered; !BattleUI_PanelRedraw = 0
; No calls.
!BattleUI_ColumnOffset = !BattleTmp_80   ; 1-2 B: slot * 12, the PC's column offset in the status map
BattleUI_ClearActivePanelColumn:
    LDA.w !BattleMenu_ActivePc
    ASL
    ASL
    STA.b !BattleUI_ColumnOffset ; slot × 4
    ASL
    CLC
    ADC.b !BattleUI_ColumnOffset ; slot × 12
    TAX                         ; X = column offset
    STZ.w BattleUI_StatusTile(0,0),X
    STZ.w BattleUI_StatusTile(1,0),X
    STZ.w BattleUI_StatusTile(2,0),X
    STZ.w BattleUI_StatusTile(3,0),X
    STZ.w BattleUI_StatusTile(4,0),X
    STZ.w BattleUI_StatusTile(5,0),X
    STZ.w BattleUI_StatusTile(0,1),X
    STZ.w BattleUI_StatusTile(1,1),X
    STZ.w BattleUI_StatusTile(2,1),X
    STZ.w BattleUI_StatusTile(3,1),X
    STZ.w BattleUI_StatusTile(4,1),X
    STZ.w BattleUI_StatusTile(5,1),X
    LDA.w !BattleUI_PanelRedraw
    BEQ .clear_done             ; zero → just clear flag and return
    LDA.w !BattleMenu_RosterIdx ; roster entry shown
    TAX
    ASL
    ASL
    STA.b !BattleUI_ColumnOffset ; × 4
    ASL
    CLC
    ADC.b !BattleUI_ColumnOffset ; × 12
    TAY
    STY.b !BattleUI_ColumnOffset ; 16-bit column offset
    LDA.w !BattleMenu_Roster,X  ; its PC slot
    TAX
    LDA.w !Pc_MenuRow,X         ; that PC's command row
    ASL
    TAX                         ; X = row × 2
    REP #$21                    ; M=0, C=0
    LDA.l !BattleRom_MenuCursorCell,X ; cursor offset within the column
    ADC.b !BattleUI_ColumnOffset ; + column offset
    TAX                         ; X = map offset of the cursor
    TDC
    SEP #$20                    ; M=1
    LDA.w !BattleMenu_TargetSelect
    BNE .clear_done             ; selecting a target → no command cursor
    LDA.b #!BattleMenu_TileCursorTL
    STA.w BattleUI_StatusTile(0,0),X
    LDA.b #!BattleMenu_TileCursorTR
    STA.w BattleUI_StatusTile(0,1),X
    LDA.b #!BattleMenu_TileCursorBL
    STA.w BattleUI_StatusTile(1,0),X
    LDA.b #!BattleMenu_TileCursorBR
    STA.w BattleUI_StatusTile(1,1),X
.clear_done:
    STZ.w !BattleUI_PanelRedraw
    RTS

; $C1:08E8 — BattleUI_HighlightPcName (65 bytes, $08E8–$0928)
; Highlight PC slot A's name in the status bar: look up the slot's offset
; in !BattleRom_NameAttrL1 (layout 1) or !BattleRom_NameAttrL02 (layouts
; 0 and 2) and set the attribute of a 5-wide × 2-high block of status-map
; cells to palette 2. That block is the PC's 10-tile name (the name line
; and the row above it, see BattleUI_DrawPcNamePanel), which is normally
; drawn in palette 3. The table offsets are odd, i.e. they point at an
; attribute byte, so the Tile(r,c),X stores below all land on attribute
; bytes. BuildStatusBarFrame also calls it with the first selected target.
; Entry: M=1, X=0 (16-bit), A = PC slot (0–2)
; Exit:  M=1; X = offset; A = !BattleUI_AttrPal2; Y unchanged
; No calls.
org $C108E8
BattleUI_HighlightPcName:
    ASL                         ; slot × 2 (table index)
    TAX
    REP #$20                    ; M=0
    LDA.w !BattleUI_GaugeLayout ; (16-bit read; layout 0/1/2)
    BNE .type_not0
    LDA.l !BattleRom_NameAttrL02,X ; layout 0
    BRA .got_offset
.type_not0:
    DEC A                       ; layout − 1
    BNE .type_not1              ; non-zero → layout 2
    LDA.l !BattleRom_NameAttrL1,X ; layout 1
    BRA .got_offset
.type_not1:
    LDA.l !BattleRom_NameAttrL02,X ; layout 2 (same table as layout 0)
.got_offset:
    TAX                         ; X = map offset of an attribute byte
    TDC
    SEP #$20                    ; M=1
    LDA.b #!BattleUI_AttrPal2
    STA.w BattleUI_StatusTile(0,0),X
    STA.w BattleUI_StatusTile(0,1),X
    STA.w BattleUI_StatusTile(0,2),X
    STA.w BattleUI_StatusTile(0,3),X
    STA.w BattleUI_StatusTile(0,4),X
    STA.w BattleUI_StatusTile(1,0),X
    STA.w BattleUI_StatusTile(1,1),X
    STA.w BattleUI_StatusTile(1,2),X
    STA.w BattleUI_StatusTile(1,3),X
    STA.w BattleUI_StatusTile(1,4),X
    RTS

; $C1:0929 — BattleMenu_DrawCommandWindowFrame (52 bytes, $0929–$095C)
; Copy one 7-column × 6-row command-window frame (corners, borders and
; fill) from !BattleRom_CommandWindowFrame into !BattleMenu_WindowMap at
; !BattleUI_MapOffset. Each ROM row is 14 bytes (7 tile/attribute
; entries): a whole frame (!BattleUI_FrameJoined = 0) copies all of it, a
; joined frame skips the row's first entry (the left border column) and
; copies the other 12 bytes.
; Entry: M=1, X=0 (16-bit), !BattleUI_MapOffset = map offset,
;        !BattleUI_FrameJoined = 0 for a whole frame
; Exit:  M=1; X/Y and DP $80-$83 clobbered
; No calls.
!BattleUI_FrameBytesLeft = !BattleTmp_80      ; 1 B: bytes left to copy in this row
!BattleUI_FrameRowsLeft = !BattleTmp_81       ; 1 B: rows left
org $C10929
BattleMenu_DrawCommandWindowFrame:
    TDC
    TAX                         ; X = 0 (ROM table index)
    LDA.b #!BattleUI_CmdWindowRows
    STA.b !BattleUI_FrameRowsLeft
.row_loop:
    LDA.b !BattleUI_FrameJoined
    BNE .joined
    LDA.b #!BattleUI_FrameRowBytesFull ; whole frame: all 14 bytes of the row
    BRA .pick_done
.joined:
    INX                         ; joined: skip the left border entry
    INX
    LDA.b #!BattleUI_FrameRowBytesJoined ; and copy the other 12 bytes
.pick_done:
    STA.b !BattleUI_FrameBytesLeft
    LDY.b !BattleUI_MapOffset   ; Y = current row
.inner_loop:
    LDA.l !BattleRom_CommandWindowFrame,X
    STA.w !BattleMenu_WindowMap,Y
    INX
    INY
    DEC.b !BattleUI_FrameBytesLeft
    BNE .inner_loop
    REP #$21                    ; M=0, C=0
    LDA.b !BattleUI_MapOffset
    ADC.w #!BattleUI_MapRowBytes ; next tilemap row
    STA.b !BattleUI_MapOffset
    TDC
    SEP #$20                    ; M=1
    DEC.b !BattleUI_FrameRowsLeft
    BNE .row_loop
    RTS

; ============================================================
; Battle Menu — Item/Tech List Rendering Cluster
; $C1:095D–$C1:0C2C  (720 bytes)
; ============================================================

; $C1:095D — BattleMenu_RenderItemListRows (83 bytes, $095D–$09AF)
; Renders the 3 visible item-list lines:
;   1. Clears the item list map (BattleMenu_ItemTile, $180 bytes).
;   2. First record offset = scroll × !Item_RecordSize.
;   3. Calls BattleMenu_RenderItemRow for lines 0-2, advancing the record
;      by one and the map offset by !BattleMenu_ListRowStride each time.
; Entry: M=1, X=0 (16-bit), DB=$7E; !BattleMenu_ListScroll = scroll position
; Exit:  M=1; DP $80-$87, $8E-$8F, $96-$98 clobbered (the last three
;        partly by BattleMenu_RenderItemRow)
; Calls: BattleMenu_RenderItemRow
; Direct-page roles (shared with RenderItemRow and the list scroll routines):
!BattleMenu_ListScroll = !BattleTmp_80    ; 1 B in: list scroll position
!BattleMenu_ItemRecOffset = !BattleTmp_80 ; 2 B: Item_BattleList offset of the line being drawn
!BattleMenu_ListPc = !BattleTmp_96        ; 2 B: active PC slot (selects its BattleRom_PcBit)
!BattleMenu_RowMapOffset = !BattleTmp_82  ; 2 B: map offset of the line being drawn (line * $80)
!BattleMenu_RowCount = !BattleTmp_86      ; 1-2 B: lines drawn so far
org $C1095D
BattleMenu_RenderItemListRows:
    LDA.w !BattleMenu_ActivePc
    TAX
    STX.b !BattleMenu_ListPc        ; (16-bit store)
    LDX.w #!BattleMenu_WindowBytes  ; bytes to clear
    REP #$20                        ; M=0
    TDC                             ; A = 0
    TAY                             ; Y = 0 (buffer index)
    SEP #$20                        ; M=1
.clear_loop:
    STA.w BattleMenu_ItemTile(0,0),Y ; zero one byte
    INY
    DEX
    BNE .clear_loop
    STZ.b !BattleMenu_ListScroll+1  ; zero-extend the scroll position
    REP #$20                        ; M=0
    TDC
    STA.b !BattleMenu_RowMapOffset  ; line 0 at map offset 0
    LDA.b !BattleMenu_ListScroll
    STA.b !BattleTmp_84
    ASL A                           ; * 2
    ASL A                           ; * 4
    CLC
    ADC.b !BattleTmp_84             ; * 4 + * 1 = * 5
    STA.b !BattleMenu_ItemRecOffset ; first record
    TAX
    TDC
    STA.b !BattleMenu_RowCount      ; lines drawn = 0
    SEP #$20                        ; M=1
.row_loop:
    JSR BattleMenu_RenderItemRow
    REP #$20                        ; M=0
    LDA.b !BattleMenu_RowCount
    INC A                           ; next line
    ASL A                           ; * 2
    ASL A                           ; * 4
    ASL A                           ; * 8
    ASL A                           ; * 16
    ASL A                           ; * 32
    ASL A                           ; * 64
    ASL A                           ; * 128 (two tilemap rows per line)
    STA.b !BattleMenu_RowMapOffset
    CLC
    LDA.b !BattleMenu_ItemRecOffset
    ADC.w #!Item_RecordSize         ; next record
    STA.b !BattleMenu_ItemRecOffset
    TDC
    SEP #$20                        ; M=1
    INC.b !BattleMenu_RowCount
    LDA.b !BattleMenu_RowCount
    CMP.b #!BattleMenu_ListRows
    BNE .row_loop
    RTS

; $C1:09B0 — BattleMenu_RenderItemRow (215 bytes, $09B0–$0A86) +
;             CODE_JP_C10A87 (1 byte, $0A87)
; Renders one item-list line for the Item_BattleList record at
; !BattleMenu_ItemRecOffset into the item map at !BattleMenu_RowMapOffset.
;   - Quantity 0 or id 0 → nothing drawn.
;   - Copies 11 bytes from bank $CC at !Item_NameTable + id × 11 + 1 into
;     !BattleMsg_TextTiles (the +1 is the carry left by the SBC, so the
;     record's leading icon byte is skipped and the 11th byte copied is
;     the next record's icon), re-encodes them, then writes 10 lower-row
;     tiles to row 1 and 11 upper-row tiles to row 0 of the line, from
;     col 3.
;   - Quantity as two digits at row 1, cols 15-16, then the glyphs
;     "Item" at cols 22-25.
;   - Attribute for the whole line: palette 3 (greyed) when .Flags bit 7 is
;     set and .PcMask lacks the active PC's bit, else palette 2.
; Entry: M=1, X=0 (16-bit), DB=$7E; !BattleMenu_ItemRecOffset, !BattleMenu_RowMapOffset
; Exit:  M=1; DP $84-$85, $8E-$8F, $98 clobbered
; Calls: BattleMsg_ReencodeTextBuffer, BattleMsg_FormatTwoDigits, BattleMsg_BlankLeadingZeros
!BattleMenu_RowAttr = !BattleTmp_98      ; 1 B: attribute for the whole line (palette 2 or greyed 3)
org $C109B0
BattleMenu_RenderItemRow:
    LDX.b !BattleMenu_ItemRecOffset ; (16-bit DP load)
    LDA.w Item_BattleList.Quantity,X
    BEQ .empty_slot                 ; none held → skip
    LDA.w Item_BattleList.Id,X
    BNE .render_item
.empty_slot:
    JMP CODE_JP_C10A87              ; skip this line
.render_item:
    REP #$20                        ; M=0
    STA.b !BattleTmp_84             ; item id (16-bit, B=0)
    ASL A                           ; * 2
    ASL A                           ; * 4
    STA.b !BattleTmp_8E             ; save * 4
    ASL A                           ; * 8
    CLC
    ADC.b !BattleTmp_8E             ; * 8 + * 4 = * 12
    SEC
    SBC.b !BattleTmp_84             ; * 12 - * 1 = * 11 (bytes per name)
    ADC.w #!Item_NameTable          ; C is still set from the SBC: +1, past the icon byte
    TAX                             ; X = name address in bank $CC
    TDC
    LDY.w #!BattleMsg_TextTiles     ; Y = destination in bank $7E
    LDA.w #!Item_NameLen-1          ; count − 1
    ; copy the item name: $CC:X → $7E:TextTiles
    MVN !Battle_WramBank,!BattleRom_TextBank ; lint-ok: MVN takes bank bytes and has no width suffix
    TDC
    SEP #$20                        ; M=1
    STA.w !Battle_WramAbs,Y         ; terminate the text (Y = end of the copy)
    JSR BattleMsg_ReencodeTextBuffer
    LDX.b !BattleMenu_ItemRecOffset
    LDA.w Item_BattleList.Flags,X
    BPL .attr_normal                ; bit 7 clear → normal
    LDA.w Item_BattleList.PcMask,X
    LDX.b !BattleMenu_ListPc        ; (16-bit DP load)
    AND.l !BattleRom_PcBit,X        ; this PC's bit
    BNE .attr_normal                ; this PC may use it → normal
    LDA.b #!BattleUI_AttrPal3       ; greyed
    BRA .attr_done
.attr_normal:
    LDA.b #!BattleUI_AttrPal2
.attr_done:
    STA.b !BattleMenu_RowAttr
    TDC
    TAY
    LDX.b !BattleMenu_RowMapOffset
.name_copy1:                        ; lower-row tiles (X steps over tile, attribute)
    LDA.w !BattleMsg_TextTiles,Y
    STA.w BattleMenu_ItemTile(1,3),X
    INX
    LDA.b !BattleMenu_RowAttr
    STA.w BattleMenu_ItemTile(1,3),X ; (X+1: the attribute byte)
    INX
    INY
    CPY.w #!Item_NameLen-1          ; 10 tiles on this row
    BNE .name_copy1
    LDA.b #!BattleUI_TileSpacer
    STA.w BattleMenu_ItemTile(1,4),X
    LDA.b !BattleMenu_RowAttr
    STA.w BattleMenu_ItemAttr(1,4),X
    TDC
    TAY
    LDX.b !BattleMenu_RowMapOffset
.name_copy2:                        ; upper-row tiles
    LDA.w !BattleMsg_TextTopTiles,Y
    STA.w BattleMenu_ItemTile(0,3),X
    INX
    LDA.b !BattleMenu_RowAttr
    STA.w BattleMenu_ItemTile(0,3),X ; (X+1: the attribute byte)
    INX
    INY
    CPY.w #!Item_NameLen            ; 11 tiles on this row
    BNE .name_copy2
    LDX.b !BattleMenu_ItemRecOffset
    LDA.w Item_BattleList.Quantity,X
    REP #$20                        ; M=0 (B is 0: zero-extended)
    STA.w !BattleMsg_NumValue
    JSR BattleMsg_FormatTwoDigits   ; two digits
    JSR BattleMsg_BlankLeadingZeros
    LDX.b !BattleMenu_RowMapOffset  ; (M=1 again after both calls)
    LDA.w !BattleMsg_Digit10
    STA.w BattleMenu_ItemTile(1,15),X
    LDA.b !BattleMenu_RowAttr
    STA.w BattleMenu_ItemAttr(1,15),X
    LDA.w !BattleMsg_Digit1
    STA.w BattleMenu_ItemTile(1,16),X
    LDA.b !BattleMenu_RowAttr
    STA.w BattleMenu_ItemAttr(1,16),X
    LDA.b #!BattleMsg_Glyph_I
    STA.w BattleMenu_ItemTile(1,22),X
    LDA.b !BattleMenu_RowAttr
    STA.w BattleMenu_ItemAttr(1,22),X
    LDA.b #!BattleMsg_Glyph_t
    STA.w BattleMenu_ItemTile(1,23),X
    LDA.b !BattleMenu_RowAttr
    STA.w BattleMenu_ItemAttr(1,23),X
    LDA.b #!BattleMsg_Glyph_e
    STA.w BattleMenu_ItemTile(1,24),X
    LDA.b !BattleMenu_RowAttr
    STA.w BattleMenu_ItemAttr(1,24),X
    LDA.b #!BattleMsg_Glyph_m
    STA.w BattleMenu_ItemTile(1,25),X
    LDA.b !BattleMenu_RowAttr
    STA.w BattleMenu_ItemAttr(1,25),X
CODE_JP_C10A87:
    RTS

; $C1:0A88 — BattleMenu_RenderTechListRows (75 bytes, $0A88–$0AD2)
; Renders 4 tech-list lines (2 per outer loop pass) for the active PC
; into the tech text buffer (BattleMenu_TechTextTile). First line =
; !BattleRom_TechListBase[PC] + !Pc_TechScroll[PC]; each line advances
; the map offset by !BattleMenu_ListRowStride.
; Entry: M=1, X=0 (16-bit), DB=$7E
; Exit:  M=1
; Calls: BattleMenu_RenderTechRow
; Direct-page roles (shared with RenderTechRow and its tails):
!BattleMenu_TechListBase = !BattleTmp_AF  ; 1 B: first line of the PC's tech list
!BattleMenu_TechRowNum = !BattleTmp_88    ; 1-2 B: list line number being drawn
!BattleMenu_PairsLeft = !BattleTmp_87     ; 1 B: line pairs left
!BattleMenu_TechCodeIdx = !BattleTmp_80   ; 2 B: !Tech_ListCode index of the line being drawn
org $C10A88
BattleMenu_RenderTechListRows:
    LDA.w !BattleMenu_ActivePc
    TAX
    LDA.l !BattleRom_TechListBase,X ; PC's first list line
    STA.b !BattleMenu_TechListBase
    LDA.w !Pc_TechScroll,X
    STA.b !BattleMenu_TechRowNum
    STA.b !BattleTmp_86             ; (not read again here)
    LDA.b #!BattleMenu_TechRowPairs
    STA.b !BattleMenu_PairsLeft     ; 2 passes × 2 lines
    STZ.b !BattleMenu_TechRowNum+1
    CLC
    LDA.b !BattleMenu_TechRowNum
    ADC.b !BattleMenu_TechListBase  ; scroll + base
    STA.b !BattleMenu_TechCodeIdx
    STZ.b !BattleMenu_TechCodeIdx+1
    TDC
    STA.b !BattleMenu_RowMapOffset  ; first line at map offset 0
    STA.b !BattleMenu_RowMapOffset+1
.row_pair_loop:
    JSR BattleMenu_RenderTechRow    ; first line of the pair
    INC.b !BattleMenu_TechCodeIdx
    REP #$21                        ; M=0, C=0
    LDA.b !BattleMenu_RowMapOffset
    ADC.w #!BattleMenu_ListRowStride ; next line
    STA.b !BattleMenu_RowMapOffset
    TDC
    SEP #$20                        ; M=1
    JSR BattleMenu_RenderTechRow    ; second line of the pair
    REP #$21                        ; M=0, C=0
    LDA.b !BattleMenu_RowMapOffset
    ADC.w #!BattleMenu_ListRowStride
    STA.b !BattleMenu_RowMapOffset
    SEP #$20                        ; M=1
    INC.b !BattleMenu_TechCodeIdx
    DEC.b !BattleMenu_PairsLeft
    BNE .row_pair_loop
    RTS

; $C1:0AD3 — BattleMenu_BuildTechAvailFlags (56 bytes, $0AD3–$0B0A)
; Builds !Tech_ListAvail (20 entries, one per list line) for the active
; PC's tech list: line code $FB-$FF (blank, header or skip line) → 0,
; anything else → 1. TechListPrev/Next use it to skip those lines.
; Entry: M=1, X=0 (16-bit), DB=$7E
; Exit:  M=1; DP $80, X/Y clobbered
; No JSR/JSL calls.
!BattleMenu_EntriesLeft = !BattleTmp_80  ; 1 B: list lines left to grade
org $C10AD3
BattleMenu_BuildTechAvailFlags:
    TDC
    TAY                             ; Y = index into !Tech_ListAvail
    LDA.b #!Tech_ListLen
    STA.b !BattleMenu_EntriesLeft
    LDA.w !BattleMenu_ActivePc
    TAX
    LDA.l !BattleRom_TechListBase,X
    TAX                             ; X = index into !Tech_ListCode
.avail_loop:
    LDA.w !Tech_ListCode,X
    CMP.b #!Tech_CodeBlank
    BEQ .unavail
    CMP.b #!Tech_CodeBlank2
    BEQ .unavail
    CMP.b #!Tech_CodeTripleHeader
    BEQ .unavail
    CMP.b #!Tech_CodeDoubleHeader
    BEQ .unavail
    CMP.b #!Tech_CodeSkip
    BEQ .unavail
    LDA #$01                        ; selectable
    STA.w !Tech_ListAvail,Y
    BRA .next
.unavail:
    TDC                             ; 0 = unselectable
    STA.w !Tech_ListAvail,Y
.next:
    INY
    INX
    DEC.b !BattleMenu_EntriesLeft
    BNE .avail_loop
    RTS

; $C1:0B0B — BattleMenu_RenderTechRow (171 bytes, $0B0B–$0BB5)
; Renders one tech-list line: blanks the text rows (!BattleMsg_TextTiles /
; TextTopTiles), fills them by the line code !Tech_ListCode[TechCodeIdx],
; and copies them into the tech text buffer at !BattleMenu_RowMapOffset:
;   $FF/$FE → blank line (via CODE_JP_C10BB6)
;   $FD     → "Triple Technique" header (!BattleRom_TechFixedText + $12)
;   $FC     → "Double Technique" header (!BattleRom_TechFixedText + 0)
;             (each 18 bytes, the text between end glyphs $5B and $5C)
;   $FB     → blank line: the still-blank text rows go through the tech-name
;             path, so cols 3-20 of both rows are blanked
;   else    → tech name: bank $CC, !Tech_NameTable + code × 11, re-encoded;
;             upper/lower rows from col 6, palette 3
; Every path advances !BattleMenu_TechRowNum.
; Entry: M=1, X=0 (16-bit), DB=$7E; !BattleMenu_TechCodeIdx, !BattleMenu_RowMapOffset
; Exit:  M=1
; Calls: BattleMsg_ReencodeTextBuffer, BattleMenu_BlankNameLeadCells,
;        CODE_JP_C10BB6, CODE_JP_C10C00
org $C10B0B
BattleMenu_RenderTechRow:
    REP #$20                        ; M=0
    LDX.w #!BattleMsg_TextBufBytes-2
    LDA.w #!BattleUI_TileBlankPair
.fill_loop:
    STA.w !BattleMsg_TextTiles,X    ; blank both text rows
    DEX
    DEX
    BPL .fill_loop
    TDC
    SEP #$20                        ; M=1
    LDX.b !BattleMenu_TechCodeIdx   ; (16-bit DP load)
    LDA.w !Tech_ListCode,X
    CMP.b #!Tech_CodeBlank
    BEQ .fixedstr_skip              ; blank line
    CMP.b #!Tech_CodeBlank2
    BEQ .fixedstr_skip              ; blank line
    CMP.b #!Tech_CodeTripleHeader
    BEQ .triple_header              ; "Triple Technique"
    CMP.b #!Tech_CodeDoubleHeader
    BEQ .double_header              ; "Double Technique"
    CMP.b #!Tech_CodeSkip
    BNE .tech_name                  ; anything else is a tech
    LDX.b !BattleMenu_TechRowNum    ; $FB blank line (X not used further)
    BRA .copy_out
.double_header:
    LDX.w #!Tech_DoubleHeaderText
    BRA .into_fixedstr
.triple_header:
    LDX.w #!Tech_TripleHeaderText
.into_fixedstr:
    TDC
    TAY
.fixed_copy:
    LDA.l !BattleRom_TechFixedText,X
    STA.w !BattleMsg_TextTiles,Y
    INX
    INY
    CPY.w #!Tech_HeaderTextLen
    BNE .fixed_copy
.fixedstr_skip:
    LDX.b !BattleMenu_TechRowNum
    JMP CODE_JP_C10BB6
.tech_name:
    LDX.b !BattleMenu_TechRowNum    ; (X not used further)
    REP #$20                        ; M=0
    STA.b !BattleTmp_8E             ; tech id (16-bit; B=0 from the TDC above)
    ASL A                           ; * 2
    ASL A                           ; * 4
    STA.b !BattleTmp_90
    ASL A                           ; * 8
    CLC
    ADC.b !BattleTmp_90             ; * 8 + * 4 = * 12
    SEC
    SBC.b !BattleTmp_8E             ; * 12 - * 1 = * 11
    CLC
    ADC.w #!Tech_NameTable
    TAX                             ; X = name address in bank $CC
    LDY.w #!BattleMsg_TextTiles     ; destination in bank $7E
    LDA.w #!Tech_NameLen-1          ; count − 1
    ; copy the tech name: $CC:X → $7E:TextTiles
    MVN !Battle_WramBank,!BattleRom_TextBank ; lint-ok: MVN takes bank bytes and has no width suffix
    TDC
    SEP #$20                        ; M=1
    STA.w !Battle_WramAbs,Y         ; terminate the text (Y = end of the copy)
    JSR BattleMsg_ReencodeTextBuffer
.copy_out:
    INC.b !BattleMenu_TechRowNum
    JSR BattleMenu_BlankNameLeadCells
    TDC
    TAY
    LDX.b !BattleMenu_RowMapOffset
.tech_copy1:                        ; lower row (X steps over tile, attribute)
    LDA.w !BattleMsg_TextTiles,Y
    STA.w BattleMenu_TechTextTile(1,6),X
    INX
    LDA.b #!BattleUI_AttrPal3
    STA.w BattleMenu_TechTextTile(1,6),X ; (X+1: the attribute byte)
    INX
    INY
    CPY.w #!Tech_NameLen
    BNE .tech_copy1
    TDC
    TAY
    LDX.b !BattleMenu_RowMapOffset
.tech_copy2:                        ; upper row
    LDA.w !BattleMsg_TextTopTiles,Y
    STA.w BattleMenu_TechTextTile(0,6),X
    INX
    LDA.b #!BattleUI_AttrPal3
    STA.w BattleMenu_TechTextTile(0,6),X ; (X+1: the attribute byte)
    INX
    INY
    CPY.w #!Tech_NameLen
    BNE .tech_copy2
    JMP CODE_JP_C10C00
    RTS                             ; dead: unreachable after the JMP, kept for the byte

; $C1:0BB6 — CODE_JP_C10BB6 (29 bytes, $0BB6–$0BD2)
; Blank-line / header exit path of BattleMenu_RenderTechRow: advances
; !BattleMenu_TechRowNum, blanks the lead cells, then copies 18 lower-row
; tiles from !BattleMsg_TextTiles into the line from col 3 (palette 3).
; Entry: M=1, X=0 (16-bit), DB=$7E; !BattleMenu_RowMapOffset
; Exit:  M=1
; Calls: BattleMenu_BlankNameLeadCells
org $C10BB6
CODE_JP_C10BB6:
    INC.b !BattleMenu_TechRowNum
    JSR BattleMenu_BlankNameLeadCells
    TDC
    TAY
    LDX.b !BattleMenu_RowMapOffset
.copy_loop:
    LDA.w !BattleMsg_TextTiles,Y
    STA.w BattleMenu_TechTextTile(1,3),X
    INX
    LDA.b #!BattleUI_AttrPal3
    STA.w BattleMenu_TechTextTile(1,3),X ; (X+1: the attribute byte)
    INX
    INY
    CPY.w #!Tech_HeaderTextLen
    BNE .copy_loop
    RTS

; $C1:0BD3 — BattleMenu_BlankNameLeadCells (45 bytes, $0BD3–$0BFF)
; Blanks cols 3-5, the lead cells left of the name (which starts at
; col 6), on both rows of the tech-list line at !BattleMenu_RowMapOffset
; (blank tile, palette 3). MP costs are not drawn here: they go to the
; tech window (BattleMenu_UpdateTechWindow).
; Called from BattleMenu_RenderTechRow and CODE_JP_C10BB6.
; Entry: M=1, X=0 (16-bit), DB=$7E; !BattleMenu_RowMapOffset
; Exit:  M=1; X/Y clobbered
; No JSR/JSL calls.
org $C10BD3
BattleMenu_BlankNameLeadCells:
    TDC
    TAY
    LDX.b !BattleMenu_RowMapOffset
.blank1_loop:
    LDA.b #!BattleUI_TileBlank
    STA.w BattleMenu_TechTextTile(1,3),X
    INX
    LDA.b #!BattleUI_AttrPal3
    STA.w BattleMenu_TechTextTile(1,3),X
    INX
    INY
    CPY.w #!BattleMenu_NameLeadCells
    BNE .blank1_loop
    TDC
    TAY
    LDX.b !BattleMenu_RowMapOffset
.blank2_loop:
    LDA.b #!BattleUI_TileBlank
    STA.w BattleMenu_TechTextTile(0,3),X
    INX
    LDA.b #!BattleUI_AttrPal3
    STA.w BattleMenu_TechTextTile(0,3),X
    INX
    INY
    CPY.w #!BattleMenu_NameLeadCells
    BNE .blank2_loop
    RTS

; $C1:0C00 — CODE_JP_C10C00 (45 bytes, $0C00–$0C2C)
; Tech-name exit path of BattleMenu_RenderTechRow: blanks cols 17-20
; (right of the 11-tile name) on both rows of the line (blank tile,
; palette 3).
; Entry: M=1, X=0 (16-bit), DB=$7E; !BattleMenu_RowMapOffset
; Exit:  M=1; X/Y clobbered
; No JSR/JSL calls.
org $C10C00
CODE_JP_C10C00:
    TDC
    TAY
    LDX.b !BattleMenu_RowMapOffset
.blank1_loop:
    LDA.b #!BattleUI_TileBlank
    STA.w BattleMenu_TechTextTile(1,17),X
    INX
    LDA.b #!BattleUI_AttrPal3
    STA.w BattleMenu_TechTextTile(1,17),X
    INX
    INY
    CPY.w #!BattleMenu_NameTailCells
    BNE .blank1_loop
    TDC
    TAY
    LDX.b !BattleMenu_RowMapOffset
.blank2_loop:
    LDA.b #!BattleUI_TileBlank
    STA.w BattleMenu_TechTextTile(0,17),X
    INX
    LDA.b #!BattleUI_AttrPal3
    STA.w BattleMenu_TechTextTile(0,17),X
    INX
    INY
    CPY.w #!BattleMenu_NameTailCells
    BNE .blank2_loop
    RTS

; ==================================================================
; BattleMenu_UpdateWindows ($C10C2D–$C10C48, 28 bytes)
; ==================================================================
; Per-frame window upkeep dispatcher. Calls BattleFx_SetPtrA2FromTable
; with the shown PC, then dispatches on !BattleMenu_Submenu:
;   0 → BattleMenu_UpdateMainWindow
;   1 → BattleMenu_UpdateTechMpAvail + BattleMenu_UpdateTechWindow
;   other → CODE_JP_C1103D (RTS)
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; registers clobbered by callees
; Callees: BattleFx_SetPtrA2FromTable, BattleMenu_UpdateMainWindow,
;          BattleMenu_UpdateTechMpAvail, BattleMenu_UpdateTechWindow
org $C10C2D
BattleMenu_UpdateWindows:
    LDA.w !BattleMenu_ActivePc
    JSL BattleFx_SetPtrA2FromTable
    LDA.w !BattleMenu_Submenu
    BNE .not_main
    JMP BattleMenu_UpdateMainWindow ; main command window
.not_main:
    CMP.b #!BattleMenu_SubmenuTech
    BNE CODE_C10C46                 ; item list: nothing to do here
    JSR BattleMenu_UpdateTechMpAvail ; tech list: grade the rows first
    JMP BattleMenu_UpdateTechWindow  ; then refresh the window

CODE_C10C46:                        ; shared exit — jumped to from UpdateMainWindow too
    JMP CODE_JP_C1103D              ; → shared RTS at $103D

; ==================================================================
; BattleMenu_UpdateMainWindow ($C10C49–$C10C82, 58 bytes)
; ==================================================================
; Main command-window upkeep (submenu 0):
; - If !BattleMenu_RosterIdx differs from !BattleMenu_RosterIdxDrawn:
;     reload the command window map and rebuild the status bar.
; - Else: BattleUI_UpdateNextPcPanel; if !BattleUI_PanelRedraw is set and
;     a roster entry is shown, redraw the command cursor column.
; - If no PC is shown (!BattleMenu_ActivePc < 0): reload the window map.
; - Always: queue the status map ($0CC0) upload, bump
;   !BattleMenu_WindowMapDirty.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1
; Callees: BattleMenu_LoadCommandWindowMap, BattleUI_BuildStatusBarFrame,
;          BattleUI_UpdateNextPcPanel, BattleUI_ClearActivePanelColumn,
;          Battle_QueueVramUpload_0CC0
BattleMenu_UpdateMainWindow:
    LDA.w !BattleMenu_Submenu       ; must still be the main menu
    BNE CODE_C10C46
    LDA.w !BattleMenu_RosterIdx
    CMP.w !BattleMenu_RosterIdxDrawn
    BEQ .same_pc
    STA.w !BattleMenu_RosterIdxDrawn
    JSR BattleMenu_LoadCommandWindowMap
    JSR BattleUI_BuildStatusBarFrame
    BRA .do_upload
.same_pc:
    JSR BattleUI_UpdateNextPcPanel
    LDA.w !BattleUI_PanelRedraw
    BEQ .do_upload
    LDA.w !BattleMenu_RosterIdx
    BMI .do_upload
    JSR BattleUI_ClearActivePanelColumn ; command cursor column
.do_upload:
    LDA.w !BattleMenu_ActivePc
    BPL .queue
    JSR BattleMenu_LoadCommandWindowMap ; no PC shown → plain window
.queue:
    JSL Battle_QueueVramUpload_0CC0
    INC.w !BattleMenu_WindowMapDirty
    JMP CODE_JP_C1103D              ; → shared RTS at $103D

; ==================================================================
; BattleMenu_UpdateTechWindow ($C10C83–$C10E59, 471 bytes)
; ==================================================================
; Tech-window refresh (submenu 1, after UpdateTechMpAvail):
; 1. BattleMenu_RenderTechListRows draws the visible lines into the tech
;    text buffer; its tile bytes are copied to the window map
;    (BattleMenu_TechTile; the attributes there come from UpdateTechMpAvail).
; 2. Columns 21-29 of all 6 rows come from !BattleRom_TechBorder
;    (frame with the "MP" header).
; 3. For each present PC slot 0/1/2 (window rows 1/3/5): its current MP
;    as two digits at cols 24-25 and blank cost cells 29-30; for an
;    absent PC only col 27 is blanked.
; 4. Copies the Tech_MenuEntry under the cursor to Tech_CursorEntry
;    (all $FF, plus PC slot 1's cost cells (row 3), when the line has no
;    entry) and
;    writes its MP cost for each involved PC at cols 29-30 of that PC's
;    row, the tens digit suppressed when zero.
; 5. Falls through into BattleMenu_DrawTechCursorRow.
; Entry: M=1, X=0, DB=$7E; !BattleMenu_ActivePc = PC shown
; Exit:  M=1 (via BattleMenu_DrawTechCursorRow → CODE_JP_C1103D)
; Callees: BattleMenu_RenderTechListRows, BattleMsg_FormatTwoDigits,
;          BattleMsg_BlankLeadingZeros, BattleMenu_DrawTechCursorRow (fall-through)
; Direct-page roles (!BattleMenu_TechListBase as in RenderTechListRows):
!BattleMenu_BorderRow = !BattleTmp_80     ; 1-2 B: frame row being copied
!BattleMenu_BorderCol = !BattleTmp_81     ; 1 B: frame column being copied
!BattleMenu_TechEntry = !BattleTmp_80     ; 1 B: menu-entry index under the cursor, then its record offset
!BattleMenu_TechEntryBase = !BattleTmp_AF ; 2 B: offset of the PC's Tech_MenuEntry block (+ entry offset)
BattleMenu_UpdateTechWindow:
    JSR BattleMenu_RenderTechListRows

    ; Copy the tile bytes of the tech text buffer to the window map
    ; (both have tile/attribute pairs; X and Y step by 2)
    TDC
    TAY
    TAX
.copy_loop:
    LDA.w BattleMenu_TechTextTile(0,0),X
    STA.w BattleMenu_TechTile(0,0),Y
    INX
    INX
    INY
    INY
    CPY.w #!BattleMenu_WindowBytes
    BNE .copy_loop

    ; Frame columns 21-29 of every row from !BattleRom_TechBorder
    TDC
    TAX
    TAY
    STX.b !BattleMenu_BorderRow
.border_row:
    STZ.b !BattleMenu_BorderCol
.border_col:
    LDA.l !BattleRom_TechBorder,X
    STA.w BattleMenu_TechTile(0,21),Y
    INX
    INY
    INY
    INC.b !BattleMenu_BorderCol
    LDA.b !BattleMenu_BorderCol
    CMP.b #!BattleMenu_TechBorderCols
    BNE .border_col
    REP #$21                        ; M=0, C=0 for 16-bit add
    TYA
    ADC.w #!BattleMenu_TechBorderSkip ; rest of the row
    TAY
    TDC
    SEP #$20                        ; M=1
    INC.b !BattleMenu_BorderRow
    LDA.b !BattleMenu_BorderRow
    CMP.b #!BattleMenu_WindowRows
    BNE .border_row

    ; PC slot 0's MP (window row 1)
    LDA.w !Battler_Present
    BEQ .slot0_mp_absent
    REP #$20                        ; M=0
    LDA.w BattlerStats.CurMp        ; (16-bit)
    STA.w !BattleMsg_NumValue
    JSR BattleMsg_FormatTwoDigits   ; → M=1
    JSR BattleMsg_BlankLeadingZeros
    LDA.w !BattleMsg_Digit10
    STA.w BattleMenu_TechTile(1,24)
    LDA.w !BattleMsg_Digit1
    STA.w BattleMenu_TechTile(1,25)
    LDA.b #!BattleUI_TileBlank
    STA.w BattleMenu_TechTile(1,29) ; cost cells
    STA.w BattleMenu_TechTile(1,30)
    BRA .slot1_check
.slot0_mp_absent:
    LDA.b #!BattleUI_TileBlank
    STA.w BattleMenu_TechTile(1,27)

    ; PC slot 1's MP (window row 3)
.slot1_check:
    LDA.w !Battler_Present+1
    BEQ .slot1_mp_absent
    REP #$20                        ; M=0
    LDA.w BattlerStats[1].CurMp     ; (16-bit)
    STA.w !BattleMsg_NumValue
    JSR BattleMsg_FormatTwoDigits   ; → M=1
    JSR BattleMsg_BlankLeadingZeros
    LDA.w !BattleMsg_Digit10
    STA.w BattleMenu_TechTile(3,24)
    LDA.w !BattleMsg_Digit1
    STA.w BattleMenu_TechTile(3,25)
    LDA.b #!BattleUI_TileBlank
    STA.w BattleMenu_TechTile(3,29)
    STA.w BattleMenu_TechTile(3,30)
    BRA .slot2_check
.slot1_mp_absent:
    LDA.b #!BattleUI_TileBlank
    STA.w BattleMenu_TechTile(3,27)

    ; PC slot 2's MP (window row 5)
.slot2_check:
    LDA.w !Battler_Present+2
    BEQ .slot2_mp_absent
    REP #$20                        ; M=0
    LDA.w BattlerStats[2].CurMp     ; (16-bit)
    STA.w !BattleMsg_NumValue
    JSR BattleMsg_FormatTwoDigits   ; → M=1
    JSR BattleMsg_BlankLeadingZeros
    LDA.w !BattleMsg_Digit10
    STA.w BattleMenu_TechTile(5,24)
    LDA.w !BattleMsg_Digit1
    STA.w BattleMenu_TechTile(5,25)
    LDA.b #!BattleUI_TileBlank
    STA.w BattleMenu_TechTile(5,29)
    STA.w BattleMenu_TechTile(5,30)
    BRA .cursor_resolve
.slot2_mp_absent:
    LDA.b #!BattleUI_TileBlank
    STA.w BattleMenu_TechTile(5,27)

    ; Menu entry under the cursor: !Tech_ListEntry[list base + scroll + row]
.cursor_resolve:
    LDA.w !BattleMenu_ActivePc
    TAX
    LDA.l !BattleRom_TechListBase,X
    STA.b !BattleMenu_TechListBase
    CLC
    LDA.w !Pc_TechScroll,X
    ADC.w !Pc_TechRow,X
    CLC
    ADC.b !BattleMenu_TechListBase
    TAX
    LDA.w !Tech_ListEntry,X
    CMP.b #!Tech_NoEntry
    BNE .slot_present
    ; no entry on this line: A = $FF into PC slot 1's cost cells (row 3) and the copy
    STA.w BattleMenu_TechTile(3,29)
    STA.w BattleMenu_TechTile(3,30)
    STA.w Tech_CursorEntry.TechId
    STA.w Tech_CursorEntry.TargetMode
    STA.w Tech_CursorEntry.Flags
    STA.w Tech_CursorEntry.MpCost0
    STA.w Tech_CursorEntry.Partners
    STA.w Tech_CursorEntry.MpCost1
    STA.w Tech_CursorEntry.MpCost2
    JMP BattleMenu_DrawTechCursorRow

.slot_present:
    ; record offset = TechEntryBase[PC] + TechEntryOffset[entry]
    STA.b !BattleMenu_TechEntry     ; menu-entry index
    LDA.w !BattleMenu_ActivePc
    ASL A
    TAX
    LDA.l !BattleRom_TechEntryBase,X
    STA.b !BattleMenu_TechEntryBase
    LDA.l !BattleRom_TechEntryBase+1,X
    STA.b !BattleMenu_TechEntryBase+1
    LDA.b !BattleMenu_TechEntry
    TAX
    LDA.l !BattleRom_TechEntryOffset,X ; index × 7
    STA.b !BattleMenu_TechEntry
    CLC
    LDA.b !BattleMenu_TechEntryBase
    ADC.b !BattleMenu_TechEntry
    STA.b !BattleMenu_TechEntryBase
    LDA.b !BattleMenu_TechEntryBase+1
    ADC #$00
    STA.b !BattleMenu_TechEntryBase+1
    LDX.b !BattleMenu_TechEntryBase
    LDA.w Tech_MenuEntry.TechId,X   ; copy the 7-byte entry
    STA.w Tech_CursorEntry.TechId
    LDA.w Tech_MenuEntry.TargetMode,X
    STA.w Tech_CursorEntry.TargetMode
    LDA.w Tech_MenuEntry.Flags,X
    STA.w Tech_CursorEntry.Flags
    LDA.w Tech_MenuEntry.MpCost0,X
    STA.w Tech_CursorEntry.MpCost0
    LDA.w Tech_MenuEntry.Partners,X
    STA.w Tech_CursorEntry.Partners
    LDA.w Tech_MenuEntry.MpCost1,X
    STA.w Tech_CursorEntry.MpCost1
    LDA.w Tech_MenuEntry.MpCost2,X
    STA.w Tech_CursorEntry.MpCost2

    ; MP cost for each PC involved (cost byte >= $80 = not involved)
    LDA.w Tech_CursorEntry.MpCost0
    BMI .check_slot1_cost            ; PC slot 0 not involved
    REP #$20                        ; M=0 (B is 0: zero-extended)
    STA.w !BattleMsg_NumValue
    JSR BattleMsg_FormatTwoDigits   ; → M=1
    LDA.w !BattleMsg_Digit10
    CMP.b #!BattleMsg_GlyphZero     ; tens digit zero?
    BNE .slot0_two_digits
    LDA.b #!BattleUI_TileBlank      ; yes: one digit, left-aligned
    STA.w BattleMenu_TechTile(1,30)
    LDA.w !BattleMsg_Digit1
    STA.w BattleMenu_TechTile(1,29)
    BRA .check_slot1_cost
.slot0_two_digits:                       ; (UNREACH_C10DFD in the reference)
    STA.w BattleMenu_TechTile(1,29)
    LDA.w !BattleMsg_Digit1
    STA.w BattleMenu_TechTile(1,30)

.check_slot1_cost:
    LDA.w Tech_CursorEntry.MpCost1
    BMI .check_slot2_cost            ; PC slot 1 not involved
    REP #$20
    STA.w !BattleMsg_NumValue
    JSR BattleMsg_FormatTwoDigits   ; → M=1
    LDA.w !BattleMsg_Digit10
    CMP.b #!BattleMsg_GlyphZero
    BNE .slot1_two_digits
    LDA.b #!BattleUI_TileBlank
    STA.w BattleMenu_TechTile(3,30)
    LDA.w !BattleMsg_Digit1
    STA.w BattleMenu_TechTile(3,29)
    BRA .check_slot2_cost
.slot1_two_digits:                       ; (UNREACH_C10E27 in the reference)
    STA.w BattleMenu_TechTile(3,29)
    LDA.w !BattleMsg_Digit1
    STA.w BattleMenu_TechTile(3,30)

.check_slot2_cost:
    LDA.w Tech_CursorEntry.MpCost2
    BMI BattleMenu_DrawTechCursorRow ; PC slot 2 not involved
    REP #$20
    STA.w !BattleMsg_NumValue
    JSR BattleMsg_FormatTwoDigits   ; → M=1
    LDA.w !BattleMsg_Digit10
    CMP.b #!BattleMsg_GlyphZero
    BNE .slot2_two_digits
    LDA.b #!BattleUI_TileBlank
    STA.w BattleMenu_TechTile(5,30)
    LDA.w !BattleMsg_Digit1
    STA.w BattleMenu_TechTile(5,29)
    BRA BattleMenu_DrawTechCursorRow
.slot2_two_digits:                       ; (UNREACH_C10E51 in the reference)
    STA.w BattleMenu_TechTile(5,29)
    LDA.w !BattleMsg_Digit1
    STA.w BattleMenu_TechTile(5,30)
    ; fall through into BattleMenu_DrawTechCursorRow at $0E5A

; ==================================================================
; BattleMenu_DrawTechCursorRow ($C10E5A–$C10EB9, 96 bytes)
; ==================================================================
; Clears the cursor columns, then (unless a target is being selected)
; draws the 2×2 row cursor ($60-$63) at the shown PC's !Pc_TechRow,
; placed through !BattleRom_TechCursorCell. With the info-panel setting
; on, shows the tech under the cursor. Queues the tech window upload and,
; once after the list opens (!BattleMenu_TechWindowNew), copies the tech
; box frame (!BattleRom_TechBoxMap) into !BattleMenu_WindowMap.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1 (via CODE_JP_C1103D)
; Callees: BattleMenu_ClearTechCursorTiles, BattleMsg_ShowFromTableCC3A09Vec,
;          Battle_QueueVramUpload_A6E1
!BattleMenu_TechCursorRow = !BattleTmp_80 ; 1 B: !Pc_TechRow of the active PC
BattleMenu_DrawTechCursorRow:
    LDA.w !BattleMenu_ActivePc
    TAX
    LDA.w !Pc_TechRow,X
    STA.b !BattleMenu_TechCursorRow
    JSR BattleMenu_ClearTechCursorTiles
    LDA.w !BattleMenu_TargetSelect
    BNE .skip_draw                  ; selecting a target → no row cursor
    LDA.b !BattleMenu_TechCursorRow
    ASL A
    TAX
    REP #$20                        ; M=0: 16-bit table entry
    LDA.l !BattleRom_TechCursorCell,X ; map offset of the cursor
    TAY
    TDC
    SEP #$20                        ; M=1
    LDA.b #!BattleMenu_TileCursorTL
    STA.w BattleMenu_TechTile(0,0),Y ; cursor top-left
    LDA.b #!BattleMenu_TileCursorTR
    STA.w BattleMenu_TechTile(0,1),Y ; cursor top-right
    LDA.b #!BattleMenu_TileCursorBL
    STA.w BattleMenu_TechTile(1,0),Y ; cursor bottom-left
    LDA.b #!BattleMenu_TileCursorBR
    STA.w BattleMenu_TechTile(1,1),Y ; cursor bottom-right
.skip_draw:
    LDA.w !BattleMenu_CfgInfoPanel
    BPL .queue_upload               ; info panel off
    LDA.w Tech_CursorEntry.TechId
    JSL BattleMsg_ShowFromTableCC3A09Vec
.queue_upload:
    JSL Battle_QueueVramUpload_A6E1
    LDA.w !BattleMenu_TechWindowNew
    BEQ .done
    TDC
    TAX
.techbox_loop:
    LDA.l !BattleRom_TechBoxMap,X
    STA.w !BattleMenu_WindowMap,X
    INX
    CPX.w #!BattleMenu_WindowBytes
    BNE .techbox_loop
    INC.w !BattleMenu_WindowMapDirty
    STZ.w !BattleMenu_TechWindowNew
.done:
    JMP CODE_JP_C1103D              ; → shared RTS at $103D

; ==================================================================
; BattleMenu_ClearTechCursorTiles ($C10EBA–$C10EE0, 39 bytes)
; ==================================================================
; Blanks cols 1-2 (the row-cursor columns) of all 6 tech-window rows.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; A=$FF; X/Y unchanged
; No JSR/JSL calls.
BattleMenu_ClearTechCursorTiles:
    LDA.b #!BattleUI_TileBlank
    STA.w BattleMenu_TechTile(0,1)
    STA.w BattleMenu_TechTile(0,2)
    STA.w BattleMenu_TechTile(1,1)
    STA.w BattleMenu_TechTile(1,2)
    STA.w BattleMenu_TechTile(2,1)
    STA.w BattleMenu_TechTile(2,2)
    STA.w BattleMenu_TechTile(3,1)
    STA.w BattleMenu_TechTile(3,2)
    STA.w BattleMenu_TechTile(4,1)
    STA.w BattleMenu_TechTile(4,2)
    STA.w BattleMenu_TechTile(5,1)
    STA.w BattleMenu_TechTile(5,2)
    RTS

; ==================================================================
; BattleMenu_UpdateTechMpAvail ($C10EE1–$C1103D, 349 bytes)
; ==================================================================
; Grades the 3 visible tech-list lines (submenu 1) and colours each line
; in the window map: palette 2 = usable, palette 3 = greyed.
;   - Line code with the high nibble $F (special line): the "Double
;     Technique" header is greyed with fewer than 2 PCs in the roster,
;     "Triple Technique" with fewer than 3; other special codes keep
;     palette 2.
;   - Real entry (via !Tech_ListEntry and the PC's Tech_MenuEntry block):
;     greyed when any involved PC's current MP is below its cost, when a
;     partner (Partners nibbles) is not menu-ready, when the shown PC has
;     !Pc_LockStatus set, or for tech id $74 unless !Battle_Unk1C48 says
;     $42; else usable. The verdict is also kept in the entry's Flags
;     bit 7 (TechConfirm checks it).
;   - The attribute goes to 18 cells of both rows of the line, from the
;     cell !BattleRom_TechRowMapOffset gives (col 3).
;   - After the 3rd line: !BattleMenu_TechAvailDone = 1.
; Entry: M=1, X=0, DB=$7E; !BattleMenu_ActivePc = PC shown
; Exit:  M=1 (falls into the shared RTS CODE_JP_C1103D)
; Callees: BattleSys_SlotMenuReadyPredicate, Battle_ShiftRight4
; Direct-page roles (!BattleMenu_TechEntryBase as in UpdateTechWindow):
!BattleMenu_MpListIdx = !BattleTmp_86     ; 2 B: !Tech_ListCode index of the row being graded
!BattleMenu_MpPc0 = !BattleTmp_96         ; 2 B: PC slot 0's current MP
!BattleMenu_MpPc1 = !BattleTmp_98         ; 2 B: PC slot 1's current MP
!BattleMenu_MpPc2 = !BattleTmp_9A         ; 2 B: PC slot 2's current MP
!BattleMenu_MpRow = !BattleTmp_82         ; 1-2 B: visible row 0-2
!BattleMenu_MpRowCell = !BattleTmp_84     ; 2 B: map offset of the row (BattleRom_TechRowMapOffset)
!BattleMenu_MpRowAttr = !BattleTmp_94     ; 1 B: attribute chosen for the row
!BattleMenu_MpEntry = !BattleTmp_88       ; 2 B: Tech_MenuEntry offset of the row's entry
!BattleMenu_MpPartners = !BattleTmp_81    ; 1 B: the entry's Partners byte
!BattleMenu_ReadySlotArg = !BattleTmp_80  ; 1 B: PC slot tested by BattleSys_SlotMenuReadyPredicate
BattleMenu_UpdateTechMpAvail:
    LDA.w !BattleMenu_ActivePc
    ASL A
    TAX
    LDA.l !BattleRom_TechEntryBase,X ; PC's Tech_MenuEntry block
    STA.b !BattleMenu_TechEntryBase
    LDA.l !BattleRom_TechEntryBase+1,X
    STA.b !BattleMenu_TechEntryBase+1
    LDA.w !BattleMenu_ActivePc
    TAX
    TAY
    LDA.l !BattleRom_TechListBase,X ; PC's first list line
    STA.b !BattleMenu_MpListIdx
    LDA.w !Pc_TechScroll,Y
    CLC
    ADC.b !BattleMenu_MpListIdx
    TAX
    STX.b !BattleMenu_MpListIdx     ; first visible line (16-bit)
    LDA.w BattlerStats.CurMp        ; copy the three PCs' MP
    STA.b !BattleMenu_MpPc0
    LDA.w BattlerStats.CurMp+1
    STA.b !BattleMenu_MpPc0+1
    LDA.w BattlerStats[1].CurMp
    STA.b !BattleMenu_MpPc1
    LDA.w BattlerStats[1].CurMp+1
    STA.b !BattleMenu_MpPc1+1
    LDA.w BattlerStats[2].CurMp
    STA.b !BattleMenu_MpPc2
    LDA.w BattlerStats[2].CurMp+1
    STA.b !BattleMenu_MpPc2+1
    TDC
    TAX
    STX.b !BattleMenu_MpRow         ; visible row 0
    ; per-row loop (re-entered via JMP from the loop tail):
CODE_JP_C10F28:
    LDA.b !BattleMenu_MpRow
    ASL A
    TAX
    LDA.l !BattleRom_TechRowMapOffset,X
    STA.b !BattleMenu_MpRowCell
    LDA.l !BattleRom_TechRowMapOffset+1,X
    STA.b !BattleMenu_MpRowCell+1
    LDA.b #!BattleUI_AttrPal2       ; default: usable
    STA.b !BattleMenu_MpRowAttr
    LDX.b !BattleMenu_MpListIdx
    LDA.w !Tech_ListCode,X
    AND.b #!Tech_CodeSpecialMask
    CMP.b #!Tech_CodeSpecialMask
    BNE _ump_check_battler          ; a real entry
    ; special line ($Fx): only the two headers are graded
    LDA.w !Tech_ListCode,X
    CMP.b #!Tech_CodeDoubleHeader
    BNE _ump_check_fd
    LDA.w !BattleMenu_ReadyCount
    CMP.b #!BattleMenu_DoubleTechPcs
    BCC _ump_set_grey               ; fewer than 2 PCs ready → grey
    BRA CODE_C10F66_JMP             ; else keep palette 2
_ump_check_fd:
    CMP.b #!Tech_CodeTripleHeader
    BNE CODE_C10F66_JMP             ; other special line → keep palette 2
    LDA.w !BattleMenu_ReadyCount
    CMP.b #!BattleMenu_TripleTechPcs
    BCS CODE_C10F66_JMP             ; 3 PCs ready → keep palette 2
_ump_set_grey:                     ; header line: grey
    LDA.b #!BattleUI_AttrPal3
    STA.b !BattleMenu_MpRowAttr
CODE_C10F66_JMP:                    ; several branches converge here
    JMP CODE_JP_C1100F              ; → colour the line

_ump_check_battler:
    ; Tech_MenuEntry offset of the line's entry
    LDA.w !Tech_ListEntry,X         ; menu-entry index
    TAX
    LDA.l !BattleRom_TechEntryOffset,X ; index × 7
    CLC
    ADC.b !BattleMenu_TechEntryBase ; + PC's block
    STA.b !BattleMenu_MpEntry
    LDA.b !BattleMenu_TechEntryBase+1
    ADC #$00
    STA.b !BattleMenu_MpEntry+1
    LDX.b !BattleMenu_MpEntry

    ; PC slot 0's MP vs its cost
    LDA.w Tech_MenuEntry.MpCost0,X
    BMI _ump_pc1_ok                 ; $80+ → not involved
    SEC
    LDA.b !BattleMenu_MpPc0
    SBC.w Tech_MenuEntry.MpCost0,X
    LDA.b !BattleMenu_MpPc0+1
    SBC #$00
    BCC _ump_set_unusable           ; borrow → can't afford

_ump_pc1_ok:
    ; PC slot 1's MP vs its cost
    LDA.w Tech_MenuEntry.MpCost1,X
    BMI _ump_pc2_ok
    SEC
    LDA.b !BattleMenu_MpPc1
    SBC.w Tech_MenuEntry.MpCost1,X
    LDA.b !BattleMenu_MpPc1+1
    SBC #$00
    BCC _ump_set_unusable

_ump_pc2_ok:
    ; PC slot 2's MP vs its cost
    LDA.w Tech_MenuEntry.MpCost2,X
    BMI _ump_pc3_ok
    SEC
    LDA.b !BattleMenu_MpPc2
    SBC.w Tech_MenuEntry.MpCost2,X
    LDA.b !BattleMenu_MpPc2+1
    SBC #$00
    BCC _ump_set_unusable

_ump_pc3_ok:
    ; partners must be menu-ready
    LDA.w Tech_MenuEntry.Partners,X
    STA.b !BattleMenu_MpPartners
    CMP.b #!Tech_NoPartners
    BEQ _ump_slot_ready             ; single tech: no partners to check
    AND.b #!Tech_PartnerLoMask      ; first partner slot
    STA.b !BattleMenu_ReadySlotArg
    JSR BattleSys_SlotMenuReadyPredicate ; A=0 if ready
    BNE _ump_set_unusable           ; not ready → grey
    LDA.b !BattleMenu_MpPartners
    AND.b #!Tech_PartnerHiMask
    CMP.b #!Tech_PartnerHiMask      ; no second partner (double tech)?
    BEQ _ump_slot_ready
    JSR Battle_ShiftRight4          ; second partner slot
    STA.b !BattleMenu_ReadySlotArg
    JSR BattleSys_SlotMenuReadyPredicate
    BNE _ump_set_unusable

_ump_slot_ready:
    ; the shown PC must not be locked; tech $74 needs one more check
    LDA.w !BattleMenu_ActivePc
    TAX
    LDA.w !Pc_LockStatus,X
    BNE _ump_set_unusable           ; locked → grey
    LDX.b !BattleMenu_MpEntry
    LDA.w Tech_MenuEntry.TechId,X
    CMP.b #!Tech_IdUnk74
    BNE _ump_write_bright
    LDX.w !Battle_UnkA0FF
    LDA.w !Battle_Unk1C48,X
    CMP.b #!Battle_Unk1C48Wanted
    BNE _ump_set_unusable           ; fail → grey

_ump_write_bright:
    LDX.b !BattleMenu_MpEntry
    LDA.w Tech_MenuEntry.Flags,X
    AND.b #!Tech_FlagUsableMask     ; usable
    STA.w Tech_MenuEntry.Flags,X
    LDA.b #!BattleUI_AttrPal2
    STA.b !BattleMenu_MpRowAttr
    BRA CODE_JP_C1100F              ; → colour the line

_ump_set_unusable:                 ; can't afford / partner not ready / locked / tech $74 check failed
    LDX.b !BattleMenu_MpEntry
    LDA.w Tech_MenuEntry.Flags,X
    ORA.b #!Tech_FlagUnusable       ; unusable
    STA.w Tech_MenuEntry.Flags,X
    LDA.b #!BattleUI_AttrPal3       ; greyed
    STA.b !BattleMenu_MpRowAttr
    ; fall through to CODE_JP_C1100F

CODE_JP_C1100F:                     ; colour both rows of the line
    LDX.b !BattleMenu_MpRowCell
    LDY.w #!BattleMenu_TechRowCells
    LDA.b !BattleMenu_MpRowAttr
.col1_loop:
    STA.w BattleMenu_TechAttr(0,0),X
    INX
    INX
    DEY
    BNE .col1_loop
    LDX.b !BattleMenu_MpRowCell
    LDY.w #!BattleMenu_TechRowCells
.col2_loop:
    STA.w BattleMenu_TechAttr(1,0),X
    INX
    INX
    DEY
    BNE .col2_loop
    INC.b !BattleMenu_MpListIdx
    INC.b !BattleMenu_MpRow
    LDA.b !BattleMenu_MpRow
    CMP.b #!BattleMenu_ListRows
    BEQ .done
    JMP CODE_JP_C10F28              ; next row
.done:
    LDA #$01
    STA.w !BattleMenu_TechAvailDone ; rows graded
CODE_JP_C1103D:                     ; shared exit RTS (jumped to from multiple routines)
    RTS

; ==================================================================
; BattleSys_SlotMenuReadyPredicate ($C1103E–$C1104D, 16 bytes)
; ==================================================================
; Returns A=0 if PC slot !BattleMenu_ReadySlotArg is menu-ready: in the
; roster (!BattleMenu_Roster entry not negative) and !Pc_LockStatus clear;
; nonzero otherwise.
; Entry: M=1, X=0 (16-bit), DB=$7E; !BattleMenu_ReadySlotArg = PC slot
; Exit:  M=1; A = 0 (ready) or nonzero (not ready); X clobbered
; No JSR/JSL calls.
BattleSys_SlotMenuReadyPredicate:
    LDA.b !BattleMenu_ReadySlotArg
    TAX
    LDA.w !BattleMenu_Roster,X
    BMI .not_ready                  ; not in the roster
    TAX
    LDA.w !Pc_LockStatus,X
    BNE .not_ready                  ; locked
    TDC                             ; A = 0 (ready)
.not_ready:
    RTS

; $C1:104E — BattleMsg_BlankLeadingZeros (32 bytes, $104E–$106D)
; Leading-zero suppression for the number formatter's digits.
; Hundreds digit is the zero glyph → blank it. Then, if the tens digit is
; the zero glyph and the hundreds digit is blank, blank the tens too.
; The ones digit is never blanked.
; Typically called immediately after BattleMsg_FormatNumberDigits.
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; A clobbered; X/Y unchanged
; No JSR/JSL calls.
org $C1104E
BattleMsg_BlankLeadingZeros:
    LDA.w !BattleMsg_Digit100
    CMP.b #!BattleMsg_GlyphZero
    BNE .check_tens                 ; no → keep, check tens
    LDA.b #!BattleUI_TileBlank
    STA.w !BattleMsg_Digit100       ; blank hundreds
.check_tens:
    LDA.w !BattleMsg_Digit10
    CMP.b #!BattleMsg_GlyphZero
    BNE .done                       ; no → done
    LDA.w !BattleMsg_Digit100       ; was hundreds already blanked?
    CMP.b #!BattleUI_TileBlank
    BNE .done                       ; no → keep tens
    LDA.b #!BattleUI_TileBlank
    STA.w !BattleMsg_Digit10        ; blank tens
.done:
    RTS

; ==================================================================
; BattleMenu_LoadCommandWindowMap ($C11C3A–$C11C49, 16 bytes)
; ==================================================================
; Copies the $180-byte command window map (!BattleRom_CommandWindowMap,
; bank $D1) into !BattleMenu_WindowMap. Used whenever the shown PC changes
; or a submenu closes.
; Entry: M=1, X=0 (16-bit), DB=$7E
; Exit:  M=1; X=$0180; A = last byte copied; Y unchanged
; No JSR/JSL calls.
org $C11C3A
BattleMenu_LoadCommandWindowMap:
    TDC
    TAX
.load_loop:
    LDA.l !BattleRom_CommandWindowMap,X
    STA.w !BattleMenu_WindowMap,X
    INX
    CPX.w #!BattleMenu_WindowBytes
    BNE .load_loop
    RTS

; ==================================================================
; BattleMenu_RefreshIfDirtyL ($C110E3–$C110F9, 23 bytes)
; ==================================================================
; JSL-entry twin of BattleMenu_RefreshIfDirtyAndTick, reached via the
; bank's cross-bank entry-vector table: JSL $C10012 -> JMP $C110E3.
; If !BattleMenu_Dirty is set: clear it and rerun the full
; menu rebuild chain (dequeue ready battler, update windows, process
; input, redraw cursor overlay). Returns with RTL (long return) since
; callers reach this via JSL through the $C10012 vector, not a
; same-bank JSR.
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; registers clobbered by callees
; Callees: BattleMenu_DequeueReadyBattler, BattleMenu_UpdateWindows,
;          BattleMenu_ProcessInput, BattleMenu_UpdateCursorOverlay
org $C110E3
BattleMenu_RefreshIfDirtyL:
    LDA.w !BattleMenu_Dirty
    BEQ .exit
    STZ.w !BattleMenu_Dirty
    STZ.b !Battle_UnkE5
    JSR BattleMenu_DequeueReadyBattler
    JSR BattleMenu_UpdateWindows
    JSR BattleMenu_ProcessInput
    JSR BattleMenu_UpdateCursorOverlay
.exit:
    RTL

; ==================================================================
; BattleMenu_RefreshIfDirtyAndTick ($C110FA–$C11114, 27 bytes)
; ==================================================================
; Same-bank JSR twin of BattleMenu_RefreshIfDirtyL — identical dirty-
; flag gate and menu rebuild chain, but always follows up with a
; cross-bank per-frame service tick (BattleSys_FrameTickVec) before returning via
; plain RTS. Called from several places in the battle-phase state
; machine ($C140A3 and others) once per frame.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; registers clobbered by callees
; Callees: BattleMenu_DequeueReadyBattler, BattleMenu_UpdateWindows,
;          BattleMenu_ProcessInput, BattleMenu_UpdateCursorOverlay,
;          BattleSys_FrameTickVec
org $C110FA
BattleMenu_RefreshIfDirtyAndTick:
    LDA.w !BattleMenu_Dirty
    BEQ .tick
    STZ.w !BattleMenu_Dirty
    STZ.b !Battle_UnkE5
    JSR BattleMenu_DequeueReadyBattler
    JSR BattleMenu_UpdateWindows
    JSR BattleMenu_ProcessInput
    JSR BattleMenu_UpdateCursorOverlay
.tick:
    JSL BattleSys_FrameTickVec
    RTS

; ==================================================================
; BattleMenu_DrawCursorSprites ($C11115–$C11152, 62 bytes)
; ==================================================================
; Builds OAM sprites 0-3 (BattleOam) for the command cursor over the
; shown PC: each of the 4 template sprites in BattleRom_CursorSprite is
; offset by the PC's !Battler_ScreenX/Y, and its palette bits are
; replaced with !BattleMenu_CursorPalette. Sets the high-table byte to
; !BattleOam_CursorSizeBits (all 4 large, x bit 8 clear). Called from
; BattleMenu_ProcessInput once per frame while a menu is open.
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; X=$0010; A/Y clobbered
; No JSR/JSL calls.
org $C11115
BattleMenu_DrawCursorSprites:
    TDC
    TAX
    LDA.w !BattleMenu_ActivePc
    TAY
.loop:                              ; X = sprite × 4
    CLC
    LDA.l BattleRom_CursorSprite.X,X
    ADC.w !Battler_ScreenX,Y
    STA.w BattleOam.X,X
    CLC
    LDA.l BattleRom_CursorSprite.Y,X
    ADC.w !Battler_ScreenY,Y
    STA.w BattleOam.Y,X
    LDA.l BattleRom_CursorSprite.Tile,X
    STA.w BattleOam.Tile,X
    LDA.l BattleRom_CursorSprite.Attr,X
    AND.b #!BattleOam_AttrKeepMask  ; drop the template palette
    ORA.w !BattleMenu_CursorPalette ; use the current cursor palette
    STA.w BattleOam.Attr,X
    INX
    INX
    INX
    INX
    CPX.w #!BattleOam_CursorBytes
    BNE .loop
    LDA.b #!BattleOam_CursorSizeBits
    STA.w !BattleOam_HighTable
    RTS

; ==================================================================
; BattleMenu_ProcessInput ($C11153–$C111E0, 142 bytes)
; ==================================================================
; Battle command-window input handler, called once per frame from the
; menu dirty-flag gates (RefreshIfDirtyL/AndTick). Reads the pad-edge
; bytes (!Battle_PadEdgeButtons / !Battle_PadEdgeDpad, pressed this
; frame) and dispatches:
;   - no PC shown (!BattleMenu_ActivePc < 0) → Battle_ClearPadEdges;
;     target selection running → BattleMenu_TargetSelectInput
;   - !BattleMenu_Submenu 1 / 2 → tech / item list input (with
;     !Battle_MenuTimeHold = !Battle_CfgBattleMode)
;   - main menu: !BattleMenu_UnkA862, or the alt-confirm button with
;     !BattleMenu_CfgCursorMemory on (row forced to 0, !BattleMenu_KeepRow
;     set), go straight to ConfirmCommand; otherwise Left/Right cycle the
;     PC, Up/Down move the cursor, confirm confirms
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; tail-jumps to one of several handlers, does not fall through
; Callees: Battle_MergePendingEntries1580,
;          BattleMenu_TargetSelectInput, BattleMenu_DrawCursorSprites,
;          BattleMenu_TechListInput, BattleMenu_ItemListInput,
;          BattleMenu_ConfirmCommand, BattleMenu_CycleActivePcPrev,
;          BattleMenu_CycleActivePcNext, BattleMenu_CursorUp,
;          BattleMenu_CursorDown, Battle_PlaySfx0, Battle_ClearPadEdges
org $C11153
BattleMenu_ProcessInput:
    JSL Battle_MergePendingEntries1580
    LDA.w !BattleMenu_ActivePc
    BPL .slot_valid
    JMP Battle_ClearPadEdges        ; no PC shown -> clear pad-edge bytes, return
.slot_valid:
    LDA.w !BattleMenu_TargetSelect
    BEQ .not_targeting
    JMP BattleMenu_TargetSelectInput
.not_targeting:
    JSR BattleMenu_DrawCursorSprites
    LDA.w !BattleMenu_Submenu       ; 0=main, 1=tech, 2=item
    BEQ .main_menu
    DEC
    BNE .item_menu
    LDA.w !Battle_CfgBattleMode
    STA.w !Battle_MenuTimeHold
    JMP BattleMenu_TechListInput
.item_menu:
    LDA.w !Battle_CfgBattleMode
    STA.w !Battle_MenuTimeHold
    JMP BattleMenu_ItemListInput
.main_menu:
    STZ.w !BattleUI_ForceDigitRefresh
    STZ.w !Battle_MenuTimeHold
    LDA.w !BattleMenu_UnkA862
    BNE .confirm                    ; set -> confirm without polling
    LDA.w !BattleMenu_CfgCursorMemory
    BEQ .poll_dpad
    LDA.w !BattleMenu_ActivePc
    TAX
    LDA.b !Battle_PadEdgeButtons
    AND.b #!Battle_PadAltConfirm
    BEQ .poll_dpad
    INC.w !BattleMenu_KeepRow
    TDC
    STA.w !Pc_MenuRow,X             ; force cursor row 0 for this slot
    JMP BattleMenu_ConfirmCommand
.poll_dpad:
    LDA.b !Battle_PadEdgeDpad
    AND.b #!Battle_DpadLeft
    BEQ .poll_up
    JMP BattleMenu_CycleActivePcPrev
.poll_up:
    LDA.b !Battle_PadEdgeDpad
    AND.b #!Battle_DpadUp
    BEQ .poll_down
    JSR Battle_PlaySfx0
    JMP BattleMenu_CursorUp
.poll_down:
    LDA.b !Battle_PadEdgeDpad
    AND.b #!Battle_DpadDown
    BEQ .poll_right
    JSR Battle_PlaySfx0
    JMP BattleMenu_CursorDown
.poll_right:
    LDA.b !Battle_PadEdgeDpad
    AND.b #!Battle_DpadRight
    BEQ .poll_confirm
    JMP BattleMenu_CycleActivePcNext
.poll_confirm:
    LDA.b !Battle_PadEdgeButtons
    AND.b #!Battle_PadConfirm
    BEQ .no_input
    JSR Battle_PlaySfx0
.confirm:
    JMP BattleMenu_ConfirmCommand
.no_input:
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_CycleActivePcPrev ($C111E1–$C11217, 55 bytes)
; ==================================================================
; Left D-pad: step !BattleMenu_RosterIdx back (wrap 0..2), skipping
; roster entries that are negative. Plays sound 0 (Battle_PlaySfx0;
; inferred to be the cursor sound, not settled) unless only one PC is in
; the roster. Carries the previously shown PC's !Pc_MenuRow to the new
; one, unless !BattleMenu_CfgCursorMemory is set, in which case the new
; PC keeps its own row and the OLD PC's row is restored from
; !Pc_SavedMenuRow. The reference disassembly marks that path as
; unreachable, but the battle init code at $CC:E39C sets
; CfgCursorMemory from config byte $2991 bit 6, so it runs whenever that
; setting is on (inferred: the cursor-memory option).
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: Battle_PlaySfx0, Battle_ClearPadEdges
org $C111E1
BattleMenu_CycleActivePcPrev:
    LDA.w !BattleMenu_ReadyCount
    DEC
    BEQ .retry                      ; only 1 PC -> no sound
    JSR Battle_PlaySfx0
.retry:
    DEC.w !BattleMenu_RosterIdx     ; wrap 0..2
    LDA.w !BattleMenu_RosterIdx
    BPL .have_index
    LDA.b #!Battle_LastPcSlot
    STA.w !BattleMenu_RosterIdx
.have_index:
    TAX
    LDA.w !BattleMenu_Roster,X      ; entry valid?
    BMI .retry                      ; no -> keep decrementing
    TAX
    LDA.w !BattleMenu_ActivePc      ; previously shown PC
    TAY
    LDA.w !BattleMenu_CfgCursorMemory
    BNE .restore_saved_row          ; cursor-memory setting on
    LDA.w !Pc_MenuRow,Y             ; carry cursor row from old slot
    STA.w !Pc_MenuRow,X
    BRA .done
.restore_saved_row:
    LDA.w !Pc_SavedMenuRow,Y        ; old PC's remembered row
    STA.w !Pc_MenuRow,Y
.done:
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_CycleActivePcNext ($C11218–$C1124F, 56 bytes)
; ==================================================================
; Right D-pad: mirror of CycleActivePcPrev — steps !BattleMenu_RosterIdx
; forward (wrap at 3 back to 0) instead; the same sound 0 and the same
; cursor-memory handling.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: Battle_PlaySfx0, Battle_ClearPadEdges
org $C11218
BattleMenu_CycleActivePcNext:
    LDA.w !BattleMenu_ReadyCount
    DEC
    BEQ .retry
    JSR Battle_PlaySfx0
.retry:
    INC.w !BattleMenu_RosterIdx     ; wrap at 3 -> 0
    LDA.w !BattleMenu_RosterIdx
    CMP.b #!Battle_NumPcSlots
    BNE .have_index
    STZ.w !BattleMenu_RosterIdx
    TDC
.have_index:
    TAX
    LDA.w !BattleMenu_Roster,X      ; entry valid?
    BMI .retry                      ; no -> keep incrementing
    TAX
    LDA.w !BattleMenu_ActivePc      ; previously shown PC
    TAY
    LDA.w !BattleMenu_CfgCursorMemory
    BNE .restore_saved_row          ; cursor-memory setting on
    LDA.w !Pc_MenuRow,Y             ; carry cursor row from old slot
    STA.w !Pc_MenuRow,X
    BRA .done
.restore_saved_row:
    LDA.w !Pc_SavedMenuRow,Y        ; old PC's remembered row
    STA.w !Pc_MenuRow,Y
.done:
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_CursorUp ($C11250–$C11263, 20 bytes)
; ==================================================================
; Up D-pad: step the shown PC's !Pc_MenuRow back (wrap 0..2) and flag
; the cursor redraw (!BattleUI_PanelRedraw).
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: Battle_ClearPadEdges
org $C11250
BattleMenu_CursorUp:
    LDA.w !BattleMenu_ActivePc      ; active PC slot
    TAX
    DEC.w !Pc_MenuRow,X
    BPL .done
    LDA.b #!BattleMenu_LastRow
    STA.w !Pc_MenuRow,X
.done:
    INC.w !BattleUI_PanelRedraw     ; flag redraw
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_CursorDown ($C11264–$C1127A, 23 bytes)
; ==================================================================
; Down D-pad: step the shown PC's !Pc_MenuRow forward (wrap at 3 back to
; 0) and flag the cursor redraw (!BattleUI_PanelRedraw).
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: Battle_ClearPadEdges
org $C11264
BattleMenu_CursorDown:
    LDA.w !BattleMenu_ActivePc      ; active PC slot
    TAX
    INC.w !Pc_MenuRow,X
    LDA.w !Pc_MenuRow,X
    CMP.b #!BattleMenu_ListRows
    BNE .done
    STZ.w !Pc_MenuRow,X
.done:
    INC.w !BattleUI_PanelRedraw     ; flag redraw
    JMP Battle_ClearPadEdges

; ==================================================================
; Battle_ClearPadEdges ($C1179C–$C117A0, 5 bytes)
; ==================================================================
; Clears both pad-edge bytes and returns. Shared tail used by most of the
; command-window input handlers above once they've consumed this frame's
; input.
; Entry: M=1, DB=$7E
; Exit:  M=1; !Battle_PadEdgeButtons = !Battle_PadEdgeDpad = 0
; No JSR/JSL calls.
org $C1179C
Battle_ClearPadEdges:
    STZ.b !Battle_PadEdgeButtons
    STZ.b !Battle_PadEdgeDpad
    RTS

; ==================================================================
; BattleMenu_EnqueueReadyBattler ($C11B19–$C11B54, 60 bytes)
; ==================================================================
; Service 1 of the cross-bank $C10045 service API (dispatch table at
; $C10051: service 0 -> $0023, 1 -> here, 2 -> RemoveBattlerFromReady).
; Called when battler slot !Battle_ArgSlot becomes ready for a command
; (presumably its ATB gauge filled): appends it to the ready queue that
; BattleMenu_DequeueReadyBattler later pops from.
;
; Skipped entirely if the slot is already in the roster
; (!BattleMenu_Roster entry non-negative). Otherwise: sets
; BattleCmd.State bit 7 ("waiting for a command"; the bit
; ConsumePartnerSlot/CommitAction clear) in the slot's command record
; (offset from !BattleRom_CmdOffset), appends the slot to
; !BattleMenu_ReadyQueue, resets its !Pc_MenuRow to !Pc_SavedMenuRow,
; and plays a sound through the same APU command Battle_PlaySfx0 uses,
; here with sound id $42 instead of 0 (inferred: the "turn ready" cue).
;
; Note: does not check whether the slot is already queued; callers
; are trusted not to enqueue twice.
;
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E; !Battle_ArgSlot = battler slot
; Exit:  M=1; registers clobbered
; Callees: Audio_ProcessEntry
org $C11B19
BattleMenu_EnqueueReadyBattler:
    LDA.b !Battle_ArgSlot           ; battler slot that became ready
    TAX
    LDA.w !BattleMenu_Roster,X      ; negative = not in the roster
    BPL .exit                       ; already in the roster
    LDA.l !BattleRom_CmdOffset,X    ; slot -> BattleCmd record offset
    TAX
    LDA.w BattleCmd.State,X
    ORA.b #!BattleCmd_StateWaiting
    STA.w BattleCmd.State,X
    LDA.w !BattleMenu_ReadyQueueLen ; = tail index
    TAX
    LDA.b !Battle_ArgSlot
    STA.w !BattleMenu_ReadyQueue,X  ; append to the queue
    TAX
    LDA.w !Pc_SavedMenuRow,X
    STA.w !Pc_MenuRow,X
    INC.w !BattleMenu_ReadyQueueLen
    LDA.b #!Sfx_TurnReady           ; sound id
    STA.w !Sfx_Param1
    LDA.b #!Sfx_CmdPlay
    STA.w !Sfx_Command
    LDA.b #!Sfx_Param2Default
    STA.w !Sfx_Param2
    JSL Audio_ProcessEntry
.exit:
    RTS

; ==================================================================
; Battle_PlaySfx0 ($C11B55–$C11B66, 18 bytes)
; ==================================================================
; APU command !Sfx_CmdPlay with sound id 0: fills !Sfx_Command /
; !Sfx_Param1 / !Sfx_Param2 (the same command block bank $C0's
; Audio_PlayTileSfxA fills) and calls the audio driver entry. Used when
; the cursor moves or a command is confirmed; whether sound 0 is a
; cursor beep or a stop is not settled, hence the neutral name.
; Entry: M=1, DB=$7E
; Exit:  M=1
; Callees: Audio_ProcessEntry
org $C11B55
Battle_PlaySfx0:
    STZ.w !Sfx_Param1
    LDA.b #!Sfx_CmdPlay
    STA.w !Sfx_Command
    LDA.b #!Sfx_Param2Default
    STA.w !Sfx_Param2
    JSL Audio_ProcessEntry
    RTS

; ==================================================================
; BattleMenu_ConfirmCommand ($C1127B–$C1129B, 33 bytes)
; ==================================================================
; Confirm-button dispatch: sets !BattleUI_UnkA0D7 to $FF (compared by
; BattleUI_BuildStatusBarFrame with the first selected target), calls
; BattleFx_SetPtrA2FromTable for the shown PC, then tail-jumps on that
; PC's !Pc_MenuRow (0/1/2 = Attack/Tech/Item).
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; tail-jumps to one of three row handlers, does not fall through
; Callees: BattleFx_SetPtrA2FromTable,
;          BattleMenu_ChooseAttack, BattleMenu_OpenTechList,
;          BattleMenu_OpenItemList
org $C1127B
BattleMenu_ConfirmCommand:
    LDA.b #!BattleMenu_CacheInvalid
    STA.w !BattleUI_UnkA0D7
    LDA.w !BattleMenu_ActivePc
    JSL BattleFx_SetPtrA2FromTable
    LDA.w !BattleMenu_ActivePc
    TAX
    LDA.w !Pc_MenuRow,X
    BNE .not_row0
    JMP BattleMenu_ChooseAttack
.not_row0:
    DEC
    BNE .not_row1
    JMP BattleMenu_OpenTechList
.not_row1:
    JMP BattleMenu_OpenItemList

; ==================================================================
; BattleMenu_ChooseAttack ($C1129C–$C112BB, 32 bytes)
; ==================================================================
; Row 0 (Attack) confirm: message call with "none", flags the cursor
; redraw (twice), sets !BattleTgt_Mode = attack, !BattleMenu_CmdMenu = 0,
; builds the target list, then enters target selection.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: BattleMsg_ShowMsg0BIfKeyChangedVec,
;          BattleMenu_BuildTargetList, Battle_ClearPadEdges
org $C1129C
BattleMenu_ChooseAttack:
    LDA.b #!BattleMsg_ArgNone
    JSL BattleMsg_ShowMsg0BIfKeyChangedVec
    INC.w !BattleUI_PanelRedraw
    INC.w !BattleUI_PanelRedraw     ; (twice)
    LDA.b #!BattleTgt_ModeAttack
    STA.w !BattleTgt_Mode
    STZ.w !BattleMenu_CmdMenu       ; command from the attack row
    JSR BattleMenu_BuildTargetList
    INC.w !BattleMenu_TargetMoved
    INC.w !BattleMenu_TargetSelect  ; enter target selection
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_OpenTechList ($C112BC–$C112EC, 49 bytes)
; ==================================================================
; Row 1 (Tech) confirm: unless !BattleMenu_Lock bit 0 is set, renders
; the tech list lines, builds !Tech_ListAvail, switches to the tech list
; (!BattleMenu_Submenu = !BattleMenu_CmdMenu = 1) and requests the tech
; box frame (!BattleMenu_TechWindowNew).
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: BattleMenu_RenderTechListRows, BattleMenu_BuildTechAvailFlags,
;          Battle_ClearPadEdges
org $C112BC
BattleMenu_OpenTechList:
    LDA.w !BattleMenu_Lock
    AND.b #!BattleMenu_LockTech
    BNE .exit                       ; tech list blocked -> no-op
    LDA.b #!Tech_NoPartners
    STA.w Tech_CursorEntry.Partners ; no cursor entry yet
    STZ.w !BattleUI_ForceDigitRefresh
    STZ.w !BattleMenu_TechAvailDone
    INC.w !BattleMenu_UnkA862
    JSR BattleMenu_RenderTechListRows
    JSR BattleMenu_BuildTechAvailFlags
    STZ.w !BattleMenu_UnkA862
    LDA.b #!BattleMenu_SubmenuTech
    STA.w !BattleMenu_CmdMenu       ; command from the tech list
    LDA.b #!BattleMenu_SubmenuTech
    STA.w !BattleMenu_Submenu
    STZ.w !BattleMenu_UnkA869
    INC.w !BattleMenu_TechWindowNew
.exit:
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_OpenItemList ($C112ED–$C1131F, 51 bytes)
; ==================================================================
; Row 2 (Item) confirm: unless !BattleMenu_Lock is non-zero, renders the
; item list at !BattleMenu_ItemScroll, queues the item map upload, copies
; the item box frame (!BattleRom_ItemBoxMap, "ItemBoxBattles") into
; !BattleMenu_WindowMap, and switches to the item list
; (!BattleMenu_Submenu = !BattleMenu_CmdMenu = 2).
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: BattleMenu_RenderItemListRows, Battle_QueueVramUpload_0E80,
;          Battle_ClearPadEdges
org $C112ED
BattleMenu_OpenItemList:
    LDA.w !BattleMenu_Lock
    BNE .exit                       ; item list blocked -> no-op
    STZ.w !BattleUI_ForceDigitRefresh
    LDA.b #!BattleMenu_SubmenuItem
    STA.w !BattleMenu_CmdMenu       ; command from the item list
    LDA.w !BattleMenu_ItemScroll
    STA.b !BattleMenu_ListScroll
    JSR BattleMenu_RenderItemListRows
    JSL Battle_QueueVramUpload_0E80
    TDC
    TAX
.copy_loop:
    LDA.l !BattleRom_ItemBoxMap,X
    STA.w !BattleMenu_WindowMap,X
    INX
    CPX.w #!BattleMenu_WindowBytes
    BNE .copy_loop
    INC.w !BattleMenu_WindowMapDirty
    LDA.b #!BattleMenu_SubmenuItem
    STA.w !BattleMenu_Submenu
.exit:
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_BuildTargetList ($C11F79–$C11FDC, 100 bytes)
; ==================================================================
; Records the requesting PC (!BattleTgt_Caster), resets the selection
; state (!BattleTgt_Result/CanCycle/TargetAll, two Unk bytes) and blanks
; !BattleTgt_Candidates and !BattleTgt_Selected (indices 0-11) to $FF.
; If !BattleTgt_Mode bit 7 is set and no return target is saved yet,
; saves submenu + 1 in !BattleMenu_ReturnSubmenu, switches to the main
; menu, sets !BattleUI_ForceDigitRefresh (UpdateNextPcPanel then always
; refreshes the HP/MP digits) and reloads the command window, so
; cancelling target selection comes back to the submenu.
;
; Then runs the mode's handler: mode & $7F (clamped to $20) indexes
; BattleTgt_ModeTable. If afterwards every one of the first 11
; selection entries is empty, !BattleTgt_Result gets the $FF just read
; (negative = no valid target).
;
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; X/Y clobbered
; Callees: BattleMenu_LoadCommandWindowMap; JSR (BattleTgt_ModeTable,X)
org $C11F79
BattleMenu_BuildTargetList:
    LDA.w !BattleMenu_ActivePc      ; active PC slot
    TAX
    STX.w !BattleTgt_Caster         ; remember requesting slot
    STZ.w !BattleTgt_Result         ; assume a target will be found
    STZ.w !BattleTgt_TargetAll
    STZ.w !BattleTgt_CanCycle
    STZ.w !BattleTgt_UnkA64F
    STZ.w !BattleTgt_UnkA6D8
    LDX.w #!Battle_NumSlots
    LDA.b #!BattleTgt_Empty
.clear_loop:
    STA.w !BattleTgt_Candidates,X   ; candidate list slot -> empty
    STA.w !BattleTgt_Selected,X     ; selection list slot -> empty
    DEX
    BPL .clear_loop
    LDA.w !BattleTgt_Mode           ; target mode
    BPL .have_mode
    LDA.w !BattleMenu_ReturnSubmenu ; saved submenu type (cancel target)
    BNE .have_mode
    LDA.w !BattleMenu_Submenu       ; current submenu type
    INC
    STA.w !BattleMenu_ReturnSubmenu ; save it for cancel-to-return
    STZ.w !BattleMenu_Submenu
    LDA.b #!BattleMenu_RosterRedraw
    STA.w !BattleMenu_RosterIdxDrawn
    INC.w !BattleUI_ForceDigitRefresh
    JSR BattleMenu_LoadCommandWindowMap
.have_mode:
    LDA.w !BattleTgt_Mode
    AND.b #!BattleTgt_ModeMask      ; strip high bit
    CMP.b #!BattleTgt_NumModes
    BCC .in_range
    LDA.b #!BattleTgt_LastMode      ; clamp to table size
.in_range:
    ASL                             ; word index
    TAX
    JSR (BattleTgt_ModeTable,X)     ; target-mode handler table
    TDC
    TAX
.scan_empty:
    LDA.w !BattleTgt_Selected,X     ; selection list slot
    BPL .done                       ; found a real target -> done
    INX
    CPX.w #!Battle_NumSlots
    BNE .scan_empty
    STA.w !BattleTgt_Result         ; all empty -> fallback result
.done:
    RTS

; ==================================================================
; BattleTgt_RunAreaQuery ($C11FDD–$C11FE9, 13 bytes)
; ==================================================================
; Service 7 of the cross-bank $C10045 service API (dispatch table at
; $C10051). Runs one of the area-target geometry routines, selected by
; !BattleTgt_AreaType (0-6) through the 7-entry table just below; out-of-range
; selectors are ignored. The same geometry routines back the menu's
; area-effect target modes (see BattleTgt_ModeTable), so this is
; presumably how non-menu code (enemy scripts, scripted attacks) asks
; "which battlers does this area hit?".
; Entry: M=1, X=0, DB=$7E; !BattleTgt_AreaType, !BattleTgt_AreaSide..AreaVariant
; Exit:  M=1
; Callees: JSR (BattleTgt_AreaTable,X) -> BattleTgt_AreaLine/AreaCircle/
;          AreaPartyTriangle/AreaRow
org $C11FDD
BattleTgt_RunAreaQuery:
    LDA.w !BattleTgt_AreaType
    CMP.b #!BattleTgt_NumAreaTypes
    BCS .exit                       ; out of range -> no-op
    ASL
    TAX
    JSR (BattleTgt_AreaTable,X)
.exit:
    RTS

; BattleTgt_AreaTable ($C11FEA–$C11FF7, 7 words)
BattleTgt_AreaTable:
    dw BattleTgt_AreaLine           ; 0
    dw BattleTgt_AreaCircle         ; 1
    dw BattleTgt_AreaCircle         ; 2
    dw BattleTgt_AreaPartyTriangle  ; 3
    dw BattleTgt_AreaLine           ; 4
    dw BattleTgt_AreaPartyTriangle  ; 5
    dw BattleTgt_AreaRow            ; 6

; ==================================================================
; BattleTgt_ModeTable ($C11FF8–$C12039, 33 words)
; ==================================================================
; Target-mode handler table, indexed by (!BattleTgt_Mode & $7F) clamped
; to $20, called from BattleMenu_BuildTargetList. Each handler fills the
; 11-entry !BattleTgt_Candidates list (battler slots: 0-2 = PCs, 3-10 =
; enemies) and seeds !BattleTgt_Selected from the cursor
; (!BattleTgt_Cursor). !BattleTgt_TargetAll = $80 means "target
; everything in the list"; !BattleTgt_CanCycle non-zero means the player
; may move the cursor; a negative !BattleTgt_Result means "no valid
; target" (the handlers store $80, BuildTargetList's empty-list check $FF).
;
; Mode -> handler (unlisted modes use BattleTgt_SingleAlly):
;   $01,$04 AllAllies          $02 Self             $03 SingleKoAlly
;   $05,$06 PcByCharId (5/4)   $07 SingleEnemy      $08,$0A AllEnemies
;   $09 Everyone               $0B,$0C,$0D area between a source PC and
;   a chosen enemy (BattleTgt_AreaLine)    $0F,$11,$12,$13,$14,$18,$1A,
;   $1B other area shapes (BattleTgt_AreaRow/AreaPartyTriangle/
;   AreaCircle)
BattleTgt_ModeTable:
    dw BattleTgt_SingleAlly         ; $00
    dw BattleTgt_AllAllies          ; $01
    dw BattleTgt_Self               ; $02
    dw BattleTgt_SingleKoAlly       ; $03
    dw BattleTgt_AllAllies          ; $04
    dw BattleTgt_PcByCharId5        ; $05
    dw BattleTgt_PcByCharId4        ; $06
    dw BattleTgt_SingleEnemy        ; $07
    dw BattleTgt_AllEnemies         ; $08
    dw BattleTgt_Everyone           ; $09
    dw BattleTgt_AllEnemies         ; $0A
    dw BattleTgt_EnemyLineFromCaster ; $0B
    dw BattleTgt_EnemyLineFromCaster2 ; $0C
    dw BattleTgt_EnemyLineFromChar3 ; $0D
    dw BattleTgt_SingleAlly         ; $0E
    dw BattleTgt_EnemyRow           ; $0F
    dw BattleTgt_SingleAlly         ; $10
    dw BattleTgt_CasterRadius       ; $11
    dw BattleTgt_EnemyRadius        ; $12
    dw BattleTgt_Char3Radius        ; $13
    dw BattleTgt_Char3Radius        ; $14
    dw BattleTgt_SingleAlly         ; $15
    dw BattleTgt_SingleAlly         ; $16
    dw BattleTgt_SingleAlly         ; $17
    dw BattleTgt_PartyTriangle      ; $18
    dw BattleTgt_SingleAlly         ; $19
    dw BattleTgt_EnemyRadius        ; $1A
    dw BattleTgt_Char6Radius        ; $1B
    dw BattleTgt_SingleAlly         ; $1C
    dw BattleTgt_SingleAlly         ; $1D
    dw BattleTgt_SingleAlly         ; $1E
    dw BattleTgt_SingleAlly         ; $1F
    dw BattleTgt_SingleAlly         ; $20

; ==================================================================
; BattleTgt_SingleAlly ($C1203A–$C12099, 96 bytes)
; ==================================================================
; Default mode: one PC (slots 0-2), cursor may cycle. Falls into
; BattleTgt_CollectValidTargets, the shared list builder that the
; other list modes enter with their own slot range (!BattleTgt_ScanEnd
; = end exclusive, X = start) and flags.
;
; CollectValidTargets keeps battler X only if it is present
; (!Battler_Present), !Battler_Unk9FF7 bit 7 is clear, it is not
; !Battler_Untargetable, and — if !Battler_KoFlag is set — only when the
; mode is $04. The requesting battler (!BattleTgt_Caster) always goes to
; the front of !BattleTgt_Candidates; everyone else is appended from
; entry 1. CompactCandidates then closes the hole if the requester
; wasn't eligible. Finally the cursor entry is copied to
; !BattleTgt_Selected, or the whole list when !BattleTgt_TargetAll says
; "target all".
; Entry: M=1, X=0, DB=$7E (all BattleTgt_* handlers)
; Exit:  M=1
; Callees: BattleTgt_CompactCandidates
!BattleTgt_ScanEnd = !BattleTmp_80       ; 2 B in: slot after the last one CollectValidTargets scans
org $C1203A
BattleTgt_SingleAlly:
    LDX.w #!Battle_NumPcSlots
    STX.b !BattleTgt_ScanEnd        ; PCs 0-2
    LDX #$0000                      ; first slot
    INC.w !BattleTgt_CanCycle
BattleTgt_CollectValidTargets:
    TDC
    TAY                             ; Y = append index
.loop:
    LDA.w !Battler_Present,X
    BEQ .next
    LDA.w !Battler_Unk9FF7,X
    BMI .next                       ; excluded
    LDA.w !Battler_KoFlag,X
    BEQ .check_hidden
    LDA.w !BattleTgt_Mode
    AND.b #!BattleTgt_ModeMask
    CMP.b #!BattleTgt_ModeAllAlliesKo ; only mode $04 may pick these
    BNE .next
.check_hidden:
    LDA.w !Battler_Untargetable,X
    BNE .next
    CPX.w !BattleTgt_Caster         ; requesting battler?
    BNE .append
    LDA.w !BattleTgt_Caster
    STA.w !BattleTgt_Candidates     ; requester goes first
    BRA .next
.append:
    TXA
    STA.w !BattleTgt_Candidates+1,Y
    INY
.next:
    INX
    CPX.b !BattleTgt_ScanEnd
    BNE .loop
    JSR BattleTgt_CompactCandidates
    LDA.w !BattleTgt_Cursor         ; entry under the cursor -> selection
    TAX
    LDA.w !BattleTgt_Candidates,X
    STA.w !BattleTgt_Selected
    LDA.w !BattleTgt_TargetAll
    BPL .exit
    LDX.w #!Battle_LastSlot         ; target all: copy whole list
.copy_all:
    LDA.w !BattleTgt_Candidates,X
    STA.w !BattleTgt_Selected,X
    DEX
    BPL .copy_all
.exit:
    RTS

; BattleTgt_AllAllies ($C1209A–$C120A8, 15 bytes): every PC
BattleTgt_AllAllies:
    LDX.w #!Battle_NumPcSlots
    STX.b !BattleTgt_ScanEnd
    LDX #$0000
    LDA.b #!BattleTgt_AllFlag
    STA.w !BattleTgt_TargetAll      ; target all
    BRA BattleTgt_CollectValidTargets

; BattleTgt_SingleEnemy ($C120A9–$C120B5, 13 bytes): one enemy (3-10),
; cursor may cycle. Also called as a list builder by the area modes.
BattleTgt_SingleEnemy:
    LDX.w #!Battle_NumSlots
    STX.b !BattleTgt_ScanEnd
    LDX.w #!Battle_FirstEnemySlot
    INC.w !BattleTgt_CanCycle
    BRA BattleTgt_CollectValidTargets

; BattleTgt_AllEnemies ($C120B6–$C120C5, 16 bytes)
BattleTgt_AllEnemies:
    LDX.w #!Battle_NumSlots
    STX.b !BattleTgt_ScanEnd
    LDX.w #!Battle_FirstEnemySlot
    LDA.b #!BattleTgt_AllFlag
    STA.w !BattleTgt_TargetAll
    JMP BattleTgt_CollectValidTargets

; BattleTgt_Everyone ($C120C6–$C120D5, 16 bytes): all battlers 0-10
BattleTgt_Everyone:
    LDX.w #!Battle_NumSlots
    STX.b !BattleTgt_ScanEnd
    LDX #$0000
    LDA.b #!BattleTgt_AllFlag
    STA.w !BattleTgt_TargetAll
    JMP BattleTgt_CollectValidTargets

; BattleTgt_Self ($C120D6–$C120DF, 10 bytes): the shown PC only
BattleTgt_Self:
    LDA.w !BattleMenu_ActivePc
    STA.w !BattleTgt_Candidates
    STA.w !BattleTgt_Selected
    RTS

; ==================================================================
; BattleTgt_SingleKoAlly ($C120E0–$C12135, 86 bytes)
; ==================================================================
; Lists the PCs whose BattlerStats.Status has bit 7 set — by context,
; KO'd allies, i.e. a revive target. Unrolled for the three PC slots.
; No candidate -> !BattleTgt_Result = $80.
BattleTgt_SingleKoAlly:
    INC.w !BattleTgt_CanCycle
    TDC
    TAX
    LDA.w !Battler_Present          ; PC 0
    BEQ .pc1
    LDA.w !Battler_Untargetable
    BNE .pc1
    LDA.w BattlerStats.Status
    BPL .pc1
    STZ.w !BattleTgt_Candidates
    INX
.pc1:
    LDA.w !Battler_Present+1        ; PC 1
    BEQ .pc2
    LDA.w !Battler_Untargetable+1
    BNE .pc2
    LDA.w BattlerStats[1].Status
    BPL .pc2
    LDA #$01
    STA.w !BattleTgt_Candidates,X
    INX
.pc2:
    LDA.w !Battler_Present+2        ; PC 2
    BEQ .check_any
    LDA.w !Battler_Untargetable+2
    BNE .check_any
    LDA.w BattlerStats[2].Status
    BPL .check_any
    LDA #$02
    STA.w !BattleTgt_Candidates,X
.check_any:
    LDA.w !BattleTgt_Candidates
    BPL .select
    LDA.b #!BattleTgt_ResultNone
    STA.w !BattleTgt_Result         ; no valid target
.select:
    LDA.w !BattleTgt_Cursor
    TAX
    LDA.w !BattleTgt_Candidates,X
    STA.w !BattleTgt_Selected
    RTS

; ==================================================================
; BattleTgt_PcByCharId5 ($C12136–$C12162, 45 bytes)
; ==================================================================
; Targets the one party member whose !Pc_CharId equals
; !BattleTgt_WantedChar (5 for this entry, 4 via BattleTgt_PcByCharId4).
; In bank $C1, !Pc_CharId behaves like the party's character-id list; if
; so these are "target Ayla"/"target Frog" modes. Which techs use target
; modes 5 and 6 is not established. The routine names keep the numeric
; ids because the character constants (!Pc_CharAyla etc.) are inferred.
!BattleTgt_WantedChar = !BattleTmp_80    ; 1 B in: character id FindPcByCharId looks for
BattleTgt_PcByCharId5:
    LDA.b #!Pc_CharAyla
    STA.b !BattleTgt_WantedChar
BattleTgt_FindPcByCharId:
    INC.w !BattleTgt_CanCycle
    LDX.w #!Battle_LastPcSlot
.loop:
    LDA.w !Battler_Present,X
    BEQ .next
    LDA.w !Battler_Untargetable,X
    BNE .next
    LDA.w !Pc_CharId,X
    CMP.b !BattleTgt_WantedChar
    BEQ .found
.next:
    DEX
    BPL .loop
    LDA.b #!BattleTgt_ResultNone
    STA.w !BattleTgt_Result         ; not in party / not targetable
    BRA .exit
.found:
    TXA
    STA.w !BattleTgt_Candidates
    STA.w !BattleTgt_Selected
.exit:
    RTS

; BattleTgt_PcByCharId4 ($C12163–$C12168, 6 bytes)
BattleTgt_PcByCharId4:
    LDA.b #!Pc_CharFrog
    STA.b !BattleTgt_WantedChar
    BRA BattleTgt_FindPcByCharId

; ==================================================================
; Area modes ($C12169–$C12331)
; ==================================================================
; All of these pick an anchor (the caster, a chosen enemy, or a
; specific party member), fill the area parameter block, run an
; area-geometry routine that writes the hit list into
; !BattleTgt_Candidates, then select the whole list
; (BattleTgt_SelectAllCandidates):
;   !BattleTgt_AreaCentre = source/centre battler, AreaAim = aimed-at
;   battler, AreaSize = shape size, AreaVariant = variant flag,
;   AreaSide = 0 (scan the enemies)
; The enemy-anchored ones build the enemy list first and let the pad
; move the aim: D-pad up/right or down/left each play Battle_PlaySfx0 and
; step the cursor. Note the three "line" modes step forward for both pad
; groups; the radius/row modes step backward for the second group.

; BattleTgt_EnemyLineFromCaster ($C12169–$C121AE, 70 bytes)
BattleTgt_EnemyLineFromCaster:
    JSR BattleTgt_SingleEnemy
    STZ.w !BattleTgt_CanCycle
    LDA.b #!BattleTgt_AllFlag
    STA.w !BattleTgt_TargetAll
    LDA.b !Battle_PadEdgeDpad
    AND.b #!Battle_DpadUpRight
    BEQ .check_other
    JSR Battle_PlaySfx0
    JSR BattleTgt_CycleNext
    BRA .setup
.check_other:
    LDA.b !Battle_PadEdgeDpad
    AND.b #!Battle_DpadDownLeft
    BEQ .setup
    JSR Battle_PlaySfx0
    JSR BattleTgt_CycleNext
.setup:
    STZ.w !BattleTgt_AreaSide
    LDA.w !BattleTgt_Caster
    STA.w !BattleTgt_AreaCentre     ; source: caster
    LDA.w !BattleTgt_Cursor
    TAX
    LDA.w !BattleTgt_Candidates,X
    STA.w !BattleTgt_AreaAim        ; aimed-at enemy
    LDA.b #!BattleTgt_LineWidth
    STA.w !BattleTgt_AreaSize
    STZ.w !BattleTgt_AreaVariant
    JSR BattleTgt_AreaLine
    JMP BattleTgt_SelectAllCandidates

; BattleTgt_EnemyLineFromChar3 ($C121AF–$C12202, 84 bytes): as above,
; but the source is the party member with character id 3 (!Pc_CharRobo,
; inferred: Robo; the name keeps the numeric id). If no PC has that id it
; returns before the area step, leaving what BattleTgt_SingleEnemy and
; the pad step set up: the cursor's enemy in !BattleTgt_Selected, with
; !BattleTgt_TargetAll = $80 (the cursor may already have moved and
; played sound 0).
BattleTgt_EnemyLineFromChar3:
    JSR BattleTgt_SingleEnemy
    STZ.w !BattleTgt_CanCycle
    LDA.b #!BattleTgt_AllFlag
    STA.w !BattleTgt_TargetAll
    LDA.b !Battle_PadEdgeDpad
    AND.b #!Battle_DpadUpRight
    BEQ .check_other
    JSR Battle_PlaySfx0
    JSR BattleTgt_CycleNext
    BRA .find_source
.check_other:
    LDA.b !Battle_PadEdgeDpad
    AND.b #!Battle_DpadDownLeft
    BEQ .find_source
    JSR Battle_PlaySfx0
    JSR BattleTgt_CycleNext
.find_source:
    TDC
    TAX
.find_loop:
    LDA.w !Pc_CharId,X
    CMP.b #!Pc_CharRobo
    BEQ .found
    INX
    CPX.w #!Battle_NumPcSlots
    BNE .find_loop
    RTS
.found:
    TXA
    STA.w !BattleTgt_AreaCentre     ; source: party member id 3
    STZ.w !BattleTgt_AreaSide
    LDA.w !BattleTgt_Cursor
    TAX
    LDA.w !BattleTgt_Candidates,X
    STA.w !BattleTgt_AreaAim
    LDA.b #!BattleTgt_LineWidth
    STA.w !BattleTgt_AreaSize
    STZ.w !BattleTgt_AreaVariant
    JSR BattleTgt_AreaLine
    JMP BattleTgt_SelectAllCandidates

; BattleTgt_EnemyLineFromCaster2 ($C12203–$C1224A, 72 bytes): same as
; EnemyLineFromCaster with !BattleTgt_AreaVariant = 1
BattleTgt_EnemyLineFromCaster2:
    JSR BattleTgt_SingleEnemy
    STZ.w !BattleTgt_CanCycle
    LDA.b #!BattleTgt_AllFlag
    STA.w !BattleTgt_TargetAll
    LDA.b !Battle_PadEdgeDpad
    AND.b #!Battle_DpadUpRight
    BEQ .check_other
    JSR Battle_PlaySfx0
    JSR BattleTgt_CycleNext
    BRA .setup
.check_other:
    LDA.b !Battle_PadEdgeDpad
    AND.b #!Battle_DpadDownLeft
    BEQ .setup
    JSR Battle_PlaySfx0
    JSR BattleTgt_CycleNext
.setup:
    STZ.w !BattleTgt_AreaSide
    LDA.w !BattleTgt_Caster
    STA.w !BattleTgt_AreaCentre
    LDA.w !BattleTgt_Cursor
    TAX
    LDA.w !BattleTgt_Candidates,X
    STA.w !BattleTgt_AreaAim
    LDA.b #!BattleTgt_LineWidth
    STA.w !BattleTgt_AreaSize
    LDA.b #!BattleTgt_LineVariantAim
    STA.w !BattleTgt_AreaVariant
    JSR BattleTgt_AreaLine
    JMP BattleTgt_SelectAllCandidates

; BattleTgt_CasterRadius ($C1224B–$C1225E, 20 bytes): area $10 around
; the caster
BattleTgt_CasterRadius:
    STZ.w !BattleTgt_AreaSide
    LDA.w !BattleTgt_Caster
    STA.w !BattleTgt_AreaCentre
    LDA.b #!BattleTgt_RadiusSq4
    STA.w !BattleTgt_AreaSize
    JSR BattleTgt_AreaCircle
    JMP BattleTgt_SelectAllCandidates

; BattleTgt_EnemyRadius ($C1225F–$C122A3, 69 bytes): area around a
; chosen enemy; size $19 for mode $1A, else $09
BattleTgt_EnemyRadius:
    JSR BattleTgt_SingleEnemy
    STZ.w !BattleTgt_CanCycle
    LDA.b !Battle_PadEdgeDpad
    AND.b #!Battle_DpadUpRight
    BEQ .check_other
    JSR Battle_PlaySfx0
    JSR BattleTgt_CycleNext
    BRA .setup
.check_other:
    LDA.b !Battle_PadEdgeDpad
    AND.b #!Battle_DpadDownLeft
    BEQ .setup
    JSR Battle_PlaySfx0
    JSR BattleTgt_CyclePrev
.setup:
    STZ.w !BattleTgt_AreaSide
    LDA.w !BattleTgt_Cursor
    TAX
    LDA.w !BattleTgt_Candidates,X
    STA.w !BattleTgt_AreaCentre     ; centre: chosen enemy
    LDA.w !BattleTgt_Mode
    AND.b #!BattleTgt_ModeMask
    CMP.b #!BattleTgt_ModeEnemyRadiusBig
    BNE .small
    LDA.b #!BattleTgt_RadiusSq5
    BRA .set_size
.small:
    LDA.b #!BattleTgt_RadiusSq3
.set_size:
    STA.w !BattleTgt_AreaSize
    JSR BattleTgt_AreaCircle
    JMP BattleTgt_SelectAllCandidates

; BattleTgt_Char3Radius ($C122A4–$C122D2, 47 bytes): area around party
; member id 3; size $19 for mode $14, else $10
BattleTgt_Char3Radius:
    STZ.w !BattleTgt_AreaSide
    TDC
    TAX
.find_loop:
    LDA.w !Pc_CharId,X
    CMP.b #!Pc_CharRobo
    BEQ .found
    INX
    CPX.w #!Battle_NumPcSlots
    BNE .find_loop
    RTS
.found:
    TXA
    STA.w !BattleTgt_AreaCentre
    LDA.w !BattleTgt_Mode
    AND.b #!BattleTgt_ModeMask
    CMP.b #!BattleTgt_ModeRoboRadiusBig
    BNE .small
    LDA.b #!BattleTgt_RadiusSq5
    BRA .set_size
.small:
    LDA.b #!BattleTgt_RadiusSq4
.set_size:
    STA.w !BattleTgt_AreaSize
    JSR BattleTgt_AreaCircle
    JMP BattleTgt_SelectAllCandidates

; BattleTgt_Char6Radius ($C122D3–$C122F4, 34 bytes): area $19 around
; party member id 6
BattleTgt_Char6Radius:
    STZ.w !BattleTgt_AreaSide
    TDC
    TAX
.find_loop:
    LDA.w !Pc_CharId,X
    CMP.b #!Pc_CharMagus
    BEQ .found
    INX
    CPX.w #!Battle_NumPcSlots
    BNE .find_loop
    RTS
.found:
    TXA
    STA.w !BattleTgt_AreaCentre
    LDA.b #!BattleTgt_RadiusSq5
    STA.w !BattleTgt_AreaSize
    JSR BattleTgt_AreaCircle
    JMP BattleTgt_SelectAllCandidates

; BattleTgt_EnemyRow ($C122F5–$C12328, 52 bytes incl. dead RTS):
; chosen enemy as anchor for BattleTgt_AreaRow (a +/-$20 band around
; the anchor's !Battler_ScreenY)
BattleTgt_EnemyRow:
    JSR BattleTgt_SingleEnemy
    STZ.w !BattleTgt_CanCycle
    LDA.b !Battle_PadEdgeDpad
    AND.b #!Battle_DpadUpRight
    BEQ .check_other
    JSR Battle_PlaySfx0
    JSR BattleTgt_CycleNext
    BRA .setup
.check_other:
    LDA.b !Battle_PadEdgeDpad
    AND.b #!Battle_DpadDownLeft
    BEQ .setup
    JSR Battle_PlaySfx0
    JSR BattleTgt_CyclePrev
.setup:
    STZ.w !BattleTgt_AreaSide
    LDA.w !BattleTgt_Cursor
    TAX
    LDA.w !BattleTgt_Candidates,X
    STA.w !BattleTgt_AreaCentre
    JSR BattleTgt_AreaRow
    JMP BattleTgt_SelectAllCandidates
    RTS                             ; dead byte after the tail JMP, preserved

; BattleTgt_PartyTriangle ($C12329–$C12331, 9 bytes): enemies inside
; the triangle formed by the three PCs (BattleTgt_AreaPartyTriangle)
BattleTgt_PartyTriangle:
    STZ.w !BattleTgt_AreaSide
    JSR BattleTgt_AreaPartyTriangle
    JMP BattleTgt_SelectAllCandidates

; ==================================================================
; BattleTgt_AreaRow ($C12332–$C123A3, 114 bytes)
; ==================================================================
; "Row" area: every eligible battler on the scanned side whose screen
; y (!Battler_ScreenY) lies within +/-$20 of the centre battler's y. The window
; is clamped to $00-$FF (TDC on borrow, $FF on carry) and both ends are
; inclusive. Only y is tested, so the shape is a horizontal band across
; the whole field (inferred from the arithmetic; the in-game name of
; the techs using it is not established here).
;
; Scanned side: !BattleTgt_AreaSide = 0 scans enemies (slots 3-10),
; non-zero scans PCs (slots 0-2); the same convention as the other area
; routines. Eligibility is the usual set (!Battler_Present,
; !Battler_Unk9FF7 bit 7 clear, !Battler_KoFlag clear, not
; !Battler_Untargetable). The centre battler is skipped in the scan and
; then written unconditionally to the front of !BattleTgt_Candidates —
; it is not checked for eligibility, and no CompactCandidates pass runs.
; Entry: M=1, X=0, DB=$7E; !BattleTgt_AreaSide, !BattleTgt_AreaCentre
; Exit:  M=1; Candidates[0] = centre, [1..] = hits, rest $FF
; Callees: BattleTgt_ClearLists
; Direct-page roles (AreaSlot/AreaEnd shared by all area routines):
!BattleTgt_AreaSlot = !BattleTmp_8E       ; 2 B: battler slot being tested
!BattleTgt_AreaEnd = !BattleTmp_90        ; 2 B: slot after the last one scanned
!BattleTgt_RowCentre = !BattleTmp_88      ; 2 B: centre battler slot
!BattleTgt_RowTop = !BattleTmp_85         ; 1 B: smallest y inside the band
!BattleTgt_RowBottom = !BattleTmp_87      ; 1 B: largest y inside the band
org $C12332
BattleTgt_AreaRow:
    LDA.w !BattleTgt_AreaCentre
    TAX
    STX.b !BattleTgt_RowCentre      ; (16-bit)
    SEC
    LDA.w !Battler_ScreenY,X
    SBC.b #!BattleTgt_RowHalfHeight ; top edge
    BCS .lo_ok
    TDC                             ; clamp at 0
.lo_ok:
    STA.b !BattleTgt_RowTop
    CLC
    LDA.w !Battler_ScreenY,X
    ADC.b #!BattleTgt_RowHalfHeight ; bottom edge
    BCC .hi_ok
    LDA.b #!BattleTgt_ScreenMax     ; clamp at $FF
.hi_ok:
    STA.b !BattleTgt_RowBottom
    JSR BattleTgt_ClearLists
    LDX.w #!Battle_NumSlots
    STX.b !BattleTgt_AreaEnd        ; end (exclusive) = 11
    LDX.w #!Battle_FirstEnemySlot
    STX.b !BattleTgt_AreaSlot       ; start = 3 (enemies)
    LDA.w !BattleTgt_AreaSide
    BEQ .scan
    STX.b !BattleTgt_AreaEnd        ; non-zero: end = 3 ...
    TDC
    TAX
    STX.b !BattleTgt_AreaSlot       ; ... start = 0 (PCs)
.scan:
    TDC
    TAY                             ; Y = append index
.loop:
    LDX.b !BattleTgt_AreaSlot
    CPX.b !BattleTgt_RowCentre
    BEQ .next                       ; skip the centre itself
    LDA.w !Battler_Present,X
    BEQ .next                       ; not present
    LDA.w !Battler_Unk9FF7,X
    BMI .next                       ; flagged out
    LDA.w !Battler_KoFlag,X
    BNE .next                       ; KO'd (inferred)
    LDA.w !Battler_Untargetable,X
    BNE .next                       ; hidden / untargetable
    LDA.w !Battler_ScreenY,X
    CMP.b !BattleTgt_RowTop
    BCC .next                       ; above the band
    CMP.b !BattleTgt_RowBottom
    BEQ .hit
    BCS .next                       ; below the band
.hit:
    LDA.b !BattleTgt_AreaSlot
    STA.w !BattleTgt_Candidates+1,Y
    INY
.next:
    INC.b !BattleTgt_AreaSlot
    LDA.b !BattleTgt_AreaSlot
    CMP.b !BattleTgt_AreaEnd
    BNE .loop
    LDA.b !BattleTgt_RowCentre
    STA.w !BattleTgt_Candidates     ; centre always heads the list
    RTS

; ==================================================================
; BattleTgt_AreaPartyTriangle ($C123A4–$C125A2, 511 bytes)
; ==================================================================
; Enemies inside the triangle whose corners are the screen positions of
; party slots 0, 1 and 2 (!Battler_ScreenX/Y for slots 0-2). The slots are read
; unconditionally, so all three PCs are assumed present (by context:
; this backs mode $18 and area types 3/5, presumably triple techs).
;
; 1. Copy the corners to P0, P1, P2 (!BattleTgt_P0X/Y .. P2X/Y).
; 2. Three compare-and-swap passes order them by x: P2 = leftmost,
;    P1 = rightmost, P0 = middle. Then fix the winding: if P2 and P0
;    share an x, or P0 and P1 do, the pair is ordered by y; otherwise
;    if P0's y is greater than P1's or P2's, P1 and P2 are swapped
;    (inferred purpose: a consistent vertex winding so each corner's
;    interior angle runs "from" one edge "to" the other).
; 3. Battle_CalcAngle gives the direction angle of each edge as seen from
;    each corner: P0 -> [P0ArcFrom, P0ArcTo], P1 -> [P1ArcFrom, P1ArcTo],
;    P2 -> [P2ArcFrom, P2ArcTo]. P0Wraps/P1Wraps/P2Wraps flag corners
;    whose range wraps past angle 0.
; 4. For each enemy slot 3-10 that is eligible, the angle from every
;    corner to the enemy must fall inside that corner's range (with
;    wrap handled as an OR instead of an AND). Inside all three wedges
;    = inside the triangle.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to BattleTgt_CompactCandidates (the scan only
;        appends from entry 1, so the $FF front entry is always closed up)
; Callees: Battle_CalcAngle, BattleTgt_ClearLists, BattleTgt_CompactCandidates
; Note: !BattleTgt_AreaSide is ignored here; the scan is always over the enemies.
; Direct-page roles:
!BattleTgt_P0X = !BattleTmp_80            ; 1 B: corner P0 screen x
!BattleTgt_P0Y = !BattleTmp_81            ; 1 B: corner P0 screen y
!BattleTgt_P1X = !BattleTmp_82            ; 1 B: corner P1 screen x
!BattleTgt_P1Y = !BattleTmp_83            ; 1 B: corner P1 screen y
!BattleTgt_P2X = !BattleTmp_84            ; 1 B: corner P2 screen x
!BattleTgt_P2Y = !BattleTmp_85            ; 1 B: corner P2 screen y
!BattleTgt_P0ArcFrom = !BattleTmp_86      ; 1 B: P0's accepted angles start (angle to P1)
!BattleTgt_P0ArcTo = !BattleTmp_87        ; 1 B: ... end (angle to P2)
!BattleTgt_P1ArcFrom = !BattleTmp_88      ; 1 B: P1's range start (angle to P2)
!BattleTgt_P1ArcTo = !BattleTmp_89        ; 1 B: ... end (angle to P0)
!BattleTgt_P2ArcFrom = !BattleTmp_8A      ; 1 B: P2's range start (angle to P0)
!BattleTgt_P2ArcTo = !BattleTmp_8B        ; 1 B: ... end (angle to P1)
!BattleTgt_P0Wraps = !BattleTmp_92        ; 1 B: non-zero = P0's range wraps past angle 0
!BattleTgt_P1Wraps = !BattleTmp_93        ; 1 B: same for P1
!BattleTgt_P2Wraps = !BattleTmp_94        ; 1 B: same for P2
org $C123A4
BattleTgt_AreaPartyTriangle:
    TDC
    TAX
    STX.b !BattleTgt_P0Wraps        ; clear P0Wraps and P1Wraps (16-bit)
    STX.b !BattleTgt_P2Wraps        ; and P2Wraps
    LDA.w !Battler_ScreenX          ; P0 = PC slot 0
    STA.b !BattleTgt_P0X
    LDA.w !Battler_ScreenY
    STA.b !BattleTgt_P0Y
    LDA.w !Battler_ScreenX+1        ; P1 = PC slot 1
    STA.b !BattleTgt_P1X
    LDA.w !Battler_ScreenY+1
    STA.b !BattleTgt_P1Y
    LDA.w !Battler_ScreenX+2        ; P2 = PC slot 2
    STA.b !BattleTgt_P2X
    LDA.w !Battler_ScreenY+2
    STA.b !BattleTgt_P2Y
    ; --- sort by x ---
    LDA.b !BattleTgt_P2X
    CMP.b !BattleTgt_P0X
    BCC .sort2                      ; x2 < x0: keep
    PHA                             ; swap P0 <-> P2
    LDA.b !BattleTgt_P0X
    STA.b !BattleTgt_P2X
    PLA
    STA.b !BattleTgt_P0X
    LDA.b !BattleTgt_P2Y
    PHA
    LDA.b !BattleTgt_P0Y
    STA.b !BattleTgt_P2Y
    PLA
    STA.b !BattleTgt_P0Y
.sort2:
    LDA.b !BattleTgt_P2X
    CMP.b !BattleTgt_P1X
    BCC .sort3                      ; x2 < x1: keep
    PHA                             ; swap P1 <-> P2
    LDA.b !BattleTgt_P1X
    STA.b !BattleTgt_P2X
    PLA
    STA.b !BattleTgt_P1X
    LDA.b !BattleTgt_P2Y
    PHA
    LDA.b !BattleTgt_P1Y
    STA.b !BattleTgt_P2Y
    PLA
    STA.b !BattleTgt_P1Y
.sort3:
    LDA.b !BattleTgt_P0X
    CMP.b !BattleTgt_P1X
    BCC .winding                    ; x0 < x1: keep
    PHA                             ; swap P0 <-> P1
    LDA.b !BattleTgt_P1X
    STA.b !BattleTgt_P0X
    PLA
    STA.b !BattleTgt_P1X
    LDA.b !BattleTgt_P0Y
    PHA
    LDA.b !BattleTgt_P1Y
    STA.b !BattleTgt_P0Y
    PLA
    STA.b !BattleTgt_P1Y
    ; --- winding / tie-break ---
.winding:
    LDA.b !BattleTgt_P2X
    CMP.b !BattleTgt_P0X
    BNE .tie01                      ; x2 != x0
    LDA.b !BattleTgt_P2Y
    CMP.b !BattleTgt_P0Y
    BCS .edges                      ; y2 >= y0: keep
    PHA                             ; swap P0 <-> P2
    LDA.b !BattleTgt_P0Y
    STA.b !BattleTgt_P2Y
    PLA
    STA.b !BattleTgt_P0Y
    LDA.b !BattleTgt_P2X
    PHA
    LDA.b !BattleTgt_P0X
    STA.b !BattleTgt_P2X
    PLA
    STA.b !BattleTgt_P0X
    BRA .edges
.tie01:
    LDA.b !BattleTgt_P0X
    CMP.b !BattleTgt_P1X
    BNE .by_y                       ; x0 != x1
    LDA.b !BattleTgt_P1Y
    CMP.b !BattleTgt_P0Y
    BCS .edges                      ; y1 >= y0: keep
    PHA                             ; swap P0 <-> P1
    LDA.b !BattleTgt_P0Y
    STA.b !BattleTgt_P1Y
    PLA
    STA.b !BattleTgt_P0Y
    LDA.b !BattleTgt_P1X
    PHA
    LDA.b !BattleTgt_P0X
    STA.b !BattleTgt_P1X
    PLA
    STA.b !BattleTgt_P0X
    BRA .edges
.by_y:
    LDA.b !BattleTgt_P0Y
    CMP.b !BattleTgt_P1Y
    BEQ .cmp_y2
    BCS .swap12                     ; y0 > y1
.cmp_y2:
    LDA.b !BattleTgt_P0Y
    CMP.b !BattleTgt_P2Y
    BEQ .edges
    BCC .edges                      ; y0 <= y2: keep
.swap12:
    LDA.b !BattleTgt_P2X            ; swap P1 <-> P2
    PHA
    LDA.b !BattleTgt_P1X
    STA.b !BattleTgt_P2X
    PLA
    STA.b !BattleTgt_P1X
    LDA.b !BattleTgt_P2Y
    PHA
    LDA.b !BattleTgt_P1Y
    STA.b !BattleTgt_P2Y
    PLA
    STA.b !BattleTgt_P1Y
    ; --- per-corner edge angles ---
.edges:
    LDA.b !BattleTgt_P0X
    STA.b !Battle_GeoOriginX
    LDA.b !BattleTgt_P0Y
    STA.b !Battle_GeoOriginY
    LDA.b !BattleTgt_P1X
    STA.b !Battle_GeoPointX
    LDA.b !BattleTgt_P1Y
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle            ; P0 vs P1
    STA.b !BattleTgt_P0ArcFrom
    LDA.b !BattleTgt_P2X
    STA.b !Battle_GeoPointX
    LDA.b !BattleTgt_P2Y
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle            ; P0 vs P2
    STA.b !BattleTgt_P0ArcTo
    LDA.b !BattleTgt_P1X
    STA.b !Battle_GeoOriginX
    LDA.b !BattleTgt_P1Y
    STA.b !Battle_GeoOriginY
    JSR Battle_CalcAngle            ; P1 vs P2
    STA.b !BattleTgt_P1ArcFrom
    LDA.b !BattleTgt_P0X
    STA.b !Battle_GeoPointX
    LDA.b !BattleTgt_P0Y
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle            ; P1 vs P0
    STA.b !BattleTgt_P1ArcTo
    LDA.b !BattleTgt_P2X
    STA.b !Battle_GeoOriginX
    LDA.b !BattleTgt_P2Y
    STA.b !Battle_GeoOriginY
    JSR Battle_CalcAngle            ; P2 vs P0
    STA.b !BattleTgt_P2ArcFrom
    LDA.b !BattleTgt_P1X
    STA.b !Battle_GeoPointX
    LDA.b !BattleTgt_P1Y
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle            ; P2 vs P1
    STA.b !BattleTgt_P2ArcTo
    LDA.b !BattleTgt_P0ArcTo
    CMP.b !BattleTgt_P0ArcFrom
    BCS .wrap1
    INC.b !BattleTgt_P0Wraps        ; P0 range wraps
.wrap1:
    LDA.b !BattleTgt_P1ArcTo
    CMP.b !BattleTgt_P1ArcFrom
    BCS .wrap2
    INC.b !BattleTgt_P1Wraps        ; P1 range wraps
.wrap2:
    LDA.b !BattleTgt_P2ArcTo
    CMP.b !BattleTgt_P2ArcFrom
    BCS .scan_init
    INC.b !BattleTgt_P2Wraps        ; P2 range wraps
.scan_init:
    JSR BattleTgt_ClearLists
    LDX.w #!Battle_NumSlots
    STX.b !BattleTgt_AreaEnd        ; end (exclusive) = 11
    LDX.w #!Battle_FirstEnemySlot
    STX.b !BattleTgt_AreaSlot       ; start = 3 (enemies only)
    TDC
    TAY                             ; Y = append index
.loop:
    LDX.b !BattleTgt_AreaSlot
    LDA.w !Battler_Present,X
    BEQ .skip                       ; not present
    LDA.w !Battler_Unk9FF7,X
    BMI .skip                       ; flagged out
    LDA.w !Battler_KoFlag,X
    BNE .skip                       ; KO'd (inferred)
    LDA.w !Battler_Untargetable,X
    BEQ .test                       ; visible -> test it
.skip:
    JMP .next                       ; (too far for a branch)
.test:
    LDA.w !Battler_ScreenX,X        ; GeoPoint = candidate
    STA.b !Battle_GeoPointX
    LDA.w !Battler_ScreenY,X
    STA.b !Battle_GeoPointY
    LDA.b !BattleTgt_P0X            ; seen from P0
    STA.b !Battle_GeoOriginX
    LDA.b !BattleTgt_P0Y
    STA.b !Battle_GeoOriginY
    JSR Battle_CalcAngle
    LDA.b !BattleTgt_P0Wraps
    BNE .p0_wrap
    LDA.b !Battle_GeoAngle
    CMP.b !BattleTgt_P0ArcFrom
    BCC .next                       ; below range
    LDA.b !BattleTgt_P0ArcTo
    CMP.b !Battle_GeoAngle
    BCC .next                       ; above range
    BRA .p1
.p0_wrap:
    LDA.b !BattleTgt_P0ArcTo
    CMP.b !Battle_GeoAngle
    BCS .p1                         ; <= upper: in
    LDA.b !Battle_GeoAngle
    CMP.b !BattleTgt_P0ArcFrom
    BCC .next                       ; neither side
.p1:
    LDA.b !BattleTgt_P1X            ; seen from P1
    STA.b !Battle_GeoOriginX
    LDA.b !BattleTgt_P1Y
    STA.b !Battle_GeoOriginY
    JSR Battle_CalcAngle
    LDA.b !BattleTgt_P1Wraps
    BNE .p1_wrap
    LDA.b !Battle_GeoAngle
    CMP.b !BattleTgt_P1ArcFrom
    BCC .next
    LDA.b !BattleTgt_P1ArcTo
    CMP.b !Battle_GeoAngle
    BCC .next
    BRA .p2
.p1_wrap:
    LDA.b !BattleTgt_P1ArcTo
    CMP.b !Battle_GeoAngle
    BCS .p2
    LDA.b !Battle_GeoAngle
    CMP.b !BattleTgt_P1ArcFrom
    BCC .next
.p2:
    LDA.b !BattleTgt_P2X            ; seen from P2
    STA.b !Battle_GeoOriginX
    LDA.b !BattleTgt_P2Y
    STA.b !Battle_GeoOriginY
    JSR Battle_CalcAngle
    LDA.b !BattleTgt_P2Wraps
    BNE .p2_wrap
    LDA.b !Battle_GeoAngle
    CMP.b !BattleTgt_P2ArcFrom
    BCC .next
    LDA.b !BattleTgt_P2ArcTo
    CMP.b !Battle_GeoAngle
    BCC .next
    BRA .hit
.p2_wrap:
    LDA.b !BattleTgt_P2ArcTo
    CMP.b !Battle_GeoAngle
    BCS .hit
    LDA.b !Battle_GeoAngle
    CMP.b !BattleTgt_P2ArcFrom
    BCC .next
.hit:
    LDA.b !BattleTgt_AreaSlot
    STA.w !BattleTgt_Candidates+1,Y ; inside the triangle
    INY
.next:
    INC.b !BattleTgt_AreaSlot
    LDA.b !BattleTgt_AreaSlot
    CMP.b !BattleTgt_AreaEnd
    BEQ .done
    JMP .loop
.done:
    JMP BattleTgt_CompactCandidates

; ==================================================================
; BattleTgt_AreaLine ($C125A3–$C12700, 350 bytes)
; ==================================================================
; "Line" area from the source battler (!BattleTgt_AreaCentre) towards the
; aimed-at battler (!BattleTgt_AreaAim), half-width r = AreaSize * 8
; (passed to Battle_SinLookup as !Battle_SinScale; AreaSize = 2 from
; every caller seen).
;
; θ = Battle_CalcAngle angle between source (GeoOrigin) and target (GeoPoint).
; Two corner points are offset sideways from the line using
; Battle_SinLookup at θ, θ+$C0, θ+$80, θ+$40 (256 units per turn):
;   PA (PaX,PaY) = source + r*(sin θ, sin(θ+$C0))
;   PB (PbX,PbY) = variant 0: source + r*(sin(θ+$80), sin(θ+$40))
;                  variant 1: target + the same offset
; Each corner gets a 90-degree wedge of accepted angles:
;   PA: [θ, θ+$40]                          (PaArcFrom/To; PaWraps)
;   PB: variant 0 [θ+$C0, θ], variant 1 [θ+$80, θ+$C0] (PbArcFrom/To; PbWraps)
; A battler is hit when its angle from both corners falls inside both
; wedges, i.e. it lies in the strip between the two offset edges
; (inferred geometry; variant 1, AreaVariant != 0, moves PB to the
; target end, presumably closing the strip into a box between the two).
;
; The aimed-at battler (kept in !BattleTgt_Anchor) is skipped by the
; scan and re-added by the shared tail BattleTgt_AreaAddAnchor if it is
; on the scanned side. Scanned side follows !BattleTgt_AreaSide as in
; BattleTgt_AreaRow.
; Entry: M=1, X=0, DB=$7E; !BattleTgt_AreaSide..AreaVariant as above
; Exit:  M=1; via BattleTgt_AreaAddAnchor -> CompactCandidates
; Callees: Battle_CalcAngle, Battle_SinLookup, BattleTgt_ClearLists
; Direct-page roles (!BattleTgt_Anchor shared with AreaCircle / AreaAddAnchor):
!BattleTgt_PaX = !BattleTmp_80            ; 1 B: r*sin(a), then corner PA screen x
!BattleTgt_PaY = !BattleTmp_81            ; 1 B: r*sin(a+$C0), then corner PA screen y
!BattleTgt_PbX = !BattleTmp_82            ; 1 B: r*sin(a+$80), then corner PB screen x
!BattleTgt_PbY = !BattleTmp_83            ; 1 B: r*sin(a+$40), then corner PB screen y
!BattleTgt_PaArcFrom = !BattleTmp_84      ; 1 B: PA's accepted angles start
!BattleTgt_PaArcTo = !BattleTmp_86        ; 1 B: ... end
!BattleTgt_PbArcFrom = !BattleTmp_88      ; 1 B: PB's accepted angles start
!BattleTgt_PbArcTo = !BattleTmp_8A        ; 1 B: ... end
!BattleTgt_PaWraps = !BattleTmp_8C        ; 1 B: non-zero = PA's range wraps past angle 0
!BattleTgt_PbWraps = !BattleTmp_8D        ; 1 B: same for PB
!BattleTgt_Anchor = !BattleTmp_92         ; 2 B: battler skipped by the scan and re-added by AreaAddAnchor
org $C125A3
BattleTgt_AreaLine:
    LDA.w !BattleTgt_AreaSize
    ASL
    ASL
    ASL
    STA.b !Battle_SinScale          ; radius scale = size * 8
    LDA.w !BattleTgt_AreaCentre
    TAX                             ; X = source
    LDA.w !BattleTgt_AreaAim
    TAY                             ; Y = aimed-at
    LDA.w !Battler_ScreenX,X
    STA.b !Battle_GeoOriginX
    LDA.w !Battler_ScreenY,X
    STA.b !Battle_GeoOriginY
    LDA.w !Battler_ScreenX,Y
    STA.b !Battle_GeoPointX
    LDA.w !Battler_ScreenY,Y
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle            ; A = GeoAngle = θ
    JSR Battle_SinLookup
    STA.b !BattleTgt_PaX            ; r*sin θ
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleThreeQuarter
    JSR Battle_SinLookup
    STA.b !BattleTgt_PaY            ; r*sin(θ+$C0)
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleHalfTurn
    JSR Battle_SinLookup
    STA.b !BattleTgt_PbX            ; r*sin(θ+$80)
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup
    STA.b !BattleTgt_PbY            ; r*sin(θ+$40)
    CLC
    LDA.b !Battle_GeoOriginX
    ADC.b !BattleTgt_PaX
    STA.b !BattleTgt_PaX            ; PA = source + offset
    CLC
    LDA.b !Battle_GeoOriginY
    ADC.b !BattleTgt_PaY
    STA.b !BattleTgt_PaY
    LDA.b !Battle_GeoAngle
    STA.b !BattleTgt_PaArcFrom      ; PA wedge low = θ
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleQuarter
    STA.b !BattleTgt_PaArcTo        ; PA wedge high = θ+$40
    LDA.w !BattleTgt_AreaVariant
    BNE .variant1
    CLC
    LDA.b !Battle_GeoOriginX
    ADC.b !BattleTgt_PbX
    STA.b !BattleTgt_PbX            ; PB = source + opposite offset
    CLC
    LDA.b !Battle_GeoOriginY
    ADC.b !BattleTgt_PbY
    STA.b !BattleTgt_PbY
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleThreeQuarter
    STA.b !BattleTgt_PbArcFrom      ; PB wedge low = θ+$C0
    CLC                             ; (unneeded: no add follows)
    LDA.b !Battle_GeoAngle
    STA.b !BattleTgt_PbArcTo        ; PB wedge high = θ
    BRA .wrap_flags
.variant1:
    CLC
    LDA.b !Battle_GeoPointX
    ADC.b !BattleTgt_PbX
    STA.b !BattleTgt_PbX            ; PB = target + opposite offset
    CLC
    LDA.b !Battle_GeoPointY
    ADC.b !BattleTgt_PbY
    STA.b !BattleTgt_PbY
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleHalfTurn
    STA.b !BattleTgt_PbArcFrom      ; PB wedge low = θ+$80
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleThreeQuarter
    STA.b !BattleTgt_PbArcTo        ; PB wedge high = θ+$C0
.wrap_flags:
    STZ.b !BattleTgt_PaWraps
    STZ.b !BattleTgt_PbWraps
    LDA.b !BattleTgt_PaArcFrom
    CMP.b #!Battle_AngleThreeQuarter
    BCC .wrap_b
    INC.b !BattleTgt_PaWraps        ; PA wedge wraps past 0
.wrap_b:
    LDA.b !BattleTgt_PbArcFrom
    CMP.b #!Battle_AngleThreeQuarter
    BCC .scan_init
    INC.b !BattleTgt_PbWraps        ; PB wedge wraps past 0
.scan_init:
    JSR BattleTgt_ClearLists
    LDX.w #!Battle_NumSlots
    STX.b !BattleTgt_AreaEnd        ; end (exclusive) = 11
    LDX.w #!Battle_FirstEnemySlot
    STX.b !BattleTgt_AreaSlot       ; start = 3 (enemies)
    LDA.w !BattleTgt_AreaSide
    BEQ .anchor
    STX.b !BattleTgt_AreaEnd        ; non-zero: PCs 0-2
    TDC
    TAX
    STX.b !BattleTgt_AreaSlot
.anchor:
    LDA.w !BattleTgt_AreaAim
    TAX
    STX.b !BattleTgt_Anchor         ; anchor = aimed-at battler
    TDC
    TAY                             ; Y = append index
.loop:
    LDX.b !BattleTgt_AreaSlot
    LDA.w !Battler_Present,X
    BEQ .next                       ; not present
    LDA.w !Battler_Unk9FF7,X
    BMI .next                       ; flagged out
    LDA.w !Battler_KoFlag,X
    BNE .next                       ; KO'd (inferred)
    LDA.w !Battler_Untargetable,X
    BNE .next                       ; hidden / untargetable
    CPX.b !BattleTgt_Anchor
    BEQ .next                       ; anchor: added by the tail
    LDA.w !Battler_ScreenX,X        ; GeoPoint = candidate
    STA.b !Battle_GeoPointX
    LDA.w !Battler_ScreenY,X
    STA.b !Battle_GeoPointY
    LDA.b !BattleTgt_PaX            ; seen from PA
    STA.b !Battle_GeoOriginX
    LDA.b !BattleTgt_PaY
    STA.b !Battle_GeoOriginY
    JSR Battle_CalcAngle
    LDA.b !BattleTgt_PaWraps
    BNE .a_wrap
    LDA.b !Battle_GeoAngle
    CMP.b !BattleTgt_PaArcFrom
    BCC .next
    LDA.b !BattleTgt_PaArcTo
    CMP.b !Battle_GeoAngle
    BCC .next
    BRA .corner_b
.a_wrap:
    LDA.b !BattleTgt_PaArcTo
    CMP.b !Battle_GeoAngle
    BCS .corner_b
    LDA.b !Battle_GeoAngle
    CMP.b !BattleTgt_PaArcFrom
    BCC .next
.corner_b:
    LDA.b !BattleTgt_PbX            ; seen from PB
    STA.b !Battle_GeoOriginX
    LDA.b !BattleTgt_PbY
    STA.b !Battle_GeoOriginY
    JSR Battle_CalcAngle
    LDA.b !BattleTgt_PbWraps
    BNE .b_wrap
    LDA.b !Battle_GeoAngle
    CMP.b !BattleTgt_PbArcFrom
    BCC .next
    LDA.b !BattleTgt_PbArcTo
    CMP.b !Battle_GeoAngle
    BCC .next
    BRA .hit
.b_wrap:
    LDA.b !BattleTgt_PbArcTo
    CMP.b !Battle_GeoAngle
    BCS .hit
    LDA.b !Battle_GeoAngle
    CMP.b !BattleTgt_PbArcFrom
    BCC .next
.hit:
    LDA.b !BattleTgt_AreaSlot
    STA.w !BattleTgt_Candidates+1,Y ; inside the line
    INY
.next:
    INC.b !BattleTgt_AreaSlot
    LDA.b !BattleTgt_AreaSlot
    CMP.b !BattleTgt_AreaEnd
    BEQ .done
    JMP .loop
.done:
    JMP BattleTgt_AreaAddAnchor     ; shared tail in AreaCircle

; ==================================================================
; BattleTgt_AreaCircle ($C12701–$C127C4, 196 bytes)
; ==================================================================
; "Circle" area around the centre battler (!BattleTgt_AreaCentre).
; Positions are reduced to 16-pixel cells (Battle_ShiftRight4) and a
; battler is hit when dx^2 + dy^2 <= !BattleTgt_AreaSize, using the
; 16-entry !BattleRom_Squares (0, 1, 4, 9, ... $E1). The sizes callers pass, $09/$10/$19,
; are 3^2/4^2/5^2, i.e. radii of 3, 4 and 5 cells. The 8-bit ADC of
; the two squares can wrap (e.g. 15^2 + 7^2 = $112 -> $12) and admit a
; very distant battler; reproduced as found, and probably unreachable
; given on-screen distances.
;
; The 16-bit centre cells (CentreCellX/Y) are stored with STY after
; TAY, so their high bytes are whatever the B accumulator held; the
; M=0 subtraction later assumes those are 0 (callers reach here with
; B clear — inferred, not proven).
;
; The centre is skipped in the scan and re-added by the tail below,
; BattleTgt_AreaAddAnchor (also the tail of BattleTgt_AreaLine): with
; AreaSide = 0 the anchor (!BattleTgt_Anchor) heads the candidate list
; only if it is an enemy (slot >= 3), with AreaSide != 0 only if it is a
; PC — i.e. only if it belongs to the side that was scanned. Otherwise
; falls through into BattleTgt_CompactCandidates (which also runs after
; the anchor is placed, as a no-op since the front entry is then filled).
; Entry: M=1, X=0, DB=$7E; !BattleTgt_AreaSide, AreaCentre, AreaSize = radius^2
; Exit:  M=1; falls through into BattleTgt_CompactCandidates
; Callees: Battle_ShiftRight4, BattleTgt_ClearLists
; Direct-page roles:
!BattleTgt_CentreCellX = !BattleTmp_80    ; 2 B: centre x / 16 (high byte = whatever B held)
!BattleTgt_CentreCellY = !BattleTmp_82    ; 2 B: centre y / 16 (same caveat)
!BattleTgt_CellDX = !BattleTmp_84         ; 2 B: candidate x / 16, then |dx|, then dx*dx
!BattleTgt_CellDY = !BattleTmp_86         ; 2 B: candidate y / 16, then |dy|
org $C12701
BattleTgt_AreaCircle:
    LDA.w !BattleTgt_AreaCentre
    TAX                             ; X = centre
    LDA.w !Battler_ScreenX,X
    JSR Battle_ShiftRight4          ; x / 16
    TAY
    STY.b !BattleTgt_CentreCellX    ; centre cell x (16-bit)
    LDA.w !Battler_ScreenY,X
    JSR Battle_ShiftRight4          ; y / 16
    TAY
    STY.b !BattleTgt_CentreCellY    ; centre cell y (16-bit)
    JSR BattleTgt_ClearLists
    LDX.w #!Battle_NumSlots
    STX.b !BattleTgt_AreaEnd        ; end (exclusive) = 11
    LDX.w #!Battle_FirstEnemySlot
    STX.b !BattleTgt_AreaSlot       ; start = 3 (enemies)
    LDA.w !BattleTgt_AreaSide
    BEQ .anchor
    STX.b !BattleTgt_AreaEnd        ; non-zero: PCs 0-2
    TDC
    TAX
    STX.b !BattleTgt_AreaSlot
.anchor:
    LDA.w !BattleTgt_AreaCentre
    TAX
    STX.b !BattleTgt_Anchor         ; anchor = centre battler
    TDC
    TAY                             ; Y = append index
.loop:
    LDX.b !BattleTgt_AreaSlot
    LDA.w !Battler_Present,X
    BEQ .next                       ; not present
    LDA.w !Battler_Unk9FF7,X
    BMI .next                       ; flagged out
    LDA.w !Battler_KoFlag,X
    BNE .next                       ; KO'd (inferred)
    LDA.w !Battler_Untargetable,X
    BNE .next                       ; hidden / untargetable
    CPX.b !BattleTgt_Anchor
    BEQ .next                       ; anchor: added by the tail
    LDA.w !Battler_ScreenX,X
    JSR Battle_ShiftRight4
    STA.b !BattleTgt_CellDX
    STZ.b !BattleTgt_CellDX+1       ; cell x (16-bit)
    LDA.w !Battler_ScreenY,X
    JSR Battle_ShiftRight4
    STA.b !BattleTgt_CellDY
    STZ.b !BattleTgt_CellDY+1       ; cell y (16-bit)
    REP #$20                        ; A -> 16-bit
    SEC
    LDA.b !BattleTgt_CellDX
    SBC.b !BattleTgt_CentreCellX
    BPL .dx_pos
    EOR.w #!Battle_Invert16
    INC A                           ; |dx|
.dx_pos:
    STA.b !BattleTgt_CellDX
    SEC
    LDA.b !BattleTgt_CellDY
    SBC.b !BattleTgt_CentreCellY
    BPL .dy_pos
    EOR.w #!Battle_Invert16
    INC A                           ; |dy|
.dy_pos:
    STA.b !BattleTgt_CellDY
    TDC                             ; clear B before going 8-bit
    SEP #$20                        ; A -> 8-bit
    LDA.b !BattleTgt_CellDX
    TAX
    LDA.l !BattleRom_Squares,X      ; dx^2
    STA.b !BattleTgt_CellDX
    LDA.b !BattleTgt_CellDY
    TAX
    LDA.l !BattleRom_Squares,X      ; dy^2
    CLC
    ADC.b !BattleTgt_CellDX
    CMP.w !BattleTgt_AreaSize
    BEQ .hit
    BCS .next                       ; outside the radius
.hit:
    CLC                             ; (unneeded: no add follows)
    LDA.b !BattleTgt_AreaSlot
    STA.w !BattleTgt_Candidates+1,Y
    INY
.next:
    INC.b !BattleTgt_AreaSlot
    LDA.b !BattleTgt_AreaSlot
    CMP.b !BattleTgt_AreaEnd
    BNE .loop
BattleTgt_AreaAddAnchor:
    LDA.w !BattleTgt_AreaSide
    BNE .pc_side
    LDA.b !BattleTgt_Anchor
    CMP.b #!Battle_FirstEnemySlot
    BCC BattleTgt_CompactCandidates ; enemy scan, anchor is a PC
    BRA .place
.pc_side:
    LDA.b !BattleTgt_Anchor
    CMP.b #!Battle_FirstEnemySlot
    BCS BattleTgt_CompactCandidates ; PC scan, anchor is an enemy
.place:
    LDA.b !BattleTgt_Anchor
    STA.w !BattleTgt_Candidates     ; anchor heads the list
    ; falls through into BattleTgt_CompactCandidates ($C127C5)

; ==================================================================
; Candidate-list helpers ($C127C5–$C1283C, 120 bytes)
; ==================================================================

; BattleTgt_CompactCandidates ($C127C5–$C127D8, 20 bytes): if the
; front slot is empty (requester wasn't eligible), shift the list
; left by one. The last step reads entry 11, one past the 11 used
; entries (the list has 12 bytes).
org $C127C5
BattleTgt_CompactCandidates:
    LDA.w !BattleTgt_Candidates
    BPL .exit
    TDC
    TAX
.loop:
    LDA.w !BattleTgt_Candidates+1,X
    STA.w !BattleTgt_Candidates,X
    INX
    CPX.w #!Battle_NumSlots
    BNE .loop
.exit:
    RTS

; BattleTgt_ClearLists ($C127D9–$C127E7, 15 bytes): blank candidate
; and selection lists (12 entries each, one more than they use)
BattleTgt_ClearLists:
    LDX.w #!Battle_NumSlots
    LDA.b #!BattleTgt_Empty
.loop:
    STA.w !BattleTgt_Candidates,X
    STA.w !BattleTgt_Selected,X
    DEX
    BPL .loop
    RTS

; BattleTgt_SelectAllCandidates ($C127E8–$C127F9, 18 bytes): set
; target-all and copy the 11 candidates into the selection list
BattleTgt_SelectAllCandidates:
    LDA.b #!BattleTgt_AllFlag
    STA.w !BattleTgt_TargetAll
    LDX.w #!Battle_LastSlot
.loop:
    LDA.w !BattleTgt_Candidates,X
    STA.w !BattleTgt_Selected,X
    DEX
    BPL .loop
    RTS

; BattleTgt_CycleNext ($C127FA–$C12813, 26 bytes): advance !BattleTgt_Cursor to the
; next non-empty candidate (wrap at 11); no-op on an empty list. Same
; cursor stepping as BattleMenu_TargetNext, plus an empty-list guard
; (TargetNext would loop forever on an empty list); unlike TargetNext it
; does not write !BattleTgt_Selected.
BattleTgt_CycleNext:
    JSR BattleTgt_AnyCandidate
    BEQ .exit                       ; list empty
.loop:
    INC.w !BattleTgt_Cursor
    LDA.w !BattleTgt_Cursor
    CMP.b #!Battle_NumSlots
    BNE .check
    TDC
    STA.w !BattleTgt_Cursor
.check:
    TAX
    LDA.w !BattleTgt_Candidates,X
    BMI .loop
.exit:
    RTS

; BattleTgt_CyclePrev ($C12814–$C1282C, 25 bytes): mirror of CycleNext
BattleTgt_CyclePrev:
    JSR BattleTgt_AnyCandidate
    BEQ .exit
.loop:
    DEC.w !BattleTgt_Cursor
    LDA.w !BattleTgt_Cursor
    BPL .check
    LDA.b #!Battle_LastSlot
    STA.w !BattleTgt_Cursor
.check:
    TAX
    LDA.w !BattleTgt_Candidates,X
    BMI .loop
.exit:
    RTS

; BattleTgt_AnyCandidate ($C1282D–$C1283C, 16 bytes): Z=1 if all 11
; candidate slots are $FF, Z=0 as soon as one isn't
BattleTgt_AnyCandidate:
    TDC
    TAX
.loop:
    LDA.w !BattleTgt_Candidates,X
    CMP.b #!BattleTgt_Empty
    BNE .exit
    INX
    CPX.w #!Battle_NumSlots
    BNE .loop
.exit:
    RTS

; ==================================================================
; BattleMenu_DequeueReadyBattler ($C11B67–$C11BA9, 67 bytes)
; ==================================================================
; Pops the head of !BattleMenu_ReadyQueue (up to 3 deep, count in
; !BattleMenu_ReadyQueueLen) into the roster: clears its
; !Battle_Unk9F38, restores its tech-list cursor (!Pc_SavedTechRow /
; SavedTechScroll -> !Pc_TechRow / TechScroll), marks it present
; (!BattleMenu_Roster entry = its own slot), forces a window rebuild,
; shifts the queue down one entry, and counts it in
; !BattleMenu_ReadyCount. If no roster entry was shown
; (!BattleMenu_RosterIdx negative), shows the new one.
;
; Quirk: the queue shift copies +1 to +0, +2 to +1 and +2 to +3 (the
; ROM bytes confirm it), so +2 is never cleared. With three entries
; queued, [a,b,c] becomes [b,c,c,c] and then [c,c,c,c]; once the count
; reaches 0 the head is still c, which is not negative, so this routine
; (which checks only the head) would dequeue c again. Whether three PCs
; are ever queued at once is not established.
;
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; X = dequeued slot index (or unchanged if queue was empty)
; No JSR/JSL calls.
org $C11B67
BattleMenu_DequeueReadyBattler:
    LDA.w !BattleMenu_ReadyQueue    ; queue head
    BMI .exit                       ; queue empty -> nothing to do
    TAX
    STZ.w !Battle_Unk9F38,X
    LDA.w !Pc_SavedTechRow,X
    STA.w !Pc_TechRow,X
    LDA.w !Pc_SavedTechScroll,X
    STA.w !Pc_TechScroll,X
    LDA.w !BattleMenu_ReadyQueue
    TAX
    STA.w !BattleMenu_Roster,X      ; in the roster (entry = own slot)
    LDA.b #!BattleMenu_RosterRedraw
    STA.w !BattleMenu_RosterIdxDrawn ; force a window rebuild
    LDA.w !BattleMenu_ReadyQueue+1
    STA.w !BattleMenu_ReadyQueue    ; shift the queue down
    LDA.w !BattleMenu_ReadyQueue+2
    STA.w !BattleMenu_ReadyQueue+1
    LDA.w !BattleMenu_ReadyQueue+2
    STA.w !BattleMenu_ReadyQueue+3
    DEC.w !BattleMenu_ReadyQueueLen
    INC.w !BattleMenu_ReadyCount
    LDA.w !BattleMenu_RosterIdx
    BPL .exit                       ; something already shown
    TXA
    STA.w !BattleMenu_RosterIdx     ; show the dequeued PC
.exit:
    RTS

; ==================================================================
; BattleMenu_RemoveBattlerFromReady ($C11BAA–$C11C39, 144 bytes)
; ==================================================================
; Service 2 of the cross-bank $C10045 service API (see the entry-vector
; table near the top of this bank). Removes battler slot !Battle_ArgSlot
; from the menu-ready state, whether it's currently queued (in
; !BattleMenu_ReadyQueue) or already in the roster.
;
; If queued: scans the queue for a matching entry and shifts everything
; after it down by one (a generalized version of DequeueReadyBattler's
; shift, starting from wherever the match was found instead of always
; slot 0), then decrements the queue count.
;
; If it's in the roster (!BattleMenu_Roster entry non-negative):
; decrements !BattleMenu_ReadyCount. If it isn't the PC shown
; (!BattleMenu_ActivePc), just clears its roster entry and forces a
; rebuild. If it IS the shown PC, additionally cancels any open
; submenu/targeting state, clears its roster entry, then scans for
; another roster entry to show (or sets "none" if none remain).
; Quirk: when targeting had started from a submenu, it first restores
; !BattleMenu_Submenu to that submenu (ReturnSubmenu - 1), but the
; STZ in .clear_targeting overwrites it at once, so it always ends on
; the main menu; the first store is dead.
;
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E; !Battle_ArgSlot = slot to remove
; Exit:  M=1; registers clobbered
; Callees: BattleMenu_LoadCommandWindowMap
!BattleMenu_RemoveSlot = !BattleTmp_80   ; 1 B: copy of !Battle_ArgSlot
org $C11BAA
BattleMenu_RemoveBattlerFromReady:
    TDC
    TAX
    LDA.b !Battle_ArgSlot
    STA.b !BattleMenu_RemoveSlot
    TAX
    LDA.w !BattleMenu_Roster,X
    BPL .active_roster
    TDC
    TAX
    LDA.b !BattleMenu_RemoveSlot
.scan_queue:
    CMP.w !BattleMenu_ReadyQueue,X
    BEQ .shift_queue
    INX
    CPX.w #!BattleMenu_ReadyQueueSize
    BNE .scan_queue
    RTS                              ; not queued -> nothing to remove
.shift_queue:
    LDA.w !BattleMenu_ReadyQueue+1,X
    STA.w !BattleMenu_ReadyQueue,X
    INX
    CPX.w #!BattleMenu_ReadyQueueSize
    BCC .shift_queue
    DEC.w !BattleMenu_ReadyQueueLen
    RTS
.active_roster:
    DEC.w !BattleMenu_ReadyCount
    CMP.w !BattleMenu_ActivePc      ; the PC shown?
    BEQ .removing_active_pc
    LDA.b !Battle_ArgSlot
    TAX
    LDA.b #!BattleMenu_NoSlot
    STA.w !BattleMenu_Roster,X      ; out of the roster
    LDA.b #!BattleMenu_RosterRedraw
    STA.w !BattleMenu_RosterIdxDrawn ; force a window rebuild
    BRA .redraw
.removing_active_pc:
    LDA.w !BattleMenu_ReturnSubmenu
    BEQ .clear_targeting
    DEC
    STA.w !BattleMenu_Submenu       ; dead store: .clear_targeting zeroes it next
    STZ.w !BattleMenu_ReturnSubmenu
    STZ.w !BattleUI_ForceDigitRefresh
.clear_targeting:
    STZ.w !BattleMenu_TargetSelect
    STZ.w !BattleTgt_Unk960E
    STZ.w !BattleTgt_Cursor
    STZ.w !BattleMenu_Submenu       ; back to the main menu
    STZ.w !Battle_MenuTimeHold
    LDA.b #!BattleMenu_RosterRedraw
    STA.w !BattleMenu_RosterIdxDrawn ; force a window rebuild
    LDA.b !Battle_ArgSlot
    TAX
    LDA.b #!BattleMenu_NoSlot
    STA.w !BattleMenu_Roster,X      ; out of the roster
    TDC
    TAX
.find_next_active:
    LDA.w !BattleMenu_Roster,X      ; entry X (its slot, or negative)
    STA.w !BattleMenu_RosterIdx
    STA.w !BattleMenu_ActivePc
    BPL .redraw                     ; valid -> show it
    INX
    CPX.w #!Battle_NumPcSlots
    BNE .find_next_active
    LDA.b #!BattleMenu_NoSlot       ; none left -> nothing shown
    STA.w !BattleMenu_RosterIdx
    STA.w !BattleMenu_ActivePc
.redraw:
    JSR BattleMenu_LoadCommandWindowMap
    STZ.w !BattleMenu_UnkA862
    RTS

; ==================================================================
; BattleMenu_TargetSelectInput ($C11561–$C11619, 185 bytes)
; ==================================================================
; Per-frame input handler while target selection runs (entered from
; BattleMenu_ProcessInput when !BattleMenu_TargetSelect != 0). Rebuilds
; the target list every call, then either cancels back to the previous
; menu (no valid target, or the cancel button) or polls for confirm
; (either confirm button) / cursor (D-pad) input.
;
; The cancel path restores whichever submenu was open before targeting
; started (!BattleMenu_ReturnSubmenu), redrawing its window (tech: just
; requests the tech box again; item: reloads the item box frame). It
; then hides the four cursor sprites (high-table x bit 8 set, y parked
; at $F0); with the main menu back, the command cursor is redrawn too.
;
; Contains one 18-byte block of dead code ($C115B6-$C115C7): a byte-for-
; byte duplicate of the item box frame copy loop above it, except its
; loop-continue branch (BNE) targets the input polling at .poll_input
; ($C115E8) instead of looping back on itself — meaning on real hardware it always
; escapes after exactly one iteration rather than functioning as a copy
; loop. Nothing in this routine's control flow can reach these bytes
; (both preceding paths branch past them via BRA); reproduced exactly
; regardless, since matching the ROM means matching orphaned bytes too.
;
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; tail-jumps to one of several handlers, does not fall through
; Callees: BattleMenu_BuildTargetList, Battle_PlaySfx0,
;          BattleMenu_CommitAction, BattleMenu_TargetNext,
;          BattleMenu_TargetPrev, Battle_ClearPadEdges
org $C11561
BattleMenu_TargetSelectInput:
    JSR BattleMenu_BuildTargetList
    LDA.w !BattleTgt_Result
    BPL .have_target
    STZ.w !BattleTgt_Cursor         ; no valid target -> cancel
    BRA .cancel
.have_target:
    LDA.b !Battle_PadEdgeButtons
    AND.b #!Battle_PadCancel
    BEQ .poll_input
    JSR Battle_PlaySfx0
.cancel:
    STZ.w !BattleTgt_Cursor
    STZ.w !BattleTgt_Unk960E
    DEC.w !BattleMenu_TargetSelect  ; leave target selection
    LDA.w !BattleMenu_ReturnSubmenu
    BEQ .redraw_cursor
    DEC
    STA.w !BattleMenu_Submenu
    STZ.w !BattleUI_ForceDigitRefresh
    STZ.w !BattleMenu_ReturnSubmenu
    LDA.w !BattleMenu_Submenu
    DEC
    BEQ .tech_return                ; tech list -> request the tech box again
    TDC                             ; item list -> reload the item box frame
    TAX
.copy_loop1:
    LDA.l !BattleRom_ItemBoxMap,X
    STA.w !BattleMenu_WindowMap,X
    INX
    CPX.w #!BattleMenu_WindowBytes
    BNE .copy_loop1
    LDA.b #!BattleMenu_CacheInvalid
    STA.w !BattleMenu_ItemScrollDrawn
    INC.w !BattleMenu_WindowMapDirty
    BRA .redraw_cursor
.tech_return:
    STZ.w !BattleMenu_UnkA869
    INC.w !BattleMenu_TechWindowNew
    BRA .redraw_cursor
; --- dead code: unreachable, see routine header ---
    TDC
    TAX
.dead_copy_loop:
    LDA.l !BattleRom_ItemBoxMap,X
    STA.w !BattleMenu_WindowMap,X
    INX
    CPX.w #!BattleMenu_WindowBytes
    BNE .poll_input                 ; escapes into live code after 1 iteration
    INC.w !BattleMenu_WindowMapDirty
.redraw_cursor:
    LDA.w !BattleMenu_Submenu
    BNE .cursor_drawn
    INC.w !BattleUI_PanelRedraw
.cursor_drawn:
    LDA.w !BattleOam_HighTable
    ORA.b #!BattleOam_HideCursorBits
    STA.w !BattleOam_HighTable
    LDA.b #!BattleOam_OffscreenY
    STA.w BattleOam.Y               ; park the 4 cursor sprites
    STA.w BattleOam[1].Y
    STA.w BattleOam[2].Y
    STA.w BattleOam[3].Y
    BRA .exit
.poll_input:
    LDA.b !Battle_PadEdgeButtons
    AND.b #!Battle_PadConfirmAny
    BEQ .check_cycle
    JSR Battle_PlaySfx0
    JMP BattleMenu_CommitAction
.check_cycle:
    LDA.w !BattleTgt_TargetAll
    BMI .exit                       ; target-all -> no per-target cycling
    LDA.b !Battle_PadEdgeDpad
    AND.b #!Battle_DpadRightDown
    BEQ .check_prev
    INC.w !BattleMenu_TargetMoved
    JSR Battle_PlaySfx0
    JMP BattleMenu_TargetNext
.check_prev:
    LDA.b !Battle_PadEdgeDpad
    AND.b #!Battle_DpadLeftUp
    BEQ .exit
    INC.w !BattleMenu_TargetMoved
    JSR Battle_PlaySfx0
    JMP BattleMenu_TargetPrev
.exit:
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_CommitAction ($C1161A–$C11749, 308 bytes)
; ==================================================================
; Confirms the currently-selected target and builds the command
; record for the shown PC's chosen action (attack/tech/item), then
; queues it and hands the menu to the next ready PC.
;
; Restores whichever submenu was saved for cancel-to-return
; (!BattleMenu_ReturnSubmenu), then dispatches on !BattleMenu_Submenu
; (0=attack, 1=tech, 2=item) to fill in the fields:
;   attack: Kind = $80, Partners = $FF (ActionId left stale)
;   tech:   with !BattleMenu_CfgListMemory on, saves the tech-list cursor
;           and tech id; consumes the partner slot in the low nibble of
;           Tech_CursorEntry.Partners (and, for a triple tech, the high
;           nibble via Battle_ShiftRight4) so those PCs don't also act;
;           Kind = $20, Partners = the nibbles, ActionId = tech id
;   item:   decrements the item's Quantity (record !BattleMenu_ItemRecord),
;           Kind = $40, Partners = $FF, ActionId = item id; resets the
;           item-list cursor unless CfgListMemory is on
; All three converge: remember the command row in !Pc_SavedMenuRow
; (unless !BattleMenu_KeepRow; rows of all PCs reset to 0 unless
; !BattleMenu_CfgCursorMemory), append the PC to !Battle_CmdQueue and
; fill its BattleCmd record (offset from !BattleRom_CmdOffset): State
; bit 6 set / bit 7 cleared, Kind | !Battle_Unk9F38, Menu, the first
; selected target, Partners, ActionId.
; Finally takes the PC out of the roster and shows the next roster
; entry, if any (same shape as BattleMenu_RemoveBattlerFromReady's tail).
;
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: BattleMenu_ConsumePartnerSlot, Battle_ShiftRight4,
;          Battle_ClearPadEdges
; Direct-page roles:
!BattleMenu_CmdKindArg = !BattleTmp_80    ; 1 B: BattleCmd.Kind being built
!BattleMenu_CmdPartners = !BattleTmp_82   ; 1 B: BattleCmd.Partners being built
!BattleMenu_CmdActionId = !BattleTmp_84   ; 1 B: BattleCmd.ActionId being built
!BattleMenu_PartnerArg = !BattleTmp_80    ; 1 B: partner PC slot for ConsumePartnerSlot (its input)
org $C1161A
BattleMenu_CommitAction:
    LDA.w !BattleMenu_ReturnSubmenu
    BEQ .dispatch
    DEC
    STA.w !BattleMenu_Submenu
    STZ.w !BattleMenu_ReturnSubmenu
.dispatch:
    DEC.w !BattleMenu_TargetSelect  ; leave target selection
    LDA.w !BattleMenu_Submenu       ; 0=attack, 1=tech, 2=item
    BNE .not_attack
    LDA.b #!BattleCmd_KindAttack
    STA.b !BattleMenu_CmdKindArg
    LDA.b #!Tech_NoPartners
    STA.b !BattleMenu_CmdPartners
    BRA .after_type
.not_attack:
    DEC
    BNE .item_path
    LDA.w !BattleMenu_CfgListMemory
    BEQ .tech_partner_check
    LDA.w !BattleMenu_ActivePc
    TAX
    LDA.w !Pc_TechScroll,X
    STA.w !Pc_SavedTechScroll,X
    LDA.w !Pc_TechRow,X
    STA.w !Pc_SavedTechRow,X
    LDA.w Tech_CursorEntry.TechId
    STA.w !Pc_SavedTech,X
.tech_partner_check:
    LDA.w Tech_CursorEntry.Partners
    CMP.b #!Tech_NoPartners
    BEQ .tech_type_fields           ; single tech
    AND.b #!Tech_PartnerLoMask      ; first partner slot
    STA.b !BattleMenu_PartnerArg
    JSR BattleMenu_ConsumePartnerSlot
    LDA.w Tech_CursorEntry.Partners
    AND.b #!Tech_PartnerHiMask
    CMP.b #!Tech_PartnerHiMask
    BEQ .tech_type_fields           ; no second partner
    JSR Battle_ShiftRight4          ; second partner slot (triple tech)
    STA.b !BattleMenu_PartnerArg
    JSR BattleMenu_ConsumePartnerSlot
.tech_type_fields:
    LDA.w Tech_CursorEntry.Partners
    STA.b !BattleMenu_CmdPartners
    LDA.w Tech_CursorEntry.TechId
    STA.b !BattleMenu_CmdActionId
    LDA.b #!BattleCmd_KindTech
    STA.b !BattleMenu_CmdKindArg
    BRA .after_type
.item_path:
    LDX.w !BattleMenu_ItemRecord
    DEC.w Item_BattleList.Quantity,X ; use one up
    LDA.b #!BattleMenu_CacheInvalid
    STA.w !BattleMenu_ItemScrollDrawn
    LDA.b #!BattleCmd_KindItem
    STA.b !BattleMenu_CmdKindArg
    LDA.w !BattleMenu_ItemId
    STA.b !BattleMenu_CmdActionId
    LDA.b #!Tech_NoPartners
    STA.b !BattleMenu_CmdPartners
    LDA.w !BattleMenu_CfgListMemory
    BNE .after_type
    STZ.w !BattleMenu_ItemRow
    STZ.w !BattleMenu_ItemScroll
.after_type:
    LDA.w !BattleMenu_KeepRow
    BNE .cursor_done
    LDA.w !BattleMenu_ActivePc
    TAX
    LDA.w !Pc_MenuRow,X
    STA.w !Pc_SavedMenuRow,X        ; remember for this PC
    LDA.w !BattleMenu_CfgCursorMemory
    BNE .cursor_done
    STZ.w !Pc_MenuRow
    STZ.w !Pc_MenuRow+1
    STZ.w !Pc_MenuRow+2
    STZ.w !Pc_SavedMenuRow
    STZ.w !Pc_SavedMenuRow+1
    STZ.w !Pc_SavedMenuRow+2
.cursor_done:
    STZ.w !BattleMenu_KeepRow
    STZ.w !BattleTgt_Unk960E
    STZ.w !BattleTgt_Cursor
    STZ.w !BattleUI_ForceDigitRefresh
    LDA.w !Battle_CmdQueueLen
    TAX
    LDA.w !BattleMenu_ActivePc
    TAY
    STA.w !Battle_CmdQueue,X        ; append this PC
    TAX
    LDA.l !BattleRom_CmdOffset,X    ; slot -> BattleCmd record offset
    TAX
    LDA.w BattleCmd.State,X
    AND.b #!BattleCmd_ClearWaiting
    ORA.b #!BattleCmd_StateQueued
    STA.w BattleCmd.State,X
    LDA.b !BattleMenu_CmdKindArg
    ORA.w !Battle_Unk9F38,Y
    STA.w BattleCmd.Kind,X
    LDA.w !BattleMenu_CmdMenu
    STA.w BattleCmd.Menu,X
    LDA.w !BattleTgt_Selected       ; first selected target
    STA.w BattleCmd.Target,X
    LDA.b !BattleMenu_CmdPartners   ; partner nibbles (or $FF)
    STA.w BattleCmd.Partners,X
    LDA.b !BattleMenu_CmdActionId   ; tech id / item id
    STA.w BattleCmd.ActionId,X
    INC.w !Battle_CmdQueueLen
    STZ.w !BattleMenu_Submenu       ; back to the main menu
    LDA.b #!BattleMenu_RosterRedraw
    STA.w !BattleMenu_RosterIdxDrawn ; force a window rebuild
    DEC.w !BattleMenu_ReadyCount
    LDA.w !BattleMenu_ActivePc
    TAX
    LDA.b #!BattleMenu_NoSlot
    STA.w !BattleMenu_Roster,X      ; out of the roster
    TDC
    TAX
.find_next_active:
    LDA.w !BattleMenu_Roster,X      ; entry X (its slot, or negative)
    STA.w !BattleMenu_RosterIdx
    STA.w !BattleMenu_ActivePc
    BPL .done                       ; valid -> show it
    INX
    CPX.w #!Battle_NumPcSlots
    BNE .find_next_active
    LDA.b #!BattleMenu_NoSlot       ; none left -> nothing shown
    STA.w !BattleMenu_RosterIdx
    STA.w !BattleMenu_ActivePc
.done:
    STZ.w !BattleMenu_UnkA862
    STZ.w !Battle_MenuTimeHold
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_ConsumePartnerSlot ($C1174E–$C1176B, 30 bytes)
; ==================================================================
; Removes PC slot !BattleMenu_PartnerArg from the ready state as part of
; committing a double/triple tech: if it's in the roster, decrements
; !BattleMenu_ReadyCount; either way marks its roster entry empty and
; clears BattleCmd.State bit 7 ("waiting for a command", set by
; BattleMenu_EnqueueReadyBattler) in its command record.
; Entry: M=1, X=0, DB=$7E; !BattleMenu_PartnerArg = partner PC slot
; Exit:  M=1; registers clobbered
; No JSR/JSL calls.
org $C1174E
BattleMenu_ConsumePartnerSlot:
    LDA.b !BattleMenu_PartnerArg
    TAX
    LDA.w !BattleMenu_Roster,X
    BMI .clear_slot
    DEC.w !BattleMenu_ReadyCount
.clear_slot:
    LDA.b #!BattleMenu_NoSlot
    STA.w !BattleMenu_Roster,X      ; out of the roster
    LDA.l !BattleRom_CmdOffset,X    ; slot -> BattleCmd record offset
    TAX
    LDA.w BattleCmd.State,X
    AND.b #!BattleCmd_ClearWaiting  ; no longer waiting for a command
    STA.w BattleCmd.State,X
    RTS

; ==================================================================
; BattleMenu_TargetNext ($C1176C–$C11785, 26 bytes)
; ==================================================================
; Right/Down while cycling targets: advance !BattleTgt_Cursor (wrap at
; 11), skipping empty candidate entries, and select the battler it lands
; on (!BattleTgt_Selected).
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: Battle_ClearPadEdges
org $C1176C
BattleMenu_TargetNext:
    INC.w !BattleTgt_Cursor
    LDA.w !BattleTgt_Cursor
    CMP.b #!Battle_NumSlots
    BNE .have_index
    TDC
    STA.w !BattleTgt_Cursor
.have_index:
    TAX
    LDA.w !BattleTgt_Candidates,X   ; candidate list entry
    BMI BattleMenu_TargetNext       ; invalid -> keep advancing
    STA.w !BattleTgt_Selected
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_TargetPrev ($C11786–$C1179B, 22 bytes)
; ==================================================================
; Left/Up while cycling targets: mirror of TargetNext — steps
; !BattleTgt_Cursor back (wrap to 10) instead. Falls straight through
; into Battle_ClearPadEdges (no JMP needed; they're adjacent in ROM).
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; falls through to Battle_ClearPadEdges
; No JSR/JSL calls.
org $C11786
BattleMenu_TargetPrev:
    DEC.w !BattleTgt_Cursor
    LDA.w !BattleTgt_Cursor
    BPL .have_index
    LDA.b #!Battle_LastSlot
    STA.w !BattleTgt_Cursor
.have_index:
    TAX
    LDA.w !BattleTgt_Candidates,X   ; candidate list entry
    BMI BattleMenu_TargetPrev       ; invalid -> keep decrementing
    STA.w !BattleTgt_Selected

; ==================================================================
; BattleMenu_TechListInput ($C11320–$C11368, 73 bytes)
; ==================================================================
; Per-frame input handler while the tech list is open (submenu 1).
; Computes the highlighted line of the PC's list into
; !BattleMenu_TechListIdx (!Pc_TechScroll + !Pc_TechRow), then polls:
; confirm, cancel, Up or Left = previous, Down or Right = next.
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; tail-jumps to one of several handlers, does not fall through
; Callees: Battle_PlaySfx0, BattleMenu_TechConfirm,
;          BattleMenu_TechListCancel, BattleMenu_TechListPrev,
;          BattleMenu_TechListNext, Battle_ClearPadEdges
!BattleMenu_TechListIdx = !BattleTmp_80  ; 2 B: line of the PC's tech list under the cursor (Prev/Next input)
org $C11320
BattleMenu_TechListInput:
    LDA.w !BattleMenu_ActivePc
    TAX
    LDA.w !Pc_TechScroll,X
    CLC
    ADC.w !Pc_TechRow,X             ; scroll + row
    TAX
    STX.b !BattleMenu_TechListIdx
    LDA.b !Battle_PadEdgeButtons
    AND.b #!Battle_PadConfirm       ; confirm
    BEQ .check_cancel
    JSR Battle_PlaySfx0
    JMP BattleMenu_TechConfirm
.check_cancel:
    LDA.b !Battle_PadEdgeButtons
    AND.b #!Battle_PadCancel        ; cancel
    BEQ .check_up
    JSR Battle_PlaySfx0
    JMP BattleMenu_TechListCancel
.check_up:
    LDA.b !Battle_PadEdgeDpad
    BIT.b #!Battle_DpadUp           ; up
    BNE .do_up
    AND.b #!Battle_DpadLeft         ; left
    BEQ .check_down
.do_up:
    JSR Battle_PlaySfx0
    JMP BattleMenu_TechListPrev
.check_down:
    LDA.b !Battle_PadEdgeDpad
    BIT.b #!Battle_DpadDown         ; down
    BNE .do_down
    AND.b #!Battle_DpadRight        ; right
    BEQ .exit
.do_down:
    JSR Battle_PlaySfx0
    JMP BattleMenu_TechListNext
.exit:
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_TechConfirm ($C11369–$C1138E, 38 bytes)
; ==================================================================
; Confirms the highlighted tech: aborts unless the rows have been graded
; (!BattleMenu_TechAvailDone) and Tech_CursorEntry.Flags bit 7 is clear.
; Otherwise sets !BattleTgt_Mode from the entry's TargetMode, builds the
; target list, and — if a valid target was found — enters target
; selection; if not, just resets the target cursor.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: BattleMenu_BuildTargetList, Battle_ClearPadEdges
org $C11369
BattleMenu_TechConfirm:
    LDA.w !BattleMenu_TechAvailDone
    BEQ .exit                       ; rows not graded yet
    LDA.w Tech_CursorEntry.Flags
    BMI .exit                       ; unusable
    LDA.w Tech_CursorEntry.TargetMode
    STA.w !BattleTgt_Mode
    JSR BattleMenu_BuildTargetList
    LDA.w !BattleTgt_Result         ; target result
    BPL .have_target
    STZ.w !BattleTgt_Cursor
    BRA .exit
.have_target:
    INC.w !BattleMenu_TargetMoved
    INC.w !BattleMenu_TargetSelect  ; enter target-select mode
.exit:
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_TechListCancel ($C1138F–$C113AC, 30 bytes)
; ==================================================================
; Closes the tech list: reload the command window, back to the main menu,
; force a window rebuild, and restore this PC's saved tech-list cursor
; (!Pc_SavedTechRow / SavedTechScroll -> !Pc_TechRow / TechScroll).
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: BattleMenu_LoadCommandWindowMap, Battle_ClearPadEdges
org $C1138F
BattleMenu_TechListCancel:
    JSR BattleMenu_LoadCommandWindowMap
    STZ.w !BattleMenu_Submenu       ; back to the main menu
    LDA.b #!BattleMenu_CacheInvalid
    STA.w !BattleMenu_RosterIdxDrawn ; force command-window reload
    LDA.w !BattleMenu_ActivePc
    TAX
    LDA.w !Pc_SavedTechRow,X        ; saved cursor row
    STA.w !Pc_TechRow,X
    LDA.w !Pc_SavedTechScroll,X     ; saved scroll position
    STA.w !Pc_TechScroll,X
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_TechListPrev ($C113AD–$C113F3, 71 bytes)
; ==================================================================
; Up/Left in the tech list: walks backward from !BattleMenu_TechListIdx
; to the previous line whose !Tech_ListAvail is non-zero. Once found,
; moves the cursor row (!Pc_TechRow) back the same number of lines,
; scrolling the list (!Pc_TechScroll) up a line at a time while the row
; would be negative.
; Entry: M=1, X=0, DB=$7E; !BattleMenu_TechListIdx = current line
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: Battle_ClearPadEdges
!BattleMenu_StepCount = !BattleTmp_82    ; 1 B: lines walked to reach an available tech
!BattleMenu_NewRow = !BattleTmp_83       ; 1 B: cursor row after that walk (may leave 0-2)
org $C113AD
BattleMenu_TechListPrev:
    STZ.b !BattleMenu_StepCount      ; steps walked
    LDA.w !BattleMenu_ActivePc
    TAY
.retry:
    INC.b !BattleMenu_StepCount
    SEC
    LDA.b !BattleMenu_TechListIdx
    SBC #$01
    BCC .no_change                  ; ran off the start -> no-op
    STA.b !BattleMenu_TechListIdx
    TAX
    LDA.w !Tech_ListAvail,X         ; tech availability
    BEQ .retry                      ; unavailable -> keep walking back
    LDA.w !Pc_TechRow,Y             ; current cursor row
    STA.b !BattleMenu_NewRow
    TYX
.shift_loop:
    SEC
    LDA.b !BattleMenu_NewRow
    SBC #$01
    STA.b !BattleMenu_NewRow
    DEC.b !BattleMenu_StepCount
    BNE .shift_loop
    LDA.b !BattleMenu_NewRow
    BPL .no_wrap                    ; row still >= 0, no scroll needed
    LDA.w !Pc_TechScroll,X          ; scroll position
    BEQ .no_change                  ; already at top -> no-op
    LDA.b !BattleMenu_NewRow
    STA.w !Pc_TechRow,X
.dec_scroll:
    DEC.w !Pc_TechScroll,X
    CLC
    LDA.w !Pc_TechRow,X
    ADC #$01
.no_wrap:
    STA.w !Pc_TechRow,X
    BMI .dec_scroll                 ; still negative -> scroll again
.no_change:
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_TechListNext ($C113F4–$C1143C, 73 bytes)
; ==================================================================
; Down/Right in the tech list: mirror of TechListPrev — walks forward
; instead of backward, bounded by the list length (!Pc_TechCount)
; instead of the start of the list, and scrolls down instead of up when
; the new row would reach 3.
; Entry: M=1, X=0, DB=$7E; !BattleMenu_TechListIdx = current line
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: Battle_ClearPadEdges
org $C113F4
BattleMenu_TechListNext:
    STZ.b !BattleMenu_StepCount      ; steps walked
    LDA.w !BattleMenu_ActivePc
    TAY
.retry:
    INC.b !BattleMenu_StepCount
    CLC
    LDA.b !BattleMenu_TechListIdx
    ADC #$01
    CMP.w !Pc_TechCount,Y           ; list length for this PC
    BCS .exit                       ; ran off the end -> no-op
    STA.b !BattleMenu_TechListIdx
    TAX
    LDA.w !Tech_ListAvail,X         ; tech availability
    BEQ .retry                      ; unavailable -> keep walking forward
    LDA.w !Pc_TechRow,Y             ; current cursor row
    STA.b !BattleMenu_NewRow
    TYX
.shift_loop:
    CLC
    LDA.b !BattleMenu_NewRow
    ADC #$01
    STA.b !BattleMenu_NewRow
    DEC.b !BattleMenu_StepCount
    BNE .shift_loop
    LDA.b !BattleMenu_NewRow
    CMP.b #!BattleMenu_ListRows
    BCC .no_wrap                    ; row still < 3, no scroll needed
    LDA.b !BattleMenu_NewRow
    STA.w !Pc_TechRow,X
.inc_scroll:
    INC.w !Pc_TechScroll,X          ; scroll position
    SEC
    LDA.w !Pc_TechRow,X
    SBC #$01
.no_wrap:
    STA.w !Pc_TechRow,X
    CMP.b #!BattleMenu_ListRows
    BCS .inc_scroll                 ; still >= 3 -> scroll again
.exit:
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_ItemListInput ($C1143D–$C11497, 91 bytes)
; ==================================================================
; Per-frame input handler while the item list is open (submenu 2).
; Unlike the tech list, item rows have no per-slot "available" flag to
; skip during cursor movement — up/down just move the cursor one row
; and scroll via ItemListScrollUp/Down at the edges. The page buttons
; page the whole list up/down by 3 rows at once.
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; tail-jumps to one of several handlers, does not fall through
; Callees: Battle_PlaySfx0, BattleMenu_ItemConfirm,
;          BattleMenu_ItemListCancel, BattleMenu_ItemCursorUp,
;          BattleMenu_ItemCursorDown, BattleMenu_ItemListPageDown,
;          BattleMenu_ItemListPageUp, BattleMenu_ItemListRefresh,
;          Battle_ClearPadEdges
org $C1143D
BattleMenu_ItemListInput:
    LDA.b !Battle_PadEdgeButtons
    AND.b #!Battle_PadConfirm       ; confirm
    BEQ .check_cancel
    JSR Battle_PlaySfx0
    JMP BattleMenu_ItemConfirm
.check_cancel:
    LDA.b !Battle_PadEdgeButtons
    AND.b #!Battle_PadCancel        ; cancel
    BEQ .check_up
    JSR Battle_PlaySfx0
    JMP BattleMenu_ItemListCancel
.check_up:
    LDA.b !Battle_PadEdgeDpad
    BIT.b #!Battle_DpadUp           ; up
    BNE .do_up
    AND.b #!Battle_DpadLeft         ; left
    BEQ .check_down
.do_up:
    JSR Battle_PlaySfx0
    JMP BattleMenu_ItemCursorUp
.check_down:
    LDA.b !Battle_PadEdgeDpad
    BIT.b #!Battle_DpadDown         ; down
    BNE .do_down
    AND.b #!Battle_DpadRight        ; right
    BEQ .check_page_down
.do_down:
    JSR Battle_PlaySfx0
    JMP BattleMenu_ItemCursorDown
.check_page_down:
    LDA.b !Battle_PadEdgeButtons
    AND.b #!Battle_PadPageDown      ; page down (3 rows)
    BEQ .check_page_up
    JSR Battle_PlaySfx0
    JMP BattleMenu_ItemListPageDown
.check_page_up:
    LDA.b !Battle_PadEdgeButtons
    AND.b #!Battle_PadPageUp        ; page up (3 rows)
    BEQ .check_refresh
    JSR Battle_PlaySfx0
    JMP BattleMenu_ItemListPageUp
.check_refresh:
    LDA.w !BattleMenu_ItemRefresh
    BEQ .exit
    JMP BattleMenu_ItemListRefresh
.exit:
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_ItemConfirm ($C11498–$C114DA, 67 bytes)
; ==================================================================
; Confirms the highlighted item: record offset = (!BattleMenu_ItemScroll
; + !BattleMenu_ItemRow) * 5 into Item_BattleList (id, target mode,
; flags, quantity, PC mask). Aborts if Flags
; bit 7 is set or the quantity is zero. Otherwise sets
; !BattleMenu_ItemId, !BattleTgt_Mode and !BattleMenu_ItemRecord, builds
; the target list, and enters target selection if a valid target was
; found.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: Battle_Mul8, BattleMenu_BuildTargetList, Battle_ClearPadEdges
!BattleMenu_ItemListIdx = !BattleTmp_80  ; 1 B: list line under the cursor (scroll + row)
org $C11498
BattleMenu_ItemConfirm:
    CLC
    LDA.w !BattleMenu_ItemScroll
    ADC.w !BattleMenu_ItemRow       ; line under the cursor
    STA.b !BattleMenu_ItemListIdx
    STA.b !Battle_Mul8A
    LDA.b #!Item_RecordSize
    STA.b !Battle_Mul8B
    JSR Battle_Mul8                 ; line * 5 = record offset
    LDX.b !Battle_Mul8Product
    LDA.w Item_BattleList.Flags,X
    BMI .exit                       ; unusable
    LDA.w Item_BattleList.Quantity,X
    BEQ .exit                       ; none left
    LDA.w Item_BattleList.Id,X
    STA.w !BattleMenu_ItemId
    LDA.w Item_BattleList.TargetMode,X
    STA.w !BattleTgt_Mode
    STX.w !BattleMenu_ItemRecord
    JSR BattleMenu_BuildTargetList
    LDA.w !BattleTgt_Result         ; target result
    BPL .have_target
    STZ.w !BattleTgt_Cursor
    BRA .exit
.have_target:
    INC.w !BattleMenu_TargetMoved
    INC.w !BattleMenu_TargetSelect  ; enter target-select mode
.exit:
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_ItemListCancel ($C114DB–$C114EB, 17 bytes)
; ==================================================================
; Closes the item list: reload the command window, back to the main
; menu, force a window rebuild, and invalidate the scroll-arrow cache.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: BattleMenu_LoadCommandWindowMap, Battle_ClearPadEdges
org $C114DB
BattleMenu_ItemListCancel:
    JSR BattleMenu_LoadCommandWindowMap
    STZ.w !BattleMenu_Submenu       ; back to the main menu
    LDA.b #!BattleMenu_CacheInvalid
    STA.w !BattleMenu_RosterIdxDrawn ; force command-window reload
    STA.w !BattleMenu_ItemScrollDrawn ; redraw the arrows next time
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_ItemCursorUp ($C114EC–$C11501, 22 bytes)
; ==================================================================
; Up/Left in the item list: decrement !BattleMenu_ItemRow, scrolling the
; list up via ItemListScrollUp when already at the top row.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: BattleMenu_ItemListScrollUp, Battle_ClearPadEdges
org $C114EC
BattleMenu_ItemCursorUp:
    LDA.w !BattleMenu_ItemRow       ; cursor row
    BNE .move
    JSR BattleMenu_ItemListScrollUp
.move:
    SEC
    LDA.w !BattleMenu_ItemRow
    SBC #$01
    BCC .exit
    STA.w !BattleMenu_ItemRow
.exit:
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_ItemCursorDown ($C11502–$C1151B, 26 bytes)
; ==================================================================
; Down/Right in the item list: increment !BattleMenu_ItemRow (max 2),
; scrolling the list down via ItemListScrollDown when already at the
; bottom row.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: BattleMenu_ItemListScrollDown, Battle_ClearPadEdges
org $C11502
BattleMenu_ItemCursorDown:
    LDA.w !BattleMenu_ItemRow       ; cursor row
    CMP.b #!BattleMenu_LastRow
    BNE .move
    JSR BattleMenu_ItemListScrollDown
.move:
    CLC
    LDA.w !BattleMenu_ItemRow
    ADC #$01
    CMP.b #!BattleMenu_ListRows
    BCS .exit
    STA.w !BattleMenu_ItemRow
.exit:
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_ItemListPageDown ($C1151C–$C11536, 27 bytes)
; ==================================================================
; Page-down button: page the item list down 3 rows at once, clamped at
; scroll position $FA. Sets !BattleMenu_ItemScroll and
; !BattleMenu_ListScroll itself, then JSRs directly into
; ItemListScrollDown's shared render+indicator tail
; (BattleMenu_ItemListScrollDown_RenderTail) rather than duplicating
; that logic.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: BattleMenu_ItemListScrollDown_RenderTail, Battle_ClearPadEdges
org $C1151C
BattleMenu_ItemListPageDown:
    CLC
    LDA.w !BattleMenu_ItemScroll    ; scroll position
    ADC.b #!BattleMenu_ListRows
    CMP.b #!Item_MaxScroll
    BCS .clamp
    CMP #$00
    BNE .have_scroll
.clamp:
    LDA.b #!Item_MaxScroll
.have_scroll:
    STA.w !BattleMenu_ItemScroll
    STA.b !BattleMenu_ListScroll
    JSR BattleMenu_ItemListScrollDown_RenderTail
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_ItemListPageUp ($C11537–$C1154A, 20 bytes)
; ==================================================================
; Page-up button: page the item list up 3 rows at once, clamped at 0.
; Mirror of ItemListPageDown, JSRs into ItemListScrollUp's shared
; render+indicator tail (BattleMenu_ItemListScrollUp_RenderTail).
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: BattleMenu_ItemListScrollUp_RenderTail, Battle_ClearPadEdges
org $C11537
BattleMenu_ItemListPageUp:
    SEC
    LDA.w !BattleMenu_ItemScroll    ; scroll position
    SBC.b #!BattleMenu_ListRows
    BCS .have_scroll
    TDC
.have_scroll:
    STA.w !BattleMenu_ItemScroll
    STA.b !BattleMenu_ListScroll
    JSR BattleMenu_ItemListScrollUp_RenderTail
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_ItemListRefresh ($C1154B–$C11560, 22 bytes)
; ==================================================================
; Re-renders the item list rows and invalidates both draw
; caches when !BattleMenu_ItemRefresh is set, clearing it.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ClearPadEdges
; Callees: BattleMenu_RenderItemListRows, Battle_ClearPadEdges
org $C1154B
BattleMenu_ItemListRefresh:
    LDA.w !BattleMenu_ItemScroll    ; scroll position
    STA.b !BattleMenu_ListScroll
    JSR BattleMenu_RenderItemListRows
    LDA.b #!BattleMenu_CacheInvalid
    STA.w !BattleMenu_ItemRowDrawn  ; redraw the row cursor
    STA.w !BattleMenu_ItemScrollDrawn ; and the arrows
    STZ.w !BattleMenu_ItemRefresh
    JMP Battle_ClearPadEdges

; ==================================================================
; BattleMenu_ItemListScrollUp ($C117A1–$C117BE, 30 bytes)
; ==================================================================
; Scrolls the item list up one row: decrements !BattleMenu_ItemScroll (min 0), then
; re-renders and invalidates both draw caches (row cursor, arrows).
;
; Contains a redundant double branch: after testing the scroll for 0 once,
; a second BEQ immediately re-tests the same (unchanged) zero flag —
; its target (skip both the decrement AND the render, straight to the
; indicator writes) can never actually be reached, since reaching that
; second branch at all requires the first BEQ to have found the flag
; clear. Reproduced exactly regardless.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1
; Callees: BattleMenu_RenderItemListRows
; Global (non-dot) labels throughout: BattleMenu_ItemListScrollUp_RenderTail
; is a real external entry point (called directly by BattleMenu_ItemListPageUp,
; which sets the scroll itself and skips straight to the render), and per
; this project's asar-quirk-6 workaround, a JSR target reached from another
; routine's scope must not be a local .dot label.
org $C117A1
BattleMenu_ItemListScrollUp:
    LDA.w !BattleMenu_ItemScroll    ; scroll position
    BEQ BattleMenu_ItemListScrollUp_SetScroll
    BEQ BattleMenu_ItemListScrollUp_SkipRender ; unreachable: flag already tested clear above
    SEC
    LDA.w !BattleMenu_ItemScroll
    SBC #$01
    STA.w !BattleMenu_ItemScroll
BattleMenu_ItemListScrollUp_SetScroll:
    STA.b !BattleMenu_ListScroll
BattleMenu_ItemListScrollUp_RenderTail:
    JSR BattleMenu_RenderItemListRows
BattleMenu_ItemListScrollUp_SkipRender:
    LDA.b #!BattleMenu_CacheInvalid
    STA.w !BattleMenu_ItemRowDrawn  ; redraw the row cursor
    STA.w !BattleMenu_ItemScrollDrawn ; and the arrows
    RTS

; ==================================================================
; BattleMenu_ItemListScrollDown ($C117BF–$C117DC, 30 bytes)
; ==================================================================
; Scrolls the item list down one row: increments !BattleMenu_ItemScroll (clamped at
; $FA), then re-renders and invalidates both draw caches.
; Mirror of ItemListScrollUp, but with a single, genuinely-reachable
; bounds check instead of the redundant double branch — when already
; at the clamp, skips both the increment AND the render entirely.
; BattleMenu_ItemListScrollDown_RenderTail is the external entry point
; called directly by BattleMenu_ItemListPageDown.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1
; Callees: BattleMenu_RenderItemListRows
org $C117BF
BattleMenu_ItemListScrollDown:
    LDA.w !BattleMenu_ItemScroll    ; scroll position
    CMP.b #!Item_MaxScroll
    BCS BattleMenu_ItemListScrollDown_SkipRender ; already at max -> skip increment and render
    CLC
    LDA.w !BattleMenu_ItemScroll
    ADC #$01
    STA.w !BattleMenu_ItemScroll
    STA.b !BattleMenu_ListScroll
BattleMenu_ItemListScrollDown_RenderTail:
    JSR BattleMenu_RenderItemListRows
BattleMenu_ItemListScrollDown_SkipRender:
    LDA.b #!BattleMenu_CacheInvalid
    STA.w !BattleMenu_ItemRowDrawn  ; redraw the row cursor
    STA.w !BattleMenu_ItemScrollDrawn ; and the arrows
    RTS

; ==================================================================
; BattleMenu_UpdateCursorOverlay ($C117DD–$C11B18, 828 bytes)
; ==================================================================
; Per-frame cursor/overlay refresh, called once per frame from the end
; of the menu rebuild chain (after ProcessInput). Draws whatever cursor
; graphic belongs on screen right now, dispatching on menu state:
;
;   no PC shown (!BattleMenu_ActivePc < 0) -> hide the 4 cursor sprites
;   target selection (!BattleMenu_TargetSelect) -> target cursor(s)
;   else, by !BattleMenu_Submenu:
;     0 (main)  -> nothing to do here (DrawCursorSprites already ran
;                  from ProcessInput); just fall through to the tail
;     1 (tech)  -> tech-list cursor: normal single highlight, or a
;                  2-3 sprite cluster over the caster + double/triple-
;                  tech partner(s) when the highlighted tech needs them
;     2 (item)  -> item-list cursor: redraws the scroll arrows and the
;                  row cursor quad, queuing the item map upload only if
;                  either changed
;
; Target selection draws either one cursor on the first selected target
; (with, on the main menu, an info-panel message for an enemy target
; through BattleMsg_ShowMsg0BIfKeyChangedVec / BattleMsg_UnkVecCD0030),
; or, when a second target is selected, a sweep over the selection list
; that fills up to 4 cursor sprites per frame and resumes next frame
; from !BattleTgt_SweepResume.
;
; Common idiom (X = any battler slot 0-10): cursor position =
;   !Battler_ScreenX/Y (same tables DrawCursorSprites uses) +
;   !Battler_ScreenOffsetX/Y (inferred: the battler's current animated
;   offset) − !BattleOam_CursorCentreX on x, written into one of the
;   four cursor sprites (BattleOam[0-3]).
;
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; pad-edge bytes cleared (shared tail, same as
;        Battle_ClearPadEdges elsewhere)
; Callees: Battle_ShiftRight4, BattleMenu_ClearTechCursorTiles,
;          BattleMenu_DrawCursorSprites, BattleMsg_ShowMsg0BIfKeyChangedVec,
;          BattleMsg_UnkVecCD0030 (sibling message vector, not analysed),
;          Battle_QueueVramUpload_0E80
; Direct-page roles:
!BattleMenu_OverlayChanged = !BattleTmp_80 ; 1 B: item path: non-zero when arrows or row cursor changed
!BattleMenu_TargetStats = !BattleTmp_80   ; 2 B: single target: BattlerStats offset of the target
!BattleTgt_SweepIdx = !BattleTmp_80       ; 2 B: multi target: selection-list index being drawn
!BattleMenu_SweepOam = !BattleTmp_82      ; 2 B: multi target: cursor sprite being filled
org $C117DD
BattleMenu_UpdateCursorOverlay:
    LDA.w !BattleMenu_ActivePc      ; (signed; <0 = none)
    BPL .check_target_select
    JMP .no_active_pc
.check_target_select:
    LDA.w !BattleMenu_TargetSelect
    BEQ .dispatch_submenu
    JMP .target_select
.dispatch_submenu:
    LDA.w !BattleMenu_Submenu       ; 0=main, 1=tech, 2=item
    BEQ .main_menu
    DEC
    BNE .item_dispatch
    JMP .tech_path
.item_dispatch:
    JMP .item_path
.main_menu:
    JMP .tail

; ------------------------------------------------------------------
; Tech-list cursor ($17FE-$18A9)
; ------------------------------------------------------------------
; Tech_CursorEntry.TechId (copied by UpdateTechWindow) below $39 means
; a single-character tech — those never need partner highlighting, so go
; straight to the normal single cursor. $39 and up are double/triple
; techs; the low nibble of Tech_CursorEntry.Partners names the first
; partner slot (sentinel $FF = "no entry resolved yet", also falls back
; to the normal single cursor).
.tech_path:
    LDA.w Tech_CursorEntry.TechId
    CMP.b #!Tech_FirstComboId
    BCS .tech_check_group
.tech_single_jmp:
    JMP .tech_single_cursor
.tech_check_group:
    LDA.w Tech_CursorEntry.Partners
    CMP.b #!Tech_NoPartners
    BEQ .tech_single_jmp
    LDA.w !BattleOam_HighTable      ; hide all 4 cursor sprites first
    ORA.b #!BattleOam_HideCursorBits
    STA.w !BattleOam_HighTable
    LDA.b #!BattleOam_OffscreenY
    STA.w BattleOam.Y
    STA.w BattleOam[1].Y
    STA.w BattleOam[2].Y
    STA.w BattleOam[3].Y
    LDA.b #!BattleOam_CursorAttr
    STA.w BattleOam.Attr
    STA.w BattleOam[1].Attr
    STA.w BattleOam[2].Attr
    STZ.w BattleOam.Tile
    STZ.w BattleOam[1].Tile
    STZ.w BattleOam[2].Tile
    ; sprite 0: caster (the shown PC)
    LDA.w !BattleMenu_ActivePc
    TAX
    CLC
    LDA.w !Battler_ScreenX,X
    ADC.w !Battler_ScreenOffsetX,X
    SEC
    SBC.b #!BattleOam_CursorCentreX
    STA.w BattleOam.X
    CLC
    LDA.w !Battler_ScreenY,X
    ADC.w !Battler_ScreenOffsetY,X
    STA.w BattleOam.Y
    ; sprite 1: first partner (low nibble of Partners)
    LDA.w Tech_CursorEntry.Partners
    AND.b #!Tech_PartnerLoMask
    TAX
    CLC
    LDA.w !Battler_ScreenX,X
    ADC.w !Battler_ScreenOffsetX,X
    SEC
    SBC.b #!BattleOam_CursorCentreX
    STA.w BattleOam[1].X
    CLC
    LDA.w !Battler_ScreenY,X
    ADC.w !Battler_ScreenOffsetY,X
    STA.w BattleOam[1].Y
    LDA.w !BattleOam_HighTable      ; show sprites 0 and 1
    AND.b #!BattleOam_ShowSprite0
    AND.b #!BattleOam_ShowSprite1
    STA.w !BattleOam_HighTable
    ; sprite 2: second partner, only for a triple tech (high nibble of
    ; Partners present; $F = "no second partner")
    LDA.w Tech_CursorEntry.Partners
    AND.b #!Tech_PartnerHiMask
    CMP.b #!Tech_PartnerHiMask
    BEQ .tech_group_done
    JSR Battle_ShiftRight4          ; high nibble -> low nibble
    TAX
    CLC
    LDA.w !Battler_ScreenX,X
    ADC.w !Battler_ScreenOffsetX,X
    SEC
    SBC.b #!BattleOam_CursorCentreX
    STA.w BattleOam[2].X
    CLC
    LDA.w !Battler_ScreenY,X
    ADC.w !Battler_ScreenOffsetY,X
    STA.w BattleOam[2].Y
    LDA.w !BattleOam_HighTable      ; show sprite 2
    AND.b #!BattleOam_ShowSprite2
    STA.w !BattleOam_HighTable
.tech_group_done:
    JMP .tail
.tech_single_cursor:
    JSR BattleMenu_DrawCursorSprites
    JMP .tail

; ------------------------------------------------------------------
; Item-list cursor ($18B0-$1978)
; ------------------------------------------------------------------
; Two independent change-tracked updates, each only redrawn (and only
; queued to VRAM) when its cached compare value differs from the live
; one; !BattleMenu_OverlayChanged tallies whether either changed.
.item_path:
    STZ.b !BattleMenu_OverlayChanged
    ; Scroll arrows: redraw the up/down arrow cells whenever
    ; !BattleMenu_ItemScroll differs from !BattleMenu_ItemScrollDrawn.
    ; Tile $FF hides an arrow. Both arrows use the same tile ($7F); the
    ; down arrow gets attribute $A9 = palette 2 + vertical flip, which
    ; turns it upside down.
    LDA.w !BattleMenu_ItemScroll
    CMP.w !BattleMenu_ItemScrollDrawn
    BNE .arrow_check_zero
    JMP .row_check
.arrow_check_zero:
    LDA.w !BattleMenu_ItemScroll
    BNE .arrow_check_max
    LDA.b #!BattleUI_TileBlank      ; top of list -> hide up arrow
    STA.w !BattleMenu_UpArrowTile
    LDA.b #!BattleMenu_TileArrow    ; down arrow
    STA.w !BattleMenu_DownArrowTile
    LDA.b #!BattleUI_AttrPal2VFlip
    STA.w !BattleMenu_UpArrowAttr
    STA.w !BattleMenu_DownArrowAttr
    BRA .arrow_done
.arrow_check_max:
    LDA.w !BattleMenu_ItemScroll
    CMP.b #!Item_MaxScroll
    BEQ .arrow_at_max
    LDA.b #!BattleMenu_TileArrow    ; middle of list -> both arrows visible
    STA.w !BattleMenu_UpArrowTile
    STA.w !BattleMenu_DownArrowTile
    LDA.b #!BattleUI_AttrPal2       ; up arrow upright
    STA.w !BattleMenu_UpArrowAttr
    LDA.b #!BattleUI_AttrPal2VFlip  ; down arrow flipped
    STA.w !BattleMenu_DownArrowAttr
    BRA .arrow_done
.arrow_at_max:
    LDA.b #!BattleMenu_TileArrow    ; up arrow
    STA.w !BattleMenu_UpArrowTile
    LDA.b #!BattleUI_TileBlank      ; bottom of list -> hide down arrow
    STA.w !BattleMenu_DownArrowTile
    LDA.b #!BattleUI_AttrPal2
    STA.w !BattleMenu_UpArrowAttr
    STA.w !BattleMenu_DownArrowAttr
.arrow_done:
    INC.b !BattleMenu_OverlayChanged
    ; Row cursor: if either the cursor row or the scroll position changed,
    ; blank the old row's 2×2 cursor (placed through
    ; !BattleRom_ItemCursorCell) and draw the new one (tiles $60-$63,
    ; palette 2) — the same cursor quad BattleMenu_DrawTechCursorRow uses.
.row_check:
    LDA.w !BattleMenu_ItemRow
    CMP.w !BattleMenu_ItemRowDrawn
    BNE .row_redraw
    LDA.w !BattleMenu_ItemScroll
    CMP.w !BattleMenu_ItemScrollDrawn
    BEQ .item_upload_check
    STA.w !BattleMenu_ItemScrollDrawn
.row_redraw:
    LDA.w !BattleMenu_ItemRowDrawn
    BPL .have_old_row
    TDC
.have_old_row:
    ASL
    TAX
    REP #$20                        ; A=16-bit: 16-bit table entry
    LDA.l !BattleRom_ItemCursorCell,X
    TAX
    TDC
    SEP #$20                        ; A=8-bit
    LDA.b #!BattleUI_TileBlank
    STA.w BattleMenu_ItemTile(0,0),X
    STA.w BattleMenu_ItemTile(0,1),X
    STA.w BattleMenu_ItemTile(1,0),X
    STA.w BattleMenu_ItemTile(1,1),X
    LDA.w !BattleMenu_ItemRow
    STA.w !BattleMenu_ItemRowDrawn  ; remember the new row
    ASL
    TAX
    REP #$20
    LDA.l !BattleRom_ItemCursorCell,X
    TAX
    TDC
    SEP #$20
    LDA.b #!BattleMenu_TileCursorTL
    STA.w BattleMenu_ItemTile(0,0),X
    LDA.b #!BattleMenu_TileCursorTR
    STA.w BattleMenu_ItemTile(0,1),X
    LDA.b #!BattleMenu_TileCursorBL
    STA.w BattleMenu_ItemTile(1,0),X
    LDA.b #!BattleMenu_TileCursorBR
    STA.w BattleMenu_ItemTile(1,1),X
    LDA.b #!BattleUI_AttrPal2
    STA.w BattleMenu_ItemAttr(0,0),X
    STA.w BattleMenu_ItemAttr(0,1),X
    STA.w BattleMenu_ItemAttr(1,0),X
    STA.w BattleMenu_ItemAttr(1,1),X
    INC.b !BattleMenu_OverlayChanged
.item_upload_check:
    LDA.b !BattleMenu_OverlayChanged
    BEQ .item_no_upload
    JSL Battle_QueueVramUpload_0E80
.item_no_upload:
    JMP .tail

; ------------------------------------------------------------------
; Target-select cursor ($1979-$1AFD)
; ------------------------------------------------------------------
.target_select:
    LDA.w !BattleTgt_Result         ; 0 = target found, <0 = none
    BPL .target_have
    JMP .to_tail
.target_have:
    LDA.w !BattleMenu_Submenu
    DEC
    BNE .target_hide_tech_cursor_done
    JSR BattleMenu_ClearTechCursorTiles ; targeting from the tech list
.target_hide_tech_cursor_done:
    LDA.w !BattleOam_HighTable      ; hide all 4 cursor sprites first
    ORA.b #!BattleOam_HideCursorBits
    STA.w !BattleOam_HighTable
    LDA.b #!BattleOam_CursorAttr
    STA.w BattleOam.Attr
    STA.w BattleOam[1].Attr
    STA.w BattleOam[2].Attr
    STA.w BattleOam[3].Attr
    STZ.w BattleOam.Tile
    STZ.w BattleOam[1].Tile
    STZ.w BattleOam[2].Tile
    STZ.w BattleOam[3].Tile
    LDA.w !BattleTgt_Selected+1     ; a second target selected?
    BMI .target_check_primary
    JMP .multi_target
.target_check_primary:
    LDA.w !BattleTgt_Selected       ; first target
    BPL .target_single
    JMP .to_tail
.target_single:
    STA.w !BattleTgt_Highlight
    TAX
    CLC
    LDA.w !Battler_ScreenX,X
    ADC.w !Battler_ScreenOffsetX,X
    SEC
    SBC.b #!BattleOam_CursorCentreX
    STA.w BattleOam.X
    CLC
    LDA.w !Battler_ScreenY,X
    ADC.w !Battler_ScreenOffsetY,X
    STA.w BattleOam.Y
    LDA.w !BattleMenu_Submenu
    BNE .after_info_panel
    LDA.w !BattleTgt_Highlight
    CMP.b #!Battle_FirstEnemySlot   ; slot < 3 -> a PC: no info panel
    BCC .after_info_panel
    ; enemy target from the main (attack) menu: info-panel message.
    ; With !Battle_Unk9F34 and the target's !Battler_Unk9F29 set, the
    ; message gets the target's HP too (BattleMsg_ShowMsg0BIfKeyChangedVec);
    ; otherwise BattleMsg_UnkVecCD0030. Either way the argument is the
    ; target slot, or $FF when BattleRom_UnkE1DE80[Unk984D] is set.
    ASL
    TAX
    LDA.w !Battler_Unk984D,X
    STA.w BattleMsg_InfoArgs.Id
    LDA.l !BattleRom_StatsOffset,X
    STA.b !BattleMenu_TargetStats
    LDA.l !BattleRom_StatsOffset+1,X
    STA.b !BattleMenu_TargetStats+1
    LDA.w !Battle_Unk9F34
    BEQ .panel_check_arg
    LDA.w !BattleTgt_Highlight
    TAY
    LDA.w !Battler_Unk9F29,Y
    BNE .panel_with_hp              ; the panel also shows the target's HP
.panel_check_arg:
    LDA.w BattleMsg_InfoArgs.Id
    TAX
    LDA.l !BattleRom_UnkE1DE80,X
    BEQ .panel_arg_slot
    LDA.b #!BattleMsg_ArgNone
    BRA .panel_send
.panel_arg_slot:
    LDA.w !BattleTgt_Highlight
.panel_send:
    JSL BattleMsg_UnkVecCD0030
    BRA .after_info_panel
.panel_with_hp:
    LDX.b !BattleMenu_TargetStats
    LDA.w BattlerStats.CurHp,X      ; the target's HP / MaxHP -> InfoArgs
    STA.w BattleMsg_InfoArgs.CurHp
    LDA.w BattlerStats.CurHp+1,X
    STA.w BattleMsg_InfoArgs.CurHp+1
    LDA.w BattlerStats.MaxHp,X
    STA.w BattleMsg_InfoArgs.MaxHp
    LDA.w BattlerStats.MaxHp+1,X
    STA.w BattleMsg_InfoArgs.MaxHp+1
    LDA.w BattleMsg_InfoArgs.Id
    TAX
    LDA.l !BattleRom_UnkE1DE80,X
    BEQ .panel_hp_arg_slot
    LDA.b #!BattleMsg_ArgNone
    BRA .panel_hp_send
.panel_hp_arg_slot:
    LDA.w !BattleTgt_Highlight
.panel_hp_send:
    JSL BattleMsg_ShowMsg0BIfKeyChangedVec
.after_info_panel:
    LDA.w !BattleOam_HighTable      ; show sprite 0 (the single cursor)
    AND.b #!BattleOam_ShowSprite0
    STA.w !BattleOam_HighTable
    ; !Battle_UnkEC latch, updated only right after the target moved
    ; (!BattleMenu_TargetMoved) and when the cursor may move: set when
    ; the cursor's y is above CursorTopY, cleared at CursorBottomY or
    ; below (what the latch is for is not known)
    LDA.w !BattleMenu_TargetMoved
    BEQ .latch_done
    STZ.w !BattleMenu_TargetMoved
    LDA.w !BattleTgt_CanCycle
    BEQ .latch_done
    LDA.b !Battle_UnkEC
    BNE .latch_check_bottom         ; latched: clear it at the bottom
    LDA.w BattleOam.Y
    CMP.b #!BattleMenu_CursorTopY
    BCS .latch_done
    INC.b !Battle_UnkEC
    BRA .latch_done
.latch_check_bottom:
    LDA.w BattleOam.Y
    CMP.b #!BattleMenu_CursorBottomY
    BCC .latch_done
    STZ.b !Battle_UnkEC
.latch_done:
    JMP .to_tail

; ------------------------------------------------------------------
; Multi-target ("target all") cursor sweep ($1A7B-$1AFA)
; ------------------------------------------------------------------
; Sprite 0 marks the first selected target; sprites 1-3 mark selection
; entries 0-2 on one frame and 3-5 on the next (!BattleTgt_SweepResume
; alternates 3 / 0), stopping early if the 4 sprites run out. Entries
; 6-10 are never reached by this sweep.
.multi_target:
    LDA.w !BattleTgt_Selected
    BMI .multi_loop_init
    TAX
    CLC
    LDA.w !Battler_ScreenX,X
    ADC.w !Battler_ScreenOffsetX,X
    SEC
    SBC.b #!BattleOam_CursorCentreX
    STA.w BattleOam.X
    CLC
    LDA.w !Battler_ScreenY,X
    ADC.w !Battler_ScreenOffsetY,X
    STA.w BattleOam.Y
    LDA.w !BattleOam_HighTable
    AND.l !BattleRom_OamShowMask    ; show sprite 0
    STA.w !BattleOam_HighTable
.multi_loop_init:
    LDY #$0001
    STY.b !BattleMenu_SweepOam      ; next sprite (0 is done above)
    LDA.w !BattleTgt_SweepResume
    TAY
    STY.b !BattleTgt_SweepIdx
.multi_loop:
    LDY.b !BattleTgt_SweepIdx
    LDA.w !BattleTgt_Selected,Y
    BMI .multi_loop_next
    TAX
    LDA.b !BattleMenu_SweepOam
    ASL
    ASL
    TAY                             ; Y = sprite × 4
    CLC
    LDA.w !Battler_ScreenX,X
    ADC.w !Battler_ScreenOffsetX,X
    SEC
    SBC.b #!BattleOam_CursorCentreX
    STA.w BattleOam.X,Y
    CLC
    LDA.w !Battler_ScreenY,X
    ADC.w !Battler_ScreenOffsetY,X
    STA.w BattleOam.Y,Y
    LDX.b !BattleMenu_SweepOam
    LDA.w !BattleOam_HighTable
    AND.l !BattleRom_OamShowMask,X  ; show this sprite
    STA.w !BattleOam_HighTable
.multi_loop_next:
    INC.b !BattleTgt_SweepIdx
    LDA.b !BattleTgt_SweepIdx
    CMP.b #!BattleTgt_SweepBatch
    BEQ .multi_loop_cap
    CMP.b #!BattleTgt_SweepWrap
    BEQ .multi_loop_cap
    INC.b !BattleMenu_SweepOam
    LDA.b !BattleMenu_SweepOam
    CMP.b #!BattleOam_CursorSprites
    BNE .multi_loop
.multi_loop_cap:
    LDA.b !BattleTgt_SweepIdx
    CMP.b #!BattleTgt_SweepWrap
    BNE .multi_loop_save
    TDC
.multi_loop_save:
    STA.w !BattleTgt_SweepResume    ; save scan index for next frame
.to_tail:
    JMP .tail

.no_active_pc:
    LDA.w !BattleOam_HighTable      ; hide all 4 main-cursor OAM slots
    ORA.b #!BattleOam_HideCursorBits
    STA.w !BattleOam_HighTable
    LDA.b #!BattleOam_OffscreenY
    STA.w BattleOam.Y
    STA.w BattleOam[1].Y
    STA.w BattleOam[2].Y
    STA.w BattleOam[3].Y
.tail:
    STZ.b !Battle_PadEdgeButtons    ; clear pad-edge bytes (same tail idiom
    STZ.b !Battle_PadEdgeDpad       ; as Battle_ClearPadEdges)
    RTS
