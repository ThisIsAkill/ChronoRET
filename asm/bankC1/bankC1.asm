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
; Battle_RunPcPose, BattleSys_RunAction ($C1:405F, $C1:40A0, $C1:40B0,
; $C1:40E1, $C1:4116, $C1:414B, $C1:41B4, $C1:41B7), BattleAct_LoadCommon
; ($C1:4841, $C1:485B, $C1:4864, $C1:488D) and BattleAct_UnpackFrames
; ($C1:4943).
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
;   Battle_ShiftLeft3: Battle_TickEnemyGroup ($C1:3410, $C1:3471),
;     BattleAct_LoadCommon ($C1:48BA)
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
; plain RTS. Runs right after each frame wait in service 4
; (BattleSys_RunAction) and its loaders BattleAct_LoadCommon and
; BattleAct_UnpackFrames.
; Callers (7 JSR sites): BattleSys_RunAction ($C1:40A3, $C1:40B6,
;   $C1:40E4), BattleAct_LoadCommon ($C1:485E, $C1:4867, $C1:4890) and
;   BattleAct_UnpackFrames ($C1:4946).
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
; Callers (JSR; scanned as above): BattleSys_RunAction ($C1:4127), which
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
; from the caller (BattleSys_Main at $C1:815F, which first runs
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
; (BattleSys_Main at $C1:8186 runs it when each of the 8 !Battler_UnkAEFF
; enemy bytes is $FF or has !Battle_UnkAF15 bit 6 set, presumably no
; enemy left).
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
; Battle_MoverLoop ($C13E33–$C13F59, 295 bytes)
; ==================================================================
; Mover 6 (moves $0A-$0C): flies round a loop near where it started. On
; the first run (!Enemy_LoopStarted clear) the loop is set up: centre =
; the enemy's position + 16 pixels down, phase $C0 (straight up),
; forwards. Each run moves the phase on by $10 (back by $10 when
; !Enemy_LoopReverse is set) and heads from the enemy's position for the
; point of an ellipse round the centre at that phase: vertical radius
; !Battle_LoopRadius = $20 (move $0A: $10), horizontal radius $20 more.
; If the step is blocked (move $0C passes cell bit 7 and other
; battlers), the phase jumps back $58 against the direction of travel
; (move $0A: $30) and the direction reverses, without a step; otherwise
; the step starts. The move never ends.
; The other movers clear !Enemy_LoopStarted, except
; Battle_MoverFixedDir and Battle_MoverToCentre, so after one of those
; the loop goes on round the old centre.
; Callers: Battle_EnemyMoverTable entry 6.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_MoverEnemy = enemy (0-7),
;        !Battle_MoverAnim
; Exit:  M=1, X=0, DP=0, DB=$7E; A, Y clobbered; X and
;        !Battle_BoxTestSlot = the enemy's battler slot; DP $80-$86,
;        $8C-$8F, $77-$78, $A5-$AE and $D3-$E3 written
; Callees: Battle_SinLookup, Battle_CalcAngle, Battle_CalcBattlerBox,
;          Battle_BoxHitsBlockedCell, Battle_BoxOverlapsOthers
!Battle_LoopBounceBy = !BattleTmp_82      ; 1 B: phase jump when blocked ($58 or $30)
Battle_MoverLoop:
    LDX.b !Battle_MoverEnemy
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    STA.w !Enemy_StepStartX,X
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    STA.w !Enemy_StepStartY,X
    LDA.w !Enemy_LoopStarted,X
    BNE .started
    INC.w !Enemy_LoopStarted,X
    CLC
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    ADC.b #!Battle_LoopDropY
    STA.w !Enemy_LoopCentreY,X
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    STA.w !Enemy_LoopCentreX,X
    LDA.b #!Battle_AngleThreeQuarter ; up
    STA.w !Enemy_LoopPhase,X
    STZ.w !Enemy_LoopReverse,X
.started:
    LDA.w !Enemy_LoopReverse,X
    BNE .backwards
    LDA.b #!Battle_LoopTurn
    BRA .turn
.backwards:
    LDA.b #!Battle_LoopTurnBack
.turn:
    CLC
    ADC.w !Enemy_LoopPhase,X
    STA.w !Enemy_LoopPhase,X
    STA.b !Battle_GeoAngle
    LDA.b #!Battle_LoopRadiusBig
    STA.w !Battle_LoopRadius
    LDA.w !Battle_MoverAnim
    CMP.b #!Enemy_MoveLoopSmall
    BNE .radius_set
    LSR.w !Battle_LoopRadius
.radius_set:
    LDA.w !Battle_LoopRadius
    STA.b !Battle_SinScale
    LDA.b !Battle_GeoAngle
    JSR Battle_SinLookup
    LDX.b !Battle_MoverEnemy
    CLC
    ADC.w !Enemy_LoopCentreY,X
    STA.b !Battle_GeoPointY
    CLC
    LDA.w !Battle_LoopRadius
    ADC.b #!Battle_LoopRadiusBig    ; wider than high
    STA.b !Battle_SinScale
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup            ; cosine
    LDX.b !Battle_MoverEnemy
    CLC
    ADC.w !Enemy_LoopCentreX,X
    STA.b !Battle_GeoPointX
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    STA.b !Battle_GeoOriginX
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    STA.b !Battle_GeoOriginY
    LDA.b #!Battle_MoveStepLen
    STA.b !Battle_SinScale
    JSR Battle_CalcAngle            ; enemy -> loop point
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
    CMP.b #!Enemy_MoveLoopPass
    BNE .test_cells
    LDA.b #1
    STA.w !Battle_PassCellBit7
.test_cells:
    JSR Battle_BoxHitsBlockedCell
    BMI .blocked
    LDA.w !Battle_MoverAnim
    CMP.b #!Enemy_MoveLoopPass
    BEQ .free                       ; move $0C passes other battlers
    JSR Battle_BoxOverlapsOthers
    BPL .free
.blocked:
    LDA.b #!Battle_LoopBounce
    STA.b !Battle_LoopBounceBy
    LDA.w !Battle_MoverAnim
    CMP.b #!Enemy_MoveLoopSmall
    BNE .bounce
    LDA.b #!Battle_LoopBounceSmall
    STA.b !Battle_LoopBounceBy
.bounce:
    LDX.b !Battle_MoverEnemy
    LDA.w !Enemy_LoopReverse,X
    BNE .bounce_forwards
    SEC
    LDA.w !Enemy_LoopPhase,X
    SBC.b !Battle_LoopBounceBy
    BRA .set_phase
.bounce_forwards:
    CLC
    LDA.w !Enemy_LoopPhase,X
    ADC.b !Battle_LoopBounceBy
.set_phase:
    STA.w !Enemy_LoopPhase,X
    LDA.w !Enemy_LoopReverse,X
    EOR.b #1
    STA.w !Enemy_LoopReverse,X
    BRA .exit
.free:
    LDX.b !Battle_MoverEnemy
    LDA.b #1
    STA.w !Enemy_Stepping,X
.exit:
    LDX.b !Battle_MoverEnemy
    INX
    INX
    INX
    STX.b !Battle_BoxTestSlot
    RTS

; ==================================================================
; Battle_MoverFixedDir ($C13F5A–$C14020, 199 bytes)
; ==================================================================
; Mover 7 (moves $11-$18): steps in a fixed direction from the enemy's
; position: $11 up, $12 down, $13 right, $14 left, $15 down-right, $16
; down-left, $17 up-left, any other (move $18) up-right. Straight moves
; face as !BattleRom_FacingByAngle says; the diagonals, exactly on that
; table's boundaries, are given the facing of the angle just below
; instead (right, down, left, up). The step starts at once; when it is
; blocked (a blocking cell or another battler) it is cancelled and
; !Enemy_MoveDone counted up. Unlike the done path of the other movers,
; this one saves neither !Enemy_ResumeAnim nor the target's position.
; Quirk: the last case ends with a BRA to the very next instruction.
; Callers: Battle_EnemyMoverTable entry 7.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_MoverEnemy = enemy (0-7),
;        !Battle_MoverAnim
; Exit:  M=1, X=0, DP=0, DB=$7E; A, Y clobbered; X and
;        !Battle_BoxTestSlot = the enemy's battler slot; DP $80-$86,
;        $8C-$8F, $77-$78 and $A5-$AE written
; Callees: Battle_SinLookup, Battle_CalcBattlerBox,
;          Battle_BoxHitsBlockedCell, Battle_BoxOverlapsOthers
!Battle_MoveFacing = !BattleTmp_80        ; 1 B: facing to force, or !Battle_FacingFromAngle
Battle_MoverFixedDir:
    LDX.b !Battle_MoverEnemy
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    STA.w !Enemy_StepStartX,X
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    STA.w !Enemy_StepStartY,X
    LDA.b #!Battle_FacingFromAngle
    STA.b !Battle_MoveFacing
    LDA.w !Battle_MoverAnim
    CMP.b #!Enemy_MoveUp
    BNE .not_up
    LDA.b #!Battle_AngleThreeQuarter
    BRA .set_angle
.not_up:
    CMP.b #!Enemy_MoveDown
    BNE .not_down
    LDA.b #!Battle_AngleQuarter
    BRA .set_angle
.not_down:
    CMP.b #!Enemy_MoveRight
    BNE .not_right
    TDC
    BRA .set_angle
.not_right:
    CMP.b #!Enemy_MoveLeft
    BNE .not_left
    LDA.b #!Battle_AngleHalfTurn
    BRA .set_angle
.not_left:
    CMP.b #!Enemy_MoveDownRight
    BNE .not_down_right
    LDA.b #!Battle_FacingRight
    STA.b !Battle_MoveFacing
    LDA.b #!Battle_AngleEighth
    BRA .set_angle
.not_down_right:
    CMP.b #!Enemy_MoveDownLeft
    BNE .not_down_left
    LDA.b #!Battle_FacingDown
    STA.b !Battle_MoveFacing
    LDA.b #!Battle_AngleQuarter+!Battle_AngleEighth
    BRA .set_angle
.not_down_left:
    CMP.b #!Enemy_MoveUpLeft
    BNE .up_right
    LDA.b #!Battle_FacingLeft
    STA.b !Battle_MoveFacing
    LDA.b #!Battle_AngleHalfTurn+!Battle_AngleEighth
    BRA .set_angle
.up_right:
    STZ.b !Battle_MoveFacing        ; !Battle_FacingUp
    LDA.b #!Battle_AngleThreeQuarter+!Battle_AngleEighth
    BRA .set_angle                  ; quirk: the next instruction
.set_angle:
    STA.w !Enemy_MoveAngle,X
    STA.b !Battle_GeoAngle
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    LDX.b !Battle_MoverEnemy
    STA.w !Battler_Facing+!Battle_FirstEnemySlot,X
    LDA.b !Battle_MoveFacing
    BMI .facing_set
    STA.w !Battler_Facing+!Battle_FirstEnemySlot,X
.facing_set:
    LDA.b #!Battle_MoveStepLen
    STA.b !Battle_SinScale
    LDA.b !Battle_GeoAngle
    JSR Battle_SinLookup
    STA.b !Battle_MoveStepY
    CLC
    LDA.b !Battle_GeoAngle
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup            ; cosine
    STA.b !Battle_MoveStepX
    LDX.b !Battle_MoverEnemy
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
    BMI .blocked
    JSR Battle_BoxOverlapsOthers
    BPL .exit
.blocked:
    LDX.b !Battle_MoverEnemy
    STZ.w !Enemy_Stepping,X
    INC.w !Enemy_MoveDone,X
.exit:
    LDX.b !Battle_MoverEnemy
    INX
    INX
    INX
    STX.b !Battle_BoxTestSlot
    RTS

; ==================================================================
; Battle_MoverToCentre ($C14021–$C14057, 55 bytes)
; ==================================================================
; Mover 8 (move $19): heads from the enemy's position for the middle of
; the screen (!Battle_ScreenCentreX/Y), faces that way and starts the
; step, with no probe and no collision test. The move never ends.
; Callers: Battle_EnemyMoverTable entry 8.
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_MoverEnemy = enemy (0-7)
; Exit:  M=1, X=0, DP=0, DB=$7E; A clobbered; Y unchanged; X and
;        !Battle_BoxTestSlot = the enemy's battler slot; DP $D3-$E3
;        written
; Callees: Battle_CalcAngle
Battle_MoverToCentre:
    LDX.b !Battle_MoverEnemy
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    STA.w !Enemy_StepStartX,X
    STA.b !Battle_GeoOriginX
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    STA.w !Enemy_StepStartY,X
    STA.b !Battle_GeoOriginY
    LDA.b #!Battle_ScreenCentreX
    STA.b !Battle_GeoPointX
    LDA.b #!Battle_ScreenCentreY
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle
    LDX.b !Battle_MoverEnemy
    STA.w !Enemy_MoveAngle,X
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    LDX.b !Battle_MoverEnemy
    STA.w !Battler_Facing+!Battle_FirstEnemySlot,X
    LDA.b #1
    STA.w !Enemy_Stepping,X
    INX
    INX
    INX
    STX.b !Battle_BoxTestSlot
    RTS

; ==================================================================
; Actions: service 4 and its frame helpers ($C1:4058–$C1:432B)
; ==================================================================
; Service 4 of the $C10045 API plays one action (an attack, a tech or
; the like; "action" is inferred from the records it loads, see
; BattleAct_LoadScript): it loads the action's script, graphics and
; palette steps, then runs the script frame by frame until the script
; says it has ended. The action is described by the block at
; !Battle_ActCaster..!Battle_ActUnkAE9B, which the unmatched code at
; $C1:ACF0 fills from the chosen command (caster from $B18B, kind and
; id from $AEE3/$AEE4, target masks built from the target list at
; $AECC). The script interpreter itself (the threads that
; BattleAct_RunThreads at $C1:4BBE runs) is not matched yet.

; ==================================================================
; BattleSys_RunAction ($C14058–$C141BD, 358 bytes)
; ==================================================================
; Service 4 of the cross-bank $C10045 service API (dispatch table at
; $C10051, entry 4 = $4058; no JSR, JMP or JSL reaches $4058 directly;
; the one request found is LDA #4 / JSR $C1:0003 at $C1:BFA4, called
; from $C1:AC57). Plays the action in !Battle_ActCaster.. (see the
; banner):
;   1. counts !Battle_UnkA0FD up, resets the action state
;      (BattleAct_ResetState) and waits a frame. Three ROM bytes at
;      $CF:FFFD-$CF:FFFF can force !Battle_ActUnkAE9B / !Battle_ActFlags
;      (they look like build switches; all three are 0 in this ROM, so
;      none applies);
;   2. keeps !Battle_UnkA4 on the stack, takes !Battle_ActSecondGroup
;      from bit 6 of !Battle_ActFlags, sets every !Battler_FxApplied to
;      $55 (BattleAct_ResetFxApplied), marks the action running
;      (!Battle_ActRunning), builds the battler lists
;      (BattleAct_BuildBattlerList) and loads the script
;      (BattleAct_LoadScript);
;   3. runs one script frame per frame (battler animations, the menu, timers,
;      palette steps, the per-entry calculations, the occupied-cell map,
;      the probes, the script threads) until !Battle_ActScriptDone;
;   4. sends APU command $18 with parameter $FF, then waits until
;      !Battle_Unk5D9B is 0;
;   5. restores !Battle_UnkA4, clears !Battle_UnkAB4E and 40 bytes from
;      !Battle_ActUnkA1A8, and, for each enemy in !Battle_ActBattlers,
;      takes its screen position as the start of its next step
;      (!Enemy_StepStartX/Y; inferred: so the stepper does not pull it
;      back to where it was before the action);
;   6. waits a frame, resets the action state again, and runs
;      Battle_PickNextStatusAnim from slot 0 until it wraps once (every
;      battler's status animation picked again), keeping
;      !Battle_StatusAnimNext;
;   7. if a PC is among the targets (!Battle_ActTargets), flags each PC
;      whose pending damage reaches its HP (BattleAct_FlagLethalPcHits)
;      and draws such a PC's frame from !BattleRom_PcKoFrame (character
;      * 4 + facing), clearing its !Battler_UnkA119 again; sets
;      !Battle_UnkA118 to 2 and waits two frames;
;   8. clears !Battle_ActRunning.
; Quirk: the TAX that takes bit 6 copies the whole 16-bit accumulator,
; and the loaders test !Battle_ActSecondGroup 16-bit while clearing only
; its low byte, so the high byte of A here matters; it comes from the
; callees before (not established, presumably 0).
; Entry: M=1, X=0, DP=0, DB=$7E (through the dispatcher, which saves A,
;        X and Y around the call)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; !Battle_UnkA4 as
;        on entry; the callees' DP scratch written
; Callees: BattleAct_ResetState, BattleSys_PumpFrames,
;          BattleAct_ResetFxApplied, BattleMenu_RefreshIfDirtyAndTick,
;          BattleAct_BuildBattlerList, BattleAct_LoadScript,
;          BattleAct_StepBattlerAnims, BattleAct_TickUnkA1A8,
;          BattleAct_StepPalettes, BattleAct_TickCalcs,
;          Battle_BuildOccupiedCellMap, Battle_CacheBattlerCoordsAll,
;          BattleAct_RunThreads, Audio_ProcessEntry,
;          Battle_PickNextStatusAnim, BattleAct_FlagLethalPcHits,
;          Battle_DrawBattlerFrame
BattleSys_RunAction:
    INC.w !Battle_UnkA0FD
    JSL BattleAct_ResetState
    JSR BattleSys_PumpFrames
    STZ.b !Battle_UnkE5
    LDA.l !BattleRom_ActForceAlt
    BEQ .switch2
    LDA.b #!Battle_ActAltFlag
    STA.w !Battle_ActUnkAE9B
    STZ.w !Battle_ActFlags
    BRA .run
.switch2:
    LDA.l !BattleRom_ActForceSecond
    BEQ .switch3
    LDA.b #!Battle_ActFlagSecond
    STA.w !Battle_ActFlags
    STZ.w !Battle_ActUnkAE9B
    BRA .run
.switch3:
    LDA.l !BattleRom_ActForceNone
    BEQ .run
    STZ.w !Battle_ActUnkAE9B
    STZ.w !Battle_ActFlags
.run:
    LDA.b !Battle_UnkA4
    PHA
    LDA.w !Battle_ActFlags
    AND.b #!Battle_ActFlagSecond
    TAX                             ; quirk: also copies B (see header)
    STX.w !Battle_ActSecondGroup
    JSL BattleAct_ResetFxApplied
    JSR BattleSys_PumpFrames
    JSR BattleMenu_RefreshIfDirtyAndTick
    INC.w !Battle_ActRunning
    JSL BattleAct_BuildBattlerList
    JSR BattleAct_LoadScript
.frame:
    JSR BattleSys_PumpFrames
    JSR BattleAct_StepBattlerAnims
    JSR BattleMenu_RefreshIfDirtyAndTick
    JSL BattleAct_TickUnkA1A8
    JSL BattleAct_StepPalettes
    JSR BattleAct_TickCalcs
    JSL Battle_BuildOccupiedCellMap
    JSR Battle_CacheBattlerCoordsAll
    JSR BattleAct_RunThreads
    LDA.w !Battle_ActScriptDone
    BEQ .frame
    LDA.b #!Sfx_Unk18Arg
    STA.w !Sfx_Param1
    LDA.b #!Sfx_CmdUnk18
    STA.w !Sfx_Command
    JSL Audio_ProcessEntry
.wait_5d9b:
    JSR BattleSys_PumpFrames
    JSR BattleMenu_RefreshIfDirtyAndTick
    LDA.w !Battle_Unk5D9B
    BNE .wait_5d9b
    PLA
    STA.b !Battle_UnkA4
    STZ.w !Battle_UnkAB4E
    LDX.w #!Battle_ActUnkA1A8Cleared-1
.clear_a1a8:
    STZ.w !Battle_ActUnkA1A8,X
    DEX
    BPL .clear_a1a8
    TDC
    TAX
.battler:
    LDA.w !Battle_ActBattlers,X
    BMI .battlers_done
    CMP.b #!Battle_FirstEnemySlot
    BCC .battler_next               ; a PC
    TAY
    LDA.w !Battler_ScreenX,Y
    STA.w !Enemy_StepStartX-!Battle_FirstEnemySlot,Y
    LDA.w !Battler_ScreenY,Y
    STA.w !Enemy_StepStartY-!Battle_FirstEnemySlot,Y
.battler_next:
    INX
    BRA .battler
.battlers_done:
    JSR BattleSys_PumpFrames
    JSL BattleAct_ResetState
    LDA.w !Battle_StatusAnimNext
    PHA
    STZ.w !Battle_StatusAnimNext
    STZ.w !Battle_StatusAnimWraps
.status_pass:
    JSR Battle_PickNextStatusAnim
    LDA.w !Battle_StatusAnimWraps
    BEQ .status_pass
    PLA
    STA.w !Battle_StatusAnimNext
    STZ.w !Battle_ActFrameHold
    TDC
    TAX
.target:
    LDA.w !Battle_ActTargets,X
    BMI .exit                       ; no PC among the targets
    BEQ .pc_hit
    DEC A
    BEQ .pc_hit
    DEC A
    BEQ .pc_hit
    INX
    BRA .target
.pc_hit:
    JSR BattleAct_FlagLethalPcHits
    JSR BattleSys_PumpFrames
    LDA.w !Battler_UnkA119
    BEQ .pc1
    STZ.w !Battler_UnkA119
    STZ.w !Battle_FrameSlot         ; PC 0
    LDA.w !Pc_CharId
    ASL A
    ASL A
    CLC
    ADC.w !Battler_Facing
    TAX
    LDA.l !BattleRom_PcKoFrame,X
    STA.w !Battle_FrameId
    JSR Battle_DrawBattlerFrame
.pc1:
    LDA.w !Battler_UnkA119+1
    BEQ .pc2
    STZ.w !Battler_UnkA119+1
    LDA.b #1
    STA.w !Battle_FrameSlot
    LDA.w !Pc_CharId+1
    ASL A
    ASL A
    CLC
    ADC.w !Battler_Facing+1
    TAX
    LDA.l !BattleRom_PcKoFrame,X
    STA.w !Battle_FrameId
    JSR Battle_DrawBattlerFrame
.pc2:
    LDA.w !Battler_UnkA119+2
    BEQ .settle
    STZ.w !Battler_UnkA119+2
    LDA.b #2
    STA.w !Battle_FrameSlot
    LDA.w !Pc_CharId+2
    ASL A
    ASL A
    CLC
    ADC.w !Battler_Facing+2
    TAX
    LDA.l !BattleRom_PcKoFrame,X
    STA.w !Battle_FrameId
    JSR Battle_DrawBattlerFrame
.settle:
    LDA.b #2
    STA.w !Battle_UnkA118
    JSR BattleSys_PumpFrames
    JSR BattleSys_PumpFrames
.exit:
    STZ.w !Battle_ActRunning
    RTS

; ==================================================================
; BattleAct_FlagLethalPcHits ($C141BE–$C14211, 84 bytes)
; ==================================================================
; For each PC 0-2, sets its !Battler_UnkA119 to 1 when its pending hit
; record (!Battle_ActPcHitAmount/Kind, 4 bytes per PC) has kind 3, the
; PC's HP is not 0, the amount is not 0 and the amount is at least the
; HP; otherwise to 0. "Hit" and "lethal" are inferred from the amount
; being compared with BattlerStats.CurHp and from Battle_PickStatusAnim
; treating a flagged battler as KO'd; what kind 3 means is not known.
; The counters are bumped with a 16-bit INC (DP $82 + PC), which cannot
; carry since each is bumped at most once.
; Quirk: the kind is tested for 0 before it is compared with 3, which
; changes nothing.
; Callers (JSR): BattleSys_RunAction ($C1:4148) only.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A = PC 2's flag; X, Y clobbered; DP
;        $80-$85 written
!BattleAct_HitPc = !BattleTmp_80        ; 2 B: PC 0-2 being checked (16-bit)
!BattleAct_HitFlags = !BattleTmp_82     ; 3 B: flag per PC ($82-$84), copied to !Battler_UnkA119
BattleAct_FlagLethalPcHits:
    TDC
    TAX
    TAY
    STY.b !BattleAct_HitPc
    STY.b !BattleAct_HitFlags
    STY.b !BattleAct_HitFlags+2
    REP #$20
.pc:
    LDA.b !BattleAct_HitPc
    XBA
    LSR A
    TAX                             ; PC * $80: its BattlerStats offset
    LDA.w !Battle_ActPcHitKind,Y
    BEQ .next                       ; quirk: 0 is not 3 either
    CMP.w #!Battle_ActHitKind3
    BNE .next
    LDA.w BattlerStats.CurHp,X
    BEQ .next
    LDA.w !Battle_ActPcHitAmount,Y
    BEQ .next
    EOR.w #!Battle_Invert16
    INC A
    CLC
    ADC.w BattlerStats.CurHp,X      ; HP - amount
    BEQ .lethal
    BCS .next                       ; HP > amount
.lethal:
    LDX.b !BattleAct_HitPc
    INC.b !BattleAct_HitFlags,X
.next:
    INY
    INY
    INY
    INY
    INC.b !BattleAct_HitPc
    LDA.b !BattleAct_HitPc
    CMP.w #!Battle_NumPcSlots
    BNE .pc
    TDC
    SEP #$20
    LDA.b !BattleAct_HitFlags
    STA.w !Battler_UnkA119
    LDA.b !BattleAct_HitFlags+1
    STA.w !Battler_UnkA119+1
    LDA.b !BattleAct_HitFlags+2
    STA.w !Battler_UnkA119+2
    RTS

; ==================================================================
; BattleAct_TickCalcs ($C14212–$C14239, 40 bytes)
; ==================================================================
; For each of the 6 entries of !Battle_ActCalcSel that is non-zero, runs
; handler (value - 1) of the unmatched table behind BattleAct_RunCalc
; and stores the two bytes it leaves in !Battle_ActCalcOutA/B into the
; entry's pair at !Battle_ActCalcResult. What the handlers compute is
; not analysed (the entries are set by the script code, presumably).
; Callers (JSR): BattleSys_RunAction ($C1:40C1) only.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X clobbered; Y unchanged
;        (BattleAct_RunCalc keeps X and Y); DP $90-$91 written
; Callees: BattleAct_RunCalc
!BattleAct_CalcIdx = !BattleTmp_90      ; 2 B: entry 0-5 (zeroed 16-bit, counted 8-bit)
BattleAct_TickCalcs:
    TDC
    TAX
    STX.b !BattleAct_CalcIdx
.entry:
    LDX.b !BattleAct_CalcIdx
    LDA.w !Battle_ActCalcSel,X
    BEQ .next
    DEC A
    JSR BattleAct_RunCalc
    LDA.b !BattleAct_CalcIdx
    ASL A
    TAX
    LDA.w !Battle_ActCalcOutA
    STA.w !Battle_ActCalcResult,X
    LDA.w !Battle_ActCalcOutB
    STA.w !Battle_ActCalcResult+1,X
.next:
    INC.b !BattleAct_CalcIdx
    LDA.b !BattleAct_CalcIdx
    CMP.b #!Battle_ActCalcEntries
    BNE .entry
    RTS

; ==================================================================
; BattleAct_StepBattlerAnims ($C1423A–$C1430F, 214 bytes)
; ==================================================================
; Plays the battlers' action animations, decoding at most one frame per
; call. First counts every non-zero !Battler_ActAnimTimer down. Then,
; starting at !Battle_ActAnimNextSlot and going round all 11 slots, looks
; for a battler whose animation is on (!Battler_ActAnimMode) and whose
; timer has run out. If none, or while !Battle_UnkA028 or
; !Battle_ActFrameHold is set, it does nothing more. Otherwise, for that
; battler (and the search starts after it next time):
;   - remembers its facing in !Battler_ActFacing and takes facing *
;     facing stride, as Battle_TickPcSlots does;
;   - moves !Battler_ActAnimEntry on by one; if !Battler_ActAnimStop is
;     non-zero, the entry becomes that value - 1 and the animation is
;     switched off (the frame is still drawn);
;   - reads the entry's duration from the battler's duration list
;     (!Battle_AnimDurList, 2 bytes per slot here, in bank $E4). A
;     duration of 0 ends the list: mode 2 starts again at entry 0
;     (a list starting with 0 would loop for ever), any other mode is
;     switched off and nothing is drawn;
;   - else sets the timer to the duration (not divided by 5, unlike
;     Battle_TickPcSlots), decodes the entry's frame id from the frame
;     list (!Battle_AnimFrameList + facing offset) with
;     Battle_DrawBattlerFrame, and sets !Battle_ActFrameHold to 2.
; The modes and lists are set by code not matched yet (the script
; threads, presumably); "mode 2 = loop" is read from this routine only.
; Quirk: when the facing equals !Battler_ActFacing it is loaded again
; from there, the same value.
; Callers (JSR): BattleSys_RunAction ($C1:40B3) only.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; when a frame was
;        drawn, DP $80-$83, the multiply's $A5-$AB and
;        Battle_DrawBattlerFrame's scratch written
; Callees: Battle_Mul8x16, Battle_DrawBattlerFrame
!BattleAct_AnimSlot = !BattleTmp_80     ; 1 B: battler slot being stepped
!BattleAct_AnimFacingOfs = !BattleTmp_82 ; 2 B: facing * facing stride
BattleAct_StepBattlerAnims:
    TDC
    TAX
.count_down:
    LDA.w !Battler_ActAnimTimer,X
    BEQ .count_next
    DEC.w !Battler_ActAnimTimer,X
.count_next:
    INX
    CPX.w #!Battle_NumSlots
    BNE .count_down
    TDC
    TAY
    LDA.w !Battle_ActAnimNextSlot
    TAX
.find:
    LDA.w !Battler_ActAnimMode,X
    BEQ .find_next
    LDA.w !Battler_ActAnimTimer,X
    BEQ .found
.find_next:
    INX
    CPX.w #!Battle_NumSlots
    BNE .find_count
    TDC
    TAX
.find_count:
    INY
    CPY.w #!Battle_NumSlots
    BNE .find
.exit:
    RTS
.found:
    LDA.w !Battle_UnkA028
    BNE .exit
    LDA.w !Battle_ActFrameHold
    BNE .exit
    STX.b !BattleAct_AnimSlot
    INX
    CPX.w #!Battle_NumSlots
    BNE .next_slot
    TDC
    TAX
.next_slot:
    TXA
    STA.w !Battle_ActAnimNextSlot
    LDX.b !BattleAct_AnimSlot
    LDA.w !Battler_Facing,X
    CMP.w !Battler_ActFacing,X
    BEQ .same_facing
    STA.w !Battler_ActFacing,X
    BRA .facing
.same_facing:
    LDA.w !Battler_ActFacing,X      ; quirk: the value A already holds
.facing:
    STA.b !Battle_MulFactor8
    LDA.w !Battler_FacingStrideLo,X
    STA.b !Battle_MulFactor16
    LDA.w !Battler_FacingStrideHi,X
    STA.b !Battle_MulFactor16+1
    JSR Battle_Mul8x16
    LDX.b !Battle_MulProduct
    STX.b !BattleAct_AnimFacingOfs
    LDA.b !BattleAct_AnimSlot
    STA.w !Battle_FrameSlot
    ASL A
    TAY                             ; slot * 2: its list offsets
    LDX.b !BattleAct_AnimSlot
    CLC
    LDA.w !Battler_ActAnimEntry,X
    ADC.b #1
    STA.w !Battler_ActAnimEntry,X
    LDA.w !Battler_ActAnimStop,X
    BEQ .duration
    DEC A
    STA.w !Battler_ActAnimEntry,X
    STZ.w !Battler_ActAnimMode,X
.duration:
    LDA.w !Battler_ActAnimEntry,X
    REP #$21                        ; A -> 16-bit, carry clear
    ADC.w !Battle_AnimDurList,Y
    TAX
    TDC
    SEP #$20
    LDA.l !BattleRom_AnimData,X
    BNE .draw
    LDX.b !BattleAct_AnimSlot
    LDA.w !Battler_ActAnimMode,X
    CMP.b #!Battle_ActAnimLoop
    BEQ .restart
    STZ.w !Battler_ActAnimMode,X
    BRA .done
.restart:
    LDX.b !BattleAct_AnimSlot
    TDC
    STA.w !Battler_ActAnimEntry,X
    BRA .duration
.draw:
    LDX.b !BattleAct_AnimSlot
    STA.w !Battler_ActAnimTimer,X
    LDA.w !Battler_ActAnimEntry,X
    REP #$21                        ; A -> 16-bit, carry clear
    ADC.b !BattleAct_AnimFacingOfs
    CLC
    ADC.w !Battle_AnimFrameList,Y
    TAX
    TDC
    SEP #$20
    LDA.l !BattleRom_AnimData,X     ; frame id
    STA.w !Battle_FrameId
    JSR Battle_DrawBattlerFrame
    LDA.b #2
    STA.w !Battle_ActFrameHold
.done:
    RTS

; ==================================================================
; BattleAct_LoadScript ($C14310–$C1432B, 28 bytes)
; ==================================================================
; Clears the 16-byte action parameter block (!Battle_ActScriptId ..
; $9886), sets !Battle_ActUnkArg987C to $FF (none) and calls the loader
; for !Battle_ActKind through BattleAct_LoaderTable (kinds 4 and up are
; taken as 0, which loads nothing). The loaders fill the parameter
; block from the action's records and start the script threads.
; Callers (JSR): BattleSys_RunAction ($C1:40AD) only.
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  as the loader (kind 0: A, X clobbered, nothing else)
; Callees: JSR (BattleAct_LoaderTable,X)
BattleAct_LoadScript:
    LDX.w #!Battle_ActParamsLen-1
.clear:
    STZ.w !Battle_ActScriptId,X
    DEX
    BPL .clear
    LDA.b #!Battle_ActArgNone
    STA.w !Battle_ActUnkArg987C
    LDA.w !Battle_ActKind
    CMP.b #!Battle_ActNumKinds
    BCC .dispatch
    TDC                             ; unknown kind: as kind 0
.dispatch:
    ASL A
    TAX
    JSR (BattleAct_LoaderTable,X)
    RTS

; ==================================================================
; Action loaders ($C1:432C–$C1:49FE)
; ==================================================================
; BattleAct_LoadScript calls one loader per !Battle_ActKind. Each reads
; the action's record: a script number (!Battle_ActScriptId), two
; graphics set numbers (!Battle_ActGfxSetA/B), and indexes of the
; compressed sprite frames, the palette steps and the object lists
; (!Battle_ActFramesIdx, !Battle_ActPalIdx, !Battle_ActObjIdx), which it
; turns into pointers through the matching tables. Then it starts the
; script's threads. A script begins with a 4-byte header: two 16-bit
; thread masks stored high byte first; bit 15 down to bit 0 stand for
; threads 0-15. The thread offsets follow, one word per set bit, first
; group's then second group's. For each set bit of the first group (or,
; when !Battle_ActSecondGroup is set, of the second group only) the
; thread gets !Battle_ActThreadOn = 1 and its long pointer in
; !Battle_ActThreadPtr. All loaders end in BattleAct_LoadCommon.
; "Attack" and "tech" for kinds 1 and 2 are guesses from the records
; (kind 1: three record sets per !Battle_Unk1C48 value for PCs, two
; records per enemy type; kind 2: one record per !Battle_ActId, for PCs
; and for enemies), not checked against what the player sees.
; Quirks shared by the four thread loops: the flag is stored 16-bit,
; so the byte after it (the next thread's flag, or $5DBC after thread
; 15) is zeroed too, which is harmless in order; the second-group test
; inside the loop is 16-bit, so it also sees the byte after
; !Battle_ActSecondGroup, while only its low byte is cleared. Every
; loader also turns 8-bit values into 16-bit indexes (TAX, or REP and
; 16-bit arithmetic) without clearing B, so it relies on B being 0:
; BattleAct_BuildBattlerList, the last call before BattleAct_LoadScript,
; ends with B = 0 (read in its unmatched code).

; ==================================================================
; BattleAct_LoadAttack ($C1432C–$C1459F, 628 bytes)
; ==================================================================
; Kind 1. For a PC caster: rebuilds the occupied-cell map, decides
; !Battle_ActNear and turns the caster towards the main target
; (BattleAct_CheckReach), takes the PC's record number from
; !Battle_Unk1C48 (the byte at offset slot * 5, kept in
; !Battle_ActPcAttackRec) and reads one of the three 5-byte record sets
; of BattleRom_PcAttackAct: "Alt" when !Battle_ActUnkAE9B bit 7 is set,
; else "Near" or "Far" by !Battle_ActNear; the script comes from the
; matching BattleRom_PcAttackScript list by character. Tables: frames
; !BattleRom_PcAttackFrames, palettes !BattleRom_PcAttackPals, objects
; !BattleRom_PcAttackObjs, scripts !BattleRom_PcAttackScripts in bank
; $CE. For an enemy caster: the record of its !Battler_Unk984D value
; (presumably its enemy type) in BattleRom_EnemyAttackAct, or
; BattleRom_EnemyAttack2Act when !Battle_ActId is non-zero; frames
; !BattleRom_ActFrames, palettes !BattleRom_EnemyActPals, objects
; !BattleRom_EnemyActObjs, scripts !BattleRom_EnemyAttackScripts in
; bank $CD. Then starts the threads and jumps to BattleAct_LoadCommon.
; Quirks: the PC record number is widened to 16 bits with REP and no
; TDC, so it relies on B being 0 there (as BattleAct_CheckReach leaves
; it, presumably; see the banner); the "Near" path ends with a BRA to
; the next instruction.
; Callers: BattleAct_LoaderTable entry 1.
; Entry: M=1, X=0, DP=0, DB=$7E; the action block set, the parameter
;        block cleared (BattleAct_LoadScript)
; Exit:  as BattleAct_LoadCommon
; Callees: Battle_BuildOccupiedCellMap, BattleAct_CheckReach,
;          BattleAct_LoadCommon (JMP)
!BattleAct_Mask = !BattleTmp_80         ; 2 B: thread mask being walked (bit 15 = thread 0); also the multiply scratch
!BattleAct_Mask2 = !BattleTmp_82        ; 2 B: the second group's mask
BattleAct_LoadAttack:
    LDA.w !Battle_ActCaster
    CMP.b #!Battle_FirstEnemySlot
    BCC .pc
    JMP .enemy
.pc:
    JSL Battle_BuildOccupiedCellMap
    JSR BattleAct_CheckReach
    LDA.w !Battle_ActCaster
    TAX
    LDA.l !BattleRom_SlotTimes5,X
    TAX
    LDA.w !Battle_Unk1C48,X
    STA.w !Battle_ActPcAttackRec
    REP #$20                        ; quirk: B not cleared (see header)
    STA.b !BattleAct_Mask
    ASL A
    ASL A
    ASL A
    ASL A
    SEC
    SBC.b !BattleAct_Mask
    TAX                             ; record * 15
    TDC
    SEP #$20
    LDA.w !Battle_ActUnkAE9B
    BPL .not_alt
    LDA.l BattleRom_PcAttackAct.AltGfxA,X
    STA.w !Battle_ActGfxSetA
    LDA.l BattleRom_PcAttackAct.AltGfxB,X
    STA.w !Battle_ActGfxSetB
    LDA.l BattleRom_PcAttackAct.AltFrames,X
    STA.w !Battle_ActFramesIdx
    LDA.l BattleRom_PcAttackAct.AltPal,X
    STA.w !Battle_ActPalIdx
    LDA.l BattleRom_PcAttackAct.AltObj,X
    STA.w !Battle_ActObjIdx
    LDA.w !Battle_ActCaster
    TAX
    LDA.w !Pc_CharId,X
    TAX
    LDA.l BattleRom_PcAttackScript.Alt,X
    STA.w !Battle_ActScriptId
    BRA .pc_pointers
.not_alt:
    LDA.w !Battle_ActNear
    BNE .near
    LDA.l BattleRom_PcAttackAct.FarGfxA,X
    STA.w !Battle_ActGfxSetA
    LDA.l BattleRom_PcAttackAct.FarGfxB,X
    STA.w !Battle_ActGfxSetB
    LDA.l BattleRom_PcAttackAct.FarFrames,X
    STA.w !Battle_ActFramesIdx
    LDA.l BattleRom_PcAttackAct.FarPal,X
    STA.w !Battle_ActPalIdx
    LDA.l BattleRom_PcAttackAct.FarObj,X
    STA.w !Battle_ActObjIdx
    LDA.w !Battle_ActCaster
    TAX
    LDA.w !Pc_CharId,X
    TAX
    LDA.l BattleRom_PcAttackScript.Far,X
    STA.w !Battle_ActScriptId
    BRA .pc_pointers
.near:
    LDA.l BattleRom_PcAttackAct.NearGfxA,X
    STA.w !Battle_ActGfxSetA
    LDA.l BattleRom_PcAttackAct.NearGfxB,X
    STA.w !Battle_ActGfxSetB
    LDA.l BattleRom_PcAttackAct.NearFrames,X
    STA.w !Battle_ActFramesIdx
    LDA.l BattleRom_PcAttackAct.NearPal,X
    STA.w !Battle_ActPalIdx
    LDA.l BattleRom_PcAttackAct.NearObj,X
    STA.w !Battle_ActObjIdx
    LDA.w !Battle_ActCaster
    TAX
    LDA.w !Pc_CharId,X
    TAX
    LDA.l BattleRom_PcAttackScript.Near,X
    STA.w !Battle_ActScriptId
    BRA .pc_pointers                ; (to the next instruction)
.pc_pointers:
    REP #$20
    LDA.w !Battle_ActFramesIdx      ; 16-bit: the byte after it is still 0
    ASL A
    TAX
    LDA.l !BattleRom_PcAttackFrames,X
    STA.w !Battle_ActFramesPtr
    LDA.w !Battle_ActPalIdx
    ASL A
    TAX
    LDA.l !BattleRom_PcAttackPals,X
    STA.w !Battle_ActPalPtr
    LDA.w !Battle_ActObjIdx
    ASL A
    TAX
    LDA.l !BattleRom_PcAttackObjs,X
    STA.w !Battle_ActObjPtr
    LDA.w !Battle_ActScriptId
    ASL A
    TAX
    LDA.l !BattleRom_PcAttackScripts,X
    STA.w !Battle_ActScriptOfs
    TAX
    TAY
    TDC
    SEP #$20
    LDA.l BattleRom_ScriptHdrCE.Mask1Hi,X
    STA.b !BattleAct_Mask+1
    LDA.l BattleRom_ScriptHdrCE.Mask1Lo,X
    STA.b !BattleAct_Mask
    LDA.l BattleRom_ScriptHdrCE.Mask2Hi,X
    STA.b !BattleAct_Mask2+1
    LDA.l BattleRom_ScriptHdrCE.Mask2Lo,X
    STA.b !BattleAct_Mask2
    INY
    INY
    INY
    INY
    TYX                             ; the first thread offset
.pc_group:
    TDC
    TAY                             ; thread 0
    REP #$20
.pc_thread:
    ASL.b !BattleAct_Mask
    BCC .pc_thread_next
    LDA.w !Battle_ActSecondGroup
    BNE .pc_thread_skip
    LDA.w #1
    STA.w !Battle_ActThreadOn,Y     ; 16-bit (see banner)
    PHY
    TYA
    ASL A
    ASL A
    TAY
    LDA.l !BattleRom_ScriptsCE,X
    STA.w !Battle_ActThreadPtr,Y
    LDA.w #!BattleRom_ScriptBankPc
    STA.w !Battle_ActThreadBank,Y
    PLY
.pc_thread_skip:
    INX
    INX
.pc_thread_next:
    INY
    CPY.w #!Battle_ActThreads
    BNE .pc_thread
    TDC
    SEP #$20
    LDA.w !Battle_ActSecondGroup
    BEQ .pc_loaded
    STZ.w !Battle_ActSecondGroup
    LDY.b !BattleAct_Mask2
    STY.b !BattleAct_Mask
    BRA .pc_group
.pc_loaded:
    JMP BattleAct_LoadCommon
.enemy:
    SEC
    LDA.w !Battle_ActCaster
    SBC.b #!Battle_FirstEnemySlot
    ASL A
    TAX
    REP #$20
    LDA.w !Battler_Unk984D+(!Battle_FirstEnemySlot*2),X
    ASL A
    STA.b !BattleAct_Mask
    ASL A
    CLC
    ADC.b !BattleAct_Mask
    TAX                             ; value * 6
    TDC
    SEP #$20
    LDA.w !Battle_ActId
    BNE .enemy_second
    LDA.l BattleRom_EnemyAttackAct.Script,X
    STA.w !Battle_ActScriptId
    LDA.l BattleRom_EnemyAttackAct.GfxA,X
    STA.w !Battle_ActGfxSetA
    LDA.l BattleRom_EnemyAttackAct.GfxB,X
    STA.w !Battle_ActGfxSetB
    LDA.l BattleRom_EnemyAttackAct.Frames,X
    STA.w !Battle_ActFramesIdx
    LDA.l BattleRom_EnemyAttackAct.Pal,X
    STA.w !Battle_ActPalIdx
    LDA.l BattleRom_EnemyAttackAct.Obj,X
    STA.w !Battle_ActObjIdx
    BRA .enemy_pointers
.enemy_second:
    LDA.l BattleRom_EnemyAttack2Act.Script,X
    STA.w !Battle_ActScriptId
    LDA.l BattleRom_EnemyAttack2Act.GfxA,X
    STA.w !Battle_ActGfxSetA
    LDA.l BattleRom_EnemyAttack2Act.GfxB,X
    STA.w !Battle_ActGfxSetB
    LDA.l BattleRom_EnemyAttack2Act.Frames,X
    STA.w !Battle_ActFramesIdx
    LDA.l BattleRom_EnemyAttack2Act.Pal,X
    STA.w !Battle_ActPalIdx
    LDA.l BattleRom_EnemyAttack2Act.Obj,X
    STA.w !Battle_ActObjIdx
.enemy_pointers:
    REP #$20
    LDA.w !Battle_ActFramesIdx
    ASL A
    TAX
    LDA.l !BattleRom_ActFrames,X
    STA.w !Battle_ActFramesPtr
    LDA.w !Battle_ActPalIdx
    ASL A
    TAX
    LDA.l !BattleRom_EnemyActPals,X
    STA.w !Battle_ActPalPtr
    LDA.w !Battle_ActObjIdx
    ASL A
    TAX
    LDA.l !BattleRom_EnemyActObjs,X
    STA.w !Battle_ActObjPtr
    LDA.w !Battle_ActScriptId
    ASL A
    TAX
    LDA.l !BattleRom_EnemyAttackScripts,X
    STA.w !Battle_ActScriptOfs
    TAX
    TAY
    TDC
    SEP #$20
    LDA.l BattleRom_ScriptHdrCD.Mask1Hi,X
    STA.b !BattleAct_Mask+1
    LDA.l BattleRom_ScriptHdrCD.Mask1Lo,X
    STA.b !BattleAct_Mask
    LDA.l BattleRom_ScriptHdrCD.Mask2Hi,X
    STA.b !BattleAct_Mask2+1
    LDA.l BattleRom_ScriptHdrCD.Mask2Lo,X
    STA.b !BattleAct_Mask2
    INY
    INY
    INY
    INY
    TYX
.enemy_group:
    TDC
    TAY
    REP #$20
.enemy_thread:
    ASL.b !BattleAct_Mask
    BCC .enemy_thread_next
    LDA.w !Battle_ActSecondGroup
    BNE .enemy_thread_skip
    LDA.w #1
    STA.w !Battle_ActThreadOn,Y
    PHY
    TYA
    ASL A
    ASL A
    TAY
    LDA.l !BattleRom_ScriptsCD,X
    STA.w !Battle_ActThreadPtr,Y
    LDA.w #!BattleRom_ScriptBankEnemy
    STA.w !Battle_ActThreadBank,Y
    PLY
.enemy_thread_skip:
    INX
    INX
.enemy_thread_next:
    INY
    CPY.w #!Battle_ActThreads
    BNE .enemy_thread
    TDC
    SEP #$20
    LDA.w !Battle_ActSecondGroup
    BEQ .enemy_loaded
    STZ.w !Battle_ActSecondGroup
    LDY.b !BattleAct_Mask2
    STY.b !BattleAct_Mask
    BRA .enemy_group
.enemy_loaded:
    JMP BattleAct_LoadCommon

; ==================================================================
; BattleAct_LoadTech ($C145A0–$C14759, 442 bytes)
; ==================================================================
; Kind 2: reads the 7-byte record !Battle_ActId of BattleRom_PcTechAct
; (PC caster) or BattleRom_EnemyTechAct (enemy caster), including
; !Battle_ActUnkArg987C, then: frames !BattleRom_ActFrames for both;
; palettes !BattleRom_PcTechPals / !BattleRom_EnemyActPals; objects
; !BattleRom_TechObjs / !BattleRom_EnemyActObjs; scripts
; !BattleRom_PcTechScripts in bank $CE / !BattleRom_EnemyTechScripts in
; bank $CD. Starts the threads (see the banner) and jumps to
; BattleAct_LoadCommon.
; Callers: BattleAct_LoaderTable entry 2.
; Entry: M=1, X=0, DP=0, DB=$7E; as BattleAct_LoadAttack
; Exit:  as BattleAct_LoadCommon
; Callees: BattleAct_LoadCommon (JMP)
BattleAct_LoadTech:
    LDA.w !Battle_ActCaster
    CMP.b #!Battle_FirstEnemySlot
    BCC .pc
    JMP .enemy
.pc:
    LDA.w !Battle_ActId
    REP #$20
    STA.b !BattleAct_Mask
    ASL A
    ASL A
    ASL A
    SEC
    SBC.b !BattleAct_Mask
    TAX                             ; id * 7
    TDC
    SEP #$20
    LDA.l BattleRom_PcTechAct.Script,X
    STA.w !Battle_ActScriptId
    LDA.l BattleRom_PcTechAct.GfxA,X
    STA.w !Battle_ActGfxSetA
    LDA.l BattleRom_PcTechAct.GfxB,X
    STA.w !Battle_ActGfxSetB
    LDA.l BattleRom_PcTechAct.Frames,X
    STA.w !Battle_ActFramesIdx
    LDA.l BattleRom_PcTechAct.Pal,X
    STA.w !Battle_ActPalIdx
    LDA.l BattleRom_PcTechAct.Obj,X
    STA.w !Battle_ActObjIdx
    LDA.l BattleRom_PcTechAct.Arg,X
    STA.w !Battle_ActUnkArg987C
    REP #$20
    LDA.w !Battle_ActFramesIdx
    ASL A
    TAX
    LDA.l !BattleRom_ActFrames,X
    STA.w !Battle_ActFramesPtr
    LDA.w !Battle_ActPalIdx
    ASL A
    TAX
    LDA.l !BattleRom_PcTechPals,X
    STA.w !Battle_ActPalPtr
    LDA.w !Battle_ActObjIdx
    ASL A
    TAX
    LDA.l !BattleRom_TechObjs,X
    STA.w !Battle_ActObjPtr
    LDA.w !Battle_ActScriptId
    ASL A
    TAX
    LDA.l !BattleRom_PcTechScripts,X
    STA.w !Battle_ActScriptOfs
    TAX
    TAY
    TDC
    SEP #$20
    LDA.l BattleRom_ScriptHdrCE.Mask1Hi,X
    STA.b !BattleAct_Mask+1
    LDA.l BattleRom_ScriptHdrCE.Mask1Lo,X
    STA.b !BattleAct_Mask
    LDA.l BattleRom_ScriptHdrCE.Mask2Hi,X
    STA.b !BattleAct_Mask2+1
    LDA.l BattleRom_ScriptHdrCE.Mask2Lo,X
    STA.b !BattleAct_Mask2
    INY
    INY
    INY
    INY
    TYX
.pc_group:
    TDC
    TAY
    REP #$20
.pc_thread:
    ASL.b !BattleAct_Mask
    BCC .pc_thread_next
    LDA.w !Battle_ActSecondGroup
    BNE .pc_thread_skip
    LDA.w #1
    STA.w !Battle_ActThreadOn,Y
    PHY
    TYA
    ASL A
    ASL A
    TAY
    LDA.l !BattleRom_ScriptsCE,X
    STA.w !Battle_ActThreadPtr,Y
    LDA.w #!BattleRom_ScriptBankPc
    STA.w !Battle_ActThreadBank,Y
    PLY
.pc_thread_skip:
    INX
    INX
.pc_thread_next:
    INY
    CPY.w #!Battle_ActThreads
    BNE .pc_thread
    TDC
    SEP #$20
    LDA.w !Battle_ActSecondGroup
    BEQ .pc_loaded
    STZ.w !Battle_ActSecondGroup
    LDY.b !BattleAct_Mask2
    STY.b !BattleAct_Mask
    BRA .pc_group
.pc_loaded:
    JMP BattleAct_LoadCommon
.enemy:
    LDA.w !Battle_ActId
    REP #$20
    STA.b !BattleAct_Mask
    ASL A
    ASL A
    ASL A
    SEC
    SBC.b !BattleAct_Mask
    TAX                             ; id * 7
    TDC
    SEP #$20
    LDA.l BattleRom_EnemyTechAct.Script,X
    STA.w !Battle_ActScriptId
    LDA.l BattleRom_EnemyTechAct.GfxA,X
    STA.w !Battle_ActGfxSetA
    LDA.l BattleRom_EnemyTechAct.GfxB,X
    STA.w !Battle_ActGfxSetB
    LDA.l BattleRom_EnemyTechAct.Frames,X
    STA.w !Battle_ActFramesIdx
    LDA.l BattleRom_EnemyTechAct.Pal,X
    STA.w !Battle_ActPalIdx
    LDA.l BattleRom_EnemyTechAct.Obj,X
    STA.w !Battle_ActObjIdx
    LDA.l BattleRom_EnemyTechAct.Arg,X
    STA.w !Battle_ActUnkArg987C
    REP #$20
    LDA.w !Battle_ActFramesIdx
    ASL A
    TAX
    LDA.l !BattleRom_ActFrames,X
    STA.w !Battle_ActFramesPtr
    LDA.w !Battle_ActPalIdx
    ASL A
    TAX
    LDA.l !BattleRom_EnemyActPals,X
    STA.w !Battle_ActPalPtr
    LDA.w !Battle_ActObjIdx
    ASL A
    TAX
    LDA.l !BattleRom_EnemyActObjs,X
    STA.w !Battle_ActObjPtr
    LDA.w !Battle_ActScriptId
    ASL A
    TAX
    LDA.l !BattleRom_EnemyTechScripts,X
    STA.w !Battle_ActScriptOfs
    TAX
    TAY
    TDC
    SEP #$20
    LDA.l BattleRom_ScriptHdrCD.Mask1Hi,X
    STA.b !BattleAct_Mask+1
    LDA.l BattleRom_ScriptHdrCD.Mask1Lo,X
    STA.b !BattleAct_Mask
    LDA.l BattleRom_ScriptHdrCD.Mask2Hi,X
    STA.b !BattleAct_Mask2+1
    LDA.l BattleRom_ScriptHdrCD.Mask2Lo,X
    STA.b !BattleAct_Mask2
    INY
    INY
    INY
    INY
    TYX
.enemy_group:
    TDC
    TAY
    REP #$20
.enemy_thread:
    ASL.b !BattleAct_Mask
    BCC .enemy_thread_next
    LDA.w !Battle_ActSecondGroup
    BNE .enemy_thread_skip
    LDA.w #1
    STA.w !Battle_ActThreadOn,Y
    PHY
    TYA
    ASL A
    ASL A
    TAY
    LDA.l !BattleRom_ScriptsCD,X
    STA.w !Battle_ActThreadPtr,Y
    LDA.w #!BattleRom_ScriptBankEnemy
    STA.w !Battle_ActThreadBank,Y
    PLY
.enemy_thread_skip:
    INX
    INX
.enemy_thread_next:
    INY
    CPY.w #!Battle_ActThreads
    BNE .enemy_thread
    TDC
    SEP #$20
    LDA.w !Battle_ActSecondGroup
    BEQ .enemy_loaded
    STZ.w !Battle_ActSecondGroup
    LDY.b !BattleAct_Mask2
    STY.b !BattleAct_Mask
    BRA .enemy_group
.enemy_loaded:
    JMP BattleAct_LoadCommon

; ==================================================================
; BattleAct_LoadNone ($C1475A, 1 byte)
; ==================================================================
; Kind 0 (and any kind of 4 and up): loads nothing, so no thread
; starts.
; Callers: BattleAct_LoaderTable entry 0.
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  unchanged
BattleAct_LoadNone:
    RTS

; ==================================================================
; BattleAct_LoadKind3 ($C1475B–$C14832, 216 bytes)
; ==================================================================
; Kind 3: like the PC branch of BattleAct_LoadTech, for any caster, with
; record !Battle_ActId - $BC of BattleRom_Kind3Act; frames
; !BattleRom_ActFrames, palettes !BattleRom_Kind3Pals, objects
; !BattleRom_TechObjs, scripts !BattleRom_Kind3Scripts in bank $CE.
; What kind 3 is (ids from $BC up) is not known. Starts the threads (see
; the banner) and falls into BattleAct_LoadCommon.
; Callers: BattleAct_LoaderTable entry 3.
; Entry: M=1, X=0, DP=0, DB=$7E; as BattleAct_LoadAttack
; Exit:  as BattleAct_LoadCommon
BattleAct_LoadKind3:
    SEC
    LDA.w !Battle_ActId
    SBC.b #!Battle_ActKind3FirstId
    REP #$20
    STA.b !BattleAct_Mask
    ASL A
    ASL A
    ASL A
    SEC
    SBC.b !BattleAct_Mask
    TAX                             ; (id - $BC) * 7
    TDC
    SEP #$20
    LDA.l BattleRom_Kind3Act.Script,X
    STA.w !Battle_ActScriptId
    LDA.l BattleRom_Kind3Act.GfxA,X
    STA.w !Battle_ActGfxSetA
    LDA.l BattleRom_Kind3Act.GfxB,X
    STA.w !Battle_ActGfxSetB
    LDA.l BattleRom_Kind3Act.Frames,X
    STA.w !Battle_ActFramesIdx
    LDA.l BattleRom_Kind3Act.Pal,X
    STA.w !Battle_ActPalIdx
    LDA.l BattleRom_Kind3Act.Obj,X
    STA.w !Battle_ActObjIdx
    LDA.l BattleRom_Kind3Act.Arg,X
    STA.w !Battle_ActUnkArg987C
    REP #$20
    LDA.w !Battle_ActFramesIdx
    ASL A
    TAX
    LDA.l !BattleRom_ActFrames,X
    STA.w !Battle_ActFramesPtr
    LDA.w !Battle_ActPalIdx
    ASL A
    TAX
    LDA.l !BattleRom_Kind3Pals,X
    STA.w !Battle_ActPalPtr
    LDA.w !Battle_ActObjIdx
    ASL A
    TAX
    LDA.l !BattleRom_TechObjs,X
    STA.w !Battle_ActObjPtr
    LDA.w !Battle_ActScriptId
    ASL A
    TAX
    LDA.l !BattleRom_Kind3Scripts,X
    STA.w !Battle_ActScriptOfs
    TAX
    TAY
    TDC
    SEP #$20
    LDA.l BattleRom_ScriptHdrCE.Mask1Hi,X
    STA.b !BattleAct_Mask+1
    LDA.l BattleRom_ScriptHdrCE.Mask1Lo,X
    STA.b !BattleAct_Mask
    LDA.l BattleRom_ScriptHdrCE.Mask2Hi,X
    STA.b !BattleAct_Mask2+1
    LDA.l BattleRom_ScriptHdrCE.Mask2Lo,X
    STA.b !BattleAct_Mask2
    INY
    INY
    INY
    INY
    TYX
.group:
    TDC
    TAY
    REP #$20
.thread:
    ASL.b !BattleAct_Mask
    BCC .thread_next
    LDA.w !Battle_ActSecondGroup
    BNE .thread_skip
    LDA.w #1
    STA.w !Battle_ActThreadOn,Y
    PHY
    TYA
    ASL A
    ASL A
    TAY
    LDA.l !BattleRom_ScriptsCE,X
    STA.w !Battle_ActThreadPtr,Y
    LDA.w #!BattleRom_ScriptBankPc
    STA.w !Battle_ActThreadBank,Y
    PLY
.thread_skip:
    INX
    INX
.thread_next:
    INY
    CPY.w #!Battle_ActThreads
    BNE .thread
    TDC
    SEP #$20
    LDA.w !Battle_ActSecondGroup
    BEQ BattleAct_LoadCommon
    STZ.w !Battle_ActSecondGroup
    LDY.b !BattleAct_Mask2
    STY.b !BattleAct_Mask
    BRA .group

; ==================================================================
; BattleAct_LoadCommon ($C14833–$C148EB, 185 bytes)
; ==================================================================
; The end of every loader:
;   - loads graphics set !Battle_ActGfxSetA (BattleAnim_LoadGfx4Vec) and
;     !Battle_ActGfxSetB (BattleAnim_LoadGfx2Vec) and waits a frame;
;   - calls BattleAnim_UnkVecCD0018 with !Battle_ActUnkArg987C unless
;     that is $FF, or unless !Battle_ActFlags is non-zero and the id is
;     not $37 (which id $37 is, is not known);
;   - waits a frame, splits the object records (BattleAct_IndexObjLists),
;     waits a frame;
;   - unpacks the sprite frames at bank $D1 + !Battle_ActFramesPtr into
;     !Battle_ActFrameBuf (Decomp_ToWramVec) and stores two zero bytes
;     at the end it reports, so the frame list ends there; waits a frame;
;   - builds up to 32 frames, 4 per call with a frame wait in each
;     (BattleAct_UnpackFrames, 8 calls);
;   - sets up the 16 action objects: BattleActObj bytes +0/+1 zeroed,
;     +2/+3 from BattleRom_ActObjInit (+3 with !Battle_ActAttrBits
;     added), !Battle_ActObjUnkA07B = 1. What the objects are is not
;     established.
; Each frame wait is BattleSys_PumpFrames followed by
; BattleMenu_RefreshIfDirtyAndTick, except the first.
; Callers: JMP from BattleAct_LoadAttack ($C1:4494, $C1:459D) and
;   BattleAct_LoadTech ($C1:467F, $C1:4757); BattleAct_LoadKind3 falls
;   in.
; Entry: M=1, X=0, DP=0, DB=$7E; the parameter block loaded
; Exit:  M=1, X=0, DP=0, DB=$7E; A = $10; X = $60 (6 per object); Y = 15;
;        DP $80-$87 and $8C and the callees' scratch written
; Callees: BattleAnim_LoadGfx4Vec, BattleAnim_LoadGfx2Vec,
;          BattleSys_PumpFrames, BattleAnim_UnkVecCD0018,
;          BattleMenu_RefreshIfDirtyAndTick, BattleAct_IndexObjLists,
;          Decomp_ToWramVec, BattleAct_UnpackFrames, Battle_ShiftLeft3
!BattleAct_ObjIdx = !BattleTmp_80       ; 2 B: action object 0-15 (zeroed 16-bit, counted 8-bit)
BattleAct_LoadCommon:
    LDA.w !Battle_ActGfxSetA
    JSL BattleAnim_LoadGfx4Vec
    LDA.w !Battle_ActGfxSetB
    JSL BattleAnim_LoadGfx2Vec
    JSR BattleSys_PumpFrames
    LDA.w !Battle_ActId
    CMP.b #!Battle_ActIdUnk37
    BEQ .arg
    LDA.w !Battle_ActFlags
    BNE .unpack
.arg:
    LDA.w !Battle_ActUnkArg987C
    CMP.b #!Battle_ActArgNone
    BEQ .unpack
    JSL BattleAnim_UnkVecCD0018
.unpack:
    JSR BattleSys_PumpFrames
    JSR BattleMenu_RefreshIfDirtyAndTick
    JSR BattleAct_IndexObjLists
    JSR BattleSys_PumpFrames
    JSR BattleMenu_RefreshIfDirtyAndTick
    LDX.w !Battle_ActFramesPtr
    STX.w !Battle_DecompSrc
    LDA.b #!BattleRom_ActFramesBank
    STA.w !Battle_DecompSrcBank
    LDX.w #!Battle_ActFrameBuf
    STX.w !Battle_DecompDest
    LDA.b #!Battle_WramBank
    STA.w !Battle_DecompDestBank
    JSL Decomp_ToWramVec
    LDX.w !Battle_DecompLen
    STZ.w !Battle_ActFrameBuf,X     ; a frame header of 0 ends the list
    STZ.w !Battle_ActFrameBuf+1,X
    JSR BattleSys_PumpFrames
    JSR BattleMenu_RefreshIfDirtyAndTick
    TDC
    TAX
    STX.w !Battle_ActFrameNum
    STX.w !Battle_ActFrameReadOfs
    JSR BattleAct_UnpackFrames
    JSR BattleAct_UnpackFrames
    JSR BattleAct_UnpackFrames
    JSR BattleAct_UnpackFrames
    JSR BattleAct_UnpackFrames
    JSR BattleAct_UnpackFrames
    JSR BattleAct_UnpackFrames
    JSR BattleAct_UnpackFrames
    TDC
    TAX
    TAY
    STY.b !BattleAct_ObjIdx
.object:
    LDA.b !BattleAct_ObjIdx
    JSR Battle_ShiftLeft3
    TAY                             ; object * 8
    TDC
    STA.w BattleActObj.Unk0,Y
    STA.w BattleActObj.Unk1,Y
    LDA.l BattleRom_ActObjInit.Unk0,X
    STA.w BattleActObj.Unk2,Y
    LDA.l BattleRom_ActObjInit.Unk1,X
    ORA.w !Battle_ActAttrBits
    STA.w BattleActObj.Unk3,Y
    LDY.b !BattleAct_ObjIdx
    LDA.b #1
    STA.w !Battle_ActObjUnkA07B,Y
    INX
    INX
    INX
    INX
    INX
    INX
    INC.b !BattleAct_ObjIdx
    LDA.b !BattleAct_ObjIdx
    CMP.b #!Battle_ActObjects
    BNE .object
    RTS

; ==================================================================
; BattleAct_IndexObjLists ($C148EC–$C14942, 87 bytes)
; ==================================================================
; Splits the 4-byte records at bank $CE + !Battle_ActObjPtr into the
; lists of the 16 action objects, by the top three bits of each record's
; first byte:
;   000  an ordinary record;
;   1xx  ends the object's list;
;   010  a mark: the count of records since the list's start or the
;        previous mark (this one included) goes to the object's
;        !Battle_ActObjMarkCount and the count restarts;
;   001  sets !Battle_ActObjMarkCount to 0 and ends the list.
; !Battle_ActObjListStart gets each list's first record (object 0: the
; pointer itself; object n: the record after object n-1's end). The
; first record of lists 1-15 is never tested and counts as 1. Records
; and marks are read here only; what they say is not analysed.
; Callers (JSR): BattleAct_LoadCommon ($C1:4861) only.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A = $10; X = the record after object 15's
;        end; Y clobbered; DP $80-$83 written
!BattleAct_RecCount = !BattleTmp_80     ; 1 B: records counted since the list start or the last mark
!BattleAct_ListIdx = !BattleTmp_82      ; 2 B: object 0-15 whose list is being read (zeroed 16-bit, counted 8-bit)
BattleAct_IndexObjLists:
    LDX.w !Battle_ActObjPtr
    STX.w !Battle_ActObjListStart
    TDC
    TAY
    STY.b !BattleAct_RecCount
    STY.b !BattleAct_ListIdx
.record:
    LDA.l !BattleRom_ScriptsCE,X
    AND.b #!Battle_ActObjRecTypeMask
    BEQ .count
    BMI .list_end
    AND.b #!Battle_ActObjRecMark
    BNE .mark
    LDA.b !BattleAct_ListIdx        ; type 001
    TAY
    TDC
    STA.w !Battle_ActObjMarkCount,Y
    BRA .list_end
.mark:
    INX
    INX
    INX
    INX
    INC.b !BattleAct_RecCount
    LDA.b !BattleAct_ListIdx
    TAY
    LDA.b !BattleAct_RecCount
    STA.w !Battle_ActObjMarkCount,Y
    STZ.b !BattleAct_RecCount
    BRA .record
.list_end:
    INX
    INX
    INX
    INX
    INC.b !BattleAct_ListIdx
    LDA.b !BattleAct_ListIdx
    CMP.b #!Battle_ActObjects
    BEQ .exit
    ASL A
    TAY
    REP #$20
    TXA
    STA.w !Battle_ActObjListStart,Y
    TDC
    SEP #$20
    STZ.b !BattleAct_RecCount
.count:
    INX
    INX
    INX
    INX
    INC.b !BattleAct_RecCount
    BRA .record
.exit:
    RTS

; ==================================================================
; BattleAct_UnpackFrames ($C14943–$C149FE, 188 bytes)
; ==================================================================
; Waits a frame (BattleSys_PumpFrames, BattleMenu_RefreshIfDirtyAndTick)
; and builds up to 4 sprite frames from the unpacked data in
; !Battle_ActFrameBuf, going on from !Battle_ActFrameNum and
; !Battle_ActFrameReadOfs. A frame is a header byte (low nibble: row
; count; high nibble: kept in DP $80 and not read), one bit mask per row
; (bit 7 = column 0), then for each set bit a tile byte and an attribute
; byte, then 2 bytes that are skipped. Each set bit gives a 16x16 sprite
; at (column * 16, row * 16) (!BattleRom_Times16), written into the
; frame's block of BattleActSprite (block offset from
; !BattleRom_ActFrameBase, $C0 bytes = 48 sprites per frame) with
; !Battle_ActAttrBits added to the attribute; the frame's sprite count
; goes to !Battle_ActFrameSprites. A header of 0 ends the data (the
; zero bytes BattleAct_LoadCommon appends); the frame number then stays.
; "Sprite" and "16x16" are inferred from the 4-byte x, y, tile,
; attribute layout and the 16-pixel steps.
; Callers (8 JSR sites): BattleAct_LoadCommon ($C1:489B, $C1:489E,
;   $C1:48A1, $C1:48A4, $C1:48A7, $C1:48AA, $C1:48AD, $C1:48B0).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $80-$87 and $8C
;        written, and the callees' scratch
; Callees: BattleSys_PumpFrames, BattleMenu_RefreshIfDirtyAndTick
!BattleAct_FrameHigh = !BattleTmp_80    ; 1 B: high nibble of the frame header (not read)
!BattleAct_RowsLeft = !BattleTmp_81     ; 1 B: rows still to build
!BattleAct_Row = !BattleTmp_82          ; 2 B: row count while copying the masks, then the row being built
!BattleAct_SpriteOfs = !BattleTmp_84    ; 2 B: offset of the next sprite in BattleActSprite
!BattleAct_Col = !BattleTmp_86          ; 2 B: column 0-7 being tested
!BattleAct_FramesDone = !BattleTmp_8C   ; 1 B: frames built in this call
BattleAct_UnpackFrames:
    JSR BattleSys_PumpFrames
    JSR BattleMenu_RefreshIfDirtyAndTick
    STZ.b !BattleAct_FramesDone
.frame:
    REP #$20
    LDA.w !Battle_ActFrameNum
    ASL A
    TAX
    LDA.l !BattleRom_ActFrameBase,X
    STA.b !BattleAct_SpriteOfs
    TDC
    SEP #$20
    LDX.w !Battle_ActFrameNum
    STZ.w !Battle_ActFrameSprites,X
    LDX.w !Battle_ActFrameReadOfs
    LDA.w !Battle_ActFrameBuf,X
    BNE .header
    JMP .exit                       ; end of the data
.header:
    AND.b #!Battle_ActFrameRowsMask
    STA.b !BattleAct_RowsLeft
    STA.b !BattleAct_Row
    LDA.w !Battle_ActFrameBuf,X
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !BattleAct_FrameHigh
    INX
    TDC
    TAY
.copy_mask:
    LDA.w !Battle_ActFrameBuf,X
    STA.w !Battle_ActRowMasks,Y
    INX
    INY
    DEC.b !BattleAct_Row
    BNE .copy_mask
    STX.w !Battle_ActFrameReadOfs
    TDC
    TAY
    STY.b !BattleAct_Row
.row:
    TDC
    TAY
    STY.b !BattleAct_Col
.col:
    LDY.b !BattleAct_Row
    LDA.w !Battle_ActRowMasks,Y
    ASL A
    STA.w !Battle_ActRowMasks,Y
    BCC .col_next
    LDX.w !Battle_ActFrameReadOfs
    LDY.b !BattleAct_SpriteOfs
    LDA.w !Battle_ActFrameBuf,X
    STA.w BattleActSprite.Tile,Y
    LDA.w !Battle_ActFrameBuf+1,X
    ORA.w !Battle_ActAttrBits
    STA.w BattleActSprite.Attr,Y
    LDX.b !BattleAct_Row
    LDA.l !BattleRom_Times16,X
    STA.w BattleActSprite.Y,Y
    LDX.b !BattleAct_Col
    LDA.l !BattleRom_Times16,X
    STA.w BattleActSprite.X,Y
    LDX.w !Battle_ActFrameReadOfs
    INX
    INX
    STX.w !Battle_ActFrameReadOfs
    INY
    INY
    INY
    INY
    STY.b !BattleAct_SpriteOfs
    LDX.w !Battle_ActFrameNum
    INC.w !Battle_ActFrameSprites,X
.col_next:
    INC.b !BattleAct_Col
    LDA.b !BattleAct_Col
    CMP.b #!Battle_ActFrameCols
    BNE .col
    INC.b !BattleAct_Row
    DEC.b !BattleAct_RowsLeft
    BNE .row
    LDX.w !Battle_ActFrameReadOfs
    INX
    INX
    STX.w !Battle_ActFrameReadOfs   ; skip 2 bytes after the frame
    INC.w !Battle_ActFrameNum
    INC.b !BattleAct_FramesDone
    LDA.b !BattleAct_FramesDone
    CMP.b #!Battle_ActFramesPerCall
    BEQ .exit
    JMP .frame
.exit:
    RTS

; ==================================================================
; Reach and path search ($C1:49FF–$C1:4BBD)
; ==================================================================
; Before a PC's attack is loaded, BattleAct_CheckReach decides whether
; the PC can get to its main target (!Battle_ActNear), and
; BattleAct_FindPath searches a way there through the cell map. The
; cell map is !Battle_PathMap: the copy of !Battle_CellMap that
; Battle_BuildOccupiedCellMap makes ($CC:F110), with $40 in every cell a
; battler stands in. One byte per 16x16-pixel cell, 16 cells per row.
; BattleAct_FindPath's direct-page roles (defined here because
; BattleAct_CheckReach passes the points through them):
!BattleAct_PathFromX = !BattleTmp_80    ; 1 B in: start x in pixels
!BattleAct_PathFromY = !BattleTmp_81    ; 1 B in: start y in pixels
!BattleAct_PathToX = !BattleTmp_82      ; 1 B in: goal x in pixels
!BattleAct_PathToY = !BattleTmp_83      ; 1 B in: goal y in pixels
!BattleAct_PathListIdx = !BattleTmp_80  ; 1 B: position in the frontier list (after the start cell is set)
!BattleAct_PathCell = !BattleTmp_82     ; 1 B: frontier cell whose neighbours are tested
!BattleAct_PathNextLen = !BattleTmp_84  ; 1 B: cells put in the next list
!BattleAct_PathStart = !BattleTmp_8E    ; 1 B: start cell
!BattleAct_PathTrace = !BattleTmp_90    ; 1 B: goal cell, then the cell the trace is on
!BattleAct_PathResult = !BattleTmp_92   ; 1 B: row bits while a cell is computed; then goal hits / result
!BattleAct_PathWave = !BattleTmp_94     ; 2 B: wave number (set 16-bit, counted 8-bit)

; ==================================================================
; BattleAct_CheckReach ($C149FF–$C14A70, 114 bytes)
; ==================================================================
; For a PC caster: sets !Battle_ActNear to 1, then to 0 when the main
; target (entry 3 of !Battle_ActBattlers) is not within 40 pixels
; (BattlePos_WithinDist40XY), and turns the caster towards the target
; (Battle_CalcAngle, !BattleRom_FacingByAngle into !Battler_Facing).
; Then, when the caster's character has its !BattleRom_PcPathAlways byte
; set or the target is within 40 pixels, searches a path from the
; caster's position to the target's (BattleAct_FindPath) and sets
; !Battle_ActNear to 1 if one was found, 0 if not. So for characters 1
; and 2 (byte 0) a far target is "Far" without a search, and for the
; others the search alone decides. That characters 1 and 2 are the two
; with ranged attacks is a guess from the data, not checked.
; Callers (JSR): BattleAct_LoadAttack ($C1:433A) only, for a PC caster
; after Battle_BuildOccupiedCellMap.
; Entry: M=1, X=0, DP=0, DB=$7E, B=0 (TAX/TAY of 8-bit slots); !Battle_ActCaster a PC slot (0-2; the
;        character is read from !Pc_CharId by it)
; Exit:  M=1, X=0, DP=0, DB=$7E; B = 0 (Battle_CalcAngle and
;        BattleAct_FindPath end with it; BattleAct_LoadAttack relies on
;        it); A, X, Y clobbered; !Battle_ActNear, the caster's
;        !Battler_Facing, !BattlePos_Subject/Other/Result and
;        !Battle_GeoOriginX/Y and PointX/Y (the caster's and the target's
;        positions) set; DP $80-$83 and the callees' scratch written;
;        after a search, !Battle_PathMap holds its marks
; Callees: BattlePos_WithinDist40XY, Battle_CalcAngle, BattleAct_FindPath
BattleAct_CheckReach:
    LDA.b #1
    STA.w !Battle_ActNear
    LDA.w !Battle_ActCaster
    STA.w !BattlePos_Subject
    TAX
    LDA.w !Battle_ActMainTarget
    STA.w !BattlePos_Other
    TAY
    LDA.w !Battler_ScreenX,X
    STA.b !Battle_GeoOriginX
    LDA.w !Battler_ScreenY,X
    STA.b !Battle_GeoOriginY
    LDA.w !Battler_ScreenX,Y
    STA.b !Battle_GeoPointX
    LDA.w !Battler_ScreenY,Y
    STA.b !Battle_GeoPointY
    JSR BattlePos_WithinDist40XY
    LDA.w !BattlePos_Result
    BPL .face                       ; within 40 pixels
    STZ.w !Battle_ActNear
.face:
    LDA.w !Battle_ActCaster
    TAY
    JSR Battle_CalcAngle
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battler_Facing,Y
    LDA.w !Pc_CharId,Y
    TAX
    LDA.l !BattleRom_PcPathAlways,X
    BNE .search
    LDA.w !Battle_ActNear
    BEQ .exit                       ; far, and no search for this character
.search:
    LDA.b !Battle_GeoOriginX
    STA.b !BattleAct_PathFromX
    LDA.b !Battle_GeoOriginY
    STA.b !BattleAct_PathFromY
    LDA.b !Battle_GeoPointX
    STA.b !BattleAct_PathToX
    LDA.b !Battle_GeoPointY
    STA.b !BattleAct_PathToY
    JSR BattleAct_FindPath
    LDA.b !BattleAct_PathResult
    BPL .found
    STZ.w !Battle_ActNear
    BRA .exit
.found:
    LDA.b #1
    STA.w !Battle_ActNear
.exit:
    RTS

; ==================================================================
; BattleAct_FindPath ($C14A71–$C14BBD, 333 bytes)
; ==================================================================
; Breadth-first search on !Battle_PathMap from the cell of the start
; point ($80, $81) to the cell of the goal point ($82, $83); the cell of
; a point is (y & $F0) | (x >> 4). Marks the start cell
; !Battle_PathCellStart and the goal cell !Battle_PathCellGoal (when the
; two are the same cell, the goal is moved to the cell above), and keeps
; both cells in !Battle_PathStartCell / !Battle_PathGoalCell.
; Wave n (1 to 30, in DP $94) takes each cell of the frontier list
; (!Battle_PathFrontier, 0-ended) and looks at its four neighbours in
; the order up, down, left, right: an empty cell (0) gets the value n
; and goes into the next list (!Battle_PathNextFrontier); the goal cell
; counts a hit in DP $92; any other value blocks. After the wave, with
; no hit, the next list becomes the frontier (even an empty one: the
; search just runs on to wave 30) and with the wave counter at $1F the
; search fails with DP $92 = !Battle_PathNotFound. With a hit (DP $92 =
; 1-4), the start cell is set back to 0 and the path is traced back
; from the goal: at each step the neighbour holding the previous wave
; number (n - 1 first, down to 0) gets !Battle_PathMark ORed in and the
; trace moves there. The marks are what the movement code reads: the
; script handler that calls this routine copies the whole map for the
; battler ($C1:549B, unmatched).
; Quirks, all reproduced:
;   - neighbours are cell index +-1 and +-16 in 8-bit X, with no edge
;     test, so the search wraps from one row end to the next row and
;     from the top row to the bottom (the battle maps are presumably
;     walled at the edges);
;   - a cell index of 0 ends the lists, so cell 0 can never be on a
;     frontier, and if the start cell is 0 the first frontier is empty;
;   - in the trace, when up, down and left all fail the right neighbour
;     is taken without being checked;
;   - the last step looks for the value 0, which the start cell has
;     again but so does any unvisited empty cell, which may come first
;     in the order.
; The meaning of the result for the caller ("can reach") is from
; BattleAct_CheckReach; the movement along the marks is not traced.
; Callers (JSR): BattleAct_CheckReach ($C1:4A5F) and the script handler
;   at $C1:542D ($C1:5479, unmatched).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E; DP $80-$83 = start x, y
;        and goal x, y in pixels; !Battle_PathMap filled
; Exit:  M=1, X=0, DP=0, DB=$7E; B = 0; DP $92 = result (bit 7 set:
;        no path within 30 steps; else the path is marked); A, X, Y
;        clobbered; DP $80, $82, $84, $8E, $90 and $94-$95 written;
;        !Battle_PathMap, the two lists and the two cell variables set
; Callees: Battle_ShiftRight4
BattleAct_FindPath:
    TDC
    TAX
    TAY
    INX
    STX.b !BattleAct_PathWave       ; wave 1 (16-bit store)
    SEP #$10
    LDA.b !BattleAct_PathFromY
    AND.b #!Battle_PathRowMask
    STA.b !BattleAct_PathResult
    LDA.b !BattleAct_PathFromX
    JSR Battle_ShiftRight4
    ORA.b !BattleAct_PathResult
    TAX                             ; start cell
    LDA.b #!Battle_PathCellStart
    STA.w !Battle_PathMap,X
    STX.w !Battle_PathFrontier
    STZ.w !Battle_PathFrontier+1    ; the first frontier: the start cell only
    STX.b !BattleAct_PathStart
    STX.w !Battle_PathStartCell
    LDA.b !BattleAct_PathToY
    AND.b #!Battle_PathRowMask
    STA.b !BattleAct_PathResult
    LDA.b !BattleAct_PathToX
    JSR Battle_ShiftRight4
    ORA.b !BattleAct_PathResult
    TAX                             ; goal cell
    CPX.w !Battle_PathStartCell
    BNE .set_goal
    SEC
    SBC.b #!Battle_PathDown
    TAX                             ; same cell: the goal is the cell above
.set_goal:
    LDA.b #!Battle_PathCellGoal
    STA.w !Battle_PathMap,X
    STX.b !BattleAct_PathTrace
    STX.w !Battle_PathGoalCell
    STZ.b !BattleAct_PathResult
.wave:
    STZ.b !BattleAct_PathNextLen
    STZ.b !BattleAct_PathListIdx
.cell:
    LDY.b !BattleAct_PathListIdx
    LDA.w !Battle_PathFrontier,Y
    BNE .neighbours
    JMP .wave_done
.neighbours:
    STA.b !BattleAct_PathCell
    CLC
    ADC.b #!Battle_PathUp
    TAX
    LDA.w !Battle_PathMap,X
    BEQ .add_up
    CMP.b #!Battle_PathCellGoal
    BNE .down
    INC.b !BattleAct_PathResult
    BRA .down
.add_up:
    LDA.b !BattleAct_PathWave
    STA.w !Battle_PathMap,X
    TXA
    LDX.b !BattleAct_PathNextLen
    STA.w !Battle_PathNextFrontier,X
    INC.b !BattleAct_PathNextLen
.down:
    CLC
    LDA.b !BattleAct_PathCell
    ADC.b #!Battle_PathDown
    TAX
    LDA.w !Battle_PathMap,X
    BEQ .add_down
    CMP.b #!Battle_PathCellGoal
    BNE .left
    INC.b !BattleAct_PathResult
    BRA .left
.add_down:
    LDA.b !BattleAct_PathWave
    STA.w !Battle_PathMap,X
    TXA
    LDX.b !BattleAct_PathNextLen
    STA.w !Battle_PathNextFrontier,X
    INC.b !BattleAct_PathNextLen
.left:
    CLC
    LDA.b !BattleAct_PathCell
    ADC.b #!Battle_PathLeft
    TAX
    LDA.w !Battle_PathMap,X
    BEQ .add_left
    CMP.b #!Battle_PathCellGoal
    BNE .right
    INC.b !BattleAct_PathResult
    BRA .right
.add_left:
    LDA.b !BattleAct_PathWave
    STA.w !Battle_PathMap,X
    TXA
    LDX.b !BattleAct_PathNextLen
    STA.w !Battle_PathNextFrontier,X
    INC.b !BattleAct_PathNextLen
.right:
    CLC
    LDA.b !BattleAct_PathCell
    ADC.b #!Battle_PathRight
    TAX
    LDA.w !Battle_PathMap,X
    BEQ .add_right
    CMP.b #!Battle_PathCellGoal
    BNE .cell_next
    INC.b !BattleAct_PathResult
    BRA .cell_next
.add_right:
    LDA.b !BattleAct_PathWave
    STA.w !Battle_PathMap,X
    TXA
    LDX.b !BattleAct_PathNextLen
    STA.w !Battle_PathNextFrontier,X
    INC.b !BattleAct_PathNextLen
.cell_next:
    INC.b !BattleAct_PathListIdx
    JMP .cell
.wave_done:
    LDA.b !BattleAct_PathResult
    BNE .trace                      ; the goal was reached
    LDX.b !BattleAct_PathNextLen
    STZ.w !Battle_PathNextFrontier,X
    TDC
    TAX
.copy_list:
    LDA.w !Battle_PathNextFrontier,X
    BEQ .copy_done
    STA.w !Battle_PathFrontier,X
    INX
    BRA .copy_list
.copy_done:
    STZ.w !Battle_PathFrontier,X
    INC.b !BattleAct_PathWave
    LDA.b !BattleAct_PathWave
    CMP.b #!Battle_PathMaxWave
    BEQ .not_found
    JMP .wave
.not_found:
    LDA.b #!Battle_PathNotFound
    STA.b !BattleAct_PathResult
    BRA .exit
.trace:
    LDX.b !BattleAct_PathStart
    STZ.w !Battle_PathMap,X
    DEC.b !BattleAct_PathWave
    LDY.b !BattleAct_PathTrace
.step:
    CLC
    LDA.b !BattleAct_PathTrace
    ADC.b #!Battle_PathUp
    TAY
    LDA.w !Battle_PathMap,Y
    CMP.b !BattleAct_PathWave
    BEQ .mark
    CLC
    LDA.b !BattleAct_PathTrace
    ADC.b #!Battle_PathDown
    TAY
    LDA.w !Battle_PathMap,Y
    CMP.b !BattleAct_PathWave
    BEQ .mark
    CLC
    LDA.b !BattleAct_PathTrace
    ADC.b #!Battle_PathLeft
    TAY
    LDA.w !Battle_PathMap,Y
    CMP.b !BattleAct_PathWave
    BEQ .mark
    CLC
    LDA.b !BattleAct_PathTrace
    ADC.b #!Battle_PathRight
    TAY
    LDA.w !Battle_PathMap,Y         ; quirk: taken without the compare
.mark:
    ORA.b #!Battle_PathMark
    STA.w !Battle_PathMap,Y
    STY.b !BattleAct_PathTrace
    DEC.b !BattleAct_PathWave
    BPL .step
.exit:
    REP #$10
    RTS

; ==================================================================
; Action script threads ($C1:4BBE–$C1:4FBE, and $C1:75BB)
; ==================================================================
; Every frame of an action, BattleAct_RunThreads runs the script
; threads that BattleAct_LoadScript started. Each thread is a long
; pointer into the script (!Battle_ActThreadPtr, 4 bytes per thread)
; and stands for an actor, by thread number:
;   - 0-3: the battler in that entry of !Battle_ActBattlers (the
;     caster, the two partner slots and the main target);
;   - 4: every slot of the target set (!Battle_ActTargetSet), run only
;     while the target mask !Battle_ActTargetMask is non-zero;
;   - 5-7: never run;
;   - 8-15: "object threads" 0-7 (!Battle_ActObjThread = thread - 8),
;     which drive the action's objects; skipped while
;     !Battle_ActUnkA3D1 is set.
; BattleAct_RunThread copies the thread's pointer to
; !Battle_ActScriptPtr and runs opcodes through the word table at
; $C1:7A6B (BattleAct_OpcodeTable, unmatched; 219 opcodes, then five
; more entries that are never used) until a handler leaves
; !Battle_ActNextOp at 0. The handlers move the pointer on with
; BattleAct_AdvanceScript; a handler that does not (the waits) runs
; again on the next frame. On entry every handler has M=1, X=0, DP=0,
; DB=$7E, Y = 0 and B = 0 (BattleAct_RunThread's TDC), the opcode in
; !Battle_ActOpcode and the thread in !Battle_ActThread.
; Names for the opcodes are taken from what the handlers do; what the
; player sees for each is not checked.

; ==================================================================
; BattleAct_RunThreads ($C14BBE–$C14C9D, 224 bytes)
; ==================================================================
; Runs one step of each live thread, in the order 0-4 then 8-15: thread
; n runs when its !Battle_ActThreadOn byte is non-zero, thread 4 only
; when !Battle_ActTargetMask is non-zero too, and threads 8-15 only
; while !Battle_ActUnkA3D1 is 0. For thread 8 + j it first sets
; !Battle_ActObjThread to j. Threads 5-7 are never run (their flags are
; set by the loaders like any other).
; Callers (JSR): BattleSys_RunAction ($C1:40CB) only.
; Entry: M=1, X=0, DP=0, DB=$7E; B=0 (A = thread * 4 goes to a 16-bit TAX
;        in BattleAct_RunThread; the caller's TDC leaves it 0)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; the threads'
;        state and whatever their handlers write
; Callees: BattleAct_RunThread
BattleAct_RunThreads:
    LDA.w !Battle_ActThreadOn
    BEQ .thread1
    LDY.w #0
    LDA.b #0*4
    JSR BattleAct_RunThread
.thread1:
    LDA.w !Battle_ActThreadOn+1
    BEQ .thread2
    LDY.w #1
    LDA.b #1*4
    JSR BattleAct_RunThread
.thread2:
    LDA.w !Battle_ActThreadOn+2
    BEQ .thread3
    LDY.w #2
    LDA.b #2*4
    JSR BattleAct_RunThread
.thread3:
    LDA.w !Battle_ActThreadOn+3
    BEQ .thread4
    LDY.w #3
    LDA.b #3*4
    JSR BattleAct_RunThread
.thread4:
    LDA.w !Battle_ActThreadOn+4
    BEQ .objects
    LDA.w !Battle_ActTargetMask
    ORA.w !Battle_ActTargetMask+1
    BEQ .objects                    ; no target set
    LDY.w #4
    LDA.b #4*4
    JSR BattleAct_RunThread
.objects:
    LDA.w !Battle_ActUnkA3D1
    BEQ .thread8
    JMP .exit
.thread8:
    LDA.w !Battle_ActThreadOn+8
    BEQ .thread9
    STZ.w !Battle_ActObjThread
    LDY.w #!Battle_ActFirstObjThread+0
    LDA.b #(!Battle_ActFirstObjThread+0)*4
    JSR BattleAct_RunThread
.thread9:
    LDA.w !Battle_ActThreadOn+9
    BEQ .thread10
    LDA.b #1
    STA.w !Battle_ActObjThread
    LDY.w #!Battle_ActFirstObjThread+1
    LDA.b #(!Battle_ActFirstObjThread+1)*4
    JSR BattleAct_RunThread
.thread10:
    LDA.w !Battle_ActThreadOn+10
    BEQ .thread11
    LDA.b #2
    STA.w !Battle_ActObjThread
    LDY.w #!Battle_ActFirstObjThread+2
    LDA.b #(!Battle_ActFirstObjThread+2)*4
    JSR BattleAct_RunThread
.thread11:
    LDA.w !Battle_ActThreadOn+11
    BEQ .thread12
    LDA.b #3
    STA.w !Battle_ActObjThread
    LDY.w #!Battle_ActFirstObjThread+3
    LDA.b #(!Battle_ActFirstObjThread+3)*4
    JSR BattleAct_RunThread
.thread12:
    LDA.w !Battle_ActThreadOn+12
    BEQ .thread13
    LDA.b #4
    STA.w !Battle_ActObjThread
    LDY.w #!Battle_ActFirstObjThread+4
    LDA.b #(!Battle_ActFirstObjThread+4)*4
    JSR BattleAct_RunThread
.thread13:
    LDA.w !Battle_ActThreadOn+13
    BEQ .thread14
    LDA.b #5
    STA.w !Battle_ActObjThread
    LDY.w #!Battle_ActFirstObjThread+5
    LDA.b #(!Battle_ActFirstObjThread+5)*4
    JSR BattleAct_RunThread
.thread14:
    LDA.w !Battle_ActThreadOn+14
    BEQ .thread15
    LDA.b #6
    STA.w !Battle_ActObjThread
    LDY.w #!Battle_ActFirstObjThread+6
    LDA.b #(!Battle_ActFirstObjThread+6)*4
    JSR BattleAct_RunThread
.thread15:
    LDA.w !Battle_ActThreadOn+15
    BEQ .exit
    LDA.b #7
    STA.w !Battle_ActObjThread
    LDY.w #!Battle_ActFirstObjThread+7
    LDA.b #(!Battle_ActFirstObjThread+7)*4
    JSR BattleAct_RunThread
.exit:
    RTS

; ==================================================================
; BattleAct_RunThread ($C14C9E–$C14CEF, 82 bytes)
; ==================================================================
; Runs one thread for this frame. Loads its pointer into
; !Battle_ActScriptPtr. While the thread's !Battle_ActThreadWait is
; non-zero it only counts it down (the pointer is not stored back,
; and is unchanged). Otherwise it runs opcodes: clears
; !Battle_ActNextOp, reads the byte at the pointer into
; !Battle_ActOpcode and, for $00-$DA, calls its handler from
; BattleAct_OpcodeTable; it goes on with the next opcode while the
; handler left !Battle_ActNextOp non-zero. Then it stores the pointer
; back. A byte of $DB or more is not run: the thread stops on it, this
; frame and every frame after.
; Callers (13 JSR sites): BattleAct_RunThreads ($C1:4BC8, $C1:4BD5,
;   $C1:4BE2, $C1:4BEF, $C1:4C04, $C1:4C1C, $C1:4C2E, $C1:4C40,
;   $C1:4C52, $C1:4C64, $C1:4C76, $C1:4C88, $C1:4C9A).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E; B=0 (16-bit TAX); A = thread * 4 (its
;        !Battle_ActThreadPtr offset), Y = thread number
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered;
;        !Battle_ActThreadOfs, !Battle_ActThread, !Battle_ActScriptPtr
;        (DP $E6-$E8) set, and whatever the handlers write
; Callees: the handlers of BattleAct_OpcodeTable
BattleAct_RunThread:
    STA.w !Battle_ActThreadOfs
    TAX
    LDA.w !Battle_ActThreadPtr,X
    STA.b !Battle_ActScriptPtr
    LDA.w !Battle_ActThreadPtr+1,X
    STA.b !Battle_ActScriptPtr+1
    LDA.w !Battle_ActThreadBank,X
    STA.b !Battle_ActScriptPtr+2
    STY.w !Battle_ActThread
    TYX
    LDA.w !Battle_ActThreadWait,X
    BEQ .opcode
    DEC.w !Battle_ActThreadWait,X
    BRA .exit
.opcode:
    STZ.w !Battle_ActNextOp
    TDC
    TAY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActOpcode
    CMP.b #!Battle_ActNumOpcodes
    BCS .store                      ; not an opcode: stop here
    REP #$20
    ASL A
    TAX
    TDC
    SEP #$20
    JSR (BattleAct_OpcodeTable,X)
    LDA.w !Battle_ActNextOp
    BNE .opcode
.store:
    LDA.w !Battle_ActThreadOfs
    TAX
    LDA.b !Battle_ActScriptPtr
    STA.w !Battle_ActThreadPtr,X
    LDA.b !Battle_ActScriptPtr+1
    STA.w !Battle_ActThreadPtr+1,X
    LDA.b !Battle_ActScriptPtr+2
    STA.w !Battle_ActThreadBank,X
.exit:
    RTS

; ==================================================================
; BattleAct_OpEndThread ($C14CF0–$C14CF6, 7 bytes)
; ==================================================================
; Opcode $00: switches the thread off (!Battle_ActThreadOn = 0). The
; pointer stays on the opcode.
; Callers: BattleAct_OpcodeTable entry $00, and the JMP at $C1:577A
;   (unmatched handler code).
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_ActThread set
; Exit:  M=1, X=0, DP=0, DB=$7E; X = thread number; A, Y unchanged
BattleAct_OpEndThread:
    LDX.w !Battle_ActThread
    STZ.w !Battle_ActThreadOn,X
    RTS

; ==================================================================
; BattleAct_OpEndScript ($C14CF7–$C14D03, 13 bytes)
; ==================================================================
; Opcode $01, and the handler of every unused opcode in the table:
; counts !Battle_ActScriptDone up, which ends the action (service 4
; waits for it). While !Battle_ActUnkA3D1 is set it does not, and
; stays on the opcode (advance by 0) to try again next frame. The
; thread is not switched off, so it runs this again every frame until
; service 4 stops calling the threads.
; Callers: BattleAct_OpcodeTable entries $01, $2F and 68 more of the
;   219 opcodes (and the five entries $DB-$DF after them, which
;   BattleAct_RunThread never reaches). xref also confirms "JMP" sites
;   at $C1:7A6C, $C1:7B02, $C1:7B68, $C1:7BB8, $C1:7BF8 and $C1:7C22,
;   which are bytes of the table itself (the $4C high byte of one entry
;   followed by this address), not calls.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A clobbered (0 after the advance);
;        X, Y unchanged
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpEndScript:
    LDA.w !Battle_ActUnkA3D1
    BEQ .done
    TDC
    JMP BattleAct_AdvanceScript     ; by 0: wait
.done:
    INC.w !Battle_ActScriptDone
    RTS

; ==================================================================
; BattleAct_OpLoopAnim ($C14D04–$C14E21, 286 bytes)
; ==================================================================
; Opcode $02 <n>: starts animation n of the thread's actor in mode 2
; (loop) and goes on with the next opcode in the same frame; advances
; 2. BattleAct_StartAnim, its body, takes the mode in DP $8E and is
; also used by the "play" opcodes with mode 1 (play once); with mode 1
; it returns without advancing, so the caller waits.
; Starting animation n:
;   - threads 0-3: for the battler of the thread (!Battle_ActBattlers
;     entry), the frame and duration list offsets are its
;     !Battler_AnimFrameBase and !Battler_AnimDurBase plus n * 4, into
;     !Battle_AnimFrameList / !Battle_AnimDurList; then
;     !Battler_ActAnimMode = the mode, the timer 0, and the entry and
;     !Battler_ActFacing $FF, so that BattleAct_StepBattlerAnims starts
;     the list at entry 0 and draws it;
;   - thread 4: the same for every slot of !Battle_ActTargetSet;
;   - threads 8-15: object thread j gets object n's list:
;     !Battle_ActObjAnimList = !Battle_ActObjListStart of n,
;     !Battle_ActObjAnimCount = its !Battle_ActObjMarkCount; then
;     !Battle_ActUnkA1A8 (mode), timer 0, entry and
;     !Battle_ActObjAnimUnkA2B8 $FF. These are stepped by the code at
;     $CC:F278 (unmatched); that they play like the battlers' lists is
;     inferred from the parallel layout.
; Quirk: the thread-4 loop has a TAX that is not used.
; Callers: BattleAct_OpcodeTable entry $02 (BattleAct_OpLoopAnim);
;   BattleAct_StartAnim: BattleAct_OpPlayAnim ($C1:4E3E, $C1:4E5F,
;   $C1:4E87), BattleAct_OpShowAnimFrame ($C1:4EBE, $C1:4EDF, $C1:4F06)
;   and the unmatched handler code at $C1:57A5, $C1:57C8 and $C1:57F2.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0; for
;        BattleAct_StartAnim DP $8E = the mode (1 or 2); the operand
;        byte after the opcode
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $80-$83, $8A,
;        $8C-$8D and $8E written; with mode 2, !Battle_ActNextOp
;        counted up and the pointer advanced 2 (A = 0)
; Callees: BattleAct_AdvanceScript (JMP)
!BattleAct_AnimNum = !BattleTmp_80      ; 1 B: the operand, animation (or object list) number
!BattleAct_AnimOfs = !BattleTmp_82      ; 2 B: animation number * 4
!BattleAct_StartSlot = !BattleTmp_8A    ; 1 B: battler slot being started
!BattleAct_AnimSetIdx = !BattleTmp_8C   ; 2 B: thread 4: position in !Battle_ActTargetSet
!BattleAct_AnimMode = !BattleTmp_8E     ; 1 B in: mode for !Battler_ActAnimMode (1 = once, 2 = loop)
BattleAct_OpLoopAnim:
    LDA.b #!Battle_ActAnimLoop
    STA.b !BattleAct_AnimMode
BattleAct_StartAnim:                    ; header: see BattleAct_OpLoopAnim
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_AnimNum
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    JMP .object
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BEQ .target_set
    LDX.w !Battle_ActThread
    LDA.w !Battle_ActBattlers,X
    STA.b !BattleAct_StartSlot
    ASL A
    TAY                             ; slot * 2
    CLC
    ADC.b !BattleAct_StartSlot
    TAX                             ; slot * 3
    LDA.w !Battler_AnimFrameBase,X
    STA.w !Battle_AnimFrameList,Y
    LDA.w !Battler_AnimFrameBase+1,X
    STA.w !Battle_AnimFrameList+1,Y
    LDA.w !Battler_AnimDurBase,X
    STA.w !Battle_AnimDurList,Y
    LDA.w !Battler_AnimDurBase+1,X
    STA.w !Battle_AnimDurList+1,Y
    LDA.b !BattleAct_AnimNum
    REP #$20
    ASL A
    ASL A
    STA.b !BattleAct_AnimOfs
    CLC
    ADC.w !Battle_AnimDurList,Y
    STA.w !Battle_AnimDurList,Y
    CLC
    LDA.b !BattleAct_AnimOfs
    ADC.w !Battle_AnimFrameList,Y
    STA.w !Battle_AnimFrameList,Y
    TDC
    SEP #$20
    LDA.b !BattleAct_StartSlot
    TAY
    LDA.b !BattleAct_AnimMode
    STA.w !Battler_ActAnimMode,Y
    TDC
    STA.w !Battler_ActAnimTimer,Y
    DEC A
    STA.w !Battler_ActAnimEntry,Y
    STA.w !Battler_ActFacing,Y
    LDA.b !BattleAct_AnimMode
    CMP.b #!Battle_ActAnimOnce
    BEQ .wait
    JMP .continue
.wait:
    RTS
.target_set:
    TDC
    TAX
    STX.b !BattleAct_AnimSetIdx
.set_slot:
    LDX.b !BattleAct_AnimSetIdx
    LDA.w !Battle_ActTargetSet,X
    BMI .set_done
    STA.b !BattleAct_StartSlot
    ASL A
    TAY
    CLC
    ADC.b !BattleAct_StartSlot
    TAX
    LDA.w !Battler_AnimFrameBase,X
    STA.w !Battle_AnimFrameList,Y
    LDA.w !Battler_AnimFrameBase+1,X
    STA.w !Battle_AnimFrameList+1,Y
    LDA.w !Battler_AnimDurBase,X
    STA.w !Battle_AnimDurList,Y
    LDA.w !Battler_AnimDurBase+1,X
    STA.w !Battle_AnimDurList+1,Y
    LDA.b !BattleAct_AnimNum
    REP #$20
    ASL A
    ASL A
    STA.b !BattleAct_AnimOfs
    CLC
    ADC.w !Battle_AnimDurList,Y
    STA.w !Battle_AnimDurList,Y
    TAX                             ; quirk: not used
    CLC
    LDA.b !BattleAct_AnimOfs
    ADC.w !Battle_AnimFrameList,Y
    STA.w !Battle_AnimFrameList,Y
    TDC
    SEP #$20
    LDA.b !BattleAct_StartSlot
    TAY
    LDA.b !BattleAct_AnimMode
    STA.w !Battler_ActAnimMode,Y
    TDC
    STA.w !Battler_ActAnimTimer,Y
    DEC A
    STA.w !Battler_ActAnimEntry,Y
    STA.w !Battler_ActFacing,Y
    INC.b !BattleAct_AnimSetIdx
    BRA .set_slot
.set_done:
    LDA.b !BattleAct_AnimMode
    CMP.b #!Battle_ActAnimOnce
    BNE .continue
    BRA .exit
.object:
    LDY.w !Battle_ActObjThread
    LDA.b !BattleAct_AnimNum
    TAX
    LDA.w !Battle_ActObjMarkCount,X
    STA.w !Battle_ActObjAnimCount,Y
    LDA.w !Battle_ActObjThread
    ASL A
    TAY
    LDA.b !BattleAct_AnimNum
    ASL A
    TAX
    LDA.w !Battle_ActObjListStart,X
    STA.w !Battle_ActObjAnimList,Y
    LDA.w !Battle_ActObjListStart+1,X
    STA.w !Battle_ActObjAnimList+1,Y
    LDY.w !Battle_ActObjThread
    LDA.b !BattleAct_AnimMode
    STA.w !Battle_ActUnkA1A8,Y
    TDC
    STA.w !Battle_ActObjAnimTimer,Y
    DEC A
    STA.w !Battle_ActObjAnimEntry,Y
    STA.w !Battle_ActObjAnimUnkA2B8,Y
    LDA.b !BattleAct_AnimMode
    CMP.b #!Battle_ActAnimOnce
    BEQ .exit
.continue:
    INC.w !Battle_ActNextOp
    LDA.b #2
    JMP BattleAct_AdvanceScript
.exit:
    RTS

; ==================================================================
; BattleAct_OpPlayAnim ($C14E22–$C14EA1, 128 bytes)
; ==================================================================
; Opcode $03 <n>: plays animation n once and waits for it to end, then
; advances 2. The first time (the actor's "started" flag is 0) it sets
; the flag and starts the animation in mode 1 (BattleAct_StartAnim),
; staying on the opcode; on later frames it waits while the animation
; is on, then clears the flag and advances.
;   - threads 0-3: flag !Battler_ActAnimStarted of the battler, done
;     when its !Battler_ActAnimMode is 0;
;   - thread 4: the flag of the first slot of the target set only; done
;     when every slot's mode is 0. Quirk: the flag is not cleared on
;     this path, so a second opcode $03 on thread 4 in the same action
;     would not start its animation (BattleAct_ResetState clears it
;     with $A124-$A1A7 before the next action);
;   - threads 8-15: flag !Battle_ActObjAnimStarted; when it starts the
;     animation it also runs BattleAct_Op70Body with DP $8E = 1
;     (!Battle_ActObjUnkA1D8 counted up, no advance); done when
;     !Battle_ActUnkA1A8 is 0, which also clears !Battle_ActObjUnkA1D8.
; Callers: BattleAct_OpcodeTable entry $03.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; when it starts,
;        BattleAct_StartAnim's DP scratch
; Callees: BattleAct_StartAnim (JMP or JSR), BattleAct_Op70Body (JMP),
;          BattleAct_AdvanceScript (JMP)
BattleAct_OpPlayAnim:
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .object
    CMP.b #!Battle_ActTargetSetThread
    BEQ .target_set
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.w !Battler_ActAnimStarted,X
    BNE .battler_wait
    INC.w !Battler_ActAnimStarted,X
    LDA.b #!Battle_ActAnimOnce
    STA.b !BattleAct_AnimMode
    JMP BattleAct_StartAnim
.battler_wait:
    LDA.w !Battler_ActAnimMode,X
    BNE .battler_exit
    STZ.w !Battler_ActAnimStarted,X
    LDA.b #2
    JMP BattleAct_AdvanceScript
.battler_exit:
    RTS
.target_set:
    LDA.w !Battle_ActTargetSet
    TAX
    LDA.w !Battler_ActAnimStarted,X
    BNE .set_wait
    INC.w !Battler_ActAnimStarted,X
    LDA.b #!Battle_ActAnimOnce
    STA.b !BattleAct_AnimMode
    JMP BattleAct_StartAnim
.set_wait:
    TDC
    TAY
.set_slot:
    LDA.w !Battle_ActTargetSet,Y
    BMI .set_done
    TAX
    LDA.w !Battler_ActAnimMode,X
    BNE .set_exit                   ; still playing
    INY
    BRA .set_slot
.set_done:
    LDA.b #2
    JMP BattleAct_AdvanceScript
.set_exit:
    RTS
.object:
    LDX.w !Battle_ActObjThread
    LDA.w !Battle_ActObjAnimStarted,X
    BNE .object_wait
    INC.w !Battle_ActObjAnimStarted,X
    LDA.b #!Battle_ActAnimOnce
    STA.b !BattleAct_AnimMode
    JSR BattleAct_StartAnim
    LDA.b #1
    STA.b !BattleAct_AnimMode       ; non-zero: the opcode $70 body does not advance
    JMP BattleAct_Op70Body
.object_wait:
    LDA.w !Battle_ActUnkA1A8,X
    BNE .object_exit
    STZ.w !Battle_ActObjAnimStarted,X
    STZ.w !Battle_ActObjUnkA1D8,X
    LDA.b #2
    JMP BattleAct_AdvanceScript
.object_exit:
    RTS

; ==================================================================
; BattleAct_OpShowAnimFrame ($C14EA2–$C14F19, 120 bytes)
; ==================================================================
; Opcodes $04-$06 <n> (one handler; the opcode is not looked at):
; starts animation n with the actor's stop byte set to 1, so that
; BattleAct_StepBattlerAnims shows its entry 0 and switches it off
; (presumably: show the animation's first frame and hold it); then
; waits for the animation to be off and advances 2. The stop byte is
; also the "started" flag:
;   - threads 0-3: !Battler_ActAnimStop of the battler, cleared when its
;     mode is 0;
;   - thread 4: the first slot of the target set only, both for the
;     start and for the wait;
;   - threads 8-15: !Battle_ActObjAnimStop; the start advances by 0
;     (same opcode next frame), the wait ends when !Battle_ActUnkA1A8
;     is 0.
; Quirk: a dead RTS after the JMP at $C1:4EF3 ($C1:4EF6).
; Callers: BattleAct_OpcodeTable entries $04, $05 and $06.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; when it starts,
;        BattleAct_StartAnim's DP scratch
; Callees: BattleAct_StartAnim (JMP or JSR), BattleAct_AdvanceScript
;          (JMP)
BattleAct_OpShowAnimFrame:
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .object
    CMP.b #!Battle_ActTargetSetThread
    BEQ .target_set
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.w !Battler_ActAnimStop,X
    BNE .battler_wait
    INC.w !Battler_ActAnimStop,X
    LDA.b #!Battle_ActAnimOnce
    STA.b !BattleAct_AnimMode
    JMP BattleAct_StartAnim
.battler_wait:
    LDA.w !Battler_ActAnimMode,X
    BNE .battler_exit
    STZ.w !Battler_ActAnimStop,X
    LDA.b #2
    JMP BattleAct_AdvanceScript
.battler_exit:
    RTS
.target_set:
    LDA.w !Battle_ActTargetSet
    TAX
    LDA.w !Battler_ActAnimStop,X
    BNE .set_wait
    INC.w !Battler_ActAnimStop,X
    LDA.b #!Battle_ActAnimOnce
    STA.b !BattleAct_AnimMode
    JMP BattleAct_StartAnim
.set_wait:
    LDA.w !Battle_ActTargetSet
    TAX
    LDA.w !Battler_ActAnimMode,X
    BNE .set_exit
    STZ.w !Battler_ActAnimStop,X
    BRA .set_done
.set_exit:
    RTS
.set_done:
    LDA.b #2
    JMP BattleAct_AdvanceScript
    RTS                             ; quirk: never reached
.object:
    LDX.w !Battle_ActObjThread
    LDA.w !Battle_ActObjAnimStop,X
    BNE .object_wait
    INC.w !Battle_ActObjAnimStop,X
    LDA.b #!Battle_ActAnimOnce
    STA.b !BattleAct_AnimMode
    JSR BattleAct_StartAnim
    TDC                             ; advance by 0
    BRA .advance
.object_wait:
    LDA.w !Battle_ActUnkA1A8,X
    BNE .object_exit
    STZ.w !Battle_ActObjAnimStop,X
    LDA.b #2
.advance:
    JMP BattleAct_AdvanceScript
.object_exit:
    RTS

; ==================================================================
; BattleAct_OpResetSpeed ($C14F1A–$C14F53, 58 bytes)
; ==================================================================
; Opcode $07: sets the actor's move delay and speed
; (!Battle_ActorMoveDelay / !Battle_ActorMoveSpeed) back to the
; battler's defaults (!Battler_DefMoveDelay / !Battler_DefMoveSpeed,
; set at battle start by $CC:E3E3, unmatched); for thread 4 for every
; slot of the target set. Object threads are left alone. Advances 1.
; Callers: BattleAct_OpcodeTable entry $07.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpResetSpeed:
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .advance
    CMP.b #!Battle_ActTargetSetThread
    BEQ .target_set
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.w !Battler_DefMoveSpeed,X
    STA.w !Battle_ActorMoveSpeed,X
    LDA.w !Battler_DefMoveDelay,X
    STA.w !Battle_ActorMoveDelay,X
    BRA .advance
.target_set:
    TDC
    TAX
.set_slot:
    LDA.w !Battle_ActTargetSet,X
    BMI .advance
    TAY
    LDA.w !Battler_DefMoveDelay,Y
    STA.w !Battle_ActorMoveDelay,Y
    LDA.w !Battler_DefMoveSpeed,Y
    STA.w !Battle_ActorMoveSpeed,Y
    INX
    BRA .set_slot
.advance:
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpSetSpeed ($C14F54–$C14FBE, 107 bytes)
; ==================================================================
; Opcodes $08-$0F (one handler): sets the actor's move delay and speed
; (!Battle_ActorMoveDelay / !Battle_ActorMoveSpeed) from entry
; (opcode - 8) of !BattleRom_ActMoveDelay / !BattleRom_ActMoveSpeed:
; (4,1), (2,1), (1,1), (1,2), (1,4), (1,8), (1,$10), (1,$20), that is
; slowest to fastest: frames per step, then pixels per step (as the
; movers at $CF:EFC4 and the move opcodes use them). For thread 4 every
; slot of the target set; for object thread j entry 11 + j. Advances 1.
; Callers: BattleAct_OpcodeTable entries $08-$0F.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, B = 0 (as from
;        BattleAct_RunThread); !Battle_ActOpcode = $08-$0F
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered; for thread 4,
;        DP $80-$81 written
; Callees: BattleAct_AdvanceScript (JMP)
!BattleAct_SpeedSetIdx = !BattleTmp_80   ; 2 B: thread 4: position in !Battle_ActTargetSet
BattleAct_OpSetSpeed:
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .object
    CMP.b #!Battle_ActTargetSetThread
    BEQ .target_set
    TAX
    LDA.w !Battle_ActBattlers,X
    TAY
    SEC
    LDA.w !Battle_ActOpcode
    SBC.b #!Battle_ActOpSetSpeed
    TAX
    LDA.l !BattleRom_ActMoveDelay,X
    STA.w !Battle_ActorMoveDelay,Y
    LDA.l !BattleRom_ActMoveSpeed,X
    STA.w !Battle_ActorMoveSpeed,Y
    BRA .advance
.target_set:
    TDC
    TAY
    STY.b !BattleAct_SpeedSetIdx
.set_slot:
    LDY.b !BattleAct_SpeedSetIdx
    LDA.w !Battle_ActTargetSet,Y
    BMI .set_done
    TAY
    SEC
    LDA.w !Battle_ActOpcode
    SBC.b #!Battle_ActOpSetSpeed
    TAX
    LDA.l !BattleRom_ActMoveDelay,X
    STA.w !Battle_ActorMoveDelay,Y
    LDA.l !BattleRom_ActMoveSpeed,X
    STA.w !Battle_ActorMoveSpeed,Y
    INC.b !BattleAct_SpeedSetIdx
    BRA .set_slot
.set_done:
    BRA .advance
.object:
    LDY.w !Battle_ActObjThread
    SEC
    LDA.w !Battle_ActOpcode
    SBC.b #!Battle_ActOpSetSpeed
    TAX
    LDA.l !BattleRom_ActMoveDelay,X
    STA.w !Battle_ActorMoveDelay+!Battle_NumSlots,Y
    LDA.l !BattleRom_ActMoveSpeed,X
    STA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,Y
.advance:
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpMoveTo ($C14FBF–$C15134, 374 bytes, with
; BattleAct_OpMoveToUnkPoint, BattleAct_OpMoveToCalc and
; BattleAct_MoveToPoint)
; ==================================================================
; The move opcodes: move the thread's actor in a straight line to a
; point, at its !Battle_ActorMoveSpeed pixels per step and
; !Battle_ActorMoveDelay frames per step, then go on. The point is put
; in !Battle_ActCalcOutA/B (x, y) and DP $8E holds the opcode's length:
;   - $10 <x> <y> (BattleAct_OpMoveTo): the point from the operands;
;     length 3;
;   - $11 (BattleAct_OpMoveToUnkPoint): the point in
;     !Battle_ActUnkPointX/Y; length 1;
;   - $12 <n> (BattleAct_OpMoveToCalc): the point left by
;     BattleAct_RunCalc handler n; length 2.
; BattleAct_MoveToPoint, the shared part, by thread:
;   - threads 0-3, the thread's battler: when it is not moving
;     (!Battle_ActorMoving 0), starts the move (BattleAct_StartBattlerMove)
;     and keeps the length in the thread's !Battle_ActThreadOpLen; it
;     stays on the opcode until the mover at $CF:F040 (unmatched) sets
;     the battler's !Battler_MoveDone, then clears !Battle_ActorMoving
;     and advances by the kept length;
;   - thread 4: starts the move of every slot of the target set and
;     advances at once, without waiting;
;   - threads 8-15, object j: when it is not moving, does what
;     BattleAct_StartBattlerMove does for a battler, from the object's
;     position (!Battle_ActObjX/Y) and with the object's entries of the
;     actor arrays (index 11 + j; the word arrays 22 + 2j), and also
;     keeps the angle in !Battle_ActObjMoveAngle and
;     !Battle_ActObjUnkA5B5, its facing in !Battle_ActObjFacing and
;     zeroes !Battle_ActObjUnkA31C; then waits for
;     !Battle_ActObjMoveDone like the battlers.
; "Move" is inferred from the mover at $CF:EFC4/$CF:F040, which adds the
; step to the offset each step and writes start + offset to
; !Battler_ScreenX/Y.
; Callers: BattleAct_OpcodeTable entries $10 (BattleAct_OpMoveTo), $11
;   (BattleAct_OpMoveToUnkPoint) and $12 (BattleAct_OpMoveToCalc);
;   BattleAct_MoveToPoint is reached only from these three.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered;
;        !Battle_ActCalcOutA/B = the point; DP $8E = the length; when a
;        move starts, BattleAct_StartBattlerMove's (or for an object the
;        same) state and DP scratch; thread 4 also DP $80-$81
; Callees: BattleAct_RunCalc, BattleAct_StartBattlerMove,
;          Battle_CalcAngle, BattleAct_CalcMoveStep, Battle_Divide,
;          Battle_Mul8x16, BattleAct_AdvanceScript (JMP)
!BattleAct_MoveLen = !BattleTmp_8E      ; 1 B: length of the move opcode
!BattleAct_MoveSetIdx = !BattleTmp_80   ; 2 B: thread 4: position in !Battle_ActTargetSet
; BattleAct_CalcMoveStep's DP outputs:
!BattleAct_MoveXNeg = !BattleTmp_82     ; 1 B out: 1 = Point x < Origin x
!BattleAct_MoveYNeg = !BattleTmp_83     ; 1 B out: 1 = Point y < Origin y
!BattleAct_MoveHalfMajor = !BattleTmp_84 ; 2 B out: major distance / 2 (zeroed 16-bit, set 8-bit)
!BattleAct_MoveYMajor = !BattleTmp_8C   ; 2 B out: 1 = |dy| > |dx| (zeroed 16-bit, set 8-bit)
BattleAct_OpMoveTo:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActCalcOutA
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActCalcOutB
    LDA.b #3
    STA.b !BattleAct_MoveLen
    BRA BattleAct_MoveToPoint

BattleAct_OpMoveToUnkPoint:             ; header: see BattleAct_OpMoveTo
    LDA.w !Battle_ActUnkPointX
    STA.w !Battle_ActCalcOutA
    LDA.w !Battle_ActUnkPointY
    STA.w !Battle_ActCalcOutB
    LDA.b #1
    STA.b !BattleAct_MoveLen
    BRA BattleAct_MoveToPoint

BattleAct_OpMoveToCalc:                 ; header: see BattleAct_OpMoveTo
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    JSR BattleAct_RunCalc
    LDA.b #2
    STA.b !BattleAct_MoveLen
BattleAct_MoveToPoint:                  ; header: see BattleAct_OpMoveTo
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    JMP .object
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BNE .one_battler
    JMP .target_set
.one_battler:
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.w !Battle_ActorMoving,X
    BNE .battler_moving
    JSR BattleAct_StartBattlerMove
    LDX.w !Battle_ActThread
    LDA.b !BattleAct_MoveLen
    STA.w !Battle_ActThreadOpLen,X
    JMP .wait
.battler_moving:
    LDA.w !Battler_MoveDone,X
    BEQ .battler_wait
    STZ.w !Battle_ActorMoving,X
    JMP .done
.battler_wait:
    JMP .wait
.target_set:
    TDC
    TAX
    STX.b !BattleAct_MoveSetIdx
.set_slot:
    LDX.b !BattleAct_MoveSetIdx
    LDA.w !Battle_ActTargetSet,X
    BMI .set_done
    TAX
    JSR BattleAct_StartBattlerMove
    INC.b !BattleAct_MoveSetIdx
    BRA .set_slot
.set_done:
    LDX.w !Battle_ActThread
    LDA.b !BattleAct_MoveLen
    STA.w !Battle_ActThreadOpLen,X
    JMP .done                       ; no wait for the target set
.object:
    LDX.w !Battle_ActObjThread
    LDA.w !Battle_ActorMoving+!Battle_NumSlots,X
    BEQ .object_start
    JMP .object_moving
.object_start:
    TXA
    ASL A
    TAX
    LDA.w !Battle_ActObjX,X
    STA.b !Battle_GeoOriginX
    LDA.w !Battle_ActObjY,X
    STA.b !Battle_GeoOriginY
    LDA.w !Battle_ActCalcOutA
    STA.b !Battle_GeoPointX
    LDA.w !Battle_ActCalcOutB
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle
    JSR BattleAct_CalcMoveStep
    LDY.w !Battle_ActObjThread
    LDA.b !BattleAct_MoveYMajor
    BNE .object_y_major
    LDA.b !Battle_GeoAbsDeltaX
    STA.b !Battle_DivDividend
    STZ.b !Battle_DivDividend+1
    BRA .object_steps
.object_y_major:
    LDA.b !Battle_GeoAbsDeltaY
    STA.b !Battle_DivDividend
    STZ.b !Battle_DivDividend+1
.object_steps:
    LDA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,Y
    STA.b !Battle_DivDivisor
    JSR Battle_Divide
    LDA.b !Battle_DivQuotient
    STA.w !Battle_ActorMoveSteps+!Battle_NumSlots,Y
    LDA.w !Battle_ActMoveUnitX
    STA.b !Battle_MulFactor16
    LDA.w !Battle_ActMoveUnitX+1
    STA.b !Battle_MulFactor16+1
    LDA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,Y
    STA.b !Battle_MulFactor8
    JSR Battle_Mul8x16
    LDX.b !Battle_MulProduct
    STX.w !Battle_ActMoveUnitX
    LDA.w !Battle_ActMoveUnitY
    STA.b !Battle_MulFactor16
    LDA.w !Battle_ActMoveUnitY+1
    STA.b !Battle_MulFactor16+1
    LDA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,Y
    STA.b !Battle_MulFactor8
    JSR Battle_Mul8x16
    LDX.b !Battle_MulProduct
    STX.w !Battle_ActMoveUnitY
    LDY.w !Battle_ActObjThread
    LDA.b !Battle_GeoAngle
    STA.w !Battle_ActObjMoveAngle,Y
    STA.w !Battle_ActObjUnkA5B5,Y
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battle_ActObjFacing,Y
    LDA.w !Battle_ActCalcOutA
    STA.w !Battle_ActorToX+!Battle_NumSlots,Y
    LDA.w !Battle_ActCalcOutB
    STA.w !Battle_ActorToY+!Battle_NumSlots,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer+!Battle_NumSlots,Y
    TDC
    STA.w !Battle_ActorMoveKind+!Battle_NumSlots,Y
    STA.w !Battle_ActObjUnkA31C,Y
    STA.w !Battle_ActObjMoveDone,Y
    TYA
    ASL A
    TAX
    LDA.w !Battle_ActObjX,X
    STA.w !Battle_ActorFromX+!Battle_NumSlots,Y
    LDA.w !Battle_ActObjY,X
    STA.w !Battle_ActorFromY+!Battle_NumSlots,Y
    REP #$20
    LDA.w !Battle_ActMoveUnitX
    STA.w !Battle_ActorStepX+(2*!Battle_NumSlots),X
    LDA.w !Battle_ActMoveUnitY
    STA.w !Battle_ActorStepY+(2*!Battle_NumSlots),X
    TDC
    STA.w !Battle_ActorOfsX+(2*!Battle_NumSlots),X
    STA.w !Battle_ActorOfsY+(2*!Battle_NumSlots),X
    SEP #$20
    LDX.w !Battle_ActThread
    LDA.b !BattleAct_MoveLen
    STA.w !Battle_ActThreadOpLen,X
    LDA.b #1
    STA.w !Battle_ActorMoving+!Battle_NumSlots,Y
    BRA .wait
.object_moving:
    LDA.w !Battle_ActObjMoveDone,X
    BEQ .wait
    STZ.w !Battle_ActorMoving+!Battle_NumSlots,X
    BRA .done
.wait:
    LDA.b #0
    JMP BattleAct_AdvanceScript     ; by 0: same opcode next frame
.done:
    LDX.w !Battle_ActThread
    LDA.w !Battle_ActThreadOpLen,X
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_StartBattlerMove ($C15135–$C151ED, 185 bytes)
; ==================================================================
; Starts a straight move of battler X to the point in
; !Battle_ActCalcOutA/B (x, y): keeps its position (!Battler_ScreenX/Y)
; in !Battle_ActorFromX/Y and the point in !Battle_ActorToX/Y, turns it
; towards the point (Battle_CalcAngle, !BattleRom_FacingByAngle into
; !Battler_Facing), gets the unit step from BattleAct_CalcMoveStep and
; sets:
;   - !Battle_ActorMoveSteps = major-axis distance / its
;     !Battle_ActorMoveSpeed (rounded down, so the move may stop short
;     of the point);
;   - !Battle_ActorStepX/Y = unit step * speed (8.8 pixels per step),
;     !Battle_ActorOfsX/Y = 0;
;   - !Battle_ActorMoveTimer = 1 (the first step comes on the next
;     tick), !Battle_ActorMoveKind = 0 (straight; the movers dispatch on
;     it through the table at $CF:F01E), !Battler_MoveDone = 0 and
;     !Battle_ActorMoving = 1.
; Quirk: it also computes slot * 4 into X, which is not used.
; Callers (JSR): BattleAct_MoveToPoint ($C1:5008, $C1:5030; header of
;   BattleAct_OpMoveTo) and $C1:7231 (unmatched).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, B = 0; X = battler slot
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 1; Y = the slot; X clobbered;
;        !Battle_ActMoveUnitX/Y scaled; DP $86-$87, the angle's $D3-$E3,
;        BattleAct_CalcMoveStep's $82-$85 and $8C-$8D, and the
;        multiply's and divide's scratch written
; Callees: Battle_CalcAngle, BattleAct_CalcMoveStep, Battle_Divide,
;          Battle_Mul8x16
!BattleAct_MoveSlot = !BattleTmp_86     ; 2 B: the battler slot
BattleAct_StartBattlerMove:
    STX.b !BattleAct_MoveSlot
    LDA.w !Battler_ScreenX,X
    STA.b !Battle_GeoOriginX
    STA.w !Battle_ActorFromX,X
    LDA.w !Battler_ScreenY,X
    STA.b !Battle_GeoOriginY
    STA.w !Battle_ActorFromY,X
    LDA.w !Battle_ActCalcOutA
    STA.b !Battle_GeoPointX
    LDA.w !Battle_ActCalcOutB
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle
    JSR BattleAct_CalcMoveStep
    LDY.b !BattleAct_MoveSlot
    LDA.b !BattleAct_MoveYMajor
    BNE .y_major
    LDA.b !Battle_GeoAbsDeltaX
    STA.b !Battle_DivDividend
    STZ.b !Battle_DivDividend+1
    BRA .steps
.y_major:
    LDA.b !Battle_GeoAbsDeltaY
    STA.b !Battle_DivDividend
    STZ.b !Battle_DivDividend+1
.steps:
    LDA.w !Battle_ActorMoveSpeed,Y
    STA.b !Battle_DivDivisor
    JSR Battle_Divide
    LDA.b !Battle_DivQuotient
    STA.w !Battle_ActorMoveSteps,Y
    LDA.w !Battle_ActMoveUnitX
    STA.b !Battle_MulFactor16
    LDA.w !Battle_ActMoveUnitX+1
    STA.b !Battle_MulFactor16+1
    LDA.w !Battle_ActorMoveSpeed,Y
    STA.b !Battle_MulFactor8
    JSR Battle_Mul8x16
    LDX.b !Battle_MulProduct
    STX.w !Battle_ActMoveUnitX
    LDA.w !Battle_ActMoveUnitY
    STA.b !Battle_MulFactor16
    LDA.w !Battle_ActMoveUnitY+1
    STA.b !Battle_MulFactor16+1
    LDA.w !Battle_ActorMoveSpeed,Y
    STA.b !Battle_MulFactor8
    JSR Battle_Mul8x16
    LDX.b !Battle_MulProduct
    STX.w !Battle_ActMoveUnitY
    LDY.b !BattleAct_MoveSlot
    LDA.b !Battle_GeoAngle
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battler_Facing,Y
    LDA.w !Battle_ActCalcOutA
    STA.w !Battle_ActorToX,Y
    LDA.w !Battle_ActCalcOutB
    STA.w !Battle_ActorToY,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer,Y
    TDC
    STA.w !Battler_MoveDone,Y
    STA.w !Battle_ActorMoveKind,Y
    PHY
    TYA
    ASL A
    TAY                             ; slot * 2
    ASL A
    TAX                             ; quirk: slot * 4, not used
    REP #$20
    LDA.w !Battle_ActMoveUnitX
    STA.w !Battle_ActorStepX,Y
    LDA.w !Battle_ActMoveUnitY
    STA.w !Battle_ActorStepY,Y
    TDC
    STA.w !Battle_ActorOfsX,Y
    STA.w !Battle_ActorOfsY,Y
    SEP #$20
    PLY
    LDA.b #1
    STA.w !Battle_ActorMoving,Y
    RTS

; ==================================================================
; BattleAct_OpCurveTo ($C151EE–$C153AF, 450 bytes, with
; BattleAct_OpCurveToUnkPoint, BattleAct_OpCurveToCalc and
; BattleAct_CurveToPoint)
; ==================================================================
; The curving move opcodes: like the move opcodes $10-$12
; (BattleAct_OpMoveTo) they move the thread's actor to a point and wait
; for it, but with mover kind !Battle_MoveKindCurve: the mover at
; $CF:F405 (unmatched) keeps a heading (!Battle_ActorHeading), turns it
; towards the angle to the point by up to !Battle_ActorMoveSpeed per
; step, the way !Battle_ActorTurnDir says, and moves along it; once the
; heading has reached that angle (!Battle_ActorOnCourse) it stops
; turning. That the move ends near the point is from the mover's call
; of $CF:F957 with $10 before it sets the done flag (not traced).
; The first operand h is the start heading ($FF: the actor's
; !Battle_ActorUnkA5AA; quirk, kept: on thread 4 the start loop stores
; each slot's heading back into DP $82, so only the first slot of the
; pass sees $FF and later slots start from the first slot's heading);
; the point is put in !Battle_ActCalcOutA/B
; (x, y) and DP $8E holds the opcode's length:
;   - $13 <h> <x> <y> (BattleAct_OpCurveTo): the point from the
;     operands; length 4;
;   - $14 <h> (BattleAct_OpCurveToUnkPoint): the point in
;     !Battle_ActUnkPointX/Y; length 2;
;   - $15 <h> <n> (BattleAct_OpCurveToCalc): the point left by
;     BattleAct_RunCalc handler n; length 3.
; BattleAct_CurveToPoint, the shared part, starts a move by taking the
; angle from the actor to the point (Battle_CalcAngle), storing the
; start heading and the turn direction (BattleAct_CurveTurnDir), the
; point in !Battle_ActorToX/Y, !Battle_ActorMoveTimer = 1, the kind,
; and zeroing !Battle_ActorUnkA311, the done flag and
; !Battle_ActorOnCourse; then !Battle_ActorMoving = 1. By thread:
;   - threads 0-3, the thread's battler: starts the move when it is not
;     moving; when it is and !Battler_MoveDone is set, clears
;     !Battle_ActorMoving and advances by the length; else it stays on
;     the opcode (advance 0);
;   - thread 4: goes through the target set starting each slot that is
;     not moving, then waits. On a later frame, at the first slot that
;     is moving it switches to counting: each slot from there that is
;     done gets !Battle_ActorMoving cleared, and it advances only when
;     none is left undone. Quirk: a slot cleared this way while others
;     still move is not moving on the next frame, so the start loop
;     starts its move again (from where it ended);
;   - threads 8-15, object j: the same as a battler with the object's
;     entries of the actor arrays (index 11 + j), from the object's
;     position (!Battle_ActObjX/Y, whose high bytes it zeroes) and
;     waiting for !Battle_ActObjMoveDone.
; Unlike the straight move it sets no step, offset or step count, and
; the length is not kept per thread: each frame the opcode runs again
; from the start and sets DP $8E (and the point) again.
; Callers: BattleAct_OpcodeTable entries $13 (BattleAct_OpCurveTo), $14
;   (BattleAct_OpCurveToUnkPoint) and $15 (BattleAct_OpCurveToCalc);
;   BattleAct_CurveToPoint is reached only from these three.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered;
;        !Battle_ActCalcOutA/B = the point; DP $82 = the start heading,
;        $8E = the length; when a move starts, Battle_CalcAngle's DP
;        ($D3-$E3) and $86-$87; thread 4 also DP $80-$81 and $84
; Callees: BattleAct_RunCalc, Battle_CalcAngle, BattleAct_CurveTurnDir,
;          BattleAct_AdvanceScript (JMP)
!BattleAct_CurveHeading = !BattleTmp_82 ; 1 B: the start heading operand, then the one used
!BattleAct_CurveBusy = !BattleTmp_84    ; 1 B: thread 4: slots of the set still moving
BattleAct_OpCurveTo:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_CurveHeading
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActCalcOutA
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActCalcOutB
    LDA.b #4
    STA.b !BattleAct_MoveLen
    BRA BattleAct_CurveToPoint

BattleAct_OpCurveToUnkPoint:            ; header: see BattleAct_OpCurveTo
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_CurveHeading
    LDA.w !Battle_ActUnkPointX
    STA.w !Battle_ActCalcOutA
    LDA.w !Battle_ActUnkPointY
    STA.w !Battle_ActCalcOutB
    LDA.b #2
    STA.b !BattleAct_MoveLen
    BRA BattleAct_CurveToPoint

BattleAct_OpCurveToCalc:                ; header: see BattleAct_OpCurveTo
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_CurveHeading
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    JSR BattleAct_RunCalc
    LDA.b #3
    STA.b !BattleAct_MoveLen
BattleAct_CurveToPoint:                 ; header: see BattleAct_OpCurveTo
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    JMP .object
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BNE .one_battler
    JMP .target_set
.one_battler:
    TAX
    LDA.w !Battle_ActBattlers,X
    TAY
    LDA.w !Battle_ActorMoving,Y
    BNE .battler_moving
    LDA.w !Battler_ScreenX,Y
    STA.b !Battle_GeoOriginX
    LDA.w !Battler_ScreenY,Y
    STA.b !Battle_GeoOriginY
    LDA.w !Battle_ActCalcOutA
    STA.b !Battle_GeoPointX
    LDA.w !Battle_ActCalcOutB
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle
    LDA.b !BattleAct_CurveHeading
    CMP.b #!Battle_CurveKeepHeading
    BNE .battler_heading
    LDA.w !Battle_ActorUnkA5AA,Y
.battler_heading:
    STA.w !Battle_ActorHeading,Y
    STA.b !BattleAct_CurveHeading
    JSR BattleAct_CurveTurnDir
    STA.w !Battle_ActorTurnDir,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer,Y
    LDA.b #!Battle_MoveKindCurve
    STA.w !Battle_ActorMoveKind,Y
    TDC
    STA.w !Battle_ActorUnkA311,Y
    STA.w !Battler_MoveDone,Y
    STA.w !Battle_ActorOnCourse,Y
    LDA.w !Battle_ActCalcOutA
    STA.w !Battle_ActorToX,Y
    LDA.w !Battle_ActCalcOutB
    STA.w !Battle_ActorToY,Y
    LDA.b #1
    STA.w !Battle_ActorMoving,Y
    BRA .battler_wait
.battler_moving:
    LDA.w !Battler_MoveDone,Y
    BEQ .battler_wait
    TDC
    STA.w !Battle_ActorMoving,Y
    JMP .done
.battler_wait:
    JMP .wait
.target_set:
    TDC
    TAX
    STX.b !BattleAct_MoveSetIdx
.start_slot:
    LDX.b !BattleAct_MoveSetIdx
    LDA.w !Battle_ActTargetSet,X
    BMI .set_started
    TAY
    LDA.w !Battle_ActorMoving,Y
    BNE .count_busy
    LDA.w !Battler_ScreenX,Y
    STA.b !Battle_GeoOriginX
    LDA.w !Battler_ScreenY,Y
    STA.b !Battle_GeoOriginY
    LDA.w !Battle_ActCalcOutA
    STA.b !Battle_GeoPointX
    LDA.w !Battle_ActCalcOutB
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle
    LDA.b !BattleAct_CurveHeading
    CMP.b #!Battle_CurveKeepHeading
    BNE .slot_heading
    LDA.w !Battle_ActorUnkA5AA,Y
.slot_heading:
    STA.w !Battle_ActorHeading,Y
    STA.b !BattleAct_CurveHeading ; overwrites the $FF: later slots reuse this heading
    JSR BattleAct_CurveTurnDir
    STA.w !Battle_ActorTurnDir,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer,Y
    LDA.b #!Battle_MoveKindCurve
    STA.w !Battle_ActorMoveKind,Y
    TDC
    STA.w !Battle_ActorUnkA311,Y
    STA.w !Battler_MoveDone,Y
    STA.w !Battle_ActorOnCourse,Y
    LDA.w !Battle_ActCalcOutA
    STA.w !Battle_ActorToX,Y
    LDA.w !Battle_ActCalcOutB
    STA.w !Battle_ActorToY,Y
    LDA.b #1
    STA.w !Battle_ActorMoving,Y
    INC.b !BattleAct_MoveSetIdx
    BRA .start_slot
.set_started:
    BRA .set_wait
.count_busy:
    STZ.b !BattleAct_CurveBusy
.count_slot:
    LDX.b !BattleAct_MoveSetIdx
    LDA.w !Battle_ActTargetSet,X
    BMI .counted
    TAY
    LDA.w !Battler_MoveDone,Y
    BEQ .slot_busy
    TDC
    STA.w !Battle_ActorMoving,Y
    BRA .next_count
.slot_busy:
    INC.b !BattleAct_CurveBusy
.next_count:
    INC.b !BattleAct_MoveSetIdx
    BRA .count_slot
.counted:
    LDA.b !BattleAct_CurveBusy
    BEQ .set_done
.set_wait:
    JMP .wait
.set_done:
    JMP .done
.object:
    LDY.w !Battle_ActObjThread
    LDA.w !Battle_ActorMoving+!Battle_NumSlots,Y
    BEQ .object_start
    JMP .object_moving
.object_start:
    TYA
    ASL A
    TAX
    LDA.w !Battle_ActObjX,X
    STA.b !Battle_GeoOriginX
    LDA.w !Battle_ActObjY,X
    STA.b !Battle_GeoOriginY
    STZ.w !Battle_ActObjX+1,X
    STZ.w !Battle_ActObjY+1,X
    LDA.w !Battle_ActCalcOutA
    STA.b !Battle_GeoPointX
    LDA.w !Battle_ActCalcOutB
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle
    LDA.b !BattleAct_CurveHeading
    CMP.b #!Battle_CurveKeepHeading
    BNE .object_heading
    LDA.w !Battle_ActObjUnkA5B5,Y
.object_heading:
    STA.w !Battle_ActorHeading+!Battle_NumSlots,Y
    STA.b !BattleAct_CurveHeading
    JSR BattleAct_CurveTurnDir
    STA.w !Battle_ActorTurnDir+!Battle_NumSlots,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer+!Battle_NumSlots,Y
    LDA.b #!Battle_MoveKindCurve
    STA.w !Battle_ActorMoveKind+!Battle_NumSlots,Y
    TDC
    STA.w !Battle_ActObjUnkA31C,Y
    STA.w !Battle_ActObjMoveDone,Y
    STA.w !Battle_ActorOnCourse+!Battle_NumSlots,Y
    LDA.w !Battle_ActCalcOutA
    STA.w !Battle_ActorToX+!Battle_NumSlots,Y
    LDA.w !Battle_ActCalcOutB
    STA.w !Battle_ActorToY+!Battle_NumSlots,Y
    LDA.b #1
    STA.w !Battle_ActorMoving+!Battle_NumSlots,Y
    BRA .wait
.object_moving:
    LDX.w !Battle_ActObjThread
    LDA.w !Battle_ActObjMoveDone,X
    BEQ .wait
    STZ.w !Battle_ActorMoving+!Battle_NumSlots,X
    BRA .done
.wait:
    LDA.b #0
    JMP BattleAct_AdvanceScript     ; by 0: same opcode next frame
.done:
    LDA.b !BattleAct_MoveLen
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_CurveTurnDir ($C153B0–$C15408, 89 bytes)
; ==================================================================
; Which way a curving move turns from heading DP $82 to the angle
; !Battle_GeoAngle (Battle_CalcAngle's, to the point): A = 0 (increase
; the angle) or 1 (decrease it), the shorter way. It compares the
; quarters of the two angles (angle >> 6, DP $86 for the angle and $87
; for the heading): in the same quarter by the angles themselves (equal
; gives 1), in neighbouring quarters by their order round the circle,
; and in opposite quarters by whether heading + $80 (8-bit, so it
; wraps) is below the angle. The result is stored in
; !Battle_ActorTurnDir, which the mover at $CF:F453 reads.
; Callers (3 JSR sites): BattleAct_CurveToPoint ($C1:526B, $C1:52DD,
;   $C1:536C; header of BattleAct_OpCurveTo).
; Entry: M=1, X=0, DP=0, DB=any; DP $82 = heading, !Battle_GeoAngle set
; Exit:  M=1, X=0, DP=0; A = 0 or 1 (Z set iff 0); X, Y unchanged; DP
;        $86-$87 written
; Callees: Battle_ShiftRight6
!BattleAct_TurnAngleQ = !BattleTmp_86   ; 1 B: quarter of the angle to the point
!BattleAct_TurnHeadQ = !BattleTmp_87    ; 1 B: quarter of the heading
BattleAct_CurveTurnDir:
    LDA.b !Battle_GeoAngle
    JSR Battle_ShiftRight6
    STA.b !BattleAct_TurnAngleQ
    LDA.b !BattleAct_CurveHeading
    JSR Battle_ShiftRight6
    STA.b !BattleAct_TurnHeadQ
    CMP.b !BattleAct_TurnAngleQ
    BNE .other_quarter
    LDA.b !BattleAct_CurveHeading
    CMP.b !Battle_GeoAngle
    BCS .decrease
    BRA .increase
.other_quarter:
    LDA.b !BattleAct_TurnHeadQ
    BNE .head_q1
    LDA.b !BattleAct_TurnAngleQ     ; heading in quarter 0
    DEC A
    BEQ .increase
    DEC A
    BNE .decrease
    BRA .opposite
.head_q1:
    DEC A
    BNE .head_q2
    LDA.b !BattleAct_TurnAngleQ
    BEQ .decrease
    DEC A
    DEC A
    BEQ .increase
    BRA .opposite
.head_q2:
    DEC A
    BNE .head_q3
    LDA.b !BattleAct_TurnAngleQ
    BEQ .opposite
    DEC A
    BEQ .decrease
    BRA .increase
.head_q3:
    LDA.b !BattleAct_TurnAngleQ
    BEQ .increase
    DEC A
    BEQ .opposite
    BRA .decrease
.opposite:
    CLC
    LDA.b !BattleAct_CurveHeading
    ADC.b #!Battle_AngleHalfTurn
    CMP.b !Battle_GeoAngle
    BCC .decrease
.increase:
    TDC
    BRA .exit
.decrease:
    LDA.b #1
.exit:
    RTS

; ==================================================================
; BattleAct_OpPathTo ($C15409–$C15610, 520 bytes, with
; BattleAct_OpPathToUnkPoint, BattleAct_OpPathToCalc and
; BattleAct_PathToPoint)
; ==================================================================
; The path-walk opcodes: a battler of threads 0-3 walks to a point cell
; by cell round what stands in the way, then the thread goes on. The
; point is put in !Battle_ActCalcOutA/B (x, y) and DP $8E holds the
; opcode's length:
;   - $16 <x> <y> (BattleAct_OpPathTo): the point from the operands;
;     length 3;
;   - $17 (BattleAct_OpPathToUnkPoint): the point in
;     !Battle_ActUnkPointX/Y; length 1;
;   - $18 <n> (BattleAct_OpPathToCalc): the point left by
;     BattleAct_RunCalc handler n; length 2.
; BattleAct_PathToPoint, the shared part, for the thread's battler:
;   - when it is not walking (!Battler_PathWalking 0): keeps its x, y
;     in !Battler_PathStartX/Y, counts !Battler_UnkA166 up, keeps the
;     length in the thread's !Battle_ActThreadPathLen and searches a
;     path from its position to the point (BattleAct_FindPath, on the
;     !Battle_PathMap that is there; whether it was found is not
;     looked at). It keeps the start cell in !Battler_PathCell and
;     copies the marked map into its !Battler_PathMaps block, sets
;     !Battler_PathStepKind and !Battler_UnkA522 to 0,
;     !Battler_PathFromDir to !Battle_PathDirNone, the step frame to $FF
;     (no step under way) and !Battler_PathWalking to 1;
;   - while a step is under way (!Battler_PathStepFrame 0-7) it waits;
;     $CF:EC78 (unmatched) moves the battler by the step's table
;     entries each frame and counts the frame down;
;   - when the step is done: the step frame = !Battle_PathStepFrames,
;     the battler's map is copied to !Battle_PathWalkMap and the next
;     step is chosen from its cell c. The neighbours of c are tried in
;     the order up, down, left, right, leaving out the direction it
;     came from; the first one with all !Battle_PathMark bits set (a
;     marked cell, or the goal $FF) gives the direction d (right is
;     taken without that test, as in BattleAct_FindPath's trace). If
;     the neighbour is the goal, the walk ends. Else, if the cell two
;     ahead (!BattleRom_PathAhead +0) is the goal the walk ends, and if
;     it is marked the step is straight (kind d * 8). Otherwise the
;     first diagonal ahead (+1) is looked at: the goal ends the walk,
;     marked makes it the step, kind d * 8 + 1, or + 3 when the side
;     cell next to it (!BattleRom_PathSide +1) has any of the mark bits
;     set; if it is not marked, the other diagonal (+2) is the step
;     (the goal still ends the walk), kind + 2, or + 4 with its side
;     cell (+2) set. The kind's !BattleRom_PathFromDir and
;     !BattleRom_PathFacing entries go to !Battler_PathFromDir and
;     !Battler_Facing, and the new cell to !Battler_PathCell. So the
;     walk ends when the goal is the neighbour cell, two cells straight
;     ahead (a straight step moves one cell, so a straight approach stops
;     two cells short) or diagonally ahead. That kinds 3 and 4
;     are curved diagonals is from the $CC:F494/$CC:F594 entries.
;     When the walk ends, !Battler_PathWalking is cleared and the
;     thread advances by its !Battle_ActThreadPathLen.
; Threads 4 and 8-15 do nothing but advance by their
; !Battle_ActThreadPathLen. Quirk: only the battler part above writes
; that byte, for threads 0-3, so these threads advance by whatever it
; holds (if 0, they stay on this opcode for good).
; Callers: BattleAct_OpcodeTable entries $16 (BattleAct_OpPathTo), $17
;   (BattleAct_OpPathToUnkPoint) and $18 (BattleAct_OpPathToCalc);
;   BattleAct_PathToPoint is reached only from these three.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered;
;        !Battle_ActCalcOutA/B = the point; DP $80 = the slot (threads
;        0-3), $8E = the length; a start also leaves
;        BattleAct_FindPath's state and DP; a step DP $82 and $84-$86
; Callees: BattleAct_RunCalc, BattleAct_FindPath,
;          BattleAct_AdvanceScript (JMP)
!BattleAct_WalkSlot = !BattleTmp_80     ; 2 B: the walking battler's slot (X; 1 B as Y)
!BattleAct_WalkCell = !BattleTmp_82     ; 1 B: the cell it walks from
!BattleAct_WalkNext = !BattleTmp_84     ; 2 B: the cell of the step (the neighbour, or the diagonal)
!BattleAct_WalkKind = !BattleTmp_85     ; 1 B: the step kind, direction * 8 + 0-4
!BattleAct_WalkDiag = !BattleTmp_86     ; 2 B: the diagonal cell while its side cell is tested
BattleAct_OpPathTo:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActCalcOutA
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActCalcOutB
    LDA.b #3
    STA.b !BattleAct_MoveLen
    BRA BattleAct_PathToPoint

BattleAct_OpPathToUnkPoint:             ; header: see BattleAct_OpPathTo
    LDA.w !Battle_ActUnkPointX
    STA.w !Battle_ActCalcOutA
    LDA.w !Battle_ActUnkPointY
    STA.w !Battle_ActCalcOutB
    LDA.b #1
    STA.b !BattleAct_MoveLen
    BRA BattleAct_PathToPoint

BattleAct_OpPathToCalc:                 ; header: see BattleAct_OpPathTo
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    JSR BattleAct_RunCalc
    LDA.b #2
    STA.b !BattleAct_MoveLen
BattleAct_PathToPoint:                  ; header: see BattleAct_OpPathTo
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    JMP .advance_kept
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BNE .one_battler
    JMP .advance_kept
.one_battler:
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    STX.b !BattleAct_WalkSlot
    LDA.w !Battler_PathWalking,X
    BNE .walking
    LDA.w !Battler_ScreenX,X
    STA.b !BattleAct_PathFromX
    STA.w !Battler_PathStartX,X
    LDA.w !Battler_ScreenY,X
    STA.w !Battler_PathStartY,X
    STA.b !BattleAct_PathFromY
    LDA.w !Battle_ActCalcOutA
    STA.b !BattleAct_PathToX
    LDA.w !Battle_ActCalcOutB
    STA.b !BattleAct_PathToY
    INC.w !Battler_UnkA166,X
    LDX.w !Battle_ActThread
    LDA.b !BattleAct_MoveLen
    STA.w !Battle_ActThreadPathLen,X
    JSR BattleAct_FindPath
    LDA.w !Battle_ActThread
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    STX.b !BattleAct_WalkSlot
    LDA.w !Battle_PathStartCell
    STA.w !Battler_PathCell,X
    LDA.b !BattleAct_WalkSlot
    ASL A
    TAX
    REP #$20
    LDA.l !BattleRom_SlotTimes256,X
    TAY
    TDC
    TAX
    SEP #$20
.copy_map:
    LDA.w !Battle_PathMap,X
    STA.w !Battler_PathMaps,Y
    INY
    INX
    CPX.w #!Battle_PathMapBytes
    BNE .copy_map
    LDY.b !BattleAct_WalkSlot
    TDC
    STA.w !Battler_PathStepKind,Y
    STA.w !Battler_UnkA522,Y
    LDA.b #!Battle_PathDirNone
    STA.w !Battler_PathFromDir,Y
    STA.w !Battler_PathStepFrame,Y
    LDA.b #1
    STA.w !Battler_PathWalking,Y
    JMP .wait
.walking:
    LDX.b !BattleAct_WalkSlot
    LDA.w !Battler_PathStepFrame,X
    BMI .next_step
    JMP .stepping
.next_step:
    LDA.b #!Battle_PathStepFrames
    STA.w !Battler_PathStepFrame,X
    LDA.b !BattleAct_WalkSlot
    ASL A
    TAX
    REP #$21
    LDA.l !BattleRom_SlotTimes256,X
    ADC.w #!Battler_PathMaps
    TAX
    LDY.w #!Battle_PathWalkMap
    LDA.w #!Battle_PathMapBytes-1
    MVN !Battle_WramBank,!Battle_WramBank ; lint-ok: MVN takes bank bytes and has no width suffix
    TDC
    SEP #$20
    LDX.b !BattleAct_WalkSlot
    LDA.w !Battler_PathCell,X
    STA.b !BattleAct_WalkCell
    LDA.w !Battler_PathFromDir,X
    BEQ .try_down                   ; came from above
    CLC
    LDA.b !BattleAct_WalkCell
    ADC.b #!Battle_PathUp
    TAY
    STY.b !BattleAct_WalkNext
    LDA.w !Battle_PathWalkMap,Y
    AND.b #!Battle_PathMark
    CMP.b #!Battle_PathMark
    BNE .try_down
    TDC                             ; !Battle_PathDirUp
    BRA .direction
.try_down:
    LDA.w !Battler_PathFromDir,X
    CMP.b #!Battle_PathDirDown
    BEQ .try_left
    CLC
    LDA.b !BattleAct_WalkCell
    ADC.b #!Battle_PathDown
    TAY
    STY.b !BattleAct_WalkNext
    LDA.w !Battle_PathWalkMap,Y
    AND.b #!Battle_PathMark
    CMP.b #!Battle_PathMark
    BNE .try_left
    LDA.b #!Battle_PathDirDown
    BRA .direction
.try_left:
    LDA.w !Battler_PathFromDir,X
    CMP.b #!Battle_PathDirLeft
    BEQ .take_right
    CLC
    LDA.b !BattleAct_WalkCell
    ADC.b #!Battle_PathLeft
    TAY
    STY.b !BattleAct_WalkNext
    LDA.w !Battle_PathWalkMap,Y
    AND.b #!Battle_PathMark
    CMP.b #!Battle_PathMark
    BNE .take_right
    LDA.b #!Battle_PathDirLeft
    BRA .direction
.take_right:
    CLC                             ; not tested (see the header)
    LDA.b !BattleAct_WalkCell
    ADC.b #!Battle_PathRight
    TAY
    STY.b !BattleAct_WalkNext
    LDA.b #!Battle_PathDirRight
.direction:
    ASL A
    ASL A
    ASL A
    STA.b !BattleAct_WalkKind
    TAX
    LDA.w !Battle_PathWalkMap,Y
    CMP.b #!Battle_PathCellGoal
    BNE .look_ahead
    JMP .walk_done
.look_ahead:                    ; the goal two cells ahead also ends the walk
    CLC
    LDA.b !BattleAct_WalkCell
    ADC.l !BattleRom_PathAhead,X
    TAY
    LDA.w !Battle_PathWalkMap,Y
    CMP.b #!Battle_PathCellGoal
    BNE .ahead_not_goal
    JMP .walk_done
.ahead_not_goal:
    AND.b #!Battle_PathMark
    CMP.b #!Battle_PathMark
    BEQ .set_step                   ; straight on
    CLC
    LDA.b !BattleAct_WalkCell
    ADC.l !BattleRom_PathAhead+1,X
    TAY
    LDA.w !Battle_PathWalkMap,Y
    CMP.b #!Battle_PathCellGoal
    BEQ .walk_done
    AND.b #!Battle_PathMark
    CMP.b #!Battle_PathMark
    BNE .other_diagonal
    STY.b !BattleAct_WalkDiag
    CLC
    LDA.b !BattleAct_WalkCell
    ADC.l !BattleRom_PathSide+1,X
    TAY
    LDA.w !Battle_PathWalkMap,Y
    AND.b #!Battle_PathMark
    BEQ .diagonal1
    LDY.b !BattleAct_WalkDiag
    INC.b !BattleAct_WalkKind       ; + 3: curved
    INC.b !BattleAct_WalkKind
    INC.b !BattleAct_WalkKind
    BRA .take_diagonal
.diagonal1:
    LDY.b !BattleAct_WalkDiag
    INC.b !BattleAct_WalkKind       ; + 1
    BRA .take_diagonal
.other_diagonal:
    CLC
    LDA.b !BattleAct_WalkCell
    ADC.l !BattleRom_PathAhead+2,X
    TAY
    LDA.w !Battle_PathWalkMap,Y
    CMP.b #!Battle_PathCellGoal
    BEQ .walk_done
    STY.b !BattleAct_WalkDiag
    CLC
    LDA.b !BattleAct_WalkCell
    ADC.l !BattleRom_PathSide+2,X
    TAY
    LDA.w !Battle_PathWalkMap,Y
    AND.b #!Battle_PathMark
    BEQ .diagonal2
    LDY.b !BattleAct_WalkDiag
    INC.b !BattleAct_WalkKind       ; + 4: curved
    INC.b !BattleAct_WalkKind
    INC.b !BattleAct_WalkKind
    INC.b !BattleAct_WalkKind
    BRA .take_diagonal
.diagonal2:
    LDY.b !BattleAct_WalkDiag
    INC.b !BattleAct_WalkKind       ; + 2
    INC.b !BattleAct_WalkKind
.take_diagonal:
    TYA
    STA.b !BattleAct_WalkNext
.set_step:
    LDA.b !BattleAct_WalkKind
    TAX
    LDY.b !BattleAct_WalkSlot
    LDA.b !BattleAct_WalkKind
    STA.w !Battler_PathStepKind,Y
    LDA.l !BattleRom_PathFromDir,X
    STA.w !Battler_PathFromDir,Y
    LDA.l !BattleRom_PathFacing,X
    STA.w !Battler_Facing,Y
    LDA.b !BattleAct_WalkNext
    STA.w !Battler_PathCell,Y
.stepping:
    BRA .wait
.walk_done:
    LDX.b !BattleAct_WalkSlot
    STZ.w !Battler_PathWalking,X
.advance_kept:
    LDX.w !Battle_ActThread
    LDA.w !Battle_ActThreadPathLen,X
    JMP BattleAct_AdvanceScript
.wait:
    LDA.b #0
    JMP BattleAct_AdvanceScript     ; by 0: same opcode next frame

; ==================================================================
; BattleAct_OpSetPos ($C15611–$C15693, 131 bytes, with
; BattleAct_SetPosToPoint, BattleAct_OpSetPosUnkPoint and
; BattleAct_OpSetPosCalc)
; ==================================================================
; The place opcodes: put the thread's actor at a point at once (no
; move). The point is put in DP $80/$81 (x, y) and DP $8E holds the
; opcode's length:
;   - $19 <x> <y> (BattleAct_OpSetPos): the point from the operands;
;     length 3;
;   - $1A (BattleAct_OpSetPosUnkPoint): !Battle_ActUnkPointX/Y; length 1;
;   - $1B <n> (BattleAct_OpSetPosCalc): the point left by
;     BattleAct_RunCalc handler n; length 2.
; BattleAct_SetPosToPoint writes it to !Battler_ScreenX/Y of the
; thread's battler (threads 0-3), of every slot of the target set
; (thread 4), or to the object's !Battle_ActObjX/Y with the high bytes
; zeroed (threads 8-15); then advances by the length.
; Callers: BattleAct_OpcodeTable entries $19 (BattleAct_OpSetPos), $1A
;   (BattleAct_OpSetPosUnkPoint) and $1B (BattleAct_OpSetPosCalc);
;   BattleAct_SetPosToPoint is reached only from these three (JMP at
;   $C1:567A and $C1:5691).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered; DP $80-$81 =
;        the point, $8E = the length
; Callees: BattleAct_RunCalc, BattleAct_AdvanceScript (JMP)
!BattleAct_PosX = !BattleTmp_80         ; 1 B: x of the point
!BattleAct_PosY = !BattleTmp_81         ; 1 B: y of the point
BattleAct_OpSetPos:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_PosX
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_PosY
    LDA.b #3
    STA.b !BattleAct_MoveLen
BattleAct_SetPosToPoint:                ; header: see BattleAct_OpSetPos
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .object
    CMP.b #!Battle_ActTargetSetThread
    BEQ .target_set
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.b !BattleAct_PosX
    STA.w !Battler_ScreenX,X
    LDA.b !BattleAct_PosY
    STA.w !Battler_ScreenY,X
    BRA .advance
.target_set:
    TDC
    TAY
.set_slot:
    LDA.w !Battle_ActTargetSet,Y
    BMI .set_done
    TAX
    LDA.b !BattleAct_PosX
    STA.w !Battler_ScreenX,X
    LDA.b !BattleAct_PosY
    STA.w !Battler_ScreenY,X
    INY
    BRA .set_slot
.set_done:
    BRA .advance
.object:
    LDA.w !Battle_ActObjThread
    ASL A
    TAX
    LDA.b !BattleAct_PosX
    STA.w !Battle_ActObjX,X
    STZ.w !Battle_ActObjX+1,X
    LDA.b !BattleAct_PosY
    STA.w !Battle_ActObjY,X
    STZ.w !Battle_ActObjY+1,X
.advance:
    LDA.b !BattleAct_MoveLen
    JMP BattleAct_AdvanceScript

BattleAct_OpSetPosUnkPoint:             ; header: see BattleAct_OpSetPos
    LDA.b #1
    STA.b !BattleAct_MoveLen
    LDA.w !Battle_ActUnkPointX
    STA.b !BattleAct_PosX
    LDA.w !Battle_ActUnkPointY
    STA.b !BattleAct_PosY
    JMP BattleAct_SetPosToPoint

BattleAct_OpSetPosCalc:                 ; header: see BattleAct_OpSetPos
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    JSR BattleAct_RunCalc
    LDA.w !Battle_ActCalcOutA
    STA.b !BattleAct_PosX
    LDA.w !Battle_ActCalcOutB
    STA.b !BattleAct_PosY
    LDA.b #2
    STA.b !BattleAct_MoveLen
    JMP BattleAct_SetPosToPoint

; ==================================================================
; BattleAct_OpFollow ($C15694–$C156BA, 39 bytes)
; ==================================================================
; Opcode $1C <n>: on an object thread, makes the object follow
; something: !Battle_ActObjFollow of the object = entry n of
; !Battle_ActBattlers (a battler slot) for n below
; !Battle_ActFollowFirstObj, else !Battle_ActFollowObj + (n - 9) (object
; thread n - 9). $CF:ECC2 (unmatched) then copies the slot's
; !Battler_ScreenX/Y, or the other object's !Battle_ActObjX/Y, to the
; object's position each frame. On other threads it does nothing.
; Goes on with the next opcode in the same frame; advances 2.
; Callers: BattleAct_OpcodeTable entry $1C.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; on an object thread X = the
;        object thread, Y = 1; !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpFollow:
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .next
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    CMP.b #!Battle_ActFollowFirstObj
    BCS .object
    TAX
    LDA.w !Battle_ActBattlers,X
    BRA .store
.object:
    SEC
    SBC.b #!Battle_ActFollowFirstObj
    ORA.b #!Battle_ActFollowObj
.store:
    LDX.w !Battle_ActObjThread
    STA.w !Battle_ActObjFollow,X
.next:
    INC.w !Battle_ActNextOp
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpUnfollow ($C156BB–$C156CB, 17 bytes)
; ==================================================================
; Opcode $1D <j>: object thread j follows nothing any more
; (!Battle_ActObjFollow = !Battle_ActFollowNone), whatever thread runs
; it. Goes on with the next opcode in the same frame; advances 2.
; Callers: BattleAct_OpcodeTable entry $1D.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = j, Y = 1;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpUnfollow:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    TAX
    LDA.b #!Battle_ActFollowNone
    STA.w !Battle_ActObjFollow,X
    INC.w !Battle_ActNextOp
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpCall ($C156CC–$C156FA, 47 bytes)
; ==================================================================
; Opcode $1E <n>: calls subscript n: keeps the address after the
; opcode (pointer + 2, the carry going into the bank) in the thread's
; !Battle_ActThreadReturn / !Battle_ActThreadReturnBank and goes to
; entry n of !BattleRom_ActSubscripts, always in bank
; !BattleRom_ScriptBankPc, running it in the same frame. One level
; only: a call inside a subscript overwrites the return address.
; Callers: BattleAct_OpcodeTable entry $1E.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = n * 2; Y = thread * 4;
;        !Battle_ActScriptPtr (and $E9) set; !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP, by 0)
BattleAct_OpCall:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    ASL A
    TAX
    LDA.w !Battle_ActThreadOfs
    TAY
    REP #$21
    LDA.w #2
    ADC.b !Battle_ActScriptPtr
    STA.w !Battle_ActThreadReturn,Y
    LDA.b !Battle_ActScriptPtr+2
    ADC.w #0
    STA.w !Battle_ActThreadReturnBank,Y
    LDA.l !BattleRom_ActSubscripts,X
    STA.b !Battle_ActScriptPtr
    LDA.w #!BattleRom_ScriptBankPc
    STA.b !Battle_ActScriptPtr+2
    TDC
    SEP #$20
    INC.w !Battle_ActNextOp
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpReturn ($C156FB–$C15713, 25 bytes)
; ==================================================================
; Opcode $1F: returns from a subscript (BattleAct_OpCall): the script
; pointer = the thread's !Battle_ActThreadReturn / ReturnBank, and the
; next opcode runs in the same frame.
; Callers: BattleAct_OpcodeTable entry $1F; BattleAct_OpReturnIfVar1F0
;   branches here.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; Y = thread * 4; X unchanged;
;        !Battle_ActScriptPtr (and $E9) set; !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP, by 0)
BattleAct_OpReturn:
    LDA.w !Battle_ActThreadOfs
    TAY
    REP #$20
    LDA.w !Battle_ActThreadReturn,Y
    STA.b !Battle_ActScriptPtr
    LDA.w !Battle_ActThreadReturnBank,Y
    STA.b !Battle_ActScriptPtr+2
    TDC
    SEP #$20
    INC.w !Battle_ActNextOp
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpPause ($C15714–$C15721, 14 bytes)
; ==================================================================
; Opcode $20 <n>: ends the thread's turn for this frame and has
; BattleAct_RunThread only count !Battle_ActThreadWait = n down on the
; next n frames before running the next opcode; advances 2.
; Callers: BattleAct_OpcodeTable entry $20.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = thread; Y = 1
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpPause:
    INY
    LDX.w !Battle_ActThread
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActThreadWait,X
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpReturnIfVar1F0 ($C15722–$C1572B, 10 bytes)
; ==================================================================
; Opcode $21: when variable $1F (!Battle_ActUnkPointY) is 0, returns
; from the subscript like opcode $1F; otherwise advances 1 (and the
; thread waits for the next frame). Why the y of the point is the
; test is not known.
; Callers: BattleAct_OpcodeTable entry $21.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; as BattleAct_OpReturn when it
;        returns; X, Y unchanged otherwise
; Callees: BattleAct_OpReturn (BEQ), BattleAct_AdvanceScript (JMP)
BattleAct_OpReturnIfVar1F0:
    LDA.w !Battle_ActUnkPointY
    BEQ BattleAct_OpReturn
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpWaitVar ($C1572C–$C15742, 23 bytes)
; ==================================================================
; Opcode $22 <n> <v>: waits until variable n (!Battle_ActVars + n) is
; v: while it is not, stays on the opcode (advance 0); then goes on
; with the next opcode in the same frame, advancing 3.
; Callers: BattleAct_OpcodeTable entry $22.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = n; Y = 2; when equal
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpWaitVar:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    TAX
    INY
    LDA.w !Battle_ActVars,X
    CMP.b [!Battle_ActScriptPtr],Y
    BEQ .equal
    TDC
    BRA .advance
.equal:
    INC.w !Battle_ActNextOp
    LDA.b #3
.advance:
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpWaitVar1C ($C15743–$C15755, 19 bytes)
; ==================================================================
; Opcode $23 <v>: as opcode $22 for variable $1C (!Battle_ActVar1C);
; advances 2 when it is v.
; Callers: BattleAct_OpcodeTable entry $23.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X unchanged; Y = 1; when equal
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpWaitVar1C:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    CMP.w !Battle_ActVar1C
    BEQ .equal
    TDC
    BRA .advance
.equal:
    INC.w !Battle_ActNextOp
    LDA.b #2
.advance:
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpWaitVar1D ($C15756–$C15768, 19 bytes)
; ==================================================================
; Opcode $24 <v>: as opcode $23 for variable $1D (!Battle_ActVar1D).
; Callers: BattleAct_OpcodeTable entry $24.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X unchanged; Y = 1; when equal
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpWaitVar1D:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    CMP.w !Battle_ActVar1D
    BEQ .equal
    TDC
    BRA .advance
.equal:
    INC.w !Battle_ActNextOp
    LDA.b #2
.advance:
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpEndIfNoTarget ($C15769–$C1577C, 20 bytes)
; ==================================================================
; Opcode $25 <i>: when entry i of !Battle_ActTargetSet is the end
; marker (bit 7 set: the set has fewer than i + 1 slots), switches the
; thread off (BattleAct_OpEndThread); otherwise goes on with the next
; opcode in the same frame, advancing 2. No bound check: an i past the
; end marker reads whatever follows it.
; Callers: BattleAct_OpcodeTable entry $25.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; as BattleAct_OpEndThread when the
;        thread ends (X = thread); else A = 0, X = i, Y = 1 and
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript, BattleAct_OpEndThread (JMP)
BattleAct_OpEndIfNoTarget:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    TAX
    LDA.w !Battle_ActTargetSet,X
    BMI .end
    INC.w !Battle_ActNextOp
    LDA.b #2
    JMP BattleAct_AdvanceScript
.end:
    JMP BattleAct_OpEndThread

; ==================================================================
; BattleAct_OpShowAnimEntry ($C1577D–$C15805, 137 bytes)
; ==================================================================
; Opcode $26 <n> <f>: like opcodes $04-$06 (BattleAct_OpShowAnimFrame)
; with the stop byte f from the operand: starts animation n with the
; actor's stop byte = f, so that BattleAct_StepBattlerAnims shows its
; entry f - 1 and switches it off; then waits for the animation to be
; off and advances 3. The stop byte is also the "started" flag:
;   - threads 0-3: !Battler_ActAnimStop of the battler, started in mode
;     1 (BattleAct_StartAnim stays on the opcode); cleared when its
;     !Battler_ActAnimMode is 0;
;   - thread 4: the stop byte of the first slot of the target set only;
;     done when every slot's mode is 0. Quirk: that stop byte is not
;     cleared, as in BattleAct_OpPlayAnim;
;   - threads 8-15: !Battle_ActObjAnimStop; done when
;     !Battle_ActUnkA1A8 is 0. Quirk: the start uses mode 2
;     (!Battle_ActAnimLoop), for which BattleAct_StartAnim itself
;     advances 2 and counts !Battle_ActNextOp up; this handler then
;     advances by 0, so the pointer is left on the f operand, which
;     runs as the next opcode in the same frame.
; While waiting it returns without calling BattleAct_AdvanceScript.
; Callers: BattleAct_OpcodeTable entry $26.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $80 = f and
;        $82-$83 = 0 written; when it starts, BattleAct_StartAnim's DP
;        scratch ($80 then = n) and $8E
; Callees: BattleAct_StartAnim (JMP or JSR), BattleAct_AdvanceScript
;          (JMP)
!BattleAct_ShowStop = !BattleTmp_80     ; 1 B: the stop byte f (BattleAct_StartAnim then reuses $80)
!BattleAct_ShowOpY = !BattleTmp_82      ; 2 B: Y on entry (0), for BattleAct_StartAnim's operand read
BattleAct_OpShowAnimEntry:
    STY.b !BattleAct_ShowOpY
    INY
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_ShowStop
    LDY.b !BattleAct_ShowOpY
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .object
    CMP.b #!Battle_ActTargetSetThread
    BEQ .target_set
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.w !Battler_ActAnimStop,X
    BNE .battler_wait
    LDA.b !BattleAct_ShowStop
    STA.w !Battler_ActAnimStop,X
    LDA.b #!Battle_ActAnimOnce
    STA.b !BattleAct_AnimMode
    JMP BattleAct_StartAnim
.battler_wait:
    LDA.w !Battler_ActAnimMode,X
    BNE .battler_exit
    STZ.w !Battler_ActAnimStop,X
    LDA.b #3
    JMP BattleAct_AdvanceScript
.battler_exit:
    RTS
.target_set:
    LDA.w !Battle_ActTargetSet
    TAX
    LDA.w !Battler_ActAnimStop,X
    BNE .set_wait
    LDA.b !BattleAct_ShowStop
    STA.w !Battler_ActAnimStop,X
    LDA.b #!Battle_ActAnimOnce
    STA.b !BattleAct_AnimMode
    JMP BattleAct_StartAnim
.set_wait:
    TDC
    TAY
.set_slot:
    LDA.w !Battle_ActTargetSet,Y
    BMI .set_done
    TAX
    LDA.w !Battler_ActAnimMode,X
    BNE .set_exit
    INY
    BRA .set_slot
.set_done:
    LDA.b #3
    JMP BattleAct_AdvanceScript
.set_exit:
    RTS
.object:
    LDX.w !Battle_ActObjThread
    LDA.w !Battle_ActObjAnimStop,X
    BNE .object_wait
    LDA.b !BattleAct_ShowStop
    STA.w !Battle_ActObjAnimStop,X
    LDA.b #!Battle_ActAnimLoop
    STA.b !BattleAct_AnimMode
    JSR BattleAct_StartAnim
    TDC
    BRA .advance
.object_wait:
    LDA.w !Battle_ActUnkA1A8,X
    BNE .object_exit
    STZ.w !Battle_ActObjAnimStop,X
    LDA.b #3
.advance:
    JMP BattleAct_AdvanceScript
.object_exit:
    RTS

; ==================================================================
; BattleAct_OpSetUnkA5CD ($C15806–$C15843, 62 bytes, with
; BattleAct_StoreUnkA5CD and BattleAct_OpClearUnkA5CD)
; ==================================================================
; Opcodes $27 (BattleAct_OpSetUnkA5CD, value 1) and $28
; (BattleAct_OpClearUnkA5CD, value 0): set !Battler_UnkA5CD of the
; thread's battler (threads 0-3) or of every slot of the target set
; (thread 4) to the value, keeping its bit 7 (the bit
; Battle_BoxOverlapsOthers skips on); object threads change nothing.
; The value is in DP $8E. Advances 1. What the low bits mean is not
; known.
; Callers: BattleAct_OpcodeTable entries $27 and $28;
;   BattleAct_StoreUnkA5CD is reached from BattleAct_OpClearUnkA5CD.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered; DP $8E = the
;        value
; Callees: BattleAct_AdvanceScript (JMP)
!BattleAct_FlagValue = !BattleTmp_8E    ; 1 B: the value stored
BattleAct_OpSetUnkA5CD:
    LDA.b #1
    STA.b !BattleAct_FlagValue
BattleAct_StoreUnkA5CD:                 ; header: see BattleAct_OpSetUnkA5CD
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .advance
    CMP.b #!Battle_ActTargetSetThread
    BEQ .target_set
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.w !Battler_UnkA5CD,X
    AND.b #!Battle_ActKeepBit7
    ORA.b !BattleAct_FlagValue
    STA.w !Battler_UnkA5CD,X
    BRA .advance
.target_set:
    TDC
    TAY
.set_slot:
    LDA.w !Battle_ActTargetSet,Y
    BMI .advance
    TAX
    LDA.w !Battler_UnkA5CD,X
    AND.b #!Battle_ActKeepBit7
    ORA.b !BattleAct_FlagValue
    STA.w !Battler_UnkA5CD,X
    INY
    BRA .set_slot
.advance:
    LDA.b #1
    JMP BattleAct_AdvanceScript

BattleAct_OpClearUnkA5CD:               ; header: see BattleAct_OpSetUnkA5CD
    STZ.b !BattleAct_FlagValue
    BRA BattleAct_StoreUnkA5CD

; ==================================================================
; BattleAct_OpSetUnk9FF7 ($C15844–$C1587C, 57 bytes, with
; BattleAct_StoreUnk9FF7 and BattleAct_OpClearUnk9FF7)
; ==================================================================
; Opcodes $29 (BattleAct_OpSetUnk9FF7, value 1) and $2A
; (BattleAct_OpClearUnk9FF7, value 0): as opcodes $27/$28 for
; !Battler_Unk9FF7 (bit 7: skipped by the target scans). Quirk: for
; the thread's battler (threads 0-3) the value is stored as it is, so
; bit 7 is cleared; only the target-set path keeps it. Advances 1.
; Callers: BattleAct_OpcodeTable entries $29 and $2A;
;   BattleAct_StoreUnk9FF7 is reached from BattleAct_OpClearUnk9FF7.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered; DP $8E = the
;        value
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpSetUnk9FF7:
    LDA.b #1
    STA.b !BattleAct_FlagValue
BattleAct_StoreUnk9FF7:                 ; header: see BattleAct_OpSetUnk9FF7
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .advance
    CMP.b #!Battle_ActTargetSetThread
    BEQ .target_set
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.b !BattleAct_FlagValue
    STA.w !Battler_Unk9FF7,X        ; quirk: bit 7 not kept
    BRA .advance
.target_set:
    TDC
    TAY
.set_slot:
    LDA.w !Battle_ActTargetSet,Y
    BMI .advance
    TAX
    LDA.w !Battler_Unk9FF7,X
    AND.b #!Battle_ActKeepBit7
    ORA.b !BattleAct_FlagValue
    STA.w !Battler_Unk9FF7,X
    INY
    BRA .set_slot
.advance:
    LDA.b #1
    JMP BattleAct_AdvanceScript

BattleAct_OpClearUnk9FF7:               ; header: see BattleAct_OpSetUnk9FF7
    STZ.b !BattleAct_FlagValue
    BRA BattleAct_StoreUnk9FF7

; ==================================================================
; BattleAct_OpClearUnkA4A4 ($C1587D–$C158AA, 46 bytes)
; ==================================================================
; Opcode $2B: zeroes !Battler_UnkA4A4 and !Battler_UnkA4AF of the
; thread's battler (threads 0-3) or of every slot of the target set
; (thread 4); object threads change nothing. Advances 1. Both bytes
; are used by the movers in bank $CF; what they mean is not known.
; Callers: BattleAct_OpcodeTable entry $2B.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpClearUnkA4A4:
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .advance
    CMP.b #!Battle_ActTargetSetThread
    BEQ .target_set
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    STZ.w !Battler_UnkA4A4,X
    STZ.w !Battler_UnkA4AF,X
    BRA .advance
.target_set:
    TDC
    TAY
.set_slot:
    LDA.w !Battle_ActTargetSet,Y
    BMI .advance
    TAX
    STZ.w !Battler_UnkA4A4,X
    STZ.w !Battler_UnkA4AF,X
    INY
    BRA .set_slot
.advance:
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpUnkRevive ($C158AB–$C158DB, 49 bytes)
; ==================================================================
; Opcode $2C: for the thread's battler (threads 0-3) or every slot of
; the target set (thread 4): counts !Battler_Present up and zeroes
; !Battler_KoFlag; object threads change nothing. Goes on with the next
; opcode in the same frame; advances 1. Probably brings the battler
; back into the battle (inferred only from the two names); "up", not
; "= 1", so a present battler gets 2.
; Callers: BattleAct_OpcodeTable entry $2C.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpUnkRevive:
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .next
    CMP.b #!Battle_ActTargetSetThread
    BEQ .target_set
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    INC.w !Battler_Present,X
    STZ.w !Battler_KoFlag,X
    BRA .next
.target_set:
    TDC
    TAY
.set_slot:
    LDA.w !Battle_ActTargetSet,Y
    BMI .next
    TAX
    INC.w !Battler_Present,X
    STZ.w !Battler_KoFlag,X
    INY
    BRA .set_slot
.next:
    INC.w !Battle_ActNextOp
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpSetUnkCFFF ($C158DC–$C158E3, 8 bytes)
; ==================================================================
; Opcode $2D: !Battle_ActUnkCFFF = 1; advances 1.
; Callers: BattleAct_OpcodeTable entry $2D.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y unchanged
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpSetUnkCFFF:
    LDA.b #1
    STA.w !Battle_ActUnkCFFF
    JMP BattleAct_AdvanceScript     ; by the 1 just stored

; ==================================================================
; BattleAct_OpClearUnkCFFF ($C158E4–$C158EB, 8 bytes)
; ==================================================================
; Opcode $2E: !Battle_ActUnkCFFF = 0; advances 1.
; Callers: BattleAct_OpcodeTable entry $2E.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y unchanged
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpClearUnkCFFF:
    STZ.w !Battle_ActUnkCFFF
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; The script variable opcodes ($C158EC–$C159B8): set, count and add
; to the bytes of !Battle_ActVars; variables $1C and $1D have opcodes
; of their own. All but $33 go on with the next opcode in the same
; frame (!Battle_ActNextOp counted up). Each is reached only through
; BattleAct_OpcodeTable, at the entry its header names.
; ==================================================================
; BattleAct_OpSetVar ($C158EC–$C158FD, 18 bytes)
; ==================================================================
; Opcode $30 <n> <v>: variable n = v; advances 3.
; Callers: BattleAct_OpcodeTable entry $30.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = n; Y = 2;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpSetVar:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    TAX
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActVars,X
    INC.w !Battle_ActNextOp
    LDA.b #3
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpSetVar1C ($C158FE–$C1590B, 14 bytes)
; ==================================================================
; Opcode $31 <v>: !Battle_ActVar1C = v; advances 2.
; Callers: BattleAct_OpcodeTable entry $31.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X unchanged; Y = 1;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpSetVar1C:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActVar1C
    INC.w !Battle_ActNextOp
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpSetVar1D ($C1590C–$C15919, 14 bytes)
; ==================================================================
; Opcode $32 <v>: !Battle_ActVar1D = v; advances 2.
; Callers: BattleAct_OpcodeTable entry $32.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X unchanged; Y = 1;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpSetVar1D:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActVar1D
    INC.w !Battle_ActNextOp
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpCalcToUnkPoint ($C1591A–$C15930, 23 bytes)
; ==================================================================
; Opcode $33 <n>: runs BattleAct_RunCalc handler n and keeps its point
; in !Battle_ActUnkPointX/Y (variables $1E/$1F), for the "UnkPoint"
; move opcodes; advances 2, and the thread waits for the next frame.
; Callers: BattleAct_OpcodeTable entry $33.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X unchanged, Y = 1 (BattleAct_RunCalc
;        keeps them); whatever the handler writes
; Callees: BattleAct_RunCalc, BattleAct_AdvanceScript (JMP)
BattleAct_OpCalcToUnkPoint:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    JSR BattleAct_RunCalc
    LDA.w !Battle_ActCalcOutA
    STA.w !Battle_ActUnkPointX
    LDA.w !Battle_ActCalcOutB
    STA.w !Battle_ActUnkPointY
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpIncVar ($C15931–$C1593F, 15 bytes)
; ==================================================================
; Opcode $34 <n>: variable n + 1; advances 2.
; Callers: BattleAct_OpcodeTable entry $34.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = n; Y = 1;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpIncVar:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    TAX
    INC.w !Battle_ActVars,X
    INC.w !Battle_ActNextOp
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpIncVar1C ($C15940–$C1594A, 11 bytes)
; ==================================================================
; Opcode $35: !Battle_ActVar1C + 1; advances 1.
; Callers: BattleAct_OpcodeTable entry $35.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y unchanged;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpIncVar1C:
    INC.w !Battle_ActVar1C
    INC.w !Battle_ActNextOp
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpIncVar1D ($C1594B–$C15955, 11 bytes)
; ==================================================================
; Opcode $36: !Battle_ActVar1D + 1; advances 1.
; Callers: BattleAct_OpcodeTable entry $36.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y unchanged;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpIncVar1D:
    INC.w !Battle_ActVar1D
    INC.w !Battle_ActNextOp
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpDecVar ($C15956–$C15964, 15 bytes)
; ==================================================================
; Opcode $37 <n>: variable n - 1; advances 2.
; Callers: BattleAct_OpcodeTable entry $37.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = n; Y = 1;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpDecVar:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    TAX
    DEC.w !Battle_ActVars,X
    INC.w !Battle_ActNextOp
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpDecVar1C ($C15965–$C1596F, 11 bytes)
; ==================================================================
; Opcode $38: !Battle_ActVar1C - 1; advances 1.
; Callers: BattleAct_OpcodeTable entry $38.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y unchanged;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpDecVar1C:
    DEC.w !Battle_ActVar1C
    INC.w !Battle_ActNextOp
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpDecVar1D ($C15970–$C1597A, 11 bytes)
; ==================================================================
; Opcode $39: !Battle_ActVar1D - 1; advances 1.
; Callers: BattleAct_OpcodeTable entry $39.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y unchanged;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpDecVar1D:
    DEC.w !Battle_ActVar1D
    INC.w !Battle_ActNextOp
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpAddVar ($C1597B–$C15990, 22 bytes)
; ==================================================================
; Opcode $3A <n> <v>: variable n + v (8-bit, wraps); advances 3.
; Callers: BattleAct_OpcodeTable entry $3A.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = n; Y = 2;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpAddVar:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    TAX
    INY
    CLC
    LDA.b [!Battle_ActScriptPtr],Y
    ADC.w !Battle_ActVars,X
    STA.w !Battle_ActVars,X
    INC.w !Battle_ActNextOp
    LDA.b #3
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpAddVar1C ($C15991–$C159A2, 18 bytes)
; ==================================================================
; Opcode $3B <v>: !Battle_ActVar1C + v; advances 2.
; Callers: BattleAct_OpcodeTable entry $3B.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X unchanged; Y = 1;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpAddVar1C:
    INY
    CLC
    LDA.b [!Battle_ActScriptPtr],Y
    ADC.w !Battle_ActVar1C
    STA.w !Battle_ActVar1C
    INC.w !Battle_ActNextOp
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpAddVarTo1C ($C159A3–$C159B8, 22 bytes)
; ==================================================================
; Opcode $3C <n>: !Battle_ActVar1C + variable n; advances 2.
; Callers: BattleAct_OpcodeTable entry $3C.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = n; Y = 1;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpAddVarTo1C:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    TAX
    CLC
    LDA.w !Battle_ActVars,X
    ADC.w !Battle_ActVar1C
    STA.w !Battle_ActVar1C
    INC.w !Battle_ActNextOp
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpCalcToResult ($C159B9–$C159E3, 43 bytes)
; ==================================================================
; Opcodes $3D-$40 and $45-$46 <n> (one handler): runs BattleAct_RunCalc
; handler n once and stores its two results in entry k of
; !Battle_ActCalcResult: k = opcode - $3D for $3D-$40 (0-3), opcode -
; $41 for $45-$46 (4-5); the same entries BattleAct_TickCalcs fills
; every frame for the handlers in !Battle_ActCalcSel. Goes on with the
; next opcode in the same frame; advances 2.
; Callers: BattleAct_OpcodeTable entries $3D-$40, $45 and $46.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread); !Battle_ActOpcode = one of those
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = k * 2; Y = 1;
;        !Battle_ActNextOp counted up; whatever the handler writes
; Callees: BattleAct_RunCalc, BattleAct_AdvanceScript (JMP)
BattleAct_OpCalcToResult:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    JSR BattleAct_RunCalc
    LDA.w !Battle_ActOpcode
    CMP.b #!Battle_ActOpCalcToResult4
    BCC .first_four
    SEC
    SBC.b #!Battle_ActOpCalcToResult4-4
    BRA .store
.first_four:
    SEC
    SBC.b #!Battle_ActOpCalcToResult
.store:
    ASL A
    TAX
    LDA.w !Battle_ActCalcOutA
    STA.w !Battle_ActCalcResult,X
    LDA.w !Battle_ActCalcOutB
    STA.w !Battle_ActCalcResult+1,X
    INC.w !Battle_ActNextOp
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpCopyVar ($C159E4–$C159F9, 22 bytes)
; ==================================================================
; Opcode $41 <a> <b>: variable b = variable a; advances 3.
; Callers: BattleAct_OpcodeTable entry $41.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = a; Y = b;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpCopyVar:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    TAX
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    TAY
    LDA.w !Battle_ActVars,X
    STA.w !Battle_ActVars,Y
    INC.w !Battle_ActNextOp
    LDA.b #3
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpCopyVar1C ($C159FA–$C15A0B, 18 bytes)
; ==================================================================
; Opcode $42 <n>: variable n = !Battle_ActVar1C; advances 2.
; Callers: BattleAct_OpcodeTable entry $42.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = n; Y = 1;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpCopyVar1C:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    TAX
    LDA.w !Battle_ActVar1C
    STA.w !Battle_ActVars,X
    INC.w !Battle_ActNextOp
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpOffsetToUnkPoint ($C15A0C–$C15A3D, 50 bytes)
; ==================================================================
; Opcode $43 <n> <x> <y>: !Battle_ActUnkPointX/Y = (x, y) plus the point
; of BattleAct_RunCalc handler n (each 8-bit, wrapping); advances 4.
; The operands are stored before the handler runs.
; Callers: BattleAct_OpcodeTable entry $43.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X unchanged, Y = 3
;        (BattleAct_RunCalc keeps them); DP $80 = n;
;        !Battle_ActNextOp counted up; whatever the handler writes
; Callees: BattleAct_RunCalc, BattleAct_AdvanceScript (JMP)
!BattleAct_OffsetCalc = !BattleTmp_80   ; 1 B: the handler number n
BattleAct_OpOffsetToUnkPoint:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_OffsetCalc
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActUnkPointX
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActUnkPointY
    LDA.b !BattleAct_OffsetCalc
    JSR BattleAct_RunCalc
    CLC
    LDA.w !Battle_ActCalcOutA
    ADC.w !Battle_ActUnkPointX
    STA.w !Battle_ActUnkPointX
    CLC
    LDA.w !Battle_ActCalcOutB
    ADC.w !Battle_ActUnkPointY
    STA.w !Battle_ActUnkPointY
    INC.w !Battle_ActNextOp
    LDA.b #4
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpActorPosToUnkPoint ($C15A3E–$C15A6F, 50 bytes)
; ==================================================================
; Opcode $44: !Battle_ActUnkPointX/Y = the position of the thread's
; actor: !Battler_ScreenX/Y of its !Battle_ActBattlers entry, or the
; object's !Battle_ActObjX/Y on threads 8-15. Thread 4 has no case of
; its own, so it takes entry 4 of the list, the first slot of the
; target set. Advances 1; the thread waits for the next frame.
; Callers: BattleAct_OpcodeTable entry $44.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X clobbered; Y unchanged; on
;        threads 0-4 DP $82-$83 = the slot (not read after)
; Callees: BattleAct_AdvanceScript (JMP)
!BattleAct_PosSlot = !BattleTmp_82      ; 2 B: the battler slot (written, not read)
BattleAct_OpActorPosToUnkPoint:
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .object
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    STX.b !BattleAct_PosSlot
    LDA.w !Battler_ScreenX,X
    STA.w !Battle_ActUnkPointX
    LDA.w !Battler_ScreenY,X
    STA.w !Battle_ActUnkPointY
    BRA .advance
.object:
    LDA.w !Battle_ActObjThread
    ASL A
    TAX
    LDA.w !Battle_ActObjX,X
    STA.w !Battle_ActUnkPointX
    LDA.w !Battle_ActObjY,X
    STA.w !Battle_ActUnkPointY
.advance:
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpAddVarClamped ($C15A70–$C15A98, 41 bytes)
; ==================================================================
; Opcode $49 <n> <d>: variable n + d, with d signed and the result
; clamped to 0-$FF (a carry out of a positive add gives $FF, a negative
; add with no carry gives 0); advances 3.
; Callers: BattleAct_OpcodeTable entry $49.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = n; Y = 2; DP $80 = d;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
!BattleAct_VarDelta = !BattleTmp_80     ; 1 B: d
BattleAct_OpAddVarClamped:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    TAX
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_VarDelta
    BMI .subtract
    CLC
    ADC.w !Battle_ActVars,X
    BCC .store
    LDA.b #!Battle_ActVarMax         ; clamp at the top
    BRA .store
.subtract:
    CLC
    LDA.b !BattleAct_VarDelta
    ADC.w !Battle_ActVars,X
    BCS .store
    TDC                             ; clamp at 0
.store:
    STA.w !Battle_ActVars,X
    INC.w !Battle_ActNextOp
    LDA.b #3
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpSwapVar1C1D ($C15A99–$C15AAE, 22 bytes)
; ==================================================================
; Opcodes $4A and $4D: swaps !Battle_ActVar1C and !Battle_ActVar1D;
; advances 1.
; Callers: BattleAct_OpcodeTable entries $4A and $4D.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y unchanged;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpSwapVar1C1D:
    LDA.w !Battle_ActVar1C
    PHA
    LDA.w !Battle_ActVar1D
    STA.w !Battle_ActVar1C
    PLA
    STA.w !Battle_ActVar1D
    INC.w !Battle_ActNextOp
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpSwapVar1C1E ($C15AAF–$C15AC4, 22 bytes)
; ==================================================================
; Opcode $4E: swaps !Battle_ActVar1C and variable $1E
; (!Battle_ActUnkPointX); advances 1.
; Callers: BattleAct_OpcodeTable entry $4E.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y unchanged;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpSwapVar1C1E:
    LDA.w !Battle_ActVar1C
    PHA
    LDA.w !Battle_ActUnkPointX
    STA.w !Battle_ActVar1C
    PLA
    STA.w !Battle_ActUnkPointX
    INC.w !Battle_ActNextOp
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpSwapVar1C1F ($C15AC5–$C15ADA, 22 bytes)
; ==================================================================
; Opcode $4F: swaps !Battle_ActVar1C and variable $1F
; (!Battle_ActUnkPointY); advances 1.
; Callers: BattleAct_OpcodeTable entry $4F.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y unchanged;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpSwapVar1C1F:
    LDA.w !Battle_ActVar1C
    PHA
    LDA.w !Battle_ActUnkPointY
    STA.w !Battle_ActVar1C
    PLA
    STA.w !Battle_ActUnkPointY
    INC.w !Battle_ActNextOp
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpShowHitNumbers ($C15ADB–$C15CF0, 534 bytes)
; ==================================================================
; Opcodes $50-$55: shows the hit numbers of record set (opcode & 7) as
; digit sprites over the battlers and waits until they have bounced.
; It runs in three states of !Battle_ActUnkA3D1 (which also holds the
; object threads and BattleAct_OpEndScript while it is non-zero):
;  0: parks all $B0 bytes of Battle_HitNumSprite at $F0 (x and y off
;     screen), clears !Battle_HitNumHigh and the four
;     !Battle_ActPalSeqOn flags, copies !Battle_HitNumColoursA/B to
;     !Battle_PaletteLive and !Battle_PaletteLive+$80 (the palettes of
;     attributes !Battle_HitNumAttr and !Battle_HitNumAttrAlt if the
;     buffer is the sprite half of CGRAM, as their palette numbers 0 and
;     4 suggest) and stays on the opcode (advances 0); state 1.
;  1: for each battler slot 0-10, reads its 4-byte record at
;     !BattleRom_HitSetOffset[set] + slot * 4 in !Battle_ActPcHitAmount/
;     Kind. Kind 0: nothing drawn. Kind 5: the tiles
;     !Battle_HitNumTileK5A/B in the two right-hand places. Any other
;     kind: the amount through BattleMsg_FormatNumber4Digits, leading
;     zeros not drawn; kinds 1 and 2 get the palette-4 attribute, kinds
;     other than 1, 3 and 5 set !Battler_HitNumAltBounce. The digits go
;     at the battler's screen x (plus !Battler_ScreenOffsetX/Y when
;     !Battler_UnkA003 is set) + !BattleRom_HitNumDigitX[zeros], which
;     centres them; each drawn sprite clears its x bit 8 in the slot's
;     high-table byte. Then !Battle_HitNumActive = 1; advances 0;
;     state 2.
;  2: advances 0 while !Battle_HitNumActive is set ($CF:E781 clears it
;     when the bounce ends); then state 0 and advances 1.
; Quirks: kind 5 also writes $90 to the byte before !BattleMsg_Digit1000
; ($949B), which nothing here reads; DP $92-$93 are zeroed and never
; read; the sprite offset of a slot with no hit is stepped with an
; 8-bit add (it never passes $B0).
; Callers: BattleAct_OpcodeTable entries $50-$55.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered; in state 1
;        DP $80-$85, $8C, $8E-$95 and BattleMsg_FormatNumber4Digits'
;        !BattleMsg_NumValue and digit bytes written
; Callees: BattleMsg_FormatNumber4Digits, BattleAct_AdvanceScript (JMP)
!BattleAct_HitRecOfs = !BattleTmp_80    ; 2 B: offset of the slot's record in !Battle_ActPcHitAmount
!BattleAct_HitSprOfs = !BattleTmp_82    ; 2 B: offset of the slot's sprites in Battle_HitNumSprite
!BattleAct_HitHigh = !BattleTmp_84      ; 1 B: the slot's high-table byte being built
!BattleAct_HitAttr = !BattleTmp_8C      ; 1 B: attribute of the slot's sprites
!BattleAct_HitZeros = !BattleTmp_8E     ; 1 B: leading zeros (0-3); HitDigitX then overwrites it
!BattleAct_HitDigitX = !BattleTmp_8E    ; 4 B ($8E-$91): x offset of each digit place
!BattleAct_HitUnk92 = !BattleTmp_92     ; 2 B: zeroed, not read
!BattleAct_HitX = !BattleTmp_94         ; 1 B: the battler's screen x
!BattleAct_HitY = !BattleTmp_94+1       ; 1 B: its screen y
BattleAct_OpShowHitNumbers:
    LDA.w !Battle_ActUnkA3D1
    BNE .state_1_or_2
    INC.w !Battle_ActUnkA3D1        ; state 0 -> 1
    LDX.w #!Battle_HitNumSpriteBytes-1
    LDA.b #!BattleOam_OffscreenY
.park:
    STA.w Battle_HitNumSprite.X,X   ; every byte, so x and y are both $F0
    DEX
    BPL .park
    LDX.w #!Battle_LastSlot
.clear_high:
    STZ.w !Battle_HitNumHigh,X
    DEX
    BPL .clear_high
    STZ.w !Battle_ActPalSeqOn
    STZ.w !Battle_ActPalSeqOn+1
    STZ.w !Battle_ActPalSeqOn+2
    STZ.w !Battle_ActPalSeqOn+3
    TDC
    TAY
.colours_a:
    LDA.w !Battle_HitNumColoursA,Y
    STA.w !Battle_PaletteLive,Y
    INY
    CPY.w #!Battle_HitNumColourBytes
    BNE .colours_a
    TDC
    TAY
.colours_b:
    LDA.w !Battle_HitNumColoursB,Y
    STA.w !Battle_PaletteLive+(!Battle_SpecialPalette*16),Y ; +$80, the bytes opcode $69 also fills
    INY
    CPY.w #!Battle_HitNumColourBytes
    BNE .colours_b
    TDC
    JMP BattleAct_AdvanceScript     ; 0: the same opcode next frame

.state_1_or_2:
    LDA.w !Battle_ActUnkA3D1
    CMP.b #1
    BEQ .build
    JMP .wait
.build:
    STZ.w !Battle_HitNumStep
    INC.w !Battle_ActUnkA3D1        ; state 1 -> 2
    LDA.w !Battle_ActOpcode
    AND.b #!Battle_HitNumSetMask
    STA.w !Battle_HitNumSet
    TAX
    LDA.l !BattleRom_HitSetOffset,X
    TAX
    STX.b !BattleAct_HitRecOfs
    TDC
    TAY                             ; Y = battler slot
    STY.b !BattleAct_HitSprOfs
    STY.b !BattleAct_HitUnk92
.slot:
    LDA.b #!Battle_HitNumAttr
    STA.b !BattleAct_HitAttr
    LDA.w !Battler_UnkA003,Y
    BNE .offset_position
    LDA.w !Battler_ScreenX,Y
    STA.b !BattleAct_HitX
    LDA.w !Battler_ScreenY,Y
    STA.b !BattleAct_HitY
    BRA .kind
.offset_position:
    CLC
    LDA.w !Battler_ScreenX,Y
    ADC.w !Battler_ScreenOffsetX,Y
    STA.b !BattleAct_HitX
    CLC
    LDA.w !Battler_ScreenY,Y
    ADC.w !Battler_ScreenOffsetY,Y
    STA.b !BattleAct_HitY
.kind:
    LDX.b !BattleAct_HitRecOfs
    LDA.w !Battle_ActPcHitKind,X
    BNE .has_hit
    JMP .no_hit
.has_hit:
    CMP.b #!Battle_ActHitKind5
    BNE .not_kind5
    LDA.b #!Battle_HitNumTileZero
    STA.w !BattleMsg_Digit1000-1    ; quirk: $949B, not read here
    STA.w !BattleMsg_Digit1000
    STA.w !BattleMsg_Digit100
    LDA.b #!Battle_HitNumTileK5A
    STA.w !BattleMsg_Digit10
    LDA.b #!Battle_HitNumTileK5B
    STA.w !BattleMsg_Digit1
    LDA.b #2                        ; placed as a number with two leading zeros
    STA.b !BattleAct_HitZeros
    BRA .place
.not_kind5:
    CMP.b #!Battle_ActHitKind3
    BEQ .format
    CMP.b #!Battle_ActHitKind1
    BEQ .alt_attr
    LDA.b #1
    STA.w !Battler_HitNumAltBounce,Y
    LDA.w !Battle_ActPcHitKind,X
    CMP.b #!Battle_ActHitKind2
    BNE .format
.alt_attr:
    LDA.b #!Battle_HitNumAttrAlt
    STA.b !BattleAct_HitAttr
.format:
    REP #$20
    LDA.w !Battle_ActPcHitAmount,X
    STA.w !BattleMsg_NumValue
    JSL BattleMsg_FormatNumber4Digits
    SEP #$20
    STZ.b !BattleAct_HitZeros
    LDA.w !BattleMsg_Digit1000
    CMP.b #!Battle_HitNumTileZero
    BNE .place
    INC.b !BattleAct_HitZeros
    LDA.w !BattleMsg_Digit100
    CMP.b #!Battle_HitNumTileZero
    BNE .place
    INC.b !BattleAct_HitZeros
    LDA.w !BattleMsg_Digit10
    CMP.b #!Battle_HitNumTileZero
    BNE .place
    INC.b !BattleAct_HitZeros
.place:
    LDA.b !BattleAct_HitZeros
    ASL A
    ASL A
    TAX
    LDA.l !BattleRom_HitNumDigitX,X
    STA.b !BattleAct_HitDigitX
    LDA.l !BattleRom_HitNumDigitX+1,X
    STA.b !BattleAct_HitDigitX+1
    LDA.l !BattleRom_HitNumDigitX+2,X
    STA.b !BattleAct_HitDigitX+2
    LDA.l !BattleRom_HitNumDigitX+3,X
    STA.b !BattleAct_HitDigitX+3
    LDA.b #!Battle_HitNumHighHidden
    STA.b !BattleAct_HitHigh
    LDX.b !BattleAct_HitSprOfs
    LDA.w !BattleMsg_Digit1000      ; thousands: drawn unless a zero
    CMP.b #!Battle_HitNumTileZero
    BEQ .hundreds
    LDA.w !BattleMsg_Digit1000
    STA.w Battle_HitNumSprite.Tile,X
    CLC
    LDA.b !BattleAct_HitX
    ADC.b !BattleAct_HitDigitX
    STA.w Battle_HitNumSprite.X,X
    LDA.b !BattleAct_HitY
    STA.w Battle_HitNumSprite.Y,X
    LDA.b !BattleAct_HitAttr
    STA.w Battle_HitNumSprite.Attr,X
    LDA.b !BattleAct_HitHigh
    AND.b #!Battle_HitNumShow0
    STA.b !BattleAct_HitHigh
.hundreds:
    INX
    INX
    INX
    INX
    LDA.w !BattleMsg_Digit100       ; drawn unless a leading zero
    CMP.b #!Battle_HitNumTileZero
    BNE .draw_hundreds
    LDA.w !BattleMsg_Digit1000
    CMP.b #!Battle_HitNumTileZero
    BEQ .tens
.draw_hundreds:
    LDA.w !BattleMsg_Digit100
    STA.w Battle_HitNumSprite.Tile,X
    CLC
    LDA.b !BattleAct_HitX
    ADC.b !BattleAct_HitDigitX+1
    STA.w Battle_HitNumSprite.X,X
    LDA.b !BattleAct_HitY
    STA.w Battle_HitNumSprite.Y,X
    LDA.b !BattleAct_HitAttr
    STA.w Battle_HitNumSprite.Attr,X
    LDA.b !BattleAct_HitHigh
    AND.b #!Battle_HitNumShow1
    STA.b !BattleAct_HitHigh
.tens:
    INX
    INX
    INX
    INX
    LDA.w !BattleMsg_Digit10        ; drawn unless a leading zero
    CMP.b #!Battle_HitNumTileZero
    BNE .draw_tens
    LDA.w !BattleMsg_Digit100
    CMP.b #!Battle_HitNumTileZero
    BNE .draw_tens
    LDA.w !BattleMsg_Digit1000
    CMP.b #!Battle_HitNumTileZero
    BEQ .ones
.draw_tens:
    LDA.w !BattleMsg_Digit10
    STA.w Battle_HitNumSprite.Tile,X
    CLC
    LDA.b !BattleAct_HitX
    ADC.b !BattleAct_HitDigitX+2
    STA.w Battle_HitNumSprite.X,X
    LDA.b !BattleAct_HitY
    STA.w Battle_HitNumSprite.Y,X
    LDA.b !BattleAct_HitAttr
    STA.w Battle_HitNumSprite.Attr,X
    LDA.b !BattleAct_HitHigh
    AND.b #!Battle_HitNumShow2
    STA.b !BattleAct_HitHigh
.ones:
    INX
    INX
    INX
    INX
    LDA.w !BattleMsg_Digit1         ; always drawn
    STA.w Battle_HitNumSprite.Tile,X
    CLC
    LDA.b !BattleAct_HitX
    ADC.b !BattleAct_HitDigitX+3
    STA.w Battle_HitNumSprite.X,X
    LDA.b !BattleAct_HitY
    STA.w Battle_HitNumSprite.Y,X
    LDA.b !BattleAct_HitAttr
    STA.w Battle_HitNumSprite.Attr,X
    LDA.b !BattleAct_HitHigh
    AND.b #!Battle_HitNumShow3
    STA.b !BattleAct_HitHigh
    INX
    INX
    INX
    INX
    STX.b !BattleAct_HitSprOfs
    LDA.b !BattleAct_HitHigh
    STA.w !Battle_HitNumHigh,Y
    LDA.b #1
    STA.w !Battler_HitNumShown,Y
    BRA .next_slot
.no_hit:
    CLC
    LDA.b !BattleAct_HitSprOfs
    ADC.b #!Battle_HitNumSlotBytes
    STA.b !BattleAct_HitSprOfs
.next_slot:
    LDX.b !BattleAct_HitRecOfs
    INX
    INX
    INX
    INX
    STX.b !BattleAct_HitRecOfs
    INY
    CPY.w #!Battle_NumSlots
    BEQ .built
    JMP .slot
.built:
    LDA.b #1
    STA.w !Battle_HitNumActive
    TDC
    JMP BattleAct_AdvanceScript     ; 0: wait from next frame on

.wait:
    LDA.w !Battle_HitNumActive
    BEQ .done
    TDC
    JMP BattleAct_AdvanceScript     ; 0: still bouncing
.done:
    STZ.w !Battle_ActUnkA3D1
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpClearUnk9FF7Bit7 ($C15CF1–$C15D17, 39 bytes, with
; BattleAct_StoreUnk9FF7Bit7 and BattleAct_OpSetUnk9FF7Bit7)
; ==================================================================
; Opcodes $5D (BattleAct_OpClearUnk9FF7Bit7, DP $8E = 0) and $5E
; (BattleAct_OpSetUnk9FF7Bit7, DP $8E = $80): sets bit 7 of the
; thread's battler's !Battler_Unk9FF7 (the target scans' skip bit) to
; that value, keeping bits 0-6. Only threads 0-3 act; threads 4-15
; (the target-set thread included, unlike opcodes $29/$2A) change
; nothing. Advances 1. Quirk: the test for the object threads is made
; before the test that already covers them.
; Callers: BattleAct_OpcodeTable entries $5D and $5E;
;   BattleAct_StoreUnk9FF7Bit7 is reached from BattleAct_OpSetUnk9FF7Bit7.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X clobbered (the slot for
;        threads 0-3); Y unchanged; DP $8E = the bit value
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpClearUnk9FF7Bit7:
    STZ.b !BattleAct_FlagValue
BattleAct_StoreUnk9FF7Bit7:             ; header: see BattleAct_OpClearUnk9FF7Bit7
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .advance
    CMP.b #!Battle_ActTargetSetThread
    BCS .advance                    ; threads 4-7 too
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.w !Battler_Unk9FF7,X
    AND.b #!Battle_ActClearBit7
    ORA.b !BattleAct_FlagValue
    STA.w !Battler_Unk9FF7,X
.advance:
    LDA.b #1
    JMP BattleAct_AdvanceScript

BattleAct_OpSetUnk9FF7Bit7:             ; header: see BattleAct_OpClearUnk9FF7Bit7
    LDA.b #!Battle_Unk9FF7Skip
    STA.b !BattleAct_FlagValue
    BRA BattleAct_StoreUnk9FF7Bit7

; ==================================================================
; BattleAct_OpNop2 ($C15D18–$C15D1C, 5 bytes)
; ==================================================================
; Opcode $5F <x>: does nothing; advances 2 (over its operand).
; Callers: BattleAct_OpcodeTable entry $5F.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y unchanged
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpNop2:
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; The palette opcodes ($C15D1D–$C15FA4): colour sets from the
; action's palette list (!Battle_ActPalPtr) and its four palette
; sequences, opcode $69's special palette and its blink, and the
; colour rotation run at $CF:E600. Each is reached only through
; BattleAct_OpcodeTable, at the entries its header names.
; ==================================================================
; BattleAct_OpLoadPalEntry ($C15D1D–$C15D92, 118 bytes)
; ==================================================================
; Opcode $60 <n>: copies the colour set of entry n of the action's
; palette list (bank $CD, !Battle_ActPalPtr + n * 2) into
; !Battle_PaletteLive+2 + (flags & 7) * 8: 6 bytes of
; !BattleRom_PalSets6 or, with flags bit 7, 14 bytes of
; !BattleRom_PalSets14. The same copy as one step of
; BattleAct_StepPalettes ($CC:F1E7), which places with flags & 3.
; Goes on with the next opcode in the same frame; advances 2.
; Callers: BattleAct_OpcodeTable entry $60.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered; DP $80-$85
;        written; !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
!BattleAct_PalSet2 = !BattleTmp_80      ; 2 B: set * 2
!BattleAct_PalLeft = !BattleTmp_82      ; 1 B: the flags, then bytes left to copy (set * 4 on the 14-byte path)
!BattleAct_PalSet6 = !BattleTmp_84      ; 2 B: set * 6 (14-byte path)
BattleAct_OpLoadPalEntry:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    REP #$20
    ASL A
    CLC
    ADC.w !Battle_ActPalPtr
    TAX
    TDC
    SEP #$20
    LDA.l !BattleRom_PalListFlags,X
    STA.b !BattleAct_PalLeft
    AND.b #!Battle_PalListPosMask
    ASL A
    ASL A
    ASL A
    TAY                             ; Y = (flags & 7) * 8
    LDA.b !BattleAct_PalLeft
    BMI .set14
    LDA.l !BattleRom_PalListSet,X
    REP #$20
    ASL A
    STA.b !BattleAct_PalSet2
    ASL A
    CLC
    ADC.b !BattleAct_PalSet2
    TAX                             ; set * 6
    TDC
    SEP #$20
    LDA.b #!Battle_PalSet6Len
    STA.b !BattleAct_PalLeft
.copy6:
    LDA.l !BattleRom_PalSets6,X
    STA.w !Battle_PaletteLive+2,Y
    INX
    INY
    DEC.b !BattleAct_PalLeft
    BNE .copy6
    BRA .next
.set14:
    LDA.l !BattleRom_PalListSet,X
    REP #$20
    ASL A
    STA.b !BattleAct_PalSet2
    ASL A
    STA.b !BattleAct_PalLeft        ; set * 4
    CLC
    ADC.b !BattleAct_PalSet2
    STA.b !BattleAct_PalSet6
    LDA.b !BattleAct_PalLeft
    ASL A
    CLC
    ADC.b !BattleAct_PalSet6
    TAX                             ; set * 8 + set * 6 = set * 14
    TDC
    SEP #$20
    LDA.b #!Battle_PalSet14Len
    STA.b !BattleAct_PalLeft
.copy14:
    LDA.l !BattleRom_PalSets14,X
    STA.w !Battle_PaletteLive+2,Y
    INX
    INY
    DEC.b !BattleAct_PalLeft
    BNE .copy14
.next:
    INC.w !Battle_ActNextOp
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpStartPalSeq ($C15D93–$C15DC0, 46 bytes)
; ==================================================================
; Opcodes $61-$64 <delay> <first> <last>: starts palette sequence
; opcode - $61 (0-3) for BattleAct_StepPalettes ($CC:F1E7): it loads
; the palette-list entries first..last in turn, one every delay frames,
; starting with the next frame, and wraps back to first. Goes on with
; the next opcode in the same frame; advances 4.
; Callers: BattleAct_OpcodeTable entries $61-$64.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = the sequence; Y = 3;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpStartPalSeq:
    SEC
    LDA.w !Battle_ActOpcode
    SBC.b #!Battle_ActOpStartPalSeq
    TAX
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActPalSeqDelay,X
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActPalSeqFirst,X
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActPalSeqLast,X
    LDA.b #1
    STA.w !Battle_ActPalSeqTimer,X
    STA.w !Battle_ActPalSeqOn,X
    LDA.b #!Battle_PalSeqStepStart
    STA.w !Battle_ActPalSeqStep,X
    INC.w !Battle_ActNextOp
    LDA.b #4
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpStopPalSeq ($C15DC1–$C15DD2, 18 bytes)
; ==================================================================
; Opcodes $65-$68: stops palette sequence opcode - $65 (0-3); the
; colours it last loaded stay. Goes on with the next opcode in the same
; frame; advances 1.
; Callers: BattleAct_OpcodeTable entries $65-$68.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = the sequence; Y unchanged;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpStopPalSeq:
    SEC
    LDA.w !Battle_ActOpcode
    SBC.b #!Battle_ActOpStopPalSeq
    TAX
    STZ.w !Battle_ActPalSeqOn,X
    INC.w !Battle_ActNextOp
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpSetSpecialPalette ($C15DD3–$C15E86, 180 bytes, with
; BattleAct_SpecialPaletteBody)
; ==================================================================
; Opcode $69 <n>: gives the thread's battler (threads 0-3) or every
; slot of the target set (threads 4-15, the object threads included)
; !Battler_Palette = !Battle_SpecialPalette, and fills that palette
; (!Battle_PaletteLive+$82, from its second colour on) with the 24
; bytes of entry n of !BattleRom_SpecialPals and six bytes of $FF.
; When !Battle_Unk99D2 is set and one of those battlers has
; !Battler_UnkA08C set (for threads 0-3 only an enemy, slot 3 on), it
; also fills !Battle_PaletteLiveLo from colour !Battle_Unk99D3 to its
; end with the entry's 12 colours over and over. Goes on with the next
; opcode in the same frame; advances by DP $8E: 2 here.
; BattleAct_SpecialPaletteBody is the same with DP $80 = n and DP $8E
; set by the caller: BattleAct_OpBlinkPalette ($C1:5F54, $C1:5F85)
; jumps there with $8E = 0, so its opcode is run again in the same
; frame.
; Callers: BattleAct_OpcodeTable entry $69; BattleAct_SpecialPaletteBody
;   from BattleAct_OpBlinkPalette ($C1:5F54, $C1:5F85; JMP).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered; DP $80-$87 and
;        $8E written; !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
!BattleAct_PalEntry = !BattleTmp_80     ; 2 B: n, then n * 8
!BattleAct_PalLo = !BattleTmp_82        ; 1 B: non-zero = fill !Battle_PaletteLiveLo too
!BattleAct_PalSrc = !BattleTmp_84       ; 2 B: n * 24, the entry's offset
!BattleAct_PalWords = !BattleTmp_86     ; 2 B: colours left of one pass
!BattleAct_PalAdvance = !BattleTmp_8E   ; 1 B: bytes to advance by
BattleAct_OpSetSpecialPalette:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_PalEntry
    LDA.b #2
    STA.b !BattleAct_PalAdvance
BattleAct_SpecialPaletteBody:           ; header: see BattleAct_OpSetSpecialPalette
    STZ.b !BattleAct_PalLo
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActTargetSetThread
    BCS .target_set
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    CMP.b #!Battle_FirstEnemySlot
    BCC .set_one
    LDA.w !Battle_Unk99D2
    BEQ .set_one
    LDA.w !Battler_UnkA08C,X
    BEQ .set_one
    INC.b !BattleAct_PalLo
.set_one:
    LDA.b #!Battle_SpecialPalette
    STA.w !Battler_Palette,X
    BRA .copy
.target_set:
    TDC
    TAX
.set_slot:
    LDA.w !Battle_ActTargetSet,X
    BMI .copy
    TAY
    LDA.w !Battle_Unk99D2
    BEQ .set_palette
    LDA.w !Battler_UnkA08C,Y
    BEQ .set_palette
    INC.b !BattleAct_PalLo
.set_palette:
    LDA.b #!Battle_SpecialPalette
    STA.w !Battler_Palette,Y
    INX
    BRA .set_slot
.copy:
    LDA.b !BattleAct_PalEntry
    REP #$20
    ASL A
    ASL A
    ASL A
    STA.b !BattleAct_PalEntry
    ASL A
    CLC
    ADC.b !BattleAct_PalEntry
    TAX                             ; n * 24
    STX.b !BattleAct_PalSrc
    TDC
    SEP #$20
    TDC
    TAY
.copy_byte:
    LDA.l !BattleRom_SpecialPals,X
    STA.w !Battle_PaletteLive+(!Battle_SpecialPalette*16)+2,Y
    INX
    INY
    CPY.w #!Battle_SpecialPalLen
    BNE .copy_byte
    LDA.b #!Battle_SpecialPalFill
    STA.w !Battle_PaletteLive+(!Battle_SpecialPalette*16)+2,Y
    STA.w !Battle_PaletteLive+(!Battle_SpecialPalette*16)+3,Y
    STA.w !Battle_PaletteLive+(!Battle_SpecialPalette*16)+4,Y
    STA.w !Battle_PaletteLive+(!Battle_SpecialPalette*16)+5,Y
    STA.w !Battle_PaletteLive+(!Battle_SpecialPalette*16)+6,Y
    STA.w !Battle_PaletteLive+(!Battle_SpecialPalette*16)+7,Y
    LDA.b !BattleAct_PalLo
    BEQ .next
    LDA.w !Battle_Unk99D3
    REP #$20
    ASL A
    TAY
.pass:
    LDX.b !BattleAct_PalSrc
    LDA.w #!Battle_SpecialPalLen/2
    STA.b !BattleAct_PalWords
.copy_colour:
    LDA.l !BattleRom_SpecialPals,X
    STA.w !Battle_PaletteLiveLo,Y
    INX
    INX
    INY
    INY
    CPY.w #!Battle_PaletteLoBytes
    BEQ .lo_done
    DEC.b !BattleAct_PalWords
    BNE .copy_colour
    BRA .pass
.lo_done:
    TDC
    SEP #$20
.next:
    INC.w !Battle_ActNextOp
    LDA.b !BattleAct_PalAdvance
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpRestorePalette ($C15E87–$C15EDE, 88 bytes, with
; BattleAct_RestorePaletteBody)
; ==================================================================
; Opcode $6A: undoes opcode $69: gives the thread's battler (threads
; 0-3) or every slot of the target set (threads 4-15) its
; !Battler_BasePalette back. For an enemy of threads 0-3 (slot 3 on)
; while !Battle_Unk99D2 is set it also copies !Battle_PaletteSavedLo
; back over !Battle_PaletteLiveLo from colour !Battle_Unk99D3 on
; (without testing !Battler_UnkA08C); the target-set path never does,
; although opcode $69's does fill it. Advances by DP $8E: 1 here.
; BattleAct_RestorePaletteBody is the same with DP $8E set by the
; caller: BattleAct_OpBlinkPalette jumps there with 3 ($C1:5F1C) or 0
; ($C1:5F59, $C1:5F8A).
; Callers: BattleAct_OpcodeTable entry $6A; BattleAct_RestorePaletteBody
;   from BattleAct_OpBlinkPalette ($C1:5F1C, $C1:5F59, $C1:5F8A; JMP).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered; DP $8E written
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpRestorePalette:
    LDA.b #1
    STA.b !BattleAct_PalAdvance
BattleAct_RestorePaletteBody:           ; header: see BattleAct_OpRestorePalette
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActTargetSetThread
    BCS .target_set
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    CMP.b #!Battle_FirstEnemySlot
    BCC .restore_one
    LDA.w !Battle_Unk99D2
    BEQ .restore_one
    LDA.w !Battler_BasePalette,X
    STA.w !Battler_Palette,X
    BRA .restore_lo
.restore_one:
    LDA.w !Battler_BasePalette,X
    STA.w !Battler_Palette,X
    BRA .advance
.restore_lo:
    LDA.w !Battle_Unk99D3
    REP #$20
    ASL A
    TAX
.copy_colour:
    LDA.w !Battle_PaletteSavedLo,X
    STA.w !Battle_PaletteLiveLo,X
    INX
    INX
    CPX.w #!Battle_PaletteLoBytes
    BNE .copy_colour
    TDC
    SEP #$20
    BRA .advance
.target_set:
    TDC
    TAX
.restore_slot:
    LDA.w !Battle_ActTargetSet,X
    BMI .advance
    TAY
    LDA.w !Battler_BasePalette,Y
    STA.w !Battler_Palette,Y
    INX
    BRA .restore_slot
.advance:
    LDA.b !BattleAct_PalAdvance
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpStartPalCycle ($C15EDF–$C15F12, 52 bytes)
; ==================================================================
; Opcode $6B <delay>: starts the colour rotation at $CF:E600
; (unmatched): every delay frames it turns the colours of
; !Battle_PaletteLive+$82-$99 (the special palette's 12 colours) on by
; one. !Battle_PalCycleTimer = 1, !Battle_UnkAB4E (its on flag) = 1.
; When !Battle_Unk99D2 is set, the first battler from the main target
; on (!Battle_ActMainTarget, then the target set) that has
; !Battler_UnkA08C set and the special palette counts
; !Battle_PalCycleLo up, so the !Battle_PaletteLiveLo colours turn too.
; Advances 2.
; Callers: BattleAct_OpcodeTable entry $6B.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered (Y = 1 or a
;        slot)
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpStartPalCycle:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_PalCycleDelay
    LDA.b #1
    STA.w !Battle_PalCycleTimer
    STA.w !Battle_UnkAB4E
    LDA.w !Battle_Unk99D2
    BEQ .advance
    TDC
    TAX
.check_slot:
    LDA.w !Battle_ActMainTarget,X
    BMI .advance
    TAY
    LDA.w !Battler_UnkA08C,Y
    BEQ .next_slot
    LDA.w !Battler_Palette,Y
    CMP.b #!Battle_SpecialPalette
    BNE .next_slot
    INC.w !Battle_PalCycleLo
    BRA .advance
.next_slot:
    INX
    BRA .check_slot
.advance:
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpBlinkPalette ($C15F13–$C15F99, 135 bytes)
; ==================================================================
; Opcode $6C <n> <frames>: blinks between opcode $69's special palette
; n and the battler's own palette. While script variable 0
; (!Battle_ActVars) is 0 it runs BattleAct_RestorePaletteBody and
; advances 3; otherwise it stays on the opcode. Object threads only
; advance 3. For the thread's battler (threads 0-3 and 5-7) or each
; slot of the target set (thread 4): while its !Battler_BlinkTimer is
; non-zero it is counted down; at 0 it is reloaded with frames and
; !Battler_BlinkOn toggles, and the handler leaves through
; BattleAct_SpecialPaletteBody (on) or BattleAct_RestorePaletteBody
; (off), with DP $8E = 0 (advance 0), which act for the whole thread
; as their opcodes do; on thread 4 the first slot whose timer ran out
; switches the whole target set. The special-palette body counts
; !Battle_ActNextOp up, so the opcode runs again in the same frame and
; already counts the new timer down once.
; Quirk: each JMP to the special-palette body is followed by a BRA
; that nothing reaches ($C1:5F57, $C1:5F88).
; Callers: BattleAct_OpcodeTable entry $6C.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered; DP $80, $8E,
;        $90-$92 written (and what the bodies write)
; Callees: BattleAct_SpecialPaletteBody, BattleAct_RestorePaletteBody
;   (JMP), BattleAct_AdvanceScript (JMP)
!BattleAct_BlinkSetIdx = !BattleTmp_90  ; 2 B: entry of !Battle_ActTargetSet (thread 4)
!BattleAct_BlinkFrames = !BattleTmp_92  ; 1 B: frames between toggles
BattleAct_OpBlinkPalette:
    LDA.b #3
    STA.b !BattleAct_PalAdvance
    LDA.w !Battle_ActVars
    BNE .blink
    JMP BattleAct_RestorePaletteBody  ; variable 0 is 0: end, advance 3
.blink:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_PalEntry
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_BlinkFrames
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .object
    CMP.b #!Battle_ActTargetSetThread
    BEQ .target_set
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.w !Battler_BlinkTimer,X
    BEQ .toggle
    DEC.w !Battler_BlinkTimer,X
    BRA .stay_one
.toggle:
    LDA.b !BattleAct_BlinkFrames
    STA.w !Battler_BlinkTimer,X
    STZ.b !BattleAct_PalAdvance
    LDA.w !Battler_BlinkOn,X
    EOR.b #1
    STA.w !Battler_BlinkOn,X
    BEQ .off
    JMP BattleAct_SpecialPaletteBody
    BRA .stay_one                   ; quirk: not reached
.off:
    JMP BattleAct_RestorePaletteBody
.stay_one:
    BRA .stay
.target_set:
    TDC
    TAX
    STX.b !BattleAct_BlinkSetIdx
.blink_slot:
    LDX.b !BattleAct_BlinkSetIdx
    LDA.w !Battle_ActTargetSet,X
    BMI .stay
    TAX
    LDA.w !Battler_BlinkTimer,X
    BEQ .toggle_slot
    DEC.w !Battler_BlinkTimer,X
    BRA .next_slot
.toggle_slot:
    LDA.b !BattleAct_BlinkFrames
    STA.w !Battler_BlinkTimer,X
    STZ.b !BattleAct_PalAdvance
    LDA.w !Battler_BlinkOn,X
    EOR.b #1
    STA.w !Battler_BlinkOn,X
    BEQ .off_slot
    JMP BattleAct_SpecialPaletteBody
    BRA .stay                       ; quirk: not reached
.off_slot:
    JMP BattleAct_RestorePaletteBody
.next_slot:
    INC.b !BattleAct_BlinkSetIdx
    BRA .blink_slot
.stay:
    TDC
    JMP BattleAct_AdvanceScript     ; 0: blink on next frame
.object:
    LDA.b #3
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpStopPalCycle ($C15F9A–$C15FA4, 11 bytes)
; ==================================================================
; Opcode $6D: stops opcode $6B's colour rotation (!Battle_UnkAB4E and
; !Battle_PalCycleLo = 0); the colours stay as they were turned.
; Advances 1.
; Callers: BattleAct_OpcodeTable entry $6D.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y unchanged
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpStopPalCycle:
    STZ.w !Battle_UnkAB4E
    STZ.w !Battle_PalCycleLo
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; The object counter opcodes ($C15FA5–$C15FDD): count
; !Battle_ActObjUnkA1D8 up or clear it, for all eight object threads
; or for the running one. Each is reached only through
; BattleAct_OpcodeTable, at the entry its header names.
; ==================================================================
; BattleAct_OpIncAllObjUnkA1D8 ($C15FA5–$C15FB2, 14 bytes)
; ==================================================================
; Opcode $6E: counts !Battle_ActObjUnkA1D8 of object threads 0-7 up;
; advances 1.
; Callers: BattleAct_OpcodeTable entry $6E.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = $FFFF; Y unchanged
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpIncAllObjUnkA1D8:
    LDX.w #!Battle_ActNumObjThreads-1
.object:
    INC.w !Battle_ActObjUnkA1D8,X
    DEX
    BPL .object
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpClearAllObjUnkA1D8 ($C15FB3–$C15FC0, 14 bytes)
; ==================================================================
; Opcode $6F: zeroes !Battle_ActObjUnkA1D8 of object threads 0-7;
; advances 1.
; Callers: BattleAct_OpcodeTable entry $6F.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = $FFFF; Y unchanged
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpClearAllObjUnkA1D8:
    LDX.w #!Battle_ActNumObjThreads-1
.object:
    STZ.w !Battle_ActObjUnkA1D8,X
    DEX
    BPL .object
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpIncObjUnkA1D8 ($C15FC1–$C15FD2, 18 bytes, with
; BattleAct_Op70Body)
; ==================================================================
; Opcode $70: counts !Battle_ActObjUnkA1D8 of the running object
; thread (!Battle_ActObjThread) up; advances 1. Meant for object
; threads: on another thread !Battle_ActObjThread is whatever the last
; object thread left.
; BattleAct_Op70Body is the same without the STZ of DP $8E: with $8E
; non-zero it counts up and returns (RTS) without advancing.
; Callers: BattleAct_OpcodeTable entry $70; BattleAct_Op70Body from
;   BattleAct_OpPlayAnim ($C1:4E8E, JMP, with DP $8E = 1).
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread);
;        BattleAct_Op70Body: DP $8E set
; Exit:  M=1, X=0, DP=0, DB=$7E; X = the object thread; Y unchanged;
;        advanced: A = 0; returned: A = DP $8E
; Callees: BattleAct_AdvanceScript (JMP)
!BattleAct_Op70Return = !BattleTmp_8E   ; 1 B: non-zero = return without advancing
BattleAct_OpIncObjUnkA1D8:
    STZ.b !BattleAct_Op70Return
BattleAct_Op70Body:                     ; header: see BattleAct_OpIncObjUnkA1D8
    LDX.w !Battle_ActObjThread
    INC.w !Battle_ActObjUnkA1D8,X
    LDA.b !BattleAct_Op70Return
    BNE .return
    LDA.b #1
    JMP BattleAct_AdvanceScript
.return:
    RTS

; ==================================================================
; BattleAct_OpClearObjUnkA1D8 ($C15FD3–$C15FDD, 11 bytes)
; ==================================================================
; Opcode $71: zeroes !Battle_ActObjUnkA1D8 of the running object thread;
; advances 1.
; Callers: BattleAct_OpcodeTable entry $71.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = the object thread; Y
;        unchanged
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpClearObjUnkA1D8:
    LDX.w !Battle_ActObjThread
    STZ.w !Battle_ActObjUnkA1D8,X
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpSetFacing ($C15FDE–$C16058, 123 bytes)
; ==================================================================
; Opcode $72 <mode>: sets the facing of the thread's actor from
; BattleAct_CalcFacing with A = mode: !Battler_Facing of the thread's
; battler (threads 0-3) or of every slot of the target set (thread
; 4), or !Battle_ActObjFacing of the object (threads 8-15). Before each
; call DP $80/$81 hold the actor's x/y (!Battler_ScreenX/Y or
; !Battle_ActObjX/Y) and X its slot or object thread. Threads 5-7 are
; taken as battler threads. Advances 2.
; Callers: BattleAct_OpcodeTable entry $72.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered; DP $80-$83 and
;        $8E written, and what the BattleAct_CalcFacing handler writes
; Callees: BattleAct_CalcFacing, BattleAct_AdvanceScript (JMP)
!BattleAct_FaceX = !BattleTmp_80        ; 1 B: the actor's x, for BattleAct_CalcFacing
!BattleAct_FaceY = !BattleTmp_81        ; 1 B: its y
!BattleAct_FaceSlot = !BattleTmp_82     ; 2 B: the battler slot
!BattleAct_FaceMode = !BattleTmp_8E     ; 1 B: the operand
BattleAct_OpSetFacing:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_FaceMode
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .object
    CMP.b #!Battle_ActTargetSetThread
    BEQ .target_set
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    STX.b !BattleAct_FaceSlot
    LDA.w !Battler_ScreenX,X
    STA.b !BattleAct_FaceX
    LDA.w !Battler_ScreenY,X
    STA.b !BattleAct_FaceY
    LDA.b !BattleAct_FaceMode
    JSR BattleAct_CalcFacing
    LDX.b !BattleAct_FaceSlot
    LDA.w !Battle_ActFacingOut
    STA.w !Battler_Facing,X
    BRA .advance
.target_set:
    TDC
    TAY
.set_slot:
    LDA.w !Battle_ActTargetSet,Y
    BMI .set_done
    TAX
    STX.b !BattleAct_FaceSlot
    LDA.w !Battler_ScreenX,X
    STA.b !BattleAct_FaceX
    LDA.w !Battler_ScreenY,X
    STA.b !BattleAct_FaceY
    LDA.b !BattleAct_FaceMode
    JSR BattleAct_CalcFacing
    LDX.b !BattleAct_FaceSlot
    LDA.w !Battle_ActFacingOut
    STA.w !Battler_Facing,X
    INY
    BRA .set_slot
.set_done:
    BRA .advance
.object:
    LDA.w !Battle_ActObjThread
    ASL A
    TAX
    LDA.w !Battle_ActObjX,X
    STA.b !BattleAct_FaceX
    LDA.w !Battle_ActObjY,X
    STA.b !BattleAct_FaceY
    LDX.w !Battle_ActObjThread
    LDA.b !BattleAct_FaceMode
    JSR BattleAct_CalcFacing
    LDX.w !Battle_ActObjThread
    LDA.w !Battle_ActFacingOut
    STA.w !Battle_ActObjFacing,X
.advance:
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpLinkObjBit7 ($C16059–$C16092, 58 bytes, with
; BattleAct_OpLinkObjBit6 and BattleAct_LinkObjBody)
; ==================================================================
; Opcodes $73 (BattleAct_OpLinkObjBit7, DP $8E = $80) and $74
; (BattleAct_OpLinkObjBit6, DP $8E = $40) <n>: links the running object
; thread j (!Battle_ActObjThread) to the battler s in entry n of
; !Battle_ActBattlers: !Battle_ActObjLinkSlot[j] = s and
; !Battle_ActObjLinks[j * 11 + s] = (j & $3F) | DP $8E. What the link
; does is not traced (read at $CF:EDD4 and $CF:F81D); "link" is
; inferred from the two tables only. Meant for object threads.
; Advances 2.
; Callers: BattleAct_OpcodeTable entries $73 and $74;
;   BattleAct_LinkObjBody is reached from BattleAct_OpLinkObjBit7 (BRA)
;   and by falling in from BattleAct_OpLinkObjBit6.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = j * 11 + s; Y = 1; DP $80,
;        $8E and Battle_Mul8's $AD-$B0 and $77/$78 written
; Callees: Battle_Mul8, BattleAct_AdvanceScript (JMP)
!BattleAct_LinkSlot = !BattleTmp_80     ; 1 B: the battler slot s
!BattleAct_LinkFlag = !BattleTmp_8E     ; 1 B: $80 or $40
BattleAct_OpLinkObjBit7:
    LDA.b #!Battle_ActObjLinkBit7
    STA.b !BattleAct_LinkFlag
    BRA BattleAct_LinkObjBody

BattleAct_OpLinkObjBit6:                ; header: see BattleAct_OpLinkObjBit7
    LDA.b #!Battle_ActObjLinkBit6
    STA.b !BattleAct_LinkFlag
BattleAct_LinkObjBody:                  ; header: see BattleAct_OpLinkObjBit7
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    TAX
    LDA.w !Battle_ActBattlers,X
    STA.b !BattleAct_LinkSlot
    LDA.w !Battle_ActObjThread
    STA.b !Battle_Mul8A
    TAX
    LDA.b !BattleAct_LinkSlot
    STA.w !Battle_ActObjLinkSlot,X
    LDA.b #!Battle_NumSlots
    STA.b !Battle_Mul8B
    JSR Battle_Mul8
    CLC
    LDA.b !Battle_Mul8Product
    ADC.b !BattleAct_LinkSlot
    TAX                             ; j * 11 + s (B = 0 from Battle_Mul8)
    LDA.w !Battle_ActObjThread
    AND.b #!Battle_ActObjLinkThreadMask
    ORA.b !BattleAct_LinkFlag
    STA.w !Battle_ActObjLinks,X
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; The heading opcodes ($C16093–$C1619D and $C16258): set
; !Battle_ActorUnkA5AA (the battlers) or !Battle_ActObjUnkA5B5 (the
; object threads), the heading a curving move with operand $FF starts
; from. On thread 4 opcodes $75-$77 walk !Battle_ActBattlers from
; entry 1 on (entries 1-2 are the two slots of the action block, 3 the
; main target, then the target set, $FF-ended), not the target set the
; other handlers use. Each is reached only through BattleAct_OpcodeTable.
; ==================================================================
; BattleAct_OpCopyHeading ($C16093–$C160E5, 83 bytes)
; ==================================================================
; Opcode $75 <a>: takes the heading of actor a (0-9: the battler in
; entry a of !Battle_ActBattlers, its !Battle_ActorUnkA5AA; 10 on:
; object thread a - 10, its !Battle_ActObjUnkA5B5) and stores it as the
; heading of the thread's battler (threads 0-3 and 5-7), of the list
; above (thread 4) or of the object (threads 8-15). Goes on with the
; next opcode in the same frame; advances 2.
; Callers: BattleAct_OpcodeTable entry $75.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X clobbered; Y = 1 or the last
;        slot; DP $80 = the heading; !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
!BattleAct_Heading = !BattleTmp_80      ; 1 B: the heading stored
BattleAct_OpCopyHeading:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    CMP.b #!Battle_ActRefFirstObj
    BCS .from_object
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.w !Battle_ActorUnkA5AA,X
    BRA .store
.from_object:
    SEC
    SBC.b #!Battle_ActRefFirstObj
    TAX
    LDA.w !Battle_ActObjUnkA5B5,X
.store:
    STA.b !BattleAct_Heading
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .object
    CMP.b #!Battle_ActTargetSetThread
    BEQ .list
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.b !BattleAct_Heading
    STA.w !Battle_ActorUnkA5AA,X
    BRA .next
.list:
    TDC
    TAX
.list_slot:
    LDA.w !Battle_ActBattlers+1,X   ; entries 1 on
    BMI .list_done
    TAY
    LDA.b !BattleAct_Heading
    STA.w !Battle_ActorUnkA5AA,Y
    INX
    BRA .list_slot
.list_done:
    BRA .next
.object:
    LDX.w !Battle_ActObjThread
    LDA.b !BattleAct_Heading
    STA.w !Battle_ActObjUnkA5B5,X
.next:
    INC.w !Battle_ActNextOp
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpHeadingFromCalc ($C160E6–$C16153, 110 bytes)
; ==================================================================
; Opcode $76 <a> <b>: runs BattleAct_RunCalc handler b and then a,
; takes each one's two results as a point's x/y, and stores the angle
; Battle_CalcAngle gives from point a (origin) to point b as the
; heading, for the same actors as opcode $75. Goes on with the next
; opcode in the same frame; advances 3.
; Callers: BattleAct_OpcodeTable entry $76.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X clobbered; Y = 2 or the last
;        slot; !Battle_ActHeadToX/Y, !Battle_ActHeadFromCalc,
;        !Battle_GeoOriginX/Y, !Battle_GeoPointX/Y and Battle_CalcAngle's
;        DP $D7-$E3 written; !Battle_ActNextOp counted up
; Callees: BattleAct_RunCalc, Battle_CalcAngle, BattleAct_AdvanceScript
;   (JMP)
BattleAct_OpHeadingFromCalc:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActHeadFromCalc
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    JSR BattleAct_RunCalc           ; point b
    LDA.w !Battle_ActCalcOutA
    STA.w !Battle_ActHeadToX
    LDA.w !Battle_ActCalcOutB
    STA.w !Battle_ActHeadToY
    LDA.w !Battle_ActHeadFromCalc
    JSR BattleAct_RunCalc           ; point a
    LDA.w !Battle_ActCalcOutA
    STA.b !Battle_GeoOriginX
    LDA.w !Battle_ActCalcOutB
    STA.b !Battle_GeoOriginY
    LDA.w !Battle_ActHeadToX
    STA.b !Battle_GeoPointX
    LDA.w !Battle_ActHeadToY
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .object
    CMP.b #!Battle_ActTargetSetThread
    BEQ .list
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.b !Battle_GeoAngle
    STA.w !Battle_ActorUnkA5AA,X
    BRA .next
.list:
    TDC
    TAX
.list_slot:
    LDA.w !Battle_ActBattlers+1,X   ; entries 1 on
    BMI .list_done
    TAY
    LDA.b !Battle_GeoAngle
    STA.w !Battle_ActorUnkA5AA,Y
    INX
    BRA .list_slot
.list_done:
    BRA .next
.object:
    LDX.w !Battle_ActObjThread
    LDA.b !Battle_GeoAngle
    STA.w !Battle_ActObjUnkA5B5,X
.next:
    INC.w !Battle_ActNextOp
    LDA.b #3
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpAddHeading ($C16154–$C1619D, 74 bytes)
; ==================================================================
; Opcode $77 <d>: adds d (mod 256, so a turn either way) to the heading
; of the same actors as opcode $75. Goes on with the next opcode in
; the same frame; advances 2.
; Callers: BattleAct_OpcodeTable entry $77.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X clobbered; Y = 1 or the last
;        slot; DP $80 = d; !Battle_ActNextOp counted up
; Callees: BattleAct_AdvanceScript (JMP)
!BattleAct_HeadingDelta = !BattleTmp_80 ; 1 B: d
BattleAct_OpAddHeading:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_HeadingDelta
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .object
    CMP.b #!Battle_ActTargetSetThread
    BEQ .list
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    CLC
    LDA.w !Battle_ActorUnkA5AA,X
    ADC.b !BattleAct_HeadingDelta
    STA.w !Battle_ActorUnkA5AA,X
    BRA .next
.list:
    TDC
    TAX
.list_slot:
    LDA.w !Battle_ActBattlers+1,X   ; entries 1 on
    BMI .list_done
    TAY
    CLC
    LDA.w !Battle_ActorUnkA5AA,Y
    ADC.b !BattleAct_HeadingDelta
    STA.w !Battle_ActorUnkA5AA,Y
    INX
    BRA .list_slot
.list_done:
    BRA .next
.object:
    LDX.w !Battle_ActObjThread
    CLC
    LDA.w !Battle_ActObjUnkA5B5,X
    ADC.b !BattleAct_HeadingDelta
    STA.w !Battle_ActObjUnkA5B5,X
.next:
    INC.w !Battle_ActNextOp
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; The sound opcodes ($C1619E–$C1621A): fill the APU command block
; (!Sfx_Command, !Sfx_Param1/2) and run Audio_ProcessEntry. Command
; $19 is the one the menus play sounds with (!Sfx_CmdPlay); $18
; (!Sfx_CmdUnk18) is not established. Each goes on with the next
; opcode in the same frame and is reached only through
; BattleAct_OpcodeTable.
; ==================================================================
; BattleAct_OpSound ($C1619E–$C161C0, 35 bytes)
; ==================================================================
; Opcodes $78/$79 <id>: APU command $18 (opcode $78) or $19 (opcode $79)
; with !Sfx_Param1 = id and !Sfx_Param2 = $80; advances 2.
; Callers: BattleAct_OpcodeTable entries $78 and $79.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y as Audio_ProcessEntry
;        leaves them (not analysed); !Battle_ActNextOp counted up
; Callees: Audio_ProcessEntry, BattleAct_AdvanceScript (JMP)
BattleAct_OpSound:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Sfx_Param1
    SEC
    LDA.w !Battle_ActOpcode
    SBC.b #!Battle_ActOpSound
    CLC
    ADC.b #!Sfx_CmdUnk18
    STA.w !Sfx_Command
    LDA.b #!Sfx_Param2Default
    STA.w !Sfx_Param2
    JSL Audio_ProcessEntry
    INC.w !Battle_ActNextOp
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpSoundCalc ($C161C1–$C161EA, 42 bytes)
; ==================================================================
; Opcodes $7A/$7B <id> <calc>: APU command $18 (opcode $7A) or $19
; (opcode $7B) with !Sfx_Param1 = id and !Sfx_Param2 = the first result
; of BattleAct_RunCalc handler calc (probably an x, as opcodes $7C/$7D
; send a screen x there); advances 3.
; Callers: BattleAct_OpcodeTable entries $7A and $7B.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y as Audio_ProcessEntry
;        leaves them; what the calc handler writes;
;        !Battle_ActNextOp counted up
; Callees: BattleAct_RunCalc, Audio_ProcessEntry,
;   BattleAct_AdvanceScript (JMP)
BattleAct_OpSoundCalc:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Sfx_Param1
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    JSR BattleAct_RunCalc
    LDA.w !Battle_ActCalcOutA
    STA.w !Sfx_Param2
    SEC
    LDA.w !Battle_ActOpcode
    SBC.b #!Battle_ActOpSoundCalc
    CLC
    ADC.b #!Sfx_CmdUnk18
    STA.w !Sfx_Command
    JSL Audio_ProcessEntry
    INC.w !Battle_ActNextOp
    LDA.b #3
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpPcAttackSfxA ($C161EB–$C1621A, 48 bytes, with
; BattleAct_OpPcAttackSfxB and BattleAct_PlayPcAttackSfx)
; ==================================================================
; Opcodes $7C (BattleAct_OpPcAttackSfxA) and $7D
; (BattleAct_OpPcAttackSfxB): APU command $18 with !Sfx_Param1 = the
; sound of the PC attack record (!Battle_ActPcAttackRec) in
; !BattleRom_PcAttackSfxA or B, and !Sfx_Param2 = !Battler_ScreenX of
; entry 0 of !Battle_ActBattlers (the actor of the action); advances 1.
; BattleAct_PlayPcAttackSfx is the shared tail, A = the sound.
; Callers: BattleAct_OpcodeTable entries $7C and $7D;
;   BattleAct_PlayPcAttackSfx is reached from BattleAct_OpPcAttackSfxA
;   (BRA) and by falling through BattleAct_OpPcAttackSfxB.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y as Audio_ProcessEntry
;        leaves them; !Battle_ActNextOp counted up
; Callees: Audio_ProcessEntry, BattleAct_AdvanceScript (JMP)
BattleAct_OpPcAttackSfxA:
    LDA.w !Battle_ActPcAttackRec
    TAX
    LDA.l !BattleRom_PcAttackSfxA,X
    BRA BattleAct_PlayPcAttackSfx

BattleAct_OpPcAttackSfxB:               ; header: see BattleAct_OpPcAttackSfxA
    LDA.w !Battle_ActPcAttackRec
    TAX
    LDA.l !BattleRom_PcAttackSfxB,X
BattleAct_PlayPcAttackSfx:              ; header: see BattleAct_OpPcAttackSfxA
    STA.w !Sfx_Param1
    LDA.b #!Sfx_CmdUnk18
    STA.w !Sfx_Command
    LDA.w !Battle_ActBattlers
    TAX
    LDA.w !Battler_ScreenX,X
    STA.w !Sfx_Param2
    JSL Audio_ProcessEntry
    INC.w !Battle_ActNextOp
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpRunVecCD001B ($C1621B–$C1623B, 33 bytes)
; ==================================================================
; Opcode $80 <len> ...: copies len & $0F bytes of the script, from the
; length byte on, to !Battle_ActOp80Args (DP $53 on), runs
; BattleAct_UnkVecCD001B and advances by that count + 1 (the opcode
; and its bytes). Quirk: a count of 0 copies 256 bytes (the DEC counts
; through 0) and advances 1.
; Callers: BattleAct_OpcodeTable entry $80.
; Entry: M=1, X=0, DP=0 (the copy is DP-relative), DB=$7E, Y = 0,
;        B = 0 (as from BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E as the vector leaves them (the code
;        after the JSL assumes so); A = 0; DP $80, $81 and $53 on
;        written
; Callees: BattleAct_UnkVecCD001B, BattleAct_AdvanceScript (JMP)
!BattleAct_Op80Left = !BattleTmp_80     ; 1 B: bytes left to copy
!BattleAct_Op80Len = !BattleTmp_81      ; 1 B: the count
BattleAct_OpRunVecCD001B:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    AND.b #!Battle_ActOp80LenMask
    STA.b !BattleAct_Op80Left
    STA.b !BattleAct_Op80Len
    TDC
    TAX
.copy:
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !Battle_ActOp80Args,X
    INY
    INX
    DEC.b !BattleAct_Op80Left
    BNE .copy
    JSL BattleAct_UnkVecCD001B
    CLC
    LDA.b !BattleAct_Op80Len
    ADC.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpSetCalcSel ($C1623C–$C16257, 28 bytes)
; ==================================================================
; Opcodes $81-$84 (entries 0-3) and $47/$48 (entries 4 and 5) <n>:
; !Battle_ActCalcSel[entry] = n + 1, so BattleAct_TickCalcs runs
; BattleAct_RunCalc handler n for that entry every frame; advances 2.
; Callers: BattleAct_OpcodeTable entries $47, $48 and $81-$84.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X = the entry; Y = 1
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpSetCalcSel:
    LDA.w !Battle_ActOpcode
    CMP.b #!Battle_ActOpSetCalcSel
    BCS .entry_0_3
    SEC
    SBC.b #!Battle_ActOpSetCalcSel4-4
    BRA .store
.entry_0_3:
    SEC
    SBC.b #!Battle_ActOpSetCalcSel
.store:
    TAX
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    INC A
    STA.w !Battle_ActCalcSel,X
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpSetHeading ($C16258–$C16298, 65 bytes)
; ==================================================================
; Opcode $85 <h>: sets the heading (see the heading opcodes above) of
; the thread's battler (threads 0-3 and 5-7), of every slot of the
; target set (thread 4; the target set here, unlike opcodes $75-$77) or
; of the object (threads 8-15) to h; advances 2. Quirk: two of its
; branches go through a JMP where a branch would reach.
; Callers: BattleAct_OpcodeTable entry $85.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X clobbered; Y = 1 or the last
;        slot; DP $80 = h
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpSetHeading:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_Heading
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .not_object
    JMP .object
.not_object:
    CMP.b #!Battle_ActTargetSetThread
    BNE .one
    JMP .target_set
.one:
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.b !BattleAct_Heading
    STA.w !Battle_ActorUnkA5AA,X
    BRA .advance
.target_set:
    TDC
    TAX
.set_slot:
    LDA.w !Battle_ActTargetSet,X
    BMI .set_done
    TAY
    LDA.b !BattleAct_Heading
    STA.w !Battle_ActorUnkA5AA,Y
    INX
    BRA .set_slot
.set_done:
    BRA .advance
.object:
    LDX.w !Battle_ActObjThread
    LDA.b !BattleAct_Heading
    STA.w !Battle_ActObjUnkA5B5,X
.advance:
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpArcToCalc ($C16299–$C16548, 688 bytes, with
; BattleAct_ArcToCalcDir and BattleAct_ArcToPoint)
; ==================================================================
; The arc opcodes: like the move opcodes $10-$12 (BattleAct_OpMoveTo)
; they move the thread's actor in a straight line to a point and wait
; for it, but with mover kind !Battle_MoveKindArc ($CF:F087,
; unmatched), which also makes a height rise and fall back over the
; move (see !Battle_ActorArcSteps; probably a jump):
;   - $98 / $9C <mode> <n> (BattleAct_OpArcToCalc): the point left by
;     BattleAct_RunCalc handler n; length 3; the height subtracted;
;   - $9A <mode> <n> (BattleAct_OpArcDownToCalc, enters at
;     BattleAct_ArcToCalcDir with DP $8F = 1): the same with the height
;     added;
;   - $99 / $9D, $9B <m> (BattleAct_OpArcToUnkPoint and
;     BattleAct_OpArcDownToUnkPoint, enter at BattleAct_ArcToPoint): the
;     point in !Battle_ActUnkPointX/Y; length 2. Quirk: the byte m
;     (probably meant as the mode) is never read and DP $90 is left as
;     it is, so the mode is whatever DP $90 held.
; For opcodes $9C/$9D the point is first moved to a quarter of the way
; (BattleAct_ArcQuarterPoint) and the step count is multiplied by 4:
; the actor still covers the whole distance, but the arc is sized for
; a quarter of it and starts again each time it lands (so probably
; four hops; inferred from the mover's reload of the start speed).
; BattleAct_ArcToPoint, the shared part, by thread:
;   - threads 0-7 other than 4, the thread's battler: when it is not
;     moving (!Battle_ActorMoving 0) starts the move as
;     BattleAct_StartBattlerMove does (from, to, facing, step, offset,
;     timer, done flag), but with the step count in
;     !Battle_ActorArcSteps, kind !Battle_MoveKindArc, and the arc set
;     up: !Battle_ActorArcSpeed = !Battle_ActorArcSpeed0 =
;     !Battle_ArcSpeedHalf for mode !Battle_ArcModeHalf, else
;     !Battle_ArcSpeedFull; !Battle_ActorArcAccel = that / (major
;     distance / 2); height and falling 0; the mode in
;     !Battle_ActorArcMode and DP $8F in !Battle_ActorArcDown. It keeps
;     the length in the thread's !Battle_ActThreadOpLen and waits
;     (advance 0) until !Battler_MoveDone, then clears
;     !Battle_ActorMoving and advances by the kept length;
;   - thread 4: starts nothing and advances at once by
;     !Battle_ActThreadOpLen of thread 4, which this opcode never set
;     (quirk, kept: a length left by an earlier opcode);
;   - threads 8-15, object j: the same as a battler with the object's
;     entries of the actor arrays (index 11 + j; the word arrays 22 + 2j,
;     the 4-byte ones 44 + 4j), from the object's position
;     (!Battle_ActObjX/Y), keeping the angle in !Battle_ActObjMoveAngle
;     and the facing in !Battle_ActObjFacing; it waits for
;     !Battle_ActObjMoveDone. Unlike the straight move it does not set
;     !Battle_ActObjUnkA5B5 or zero !Battle_ActObjUnkA31C.
; !Battle_ActorMoveSteps is not set: the arc mover ends on its own
; count. The mode operand and the direction are DP $90 and $8F.
; Callers: BattleAct_OpcodeTable entries $98 and $9C; BattleAct_ArcToCalcDir
;   is reached by JMP from BattleAct_OpArcDownToCalc ($C1:6747),
;   BattleAct_ArcToPoint by JMP from BattleAct_ArcToUnkPointDir
;   ($C1:6740; header of BattleAct_OpArcToUnkPoint).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread); BattleAct_ArcToCalcDir: DP $8F set;
;        BattleAct_ArcToPoint: DP $8E, $8F set and the point in
;        !Battle_ActCalcOutA/B
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered;
;        !Battle_ActCalcOutA/B = the point; DP $8E = the length, $8F the
;        direction, $90 the mode; when a move starts, DP $80-$81 and the
;        angle's, BattleAct_CalcMoveStep's, multiply's and divide's DP
;        scratch
; Callees: BattleAct_RunCalc, BattleAct_ArcQuarterPoint,
;          Battle_CalcAngle, BattleAct_CalcMoveStep, Battle_Divide,
;          Battle_Mul8x16, BattleAct_AdvanceScript (JMP)
!BattleAct_ArcSlot = !BattleTmp_80      ; 2 B: the battler slot
!BattleAct_ArcDown = !BattleTmp_8E+1    ; 1 B: 0 = height subtracted, 1 = added
!BattleAct_ArcMode = !BattleTmp_90      ; 1 B: the mode operand
BattleAct_OpArcToCalc:
    STZ.b !BattleAct_ArcDown
BattleAct_ArcToCalcDir:                 ; header: see BattleAct_OpArcToCalc
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_ArcMode
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    JSR BattleAct_RunCalc
    LDA.b #3
    STA.b !BattleAct_MoveLen
BattleAct_ArcToPoint:                   ; header: see BattleAct_OpArcToCalc
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    JMP .object
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BNE .one_battler
    JMP .target_set
.one_battler:
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.w !Battle_ActorMoving,X
    BEQ .battler_start
    JMP .battler_moving
.battler_start:
    STX.b !BattleAct_ArcSlot
    LDA.w !Battler_ScreenX,X
    STA.b !Battle_GeoOriginX
    STA.w !Battle_ActorFromX,X
    LDA.w !Battler_ScreenY,X
    STA.b !Battle_GeoOriginY
    STA.w !Battle_ActorFromY,X
    LDA.w !Battle_ActCalcOutA
    STA.b !Battle_GeoPointX
    LDA.w !Battle_ActCalcOutB
    STA.b !Battle_GeoPointY
    LDA.w !Battle_ActOpcode
    CMP.b #!Battle_ActOpArcQuarter
    BEQ .battler_quarter
    CMP.b #!Battle_ActOpArcQuarterUnkPoint
    BNE .battler_angle
.battler_quarter:
    JSR BattleAct_ArcQuarterPoint
.battler_angle:
    JSR Battle_CalcAngle
    JSR BattleAct_CalcMoveStep
    LDY.b !BattleAct_ArcSlot
    LDA.b !BattleAct_MoveYMajor
    BNE .battler_y_major
    LDA.b !Battle_GeoAbsDeltaX
    STA.b !Battle_DivDividend
    STZ.b !Battle_DivDividend+1
    BRA .battler_steps
.battler_y_major:
    LDA.b !Battle_GeoAbsDeltaY
    STA.b !Battle_DivDividend
    STZ.b !Battle_DivDividend+1
.battler_steps:
    LDA.w !Battle_ActorMoveSpeed,Y
    STA.b !Battle_DivDivisor
    JSR Battle_Divide
    LDA.b !Battle_DivQuotient
    STA.w !Battle_ActorArcSteps,Y
    LDA.w !Battle_ActOpcode
    CMP.b #!Battle_ActOpArcQuarter
    BEQ .battler_times4
    CMP.b #!Battle_ActOpArcQuarterUnkPoint
    BNE .battler_scale
.battler_times4:
    LDA.w !Battle_ActorArcSteps,Y
    ASL A
    ASL A
    STA.w !Battle_ActorArcSteps,Y
.battler_scale:
    LDA.b !BattleAct_ArcDown
    STA.w !Battle_ActorArcDown,Y
    LDA.w !Battle_ActMoveUnitX
    STA.b !Battle_MulFactor16
    LDA.w !Battle_ActMoveUnitX+1
    STA.b !Battle_MulFactor16+1
    LDA.w !Battle_ActorMoveSpeed,Y
    STA.b !Battle_MulFactor8
    JSR Battle_Mul8x16
    LDX.b !Battle_MulProduct
    STX.w !Battle_ActMoveUnitX
    LDA.w !Battle_ActMoveUnitY
    STA.b !Battle_MulFactor16
    LDA.w !Battle_ActMoveUnitY+1
    STA.b !Battle_MulFactor16+1
    LDA.w !Battle_ActorMoveSpeed,Y
    STA.b !Battle_MulFactor8
    JSR Battle_Mul8x16
    LDX.b !Battle_MulProduct
    STX.w !Battle_ActMoveUnitY
    LDA.b !BattleAct_ArcSlot
    ASL A
    TAX
    LDA.b !BattleAct_ArcMode
    STA.w !Battle_ActorArcMode,X
    STZ.w !Battle_ActorArcMode+1,X
    CMP.b #!Battle_ArcModeHalf
    BNE .battler_full
    LDX.w #!Battle_ArcSpeedHalf
    BRA .battler_accel
.battler_full:
    LDX.w #!Battle_ArcSpeedFull
.battler_accel:
    STX.b !Battle_DivDividend
    LDA.b !BattleAct_MoveHalfMajor
    STA.b !Battle_DivDivisor
    JSR Battle_Divide
    LDY.b !BattleAct_ArcSlot
    LDA.b !Battle_GeoAngle
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battler_Facing,Y
    LDA.w !Battle_ActCalcOutA
    STA.w !Battle_ActorToX,Y
    LDA.w !Battle_ActCalcOutB
    STA.w !Battle_ActorToY,Y
    LDA.b #!Battle_MoveKindArc          ; also the timer's 1
    STA.w !Battle_ActorMoveTimer,Y
    STA.w !Battle_ActorMoveKind,Y
    TDC
    STA.w !Battler_MoveDone,Y
    PHY
    TYA
    ASL A
    TAY                             ; slot * 2
    ASL A
    TAX                             ; slot * 4
    REP #$20
    LDA.w !Battle_ActMoveUnitX
    STA.w !Battle_ActorStepX,Y
    LDA.w !Battle_ActMoveUnitY
    STA.w !Battle_ActorStepY,Y
    LDA.b !Battle_DivQuotient
    STA.w !Battle_ActorArcAccel,Y
    LDA.b !Battle_DivDividend           ; the start speed
    STA.w !Battle_ActorArcSpeed,X
    STA.w !Battle_ActorArcSpeed0,Y
    TDC
    STZ.w !Battle_ActorArcSpeed+2,X
    STA.w !Battle_ActorOfsX,Y
    STA.w !Battle_ActorOfsY,Y
    STZ.w !Battle_ActorArcHeight,X
    STZ.w !Battle_ActorArcHeight+2,X
    STA.w !Battle_ActorArcFalling,Y
    SEP #$20
    PLY
    LDX.w !Battle_ActThread
    LDA.b !BattleAct_MoveLen
    STA.w !Battle_ActThreadOpLen,X
    LDA.b #1
    STA.w !Battle_ActorMoving,Y
    JMP .wait
.battler_moving:
    LDA.w !Battler_MoveDone,X
    BEQ .battler_wait
    STZ.w !Battle_ActorMoving,X
    JMP .done
.battler_wait:
    JMP .wait
.target_set:
    JMP .done                       ; quirk: thread 4's length was not kept here
.object:
    LDX.w !Battle_ActObjThread
    LDA.w !Battle_ActorMoving+!Battle_NumSlots,X
    BEQ .object_start
    JMP .object_moving
.object_start:
    TXA
    TXY
    ASL A
    TAX
    LDA.w !Battle_ActObjX,X
    STA.b !Battle_GeoOriginX
    STA.w !Battle_ActorFromX+!Battle_NumSlots,Y
    LDA.w !Battle_ActObjY,X
    STA.b !Battle_GeoOriginY
    STA.w !Battle_ActorFromY+!Battle_NumSlots,Y
    LDA.w !Battle_ActCalcOutA
    STA.b !Battle_GeoPointX
    LDA.w !Battle_ActCalcOutB
    STA.b !Battle_GeoPointY
    LDA.w !Battle_ActOpcode
    CMP.b #!Battle_ActOpArcQuarter
    BEQ .object_quarter
    CMP.b #!Battle_ActOpArcQuarterUnkPoint
    BNE .object_angle
.object_quarter:
    JSR BattleAct_ArcQuarterPoint
.object_angle:
    JSR Battle_CalcAngle
    JSR BattleAct_CalcMoveStep
    LDY.w !Battle_ActObjThread
    LDA.b !BattleAct_MoveYMajor
    BNE .object_y_major
    LDA.b !Battle_GeoAbsDeltaX
    STA.b !Battle_DivDividend
    STZ.b !Battle_DivDividend+1
    BRA .object_steps
.object_y_major:
    LDA.b !Battle_GeoAbsDeltaY
    STA.b !Battle_DivDividend
    STZ.b !Battle_DivDividend+1
.object_steps:
    LDA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,Y
    STA.b !Battle_DivDivisor
    JSR Battle_Divide
    LDA.b !Battle_DivQuotient
    STA.w !Battle_ActorArcSteps+!Battle_NumSlots,Y
    LDA.w !Battle_ActOpcode
    CMP.b #!Battle_ActOpArcQuarter
    BEQ .object_times4
    CMP.b #!Battle_ActOpArcQuarterUnkPoint
    BNE .object_scale
.object_times4:
    LDA.w !Battle_ActorArcSteps+!Battle_NumSlots,Y
    ASL A
    ASL A
    STA.w !Battle_ActorArcSteps+!Battle_NumSlots,Y
.object_scale:
    LDA.b !BattleAct_ArcDown
    STA.w !Battle_ActorArcDown+!Battle_NumSlots,Y
    LDA.w !Battle_ActMoveUnitX
    STA.b !Battle_MulFactor16
    LDA.w !Battle_ActMoveUnitX+1
    STA.b !Battle_MulFactor16+1
    LDA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,Y
    STA.b !Battle_MulFactor8
    JSR Battle_Mul8x16
    LDX.b !Battle_MulProduct
    STX.w !Battle_ActMoveUnitX
    LDA.w !Battle_ActMoveUnitY
    STA.b !Battle_MulFactor16
    LDA.w !Battle_ActMoveUnitY+1
    STA.b !Battle_MulFactor16+1
    LDA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,Y
    STA.b !Battle_MulFactor8
    JSR Battle_Mul8x16
    LDX.b !Battle_MulProduct
    STX.w !Battle_ActMoveUnitY
    LDA.w !Battle_ActObjThread
    ASL A
    TAX
    LDA.b !BattleAct_ArcMode
    STA.w !Battle_ActorArcMode+(2*!Battle_NumSlots),X
    STZ.w !Battle_ActorArcMode+(2*!Battle_NumSlots)+1,X
    CMP.b #!Battle_ArcModeHalf
    BNE .object_full
    LDX.w #!Battle_ArcSpeedHalf
    BRA .object_accel
.object_full:
    LDX.w #!Battle_ArcSpeedFull
.object_accel:
    STX.b !Battle_DivDividend
    LDA.b !BattleAct_MoveHalfMajor
    STA.b !Battle_DivDivisor
    JSR Battle_Divide
    LDY.w !Battle_ActObjThread
    LDA.b !Battle_GeoAngle
    STA.w !Battle_ActObjMoveAngle,Y
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battle_ActObjFacing,Y
    LDA.w !Battle_ActCalcOutA
    STA.w !Battle_ActorToX+!Battle_NumSlots,Y
    LDA.w !Battle_ActCalcOutB
    STA.w !Battle_ActorToY+!Battle_NumSlots,Y
    LDA.b #!Battle_MoveKindArc          ; also the timer's 1
    STA.w !Battle_ActorMoveTimer+!Battle_NumSlots,Y
    STA.w !Battle_ActorMoveKind+!Battle_NumSlots,Y
    TDC
    STA.w !Battle_ActObjMoveDone,Y
    PHY
    TYA
    ASL A
    TAY                             ; j * 2
    ASL A
    TAX                             ; j * 4
    REP #$20
    LDA.w !Battle_ActMoveUnitX
    STA.w !Battle_ActorStepX+(2*!Battle_NumSlots),Y
    LDA.w !Battle_ActMoveUnitY
    STA.w !Battle_ActorStepY+(2*!Battle_NumSlots),Y
    LDA.b !Battle_DivQuotient
    STA.w !Battle_ActorArcAccel+(2*!Battle_NumSlots),Y
    LDA.b !Battle_DivDividend           ; the start speed
    STA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),X
    STA.w !Battle_ActorArcSpeed0+(2*!Battle_NumSlots),Y
    TDC
    STZ.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots)+2,X
    STA.w !Battle_ActorOfsX+(2*!Battle_NumSlots),Y
    STA.w !Battle_ActorOfsY+(2*!Battle_NumSlots),Y
    STZ.w !Battle_ActorArcHeight+(4*!Battle_NumSlots),X
    STZ.w !Battle_ActorArcHeight+(4*!Battle_NumSlots)+2,X
    STA.w !Battle_ActorArcFalling+(2*!Battle_NumSlots),Y
    SEP #$20
    PLY
    LDX.w !Battle_ActThread
    LDA.b !BattleAct_MoveLen
    STA.w !Battle_ActThreadOpLen,X
    LDA.b #1
    STA.w !Battle_ActorMoving+!Battle_NumSlots,Y
    BRA .wait
.object_moving:
    LDA.w !Battle_ActObjMoveDone,X
    BEQ .wait
    STZ.w !Battle_ActorMoving+!Battle_NumSlots,X
    BRA .done
.wait:
    LDA.b #0
    JMP BattleAct_AdvanceScript     ; by 0: same opcode next frame
.done:
    LDX.w !Battle_ActThread
    LDA.w !Battle_ActThreadOpLen,X
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_ArcQuarterPoint ($C16549–$C165B9, 113 bytes)
; ==================================================================
; Opcodes $9C/$9D: moves !Battle_GeoPointX/Y to a quarter of the way
; from !Battle_GeoOriginX/Y: Origin + (|Point - Origin| / 4, rounded
; down) with the delta's sign, per axis (8-bit, no carry out).
; Its first part is the delta code of BattleAct_CalcMoveStep, which
; the caller runs next and which recomputes all of it from the new
; point.
; Callers (JSR): BattleAct_OpArcToCalc ($C1:62EF, $C1:6430; header of
;   BattleAct_OpArcToCalc).
; Entry: M=1, X=0, DP=0, DB any (DP operands only); the two Geo points
;        set
; Exit:  M=1, X=0, DP=0; A clobbered; X, Y unchanged; DP $82/$83 = 1
;        when the x / y delta is negative; !Battle_GeoDeltaX/Y = Point -
;        Origin (16-bit); !Battle_GeoAbsDeltaX/Y = the quarter
;        distances; !Battle_GeoPointX/Y moved
; No calls.
BattleAct_ArcQuarterPoint:
    STZ.b !BattleAct_MoveXNeg
    STZ.b !BattleAct_MoveYNeg
    SEC
    LDA.b !Battle_GeoPointX
    SBC.b !Battle_GeoOriginX
    STA.b !Battle_GeoDeltaX
    LDA.b #0
    SBC.b #0                        ; high byte: $FF when it borrowed
    STA.b !Battle_GeoDeltaX+1
    BCS .y
    INC.b !BattleAct_MoveXNeg
.y:
    SEC
    LDA.b !Battle_GeoPointY
    SBC.b !Battle_GeoOriginY
    STA.b !Battle_GeoDeltaY
    LDA.b #0
    SBC.b #0
    STA.b !Battle_GeoDeltaY+1
    BCS .abs
    INC.b !BattleAct_MoveYNeg
.abs:
    LDA.b !Battle_GeoDeltaX
    EOR.b !Battle_GeoDeltaX+1
    SEC
    SBC.b !Battle_GeoDeltaX+1
    STA.b !Battle_GeoAbsDeltaX
    STZ.b !Battle_GeoAbsDeltaX+1
    LDA.b !Battle_GeoDeltaY
    EOR.b !Battle_GeoDeltaY+1
    SEC
    SBC.b !Battle_GeoDeltaY+1
    STA.b !Battle_GeoAbsDeltaY
    STZ.b !Battle_GeoAbsDeltaY+1
    LDA.b !Battle_GeoAbsDeltaX
    LSR A
    LSR A
    STA.b !Battle_GeoAbsDeltaX
    LDA.b !Battle_GeoAbsDeltaY
    LSR A
    LSR A
    STA.b !Battle_GeoAbsDeltaY
    LDA.b !BattleAct_MoveXNeg
    BNE .x_neg
    CLC
    LDA.b !Battle_GeoOriginX
    ADC.b !Battle_GeoAbsDeltaX
    STA.b !Battle_GeoPointX
    BRA .y_point
.x_neg:
    SEC
    LDA.b !Battle_GeoOriginX
    SBC.b !Battle_GeoAbsDeltaX
    STA.b !Battle_GeoPointX
.y_point:
    LDA.b !BattleAct_MoveYNeg
    BNE .y_neg
    CLC
    LDA.b !Battle_GeoOriginY
    ADC.b !Battle_GeoAbsDeltaY
    STA.b !Battle_GeoPointY
    BRA .exit
.y_neg:
    SEC
    LDA.b !Battle_GeoOriginY
    SBC.b !Battle_GeoAbsDeltaY
    STA.b !Battle_GeoPointY
.exit:
    RTS

; ==================================================================
; BattleAct_CalcMoveStep ($C165BA–$C16670, 183 bytes)
; ==================================================================
; Unit step of a straight move from !Battle_GeoOriginX/Y to
; !Battle_GeoPointX/Y, as signed 8.8 pixels: the axis with the larger
; distance (x on a tie) moves 1.0 ($0100) per step, the other
; (smaller * 256) / larger (Battle_Divide), each with the sign of its
; delta, into !Battle_ActMoveUnitX/Y. Also sets !Battle_GeoDeltaX/Y
; (Point - Origin here, the opposite of Battle_CalcAngle's) and
; !Battle_GeoAbsDeltaX/Y, !Battle_MoveMajorDist (the larger distance),
; DP $84 (half of it) and the flags in DP $82/$83 (x / y delta
; negative) and $8C (y is the major axis), which the callers test.
; Quirk: for two equal points the divide is by 0 (what Battle_Divide
; returns then is the hardware's); the move then has 0 steps anyway.
; Callers (6 JSR sites): BattleAct_MoveToPoint ($C1:5067; header of
;   BattleAct_OpMoveTo), BattleAct_StartBattlerMove ($C1:5154) and
;   $C1:62F5, $C1:6436, $C1:7261, $C1:7468 (unmatched).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E (the step is stored
;        .w); the four Geo points set
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0, B = 0; X = $0100; Y unchanged;
;        DP $82-$85, $8C-$8D, $D7-$DA, $DE-$E1 and Battle_Divide's
;        $B1-$B8 and $79-$7B written
; Callees: Battle_ShiftLeft8, Battle_Divide
; (its DP outputs are named in the header of BattleAct_OpMoveTo)
org $C165BA
BattleAct_CalcMoveStep:
    TDC
    TAX
    STX.b !BattleAct_MoveXNeg       ; and YNeg
    STX.b !BattleAct_MoveHalfMajor
    STX.b !BattleAct_MoveYMajor
    SEC
    LDA.b !Battle_GeoPointX
    SBC.b !Battle_GeoOriginX
    STA.b !Battle_GeoDeltaX
    LDA.b #0
    SBC.b #0                        ; borrow -> high byte $FF, carry clear
    STA.b !Battle_GeoDeltaX+1
    BCS .dy
    INC.b !BattleAct_MoveXNeg
.dy:
    SEC
    LDA.b !Battle_GeoPointY
    SBC.b !Battle_GeoOriginY
    STA.b !Battle_GeoDeltaY
    LDA.b #0
    SBC.b #0
    STA.b !Battle_GeoDeltaY+1
    BCS .abs
    INC.b !BattleAct_MoveYNeg
.abs:
    LDA.b !Battle_GeoDeltaX
    EOR.b !Battle_GeoDeltaX+1
    SEC
    SBC.b !Battle_GeoDeltaX+1
    STA.b !Battle_GeoAbsDeltaX
    STZ.b !Battle_GeoAbsDeltaX+1
    LDA.b !Battle_GeoDeltaY
    EOR.b !Battle_GeoDeltaY+1
    SEC
    SBC.b !Battle_GeoDeltaY+1
    STA.b !Battle_GeoAbsDeltaY
    STZ.b !Battle_GeoAbsDeltaY+1
    LDA.b !Battle_GeoAbsDeltaX
    CMP.b !Battle_GeoAbsDeltaY
    BCC .y_major
    STA.b !Battle_DivDivisor
    STA.w !Battle_MoveMajorDist
    LSR A
    STA.b !BattleAct_MoveHalfMajor
    LDA.b !Battle_GeoAbsDeltaY
    REP #$20
    JSR Battle_ShiftLeft8
    STA.b !Battle_DivDividend
    TDC
    SEP #$20
    JSR Battle_Divide
    LDX.b !Battle_DivQuotient
    STX.w !Battle_ActMoveUnitY
    LDX.w #!Battle_MoveUnitStep
    STX.w !Battle_ActMoveUnitX
    BRA .signs
.y_major:
    INC.b !BattleAct_MoveYMajor
    LDA.b !Battle_GeoAbsDeltaY
    STA.b !Battle_DivDivisor
    STA.w !Battle_MoveMajorDist
    LSR A
    STA.b !BattleAct_MoveHalfMajor
    LDA.b !Battle_GeoAbsDeltaX
    REP #$20
    JSR Battle_ShiftLeft8
    STA.b !Battle_DivDividend
    TDC
    SEP #$20
    JSR Battle_Divide
    LDX.b !Battle_DivQuotient
    STX.w !Battle_ActMoveUnitX
    LDX.w #!Battle_MoveUnitStep
    STX.w !Battle_ActMoveUnitY
.signs:
    LDA.b !BattleAct_MoveXNeg
    BEQ .y_sign
    REP #$20
    LDA.w !Battle_ActMoveUnitX
    EOR.w #!Battle_Invert16
    INC A
    STA.w !Battle_ActMoveUnitX
    TDC
    SEP #$20
.y_sign:
    LDA.b !BattleAct_MoveYNeg
    BEQ .exit
    REP #$20
    LDA.w !Battle_ActMoveUnitY
    EOR.w #!Battle_Invert16
    INC A
    STA.w !Battle_ActMoveUnitY
    TDC
    SEP #$20
.exit:
    RTS

; ==================================================================
; BattleAct_CalcMidpointSteps ($C16671–$C1672D, 189 bytes)
; ==================================================================
; From !Battle_GeoOriginX/Y and !Battle_GeoPointX/Y: sets
; !Battle_ActMoveUnitX/Y to the delta * 4 with the delta's sign (as
; signed 8.8, 1/64 of the delta: probably a move of 64 steps),
; !Battle_ActUnkMidX/Y to the point halfway (Origin +- |delta| / 2,
; rounded towards Origin), with y then raised by !Battle_ActMidRise
; (clamped at 0), and !Battle_ActUnkAAFC/AAFD to
; !Battle_ActUnkAAFCStart and 0. What the callers do with them is not
; traced (perhaps a thrown arc through the raised midpoint; a guess
; from the numbers).
; Callers (JSR): $C1:7095 and $C1:715C (unmatched; opcode $D2's
;   handler, BattleAct_OpcodeTable entry $D2 at $C1:705A).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E; the two Geo points set
; Exit:  M=1, X=0, DP=0, DB=$7E; A clobbered (B = 0); X = 0; Y
;        unchanged; DP $82/$83 = half |dx| / |dy| when that delta is
;        negative, else 0; DP $84-$85 = 0;
;        !Battle_GeoDeltaX/Y and !Battle_GeoAbsDeltaX/Y set
; No calls.
!BattleAct_MidXNeg = !BattleTmp_82      ; 1 B: 1 = x delta negative (then reused for half |dx|)
!BattleAct_MidYNeg = !BattleTmp_83      ; 1 B: the same for y
BattleAct_CalcMidpointSteps:
    TDC
    TAX
    STX.b !BattleAct_MidXNeg        ; and MidYNeg
    STX.b !BattleTmp_84             ; zeroed, not used here
    SEC
    LDA.b !Battle_GeoPointX
    SBC.b !Battle_GeoOriginX
    STA.b !Battle_GeoDeltaX
    LDA.b #0
    SBC.b #0                        ; high byte: $FF when it borrowed
    STA.b !Battle_GeoDeltaX+1
    BCS .y
    INC.b !BattleAct_MidXNeg
.y:
    SEC
    LDA.b !Battle_GeoPointY
    SBC.b !Battle_GeoOriginY
    STA.b !Battle_GeoDeltaY
    LDA.b #0
    SBC.b #0
    STA.b !Battle_GeoDeltaY+1
    BCS .abs
    INC.b !BattleAct_MidYNeg
.abs:
    LDA.b !Battle_GeoDeltaX
    EOR.b !Battle_GeoDeltaX+1
    SEC
    SBC.b !Battle_GeoDeltaX+1
    STA.b !Battle_GeoAbsDeltaX
    STZ.b !Battle_GeoAbsDeltaX+1
    LDA.b !Battle_GeoDeltaY
    EOR.b !Battle_GeoDeltaY+1
    SEC
    SBC.b !Battle_GeoDeltaY+1
    STA.b !Battle_GeoAbsDeltaY
    STZ.b !Battle_GeoAbsDeltaY+1
    REP #$20
    LDA.b !Battle_GeoAbsDeltaX
    ASL A
    ASL A
    STA.w !Battle_ActMoveUnitX
    LDA.b !Battle_GeoAbsDeltaY
    ASL A
    ASL A
    STA.w !Battle_ActMoveUnitY
    TDC
    SEP #$20
    LDA.b !BattleAct_MidXNeg
    BEQ .x_pos
    REP #$20
    LDA.w !Battle_ActMoveUnitX
    EOR.w #!Battle_Invert16
    INC A
    STA.w !Battle_ActMoveUnitX
    TDC
    SEP #$20
    LDA.b !Battle_GeoAbsDeltaX
    LSR A
    STA.b !BattleAct_MidXNeg
    SEC
    LDA.b !Battle_GeoOriginX
    SBC.b !BattleAct_MidXNeg
    STA.w !Battle_ActUnkMidX
    BRA .mid_y
.x_pos:
    LDA.b !Battle_GeoAbsDeltaX
    LSR A
    CLC
    ADC.b !Battle_GeoOriginX
    STA.w !Battle_ActUnkMidX
.mid_y:
    LDA.b !BattleAct_MidYNeg
    BEQ .y_pos
    REP #$20
    LDA.w !Battle_ActMoveUnitY
    EOR.w #!Battle_Invert16
    INC A
    STA.w !Battle_ActMoveUnitY
    TDC
    SEP #$20
    LDA.b !Battle_GeoAbsDeltaY
    LSR A
    STA.b !BattleAct_MidYNeg
    SEC
    LDA.b !Battle_GeoOriginY
    SBC.b !BattleAct_MidYNeg
    STA.w !Battle_ActUnkMidY
    BRA .rise
.y_pos:
    LDA.b !Battle_GeoAbsDeltaY
    LSR A
    CLC
    ADC.b !Battle_GeoOriginY
    STA.w !Battle_ActUnkMidY
.rise:
    SEC
    LDA.w !Battle_ActUnkMidY
    SBC.b #!Battle_ActMidRise
    BCS .store_y
    LDA.b #0
.store_y:
    STA.w !Battle_ActUnkMidY
    LDA.b #!Battle_ActUnkAAFCStart
    STA.w !Battle_ActUnkAAFC
    STZ.w !Battle_ActUnkAAFD
    RTS

; ==================================================================
; BattleAct_OpArcToUnkPoint ($C1672E–$C16742, 21 bytes, with
; BattleAct_ArcToUnkPointDir)
; ==================================================================
; Opcodes $99/$9D <m>: the arc move (BattleAct_OpArcToCalc) to the
; point in !Battle_ActUnkPointX/Y, height subtracted; length 2. Quirk:
; m is never read and DP $90 (the mode) is left as it is (see
; BattleAct_OpArcToCalc).
; BattleAct_ArcToUnkPointDir is the entry with DP $8F already set
; (opcode $9B, BattleAct_OpArcDownToUnkPoint).
; Callers: BattleAct_OpcodeTable entries $99 and $9D;
;   BattleAct_ArcToUnkPointDir by JMP from BattleAct_OpArcDownToUnkPoint
;   ($C1:674E).
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  as BattleAct_OpArcToCalc's (DP $8E = 2, $8F = 0 or as set)
; Callees: BattleAct_ArcToPoint (JMP)
BattleAct_OpArcToUnkPoint:
    STZ.b !BattleAct_ArcDown
BattleAct_ArcToUnkPointDir:             ; header: see BattleAct_OpArcToUnkPoint
    LDA.w !Battle_ActUnkPointX
    STA.w !Battle_ActCalcOutA
    LDA.w !Battle_ActUnkPointY
    STA.w !Battle_ActCalcOutB
    LDA.b #2                        ; skips a byte it does not read
    STA.b !BattleAct_MoveLen
    JMP BattleAct_ArcToPoint

; ==================================================================
; BattleAct_OpArcDownToCalc ($C16743–$C16749, 7 bytes)
; ==================================================================
; Opcode $9A <mode> <n>: opcode $98 (BattleAct_OpArcToCalc) with the
; height added instead of subtracted (DP $8F = 1).
; Callers: BattleAct_OpcodeTable entry $9A.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  as BattleAct_OpArcToCalc's (DP $8F = 1)
; Callees: BattleAct_ArcToCalcDir (JMP)
BattleAct_OpArcDownToCalc:
    LDA.b #1
    STA.b !BattleAct_ArcDown
    JMP BattleAct_ArcToCalcDir

; ==================================================================
; BattleAct_OpArcDownToUnkPoint ($C1674A–$C16750, 7 bytes)
; ==================================================================
; Opcode $9B <m>: opcode $99 (BattleAct_OpArcToUnkPoint) with the height
; added instead of subtracted (DP $8F = 1).
; Callers: BattleAct_OpcodeTable entry $9B.
; Entry: M=1, X=0, DP=0, DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  as BattleAct_OpArcToCalc's (DP $8E = 2, $8F = 1)
; Callees: BattleAct_ArcToUnkPointDir (JMP)
BattleAct_OpArcDownToUnkPoint:
    LDA.b #1
    STA.b !BattleAct_ArcDown
    JMP BattleAct_ArcToUnkPointDir

; ==================================================================
; BattleAct_OpMoveAlongHeading ($C16751–$C1691A, 458 bytes)
; ==================================================================
; Opcode $A2: moves the thread's actor along its heading
; (!Battle_ActorUnkA5AA; for the objects !Battle_ActObjUnkA5B5) with
; mover kind !Battle_MoveKindHeading ($CF:F194, unmatched; up to $FF
; steps, see !Battle_ActorHeadSteps) until the cell
; !Battle_HeadProbeDist pixels ahead along the angle (sine lookups:
; sin to y, cos to x) has either blocking bit (!Battle_CellBlocksAny)
; in !Battle_CellMap, or the mover is done; then advances 1. Starting
; a move stores the angle in !Battle_ActorMoveAngle, the facing from
; !BattleRom_FacingByAngle, the position in !Battle_ActorFromX/Y,
; !Battle_ActorMoveTimer = 1, the kind, and zeroes
; !Battle_ActorUnkA311 (the mover's distance) and the done flag. By
; thread:
;   - threads 0-7 other than 4, the thread's battler: starts the move
;     when it is not moving, then on the same and every later frame
;     tests done / the cell ahead: stopped, it clears
;     !Battle_ActorMoving and advances; else it sets it to 1 and waits;
;   - thread 4: starts every slot of !Battle_ActTargetSet up to the
;     first that is already moving, then tests from that slot on,
;     counting in DP $84 the slots still free to go; it waits while
;     any is. Quirk, kept: on the frame that starts the whole set the
;     test loop starts at the set's end, so it advances at once
;     without testing; the start loop never sets !Battle_ActorMoving
;     (only the test loop does), and the mover at $CF:EFC4 skips actors
;     with it 0, so none of the set moves: the opcode only sets angle,
;     facing and move state;
;   - threads 8-15, object j: as a battler with the object's entries
;     (index 11 + j), its position !Battle_ActObjX/Y, and
;     !Battle_ActObjMoveDone; it also zeroes !Battle_ActObjUnkA31C.
; Clearing !Battle_ActorMoving stops the mover (it steps only moving
; actors) wherever the actor is.
; Callers: BattleAct_OpcodeTable entry $A2.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered; DP $82/$83 and
;        Battle_SinLookup's DP written; thread 4 also DP $80-$81 and $84
; Callees: Battle_SinLookup, Battle_ShiftRight4,
;          BattleAct_AdvanceScript (JMP)
!BattleAct_HeadSetIdx = !BattleTmp_80   ; 2 B: thread 4: position in !Battle_ActTargetSet
!BattleAct_HeadCellRow = !BattleTmp_82  ; 1 B: sin part, then the probe's row * 16
!BattleAct_HeadCos = !BattleTmp_83      ; 1 B: cos part of the probe
!BattleAct_HeadBusy = !BattleTmp_84     ; 1 B: thread 4: slots still moving
BattleAct_OpMoveAlongHeading:
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    JMP .object
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BNE .one_battler
    JMP .target_set
.one_battler:
    TAX
    LDA.w !Battle_ActBattlers,X
    TAY
    LDA.w !Battle_ActorMoving,Y
    BNE .battler_test
    LDA.w !Battle_ActorUnkA5AA,Y
    STA.w !Battle_ActorMoveAngle,Y
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battler_Facing,Y
    LDA.w !Battler_ScreenX,Y
    STA.w !Battle_ActorFromX,Y
    LDA.w !Battler_ScreenY,Y
    STA.w !Battle_ActorFromY,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer,Y
    INC A                           ; !Battle_MoveKindHeading
    STA.w !Battle_ActorMoveKind,Y
    TDC
    STA.w !Battle_ActorUnkA311,Y
    STA.w !Battler_MoveDone,Y
    DEC A                           ; $FF steps
    STA.w !Battle_ActorHeadSteps,Y
.battler_test:
    LDA.w !Battler_MoveDone,Y
    BNE .battler_stop
    LDA.b #!Battle_HeadProbeDist
    STA.b !Battle_SinScale
    LDA.w !Battle_ActorMoveAngle,Y
    JSR Battle_SinLookup
    STA.b !BattleAct_HeadCellRow
    CLC
    LDA.w !Battle_ActorMoveAngle,Y
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup
    STA.b !BattleAct_HeadCos
    CLC
    LDA.w !Battler_ScreenY,Y
    ADC.b !BattleAct_HeadCellRow
    AND.b #!Battle_PathRowMask
    STA.b !BattleAct_HeadCellRow
    CLC
    LDA.w !Battler_ScreenX,Y
    ADC.b !BattleAct_HeadCos
    JSR Battle_ShiftRight4
    ORA.b !BattleAct_HeadCellRow
    TAX
    LDA.w !Battle_CellMap,X
    AND.b #!Battle_CellBlocksAny
    BEQ .battler_go
.battler_stop:
    TDC
    STA.w !Battle_ActorMoving,Y
    JMP .done
.battler_go:
    LDA.b #1
    STA.w !Battle_ActorMoving,Y
    JMP .wait
.target_set:
    TDC
    TAX
    STX.b !BattleAct_HeadSetIdx
.start_slot:
    LDX.b !BattleAct_HeadSetIdx
    LDA.w !Battle_ActTargetSet,X
    BMI .test_set
    TAY
    LDA.w !Battle_ActorMoving,Y
    BNE .test_set
    LDA.w !Battle_ActorUnkA5AA,Y
    STA.w !Battle_ActorMoveAngle,Y
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battler_Facing,Y
    LDA.w !Battler_ScreenX,Y
    STA.w !Battle_ActorFromX,Y
    LDA.w !Battler_ScreenY,Y
    STA.w !Battle_ActorFromY,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer,Y
    INC A                           ; !Battle_MoveKindHeading
    STA.w !Battle_ActorMoveKind,Y
    TDC
    STA.w !Battle_ActorUnkA311,Y
    STA.w !Battler_MoveDone,Y
    DEC A                           ; $FF steps
    STA.w !Battle_ActorHeadSteps,Y
    INC.b !BattleAct_HeadSetIdx
    BRA .start_slot
.test_set:
    STZ.b !BattleAct_HeadBusy
.test_slot:
    LDX.b !BattleAct_HeadSetIdx
    LDA.w !Battle_ActTargetSet,X
    BMI .set_done
    TAY
    LDA.w !Battler_MoveDone,Y
    BNE .slot_stop
    LDA.b #!Battle_HeadProbeDist
    STA.b !Battle_SinScale
    LDA.w !Battle_ActorMoveAngle,Y
    JSR Battle_SinLookup
    STA.b !BattleAct_HeadCellRow
    CLC
    LDA.w !Battle_ActorMoveAngle,Y
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup
    STA.b !BattleAct_HeadCos
    CLC
    LDA.w !Battler_ScreenY,Y
    ADC.b !BattleAct_HeadCellRow
    AND.b #!Battle_PathRowMask
    STA.b !BattleAct_HeadCellRow
    CLC
    LDA.w !Battler_ScreenX,Y
    ADC.b !BattleAct_HeadCos
    JSR Battle_ShiftRight4
    ORA.b !BattleAct_HeadCellRow
    TAX
    LDA.w !Battle_CellMap,X
    AND.b #!Battle_CellBlocksAny
    BEQ .slot_go
.slot_stop:
    TDC
    STA.w !Battle_ActorMoving,Y
    BRA .next_slot
.slot_go:
    LDA.b #1
    STA.w !Battle_ActorMoving,Y
    INC.b !BattleAct_HeadBusy
.next_slot:
    INC.b !BattleAct_HeadSetIdx
    BRA .test_slot
.set_done:
    LDA.b !BattleAct_HeadBusy
    BEQ .set_advance
    JMP .wait
.set_advance:
    JMP .done
.object:
    LDY.w !Battle_ActObjThread
    LDA.w !Battle_ActorMoving+!Battle_NumSlots,Y
    BEQ .object_start
    JMP .object_test
.object_start:
    LDA.w !Battle_ActObjUnkA5B5,Y
    STA.w !Battle_ActObjMoveAngle,Y
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battle_ActObjFacing,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer+!Battle_NumSlots,Y
    INC A                           ; !Battle_MoveKindHeading
    STA.w !Battle_ActorMoveKind+!Battle_NumSlots,Y
    TDC
    STA.w !Battle_ActObjUnkA31C,Y
    STA.w !Battle_ActObjMoveDone,Y
    DEC A                           ; $FF steps
    STA.w !Battle_ActorHeadSteps+!Battle_NumSlots,Y
    TYA
    ASL A
    TAX
    LDA.w !Battle_ActObjX,X
    STA.w !Battle_ActorFromX+!Battle_NumSlots,Y
    LDA.w !Battle_ActObjY,X
    STA.w !Battle_ActorFromY+!Battle_NumSlots,Y
.object_test:
    LDX.w !Battle_ActObjThread
    LDA.w !Battle_ActObjMoveDone,X
    BNE .object_stop
    LDA.b #!Battle_HeadProbeDist
    STA.b !Battle_SinScale
    LDA.w !Battle_ActObjMoveAngle,X
    JSR Battle_SinLookup
    STA.b !BattleAct_HeadCellRow
    LDX.w !Battle_ActObjThread
    CLC
    LDA.w !Battle_ActObjMoveAngle,X
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup
    STA.b !BattleAct_HeadCos
    TYA
    ASL A
    TAY
    CLC
    LDA.w !Battle_ActObjY,Y
    ADC.b !BattleAct_HeadCellRow
    AND.b #!Battle_PathRowMask
    STA.b !BattleAct_HeadCellRow
    CLC
    LDA.w !Battle_ActObjX,Y
    ADC.b !BattleAct_HeadCos
    JSR Battle_ShiftRight4
    ORA.b !BattleAct_HeadCellRow
    TAX
    LDA.w !Battle_CellMap,X
    AND.b #!Battle_CellBlocksAny
    BEQ .object_go
    LDX.w !Battle_ActObjThread
.object_stop:
    STZ.w !Battle_ActorMoving+!Battle_NumSlots,X
    BRA .done
.object_go:
    LDX.w !Battle_ActObjThread
    LDA.b #1
    STA.w !Battle_ActorMoving+!Battle_NumSlots,X
.wait:
    LDA.b #0
    JMP BattleAct_AdvanceScript     ; by 0: same opcode next frame
.done:
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpStartPosHistory ($C1691B–$C169B9, 159 bytes, with
; BattleAct_SetPosHistory)
; ==================================================================
; Opcode $A4 <delay> <b>: starts the position history of the thread's
; battler (threads 0-3) or of every slot of !Battle_ActTargetSet
; (threads 4-7; unlike most opcodes, threads 5-7 take the set too):
; !Battler_PosHistDelay = delay, !Battler_PosHistUnkAB7D = b,
; !Battler_PosHistTimer and !Battler_PosHistUnkAB88 = 1, all four
; records = the battler's !Battler_ScreenX/Y, and !Battler_PosHistOn =
; 3; advances 3. Object threads only advance.
; BattleAct_SetPosHistory is the shared part, with DP $8E = the length
; and $8F = the on value (opcode $A5, BattleAct_OpStopPosHistory, enters
; there with 1 and 0).
; Callers: BattleAct_OpcodeTable entry $A4; BattleAct_SetPosHistory by
;   JMP from BattleAct_OpStopPosHistory ($C1:69C0).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread); BattleAct_SetPosHistory: DP $80, $81,
;        $8E and $8F set
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered; DP $80/$81 =
;        the operands, $8E the length, $8F the on value
; Callees: BattleAct_AdvanceScript (JMP)
!BattleAct_HistDelay = !BattleTmp_80    ; 1 B: the delay operand
!BattleAct_HistUnk = !BattleTmp_81      ; 1 B: the second operand
!BattleAct_HistLen = !BattleTmp_8E      ; 1 B: the opcode's length
!BattleAct_HistOn = !BattleTmp_8E+1     ; 1 B: value for !Battler_PosHistOn
BattleAct_OpStartPosHistory:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_HistDelay
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_HistUnk
    LDA.b #3                        ; the length, and the on value
    STA.b !BattleAct_HistLen
    STA.b !BattleAct_HistOn
BattleAct_SetPosHistory:                ; header: see BattleAct_OpStartPosHistory
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    JMP .advance
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BCS .target_set
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.b !BattleAct_HistDelay
    STA.w !Battler_PosHistDelay,X
    LDA.b !BattleAct_HistUnk
    STA.w !Battler_PosHistUnkAB7D,X
    LDA.b #1
    STA.w !Battler_PosHistTimer,X
    STA.w !Battler_PosHistUnkAB88,X
    LDA.w !Battler_ScreenX,X
    STA.w !Battler_PosHistX,X
    STA.w !Battler_PosHistX+(2*!Battle_NumSlots),X
    STA.w !Battler_PosHistX+(4*!Battle_NumSlots),X
    STA.w !Battler_PosHistX+(6*!Battle_NumSlots),X
    LDA.w !Battler_ScreenY,X
    STA.w !Battler_PosHistY,X
    STA.w !Battler_PosHistY+(2*!Battle_NumSlots),X
    STA.w !Battler_PosHistY+(4*!Battle_NumSlots),X
    STA.w !Battler_PosHistY+(6*!Battle_NumSlots),X
    LDA.b !BattleAct_HistOn
    STA.w !Battler_PosHistOn,X
    BRA .advance
.target_set:
    TDC
    TAY
.set_slot:
    LDA.w !Battle_ActTargetSet,Y
    BMI .advance
    TAX
    LDA.b !BattleAct_HistDelay
    STA.w !Battler_PosHistDelay,X
    LDA.b !BattleAct_HistUnk
    STA.w !Battler_PosHistUnkAB7D,X
    LDA.b #1
    STA.w !Battler_PosHistTimer,X
    STA.w !Battler_PosHistUnkAB88,X
    LDA.w !Battler_ScreenX,X
    STA.w !Battler_PosHistX,X
    STA.w !Battler_PosHistX+(2*!Battle_NumSlots),X
    STA.w !Battler_PosHistX+(4*!Battle_NumSlots),X
    STA.w !Battler_PosHistX+(6*!Battle_NumSlots),X
    LDA.w !Battler_ScreenY,X
    STA.w !Battler_PosHistY,X
    STA.w !Battler_PosHistY+(2*!Battle_NumSlots),X
    STA.w !Battler_PosHistY+(4*!Battle_NumSlots),X
    STA.w !Battler_PosHistY+(6*!Battle_NumSlots),X
    LDA.b !BattleAct_HistOn
    STA.w !Battler_PosHistOn,X
    INY
    BRA .set_slot
.advance:
    LDA.b !BattleAct_HistLen
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpStopPosHistory ($C169BA–$C169C2, 9 bytes)
; ==================================================================
; Opcode $A5: !Battler_PosHistOn = 0 for the same battlers as opcode
; $A4 (BattleAct_OpStartPosHistory); advances 1. Quirk: it goes through
; the whole of opcode $A4's store, so it also writes the delay, the
; second operand, the timers and the records, with whatever DP $80/$81
; hold (it reads no operands).
; Callers: BattleAct_OpcodeTable entry $A5.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as from BattleAct_RunThread)
; Exit:  as BattleAct_OpStartPosHistory's (DP $8E = 1, $8F = 0)
; Callees: BattleAct_SetPosHistory (JMP)
BattleAct_OpStopPosHistory:
    LDA.b #1
    STA.b !BattleAct_HistLen
    STZ.b !BattleAct_HistOn
    JMP BattleAct_SetPosHistory

; ==================================================================
; BattleAct_OpMoveHeadingSteps ($C169C3–$C16AEF, 301 bytes)
; ==================================================================
; Opcode $A8 <n>: moves the thread's actor along its heading
; (!Battle_ActorUnkA5AA; objects !Battle_ActObjUnkA5B5) with mover kind
; !Battle_MoveKindHeading for n steps (!Battle_ActorHeadSteps = n, kept
; in !Battle_ActHeadSteps; the mover also stops it, probably at the
; screen's edge: see the heading-move notes in ram_battle.inc),
; and waits for the done flag; then advances 2. Unlike opcode $A2
; (BattleAct_OpMoveAlongHeading) it does not test the cells ahead. A
; start stores what opcode $A2's does (and sets !Battle_ActorMoving).
; By thread:
;   - threads 0-7 other than 4, the thread's battler: starts it when
;     not moving; when moving and done, clears !Battle_ActorMoving and
;     advances; else waits;
;   - thread 4: starts every slot of !Battle_ActTargetSet up to the
;     first that is already moving and waits; at such a slot it goes
;     through the whole set from the start instead, clearing
;     !Battle_ActorMoving of each done slot and counting the others in
;     DP $84, and advances when none is left. Quirk, kept (as in
;     BattleAct_OpCurveTo): a slot cleared while others still move is
;     started again on the next frame;
;   - threads 8-15, object j: as a battler with the object's entries
;     (index 11 + j), its position, and !Battle_ActObjMoveDone; it also
;     zeroes !Battle_ActObjUnkA31C.
; Callers: BattleAct_OpcodeTable entry $A8.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered; thread 4 also
;        DP $80-$81 and $84-$85
; Callees: BattleAct_AdvanceScript (JMP)
!BattleAct_StepsSetIdx = !BattleTmp_80  ; 2 B: thread 4: position in !Battle_ActTargetSet
!BattleAct_StepsBusy = !BattleTmp_84    ; 2 B: thread 4: slots still moving (zeroed 16-bit)
BattleAct_OpMoveHeadingSteps:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActHeadSteps
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    JMP .object
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BNE .one_battler
    JMP .target_set
.one_battler:
    TAX
    LDA.w !Battle_ActBattlers,X
    TAY
    LDA.w !Battle_ActorMoving,Y
    BNE .battler_moving
    LDA.w !Battle_ActHeadSteps
    STA.w !Battle_ActorHeadSteps,Y
    LDA.w !Battle_ActorUnkA5AA,Y
    STA.w !Battle_ActorMoveAngle,Y
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battler_Facing,Y
    LDA.w !Battler_ScreenX,Y
    STA.w !Battle_ActorFromX,Y
    LDA.w !Battler_ScreenY,Y
    STA.w !Battle_ActorFromY,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer,Y
    INC A                           ; !Battle_MoveKindHeading
    STA.w !Battle_ActorMoveKind,Y
    TDC
    STA.w !Battle_ActorUnkA311,Y
    STA.w !Battler_MoveDone,Y
    LDA.b #1
    STA.w !Battle_ActorMoving,Y
    BRA .battler_wait
.battler_moving:
    LDA.w !Battler_MoveDone,Y
    BEQ .battler_wait
    TYX
    STZ.w !Battle_ActorMoving,X
    JMP .done
.battler_wait:
    JMP .wait
.target_set:
    TDC
    TAX
    STX.b !BattleAct_StepsSetIdx
.start_slot:
    LDX.b !BattleAct_StepsSetIdx
    LDA.w !Battle_ActTargetSet,X
    BMI .set_started
    TAY
    LDA.w !Battle_ActorMoving,Y
    BNE .test_set
    LDA.w !Battle_ActHeadSteps
    STA.w !Battle_ActorHeadSteps,Y
    LDA.w !Battle_ActorUnkA5AA,Y
    STA.w !Battle_ActorMoveAngle,Y
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battler_Facing,Y
    LDA.w !Battler_ScreenX,Y
    STA.w !Battle_ActorFromX,Y
    LDA.w !Battler_ScreenY,Y
    STA.w !Battle_ActorFromY,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer,Y
    INC A                           ; !Battle_MoveKindHeading
    STA.w !Battle_ActorMoveKind,Y
    TDC
    STA.w !Battle_ActorUnkA311,Y
    STA.w !Battler_MoveDone,Y
    LDA.b #1
    STA.w !Battle_ActorMoving,Y
    INC.b !BattleAct_StepsSetIdx
    BRA .start_slot
.set_started:
    BRA .set_wait
.test_set:
    TDC
    TAY
    STY.b !BattleAct_StepsBusy
.test_slot:
    LDA.w !Battle_ActTargetSet,Y
    BMI .set_tested
    TAX
    LDA.w !Battler_MoveDone,X
    BEQ .slot_busy
    STZ.w !Battle_ActorMoving,X
    BRA .next_slot
.slot_busy:
    INC.b !BattleAct_StepsBusy
.next_slot:
    INY
    BRA .test_slot
.set_tested:
    LDA.b !BattleAct_StepsBusy
    BEQ .set_done
.set_wait:
    JMP .wait
.set_done:
    JMP .done
.object:
    LDY.w !Battle_ActObjThread
    LDA.w !Battle_ActorMoving+!Battle_NumSlots,Y
    BNE .object_moving
    LDA.w !Battle_ActHeadSteps
    STA.w !Battle_ActorHeadSteps+!Battle_NumSlots,Y
    LDA.w !Battle_ActObjUnkA5B5,Y
    STA.w !Battle_ActObjMoveAngle,Y
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battle_ActObjFacing,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer+!Battle_NumSlots,Y
    INC A                           ; !Battle_MoveKindHeading
    STA.w !Battle_ActorMoveKind+!Battle_NumSlots,Y
    TDC
    STA.w !Battle_ActObjUnkA31C,Y
    STA.w !Battle_ActObjMoveDone,Y
    TYA
    ASL A
    TAX
    LDA.w !Battle_ActObjX,X
    STA.w !Battle_ActorFromX+!Battle_NumSlots,Y
    LDA.w !Battle_ActObjY,X
    STA.w !Battle_ActorFromY+!Battle_NumSlots,Y
    LDA.b #1
    STA.w !Battle_ActorMoving+!Battle_NumSlots,Y
    BRA .wait
.object_moving:
    LDA.w !Battle_ActObjMoveDone,Y
    BEQ .wait
    TYX
    STZ.w !Battle_ActorMoving+!Battle_NumSlots,X
    BRA .done
.wait:
    LDA.b #0
    JMP BattleAct_AdvanceScript     ; by 0: same opcode next frame
.done:
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpMoveHeadingChecked ($C16AF0–$C16CF2, 515 bytes)
; ==================================================================
; Opcode $A9 <n>: opcode $A8 (BattleAct_OpMoveHeadingSteps) with opcode
; $A2's test of the cell ahead (BattleAct_OpMoveAlongHeading), and for
; the battlers also the box test: BattleAct_ProbeBoxOverlap at the
; battler's position; touching another battler (bit 7 of the result)
; stops it too. Each frame that none of these stops it, the opcode
; itself also counts !Battle_ActorHeadSteps down (as does the mover per
; step) and stops it at 0. Stopped, it clears !Battle_ActorMoving and
; advances 2; else it waits. A start is opcode $A8's, n from
; !Battle_ActHeadSteps. By thread:
;   - threads 0-7 other than 4, the thread's battler: as above;
;   - thread 4: starts every slot of !Battle_ActTargetSet up to the
;     first that is already moving, then tests from there with
;     DP $84 as the count of slots still going. Quirks, kept: the INC
;     of that count is dead code (after a BRA), so the opcode always
;     advances once the test loop ends; the loop ends at the first
;     slot whose countdown is not yet 0; the box test's slot (DP $80)
;     and then its result overwrite the loop index in DP $80, so the
;     next slot tested is entry result + 1 of the set; and on the frame
;     that starts the whole set the test loop starts at the set's end,
;     so it advances at once without testing;
;   - threads 8-15, object j: as a battler with the object's entries
;     (index 11 + j), but without the box test.
; Callers: BattleAct_OpcodeTable entry $A9.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered; DP $80-$83 and
;        the sine lookups' and box test's DP written; thread 4 also
;        DP $84
; Callees: Battle_SinLookup, Battle_ShiftRight4,
;          BattleAct_ProbeBoxOverlap, BattleAct_AdvanceScript (JMP)
!BattleAct_CheckSetIdx = !BattleTmp_80  ; 2 B: thread 4: position in !Battle_ActTargetSet (also the box test's slot)
!BattleAct_CheckBusy = !BattleTmp_84    ; 1 B: thread 4: slots still moving (never raised)
BattleAct_OpMoveHeadingChecked:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.w !Battle_ActHeadSteps
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    JMP .object
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BNE .one_battler
    JMP .target_set
.one_battler:
    TAX
    LDA.w !Battle_ActBattlers,X
    TAY
    LDA.w !Battle_ActorMoving,Y
    BNE .battler_test
    LDA.w !Battle_ActHeadSteps
    STA.w !Battle_ActorHeadSteps,Y
    LDA.w !Battle_ActorUnkA5AA,Y
    STA.w !Battle_ActorMoveAngle,Y
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battler_Facing,Y
    LDA.w !Battler_ScreenX,Y
    STA.w !Battle_ActorFromX,Y
    LDA.w !Battler_ScreenY,Y
    STA.w !Battle_ActorFromY,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer,Y
    INC A                           ; !Battle_MoveKindHeading
    STA.w !Battle_ActorMoveKind,Y
    TDC
    STA.w !Battle_ActorUnkA311,Y
    STA.w !Battler_MoveDone,Y
    LDA.b #1
    STA.w !Battle_ActorMoving,Y
.battler_test:
    LDA.w !Battler_MoveDone,Y
    BNE .battler_stop
    LDA.b #!Battle_HeadProbeDist
    STA.b !Battle_SinScale
    LDA.w !Battle_ActorMoveAngle,Y
    JSR Battle_SinLookup
    STA.b !BattleAct_HeadCellRow
    CLC
    LDA.w !Battle_ActorMoveAngle,Y
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup
    STA.b !BattleAct_HeadCos
    CLC
    LDA.w !Battler_ScreenY,Y
    ADC.b !BattleAct_HeadCellRow
    AND.b #!Battle_PathRowMask
    STA.b !BattleAct_HeadCellRow
    CLC
    LDA.w !Battler_ScreenX,Y
    ADC.b !BattleAct_HeadCos
    JSR Battle_ShiftRight4
    ORA.b !BattleAct_HeadCellRow
    TAX
    LDA.w !Battle_CellMap,X
    AND.b #!Battle_CellBlocksAny
    BNE .battler_stop
    STY.b !Battle_BoxTestSlot
    PHY
    TYX
    JSR BattleAct_ProbeBoxOverlap
    STA.b !Battle_BoxTestSlot       ; kept in DP $80 (scratch here)
    PLY
    LDA.b !Battle_BoxTestSlot
    BMI .battler_stop
    TYX
    DEC.w !Battle_ActorHeadSteps,X
    BNE .battler_wait
.battler_stop:
    TDC
    STA.w !Battle_ActorMoving,Y
    JMP .done
.battler_wait:
    JMP .wait
.target_set:
    TDC
    TAX
    STX.b !BattleAct_CheckSetIdx
.start_slot:
    LDX.b !BattleAct_CheckSetIdx
    LDA.w !Battle_ActTargetSet,X
    BMI .test_set
    TAY
    LDA.w !Battle_ActorMoving,Y
    BNE .test_set
    LDA.w !Battle_ActHeadSteps
    STA.w !Battle_ActorHeadSteps,Y
    LDA.w !Battle_ActorUnkA5AA,Y
    STA.w !Battle_ActorMoveAngle,Y
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battler_Facing,Y
    LDA.w !Battler_ScreenX,Y
    STA.w !Battle_ActorFromX,Y
    LDA.w !Battler_ScreenY,Y
    STA.w !Battle_ActorFromY,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer,Y
    INC A                           ; !Battle_MoveKindHeading
    STA.w !Battle_ActorMoveKind,Y
    TDC
    STA.w !Battle_ActorUnkA311,Y
    STA.w !Battler_MoveDone,Y
    LDA.b #1
    STA.w !Battle_ActorMoving,Y
    INC.b !BattleAct_CheckSetIdx
    BRA .start_slot
.test_set:
    STZ.b !BattleAct_CheckBusy
.test_slot:
    LDX.b !BattleAct_CheckSetIdx
    LDA.w !Battle_ActTargetSet,X
    BMI .set_tested
    TAY
    LDA.w !Battler_MoveDone,Y
    BNE .slot_stop
    LDA.b #!Battle_HeadProbeDist
    STA.b !Battle_SinScale
    LDA.w !Battle_ActorMoveAngle,Y
    JSR Battle_SinLookup
    STA.b !BattleAct_HeadCellRow
    CLC
    LDA.w !Battle_ActorMoveAngle,Y
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup
    STA.b !BattleAct_HeadCos
    CLC
    LDA.w !Battler_ScreenY,Y
    ADC.b !BattleAct_HeadCellRow
    AND.b #!Battle_PathRowMask
    STA.b !BattleAct_HeadCellRow
    CLC
    LDA.w !Battler_ScreenX,Y
    ADC.b !BattleAct_HeadCos
    JSR Battle_ShiftRight4
    ORA.b !BattleAct_HeadCellRow
    TAX
    LDA.w !Battle_CellMap,X
    AND.b #!Battle_CellBlocksAny
    BNE .slot_stop
    STY.b !Battle_BoxTestSlot       ; quirk: overwrites the loop index
    PHY
    TYX
    JSR BattleAct_ProbeBoxOverlap
    STA.b !Battle_BoxTestSlot       ; and again, with the result
    PLY
    LDA.b !Battle_BoxTestSlot
    BMI .slot_stop
    TYX
    DEC.w !Battle_ActorHeadSteps,X
    BNE .set_tested                 ; quirk: leaves the loop
.slot_stop:
    TDC
    STA.w !Battle_ActorMoving,Y
    BRA .next_slot
    INC.b !BattleAct_CheckBusy      ; dead code: no path reaches it
.next_slot:
    INC.b !BattleAct_CheckSetIdx
    BRA .test_slot
.set_tested:
    LDA.b !BattleAct_CheckBusy
    BEQ .set_done
    JMP .wait
.set_done:
    JMP .done
.object:
    LDY.w !Battle_ActObjThread
    LDA.w !Battle_ActorMoving+!Battle_NumSlots,Y
    BEQ .object_start
    JMP .object_test
.object_start:
    LDA.w !Battle_ActHeadSteps
    STA.w !Battle_ActorHeadSteps+!Battle_NumSlots,Y
    LDA.w !Battle_ActObjUnkA5B5,Y
    STA.w !Battle_ActObjMoveAngle,Y
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battle_ActObjFacing,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer+!Battle_NumSlots,Y
    INC A                           ; !Battle_MoveKindHeading
    STA.w !Battle_ActorMoveKind+!Battle_NumSlots,Y
    TDC
    STA.w !Battle_ActObjUnkA31C,Y
    STA.w !Battle_ActObjMoveDone,Y
    TYA
    ASL A
    TAX
    LDA.w !Battle_ActObjX,X
    STA.w !Battle_ActorFromX+!Battle_NumSlots,Y
    LDA.w !Battle_ActObjY,X
    STA.w !Battle_ActorFromY+!Battle_NumSlots,Y
    LDA.b #1
    STA.w !Battle_ActorMoving+!Battle_NumSlots,Y
.object_test:
    LDX.w !Battle_ActObjThread
    LDA.w !Battle_ActObjMoveDone,X
    BNE .object_stop
    LDA.b #!Battle_HeadProbeDist
    STA.b !Battle_SinScale
    LDA.w !Battle_ActObjMoveAngle,X
    JSR Battle_SinLookup
    STA.b !BattleAct_HeadCellRow
    LDX.w !Battle_ActObjThread
    CLC
    LDA.w !Battle_ActObjMoveAngle,X
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup
    STA.b !BattleAct_HeadCos
    TYA
    ASL A
    TAY
    CLC
    LDA.w !Battle_ActObjY,Y
    ADC.b !BattleAct_HeadCellRow
    AND.b #!Battle_PathRowMask
    STA.b !BattleAct_HeadCellRow
    CLC
    LDA.w !Battle_ActObjX,Y
    ADC.b !BattleAct_HeadCos
    JSR Battle_ShiftRight4
    ORA.b !BattleAct_HeadCellRow
    TAX
    LDA.w !Battle_CellMap,X
    AND.b #!Battle_CellBlocksAny
    BNE .object_stop
    LDX.w !Battle_ActObjThread
    DEC.w !Battle_ActorHeadSteps+!Battle_NumSlots,X
    BNE .wait
.object_stop:
    LDX.w !Battle_ActObjThread
    STZ.w !Battle_ActorMoving+!Battle_NumSlots,X
    BRA .done
.wait:
    LDA.b #0
    JMP BattleAct_AdvanceScript     ; by 0: same opcode next frame
.done:
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpCircleToCalc ($C16CF3–$C16F30, 574 bytes, with
; BattleAct_CircleMove and BattleAct_CircleMoveKind)
; ==================================================================
; Opcode $C0 <n> <r> <a> <q>: moves the thread's actor round a circle
; whose centre is the point left by BattleAct_RunCalc handler n, with
; mover kind !Battle_MoveKindCircle ($CF:F1F8, unmatched; see
; !Battle_ActorCircleX): radius r & !Battle_CircleRadiusMask, start
; angle a ($FF (!Battle_CurveKeepHeading) = the actor's
; !Battle_ActorUnkA5AA, or !Battle_ActObjUnkA5B5 for an object), and
; q quarter turns: the angle moves by the actor's
; !Battle_ActorMoveSpeed per step, growing when bit 7 of r is clear
; and shrinking when it is set; the angle is kept one step before a so
; that the first step lands on it; the step count is q * 64 / speed
; (Battle_Mul8, Battle_Divide), so the actor turns q quarters (minus
; the remainder). Length 5. "Circle" is inferred from the mover, which
; puts radius * sin / cos of the angle in !Battler_UnkA4AF / A4A4
; (the offsets the position history also adds to the position).
; BattleAct_CircleMove (opcode $C1's entry, length set) uses kind
; !Battle_MoveKindCircle; BattleAct_CircleMoveKind (opcodes $C2/$C3,
; length and kind set) the kind in DP $8F. The shared part, by thread:
;   - threads 0-7 other than 4, the thread's battler: when it is not
;     moving (!Battle_ActorMoving 0) puts it at the centre
;     (!Battler_ScreenX/Y and !Battle_ActorCircleX/Y), sets the circle
;     up, !Battle_ActorMoveTimer = 1, the kind, !Battler_MoveDone = 0
;     and !Battle_ActorMoving = 1, and waits (advance 0); while it
;     moves it waits until !Battler_MoveDone, then clears
;     !Battle_ActorMoving and advances by the length;
;   - thread 4: starts every slot of !Battle_ActTargetSet the same way
;     up to the first that is already moving, and waits when it runs
;     to the set's end. Once a slot is moving it tests the whole set:
;     each slot with !Battler_MoveDone gets !Battle_ActorMoving
;     cleared and is counted (in DP $84). Quirk, kept: it advances
;     when that count is 0 and waits otherwise (the reverse of the
;     battlers' test), and the slots it stopped are started again the
;     next frame, so in practice it advances on the frame after the
;     start;
;   - threads 8-15, object j: as a battler with the object's entries
;     of the actor arrays (index 11 + j, the word array 22 + 2j) and
;     !Battle_ActObjMoveDone, but the object's position
;     (!Battle_ActObjX/Y) is not moved to the centre.
; Callers: BattleAct_OpcodeTable entry $C0; BattleAct_CircleMove by
;   JMP from BattleAct_OpCircleToUnkPoint ($C1:6F50),
;   BattleAct_CircleMoveKind by JMP from BattleAct_OpEllipseToCalc
;   ($C1:6F72) and BattleAct_OpEllipseToUnkPoint ($C1:6F97).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread); BattleAct_CircleMove: also DP $80, $82,
;        $84 = r, a, q, DP $8E = the length and the centre in
;        !Battle_ActCalcOutA/B; BattleAct_CircleMoveKind: all that and
;        DP $8F = the kind
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered;
;        !Battle_ActCalcOutA/B = the centre; DP $80-$84, $86, $8E-$8F
;        written (thread 4 also DP $87; $82 becomes the start angle
;        when a was $FF); a start also writes Battle_Mul8's and
;        Battle_Divide's DP
; Callees: BattleAct_RunCalc, Battle_Mul8, Battle_Divide,
;          BattleAct_AdvanceScript (JMP)
!BattleAct_CircleCalc = !BattleTmp_86   ; 1 B: calc handler; then (2 B) thread 4: position in !Battle_ActTargetSet
!BattleAct_CircleRadius = !BattleTmp_80 ; 1 B: r (bit 7: angle shrinks)
!BattleAct_CircleAngle = !BattleTmp_82  ; 1 B: a
!BattleAct_CircleQuarters = !BattleTmp_84 ; 1 B: q; thread 4's test reuses it as the count of slots done
!BattleAct_CircleKind = !BattleTmp_8E+1 ; 1 B: mover kind
BattleAct_OpCircleToCalc:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_CircleCalc
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_CircleRadius
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_CircleAngle
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_CircleQuarters
    LDA.b !BattleAct_CircleCalc
    JSR BattleAct_RunCalc
    LDA.b #5
    STA.b !BattleAct_MoveLen
BattleAct_CircleMove:                   ; header: see BattleAct_OpCircleToCalc
    LDA.b #!Battle_MoveKindCircle
    STA.b !BattleAct_CircleKind
BattleAct_CircleMoveKind:               ; header: see BattleAct_OpCircleToCalc
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    JMP .object
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BNE .one_battler
    JMP .target_set
.one_battler:
    TAX
    LDA.w !Battle_ActBattlers,X
    TAY
    LDA.w !Battle_ActorMoving,Y
    BEQ .battler_start
    JMP .battler_moving
.battler_start:
    LDA.b !BattleAct_CircleAngle
    CMP.b #!Battle_CurveKeepHeading
    BNE .battler_angle
    LDA.w !Battle_ActorUnkA5AA,Y
    STA.b !BattleAct_CircleAngle
.battler_angle:
    LDA.w !Battle_ActCalcOutA
    STA.w !Battle_ActorCircleX,Y
    STA.w !Battler_ScreenX,Y
    LDA.w !Battle_ActCalcOutB
    STA.w !Battle_ActorCircleY,Y
    STA.w !Battler_ScreenY,Y
    LDA.b !BattleAct_CircleRadius
    BMI .battler_shrink
    SEC
    LDA.b !BattleAct_CircleAngle
    SBC.w !Battle_ActorMoveSpeed,Y
    STA.w !Battle_ActorCircleAngle,Y
    LDA.w !Battle_ActorMoveSpeed,Y
    STA.w !Battle_ActorCircleStep,Y
    BRA .battler_radius
.battler_shrink:
    CLC
    LDA.b !BattleAct_CircleAngle
    ADC.w !Battle_ActorMoveSpeed,Y
    STA.w !Battle_ActorCircleAngle,Y
    LDA.w !Battle_ActorMoveSpeed,Y
    EOR.b #!Battle_Invert8
    INC A
    STA.w !Battle_ActorCircleStep,Y
.battler_radius:
    LDA.b !BattleAct_CircleRadius
    AND.b #!Battle_CircleRadiusMask
    STA.w !Battle_ActorCircleRadius,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer,Y
    LDA.b !BattleAct_CircleKind
    STA.w !Battle_ActorMoveKind,Y
    TDC
    STA.w !Battler_MoveDone,Y
    PHY
    LDA.b !BattleAct_CircleQuarters
    STA.b !Battle_Mul8B
    LDA.b #!Battle_AngleQuarter
    STA.b !Battle_Mul8A
    JSR Battle_Mul8
    LDX.b !Battle_Mul8Product
    STX.b !Battle_DivDividend
    LDA.w !Battle_ActorMoveSpeed,Y
    STA.b !Battle_DivDivisor
    JSR Battle_Divide
    TYA
    ASL A
    TAY                             ; slot * 2
    LDA.b !Battle_DivQuotient
    STA.w !Battle_ActorCircleSteps,Y
    LDA.b !Battle_DivQuotient+1
    STA.w !Battle_ActorCircleSteps+1,Y
    PLY
    LDA.b #1
    STA.w !Battle_ActorMoving,Y
    BRA .battler_wait
.battler_moving:
    LDA.w !Battler_MoveDone,Y
    BEQ .battler_wait
    TDC
    STA.w !Battle_ActorMoving,Y
    JMP .done
.battler_wait:
    JMP .wait
.target_set:
    TDC
    TAX
    STX.b !BattleAct_CircleCalc
.start_slot:
    LDX.b !BattleAct_CircleCalc
    LDA.w !Battle_ActTargetSet,X
    BPL .start_entry
    JMP .set_started
.start_entry:
    TAY
    LDA.w !Battle_ActorMoving,Y
    BEQ .slot_start
    JMP .test_set
.slot_start:
    LDA.b !BattleAct_CircleAngle
    CMP.b #!Battle_CurveKeepHeading
    BNE .slot_angle
    LDA.w !Battle_ActorUnkA5AA,Y
    STA.b !BattleAct_CircleAngle
.slot_angle:
    LDA.w !Battle_ActCalcOutA
    STA.w !Battle_ActorCircleX,Y
    STA.w !Battler_ScreenX,Y
    LDA.w !Battle_ActCalcOutB
    STA.w !Battle_ActorCircleY,Y
    STA.w !Battler_ScreenY,Y
    LDA.b !BattleAct_CircleRadius
    BMI .slot_shrink
    SEC
    LDA.b !BattleAct_CircleAngle
    SBC.w !Battle_ActorMoveSpeed,Y
    STA.w !Battle_ActorCircleAngle,Y
    LDA.w !Battle_ActorMoveSpeed,Y
    STA.w !Battle_ActorCircleStep,Y
    BRA .slot_radius
.slot_shrink:
    CLC
    LDA.b !BattleAct_CircleAngle
    ADC.w !Battle_ActorMoveSpeed,Y
    STA.w !Battle_ActorCircleAngle,Y
    LDA.w !Battle_ActorMoveSpeed,Y
    EOR.b #!Battle_Invert8
    INC A
    STA.w !Battle_ActorCircleStep,Y
.slot_radius:
    LDA.b !BattleAct_CircleRadius
    AND.b #!Battle_CircleRadiusMask
    STA.w !Battle_ActorCircleRadius,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer,Y
    LDA.b !BattleAct_CircleKind
    STA.w !Battle_ActorMoveKind,Y
    TDC
    STA.w !Battler_MoveDone,Y
    PHY
    LDA.b !BattleAct_CircleQuarters
    STA.b !Battle_Mul8B
    LDA.b #!Battle_AngleQuarter
    STA.b !Battle_Mul8A
    JSR Battle_Mul8
    LDX.b !Battle_Mul8Product
    STX.b !Battle_DivDividend
    LDA.w !Battle_ActorMoveSpeed,Y
    STA.b !Battle_DivDivisor
    JSR Battle_Divide
    TYA
    ASL A
    TAY                             ; slot * 2
    LDA.b !Battle_DivQuotient
    STA.w !Battle_ActorCircleSteps,Y
    LDA.b !Battle_DivQuotient+1
    STA.w !Battle_ActorCircleSteps+1,Y
    PLY
    LDA.b #1
    STA.w !Battle_ActorMoving,Y
    INC.b !BattleAct_CircleCalc
    JMP .start_slot
.set_started:
    BRA .set_wait
.test_set:
    TDC
    TAX
    STX.b !BattleAct_CircleCalc
    STZ.b !BattleAct_CircleQuarters
.test_slot:
    LDX.b !BattleAct_CircleCalc
    LDA.w !Battle_ActTargetSet,X
    BMI .set_tested
    TAX
    LDA.w !Battler_MoveDone,X
    BEQ .next_slot
    STZ.w !Battle_ActorMoving,X
    INC.b !BattleAct_CircleQuarters
.next_slot:
    INC.b !BattleAct_CircleCalc
    BRA .test_slot
.set_tested:
    LDA.b !BattleAct_CircleQuarters
    BEQ .set_done                   ; quirk: advances when no slot is done
.set_wait:
    JMP .wait
.set_done:
    JMP .done
.object:
    LDY.w !Battle_ActObjThread
    LDA.w !Battle_ActorMoving+!Battle_NumSlots,Y
    BEQ .object_start
    JMP .object_moving
.object_start:
    LDA.b !BattleAct_CircleAngle
    CMP.b #!Battle_CurveKeepHeading
    BNE .object_angle
    LDA.w !Battle_ActObjUnkA5B5,Y
    STA.b !BattleAct_CircleAngle
.object_angle:
    LDA.w !Battle_ActCalcOutA
    STA.w !Battle_ActorCircleX+!Battle_NumSlots,Y
    LDA.w !Battle_ActCalcOutB
    STA.w !Battle_ActorCircleY+!Battle_NumSlots,Y
    LDA.b !BattleAct_CircleRadius
    BMI .object_shrink
    SEC
    LDA.b !BattleAct_CircleAngle
    SBC.w !Battle_ActorMoveSpeed+!Battle_NumSlots,Y
    STA.w !Battle_ActorCircleAngle+!Battle_NumSlots,Y
    LDA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,Y
    STA.w !Battle_ActorCircleStep+!Battle_NumSlots,Y
    BRA .object_radius
.object_shrink:
    CLC
    LDA.b !BattleAct_CircleAngle
    ADC.w !Battle_ActorMoveSpeed+!Battle_NumSlots,Y
    STA.w !Battle_ActorCircleAngle+!Battle_NumSlots,Y
    LDA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,Y
    EOR.b #!Battle_Invert8
    INC A
    STA.w !Battle_ActorCircleStep+!Battle_NumSlots,Y
.object_radius:
    LDA.b !BattleAct_CircleRadius
    AND.b #!Battle_CircleRadiusMask
    STA.w !Battle_ActorCircleRadius+!Battle_NumSlots,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer+!Battle_NumSlots,Y
    LDA.b !BattleAct_CircleKind
    STA.w !Battle_ActorMoveKind+!Battle_NumSlots,Y
    TDC
    STA.w !Battle_ActObjMoveDone,Y
    PHY
    LDA.b !BattleAct_CircleQuarters
    STA.b !Battle_Mul8B
    LDA.b #!Battle_AngleQuarter
    STA.b !Battle_Mul8A
    JSR Battle_Mul8
    LDX.b !Battle_Mul8Product
    STX.b !Battle_DivDividend
    LDA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,Y
    STA.b !Battle_DivDivisor
    JSR Battle_Divide
    TYA
    ASL A
    TAY                             ; j * 2
    LDA.b !Battle_DivQuotient
    STA.w !Battle_ActorCircleSteps+(2*!Battle_NumSlots),Y
    LDA.b !Battle_DivQuotient+1
    STA.w !Battle_ActorCircleSteps+(2*!Battle_NumSlots)+1,Y
    PLY
    LDA.b #1
    STA.w !Battle_ActorMoving+!Battle_NumSlots,Y
    BRA .wait
.object_moving:
    LDX.w !Battle_ActObjThread
    LDA.w !Battle_ActObjMoveDone,X
    BEQ .wait
    STZ.w !Battle_ActorMoving+!Battle_NumSlots,X
    BRA .done
.wait:
    LDA.b #0
    JMP BattleAct_AdvanceScript     ; by 0: same opcode next frame
.done:
    LDA.b !BattleAct_MoveLen
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpCircleToUnkPoint ($C16F31–$C16F52, 34 bytes)
; ==================================================================
; Opcode $C1 <r> <a> <q>: opcode $C0 (BattleAct_OpCircleToCalc) round
; the point in !Battle_ActUnkPointX/Y; length 4.
; Callers: BattleAct_OpcodeTable entry $C1.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  as BattleAct_OpCircleToCalc's (DP $86 not set from a script
;        byte; DP $8E = 4)
; Callees: BattleAct_CircleMove (JMP)
BattleAct_OpCircleToUnkPoint:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_CircleRadius
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_CircleAngle
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_CircleQuarters
    LDA.w !Battle_ActUnkPointX
    STA.w !Battle_ActCalcOutA
    LDA.w !Battle_ActUnkPointY
    STA.w !Battle_ActCalcOutB
    LDA.b #4
    STA.b !BattleAct_MoveLen
    JMP BattleAct_CircleMove

; ==================================================================
; BattleAct_OpEllipseToCalc ($C16F53–$C16F74, 34 bytes)
; ==================================================================
; Opcode $C2 <n> <r> <a> <q>: opcode $C0 (BattleAct_OpCircleToCalc)
; with mover kind !Battle_MoveKindEllipse ($CF:F354, unmatched), which
; differs from the circle mover only in using half the radius for the
; y offset (so probably an ellipse, flattened like a ring on the
; ground); length 5. The kind is the same 5 as the length (one store
; of A to each).
; Callers: BattleAct_OpcodeTable entry $C2.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  as BattleAct_OpCircleToCalc's
; Callees: BattleAct_RunCalc, BattleAct_CircleMoveKind (JMP)
BattleAct_OpEllipseToCalc:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_CircleCalc
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_CircleRadius
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_CircleAngle
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_CircleQuarters
    LDA.b !BattleAct_CircleCalc
    JSR BattleAct_RunCalc
    LDA.b #5                        ; the length; also !Battle_MoveKindEllipse
    STA.b !BattleAct_MoveLen
    STA.b !BattleAct_CircleKind
    JMP BattleAct_CircleMoveKind

; ==================================================================
; BattleAct_OpEllipseToUnkPoint ($C16F75–$C16F99, 37 bytes)
; ==================================================================
; Opcode $C3 <r> <a> <q>: opcode $C2 (BattleAct_OpEllipseToCalc) round
; the point in !Battle_ActUnkPointX/Y; length 4.
; Callers: BattleAct_OpcodeTable entry $C3.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  as BattleAct_OpCircleToCalc's (DP $86 not set from a script
;        byte; DP $8E = 4, $8F = 5)
; Callees: BattleAct_CircleMoveKind (JMP)
BattleAct_OpEllipseToUnkPoint:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_CircleRadius
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_CircleAngle
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_CircleQuarters
    LDA.w !Battle_ActUnkPointX
    STA.w !Battle_ActCalcOutA
    LDA.w !Battle_ActUnkPointY
    STA.w !Battle_ActCalcOutB
    LDA.b #4
    STA.b !BattleAct_MoveLen
    INC A                           ; !Battle_MoveKindEllipse
    STA.b !BattleAct_CircleKind
    JMP BattleAct_CircleMoveKind

; ==================================================================
; BattleAct_OpStepUnkA4AF ($C16F9A–$C16FEE, 85 bytes, with
; BattleAct_StepUnkA4AF)
; ==================================================================
; Opcode $C4 <t> <d>: each frame adds d to the thread's battler's
; !Battler_UnkA4AF (the y offset the movers and the position history
; use) and waits (advance 0), until the value equals t, then advances
; by the length (3). The test is for equality before the add, and the
; add wraps in 8 bits, so the value reaches t only when gcd(d,256)
; divides (t - value); otherwise (e.g. d = 0, or an even d with an odd
; gap) the opcode waits forever. By thread:
;   - threads 0-7 other than 4, the thread's battler: as above;
;   - thread 4: steps every slot of !Battle_ActTargetSet; it advances
;     as soon as one slot (in set order) already equals t, leaving the
;     later slots unstepped that frame;
;   - threads 8-15: nothing; advances at once.
; BattleAct_StepUnkA4AF is the entry with DP $80/$81 = t/d and DP $8E
; = the length set (opcode $C5, BattleAct_OpStepUnkA4AFTo0).
; Callers: BattleAct_OpcodeTable entry $C4; BattleAct_StepUnkA4AF by
;   BRA from BattleAct_OpStepUnkA4AFTo0 ($C1:6FFA).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread); !Battle_ActThread read 16-bit by LDX
;        (BattleAct_RunThread stores it 16-bit)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered; DP $80, $81,
;        $8E written
; Callees: BattleAct_AdvanceScript (JMP)
!BattleAct_StepTarget = !BattleTmp_80   ; 1 B: t
!BattleAct_StepDelta = !BattleTmp_80+1  ; 1 B: d
BattleAct_OpStepUnkA4AF:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_StepTarget
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_StepDelta
    LDA.b #3
    STA.b !BattleAct_MoveLen
BattleAct_StepUnkA4AF:                  ; header: see BattleAct_OpStepUnkA4AF
    LDX.w !Battle_ActThread
    CPX.w #!Battle_ActFirstObjThread
    BCC .battler
    JMP .done
.battler:
    CPX.w #!Battle_ActTargetSetThread
    BNE .one_battler
    JMP .target_set
.one_battler:
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.w !Battler_UnkA4AF,X
    CMP.b !BattleAct_StepTarget
    BEQ .done
    CLC
    ADC.b !BattleAct_StepDelta
    STA.w !Battler_UnkA4AF,X
    BRA .wait
.target_set:
    TDC
    TAY
.slot:
    LDA.w !Battle_ActTargetSet,Y
    BMI .wait
    TAX
    LDA.w !Battler_UnkA4AF,X
    CMP.b !BattleAct_StepTarget
    BEQ .done
    CLC
    ADC.b !BattleAct_StepDelta
    STA.w !Battler_UnkA4AF,X
    INY
    BRA .slot
.wait:
    TDC
    JMP BattleAct_AdvanceScript     ; by 0: same opcode next frame
.done:
    LDA.b !BattleAct_MoveLen
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpStepUnkA4AFTo0 ($C16FEF–$C16FFB, 13 bytes)
; ==================================================================
; Opcode $C5 <d>: opcode $C4 (BattleAct_OpStepUnkA4AF) with t = 0:
; steps !Battler_UnkA4AF back to 0 by d per frame; length 2.
; Callers: BattleAct_OpcodeTable entry $C5.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  as BattleAct_OpStepUnkA4AF's (DP $80 = 0, $8E = 2)
; Callees: BattleAct_StepUnkA4AF (BRA)
BattleAct_OpStepUnkA4AFTo0:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_StepDelta
    STZ.b !BattleAct_StepTarget
    LDA.b #2
    STA.b !BattleAct_MoveLen
    BRA BattleAct_StepUnkA4AF

; ==================================================================
; BattleAct_OpIncUnkA5D8 ($C16FFC–$C1702A, 47 bytes)
; ==================================================================
; Opcode $D0: counts the thread's battler's !Battler_UnkA5D8 up by 1
; (no reader of it found); length 1. Thread 4 does it for the entries
; of !Battle_ActBattlers from entry 1 on (the slots from $AE97/$AE98,
; the main target, the target set) up to the first $FF, not for
; !Battle_ActTargetSet as the other opcodes do; threads 8-15 do
; nothing.
; Callers: BattleAct_OpcodeTable entry $D0.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread); !Battle_ActThread read 16-bit by LDX
;        (BattleAct_RunThread stores it 16-bit)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpIncUnkA5D8:
    LDX.w !Battle_ActThread
    CPX.w #!Battle_ActFirstObjThread
    BCC .battler
    JMP .done
.battler:
    CPX.w #!Battle_ActTargetSetThread
    BNE .one_battler
    JMP .list
.one_battler:
    LDA.w !Battle_ActBattlers,X
    TAX
    INC.w !Battler_UnkA5D8,X
    BRA .done
.list:
    TDC
    TAY
.entry:
    LDA.w !Battle_ActBattlers+1,Y   ; from entry 1
    BMI .done
    TAX
    INC.w !Battler_UnkA5D8,X
    INY
    BRA .entry
.done:
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpClearUnkA5D8 ($C1702B–$C17059, 47 bytes)
; ==================================================================
; Opcode $D1: zeroes !Battler_UnkA5D8, for the same battlers as opcode
; $D0 (BattleAct_OpIncUnkA5D8); length 1.
; Callers: BattleAct_OpcodeTable entry $D1.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread); !Battle_ActThread read 16-bit by LDX
;        (BattleAct_RunThread stores it 16-bit)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpClearUnkA5D8:
    LDX.w !Battle_ActThread
    CPX.w #!Battle_ActFirstObjThread
    BCC .battler
    JMP .done
.battler:
    CPX.w #!Battle_ActTargetSetThread
    BNE .one_battler
    JMP .list
.one_battler:
    LDA.w !Battle_ActBattlers,X
    TAX
    STZ.w !Battler_UnkA5D8,X
    BRA .done
.list:
    TDC
    TAY
.entry:
    LDA.w !Battle_ActBattlers+1,Y   ; from entry 1
    BMI .done
    TAX
    STZ.w !Battler_UnkA5D8,X
    INY
    BRA .entry
.done:
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpMoveKind4ToCalc ($C1705A–$C1720D, 436 bytes)
; ==================================================================
; Opcode $D2 <n>: sets up, without starting it, a move of the thread's
; actor to the point left by BattleAct_RunCalc handler n with mover
; kind !Battle_MoveKindUnk4 ($CF:F23D, unmatched); length 2; it
; advances at once. !Battle_ActorMoving is not set, so the mover (which
; runs only for moving actors, $CF:EFC4) waits for opcode $D4, $D5 or
; $D6 (BattleAct_OpRunMoveAfterUnkAAFC, BattleAct_OpRunMoveAfterMajorDist)
; to start it. Set up as an arc move (BattleAct_OpArcToCalc) but with
; the unit step from BattleAct_CalcMidpointSteps (1/64 of the
; distance, then * the actor's !Battle_ActorMoveSpeed), arc mode 0,
; start speed !Battle_ArcSpeedHalf and
; accel !Battle_ArcSpeedHalf / !Battle_Kind4AccelDiv ($FF), and
; !Battle_ActorUnkAB00 = 0. BattleAct_CalcMidpointSteps also leaves the
; raised midpoint (!Battle_ActUnkMidX/Y, read by opcode $D3) and
; !Battle_ActUnkAAFC = !Battle_ActUnkAAFCStart. The kind-4 mover (read,
; not matched) steps the offset and the arc like the arc mover, sets
; the done flag at the top of the rise, and once falling sets it again
; and stops when the actor is within 16 pixels of the point in both
; axes with !Battler_UnkA4AF between -24 and -1 (so probably a jump
; that lands at the point; "jump" is a guess). By thread:
;   - threads 0-7 other than 4, the thread's battler: from its
;     position (also kept in !Battle_ActorFromX/Y);
;   - thread 4: nothing;
;   - threads 8-15, object j: from !Battle_ActObjX/Y, with the object's
;     entries of the actor arrays (index 11 + j; the word arrays
;     22 + 2j, the 4-byte ones 44 + 4j); it also keeps the angle
;     (Battle_CalcAngle) in !Battle_ActObjMoveAngle and its facing in
;     !Battle_ActObjFacing. For a battler the angle is computed but not
;     used.
; Callers: BattleAct_OpcodeTable entry $D2.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered;
;        !Battle_ActCalcOutA/B = the point; battlers: DP $80-$81;
;        both: the angle's, BattleAct_CalcMidpointSteps', multiply's and
;        divide's DP scratch
; Callees: BattleAct_RunCalc, Battle_CalcAngle,
;          BattleAct_CalcMidpointSteps, Battle_Mul8x16, Battle_Divide,
;          BattleAct_AdvanceScript (JMP)
!BattleAct_Kind4Slot = !BattleTmp_80    ; 2 B: the battler slot
BattleAct_OpMoveKind4ToCalc:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    JSR BattleAct_RunCalc
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    JMP .object
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BNE .one_battler
    JMP .target_set
.one_battler:
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    STX.b !BattleAct_Kind4Slot
    LDA.w !Battler_ScreenX,X
    STA.b !Battle_GeoOriginX
    STA.w !Battle_ActorFromX,X
    LDA.w !Battler_ScreenY,X
    STA.b !Battle_GeoOriginY
    STA.w !Battle_ActorFromY,X
    LDA.w !Battle_ActCalcOutA
    STA.b !Battle_GeoPointX
    LDA.w !Battle_ActCalcOutB
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle
    JSR BattleAct_CalcMidpointSteps
    LDY.b !BattleAct_Kind4Slot
    LDA.w !Battle_ActMoveUnitX
    STA.b !Battle_MulFactor16
    LDA.w !Battle_ActMoveUnitX+1
    STA.b !Battle_MulFactor16+1
    LDA.w !Battle_ActorMoveSpeed,Y
    STA.b !Battle_MulFactor8
    JSR Battle_Mul8x16
    LDX.b !Battle_MulProduct
    STX.w !Battle_ActMoveUnitX
    LDA.w !Battle_ActMoveUnitY
    STA.b !Battle_MulFactor16
    LDA.w !Battle_ActMoveUnitY+1
    STA.b !Battle_MulFactor16+1
    LDA.w !Battle_ActorMoveSpeed,Y
    STA.b !Battle_MulFactor8
    JSR Battle_Mul8x16
    LDX.b !Battle_MulProduct
    STX.w !Battle_ActMoveUnitY
    LDA.b !BattleAct_Kind4Slot
    ASL A
    TAX
    STZ.w !Battle_ActorArcMode,X
    STZ.w !Battle_ActorArcMode+1,X
    LDX.w #!Battle_ArcSpeedHalf
    STX.b !Battle_DivDividend
    LDA.b #!Battle_Kind4AccelDiv
    STA.b !Battle_DivDivisor
    JSR Battle_Divide
    LDY.b !BattleAct_Kind4Slot
    LDA.w !Battle_ActCalcOutA
    STA.w !Battle_ActorToX,Y
    LDA.w !Battle_ActCalcOutB
    STA.w !Battle_ActorToY,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer,Y
    LDA.b #!Battle_MoveKindUnk4
    STA.w !Battle_ActorMoveKind,Y
    TDC
    STA.w !Battler_MoveDone,Y
    STA.w !Battle_ActorUnkAB00,Y
    TYA
    ASL A
    TAY                             ; slot * 2
    ASL A
    TAX                             ; slot * 4
    REP #$20
    LDA.w !Battle_ActMoveUnitX
    STA.w !Battle_ActorStepX,Y
    LDA.w !Battle_ActMoveUnitY
    STA.w !Battle_ActorStepY,Y
    LDA.b !Battle_DivQuotient
    STA.w !Battle_ActorArcAccel,Y
    LDA.b !Battle_DivDividend           ; the start speed
    STA.w !Battle_ActorArcSpeed,X
    STA.w !Battle_ActorArcSpeed0,Y
    TDC
    STZ.w !Battle_ActorArcSpeed+2,X
    STA.w !Battle_ActorOfsX,Y
    STA.w !Battle_ActorOfsY,Y
    STZ.w !Battle_ActorArcHeight,X
    STZ.w !Battle_ActorArcHeight+2,X
    STA.w !Battle_ActorArcFalling,Y
    SEP #$20
    JMP .done
.target_set:
    JMP .done
.object:
    LDX.w !Battle_ActObjThread
    TXA
    TXY
    ASL A
    TAX
    LDA.w !Battle_ActObjX,X
    STA.b !Battle_GeoOriginX
    STA.w !Battle_ActorFromX+!Battle_NumSlots,Y
    LDA.w !Battle_ActObjY,X
    STA.b !Battle_GeoOriginY
    STA.w !Battle_ActorFromY+!Battle_NumSlots,Y
    LDA.w !Battle_ActCalcOutA
    STA.b !Battle_GeoPointX
    LDA.w !Battle_ActCalcOutB
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle
    JSR BattleAct_CalcMidpointSteps
    LDY.w !Battle_ActObjThread
    LDA.w !Battle_ActMoveUnitX
    STA.b !Battle_MulFactor16
    LDA.w !Battle_ActMoveUnitX+1
    STA.b !Battle_MulFactor16+1
    LDA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,Y
    STA.b !Battle_MulFactor8
    JSR Battle_Mul8x16
    LDX.b !Battle_MulProduct
    STX.w !Battle_ActMoveUnitX
    LDA.w !Battle_ActMoveUnitY
    STA.b !Battle_MulFactor16
    LDA.w !Battle_ActMoveUnitY+1
    STA.b !Battle_MulFactor16+1
    LDA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,Y
    STA.b !Battle_MulFactor8
    JSR Battle_Mul8x16
    LDX.b !Battle_MulProduct
    STX.w !Battle_ActMoveUnitY
    LDA.w !Battle_ActObjThread
    ASL A
    TAX
    STZ.w !Battle_ActorArcMode+(2*!Battle_NumSlots),X
    STZ.w !Battle_ActorArcMode+(2*!Battle_NumSlots)+1,X
    LDX.w #!Battle_ArcSpeedHalf
    STX.b !Battle_DivDividend
    LDA.b #!Battle_Kind4AccelDiv
    STA.b !Battle_DivDivisor
    JSR Battle_Divide
    LDY.w !Battle_ActObjThread
    LDA.b !Battle_GeoAngle
    STA.w !Battle_ActObjMoveAngle,Y
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battle_ActObjFacing,Y
    LDA.w !Battle_ActCalcOutA
    STA.w !Battle_ActorToX+!Battle_NumSlots,Y
    LDA.w !Battle_ActCalcOutB
    STA.w !Battle_ActorToY+!Battle_NumSlots,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer+!Battle_NumSlots,Y
    LDA.b #!Battle_MoveKindUnk4
    STA.w !Battle_ActorMoveKind+!Battle_NumSlots,Y
    TDC
    STA.w !Battle_ActObjMoveDone,Y
    STA.w !Battle_ActorUnkAB00+!Battle_NumSlots,Y
    TYA
    ASL A
    TAY                             ; j * 2
    ASL A
    TAX                             ; j * 4
    REP #$20
    LDA.w !Battle_ActMoveUnitX
    STA.w !Battle_ActorStepX+(2*!Battle_NumSlots),Y
    LDA.w !Battle_ActMoveUnitY
    STA.w !Battle_ActorStepY+(2*!Battle_NumSlots),Y
    LDA.b !Battle_DivQuotient
    STA.w !Battle_ActorArcAccel+(2*!Battle_NumSlots),Y
    LDA.b !Battle_DivDividend           ; the start speed
    STA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),X
    STA.w !Battle_ActorArcSpeed0+(2*!Battle_NumSlots),Y
    TDC
    STZ.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots)+2,X
    STA.w !Battle_ActorOfsX+(2*!Battle_NumSlots),Y
    STA.w !Battle_ActorOfsY+(2*!Battle_NumSlots),Y
    STZ.w !Battle_ActorArcHeight+(4*!Battle_NumSlots),X
    STZ.w !Battle_ActorArcHeight+(4*!Battle_NumSlots)+2,X
    STA.w !Battle_ActorArcFalling+(2*!Battle_NumSlots),Y
    SEP #$20
.done:
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpMoveToMidpoint ($C1720E–$C17348, 315 bytes)
; ==================================================================
; Opcode $D3: sets up, without starting it, a straight move of the
; thread's actor to the raised midpoint opcode $D2 left
; (!Battle_ActUnkMidX/Y, copied to !Battle_ActCalcOutA/B); length 1;
; it advances at once. Like opcode $D2 it leaves !Battle_ActorMoving
; 0, so opcode $D4, $D5 or $D6 starts it. Then .split_delay compares
; the move's step count s (!Battle_MoveMajorDist / the actor's
; !Battle_ActorMoveSpeed) with the 16-bit !Battle_ActUnkAAFC (opcode
; $D2's !Battle_ActUnkAAFCStart): when AAFC >= s, the 16-bit
; !Battle_MoveMajorDist = AAFC - s and AAFC = 0; else AAFC = s - AAFC
; and !Battle_MoveMajorDist = 0. Opcodes $D4 and $D5 wait those
; frames before they start the move, so one of the two waits the
; difference (probably to time two actors' moves against each other;
; not traced). By thread:
;   - threads 0-7 other than 4, the thread's battler:
;     BattleAct_StartBattlerMove, then !Battle_ActorMoving cleared;
;   - thread 4: nothing (no split either);
;   - threads 8-15, object j: what BattleAct_StartBattlerMove does,
;     from !Battle_ActObjX/Y with the object's entries of the actor
;     arrays (index 11 + j, the word arrays 22 + 2j), the angle also in
;     !Battle_ActObjMoveAngle and !Battle_ActObjUnkA5B5, the facing in
;     !Battle_ActObjFacing, !Battle_ActObjUnkA31C zeroed, and
;     !Battle_ActorMoving not set. Quirk, kept: the split divides by
;     !Battle_ActorMoveSpeed + 11 indexed by 2j (the X left from the
;     word stores), not by the object's own speed.
; Callers: BattleAct_OpcodeTable entry $D3.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered;
;        !Battle_ActCalcOutA/B = the midpoint; the move's state as
;        above; BattleAct_StartBattlerMove's (or the angle's,
;        BattleAct_CalcMoveStep's, multiply's) and the divide's DP
;        scratch
; Callees: BattleAct_StartBattlerMove, Battle_CalcAngle,
;          BattleAct_CalcMoveStep, Battle_Divide, Battle_Mul8x16,
;          BattleAct_AdvanceScript (JMP)
BattleAct_OpMoveToMidpoint:
    LDA.w !Battle_ActUnkMidX
    STA.w !Battle_ActCalcOutA
    LDA.w !Battle_ActUnkMidY
    STA.w !Battle_ActCalcOutB
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    JMP .object
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BNE .one_battler
    JMP .target_set
.one_battler:
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    PHX
    JSR BattleAct_StartBattlerMove
    PLX
    STZ.w !Battle_ActorMoving,X
    LDA.w !Battle_ActorMoveSpeed,X
    JSR .split_delay
    JMP .done
.target_set:
    JMP .done
.object:
    LDX.w !Battle_ActObjThread
    TXA
    ASL A
    TAX
    LDA.w !Battle_ActObjX,X
    STA.b !Battle_GeoOriginX
    LDA.w !Battle_ActObjY,X
    STA.b !Battle_GeoOriginY
    LDA.w !Battle_ActCalcOutA
    STA.b !Battle_GeoPointX
    LDA.w !Battle_ActCalcOutB
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle
    JSR BattleAct_CalcMoveStep
    LDY.w !Battle_ActObjThread
    LDA.b !BattleAct_MoveYMajor
    BNE .y_major
    LDA.b !Battle_GeoAbsDeltaX
    STA.b !Battle_DivDividend
    STZ.b !Battle_DivDividend+1
    BRA .steps
.y_major:
    LDA.b !Battle_GeoAbsDeltaY
    STA.b !Battle_DivDividend
    STZ.b !Battle_DivDividend+1
.steps:
    LDA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,Y
    STA.b !Battle_DivDivisor
    JSR Battle_Divide
    LDA.b !Battle_DivQuotient
    STA.w !Battle_ActorMoveSteps+!Battle_NumSlots,Y
    LDA.w !Battle_ActMoveUnitX
    STA.b !Battle_MulFactor16
    LDA.w !Battle_ActMoveUnitX+1
    STA.b !Battle_MulFactor16+1
    LDA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,Y
    STA.b !Battle_MulFactor8
    JSR Battle_Mul8x16
    LDX.b !Battle_MulProduct
    STX.w !Battle_ActMoveUnitX
    LDA.w !Battle_ActMoveUnitY
    STA.b !Battle_MulFactor16
    LDA.w !Battle_ActMoveUnitY+1
    STA.b !Battle_MulFactor16+1
    LDA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,Y
    STA.b !Battle_MulFactor8
    JSR Battle_Mul8x16
    LDX.b !Battle_MulProduct
    STX.w !Battle_ActMoveUnitY
    LDY.w !Battle_ActObjThread
    LDA.b !Battle_GeoAngle
    STA.w !Battle_ActObjMoveAngle,Y
    STA.w !Battle_ActObjUnkA5B5,Y
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battle_ActObjFacing,Y
    LDA.w !Battle_ActCalcOutA
    STA.w !Battle_ActorToX+!Battle_NumSlots,Y
    LDA.w !Battle_ActCalcOutB
    STA.w !Battle_ActorToY+!Battle_NumSlots,Y
    LDA.b #1
    STA.w !Battle_ActorMoveTimer+!Battle_NumSlots,Y
    TDC                             ; kind 0: straight
    STA.w !Battle_ActorMoveKind+!Battle_NumSlots,Y
    STA.w !Battle_ActObjUnkA31C,Y
    STA.w !Battle_ActObjMoveDone,Y
    TYA
    ASL A
    TAX                             ; j * 2
    LDA.w !Battle_ActObjX,X
    STA.w !Battle_ActorFromX+!Battle_NumSlots,Y
    LDA.w !Battle_ActObjY,X
    STA.w !Battle_ActorFromY+!Battle_NumSlots,Y
    REP #$20
    LDA.w !Battle_ActMoveUnitX
    STA.w !Battle_ActorStepX+(2*!Battle_NumSlots),X
    LDA.w !Battle_ActMoveUnitY
    STA.w !Battle_ActorStepY+(2*!Battle_NumSlots),X
    TDC
    STA.w !Battle_ActorOfsX+(2*!Battle_NumSlots),X
    STA.w !Battle_ActorOfsY+(2*!Battle_NumSlots),X
    SEP #$20
    LDA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,X ; quirk: X = j * 2
    JSR .split_delay
.done:
    LDA.b #1
    JMP BattleAct_AdvanceScript

.split_delay:
    STA.b !Battle_DivDivisor
    LDA.w !Battle_MoveMajorDist
    STA.b !Battle_DivDividend
    STZ.b !Battle_DivDividend+1
    JSR Battle_Divide
    LDX.b !Battle_DivQuotient
    STX.w !Battle_MoveMajorDist     ; s, 16-bit
    REP #$20
    SEC
    LDA.w !Battle_ActUnkAAFC        ; with !Battle_ActUnkAAFD
    SBC.w !Battle_MoveMajorDist
    BCS .aafc_longer
    SEC
    LDA.w !Battle_MoveMajorDist
    SBC.w !Battle_ActUnkAAFC
    STA.w !Battle_ActUnkAAFC
    TDC
    STA.w !Battle_MoveMajorDist
    BRA .split_done
.aafc_longer:
    STA.w !Battle_MoveMajorDist
    TDC
    STA.w !Battle_ActUnkAAFC
.split_done:
    SEP #$20
    RTS

; ==================================================================
; BattleAct_OpRunMoveAfterUnkAAFC ($C17349–$C173AC, 100 bytes, with
; BattleAct_OpRunMove)
; ==================================================================
; Opcode $D4: waits (advance 0) while the 16-bit !Battle_ActUnkAAFC
; (with !Battle_ActUnkAAFD) is not 0, counting it down by 1 a frame;
; at 0 it goes on as opcode $D6.
; Opcode $D6 (BattleAct_OpRunMove): runs the move opcode $D2 or $D3 set
; up: sets the actor's !Battle_ActorMoving to 1 every frame and waits
; until its done flag, then clears !Battle_ActorMoving and the done
; flag and advances by 1 (both opcodes have length 1). By thread:
;   - threads 0-7 other than 4, the thread's battler, !Battler_MoveDone;
;   - thread 4: advances at once (after $D4's count);
;   - threads 8-15, object j: entry 11 + j, !Battle_ActObjMoveDone.
; Clearing the done flag lets a later $D6 run the same move on (the
; kind-4 mover of opcode $D2 sets it at the top of the rise and again
; at the end). BattleAct_OpRunMove_Wait and BattleAct_OpRunMove_Done
; are the shared exits (advance 0 / 1), global only because the
; opcode $D4 part branches to them.
; Callers: BattleAct_OpcodeTable entries $D4 and $D6 (BattleAct_OpRunMove).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X clobbered (battlers and
;        objects); Y unchanged
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpRunMoveAfterUnkAAFC:
    LDA.w !Battle_ActUnkAAFC
    ORA.w !Battle_ActUnkAAFD
    BEQ BattleAct_OpRunMove
    SEC
    LDA.w !Battle_ActUnkAAFC
    SBC.b #1
    STA.w !Battle_ActUnkAAFC
    LDA.w !Battle_ActUnkAAFD
    SBC.b #0
    STA.w !Battle_ActUnkAAFD
    BRA BattleAct_OpRunMove_Wait

BattleAct_OpRunMove:                    ; header: see BattleAct_OpRunMoveAfterUnkAAFC
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    BRA .object
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BNE .one_battler
    BRA .target_set
.one_battler:
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.b #1
    STA.w !Battle_ActorMoving,X
    LDA.w !Battler_MoveDone,X
    BEQ .battler_wait
    STZ.w !Battle_ActorMoving,X
    STZ.w !Battler_MoveDone,X
    BRA BattleAct_OpRunMove_Done
.battler_wait:
    BRA BattleAct_OpRunMove_Wait
.target_set:
    BRA BattleAct_OpRunMove_Done
.object:
    LDX.w !Battle_ActObjThread
    LDA.b #1
    STA.w !Battle_ActorMoving+!Battle_NumSlots,X
    LDA.w !Battle_ActObjMoveDone,X
    BEQ BattleAct_OpRunMove_Wait
    STZ.w !Battle_ActorMoving+!Battle_NumSlots,X
    STZ.w !Battle_ActObjMoveDone,X
    BRA BattleAct_OpRunMove_Done
BattleAct_OpRunMove_Wait:               ; header: see BattleAct_OpRunMoveAfterUnkAAFC
    LDA.b #0
    JMP BattleAct_AdvanceScript     ; by 0: same opcode next frame
BattleAct_OpRunMove_Done:               ; header: see BattleAct_OpRunMoveAfterUnkAAFC
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpRunMoveAfterMajorDist ($C173AD–$C1740A, 94 bytes)
; ==================================================================
; Opcode $D5: opcode $D4 (BattleAct_OpRunMoveAfterUnkAAFC) with the
; other delay opcode $D3 leaves: waits while the 16-bit
; !Battle_MoveMajorDist is not 0, counting it down by 1 a frame; then
; sets the actor's !Battle_ActorMoving to 1 every frame and waits for
; its done flag, then clears !Battle_ActorMoving and advances by 1.
; Unlike opcode $D6 it leaves the done flag set. Threads as in
; BattleAct_OpRunMoveAfterUnkAAFC.
; Callers: BattleAct_OpcodeTable entry $D5.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X clobbered (battlers and
;        objects); Y unchanged
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpRunMoveAfterMajorDist:
    LDA.w !Battle_MoveMajorDist
    ORA.w !Battle_MoveMajorDist+1
    BEQ .run
    SEC
    LDA.w !Battle_MoveMajorDist
    SBC.b #1
    STA.w !Battle_MoveMajorDist
    LDA.w !Battle_MoveMajorDist+1
    SBC.b #0
    STA.w !Battle_MoveMajorDist+1
    BRA .wait
.run:
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    BRA .object
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BNE .one_battler
    BRA .target_set
.one_battler:
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.b #1
    STA.w !Battle_ActorMoving,X
    LDA.w !Battler_MoveDone,X
    BEQ .battler_wait
    STZ.w !Battle_ActorMoving,X
    BRA .done
.battler_wait:
    BRA .wait
.target_set:
    BRA .done
.object:
    LDX.w !Battle_ActObjThread
    LDA.b #1
    STA.w !Battle_ActorMoving+!Battle_NumSlots,X
    LDA.w !Battle_ActObjMoveDone,X
    BEQ .wait
    STZ.w !Battle_ActorMoving+!Battle_NumSlots,X
    BRA .done
.wait:
    LDA.b #0
    JMP BattleAct_AdvanceScript     ; by 0: same opcode next frame
.done:
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpPointTowardCalc ($C1740B–$C174B3, 169 bytes)
; ==================================================================
; Opcode $D7 <d> <n>: sets !Battle_ActUnkPointX/Y to the point d
; pixels (along the major axis) from the thread's actor towards the
; point left by BattleAct_RunCalc handler n: .along adds the unit step
; of BattleAct_CalcMoveStep (signed 8.8) d times and adds the whole
; pixels to the actor's position. When d is not below the major
; distance (the point is reached or passed) it sets the point to
; (0, 0) instead (what that means to the readers is not traced).
; Quirk, kept: d = 0 with the points apart counts the loop down from 0,
; so it adds the step 256 times. Length 3. By thread: the battler at
; !Battler_ScreenX/Y; thread 4 nothing; object j from
; !Battle_ActObjX/Y.
; Callers: BattleAct_OpcodeTable entry $D7.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered;
;        !Battle_ActCalcOutA/B = the point; DP $8E = 0 after the loop
;        (d otherwise); DP $80-$83 and BattleAct_CalcMoveStep's DP
;        written
; Callees: BattleAct_RunCalc, BattleAct_CalcMoveStep,
;          BattleAct_AdvanceScript (JMP)
!BattleAct_AlongDist = !BattleTmp_8E    ; 1 B: d (the loop's count)
!BattleAct_AlongX = !BattleTmp_80       ; 2 B: sum of the x steps, 8.8 (overlaps CalcMoveStep's $82/$83 after)
!BattleAct_AlongY = !BattleTmp_82       ; 2 B: sum of the y steps
BattleAct_OpPointTowardCalc:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    PHA
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    JSR BattleAct_RunCalc
    PLA
    STA.b !BattleAct_AlongDist
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    JMP .object
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BNE .one_battler
    JMP .target_set
.one_battler:
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.w !Battler_ScreenX,X
    STA.b !Battle_GeoOriginX
    LDA.w !Battler_ScreenY,X
    STA.b !Battle_GeoOriginY
    LDA.w !Battle_ActCalcOutA
    STA.b !Battle_GeoPointX
    LDA.w !Battle_ActCalcOutB
    STA.b !Battle_GeoPointY
    JSR .along
.target_set:
    BRA .done
.object:
    LDA.w !Battle_ActObjThread
    ASL A
    TAX
    LDA.w !Battle_ActObjX,X
    STA.b !Battle_GeoOriginX
    LDA.w !Battle_ActObjY,X
    STA.b !Battle_GeoOriginY
    LDA.w !Battle_ActCalcOutA
    STA.b !Battle_GeoPointX
    LDA.w !Battle_ActCalcOutB
    STA.b !Battle_GeoPointY
    JSR .along
.done:
    LDA.b #3
    JMP BattleAct_AdvanceScript

.along:
    JSR BattleAct_CalcMoveStep
    LDA.b !BattleAct_MoveYMajor
    BNE .y_major
    LDA.b !BattleAct_AlongDist
    CMP.b !Battle_GeoAbsDeltaX
    BCS .reached
    BRA .sum
.y_major:
    LDA.b !BattleAct_AlongDist
    CMP.b !Battle_GeoAbsDeltaY
    BCC .sum
.reached:
    STZ.w !Battle_ActUnkPointX
    STZ.w !Battle_ActUnkPointY
    BRA .exit
.sum:
    TDC
    TAX
    STX.b !BattleAct_AlongX
    STX.b !BattleAct_AlongY
.step:
    REP #$21
    LDA.w !Battle_ActMoveUnitX
    ADC.b !BattleAct_AlongX
    STA.b !BattleAct_AlongX
    CLC
    LDA.w !Battle_ActMoveUnitY
    ADC.b !BattleAct_AlongY
    STA.b !BattleAct_AlongY
    TDC
    SEP #$20
    DEC.b !BattleAct_AlongDist
    BNE .step
    CLC
    LDA.b !Battle_GeoOriginX
    ADC.b !BattleAct_AlongX+1
    STA.w !Battle_ActUnkPointX
    CLC
    LDA.b !Battle_GeoOriginY
    ADC.b !BattleAct_AlongY+1
    STA.w !Battle_ActUnkPointY
.exit:
    RTS

; ==================================================================
; BattleAct_OpShake ($C174B4–$C17539, 134 bytes)
; ==================================================================
; Opcode $D8 <a> <p> <f>: starts mover kind !Battle_MoveKindShake
; ($CF:F39F, unmatched) for the thread's battler and advances at once
; (length 4): !Battler_ShakeAmp = a, !Battler_ShakePeriod = p,
; !Battler_ShakeFrames = f + 1, !Battler_ShakeTimer and
; !Battler_ShakeOff = 1, !Battle_ActorMoveDelay and
; !Battle_ActorMoveTimer = 1 (the mover runs every frame) and
; !Battle_ActorMoving = 1. The mover (read, not matched) toggles the
; offset (!Battler_UnkA4A4/A4AF) between 0 and a pixels along
; !Battle_ActorUnkA5AA every p frames and ends the move itself (offset
; and !Battle_ActorMoving zeroed) after f frames, so probably a shake
; or vibration. Thread 4 does this for every slot of
; !Battle_ActTargetSet; threads 8-15 do nothing.
; Callers: BattleAct_OpcodeTable entry $D8.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered; DP $80, $82,
;        $84 = a, p, f + 1
; Callees: BattleAct_AdvanceScript (JMP)
!BattleAct_ShakeAmp = !BattleTmp_80     ; 1 B: a
!BattleAct_ShakePeriod = !BattleTmp_82  ; 1 B: p
!BattleAct_ShakeFrames = !BattleTmp_84  ; 1 B: f + 1
BattleAct_OpShake:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_ShakeAmp
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_ShakePeriod
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    INC A
    STA.b !BattleAct_ShakeFrames
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    JMP .done
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BNE .one_battler
    JMP .target_set
.one_battler:
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.b !BattleAct_ShakeAmp
    STA.w !Battler_ShakeAmp,X
    LDA.b !BattleAct_ShakePeriod
    STA.w !Battler_ShakePeriod,X
    LDA.b !BattleAct_ShakeFrames
    STA.w !Battler_ShakeFrames,X
    LDA.b #1
    STA.w !Battler_ShakeTimer,X
    STA.w !Battler_ShakeOff,X
    STA.w !Battle_ActorMoveDelay,X
    STA.w !Battle_ActorMoveTimer,X
    LDA.b #!Battle_MoveKindShake
    STA.w !Battle_ActorMoveKind,X
    LDA.b #1
    STA.w !Battle_ActorMoving,X
    BRA .done
.target_set:
    TDC
    TAY
.slot:
    LDA.w !Battle_ActTargetSet,Y
    BMI .done
    TAX
    LDA.b !BattleAct_ShakeAmp
    STA.w !Battler_ShakeAmp,X
    LDA.b !BattleAct_ShakePeriod
    STA.w !Battler_ShakePeriod,X
    LDA.b !BattleAct_ShakeFrames
    STA.w !Battler_ShakeFrames,X
    LDA.b #1
    STA.w !Battler_ShakeTimer,X
    STA.w !Battler_ShakeOff,X
    STA.w !Battle_ActorMoveDelay,X
    STA.w !Battle_ActorMoveTimer,X
    LDA.b #!Battle_MoveKindShake
    STA.w !Battle_ActorMoveKind,X
    LDA.b #1
    STA.w !Battle_ActorMoving,X
    INY
    BRA .slot
.done:
    LDA.b #4
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpSetActAttr ($C1753A–$C17578, 63 bytes)
; ==================================================================
; Opcode $D9 <v>: sets the thread's actor's attribute value to v
; (!Battler_ActAttr for a battler, every slot of !Battle_ActTargetSet
; for thread 4, !Battle_ActObjAttr for object j; probably sprite
; attribute bits, see the define); length 2.
; Callers: BattleAct_OpcodeTable entry $D9.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X clobbered; Y = 1 or (thread
;        4) clobbered; DP $80 = v
; Callees: BattleAct_AdvanceScript (JMP)
!BattleAct_AttrValue = !BattleTmp_80    ; 1 B: v
BattleAct_OpSetActAttr:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleAct_AttrValue
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    BRA .object
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BNE .one_battler
    BRA .target_set
.one_battler:
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.b !BattleAct_AttrValue
    STA.w !Battler_ActAttr,X
    BRA .done
.target_set:
    TDC
    TAX
.slot:
    LDA.w !Battle_ActTargetSet,X
    BMI .set_done
    TAY
    LDA.b !BattleAct_AttrValue
    STA.w !Battler_ActAttr,Y
    INX
    BRA .slot
.set_done:
    BRA .done
.object:
    LDX.w !Battle_ActObjThread
    LDA.b !BattleAct_AttrValue
    STA.w !Battle_ActObjAttr,X
.done:
    LDA.b #2
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_OpResetActAttr ($C17579–$C175BA, 66 bytes)
; ==================================================================
; Opcode $DA: puts the thread's actor's attribute value back to its
; initial one (!Battler_ActAttrInit into !Battler_ActAttr, for thread
; 4 every slot of !Battle_ActTargetSet, !Battle_ActObjAttrInit into
; !Battle_ActObjAttr for object j); length 1. Quirk, kept: it also
; reads the byte after the opcode into DP $80 and never uses it.
; Callers: BattleAct_OpcodeTable entry $DA.
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E, Y = 0, B = 0 (as from
;        BattleAct_RunThread)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X clobbered; Y = 1 or (thread
;        4) clobbered; DP $80 = the byte after the opcode
; Callees: BattleAct_AdvanceScript (JMP)
BattleAct_OpResetActAttr:
    INY
    LDA.b [!Battle_ActScriptPtr],Y
    STA.b !BattleTmp_80             ; not used
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCC .battler
    BRA .object
.battler:
    CMP.b #!Battle_ActTargetSetThread
    BNE .one_battler
    BRA .target_set
.one_battler:
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.w !Battler_ActAttrInit,X
    STA.w !Battler_ActAttr,X
    BRA .done
.target_set:
    TDC
    TAX
.slot:
    LDA.w !Battle_ActTargetSet,X
    BMI .set_done
    TAY
    LDA.w !Battler_ActAttrInit,Y
    STA.w !Battler_ActAttr,Y
    INX
    BRA .slot
.set_done:
    BRA .done
.object:
    LDX.w !Battle_ActObjThread
    LDA.w !Battle_ActObjAttrInit,X
    STA.w !Battle_ActObjAttr,X
.done:
    LDA.b #1
    JMP BattleAct_AdvanceScript

; ==================================================================
; BattleAct_AdvanceScript ($C175BB–$C175CB, 17 bytes)
; ==================================================================
; Moves the thread's script pointer !Battle_ActScriptPtr on by A bytes:
; a 16-bit add to the offset, with the carry going into the bank byte
; (added 16-bit, so DP $E9 takes part too). The opcode handlers end
; here with A = the length of their opcode, or 0 to run the same opcode
; again next frame.
; Callers (113 JMP sites): the opcode handlers, e.g. BattleAct_OpEndScript
;   ($C1:4CFD), BattleAct_OpLoopAnim ($C1:4E1E), BattleAct_OpPlayAnim
;   ($C1:4E4B), BattleAct_OpSetSpeed ($C1:4FBC) BattleAct_MoveToPoint ($C1:5129,
;   $C1:5132) and many in unmatched code ($C1:53A8 on).
; Entry: M=1, X=0, DP=0, DB=$7E; A = byte count, B = 0 (the add is
;        16-bit; the handlers come from BattleAct_RunThread's TDC)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0 (B too); X, Y unchanged;
;        DP $E6-$E9 written
org $C175BB
BattleAct_AdvanceScript:
    REP #$21                        ; 16-bit A, carry clear
    ADC.b !Battle_ActScriptPtr
    STA.b !Battle_ActScriptPtr
    LDA.b !Battle_ActScriptPtr+2
    ADC.w #0
    STA.b !Battle_ActScriptPtr+2
    TDC
    SEP #$20
    RTS

; ==================================================================
; Facing and point calculations ($C1:75CC–$C1:7A62)
; ==================================================================
; Two dispatchers with their handlers and tables. BattleAct_CalcFacing
; gives opcode $72 a facing (0-3, the !Battler_Facing values) for a
; mode; BattleAct_RunCalc gives the move, heading, sound and result
; opcodes and BattleAct_TickCalcs a point (x in !Battle_ActCalcOutA,
; y in !Battle_ActCalcOutB) for a handler number, mostly worked out
; from the screen positions of the entries of !Battle_ActBattlers
; (0 = caster, 1-2 = the two partners, 3 = the main target, 4 on = the
; target set). Neither dispatcher nor any handler checks an entry for
; the $FF end marker.

; ==================================================================
; BattleAct_CalcFacing ($C175CC–$C175D6, 11 bytes)
; ==================================================================
; Runs the BattleAct_FacingModeTable handler for mode A (0-$18), which
; leaves the facing in !Battle_ActFacingOut: modes 0-9 copy the facing
; of !Battle_ActBattlers entry A, $0A-$13 face entry A - $0A, $14-$17
; give facing A - $14, $18 faces the screen centre. The handler gets
; the mode in Y; the caller's X and Y come back.
; Callers (3 JSR sites): BattleAct_OpSetFacing ($C1:6001, $C1:6024,
;   $C1:6048).
; Entry: M=1, X=0, DP=0, DB=$7E, B=0 (the 16-bit TAY/TAX take B as the
;        mode's high byte); A = mode; DP $80/$81 = the actor's x/y
;        (read by modes $0A-$13 and $18)
; Exit:  M=1, X=0, DP=0, DB=$7E, B=0; X, Y unchanged; A = the facing;
;        !Battle_ActFacingOut written; modes $0A-$13 and $18 also write
;        !Battle_GeoOriginX/Y, !Battle_GeoPointX/Y and Battle_CalcAngle's
;        DP $D7-$E3
; Callees: the BattleAct_FacingModeTable handlers (JSR (table,X))
org $C175CC
BattleAct_CalcFacing:
    PHY
    PHX
    TAY
    ASL A
    TAX
    JSR (BattleAct_FacingModeTable,X)
    PLX
    PLY
    RTS

; ==================================================================
; BattleAct_FaceLikeEntry ($C175D7–$C175E2, 12 bytes)
; ==================================================================
; Facing modes 0-9: the !Battler_Facing of !Battle_ActBattlers entry Y.
; Callers: BattleAct_FacingModeTable entries 0-9 (BattleAct_CalcFacing).
; Entry: M=1, X=0, DP=0, DB=$7E, B=0; Y = mode (0-9)
; Exit:  M=1, X=0, DP=0, DB=$7E, B=0; A = the facing, also in
;        !Battle_ActFacingOut; X = the slot; Y unchanged
org $C175D7
BattleAct_FaceLikeEntry:
    TYX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.w !Battler_Facing,X
    STA.w !Battle_ActFacingOut
    RTS

; ==================================================================
; BattleAct_FaceTowardEntry ($C175E3–$C17609, 39 bytes)
; ==================================================================
; Facing modes $0A-$13: the facing from the actor's point (DP $80/$81)
; toward the screen position of !Battle_ActBattlers entry Y - $0A, from
; Battle_CalcAngle and !BattleRom_FacingByAngle.
; Callers: BattleAct_FacingModeTable entries $0A-$13
;   (BattleAct_CalcFacing).
; Entry: M=1, X=0, DP=0, DB=$7E, B=0; Y = mode ($0A-$13); DP $80/$81 =
;        the actor's x/y
; Exit:  M=1, X=0, DP=0, DB=$7E, B=0 (Battle_CalcAngle leaves it 0); A =
;        the facing, also in !Battle_ActFacingOut; X = the angle; Y
;        unchanged; !Battle_GeoOriginX/Y, !Battle_GeoPointX/Y and DP
;        $D7-$E3 written
; Callees: Battle_CalcAngle
org $C175E3
BattleAct_FaceTowardEntry:
    LDA.b !BattleTmp_80
    STA.b !Battle_GeoOriginX
    LDA.b !BattleTmp_81
    STA.b !Battle_GeoOriginY
    TYA
    SEC
    SBC.b #!BattleAct_FaceModeToward
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    LDA.w !Battler_ScreenX,X
    STA.b !Battle_GeoPointX
    LDA.w !Battler_ScreenY,X
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battle_ActFacingOut
    RTS

; ==================================================================
; BattleAct_FaceFixed ($C1760A–$C17611, 8 bytes)
; ==================================================================
; Facing modes $14-$17: facing Y - $14 (!Battle_FacingUp, Down, Left,
; Right).
; Callers: BattleAct_FacingModeTable entries $14-$17
;   (BattleAct_CalcFacing).
; Entry: M=1, X=0, DP=0, DB=$7E; Y = mode ($14-$17)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = the facing, also in
;        !Battle_ActFacingOut; X, Y unchanged
org $C1760A
BattleAct_FaceFixed:
    TYA
    SEC
    SBC.b #!BattleAct_FaceModeFixed
    STA.w !Battle_ActFacingOut
    RTS

; ==================================================================
; BattleAct_FaceTowardCentre ($C17612–$C1762D, 28 bytes)
; ==================================================================
; Facing mode $18: the facing from the actor's point (DP $80/$81)
; toward the middle of the screen (!Battle_ScreenCentreX/Y).
; Callers: BattleAct_FacingModeTable entry $18 (BattleAct_CalcFacing).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $80/$81 = the actor's x/y
; Exit:  M=1, X=0, DP=0, DB=$7E, B=0 (Battle_CalcAngle leaves it 0); A =
;        the facing, also in !Battle_ActFacingOut; X = the angle; Y
;        unchanged; !Battle_GeoOriginX/Y, !Battle_GeoPointX/Y and DP
;        $D7-$E3 written
; Callees: Battle_CalcAngle
org $C17612
BattleAct_FaceTowardCentre:
    LDA.b !BattleTmp_80
    STA.b !Battle_GeoOriginX
    LDA.b !BattleTmp_81
    STA.b !Battle_GeoOriginY
    LDA.b #!Battle_ScreenCentreX
    STA.b !Battle_GeoPointX
    LDA.b #!Battle_ScreenCentreY
    STA.b !Battle_GeoPointY
    JSR Battle_CalcAngle
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    STA.w !Battle_ActFacingOut
    RTS

; ==================================================================
; BattleAct_RunCalc ($C1762E–$C17638, 11 bytes)
; ==================================================================
; Runs the BattleAct_CalcTable handler for number A (0-$47), which
; leaves a point in !Battle_ActCalcOutA (x) and !Battle_ActCalcOutB (y)
; (two script variables for handlers $2A-$31; nothing for $12). The
; handler gets the number in Y; the caller's X and Y come back.
; Callers (16 JSR sites): BattleAct_TickCalcs ($C1:421E),
;   BattleAct_OpMoveToCalc ($C1:4FE6), BattleAct_OpCurveToCalc
;   ($C1:5224), BattleAct_OpPathToCalc ($C1:5430), BattleAct_OpSetPosCalc
;   ($C1:5680), BattleAct_OpCalcToUnkPoint ($C1:591D),
;   BattleAct_OpCalcToResult ($C1:59BC), BattleAct_OpOffsetToUnkPoint
;   ($C1:5A1F), BattleAct_OpHeadingFromCalc ($C1:60EF, $C1:6101),
;   BattleAct_OpSoundCalc ($C1:61CA), BattleAct_ArcToCalcDir ($C1:62A3),
;   BattleAct_OpCircleToCalc ($C1:6D09), BattleAct_OpEllipseToCalc
;   ($C1:6F69), BattleAct_OpMoveKind4ToCalc ($C1:705D) and
;   BattleAct_OpPointTowardCalc ($C1:7412).
; Entry: M=1, X=0, DP=0, DB=$7E, B=0 (the 16-bit TAY/TAX take B as the
;        number's high byte); A = handler number
; Exit:  M=1, X=0, DP=0, DB=$7E, B=0 (every handler leaves it 0); X, Y
;        unchanged; A clobbered; !Battle_ActCalcOutA/B written (16-bit,
;        $A2B0-$A2B3, by handler $17 for an object and by $1C-$23); DP
;        bytes the handler uses: at most $77/$78, $79-$7B, $80-$8B and
;        $A5-$B8 (see each handler)
; Callees: the BattleAct_CalcTable handlers (JSR (table,X))
org $C1762E
BattleAct_RunCalc:
    PHY
    PHX
    TAY
    ASL A
    TAX
    JSR (BattleAct_CalcTable,X)
    PLX
    PLY
    RTS

; ==================================================================
; BattleAct_CalcEntryPos ($C17639–$C17649, 17 bytes)
; ==================================================================
; Handlers 0-8: the screen position (!Battler_ScreenX/Y) of
; !Battle_ActBattlers entry Y.
; Callers: BattleAct_CalcTable entries 0-8 (BattleAct_RunCalc).
; Entry: M=1, X=0, DP=0, DB=$7E, B=0; Y = handler number (0-8)
; Exit:  M=1, X=0, DP=0, DB=$7E, B=0; A = the y; X = the slot; Y
;        unchanged; !Battle_ActCalcOutA/B written
org $C17639
BattleAct_CalcEntryPos:
    LDA.w !Battle_ActBattlers,Y
    TAX
    LDA.w !Battler_ScreenX,X
    STA.w !Battle_ActCalcOutA
    LDA.w !Battler_ScreenY,X
    STA.w !Battle_ActCalcOutB
    RTS

; ==================================================================
; BattleAct_CalcEntryOffsetPos ($C1764A–$C1767C, 51 bytes)
; ==================================================================
; Handlers 9-$11: the screen position of !Battle_ActBattlers entry Y - 9
; plus its !Battler_ScreenOffsetX/Y. The x sum wraps at 8 bits; the y
; offset is taken as signed and the sum is clamped to 0..$FF.
; Callers: BattleAct_CalcTable entries 9-$11 (BattleAct_RunCalc).
; Entry: M=1, X=0, DP=0, DB=$7E, B=0; Y = handler number (9-$11)
; Exit:  M=1, X=0, DP=0, DB=$7E, B=0; A = the y; X = the slot; Y = the
;        entry (handler - 9); !Battle_ActCalcOutA/B written
org $C1764A
BattleAct_CalcEntryOffsetPos:
    TYA
    SEC
    SBC.b #!BattleAct_CalcOffsetPos
    TAY
    LDA.w !Battle_ActBattlers,Y
    TAX
    CLC
    LDA.w !Battler_ScreenX,X
    ADC.w !Battler_ScreenOffsetX,X
    STA.w !Battle_ActCalcOutA
    LDA.w !Battler_ScreenOffsetY,X
    BPL .offset_down
    CLC
    LDA.w !Battler_ScreenY,X
    ADC.w !Battler_ScreenOffsetY,X
    BCS .store_y                        ; adding a negative byte: carry = no wrap below 0
    TDC
    BRA .store_y
.offset_down:
    CLC
    LDA.w !Battler_ScreenY,X
    ADC.w !Battler_ScreenOffsetY,X
    BCC .store_y
    LDA.b #!BattleAct_CalcYMax
.store_y:
    STA.w !Battle_ActCalcOutB
    RTS

; ==================================================================
; BattleAct_CalcNone ($C1767D, 1 byte)
; ==================================================================
; Handler $12: does nothing; !Battle_ActCalcOutA/B keep what the last
; handler left.
; Callers: BattleAct_CalcTable entry $12 (BattleAct_RunCalc).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y unchanged
org $C1767D
BattleAct_CalcNone:
    RTS

; ==================================================================
; BattleAct_CalcMid03 ($C1767E–$C17685, 8 bytes)
; ==================================================================
; Handler $13: the midpoint of !Battle_ActBattlers entries 0 and 3 (the
; caster and the main target), through BattleAct_CalcMid02's
; BattleAct_CalcMidWithEntry0.
; Callers: BattleAct_CalcTable entry $13 (BattleAct_RunCalc).
; Entry: M=1, X=0, DP=0, DB=$7E, B=0
; Exit:  as BattleAct_CalcMid02's: M=1, X=0, DP=0, DB=$7E, B=0; A = the
;        y; X, Y clobbered; DP $80-$87 written; !Battle_ActCalcOutA/B
;        written
; Callees: BattleAct_CalcMidWithEntry0 (JMP)
org $C1767E
BattleAct_CalcMid03:
    LDY.w #3
    STY.b !BattleTmp_84
    JMP BattleAct_CalcMidWithEntry0

; ==================================================================
; BattleAct_CalcMid01 ($C17686–$C1768D, 8 bytes)
; ==================================================================
; Handler $14: the midpoint of !Battle_ActBattlers entries 0 and 1,
; through BattleAct_CalcMid02's BattleAct_CalcMidWithEntry0.
; Callers: BattleAct_CalcTable entry $14 (BattleAct_RunCalc).
; Entry: M=1, X=0, DP=0, DB=$7E, B=0
; Exit:  M=1, X=0, DP=0, DB=$7E, B=0; A = the y; X, Y clobbered; DP
;        $80-$87 written; !Battle_ActCalcOutA/B written
; Callees: BattleAct_CalcMidWithEntry0 (JMP)
org $C17686
BattleAct_CalcMid01:
    LDY.w #1
    STY.b !BattleTmp_84
    JMP BattleAct_CalcMidWithEntry0

; ==================================================================
; BattleAct_CalcMid02 ($C1768E–$C176D7, 74 bytes)
; ==================================================================
; Handler $15: the midpoint of the screen positions of two battler
; slots, (x1 + x2) / 2 and (y1 + y2) / 2 worked out 16-bit. Three
; entries:
; - BattleAct_CalcMid02 (table entry $15): entries 0 and 2.
; - BattleAct_CalcMidWithEntry0 ($C1:7693): entry 0 and the entry in
;   DP $84 (BattleAct_CalcMid03 and BattleAct_CalcMid01 jump here).
; - BattleAct_CalcMidFromSlot ($C1:7697): slot X and the entry in DP $84
;   (BattleAct_CalcMid12 jumps here).
; Callers: BattleAct_CalcTable entry $15 (BattleAct_RunCalc);
;   BattleAct_CalcMid03 ($C1:7683) and BattleAct_CalcMid01 ($C1:768B)
;   JMP to BattleAct_CalcMidWithEntry0; BattleAct_CalcMid12 ($C1:791D)
;   to BattleAct_CalcMidFromSlot.
; Entry: M=1, X=0, DP=0, DB=$7E, B=0; BattleAct_CalcMidWithEntry0: DP
;        $84-$85 = the second entry; BattleAct_CalcMidFromSlot: also X =
;        the first battler slot
; Exit:  M=1, X=0, DP=0, DB=$7E, B=0; A = the y; X = the second slot; Y =
;        the second entry; DP $80-$87 written; !Battle_ActCalcOutA/B
;        written
!BattleAct_MidX1 = !BattleTmp_80        ; 2 B: first x, then the mean x
!BattleAct_MidY1 = !BattleTmp_82        ; 2 B: first y, then the mean y
!BattleAct_MidX2 = !BattleTmp_84        ; 2 B: on entry the second entry; then the second x
!BattleAct_MidY2 = !BattleTmp_86        ; 2 B: second y
org $C1768E
BattleAct_CalcMid02:
    LDY.w #2
    STY.b !BattleAct_MidX2
BattleAct_CalcMidWithEntry0:            ; header: see BattleAct_CalcMid02
    LDA.w !Battle_ActBattlers
    TAX
BattleAct_CalcMidFromSlot:              ; header: see BattleAct_CalcMid02
    LDA.w !Battler_ScreenX,X
    STA.b !BattleAct_MidX1
    STZ.b !BattleAct_MidX1+1
    LDA.w !Battler_ScreenY,X
    STA.b !BattleAct_MidY1
    STZ.b !BattleAct_MidY1+1
    LDY.b !BattleAct_MidX2
    LDA.w !Battle_ActBattlers,Y
    TAX
    LDA.w !Battler_ScreenX,X
    STA.b !BattleAct_MidX2
    STZ.b !BattleAct_MidX2+1
    LDA.w !Battler_ScreenY,X
    STA.b !BattleAct_MidY2
    STZ.b !BattleAct_MidY2+1
    REP #$21                            ; 16-bit A, carry clear
    LDA.b !BattleAct_MidX1
    ADC.b !BattleAct_MidX2
    LSR A
    STA.b !BattleAct_MidX1
    CLC
    LDA.b !BattleAct_MidY1
    ADC.b !BattleAct_MidY2
    LSR A
    STA.b !BattleAct_MidY1
    TDC
    SEP #$20
    LDA.b !BattleAct_MidX1
    STA.w !Battle_ActCalcOutA
    LDA.b !BattleAct_MidY1
    STA.w !Battle_ActCalcOutB
    RTS

; ==================================================================
; BattleAct_CalcCentroid ($C176D8–$C1774D, 118 bytes)
; ==================================================================
; Handler $16: meant as the centre of !Battle_ActBattlers entries 0-2
; (the caster and its two partners): sums the three screen x and the
; three screen y 16-bit and divides by 3 with Battle_Divide. Quirk: the
; second division divides the x sum again (DP $80/$81, not the y sum
; in $82/$83), so !Battle_ActCalcOutB gets the mean x as well; the y
; sum is never used.
; Callers: BattleAct_CalcTable entry $16 (BattleAct_RunCalc).
; Entry: M=1, X=0, DP=0, DB=$7E, B=0
; Exit:  M=1, X=0, DP=0, DB=$7E, B=0; A = the mean x; X = the slot of
;        entry 2; Y unchanged; DP $80-$8B, $B1-$B3 written and
;        Battle_Divide's $79-$7B and $B5-$B8; !Battle_ActCalcOutA/B
;        written
; Callees: Battle_Divide
!BattleAct_SumX = !BattleTmp_80         ; 2 B: x of entry 0, then the sum of the three
!BattleAct_SumY = !BattleTmp_82         ; 2 B: y of entry 0, then the sum
!BattleAct_X1 = !BattleTmp_84           ; 2 B: x of entry 1
!BattleAct_Y1 = !BattleTmp_86           ; 2 B: y of entry 1
!BattleAct_X2 = !BattleTmp_88           ; 2 B: x of entry 2
!BattleAct_Y2 = !BattleTmp_8A           ; 2 B: y of entry 2
org $C176D8
BattleAct_CalcCentroid:
    LDA.w !Battle_ActBattlers
    TAX
    LDA.w !Battler_ScreenX,X
    STA.b !BattleAct_SumX
    STZ.b !BattleAct_SumX+1
    LDA.w !Battler_ScreenY,X
    STA.b !BattleAct_SumY
    STZ.b !BattleAct_SumY+1
    LDA.w !Battle_ActBattlers+1
    TAX
    LDA.w !Battler_ScreenX,X
    STA.b !BattleAct_X1
    STZ.b !BattleAct_X1+1
    LDA.w !Battler_ScreenY,X
    STA.b !BattleAct_Y1
    STZ.b !BattleAct_Y1+1
    LDA.w !Battle_ActBattlers+2
    TAX
    LDA.w !Battler_ScreenX,X
    STA.b !BattleAct_X2
    STZ.b !BattleAct_X2+1
    LDA.w !Battler_ScreenY,X
    STA.b !BattleAct_Y2
    STZ.b !BattleAct_Y2+1
    REP #$21                            ; 16-bit A, carry clear
    LDA.b !BattleAct_SumX
    ADC.b !BattleAct_X1
    CLC
    ADC.b !BattleAct_X2
    STA.b !BattleAct_SumX
    LDA.b !BattleAct_SumY               ; no CLC: the x sum (at most $2FD) left carry clear
    ADC.b !BattleAct_Y1
    CLC
    ADC.b !BattleAct_Y2
    STA.b !BattleAct_SumY
    TDC
    SEP #$20
    LDA.b !BattleAct_SumX
    STA.b !Battle_DivDividend
    LDA.b !BattleAct_SumX+1
    STA.b !Battle_DivDividend+1
    LDA.b #3
    STA.b !Battle_DivDivisor
    JSR Battle_Divide
    LDA.b !Battle_DivQuotient
    STA.w !Battle_ActCalcOutA
    LDA.b !BattleAct_SumX               ; quirk: the x sum again, not !BattleAct_SumY
    STA.b !Battle_DivDividend
    LDA.b !BattleAct_SumX+1
    STA.b !Battle_DivDividend+1
    LDA.b #3
    STA.b !Battle_DivDivisor
    JSR Battle_Divide
    LDA.b !Battle_DivQuotient
    STA.w !Battle_ActCalcOutB
    RTS

; ==================================================================
; BattleAct_CalcAheadOfActor ($C1774E–$C177D0, 131 bytes)
; ==================================================================
; Handler $17: the point $18 pixels from the thread's actor along its
; move angle: y + the sine of the angle and x + the sine of the angle
; + $40, each from Battle_SinLookup with scale $18 (a signed byte).
; - Battler threads (0-7): the actor is the slot of !Battle_ActBattlers
;   entry (thread) (thread 4 gives the first slot of the target set),
;   its angle !Battle_ActorMoveAngle; the sums are 8-bit and wrap.
; - Object threads (8-15): object thread - 8, its angle
;   !Battle_ActObjMoveAngle; the sums are 16-bit with !Battle_ActObjX/Y
;   and stored 16-bit. Quirk: the sine bytes are zero-extended, not
;   sign-extended, so for a negative one the high bytes written to
;   $A2B1/$A2B3 come out one too high (the low bytes are right).
; Callers: BattleAct_CalcTable entry $17 (BattleAct_RunCalc).
; Entry: M=1, X=0, DP=0, DB=$7E, B=0
; Exit:  M=1, X=0, DP=0, DB=$7E, B=0; A = the x (battlers) or 0
;        (objects); X = the slot or the object * 2; Y unchanged; DP
;        $80-$83 (objects: $80-$85) and $AE written, and
;        Battle_SinLookup's $77/$78 and $A5-$AB; !Battle_ActCalcOutA/B
;        written (objects: $A2B0-$A2B3)
; Callees: Battle_SinLookup
!BattleAct_AheadActor = !BattleTmp_80   ; 2 B: the battler slot or object
!BattleAct_AheadDy = !BattleTmp_82      ; 1 B (objects: 2 B, high byte 0): the sine of the angle
!BattleAct_AheadDx = !BattleTmp_83      ; 1 B (battlers): the sine of the angle + $40
!BattleAct_AheadObjDx = !BattleTmp_84   ; 2 B (objects, high byte 0): the same
org $C1774E
BattleAct_CalcAheadOfActor:
    LDA.w !Battle_ActThread
    CMP.b #!Battle_ActFirstObjThread
    BCS .object
    TAX
    LDA.w !Battle_ActBattlers,X
    TAX
    STX.b !BattleAct_AheadActor
    LDA.b #!BattleAct_CalcAheadDist
    STA.b !Battle_SinScale
    LDA.w !Battle_ActorMoveAngle,X
    JSR Battle_SinLookup
    STA.b !BattleAct_AheadDy
    LDX.b !BattleAct_AheadActor
    LDA.b #!BattleAct_CalcAheadDist
    STA.b !Battle_SinScale
    CLC
    LDA.w !Battle_ActorMoveAngle,X
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup
    STA.b !BattleAct_AheadDx
    LDX.b !BattleAct_AheadActor
    CLC
    LDA.w !Battler_ScreenY,X
    ADC.b !BattleAct_AheadDy
    STA.w !Battle_ActCalcOutB
    CLC
    LDA.w !Battler_ScreenX,X
    ADC.b !BattleAct_AheadDx
    STA.w !Battle_ActCalcOutA
    BRA .done
.object:
    SEC
    SBC.b #!Battle_ActFirstObjThread
    TAX
    STX.b !BattleAct_AheadActor
    LDA.b #!BattleAct_CalcAheadDist
    STA.b !Battle_SinScale
    LDA.w !Battle_ActObjMoveAngle,X
    JSR Battle_SinLookup
    STA.b !BattleAct_AheadDy
    STZ.b !BattleAct_AheadDy+1          ; quirk: zero-extended
    LDX.b !BattleAct_AheadActor
    LDA.b #!BattleAct_CalcAheadDist
    STA.b !Battle_SinScale
    CLC
    LDA.w !Battle_ActObjMoveAngle,X
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookup
    STA.b !BattleAct_AheadObjDx
    STZ.b !BattleAct_AheadObjDx+1       ; quirk: zero-extended
    LDA.b !BattleAct_AheadActor
    ASL A
    TAX
    REP #$21                            ; 16-bit A, carry clear
    LDA.w !Battle_ActObjY,X
    ADC.b !BattleAct_AheadDy
    STA.w !Battle_ActCalcOutB
    CLC
    LDA.w !Battle_ActObjX,X
    ADC.b !BattleAct_AheadObjDx
    STA.w !Battle_ActCalcOutA
    TDC
    SEP #$20
.done:
    RTS

; ==================================================================
; BattleAct_CalcFixedPoint ($C177D1–$C177D9, 9 bytes)
; ==================================================================
; Handler $18: the point ($80, $80). The screen centre used elsewhere
; is ($80, $70) (!Battle_ScreenCentreX/Y), so what this point is meant
; to be is not known.
; Callers: BattleAct_CalcTable entry $18 (BattleAct_RunCalc).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A = $80; X, Y unchanged;
;        !Battle_ActCalcOutA/B written
org $C177D1
BattleAct_CalcFixedPoint:
    LDA.b #!BattleAct_CalcFixedXY
    STA.w !Battle_ActCalcOutA
    STA.w !Battle_ActCalcOutB
    RTS

; ==================================================================
; BattleAct_CalcSavedPos ($C177DA–$C177EB, 18 bytes)
; ==================================================================
; Handlers $19-$1B: the position saved for !Battle_ActBattlers entry
; Y - $19 (0-2) in !Battle_ActSavedX/Y.
; Callers: BattleAct_CalcTable entries $19-$1B (BattleAct_RunCalc).
; Entry: M=1, X=0, DP=0, DB=$7E, B=0; Y = handler number ($19-$1B)
; Exit:  M=1, X=0, DP=0, DB=$7E, B=0; A = the y; X = the entry; Y
;        unchanged; !Battle_ActCalcOutA/B written
org $C177DA
BattleAct_CalcSavedPos:
    TYA
    SEC
    SBC.b #!BattleAct_CalcSavedPos
    TAX
    LDA.w !Battle_ActSavedX,X
    STA.w !Battle_ActCalcOutA
    LDA.w !Battle_ActSavedY,X
    STA.w !Battle_ActCalcOutB
    RTS

; ==================================================================
; BattleAct_CalcObjOffset ($C177EC–$C1780A, 31 bytes)
; ==================================================================
; Handlers $1C-$23: the position of object Y - $1C (0-7) plus its
; !Battle_ActObjOfsX/Y, 16-bit, stored 16-bit.
; Callers: BattleAct_CalcTable entries $1C-$23 (BattleAct_RunCalc).
; Entry: M=1, X=0, DP=0, DB=$7E, B=0; Y = handler number ($1C-$23)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0 (B too); X = the object * 2; Y
;        unchanged; !Battle_ActCalcOutA/B written ($A2B0-$A2B3)
org $C177EC
BattleAct_CalcObjOffset:
    TYA
    SEC
    SBC.b #!BattleAct_CalcObjOffset
    ASL A
    TAX
    REP #$21                            ; 16-bit A, carry clear
    LDA.w !Battle_ActObjOfsX,X
    ADC.w !Battle_ActObjX,X
    STA.w !Battle_ActCalcOutA
    CLC
    LDA.w !Battle_ActObjOfsY,X
    ADC.w !Battle_ActObjY,X
    STA.w !Battle_ActCalcOutB
    TDC
    SEP #$20
    RTS

; ==================================================================
; BattleAct_CalcLerpToTarget ($C1780B–$C17900, 246 bytes)
; ==================================================================
; Handlers $24-$29 and $32-$3F: a point on the line from one battler to
; the main target (!Battle_ActMainTarget): (w1 * P + w2 * T) >> 3 per
; coordinate, with the weight pair (w1, w2) k of
; !BattleRom_ActLerpWeights (the pairs add up to 8, so k = 0-5 give 1/8,
; 2/8, 3/8, 5/8, 6/8, 7/8 of the way and k = 6 the midpoint). The
; products are 16-bit from Battle_Mul8; the result keeps the low byte.
; - $24-$29: from !Battle_ActBattlers entry 0 (the caster), k = n - $24.
; - $32-$38: from entry 1, k = n - $32.
; - $39-$3F: from entry 0, k = n - $39, with both points moved by their
;   !Battler_ScreenOffsetX/Y (x wrapping at 8 bits, y + offset clamped
;   to 0..$FF, as in BattleAct_CalcEntryOffsetPos).
; Callers: BattleAct_CalcTable entries $24-$29 and $32-$3F
;   (BattleAct_RunCalc).
; Entry: M=1, X=0, DP=0, DB=$7E, B=0; Y = handler number
; Exit:  M=1, X=0, DP=0, DB=$7E, B=0; A = the y; X = w1 * y1;
;        Y unchanged; DP $80-$85 and $AD/$AE written, and Battle_Mul8's
;        $77/$78 and $AF/$B0; !Battle_ActCalcOutA/B written
; Callees: Battle_Mul8, Battle_ShiftRight3
!BattleAct_LerpW1 = !BattleTmp_80       ; 1 B: weight of the first point
!BattleAct_LerpW2 = !BattleTmp_81       ; 1 B: weight of the target
!BattleAct_LerpSum = !BattleTmp_82      ; 2 B: on entry the first slot; then w1 * coordinate, then the result
!BattleAct_LerpY1 = !BattleTmp_84       ; 1 B: y of the first point
!BattleAct_LerpY2 = !BattleTmp_85       ; 1 B: y of the target
org $C1780B
BattleAct_CalcLerpToTarget:
    LDA.w !Battle_ActBattlers
    STA.b !BattleAct_LerpSum
    CPY.w #!BattleAct_CalcLerpEntry1
    BCC .from_caster
    CPY.w #!BattleAct_CalcLerpOffset
    BCC .from_entry1
    TYA
    SEC
    SBC.b #!BattleAct_CalcLerpOffset
    BRA .weights
.from_entry1:
    LDA.w !Battle_ActBattlers+1
    STA.b !BattleAct_LerpSum
    TYA
    SEC
    SBC.b #!BattleAct_CalcLerpEntry1
    BRA .weights
.from_caster:
    TYA
    SEC
    SBC.b #!BattleAct_CalcLerpCaster
.weights:
    ASL A
    TAX
    LDA.l !BattleRom_ActLerpWeights,X
    STA.b !BattleAct_LerpW1
    STA.b !Battle_Mul8B
    LDA.l !BattleRom_ActLerpWeights+1,X
    STA.b !BattleAct_LerpW2
    LDA.b !BattleAct_LerpSum
    TAX
    CPY.w #!BattleAct_CalcLerpOffset
    BCC .first_plain
    CLC
    LDA.w !Battler_ScreenX,X
    ADC.w !Battler_ScreenOffsetX,X
    STA.b !Battle_Mul8A
    LDA.w !Battler_ScreenOffsetY,X
    BPL .first_down
    CLC
    LDA.w !Battler_ScreenY,X
    ADC.w !Battler_ScreenOffsetY,X
    BCS .first_y
    TDC
    BRA .first_y
.first_down:
    CLC
    LDA.w !Battler_ScreenY,X
    ADC.w !Battler_ScreenOffsetY,X
    BCC .first_y
    LDA.b #!BattleAct_CalcYMax
    BRA .first_y
.first_plain:
    LDA.w !Battler_ScreenX,X
    STA.b !Battle_Mul8A
    LDA.w !Battler_ScreenY,X
.first_y:
    STA.b !BattleAct_LerpY1
    JSR Battle_Mul8                     ; w1 * x1
    LDX.b !Battle_Mul8Product
    STX.b !BattleAct_LerpSum
    LDA.w !Battle_ActMainTarget
    TAX
    CPY.w #!BattleAct_CalcLerpOffset
    BCC .target_plain
    CLC
    LDA.w !Battler_ScreenX,X
    ADC.w !Battler_ScreenOffsetX,X
    STA.b !Battle_Mul8A
    LDA.w !Battler_ScreenOffsetY,X
    BPL .target_down
    CLC
    LDA.w !Battler_ScreenY,X
    ADC.w !Battler_ScreenOffsetY,X
    BCS .target_y
    TDC
    BRA .target_y
.target_down:
    CLC
    LDA.w !Battler_ScreenY,X
    ADC.w !Battler_ScreenOffsetY,X
    BCC .target_y
    LDA.b #!BattleAct_CalcYMax
    BRA .target_y
.target_plain:
    LDA.w !Battler_ScreenX,X
    STA.b !Battle_Mul8A
    LDA.w !Battler_ScreenY,X
.target_y:
    STA.b !BattleAct_LerpY2
    LDA.b !BattleAct_LerpW2
    STA.b !Battle_Mul8B
    JSR Battle_Mul8                     ; w2 * x2
    REP #$21                            ; 16-bit A, carry clear
    LDA.b !Battle_Mul8Product
    ADC.b !BattleAct_LerpSum
    JSR Battle_ShiftRight3
    STA.b !BattleAct_LerpSum
    TDC
    SEP #$20
    LDA.b !BattleAct_LerpSum
    STA.w !Battle_ActCalcOutA
    LDA.b !BattleAct_LerpY1
    STA.b !Battle_Mul8A
    LDA.b !BattleAct_LerpW1
    STA.b !Battle_Mul8B
    JSR Battle_Mul8                     ; w1 * y1
    LDX.b !Battle_Mul8Product
    STX.b !BattleAct_LerpSum
    LDA.b !BattleAct_LerpY2
    STA.b !Battle_Mul8A
    LDA.b !BattleAct_LerpW2
    STA.b !Battle_Mul8B
    JSR Battle_Mul8                     ; w2 * y2
    REP #$21                            ; 16-bit A, carry clear
    LDA.b !Battle_Mul8Product
    ADC.b !BattleAct_LerpSum
    JSR Battle_ShiftRight3
    STA.b !BattleAct_LerpSum
    TDC
    SEP #$20
    LDA.b !BattleAct_LerpSum
    STA.w !Battle_ActCalcOutB
    RTS

; ==================================================================
; BattleAct_CalcVarPair ($C17901–$C17913, 19 bytes)
; ==================================================================
; Handlers $2A-$31: script variables 2k and 2k + 1 of !Battle_ActVars,
; k = n - $2A (0-7), as the pair (not necessarily a point).
; Callers: BattleAct_CalcTable entries $2A-$31 (BattleAct_RunCalc).
; Entry: M=1, X=0, DP=0, DB=$7E, B=0; Y = handler number ($2A-$31)
; Exit:  M=1, X=0, DP=0, DB=$7E, B=0; A = variable 2k + 1; X = 2k; Y
;        unchanged; !Battle_ActCalcOutA/B written
org $C17901
BattleAct_CalcVarPair:
    TYA
    SEC
    SBC.b #!BattleAct_CalcVarPair
    ASL A
    TAX
    LDA.w !Battle_ActVars,X
    STA.w !Battle_ActCalcOutA
    LDA.w !Battle_ActVars+1,X
    STA.w !Battle_ActCalcOutB
    RTS

; ==================================================================
; BattleAct_CalcMid12 ($C17914–$C1791F, 12 bytes)
; ==================================================================
; Handler $40: the midpoint of !Battle_ActBattlers entries 1 and 2 (the
; two partners), through BattleAct_CalcMid02's
; BattleAct_CalcMidFromSlot.
; Callers: BattleAct_CalcTable entry $40 (BattleAct_RunCalc).
; Entry: M=1, X=0, DP=0, DB=$7E, B=0
; Exit:  M=1, X=0, DP=0, DB=$7E, B=0; A = the y; X, Y clobbered; DP
;        $80-$87 written; !Battle_ActCalcOutA/B written
; Callees: BattleAct_CalcMidFromSlot (JMP)
org $C17914
BattleAct_CalcMid12:
    LDY.w #2
    STY.b !BattleTmp_84
    LDA.w !Battle_ActBattlers+1
    TAX
    JMP BattleAct_CalcMidFromSlot

; ==================================================================
; BattleAct_CalcLerpToObj0 ($C17920–$C179A0, 129 bytes)
; ==================================================================
; Handlers $41-$47: a point on the line from !Battle_ActBattlers entry
; 0 (the caster) to object 0 (the low bytes of !Battle_ActObjX/Y),
; (w1 * P + w2 * O) >> 3 with weight pair n - $41 of
; !BattleRom_ActLerpWeights, as in BattleAct_CalcLerpToTarget. It saves
; DP $86-$87 on the stack and puts it back at the end, though nothing in
; it writes there (probably left over).
; Callers: BattleAct_CalcTable entries $41-$47 (BattleAct_RunCalc).
; Entry: M=1, X=0, DP=0, DB=$7E, B=0; Y = handler number ($41-$47)
; Exit:  M=1, X=0, DP=0, DB=$7E, B=0; A = the y; X = DP $86-$87 (kept);
;        Y unchanged; DP $80-$85 and $AD/$AE written, and Battle_Mul8's
;        $77/$78 and $AF/$B0; !Battle_ActCalcOutA/B written
; Callees: Battle_Mul8, Battle_ShiftRight3
org $C17920
BattleAct_CalcLerpToObj0:
    LDX.b !BattleTmp_86
    PHX
    TYA
    SEC
    SBC.b #!BattleAct_CalcLerpObj0
    ASL A
    TAX
    LDA.l !BattleRom_ActLerpWeights,X
    STA.b !BattleAct_LerpW1
    STA.b !Battle_Mul8B
    LDA.l !BattleRom_ActLerpWeights+1,X
    STA.b !BattleAct_LerpW2
    LDA.w !Battle_ActBattlers
    TAX
    LDA.w !Battler_ScreenX,X
    STA.b !Battle_Mul8A
    LDA.w !Battler_ScreenY,X
    STA.b !BattleAct_LerpY1
    JSR Battle_Mul8                     ; w1 * x1
    LDX.b !Battle_Mul8Product
    STX.b !BattleAct_LerpSum
    LDA.w !Battle_ActObjX
    STA.b !Battle_Mul8A
    LDA.w !Battle_ActObjY
    STA.b !BattleAct_LerpY2
    LDA.b !BattleAct_LerpW2
    STA.b !Battle_Mul8B
    JSR Battle_Mul8                     ; w2 * x2
    REP #$21                            ; 16-bit A, carry clear
    LDA.b !Battle_Mul8Product
    ADC.b !BattleAct_LerpSum
    JSR Battle_ShiftRight3
    STA.b !BattleAct_LerpSum
    TDC
    SEP #$20
    LDA.b !BattleAct_LerpSum
    STA.w !Battle_ActCalcOutA
    LDA.b !BattleAct_LerpY1
    STA.b !Battle_Mul8A
    LDA.b !BattleAct_LerpW1
    STA.b !Battle_Mul8B
    JSR Battle_Mul8                     ; w1 * y1
    LDX.b !Battle_Mul8Product
    STX.b !BattleAct_LerpSum
    LDA.b !BattleAct_LerpY2
    STA.b !Battle_Mul8A
    LDA.b !BattleAct_LerpW2
    STA.b !Battle_Mul8B
    JSR Battle_Mul8                     ; w2 * y2
    REP #$21                            ; 16-bit A, carry clear
    LDA.b !Battle_Mul8Product
    ADC.b !BattleAct_LerpSum
    JSR Battle_ShiftRight3
    STA.b !BattleAct_LerpSum
    TDC
    SEP #$20
    LDA.b !BattleAct_LerpSum
    STA.w !Battle_ActCalcOutB
    PLX
    STX.b !BattleTmp_86
    RTS

; ==================================================================
; BattleAct_FacingModeTable ($C179A1–$C179D2, 25 words)
; ==================================================================
; BattleAct_CalcFacing's handler per facing mode 0-$18, called through
; JSR (BattleAct_FacingModeTable,X) with X = mode * 2.
org $C179A1
BattleAct_FacingModeTable:
    dw BattleAct_FaceLikeEntry          ; $00-$09: the facing of entry n
    dw BattleAct_FaceLikeEntry
    dw BattleAct_FaceLikeEntry
    dw BattleAct_FaceLikeEntry
    dw BattleAct_FaceLikeEntry
    dw BattleAct_FaceLikeEntry
    dw BattleAct_FaceLikeEntry
    dw BattleAct_FaceLikeEntry
    dw BattleAct_FaceLikeEntry
    dw BattleAct_FaceLikeEntry
    dw BattleAct_FaceTowardEntry        ; $0A-$13: toward entry n - $0A
    dw BattleAct_FaceTowardEntry
    dw BattleAct_FaceTowardEntry
    dw BattleAct_FaceTowardEntry
    dw BattleAct_FaceTowardEntry
    dw BattleAct_FaceTowardEntry
    dw BattleAct_FaceTowardEntry
    dw BattleAct_FaceTowardEntry
    dw BattleAct_FaceTowardEntry
    dw BattleAct_FaceTowardEntry
    dw BattleAct_FaceFixed              ; $14-$17: facing n - $14
    dw BattleAct_FaceFixed
    dw BattleAct_FaceFixed
    dw BattleAct_FaceFixed
    dw BattleAct_FaceTowardCentre       ; $18

; ==================================================================
; BattleAct_CalcTable ($C179D3–$C17A62, 72 words)
; ==================================================================
; BattleAct_RunCalc's handler per number 0-$47, called through
; JSR (BattleAct_CalcTable,X) with X = number * 2.
org $C179D3
BattleAct_CalcTable:
    dw BattleAct_CalcEntryPos           ; $00-$08: entry n
    dw BattleAct_CalcEntryPos
    dw BattleAct_CalcEntryPos
    dw BattleAct_CalcEntryPos
    dw BattleAct_CalcEntryPos
    dw BattleAct_CalcEntryPos
    dw BattleAct_CalcEntryPos
    dw BattleAct_CalcEntryPos
    dw BattleAct_CalcEntryPos
    dw BattleAct_CalcEntryOffsetPos     ; $09-$11: entry n - 9 with its screen offsets
    dw BattleAct_CalcEntryOffsetPos
    dw BattleAct_CalcEntryOffsetPos
    dw BattleAct_CalcEntryOffsetPos
    dw BattleAct_CalcEntryOffsetPos
    dw BattleAct_CalcEntryOffsetPos
    dw BattleAct_CalcEntryOffsetPos
    dw BattleAct_CalcEntryOffsetPos
    dw BattleAct_CalcEntryOffsetPos
    dw BattleAct_CalcNone               ; $12
    dw BattleAct_CalcMid03              ; $13
    dw BattleAct_CalcMid01              ; $14
    dw BattleAct_CalcMid02              ; $15
    dw BattleAct_CalcCentroid           ; $16
    dw BattleAct_CalcAheadOfActor       ; $17
    dw BattleAct_CalcFixedPoint         ; $18
    dw BattleAct_CalcSavedPos           ; $19-$1B
    dw BattleAct_CalcSavedPos
    dw BattleAct_CalcSavedPos
    dw BattleAct_CalcObjOffset          ; $1C-$23: object n - $1C
    dw BattleAct_CalcObjOffset
    dw BattleAct_CalcObjOffset
    dw BattleAct_CalcObjOffset
    dw BattleAct_CalcObjOffset
    dw BattleAct_CalcObjOffset
    dw BattleAct_CalcObjOffset
    dw BattleAct_CalcObjOffset
    dw BattleAct_CalcLerpToTarget       ; $24-$29: caster to target
    dw BattleAct_CalcLerpToTarget
    dw BattleAct_CalcLerpToTarget
    dw BattleAct_CalcLerpToTarget
    dw BattleAct_CalcLerpToTarget
    dw BattleAct_CalcLerpToTarget
    dw BattleAct_CalcVarPair            ; $2A-$31: variable pair n - $2A
    dw BattleAct_CalcVarPair
    dw BattleAct_CalcVarPair
    dw BattleAct_CalcVarPair
    dw BattleAct_CalcVarPair
    dw BattleAct_CalcVarPair
    dw BattleAct_CalcVarPair
    dw BattleAct_CalcVarPair
    dw BattleAct_CalcLerpToTarget       ; $32-$38: entry 1 to target
    dw BattleAct_CalcLerpToTarget
    dw BattleAct_CalcLerpToTarget
    dw BattleAct_CalcLerpToTarget
    dw BattleAct_CalcLerpToTarget
    dw BattleAct_CalcLerpToTarget
    dw BattleAct_CalcLerpToTarget
    dw BattleAct_CalcLerpToTarget       ; $39-$3F: caster to target, with screen offsets
    dw BattleAct_CalcLerpToTarget
    dw BattleAct_CalcLerpToTarget
    dw BattleAct_CalcLerpToTarget
    dw BattleAct_CalcLerpToTarget
    dw BattleAct_CalcLerpToTarget
    dw BattleAct_CalcLerpToTarget
    dw BattleAct_CalcMid12              ; $40
    dw BattleAct_CalcLerpToObj0         ; $41-$47: caster to object 0
    dw BattleAct_CalcLerpToObj0
    dw BattleAct_CalcLerpToObj0
    dw BattleAct_CalcLerpToObj0
    dw BattleAct_CalcLerpToObj0
    dw BattleAct_CalcLerpToObj0
    dw BattleAct_CalcLerpToObj0

; ==================================================================
; BattleAct_LoaderTable ($C17A63–$C17A6A, 4 words)
; ==================================================================
; Action loader per !Battle_ActKind 0-3, called by BattleAct_LoadScript
; through JSR (BattleAct_LoaderTable,X) with X = kind * 2 (kinds 4 and
; up are taken as 0).
org $C17A63
BattleAct_LoaderTable:
    dw BattleAct_LoadNone           ; 0
    dw BattleAct_LoadAttack         ; 1
    dw BattleAct_LoadTech           ; 2
    dw BattleAct_LoadKind3          ; 3

; ==================================================================
; BattleAct_OpcodeTable ($C17A6B–$C17C2A, 224 words)
; ==================================================================
; Handler per action-script opcode, called by BattleAct_RunThread
; through JSR (BattleAct_OpcodeTable,X) with X = opcode * 2. Only
; opcodes below !Battle_ActNumOpcodes ($DB) are run, so the last five
; entries ($DB-$DF) are never reached. 75 entries point at
; BattleAct_OpEndScript: opcode $01 itself and the unused opcodes,
; among them $AA-$BF, $C6-$CF and $DB-$DF. 115 distinct handlers.
BattleAct_OpcodeTable:
    dw BattleAct_OpEndThread        ; $00
    dw BattleAct_OpEndScript        ; $01
    dw BattleAct_OpLoopAnim         ; $02
    dw BattleAct_OpPlayAnim         ; $03
    dw BattleAct_OpShowAnimFrame    ; $04
    dw BattleAct_OpShowAnimFrame    ; $05
    dw BattleAct_OpShowAnimFrame    ; $06
    dw BattleAct_OpResetSpeed       ; $07
    dw BattleAct_OpSetSpeed         ; $08
    dw BattleAct_OpSetSpeed         ; $09
    dw BattleAct_OpSetSpeed         ; $0A
    dw BattleAct_OpSetSpeed         ; $0B
    dw BattleAct_OpSetSpeed         ; $0C
    dw BattleAct_OpSetSpeed         ; $0D
    dw BattleAct_OpSetSpeed         ; $0E
    dw BattleAct_OpSetSpeed         ; $0F
    dw BattleAct_OpMoveTo           ; $10
    dw BattleAct_OpMoveToUnkPoint   ; $11
    dw BattleAct_OpMoveToCalc       ; $12
    dw BattleAct_OpCurveTo          ; $13
    dw BattleAct_OpCurveToUnkPoint  ; $14
    dw BattleAct_OpCurveToCalc      ; $15
    dw BattleAct_OpPathTo           ; $16
    dw BattleAct_OpPathToUnkPoint   ; $17
    dw BattleAct_OpPathToCalc       ; $18
    dw BattleAct_OpSetPos           ; $19
    dw BattleAct_OpSetPosUnkPoint   ; $1A
    dw BattleAct_OpSetPosCalc       ; $1B
    dw BattleAct_OpFollow           ; $1C
    dw BattleAct_OpUnfollow         ; $1D
    dw BattleAct_OpCall             ; $1E
    dw BattleAct_OpReturn           ; $1F
    dw BattleAct_OpPause            ; $20
    dw BattleAct_OpReturnIfVar1F0   ; $21
    dw BattleAct_OpWaitVar          ; $22
    dw BattleAct_OpWaitVar1C        ; $23
    dw BattleAct_OpWaitVar1D        ; $24
    dw BattleAct_OpEndIfNoTarget    ; $25
    dw BattleAct_OpShowAnimEntry    ; $26
    dw BattleAct_OpSetUnkA5CD       ; $27
    dw BattleAct_OpClearUnkA5CD     ; $28
    dw BattleAct_OpSetUnk9FF7       ; $29
    dw BattleAct_OpClearUnk9FF7     ; $2A
    dw BattleAct_OpClearUnkA4A4     ; $2B
    dw BattleAct_OpUnkRevive        ; $2C
    dw BattleAct_OpSetUnkCFFF       ; $2D
    dw BattleAct_OpClearUnkCFFF     ; $2E
    dw BattleAct_OpEndScript        ; $2F
    dw BattleAct_OpSetVar           ; $30
    dw BattleAct_OpSetVar1C         ; $31
    dw BattleAct_OpSetVar1D         ; $32
    dw BattleAct_OpCalcToUnkPoint   ; $33
    dw BattleAct_OpIncVar           ; $34
    dw BattleAct_OpIncVar1C         ; $35
    dw BattleAct_OpIncVar1D         ; $36
    dw BattleAct_OpDecVar           ; $37
    dw BattleAct_OpDecVar1C         ; $38
    dw BattleAct_OpDecVar1D         ; $39
    dw BattleAct_OpAddVar           ; $3A
    dw BattleAct_OpAddVar1C         ; $3B
    dw BattleAct_OpAddVarTo1C       ; $3C
    dw BattleAct_OpCalcToResult     ; $3D
    dw BattleAct_OpCalcToResult     ; $3E
    dw BattleAct_OpCalcToResult     ; $3F
    dw BattleAct_OpCalcToResult     ; $40
    dw BattleAct_OpCopyVar          ; $41
    dw BattleAct_OpCopyVar1C        ; $42
    dw BattleAct_OpOffsetToUnkPoint ; $43
    dw BattleAct_OpActorPosToUnkPoint ; $44
    dw BattleAct_OpCalcToResult     ; $45
    dw BattleAct_OpCalcToResult     ; $46
    dw BattleAct_OpSetCalcSel       ; $47
    dw BattleAct_OpSetCalcSel       ; $48
    dw BattleAct_OpAddVarClamped    ; $49
    dw BattleAct_OpSwapVar1C1D      ; $4A
    dw BattleAct_OpEndScript        ; $4B
    dw BattleAct_OpEndScript        ; $4C
    dw BattleAct_OpSwapVar1C1D      ; $4D
    dw BattleAct_OpSwapVar1C1E      ; $4E
    dw BattleAct_OpSwapVar1C1F      ; $4F
    dw BattleAct_OpShowHitNumbers   ; $50
    dw BattleAct_OpShowHitNumbers   ; $51
    dw BattleAct_OpShowHitNumbers   ; $52
    dw BattleAct_OpShowHitNumbers   ; $53
    dw BattleAct_OpShowHitNumbers   ; $54
    dw BattleAct_OpShowHitNumbers   ; $55
    dw BattleAct_OpEndScript        ; $56
    dw BattleAct_OpEndScript        ; $57
    dw BattleAct_OpEndScript        ; $58
    dw BattleAct_OpEndScript        ; $59
    dw BattleAct_OpEndScript        ; $5A
    dw BattleAct_OpEndScript        ; $5B
    dw BattleAct_OpEndScript        ; $5C
    dw BattleAct_OpClearUnk9FF7Bit7 ; $5D
    dw BattleAct_OpSetUnk9FF7Bit7   ; $5E
    dw BattleAct_OpNop2             ; $5F
    dw BattleAct_OpLoadPalEntry     ; $60
    dw BattleAct_OpStartPalSeq      ; $61
    dw BattleAct_OpStartPalSeq      ; $62
    dw BattleAct_OpStartPalSeq      ; $63
    dw BattleAct_OpStartPalSeq      ; $64
    dw BattleAct_OpStopPalSeq       ; $65
    dw BattleAct_OpStopPalSeq       ; $66
    dw BattleAct_OpStopPalSeq       ; $67
    dw BattleAct_OpStopPalSeq       ; $68
    dw BattleAct_OpSetSpecialPalette ; $69
    dw BattleAct_OpRestorePalette   ; $6A
    dw BattleAct_OpStartPalCycle    ; $6B
    dw BattleAct_OpBlinkPalette     ; $6C
    dw BattleAct_OpStopPalCycle     ; $6D
    dw BattleAct_OpIncAllObjUnkA1D8 ; $6E
    dw BattleAct_OpClearAllObjUnkA1D8 ; $6F
    dw BattleAct_OpIncObjUnkA1D8    ; $70
    dw BattleAct_OpClearObjUnkA1D8  ; $71
    dw BattleAct_OpSetFacing        ; $72
    dw BattleAct_OpLinkObjBit7      ; $73
    dw BattleAct_OpLinkObjBit6      ; $74
    dw BattleAct_OpCopyHeading      ; $75
    dw BattleAct_OpHeadingFromCalc  ; $76
    dw BattleAct_OpAddHeading       ; $77
    dw BattleAct_OpSound            ; $78
    dw BattleAct_OpSound            ; $79
    dw BattleAct_OpSoundCalc        ; $7A
    dw BattleAct_OpSoundCalc        ; $7B
    dw BattleAct_OpPcAttackSfxA     ; $7C
    dw BattleAct_OpPcAttackSfxB     ; $7D
    dw BattleAct_OpEndScript        ; $7E
    dw BattleAct_OpEndScript        ; $7F
    dw BattleAct_OpRunVecCD001B     ; $80
    dw BattleAct_OpSetCalcSel       ; $81
    dw BattleAct_OpSetCalcSel       ; $82
    dw BattleAct_OpSetCalcSel       ; $83
    dw BattleAct_OpSetCalcSel       ; $84
    dw BattleAct_OpSetHeading       ; $85
    dw BattleAct_OpEndScript        ; $86
    dw BattleAct_OpEndScript        ; $87
    dw BattleAct_OpEndScript        ; $88
    dw BattleAct_OpEndScript        ; $89
    dw BattleAct_OpEndScript        ; $8A
    dw BattleAct_OpEndScript        ; $8B
    dw BattleAct_OpEndScript        ; $8C
    dw BattleAct_OpEndScript        ; $8D
    dw BattleAct_OpEndScript        ; $8E
    dw BattleAct_OpEndScript        ; $8F
    dw BattleAct_OpEndScript        ; $90
    dw BattleAct_OpEndScript        ; $91
    dw BattleAct_OpEndScript        ; $92
    dw BattleAct_OpEndScript        ; $93
    dw BattleAct_OpEndScript        ; $94
    dw BattleAct_OpEndScript        ; $95
    dw BattleAct_OpEndScript        ; $96
    dw BattleAct_OpEndScript        ; $97
    dw BattleAct_OpArcToCalc        ; $98
    dw BattleAct_OpArcToUnkPoint    ; $99
    dw BattleAct_OpArcDownToCalc    ; $9A
    dw BattleAct_OpArcDownToUnkPoint ; $9B
    dw BattleAct_OpArcToCalc        ; $9C
    dw BattleAct_OpArcToUnkPoint    ; $9D
    dw BattleAct_OpEndScript        ; $9E
    dw BattleAct_OpEndScript        ; $9F
    dw BattleAct_OpEndScript        ; $A0
    dw BattleAct_OpEndScript        ; $A1
    dw BattleAct_OpMoveAlongHeading ; $A2
    dw BattleAct_OpEndScript        ; $A3
    dw BattleAct_OpStartPosHistory  ; $A4
    dw BattleAct_OpStopPosHistory   ; $A5
    dw BattleAct_OpEndScript        ; $A6
    dw BattleAct_OpEndScript        ; $A7
    dw BattleAct_OpMoveHeadingSteps ; $A8
    dw BattleAct_OpMoveHeadingChecked ; $A9
    dw BattleAct_OpEndScript        ; $AA
    dw BattleAct_OpEndScript        ; $AB
    dw BattleAct_OpEndScript        ; $AC
    dw BattleAct_OpEndScript        ; $AD
    dw BattleAct_OpEndScript        ; $AE
    dw BattleAct_OpEndScript        ; $AF
    dw BattleAct_OpEndScript        ; $B0
    dw BattleAct_OpEndScript        ; $B1
    dw BattleAct_OpEndScript        ; $B2
    dw BattleAct_OpEndScript        ; $B3
    dw BattleAct_OpEndScript        ; $B4
    dw BattleAct_OpEndScript        ; $B5
    dw BattleAct_OpEndScript        ; $B6
    dw BattleAct_OpEndScript        ; $B7
    dw BattleAct_OpEndScript        ; $B8
    dw BattleAct_OpEndScript        ; $B9
    dw BattleAct_OpEndScript        ; $BA
    dw BattleAct_OpEndScript        ; $BB
    dw BattleAct_OpEndScript        ; $BC
    dw BattleAct_OpEndScript        ; $BD
    dw BattleAct_OpEndScript        ; $BE
    dw BattleAct_OpEndScript        ; $BF
    dw BattleAct_OpCircleToCalc     ; $C0
    dw BattleAct_OpCircleToUnkPoint ; $C1
    dw BattleAct_OpEllipseToCalc    ; $C2
    dw BattleAct_OpEllipseToUnkPoint ; $C3
    dw BattleAct_OpStepUnkA4AF      ; $C4
    dw BattleAct_OpStepUnkA4AFTo0   ; $C5
    dw BattleAct_OpEndScript        ; $C6
    dw BattleAct_OpEndScript        ; $C7
    dw BattleAct_OpEndScript        ; $C8
    dw BattleAct_OpEndScript        ; $C9
    dw BattleAct_OpEndScript        ; $CA
    dw BattleAct_OpEndScript        ; $CB
    dw BattleAct_OpEndScript        ; $CC
    dw BattleAct_OpEndScript        ; $CD
    dw BattleAct_OpEndScript        ; $CE
    dw BattleAct_OpEndScript        ; $CF
    dw BattleAct_OpIncUnkA5D8       ; $D0
    dw BattleAct_OpClearUnkA5D8     ; $D1
    dw BattleAct_OpMoveKind4ToCalc  ; $D2
    dw BattleAct_OpMoveToMidpoint   ; $D3
    dw BattleAct_OpRunMoveAfterUnkAAFC ; $D4
    dw BattleAct_OpRunMoveAfterMajorDist ; $D5
    dw BattleAct_OpRunMove          ; $D6
    dw BattleAct_OpPointTowardCalc  ; $D7
    dw BattleAct_OpShake            ; $D8
    dw BattleAct_OpSetActAttr       ; $D9
    dw BattleAct_OpResetActAttr     ; $DA
    dw BattleAct_OpEndScript        ; $DB
    dw BattleAct_OpEndScript        ; $DC
    dw BattleAct_OpEndScript        ; $DD
    dw BattleAct_OpEndScript        ; $DE
    dw BattleAct_OpEndScript        ; $DF

; ==================================================================
; BattleAct_ProbeBoxOverlap ($C17C2B–$C17C3C, 18 bytes)
; ==================================================================
; Puts battler X's probe (!Battler_ProbeX/Y) at its screen position,
; builds its box (Battle_CalcBattlerBox) and tests it against the
; other battlers' boxes (Battle_BoxOverlapsOthers, tail JMP). It sits
; right after BattleAct_OpcodeTable.
; Callers (JSR): BattleAct_OpMoveHeadingChecked ($C1:6B83, $C1:6C2E).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E; X = battler slot, DP
;        $80-$81 (!Battle_BoxTestSlot) = the same slot
; Exit:  as Battle_BoxOverlapsOthers': A = $80 / $81 (N set) when the
;        box touches a PC's / an enemy's, else 0; Y = the slot touched
;        (11 when none); X = the slot; ProbeX/Y and the box written
; Callees: Battle_CalcBattlerBox, Battle_BoxOverlapsOthers (JMP)
org $C17C2B
BattleAct_ProbeBoxOverlap:
    LDA.w !Battler_ScreenX,X
    STA.w !Battler_ProbeX,X
    LDA.w !Battler_ScreenY,X
    STA.w !Battler_ProbeY,X
    JSR Battle_CalcBattlerBox
    JMP Battle_BoxOverlapsOthers

; ==================================================================
; BankC1_OldBuildLeftovers ($C17C3D–$C17FFF, 963 bytes)
; ==================================================================
; Not code and, as far as found, never read: xref finds no call or
; jump to $C1:7C3D or to any of the segment starts below, and the
; absolute $7C3D-$7FFF operands in bank $C1 code are WRAM reads (DB =
; $7E). The bytes are what earlier, longer assemblies of the
; end of this part of the bank left behind: the tables and
; BattleAct_ProbeBoxOverlap from BattleAct_FacingModeTable on, laid out
; as today but at higher addresses and with every pointer moved to
; match. Each later (shorter) build wrote over the start of the one
; before, so the copies are cut off at the front; the order newest to
; oldest is probably the order below. Kept as bytes; the code copies
; are given as db since they never run. $C1:8000 starts the next part
; of the bank (BankC1_BattleStartVec).
; - $7C3D-$7CC1: the current $7BB8-$7C3C (the last 57 entries and a
;   half of BattleAct_OpcodeTable, then BattleAct_ProbeBoxOverlap)
;   assembled $85 higher: every table word and both call operands
;   are the current value + $85.
; - $7CC2-$7F49: a build $30D higher, whole from its facing table on:
;   a 15-entry facing-mode table (modes 0-9 hold
;   BattleAct_FaceTowardEntry + $30D, $0A-$0D BattleAct_FaceFixed +
;   $30D, $0E BattleAct_FaceTowardCentre + $30D; there is no
;   BattleAct_FaceLikeEntry entry), then BattleAct_CalcTable,
;   BattleAct_LoaderTable and BattleAct_OpcodeTable entry for entry
;   + $30D, then BattleAct_ProbeBoxOverlap calling $2C59 / $2CAF (the
;   current targets + $3FF).
; - $7F4A-$7FE2: the high byte of entry $93 and entries $94-$DF of an
;   opcode table $3B8 higher (handlers + $3B8, the BattleAct_OpEndScript
;   entries + $3C4); $7FE3-$7FF4: its BattleAct_ProbeBoxOverlap,
;   calling $2BC4 / $2C1A (current + $36A).
; - $7FF5-$7FFC: the last 8 bytes of one more ProbeBoxOverlap copy
;   with the same two targets, 8 bytes higher.
; - $7FFD-$7FFF: $FF fill up to $C1:8000.
; Entry/Exit: not code (data; never executed).
org $C17C3D
BankC1_OldBuildLeftovers:
.copy85:                                ; $C1:7C3D-$C1:7CC1: the current $C1:7BB8-$C1:7C3C, $85 higher
    db $4D
                                        ; (the high byte of an unused-opcode entry, $4CF7 + $85)
    dw $4D7C,$6A48,$6B75,$4D7C,$4D7C,$4D7C,$4D7C,$4D7C
    dw $4D7C,$4D7C,$4D7C,$4D7C,$4D7C,$4D7C,$4D7C,$4D7C
    dw $4D7C,$4D7C,$4D7C,$4D7C,$4D7C,$4D7C,$4D7C,$4D7C
    dw $4D7C,$6D78,$6FB6,$6FD8,$6FFA,$701F,$7074,$4D7C
    dw $4D7C,$4D7C,$4D7C,$4D7C,$4D7C,$4D7C,$4D7C,$4D7C
    dw $4D7C,$7081,$70B0,$70DF,$7293,$73CE,$7432,$73E9
    dw $7490,$7539,$75BF,$75FE,$4D7C,$4D7C,$4D7C,$4D7C
    dw $4D7C
    db $BD,$0C,$1D,$9D,$39,$A0,$BD,$23,$1D,$9D,$50,$A0,$20,$DF,$28,$4C,$35,$29
                                        ; (BattleAct_ProbeBoxOverlap calling $28DF / $2935)
.facing30D:                             ; $C1:7CC2: 15-entry facing-mode table
    dw $78F0,$78F0,$78F0,$78F0,$78F0,$78F0,$78F0,$78F0,$78F0,$78F0
    dw $7917,$7917,$7917,$7917,$791F
.calc30D:                               ; $C1:7CE0: 72-entry calc table
    dw $7946,$7946,$7946,$7946,$7946,$7946,$7946,$7946
    dw $7946,$7957,$7957,$7957,$7957,$7957,$7957,$7957
    dw $7957,$7957,$798A,$798B,$7993,$799B,$79E5,$7A5B
    dw $7ADE,$7AE7,$7AE7,$7AE7,$7AF9,$7AF9,$7AF9,$7AF9
    dw $7AF9,$7AF9,$7AF9,$7AF9,$7B18,$7B18,$7B18,$7B18
    dw $7B18,$7B18,$7C0E,$7C0E,$7C0E,$7C0E,$7C0E,$7C0E
    dw $7C0E,$7C0E,$7B18,$7B18,$7B18,$7B18,$7B18,$7B18
    dw $7B18,$7B18,$7B18,$7B18,$7B18,$7B18,$7B18,$7B18
    dw $7C21,$7C2D,$7C2D,$7C2D,$7C2D,$7C2D,$7C2D,$7C2D
.loader30D:                             ; $C1:7D70: 4-entry loader table
    dw $4A67,$4639,$48AD,$4A68
.opcode30D:                             ; $C1:7D78: 224-entry opcode table
    dw $4FFD,$5004,$5011,$512F,$51AF,$51AF,$51AF,$5227
    dw $5261,$5261,$5261,$5261,$5261,$5261,$5261,$5261
    dw $52CC,$52DE,$52F0,$54FB,$5512,$5529,$5716,$5728
    dw $573A,$591E,$5979,$598A,$59A1,$59C8,$59D9,$5A08
    dw $5A21,$5A2F,$5A39,$5A50,$5A63,$5A76,$5A8A,$5B13
    dw $5B4D,$5B51,$5B86,$5B8A,$5BB8,$5BE9,$5BF1,$5004
    dw $5BF9,$5C0B,$5C19,$5C27,$5C3E,$5C4D,$5C58,$5C63
    dw $5C72,$5C7D,$5C88,$5C9E,$5CB0,$5CC6,$5CC6,$5CC6
    dw $5CC6,$5CF1,$5D07,$5D19,$5D4B,$5CC6,$5CC6,$6549
    dw $6549,$5D7D,$5DA6,$5004,$5004,$5DA6,$5DBC,$5DD2
    dw $5DE8,$5DE8,$5DE8,$5DE8,$5DE8,$5DE8,$5004,$5004
    dw $5004,$5004,$5004,$5004,$5004,$5FFE,$601F,$6025
    dw $602A,$60A0,$60A0,$60A0,$60A0,$60CE,$60CE,$60CE
    dw $60CE,$60E0,$6194,$61EC,$6220,$62A7,$62B2,$62C0
    dw $62CE,$62E0,$62EB,$6366,$636C,$63A0,$63F3,$6461
    dw $64AB,$64AB,$64CE,$64CE,$64F8,$6502,$5004,$5004
    dw $6528,$6549,$6549,$6549,$6549,$6565,$5004,$5004
    dw $5004,$5004,$5004,$5004,$5004,$5004,$5004,$5004
    dw $5004,$5004,$5004,$5004,$5004,$5004,$5004,$5004
    dw $65A6,$6A3B,$6A50,$6A57,$65A6,$6A3B,$5004,$5004
    dw $5004,$5004,$6A5E,$5004,$6C28,$6CC7,$5004,$5004
    dw $6CD0,$6DFD,$5004,$5004,$5004,$5004,$5004,$5004
    dw $5004,$5004,$5004,$5004,$5004,$5004,$5004,$5004
    dw $5004,$5004,$5004,$5004,$5004,$5004,$5004,$5004
    dw $7000,$723E,$7260,$7282,$72A7,$72FC,$5004,$5004
    dw $5004,$5004,$5004,$5004,$5004,$5004,$5004,$5004
    dw $7309,$7338,$7367,$751B,$7656,$76BA,$7671,$7718
    dw $77C1,$7847,$7886,$5004,$5004,$5004,$5004,$5004
.probe3FF:                              ; $C1:7F38: BattleAct_ProbeBoxOverlap calling $2C59 / $2CAF
    db $BD,$0C,$1D,$9D,$39,$A0,$BD,$23,$1D,$9D,$50,$A0,$20,$59,$2C,$4C,$AF,$2C
.opcode3B8:                             ; $C1:7F4A: the last 76 entries and a half of an opcode table
    db $50
    dw $50BB,$50BB,$50BB,$50BB,$6651,$6AE6,$6AFB,$6B02
    dw $6651,$6AE6,$50BB,$50BB,$50BB,$50BB,$6B09,$50BB
    dw $6CD3,$6D72,$50BB,$50BB,$6D7B,$6EA8,$50BB,$50BB
    dw $50BB,$50BB,$50BB,$50BB,$50BB,$50BB,$50BB,$50BB
    dw $50BB,$50BB,$50BB,$50BB,$50BB,$50BB,$50BB,$50BB
    dw $50BB,$50BB,$50BB,$50BB,$70AB,$72E9,$730B,$732D
    dw $7352,$73A7,$50BB,$50BB,$50BB,$50BB,$50BB,$50BB
    dw $50BB,$50BB,$50BB,$50BB,$73B4,$73E3,$7412,$75C6
    dw $7701,$7765,$771C,$77C3,$786C,$78F2,$7931,$50BB
    dw $50BB,$50BB,$50BB,$50BB
.probe36A:                              ; $C1:7FE3: BattleAct_ProbeBoxOverlap calling $2BC4 / $2C1A
    db $BD,$0C,$1D,$9D,$39,$A0,$BD,$23,$1D,$9D,$50,$A0,$20,$C4,$2B,$4C,$1A,$2C
.probe36A_tail:                         ; $C1:7FF5: the last 8 bytes of one more such copy
    db $50,$A0,$20,$C4,$2B,$4C,$1A,$2C
.fill:
    db $FF,$FF,$FF

; ==================================================================
; Battle main routine ($C1:8000–$C1:8460)
; ==================================================================
; $C1:8000 starts a new part of the bank: two JMP vectors, then the
; routine the battle runs in from its setup to its end. The battle entry
; reaches it as JSL $C10000 (from the field at $C0:18A7) -> JMP $001B ->
; JML $CF:FB65, which clears the battle RAM and JMLs to $C1:8000
; (BattleSys_PumpFrames' header; the JML is at $CF:FBE1).

; $C1:8000 — BankC1_BattleStartVec (3 bytes)
; Vector into BattleSys_Main.
; Callers: JML at $CF:FBE1 (the battle entry, unmatched); xref also
;   confirms a JSL $C1:8000 decoded at $E2:74F3 (unmatched, not checked
;   to be code).
; Entry: as BattleSys_Main (M=1, X=0, DP=0, DB=$7E)
; Exit:  never returns (BattleSys_Main leaves through BattleSys_ExitVec)
org $C18000
BankC1_BattleStartVec:
    JMP BattleSys_Main

; $C1:8003 — BankC1_Entry8003 (3 bytes)
; Long vector into BankC1_RunService (unmatched, $C1:CFC2), which
; pushes P, X, DP and DB itself (PHP, REP #$30, PHX, PHD, PHB), sets
; DB=$7E and DP=0, runs entry A (low byte) of its service table at
; $C1:D126 with argument Y, pulls them back and returns with RTL; service 1 is
; BankC1_AddItem, service 4 BankC1_AddGold (!BankC1Svc_AddItem /
; AddGold, as Field_CheckTileInFront uses them).
; Callers (JSL): Field_CheckTileInFront ($C0:1E72, $C0:1E84) and the
;   unmatched bank-$C0 code at $C0:378E, $C0:37BF, $C0:37F1, $C0:3838,
;   $C0:386C and $C0:3885.
; Entry: M and X any (the service sets its own widths), DP and DB any;
;        A = service number, Y = argument
; Exit:  P, X, DP and DB as on entry; A = the service's result; Y as
;        the service leaves it (RTL)
BankC1_Entry8003:
    JMP BankC1_RunService

; $C1:8006 — BattleSys_Main (1115 bytes, $8006–$8460)
; The battle from its setup to its end; it never returns, leaving
; through BattleSys_ExitVec ($C1:0006 -> $001F -> JML $CF:FBE5).
; Setup:
;   - BattleFD_UnkA982; !Battle_RandIdx (and !Battle_UnkB3E6) from
;     !Battle_SavedRandIdx; Battle_SetupBattle.
;   - !Battle_Unk2989 bit 5 is saved in !Battle_Saved2989Bit5 and
;     cleared, so the shuffles below are random; then service 0
;     (not analysed).
;   - !Battle_SlotOrder: a random order of the battlers taking part. The
;     pool gets !Battle_UnkB1BE[!Battler_UnkAEFF] + 1 for each PC entry
;     that is not negative (PCs 0-2), then !Battle_EnemyCount + 3 down
;     to 4 (slots 3.. as slot + 1; with an enemy count of 0 that loop
;     would run on past the 11 bytes, which is presumably never the
;     case); it is drawn from with Battle_RandRange
;     over the first !Battle_BattlerCount entries until each is taken.
;   - !Battle_EnemyOrder: the enemy entries 0-7 whose
;     !Battler_UnkAF0A value is not $FF, in a random order. Quirk: the
;     draw loop ends once entries 0 to !Battle_EnemyCount - 1 are all
;     taken, so a present entry at or past !Battle_EnemyCount is in the
;     list only if it was drawn before that.
;   - !Battle_UnkB242 set to $FF, !Battle_UnkB252 zeroed,
;     BattleSys_Unk8C09, bit 5 put back. With bit 5 set, PCs get
;     !Battler_UnkAFAB 1 and the enemies $FF.
; Each pass of the loop (.pass): !Battle_LoopCount + 1,
; !Battle_UnkB2C7 = 0, service 3 (BattleSys_UpkeepTwoFrames: two
; frames), BattleFD_UnkACFD, BattleSys_UnkB223, then the first of:
;   - !Battle_Unk24 non-zero: the defeat end.
;   - no enemy entry left (each of the 8 !Battler_UnkAEFF enemy bytes
;     $FF or its !Battle_UnkAF15 bit 6 set): the victory end.
;   - otherwise BattleSys_UnkB093 for the 3 PCs and BattleSys_UnkB0B6
;     for Y = 0-10 (11 calls; the loop tests Y after the call), then by state: wait mode (!Battle_MenuTimeHold set):
;     BattleSys_UnkB3F9 for each PC with a !Battler_UnkAF0A entry;
;     !Battle_Unk99CD set (bit 5 clear): the !Battle_Unk99CD end;
;     !Battle_UnkAF25 set: BattleSys_Unk8461; else the turn lists:
;     .count steps the !Battle_ListTimers countdowns and marks due
;     entries in !Battle_ListFlags; every second pass .scan finds each
;     list's next due slot in !Battle_SlotOrder (!Battle_ListCursor)
;     and .run runs BattleSys_ListHandlerTable for the lists that found
;     one (!Battle_ListDue).
;   - then the debug win (.debug_check; it ends the battle without
;     putting the max HP back) and, with bit 5 clear, the next
;     pass; with bit 5 set the battle ends after this pass
;     (BattleSys_UnkB3D2, then .victory, which with bit 5 set goes on
;     to .end_lost: no rewards).
; Ends: victory (service 8, BattleSys_VictoryPose; the max HP put back;
; unless bit 5 is set: the gold, unless !Battle_Unk2880 is set, and
; the item rewards), defeat (service 3 eight times with
; !Battle_UnkA10E set, then service 9, BattleSys_DefeatPose), the
; !Battle_Unk99CD end (probably running away; not traced). All save
; !Battle_RandIdx back and copy !Battle_Unk1C48 entries 0/5/10 to the
; PCs' BattlerStats.Unk56 before BattleFD_UnkAAB0.
; "Victory", "defeat" and "wait mode" rest on the services and flags'
; known roles (their headers); the turn-list reading (13 lists, each
; finding the next due battler in the shuffled order) is inferred from
; the loops only: what each list and handler stands for is not traced.
; Callers: none by call; reached through BankC1_BattleStartVec.
; Entry: M=1, X=0, DP=0, DB=$7E (as the battle entry leaves them; the
;        code uses .b direct page, TDC as zero and .w WRAM operands)
; Exit:  never returns: JMP BattleSys_ExitVec with M=1, X=0, DP=0,
;        DB=$7E
; Callees: BattleFD_UnkA982/ACFD/AA98/AD17/B201/AAB0, Battle_SetupBattle,
;          BattleSys_RunServiceVec (services 0, 3, 6, 8, 9),
;          Battle_RandRange, BattleSys_Unk8C09/8461/895B,
;          BattleSys_UnkB223/B3BB/B3D2/B3F9/B442/B4E9/B7F2/B093/B0B6/BC60,
;          BattleSys_UnkEA9D/EAE8/F93E, BattleSys_UnkVecCD0021,
;          BattleSys_ListHandlerTable entries, BankC1_AddGold,
;          BankC1_AddItem, BattleSys_ExitVec (JMP)
!BattleMain_Idx    = !BattleTmp_00      ; 1-2 B: loop index (PC, enemy, list)
!BattleMain_Slot   = !BattleTmp_02      ; 2 B: slot from !Battle_SlotOrder (.scan)
!BattleMain_Reward = !BattleTmp_10      ; 1-2 B: !Battle_RewardItems index
BattleSys_Main:
    JSL BattleFD_UnkA982
    LDA.w !Battle_SavedRandIdx
    STA.b !Battle_RandIdx
    STA.w !Battle_UnkB3E6
    JSR Battle_SetupBattle
    SEP #$20
    REP #$10
    STZ.w !Battle_Saved2989Bit5
    LDA.w !Battle_Unk2989
    AND.b #!Battle_2989Bit5
    STA.w !Battle_Saved2989Bit5
    LDA.w !Battle_Unk2989
    AND.b #!Battle_2989Bit5^$FF
    STA.w !Battle_Unk2989
    TDC                                 ; A = !BattleSys_ServiceUnk0
    JSR BattleSys_RunServiceVec
    TDC
    TAX
    STX.w !Battle_ListDue
    LDA.b #!Battle_EntryNone
.clear_lists:
    STA.w !Battle_SlotOrder,X
    STA.w !Battle_UnkB16E,X
    INX
    CPX.w #!Battle_NumSlots
    BNE .clear_lists
    ; Pool: the PCs taking part, then the enemies, as slot + 1.
    TDC
    TAX
    TAY
    STX.b !BattleMain_Idx
.pool_pcs:
    LDX.b !BattleMain_Idx
    LDA.w !Battler_UnkAEFF,X
    BMI .pool_pc_next
    TAX
    LDA.w !Battle_UnkB1BE,X
    INC A
    LDX.b !BattleMain_Idx
    STA.w !Battle_UnkB16E,Y
    INY
.pool_pc_next:
    INC.b !BattleMain_Idx
    LDA.b !BattleMain_Idx
    CMP.b #!Battle_NumPcSlots
    BCC .pool_pcs
    TYX
    LDA.w !Battle_EnemyCount
    CLC
    ADC.b #!Battle_FirstEnemySlot
.pool_enemies:
    STA.w !Battle_UnkB16E,X             ; EnemyCount + 3 down to 4: slots 3.. + 1 (count 0 runs on 256 times, past the 11 bytes)
    INX
    DEC A
    CMP.b #!Battle_FirstEnemySlot
    BNE .pool_enemies
    ; Draw them into !Battle_SlotOrder.
    TDC
    TAX
    TAY
.draw_slot:
    PHX
    TDC
    TAX                                 ; low bound 0
    LDA.w !Battle_BattlerCount
    JSR Battle_RandRange
    PLX
    TAY
    LDA.w !Battle_UnkB16E,Y
    CMP.b #!Battle_EntryNone
    BEQ .draw_slot                      ; taken already: draw again
    DEC A
    STA.w !Battle_SlotOrder,X
    LDA.b #!Battle_EntryNone
    STA.w !Battle_UnkB16E,Y
    INX
    TXA
    CMP.w !Battle_BattlerCount
    BCC .draw_slot
    ; The enemy entries into !Battle_EnemyOrder.
    TDC
    TAX
.copy_enemies:
    LDA.b #!Battle_EntryNone
    STA.w !Battle_EnemyOrder,X
    LDA.w !Battler_UnkAF0A+!Battle_FirstEnemySlot,X
    STA.w !Battle_UnkB16E,X
    INX
    CPX.w #!Battle_NumEnemies
    BCC .copy_enemies
    TDC
    TAX
    TAY
.draw_enemy:
    TDC
    TAX
    LDA.b #!Battle_NumEnemies
    JSR Battle_RandRange
    TAX
    LDA.w !Battle_UnkB16E,X
    CMP.b #!Battle_EntryNone
    BEQ .draw_enemy
    LDA.b #!Battle_EntryNone
    STA.w !Battle_UnkB16E,X
    TXA
    STA.w !Battle_EnemyOrder,Y
    INY
    TDC
    TAX
.any_left:
    LDA.w !Battle_UnkB16E,X
    CMP.b #!Battle_EntryNone
    BNE .any_left_found                 ; C=0 (A < $FF)
    INX
    TXA
    CMP.w !Battle_EnemyCount
    BCC .any_left
.any_left_found:
    BCC .draw_enemy                     ; C=1: entries 0..EnemyCount-1 all taken (quirk: later ones not checked)
    TDC
    TAX
    LDA.b #!Battle_EntryNone
.clear_b242:
    STA.w !Battle_UnkB242,X
    INX
    CPX.w #!Battle_NumEnemies
    BCC .clear_b242
    STZ.w !Battle_UnkB252
    JSR BattleSys_Unk8C09
    LDA.w !Battle_Unk2989
    ORA.w !Battle_Saved2989Bit5
    STA.w !Battle_Unk2989
    LDA.w !Battle_Unk2989
    BIT.b #!Battle_2989Bit5
    BEQ .pass
    LDA.b #1
    STA.w !Battler_UnkAFAB
    STA.w !Battler_UnkAFAB+1
    STA.w !Battler_UnkAFAB+2
    LDA.b #!Battle_EntryNone
    STA.w !Battler_UnkAFAB+3
    STA.w !Battler_UnkAFAB+4
    STA.w !Battler_UnkAFAB+5
    STA.w !Battler_UnkAFAB+6
    STA.w !Battler_UnkAFAB+7
    STA.w !Battler_UnkAFAB+8
    STA.w !Battler_UnkAFAB+9
    STA.w !Battler_UnkAFAB+10
.pass:
    TDC
    INC.w !Battle_LoopCount             ; absolute form of the DP byte (DP=0)
    STA.w !Battle_UnkB2C7
    LDA.b #!BattleSys_ServiceUpkeep
    JSR BattleSys_RunServiceVec
    JSL BattleFD_UnkACFD
    JSR BattleSys_UnkB223
    LDA.b !Battle_Unk24
    BEQ .check_enemies
    ; Defeat end.
    JSR BattleSys_UnkEA9D
    JSR BattleSys_UnkB3BB
    LDA.b #1
    STA.l !Battle_Unk7F01EC
    JSR BattleSys_UnkB7F2
    LDA.b #1
    STA.w !Battle_UnkA10E
    TDC
    TAX
    STX.b !BattleMain_Idx
.defeat_upkeep:
    LDA.b #!BattleSys_ServiceUpkeep
    JSR BattleSys_RunServiceVec
    INC.b !BattleMain_Idx
    LDA.b !BattleMain_Idx
    CMP.b #8
    BCC .defeat_upkeep
    STZ.w !Battle_UnkA10E
    LDA.b #!BattleSys_ServiceDefeat
    JSR BattleSys_RunServiceVec
    JMP .end_lost
.check_enemies:
    TDC
    TAX
.check_enemy:
    LDA.w !Battler_UnkAEFF+!Battle_FirstEnemySlot,X
    CMP.b #!Battle_EntryNone
    BNE .enemy_present
.check_enemy_next:
    INX
    CPX.w #!Battle_NumEnemies
    BCC .check_enemy
    ; Victory end: no enemy entry left.
    JSR BattleSys_UnkB3BB
    TDC
    STA.l !Battle_Unk7F01EC
    LDA.b #!Battle_EntryNone
    STA.w !Battle_UnkA5A9
    JSR BattleSys_UnkEA9D
    LDA.b #!BattleSys_ServiceVictory
    JSR BattleSys_RunServiceVec
    JMP .victory
.enemy_present:
    LDA.w !Battle_UnkAF15,X
    BIT.b #!Battle_AF15NotCounted
    BNE .check_enemy_next               ; bit 6: does not count
    TDC
    TAX
    TAY
    JSR BattleSys_UnkB093
    JSR BattleSys_UnkB0B6
    LDX.w #!Battle_StatsStride
    LDY.w #1
    JSR BattleSys_UnkB093
    JSR BattleSys_UnkB0B6
    LDX.w #!Battle_StatsStride*2
    LDY.w #2
    JSR BattleSys_UnkB093
    JSR BattleSys_UnkB0B6
.b0b6_rest:
    REP #$20
    TXA
    CLC
    ADC.w #!Battle_StatsStride
    TAX
    TDC
    SEP #$20
    INY
    JSR BattleSys_UnkB0B6
    CPY.w #!Battle_UnkB0B6Slots
    BCC .b0b6_rest
    LDA.w !Battle_MenuTimeHold
    BEQ .not_held
    ; Wait mode: only BattleSys_UnkB3F9 for the PCs.
    TDC
    STZ.w !Battle_UnkAE5A
.held_pc:
    TAX
    LDA.w !Battler_UnkAF0A,X
    CMP.b #!Battle_EntryNone
    BEQ .held_pc_next
    JSR BattleSys_UnkB3F9
.held_pc_next:
    TDC
    INC.w !Battle_UnkAE5A
    LDA.w !Battle_UnkAE5A
    CMP.b #!Battle_NumPcSlots
    BCC .held_pc
    JMP .debug_check
.not_held:
    LDA.w !Battle_Unk2989
    BIT.b #!Battle_2989Bit5
    BNE .not_99cd
    LDA.w !Battle_Unk99CD
    BEQ .not_99cd
    ; !Battle_Unk99CD end.
    TDC
    STA.l !Battle_Unk7F01EC
    JSL BattleFD_UnkAA98
    LDA.b #!Battle_EndUnkCD0021Arg
    JSL BattleSys_UnkVecCD0021
    JSR BattleSys_UnkEA9D
    JSR BattleSys_UnkB7F2
    LDA.b #!Battle_EndUnk895BArg
    JSR BattleSys_Unk895B
    JSR BattleSys_UnkEAE8
    JSR BattleSys_UnkB442
    JSR BattleSys_UnkB4E9
    JSR BattleSys_UnkB3BB
    JMP .end_lost
.not_99cd:
    REP #$30
    LDA.w !Battle_UnkAF25
    BEQ .count
    TDC
    SEP #$20
    JSR BattleSys_Unk8461
    JMP .debug_check
.count:
    ; Turn-list countdown over all 13 x 11 entries of !Battle_ListFlags:
    ; for an entry that takes part (non-zero, bit 7 clear), count down
    ; !Battle_ListTimers - list 0's timer of the same slot when the
    ; slot's list-0 entry is non-zero, due or not (counted once for each
    ; such entry),
    ; else the entry's own timer if not 0 already - and mark the entry
    ; due (bit 7) when it reaches 0. In the first case the bit goes on
    ; the slot's list-0 entry (X), not on the entry counted.
    SEP #$20
    TDC
    TAX
    TAY
    STY.w !Battle_UnkB3C0
    STY.w !Battle_UnkB3C4
.count_entry:
    LDX.w !Battle_UnkB3C4
    LDA.w !Battle_ListFlags,X
    BEQ .count_next
    BMI .count_next
    TDC
    LDA.w !Battle_UnkB3C0
    TAX
    LDA.w !Battle_ListFlags,X
    BEQ .count_own
    LDA.w !Battle_ListTimers,X
    DEC A
    STA.w !Battle_ListTimers,X
    CMP.b #0
    BNE .count_next
    BRA .count_due
.count_own:
    LDX.w !Battle_UnkB3C4
    LDA.w !Battle_ListTimers,X
    CMP.b #0
    BEQ .count_due
    DEC A
    STA.w !Battle_ListTimers,X
    CMP.b #0
    BNE .count_next
.count_due:
    LDA.w !Battle_ListFlags,X
    ORA.b #!Battle_ListDueBit
    STA.w !Battle_ListFlags,X
.count_next:
    INC.w !Battle_UnkB3C0
    LDA.w !Battle_UnkB3C0
    CMP.b #!Battle_NumSlots
    BCC .count_slot_ok
    STZ.w !Battle_UnkB3C0
.count_slot_ok:
    LDX.w !Battle_UnkB3C4
    INX
    STX.w !Battle_UnkB3C4
    CPX.w #!Battle_ListEntries
    BCC .count_entry
    LDA.w !Battler_UnkAFAB
    STA.w !Pc_AtbCur
    LDA.w !Battler_UnkAFAB+1
    STA.w !Pc_AtbCur+1
    LDA.w !Battler_UnkAFAB+2
    STA.w !Pc_AtbCur+2
    LDA.w !Battle_LoopCount
    BIT.b #1
    BEQ .scan_done
    ; Scan: for each list, from its cursor in !Battle_SlotOrder to the
    ; end, the first slot whose entry is due. Found: set the list's
    ; !Battle_ListDue bit and step the cursor past it (no wrap check
    ; there: the cursor can reach 11). Not found: the cursor goes back
    ; to 0 and the next list is scanned.
    TDC
    TAX
    STX.b !BattleMain_Idx
    LDX.w #!Battle_ListBit0
    STX.w !Battle_ListBit
.scan:
    TDC
    LDY.b !BattleMain_Idx
    LDA.w !Battle_ListCursor,Y
    TAX
    LDA.w !Battle_SlotOrder,X
    REP #$20
    STA.b !BattleMain_Slot
    LDA.b !BattleMain_Idx
    ASL A
    TAX
    LDA.l BattleSys_ListOffsetTable,X
    CLC
    ADC.b !BattleMain_Slot
    TAX
    TDC
    SEP #$20
    LDA.w !Battle_WramAbs,X             ; X = the !Battle_ListFlags entry's full address
    BIT.b #!Battle_ListDueBit
    BEQ .scan_step
    REP #$20
    LDA.w !Battle_ListDue
    ORA.w !Battle_ListBit
    STA.w !Battle_ListDue
    TDC
    SEP #$20
    LDY.b !BattleMain_Idx
    LDA.w !Battle_ListCursor,Y
    INC A
    STA.w !Battle_ListCursor,Y
    BRA .scan_next_list
.scan_step:
    LDY.b !BattleMain_Idx
    LDA.w !Battle_ListCursor,Y
    INC A
    STA.w !Battle_ListCursor,Y
    CMP.b #!Battle_NumSlots
    BCC .scan
    TDC
    STA.w !Battle_ListCursor,Y
.scan_next_list:
    INC.b !BattleMain_Idx
    LDY.b !BattleMain_Idx
    REP #$20
    LSR.w !Battle_ListBit
    TDC
    SEP #$20
    LDA.b !BattleMain_Idx
    CMP.b #!Battle_NumLists
    BCC .scan
.scan_done:
    LDA.w !Battle_LoopCount             ; the same bit tested again (redundant: nothing changed it)
    BIT.b #1
    BEQ .debug_check
    ; Run the handler of each list with a !Battle_ListDue bit, list 0
    ; first. The bits are not cleared here.
    REP #$20
    LDA.w #!Battle_ListBit0
    STA.w !Battle_ListBit
    TDC
    TAX
.run:
    LDA.w !Battle_ListBit
    BIT.w !Battle_ListDue
    BEQ .run_next
    PHX
    TXA
    ASL A
    TAX
    TDC
    SEP #$20
    JSR (BattleSys_ListHandlerTable,X)
    REP #$20
    PLX
.run_next:
    LSR.w !Battle_ListBit
    INX
    CPX.w #!Battle_NumLists
    BCC .run
    TDC
    SEP #$20
.debug_check:
    ; Debug win: with !BattleRom_DebugFlag set (it is 0 in this ROM)
    ; and Select held on pad 2, every enemy is KO'd with 0 HP and the
    ; battle ends at once.
    LDA.l !BattleRom_DebugFlag
    BEQ .no_debug
    LDA.l JOY2H
    AND.b #!Battle_JoySelectHi
    BNE .debug_win
.no_debug:
    JMP .pass_end
.debug_win:
    TDC
    STA.l !Battle_Unk7F01EC
    TAY
.debug_ko:
    LDA.b #!Battle_StatusKo
    STA.w BattlerStats[3].Status,Y
    REP #$20
    LDA.w #0
    STA.w BattlerStats[3].CurHp,Y
    TYA
    CLC
    ADC.w #!Battle_StatsStride
    TAY
    TDC
    SEP #$20
    CPY.w #!Battle_NumEnemies*!Battle_StatsStride
    BCC .debug_ko
    TDC
    TAX
.debug_clear:
    LDA.w !Battler_UnkAEFF+!Battle_FirstEnemySlot,X
    CMP.b #!Battle_EntryNone
    BEQ .debug_clear_next
    LDA.b #1
    STA.w !Battle_UnkAEB3,X             ; meaning unknown
    LDA.b #!Battle_EntryNone
    STA.w !Battler_UnkAEFF+!Battle_FirstEnemySlot,X
.debug_clear_next:
    INX
    CPX.w #!Battle_NumEnemies
    BCC .debug_clear
    TDC
    STA.w !Battle_UnkB18B
    JSR BattleSys_UnkBC60
    INC.w !Battle_UnkB18B
    JSR BattleSys_UnkBC60
    INC.w !Battle_UnkB18B
    JSR BattleSys_UnkBC60
    JSR BattleSys_UnkB3BB
    LDA.b #!BattleSys_ServiceUnk6
    JSR BattleSys_RunServiceVec
    JMP .end_common
.pass_end:
    LDA.w !Battle_Unk2989
    BIT.b #!Battle_2989Bit5
    BNE .bit5_end
    JMP .pass
.bit5_end:
    JSR BattleSys_UnkB3D2
.victory:
    REP #$20
    LDA.w !Battle_SavedMaxHp
    STA.w BattlerStats.MaxHp
    LDA.w !Battle_SavedMaxHp+2
    STA.w BattlerStats[1].MaxHp
    LDA.w !Battle_SavedMaxHp+4
    STA.w BattlerStats[2].MaxHp
    TDC
    SEP #$20
    LDA.w !Battle_Unk2989
    BIT.b #!Battle_2989Bit5
    BNE .end_lost
    LDA.w !Battle_Unk2880
    CMP.b #0
    BNE .no_gold
    JSL BattleFD_UnkB201
    LDY.w !Battle_RewardGold
    JSR BankC1_AddGold
    LDA.w !Battle_UnkB2AF
    ORA.b #!Battle_RewardBitGold
    STA.w !Battle_UnkB2AF
    JSR BattleSys_UnkF93E
.no_gold:
    JSL BattleFD_UnkAD17
    JSR BattleSys_UnkEAE8
    JSR BattleSys_UnkB442
    JSR BattleSys_UnkB4E9
    TDC
    TAX
    STX.b !BattleMain_Reward
.give_item:
    LDX.b !BattleMain_Reward
    LDA.w !Battle_RewardItems,X
    BEQ .give_item_next
    TAY
    JSR BankC1_AddItem
    LDA.w !Battle_UnkB2AF
    ORA.b #!Battle_RewardBitItem
    STA.w !Battle_UnkB2AF
.give_item_next:
    INC.b !BattleMain_Reward
    LDA.b !BattleMain_Reward
    CMP.b #!Battle_NumRewardItems
    BCC .give_item
    BRA .end_common
.end_lost:
    ; Defeat, the !Battle_Unk99CD end, and bit 5 set: max HP put back.
    REP #$20
    LDA.w !Battle_SavedMaxHp
    STA.w BattlerStats.MaxHp
    LDA.w !Battle_SavedMaxHp+2
    STA.w BattlerStats[1].MaxHp
    LDA.w !Battle_SavedMaxHp+4
    STA.w BattlerStats[2].MaxHp
    TDC
    SEP #$20
    JSR BattleSys_UnkEA9D
    JSR BattleSys_UnkEAE8
    JSR BattleSys_UnkB442
.end_common:
    LDA.b !Battle_RandIdx
    STA.w !Battle_SavedRandIdx
    LDA.w !Battle_Unk1C48
    STA.w BattlerStats.Unk56
    LDA.w !Battle_Unk1C48+5
    STA.w BattlerStats[1].Unk56
    LDA.w !Battle_Unk1C48+10
    STA.w BattlerStats[2].Unk56
    JSL BattleFD_UnkAAB0
    JMP BattleSys_ExitVec

; ==================================================================
; Turn-list handlers ($C1:8461–$C1:8C3D)
; ==================================================================
; The 13 per-slot turn lists BattleSys_Main counts and scans (see its
; header): four 13 x 11-byte arrays, one byte per list and battler slot,
; list n at +n * 11: !Battle_ListTimers (countdowns), !Battle_ListFlags
; (bit 7 due, low bits "takes part"), !Battle_ListRuns (runs left) and
; !Battle_ListReload (timer reload). When list n's scan finds a due slot
; it steps !Battle_ListCursor past it and sets the list's !Battle_ListDue
; bit; BattleSys_Main then runs entry n of BattleSys_ListHandlerTable.
; Every handler finds its slot the same way: the !Battle_SlotOrder entry
; just before the list's cursor (the last one, at !Battle_BattlerCount
; - 1, when the cursor is 0).
; The usual handler (lists 0, 2-5 and 10) re-arms the entry (flags = 1,
; timer = reload), clears the list's !Battle_ListDue bit, and counts
; !Battle_ListRuns down; at 0 it sets it back to 10, clears one status
; bit of the slot's BattlerStats and stops the entry (flags = 0). That
; shape, and lists 8/9 halving or doubling the timer by status bits,
; suggest timed statuses; which status each list is was not traced.
; List 12 (BattleSys_Unk8461) is the turn list proper: it hands ready
; PCs to the command menu and makes ready enemies act.
; The handlers run in BattleSys_Main's state (M=1, X=0, DP=0, DB=$7E,
; A = 0 from its TDC).

; $C1:8461 — BattleSys_Unk8461 (988 bytes, $8461–$883C)
; Handler of turn list 12, the battlers' turns (inferred: a ready PC is
; queued for the command menu by service 1, BattleMenu_EnqueueReadyBattler;
; a ready enemy's !Battler_UnkAFAB, probably its ATB gauge, is reloaded
; from !Battle_UnkB158). Also run by BattleSys_Main instead of the turn
; lists while !Battle_UnkAF25 is set. Steps:
;   - !Battle_UnkB2C0 and !Battle_UnkB3B9 = 0. On an even
;     !Battle_LoopCount it goes straight to .after_turn.
;   - Clears !Battle_UnkAEB2 and the 8 !Battle_UnkAEB3 bytes; the slot is
;     the one list 12 found (also when run through !Battle_UnkAF25), kept
;     in DP $22.
;   - Enemy slot (3-10), present (!Battler_UnkAEFF not $FF) and
;     !Battler_UnkAFAB 0: if its !Enemy_AnimWanted is 0, 4, 6 or
;     $0A-$10, or !Battler_Unk9826 is set, !Battler_Unk9826 is cleared
;     and, unless its !Battle_UnkB24A entry is set, !Battle_UnkAEC8 =
;     enemy, BattleSys_Unk8CF9, !Battler_UnkAFAB = !Battle_UnkB158,
;     BattleSys_UnkBD6F and list 12's flags = 1 (re-armed, not due).
;     When any test above fails: if any of !Battle_UnkB188-B18A is negative (a PC waiting),
;     !Battle_UnkB3BE counts 2, 1, 0, 2, ... into DP $14 (16-bit) and it
;     goes on at .pending; with none, to .end.
;   - PC slot with list 12 due: BattleFD_UnkAB30 (X = slot * $80,
;     Y = slot); then if !Battle_UnkAF23 is set: !Battle_UnkB3F4 and DP
;     $14 = slot, BattleSys_UnkB575, BattleSys_UnkBCE1. Else, if the
;     PC's BattleCmd.State is 0: with !Battle_Unk2989 bit 5 set
;     BattleSys_UnkB70E, else State = 1 and service 1 for the slot
;     (which adds bit 7, "waiting for a command").
;   - .pending: each PC whose BattleCmd.State is negative has it copied
;     to its !Battle_UnkB188-B18A byte; with bit 5 set BattleSys_UnkB725.
;     Then the head of !Battle_CmdQueue (a PC that committed a command),
;     if any, is popped into !Battle_UnkB18B; if bit 7 of that PC's
;     State and of its latched B188-B18A byte differ (the command was
;     chosen since), BattleSys_UnkB967 runs (probably the command; not
;     traced) and both bytes are zeroed.
;   - BattleSys_Unk883D: a popped command of PC 0 or 1 never calls it;
;     one of PC 2 calls it only after BattleSys_UnkB967 ran (it falls
;     through into the JSR at $C1:860A; when nothing ran, the BPL at
;     $C1:85F9 skips it); then, when no PC is latched any more, list 12's
;     !Battle_ListDue bit is cleared.
;   - .after_turn: BattleSys_UnkB223, !Battle_UnkB3AC = the 11 bytes of
;     !Battle_UnkAD8E, !Battle_UnkB3B7 = !Battle_UnkB18B,
;     BattleSys_UnkB762. With bit 5 set, or !Battle_UnkB2C0 still 0
;     (then after BattleFD_UnkAC6E), or an enemy !Battle_UnkB3B7 whose
;     BattlerStats.Status2 has bit 2, it goes to .end.
;   - .react: for each of the first 8 !Battle_UnkB3AC entries that is an
;     enemy slot, the second part of that enemy's script (probably its
;     behaviour script, from bank $CC: BattleSys_UnkB488 looks it up by the id in
;     !Battler_UnkAEFF, or by !Battler_UnkAF0A when the entry is empty
;     and the part starts with code $20, which then also puts the id
;     back) is run block by block through BattleSys_UnkB80DTable, unless
;     the enemy's Status2 has any of bits 7, 3-0. A block is one or two
;     4-byte records (two when byte 4 is not $FE), then up to a $FE; $FF
;     ends the part. When a block's condition records leave
;     !Battle_UnkAF24 0, the enemy acts on it (BattleSys_Unk8CF9, which
;     zeroes AF24 and may set it again, then BattleSys_UnkB223), and
;     AF24 is stored to !Battle_UnkB24A (2 also zeroes !Battle_UnkB2B6).
;     Then, if AF24 is 0 the part ends; otherwise the rest of the block
;     is skipped (for a value other than 2, the remaining conditions to
;     the $FE first) and the next block is tried, unless $FF follows
;     (!Battle_UnkB263 counts the blocks tried).
;     !Enemy_AnimWanted is saved over the part and put back.
;     BattleSys_UnkB575 runs after each entry, BattleSys_ClearUnkB192
;     between entries. !Battle_UnkB1D4, !Battle_UnkB24A, !Battle_UnkB263
;     and !Battle_UnkB2B6 are indexed here by the list position
;     !Battle_UnkB315; BattleSys_Unk8C09 (through BattleSys_UnkAFD2)
;     indexes B24A, B263 and B2B6 by enemy instead (a bug or not, not
;     known). The reading as "reactions to the last action"
;     rests on !Battle_UnkB3AC being copied right after it; not traced.
;   - .end: BattleSys_UnkAC5E; unless DP !Battle_Unk24 is set,
;     BattleSys_Unk8C09; !Battle_UnkB18B = !Battle_UnkB3B7,
;     BattleSys_ClearUnkB192, BattleSys_UnkAC46, BattleFD_UnkACEE;
;     !Battle_UnkB2C0 = 0.
; Quirks: a NOP after the bit-5 test ($C1:864A); in .react the LDX of
; !Battle_UnkB1D2 at $C1:87EE is dead (X is reloaded at once).
; Callers: BattleSys_Main ($C1:822B); also entry 12 of
;   BattleSys_ListHandlerTable.
; Entry: M=1, X=0, DP=0, DB=$7E (.b direct page, .w WRAM operands); A
;        is set with TDC before use
; Exit:  M=1, X=0 (as the code assumes after its callees, none of which
;        is analysed), DP=0, DB=$7E; A, X, Y clobbered; DP $14/$15 and
;        $22/$23 written; the RAM above changed, plus whatever the
;        callees change
; Callees: BattleSys_Unk8CF9, BattleSys_UnkBD6F, BattleFD_UnkAB30,
;          BattleSys_UnkB575, BattleSys_UnkBCE1, BattleSys_UnkB70E,
;          BattleSys_RunServiceVec (service 1), BattleSys_UnkB725,
;          BattleSys_UnkB967, BattleSys_Unk883D, BattleSys_UnkB223,
;          BattleSys_UnkB762, BattleFD_UnkAC6E, BattleSys_UnkB488,
;          BattleSys_UnkB80DTable entries, BattleSys_ClearUnkB192,
;          BattleSys_UnkAC5E, BattleSys_Unk8C09, BattleSys_UnkAC46,
;          BattleFD_UnkACEE
!BattleTurn_Slot = !BattleTmp_22        ; 2 B: the slot list 12 found
!BattleTurn_Arg14 = !BattleTmp_14       ; 1-2 B: slot (or !Battle_UnkB3BE) left for the callees (not traced)
org $C18461
BattleSys_Unk8461:
    TDC
    STA.w !Battle_UnkB2C0
    STA.w !Battle_UnkB3B9
    LDA.w !Battle_LoopCount             ; absolute $0027 (DB=$7E: the same byte as the DP one)
    BIT.b #1
    BNE .odd_pass
    JMP .after_turn
.odd_pass:
    TDC
    TAX
.clear_aeb2:
    STA.w !Battle_UnkAEB2,X
    INX
    CPX.w #!Battle_UnkAEB2Bytes
    BCC .clear_aeb2
    TDC
    LDX.w #!Battle_TurnList
    LDA.w !Battle_ListCursor,X
    BNE .cursor_ok
    LDA.w !Battle_BattlerCount
.cursor_ok:
    DEC A
    TAX
    LDA.w !Battle_SlotOrder,X
    TAX
    STX.b !BattleTurn_Slot
    CMP.b #!Battle_FirstEnemySlot
    BCC .pc
    ; Enemy slot.
    LDX.b !BattleTurn_Slot
    LDA.w !Battler_UnkAEFF,X
    CMP.b #!Battle_EntryNone
    BEQ .enemy_not_ready
    LDA.w !Battler_UnkAFAB,X
    BNE .enemy_not_ready
    LDA.w !Enemy_AnimWanted-!Battle_FirstEnemySlot,X
    BEQ .enemy_go
    CMP.b #4
    BEQ .enemy_go
    CMP.b #6
    BEQ .enemy_go
    CMP.b #!Battle_TurnAnimLo
    BCC .enemy_check_9826
    CMP.b #!Battle_TurnAnimEnd
    BCC .enemy_go
.enemy_check_9826:
    LDA.w !Battler_Unk9826,X
    BEQ .enemy_not_ready
.enemy_go:
    STZ.w !Battler_Unk9826,X
    LDA.w !Battle_UnkB24A-!Battle_FirstEnemySlot,X
    BNE .enemy_not_ready
    LDX.b !BattleTurn_Slot
    LDA.w !Battler_UnkAEFF,X
    CMP.b #!Battle_EntryNone
    BEQ .enemy_not_ready
    LDA.b !BattleTurn_Slot
    SEC
    SBC.b #!Battle_FirstEnemySlot
    STA.w !Battle_UnkAEC8
    JSR BattleSys_Unk8CF9
    LDX.b !BattleTurn_Slot
    LDA.w !Battle_UnkB158,X
    STA.w !Battler_UnkAFAB,X
    JSR BattleSys_UnkBD6F
    LDA.b #1
    STA.w !Battle_ListFlags+(!Battle_NumSlots*!Battle_TurnList),X
    JMP .held_pcs
.enemy_not_ready:
    TDC
    LDA.w !Battle_UnkB188
    ORA.w !Battle_UnkB189
    ORA.w !Battle_UnkB18A
    BPL .to_end
    DEC.w !Battle_UnkB3BE
    LDA.w !Battle_UnkB3BE
    BPL .b3be_ok
    LDA.b #2
    STA.w !Battle_UnkB3BE
.b3be_ok:
    LDA.w !Battle_UnkB3BE
    TAX
    STX.b !BattleTurn_Arg14
    JMP .pending
.to_end:
    JMP .end
.pc:
    LDX.b !BattleTurn_Slot
    LDA.w !Battle_ListFlags+(!Battle_NumSlots*!Battle_TurnList),X
    BMI .pc_due
    JMP .held_pcs
.pc_due:
    LDA.b !BattleTurn_Slot
    TAY
    REP #$20
    XBA
    LSR A
    TAX                                 ; X = slot * $80
    TDC
    SEP #$20
    JSL BattleFD_UnkAB30
    LDA.w !Battle_UnkAF23
    BEQ .pc_cmd
    LDA.b !BattleTurn_Slot
    STA.w !Battle_UnkB3F4
    STA.b !BattleTurn_Arg14
    STZ.b !BattleTurn_Arg14+1
    JSR BattleSys_UnkB575
    JSR BattleSys_UnkBCE1
    JMP .held_pcs
.pc_cmd:
    TDC
    LDX.b !BattleTurn_Slot
    STX.b !BattleTurn_Arg14
    LDA.b !BattleTurn_Arg14
    ASL A
    ASL A
    ASL A
    SEC
    SBC.b !BattleTurn_Arg14
    TAX                                 ; X = slot * 7, its BattleCmd record
    LDA.w BattleCmd.State,X
    BNE .pending
    TDC
    LDA.w !Battle_Unk2989
    BIT.b #!Battle_2989Bit5
    BEQ .pc_enqueue
    JSR BattleSys_UnkB70E
    JMP .pending_b725
.pc_enqueue:
    LDA.b #1
    STA.w BattleCmd.State,X
    LDA.b !BattleTurn_Arg14
    STA.b !Battle_ArgSlot
    LDA.b #!BattleSys_ServiceEnqueue
    JSR BattleSys_RunServiceVec
.pending:
    LDA.w BattleCmd.State
    BPL .pending_pc1
    STA.w !Battle_UnkB188
.pending_pc1:
    LDA.w BattleCmd[1].State
    BPL .pending_pc2
    STA.w !Battle_UnkB189
.pending_pc2:
    LDA.w BattleCmd[2].State
    BPL .pending_b725
    STA.w !Battle_UnkB18A
.pending_b725:
    LDA.w !Battle_Unk2989
    BIT.b #!Battle_2989Bit5
    BEQ .pop_cmd
    JSR BattleSys_UnkB725
.pop_cmd:
    LDA.w !Battle_CmdQueue
    BMI .held_pcs
    LDA.w !Battle_CmdQueue
    STA.w !Battle_UnkB18B
    LDA.w !Battle_CmdQueue+1
    STA.w !Battle_CmdQueue
    LDA.w !Battle_CmdQueue+2
    STA.w !Battle_CmdQueue+1
    LDA.b #!Battle_EntryNone
    STA.w !Battle_CmdQueue+2
    DEC.w !Battle_CmdQueueLen
    LDA.w !Battle_UnkB18B
    CMP.b #0
    BEQ .cmd_pc0
    CMP.b #1
    BEQ .cmd_pc1
    CMP.b #2
    BEQ .cmd_pc2
    BRA .held_pcs
.cmd_pc0:
    LDA.w BattleCmd.State
    EOR.w !Battle_UnkB188
    BPL .latched_check
    TDC
    STA.w !Battle_UnkB18B
    JSR BattleSys_UnkB967
    TDC
    STA.w !Battle_UnkB188
    STA.w BattleCmd.State
    BRA .latched_check
.cmd_pc1:
    LDA.w BattleCmd[1].State
    EOR.w !Battle_UnkB189
    BPL .latched_check
    LDA.b #1
    STA.w !Battle_UnkB18B
    JSR BattleSys_UnkB967
    TDC
    STA.w !Battle_UnkB189
    STA.w BattleCmd[1].State
    BRA .latched_check
.cmd_pc2:
    LDA.w BattleCmd[2].State
    EOR.w !Battle_UnkB18A
    BPL .latched_check
    LDA.b #2
    STA.w !Battle_UnkB18B
    JSR BattleSys_UnkB967
    TDC
    STA.w !Battle_UnkB18A
    STA.w BattleCmd[2].State
.held_pcs:
    JSR BattleSys_Unk883D
.latched_check:
    LDA.w !Battle_UnkB188
    ORA.w !Battle_UnkB189
    ORA.w !Battle_UnkB18A
    BNE .after_turn
    REP #$20
    LDA.w !Battle_ListDue
    AND.w #$FFFF^(!Battle_ListBit0>>!Battle_TurnList)
    STA.w !Battle_ListDue
    TDC
    SEP #$20
.after_turn:
    JSR BattleSys_UnkB223
    TDC
    TAX
.copy_ad8e:
    LDA.w !Battle_UnkAD8E,X
    STA.w !Battle_UnkB3AC,X
    INX
    CPX.w #!Battle_NumSlots
    BCC .copy_ad8e
    LDA.w !Battle_UnkB18B
    STA.w !Battle_UnkB3B7
    JSR BattleSys_UnkB762
    LDA.w !Battle_Unk2989
    BIT.b #!Battle_2989Bit5
    BEQ .bit5_clear
    JMP .end
.bit5_clear:
    NOP                                 ; quirk: no effect
    LDA.w !Battle_UnkB2C0
    BNE .check_actor
    JSL BattleFD_UnkAC6E
    JMP .end
.check_actor:
    TDC
    LDA.w !Battle_UnkB3B7
    CMP.b #!Battle_FirstEnemySlot
    BCC .react_start
    REP #$20
    XBA
    LSR A
    TAX                                 ; X = slot * $80
    TDC
    SEP #$20
    LDA.w BattlerStats.Status2,X
    BIT.b #!Battle_TurnNoReactBit
    BEQ .react_start
    JMP .end
.react_start:
    TDC
    STA.w !Battle_UnkB252
    STA.w !Battle_UnkB315
    STA.w !Battle_UnkB1CF
    STA.w !Battle_UnkAF24
.react:
    LDA.w !Battle_UnkB315
    TAX
    LDA.w !Battle_UnkB3AC,X
    CMP.b #!Battle_FirstEnemySlot
    BCS .react_enemy
    JMP .react_next
.react_enemy:
    CMP.b #!Battle_EntryNone
    BNE .react_slot
    JMP .react_next
.react_slot:
    TAX
    LDA.w !Battler_UnkAEFF,X
    CMP.b #!Battle_EntryNone
    BNE .react_present
    TXA
    SEC
    SBC.b #!Battle_FirstEnemySlot
    STA.w !Battle_UnkB252
    STA.w !Battle_UnkAEC8
    LDA.w !Battler_UnkAF0A,X
    JSR BattleSys_UnkB488
    LDX.w !Battle_UnkB1D2
    STX.w !Battle_UnkB273
    STX.w !Battle_UnkB1D0
    LDA.l !BattleRom_ScriptBank,X
    CMP.b #!BattleAi_CodeUnk20
    BNE .react_skip
    LDA.w !Battle_UnkAEC8
    TAX
    LDA.w !Battler_UnkAF0A+!Battle_FirstEnemySlot,X
    STA.w !Battler_UnkAEFF+!Battle_FirstEnemySlot,X
    BRA .react_script
.react_skip:
    JMP .react_next
.react_present:
    TXA
    SEC
    SBC.b #!Battle_FirstEnemySlot
    STA.w !Battle_UnkB252
    STA.w !Battle_UnkAEC8
    LDA.w !Battler_UnkAEFF,X
    JSR BattleSys_UnkB488
    LDX.w !Battle_UnkB1D2
    STX.w !Battle_UnkB273
    STX.w !Battle_UnkB1D0
.react_script:
    TDC
    LDA.w !Battle_UnkAEC8
    TAX
    LDA.w !Enemy_AnimWanted,X
    STA.w !Battle_UnkB2D5
    TDC
    LDA.w !Battle_UnkAEC8
    REP #$20
    XBA
    LSR A
    CLC
    ADC.w #!Battle_FirstEnemySlot*!Battle_StatsStride
    TAX                                 ; X = (enemy + 3) * $80
    TDC
    SEP #$20
    LDA.w BattlerStats.Status2,X
    BIT.b #!Battle_NoReactMask
    BNE .react_skip
.react_block:
    TDC
    STA.w !Battle_UnkB1CF
    STA.w !Battle_UnkAF24
    LDA.w !Battle_UnkB252
    TAX
    LDA.w !Battle_UnkB16E,X
    STA.w !Battle_UnkAEBB
    LDA.w !Battle_UnkB3B7
    STA.w !Battle_UnkB16E,X
    TDC
    LDX.w !Battle_UnkB1D2
    LDA.l !BattleRom_ScriptBank,X
    STA.w !Battle_UnkB239
    STZ.w !Battle_UnkAF24
    LDA.l !BattleRom_ScriptBank+4,X
    CMP.b #!BattleAi_BlockEnd
    BEQ .react_one_record
    LDA.b #1
    STA.w !Battle_UnkB1CF
.react_one_record:
    TDC
    LDA.w !Battle_UnkB315
    ASL A
    TAX
    REP #$20
    LDA.w !Battle_UnkB1D4,X
    STA.w !Battle_UnkB3CA
    TDC
    SEP #$20
    LDA.w !Battle_UnkB239
    ASL A
    TAX
    JSR (BattleSys_UnkB80DTable,X)
    LDA.w !Battle_UnkB1CF
    BEQ .react_ran
    LDX.w !Battle_UnkB1D0
    INX
    INX
    INX
    INX
    STX.w !Battle_UnkB1D2
    LDA.l !BattleRom_ScriptBank,X
    STA.w !Battle_UnkB239
    ASL A
    TAX
    JSR (BattleSys_UnkB80DTable,X)
.react_ran:
    LDA.w !Battle_UnkAF24
    BNE .react_after
    TDC
    LDA.w !Battle_UnkB252
    TAX
    LDA.w !Battle_UnkB3B7
    STA.w !Battle_UnkB16E,X
    LDA.w !Battle_UnkAEC8
    PHA
    JSR BattleSys_Unk8CF9
    PLA
    STA.w !Battle_UnkAEC8
    JSR BattleSys_UnkB223
    TDC
    LDA.w !Battle_UnkB315
    ASL A
    TAX
    REP #$20
    LDA.w !Battle_UnkB3CA
    STA.w !Battle_UnkB1D4,X
    SEP #$20
    TDC
    LDA.w !Battle_UnkB315
    TAX
    LDA.w !Battle_UnkAF24
    STA.w !Battle_UnkB24A,X
    CMP.b #2
    BNE .react_after
    LDA.b #0
    STA.w !Battle_UnkB2B6,X
.react_after:
    LDA.w !Battle_UnkAF24
    BEQ .react_done
    LDA.w !Battle_UnkAF24
    CMP.b #2
    BEQ .react_skip_actions
    STZ.w !Battle_UnkB1CF
    LDX.w !Battle_UnkB1D2
.react_skip_conds:
    INX
    LDA.l !BattleRom_ScriptBank,X
    CMP.b #!BattleAi_BlockEnd
    BNE .react_skip_conds
    STX.w !Battle_UnkB1D2
.react_skip_actions:
    LDX.w !Battle_UnkB1D2
.react_find_end:
    INX
    LDA.l !BattleRom_ScriptBank,X
    CMP.b #!BattleAi_BlockEnd
    BNE .react_find_end
    INX
    STX.w !Battle_UnkB1D2
    LDA.l !BattleRom_ScriptBank,X
    CMP.b #!BattleAi_ScriptEnd
    BEQ .react_done
    STX.w !Battle_UnkB1D0
    LDA.w !Battle_UnkB315
    TAX
    INC.w !Battle_UnkB263,X
    LDX.w !Battle_UnkB1D2               ; quirk: dead, X is reloaded below
    LDA.w !Battle_UnkB252
    TAX
    LDA.w !Battle_UnkAEBB
    STA.w !Battle_UnkB16E,X
    JMP .react_block
.react_done:
    TDC
    LDA.w !Battle_UnkAEC8
    TAX
    LDA.w !Battle_UnkB2D5
    STA.w !Enemy_AnimWanted,X
.react_next:
    JSR BattleSys_UnkB575
    INC.w !Battle_UnkB315
    LDA.w !Battle_UnkB315
    CMP.b #!Battle_NumEnemies
    BCS .end
    JSR BattleSys_ClearUnkB192
    JMP .react
.end:
    JSR BattleSys_UnkAC5E
    STZ.w !Battle_UnkB2C0
    LDA.b !Battle_Unk24
    BNE .end_no_8c09
    JSR BattleSys_Unk8C09
.end_no_8c09:
    LDA.w !Battle_UnkB3B7
    STA.w !Battle_UnkB18B
    JSR BattleSys_ClearUnkB192
    JSR BattleSys_UnkAC46
    JSL BattleFD_UnkACEE
    STZ.w !Battle_UnkB2C0
    RTS

; $C1:883D — BattleSys_Unk883D (37 bytes, $883D–$8861)
; For each PC slot 0-2 whose !Battler_UnkAF0A entry is not $FF: DP $14
; (16-bit) = the slot, BattleSys_UnkB575, then BattleSys_UnkB3F9 with
; X = the slot. The same loop as BattleSys_Main's wait-mode path; what
; the two callees do is not traced.
; Callers: BattleSys_Unk8461 ($C1:860A). xref also lists a BRL decoded at
;   $C1:B78C (unmatched, DOUBTFUL: inside another instruction or data).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0 (as assumed after the callees), DP=0, DB=$7E; A, X
;        clobbered (Y as the callees leave it); DP $14/$15 and
;        !Battle_UnkAE5A (3) written, plus whatever the callees change
; Callees: BattleSys_UnkB575, BattleSys_UnkB3F9
BattleSys_Unk883D:
    TDC
    STZ.w !Battle_UnkAE5A
.pc:
    TAX
    LDA.w !Battler_UnkAF0A,X
    CMP.b #!Battle_EntryNone
    BEQ .next
    STX.b !BattleTmp_14
    JSR BattleSys_UnkB575
    TDC
    LDA.w !Battle_UnkAE5A
    TAX
    JSR BattleSys_UnkB3F9
.next:
    TDC
    INC.w !Battle_UnkAE5A
    LDA.w !Battle_UnkAE5A
    CMP.b #!Battle_NumPcSlots
    BCC .pc
    RTS

; $C1:8862 — BattleSys_ClearUnkB192 (20 bytes, $8862–$8875)
; Zeroes the 4-byte !Battle_UnkB192 record of battler slot
; !Battle_UnkB18B.
; Callers: BattleSys_Unk8461 ($C1:8816, $C1:882F).
; Entry: M=1, X=0, DP=0 (not used), DB=$7E; !Battle_UnkB18B = slot
;        (0-$3F: the index is slot * 4 in 8 bits)
; Exit:  M=1, X=0, DP and DB unchanged; A = 0; X = slot * 4 + 4; Y = 4
BattleSys_ClearUnkB192:
    TDC
    TAY
    LDA.w !Battle_UnkB18B
    ASL A
    ASL A
    TAX
    TDC
.clear:
    STA.w !Battle_UnkB192,X
    INX
    INY
    CPY.w #!Battle_UnkB192Size
    BCC .clear
    RTS

; $C1:8876 — BattleSys_ListHandler0 (79 bytes, $8876–$88C4)
; Turn list 0 (BattleSys_ListHandlerTable entry 0): the usual handler
; (see the banner); at the end of its runs it clears BattlerStats.Status2
; bit 7 of the slot.
; Callers: none by call; entry 0 of BattleSys_ListHandlerTable.
; Entry: M=1, X=0, DP=0 (TDC loads A = 0 for the B=0 TAX/TAY), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A = the runs left (B=0), 0 after
;        the last run; X = the list's !Battle_SlotOrder
;        position, or slot * $80 after the last run; Y = the slot; the list's
;        !Battle_ListDue bit cleared and its entries for the slot
;        changed as above
BattleSys_ListHandler0:
    TDC
    LDX.w #0
    LDA.w !Battle_ListCursor,X
    BNE .cursor_ok
    LDA.w !Battle_BattlerCount
.cursor_ok:
    DEC A
    TAX
    LDA.w !Battle_SlotOrder,X
    TAY
    LDA.b #1
    STA.w !Battle_ListFlags,Y
    LDA.w !Battle_ListReload,Y
    STA.w !Battle_ListTimers,Y
    REP #$20
    LDA.w !Battle_ListDue
    AND.w #!Battle_ListDueAll^(!Battle_ListBit0>>0)
    STA.w !Battle_ListDue
    TDC
    SEP #$20
    LDA.w !Battle_ListRuns,Y
    DEC A
    STA.w !Battle_ListRuns,Y
    BNE .done
    LDA.b #!Battle_ListRunsReset
    STA.w !Battle_ListRuns,Y
    TYA
    REP #$20
    XBA
    LSR A
    TAX                                 ; X = slot * $80
    TDC
    SEP #$20
    LDA.w BattlerStats.Status2,X
    AND.b #!Battle_List0StatusBit^$FF
    STA.w BattlerStats.Status2,X
    TDC
    STA.w !Battle_ListFlags,Y
.done:
    RTS

; $C1:88C5 — BattleSys_ListHandler1 (150 bytes, $88C5–$895A)
; Turn list 1: a repeating hit on the slot (inferred from the amount
; going to !Battle_ActPcHitAmount with kind 3, which
; BattleAct_FlagLethalPcHits checks as damage; probably poison). Skipped
; while the slot is KO'd (Status bit 7) or its BattlerStats.Status2
; bit 6 is clear; then the entry stays due and only the list's
; !Battle_ListDue bit is cleared. Else: flags = 1, timer = reload +
; BattlerStats.Unk64; amount = MaxHp / (Unk64 / 2 + 8) through
; Battle_Div32 into !Battle_UnkAD89, slot in !Battle_UnkB1FD,
; BattleSys_UnkE89F; the amount and kind 3 go into the
; !Battle_ActPcHit* record at the offset in DP $0E (probably left by
; BattleSys_UnkE89F); !Battle_UnkB202 = 0, BattleSys_UnkEBF8,
; BattleSys_Unk895B with A = $7F, BattleFD_UnkACEE. No run count: the
; entry never ends here.
; Quirk: only the low byte of the divisor !Battle_MathB is written and
; !Battle_MathHi (the dividend's high word) not at all, so the divide
; uses what earlier math left there.
; Callers: none by call; entry 1 of BattleSys_ListHandlerTable.
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0 (as assumed after the callees), DP=0, DB=$7E; A = 0;
;        X, Y clobbered; DP $10 = slot * $80; on the hit path the math DP
;        bytes, !Battle_UnkAD89/B1FD/B202 and whatever the callees change
BattleSys_ListHandler1:
    TDC
    LDX.w #1
    LDA.w !Battle_ListCursor,X
    BNE .cursor_ok
    LDA.w !Battle_BattlerCount
.cursor_ok:
    DEC A
    TAX
    LDA.w !Battle_SlotOrder,X
    TAY
    REP #$20
    XBA
    LSR A
    TAX                                 ; X = slot * $80
    STA.b !BattleTmp_10
    TDC
    SEP #$20
    LDA.w BattlerStats.Status,X
    BIT.b #!Battle_StatusKo
    BEQ .alive
    JMP .done
.alive:
    LDA.w BattlerStats.Status2,X
    BIT.b #!Battle_List1StatusBit
    BNE .hit
    JMP .done
.hit:
    LDA.b #1
    STA.w !Battle_ListFlags+(!Battle_NumSlots*1),Y
    LDA.w !Battle_ListReload+(!Battle_NumSlots*1),Y
    CLC
    ADC.w BattlerStats.Unk64,X
    STA.w !Battle_ListTimers+(!Battle_NumSlots*1),Y
    TDC
    LDA.w BattlerStats.Unk64,X
    LSR A
    CLC
    ADC.b #!Battle_List1DivBase
    STA.b !Battle_MathB
    LDA.w BattlerStats.MaxHp,X
    STA.b !Battle_MathA
    LDA.w BattlerStats.MaxHp+1,X
    STA.b !Battle_MathA+1
    JSR Battle_Div32
    LDX.b !Battle_MathLo
    STX.w !Battle_UnkAD89
    TYA
    STA.w !Battle_UnkB1FD
    JSR BattleSys_UnkE89F
    REP #$20
    LDA.w !Battle_UnkAD89
    LDX.b !BattleTmp_0E
    STA.w !Battle_ActPcHitAmount,X
    TDC
    SEP #$20
    LDA.b #!Battle_List1HitKind
    LDX.b !BattleTmp_0E
    STA.w !Battle_ActPcHitKind,X
    LDA.b #0
    STA.w !Battle_UnkB202
    JSR BattleSys_UnkEBF8
    LDA.b #!Battle_ListHitActId
    JSR BattleSys_Unk895B
    JSL BattleFD_UnkACEE
.done:
    REP #$20
    LDA.w !Battle_ListDue
    AND.w #!Battle_ListDueAll^(!Battle_ListBit0>>1)
    STA.w !Battle_ListDue
    TDC
    SEP #$20
    RTS

; $C1:895B — BattleSys_Unk895B (26 bytes, $895B–$8974)
; Sets up the action block for a kind-2 action (BattleAct_LoaderTable's
; loader 2; the tech loader, inferred in !Battle_ActId's note) with
; record A, caster slot 0, no flags and the main-target mask
; !Battle_ActMainMask = $8000 (bit 15: slot 0), then
; BattleSys_UnkAC57 (not traced; probably runs it).
; Callers: BattleSys_Main ($C1:820F), BattleSys_ListHandler1 ($C1:8945),
;   BattleSys_ListHandler9 ($C1:8BB1).
; Entry: M=1, X=0, DP=0 (not used here), DB=$7E; A = the action record
; Exit:  M=1, X=0 as assumed after BattleSys_UnkAC57 (not analysed);
;        DP=0, DB=$7E; !Battle_ActId/Caster/Kind/Flags and !Battle_ActMainMask
;        written, plus whatever BattleSys_UnkAC57 changes
BattleSys_Unk895B:
    STA.w !Battle_ActId
    STZ.w !Battle_ActCaster
    LDA.b #2
    STA.w !Battle_ActKind
    STZ.w !Battle_ActFlags
    STZ.w !Battle_ActMainMask
    LDA.b #!Battle_ActMainMaskSlot0Hi
    STA.w !Battle_ActMainMask+1
    JSR BattleSys_UnkAC57
    RTS

; $C1:8975 — BattleSys_ListHandler2 (68 bytes, $8975–$89B8)
; Turn list 2: the usual handler, but after its last run it only stops
; the entry: no status bit is cleared.
; Quirk: it still computes X = slot * $80 there and does not use it.
; Callers: none by call; entry 2 of BattleSys_ListHandlerTable.
; Entry: M=1, X=0, DP=0 (TDC loads A = 0 for the B=0 TAX/TAY), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A = the runs left (B=0), 0 after
;        the last run; X = the list's !Battle_SlotOrder
;        position, or slot * $80 after the last run; Y = the slot; the list's
;        !Battle_ListDue bit cleared and its entries for the slot
;        changed as above
BattleSys_ListHandler2:
    TDC
    LDA.w !Battle_ListCursor+2
    BNE .cursor_ok
    LDA.w !Battle_BattlerCount
.cursor_ok:
    DEC A
    TAX
    LDA.w !Battle_SlotOrder,X
    TAY
    LDA.b #1
    STA.w !Battle_ListFlags+(!Battle_NumSlots*2),Y
    LDA.w !Battle_ListReload+(!Battle_NumSlots*2),Y
    STA.w !Battle_ListTimers+(!Battle_NumSlots*2),Y
    REP #$20
    LDA.w !Battle_ListDue
    AND.w #!Battle_ListDueAll^(!Battle_ListBit0>>2)
    STA.w !Battle_ListDue
    TDC
    SEP #$20
    LDA.w !Battle_ListRuns+(!Battle_NumSlots*2),Y
    DEC A
    STA.w !Battle_ListRuns+(!Battle_NumSlots*2),Y
    BNE .done
    LDA.b #!Battle_ListRunsReset
    STA.w !Battle_ListRuns+(!Battle_NumSlots*2),Y
    TYA
    REP #$20
    XBA
    LSR A
    TAX                                 ; X = slot * $80, unused (quirk)
    TDC
    SEP #$20
    TDC
    STA.w !Battle_ListFlags+(!Battle_NumSlots*2),Y
.done:
    RTS

; $C1:89B9 — BattleSys_ListHandler3 (76 bytes, $89B9–$8A04)
; Turn list 3: the usual handler; at the end of its runs it clears bit 7
; of the slot's BattlerStats.Unk4C+1 (+$4D).
; Callers: none by call; entry 3 of BattleSys_ListHandlerTable.
; Entry: M=1, X=0, DP=0 (TDC loads A = 0 for the B=0 TAX/TAY), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A = the runs left (B=0), 0 after
;        the last run; X = the list's !Battle_SlotOrder
;        position, or slot * $80 after the last run; Y = the slot; the list's
;        !Battle_ListDue bit cleared and its entries for the slot
;        changed as above
BattleSys_ListHandler3:
    TDC
    LDA.w !Battle_ListCursor+3
    BNE .cursor_ok
    LDA.w !Battle_BattlerCount
.cursor_ok:
    DEC A
    TAX
    LDA.w !Battle_SlotOrder,X
    TAY
    LDA.b #1
    STA.w !Battle_ListFlags+(!Battle_NumSlots*3),Y
    LDA.w !Battle_ListReload+(!Battle_NumSlots*3),Y
    STA.w !Battle_ListTimers+(!Battle_NumSlots*3),Y
    REP #$20
    LDA.w !Battle_ListDue
    AND.w #!Battle_ListDueAll^(!Battle_ListBit0>>3)
    STA.w !Battle_ListDue
    TDC
    SEP #$20
    LDA.w !Battle_ListRuns+(!Battle_NumSlots*3),Y
    DEC A
    STA.w !Battle_ListRuns+(!Battle_NumSlots*3),Y
    BNE .done
    LDA.b #!Battle_ListRunsReset
    STA.w !Battle_ListRuns+(!Battle_NumSlots*3),Y
    TYA
    REP #$20
    XBA
    LSR A
    TAX                                 ; X = slot * $80
    TDC
    SEP #$20
    LDA.w BattlerStats.Unk4C+1,X
    AND.b #!Battle_List3StatusBit^$FF
    STA.w BattlerStats.Unk4C+1,X
    TDC
    STA.w !Battle_ListFlags+(!Battle_NumSlots*3),Y
.done:
    RTS

; $C1:8A05 — BattleSys_ListHandler4 (76 bytes, $8A05–$8A50)
; Turn list 4: the usual handler; at the end of its runs it clears bit 6
; of the slot's BattlerStats.Unk4C+1 (+$4D).
; Callers: none by call; entry 4 of BattleSys_ListHandlerTable.
; Entry: M=1, X=0, DP=0 (TDC loads A = 0 for the B=0 TAX/TAY), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A = the runs left (B=0), 0 after
;        the last run; X = the list's !Battle_SlotOrder
;        position, or slot * $80 after the last run; Y = the slot; the list's
;        !Battle_ListDue bit cleared and its entries for the slot
;        changed as above
BattleSys_ListHandler4:
    TDC
    LDA.w !Battle_ListCursor+4
    BNE .cursor_ok
    LDA.w !Battle_BattlerCount
.cursor_ok:
    DEC A
    TAX
    LDA.w !Battle_SlotOrder,X
    TAY
    LDA.b #1
    STA.w !Battle_ListFlags+(!Battle_NumSlots*4),Y
    LDA.w !Battle_ListReload+(!Battle_NumSlots*4),Y
    STA.w !Battle_ListTimers+(!Battle_NumSlots*4),Y
    REP #$20
    LDA.w !Battle_ListDue
    AND.w #!Battle_ListDueAll^(!Battle_ListBit0>>4)
    STA.w !Battle_ListDue
    TDC
    SEP #$20
    LDA.w !Battle_ListRuns+(!Battle_NumSlots*4),Y
    DEC A
    STA.w !Battle_ListRuns+(!Battle_NumSlots*4),Y
    BNE .done
    LDA.b #!Battle_ListRunsReset
    STA.w !Battle_ListRuns+(!Battle_NumSlots*4),Y
    TYA
    REP #$20
    XBA
    LSR A
    TAX                                 ; X = slot * $80
    TDC
    SEP #$20
    LDA.w BattlerStats.Unk4C+1,X
    AND.b #!Battle_List4StatusBit^$FF
    STA.w BattlerStats.Unk4C+1,X
    TDC
    STA.w !Battle_ListFlags+(!Battle_NumSlots*4),Y
.done:
    RTS

; $C1:8A51 — BattleSys_ListHandler5 (76 bytes, $8A51–$8A9C)
; Turn list 5: the usual handler; at the end of its runs it clears bit 6
; of the slot's BattlerStats.Unk4C+2 (+$4E).
; Callers: none by call; entry 5 of BattleSys_ListHandlerTable.
; Entry: M=1, X=0, DP=0 (TDC loads A = 0 for the B=0 TAX/TAY), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A = the runs left (B=0), 0 after
;        the last run; X = the list's !Battle_SlotOrder
;        position, or slot * $80 after the last run; Y = the slot; the list's
;        !Battle_ListDue bit cleared and its entries for the slot
;        changed as above
BattleSys_ListHandler5:
    TDC
    LDA.w !Battle_ListCursor+5
    BNE .cursor_ok
    LDA.w !Battle_BattlerCount
.cursor_ok:
    DEC A
    TAX
    LDA.w !Battle_SlotOrder,X
    TAY
    LDA.b #1
    STA.w !Battle_ListFlags+(!Battle_NumSlots*5),Y
    LDA.w !Battle_ListReload+(!Battle_NumSlots*5),Y
    STA.w !Battle_ListTimers+(!Battle_NumSlots*5),Y
    REP #$20
    LDA.w !Battle_ListDue
    AND.w #!Battle_ListDueAll^(!Battle_ListBit0>>5)
    STA.w !Battle_ListDue
    TDC
    SEP #$20
    LDA.w !Battle_ListRuns+(!Battle_NumSlots*5),Y
    DEC A
    STA.w !Battle_ListRuns+(!Battle_NumSlots*5),Y
    BNE .done
    LDA.b #!Battle_ListRunsReset
    STA.w !Battle_ListRuns+(!Battle_NumSlots*5),Y
    TYA
    REP #$20
    XBA
    LSR A
    TAX                                 ; X = slot * $80
    TDC
    SEP #$20
    LDA.w BattlerStats.Unk4C+2,X
    AND.b #!Battle_List5StatusBit^$FF
    STA.w BattlerStats.Unk4C+2,X
    TDC
    STA.w !Battle_ListFlags+(!Battle_NumSlots*5),Y
.done:
    RTS

; $C1:8A9D — BattleSys_ListHandler6 (1 byte)
; Turn list 6: does nothing (RTS). The list's !Battle_ListDue bit is not
; cleared and its entries stay due.
; Callers: none by call; entry 6 of BattleSys_ListHandlerTable.
; Entry: M=1, X=0, DP=0, DB=$7E (nothing used)
; Exit:  nothing changed
BattleSys_ListHandler6:
    RTS

; $C1:8A9E — BattleSys_ListHandler7 (1 byte)
; Turn list 7: does nothing (RTS), like list 6.
; Callers: none by call; entry 7 of BattleSys_ListHandlerTable.
; Entry: M=1, X=0, DP=0, DB=$7E (nothing used)
; Exit:  nothing changed
BattleSys_ListHandler7:
    RTS

; $C1:8A9F — BattleSys_ListHandler8 (113 bytes, $8A9F–$8B0F)
; Turn list 8: re-arms the entry (flags = 1) with the timer = reload,
; halved when bit 7 of the slot's BattlerStats.Unk4C+1 or Unk4C+6
; (+$4D, +$52) is set, doubled (from the reload, so this wins) when
; Status2 bit 5 is set (probably haste / slow; not traced); clears the
; list's !Battle_ListDue bit; then, with Status2 bit 4 set:
; !Battle_UnkAD89 = 1, !Battle_UnkB1FD = slot, !Battle_UnkB202 = 0,
; BattleSys_UnkEBF8 and BattleSys_UnkEC7F. No run count.
; Callers: none by call; entry 8 of BattleSys_ListHandlerTable.
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0 (as assumed after the callees), DP=0, DB=$7E; A, X
;        clobbered; Y = the slot; DP $10 = slot * $80; with bit 4 set
;        !Battle_UnkAD89/B1FD/B202 and whatever the callees change
BattleSys_ListHandler8:
    TDC
    LDX.w #8
    LDA.w !Battle_ListCursor,X
    BNE .cursor_ok
    LDA.w !Battle_BattlerCount
.cursor_ok:
    DEC A
    TAX
    LDA.w !Battle_SlotOrder,X
    TAY
    REP #$20
    XBA
    LSR A
    TAX                                 ; X = slot * $80
    STA.b !BattleTmp_10
    TDC
    SEP #$20
    LDA.b #1
    STA.w !Battle_ListFlags+(!Battle_NumSlots*8),Y
    LDA.w !Battle_ListReload+(!Battle_NumSlots*8),Y
    STA.w !Battle_ListTimers+(!Battle_NumSlots*8),Y
    LDA.w BattlerStats.Unk4C+1,X
    ORA.w BattlerStats.Unk4C+6,X
    BIT.b #!Battle_ListHalveBit
    BEQ .not_halved
    LDA.w !Battle_ListReload+(!Battle_NumSlots*8),Y
    LSR A
    STA.w !Battle_ListTimers+(!Battle_NumSlots*8),Y
.not_halved:
    LDA.w BattlerStats.Status2,X
    BIT.b #!Battle_ListDoubleBit
    BEQ .not_doubled
    LDA.w !Battle_ListReload+(!Battle_NumSlots*8),Y
    ASL A
    STA.w !Battle_ListTimers+(!Battle_NumSlots*8),Y
.not_doubled:
    REP #$20
    LDA.w !Battle_ListDue
    AND.w #!Battle_ListDueAll^(!Battle_ListBit0>>8)
    STA.w !Battle_ListDue
    TDC
    SEP #$20
    LDA.w BattlerStats.Status2,X
    BIT.b #!Battle_List8StatusBit
    BEQ .done
    LDX.w #!Battle_List8Amount
    STX.w !Battle_UnkAD89
    TYA
    STA.w !Battle_UnkB1FD
    LDA.b #0
    STA.w !Battle_UnkB202
    JSR BattleSys_UnkEBF8
    JSR BattleSys_UnkEC7F
.done:
    RTS

; $C1:8B10 — BattleSys_ListHandler9 (169 bytes, $8B10–$8BB8)
; Turn list 9: re-arms the entry with the timer halved / doubled as list
; 8 does, clears the list's !Battle_ListDue bit and counts
; !Battle_ListRuns down; at 0 (set back to 10), unless the slot is KO'd,
; with bit 5 of its BattlerStats.Unk4C+2 or Unk4C+7 (+$4E, +$53) set:
; amount 5 in !Battle_UnkAD89, slot in !Battle_UnkB1FD,
; BattleSys_UnkE89F; !Battle_UnkAD89 and kind 2 go into the
; !Battle_ActPcHit* record at the offset in DP $0E; !Battle_UnkB202 =
; $C0, BattleSys_UnkEBF8, BattleSys_Unk895B with A = $7F,
; BattleFD_UnkACEE (the same tail as list 1's hit, other kind; probably
; a heal over time). The entry is never stopped here.
; Quirk: the halving test loads Unk4C+1 and then overwrites it with
; Unk4C+6 (list 8 ORs the two), so only Unk4C+6 bit 7 halves the timer.
; Callers: none by call; entry 9 of BattleSys_ListHandlerTable.
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0 (as assumed after the callees), DP=0, DB=$7E; A, X
;        clobbered; Y = the slot; DP $10 = slot * $80; on the hit path
;        !Battle_UnkAD89/B1FD/B202 and whatever the callees change
BattleSys_ListHandler9:
    TDC
    LDX.w #!Battle_ListIndex9
    LDA.w !Battle_ListCursor,X
    BNE .cursor_ok
    LDA.w !Battle_BattlerCount
.cursor_ok:
    DEC A
    TAX
    LDA.w !Battle_SlotOrder,X
    TAY
    REP #$20
    XBA
    LSR A
    TAX                                 ; X = slot * $80
    STA.b !BattleTmp_10
    TDC
    SEP #$20
    LDA.b #1
    STA.w !Battle_ListFlags+(!Battle_NumSlots*9),Y
    LDA.w !Battle_ListReload+(!Battle_NumSlots*9),Y
    STA.w !Battle_ListTimers+(!Battle_NumSlots*9),Y
    LDA.w BattlerStats.Unk4C+1,X        ; quirk: overwritten by the next load
    LDA.w BattlerStats.Unk4C+6,X
    BIT.b #!Battle_ListHalveBit
    BEQ .not_halved
    LDA.w !Battle_ListReload+(!Battle_NumSlots*9),Y
    LSR A
    STA.w !Battle_ListTimers+(!Battle_NumSlots*9),Y
.not_halved:
    LDA.w BattlerStats.Status2,X
    BIT.b #!Battle_ListDoubleBit
    BEQ .not_doubled
    LDA.w !Battle_ListReload+(!Battle_NumSlots*9),Y
    ASL A
    STA.w !Battle_ListTimers+(!Battle_NumSlots*9),Y
.not_doubled:
    REP #$20
    LDA.w !Battle_ListDue
    AND.w #!Battle_ListDueAll^(!Battle_ListBit0>>9)
    STA.w !Battle_ListDue
    TDC
    SEP #$20
    LDA.w !Battle_ListRuns+(!Battle_NumSlots*9),Y
    DEC A
    STA.w !Battle_ListRuns+(!Battle_NumSlots*9),Y
    BNE .done
    LDA.b #!Battle_ListRunsReset
    STA.w !Battle_ListRuns+(!Battle_NumSlots*9),Y
    LDA.w BattlerStats.Status,X
    BIT.b #!Battle_StatusKo
    BEQ .alive
    JMP .done
.alive:
    LDA.w BattlerStats.Unk4C+2,X
    ORA.w BattlerStats.Unk4C+7,X
    BIT.b #!Battle_List9StatusBit
    BEQ .done
    LDX.w #!Battle_List9Amount
    STX.w !Battle_UnkAD89
    TYA
    STA.w !Battle_UnkB1FD
    JSR BattleSys_UnkE89F
    REP #$20
    LDA.w !Battle_UnkAD89
    LDX.b !BattleTmp_0E
    STA.w !Battle_ActPcHitAmount,X
    TDC
    SEP #$20
    LDA.b #!Battle_List9HitKind
    LDX.b !BattleTmp_0E
    STA.w !Battle_ActPcHitKind,X
    LDA.b #!Battle_List9UnkB202
    STA.w !Battle_UnkB202
    JSR BattleSys_UnkEBF8
    LDA.b #!Battle_ListHitActId
    JSR BattleSys_Unk895B
    JSL BattleFD_UnkACEE
.done:
    RTS

; $C1:8BB9 — BattleSys_ListHandler10 (79 bytes, $8BB9–$8C07)
; Turn list 10: the usual handler; at the end of its runs it clears
; bit 2 of the slot's BattlerStats.Unk4C+2 (+$4E).
; Callers: none by call; entry 10 of BattleSys_ListHandlerTable.
; Entry: M=1, X=0, DP=0 (TDC loads A = 0 for the B=0 TAX/TAY), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A = the runs left (B=0), 0 after
;        the last run; X = the list's !Battle_SlotOrder
;        position, or slot * $80 after the last run; Y = the slot; the list's
;        !Battle_ListDue bit cleared and its entries for the slot
;        changed as above
BattleSys_ListHandler10:
    TDC
    LDX.w #!Battle_ListIndex10
    LDA.w !Battle_ListCursor,X
    BNE .cursor_ok
    LDA.w !Battle_BattlerCount
.cursor_ok:
    DEC A
    TAX
    LDA.w !Battle_SlotOrder,X
    TAY
    LDA.b #1
    STA.w !Battle_ListFlags+(!Battle_NumSlots*10),Y
    LDA.w !Battle_ListReload+(!Battle_NumSlots*10),Y
    STA.w !Battle_ListTimers+(!Battle_NumSlots*10),Y
    REP #$20
    LDA.w !Battle_ListDue
    AND.w #!Battle_ListDueAll^(!Battle_ListBit0>>10)
    STA.w !Battle_ListDue
    TDC
    SEP #$20
    LDA.w !Battle_ListRuns+(!Battle_NumSlots*10),Y
    DEC A
    STA.w !Battle_ListRuns+(!Battle_NumSlots*10),Y
    BNE .done
    LDA.b #!Battle_ListRunsReset
    STA.w !Battle_ListRuns+(!Battle_NumSlots*10),Y
    TYA
    REP #$20
    XBA
    LSR A
    TAX                                 ; X = slot * $80
    TDC
    SEP #$20
    LDA.w BattlerStats.Unk4C+2,X
    AND.b #!Battle_List10StatusBit^$FF
    STA.w BattlerStats.Unk4C+2,X
    TDC
    STA.w !Battle_ListFlags+(!Battle_NumSlots*10),Y
.done:
    RTS

; $C1:8C08 — BattleSys_ListHandler11 (1 byte)
; Turn list 11: does nothing (RTS), like lists 6 and 7.
; Callers: none by call; entry 11 of BattleSys_ListHandlerTable.
; Entry: M=1, X=0, DP=0, DB=$7E (nothing used)
; Exit:  nothing changed
BattleSys_ListHandler11:
    RTS

; $C1:8C09 — BattleSys_Unk8C09 (53 bytes, $8C09–$8C3D)
; Runs BattleSys_UnkAFD2 (probably an enemy's behaviour script: it reads a
; pointer from the $CC:8B08 table by the id in A) for each enemy entry
; 0-7 with !Battle_UnkB2B6 0 whose !Battle_UnkAF15 has bit 7 set or
; whose !Battler_UnkAEFF entry is present, with A = that
; !Battler_UnkAEFF entry (possibly $FF when bit 7 is set). Before each,
; that entry's !Battle_UnkB24A and !Battle_UnkB263 are zeroed and
; !Battle_UnkB1CF = 0. !Battle_UnkB252 is the loop's enemy index.
; Callers: BattleSys_Main ($C1:80E8), BattleSys_Unk8461 ($C1:8826).
; Entry: M=1, X=0, DP=0 (not used), DB=$7E
; Exit:  M=1, X=0 (as assumed after BattleSys_UnkAFD2), DP=0, DB=$7E; A = 8;
;        X clobbered; !Battle_UnkB252 = 8, plus whatever
;        BattleSys_UnkAFD2 changes
BattleSys_Unk8C09:
    STZ.w !Battle_UnkB252
.enemy:
    TDC
    STA.w !Battle_UnkB1CF
    LDA.w !Battle_UnkB252
    TAX
    STZ.w !Battle_UnkB24A,X
    STZ.w !Battle_UnkB263,X
    LDA.w !Battle_UnkAF15,X
    BIT.b #!Battle_AF15Bit7
    BNE .check_b2b6
    LDA.w !Battler_UnkAEFF+!Battle_FirstEnemySlot,X
    CMP.b #!Battle_EntryNone
    BEQ .next
.check_b2b6:
    LDA.w !Battle_UnkB2B6,X
    BNE .next
    LDA.w !Battler_UnkAEFF+!Battle_FirstEnemySlot,X
    JSR BattleSys_UnkAFD2
.next:
    INC.w !Battle_UnkB252
    LDA.w !Battle_UnkB252
    CMP.b #!Battle_NumEnemies
    BCC .enemy
    RTS

; ==================================================================
; Random range and 16-bit math ($C1:AF22–$C1:AF78, $C1:C90B–$C1:C95B)
; ==================================================================
; Direct-page arithmetic on !Battle_MathA ($28) .. !Battle_MathRem ($32),
; used all over the part of the bank from $C1:8000 on.

; $C1:AF22 — Battle_RandRange (87 bytes, $AF22–$AF78)
; A random number from the low bound X (low byte) up to, but not
; including, the high bound A: low + (RandomTableFD[!Battle_RandIdx]
; mod (high - low)), then !Battle_RandIdx + 1. Special cases, in order:
;   - low = $FF: returns A as it came (the high bound);
;   - !Battle_Unk2989 bit 5 set: returns the low bound;
;   - high = 0: returns 0; high = low: returns that value;
;   - high - low = $FF: returns RandomTableFD[!Battle_RandIdx] without
;     adding the low bound and without advancing !Battle_RandIdx
;     (quirk: so 0-255, not low..low+$FE).
; Quirks: Battle_Div32 divides the 32-bit !Battle_MathHi:MathA, and this
; routine sets only !Battle_MathA, so whatever !Battle_MathHi holds
; takes part (the result stays below high - low all the same). A high
; bound below the low one is not handled (the subtraction wraps).
; Callers: 37 JSR sites, e.g. BattleSys_Main ($C1:807B, $C1:80B1) and
;   unmatched code from $C1:8DE8 on (xref).
; Entry: M=1, X any (only X's low byte is used), DP=0, DB=$7E; A = high
;        bound, X = low bound
; Exit:  M=1, X=0; A = the number; X = !Battle_MathLo (saved and put
;        back); Y unchanged; !Battle_RandMin and !Battle_UnkB31E written;
;        on the divide path !Battle_RandIdx advanced and !Battle_MathA,
;        MathB, MathHi and MathRem changed (Battle_Div32; MathLo is
;        saved and put back)
; Callee: Battle_Div32
org $C1AF22
Battle_RandRange:
    SEP #$10
    STX.b !Battle_RandMin
    REP #$10
    LDX.b !Battle_MathLo
    PHX
    SEP #$10
    LDX.b !Battle_RandMin
    CPX.b #!Battle_EntryNone
    BNE .bounds
    BRA .done
.bounds:
    STA.w !Battle_UnkB31E
    LDA.w !Battle_Unk2989
    BIT.b #!Battle_2989Bit5
    BEQ .random
    TXA                                 ; bit 5: the low bound
    BRA .done
.random:
    LDA.w !Battle_UnkB31E
    CMP.b #0
    BEQ .done
    CMP.b !Battle_RandMin
    BEQ .done
    LDX.b !Battle_RandIdx
    SEC
    SBC.b !Battle_RandMin
    CMP.b #!Battle_RandFullRange
    BNE .divide
    LDA.l RandomTableFD,X               ; range 256: the raw byte
    BRA .done
.divide:
    STA.b !Battle_MathB
    STZ.b !Battle_MathB+1
    LDA.l RandomTableFD,X
    TAX
    STX.b !Battle_MathA
    STZ.b !Battle_MathA+1
    JSR Battle_Div32
    LDA.b !Battle_MathRem
    CLC
    ADC.b !Battle_RandMin
    INC.b !Battle_RandIdx
.done:
    REP #$10
    PLX
    STX.b !Battle_MathLo
    RTS

; ==================================================================
; Turn-list tables ($C1:B92D–$C1:B960)
; ==================================================================

; $C1:B92D — BattleSys_ListHandlerTable (13 words, $B92D–$B946)
; Handler of each turn list, indexed by list number * 2:
; BattleSys_Main runs entry n (JSR (T,X) at $C1:8333) for each list
; whose !Battle_ListDue bit is set. Entries 6, 7 and 11 are bare RTSs.
org $C1B92D
BattleSys_ListHandlerTable:
    dw BattleSys_ListHandler0           ; $00
    dw BattleSys_ListHandler1           ; $01
    dw BattleSys_ListHandler2           ; $02
    dw BattleSys_ListHandler3           ; $03
    dw BattleSys_ListHandler4           ; $04
    dw BattleSys_ListHandler5           ; $05
    dw BattleSys_ListHandler6           ; $06
    dw BattleSys_ListHandler7           ; $07
    dw BattleSys_ListHandler8           ; $08
    dw BattleSys_ListHandler9           ; $09
    dw BattleSys_ListHandler10          ; $0A
    dw BattleSys_ListHandler11          ; $0B
    dw BattleSys_Unk8461                ; $0C: the battlers' turns

; $C1:B947 — BattleSys_ListOffsetTable (13 words, $B947–$B960)
; Address of each turn list's !Battle_ListFlags bytes (list * 11 past
; the start), indexed by list number * 2; BattleSys_Main's scan reads it
; with LDA.l at $C1:82C5.
BattleSys_ListOffsetTable:
    dw !Battle_ListFlags+(!Battle_NumSlots*0)
    dw !Battle_ListFlags+(!Battle_NumSlots*1)
    dw !Battle_ListFlags+(!Battle_NumSlots*2)
    dw !Battle_ListFlags+(!Battle_NumSlots*3)
    dw !Battle_ListFlags+(!Battle_NumSlots*4)
    dw !Battle_ListFlags+(!Battle_NumSlots*5)
    dw !Battle_ListFlags+(!Battle_NumSlots*6)
    dw !Battle_ListFlags+(!Battle_NumSlots*7)
    dw !Battle_ListFlags+(!Battle_NumSlots*8)
    dw !Battle_ListFlags+(!Battle_NumSlots*9)
    dw !Battle_ListFlags+(!Battle_NumSlots*10)
    dw !Battle_ListFlags+(!Battle_NumSlots*11)
    dw !Battle_ListFlags+(!Battle_NumSlots*12)

; $C1:C90B — Battle_Mul16 (31 bytes, $C90B–$C929)
; 16 x 16 -> 32-bit unsigned shift-and-add multiply:
; !Battle_MathHi:MathLo = !Battle_MathA * !Battle_MathB. MathB is
; shifted out on the way (it ends as garbage; its first shift takes in
; the caller's carry).
; Callers: 109 JSR sites, e.g. $C1:B329, $C1:B455, $C1:B4BC and
;   Battle_SetupBattle (xref; nearly all in unmatched code).
; Entry: M any, X=0 (LDX #16 is a 3-byte immediate), DP=0, DB any
; Exit:  M=1, X=0; A = 0, X = 0, Y unchanged; !Battle_MathLo/Hi = the
;        product, !Battle_MathB clobbered, !Battle_MathA unchanged
org $C1C90B
Battle_Mul16:
    REP #$20
    LDX.w #!Battle_Mul16Steps
    STZ.b !Battle_MathLo
    STZ.b !Battle_MathHi
.bit:
    ROR.b !Battle_MathB
    BCC .shift
    CLC
    LDA.b !Battle_MathA
    ADC.b !Battle_MathHi
    STA.b !Battle_MathHi
.shift:
    ROR.b !Battle_MathHi
    ROR.b !Battle_MathLo
    DEX
    BNE .bit
    TDC
    SEP #$20
    RTS

; $C1:C92A — Battle_Div32 (50 bytes, $C92A–$C95B)
; 32 / 16-bit unsigned restoring divide of !Battle_MathHi:MathA by
; !Battle_MathB: !Battle_MathRem = the remainder, !Battle_MathLo = the
; quotient's low word. The three words MathA, MathHi and MathRem are
; shifted as one 48-bit value, with each quotient bit rolled into
; MathLo and MathLo's top bit carried into MathA, 32 times.
; Quirks: if the low word !Battle_MathA or the divisor is 0, nothing is
; divided and quotient and remainder are 0 (even with MathHi non-zero).
; After the loop MathA holds quotient bits 1-15 (high word >> 1; bit 16
; is lost in the carry), and MathHi holds the caller's carry in bit 15
; (it is shifted in first), not usable results. The remainder is kept
; in 16 bits, so a divisor of $8000 or more can give wrong results.
; Callers: 59 JSR sites, e.g. $C1:8918, Battle_RandRange ($C1:AF69),
;   $C1:AFC1 and Battle_SetupBattle (xref; mostly unmatched code).
; Entry: M any, X any, DP=0, DB any; the caller's carry goes in as said
; Exit:  P restored (PLP: M, X and the flags as on entry); A = 0;
;        X = 0 after a divide, else unchanged; Y unchanged;
;        !Battle_MathLo, MathRem, MathA and MathHi as above
org $C1C92A
Battle_Div32:
    PHP
    REP #$30
    STZ.b !Battle_MathLo
    STZ.b !Battle_MathRem
    LDA.b !Battle_MathA
    BEQ .done
    LDA.b !Battle_MathB
    BEQ .done
    LDX.w #!Battle_Div32Steps
.bit:
    ROL.b !Battle_MathA
    ROL.b !Battle_MathHi
    ROL.b !Battle_MathRem
    SEC
    LDA.b !Battle_MathRem
    SBC.b !Battle_MathB
    STA.b !Battle_MathRem
    BCS .quotient_bit
    LDA.b !Battle_MathRem               ; did not fit: add it back
    ADC.b !Battle_MathB
    STA.b !Battle_MathRem
    CLC
.quotient_bit:
    ROL.b !Battle_MathLo
    DEX
    BNE .bit
.done:
    TDC
    SEP #$20
    PLP
    RTS

; ==================================================================
; Battle setup ($C1:FA8B–$C1:FDBE)
; ==================================================================

; $C1:FA8B — Battle_SetupBattle (803 bytes, $FA8B–$FDAD)
; BattleSys_Main's first step: builds the battle state before the
; shuffles. Most of the work is in callees that are not analysed (bank
; $FD and the $C1:C96A-$C1:CF15 group); what this routine does itself:
;   - zeroes $400 bytes from BattlerStats[3].Unk2D ($5FAD-$63AC: the
;     enemy records from +$2D on, and $2D bytes past slot 10's);
;   - runs BattleFD_UnkB438 for X = 0 to !Battle_EnemyCount - 1
;     (a count of 0 would run it 256 times);
;   - for each PC: BattleFD_UnkAE52 (Y = PC), then if its
;     BattlerStats.Unk2D is 5, BattlerStats.Unk56 = Battle_CalcUnk56
;     (its .Unk3F);
;   - !Battler_UnkAEFF / !Battler_UnkAF0A of each PC = its !Pc_CharId,
;     or $FF when !Battler_Untargetable or the id is negative;
;     !Battle_PcCount = the PCs taken, !Battle_BattlerCount = it +
;     !Battle_EnemyCount;
;   - clears 18 bytes from BattleCmd (records 0 and 1 and the first
;     four bytes of record 2), !Battle_UnkB188-B18A, !Battle_UnkAD8D,
;     the list state (!Battle_ListBit, !Battle_ListDue, the timers and
;     flags of all 13 lists, !Battle_ListCursor), sets !Battle_UnkAD8E
;     (12 B), !Battle_SlotOrder, !Battle_UnkB16E, !Battle_UnkB158 and
;     !Battler_UnkAFAB (11 B each) to $FF;
;   - .pc_stats, for each PC's stat block (PcStatBlk, at the address in
;     !BattleRom_PcStatBlock: BattlerStats[n].Unk2D): .Unk3E =
;     .Unk37 + .Unk48 + .Unk70, at most $FF; BattleFD_UnkB14D when .Unk4C
;     bit 6 and .Unk4D are set; .Unk3D = (.Unk3A for character ids 1 and
;     2, else .Unk36) + a byte read from bank $CC (see the quirks);
;   - saves the PCs' BattlerStats.MaxHp in !Battle_SavedMaxHp (put back
;     by BattleSys_Main at the end);
;   - for each enemy entry with an id in !Battler_UnkAEFF:
;     !Battle_UnkAE5D bit 7 / bit 6 = byte 1 / byte 0 of its 7-byte
;     record at !BattleRom_EnemyUnk5E04 is non-zero.
; Quirks in .pc_stats: the X it computes from .Unk29 (= BattlerStats.Unk56)
; * 6 + $0262 is overwritten by LDX on both paths before the LDA.l
; $CC0000,X it looks meant for, so that reads $CC:0000 + the block's
; RAM address ($CC:5E2D/5EAD/5F2D); and the 16-bit add of two 8-bit
; values that follows never carries, so its clamp to $FF never runs and
; .Unk3D keeps the low byte of the sum. .Unk70 lies past the $80-byte
; record of the block's own slot (the next slot's +$1D). The +$2D-based
; offsets of PcStatBlk are what the code uses; what the fields hold is
; not traced.
; Callers: BattleSys_Main ($C1:8012).
; Entry: M any, X any (it sets M=1, X=0 itself), DP=0, DB=$7E
; Exit:  M=1, X=0; A, X, Y, DP $00-$13 scratch and !Battle_MathA..MathRem
;        clobbered, plus what the unanalysed callees change
; Callees: BattleFD_UnkB2DE/B22E/B438/B121/AE52/B3FE/AE99/AD09/AEF2/
;          ACEE/B14D/B0D5/B4E7/B7EB/B555/B732/ACFD/B363/B223/AEC4,
;          Battle_CalcUnk56, BattleSys_UnkC96A/CA1A/CCCB/CDFF/CE3A/CF15,
;          Battle_Mul16, BattleSys_UnkB093
!BattleSetup_Idx   = !BattleTmp_00      ; 1-2 B: enemy index; also the stat block kept around BattleFD_UnkB14D
!BattleSetup_Arg02 = !BattleTmp_02      ; 1-2 B: enemy entry for BattleFD_UnkB438, PC for BattleSys_UnkCE3A, record offset
!BattleSetup_Arg04 = !BattleTmp_04      ; 2 B: zeroed before the BattleFD_UnkB438 loop (read by it, probably)
!BattleSetup_Arg06 = !BattleTmp_06      ; 1-2 B: PC for C96A/CA1A/CCCB; first argument of BattleSys_UnkCF15
!BattleSetup_Arg08 = !BattleTmp_08      ; 1-2 B: second argument of BattleSys_UnkCF15
!BattleSetup_Arg0A = !BattleTmp_0A      ; 1-2 B: third argument of BattleSys_UnkCF15
!BattleSetup_Arg0E = !BattleTmp_0E      ; 2 B: address argument of BattleFD_UnkB14D
!BattleSetup_PcOfs = !BattleTmp_10      ; 2 B: PC * 2 in .pc_stats
!BattleSetup_Block = !BattleTmp_12      ; 2 B: the PC's stat block address in .pc_stats
org $C1FA8B
Battle_SetupBattle:
    SEP #$20
    REP #$10
    JSL BattleFD_UnkB2DE
    JSL BattleFD_UnkB22E
    TDC
    TAX
    TAY
.clear_enemy_stats:
    STA.w BattlerStats[3].Unk2D,Y
    INY
    CPY.w #!Battle_NumEnemies*!Battle_StatsStride
    BCC .clear_enemy_stats
    TDC
    TAX
    TAY
    STX.b !BattleSetup_Arg02
    STX.b !BattleSetup_Arg04
.enemy_entry:
    LDX.b !BattleSetup_Arg02
    JSL BattleFD_UnkB438
    INC.b !BattleSetup_Arg02
    LDA.w !Battle_EnemyCount
    CMP.b !BattleSetup_Arg02
    BNE .enemy_entry
    JSL BattleFD_UnkB121
    TDC
    LDY.w #0
    JSL BattleFD_UnkAE52
    LDA.w BattlerStats.Unk2D
    CMP.b #!Battle_StatsUnk2DCalc56
    BNE .pc1
    TDC
    LDA.w BattlerStats.Unk3F
    JSR Battle_CalcUnk56
    STA.w BattlerStats.Unk56
.pc1:
    LDY.w #1
    JSL BattleFD_UnkAE52
    LDA.w BattlerStats[1].Unk2D
    CMP.b #!Battle_StatsUnk2DCalc56
    BNE .pc2
    TDC
    LDA.w BattlerStats[1].Unk3F
    JSR Battle_CalcUnk56
    STA.w BattlerStats[1].Unk56
.pc2:
    LDY.w #2
    JSL BattleFD_UnkAE52
    LDA.w BattlerStats[2].Unk2D
    CMP.b #!Battle_StatsUnk2DCalc56
    BNE .pcs_done
    TDC
    LDA.w BattlerStats[2].Unk3F
    JSR Battle_CalcUnk56
    STA.w BattlerStats[2].Unk56
.pcs_done:
    TDC
    STA.w !Battle_PcCount
    TAX
.pc_entry:
    LDA.b #!Battle_EntryNone
    STA.w !Battler_UnkAEFF,X
    STA.w !Battler_UnkAF0A,X
    LDA.w !Battler_Untargetable,X
    BNE .pc_entry_next
    LDA.w !Pc_CharId,X
    BMI .pc_entry_next
    STA.w !Battler_UnkAEFF,X
    STA.w !Battler_UnkAF0A,X
    INC.w !Battle_PcCount
.pc_entry_next:
    INX
    CPX.w #!Battle_NumPcSlots
    BCC .pc_entry
    LDA.w !Battle_PcCount
    CLC
    ADC.w !Battle_EnemyCount
    STA.w !Battle_BattlerCount
    TDC
    LDX.w #0
    LDY.w #0
    JSL BattleFD_UnkB3FE                ; X = PC, Y = PC * $80
    LDX.w #1
    LDY.w #!Battle_StatsStride
    JSL BattleFD_UnkB3FE
    LDX.w #2
    LDY.w #!Battle_StatsStride*2
    JSL BattleFD_UnkB3FE
    JSL BattleFD_UnkAE99
    JSL BattleFD_UnkAD09
    LDX.w #0
    STX.b !BattleSetup_Arg06
    JSR BattleSys_UnkC96A
    JSR BattleSys_UnkCA1A
    JSR BattleSys_UnkCCCB
    INC.b !BattleSetup_Arg06
    JSR BattleSys_UnkC96A
    JSR BattleSys_UnkCA1A
    JSR BattleSys_UnkCCCB
    INC.b !BattleSetup_Arg06
    JSR BattleSys_UnkC96A
    JSR BattleSys_UnkCA1A
    JSR BattleSys_UnkCCCB
    JSR BattleSys_UnkCDFF
    JSL BattleFD_UnkAEF2
    TDC
    TAX
.clear_cmds:
    STA.w BattleCmd.State,X
    INX
    CPX.w #!Battle_CmdBytesCleared
    BCC .clear_cmds
    STZ.w !Battle_UnkB188
    STZ.w !Battle_UnkB189
    STZ.w !Battle_UnkB18A
    TDC
    TAX
    STA.w !Battle_UnkAD8D
    LDA.b #!Battle_EntryNone
.clear_ad8e:
    STA.w !Battle_UnkAD8E,X
    INX
    CPX.w #!Battle_UnkAD8EBytes
    BNE .clear_ad8e
    JSL BattleFD_UnkACEE
    TDC
    TAX
    STA.w !Battle_UnkAEBB
    STX.w !Battle_UnkAEBD
    STX.w !Battle_UnkAEBF
    STX.w !Battle_UnkAEC1
    STX.w !Battle_ListBit
    STX.w !Battle_ListDue
.clear_lists:
    STA.w !Battle_ListTimers,X          ; the timers, then !Battle_ListFlags right after
    INX
    CPX.w #!Battle_ListEntries*2
    BNE .clear_lists
    TDC
    TAX
    LDA.b #!Battle_EntryNone
.clear_slots:
    STA.w !Battle_SlotOrder,X
    STA.w !Battle_UnkB16E,X
    STZ.w !Battle_ListCursor,X
    STA.w !Battle_UnkB158,X
    STA.w !Battler_UnkAFAB,X
    INX
    CPX.w #!Battle_NumSlots
    BNE .clear_slots
.clear_cursors:
    STZ.w !Battle_ListCursor,X          ; the last two of the 13
    INX
    CPX.w #!Battle_NumLists
    BNE .clear_cursors
    TDC
    TAX
    STX.b !BattleSetup_Arg02
    JSR BattleSys_UnkCE3A               ; PC 0, 1, 2 in !BattleSetup_Arg02
    INC.b !BattleSetup_Arg02
    JSR BattleSys_UnkCE3A
    INC.b !BattleSetup_Arg02
    JSR BattleSys_UnkCE3A
    TDC
    TAX
    STX.b !BattleSetup_Arg06
    STX.b !BattleSetup_Arg08
    STX.b !BattleSetup_Arg0A
    LDA.b #!Battle_CF15Call1A
    STA.b !BattleSetup_Arg06
    LDA.b #!Battle_CF15Call1B
    STA.b !BattleSetup_Arg08
    LDA.b #6
    STA.b !BattleSetup_Arg0A
    JSR BattleSys_UnkCF15
    LDA.b #!Battle_CF15Call2A
    STA.b !BattleSetup_Arg06
    LDA.b #!Battle_CF15Call2B
    STA.b !BattleSetup_Arg08
    LDA.b #3
    STA.b !BattleSetup_Arg0A
    JSR BattleSys_UnkCF15
    LDA.b #!Battle_CF15Call3A
    STA.b !BattleSetup_Arg06
    LDA.b #!Battle_CF15Call3B
    STA.b !BattleSetup_Arg08
    LDA.b #3
    STA.b !BattleSetup_Arg0A
    JSR BattleSys_UnkCF15
    LDA.b #!Battle_CF15Call4A
    STA.b !BattleSetup_Arg06
    LDA.b #!Battle_CF15Call4B
    STA.b !BattleSetup_Arg08
    LDA.b #4
    STA.b !BattleSetup_Arg0A
    JSR BattleSys_UnkCF15
    TDC
    TAX
    STX.b !BattleSetup_PcOfs
    STA.w !Battle_UnkAE56
.pc_stats:
    REP #$20
    LDA.l !BattleRom_PcStatBlock,X
    STA.b !BattleSetup_Block
    TAY
    TDC
    STA.b !Battle_MathA
    STA.b !Battle_MathB
    STA.b !Battle_MathLo
    SEP #$20
    LDA.w PcStatBlk.Unk37,Y
    STA.b !Battle_MathA
    LDA.w PcStatBlk.Unk48,Y
    STA.b !Battle_MathB
    LDA.w PcStatBlk.Unk70,Y
    REP #$20
    CLC
    ADC.b !Battle_MathA
    ADC.b !Battle_MathB
    CMP.w #!Battle_StatByteMax
    BCC .unk3e_ok
    LDA.w #!Battle_StatByteMax
.unk3e_ok:
    SEP #$20
    STA.w PcStatBlk.Unk3E,Y
    TDC
    LDA.w PcStatBlk.Unk4C,Y
    BIT.b #!Battle_PcStatUnk4CBit6
    BEQ .no_b14d
    LDA.w PcStatBlk.Unk4D,Y
    BEQ .no_b14d
    STY.b !BattleSetup_Idx
    LDY.w #!Battle_Unk29D7
    STY.b !BattleSetup_Arg0E
    JSL BattleFD_UnkB14D
    LDY.b !BattleSetup_Idx
.no_b14d:
    TDC
    LDX.b !BattleSetup_Block
    LDA.w PcStatBlk.Unk29,X
    TAX
    STX.b !Battle_MathA
    LDA.b #6
    TAX
    STX.b !Battle_MathB
    JSR Battle_Mul16
    REP #$20
    LDA.b !Battle_MathLo
    CLC
    ADC.w #!Battle_UnkCC0262Ofs
    TAX                                 ; quirk: overwritten below before any use
    LDA.b !BattleSetup_PcOfs
    LSR A
    TAY
    TDC
    STA.b !Battle_MathA
    STA.b !Battle_MathB
    SEP #$20
    LDA.w !Battler_UnkAEFF,Y            ; the PC's character id
    CMP.b #1
    BEQ .use_3a
    CMP.b #2
    BEQ .use_3a
    LDX.b !BattleSetup_Block
    LDA.w PcStatBlk.Unk36,X
    STA.b !Battle_MathA
    BRA .add_cc
.use_3a:
    LDX.b !BattleSetup_Block
    LDA.w PcStatBlk.Unk3A,X
    STA.b !Battle_MathA
.add_cc:
    LDA.l !BattleRom_UnkCC0000,X        ; X = the block's RAM address (quirk, see header)
    STA.b !Battle_MathB
    REP #$20
    LDA.b !Battle_MathA
    CLC
    ADC.b !Battle_MathB
    BCC .unk3d_ok                       ; always taken: the sum is at most $1FE
    LDA.w #!Battle_StatByteMax
.unk3d_ok:
    SEP #$20
    STA.w PcStatBlk.Unk3D,X
    TDC
    LDX.b !BattleSetup_PcOfs
    INX
    INX
    STX.b !BattleSetup_PcOfs
    CPX.w #!Battle_NumPcSlots*2
    BCS .pc_stats_done
    JMP .pc_stats
.pc_stats_done:
    JSL BattleFD_UnkB0D5
    JSL BattleFD_UnkB4E7
    JSL BattleFD_UnkB7EB
    JSL BattleFD_UnkB555
    JSL BattleFD_UnkB732
    JSL BattleFD_UnkACFD
    TDC
    TAX
    JSR BattleSys_UnkB093
    LDX.w #!Battle_StatsStride
    JSR BattleSys_UnkB093
    LDX.w #!Battle_StatsStride*2
    JSR BattleSys_UnkB093
    REP #$20
    LDA.w BattlerStats.MaxHp
    STA.w !Battle_SavedMaxHp
    LDA.w BattlerStats[1].MaxHp
    STA.w !Battle_SavedMaxHp+2
    LDA.w BattlerStats[2].MaxHp
    STA.w !Battle_SavedMaxHp+4
    TDC
    SEP #$20
    LDY.w #0
    JSL BattleFD_UnkB363
    LDY.w #1
    JSL BattleFD_UnkB363
    LDY.w #2
    JSL BattleFD_UnkB363
    TDC
    TAX
    STX.w !Battle_UnkB3C0
    STX.w !Battle_UnkB3C2
    STX.w !Battle_UnkB3C4
    STX.b !BattleSetup_Idx
.enemy_flags:
    TDC
    LDX.b !BattleSetup_Idx
    STA.w !Battle_UnkAE5D,X
    LDA.w !Battler_UnkAEFF+!Battle_FirstEnemySlot,X
    CMP.b #!Battle_EntryNone
    BEQ .enemy_flags_next
    TAX
    STX.b !Battle_MathA
    LDX.w #!Battle_EnemyRecUnk5E04Size
    STX.b !Battle_MathB
    JSR Battle_Mul16
    LDX.b !Battle_MathLo
    STX.b !BattleSetup_Arg02
    LDX.b !BattleSetup_Arg02
    LDA.l !BattleRom_EnemyUnk5E05,X
    BEQ .enemy_flag6
    LDX.b !BattleSetup_Idx
    LDA.b #!Battle_AE5DBit7
    STA.w !Battle_UnkAE5D,X
.enemy_flag6:
    LDX.b !BattleSetup_Arg02
    LDA.l !BattleRom_EnemyUnk5E04,X
    BEQ .enemy_flags_next
    LDX.b !BattleSetup_Idx
    LDA.w !Battle_UnkAE5D,X
    ORA.b #!Battle_AE5DBit6
    STA.w !Battle_UnkAE5D,X
.enemy_flags_next:
    INC.b !BattleSetup_Idx
    LDA.b !BattleSetup_Idx
    CMP.b #!Battle_NumEnemies
    BCC .enemy_flags
    JSL BattleFD_UnkB223
    JSL BattleFD_UnkAEC4
    RTS

; $C1:FDAE — Battle_CalcUnk56 (17 bytes, $FDAE–$FDBE)
; A / 24 + $44: Battle_SetupBattle's BattlerStats.Unk56 from .Unk3F for
; a PC whose .Unk2D is 5. What the values mean is not traced.
; Quirk: !Battle_MathHi is not set, so its stale value is the dividend's
; high word (Battle_Div32), and a .Unk3F of 0 gives $44 (no divide).
; Callers (JSR): Battle_SetupBattle ($C1:FAD0, $C1:FAE8, $C1:FB00).
; Entry: M=1, X=0, DP=0, DB any; A = the value with B = 0 (the callers
;        TDC first, so the 16-bit TAX takes 0 as its high byte)
; Exit:  M=1, X=0; A = quotient low byte + $44; X = 0 after a divide, or
;        24; Y unchanged; !Battle_MathA, MathB, MathLo, MathHi, MathRem
;        as Battle_Div32 leaves them
org $C1FDAE
Battle_CalcUnk56:
    TAX
    STX.b !Battle_MathA
    LDX.w #!Battle_Unk56Divisor
    STX.b !Battle_MathB
    JSR Battle_Div32
    LDA.b !Battle_MathLo
    CLC
    ADC.b #!Battle_Unk56Base
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
