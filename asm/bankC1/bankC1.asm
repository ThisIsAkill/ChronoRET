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

; $C1:00A7 — Battle_MulAccum (48 bytes, $00A7–$00D6)
; 8×16→24 multiply in two hardware passes (despite the name, nothing is
; accumulated from the caller: the top byte is zeroed first):
;   pass 1: Factor8 × low byte of Factor16  -> Product+0/+1
;   pass 2: Factor8 × high byte of Factor16 -> added at Product+1/+2
; In:  !Battle_MulFactor8 (8-bit), !Battle_MulFactor16 (16-bit)
; Out: !Battle_MulProduct = 24-bit product (Battle_SinLookup returns
;      its middle byte, i.e. product >> 8)
; Sets DB=0 itself (PHB/TDC/PHA/PLB) to safely use STA.w for HW regs.
org $C100A7
Battle_MulAccum:
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
; All routines operate on M=1 (8-bit A); ASL A / LSR A = 1 byte each.
;
; Left-shift chain: ShiftLeft7 (8 ASL → *256) → ShiftLeft4 (4 ASL → *16)
;   → ShiftLeft3 (3 ASL → *8, RTS)
; Right-shift chain: Loc_C10116 (8 LSR → >>8) → ShiftRight6 (>>6)
;   → ShiftRight5 (>>5) → ShiftRight4 (>>4) → ShiftRight3 (>>3, RTS)
org $C1010D
Battle_ShiftLeft7:          ; A <<= 7 (falls through ShiftLeft4 + ShiftLeft3 chain)
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
Loc_C10116:                 ; A >>= 8 (2 extra LSR before ShiftRight6 chain)
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

