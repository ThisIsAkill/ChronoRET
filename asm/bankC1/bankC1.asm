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
; Label stubs — no bytes emitted; used for JSR/JSL targets
; ============================================================

org $C11320
BattleMenu_TechListInput:       ; tech-list submenu input handler; not yet matched

org $C1143D
BattleMenu_ItemListInput:       ; item-list submenu input handler; not yet matched

org $C1161A
BattleMenu_CommitAction:        ; builds command record + enqueues confirmed action; not yet matched

org $C1176C
BattleMenu_TargetNext:          ; cycle target selection forward; not yet matched

org $C11786
BattleMenu_TargetPrev:          ; cycle target selection backward; not yet matched

org $C117DD
BattleMenu_UpdateCursorOverlay: ; per-frame cursor sprite/overlay refresh; not yet matched

; ============================================================
; Math Utility Cluster ($C1:0089–$C1:011E)
; ============================================================

; $C1:0089 — Battle_Mul8 (30 bytes, $0089–$00A6)
; 8×8→16 HW multiply via $4202/$4203/$4216.
; In:  $AD = multiplicand, $AE = multiplier
; Out: $AF = 16-bit product; mirrors operands to $77/$78
; M=1 on entry; uses STA.l for HW regs (DB unknown, must be fully qualified)
org $C10089
Battle_Mul8:
    LDA $AD
    STA $77
    STA.l WRMPYA            ; $004202 — load multiplicand (long: DB may be any)
    LDA $AE
    STA $78
    STA.l WRMPYB            ; $004203 — load multiplier (triggers multiply)
    REP #$20                ; A → 16-bit
    NOP
    NOP
    LDA.l RDMPYL            ; $004216 — read 16-bit product
    STA $AF
    TDC
    SEP #$20                ; A → 8-bit
    RTS

; $C1:00A7 — Battle_MulAccum (48 bytes, $00A7–$00D6)
; Multiply-accumulate: $A5 × $A7 via HW mult, 32-bit accumulate into $A9/$AA.
; Also multiplies $A8 × $A7 and accumulates into $AA (upper 16 bits).
; In:  $A5 = multiplicand, $A7 = multiplier, $A8 = accumulator byte, $AA = upper word
; Out: $A9/$AA = updated 32-bit accumulator
; Sets DB=0 itself (PHB/TDC/PHA/PLB) to safely use STA.w for HW regs.
org $C100A7
Battle_MulAccum:
    PHB
    TDC
    PHA
    PLB                     ; DB = 0 (hardware regs accessible via absolute)
    LDA $A5
    STA $77
    STA.w WRMPYA            ; $4202 — first operand (DB=0 → $004202)
    LDA $A7
    STA $78
    STA.w WRMPYB            ; $4203 — triggers first multiply ($A5 × $A7)
    PHP
    LDA $A8
    STZ $AB
    LDX.w RDMPYL            ; $4216 — read 16-bit product of $A5 × $A7
    STA $78
    STA.w WRMPYB            ; $4203 — triggers second multiply ($A8 × $A7)
    STX $A9                 ; save first product low word
    REP #$21                ; A → 16-bit, C=0 (clear carry for ADC)
    LDA $AA
    ADC.w RDMPYL            ; $4216 — add second product to running accumulator
    STA $AA
    TDC
    PLP
    SEP #$20                ; A → 8-bit
    PLB
    RTS

; $C1:00D7 — Battle_Divide (54 bytes, $00D7–$010C)
; 16÷8 HW divide via $4204/$4205/$4206/$4214.
; In:  $B1/$B2 = 16-bit dividend (lo/hi), $B3 = 8-bit divisor
; Out: $B5 = 16-bit quotient, $B7 = 16-bit remainder; mirrors to $79/$7A/$7B
; Guards with INC/STZ $A029 (re-entrancy flag in WRAM).
org $C100D7
Battle_Divide:
    INC.w $A029             ; increment re-entrancy guard
    LDA $B1
    STA $79
    STA.l WRDIVL            ; $004204 — dividend low byte
    LDA $B2
    STA $7A
    STA.l WRDIVH            ; $004205 — dividend high byte
    LDA $B3
    STA $7B
    STA.l WRDIVB            ; $004206 — divisor (triggers divide)
    REP #$20                ; A → 16-bit
    NOP                     ; 6 NOPs: hardware latency for divide result
    NOP
    NOP
    NOP
    NOP
    NOP
    LDA.l RDDIVL            ; $004214 — read 16-bit quotient
    STA $B5
    LDA.l RDMPYL            ; $004216 — read 16-bit remainder
    STA $B7
    TDC
    SEP #$20                ; A → 8-bit
    STZ.w $A029             ; clear re-entrancy guard
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
; Format the 16-bit value at $9499 into four font digit tiles:
;   $949C = $FF (blank, thousands), $949D = hundreds,
;   $949E = tens, $949F = ones.
;   Digit tile glyphs looked up via table at $CCF903.
; Entry: M=0 (16-bit A), X=0 (16-bit), DB=$7E (WRAM accessible)
; Exit:  M=1 (8-bit A), X=0 (16-bit)
; Note: M=0 is established by the caller; no REP #$20 emitted here.
;   SBC/ADC with 16-bit immediates forced via db to get 3-byte encoding.
; No JSR/JSL calls.
org $C1011F
BattleMsg_FormatNumberDigits:
    PHX
    TDC
    TAX
.hundreds_loop:
    SEC
    LDA.w $9499
    db $E9,$64,$00              ; SBC #$0064 — subtract 100 (3-byte M=0 form)
    STA.w $9499
    INX
    BCS .hundreds_loop
    CLC
    LDA.w $9499
    db $69,$64,$00              ; ADC #$0064 — restore overshoot
    STA.w $9499
    DEX
    PHX                         ; push hundreds digit count
    TDC
    TAX
.tens_loop:
    SEC
    LDA.w $9499
    db $E9,$0A,$00              ; SBC #$000A — subtract 10
    STA.w $9499
    INX
    BCS .tens_loop
    CLC
    LDA.w $9499
    db $69,$0A,$00              ; ADC #$000A — restore overshoot; A = ones digit (not stored back)
    DEX
    PHX                         ; push tens digit count
    SEP #$20                    ; A → 8-bit
    TAX                         ; X = ones digit
    LDA.l $CCF903,X             ; ones → digit tile glyph
    STA.w $949F
    PLX                         ; X = tens count
    LDA.l $CCF903,X
    STA.w $949E
    PLX                         ; X = hundreds count
    LDA.l $CCF903,X
    STA.w $949D
    LDA #$FF                    ; thousands digit = blank ($FF)
    STA.w $949C
    PLX
    RTS

