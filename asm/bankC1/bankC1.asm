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
; Frame Wait ($C1:007E–$C1:0088)
; ============================================================

; $C1:007E — BattleSys_PumpFrames (11 bytes, $007E–$0088)
; Waits for the next frame: sets !Battle_FramePending, then calls
; BattleSys_IdleVecCD0036 again and again until something else clears
; the flag. The likely clearer is the STZ $9E at $CF:E77B, just before
; the RTL of a bank-$CF routine that reads JOY1 ($CF:E6E0, $CF:E70B) and
; bumps a 32-bit counter at $96F1, which reads as per-frame work; its
; entry and who calls it are not traced, so "wait for the frame" is
; inferred, not proven. ($CF:FB65 also zeroes $9E, but it is the battle
; entry, reached once from the field: JSL $C10000 at $C0:18A7 -> JMP
; $001B -> JML $CFFB65, which clears battle RAM and JMLs to $C1:8000.)
; What the $CD0036 callee does meanwhile is not analysed.
; Callers (JSR; scanned for JSR/JSL/JML/JMP/BRL, hits inside other
; instructions discarded): BattleSys_UpkeepTwoFrames (twice),
; BattleSys_DefeatPose, BattleSys_VictoryPose (three times),
; Battle_RunPcPose, and the unmatched code at $C1:405F, $C1:40A0,
; $C1:40B0, $C1:40E1, $C1:4116, $C1:414B, $C1:41B4, $C1:41B7, $C1:4841,
; $C1:485B, $C1:4864, $C1:488D, $C1:4943.
; Entry: M=1 (8-bit INC/LDA of the flag), X any, DP=0, DB=$7E (as at
;        every caller; the routine itself only touches direct page)
; Exit:  M=1, DP=0; A = 0; X, Y, DB as the $CD0036 callee leaves them
;        (not analysed)
; Callee: BattleSys_IdleVecCD0036
org $C1007E
BattleSys_PumpFrames:
    INC.b !Battle_FramePending
.wait:
    JSL BattleSys_IdleVecCD0036
    LDA.b !Battle_FramePending
    BNE .wait                   ; cleared elsewhere (likely $CF:E77B)
    RTS

; ============================================================
; Math Utility Cluster ($C1:0089–$C1:011E)
; ============================================================

