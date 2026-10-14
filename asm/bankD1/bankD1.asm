; ============================================================
; Bank $D1 — battle data, and the battle's screen-effect code
; File offset 0x110000 (bank $D1 = ROM offset $110000)
;
; $D1:0000-$D1:E709 is data (left as ROM bytes): among it, by the
; readers matched so far, the battle's packed sprite frames, palette
; sets and the menu's window maps (the !BattleRom_* names at $D1xxxx).
; From $D1:E70A to $D1:FEF3 the bank holds code that works with the
; battle code in bank $CD (bankCD.asm): the battle's NMI and IRQ
; handlers while that code runs, its set-up at the battle's start
; (BattleFx_Init, through the vector $CD:0000), and helpers bank $CD
; calls by JSL, most of them from one-line command handlers (JSL, RTS)
; whose argument bytes they read through the long pointer at DP $40
; (!BattleCD_FxScriptPtr): palette moves, a background colour gradient that
; follows an enemy's HP, window shapes drawn into the two window tables
; at $7E:C161 and $7E:C4E1 (!BattleFx_WinTable0/1; the one written is
; picked by bit 0 of !Battle_FrameCount), background set loads and the
; settings of battle-script opcode $80. The window tables hold 4 bytes
; per screen line: the left and right edge of a first and of a second
; window. That they feed the window registers WH0-WH3 by HDMA is
; inferred from that layout (BattleCD_NmiSetup sets up HDMA channels
; 0-6; which of them read these tables is not traced here). $D1:FEF4-
; $FFFF is $FF fill.
; ============================================================

arch snes.cpu
hirom

org $D1E70A

; ============================================================
; Palettes, the NMI handler and the map upload ($D1:E70A–$D1:EA20)
; ============================================================

; $D1:E70A — BattleFx_SwapObjPalettes (114 bytes, $E70A–$E77B)
; Swaps OBJ palette rows 1-3 with rows 5-7, colour for colour, in both
; the live (!Battle_PaletteLive) and the saved (!Battle_PaletteSaved)
; palette. Before that it zeroes !Battle_UnkA101 and, when
; !Battle_Unk2A21 bit 1 is set, flips bit 6 of FieldAnimB[7].Unk1 (the
; first colour of palette animation 7 moves 64 colours, four rows: to
; follow the swapped rows, probably). At the end it steps the 16-bit
; !BattleCD_FxScriptPtr back by one (why is not traced: probably to undo a
; step past an argument byte this command does not have; the bank-$CD
; handler that ends just before the JSL, at $CD:1B95, has the same
; 16-bit DEC).
; Callers note: the JSL at $CD:1B9A is followed by RTS, the shape of
;   bank $CD's script command handlers (past $CD:16B4, not matched).
; Callers (1 JSL site): unmatched ($CD:1B9A).
; Entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=0 (DP $40), DB=$7E (the
;        palettes and flags are read .w); the bank-$CD caller is not
;        matched, so this is from the code, not traced there
; Exit:  M=1, X=0, DP and DB unchanged; A = 0 (TDC with DP=0); X =
;        !Battle_RowBytes; Y = the last colour moved (16-bit);
;        !BattleCD_FxScriptPtr's low word one less
BattleFx_SwapObjPalettes:
    STZ.w !Battle_UnkA101
    LDA.w !Battle_Unk2A21
    AND.b #$02
    BEQ .swap
    LDA.w FieldAnimB[7].Unk1
    EOR.b #!BattleFx_Anim7ColourBit
    STA.w FieldAnimB[7].Unk1
.swap:
    REP #$20
    LDX.w #$0000
.colour:
    LDY.w !Battle_PaletteLive+(1*!Battle_RowBytes),X
    LDA.w !Battle_PaletteLive+(5*!Battle_RowBytes),X
    STA.w !Battle_PaletteLive+(1*!Battle_RowBytes),X
    TYA
    STA.w !Battle_PaletteLive+(5*!Battle_RowBytes),X
    LDY.w !Battle_PaletteLive+(2*!Battle_RowBytes),X
    LDA.w !Battle_PaletteLive+(6*!Battle_RowBytes),X
    STA.w !Battle_PaletteLive+(2*!Battle_RowBytes),X
    TYA
    STA.w !Battle_PaletteLive+(6*!Battle_RowBytes),X
    LDY.w !Battle_PaletteLive+(3*!Battle_RowBytes),X
    LDA.w !Battle_PaletteLive+(7*!Battle_RowBytes),X
    STA.w !Battle_PaletteLive+(3*!Battle_RowBytes),X
    TYA
    STA.w !Battle_PaletteLive+(7*!Battle_RowBytes),X
    LDY.w !Battle_PaletteSaved+(1*!Battle_RowBytes),X
    LDA.w !Battle_PaletteSaved+(5*!Battle_RowBytes),X
    STA.w !Battle_PaletteSaved+(1*!Battle_RowBytes),X
    TYA
    STA.w !Battle_PaletteSaved+(5*!Battle_RowBytes),X
    LDY.w !Battle_PaletteSaved+(2*!Battle_RowBytes),X
    LDA.w !Battle_PaletteSaved+(6*!Battle_RowBytes),X
    STA.w !Battle_PaletteSaved+(2*!Battle_RowBytes),X
    TYA
    STA.w !Battle_PaletteSaved+(6*!Battle_RowBytes),X
    LDY.w !Battle_PaletteSaved+(3*!Battle_RowBytes),X
    LDA.w !Battle_PaletteSaved+(7*!Battle_RowBytes),X
    STA.w !Battle_PaletteSaved+(3*!Battle_RowBytes),X
    TYA
    STA.w !Battle_PaletteSaved+(7*!Battle_RowBytes),X
    INX
    INX
    CPX.w #!Battle_RowBytes
    BNE .colour
    DEC.b !BattleCD_FxScriptPtr         ; 16-bit: the argument pointer one byte back
    TDC
    SEP #$20
    RTL

; $D1:E77C — BattleFx_Nmi (285 bytes, $E77C–$E898)
; The battle's NMI handler while this engine runs: BattleFx_Init writes
; JML $D1:E77C into !NmiTrampoline. It saves A, X, Y, DB and DP, sets
; DP=0, turns HDMA off, reads RDNMI (acknowledging the NMI) and writes
; !Nmi_Nmitimen to NMITIMEN (NMI, the V-count IRQ, joypad read). When
; !BattleFx_IntBusy is set (the IRQ handler or an earlier NMI has not
; finished) it does nothing more. Otherwise, with !BattleFx_IntBusy set:
;   - saves DP $00-$2A to !BattleFx_NmiDpSave (MVN, which leaves DB=$7E)
;     and copies the words !Battle_HdmaScreens, !BattleFx_UnkBE8B,
;     !Battle_HdmaColour and !Battle_HdmaColData to
;     !BattleFx_UnkBE8D/8F/95/97;
;   - with DB=$00: HDMA off again, reads STAT78, forced blank (INIDISP)
;     and VMAIN = $80 (the same value), then JSL BattleCD_NmiDispatch,
;     bank $CD's NMI work (picked by !Battle_NmiMode);
;   - the rest uses .w operands in bank $7E, so it needs that call to
;     leave DB=$7E: its two handlers (BattleCD_NmiMain and
;     BattleCD_NmiSetup, through BattleCD_NmiTable) do set DB=$7E with
;     PLB on the paths looked at; not traced to every exit;
;   - unless !Battle_Paused: JSL BattleCD_ScrollStepL (the layer drift,
;     ScrollStepAccum), !Battle_FrameCount + 1, and while
;     !Battle_MsgTiming is set one frame off !Battle_MsgTimer; when
;     it reaches 0: !Battle_LastScriptMsg = $FF if !Battle_ScriptMsgUp was
;     set, then !Battle_ScriptMsgUp, !Battle_MsgShown and
;     !Battle_MsgTiming zeroed and !BattleFx_CeSetReload counted up;
;   - pause: only when !Battle_NmiMode is 1. If !Battle_2989NoPause is
;     set in !BattleFx_Unk2989Copy or !Battle_UnkCE16 is non-zero,
;     !Battle_Paused and !BattleFx_StartLatch are zeroed; otherwise a
;     new press of Start (JOY1H) sets !Battle_Paused to (it + 1) & 1
;     (bit 0 flipped, the rest cleared), and
;     !BattleFx_StartLatch holds the button until it is let go (that
;     !Battle_Paused pauses the battle is inferred from what it skips
;     here and in BattleFx_Irq);
;   - BattleFx_RestoreMathRegs;
;   - a debug slow motion, run only when !BattleRom_DebugSlowMo ($CD:3FFF)
;     is non-zero (it is 0 in this ROM): R held unpauses; while
;     !BattleFx_StartLatch is set, !BattleFx_SlowCount counts frames and
;     !Battle_Paused is 0 (run) on one frame in four if L is held, else
;     non-zero;
;   - restores DP $00-$2A, zeroes !BattleFx_IntBusy and
;     !BattleFx_FrameWait (bank $CD waits for that, probably: $CD:3E58
;     counts it up and loops until it reads 0).
; Callers note: no call site; reached through !NmiTrampoline.
; Entry: an NMI; any M, X, DP and DB (it sets M=0, X=0, then M=1, DP=0
;        and DB itself; the interrupted DP and DB are saved)
; Exit:  RTI with A, X, Y (16-bit), DB, DP and P restored; DP $00-$2A as
;        they were (restored from the save) on the path that ran
BattleFx_Nmi:
    REP #$30
    PHA
    PHX
    PHY
    PHB
    PHD
    LDA.w #$0000
    TCD
    TDC
    SEP #$20
    STA.l HDMAEN
    LDA.l RDNMI                         ; acknowledge the NMI
    LDA.b #!Nmi_Nmitimen
    STA.l NMITIMEN
    LDA.b !BattleFx_IntBusy
    BEQ .run
    JMP .done
.run:
    INC.b !BattleFx_IntBusy
    REP #$30
    ; Save DP $00-$2A (the MVN leaves DB=$7E).
    LDX.w #$0000
    LDY.w #!BattleFx_NmiDpSave
    LDA.w #!BattleFx_NmiDpSaveLen
    MVN !Bank7E,!Bank7E                ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDA.w !Battle_HdmaScreens
    STA.w !BattleFx_UnkBE8D
    LDA.w !BattleFx_UnkBE8B
    STA.w !BattleFx_UnkBE8F
    LDA.w !Battle_HdmaColour
    STA.w !BattleFx_UnkBE95
    LDA.w !Battle_HdmaColData
    STA.w !BattleFx_UnkBE97
    TDC
    SEP #$20
    PHA
    PLB
    STA.w HDMAEN
    LDA.w STAT78                        ; read only (latch reset, probably)
    LDA.b #!INIDISP_ForceBlank
    STA.w INIDISP
    STA.w VMAIN                         ; the same $80: !VMAIN_IncAfterHigh
    JSL BattleCD_NmiDispatch
    LDA.w !Battle_Paused                ; DB as BattleCD_NmiDispatch left it ($7E, see the header)
    BNE .pause_input
    JSL BattleCD_ScrollStepL
    LDX.b !Battle_FrameCount
    INX
    STX.b !Battle_FrameCount
    LDA.w !Battle_MsgTiming
    BEQ .pause_input
    DEC.w !Battle_MsgTimer
    BNE .pause_input
    LDA.w !Battle_ScriptMsgUp
    BEQ .timer_end
    LDA.b #!BattleFx_UnkCE17Set
    STA.w !Battle_LastScriptMsg
.timer_end:
    STZ.w !Battle_ScriptMsgUp
    STZ.w !Battle_MsgShown
    STZ.w !Battle_MsgTiming
    INC.w !BattleFx_CeSetReload
.pause_input:
    ; Start pauses, in mode 1 only.
    LDA.b !Battle_NmiMode
    CMP.b #$01
    BNE .start_up
    LDA.w !BattleFx_Unk2989Copy
    AND.b #!Battle_2989NoPause
    BNE .no_pause
    LDA.w !Battle_UnkCE16
    BNE .no_pause
    LDA.l JOY1H
    AND.b #!Battle_JoyStartHi
    BEQ .start_up
    LDA.w !BattleFx_StartLatch
    BNE .math
    LDA.w !Battle_Paused
    INC A
    AND.b #$01
    STA.w !Battle_Paused
    LDA.b #$01
    STA.w !BattleFx_StartLatch
    BRA .math
.no_pause:
    STZ.w !Battle_Paused
.start_up:
    STZ.w !BattleFx_StartLatch
.math:
    JSL BattleFx_RestoreMathRegs
    ; Debug slow motion (off in this ROM).
    LDA.l !BattleRom_DebugSlowMo        ; 0 in this ROM: the slow motion below never runs
    BEQ .restore_dp
    LDA.l JOY1L
    AND.b #!Battle_JoyRLo
    BEQ .slow_motion
    STZ.w !Battle_Paused
    STZ.w !BattleFx_StartLatch
    BRA .restore_dp
.slow_motion:
    LDA.w !BattleFx_StartLatch
    BEQ .restore_dp
    INC.w !BattleFx_SlowCount
    LDA.w !BattleFx_SlowCount
    AND.b #$03
    BNE .set_paused
    LDA.l JOY1L
    AND.b #!Battle_JoyLLo
    EOR.b #!Battle_JoyLLo
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
.set_paused:
    STA.w !Battle_Paused
.restore_dp:
    REP #$30
    ; Restore DP $00-$2A.
    LDX.w #!BattleFx_NmiDpSave
    LDY.w #$0000
    LDA.w #!BattleFx_NmiDpSaveLen
    MVN !Bank7E,!Bank7E                ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    TDC
    SEP #$20
    STA.b !BattleFx_IntBusy
    STA.l (!Bank7E<<16)|!BattleFx_FrameWait
.done:
    REP #$30
    PLD
    PLB
    PLY
    PLX
    PLA
    RTI

; $D1:E899 — BattleFx_WhitenRows (40 bytes, $E899–$E8C0)
; Fills background palette rows 2-7 ($2040-$20FF of
; !Battle_PaletteSavedLo and $2240-$22FF of !Battle_PaletteLiveLo) and
; OBJ palette rows 1-3 (saved and live) with !BattleFx_White ($7FFF).
; Callers note: the JSL at $CD:2A9C is followed by RTS (a bank-$CD
;   script command handler, probably; not matched).
; Callers (1 JSL site): unmatched ($CD:2A9C).
; Entry: M=1, X=0, DP=0 (TDC gives the start index 0), DB=$7E (the
;        palettes are written .w)
; Exit:  M=1, X=0, DP and DB unchanged; A = 0; X = 3*!Battle_RowBytes;
;        Y unchanged
BattleFx_WhitenRows:
    TDC
    TAX
    REP #$20
    LDA.w #!BattleFx_White
.bg_rows:
    STA.w !Battle_PaletteSavedLo+(2*!Battle_RowBytes),X
    STA.w !Battle_PaletteLiveLo+(2*!Battle_RowBytes),X
    INX
    INX
    CPX.w #6*!Battle_RowBytes
    BNE .bg_rows
    LDX.w #$0000
.obj_rows:
    STA.w !Battle_PaletteSaved+(1*!Battle_RowBytes),X
    STA.w !Battle_PaletteLive+(1*!Battle_RowBytes),X
    INX
    INX
    CPX.w #3*!Battle_RowBytes
    BNE .obj_rows
    TDC
    SEP #$20
    RTL

; $D1:E8C1 — BattleFx_WhitenObjRows5To7 (24 bytes, $E8C1–$E8D8)
; Fills OBJ palette rows 5-7 (saved and live) with !BattleFx_White.
; Callers note: the JSL at $CD:2A97 is followed by RTS (as
;   BattleFx_WhitenRows).
; Callers (1 JSL site): unmatched ($CD:2A97).
; Entry: M=1, X=0, DP=0 (TDC as 0), DB=$7E
; Exit:  M=1, X=0, DP and DB unchanged; A = 0; X = 3*!Battle_RowBytes;
;        Y unchanged
BattleFx_WhitenObjRows5To7:
    TDC
    TAX
    REP #$20
    LDA.w #!BattleFx_White
.colour:
    STA.w !Battle_PaletteSaved+(5*!Battle_RowBytes),X
    STA.w !Battle_PaletteLive+(5*!Battle_RowBytes),X
    INX
    INX
    CPX.w #3*!Battle_RowBytes
    BNE .colour
    TDC
    SEP #$20
    RTL

