; ============================================================
; Bank $C6 — scene data, and scene routines the scene scripts call
; File offset 0x060000 (bank $C6 = ROM offset $060000)
;
; Most of bank $C6 is data for the scene mode of bank $C2 (left as ROM
; bytes): packed graphics, maps and palettes, the scene headers
; (C2SceneRom_HeaderTable, $C6:FD00), the pack tables C2SceneRom_*Packs
; ($C6:FDF0-$FFFF) and the tables the matched bank-$C2 code reads at
; $C6:F400 on (label strings, the map view's tiles and palette, the zoom
; divisors, object A's palettes, the random velocities, the dial's
; picture).
;
; $C6:E000-$C6:EE42 is code, then $00 fill. Two entries are called by
; JSL from bank $C2 (BankC6_UnkE74E from C2Scene_ObjBFly,
; BankC6_UnkE797 from C2Scene_ObjAFly; their stub names are kept because
; that code calls them so); the others are script routines: scene
; script op $4E (C2Script_CallLong) calls them by a long address, with
; M=1 and X=0, from inside C2Scene_TaskRunAll (the scene NMI), so with
; DP=$0000, DB=$00 and C2Scene_TaskCur = the task running the script;
; they end with RTL. The op $4E sites are in the scene scripts
; C2Scene_LoadScript unpacks: C2SceneRom_ScriptPacks entries 0-7 (packed
; at $C3:8B6C, $C3:97D7, $C3:9F41, $C3:A607, $C3:AC3E, $C3:BA14,
; $C3:BF7B and $C3:C805); a header's "pack n +$xxxx" is the op's offset
; in the unpacked script (the bytes are split by the packing, so no ROM
; address holds them). One routine has no site in these scripts
; (C6Scene_Bg2VNudge).
;
; The routines set up the scene's HDMA effects (the C2Scene_HdmaTable
; records, two runs of 112 lines in indirect mode, whose addresses the
; NMI copies from C2Scene_HdmaValues): window shapes through the bank $C3
; window routines, colour gradients, a BG1 line wave and a per-line
; Mode 7 matrix; they unpack graphics and palettes, move tasks and
; scroll layers, and draw a Mode 7 picture of the scene's maps. Several
; are byte-identical copies of each other (the headers say which).
; ============================================================

arch snes.cpu
hirom

org $C6E000

; ============================================================
; HDMA set-ups, unpacks and gradients ($C6:E000–$C6:E2B4)
; ============================================================

; $C6:E000 — C6Scene_Win1HdmaOn (40 bytes, $E000–$E027)
; Script routine (pack 1 +$05C3): sets up C2Scene_HdmaTable[0] (two runs
; of 112 lines) as HDMA channel 1 to WH0/WH1 (indirect, two registers)
; and turns the channel on: the set-up part of C2Scene_Win1Init, without
; its buffer toggle and table build. C6Scene_Win1HdmaOnB ($C6:E318) and
; C6Scene_Win1HdmaOnC ($C6:E448) are byte-identical copies.
; Entry: M=1 (8-bit stores), X=0 (the 16-bit STYs write DMAP1 with
;        BBAD1 and A1T1L with A1T1H), DP=$0000 (TDC as zero,
;        C2Scene_HdmaenShadow), DB=$00 (the DMA registers .w)
; Exit:  M=1, X=0; A = DMA_CH1; Y = C2Scene_HdmaTable[0]'s address; X
;        unchanged; DB unchanged
; No calls.
C6Scene_Win1HdmaOn:
    LDA.b #!C2Scene_HdmaRun112
    STA.l C2Scene_HdmaTable[0].Count0
    STA.l C2Scene_HdmaTable[0].Count1
    TDC
    STA.l C2Scene_HdmaTable[0].End
    LDY.w #(!BBAD_WH0<<8)|!DMAP_HdmaIndirect|DMA_MODE_2BYTE
    STY.w DMAP1
    LDY.w #C2Scene_HdmaTable[0].Count0&$FFFF
    STY.w A1T1L
    LDA.b #!Bank7E
    STA.w A1B1
    STA.w DAS1B                         ; bank of the indirect addresses
    LDA.b #DMA_CH1
    TSB.b !C2Scene_HdmaenShadow
    RTL

; $C6:E028 — C6Scene_UnpackObjPackA (37 bytes, $E028–$E04C)
; Script routine (pack 0 +$11FD, pack 2 +$0295 and +$08A0, pack 3
; +$02F8, pack 4 +$0D1D and +$112C, pack 5 +$020F and +$02BA, pack 6
; +$0A15): unpacks entry C6Scene_ObjPackA of C2SceneRom_ObjPacks into
; C2Scene_DecompBuf, as C2Scene_LoadExtraObjPack does with its entry. In
; pack 0 the op after it (op $03, $7F:9000) uploads the buffer.
; Entry: M=1 (8-bit bank stores), X=0 (16-bit LDX/STX), DP any (no
;        direct page), DB=$00 (Menu_Decomp* .w)
; Exit:  M=1, X=0 (Decomp_ToWram restores P, A, X and Y); A = the pack's
;        bank byte (B = the high byte of its address); X = the entry's
;        offset; Y unchanged; Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C6Scene_UnpackObjPackA:
    LDX.w #!C2Scene_DecompBuf&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_DecompBuf)
    STA.w !Menu_DecompDestBank
    LDX.w #!C6Scene_ObjPackA*!C2Scene_PackEntrySize
    REP #$20
    LDA.l !C2SceneRom_ObjPacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_ObjPacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
    RTL

; $C6:E04D — C6Scene_UnpackPalPackA (37 bytes, $E04D–$E071)
; Script routine (right after C6Scene_UnpackObjPackA in each of its
; scripts: pack 0 +$120D, pack 2 +$02A5 and +$08B0, pack 3 +$0308, pack
; 4 +$0D3D and +$113C, pack 5 +$021F and +$02CA, pack 6 +$0A25): unpacks
; entry C6Scene_PalPackA of C2SceneRom_PalettePacks into
; C2Scene_PaletteStage.
; Entry: M=1, X=0, DP any (no direct page), DB=$00 (Menu_Decomp* .w)
; Exit:  M=1, X=0 (Decomp_ToWram restores P, A, X and Y); A = the pack's
;        bank byte (B = the high byte of its address); X = the entry's
;        offset; Y unchanged; Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C6Scene_UnpackPalPackA:
    LDX.w #!C2Scene_PaletteStage&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_PaletteStage)
    STA.w !Menu_DecompDestBank
    LDX.w #!C6Scene_PalPackA*!C2Scene_PackEntrySize
    REP #$20
    LDA.l !C2SceneRom_PalettePacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_PalettePacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
    RTL