; $C1:0174 — Battle_DivTen9499 (53 bytes, $0174–$01A8)
; Two-digit variant of BattleMsg_FormatNumberDigits: formats $9499
; as tens+ones only. $949C/$949D = $FF (blank); $949E = tens, $949F = ones.
; Used for two-digit battle values (0–99).
; Entry: M=0 (16-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1 (8-bit A), X=0 (16-bit)
; Note: same SBC/ADC db trick as BattleMsg_FormatNumberDigits.
; No JSR/JSL calls.
org $C10174
Battle_DivTen9499:
    PHX
    TDC
    TAX
.tens_loop:
    SEC
    LDA.w $9499
    db $E9,$0A,$00              ; SBC #$000A — subtract 10
    STA.w $9499
    INX
    BCS .tens_loop
    CLC
    LDA.w $9499
    db $69,$0A,$00              ; ADC #$000A — restore overshoot; A = ones digit
    DEX
    PHX                         ; push tens digit count
    SEP #$20                    ; A → 8-bit
    TAX                         ; X = ones digit
    LDA.l $CCF903,X             ; ones → digit tile glyph
    STA.w $949F
    PLX                         ; X = tens count
    LDA.l $CCF903,X
    STA.w $949E
    LDA #$FF                    ; hundreds = blank
    STA.w $949D
    STA.w $949C                 ; thousands = blank
    PLX
    RTS

; $C1:01A9 — BattleMsg_ReencodeTextBuffer (80 bytes, $01A9–$01F8)
; Copy 16-char source buf $94C0–$94CF (backup), blank $94A0/$94B0,
; then re-encode each char byte into tile ($94A0,X) + plane marker ($94B0,X):
;   $40–$68 → tile += $40, plane = $71
;   $69–$72 → tile += $17, plane = $72
;   $73+    → tile = char unchanged, plane = $FF (passthrough)
;   $00     → stop early (blank fill already done by MVN)
; Entry: M=1 (8-bit A), X=0 (16-bit); entry state from caller
; Exit:  M=1 (8-bit A)
; No JSR/JSL calls.
org $C101A9
BattleMsg_ReencodeTextBuffer:
    REP #$20                    ; A → 16-bit
    LDX.w #$94A0                ; src index for MVN
    LDY.w #$94C0                ; dst index for MVN
    LDA.w #$000F                ; count − 1 = 15 (copy 16 bytes)
    MVN $7E,$7E                 ; copy $7E:$94A0..$94AF → $7E:$94C0..$94CF (backup)
    LDX.w #$001E                ; loop index = 30 (step −2, 16 word-slots)
.blank_loop:
    STA.w $94A0,X               ; write $FFFF (MVN leaves A=$FFFF) to blank each word slot
    DEX
    DEX
    BPL .blank_loop
    TDC                         ; A = 0
    TAX                         ; X = 0
    SEP #$20                    ; A → 8-bit
.char_loop:
    LDA.w $94C0,X               ; read source char from backup
    BEQ .done                   ; $00 = end of string
    CMP #$73
    BCS .passthrough            ; $73+ → passthrough (tile unchanged, plane = $FF)
    CMP #$69
    BCS .range69                ; $69–$72 → add $17, plane = $72
    CMP #$40
    BCC .passthrough            ; < $40 → passthrough
    ; $40–$68: add $40 to get tile index, plane = $71
    CLC
    ADC #$40
    STA.w $94A0,X
    LDA #$71
    BRA .store_plane
.range69:
    ; $69–$72: add $17 to get tile index, plane = $72
    CLC
    ADC #$17
    STA.w $94A0,X
    LDA #$72
    BRA .store_plane
.passthrough:
    STA.w $94A0,X               ; store tile unchanged
    LDA #$FF                    ; plane = $FF (passthrough marker)
.store_plane:
    STA.w $94B0,X               ; write plane marker
    INX
    CPX.w #$0010                ; processed all 16 chars?
    BNE .char_loop
.done:
    RTS

; ============================================================
; Status-Bar UI Callees ($C1:06F0–$C1:095C)
; Matched session 37; called by BattleUI_BuildStatusBarFrame and peers.
; ============================================================

; $C1:06F0 — BattleUI_DrawSlotGaugeBar (149 bytes, $06F0–$0784)
; Render the ATB gauge bar for PC slot $80 into the status-bar tilemap.
; Computes fill ratio = (ATB_cur * 256) / ATB_max via Battle_Divide, then
; plots full-fill tiles ($6F), a partial tile ($67+offset), and background
; tiles ($67) across a 32-unit-wide gauge strip.  Attr byte is $2D if ATB
; is non-zero, $29 if zero.  Destination is tilemap word-pair at $CCFA35[slot]+$1A.
; Entry: M=1, X=0 (16-bit), $80 = PC slot index (0–2)
; Exit:  M=1; Y = last written tilemap position; $82/$83/$86/$AD/$AE/$B1–$B7 clobbered
; Calls: Battle_ShiftLeft7 ($010D), Battle_Divide ($00D7), Battle_ShiftRight3 ($011B)
org $C106F0
BattleUI_DrawSlotGaugeBar:
    REP #$21                    ; M=0, C=0
    LDA $80                     ; PC slot index (16-bit DP load; high byte = 0)
    ASL                         ; × 2 (table index)
    TAX
    LDA.l $CCFA35,X             ; tilemap base word-pair offset for this slot
    db $69,$1A,$00              ; ADC #$001A — gauge row offset within strip (M=0 3-byte)
    TAY                         ; Y = tilemap destination
    TDC
    SEP #$20                    ; M=1
    LDX $80                     ; X = slot index (16-bit DP load)
    LDA.w $99DD,X               ; ATB current value for this slot
    STA $AD
    STZ $AE
    LDA.w $9F22,X               ; ATB max value for this slot
    STA $B3
    STZ $B4
    REP #$20                    ; M=0
    LDA $AD                     ; current ATB (16-bit; $AE=0)
    JSR Battle_ShiftLeft7       ; A <<= 8 (× 256) — scale to fixed-point
    STA $B1                     ; 16-bit store: $B1=lo, $B2=hi (dividend for Divide)
    TDC
    SEP #$20                    ; M=1
    JSR Battle_Divide           ; quotient = (ATB*256)/ATBmax → $B5 (0–255 fill ratio)
    REP #$20                    ; M=0
    LDA $B5                     ; quotient (16-bit; hi byte=$B6=remainder hi)
    JSR Battle_ShiftRight3      ; >> 3 → scale 0–255 to 0–31 tile units
    STA $B5
    TDC
    SEP #$20                    ; M=1
    SEC
    LDA #$20                    ; 32 = full gauge width
    SBC $B5                     ; unfilled tile count
    STA $82
    LSR
    LSR
    LSR                         ; / 8 = number of complete 8-unit blocks
    STA $83
    ASL
    ASL
    ASL                         ; × 8 = tiles covered by full blocks
    STA $86
    SEC
    LDA $82
    SBC $86                     ; fractional remainder after full blocks
    STA $82
    ; Write 4 background tiles at destination
    LDA #$67                    ; background gauge tile
    STA.w $0CC0,Y
    STA.w $0CC2,Y
    STA.w $0CC4,Y
    STA.w $0CC6,Y
    LDX $80                     ; slot index
    LDA.w $99DD,X               ; ATB current
    BNE .has_atb
    LDA #$29                    ; zero ATB → dim palette attr
    BRA .set_attr
.has_atb:
    LDA #$2D                    ; non-zero ATB → bright palette attr
.set_attr:
    STA.w $0CC1,Y
    STA.w $0CC3,Y
    STA.w $0CC5,Y
    STA.w $0CC7,Y
.full_tile_loop:
    LDA $83                     ; full-block counter
    BEQ .partial_tile
    LDA #$6F                    ; full-fill gauge tile
    STA.w $0CC0,Y
    INY
    INY
    DEC $83
    BRA .full_tile_loop
.partial_tile:
    CLC
    LDA $82                     ; fractional remainder
    BEQ .done                   ; exactly on tile boundary → nothing to add
    ADC #$67                    ; partial tile = base tile + fill offset
    STA.w $0CC0,Y
.done:
    RTS

; $C1:0785 — BattleSys_SlotPanelRefresh (153 bytes, $0785–$081D)
; Write a 6-row × 7-col panel tile strip for PC slot A into the status-bar
; tilemap at base offset slot×12.  Two tile tables are used:
;   $CCFA41 — "empty" panel (slot inactive or same as active PC)
;   $CCFA6B — "ready" indicator panel (slot is ready / different from active PC)
; Selection depends on $95F1, $9F25/$9F28 per-slot flags, $A117, $A6DE, and $A6D9.
; Each row is 7 tiles wide; each tile written as (tile,attr=$29) word-pair.
; Entry: M=1, X=0 (16-bit), A = PC slot index (0–2)
; Exit:  M=1; $80/$81/$82 clobbered; X/Y clobbered
; No calls.
org $C10785
BattleSys_SlotPanelRefresh:
    STA $80                     ; save slot index
    ASL
    ASL                         ; × 4
    STA $82
    ASL                         ; × 8
    CLC
    ADC $82                     ; slot × 12 (= 6 rows × 2 cols × word-pair stride)
    TAX
    STX.b $82                   ; $82/$83 = tilemap base offset (16-bit)
    LDA.w $95F1                 ; panel-state flag
    BEQ .empty_panel            ; zero → draw empty panel
    LDA $80
    TAX
    LDA.w $9F25,X               ; per-slot flag A
    ORA.w $9F28,X               ; OR per-slot flag B
    BEQ .empty_panel            ; both zero → empty panel
    LDA.w $A117                 ; timing/animation flag
    BEQ .ready_panel            ; zero → ready panel
    LDA.w $A6DE                 ; PC-change flag
    CMP #$03
    BEQ .ready_panel            ; = 3 → ready panel
    LDA $80
    CMP.w $A115                 ; compare slot with active PC
    BEQ .empty_panel            ; same PC → empty
    LDX.w $A115                 ; X = active PC index
    LDA.w $A6D9,X               ; slot state for active PC
    BMI .ready_panel            ; negative → ready panel

.empty_panel:
    TDC
    TAX                         ; X = table index (starts at 0)
    LDA #$06
    STA $80                     ; row counter = 6
.empty_row_start:
    LDA #$07
    STA $81                     ; col counter = 7
    LDY.b $82                   ; Y = current row base
.empty_col_loop:
    LDA.l $CCFA41,X             ; tile from empty-panel table
    STA.w $0CC0,Y
    LDA #$29                    ; attr = $29
    STA.w $0CC1,Y
    INY
    INY
    INX
    DEC $81
    BNE .empty_col_loop
    REP #$21                    ; M=0, C=0
    LDA $82
    db $69,$40,$00              ; ADC #$0040 — advance to next row (64 word-pairs)
    STA $82
    TDC
    SEP #$20                    ; M=1
    DEC $80
    BNE .empty_row_start
    BRA .done

.ready_panel:
    TDC
    TAX                         ; X = table index
    LDA #$06
    STA $80                     ; row counter = 6
.ready_row_start:
    LDA #$07
    STA $81                     ; col counter = 7
    LDY.b $82
.ready_col_loop:
    LDA.l $CCFA6B,X             ; tile from ready-panel table
    STA.w $0CC0,Y
    LDA #$29
    STA.w $0CC1,Y
    INY
    INY
    INX
    DEC $81
    BNE .ready_col_loop
    REP #$21                    ; M=0, C=0
    LDA $82
    db $69,$40,$00              ; ADC #$0040
    STA $82
    TDC
    SEP #$20                    ; M=1
    DEC $80
    BNE .ready_row_start
.done:
    RTS

; $C1:081E — BattleMenu_DrawReadyWindowEdges (202 bytes, $081E–$08E7)
; Draw the command-window border strips for all active PC slots and then
; clear/repaint the active-PC column (BattleUI_ClearActivePanelColumn).
; Iterates slots 0–2 via $A6D9: for each slot whose state is non-negative,
; selects a column offset and calls BattleMenu_DrawWindowEdgeStrip ($0929).
; The $84 flag controls left (0) vs right (1) edge.  Then calls
; BattleUI_SetPanelAttrColumn for the active PC and repaints the status tiles.
; BattleUI_ClearActivePanelColumn ($0872) is a separate entry point used
; when only the column redraw is needed (called also from $C10C6E).
; Entry: M=1, X=0 (16-bit)
; Exit:  M=1; $80/$82/$84 clobbered; X/Y clobbered
; Calls: BattleMenu_DrawWindowEdgeStrip ($0929), BattleUI_SetPanelAttrColumn ($08E8)
org $C1081E
BattleMenu_DrawReadyWindowEdges:
    STZ $84                     ; edge flag = 0 (left edge)
    LDA.w $A6D9                 ; slot-state for PC slot 0
    BMI .check_slot1            ; negative → skip slot 0 strip
    LDX.w #$0000                ; col offset = 0
    STX.b $82
    JSR BattleMenu_DrawWindowEdgeStrip
.check_slot1:
    LDA.w $A6DA                 ; slot-state for PC slot 1
    BMI .check_slot2            ; negative → skip slot 1 strip
    LDA.w $A6D9                 ; re-check slot 0
    BMI .slot1_left             ; slot 0 present → right edge for slot 1
    LDA #$01
    STA $84                     ; right-edge flag
    LDX.w #$000E                ; col offset $0E (right side of 2-slot bar)
    BRA .slot1_draw
.slot1_left:
    LDX.w #$000C                ; col offset $0C (left side, slot 0 absent)
.slot1_draw:
    STX.b $82
    JSR BattleMenu_DrawWindowEdgeStrip
    STZ $84                     ; reset edge flag
.check_slot2:
    LDA.w $A6DB                 ; slot-state for PC slot 2
    BMI .active_pc_section      ; negative → skip slot 2 strip
    LDA.w $A6DA                 ; re-check slot 1
    BMI .slot2_left             ; slot 1 present → right edge for slot 2
    LDA #$01
    STA $84
    LDX.w #$001A                ; col offset $1A (right of 3-slot bar)
    BRA .slot2_draw
.slot2_left:
    LDX.w #$0018                ; col offset $18 (left, slot 1 absent)
.slot2_draw:
    STX.b $82
    JSR BattleMenu_DrawWindowEdgeStrip
.active_pc_section:
    LDA.w $A6DD                 ; active PC index
    TAX
    LDA.w $A6D9,X               ; slot-state for active PC
    JSR BattleUI_SetPanelAttrColumn
    INC.w $A43F                 ; set redraw flag

; $C1:0872 — BattleUI_ClearActivePanelColumn (entry point within above body)
; Zero a 6-row × 2-col block of tilemap ($0CC0/$0E02 + slot×12) for the
; current active slot ($95D5), then repaint ATB-source corner tiles if $A43F
; was set (newly-active PC $A6DD).
; Entry: M=1, X=0 (16-bit)
; Exit:  M=1; $80/X/Y clobbered; $A43F = 0
; No calls.
BattleUI_ClearActivePanelColumn:
    LDA.w $95D5                 ; current active slot index
    ASL
    ASL
    STA $80                     ; $80 = slot × 4
    ASL
    CLC
    ADC $80                     ; slot × 12
    TAX                         ; X = tilemap column offset
    STZ.w $0CC0,X
    STZ.w $0D00,X
    STZ.w $0D40,X
    STZ.w $0D80,X
    STZ.w $0DC0,X
    STZ.w $0E00,X
    STZ.w $0CC2,X
    STZ.w $0D02,X
    STZ.w $0D42,X
    STZ.w $0D82,X
    STZ.w $0DC2,X
    STZ.w $0E02,X
    LDA.w $A43F                 ; redraw flag
    BEQ .clear_done             ; zero → just clear flag and return
    LDA.w $A6DD                 ; newly-active PC index
    TAX
    ASL
    ASL
    STA $80                     ; $80 = active × 4
    ASL
    CLC
    ADC $80                     ; active × 12
    TAY
    STY.b $80                   ; $80/$81 = active × 12 (16-bit DP save)
    LDA.w $A6D9,X               ; slot-state for active PC
    TAX
    LDA.w $95DC,X               ; lookup index from slot-state
    ASL
    TAX                         ; X = table index × 2
    REP #$21                    ; M=0, C=0
    LDA.l $CCFADD,X             ; 16-bit column offset from table
    ADC $80                     ; + active × 12
    TAX                         ; X = absolute tilemap index
    TDC
    SEP #$20                    ; M=1
    LDA.w $9609                 ; transition flag
    BNE .clear_done             ; non-zero → skip tile repaint
    LDA #$60                    ; top-left ATB source corner tile
    STA.w $0CC0,X
    LDA #$61
    STA.w $0CC2,X
    LDA #$62
    STA.w $0D00,X
    LDA #$63
    STA.w $0D02,X
.clear_done:
    STZ.w $A43F                 ; clear redraw flag
    RTS

; $C1:08E8 — BattleUI_SetPanelAttrColumn (65 bytes, $08E8–$0928)
; For PC slot A: pick the status-bar tilemap column offset from table $CCFA29
; or $CCFA23 (depending on party layout $9F20) and write attr $29 to a
; 5-tile-high × 2-col block ($0CC0..$0D08,X stride $02).
; Entry: M=1, X=0 (16-bit), A = PC slot index (0–2)
; Exit:  M=1; X = column offset; A = $29; Y unchanged
; No calls.
org $C108E8
BattleUI_SetPanelAttrColumn:
    ASL                         ; slot × 2 (table index)
    TAX
    REP #$20                    ; M=0
    LDA.w $9F20                 ; BattleGaugeDisplayType (16-bit; type 0/1/2)
    BNE .type_not0
    LDA.l $CCFA29,X             ; type 0 → column offset table A
    BRA .got_offset
.type_not0:
    DEC A                       ; type − 1
    BNE .type_not1              ; non-zero → type 2 → also table A
    LDA.l $CCFA23,X             ; type 1 → column offset table B
    BRA .got_offset
.type_not1:
    LDA.l $CCFA29,X             ; type 2 → table A (same as type 0)
.got_offset:
    TAX                         ; X = column offset (tilemap index)
    TDC
    SEP #$20                    ; M=1
    LDA #$29                    ; attr byte
    STA.w $0CC0,X
    STA.w $0CC2,X
    STA.w $0CC4,X
    STA.w $0CC6,X
    STA.w $0CC8,X
    STA.w $0D00,X
    STA.w $0D02,X
    STA.w $0D04,X
    STA.w $0D06,X
    STA.w $0D08,X
    RTS

; $C1:0929 — BattleMenu_DrawWindowEdgeStrip (52 bytes, $0929–$095C)
; Copy a 6-row window-border strip from tile table $D159FC into the
; command-window tilemap at $0B40+$82.  $84=0 → left edge ($0E/$0F tile pair,
; 14 bytes per row); $84≠0 → right edge ($0C/$0D tile pair, 12 bytes + 2 INX).
; Each row advances Y by the row stride (64 via REP/ADC) after writing.
; Entry: M=1, X=0 (16-bit), $82 = tilemap col offset, $84 = edge flag
; Exit:  M=1; X/Y/$80/$81/$82 clobbered
; No calls.
org $C10929
BattleMenu_DrawWindowEdgeStrip:
    TDC
    TAX                         ; X = 0 (table index into $D159FC)
    LDA #$06
    STA $81                     ; row counter = 6
.row_loop:
    LDA $84                     ; edge flag
    BNE .right_edge
    LDA #$0E                    ; left edge: 14 bytes per row-entry
    BRA .pick_done
.right_edge:
    INX                         ; skip to right-edge entries (offset +2 in table)
    INX
    LDA #$0C                    ; right edge: 12 bytes per row-entry
.pick_done:
    STA $80                     ; byte count for inner copy
    LDY.b $82                   ; Y = current tilemap row base
.inner_loop:
    LDA.l $D159FC,X             ; window border tile byte
    STA.w $0B40,Y               ; write to command-window tilemap
    INX
    INY
    DEC $80
    BNE .inner_loop
    REP #$21                    ; M=0, C=0
    LDA $82
    db $69,$40,$00              ; ADC #$0040 — advance to next row (stride 64)
    STA $82
    TDC
    SEP #$20                    ; M=1
    DEC $81                     ; row counter
    BNE .row_loop
    RTS

; ============================================================
; Trig / Geometry Cluster ($C1:01F9–$C1:0298)
; ============================================================

; $C1:01F9 — Battle_SinLookup (41 bytes, $01F9–$0221)
; Sine lookup: computes sin(A) × $AE and stores result in $AA.
; A (8-bit on entry) is a phase angle; table at $C0F900 gives signed
; sine values. Multiplied by $AE via Battle_MulAccum ($A5 = sin, $A7 = $AE).
; Entry: M=1 (8-bit A), X=0 (16-bit); angle in A
; Exit:  M=1 (8-bit A); result byte in $AA (high byte of MulAccum product)
; Calls: Battle_MulAccum ($C1:00A7, matched)
org $C101F9
Battle_SinLookup:
    REP #$20                    ; A → 16-bit
    ASL A
    ASL A
    AND.w #$03FF                ; wrap angle to [0, 1023] (512-entry sin table, × 2 = 1024 indices)
    TAX                         ; X = table byte index
    LDA.l $C0F900,X             ; read 16-bit entry from sine table (signed, little-endian)
    AND.w #$00FF                ; keep low byte (magnitude)
    CPX.w #$0200                ; X >= $0200 → second half of sine (negative quadrants)
    BCC .first_quadrant
    EOR.w #$FFFF                ; invert for negative quadrant
    INC A                       ; two's complement negate (EOR + INC)
.first_quadrant:
    STA $A7                     ; $A7 (M=0: also clears $A8) = signed sin value
    LDA $AE                     ; read multiplier (M=0: also reads $AF)
    AND.w #$00FF                ; keep low byte only ($AE value, zero-extend)
    STA $A5                     ; $A5 (M=0: also clears $A6) = multiplier byte
    SEP #$20                    ; A → 8-bit
    JSR Battle_MulAccum         ; $A5 × $A7 → 32-bit accumulate into $A9/$AA
    LDA $AA                     ; return high byte of product
    RTS

; $C1:0222 — Calc_Delta16 (119 bytes, $0222–$0298)
; 16-bit signed vector delta and direction-angle computation.
; Computes (D3–D5) and (D4–D6) as 16-bit signed differences (→ $D7/$D8, $D9/$DA),
; derives absolute deltas ($DE/$DF, $E0/$E1), computes a blended "magnitude" index
; in $E2, looks up a base direction angle from $C0F300, then adjusts the sign
; of the angle based on the quadrant determined by $D8 and $DA sign bits.
; Entry: M=1 (8-bit A), X=0 (16-bit)
; Exit:  M=1 (8-bit A); direction angle in $DB
; No JSR/JSL calls.
org $C10222
Calc_Delta16:
    ; --- Phase 1: compute (D3 − D5) → $D7/$D8, (D4 − D6) → $D9/$DA ---
    SEC
    LDA $D3
    SBC $D5
    STA $D7
    LDA #$00
    SBC #$00                    ; propagate borrow → $D8 = high byte (0 or $FF)
    STA $D8
    SEC
    LDA $D4
    SBC $D6
    STA $D9
    LDA #$00
    SBC #$00                    ; propagate borrow → $DA
    STA $DA
    ; --- Phase 2: absolute values → $DE/$DF, $E0/$E1 ---
    LDA $D7
    EOR $D8                     ; XOR sign byte: if negative, flips bits
    SEC
    SBC $D8                     ; subtract sign byte: two's complement abs
    STA $DE
    STZ $DF
    LDA $D9
    EOR $DA
    SEC
    SBC $DA
    STA $E0
    STZ $E1
    ; --- Phase 3: blended magnitude index in $E2 ---
    REP #$20                    ; A → 16-bit
    LDA $DE                     ; 16-bit |ΔX| ($DE/$DF)
    LSR A
    LSR A
    LSR A                       ; |ΔX| >> 3
    STA $DC
    LDA $E0                     ; 16-bit |ΔY| ($E0/$E1)
    AND.w #$FFF8                ; mask lower 3 bits (align to 8)
    ASL A
    ASL A                       ; |ΔY| & $FFF8, × 4
    CLC
    ADC $DC                     ; + (|ΔX| >> 3)
    STA $E2                     ; blended index
    ASL A                       ; × 2 (dead code: X overridden by LDX $E2 below)
    TAX
    TDC                         ; A = 0
    SEP #$20                    ; A → 8-bit
    LDX $E2                     ; X = table index (overrides dead TAX above)
    LDA.l $C0F300,X             ; look up base direction angle from $C0F300
    STA $DB
    ; --- Phase 4: quadrant adjustment of angle ---
    LDA $D8                     ; check sign of ΔX (high byte)
    BMI .d8_negative            ; ΔX < 0
    LDA $DA                     ; check sign of ΔY (high byte)
    BMI .da_negative_q1         ; ΔX ≥ 0, ΔY < 0 → Q4
    ; Q1: ΔX ≥ 0, ΔY ≥ 0 → angle = $80 + base
    CLC
    LDA #$80
    ADC $DB
    STA $DB
    RTS
.da_negative_q1:                ; Q4: ΔX ≥ 0, ΔY < 0 → angle = $80 − base
    SEC
    LDA #$80
    SBC $DB
    STA $DB
    RTS
.d8_negative:
    LDA $DA                     ; check sign of ΔY
    BMI .da_negative_q3         ; ΔX < 0, ΔY < 0 → Q3
    ; Q2: ΔX < 0, ΔY ≥ 0 → angle = 0 − base (negate)
    TDC                         ; A = 0
    SEC
    SBC $DB
    STA $DB
.da_negative_q3:                ; Q3: ΔX < 0, ΔY < 0 → angle unchanged ($DB as is)
    LDA $DB
    RTS

; ============================================================
; Status-Bar UI Cluster ($C1:0299–$C1:05A6)
; ============================================================

; $C1:0299 — BattleUI_BuildStatusBarFrame (782 bytes, $0299–$05A6)
; Initialises the battle status-bar tilemap buffer at WRAM $7E:0CC0:
;   1. Clears 192 word-pairs (tile=$00, attr=$29).
;   2. Overlays panel-border tiles for the active gauge arrangement
;      (BattleGaugeDisplayType $9F20: 0=3PC HP+MaxHP+MP, 1=3PC HP+MP, 2=2PC+TP).
;   3. Fills each active PC slot (0-2, via $96F5 presence table) with:
;      - 5-char name tiles (from $9412 name buffer, offset via $CCF837)
;        written to both the top row and a copy row 64 word-pairs earlier.
;      - Current HP digits ($5E30+idx), formatted via FormatNumberDigits /
;        BlankLeadingZeros; low-HP flag set in $A10F when curHP ≤ maxHP/8.
;      - Max HP digits ($5E32+idx) for gauge type 0 only.
;      - Current MP digits ($5E34+idx), formatted via DivTen9499.
;      - TP gauge bar tiles ($5D/$5E) for gauge types 1/2.
;   4. Fills each active enemy slot (0-2, via $98CC) with 11-char names from $ACBC.
;   5. Updates active-PC tracking vars ($A6DE/$A6DD/$A6D9/$95D5/$95F1),
;      dispatches BattleSys_SlotPanelRefresh (per active slot) and
;      BattleMenu_DrawReadyWindowEdges (draws command-window border) when dirty;
;      jumps to BattleUI_SetPanelAttrColumn if $A86B == 0 and PC changed.
; Entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=0, DB=$7E
; Exit:  M=1; X, Y clobbered; $80/$84/$86/$8E/$A2 used as temporaries
; Calls: Battle_ShiftRight3, BattleMsg_FormatNumberDigits, BattleMsg_BlankLeadingZeros,
;        Battle_DivTen9499, BattleUI_DrawSlotGaugeBar (stub), BattleUI_SetPanelAttrColumn (stub),
;        BattleSys_SlotPanelRefresh (stub), BattleMenu_DrawReadyWindowEdges (stub)
org $C10299
BattleUI_BuildStatusBarFrame:
    TDC
    TAX
    TAY
.init_loop:
    TDC                             ; tile byte = 0
    STA.w $0CC0,Y
    LDA #$29                        ; attr byte = $29
    STA.w $0CC1,Y
    INY
    INY
    INX
    CPX.w #$00C0                    ; 192 word-pairs cleared?
    BNE .init_loop
    ; --- Overlay panel-border tiles based on BattleGaugeDisplayType ($9F20) ---
    LDA.w $9F20
    BNE .gauge_not0
    ; Gauge type 0: 3-PC with HP+MaxHP+MP columns
    LDA #$64
    STA.w $0CE8
    LDA #$66
    STA.w $0CEA
    STA.w $0CFC
    LDA #$65
    STA.w $0CFA
    BRA .gauge_dest_sel
.gauge_not0:
    DEC A
    BNE .gauge_type2
    ; Gauge type 1: 3-PC with HP+MP only
    LDA #$64
    STA.w $0CDA
    LDA #$66
    STA.w $0CDC
    STA.w $0CE4
    LDA #$65
    STA.w $0CE2
    BRA .gauge_dest_sel
.gauge_type2:
    ; Gauge type 2: 2-PC+TP layout
    LDA #$64
    STA.w $0CE6
    LDA #$66
    STA.w $0CE8
    STA.w $0CF0
    LDA #$65
    STA.w $0CEE
.gauge_dest_sel:
    ; Choose Y-dest base: type 1 → $0068, types 0/2 → $005A
    LDA.w $9F20
    BEQ .dest_5A
    DEC A
    BNE .dest_5A
    LDX.w #$0068
    BRA .set_dest_base
.dest_5A:
    LDX.w #$005A
.set_dest_base:
    STX.B $84                       ; $84 = tilemap word-pair dest base
    TDC
    TAX
    STX.B $80                       ; $80 = PC slot index (0)
    ; --- BattleUI_DrawPcNamePanel ---
    ; Writes one PC slot's name + HP/MP/TP digits into status-bar tilemap.
    ; Called as a loop: after each slot, BattleUI_NextNamePanel advances $84/$80
    ; and JMPs back here for the next slot.
BattleUI_DrawPcNamePanel:
    LDY.B $84                       ; Y = tilemap word-pair dest
    LDX.B $80                       ; X = PC slot index
    LDA.w $96F5,X                   ; is this slot active?
    BNE .pc_present
    JMP.w BattleUI_NextNamePanel    ; inactive → skip to next slot
.pc_present:
    LDA.l $CCF837,X                 ; name buffer offset for this slot (1 byte)
    TAX                             ; X = offset into $9412 name buffer
    LDA #$05
    STA.B $8E                       ; $8E = char count (5)
.name_row1_loop:                    ; write 5-char name to tilemap row 1
    LDA.w $9412,X
    STA.w $0CC0,Y
    LDA #$2D                        ; attr = $2D (normal palette, row 1)
    STA.w $0CC1,Y
    INY
    INY
    INX
    DEC.B $8E
    BNE .name_row1_loop
    REP #$20                        ; M=0 (16-bit A)
    SEC
    LDA.B $84                       ; dest base (16-bit DP load)
    db $E9,$40,$00                  ; SBC #$0040 — row-2 dest = row-1 dest − 64 pairs (M=0)
    TAY
    TDC
    SEP #$20                        ; M=1
    LDA #$05
    STA.B $8E
.name_row2_loop:                    ; write 5-char name to tilemap row 2 (same tiles)
    LDA.w $9412,X
    STA.w $0CC0,Y
    LDA #$2D
    STA.w $0CC1,Y
    INY
    INY
    INX
    DEC.B $8E
    BNE .name_row2_loop
    ; --- Low-HP flag and HP digit formatting ---
    STZ.w $A10F                     ; clear low-HP flag
    REP #$20                        ; M=0 (16-bit A)
    LDA.B $80                       ; PC slot index (zero-extended 16-bit)
    ASL A
    TAX                             ; X = slot × 2
    LDA.l $CCF8ED,X                 ; load battler work-area index (16-bit)
    STA.B $A2                       ; $A2 = battler index (stored 16-bit)
    TAX
    LDA.w $5E30,X                   ; BatWork_CurHp (16-bit)
    STA.w $9499                     ; → format workspace
    BEQ .lhp_set                    ; curHP == 0 → set low-HP flag
    LDA.w $5E32,X                   ; BatWork_MaxHp (16-bit)
    JSR Battle_ShiftRight3          ; maxHP >> 3 (operates in M=0, 16-bit shifts)
    CMP.w $9499                     ; maxHP/8 vs curHP
    BEQ .lhp_equal                  ; equal → check $A110
    BCC .lhp_ok                     ; maxHP/8 < curHP → HP not low
.lhp_equal:
    LDA.w $A110
    BEQ .lhp_ok
.lhp_set:
    INC.w $A10F                     ; set low-HP indicator
.lhp_ok:
    ; --- HP digit Y-offset based on gauge type ---
    LDA.w $9F20                     ; BattleGaugeDisplayType (M=0, 16-bit read)
    BNE .hp_yoff_not0
    CLC
    LDA.B $84
    db $69,$0E,$00                  ; ADC #$000E — gauge 0: HP at dest+$0E (M=0)
    BRA .hp_fmt
.hp_yoff_not0:
    DEC A
    BNE .hp_yoff_type2
    SEC
    LDA.B $84
    db $E9,$0E,$00                  ; SBC #$000E — gauge 1: HP at dest−$0E (M=0)
    BRA .hp_fmt
.hp_yoff_type2:
    CLC
    LDA.B $84
    db $69,$0C,$00                  ; ADC #$000C — gauge 2: HP at dest+$0C (M=0)
.hp_fmt:
    TAY
    JSR BattleMsg_FormatNumberDigits ; exits M=1
    JSR BattleMsg_BlankLeadingZeros
    LDA.w $949D                     ; hundreds digit tile (M=1)
    STA.w $0CC0,Y
    LDA.w $949E
    STA.w $0CC2,Y
    LDA.w $949F
    STA.w $0CC4,Y
    LDX.w #$0029                    ; normal attr
    LDA.w $A10F
    BEQ .hp_attr_ok
    LDX.w #$002D                    ; low-HP attr
.hp_attr_ok:
    TXA
    STA.w $0CC1,Y
    STA.w $0CC3,Y
    STA.w $0CC5,Y
    STA.w $0CC7,Y
    LDA.w $9F20
    BNE .hp_bar_not0
    LDA #$E0                        ; gauge 0: HP-bar tile
    STA.w $0CC6,Y
    BRA .maxhp_fmt
.hp_bar_not0:
    LDA #$5F                        ; other gauges: blank/separator tile
    STA.w $0CC6,Y
    BRA .mp_display                 ; skip MaxHP section
.maxhp_fmt:
    REP #$20                        ; M=0
    LDX.B $A2                       ; battler index (16-bit DP load)
    LDA.w $5E32,X                   ; BatWork_MaxHp (16-bit)
    STA.w $9499
    CLC
    LDA.B $84
    db $69,$16,$00                  ; ADC #$0016 — MaxHP at dest+$0016 (M=0)
    TAY
    JSR BattleMsg_FormatNumberDigits ; exits M=1
    JSR BattleMsg_BlankLeadingZeros
    LDA.w $949D
    STA.w $0CC0,Y
    LDA.w $949E
    STA.w $0CC2,Y
    LDA.w $949F
    STA.w $0CC4,Y
    LDX.w #$0029
    LDA.w $A10F
    BEQ .maxhp_attr_ok
    LDX.w #$002D
.maxhp_attr_ok:
    TXA
    STA.w $0CC1,Y
    STA.w $0CC3,Y
    STA.w $0CC5,Y
.mp_display:
    REP #$20                        ; M=0
    LDX.B $A2
    LDA.w $5E34,X                   ; BatWork_CurMp (16-bit)
    STA.w $9499
    LDA.w $9F20                     ; gauge type (M=0, 16-bit read)
    BNE .mp_yoff_not0
    CLC
    LDA.B $84
    db $69,$1E,$00                  ; ADC #$001E — gauge 0: MP at dest+$1E (M=0)
    BRA .mp_fmt
.mp_yoff_not0:
    DEC A
    BNE .mp_yoff_type2
    SEC
    LDA.B $84
    db $E9,$06,$00                  ; SBC #$0006 — gauge 1: MP at dest−$06 (M=0)
    BRA .mp_fmt
.mp_yoff_type2:
    CLC
    LDA.B $84
    db $69,$14,$00                  ; ADC #$0014 — gauge 2: MP at dest+$14 (M=0)
.mp_fmt:
    TAY
    JSR Battle_DivTen9499           ; exits M=1
    LDA.w $9F20
    BNE .mp_blanking
    JSR BattleMsg_BlankLeadingZeros
    BRA .mp_place_0
.mp_blanking:
    JSR BattleMsg_BlankLeadingZeros
    LDA.w $949E
    STA.w $0CC0,Y
    LDA.w $949F
    STA.w $0CC2,Y
    LDX.w #$0029
    LDA.w $A10F
    BEQ .mp_attr_ok
    LDX.w #$002D
.mp_attr_ok:
    TXA
    STA.w $0CC1,Y
    STA.w $0CC3,Y
    BRA .tp_gauge
.mp_place_0:                        ; gauge 0: MP occupies cols 2-3 (no col 0-1)
    LDA.w $949E
    STA.w $0CC2,Y
    LDA.w $949F
    STA.w $0CC4,Y
    LDX.w #$0029
    LDA.w $A10F
    BEQ .mp_attr0_ok
    LDX.w #$002D
.mp_attr0_ok:
    TXA
    STA.w $0CC3,Y
    STA.w $0CC5,Y
.tp_gauge:
    LDA.w $9F20
    BEQ BattleUI_NextNamePanel      ; gauge type 0: no TP bar
    REP #$20                        ; M=0
    DEC A
    BNE .tp_yoff_type2
    CLC
    LDA.B $84
    db $69,$0A,$00                  ; ADC #$000A — gauge 1: TP at dest+$0A (M=0)
    BRA .tp_fmt
.tp_yoff_type2:
    CLC
    LDA.B $84
    db $69,$18,$00                  ; ADC #$0018 — gauge 2: TP at dest+$18 (M=0)
.tp_fmt:
    TAY
    TDC
    SEP #$20                        ; M=1
    LDA #$5D                        ; TP bar left tile
    STA.w $0CC0,Y
    LDA #$5E                        ; TP bar right tile
    STA.w $0CCA,Y
    LDA #$29                        ; normal attr
    STA.w $0CC1,Y
    STA.w $0CCB,Y
    JSR BattleUI_DrawSlotGaugeBar
    BRA BattleUI_NextNamePanel
    ; --- Loop tail: advance to next PC slot, then start enemy section ---
BattleUI_NextNamePanel:
    REP #$21                        ; M=0, C=0
    LDA.B $84
    db $69,$80,$00                  ; ADC #$0080 — next slot's base (M=0, 128 pairs)
    STA.B $84
    TDC
    SEP #$20                        ; M=1
    INC.B $80
    LDA.B $80
    CMP #$03
    BEQ .enemy_section
    JMP.w BattleUI_DrawPcNamePanel
.enemy_section:
    ; Draw 3 enemy name slots from $98CC presence table / $ACBC name data
    LDX.w #$0042
    STX.B $84
    TDC
    TAX
    STX.B $80
.enemy_loop:
    LDX.B $80
    LDA.w $98CC,X                   ; enemy slot present?
    BEQ .enemy_next
    ; Compute name buffer offset: slot × 24 = (slot×8)×3 = (slot << 3 + slot << 4)
    LDA.B $80
    ASL A
    ASL A
    ASL A                           ; A = slot × 8
    STA.B $8E
    ASL A                           ; A = slot × 16
    CLC
    ADC.B $8E                       ; A = slot × 24 (name record stride)
    TAX
    LDA #$0B
    STA.B $8E                       ; $8E = char count (11)
    LDY.B $84
.ename_row1_loop:                   ; write 11-char enemy name, row 1
    LDA.w $ACBC,X
    STA.w $0CC0,Y
    LDA #$29
    STA.w $0CC1,Y
    INY
    INY
    INX
    DEC.B $8E
    BNE .ename_row1_loop
    REP #$20                        ; M=0
    SEC
    LDA.B $84
    db $E9,$40,$00                  ; SBC #$0040 — row-2 dest (M=0)
    TAY
    TDC
    SEP #$20                        ; M=1
    INX                             ; skip one byte (gap between row data)
    LDA #$0B
    STA.B $8E
.ename_row2_loop:                   ; write 11-char enemy name, row 2
    LDA.w $ACBC,X
    STA.w $0CC0,Y
    LDA #$29
    STA.w $0CC1,Y
    INY
    INY
    INX
    DEC.B $8E
    BNE .ename_row2_loop
    REP #$21                        ; M=0, C=0
    LDA.B $84
    db $69,$80,$00                  ; ADC #$0080 — next enemy slot base (M=0)
    STA.B $84
    TDC
    SEP #$20                        ; M=1
.enemy_next:
    INC.B $80
    LDA.B $80
    CMP #$03
    BNE .enemy_loop
    ; --- Active-PC tracking and panel refresh ---
    LDA.w $A6DE
    BEQ .buildbar_done              ; no active-PC change → done
    LDA.w $A86B
    BEQ .check_slot_state           ; menu-open flag → check slot state
    LDA.w $A62D
    CMP.w $A0D7
    BEQ .buildbar_done              ; same PC as before → done
    LDA #$FE
    STA.w $A6DF
    LDA.w $A62D
    JMP.w BattleUI_SetPanelAttrColumn
.check_slot_state:
    LDA.w $95DB
    BEQ .do_slot_state
    RTS                             ; early exit — state not ready
.do_slot_state:
    LDA.w $A6DE
    DEC A
    STA.w $95F1
    LDA.w $A6DD
    TAX
    LDA.w $A6D9,X
    BPL .slot_search_done           ; slot valid → use it
    TDC
    TAX
.find_valid_slot:
    LDA.w $A6D9,X
    BPL .found_slot
    INX
    BRA .find_valid_slot
.found_slot:
    PHA
    TXA
    STA.w $A6DD
    PLA
.slot_search_done:
    STA.w $95D5
    TDC
    TAX
    STX.B $86
.slot_refresh_loop:
    LDX.B $86
    LDA.w $A6D9,X
    BMI .slot_skip
    JSR BattleSys_SlotPanelRefresh
.slot_skip:
    INC.B $86
    LDA.B $86
    CMP #$03
    BNE .slot_refresh_loop
    JSR BattleMenu_DrawReadyWindowEdges
.buildbar_done:
    RTS

; ============================================================
; BattleUI_UpdateNextPcPanel ($C1:05A7–$C1:06EF, 329 bytes)
; Peer to BattleUI_BuildStatusBarFrame: refreshes HP/MP display and
; ATB gauge bars for the next-active PC slot.
; Logic:
;   1. Early-exit check: skip refresh if slot 2 is absent ($A6DB<0), a
;      global inhibit flag is set ($A09A≠0), gauge type is 0 ($9F20==0),
;      or gauge type is 2 (DEC A leaves A=1≠0). Type 1 jumps to .tp_gauges.
;   2. Advance next-PC pointer ($A6E0), wrap at 3, check slot presence.
;   3. Compute tilemap dest Y via long table ($CCFA2F/$CCFA35/$CCFA3B by type).
;   4. Format and write HP digits ($9499–$949F) with low-HP attr ($2D) if needed.
;   5. For gauge type 0: write extra HP attr bytes ($0CC9/$0CCB/$0CCD,Y).
;   6. Format and write MP digits, offset Y by +$10 (type 0) or +$08 (types 1/2).
;   7. Draw ATB gauge bars for all 3 active slots via Battle_DrawHpBars loop.
; Entry: M=1 (8-bit A), X=0 (16-bit), DP=0, DB=$7E
; Exit:  M=1; X, Y clobbered; $80/$86/$A2/$A10F/$9499 used as temporaries
; Calls: Battle_ShiftRight3 ($011B), BattleMsg_FormatNumberDigits ($011F),
;        BattleMsg_BlankLeadingZeros ($104E), Battle_DivTen9499 ($0174),
;        BattleUI_DrawSlotGaugeBar ($06F0)
; Sub-entry: Battle_DrawHpBars ($06DB) — redraw ATB gauge bars for all 3 slots
org $C105A7
BattleUI_UpdateNextPcPanel:
    LDA.w $A6DB                     ; slot 2 state
    BMI .advance_panel              ; absent → update counter anyway
    LDA.w $A09A                     ; panel update-inhibit flag
    BNE .advance_panel              ; inhibited → skip digit refresh
    LDA.w $9F20                     ; gauge display type
    BEQ .advance_panel              ; type 0 → skip (fixed HP+MaxHP+MP layout)
    DEC A                           ; type 1 → A=0; type 2 → A=1
    BNE .advance_panel              ; type 2 → skip
    JMP .tp_gauges                  ; type 1 → jump to HP-bar draw section
.advance_panel:
    INC.w $A6E0                     ; advance next-PC slot counter
    LDA.w $A6E0
    CMP #$03
    BCC .slot_ok
    STZ.w $A6E0                     ; wrap to 0
.slot_ok:
    LDA.w $A6E0
    TAX
    STX.b $80                       ; save slot index (16-bit X → $80/$81)
    LDA.w $96F5,X                   ; slot presence flag
    BNE .slot_present
    JMP UpdateNpc_exit              ; slot empty → nothing to draw
.slot_present:
    REP #$21                        ; M=0, C=0
    LDA.b $80                       ; slot index (16-bit DP load)
    ASL
    TAX                             ; X = slot * 2
    LDA.w $9F20                     ; gauge type (16-bit; low byte = type)
    BNE .type_not0_a
    LDA.l $CCFA2F,X                 ; type 0: base Y from HP+MaxHP+MP table
    BRA .got_base_y
.type_not0_a:
    DEC A
    BNE .type_not1_a
    LDA.l $CCFA35,X                 ; type 1: base Y from HP+MP table
    BRA .got_base_y
.type_not1_a:
    LDA.l $CCFA3B,X                 ; type 2: base Y from HP+MP+TP table
.got_base_y:
    TAY
    STY.b $86                       ; save base tilemap Y (16-bit)
    TDC
    SEP #$20                        ; M=1
    STZ.w $A10F                     ; clear low-HP flag
    REP #$20                        ; M=0
    LDA.b $80                       ; slot index
    ASL
    TAX                             ; X = slot * 2
    LDA.l $CCF8ED,X                 ; battler data-struct offset
    STA.b $A2                       ; save struct offset (16-bit)
    TAX
    LDA.w $5E30,X                   ; CurHP (16-bit)
    STA.w $9499
    BEQ .set_low_hp                 ; HP == 0 → always flag low-HP
    LDA.w $5E32,X                   ; MaxHP (16-bit)
    JSR Battle_ShiftRight3          ; A = maxHP >> 3 (1/8 threshold)
    CMP.w $9499                     ; threshold vs curHP
    BEQ .check_a110                 ; equal → check secondary gate
    BCC .hp_ok                      ; threshold < curHP → not low-HP
.check_a110:
    LDA.w $A110                     ; secondary low-HP gate
    BEQ .hp_ok
.set_low_hp:
    INC.w $A10F                     ; set low-HP flag (M=0 → 16-bit INC)
.hp_ok:
    JSR BattleMsg_FormatNumberDigits ; format HP → $949D–$949F (exits M=1)
    JSR BattleMsg_BlankLeadingZeros  ; suppress leading zeros (M=1)
    LDA.w $949D                     ; hundreds digit tile
    STA.w $0CC0,Y
    LDA.w $949E                     ; tens digit tile
    STA.w $0CC2,Y
    LDA.w $949F                     ; ones digit tile
    STA.w $0CC4,Y
    LDX.w #$0029                    ; normal attr ($29 = standard palette)
    LDA.w $A10F                     ; low-HP flag
    BEQ .normal_attr
    LDX.w #$002D                    ; low-HP attr ($2D = alt palette)
.normal_attr:
    TXA
    STA.w $0CC1,Y
    STA.w $0CC3,Y
    STA.w $0CC5,Y
    STA.w $0CC7,Y
    LDA.w $9F20                     ; gauge type
    BNE .skip_type0_hp_extra        ; type ≠ 0 → skip extra HP cols
    TXA                             ; type 0: 3 extra attr bytes for MaxHP cols
    STA.w $0CC9,Y
    STA.w $0CCB,Y
    STA.w $0CCD,Y
.skip_type0_hp_extra:
    REP #$20                        ; M=0
    LDX.b $A2                       ; struct offset (16-bit DP load)
    LDA.w $5E34,X                   ; CurMP (16-bit)
    STA.w $9499
    LDA.w $9F20                     ; gauge type (16-bit load; low byte = type)
    BNE .mp_offset_short
    CLC
    LDA.b $86                       ; base tilemap Y
    db $69,$10,$00                  ; ADC #$0010 (M=0 3-byte encoding)
    TAY
    BRA .mp_dest_done
.mp_offset_short:
    CLC
    LDA.b $86
    db $69,$08,$00                  ; ADC #$0008 (M=0 3-byte encoding)
.mp_dest_done:
    TAY
    JSR Battle_DivTen9499           ; divide MP by 10 three times (exits M=1)
    LDA.w $9F20                     ; gauge type
    BNE .mp_not_type0
    JSR BattleMsg_BlankLeadingZeros
    BRA .gauge0_mp_path
.mp_not_type0:
    JSR BattleMsg_BlankLeadingZeros
    LDA.w $949E                     ; tens MP digit
    STA.w $0CC0,Y
    LDA.w $949F                     ; ones MP digit
    STA.w $0CC2,Y
    LDX.w #$0029
    LDA.w $A10F
    BEQ .mp_normal_attr
    LDX.w #$002D
.mp_normal_attr:
    TXA
    STA.w $0CC1,Y
    STA.w $0CC3,Y
    BRA .tp_gauges
.gauge0_mp_path:
    LDA.w $949E
    STA.w $0CC2,Y
    LDA.w $949F
    STA.w $0CC4,Y
    LDX.w #$0029
    LDA.w $A10F
    BEQ .gauge0_normal_attr
    LDX.w #$002D
.gauge0_normal_attr:
    TXA
    STA.w $0CC3,Y
    STA.w $0CC5,Y
.tp_gauges:
    LDA.w $9F20                     ; gauge type
    BEQ UpdateNpc_exit              ; type 0 → skip ATB-gauge pass
    TDC
    TAX                             ; X = 0 (slot counter)
Battle_DrawHpBars:
    STX.b $80                       ; reset slot counter
.gauge_loop:
    LDX.b $80                       ; X = current slot
    LDA.w $96F5,X                   ; slot presence flag
    BEQ .next_slot
    JSR BattleUI_DrawSlotGaugeBar
.next_slot:
    INC.b $80
    LDA.b $80
    CMP #$03
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
;   - If item ID ($1583,X) = 0 or unconfirmed-animation ($1580,X) = 0 → exit.
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
    LDA.w $1583,X                   ; item ID
    BEQ .empty_slot                 ; 0 → empty, skip
    LDA.w $1580,X                   ; unconfirmed-animation / display flag
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
; Leading-zero suppression for 3-digit HP/reward display.
; Checks $949D (hundreds tile): if == $73 (zero-glyph), replaces with $FF (blank).
; Then checks $949E (tens tile): if == $73 AND $949D == $FF (already blanked),
; replaces $949E with $FF as well. Ones digit ($949F) is never blanked.
; Typically called immediately after BattleMsg_FormatNumberDigits.
; Entry: M=1 (8-bit A), X=0 (16-bit), DB=$7E
; Exit:  M=1; A clobbered; X/Y unchanged
; No JSR/JSL calls.
org $C1104E
BattleMsg_BlankLeadingZeros:
    LDA.w $949D                     ; hundreds digit tile
    CMP #$73                        ; = zero glyph?
    BNE .check_tens                 ; no → keep, check tens
    LDA #$FF
    STA.w $949D                     ; blank hundreds
.check_tens:
    LDA.w $949E                     ; tens digit tile
    CMP #$73                        ; = zero glyph?
    BNE .done                       ; no → done
    LDA.w $949D                     ; was hundreds already blanked?
    CMP #$FF
    BNE .done                       ; no → keep tens
    LDA #$FF
    STA.w $949E                     ; blank tens
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
    JSR ($1FF8,X)                   ; target-mode handler table (unmatched)
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