; $C1:0089 — Battle_Mul8 (30 bytes, $0089–$00A6)
; 8×8→16 HW multiply via WRMPYA/WRMPYB/RDMPYL.
; In:  !Battle_Mul8A = multiplicand, !Battle_Mul8B = multiplier
; Out: !Battle_Mul8Product = 16-bit product; operands mirrored to
;      !Battle_MulMirrorA/B
; The two NOPs after REP are multiply latency: the 8x8 product is only
; valid in RDMPYL 8 cycles after the WRMPYB write.
; Entry: M=1, X either width, DP=0, DB any (the HW registers are reached
;        with STA.l/LDA.l, so the caller's data bank does not matter)
; Exit:  M=1; A=0 (TDC with DP=0); X/Y and DB unchanged; DP $77/$78 and
;        $AF/$B0 written
; Callers: 20 JSR sites across bank $C1: BattleMenu_ItemConfirm
; ($C1:14A7), Battle_DrawBattlerFrameAnyLayout ($C1:1CBE),
; BattlePos_CheckDist ($C1:2B8D, $C1:2B9A), BattlePos_DistDifference
; ($C1:2D14, $C1:2D2A, $C1:2D4B, $C1:2D61) and 12 in unmatched code
; (e.g. $C1:607B, $C1:7878). No calls.
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
; Sets DB=0 itself (PHB / TDC / PHA / PLB: A=D=0 because DP=0) so STA.w
; reaches the HW registers, and restores the caller's DB at the end.
; PHP..PLP brackets the REP #$21 so the caller's M/X/C come back; the SEP
; #$20 after PLP is redundant (PLP has already restored M=1).
; Entry: M=1, X=0 (LDX.w RDMPYL / STX.b move the 16-bit first product),
;        DP=0, DB any
; Exit:  M=1, X=0 (P restored); A=0; X = first partial product; Y and DB
;        unchanged; DP $77/$78 and $A9-$AB written
; Callers: 20 JSR sites across bank $C1: Battle_SinLookup ($C1:021C),
; Battle_DrawBattlerFrameAnyLayout ($C1:1C7F), Battle_TickPcSlots
; ($C1:2E98), Battle_TickEnemyGroup ($C1:33A5), Battle_RunPcPose
; ($C1:35FF) and 15 in unmatched code (e.g. $C1:509B). No calls.
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
; 16÷8 HW divide via WRDIVL/WRDIVH/WRDIVB, quotient from RDDIVL and
; remainder from RDMPYL.
; In:  !Battle_DivDividend (16-bit), !Battle_DivDivisor (8-bit)
; Out: !Battle_DivQuotient, !Battle_DivRemainder (16-bit each);
;      operands mirrored to !Battle_DivMirrorLo/Hi/Divisor
; Brackets the work with INC/STZ !Battle_DivBusy (busy flag in WRAM).
; Entry: M=1, X either width, DP=0, DB=$7E (INC.w/STZ.w !Battle_DivBusy at
;        $A029, outside the low-RAM mirror); HW registers use .l
; Exit:  M=1; A=0 (TDC with DP=0); X/Y unchanged; DP $79-$7B and $B5-$B8
;        written
; Callers: 19 JSR sites across bank $C1: BattleUI_DrawSlotGaugeBar
; ($C1:071D), Battle_TickPcSlots ($C1:2ECF) and 17 in unmatched code
; (e.g. $C1:5084, $C1:6311, $C1:7731). No calls.
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
; Left-shift chain: Battle_ShiftLeft8 (8 ASL → *256) → Battle_ShiftLeft4
;   (4 ASL → *16) → Battle_ShiftLeft3 (3 ASL → *8, RTS)
; Right-shift chain: Battle_ShiftRight8 (8 LSR → >>8) → Battle_ShiftRight6
;   (>>6) → Battle_ShiftRight5 (>>5) → Battle_ShiftRight4 (>>4)
;   → Battle_ShiftRight3 (>>3, RTS)
; The other seven labels are sub-entries documented here.
; Callers (all JSR, by entry point):
;   Battle_ShiftLeft8: BattleUI_DrawSlotGaugeBar ($C1:0715), $C1:660C,
;     $C1:6634
;   Battle_ShiftLeft4: Battle_FxReset ($C1:30CF), Battle_FxOverlay2Tint
;     ($C1:310F)
;   Battle_ShiftLeft3: Battle_TickEnemyGroup ($C1:3410, $C1:3471), $C1:48BA
;   Battle_ShiftRight8: BattlePos_DistDifference ($C1:2D73)
;   Battle_ShiftRight6: $C1:3AB7, $C1:3C41, $C1:53B2, $C1:53B9
;   Battle_ShiftRight5: $C1:39F6, $C1:39FE, $C1:3A0A, $C1:3A12
;   Battle_ShiftRight4 (15 sites): BattleMenu_UpdateTechMpAvail,
;     BattleMenu_CommitAction, BattleMenu_UpdateCursorOverlay,
;     BattleTgt_AreaCircle (4), and $C1:4A81, $C1:4A9F, $C1:67C6, $C1:685B,
;     $C1:68F4, $C1:6B72, $C1:6C1D, $C1:6CCC
;   Battle_ShiftRight3: BattleUI_DrawPcNamePanel, BattleUI_UpdateNextPcPanel,
;     BattleUI_DrawSlotGaugeBar, $C1:78C6, $C1:78F3, $C1:7963, $C1:7990
; Entry: M either width (A shifted at its current width), X, DP, DB any
; Exit:  M, X, DP, DB unchanged; A shifted; C = last bit shifted out;
;        X/Y and memory untouched
org $C1010D
Battle_ShiftLeft8:          ; A <<= 8 (4 here, then falls through ShiftLeft4's 1 + ShiftLeft3's 3)
    ASL A
    ASL A
    ASL A
    ASL A
Battle_ShiftLeft4:          ; A <<= 4 (falls through ShiftLeft3 chain); header: see Battle_ShiftLeft8
    ASL A
Battle_ShiftLeft3:          ; A <<= 3; header: see Battle_ShiftLeft8
    ASL A
    ASL A
    ASL A
    RTS
Battle_ShiftRight8:         ; A >>= 8 (2 extra LSR before ShiftRight6 chain); header: see Battle_ShiftLeft8
    LSR A
    LSR A
Battle_ShiftRight6:         ; A >>= 6; header: see Battle_ShiftLeft8
    LSR A
Battle_ShiftRight5:         ; A >>= 5; header: see Battle_ShiftLeft8
    LSR A
Battle_ShiftRight4:         ; A >>= 4; header: see Battle_ShiftLeft8
    LSR A
Battle_ShiftRight3:         ; A >>= 3; header: see Battle_ShiftLeft8
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
; Callers (JSR): BattleUI_DrawPcNamePanel ($C1:039A, $C1:03EE) and
;   BattleUI_UpdateNextPcPanel ($C1:0628).
; Entry: M=0 (16-bit A), X=0 (16-bit), DP=0 (TDC / TAX zeroes the digit
;        counters only because D=0), DB=$7E (WRAM accessible)
; Exit:  M=1 (8-bit A), X=0; X and Y unchanged (PHX/PLX); A = blank tile;
;        !BattleMsg_NumValue consumed
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
; Callers (9 JSR sites): BattleUI_DrawPcNamePanel ($C1:0444),
;   BattleUI_UpdateNextPcPanel ($C1:0686), BattleMenu_RenderItemRow
;   ($C1:0A41) and BattleMenu_UpdateTechWindow (6 sites).
; Entry: M=0 (16-bit A), X=0 (16-bit), DP=0 (TDC as zero), DB=$7E
; Exit:  M=1 (8-bit A), X=0; X and Y unchanged (PHX/PLX); A = blank tile;
;        !BattleMsg_NumValue consumed
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
; Callers (JSR): BattleMenu_RenderItemRow ($C1:09E2) and
;   BattleMenu_RenderTechRow ($C1:0B7C).
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0 (TDC / TAX as zero), DB any
;        (nothing touches memory before the MVN)
; Exit:  M=1, X=0; DB=$7E (set by the MVN); A, X, Y clobbered
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
; Callers (46 JSR sites): BattleTgt_AreaLine (4 sites), BattlePos_PathClear
;   ($C1:2C38, $C1:2C42) and 40 in unmatched code (e.g. $C1:37D7,
;   $C1:37E1).
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0, DB any (table read with .l);
;        angle in A
; Exit:  M=1, X=0; A = !Battle_MulProduct+1 (product >> 8); X clobbered
;        (Mul8x16 leaves its first partial product there); Y and DB
;        unchanged; DP $77/$78 and $A5-$AB written
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
; Callers (37 JSR sites): BattleTgt_AreaPartyTriangle (9 sites),
;   BattleTgt_AreaLine ($C1:25C7, $C1:26A3, $C1:26CC), BattlePos_PathClear
;   ($C1:2C27), Battle_UpdatePcFacing ($C1:2F82),
;   Battle_FaceAllPcsNearestEnemy ($C1:353B) and 22 in unmatched code
;   (e.g. $C1:37C9).
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0 (TDC as zero), DB any (table
;        read with .l); !Battle_GeoOriginX/Y, !Battle_GeoPointX/Y
; Exit:  M=1, X=0; angle in A and !Battle_GeoAngle; X = table index;
;        Y and DB unchanged; DP $D7-$E3 written
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

; $C1:0299 — BattleUI_BuildStatusBarFrame (108 bytes, $0299–$0304; it
; falls into BattleUI_DrawPcNamePanel and BattleUI_NextNamePanel, which
; run to $05A6)
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
; Callers (JSR): BattleMenu_UpdateMainWindow ($C1:0C5C) and unmatched code
;   at $C1:0027.
; Entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $80-$87, $8E and
;        $A2/$A3 used as temporaries, plus the callees' DP: $79-$7B,
;        $82/$83, $86, $AD/$AE and $B1-$B8 (DrawSlotGaugeBar, through
;        Battle_Divide) and $80-$84 (DrawCommandList, DrawCommandWindowFrames);
;        !BattleMsg_NumValue and !BattleUI_LowHp overwritten
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
    ; --- BattleUI_DrawPcNamePanel ($C1:0305) ---
    ; Writes one PC slot's name, HP/MP and ATB gauge into the status map. Loop body:
    ; BattleUI_NextNamePanel advances PanelDest/Slot and JMPs back here.
    ; Entry: M=1, X=0, DP=0, DB=$7E; !BattleUI_Slot = PC slot,
    ;        !BattleUI_PanelDest = its name cell
    ; Exit:  continues into BattleUI_NextNamePanel (same state; A/X/Y and
    ;        the DP listed for BuildStatusBarFrame clobbered)
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
    BNE .hp_spacer
    LDA.b #!BattleUI_TileHpSlash    ; layout 0: separator before MaxHP
    STA.w BattleUI_StatusTile(0,3),Y
    BRA .maxhp_fmt
.hp_spacer:
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
    BNE .mp_place_12
    JSR BattleMsg_BlankLeadingZeros ; (both layout paths blank)
    BRA .mp_place_0
.mp_place_12:                       ; layouts 1/2: MP digits at the MP cell
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
    ; --- BattleUI_NextNamePanel ($C1:04C5): loop tail ---
    ; Next PC slot (JMP back to DrawPcNamePanel), then the enemy-name lines
    ; and the command windows; ends BuildStatusBarFrame (RTS or tail JMP to
    ; BattleUI_HighlightPcName). Reached by falling in, by BEQ/BRA from
    ; .gauge_caps above, and by JMP from BattleUI_DrawPcNamePanel ($C1:030E)
    ; when the slot holds no PC.
    ; Entry/Exit: as BattleUI_BuildStatusBarFrame (M=1, X=0, DP=0, DB=$7E)
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
; BattleUI_UpdateNextPcPanel ($C1:05A7–$C1:06DA, 308 bytes; falls into
; BattleUI_DrawAtbGauges and BattleUI_UpdateNextPcPanel_Exit, to $06EF)
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
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $80/$81, $86/$87,
;        $A2/$A3, !BattleUI_LowHp and !BattleMsg_NumValue used as
;        temporaries, plus DrawSlotGaugeBar's $79-$7B, $82/$83, $86,
;        $AD/$AE and $B1-$B8
; Calls: Battle_ShiftRight3, BattleMsg_FormatNumberDigits,
;        BattleMsg_BlankLeadingZeros, BattleMsg_FormatTwoDigits, BattleUI_DrawSlotGaugeBar
; Caller: BattleMenu_UpdateMainWindow (when the shown roster entry has not
;        changed, so no full BuildStatusBarFrame is needed)
; Sub-entry: BattleUI_DrawAtbGauges ($06DB) — X = first PC slot; redraw the
;        ATB gauges from there to slot 2 (same entry state; only reached
;        by falling in from above, X = 0)
; BattleUI_UpdateNextPcPanel_Exit ($06EF) is the shared RTS.
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
    BNE .mp_cell_l12
    CLC
    LDA.b !BattleUI_PanelBase
    ADC.w #!BattleUI_MpCellL0
    TAY                             ; (redundant: .mp_dest_done does TAY again)
    BRA .mp_dest_done
.mp_cell_l12:
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
BattleUI_DrawAtbGauges:             ; header: see BattleUI_UpdateNextPcPanel
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
BattleUI_UpdateNextPcPanel_Exit:    ; header: see BattleUI_UpdateNextPcPanel
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
; Entry: M=1, X=0 (16-bit), DP=0, DB=$7E (.w !Pc_AtbCur/!Pc_AtbMax, and
;        Battle_Divide's !Battle_DivBusy); !BattleUI_Slot = PC slot (0–2)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X clobbered; Y = gauge start + 2 x
;        the whole TileGauge8 tiles (the partial tile's offset, written
;        only when units are left over: Y = start + 8 for an empty gauge,
;        start for a full one); DP $79–$7B, $82/$83, $86, $AD/$AE and
;        $B1–$B8 clobbered ($B7/$B8 is Battle_Divide's 16-bit remainder)
; Callers: BattleUI_DrawPcNamePanel, BattleUI_DrawAtbGauges
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
; Entry: M=1, X=0 (16-bit), DP=0, DB=$7E (.w !Pc_Unk9F25/!BattleUI_UnkA117/
;        !BattleMenu_Roster), A = PC slot (0–2)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $80-$83 clobbered
; Caller: BattleUI_NextNamePanel (once per roster PC). No calls.
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

; $C1:081E — BattleMenu_DrawCommandWindowFrames (84 bytes, $081E–$0871;
; falls into BattleUI_ClearActivePanelColumn, which runs to $08E7)
; Draw the 7×6 command-window frame of every PC in the roster into
; !BattleMenu_WindowMap, then highlight the shown PC's name and fall into
; BattleUI_ClearActivePanelColumn. Slot 1's / slot 2's frame is drawn
; joined (!BattleUI_FrameJoined = 1: without its left border column, one
; cell further right) when the slot before it is also in the roster, so
; it shares that window's right border; else it is drawn whole.
; BattleUI_ClearActivePanelColumn ($0872) is also called on its own
; (BattleMenu_UpdateMainWindow) when only the cursor column needs redrawing.
; It sets !BattleUI_PanelRedraw before falling in, so the command cursor
; is always redrawn (unless a target selection is running); the fall-through
; leaves !BattleUI_PanelRedraw = 0.
; Entry: M=1, X=0 (16-bit), DP=0, DB=$7E (.w !BattleMenu_Roster)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $80-$84 clobbered
;        ($81 is FrameRowsLeft and the high byte of ColumnOffset);
;        !BattleUI_PanelRedraw = 0
; Caller: BattleUI_NextNamePanel
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
; Entry: M=1, X=0 (16-bit), DP=0, DB=$7E (.w !BattleMenu_ActivePc/!Pc_MenuRow)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y and DP $80/$81 clobbered;
;        !BattleUI_PanelRedraw = 0
; Callers: falls in from BattleMenu_DrawCommandWindowFrames; JSR from
;        BattleMenu_UpdateMainWindow. No calls.
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
; Entry: M=1, X=0 (16-bit), DP=0, DB=$7E (.w !BattleUI_GaugeLayout),
;        A = PC slot (0–2)
; Exit:  M=1, X=0, DP=0, DB=$7E; X = offset; A = !BattleUI_AttrPal2;
;        Y and DP unchanged
; Callers: BattleMenu_DrawCommandWindowFrames (JSR); BattleUI_NextNamePanel
;        (tail JMP). No calls.
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
; Entry: M=1, X=0 (16-bit), DP=0, DB=$7E (STA.w !BattleMenu_WindowMap at
;        $0B40 lands in WRAM through the $7E bank),
;        !BattleUI_MapOffset = map offset, !BattleUI_FrameJoined = 0 for
;        a whole frame
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y and DP $80-$83 clobbered
; Caller: BattleMenu_DrawCommandWindowFrames (up to 3 times). No calls.
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
; Entry: M=1, X=0 (16-bit), DP=0 (TDC as zero), DB=$7E;
;        !BattleMenu_ListScroll = scroll position
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $80-$87, $8E-$8F,
;        $96-$98 clobbered (the last three partly by BattleMenu_RenderItemRow)
; Callers: BattleMenu_OpenItemList, BattleMenu_ItemListRefresh,
;        BattleMenu_ItemListScrollUp_RenderTail, BattleMenu_ItemListScrollDown_RenderTail
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

; $C1:09B0 — BattleMenu_RenderItemRow (215 bytes, $09B0–$0A86), then its
;             RTS BattleMenu_RenderItemRow_Exit (1 byte, $0A87)
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
; Entry: M=1, X=0 (16-bit), DP=0, DB=$7E; !BattleMenu_ItemRecOffset,
;        !BattleMenu_RowMapOffset
; Exit:  M=1, X=0, DP=0, DB=$7E (the MVN also sets $7E); A, X, Y
;        clobbered; DP $84-$85, $8E-$8F, $98 clobbered;
;        !BattleMsg_TextTiles/TextTopTiles/TextSource and the digit cells
;        overwritten
; Caller: BattleMenu_RenderItemListRows (3 times)
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
    JMP BattleMenu_RenderItemRow_Exit              ; skip this line
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
BattleMenu_RenderItemRow_Exit:      ; header: see BattleMenu_RenderItemRow
    RTS

; $C1:0A88 — BattleMenu_RenderTechListRows (75 bytes, $0A88–$0AD2)
; Renders 4 tech-list lines (2 per outer loop pass) for the active PC
; into the tech text buffer (BattleMenu_TechTextTile). First line =
; !BattleRom_TechListBase[PC] + !Pc_TechScroll[PC]; each line advances
; the map offset by !BattleMenu_ListRowStride.
; Entry: M=1, X=0 (16-bit), DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $80-$83, $86-$89,
;        $8E-$91 and $AF clobbered (with RenderTechRow's)
; Callers: BattleMenu_UpdateTechWindow, BattleMenu_OpenTechList
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
; Entry: M=1, X=0 (16-bit), DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y and DP $80 clobbered
; Caller: BattleMenu_OpenTechList. No JSR/JSL calls.
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
;   $FF/$FE → blank line (via BattleMenu_DrawTechLowerRow)
;   $FD     → "Triple Technique" header (!BattleRom_TechFixedText + $12)
;   $FC     → "Double Technique" header (!BattleRom_TechFixedText + 0)
;             (each 18 bytes, the text between end glyphs $5B and $5C)
;   $FB     → blank line: the still-blank text rows go through the tech-name
;             path, so cols 3-20 of both rows are blanked
;   else    → tech name: bank $CC, !Tech_NameTable + code × 11, re-encoded;
;             upper/lower rows from col 6, palette 3
; Every path advances !BattleMenu_TechRowNum.
; Entry: M=1, X=0 (16-bit), DP=0 (TDC as zero), DB=$7E;
;        !BattleMenu_TechCodeIdx, !BattleMenu_RowMapOffset
; Exit:  M=1, X=0, DP=0, DB=$7E (the MVN also sets $7E), through one of
;        its tail JMPs; A, X, Y clobbered; DP $88 and $8E-$91 clobbered;
;        !BattleMsg_TextTiles/TextTopTiles/TextSource overwritten
; Caller: BattleMenu_RenderTechListRows (4 times)
; Calls: BattleMsg_ReencodeTextBuffer, BattleMenu_BlankNameLeadCells;
;        tail JMPs to BattleMenu_DrawTechLowerRow (header/blank lines) or
;        BattleMenu_BlankNameTailCells (tech names)
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
    JMP BattleMenu_DrawTechLowerRow
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
    JMP BattleMenu_BlankNameTailCells
    RTS                             ; dead: unreachable after the JMP, kept for the byte

; $C1:0BB6 — BattleMenu_DrawTechLowerRow (29 bytes, $0BB6–$0BD2)
; Blank-line / header exit path of BattleMenu_RenderTechRow: advances
; !BattleMenu_TechRowNum, blanks the lead cells, then copies 18 lower-row
; tiles from !BattleMsg_TextTiles into the line from col 3 (palette 3).
; Reached only by JMP from BattleMenu_RenderTechRow.
; Entry: M=1, X=0 (16-bit), DP=0 (TDC as zero), DB=$7E; !BattleMenu_RowMapOffset
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $88 advanced
; Calls: BattleMenu_BlankNameLeadCells
org $C10BB6
BattleMenu_DrawTechLowerRow:
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
; (blank tile, palette 3).
; Called from BattleMenu_RenderTechRow and BattleMenu_DrawTechLowerRow.
; Entry: M=1, X=0 (16-bit), DP=0 (TDC as zero), DB=$7E; !BattleMenu_RowMapOffset
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; no DP written
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

; $C1:0C00 — BattleMenu_BlankNameTailCells (45 bytes, $0C00–$0C2C)
; Tech-name exit path of BattleMenu_RenderTechRow (reached by its tail
; JMP): blanks cols 17-20 (right of the 11-tile name) on both rows of the
; line (blank tile, palette 3); the mirror of BattleMenu_BlankNameLeadCells.
; Entry: M=1, X=0 (16-bit), DP=0 (TDC as zero), DB=$7E; !BattleMenu_RowMapOffset
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; no DP written
; No JSR/JSL calls.
org $C10C00
BattleMenu_BlankNameTailCells:
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
; BattleMenu_UpdateWindows ($C10C2D–$C10C45, 25 bytes; then
; BattleMenu_UpdateWindows_Exit, $C10C46–$C10C48)
; ==================================================================
; Per-frame window upkeep dispatcher. Calls BattleFx_SetPtrA2FromTable
; with the shown PC, then dispatches on !BattleMenu_Submenu:
;   0 → BattleMenu_UpdateMainWindow
;   1 → BattleMenu_UpdateTechMpAvail + BattleMenu_UpdateTechWindow
;   other → BattleMenu_UpdateWindows_Exit → BattleMenu_Return (RTS)
; Callers (4 JSRs, checked in the ROM): BattleMenu_RefreshIfDirtyL,
;   BattleMenu_RefreshIfDirtyAndTick, BattleSys_UpkeepTwoFrames (behind
;   the same !BattleMenu_Dirty gate) and BattleSys_VictoryPose.
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered, plus the DP scratch of
;        whichever window routine ran (see their headers) and whatever
;        BattleFx_SetPtrA2FromTable (not matched yet) changes
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
    BNE BattleMenu_UpdateWindows_Exit                 ; item list: nothing to do here
    JSR BattleMenu_UpdateTechMpAvail ; tech list: grade the rows first
    JMP BattleMenu_UpdateTechWindow  ; then refresh the window

BattleMenu_UpdateWindows_Exit:      ; shared exit — branched to from UpdateMainWindow too; header: see BattleMenu_UpdateWindows
    JMP BattleMenu_Return           ; → shared RTS at $103D

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
; The opening Submenu != 0 test is redundant: the only way in is the JMP
; from BattleMenu_UpdateWindows, taken only when !BattleMenu_Submenu = 0
; (no other JSR/JMP to $0C49 in the bank).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E (through BattleMenu_Return); A, X, Y
;        clobbered, plus the callees' DP: BuildStatusBarFrame's or
;        UpdateNextPcPanel's (see their headers), $80/$81 from
;        ClearActivePanelColumn, and whatever Battle_QueueVramUpload_0CC0
;        (not matched yet) changes
; Callees: BattleMenu_LoadCommandWindowMap, BattleUI_BuildStatusBarFrame,
;          BattleUI_UpdateNextPcPanel, BattleUI_ClearActivePanelColumn,
;          Battle_QueueVramUpload_0CC0
BattleMenu_UpdateMainWindow:
    LDA.w !BattleMenu_Submenu       ; must still be the main menu
    BNE BattleMenu_UpdateWindows_Exit
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
    JMP BattleMenu_Return              ; → shared RTS at $103D

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
; Reached only by the JMP from BattleMenu_UpdateWindows (submenu 1).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E; !BattleMenu_ActivePc = PC shown
; Exit:  M=1, X=0, DP=0, DB=$7E (via BattleMenu_DrawTechCursorRow →
;        BattleMenu_Return); A, X, Y clobbered; DP $80-$83, $86-$89,
;        $8E-$91 and $AF/$B0 clobbered (with RenderTechListRows');
;        !BattleMsg_NumValue and the digit cells overwritten
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
.slot0_two_digits:                  ; tens digit non-zero: cost 10 or more
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
.slot1_two_digits:                  ; tens digit non-zero: cost 10 or more
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
.slot2_two_digits:                  ; tens digit non-zero: cost 10 or more
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
; Reached by fall-through or JMP/branch from BattleMenu_UpdateTechWindow only.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E (via BattleMenu_Return); A, X, Y and DP $80
;        clobbered, plus whatever the two JSL targets (not matched yet)
;        change
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
    JMP BattleMenu_Return              ; → shared RTS at $103D

; ==================================================================
; BattleMenu_ClearTechCursorTiles ($C10EBA–$C10EE0, 39 bytes)
; ==================================================================
; Blanks cols 1-2 (the row-cursor columns) of all 6 tech-window rows.
; Callers: BattleMenu_DrawTechCursorRow, BattleMenu_UpdateCursorOverlay
; Entry: M=1, X either width, DP any (no DP access), DB=$7E
; Exit:  M, X, DP, DB unchanged; A=$FF; X/Y unchanged
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
; BattleMenu_UpdateTechMpAvail ($C10EE1–$C1103C, 348 bytes; falls into the
; shared RTS BattleMenu_Return at $C1103D)
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
; Caller: BattleMenu_UpdateWindows (submenu 1), just before UpdateTechWindow.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E; !BattleMenu_ActivePc = PC shown
; Exit:  M=1, X=0, DP=0, DB=$7E (falls into BattleMenu_Return); A, X, Y
;        clobbered; DP $80-$89, $94, $96-$9B and $AF/$B0 clobbered
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
.row_loop:                          ; per visible row (JMP back from the loop tail)
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
    BNE .grade_entry                ; a real entry
    ; special line ($Fx): only the two headers are graded
    LDA.w !Tech_ListCode,X
    CMP.b #!Tech_CodeDoubleHeader
    BNE .check_triple_header
    LDA.w !BattleMenu_ReadyCount
    CMP.b #!BattleMenu_DoubleTechPcs
    BCC .set_grey                   ; fewer than 2 PCs ready → grey
    BRA .to_colour_line             ; else keep palette 2
.check_triple_header:
    CMP.b #!Tech_CodeTripleHeader
    BNE .to_colour_line             ; other special line → keep palette 2
    LDA.w !BattleMenu_ReadyCount
    CMP.b #!BattleMenu_TripleTechPcs
    BCS .to_colour_line             ; 3 PCs ready → keep palette 2
.set_grey:                          ; header line: grey
    LDA.b #!BattleUI_AttrPal3
    STA.b !BattleMenu_MpRowAttr
.to_colour_line:                    ; the header branches converge here
    JMP .colour_line                ; → colour the line

.grade_entry:
    ; Tech_MenuEntry offset of the line's entry, then the cost tests
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
    BMI .check_slot1_cost           ; $80+ → not involved
    SEC
    LDA.b !BattleMenu_MpPc0
    SBC.w Tech_MenuEntry.MpCost0,X
    LDA.b !BattleMenu_MpPc0+1
    SBC #$00
    BCC .set_unusable               ; borrow → can't afford

.check_slot1_cost:
    ; PC slot 1's MP vs its cost
    LDA.w Tech_MenuEntry.MpCost1,X
    BMI .check_slot2_cost
    SEC
    LDA.b !BattleMenu_MpPc1
    SBC.w Tech_MenuEntry.MpCost1,X
    LDA.b !BattleMenu_MpPc1+1
    SBC #$00
    BCC .set_unusable

.check_slot2_cost:
    ; PC slot 2's MP vs its cost
    LDA.w Tech_MenuEntry.MpCost2,X
    BMI .check_partners
    SEC
    LDA.b !BattleMenu_MpPc2
    SBC.w Tech_MenuEntry.MpCost2,X
    LDA.b !BattleMenu_MpPc2+1
    SBC #$00
    BCC .set_unusable

.check_partners:
    ; partners must be menu-ready
    LDA.w Tech_MenuEntry.Partners,X
    STA.b !BattleMenu_MpPartners
    CMP.b #!Tech_NoPartners
    BEQ .partners_ready             ; single tech: no partners to check
    AND.b #!Tech_PartnerLoMask      ; first partner slot
    STA.b !BattleMenu_ReadySlotArg
    JSR BattleSys_SlotMenuReadyPredicate ; A=0 if ready
    BNE .set_unusable               ; not ready → grey
    LDA.b !BattleMenu_MpPartners
    AND.b #!Tech_PartnerHiMask
    CMP.b #!Tech_PartnerHiMask      ; no second partner (double tech)?
    BEQ .partners_ready
    JSR Battle_ShiftRight4          ; second partner slot
    STA.b !BattleMenu_ReadySlotArg
    JSR BattleSys_SlotMenuReadyPredicate
    BNE .set_unusable

.partners_ready:
    ; the shown PC must not be locked; tech $74 needs one more check
    LDA.w !BattleMenu_ActivePc
    TAX
    LDA.w !Pc_LockStatus,X
    BNE .set_unusable               ; locked → grey
    LDX.b !BattleMenu_MpEntry
    LDA.w Tech_MenuEntry.TechId,X
    CMP.b #!Tech_IdUnk74
    BNE .set_usable
    LDX.w !Battle_UnkA0FF
    LDA.w !Battle_Unk1C48,X
    CMP.b #!Battle_Unk1C48Wanted
    BNE .set_unusable               ; fail → grey

.set_usable:
    LDX.b !BattleMenu_MpEntry
    LDA.w Tech_MenuEntry.Flags,X
    AND.b #!Tech_FlagUsableMask     ; usable
    STA.w Tech_MenuEntry.Flags,X
    LDA.b #!BattleUI_AttrPal2
    STA.b !BattleMenu_MpRowAttr
    BRA .colour_line                ; → colour the line

.set_unusable:                      ; can't afford / partner not ready / locked / tech $74 check failed
    LDX.b !BattleMenu_MpEntry
    LDA.w Tech_MenuEntry.Flags,X
    ORA.b #!Tech_FlagUnusable       ; unusable
    STA.w Tech_MenuEntry.Flags,X
    LDA.b #!BattleUI_AttrPal3       ; greyed
    STA.b !BattleMenu_MpRowAttr

.colour_line:                       ; colour both rows of the line, then next row
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
    JMP .row_loop                   ; next row
.done:
    LDA #$01
    STA.w !BattleMenu_TechAvailDone ; rows graded
; Shared RTS, also the JMP target of BattleMenu_UpdateMainWindow,
; BattleMenu_DrawTechCursorRow and BattleMenu_UpdateWindows_Exit.
; header: see BattleMenu_UpdateTechMpAvail
BattleMenu_Return:
    RTS

; ==================================================================
; BattleSys_SlotMenuReadyPredicate ($C1103E–$C1104D, 16 bytes)
; ==================================================================
; Returns A=0 if PC slot !BattleMenu_ReadySlotArg is menu-ready: in the
; roster (!BattleMenu_Roster entry not negative) and !Pc_LockStatus clear;
; nonzero otherwise. The callers (UpdateTechMpAvail, twice) BNE straight
; after the JSR, so the Z flag is the real result: the ready path ends
; with TDC, which gives A=0 and Z set only because DP=0.
; Callers (JSR): BattleMenu_UpdateTechMpAvail ($C1:0FBE, $C1:0FD0).
; Entry: M=1, X=0 (16-bit), DP=0, DB=$7E; !BattleMenu_ReadySlotArg = PC slot
; Exit:  M=1, X=0, DP=0, DB=$7E; Z set iff ready (A = 0), else Z clear and
;        A non-zero; X clobbered; Y unchanged
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
; Always called straight after a formatter: 8 of its 11 call sites follow
; BattleMsg_FormatTwoDigits (hundreds already blank, so only the tens test
; matters) and 3 follow BattleMsg_FormatNumberDigits (the HP and MaxHP
; digits).
; Entry: M=1 (8-bit A), X=0 (16-bit), DP any (no DP access), DB=$7E
; Exit:  M, X, DP, DB unchanged; A clobbered; X/Y unchanged
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
; BattleSys_UpkeepTwoFrames ($C1106E–$C110E2, 117 bytes)
; ==================================================================
; Service 3 of the same-bank $C10045 service dispatcher (reached only
; by JSR $0003/$0045 inside bank $C1; returns RTS; dispatch table at
; $C10051, entry 3 = $106E; searched: no JSR, JMP or JSL reaches $106E
; directly). Runs the battle's per-frame upkeep across two waits:
;   1. Unless !Battle_UnkA10E is set: clear !Battle_UnkA0FD, and if
;      !Battle_Unk99CF or !Battle_Unk99D0 is set while !Battle_Unk2989
;      bit 7 is set, clear both and, once per L+R hold (!Battle_Unk99D1
;      latch, cleared again by the bank-$CF frame routine at $CF:E732
;      whenever L and R are not both held and $A013 is 0), send info
;      message $FF then $75.
;   2. Wait (BattleSys_PumpFrames), service tick, PC upkeep
;      (Battle_TickPcSlots, with !Battle_UnkA4 saved in !Battle_Unk993B
;      and taken back from it if that changed), the slot timers and the
;      battler coordinate cache.
;   3. Wait and tick again with !Battle_UnkE5 cleared, then set; rebuild
;      the menu if !BattleMenu_Dirty (the same chain as
;      BattleMenu_RefreshIfDirtyL, plus clearing !Battle_PadEdgeButtons);
;      then the slot timers and the coordinate cache once more.
; What the two message ids show, and what the Unk flags stand for, has
; not been traced; the "wait" reading of BattleSys_PumpFrames is inferred
; from its loop (it spins on JSL $CD0036 until $9E is cleared).
; Entry: M=1, X=0, DP=0, DB=$7E (through the dispatcher at $C10045,
;        which saves A, X and Y around the call)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y and the callees' DP scratch
;        clobbered, plus whatever the unmatched callees change
; Callees: BattleMsg_ShowFromTableCC3A09Vec, BattleSys_PumpFrames,
;          BattleSys_FrameTickVec, Battle_TickPcSlots,
;          Battle_TickEnemyMovers, Battle_CacheBattlerCoordsAll,
;          BattleMenu_DequeueReadyBattler, BattleMenu_UpdateWindows,
;          BattleMenu_ProcessInput, BattleMenu_UpdateCursorOverlay
org $C1106E
BattleSys_UpkeepTwoFrames:
    LDA.w !Battle_UnkA10E
    BNE .upkeep
    STZ.w !Battle_UnkA0FD
    LDA.w !Battle_Unk99CF
    ORA.w !Battle_Unk99D0
    BEQ .upkeep
    LDA.w !Battle_Unk2989
    BPL .upkeep
    STZ.w !Battle_Unk99CF
    STZ.w !Battle_Unk99D0
    LDA.w !Battle_Unk99D1
    BNE .upkeep                     ; message already shown
    INC.w !Battle_Unk99D1
    LDA.b #!BattleMsg_InfoNone
    JSL BattleMsg_ShowFromTableCC3A09Vec
    LDA.b #!BattleMsg_Info75
    JSL BattleMsg_ShowFromTableCC3A09Vec
.upkeep:
    JSR BattleSys_PumpFrames
    JSL BattleSys_FrameTickVec
    LDA.b !Battle_UnkA4
    STA.w !Battle_Unk993B
    JSR Battle_TickPcSlots
    LDA.w !Battle_Unk993B
    CMP.b !Battle_UnkA4
    BEQ .a4_kept
    STA.b !Battle_UnkA4             ; take the copy back
.a4_kept:
    JSR Battle_TickEnemyMovers
    JSR Battle_CacheBattlerCoordsAll
    STZ.b !Battle_UnkE5
    JSR BattleSys_PumpFrames
    JSL BattleSys_FrameTickVec
    INC.b !Battle_UnkE5
    LDA.w !BattleMenu_Dirty
    BEQ .menu_clean
    STZ.w !BattleMenu_Dirty
    JSR BattleMenu_DequeueReadyBattler
    JSR BattleMenu_UpdateWindows
    JSR BattleMenu_ProcessInput
    JSR BattleMenu_UpdateCursorOverlay
    STZ.b !Battle_PadEdgeButtons
.menu_clean:
    JSR Battle_TickEnemyMovers
    JSR Battle_CacheBattlerCoordsAll
    RTS

; ==================================================================
; BattleMenu_LoadCommandWindowMap ($C11C3A–$C11C49, 16 bytes)
; ==================================================================
; Copies the $180-byte command window map (!BattleRom_CommandWindowMap,
; bank $D1) into !BattleMenu_WindowMap. Used whenever the shown PC changes
; or a submenu closes.
; Callers: BattleMenu_UpdateMainWindow (twice), BattleMenu_BuildTargetList,
;        BattleMenu_RemoveBattlerFromReady, BattleMenu_TechListCancel,
;        BattleMenu_ItemListCancel
; Entry: M=1, X=0 (16-bit), DP=0 (TDC / TAX zeroes X only because D=0),
;        DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; X=$0180; A = last byte copied; Y and DP
;        unchanged
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
; Battler frame decoder ($C1:1C4A–$C1:1F78)
; ==================================================================
!BattleFrame_ColsLeft = !BattleTmp_80     ; 1 B: tiles left in this row; later 2 B: count of extra bytes
!BattleFrame_Width = !BattleTmp_81        ; 1 B: tiles per row (reloads ColsLeft)
!BattleFrame_RowPtr = !BattleTmp_82       ; 3 B: long pointer to the next BattleRom_FrameLayout.RowOffset word;
                                          ; later 2 B: the slot's !Battler_FrameExtra offset
!BattleFrame_RowsLeft = !BattleTmp_85     ; 1 B: rows left
!BattleFrame_Slot = !BattleTmp_88         ; 2 B: battler slot, doubled once the layout is read
!BattleFrame_Entry = !BattleTmp_8C        ; 2 B: current tilemap entry; on the mirrored path, the tile's source address
!BattleFrame_DestPtr = !BattleTmp_AD      ; 3 B: long pointer to the destination tile (mirrored path; bank $7E in +2)
!BattleFrame_MapPtr = !BattleTmp_BA       ; 3 B: long pointer into the frame record (tilemap, then the extra bytes)
!BattleFrame_GfxBase = !BattleTmp_BD      ; 2 B: address of tile 0 in the battler's tile bank (DB while copying)

; $C1:1C4A — Battle_DrawBattlerFrame (11 bytes, $1C4A–$1C54)
; Decodes frame !Battle_FrameId of battler !Battle_FrameSlot into the
; battler's tile buffer in bank $7E, unless the battler uses frame layout 3
; (!Battle_FrameLayoutStrip), which this entry leaves alone. The work is
; done by Battle_DrawBattlerFrameAnyLayout, which it falls into.
; Names are inferred from what the code does (a per-battler frame number,
; a cache of the last one shown, tiles copied by number with a mirror
; bit); what the buffer is shown as has not been traced.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_FrameSlot and !Battle_FrameId set
; Exit:  see Battle_DrawBattlerFrameAnyLayout (layout 3: M=1, X=0, DP=0,
;        DB=$7E, X = slot, A = 3, nothing written)
; Callers: JSR from Battle_TickPcSlots, Battle_TickEnemyGroup,
;          Battle_PoseStep, $C1:416A, $C1:418B, $C1:41AC and $C1:4307
;          (searched: every JSR $1C4A in bank $C1; no JMP or JSL
;          reaches it)
org $C11C4A
Battle_DrawBattlerFrame:
    LDX.w !Battle_FrameSlot
    LDA.w !Battler_FrameLayout,X
    CMP.b #!Battle_FrameLayoutStrip
    BNE Battle_DrawBattlerFrameAnyLayout
    RTS

; $C1:1C55 — Battle_DrawBattlerFrameAnyLayout (804 bytes, $1C55–$1F78)
; Decodes one animation frame of a battler into bank $7E tiles:
;   1. Clear the slot's !Battler_FrameDeferred; return at once if
;      !Battle_FrameId is already the slot's !Battler_FrameShown.
;   2. Frame record = !Battler_FramesPtr + FrameId * BattleRom_FrameBytes
;      (by layout). It holds Width * Height tilemap words, then
;      Width * Height / 2 signed bytes.
;   3. For each row (BattleRom_FrameLayout: Width, Height, and a buffer
;      offset per row, added to the slot's BattleRom_FrameDestBase) and
;      each cell: entry & $07FF = 0 writes 32 zero bytes; otherwise tile
;      (entry & $07FF) is copied from !Battler_TileGfxPtr (32 bytes per
;      tile), bit-reversing each byte through BitReverseTable ($C0:FD00) when
;      bit 14 (!Battle_FrameHFlip) is set, which mirrors a 4bpp tile left
;      to right. Bit 15 (a vertical flip in SNES maps) is not tested.
;   4. Copy the signed bytes, widened to words, into the slot's
;      !Battler_FrameExtra block, and count the decode in
;      !Battle_FramesDecoded.
; Layout 2 (8 x 6) is read with record 5's row order for every slot but
; 3; why slot 3 differs is not known.
; The cell copies are unrolled 16 (words) and 32 (mirrored bytes) times in
; the original, and kept that way.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_FrameSlot and !Battle_FrameId set
;        (falls in from Battle_DrawBattlerFrame or is called directly)
; Exit:  M=1, X=0, DP=0, DB=$7E (pushed and restored around the copy, which
;        runs with DB = the tile bank); A, X, Y clobbered; DP $77-$78,
;        $80-$85, $88-$89, $8C-$8D, $A5, $A7-$B0 (partly the multiply
;        helpers') and $BA-$BE written.
;        An unchanged frame returns early with X = slot and A = FrameId.
; Callers: JSR from Battle_DrawAllBattlerFrames (all 11 slots), and the fall-in
;          from Battle_DrawBattlerFrame (searched: no other JSR, JMP or JSL
;          reaches $1C55)
; Callees: Battle_Mul8x16, Battle_Mul8
Battle_DrawBattlerFrameAnyLayout:
    LDX.w !Battle_FrameSlot
    STX.b !BattleFrame_Slot
    STZ.w !Battler_FrameDeferred,X
    LDA.w !Battle_FrameId
    CMP.w !Battler_FrameShown,X
    BNE .new_frame
    RTS                             ; already showing this frame
.new_frame:
    STA.w !Battler_FrameShown,X

    ; Frame record offset = FrameId * bytes per record of this layout.
    LDA.w !Battler_FrameLayout,X
    ASL
    TAX
    LDA.l !BattleRom_FrameBytes,X
    STA.b !Battle_MulFactor16
    LDA.l !BattleRom_FrameBytes+1,X
    STA.b !Battle_MulFactor16+1
    LDA.w !Battle_FrameId
    STA.b !Battle_MulFactor8
    JSR Battle_Mul8x16
    LDX.b !BattleFrame_Slot
    LDA.l !BattleRom_SlotTimes3,X
    TAX
    REP #$21                        ; A 16-bit, carry clear for the ADC
    LDA.w !Battler_FramesPtr,X
    ADC.b !Battle_MulProduct
    STA.b !BattleFrame_MapPtr
    LDA.w !Battler_TileGfxPtr,X
    STA.b !BattleFrame_GfxBase
    TDC
    SEP #$20
    PHB                             ; keep the caller's DB ($7E)
    LDA.w !Battler_FramesPtr+2,X
    STA.b !BattleFrame_MapPtr+2
    LDA.w !Battler_TileGfxPtr+2,X
    PHA                             ; the tile bank becomes DB below

    ; Layout record = BattleRom_FrameLayout + layout * 14.
    LDX.b !BattleFrame_Slot
    LDA.w !Battler_FrameLayout,X
    STA.b !Battle_Mul8A
    CMP.b #!Battle_FrameLayoutTall
    BNE .layout_ok
    LDA.w !Battle_FrameSlot
    CMP.b #!Battle_FirstEnemySlot
    BEQ .layout_ok                  ; slot 3 keeps layout 2's row order
    LDA.b #!Battle_FrameLayoutTallAlt
    STA.b !Battle_Mul8A
.layout_ok:
    LDA.b #!Battle_FrameLayoutBytes
    STA.b !Battle_Mul8B
    JSR Battle_Mul8
    LDX.b !Battle_Mul8Product
    LDA.l BattleRom_FrameLayout.Width,X
    STA.b !BattleFrame_ColsLeft
    STA.b !BattleFrame_Width
    LDA.l BattleRom_FrameLayout.Height,X
    STA.b !BattleFrame_RowsLeft
    REP #$21
    TXA
    ADC.w #BattleRom_FrameLayout&$FFFF
    STA.b !BattleFrame_RowPtr
    ASL.b !BattleFrame_Slot         ; slot * 2 from here on
    TDC
    SEP #$20
    LDA.b #BattleRom_FrameLayout>>16
    STA.b !BattleFrame_RowPtr+2
    LDA.b #!Battle_WramBank
    STA.b !BattleFrame_DestPtr+2
    PLB                             ; DB = tile bank

.row:
    REP #$21
    LDX.b !BattleFrame_Slot
    LDA.l !BattleRom_FrameDestBase,X
    ADC.b [!BattleFrame_RowPtr]     ; + this row's offset
    TAX                             ; X = destination of the row's first tile
    INC.b !BattleFrame_RowPtr
    INC.b !BattleFrame_RowPtr
.cell:
    REP #$20
    LDA.b [!BattleFrame_MapPtr]
    STA.b !BattleFrame_Entry
    AND.w #!Battle_FrameTileMask
    BNE .tile

    ; Tile 0: a blank cell, 32 zero bytes (A = 0 here).
    STA.l !Battle_WramLong,X
    STA.l !Battle_WramLong+2,X
    STA.l !Battle_WramLong+4,X
    STA.l !Battle_WramLong+6,X
    STA.l !Battle_WramLong+8,X
    STA.l !Battle_WramLong+10,X
    STA.l !Battle_WramLong+12,X
    STA.l !Battle_WramLong+14,X
    STA.l !Battle_WramLong+16,X
    STA.l !Battle_WramLong+18,X
    STA.l !Battle_WramLong+20,X
    STA.l !Battle_WramLong+22,X
    STA.l !Battle_WramLong+24,X
    STA.l !Battle_WramLong+26,X
    STA.l !Battle_WramLong+28,X
    STA.l !Battle_WramLong+30,X
    TXA
    CLC
    ADC.w #!Battle_TileBytes
    TAX
    JMP .next_cell

.tile:
    ASL                             ; tile number * 32
    ASL
    ASL
    ASL
    ASL
    CLC
    ADC.b !BattleFrame_GfxBase
    TAY                             ; Y = source tile in bank DB
    LDA.b !BattleFrame_Entry
    AND.w #!Battle_FrameHFlip
    BNE .mirrored
    LDA.w !Battle_DataBankAbs,Y
    STA.l !Battle_WramLong,X
    LDA.w !Battle_DataBankAbs+2,Y
    STA.l !Battle_WramLong+2,X
    LDA.w !Battle_DataBankAbs+4,Y
    STA.l !Battle_WramLong+4,X
    LDA.w !Battle_DataBankAbs+6,Y
    STA.l !Battle_WramLong+6,X
    LDA.w !Battle_DataBankAbs+8,Y
    STA.l !Battle_WramLong+8,X
    LDA.w !Battle_DataBankAbs+10,Y
    STA.l !Battle_WramLong+10,X
    LDA.w !Battle_DataBankAbs+12,Y
    STA.l !Battle_WramLong+12,X
    LDA.w !Battle_DataBankAbs+14,Y
    STA.l !Battle_WramLong+14,X
    LDA.w !Battle_DataBankAbs+16,Y
    STA.l !Battle_WramLong+16,X
    LDA.w !Battle_DataBankAbs+18,Y
    STA.l !Battle_WramLong+18,X
    LDA.w !Battle_DataBankAbs+20,Y
    STA.l !Battle_WramLong+20,X
    LDA.w !Battle_DataBankAbs+22,Y
    STA.l !Battle_WramLong+22,X
    LDA.w !Battle_DataBankAbs+24,Y
    STA.l !Battle_WramLong+24,X
    LDA.w !Battle_DataBankAbs+26,Y
    STA.l !Battle_WramLong+26,X
    LDA.w !Battle_DataBankAbs+28,Y
    STA.l !Battle_WramLong+28,X
    LDA.w !Battle_DataBankAbs+30,Y
    STA.l !Battle_WramLong+30,X
    TXA
    CLC
    ADC.w #!Battle_TileBytes
    TAX
    JMP .next_cell

.mirrored:
    ; Same 32 bytes, each passed through the bit-reverse table. Both
    ; pointers go to DP so Y can be a byte index with 8-bit X/Y.
    STY.b !BattleFrame_Entry        ; now the source address
    STX.b !BattleFrame_DestPtr
    SEP #$30
    LDY.b #0
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    LDA.b (!BattleFrame_Entry),Y
    TAX
    LDA.l BitReverseTable,X
    STA.b [!BattleFrame_DestPtr],Y
    INY
    REP #$31                        ; A, X/Y 16-bit, carry clear
    LDA.b !BattleFrame_DestPtr
    ADC.w #!Battle_TileBytes
    TAX

.next_cell:
    INC.b !BattleFrame_MapPtr
    INC.b !BattleFrame_MapPtr
    TDC
    SEP #$20
    DEC.b !BattleFrame_ColsLeft
    BEQ .row_done
    JMP .cell
.row_done:
    DEC.b !BattleFrame_RowsLeft
    BEQ .tiles_done
    LDA.b !BattleFrame_Width
    STA.b !BattleFrame_ColsLeft
    JMP .row

.tiles_done:
    PLB                             ; DB = $7E again
    ; MapPtr now points past the tilemap: copy the signed bytes that
    ; follow into the slot's !Battler_FrameExtra words.
    LDA.w !Battle_FrameSlot
    TAX
    LDA.w !Battler_FrameLayout,X
    TAX
    LDA.l !BattleRom_FrameExtraCount,X
    TAX
    STX.b !BattleFrame_ColsLeft     ; 16-bit count
    LDX.b !BattleFrame_Slot
    LDA.l !BattleRom_SlotTimes16,X
    STA.b !BattleFrame_RowPtr
    LDA.l !BattleRom_SlotTimes16+1,X
    STA.b !BattleFrame_RowPtr+1
    LDX.b !BattleFrame_RowPtr
    LDY.w #0
.extra:
    LDA.b [!BattleFrame_MapPtr],Y
    STA.w !Battler_FrameExtra,X
    BMI .negative
    TDC
    BRA .store_high
.negative:
    LDA.b #!Battle_SignExtendNeg
.store_high:
    STA.w !Battler_FrameExtra+1,X
    INX
    INX
    INY
    CPY.b !BattleFrame_ColsLeft
    BNE .extra
    INC.w !Battle_FramesDecoded
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
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y and the callees' DP scratch
;        clobbered (see their headers; the JSL targets they reach are not
;        matched yet)
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
; plain RTS. Called once per frame from the battle-phase state machine.
; Callers (7 JSR sites): unmatched code at $C1:40A3, $C1:40B6, $C1:40E4,
;   $C1:485E, $C1:4867, $C1:4890, $C1:4946.
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y and the callees' DP scratch
;        clobbered, plus whatever BattleSys_FrameTickVec (not matched yet)
;        changes
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
; BattleMenu_ProcessInput while no target selection runs, and from
; BattleMenu_UpdateCursorOverlay (.tech_single_cursor, JSR at $C1:18AA).
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; X=$0010; A/Y clobbered; no DP written
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
; Battle command-window input handler. Its three callers (JSR from
; BattleMenu_RefreshIfDirtyL, BattleMenu_RefreshIfDirtyAndTick and
; BattleSys_UpkeepTwoFrames at $C1:10D4) each call it only on frames
; where !BattleMenu_Dirty is set (they clear the flag and run the menu
; chain). Reads the pad-edge bytes (!Battle_PadEdgeButtons /
; !Battle_PadEdgeDpad, pressed this frame) and dispatches:
;   - no PC shown (!BattleMenu_ActivePc < 0) → Battle_ClearPadEdges;
;     target selection running → BattleMenu_TargetSelectInput
;   - !BattleMenu_Submenu 1 / 2 → tech / item list input (with
;     !Battle_MenuTimeHold = !Battle_CfgBattleMode)
;   - main menu: !BattleMenu_UnkA862, or the alt-confirm button with
;     !BattleMenu_CfgCursorMemory on (row forced to 0, !BattleMenu_KeepRow
;     set), go straight to ConfirmCommand; otherwise Left/Right cycle the
;     PC, Up/Down move the cursor, confirm confirms
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0 (LDA.b pad edges, TDC as
;        zero), DB=$7E
; Exit:  tail-jumps to one of several handlers, does not fall through;
;        they all return M=1, X=0, DP=0, DB=$7E with A, X, Y clobbered
;        (DP scratch and pad edges as in each handler's header), plus
;        whatever Battle_MergePendingEntries1580 (not matched yet) changes
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
; Callers (JMP): BattleMenu_ProcessInput ($C1:11AE).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X,
;        Y clobbered; pad edges ($EE/$EF) cleared
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
; Callers (JMP): BattleMenu_ProcessInput ($C1:11CF).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X,
;        Y clobbered; pad edges ($EE/$EF) cleared
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
; Callers (JMP): BattleMenu_ProcessInput ($C1:11BA).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X
;        clobbered; pad edges ($EE/$EF) cleared
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
; Callers (JMP): BattleMenu_ProcessInput ($C1:11C6).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X
;        clobbered; pad edges ($EE/$EF) cleared
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
; Callers (25 JMP sites): BattleMenu_ProcessInput ($C1:115C, $C1:11DE),
;   BattleMenu_CycleActivePcPrev ($C1:1215), BattleMenu_CycleActivePcNext
;   ($C1:124D), BattleMenu_CursorUp ($C1:1261), BattleMenu_CursorDown
;   ($C1:1278), BattleMenu_ChooseAttack ($C1:12B9), BattleMenu_OpenTechList
;   ($C1:12EA), BattleMenu_OpenItemList ($C1:131D), BattleMenu_TechListInput
;   ($C1:1366), BattleMenu_TechConfirm ($C1:138C), BattleMenu_TechListCancel
;   ($C1:13AA), BattleMenu_TechListPrev ($C1:13F1), BattleMenu_TechListNext
;   ($C1:143A), BattleMenu_ItemListInput ($C1:1495), BattleMenu_ItemConfirm
;   ($C1:14D8), BattleMenu_ItemListCancel ($C1:14E9),
;   BattleMenu_ItemCursorUp ($C1:14FF), BattleMenu_ItemCursorDown
;   ($C1:1519), BattleMenu_ItemListPageDown ($C1:1534),
;   BattleMenu_ItemListPageUp ($C1:1548), BattleMenu_ItemListRefresh
;   ($C1:155E), BattleMenu_TargetSelectInput ($C1:1617),
;   BattleMenu_CommitAction ($C1:174B) and BattleMenu_TargetNext ($C1:1783).
; Entry: M=1, X either width, DP=0 (STZ.b $EE/$EF), DB any
; Exit:  M, X, DP, DB unchanged; A/X/Y unchanged;
;        !Battle_PadEdgeButtons = !Battle_PadEdgeDpad = 0
; No JSR/JSL calls.
org $C1179C
Battle_ClearPadEdges:
    STZ.b !Battle_PadEdgeButtons
    STZ.b !Battle_PadEdgeDpad
    RTS

; ==================================================================
; BattleMenu_EnqueueReadyBattler ($C11B19–$C11B54, 60 bytes)
; ==================================================================
; Service 1 of the $C10045 service dispatcher (dispatch table at
; $C10051: service 0 -> $0023, 1 -> here, 2 -> RemoveBattlerFromReady).
; The dispatcher is a same-bank API: it is reached only by JSR $0003
; (the vector JMP $0045) or JSR $0045 from bank $C1, never by JSL/JML,
; and returns with RTS.
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
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0 (LDA.b !Battle_ArgSlot), DB=$7E;
;        !Battle_ArgSlot = battler slot
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X clobbered, plus whatever
;        Audio_ProcessEntry (not matched yet) changes
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
; Callers (29 JSR sites): BattleMenu_ProcessInput ($C1:11B7, $C1:11C3,
;   $C1:11D8), BattleMenu_CycleActivePcPrev ($C1:11E7),
;   BattleMenu_CycleActivePcNext ($C1:121E), BattleMenu_TechListInput
;   (4 sites), BattleMenu_ItemListInput (6 sites),
;   BattleMenu_TargetSelectInput (4 sites), BattleTgt_EnemyLineFromCaster
;   ($C1:217A, $C1:2188), BattleTgt_EnemyLineFromChar3 ($C1:21C0, $C1:21CE),
;   BattleTgt_EnemyLineFromCaster2 ($C1:2214, $C1:2222),
;   BattleTgt_EnemyRadius ($C1:226B, $C1:2279) and BattleTgt_EnemyRow
;   ($C1:2301, $C1:230F).
; Entry: M=1, X=0, DP=0, DB=$7E (as at every caller; the routine itself
;        only needs M=1 and DB=$7E for the .w stores)
; Exit:  M=1, X=0, DP=0, DB=$7E; A clobbered, plus whatever
;        Audio_ProcessEntry (not matched yet) changes
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
; Callers (JMP): BattleMenu_ProcessInput ($C1:11A5, $C1:11DB).
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0, DB=$7E
; Exit:  tail-jumps to one of three row handlers, does not fall through;
;        each ends in Battle_ClearPadEdges with M=1, X=0, DP=0, DB=$7E;
;        A, X, Y clobbered, plus the chosen handler's DP scratch and
;        callee effects (see BattleMenu_ChooseAttack / OpenTechList /
;        OpenItemList) and whatever BattleFx_SetPtrA2FromTable (not
;        matched yet) changes
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
; redraw, sets !BattleTgt_Mode = attack, !BattleMenu_CmdMenu = 0, builds
; the target list, sets !BattleMenu_TargetMoved (so UpdateCursorOverlay
; places the target cursor) and enters target selection.
; !BattleUI_PanelRedraw is incremented twice; the second INC changes
; nothing, since every access to it in banks $C0-$CF is an INC, a
; zero/non-zero test or the STZ that clears it (ROM scan of $A43F).
; Callers (JMP): BattleMenu_ConfirmCommand ($C1:1290).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X,
;        Y clobbered, plus BuildTargetList's (see its header) and
;        whatever BattleMsg_ShowMsg0BIfKeyChangedVec (not matched yet) changes
; Callees: BattleMsg_ShowMsg0BIfKeyChangedVec,
;          BattleMenu_BuildTargetList, Battle_ClearPadEdges
org $C1129C
BattleMenu_ChooseAttack:
    LDA.b #!BattleMsg_ArgNone
    JSL BattleMsg_ShowMsg0BIfKeyChangedVec
    INC.w !BattleUI_PanelRedraw
    INC.w !BattleUI_PanelRedraw     ; (no effect: only tested for non-zero)
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
; Callers (JMP): BattleMenu_ConfirmCommand ($C1:1296).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X,
;        Y clobbered; DP as in RenderTechListRows and BuildTechAvailFlags
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
; the item box frame (!BattleRom_ItemBoxMap) into !BattleMenu_WindowMap,
; and switches to the item list (!BattleMenu_Submenu = !BattleMenu_CmdMenu = 2).
; Callers (JMP): BattleMenu_ConfirmCommand ($C1:1299).
; Entry: M=1, X=0, DP=0 (STA.b !BattleMenu_ListScroll, TDC as zero), DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X,
;        Y clobbered; DP as in RenderItemListRows, plus whatever
;        Battle_QueueVramUpload_0E80 (not matched yet) changes
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
; The clear loop starts at X = !Battle_NumSlots (11) and runs down to 0,
; so it blanks 12 entries of each list, one past the 11 battler slots.
;
; Then runs the mode's handler: mode & $7F (clamped to $20) indexes
; BattleTgt_ModeTable. If afterwards every one of the first 11
; selection entries is empty, !BattleTgt_Result gets the $FF just read
; (negative = no valid target).
;
; Callers (4 JSR sites): BattleMenu_ChooseAttack ($C1:12B0),
;   BattleMenu_TechConfirm ($C1:1379), BattleMenu_ItemConfirm ($C1:14C5) and
;   BattleMenu_TargetSelectInput ($C1:1561).
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered, plus the DP scratch of
;        the mode handler that ran (the BattleTgt_ routines below: within
;        $80-$95, plus $77/$78, $A5-$AB, $AE and $D3-$E3 for the area modes)
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
; Service 7 of the $C10045 service dispatcher (dispatch table at
; $C10051; reached only by same-bank JSR from bank $C1, see
; BattleMenu_EnqueueReadyBattler). Runs one of the area-target geometry
; routines, selected by !BattleTgt_AreaType (0-6) through the 7-entry
; table just below; out-of-range selectors are ignored. The same geometry routines back the menu's
; area-effect target modes (see BattleTgt_ModeTable), so this is
; presumably how non-menu code (enemy scripts, scripted attacks) asks
; "which battlers does this area hit?".
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleTgt_AreaType,
;        !BattleTgt_AreaSide..AreaVariant
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y and the area routine's DP scratch
;        clobbered (see its header)
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
;
; CPU state for every handler below (and the BattleTgt_ helpers): Entry
; M=1, X=0, DP=0, DB=$7E (they use .b DP scratch and TDC as zero);
; they return the same, with A, X, Y clobbered. Each header names the DP
; it writes, including its callees'.
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
; BattleTgt_SingleAlly ($C1203A–$C12044, 11 bytes; falls into
; BattleTgt_CollectValidTargets, $C12045–$C12099, 85 bytes)
; ==================================================================
; Default mode: one PC (slots 0-2), cursor may cycle. Falls into
; BattleTgt_CollectValidTargets, the shared list builder that the
; other list modes enter with their own slot range (!BattleTgt_ScanEnd
; = end exclusive, X = start) and flags: BRA from BattleTgt_AllAllies and
; BattleTgt_SingleEnemy, JMP from BattleTgt_AllEnemies ($C1:20C3) and
; BattleTgt_Everyone ($C1:20D3).
;
; CollectValidTargets keeps battler X only if it is present
; (!Battler_Present), !Battler_Unk9FF7 bit 7 is clear, it is not
; !Battler_Untargetable, and — if !Battler_KoFlag is set — only when the
; mode is $04. The requesting battler (!BattleTgt_Caster) goes to the
; front of !BattleTgt_Candidates if it passes those tests and lies in
; the scanned range; everyone else is appended from entry 1.
; CompactCandidates then closes the hole if the front stayed empty.
; Finally the cursor entry is copied to !BattleTgt_Selected, or the
; whole list when !BattleTgt_TargetAll says "target all".
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E; CollectValidTargets also
;        takes X = first slot and !BattleTgt_ScanEnd
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $80/$81 written
;        (ScanEnd)
; Callees: BattleTgt_CompactCandidates
!BattleTgt_ScanEnd = !BattleTmp_80       ; 2 B in: slot after the last one CollectValidTargets scans
org $C1203A
BattleTgt_SingleAlly:
    LDX.w #!Battle_NumPcSlots
    STX.b !BattleTgt_ScanEnd        ; PCs 0-2
    LDX #$0000                      ; first slot
    INC.w !BattleTgt_CanCycle
BattleTgt_CollectValidTargets:      ; header: see BattleTgt_SingleAlly
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
; Entry/Exit: M=1, X=0, DP=0, DB=$7E, as BattleTgt_SingleAlly (DP $80/$81)
BattleTgt_AllAllies:
    LDX.w #!Battle_NumPcSlots
    STX.b !BattleTgt_ScanEnd
    LDX #$0000
    LDA.b #!BattleTgt_AllFlag
    STA.w !BattleTgt_TargetAll      ; target all
    BRA BattleTgt_CollectValidTargets

; BattleTgt_SingleEnemy ($C120A9–$C120B5, 13 bytes): one enemy (3-10),
; cursor may cycle. Also called as a list builder by the area modes.
; Callers (5 JSR sites): BattleTgt_EnemyLineFromCaster ($C1:2169),
;   BattleTgt_EnemyLineFromChar3 ($C1:21AF), BattleTgt_EnemyLineFromCaster2
;   ($C1:2203), BattleTgt_EnemyRadius ($C1:225F) and BattleTgt_EnemyRow
;   ($C1:22F5).
; Entry/Exit: M=1, X=0, DP=0, DB=$7E, as BattleTgt_SingleAlly (DP $80/$81)
BattleTgt_SingleEnemy:
    LDX.w #!Battle_NumSlots
    STX.b !BattleTgt_ScanEnd
    LDX.w #!Battle_FirstEnemySlot
    INC.w !BattleTgt_CanCycle
    BRA BattleTgt_CollectValidTargets

; BattleTgt_AllEnemies ($C120B6–$C120C5, 16 bytes)
; Entry/Exit: M=1, X=0, DP=0, DB=$7E, as BattleTgt_SingleAlly (DP $80/$81)
BattleTgt_AllEnemies:
    LDX.w #!Battle_NumSlots
    STX.b !BattleTgt_ScanEnd
    LDX.w #!Battle_FirstEnemySlot
    LDA.b #!BattleTgt_AllFlag
    STA.w !BattleTgt_TargetAll
    JMP BattleTgt_CollectValidTargets

; BattleTgt_Everyone ($C120C6–$C120D5, 16 bytes): all battlers 0-10
; Entry/Exit: M=1, X=0, DP=0, DB=$7E, as BattleTgt_SingleAlly (DP $80/$81)
BattleTgt_Everyone:
    LDX.w #!Battle_NumSlots
    STX.b !BattleTgt_ScanEnd
    LDX #$0000
    LDA.b #!BattleTgt_AllFlag
    STA.w !BattleTgt_TargetAll
    JMP BattleTgt_CollectValidTargets

; BattleTgt_Self ($C120D6–$C120DF, 10 bytes): the shown PC only
; Entry/Exit: M=1, X either width, DP any, DB=$7E; only A changes, no DP
; written
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
; Entry/Exit: M=1, X=0, DP=0 (TDC as zero), DB=$7E; A, X clobbered; no DP
; written
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
; BattleTgt_PcByCharId5 ($C12136–$C12139, 4 bytes; falls into
; BattleTgt_FindPcByCharId, $C1213A–$C12162)
; ==================================================================
; Targets the one party member whose !Pc_CharId equals
; !BattleTgt_WantedChar (5 for this entry, 4 via BattleTgt_PcByCharId4).
; In bank $C1, !Pc_CharId behaves like the party's character-id list; if
; so these are "target Ayla"/"target Frog" modes. Which techs use target
; modes 5 and 6 is not established. The routine names keep the numeric
; ids because the character constants (!Pc_CharAyla etc.) are inferred.
; Entry: M=1, X=0, DP=0, DB=$7E (FindPcByCharId also takes
;        !BattleTgt_WantedChar in $80)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X clobbered; DP $80 written
!BattleTgt_WantedChar = !BattleTmp_80    ; 1 B in: character id FindPcByCharId looks for
BattleTgt_PcByCharId5:
    LDA.b #!Pc_CharAyla
    STA.b !BattleTgt_WantedChar
BattleTgt_FindPcByCharId:           ; header: see BattleTgt_PcByCharId5
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

; BattleTgt_PcByCharId4 ($C12163–$C12168, 6 bytes); state as PcByCharId5
; header: see BattleTgt_PcByCharId5
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
; (BattleTgt_SelectAllCandidates). The exception: EnemyLineFromChar3,
; Char3Radius and Char6Radius return early, before the area step, when
; no PC has the character id they look for (see their headers):
;   !BattleTgt_AreaCentre = source/centre battler, AreaAim = aimed-at
;   battler, AreaSize = shape size, AreaVariant = variant flag,
;   AreaSide = 0 (scan the enemies)
; The enemy-anchored ones build the enemy list first and let the pad
; move the aim: D-pad up/right or down/left each play Battle_PlaySfx0 and
; step the cursor. Note the three "line" modes step forward for both pad
; groups; the radius/row modes step backward for the second group.
; State for all of them: Entry/Exit M=1, X=0, DP=0, DB=$7E; A, X, Y
; clobbered; they read the pad edges with LDA.b. DP written: the
; enemy-anchored ones $80/$81 (SingleEnemy) plus the area routine's DP
; (AreaLine, AreaCircle, AreaRow, AreaPartyTriangle: see those headers),
; and whatever Battle_PlaySfx0's Audio_ProcessEntry (not matched yet)
; changes.

; BattleTgt_EnemyLineFromCaster ($C12169–$C121AE, 70 bytes)
; Entry/Exit: M=1, X=0, DP=0, DB=$7E, as in the area-mode notes above
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
; the pad step set up: in !BattleTgt_Selected the enemy that was under
; the cursor before the pad step (CycleNext moves only !BattleTgt_Cursor),
; with !BattleTgt_TargetAll = $80 (the cursor may already have moved and
; played sound 0).
; Entry/Exit: M=1, X=0, DP=0, DB=$7E, as in the area-mode notes above
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
; Entry/Exit: M=1, X=0, DP=0, DB=$7E, as in the area-mode notes above
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
; Entry/Exit: M=1, X=0, DP=0, DB=$7E, as in the area-mode notes above
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
; Entry/Exit: M=1, X=0, DP=0, DB=$7E, as in the area-mode notes above
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
; member id 3; size $19 for mode $14, else $10. If no PC has id 3 it
; returns at once with nothing listed, so BuildTargetList finds every
; selection entry empty and sets !BattleTgt_Result = $FF (no target).
; Entry/Exit: M=1, X=0, DP=0, DB=$7E, as in the area-mode notes above
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
; party member id 6. If no PC has id 6 it returns at once with nothing
; listed (BuildTargetList then sets !BattleTgt_Result = $FF).
; Entry/Exit: M=1, X=0, DP=0, DB=$7E, as in the area-mode notes above
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
; Entry/Exit: M=1, X=0, DP=0, DB=$7E, as in the area-mode notes above
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
; Entry/Exit: M=1, X=0, DP=0, DB=$7E, as in the area-mode notes above
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
; Callers (JSR): BattleTgt_EnemyRow ($C1:2322).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E; !BattleTgt_AreaSide,
;        !BattleTgt_AreaCentre
; Exit:  M=1, X=0, DP=0, DB=$7E; Candidates[0] = centre, [1..] = hits,
;        rest $FF; A, X, Y clobbered; DP $85, $87-$89 and $8E-$91 written
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
; Callers (JSR): BattleTgt_PartyTriangle ($C1:232C).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; tail-jumps to BattleTgt_CompactCandidates
;        (the scan only appends from entry 1, so the $FF front entry is
;        always closed up); A, X, Y clobbered; DP $80-$8B, $8E-$95 and
;        Battle_CalcAngle's $D3-$E3 written
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
; Callers (JSR): BattleTgt_EnemyLineFromCaster ($C1:21A9),
;   BattleTgt_EnemyLineFromChar3 ($C1:21FD) and
;   BattleTgt_EnemyLineFromCaster2 ($C1:2245).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E; !BattleTgt_AreaSide..
;        AreaVariant as above
; Exit:  M=1, X=0, DP=0, DB=$7E; via BattleTgt_AreaAddAnchor ->
;        CompactCandidates; A, X, Y clobbered; DP $80-$93 (scratch and
;        Anchor), $AE (!Battle_SinScale), Battle_SinLookup's $77/$78 and
;        $A5-$AB, and Battle_CalcAngle's $D3-$E3 written
; Callees: Battle_CalcAngle, Battle_SinLookup, BattleTgt_ClearLists
; Direct-page roles (!BattleTgt_Anchor shared with AreaCircle / AreaAddAnchor):
!BattleTgt_PaX = !BattleTmp_80            ; 1 B: r*sin θ, then corner PA screen x
!BattleTgt_PaY = !BattleTmp_81            ; 1 B: r*sin(θ+$C0), then corner PA screen y
!BattleTgt_PbX = !BattleTmp_82            ; 1 B: r*sin(θ+$80), then corner PB screen x
!BattleTgt_PbY = !BattleTmp_83            ; 1 B: r*sin(θ+$40), then corner PB screen y
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
; BattleTgt_AreaCircle ($C12701–$C127AC, 172 bytes; falls into
; BattleTgt_AreaAddAnchor, $C127AD–$C127C4)
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
; Callers (4 JSR sites): BattleTgt_CasterRadius ($C1:2259),
;   BattleTgt_EnemyRadius ($C1:229E), BattleTgt_Char3Radius ($C1:22CD) and
;   BattleTgt_Char6Radius ($C1:22EF).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E; !BattleTgt_AreaSide,
;        AreaCentre, AreaSize = radius^2
; Exit:  M=1, X=0, DP=0, DB=$7E; falls through into BattleTgt_AreaAddAnchor
;        and BattleTgt_CompactCandidates; A, X, Y clobbered; DP $80-$87
;        and $8E-$93 written
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

; BattleTgt_AreaAddAnchor ($C127AD–$C127C4, 24 bytes)
; Shared tail of the area scans: puts !BattleTgt_Anchor at the front of
; !BattleTgt_Candidates if it belongs to the scanned side (see the
; AreaCircle header), then falls into BattleTgt_CompactCandidates.
; Reached by falling in from BattleTgt_AreaCircle and by JMP from
; BattleTgt_AreaLine.
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleTgt_AreaSide, !BattleTgt_Anchor ($92)
; Exit:  M=1, X=0, DP=0, DB=$7E (through CompactCandidates); A, X
;        clobbered; no DP written
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
; front slot is empty, shift the list left by one. The front stays empty
; when CollectValidTargets' requester was not eligible or lay outside the
; scanned range (every enemy mode, since the requester is a PC), always after
; AreaPartyTriangle (its scan appends from entry 1), and after
; AreaAddAnchor when the anchor is on the other side. The last step reads
; entry 11, one past the 11 used entries (the list has 12 bytes).
; Callers (2 sites: 1 JSR, 1 JMP): BattleTgt_CollectValidTargets ($C1:207B)
;   and BattleTgt_AreaPartyTriangle ($C1:25A0).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A = the front entry if it was filled,
;        else the last byte moved; X unchanged if the front was filled,
;        else !Battle_NumSlots; Y unchanged
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
; Callers (4 JSR sites): BattleTgt_AreaRow ($C1:234F),
;   BattleTgt_AreaPartyTriangle ($C1:24E2), BattleTgt_AreaLine ($C1:2657)
;   and BattleTgt_AreaCircle ($C1:2717).
; Entry/Exit: M=1, X=0 (LDX.w #$0B), DP=0, DB=$7E; A = $FF, X = $FFFF;
; Y and DP unchanged
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
; Callers (9 JMP sites): BattleTgt_EnemyLineFromCaster ($C1:21AC),
;   BattleTgt_EnemyLineFromChar3 ($C1:2200), BattleTgt_EnemyLineFromCaster2
;   ($C1:2248), BattleTgt_CasterRadius ($C1:225C), BattleTgt_EnemyRadius
;   ($C1:22A1), BattleTgt_Char3Radius ($C1:22D0), BattleTgt_Char6Radius
;   ($C1:22F2), BattleTgt_EnemyRow ($C1:2325) and BattleTgt_PartyTriangle
;   ($C1:232F).
; Entry/Exit: M=1, X=0, DP=0, DB=$7E; A, X clobbered; Y and DP unchanged
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
; Callers (8 JSR sites): BattleTgt_EnemyLineFromCaster ($C1:217D, $C1:218B),
;   BattleTgt_EnemyLineFromChar3 ($C1:21C3, $C1:21D1),
;   BattleTgt_EnemyLineFromCaster2 ($C1:2217, $C1:2225),
;   BattleTgt_EnemyRadius ($C1:226E) and BattleTgt_EnemyRow ($C1:2304).
; Entry/Exit: M=1, X=0, DP=0 (TDC as zero), DB=$7E; A, X clobbered; Y and
; DP unchanged
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
; Callers (JSR): BattleTgt_EnemyRadius ($C1:227C) and BattleTgt_EnemyRow
;   ($C1:2312).
; Entry/Exit: M=1, X=0, DP=0, DB=$7E; A, X clobbered; Y and DP unchanged
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
; Callers (JSR): BattleTgt_CycleNext ($C1:27FA) and BattleTgt_CyclePrev
;   ($C1:2814).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; Z as above (callers BEQ on it); A, X
;        clobbered; Y unchanged
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
; Battler boxes and collision tests ($C1:283D–$C1:2985)
; ==================================================================
; Each battler has a probe position (!Battler_ProbeX/Y, a copy of its
; screen position) and a box around it: probe x +/- !Battler_HalfWidth,
; from probe y - !Battler_Height down to probe y (+ 8). Movers write a
; tentative position into the probe, rebuild the box and test it
; against the screen cell map and against the other battlers' boxes
; before committing the move (inferred from the callers at $C1:3851 and
; following, and from BattlePos_PathClear).

; ==================================================================
; Battle_CacheBattlerCoordsAll ($C1283D–$C12859, 29 bytes)
; ==================================================================
; Copies every present battler's screen position into its probe
; position and rebuilds its box.
; Callers (JSR; scanned for JSR/JSL/JML/JMP/BRL, hits inside other
; instructions discarded): BattleSys_UpkeepTwoFrames (twice), the
; unmatched service 0 at $C1:002A and $C1:40C8.
; Entry: M=1, X=0 (16-bit slot counter), DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; X = 11; A clobbered; Y unchanged
; Callee: Battle_CalcBattlerBox
org $C1283D
Battle_CacheBattlerCoordsAll:
    TDC
    TAX                             ; slot 0
.loop:
    LDA.w !Battler_Present,X
    BEQ .next
    LDA.w !Battler_ScreenX,X
    STA.w !Battler_ProbeX,X
    LDA.w !Battler_ScreenY,X
    STA.w !Battler_ProbeY,X
    JSR Battle_CalcBattlerBox
.next:
    INX
    CPX.w #!Battle_NumSlots
    BNE .loop
    RTS

; ==================================================================
; Battle_CalcBattlerBox ($C1285A–$C128AF, 86 bytes)
; ==================================================================
; Builds battler X's box from its probe position:
;   left   = ProbeX - HalfWidth, clamped at 0
;   right  = ProbeX + HalfWidth, clamped at $FF
;   top    = ProbeY - Height, clamped at 0
;   bottom = ProbeY + 8, or ProbeY when !Battle_Unk2989 bit 2 is set
; A clamp is only tried on the half of the screen where it can be
; needed (left/top only when the coordinate is below $80, right only
; when it is $80 or more), which is right as long as the half-width and
; height stay below $80. The bottom edge is never clamped.
; Callers (JSR/JMP, scanned as above): Battle_CacheBattlerCoordsAll,
; BattlePos_PathClear (JSR, and JMP as its tail), and the unmatched
; movers at $C1:386A, $C1:3925, $C1:39D6, $C1:3B79, $C1:3CEB, $C1:3DFA,
; $C1:3EF7, $C1:4001, $C1:7C37.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E; X = battler slot
; Exit:  M=1, X=0, DP=0, DB=$7E; A clobbered; X, Y unchanged
; No calls.
Battle_CalcBattlerBox:
    SEC
    LDA.w !Battler_ProbeX,X
    BMI .left_right_half
    SBC.w !Battler_HalfWidth,X
    BPL .store_left
    TDC                             ; went below 0: clamp
    BRA .store_left
.left_right_half:
    SBC.w !Battler_HalfWidth,X
.store_left:
    STA.w !Battler_BoxLeft,X
    CLC
    LDA.w !Battler_ProbeX,X
    BPL .right_left_half
    ADC.w !Battler_HalfWidth,X
    BMI .store_right
    LDA.b #!Battle_BoxEdgeMax       ; went past $FF: clamp
    BRA .store_right
.right_left_half:
    ADC.w !Battler_HalfWidth,X
.store_right:
    STA.w !Battler_BoxRight,X
    SEC
    LDA.w !Battler_ProbeY,X
    BMI .top_lower_half
    SBC.w !Battler_Height,X
    BPL .store_top
    TDC                             ; went below 0: clamp
    BRA .store_top
.top_lower_half:
    SBC.w !Battler_Height,X
.store_top:
    STA.w !Battler_BoxTop,X
    LDA.w !Battle_Unk2989
    AND.b #!Battle_Unk2989NoBoxPad
    BEQ .padded_bottom
    LDA.w !Battler_ProbeY,X
    STA.w !Battler_BoxBottom,X
    BRA .exit
.padded_bottom:
    CLC
    LDA.w !Battler_ProbeY,X
    ADC.b #!Battle_BoxBottomPad
    STA.w !Battler_BoxBottom,X
.exit:
    RTS

; ==================================================================
; Battle_BoxOverlapsOthers ($C128B0–$C12925, 118 bytes)
; ==================================================================
; Tests the box of battler !Battle_BoxTestSlot against the box of every
; other present battler, skipping those with !Battler_Unk9FF7 or
; !Battler_UnkA5CD bit 7 set. Edges count as touching (the tests are
; <= / >=). Stops at the first overlap.
; Returns A = $80 (N set) when it touches a PC's box, $81 an enemy's,
; 0 when it touches none; Y = the slot touched (11 when none).
; The horizontal test is written out twice, once for each order of the
; two left edges, and each copy repeats the vertical test.
; Callers (JSR/JMP, scanned as above): BattlePos_PathClear and the
; unmatched movers at $C1:3888, $C1:3930, $C1:39E1, $C1:3B8B, $C1:3D09,
; $C1:3E18, $C1:3F15, $C1:400C, plus a JMP (tail call) at $C1:7C3A.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E; !Battle_BoxTestSlot (16-bit,
;        CPY compares both bytes) = the battler to test
; Exit:  M=1, X=0, DP=0, DB=$7E; A and Y as above; X = the tested slot
; No calls.
!Battle_BoxTestSlot = !BattleTmp_80       ; 2 B in: battler whose box is tested (also Battle_BoxHitsBlockedCell)
Battle_BoxOverlapsOthers:
    TDC
    TAY                             ; other battler, from slot 0
    LDX.b !Battle_BoxTestSlot
.loop:
    CPY.b !Battle_BoxTestSlot
    BEQ .next                       ; itself
    LDA.w !Battler_Present,Y
    BEQ .next
    LDA.w !Battler_Unk9FF7,Y
    BMI .next
    LDA.w !Battler_UnkA5CD,Y
    BMI .next
    LDA.w !Battler_BoxLeft,X
    CMP.w !Battler_BoxLeft,Y
    BCC .starts_left_of_it
    CMP.w !Battler_BoxRight,Y
    BEQ .x_overlap
    BCS .next                       ; starts right of its box
.x_overlap:
    LDA.w !Battler_BoxTop,X
    CMP.w !Battler_BoxTop,Y
    BCC .starts_above_it
    CMP.w !Battler_BoxBottom,Y
    BEQ .hit
    BCC .hit
    BCS .next                       ; starts below its box
.starts_above_it:
    LDA.w !Battler_BoxBottom,X
    CMP.w !Battler_BoxTop,Y
    BCC .next                       ; ends above its box
    BCS .hit
.starts_left_of_it:
    LDA.w !Battler_BoxRight,X
    CMP.w !Battler_BoxLeft,Y
    BCC .next                       ; ends left of its box
    LDA.w !Battler_BoxTop,X
    CMP.w !Battler_BoxTop,Y
    BCC .starts_above_it_2
    CMP.w !Battler_BoxBottom,Y
    BEQ .hit
    BCC .hit
    BCS .next
.starts_above_it_2:
    LDA.w !Battler_BoxBottom,X
    CMP.w !Battler_BoxTop,Y
    BCC .next
    BCS .hit
.next:
    INY
    CPY.w #!Battle_NumSlots
    BNE .loop
    TDC                             ; no overlap
    BRA .exit
.hit:
    LDA.b #!Battle_OverlapPc
    CPY.w #!Battle_FirstEnemySlot
    BCC .exit
    INC A                           ; $81: an enemy
.exit:
    RTS

; ==================================================================
; Battle_BoxHitsBlockedCell ($C12926–$C12985, 96 bytes)
; ==================================================================
; Tests whether the box of battler !Battle_BoxTestSlot covers a blocked
; cell of !Battle_CellMap (16x16-pixel cells, 16 per row). Every cell
; from (top/16, left/16) to (bottom/16, right/16) is checked; one with
; bit 6 set blocks, and one with bit 7 set blocks unless
; !Battle_PassCellBit7 is non-zero.
; Returns A = $FF (N set) when blocked, 0 when not.
; The cell index row*16 + col is built in 8-bit A and moved with TAY,
; which also copies B; the index is right only while B is 0 (as after
; the callers' TDC; assumed, not traced for every caller).
; Callers (JSR, scanned as above): BattlePos_PathClear and the unmatched
; movers at $C1:387C, $C1:392B, $C1:39DC, $C1:3B7F, $C1:3CFD, $C1:3E0C,
; $C1:3F09, $C1:4007.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E; !Battle_BoxTestSlot
; Exit:  M=1, X=0, DP=0, DB=$7E; A as above; X = the tested slot; Y =
;        last cell index; DP $82-$86 written
; No calls.
!Battle_CellRow = !BattleTmp_82           ; 1 B: cell row being scanned (from top / 16)
!Battle_CellFirstCol = !BattleTmp_83      ; 1 B: left / 16
!Battle_CellRowEnd = !BattleTmp_84        ; 1 B: bottom / 16 + 1 (exclusive)
!Battle_CellColEnd = !BattleTmp_85        ; 1 B: right / 16 + 1 (exclusive)
!Battle_CellColOffset = !BattleTmp_86     ; 1 B: column, counted from FirstCol
Battle_BoxHitsBlockedCell:
    LDX.b !Battle_BoxTestSlot
    LDA.w !Battler_BoxTop,X
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !Battle_CellRow
    LDA.w !Battler_BoxLeft,X
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !Battle_CellFirstCol
    LDA.w !Battler_BoxBottom,X
    LSR A
    LSR A
    LSR A
    LSR A
    INC A
    STA.b !Battle_CellRowEnd
    LDA.w !Battler_BoxRight,X
    LSR A
    LSR A
    LSR A
    LSR A
    INC A
    STA.b !Battle_CellColEnd
.row:
    STZ.b !Battle_CellColOffset
.cell:
    LDA.b !Battle_CellRow
    ASL A
    ASL A
    ASL A
    ASL A                           ; row * 16
    CLC
    ADC.b !Battle_CellColOffset
    ADC.b !Battle_CellFirstCol
    TAY
    LDA.w !Battle_CellMap,Y
    AND.b #!Battle_CellBlocked
    BNE .blocked
    LDA.w !Battle_PassCellBit7
    BNE .next_cell
    LDA.w !Battle_CellMap,Y
    BMI .blocked                    ; bit 7 blocks too
.next_cell:
    INC.b !Battle_CellColOffset
    CLC
    LDA.b !Battle_CellColOffset
    ADC.b !Battle_CellFirstCol
    CMP.b !Battle_CellColEnd
    BCC .cell
    INC.b !Battle_CellRow
    LDA.b !Battle_CellRow
    CMP.b !Battle_CellRowEnd
    BCC .row
    TDC                             ; nothing blocks
    BRA .exit
.blocked:
    TDC
    DEC A                           ; $FF
.exit:
    RTS

; ==================================================================
; Position queries: service 5 of the $C10045 API ($C1:2986–$C1:2D9E)
; ==================================================================
; BattlePos_Query answers one question about two battlers' positions,
; chosen by !BattlePos_Mode (table at $C1:2D81):
;   0/1  nearest / farthest PC          2/3  nearest / farthest enemy
;   4    within 32 pixels               14   within 48 pixels
;   5    |dy| <= 32                     6/7  subject above / left of other
;   8    path to the other is clear     9-12 subject in the lower /
;   13   distance difference                 upper half, right / left part
; Results: !BattlePos_Result (0 = holds, $FF = not) and, for 0-3 and 13,
; !BattlePos_Found. Callers set !BattlePos_Mode, Subject, Other (and
; Arg) and run service 5 (LDA #5, JSR to $C1:0003 or $C1:0045), e.g. the
; battle-script code at $C1:9270-$C1:A74A tests Result or Found after
; it, and Battle_UpdatePcFacing turns the angle to query 2's Found into
; !Battler_Facing. What the script commands that use the queries
; stand for is not traced.
; The distance checks also have entries of their own, used by movers
; that pass the two slots in X and Y.

; ==================================================================
; BattlePos_Query ($C12986–$C129B1, 44 bytes)
; ==================================================================
; Service 5 of the same-bank $C10045 service dispatcher (reached only
; by JSR $0003/$0045 inside bank $C1; returns RTS; dispatch table at
; $C10051, entry 5 = $2986; searched: no JSR, JMP or JSL reaches $2986
; directly). Copies the screen positions of !BattlePos_Subject and
; !BattlePos_Other into their probe positions, clears
; !BattlePos_Result and runs the query handler for !BattlePos_Mode.
; Entry: M=1, X=0, DP=0, DB=$7E (through the dispatcher, which saves A,
;        X and Y around the call); TAX/TAY of the slots also copy B,
;        assumed 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y and the handler's DP scratch
;        clobbered
; Callees: JSR (BattlePos_ModeTable,X)
org $C12986
BattlePos_Query:
    LDA.w !BattlePos_Subject
    TAX
    LDA.w !BattlePos_Other
    TAY
    LDA.w !Battler_ScreenX,X
    STA.w !Battler_ProbeX,X
    LDA.w !Battler_ScreenY,X
    STA.w !Battler_ProbeY,X
    LDA.w !Battler_ScreenX,Y
    STA.w !Battler_ProbeX,Y
    LDA.w !Battler_ScreenY,Y
    STA.w !Battler_ProbeY,Y
    STZ.w !BattlePos_Result
    LDA.w !BattlePos_Mode
    ASL A
    TAX
    JSR (BattlePos_ModeTable,X)
    RTS

; ==================================================================
; BattlePos_NearestPc / BattlePos_FarthestPc / BattlePos_NearestEnemy /
; BattlePos_FarthestEnemy ($C129B2–$C12AE2, 305 bytes; queries 0-3)
; ==================================================================
; Each scans one side, skipping battlers that are not present, have
; !Battler_Unk9FF7 bit 7 set or are KO'd (BattlerStats.Status bit 7),
; measures the squared distance from the subject with
; BattlePos_WithinDist32 (its Result side effect is left in place: the
; last battler examined decides !BattlePos_Result) and keeps the best
; slot in !BattlePos_Found. Ties go to the later slot (the compares keep
; a new battler when it is at least as near / far). With no candidate,
; Found is left as it was.
; Only NearestEnemy skips the subject itself; the PC scans include it
; when it is a PC (distance 0, so NearestPc then returns the subject).
; Found is stored 16-bit from the 16-bit slot counter, so $9874 gets 0.
; Callers: BattlePos_ModeTable entries 0-3 only (BattlePos_Query).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E; !BattlePos_Subject
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; !BattlePos_Other =
;        last slot examined; DP $77-$78, $80-$87 (and $8A for
;        NearestEnemy) and $AD-$B0 written
; Callee: BattlePos_WithinDist32
!BattlePos_ScanSlot = !BattleTmp_84       ; 2 B: slot being examined (initialised 16-bit, counted 8-bit)
!BattlePos_BestDist = !BattleTmp_86       ; 2 B: squared distance of the best battler so far
!BattlePos_SubjectCopy = !BattleTmp_8A    ; 1 B: subject slot (NearestEnemy skips it)
!BattlePos_DistSq = !BattleTmp_AF         ; 2 B: squared distance left by BattlePos_CheckDist
BattlePos_NearestPc:
    TDC
    TAX
    STX.b !BattlePos_ScanSlot       ; slot 0
    DEX
    STX.b !BattlePos_BestDist       ; $FFFF
.loop:
    LDA.b !BattlePos_ScanSlot
    STA.w !BattlePos_Other
    TAX
    LDA.w !Battler_Present,X
    BEQ .next
    LDA.w !Battler_Unk9FF7,X
    BMI .next
    TXA
    ASL A
    TAX
    REP #$20                        ; A -> 16-bit
    LDA.l !BattleRom_StatsOffset,X
    TAX
    TDC
    SEP #$20                        ; A -> 8-bit
    LDA.w BattlerStats.Status,X
    BMI .next                       ; KO'd
    JSR BattlePos_WithinDist32
    REP #$20                        ; A -> 16-bit
    LDA.b !BattlePos_BestDist
    CMP.b !BattlePos_DistSq
    BCC .keep                       ; best is nearer
    LDA.b !BattlePos_DistSq
    STA.b !BattlePos_BestDist
    LDA.b !BattlePos_ScanSlot
    STA.w !BattlePos_Found          ; (16-bit)
.keep:
    TDC
    SEP #$20                        ; A -> 8-bit
.next:
    INC.b !BattlePos_ScanSlot
    LDA.b !BattlePos_ScanSlot
    CMP.b #!Battle_NumPcSlots
    BNE .loop
    RTS

BattlePos_FarthestPc:               ; header: see BattlePos_NearestPc
    TDC
    TAX
    STX.b !BattlePos_ScanSlot       ; slot 0
    STX.b !BattlePos_BestDist       ; 0
.loop:
    LDA.b !BattlePos_ScanSlot
    STA.w !BattlePos_Other
    TAX
    LDA.w !Battler_Present,X
    BEQ .next
    LDA.w !Battler_Unk9FF7,X
    BMI .next
    TXA
    ASL A
    TAX
    REP #$20                        ; A -> 16-bit
    LDA.l !BattleRom_StatsOffset,X
    TAX
    TDC
    SEP #$20                        ; A -> 8-bit
    LDA.w BattlerStats.Status,X
    BMI .next                       ; KO'd
    JSR BattlePos_WithinDist32
    REP #$20                        ; A -> 16-bit
    LDA.b !BattlePos_DistSq
    CMP.b !BattlePos_BestDist
    BCC .keep                       ; best is farther
    LDA.b !BattlePos_DistSq
    STA.b !BattlePos_BestDist
    LDA.b !BattlePos_ScanSlot
    STA.w !BattlePos_Found          ; (16-bit)
.keep:
    TDC
    SEP #$20                        ; A -> 8-bit
.next:
    INC.b !BattlePos_ScanSlot
    LDA.b !BattlePos_ScanSlot
    CMP.b #!Battle_NumPcSlots
    BNE .loop
    RTS

BattlePos_NearestEnemy:             ; header: see BattlePos_NearestPc
    LDX.w #!BattlePos_NoBest
    STX.b !BattlePos_BestDist
    LDX.w #!Battle_FirstEnemySlot
    STX.b !BattlePos_ScanSlot
    LDA.w !BattlePos_Subject
    STA.b !BattlePos_SubjectCopy
.loop:
    LDA.b !BattlePos_ScanSlot
    CMP.b !BattlePos_SubjectCopy
    BEQ .next                       ; the subject itself
    STA.w !BattlePos_Other
    TAX
    LDA.w !Battler_Present,X
    BEQ .next
    LDA.w !Battler_Unk9FF7,X
    BMI .next
    TXA
    ASL A
    TAX
    REP #$20                        ; A -> 16-bit
    LDA.l !BattleRom_StatsOffset,X
    TAX
    TDC
    SEP #$20                        ; A -> 8-bit
    LDA.w BattlerStats.Status,X
    BMI .next                       ; KO'd
    JSR BattlePos_WithinDist32
    REP #$20                        ; A -> 16-bit
    LDA.b !BattlePos_BestDist
    CMP.b !BattlePos_DistSq
    BCC .keep                       ; best is nearer
    LDA.b !BattlePos_DistSq
    STA.b !BattlePos_BestDist
    LDA.b !BattlePos_ScanSlot
    STA.w !BattlePos_Found          ; (16-bit)
.keep:
    TDC
    SEP #$20                        ; A -> 8-bit
.next:
    INC.b !BattlePos_ScanSlot
    LDA.b !BattlePos_ScanSlot
    CMP.b #!Battle_NumSlots
    BNE .loop
    RTS

BattlePos_FarthestEnemy:            ; header: see BattlePos_NearestPc
    TDC
    TAX
    STX.b !BattlePos_BestDist       ; 0
    LDX.w #!Battle_FirstEnemySlot
    STX.b !BattlePos_ScanSlot
.loop:
    LDA.b !BattlePos_ScanSlot
    STA.w !BattlePos_Other
    TAX
    LDA.w !Battler_Present,X
    BEQ .next
    LDA.w !Battler_Unk9FF7,X
    BMI .next
    TXA
    ASL A
    TAX
    REP #$20                        ; A -> 16-bit
    LDA.l !BattleRom_StatsOffset,X
    TAX
    TDC
    SEP #$20                        ; A -> 8-bit
    LDA.w BattlerStats.Status,X
    BMI .next                       ; KO'd
    JSR BattlePos_WithinDist32
    REP #$20                        ; A -> 16-bit
    LDA.b !BattlePos_DistSq
    CMP.b !BattlePos_BestDist
    BCC .keep                       ; best is farther
    LDA.b !BattlePos_DistSq
    STA.b !BattlePos_BestDist
    LDA.b !BattlePos_ScanSlot
    STA.w !BattlePos_Found          ; (16-bit)
.keep:
    TDC
    SEP #$20                        ; A -> 8-bit
.next:
    INC.b !BattlePos_ScanSlot
    LDA.b !BattlePos_ScanSlot
    CMP.b #!Battle_NumSlots
    BNE .loop
    RTS

; ==================================================================
; BattlePos_WithinDist* ($C12AE3–$C12BBB, 217 bytes; queries 4 and 14)
; ==================================================================
; Squared-distance checks between two battlers' probe positions:
; Result = 0 when dx*dx + dy*dy <= the entry's limit, else $FF; the
; squared distance is left in !BattlePos_DistSq. Each entry sets
; !BattlePos_DistLimit and joins BattlePos_CheckDist; the "XY" entries
; take the two slots in X and Y from the caller, the others load them
; from !BattlePos_Subject (X) and !BattlePos_Other (Y) in
; BattlePos_CheckPairDist. The entries: BattlePos_WithinDist40XY,
; BattlePos_WithinDist32XY, BattlePos_WithinDist64XY,
; BattlePos_WithinDist4XY, BattlePos_WithinDist4XYTwin,
; BattlePos_WithinDist16XY, BattlePos_WithinDist48 and
; BattlePos_WithinDist32 (which falls into BattlePos_CheckPairDist, and
; that into BattlePos_CheckDist). WithinDist4XY and WithinDist4XYTwin run
; the same code (same limit, two copies in the ROM, one caller each); the
; bytes differ only in the BRA displacement to CheckDist ($36 vs $2A).
; The 16-bit sum of the two squares wraps for points about 256 pixels
; or more apart (reproduced as found; on-screen distances keep below).
; Callers (JSR, scanned for JSR/JSL/JML/JMP/BRL, hits inside other
; instructions discarded):
;   WithinDist40XY      $C1:4A26 (unmatched)
;   WithinDist32XY      BattlePos_PathClear ($C1:2C5D), $C1:3819 (unmatched)
;   WithinDist64XY      $C1:3821 (unmatched)
;   WithinDist4XY       $C1:3829 (unmatched)
;   WithinDist4XYTwin   $C1:3B38 (unmatched)
;   WithinDist16XY      $C1:3CBB (unmatched)
;   WithinDist48        BattlePos_ModeTable entry 14 only
;   WithinDist32        BattlePos_ModeTable entry 4, and the scans of
;                       queries 0-3: BattlePos_NearestPc ($C1:29DB),
;                       BattlePos_FarthestPc ($C1:2A23),
;                       BattlePos_NearestEnemy ($C1:2A78) and
;                       BattlePos_FarthestEnemy ($C1:2AC3)
;   CheckPairDist, CheckDist  only by falling in or BRA from the entries
; Entry: M=1, X=0, DP=0, DB=$7E; for the XY entries and CheckDist X and
;        Y = the two battler slots (CheckPairDist and CheckDist also take
;        !BattlePos_DistLimit as set by the entry)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0 or $FF; X = dx*dx (from
;        Battle_Mul8's product); Y unchanged for the XY entries and
;        CheckDist, = the slot from !BattlePos_Other for WithinDist32,
;        WithinDist48 and CheckPairDist; DP $77-$78, $80-$83 and $AD-$B0
;        written; !BattlePos_DistLimit set
; Callee: Battle_Mul8 (twice)
!BattlePos_CoordA = !BattleTmp_80         ; 2 B: first battler's coordinate (zero-extended), then |dy|
!BattlePos_CoordB = !BattleTmp_82         ; 2 B: second battler's coordinate, then dx*dx
BattlePos_WithinDist40XY:
    LDA.b #!BattlePos_DistSq40&$FF
    STA.w !BattlePos_DistLimit
    LDA.b #!BattlePos_DistSq40>>8
    STA.w !BattlePos_DistLimit+1
    BRA BattlePos_CheckDist

BattlePos_WithinDist32XY:           ; header: see BattlePos_WithinDist40XY
    LDA.b #!BattlePos_DistSq32&$FF
    STA.w !BattlePos_DistLimit
    LDA.b #!BattlePos_DistSq32>>8
    STA.w !BattlePos_DistLimit+1
    BRA BattlePos_CheckDist

BattlePos_WithinDist64XY:           ; header: see BattlePos_WithinDist40XY
    LDA.b #!BattlePos_DistSq64&$FF
    STA.w !BattlePos_DistLimit
    LDA.b #!BattlePos_DistSq64>>8
    STA.w !BattlePos_DistLimit+1
    BRA BattlePos_CheckDist

BattlePos_WithinDist4XY:            ; header: see BattlePos_WithinDist40XY
    LDA.b #!BattlePos_DistSq4&$FF
    STA.w !BattlePos_DistLimit
    LDA.b #!BattlePos_DistSq4>>8
    STA.w !BattlePos_DistLimit+1
    BRA BattlePos_CheckDist

BattlePos_WithinDist4XYTwin:        ; header: see BattlePos_WithinDist40XY
    LDA.b #!BattlePos_DistSq4&$FF
    STA.w !BattlePos_DistLimit
    LDA.b #!BattlePos_DistSq4>>8
    STA.w !BattlePos_DistLimit+1
    BRA BattlePos_CheckDist

BattlePos_WithinDist16XY:           ; header: see BattlePos_WithinDist40XY
    LDA.b #!BattlePos_DistSq16&$FF
    STA.w !BattlePos_DistLimit
    LDA.b #!BattlePos_DistSq16>>8
    STA.w !BattlePos_DistLimit+1
    BRA BattlePos_CheckDist

BattlePos_WithinDist48:             ; header: see BattlePos_WithinDist40XY
    LDA.b #!BattlePos_DistSq48&$FF
    STA.w !BattlePos_DistLimit
    LDA.b #!BattlePos_DistSq48>>8
    STA.w !BattlePos_DistLimit+1
    BRA BattlePos_CheckPairDist

BattlePos_WithinDist32:             ; header: see BattlePos_WithinDist40XY
    LDA.b #!BattlePos_DistSq32&$FF
    STA.w !BattlePos_DistLimit
    LDA.b #!BattlePos_DistSq32>>8
    STA.w !BattlePos_DistLimit+1
BattlePos_CheckPairDist:            ; X = subject, Y = other; header: see BattlePos_WithinDist40XY
    LDA.w !BattlePos_Subject
    TAX
    LDA.w !BattlePos_Other
    TAY
BattlePos_CheckDist:                ; X, Y = the two battlers; header: see BattlePos_WithinDist40XY
    LDA.w !Battler_ProbeX,X
    STA.b !BattlePos_CoordA
    STZ.b !BattlePos_CoordA+1
    LDA.w !Battler_ProbeX,Y
    STA.b !BattlePos_CoordB
    STZ.b !BattlePos_CoordB+1
    REP #$20                        ; A -> 16-bit
    SEC
    LDA.b !BattlePos_CoordA
    SBC.b !BattlePos_CoordB
    BPL .dx_positive
    EOR.w #!Battle_Invert16
    INC A
.dx_positive:
    STA.b !Battle_Mul8A             ; 16-bit: |dx| to Mul8A, its high byte (0) to Mul8B
    TDC
    SEP #$20                        ; A -> 8-bit
    LDA.b !Battle_Mul8A
    STA.b !Battle_Mul8B             ; |dx| * |dx|
    LDA.w !Battler_ProbeY,X
    STA.b !BattlePos_CoordA
    STZ.b !BattlePos_CoordA+1
    LDA.w !Battler_ProbeY,Y
    STA.b !BattlePos_CoordB
    STZ.b !BattlePos_CoordB+1
    REP #$20                        ; A -> 16-bit
    SEC
    LDA.b !BattlePos_CoordA
    SBC.b !BattlePos_CoordB
    BPL .dy_positive
    EOR.w #!Battle_Invert16
    INC A
.dy_positive:
    STA.b !BattlePos_CoordA         ; |dy|
    TDC
    SEP #$20                        ; A -> 8-bit
    JSR Battle_Mul8                 ; dx * dx
    LDX.b !Battle_Mul8Product
    STX.b !BattlePos_CoordB
    LDA.b !BattlePos_CoordA
    STA.b !Battle_Mul8A
    STA.b !Battle_Mul8B
    JSR Battle_Mul8                 ; dy * dy
    REP #$21                        ; A -> 16-bit, carry clear
    LDA.b !BattlePos_CoordB
    ADC.b !Battle_Mul8Product
    STA.b !BattlePos_DistSq
    CMP.w !BattlePos_DistLimit
    BEQ .within
    BCC .within
    TDC
    SEP #$20                        ; A -> 8-bit
    LDA.b #!BattlePos_Fail
    STA.w !BattlePos_Result
    RTS
.within:
    TDC
    SEP #$20                        ; A -> 8-bit
    STA.w !BattlePos_Result         ; 0
    RTS

; ==================================================================
; BattlePos_SameRowBand / BattlePos_SubjectAbove / BattlePos_SubjectLeft
; ($C12BBC–$C12C01, 70 bytes; queries 5-7)
; ==================================================================
; Compare the subject's and the other battler's screen positions and
; DEC !BattlePos_Result (0 -> $FF) when the condition fails:
;   SameRowBand   |y difference| <= $20 (8-bit: a difference of $80 or
;                 more folds to its 256-complement)
;   SubjectAbove  subject y < other y
;   SubjectLeft   subject x < other x
; Callers: BattlePos_ModeTable entries 5-7 only (BattlePos_Query).
; Entry: M=1, X=0, DP=0, DB=$7E; !BattlePos_Result = 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A clobbered; X = subject, Y = other
; No calls.
BattlePos_SameRowBand:
    LDA.w !BattlePos_Subject
    TAX
    LDA.w !BattlePos_Other
    TAY
    SEC
    LDA.w !Battler_ScreenY,X
    SBC.w !Battler_ScreenY,Y
    BPL .positive
    EOR.b #!Battle_Invert8
    INC A                           ; |dy|
.positive:
    CMP.b #!BattlePos_RowBand
    BEQ .exit
    BCC .exit
    DEC.w !BattlePos_Result         ; too far apart
.exit:
    RTS

BattlePos_SubjectAbove:             ; header: see BattlePos_SameRowBand
    LDA.w !BattlePos_Subject
    TAX
    LDA.w !BattlePos_Other
    TAY
    LDA.w !Battler_ScreenY,X
    CMP.w !Battler_ScreenY,Y
    BCC .exit
    DEC.w !BattlePos_Result         ; not above
.exit:
    RTS

BattlePos_SubjectLeft:              ; header: see BattlePos_SameRowBand
    LDA.w !BattlePos_Subject
    TAX
    LDA.w !BattlePos_Other
    TAY
    LDA.w !Battler_ScreenX,X
    CMP.w !Battler_ScreenX,Y
    BCC .exit
    DEC.w !BattlePos_Result         ; not left of it
.exit:
    RTS

; ==================================================================
; BattlePos_PathClear ($C12C02–$C12CA6, 165 bytes; query 8)
; ==================================================================
; Places the subject's probe position out from its screen position in
; the direction Battle_CalcAngle gives from the subject to the other
; battler, at a radius of !Battle_SinScale (see the quirk below), and
; after each placement:
;   - checks the probe with BattlePos_WithinDist32XY; within -> done,
;     Result 0;
;   - otherwise clears !Battle_PassCellBit7 and rebuilds the subject's
;     box: a blocked cell, or (with !BattlePos_Arg non-zero) another
;     battler's box -> Result $FF; else another pass.
; At the end the subject's screen position is written back from the
; copy taken at the start (it was never changed here) and its box is
; rebuilt (tail JMP to Battle_CalcBattlerBox). That box comes from the
; probe position, so it is the box at the last probe, not at home.
; Quirk: at the distance check Y is the subject but X still holds what
; Battle_SinLookup left (Battle_Mul8x16's first partial product), not
; the other battler's slot, so the probe is compared with an arbitrary
; ProbeX/ProbeY,X byte pair. Reproduced as found; the other battler was
; probably meant.
; Quirk: the radius does not grow by !Battler_PathStep each pass.
; !Battle_SinScale is the same byte as !Battle_Mul8B ($AE), and the
; distance check leaves |dy| of its comparison there (its second
; Battle_Mul8 squares it), so from the second pass on the radius is
; PathStep + the previous check's |dy| (8-bit add), not a running sum.
; Reproduced as found.
; Callers: BattlePos_ModeTable entry 8 only (BattlePos_Query).
; Entry: M=1, X=0, DP=0, DB=$7E; !BattlePos_Subject, Other, Arg
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $80-$8E, $A5-$B0,
;        $D3-$E3 written (also $77-$78 through the multiplies);
;        !Battle_PassCellBit7 = 0 if any check failed (unchanged when the
;        first check is within)
; Callees: Battle_CalcAngle, Battle_SinLookup, BattlePos_WithinDist32XY,
;          Battle_CalcBattlerBox, Battle_BoxHitsBlockedCell,
;          Battle_BoxOverlapsOthers
!BattlePos_HomeX = !BattleTmp_8A          ; 1 B: subject screen x at the start
!BattlePos_HomeY = !BattleTmp_8B          ; 1 B: subject screen y at the start
!BattlePos_StepY = !BattleTmp_8C          ; 1 B: y offset of the probe this pass (sine * radius / 256)
!BattlePos_StepX = !BattleTmp_8E          ; 1 B: x offset (cosine * radius / 256)
BattlePos_PathClear:
    STZ.w !BattlePos_Result
    STZ.b !Battle_SinScale          ; radius 0
    LDA.w !BattlePos_Subject
    TAY
    LDA.w !BattlePos_Other
    TAX
    LDA.w !Battler_ScreenX,Y
    STA.b !BattlePos_HomeX
    STA.b !Battle_GeoOriginX
    LDA.w !Battler_ScreenY,Y
    STA.b !BattlePos_HomeY
    STA.b !Battle_GeoOriginY
    LDA.w !Battler_ScreenX,X
    STA.b !Battle_GeoPointX
    LDA.w !Battler_ScreenY,X
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle
.step:
    LDA.w !BattlePos_Subject
    TAX
    CLC
    LDA.w !Battler_PathStep,X
    ADC.b !Battle_SinScale
    STA.b !Battle_SinScale          ; radius = step + $AE (|dy| after pass 1, see header)
    LDA.b !Battle_GeoAngle
    JSR Battle_SinLookup
    STA.b !BattlePos_StepY
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup            ; cosine
    STA.b !BattlePos_StepX
    LDA.w !BattlePos_Subject
    TAY
    CLC
    LDA.w !Battler_ScreenY,Y
    ADC.b !BattlePos_StepY
    STA.w !Battler_ProbeY,Y
    CLC
    LDA.w !Battler_ScreenX,Y
    ADC.b !BattlePos_StepX
    STA.w !Battler_ProbeX,Y
    JSR BattlePos_WithinDist32XY    ; X is stale here (see header)
    LDA.w !BattlePos_Result
    BPL .done                       ; within: path clear
    LDA.w !BattlePos_Subject
    TAX
    STX.b !Battle_BoxTestSlot
    JSR Battle_CalcBattlerBox
    STZ.w !Battle_PassCellBit7
    JSR Battle_BoxHitsBlockedCell
    BMI .blocked
    LDA.w !BattlePos_Arg
    BEQ .free
    JSR Battle_BoxOverlapsOthers
    BMI .blocked
.free:
    LDA.w !BattlePos_Subject
    TAX
    LDA.b !BattlePos_HomeX
    STA.w !Battler_ScreenX,X
    LDA.b !BattlePos_HomeY
    STA.w !Battler_ScreenY,X
    JMP .step
.blocked:
    LDA.b #!BattlePos_Fail
    STA.w !BattlePos_Result
.done:
    LDA.w !BattlePos_Subject
    TAX
    LDA.b !BattlePos_HomeX
    STA.w !Battler_ScreenX,X
    LDA.b !BattlePos_HomeY
    STA.w !Battler_ScreenY,X
    JMP Battle_CalcBattlerBox

; ==================================================================
; BattlePos_SubjectLowerHalf / BattlePos_SubjectUpperHalf /
; BattlePos_SubjectRightPart / BattlePos_SubjectLeftPart
; ($C12CA7–$C12CF2, 76 bytes; queries 9-12)
; ==================================================================
; Test the subject's 16-pixel cell (screen position / 16) and DEC
; !BattlePos_Result (0 -> $FF) when the condition fails:
;   LowerHalf  y / 16 >= 8          UpperHalf  y / 16 < 8
;   RightPart  x / 16 >= 11         LeftPart   x / 16 < 5
; Callers: BattlePos_ModeTable entries 9-12 only (BattlePos_Query).
; Entry: M=1, X=0, DP=0, DB=$7E; !BattlePos_Result = 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A clobbered; X = subject; Y unchanged
; No calls.
BattlePos_SubjectLowerHalf:
    LDA.w !BattlePos_Subject
    TAX
    LDA.w !Battler_ScreenY,X
    LSR A
    LSR A
    LSR A
    LSR A
    CMP.b #!BattlePos_MidRow
    BCS .exit
    DEC.w !BattlePos_Result
.exit:
    RTS

BattlePos_SubjectUpperHalf:         ; header: see BattlePos_SubjectLowerHalf
    LDA.w !BattlePos_Subject
    TAX
    LDA.w !Battler_ScreenY,X
    LSR A
    LSR A
    LSR A
    LSR A
    CMP.b #!BattlePos_MidRow
    BCC .exit
    DEC.w !BattlePos_Result
.exit:
    RTS

BattlePos_SubjectRightPart:         ; header: see BattlePos_SubjectLowerHalf
    LDA.w !BattlePos_Subject
    TAX
    LDA.w !Battler_ScreenX,X
    LSR A
    LSR A
    LSR A
    LSR A
    CMP.b #!BattlePos_RightCol
    BCS .exit
    DEC.w !BattlePos_Result
.exit:
    RTS

BattlePos_SubjectLeftPart:          ; header: see BattlePos_SubjectLowerHalf
    LDA.w !BattlePos_Subject
    TAX
    LDA.w !Battler_ScreenX,X
    LSR A
    LSR A
    LSR A
    LSR A
    CMP.b #!BattlePos_LeftColEnd
    BCC .exit
    DEC.w !BattlePos_Result
.exit:
    RTS

; ==================================================================
; BattlePos_DistDifference ($C12CF3–$C12D80, 142 bytes; query 13)
; ==================================================================
; Measures, from the other battler's screen position, the squared
; distance to the subject (d1) and to the battler in !BattlePos_Arg
; (d2), and stores |d2 - d1| / 256 (low byte) in !BattlePos_Found.
; Result is left at 0. What the scripts use the value for is not traced.
; The per-axis differences are 8-bit (a difference of $80 or more folds
; to its 256-complement), so each is at most $80, each square at most
; $4000 and d1, d2 at most $8000: the 16-bit sums do not wrap and
; |d2 - d1| is exact.
; Callers: BattlePos_ModeTable entry 13 only (BattlePos_Query).
; Entry: M=1, X=0, DP=0, DB=$7E; !BattlePos_Subject, Other, Arg
; Exit:  M=1, X=0, DP=0, DB=$7E; A clobbered; X = d2's dx*dx; Y = Arg;
;        DP $77-$78, $80-$85 and $AD-$B0 written
; Callees: Battle_Mul8 (four times), Battle_ShiftRight8 (16-bit)
!BattlePos_PointX = !BattleTmp_80         ; 1 B: other battler's x; at the end the 16-bit result
!BattlePos_PointY = !BattleTmp_81         ; 1 B: other battler's y
!BattlePos_DistSq1 = !BattleTmp_82        ; 2 B: d1 (dx*dx first)
!BattlePos_DistSq2 = !BattleTmp_84        ; 2 B: dx*dx of d2
BattlePos_DistDifference:
    LDA.w !BattlePos_Other
    TAX
    LDA.w !Battler_ScreenX,X
    STA.b !BattlePos_PointX
    LDA.w !Battler_ScreenY,X
    STA.b !BattlePos_PointY
    LDA.w !BattlePos_Subject
    TAY
    SEC
    LDA.b !BattlePos_PointX
    SBC.w !Battler_ScreenX,Y
    BPL .dx1_positive
    EOR.b #!Battle_Invert8
    INC A
.dx1_positive:
    STA.b !Battle_Mul8A
    STA.b !Battle_Mul8B
    JSR Battle_Mul8
    LDX.b !Battle_Mul8Product
    STX.b !BattlePos_DistSq1
    SEC
    LDA.b !BattlePos_PointY
    SBC.w !Battler_ScreenY,Y
    BPL .dy1_positive
    EOR.b #!Battle_Invert8
    INC A
.dy1_positive:
    STA.b !Battle_Mul8A
    STA.b !Battle_Mul8B
    JSR Battle_Mul8
    REP #$21                        ; A -> 16-bit, carry clear
    LDA.b !Battle_Mul8Product
    ADC.b !BattlePos_DistSq1
    STA.b !BattlePos_DistSq1        ; d1
    TDC
    SEP #$20                        ; A -> 8-bit
    LDA.w !BattlePos_Arg
    TAY
    SEC
    LDA.b !BattlePos_PointX
    SBC.w !Battler_ScreenX,Y
    BPL .dx2_positive
    EOR.b #!Battle_Invert8
    INC A
.dx2_positive:
    STA.b !Battle_Mul8A
    STA.b !Battle_Mul8B
    JSR Battle_Mul8
    LDX.b !Battle_Mul8Product
    STX.b !BattlePos_DistSq2
    SEC
    LDA.b !BattlePos_PointY
    SBC.w !Battler_ScreenY,Y
    BPL .dy2_positive
    EOR.b #!Battle_Invert8
    INC A
.dy2_positive:
    STA.b !Battle_Mul8A
    STA.b !Battle_Mul8B
    JSR Battle_Mul8
    REP #$21                        ; A -> 16-bit, carry clear
    LDA.b !Battle_Mul8Product
    ADC.b !BattlePos_DistSq2        ; d2
    SEC
    SBC.b !BattlePos_DistSq1
    BPL .diff_positive
    EOR.w #!Battle_Invert16
    INC A
.diff_positive:
    JSR Battle_ShiftRight8          ; / 256
    STA.b !BattlePos_PointX         ; (16-bit)
    TDC
    SEP #$20                        ; A -> 8-bit
    LDA.b !BattlePos_PointX
    STA.w !BattlePos_Found
    RTS

; BattlePos_ModeTable ($C12D81–$C12D9E, 30 bytes): query handlers by
; !BattlePos_Mode, called from BattlePos_Query.
BattlePos_ModeTable:
    dw BattlePos_NearestPc          ; $00
    dw BattlePos_FarthestPc         ; $01
    dw BattlePos_NearestEnemy       ; $02
    dw BattlePos_FarthestEnemy      ; $03
    dw BattlePos_WithinDist32       ; $04
    dw BattlePos_SameRowBand        ; $05
    dw BattlePos_SubjectAbove       ; $06
    dw BattlePos_SubjectLeft        ; $07
    dw BattlePos_PathClear          ; $08
    dw BattlePos_SubjectLowerHalf   ; $09
    dw BattlePos_SubjectUpperHalf   ; $0A
    dw BattlePos_SubjectRightPart   ; $0B
    dw BattlePos_SubjectLeftPart    ; $0C
    dw BattlePos_DistDifference     ; $0D
    dw BattlePos_WithinDist48       ; $0E

; ==================================================================
; PC animation tick ($C1:2D9F–$C1:2F96)
; ==================================================================

; ==================================================================
; Battle_TickPcSlots ($C12D9F–$C12F1E, 384 bytes)
; ==================================================================
; Per-frame animation step for the three PCs. With !Battle_UnkA4 set it
; jumps to Battle_TickEnemyGroup instead. Otherwise it
; visits the PCs in !Battle_TickOrder, starting with the first PC whose
; frame decode was put off (!Battler_FrameDeferred; 0,1,2 / 1,2,0 /
; 2,0,1), and for each present PC:
;   - once a frame has been decoded this pass (!Battle_FramesDecoded =
;     1), only marks the PC deferred, so it goes first next time
;     (inferred: one decode per frame);
;   - counts down !Pc_AnimTimer; at 0 it picks the animation
;     (Battle_PickStatusAnim, into !Battle_AnimId), updates the facing
;     (Battle_UpdatePcFacing) and the status effect
;     (Battle_ApplyPendingEffect). Animation 3 becomes $2B while
;     !Battle_Unk99CF or !Battle_Unk99D0 is set, restarting the list;
;   - steps !Battler_AnimFrame through the animation's lists in bank $E4
;     (!BattleRom_AnimData): the duration list (!Battler_AnimDurBase +
;     AnimId * 4) and the frame-id list (!Battler_AnimFrameBase +
;     AnimId * 4 + Facing * FacingStride). A duration of 0 ends the list
;     and the index goes back to 0 (a list whose first entry is 0 would
;     loop for ever). The timer is reloaded with duration / 5 (at
;     least 1);
;   - decodes the frame (Battle_DrawBattlerFrame) when the animation
;     changed, or when it is not animation 3, or when animation 3 has a
;     new facing or belongs to the PC whose menu is shown.
; Lists, ids and the "facing" reading are inferred from how the values
; combine; the animation data itself has not been looked at.
; Callers (JSR, scanned for JSR/JSL/JML/JMP/BRL, hits inside other
; instructions discarded): BattleSys_UpkeepTwoFrames only.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $80-$94 and the
;        callees' scratch written
; Callees: Battle_TickEnemyGroup (JMP), Battle_PickStatusAnim,
;          Battle_UpdatePcFacing, Battle_ApplyPendingEffect,
;          Battle_Mul8x16, Battle_Divide, Battle_DrawBattlerFrame
!Battle_TickOrderIdx = !BattleTmp_92      ; 2 B: index into !Battle_TickOrder (zeroed 16-bit, counted 8-bit)
!Battle_TickSlot = !BattleTmp_94          ; 2 B: battler slot being ticked (16-bit; also read by the callees)
!Battle_TickFacingOffset = !BattleTmp_82  ; 2 B: AnimId * 4, then Facing * FacingStride
!Battle_FacingChanged = !BattleTmp_80     ; 1 B: set by Battle_UpdatePcFacing when the facing changed
!Battle_TickUnk84 = !BattleTmp_84         ; 1 B: set to 3 here; Battle_PickStatusAnim sets it again before use
Battle_TickPcSlots:
    STZ.w !Battle_FramesDecoded
    LDA.b !Battle_UnkA4
    BEQ .order
    JMP Battle_TickEnemyGroup
.order:
    LDA.b #!Battle_AnimDefault
    STA.b !Battle_TickUnk84         ; (overwritten before it is read)
    LDA.w !Battler_FrameDeferred
    BEQ .pc1_deferred
    STZ.w !Battler_FrameDeferred
    TDC
    STA.w !Battle_TickOrder             ; 0, 1, 2
    INC A
    STA.w !Battle_TickOrder+1
    INC A
    STA.w !Battle_TickOrder+2
    BRA .tick
.pc1_deferred:
    LDA.w !Battler_FrameDeferred+1
    BEQ .pc2_deferred
    STZ.w !Battler_FrameDeferred+1
    LDA.b #1
    STA.w !Battle_TickOrder             ; 1, 2, 0
    INC A
    STA.w !Battle_TickOrder+1
    TDC
    STA.w !Battle_TickOrder+2
    BRA .tick
.pc2_deferred:
    LDA.w !Battler_FrameDeferred+2
    BEQ .none_deferred
    STZ.w !Battler_FrameDeferred+2
    LDA.b #2
    STA.w !Battle_TickOrder             ; 2, 0, 1
    TDC
    STA.w !Battle_TickOrder+1
    INC A
    STA.w !Battle_TickOrder+2
    BRA .tick
.none_deferred:
    TDC
    STA.w !Battle_TickOrder             ; 0, 1, 2
    INC A
    STA.w !Battle_TickOrder+1
    INC A
    STA.w !Battle_TickOrder+2
.tick:
    TDC
    TAX
    STX.b !Battle_TickOrderIdx
.loop:
    LDX.b !Battle_TickOrderIdx
    LDA.w !Battle_TickOrder,X
    TAX
    STX.b !Battle_TickSlot
    LDA.w !Battler_Present,X
    BNE .present
    JMP .next
.present:
    LDA.w !Battle_FramesDecoded
    CMP.b #1
    BNE .count_down
    INC.w !Battler_FrameDeferred,X  ; a frame was decoded already: go first next time
    JMP .next
.count_down:
    LDX.b !Battle_TickSlot
    DEC.w !Pc_AnimTimer,X
    BEQ .step
    JMP .next
.step:
    JSR Battle_PickStatusAnim
    JSR Battle_UpdatePcFacing
    JSR Battle_ApplyPendingEffect
    LDA.w !Battle_AnimId
    CMP.b #!Battle_AnimDefault
    BNE .lists
    LDA.w !Battle_Unk99CF
    ORA.w !Battle_Unk99D0
    BEQ .lists
    LDA.b #!Battle_AnimUnk2B
    STA.w !Battle_AnimId
    LDX.b !Battle_TickSlot
    LDA.b #!Battle_AnimRestart
    STA.w !Battler_AnimFrame,X
.lists:
    LDA.b !Battle_TickSlot
    ASL A
    CLC
    ADC.b !Battle_TickSlot
    TAX                             ; slot * 3
    LDA.w !Battler_AnimFrameBase,X
    STA.w !Battle_AnimFrameList
    LDA.w !Battler_AnimFrameBase+1,X
    STA.w !Battle_AnimFrameList+1
    LDA.w !Battler_AnimDurBase,X
    STA.w !Battle_AnimDurList
    LDA.w !Battler_AnimDurBase+1,X
    STA.w !Battle_AnimDurList+1
    LDA.w !Battle_AnimId
    REP #$20                        ; A -> 16-bit
    ASL A
    ASL A
    STA.b !Battle_TickFacingOffset  ; AnimId * 4
    CLC
    ADC.w !Battle_AnimDurList
    STA.w !Battle_AnimDurList
    CLC
    LDA.b !Battle_TickFacingOffset
    ADC.w !Battle_AnimFrameList
    STA.w !Battle_AnimFrameList
    TDC
    SEP #$20                        ; A -> 8-bit
    LDX.b !Battle_TickSlot
    LDA.w !Battler_Facing,X
    STA.b !Battle_MulFactor8
    LDA.w !Battler_FacingStrideLo,X
    STA.b !Battle_MulFactor16
    LDA.w !Battler_FacingStrideHi,X
    STA.b !Battle_MulFactor16+1
    JSR Battle_Mul8x16
    LDX.b !Battle_MulProduct
    STX.b !Battle_TickFacingOffset  ; Facing * FacingStride
    LDA.b !Battle_TickSlot
    STA.w !Battle_FrameSlot
    ASL A
    TAY                             ; (Y is not used below)
    LDX.b !Battle_TickSlot
    CLC
    LDA.w !Battler_AnimFrame,X
    ADC.b #1
.set_frame:
    STA.w !Battler_AnimFrame,X
    REP #$21                        ; A -> 16-bit, carry clear
    ADC.w !Battle_AnimDurList
    TAX
    TDC
    SEP #$20                        ; A -> 8-bit
    LDA.l !BattleRom_AnimData,X     ; this frame's duration
    BNE .duration
    TDC                             ; end of the list: back to frame 0
    LDX.b !Battle_TickSlot
    BRA .set_frame
.duration:
    LDX.b !Battle_TickSlot
    STA.b !Battle_DivDividend
    STZ.b !Battle_DivDividend+1
    LDA.b #!Battle_AnimTicksDivisor
    STA.b !Battle_DivDivisor
    JSR Battle_Divide
    LDA.b !Battle_DivQuotient
    BNE .timer
    INC A                           ; at least 1
.timer:
    STA.w !Pc_AnimTimer,X
    LDX.b !Battle_TickSlot
    LDA.w !Battler_AnimFrame,X
    REP #$21                        ; A -> 16-bit, carry clear
    ADC.b !Battle_TickFacingOffset
    CLC
    ADC.w !Battle_AnimFrameList
    TAX
    TDC
    SEP #$20                        ; A -> 8-bit
    LDA.l !BattleRom_AnimData,X     ; frame id
    STA.w !Battle_FrameId
    LDX.b !Battle_TickSlot
    LDA.w !Battle_AnimId
    CMP.w !Battler_AnimShown,X
    BEQ .same_anim
    STA.w !Battler_AnimShown,X
    BRA .draw
.same_anim:
    CMP.b #!Battle_AnimDefault
    BNE .draw
    LDA.b !Battle_FacingChanged
    BNE .draw
    LDA.w !BattleMenu_ActivePc
    CMP.b !Battle_TickSlot
    BNE .next                       ; idle, same facing, menu not shown: skip
.draw:
    JSR Battle_DrawBattlerFrame
.next:
    INC.b !Battle_TickOrderIdx
    LDA.b !Battle_TickOrderIdx
    CMP.b #!Battle_NumPcSlots
    BEQ .exit
    JMP .loop
.exit:
    RTS

; Battle_UnkThunk2F1F ($C12F1F–$C12F21, 3 bytes): a lone JMP to the RTS
; that ends Battle_TickEnemyGroup ($C1:34A6). Nothing reaches it (searched: no JSR, JMP, JSL, JML or
; BRL targets $2F1F, and no word table holds it); kept as found.
; Entry: none (unreached); as written it needs only a return address on
;        the stack, like the RTS it jumps to
; Exit:  as Battle_TickEnemyGroup's RTS: no register, flag or memory
;        changed
Battle_UnkThunk2F1F:
    JMP Battle_TickEnemyGroup_exit

; ==================================================================
; Battle_UpdatePcFacing ($C12F22–$C12F96, 117 bytes)
; ==================================================================
; Turns PC !Battle_TickSlot toward its nearest enemy, one PC at a time:
; !Battle_FacingTurn holds the PC whose turn it is (bit 7 = the turn was
; handed on and has not been taken yet). A PC that is not the one named
; hands the turn to itself (sets FacingTurn = slot | $80) if bit 7 is
; clear, and returns. The PC named clears bit 7 and, unless it is KO'd
; (BattlerStats.Status bit 7) or BattlerStats.Status2 bit 1 is set, runs
; position query 2 (nearest enemy, BattlePos_NearestEnemy) through
; service 5, keeps the enemy in !Pc_FacingTarget, and sets
; !Battler_Facing from !BattleRom_FacingByAngle[angle to the enemy].
; Returns !Battle_FacingChanged = 1 when the facing changed, else 0.
; The turn-passing reading and the meaning of the Status2 bit are inferred
; or unknown. The BattlerStats offset in !Battle_PickStatsOffset comes
; from Battle_PickStatusAnim, which runs first.
; Callers (JSR, scanned as above): Battle_TickPcSlots only.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_TickSlot, and
;        !Battle_PickStatsOffset = its BattlerStats offset
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $80-$81 written
;        (and the query's and Battle_CalcAngle's scratch when it runs)
; Callees: BattleSys_RunService (service 5), Battle_CalcAngle
!Battle_FacingTurnSlot = !BattleTmp_81    ; 1 B: !Battle_FacingTurn without bit 7
!Battle_PickStatsOffset = !BattleTmp_A2   ; 2 B: BattlerStats offset of !Battle_TickSlot (set by Battle_PickStatusAnim)
Battle_UpdatePcFacing:
    STZ.b !Battle_FacingChanged
    LDA.w !Battle_FacingTurn
    AND.b #!Battle_FacingSlotMask
    STA.b !Battle_FacingTurnSlot
    LDA.b !Battle_TickSlot
    CMP.b !Battle_FacingTurnSlot
    BEQ .my_turn
    LDA.w !Battle_FacingTurn
    BMI .exit                       ; already handed on
    LDA.b !Battle_TickSlot
    ORA.b #!Battle_FacingHandedOn
    STA.w !Battle_FacingTurn
    BRA .exit
.my_turn:
    LDA.b !Battle_FacingTurnSlot
    STA.w !Battle_FacingTurn        ; take it (bit 7 clear)
    LDY.b !Battle_PickStatsOffset
    LDA.w BattlerStats.Status,Y
    BPL .alive
    BRA .exit                       ; KO'd
.alive:
    LDA.w BattlerStats.Status2,Y
    AND.b #!Battle_StatusUnk4BNoTurn
    BNE .exit
    LDA.b #!BattlePos_QueryNearestEnemy
    STA.w !BattlePos_Mode
    LDA.b !Battle_TickSlot
    STA.w !BattlePos_Subject
    LDA.b #!BattleSys_ServicePosQuery
    JSR BattleSys_RunService
    LDX.b !Battle_TickSlot
    LDA.w !Battler_ScreenX,X
    STA.b !Battle_GeoOriginX
    LDA.w !Battler_ScreenY,X
    STA.b !Battle_GeoOriginY
    LDA.w !BattlePos_Found
    STA.w !Pc_FacingTarget,X
    TAX
    LDA.w !Battler_ScreenX,X
    STA.b !Battle_GeoPointX
    LDA.w !Battler_ScreenY,X
    STA.b !Battle_GeoPointY
    STZ.b !Battle_FacingChanged
    JSR Battle_CalcAngle
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    LDX.b !Battle_TickSlot
    CMP.w !Battler_Facing,X
    BEQ .exit
    STA.w !Battler_Facing,X
    INC.b !Battle_FacingChanged
.exit:
    RTS

; ==================================================================
; Status animations and status effects ($C1:2F97–$C1:3233)
; ==================================================================

; ==================================================================
; Battle_PickStatusAnim ($C12F97–$C1305B, 197 bytes)
; ==================================================================
; Picks the animation and the status effect for battler !Battle_TickSlot
; from its status bytes:
;   - default animation 3 (!Battle_AnimDefault), or 0 for an
;     untargetable battler; effect !Battle_FxNone;
;   - keeps the battler's BattlerStats offset in !Battle_PickStatsOffset
;     (Battle_UpdatePcFacing uses it next) and clears DP $80-$81;
;   - a KO'd battler (Status bit 7), or one with !Battler_UnkA119 set,
;     gets !Battler_KoFlag = 1 and its animation list restarted;
;   - walks BattleRom_StatusAnim, 4-byte records (status byte, mask,
;     effect, animation) ended by a negative status byte. The first
;     record whose bits are set in the battler's stats wins; the first
;     record (KO) also wins when !Battler_UnkA119 is set. A record
;     without an animation of its own ($FF) is skipped while
;     !BattleMenu_Lock is set, otherwise it gives animation 3. A
;     non-negative effect goes to !Battler_FxWanted, and a new one
;     restarts the animation list;
;   - when no record matches and BattlerStats.Unk2F bit 0 is set (and the
;     battler is targetable): effect !Battle_FxUnk2F and animation $12.
; The result goes to !Battle_AnimId. The record table (read from the ROM)
; maps Status bit 7 to animation 8 and Status2 / the bytes at +$4D, +$4E,
; +$52, +$53 to effects 2-$0E; what those status bits mean in the game is
; not established here.
; Quirk: on the Unk2F path the restart test compares
; !Battler_FxApplied with $12, the animation id, not the effect $80 just
; stored. The effects written to FxApplied in bank $C1 are 0-$0E, $80 and
; $FF, so as far as traced the test never matches and a PC's list restarts
; on every pick (kept as found; the battle-init writers in bank $CC were
; not checked).
; Quirk: the restarts at the top and after a record match store into
; !Battler_AnimFrame,X for any slot, while the array is 3 bytes long; for
; enemy slots 8-10 the store lands on !Enemy_AnimTimer+0..2
; (Battle_TickEnemyGroup). Only the Unk2F path checks for a PC slot.
; Whether that matters in play is not traced.
; Callers (JSR; scanned for JSR/JSL/JML/JMP/BRL and word tables, hits
; inside other instructions discarded): Battle_TickPcSlots,
; Battle_PickNextStatusAnim.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_TickSlot = battler slot
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $80-$81, $84 and
;        $A2-$A3 written
; No calls.
!Battle_PickAnim = !BattleTmp_84          ; 1 B: animation picked so far
Battle_PickStatusAnim:
    LDX.b !Battle_TickSlot
    LDA.w !Battler_Untargetable,X
    BEQ .targetable
    LDA.b #!Battle_AnimUntargetable
    BRA .set_default
.targetable:
    LDA.b #!Battle_AnimDefault
.set_default:
    STA.b !Battle_PickAnim
    LDA.b #!Battle_FxNone
    STA.w !Battler_FxWanted,X
    LDA.b !Battle_TickSlot
    ASL A
    TAX
    REP #$20                        ; A -> 16-bit
    LDA.l !BattleRom_StatsOffset,X
    TAY
    STY.b !Battle_PickStatsOffset
    TDC
    STA.b !Battle_FacingChanged     ; (16-bit: clears $80 and $81)
    SEP #$20                        ; A -> 8-bit
    LDX.b !Battle_TickSlot
    LDA.w !Battler_UnkA119,X
    BNE .down
    LDA.w BattlerStats.Status,Y
    BPL .scan
.down:
    LDA.b #1
    STA.w !Battler_KoFlag,X
    LDA.b #!Battle_AnimRestart
    STA.w !Battler_AnimFrame,X      ; (an enemy slot writes past the PC array)
.scan:
    TDC
    TAX                             ; X = record offset
.record:
    LDA.l BattleRom_StatusAnim.StatusByte,X
    BMI .table_end
    REP #$21                        ; A -> 16-bit, carry clear
    ADC.b !Battle_PickStatsOffset
    TAY
    TDC
    SEP #$20                        ; A -> 8-bit
    LDA.w BattlerStats.Status,Y     ; the record's status byte
    AND.l BattleRom_StatusAnim.Mask,X
    BNE .match
    TXA
    BNE .next_record
    LDX.b !Battle_TickSlot          ; first record (KO): Unk A119 forces it
    LDA.w !Battler_UnkA119,X
    BEQ .not_forced
    TDC
    TAX
    BRA .match
.not_forced:
    TDC
    TAX
    BRA .next_record
.match:
    LDA.l BattleRom_StatusAnim.Anim,X
    CMP.b #!Battle_StatusAnimNone
    BNE .set_anim
    LDA.w !BattleMenu_Lock
    BNE .next_record                ; no animation of its own: look further while locked
    LDA.b #!Battle_AnimDefault
.set_anim:
    STA.b !Battle_PickAnim
    LDY.b !Battle_TickSlot
    LDA.l BattleRom_StatusAnim.Effect,X
    BMI .effect_done
    STA.w !Battler_FxWanted,Y
    CMP.w !Battler_FxApplied,Y
    BEQ .effect_done
    LDA.b #!Battle_AnimRestart
    STA.w !Battler_AnimFrame,Y      ; (an enemy slot writes past the PC array)
.effect_done:
    BRA .use_pick
.next_record:
    INX
    INX
    INX
    INX
    BRA .record
.table_end:
    LDY.b !Battle_PickStatsOffset
    LDA.w BattlerStats.Unk2F,Y
    AND.b #!Battle_StatsUnk2FBit
    BEQ .use_pick
    LDY.b !Battle_TickSlot
    LDA.w !Battler_Untargetable,Y
    BNE .use_pick
    LDA.b #!Battle_FxUnk2F
    STA.w !Battler_FxWanted,Y
    LDA.b #!Battle_AnimUnk12
    CMP.w !Battler_FxApplied,Y      ; quirk: the animation id, not the effect (see header)
    BEQ .anim_unk12
    CPY.w #!Battle_NumPcSlots
    BCS .anim_unk12
    LDA.b #!Battle_AnimRestart
    STA.w !Battler_AnimFrame,Y
.anim_unk12:
    LDA.b #!Battle_AnimUnk12
    BRA .store
.use_pick:
    LDA.b !Battle_PickAnim
.store:
    STA.w !Battle_AnimId
    RTS

; ==================================================================
; Battle_PickNextStatusAnim ($C1305C–$C1308B, 48 bytes)
; ==================================================================
; Runs Battle_PickStatusAnim for one battler per call, the slot in
; !Battle_StatusAnimNext (if present), and moves it on; past slot 10 it
; counts a wrap in !Battle_StatusAnimWraps and goes back to slot 3, so
; after the first pass only enemies are visited (the PCs are picked by
; Battle_TickPcSlots). Then runs Battle_ApplyPendingEffect for all 11
; slots. The animation id the pick leaves in !Battle_AnimId is not used
; here.
; Callers (JSR; scanned as above): the unmatched code at $C1:4127, which
; starts it at slot 0 and calls it until !Battle_StatusAnimWraps is set
; (inferred: one full pass over every battler).
; Entry: M=1, X=0, DP=0, DB=$7E; TAX of the slot also copies B, assumed 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; !Battle_TickSlot = 11
;        and the callees' DP scratch written
; Callees: Battle_PickStatusAnim, Battle_ApplyPendingEffect
Battle_PickNextStatusAnim:
    LDA.w !Battle_StatusAnimNext
    TAX
    STX.b !Battle_TickSlot
    LDA.w !Battler_Present,X
    BEQ .advance
    JSR Battle_PickStatusAnim
.advance:
    INC.w !Battle_StatusAnimNext
    LDA.w !Battle_StatusAnimNext
    CMP.b #!Battle_NumSlots
    BNE .apply
    INC.w !Battle_StatusAnimWraps
    LDA.b #!Battle_FirstEnemySlot
    STA.w !Battle_StatusAnimNext
.apply:
    TDC
    TAX
    STX.b !Battle_TickSlot
.apply_loop:
    JSR Battle_ApplyPendingEffect
    INC.b !Battle_TickSlot
    LDA.b !Battle_TickSlot
    CMP.b #!Battle_NumSlots
    BNE .apply_loop
    RTS

; ==================================================================
; Battle_ApplyPendingEffect ($C1308C–$C130B5, 42 bytes)
; ==================================================================
; For battler !Battle_TickSlot, if present: when the effect picked
; (!Battler_FxWanted) differs from the one running (!Battler_FxApplied),
; records it, stops the overlay and the colour cycle, clears
; !Battler_KoFlag and runs the effect's entry of Battle_FxHandlerTable.
; A negative effect ($FF none, $80 from the Unk2F path) runs entry 0,
; Battle_FxReset.
; Callers (JSR; scanned as above): Battle_TickPcSlots,
; Battle_PickNextStatusAnim.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_TickSlot; the TAX of the table
;        index also copies B, assumed 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered (and DP $80 by
;        Battle_FxOverlay2Tint)
; Callees: JSR (Battle_FxHandlerTable,X)
Battle_ApplyPendingEffect:
    LDX.b !Battle_TickSlot
    LDA.w !Battler_Present,X
    BEQ .exit
    LDA.w !Battler_FxWanted,X
    CMP.w !Battler_FxApplied,X
    BEQ .exit
    STA.w !Battler_FxApplied,X
    STZ.w !Battler_FxOverlayOn,X
    STZ.w !Battler_FxCycleStep,X
    STZ.w !Battler_KoFlag,X
    STZ.w !Battler_FxCycleOn,X
    LDA.w !Battler_FxWanted,X
    BPL .run
    TDC                             ; none / Unk2F: entry 0
.run:
    ASL A
    TAX
    JSR (Battle_FxHandlerTable,X)
.exit:
    RTS

; ==================================================================
; Status effect handlers ($C1:30B6–$C1:3233)
; ==================================================================
; Each handler sets up the visuals of one effect for battler
; !Battle_TickSlot. Two mechanisms are started here and run elsewhere:
;   - an overlay (!Battler_FxOverlayOn): frame !Battler_FxOverlayFrame
;     (0-3, $FF = before the first) steps every !Battler_FxOverlayPeriod
;     frames (counted in !Battler_FxOverlayTimer), from frame block
;     !Battler_FxOverlayBase of the table at $CC:F6D4 (code at $CF:EE38);
;   - a colour cycle (!Battler_FxCycleOn): colours from $CE:0100 by
;     !Battler_FxCycleStep, written into the battler's live palette
;     (code at $CF:E7E0).
; Overlay block n ($10 * n) has its period in !BattleRom_FxOverlayPeriod
; entry n-1. The "overlay" and "colour cycle" readings come from that
; code in bank $CF, which is not matched; what each overlay looks like
; has not been checked.
; Entry (all): M=1, X=0, DP=0, DB=$7E; !Battle_TickSlot
; Exit (all):  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered

; Battle_FxReset ($C130B6–$C130E0, 43 bytes)
; Effect 0 (none): clears the battler's effect flags; for a PC also
; copies the saved palette (!Battle_PaletteSaved, 26 bytes from
; !Battler_Palette * 16) back over the live one, undoing a tint or
; colour cycle.
; Callers (8 JSR sites): Battle_FxHandlerTable entry 0; the handlers
;   Battle_FxOverlay2Tint ($C1:30E1), Battle_FxOverlay7 ($C1:3141),
;   Battle_FxOverlay6 ($C1:3163), Battle_FxColourCycle ($C1:3185),
;   Battle_FxOverlay3 ($C1:31B0), Battle_FxOverlay4 ($C1:31D2) and
;   Battle_FxOverlay5 ($C1:31F4); and BattleSys_VictoryPose ($C1:3582).
; The ×16 shift runs on an 8-bit A; the TAY also copies B, assumed 0.
Battle_FxReset:
    LDX.b !Battle_TickSlot
    STZ.w !Battler_UnkA483,X
    STZ.w !Battler_FxOverlayOn,X
    STZ.w !Battler_UnkA457,X
    STZ.w !Battler_FxCycleOn,X
    STZ.w !Battler_FxTinted,X
    CPX.w #!Battle_NumPcSlots
    BCS .exit
    LDA.w !Battler_Palette,X
    JSR Battle_ShiftLeft4
    TAY
    LDX.w #!Battle_PaletteCopyLen
.copy:
    LDA.w !Battle_PaletteSaved,Y
    STA.w !Battle_PaletteLive,Y
    INY
    DEX
    BNE .copy
.exit:
    RTS

; Battle_FxOverlay2Tint ($C130E1–$C13140, 96 bytes)
; Effect 3: resets, starts overlay 2 and marks the battler tinted
; (!Battler_FxTinted); for a PC also restores the saved palette from
; byte 2 on (24 bytes) and then writes the 4 bytes at
; !BattleRom_FxTintColours into live palette bytes 6-9 (inferred: two
; colours).
; Callers: Battle_FxHandlerTable entry 3.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_TickSlot (read 16-bit)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X clobbered; for a PC, Y clobbered
;        and DP $80-$81 written (!Battle_FxPalOffset)
!Battle_FxPalOffset = !BattleTmp_80       ; 2 B: !Battler_Palette * 16
Battle_FxOverlay2Tint:
    JSR Battle_FxReset
    LDX.b !Battle_TickSlot
    INC.w !Battler_FxOverlayOn,X
    STZ.w !Battler_FxCycleStep,X
    LDA.b #!Battle_FxOverlayFrameStart
    STA.w !Battler_FxOverlayFrame,X
    LDA.b #!Battle_FxOverlayStride*2
    STA.w !Battler_FxOverlayBase,X
    LDA.b #1
    STA.w !Battler_FxOverlayTimer,X
    LDA.l !BattleRom_FxOverlayPeriod+1
    STA.w !Battler_FxOverlayPeriod,X
    LDX.b !Battle_TickSlot
    INC.w !Battler_FxTinted,X
    CPX.w #!Battle_NumPcSlots
    BCS .exit
    LDA.w !Battler_Palette,X
    JSR Battle_ShiftLeft4
    TAY
    STY.b !Battle_FxPalOffset
    LDX.w #!Battle_PaletteTintCopyLen
.copy:
    LDA.w !Battle_PaletteSaved+2,Y
    STA.w !Battle_PaletteLive+2,Y
    INY
    DEX
    BNE .copy
    LDY.b !Battle_FxPalOffset
    LDA.l !BattleRom_FxTintColours
    STA.w !Battle_PaletteLive+6,Y
    LDA.l !BattleRom_FxTintColours+1
    STA.w !Battle_PaletteLive+7,Y
    LDA.l !BattleRom_FxTintColours+2
    STA.w !Battle_PaletteLive+8,Y
    LDA.l !BattleRom_FxTintColours+3
    STA.w !Battle_PaletteLive+9,Y
.exit:
    RTS

; Battle_FxOverlay7 ($C13141–$C13162, 34 bytes)
; Effect $0E: resets and starts overlay 7.
; Callers: Battle_FxHandlerTable entry $0E.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_TickSlot (read 16-bit)
; Exit:  M=1, X=0, DP=0, DB=$7E; A clobbered; X = !Battle_TickSlot; Y
;        clobbered for a PC (by Battle_FxReset)
Battle_FxOverlay7:
    JSR Battle_FxReset
    LDX.b !Battle_TickSlot
    INC.w !Battler_FxOverlayOn,X
    STZ.w !Battler_FxCycleStep,X
    LDA.b #!Battle_FxOverlayFrameStart
    STA.w !Battler_FxOverlayFrame,X
    LDA.b #!Battle_FxOverlayStride*7
    STA.w !Battler_FxOverlayBase,X
    LDA.b #1
    STA.w !Battler_FxOverlayTimer,X
    LDA.l !BattleRom_FxOverlayPeriod+6
    STA.w !Battler_FxOverlayPeriod,X
    RTS

; Battle_FxOverlay6 ($C13163–$C13184, 34 bytes)
; Effect 9: resets and starts overlay 6.
; Callers: Battle_FxHandlerTable entry 9.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_TickSlot (read 16-bit)
; Exit:  M=1, X=0, DP=0, DB=$7E; A clobbered; X = !Battle_TickSlot; Y
;        clobbered for a PC (by Battle_FxReset)
Battle_FxOverlay6:
    JSR Battle_FxReset
    LDX.b !Battle_TickSlot
    INC.w !Battler_FxOverlayOn,X
    STZ.w !Battler_FxCycleStep,X
    LDA.b #!Battle_FxOverlayFrameStart
    STA.w !Battler_FxOverlayFrame,X
    LDA.b #!Battle_FxOverlayStride*6
    STA.w !Battler_FxOverlayBase,X
    LDA.b #1
    STA.w !Battler_FxOverlayTimer,X
    LDA.l !BattleRom_FxOverlayPeriod+5
    STA.w !Battler_FxOverlayPeriod,X
    RTS

; Battle_FxColourCycle ($C13185–$C13190, 12 bytes)
; Effects 6, 7, $0B, $0C and $0D: resets and starts the colour cycle
; from step 0.
; Callers: Battle_FxHandlerTable entries 6, 7, $0B, $0C, $0D.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_TickSlot (read 16-bit)
; Exit:  M=1, X=0, DP=0, DB=$7E; A clobbered; X = !Battle_TickSlot; Y
;        clobbered for a PC (by Battle_FxReset)
Battle_FxColourCycle:
    JSR Battle_FxReset
    LDX.b !Battle_TickSlot
    INC.w !Battler_FxCycleOn,X
    STZ.w !Battler_FxCycleStep,X
    RTS

; Battle_FxOverlay1 ($C13191–$C131AF, 31 bytes)
; Effects 1, 2 and $0A: starts overlay 1. Unlike every other handler
; it does not run Battle_FxReset first, so the previous effect's tint
; (palette bytes and !Battler_FxTinted) and the Unk A457/A483 flags
; stay as they were (kept as found; whether that shows in play is not
; traced).
; Callers: Battle_FxHandlerTable entries 1, 2, $0A.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_TickSlot (read 16-bit)
; Exit:  M=1, X=0, DP=0, DB=$7E; A clobbered; X = !Battle_TickSlot; Y
;        unchanged
Battle_FxOverlay1:
    LDX.b !Battle_TickSlot
    INC.w !Battler_FxOverlayOn,X
    STZ.w !Battler_FxCycleStep,X
    LDA.b #!Battle_FxOverlayFrameStart
    STA.w !Battler_FxOverlayFrame,X
    LDA.b #!Battle_FxOverlayStride*1
    STA.w !Battler_FxOverlayBase,X
    LDA.b #1
    STA.w !Battler_FxOverlayTimer,X
    LDA.l !BattleRom_FxOverlayPeriod
    STA.w !Battler_FxOverlayPeriod,X
    RTS

; Battle_FxOverlay3 ($C131B0–$C131D1, 34 bytes)
; Effect 4: resets and starts overlay 3.
; Callers: Battle_FxHandlerTable entry 4.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_TickSlot (read 16-bit)
; Exit:  M=1, X=0, DP=0, DB=$7E; A clobbered; X = !Battle_TickSlot; Y
;        clobbered for a PC (by Battle_FxReset)
Battle_FxOverlay3:
    JSR Battle_FxReset
    LDX.b !Battle_TickSlot
    INC.w !Battler_FxOverlayOn,X
    STZ.w !Battler_FxCycleStep,X
    LDA.b #!Battle_FxOverlayFrameStart
    STA.w !Battler_FxOverlayFrame,X
    LDA.b #!Battle_FxOverlayStride*3
    STA.w !Battler_FxOverlayBase,X
    LDA.b #1
    STA.w !Battler_FxOverlayTimer,X
    LDA.l !BattleRom_FxOverlayPeriod+2
    STA.w !Battler_FxOverlayPeriod,X
    RTS

; Battle_FxOverlay4 ($C131D2–$C131F3, 34 bytes)
; Effect 5: resets and starts overlay 4.
; Callers: Battle_FxHandlerTable entry 5.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_TickSlot (read 16-bit)
; Exit:  M=1, X=0, DP=0, DB=$7E; A clobbered; X = !Battle_TickSlot; Y
;        clobbered for a PC (by Battle_FxReset)
Battle_FxOverlay4:
    JSR Battle_FxReset
    LDX.b !Battle_TickSlot
    INC.w !Battler_FxOverlayOn,X
    STZ.w !Battler_FxCycleStep,X
    LDA.b #!Battle_FxOverlayFrameStart
    STA.w !Battler_FxOverlayFrame,X
    LDA.b #!Battle_FxOverlayStride*4
    STA.w !Battler_FxOverlayBase,X
    LDA.b #1
    STA.w !Battler_FxOverlayTimer,X
    LDA.l !BattleRom_FxOverlayPeriod+3
    STA.w !Battler_FxOverlayPeriod,X
    RTS

; Battle_FxOverlay5 ($C131F4–$C13215, 34 bytes)
; Effect 8: resets and starts overlay 5.
; Callers: Battle_FxHandlerTable entry 8.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_TickSlot (read 16-bit)
; Exit:  M=1, X=0, DP=0, DB=$7E; A clobbered; X = !Battle_TickSlot; Y
;        clobbered for a PC (by Battle_FxReset)
Battle_FxOverlay5:
    JSR Battle_FxReset
    LDX.b !Battle_TickSlot
    INC.w !Battler_FxOverlayOn,X
    STZ.w !Battler_FxCycleStep,X
    LDA.b #!Battle_FxOverlayFrameStart
    STA.w !Battler_FxOverlayFrame,X
    LDA.b #!Battle_FxOverlayStride*5
    STA.w !Battler_FxOverlayBase,X
    LDA.b #1
    STA.w !Battler_FxOverlayTimer,X
    LDA.l !BattleRom_FxOverlayPeriod+4
    STA.w !Battler_FxOverlayPeriod,X
    RTS

; Battle_FxHandlerTable ($C13216–$C13233, 30 bytes)
; One handler per status effect id 0-$0E, called from
; Battle_ApplyPendingEffect.
Battle_FxHandlerTable:
    dw Battle_FxReset               ; $00 none
    dw Battle_FxOverlay1            ; $01
    dw Battle_FxOverlay1            ; $02
    dw Battle_FxOverlay2Tint        ; $03
    dw Battle_FxOverlay3            ; $04
    dw Battle_FxOverlay4            ; $05
    dw Battle_FxColourCycle         ; $06
    dw Battle_FxColourCycle         ; $07
    dw Battle_FxOverlay5            ; $08
    dw Battle_FxOverlay6            ; $09
    dw Battle_FxOverlay1            ; $0A
    dw Battle_FxColourCycle         ; $0B
    dw Battle_FxColourCycle         ; $0C
    dw Battle_FxColourCycle         ; $0D
    dw Battle_FxOverlay7            ; $0E

; ==================================================================
; Enemy animation tick ($C1:3234–$C1:34DA)
; ==================================================================

; ==================================================================
; Battle_TickEnemyGroup ($C13234–$C134A6, 627 bytes)
; ==================================================================
; The enemy counterpart of Battle_TickPcSlots, which jumps here instead
; of ticking the PCs while !Battle_UnkA4 is 1-3 (A = that value). Value
; n picks a group of enemies: 1 = enemies 0-2, 2 = enemies 3-5, 3 =
; enemies 6-7. The group's members go into !Battle_TickOrder, starting
; with the first whose frame decode was put off (!Battler_FrameDeferred
; of slot 3 + enemy; $FF fills the unused third entry of group 3). For
; each present enemy:
;   - when !Enemy_AnimWanted or the facing (!Battler_Facing) changed,
;     reloads its lists: from the battler's long pointers
;     !Battler_AnimDurBase / !Battler_AnimFrameBase it copies 8 frame
;     ids (offset list * 4 + Facing * FacingStride) into
;     !Enemy_AnimFrames and 8 durations (offset list * 4), each turned
;     into frames by !BattleRom_Div5, into !Enemy_AnimTicks. The list is
;     picked by !BattleRom_EnemyAnimKind[animation]: kind 0 = list 3,
;     kind 1 = list 1 (and clears !Enemy_MoveDone), other kinds = list 6;
;   - counts down !Enemy_AnimTimer; at 0 it shows the current frame
;     (Battle_DrawBattlerFrame, layouts 0-2 only), moves
;     !Enemy_AnimFrame on (wrapping at 4, or to 0 at a 0 tick count) and
;     reloads the timer from the new entry's ticks. When a frame was
;     already decoded this pass (!Battle_FramesDecoded) the step is put
;     off instead: the enemy is marked deferred and its timer set back
;     to 1. With exactly one decode done and frame layout 0, slots 4
;     and 6-10 still draw and slots 3 and 5 wait; why is not known.
; Finally !Battle_UnkA4, decremented on the way in, is incremented again
; when it differs from !Battle_Unk993B (the copy
; BattleSys_UpkeepTwoFrames took before the tick) and is below 3; as the
; code stands the two cancel, so the group is not advanced here (what
; else writes $A4 is not traced).
; Quirks, kept as found: the lists are copied 8 entries long, but the
; frame index wraps at 4, so entries 4-7 are never shown by this
; routine; durations 0-4 become 0 ticks through the /5 table, which here
; ends the list (the PC tick only ends at a 0 byte and keeps 1 as the
; minimum); group 3 ends with a JMP to the very next instruction.
; "Group" and the enemy reading come from the index arithmetic
; (slot = enemy + 3, 3-byte pointer arrays indexed at +9); the meaning of
; the list numbers and of the kind table is not established.
; Callers (JMP; scanned for JSR/JSL/JML/JMP/BRL and word tables, hits
; inside other instructions discarded): Battle_TickPcSlots only. The
; final RTS (.exit) is also the target of Battle_UnkThunk2F1F.
; Entry: M=1, X=0, DP=0, DB=$7E; A = !Battle_UnkA4
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $80-$86, $9C and
;        $C0-$C5 written, plus the callees' scratch
; Callees: Battle_Mul8x16, Battle_ShiftLeft3, Battle_DrawBattlerFrame
!Battle_EnemyIdx = !BattleTmp_9C          ; 2 B: enemy being ticked (0-7; slot = enemy + 3)
!Battle_EnemyFrameSrc = !BattleTmp_C0     ; 3 B: long pointer to the enemy's frame-id lists
!Battle_EnemyTicksSrc = !BattleTmp_C3     ; 3 B: long pointer to its duration lists
!Battle_EnemyListOfs = !BattleTmp_86      ; 1 B: list number * 4 (offset of the duration list)
!Battle_EnemyFrameOfs = !BattleTmp_82     ; 2 B: list number * 4 + Facing * FacingStride
!Battle_EnemyCopyLeft = !BattleTmp_80     ; 1 B: entries left to copy
!Battle_EnemyListBase = !BattleTmp_80     ; 1 B: enemy * 8, its block in !Enemy_AnimTicks/Frames
!Battle_EnemyCopyDest = !BattleTmp_84     ; 2 B: index into !Enemy_AnimTicks being written
Battle_TickEnemyGroup:
    STZ.w !Battle_EnemyTickIdx
    DEC A
    BNE .not_group1
    DEC.b !Battle_UnkA4
    JMP .group1
.not_group1:
    DEC A
    BNE .not_group2
    DEC.b !Battle_UnkA4
    JMP .group2
.not_group2:
    DEC A
    BNE .no_group
    DEC.b !Battle_UnkA4
    JMP .group3
.no_group:
    JMP .exit
.group1:
    LDA.w !Battler_FrameDeferred+!Battle_FirstEnemySlot
    BEQ .g1_enemy1
    STZ.w !Battler_FrameDeferred+!Battle_FirstEnemySlot
    TDC
    STA.w !Battle_TickOrder         ; 0, 1, 2
    INC A
    STA.w !Battle_TickOrder+1
    INC A
    STA.w !Battle_TickOrder+2
    BRA .g1_done
.g1_enemy1:
    LDA.w !Battler_FrameDeferred+!Battle_FirstEnemySlot+1
    BEQ .g1_enemy2
    STZ.w !Battler_FrameDeferred+!Battle_FirstEnemySlot+1
    LDA.b #1
    STA.w !Battle_TickOrder         ; 1, 2, 0
    INC A
    STA.w !Battle_TickOrder+1
    TDC
    STA.w !Battle_TickOrder+2
    BRA .g1_done
.g1_enemy2:
    LDA.w !Battler_FrameDeferred+!Battle_FirstEnemySlot+2
    BEQ .g1_none
    STZ.w !Battler_FrameDeferred+!Battle_FirstEnemySlot+2
    LDA.b #2
    STA.w !Battle_TickOrder         ; 2, 0, 1
    TDC
    STA.w !Battle_TickOrder+1
    INC A
    STA.w !Battle_TickOrder+2
    BRA .g1_done
.g1_none:
    TDC
    STA.w !Battle_TickOrder         ; 0, 1, 2
    INC A
    STA.w !Battle_TickOrder+1
    INC A
    STA.w !Battle_TickOrder+2
.g1_done:
    JMP .tick
.group2:
    LDA.w !Battler_FrameDeferred+!Battle_FirstEnemySlot+3
    BEQ .g2_enemy4
    STZ.w !Battler_FrameDeferred+!Battle_FirstEnemySlot+3
    LDA.b #3
    STA.w !Battle_TickOrder         ; 3, 4, 5
    INC A
    STA.w !Battle_TickOrder+1
    INC A
    STA.w !Battle_TickOrder+2
    BRA .g2_done
.g2_enemy4:
    LDA.w !Battler_FrameDeferred+!Battle_FirstEnemySlot+4
    BEQ .g2_enemy5
    STZ.w !Battler_FrameDeferred+!Battle_FirstEnemySlot+4
    LDA.b #4
    STA.w !Battle_TickOrder         ; 4, 5, 3
    INC A
    STA.w !Battle_TickOrder+1
    LDA.b #3
    STA.w !Battle_TickOrder+2
    BRA .g2_done
.g2_enemy5:
    LDA.w !Battler_FrameDeferred+!Battle_FirstEnemySlot+5
    BEQ .g2_none
    STZ.w !Battler_FrameDeferred+!Battle_FirstEnemySlot+5
    LDA.b #5
    STA.w !Battle_TickOrder         ; 5, 3, 4
    LDA.b #3
    STA.w !Battle_TickOrder+1
    INC A
    STA.w !Battle_TickOrder+2
    BRA .g2_done
.g2_none:
    LDA.b #3
    STA.w !Battle_TickOrder         ; 3, 4, 5
    INC A
    STA.w !Battle_TickOrder+1
    INC A
    STA.w !Battle_TickOrder+2
.g2_done:
    JMP .tick
.group3:
    LDA.w !Battler_FrameDeferred+!Battle_FirstEnemySlot+6
    BEQ .g3_enemy7
    STZ.w !Battler_FrameDeferred+!Battle_FirstEnemySlot+6
    LDA.b #6
    STA.w !Battle_TickOrder         ; 6, 7, none
    INC A
    STA.w !Battle_TickOrder+1
    LDA.b #!Battle_TickOrderNone
    STA.w !Battle_TickOrder+2
    BRA .g3_done
.g3_enemy7:
    LDA.w !Battler_FrameDeferred+!Battle_FirstEnemySlot+7
    BEQ .g3_none
    STZ.w !Battler_FrameDeferred+!Battle_FirstEnemySlot+7
    LDA.b #7
    STA.w !Battle_TickOrder         ; 7, 6, none
    DEC A
    STA.w !Battle_TickOrder+1
    LDA.b #!Battle_TickOrderNone
    STA.w !Battle_TickOrder+2
    BRA .g3_done
.g3_none:
    LDA.b #6
    STA.w !Battle_TickOrder         ; 6, 7, none
    INC A
    STA.w !Battle_TickOrder+1
    LDA.b #!Battle_TickOrderNone
    STA.w !Battle_TickOrder+2
.g3_done:
    JMP .tick                       ; quirk: the next instruction
.tick:
    LDA.w !Battle_EnemyTickIdx
    TAX
    LDA.w !Battle_TickOrder,X
    BMI .skip
    TAX
    STX.b !Battle_EnemyIdx
    LDA.w !Battler_Present+!Battle_FirstEnemySlot,X
    BNE .present
.skip:
    JMP .next
.present:
    LDA.w !Enemy_Anim,X
    CMP.w !Enemy_AnimWanted,X
    BNE .reload
    LDA.w !Battler_Facing+!Battle_FirstEnemySlot,X
    CMP.w !Enemy_FacingShown,X
    BNE .reload
    JMP .count_down
.reload:
    LDA.w !Enemy_AnimWanted,X
    STA.w !Enemy_Anim,X
    LDA.w !Battler_Facing+!Battle_FirstEnemySlot,X
    STA.w !Enemy_FacingShown,X
    TXA
    ASL A
    CLC
    ADC.b !Battle_EnemyIdx
    TAX                             ; enemy * 3 (+9 below: its slot's pointers)
    LDA.w !Battler_AnimDurBase+(!Battle_FirstEnemySlot*3),X
    STA.b !Battle_EnemyTicksSrc
    LDA.w !Battler_AnimDurBase+(!Battle_FirstEnemySlot*3)+1,X
    STA.b !Battle_EnemyTicksSrc+1
    LDA.w !Battler_AnimDurBase+(!Battle_FirstEnemySlot*3)+2,X
    STA.b !Battle_EnemyTicksSrc+2
    LDA.w !Battler_AnimFrameBase+(!Battle_FirstEnemySlot*3),X
    STA.b !Battle_EnemyFrameSrc
    LDA.w !Battler_AnimFrameBase+(!Battle_FirstEnemySlot*3)+1,X
    STA.b !Battle_EnemyFrameSrc+1
    LDA.w !Battler_AnimFrameBase+(!Battle_FirstEnemySlot*3)+2,X
    STA.b !Battle_EnemyFrameSrc+2
    LDX.b !Battle_EnemyIdx
    LDA.w !Battler_Facing+!Battle_FirstEnemySlot,X
    STA.b !Battle_MulFactor8
    LDA.w !Battler_FacingStrideLo+!Battle_FirstEnemySlot,X
    STA.b !Battle_MulFactor16
    LDA.w !Battler_FacingStrideHi+!Battle_FirstEnemySlot,X
    STA.b !Battle_MulFactor16+1
    JSR Battle_Mul8x16
    LDX.b !Battle_EnemyIdx
    LDA.w !Enemy_Anim,X
    TAX
    LDA.l !BattleRom_EnemyAnimKind,X
    BNE .kind_not0
    LDA.b #!Battle_AnimDefault*4    ; kind 0: list 3
    BRA .set_list
.kind_not0:
    DEC A
    BNE .kind_other
    LDX.b !Battle_EnemyIdx
    STZ.w !Enemy_MoveDone,X
    LDA.b #!Battle_EnemyListKind1*4 ; kind 1: list 1
    BRA .set_list
.kind_other:
    LDA.b #!Battle_EnemyListOther*4 ; other kinds: list 6
.set_list:
    STA.b !Battle_EnemyListOfs
    REP #$21                        ; A -> 16-bit, carry clear
    ADC.b !Battle_MulProduct
    STA.b !Battle_EnemyFrameOfs
    TDC
    SEP #$20                        ; A -> 8-bit
    LDA.b #!Battle_EnemyAnimListLen
    STA.b !Battle_EnemyCopyLeft
    LDX.b !Battle_EnemyIdx
    LDA.l !BattleRom_EnemyListOffset,X
    TAX
    PHX
    LDY.b !Battle_EnemyFrameOfs
.copy_frames:
    LDA.b [!Battle_EnemyFrameSrc],Y
    STA.w !Enemy_AnimFrames,X
    INY
    INX
    DEC.b !Battle_EnemyCopyLeft
    BNE .copy_frames
    LDA.b #!Battle_EnemyAnimListLen
    STA.b !Battle_EnemyCopyLeft
    PLX
    STX.b !Battle_EnemyCopyDest
    LDA.b !Battle_EnemyListOfs
    TAY
.copy_ticks:
    LDA.b [!Battle_EnemyTicksSrc],Y
    TAX
    LDA.l !BattleRom_Div5,X         ; duration byte -> frames
    LDX.b !Battle_EnemyCopyDest
    STA.w !Enemy_AnimTicks,X
    INY
    INC.b !Battle_EnemyCopyDest
    DEC.b !Battle_EnemyCopyLeft
    BNE .copy_ticks
.count_down:
    LDX.b !Battle_EnemyIdx
    DEC.w !Enemy_AnimTimer,X
    BNE .next
    LDA.b !Battle_EnemyIdx
    JSR Battle_ShiftLeft3
    STA.b !Battle_EnemyListBase
    CLC
    ADC.w !Enemy_AnimFrame,X
    TAY
    LDA.w !Enemy_AnimTicks,Y
    BNE .frame
    STZ.w !Enemy_AnimFrame,X        ; end of the list: back to entry 0
    LDA.b !Battle_EnemyListBase
    TAY
.frame:
    LDA.w !Enemy_AnimFrames,Y
    STA.w !Battle_FrameId
    CLC
    LDA.b !Battle_EnemyIdx
    ADC.b #!Battle_FirstEnemySlot
    STA.w !Battle_FrameSlot
    TAX                             ; X = battler slot
    LDA.w !Battle_FramesDecoded
    BEQ .draw
    DEC A
    BNE .defer
    LDA.w !Battler_FrameLayout,X
    BNE .defer
    LDA.w !Battle_FrameSlot
    CMP.b #!Battle_FirstEnemySlot+1
    BEQ .draw                       ; slot 4
    CMP.b #!Battle_FirstEnemySlot+3
    BCS .draw                       ; slots 6-10
.defer:
    INC.w !Battler_FrameDeferred,X
    LDX.b !Battle_EnemyIdx
    INC.w !Enemy_AnimTimer,X        ; try again next time
    BRA .next
.draw:
    LDA.w !Battler_FrameLayout,X
    CMP.b #!Battle_FrameLayoutStrip
    BCS .advance
    JSR Battle_DrawBattlerFrame
.advance:
    LDX.b !Battle_EnemyIdx
    INC.w !Enemy_AnimFrame,X
    LDA.w !Enemy_AnimFrame,X
    CMP.b #!Battle_EnemyAnimFrames
    BNE .in_range
    STZ.w !Enemy_AnimFrame,X
.in_range:
    LDA.b !Battle_EnemyIdx
    JSR Battle_ShiftLeft3
    STA.b !Battle_EnemyListBase
    CLC
    ADC.w !Enemy_AnimFrame,X
    TAY
    LDA.w !Enemy_AnimTicks,Y
    BNE .set_timer
    STZ.w !Enemy_AnimFrame,X
    LDA.b !Battle_EnemyListBase
    TAY
    LDA.w !Enemy_AnimTicks,Y
.set_timer:
    STA.w !Enemy_AnimTimer,X
.next:
    INC.w !Battle_EnemyTickIdx
    LDA.w !Battle_EnemyTickIdx
    CMP.b #!Battle_EnemyGroupSize
    BEQ .group_done
    JMP .tick
.group_done:
    LDA.b !Battle_UnkA4
    CMP.w !Battle_Unk993B
    BEQ .exit
    CMP.b #!Battle_EnemyGroupLast
    BCS .exit
    INC.b !Battle_UnkA4             ; (undoes the DEC above; see header)
.exit:
    RTS

; ==================================================================
; Battle_DrawAllBattlerFrames ($C134A7–$C134DA, 52 bytes)
; ==================================================================
; Draws the starting frame (!Battler_StartFrame) of every present
; battler, any frame layout (Battle_DrawBattlerFrameAnyLayout), then sets
; the three PC animation timers to 1, 2 and 3 so the PCs take their first
; steps on different frames (inferred from Battle_TickPcSlots, which
; counts them down).
; !Pc_AnimTimer serves as the loop counter (16-bit store, 8-bit count)
; before it gets those values.
; Callers (JSR; scanned as above): the battle set-up of service 0 at
; $C1:0031 only.
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 3; X, Y and the decoder's scratch
;        clobbered
; Callees: Battle_DrawBattlerFrameAnyLayout
Battle_DrawAllBattlerFrames:
    TDC
    TAX
    STX.w !Pc_AnimTimer             ; loop counter (slot)
.loop:
    LDX.w !Pc_AnimTimer
    LDA.w !Battler_Present,X
    BEQ .next
    LDA.w !Pc_AnimTimer
    STA.w !Battle_FrameSlot
    LDA.w !Battler_StartFrame,X
    STA.w !Battle_FrameId
    JSR Battle_DrawBattlerFrameAnyLayout
.next:
    INC.w !Pc_AnimTimer
    LDA.w !Pc_AnimTimer
    CMP.b #!Battle_NumSlots
    BNE .loop
    LDA.b #1
    STA.w !Pc_AnimTimer             ; PC timers 1, 2, 3
    INC A
    STA.w !Pc_AnimTimer+1
    INC A
    STA.w !Pc_AnimTimer+2
    RTS

; ==================================================================
; PC poses: battle start, services 8 and 9 ($C1:34DB–$C1:3713)
; ==================================================================
; A pose plays one animation list on all three PCs for 64 frames
; (Battle_RunPcPose). Each PC's list is chosen by !Pc_PoseListOfs, an
; offset (animation * 4) into its lists in bank $E4, the same layout
; Battle_TickPcSlots steps through.

; ==================================================================
; Battle_StartPose ($C134DB–$C1350E, 52 bytes)
; ==================================================================
; The last step of the battle set-up (service 0, which JMPs here): turns
; every PC toward its nearest enemy, then plays animation $0C on the
; targetable PCs (animation 0 on the others) through Battle_RunPcPose,
; with !Battle_PoseUnk5DDD set and KO'd PCs left out. That this is the
; PCs' entry into battle is inferred from where it runs.
; Callers (JMP; scanned for JSR/JSL/JML/JMP/BRL and word tables, hits
; inside other instructions discarded): service 0 at $C1:0042 only.
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  as Battle_RunPcPose
; Callees: Battle_FaceAllPcsNearestEnemy, Battle_RunPcPose (JMP)
Battle_StartPose:
    JSR Battle_FaceAllPcsNearestEnemy
    LDX.w #!Battle_LastPcSlot
    LDY.w #!Battle_LastPcSlot*2
.slot:
    LDA.w !Battler_Untargetable,X
    BEQ .targetable
    LDA.b #!Battle_AnimUntargetable*4
    STA.w !Pc_PoseListOfs,Y
    LDA.b #0
    STA.w !Pc_PoseListOfs+1,Y
    BRA .next
.targetable:
    LDA.b #!Battle_AnimUnk0C*4
    STA.w !Pc_PoseListOfs,Y
    LDA.b #0
    STA.w !Pc_PoseListOfs+1,Y
.next:
    DEY
    DEY
    DEX
    BPL .slot
    LDA.b #1
    STA.w !Battle_PoseUnk5DDD
    STZ.w !Battle_PoseIncludeKo
    JMP Battle_RunPcPose

; ==================================================================
; Battle_FaceAllPcsNearestEnemy ($C1350F–$C1354C, 62 bytes)
; ==================================================================
; Sets !Battler_Facing of PCs 2, 1, 0 from the angle to each one's
; nearest enemy (position query 2 through service 5, as in
; Battle_UpdatePcFacing, but for every PC at once and without the
; presence, KO, Status2 and turn checks, and without updating
; !Pc_FacingTarget). The query mode is set once; the value 2 also serves
; as the first PC slot of the loop. Assumes the query leaves
; !BattlePos_Mode alone (it is not written by BattlePos_Query).
; Callers (JSR; scanned as above): Battle_StartPose only.
; Entry: M=1, X=0, DP=0, DB=$7E; the TAX of the found enemy and of the
;        angle also copy B, assumed 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; !Battle_TickSlot =
;        low byte $FF, and the query's and Battle_CalcAngle's
;        scratch written
; Callees: BattleSys_RunService (service 5), Battle_CalcAngle
Battle_FaceAllPcsNearestEnemy:
    LDA.b #!BattlePos_QueryNearestEnemy
    STA.w !BattlePos_Mode
    TAX                             ; 2: also the last PC slot
    STX.b !Battle_TickSlot
.slot:
    LDA.b !Battle_TickSlot
    STA.w !BattlePos_Subject
    LDA.b #!BattleSys_ServicePosQuery
    JSR BattleSys_RunService
    LDX.b !Battle_TickSlot
    LDA.w !Battler_ScreenX,X
    STA.b !Battle_GeoOriginX
    LDA.w !Battler_ScreenY,X
    STA.b !Battle_GeoOriginY
    LDA.w !BattlePos_Found
    TAX
    LDA.w !Battler_ScreenX,X
    STA.b !Battle_GeoPointX
    LDA.w !Battler_ScreenY,X
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    LDX.b !Battle_TickSlot
    STA.w !Battler_Facing,X
    DEC.b !Battle_TickSlot
    BPL .slot
    RTS

; ==================================================================
; BattleSys_DefeatPose ($C1354D–$C1356C, 32 bytes)
; ==================================================================
; Service 9 of the same-bank $C10045 service dispatcher (reached only
; by JSR $0003/$0045 inside bank $C1; returns RTS; dispatch table at
; $C10051, entry 9 = $354D; no JSR, JMP or JSL reaches $354D directly).
; Ticks the frame service, counts !Battle_UnkA0FE up, waits a frame and
; plays animation 8 on all three PCs, KO'd ones included
; (!Battle_PoseIncludeKo). Animation 8 is the one BattleRom_StatusAnim
; gives a KO'd battler; the "defeat" reading is inferred from that and
; from the caller (the unmatched code at $C1:815F, which first runs
; service 3 eight times with !Battle_UnkA10E set).
; Entry: M=1, X=0, DP=0, DB=$7E (through the dispatcher, which saves A,
;        X and Y around the call)
; Exit:  as Battle_RunPcPose
; Callees: BattleSys_FrameTickVec, BattleSys_PumpFrames,
;          Battle_RunPcPose (BRA)
BattleSys_DefeatPose:
    JSL BattleSys_FrameTickVec
    INC.w !Battle_UnkA0FE
    JSR BattleSys_PumpFrames
    LDX.w #!Battle_AnimDown*4
    STX.w !Pc_PoseListOfs           ; all three PCs
    STX.w !Pc_PoseListOfs+2
    STX.w !Pc_PoseListOfs+4
    STZ.w !Battle_PoseUnk5DDD
    LDA.b #1
    STA.w !Battle_PoseIncludeKo
    BRA Battle_RunPcPose

; ==================================================================
; BattleSys_VictoryPose ($C1356D–$C135DC, 112 bytes)
; ==================================================================
; Service 8 of the same-bank $C10045 service dispatcher (reached only
; by JSR $0003/$0045 inside bank $C1; returns RTS; dispatch table at
; $C10051, entry 8 = $356D; no JSR, JMP or JSL reaches $356D directly).
; Ticks the frame service, counts !Battle_UnkA0FE up, clears
; !Enemy_Stepping, stops the PCs' status effects (Battle_FxReset), takes
; the three PCs out of the ready queue one per frame, closes the menu
; (!BattleMenu_ActivePc = none, BattleMenu_UpdateWindows), and then,
; unless !Battle_Unk2989 bit 0 is set, plays animation $0A on the
; targetable PCs (0 on the others; KO'd PCs left out), falling into
; Battle_RunPcPose. The "victory" reading is inferred from the caller
; (the unmatched code at $C1:8186 runs it when all 8 bytes at $AF02 are
; $FF, presumably no enemy left).
; Entry: M=1, X=0, DP=0, DB=$7E (through the dispatcher)
; Exit:  as Battle_RunPcPose, or after the menu update when bit 0 of
;        !Battle_Unk2989 is set
; Callees: BattleSys_FrameTickVec, Battle_FxReset,
;          BattleMenu_RemoveBattlerFromReady, BattleSys_PumpFrames,
;          BattleMenu_UpdateWindows, Battle_RunPcPose (falls through)
BattleSys_VictoryPose:
    JSL BattleSys_FrameTickVec
    INC.w !Battle_UnkA0FE
    LDX.w #!Battle_LastSlot-!Battle_FirstEnemySlot
.clear:
    STZ.w !Enemy_Stepping,X
    DEX
    BPL .clear
    LDX.w #!Battle_LastPcSlot
    STX.b !Battle_TickSlot
.reset_fx:
    JSR Battle_FxReset
    DEC.b !Battle_TickSlot
    BPL .reset_fx
    STZ.b !Battle_ArgSlot
    JSR BattleMenu_RemoveBattlerFromReady
    JSR BattleSys_PumpFrames
    INC.b !Battle_ArgSlot
    JSR BattleMenu_RemoveBattlerFromReady
    JSR BattleSys_PumpFrames
    INC.b !Battle_ArgSlot
    JSR BattleMenu_RemoveBattlerFromReady
    JSR BattleSys_PumpFrames
    LDA.b #!BattleMenu_NoSlot
    STA.w !BattleMenu_ActivePc
    JSR BattleMenu_UpdateWindows
    LDA.w !Battle_Unk2989
    AND.b #!Battle_Unk2989NoEndPose
    BEQ .pose
    RTS
.pose:
    LDX.w #!Battle_LastPcSlot
    LDY.w #!Battle_LastPcSlot*2
.slot:
    LDA.w !Battler_Untargetable,X
    BEQ .targetable
    LDA.b #!Battle_AnimUntargetable*4
    STA.w !Pc_PoseListOfs,Y
    LDA.b #0
    STA.w !Pc_PoseListOfs+1,Y
    BRA .next
.targetable:
    LDA.b #!Battle_AnimUnk0A*4
    STA.w !Pc_PoseListOfs,Y
    LDA.b #0
    STA.w !Pc_PoseListOfs+1,Y
.next:
    DEY
    DEY
    DEX
    BPL .slot
    STZ.w !Battle_PoseUnk5DDD
    STZ.w !Battle_PoseIncludeKo
    ; falls through into Battle_RunPcPose

; ==================================================================
; Battle_RunPcPose ($C135DD–$C13699, 189 bytes)
; ==================================================================
; Copies, for each present PC, the first 8 entries of its pose list into
; !Pc_PoseTicks (durations, halved) and !Pc_PoseFrames (frame ids, for
; its current facing): the lists come from bank $E4 at
; !Battler_AnimDurBase / !Battler_AnimFrameBase + !Pc_PoseListOfs (+
; Facing * FacingStride for the frame ids), as in Battle_TickPcSlots.
; Then starts the PCs on entry 0 with timers 1, 2 and 3 and runs 64
; frames: wait (BattleSys_PumpFrames), frame service tick, and
; Battle_PoseStep, which advances the poses every second call.
; !Battle_UnkE5 and !Battle_UnkA4 are cleared before and after.
; Durations are halved here (LSR) where Battle_TickPcSlots divides by 5;
; the tick buffer is cleared (24 bytes), the frame buffer is not.
; Callers: Battle_StartPose (JMP), BattleSys_DefeatPose (BRA),
; BattleSys_VictoryPose (falls through); scanned as above, no other.
; Entry: M=1, X=0, DP=0, DB=$7E; !Pc_PoseListOfs, !Battle_PoseUnk5DDD,
;        !Battle_PoseIncludeKo
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $80-$85 and the
;        callees' scratch written
; Callees: Battle_Mul8x16, BattleSys_PumpFrames, BattleSys_FrameTickVec,
;          Battle_PoseStep
!Battle_PoseSetupSlot = !BattleTmp_80     ; 2 B: PC slot whose lists are copied (zeroed 16-bit, counted 8-bit)
!Battle_PoseCopyLeft = !BattleTmp_82      ; 1 B: entries left to copy
!Battle_PoseDest = !BattleTmp_84          ; 2 B: slot * 8, its block in !Pc_PoseTicks/Frames
Battle_RunPcPose:
    LDX.w #!Battle_PoseTicksLast
.clear:
    STZ.w !Pc_PoseTicks,X
    DEX
    BPL .clear
    INX
    STX.b !Battle_PoseSetupSlot
.slot:
    LDX.b !Battle_PoseSetupSlot
    LDA.w !Battler_Present,X
    BEQ .next
    LDA.w !Battler_Facing,X
    STA.b !Battle_MulFactor8
    LDA.w !Battler_FacingStrideLo,X
    STA.b !Battle_MulFactor16
    LDA.w !Battler_FacingStrideHi,X
    STA.b !Battle_MulFactor16+1
    JSR Battle_Mul8x16
    REP #$20                        ; A -> 16-bit
    LDA.b !Battle_PoseSetupSlot
    ASL A
    ASL A
    ASL A
    STA.b !Battle_PoseDest          ; slot * 8
    LDA.b !Battle_PoseSetupSlot
    ASL A
    CLC
    ADC.b !Battle_PoseSetupSlot
    TAX                             ; slot * 3
    LDA.b !Battle_PoseSetupSlot
    ASL A
    TAY                             ; slot * 2
    CLC
    LDA.w !Pc_PoseListOfs,Y
    ADC.w !Battler_AnimDurBase,X
    STA.w !Battle_AnimDurList
    CLC
    LDA.w !Pc_PoseListOfs,Y
    ADC.w !Battler_AnimFrameBase,X
    CLC
    ADC.b !Battle_MulProduct        ; + Facing * FacingStride
    STA.w !Battle_AnimFrameList
    TDC
    SEP #$20                        ; A -> 8-bit
    LDY.b !Battle_PoseDest
    LDX.w !Battle_AnimDurList
    LDA.b #!Battle_PoseListLen
    STA.b !Battle_PoseCopyLeft
.copy_ticks:
    LDA.l !BattleRom_AnimData,X
    LSR A                           ; duration / 2
    STA.w !Pc_PoseTicks,Y
    INY
    INX
    DEC.b !Battle_PoseCopyLeft
    BNE .copy_ticks
    LDA.b #!Battle_PoseListLen
    STA.b !Battle_PoseCopyLeft
    LDX.w !Battle_AnimFrameList
    LDY.b !Battle_PoseDest
.copy_frames:
    LDA.l !BattleRom_AnimData,X
    STA.w !Pc_PoseFrames,Y
    INY
    INX
    DEC.b !Battle_PoseCopyLeft
    BNE .copy_frames
.next:
    INC.b !Battle_PoseSetupSlot
    LDA.b !Battle_PoseSetupSlot
    CMP.b #!Battle_NumPcSlots
    BNE .slot
    LDA.b #1
    STA.w !Pc_PoseTimer             ; timers 1, 2, 3
    INC A
    STA.w !Pc_PoseTimer+1
    INC A
    STA.w !Pc_PoseTimer+2
    LDA.b #!Battle_PoseEntryStart
    STA.w !Pc_PoseEntry             ; the first step makes it 0
    STA.w !Pc_PoseEntry+1
    STA.w !Pc_PoseEntry+2
    STZ.b !Battle_UnkE5
    STZ.b !Battle_UnkA4
    LDA.b #!Battle_PoseFrames
    STA.w !Battle_PoseFramesLeft
.frame:
    JSR BattleSys_PumpFrames
    JSL BattleSys_FrameTickVec
    JSR Battle_PoseStep
    DEC.w !Battle_PoseFramesLeft
    BNE .frame
    STZ.b !Battle_UnkE5
    STZ.b !Battle_UnkA4
    RTS

; ==================================================================
; Battle_PoseStep ($C1369A–$C13713, 122 bytes)
; ==================================================================
; One pose step, run on every second call: !Battle_UnkE5 flips between
; 0 (set it, return) and 1 (clear it, step). A step sets !Battle_UnkA4
; to 1 for its duration and, for PCs 0-2: skips a KO'd PC unless
; !Battle_PoseIncludeKo is set (the BattlerStats offset comes from
; BattleFx_SetPtrA2FromTable), skips an absent one, counts down
; !Pc_PoseTimer, and at 0 moves !Pc_PoseEntry on and reloads the timer
; from !Pc_PoseTicks; a non-zero tick count draws the entry's frame
; (Battle_DrawBattlerFrame). Entry 8 or a 0 tick count ends the pose:
; the timer stays 0, so the next count-down wraps it to 255 steps, longer
; than the 64-frame run.
; Quirk: at a 0 tick count it tests !Battle_PoseUnk5DDD, but both
; outcomes go to the next PC, so the flag has no effect here (kept as
; found; the code may once have done something for the battle-start
; pose, which sets it).
; Why !Battle_UnkA4 is set during the step is not known; Battle_TickPcSlots
; would tick enemy group 1 if it ran meanwhile.
; Callers (JSR; scanned as above): Battle_RunPcPose only.
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $80 and $A2-$A3
;        written, plus the decoder's scratch
; Callees: BattleFx_SetPtrA2FromTable, Battle_DrawBattlerFrame
!Battle_PoseStatsOffset = !BattleTmp_A2   ; 2 B: BattlerStats offset left by BattleFx_SetPtrA2FromTable (inferred)
!Battle_PoseEntryIdx = !BattleTmp_80      ; 1 B: the PC's new !Pc_PoseEntry
Battle_PoseStep:
    LDA.b !Battle_UnkE5
    BNE .step
    INC.b !Battle_UnkE5
    RTS
.step:
    STZ.b !Battle_UnkE5
    LDA.b #1
    STA.b !Battle_UnkA4
    TDC
    TAX
    STX.w !Battle_PoseSlot
.slot:
    LDA.w !Battle_PoseIncludeKo
    BNE .alive
    LDA.w !Battle_PoseSlot
    JSL BattleFx_SetPtrA2FromTable
    LDX.b !Battle_PoseStatsOffset
    LDA.w BattlerStats.Status,X
    BMI .next                       ; KO'd
.alive:
    LDX.w !Battle_PoseSlot
    LDA.w !Battler_Present,X
    BEQ .next
    DEC.w !Pc_PoseTimer,X
    BNE .next
    INC.w !Pc_PoseEntry,X
    LDA.w !Pc_PoseEntry,X
    CMP.b #!Battle_PoseListLen
    BNE .entry
.stop:
    BRA .next                       ; past the last entry
.entry:
    LDA.w !Pc_PoseEntry,X
    STA.b !Battle_PoseEntryIdx
    LDA.w !Battle_PoseSlot
    ASL A
    ASL A
    ASL A
    CLC
    ADC.b !Battle_PoseEntryIdx
    TAY                             ; slot * 8 + entry
    LDA.w !Pc_PoseTicks,Y
    STA.w !Pc_PoseTimer,X
    BNE .draw
    LDA.w !Battle_PoseUnk5DDD
    BEQ .stop                       ; quirk: both ways lead to .next
    BRA .next
.draw:
    LDA.w !Battle_PoseSlot
    STA.w !Battle_FrameSlot
    LDA.w !Pc_PoseFrames,Y
    STA.w !Battle_FrameId
    JSR Battle_DrawBattlerFrame
.next:
    INC.w !Battle_PoseSlot
    LDA.w !Battle_PoseSlot
    CMP.b #!Battle_NumPcSlots
    BNE .slot
    STZ.b !Battle_UnkA4
    STZ.b !Battle_UnkE5
    RTS

; ==================================================================
; Enemy movers ($C1:3714–$C1:4057)
; ==================================================================
; Enemies move in 8-pixel steps. A mover, picked by the enemy's
; !Enemy_Anim through !BattleRom_EnemyMover and Battle_EnemyMoverTable,
; chooses the heading of the next step (!Enemy_MoveAngle) and its start
; (!Enemy_StepStartX/Y), puts the enemy's probe (!Battler_ProbeX/Y) one
; step ahead and tests the box there against the cell map and the other
; battlers. If the way is free it sets !Enemy_Stepping, and the
; unmatched stepper at $CF:F978 moves the enemy along the heading over
; the next frames. When the move's goal is reached (or, for some movers,
; when a step is blocked) the mover sets !Enemy_MoveDone and saves
; !Enemy_AnimWanted in !Enemy_ResumeAnim. "Target" below is the battler
; in !Enemy_MoveTarget. Angles are 256 units per turn, measured from the
; first point towards the second (as Battle_FaceAllPcsNearestEnemy uses
; Battle_CalcAngle); 0 = right, $40 = down, $80 = left, $C0 = up, with y
; growing downwards.

; ==================================================================
; Battle_TickEnemyMovers ($C13714–$C1373A, 39 bytes)
; ==================================================================
; Per-frame enemy movement. Does nothing while !Battle_MenuTimeHold is
; set (a list is open in the waiting battle mode, inferred from that
; define). Otherwise, for each enemy 0-7 whose !Enemy_Anim is non-zero,
; counts !Enemy_MoveTimer down and, at 0, reloads it from
; !Enemy_MoveInterval and runs the enemy's mover (Battle_RunEnemyMover).
; Presence is checked only there, so an absent enemy's timer still runs.
; This routine was stubbed as Battle_TickStatusEffectVisuals, a name
; the code does not bear out.
; Callers (2 JSR sites): BattleSys_UpkeepTwoFrames ($C1:10B5, $C1:10DC).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; !Battle_MoverEnemy =
;        8 unless held; when a mover ran, its scratch too (DP $80-$86,
;        $8C-$8F, $77-$78, $A5-$B0, $D3-$E3, !Battle_MoverAnim)
; Callees: Battle_RunEnemyMover
!Battle_MoverEnemy = !BattleTmp_9C        ; 2 B: enemy being moved (0-7; slot = enemy + 3), zeroed 16-bit, counted 8-bit
Battle_TickEnemyMovers:
    LDA.w !Battle_MenuTimeHold
    BNE .exit
    TDC
    TAX
    STX.b !Battle_MoverEnemy
.enemy:
    LDX.b !Battle_MoverEnemy
    LDA.w !Enemy_Anim,X
    BEQ .next
    DEC.w !Enemy_MoveTimer,X
    BNE .next
    LDA.w !Enemy_MoveInterval,X
    STA.w !Enemy_MoveTimer,X
    JSR Battle_RunEnemyMover
.next:
    INC.b !Battle_MoverEnemy
    LDA.b !Battle_MoverEnemy
    CMP.b #8                        ; enemies 0-7
    BNE .enemy
.exit:
    RTS

; ==================================================================
; Battle_RunEnemyMover ($C1373B–$C1375F, 37 bytes)
; ==================================================================
; Runs the mover of enemy !Battle_MoverEnemy, if that enemy is present:
; copies !Enemy_TargetWanted into !Enemy_MoveTarget, then, unless
; !Enemy_Anim is negative, stores the id in !Battle_MoverAnim and calls
; entry !BattleRom_EnemyMover[id] of Battle_EnemyMoverTable.
; Quirk: the copy is skipped when the two are already equal, which
; changes nothing (kept as found).
; Callers (JSR): Battle_TickEnemyMovers ($C1:372F) only.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_MoverEnemy = enemy (0-7)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; when a mover ran,
;        !Battle_MoverAnim and the mover's scratch (see the movers)
; Callees: JSR (Battle_EnemyMoverTable,X)
Battle_RunEnemyMover:
    LDX.b !Battle_MoverEnemy
    LDA.w !Battler_Present+!Battle_FirstEnemySlot,X
    BEQ .exit
    LDA.w !Enemy_TargetWanted,X
    CMP.w !Enemy_MoveTarget,X
    BEQ .target_set                 ; quirk: storing it anyway would do the same
    STA.w !Enemy_MoveTarget,X
.target_set:
    LDA.w !Enemy_Anim,X
    BMI .exit
    STA.w !Battle_MoverAnim
    TAX
    LDA.l !BattleRom_EnemyMover,X
    ASL A
    TAX
    JSR (Battle_EnemyMoverTable,X)
.exit:
    RTS

; Battle_EnemyMoverTable ($C13760–$C13771, 18 bytes)
; One mover per !BattleRom_EnemyMover entry, called from
; Battle_RunEnemyMover. The comments give the move ids that pick each
; entry ($CC:FBAB-$CC:FBC4, ids $00-$19); id 0 maps to entry 0 but never
; gets there, since Battle_TickEnemyMovers skips enemies whose id is 0.
Battle_EnemyMoverTable:
    dw Battle_MoverIdle             ; 0: ids $00, $04
    dw Battle_MoverApproach         ; 1: ids $01-$03, $05
    dw Battle_MoverCharge           ; 2: id $07
    dw Battle_MoverAxis             ; 3: ids $08, $09
    dw Battle_MoverKeepRange        ; 4: ids $06, $10
    dw Battle_MoverOrbit            ; 5: ids $0D-$0F
    dw Battle_MoverLoop             ; 6: ids $0A-$0C
    dw Battle_MoverFixedDir         ; 7: ids $11-$18
    dw Battle_MoverToCentre         ; 8: id $19

; ==================================================================
; Battle_MoverIdle ($C13772–$C13799, 40 bytes)
; ==================================================================
; Mover 0 (move 4): stays put. Once the enemy's last move has ended
; (!Enemy_MoveDone), watches the target: when it is no longer where it
; was at the end (!Enemy_DoneTargetX/Y), restores the move that ended
; (!Enemy_ResumeAnim -> !Enemy_AnimWanted) and clears !Enemy_MoveDone,
; so the enemy follows the target again. Clears !Enemy_LoopStarted only
; when MoveDone is set.
; Callers: Battle_EnemyMoverTable entry 0.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_MoverEnemy = enemy (0-7)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, Y clobbered; X = enemy (0-7)
Battle_MoverIdle:
    LDX.b !Battle_MoverEnemy
    LDA.w !Enemy_MoveDone,X
    BEQ .exit
    STZ.w !Enemy_LoopStarted,X
    LDA.w !Enemy_MoveTarget,X
    TAY
    LDA.w !Battler_ScreenX,Y
    CMP.w !Enemy_DoneTargetX,X
    BNE .resume
    LDA.w !Battler_ScreenY,Y
    CMP.w !Enemy_DoneTargetY,X
    BEQ .exit
.resume:
    LDA.w !Enemy_ResumeAnim,X
    STA.w !Enemy_AnimWanted,X
    STZ.w !Enemy_MoveDone,X
.exit:
    RTS

; ==================================================================
; Battle_MoverApproach ($C1379A–$C138BE, 293 bytes)
; ==================================================================
; Mover 1: walks towards the target until within reach. Unless a detour
; is pending (!Enemy_Detour), the step starts at the enemy's position and
; heads straight for the target; with a detour it keeps the turned
; heading (the blocked step never moved the enemy, so the old start
; still holds). Facing follows the heading. Then, by !Battle_MoverAnim:
;   1, 2, 3  ends the move (done path below) once within 32, 64 or 4
;            pixels (BattlePos_WithinDist32XY/64XY/4XY, measured on the
;            probes, which are first set to both battlers' positions);
;   other    (move 5) ends the move at once, without a step.
; Otherwise it probes one step ahead: if the box hits a blocking cell
; (move 3 passes cell bit 7) or, except for move 3, another battler, the
; heading is turned a quarter turn on and rounded down to a multiple of
; a quarter (right, down, left, up), !Enemy_Detour set and no step made;
; else the step starts (!Enemy_Stepping) and the detour is cleared.
; Done: !Enemy_MoveDone counted up, !Enemy_AnimWanted saved in
; !Enemy_ResumeAnim, the target's position in !Enemy_DoneTargetX/Y,
; !Enemy_Stepping cleared.
; Callers: Battle_EnemyMoverTable entry 1.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_MoverEnemy = enemy (0-7),
;        !Battle_MoverAnim
; Exit:  M=1, X=0, DP=0, DB=$7E; A, Y clobbered; X and
;        !Battle_BoxTestSlot = the enemy's battler slot; DP $8C-$8F,
;        $77-$78, $A5-$AE, $D3-$E3 and the callees' $80-$86 written
; Callees: Battle_CalcAngle, Battle_SinLookup, BattlePos_WithinDist32XY,
;          BattlePos_WithinDist64XY, BattlePos_WithinDist4XY,
;          Battle_CalcBattlerBox, Battle_BoxHitsBlockedCell,
;          Battle_BoxOverlapsOthers
!Battle_MoveStepY = !BattleTmp_8C         ; 1 B: y part of the step (sin * 8), signed
!Battle_MoveStepX = !BattleTmp_8E         ; 1 B: x part of the step (cos * 8), signed
Battle_MoverApproach:
    LDX.b !Battle_MoverEnemy
    STZ.w !Enemy_LoopStarted,X
    LDA.w !Enemy_Detour,X
    BEQ .aim
    LDA.w !Enemy_MoveAngle,X
    STA.b !Battle_GeoAngle
    BRA .heading
.aim:
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    STA.b !Battle_GeoOriginX
    STA.w !Enemy_StepStartX,X
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    STA.b !Battle_GeoOriginY
    STA.w !Enemy_StepStartY,X
    LDA.w !Enemy_MoveTarget,X
    TAY
    LDA.w !Battler_ScreenX,Y
    STA.b !Battle_GeoPointX
    LDA.w !Battler_ScreenY,Y
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle
.heading:
    LDA.b #!Battle_MoveStepLen
    STA.b !Battle_SinScale
    LDX.b !Battle_MoverEnemy
    LDA.b !Battle_GeoAngle
    STA.w !Enemy_MoveAngle,X
    JSR Battle_SinLookup
    STA.b !Battle_MoveStepY
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup            ; cosine
    STA.b !Battle_MoveStepX
    LDA.b !Battle_GeoAngle
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    LDX.b !Battle_MoverEnemy
    STA.w !Battler_Facing+!Battle_FirstEnemySlot,X
    LDA.w !Enemy_MoveTarget,X
    TAY
    LDA.w !Battler_ScreenX,Y
    STA.w !Battler_ProbeX,Y
    LDA.w !Battler_ScreenY,Y
    STA.w !Battler_ProbeY,Y
    TXA
    CLC
    ADC.b #!Battle_FirstEnemySlot
    TAX                             ; X = the enemy's battler slot
    LDA.w !Battler_ScreenX,X
    STA.w !Battler_ProbeX,X
    LDA.w !Battler_ScreenY,X
    STA.w !Battler_ProbeY,X
    LDA.w !Battle_MoverAnim
    DEC A
    BNE .not_near32
    JSR BattlePos_WithinDist32XY
    BRA .check_reach
.not_near32:
    DEC A
    BNE .not_near64
    JSR BattlePos_WithinDist64XY
    BRA .check_reach
.not_near64:
    DEC A
    BNE .done                       ; move 5: ends at once
    JSR BattlePos_WithinDist4XY
.check_reach:
    LDA.w !BattlePos_Result
    BMI .step
.done:
    LDX.b !Battle_MoverEnemy
    INC.w !Enemy_MoveDone,X
    LDA.w !Enemy_AnimWanted,X
    STA.w !Enemy_ResumeAnim,X
    LDA.w !Enemy_MoveTarget,X
    TAY
    LDA.w !Battler_ScreenX,Y
    STA.w !Enemy_DoneTargetX,X
    LDA.w !Battler_ScreenY,Y
    STA.w !Enemy_DoneTargetY,X
    STZ.w !Enemy_Stepping,X
    BRA .exit
.step:
    LDX.b !Battle_MoverEnemy
    CLC
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    ADC.b !Battle_MoveStepY
    STA.w !Battler_ProbeY+!Battle_FirstEnemySlot,X
    CLC
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    ADC.b !Battle_MoveStepX
    STA.w !Battler_ProbeX+!Battle_FirstEnemySlot,X
    INX
    INX
    INX
    STX.b !Battle_BoxTestSlot
    JSR Battle_CalcBattlerBox
    STZ.w !Battle_PassCellBit7
    LDA.w !Battle_MoverAnim
    CMP.b #!Enemy_MoveNear4
    BNE .test_cells
    LDA.b #1
    STA.w !Battle_PassCellBit7
.test_cells:
    JSR Battle_BoxHitsBlockedCell
    BMI .blocked
    LDA.w !Battle_MoverAnim
    CMP.b #!Enemy_MoveNear4
    BEQ .free                       ; move 3 passes other battlers
    JSR Battle_BoxOverlapsOthers
    BPL .free
.blocked:
    LDX.b !Battle_MoverEnemy
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleQuarter
    LSR A                           ; round down to a quarter turn
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    STA.b !Battle_GeoAngle
    LDA.b !Battle_GeoAngle
    STA.w !Enemy_MoveAngle,X
    INC.w !Enemy_Detour,X
    STZ.w !Enemy_Stepping,X
    BRA .exit
.free:
    LDX.b !Battle_MoverEnemy
    STZ.w !Enemy_Detour,X
    LDA.b #1
    STA.w !Enemy_Stepping,X
.exit:
    INX
    INX
    INX
    STX.b !Battle_BoxTestSlot
    RTS

; ==================================================================
; Battle_MoverCharge ($C138BF–$C13958, 154 bytes)
; ==================================================================
; Mover 2 (move 7): heads straight for the target from the enemy's
; position every time and starts the step, until a step is blocked by a
; blocking cell or another battler (the target included): then the step
; is cancelled and the move ends (the done path of
; Battle_MoverApproach). No detours.
; Quirk: when the step is free, X still holds the battler slot that
; Battle_BoxOverlapsOthers returns, so the closing INX x3 leaves X and
; !Battle_BoxTestSlot at enemy + 6 instead of the slot; the callers
; reload X, so it does no harm (kept as found).
; Callers: Battle_EnemyMoverTable entry 2.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_MoverEnemy = enemy (0-7)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, Y clobbered; X and
;        !Battle_BoxTestSlot = the enemy's battler slot (enemy + 6 when
;        the step is free, see above); DP $8C-$8F,
;        $77-$78, $A5-$AE, $D3-$E3 and the callees' $80-$86 written
; Callees: Battle_CalcAngle, Battle_SinLookup, Battle_CalcBattlerBox,
;          Battle_BoxHitsBlockedCell, Battle_BoxOverlapsOthers
Battle_MoverCharge:
    LDX.b !Battle_MoverEnemy
    STZ.w !Enemy_LoopStarted,X
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    STA.b !Battle_GeoOriginX
    STA.w !Enemy_StepStartX,X
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    STA.b !Battle_GeoOriginY
    STA.w !Enemy_StepStartY,X
    LDA.w !Enemy_MoveTarget,X
    TAY
    LDA.w !Battler_ScreenX,Y
    STA.b !Battle_GeoPointX
    LDA.w !Battler_ScreenY,Y
    STA.b !Battle_GeoPointY
    LDA.b #!Battle_MoveStepLen
    STA.b !Battle_SinScale
    JSR Battle_CalcAngle
    LDX.b !Battle_MoverEnemy
    STA.w !Enemy_MoveAngle,X
    JSR Battle_SinLookup
    STA.b !Battle_MoveStepY
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup            ; cosine
    STA.b !Battle_MoveStepX
    LDA.b !Battle_GeoAngle
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    LDX.b !Battle_MoverEnemy
    STA.w !Battler_Facing+!Battle_FirstEnemySlot,X
    LDA.b #1
    STA.w !Enemy_Stepping,X
    CLC
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    ADC.b !Battle_MoveStepY
    STA.w !Battler_ProbeY+!Battle_FirstEnemySlot,X
    CLC
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    ADC.b !Battle_MoveStepX
    STA.w !Battler_ProbeX+!Battle_FirstEnemySlot,X
    INX
    INX
    INX
    STX.b !Battle_BoxTestSlot
    JSR Battle_CalcBattlerBox
    STZ.w !Battle_PassCellBit7
    JSR Battle_BoxHitsBlockedCell
    BMI .done
    JSR Battle_BoxOverlapsOthers
    BPL .exit
.done:
    LDX.b !Battle_MoverEnemy
    INC.w !Enemy_MoveDone,X
    LDA.w !Enemy_AnimWanted,X
    STA.w !Enemy_ResumeAnim,X
    LDA.w !Enemy_MoveTarget,X
    TAY
    LDA.w !Battler_ScreenX,Y
    STA.w !Enemy_DoneTargetX,X
    LDA.w !Battler_ScreenY,Y
    STA.w !Enemy_DoneTargetY,X
    STZ.w !Enemy_Stepping,X
.exit:
    INX
    INX
    INX
    STX.b !Battle_BoxTestSlot
    RTS

; ==================================================================
; Battle_MoverAxis ($C13959–$C13A3C, 228 bytes)
; ==================================================================
; Mover 3: lines the enemy up with the target along one axis. Move 8
; steps straight up or down towards the target's y (up when the target
; is higher, otherwise down); move 9 steps left or right towards its x
; (left when the target is further left, otherwise right). The step
; starts from the enemy's position each time. The move ends (done path
; of Battle_MoverApproach, which also cancels the step just started)
; when the step is blocked by a cell or a battler, or when the enemy
; and the target are in the same 32-pixel band of y (move 8) or x
; (move 9), compared on their current positions.
; Callers: Battle_EnemyMoverTable entry 3.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_MoverEnemy = enemy (0-7),
;        !Battle_MoverAnim
; Exit:  M=1, X=0, DP=0, DB=$7E; A clobbered; Y = the target's slot; X
;        and !Battle_BoxTestSlot = the enemy's battler slot; DP $8C-$8F,
;        $77-$78, $A5-$AE and the callees' $80-$86 written
; Callees: Battle_SinLookup, Battle_CalcBattlerBox,
;          Battle_BoxHitsBlockedCell, Battle_BoxOverlapsOthers,
;          Battle_ShiftRight5
!Battle_MoveTargetBand = !BattleTmp_80    ; 1 B: the target's 32-pixel band (coordinate >> 5)
Battle_MoverAxis:
    LDX.b !Battle_MoverEnemy
    STZ.w !Enemy_LoopStarted,X
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    STA.w !Enemy_StepStartX,X
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    STA.w !Enemy_StepStartY,X
    LDA.w !Enemy_MoveTarget,X
    TAY
    LDA.w !Battle_MoverAnim
    CMP.b #!Enemy_MoveAxisY
    BNE .horizontal
    LDA.w !Battler_ScreenY,Y
    CMP.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    BCS .down
    LDA.b #!Battle_AngleThreeQuarter ; up
    BRA .heading
.down:
    LDA.b #!Battle_AngleQuarter
    BRA .heading
.horizontal:
    LDA.w !Battler_ScreenX,Y
    CMP.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    BCS .right
    LDA.b #!Battle_AngleHalfTurn    ; left
    BRA .heading
.right:
    TDC
.heading:
    STA.b !Battle_GeoAngle
    LDA.b #!Battle_MoveStepLen
    STA.b !Battle_SinScale
    LDX.b !Battle_MoverEnemy
    LDA.b !Battle_GeoAngle
    STA.w !Enemy_MoveAngle,X
    JSR Battle_SinLookup
    STA.b !Battle_MoveStepY
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup            ; cosine
    STA.b !Battle_MoveStepX
    LDA.b !Battle_GeoAngle
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    LDX.b !Battle_MoverEnemy
    STA.w !Battler_Facing+!Battle_FirstEnemySlot,X
    LDA.b #1
    STA.w !Enemy_Stepping,X
    CLC
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    ADC.b !Battle_MoveStepY
    STA.w !Battler_ProbeY+!Battle_FirstEnemySlot,X
    CLC
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    ADC.b !Battle_MoveStepX
    STA.w !Battler_ProbeX+!Battle_FirstEnemySlot,X
    INX
    INX
    INX
    STX.b !Battle_BoxTestSlot
    JSR Battle_CalcBattlerBox
    STZ.w !Battle_PassCellBit7
    JSR Battle_BoxHitsBlockedCell
    BMI .done
    JSR Battle_BoxOverlapsOthers
    BMI .done
    LDX.b !Battle_MoverEnemy
    LDA.w !Enemy_MoveTarget,X
    TAY
    LDA.w !Battle_MoverAnim
    CMP.b #!Enemy_MoveAxisY
    BNE .band_x
    LDA.w !Battler_ScreenY,Y
    JSR Battle_ShiftRight5
    STA.b !Battle_MoveTargetBand
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    JSR Battle_ShiftRight5
    CMP.b !Battle_MoveTargetBand
    BEQ .done
    BRA .exit
.band_x:
    LDA.w !Battler_ScreenX,Y
    JSR Battle_ShiftRight5
    STA.b !Battle_MoveTargetBand
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    JSR Battle_ShiftRight5
    CMP.b !Battle_MoveTargetBand
    BNE .exit
.done:
    LDX.b !Battle_MoverEnemy
    INC.w !Enemy_MoveDone,X
    LDA.w !Enemy_AnimWanted,X
    STA.w !Enemy_ResumeAnim,X
    LDA.w !Enemy_MoveTarget,X
    TAY
    LDA.w !Battler_ScreenX,Y
    STA.w !Enemy_DoneTargetX,X
    LDA.w !Battler_ScreenY,Y
    STA.w !Enemy_DoneTargetY,X
    STZ.w !Enemy_Stepping,X
.exit:
    INX
    INX
    INX
    STX.b !Battle_BoxTestSlot
    RTS

; ==================================================================
; Battle_MoverKeepRange ($C13A3D–$C13BC1, 389 bytes)
; ==================================================================
; Mover 4 (moves 6 and $10): makes for the point on a ring around the
; target, radius $40 (move $10: $80), on the enemy's side of it. Unless a
; detour is pending (then the turned heading is kept, as in
; Battle_MoverApproach), it takes the angle from the target to the enemy,
; puts the ring point there (kept in !Enemy_RingGoalX/Y) and compares the
; enemy's position with it. Per quadrant of that angle, when the enemy is
; level with or beyond the point on either axis (further from the
; target), the heading is turned a half turn, towards the target;
; otherwise it stays, away from the target. The step starts from the
; enemy's position. Facing follows the heading.
; Move 6 ends the move (done path of Battle_MoverApproach) once the
; enemy's probe is within 4 pixels of the ring point (the point goes in
; probe entry !Battle_GoalSlot, past the battlers); move $10 never ends
; it. Otherwise the step is probed and taken, or blocked (a blocking
; cell or another battler) with a quarter-turn detour, as in
; Battle_MoverApproach.
; Quirks, kept as found: the y comparison runs on the borrow of the x
; comparison (no SEC between), so it is one pixel off when the enemy is
; left of the point; and the step test still skips the battler test for
; move 3, which never reaches this mover (copied from
; Battle_MoverApproach, inferred).
; Callers: Battle_EnemyMoverTable entry 4.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_MoverEnemy = enemy (0-7),
;        !Battle_MoverAnim
; Exit:  M=1, X=0, DP=0, DB=$7E; A, Y clobbered; X and
;        !Battle_BoxTestSlot = the enemy's battler slot; DP $80-$86,
;        $8C-$8F, $77-$78, $A5-$B0 and $D3-$E3 written; probe entry
;        !Battle_GoalSlot set unless the move is $10
; Callees: Battle_CalcAngle, Battle_SinLookup, Battle_ShiftRight6,
;          BattlePos_WithinDist4XYTwin, Battle_CalcBattlerBox,
;          Battle_BoxHitsBlockedCell, Battle_BoxOverlapsOthers
!Battle_RingPointX = !BattleTmp_80        ; 1 B: x of the ring point
!Battle_RingSignX = !BattleTmp_81         ; 1 B: 0 = enemy x >= ring point x, $FF = less
!Battle_RingPointY = !BattleTmp_82        ; 1 B: y of the ring point
!Battle_RingSignY = !BattleTmp_83         ; 1 B: 0 = enemy y >= ring point y (see the quirk), $FF = less
!Battle_RingQuadrant = !BattleTmp_84      ; 1 B: angle >> 6: 0 = right-down, 1 = left-down, 2 = left-up, 3 = right-up
Battle_MoverKeepRange:
    LDX.b !Battle_MoverEnemy
    STZ.w !Enemy_LoopStarted,X
    LDA.w !Enemy_Detour,X
    BEQ .aim
    LDA.w !Enemy_MoveAngle,X
    STA.b !Battle_GeoAngle
    JMP .heading
.aim:
    LDA.w !Enemy_MoveTarget,X
    TAY
    LDA.w !Battler_ScreenX,Y
    STA.b !Battle_GeoOriginX
    LDA.w !Battler_ScreenY,Y
    STA.b !Battle_GeoOriginY
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    STA.b !Battle_GeoPointX
    STA.w !Enemy_StepStartX,X
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    STA.b !Battle_GeoPointY
    STA.w !Enemy_StepStartY,X
    LDA.b #!Battle_RingRadius
    STA.b !Battle_SinScale
    LDA.w !Battle_MoverAnim
    CMP.b #!Enemy_MoveRingFar
    BNE .radius_set
    LDA.b #!Battle_RingRadiusFar
    STA.b !Battle_SinScale
.radius_set:
    JSR Battle_CalcAngle            ; target -> enemy
    JSR Battle_SinLookup
    CLC
    ADC.b !Battle_GeoOriginY
    LDX.b !Battle_MoverEnemy
    STA.b !Battle_RingPointY
    STA.w !Enemy_RingGoalY,X
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup            ; cosine
    CLC
    ADC.b !Battle_GeoOriginX
    LDX.b !Battle_MoverEnemy
    STA.b !Battle_RingPointX
    STA.w !Enemy_RingGoalX,X
    LDX.b !Battle_MoverEnemy
    SEC
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    SBC.b !Battle_RingPointX
    TDC
    SBC.b #0
    STA.b !Battle_RingSignX
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    SBC.b !Battle_RingPointY        ; quirk: borrows from the x sign above
    TDC
    SBC.b #0
    STA.b !Battle_RingSignY
    LDA.b !Battle_GeoAngle
    JSR Battle_ShiftRight6
    STA.b !Battle_RingQuadrant
    AND.b #2
    BNE .upper
    LDA.b !Battle_RingQuadrant
    BNE .left_down
    LDA.b !Battle_RingSignX         ; right-down
    BEQ .inward
    LDA.b !Battle_RingSignY
    BEQ .inward
    BRA .heading
.left_down:
    LDA.b !Battle_RingSignX
    BMI .inward
    LDA.b !Battle_RingSignY
    BEQ .inward
    BRA .heading
.upper:
    LDA.b !Battle_RingQuadrant
    AND.b #1
    BNE .right_up
    LDA.b !Battle_RingSignX         ; left-up
    BMI .inward
    LDA.b !Battle_RingSignY
    BMI .inward
    BRA .heading
.right_up:
    LDA.b !Battle_RingSignX
    BEQ .inward
    LDA.b !Battle_RingSignY
    BEQ .heading
.inward:
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleHalfTurn
    STA.b !Battle_GeoAngle
.heading:
    LDA.b #!Battle_MoveStepLen
    STA.b !Battle_SinScale
    LDX.b !Battle_MoverEnemy
    LDA.b !Battle_GeoAngle
    STA.w !Enemy_MoveAngle,X
    JSR Battle_SinLookup
    STA.b !Battle_MoveStepY
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup            ; cosine
    STA.b !Battle_MoveStepX
    LDA.b !Battle_GeoAngle
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    LDX.b !Battle_MoverEnemy
    STA.w !Battler_Facing+!Battle_FirstEnemySlot,X
    LDA.w !Battle_MoverAnim
    CMP.b #!Enemy_MoveRingFar
    BEQ .step
    LDY.w #!Battle_GoalSlot
    LDA.w !Enemy_RingGoalY,X
    STA.w !Battler_ProbeY,Y
    LDA.w !Enemy_RingGoalX,X
    STA.w !Battler_ProbeX,Y
    TXA
    CLC
    ADC.b #!Battle_FirstEnemySlot
    TAX                             ; X = the enemy's battler slot
    JSR BattlePos_WithinDist4XYTwin
    LDA.w !BattlePos_Result
    BMI .step
    LDX.b !Battle_MoverEnemy
    INC.w !Enemy_MoveDone,X
    LDA.w !Enemy_AnimWanted,X
    STA.w !Enemy_ResumeAnim,X
    LDA.w !Enemy_MoveTarget,X
    TAY
    LDA.w !Battler_ScreenX,Y
    STA.w !Enemy_DoneTargetX,X
    LDA.w !Battler_ScreenY,Y
    STA.w !Enemy_DoneTargetY,X
    STZ.w !Enemy_Stepping,X
    BRA .exit
.step:
    LDX.b !Battle_MoverEnemy
    CLC
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    ADC.b !Battle_MoveStepY
    STA.w !Battler_ProbeY+!Battle_FirstEnemySlot,X
    CLC
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    ADC.b !Battle_MoveStepX
    STA.w !Battler_ProbeX+!Battle_FirstEnemySlot,X
    INX
    INX
    INX
    STX.b !Battle_BoxTestSlot
    JSR Battle_CalcBattlerBox
    STZ.w !Battle_PassCellBit7
    JSR Battle_BoxHitsBlockedCell
    BMI .blocked
    LDA.w !Battle_MoverAnim
    CMP.b #!Enemy_MoveNear4
    BEQ .free                       ; quirk: move 3 never gets here
    JSR Battle_BoxOverlapsOthers
    BPL .free
.blocked:
    LDX.b !Battle_MoverEnemy
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleQuarter
    LSR A                           ; round down to a quarter turn
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    STA.b !Battle_GeoAngle
    LDA.b !Battle_GeoAngle
    STA.w !Enemy_MoveAngle,X
    INC.w !Enemy_Detour,X
    STZ.w !Enemy_Stepping,X
    BRA .exit
.free:
    LDX.b !Battle_MoverEnemy
    STZ.w !Enemy_Detour,X
    LDA.b #1
    STA.w !Enemy_Stepping,X
.exit:
    INX
    INX
    INX
    STX.b !Battle_BoxTestSlot
    RTS

; ==================================================================
; Battle_MoverOrbit ($C13BC2–$C13E32, 625 bytes)
; ==================================================================
; Mover 5 (moves $0D-$0F): circles the target on a ring of radius
; !Battle_OrbitRadius ($20; move $0E: $40). The first part is
; Battle_MoverKeepRange with that radius (same ring point, same quirks,
; the detour kept the same way). Then:
;   - the enemy's probe within 16 pixels of the ring point: orbit (below);
;   - otherwise move $0D stays put (!Enemy_Stepping cleared; it only
;     circles once it is on the ring), and the others step towards the
;     ring point as Battle_MoverKeepRange does, move $0F passing cell
;     bit 7 and other battlers.
; Orbit: clears the detour, takes the angle from the target to the enemy
; again (step start = the enemy's position), moves it on by $10, or back
; by $10 when !Enemy_OrbitReverse is set, and heads for the point of the
; ring at that angle. If that heading is exactly the direction to the
; target it is turned on by 1 unit, by 2 at radius $20 (presumably so as
; not to walk straight at the target; why is not known). A blocked step
; reverses the orbit (!Enemy_OrbitReverse flipped) and leaves
; !Enemy_Stepping as it was; a free one starts it. Move $0F passes cell
; bit 7 and other battlers here too.
; The move never ends; the approach part never sets !Enemy_MoveDone.
; Callers: Battle_EnemyMoverTable entry 5.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_MoverEnemy = enemy (0-7),
;        !Battle_MoverAnim
; Exit:  M=1, X=0, DP=0, DB=$7E; A, Y clobbered; X and
;        !Battle_BoxTestSlot = the enemy's battler slot; DP $80-$86,
;        $8C-$8F, $77-$78, $A5-$B0 and $D3-$E3 written; probe entry
;        !Battle_GoalSlot set; !Battle_OrbitRadius set unless a detour
;        was pending
; Callees: Battle_CalcAngle, Battle_SinLookup, Battle_ShiftRight6,
;          BattlePos_WithinDist16XY, Battle_CalcBattlerBox,
;          Battle_BoxHitsBlockedCell, Battle_BoxOverlapsOthers
Battle_MoverOrbit:
    LDX.b !Battle_MoverEnemy
    STZ.w !Enemy_LoopStarted,X
    LDA.w !Enemy_Detour,X
    BEQ .aim
    LDA.w !Enemy_MoveAngle,X
    STA.b !Battle_GeoAngle
    JMP .heading
.aim:
    LDA.w !Enemy_MoveTarget,X
    TAY
    LDA.w !Battler_ScreenX,Y
    STA.b !Battle_GeoOriginX
    LDA.w !Battler_ScreenY,Y
    STA.b !Battle_GeoOriginY
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    STA.b !Battle_GeoPointX
    STA.w !Enemy_StepStartX,X
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    STA.b !Battle_GeoPointY
    STA.w !Enemy_StepStartY,X
    LDA.b #!Battle_OrbitRadiusSmall
    STA.w !Battle_OrbitRadius
    LDA.w !Battle_MoverAnim
    CMP.b #!Enemy_MoveOrbitWide
    BNE .radius_set
    ASL.w !Battle_OrbitRadius
.radius_set:
    LDA.w !Battle_OrbitRadius
    STA.b !Battle_SinScale
    JSR Battle_CalcAngle            ; target -> enemy
    JSR Battle_SinLookup
    CLC
    ADC.b !Battle_GeoOriginY
    LDX.b !Battle_MoverEnemy
    STA.b !Battle_RingPointY
    STA.w !Enemy_RingGoalY,X
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup            ; cosine
    CLC
    ADC.b !Battle_GeoOriginX
    LDX.b !Battle_MoverEnemy
    STA.b !Battle_RingPointX
    STA.w !Enemy_RingGoalX,X
    LDX.b !Battle_MoverEnemy
    SEC
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    SBC.b !Battle_RingPointX
    TDC
    SBC.b #0
    STA.b !Battle_RingSignX
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    SBC.b !Battle_RingPointY        ; quirk: borrows from the x sign above
    TDC
    SBC.b #0
    STA.b !Battle_RingSignY
    LDA.b !Battle_GeoAngle
    JSR Battle_ShiftRight6
    STA.b !Battle_RingQuadrant
    AND.b #2
    BNE .upper
    LDA.b !Battle_RingQuadrant
    BNE .left_down
    LDA.b !Battle_RingSignX         ; right-down
    BEQ .inward
    LDA.b !Battle_RingSignY
    BEQ .inward
    BRA .heading
.left_down:
    LDA.b !Battle_RingSignX
    BMI .inward
    LDA.b !Battle_RingSignY
    BEQ .inward
    BRA .heading
.upper:
    LDA.b !Battle_RingQuadrant
    AND.b #1
    BNE .right_up
    LDA.b !Battle_RingSignX         ; left-up
    BMI .inward
    LDA.b !Battle_RingSignY
    BMI .inward
    BRA .heading
.right_up:
    LDA.b !Battle_RingSignX
    BEQ .inward
    LDA.b !Battle_RingSignY
    BEQ .heading
.inward:
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleHalfTurn
    STA.b !Battle_GeoAngle
.heading:
    LDA.b #!Battle_MoveStepLen
    STA.b !Battle_SinScale
    LDX.b !Battle_MoverEnemy
    LDA.b !Battle_GeoAngle
    STA.w !Enemy_MoveAngle,X
    JSR Battle_SinLookup
    STA.b !Battle_MoveStepY
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup            ; cosine
    STA.b !Battle_MoveStepX
    LDA.b !Battle_GeoAngle
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    LDX.b !Battle_MoverEnemy
    STA.w !Battler_Facing+!Battle_FirstEnemySlot,X
    LDY.w #!Battle_GoalSlot
    LDA.w !Enemy_RingGoalY,X
    STA.w !Battler_ProbeY,Y
    LDA.w !Enemy_RingGoalX,X
    STA.w !Battler_ProbeX,Y
    TXA
    CLC
    ADC.b #!Battle_FirstEnemySlot
    TAX                             ; X = the enemy's battler slot
    JSR BattlePos_WithinDist16XY
    LDA.w !BattlePos_Result
    BMI .approach
    JMP .orbit
.approach:
    LDX.b !Battle_MoverEnemy
    LDA.w !Battle_MoverAnim
    CMP.b #!Enemy_MoveOrbitHold
    BNE .step
    STZ.w !Enemy_Stepping,X
    BRA .exit
.step:
    CLC
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    ADC.b !Battle_MoveStepY
    STA.w !Battler_ProbeY+!Battle_FirstEnemySlot,X
    CLC
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    ADC.b !Battle_MoveStepX
    STA.w !Battler_ProbeX+!Battle_FirstEnemySlot,X
    INX
    INX
    INX
    STX.b !Battle_BoxTestSlot
    JSR Battle_CalcBattlerBox
    STZ.w !Battle_PassCellBit7
    LDA.w !Battle_MoverAnim
    CMP.b #!Enemy_MoveOrbitPass
    BNE .test_cells
    LDA.b #1
    STA.w !Battle_PassCellBit7
.test_cells:
    JSR Battle_BoxHitsBlockedCell
    BMI .blocked
    LDA.w !Battle_MoverAnim
    CMP.b #!Enemy_MoveOrbitPass
    BEQ .free                       ; move $0F passes other battlers
    JSR Battle_BoxOverlapsOthers
    BPL .free
.blocked:
    LDX.b !Battle_MoverEnemy
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleQuarter
    LSR A                           ; round down to a quarter turn
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    STA.b !Battle_GeoAngle
    LDA.b !Battle_GeoAngle
    STA.w !Enemy_MoveAngle,X
    INC.w !Enemy_Detour,X
    STZ.w !Enemy_Stepping,X
    BRA .exit
.free:
    LDX.b !Battle_MoverEnemy
    STZ.w !Enemy_Detour,X
    LDA.b #1
    STA.w !Enemy_Stepping,X
.exit:
    INX
    INX
    INX
    STX.b !Battle_BoxTestSlot
    RTS
.orbit:
    LDX.b !Battle_MoverEnemy
    STZ.w !Enemy_Detour,X
    LDA.w !Enemy_MoveTarget,X
    TAY
    LDA.w !Battler_ScreenX,Y
    STA.b !Battle_GeoOriginX
    LDA.w !Battler_ScreenY,Y
    STA.b !Battle_GeoOriginY
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    STA.b !Battle_GeoPointX
    STA.w !Enemy_StepStartX,X
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    STA.b !Battle_GeoPointY
    STA.w !Enemy_StepStartY,X
    JSR Battle_CalcAngle            ; target -> enemy
    PHA
    LDX.b !Battle_MoverEnemy
    LDA.w !Enemy_OrbitReverse,X
    BNE .backwards
    LDA.b #!Battle_OrbitTurn
    BRA .turn
.backwards:
    LDA.b #!Battle_OrbitTurnBack
.turn:
    CLC
    ADC.b !Battle_GeoAngle
    STA.b !Battle_GeoAngle
    LDA.w !Battle_OrbitRadius
    STA.b !Battle_SinScale
    LDA.b !Battle_GeoAngle
    JSR Battle_SinLookup
    LDX.b !Battle_MoverEnemy
    CLC
    ADC.w !Battler_ScreenY,Y
    STA.b !Battle_GeoPointY
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup            ; cosine
    LDX.b !Battle_MoverEnemy
    CLC
    ADC.w !Battler_ScreenX,Y
    STA.b !Battle_GeoPointX         ; the next point of the ring
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    STA.b !Battle_GeoOriginX
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    STA.b !Battle_GeoOriginY
    JSR Battle_CalcAngle            ; enemy -> that point
    PLA
    CLC
    ADC.b #!Battle_AngleHalfTurn    ; enemy -> target
    CMP.b !Battle_GeoAngle
    BNE .orbit_heading
    INC.b !Battle_GeoAngle
    LDA.w !Battle_OrbitRadius
    CMP.b #!Battle_OrbitRadiusSmall
    BNE .orbit_heading
    INC.b !Battle_GeoAngle
.orbit_heading:
    LDA.b #!Battle_MoveStepLen
    STA.b !Battle_SinScale
    LDX.b !Battle_MoverEnemy
    LDA.b !Battle_GeoAngle
    STA.w !Enemy_MoveAngle,X
    JSR Battle_SinLookup
    STA.b !Battle_MoveStepY
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup            ; cosine
    STA.b !Battle_MoveStepX
    LDA.b !Battle_GeoAngle
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    LDX.b !Battle_MoverEnemy
    STA.w !Battler_Facing+!Battle_FirstEnemySlot,X
    LDX.b !Battle_MoverEnemy
    CLC
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    ADC.b !Battle_MoveStepY
    STA.w !Battler_ProbeY+!Battle_FirstEnemySlot,X
    CLC
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    ADC.b !Battle_MoveStepX
    STA.w !Battler_ProbeX+!Battle_FirstEnemySlot,X
    INX
    INX
    INX
    STX.b !Battle_BoxTestSlot
    JSR Battle_CalcBattlerBox
    STZ.w !Battle_PassCellBit7
    LDA.w !Battle_MoverAnim
    CMP.b #!Enemy_MoveOrbitPass
    BNE .orbit_cells
    LDA.b #1
    STA.w !Battle_PassCellBit7
.orbit_cells:
    JSR Battle_BoxHitsBlockedCell
    BMI .orbit_blocked
    LDA.w !Battle_MoverAnim
    CMP.b #!Enemy_MoveOrbitPass
    BEQ .orbit_free
    JSR Battle_BoxOverlapsOthers
    BPL .orbit_free
.orbit_blocked:
    LDX.b !Battle_MoverEnemy
    LDA.w !Enemy_OrbitReverse,X
    EOR.b #1
    STA.w !Enemy_OrbitReverse,X
    BRA .orbit_exit
.orbit_free:
    LDX.b !Battle_MoverEnemy
    LDA.b #1
    STA.w !Enemy_Stepping,X
.orbit_exit:
    JMP .exit

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
; Callers (JSR): BattleMenu_RefreshIfDirtyL ($C1:10ED),
;   BattleMenu_RefreshIfDirtyAndTick ($C1:1104) and
;   BattleSys_UpkeepTwoFrames ($C1:10CE).
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0 (as at every caller; no DP
;        access here), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A clobbered; X = dequeued slot index (or
;        unchanged if queue was empty); Y unchanged
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
; Service 2 of the $C10045 service dispatcher (dispatch table at
; $C10051; reached only by same-bank JSR from bank $C1, see
; BattleMenu_EnqueueReadyBattler). Removes battler slot !Battle_ArgSlot
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
; Callers (JSR): BattleSys_VictoryPose ($C1:358B, $C1:3593, $C1:359B).
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0 (LDA.b !Battle_ArgSlot, STA.b $80,
;        TDC as zero), DB=$7E; !Battle_ArgSlot = slot to remove
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X clobbered; DP $80 written; Y unchanged
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
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0 (LDA.b pad edges, TDC as zero),
;        DB=$7E
; Exit:  tail-jumps to one of several handlers, does not fall through;
;        all return M=1, X=0, DP=0, DB=$7E with A, X, Y clobbered and the
;        pad edges cleared; DP: BuildTargetList's (the mode handler's DP, see its header), plus
;        CommitAction's $80/$82/$84 on confirm, plus whatever
;        Battle_PlaySfx0's Audio_ProcessEntry (not matched yet) changes
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
    BNE .hide_target_cursors
    INC.w !BattleUI_PanelRedraw     ; main menu back: redraw the command cursor
.hide_target_cursors:
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
; BattleMenu_CommitAction ($C1161A–$C1174D, 308 bytes; ends with the JMP to
; Battle_ClearPadEdges at $C1174B)
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
; Callers (JMP): BattleMenu_TargetSelectInput ($C1:15F1).
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0 (STA.b $80-$84, TDC as zero), DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X, Y
;        clobbered; DP $80, $82 and $84 written
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
; Callers (JSR): BattleMenu_CommitAction ($C1:1661, $C1:1672).
; Entry: M=1, X=0, DP=0 (reads its argument with LDA.b !BattleMenu_PartnerArg,
;        $80), DB=$7E; !BattleMenu_PartnerArg = partner PC slot
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X clobbered; Y and DP unchanged
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
; The BMI loop has no empty-list guard (BattleTgt_CycleNext has one): with
; all 11 candidates $FF it would never exit. It cannot happen as far as
; this bank shows: the only caller, TargetSelectInput, JMPs here in the
; same call right after BuildTargetList returned a non-negative
; !BattleTgt_Result, i.e. some !BattleTgt_Selected entry 0-10 is a real
; slot, and every mode handler fills Selected only with values it also
; put in Candidates 0-10. (Argued from the handlers, not proven for every
; caller of the $C10045 services that also write Candidates.)
; Callers (JMP): BattleMenu_TargetSelectInput ($C1:1605).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X
;        clobbered
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
; Same unguarded BMI loop as TargetNext, safe for the same reason.
; Callers (JMP): BattleMenu_TargetSelectInput ($C1:1614).
; Entry: M=1, X=0, DP=0 (the fall-through writes DP $EE/$EF), DB=$7E
; Exit:  falls through to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X
;        clobbered
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
; Callers (JMP): BattleMenu_ProcessInput ($C1:1178).
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0 (LDA.b pad edges, STX.b), DB=$7E
; Exit:  tail-jumps to one of several handlers, does not fall through;
;        all return M=1, X=0, DP=0, DB=$7E with A, X, Y clobbered and the
;        pad edges cleared; DP $80/$81 written here, plus the handler's
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
    AND.b #!Battle_PadConfirm
    BEQ .check_cancel
    JSR Battle_PlaySfx0
    JMP BattleMenu_TechConfirm
.check_cancel:
    LDA.b !Battle_PadEdgeButtons
    AND.b #!Battle_PadCancel
    BEQ .check_up
    JSR Battle_PlaySfx0
    JMP BattleMenu_TechListCancel
.check_up:
    LDA.b !Battle_PadEdgeDpad
    BIT.b #!Battle_DpadUp
    BNE .do_up
    AND.b #!Battle_DpadLeft
    BEQ .check_down
.do_up:
    JSR Battle_PlaySfx0
    JMP BattleMenu_TechListPrev
.check_down:
    LDA.b !Battle_PadEdgeDpad
    BIT.b #!Battle_DpadDown
    BNE .do_down
    AND.b #!Battle_DpadRight
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
; selection; if not, resets the target cursor. When the TargetMode has
; bit 7, BuildTargetList has already left the tech list before the
; missing target is noticed (Submenu = 0, !BattleMenu_ReturnSubmenu
; saved, command window reloaded), and nothing here undoes that.
; Callers (JMP): BattleMenu_TechListInput ($C1:1337).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X, Y
;        clobbered, plus BuildTargetList's (the mode handler's DP, see its header)
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
; Callers (JMP): BattleMenu_TechListInput ($C1:1343).
; Entry: M=1, X=0, DP=0 (TDC in LoadCommandWindowMap, tail ClearPadEdges), DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X
;        clobbered; no DP written besides the pad edges
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
; Callers (JMP): BattleMenu_TechListInput ($C1:1353).
; Entry: M=1, X=0, DP=0 (.b StepCount/NewRow/TechListIdx), DB=$7E;
;        !BattleMenu_TechListIdx = current line
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X, Y
;        clobbered; DP $80, $82 and $83 written
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
    BPL .store_row                  ; row still >= 0, no scroll needed
    LDA.w !Pc_TechScroll,X          ; scroll position
    BEQ .no_change                  ; already at top -> no-op
    LDA.b !BattleMenu_NewRow
    STA.w !Pc_TechRow,X
.dec_scroll:
    DEC.w !Pc_TechScroll,X
    CLC
    LDA.w !Pc_TechRow,X
    ADC #$01
.store_row:
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
; Callers (JMP): BattleMenu_TechListInput ($C1:1363).
; Entry: M=1, X=0, DP=0 (.b StepCount/NewRow/TechListIdx), DB=$7E;
;        !BattleMenu_TechListIdx = current line
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X, Y
;        clobbered; DP $80, $82 and $83 written
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
    BCC .store_row                  ; row still < 3, no scroll needed
    LDA.b !BattleMenu_NewRow
    STA.w !Pc_TechRow,X
.inc_scroll:
    INC.w !Pc_TechScroll,X          ; scroll position
    SEC
    LDA.w !Pc_TechRow,X
    SBC #$01
.store_row:
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
; Callers (JMP): BattleMenu_ProcessInput ($C1:1181).
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0 (LDA.b pad edges), DB=$7E
; Exit:  tail-jumps to one of several handlers, does not fall through;
;        all return M=1, X=0, DP=0, DB=$7E with A, X, Y clobbered and the
;        pad edges cleared; DP as in the handler that ran
; Callees: Battle_PlaySfx0, BattleMenu_ItemConfirm,
;          BattleMenu_ItemListCancel, BattleMenu_ItemCursorUp,
;          BattleMenu_ItemCursorDown, BattleMenu_ItemListPageDown,
;          BattleMenu_ItemListPageUp, BattleMenu_ItemListRefresh,
;          Battle_ClearPadEdges
org $C1143D
BattleMenu_ItemListInput:
    LDA.b !Battle_PadEdgeButtons
    AND.b #!Battle_PadConfirm
    BEQ .check_cancel
    JSR Battle_PlaySfx0
    JMP BattleMenu_ItemConfirm
.check_cancel:
    LDA.b !Battle_PadEdgeButtons
    AND.b #!Battle_PadCancel
    BEQ .check_up
    JSR Battle_PlaySfx0
    JMP BattleMenu_ItemListCancel
.check_up:
    LDA.b !Battle_PadEdgeDpad
    BIT.b #!Battle_DpadUp
    BNE .do_up
    AND.b #!Battle_DpadLeft
    BEQ .check_down
.do_up:
    JSR Battle_PlaySfx0
    JMP BattleMenu_ItemCursorUp
.check_down:
    LDA.b !Battle_PadEdgeDpad
    BIT.b #!Battle_DpadDown
    BNE .do_down
    AND.b #!Battle_DpadRight
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
; found. As in TechConfirm, a TargetMode with bit 7 has already left the
; item list (inside BuildTargetList) by the time a missing target shows.
; Callers (JMP): BattleMenu_ItemListInput ($C1:1446).
; Entry: M=1, X=0, DP=0 (STA.b Mul8A/ItemListIdx, LDX.b Mul8Product), DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X, Y
;        clobbered; DP $80 written, Battle_Mul8's $77/$78, $AD/$AE and
;        $AF/$B0, plus BuildTargetList's (the mode handler's DP, see its header)
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
; Callers (JMP): BattleMenu_ItemListInput ($C1:1452).
; Entry: M=1, X=0, DP=0 (TDC in LoadCommandWindowMap, tail ClearPadEdges), DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X
;        clobbered; no DP written besides the pad edges
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
; Callers (JMP): BattleMenu_ItemListInput ($C1:1462).
; Entry: M=1, X=0, DP=0 (the tail Battle_ClearPadEdges writes DP $EE/$EF), DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X, Y
;        clobbered; at the edge row (Scroll call), RenderItemListRows' $80-$87, $8E/$8F and $96-$98
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
; Callers (JMP): BattleMenu_ItemListInput ($C1:1472).
; Entry: M=1, X=0, DP=0 (the tail Battle_ClearPadEdges writes DP $EE/$EF), DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X, Y
;        clobbered; at the edge row (Scroll call), RenderItemListRows' $80-$87, $8E/$8F and $96-$98
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
; Callers (JMP): BattleMenu_ItemListInput ($C1:147E).
; Entry: M=1, X=0, DP=0 (STA.b !BattleMenu_ListScroll), DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X, Y
;        clobbered; RenderItemListRows' $80-$87, $8E/$8F and $96-$98
; Callees: BattleMenu_ItemListScrollDown_RenderTail, Battle_ClearPadEdges
org $C1151C
BattleMenu_ItemListPageDown:
    CLC
    LDA.w !BattleMenu_ItemScroll    ; scroll position
    ADC.b #!BattleMenu_ListRows
    CMP.b #!Item_MaxScroll
    BCS .clamp
    CMP #$00                        ; quirk: never 0 here (scroll <= $FA, so the
    BNE .have_scroll                ; sum is 3-$F9): always taken, never falls to .clamp
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
; Callers (JMP): BattleMenu_ItemListInput ($C1:148A).
; Entry: M=1, X=0, DP=0 (the clamp TDC means A=0 only because D=0, and
;        STA.b !BattleMenu_ListScroll is DP), DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X, Y
;        clobbered; RenderItemListRows' $80-$87, $8E/$8F and $96-$98
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
; Re-renders the item list rows, invalidates both draw caches and clears
; !BattleMenu_ItemRefresh. Called (JMP) by ItemListInput when
; !BattleMenu_ItemRefresh is set and no button was pressed.
; Callers (JMP): BattleMenu_ItemListInput ($C1:1492).
; Entry: M=1, X=0, DP=0 (STA.b !BattleMenu_ListScroll), DB=$7E
; Exit:  tail-jumps to Battle_ClearPadEdges: M=1, X=0, DP=0, DB=$7E; A, X, Y
;        clobbered; RenderItemListRows' $80-$87, $8E/$8F and $96-$98
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
; BattleMenu_ItemListScrollUp ($C117A1–$C117B0, 16 bytes; sub-entries
; BattleMenu_ItemListScrollUp_SetScroll $C117B1,
; BattleMenu_ItemListScrollUp_RenderTail $C117B3 and
; BattleMenu_ItemListScrollUp_SkipRender $C117B6–$C117BE)
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
; Callers (JSR): BattleMenu_ItemCursorUp ($C1:14F1).
; Entry: M=1, X=0, DP=0 (STA.b !BattleMenu_ListScroll), DB=$7E (the
;        sub-entries take the same state)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; RenderItemListRows' $80-$87, $8E/$8F and $96-$98
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
BattleMenu_ItemListScrollUp_SetScroll:      ; header: see BattleMenu_ItemListScrollUp
    STA.b !BattleMenu_ListScroll
BattleMenu_ItemListScrollUp_RenderTail:     ; header: see BattleMenu_ItemListScrollUp
    JSR BattleMenu_RenderItemListRows
BattleMenu_ItemListScrollUp_SkipRender:     ; header: see BattleMenu_ItemListScrollUp
    LDA.b #!BattleMenu_CacheInvalid
    STA.w !BattleMenu_ItemRowDrawn  ; redraw the row cursor
    STA.w !BattleMenu_ItemScrollDrawn ; and the arrows
    RTS

; ==================================================================
; BattleMenu_ItemListScrollDown ($C117BF–$C117D0, 18 bytes; sub-entries
; BattleMenu_ItemListScrollDown_RenderTail $C117D1 and
; BattleMenu_ItemListScrollDown_SkipRender $C117D4–$C117DC)
; ==================================================================
; Scrolls the item list down one row: increments !BattleMenu_ItemScroll (clamped at
; $FA), then re-renders and invalidates both draw caches.
; Mirror of ItemListScrollUp, but with a single, genuinely-reachable
; bounds check instead of the redundant double branch — when already
; at the clamp, skips both the increment AND the render entirely.
; BattleMenu_ItemListScrollDown_RenderTail is the external entry point
; called directly by BattleMenu_ItemListPageDown.
; Callers (JSR): BattleMenu_ItemCursorDown ($C1:1509).
; Entry: M=1, X=0, DP=0 (STA.b !BattleMenu_ListScroll), DB=$7E (the
;        sub-entries take the same state)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; RenderItemListRows' $80-$87, $8E/$8F and $96-$98
;        (none when already at $FA)
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
BattleMenu_ItemListScrollDown_RenderTail:   ; header: see BattleMenu_ItemListScrollDown
    JSR BattleMenu_RenderItemListRows
BattleMenu_ItemListScrollDown_SkipRender:   ; header: see BattleMenu_ItemListScrollDown
    LDA.b #!BattleMenu_CacheInvalid
    STA.w !BattleMenu_ItemRowDrawn  ; redraw the row cursor
    STA.w !BattleMenu_ItemScrollDrawn ; and the arrows
    RTS

; ==================================================================
; BattleMenu_UpdateCursorOverlay ($C117DD–$C11B18, 828 bytes)
; ==================================================================
; Cursor/overlay refresh at the end of the menu rebuild chain (after
; ProcessInput), so like it only on frames with !BattleMenu_Dirty set:
; JSR from BattleMenu_RefreshIfDirtyL, BattleMenu_RefreshIfDirtyAndTick
; and BattleSys_UpkeepTwoFrames ($C1:10D7). Draws whatever cursor
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
; (with, while !BattleMenu_Submenu = 0, an info-panel message for an
; enemy target through BattleMsg_ShowMsg0BIfKeyChangedVec /
; BattleMsg_UnkVecCD0030),
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
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0 (TDC as zero; STZ.b/STY.b), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; pad-edge bytes cleared (shared tail, same as
;        Battle_ClearPadEdges elsewhere); A, X, Y clobbered; DP $80-$83 and
;        $EC written, plus whatever the JSL targets (not matched yet) change
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
; Tech-list cursor ($17FE-$18AF)
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
    ; enemy target with Submenu 0: the attack row, or a tech/item whose
    ; target mode has bit 7 (BuildTargetList closed the submenu for it).
    ; Info-panel message.
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
; alternates 3 / 0). Entries 6-10 are never reached by this sweep.
; The loop has two exits, but with a start index of 0 or 3 the index cap
; (SweepBatch 3 / SweepWrap 6) always fires after 3 steps, when the
; sprite index has only reached 3; the BattleOam_CursorSprites test never
; ends the loop. 0 and 3 are the only values stored to $960B (its one
; writer is the STA below, checked across banks $C0-$CF); its first value
; comes from the battle RAM set-up, which is not matched yet.
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