; $C6:E072 — C6Scene_FadeGradInit (143 bytes, $E072–$E100)
; Script routine (pack 3 +$031E): a fade from white. Sets up
; C2Scene_HdmaTable[0] (two runs of 112 lines) as HDMA channel 1 to
; COLDATA (indirect, one register, one byte a line), turns it on, points
; C2Scene_HdmaValues words 0-1 at C6Scene_FadeGrad and 112 bytes on, and
; fills C6Scene_FadeGrad: 224 bytes of C6Scene_GradFull (all three
; channels at 31), then 30 steps of 8 lines going down from intensity 30
; to 1 (C6Scene_GradFirstStep down), then 224 bytes of COLDATA_AllZero:
; $2B0 bytes, $7E:8B56-$8E05 (C2Scene_HandBufA's area on). Each value is
; stored as a word and spread by an overlapping MVN (the zero high byte
; is overwritten). C6Scene_FadeGradStep then moves both addresses 8
; lines on each frame (pack 3 runs it 58 times), so the gradient climbs
; the screen and leaves it dark. That COLDATA is added to the picture
; (CGADSUB) is not traced here.
; Entry: M any (SEP #$20 here), X=0 (16-bit index and MVN counts),
;        DP=$0000 (TDC as zero; C2Tmp_00/02/08, C2Scene_HdmaenShadow),
;        DB=$00 (the DMA registers .w; saved around the MVNs)
; Exit:  M=0, X=0; A = $FFFF, X = $8E05, Y = $8E06 (the last MVN's
;        ends); DB unchanged; C2Tmp_00 = $00E0, C2Tmp_02 = 0, C2Tmp_08 =
;        $8D26 (words)
; No calls.
!C6Scene_GradLevel = !C2Tmp_00         ; 16-bit COLDATA value of the step being written
!C6Scene_GradStepsLeft = !C2Tmp_02     ; 16-bit steps left
!C6Scene_GradOut = !C2Tmp_08           ; 16-bit address of the step's first line (bank $7E)
C6Scene_FadeGradInit:
    SEP #$20
    LDA.b #!C2Scene_HdmaRun112
    STA.l C2Scene_HdmaTable[0].Count0
    STA.l C2Scene_HdmaTable[0].Count1
    TDC
    STA.l C2Scene_HdmaTable[0].End
    LDY.w #(!BBAD_COLDATA<<8)|!DMAP_HdmaIndirect
    STY.w DMAP1
    LDY.w #C2Scene_HdmaTable[0].Count0&$FFFF
    STY.w A1T1L
    LDA.b #!Bank7E
    STA.w A1B1
    STA.w DAS1B
    LDA.b #DMA_CH1
    TSB.b !C2Scene_HdmaenShadow
    REP #$20
    LDA.w #!C6Scene_FadeGrad&$FFFF
    STA.l !C2Scene_HdmaValues
    LDA.w #(!C6Scene_FadeGrad+!C6Scene_GradRunBytes)&$FFFF
    STA.l !C2Scene_HdmaValues+2
    PHB
    LDA.w #!C6Scene_GradFull
    STA.l !C6Scene_FadeGrad
    LDX.w #!C6Scene_FadeGrad&$FFFF
    LDY.w #(!C6Scene_FadeGrad+1)&$FFFF
    LDA.w #!C6Scene_GradScreenBytes-2
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDA.w #!C6Scene_GradFirstStep
    STA.b !C6Scene_GradLevel
    LDA.w #!C6Scene_FadeGradSteps&$FFFF
    STA.b !C6Scene_GradOut
    LDA.w #!C6Scene_GradSteps
    STA.b !C6Scene_GradStepsLeft
.step:
    LDX.b !C6Scene_GradOut
    LDA.b !C6Scene_GradLevel
    STA.l !Eng_PtrBase|(!Bank7E<<16),X
    TXY
    INY
    LDA.w #!C6Scene_GradStepLines-2
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDA.b !C6Scene_GradOut
    CLC
    ADC.w #!C6Scene_GradStepLines
    STA.b !C6Scene_GradOut
    DEC.b !C6Scene_GradLevel
    DEC.b !C6Scene_GradStepsLeft
    BNE .step
    LDA.w #!COLDATA_AllZero
    STA.l !C6Scene_FadeGradDark
    LDX.w #!C6Scene_FadeGradDark&$FFFF
    LDY.w #(!C6Scene_FadeGradDark+1)&$FFFF
    LDA.w #!C6Scene_GradScreenBytes-2
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    RTL

; $C6:E101 — C6Scene_PlaceOnEdgeRandom (111 bytes, $E101–$E16F)
; Script routine (pack 3 +$05CB): puts the task on the edge of a shape
; drawn as a table of 2-byte line entries (left edge, right edge, by the
; use; pack 3 sets C2Tmp_10-$12 to $7E:9176 with op $13 just before,
; and .Var22 to 4). Takes two RandomTable bytes at C2Scene_Unk1B30 (which
; goes up by 2): with the first, r = byte x .Var22 / 256 (WRMPYA/B),
; rounded up when the product's low byte has bit 7 set and then lowered
; by one when it reached .Var22, so 0 to .Var22 - 1; .SprY = r +
; C6Scene_EdgeLineBase. .SprX is the left edge (second byte's bit 7
; clear) or the right edge (set) of the table entry .SprY - 8.
; Entry: M=1 (8-bit loads and multiply; op $4E calls it so), X any
;        (SEP #$10, then REP #$10 here), DP=$0000 (C2Tmp_00/08/10, C2Scene_TaskCur), DB=$00 (the record,
;        C2Scene_Unk1B30, the multiplier .w); C2Tmp_10-$12 = the table
; Exit:  M=0, X=0; X = the task; Y = C2Tmp_08; A = the new .SprX;
;        C2Tmp_00 = the second random byte (8-bit),
;        C2Tmp_08 = (.SprY - 8) x 2 (word); C2Scene_Unk1B30 + 2
; No calls.
!C6Scene_EdgeRand = !C2Tmp_00          ; 8-bit: the second random byte (bit 7: right edge)
!C6Scene_EdgeOfs = !C2Tmp_08           ; 16-bit byte offset of the line's entry
!C6Scene_EdgeTable = !C2Tmp_10         ; 24-bit: the line table (input)
C6Scene_PlaceOnEdgeRandom:
    SEP #$10
    LDX.w !C2Scene_Unk1B30
    LDA.l RandomTable+1,X
    STA.b !C6Scene_EdgeRand
    LDA.l RandomTable,X
    INX
    INX
    STX.w !C2Scene_Unk1B30
    REP #$10
    STA.w WRMPYA
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_EffectTask.Var22,X
    STA.w WRMPYB
    NOP                                 ; the multiplier's 8 cycles
    NOP
    NOP
    LDA.w RDMPYL
    BMI .round_up
    LDA.w RDMPYH
    BRA .clamp
.round_up:
    LDA.w RDMPYH
    INC A
.clamp:
    CMP.w C2Scene_EffectTask.Var22,X
    BCC .line_ok
    DEC A                               ; rounded up to .Var22: one back
.line_ok:
    REP #$20
    AND.w #!Eng_LowByteMask
    CLC
    ADC.w #!C6Scene_EdgeLineBase
    STA.w C2Scene_Task.SprY,X
    SEC
    SBC.w #!C6Scene_EdgeLineOfs
    ASL A
    STA.b !C6Scene_EdgeOfs
    LDA.b !C6Scene_EdgeRand
    REP #$20
    BIT.w #!C6Scene_EdgeRightBit
    BNE .right
    LDY.b !C6Scene_EdgeOfs
    LDX.b !C2Scene_TaskCur
    LDA.b [!C6Scene_EdgeTable],Y
    AND.w #!Eng_LowByteMask             ; the left edge
    STA.w C2Scene_Task.SprX,X
    RTL
.right:
    LDY.b !C6Scene_EdgeOfs
    LDX.b !C2Scene_TaskCur
    LDA.b [!C6Scene_EdgeTable],Y
    XBA
    AND.w #!Eng_LowByteMask             ; the right edge
    STA.w C2Scene_Task.SprX,X
    RTL

; $C6:E170 — C6Scene_Grad2Init (143 bytes, $E170–$E1FE)
; Script routine (pack 4 +$02CE): sets up C2Scene_HdmaTable[1] (two
; runs of 112 lines) as HDMA channel 2 to COLDATA (indirect, one
; register), turns it on, points C2Scene_HdmaValues words 2-3 at
; C6Scene_Grad2 and 112 bytes on, and fills it: 112 bytes of
; C6Scene_GradFull (all channels at 31), 112 of COLDATA_AllZero, then
; writes over the start of the second run (through WMDATA, bank $7E) the
; ramp C6Scene_Grad2Ramp also writes: intensity 16 down to 9, two lines
; each, then 8 down to 1, four lines each (48 lines).
; Quirk, kept: both MVNs move $70 bytes, one more than the 111 after the
; stored byte: the first one's extra byte is overwritten by the second
; fill, the second one's lands at $7E:9256, the byte after the table.
; Entry: M=1 (8-bit stores; op $4E calls it so), X=0 (16-bit index and
;        counts), DP=$0000 (TDC as zero, C2Scene_HdmaenShadow), DB=$00
;        (the DMA and WRAM-port registers .w; saved around the MVNs)
; Exit:  M=1, X=0; A = COLDATA_AllZero (B = $FF, from the MVN's A); X =
;        the second run's address ($91E6), Y = 0; DB unchanged; WMADD
;        left after the ramp
; No calls.
C6Scene_Grad2Init:
    LDA.b #!C2Scene_HdmaRun112
    STA.l C2Scene_HdmaTable[1].Count0
    STA.l C2Scene_HdmaTable[1].Count1
    TDC
    STA.l C2Scene_HdmaTable[1].End
    LDY.w #(!BBAD_COLDATA<<8)|!DMAP_HdmaIndirect
    STY.w DMAP2
    LDY.w #C2Scene_HdmaTable[1].Count0&$FFFF
    STY.w A1T2L
    LDA.b #!Bank7E
    STA.w A1B2
    STA.w DAS2B
    LDA.b #DMA_CH2
    TSB.b !C2Scene_HdmaenShadow
    REP #$20
    LDA.w #!C6Scene_Grad2&$FFFF
    STA.l !C2Scene_HdmaValues+4
    LDA.w #(!C6Scene_Grad2+!C6Scene_GradRunBytes)&$FFFF
    STA.l !C2Scene_HdmaValues+6
    PHB
    LDA.w #!C6Scene_GradFull
    STA.l !C6Scene_Grad2
    LDX.w #!C6Scene_Grad2&$FFFF
    LDY.w #(!C6Scene_Grad2+1)&$FFFF
    LDA.w #!C6Scene_GradRunBytes-1      ; one byte too many (see the header)
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDA.w #!COLDATA_AllZero
    STA.l !C6Scene_Grad2+!C6Scene_GradRunBytes
    LDX.w #(!C6Scene_Grad2+!C6Scene_GradRunBytes)&$FFFF
    LDY.w #(!C6Scene_Grad2+!C6Scene_GradRunBytes+1)&$FFFF
    LDA.w #!C6Scene_GradRunBytes-1      ; likewise
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    SEP #$20
    LDX.w #(!C6Scene_Grad2+!C6Scene_GradRunBytes)&$FFFF
    STX.w WMADDL
    LDA.b #bank(!C6Scene_Grad2)
    STA.w WMADDH
    LDY.w #!C6Scene_RampSteps
    LDA.b #!C6Scene_RampStart
.pairs:
    STA.w WMDATA
    STA.w WMDATA
    DEC A
    DEY
    BNE .pairs
    LDY.w #!C6Scene_RampSteps
.fours:
    STA.w WMDATA
    STA.w WMDATA
    STA.w WMDATA
    STA.w WMDATA
    DEC A
    DEY
    BNE .fours
    RTL

; $C6:E1FF — C6Scene_Grad2Ramp (56 bytes, $E1FF–$E236)
; Script routine (pack 4 +$039A): writes C6Scene_Grad2Init's 48-line
; ramp (16 down to 9, two lines each; 8 down to 1, four each) into
; C6Scene_Grad2 at the byte offset .Var22 (through WMDATA, bank $7E).
; What was there before is not restored.
; Entry: M=1 (op $4E calls it so; REP #$20 / SEP #$20 here), X=0,
;        DP=$0000 (C2Scene_TaskCur), DB=$00 (the record, the WRAM port
;        registers .w)
; Exit:  M=1, X=0; A = COLDATA_AllZero (B = the high byte of the
;        address); X = the task; Y = 0; WMADD left after the ramp
; No calls.
C6Scene_Grad2Ramp:
    REP #$20
    LDX.b !C2Scene_TaskCur
    CLC
    LDA.w C2Scene_EffectTask.Var22,X
    ADC.w #!C6Scene_Grad2&$FFFF
    STA.w WMADDL                        ; and WMADDM
    SEP #$20
    LDA.b #bank(!C6Scene_Grad2)
    STA.w WMADDH
    LDY.w #!C6Scene_RampSteps
    LDA.b #!C6Scene_RampStart
.pairs:
    STA.w WMDATA
    STA.w WMDATA
    DEC A
    DEY
    BNE .pairs
    LDY.w #!C6Scene_RampSteps
.fours:
    STA.w WMDATA
    STA.w WMDATA
    STA.w WMDATA
    STA.w WMDATA
    DEC A
    DEY
    BNE .fours
    RTL

; $C6:E237 — C6Scene_GetFlagF2Bits (10 bytes, $E237–$E240)
; Script routine (pack 1 +$0184): C2Tmp_00 = bits 2-5 of the copy of
; $7F:01F2 (C2Scene_FlagTailCopy+2) as a number 0-15, probably for the
; script's next test of $0000.
; Entry: M=1 (8-bit; op $4E calls it so), X any, DP=$0000 (C2Tmp_00),
;        DB=$00 (C2Scene_FlagTailCopy .w)
; Exit:  M=1; A = C2Tmp_00 = the value; X, Y unchanged
; No calls.
C6Scene_GetFlagF2Bits:
    LDA.w !C2Scene_FlagTailCopy+2
    AND.b #!C6Scene_FlagF2Mask
    LSR A
    LSR A
    STA.b !C2Tmp_00
    RTL

; $C6:E241 — C6Scene_WipeWinInit (110 bytes with C6Scene_WipeWinStep, $E241–$E2AE)
; Script routine (pack 0 +$0FB0, pack 2 +$0442, pack 5 +$0162, pack 7
; +$094E, each followed by C6Scene_WipeWinStep): sets up
; C2Scene_HdmaTable[1] (two runs of 112 lines) as HDMA channel 2 to WH1
; (indirect, one register: one byte a line), turns the channel on, and
; hands BankC3_Entry000E (WinFx_StepWipe) its block: WinFx_C3EMode =
; .Var22's low byte (high byte, WinFx_WipeFrame, 0: the first frame),
; WinFx_C3ETablePtr = .Var24 (a word), WinFx_C3ETableBank = $7E; then
; falls into the sub-entry C6Scene_WipeWinStep ($C6:E27E; also called on
; its own, pack 0 +$0FCB, pack 2 +$045D, pack 3 +$0658, pack 5 +$019A,
; pack 7 +$0969, probably once a frame): runs one frame of the wipe
; (BankC3_Entry000E), then points C2Scene_HdmaValues words 2-3 at the
; buffer it wrote: the table itself (.Var24) after an odd
; WinFx_WipeFrame, .Var24 + WinFx_Lines after an even one, and 112 bytes
; further for the second run. After the wipe's last frame
; (WinFx_WipeFrame back to 0) it points at the second buffer, which
; WinFx_StepWipe did not write that frame.
; Entry (both): M=1 (8-bit stores, the LSR; op $4E calls them so), X=0
;        (16-bit STY/LDY), DP=$0000 (TDC as zero, C2Scene_TaskCur,
;        C2Scene_HdmaenShadow), DB=$00 (the DMA registers and WinFx_*
;        .w, the record); C2Scene_TaskCur = the task
; Exit (both):  M=0, X=0 (BankC3_Entry000E restores P, A, X and Y); X =
;        the task; A = the second run's address; Y = .Var24
;        (C6Scene_WipeWinInit) or as on entry (C6Scene_WipeWinStep); WinFx_* stepped by WinFx_StepWipe (C3_RandSeed and WMADD
;        changed); C2Scene_HdmaValues words 2-3 changed
; Calls: BankC3_Entry000E (JSL).
C6Scene_WipeWinInit:
    LDA.b #!C2Scene_HdmaRun112
    STA.l C2Scene_HdmaTable[1].Count0
    STA.l C2Scene_HdmaTable[1].Count1
    TDC
    STA.l C2Scene_HdmaTable[1].End
    LDY.w #(!BBAD_WH1<<8)|!DMAP_HdmaIndirect
    STY.w DMAP2
    LDY.w #C2Scene_HdmaTable[1].Count0&$FFFF
    STY.w A1T2L
    LDA.b #!Bank7E
    STA.w A1B2
    STA.w DAS2B
    LDA.b #DMA_CH2
    TSB.b !C2Scene_HdmaenShadow
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_EffectTask.Var22,X
    STA.w !WinFx_C3EMode
    STZ.w !WinFx_WipeFrame              ; the mode word's high byte
    LDY.w C2Scene_EffectTask.Var24,X
    STY.w !WinFx_C3ETablePtr
    LDA.b #!Bank7E
    STA.w !WinFx_C3ETableBank
C6Scene_WipeWinStep:                    ; header: see C6Scene_WipeWinInit
    JSL BankC3_Entry000E
    LDX.b !C2Scene_TaskCur
    LDA.w !WinFx_WipeFrame
    LSR A
    REP #$20
    BCC .second_buf
    LDA.w C2Scene_EffectTask.Var24,X
    STA.l !C2Scene_HdmaValues+4
    CLC
    ADC.w #!C6Scene_WipeRunBytes
    STA.l !C2Scene_HdmaValues+6
    RTL
.second_buf:
    LDA.w C2Scene_EffectTask.Var24,X
    ADC.w #!WinFx_Lines                 ; C=0 here (the BCC)
    STA.l !C2Scene_HdmaValues+4
    CLC
    ADC.w #!C6Scene_WipeRunBytes
    STA.l !C2Scene_HdmaValues+6
    RTL

; $C6:E2AF — C6Scene_ClearUnk7F0062 (6 bytes, $E2AF–$E2B4)
; Script routine (pack 0 +$0FE3, pack 2 +$0475, pack 3 +$0670, pack 5
; +$01B2, pack 7 +$0981, each soon after a C6Scene_WipeWinStep):
; zeroes C6Scene_Unk7F0062 (what reads it is not traced).
; Entry: M=1 (8-bit store), X any, DP=$0000 (TDC as zero), DB any (long
;        store)
; Exit:  M=1; A = 0 (B = 0); X, Y unchanged
; No calls.
C6Scene_ClearUnk7F0062:
    TDC
    STA.l !C6Scene_Unk7F0062
    RTL

; $C6:E2B5 — C6Scene_Bg3Accel (99 bytes, $E2B5–$E317)
; Script routine (pack 4 +$0947 and +$0953): moves BG3 by the task's
; velocity, the fractions kept in .XFrac/.YFrac and the whole pixels
; added to C2Scene_Bg3HScroll/VScroll (as C2Scene_TaskMove does with
; .SprX/.SprY), adds the leader's last move (C2Scene_Unk1BF1/1BF3, then
; zeroed) as C2Scene_TaskBg3Drift does, and speeds the velocity up:
; .XVelFrac + C6Scene_Bg3AccelX and .YVelFrac + C6Scene_Bg3AccelY (1/32
; pixel), each carrying into the whole pixels.
; Entry: M any (REP #$20 here), X=0, DP=$0000 (the scroll shadows),
;        DB=$00 (the record, C2Scene_Unk1BF1/1BF3 .w); C2Scene_TaskCur =
;        the task
; Exit:  M=0, X=0; X = the task; A = the new .YVel; Y unchanged; the BG3
;        scroll, .XFrac/.YFrac and the velocity changed;
;        C2Scene_Unk1BF1/1BF3 = 0
; No calls.
C6Scene_Bg3Accel:
    REP #$20
    LDX.b !C2Scene_TaskCur
    CLC
    LDA.w C2Scene_Task.XFrac,X
    ADC.w C2Scene_Task.XVelFrac,X
    STA.w C2Scene_Task.XFrac,X
    LDA.b !C2Scene_Bg3HScroll
    ADC.w C2Scene_Task.XVel,X
    STA.b !C2Scene_Bg3HScroll
    CLC
    LDA.w C2Scene_Task.YFrac,X
    ADC.w C2Scene_Task.YVelFrac,X
    STA.w C2Scene_Task.YFrac,X
    LDA.b !C2Scene_Bg3VScroll
    ADC.w C2Scene_Task.YVel,X
    STA.b !C2Scene_Bg3VScroll
    LDA.b !C2Scene_Bg3HScroll
    CLC
    ADC.w !C2Scene_Unk1BF1
    STA.b !C2Scene_Bg3HScroll
    LDA.b !C2Scene_Bg3VScroll
    CLC
    ADC.w !C2Scene_Unk1BF3
    STA.b !C2Scene_Bg3VScroll
    STZ.w !C2Scene_Unk1BF1
    STZ.w !C2Scene_Unk1BF3
    CLC
    LDA.w C2Scene_Task.XVelFrac,X
    ADC.w #!C6Scene_Bg3AccelX
    STA.w C2Scene_Task.XVelFrac,X
    LDA.w C2Scene_Task.XVel,X
    ADC.w #0
    STA.w C2Scene_Task.XVel,X
    CLC
    LDA.w C2Scene_Task.YVelFrac,X
    ADC.w #!C6Scene_Bg3AccelY
    STA.w C2Scene_Task.YVelFrac,X
    LDA.w C2Scene_Task.YVel,X
    ADC.w #0
    STA.w C2Scene_Task.YVel,X
    RTL

; ============================================================
; Window shapes ($C6:E318–$C6:E567)
; ============================================================
; The window tables (2 bytes a line: left edge, right edge) are built by
; BankC3_Entry0008 (WinFx_BuildCircle) in one of two buffers, picked by a
; toggle in the task record, whose two 112-line halves C2Scene_HdmaValues
; words 0-1 (C2Scene_HdmaTable[0], window 1) or 2-3 (table 1, window 2)
; point at; the routines then reshape the circle in place.

; $C6:E318 — C6Scene_Win1HdmaOnB (40 bytes, $E318–$E33F)
; Script routine (pack 6 +$08A1 and +$0937, each followed by
; C6Scene_Win1EllipseStep): a byte-identical copy of C6Scene_Win1HdmaOn
; (HDMA channel 1 to WH0/WH1 from C2Scene_HdmaTable[0], turned on).
; Entry: M=1 (8-bit stores), X=0 (16-bit STY), DP=$0000 (TDC as zero,
;        C2Scene_HdmaenShadow), DB=$00 (the DMA registers .w)
; Exit:  M=1, X=0; A = DMA_CH1; Y = C2Scene_HdmaTable[0]'s address; X
;        unchanged; DB unchanged
; No calls.
C6Scene_Win1HdmaOnB:
    LDA.b #!C2Scene_HdmaRun112
    STA.l C2Scene_HdmaTable[0].Count0
    STA.l C2Scene_HdmaTable[0].Count1
    TDC
    STA.l C2Scene_HdmaTable[0].End
    LDY.w #(!BBAD_WH0<<8)|!DMAP_HdmaIndirect|DMA_MODE_2BYTE
    STY.w DMAP1
    LDY.w #C2Scene_HdmaTable[0].Count0&$FFFF
    STY.w A1T1L
    LDA.b #!Bank7E
    STA.w A1B1
    STA.w DAS1B
    LDA.b #DMA_CH1
    TSB.b !C2Scene_HdmaenShadow
    RTL

; $C6:E340 — C6Scene_Win2HdmaOn (40 bytes, $E340–$E367)
; Script routine (pack 6 +$071A and +$08DF, each followed by
; C6Scene_Win2EllipseStep): sets up C2Scene_HdmaTable[1] (two runs of
; 112 lines) as HDMA channel 2 to WH2/WH3 (indirect, two registers) and
; turns it on: C2Scene_Win2Init without its SEP #$20.
; C6Scene_Win2HdmaOnB ($C6:E470) is a byte-identical copy.
; Entry: M=1 (8-bit stores), X=0 (16-bit STY), DP=$0000 (TDC as zero,
;        C2Scene_HdmaenShadow), DB=$00 (the DMA registers .w)
; Exit:  M=1, X=0; A = DMA_CH2; Y = C2Scene_HdmaTable[1]'s address; X
;        unchanged; DB unchanged
; No calls.
C6Scene_Win2HdmaOn:
    LDA.b #!C2Scene_HdmaRun112
    STA.l C2Scene_HdmaTable[1].Count0
    STA.l C2Scene_HdmaTable[1].Count1
    TDC
    STA.l C2Scene_HdmaTable[1].End
    LDY.w #(!BBAD_WH2<<8)|!DMAP_HdmaIndirect|DMA_MODE_2BYTE
    STY.w DMAP2
    LDY.w #C2Scene_HdmaTable[1].Count0&$FFFF
    STY.w A1T2L
    LDA.b #!Bank7E
    STA.w A1B2
    STA.w DAS2B
    LDA.b #DMA_CH2
    TSB.b !C2Scene_HdmaenShadow
    RTL

; $C6:E368 — C6Scene_Win1EllipseStep (224 bytes with C6Scene_Win2EllipseStep and C6Scene_EllipseBuild, $E368–$E447)
; Script routine (pack 6 +$08A5, +$08B0, +$08C7, +$093B, +$0944):
; adds one to .Var24 (a word) and takes C2Scene_HandBufB (now odd) or
; C2Scene_HandBufA (even) as the table: C2Scene_HdmaValues words 0-1
; (window 1) point at it and its second half, and WinFx_TablePtr at it.
; The sub-entry C6Scene_Win2EllipseStep ($C6:E391; pack 6 +$071E,
; +$08E3, +$08EF) does the same with C2Scene_SwirlCosB / SwirlCosA and
; words 2-3 (window 2). Both go on at C6Scene_EllipseBuild ($C6:E3B8):
; BankC3_Entry0008 (A = WinFx_Mode0) builds a circle there from .SprX,
; .SprY and .Var22 (low bytes, WinFx_ArgX/ArgY/ArgSize = Xc, Yc, r;
; bank $7E), which is then squeezed to half its height about line c =
; .SprY (the word): line c - 1 - k takes line c - 2 - 2k and line c + k
; takes line c + 1 + 2k, for k = 0 to r/2 - 1, and the r/2 + 1 lines past
; each end are emptied (WinFx_EmptyEntry): an ellipse r wide and about
; r/2 high, probably.
; Quirks, kept: the ADC that finds line c has no CLC (C = bit 15 of
; .SprY from the ASL, 0 for any line on screen); the copy loops count
; r/2 down with a 16-bit DEC and test only after it, so r below 2 would
; run them 65,536 times (not checked: the scripts' .Var22 values were
; not traced).
; Entry (all three): M any (REP #$20 at the first two, SEP #$20 at
;        C6Scene_EllipseBuild, which only they reach), X=0 (16-bit
;        index; X = the task at C6Scene_EllipseBuild), DP=$0000 (TDC as zero; C2Tmp_00-$1A), DB=$00 (the record
;        and WinFx_* .w; saved, $7E for the reshaping); C2Scene_TaskCur
;        = the task
; Exit (all three): M=0, X=0; A = WinFx_EmptyEntry; X = 0; Y past the
;        last emptied line; DB unchanged; C2Tmp_00 = C2Tmp_02 = r/2,
;        C2Tmp_10/13/16/19 = the line pointers (words); .Var24 + 1;
;        WinFx_* changed (WinFx_BuildCircle zeroes WinFx_ArgXHi..); the
;        C2Scene_HdmaValues words changed
; Calls: BankC3_Entry0008 (JSL).
!C6Scene_EllipseHalf = !C2Tmp_00       ; 16-bit r/2: lines left to copy
!C6Scene_EllipseHalf2 = !C2Tmp_02      ; 16-bit r/2 kept for the second half
!C6Scene_EllipseUpSrc = !C2Tmp_10      ; 16-bit entry of line c - 2 (bank $7E)
!C6Scene_EllipseUpDst = !C2Tmp_13      ; 16-bit entry of line c - 1
!C6Scene_EllipseDownSrc = !C2Tmp_16    ; 16-bit entry of line c + 1
!C6Scene_EllipseDownDst = !C2Tmp_19    ; 16-bit entry of line c
C6Scene_Win1EllipseStep:
    REP #$20
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_EffectTask.Var24,X
    LDA.w C2Scene_EffectTask.Var24,X
    LSR A
    BCS .buf_b
    LDA.w #!C2Scene_HandBufA&$FFFF
    LDY.w #(!C2Scene_HandBufA+!C2Scene_HdmaHalfBytes)&$FFFF
    BRA .set
.buf_b:
    LDA.w #!C2Scene_HandBufB&$FFFF
    LDY.w #(!C2Scene_HandBufB+!C2Scene_HdmaHalfBytes)&$FFFF
.set:
    STA.l !C2Scene_HdmaValues
    STA.w !WinFx_TablePtr
    TYA
    STA.l !C2Scene_HdmaValues+2
    BRA C6Scene_EllipseBuild
C6Scene_Win2EllipseStep:                ; header: see C6Scene_Win1EllipseStep
    REP #$20
    LDX.b !C2Scene_TaskCur
    INC.w C2Scene_EffectTask.Var24,X
    LDA.w C2Scene_EffectTask.Var24,X
    LSR A
    BCS .buf_b
    LDA.w #!C2Scene_SwirlCosA&$FFFF
    LDY.w #(!C2Scene_SwirlCosA+!C2Scene_HdmaHalfBytes)&$FFFF
    BRA .set
.buf_b:
    LDA.w #!C2Scene_SwirlCosB&$FFFF
    LDY.w #(!C2Scene_SwirlCosB+!C2Scene_HdmaHalfBytes)&$FFFF
.set:
    STA.l !C2Scene_HdmaValues+4
    STA.w !WinFx_TablePtr
    TYA
    STA.l !C2Scene_HdmaValues+6
C6Scene_EllipseBuild:                   ; header: see C6Scene_Win1EllipseStep
    SEP #$20
    LDA.w C2Scene_Task.SprX,X
    STA.w !WinFx_ArgX
    LDA.w C2Scene_Task.SprY,X
    STA.w !WinFx_ArgY
    LDA.w C2Scene_EffectTask.Var22,X
    STA.w !WinFx_ArgSize
    LDA.b #!Bank7E
    STA.w !WinFx_TableBank
    TDC                                 ; A = WinFx_Mode0
    JSL BankC3_Entry0008
    SEP #$20
    PHB
    LDA.b #!Bank7E
    PHA
    PLB
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.SprY,X
    ASL A
    ADC.w !WinFx_TablePtr               ; no CLC (see the header)
    STA.b !C6Scene_EllipseDownDst
    INC A
    INC A
    STA.b !C6Scene_EllipseDownSrc
    CLC
    ADC.w #-4&$FFFF
    STA.b !C6Scene_EllipseUpDst
    DEC A
    DEC A
    STA.b !C6Scene_EllipseUpSrc
    LDA.w C2Scene_EffectTask.Var22,X
    LSR A
    STA.b !C6Scene_EllipseHalf
    STA.b !C6Scene_EllipseHalf2
    LDX.b !C6Scene_EllipseUpSrc
    LDY.b !C6Scene_EllipseUpDst
.up:
    LDA.w !Eng_PtrBase,X
    STA.w !Eng_PtrBase,Y
    DEX                                 ; two lines up
    DEX
    DEX
    DEX
    DEY                                 ; one line up
    DEY
    DEC.b !C6Scene_EllipseHalf
    BNE .up
    LDX.b !C6Scene_EllipseHalf2
    STX.b !C6Scene_EllipseHalf
    INX
    LDA.w #!WinFx_EmptyEntry
.up_clear:
    STA.w !Eng_PtrBase,Y
    DEY
    DEY
    DEX
    BNE .up_clear
    LDX.b !C6Scene_EllipseDownSrc
    LDY.b !C6Scene_EllipseDownDst
.down:
    LDA.w !Eng_PtrBase,X
    STA.w !Eng_PtrBase,Y
    INX
    INX
    INX
    INX
    INY
    INY
    DEC.b !C6Scene_EllipseHalf
    BNE .down
    LDX.b !C6Scene_EllipseHalf2
    INX
    LDA.w #!WinFx_EmptyEntry
.down_clear:
    STA.w !Eng_PtrBase,Y
    INY
    INY
    DEX
    BNE .down_clear
    PLB
    RTL

; $C6:E448 — C6Scene_Win1HdmaOnC (40 bytes, $E448–$E46F)
; Script routine (pack 4 +$02A3, +$1570 and +$1769, pack 5 +$0494 and
; +$04DE, pack 6 +$06CE, each followed by C6Scene_Win1CapsuleStep): a
; byte-identical copy of C6Scene_Win1HdmaOn (HDMA channel 1 to WH0/WH1
; from C2Scene_HdmaTable[0], turned on).
; Entry: M=1 (8-bit stores), X=0 (16-bit STY), DP=$0000 (TDC as zero,
;        C2Scene_HdmaenShadow), DB=$00 (the DMA registers .w)
; Exit:  M=1, X=0; A = DMA_CH1; Y = C2Scene_HdmaTable[0]'s address; X
;        unchanged; DB unchanged
; No calls.
C6Scene_Win1HdmaOnC:
    LDA.b #!C2Scene_HdmaRun112
    STA.l C2Scene_HdmaTable[0].Count0
    STA.l C2Scene_HdmaTable[0].Count1
    TDC
    STA.l C2Scene_HdmaTable[0].End
    LDY.w #(!BBAD_WH0<<8)|!DMAP_HdmaIndirect|DMA_MODE_2BYTE
    STY.w DMAP1
    LDY.w #C2Scene_HdmaTable[0].Count0&$FFFF
    STY.w A1T1L
    LDA.b #!Bank7E
    STA.w A1B1
    STA.w DAS1B
    LDA.b #DMA_CH1
    TSB.b !C2Scene_HdmaenShadow
    RTL

; $C6:E470 — C6Scene_Win2HdmaOnB (40 bytes, $E470–$E497)
; Script routine (pack 1 +$06FA, pack 4 +$1574 and +$176D, pack 5
; +$0528, each followed by C6Scene_Win2CapsuleStep): a byte-identical
; copy of C6Scene_Win2HdmaOn (HDMA channel 2 to WH2/WH3 from
; C2Scene_HdmaTable[1], turned on).
; Entry: M=1 (8-bit stores), X=0 (16-bit STY), DP=$0000 (TDC as zero,
;        C2Scene_HdmaenShadow), DB=$00 (the DMA registers .w)
; Exit:  M=1, X=0; A = DMA_CH2; Y = C2Scene_HdmaTable[1]'s address; X
;        unchanged; DB unchanged
; No calls.
C6Scene_Win2HdmaOnB:
    LDA.b #!C2Scene_HdmaRun112
    STA.l C2Scene_HdmaTable[1].Count0
    STA.l C2Scene_HdmaTable[1].Count1
    TDC
    STA.l C2Scene_HdmaTable[1].End
    LDY.w #(!BBAD_WH2<<8)|!DMAP_HdmaIndirect|DMA_MODE_2BYTE
    STY.w DMAP2
    LDY.w #C2Scene_HdmaTable[1].Count0&$FFFF
    STY.w A1T2L
    LDA.b #!Bank7E
    STA.w A1B2
    STA.w DAS2B
    LDA.b #DMA_CH2
    TSB.b !C2Scene_HdmaenShadow
    RTL

; $C6:E498 — C6Scene_Win1CapsuleStep (208 bytes with C6Scene_Win2CapsuleStep and C6Scene_CapsuleBuild, $E498–$E567)
; Script routine (pack 4 +$02C2 and 14 more sites to +$17FD, pack 5 +$0498 to +$04FC (6 sites), pack 6 +$06D5 to +$06FE (4
; sites)): takes C2Scene_HandBufB (.Var26 odd) or C2Scene_HandBufA
; (even) as the table, points C2Scene_HdmaValues words 0-1 (window 1)
; and WinFx_TablePtr at it, and adds one to .Var26 (a 16-bit INC, so a
; carry reaches +$27). The sub-entry C6Scene_Win2CapsuleStep ($C6:E4BE;
; pack 1 +$0717 to +$075A (7 sites), pack 4 +$1623, +$1634, +$1818,
; +$1827, pack 5 +$052C, +$0538, +$0546) does the same with
; C2Scene_SwirlCosB / SwirlCosA and words 2-3 (window 2) and falls into
; C6Scene_CapsuleBuild ($C6:E4E2): BankC3_Entry0008 (A = WinFx_Mode0)
; builds a circle from .SprX, .SprY and .Var22 (WinFx_ArgX/ArgY/ArgSize
; = Xc, Yc, r, written as words; bank $7E written as a word too, so
; $0359 = 0), then with n = .Var24:
; - r = 0 (the circle routine empties the table): the n lines from
;   .SprY on get the entry (x, x), x = .SprX's low byte (the word
;   stored, then spread by an overlapping MVN of 2n - 1 bytes): a line
;   one pixel wide, probably;
; - r > 0: the r lines from Yc - 1 up (the upper half, widest line
;   first) are copied, mirrored, to the lines from Yc - 1 + n down, and
;   the n - 1 lines from Yc on take line Yc - 1 (an MVN of 2n - 2
;   bytes): the circle cut at its middle and stretched by n - 1 lines, a
;   capsule shape, probably.
; Quirks, kept: the ADCs that find the lines have no CLC (C from the ASL
; before each: bit 15 of the word, 0 for lines on screen); nothing
; checks n: with r = 0 and n = 0, or r > 0 and n below 2, the MVN count
; wraps and 64 KB of bank $7E are moved (not checked: the scripts'
; values were not traced). Nothing keeps the lines inside the table.
; Entry (all three): M any (REP #$20 at the first two; M=0 at
;        C6Scene_CapsuleBuild, which only they reach), X=0 (X = the
;        task at C6Scene_CapsuleBuild), DP=$0000
;        (TDC as zero; C2Tmp_00/08), DB=$00 (the record and WinFx_* .w;
;        saved, $7E for the reshaping); C2Scene_TaskCur = the task
; Exit (all three): M=0, X=0; A = $FFFF (the MVN's end); X, Y = the
;        MVN's ends; DB unchanged; C2Tmp_08 = n (r = 0) or the entry of
;        line Yc - 1, C2Tmp_00 = 0 (r > 0); .Var26 + 1; WinFx_* changed;
;        the C2Scene_HdmaValues words changed
; Calls: BankC3_Entry0008 (JSL).
!C6Scene_CapsuleLines = !C2Tmp_08      ; 16-bit n (r = 0)
!C6Scene_CapsuleMid = !C2Tmp_08        ; 16-bit entry of line Yc - 1 (r > 0)
!C6Scene_CapsuleLeft = !C2Tmp_00       ; 16-bit lines left to mirror
C6Scene_Win1CapsuleStep:
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_EffectTask.Var26,X
    LSR A
    BCS .buf_b
    LDA.w #!C2Scene_HandBufA&$FFFF
    BRA .set
.buf_b:
    LDA.w #!C2Scene_HandBufB&$FFFF
.set:
    STA.l !C2Scene_HdmaValues
    STA.w !WinFx_TablePtr
    CLC
    ADC.w #!C2Scene_HdmaHalfBytes
    STA.l !C2Scene_HdmaValues+2
    INC.w C2Scene_EffectTask.Var26,X
    BRA C6Scene_CapsuleBuild
C6Scene_Win2CapsuleStep:                ; header: see C6Scene_Win1CapsuleStep
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_EffectTask.Var26,X
    LSR A
    BCS .buf_b
    LDA.w #!C2Scene_SwirlCosA&$FFFF
    BRA .set
.buf_b:
    LDA.w #!C2Scene_SwirlCosB&$FFFF
.set:
    STA.l !C2Scene_HdmaValues+4
    STA.w !WinFx_TablePtr
    CLC
    ADC.w #!C2Scene_HdmaHalfBytes
    STA.l !C2Scene_HdmaValues+6
    INC.w C2Scene_EffectTask.Var26,X
C6Scene_CapsuleBuild:                   ; header: see C6Scene_Win1CapsuleStep
    LDA.w C2Scene_Task.SprX,X
    STA.w !WinFx_ArgX                   ; and WinFx_ArgXHi
    LDA.w C2Scene_Task.SprY,X
    STA.w !WinFx_ArgY                   ; and WinFx_ArgYHi
    LDA.w C2Scene_EffectTask.Var22,X
    STA.w !WinFx_ArgSize                ; and WinFx_ArgSizeHi
    LDA.w #!Bank7E
    STA.w !WinFx_TableBank              ; and $0359
    TDC                                 ; A = WinFx_Mode0
    JSL BankC3_Entry0008
    SEP #$20
    PHB
    LDA.b #!Bank7E
    PHA
    PLB
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_EffectTask.Var22,X
    BNE .circle
    LDA.w C2Scene_EffectTask.Var24,X
    STA.b !C6Scene_CapsuleLines
    LDA.w C2Scene_Task.SprY,X
    ASL A
    ADC.w !WinFx_TablePtr               ; no CLC (see the header)
    TAY
    LDA.w C2Scene_Task.SprX,X
    STA.w !Eng_PtrBase,Y
    TYX
    INY
    LDA.b !C6Scene_CapsuleLines
    ASL A
    DEC A
    DEC A
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    RTL
.circle:
    LDA.w !WinFx_ArgY                   ; Yc (WinFx_BuildCircle zeroed the high byte)
    DEC A
    ASL A
    ADC.w !WinFx_TablePtr               ; no CLC (see the header)
    STA.b !C6Scene_CapsuleMid
    TAY
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_EffectTask.Var24,X
    ASL A
    ADC.b !C6Scene_CapsuleMid           ; no CLC (see the header)
    TAX
    LDA.w !WinFx_ArgSize                ; r
    STA.b !C6Scene_CapsuleLeft
.mirror:
    LDA.w !Eng_PtrBase,Y
    STA.w !Eng_PtrBase,X
    DEY
    DEY
    INX
    INX
    DEC.b !C6Scene_CapsuleLeft
    BNE .mirror
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_EffectTask.Var24,X
    ASL A
    ADC.w #-3&$FFFF                     ; 2n - 3: the MVN count for 2n - 2 bytes (C=0 from the ASL)
    LDX.b !C6Scene_CapsuleMid
    TXY
    INY
    INY
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    PLB
    RTL

; $C6:E568 — C6Scene_FadeGradStep (27 bytes, $E568–$E582)
; Script routine (pack 3 +$0339, in a loop the script runs 58 times, one
; frame each): moves C2Scene_HdmaValues words 0 and 1 on by
; C6Scene_GradStepBytes (8 lines of C6Scene_FadeGradInit's gradient).
; Entry: M any (REP #$20 here), X any, DP any, DB any (long addressing)
; Exit:  M=0; A = the new word 1; X, Y unchanged
; No calls.
C6Scene_FadeGradStep:
    REP #$20
    LDA.l !C2Scene_HdmaValues
    CLC
    ADC.w #!C6Scene_GradStepBytes
    STA.l !C2Scene_HdmaValues
    LDA.l !C2Scene_HdmaValues+2
    CLC
    ADC.w #!C6Scene_GradStepBytes
    STA.l !C2Scene_HdmaValues+2
    RTL

; $C6:E583 — C6Scene_Bg2VNudge (18 bytes, $E583–$E594)
; Script routine (no op $4E site found in the unpacked scripts): moves
; BG2 two pixels down (.Var22 bit 0 clear) or up (set): two INC or DEC
; of C2Scene_Bg2VScroll, 8-bit with M=1, so only its low byte changes
; (no carry into the high byte).
; Entry: M=1 (assumed, as op $4E calls; the 8-bit LSR and INC/DEC), X=0,
;        DP=$0000 (C2Scene_TaskCur, the scroll), DB=$00 (the record .w);
;        C2Scene_TaskCur = the task
; Exit:  M=1, X=0; X = the task; A = .Var22 >> 1; Y unchanged
; No calls.
C6Scene_Bg2VNudge:
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_EffectTask.Var22,X
    LSR A
    BCS .up
    INC.b !C2Scene_Bg2VScroll
    INC.b !C2Scene_Bg2VScroll
    RTL
.up:
    DEC.b !C2Scene_Bg2VScroll
    DEC.b !C2Scene_Bg2VScroll
    RTL

; ============================================================
; BG1 line wave, flags, more unpacks, random moves ($C6:E595–$C6:E7F9)
; ============================================================

; $C6:E595 — C6Scene_Bg1WaveInit (48 bytes, $E595–$E5C4)
; Script routine (pack 5 +$03A1, followed by C6Scene_Bg1WaveStep): sets
; up C2Scene_HdmaTable[2] (two runs of 112 lines) as HDMA channel 3 to
; BG1VOFS (indirect, one register written twice), turns it on, and
; zeroes the wave's phase .Var22 (two 8-bit STZs).
; Entry: M=1 (8-bit stores; op $4E calls it so), X=0 (16-bit STY),
;        DP=$0000 (TDC as zero, C2Scene_HdmaenShadow), DB=$00 (the DMA
;        registers and the record .w); C2Scene_TaskCur = the task
; Exit:  M=1, X=0; A = DMA_CH3; X = the task; Y = C2Scene_HdmaTable[2]'s
;        address
; No calls.
C6Scene_Bg1WaveInit:
    LDA.b #!C2Scene_HdmaRun112
    STA.l C2Scene_HdmaTable[2].Count0
    STA.l C2Scene_HdmaTable[2].Count1
    TDC
    STA.l C2Scene_HdmaTable[2].End
    LDY.w #(!BBAD_BG1VOFS<<8)|!DMAP_HdmaIndirect|DMA_MODE_1BYTE_X2
    STY.w DMAP3
    LDY.w #C2Scene_HdmaTable[2].Count0&$FFFF
    STY.w A1T3L
    LDA.b #!Bank7E
    STA.w A1B3
    STA.w DAS3B
    LDA.b #DMA_CH3
    TSB.b !C2Scene_HdmaenShadow
    LDX.b !C2Scene_TaskCur
    STZ.w C2Scene_EffectTask.Var22,X
    STZ.w C2Scene_EffectTask.Var22+1,X
    RTL

; $C6:E5C5 — C6Scene_Bg1WaveStep (120 bytes, $E5C5–$E63C)
; Script routine (pack 5 +$03A5 and +$03AB): writes one frame of a
; vertical wave on BG1: picks C2Scene_SwirlSinA (.Var24 odd) or
; C2Scene_SwirlSinB (even), points C2Scene_HdmaValues words 4-5
; (C2Scene_HdmaTable[2], channel 3) and WMADD at it, adds one to .Var24
; (a 16-bit INC), and writes 224 words through WMDATA: line n gets
; C2Scene_Bg1VScroll + w(.Var22 + 8n), w(a) = the Rom_SineTable byte of
; a (AND $3FF) x 4 / 256, so 0 to 3 in the first half turn and -1 to -4
; (rounded down) in the second. Then .Var22 + 8.
; Quirk, kept: at a = $200 the table byte is 0 and the second-half path
; turns it into -256 ($FF00), so with .Var22 a multiple of 8 (as
; C6Scene_Bg1WaveInit and the steps leave it) one or two lines each
; frame are moved 256 pixels; a BG1 256 pixels tall would not show it
; (not traced).
; Entry: M=1 (the 8-bit WMADDH store and .Var24 test; op $4E calls it
;        so), X=0, DP=$0000 (C2Tmp_08, C2Scene_Bg1VScroll), DB=$00 (the
;        WRAM port registers and the record .w, Rom_SineTable read .w
;        through bank $00's mirror of $C0:F900); C2Scene_TaskCur = the
;        task
; Exit:  M=0, X=0; X = the task; Y = 0; A = the new .Var22; C2Tmp_08 =
;        the phase after the last line; .Var24 + 1; WMADD after the
;        buffer; C2Scene_HdmaValues words 4-5 changed
; No calls.
!C6Scene_WavePhase = !C2Tmp_08         ; 16-bit angle of the line (Rom_SineTable index, 1024 a turn)
C6Scene_Bg1WaveStep:
    LDA.b #!Bank7E
    STA.w WMADDH
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_EffectTask.Var24,X
    LSR A
    REP #$20
    BCS .buf_a
    LDA.w #!C2Scene_SwirlSinB&$FFFF
    BRA .set
.buf_a:
    LDA.w #!C2Scene_SwirlSinA&$FFFF
.set:
    STA.w WMADDL                        ; and WMADDM
    STA.l !C2Scene_HdmaValues+8
    CLC
    ADC.w #!C2Scene_HdmaHalfBytes
    STA.l !C2Scene_HdmaValues+10
    INC.w C2Scene_EffectTask.Var24,X
    LDA.w C2Scene_EffectTask.Var22,X
    STA.b !C6Scene_WavePhase
    LDY.w #!WinFx_Lines
.line:
    LDA.b !C6Scene_WavePhase
    AND.w #!Trig_IndexMask
    TAX
    LDA.w !Rom_SineTable,X
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    CPX.w #!Trig_HalfTable
    BCC .positive
    EOR.w #!Eng_Invert16
    INC A
    XBA                                 ; / 256, rounded down
    ORA.w #!Eng_HighByteMask
    BRA .add
.positive:
    XBA
    AND.w #!Eng_LowByteMask
.add:
    CLC
    ADC.b !C2Scene_Bg1VScroll
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    REP #$20
    CLC
    LDA.b !C6Scene_WavePhase
    ADC.w #!C6Scene_WaveLineStep
    STA.b !C6Scene_WavePhase
    DEY
    BNE .line
    CLC
    LDX.b !C2Scene_TaskCur
    LDA.w C2Scene_EffectTask.Var22,X
    ADC.w #!C6Scene_WaveLineStep
    STA.w C2Scene_EffectTask.Var22,X
    RTL

; $C6:E63D — C6Scene_SetUnk7F01ED (7 bytes, $E63D–$E643)
; Script routine (pack 4 +$115D): C2Scene_Unk7F01ED = 1 (script op $3D
; then skips its sound command).
; Entry: M=1 (8-bit; op $4E calls it so), X any, DP any, DB any (long
;        store)
; Exit:  M=1; A = 1; X, Y unchanged
; No calls.
C6Scene_SetUnk7F01ED:
    LDA.b #1
    STA.l !C2Scene_Unk7F01ED
    RTL

; $C6:E644 — C6Scene_ClearUnk7F01ED (6 bytes, $E644–$E649)
; Script routine (pack 4 +$06E9 and +$083A): C2Scene_Unk7F01ED = 0.
; Entry: M=1 (8-bit; op $4E calls it so), X any, DP=$0000 (TDC as
;        zero), DB any (long store)
; Exit:  M=1; A = 0 (B = 0); X, Y unchanged
; No calls.
C6Scene_ClearUnk7F01ED:
    TDC
    STA.l !C2Scene_Unk7F01ED
    RTL

; $C6:E64A — C6Scene_UnpackObjPackB (37 bytes, $E64A–$E66E)
; Script routine (pack 4 +$0D2D, between C6Scene_UnpackObjPackA and
; C6Scene_UnpackPalPackA): as C6Scene_UnpackObjPackA with entry
; C6Scene_ObjPackB of C2SceneRom_ObjPacks.
; Entry: M=1 (8-bit bank stores), X=0 (16-bit LDX/STX), DP any (no
;        direct page), DB=$00 (Menu_Decomp* .w)
; Exit:  M=1, X=0 (Decomp_ToWram restores P, A, X and Y); A = the pack's
;        bank byte (B = the high byte of its address); X = the entry's
;        offset; Y unchanged; Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C6Scene_UnpackObjPackB:
    LDX.w #!C2Scene_DecompBuf&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_DecompBuf)
    STA.w !Menu_DecompDestBank
    LDX.w #!C6Scene_ObjPackB*!C2Scene_PackEntrySize
    REP #$20
    LDA.l !C2SceneRom_ObjPacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_ObjPacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
    RTL

; $C6:E66F — C6Scene_UnpackPalPackB (37 bytes, $E66F–$E693)
; Script routine (pack 4 +$0D55, after C6Scene_UnpackPalPackA): as
; C6Scene_UnpackPalPackA with entry C6Scene_PalPackB of
; C2SceneRom_PalettePacks (into C2Scene_PaletteStage).
; Entry: M=1, X=0, DP any (no direct page), DB=$00 (Menu_Decomp* .w)
; Exit:  M=1, X=0 (Decomp_ToWram restores P, A, X and Y); A = the pack's
;        bank byte (B = the high byte of its address); X = the entry's
;        offset; Y unchanged; Menu_Decomp* changed
; Calls: Decomp_ToWramVec (JSL).
C6Scene_UnpackPalPackB:
    LDX.w #!C2Scene_PaletteStage&$FFFF
    STX.w !Menu_DecompDest
    LDA.b #bank(!C2Scene_PaletteStage)
    STA.w !Menu_DecompDestBank
    LDX.w #!C6Scene_PalPackB*!C2Scene_PackEntrySize
    REP #$20
    LDA.l !C2SceneRom_PalettePacks,X
    STA.w !Menu_DecompSrc
    SEP #$20
    LDA.l !C2SceneRom_PalettePacks+2,X
    STA.w !Menu_DecompSrcBank
    JSL Decomp_ToWramVec
    RTL

; $C6:E694 — C6Scene_PlaceInViewRandom (60 bytes, $E694–$E6CF)
; Script routine (pack 4 +$0FD3 to +$1015, 7 sites): puts the task at a
; random point: .SprX = BG2's tile X x 8 (C2Scene_BgTileX+2) + a random
; 0-127 + 64, as C2Scene_PlaceBelowView; .SprY = $60 + a random 0-63
; (not relative to the view). The two bytes are RandomTable's at
; C2Scene_Unk1B30, which goes up by 2.
; Quirk, kept: the ADC of the random X has no CLC; the carry is bit 13
; of the tile X shifted out by the third ASL (0 for any tile X, 0-191),
; as in C2Scene_PlaceBelowView.
; Entry: M any, X any (SEP #$30 here), DP=$0000 (C2Tmp_08-$0B,
;        C2Scene_BgTileX), DB=$00 (C2Scene_Unk1B30 and the record .w);
;        C2Scene_TaskCur = the task
; Exit:  M=0, X=0; X = the task; A = the new .SprY; Y's high byte
;        cleared (the SEP #$30), low byte kept; C2Tmp_08/0A = the random
;        X/Y parts (words); C2Scene_Unk1B30 + 2
; No calls.
!C6Scene_RandX = !C2Tmp_08             ; 16-bit random part of X (0-127)
!C6Scene_RandY = !C2Tmp_0A             ; 16-bit random part of Y (0-63)
C6Scene_PlaceInViewRandom:
    SEP #$30
    LDX.w !C2Scene_Unk1B30
    LDA.l RandomTable,X
    AND.b #!C2Scene_PlaceRandMask
    STA.b !C6Scene_RandX
    INX
    LDA.l RandomTable,X
    AND.b #!C6Scene_PlaceRandYMask
    STA.b !C6Scene_RandY
    INX
    STX.w !C2Scene_Unk1B30
    REP #$10
    STZ.b !C6Scene_RandX+1
    STZ.b !C6Scene_RandY+1
    LDX.b !C2Scene_TaskCur
    REP #$20
    LDA.b !C2Scene_BgTileX+2            ; BG2's tile X, x 8
    ASL A
    ASL A
    ASL A
    ADC.b !C6Scene_RandX                ; no CLC (see the header)
    CLC
    ADC.w #!C2Scene_PlaceMarginX
    STA.w C2Scene_Task.SprX,X
    LDA.w #!C6Scene_PlaceTopY
    CLC
    ADC.b !C6Scene_RandY
    STA.w C2Scene_Task.SprY,X
    RTL

; $C6:E6D0 — C6Scene_NudgeRandomDir (126 bytes, $E6D0–$E74D)
; Script routine (pack 4 +$0FAA): moves the task by a random distance d
; (0-63) in a random direction a (0-255, C2Scene_Unk2273/Unk2277's
; units): .SprX + cos(a) x d / 256 and .SprY + sin(a) x d / 256, with
; cos and sin -128..+128, so 0 to 31 pixels each way; each product is
; taken of the magnitudes (WRMPYA/B) and its sign put back after (the
; PHP keeps the N flag of the TAX). The two bytes are RandomTable's at
; C2Scene_Unk1B30, which goes up by 2.
; Entry: M any, X any (SEP #$30 here), DP=$0000 (C2Tmp_08/0A), DB=$00
;        (C2Scene_Unk1B30, the record and the multiplier .w; the sine
;        helpers read their table through bank $00); C2Scene_TaskCur =
;        the task
; Exit:  M=0, X=0; X = the task; A = the new .SprY; Y's high byte
;        cleared (the SEP #$30), low byte kept; C2Tmp_08 = a (word),
;        C2Tmp_0A = d (8-bit; C2Tmp_0B unchanged); C2Scene_Unk1B30 + 2
; Calls: C2Scene_Unk2273, C2Scene_Unk2277 (JSL).
!C6Scene_NudgeDir = !C2Tmp_08          ; 16-bit direction (256 a turn)
!C6Scene_NudgeDist = !C2Tmp_0A         ; 8-bit distance
C6Scene_NudgeRandomDir:
    SEP #$30
    LDX.w !C2Scene_Unk1B30
    LDA.l RandomTable,X
    STA.b !C6Scene_NudgeDir
    STZ.b !C6Scene_NudgeDir+1
    INX
    LDA.l RandomTable,X
    AND.b #!C6Scene_NudgeDistMask
    STA.b !C6Scene_NudgeDist
    INX
    STX.w !C2Scene_Unk1B30
    REP #$30
    LDA.b !C6Scene_NudgeDir
    JSL C2Scene_Unk2273
    TAX                                 ; (for the N flag)
    PHP
    BPL .cos_abs
    EOR.w #!Eng_Invert16
    INC A
.cos_abs:
    SEP #$20
    STA.w WRMPYA
    LDA.b !C6Scene_NudgeDist
    STA.w WRMPYB
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w RDMPYL
    XBA                                 ; / 256
    AND.w #!Eng_LowByteMask
    PLP
    BPL .x_pos
    EOR.w #!Eng_Invert16
    INC A
.x_pos:
    CLC
    ADC.w C2Scene_Task.SprX,X
    STA.w C2Scene_Task.SprX,X
    LDA.b !C6Scene_NudgeDir
    JSL C2Scene_Unk2277
    TAX                                 ; (for the N flag)
    PHP
    SEP #$20
    BPL .sin_abs
    EOR.b #!Eng_Invert8                 ; the low byte is enough for the multiplier
    INC A
.sin_abs:
    STA.w WRMPYA
    LDA.b !C6Scene_NudgeDist
    STA.w WRMPYB
    REP #$20
    LDX.b !C2Scene_TaskCur
    LDA.w RDMPYL
    XBA
    AND.w #!Eng_LowByteMask
    PLP
    BPL .y_pos
    EOR.w #!Eng_Invert16
    INC A
.y_pos:
    CLC
    ADC.w C2Scene_Task.SprY,X
    STA.w C2Scene_Task.SprY,X
    RTL

; $C6:E74E — BankC6_UnkE74E (49 bytes, $E74E–$E77E)
; Tests the 8x8 tile (C2Tmp_00, C2Tmp_01) against a rectangle of columns
; C2Tmp_04 to C2Tmp_05 - 1 and rows C2Tmp_02 to C2Tmp_03 - 1 (unsigned
; bytes): C2Tmp_06 = 0 when the tile is inside, else bit 0 (left of
; it), bit 1 (right of it), bit 2 (above) and/or bit 3 (below). The name
; is the stub's (verified C2Scene_ObjBFly calls it so; better:
; C6Scene_TileOutsideRect).
; Callers (2 JSL sites): C2Scene_ObjBFly ($C2:4E6D) and BankC6_UnkE797 ($C6:E7EE).
; Entry: M any (SEP #$20 here), X any, DP=$0000 (C2Tmp_00-$06), DB any
; Exit:  M=1; C2Tmp_06 = the result; A = the result when the tile is
;        above or below, else the tile row; X, Y unchanged
; No calls.
BankC6_UnkE74E:
    SEP #$20
    STZ.b !C2Scene_RectOut
    LDA.b !C2Scene_RectTileX
    CMP.b !C2Scene_RectLeft
    BCS .not_left
    LDA.b #!C6Scene_RectLeftOf
    STA.b !C2Scene_RectOut
    BRA .rows
.not_left:
    CMP.b !C2Scene_RectRight
    BCC .rows
    LDA.b #!C6Scene_RectRightOf
    STA.b !C2Scene_RectOut
.rows:
    LDA.b !C2Scene_RectTileY
    CMP.b !C2Scene_RectTop
    BCS .not_above
    LDA.b !C2Scene_RectOut
    ORA.b #!C6Scene_RectAbove
    STA.b !C2Scene_RectOut
    BRA .done
.not_above:
    CMP.b !C2Scene_RectBottom
    BCC .done
    LDA.b !C2Scene_RectOut
    ORA.b #!C6Scene_RectBelow
    STA.b !C2Scene_RectOut
.done:
    RTL

; $C6:E77F — C6Scene_AddYAccel (24 bytes, $E77F–$E796)
; Script routine (pack 4 +$0ED9 and 10 more sites to +$10DF): adds the
; 16.16 value .Var22 (fraction) / .Var24 (whole) to the task's Y
; velocity (.YVelFrac, carrying into .YVel): C2Scene_AddGravity with the
; step taken from the task.
; Entry: M any (REP #$20 here), X=0, DP=$0000 (C2Scene_TaskCur), DB=$00
;        (the record .w); C2Scene_TaskCur = the task
; Exit:  M=0, X=0; X = the task; A = the new .YVel; Y unchanged
; No calls.
C6Scene_AddYAccel:
    REP #$20
    LDX.b !C2Scene_TaskCur
    CLC
    LDA.w C2Scene_Task.YVelFrac,X
    ADC.w C2Scene_EffectTask.Var22,X
    STA.w C2Scene_Task.YVelFrac,X
    LDA.w C2Scene_Task.YVel,X
    ADC.w C2Scene_EffectTask.Var24,X
    STA.w C2Scene_Task.YVel,X
    RTL

; $C6:E797 — BankC6_UnkE797 (99 bytes, $E797–$E7F9)
; Object A's landing check (the name is the stub's: verified
; C2Scene_ObjAFly calls it so; better: C6Scene_ObjANoLandHere). Takes
; the task's 8x8 tile (.SprX / 8 into C2Tmp_00, .SprY / 8 into C2Tmp_01,
; both stored as words, so C2Tmp_02 gets the row's high byte) and, by
; Loc_Id - Loc_FirstBankC2 (the .handlers table, 8 entries), the
; location's rectangle where object A may not come down: Loc_Id $1F0
; rows $64-$7E, columns $41-$71; $1F1 rows $76-$7E, columns $60-$6D;
; $1F3 rows $00-$33, columns $00-$0D; $1F4 rows $60-$7E, columns
; $00-$1F; $1F2 and $1F5-$1F7 have none (C=0 at once). With a rectangle
; it returns C=1 when the tile is inside it (BankC6_UnkE74E gives 0),
; else C=0. C2Scene_ObjAFly comes down on C=0.
; Quirk, kept: Loc_Id is not checked: outside $1F0-$1F7 the JMP takes
; its address from the bytes after the table (or anywhere in the bank
; below $1F0) (object A's task runs only
; in those scenes, probably).
; Callers (1 JSL site): C2Scene_ObjAFly ($C2:455E).
; Entry: M any (REP #$20 here), X=0 (the 16-bit index), DP=$0000 (TDC
;        as zero; C2Tmp_00-$06), DB=$00 (the record and DP_Field+Loc_Id
;        .w); C2Scene_TaskCur = object A's task
; Exit:  M=1, X=0; C=1: the tile is in the location's rectangle (stay
;        up), C=0: it is not, or the location has none; A = C2Tmp_06 (a
;        rectangle) or 0 (none; B = 0); X = the rows word or the table
;        index; Y = the columns word or the task; C2Tmp_00-$02 (and with
;        a rectangle C2Tmp_02-$06) changed
; Calls: BankC6_UnkE74E (JSL).
BankC6_UnkE797:
    REP #$20
    LDY.b !C2Scene_TaskCur
    LDA.w C2Scene_Task.SprX,Y
    LSR A
    LSR A
    LSR A
    STA.b !C2Scene_RectTileX            ; a word: C2Tmp_01 is overwritten next
    LDA.w C2Scene_Task.SprY,Y
    LSR A
    LSR A
    LSR A
    STA.b !C2Scene_RectTileY            ; a word: also C2Tmp_02
    LDA.w !DP_Field+!Loc_Id
    SEC
    SBC.w #!Loc_FirstBankC2
    ASL A
    TAX
    TDC
    SEP #$20
    JMP (.handlers,X)
.handlers:
    dw .loc1F0
    dw .loc1F1
    dw .anywhere                        ; $1F2
    dw .loc1F3
    dw .loc1F4
    dw .anywhere                        ; $1F5
    dw .anywhere                        ; $1F6
    dw .anywhere                        ; $1F7
.loc1F0:
    LDX.w #!C6Scene_NoLand1F0Rows
    LDY.w #!C6Scene_NoLand1F0Cols
    BRA .test
.loc1F1:
    LDX.w #!C6Scene_NoLand1F1Rows
    LDY.w #!C6Scene_NoLand1F1Cols
    BRA .test
.anywhere:
    CLC
    RTL
.loc1F3:
    LDX.w #!C6Scene_NoLand1F3Rows
    LDY.w #!C6Scene_NoLand1F3Cols
    BRA .test
.loc1F4:
    LDX.w #!C6Scene_NoLand1F4Rows
    LDY.w #!C6Scene_NoLand1F4Cols
.test:
    STX.b !C2Scene_RectTop              ; and C2Scene_RectBottom
    STY.b !C2Scene_RectLeft             ; and C2Scene_RectRight
    JSL BankC6_UnkE74E
    LDA.b !C2Scene_RectOut
    BNE .outside
    SEC
    RTL
.outside:
    CLC
    RTL

; ============================================================
; The Mode 7 view: picture and per-line matrix ($C6:E7FA–$C6:EE30)
; ============================================================
; Script pack 0 runs these after the map view's helpers (op $34 to
; C2Scene_ClearVram, C2Scene_MapViewGradient, C2Scene_LoadBgGfx and
; C2Scene_MapTileColors, then C6Scene_MapPicture, C2Scene_MapBuildTilemap
; and C6Scene_PerspInit), then turns the view a step at a time
; (C6Scene_AddAngle with C2Tmp_08 = -2, C6Scene_PerspStep). A Mode 7
; view of the scene's maps seen at a slant from above, probably (only
; the register values are traced, not the picture).

; $C6:E7FA — C6Scene_MapPicture (205 bytes, $E7FA–$E8C6)
; Script routine (pack 0 +$11F0): draws the Mode 7 picture of the two
; maps as C2Scene_MapDrawPixels does, but whole: zeroes C2Scene_DecompBuf
; ($7F:9000-$BFFF, C6Scene_PicBytes), then for each of the 64 metatile
; rows and 96 columns draws the cell of map A (C2Scene_MapPtrA, set
; C2Scene_MetaBaseA) and over it the cell of map B (C2Scene_MapPtrB, set
; C2Scene_MetaBaseB) with C6Scene_MapCellPixels (two pixels, one under
; the other; 0 is not drawn) into Mode 7 tiles of 8 x 8 bytes, 12 tiles
; to a row, and DMAs the $3000 bytes on channel 7 to VMDATAH from VRAM
; word C2Scene_MapFirstTileVram (tiles 1-192). Unlike
; C2Scene_MapDrawPixels it has no colour filter and no Loc_Id test.
; Pack 0 sets the pointers with op $13 just before: map A $7E:5800 with
; set $7E:3800 (BG2's), map B $7E:4000 with set $7E:3000 (BG1's).
; Entry: M any (REP #$20 here), X=0, DP=$0000 (TDC as zero;
;        C2Tmp_05-$1A), DB any (saved; $7F for the clear, then $7E;
;        registers written long); C2Tmp_10/13 = the maps' first rows,
;        C2Tmp_16/19 = the metatile sets (bank $7E); C2Scene_TileColors
;        built; DMA channel 7 free
; Exit:  M=1, X=0; A = MDMAEN_Ch7; X, Y clobbered; DB unchanged;
;        C2Tmp_00/01 and $05-$0F changed, C2Tmp_10/13 past the maps
; Calls: C6Scene_MapCellPixels.
!C6Scene_PicOut = !C2Tmp_05            ; 24-bit address of the cell's top pixel (bank $7F)
C6Scene_MapPicture:
    REP #$20
    PHB
    LDX.w #!C2Scene_DecompBuf&$FFFF
    STX.b !C6Scene_PicOut
    TDC
    STA.l !C2Scene_DecompBuf
    TXY
    INY
    LDA.w #!C6Scene_PicBytes-2
    MVN !Bank7F,!Bank7F                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    SEP #$20
    LDA.b #!Bank7E
    PHA
    PLB
    LDA.b #bank(!C2Scene_DecompBuf)
    STA.b !C6Scene_PicOut+2
    REP #$20
    STZ.b !C2Scene_MapRow
.row:
    STZ.b !C2Scene_MapCol
.cell:
    LDY.b !C2Scene_MapCol
    LDA.b (!C2Scene_MapPtrA),Y
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A                               ; * 8 bytes per metatile (C=0)
    ADC.b !C2Scene_MetaBaseA
    STA.b !C2Scene_MetaPtr
    SEP #$20
    JSR C6Scene_MapCellPixels
    LDY.b !C2Scene_MapCol
    LDA.b (!C2Scene_MapPtrB),Y
    REP #$20
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A
    ADC.b !C2Scene_MetaBaseB
    STA.b !C2Scene_MetaPtr
    SEP #$20
    JSR C6Scene_MapCellPixels
    REP #$20
    INC.b !C2Scene_MapCol
    LDA.b !C2Scene_MapCol
    AND.w #!C2Scene_MapTilePxMask
    BNE .same_tile
    CLC
    LDA.b !C6Scene_PicOut
    ADC.w #!C2Scene_MapNextTile         ; to the next tile's first row
    STA.b !C6Scene_PicOut
    BRA .col_done
.same_tile:
    INC.b !C6Scene_PicOut
.col_done:
    LDA.b !C2Scene_MapCol
    CMP.w #!C2Scene_MapCols
    BCC .cell
    LDA.b !C2Scene_MapPtrA
    CLC
    ADC.w #!C2Scene_MapCols
    STA.b !C2Scene_MapPtrA
    LDA.b !C2Scene_MapPtrB
    CLC
    ADC.w #!C2Scene_MapCols
    STA.b !C2Scene_MapPtrB
    LDA.b !C6Scene_PicOut
    SEC
    SBC.w #!C2Scene_MapBackToRow        ; back to the first tile, two pixel rows down
    STA.b !C6Scene_PicOut
    INC.b !C2Scene_MapRow
    LDA.b !C2Scene_MapRow
    AND.w #!C2Scene_MapBandRowMask
    BNE .band_open
    CLC
    LDA.b !C6Scene_PicOut
    ADC.w #!C6Scene_PicNextBand         ; on to the next row of tiles
    STA.b !C6Scene_PicOut
.band_open:
    LDA.b !C2Scene_MapRow
    CMP.w #!C2Scene_MapRows
    BCC .row
    LDA.w #!C2Scene_MapFirstTileVram
    STA.l VMADDL
    LDA.w #!C2Scene_DecompBuf&$FFFF
    STA.l A1T7L
    LDA.w #!C6Scene_PicBytes
    STA.l DAS7L
    LDA.w #!BBAD_VMDATAH<<8             ; DMAP7 = 0 (one register), BBAD7 = VMDATAH
    STA.l DMAP7
    SEP #$20
    LDA.b #!VMAIN_IncAfterHigh
    STA.l VMAIN
    LDA.b #bank(!C2Scene_DecompBuf)
    STA.l A1B7
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    PLB
    RTL

; $C6:E8C7 — C6Scene_MapCellPixels (72 bytes, $E8C7–$E90E)
; Draws one metatile cell as two pixels, at [C6Scene_PicOut] and 8 bytes
; (one pixel row) below: the colours (C2Scene_TileColors) of the
; metatile's top-right and bottom-right tiles, each ORed with that
; tile's palette * 16 (high-byte bits 2-4); a colour of 0 writes nothing.
; C2Scene_MapCellPixels without the colour filter.
; Callers note: both sites are C6Scene_MapPicture's (JSR).
; Callers (2 JSR sites): C6Scene_MapPicture ($C6:E82F, $C6:E844).
; Entry: M=1 (SEP #$20 before each JSR), X=0, DP=$0000, DB=$7E (the
;        metatile); C2Scene_MetaPtr = the metatile, C6Scene_PicOut = the
;        pixel
; Exit:  M=1, X=0; A, X clobbered; Y = 8; C2Tmp_00/$01 = the two
;        palettes * 16
; No calls.
C6Scene_MapCellPixels:
    LDY.w #C2Scene_Metatile.TopRight+1
    LDA.b (!C2Scene_MetaPtr),Y
    AND.b #!C2Scene_TilePalBits
    ASL A
    ASL A
    STA.b !C2Scene_PalTop
    LDY.w #C2Scene_Metatile.BottomRight+1
    LDA.b (!C2Scene_MetaPtr),Y
    AND.b #!C2Scene_TilePalBits
    ASL A
    ASL A
    STA.b !C2Scene_PalBottom
    REP #$20
    LDY.w #C2Scene_Metatile.TopRight
    LDA.b (!C2Scene_MetaPtr),Y
    AND.w #!C2Scene_TileNumMask
    TAX
    SEP #$20
    LDA.l !C2Scene_TileColors,X
    BEQ .bottom
    ORA.b !C2Scene_PalTop
    STA.b [!C6Scene_PicOut]
.bottom:
    REP #$20
    LDY.w #C2Scene_Metatile.BottomRight
    LDA.b (!C2Scene_MetaPtr),Y
    AND.w #!C2Scene_TileNumMask
    TAX
    SEP #$20
    LDY.w #!C6Scene_PixelRowBytes
    LDA.l !C2Scene_TileColors,X
    BEQ .done
    ORA.b !C2Scene_PalBottom
    STA.b [!C6Scene_PicOut],Y
.done:
    RTS

; $C6:E90F — C6Scene_PerspInit (524 bytes with C6Scene_PerspStep, $E90F–$EB1A)
; Script routine (pack 0 +$11F7): sets up HDMA channels 2-5 to M7A, M7B,
; M7C and M7D (indirect, one register written twice: a word a line) from
; C2Scene_HdmaTable[1]-[4] (two runs of 112 lines each; written through
; DP = DP_DMA), turns them on (HDMAEN_Ch2To5), points C2Scene_HdmaValues
; words 2-9 at buffer A of each (C6Scene_PerspM7A..D and 112 bytes on)
; and sets the view: .Angle 0, .Scale $80, .DepthA $A0, .DepthB $60,
; .CenterX $40, .CenterY $70, .Unk2E 0, .Ahead $70, .Tilt 0; then falls
; into the sub-entry C6Scene_PerspStep ($C6:E9F5; also called on its
; own, pack 0 +$124C and 16 more sites to +$1483, most right after
; C6Scene_AddAngle): one frame of the view.
; - c = cos(.Angle) x .Scale and s = sin(.Angle) x .Scale (Trig_Cos1024
;   / Sin1024, magnitudes; their signs go to bits 0 and 1 of C2Tmp_10,
;   which picks the C6Scene_PerspQuadrants handler);
; - C2Scene_DialFlags + 1 (here only a frame toggle): bit 0 set fills
;   buffer A and points words 2-9 at it, clear buffer B
;   (C6Scene_PerspBufBOfs on);
; - the depths: dA = .DepthA x 256 - 56t and dB = .DepthB x 256 - 56t,
;   t = C6Scene_PerspTiltSteps[.Tilt] (8.8; the middle of the 112 line
;   pairs gets the depths themselves); the quadrant handler writes 112
;   pairs of lines (each value twice) and adds t to both depths per pair.
; Quirk, kept: the init's eight C2Scene_HdmaValues words point the
; second runs only 112 bytes (56 lines) into each buffer, but the
; sub-entry it falls into overwrites all eight before the NMI uses them.
; Entry (both): M=1 at C6Scene_PerspInit (8-bit stores; op $4E calls
;        it so), M any at C6Scene_PerspStep (REP #$20 there), X=0, DP=$0000 (saved; DP_DMA for the
;        channel set-up; then C2Tmp_00-$17, C2Scene_HdmaenShadow), DB=$00
;        (the record, C2Scene_DialFlags and the multiplier .w; the sine
;        helpers' table is read long); C2Scene_TaskCur = the task
; Exit (both): as the quadrant handler's (C6Scene_PerspQuad0)
; Calls: Trig_Cos1024, Trig_Sin1024 (JSL); the C6Scene_PerspQuadrants
;   handlers (JMP (abs,X)).
!C6Scene_PerspA = !C2Tmp_00            ; 16-bit |M7A| (|c| / dA), then the signed matrix
!C6Scene_PerspB = !C2Tmp_02            ; 16-bit |M7B| (|s| / dA)
!C6Scene_PerspC = !C2Tmp_04            ; 16-bit M7C (-|s| / dB)
!C6Scene_PerspD = !C2Tmp_06            ; 16-bit M7D (|c| / dB)
!C6Scene_PerspCos = !C2Tmp_08          ; 16-bit |cos| x .Scale
!C6Scene_PerspSin = !C2Tmp_0A          ; 16-bit |sin| x .Scale
!C6Scene_PerspDepthA = !C2Tmp_0C       ; 16-bit dA, 8.8 (C2Tmp_0D: the whole part, the divisor)
!C6Scene_PerspDepthB = !C2Tmp_0E       ; 16-bit dB, 8.8 (C2Tmp_0F)
!C6Scene_PerspSigns = !C2Tmp_10        ; 16-bit sign bits: bit 0 cos, bit 1 sin (then A-D)
!C6Scene_PerspPairs = !C2Tmp_12        ; 8-bit line pairs left
!C6Scene_PerspOfs = !C2Tmp_13          ; 16-bit byte offset of the pair in the buffers
!C6Scene_PerspTilt = !C2Tmp_16         ; 16-bit t: depth step per line pair
C6Scene_PerspInit:
    PHD
    PEA.w !DP_DMA
    PLD
    LDA.b #!C2Scene_HdmaRun112
    STA.l C2Scene_HdmaTable[1].Count0
    STA.l C2Scene_HdmaTable[1].Count1
    STA.l C2Scene_HdmaTable[2].Count0
    STA.l C2Scene_HdmaTable[2].Count1
    STA.l C2Scene_HdmaTable[3].Count0
    STA.l C2Scene_HdmaTable[3].Count1
    STA.l C2Scene_HdmaTable[4].Count0
    STA.l C2Scene_HdmaTable[4].Count1
    TDC                                 ; A = DP's low byte, 0 (B = $43)
    STA.l C2Scene_HdmaTable[1].End
    STA.l C2Scene_HdmaTable[2].End
    STA.l C2Scene_HdmaTable[3].End
    STA.l C2Scene_HdmaTable[4].End
    LDA.b #!DMAP_HdmaIndirect|DMA_MODE_1BYTE_X2
    STA.b DMAP2-!DP_DMA
    STA.b DMAP3-!DP_DMA
    STA.b DMAP4-!DP_DMA
    STA.b DMAP5-!DP_DMA
    LDA.b #!BBAD_M7A
    STA.b BBAD2-!DP_DMA
    INC A                               ; M7B
    STA.b BBAD3-!DP_DMA
    INC A                               ; M7C
    STA.b BBAD4-!DP_DMA
    INC A                               ; M7D
    STA.b BBAD5-!DP_DMA
    LDY.w #C2Scene_HdmaTable[1].Count0&$FFFF
    STY.b A1T2L-!DP_DMA
    LDY.w #C2Scene_HdmaTable[2].Count0&$FFFF
    STY.b A1T3L-!DP_DMA
    LDY.w #C2Scene_HdmaTable[3].Count0&$FFFF
    STY.b A1T4L-!DP_DMA
    LDY.w #C2Scene_HdmaTable[4].Count0&$FFFF
    STY.b A1T5L-!DP_DMA
    LDA.b #!Bank7E
    STA.b A1B2-!DP_DMA
    STA.b DAS2B-!DP_DMA
    STA.b A1B3-!DP_DMA
    STA.b DAS3B-!DP_DMA
    STA.b A1B4-!DP_DMA
    STA.b DAS4B-!DP_DMA
    STA.b A1B5-!DP_DMA
    STA.b DAS5B-!DP_DMA
    PLD
    LDA.b #!HDMAEN_Ch2To5
    TSB.b !C2Scene_HdmaenShadow
    REP #$20
    LDA.w #!C6Scene_PerspM7A&$FFFF
    STA.l !C2Scene_HdmaValues+4
    LDA.w #(!C6Scene_PerspM7A+!C6Scene_PerspInitRun)&$FFFF
    STA.l !C2Scene_HdmaValues+6
    LDA.w #!C6Scene_PerspM7B&$FFFF
    STA.l !C2Scene_HdmaValues+8
    LDA.w #(!C6Scene_PerspM7B+!C6Scene_PerspInitRun)&$FFFF
    STA.l !C2Scene_HdmaValues+10
    LDA.w #!C6Scene_PerspM7C&$FFFF
    STA.l !C2Scene_HdmaValues+12
    LDA.w #(!C6Scene_PerspM7C+!C6Scene_PerspInitRun)&$FFFF
    STA.l !C2Scene_HdmaValues+14
    LDA.w #!C6Scene_PerspM7D&$FFFF
    STA.l !C2Scene_HdmaValues+16
    LDA.w #(!C6Scene_PerspM7D+!C6Scene_PerspInitRun)&$FFFF
    STA.l !C2Scene_HdmaValues+18
    LDX.b !C2Scene_TaskCur
    STZ.w C6Scene_PerspTask.Angle,X
    LDA.w #!C6Scene_PerspScale0
    STA.w C6Scene_PerspTask.Scale,X
    LDA.w #!C6Scene_PerspDepthA0
    STA.w C6Scene_PerspTask.DepthA,X
    LDA.w #!C6Scene_PerspDepthB0
    STA.w C6Scene_PerspTask.DepthB,X
    LDA.w #!C6Scene_PerspCenterX0
    STA.w C6Scene_PerspTask.CenterX,X
    LDA.w #!C6Scene_PerspCenterY0
    STA.w C6Scene_PerspTask.CenterY,X
    LDA.w #0
    STA.w C6Scene_PerspTask.Unk2E,X
    LDA.w #!C6Scene_PerspAhead0
    STA.w C6Scene_PerspTask.Ahead,X
    STZ.w C6Scene_PerspTask.Tilt,X
C6Scene_PerspStep:                      ; header: see C6Scene_PerspInit
    REP #$20
    LDX.b !C2Scene_TaskCur
    STZ.b !C6Scene_PerspSigns
    TXY
    LDA.w C6Scene_PerspTask.Angle,Y
    JSL Trig_Cos1024
    STA.w !C6Scene_PerspA               ; absolute: the same byte as DP $00 here
    TAX                                 ; (for the N flag)
    BPL .cos_abs
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C6Scene_PerspA
    LDA.w #!C6Scene_SignA
    TSB.b !C6Scene_PerspSigns
.cos_abs:
    LDA.w C6Scene_PerspTask.Angle,Y
    JSL Trig_Sin1024
    STA.b !C6Scene_PerspB
    TAX
    BPL .sin_abs
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C6Scene_PerspB
    LDA.w #!C6Scene_SignB
    TSB.b !C6Scene_PerspSigns
.sin_abs:
    LDA.w C6Scene_PerspTask.Scale,Y
    STA.b !C6Scene_PerspC
    SEP #$10
    LDX.b !C6Scene_PerspC               ; .Scale's low byte
    LDY.b !C6Scene_PerspA               ; |cos| (0-255)
    STX.w WRMPYA
    STY.w WRMPYB
    LDY.b !C6Scene_PerspB
    REP #$20
    LDA.w RDMPYL
    STA.b !C6Scene_PerspCos
    STY.w WRMPYB
    NOP
    REP #$30
    LDA.w RDMPYL
    STA.b !C6Scene_PerspSin
    SEP #$20
    INC.w !C2Scene_DialFlags
    LDA.w !C2Scene_DialFlags
    LSR A
    REP #$20
    BCC .buf_b
    STZ.b !C6Scene_PerspOfs
    LDA.w #!C6Scene_PerspM7A&$FFFF
    STA.l !C2Scene_HdmaValues+4
    LDA.w #(!C6Scene_PerspM7A+!C2Scene_HdmaHalfBytes)&$FFFF
    STA.l !C2Scene_HdmaValues+6
    LDA.w #!C6Scene_PerspM7B&$FFFF
    STA.l !C2Scene_HdmaValues+8
    LDA.w #(!C6Scene_PerspM7B+!C2Scene_HdmaHalfBytes)&$FFFF
    STA.l !C2Scene_HdmaValues+10
    LDA.w #!C6Scene_PerspM7C&$FFFF
    STA.l !C2Scene_HdmaValues+12
    LDA.w #(!C6Scene_PerspM7C+!C2Scene_HdmaHalfBytes)&$FFFF
    STA.l !C2Scene_HdmaValues+14
    LDA.w #!C6Scene_PerspM7D&$FFFF
    STA.l !C2Scene_HdmaValues+16
    LDA.w #(!C6Scene_PerspM7D+!C2Scene_HdmaHalfBytes)&$FFFF
    STA.l !C2Scene_HdmaValues+18
    BRA .depths
.buf_b:
    LDA.w #!C6Scene_PerspBufBOfs
    STA.b !C6Scene_PerspOfs
    LDA.w #(!C6Scene_PerspM7A+!C6Scene_PerspBufBOfs)&$FFFF
    STA.l !C2Scene_HdmaValues+4
    LDA.w #(!C6Scene_PerspM7A+!C6Scene_PerspBufBOfs+!C2Scene_HdmaHalfBytes)&$FFFF
    STA.l !C2Scene_HdmaValues+6
    LDA.w #(!C6Scene_PerspM7B+!C6Scene_PerspBufBOfs)&$FFFF
    STA.l !C2Scene_HdmaValues+8
    LDA.w #(!C6Scene_PerspM7B+!C6Scene_PerspBufBOfs+!C2Scene_HdmaHalfBytes)&$FFFF
    STA.l !C2Scene_HdmaValues+10
    LDA.w #(!C6Scene_PerspM7C+!C6Scene_PerspBufBOfs)&$FFFF
    STA.l !C2Scene_HdmaValues+12
    LDA.w #(!C6Scene_PerspM7C+!C6Scene_PerspBufBOfs+!C2Scene_HdmaHalfBytes)&$FFFF
    STA.l !C2Scene_HdmaValues+14
    LDA.w #(!C6Scene_PerspM7D+!C6Scene_PerspBufBOfs)&$FFFF
    STA.l !C2Scene_HdmaValues+16
    LDA.w #(!C6Scene_PerspM7D+!C6Scene_PerspBufBOfs+!C2Scene_HdmaHalfBytes)&$FFFF
    STA.l !C2Scene_HdmaValues+18
.depths:
    SEP #$20
    LDY.b !C2Scene_TaskCur
    LDA.w C6Scene_PerspTask.DepthA,Y
    STA.b !C6Scene_PerspDepthA+1
    STZ.b !C6Scene_PerspDepthA
    LDA.w C6Scene_PerspTask.DepthB,Y
    STA.b !C6Scene_PerspDepthB+1
    STZ.b !C6Scene_PerspDepthB
    LDX.w C6Scene_PerspTask.Tilt,Y
    LDA.l C6Scene_PerspTiltSteps,X
    STA.b !C6Scene_PerspTilt
    STZ.b !C6Scene_PerspTilt+1
    STA.w WRMPYA
    LDA.b #!C6Scene_PerspMidPair
    STA.w WRMPYB
    REP #$20
    SEC
    LDA.b !C6Scene_PerspDepthA
    SBC.w RDMPYL
    STA.b !C6Scene_PerspDepthA
    SEC
    LDA.b !C6Scene_PerspDepthB
    SBC.w RDMPYL
    STA.b !C6Scene_PerspDepthB
    SEP #$20
    TDC                                 ; B = 0 for the TAX below
    LDA.b #!C6Scene_PerspLinePairs
    STA.b !C6Scene_PerspPairs
    LDA.b !C6Scene_PerspSigns
    ASL A
    TAX
    JMP (C6Scene_PerspQuadrants,X)

; $C6:EB1B — C6Scene_PerspQuadrants (4 words, $EB1B–$EB22)
; C6Scene_PerspStep's fill for each sign pair (index = C2Tmp_10 bits 0-1:
; cos < 0, sin < 0).
C6Scene_PerspQuadrants:
    dw C6Scene_PerspQuad0               ; cos >= 0, sin >= 0
    dw C6Scene_PerspQuad1               ; cos < 0
    dw C6Scene_PerspQuad2               ; sin < 0
    dw C6Scene_PerspQuad3               ; both < 0

; $C6:EB23 — C6Scene_PerspTiltSteps (24 bytes, $EB23–$EB3A)
; The depth step t per line pair (8.8, so 0 to just under 1), read by
; C6Scene_PerspStep at .Tilt (a byte offset; pack 0 steps it with op $0B
; between turns). Rising faster towards the end, the last two $FF.
C6Scene_PerspTiltSteps:
    db $00,$08,$11,$1A,$23,$2D,$36,$3F,$49,$53,$5D,$67
    db $71,$7C,$88,$93,$9F,$AC,$B9,$C8,$D6,$E6,$FF,$FF

; $C6:EB3B — C6Scene_PerspQuad0 (458 bytes with C6Scene_PerspQuad1-3 and C6Scene_PerspTail, $EB3B–$ED04)
; The fills of C6Scene_PerspStep, one per quadrant (C6Scene_PerspQuad0
; and the sub-entries C6Scene_PerspQuad1 ($C6:EB96), C6Scene_PerspQuad2
; ($C6:EC09) and C6Scene_PerspQuad3 ($C6:EC7C), reached through
; C6Scene_PerspQuadrants): for each of the 112 line
; pairs, C6Scene_PerspDivide gives |c| / dA, |s| / dA, -|s| / dB and |c|
; / dB (dA, dB: the whole parts of the depths) and the handler stores
; them, signed by its quadrant (Quad0 as they are; Quad1 negates M7A and
; M7D, Quad2 M7B and M7C, Quad3 all four), twice each (two lines) into
; C6Scene_PerspM7A..D at C2Tmp_13, then adds t to both depths. So the
; usual rotation matrix (cos, sin; -sin, cos), each row scaled by .Scale
; / its depth: the scale changes down the screen, a slanted view,
; probably. Then the matrix of the middle depths (.DepthA, .DepthB
; themselves) with the same signs, and the shared tail
; C6Scene_PerspTail ($C6:ED04; JMP from Quad0-2, Quad3 falls in): the
; signs of B and D to C2Tmp_10 bits 1 and 3 (A, C to bits 0 and 2) and
; their magnitudes; M7X = .CenterX + .Ahead x B / 256 and M7Y = .CenterY +
; .Ahead x D / 256 (low byte of .Ahead; each product rounded up from a
; half, then signed), C2Scene_Bg1HScroll = M7X - C6Scene_PerspPivotX and
; C2Scene_Bg1VScroll = M7Y - C6Scene_PerspPivotY: the turning point sits
; at the bottom middle of the screen and moves ahead of the view's
; centre, probably.
; Quirk, kept: the tail reads .Unk2E into C2Tmp_08 and never uses it.
; Callers note: the handlers are reached through C6Scene_PerspQuadrants
;   (C6Scene_PerspStep's JMP (abs,X)); Quad0-2 end with JMP
;   C6Scene_PerspTail.
; Entry (all five): M=1 (8-bit loop count; M=0 at C6Scene_PerspTail),
;        X=0, DP=$0000 (TDC as zero; C2Tmp_00-$17, the PPU shadows),
;        DB=$00 (the record and the divider/multiplier .w; the buffers
;        long); C2Tmp_08/0A/0C/0E/12/13/16 as C6Scene_PerspStep leaves
;        them; C2Scene_TaskCur = the task
; Exit (all five): M=0, X=0; X = the task; A = the new
;        C2Scene_Bg1VScroll; Y = |D| / 256; C2Scene_M7X/M7Y and
;        C2Scene_Bg1HScroll/Bg1VScroll set; C2Tmp_00-$17 changed
; Calls: C6Scene_PerspDivide.
C6Scene_PerspQuad0:
    JSR C6Scene_PerspDivide
    LDX.b !C6Scene_PerspOfs
    LDA.b !C6Scene_PerspA
    STA.l !C6Scene_PerspM7A,X
    STA.l !C6Scene_PerspM7A+2,X
    LDA.b !C6Scene_PerspB
    STA.l !C6Scene_PerspM7B,X
    STA.l !C6Scene_PerspM7B+2,X
    LDA.b !C6Scene_PerspC
    STA.l !C6Scene_PerspM7C,X
    STA.l !C6Scene_PerspM7C+2,X
    LDA.b !C6Scene_PerspD
    STA.l !C6Scene_PerspM7D,X
    STA.l !C6Scene_PerspM7D+2,X
    INX
    INX
    INX
    INX
    STX.b !C6Scene_PerspOfs
    CLC
    LDA.b !C6Scene_PerspDepthA
    ADC.b !C6Scene_PerspTilt
    STA.b !C6Scene_PerspDepthA
    CLC
    LDA.b !C6Scene_PerspDepthB
    ADC.b !C6Scene_PerspTilt
    STA.b !C6Scene_PerspDepthB
    SEP #$20
    DEC.b !C6Scene_PerspPairs
    BNE C6Scene_PerspQuad0
    LDX.b !C2Scene_TaskCur
    LDA.w C6Scene_PerspTask.DepthA,X
    STA.b !C6Scene_PerspDepthA+1
    LDA.w C6Scene_PerspTask.DepthB,X
    STA.b !C6Scene_PerspDepthB+1
    JSR C6Scene_PerspDivide
    REP #$20
    JMP C6Scene_PerspTail
C6Scene_PerspQuad1:                     ; header: see C6Scene_PerspQuad0
    JSR C6Scene_PerspDivide
    LDX.b !C6Scene_PerspOfs
    LDA.b !C6Scene_PerspA
    EOR.w #!Eng_Invert16
    INC A
    STA.l !C6Scene_PerspM7A,X
    STA.l !C6Scene_PerspM7A+2,X
    LDA.b !C6Scene_PerspB
    STA.l !C6Scene_PerspM7B,X
    STA.l !C6Scene_PerspM7B+2,X
    LDA.b !C6Scene_PerspC
    STA.l !C6Scene_PerspM7C,X
    STA.l !C6Scene_PerspM7C+2,X
    LDA.b !C6Scene_PerspD
    EOR.w #!Eng_Invert16
    INC A
    STA.l !C6Scene_PerspM7D,X
    STA.l !C6Scene_PerspM7D+2,X
    INX
    INX
    INX
    INX
    STX.b !C6Scene_PerspOfs
    CLC
    LDA.b !C6Scene_PerspDepthA
    ADC.b !C6Scene_PerspTilt
    STA.b !C6Scene_PerspDepthA
    CLC
    LDA.b !C6Scene_PerspDepthB
    ADC.b !C6Scene_PerspTilt
    STA.b !C6Scene_PerspDepthB
    SEP #$20
    DEC.b !C6Scene_PerspPairs
    BNE C6Scene_PerspQuad1
    LDX.b !C2Scene_TaskCur
    LDA.w C6Scene_PerspTask.DepthA,X
    STA.b !C6Scene_PerspDepthA+1
    LDA.w C6Scene_PerspTask.DepthB,X
    STA.b !C6Scene_PerspDepthB+1
    JSR C6Scene_PerspDivide
    REP #$20
    LDA.b !C6Scene_PerspA
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C6Scene_PerspA
    LDA.b !C6Scene_PerspD
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C6Scene_PerspD
    JMP C6Scene_PerspTail
C6Scene_PerspQuad2:                     ; header: see C6Scene_PerspQuad0
    JSR C6Scene_PerspDivide
    LDX.b !C6Scene_PerspOfs
    LDA.b !C6Scene_PerspA
    STA.l !C6Scene_PerspM7A,X
    STA.l !C6Scene_PerspM7A+2,X
    LDA.b !C6Scene_PerspB
    EOR.w #!Eng_Invert16
    INC A
    STA.l !C6Scene_PerspM7B,X
    STA.l !C6Scene_PerspM7B+2,X
    LDA.b !C6Scene_PerspC
    EOR.w #!Eng_Invert16
    INC A
    STA.l !C6Scene_PerspM7C,X
    STA.l !C6Scene_PerspM7C+2,X
    LDA.b !C6Scene_PerspD
    STA.l !C6Scene_PerspM7D,X
    STA.l !C6Scene_PerspM7D+2,X
    INX
    INX
    INX
    INX
    STX.b !C6Scene_PerspOfs
    CLC
    LDA.b !C6Scene_PerspDepthA
    ADC.b !C6Scene_PerspTilt
    STA.b !C6Scene_PerspDepthA
    CLC
    LDA.b !C6Scene_PerspDepthB
    ADC.b !C6Scene_PerspTilt
    STA.b !C6Scene_PerspDepthB
    SEP #$20
    DEC.b !C6Scene_PerspPairs
    BNE C6Scene_PerspQuad2
    LDX.b !C2Scene_TaskCur
    LDA.w C6Scene_PerspTask.DepthA,X
    STA.b !C6Scene_PerspDepthA+1
    LDA.w C6Scene_PerspTask.DepthB,X
    STA.b !C6Scene_PerspDepthB+1
    JSR C6Scene_PerspDivide
    REP #$20
    LDA.b !C6Scene_PerspB
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C6Scene_PerspB
    LDA.b !C6Scene_PerspC
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C6Scene_PerspC
    JMP C6Scene_PerspTail
C6Scene_PerspQuad3:                     ; header: see C6Scene_PerspQuad0
    JSR C6Scene_PerspDivide
    LDX.b !C6Scene_PerspOfs
    LDA.b !C6Scene_PerspA
    EOR.w #!Eng_Invert16
    INC A
    STA.l !C6Scene_PerspM7A,X
    STA.l !C6Scene_PerspM7A+2,X
    LDA.b !C6Scene_PerspB
    EOR.w #!Eng_Invert16
    INC A
    STA.l !C6Scene_PerspM7B,X
    STA.l !C6Scene_PerspM7B+2,X
    LDA.b !C6Scene_PerspC
    EOR.w #!Eng_Invert16
    INC A
    STA.l !C6Scene_PerspM7C,X
    STA.l !C6Scene_PerspM7C+2,X
    LDA.b !C6Scene_PerspD
    EOR.w #!Eng_Invert16
    INC A
    STA.l !C6Scene_PerspM7D,X
    STA.l !C6Scene_PerspM7D+2,X
    INX
    INX
    INX
    INX
    STX.b !C6Scene_PerspOfs
    CLC
    LDA.b !C6Scene_PerspDepthA
    ADC.b !C6Scene_PerspTilt
    STA.b !C6Scene_PerspDepthA
    CLC
    LDA.b !C6Scene_PerspDepthB
    ADC.b !C6Scene_PerspTilt
    STA.b !C6Scene_PerspDepthB
    SEP #$20
    DEC.b !C6Scene_PerspPairs
    BNE C6Scene_PerspQuad3
    LDX.b !C2Scene_TaskCur
    LDA.w C6Scene_PerspTask.DepthA,X
    STA.b !C6Scene_PerspDepthA+1
    LDA.w C6Scene_PerspTask.DepthB,X
    STA.b !C6Scene_PerspDepthB+1
    JSR C6Scene_PerspDivide
    REP #$20
    LDA.b !C6Scene_PerspA
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C6Scene_PerspA
    LDA.b !C6Scene_PerspB
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C6Scene_PerspB
    LDA.b !C6Scene_PerspC
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C6Scene_PerspC
    LDA.b !C6Scene_PerspD
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C6Scene_PerspD
C6Scene_PerspTail:                      ; header: see C6Scene_PerspQuad0
    STZ.b !C6Scene_PerspSigns
    LDA.b !C6Scene_PerspA
    BPL .a_pos
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C6Scene_PerspA
    LDA.w #!C6Scene_SignA
    TSB.b !C6Scene_PerspSigns
.a_pos:
    LDA.b !C6Scene_PerspB
    BPL .b_pos
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C6Scene_PerspB
    LDA.w #!C6Scene_SignB
    TSB.b !C6Scene_PerspSigns
.b_pos:
    LDA.b !C6Scene_PerspC
    BPL .c_pos
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C6Scene_PerspC
    LDA.w #!C6Scene_SignC
    TSB.b !C6Scene_PerspSigns
.c_pos:
    LDA.b !C6Scene_PerspD
    BPL .d_pos
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C6Scene_PerspD
    LDA.w #!C6Scene_SignD
    TSB.b !C6Scene_PerspSigns
.d_pos:
    LDY.b !C2Scene_TaskCur
    LDA.w C6Scene_PerspTask.Unk2E,Y
    STA.b !C6Scene_PerspCos             ; never read (see the header)
    LDA.w C6Scene_PerspTask.Ahead,Y
    STA.b !C6Scene_PerspSin             ; .Ahead (only the low byte is used)
    SEP #$30
    LDX.b !C6Scene_PerspSin
    LDY.b !C6Scene_PerspB               ; |B|'s low byte
    STX.w WRMPYA
    STY.w WRMPYB
    LDY.b !C6Scene_PerspB+1             ; its high byte
    TDC                                 ; B = 0
    LDA.w RDMPYL
    TAX                                 ; (for the rounding)
    LDA.w RDMPYH
    STY.w WRMPYB
    REP #$30
    CLC
    ADC.w RDMPYL                        ; .Ahead x |B| / 256
    STA.b !C6Scene_PerspDepthA
    TXA
    BIT.w #!C6Scene_RoundBit
    BEQ .x_rounded
    INC.b !C6Scene_PerspDepthA
.x_rounded:
    LDA.b !C6Scene_PerspSigns
    BIT.w #!C6Scene_SignB
    BEQ .x_signed
    LDA.b !C6Scene_PerspDepthA
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C6Scene_PerspDepthA
.x_signed:
    SEP #$30
    LDX.b !C6Scene_PerspSin
    LDY.b !C6Scene_PerspD
    STX.w WRMPYA
    STY.w WRMPYB
    LDY.b !C6Scene_PerspD+1
    TDC
    LDA.w RDMPYL
    TAX
    LDA.w RDMPYH
    STY.w WRMPYB
    REP #$30
    CLC
    ADC.w RDMPYL                        ; .Ahead x |D| / 256
    STA.b !C6Scene_PerspDepthB
    TXA
    BIT.w #!C6Scene_RoundBit
    BEQ .y_rounded
    INC.b !C6Scene_PerspDepthB
.y_rounded:
    LDA.b !C6Scene_PerspSigns
    BIT.w #!C6Scene_SignD
    BEQ .y_signed
    LDA.b !C6Scene_PerspDepthB
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C6Scene_PerspDepthB
.y_signed:
    LDX.b !C2Scene_TaskCur
    CLC
    LDA.w C6Scene_PerspTask.CenterX,X
    ADC.b !C6Scene_PerspDepthA
    STA.b !C2Scene_M7X
    CLC
    LDA.w C6Scene_PerspTask.CenterY,X
    ADC.b !C6Scene_PerspDepthB
    STA.b !C2Scene_M7Y
    CLC
    LDA.b !C2Scene_M7X
    ADC.w #($10000-!C6Scene_PerspPivotX)
    STA.b !C2Scene_Bg1HScroll
    CLC
    LDA.b !C2Scene_M7Y
    ADC.w #($10000-!C6Scene_PerspPivotY)
    STA.b !C2Scene_Bg1VScroll
    RTL

; $C6:EDE1 — C6Scene_PerspDivide (66 bytes, $EDE1–$EE22)
; The four quotients of a line pair (WRDIV/RDDIV): C2Tmp_00 = |c| / dA,
; C2Tmp_02 = |s| / dA, C2Tmp_04 = -(|s| / dB), C2Tmp_06 = |c| / dB, with
; |c|, |s| = C2Tmp_08, C2Tmp_0A and the 8-bit divisors dA = C2Tmp_0D, dB
; = C2Tmp_0F (the whole parts of the depths). The divisions are chained:
; each dividend is written to WRDIVL/H before the quotient of the one
; under way is read, and |s| is written twice. A divisor of 0 is not
; checked.
; Callers note: all eight sites are the C6Scene_PerspQuad0-3 handlers'.
; Callers (8 JSR sites): C6Scene_PerspQuad0 ($C6:EB3B, $C6:EB8E), C6Scene_PerspQuad1 ($C6:EB96,
;   $C6:EBF1), C6Scene_PerspQuad2 ($C6:EC09, $C6:EC64) and C6Scene_PerspQuad3 ($C6:EC7C, $C6:ECDF).
; Entry: M=1 (8-bit divisors), X=0 (16-bit dividends and quotients),
;        DP=$0000 (C2Tmp_00-$0F), DB=$00 (the divider .w)
; Exit:  M=0, X=0; A = C2Tmp_04; X = C2Tmp_08; Y = C2Tmp_06
; No calls.
C6Scene_PerspDivide:
    LDX.b !C6Scene_PerspCos
    LDA.b !C6Scene_PerspDepthA+1
    STX.w WRDIVL
    STA.w WRDIVB                        ; |c| / dA
    LDX.b !C6Scene_PerspSin
    STX.w WRDIVL
    NOP
    NOP
    LDY.w RDDIVL
    STA.w WRDIVB                        ; |s| / dA
    STY.b !C6Scene_PerspA
    NOP
    STX.w WRDIVL
    LDA.b !C6Scene_PerspDepthB+1
    LDY.w RDDIVL
    STA.w WRDIVB                        ; |s| / dB
    STY.b !C6Scene_PerspB
    LDX.b !C6Scene_PerspCos
    STX.w WRDIVL
    NOP
    LDY.w RDDIVL
    STA.w WRDIVB                        ; |c| / dB
    REP #$20
    TYA
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C6Scene_PerspC
    LDY.w RDDIVL
    STY.b !C6Scene_PerspD
    RTS

; ============================================================
; Small script routines ($C6:EE23–$C6:EE42) and the fill after them
; ============================================================

; $C6:EE23 — C6Scene_AddAngle (14 bytes, $EE23–$EE30)
; Script routine (pack 0 +$1248 and 14 more sites to +$146F, each before
; C6Scene_PerspStep; the script sets C2Tmp_08/09 with op $13 first, e.g.
; $FFFE): .Angle (+$22) + C2Tmp_08.
; Entry: M any (REP #$20 here), X=0, DP=$0000 (C2Tmp_08), DB=$00 (the
;        record .w); C2Scene_TaskCur = the task
; Exit:  M=0, X=0; X = the task; A = the new .Angle; Y unchanged
; No calls.
C6Scene_AddAngle:
    REP #$20
    LDX.b !C2Scene_TaskCur
    CLC
    LDA.b !C2Tmp_08
    ADC.w C6Scene_PerspTask.Angle,X
    STA.w C6Scene_PerspTask.Angle,X
    RTL

; $C6:EE31 — C6Scene_SetUnk7F00CD (7 bytes, $EE31–$EE37)
; Script routine (pack 2 +$09A3 and +$09AE, pack 7 +$0779, +$0A27,
; +$0A32, +$0A5F, +$0A6A): C2Scene_Unk7F00CD = C2Tmp_00 (8-bit; set by
; the script before).
; Entry: M=1 (8-bit; op $4E calls it so), X any, DP=$0000 (C2Tmp_00), DB
;        any (long store)
; Exit:  M=1; A = C2Tmp_00; X, Y unchanged
; No calls.
C6Scene_SetUnk7F00CD:
    LDA.b !C2Tmp_00
    STA.l !C2Scene_Unk7F00CD
    RTL

; $C6:EE38 — C6Scene_ClearUnk7F01F5Bit0 (11 bytes, $EE38–$EE42)
; Script routine (pack 2 +$08CF): clears bit 0 of C2Scene_Unk7F01F5.
; Entry: M=1 (8-bit; op $4E calls it so), X any, DP any, DB any (long
;        addressing)
; Exit:  M=1; A = the new byte; X, Y unchanged
; No calls.
C6Scene_ClearUnk7F01F5Bit0:
    LDA.l !C2Scene_Unk7F01F5
    AND.b #!C6Scene_Unk7F01F5Keep
    STA.l !C2Scene_Unk7F01F5
    RTL

; $C6:EE43 — BankC6_CodeEndFill (445 bytes, $EE43–$EFFF)
; $00 fill after the last routine, up to the data from $C6:F000 on. No
; reference to it was found.
BankC6_CodeEndFill:
    fillbyte $00
    fill $C6F000-$C6EE43