; $C1:0174 — Battle_DivTen9499 (53 bytes, $0174–$01A8)
; Two-digit variant of BattleMsg_FormatNumberDigits: formats
; !BattleMsg_NumValue as tens+ones only. Digit1000/Digit100 = blank;
; Digit10 = tens, Digit1 = ones. Used for two-digit values (0–99).
; Entry: M=0 (16-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1 (8-bit A), X=0 (16-bit)
; Note: same explicit .w immediates as BattleMsg_FormatNumberDigits.
; No JSR/JSL calls.
org $C10174
Battle_DivTen9499:
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
;   $40–$68 → tile = byte + $40, upper tile = $71
;   $69–$72 → tile = byte + $17, upper tile = $72
;   $73+, < $40 → tile = byte unchanged, upper tile = $FF (blank)
;   $00     → stop early (the rest is already blank)
; Entry: M=1 (8-bit A), X=0 (16-bit); entry state from caller
; Exit:  M=1 (8-bit A)
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
    BCS .range69                ; $69–$72 → second accent set
    CMP.b #!BattleMsg_CharSet1Min
    BCC .passthrough            ; < $40 → already a tile
    ; $40–$68: first accent set
    CLC
    ADC.b #!BattleMsg_CharSet1TileAdd
    STA.w !BattleMsg_TextTiles,X
    LDA.b #!BattleMsg_CharSet1Top
    BRA .store_plane
.range69:
    ; $69–$72: second accent set
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
; Status-Bar UI Callees ($C1:06F0–$C1:095C)
; Matched session 37; called by BattleUI_BuildStatusBarFrame and peers.
; ============================================================

; $C1:06F0 — BattleUI_DrawSlotGaugeBar (149 bytes, $06F0–$0784)
; Draw the 4-tile ATB gauge of PC slot !BattleUI_Slot into the status map
; at BattleRom_HpCellL1[slot] + !BattleUI_GaugeCellOffset.
;   fill = (AtbCur * 256 / AtbMax) >> 3, 0-31 units of 32
;   rest = 32 - fill; rest / 8 tiles get TileGauge8, then one tile gets
;   TileGauge0 + (rest mod 8); the remaining tiles keep TileGauge0.
; So the tiles drawn track the part of the gauge still to fill (the
; earlier header called the $6F tiles "full-fill"; what they show depends
; on the graphics, which were not checked). Attribute: palette 3 if
; AtbCur is non-zero, else palette 2.
; Entry: M=1, X=0 (16-bit), !BattleUI_Slot = PC slot (0–2)
; Exit:  M=1; Y = last map offset written; DP $82/$83/$86/$AD/$AE/$B1–$B7 clobbered
; Calls: Battle_ShiftLeft7, Battle_Divide, Battle_ShiftRight3
; Direct-page roles (status-bar routines share !BattleUI_Slot):
!BattleUI_Slot = !BattleTmp_80            ; 1-2 B: PC slot (or enemy-name line) being drawn
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
    JSR Battle_ShiftLeft7       ; A <<= 8 (× 256) — scale to fixed-point
    STA.b !Battle_DivDividend
    TDC
    SEP #$20                    ; M=1
    JSR Battle_Divide           ; quotient = AtbCur * 256 / AtbMax (0–255)
    REP #$20                    ; M=0
    LDA.b !Battle_DivQuotient   ; (16-bit read)
    JSR Battle_ShiftRight3      ; >> 3 → 0–31 gauge units
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

; $C1:0785 — BattleSys_SlotPanelRefresh (153 bytes, $0785–$081D)
; Draw the 6-row × 7-column panel of PC slot A into the status map at
; offset slot × 12, from one of two ROM tile tables:
;   !BattleRom_PanelEmpty — no other PC waiting / panel not applicable
;   !BattleRom_PanelReady — another PC is waiting for a command
; Ready is chosen when !BattleUI_OtherReady and the slot's
; !Pc_Unk9F25|!Pc_Unk9F28 are non-zero, and then either !BattleUI_UnkA117
; is zero, all three PCs are in the roster, or !BattleUI_UnkA115 names a
; different PC whose roster entry is negative. Attribute: palette 2.
; Entry: M=1, X=0 (16-bit), A = PC slot (0–2)
; Exit:  M=1; DP $80-$83 clobbered; X/Y clobbered
; No calls.
; Direct-page roles (!BattleUI_Slot holds the slot until the drawing loops):
!BattleUI_RowsLeft = !BattleTmp_80        ; 1 B: panel rows left to draw
!BattleUI_ColsLeft = !BattleTmp_81        ; 1 B: columns left in the row
!BattleUI_MapOffset = !BattleTmp_82       ; 2 B: map offset of the current row / edge strip
org $C10785
BattleSys_SlotPanelRefresh:
    STA.b !BattleUI_Slot
    ASL
    ASL                         ; × 4
    STA.b !BattleUI_MapOffset
    ASL                         ; × 8
    CLC
    ADC.b !BattleUI_MapOffset   ; slot × 12
    TAX
    STX.b !BattleUI_MapOffset   ; 16-bit map offset of the panel
    LDA.w !BattleUI_OtherReady
    BEQ .empty_panel            ; no other PC waiting → empty panel
    LDA.b !BattleUI_Slot
    TAX
    LDA.w !Pc_Unk9F25,X
    ORA.w !Pc_Unk9F28,X
    BEQ .empty_panel            ; both zero → empty panel
    LDA.w !BattleUI_UnkA117
    BEQ .ready_panel            ; zero → ready panel
    LDA.w !BattleMenu_ReadyCount
    CMP.b #!Battle_NumPcSlots
    BEQ .ready_panel            ; all three PCs waiting → ready panel
    LDA.b !BattleUI_Slot
    CMP.w !BattleUI_UnkA115
    BEQ .empty_panel            ; same slot → empty
    LDX.w !BattleUI_UnkA115
    LDA.w !BattleMenu_Roster,X
    BMI .ready_panel            ; that PC not in the roster → ready panel

.empty_panel:
    TDC
    TAX                         ; X = table index (starts at 0)
    LDA.b #!BattleUI_PanelRows
    STA.b !BattleUI_RowsLeft
.empty_row_start:
    LDA.b #!BattleUI_PanelCols
    STA.b !BattleUI_ColsLeft
    LDY.b !BattleUI_MapOffset   ; Y = current row
.empty_col_loop:
    LDA.l !BattleRom_PanelEmpty,X
    STA.w BattleUI_StatusTile(0,0),Y
    LDA.b #!BattleUI_AttrPal2
    STA.w BattleUI_StatusAttr(0,0),Y
    INY
    INY
    INX
    DEC.b !BattleUI_ColsLeft
    BNE .empty_col_loop
    REP #$21                    ; M=0, C=0
    LDA.b !BattleUI_MapOffset
    ADC.w #!BattleUI_MapRowBytes ; next tilemap row
    STA.b !BattleUI_MapOffset
    TDC
    SEP #$20                    ; M=1
    DEC.b !BattleUI_RowsLeft
    BNE .empty_row_start
    BRA .done

.ready_panel:
    TDC
    TAX                         ; X = table index
    LDA.b #!BattleUI_PanelRows
    STA.b !BattleUI_RowsLeft
.ready_row_start:
    LDA.b #!BattleUI_PanelCols
    STA.b !BattleUI_ColsLeft
    LDY.b !BattleUI_MapOffset
.ready_col_loop:
    LDA.l !BattleRom_PanelReady,X
    STA.w BattleUI_StatusTile(0,0),Y
    LDA.b #!BattleUI_AttrPal2
    STA.w BattleUI_StatusAttr(0,0),Y
    INY
    INY
    INX
    DEC.b !BattleUI_ColsLeft
    BNE .ready_col_loop
    REP #$21                    ; M=0, C=0
    LDA.b !BattleUI_MapOffset
    ADC.w #!BattleUI_MapRowBytes ; next tilemap row
    STA.b !BattleUI_MapOffset
    TDC
    SEP #$20                    ; M=1
    DEC.b !BattleUI_RowsLeft
    BNE .ready_row_start
.done:
    RTS

; $C1:081E — BattleMenu_DrawReadyWindowEdges (202 bytes, $081E–$08E7)
; Draw the window edge strip of every PC in the roster, then colour the
; shown PC's attribute column and fall into BattleUI_ClearActivePanelColumn.
; Slot 1's / slot 2's strip is a right edge (!BattleUI_EdgeRight = 1) when
; the slot before it is also in the roster, else a left edge further left.
; BattleUI_ClearActivePanelColumn ($0872) is also called on its own
; (BattleMenu_UpdateMainWindow) when only the cursor column needs redrawing.
; Entry: M=1, X=0 (16-bit)
; Exit:  M=1; DP $80/$82/$84 clobbered; X/Y clobbered
; Calls: BattleMenu_DrawWindowEdgeStrip, BattleUI_SetPanelAttrColumn
!BattleUI_EdgeRight = !BattleTmp_84      ; 1 B: 0 = left edge strip, else right (DrawWindowEdgeStrip input)
org $C1081E
BattleMenu_DrawReadyWindowEdges:
    STZ.b !BattleUI_EdgeRight   ; left edge
    LDA.w !BattleMenu_Roster    ; PC slot 0 in the roster?
    BMI .check_slot1            ; no → no strip
    LDX.w #$0000                ; map offset 0
    STX.b !BattleUI_MapOffset
    JSR BattleMenu_DrawWindowEdgeStrip
.check_slot1:
    LDA.w !BattleMenu_Roster+1  ; PC slot 1 in the roster?
    BMI .check_slot2            ; no → no strip
    LDA.w !BattleMenu_Roster    ; slot 0 too?
    BMI .slot1_left             ; no → left edge
    LDA #$01
    STA.b !BattleUI_EdgeRight   ; yes → right edge
    LDX.w #!BattleUI_EdgeCol1Right
    BRA .slot1_draw
.slot1_left:
    LDX.w #!BattleUI_EdgeCol1Left
.slot1_draw:
    STX.b !BattleUI_MapOffset
    JSR BattleMenu_DrawWindowEdgeStrip
    STZ.b !BattleUI_EdgeRight   ; back to left edge
.check_slot2:
    LDA.w !BattleMenu_Roster+2  ; PC slot 2 in the roster?
    BMI .active_pc_section      ; no → no strip
    LDA.w !BattleMenu_Roster+1  ; slot 1 too?
    BMI .slot2_left             ; no → left edge
    LDA #$01
    STA.b !BattleUI_EdgeRight   ; yes → right edge
    LDX.w #!BattleUI_EdgeCol2Right
    BRA .slot2_draw
.slot2_left:
    LDX.w #!BattleUI_EdgeCol2Left
.slot2_draw:
    STX.b !BattleUI_MapOffset
    JSR BattleMenu_DrawWindowEdgeStrip
.active_pc_section:
    LDA.w !BattleMenu_RosterIdx ; roster entry shown
    TAX
    LDA.w !BattleMenu_Roster,X  ; its PC slot
    JSR BattleUI_SetPanelAttrColumn
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

; $C1:08E8 — BattleUI_SetPanelAttrColumn (65 bytes, $08E8–$0928)
; For PC slot A: look up the slot's offset in !BattleRom_AttrColumnL1
; (layout 1) or !BattleRom_AttrColumnL02 (layouts 0 and 2) and set the
; attribute of a 5-wide × 2-high block of status-map cells to palette 2.
; The table offsets are odd, i.e. they point at an attribute byte, so the
; Tile(r,c),X stores below all land on attribute bytes.
; Entry: M=1, X=0 (16-bit), A = PC slot (0–2)
; Exit:  M=1; X = offset; A = !BattleUI_AttrPal2; Y unchanged
; No calls.
org $C108E8
BattleUI_SetPanelAttrColumn:
    ASL                         ; slot × 2 (table index)
    TAX
    REP #$20                    ; M=0
    LDA.w !BattleUI_GaugeLayout ; (16-bit read; layout 0/1/2)
    BNE .type_not0
    LDA.l !BattleRom_AttrColumnL02,X ; layout 0
    BRA .got_offset
.type_not0:
    DEC A                       ; layout − 1
    BNE .type_not1              ; non-zero → layout 2
    LDA.l !BattleRom_AttrColumnL1,X ; layout 1
    BRA .got_offset
.type_not1:
    LDA.l !BattleRom_AttrColumnL02,X ; layout 2 (same table as layout 0)
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

; $C1:0929 — BattleMenu_DrawWindowEdgeStrip (52 bytes, $0929–$095C)
; Copy a 6-row window edge strip from !BattleRom_WindowEdges into
; !BattleMenu_WindowMap at !BattleUI_MapOffset. Each ROM row is 14 bytes
; (7 entries): a left edge (!BattleUI_EdgeRight = 0) copies all of it, a
; right edge skips the row's first entry and copies the other 12 bytes.
; Entry: M=1, X=0 (16-bit), !BattleUI_MapOffset = map offset,
;        !BattleUI_EdgeRight = edge kind
; Exit:  M=1; X/Y and DP $80-$83 clobbered
; No calls.
!BattleUI_EdgeBytes = !BattleTmp_80      ; 1 B: bytes left to copy in this row
!BattleUI_EdgeRows = !BattleTmp_81       ; 1 B: rows left
org $C10929
BattleMenu_DrawWindowEdgeStrip:
    TDC
    TAX                         ; X = 0 (ROM table index)
    LDA.b #!BattleUI_PanelRows
    STA.b !BattleUI_EdgeRows
.row_loop:
    LDA.b !BattleUI_EdgeRight
    BNE .right_edge
    LDA.b #!BattleUI_EdgeBytesLeft ; left edge: whole 14-byte row
    BRA .pick_done
.right_edge:
    INX                         ; right edge: skip the row's first entry
    INX
    LDA.b #!BattleUI_EdgeBytesRight ; and copy the other 12 bytes
.pick_done:
    STA.b !BattleUI_EdgeBytes
    LDY.b !BattleUI_MapOffset   ; Y = current row
.inner_loop:
    LDA.l !BattleRom_WindowEdges,X
    STA.w !BattleMenu_WindowMap,Y
    INX
    INY
    DEC.b !BattleUI_EdgeBytes
    BNE .inner_loop
    REP #$21                    ; M=0, C=0
    LDA.b !BattleUI_MapOffset
    ADC.w #!BattleUI_MapRowBytes ; next tilemap row
    STA.b !BattleUI_MapOffset
    TDC
    SEP #$20                    ; M=1
    DEC.b !BattleUI_EdgeRows
    BNE .row_loop
    RTS

; ============================================================
; Trig / Geometry Cluster ($C1:01F9–$C1:0298)
; ============================================================

; $C1:01F9 — Battle_SinLookup (41 bytes, $01F9–$0221)
; Scaled sine: returns (sin(A) × !Battle_SinScale) >> 8 in A.
; A (8-bit) is an angle, 256 units per turn; !BattleRom_SineTable gives
; the magnitude (low byte of each 2-byte entry), negated for the second
; half turn. The signed sine goes to !Battle_MulFactor16, the scale to
; !Battle_MulFactor8, and Battle_MulAccum multiplies them.
; Entry: M=1 (8-bit A), X=0 (16-bit); angle in A
; Exit:  M=1 (8-bit A); A = !Battle_MulProduct+1 (product >> 8)
; Calls: Battle_MulAccum
!Battle_SinScale = !Battle_Mul8B          ; 1 B in: scale multiplied into the sine (Mul8's B slot)
org $C101F9
Battle_SinLookup:
    REP #$20                    ; A → 16-bit
    ASL A
    ASL A
    AND.w #!Battle_SineIndexMask ; angle × 4, wrapped to the table (512 entries × 2 B)
    TAX                         ; X = table byte index
    LDA.l !BattleRom_SineTable,X
    AND.w #!Battle_LowByteMask  ; keep low byte (magnitude)
    CPX.w #!Battle_SineHalfTable ; second half turn → negative
    BCC .first_quadrant
    EOR.w #!Battle_Invert16
    INC A                       ; two's complement negate (EOR + INC)
.first_quadrant:
    STA.b !Battle_MulFactor16   ; signed sine (16-bit store)
    LDA.b !Battle_SinScale      ; (16-bit read: also the next byte)
    AND.w #!Battle_LowByteMask  ; zero-extend the scale byte
    STA.b !Battle_MulFactor8    ; (16-bit store: also clears $A6)
    SEP #$20                    ; A → 8-bit
    JSR Battle_MulAccum         ; Factor8 × Factor16 → 24-bit product
    LDA.b !Battle_MulProduct+1  ; return product >> 8
    RTS

; $C1:0222 — Calc_Delta16 (119 bytes, $0222–$0298)
; Direction angle between two screen points (256 units per turn).
; Computes dx = OriginX − PointX and dy = OriginY − PointY as signed
; 16-bit values, takes |dx| and |dy|, looks up a base angle in
; !BattleRom_AngleTable at index (|dy| & ~7) × 4 + (|dx| >> 3), then
; places it in the right quadrant from the signs of dx and dy.
; Entry: M=1 (8-bit A), X=0 (16-bit); !Battle_GeoOriginX/Y, !Battle_GeoPointX/Y
; Exit:  M=1 (8-bit A); angle in A and !Battle_GeoAngle
; No JSR/JSL calls.
org $C10222
Calc_Delta16:
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
    BMI .d8_negative            ; ΔX < 0
    LDA.b !Battle_GeoDeltaY+1   ; check sign of ΔY (high byte)
    BMI .da_negative_q1         ; ΔX ≥ 0, ΔY < 0 → Q4
    ; Q1: ΔX ≥ 0, ΔY ≥ 0 → angle = $80 + base
    CLC
    LDA.b #!Battle_AngleHalfTurn
    ADC.b !Battle_GeoAngle
    STA.b !Battle_GeoAngle
    RTS
.da_negative_q1:                ; Q4: ΔX ≥ 0, ΔY < 0 → angle = $80 − base
    SEC
    LDA.b #!Battle_AngleHalfTurn
    SBC.b !Battle_GeoAngle
    STA.b !Battle_GeoAngle
    RTS
.d8_negative:
    LDA.b !Battle_GeoDeltaY+1   ; check sign of ΔY
    BMI .da_negative_q3         ; ΔX < 0, ΔY < 0 → Q3
    ; Q2: ΔX < 0, ΔY ≥ 0 → angle = 0 − base (negate)
    TDC                         ; A = 0
    SEC
    SBC.b !Battle_GeoAngle
    STA.b !Battle_GeoAngle
.da_negative_q3:                ; Q3: ΔX < 0, ΔY < 0 → angle unchanged
    LDA.b !Battle_GeoAngle
    RTS

; ============================================================
; Status-Bar UI Cluster ($C1:0299–$C1:05A6)
; ============================================================

; $C1:0299 — BattleUI_BuildStatusBarFrame (782 bytes, $0299–$05A6)
; Rebuilds the battle status-bar map (BattleUI_StatusTile, $0CC0):
;   1. Clears 192 entries (tile 0, palette 2).
;   2. Writes the "HP"/"MP" header glyphs where the current layout
;      (!BattleUI_GaugeLayout: 0 = HP/MaxHP/MP, 1 = HP/MP + gauge,
;      2 = HP/MP/TP + gauge) puts them.
;   3. For each present PC (!Battler_Present, slots 0-2), from the line's
;      name cell (!BattleUI_PanelDest):
;      - the 10 name tiles from !Pc_NameTiles: 5 on the line, the next 5
;        on the tilemap row above it;
;      - HP digits (BattlerStats.CurHp; palette 3 when HP is 0 or at most
;        MaxHP/8, see !BattleUI_LowHp);
;      - layout 0: a separator tile and the MaxHP digits;
;      - MP digits (two digits); layouts 1/2: the TP gauge ends and the
;        ATB gauge (BattleUI_DrawSlotGaugeBar).
;   4. For each used enemy-name line (!Enemy_NameLineUsed, 0-2): the 11
;      lower-row and 11 upper-row tiles from !Enemy_NameTiles.
;   5. If PCs are waiting for a command (!BattleMenu_ReadyCount):
;      - while targeting from a submenu (!BattleMenu_ReturnSubmenu != 0)
;        and the first selected target differs from !BattleUI_UnkA0D7:
;        force a window rebuild and tail-jump to
;        BattleUI_SetPanelAttrColumn with that target's slot;
;      - else, on the main menu only: latch !BattleUI_OtherReady, make
;        sure !BattleMenu_RosterIdx names a roster entry (first valid one
;        otherwise), set !BattleMenu_ActivePc, redraw every roster PC's
;        panel (BattleSys_SlotPanelRefresh) and the window edges
;        (BattleMenu_DrawReadyWindowEdges).
; Entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=0, DB=$7E
; Exit:  M=1; X, Y clobbered; DP $80/$84/$86/$8E/$A2 used as temporaries
; Calls: Battle_ShiftRight3, BattleMsg_FormatNumberDigits, BattleMsg_BlankLeadingZeros,
;        Battle_DivTen9499, BattleUI_DrawSlotGaugeBar, BattleUI_SetPanelAttrColumn,
;        BattleSys_SlotPanelRefresh, BattleMenu_DrawReadyWindowEdges
; Direct-page roles:
!BattleUI_PanelDest = !BattleTmp_84       ; 2 B: map offset of the current line's name cell
!BattleUI_CharsLeft = !BattleTmp_8E       ; 1 B: name tiles left to copy
!BattleUI_StatsOffset = !BattleTmp_A2     ; 2 B: BattlerStats offset of the PC being drawn
!BattleUI_RefreshSlot = !BattleTmp_86     ; 1-2 B: PC slot of the panel-refresh loop
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
    ; Layout 1: HP + MP + gauge
    LDA.b #!BattleUI_TileH
    STA.w BattleUI_StatusTile(0,13)
    LDA.b #!BattleUI_TileP
    STA.w BattleUI_StatusTile(0,14)
    STA.w BattleUI_StatusTile(0,18)
    LDA.b #!BattleUI_TileM
    STA.w BattleUI_StatusTile(0,17)
    BRA .gauge_dest_sel
.gauge_type2:
    ; Layout 2: HP + MP + TP + gauge
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
    BEQ .dest_5A
    DEC A
    BNE .dest_5A
    LDX.w #!BattleUI_PanelDestL1
    BRA .set_dest_base
.dest_5A:
    LDX.w #!BattleUI_PanelDestL02
.set_dest_base:
    STX.b !BattleUI_PanelDest
    TDC
    TAX
    STX.b !BattleUI_Slot            ; PC slot 0
    ; --- BattleUI_DrawPcNamePanel ---
    ; Writes one PC slot's name + HP/MP/TP into the status map. Loop body:
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
    BEQ .lhp_equal                  ; equal → !BattleUI_UnkA110 decides
    BCC .lhp_ok                     ; MaxHP/8 < HP → not low
.lhp_equal:
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
    JSR Battle_DivTen9499           ; exits M=1
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
    BRA .tp_gauge
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
.tp_gauge:
    LDA.w !BattleUI_GaugeLayout
    BEQ BattleUI_NextNamePanel      ; layout 0: no TP / ATB gauge
    REP #$20                        ; M=0
    DEC A
    BNE .tp_yoff_type2
    CLC
    LDA.b !BattleUI_PanelDest
    ADC.w #!BattleUI_TpOffsetL1     ; layout 1
    BRA .tp_fmt
.tp_yoff_type2:
    CLC
    LDA.b !BattleUI_PanelDest
    ADC.w #!BattleUI_TpOffsetL2     ; layout 2
.tp_fmt:
    TAY
    TDC
    SEP #$20                        ; M=1
    LDA.b #!BattleUI_TileTpBarL
    STA.w BattleUI_StatusTile(0,0),Y
    LDA.b #!BattleUI_TileTpBarR
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
    ; --- Ready-PC panels ---
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
    JMP.w BattleUI_SetPanelAttrColumn
.check_slot_state:
    LDA.w !BattleMenu_Submenu
    BEQ .do_slot_state
    RTS                             ; a submenu is open → leave the panels
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
    JSR BattleSys_SlotPanelRefresh
.slot_skip:
    INC.b !BattleUI_RefreshSlot
    LDA.b !BattleUI_RefreshSlot
    CMP.b #!Battle_NumPcSlots
    BNE .slot_refresh_loop
    JSR BattleMenu_DrawReadyWindowEdges
.buildbar_done:
    RTS

; ============================================================
; BattleUI_UpdateNextPcPanel ($C1:05A7–$C1:06EF, 329 bytes)
; Per-frame peer of BattleUI_BuildStatusBarFrame: refreshes one PC's
; HP/MP digits per call (round robin through !BattleUI_NextPanelSlot),
; then redraws every present PC's ATB gauge (layouts 1/2).
; Logic:
;   1. The digit refresh is skipped (straight to the gauges) only when
;      PC slot 2 is in the roster, !BattleUI_PanelHold is clear and the
;      layout is 1; every other case refreshes.
;   2. Advance !BattleUI_NextPanelSlot (wrap at 3); stop if no PC there.
;   3. HP cell from !BattleRom_HpCellL0/L1/L2 by layout.
;   4. HP digits, palette 3 when low (same test as BuildStatusBarFrame);
;      layout 0 also recolours the three MaxHP cells after them.
;   5. MP digits at HP cell + !BattleUI_MpCellL0 / L12.
;   6. Layouts 1/2: ATB gauges for all present PCs (Battle_DrawHpBars).
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0, DB=$7E
; Exit:  M=1; X, Y clobbered; DP $80/$86/$A2, !BattleUI_LowHp and
;        !BattleMsg_NumValue used as temporaries
; Calls: Battle_ShiftRight3, BattleMsg_FormatNumberDigits,
;        BattleMsg_BlankLeadingZeros, Battle_DivTen9499, BattleUI_DrawSlotGaugeBar
; Sub-entry: Battle_DrawHpBars ($06DB) — X = first PC slot; redraw the
;        ATB gauges from there to slot 2
!BattleUI_PanelBase = !BattleTmp_86      ; 2 B: map offset of the PC's HP cell
org $C105A7
BattleUI_UpdateNextPcPanel:
    LDA.w !BattleMenu_Roster+2      ; PC slot 2 in the roster?
    BMI .advance_panel              ; no → refresh digits
    LDA.w !BattleUI_PanelHold
    BNE .advance_panel              ; held → refresh digits
    LDA.w !BattleUI_GaugeLayout
    BEQ .advance_panel              ; layout 0 → refresh digits
    DEC A                           ; layout 1 → A=0; layout 2 → A=1
    BNE .advance_panel              ; layout 2 → refresh digits
    JMP .tp_gauges                  ; layout 1 → gauges only
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
    JMP UpdateNpc_exit              ; no PC in this slot
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
    BEQ .check_a110                 ; equal → !BattleUI_UnkA110 decides
    BCC .hp_ok                      ; MaxHP/8 < HP → not low
.check_a110:
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
    JSR Battle_DivTen9499           ; MP digits (exits M=1)
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
    BRA .tp_gauges
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
.tp_gauges:
    LDA.w !BattleUI_GaugeLayout
    BEQ UpdateNpc_exit              ; layout 0 has no ATB gauges
    TDC
    TAX                             ; X = 0 (first slot)
Battle_DrawHpBars:
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
UpdateNpc_exit:
    RTS

; ============================================================
; Battle Menu — Item/Tech List Rendering Cluster
; $C1:095D–$C1:0C2C  (720 bytes)
; ============================================================

; $C1:095D — BattleMenu_RenderItemListRows (83 bytes, $095D–$09AF)
; Renders 3 visible item-list rows:
;   1. Clears text buffer $0E80 ($180 bytes).
;   2. Computes first item record index = $80 * 5 (5-byte records).
;   3. Calls BattleMenu_RenderItemRow for rows 0, 1, 2, advancing
;      the item index by 5 and the display-column offset by $80 each row.
; Entry: M=1, X=0 (16-bit), DB=$7E; $80 = item list scroll position
; Exit:  M=1; $80/$82/$84/$86 clobbered
; Calls: BattleMenu_RenderItemRow ($09B0)
org $C1095D
BattleMenu_RenderItemListRows:
    LDA.w $95D5                     ; active PC slot index
    TAX
    STX.b $96                       ; save slot (16-bit) to DP $96–$97
    LDX.w #$0180                    ; $180 bytes to clear
    REP #$20                        ; M=0
    TDC                             ; A = 0
    TAY                             ; Y = 0 (buffer index)
    SEP #$20                        ; M=1
.clear_loop:
    STA.w $0E80,Y                   ; zero one byte of item text buffer
    INY
    DEX
    BNE .clear_loop
    STZ.b $81                       ; item index high byte = 0
    REP #$20                        ; M=0
    TDC
    STA.b $82                       ; display-column offset = 0
    LDA.b $80                       ; scroll position
    STA.b $84                       ; save
    ASL A                           ; * 2
    ASL A                           ; * 4
    CLC
    ADC.b $84                       ; * 4 + * 1 = * 5 (5-byte item records)
    STA.b $80                       ; first item record index
    TAX
    TDC
    STA.b $86                       ; row counter = 0
    SEP #$20                        ; M=1
.row_loop:
    JSR BattleMenu_RenderItemRow
    REP #$20                        ; M=0
    LDA.b $86                       ; row counter
    INC A                           ; (row + 1) for row-buffer stride calc
    ASL A                           ; * 2
    ASL A                           ; * 4
    ASL A                           ; * 8
    ASL A                           ; * 16
    ASL A                           ; * 32
    ASL A                           ; * 64
    ASL A                           ; * 128 ($80 words per row = line-buffer stride)
    STA.b $82                       ; column offset for next row
    CLC
    LDA.b $80
    db $69,$05,$00                  ; ADC #$0005 — next item record (M=0 3-byte form)
    STA.b $80
    TDC
    SEP #$20                        ; M=1
    INC.b $86                       ; row counter++
    LDA.b $86
    CMP #$03
    BNE .row_loop
    RTS

; $C1:09B0 — BattleMenu_RenderItemRow (215 bytes, $09B0–$0A86) +
;             CODE_JP_C10A87 (1 byte, $0A87)
; Renders one item-list row for item record at $7E:1580+$80.
;   - If quantity ($1583,X) = 0 or item id ($1580,X) = 0 → exit.
;   - Copies 11-byte item name from $CC:name_table into $94A0, re-encodes,
;     then lays tile/attr pairs into display buffers $0EC6 and $0E86.
;   - Formats item quantity ($1583,X) as 2-digit display at $0EDE/$0EE0.
;   - Attr tile = $29 (normal) or $2D (greyed) based on party-use flags.
; Entry: M=1, X=0 (16-bit), DB=$7E; $80 = item record index, $82 = column offset
; Exit:  M=1; $84/$8E/$98 clobbered
; Calls: BattleMsg_ReencodeTextBuffer ($01A9), Battle_DivTen9499 ($0174),
;        BattleMsg_BlankLeadingZeros ($104E)
org $C109B0
BattleMenu_RenderItemRow:
    LDX.b $80                       ; item record index (16-bit from DP)
    LDA.w $1583,X                   ; item quantity
    BEQ .empty_slot                 ; 0 → empty, skip
    LDA.w $1580,X                   ; item id
    BNE .render_item                ; nonzero → render
.empty_slot:
    JMP CODE_JP_C10A87              ; skip this row
.render_item:
    REP #$20                        ; M=0
    STA.b $84                       ; save display-flag value (16-bit, B=0)
    ASL A                           ; * 2
    ASL A                           ; * 4
    STA.b $8E                       ; save * 4
    ASL A                           ; * 8
    CLC
    ADC.b $8E                       ; * 8 + * 4 = * 12
    SEC
    SBC.b $84                       ; * 12 - * 1 = * 11 (11 bytes/name)
    db $69,$5E,$0B                  ; ADC #$0B5E — ROM offset of item name table (M=0 3-byte)
    TAX                             ; X = ROM offset in bank $CC
    TDC
    LDY.w #$94A0                    ; Y = destination in $7E
    LDA.w #$000A                    ; 11 bytes (count-1)
    MVN $7E,$CC                     ; copy 11-byte item name: $CC:X → $7E:$94A0
    TDC
    SEP #$20                        ; M=1
    STA.w $0000,Y                   ; null-terminate at $7E:$94AB
    JSR BattleMsg_ReencodeTextBuffer
    LDX.b $80                       ; item record index
    LDA.w $1582,X                   ; item status flags
    BPL .attr_normal                ; non-negative → selectable
    LDA.w $1584,X                   ; party-use bitfield
    LDX.b $96                       ; slot index (16-bit from DP $96–$97)
    AND.l $CCF9FB,X                 ; mask against per-PC usability table
    BNE .attr_normal                ; can use → normal attr
    LDA #$2D                        ; greyed-out attr tile
    BRA .attr_done
.attr_normal:
    LDA #$29                        ; normal attr tile
.attr_done:
    STA.b $98                       ; save attribute tile
    TDC
    TAY
    LDX.b $82                       ; column offset
.name_copy1:
    LDA.w $94A0,Y                   ; name tile from re-encoded buffer
    STA.w $0EC6,X
    INX
    LDA.b $98                       ; attr tile
    STA.w $0EC6,X
    INX
    INY
    CPY.w #$000A                    ; 10 tile+attr pairs
    BNE .name_copy1
    LDA #$5F                        ; separator tile
    STA.w $0EC8,X
    LDA.b $98
    STA.w $0EC9,X
    TDC
    TAY
    LDX.b $82
.name_copy2:
    LDA.w $94B0,Y
    STA.w $0E86,X
    INX
    LDA.b $98
    STA.w $0E86,X
    INX
    INY
    CPY.w #$000B                    ; 11 tile+attr pairs
    BNE .name_copy2
    LDX.b $80                       ; item record index
    LDA.w $1583,X                   ; item quantity
    REP #$20                        ; M=0 (zero-extend quantity to 16-bit)
    STA.w $9499                     ; → digit-format workspace
    JSR Battle_DivTen9499           ; format quantity as 2-digit decimal
    JSR BattleMsg_BlankLeadingZeros ; suppress leading zero
    LDX.b $82                       ; column offset (M=1 on return from both JSRs)
    LDA.w $949E                     ; tens digit tile
    STA.w $0EDE,X
    LDA.b $98
    STA.w $0EDF,X
    LDA.w $949F                     ; ones digit tile
    STA.w $0EE0,X
    LDA.b $98
    STA.w $0EE1,X
    LDA #$A8
    STA.w $0EEC,X
    LDA.b $98
    STA.w $0EED,X
    LDA #$CD
    STA.w $0EEE,X
    LDA.b $98
    STA.w $0EEF,X
    LDA #$BE
    STA.w $0EF0,X
    LDA.b $98
    STA.w $0EF1,X
    LDA #$C6
    STA.w $0EF2,X
    LDA.b $98
    STA.w $0EF3,X
CODE_JP_C10A87:
    RTS

; $C1:0A88 — BattleMenu_RenderTechListRows (75 bytes, $0A88–$0AD2)
; Renders 4 tech-list rows (2 per outer loop iteration) for the active PC.
; Loads PC's tech-display base from DATA8_CCF38C[slot], adds scroll position
; ($95EB,slot), then calls BattleMenu_RenderTechRow four times advancing
; the destination offset $82 by $80 per row.
; Entry: M=1, X=0 (16-bit), DB=$7E; $82 = base display-column offset
; Exit:  M=1
; Calls: BattleMenu_RenderTechRow ($0B0B)
org $C10A88
BattleMenu_RenderTechListRows:
    LDA.w $95D5                     ; active PC slot
    TAX
    LDA.l $CCF38C,X                 ; tech-display base index for this PC
    STA.b $AF
    LDA.w $95EB,X                   ; PC tech-list scroll position
    STA.b $88
    STA.b $86
    LDA #$02
    STA.b $87                       ; outer loop count = 2 (2 passes × 2 rows = 4 rows)
    STZ.b $89
    CLC
    LDA.b $88
    ADC.b $AF                       ; first display code index = scroll + base
    STA.b $80
    STZ.b $81
    TDC
    STA.b $82                       ; display-column offset low = 0
    STA.b $83
.row_pair_loop:
    JSR BattleMenu_RenderTechRow    ; render row A
    INC.b $80                       ; advance display code index
    REP #$21                        ; M=0, C=0
    LDA.b $82
    db $69,$80,$00                  ; ADC #$0080 — advance one row ($80 words, M=0 3-byte)
    STA.b $82
    TDC
    SEP #$20                        ; M=1
    JSR BattleMenu_RenderTechRow    ; render row B
    REP #$21                        ; M=0, C=0
    LDA.b $82
    db $69,$80,$00                  ; ADC #$0080 (M=0 3-byte)
    STA.b $82
    SEP #$20                        ; M=1
    INC.b $80
    DEC.b $87
    BNE .row_pair_loop
    RTS

; $C1:0AD3 — BattleMenu_BuildTechAvailFlags (56 bytes, $0AD3–$0B0A)
; Builds availability array $7E:1CDB (20 entries, one per display slot) for
; the active PC's tech list.  For each slot, reads display code from
; $94D0+base: if $FB–$FF → write 0 (unselectable); else → write 1.
; Used by cursor-movement logic to skip blank/locked entries.
; Entry: M=1, X=0 (16-bit), DB=$7E
; Exit:  M=1; $80/X/Y clobbered
; No JSR/JSL calls.
org $C10AD3
BattleMenu_BuildTechAvailFlags:
    TDC
    TAY                             ; Y = output index into $1CDB
    LDA #$14
    STA.b $80                       ; 20 entries to process
    LDA.w $95D5                     ; active PC slot
    TAX
    LDA.l $CCF38C,X                 ; tech-display base index
    TAX                             ; X = index into $94D0 display table
.avail_loop:
    LDA.w $94D0,X                   ; display code
    CMP #$FF
    BEQ .unavail
    CMP #$FE
    BEQ .unavail
    CMP #$FD
    BEQ .unavail
    CMP #$FC
    BEQ .unavail
    CMP #$FB
    BEQ .unavail
    LDA #$01                        ; selectable
    STA.w $1CDB,Y
    BRA .next
.unavail:
    TDC                             ; 0 = unselectable
    STA.w $1CDB,Y
.next:
    INY
    INX
    DEC.b $80
    BNE .avail_loop
    RTS

; $C1:0B0B — BattleMenu_RenderTechRow (171 bytes, $0B0B–$0BB5)
; Renders one tech-list row into 16-word buffer $94A0 (cleared to $FFFF),
; then copies tile+attr pairs into window tilemap buffers $9A2F/$99EF.
; Display code in $94D0+$80:
;   $FF/$FE → blank (jump to CODE_JP_C10BB6 / exit early)
;   $FD     → fixed string type 2 at $CCFB4B+$12 (labelled UNREACH in ref)
;   $FC     → fixed string type 1 at $CCFB4B+$00
;   $FB     → indexed variant (use $88 as table index, skip name decode)
;   else    → tech name: id*11+$15C4 in bank $CC, re-encoded via $01A9
; Entry: M=1, X=0 (16-bit), DB=$7E; $80 = display code index, $82 = col offset
; Exit:  M=1
; Calls: BattleMsg_ReencodeTextBuffer ($01A9), BattleMenu_BlankMpCostDigits ($0BD3),
;        CODE_JP_C10BB6 ($0BB6), CODE_JP_C10C00 ($0C00)
org $C10B0B
BattleMenu_RenderTechRow:
    REP #$20                        ; M=0
    LDX.w #$001E
    LDA.w #$FFFF
.fill_loop:
    STA.w $94A0,X                   ; fill $94A0–$94BF with $FFFF
    DEX
    DEX
    BPL .fill_loop
    TDC
    SEP #$20                        ; M=1
    LDX.b $80                       ; display code index (16-bit from DP)
    LDA.w $94D0,X                   ; tech display code
    CMP #$FF
    BEQ .fixedstr_skip              ; FF → blank row
    CMP #$FE
    BEQ .fixedstr_skip              ; FE → blank row
    CMP #$FD
    BEQ .unreach_fd                 ; FD → fixed string variant 2 (unreachable)
    CMP #$FC
    BEQ .fixedstr_fc                ; FC → fixed string variant 1
    CMP #$FB
    BNE .tech_name                  ; not special → decode tech name
    LDX.b $88                       ; FB: use scroll index
    BRA .copy_out                   ; → INC $88 + copy path
.fixedstr_fc:
    LDX.w #$0000                    ; string starts at $CCFB4B+0
    BRA .into_fixedstr
.unreach_fd:
    LDX.w #$0012                    ; string starts at $CCFB4B+$12
.into_fixedstr:
    TDC
    TAY
.fixed_copy:
    LDA.l $CCFB4B,X                 ; fixed string byte from ROM
    STA.w $94A0,Y
    INX
    INY
    CPY.w #$0012                    ; 18 bytes
    BNE .fixed_copy
.fixedstr_skip:
    LDX.b $88
    JMP CODE_JP_C10BB6
.tech_name:
    LDX.b $88                       ; save scroll index (carried through to .copy_out)
    REP #$20                        ; M=0
    STA.b $8E                       ; tech ID (16-bit; B=0 from prior TDC)
    ASL A                           ; * 2
    ASL A                           ; * 4
    STA.b $90
    ASL A                           ; * 8
    CLC
    ADC.b $90                       ; * 8 + * 4 = * 12
    SEC
    SBC.b $8E                       ; * 12 - * 1 = * 11
    CLC
    db $69,$C4,$15                  ; ADC #$15C4 — tech name table offset (M=0 3-byte)
    TAX                             ; X = ROM offset in bank $CC
    LDY.w #$94A0                    ; destination
    LDA.w #$000A                    ; 11 bytes (count-1)
    MVN $7E,$CC                     ; copy 11-byte tech name: $CC:X → $7E:$94A0
    TDC
    SEP #$20                        ; M=1
    STA.w $0000,Y                   ; null-terminate at $7E:$94A0+11
    JSR BattleMsg_ReencodeTextBuffer
.copy_out:
    INC.b $88                       ; advance scroll tracker
    JSR BattleMenu_BlankMpCostDigits
    TDC
    TAY
    LDX.b $82
.tech_copy1:
    LDA.w $94A0,Y
    STA.w $9A2F,X
    INX
    LDA #$2D
    STA.w $9A2F,X
    INX
    INY
    CPY.w #$000B
    BNE .tech_copy1
    TDC
    TAY
    LDX.b $82
.tech_copy2:
    LDA.w $94B0,Y
    STA.w $99EF,X
    INX
    LDA #$2D
    STA.w $99EF,X
    INX
    INY
    CPY.w #$000B
    BNE .tech_copy2
    JMP CODE_JP_C10C00
    db $60                          ; dead RTS (unreachable, byte-exact pad)

; $C1:0BB6 — CODE_JP_C10BB6 (29 bytes, $0BB6–$0BD2)
; Blank/fixed-string exit path from BattleMenu_RenderTechRow:
; increments scroll tracker, blanks MP digit fields, then copies
; 18 tile+attr pairs from $94A0 into tech-window buffer $9A29.
; Entry: M=1, X=0 (16-bit), DB=$7E; $82 = column offset
; Exit:  M=1
; Calls: BattleMenu_BlankMpCostDigits ($0BD3)
org $C10BB6
CODE_JP_C10BB6:
    INC.b $88
    JSR BattleMenu_BlankMpCostDigits
    TDC
    TAY
    LDX.b $82
.copy_loop:
    LDA.w $94A0,Y
    STA.w $9A29,X
    INX
    LDA #$2D
    STA.w $9A29,X
    INX
    INY
    CPY.w #$0012                    ; 18 tile+attr pairs
    BNE .copy_loop
    RTS

; $C1:0BD3 — BattleMenu_BlankMpCostDigits (45 bytes, $0BD3–$0BFF)
; Blanks two 3-cell MP-cost digit fields in the tech window:
;   $9A29+$82 and $99E9+$82 (tile=$FF attr=$2D pairs × 3 each).
; Called from BattleMenu_RenderTechRow and CODE_JP_C10BB6.
; Entry: M=1, X=0 (16-bit), DB=$7E; $82 = column offset
; Exit:  M=1; X/Y clobbered
; No JSR/JSL calls.
org $C10BD3
BattleMenu_BlankMpCostDigits:
    TDC
    TAY
    LDX.b $82
.blank1_loop:
    LDA #$FF
    STA.w $9A29,X
    INX
    LDA #$2D
    STA.w $9A29,X
    INX
    INY
    CPY.w #$0003
    BNE .blank1_loop
    TDC
    TAY
    LDX.b $82
.blank2_loop:
    LDA #$FF
    STA.w $99E9,X
    INX
    LDA #$2D
    STA.w $99E9,X
    INX
    INY
    CPY.w #$0003
    BNE .blank2_loop
    RTS

; $C1:0C00 — CODE_JP_C10C00 (45 bytes, $0C00–$0C2C)
; Tech-name exit path from BattleMenu_RenderTechRow:
; blanks two 4-cell tech-window digit fields:
;   $9A45+$82 (MP cost) and $9A05+$82 (second field), 4 pairs each.
; Entry: M=1, X=0 (16-bit), DB=$7E; $82 = column offset
; Exit:  M=1; X/Y clobbered
; No JSR/JSL calls.
org $C10C00
CODE_JP_C10C00:
    TDC
    TAY
    LDX.b $82
.blank1_loop:
    LDA #$FF
    STA.w $9A45,X
    INX
    LDA #$2D
    STA.w $9A45,X
    INX
    INY
    CPY.w #$0004
    BNE .blank1_loop
    TDC
    TAY
    LDX.b $82
.blank2_loop:
    LDA #$FF
    STA.w $9A05,X
    INX
    LDA #$2D
    STA.w $9A05,X
    INX
    INY
    CPY.w #$0004
    BNE .blank2_loop
    RTS

; ==================================================================
; BattleMenu_UpdateWindows ($C10C2D–$C10C48, 28 bytes)
; ==================================================================
; Per-frame window upkeep dispatcher. Loads active-slot ptr via JSL
; $CFFD9E, then dispatches on $95DB (submenu type):
;   0 → BattleMenu_UpdateMainWindow
;   1 → BattleMenu_UpdateTechMpAvail + BattleMenu_UpdateTechWindow
;   other → CODE_JP_C1103D (RTS)
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; registers clobbered by callees
; Callees: JSL $CFFD9E (BattleFx_SetPtrA2FromTable, cross-bank),
;          BattleMenu_UpdateMainWindow, BattleMenu_UpdateTechMpAvail,
;          BattleMenu_UpdateTechWindow
org $C10C2D
BattleMenu_UpdateWindows:
    LDA.w $95D5                     ; active PC slot index
    JSL $CFFD9E                     ; BattleFx_SetPtrA2FromTable (CF bank)
    LDA.w $95DB                     ; submenu type: 0=main, 1=tech, 2=item(→exit)
    BNE .not_main
    JMP BattleMenu_UpdateMainWindow ; type 0 → main command window
.not_main:
    CMP #$01
    BNE CODE_C10C46                 ; type != 1 → exit (type 2 = item, just return)
    JSR BattleMenu_UpdateTechMpAvail ; type 1: refresh tech MP availability first
    JMP BattleMenu_UpdateTechWindow  ; then update tech window display

CODE_C10C46:                        ; shared exit — jumped to from UpdateMainWindow too
    JMP CODE_JP_C1103D              ; → shared RTS at $103D

; ==================================================================
; BattleMenu_UpdateMainWindow ($C10C49–$C10C82, 58 bytes)
; ==================================================================
; Main command-window upkeep (submenu type 0):
; - If $A6DD (active-PC index) changed vs. cached $A6DF:
;     reload command window map ($C11C3A) + rebuild status frame ($C10299).
; - Else: per-slot panel refresh ($C105A7); if $A43F set and $A6DD >= 0,
;     redraw active-panel cursor column ($C10872).
; - If $95D5 < 0: reload command window map again.
; - Always: JSL $CFFD02 (queue $0CC0 VRAM upload), INC $99E2.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1
; Callees: BattleMenu_LoadCommandWindowMap, BattleUI_BuildStatusBarFrame,
;          BattleUI_UpdateNextPcPanel, BattleUI_ClearActivePanelColumn,
;          JSL $CFFD02 (Battle_QueueVramUpload_0CC0, cross-bank)
BattleMenu_UpdateMainWindow:
    LDA.w $95DB                     ; must still be type 0
    BNE CODE_C10C46                 ; if not, bail (offset -8 → $0C46)
    LDA.w $A6DD                     ; current active-PC index
    CMP.w $A6DF                     ; == cached value?
    BEQ .same_pc
    STA.w $A6DF                     ; update cache
    JSR BattleMenu_LoadCommandWindowMap ; reload tilemap ($1C3A)
    JSR BattleUI_BuildStatusBarFrame  ; rebuild status bar ($0299)
    BRA .do_upload
.same_pc:
    JSR BattleUI_UpdateNextPcPanel  ; per-slot panel refresh ($05A7)
    LDA.w $A43F
    BEQ .do_upload
    LDA.w $A6DD
    BMI .do_upload
    JSR BattleUI_ClearActivePanelColumn ; cursor column redraw ($0872)
.do_upload:
    LDA.w $95D5
    BPL .queue
    JSR BattleMenu_LoadCommandWindowMap ; reload again if $95D5 negative
.queue:
    JSL $CFFD02                     ; Battle_QueueVramUpload_0CC0 (CF bank)
    INC.w $99E2
    JMP CODE_JP_C1103D              ; → shared RTS at $103D

; ==================================================================
; BattleMenu_UpdateTechWindow ($C10C83–$C10E59, 471 bytes)
; ==================================================================
; Tech-window content refresh (submenu type 1, called after UpdateTechMpAvail):
; 1. JSR BattleMenu_RenderTechListRows ($0A88) — renders text into $99E3 buffer.
; 2. Copies $180 bytes from $99E3 into window tilemap $A6E1 (word-stride).
; 3. Composes 6-row window border/column structure from $CCFA95 template
;    into $A70B area (9 tiles per row, 6 rows, with Y advancing by $2E stride).
; 4. For each of 3 PCs, if $96F5/$96F6/$96F7 != 0 (PC has techs to show):
;    converts $5E34/$5EB4/$5F34 (MP) to digit tiles via DivTen9499 + BlankLeadingZeros,
;    stores into $A751/$A7D1/$A851 digit cells; else blanks MP cost.
; 5. Resolves active cursor tech slot; copies battler data into $9EE3-$9EE9;
;    for each PC present, converts relevant value to tile digits.
; 6. Falls through into BattleMenu_DrawTechCursorRow ($0E5A).
; Entry: M=1, X=0, DB=$7E; $95D5 = active PC slot
; Exit:  M=1 (via BattleMenu_DrawTechCursorRow → CODE_JP_C1103D)
; Callees: BattleMenu_RenderTechListRows, Battle_DivTen9499,
;          BattleMsg_BlankLeadingZeros, BattleMenu_DrawTechCursorRow (fall-through)
BattleMenu_UpdateTechWindow:
    JSR BattleMenu_RenderTechListRows ; render tech list into $99E3 buffer

    ; Copy $180-byte text buffer $99E3 → window tilemap $A6E1 (word stride:
    ; each tile occupies word pair = 2 bytes tile, 2 bytes attr; read/write by 1)
    TDC
    TAY
    TAX
.copy_loop:
    LDA.w $99E3,X
    STA.w $A6E1,Y
    INX
    INX
    INY
    INY
    CPY.w #$0180
    BNE .copy_loop

    ; Compose window border columns from $CCFA95 template:
    ; outer loop: 6 rows ($80 = row 0..5)
    ; inner loop: 9 tiles per row ($81 = col 0..8) → store into $A70B,Y
    TDC
    TAX
    TAY
    STX.b $80                       ; row counter = 0
.border_row:
    STZ.b $81                       ; col counter = 0
.border_col:
    LDA.l $CCFA95,X                 ; border template byte
    STA.w $A70B,Y                   ; store into tech window tilemap
    INX
    INY
    INY
    INC.b $81
    LDA.b $81
    CMP #$09
    BNE .border_col
    REP #$21                        ; M=0, C=0 for 16-bit add
    TYA
    db $69,$2E,$00                  ; ADC #$002E — advance Y by row stride
    TAY
    TDC
    SEP #$20                        ; M=1
    INC.b $80
    LDA.b $80
    CMP #$06
    BNE .border_row

    ; PC1 MP digits: if $96F5 != 0, convert $5E34 (PC1 MP) → digit tiles
    LDA.w $96F5
    BEQ .pc1_mp_absent              ; $96F5=0 → no PC1 tech, blank
    REP #$20                        ; M=0 for 16-bit PCHP write
    LDA.w $5E34                     ; PC1 MP low byte
    STA.w $9499                     ; PCHP = PC1 MP (16-bit)
    JSR Battle_DivTen9499           ; → M=1; digit tiles in $949C-$949F
    JSR BattleMsg_BlankLeadingZeros ; suppress leading zeros
    LDA.w $949E                     ; tens digit
    STA.w $A751                     ; PC1 tech window tens cell
    LDA.w $949F                     ; ones digit
    STA.w $A753                     ; PC1 tech window ones cell
    LDA #$FF
    STA.w $A75B                     ; blank PC1 cost hi
    STA.w $A75D                     ; blank PC1 cost hi+1
    BRA .pc2_check
.pc1_mp_absent:
    LDA #$FF
    STA.w $A757                     ; blank PC1 MP field

    ; PC2 MP digits: if $96F6 != 0
.pc2_check:
    LDA.w $96F6
    BEQ .pc2_mp_absent
    REP #$20                        ; M=0
    LDA.w $5EB4                     ; PC2 MP low byte
    STA.w $9499
    JSR Battle_DivTen9499           ; → M=1
    JSR BattleMsg_BlankLeadingZeros
    LDA.w $949E
    STA.w $A7D1
    LDA.w $949F
    STA.w $A7D3
    LDA #$FF
    STA.w $A7DB
    STA.w $A7DD
    BRA .pc3_check
.pc2_mp_absent:
    LDA #$FF
    STA.w $A7D7

    ; PC3 MP digits: if $96F7 != 0
.pc3_check:
    LDA.w $96F7
    BEQ .pc3_mp_absent
    REP #$20                        ; M=0
    LDA.w $5F34                     ; PC3 MP low byte
    STA.w $9499
    JSR Battle_DivTen9499           ; → M=1
    JSR BattleMsg_BlankLeadingZeros
    LDA.w $949E
    STA.w $A851
    LDA.w $949F
    STA.w $A853
    LDA #$FF
    STA.w $A85B
    STA.w $A85D
    BRA .cursor_resolve
.pc3_mp_absent:
    LDA #$FF
    STA.w $A857

    ; Resolve active cursor tech slot:
    ; $95D5 → CCF38C table → base offset; add scroll $95EB + cursor $95DF;
    ; look up in $9551 table → battler slot. If $FF, blank all and jump to cursor draw.
.cursor_resolve:
    LDA.w $95D5
    TAX
    LDA.l $CCF38C,X                 ; PC base offset from table
    STA.b $AF
    CLC
    LDA.w $95EB,X                   ; scroll offset (PC1NumberLinesScrolled)
    ADC.w $95DF,X                   ; + cursor position page
    CLC
    ADC.b $AF                       ; + base
    TAX
    LDA.w $9551,X                   ; battler slot at cursor row
    CMP #$FF
    BNE .slot_present
    ; slot == $FF: blank relevant tilemap cells and go to cursor draw
    STA.w $A7DB
    STA.w $A7DD
    STA.w $9EE3
    STA.w $9EE4
    STA.w $9EE5
    STA.w $9EE6
    STA.w $9EE7
    STA.w $9EE8
    STA.w $9EE9
    JMP BattleMenu_DrawTechCursorRow ; → $0E5A

.slot_present:
    ; slot found — copy battler data from $1A80+slot into $9EE3-$9EE9
    STA.b $80                       ; save battler slot
    LDA.w $95D5
    ASL A
    TAX
    LDA.l $CCF395,X                 ; PC tech-table ptr lo
    STA.b $AF
    LDA.l $CCF396,X                 ; PC tech-table ptr hi
    STA.b $B0
    LDA.b $80
    TAX
    LDA.l $CCF3A1,X                 ; battler offset from table
    STA.b $80
    CLC
    LDA.b $AF
    ADC.b $80
    STA.b $AF
    LDA.b $B0
    ADC #$00
    STA.b $B0
    LDX.b $AF
    LDA.w $1A80,X                   ; battler fields → $9EE3-$9EE9
    STA.w $9EE3
    LDA.w $1A81,X
    STA.w $9EE4
    LDA.w $1A82,X
    STA.w $9EE5
    LDA.w $1A83,X
    STA.w $9EE6
    LDA.w $1A84,X
    STA.w $9EE7
    LDA.w $1A85,X
    STA.w $9EE8
    LDA.w $1A86,X
    STA.w $9EE9

    ; For each PC present ($9EE6/$9EE8/$9EE9 >= 0), convert HP-related
    ; value to digit tiles and store into tech window digit cells
    LDA.w $9EE6
    BMI .check_pc2_digit            ; negative → PC1 absent, skip
    REP #$20                        ; M=0: write 16-bit to PCHP
    STA.w $9499
    JSR Battle_DivTen9499           ; → M=1; digit tiles in $949E/$949F
    LDA.w $949E
    CMP #$73                        ; zero digit?
    BNE .pc1_nonzero
    LDA #$FF
    STA.w $A75D                     ; blank hi digit
    LDA.w $949F
    STA.w $A75B
    BRA .check_pc2_digit
.pc1_nonzero:                       ; (UNREACH_C10DFD path: digit != $73)
    STA.w $A75B
    LDA.w $949F
    STA.w $A75D

.check_pc2_digit:
    LDA.w $9EE8
    BMI .check_pc3_digit
    REP #$20
    STA.w $9499
    JSR Battle_DivTen9499           ; → M=1
    LDA.w $949E
    CMP #$73
    BNE .pc2_nonzero
    LDA #$FF
    STA.w $A7DD
    LDA.w $949F
    STA.w $A7DB
    BRA .check_pc3_digit
.pc2_nonzero:                       ; (UNREACH_C10E27 path)
    STA.w $A7DB
    LDA.w $949F
    STA.w $A7DD

.check_pc3_digit:
    LDA.w $9EE9
    BMI BattleMenu_DrawTechCursorRow ; negative → no PC3, go draw cursor
    REP #$20
    STA.w $9499
    JSR Battle_DivTen9499           ; → M=1
    LDA.w $949E
    CMP #$73
    BNE .pc3_nonzero
    LDA #$FF
    STA.w $A85D
    LDA.w $949F
    STA.w $A85B
    BRA BattleMenu_DrawTechCursorRow
.pc3_nonzero:                       ; (UNREACH_C10E51 path)
    STA.w $A85B
    LDA.w $949F
    STA.w $A85D
    ; fall through into BattleMenu_DrawTechCursorRow at $0E5A

; ==================================================================
; BattleMenu_DrawTechCursorRow ($C10E5A–$C10EB9, 96 bytes)
; ==================================================================
; Clears old cursor tiles then draws row cursor ($60-$63) at the
; tech-list row given by $95DF[slot] (indexed via $CCFAE3 offset table)
; into window buffer $A6E1/$A721. Skipped while targeting ($9609 != 0).
; Then queues the tech window VRAM upload (JSL $CFFD36) and conditionally
; copies TechBoxBattles ($D15A50) into $0B40 if $A86A != 0.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1 (via CODE_JP_C1103D)
; Callees: BattleMenu_ClearTechCursorTiles, JSL $CD0027, JSL $CFFD36
BattleMenu_DrawTechCursorRow:
    LDA.w $95D5
    TAX
    LDA.w $95DF,X                   ; cursor row position (PC1CursorPositionPage)
    STA.b $80
    JSR BattleMenu_ClearTechCursorTiles ; clear all cursor tile columns
    LDA.w $9609                     ; targeting flag
    BNE .skip_draw                  ; non-zero = targeting, skip cursor draw
    LDA.b $80                       ; cursor row
    ASL A
    TAX
    REP #$20                        ; M=0: load 16-bit offset from table
    LDA.l $CCFAE3,X                 ; cursor row tilemap Y offset
    TAY
    TDC
    SEP #$20                        ; M=1
    LDA #$60
    STA.w $A6E1,Y                   ; cursor top-left
    LDA #$61
    STA.w $A6E3,Y                   ; cursor top-right
    LDA #$62
    STA.w $A721,Y                   ; cursor bottom-left
    LDA #$63
    STA.w $A723,Y                   ; cursor bottom-right
.skip_draw:
    LDA.w $A0DB                     ; SkillItemInfoSetting
    BPL .queue_upload
    LDA.w $9EE3                     ; item/skill for info panel
    JSL $CD0027                     ; BattleMsg_ShowFromTableCC3A09Vec
.queue_upload:
    JSL $CFFD36                     ; Battle_QueueVramUpload_A6E1 (CF bank)
    LDA.w $A86A
    BEQ .done
    TDC
    TAX
.techbox_loop:
    LDA.l $D15A50,X                 ; TechBoxBattles data
    STA.w $0B40,X                   ; copy into WRAM $0B40
    INX
    CPX.w #$0180
    BNE .techbox_loop
    INC.w $99E2
    STZ.w $A86A
.done:
    JMP CODE_JP_C1103D              ; → shared RTS at $103D

; ==================================================================
; BattleMenu_ClearTechCursorTiles ($C10EBA–$C10EE0, 39 bytes)
; ==================================================================
; Writes $FF over the cursor-column tile slots of all 6 tech-window
; buffer rows ($A6E3/$A6E5, $A723/$A725, $A763/$A765, $A7A3/$A7A5,
; $A7E3/$A7E5, $A823/$A825).
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; A=$FF; X/Y unchanged
; No JSR/JSL calls.
BattleMenu_ClearTechCursorTiles:
    LDA #$FF
    STA.w $A6E3
    STA.w $A6E5
    STA.w $A723
    STA.w $A725
    STA.w $A763
    STA.w $A765
    STA.w $A7A3
    STA.w $A7A5
    STA.w $A7E3
    STA.w $A7E5
    STA.w $A823
    STA.w $A825
    RTS

; ==================================================================
; BattleMenu_UpdateTechMpAvail ($C10EE1–$C1103D, 349 bytes)
; ==================================================================
; Per-row tech-availability sweep for the tech window (submenu type 1).
; For each of 3 tech rows (loop on $82 = 0..2):
;   - Looks up window-column offset ($CCF39B/C), tech-table ptr ($CCF395/6),
;     base offset ($CCF38C + scroll $95EB), and row palette slot ($A6D9).
;   - If slot $94D0,X indicates slot type $FC/$FD (special slots), checks
;     $A6DE party-size; if condition fails → gray the tech cell (attr $2D).
;   - Else: resolves battler ptr ($9551 → $CCF3A1 + $AF/$B0),
;     then checks each PC's MP against the tech MP cost ($1A83/$1A85/$1A86).
;     If all costs affordable and slot is menu-ready: brightens cell (attr $29).
;     If not affordable or locked: grays cell (attr $2D).
;   - Sets $A6E2/A722 columns with computed attr byte (18 entries each).
;   - On $82 reaching 3: sets $A099 = 1 (mark window as updated).
; Entry: M=1, X=0, DB=$7E; $95D5 = active PC slot
; Exit:  M=1 (via CODE_JP_C1103D / fall-through)
; Callees: BattleSys_SlotMenuReadyPredicate ($103E),
;          Battle_ShiftRight4 ($011A)
BattleMenu_UpdateTechMpAvail:
    LDA.w $95D5
    ASL A
    TAX
    LDA.l $CCF395,X                 ; PC tech-table ptr lo
    STA.b $AF
    LDA.l $CCF396,X                 ; PC tech-table ptr hi
    STA.b $B0
    LDA.w $95D5
    TAX
    TAY
    LDA.l $CCF38C,X                 ; PC base offset from table
    STA.b $86
    LDA.w $95EB,Y                   ; scroll offset (PC1NumberLinesScrolled)
    CLC
    ADC.b $86
    TAX
    STX.b $86                       ; $86 = base + scroll (row ptr)
    LDA.w $5E34                     ; PC1 MP lo
    STA.b $96
    LDA.w $5E35                     ; PC1 MP hi
    STA.b $97
    LDA.w $5EB4                     ; PC2 MP lo
    STA.b $98
    LDA.w $5EB5                     ; PC2 MP hi
    STA.b $99
    LDA.w $5F34                     ; PC3 MP lo
    STA.b $9A
    LDA.w $5F35                     ; PC3 MP hi
    STA.b $9B
    TDC
    TAX
    STX.b $82                       ; row counter = 0
    ; outer loop entry point (re-entered via JMP from loop tail):
CODE_JP_C10F28:
    LDA.b $82
    ASL A
    TAX
    LDA.l $CCF39B,X                 ; window column ptr lo
    STA.b $84
    LDA.l $CCF39C,X                 ; window column ptr hi
    STA.b $85
    LDA #$29                        ; default attr = bright (affordable)
    STA.b $94
    LDX.b $86
    LDA.w $94D0,X                   ; slot type byte
    AND #$F0
    CMP #$F0
    BNE _ump_check_battler          ; not special → check battler
    ; special slot type ($Fxx): further checks
    LDA.w $94D0,X
    CMP #$FC
    BNE _ump_check_fd
    LDA.w $A6DE                     ; party-size field
    CMP #$02
    BCC _ump_set_bright             ; party < 2 → bright (gray the unavail tech)
    BRA CODE_C10F66_JMP             ; party >= 2 → gray exit
_ump_check_fd:
    CMP #$FD
    BNE CODE_C10F66_JMP             ; not $FC or $FD → gray
    LDA.w $A6DE
    CMP #$03
    BCS CODE_C10F66_JMP             ; party >= 3 → gray
_ump_set_bright:
    LDA #$2D                        ; attr = gray (tech unavailable for this party size)
    STA.b $94
CODE_C10F66_JMP:                    ; several branches converge here
    JMP CODE_JP_C1100F              ; → write column attrs

_ump_check_battler:
    ; resolve battler slot and tech offsets
    LDA.w $9551,X                   ; battler slot from row ptr
    TAX
    LDA.l $CCF3A1,X                 ; battler offset
    CLC
    ADC.b $AF                       ; + PC tech-table ptr
    STA.b $88
    LDA.b $B0
    ADC #$00
    STA.b $89
    LDX.b $88

    ; check PC1 MP vs tech cost at $1A83,X
    LDA.w $1A83,X
    BMI _ump_pc1_ok                 ; negative = cost 0 → ok
    SEC
    LDA.b $96                       ; PC1 MP lo
    SBC.w $1A83,X                   ; − tech cost lo
    LDA.b $97                       ; PC1 MP hi
    SBC #$00
    BCC _L1001                      ; borrow → can't afford

_ump_pc1_ok:
    ; check PC2 MP vs tech cost at $1A85,X
    LDA.w $1A85,X
    BMI _ump_pc2_ok
    SEC
    LDA.b $98
    SBC.w $1A85,X
    LDA.b $99
    SBC #$00
    BCC _L1001

_ump_pc2_ok:
    ; check PC3 MP vs tech cost at $1A86,X
    LDA.w $1A86,X
    BMI _ump_pc3_ok
    SEC
    LDA.b $9A
    SBC.w $1A86,X
    LDA.b $9B
    SBC #$00
    BCC _L1001

_ump_pc3_ok:
    ; load tech slot id ($1A84,X); check if valid / single / dual
    LDA.w $1A84,X
    STA.b $81
    CMP #$FF                        ; $FF = no tech
    BEQ _ump_slot_ready             ; → treat as ready (won't show)
    AND #$0F                        ; tech slot lo nibble
    STA.b $80
    JSR BattleSys_SlotMenuReadyPredicate ; A=0 if slot ready
    BNE _L1001                      ; not ready → gray
    LDA.b $81
    AND #$F0
    CMP #$F0                        ; dual tech marker?
    BEQ _ump_slot_ready
    JSR Battle_ShiftRight4          ; shift hi nibble down ($011A)
    STA.b $80
    JSR BattleSys_SlotMenuReadyPredicate
    BNE _L1001

_ump_slot_ready:
    ; all checks passed: mark bright, check lock status
    LDA.w $95D5
    TAX
    LDA.w $A0D1,X                   ; PC1HasLockStatus
    BNE _L1001                      ; locked → gray
    LDX.b $88
    LDA.w $1A80,X                   ; EventCommand7A7B (battler type)
    CMP #$74                        ; special type?
    BNE _ump_write_bright
    LDX.w $A0FF
    LDA.w $1C48,X
    CMP #$42                        ; status check
    BNE _L1001                      ; fail → gray

_ump_write_bright:
    LDX.b $88
    LDA.w $1A82,X
    AND #$7F                        ; clear gray bit
    STA.w $1A82,X
    LDA #$29                        ; bright attr
    STA.b $94
    BRA CODE_JP_C1100F              ; → write column attrs

_L1001:                             ; not affordable / locked → gray
    LDX.b $88
    LDA.w $1A82,X
    ORA #$80                        ; set gray bit
    STA.w $1A82,X
    LDA #$2D                        ; gray attr
    STA.b $94
    ; fall through to CODE_JP_C1100F

CODE_JP_C1100F:                     ; write computed attr to column
    LDX.b $84                       ; window column ptr
    LDY.w #$0012                    ; 18 entries
    LDA.b $94                       ; attr byte
.col1_loop:
    STA.w $A6E2,X
    INX
    INX
    DEY
    BNE .col1_loop
    LDX.b $84
    LDY.w #$0012
.col2_loop:
    STA.w $A722,X
    INX
    INX
    DEY
    BNE .col2_loop
    INC.b $86
    INC.b $82
    LDA.b $82
    CMP #$03
    BEQ .done
    JMP CODE_JP_C10F28              ; next row
.done:
    LDA #$01
    STA.w $A099                     ; mark window updated
CODE_JP_C1103D:                     ; shared exit RTS (jumped to from multiple routines)
    RTS

; ==================================================================
; BattleSys_SlotMenuReadyPredicate ($C1103E–$C1104D, 16 bytes)
; ==================================================================
; Returns A=0 if battler for slot $80 is menu-ready (slot's $A6D9,X entry
; is valid / not negative, and $A0D1 lock flag is clear); nonzero otherwise.
; Entry: M=1, X=0 (16-bit), DB=$7E; $80 = battler slot index
; Exit:  M=1; A = 0 (ready) or nonzero (not ready); X clobbered
; No JSR/JSL calls.
BattleSys_SlotMenuReadyPredicate:
    LDA.b $80
    TAX
    LDA.w $A6D9,X                   ; slot state
    BMI .not_ready                  ; negative → slot not active
    TAX
    LDA.w $A0D1,X                   ; PC1HasLockStatus
    BNE .not_ready                  ; locked → not ready
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
; Loads $180 bytes from bank $D1 (TechBoxBattles at $D15800) into
; WRAM $7E:0B40. Used to reload the command window tilemap whenever
; the active PC changes or the menu layout needs refreshing.
; Entry: M=1, X=0 (16-bit), DB=$7E
; Exit:  M=1; X=$0180; A = last byte copied; Y unchanged
; No JSR/JSL calls.
org $C11C3A
BattleMenu_LoadCommandWindowMap:
    TDC
    TAX
.load_loop:
    LDA.l $D15800,X                 ; TechBoxBattles source (bank $D1)
    STA.w $0B40,X                   ; dest WRAM $0B40
    INX
    CPX.w #$0180
    BNE .load_loop
    RTS

; ==================================================================
; BattleMenu_RefreshIfDirtyL ($C110E3–$C110F9, 23 bytes)
; ==================================================================
; JSL-entry twin of BattleMenu_RefreshIfDirtyAndTick, reached via the
; bank's cross-bank entry-vector table: JSL $C10012 -> JMP $C110E3.
; If the menu-dirty flag $993A is set: clear it and rerun the full
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
    LDA.w $993A                     ; menu-dirty flag
    BEQ .exit
    STZ.w $993A                     ; clear flag
    STZ $E5
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
; cross-bank per-frame service tick (JSL $CD0009) before returning via
; plain RTS. Called from several places in the battle-phase state
; machine ($C140A3 and others) once per frame.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; registers clobbered by callees
; Callees: BattleMenu_DequeueReadyBattler, BattleMenu_UpdateWindows,
;          BattleMenu_ProcessInput, BattleMenu_UpdateCursorOverlay,
;          JSL $CD0009 (cross-bank per-frame service tick)
org $C110FA
BattleMenu_RefreshIfDirtyAndTick:
    LDA.w $993A                     ; menu-dirty flag
    BEQ .tick
    STZ.w $993A                     ; clear flag
    STZ $E5
    JSR BattleMenu_DequeueReadyBattler
    JSR BattleMenu_UpdateWindows
    JSR BattleMenu_ProcessInput
    JSR BattleMenu_UpdateCursorOverlay
.tick:
    JSL $CD0009                     ; per-frame service tick (cross-bank)
    RTS

; ==================================================================
; BattleMenu_DrawCursorSprites ($C11115–$C11152, 62 bytes)
; ==================================================================
; Builds the 4 OAM entries for the command-window selection cursor at
; WRAM $0700, positioned relative to the active PC slot ($95D5). Reads
; a 4-tile x/y/tile/attr template from ROM table $CCF604-$CCF607
; (indexed by X = 0,4,8,12) and adds per-slot cursor coordinates from
; $1D0C,Y (X-origin) / $1D23,Y (Y-origin). The attribute byte's low
; palette bits are replaced from the current cursor-flash palette
; ($9F46). Also marks OAM high-table byte $0900 = $AA (all 4 sprites
; present, size bit set). Called from BattleMenu_ProcessInput once per
; frame while the command menu is active.
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; X=$0010; A/Y clobbered
; No JSR/JSL calls.
org $C11115
BattleMenu_DrawCursorSprites:
    TDC
    TAX
    LDA.w $95D5                     ; active PC slot
    TAY
.loop:
    CLC
    LDA.l $CCF604,X                 ; template X-offset
    ADC.w $1D0C,Y                   ; + slot cursor X-origin
    STA.w $0700,X                   ; OAM X
    CLC
    LDA.l $CCF605,X                 ; template Y-offset
    ADC.w $1D23,Y                   ; + slot cursor Y-origin
    STA.w $0701,X                   ; OAM Y
    LDA.l $CCF606,X                 ; template tile index
    STA.w $0702,X
    LDA.l $CCF607,X                 ; template attr byte
    AND #$F1                        ; clear palette bits, keep priority/flip
    ORA.w $9F46                     ; OR in current cursor-flash palette
    STA.w $0703,X
    INX
    INX
    INX
    INX
    CPX #$0010
    BNE .loop
    LDA #$AA
    STA.w $0900                     ; OAM high-table: all 4 sprites, size bit
    RTS

; ==================================================================
; BattleMenu_ProcessInput ($C11153–$C111E0, 142 bytes)
; ==================================================================
; Battle command-window input handler, called once per frame from the
; menu dirty-flag gates (RefreshIfDirtyL/AndTick). Reads two pad-edge
; bytes ($EE, $EF — button/D-pad bits that went low-to-high this
; frame) and dispatches:
;   - no active PC ($95D5 < 0) or target-select active ($9609 != 0):
;     bail out early (ZeroResultEE / TargetSelectInput)
;   - submenu type ($95DB): 1 = tech list, 2 = item list, 0 = main menu
;   - main menu: $A862 (force-confirm) or $EE bit $40 (with $A0D4 cursor-
;     save setting) can jump straight to ConfirmCommand; otherwise polls
;     $EF for Left/Up/Down/Right (cycle PC / move cursor) and $EE bit
;     $80 for confirm
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; tail-jumps to one of several handlers, does not fall through
; Callees: JSL $CFFAE2 (Battle_MergePendingEntries1580, cross-bank),
;          BattleMenu_TargetSelectInput, BattleMenu_DrawCursorSprites,
;          BattleMenu_TechListInput, BattleMenu_ItemListInput,
;          BattleMenu_ConfirmCommand, BattleMenu_CycleActivePcPrev,
;          BattleMenu_CycleActivePcNext, BattleMenu_CursorUp,
;          BattleMenu_CursorDown, Battle_StopSfx, Battle_ZeroResultEE
org $C11153
BattleMenu_ProcessInput:
    JSL $CFFAE2                     ; Battle_MergePendingEntries1580 (cross-bank)
    LDA.w $95D5                     ; active PC slot index
    BPL .slot_valid
    JMP Battle_ZeroResultEE         ; no active PC -> clear pad-edge bytes, return
.slot_valid:
    LDA.w $9609                     ; target-select active flag
    BEQ .not_targeting
    JMP BattleMenu_TargetSelectInput
.not_targeting:
    JSR BattleMenu_DrawCursorSprites
    LDA.w $95DB                     ; submenu type: 0=main, 1=tech, 2=item
    BEQ .main_menu
    DEC
    BNE .item_menu
    LDA.w $99E1                     ; battle-mode setting
    STA.w $99E0
    JMP BattleMenu_TechListInput
.item_menu:
    LDA.w $99E1
    STA.w $99E0
    JMP BattleMenu_ItemListInput
.main_menu:
    STZ.w $A09A
    STZ.w $99E0
    LDA.w $A862
    BNE .confirm                    ; force-confirm flag set -> skip input polling
    LDA.w $A0D4                     ; cursor-position-save setting
    BEQ .poll_dpad
    LDA.w $95D5
    TAX
    LDA $EE                         ; pad-edge byte (button bits)
    AND #$40
    BEQ .poll_dpad
    INC.w $A114
    TDC
    STA.w $95DC,X                   ; force cursor row 0 for this slot
    JMP BattleMenu_ConfirmCommand
.poll_dpad:
    LDA $EF                         ; pad-edge byte (D-pad bits)
    AND #$02                        ; Left
    BEQ .poll_up
    JMP BattleMenu_CycleActivePcPrev
.poll_up:
    LDA $EF
    AND #$08                        ; Up
    BEQ .poll_down
    JSR Battle_StopSfx
    JMP BattleMenu_CursorUp
.poll_down:
    LDA $EF
    AND #$04                        ; Down
    BEQ .poll_right
    JSR Battle_StopSfx
    JMP BattleMenu_CursorDown
.poll_right:
    LDA $EF
    AND #$01                        ; Right
    BEQ .poll_confirm
    JMP BattleMenu_CycleActivePcNext
.poll_confirm:
    LDA $EE
    AND #$80                        ; confirm button
    BEQ .no_input
    JSR Battle_StopSfx
.confirm:
    JMP BattleMenu_ConfirmCommand
.no_input:
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_CycleActivePcPrev ($C111E1–$C11217, 55 bytes)
; ==================================================================
; Left D-pad: decrement active PC index $A6DD (wrap 0..2), skipping
; slots whose $A6D9 entry is invalid (negative). Plays the cursor-move
; SFX unless $A6DE (active PC count) is 1. Carries the previous slot's
; cursor row ($95DC) to the newly-active slot, unless $A0D4 (cursor-
; position-save setting) is set, in which case it instead overwrites
; $95DC for the OLD slot from a per-PC default-row table ($9916) — a
; path the reference disassembly marks as unreachable in practice.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: Battle_StopSfx, Battle_ZeroResultEE
org $C111E1
BattleMenu_CycleActivePcPrev:
    LDA.w $A6DE                     ; active PC count
    DEC
    BEQ .retry                      ; only 1 PC -> skip the cursor-move sound
    JSR Battle_StopSfx
.retry:
    DEC.w $A6DD                     ; active PC index, wrap 0..2
    LDA.w $A6DD
    BPL .have_index
    LDA #$02
    STA.w $A6DD
.have_index:
    TAX
    LDA.w $A6D9,X                   ; slot valid?
    BMI .retry                      ; invalid slot -> keep decrementing
    TAX
    LDA.w $95D5                     ; previous active slot
    TAY
    LDA.w $A0D4                     ; cursor-position-save setting
    BNE .default_row                ; (reference: unreachable in practice)
    LDA.w $95DC,Y                   ; carry cursor row from old slot
    STA.w $95DC,X
    BRA .done
.default_row:
    LDA.w $9916,Y                   ; per-PC default cursor row
    STA.w $95DC,Y
.done:
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_CycleActivePcNext ($C11218–$C1124F, 56 bytes)
; ==================================================================
; Right D-pad: mirror of CycleActivePcPrev — increment $A6DD (wrap at
; 3 back to 0) instead of decrementing.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: Battle_StopSfx, Battle_ZeroResultEE
org $C11218
BattleMenu_CycleActivePcNext:
    LDA.w $A6DE                     ; active PC count
    DEC
    BEQ .retry
    JSR Battle_StopSfx
.retry:
    INC.w $A6DD                     ; active PC index, wrap at 3 -> 0
    LDA.w $A6DD
    CMP #$03
    BNE .have_index
    STZ.w $A6DD
    TDC
.have_index:
    TAX
    LDA.w $A6D9,X                   ; slot valid?
    BMI .retry                      ; invalid slot -> keep incrementing
    TAX
    LDA.w $95D5                     ; previous active slot
    TAY
    LDA.w $A0D4                     ; cursor-position-save setting
    BNE .default_row                ; (reference: unreachable in practice)
    LDA.w $95DC,Y                   ; carry cursor row from old slot
    STA.w $95DC,X
    BRA .done
.default_row:
    LDA.w $9916,Y                   ; per-PC default cursor row
    STA.w $95DC,Y
.done:
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_CursorUp ($C11250–$C11263, 20 bytes)
; ==================================================================
; Up D-pad: decrement the active PC's menu cursor row $95DC (wrap 0..2),
; flag a redraw via $A43F.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: Battle_ZeroResultEE
org $C11250
BattleMenu_CursorUp:
    LDA.w $95D5                     ; active PC slot
    TAX
    DEC.w $95DC,X
    BPL .done
    LDA #$02
    STA.w $95DC,X
.done:
    INC.w $A43F                     ; flag redraw
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_CursorDown ($C11264–$C1127A, 23 bytes)
; ==================================================================
; Down D-pad: increment the active PC's menu cursor row $95DC, wrap at
; 3 back to 0, flag a redraw via $A43F.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: Battle_ZeroResultEE
org $C11264
BattleMenu_CursorDown:
    LDA.w $95D5                     ; active PC slot
    TAX
    INC.w $95DC,X
    LDA.w $95DC,X
    CMP #$03
    BNE .done
    STZ.w $95DC,X
.done:
    INC.w $A43F                     ; flag redraw
    JMP Battle_ZeroResultEE

; ==================================================================
; Battle_ZeroResultEE ($C1179C–$C117A0, 5 bytes)
; ==================================================================
; Clears both pad-edge bytes ($EE, $EF) and returns. Shared tail used
; by most of the command-window input handlers above once they've
; consumed this frame's input.
; Entry: M=1, DB=$7E
; Exit:  M=1; $EE=$EF=0
; No JSR/JSL calls.
org $C1179C
Battle_ZeroResultEE:
    STZ $EE
    STZ $EF
    RTS

; ==================================================================
; BattleMenu_EnqueueReadyBattler ($C11B19–$C11B54, 60 bytes)
; ==================================================================
; Service 1 of the cross-bank $C10045 service API (dispatch table at
; $C10051: service 0 -> $0023, 1 -> here, 2 -> RemoveBattlerFromReady).
; Called when battler slot $A1 becomes ready for a command (presumably
; its ATB gauge filled): appends it to the ATB-ready queue that
; BattleMenu_DequeueReadyBattler later pops from.
;
; Skipped entirely if the slot is already in the active roster
; ($A6D9,X non-negative). Otherwise: sets bit 7 of the battler's
; sprite flag byte at $93EE (via the $CCFAF0 slot->sprite lookup) —
; the same bit ConsumePartnerSlot/CommitAction clear, i.e. "waiting
; for a command" — writes the slot to the queue tail ($95D6+count),
; resets the battler's menu cursor row ($95DC,X) to its per-PC
; default ($9916,X), bumps the queue count ($95DA), and plays a sound
; cue through the same SPC command $19 interface Battle_StopSfx uses,
; here with $1E01 = $42 instead of 0 (inferred: the "turn ready" cue).
;
; Note: does not check whether the slot is already queued; callers
; are trusted not to enqueue twice.
;
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E; $A1 = battler slot
; Exit:  M=1; registers clobbered
; Callees: JSL $C70004 (Audio_Process_Entry, cross-bank)
org $C11B19
BattleMenu_EnqueueReadyBattler:
    LDA $A1                         ; battler slot that became ready
    TAX
    LDA.w $A6D9,X                   ; roster presence (<0 = absent)
    BPL .exit                       ; already in the active roster
    LDA.l $CCFAF0,X                 ; slot -> sprite index
    TAX
    LDA.w $93EE,X
    ORA #$80                        ; mark "waiting for command"
    STA.w $93EE,X
    LDA.w $95DA                     ; queue count = tail index
    TAX
    LDA $A1
    STA.w $95D6,X                   ; append slot to ready queue
    TAX
    LDA.w $9916,X                   ; per-PC default cursor row
    STA.w $95DC,X
    INC.w $95DA                     ; queue count
    LDA #$42                        ; sound id (turn-ready cue, inferred)
    STA.w $1E01
    LDA #$19                        ; SPC command $19
    STA.w $1E00
    LDA #$80
    STA.w $1E02
    JSL $C70004                     ; Audio_Process_Entry (cross-bank)
.exit:
    RTS

; ==================================================================
; Battle_StopSfx ($C11B55–$C11B66, 18 bytes)
; ==================================================================
; SPC audio command $19 dispatcher (mirrors bank $C0's Sub_1B90
; pattern): sets $1E00-$1E02 and JSLs into the audio driver entry.
; Used here to play/cancel a sound cue when the cursor moves or a
; command is confirmed.
; Entry: M=1, DB=$7E
; Exit:  M=1
; Callees: JSL $C70004 (Audio_Process_Entry, cross-bank)
org $C11B55
Battle_StopSfx:
    STZ.w $1E01
    LDA #$19
    STA.w $1E00
    LDA #$80
    STA.w $1E02
    JSL $C70004
    RTS

; ==================================================================
; BattleMenu_ConfirmCommand ($C1127B–$C1129B, 33 bytes)
; ==================================================================
; Confirm-button dispatch: sets a sentinel at $A0D7 (compared elsewhere,
; e.g. BattleUI_BuildStatusBarFrame, to force a status-bar refresh),
; reloads the active-PC pointer via JSL $CFFD9E, then reads the active
; PC's menu cursor row ($95DC,X: 0/1/2 = Attack/Tech/Item) and tail-
; jumps to the matching row handler.
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; tail-jumps to one of three row handlers, does not fall through
; Callees: JSL $CFFD9E (BattleFx_SetPtrA2FromTable, cross-bank),
;          BattleMenu_ChooseAttack, BattleMenu_OpenTechList,
;          BattleMenu_OpenItemList
org $C1127B
BattleMenu_ConfirmCommand:
    LDA #$FF
    STA.w $A0D7                     ; sentinel: force refresh elsewhere
    LDA.w $95D5
    JSL $CFFD9E                     ; BattleFx_SetPtrA2FromTable (cross-bank)
    LDA.w $95D5
    TAX
    LDA.w $95DC,X                   ; menu cursor row for active PC
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
; Row 0 (Attack) confirm: shows the command message, flags two redraws
; via $A43F, sets target mode $960D=$07 (attack targeting), clears
; $9615 (submenu-open marker), builds the valid-target list, then
; enters target-select mode by incrementing $9609.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: JSL $CD002D (BattleMsg_ShowMsg0BIfKeyChangedVec, cross-bank),
;          BattleMenu_BuildTargetList, Battle_ZeroResultEE
org $C1129C
BattleMenu_ChooseAttack:
    LDA #$FF
    JSL $CD002D                     ; BattleMsg_ShowMsg0BIfKeyChangedVec (cross-bank)
    INC.w $A43F                     ; flag redraw
    INC.w $A43F                     ; flag redraw (twice)
    LDA #$07
    STA.w $960D                     ; target mode: attack
    STZ.w $9615                     ; submenu-open marker: none
    JSR BattleMenu_BuildTargetList
    INC.w $A4EE
    INC.w $9609                     ; enter target-select mode
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_OpenTechList ($C112BC–$C112EC, 49 bytes)
; ==================================================================
; Row 1 (Tech) confirm: unless $A0A7 bit 0 is set (tech list locked),
; renders the tech list rows, builds per-tech availability flags,
; switches the submenu to tech ($95DB=1, $9615=1), and marks the tech
; window active ($A86A).
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: BattleMenu_RenderTechListRows, BattleMenu_BuildTechAvailFlags,
;          Battle_ZeroResultEE
org $C112BC
BattleMenu_OpenTechList:
    LDA.w $A0A7
    AND #$01
    BNE .exit                       ; tech list locked -> no-op
    LDA #$FF
    STA.w $9EE7
    STZ.w $A09A
    STZ.w $A099
    INC.w $A862
    JSR BattleMenu_RenderTechListRows
    JSR BattleMenu_BuildTechAvailFlags
    STZ.w $A862
    LDA #$01
    STA.w $9615                     ; submenu-open marker: tech
    LDA #$01
    STA.w $95DB                     ; submenu type: tech list
    STZ.w $A869
    INC.w $A86A                     ; mark tech window active
.exit:
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_OpenItemList ($C112ED–$C1131F, 51 bytes)
; ==================================================================
; Row 2 (Item) confirm: unless $A0A7 is set (item list locked), renders
; the item list rows, queues the $0E80 tilemap for VRAM upload, copies
; the $180-byte item-window graphic (ROM $D15BD0, "ItemBoxBattles")
; into the command-window tilemap $0B40, and switches the submenu to
; item ($95DB=2).
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: BattleMenu_RenderItemListRows,
;          JSL $CFFD6A (Battle_QueueVramUpload_0E80, cross-bank),
;          Battle_ZeroResultEE
org $C112ED
BattleMenu_OpenItemList:
    LDA.w $A0A7
    BNE .exit                       ; item list locked -> no-op
    STZ.w $A09A
    LDA #$02
    STA.w $9615                     ; submenu-open marker: item
    LDA.w $95E6                     ; item-list scroll position
    STA $80
    JSR BattleMenu_RenderItemListRows
    JSL $CFFD6A                     ; Battle_QueueVramUpload_0E80 (cross-bank)
    TDC
    TAX
.copy_loop:
    LDA.l $D15BD0,X                 ; ItemBoxBattles (bank $D1)
    STA.w $0B40,X
    INX
    CPX #$0180
    BNE .copy_loop
    INC.w $99E2
    LDA #$02
    STA.w $95DB                     ; submenu type: item list
.exit:
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_BuildTargetList ($C11F79–$C11FDC, 100 bytes)
; ==================================================================
; Resets the target-selection state ($9613/$960A/$960C/$A64F/$A6D8),
; blanks the 11-entry candidate list ($99C0-$99CA) and selection list
; ($A62D-$A637) to $FF, then — unless already in a "return to main
; menu on cancel" state — snapshots the current submenu type into
; $A86B and reloads the command window map so cancelling target-select
; comes back to the right screen.
;
; The actual target-collection work is fully mode-specific: it clamps
; $960D (target mode, low 7 bits) to $00-$20, doubles it for a word
; index, and JSRs indirectly through a jump table at $11FF8 (bank-
; local target-mode handler table; the individual handlers and the
; table's contents are a separate, much larger unmatched targeting
; subsystem — see BANK_MAP.md). After the handler returns, if every
; slot in the selection list is empty (all $FF), the result byte $9613
; is set from whatever value fell out of the scan (defensive fallback
; for "no valid targets").
;
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; X/Y clobbered
; Callees: BattleMenu_LoadCommandWindowMap; JSR ($1FF8,X) into the
;          (unmatched) target-mode handler table
org $C11F79
BattleMenu_BuildTargetList:
    LDA.w $95D5                     ; active PC slot
    TAX
    STX.w $960F                     ; remember requesting slot
    STZ.w $9613                     ; result: no target yet
    STZ.w $960C
    STZ.w $960A
    STZ.w $A64F
    STZ.w $A6D8
    LDX #$000B
    LDA #$FF
.clear_loop:
    STA.w $99C0,X                   ; candidate list slot -> empty
    STA.w $A62D,X                   ; selection list slot -> empty
    DEX
    BPL .clear_loop
    LDA.w $960D                     ; target mode
    BPL .have_mode
    LDA.w $A86B                     ; saved submenu type (cancel target)
    BNE .have_mode
    LDA.w $95DB                     ; current submenu type
    INC
    STA.w $A86B                     ; save it for cancel-to-return
    STZ.w $95DB
    LDA #$FE
    STA.w $A6DF
    INC.w $A09A
    JSR BattleMenu_LoadCommandWindowMap
.have_mode:
    LDA.w $960D
    AND #$7F                        ; strip high bit
    CMP #$21
    BCC .in_range
    LDA #$20                        ; clamp to table size
.in_range:
    ASL                             ; word index
    TAX
    JSR (BattleTgt_ModeTable,X)     ; target-mode handler table
    TDC
    TAX
.scan_empty:
    LDA.w $A62D,X                   ; selection list slot
    BPL .done                       ; found a real target -> done
    INX
    CPX #$000B
    BNE .scan_empty
    STA.w $9613                     ; all empty -> fallback result
.done:
    RTS

; ==================================================================
; BattleTgt_RunAreaQuery ($C11FDD–$C11FE9, 13 bytes)
; ==================================================================
; Service 7 of the cross-bank $C10045 service API (dispatch table at
; $C10051). Runs one of the area-target geometry routines, selected by
; $99CC (0-6) through the 7-entry table just below; out-of-range
; selectors are ignored. The same geometry routines back the menu's
; area-effect target modes (see BattleTgt_ModeTable), so this is
; presumably how non-menu code (enemy scripts, scripted attacks) asks
; "which battlers does this area hit?".
; Entry: M=1, X=0, DB=$7E; $99CC = area type, $9604-$9608 = params
; Exit:  M=1
; Callees: JSR ($1FEA,X) -> BattleTgt_AreaLine/AreaCircle/
;          AreaPartyTriangle/AreaRow
org $C11FDD
BattleTgt_RunAreaQuery:
    LDA.w $99CC                     ; area type selector
    CMP #$07
    BCS .exit                       ; out of range -> no-op
    ASL
    TAX
    JSR (BattleTgt_AreaTable,X)
.exit:
    RTS

; BattleTgt_AreaTable ($C11FEA–$C11FF7, 7 words)
BattleTgt_AreaTable:
    dw BattleTgt_AreaLine           ; 0
    dw BattleTgt_AreaCircle           ; 1
    dw BattleTgt_AreaCircle           ; 2
    dw BattleTgt_AreaPartyTriangle           ; 3
    dw BattleTgt_AreaLine           ; 4
    dw BattleTgt_AreaPartyTriangle           ; 5
    dw BattleTgt_AreaRow           ; 6

; ==================================================================
; BattleTgt_ModeTable ($C11FF8–$C12039, 33 words)
; ==================================================================
; Target-mode handler table, indexed by ($960D & $7F) clamped to $20,
; called from BattleMenu_BuildTargetList. Each handler fills the
; 11-entry candidate list ($99C0-$99CA, battler slots: 0-2 = PCs,
; 3-10 = enemies) and seeds the selection list ($A62D...) from the
; cursor ($9614). $960C = $80 means "target everything in the list";
; $960A non-zero means the player may cycle the cursor; $9613 = $80
; means "no valid target".
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
    dw BattleTgt_EnemyRow      ; $0F
    dw BattleTgt_SingleAlly         ; $10
    dw BattleTgt_CasterRadius       ; $11
    dw BattleTgt_EnemyRadius        ; $12
    dw BattleTgt_Char3Radius        ; $13
    dw BattleTgt_Char3Radius        ; $14
    dw BattleTgt_SingleAlly         ; $15
    dw BattleTgt_SingleAlly         ; $16
    dw BattleTgt_SingleAlly         ; $17
    dw BattleTgt_PartyTriangle       ; $18
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
; other list modes enter with their own slot range ($80 = end
; exclusive, X = start) and flags.
;
; CollectValidTargets keeps battler X only if it is present ($96F5,X),
; not flagged out ($9FF7,X bit 7 clear), not hidden ($A09B,X zero) and
; — if $A0A8,X is set (inferred: KO'd) — only when the mode is $04.
; The requesting battler ($960F) always goes to the front ($99C0);
; everyone else is appended from $99C1. CompactCandidates then closes
; the hole if the requester wasn't eligible. Finally the cursor entry
; is copied to the selection list, or the whole list when $960C says
; "target all".
; Entry: M=1, X=0, DB=$7E (all BattleTgt_* handlers)
; Exit:  M=1
; Callees: BattleTgt_CompactCandidates
org $C1203A
BattleTgt_SingleAlly:
    LDX #$0003
    STX $80                         ; end slot (exclusive): PCs 0-2
    LDX #$0000                      ; start slot
    INC.w $960A                     ; cursor may cycle
BattleTgt_CollectValidTargets:
    TDC
    TAY                             ; Y = append index
.loop:
    LDA.w $96F5,X                   ; battler present?
    BEQ .next
    LDA.w $9FF7,X
    BMI .next                       ; flagged out
    LDA.w $A0A8,X                   ; KO'd? (inferred)
    BEQ .check_hidden
    LDA.w $960D
    AND #$7F
    CMP #$04                        ; only mode $04 may pick these
    BNE .next
.check_hidden:
    LDA.w $A09B,X
    BNE .next                       ; hidden / untargetable
    CPX.w $960F                     ; requesting battler?
    BNE .append
    LDA.w $960F
    STA.w $99C0                     ; requester goes first
    BRA .next
.append:
    TXA
    STA.w $99C1,Y
    INY
.next:
    INX
    CPX $80
    BNE .loop
    JSR BattleTgt_CompactCandidates
    LDA.w $9614                     ; cursor -> selection
    TAX
    LDA.w $99C0,X
    STA.w $A62D
    LDA.w $960C
    BPL .exit
    LDX #$000A                      ; target all: copy whole list
.copy_all:
    LDA.w $99C0,X
    STA.w $A62D,X
    DEX
    BPL .copy_all
.exit:
    RTS

; BattleTgt_AllAllies ($C1209A–$C120A8, 15 bytes): every PC
BattleTgt_AllAllies:
    LDX #$0003
    STX $80
    LDX #$0000
    LDA #$80
    STA.w $960C                     ; target all
    BRA BattleTgt_CollectValidTargets

; BattleTgt_SingleEnemy ($C120A9–$C120B5, 13 bytes): one enemy (3-10),
; cursor may cycle. Also called as a list builder by the area modes.
BattleTgt_SingleEnemy:
    LDX #$000B
    STX $80
    LDX #$0003
    INC.w $960A
    BRA BattleTgt_CollectValidTargets

; BattleTgt_AllEnemies ($C120B6–$C120C5, 16 bytes)
BattleTgt_AllEnemies:
    LDX #$000B
    STX $80
    LDX #$0003
    LDA #$80
    STA.w $960C
    JMP BattleTgt_CollectValidTargets

; BattleTgt_Everyone ($C120C6–$C120D5, 16 bytes): all battlers 0-10
BattleTgt_Everyone:
    LDX #$000B
    STX $80
    LDX #$0000
    LDA #$80
    STA.w $960C
    JMP BattleTgt_CollectValidTargets

; BattleTgt_Self ($C120D6–$C120DF, 10 bytes): the active PC only
BattleTgt_Self:
    LDA.w $95D5                     ; active PC slot
    STA.w $99C0
    STA.w $A62D
    RTS

; ==================================================================
; BattleTgt_SingleKoAlly ($C120E0–$C12135, 86 bytes)
; ==================================================================
; Lists the PCs whose status byte (+$4A in each PC's $80-byte battle
; record at $5E00) has bit 7 set — by context, KO'd allies, i.e. a
; revive target. Unrolled for the three PC slots. No candidate ->
; $9613 = $80.
BattleTgt_SingleKoAlly:
    INC.w $960A
    TDC
    TAX
    LDA.w $96F5                     ; PC 0
    BEQ .pc1
    LDA.w $A09B
    BNE .pc1
    LDA.w $5E4A
    BPL .pc1
    STZ.w $99C0
    INX
.pc1:
    LDA.w $96F6                     ; PC 1
    BEQ .pc2
    LDA.w $A09C
    BNE .pc2
    LDA.w $5ECA
    BPL .pc2
    LDA #$01
    STA.w $99C0,X
    INX
.pc2:
    LDA.w $96F7                     ; PC 2
    BEQ .check_any
    LDA.w $A09D
    BNE .check_any
    LDA.w $5F4A
    BPL .check_any
    LDA #$02
    STA.w $99C0,X
.check_any:
    LDA.w $99C0
    BPL .select
    LDA #$80
    STA.w $9613                     ; no valid target
.select:
    LDA.w $9614
    TAX
    LDA.w $99C0,X
    STA.w $A62D
    RTS

; ==================================================================
; BattleTgt_PcByCharId5 ($C12136–$C12162, 45 bytes)
; ==================================================================
; Targets the one party member whose $2980,X entry equals $80 (5 for
; this entry, 4 via BattleTgt_PcByCharId4). In bank $C1, $2980-$2982
; behaves like the party's character-id list; if so these are
; "target Ayla"/"target Frog" modes, used by dual/triple techs that
; act on a specific partner.
BattleTgt_PcByCharId5:
    LDA #$05
    STA $80
BattleTgt_FindPcByCharId:
    INC.w $960A
    LDX #$0002
.loop:
    LDA.w $96F5,X
    BEQ .next
    LDA.w $A09B,X
    BNE .next
    LDA.w $2980,X                   ; party member id (inferred)
    CMP $80
    BEQ .found
.next:
    DEX
    BPL .loop
    LDA #$80
    STA.w $9613                     ; not in party / not targetable
    BRA .exit
.found:
    TXA
    STA.w $99C0
    STA.w $A62D
.exit:
    RTS

; BattleTgt_PcByCharId4 ($C12163–$C12168, 6 bytes)
BattleTgt_PcByCharId4:
    LDA #$04
    STA $80
    BRA BattleTgt_FindPcByCharId

; ==================================================================
; Area modes ($C12169–$C12331)
; ==================================================================
; All of these pick an anchor (the caster, a chosen enemy, or a
; specific party member), fill the $9604-$9608 parameter block, run an
; area-geometry routine that writes the hit list into $99C0, then
; select the whole list (BattleTgt_SelectAllCandidates).
;   $9605 = source/centre battler, $9606 = aimed-at battler,
;   $9607 = shape/size code, $9608 = variant flag, $9604 = 0
; The enemy-anchored ones build the enemy list first and let the pad
; move the aim: $EF bits $09 / $06 each play Battle_StopSfx and step
; the cursor. Note the three "line" modes step forward for both pad
; groups; the radius/row modes step backward for the second group.

; BattleTgt_EnemyLineFromCaster ($C12169–$C121AE, 70 bytes)
BattleTgt_EnemyLineFromCaster:
    JSR BattleTgt_SingleEnemy
    STZ.w $960A
    LDA #$80
    STA.w $960C
    LDA $EF
    AND #$09
    BEQ .check_other
    JSR Battle_StopSfx
    JSR BattleTgt_CycleNext
    BRA .setup
.check_other:
    LDA $EF
    AND #$06
    BEQ .setup
    JSR Battle_StopSfx
    JSR BattleTgt_CycleNext
.setup:
    STZ.w $9604
    LDA.w $960F
    STA.w $9605                     ; source: caster
    LDA.w $9614
    TAX
    LDA.w $99C0,X
    STA.w $9606                     ; aimed-at enemy
    LDA #$02
    STA.w $9607
    STZ.w $9608
    JSR BattleTgt_AreaLine
    JMP BattleTgt_SelectAllCandidates

; BattleTgt_EnemyLineFromChar3 ($C121AF–$C12202, 84 bytes): as above,
; but the source is the party member with id 3 (no-op if absent)
BattleTgt_EnemyLineFromChar3:
    JSR BattleTgt_SingleEnemy
    STZ.w $960A
    LDA #$80
    STA.w $960C
    LDA $EF
    AND #$09
    BEQ .check_other
    JSR Battle_StopSfx
    JSR BattleTgt_CycleNext
    BRA .find_source
.check_other:
    LDA $EF
    AND #$06
    BEQ .find_source
    JSR Battle_StopSfx
    JSR BattleTgt_CycleNext
.find_source:
    TDC
    TAX
.find_loop:
    LDA.w $2980,X
    CMP #$03
    BEQ .found
    INX
    CPX #$0003
    BNE .find_loop
    RTS
.found:
    TXA
    STA.w $9605                     ; source: party member id 3
    STZ.w $9604
    LDA.w $9614
    TAX
    LDA.w $99C0,X
    STA.w $9606
    LDA #$02
    STA.w $9607
    STZ.w $9608
    JSR BattleTgt_AreaLine
    JMP BattleTgt_SelectAllCandidates

; BattleTgt_EnemyLineFromCaster2 ($C12203–$C1224A, 72 bytes): same as
; EnemyLineFromCaster with variant flag $9608 = 1
BattleTgt_EnemyLineFromCaster2:
    JSR BattleTgt_SingleEnemy
    STZ.w $960A
    LDA #$80
    STA.w $960C
    LDA $EF
    AND #$09
    BEQ .check_other
    JSR Battle_StopSfx
    JSR BattleTgt_CycleNext
    BRA .setup
.check_other:
    LDA $EF
    AND #$06
    BEQ .setup
    JSR Battle_StopSfx
    JSR BattleTgt_CycleNext
.setup:
    STZ.w $9604
    LDA.w $960F
    STA.w $9605
    LDA.w $9614
    TAX
    LDA.w $99C0,X
    STA.w $9606
    LDA #$02
    STA.w $9607
    LDA #$01
    STA.w $9608
    JSR BattleTgt_AreaLine
    JMP BattleTgt_SelectAllCandidates

; BattleTgt_CasterRadius ($C1224B–$C1225E, 20 bytes): area $10 around
; the caster
BattleTgt_CasterRadius:
    STZ.w $9604
    LDA.w $960F
    STA.w $9605
    LDA #$10
    STA.w $9607
    JSR BattleTgt_AreaCircle
    JMP BattleTgt_SelectAllCandidates

; BattleTgt_EnemyRadius ($C1225F–$C122A3, 69 bytes): area around a
; chosen enemy; size $19 for mode $1A, else $09
BattleTgt_EnemyRadius:
    JSR BattleTgt_SingleEnemy
    STZ.w $960A
    LDA $EF
    AND #$09
    BEQ .check_other
    JSR Battle_StopSfx
    JSR BattleTgt_CycleNext
    BRA .setup
.check_other:
    LDA $EF
    AND #$06
    BEQ .setup
    JSR Battle_StopSfx
    JSR BattleTgt_CyclePrev
.setup:
    STZ.w $9604
    LDA.w $9614
    TAX
    LDA.w $99C0,X
    STA.w $9605                     ; centre: chosen enemy
    LDA.w $960D
    AND #$7F
    CMP #$1A
    BNE .small
    LDA #$19
    BRA .set_size
.small:
    LDA #$09
.set_size:
    STA.w $9607
    JSR BattleTgt_AreaCircle
    JMP BattleTgt_SelectAllCandidates

; BattleTgt_Char3Radius ($C122A4–$C122D2, 47 bytes): area around party
; member id 3; size $19 for mode $14, else $10
BattleTgt_Char3Radius:
    STZ.w $9604
    TDC
    TAX
.find_loop:
    LDA.w $2980,X
    CMP #$03
    BEQ .found
    INX
    CPX #$0003
    BNE .find_loop
    RTS
.found:
    TXA
    STA.w $9605
    LDA.w $960D
    AND #$7F
    CMP #$14
    BNE .small
    LDA #$19
    BRA .set_size
.small:
    LDA #$10
.set_size:
    STA.w $9607
    JSR BattleTgt_AreaCircle
    JMP BattleTgt_SelectAllCandidates

; BattleTgt_Char6Radius ($C122D3–$C122F4, 34 bytes): area $19 around
; party member id 6
BattleTgt_Char6Radius:
    STZ.w $9604
    TDC
    TAX
.find_loop:
    LDA.w $2980,X
    CMP #$06
    BEQ .found
    INX
    CPX #$0003
    BNE .find_loop
    RTS
.found:
    TXA
    STA.w $9605
    LDA #$19
    STA.w $9607
    JSR BattleTgt_AreaCircle
    JMP BattleTgt_SelectAllCandidates

; BattleTgt_EnemyRow ($C122F5–$C12328, 52 bytes incl. dead RTS):
; chosen enemy as anchor for BattleTgt_AreaRow (a +/-$20 band around
; the anchor's $1D23 screen y)
BattleTgt_EnemyRow:
    JSR BattleTgt_SingleEnemy
    STZ.w $960A
    LDA $EF
    AND #$09
    BEQ .check_other
    JSR Battle_StopSfx
    JSR BattleTgt_CycleNext
    BRA .setup
.check_other:
    LDA $EF
    AND #$06
    BEQ .setup
    JSR Battle_StopSfx
    JSR BattleTgt_CyclePrev
.setup:
    STZ.w $9604
    LDA.w $9614
    TAX
    LDA.w $99C0,X
    STA.w $9605
    JSR BattleTgt_AreaRow
    JMP BattleTgt_SelectAllCandidates
    RTS                             ; dead byte after the tail JMP, preserved

; BattleTgt_PartyTriangle ($C12329–$C12331, 9 bytes): enemies inside
; the triangle formed by the three PCs (BattleTgt_AreaPartyTriangle)
BattleTgt_PartyTriangle:
    STZ.w $9604
    JSR BattleTgt_AreaPartyTriangle
    JMP BattleTgt_SelectAllCandidates

; ==================================================================
; BattleTgt_AreaRow ($C12332–$C123A3, 114 bytes)
; ==================================================================
; "Row" area: every eligible battler on the scanned side whose screen
; y ($1D23,X) lies within +/-$20 of the centre battler's y. The window
; is clamped to $00-$FF (TDC on borrow, $FF on carry) and both ends are
; inclusive. Only y is tested, so the shape is a horizontal band across
; the whole field (inferred from the arithmetic; the in-game name of
; the techs using it is not established here).
;
; Scanned side: $9604 = 0 scans enemies (slots 3-10), non-zero scans
; PCs (slots 0-2); the same convention as the other area routines.
; Eligibility is the usual set (present $96F5, not flagged out $9FF7
; bit 7, $A0A8 clear, not hidden $A09B). The centre battler is skipped
; in the scan and then written unconditionally to $99C0 — it is not
; checked for eligibility, and no CompactCandidates pass runs.
; Entry: M=1, X=0, DB=$7E; $9604 side, $9605 centre slot
; Exit:  M=1; $99C0 = centre, $99C1.. = hits, rest $FF
; Callees: BattleTgt_ClearLists
org $C12332
BattleTgt_AreaRow:
    LDA.w $9605                     ; centre battler
    TAX
    STX $88                         ; $88/$89 = centre slot (16-bit)
    SEC
    LDA.w $1D23,X
    SBC #$20                        ; low edge = y - $20
    BCS .lo_ok
    TDC                             ; clamp at 0
.lo_ok:
    STA $85
    CLC
    LDA.w $1D23,X
    ADC #$20                        ; high edge = y + $20
    BCC .hi_ok
    LDA #$FF                        ; clamp at $FF
.hi_ok:
    STA $87
    JSR BattleTgt_ClearLists
    LDX #$000B
    STX $90                         ; end (exclusive) = 11
    LDX #$0003
    STX $8E                         ; start = 3 (enemies)
    LDA.w $9604
    BEQ .scan
    STX $90                         ; non-zero: end = 3 ...
    TDC
    TAX
    STX $8E                         ; ... start = 0 (PCs)
.scan:
    TDC
    TAY                             ; Y = append index
.loop:
    LDX $8E
    CPX $88
    BEQ .next                       ; skip the centre itself
    LDA.w $96F5,X
    BEQ .next                       ; not present
    LDA.w $9FF7,X
    BMI .next                       ; flagged out
    LDA.w $A0A8,X
    BNE .next                       ; KO'd (inferred)
    LDA.w $A09B,X
    BNE .next                       ; hidden / untargetable
    LDA.w $1D23,X
    CMP $85
    BCC .next                       ; above the band
    CMP $87
    BEQ .hit
    BCS .next                       ; below the band
.hit:
    LDA $8E
    STA.w $99C1,Y
    INY
.next:
    INC $8E
    LDA $8E
    CMP $90
    BNE .loop
    LDA $88
    STA.w $99C0                     ; centre always heads the list
    RTS

; ==================================================================
; BattleTgt_AreaPartyTriangle ($C123A4–$C125A2, 511 bytes)
; ==================================================================
; Enemies inside the triangle whose corners are the screen positions of
; party slots 0, 1 and 2 ($1D0C/$1D23 for X = 0-2). The slots are read
; unconditionally, so all three PCs are assumed present (by context:
; this backs mode $18 and area types 3/5, presumably triple techs).
;
; 1. Copy the corners to P0 ($80,$81), P1 ($82,$83), P2 ($84,$85).
; 2. Three compare-and-swap passes order them by x: P2 = leftmost,
;    P1 = rightmost, P0 = middle. Then fix the winding: if P2 and P0
;    share an x, or P0 and P1 do, the pair is ordered by y; otherwise
;    if P0's y is greater than P1's or P2's, P1 and P2 are swapped
;    (inferred purpose: a consistent vertex winding so each corner's
;    interior angle runs "from" one edge "to" the other).
; 3. Calc_Delta16 gives the direction angle of each edge as seen from
;    each corner: P0 -> [$86,$87], P1 -> [$88,$89], P2 -> [$8A,$8B].
;    $92/$93/$94 flag corners whose range wraps past angle 0.
; 4. For each enemy slot 3-10 that is eligible, the angle from every
;    corner to the enemy must fall inside that corner's range (with
;    wrap handled as an OR instead of an AND). Inside all three wedges
;    = inside the triangle.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to BattleTgt_CompactCandidates (the scan only
;        appends from $99C1, so the $FF front slot is always closed up)
; Callees: Calc_Delta16, BattleTgt_ClearLists, BattleTgt_CompactCandidates
; Note: $9604 is ignored here; the scan is always over the enemies.
org $C123A4
BattleTgt_AreaPartyTriangle:
    TDC
    TAX
    STX $92                         ; clear wrap flags $92/$93
    STX $94                         ; and $94
    LDA.w $1D0C                     ; P0 = PC slot 0
    STA $80
    LDA.w $1D23
    STA $81
    LDA.w $1D0D                     ; P1 = PC slot 1
    STA $82
    LDA.w $1D24
    STA $83
    LDA.w $1D0E                     ; P2 = PC slot 2
    STA $84
    LDA.w $1D25
    STA $85
    ; --- sort by x ---
    LDA $84
    CMP $80
    BCC .sort2                      ; x2 < x0: keep
    PHA                             ; swap P0 <-> P2
    LDA $80
    STA $84
    PLA
    STA $80
    LDA $85
    PHA
    LDA $81
    STA $85
    PLA
    STA $81
.sort2:
    LDA $84
    CMP $82
    BCC .sort3                      ; x2 < x1: keep
    PHA                             ; swap P1 <-> P2
    LDA $82
    STA $84
    PLA
    STA $82
    LDA $85
    PHA
    LDA $83
    STA $85
    PLA
    STA $83
.sort3:
    LDA $80
    CMP $82
    BCC .winding                    ; x0 < x1: keep
    PHA                             ; swap P0 <-> P1
    LDA $82
    STA $80
    PLA
    STA $82
    LDA $81
    PHA
    LDA $83
    STA $81
    PLA
    STA $83
    ; --- winding / tie-break ---
.winding:
    LDA $84
    CMP $80
    BNE .tie01                      ; x2 != x0
    LDA $85
    CMP $81
    BCS .edges                      ; y2 >= y0: keep
    PHA                             ; swap P0 <-> P2
    LDA $81
    STA $85
    PLA
    STA $81
    LDA $84
    PHA
    LDA $80
    STA $84
    PLA
    STA $80
    BRA .edges
.tie01:
    LDA $80
    CMP $82
    BNE .by_y                       ; x0 != x1
    LDA $83
    CMP $81
    BCS .edges                      ; y1 >= y0: keep
    PHA                             ; swap P0 <-> P1
    LDA $81
    STA $83
    PLA
    STA $81
    LDA $82
    PHA
    LDA $80
    STA $82
    PLA
    STA $80
    BRA .edges
.by_y:
    LDA $81
    CMP $83
    BEQ .cmp_y2
    BCS .swap12                     ; y0 > y1
.cmp_y2:
    LDA $81
    CMP $85
    BEQ .edges
    BCC .edges                      ; y0 <= y2: keep
.swap12:
    LDA $84                         ; swap P1 <-> P2
    PHA
    LDA $82
    STA $84
    PLA
    STA $82
    LDA $85
    PHA
    LDA $83
    STA $85
    PLA
    STA $83
    ; --- per-corner edge angles ---
.edges:
    LDA $80
    STA $D3
    LDA $81
    STA $D4
    LDA $82
    STA $D5
    LDA $83
    STA $D6
    JSR Calc_Delta16                ; P0 vs P1
    STA $86
    LDA $84
    STA $D5
    LDA $85
    STA $D6
    JSR Calc_Delta16                ; P0 vs P2
    STA $87
    LDA $82
    STA $D3
    LDA $83
    STA $D4
    JSR Calc_Delta16                ; P1 vs P2
    STA $88
    LDA $80
    STA $D5
    LDA $81
    STA $D6
    JSR Calc_Delta16                ; P1 vs P0
    STA $89
    LDA $84
    STA $D3
    LDA $85
    STA $D4
    JSR Calc_Delta16                ; P2 vs P0
    STA $8A
    LDA $82
    STA $D5
    LDA $83
    STA $D6
    JSR Calc_Delta16                ; P2 vs P1
    STA $8B
    LDA $87
    CMP $86
    BCS .wrap1
    INC $92                         ; P0 range wraps
.wrap1:
    LDA $89
    CMP $88
    BCS .wrap2
    INC $93                         ; P1 range wraps
.wrap2:
    LDA $8B
    CMP $8A
    BCS .scan_init
    INC $94                         ; P2 range wraps
.scan_init:
    JSR BattleTgt_ClearLists
    LDX #$000B
    STX $90                         ; end (exclusive) = 11
    LDX #$0003
    STX $8E                         ; start = 3 (enemies only)
    TDC
    TAY                             ; Y = append index
.loop:
    LDX $8E
    LDA.w $96F5,X
    BEQ .skip                       ; not present
    LDA.w $9FF7,X
    BMI .skip                       ; flagged out
    LDA.w $A0A8,X
    BNE .skip                       ; KO'd (inferred)
    LDA.w $A09B,X
    BEQ .test                       ; visible -> test it
.skip:
    JMP .next                       ; (too far for a branch)
.test:
    LDA.w $1D0C,X                   ; D5/D6 = candidate
    STA $D5
    LDA.w $1D23,X
    STA $D6
    LDA $80                         ; seen from P0
    STA $D3
    LDA $81
    STA $D4
    JSR Calc_Delta16
    LDA $92
    BNE .p0_wrap
    LDA $DB
    CMP $86
    BCC .next                       ; below range
    LDA $87
    CMP $DB
    BCC .next                       ; above range
    BRA .p1
.p0_wrap:
    LDA $87
    CMP $DB
    BCS .p1                         ; <= upper: in
    LDA $DB
    CMP $86
    BCC .next                       ; neither side
.p1:
    LDA $82                         ; seen from P1
    STA $D3
    LDA $83
    STA $D4
    JSR Calc_Delta16
    LDA $93
    BNE .p1_wrap
    LDA $DB
    CMP $88
    BCC .next
    LDA $89
    CMP $DB
    BCC .next
    BRA .p2
.p1_wrap:
    LDA $89
    CMP $DB
    BCS .p2
    LDA $DB
    CMP $88
    BCC .next
.p2:
    LDA $84                         ; seen from P2
    STA $D3
    LDA $85
    STA $D4
    JSR Calc_Delta16
    LDA $94
    BNE .p2_wrap
    LDA $DB
    CMP $8A
    BCC .next
    LDA $8B
    CMP $DB
    BCC .next
    BRA .hit
.p2_wrap:
    LDA $8B
    CMP $DB
    BCS .hit
    LDA $DB
    CMP $8A
    BCC .next
.hit:
    LDA $8E
    STA.w $99C1,Y                   ; inside the triangle
    INY
.next:
    INC $8E
    LDA $8E
    CMP $90
    BEQ .done
    JMP .loop
.done:
    JMP BattleTgt_CompactCandidates

; ==================================================================
; BattleTgt_AreaLine ($C125A3–$C12700, 350 bytes)
; ==================================================================
; "Line" area from the source battler ($9605) towards the aimed-at
; battler ($9606), half-width r = $9607 * 8 (scale passed to
; Battle_SinLookup via $AE; $9607 = $02 from every caller seen).
;
; θ = Calc_Delta16 angle between source (D3/D4) and target (D5/D6).
; Two corner points are offset sideways from the line using
; Battle_SinLookup at θ, θ+$C0, θ+$80, θ+$40 (256 units per turn):
;   PA ($80,$81) = source + r*(sin θ, sin(θ+$C0))
;   PB ($82,$83) = variant 0: source + r*(sin(θ+$80), sin(θ+$40))
;                  variant 1: target + the same offset
; Each corner gets a 90-degree wedge of accepted angles:
;   PA: [θ, θ+$40]                          ($84,$86; wrap flag $8C)
;   PB: variant 0 [θ+$C0, θ], variant 1 [θ+$80, θ+$C0] ($88,$8A; $8D)
; A battler is hit when its angle from both corners falls inside both
; wedges, i.e. it lies in the strip between the two offset edges
; (inferred geometry; variant 1, $9608 != 0, moves PB to the target
; end, presumably closing the strip into a box between the two).
;
; The aimed-at battler ($9606, kept in $92) is skipped by the scan and
; re-added by the shared tail BattleTgt_AreaAddAnchor if it is on the
; scanned side. Scanned side follows $9604 as in BattleTgt_AreaRow.
; Entry: M=1, X=0, DB=$7E; $9604-$9608 as above
; Exit:  M=1; via BattleTgt_AreaAddAnchor -> CompactCandidates
; Callees: Calc_Delta16, Battle_SinLookup, BattleTgt_ClearLists
org $C125A3
BattleTgt_AreaLine:
    LDA.w $9607
    ASL
    ASL
    ASL
    STA $AE                         ; radius scale = size * 8
    LDA.w $9605
    TAX                             ; X = source
    LDA.w $9606
    TAY                             ; Y = aimed-at
    LDA.w $1D0C,X
    STA $D3
    LDA.w $1D23,X
    STA $D4
    LDA.w $1D0C,Y
    STA $D5
    LDA.w $1D23,Y
    STA $D6
    JSR Calc_Delta16                ; A = $DB = θ
    JSR Battle_SinLookup
    STA $80                         ; r*sin θ
    CLC
    LDA $DB
    ADC #$C0
    JSR Battle_SinLookup
    STA $81                         ; r*sin(θ+$C0)
    CLC
    LDA $DB
    ADC #$80
    JSR Battle_SinLookup
    STA $82                         ; r*sin(θ+$80)
    CLC
    LDA $DB
    ADC #$40
    JSR Battle_SinLookup
    STA $83                         ; r*sin(θ+$40)
    CLC
    LDA $D3
    ADC $80
    STA $80                         ; PA = source + offset
    CLC
    LDA $D4
    ADC $81
    STA $81
    LDA $DB
    STA $84                         ; PA wedge low = θ
    CLC
    LDA $DB
    ADC #$40
    STA $86                         ; PA wedge high = θ+$40
    LDA.w $9608
    BNE .variant1
    CLC
    LDA $D3
    ADC $82
    STA $82                         ; PB = source + opposite offset
    CLC
    LDA $D4
    ADC $83
    STA $83
    CLC
    LDA $DB
    ADC #$C0
    STA $88                         ; PB wedge low = θ+$C0
    CLC                             ; (unneeded: no add follows)
    LDA $DB
    STA $8A                         ; PB wedge high = θ
    BRA .wrap_flags
.variant1:
    CLC
    LDA $D5
    ADC $82
    STA $82                         ; PB = target + opposite offset
    CLC
    LDA $D6
    ADC $83
    STA $83
    CLC
    LDA $DB
    ADC #$80
    STA $88                         ; PB wedge low = θ+$80
    CLC
    LDA $DB
    ADC #$C0
    STA $8A                         ; PB wedge high = θ+$C0
.wrap_flags:
    STZ $8C
    STZ $8D
    LDA $84
    CMP #$C0
    BCC .wrap_b
    INC $8C                         ; PA wedge wraps past 0
.wrap_b:
    LDA $88
    CMP #$C0
    BCC .scan_init
    INC $8D                         ; PB wedge wraps past 0
.scan_init:
    JSR BattleTgt_ClearLists
    LDX #$000B
    STX $90                         ; end (exclusive) = 11
    LDX #$0003
    STX $8E                         ; start = 3 (enemies)
    LDA.w $9604
    BEQ .anchor
    STX $90                         ; non-zero: PCs 0-2
    TDC
    TAX
    STX $8E
.anchor:
    LDA.w $9606
    TAX
    STX $92                         ; anchor = aimed-at battler
    TDC
    TAY                             ; Y = append index
.loop:
    LDX $8E
    LDA.w $96F5,X
    BEQ .next                       ; not present
    LDA.w $9FF7,X
    BMI .next                       ; flagged out
    LDA.w $A0A8,X
    BNE .next                       ; KO'd (inferred)
    LDA.w $A09B,X
    BNE .next                       ; hidden / untargetable
    CPX $92
    BEQ .next                       ; anchor: added by the tail
    LDA.w $1D0C,X                   ; D5/D6 = candidate
    STA $D5
    LDA.w $1D23,X
    STA $D6
    LDA $80                         ; seen from PA
    STA $D3
    LDA $81
    STA $D4
    JSR Calc_Delta16
    LDA $8C
    BNE .a_wrap
    LDA $DB
    CMP $84
    BCC .next
    LDA $86
    CMP $DB
    BCC .next
    BRA .corner_b
.a_wrap:
    LDA $86
    CMP $DB
    BCS .corner_b
    LDA $DB
    CMP $84
    BCC .next
.corner_b:
    LDA $82                         ; seen from PB
    STA $D3
    LDA $83
    STA $D4
    JSR Calc_Delta16
    LDA $8D
    BNE .b_wrap
    LDA $DB
    CMP $88
    BCC .next
    LDA $8A
    CMP $DB
    BCC .next
    BRA .hit
.b_wrap:
    LDA $8A
    CMP $DB
    BCS .hit
    LDA $DB
    CMP $88
    BCC .next
.hit:
    LDA $8E
    STA.w $99C1,Y                   ; inside the line
    INY
.next:
    INC $8E
    LDA $8E
    CMP $90
    BEQ .done
    JMP .loop
.done:
    JMP BattleTgt_AreaAddAnchor     ; shared tail in AreaCircle

; ==================================================================
; BattleTgt_AreaCircle ($C12701–$C127C4, 196 bytes)
; ==================================================================
; "Circle" area around the centre battler ($9605). Positions are
; reduced to 16-pixel cells (Battle_ShiftRight4) and a battler is hit
; when dx^2 + dy^2 <= $9607, using the 16-entry squares table at
; $CC:FB6F (0, 1, 4, 9, ... $E1). The sizes callers pass, $09/$10/$19,
; are 3^2/4^2/5^2, i.e. radii of 3, 4 and 5 cells. The 8-bit ADC of
; the two squares can wrap (e.g. 15^2 + 7^2 = $112 -> $12) and admit a
; very distant battler; reproduced as found, and probably unreachable
; given on-screen distances.
;
; The 16-bit centre cells ($80/$81, $82/$83) are stored with STY after
; TAY, so their high bytes are whatever the B accumulator held; the
; M=0 subtraction later assumes those are 0 (callers reach here with
; B clear — inferred, not proven).
;
; The centre is skipped in the scan and re-added by the tail below,
; BattleTgt_AreaAddAnchor (also the tail of BattleTgt_AreaLine): with
; $9604 = 0 the anchor ($92) goes to $99C0 only if it is an enemy
; (slot >= 3), with $9604 != 0 only if it is a PC — i.e. only if it
; belongs to the side that was scanned. Otherwise falls through into
; BattleTgt_CompactCandidates (which also runs after the anchor is
; placed, as a no-op since $99C0 is then filled).
; Entry: M=1, X=0, DB=$7E; $9604 side, $9605 centre, $9607 radius^2
; Exit:  M=1; falls through into BattleTgt_CompactCandidates
; Callees: Battle_ShiftRight4, BattleTgt_ClearLists
org $C12701
BattleTgt_AreaCircle:
    LDA.w $9605
    TAX                             ; X = centre
    LDA.w $1D0C,X
    JSR Battle_ShiftRight4          ; x / 16
    TAY
    STY $80                         ; centre cell x (16-bit)
    LDA.w $1D23,X
    JSR Battle_ShiftRight4          ; y / 16
    TAY
    STY $82                         ; centre cell y (16-bit)
    JSR BattleTgt_ClearLists
    LDX #$000B
    STX $90                         ; end (exclusive) = 11
    LDX #$0003
    STX $8E                         ; start = 3 (enemies)
    LDA.w $9604
    BEQ .anchor
    STX $90                         ; non-zero: PCs 0-2
    TDC
    TAX
    STX $8E
.anchor:
    LDA.w $9605
    TAX
    STX $92                         ; anchor = centre battler
    TDC
    TAY                             ; Y = append index
.loop:
    LDX $8E
    LDA.w $96F5,X
    BEQ .next                       ; not present
    LDA.w $9FF7,X
    BMI .next                       ; flagged out
    LDA.w $A0A8,X
    BNE .next                       ; KO'd (inferred)
    LDA.w $A09B,X
    BNE .next                       ; hidden / untargetable
    CPX $92
    BEQ .next                       ; anchor: added by the tail
    LDA.w $1D0C,X
    JSR Battle_ShiftRight4
    STA $84
    STZ $85                         ; $84/$85 = cell x
    LDA.w $1D23,X
    JSR Battle_ShiftRight4
    STA $86
    STZ $87                         ; $86/$87 = cell y
    REP #$20                        ; A -> 16-bit
    SEC
    LDA $84
    SBC $80
    BPL .dx_pos
    EOR.w #$FFFF
    INC A                           ; |dx|
.dx_pos:
    STA $84
    SEC
    LDA $86
    SBC $82
    BPL .dy_pos
    EOR.w #$FFFF
    INC A                           ; |dy|
.dy_pos:
    STA $86
    TDC                             ; clear B before going 8-bit
    SEP #$20                        ; A -> 8-bit
    LDA $84
    TAX
    LDA.l $CCFB6F,X                 ; dx^2
    STA $84
    LDA $86
    TAX
    LDA.l $CCFB6F,X                 ; dy^2
    CLC
    ADC $84
    CMP.w $9607
    BEQ .hit
    BCS .next                       ; outside the radius
.hit:
    CLC                             ; (unneeded: no add follows)
    LDA $8E
    STA.w $99C1,Y
    INY
.next:
    INC $8E
    LDA $8E
    CMP $90
    BNE .loop
BattleTgt_AreaAddAnchor:
    LDA.w $9604
    BNE .pc_side
    LDA $92
    CMP #$03
    BCC BattleTgt_CompactCandidates ; enemy scan, anchor is a PC
    BRA .place
.pc_side:
    LDA $92
    CMP #$03
    BCS BattleTgt_CompactCandidates ; PC scan, anchor is an enemy
.place:
    LDA $92
    STA.w $99C0                     ; anchor heads the list
    ; falls through into BattleTgt_CompactCandidates ($C127C5)

; ==================================================================
; Candidate-list helpers ($C127C5–$C1283C, 120 bytes)
; ==================================================================

; BattleTgt_CompactCandidates ($C127C5–$C127D8, 20 bytes): if the
; front slot is empty (requester wasn't eligible), shift the list
; left by one. Reads one byte past the list ($99CB) on the last step.
org $C127C5
BattleTgt_CompactCandidates:
    LDA.w $99C0
    BPL .exit
    TDC
    TAX
.loop:
    LDA.w $99C1,X
    STA.w $99C0,X
    INX
    CPX #$000B
    BNE .loop
.exit:
    RTS

; BattleTgt_ClearLists ($C127D9–$C127E7, 15 bytes): blank candidate
; and selection lists (12 entries each, one more than they use)
BattleTgt_ClearLists:
    LDX #$000B
    LDA #$FF
.loop:
    STA.w $99C0,X
    STA.w $A62D,X
    DEX
    BPL .loop
    RTS

; BattleTgt_SelectAllCandidates ($C127E8–$C127F9, 18 bytes): set
; target-all and copy the 11 candidates into the selection list
BattleTgt_SelectAllCandidates:
    LDA #$80
    STA.w $960C
    LDX #$000A
.loop:
    LDA.w $99C0,X
    STA.w $A62D,X
    DEX
    BPL .loop
    RTS

; BattleTgt_CycleNext ($C127FA–$C12813, 26 bytes): advance $9614 to the
; next non-empty candidate (wrap at 11); no-op on an empty list. Same
; logic as BattleMenu_TargetNext, duplicated rather than shared.
BattleTgt_CycleNext:
    JSR BattleTgt_AnyCandidate
    BEQ .exit                       ; list empty
.loop:
    INC.w $9614
    LDA.w $9614
    CMP #$0B
    BNE .check
    TDC
    STA.w $9614
.check:
    TAX
    LDA.w $99C0,X
    BMI .loop
.exit:
    RTS

; BattleTgt_CyclePrev ($C12814–$C1282C, 25 bytes): mirror of CycleNext
BattleTgt_CyclePrev:
    JSR BattleTgt_AnyCandidate
    BEQ .exit
.loop:
    DEC.w $9614
    LDA.w $9614
    BPL .check
    LDA #$0A
    STA.w $9614
.check:
    TAX
    LDA.w $99C0,X
    BMI .loop
.exit:
    RTS

; BattleTgt_AnyCandidate ($C1282D–$C1283C, 16 bytes): Z=1 if all 11
; candidate slots are $FF, Z=0 as soon as one isn't
BattleTgt_AnyCandidate:
    TDC
    TAX
.loop:
    LDA.w $99C0,X
    CMP #$FF
    BNE .exit
    INX
    CPX #$000B
    BNE .loop
.exit:
    RTS

; ==================================================================
; BattleMenu_DequeueReadyBattler ($C11B67–$C11BA9, 67 bytes)
; ==================================================================
; Pops the head of the ATB-ready queue ($95D6-$95D9, up to 3 deep,
; count in $95DA) into the active menu roster: restores that battler's
; saved cursor position ($A863/$A866 -> $95DF/$95EB), marks it present
; in the roster ($A6D9,X = X, i.e. identity-maps the slot), forces a
; command-window reload sentinel ($A6DF = $FE), shifts the queue down
; one slot, decrements the queue count, and increments the active-PC
; count ($A6DE). If no PC was already active ($A6DD negative), makes
; the newly dequeued battler the active one.
;
; Note: the second queue-shift step reads $95D8 twice (into both
; $95D7 and $95D9) rather than reading $95D9 for the second copy —
; reproduced exactly as found; harmless in practice since $95DA (the
; live count) never exceeds what the shift correctly updates.
;
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; X = dequeued slot index (or unchanged if queue was empty)
; No JSR/JSL calls.
org $C11B67
BattleMenu_DequeueReadyBattler:
    LDA.w $95D6                     ; queue head
    BMI .exit                       ; queue empty -> nothing to do
    TAX
    STZ.w $9F38,X                   ; clear per-slot pending flag
    LDA.w $A863,X                   ; saved cursor row
    STA.w $95DF,X
    LDA.w $A866,X                   ; saved cursor scroll
    STA.w $95EB,X
    LDA.w $95D6
    TAX
    STA.w $A6D9,X                   ; mark slot present (identity-map)
    LDA #$FE
    STA.w $A6DF                     ; force command-window reload
    LDA.w $95D7
    STA.w $95D6                     ; shift queue down
    LDA.w $95D8
    STA.w $95D7
    LDA.w $95D8
    STA.w $95D9
    DEC.w $95DA                     ; queue count
    INC.w $A6DE                     ; active PC count
    LDA.w $A6DD
    BPL .exit                       ; already have an active PC
    TXA
    STA.w $A6DD                     ; make the dequeued battler active
.exit:
    RTS

; ==================================================================
; BattleMenu_RemoveBattlerFromReady ($C11BAA–$C11C39, 144 bytes)
; ==================================================================
; Service 2 of the cross-bank $C10045 service API (see the entry-vector
; table near the top of this bank). Removes battler slot $A1 from the
; menu-ready state, whether it's currently queued (in $95D6-$95D9) or
; already the active menu PC.
;
; If queued: scans the queue for a matching entry and shifts everything
; after it down by one (a generalized version of DequeueReadyBattler's
; shift, starting from wherever the match was found instead of always
; slot 0), then decrements the queue count.
;
; If it's the active roster slot ($A6D9,X non-negative): decrements the
; active-PC count. If it wasn't the currently-displayed active PC
; ($95D5), just clears its roster presence and forces a redraw. If it
; WAS the active PC, additionally cancels any open submenu/targeting
; state ($9609/$960E/$9614/$95DB/$99E0), clears its roster slot, then
; scans for another valid roster slot to promote to active (or sets
; "no active PC" if none remain).
;
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E; $A1 = battler slot to remove
; Exit:  M=1; registers clobbered
; Callees: BattleMenu_LoadCommandWindowMap
org $C11BAA
BattleMenu_RemoveBattlerFromReady:
    TDC
    TAX
    LDA $A1                         ; battler slot to remove
    STA $80
    TAX
    LDA.w $A6D9,X                   ; roster presence value for this slot
    BPL .active_roster
    TDC
    TAX
    LDA $80
.scan_queue:
    CMP.w $95D6,X
    BEQ .shift_queue
    INX
    CPX #$0003
    BNE .scan_queue
    RTS                              ; not queued -> nothing to remove
.shift_queue:
    LDA.w $95D7,X
    STA.w $95D6,X
    INX
    CPX #$0003
    BCC .shift_queue
    DEC.w $95DA                     ; queue count
    RTS
.active_roster:
    DEC.w $A6DE                     ; active PC count
    CMP.w $95D5                     ; is this slot the current active PC?
    BEQ .removing_active_pc
    LDA $A1
    TAX
    LDA #$FF
    STA.w $A6D9,X                   ; clear roster presence
    LDA #$FE
    STA.w $A6DF                     ; force command-window reload
    BRA .redraw
.removing_active_pc:
    LDA.w $A86B                     ; saved submenu type (cancel target)
    BEQ .clear_targeting
    DEC
    STA.w $95DB
    STZ.w $A86B
    STZ.w $A09A
.clear_targeting:
    STZ.w $9609                     ; target-select mode
    STZ.w $960E
    STZ.w $9614
    STZ.w $95DB                     ; submenu type -> main
    STZ.w $99E0
    LDA #$FE
    STA.w $A6DF                     ; force command-window reload
    LDA $A1
    TAX
    LDA #$FF
    STA.w $A6D9,X                   ; clear roster presence
    TDC
    TAX
.find_next_active:
    LDA.w $A6D9,X                   ; next roster slot's presence value
    STA.w $A6DD
    STA.w $95D5
    BPL .redraw                     ; found a valid slot -> promote it
    INX
    CPX #$0003
    BNE .find_next_active
    LDA #$FF                        ; none left -> no active PC
    STA.w $A6DD
    STA.w $95D5
.redraw:
    JSR BattleMenu_LoadCommandWindowMap
    STZ.w $A862
    RTS

; ==================================================================
; BattleMenu_TargetSelectInput ($C11561–$C11619, 185 bytes)
; ==================================================================
; Per-frame input handler while target-select mode is active (entered
; from BattleMenu_ProcessInput when $9609 != 0). Rebuilds the target
; list every call, then either cancels back to the previous menu
; (no valid target, or cancel button $EE bit $08) or polls for
; confirm ($EE bits $C0) / cycle-target ($EF bits) input.
;
; The cancel path restores whichever submenu was open before targeting
; started ($A86B), redrawing its window contents (tech: just re-flags
; $A86A; item: reloads the $180-byte ItemBoxBattles graphic). It then
; falls through to a cursor-highlight update (OAM attr OR $55, four
; X-position bytes set to $F0) shared with the non-cancel exit path.
;
; Contains one 18-byte block of dead code ($115B6-$115C7): a byte-for-
; byte duplicate of the item-graphic copy loop above it, except its
; loop-continue branch (BNE) targets the input-polling code at $15E8
; instead of looping back on itself — meaning on real hardware it always
; escapes after exactly one iteration rather than functioning as a copy
; loop. Nothing in this routine's control flow can reach these bytes
; (both preceding paths branch past them via BRA); reproduced exactly
; regardless, since matching the ROM means matching orphaned bytes too.
;
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; tail-jumps to one of several handlers, does not fall through
; Callees: BattleMenu_BuildTargetList, Battle_StopSfx,
;          BattleMenu_CommitAction, BattleMenu_TargetNext,
;          BattleMenu_TargetPrev, Battle_ZeroResultEE
org $C11561
BattleMenu_TargetSelectInput:
    JSR BattleMenu_BuildTargetList
    LDA.w $9613                     ; target result (from BuildTargetList)
    BPL .have_target
    STZ.w $9614
    BRA .cancel
.have_target:
    LDA $EE                         ; pad-edge byte (button bits)
    AND #$08                        ; cancel button
    BEQ .poll_input
    JSR Battle_StopSfx
.cancel:
    STZ.w $9614
    STZ.w $960E
    DEC.w $9609                     ; leave target-select mode
    LDA.w $A86B                     ; saved submenu type
    BEQ .redraw_cursor
    DEC
    STA.w $95DB
    STZ.w $A09A
    STZ.w $A86B
    LDA.w $95DB
    DEC
    BEQ .tech_return                ; $95DB was 1 (tech) -> just re-flag it
    TDC                              ; else (item) -> reload item window gfx
    TAX
.copy_loop1:
    LDA.l $D15BD0,X                 ; ItemBoxBattles (bank $D1)
    STA.w $0B40,X
    INX
    CPX #$0180
    BNE .copy_loop1
    LDA #$FF
    STA.w $9920
    INC.w $99E2
    BRA .redraw_cursor
.tech_return:
    STZ.w $A869
    INC.w $A86A
    BRA .redraw_cursor
; --- dead code: unreachable, see routine header ---
    TDC
    TAX
.dead_copy_loop:
    LDA.l $D15BD0,X
    STA.w $0B40,X
    INX
    CPX #$0180
    BNE .poll_input                 ; escapes into live code after 1 iteration
    INC.w $99E2
.redraw_cursor:
    LDA.w $95DB
    BNE .cursor_drawn
    INC.w $A43F
.cursor_drawn:
    LDA.w $0900                     ; OAM high-table
    ORA #$55
    STA.w $0900
    LDA #$F0
    STA.w $0701                     ; cursor sprite X positions
    STA.w $0705
    STA.w $0709
    STA.w $070D
    BRA .exit
.poll_input:
    LDA $EE
    AND #$C0                        ; confirm buttons
    BEQ .check_cycle
    JSR Battle_StopSfx
    JMP BattleMenu_CommitAction
.check_cycle:
    LDA.w $960C                     ; target-all flag
    BMI .exit                       ; target-all -> no per-target cycling
    LDA $EF                         ; pad-edge byte (D-pad bits)
    AND #$05                        ; right/down
    BEQ .check_prev
    INC.w $A4EE
    JSR Battle_StopSfx
    JMP BattleMenu_TargetNext
.check_prev:
    LDA $EF
    AND #$0A                        ; left/up
    BEQ .exit
    INC.w $A4EE
    JSR Battle_StopSfx
    JMP BattleMenu_TargetPrev
.exit:
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_CommitAction ($C1161A–$C11749, 308 bytes)
; ==================================================================
; Confirms the currently-selected target and builds the command
; record for the active PC's chosen action (attack/tech/item), then
; enqueues it and hands the menu focus to the next ready battler.
;
; Restores whichever submenu was saved for cancel-to-return ($A86B),
; then dispatches on $95DB (0=attack, 1=tech, 2=item) to fill in
; type-specific fields:
;   attack: $80=$80 (type flag), $82=$FF (no tech/item id)
;   tech:   saves cursor position if $A0D5 set; consumes the primary
;           partner slot from $9EE7's low nibble (and, for a triple-
;           tech, the high nibble too via Battle_ShiftRight4) so those
;           slots don't also act this round; $80=$20, $82/$84 = tech
;           id/table row from $9EE7/$9EE3
;   item:   decrements the item's stock count ($1583,X from $9F36),
;           $80=$40, $82=$FF, $84=item id ($9F35); clears the item-
;           list scroll position unless $A0D5 is set
; All three converge to build/queue the record: save the current
; menu-cursor row as this PC's remembered row (unless $A114 override
; is set) via BattleUI's $9916 table, then write an 8-byte command
; record at $93EE+(sprite index from $CCFAF0 lookup): type byte
; (bit 6 = "queued"), the $80/$9F38 flag byte, submenu type ($9615),
; target ($A62D), and the tech/item id pair ($82/$84). Finally clears
; this PC's roster slot, advances the active-PC index/count, and
; scans for another valid roster slot to promote (or clears active-PC
; if none remain — same shape as BattleMenu_RemoveBattlerFromReady's
; tail).
;
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: BattleMenu_ConsumePartnerSlot, Battle_ShiftRight4,
;          Battle_ZeroResultEE
org $C1161A
BattleMenu_CommitAction:
    LDA.w $A86B                     ; saved submenu type (cancel target)
    BEQ .dispatch
    DEC
    STA.w $95DB
    STZ.w $A86B
.dispatch:
    DEC.w $9609                     ; leave target-select mode
    LDA.w $95DB                     ; confirmed submenu: 0=attack,1=tech,2=item
    BNE .not_attack
    LDA #$80                        ; type flag: attack
    STA $80
    LDA #$FF                        ; no tech/item id
    STA $82
    BRA .after_type
.not_attack:
    DEC
    BNE .item_path
    LDA.w $A0D5                     ; save-skill-cursor setting
    BEQ .tech_partner_check
    LDA.w $95D5
    TAX
    LDA.w $95EB,X
    STA.w $A866,X
    LDA.w $95DF,X
    STA.w $A863,X
    LDA.w $9EE3
    STA.w $A0D8,X
.tech_partner_check:
    LDA.w $9EE7                     ; dual/triple-tech partner nibbles
    CMP #$FF
    BEQ .tech_type_fields
    AND #$0F                        ; primary partner slot
    STA $80
    JSR BattleMenu_ConsumePartnerSlot
    LDA.w $9EE7
    AND #$F0
    CMP #$F0
    BEQ .tech_type_fields
    JSR Battle_ShiftRight4          ; secondary partner slot (triple-tech)
    STA $80
    JSR BattleMenu_ConsumePartnerSlot
.tech_type_fields:
    LDA.w $9EE7
    STA $82                          ; tech id
    LDA.w $9EE3
    STA $84                          ; tech table row
    LDA #$20                        ; type flag: tech
    STA $80
    BRA .after_type
.item_path:
    LDX.w $9F36                     ; item slot
    DEC.w $1583,X                   ; decrement stock count
    LDA #$FF
    STA.w $9920
    LDA #$40                        ; type flag: item
    STA $80
    LDA.w $9F35                     ; item id
    STA $84
    LDA #$FF                        ; no tech id
    STA $82
    LDA.w $A0D5                     ; save-skill-cursor setting
    BNE .after_type
    STZ.w $95E5
    STZ.w $95E6
.after_type:
    LDA.w $A114                     ; cursor-row override flag
    BNE .cursor_done
    LDA.w $95D5
    TAX
    LDA.w $95DC,X                   ; current menu cursor row
    STA.w $9916,X                   ; remember for this PC
    LDA.w $A0D4                     ; cursor-position-save setting
    BNE .cursor_done
    STZ.w $95DC
    STZ.w $95DD
    STZ.w $95DE
    STZ.w $9916
    STZ.w $9917
    STZ.w $9918
.cursor_done:
    STZ.w $A114
    STZ.w $960E
    STZ.w $9614
    STZ.w $A09A
    LDA.w $99D8                     ; command queue count
    TAX
    LDA.w $95D5
    TAY
    STA.w $99D4,X                   ; enqueue this PC's slot
    TAX
    LDA.l $CCFAF0,X                 ; slot -> sprite index
    TAX
    LDA.w $93EE,X
    AND #$7F
    ORA #$40                        ; mark queued
    STA.w $93EE,X
    LDA $80                          ; type flag
    ORA.w $9F38,Y
    STA.w $93EF,X
    LDA.w $9615                     ; submenu type
    STA.w $93F0,X
    LDA.w $A62D                     ; confirmed target
    STA.w $93F1,X
    LDA $82                          ; tech id (or $FF)
    STA.w $93F3,X
    LDA $84                          ; item id / tech table row
    STA.w $93F4,X
    INC.w $99D8
    STZ.w $95DB                     ; back to main menu
    LDA #$FE
    STA.w $A6DF                     ; force command-window reload
    DEC.w $A6DE                     ; active PC count
    LDA.w $95D5
    TAX
    LDA #$FF
    STA.w $A6D9,X                   ; clear this PC's roster slot
    TDC
    TAX
.find_next_active:
    LDA.w $A6D9,X                   ; next roster slot's presence value
    STA.w $A6DD
    STA.w $95D5
    BPL .done                       ; found a valid slot -> promote it
    INX
    CPX #$0003
    BNE .find_next_active
    LDA #$FF                        ; none left -> no active PC
    STA.w $A6DD
    STA.w $95D5
.done:
    STZ.w $A862
    STZ.w $99E0
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_ConsumePartnerSlot ($C1174E–$C1176B, 30 bytes)
; ==================================================================
; Removes battler slot $80 from the ready/active state as part of
; committing a dual/triple-tech: if it's currently the active roster
; slot, decrements the active-PC count; either way marks the slot
; absent ($A6D9,X = $FF) and clears the "waiting for command" bit (bit
; 7, set by BattleMenu_EnqueueReadyBattler) of its sprite flag byte at
; $93EE (via the same $CCFAF0 slot->sprite lookup used in
; BattleMenu_CommitAction).
; Entry: M=1, X=0, DB=$7E; $80 = partner battler slot
; Exit:  M=1; registers clobbered
; No JSR/JSL calls.
org $C1174E
BattleMenu_ConsumePartnerSlot:
    LDA $80
    TAX
    LDA.w $A6D9,X
    BMI .clear_slot
    DEC.w $A6DE                     ; active PC count
.clear_slot:
    LDA #$FF
    STA.w $A6D9,X                   ; mark slot absent
    LDA.l $CCFAF0,X                 ; slot -> sprite index
    TAX
    LDA.w $93EE,X
    AND #$7F                        ; clear "waiting for command" bit
    STA.w $93EE,X
    RTS

; ==================================================================
; BattleMenu_TargetNext ($C1176C–$C11785, 26 bytes)
; ==================================================================
; Right/Down while cycling targets: advance $9614 (wrap at 11), skip
; candidate-list slots whose $99C0,X entry is invalid, store the
; landed battler id to $A62D.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: Battle_ZeroResultEE
org $C1176C
BattleMenu_TargetNext:
    INC.w $9614
    LDA.w $9614
    CMP #$0B
    BNE .have_index
    TDC
    STA.w $9614
.have_index:
    TAX
    LDA.w $99C0,X                   ; candidate list entry
    BMI BattleMenu_TargetNext       ; invalid -> keep advancing
    STA.w $A62D
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_TargetPrev ($C11786–$C1179B, 22 bytes)
; ==================================================================
; Left/Up while cycling targets: mirror of TargetNext — decrement
; $9614 (wrap to 10) instead of incrementing. Falls straight through
; into Battle_ZeroResultEE (no JMP needed; they're adjacent in ROM).
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; falls through to Battle_ZeroResultEE
; No JSR/JSL calls.
org $C11786
BattleMenu_TargetPrev:
    DEC.w $9614
    LDA.w $9614
    BPL .have_index
    LDA #$0A
    STA.w $9614
.have_index:
    TAX
    LDA.w $99C0,X                   ; candidate list entry
    BMI BattleMenu_TargetPrev       ; invalid -> keep decrementing
    STA.w $A62D

; ==================================================================
; BattleMenu_TechListInput ($C11320–$C11368, 73 bytes)
; ==================================================================
; Per-frame input handler while the tech list is open ($95DB==1).
; Computes the currently-highlighted tech's list index into $80
; (scroll $95EB + cursor $95DF), then polls pad-edge bytes: $EE bit
; $80 = confirm, $EE bit $08 = cancel, $EF bits $08/$02 = up (via
; Y-axis bit or Left), $EF bits $04/$01 = down (via Y-axis bit or
; Right).
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; tail-jumps to one of several handlers, does not fall through
; Callees: Battle_StopSfx, BattleMenu_TechConfirm,
;          BattleMenu_TechListCancel, BattleMenu_TechListPrev,
;          BattleMenu_TechListNext, Battle_ZeroResultEE
org $C11320
BattleMenu_TechListInput:
    LDA.w $95D5                     ; active PC slot
    TAX
    LDA.w $95EB,X                   ; scroll position
    CLC
    ADC.w $95DF,X                   ; + cursor row
    TAX
    STX $80                          ; highlighted tech list index
    LDA $EE
    AND #$80                        ; confirm
    BEQ .check_cancel
    JSR Battle_StopSfx
    JMP BattleMenu_TechConfirm
.check_cancel:
    LDA $EE
    AND #$08                        ; cancel
    BEQ .check_up
    JSR Battle_StopSfx
    JMP BattleMenu_TechListCancel
.check_up:
    LDA $EF
    BIT #$08                        ; up
    BNE .do_up
    AND #$02                        ; left
    BEQ .check_down
.do_up:
    JSR Battle_StopSfx
    JMP BattleMenu_TechListPrev
.check_down:
    LDA $EF
    BIT #$04                        ; down
    BNE .do_down
    AND #$01                        ; right
    BEQ .exit
.do_down:
    JSR Battle_StopSfx
    JMP BattleMenu_TechListNext
.exit:
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_TechConfirm ($C11369–$C1138E, 38 bytes)
; ==================================================================
; Confirms the highlighted tech: aborts if the tech-availability check
; ($A099) is clear or the tech's flag byte ($9EE5) marks it
; unavailable (bit 7). Otherwise sets target mode from $9EE4, builds
; the target list, and — if a valid target was found — enters
; target-select mode; if not, just resets the target cursor.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: BattleMenu_BuildTargetList, Battle_ZeroResultEE
org $C11369
BattleMenu_TechConfirm:
    LDA.w $A099                     ; tech-availability check
    BEQ .exit
    LDA.w $9EE5                     ; tech flag byte
    BMI .exit                       ; unavailable
    LDA.w $9EE4                     ; target mode for this tech
    STA.w $960D
    JSR BattleMenu_BuildTargetList
    LDA.w $9613                     ; target result
    BPL .have_target
    STZ.w $9614
    BRA .exit
.have_target:
    INC.w $A4EE
    INC.w $9609                     ; enter target-select mode
.exit:
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_TechListCancel ($C1138F–$C113AC, 30 bytes)
; ==================================================================
; Closes the tech list: back to main menu ($95DB=0), force a command-
; window reload sentinel, and restore this PC's saved cursor/scroll
; position ($A863/$A866 -> $95DF/$95EB).
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: BattleMenu_LoadCommandWindowMap, Battle_ZeroResultEE
org $C1138F
BattleMenu_TechListCancel:
    JSR BattleMenu_LoadCommandWindowMap
    STZ.w $95DB                     ; submenu type -> main
    LDA #$FF
    STA.w $A6DF                     ; force command-window reload
    LDA.w $95D5
    TAX
    LDA.w $A863,X                   ; saved cursor row
    STA.w $95DF,X
    LDA.w $A866,X                   ; saved scroll position
    STA.w $95EB,X
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_TechListPrev ($C113AD–$C113F3, 71 bytes)
; ==================================================================
; Up/Left in the tech list: walks backward from the current index
; ($80) looking for an entry whose availability byte ($1CDB,X) is
; nonzero, skipping unavailable techs. Once found, recomputes the
; cursor row / scroll position pair ($95DF/$95EB) by walking the same
; distance backward from the current (row, scroll) state, scrolling
; the list up a row at a time if the new row would go negative.
; Entry: M=1, X=0, DB=$7E; $80 = current list index
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: Battle_ZeroResultEE
org $C113AD
BattleMenu_TechListPrev:
    STZ $82                          ; steps walked
    LDA.w $95D5
    TAY
.retry:
    INC $82
    SEC
    LDA $80
    SBC #$01
    BCC .no_change                  ; ran off the start -> no-op
    STA $80
    TAX
    LDA.w $1CDB,X                   ; tech availability
    BEQ .retry                      ; unavailable -> keep walking back
    LDA.w $95DF,Y                   ; current cursor row
    STA $83
    TYX
.shift_loop:
    SEC
    LDA $83
    SBC #$01
    STA $83
    DEC $82
    BNE .shift_loop
    LDA $83
    BPL .no_wrap                    ; row still >= 0, no scroll needed
    LDA.w $95EB,X                   ; scroll position
    BEQ .no_change                  ; already at top -> no-op
    LDA $83
    STA.w $95DF,X
.dec_scroll:
    DEC.w $95EB,X
    CLC
    LDA.w $95DF,X
    ADC #$01
.no_wrap:
    STA.w $95DF,X
    BMI .dec_scroll                 ; still negative -> scroll again
.no_change:
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_TechListNext ($C113F4–$C1143C, 73 bytes)
; ==================================================================
; Down/Right in the tech list: mirror of TechListPrev — walks forward
; instead of backward, bounded by the list length ($A02A,Y) instead of
; the start of the list, and scrolls the row/scroll pair down instead
; of up when the new row would reach 3.
; Entry: M=1, X=0, DB=$7E; $80 = current list index
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: Battle_ZeroResultEE
org $C113F4
BattleMenu_TechListNext:
    STZ $82                          ; steps walked
    LDA.w $95D5
    TAY
.retry:
    INC $82
    CLC
    LDA $80
    ADC #$01
    CMP.w $A02A,Y                   ; list length for this PC
    BCS .exit                       ; ran off the end -> no-op
    STA $80
    TAX
    LDA.w $1CDB,X                   ; tech availability
    BEQ .retry                      ; unavailable -> keep walking forward
    LDA.w $95DF,Y                   ; current cursor row
    STA $83
    TYX
.shift_loop:
    CLC
    LDA $83
    ADC #$01
    STA $83
    DEC $82
    BNE .shift_loop
    LDA $83
    CMP #$03
    BCC .no_wrap                    ; row still < 3, no scroll needed
    LDA $83
    STA.w $95DF,X
.inc_scroll:
    INC.w $95EB,X                   ; scroll position
    SEC
    LDA.w $95DF,X
    SBC #$01
.no_wrap:
    STA.w $95DF,X
    CMP #$03
    BCS .inc_scroll                 ; still >= 3 -> scroll again
.exit:
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_ItemListInput ($C1143D–$C11497, 91 bytes)
; ==================================================================
; Per-frame input handler while the item list is open ($95DB==2).
; Unlike the tech list, item rows have no per-slot "available" flag to
; skip during cursor movement — up/down just move the cursor one row
; and scroll via ItemListScrollUp/Down at the edges. $EE bit $20/$10
; also let the player page the whole list up/down by 3 rows at once.
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; tail-jumps to one of several handlers, does not fall through
; Callees: Battle_StopSfx, BattleMenu_ItemConfirm,
;          BattleMenu_ItemListCancel, BattleMenu_ItemCursorUp,
;          BattleMenu_ItemCursorDown, BattleMenu_ItemListPageDown,
;          BattleMenu_ItemListPageUp, BattleMenu_ItemListRefresh,
;          Battle_ZeroResultEE
org $C1143D
BattleMenu_ItemListInput:
    LDA $EE
    AND #$80                        ; confirm
    BEQ .check_cancel
    JSR Battle_StopSfx
    JMP BattleMenu_ItemConfirm
.check_cancel:
    LDA $EE
    AND #$08                        ; cancel
    BEQ .check_up
    JSR Battle_StopSfx
    JMP BattleMenu_ItemListCancel
.check_up:
    LDA $EF
    BIT #$08                        ; up
    BNE .do_up
    AND #$02                        ; left
    BEQ .check_down
.do_up:
    JSR Battle_StopSfx
    JMP BattleMenu_ItemCursorUp
.check_down:
    LDA $EF
    BIT #$04                        ; down
    BNE .do_down
    AND #$01                        ; right
    BEQ .check_page_down
.do_down:
    JSR Battle_StopSfx
    JMP BattleMenu_ItemCursorDown
.check_page_down:
    LDA $EE
    AND #$20                        ; page down (3 rows)
    BEQ .check_page_up
    JSR Battle_StopSfx
    JMP BattleMenu_ItemListPageDown
.check_page_up:
    LDA $EE
    AND #$10                        ; page up (3 rows)
    BEQ .check_refresh
    JSR Battle_StopSfx
    JMP BattleMenu_ItemListPageUp
.check_refresh:
    LDA.w $A0D0                     ; refresh-pending flag
    BEQ .exit
    JMP BattleMenu_ItemListRefresh
.exit:
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_ItemConfirm ($C11498–$C114DA, 67 bytes)
; ==================================================================
; Confirms the highlighted item: index = (scroll $95E6 + cursor $95E5)
; * 5 into the item record table at $1580 (id, target mode, flags,
; quantity — one padding byte, 5-byte stride). Aborts if the flags
; byte is negative (unusable) or the quantity is zero. Otherwise sets
; $9F35 = item id, $960D = target mode, $9F36 = record index, builds
; the target list, and enters target-select mode if a valid target
; was found.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: Battle_Mul8, BattleMenu_BuildTargetList, Battle_ZeroResultEE
org $C11498
BattleMenu_ItemConfirm:
    CLC
    LDA.w $95E6                     ; item-list scroll position
    ADC.w $95E5                     ; + cursor row
    STA $80
    STA $AD
    LDA #$05                        ; record stride
    STA $AE
    JSR Battle_Mul8                 ; record index * 5
    LDX $AF
    LDA.w $1582,X                   ; item status flags
    BMI .exit                       ; unusable
    LDA.w $1583,X                   ; item quantity
    BEQ .exit                       ; none left
    LDA.w $1580,X                   ; item id
    STA.w $9F35
    LDA.w $1581,X                   ; target mode
    STA.w $960D
    STX.w $9F36                     ; record index
    JSR BattleMenu_BuildTargetList
    LDA.w $9613                     ; target result
    BPL .have_target
    STZ.w $9614
    BRA .exit
.have_target:
    INC.w $A4EE
    INC.w $9609                     ; enter target-select mode
.exit:
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_ItemListCancel ($C114DB–$C114EB, 17 bytes)
; ==================================================================
; Closes the item list: back to main menu ($95DB=0), force a command-
; window reload sentinel, and invalidate the scroll-arrow indicators.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: Battle_ZeroResultEE
org $C114DB
BattleMenu_ItemListCancel:
    JSR BattleMenu_LoadCommandWindowMap
    STZ.w $95DB                     ; submenu type -> main
    LDA #$FF
    STA.w $A6DF                     ; force command-window reload
    STA.w $9920                     ; invalidate scroll-arrow indicator
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_ItemCursorUp ($C114EC–$C11501, 22 bytes)
; ==================================================================
; Up/Left in the item list: decrement cursor row $95E5, scrolling the
; list up via ItemListScrollUp when already at the top row.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: BattleMenu_ItemListScrollUp, Battle_ZeroResultEE
org $C114EC
BattleMenu_ItemCursorUp:
    LDA.w $95E5                     ; cursor row
    BNE .move
    JSR BattleMenu_ItemListScrollUp
.move:
    SEC
    LDA.w $95E5
    SBC #$01
    BCC .exit
    STA.w $95E5
.exit:
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_ItemCursorDown ($C11502–$C1151B, 26 bytes)
; ==================================================================
; Down/Right in the item list: increment cursor row $95E5 (max 2),
; scrolling the list down via ItemListScrollDown when already at the
; bottom row.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: BattleMenu_ItemListScrollDown, Battle_ZeroResultEE
org $C11502
BattleMenu_ItemCursorDown:
    LDA.w $95E5                     ; cursor row
    CMP #$02
    BNE .move
    JSR BattleMenu_ItemListScrollDown
.move:
    CLC
    LDA.w $95E5
    ADC #$01
    CMP #$03
    BCS .exit
    STA.w $95E5
.exit:
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_ItemListPageDown ($C1151C–$C11536, 27 bytes)
; ==================================================================
; $EE bit $20: page the item list down 3 rows at once, clamped at
; scroll position $FA. Sets the scroll position and index itself, then
; JSRs directly into ItemListScrollDown's shared render+indicator tail
; (BattleMenu_ItemListScrollDown_RenderTail) rather than duplicating
; that logic — the same "call into another routine's tail" pattern
; already seen elsewhere in this bank (e.g. Sub_1BA7 in bank $C0).
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: BattleMenu_ItemListScrollDown_RenderTail, Battle_ZeroResultEE
org $C1151C
BattleMenu_ItemListPageDown:
    CLC
    LDA.w $95E6                     ; scroll position
    ADC #$03
    CMP #$FA
    BCS .clamp
    CMP #$00
    BNE .have_scroll
.clamp:
    LDA #$FA
.have_scroll:
    STA.w $95E6
    STA $80
    JSR BattleMenu_ItemListScrollDown_RenderTail
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_ItemListPageUp ($C11537–$C1154A, 20 bytes)
; ==================================================================
; $EE bit $10: page the item list up 3 rows at once, clamped at 0.
; Mirror of ItemListPageDown, JSRs into ItemListScrollUp's shared
; render+indicator tail (BattleMenu_ItemListScrollUp_RenderTail).
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: BattleMenu_ItemListScrollUp_RenderTail, Battle_ZeroResultEE
org $C11537
BattleMenu_ItemListPageUp:
    SEC
    LDA.w $95E6                     ; scroll position
    SBC #$03
    BCS .have_scroll
    TDC
.have_scroll:
    STA.w $95E6
    STA $80
    JSR BattleMenu_ItemListScrollUp_RenderTail
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_ItemListRefresh ($C1154B–$C11560, 22 bytes)
; ==================================================================
; Re-renders the item list rows and invalidates the scroll-arrow
; indicators when $A0D0 (refresh-pending flag) is set, clearing it.
; Entry: M=1, X=0, DB=$7E
; Exit:  M=1; tail-jumps to Battle_ZeroResultEE
; Callees: BattleMenu_RenderItemListRows, Battle_ZeroResultEE
org $C1154B
BattleMenu_ItemListRefresh:
    LDA.w $95E6                     ; scroll position
    STA $80
    JSR BattleMenu_RenderItemListRows
    LDA #$FF
    STA.w $991F                     ; scroll-arrow indicator
    STA.w $9920                     ; scroll-arrow indicator
    STZ.w $A0D0                     ; clear refresh-pending flag
    JMP Battle_ZeroResultEE

; ==================================================================
; BattleMenu_ItemListScrollUp ($C117A1–$C117BE, 30 bytes)
; ==================================================================
; Scrolls the item list up one row: decrements $95E6 (min 0), then
; re-renders and invalidates the scroll-arrow indicators.
;
; Contains a redundant double branch: after testing $95E6==0 once,
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
; which sets $95E6/$80 itself and skips straight to the render), and per
; this project's asar-quirk-6 workaround, a JSR target reached from another
; routine's scope must not be a local .dot label.
org $C117A1
BattleMenu_ItemListScrollUp:
    LDA.w $95E6                     ; scroll position
    BEQ BattleMenu_ItemListScrollUp_SetScroll
    BEQ BattleMenu_ItemListScrollUp_SkipRender ; unreachable: flag already tested clear above
    SEC
    LDA.w $95E6
    SBC #$01
    STA.w $95E6
BattleMenu_ItemListScrollUp_SetScroll:
    STA $80
BattleMenu_ItemListScrollUp_RenderTail:
    JSR BattleMenu_RenderItemListRows
BattleMenu_ItemListScrollUp_SkipRender:
    LDA #$FF
    STA.w $991F                     ; scroll-arrow indicator
    STA.w $9920                     ; scroll-arrow indicator
    RTS

; ==================================================================
; BattleMenu_ItemListScrollDown ($C117BF–$C117DC, 30 bytes)
; ==================================================================
; Scrolls the item list down one row: increments $95E6 (clamped at
; $FA), then re-renders and invalidates the scroll-arrow indicators.
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
    LDA.w $95E6                     ; scroll position
    CMP #$FA
    BCS BattleMenu_ItemListScrollDown_SkipRender ; already at max -> skip increment and render
    CLC
    LDA.w $95E6
    ADC #$01
    STA.w $95E6
    STA $80
BattleMenu_ItemListScrollDown_RenderTail:
    JSR BattleMenu_RenderItemListRows
BattleMenu_ItemListScrollDown_SkipRender:
    LDA #$FF
    STA.w $991F                     ; scroll-arrow indicator
    STA.w $9920                     ; scroll-arrow indicator
    RTS

; ==================================================================
; BattleMenu_UpdateCursorOverlay ($C117DD–$C11B18, 828 bytes)
; ==================================================================
; Per-frame cursor/overlay refresh, called once per frame from the end
; of the menu rebuild chain (after ProcessInput). Draws whatever cursor
; graphic belongs on screen right now, dispatching on menu state:
;
;   no active PC ($95D5 < 0)     -> hide the 4-sprite main cursor
;   target-select mode ($9609)   -> draw target-highlight cursor(s)
;   else, by submenu ($95DB):
;     0 (main)  -> nothing to do here (DrawCursorSprites already ran
;                  from ProcessInput); just fall through to the tail
;     1 (tech)  -> tech-list cursor: normal single highlight, or a
;                  2-3 sprite cluster over the caster + dual/triple-
;                  tech partner(s) when the highlighted tech needs them
;     2 (item)  -> item-list cursor: recomputes the up/down scroll-
;                  arrow glow and the row-highlight tile quad, queuing
;                  a VRAM upload ($CFFD6A) only if either changed
;
; Also, still within target-select mode, handles the "confirm-target"
; single-cursor placement (including a special enemy-vs-ally info-
; panel dispatch via JSL $CD002D/$CD0030) and a separate multi-target
; ("target all") sweep that walks the 11-entry selection list
; ($A62D-$A637) a few slots at a time, resuming next frame from a
; saved index ($960B) — the same incremental-scan pattern used by
; BattleMenu_BuildTargetList's own list handling.
;
; Common idiom used throughout (X = a battler/target slot id, not
; just a PC index 0-2 — this table is indexed by any of the 11
; selectable battler slots): compute a live screen position as
;   base origin ($1D0C,X / $1D23,X, same tables DrawCursorSprites
;   uses) + per-slot live offset ($9708,X / $9713,X, not yet named
;   elsewhere — likely each battler's current animated screen
;   position) - $10 (sprite-origin centering constant), written into
;   one of the four cursor OAM slots at $0700-$070F.
;
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; pad-edge bytes $EE/$EF cleared (shared tail, same as
;        Battle_ZeroResultEE elsewhere)
; Callees: Battle_ShiftRight4, BattleMenu_ClearTechCursorTiles,
;          BattleMenu_DrawCursorSprites, JSL $CD002D
;          (BattleMsg_ShowMsg0BIfKeyChangedVec), JSL $CD0030 (cross-
;          bank, sibling message vector — not yet analyzed), JSL
;          $CFFD6A (Battle_QueueVramUpload_0E80)
org $C117DD
BattleMenu_UpdateCursorOverlay:
    LDA.w $95D5                     ; active PC slot (signed; <0 = none)
    BPL .check_target_select
    JMP .no_active_pc
.check_target_select:
    LDA.w $9609                     ; target-select mode depth
    BEQ .dispatch_submenu
    JMP .target_select
.dispatch_submenu:
    LDA.w $95DB                     ; submenu type: 0=main, 1=tech, 2=item
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
; $9EE3 (tech id copied from the cursor's tech record by
; UpdateTechWindow) below $39 means a single-character tech — those
; never need partner highlighting, so go straight to the normal
; single cursor. $39 and up are dual/triple techs; $9EE7's low nibble
; names the primary partner slot (sentinel $FF = "no partner data
; resolved yet", also falls back to the normal single cursor).
.tech_path:
    LDA.w $9EE3                     ; tech id at cursor
    CMP #$39
    BCS .tech_check_group
.tech_single_jmp:
    JMP .tech_single_cursor
.tech_check_group:
    LDA.w $9EE7                     ; dual/triple-tech partner nibbles
    CMP #$FF
    BEQ .tech_single_jmp
    LDA.w $0900                     ; hide all 4 main-cursor OAM slots first
    ORA #$55
    STA.w $0900
    LDA #$F0
    STA.w $0701
    STA.w $0705
    STA.w $0709
    STA.w $070D
    LDA #$32
    STA.w $0703
    STA.w $0707
    STA.w $070B
    STZ.w $0702
    STZ.w $0706
    STZ.w $070A
    ; OAM slot 0: caster (active PC slot)
    LDA.w $95D5
    TAX
    CLC
    LDA.w $1D0C,X
    ADC.w $9708,X
    SEC
    SBC #$10
    STA.w $0700
    CLC
    LDA.w $1D23,X
    ADC.w $9713,X
    STA.w $0701
    ; OAM slot 1: primary partner (low nibble of $9EE7)
    LDA.w $9EE7
    AND #$0F
    TAX
    CLC
    LDA.w $1D0C,X
    ADC.w $9708,X
    SEC
    SBC #$10
    STA.w $0704
    CLC
    LDA.w $1D23,X
    ADC.w $9713,X
    STA.w $0705
    LDA.w $0900                     ; reveal caster + primary-partner sprites
    AND #$FE
    AND #$FB
    STA.w $0900
    ; OAM slot 2: second partner, only for a triple-tech (high nibble
    ; of $9EE7 present; $F = "no third partner")
    LDA.w $9EE7
    AND #$F0
    CMP #$F0
    BEQ .tech_group_done
    JSR Battle_ShiftRight4          ; high nibble -> low nibble
    TAX
    CLC
    LDA.w $1D0C,X
    ADC.w $9708,X
    SEC
    SBC #$10
    STA.w $0708
    CLC
    LDA.w $1D23,X
    ADC.w $9713,X
    STA.w $0709
    LDA.w $0900                     ; reveal second-partner sprite
    AND #$EF
    STA.w $0900
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
; one; $80 tallies whether either actually changed this frame.
.item_path:
    STZ $80
    ; Scroll-arrow glow: recompute the up/down arrow tile+attr pairs
    ; ($0EFC/$0EFD = up arrow, $0FFC/$0FFD = down arrow) whenever the
    ; scroll position ($95E6) differs from the cached value ($9920).
    ; Tile $FF hides an arrow entirely (nothing further that way);
    ; attr $A9 (vs the normal $29) is used only on the down arrow, and
    ; only while it's still visible — drawing attention toward more
    ; items below except at the very bottom of the list.
    LDA.w $95E6                     ; scroll position
    CMP.w $9920                     ; cached scroll-arrow state
    BNE .arrow_check_zero
    JMP .row_check
.arrow_check_zero:
    LDA.w $95E6
    BNE .arrow_check_max
    LDA #$FF                        ; top of list -> hide up arrow
    STA.w $0EFC
    LDA #$7F                        ; down arrow visible + flashing
    STA.w $0FFC
    LDA #$A9
    STA.w $0EFD
    STA.w $0FFD
    BRA .arrow_done
.arrow_check_max:
    LDA.w $95E6
    CMP #$FA
    BEQ .arrow_at_max
    LDA #$7F                        ; middle of list -> both arrows visible
    STA.w $0EFC
    STA.w $0FFC
    LDA #$29                        ; up arrow normal
    STA.w $0EFD
    LDA #$A9                        ; down arrow flashing
    STA.w $0FFD
    BRA .arrow_done
.arrow_at_max:
    LDA #$7F                        ; up arrow visible, normal
    STA.w $0EFC
    LDA #$FF                        ; bottom of list -> hide down arrow
    STA.w $0FFC
    LDA #$29
    STA.w $0EFD
    STA.w $0FFD
.arrow_done:
    INC $80
    ; Row-highlight quad: if either the cursor row ($95E5) or the
    ; scroll-arrow state changed, blank the old row's 4-tile marker
    ; (looked up via $CCFAE9) and draw the new one (tiles $60-$63,
    ; attr $29) — the same tile ids/scheme BattleMenu_DrawTechCursorRow
    ; uses for its own cursor row.
.row_check:
    LDA.w $95E5                     ; cursor row
    CMP.w $991F                     ; cached row-highlight state
    BNE .row_redraw
    LDA.w $95E6
    CMP.w $9920
    BEQ .item_upload_check
    STA.w $9920
.row_redraw:
    LDA.w $991F
    BPL .have_old_row
    TDC
.have_old_row:
    ASL
    TAX
    REP #$20                        ; A=16-bit: fetch tile-quad pointer
    LDA.l $CCFAE9,X
    TAX
    TDC
    SEP #$20                        ; A=8-bit
    LDA #$FF
    STA.w $0E80,X
    STA.w $0E82,X
    STA.w $0EC0,X
    STA.w $0EC2,X
    LDA.w $95E5
    STA.w $991F                     ; cache new row
    ASL
    TAX
    REP #$20
    LDA.l $CCFAE9,X
    TAX
    TDC
    SEP #$20
    LDA #$60
    STA.w $0E80,X
    LDA #$61
    STA.w $0E82,X
    LDA #$62
    STA.w $0EC0,X
    LDA #$63
    STA.w $0EC2,X
    LDA #$29
    STA.w $0E81,X
    STA.w $0E83,X
    STA.w $0EC1,X
    STA.w $0EC3,X
    INC $80
.item_upload_check:
    LDA $80
    BEQ .item_no_upload
    JSL $CFFD6A                     ; Battle_QueueVramUpload_0E80 (cross-bank)
.item_no_upload:
    JMP .tail

; ------------------------------------------------------------------
; Target-select cursor ($1979-$1AFD)
; ------------------------------------------------------------------
.target_select:
    LDA.w $9613                     ; target-found flag (0=found, <0=none)
    BPL .target_have
    JMP .to_tail
.target_have:
    LDA.w $95DB                     ; submenu type
    DEC
    BNE .target_hide_tech_cursor_done
    JSR BattleMenu_ClearTechCursorTiles ; leaving tech list -> clear its cursor tiles
.target_hide_tech_cursor_done:
    LDA.w $0900                     ; hide all 4 main-cursor OAM slots first
    ORA #$55
    STA.w $0900
    LDA #$32
    STA.w $0703
    STA.w $0707
    STA.w $070B
    STA.w $070F
    STZ.w $0702
    STZ.w $0706
    STZ.w $070A
    STZ.w $070E
    LDA.w $A62E                     ; second selection-list slot (multi-target?)
    BMI .target_check_primary
    JMP .multi_target
.target_check_primary:
    LDA.w $A62D                     ; primary selection-list slot
    BPL .target_single
    JMP .to_tail
.target_single:
    STA.w $A64E                     ; confirmed/highlighted target id
    TAX
    CLC
    LDA.w $1D0C,X
    ADC.w $9708,X
    SEC
    SBC #$10
    STA.w $0700
    CLC
    LDA.w $1D23,X
    ADC.w $9713,X
    STA.w $0701
    LDA.w $95DB
    BNE .after_marker
    LDA.w $A64E
    CMP #$03                        ; target id < 3 -> a PC ally slot
    BCC .after_marker
    ; enemy target while in the main attack menu: look up the
    ; enemy's info-panel dispatch id and route through one of two
    ; cross-bank message calls depending on a per-enemy flag table
    ASL
    TAX
    LDA.w $984D,X                   ; info-panel dispatch id for this target
    STA.w $0200
    LDA.l $CCF8ED,X                 ; battler work-area pointer, low
    STA $80
    LDA.l $CCF8EE,X                 ; battler work-area pointer, high
    STA $81
    LDA.w $9F34
    BEQ .enemy_marker_check2
    LDA.w $A64E
    TAY
    LDA.w $9F29,Y
    BNE .ally_target
.enemy_marker_check2:
    LDA.w $0200
    TAX
    LDA.l $E1DE80,X
    BEQ .enemy_marker_fallback1
    LDA #$FF
    BRA .enemy_marker_send1
.enemy_marker_fallback1:
    LDA.w $A64E
.enemy_marker_send1:
    JSL $CD0030                     ; cross-bank message call (sibling of $CD002D)
    BRA .after_marker
.ally_target:
    LDX $80
    LDA.w $5E30,X                   ; ally battler data -> scratch record
    STA.w $0201
    LDA.w $5E31,X
    STA.w $0202
    LDA.w $5E32,X
    STA.w $0203
    LDA.w $5E33,X
    STA.w $0204
    LDA.w $0200
    TAX
    LDA.l $E1DE80,X
    BEQ .ally_marker_fallback
    LDA #$FF
    BRA .ally_marker_send
.ally_marker_fallback:
    LDA.w $A64E
.ally_marker_send:
    JSL $CD002D                     ; BattleMsg_ShowMsg0BIfKeyChangedVec (cross-bank)
.after_marker:
    LDA.w $0900                     ; reveal OAM slot 0 (single-target cursor)
    AND #$FE
    STA.w $0900
    ; blink-direction latch: nudged whenever the target was just
    ; cycled/confirmed ($A4EE), based on which half of the screen the
    ; cursor currently sits in ($0701 vs $2D/$9C)
    LDA.w $A4EE
    BEQ .blink_done
    STZ.w $A4EE
    LDA.w $960A
    BEQ .blink_done
    LDA $EC
    BNE .blink_check_high
    LDA.w $0701
    CMP #$2D
    BCS .blink_done
    INC $EC
    BRA .blink_done
.blink_check_high:
    LDA.w $0701
    CMP #$9C
    BCC .blink_done
    STZ $EC
.blink_done:
    JMP .to_tail

; ------------------------------------------------------------------
; Multi-target ("target all") cursor sweep ($1A7B-$1AFA)
; ------------------------------------------------------------------
; Walks the 11-entry selection list ($A62D-$A637), drawing one cursor
; OAM slot per confirmed target (up to the 4 available: $0700-$070F),
; resuming next frame from a saved scan index ($960B) rather than
; redoing the whole list every frame.
.multi_target:
    LDA.w $A62D
    BMI .multi_loop_init
    TAX
    CLC
    LDA.w $1D0C,X
    ADC.w $9708,X
    SEC
    SBC #$10
    STA.w $0700
    CLC
    LDA.w $1D23,X
    ADC.w $9713,X
    STA.w $0701
    LDA.w $0900
    AND.l $CCFB8D                   ; reveal OAM slot 0 (visibility-bit-clear table)
    STA.w $0900
.multi_loop_init:
    LDY #$0001
    STY $82                         ; next OAM slot index (slot 0 handled above)
    LDA.w $960B                     ; resume index from last frame
    TAY
    STY $80
.multi_loop:
    LDY $80
    LDA.w $A62D,Y                   ; selection-list slot
    BMI .multi_loop_next
    TAX
    LDA $82
    ASL
    ASL
    TAY                              ; Y = OAM slot index * 4 (OAM entry stride)
    CLC
    LDA.w $1D0C,X
    ADC.w $9708,X
    SEC
    SBC #$10
    STA.w $0700,Y
    CLC
    LDA.w $1D23,X
    ADC.w $9713,X
    STA.w $0701,Y
    LDX $82
    LDA.w $0900
    AND.l $CCFB8D,X                 ; reveal this OAM slot
    STA.w $0900
.multi_loop_next:
    INC $80
    LDA $80
    CMP #$03
    BEQ .multi_loop_cap
    CMP #$06
    BEQ .multi_loop_cap
    INC $82
    LDA $82
    CMP #$04
    BNE .multi_loop
.multi_loop_cap:
    LDA $80
    CMP #$06
    BNE .multi_loop_save
    TDC
.multi_loop_save:
    STA.w $960B                     ; save scan index for next frame
.to_tail:
    JMP .tail

.no_active_pc:
    LDA.w $0900                     ; hide all 4 main-cursor OAM slots
    ORA #$55
    STA.w $0900
    LDA #$F0
    STA.w $0701
    STA.w $0705
    STA.w $0709
    STA.w $070D
.tail:
    STZ $EE                         ; clear pad-edge bytes (same tail idiom
    STZ $EF                         ; as Battle_ZeroResultEE)
    RTS