; $D1:E8D9 — BattleFx_UploadMapBlock (65 bytes, $E8D9–$E919)
; Sends a 16 x 16 block of map words to VRAM by DMA on channel 7:
; 16 rows of !BattleFx_MapRowBytes (32 bytes) from A:X, one after the
; other in the source, to VRAM word address DP $45, $45 + $20, $45 + $40,
; ... (each row one row of a 32-word-wide map, so the block is half a
; map's width). VMAIN is not written: the caller's setting is used.
; Callers note: the only caller, BattleCD_NmiUploadText, passes A = $7E
;   and X = !Battle_TilePageSrc (a tilemap page), DP $45 = a
;   BattleCD_TileUploadVram word.
; Callers (1 JSL site): BattleCD_NmiUploadText ($CD:0644).
; Entry: M=1, X=0 (X is stored 16-bit to A1T7L/H), A = source bank, X =
;        source address, DP $45 = the first VRAM word address (DP=0),
;        DB any (saved; set to $00 for the registers); needs vertical or
;        forced blank (not checked)
; Exit:  M=1, X=0, DP unchanged, DB restored; A = 0 (TDC with DP=0); X =
;        $0080 and Y = $0020 (set while X=1, high bytes cleared); DP $47
;        = 0 (the row count, run down 16-bit); DMA channel 7 and VMADD
;        changed
BattleFx_UploadMapBlock:
    PHB
    PHA
    LDA.b #!Bank00
    PHA
    PLB
    PLA
    STX.w A1T7L
    STA.w A1B7
    LDA.b #!DMAP_TwoRegs
    STA.w DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD7
    STZ.w DAS7H
    REP #$20
    SEP #$10
    LDY.b #!BattleFx_MapRowBytes
    LDX.b #!MDMAEN_Ch7
    LDA.w #!BattleFx_MapRows
    STA.b !BattleCD_Tmp47
    LDA.b !BattleCD_Tmp45
.row:
    STA.w VMADDL
    STY.w DAS7L                         ; 8-bit Y: DAS7L only (DAS7H zeroed above)
    STX.w MDMAEN                        ; 8-bit X: !MDMAEN_Ch7
    CLC
    ADC.w #!BattleFx_MapRowWords
    DEC.b !BattleCD_Tmp47
    BNE .row
    TDC
    SEP #$20
    REP #$10
    PLB
    RTL

; $D1:E91A — BattleFx_MoveBgRowsUp (106 bytes, $E91A–$E983)
; Moves background palette rows 2-4 to rows 5-7, with the palette
; animations that work on them:
;   - rows 2-4 of !Battle_PaletteSavedLo are copied to rows 5-7 of both
;     the saved and the live palette, then rows 2-4 of both are zeroed;
;   - FieldAnimB records 3-5 (36 bytes) are copied over records 0-2,
;     whose .Unk1 (first colour) then gets 48 added (three rows on) and
;     whose .Unk0 becomes !BattleFx_AnimKind3 ($30);
;   - !BattleFx_SavedKinds+0..2 = $30, +3..5 = 0, !BattleFx_UnkCDC8 = 0,
;     and !BattleFx_AnimsHeld is counted up, so that the next
;     BattleFx_HoldAnimsTick with !BattleFx_HoldAnims clear puts those
;     kinds back (records 0-2 running, 3-5 stopped).
; Callers note: the JSL at $CD:2AA5 is followed by RTS (a bank-$CD
;   script command handler, probably; not matched).
; Callers (1 JSL site): unmatched ($CD:2AA5).
; Entry: M=1, X=0, DP=0 (TDC as 0), DB=$7E
; Exit:  M=1, X=0, DP and DB unchanged; A = !BattleFx_AnimKind3; X =
;        3*!FieldAnimB_Size; Y unchanged
BattleFx_MoveBgRowsUp:
    REP #$20
    TDC
    TAX
.colour:
    LDA.w !Battle_PaletteSavedLo+(2*!Battle_RowBytes),X
    STA.w !Battle_PaletteSavedLo+(5*!Battle_RowBytes),X
    STA.w !Battle_PaletteLiveLo+(5*!Battle_RowBytes),X
    STZ.w !Battle_PaletteSavedLo+(2*!Battle_RowBytes),X
    STZ.w !Battle_PaletteLiveLo+(2*!Battle_RowBytes),X
    INX
    INX
    CPX.w #3*!Battle_RowBytes
    BNE .colour
    TDC
    SEP #$20
    TDC
    TAX
.anim_byte:
    LDA.w FieldAnimB[3].Unk0,X
    STA.w FieldAnimB[0].Unk0,X
    INX
    CPX.w #3*!FieldAnimB_Size
    BNE .anim_byte
    LDA.w FieldAnimB[0].Unk1
    CLC
    ADC.b #3*!Battle_ColoursPerRow
    STA.w FieldAnimB[0].Unk1
    LDA.w FieldAnimB[1].Unk1
    CLC
    ADC.b #3*!Battle_ColoursPerRow
    STA.w FieldAnimB[1].Unk1
    LDA.w FieldAnimB[2].Unk1
    CLC
    ADC.b #3*!Battle_ColoursPerRow
    STA.w FieldAnimB[2].Unk1
    LDA.b #!BattleFx_AnimKind3
    STA.w FieldAnimB[0].Unk0
    STA.w FieldAnimB[1].Unk0
    STA.w FieldAnimB[2].Unk0
    STA.w !BattleFx_SavedKinds
    STA.w !BattleFx_SavedKinds+1
    STA.w !BattleFx_SavedKinds+2
    STZ.w !BattleFx_SavedKinds+3
    STZ.w !BattleFx_SavedKinds+4
    STZ.w !BattleFx_SavedKinds+5
    STZ.w !BattleFx_UnkCDC8
    INC.w !BattleFx_AnimsHeld
    RTL

; $D1:E984 — BattleFx_LoadBgRows2To4 (107 bytes, $E984–$E9EE)
; Counts up !BattleFx_UnkCDC8 and !Battle_CgramPending, loads background
; palette rows 2-4 (saved and live) from !BattleRom_BgRows2To4 ($D0:FD00,
; 48 colours), copies FieldAnimB records 0-2 over records 3-5 and moves
; those back three rows (.Unk1 - 48), sets their .Unk4/.Unk5 to 0/1 and
; their .Unk0 to !BattleFx_AnimKind3, sets !BattleFx_SavedKinds+3..5 to
; $30 and counts up !BattleFx_AnimsHeld (see BattleFx_MoveBgRowsUp,
; whose records 0-2 this copies back).
; Callers note: the JSL at $CD:2AAA is followed by RTS (a bank-$CD
;   script command handler, probably; not matched).
; Callers (1 JSL site): unmatched ($CD:2AAA).
; Entry: M=1, X=0, DP=0 (TDC as 0), DB=$7E
; Exit:  M=1, X=0, DP and DB unchanged; A = !BattleFx_AnimKind3; X =
;        !BattleFx_AnimUnk4Init ($0100); Y unchanged
BattleFx_LoadBgRows2To4:
    INC.w !BattleFx_UnkCDC8
    INC.w !Battle_CgramPending
    REP #$20
    TDC
    TAX
.colour:
    LDA.l !BattleRom_BgRows2To4,X
    STA.w !Battle_PaletteSavedLo+(2*!Battle_RowBytes),X
    STA.w !Battle_PaletteLiveLo+(2*!Battle_RowBytes),X
    INX
    INX
    CPX.w #3*!Battle_RowBytes
    BNE .colour
    TDC
    SEP #$20
    TDC
    TAX
.anim_byte:
    LDA.w FieldAnimB[0].Unk0,X
    STA.w FieldAnimB[3].Unk0,X
    INX
    CPX.w #3*!FieldAnimB_Size
    BNE .anim_byte
    LDA.w FieldAnimB[3].Unk1
    SEC
    SBC.b #3*!Battle_ColoursPerRow
    STA.w FieldAnimB[3].Unk1
    LDA.w FieldAnimB[4].Unk1
    SEC
    SBC.b #3*!Battle_ColoursPerRow
    STA.w FieldAnimB[4].Unk1
    LDA.w FieldAnimB[5].Unk1
    SEC
    SBC.b #3*!Battle_ColoursPerRow
    STA.w FieldAnimB[5].Unk1
    LDX.w #!BattleFx_AnimUnk4Init
    STX.w FieldAnimB[3].Unk4
    STX.w FieldAnimB[4].Unk4
    STX.w FieldAnimB[5].Unk4
    LDA.b #!BattleFx_AnimKind3
    STA.w FieldAnimB[3].Unk0
    STA.w FieldAnimB[4].Unk0
    STA.w FieldAnimB[5].Unk0
    STA.w !BattleFx_SavedKinds+3
    STA.w !BattleFx_SavedKinds+4
    STA.w !BattleFx_SavedKinds+5
    INC.w !BattleFx_AnimsHeld
    RTL

; $D1:E9EF — BattleFx_GradLevelOfs (18 bytes, $E9EF–$EA00)
; Byte offset into !BattleRom_GradColours of the 14 colours of each
; gradient level 0-8 (BattleFx_HpGradientTick indexes it with the level
; * 2). Level 8 (the one BattleFx_Init starts at) is offset 0, the first
; set; levels 0-7 use the other eight sets ($20 bytes each) in the order
; listed.
BattleFx_GradLevelOfs:
    dw $00A0, $0100, $00C0, $0080, $00E0, $0060, $0040, $0020, $0000  ; levels 0-8

; $D1:EA01 — BattleFx_FindGradStart (32 bytes, $EA01–$EA20)
; Looks for the first colour of !BattleRom_GradColours among colours
; 1-14 of saved background palette row 5 and stores the colour number
; less 1 (0-13) to !BattleFx_GradStart; 0 when none matches.
; BattleFx_HpGradientTick uses it to pick the rotation of the gradient
; (BattleFx_GradRotA/B/C).
; Callers (1 JSR site): BattleFx_Init ($D1:F2D5).
; Entry: M=1, X=0, DP=0 (TDC as 0), DB=$7E
; Exit:  M=1, X=0, DP and DB unchanged; A = Y = the stored value (B = 0);
;        X = the value * 2, or !BattleFx_GradBytes when none matched
BattleFx_FindGradStart:
    TDC
    TAX
    TAY
    REP #$20
.colour:
    LDA.l !BattleRom_GradColours
    CMP.w !Battle_PaletteSavedLo+(5*!Battle_RowBytes)+2,X
    BEQ .store
    INY
    INX
    INX
    CPX.w #!BattleFx_GradBytes
    BNE .colour
    TDC
    TAY
.store:
    TDC
    SEP #$20
    TYA
    STA.w !BattleFx_GradStart
    RTS

; ============================================================
; The HP-driven background gradient ($D1:EA21–$D1:EBFE)
; ============================================================

; $D1:EA21 — BattleFx_GradRotA (14 bytes, $EA21–$EA2E)
; Three rotation tables of BattleFx_HpGradientTick, indexed by
; !BattleFx_GradStart (0-13): the rotation of background row 5 (A), 6
; (B) and 7 (C). The gradient colour a row shows at colour 1 is this
; value with !BattleFx_GradRotRaw set, else 14 minus it
; (BattleFx_GradRotation). Each table is the list 0-13 started at a
; different point (A at 0, B at 4, C at 10), so the three rows show the
; same 14 colours rotated against each other.
BattleFx_GradRotA:
    db $00,$01,$02,$03,$04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D

; $D1:EA2F — BattleFx_GradRotB (14 bytes, $EA2F–$EA3C)
; Row 6's start (see BattleFx_GradRotA).
BattleFx_GradRotB:
    db $04,$05,$06,$07,$08,$09,$0A,$0B,$0C,$0D,$00,$01,$02,$03

; $D1:EA3D — BattleFx_GradRotC (14 bytes, $EA3D–$EA4A)
; Row 7's start (see BattleFx_GradRotA).
BattleFx_GradRotC:
    db $0A,$0B,$0C,$0D,$00,$01,$02,$03,$04,$05,$06,$07,$08,$09

; $D1:EA4B — BattleFx_HpGradientTick (389 bytes, $EA4B–$EBCF)
; One step of a background colour gradient that follows the HP of
; battler slot 3 (the first enemy). Bank $CD's NMI work calls it on the
; frames where (!Battle_FrameCount & !BattleFx_GradTickMask) is 0
; (every 8th frame with the mask's set-up value 7). It returns at once
; while !Battle_Unk5D9B or .Unk0 of any of FieldAnimB records 8-11 is
; non-zero.
;   - Not fading (!BattleFx_GradFading = 0): the level is 1 + the number
;     of times BattlerStats[3].MaxHp / 8 fits into .CurHp, at most 8, or
;     the low 7 bits of !BattleFx_GradForce when its bit 7 is set. It is
;     stored to !BattleFx_GradLevel. When it differs from
;     !BattleFx_GradShown a fade of !BattleFx_GradFadeSteps (32) steps
;     starts: !BattleFx_GradColours gets the 14 colours of the level
;     shown, and !BattleFx_GradShown moves to the new level (when forced)
;     or one level toward it (and !BattleFx_GradLevel with it).
;   - Fading: each of the 14 colours moves one unit per channel (red,
;     green, blue) toward the colours of !BattleFx_GradLevel
;     (!BattleRom_GradColours + BattleFx_GradLevelOfs), the fade ends
;     after its steps, the colours are copied once more after themselves
;     (so a rotated read can run past the end), and colours 1-14 of
;     background rows 5, 6 and 7 (saved and live) get them, rotated by
;     BattleFx_GradRotA/B/C at !BattleFx_GradStart (or 14 minus that when
;     !BattleFx_GradRotRaw is 0).
; That it is a background sky that changes with a boss's HP is a guess
; from the reads; which battles use it is not traced.
; Callers note: the JSL at $CD:0985 is in BattleCD_NmiMain, with
;   !Battle_Unk2A21 bit 0 set, on the frames where !Battle_FrameCount AND
;   !BattleFx_GradTickMask is 0.
; Callers (1 JSL site): BattleCD_NmiMain ($CD:0985).
; Entry: M=1, X=0, DP=0 (DP $45/$47 scratch, TDC as 0), DB=$7E; B (A's
;        high byte) = 0 assumed on the fading path, whose first TAX
;        takes it in (not traced at the caller; the other TAXs follow a
;        TDC)
; Exit:  M=1, X=0, DP and DB unchanged; A, X and Y clobbered (X and Y
;        unchanged on the first early return; A clobbered, holding the
;        non-zero OR of the flags read); DP $45-$48 written
BattleFx_HpGradientTick:
    LDA.w !Battle_Unk5D9B
    ORA.w FieldAnimB[11].Unk0           ; palette animations 8-11 running?
    ORA.w FieldAnimB[10].Unk0
    ORA.w FieldAnimB[9].Unk0
    ORA.w FieldAnimB[8].Unk0
    BEQ .idle
    RTL
.idle:
    LDA.w !BattleFx_GradFading
    BNE .fade
    JMP .pick_level
.fade:
    LDA.w !BattleFx_GradLevel
    ASL A
    TAX
    REP #$20
    LDA.l BattleFx_GradLevelOfs,X
    TAX
    TDC
    TAY
    SEP #$20
.colour:
    LDA.l !BattleRom_GradColours,X
    AND.b #!BattleFx_RedMask
    STA.b !BattleCD_Tmp45
    LDA.w !BattleFx_GradColours,Y
    AND.b #!BattleFx_RedMask
    CMP.b !BattleCD_Tmp45
    BEQ .green
    BCC .red_up
    LDA.w !BattleFx_GradColours,Y
    DEC A
    STA.w !BattleFx_GradColours,Y
    BRA .green
.red_up:
    LDA.w !BattleFx_GradColours,Y
    INC A
    STA.w !BattleFx_GradColours,Y
.green:
    REP #$20
    LDA.l !BattleRom_GradColours,X
    AND.w #!BattleFx_GreenMask
    STA.b !BattleCD_Tmp45
    LDA.w !BattleFx_GradColours,Y
    AND.w #!BattleFx_GreenMask
    CMP.b !BattleCD_Tmp45
    BEQ .blue
    BCC .green_up
    LDA.w !BattleFx_GradColours,Y
    SEC
    SBC.w #!BattleFx_GreenStep
    STA.w !BattleFx_GradColours,Y
    BRA .blue
.green_up:
    LDA.w !BattleFx_GradColours,Y
    CLC
    ADC.w #!BattleFx_GreenStep
    STA.w !BattleFx_GradColours,Y
.blue:
    TDC
    SEP #$20
    LDA.l !BattleRom_GradColours+1,X
    AND.b #!BattleFx_BlueMaskHi
    STA.b !BattleCD_Tmp45
    LDA.w !BattleFx_GradColours+1,Y
    AND.b #!BattleFx_BlueMaskHi
    CMP.b !BattleCD_Tmp45
    BEQ .next_colour
    BCC .blue_up
    LDA.w !BattleFx_GradColours+1,Y
    SEC
    SBC.b #$04
    STA.w !BattleFx_GradColours+1,Y
    BRA .next_colour
.blue_up:
    LDA.w !BattleFx_GradColours+1,Y
    CLC
    ADC.b #$04
    STA.w !BattleFx_GradColours+1,Y
.next_colour:
    INY
    INY
    INX
    INX
    CPY.w #!BattleFx_GradBytes
    BEQ .faded
    JMP .colour
.faded:
    TDC
    SEP #$20
    DEC.w !BattleFx_GradSteps
    BNE .copy
    STZ.w !BattleFx_GradFading
.copy:
    TDC
    TAX
    REP #$20
.copy_word:
    LDA.w !BattleFx_GradColours,X
    STA.w !BattleFx_GradColours+!BattleFx_GradBytes,X
    INX
    INX
    CPX.w #!BattleFx_GradBytes
    BNE .copy_word
    TDC
    SEP #$20
    LDA.w !BattleFx_GradStart
    TAX
    LDA.l BattleFx_GradRotA,X
    STA.b !BattleCD_Tmp45
    LDY.w #$0000
    JSR BattleFx_GradRotation
    JSR BattleFx_GradWriteRow
    LDA.l BattleFx_GradRotB,X
    STA.b !BattleCD_Tmp45
    LDY.w #!Battle_RowBytes
    JSR BattleFx_GradRotation
    JSR BattleFx_GradWriteRow
    LDA.l BattleFx_GradRotC,X
    STA.b !BattleCD_Tmp45
    LDY.w #2*!Battle_RowBytes
    JSR BattleFx_GradRotation
    JSR BattleFx_GradWriteRow
    RTL
.pick_level:
    LDX.w #$0001
    REP #$20
    LDA.w BattlerStats[3].MaxHp
    LSR A
    LSR A
    LSR A
    STA.b !BattleCD_Tmp45
    STA.b !BattleCD_Tmp47
.count:
    LDA.w BattlerStats[3].CurHp
    CMP.b !BattleCD_Tmp45
    BCC .counted
    LDA.b !BattleCD_Tmp45
    CLC
    ADC.b !BattleCD_Tmp47
    STA.b !BattleCD_Tmp45
    INX
    CPX.w #$0008
    BNE .count
.counted:
    TDC
    SEP #$20
    LDA.w !BattleFx_GradForce
    BPL .have_level
    AND.b #!BattleFx_GradForceLevel
    TAX
.have_level:
    TXA
    STA.w !BattleFx_GradLevel
    CMP.w !BattleFx_GradShown
    BEQ .done
    INC.w !BattleFx_GradFading
    LDA.b #!BattleFx_GradFadeSteps
    STA.w !BattleFx_GradSteps
    LDA.w !BattleFx_GradShown
    ASL A
    TAX
    LDA.w !BattleFx_GradForce
    BPL .step
    LDA.w !BattleFx_GradLevel
    STA.w !BattleFx_GradShown
    BRA .load_shown
.step:
    LDA.w !BattleFx_GradLevel
    CMP.w !BattleFx_GradShown
    BCC .step_down
    INC.w !BattleFx_GradShown
    BRA .stepped
.step_down:
    DEC.w !BattleFx_GradShown
.stepped:
    LDA.w !BattleFx_GradShown
    STA.w !BattleFx_GradLevel
.load_shown:
    TDC
    TAY
    REP #$20
    LDA.l BattleFx_GradLevelOfs,X
    TAX
.load_colour:
    LDA.l !BattleRom_GradColours,X
    STA.w !BattleFx_GradColours,Y
    INX
    INX
    INY
    INY
    CPY.w #!BattleFx_GradBytes
    BNE .load_colour
    TDC
    SEP #$20
.done:
    RTL

; $D1:EBD0 — BattleFx_GradRotation (15 bytes, $EBD0–$EBDE)
; A = DP $45 (a row's rotation from BattleFx_GradRotA/B/C) when
; !BattleFx_GradRotRaw is non-zero, else !BattleFx_GradCount - DP $45.
; Callers (3 JSR sites): BattleFx_HpGradientTick ($D1:EB27, $D1:EB36, $D1:EB45).
; Entry: M=1, DP=0, DB=$7E (BattleFx_HpGradientTick's state)
; Exit:  M=1; A = the rotation (B unchanged); X, Y unchanged
BattleFx_GradRotation:
    LDA.w !BattleFx_GradRotRaw
    BEQ .reversed
    LDA.b !BattleCD_Tmp45
    BRA .done
.reversed:
    LDA.b #!BattleFx_GradCount
    SEC
    SBC.b !BattleCD_Tmp45
.done:
    RTS

; $D1:EBDF — BattleFx_GradWriteRow (32 bytes, $EBDF–$EBFE)
; Writes the 14 colours !BattleFx_GradColours + A * 2 on to colours 1-14
; of the background palette row at Y ($20 per row, from row 5), in the
; saved and the live palette.
; Callers (3 JSR sites): BattleFx_HpGradientTick ($D1:EB2A, $D1:EB39, $D1:EB48).
; Entry: M=1, X=0, A = the rotation (0-14), B = 0 (A is shifted 16-bit;
;        BattleFx_HpGradientTick's TDC leaves it 0), Y = 0, $20 or $40,
;        DP=0 (DP $45 counter), DB=$7E
; Exit:  M=1, X=0 (X restored by PLX); A = 0; Y + $1C; DP $45 = 0
BattleFx_GradWriteRow:
    PHX
    REP #$20
    ASL A
    TAX
    LDA.w #!BattleFx_GradCount
    STA.b !BattleCD_Tmp45
.colour:
    LDA.w !BattleFx_GradColours,X
    STA.w !Battle_PaletteSavedLo+(5*!Battle_RowBytes)+2,Y
    STA.w !Battle_PaletteLiveLo+(5*!Battle_RowBytes)+2,Y
    INX
    INX
    INY
    INY
    DEC.b !BattleCD_Tmp45
    BNE .colour
    TDC
    SEP #$20
    PLX
    RTS

; ============================================================
; A swaying beam, background sets, bands and wave windows
; ($D1:EBFF–$D1:F1AF)
; ============================================================

; $D1:EBFF — BattleFx_SwayQuad (96 bytes, $EBFF–$EC5E)
; Fills quad X (X = the argument byte) of !BattleFx_Quads and draws it:
; a beam from the top of the screen down to the point in
; !Battle_ActCalcResult. Its top edge runs from x = $B0 + s to $B0 + s +
; $20 on line 0, where s = !BattleFx_SwayAmp (40) x the sine of the low
; byte of !Battle_FrameCount (!BattleRom_AbsSine, negated for angles
; $80-$FF, so s sways between -39 and 39); its bottom edge runs from the
; point's x - $10 to x + $10 on the point's line. Then BattleFx_DrawQuad.
; Callers note: the JSL at $CD:1805 is followed by RTS (a bank-$CD
;   script command handler, probably; not matched).
; Callers (1 JSL site): unmatched ($CD:1805).
; Entry: M=1, X=0, DP=0 (DP $40 long pointer to the argument, DP $7C),
;        DB=$7E; B (A's high byte) = 0 assumed: the two TAX copy it into
;        X (not traced at the bank-$CD caller)
; Exit:  as BattleFx_DrawQuad (X = the argument)
BattleFx_SwayQuad:
    LDA.b #!BattleFx_SwayAmp
    STA.l WRMPYA
    LDA.b !Battle_FrameCount
    BMI .negative
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYB
    NOP                                 ; wait for the multiply
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.l RDMPYH
    BRA .store
.negative:
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYB
    NOP                                 ; wait for the multiply
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.l RDMPYH
    EOR.b #!Battle_Invert8
    INC A
.store:
    CLC
    ADC.b #!BattleFx_SwayLeft
    STA.w !BattleFx_Quads,X
    STZ.w !BattleFx_Quads+2,X
    CLC
    ADC.b #!BattleFx_SwaySize
    STA.w !BattleFx_Quads+4,X
    STZ.w !BattleFx_Quads+6,X
    LDA.w !Battle_ActCalcResult
    SEC
    SBC.b #!BattleFx_SwayHalf
    STA.w !BattleFx_Quads+8,X
    CLC
    ADC.b #!BattleFx_SwaySize
    STA.w !BattleFx_Quads+12,X
    LDA.w !Battle_ActCalcResult+1
    STA.w !BattleFx_Quads+10,X
    STA.w !BattleFx_Quads+14,X
    JSL BattleFx_DrawQuad
    RTL

; $D1:EC5F — BattleFx_UnkTableEC5F (112 bytes, $EC5F–$ECCE)
; 4-byte entries read by bank $CD (not matched): $CD:1EFE loads bytes 0,
; 1 and 2 of entry (A * 4 + DP $4F) into $7E:CB06, $CB08 and (plus DP
; $51) $CB0A. Nothing in bank $D1 reads it; its meaning is not traced.
; Shown as 7 rows of 4 entries.
BattleFx_UnkTableEC5F:
    db $00,$B7,$00,$00,$40,$25,$25,$00,$C0,$25,$25,$00,$00,$00,$00,$00
    db $00,$E3,$00,$00,$19,$0E,$0F,$00,$E7,$0E,$0F,$00,$00,$00,$00,$00
    db $00,$DC,$00,$00,$20,$12,$13,$00,$E0,$12,$13,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$F8,$73,$00,$00,$08,$73,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$F8,$73,$00,$00,$08,$73,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$FC,$7E,$00,$00,$04,$7E,$00,$00,$00,$00,$00,$00
    db $00,$00,$00,$00,$FC,$7E,$00,$00,$04,$7E,$00,$00,$00,$00,$00,$00

; $D1:ECCF — BattleFx_BgSetPalOfs (12 bytes, $ECCF–$ECDA)
; Per background set 0-5 (BattleFx_LoadBgSet, index = set * 2): byte
; offset into !BattleRom_BgSetPalettes of the set's three palette rows
; ($60 bytes). Sets 4 and 5 share one.
BattleFx_BgSetPalOfs:
    dw $0000, $0060, $00C0, $0120, $0180, $0180  ; sets 0-5

; $D1:ECDB — BattleFx_BgSetPacks (24 bytes, $ECDB–$ECF2)
; Per background set 0-5 (BattleFx_LoadBgSet, index = set * 4): the four
; graphics pack ids (!LocGfx_PackPtrs entries) unpacked to VRAM $2000,
; $2800, $3000 and $3800 (words); !BattleFx_BgPackNone ($FF) skips a
; slot. Set 5 has all four $FF.
BattleFx_BgSetPacks:
    db $6D,$5B,$5D,$5E  ; set 0
    db $76,$77,$78,$79  ; set 1
    db $22,$23,$24,$26  ; set 2
    db $7E,$82,$83,$85  ; set 3
    db $4A,$4B,$4C,$4D  ; set 4
    db $FF,$FF,$FF,$FF  ; set 5

; $D1:ECF3 — BattleFx_LoadBgSet (218 bytes, $ECF3–$EDCC)
; Loads background set A (0-5): with !BattleFx_BgLoading set meanwhile,
; for each of the set's four entries in BattleFx_BgSetPacks that is not
; !BattleFx_BgPackNone, unpacks that graphics pack (!LocGfx_PackPtrs)
; to $7E:D000 (Decomp_ToWramVec) and queues its !BattleFx_BgPackBytes to
; VRAM word $2000, $2800, $3000 or $3800 (by slot; BattleCD_Unk3ECE);
; then copies the set's three palette rows (!BattleRom_BgSetPalettes +
; BattleFx_BgSetPalOfs) to saved background rows 2-4 (not the live
; ones), and unpacks the set's map (!BattleRom_BgMapPtrs, 3 bytes per
; set) to $7E:D000 and queues !BattleFx_BgMapBytes of it to VRAM word
; $6800. "Background" is inferred from the tiles plus map plus palette.
; Callers note: the only caller, BattleCD_FrameTick, passes A =
;   !Battle_UnkCD45 when !BattleFx_BgRequest is set and
;   !BattleFx_BgLoading is clear, and zeroes !BattleFx_BgRequest after it.
; Callers (1 JSL site): BattleCD_FrameTick ($CD:04D4).
; Entry: M=1, X=0, A = the set, B = 0 assumed (A * 4 and the first pack
;        id * 3 are formed 16-bit; not traced at the caller), DP=0 (DP
;        $53 is the upload size), DB=$7E (the Decomp_ToWramVec block at
;        $0300 and the variables are written .w)
; Exit:  M=1, X=0, DP and DB unchanged; A, X and Y clobbered (as
;        BattleCD_Unk3ECE leaves them; not analysed);
;        !BattleFx_BgLoading = 0; !BattleFx_BgSet = the set; DP $53 =
;        !BattleFx_BgMapBytes
BattleFx_LoadBgSet:
    INC.w !BattleFx_BgLoading
    STA.w !BattleFx_BgSet
    ASL A
    ASL A
    TAX
    STX.w !BattleFx_BgPackIdx
    LDX.w #!BattleFx_BgTilesVram
    STX.w !BattleFx_BgPackVram
    STZ.w !BattleFx_BgPackCount
.pack:
    LDX.w !BattleFx_BgPackIdx
    LDA.l BattleFx_BgSetPacks,X
    CMP.b #!BattleFx_BgPackNone
    BEQ .next_pack
    REP #$20
    STA.b !BattleFx_UploadBytes
    ASL A
    CLC
    ADC.b !BattleFx_UploadBytes
    TAX
    LDA.l !LocGfx_PackPtrs,X
    STA.w !Decomp_Src
    LDA.w #!BattleFx_DecompBuf
    STA.w !Decomp_Dest
    TDC
    SEP #$20
    LDA.l !LocGfx_PackPtrs+2,X
    STA.w !Decomp_SrcBank
    LDA.b #!Bank7E
    STA.w !Decomp_DestBank
    JSL Decomp_ToWramVec
    LDX.w #!BattleFx_BgPackBytes
    STX.b !BattleFx_UploadBytes
    LDY.w !BattleFx_BgPackVram
    LDX.w #!BattleFx_DecompBuf
    LDA.b #!Bank7E
    JSL BattleCD_Unk3ECE
.next_pack:
    REP #$20
    LDA.w !BattleFx_BgPackVram
    CLC
    ADC.w #!BattleFx_BgPackWords
    STA.w !BattleFx_BgPackVram
    INC.w !BattleFx_BgPackIdx
    TDC
    SEP #$20
    INC.w !BattleFx_BgPackCount
    LDA.w !BattleFx_BgPackCount
    CMP.b #$04
    BNE .pack
    LDA.w !BattleFx_BgSet
    ASL A
    TAX
    TDC
    TAY
    REP #$20
    LDA.l BattleFx_BgSetPalOfs,X
    TAX
.colour:
    LDA.l !BattleRom_BgSetPalettes,X
    STA.w !Battle_PaletteSavedLo+(2*!Battle_RowBytes),Y
    INX
    INX
    INY
    INY
    CPY.w #3*!Battle_RowBytes
    BNE .colour
    TDC
    SEP #$20
    LDA.w !BattleFx_BgSet
    STA.b !BattleFx_UploadBytes
    ASL A
    CLC
    ADC.b !BattleFx_UploadBytes
    TAX
    LDA.l !BattleRom_BgMapPtrs,X
    STA.w !Decomp_Src
    LDA.l !BattleRom_BgMapPtrs+1,X
    STA.w !Decomp_Src+1
    LDA.l !BattleRom_BgMapPtrs+2,X
    STA.w !Decomp_SrcBank
    LDX.w #!BattleFx_DecompBuf
    STX.w !Decomp_Dest
    LDA.b #!Bank7E
    STA.w !Decomp_DestBank
    JSL Decomp_ToWramVec
    LDX.w #!BattleFx_BgMapBytes
    STX.b !BattleFx_UploadBytes
    LDY.w #!BattleFx_BgMapVram
    LDX.w #!BattleFx_DecompBuf
    LDA.b #!Bank7E
    JSL BattleCD_Unk3ECE
    STZ.w !BattleFx_BgLoading
    RTL

; $D1:EDCD — BattleFx_GrowBand (204 bytes, $EDCD–$EE98)
; Draws a band around the point in !Battle_ActCalcResult into the window
; table of this frame (!BattleFx_WinTable1 when bit 0 of
; !Battle_FrameCount is set, else !BattleFx_WinTable0), one step wider
; per call. The argument byte picks the kind:
;   - 0: a column. Left = point x - !BattleFx_CountA (at least 0), right
;     = point x + !BattleFx_CountA (at most 255); the first pair of every
;     line 0-211 is set to them. !BattleFx_CountA counts up to 8.
;   - non-zero: a row. Lines point y - !BattleFx_CountB (at least 0) up
;     to point y + !BattleFx_CountB (at most !BattleFx_WinLines, 212),
;     not including the last, get !BattleFx_WinFull in their second pair
;     (left 0, right 255); nothing when the two meet.
;     !BattleFx_CountB counts up to !BattleFx_BandRowsMax (9).
; Callers note: the JSL at $CD:1850 is followed by RTS (a bank-$CD
;   script command handler, probably; not matched).
; Callers (1 JSL site): unmatched ($CD:1850).
; Entry: M=1, X=0, DP=0 (DP $40 long pointer to the argument), DB=$7E
; Exit:  M=1, X=0, DP and DB unchanged; A = 0; X clobbered; Y unchanged;
;        DP $45/$46 written
BattleFx_GrowBand:
    LDA.b [!BattleCD_FxScriptPtr]
    BNE .rows
    LDA.w !Battle_ActCalcResult
    SEC
    SBC.w !BattleFx_CountA
    BCS .left_ok
    TDC
.left_ok:
    STA.b !BattleCD_Tmp45
    LDA.w !Battle_ActCalcResult
    CLC
    ADC.w !BattleFx_CountA
    BCC .right_ok
    LDA.b #!WH_RightEdge
.right_ok:
    STA.b !BattleFx_Tmp46
    LDA.w !BattleFx_CountA
    CMP.b #$08
    BCS .fill_columns
    INC.w !BattleFx_CountA
.fill_columns:
    TDC
    TAX
    REP #$20
    LDA.b !Battle_FrameCount
    AND.w #$0001
    BEQ .buffer0
    LDA.b !BattleCD_Tmp45
.column_buf1:
    STA.w !BattleFx_WinTable1,X
    STA.w !BattleFx_WinTable1+212,X
    STA.w !BattleFx_WinTable1+424,X
    STA.w !BattleFx_WinTable1+636,X
    INX
    INX
    INX
    INX
    CPX.w #!BattleFx_WinQuarterBytes
    BNE .column_buf1
    BRA .done
.buffer0:
    LDA.b !BattleCD_Tmp45
.column_buf0:
    STA.w !BattleFx_WinTable0,X
    STA.w !BattleFx_WinTable0+212,X
    STA.w !BattleFx_WinTable0+424,X
    STA.w !BattleFx_WinTable0+636,X
    INX
    INX
    INX
    INX
    CPX.w #!BattleFx_WinQuarterBytes
    BNE .column_buf0
.done:
    TDC
    SEP #$20
    RTL
.rows:
    LDA.w !Battle_ActCalcResult+1
    SEC
    SBC.w !BattleFx_CountB
    BCS .top_ok
    TDC
.top_ok:
    STA.b !BattleCD_Tmp45
    LDA.w !Battle_ActCalcResult+1
    CLC
    ADC.w !BattleFx_CountB
    BCS .clamp_bottom
    CMP.b #!BattleFx_WinLines
    BCC .bottom_ok
.clamp_bottom:
    LDA.b #!BattleFx_WinLines
.bottom_ok:
    STA.b !BattleFx_Tmp46
    LDA.w !BattleFx_CountB
    CMP.b #!BattleFx_BandRowsMax
    BCS .fill_rows
    INC.w !BattleFx_CountB
.fill_rows:
    TDC
    TAX
    LDA.b !BattleCD_Tmp45
    REP #$20
    ASL A
    ASL A
    TAX
    LDA.b !BattleFx_Tmp46
    AND.w #!Battle_LowByteMask
    ASL A
    ASL A
    STA.b !BattleCD_Tmp45
    CPX.b !BattleCD_Tmp45
    BEQ .rows_done
    LDA.b !Battle_FrameCount
    AND.w #$0001
    BEQ .rows_buf0
    LDA.w #!BattleFx_WinFull
.row_buf1:
    STA.w !BattleFx_WinTable1+2,X
    INX
    INX
    INX
    INX
    CPX.b !BattleCD_Tmp45
    BNE .row_buf1
    BRA .rows_done
.rows_buf0:
    LDA.w #!BattleFx_WinFull
.row_buf0:
    STA.w !BattleFx_WinTable0+2,X
    INX
    INX
    INX
    INX
    CPX.b !BattleCD_Tmp45
    BNE .row_buf0
.rows_done:
    TDC
    SEP #$20
    RTL

; $D1:EE99 — BattleFx_MsgSfx (12 bytes, $EE99–$EEA4)
; 1 byte per battle message: the sound BattleCD_ShowMessage plays for it
; (through BattleCD_ApuCmd18, unless !BattleCD_MsgNoSfx, $FF). Nothing in
; bank $D1 reads it.
BattleFx_MsgSfx:
    db $FF,$FF,$FF,$FF,$89,$88,$88,$88,$FF,$FF,$FF,$FF

; $D1:EEA5 — BattleFx_RampWin2 (31 bytes, $EEA5–$EEC3)
; With n = !BattleFx_RampBottom ($C0) - !BattleFx_CountA (an 8-bit
; subtraction, so n is 0-255), stores the words 0, 1, 2, ... to
; !BattleFx_WinTable0-2 + 4n, + 4(n-1), ... down to + 0, i.e. to the
; second pair of line n-1, n-2, ... up to the line before line 0 (the
; bytes just before the table): left edges 0, 1, 2, ... going up, right
; edges 0. Then counts !BattleFx_CountA up. Always table 0, whatever the
; frame.
; Quirks: the BMI after TAY looks like a guard for n < 0, but with B = 0
; n * 4 is at most $3FC and it never fires (only bit 5 of B set would
; make it). Once !BattleFx_CountA passes $C0, n wraps (CountA $C1-$DF
; gives n $FF-$E1) and the loop writes past the end of the $380-byte
; table into !BattleFx_WinTable1 (up to $7E:C55C). The final INC.w runs
; with M=0, so a !BattleFx_CountA of $FF carries into !BattleFx_CountB
; ($CD3B).
; Callers note: the JSL at $CD:185A is followed by RTS (a bank-$CD
;   script command handler, probably; not matched).
; Callers (1 JSL site): unmatched ($CD:185A).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 assumed (n * 4 is formed 16-bit
;        after the 8-bit subtraction; not traced at the caller)
; Exit:  M=1, X=0, DP and DB unchanged; A = 0; X unchanged; Y clobbered;
;        the word at !BattleFx_CountA incremented
BattleFx_RampWin2:
    LDA.b #!BattleFx_RampBottom
    SEC
    SBC.w !BattleFx_CountA
    REP #$20
    ASL A
    ASL A
    TAY
    BMI .done
    TDC
.line:
    STA.w !BattleFx_WinTable0-2,Y
    INC A
    DEY
    DEY
    DEY
    DEY
    BPL .line
.done:
    INC.w !BattleFx_CountA
    TDC
    SEP #$20
    RTL

; $D1:EEC4 — BattleFx_WaveWindowA (159 bytes, $EEC4–$EF62)
; Writes wavy edges into !BattleFx_WinTable0, two lines at a time, for
; Y = 0 to !BattleFx_WinUsedBytes - 8 in steps of 8 (the pairs at
; !BattleFx_WinTable0-4 + Y and + Y: the line before line 0 to line 210).
; !BattleFx_CountA grows by the argument byte; r1 = !BattleFx_WaveRadius
; ($60) - !BattleFx_CountA and r2 = r1 / 2. Two angles start at
; !Battle_FrameCount * 2 and * 4 (low bytes) and count up once per
; step. For each step:
;   - first pair: the word at !BattleFx_WaveBaseX + Y ($7E:E500 + Y)
;     plus r1 x the sine of the first angle (BattleFx_WaveLeftA);
;   - second pair: r2 x the sine of the second angle plus (!BattleFx_ShakeY
;     + !BattleFx_BounceOut) (BattleFx_WaveRight).
; The sines are !BattleRom_AbsSine x the radius / 256, negated for
; angles $80-$FF. Who fills $7E:E500 is not traced (bank $CD).
; Callers note: the JSL at $CD:1855 is followed by RTS (a bank-$CD
;   script command handler, probably; not matched).
; Callers (1 JSL site): unmatched ($CD:1855).
; Entry: M=1, X=0, DP=0 (DP $40 long pointer to the argument; DP
;        $45-$52 scratch), DB=$7E; DP $46/$48 get A's high byte (B) from
;        the 16-bit STX, which nothing here reads
; Exit:  M=1, X=0, DP and DB unchanged; A = 0; X clobbered; Y =
;        !BattleFx_WinUsedBytes; DP $45-$52 written
BattleFx_WaveWindowA:
    LDA.w !BattleFx_CountA
    CLC
    ADC.b [!BattleCD_FxScriptPtr]
    STA.w !BattleFx_CountA
    LDA.b #!BattleFx_WaveRadius
    SEC
    SBC.w !BattleFx_CountA
    STA.b !BattleCD_Tmp4B
    LSR A
    STA.b !BattleCD_Tmp4D
    LDA.b !Battle_FrameCount
    ASL A
    ASL A
    TAX
    STX.b !BattleCD_Tmp45
    LDA.b !Battle_FrameCount
    ASL A
    TAX
    STX.b !BattleCD_Tmp47
    REP #$20
    LDA.w !BattleFx_ShakeX
    CLC
    ADC.w !Battle_FxScrollAddX
    STA.b !BattleCD_Tmp4F
    LDA.w !BattleFx_ShakeY
    CLC
    ADC.w !BattleFx_BounceOut
    STA.b !BattleFx_Tmp51
    TDC
    SEP #$20
    TDC
    TAY
.pair:
    LDA.b !BattleCD_Tmp47
    BPL .left_positive
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp4B
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    EOR.b #!Battle_Invert8
    INC A
    JSR BattleFx_WaveLeftA
    BCC .right_positive
.right_negative:
    LDA.l RDMPYH
    EOR.b #!Battle_Invert8
    INC A
    JSR BattleFx_WaveRight
    BRA .next
.left_positive:
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp4B
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    JSR BattleFx_WaveLeftA
    BCS .right_negative
.right_positive:
    LDA.l RDMPYH
    JSR BattleFx_WaveRight
.next:
    INC.b !BattleCD_Tmp45
    INC.b !BattleCD_Tmp47
    REP #$20
    TYA
    CLC
    ADC.w #$0008
    TAY
    TDC
    SEP #$20
    CPY.w #!BattleFx_WinUsedBytes
    BNE .pair
    RTL

; $D1:EF63 — BattleFx_WaveLeftA (109 bytes, $EF63–$EFCF)
; BattleFx_WaveWindowA's first pair: A (8-bit, its sign in N) is sign-
; extended, added to the word at !BattleFx_WaveBaseX + Y and stored to
; !BattleFx_WinTable0-4 + Y and !BattleFx_WinTable0 + Y. Then starts the
; multiply for the second pair: WRMPYA = !BattleRom_AbsSine at the angle
; DP $45, WRMPYB = DP $4D, and C = 1 when that angle is $80-$FF (the
; caller negates the product).
; Callers (2 JSR sites): BattleFx_WaveWindowA ($D1:EF1B, $D1:EF42).
; Entry: M=1, X=0, A = the offset with N set from it, Y = the step's
;        byte offset, DP=0, DB=$7E; B (A's high byte) = 0, which the
;        positive path's 16-bit ADC takes as the offset's high byte (the
;        TDCs in BattleFx_WaveWindowA guarantee it); the sum is done
;        with C cleared
; Exit:  M=1, X=0; A = DP $4D; X = the angle; Y unchanged; C as above;
;        WRMPYA/WRMPYB written (the multiply runs)
BattleFx_WaveLeftA:
    BPL .positive
    REP #$21
    ORA.w #!BattleFx_SignExtend
    ADC.w !BattleFx_WaveBaseX,Y
    STA.w !BattleFx_WinTable0-4,Y
    STA.w !BattleFx_WinTable0,Y
    TDC
    SEP #$20
    LDA.b !BattleCD_Tmp45
    BPL .next_positive
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp4D
    STA.l WRMPYB
    SEC
    RTS
.next_positive:
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp4D
    STA.l WRMPYB
    CLC
    RTS
.positive:
    REP #$21
    ADC.w !BattleFx_WaveBaseX,Y
    STA.w !BattleFx_WinTable0-4,Y
    STA.w !BattleFx_WinTable0,Y
    TDC
    SEP #$20
    LDA.b !BattleCD_Tmp45
    BPL .next_positive2
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp4D
    STA.l WRMPYB
    SEC
    RTS
.next_positive2:
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp4D
    STA.l WRMPYB
    CLC
    RTS

; $D1:EFD0 — BattleFx_WaveWindowB (174 bytes, $EFD0–$F07D)
; Like BattleFx_WaveWindowA, but with r1 = r2 = !BattleFx_WaveRadius -
; !BattleFx_CountA, and the first pair is r1 x the sine plus
; (!BattleFx_ShakeX + !Battle_FxScrollAddX) instead of the $7E:E500 words
; (BattleFx_WaveLeftB). Two entries pick the angles:
;   - BattleFx_WaveWindowB: from !BattleFx_CountB + !BattleFx_WaveBPhase
;     ($A8), times 2 and times 4; !BattleFx_CountB counts up;
;   - BattleFx_WaveWindowB_ByFrame: from !Battle_FrameCount, times 2
;     and times 4, as BattleFx_WaveWindowA.
; Both then grow !BattleFx_CountA by the argument byte and write the
; table.
; Callers note: the JSLs at $CD:184B (BattleFx_WaveWindowB) and $CD:185F
;   (BattleFx_WaveWindowB_ByFrame) are each followed by RTS (bank-$CD
;   script command handlers, probably; not matched).
; Callers (1 JSL site): unmatched ($CD:184B).
; Callers of BattleFx_WaveWindowB_ByFrame (1 JSL site): unmatched ($CD:185F).
; Entry (both): M=1, X=0, DP=0 (DP $40 long pointer to the argument; DP
;        $45-$52 scratch), DB=$7E; DP $46/$48 get B from the 16-bit STX,
;        which nothing here reads
; Exit (both):  M=1, X=0, DP and DB unchanged; A = 0; X clobbered; Y =
;        !BattleFx_WinUsedBytes; DP $45-$52 written
BattleFx_WaveWindowB:
    LDA.w !BattleFx_CountB
    CLC
    ADC.b #!BattleFx_WaveBPhase
    ASL A
    TAX
    STX.b !BattleCD_Tmp47
    ASL A
    TAX
    STX.b !BattleCD_Tmp45
    INC.w !BattleFx_CountB
    BRA BattleFx_WaveWindowB_ByFrame_build
BattleFx_WaveWindowB_ByFrame:        ; header: see BattleFx_WaveWindowB
    LDA.b !Battle_FrameCount
    ASL A
    TAX
    STX.b !BattleCD_Tmp47
    ASL A
    TAX
    STX.b !BattleCD_Tmp45
.build:
    LDA.w !BattleFx_CountA
    CLC
    ADC.b [!BattleCD_FxScriptPtr]
    STA.w !BattleFx_CountA
    LDA.b #!BattleFx_WaveRadius
    SEC
    SBC.w !BattleFx_CountA
    STA.b !BattleCD_Tmp4B
    STA.b !BattleCD_Tmp4D
    REP #$20
    LDA.w !BattleFx_ShakeX
    CLC
    ADC.w !Battle_FxScrollAddX
    STA.b !BattleCD_Tmp4F
    LDA.w !BattleFx_ShakeY
    CLC
    ADC.w !BattleFx_BounceOut
    STA.b !BattleFx_Tmp51
    TDC
    SEP #$20
    TDC
    TAY
.pair:
    LDA.b !BattleCD_Tmp47
    BPL .left_positive
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp4B
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    EOR.b #!Battle_Invert8
    INC A
    JSR BattleFx_WaveLeftB
    BCC .right_positive
.right_negative:
    LDA.l RDMPYH
    EOR.b #!Battle_Invert8
    INC A
    JSR BattleFx_WaveRight
    BRA .next
.left_positive:
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp4B
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    JSR BattleFx_WaveLeftB
    BCS .right_negative
.right_positive:
    LDA.l RDMPYH
    JSR BattleFx_WaveRight
.next:
    INC.b !BattleCD_Tmp45
    INC.b !BattleCD_Tmp47
    REP #$20
    TYA
    CLC
    ADC.w #$0008
    TAY
    TDC
    SEP #$20
    CPY.w #!BattleFx_WinUsedBytes
    BNE .pair
    RTL

; $D1:F07E — BattleFx_WaveLeftB (107 bytes, $F07E–$F0E8)
; BattleFx_WaveLeftA with DP $4F (the word BattleFx_WaveWindowB formed)
; in place of the !BattleFx_WaveBaseX words.
; Callers (2 JSR sites): BattleFx_WaveWindowB_ByFrame ($D1:F036, $D1:F05D).
; Entry: M=1, X=0, A = the offset with N set from it, Y = the step's
;        byte offset, DP=0, DB=$7E; B (A's high byte) = 0, which the
;        positive path's 16-bit ADC takes as the offset's high byte (the
;        TDCs in BattleFx_WaveWindowB guarantee it)
; Exit:  M=1, X=0; A = DP $4D; X = the angle; Y unchanged; C = 1 when
;        the angle in DP $45 is $80-$FF; WRMPYA/WRMPYB written
BattleFx_WaveLeftB:
    BPL .positive
    REP #$21
    ORA.w #!BattleFx_SignExtend
    ADC.b !BattleCD_Tmp4F
    STA.w !BattleFx_WinTable0-4,Y
    STA.w !BattleFx_WinTable0,Y
    TDC
    SEP #$20
    LDA.b !BattleCD_Tmp45
    BPL .next_positive
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp4D
    STA.l WRMPYB
    SEC
    RTS
.next_positive:
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp4D
    STA.l WRMPYB
    CLC
    RTS
.positive:
    REP #$21
    ADC.b !BattleCD_Tmp4F
    STA.w !BattleFx_WinTable0-4,Y
    STA.w !BattleFx_WinTable0,Y
    TDC
    SEP #$20
    LDA.b !BattleCD_Tmp45
    BPL .next_positive2
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp4D
    STA.l WRMPYB
    SEC
    RTS
.next_positive2:
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp4D
    STA.l WRMPYB
    CLC
    RTS

; $D1:F0E9 — BattleFx_WaveRight (31 bytes, $F0E9–$F107)
; The second pair of the wave windows: A (8-bit, its sign in N) sign-
; extended, plus DP $51, stored to !BattleFx_WinTable0-2 + Y and
; !BattleFx_WinTable0+2 + Y.
; Callers (4 JSR sites): BattleFx_WaveWindowA ($D1:EF27, $D1:EF4B) and BattleFx_WaveWindowB_ByFrame
;   ($D1:F042, $D1:F066).
; Entry: M=1, X=0 (Y is a 16-bit offset, up to $348), A = the offset
;        with N set from it, Y = the step's byte offset, DP=0, DB=$7E;
;        B (A's high byte) = 0, which the positive path's 16-bit ADC
;        takes as the offset's high byte (BattleFx_WaveLeftA/B's TDC
;        leaves it 0)
; Exit:  M=1, X=0; A = the low byte of the sum and B its high byte (no TDC);
;        X and Y unchanged
BattleFx_WaveRight:
    BPL .positive
    REP #$21
    ORA.w #!BattleFx_SignExtend
    ADC.b !BattleFx_Tmp51
    STA.w !BattleFx_WinTable0-2,Y
    STA.w !BattleFx_WinTable0+2,Y
    SEP #$20
    RTS
.positive:
    REP #$21
    ADC.b !BattleFx_Tmp51
    STA.w !BattleFx_WinTable0-2,Y
    STA.w !BattleFx_WinTable0+2,Y
    SEP #$20
    RTS

; $D1:F108 — BattleFx_AddLineOffsets (168 bytes, $F108–$F1AF)
; Adds per-line bytes from $7E:0A00 (DP=$0A00 meanwhile) to lines 48-111
; and 112-175 of this frame's window table (by bit 0 of
; !Battle_FrameCount): for n = 0-63, line 48 + n and line 112 + n each
; get $0A00 + n added to both edges of their first pair, and $0A20 + n
; (table 0) or $0A40 + n (table 1) to both edges of their second pair.
; There is no CLC: each ADC also adds the carry of the one before (the
; first one the carry the caller left); kept as found. Who fills $0A00
; is not traced (bank $CD).
; Callers note: the JSL at $CD:2B64 is followed by RTS (a bank-$CD
;   script command handler, probably; not matched).
; Callers (1 JSL site): unmatched ($CD:2B64).
; Entry: M=1, X=0 (it loads $0A00 16-bit, then sets X=1), DP any (saved;
;        set to !BattleFx_LineAddDp), DB=$7E (the frame count is read as
;        $7E:007C and the tables .w)
; Exit:  M=1, X=0 (REP #$10), DP restored, DB unchanged; A = the last
;        sum; X = $0040; Y = 0 (both counted while X=1, so their high
;        bytes are 0)
BattleFx_AddLineOffsets:
    PHD
    LDX.w #!BattleFx_LineAddDp
    PHX
    PLD
    SEP #$10
    LDY.b #$00
    TYX
    LDA.w !Battle_FrameCount            ; $7E:007C (DP is $0A00 here)
    AND.b #$01
    BEQ .line_buf0
.line_buf1:
    LDA.w !BattleFx_WinTable1+192,Y
    ADC.b !BattleFx_LineAddA,X          ; no CLC: carries chain (kept as found)
    STA.w !BattleFx_WinTable1+192,Y
    LDA.w !BattleFx_WinTable1+193,Y
    ADC.b !BattleFx_LineAddA,X
    STA.w !BattleFx_WinTable1+193,Y
    LDA.w !BattleFx_WinTable1+194,Y
    ADC.b !BattleFx_LineAddB1,X
    STA.w !BattleFx_WinTable1+194,Y
    LDA.w !BattleFx_WinTable1+195,Y
    ADC.b !BattleFx_LineAddB1,X
    STA.w !BattleFx_WinTable1+195,Y
    LDA.w !BattleFx_WinTable1+448,Y
    ADC.b !BattleFx_LineAddA,X
    STA.w !BattleFx_WinTable1+448,Y
    LDA.w !BattleFx_WinTable1+449,Y
    ADC.b !BattleFx_LineAddA,X
    STA.w !BattleFx_WinTable1+449,Y
    LDA.w !BattleFx_WinTable1+450,Y
    ADC.b !BattleFx_LineAddB1,X
    STA.w !BattleFx_WinTable1+450,Y
    LDA.w !BattleFx_WinTable1+451,Y
    ADC.b !BattleFx_LineAddB1,X
    STA.w !BattleFx_WinTable1+451,Y
    INX
    INY
    INY
    INY
    INY
    BNE .line_buf1
    PLD
    REP #$10
    RTL
.line_buf0:
    LDA.w !BattleFx_WinTable0+192,Y
    ADC.b !BattleFx_LineAddA,X
    STA.w !BattleFx_WinTable0+192,Y
    LDA.w !BattleFx_WinTable0+193,Y
    ADC.b !BattleFx_LineAddA,X
    STA.w !BattleFx_WinTable0+193,Y
    LDA.w !BattleFx_WinTable0+194,Y
    ADC.b !BattleFx_LineAddB0,X
    STA.w !BattleFx_WinTable0+194,Y
    LDA.w !BattleFx_WinTable0+195,Y
    ADC.b !BattleFx_LineAddB0,X
    STA.w !BattleFx_WinTable0+195,Y
    LDA.w !BattleFx_WinTable0+448,Y
    ADC.b !BattleFx_LineAddA,X
    STA.w !BattleFx_WinTable0+448,Y
    LDA.w !BattleFx_WinTable0+449,Y
    ADC.b !BattleFx_LineAddA,X
    STA.w !BattleFx_WinTable0+449,Y
    LDA.w !BattleFx_WinTable0+450,Y
    ADC.b !BattleFx_LineAddB0,X
    STA.w !BattleFx_WinTable0+450,Y
    LDA.w !BattleFx_WinTable0+451,Y
    ADC.b !BattleFx_LineAddB0,X
    STA.w !BattleFx_WinTable0+451,Y
    INX
    INY
    INY
    INY
    INY
    BNE .line_buf0
    PLD
    REP #$10
    RTL

; ============================================================
; Set-up, the palette-animation hold, shakes, the second NMI handler,
; bounces and window copies ($D1:F1B0–$D1:F679)
; ============================================================

; $D1:F1B0 — BattleFx_Init (609 bytes, $F1B0–$F410)
; This engine's set-up at the start of a battle (bank $CD's vector
; $CD:0000, which BattleCF_EnterBattle calls as BattleSys_VecCD0000
; before it clears the battle RAM $7E:2D01-$ACEC). Sets DB=$7E and DP=0
; and leaves them so. In order:
;   - JML BattleFx_Nmi and JML BattleFx_Irq into !NmiTrampoline and
;     !IrqTrampoline;
;   - JSL BattleCD_ScrollStepL (the layer drift) and BattleCD_InitHdmaDataL;
;   - !BattleFx_UnkCCA1, !BattleFx_CeSetWant and !BattleFx_CeSet =
;     !Battle_UnkEC bit 0;
;   - zeroes most of its variables (byte and word stores, the words with
;     X = 0), !Battle_Unk99D2, !Battle_NmiMode, !BattleFx_IntBusy,
;     !Battle_FrameCount, !Battle_Paused and the HP gradient's
;     state, then !BattleFx_GradShown = 8, !BattleFx_Unk2989Copy =
;     !Battle_Unk2989, $FF to !Battle_InfoKey, !Battle_UnkCE16,
;     !Battle_LastScriptMsg, !Battle_HdmaEnable and !BattleFx_UnkCD46,
;     !BattleFx_CeSetBase = 8, !BattleFx_HoldAnims = 0, the V-count IRQ
;     at line !BattleFx_IrqLine (211), !BattleFx_CeSetReload = 1, the
;     words !BattleFx_UnkBE9B+0/+2 = $7878; BattleFx_FindGradStart;
;     !BattleFx_GradTickMask = 7;
;   - unless !Battle_Unk2A21 bit 1 is set, stops (.Unk0 = 0) each of
;     FieldAnimB records 0-7 whose .Unk1 has bit 7 set (a first colour
;     in the sprite half of the palette);
;   - more zeroed words; the eight words before !BattleFx_WinTable0-2
;     back to !BattleFx_WinTable0-$10 = !BattleFx_WinFull;
;     !BattleFx_UnkCD46 = !BattleFx_UnkCD46Alt when !Battle_Unk2A21 bit 0
;     is set; the byte at !BattleFx_WinTable0-$12 = 9 (stored twice, with
;     the next byte zeroed between: kept as found); fixed values for
;     !BattleFx_UnkBE9B+6/+$A/+$E, !BattleFx_UnkCA02+2/6/$A/$E/$12 and
;     the two words !BattleFx_UnkC02B;
;   - BattleFx_SaveAnimKinds;
;   - !BattleFx_UnkBEAB and !BattleFx_UnkBF6B: 48 entries of 4 bytes,
;     word 0 then a word v ($FFFC for 19 entries, then 0, 4 and 8 for 12
;     each, 5 of the 8 fitting) and v - $98;
;   - both window tables all !BattleFx_WinEmpty, !BattleFx_UnkBB05
;     zeroed, !Battle_PalRowSave = colours 8-15 of saved background row 1;
;   - JSL BattleCE_UnkEE6E with A = 8, BattleFx_BuildGradHdma,
;     BattleCD_ClearTextGfxL, and ReentryVectors [3] (MusicCueDispatch, the
;     battle music cue, probably) with DB, DP and P saved around it;
;   - A = 0 and !Battle_UnkCAD3 counted up.
; Callers note: reached by JSL from $CD:0039, the target of the vector
;   JMP at $CD:0000 (BattleSys_VecCD0000), which BattleCF_EnterBattle
;   calls.
; Callers (1 JSL site): BattleCD_EnterBattle ($CD:0039).
; Entry: M=1 (8-bit immediates), X=0 (16-bit index loads), DP any and DB
;        any (both set here)
; Exit:  M=1, X=0, DP=0 and DB=$7E (set, not restored); A = 0; X and Y
;        clobbered
BattleFx_Init:
    LDA.b #!Bank7E
    PHA
    PLB
    LDX.w #$0000
    PHX
    PLD
    LDA.b #bank(BattleFx_Nmi)
    STA.w !NmiTrampoline+3
    LDA.b #bank(BattleFx_Irq)
    STA.w !IrqTrampoline+3
    LDX.w #BattleFx_Nmi
    STX.w !NmiTrampoline+1
    LDX.w #BattleFx_Irq
    STX.w !IrqTrampoline+1
    LDA.b #!Op_JML
    STA.w !NmiTrampoline
    STA.w !IrqTrampoline
    JSL BattleCD_ScrollStepL
    JSL BattleCD_InitHdmaDataL
    LDA.b !Battle_UnkEC
    AND.b #$01
    STA.w !BattleFx_UnkCCA1
    STA.w !BattleFx_CeSetWant
    STA.w !BattleFx_CeSet
    TDC
    TAX
    STZ.w !Battle_TilePageSlot
    STZ.w !Battle_TilePageReq
    STZ.w !BattleFx_IntBusy             ; the same byte as DP $7F (DP=0)
    STZ.w !Battle_UnkCA23
    STZ.w !Battle_SfxPending
    STZ.w !Battle_ShakeXOn
    STZ.w !Battle_UnkCD29
    STZ.w !Battle_UnkCD2D
    STZ.w !Battle_ShakeYOn
    STZ.w !Battle_ShakeLayers
    STX.w !Battle_ShakeOfs1X
    STX.w !Battle_ShakeOfs1X+2
    STX.w !Battle_ShakeOfs1X+4
    STX.w !Battle_ShakeOfs1X+6
    STX.w !Battle_ShakeOfs1X+8
    STX.w !Battle_ShakeOfs1X+10
    STZ.w !Battle_UnkCD2E
    STZ.w !Battle_PalAnimCopy
    STZ.w !Battle_BgFxEnded
    STZ.w !Battle_MsgTimer
    STX.w !Battle_MsgShown
    STX.w !Battle_Paused
    STZ.w !Battle_TextStepping
    STZ.w !Battle_UnkCD07
    STX.w !Battle_Unk99D2
    STX.w !BattleFx_UnkCD0A
    STX.w !Battle_ScrollAddX
    STX.w !Battle_ScrollAddY
    STZ.w !Battle_LayerFxLoaded
    STZ.w !Battle_DmaQueueBusy
    STX.w !Battle_ScriptMsgUp
    STZ.b !Battle_NmiMode
    STZ.w !Battle_UnkCAD3
    STZ.w !Battle_LayerFxMode
    STX.w !Battle_FrameCount            ; the same word as DP $7C (DP=0)
    STX.w !BattleFx_BgRequest
    STX.w !BattleFx_UnkCDC7
    STZ.w !Battle_UnkCD3C
    STZ.w !BattleFx_BgLoading
    STX.w !BattleFx_GradFading
    STX.w !BattleFx_GradShown
    STX.w !BattleFx_SlowCount
    STZ.w !BattleFx_GradForce
    STZ.w !Battle_CgramPending
    STZ.w !BattleFx_GradRotRaw
    STZ.w !BattleFx_UnkCE15
    STZ.w !BattleFx_AnimsHeld
    LDA.b #$08
    STA.w !BattleFx_GradShown
    LDA.w !Battle_Unk2989
    STA.w !BattleFx_Unk2989Copy
    LDA.b #!BattleFx_InitFF
    STA.w !Battle_InfoKey
    STA.w !Battle_UnkCE16
    STA.w !Battle_LastScriptMsg
    LDA.b #$08
    STA.w !BattleFx_CeSetBase
    STZ.w !BattleFx_HoldAnims
    LDA.b #!BattleFx_IrqLine
    STA.l VTIMEL
    LDA.b #$00
    STA.l VTIMEH
    LDA.b #!BattleFx_InitFF
    STA.w !Battle_HdmaEnable
    STA.w !BattleFx_UnkCD46
    STZ.w !Battle_WipeMode
    STZ.w !BattleFx_FrameWait
    STZ.w !BattleFx_UnkCA26
    STZ.w !Battle_Unk5D9B
    STZ.w !Battle_FxChannels
    LDA.b #$01
    STA.w !BattleFx_CeSetReload
    LDX.w #!BattleFx_UnkBE9BInit
    STX.w !BattleFx_UnkBE9B
    LDX.w #!BattleFx_UnkBE9BInit
    STX.w !BattleFx_UnkBE9B+2
    STZ.w !Battle_WinRegs+2
    STZ.w !Battle_WinRegs+3
    STZ.w !Battle_WinRegs+4
    JSR BattleFx_FindGradStart
    LDA.b #$07
    STA.w !BattleFx_GradTickMask
    LDA.w !Battle_Unk2A21
    AND.b #$02
    BNE .anims_done
    TDC
    TAX
.anim:
    LDA.w FieldAnimB[0].Unk1,X
    BPL .next_anim
    STZ.w FieldAnimB[0].Unk0,X
.next_anim:
    TXA
    CLC
    ADC.b #!FieldAnimB_Size
    TAX
    CPX.w #8*!FieldAnimB_Size
    BNE .anim
.anims_done:
    LDX.w #$0000
    STX.w !BattleFx_UnkBE9B+4
    STX.w !BattleFx_UnkBE9B+8
    STX.w !BattleFx_UnkBE9B+12
    STX.w !BattleFx_UnkBEAB
    STX.w !BattleFx_UnkCA02
    STX.w !BattleFx_UnkCA02+4
    STX.w !BattleFx_UnkCA02+8
    STX.w !BattleFx_UnkCA02+12
    STX.w !BattleFx_UnkCA02+16
    LDX.w #!BattleFx_WinFull
    STX.w !BattleFx_WinTable0-16
    STX.w !BattleFx_WinTable0-14
    STX.w !BattleFx_WinTable0-12
    STX.w !BattleFx_WinTable0-10
    STX.w !BattleFx_WinTable0-8
    STX.w !BattleFx_WinTable0-6
    STX.w !BattleFx_WinTable0-4
    STX.w !BattleFx_WinTable0-2
    STZ.w !Battle_WinRegs
    STZ.w !Battle_WinRegs+1
    LDA.w !Battle_Unk2A21
    AND.b #$01
    BEQ .unk_c14f
    LDA.b #!BattleFx_UnkCD46Alt
    STA.w !BattleFx_UnkCD46
.unk_c14f:
    LDA.b #!BattleFx_UnkC14FInit
    STA.w !BattleFx_WinTable0-18
    STZ.w !BattleFx_WinTable0-17
    LDA.b #!BattleFx_UnkC14FInit        ; stored a second time (kept as found)
    STA.w !BattleFx_WinTable0-18
    LDX.w #!BattleFx_UnkBEA1Init
    STX.w !BattleFx_UnkBE9B+6
    STX.w !BattleFx_UnkBE9B+14
    LDX.w #!BattleFx_UnkBEA5Init
    STX.w !BattleFx_UnkBE9B+10
    LDX.w #!BattleFx_UnkCA04Init
    STX.w !BattleFx_UnkCA02+2
    LDX.w #!BattleFx_UnkCA08Init
    STX.w !BattleFx_UnkCA02+6
    STX.w !BattleFx_UnkCA02+10
    LDX.w #!BattleFx_UnkCA10Init
    STX.w !BattleFx_UnkCA02+14
    LDX.w #!BattleFx_UnkCA14Init
    STX.w !BattleFx_UnkCA02+18
    LDX.w #!BattleFx_UnkC02BInit
    STX.w !BattleFx_UnkC02B
    STX.w !BattleFx_UnkC02B+2
    JSR BattleFx_SaveAnimKinds
    REP #$20
    LDA.w #!BattleFx_UnkBEABRun1
    STA.b !BattleCD_Tmp53
    LDA.w #!BattleFx_UnkBEABStart
    STA.b !BattleCD_Tmp55
    TDC
    TAX
    BRA .entry
.run12:
    LDA.w #!BattleFx_UnkBEABRun
    STA.b !BattleCD_Tmp53
.entry:
    STZ.w !BattleFx_UnkBEAB,X
    STZ.w !BattleFx_UnkBF6B,X
    LDA.b !BattleCD_Tmp55
    STA.w !BattleFx_UnkBEAB+2,X
    SEC
    SBC.w #!BattleFx_UnkBF6BOfs
    STA.w !BattleFx_UnkBF6B+2,X
    INX
    INX
    INX
    INX
    CPX.w #!BattleFx_UnkBEABBytes
    BEQ .windows
    DEC.b !BattleCD_Tmp53
    BNE .entry
    LDA.b !BattleCD_Tmp55
    CLC
    ADC.w #$0004
    STA.b !BattleCD_Tmp55
    BRA .run12
.windows:
    TDC
    TAX
    LDA.w #!BattleFx_WinEmpty
.window_word:
    STA.w !BattleFx_WinTable0,X
    STA.w !BattleFx_WinTable1,X
    INX
    INX
    CPX.w #!BattleFx_WinTableBytes
    BNE .window_word
    TDC
    TAX
.clear_bb05:
    STZ.w !BattleFx_UnkBB05,X
    INX
    INX
    CPX.w #!BattleFx_UnkBB05Bytes
    BNE .clear_bb05
    TDC
    TAX
.copy_colours:
    LDA.w !Battle_PaletteSavedLo+(1*!Battle_RowBytes)+16,X
    STA.w !Battle_PalRowSave,X
    INX
    INX
    CPX.w #!BattleFx_UnkCCEEBytes
    BNE .copy_colours
    TDC
    SEP #$20
    LDA.b #$08
    JSL BattleCE_UnkEE6E
    JSL BattleFx_BuildGradHdma
    JSL BattleCD_ClearTextGfxL
    PHB
    PHD
    PHP
    JSL ReentryVectors+8                ; ReentryVectors [3]: MusicCueDispatch
    PLP
    PLD
    PLB
    TDC
    INC.w !Battle_UnkCAD3
    RTL

; $D1:F411 — BattleFx_SaveAnimKinds (21 bytes, $F411–$F425)
; Copies .Unk0 (the kind) of FieldAnimB records 0-7 to
; !BattleFx_SavedKinds+0..7.
; Callers (2 JSR sites): BattleFx_Init ($D1:F383) and BattleFx_HoldAnimsTick ($D1:F439).
; Entry: M=1, X=0, DP=0 (TDC as 0), DB=$7E
; Exit:  M=1, X=0; A = X = 8*!FieldAnimB_Size; Y = 8
BattleFx_SaveAnimKinds:
    TDC
    TAX
    TAY
.record:
    LDA.w FieldAnimB[0].Unk0,X
    STA.w !BattleFx_SavedKinds,Y
    TXA
    CLC
    ADC.b #!FieldAnimB_Size
    TAX
    INY
    CPY.w #$0008
    BNE .record
    RTS

; $D1:F426 — BattleFx_HoldAnimsTick (78 bytes, $F426–$F473)
; Holds and releases the palette animations around bank $CD's
; PalAnim_TickAll call (its callers run FdVec_FFF7 right after):
;   - !BattleFx_HoldAnims non-zero, !BattleFx_AnimsHeld still 0: sets
;     !BattleFx_AnimsHeld, saves the kinds of records 0-7
;     (BattleFx_SaveAnimKinds) and stops each one whose kind is
;     !FieldAnimB_Kind10 or has bit 7 set (kinds 1 and 8-15);
;   - !BattleFx_HoldAnims 0, !BattleFx_AnimsHeld set: clears it and puts
;     the kinds of records 0-7 back from !BattleFx_SavedKinds;
;   - otherwise nothing.
; Callers note: the JSLs at $CD:09BB and $CD:0AD2 are in bank $CD's NMI
;   work, every frame.
; Callers (2 JSL sites): BattleCD_NmiMain ($CD:09BB) and BattleCD_NmiSetup ($CD:0AD2).
; Entry: M=1, X=0, DP=0 (TDC as 0), DB=$7E
; Exit:  M=1, X=0, DP and DB unchanged; A, X and Y clobbered (when
;        nothing is done X and Y are unchanged and A = the flag read
;        last: !BattleFx_AnimsHeld)
BattleFx_HoldAnimsTick:
    LDA.w !BattleFx_HoldAnims
    BEQ .release
    JMP .hold
.release:
    JMP .release_do
.hold:
    LDA.w !BattleFx_AnimsHeld
    BNE .done
    INC.w !BattleFx_AnimsHeld
    JSR BattleFx_SaveAnimKinds
    TDC
    TAX
.record:
    LDA.w FieldAnimB[0].Unk0,X
    BMI .stop
    AND.b #!BattleFx_HighNibble
    CMP.b #!FieldAnimB_Kind10
    BNE .next
.stop:
    STZ.w FieldAnimB[0].Unk0,X
.next:
    TXA
    CLC
    ADC.b #!FieldAnimB_Size
    TAX
    CPX.w #8*!FieldAnimB_Size
    BNE .record
.done:
    RTL
.release_do:
    LDA.w !BattleFx_AnimsHeld
    BEQ .done2
    STZ.w !BattleFx_AnimsHeld
    TDC
    TAX
    TAY
.restore:
    LDA.w !BattleFx_SavedKinds,Y
    STA.w FieldAnimB[0].Unk0,X
    TXA
    CLC
    ADC.b #!FieldAnimB_Size
    TAX
    INY
    CPY.w #$0008
    BNE .restore
.done2:
    RTL

; $D1:F474 — BattleFx_RandomByte (8 bytes, $F474–$F47B)
; A = RandomTable entry A + !Battle_FrameCount (low byte) + C. No CLC:
; the carry the caller left is added too.
; Callers (2 JSR sites): BattleFx_RandomShake ($D1:F483, $D1:F490).
; Entry: M=1, X=0, A = the base, B = 0 (TAX makes the 16-bit index;
;        see BattleFx_RandomShake), DP=0, DB any (the table is read long)
; Exit:  M=1; A = the byte; X = the index; Y unchanged
BattleFx_RandomByte:
    ADC.b !Battle_FrameCount            ; no CLC: the caller's carry is added too
    TAX
    LDA.l RandomTable,X
    RTS

; $D1:F47C — BattleFx_RandomShake (68 bytes, $F47C–$F4BF)
; Picks a random shake from three argument bytes (base x, base y, mask):
; x = (random byte & mask) + base x, y = (random byte & mask) + base y,
; and stores -x and -y (16-bit) to !BattleFx_ShakeX and
; !BattleFx_ShakeY at X = !BattleFx_RecOfs. The random bytes are
; BattleFx_RandomByte at mask + frame count and at x + frame count (each
; with the carry left before). Then moves !BattleCD_FxScriptPtr on by 2.
; Callers note: the JSL at $CD:1913 is followed by RTS (a bank-$CD
;   script command handler, probably; not matched).
; Callers (1 JSL site): unmatched ($CD:1913).
; Entry: M=1, X=0, DP=0 (DP $40 long pointer to the arguments, DP $43),
;        DB=$7E; B = 0 assumed (BattleFx_RandomByte's TAX; not traced at
;        the caller); C is used by the first random index
; Exit:  M=1, X=0, DP and DB unchanged; A = 0; X = !BattleFx_RecOfs; Y
;        = the new low word of !BattleCD_FxScriptPtr; DP $45, $47, $49
;        written
BattleFx_RandomShake:
    LDY.w #$0002
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.b !BattleCD_Tmp49
    JSR BattleFx_RandomByte
    AND.b !BattleCD_Tmp49
    CLC
    ADC.b [!BattleCD_FxScriptPtr]
    STA.b !BattleCD_Tmp45
    LDY.w #$0001
    JSR BattleFx_RandomByte
    AND.b !BattleCD_Tmp49
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.b !BattleCD_Tmp47
    LDX.b !BattleFx_RecOfs
    REP #$20
    LDA.b !BattleCD_Tmp45
    AND.w #!Battle_LowByteMask
    EOR.w #!Battle_Invert16
    INC A
    STA.w !BattleFx_ShakeX,X
    LDA.b !BattleCD_Tmp47
    AND.w #!Battle_LowByteMask
    EOR.w #!Battle_Invert16
    INC A
    STA.w !BattleFx_ShakeY,X
    TDC
    SEP #$20
    LDY.b !BattleCD_FxScriptPtr
    INY
    INY
    STY.b !BattleCD_FxScriptPtr
    RTL

; $D1:F4C0 — BattleFx_NmiAlt (153 bytes, $F4C0–$F558)
; A second NMI handler of the battle: BattleCD_ExitBattle installs it
; at the battle's end, after the closing wipe (the STX at $CD:0420
; stores its address to !NmiTrampoline+1, the STA at $CD:041A the bank
; byte to +3). It saves A, X, Y, DB and DP, sets DP=0, turns HDMA off
; (STA.l), reads RDNMI, writes !Nmi_Nmitimen, zeroes DP $47, then: JSL
; BattleCD_UploadCgram (meant as the CGRAM upload), ReentryVectors [2]
; (Field_RefreshHdmaLong, whose A it stores with STA.w HDMAEN), INIDISP
; = DP $45 (read long), BG1-BG3 scroll from !Battle_PpuScroll2 (with
; DB=$7E, each register written low then high), JSL
; BattleCD_ScrollStepL (the layer drift) and FdVec_FFF7
; (PalAnim_TickAll). Unlike BattleFx_Nmi it has no busy flag and does
; not restore the math registers.
; Quirk: the STA.w HDMAEN here and BattleCD_UploadCgram's .w register
; stores use the interrupted code's DB (neither routine sets DB before
; them; Field_RefreshHdmaLong restores it). The NMIs it is installed
; for interrupt BattleCD_ExitBattle, which runs with DB=$7E (its own .w
; accesses to $2A1F, $2A21 and $BB00 around the waits need it): in its
; BattleCD_WaitNmiAck waits (and the instructions between the install
; and the first wait) those stores land in WRAM ($7E:420C, $7E:420B,
; $7E:2121, $7E:4370-$4377), not on the registers. So there the palette
; is not uploaded and HDMA stays off (the STA.l above zeroed HDMAEN);
; only NMITIMEN, INIDISP and the scroll registers (all written long)
; reach the hardware. An NMI that lands in AudioFadeDispatch, or after
; ExitBattle returns while this handler is still installed, gets that
; code's DB; not traced.
; Callers note: no call site; reached through !NmiTrampoline.
; Entry: an NMI; any M, X and DP (it sets M=0, X=0, then M=1 and DP=0);
;        DB the interrupted code's ($7E in BattleCD_ExitBattle's waits;
;        see above; saved, then set to $7E)
; Exit:  RTI with A, X, Y (16-bit), DB, DP and P restored
BattleFx_NmiAlt:
    REP #$30
    PHA
    PHX
    PHY
    PHB
    PHD
    LDA.w #$0000
    TCD
    TDC
    SEP #$20
    STA.l HDMAEN
    LDA.l RDNMI                         ; acknowledge the NMI
    LDA.b #!Nmi_Nmitimen
    STA.l NMITIMEN
    STZ.b !BattleCD_Tmp47
    JSL BattleCD_UploadCgram
    JSL ReentryVectors+5                ; ReentryVectors [2]: Field_RefreshHdmaLong
    STA.w HDMAEN                        ; absolute: the interrupted code's DB
    LDA.l !BattleCD_Tmp45               ; DP $45 read long
    STA.l INIDISP
    LDA.b #!Bank7E
    PHA
    PLB
    LDA.w !Battle_PpuScroll2
    STA.l BG1HOFS
    LDA.w !Battle_PpuScroll2+1
    STA.l BG1HOFS
    LDA.w !Battle_PpuScroll2+2
    STA.l BG1VOFS
    LDA.w !Battle_PpuScroll2+3
    STA.l BG1VOFS
    LDA.w !Battle_PpuScroll2+4
    STA.l BG2HOFS
    LDA.w !Battle_PpuScroll2+5
    STA.l BG2HOFS
    LDA.w !Battle_PpuScroll2+6
    STA.l BG2VOFS
    LDA.w !Battle_PpuScroll2+7
    STA.l BG2VOFS
    LDA.w !Battle_PpuScroll2+8
    STA.l BG3HOFS
    LDA.w !Battle_PpuScroll2+9
    STA.l BG3HOFS
    LDA.w !Battle_PpuScroll2+10
    STA.l BG3VOFS
    LDA.w !Battle_PpuScroll2+11
    STA.l BG3VOFS
    JSL BattleCD_ScrollStepL
    JSL FdVec_FFF7
    REP #$30
    PLD
    PLB
    PLY
    PLX
    PLA
    RTI

; $D1:F559 — BattleFx_StepBounce (116 bytes, $F559–$F5CC)
; One step of a bounce for record X = !BattleFx_RecOfs (16-bit fields):
;   - !BattleFx_BounceDir non-zero (falling): !BattleFx_BounceSpeed +=
;     !BattleFx_BounceAccel, unless that overflows, which zeroes the
;     direction word instead; then the 32-bit !BattleFx_BouncePos loses
;     the speed;
;   - zero (rising): the speed loses the accel, unless that would go
;     below 0, which counts the direction up instead; the position gains
;     the speed;
;   - !BattleFx_BounceOut = !BattleFx_BounceBase + the high word of the
;     position, or minus it for record !BattleFx_BounceMirrorOfs ($10).
; "Bounce" is inferred from the motion (slows down, turns, speeds up).
; Callers note: the JSL at $CD:1AE6 is followed by RTS (a bank-$CD
;   script command handler, probably; not matched).
; Callers (1 JSL site): unmatched ($CD:1AE6).
; Entry: M=1, X=0, DP=0 (DP $43), DB=$7E
; Exit:  M=1, X=0, DP and DB unchanged; A = 0; X = !BattleFx_RecOfs; Y
;        unchanged
BattleFx_StepBounce:
    LDX.b !BattleFx_RecOfs
    LDA.w !BattleFx_BounceDir,X
    BEQ .slowing
    REP #$20
    LDA.w !BattleFx_BounceSpeed,X
    CLC
    ADC.w !BattleFx_BounceAccel,X
    BCC .store_speed
    STZ.w !BattleFx_BounceDir,X
    BRA .move_down
.store_speed:
    STA.w !BattleFx_BounceSpeed,X
.move_down:
    LDA.w !BattleFx_BouncePos,X
    SEC
    SBC.w !BattleFx_BounceSpeed,X
    STA.w !BattleFx_BouncePos,X
    LDA.w !BattleFx_BouncePos+2,X
    SBC.w #$0000
    STA.w !BattleFx_BouncePos+2,X
    BRA .output
.slowing:
    REP #$20
    LDA.w !BattleFx_BounceSpeed,X
    SEC
    SBC.w !BattleFx_BounceAccel,X
    BCS .store_speed2
    INC.w !BattleFx_BounceDir,X
    BRA .move_up
.store_speed2:
    STA.w !BattleFx_BounceSpeed,X
.move_up:
    LDA.w !BattleFx_BouncePos,X
    CLC
    ADC.w !BattleFx_BounceSpeed,X
    STA.w !BattleFx_BouncePos,X
    LDA.w !BattleFx_BouncePos+2,X
    ADC.w #$0000
    STA.w !BattleFx_BouncePos+2,X
.output:
    CPX.w #!BattleFx_BounceMirrorOfs
    BNE .add
    LDA.w !BattleFx_BounceBase,X
    SEC
    SBC.w !BattleFx_BouncePos+2,X
    STA.w !BattleFx_BounceOut,X
    BRA .done
.add:
    LDA.w !BattleFx_BounceBase,X
    CLC
    ADC.w !BattleFx_BouncePos+2,X
    STA.w !BattleFx_BounceOut,X
.done:
    TDC
    SEP #$20
    RTL

; $D1:F5CD — BattleFx_SaveCalcPoints (40 bytes, $F5CD–$F5F4)
; Copies the six bytes of !Battle_ActCalcResult to !BattleFx_CalcCopy +
; X (X = the argument byte), two bytes apart: bytes 0, 2, 4 (the x of
; the three points, probably) to +0, +4, +8, bytes 1, 3, 5 to +2, +6,
; +$A. X = 0 and 1 give two interleaved copies.
; Callers note: the JSL at $CD:191E is followed by RTS (a bank-$CD
;   script command handler, probably; not matched).
; Callers (1 JSL site): unmatched ($CD:191E).
; Entry: M=1, X=0, DP=0 (DP $40 long pointer to the argument), DB=$7E;
;        B = 0 assumed (TAX; not traced at the caller)
; Exit:  M=1, X=0, DP and DB unchanged; A = !Battle_ActCalcResult+5; X =
;        the argument; Y unchanged
BattleFx_SaveCalcPoints:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.w !Battle_ActCalcResult
    STA.w !BattleFx_CalcCopy,X
    LDA.w !Battle_ActCalcResult+2
    STA.w !BattleFx_CalcCopy+4,X
    LDA.w !Battle_ActCalcResult+4
    STA.w !BattleFx_CalcCopy+8,X
    LDA.w !Battle_ActCalcResult+1
    STA.w !BattleFx_CalcCopy+2,X
    LDA.w !Battle_ActCalcResult+3
    STA.w !BattleFx_CalcCopy+6,X
    LDA.w !Battle_ActCalcResult+5
    STA.w !BattleFx_CalcCopy+10,X
    RTL

; $D1:F5F5 — BattleFx_CopyWin1ToWin2 (133 bytes, $F5F5–$F679)
; Copies the first pair of every line (0-223) of one window table into
; the second pair of the other: table 0 into table 1 when bit 0 of
; !Battle_FrameCount is set (the table this frame writes), table 1
; into table 0 when clear.
; Callers note: the JSL at $CD:1932 is followed by RTS (a bank-$CD
;   script command handler, probably; not matched).
; Callers (1 JSL site): unmatched ($CD:1932).
; Entry: M=1, X any (set to 1 here), DP=0 (TDC as 0, DP $7C), DB=$7E
; Exit:  M=1, X=0 (REP #$10), DP and DB unchanged; A = 0; X =
;        !BattleFx_WinBlockBytes; Y's low byte kept, high byte cleared
;        (SEP #$10)
BattleFx_CopyWin1ToWin2:
    TDC
    TAX
    REP #$20
    SEP #$10
    LDA.b !Battle_FrameCount
    AND.w #$0001
    BEQ .line_buf0
.line_buf1:
    LDA.w !BattleFx_WinTable0,X
    STA.w !BattleFx_WinTable1+2,X
    LDA.w !BattleFx_WinTable0+112,X
    STA.w !BattleFx_WinTable1+114,X
    LDA.w !BattleFx_WinTable0+224,X
    STA.w !BattleFx_WinTable1+226,X
    LDA.w !BattleFx_WinTable0+336,X
    STA.w !BattleFx_WinTable1+338,X
    LDA.w !BattleFx_WinTable0+448,X
    STA.w !BattleFx_WinTable1+450,X
    LDA.w !BattleFx_WinTable0+560,X
    STA.w !BattleFx_WinTable1+562,X
    LDA.w !BattleFx_WinTable0+672,X
    STA.w !BattleFx_WinTable1+674,X
    LDA.w !BattleFx_WinTable0+784,X
    STA.w !BattleFx_WinTable1+786,X
    INX
    INX
    INX
    INX
    CPX.b #!BattleFx_WinBlockBytes
    BNE .line_buf1
    BRA .done
.line_buf0:
    LDA.w !BattleFx_WinTable1,X
    STA.w !BattleFx_WinTable0+2,X
    LDA.w !BattleFx_WinTable1+112,X
    STA.w !BattleFx_WinTable0+114,X
    LDA.w !BattleFx_WinTable1+224,X
    STA.w !BattleFx_WinTable0+226,X
    LDA.w !BattleFx_WinTable1+336,X
    STA.w !BattleFx_WinTable0+338,X
    LDA.w !BattleFx_WinTable1+448,X
    STA.w !BattleFx_WinTable0+450,X
    LDA.w !BattleFx_WinTable1+560,X
    STA.w !BattleFx_WinTable0+562,X
    LDA.w !BattleFx_WinTable1+672,X
    STA.w !BattleFx_WinTable0+674,X
    LDA.w !BattleFx_WinTable1+784,X
    STA.w !BattleFx_WinTable0+786,X
    INX
    INX
    INX
    INX
    CPX.b #!BattleFx_WinBlockBytes
    BNE .line_buf0
.done:
    TDC
    SEP #$20
    REP #$10
    RTL

; ============================================================
; Battle-script opcode $80's settings ($D1:F67A–$D1:F83C)
; ============================================================

; $D1:F67A — BattleFx_Op80Dispatch (12 bytes, $F67A–$F685)
; Runs the handler of BattleFx_Op80Table picked by the high nibble of
; !Battle_ActOp80Args (the bytes battle-script opcode $80 copied; its
; first byte's low nibble is their count).
; Callers note: reached by JSL from $CD:003E (then RTL), the target of
;   the vector JMP at $CD:001B (BattleAct_UnkVecCD001B), which
;   BattleAct_OpRunVecCD001B calls.
; Callers (1 JSL site): BattleCD_ActOp80 ($CD:003E).
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (as BattleAct_OpRunVecCD001B
;        leaves them; the vector code in bank $CD only jumps)
; Exit:  as the handler: M=1, X=0, DP=0, DB=$7E; A, X and Y as it
;        leaves them
BattleFx_Op80Dispatch:
    LDA.b !Battle_ActOp80Args
    AND.b #!BattleFx_HighNibble
    LSR A
    LSR A
    LSR A
    TAX
    JSR (BattleFx_Op80Table,X)
    RTL

; $D1:F686 — BattleFx_Op80Table (12 bytes, $F686–$F691)
; BattleFx_Op80Dispatch's handlers, by the high nibble of
; !Battle_ActOp80Args (0-5). A nibble of 6 or more would read past the
; table into the code after it.
BattleFx_Op80Table:
    dw BattleFx_Op80Kind0               ; 0
    dw BattleFx_Op80Kind0               ; 1
    dw BattleFx_Op80Kind0               ; 2
    dw BattleFx_Op80Kind0               ; 3
    dw BattleFx_Op80Kind4               ; 4
    dw BattleFx_Op80Clear               ; 5

; $D1:F692 — BattleFx_Op80Clear (10 bytes, $F692–$F69B)
; Op80 handler 5 (BattleFx_Op80Table), also run first by
; BattleFx_Op80Kind4: zeroes !Battle_ShakeXOn, !Battle_ShakeYOn and
; !Battle_ShakeLayers (the screen shake off).
; Callers note: also BattleFx_Op80Table entry 5.
; Callers (1 JSR site): BattleFx_Op80Kind4 ($D1:F6B4).
; Entry: M=1, DP any, DB=$7E
; Exit:  M=1; A, X, Y unchanged
BattleFx_Op80Clear:
    STZ.w !Battle_ShakeXOn
    STZ.w !Battle_ShakeYOn
    STZ.w !Battle_ShakeLayers
    RTS

; $D1:F69C — BattleFx_Op80Bits8 (8 bytes, $F69C–$F6A3)
; BattleFx_Op80Kind4: the value for bits 2-4 of an argument byte (0-7):
; 1, 2, 3, 4, then single bits 8, $10, $20, $40.
BattleFx_Op80Bits8:
    db $01,$02,$03,$04,$08,$10,$20,$40

; $D1:F6A4 — BattleFx_Op80BitsHi (8 bytes, $F6A4–$F6AB)
; BattleFx_Op80Kind4: the value for bits 5-7 of an argument byte (0-7):
; the single bits 1 to $80.
BattleFx_Op80BitsHi:
    db $01,$02,$04,$08,$10,$20,$40,$80

; $D1:F6AC — BattleFx_Op80OrA (4 bytes, $F6AC–$F6AF)
; BattleFx_Op80Kind4: by bits 0-1 of the first argument byte, the bits
; ORed into !Battle_ShakeLayers ($00, $28, $A0, $A8).
BattleFx_Op80OrA:
    db $00,$28,$A0,$A8

; $D1:F6B0 — BattleFx_Op80OrB (4 bytes, $F6B0–$F6B3)
; The same by bits 0-1 of the third argument byte ($00, $14, $50, $54:
; BattleFx_Op80OrA's values shifted right once).
BattleFx_Op80OrB:
    db $00,$14,$50,$54

; $D1:F6B4 — BattleFx_Op80Kind4 (153 bytes, $F6B4–$F74C)
; Op80 handler 4: BattleFx_Op80Clear, then fills the two 8-byte groups
; from !Battle_ShakeXOn (x) and !Battle_ShakeYOn (y) from the argument
; bytes 1-4 (!Battle_ActOp80Args+1 to +4). For byte 1 (group at +0) and
; byte 3 (group at +8):
;   +3 = BattleFx_Op80Bits8[bits 2-4], +2 = 0,
;   +5 = BattleFx_Op80BitsHi[bits 5-7], +4 = 0,
;   +0 = bits 0-1;
; and from byte 2 (group +0) and byte 4 (group +8): +7 = its low nibble,
; +6 = its high nibble. +$10 (!Battle_ShakeLayers) =
; BattleFx_Op80OrA[byte 1 bits 0-1] | BattleFx_Op80OrB[byte 3 bits 0-1].
; These are the screen shake's settings (on, random period, step period,
; amplitude, target), which BattleCD_StepShake runs.
; Callers note: BattleFx_Op80Table entry 4.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (BattleFx_Op80Dispatch)
; Exit:  M=1, X=0; A = the last value stored; X clobbered; Y unchanged;
;        DP $5B written
BattleFx_Op80Kind4:
    JSR BattleFx_Op80Clear
    LDA.b !Battle_ActOp80Args+1
    AND.b #!BattleFx_Op80Bits8Mask
    LSR A
    LSR A
    TAX
    LDA.l BattleFx_Op80Bits8,X
    STA.w !Battle_ShakeXRandPeriod
    STZ.w !Battle_ShakeXRandTime
    LDA.b !Battle_ActOp80Args+1
    AND.b #!BattleFx_Op80BitsHiMask
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    TAX
    LDA.l BattleFx_Op80BitsHi,X
    STA.w !Battle_ShakeXStepPeriod
    STZ.w !Battle_ShakeXStepTime
    LDA.b !Battle_ActOp80Args+2
    AND.b #!BattleFx_LowNibble
    STA.w !Battle_ShakeXTarget
    LDA.b !Battle_ActOp80Args+2
    AND.b #!BattleFx_HighNibble
    LSR A
    LSR A
    LSR A
    LSR A
    STA.w !Battle_ShakeXAmp
    LDA.b !Battle_ActOp80Args+3
    AND.b #!BattleFx_Op80Bits8Mask
    LSR A
    LSR A
    TAX
    LDA.l BattleFx_Op80Bits8,X
    STA.w !Battle_ShakeYRandPeriod
    STZ.w !Battle_ShakeYRandTime
    LDA.b !Battle_ActOp80Args+3
    AND.b #!BattleFx_Op80BitsHiMask
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    TAX
    LDA.l BattleFx_Op80BitsHi,X
    STA.w !Battle_ShakeYStepPeriod
    STZ.w !Battle_ShakeYStepTime
    LDA.b !Battle_ActOp80Args+4
    AND.b #!BattleFx_LowNibble
    STA.w !Battle_ShakeYTarget
    LDA.b !Battle_ActOp80Args+4
    AND.b #!BattleFx_HighNibble
    LSR A
    LSR A
    LSR A
    LSR A
    STA.w !Battle_ShakeYAmp
    LDA.b !Battle_ActOp80Args+1
    AND.b #$03
    TAX
    LDA.l BattleFx_Op80OrA,X
    STA.b !BattleCD_Tmp5B
    LDA.b !Battle_ActOp80Args+3
    AND.b #$03
    TAX
    LDA.l BattleFx_Op80OrB,X
    ORA.b !BattleCD_Tmp5B
    STA.w !Battle_ShakeLayers
    LDA.b !Battle_ActOp80Args+1
    AND.b #$03
    STA.w !Battle_ShakeXOn
    LDA.b !Battle_ActOp80Args+3
    AND.b #$03
    STA.w !Battle_ShakeYOn
    RTS

; $D1:F74D — BattleFx_Op80Kind0 (240 bytes, $F74D–$F83C)
; Op80 handlers 0-3: builds the two FieldAnimB records of
; !Battle_PalAnimRecs89 (record 8 at +0, record 9 at +12; offsets below
; are within each record). The high nibble n of the first argument byte
; picks 8 bytes of !BattleRom_Op80RegsA and of !BattleRom_Op80RegsB
; (+ n * 16), copied to +1 of record 8 and of record 9. Then, from
; argument byte 1 (!Battle_ActOp80Args+1), in both records:
;   - +0 = !BattleFx_UnkCCC1Base ($40), or'd with !BattleFx_UnkCCC1Swap
;     when bit 6 is set;
;   - +6 = bits 0-2;
;   - +4/+5 = two of the four bytes of !BattleRom_Op80PairA at
;     (bits 3-5) * 4; +3 = one of the two of !BattleRom_Op80PairB at
;     (bits 3-5) * 2;
;   - bit 7 set, bit 6 clear: each +7 and +8 that is non-zero becomes $80;
;   - bit 7 set, bit 6 set: each of them that is zero becomes $80, then
;     as bit 6 alone;
;   - bit 6 set: +7 and +8 swap.
; Then counts !Battle_PalAnimCopy up, so BattleCD_StepShake copies the
; records to FieldAnimB records 8 and 9 (palette animations).
; Callers note: BattleFx_Op80Table entries 0-3.
; Entry: M=1, X=0, DP=0, DB=$7E, B = 0 (BattleFx_Op80Dispatch)
; Exit:  M=1, X=0; A, X and Y clobbered
BattleFx_Op80Kind0:
    LDA.b !Battle_ActOp80Args
    AND.b #!BattleFx_HighNibble
    TAX
    TDC
    TAY
.copy:
    LDA.l !BattleRom_Op80RegsA,X
    STA.w !Battle_PalAnimRecs89+1,Y
    LDA.l !BattleRom_Op80RegsB,X
    STA.w !Battle_PalAnimRecs89+13,Y
    INX
    INY
    CPY.w #$0008
    BNE .copy
    LDA.b !Battle_ActOp80Args+1
    AND.b #!BattleFx_Op80SwapBit
    BEQ .store_c1
    LDA.b #!BattleFx_UnkCCC1Swap
.store_c1:
    ORA.b #!BattleFx_UnkCCC1Base
    STA.w !Battle_PalAnimRecs89
    STA.w !Battle_PalAnimRecs89+12
    LDA.b !Battle_ActOp80Args+1
    AND.b #$07
    STA.w !Battle_PalAnimRecs89+6
    STA.w !Battle_PalAnimRecs89+18
    LDA.b !Battle_ActOp80Args+1
    AND.b #!BattleFx_Op80PairMask
    LSR A
    TAX
    LDA.l !BattleRom_Op80PairA,X
    STA.w !Battle_PalAnimRecs89+4
    LDA.l !BattleRom_Op80PairA+1,X
    STA.w !Battle_PalAnimRecs89+5
    LDA.l !BattleRom_Op80PairA+2,X
    STA.w !Battle_PalAnimRecs89+16
    LDA.l !BattleRom_Op80PairA+3,X
    STA.w !Battle_PalAnimRecs89+17
    LDA.b !Battle_ActOp80Args+1
    AND.b #!BattleFx_Op80PairMask
    LSR A
    LSR A
    TAX
    LDA.l !BattleRom_Op80PairB,X
    STA.w !Battle_PalAnimRecs89+3
    LDA.l !BattleRom_Op80PairB+1,X
    STA.w !Battle_PalAnimRecs89+15
    LDA.b !Battle_ActOp80Args+1
    BPL .swap
    LDA.b !Battle_ActOp80Args+1
    AND.b #!BattleFx_Op80SwapBit
    BNE .set_bits
    LDA.w !Battle_PalAnimRecs89+7
    BEQ .store_c8
    LDA.b #!BattleFx_UnkCCC8Bit7
.store_c8:
    STA.w !Battle_PalAnimRecs89+7
    LDA.w !Battle_PalAnimRecs89+8
    BEQ .store_c9
    LDA.b #!BattleFx_UnkCCC8Bit7
.store_c9:
    STA.w !Battle_PalAnimRecs89+8
    LDA.w !Battle_PalAnimRecs89+19
    BEQ .store_d4
    LDA.b #!BattleFx_UnkCCC8Bit7
.store_d4:
    STA.w !Battle_PalAnimRecs89+19
    LDA.w !Battle_PalAnimRecs89+20
    BEQ .store_d5
    LDA.b #!BattleFx_UnkCCC8Bit7
.store_d5:
    STA.w !Battle_PalAnimRecs89+20
    JMP .done
.set_bits:
    LDA.w !Battle_PalAnimRecs89+7
    BNE .set_c8
    ORA.b #!BattleFx_UnkCCC8Bit7
.set_c8:
    STA.w !Battle_PalAnimRecs89+7
    LDA.w !Battle_PalAnimRecs89+8
    BNE .set_c9
    ORA.b #!BattleFx_UnkCCC8Bit7
.set_c9:
    STA.w !Battle_PalAnimRecs89+8
    LDA.w !Battle_PalAnimRecs89+19
    BNE .set_d4
    ORA.b #!BattleFx_UnkCCC8Bit7
.set_d4:
    STA.w !Battle_PalAnimRecs89+19
    LDA.w !Battle_PalAnimRecs89+20
    BNE .set_d5
    ORA.b #!BattleFx_UnkCCC8Bit7
.set_d5:
    STA.w !Battle_PalAnimRecs89+20
.swap:
    LDA.b !Battle_ActOp80Args+1
    AND.b #!BattleFx_Op80SwapBit
    BEQ .done
    LDA.w !Battle_PalAnimRecs89+7
    PHA
    LDA.w !Battle_PalAnimRecs89+8
    STA.w !Battle_PalAnimRecs89+7
    PLA
    STA.w !Battle_PalAnimRecs89+8
    LDA.w !Battle_PalAnimRecs89+19
    PHA
    LDA.w !Battle_PalAnimRecs89+20
    STA.w !Battle_PalAnimRecs89+19
    PLA
    STA.w !Battle_PalAnimRecs89+20
.done:
    INC.w !Battle_PalAnimCopy
    RTS

; ============================================================
; The gradient lists and the quad rasteriser ($D1:F83D–$D1:FB67)
; ============================================================

; $D1:F83D — BattleFx_BuildGradHdma (174 bytes, $F83D–$F8EA)
; Zeroes !BattleFx_GradHdmaBytes from !BattleFx_GradHdmaA-1 and builds
; four lists of 4-byte entries, two bytes used in each:
;   - !BattleFx_GradHdmaA: 24 entries (1, v) with v the high byte of a
;     16-bit value starting $E8AB and falling by $55 per entry ($E8 down
;     to $E1); !BattleFx_GradHdmaB: 24 entries (!BattleFx_GradRepeat1,
;     w) with w rising from $E0 to $E7 ($E055, + $55);
;   - !BattleFx_GradHdmaC and D: the same with 12 entries and steps of
;     $AA ($E856 down, $E0AA up);
; then the last entry of B and of D becomes (0, !BattleFx_GradStartB
; ($E0)), with the byte before it and the one after it zeroed. $E0-$E8 read as
; COLDATA values (all three channels, intensity 0-8), so this is
; probably a fixed-colour gradient; which HDMA channel reads these
; lists is not traced.
; Callers note: called only by BattleFx_Init (JSL).
; Callers (1 JSL site): BattleFx_Init ($D1:F3FA).
; Entry: M=1, X=0, DP=0 (DP $53-$56 accumulators; TDC as 0), DB=$7E
; Exit:  M=1, X=0, DP and DB unchanged; A = !BattleFx_GradStartB; X =
;        !BattleFx_GradPart2Bytes; Y unchanged; DP $53-$56 written
BattleFx_BuildGradHdma:
    LDA.b #!BattleFx_GradStartA
    STA.b !BattleFx_GradStepA+1
    LDA.b #!BattleFx_GradStartB
    STA.b !BattleFx_GradStepB+1
    LDA.b #!BattleFx_GradFracA1
    STA.b !BattleFx_GradStepA
    LDA.b #!BattleFx_GradFracB1
    STA.b !BattleFx_GradStepB
    TDC
    TAX
.clear:
    STZ.w !BattleFx_GradHdmaA-1,X
    INX
    CPX.w #!BattleFx_GradHdmaBytes
    BNE .clear
    TDC
    TAX
.entry_ab:
    LDA.b !BattleFx_GradStepA+1
    STA.w !BattleFx_GradHdmaA+1,X
    LDA.b !BattleFx_GradStepB+1
    STA.w !BattleFx_GradHdmaB+1,X
    LDA.b #!BattleFx_GradRepeat1
    STA.w !BattleFx_GradHdmaB,X
    LDA.b #$01
    STA.w !BattleFx_GradHdmaA,X
    REP #$20
    LDA.b !BattleFx_GradStepA
    SEC
    SBC.w #!BattleFx_GradStep1
    STA.b !BattleFx_GradStepA
    LDA.b !BattleFx_GradStepB
    CLC
    ADC.w #!BattleFx_GradStep1
    STA.b !BattleFx_GradStepB
    TDC
    SEP #$20
    INX
    INX
    INX
    INX
    CPX.w #!BattleFx_GradPart1Bytes
    BNE .entry_ab
    LDA.b #!BattleFx_GradStartA
    STA.b !BattleFx_GradStepA+1
    LDA.b #!BattleFx_GradStartB
    STA.b !BattleFx_GradStepB+1
    LDA.b #!BattleFx_GradFracA2
    STA.b !BattleFx_GradStepA
    LDA.b #!BattleFx_GradFracB2
    STA.b !BattleFx_GradStepB
    TDC
    TAX
.entry_cd:
    LDA.b !BattleFx_GradStepA+1
    STA.w !BattleFx_GradHdmaC+1,X
    LDA.b !BattleFx_GradStepB+1
    STA.w !BattleFx_GradHdmaD+1,X
    LDA.b #!BattleFx_GradRepeat1
    STA.w !BattleFx_GradHdmaD,X
    LDA.b #$01
    STA.w !BattleFx_GradHdmaC,X
    REP #$20
    LDA.b !BattleFx_GradStepA
    SEC
    SBC.w #!BattleFx_GradStep2
    STA.b !BattleFx_GradStepA
    LDA.b !BattleFx_GradStepB
    CLC
    ADC.w #!BattleFx_GradStep2
    STA.b !BattleFx_GradStepB
    TDC
    SEP #$20
    INX
    INX
    INX
    INX
    CPX.w #!BattleFx_GradPart2Bytes
    BNE .entry_cd
    LDA.b #!BattleFx_GradStartB
    STA.w !BattleFx_GradHdmaB+93
    STA.w !BattleFx_GradHdmaD+45
    STZ.w !BattleFx_GradHdmaB+91
    STZ.w !BattleFx_GradHdmaB+92
    STZ.w !BattleFx_GradHdmaB+94
    STZ.w !BattleFx_GradHdmaD+43
    STZ.w !BattleFx_GradHdmaD+44
    STZ.w !BattleFx_GradHdmaD+46
    RTL

; $D1:F8EB — BattleFx_SortQuadByY (50 bytes, $F8EB–$F91C)
; Sorts the four points of BattleFx_DrawQuad (DP $12-$19, x then y) by
; y, top first: four passes of three compare-and-swaps of neighbours
; (equal y also swap), each swap moving a whole point with 16-bit X/Y.
; Callers (1 JSR site): BattleFx_DrawQuad ($D1:F9DB).
; Entry: M=1, X=0, DP=0, DB any (only DP is used)
; Exit:  M=1, X=0; A = 0; X and Y clobbered (the last swap's points);
;        DP and DB unchanged
BattleFx_SortQuadByY:
    LDA.b #$04
.pass:
    PHA
    LDA.b !BattleFx_QuadY0
    CMP.b !BattleFx_QuadY1
    BCC .pair12
    LDX.b !BattleFx_QuadX0
    LDY.b !BattleFx_QuadX1
    STX.b !BattleFx_QuadX1
    STY.b !BattleFx_QuadX0
.pair12:
    LDA.b !BattleFx_QuadY1
    CMP.b !BattleFx_QuadY2
    BCC .pair23
    LDX.b !BattleFx_QuadX1
    LDY.b !BattleFx_QuadX2
    STX.b !BattleFx_QuadX2
    STY.b !BattleFx_QuadX1
.pair23:
    LDA.b !BattleFx_QuadY2
    CMP.b !BattleFx_QuadY3
    BCC .next_pass
    LDX.b !BattleFx_QuadX2
    LDY.b !BattleFx_QuadX3
    STX.b !BattleFx_QuadX3
    STY.b !BattleFx_QuadX2
.next_pass:
    PLA
    DEC A
    BNE .pass
    RTS

; $D1:F91D — BattleFx_QuadSlopes (85 bytes, $F91D–$F971)
; !BattleFx_QuadTop = y0, and the four edge slopes of the sorted quad
; (BattleFx_EdgeSlope): !BattleFx_Slope02 (point 0 to 2),
; !BattleFx_Slope23, !BattleFx_Slope01 and !BattleFx_Slope13.
; Callers (3 JSR sites): BattleFx_RasterQuad ($D1:FA1D, $D1:FA23, $D1:FA29).
; Entry: M=1, X=0, DP=0, DB=$00 (BattleFx_EdgeSlope's registers), B = 0
;        (the dividend's low byte; see BattleFx_EdgeSlope)
; Exit:  M=1, X=0; A = 0, B = 0; X unchanged; Y = !BattleFx_Slope13;
;        DP $03-$0F written
BattleFx_QuadSlopes:
    LDA.b !BattleFx_QuadY0
    STA.b !BattleFx_QuadTop
    LDA.b !BattleFx_QuadY2
    SEC
    SBC.b !BattleFx_QuadY0
    STA.b !BattleFx_SlopeDy
    LDA.b !BattleFx_QuadX2
    STA.b !BattleFx_SlopeXTo
    LDA.b !BattleFx_QuadX0
    STA.b !BattleFx_SlopeXFrom
    JSR BattleFx_EdgeSlope
    STY.b !BattleFx_Slope02
    LDA.b !BattleFx_QuadY3
    SEC
    SBC.b !BattleFx_QuadY2
    STA.b !BattleFx_SlopeDy
    LDA.b !BattleFx_QuadX3
    STA.b !BattleFx_SlopeXTo
    LDA.b !BattleFx_QuadX2
    STA.b !BattleFx_SlopeXFrom
    JSR BattleFx_EdgeSlope
    STY.b !BattleFx_Slope23
    LDA.b !BattleFx_QuadY1
    SEC
    SBC.b !BattleFx_QuadY0
    STA.b !BattleFx_SlopeDy
    LDA.b !BattleFx_QuadX1
    STA.b !BattleFx_SlopeXTo
    LDA.b !BattleFx_QuadX0
    STA.b !BattleFx_SlopeXFrom
    JSR BattleFx_EdgeSlope
    STY.b !BattleFx_Slope01
    LDA.b !BattleFx_QuadY3
    SEC
    SBC.b !BattleFx_QuadY1
    STA.b !BattleFx_SlopeDy
    LDA.b !BattleFx_QuadX3
    STA.b !BattleFx_SlopeXTo
    LDA.b !BattleFx_QuadX1
    STA.b !BattleFx_SlopeXFrom
    JSR BattleFx_EdgeSlope
    STY.b !BattleFx_Slope13
    RTS

; $D1:F972 — BattleFx_EdgeSlope (61 bytes, $F972–$F9AE)
; Y = (!BattleFx_SlopeXTo - !BattleFx_SlopeXFrom) * 256 /
; !BattleFx_SlopeDy, signed (the hardware divides the size of the
; difference; a negative difference negates the quotient): the x step
; per line in 8.8 fixed point. The dividend's low byte is B (XBA after
; the 8-bit subtraction), 0 at every call (the TDC before each). A
; !BattleFx_SlopeDy of 0 is not checked (the hardware then gives $FFFF).
; Callers (4 JSR sites): BattleFx_QuadSlopes ($D1:F930, $D1:F944, $D1:F958, $D1:F96C).
; Entry: M=1, X=0 (16-bit Y), B = 0, DP=0, DB=$00 (WRDIVL/WRDIVB and
;        RDDIVL are absolute)
; Exit:  M=1, X=0; A = 0, B = 0; X unchanged; Y = the slope
BattleFx_EdgeSlope:
    LDA.b !BattleFx_SlopeXTo
    SEC
    SBC.b !BattleFx_SlopeXFrom
    BCC .negative
    XBA
    TAY
    STY.w WRDIVL
    LDA.b !BattleFx_SlopeDy
    STA.w WRDIVB
    TDC
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    LDY.w RDDIVL
    RTS
.negative:
    EOR.b #!Battle_Invert8
    INC A
    XBA
    TAY
    STY.w WRDIVL
    LDA.b !BattleFx_SlopeDy
    STA.w WRDIVB
    TDC
    NOP
    NOP
    NOP
    NOP
    NOP
    REP #$20
    LDA.w RDDIVL
    EOR.w #!Battle_Invert16
    INC A
    TAY
    TDC
    SEP #$20
    RTS

; $D1:F9AF — BattleFx_DrawQuad (56 bytes, $F9AF–$F9E6)
; Draws quad X of !BattleFx_Quads into this frame's window table:
; !BattleFx_QuadSlot = X, the quad's eight coordinate bytes (two bytes
; apart from !BattleFx_Quads + X: x0, y0, x1, y1, x2, y2, x3, y3) go to
; DP $12-$19, BattleFx_SortQuadByY, then BattleFx_RasterQuad with
; DB=$00 (saved and restored around it). X = 0 and 1 are two
; interleaved quads; bit 0 of !BattleFx_QuadSlot makes
; BattleCD_Unk38B2 aim at the second pair of each line.
; Callers note: also the JSL at $CD:24E9 (not matched), after REP #$10
;   with X its quad.
; Callers (2 JSL sites): BattleFx_SwayQuad ($D1:EC5A) and unmatched ($CD:24E9).
; Entry: M=1, X=0, X = the quad, DP=0, DB=$7E (the quads are read .w)
; Exit:  M=1, X=0, DP unchanged, DB restored; A = 0; X and Y clobbered;
;        DP $03-$19 and $45-$4A written; the window table lines written;
;        APU port 3 ($2143) written by BattleFx_RasterQuad's word stores
;        to WMDATA-1 ($217F)
BattleFx_DrawQuad:
    TXA
    STA.w !BattleFx_QuadSlot
    LDA.w !BattleFx_Quads,X
    STA.b !BattleFx_QuadX0
    LDA.w !BattleFx_Quads+2,X
    STA.b !BattleFx_QuadY0
    LDA.w !BattleFx_Quads+4,X
    STA.b !BattleFx_QuadX1
    LDA.w !BattleFx_Quads+6,X
    STA.b !BattleFx_QuadY1
    LDA.w !BattleFx_Quads+8,X
    STA.b !BattleFx_QuadX2
    LDA.w !BattleFx_Quads+10,X
    STA.b !BattleFx_QuadY2
    LDA.w !BattleFx_Quads+12,X
    STA.b !BattleFx_QuadX3
    LDA.w !BattleFx_Quads+14,X
    STA.b !BattleFx_QuadY3
    JSR BattleFx_SortQuadByY
    PHB
    TDC
    PHA
    PLB
    JSR BattleFx_RasterQuad
    PLB
    RTL

; $D1:F9E7 — BattleFx_RasterQuad (385 bytes, $F9E7–$FB67)
; Rasterises the y-sorted quad in DP $12-$19 into the window table
; through the WRAM port: BattleFx_QuadSlopes, then JSL
; BattleCD_Unk38B2 with A = !BattleFx_QuadTop aims WMADD at that line
; of the table, and each line is written as left edge, right edge (the
; integer bytes of two 8.8 edges, written with a 16-bit STA to WMDATA-1
; so the high byte lands in WMDATA), then two 16-bit reads that each
; read WMDATA once and step past the other pair. The edges are stepped
; before each line. $217F (WMDATA-1) mirrors APU port 3 (APUIO3,
; $2143), so each of these word stores also writes A's low byte (the
; edge's fraction) to that port. Each segment clears C once before its
; loop, so the carry out of each edge's ADC feeds the next one (kept as
; found). Three shapes:
;   - y0 = y1 (flat top): points 0/1 and 2/3 put left to right; y2 - y1
;     lines with the left edge from x0 along !BattleFx_Slope02 and the
;     right edge from x1 along !BattleFx_Slope13;
;   - x2 < x1: both edges from x0; left along 0-2 then 2-3, right along
;     0-1 then 1-3 (y1 - y0, y2 - y1 and y3 - y2 lines);
;   - otherwise points 1 and 2 swap first, then left along 0-2, 2-3,
;     right along 0-1, 1-3 with the line counts to match.
; Callers (1 JSR site): BattleFx_DrawQuad ($D1:F9E2).
; Entry: M=1, X=0, B = 0 (from BattleFx_DrawQuad's TDC), DP=0, DB=$00
;        (WMDATA and the divider are absolute)
; Exit:  M=1, X=0; A = 0; X and Y = the last edges (8.8); DP $03-$0F,
;        $45-$4A written; APU port 3 ($2143) written by the word stores
;        to WMDATA-1
BattleFx_RasterQuad:
    LDA.b !BattleFx_QuadY0
    CMP.b !BattleFx_QuadY1
    BNE .middle
    LDA.b !BattleFx_QuadX0
    CMP.b !BattleFx_QuadX1
    BCC .order_bottom
    LDX.b !BattleFx_QuadX0
    LDY.b !BattleFx_QuadX1
    STX.b !BattleFx_QuadX1
    STY.b !BattleFx_QuadX0
.order_bottom:
    LDA.b !BattleFx_QuadX2
    CMP.b !BattleFx_QuadX3
    BCC .flat_top
    LDX.b !BattleFx_QuadX2
    LDY.b !BattleFx_QuadX3
    STX.b !BattleFx_QuadX3
    STY.b !BattleFx_QuadX2
.flat_top:
    JMP .trapezoid
.middle:
    LDA.b !BattleFx_QuadX2
    CMP.b !BattleFx_QuadX1
    BCC .left_bend
    LDX.b !BattleFx_QuadX1
    LDY.b !BattleFx_QuadX2
    STX.b !BattleFx_QuadX2
    STY.b !BattleFx_QuadX1
    JMP .right_bend
.left_bend:
    JSR BattleFx_QuadSlopes
    JMP .left_bend_draw
.right_bend:
    JSR BattleFx_QuadSlopes
    JMP .right_bend_draw
.trapezoid:
    JSR BattleFx_QuadSlopes
    LDA.b !BattleFx_QuadTop
    JSL BattleCD_Unk38B2
    LDA.b !BattleFx_QuadY2
    SEC
    SBC.b !BattleFx_QuadY1
    TAX
    STX.b !BattleCD_Tmp45
    LDA.b !BattleFx_QuadX0
    REP #$21
    XBA
    TAX
    LDA.b !BattleFx_QuadX1
    AND.w #!Battle_LowByteMask
    XBA
    TAY
    LDA.b !BattleCD_Tmp45
    BEQ .trap_done
    CLC
.trap_line:
    TXA
    ADC.b !BattleFx_Slope02
    TAX
    STA.w WMDATA-1                      ; the high byte (the edge) goes to WMDATA
    TYA
    ADC.b !BattleFx_Slope13
    TAY
    STA.w WMDATA-1
    LDA.w WMDATA-1                      ; two reads of WMDATA step past the other pair
    LDA.w WMDATA-1
    DEC.b !BattleCD_Tmp45
    BNE .trap_line
    TDC
.trap_done:
    SEP #$20
    RTS
.left_bend_draw:
    LDA.b !BattleFx_QuadTop
    JSL BattleCD_Unk38B2
    LDA.b !BattleFx_QuadY1
    SEC
    SBC.b !BattleFx_QuadY0
    TAX
    STX.b !BattleCD_Tmp45
    LDA.b !BattleFx_QuadY2
    SEC
    SBC.b !BattleFx_QuadY1
    TAX
    STX.b !BattleCD_Tmp47
    LDA.b !BattleFx_QuadY3
    SEC
    SBC.b !BattleFx_QuadY2
    TAX
    STX.b !BattleCD_Tmp49
    LDA.b !BattleFx_QuadX0
    REP #$20
    XBA
    TAX
    TAY
    LDA.b !BattleCD_Tmp45
    BEQ .lb_part2
    CLC
.lb_seg1:
    TXA
    ADC.b !BattleFx_Slope02
    TAX
    STA.w WMDATA-1
    TYA
    ADC.b !BattleFx_Slope01
    TAY
    STA.w WMDATA-1
    LDA.w WMDATA-1
    LDA.w WMDATA-1
    DEC.b !BattleCD_Tmp45
    BNE .lb_seg1
.lb_part2:
    LDA.b !BattleCD_Tmp47
    BEQ .lb_part3
    CLC
.lb_seg2:
    TXA
    ADC.b !BattleFx_Slope02
    TAX
    STA.w WMDATA-1
    TYA
    ADC.b !BattleFx_Slope13
    TAY
    STA.w WMDATA-1
    LDA.w WMDATA-1
    LDA.w WMDATA-1
    DEC.b !BattleCD_Tmp47
    BNE .lb_seg2
.lb_part3:
    LDA.b !BattleCD_Tmp49
    BEQ .lb_done
    CLC
.lb_seg3:
    TXA
    ADC.b !BattleFx_Slope23
    TAX
    STA.w WMDATA-1
    TYA
    ADC.b !BattleFx_Slope13
    TAY
    STA.w WMDATA-1
    LDA.w WMDATA-1
    LDA.w WMDATA-1
    DEC.b !BattleCD_Tmp49
    BNE .lb_seg3
    TDC
.lb_done:
    SEP #$20
    RTS
.right_bend_draw:
    LDA.b !BattleFx_QuadTop
    JSL BattleCD_Unk38B2
    LDA.b !BattleFx_QuadY2
    SEC
    SBC.b !BattleFx_QuadY0
    TAX
    STX.b !BattleCD_Tmp45
    LDA.b !BattleFx_QuadY1
    SEC
    SBC.b !BattleFx_QuadY2
    TAX
    STX.b !BattleCD_Tmp47
    LDA.b !BattleFx_QuadY3
    SEC
    SBC.b !BattleFx_QuadY1
    TAX
    STX.b !BattleCD_Tmp49
    LDA.b !BattleFx_QuadX0
    REP #$20
    XBA
    TAX
    TAY
    LDA.b !BattleCD_Tmp45
    BEQ .rb_part2
    CLC
.rb_seg1:
    TXA
    ADC.b !BattleFx_Slope02
    TAX
    STA.w WMDATA-1
    TYA
    ADC.b !BattleFx_Slope01
    TAY
    STA.w WMDATA-1
    LDA.w WMDATA-1
    LDA.w WMDATA-1
    DEC.b !BattleCD_Tmp45
    BNE .rb_seg1
.rb_part2:
    LDA.b !BattleCD_Tmp47
    BEQ .rb_part3
    CLC
.rb_seg2:
    TXA
    ADC.b !BattleFx_Slope23
    TAX
    STA.w WMDATA-1
    TYA
    ADC.b !BattleFx_Slope01
    TAY
    STA.w WMDATA-1
    LDA.w WMDATA-1
    LDA.w WMDATA-1
    DEC.b !BattleCD_Tmp47
    BNE .rb_seg2
.rb_part3:
    LDA.b !BattleCD_Tmp49
    BEQ .rb_done
    CLC
.rb_seg3:
    TXA
    ADC.b !BattleFx_Slope23
    TAX
    STA.w WMDATA-1
    TYA
    ADC.b !BattleFx_Slope13
    TAY
    STA.w WMDATA-1
    LDA.w WMDATA-1
    LDA.w WMDATA-1
    DEC.b !BattleCD_Tmp49
    BNE .rb_seg3
    TDC
.rb_done:
    SEP #$20
    RTS

; ============================================================
; Window boxes, fills and copies ($D1:FB68–$D1:FE4B)
; ============================================================

; $D1:FB68 — BattleFx_AddBoxInset (10 bytes, $FB68–$FB71)
; Adds the argument byte to !BattleFx_BoxInset.
; Callers note: the JSL at $CD:1879 is followed by RTS (a bank-$CD
;   script command handler, probably; not matched).
; Callers (1 JSL site): unmatched ($CD:1879).
; Entry: M=1, DP=0 (DP $40 long pointer to the argument), DB=$7E
; Exit:  M=1; A = the new inset; X, Y unchanged
BattleFx_AddBoxInset:
    LDA.w !BattleFx_BoxInset
    CLC
    ADC.b [!BattleCD_FxScriptPtr]
    STA.w !BattleFx_BoxInset
    RTL

; $D1:FB72 — BattleFx_GrowBox (92 bytes, $FB72–$FBCD)
; Adds the argument byte to !BattleFx_BoxHalfHeight (h), then sets the
; first pair of lines !BattleFx_BoxCentre ($6A, line 106) - h to $6A + h
; - 1 of this frame's window table to left = !BattleFx_BoxInset, right =
; 255 - !BattleFx_BoxInset: a box centred on line 106. Nothing when h
; is 0. The table-0 path loads !BattleFx_WinFull and at once overwrites
; it (a dead load, kept as found).
; Callers note: the JSL at $CD:1874 is followed by RTS (a bank-$CD
;   script command handler, probably; not matched).
; Callers (1 JSL site): unmatched ($CD:1874).
; Entry: M=1, X=0, DP=0 (DP $40 long pointer to the argument), DB=$7E;
;        B = 0 assumed ((line * 4) is formed 16-bit after the 8-bit
;        subtraction; not traced at the caller)
; Exit:  M=1, X=0, DP and DB unchanged; A = 0; X clobbered; Y unchanged;
;        DP $45/$46, $49, $4A written
BattleFx_GrowBox:
    LDA.w !BattleFx_BoxHalfHeight
    CLC
    ADC.b [!BattleCD_FxScriptPtr]
    STA.w !BattleFx_BoxHalfHeight
    LDA.w !BattleFx_BoxInset
    STA.b !BattleCD_Tmp49
    EOR.b #!Battle_Invert8
    STA.b !BattleFx_Tmp4A
    LDA.w !BattleFx_BoxHalfHeight
    CLC
    ADC.b #!BattleFx_BoxCentre
    STA.b !BattleCD_Tmp45
    LDA.b #!BattleFx_BoxCentre
    SEC
    SBC.w !BattleFx_BoxHalfHeight
    REP #$20
    ASL A
    ASL A
    TAX
    LDA.b !BattleCD_Tmp45
    AND.w #!Battle_LowByteMask
    ASL A
    ASL A
    STA.b !BattleCD_Tmp45
    CPX.b !BattleCD_Tmp45
    BEQ .done
    LDA.b !Battle_FrameCount
    AND.w #$0001
    BEQ .buffer0
    LDA.b !BattleCD_Tmp49
.line_buf1:
    STA.w !BattleFx_WinTable1,X
    INX
    INX
    INX
    INX
    CPX.b !BattleCD_Tmp45
    BNE .line_buf1
    BRA .done
.buffer0:
    LDA.w #!BattleFx_WinFull            ; dead load: overwritten at once (kept as found)
    LDA.b !BattleCD_Tmp49
.line_buf0:
    STA.w !BattleFx_WinTable0,X
    INX
    INX
    INX
    INX
    CPX.b !BattleCD_Tmp45
    BNE .line_buf0
.done:
    TDC
    SEP #$20
    RTL

; $D1:FBCE — BattleFx_FillWindow (4 bytes, $FBCE–$FBD1)
; Runs BattleFx_FillTable's handler X: 0 all empty, 2 first pairs empty,
; 4 second pairs empty, 6 first pairs full (in this frame's table).
; Callers note: the only caller, $CD:29DE (not matched), passes X = the
;   argument byte * 2 (LDA [$40] / ASL / TAX).
; Callers (1 JSL site): unmatched ($CD:29DE).
; Entry: M=1, X=0, X = 0, 2, 4 or 6, DP=0, DB=$7E
; Exit:  as the handler: M=1, X=0; A = its fill word's low byte (B the
;        high byte); X = 0; Y's low byte kept, high byte cleared
BattleFx_FillWindow:
    JSR (BattleFx_FillTable,X)
    RTL

; $D1:FBD2 — BattleFx_FillTable (8 bytes, $FBD2–$FBD9)
; BattleFx_FillWindow's handlers, by X = 0, 2, 4, 6.
BattleFx_FillTable:
    dw BattleFx_FillAllEmpty            ; 0
    dw BattleFx_FillWin1Empty           ; 2
    dw BattleFx_FillWin2Empty           ; 4
    dw BattleFx_FillWin1Full            ; 6

; $D1:FBDA — BattleFx_FillWin1Full (94 bytes, $FBDA–$FC37)
; Sets the first pair of lines 0-223 of this frame's window table to
; !BattleFx_WinFull (left 0, right 255): eight blocks of 28 lines, X
; from $70 down to 4.
; Callers note: BattleFx_FillTable entry 6.
; Entry: M=1, X=0, DP=0 (DP $7C), DB=$7E
; Exit:  M=1, X=0 (REP #$10); A = $00 and B = $FF; X = 0; Y's low byte
;        kept, high byte cleared (SEP #$10)
BattleFx_FillWin1Full:
    LDA.b !Battle_FrameCount
    AND.b #$01
    BEQ .buffer0
    REP #$20
    SEP #$10
    LDX.b #!BattleFx_WinBlockBytes
    LDA.w #!BattleFx_WinFull
.line_buf1:
    STA.w !BattleFx_WinTable0+892,X
    STA.w !BattleFx_WinTable1+108,X
    STA.w !BattleFx_WinTable1+220,X
    STA.w !BattleFx_WinTable1+332,X
    STA.w !BattleFx_WinTable1+444,X
    STA.w !BattleFx_WinTable1+556,X
    STA.w !BattleFx_WinTable1+668,X
    STA.w !BattleFx_WinTable1+780,X
    DEX
    DEX
    DEX
    DEX
    BNE .line_buf1
    REP #$10
    SEP #$20
    RTS
.buffer0:
    REP #$20
    SEP #$10
    LDX.b #!BattleFx_WinBlockBytes
    LDA.w #!BattleFx_WinFull
.line_buf0:
    STA.w !BattleFx_WinTable0-4,X
    STA.w !BattleFx_WinTable0+108,X
    STA.w !BattleFx_WinTable0+220,X
    STA.w !BattleFx_WinTable0+332,X
    STA.w !BattleFx_WinTable0+444,X
    STA.w !BattleFx_WinTable0+556,X
    STA.w !BattleFx_WinTable0+668,X
    STA.w !BattleFx_WinTable0+780,X
    DEX
    DEX
    DEX
    DEX
    BNE .line_buf0
    REP #$10
    SEP #$20
    RTS

; $D1:FC38 — BattleFx_FillWin1Empty (94 bytes, $FC38–$FC95)
; Sets the first pair of lines 0-223 of this frame's window table to
; !BattleFx_WinEmpty (left 255, right 0).
; Callers note: BattleFx_FillTable entry 2.
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0; A = $FF and B = $00; X = 0; Y's low byte kept, high
;        byte cleared (SEP #$10)
BattleFx_FillWin1Empty:
    LDA.b !Battle_FrameCount
    AND.b #$01
    BEQ .buffer0
    REP #$20
    SEP #$10
    LDX.b #!BattleFx_WinBlockBytes
    LDA.w #!BattleFx_WinEmpty
.line_buf1:
    STA.w !BattleFx_WinTable0+892,X
    STA.w !BattleFx_WinTable1+108,X
    STA.w !BattleFx_WinTable1+220,X
    STA.w !BattleFx_WinTable1+332,X
    STA.w !BattleFx_WinTable1+444,X
    STA.w !BattleFx_WinTable1+556,X
    STA.w !BattleFx_WinTable1+668,X
    STA.w !BattleFx_WinTable1+780,X
    DEX
    DEX
    DEX
    DEX
    BNE .line_buf1
    REP #$10
    SEP #$20
    RTS
.buffer0:
    REP #$20
    SEP #$10
    LDX.b #!BattleFx_WinBlockBytes
    LDA.w #!BattleFx_WinEmpty
.line_buf0:
    STA.w !BattleFx_WinTable0-4,X
    STA.w !BattleFx_WinTable0+108,X
    STA.w !BattleFx_WinTable0+220,X
    STA.w !BattleFx_WinTable0+332,X
    STA.w !BattleFx_WinTable0+444,X
    STA.w !BattleFx_WinTable0+556,X
    STA.w !BattleFx_WinTable0+668,X
    STA.w !BattleFx_WinTable0+780,X
    DEX
    DEX
    DEX
    DEX
    BNE .line_buf0
    REP #$10
    SEP #$20
    RTS

; $D1:FC96 — BattleFx_FillWin2Empty (94 bytes, $FC96–$FCF3)
; Sets the second pair of lines 0-223 of this frame's window table to
; !BattleFx_WinEmpty.
; Callers note: BattleFx_FillTable entry 4.
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0; A = $FF and B = $00; X = 0; Y's low byte kept, high
;        byte cleared (SEP #$10)
BattleFx_FillWin2Empty:
    LDA.b !Battle_FrameCount
    AND.b #$01
    BEQ .buffer0
    REP #$20
    SEP #$10
    LDX.b #!BattleFx_WinBlockBytes
    LDA.w #!BattleFx_WinEmpty
.line_buf1:
    STA.w !BattleFx_WinTable0+894,X
    STA.w !BattleFx_WinTable1+110,X
    STA.w !BattleFx_WinTable1+222,X
    STA.w !BattleFx_WinTable1+334,X
    STA.w !BattleFx_WinTable1+446,X
    STA.w !BattleFx_WinTable1+558,X
    STA.w !BattleFx_WinTable1+670,X
    STA.w !BattleFx_WinTable1+782,X
    DEX
    DEX
    DEX
    DEX
    BNE .line_buf1
    REP #$10
    SEP #$20
    RTS
.buffer0:
    REP #$20
    SEP #$10
    LDX.b #!BattleFx_WinBlockBytes
    LDA.w #!BattleFx_WinEmpty
.line_buf0:
    STA.w !BattleFx_WinTable0-2,X
    STA.w !BattleFx_WinTable0+110,X
    STA.w !BattleFx_WinTable0+222,X
    STA.w !BattleFx_WinTable0+334,X
    STA.w !BattleFx_WinTable0+446,X
    STA.w !BattleFx_WinTable0+558,X
    STA.w !BattleFx_WinTable0+670,X
    STA.w !BattleFx_WinTable0+782,X
    DEX
    DEX
    DEX
    DEX
    BNE .line_buf0
    REP #$10
    SEP #$20
    RTS

; $D1:FCF4 — BattleFx_FillAllEmpty (138 bytes, $FCF4–$FD7D)
; Sets both pairs of lines 0-223 of this frame's window table to
; !BattleFx_WinEmpty: sixteen blocks of 14 lines, X from $38 down to 2
; in steps of 2 (every word).
; Callers note: BattleFx_FillTable entry 0.
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0; A = $FF and B = $00; X = 0; Y's low byte kept, high
;        byte cleared (SEP #$10)
BattleFx_FillAllEmpty:
    LDA.b !Battle_FrameCount
    AND.b #$01
    BEQ .buffer0
    REP #$20
    SEP #$10
    LDX.b #!BattleFx_WinBlockBytes/2
    LDA.w #!BattleFx_WinEmpty
.word_buf1:
    STA.w !BattleFx_WinTable0+894,X
    STA.w !BattleFx_WinTable1+54,X
    STA.w !BattleFx_WinTable1+110,X
    STA.w !BattleFx_WinTable1+166,X
    STA.w !BattleFx_WinTable1+222,X
    STA.w !BattleFx_WinTable1+278,X
    STA.w !BattleFx_WinTable1+334,X
    STA.w !BattleFx_WinTable1+390,X
    STA.w !BattleFx_WinTable1+446,X
    STA.w !BattleFx_WinTable1+502,X
    STA.w !BattleFx_WinTable1+558,X
    STA.w !BattleFx_WinTable1+614,X
    STA.w !BattleFx_WinTable1+670,X
    STA.w !BattleFx_WinTable1+726,X
    STA.w !BattleFx_WinTable1+782,X
    STA.w !BattleFx_WinTable1+838,X
    DEX
    DEX
    BNE .word_buf1
    REP #$10
    SEP #$20
    RTS
.buffer0:
    REP #$20
    SEP #$10
    LDX.b #!BattleFx_WinBlockBytes/2
    LDA.w #!BattleFx_WinEmpty
.word_buf0:
    STA.w !BattleFx_WinTable0-2,X
    STA.w !BattleFx_WinTable0+54,X
    STA.w !BattleFx_WinTable0+110,X
    STA.w !BattleFx_WinTable0+166,X
    STA.w !BattleFx_WinTable0+222,X
    STA.w !BattleFx_WinTable0+278,X
    STA.w !BattleFx_WinTable0+334,X
    STA.w !BattleFx_WinTable0+390,X
    STA.w !BattleFx_WinTable0+446,X
    STA.w !BattleFx_WinTable0+502,X
    STA.w !BattleFx_WinTable0+558,X
    STA.w !BattleFx_WinTable0+614,X
    STA.w !BattleFx_WinTable0+670,X
    STA.w !BattleFx_WinTable0+726,X
    STA.w !BattleFx_WinTable0+782,X
    STA.w !BattleFx_WinTable0+838,X
    DEX
    DEX
    BNE .word_buf0
    REP #$10
    SEP #$20
    RTS

; $D1:FD7E — BattleFx_MirrorWin1ToWin2 (206 bytes, $FD7E–$FE4B)
; Like BattleFx_CopyWin1ToWin2 (first pairs of the other table into the
; second pairs of this frame's table), but mirrored left to right (the
; word is inverted and its bytes swapped: left = 255 - right, right =
; 255 - left), and for 28 lines of each of the eight 28-line blocks
; starting at byte offset X = the argument byte * 2 (8-bit) in the
; block: line offset 0-27 for an argument of 0.
; Callers note: the JSL at $CD:1AE1 is followed by RTS (a bank-$CD
;   script command handler, probably; not matched).
; Callers (1 JSL site): unmatched ($CD:1AE1).
; Entry: M=1, X=0, DP=0 (DP $40 long pointer to the argument, DP $45),
;        DB=$7E; B does not matter (X is cut to 8 bits before use)
; Exit:  M=1, X=0 (REP #$10), DP and DB unchanged; A = 0; X = the end
;        offset; Y's low byte kept, high byte cleared (SEP #$10); DP
;        $45/$46 written
BattleFx_MirrorWin1ToWin2:
    LDA.b [!BattleCD_FxScriptPtr]
    ASL A
    TAX
    REP #$20
    SEP #$10
    TXA
    CLC
    ADC.w #!BattleFx_WinBlockBytes
    STA.b !BattleCD_Tmp45
    LDA.b !Battle_FrameCount
    AND.w #$0001
    BEQ .line_buf0
.line_buf1:
    LDA.w !BattleFx_WinTable0,X
    EOR.w #!Battle_Invert16
    XBA
    STA.w !BattleFx_WinTable1+2,X
    LDA.w !BattleFx_WinTable0+112,X
    EOR.w #!Battle_Invert16
    XBA
    STA.w !BattleFx_WinTable1+114,X
    LDA.w !BattleFx_WinTable0+224,X
    EOR.w #!Battle_Invert16
    XBA
    STA.w !BattleFx_WinTable1+226,X
    LDA.w !BattleFx_WinTable0+336,X
    EOR.w #!Battle_Invert16
    XBA
    STA.w !BattleFx_WinTable1+338,X
    LDA.w !BattleFx_WinTable0+448,X
    EOR.w #!Battle_Invert16
    XBA
    STA.w !BattleFx_WinTable1+450,X
    LDA.w !BattleFx_WinTable0+560,X
    EOR.w #!Battle_Invert16
    XBA
    STA.w !BattleFx_WinTable1+562,X
    LDA.w !BattleFx_WinTable0+672,X
    EOR.w #!Battle_Invert16
    XBA
    STA.w !BattleFx_WinTable1+674,X
    LDA.w !BattleFx_WinTable0+784,X
    EOR.w #!Battle_Invert16
    XBA
    STA.w !BattleFx_WinTable1+786,X
    INX
    INX
    INX
    INX
    CPX.b !BattleCD_Tmp45
    BNE .line_buf1
    BRA .done
.line_buf0:
    LDA.w !BattleFx_WinTable1,X
    EOR.w #!Battle_Invert16
    XBA
    STA.w !BattleFx_WinTable0+2,X
    LDA.w !BattleFx_WinTable1+112,X
    EOR.w #!Battle_Invert16
    XBA
    STA.w !BattleFx_WinTable0+114,X
    LDA.w !BattleFx_WinTable1+224,X
    EOR.w #!Battle_Invert16
    XBA
    STA.w !BattleFx_WinTable0+226,X
    LDA.w !BattleFx_WinTable1+336,X
    EOR.w #!Battle_Invert16
    XBA
    STA.w !BattleFx_WinTable0+338,X
    LDA.w !BattleFx_WinTable1+448,X
    EOR.w #!Battle_Invert16
    XBA
    STA.w !BattleFx_WinTable0+450,X
    LDA.w !BattleFx_WinTable1+560,X
    EOR.w #!Battle_Invert16
    XBA
    STA.w !BattleFx_WinTable0+562,X
    LDA.w !BattleFx_WinTable1+672,X
    EOR.w #!Battle_Invert16
    XBA
    STA.w !BattleFx_WinTable0+674,X
    LDA.w !BattleFx_WinTable1+784,X
    EOR.w #!Battle_Invert16
    XBA
    STA.w !BattleFx_WinTable0+786,X
    INX
    INX
    INX
    INX
    CPX.b !BattleCD_Tmp45
    BNE .line_buf0
.done:
    TDC
    SEP #$20
    REP #$10
    RTL

; ============================================================
; The IRQ handler and its helpers ($D1:FE4C–$D1:FEF3)
; ============================================================

; $D1:FE4C — BattleFx_ReloadCeSet (37 bytes, $FE4C–$FE70)
; When !BattleFx_CeSetWant differs from !BattleFx_CeSet (which then
; takes it), or else when !BattleFx_CeSetReload is set: JSL
; BattleCE_UnkEE6E with A = !BattleFx_CeSetBase + !BattleFx_CeSet +
; !Battle_MsgShown, and !BattleFx_CeSetReload = 0. What the sets are
; is not traced (BattleCE_UnkEE6E copies records from bank $CE to
; $7E:C867 on; not analysed).
; Callers (1 JSR site): BattleFx_Irq ($D1:FECE).
; Entry: M=1, X=0, DP=0, DB=$7E (BattleFx_Irq sets it just before)
; Exit:  M=1; A, X and Y clobbered on the reload path (as
;        BattleCE_UnkEE6E leaves them), else A = the flag tested
BattleFx_ReloadCeSet:
    LDA.w !BattleFx_CeSetWant
    CMP.w !BattleFx_CeSet
    BEQ .same
    STA.w !BattleFx_CeSet
    BRA .reload
.same:
    LDA.w !BattleFx_CeSetReload
    BEQ .done
.reload:
    LDA.w !BattleFx_CeSetBase
    CLC
    ADC.w !BattleFx_CeSet
    CLC
    ADC.w !Battle_MsgShown
    JSL BattleCE_UnkEE6E
    STZ.w !BattleFx_CeSetReload
.done:
    RTS

; $D1:FE71 — BattleFx_RestoreMathRegs (38 bytes, $FE71–$FE96)
; Writes the math unit's operands again from their mirrors: the
; dividend and divisor (!Battle_DivMirrorLo/Hi/Divisor, which restarts
; the division) when !Battle_DivBusy is set, else the two factors
; (!Battle_MulMirrorA/B, restarting the multiply). The interrupt
; handlers run it before they return, probably so that code they
; interrupted between starting a multiply or divide and reading it still
; gets its own result (the mirrors are written by the battle's multiply
; and divide routines).
; Callers (2 JSL sites): BattleFx_Nmi ($D1:E841) and BattleFx_Irq ($D1:FEE6).
; Entry: M=1, DP=0 (the mirrors), DB any (everything else is long)
; Exit:  M=1; A = the last mirror written; X, Y, DP and DB unchanged
BattleFx_RestoreMathRegs:
    LDA.l (!Bank7E<<16)|!Battle_DivBusy
    BEQ .multiply
    LDA.b !Battle_DivMirrorLo
    STA.l WRDIVL
    LDA.b !Battle_DivMirrorHi
    STA.l WRDIVH
    LDA.b !Battle_DivMirrorDivisor
    STA.l WRDIVB
    RTL
.multiply:
    LDA.b !Battle_MulMirrorA
    STA.l WRMPYA
    LDA.b !Battle_MulMirrorB
    STA.l WRMPYB
    RTL

; $D1:FE97 — BattleFx_Irq (93 bytes, $FE97–$FEF3)
; The battle's IRQ handler while this engine runs: BattleFx_Init writes
; JML $D1:FE97 into !IrqTrampoline and sets the V-count IRQ at line
; !BattleFx_IrqLine (211). It saves A, X, Y, DB and DP, sets DP=0,
; counts !BattleFx_IntBusy up (BattleFx_Nmi does nothing while it is
; set), reads TIMEUP, writes !NMITIMEN_NmiAutoJoy (no more V-count IRQ
; until BattleFx_Nmi writes !Nmi_Nmitimen again), then with DB=$00 turns
; HDMA off, waits for H-blank and forces blank from there on. On frames
; with bit 0 of !Battle_FrameCount clear it runs BattleFx_ReloadCeSet
; (with DB=$7E); on the others, unless !Battle_Paused, JSL FdVec_FFFD
; (FieldFD_UploadTileAnims) with P saved. Then DP=0 again, M=1,
; BattleFx_RestoreMathRegs, !BattleFx_IntBusy = 0, and it returns.
; Callers note: no call site; reached through !IrqTrampoline.
; Entry: an IRQ; any M, X, DP and DB (it sets M=0, X=0, then M=1, DP=0
;        and DB itself; the interrupted DP and DB are saved)
; Exit:  RTI with A, X, Y (16-bit), DB, DP and P restored
BattleFx_Irq:
    REP #$30
    PHA
    PHX
    PHY
    PHB
    PHD
    LDA.w #$0000
    TCD
    SEP #$20
    INC.b !BattleFx_IntBusy
    REP #$10
    LDA.l TIMEUP                        ; acknowledge the IRQ
    LDA.b #!NMITIMEN_NmiAutoJoy
    STA.l NMITIMEN
    TDC
    PHA
    PLB
    STA.w HDMAEN
.wait_hblank:
    LDA.w HVBJOY
    AND.b #!HVBJOY_HBlank
    BEQ .wait_hblank
    LDA.b #!INIDISP_ForceBlank
    STA.w INIDISP
    LDA.b !Battle_FrameCount
    AND.b #$01
    BNE .buffer1
    LDA.b #!Bank7E
    PHA
    PLB
    JSR BattleFx_ReloadCeSet
    BRA .math
.buffer1:
    LDA.l (!Bank7E<<16)|!Battle_Paused
    BNE .math
    PHP
    JSL FdVec_FFFD                      ; FieldFD_UploadTileAnims
    PLP
.math:
    LDX.w #$0000
    PHX
    PLD
    SEP #$20
    JSL BattleFx_RestoreMathRegs
    STZ.b !BattleFx_IntBusy
    REP #$30
    PLD
    PLB
    PLY
    PLX
    PLA
    RTI

; $D1:FEF4 — BankD1_EndFill (268 bytes, $FEF4–$FFFF)
; $FF fill after the last routine, to the end of the bank. No reference
; found.
BankD1_EndFill:
    db $FF
    fillbyte $FF
    fill $D20000-$D1FEF5
