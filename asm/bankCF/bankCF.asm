; ============================================================
; Bank $CF — battle support
; File offset 0x0F0000 (bank $CF = ROM offset $F0000)
;
; $CF:0000-$CF:E2FF is data (left as ROM bytes). From $CF:E300 on the
; bank holds battle-engine code reached from bank $C1: the vblank uploads
; and the per-frame update behind the $C1:0009/$000C vectors, the sprite
; builder, the action movers, the battle entry ($C1:001B) and exit
; ($C1:001F), service 6, and helpers the battle menu calls by JSL. It
; uses the battle engine's RAM names. Nothing here is reached from the
; field engine except through those bank-$C1 vectors.
; ============================================================

arch snes.cpu
hirom

; ============================================================
; Vertical-blank uploads ($CF:E300–$CF:E589)
; ============================================================

; $CF:E300 — BattleCF_VblankUploads (650 bytes, $E300–$E589)
; Copies the battle's buffers to the PPU by DMA on channel 7, which needs
; vertical blank or forced blank: hence "vblank", inferred (the caller at
; $CD:08B4 is not matched). In order:
;   - OAM: $220 bytes from BattleOam (bank $00 mirror of $7E:0700), OAM
;     address 0;
;   - when !Battle_VramQPending is set, the one VRAM upload that
;     Battle_QueueVramUpload_0CC0 / _A6E1 / _0E80 described in
;     !Battle_VramQDmap..!Battle_VramQAddrHi; then clears the flag;
;   - when !BattleMenu_WindowMapDirty is set, !BattleMenu_WindowMap
;     ($180 bytes) to VRAM word $7A00 (!Battle_WindowMapVram); clears it;
;   - CGRAM: all $200 bytes of !Battle_PaletteLiveLo (bank $7E), from
;     colour 0;
;   - when no action runs (!Battle_ActRunning = 0) and !Battle_UnkE5 is
;     set: step !Battle_UnkA4 (0-3) of the graphics uploads in the
;     !BattleRom_GfxStep* tables (one or two blocks from bank $7E), then
;     !Battle_UnkA4 counts on, wrapping 3 -> 0;
;   - when !Battle_ActFrameHold is 1 (BattleCF_FrameUpdate brings the 2
;     a decoded frame leaves down to 1): clears it and, unless battler
;     !Battle_FrameSlot uses !Battle_FrameLayoutStrip or a later layout,
;     uploads its two tile blocks described by the per-slot words
;     !Battler_FrameDmaSrcA/B, !Battler_FrameDmaVramA/B and
;     !Battler_FrameDmaSizeA/B (who fills those is not traced);
;   - when !Battle_UnkA118 counts down to 0: step 0 of the graphics
;     uploads again (without touching !Battle_UnkA4).
; A second block of a graphics step with size 0 is skipped (step 3).
; The graphics steps' sources lie in the battlers' decoded-frame buffers
; (!BattleRom_FrameDestBase gives $64AD, $67AD, $68AD, ...), so a step
; probably sends the frames of a group of battlers (!Battle_UnkA4 1-3
; also picks the enemy group Battle_TickPcSlots ticks); not traced
; further.
; Callers (1 JML site): BankC1_JmlCFE300 ($C1:0076).
; Entry: M=1, X=0, DP=0 (DP $A0, $A4, $E5; TDC as zero), DB=$7E (the
;        queue, per-slot words and flags are read .w)
; Exit:  M=1, X=0, DP=0, DB=$7E; A and X clobbered (X = !Battle_UnkA4 * 2
;        or the slot * 2 on the paths that index); Y unchanged
; Callers note: reached only by the JML at $C1:0076 (BankC1_JmlCFE300),
;   which the vector BankC1_VecCFE300 ($C1:0009) jumps to; that vector is
;   JSL'd from $CD:08B4 (unmatched), so the RTL here returns there.
; No JSR/JSL calls.
org $CFE300
BattleCF_VblankUploads:
    TDC
    STA.l DMAP7                         ; mode 0: one register
    LDA.b #!BBAD_OAMDATA
    STA.l BBAD7
    LDA.b #BattleOam.X&$FF
    STA.l A1T7L
    LDA.b #BattleOam.X>>8
    STA.l A1T7H
    LDA.b #$00                          ; bank $00 (the low WRAM mirror)
    STA.l A1B7
    LDA.b #!Battle_OamBytes&$FF
    STA.l DAS7L
    LDA.b #!Battle_OamBytes>>8
    STA.l DAS7H
    TDC
    STA.l OAMADDL
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    LDA.b !Battle_VramQPending
    BEQ .no_queued
    LDA.w !Battle_VramQDmap
    STA.l DMAP7
    LDA.w !Battle_VramQBbad
    STA.l BBAD7
    LDA.w !Battle_VramQSrcLo
    STA.l A1T7L
    LDA.w !Battle_VramQSrcHi
    STA.l A1T7H
    LDA.w !Battle_VramQSrcBank
    STA.l A1B7
    LDA.w !Battle_VramQSizeLo
    STA.l DAS7L
    LDA.w !Battle_VramQSizeHi
    STA.l DAS7H
    LDA.w !Battle_VramQAddrLo
    STA.l VMADDL
    LDA.w !Battle_VramQAddrHi
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    STZ.b !Battle_VramQPending
.no_queued:
    LDA.w !BattleMenu_WindowMapDirty
    BEQ .no_window
    LDA.b #!DMAP_TwoRegs
    STA.l DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.l BBAD7
    LDA.b #!BattleMenu_WindowMap&$FF
    STA.l A1T7L
    LDA.b #!BattleMenu_WindowMap>>8
    STA.l A1T7H
    LDA.b #$00                          ; bank $00
    STA.l A1B7
    LDA.b #!BattleMenu_WindowBytes&$FF
    STA.l DAS7L
    LDA.b #!BattleMenu_WindowBytes>>8
    STA.l DAS7H
    LDA.b #!Battle_WindowMapVram&$FF
    STA.l VMADDL
    LDA.b #!Battle_WindowMapVram>>8
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    STZ.w !BattleMenu_WindowMapDirty
.no_window:
    LDA.b #$00                          ; mode 0: one register
    STA.l DMAP7
    LDA.b #!BBAD_CGDATA
    STA.l BBAD7
    LDA.b #!Battle_PaletteLiveLo&$FF
    STA.l A1T7L
    LDA.b #!Battle_PaletteLiveLo>>8
    STA.l A1T7H
    LDA.b #!Battle_WramBank
    STA.l A1B7
    LDA.b #!Battle_CgramBytes&$FF
    STA.l DAS7L
    LDA.b #!Battle_CgramBytes>>8
    STA.l DAS7H
    TDC
    STA.l CGADD
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    LDA.w !Battle_ActRunning
    BNE .skip_gfx_step
    LDA.b !Battle_UnkE5
    BNE .gfx_step
.skip_gfx_step:
    JMP .frame_upload
.gfx_step:
    LDA.b !Battle_UnkA4
    ASL A
    TAX                                 ; X = step * 2
    LDA.b #!DMAP_TwoRegs
    STA.l DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.l BBAD7
    LDA.l !BattleRom_GfxStepSrcA,X
    STA.l A1T7L
    LDA.l !BattleRom_GfxStepSrcA+1,X
    STA.l A1T7H
    LDA.b #!Battle_WramBank
    STA.l A1B7
    REP #$20
    LDA.l !BattleRom_GfxStepSizeA,X
    STA.l DAS7L
    LDA.l !BattleRom_GfxStepVramA,X
    STA.l VMADDL
    TDC
    SEP #$20
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    LDA.l !BattleRom_GfxStepSrcB,X
    STA.l A1T7L
    LDA.l !BattleRom_GfxStepSrcB+1,X
    STA.l A1T7H
    REP #$20
    LDA.l !BattleRom_GfxStepSizeB,X
    BNE .gfx_second
    TDC
    SEP #$20
    BRA .gfx_next
.gfx_second:
    STA.l DAS7L
    LDA.l !BattleRom_GfxStepVramB,X
    STA.l VMADDL
    TDC
    SEP #$20
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
.gfx_next:
    INC.b !Battle_UnkA4
    LDA.b !Battle_UnkA4
    CMP.b #!Battle_GfxSteps
    BNE .frame_upload
    STZ.b !Battle_UnkA4
.frame_upload:
    LDA.w !Battle_ActFrameHold
    BEQ .frame_none
    CMP.b #$01
    BEQ .frame_due
.frame_none:
    JMP .unk_a118
.frame_due:
    STZ.w !Battle_ActFrameHold
    LDA.w !Battle_FrameSlot
    TAX
    LDA.w !Battler_FrameLayout,X
    CMP.b #!Battle_FrameLayoutStrip
    BCS .unk_a118
    TXA
    ASL A
    TAX                                 ; X = slot * 2
    LDA.b #!DMAP_TwoRegs
    STA.l DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.l BBAD7
    LDA.w !Battler_FrameDmaSrcA,X
    STA.l A1T7L
    LDA.w !Battler_FrameDmaSrcA+1,X
    STA.l A1T7H
    LDA.b #!Battle_WramBank
    STA.l A1B7
    LDA.w !Battler_FrameDmaSizeA,X
    STA.l DAS7L
    LDA.w !Battler_FrameDmaSizeA+1,X
    STA.l DAS7H
    LDA.w !Battler_FrameDmaVramA,X
    STA.l VMADDL
    LDA.w !Battler_FrameDmaVramA+1,X
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    LDA.w !Battler_FrameDmaSrcB,X
    STA.l A1T7L
    LDA.w !Battler_FrameDmaSrcB+1,X
    STA.l A1T7H
    LDA.w !Battler_FrameDmaSizeB,X
    STA.l DAS7L
    LDA.w !Battler_FrameDmaSizeB+1,X
    STA.l DAS7H
    LDA.w !Battler_FrameDmaVramB,X
    STA.l VMADDL
    LDA.w !Battler_FrameDmaVramB+1,X
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
.unk_a118:
    LDA.w !Battle_UnkA118
    BEQ .done
    DEC.w !Battle_UnkA118
    BNE .done
    LDA.b #!DMAP_TwoRegs
    STA.l DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.l BBAD7
    LDA.l !BattleRom_GfxStepSrcA
    STA.l A1T7L
    LDA.l !BattleRom_GfxStepSrcA+1
    STA.l A1T7H
    LDA.b #!Battle_WramBank
    STA.l A1B7
    REP #$20
    LDA.l !BattleRom_GfxStepSizeA
    STA.l DAS7L
    LDA.l !BattleRom_GfxStepVramA
    STA.l VMADDL
    TDC
    SEP #$20
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    LDA.l !BattleRom_GfxStepSrcB
    STA.l A1T7L
    LDA.l !BattleRom_GfxStepSrcB+1
    STA.l A1T7H
    REP #$20
    LDA.l !BattleRom_GfxStepSizeB
    BNE .a118_second
    TDC
    SEP #$20
    BRA .done
.a118_second:
    STA.l DAS7L
    LDA.l !BattleRom_GfxStepVramB
    STA.l VMADDL
    TDC
    SEP #$20
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
.done:
    RTL

; ============================================================
; Per-frame update ($CF:E58A–$CF:E839)
; ============================================================

; $CF:E58A — BattleCF_FrameUpdate (503 bytes, $E58A–$E780)
; The battle's once-a-frame work behind the vector $C1:000C. In order:
;   - every 12 frames (!Battle_UnkA112 counts down from
;     !Battle_BlinkFrames) toggles bit 0 of !BattleUI_UnkA110 (a blink
;     phase, probably; its readers are elsewhere);
;   - when !Battle_UnkA113 is set, battler slot 9 takes slot 3's
;     !Battler_Palette (an enemy drawn as two parts, probably: the shake
;     mover copies slot 3's offsets to slot 9 under the same flag);
;   - BattleCF_StepFxColourCycle;
;   - steps !Battle_CursorGlowStep (0-$3D) and writes entry n of
;     !BattleRom_CursorGlow to colour 14 of OBJ palette 1 ($233C) when
;     !BattleMenu_CursorPalette bit 3 is clear, else of OBJ palette 5
;     ($23BC); !Battle_UnkA101 non-zero swaps the two (the cursor's
;     colour pulsing, probably);
;   - counts the 32-bit !Battle_FrameCounter up;
;   - the colour rotation ($CF:E600 on): when !Battle_UnkAB4E is set,
;     every !Battle_PalCycleDelay frames turns colours 1-12 of OBJ palette
;     4 (!Battle_PaletteLive+$80, the !Battle_SpecialPalette unit) by one
;     place (colour 12 to 1); with !Battle_PalCycleLo also the background
;     colours: the row of colour !Battle_Unk99D3 from that colour to 15,
;     then colours 1-15 of every later row up to colour 127;
;   - puts !BattleMenu_CursorPalette into the palette bits of OAM sprites
;     0-3 (the cursors);
;   - in the demo battle (!Battle_Unk2989 bit 5): once a button has been
;     pressed (!Battle_DemoKeyHit) counts !Battle_DemoQuitTimer down and
;     at 0 sets !Battle_UnkBB80 to $80 and restarts the game (JML Reset);
;   - while no action runs: holding L and R counts !Battle_Unk99CF up
;     and from 120 frames on bumps !Battle_Unk99CD (unless !Battle_Unk2989
;     bit 7); releasing them clears !Battle_Unk99CF/99D0/99D1;
;   - counts !Battle_FrameCount8 up and every fourth frame bumps
;     !BattleMenu_Dirty;
;   - BattleCF_RunMovers; while an action runs also
;     BattleCF_StepPathWalks, BattleCF_FollowObjects,
;     BattleCF_RecordPosHistory and BattleCF_BounceHitNumbers;
;     BattleCF_PlaceEnemyParts when !Battle_EnemyPartsOn is set;
;   - unless !Battle_UnkA028 is set: brings !Battle_ActFrameHold from 2
;     down to 1 while an action runs (BattleCF_VblankUploads sends the
;     frame at 1) and rebuilds the sprites (BattleCF_BuildSprites);
;   - clears !Battle_FramePending, which BattleSys_PumpFrames and
;     BattleCF_WaitFrame wait on.
; DP $A1 (!Battle_ArgSlot) is saved and restored around it all, because
; BattleCF_DrawActObj uses it.
; Quirk: the loop over the later background rows tests its end after the
; first pass, so with !Battle_Unk99D3 in the last row (colours 112-127)
; it still turns colours 1-15 of row 8 (OBJ palette 0, the start of
; !Battle_PaletteLive). And with !Battle_Unk99D3 at colour 15 of a row
; the first row's move count is 0: one move runs before the 16-bit DEC,
; which then wraps it, so the loop makes 65536 moves (not guarded).
; Callers (1 JML site): BankC1_JmlCFE58A ($C1:007A).
; Entry: M=1, X=0, DP=0, DB=$7E; A's high byte is used as is by the first
;        pass of BattleCF_StepFxColourCycle (see there), and again by the
;        glow index (ASL/TAX at $CF:E5B8) when neither that routine reached
;        its TDC (no PC slot with !Battler_FxCycleOn set while
;        !Battle_UnkA101 is clear) nor !Battle_CursorGlowStep wrapped to 0
;        (the TDC here); the caller's value is not traced
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $00-$06 and
;        $C6-$D1 (here and in the callees) and $7E:1D2E-$1DCE
;        (BattleCF_BuildSprites' direct page) written; !Battle_ArgSlot as
;        on entry
; Callers note: reached only by the JML at $C1:007A (BankC1_JmlCFE58A),
;   which the vector BankC1_VecCFE58A ($C1:000C) jumps to; that vector is
;   JSL'd from $CD:0997 and $EF:523C (unmatched).
; Callees: BattleCF_StepFxColourCycle, BattleCF_RunMovers,
;          BattleCF_StepPathWalks, BattleCF_FollowObjects,
;          BattleCF_RecordPosHistory, BattleCF_BounceHitNumbers,
;          BattleCF_PlaceEnemyParts, BattleCF_BuildSprites; Reset (JML)
org $CFE58A
BattleCF_FrameUpdate:
    DEC.w !Battle_UnkA112
    BNE .blink_done
    LDA.b #!Battle_BlinkFrames
    STA.w !Battle_UnkA112
    LDA.w !BattleUI_UnkA110
    EOR.b #$01
    STA.w !BattleUI_UnkA110
.blink_done:
    LDA.w !Battle_UnkA113
    BEQ .no_mirror
    LDA.w !Battler_Palette+!Battle_PartMainSlot
    STA.w !Battler_Palette+!Battle_PartMirrorSlot
.no_mirror:
    JSR BattleCF_StepFxColourCycle
    INC.w !Battle_CursorGlowStep
    LDA.w !Battle_CursorGlowStep
    CMP.b #!Battle_CursorGlowSteps
    BNE .glow_step
    TDC
    STA.w !Battle_CursorGlowStep
.glow_step:
    ASL A
    TAX                                 ; X = step * 2
    LDA.w !Battle_UnkA101
    BEQ .glow_plain
    LDA.w !BattleMenu_CursorPalette
    EOR.b #!Battle_CursorPalBit
    BRA .glow_pick
.glow_plain:
    LDA.w !BattleMenu_CursorPalette
.glow_pick:
    AND.b #!Battle_CursorPalBit
    BNE .glow_pal5
    LDA.l !BattleRom_CursorGlow,X
    STA.w !Battle_GlowColourA
    LDA.l !BattleRom_CursorGlow+1,X
    STA.w !Battle_GlowColourA+1
    BRA .count_frame
.glow_pal5:
    LDA.l !BattleRom_CursorGlow,X
    STA.w !Battle_GlowColourB
    LDA.l !BattleRom_CursorGlow+1,X
    STA.w !Battle_GlowColourB+1
.count_frame:
    REP #$21                            ; A 16-bit, C=0
    LDA.w !Battle_FrameCounter
    ADC.w #$0001
    STA.w !Battle_FrameCounter
    LDA.w !Battle_FrameCounter+2
    ADC.w #$0000
    STA.w !Battle_FrameCounter+2
    TDC
    SEP #$20
    ; the colour rotation (the "$CF:E600" of the opcode $6B notes)
    LDA.w !Battle_UnkAB4E
    BNE .rot_on
    JMP .cursor_attr
.rot_on:
    DEC.w !Battle_PalCycleTimer
    BEQ .rot_due
    JMP .cursor_attr
.rot_due:
    LDA.w !Battle_PalCycleDelay
    STA.w !Battle_PalCycleTimer
    LDX.w #!Battle_RotObjLastOfs        ; colour 11, the last one moved up
    REP #$20
    LDA.w !Battle_RotObjLast
    STA.b !BattleCF_TmpC6
.rot_obj:
    LDA.w !Battle_RotObjFirst-2,X
    STA.w !Battle_RotObjFirst,X
    DEX
    DEX
    BPL .rot_obj
    LDA.b !BattleCF_TmpC6
    STA.w !Battle_RotObjFirst           ; colour 12 wraps round to colour 1
    TDC
    SEP #$20
    LDA.w !Battle_PalCycleLo
    BEQ .cursor_attr
    LDA.w !Battle_Unk99D3
    AND.b #!Battle_ColourInRow
    STA.b !BattleCF_TmpC6
    SEC
    LDA.b #!Battle_ColourInRow
    SBC.b !BattleCF_TmpC6
    TAX
    STX.b !BattleCF_TmpC8                ; moves: 15 - first colour
    LDA.w !Battle_Unk99D3
    ORA.b #!Battle_ColourInRow
    REP #$20
    ASL A
    TAX
    STX.b !BattleCF_TmpCA                ; offset of colour 15 of that row
    LDA.w !Battle_PaletteLiveLo,X
    STA.b !BattleCF_TmpC6
    DEX
    DEX
.rot_first_row:
    LDA.w !Battle_PaletteLiveLo,X
    STA.w !Battle_PaletteLiveLo+2,X
    DEX
    DEX
    DEC.b !BattleCF_TmpC8
    BNE .rot_first_row
    LDA.b !BattleCF_TmpC6
    STA.w !Battle_PaletteLiveLo+2,X
    TDC
    SEP #$20
    LDA.w !Battle_Unk99D3
    ORA.b #!Battle_ColourInRow
    CLC
    ADC.b #!Battle_ColoursPerRow
    REP #$20
    ASL A
    STA.b !BattleCF_TmpCA                ; colour 15 of the next row
.rot_row:
    LDA.w #!Battle_ColourInRow-1
    STA.b !BattleCF_TmpC8                ; 14 moves: colours 1-15 turn
    LDX.b !BattleCF_TmpCA
    LDA.w !Battle_PaletteLiveLo,X
    STA.b !BattleCF_TmpC6
    DEX
    DEX
.rot_row_loop:
    LDA.w !Battle_PaletteLiveLo,X
    STA.w !Battle_PaletteLiveLo+2,X
    DEX
    DEX
    DEC.b !BattleCF_TmpC8
    BNE .rot_row_loop
    LDA.b !BattleCF_TmpC6
    STA.w !Battle_PaletteLiveLo+2,X
    CLC
    LDA.b !BattleCF_TmpCA
    ADC.w #!Battle_RowBytes
    STA.b !BattleCF_TmpCA
    AND.w #!Battle_HighByteMask         ; on to offset $100: the first 128 colours
    BEQ .rot_row
    TDC
    SEP #$20
.cursor_attr:
    LDA.w BattleOam.Attr
    AND.b #!BattleOam_AttrKeepMask
    ORA.w !BattleMenu_CursorPalette
    STA.w BattleOam.Attr
    LDA.w BattleOam[1].Attr
    AND.b #!BattleOam_AttrKeepMask
    ORA.w !BattleMenu_CursorPalette
    STA.w BattleOam[1].Attr
    LDA.w BattleOam[2].Attr
    AND.b #!BattleOam_AttrKeepMask
    ORA.w !BattleMenu_CursorPalette
    STA.w BattleOam[2].Attr
    LDA.w BattleOam[3].Attr
    AND.b #!BattleOam_AttrKeepMask
    ORA.w !BattleMenu_CursorPalette
    STA.w BattleOam[3].Attr
    LDA.b !Battle_ArgSlot
    PHA
    LDA.w !Battle_Unk2989
    AND.b #!Battle_2989Bit5
    BEQ .not_demo
    LDA.l JOY1L
    ORA.l JOY1H
    BEQ .demo_count
    LDA.b #$01
    STA.w !Battle_DemoKeyHit
.demo_count:
    LDA.w !Battle_DemoKeyHit
    BEQ .not_demo
    LDA.w !Battle_DemoQuitTimer
    DEC A
    STA.w !Battle_DemoQuitTimer
    BNE .not_demo
    LDA.b #!Battle_DemoQuitFlag
    STA.w !Battle_UnkBB80
    JML Reset
.not_demo:
    LDA.w !Battle_ActRunning
    BNE .lr_done
    LDA.l JOY1L
    AND.b #!Battle_PadLR
    CMP.b #!Battle_PadLR
    BNE .lr_released
    REP #$20
    INC.w !Battle_Unk99CF
    LDA.w !Battle_Unk99CF
    CMP.w #!Battle_LrHoldFrames
    BCC .lr_held
    LDA.w !Battle_Unk2989
    AND.w #!Battle_2989Bit7
    BNE .lr_held
    INC.w !Battle_Unk99CD
.lr_held:
    TDC
    SEP #$20
    BRA .lr_done
.lr_released:
    STZ.w !Battle_Unk99D1
    STZ.w !Battle_Unk99CF
    STZ.w !Battle_Unk99D0
.lr_done:
    INC.w !Battle_FrameCount8
    LDA.w !Battle_FrameCount8
    AND.b #$03
    BNE .run_movers
    INC.w !BattleMenu_Dirty
.run_movers:
    JSR BattleCF_RunMovers
    LDA.w !Battle_ActRunning
    BEQ .no_action
    JSR BattleCF_StepPathWalks
    JSR BattleCF_FollowObjects
    JSR BattleCF_RecordPosHistory
    JSR BattleCF_BounceHitNumbers
.no_action:
    LDA.w !Battle_EnemyPartsOn
    BEQ .parts_done
    JSR BattleCF_PlaceEnemyParts
.parts_done:
    LDA.w !Battle_UnkA028
    BNE .frame_done
    LDA.w !Battle_ActRunning
    BEQ .build
    LDA.w !Battle_ActFrameHold
    CMP.b #$02
    BNE .build
    DEC.w !Battle_ActFrameHold
.build:
    JSR BattleCF_BuildSprites
.frame_done:
    STZ.b !Battle_FramePending
    PLA
    STA.b !Battle_ArgSlot
    RTL

; $CF:E781 — BattleCF_BounceHitNumbers (86 bytes, $E781–$E7D6)
; Bounces the hit numbers BattleAct_OpShowHitNumbers built: while
; !Battle_HitNumActive is set, takes step !Battle_HitNumStep of the bounce
; table for each battler slot (!BattleRom_HitNumBounceAlt for slots with
; !Battler_HitNumAltBounce, else !BattleRom_HitNumBounce) into
; !Battler_HitNumDelta, counts the step on and adds each slot's delta to
; the y of its four Battle_HitNumSprite records. When
; !BattleRom_HitNumBounce holds !Battle_HitNumBounceEnd at the step, it
; clears !Battle_HitNumActive instead (the opcodes wait for that). The
; deltas are added to every slot's sprites, shown or not.
; Callers (1 JSR site): BattleCF_FrameUpdate ($CF:E759).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A, X, Y clobbered; DP $C6 written
; No calls.
org $CFE781
BattleCF_BounceHitNumbers:
    LDA.w !Battle_HitNumActive
    BEQ .done
    LDA.w !Battle_HitNumStep
    TAX
    LDA.l !BattleRom_HitNumBounce,X
    CMP.b #!Battle_HitNumBounceEnd
    BEQ .end
    TDC
    TAY
.pick:
    LDA.w !Battler_HitNumAltBounce,Y
    BNE .pick_alt
    LDA.l !BattleRom_HitNumBounce,X
    STA.w !Battler_HitNumDelta,Y
    BRA .picked
.pick_alt:
    LDA.l !BattleRom_HitNumBounceAlt,X
    STA.w !Battler_HitNumDelta,Y
.picked:
    INY
    CPY.w #!Battle_NumSlots
    BNE .pick
    INC.w !Battle_HitNumStep
    TDC
    TAX
    TAY
.slot:
    LDA.b #!Battle_HitNumSprites
    STA.b !BattleCF_TmpC6
.sprite:
    CLC
    LDA.w Battle_HitNumSprite.Y,X
    ADC.w !Battler_HitNumDelta,Y
    STA.w Battle_HitNumSprite.Y,X
    INX
    INX
    INX
    INX
    DEC.b !BattleCF_TmpC6
    BNE .sprite
    INY
    CPY.w #!Battle_NumSlots
    BNE .slot
    BRA .done
.end:
    STZ.w !Battle_HitNumActive
.done:
    RTS

; $CF:E7D7 — BattleCF_StepFxColourCycle (99 bytes, $E7D7–$E839)
; The status colour cycle (Battle_FxColourCycle turns it on): for PC
; slots 2, 1, 0 whose !Battler_FxCycleOn is set, unless !Battle_UnkA101
; is set or the PC uses !Battle_SpecialPalette, copies the colour at
; offset !Battler_FxCycleStep of the effect's list (!BattleRom_FxCycleList
; entry !Battler_FxWanted, an offset in !BattleRom_FxCycleColours) to bytes
; 2-3 and $18-$19 of the PC's !Battle_PaletteLive unit, then steps
; !Battler_FxCycleStep by 2, wrapping at !Battle_FxCycleBytes. A PC on the
; special palette is skipped before the copy, so its step does not move.
; The loop runs with 8-bit X and Y (SEP #$10) and switches to 16-bit for
; the copy.
; Quirk: the special-palette skip comes after REP #$10, so the next pass
; runs its LDY !BattleCF_TmpC6 with 16-bit Y; that reads $C7, which is 0
; (the STY at the start stored 16 bits), so nothing changes.
; Quirk: the first pass's ASL/TAX and 16-bit ADC use A's high byte as the
; caller left it (0 after this routine's own TDC on later passes); with
; BattleCF_FrameUpdate as the caller it is not traced.
; Callers (1 JSR site): BattleCF_FrameUpdate ($CF:E5A7).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0 (REP #$10 at the end); A, X, Y clobbered; DP $C6-$C7
;        written ($C6 ends at $FF)
; No calls.
org $CFE7D7
BattleCF_StepFxColourCycle:
    LDY.w #!Battle_LastPcSlot
    STY.b !BattleCF_TmpC6
    SEP #$10                            ; X, Y 8-bit
.slot:
    LDY.b !BattleCF_TmpC6
    LDA.w !Battler_FxCycleOn,Y
    BEQ .next
    LDA.w !Battle_UnkA101
    BNE .next
    REP #$10
    LDA.w !Battler_FxWanted,Y
    ASL A
    TAX
    CLC
    LDA.w !Battler_FxCycleStep,Y
    REP #$20
    ADC.l !BattleRom_FxCycleList,X
    TAX                                 ; X = colour offset in bank $CE
    TDC
    SEP #$20
    LDA.w !Battler_Palette,Y
    CMP.b #!Battle_SpecialPalette
    BEQ .next                           ; (with 16-bit X/Y: see the quirk)
    ASL A
    ASL A
    ASL A
    ASL A
    TAY                                 ; Y = palette unit * 16
    LDA.l !BattleRom_FxCycleColours,X
    STA.w !Battle_PaletteLive+2,Y
    STA.w !Battle_PaletteLive+!Battle_FxCycleSecondOfs,Y
    LDA.l !BattleRom_FxCycleColours+1,X
    STA.w !Battle_PaletteLive+3,Y
    STA.w !Battle_PaletteLive+!Battle_FxCycleSecondOfs+1,Y
    LDX.b !BattleCF_TmpC6
    INC.w !Battler_FxCycleStep,X
    INC.w !Battler_FxCycleStep,X
    LDA.w !Battler_FxCycleStep,X
    CMP.b #!Battle_FxCycleBytes
    BNE .stepped
    STZ.w !Battler_FxCycleStep,X
.stepped:
    SEP #$10
.next:
    DEC.b !BattleCF_TmpC6
    BPL .slot
    REP #$10
    RTS

; ============================================================
; Battle sprites ($CF:E83A–$CF:EFAE)
; ============================================================
; BattleCF_BuildSprites fills the OAM buffer (BattleOam, from sprite 4 on;
; sprites 0-3 are the cursors) once a frame. It runs with the direct page
; at !BattleSpr_Page ($1D00), whose bytes hold its list and counters; its
; callees switch back to D = 0 for the parts that use the bank-$CF scratch.
; A battler is handled by its sprite index, slot + !Battle_SprIdxBias
; (12-22), so that the per-slot arrays at $1D0C/$1D23 (!Battler_ScreenX/Y)
; read as $1D00/$1D17 + index; every per-slot array is read the same way
; (array - 12, indexed by the sprite index).

; $CF:E83A — BattleCF_BuildSprites (242 bytes, $E83A–$E92B)
; Builds the battle's sprites, front to back:
;   1. lists every present battler (!Battler_Present) with its sprite
;      index | !Battle_SprListBattler under the key !Battler_ScreenY, and
;      copies !Battler_UnkA5CD to !Battler_SprDrawState; a battler with
;      it non-zero gets state 1 and a second entry, its bare index under
;      the key !Battle_SprKeyTop;
;   2. sorts the list by key, largest first (a bubble sort that swaps keys
;      and entries together), and ends it with $FF;
;   3. walks it with the OAM offset !BattleSpr_OamOfs starting at $10
;      (sprite 4). For an entry whose battler's state is not negative and
;      whose !Battler_SprBytes is not 0: BattleCF_DrawFrontLayer, the
;      battler's tile words (BattleCF_CopySprTiles), its positions
;      (BattleCF_DrawBattler), BattleCF_DrawBackObjects, and a state of 1
;      becomes $80 and the entry branches past the next step; every other
;      entry (drawn with state 0, or skipped) gets
;      BattleCF_DrawUnkA5D8Sprite; and while an action runs, for every
;      entry with !Battle_SprListBattler whose battler has
;      !Battler_PosHistOn, BattleCF_DrawPosHistory.
; So a battler with !Battler_UnkA5CD set is drawn at its key-$FE entry,
; which sorts first: its sprites come first in OAM and show in front of
; the others (the lower OAM entry wins); its own entry is then skipped
; but still gets the marker and the position history. Lower on screen
; (larger y) sorts earlier, so it shows in front ("draw order" is
; inferred from the sort, the key and OAM priority).
; Quirk: with no battler listed, count - 1 is $FFFF; its low byte is not
; 0, so the sort would run over 65535 entries (not guarded; a battle
; always has battlers, probably).
; Callers (1 JSR site): BattleCF_FrameUpdate ($CF:E778).
; Entry: M=1, X=0, DP any (set here), DB=$7E
; Exit:  M=1, X=0, DP=0 (PLD of 0 at the end), DB=$7E; A, X, Y clobbered;
;        $7E:1D2E-$1DCE (this direct page), DP $C6-$D1 (D = 0) and
;        BattleOam from sprite 4 written; DP $A1 (!Battle_ArgSlot, D = 0)
;        overwritten by BattleCF_DrawActObj (through
;        BattleCF_DrawFrontLayer and BattleCF_DrawBackObjects);
;        !Battler_SprDrawState of a state-1 battler that was drawn
;        (!Battler_SprBytes not 0) left at $80, others as collected
; Callees: BattleCF_DrawFrontLayer, BattleCF_CopySprTiles,
;          BattleCF_DrawBattler, BattleCF_DrawBackObjects,
;          BattleCF_DrawUnkA5D8Sprite, BattleCF_DrawPosHistory
org $CFE83A
BattleCF_BuildSprites:
    LDX.w #!BattleSpr_Page
    PHX
    PLD                                 ; D = $1D00
    LDY.w #!Battle_SprIdxBias           ; sprite index of slot 0
    LDX.w #$0000                        ; list length
.collect:
    LDA.w !Battler_Present-!Battle_SprIdxBias,Y
    BEQ .collect_next
    LDA.w !BattleSpr_Y,Y
    STA.b !BattleSpr_Keys-!BattleSpr_Page,X
    TYA
    ORA.b #!Battle_SprListBattler
    STA.b !BattleSpr_List-!BattleSpr_Page,X
    INX
    LDA.w !Battler_UnkA5CD-!Battle_SprIdxBias,Y
    STA.w !BattleSpr_DrawState,Y
    BEQ .collect_next
    LDA.b #$01
    STA.w !BattleSpr_DrawState,Y
    LDA.b #!Battle_SprKeyTop
    STA.b !BattleSpr_Keys-!BattleSpr_Page,X
    TYA
    STA.b !BattleSpr_List-!BattleSpr_Page,X
    INX
.collect_next:
    INY
    CPY.w #!Battle_SprIdxEnd
    BNE .collect
    DEX
    STX.b !BattleSpr_LastEntry-!BattleSpr_Page
    LDY.w #$0000
    LDA.b !BattleSpr_LastEntry-!BattleSpr_Page
    BEQ .terminate                      ; one entry: nothing to sort
.sort_outer:
    TYX
.sort_inner:
    LDA.w !BattleSpr_Keys,Y
    CMP.b !BattleSpr_Keys+1-!BattleSpr_Page,X
    BCS .sort_keep
    PHA
    LDA.b !BattleSpr_Keys+1-!BattleSpr_Page,X
    STA.w !BattleSpr_Keys,Y
    PLA
    STA.b !BattleSpr_Keys+1-!BattleSpr_Page,X
    LDA.w !BattleSpr_List,Y
    PHA
    LDA.b !BattleSpr_List+1-!BattleSpr_Page,X
    STA.w !BattleSpr_List,Y
    PLA
    STA.b !BattleSpr_List+1-!BattleSpr_Page,X
.sort_keep:
    INX
    CPX.b !BattleSpr_LastEntry-!BattleSpr_Page
    BNE .sort_inner
    INY
    CPY.b !BattleSpr_LastEntry-!BattleSpr_Page
    BNE .sort_outer
.terminate:
    LDA.b #!Battle_SprListEnd
    STA.w !BattleSpr_List+1,Y           ; after the last entry
    LDY.w #$0000
    STY.b !BattleSpr_Index-!BattleSpr_Page
    STY.b !BattleSpr_ByteCount-!BattleSpr_Page
    STY.b !BattleSpr_Pos-!BattleSpr_Page
    LDY.w #!Battle_SprFirstOamOfs
    STY.b !BattleSpr_OamOfs-!BattleSpr_Page
.entry:
    LDX.b !BattleSpr_Pos-!BattleSpr_Page
    LDA.b !BattleSpr_List-!BattleSpr_Page,X
    BPL .entry_live
    JMP .done
.entry_live:
    AND.b #!Battle_SprListIdxMask
    STA.b !BattleSpr_Index-!BattleSpr_Page
    TAX
    LDA.b !BattleSpr_DrawState-!BattleSpr_Page,X
    BPL .state_ok
    JMP .marker
.state_ok:
    LDX.b !BattleSpr_Index-!BattleSpr_Page
    LDA.b !BattleSpr_Bytes-!BattleSpr_Page,X
    BNE .draw
    JMP .marker
.draw:
    STA.b !BattleSpr_ByteCount-!BattleSpr_Page
    JSR BattleCF_DrawFrontLayer
    REP #$31                            ; A 16-bit, C=0
    LDA.b !BattleSpr_OamOfs-!BattleSpr_Page
    ADC.w #BattleOam.X
    TAY                                 ; Y = OAM entry address
    LDA.b !BattleSpr_Index-!BattleSpr_Page
    ASL A
    TAX
    LDA.l !BattleRom_SprTileListPtr,X
    TAX                                 ; X = the battler's tile-word list
    LDA.b !BattleSpr_ByteCount-!BattleSpr_Page
    INC A
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !BattleSpr_Groups-!BattleSpr_Page ; groups of four sprites
    JSR BattleCF_CopySprTiles
    JSR BattleCF_DrawBattler
    JSR BattleCF_DrawBackObjects
    LDX.b !BattleSpr_Index-!BattleSpr_Page
    LDA.b !BattleSpr_DrawState-!BattleSpr_Page,X
    BEQ .marker
    LDA.b #!Battle_SprDrawn
    STA.b !BattleSpr_DrawState-!BattleSpr_Page,X
    BRA .history
.marker:
    JSR BattleCF_DrawUnkA5D8Sprite
.history:
    LDA.w !Battle_ActRunning
    BEQ .entry_next
    LDX.b !BattleSpr_Pos-!BattleSpr_Page
    LDA.b !BattleSpr_List-!BattleSpr_Page,X
    BIT.b #!Battle_SprListBattler
    BEQ .entry_next
    AND.b #!Battle_SprListIdxMask
    TAX
    LDA.w !Battler_PosHistOn-!Battle_SprIdxBias,X
    BEQ .entry_next
    JSR BattleCF_DrawPosHistory
.entry_next:
    INC.b !BattleSpr_Pos-!BattleSpr_Page
    JMP .entry
.done:
    LDX.w #$0000
    PHX
    PLD
    RTS

; $CF:E92C — BattleCF_DrawPosHistory (112 bytes, $E92C–$E99B)
; Draws the four position-history records BattleCF_RecordPosHistory keeps
; for the battler at sprite index X: every !Battler_PosHistUnkAB7D frames
; (!Battler_PosHistUnkAB88 counts them down) it draws record 0, 1, 2 and 3
; as copies of the battler (BattleCF_DrawPosHistRecord); on the frames
; between it draws none, so the copies flicker (after-images, probably,
; as the opcode $A4/$A5 notes guess).
; Callers (1 JSR site): BattleCF_BuildSprites ($CF:E91E).
; Quirk: BattleCF_BuildSprites sets !BattleSpr_ByteCount only for an
; entry it draws. For an entry it skipped (state $80, as a battler's own
; entry after its key-$FE entry was drawn, or !Battler_SprBytes 0) the
; count is still the last drawn battler's (0 if none yet), and
; BattleCF_DrawPosHistRecord takes the group count it gives
; BattleCF_CopySprTiles from it: the copies get that battler's count.
; Entry: M=1, X=0, DP=$1D00 (!BattleSpr_Page), DB=$7E; X = sprite index
;        (slot + 12); !BattleSpr_Index the battler's; !BattleSpr_ByteCount
;        the battler's only when this entry was drawn (see the quirk)
; Exit:  M=1, X=0, DP=$1D00, DB=$7E; A, X, Y clobbered; !BattleSpr_OamOfs
;        moved past the sprites drawn; $7E:1DCB-$1DCC (!BattleSpr_SavedIdx)
;        written, and on a drawing frame $7E:1D2E-$1D43 and $1DCD-$1DCE
;        (!BattleSpr_Groups) by BattleCF_DrawPosHistRecord
; Callees: BattleCF_DrawPosHistRecord
org $CFE92C
BattleCF_DrawPosHistory:
    STX.b !BattleSpr_SavedIdx-!BattleSpr_Page
    DEC.w !Battler_PosHistUnkAB88-!Battle_SprIdxBias,X
    BNE .done
    LDA.w !Battler_PosHistUnkAB7D-!Battle_SprIdxBias,X
    STA.w !Battler_PosHistUnkAB88-!Battle_SprIdxBias,X
    LDA.w !Battler_PosHistX-!Battle_SprIdxBias,X
    STA.b !BattleSpr_HistX-!BattleSpr_Page
    LDA.w !Battler_PosHistY-!Battle_SprIdxBias,X
    STA.b !BattleSpr_HistY-!BattleSpr_Page
    LDA.w !Battler_PosHistXHi-!Battle_SprIdxBias,X
    STA.b !BattleSpr_HistXHi-!BattleSpr_Page
    LDA.w !Battler_PosHistYHi-!Battle_SprIdxBias,X
    STA.b !BattleSpr_HistYHi-!BattleSpr_Page
    JSR BattleCF_DrawPosHistRecord
    LDX.b !BattleSpr_SavedIdx-!BattleSpr_Page
    LDA.w !Battler_PosHistX+(1*!Battle_PosHistRecBytes)-!Battle_SprIdxBias,X
    STA.b !BattleSpr_HistX-!BattleSpr_Page
    LDA.w !Battler_PosHistY+(1*!Battle_PosHistRecBytes)-!Battle_SprIdxBias,X
    STA.b !BattleSpr_HistY-!BattleSpr_Page
    LDA.w !Battler_PosHistXHi+(1*!Battle_PosHistRecBytes)-!Battle_SprIdxBias,X
    STA.b !BattleSpr_HistXHi-!BattleSpr_Page
    LDA.w !Battler_PosHistYHi+(1*!Battle_PosHistRecBytes)-!Battle_SprIdxBias,X
    STA.b !BattleSpr_HistYHi-!BattleSpr_Page
    JSR BattleCF_DrawPosHistRecord
    LDX.b !BattleSpr_SavedIdx-!BattleSpr_Page
    LDA.w !Battler_PosHistX+(2*!Battle_PosHistRecBytes)-!Battle_SprIdxBias,X
    STA.b !BattleSpr_HistX-!BattleSpr_Page
    LDA.w !Battler_PosHistY+(2*!Battle_PosHistRecBytes)-!Battle_SprIdxBias,X
    STA.b !BattleSpr_HistY-!BattleSpr_Page
    LDA.w !Battler_PosHistXHi+(2*!Battle_PosHistRecBytes)-!Battle_SprIdxBias,X
    STA.b !BattleSpr_HistXHi-!BattleSpr_Page
    LDA.w !Battler_PosHistYHi+(2*!Battle_PosHistRecBytes)-!Battle_SprIdxBias,X
    STA.b !BattleSpr_HistYHi-!BattleSpr_Page
    JSR BattleCF_DrawPosHistRecord
    LDX.b !BattleSpr_SavedIdx-!BattleSpr_Page
    LDA.w !Battler_PosHistX+(3*!Battle_PosHistRecBytes)-!Battle_SprIdxBias,X
    STA.b !BattleSpr_HistX-!BattleSpr_Page
    LDA.w !Battler_PosHistY+(3*!Battle_PosHistRecBytes)-!Battle_SprIdxBias,X
    STA.b !BattleSpr_HistY-!BattleSpr_Page
    LDA.w !Battler_PosHistXHi+(3*!Battle_PosHistRecBytes)-!Battle_SprIdxBias,X
    STA.b !BattleSpr_HistXHi-!BattleSpr_Page
    LDA.w !Battler_PosHistYHi+(3*!Battle_PosHistRecBytes)-!Battle_SprIdxBias,X
    STA.b !BattleSpr_HistYHi-!BattleSpr_Page
    JSR BattleCF_DrawPosHistRecord
.done:
    RTS

; $CF:E99C — BattleCF_DrawPosHistRecord (238 bytes, $E99C–$EA89)
; Draws one copy of the battler !BattleSpr_Index at the history position
; in !BattleSpr_HistX/Y (low bytes) and !BattleSpr_HistXHi/YHi (only
; their sign is used: negative = the high byte is $FF): its tile words
; (BattleCF_CopySprTiles), then each sprite at that position plus the
; battler's !Battler_FrameExtra offsets, as BattleCF_DrawBattler does
; (see there for the attribute and when x bit 8 is set). A battler whose
; !Battler_Unk9FF7 is non-zero gets the tile words but no positions.
; The display offsets (!Battler_UnkA4A4/A4AF) are not added: they were
; already added when the record was taken.
; Callers (4 JSR sites): BattleCF_DrawPosHistory ($CF:E94D, $CF:E966, $CF:E97F, $CF:E998).
; Entry: M=1, X=0, DP=$1D00, DB=$7E; !BattleSpr_Index, !BattleSpr_ByteCount
;        and !BattleSpr_OamOfs set
; Exit:  M=1, X=0, DP=$1D00, DB=$7E; A, X, Y clobbered; !BattleSpr_OamOfs
;        moved past the sprites drawn (not moved when !Battler_Unk9FF7 is
;        set); $7E:1D2E-$1D43 and $1DCD-$1DCE (!BattleSpr_Groups) written
; Callees: BattleCF_CopySprTiles
org $CFE99C
BattleCF_DrawPosHistRecord:
    REP #$31                            ; A 16-bit, C=0
    LDA.b !BattleSpr_OamOfs-!BattleSpr_Page
    ADC.w #BattleOam.X
    TAY
    LDA.b !BattleSpr_Index-!BattleSpr_Page
    ASL A
    TAX
    LDA.l !BattleRom_SprTileListPtr,X
    TAX
    LDA.b !BattleSpr_ByteCount-!BattleSpr_Page
    INC A
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !BattleSpr_Groups-!BattleSpr_Page
    JSR BattleCF_CopySprTiles
    LDA.w #$0000
    SEP #$20
    LDA.b !BattleSpr_Index-!BattleSpr_Page
    TAX
    SEC
    SBC.b #!Battle_SprIdxBias
    ASL A
    ASL A
    ASL A
    ASL A
    TAY
    STY.b !BattleSpr_ExtraOfs-!BattleSpr_Page ; slot * 16: its !Battler_FrameExtra block
    LDA.w !Battler_Unk9FF7-!Battle_SprIdxBias,X
    BEQ .place
    RTS
.place:
    LDA.b !BattleSpr_HistX-!BattleSpr_Page
    STA.b !BattleSpr_BaseX-!BattleSpr_Page
    STZ.b !BattleSpr_BaseX+1-!BattleSpr_Page
    LDA.b #$00
    STA.b !BattleSpr_OfsX-!BattleSpr_Page
    LDA.b !BattleSpr_HistXHi-!BattleSpr_Page
    BMI .x_neg
    LDA.b #$00
    BRA .x_hi
.x_neg:
    LDA.b #!Battle_SignFill
.x_hi:
    STA.b !BattleSpr_OfsX+1-!BattleSpr_Page ; $0000 or $FF00
    LDA.b !BattleSpr_HistY-!BattleSpr_Page
    STA.b !BattleSpr_BaseY-!BattleSpr_Page
    STZ.b !BattleSpr_BaseY+1-!BattleSpr_Page
    LDA.b #$00
    STA.b !BattleSpr_OfsY-!BattleSpr_Page
    LDA.b !BattleSpr_HistYHi-!BattleSpr_Page
    BMI .y_neg
    LDA.b #$00
    BRA .y_hi
.y_neg:
    LDA.b #!Battle_SignFill
.y_hi:
    STA.b !BattleSpr_OfsY+1-!BattleSpr_Page
    REP #$21
    LDA.b !BattleSpr_BaseX-!BattleSpr_Page
    ADC.b !BattleSpr_OfsX-!BattleSpr_Page
    STA.b !BattleSpr_BaseX-!BattleSpr_Page
    CLC
    LDA.b !BattleSpr_BaseY-!BattleSpr_Page
    ADC.b !BattleSpr_OfsY-!BattleSpr_Page
    STA.b !BattleSpr_BaseY-!BattleSpr_Page
    LDA.w #$0000
    SEP #$20
    LDA.w !Battler_Palette-!Battle_SprIdxBias,X
    ORA.w !Battler_ActAttr-!Battle_SprIdxBias,X
    STA.b !BattleSpr_AttrWord+1-!BattleSpr_Page
    STZ.b !BattleSpr_AttrWord-!BattleSpr_Page
    LDA.w !Battler_FrameLayout-!Battle_SprIdxBias,X
    ASL A
    TAX
    LDA.l !BattleRom_LayoutSprites,X
    TAX
    STX.b !BattleSpr_SprCount-!BattleSpr_Page
.sprite:
    LDY.b !BattleSpr_ExtraOfs-!BattleSpr_Page
    LDX.b !BattleSpr_OamOfs-!BattleSpr_Page
    REP #$21
    LDA.w !Battler_FrameExtra,Y
    ADC.b !BattleSpr_BaseX-!BattleSpr_Page
    STA.b !BattleSpr_SprX-!BattleSpr_Page
    CLC
    LDA.w !Battler_FrameExtra+2,Y
    ADC.b !BattleSpr_BaseY-!BattleSpr_Page
    STA.b !BattleSpr_SprY-!BattleSpr_Page
    LDA.w BattleOam.Tile,X
    AND.w #!Battle_OamKeepTileFlip
    ORA.b !BattleSpr_AttrWord-!BattleSpr_Page
    STA.w BattleOam.Tile,X
    LDA.w #$0000
    SEP #$20
    LDA.b !BattleSpr_SprX-!BattleSpr_Page
    STA.w BattleOam.X,X
    LDA.b !BattleSpr_SprY-!BattleSpr_Page
    STA.w BattleOam.Y,X
    LDA.b !BattleSpr_SprY+1-!BattleSpr_Page
    BEQ .y_on
    LDA.b !BattleSpr_SprY-!BattleSpr_Page
    CMP.b #!Battle_SprHideY
    BCC .hide
    BRA .next
.y_on:
    LDA.b !BattleSpr_SprX+1-!BattleSpr_Page
    BEQ .next
.hide:
    LDA.w !Battle_OamHighIdx,X
    TAX
    LDY.b !BattleSpr_OamOfs-!BattleSpr_Page
    LDA.w !BattleOam_HighTable,X
    ORA.w !Battle_OamHighXBit,Y
    STA.w !BattleOam_HighTable,X
.next:
    LDX.b !BattleSpr_OamOfs-!BattleSpr_Page
    INX
    INX
    INX
    INX
    STX.b !BattleSpr_OamOfs-!BattleSpr_Page
    LDY.b !BattleSpr_ExtraOfs-!BattleSpr_Page
    INY
    INY
    INY
    INY
    STY.b !BattleSpr_ExtraOfs-!BattleSpr_Page
    DEC.b !BattleSpr_SprCount-!BattleSpr_Page
    BNE .sprite
    RTS

; $CF:EA8A — BattleCF_DrawUnkA5D8Sprite (59 bytes, $EA8A–$EAC4)
; For the battler at sprite index X whose !Battler_UnkA5D8 is non-zero
; (opcodes $D0/$D1 set and clear it) and whose !Battler_Unk9FF7 is 0:
; puts one sprite, tile !Battle_UnkA5D8Tile, at its screen position less
; (8, 4), with !Battle_ActAttrBits | !BattleMenu_CursorPalette as the
; attribute, and moves !BattleSpr_OamOfs on by $10 (four sprites; the
; other three are left as they were). What the sprite shows is not
; traced (a marker over the battler, probably).
; Callers (1 JSR site): BattleCF_BuildSprites ($CF:E906).
; Entry: M=1, X=0, DP=$1D00, DB=$7E; X = sprite index (slot + 12)
; Exit:  M=1, X=0, DP=$1D00, DB=$7E; X unchanged; A clobbered; Y =
;        !BattleSpr_OamOfs after the sprite (unchanged when nothing is
;        drawn)
; No calls.
org $CFEA8A
BattleCF_DrawUnkA5D8Sprite:
    LDA.w !Battler_UnkA5D8-!Battle_SprIdxBias,X
    BEQ .done
    LDA.w !Battler_Unk9FF7-!Battle_SprIdxBias,X
    BNE .done
    LDY.b !BattleSpr_OamOfs-!BattleSpr_Page
    SEC
    LDA.w !BattleSpr_X,X
    SBC.b #!Battle_UnkA5D8DX
    STA.w BattleOam.X,Y
    SEC
    LDA.w !BattleSpr_Y,X
    SBC.b #!Battle_UnkA5D8DY
    STA.w BattleOam.Y,Y
    LDA.b #!Battle_UnkA5D8Tile
    STA.w BattleOam.Tile,Y
    LDA.w !Battle_ActAttrBits
    ORA.w !BattleMenu_CursorPalette
    STA.w BattleOam.Attr,Y
    REP #$21
    TYA
    ADC.w #!Battle_SprGroupBytes
    TAY
    STY.b !BattleSpr_OamOfs-!BattleSpr_Page
    LDA.w #$0000
    SEP #$20
.done:
    RTS

; $CF:EAC5 — BattleCF_DrawBattler (207 bytes, $EAC5–$EB93)
; Places the sprites of the battler !BattleSpr_Index whose tile words
; BattleCF_CopySprTiles has just put in OAM: its position is
; !Battler_ScreenX/Y plus the signed display offsets !Battler_UnkA4A4/A4AF
; (what the circle, shake and arc movers write), as 16-bit values. For
; each of the layout's sprites (!BattleRom_LayoutSprites of its
; !Battler_FrameLayout) it adds the sprite's x and y words from the
; battler's !Battler_FrameExtra block (so those words are the sprites'
; offsets in the frame), writes x and y to OAM, puts !Battler_Palette |
; !Battler_ActAttr into the attribute's palette and priority bits
; (keeping the flips and the tile), and sets the sprite's x bit 8 in the
; high table (!Battle_OamHighIdx / !Battle_OamHighXBit, RAM tables built
; elsewhere) when y's high byte is not 0 and its low byte is below $F0,
; or when y's high byte is 0 and x's high byte is not 0; with y's high
; byte not 0 and its low byte $F0 or more, x is not tested. Only x's low
; byte goes to OAM, so with bit 8 set the sprite is at that low byte
; - 256: off the left edge unless the low byte is near 255 and the sprite
; reaches past it; for a negative x ($FFxx) that is its true place, so
; it shows partly at the left edge rather than being hidden. A battler
; whose !Battler_Unk9FF7 is non-zero gets no positions (nor any OAM step).
; Callers (1 JSR site): BattleCF_BuildSprites ($CF:E8F4).
; Entry: M=0 (16-bit A: the first LDA #$0000 is 3 bytes; BattleCF_CopySprTiles
;        returns so), X=0, DP=$1D00, DB=$7E; !BattleSpr_Index,
;        !BattleSpr_OamOfs set
; Exit:  M=1, X=0, DP=$1D00, DB=$7E; A, X, Y clobbered; !BattleSpr_OamOfs
;        moved past the sprites; $7E:1D2E-$1D43 written
; No calls.
org $CFEAC5
BattleCF_DrawBattler:
    LDA.w #$0000
    SEP #$20
    LDA.b !BattleSpr_Index-!BattleSpr_Page
    TAX
    SEC
    SBC.b #!Battle_SprIdxBias
    ASL A
    ASL A
    ASL A
    ASL A
    TAY
    STY.b !BattleSpr_ExtraOfs-!BattleSpr_Page
    LDA.w !Battler_Unk9FF7-!Battle_SprIdxBias,X
    BEQ .place
    RTS
.place:
    LDA.b !BattleSpr_X-!BattleSpr_Page,X
    STA.b !BattleSpr_BaseX-!BattleSpr_Page
    STZ.b !BattleSpr_BaseX+1-!BattleSpr_Page
    LDA.w !Battler_UnkA4A4-!Battle_SprIdxBias,X
    STA.b !BattleSpr_OfsX-!BattleSpr_Page
    BMI .x_neg
    LDA.b #$00
    BRA .x_hi
.x_neg:
    LDA.b #!Battle_SignFill
.x_hi:
    STA.b !BattleSpr_OfsX+1-!BattleSpr_Page
    LDA.b !BattleSpr_Y-!BattleSpr_Page,X
    STA.b !BattleSpr_BaseY-!BattleSpr_Page
    STZ.b !BattleSpr_BaseY+1-!BattleSpr_Page
    LDA.w !Battler_UnkA4AF-!Battle_SprIdxBias,X
    STA.b !BattleSpr_OfsY-!BattleSpr_Page
    BMI .y_neg
    LDA.b #$00
    BRA .y_hi
.y_neg:
    LDA.b #!Battle_SignFill
.y_hi:
    STA.b !BattleSpr_OfsY+1-!BattleSpr_Page
    REP #$21
    LDA.b !BattleSpr_BaseX-!BattleSpr_Page
    ADC.b !BattleSpr_OfsX-!BattleSpr_Page
    STA.b !BattleSpr_BaseX-!BattleSpr_Page
    CLC
    LDA.b !BattleSpr_BaseY-!BattleSpr_Page
    ADC.b !BattleSpr_OfsY-!BattleSpr_Page
    STA.b !BattleSpr_BaseY-!BattleSpr_Page
    LDA.w #$0000
    SEP #$20
    LDA.w !Battler_Palette-!Battle_SprIdxBias,X
    ORA.w !Battler_ActAttr-!Battle_SprIdxBias,X
    STA.b !BattleSpr_AttrWord+1-!BattleSpr_Page
    STZ.b !BattleSpr_AttrWord-!BattleSpr_Page
    LDA.w !Battler_FrameLayout-!Battle_SprIdxBias,X
    ASL A
    TAX
    LDA.l !BattleRom_LayoutSprites,X
    TAX
    STX.b !BattleSpr_SprCount-!BattleSpr_Page
.sprite:
    LDY.b !BattleSpr_ExtraOfs-!BattleSpr_Page
    LDX.b !BattleSpr_OamOfs-!BattleSpr_Page
    REP #$21
    LDA.w !Battler_FrameExtra,Y
    ADC.b !BattleSpr_BaseX-!BattleSpr_Page
    STA.b !BattleSpr_SprX-!BattleSpr_Page
    CLC
    LDA.w !Battler_FrameExtra+2,Y
    ADC.b !BattleSpr_BaseY-!BattleSpr_Page
    STA.b !BattleSpr_SprY-!BattleSpr_Page
    LDA.w BattleOam.Tile,X
    AND.w #!Battle_OamKeepTileFlip
    ORA.b !BattleSpr_AttrWord-!BattleSpr_Page
    STA.w BattleOam.Tile,X
    LDA.w #$0000
    SEP #$20
    LDA.b !BattleSpr_SprX-!BattleSpr_Page
    STA.w BattleOam.X,X
    LDA.b !BattleSpr_SprY-!BattleSpr_Page
    STA.w BattleOam.Y,X
    LDA.b !BattleSpr_SprY+1-!BattleSpr_Page
    BEQ .y_on
    LDA.b !BattleSpr_SprY-!BattleSpr_Page
    CMP.b #!Battle_SprHideY
    BCC .hide
    BRA .next
.y_on:
    LDA.b !BattleSpr_SprX+1-!BattleSpr_Page
    BEQ .next
.hide:
    LDA.w !Battle_OamHighIdx,X
    TAX
    LDY.b !BattleSpr_OamOfs-!BattleSpr_Page
    LDA.w !BattleOam_HighTable,X
    ORA.w !Battle_OamHighXBit,Y
    STA.w !BattleOam_HighTable,X
.next:
    LDX.b !BattleSpr_OamOfs-!BattleSpr_Page
    INX
    INX
    INX
    INX
    STX.b !BattleSpr_OamOfs-!BattleSpr_Page
    LDY.b !BattleSpr_ExtraOfs-!BattleSpr_Page
    INY
    INY
    INY
    INY
    STY.b !BattleSpr_ExtraOfs-!BattleSpr_Page
    DEC.b !BattleSpr_SprCount-!BattleSpr_Page
    BNE .sprite
    RTS

; $CF:EB94 — BattleCF_CopySprTiles (228 bytes, $EB94–$EC77)
; Copies the tile/attribute words (bytes 2-3 of each 4-byte sprite
; record) of four sprites per group from the list at X to the OAM entries
; at Y, !BattleSpr_Groups groups: it returns after a group when the
; (16-bit, as M=0) decrement of the count reaches 0, and after the eighth
; group in any case, so 1-8 groups (0 or more than 8 give 8). Written
; out in full, one block per group.
; Callers (2 JSR sites): BattleCF_BuildSprites ($CF:E8F1) and BattleCF_DrawPosHistRecord ($CF:E9B6).
; Entry: M=0 (16-bit A: a word per sprite), X=0, DP=$1D00 (the group
;        count), DB=$7E; X = source list address, Y = OAM entry address
; Exit:  M=0, X=0, DP=$1D00, DB=$7E; X, Y unchanged; A = the last word
;        copied; !BattleSpr_Groups = 0 after 1-7 groups, else the count
;        less 7
; No calls.
org $CFEB94
BattleCF_CopySprTiles:
    LDA.w BattleSprRec[0].Tile,X
    STA.w BattleSprRec[0].Tile,Y
    LDA.w BattleSprRec[1].Tile,X
    STA.w BattleSprRec[1].Tile,Y
    LDA.w BattleSprRec[2].Tile,X
    STA.w BattleSprRec[2].Tile,Y
    LDA.w BattleSprRec[3].Tile,X
    STA.w BattleSprRec[3].Tile,Y
    DEC.b !BattleSpr_Groups-!BattleSpr_Page
    BNE .group2
    RTS
.group2:
    LDA.w BattleSprRec[4].Tile,X
    STA.w BattleSprRec[4].Tile,Y
    LDA.w BattleSprRec[5].Tile,X
    STA.w BattleSprRec[5].Tile,Y
    LDA.w BattleSprRec[6].Tile,X
    STA.w BattleSprRec[6].Tile,Y
    LDA.w BattleSprRec[7].Tile,X
    STA.w BattleSprRec[7].Tile,Y
    DEC.b !BattleSpr_Groups-!BattleSpr_Page
    BNE .group3
    RTS
.group3:
    LDA.w BattleSprRec[8].Tile,X
    STA.w BattleSprRec[8].Tile,Y
    LDA.w BattleSprRec[9].Tile,X
    STA.w BattleSprRec[9].Tile,Y
    LDA.w BattleSprRec[10].Tile,X
    STA.w BattleSprRec[10].Tile,Y
    LDA.w BattleSprRec[11].Tile,X
    STA.w BattleSprRec[11].Tile,Y
    DEC.b !BattleSpr_Groups-!BattleSpr_Page
    BNE .group4
    RTS
.group4:
    LDA.w BattleSprRec[12].Tile,X
    STA.w BattleSprRec[12].Tile,Y
    LDA.w BattleSprRec[13].Tile,X
    STA.w BattleSprRec[13].Tile,Y
    LDA.w BattleSprRec[14].Tile,X
    STA.w BattleSprRec[14].Tile,Y
    LDA.w BattleSprRec[15].Tile,X
    STA.w BattleSprRec[15].Tile,Y
    DEC.b !BattleSpr_Groups-!BattleSpr_Page
    BNE .group5
    RTS
.group5:
    LDA.w BattleSprRec[16].Tile,X
    STA.w BattleSprRec[16].Tile,Y
    LDA.w BattleSprRec[17].Tile,X
    STA.w BattleSprRec[17].Tile,Y
    LDA.w BattleSprRec[18].Tile,X
    STA.w BattleSprRec[18].Tile,Y
    LDA.w BattleSprRec[19].Tile,X
    STA.w BattleSprRec[19].Tile,Y
    DEC.b !BattleSpr_Groups-!BattleSpr_Page
    BNE .group6
    RTS
.group6:
    LDA.w BattleSprRec[20].Tile,X
    STA.w BattleSprRec[20].Tile,Y
    LDA.w BattleSprRec[21].Tile,X
    STA.w BattleSprRec[21].Tile,Y
    LDA.w BattleSprRec[22].Tile,X
    STA.w BattleSprRec[22].Tile,Y
    LDA.w BattleSprRec[23].Tile,X
    STA.w BattleSprRec[23].Tile,Y
    DEC.b !BattleSpr_Groups-!BattleSpr_Page
    BNE .group7
    RTS
.group7:
    LDA.w BattleSprRec[24].Tile,X
    STA.w BattleSprRec[24].Tile,Y
    LDA.w BattleSprRec[25].Tile,X
    STA.w BattleSprRec[25].Tile,Y
    LDA.w BattleSprRec[26].Tile,X
    STA.w BattleSprRec[26].Tile,Y
    LDA.w BattleSprRec[27].Tile,X
    STA.w BattleSprRec[27].Tile,Y
    DEC.b !BattleSpr_Groups-!BattleSpr_Page
    BNE .group8
    RTS
.group8:
    LDA.w BattleSprRec[28].Tile,X
    STA.w BattleSprRec[28].Tile,Y
    LDA.w BattleSprRec[29].Tile,X
    STA.w BattleSprRec[29].Tile,Y
    LDA.w BattleSprRec[30].Tile,X
    STA.w BattleSprRec[30].Tile,Y
    LDA.w BattleSprRec[31].Tile,X
    STA.w BattleSprRec[31].Tile,Y
    RTS

; $CF:EC78 — BattleCF_StepPathWalks (74 bytes, $EC78–$ECC1)
; Steps the path walks BattleAct_PathToPoint starts: for each battler slot
; whose !Battler_PathWalking is set and whose step is not done
; (!Battler_PathStepFrame not negative), adds entry
; !Battler_PathStepKind * 8 + (7 - !Battler_PathStepFrame) of
; !BattleRom_PathStepDX / !BattleRom_PathStepDY to !Battler_ScreenX / Y
; and counts the frame down (to $FF when the step is done; the opcode
; then picks the next cell).
; Callers (1 JSR site): BattleCF_FrameUpdate ($CF:E750).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X clobbered; Y = !Battle_NumSlots;
;        DP $C6-$C7 written when a battler walks
; No calls.
org $CFEC78
BattleCF_StepPathWalks:
    TDC
    TAY
.slot:
    LDA.w !Battler_PathWalking,Y
    BEQ .next
    LDA.w !Battler_PathStepFrame,Y
    BMI .next
    SEC
    LDA.b #!Battle_PathStepFrames
    SBC.w !Battler_PathStepFrame,Y
    TAX
    STX.b !BattleCF_TmpC6               ; frame of the step, 0-7
    LDA.w !Battler_PathStepKind,Y
    REP #$20
    ASL A
    ASL A
    ASL A
    CLC
    ADC.b !BattleCF_TmpC6
    TAX                                 ; X = kind * 8 + frame
    TDC
    SEP #$20
    CLC
    LDA.l !BattleRom_PathStepDX,X
    ADC.w !Battler_ScreenX,Y
    STA.w !Battler_ScreenX,Y
    CLC
    LDA.l !BattleRom_PathStepDY,X
    ADC.w !Battler_ScreenY,Y
    STA.w !Battler_ScreenY,Y
    SEC
    LDA.w !Battler_PathStepFrame,Y
    SBC.b #$01
    STA.w !Battler_PathStepFrame,Y
.next:
    INY
    CPY.w #!Battle_NumSlots
    BNE .slot
    RTS

; $CF:ECC2 — BattleCF_FollowObjects (86 bytes, $ECC2–$ED17)
; Moves the action objects that follow something (!Battle_ActObjFollow,
; set by the action opcodes): for object threads 7 down to 0, a value with
; bit 7 clear and !Battle_ActFollowObj clear is a battler slot, and the
; object's !Battle_ActObjX/Y become that battler's !Battler_ScreenX/Y
; (high bytes 0); with !Battle_ActFollowObj set, bits 0-2 name another
; object thread, whose x and y words are copied. Negative = follows
; nothing. Threads are done from 7 down, so a thread following a lower
; one takes that one's position from before (not yet updated this
; frame), one following a higher one its position of this frame.
; Runs with 8-bit X and Y.
; Callers (1 JSR site): BattleCF_FrameUpdate ($CF:E753).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0 (REP #$10 at the end); A clobbered (its high byte as
;        on entry); X, Y clobbered (high bytes 0); DP $C6 = $FF, $C7 = 0
; No calls.
org $CFECC2
BattleCF_FollowObjects:
    LDX.w #!Battle_LastObjThread
    STX.b !BattleCF_TmpC6
    SEP #$10                            ; X, Y 8-bit
.thread:
    LDX.b !BattleCF_TmpC6
    LDA.w !Battle_ActObjFollow,X
    BMI .next
    AND.b #!Battle_ActFollowObj
    BNE .follow_obj
    LDA.w !Battle_ActObjFollow,X
    TAY                                 ; Y = battler slot
    TXA
    ASL A
    TAX                                 ; X = thread * 2
    LDA.w !Battler_ScreenX,Y
    STA.w !Battle_ActObjX,X
    STZ.w !Battle_ActObjX+1,X
    LDA.w !Battler_ScreenY,Y
    STA.w !Battle_ActObjY,X
    STZ.w !Battle_ActObjY+1,X
    BRA .next
.follow_obj:
    LDA.w !Battle_ActObjFollow,X
    AND.b #!Battle_ObjThreadMask
    ASL A
    TAY                                 ; Y = followed thread * 2
    TXA
    ASL A
    TAX
    LDA.w !Battle_ActObjX,Y
    STA.w !Battle_ActObjX,X
    LDA.w !Battle_ActObjX+1,Y
    STA.w !Battle_ActObjX+1,X
    LDA.w !Battle_ActObjY,Y
    STA.w !Battle_ActObjY,X
    LDA.w !Battle_ActObjY+1,Y
    STA.w !Battle_ActObjY+1,X
.next:
    DEC.b !BattleCF_TmpC6
    BPL .thread
    REP #$10
    RTS

; $CF:ED18 — BattleCF_RecordPosHistory (160 bytes, $ED18–$EDB7)
; Keeps the position history of opcodes $A4/$A5: for battler slots 10
; down to 0 whose !Battler_PosHistOn is set, every !Battler_PosHistDelay
; frames (!Battler_PosHistTimer counts them) shifts records 0-2 into
; records 1-3 (x, y and their high bytes) and takes a new record 0: the
; battler's !Battler_ScreenX/Y plus its signed display offsets
; !Battler_UnkA4A4 / !Battler_UnkA4AF, as 16-bit values (low bytes in
; !Battler_PosHistX/Y, high bytes in !Battler_PosHistXHi/YHi).
; BattleCF_DrawPosHistory draws them. Runs with 8-bit X and Y.
; Callers (1 JSR site): BattleCF_FrameUpdate ($CF:E756).
; Entry: M=1, X=0, DP any, DB=$7E
; Exit:  M=1, X=0 (REP #$10 at the end); A clobbered; X = $00FF; Y's low
;        byte kept, high byte cleared (SEP #$10 at $CF:ED1B)
; No calls.
org $CFED18
BattleCF_RecordPosHistory:
    LDX.w #!Battle_NumSlots-1
    SEP #$10                            ; X 8-bit
.slot:
    LDA.w !Battler_PosHistOn,X
    BNE .on
    JMP .next
.on:
    DEC.w !Battler_PosHistTimer,X
    BEQ .record
    JMP .next
.record:
    LDA.w !Battler_PosHistDelay,X
    STA.w !Battler_PosHistTimer,X
    LDA.w !Battler_PosHistX+(2*!Battle_PosHistRecBytes),X
    STA.w !Battler_PosHistX+(3*!Battle_PosHistRecBytes),X
    LDA.w !Battler_PosHistX+(1*!Battle_PosHistRecBytes),X
    STA.w !Battler_PosHistX+(2*!Battle_PosHistRecBytes),X
    LDA.w !Battler_PosHistX,X
    STA.w !Battler_PosHistX+(1*!Battle_PosHistRecBytes),X
    LDA.w !Battler_PosHistXHi+(2*!Battle_PosHistRecBytes),X
    STA.w !Battler_PosHistXHi+(3*!Battle_PosHistRecBytes),X
    LDA.w !Battler_PosHistXHi+(1*!Battle_PosHistRecBytes),X
    STA.w !Battler_PosHistXHi+(2*!Battle_PosHistRecBytes),X
    LDA.w !Battler_PosHistXHi,X
    STA.w !Battler_PosHistXHi+(1*!Battle_PosHistRecBytes),X
    STZ.w !Battler_PosHistXHi,X
    LDA.w !Battler_UnkA4A4,X
    BPL .x_pos
    DEC.w !Battler_PosHistXHi,X         ; negative offset: high byte $FF
.x_pos:
    CLC
    ADC.w !Battler_ScreenX,X
    STA.w !Battler_PosHistX,X
    LDA.w !Battler_PosHistXHi,X
    ADC.b #$00
    STA.w !Battler_PosHistXHi,X
    LDA.w !Battler_PosHistY+(2*!Battle_PosHistRecBytes),X
    STA.w !Battler_PosHistY+(3*!Battle_PosHistRecBytes),X
    LDA.w !Battler_PosHistY+(1*!Battle_PosHistRecBytes),X
    STA.w !Battler_PosHistY+(2*!Battle_PosHistRecBytes),X
    LDA.w !Battler_PosHistY,X
    STA.w !Battler_PosHistY+(1*!Battle_PosHistRecBytes),X
    LDA.w !Battler_PosHistYHi+(2*!Battle_PosHistRecBytes),X
    STA.w !Battler_PosHistYHi+(3*!Battle_PosHistRecBytes),X
    LDA.w !Battler_PosHistYHi+(1*!Battle_PosHistRecBytes),X
    STA.w !Battler_PosHistYHi+(2*!Battle_PosHistRecBytes),X
    LDA.w !Battler_PosHistYHi,X
    STA.w !Battler_PosHistYHi+(1*!Battle_PosHistRecBytes),X
    STZ.w !Battler_PosHistYHi,X
    LDA.w !Battler_UnkA4AF,X
    BPL .y_pos
    DEC.w !Battler_PosHistYHi,X
.y_pos:
    CLC
    ADC.w !Battler_ScreenY,X
    STA.w !Battler_PosHistY,X
    LDA.w !Battler_PosHistYHi,X
    ADC.b #$00
    STA.w !Battler_PosHistYHi,X
.next:
    DEX
    BMI .done
    JMP .slot
.done:
    REP #$10
    RTS

; $CF:EDB8 — BattleCF_DrawFrontLayer (63 bytes, $EDB8–$EDF6)
; Called by BattleCF_BuildSprites just before a battler's own sprites, so
; what it adds shows in front of the battler. By state:
;   - !Battle_ActUnkA3D1 set: jumps to BattleCF_DrawHitNumbers;
;   - else, while an action runs or !Battle_UnkA0FE is set (the
;     end-of-battle poses): draws every action object linked to this
;     battler with bit 7 (!Battle_ActObjLinks entry thread * 11 + slot)
;     whose !Battle_ActObjUnkA1D8 is non-zero (BattleCF_DrawActObj);
;   - else jumps to BattleCF_DrawFxOverlay (the status overlay).
; The objects BattleCF_ObjMoveOrbit links with bit 7 are those on the
; near half of the circle (angle below $80), which fits "in front".
; Callers (1 JSR site): BattleCF_BuildSprites ($CF:E8D4).
; Entry: M=1, X=0, DP=$1D00, DB=$7E; !BattleSpr_Index = the battler's
;        sprite index
; Exit:  M=1, X=0, DP=$1D00 (the jumped-to parts restore it too), DB=$7E;
;        A, X, Y clobbered; !BattleSpr_OamOfs moved past what was drawn;
;        DP $A1, $C6-$D1 (D = 0) written by BattleCF_DrawActObj
; Callees: BattleCF_DrawActObj; BattleCF_DrawHitNumbers and
;          BattleCF_DrawFxOverlay (JMP)
org $CFEDB8
BattleCF_DrawFrontLayer:
    LDA.w !Battle_ActUnkA3D1
    BEQ .not_numbers
    JMP BattleCF_DrawHitNumbers
.not_numbers:
    LDA.w !Battle_ActRunning
    BNE .objects
    LDA.w !Battle_UnkA0FE
    BNE .objects
    JMP BattleCF_DrawFxOverlay
.objects:
    SEC
    LDA.b !BattleSpr_Index-!BattleSpr_Page
    SBC.b #!Battle_SprIdxBias
    TAX                                 ; X = slot: link entry of thread 0
.link:
    PHX
    LDA.w !Battle_ActObjLinks,X
    BEQ .link_next
    BPL .link_next                      ; bit 7: in front
    PHX
    AND.b #!Battle_ActLinkThreadMask7F
    TAX
    LDA.w !Battle_ActObjUnkA1D8,X
    BEQ .link_hidden
    PLX
    JSR BattleCF_DrawActObj
    BRA .link_next
.link_hidden:
    PLX
.link_next:
    PLX
    TXA
    CLC
    ADC.b #!Battle_NumSlots
    TAX                                 ; next thread's entry
    CPX.w #!Battle_ActLinkBytes
    BCC .link
    RTS

; $CF:EDF7 — BattleCF_DrawBackObjects (53 bytes, $EDF7–$EE2B)
; Called by BattleCF_BuildSprites just after a battler's own sprites, so
; these show behind it: while an action runs and !Battle_ActUnkA3D1 is
; clear, draws every action object linked to this battler with bit 7
; clear (bit 6, as opcodes $73/$74 and BattleCF_ObjMoveOrbit set it) whose
; !Battle_ActObjUnkA1D8 is non-zero (BattleCF_DrawActObj).
; Callers (1 JSR site): BattleCF_BuildSprites ($CF:E8F7).
; Entry: M=1, X=0, DP=$1D00, DB=$7E; !BattleSpr_Index = the battler's
;        sprite index; A's high byte 0 (the TAXs use it; BattleCF_DrawBattler
;        leaves it so, and BattleCF_DrawActObj returns with it 0)
; Exit:  M=1, X=0, DP=$1D00, DB=$7E; A, X, Y clobbered (X = $58 + the
;        battler's slot (0-10) after the scan: it steps by 11 from the slot
;        until $58 or more); !BattleSpr_OamOfs moved past what was drawn;
;        DP $A1, $C6-$D1 (D = 0) written by BattleCF_DrawActObj
; Callees: BattleCF_DrawActObj
org $CFEDF7
BattleCF_DrawBackObjects:
    LDA.w !Battle_ActRunning
    BEQ .done
    LDA.w !Battle_ActUnkA3D1
    BEQ .objects
.done:
    RTS
.objects:
    SEC
    LDA.b !BattleSpr_Index-!BattleSpr_Page
    SBC.b #!Battle_SprIdxBias
    TAX
.link:
    PHX
    LDA.w !Battle_ActObjLinks,X
    BEQ .link_next
    BMI .link_next                      ; bit 7: drawn in front instead
    PHX
    AND.b #!Battle_ActLinkThreadMaskBF
    TAX
    LDA.w !Battle_ActObjUnkA1D8,X
    BEQ .link_hidden
    PLX
    JSR BattleCF_DrawActObj
    BRA .link_next
.link_hidden:
    PLX
.link_next:
    PLX
    TXA
    CLC
    ADC.b #!Battle_NumSlots
    TAX
    CPX.w #!Battle_ActLinkBytes
    BCC .link
    RTS

; $CF:EE2C — BattleCF_DrawFxOverlay (115 bytes, $EE2C–$EE9E)
; The status overlay (Battle_FxOverlay* turn it on): for the battler
; !BattleSpr_Index with !Battler_FxOverlayOn set, steps its frame (0-3,
; every !Battler_FxOverlayPeriod frames, !Battler_FxOverlayTimer counting)
; and puts one sprite from !BattleRom_FxOverlaySpr record
; !Battler_FxOverlayBase + frame * 4 at its !Battler_ScreenX/Y plus the
; record's offsets (8-bit adds), attribute | !Battle_ActAttrBits. Runs
; with D = 0 and puts $1D00 back at the end.
; Callers (1 JMP site): BattleCF_DrawFrontLayer ($CF:EDCA).
; Entry: M=1, X=0, DP=$1D00, DB=$7E (reached by JMP from
;        BattleCF_DrawFrontLayer when no action runs)
; Exit:  M=1, X=0, DP=$1D00, DB=$7E; A, X, Y clobbered (Y = $1D00);
;        !BattleSpr_OamOfs moved on by 4 when drawn; DP $CC-$CD (D = 0)
;        written
; Callers note: JMP from BattleCF_DrawFrontLayer ($CF:EDCA).
; No calls.
!BattleCF_OvlX = !BattleCF_TmpCC        ; 1 B: the battler's screen x
!BattleCF_OvlY = !BattleCF_TmpCD        ; 1 B: its screen y
org $CFEE2C
BattleCF_DrawFxOverlay:
    LDY.w #$0000
    PHY
    PLD                                 ; D = 0
    SEC
    LDA.w !BattleSpr_Index
    SBC.b #!Battle_SprIdxBias
    TAX
    LDA.w !Battler_FxOverlayOn,X
    BEQ .done
    LDA.w !Battler_ScreenX,X
    STA.b !BattleCF_OvlX
    LDA.w !Battler_ScreenY,X
    STA.b !BattleCF_OvlY
    DEC.w !Battler_FxOverlayTimer,X
    BNE .draw
    LDA.w !Battler_FxOverlayPeriod,X
    STA.w !Battler_FxOverlayTimer,X
    INC.w !Battler_FxOverlayFrame,X
    LDA.w !Battler_FxOverlayFrame,X
    CMP.b #!Battle_FxOverlayFrames
    BNE .draw
    TDC
    STA.w !Battler_FxOverlayFrame,X
.draw:
    LDA.w !Battler_FxOverlayFrame,X
    ASL A
    ASL A
    CLC
    ADC.w !Battler_FxOverlayBase,X
    TAX
    LDY.w !BattleSpr_OamOfs
    CLC
    LDA.l BattleRom_FxOverlaySpr.DX,X
    ADC.b !BattleCF_OvlX
    STA.w BattleOam.X,Y
    CLC
    LDA.l BattleRom_FxOverlaySpr.DY,X
    ADC.b !BattleCF_OvlY
    STA.w BattleOam.Y,Y
    LDA.l BattleRom_FxOverlaySpr.Tile,X
    STA.w BattleOam.Tile,Y
    LDA.l BattleRom_FxOverlaySpr.Attr,X
    ORA.w !Battle_ActAttrBits
    STA.w BattleOam.Attr,Y
    INY
    INY
    INY
    INY
    STY.w !BattleSpr_OamOfs
.done:
    LDY.w #!BattleSpr_Page
    PHY
    PLD
    RTS

; $CF:EE9F — BattleCF_DrawHitNumbers (76 bytes, $EE9F–$EEEA)
; Puts the four hit-number sprites (Battle_HitNumSprite) of the battler
; !BattleSpr_Index into OAM, when !Battler_HitNumShown is set, and stores
; its !Battle_HitNumHigh byte as the whole OAM high-table byte of the
; first one (the four sprites' bits; that lines up only when
; !BattleSpr_OamOfs is a multiple of 16, not checked here).
; Callers (1 JMP site): BattleCF_DrawFrontLayer ($CF:EDBD).
; Entry: M=1, X=0, DP=$1D00, DB=$7E (reached by JMP from
;        BattleCF_DrawFrontLayer while !Battle_ActUnkA3D1 is set)
; Exit:  M=1, X=0, DP=$1D00, DB=$7E; A, X, Y clobbered;
;        !BattleSpr_OamOfs moved on by 16 when drawn; $7E:00C8 (DP $C8 of
;        the D = 0 code) used as the counter
; Callers note: JMP from BattleCF_DrawFrontLayer ($CF:EDBD).
; No calls.
org $CFEE9F
BattleCF_DrawHitNumbers:
    SEC
    LDA.b !BattleSpr_Index-!BattleSpr_Page
    SBC.b #!Battle_SprIdxBias
    TAX                                 ; X = slot
    LDA.w !Battler_HitNumShown,X
    BEQ .done
    LDY.b !BattleSpr_OamOfs-!BattleSpr_Page
    LDA.w !Battle_OamHighIdx,Y
    TAY
    LDA.w !Battle_HitNumHigh,X
    STA.w !BattleOam_HighTable,Y
    TXA
    ASL A
    ASL A
    ASL A
    ASL A
    TAX                                 ; X = slot * 16: its four records
    LDA.b #!Battle_HitNumSprites
    STA.w !BattleCF_TmpC8
    LDY.b !BattleSpr_OamOfs-!BattleSpr_Page
.sprite:
    LDA.w Battle_HitNumSprite.X,X
    STA.w BattleOam.X,Y
    LDA.w Battle_HitNumSprite.Y,X
    STA.w BattleOam.Y,Y
    LDA.w Battle_HitNumSprite.Tile,X
    STA.w BattleOam.Tile,Y
    LDA.w Battle_HitNumSprite.Attr,X
    STA.w BattleOam.Attr,Y
    INY
    INY
    INY
    INY
    INX
    INX
    INX
    INX
    DEC.w !BattleCF_TmpC8
    BNE .sprite
    STY.b !BattleSpr_OamOfs-!BattleSpr_Page
.done:
    RTS

; $CF:EEEB — BattleCF_DrawActObj (196 bytes, $EEEB–$EFAE)
; Draws one action object: the thread in bits 0-2 of !Battle_ActObjLinks
; entry X. Its position is !Battle_ActObjX/Y + !Battle_ActObjOfsX/Y
; (16-bit). When its !Battle_ActObjAnimTimer is 0 nothing is drawn; else
; the frame in bits 0-5 of !Battle_ActObjFrame gives
; !Battle_ActFrameSprites sprites from its BattleActSprite block
; (!BattleRom_ActFrameBase): each at the position plus the sprite's
; unsigned offsets, its attribute's priority bits replaced by
; !Battle_ActObjAttr, x bit 8 set in the high table as in
; BattleCF_DrawBattler. Runs with D = 0 and puts $1D00 back at the end.
; Callers (2 JSR sites): BattleCF_DrawFrontLayer ($CF:EDE5) and BattleCF_DrawBackObjects ($CF:EE1A).
; Entry: M=1, X=0, DP=$1D00, DB=$7E; X = link entry (thread * 11 + slot)
; Exit:  M=1, X=0, DP=$1D00, DB=$7E; A, X, Y clobbered;
;        !BattleSpr_OamOfs moved past the sprites; DP $A1, $C6-$D1 (D = 0)
;        written ($A1 is !Battle_ArgSlot, which BattleCF_FrameUpdate
;        saves around the build)
; No calls.
!BattleCF_ObjAttr = !Battle_ArgSlot     ; 1 B: the object's !Battle_ActObjAttr
!BattleCF_ObjX = !BattleCF_TmpCC        ; 2 B: its x
!BattleCF_ObjY = !BattleCF_TmpCE        ; 2 B: its y
!BattleCF_ObjSrc = !BattleCF_TmpC6      ; 2 B: address of the current BattleActSprite record
!BattleCF_ObjCount = !BattleCF_TmpC8    ; 2 B: frame bytes (sprites * 4), then sprites left
!BattleCF_ObjSprX = !BattleCF_TmpCA     ; 2 B: the sprite's x
!BattleCF_ObjSprY = !BattleCF_TmpD0     ; 2 B: the sprite's y
org $CFEEEB
BattleCF_DrawActObj:
    LDY.w #$0000
    PHY
    PLD                                 ; D = 0
    LDA.w !Battle_ActObjLinks,X
    AND.b #!Battle_ObjThreadMask
    TAX                                 ; X = thread
    ASL A
    TAY                                 ; Y = thread * 2
    LDA.w !Battle_ActObjAttr,X
    STA.b !BattleCF_ObjAttr
    REP #$21
    LDA.w !Battle_ActObjX,Y
    ADC.w !Battle_ActObjOfsX,Y
    STA.b !BattleCF_ObjX
    CLC
    LDA.w !Battle_ActObjY,Y
    ADC.w !Battle_ActObjOfsY,Y
    STA.b !BattleCF_ObjY
    TDC
    SEP #$20
    LDA.w !Battle_ActObjAnimTimer,X
    BNE .shown
    JMP .done
.shown:
    LDA.w !Battle_ActObjFrame,X
    AND.b #!Battle_ActFrameMask
    TAY                                 ; Y = frame
    LDA.w !Battle_ActFrameSprites,Y
    ASL A
    ASL A
    TAX
    STX.b !BattleCF_ObjCount            ; bytes of OAM it takes
    REP #$30
    TYA
    ASL A
    TAX
    LDA.l !BattleRom_ActFrameBase,X
    TAX
    STX.b !BattleCF_ObjSrc
    LDY.w !BattleSpr_OamOfs
    LDA.b !BattleCF_ObjCount
    PHA
    LSR A
    LSR A
    STA.b !BattleCF_ObjCount            ; sprites
    TDC
    SEP #$20
.sprite:
    LDA.w BattleActSprite.X,X
    REP #$21
    ADC.b !BattleCF_ObjX
    STA.b !BattleCF_ObjSprX
    SEP #$20
    STA.w BattleOam.X,Y
    TDC
    LDA.w BattleActSprite.Y,X
    REP #$21
    ADC.b !BattleCF_ObjY
    STA.b !BattleCF_ObjSprY
    SEP #$20
    STA.w BattleOam.Y,Y
    TDC
    LDA.w BattleActSprite.Tile,X
    STA.w BattleOam.Tile,Y
    LDA.w BattleActSprite.Attr,X
    AND.b #!Battle_OamAttrNoPriority
    ORA.b !BattleCF_ObjAttr
    STA.w BattleOam.Attr,Y
    LDA.b !BattleCF_ObjSprY+1
    BEQ .y_on
    LDA.b !BattleCF_ObjSprY
    CMP.b #!Battle_SprHideY
    BCC .hide
    BRA .next
.y_on:
    LDA.b !BattleCF_ObjSprX+1
    BEQ .next
.hide:
    LDA.w !Battle_OamHighIdx,Y
    TAX
    LDA.w !BattleOam_HighTable,X
    ORA.w !Battle_OamHighXBit,Y
    STA.w !BattleOam_HighTable,X
.next:
    LDX.b !BattleCF_ObjSrc
    INX
    INX
    INX
    INX
    STX.b !BattleCF_ObjSrc
    INY
    INY
    INY
    INY
    DEC.b !BattleCF_ObjCount
    BNE .sprite
    REP #$31
    PLA
    ADC.w !BattleSpr_OamOfs
    STA.w !BattleSpr_OamOfs
    TDC
    SEP #$20
.done:
    LDX.w #!BattleSpr_Page
    PHX
    PLD
    RTS

; ============================================================
; Action movers ($CF:EFAF–$CF:F977)
; ============================================================
; The move opcodes (BattleAct_Op*) set an actor's mover kind, steps and
; start, set !Battle_ActorMoving and wait for the done flag; the movers
; below make the steps. An actor is a battler slot (0-10) or an object
; thread (0-7); the actor arrays hold the 11 battlers first and the
; objects from index 11 (byte arrays), 22 (word arrays) or 44 (4-byte
; arrays), which the object movers reach as array + !Battle_NumSlots
; (and twice / four times that). Each mover is entered with the actor in
; DP $C6 (!BattleCF_Actor), actor * 2 in $C8 and actor * 4 in $CA, and
; returns with M=1, X=0.

!BattleCF_Actor = !BattleCF_TmpC6       ; 2 B: actor (battler slot, or object thread for the object movers)
!BattleCF_Actor2 = !BattleCF_TmpC8      ; 2 B: actor * 2 (word arrays)
!BattleCF_Actor4 = !BattleCF_TmpCA      ; 2 B: actor * 4 (4-byte arrays)
!BattleCF_SinPart = !BattleCF_TmpCC     ; 1 B: sine part of a step (added to y)
!BattleCF_CosPart = !BattleCF_TmpCD     ; 1 B: cosine part (added to x)
!BattleCF_ArcLoop = !BattleCF_TmpCC     ; 2 B: arc speed steps left in this move step

; $CF:EFAF — BattleCF_RunMovers (111 bytes, $EFAF–$F01D)
; While an action runs: for battler slots 10 down to 0 with
; !Battle_ActorMoving set, counts !Battle_ActorMoveTimer down and at 0
; reloads it from !Battle_ActorMoveDelay and runs mover
; !Battle_ActorMoveKind from BattleCF_MoverTable; then the same for object
; threads 7 down to 0 (the objects' part of those arrays) with
; BattleCF_ObjMoverTable. With no action running it jumps to
; BattleCF_StepEnemies unless !Battle_UnkA0FD is set (then it does
; nothing).
; Callers (1 JSR site): BattleCF_FrameUpdate ($CF:E748).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $00-$06 (the sine
;        lookups) and $C6-$D1 written by the movers; !BattleCF_Actor = $FF
;        after the loops
; Callees: the movers of BattleCF_MoverTable and BattleCF_ObjMoverTable
;          (JSR (table,X)); BattleCF_StepEnemies (JMP)
org $CFEFAF
BattleCF_RunMovers:
    LDA.w !Battle_ActRunning
    BNE .action
    LDA.w !Battle_UnkA0FD
    BEQ .enemies
    RTS
.enemies:
    JMP BattleCF_StepEnemies
.action:
    LDX.w #!Battle_NumSlots-1
    STX.b !BattleCF_Actor
.battler:
    LDX.b !BattleCF_Actor
    LDA.w !Battle_ActorMoving,X
    BEQ .battler_next
    DEC.w !Battle_ActorMoveTimer,X
    BNE .battler_next
    LDA.w !Battle_ActorMoveDelay,X
    STA.w !Battle_ActorMoveTimer,X
    REP #$20
    LDA.b !BattleCF_Actor
    ASL A
    STA.b !BattleCF_Actor2
    ASL A
    STA.b !BattleCF_Actor4
    TDC
    SEP #$20
    LDA.w !Battle_ActorMoveKind,X
    ASL A
    TAX
    JSR (BattleCF_MoverTable,X)
.battler_next:
    DEC.b !BattleCF_Actor
    BPL .battler
    LDX.w #!Battle_LastObjThread
    STX.b !BattleCF_Actor
.object:
    LDX.b !BattleCF_Actor
    LDA.w !Battle_ActorMoving+!Battle_NumSlots,X
    BEQ .object_next
    DEC.w !Battle_ActorMoveTimer+!Battle_NumSlots,X
    BNE .object_next
    LDA.w !Battle_ActorMoveDelay+!Battle_NumSlots,X
    STA.w !Battle_ActorMoveTimer+!Battle_NumSlots,X
    REP #$20
    LDA.b !BattleCF_Actor
    ASL A
    STA.b !BattleCF_Actor2
    ASL A
    STA.b !BattleCF_Actor4
    TDC
    SEP #$20
    LDA.w !Battle_ActorMoveKind+!Battle_NumSlots,X
    ASL A
    TAX
    JSR (BattleCF_ObjMoverTable,X)
.object_next:
    DEC.b !BattleCF_Actor
    BPL .object
    RTS

; $CF:F01E — BattleCF_MoverTable (16 bytes, $F01E–$F02D)
; The battlers' movers by !Battle_ActorMoveKind (BattleCF_RunMovers).
BattleCF_MoverTable:
    dw BattleCF_MoveStraight            ; 0
    dw BattleCF_MoveArc                 ; 1 !Battle_MoveKindArc
    dw BattleCF_MoveHeading             ; 2 !Battle_MoveKindHeading
    dw BattleCF_MoveCircle              ; 3 !Battle_MoveKindCircle
    dw BattleCF_MoveKind4               ; 4 !Battle_MoveKindUnk4
    dw BattleCF_MoveEllipse             ; 5 !Battle_MoveKindEllipse
    dw BattleCF_MoveShake               ; 6 !Battle_MoveKindShake
    dw BattleCF_MoveCurve               ; 7 !Battle_MoveKindCurve

; $CF:F02E — BattleCF_ObjMoverTable (16 bytes, $F02E–$F03D)
; The object threads' movers by their !Battle_ActorMoveKind entry.
; Quirk: kind 6 is the battlers' BattleCF_MoveShake, which works on the
; battler arrays with the object's thread number as a slot (no object
; shake found, so probably never used).
BattleCF_ObjMoverTable:
    dw BattleCF_ObjMoveStraight         ; 0
    dw BattleCF_ObjMoveArc              ; 1
    dw BattleCF_ObjMoveHeading          ; 2
    dw BattleCF_ObjMoveCircle           ; 3
    dw BattleCF_ObjMoveKind4            ; 4
    dw BattleCF_ObjMoveOrbit            ; 5
    dw BattleCF_MoveShake               ; 6 (the battlers' mover)
    dw BattleCF_ObjMoveCurve            ; 7

; $CF:F03E — BattleCF_MoveStraight (73 bytes, $F03E–$F086)
; Mover kind 0: unless the battler's !Battler_MoveDone is set, adds
; !Battle_ActorStepX/Y to !Battle_ActorOfsX/Y (8.8) and puts the battler
; at !Battle_ActorFromX/Y + the offsets' high bytes; counts
; !Battle_ActorMoveSteps down and sets !Battler_MoveDone at 0 (at once
; when it is already 0).
; Callers note: BattleCF_MoverTable entry 0 (JSR (table,X) in BattleCF_RunMovers).
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleCF_Actor/2 set (see the banner)
; Exit:  M=1, X=0, DP=0, DB=$7E; X = the actor; A, Y clobbered
; No calls.
org $CFF03E
BattleCF_MoveStraight:
    LDX.b !BattleCF_Actor
    LDA.w !Battler_MoveDone,X
    BNE .done
    LDA.w !Battle_ActorMoveSteps,X
    BEQ .end
    LDX.b !BattleCF_Actor2
    REP #$21
    LDA.w !Battle_ActorStepX,X
    ADC.w !Battle_ActorOfsX,X
    STA.w !Battle_ActorOfsX,X
    CLC
    LDA.w !Battle_ActorStepY,X
    ADC.w !Battle_ActorOfsY,X
    STA.w !Battle_ActorOfsY,X
    TDC
    SEP #$20
    LDX.b !BattleCF_Actor
    LDY.b !BattleCF_Actor2
    CLC
    LDA.w !Battle_ActorOfsX+1,Y
    ADC.w !Battle_ActorFromX,X
    STA.w !Battler_ScreenX,X
    CLC
    LDA.w !Battle_ActorOfsY+1,Y
    ADC.w !Battle_ActorFromY,X
    STA.w !Battler_ScreenY,X
    DEC.w !Battle_ActorMoveSteps,X
    BNE .done
.end:
    LDA.b #$01
    STA.w !Battler_MoveDone,X
.done:
    RTS

; $CF:F087 — BattleCF_MoveArc (269 bytes, $F087–$F193)
; Mover kind 1, the arc moves (see the arc notes at !Battle_ActorArcSteps
; in ram_battle.inc): steps the offset like BattleCF_MoveStraight, then
; !Battle_ActorMoveSpeed times steps the arc's speed and height (rising:
; the speed drops by !Battle_ActorArcAccel and the height grows by it;
; once the speed would go below 0 it is zeroed and the arc falls: the
; speed grows by the accel and the height shrinks by it; once it would
; pass $FFFF it is reset to !Battle_ActorArcSpeed0 and the arc rises
; again). Puts the battler at its start + the offsets and writes the
; height's pixel part h to !Battler_UnkA4AF: -h (or +h with
; !Battle_ActorArcDown set) when !Battle_ActorArcMode is non-zero, -2h
; (or +2h) when it is 0. Counts !Battle_ActorArcSteps down; at 0 (or at
; once when it is 0) zeroes !Battler_UnkA4AF and sets !Battler_MoveDone.
; Callers note: BattleCF_MoverTable entry 1.
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleCF_Actor/2/4 set
; Exit:  M=1, X=0, DP=0, DB=$7E; X = the actor; A, Y clobbered; DP $04
;        (the height) and $CC-$CD written
; No calls.
org $CFF087
BattleCF_MoveArc:
    LDX.b !BattleCF_Actor
    LDA.w !Battler_MoveDone,X
    BEQ .moving
    JMP .done
.moving:
    LDA.w !Battle_ActorArcSteps,X
    BNE .step
    JMP .end
.step:
    LDX.b !BattleCF_Actor2
    REP #$21
    LDA.w !Battle_ActorStepX,X
    ADC.w !Battle_ActorOfsX,X
    STA.w !Battle_ActorOfsX,X
    CLC
    LDA.w !Battle_ActorStepY,X
    ADC.w !Battle_ActorOfsY,X
    STA.w !Battle_ActorOfsY,X
    TDC
    SEP #$20
    LDX.b !BattleCF_Actor
    LDA.w !Battle_ActorMoveSpeed,X
    TAX
    STX.b !BattleCF_ArcLoop
    REP #$20
    LDY.b !BattleCF_Actor4
    LDX.b !BattleCF_Actor2
.arc_loop:
    LDA.w !Battle_ActorArcFalling,X
    BNE .falling_speed
    SEC
    LDA.w !Battle_ActorArcSpeed,Y
    SBC.w !Battle_ActorArcAccel,X
    STA.w !Battle_ActorArcSpeed,Y
    BCS .height
    TDC
    STA.w !Battle_ActorArcSpeed,Y
    STA.w !Battle_ActorArcSpeed+2,Y
    INC A
    STA.w !Battle_ActorArcFalling,X
    BRA .height
.falling_speed:
    CLC
    LDA.w !Battle_ActorArcSpeed,Y
    ADC.w !Battle_ActorArcAccel,X
    STA.w !Battle_ActorArcSpeed,Y
    BCC .height
    LDA.w !Battle_ActorArcSpeed0,X
    STA.w !Battle_ActorArcSpeed,Y
    TDC
    STA.w !Battle_ActorArcSpeed+2,Y
    STA.w !Battle_ActorArcFalling,X
.height:
    LDA.w !Battle_ActorArcFalling,X
    BNE .falling_height
    CLC
    LDA.w !Battle_ActorArcSpeed,Y
    ADC.w !Battle_ActorArcHeight,Y
    STA.w !Battle_ActorArcHeight,Y
    LDA.w !Battle_ActorArcSpeed+2,Y
    ADC.w !Battle_ActorArcHeight+2,Y
    STA.w !Battle_ActorArcHeight+2,Y
    BRA .arc_next
.falling_height:
    SEC
    LDA.w !Battle_ActorArcHeight,Y
    SBC.w !Battle_ActorArcSpeed,Y
    STA.w !Battle_ActorArcHeight,Y
    LDA.w !Battle_ActorArcHeight+2,Y
    SBC.w !Battle_ActorArcSpeed+2,Y
    STA.w !Battle_ActorArcHeight+2,Y
.arc_next:
    DEC.b !BattleCF_ArcLoop
    BNE .arc_loop
    LDA.w !Battle_ActorArcHeight+2,Y
    STA.b !BattleCF_SinProduct          ; the height in pixels (scratch)
    TDC
    SEP #$20
    LDX.b !BattleCF_Actor
    LDY.b !BattleCF_Actor2
    CLC
    LDA.w !Battle_ActorOfsX+1,Y
    ADC.w !Battle_ActorFromX,X
    STA.w !Battler_ScreenX,X
    CLC
    LDA.w !Battle_ActorOfsY+1,Y
    ADC.w !Battle_ActorFromY,X
    STA.w !Battler_ScreenY,X
    LDA.w !Battle_ActorArcDown,X
    BNE .down
    LDA.w !Battle_ActorArcMode,Y
    BEQ .up_double
    SEC
    LDA.b #$00
    SBC.b !BattleCF_SinProduct
    STA.w !Battler_UnkA4AF,X
    BRA .count
.up_double:
    SEC
    LDA.b #$00
    SBC.b !BattleCF_SinProduct
    SEC
    SBC.b !BattleCF_SinProduct
    STA.w !Battler_UnkA4AF,X
    BRA .count
.down:
    LDA.w !Battle_ActorArcMode,Y
    BEQ .down_double
    CLC
    LDA.b #$00
    ADC.b !BattleCF_SinProduct
    STA.w !Battler_UnkA4AF,X
    BRA .count
.down_double:
    CLC
    LDA.b #$00
    ADC.b !BattleCF_SinProduct
    CLC
    ADC.b !BattleCF_SinProduct
    STA.w !Battler_UnkA4AF,X
.count:
    LDX.b !BattleCF_Actor
    DEC.w !Battle_ActorArcSteps,X
    BNE .done
.end:
    STZ.w !Battler_UnkA4AF,X
    LDA.b #$01
    STA.w !Battler_MoveDone,X
.done:
    RTS

; $CF:F194 — BattleCF_MoveHeading (100 bytes, $F194–$F1F7)
; Mover kind 2, the heading moves: ends the move (!Battler_MoveDone)
; when the battler's 16-pixel cell (BattleCF_PixelToCell of its screen y,
; then x) is in row 0 or !Battle_CellRowBottom or column 0 or
; !Battle_CellColRight (the screen's edge cells, probably), or when
; !Battle_ActorHeadSteps counts down to 0; else adds
; !Battle_ActorMoveSpeed to the distance !Battle_ActorUnkA311, copies
; !Battle_ActorMoveAngle to !Battle_ActorUnkA5AA and puts the battler at
; !Battle_ActorFromX/Y + distance * (cos, sin) of the angle.
; Callers note: BattleCF_MoverTable entry 2.
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleCF_Actor set
; Exit:  M=1, X=0, DP=0, DB=$7E; X = the actor; Y unchanged; A
;        clobbered; DP $00-$06, $CC-$CD written when it steps
; Callees: BattleCF_PixelToCell, Battle_SinLookupCF
org $CFF194
BattleCF_MoveHeading:
    LDX.b !BattleCF_Actor
    LDA.w !Battler_MoveDone,X
    BNE .done
    LDA.w !Battler_ScreenY,X
    JSR BattleCF_PixelToCell
    BEQ .end
    CMP.b #!Battle_CellRowBottom
    BEQ .end
    LDA.w !Battler_ScreenX,X
    JSR BattleCF_PixelToCell
    BEQ .end
    CMP.b #!Battle_CellColRight
    BEQ .end
    DEC.w !Battle_ActorHeadSteps,X
    BEQ .end
    CLC
    LDA.w !Battle_ActorUnkA311,X
    ADC.w !Battle_ActorMoveSpeed,X
    STA.w !Battle_ActorUnkA311,X
    STA.b !BattleCF_SinScale
    LDA.w !Battle_ActorMoveAngle,X
    STA.w !Battle_ActorUnkA5AA,X
    JSR Battle_SinLookupCF
    STA.b !BattleCF_SinPart
    LDX.b !BattleCF_Actor
    CLC
    LDA.w !Battle_ActorMoveAngle,X
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookupCF
    STA.b !BattleCF_CosPart
    LDX.b !BattleCF_Actor
    CLC
    LDA.w !Battle_ActorFromY,X
    ADC.b !BattleCF_SinPart
    STA.w !Battler_ScreenY,X
    CLC
    LDA.w !Battle_ActorFromX,X
    ADC.b !BattleCF_CosPart
    STA.w !Battler_ScreenX,X
    BRA .done
.end:
    LDA.b #$01
    STA.w !Battler_MoveDone,X
.done:
    RTS

; $CF:F1F8 — BattleCF_MoveCircle (69 bytes, $F1F8–$F23C)
; Mover kind 3: unless done, adds !Battle_ActorCircleStep to
; !Battle_ActorCircleAngle and writes radius * sin(angle) to
; !Battler_UnkA4AF and radius * cos(angle) to !Battler_UnkA4A4 (the
; display offsets: the battler itself stays put); counts the 16-bit
; !Battle_ActorCircleSteps down and counts !Battler_MoveDone up at 0.
; Callers note: BattleCF_MoverTable entry 3.
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleCF_Actor/2 set
; Exit:  M=1, X=0, DP=0, DB=$7E; Y = the actor; X = the actor when the
;        steps run out, actor * 2 after another step, unchanged when
;        already done; A clobbered; DP $00-$06 written when it steps
; Callees: Battle_SinLookupCF
org $CFF1F8
BattleCF_MoveCircle:
    LDY.b !BattleCF_Actor
    LDA.w !Battler_MoveDone,Y
    BNE .done
    LDA.w !Battle_ActorCircleRadius,Y
    STA.b !BattleCF_SinScale
    CLC
    LDA.w !Battle_ActorCircleAngle,Y
    ADC.w !Battle_ActorCircleStep,Y
    STA.w !Battle_ActorCircleAngle,Y
    JSR Battle_SinLookupCF
    STA.w !Battler_UnkA4AF,Y
    CLC
    LDA.w !Battle_ActorCircleAngle,Y
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookupCF
    STA.w !Battler_UnkA4A4,Y
    LDX.b !BattleCF_Actor2
    SEC
    LDA.w !Battle_ActorCircleSteps,X
    SBC.b #$01
    STA.w !Battle_ActorCircleSteps,X
    LDA.w !Battle_ActorCircleSteps+1,X
    SBC.b #$00
    STA.w !Battle_ActorCircleSteps+1,X
    ORA.w !Battle_ActorCircleSteps,X
    BNE .done
    TYX
    INC.w !Battler_MoveDone,X
.done:
    RTS

; $CF:F23D — BattleCF_MoveKind4 (279 bytes, $F23D–$F353)
; Mover kind 4 (opcode $D2's move, a jump that lands on the point,
; probably; see BattleAct_OpMoveKind4ToCalc). While the arc rises it
; steps the offset and the arc as BattleCF_MoveArc does, 4 arc steps per
; move step, and counts !Battler_MoveDone up when the speed runs out (the
; top). Once falling, it first tests the battler against the point
; (!Battle_ActorToX/Y, BattleCF_PointsNear): with !Battle_ActorUnkAB00
; clear, within 16 pixels and with !Battler_UnkA4AF at
; !Battle_Kind4LandHeight or above (-24..-1) it counts !Battler_MoveDone
; and !Battle_ActorUnkAB00 up and returns; with it set, within 1 pixel
; (the same point) it counts !Battler_MoveDone up and returns; else it
; steps as while rising. There is no step count: only the landing ends it.
; The battler goes to its start + the offsets; !Battler_UnkA4AF gets -2h.
; Quirk: when !Battle_ActorArcMode is non-zero it first stores -h, then
; falls into the -2h store (no branch over it), so the mode makes no
; difference.
; Callers note: BattleCF_MoverTable entry 4.
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleCF_Actor/2/4 set
; Exit:  M=1, X=0, DP=0, DB=$7E; X = the actor; A, Y clobbered; DP $04
;        and $CC-$D1 written
; Callees: BattleCF_PointsNear
org $CFF23D
BattleCF_MoveKind4:
    LDX.b !BattleCF_Actor2
    LDA.w !Battle_ActorArcFalling,X
    BEQ .step
    LDX.b !BattleCF_Actor
    LDA.w !Battler_ScreenX,X
    STA.b !BattleCF_NearX1
    LDA.w !Battler_ScreenY,X
    STA.b !BattleCF_NearY1
    LDA.w !Battle_ActorToX,X
    STA.b !BattleCF_NearX2
    LDA.w !Battle_ActorToY,X
    STA.b !BattleCF_NearY2
    LDA.w !Battle_ActorUnkAB00,X
    BNE .landed
    LDA.b #!Battle_NearMargin
    STA.b !BattleCF_NearMargin
    JSR BattleCF_PointsNear
    LDA.b !BattleCF_Near
    BEQ .step
    LDA.w !Battler_UnkA4AF,X
    CMP.b #!Battle_Kind4LandHeight
    BCC .step
    INC.w !Battler_MoveDone,X
    INC.w !Battle_ActorUnkAB00,X
    RTS
.landed:
    LDA.b #$01
    STA.b !BattleCF_NearMargin
    JSR BattleCF_PointsNear
    LDA.b !BattleCF_Near
    BEQ .step
    INC.w !Battler_MoveDone,X
    RTS
.step:
    LDX.b !BattleCF_Actor2
    REP #$21
    LDA.w !Battle_ActorStepX,X
    ADC.w !Battle_ActorOfsX,X
    STA.w !Battle_ActorOfsX,X
    CLC
    LDA.w !Battle_ActorStepY,X
    ADC.w !Battle_ActorOfsY,X
    STA.w !Battle_ActorOfsY,X
    TDC
    SEP #$20
    LDX.w #!Battle_Kind4ArcSteps
    STX.b !BattleCF_ArcLoop
    REP #$20
    LDY.b !BattleCF_Actor4
    LDX.b !BattleCF_Actor2
.arc_loop:
    LDA.w !Battle_ActorArcFalling,X
    BNE .falling_speed
    SEC
    LDA.w !Battle_ActorArcSpeed,Y
    SBC.w !Battle_ActorArcAccel,X
    STA.w !Battle_ActorArcSpeed,Y
    BCS .height
    TDC
    STA.w !Battle_ActorArcSpeed,Y
    STA.w !Battle_ActorArcSpeed+2,Y
    INC A
    STA.w !Battle_ActorArcFalling,X
    PHX
    LDX.b !BattleCF_Actor
    INC.w !Battler_MoveDone,X           ; the top of the rise
    PLX
    BRA .height
.falling_speed:
    CLC
    LDA.w !Battle_ActorArcSpeed,Y
    ADC.w !Battle_ActorArcAccel,X
    STA.w !Battle_ActorArcSpeed,Y
    BCC .height
    LDA.w !Battle_ActorArcSpeed0,X
    STA.w !Battle_ActorArcSpeed,Y
    TDC
    STA.w !Battle_ActorArcSpeed+2,Y
    STA.w !Battle_ActorArcFalling,X
.height:
    LDA.w !Battle_ActorArcFalling,X
    BNE .falling_height
    CLC
    LDA.w !Battle_ActorArcSpeed,Y
    ADC.w !Battle_ActorArcHeight,Y
    STA.w !Battle_ActorArcHeight,Y
    LDA.w !Battle_ActorArcSpeed+2,Y
    ADC.w !Battle_ActorArcHeight+2,Y
    STA.w !Battle_ActorArcHeight+2,Y
    BRA .arc_next
.falling_height:
    SEC
    LDA.w !Battle_ActorArcHeight,Y
    SBC.w !Battle_ActorArcSpeed,Y
    STA.w !Battle_ActorArcHeight,Y
    LDA.w !Battle_ActorArcHeight+2,Y
    SBC.w !Battle_ActorArcSpeed+2,Y
    STA.w !Battle_ActorArcHeight+2,Y
.arc_next:
    DEC.b !BattleCF_ArcLoop
    BNE .arc_loop
    LDA.w !Battle_ActorArcHeight+2,Y
    STA.b !BattleCF_SinProduct          ; the height in pixels (scratch)
    TDC
    SEP #$20
    LDX.b !BattleCF_Actor
    LDY.b !BattleCF_Actor2
    CLC
    LDA.w !Battle_ActorOfsX+1,Y
    ADC.w !Battle_ActorFromX,X
    STA.w !Battler_ScreenX,X
    CLC
    LDA.w !Battle_ActorOfsY+1,Y
    ADC.w !Battle_ActorFromY,X
    STA.w !Battler_ScreenY,X
    LDA.w !Battle_ActorArcMode,Y
    BEQ .double
    SEC
    LDA.b #$00
    SBC.b !BattleCF_SinProduct
    STA.w !Battler_UnkA4AF,X            ; overwritten just below (quirk)
.double:
    SEC
    LDA.b #$00
    SBC.b !BattleCF_SinProduct
    SEC
    SBC.b !BattleCF_SinProduct
    STA.w !Battler_UnkA4AF,X
    RTS

; $CF:F354 — BattleCF_MoveEllipse (75 bytes, $F354–$F39E)
; Mover kind 5: BattleCF_MoveCircle with half the radius for the sine
; (y) part: !Battler_UnkA4AF = radius / 2 * sin(angle), !Battler_UnkA4A4
; = radius * cos(angle).
; Callers note: BattleCF_MoverTable entry 5.
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleCF_Actor/2 set
; Exit:  M=1, X=0, DP=0, DB=$7E; Y = the actor; X = the actor when the
;        steps run out, actor * 2 after another step, unchanged when
;        already done; A clobbered; DP $00-$06 written when it steps
; Callees: Battle_SinLookupCF
org $CFF354
BattleCF_MoveEllipse:
    LDY.b !BattleCF_Actor
    LDA.w !Battler_MoveDone,Y
    BNE .done
    LDA.w !Battle_ActorCircleRadius,Y
    LSR A
    STA.b !BattleCF_SinScale
    CLC
    LDA.w !Battle_ActorCircleAngle,Y
    ADC.w !Battle_ActorCircleStep,Y
    STA.w !Battle_ActorCircleAngle,Y
    JSR Battle_SinLookupCF
    STA.w !Battler_UnkA4AF,Y
    LDA.w !Battle_ActorCircleRadius,Y
    STA.b !BattleCF_SinScale
    CLC
    LDA.w !Battle_ActorCircleAngle,Y
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookupCF
    STA.w !Battler_UnkA4A4,Y
    LDX.b !BattleCF_Actor2
    SEC
    LDA.w !Battle_ActorCircleSteps,X
    SBC.b #$01
    STA.w !Battle_ActorCircleSteps,X
    LDA.w !Battle_ActorCircleSteps+1,X
    SBC.b #$00
    STA.w !Battle_ActorCircleSteps+1,X
    ORA.w !Battle_ActorCircleSteps,X
    BNE .done
    TYX
    INC.w !Battler_MoveDone,X
.done:
    RTS

; $CF:F39F — BattleCF_MoveShake (27 bytes, $F39F–$F3B9)
; Mover kind 6 (opcode $D8): BattleCF_ShakeStep, then, for battler slot
; !Battle_PartMainSlot (3) with !Battle_UnkA113 set, copies its display
; offsets !Battler_UnkA4A4/A4AF to slot !Battle_PartMirrorSlot (9).
; Also the objects' kind 6 (see BattleCF_ObjMoverTable).
; Callers note: BattleCF_MoverTable entry 6 and BattleCF_ObjMoverTable entry 6.
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleCF_Actor set
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered
; Callees: BattleCF_ShakeStep
org $CFF39F
BattleCF_MoveShake:
    JSR BattleCF_ShakeStep
    LDA.b !BattleCF_Actor
    CMP.b #!Battle_PartMainSlot
    BNE .done
    LDA.w !Battle_UnkA113
    BEQ .done
    LDA.w !Battler_UnkA4A4+!Battle_PartMainSlot
    STA.w !Battler_UnkA4A4+!Battle_PartMirrorSlot
    LDA.w !Battler_UnkA4AF+!Battle_PartMainSlot
    STA.w !Battler_UnkA4AF+!Battle_PartMirrorSlot
.done:
    RTS

; $CF:F3BA — BattleCF_ShakeStep (75 bytes, $F3BA–$F404)
; The shake: counts !Battler_ShakeFrames down; at 0 zeroes the display
; offsets and !Battle_ActorMoving (the move ends without the done flag).
; Else every !Battler_ShakePeriod frames toggles !Battler_ShakeOff: 1 =
; offsets zeroed, 0 = offsets set to !Battler_ShakeAmp * (cos, sin) of
; !Battle_ActorUnkA5AA (x to !Battler_UnkA4A4, y to !Battler_UnkA4AF).
; Callers (1 JSR site): BattleCF_MoveShake ($CF:F39F).
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleCF_Actor set
; Exit:  M=1, X=0, DP=0, DB=$7E; X = the actor, or the multiply's
;        partial product when the offsets are set; Y = the actor then,
;        else unchanged; A clobbered; DP $00-$06 written then
; Callees: Battle_SinLookupCF
org $CFF3BA
BattleCF_ShakeStep:
    LDX.b !BattleCF_Actor
    DEC.w !Battler_ShakeFrames,X
    BNE .running
    STZ.w !Battler_UnkA4A4,X
    STZ.w !Battler_UnkA4AF,X
    STZ.w !Battle_ActorMoving,X
    RTS
.running:
    DEC.w !Battler_ShakeTimer,X
    BEQ .toggle
    RTS
.toggle:
    LDA.w !Battler_ShakePeriod,X
    STA.w !Battler_ShakeTimer,X
    LDA.w !Battler_ShakeAmp,X
    STA.b !BattleCF_SinScale
    LDA.w !Battler_ShakeOff,X
    EOR.b #$01
    STA.w !Battler_ShakeOff,X
    BEQ .set
    STZ.w !Battler_UnkA4A4,X
    STZ.w !Battler_UnkA4AF,X
    RTS
.set:
    LDY.b !BattleCF_Actor
    LDA.w !Battle_ActorUnkA5AA,Y
    JSR Battle_SinLookupCF
    STA.w !Battler_UnkA4AF,Y
    CLC
    LDA.w !Battle_ActorUnkA5AA,Y
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookupCF
    STA.w !Battler_UnkA4A4,Y
    RTS

; $CF:F405 — BattleCF_MoveCurve (173 bytes, $F405–$F4B1)
; Mover kind 7, the curving move: when the battler is within 16 pixels of
; !Battle_ActorToX/Y in both axes (BattleCF_PointsNear) counts
; !Battler_MoveDone up and returns. Else takes the angle from the battler
; to the point (Battle_CalcAngleCF) and turns !Battle_ActorHeading
; towards it by up to !Battle_ActorMoveSpeed units (up with
; !Battle_ActorTurnDir 0, down with 1), counting !Battle_ActorOnCourse up
; when it gets there; once on course the heading simply takes the angle.
; Sets !Battler_Facing from the heading (!BattleRom_FacingByAngle) and
; moves the battler by speed * (cos, sin) of the heading.
; Callers note: BattleCF_MoverTable entry 7.
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleCF_Actor set
; Exit:  M=1, X=0, DP=0, DB=$7E; X = the actor; A, Y clobbered; DP
;        $00-$06, $CC-$D1 and !BattleCF_GeoOriginX..!BattleCF_GeoAngleIndex
;        written
; Callees: BattleCF_PointsNear, Battle_CalcAngleCF, Battle_SinLookupCF
org $CFF405
BattleCF_MoveCurve:
    LDX.b !BattleCF_Actor
    LDA.w !Battler_ScreenX,X
    STA.b !BattleCF_NearX1
    STA.w !BattleCF_GeoOriginX
    LDA.w !Battler_ScreenY,X
    STA.b !BattleCF_NearY1
    STA.w !BattleCF_GeoOriginY
    LDA.w !Battle_ActorToX,X
    STA.b !BattleCF_NearX2
    STA.w !BattleCF_GeoPointX
    LDA.w !Battle_ActorToY,X
    STA.b !BattleCF_NearY2
    STA.w !BattleCF_GeoPointY
    LDA.b #!Battle_NearMargin
    STA.b !BattleCF_NearMargin
    JSR BattleCF_PointsNear
    LDA.b !BattleCF_Near
    BEQ .steer
    INC.w !Battler_MoveDone,X
    RTS
.steer:
    JSR Battle_CalcAngleCF
    LDX.b !BattleCF_Actor
    LDA.w !Battle_ActorMoveSpeed,X
    STA.b !BattleCF_SinScale
    TAY                                 ; Y = turn units left
    LDA.w !Battle_ActorOnCourse,X
    BEQ .turn
    LDA.w !BattleCF_GeoAngle
    BRA .heading
.turn:
    LDA.w !Battle_ActorHeading,X
    CMP.w !BattleCF_GeoAngle
    BEQ .heading
    LDA.w !Battle_ActorTurnDir,X
    BNE .turn_down
    LDA.w !Battle_ActorHeading,X
.turn_up:
    CLC
    ADC.b #$01
    CMP.w !BattleCF_GeoAngle
    BEQ .on_course
    DEY
    BNE .turn_up
    BRA .heading
.turn_down:
    LDA.w !Battle_ActorHeading,X
.turn_down_loop:
    SEC
    SBC.b #$01
    CMP.w !BattleCF_GeoAngle
    BEQ .on_course
    DEY
    BNE .turn_down_loop
    BRA .heading
.on_course:
    INC.w !Battle_ActorOnCourse,X
.heading:
    STA.w !Battle_ActorHeading,X
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    LDX.b !BattleCF_Actor
    STA.w !Battler_Facing,X
    LDA.w !Battle_ActorHeading,X
    JSR Battle_SinLookupCF
    STA.b !BattleCF_SinPart
    LDX.b !BattleCF_Actor
    CLC
    LDA.w !Battle_ActorHeading,X
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookupCF
    STA.b !BattleCF_CosPart
    LDX.b !BattleCF_Actor
    CLC
    LDA.w !Battler_ScreenY,X
    ADC.b !BattleCF_SinPart
    STA.w !Battler_ScreenY,X
    CLC
    LDA.w !Battler_ScreenX,X
    ADC.b !BattleCF_CosPart
    STA.w !Battler_ScreenX,X
    RTS

; --- The object threads' movers (BattleCF_ObjMoverTable) ---
; They move !Battle_ActObjX/Y (words; the movers write the low byte and
; most zero the high byte) with the objects' part of the actor arrays;
; !BattleCF_Actor is the object thread (0-7).

; $CF:F4B2 — BattleCF_ObjMoveStraight (81 bytes, $F4B2–$F502)
; Object kind 0: BattleCF_MoveStraight for an object: the offset steps,
; !Battle_ActObjX/Y = start + the offsets' high bytes (high bytes 0),
; !Battle_ActObjMoveDone set when the steps run out.
; Callers note: BattleCF_ObjMoverTable entry 0 (JSR (table,X) in BattleCF_RunMovers).
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleCF_Actor/2 set
; Exit:  M=1, X=0, DP=0, DB=$7E; X = the thread; A, Y clobbered
; No calls.
org $CFF4B2
BattleCF_ObjMoveStraight:
    LDX.b !BattleCF_Actor
    LDA.w !Battle_ActObjMoveDone,X
    BNE .done
    LDA.w !Battle_ActorMoveSteps+!Battle_NumSlots,X
    BEQ .end
    LDX.b !BattleCF_Actor2
    REP #$21
    LDA.w !Battle_ActorStepX+(2*!Battle_NumSlots),X
    ADC.w !Battle_ActorOfsX+(2*!Battle_NumSlots),X
    STA.w !Battle_ActorOfsX+(2*!Battle_NumSlots),X
    CLC
    LDA.w !Battle_ActorStepY+(2*!Battle_NumSlots),X
    ADC.w !Battle_ActorOfsY+(2*!Battle_NumSlots),X
    STA.w !Battle_ActorOfsY+(2*!Battle_NumSlots),X
    TDC
    SEP #$20
    LDX.b !BattleCF_Actor
    LDY.b !BattleCF_Actor2
    CLC
    LDA.w !Battle_ActorOfsX+(2*!Battle_NumSlots)+1,Y
    ADC.w !Battle_ActorFromX+!Battle_NumSlots,X
    STA.w !Battle_ActObjX,Y
    TDC
    STA.w !Battle_ActObjX+1,Y
    CLC
    LDA.w !Battle_ActorOfsY+(2*!Battle_NumSlots)+1,Y
    ADC.w !Battle_ActorFromY+!Battle_NumSlots,X
    STA.w !Battle_ActObjY,Y
    TDC
    STA.w !Battle_ActObjY+1,Y
    DEC.w !Battle_ActorMoveSteps+!Battle_NumSlots,X
    BNE .done
.end:
    LDA.b #$01
    STA.w !Battle_ActObjMoveDone,X
.done:
    RTS

; $CF:F503 — BattleCF_ObjMoveArc (284 bytes, $F503–$F61E)
; Object kind 1: BattleCF_MoveArc for an object. The height goes into the
; object's y instead of a display offset: !Battle_ActObjY = start y + the
; offset's high byte - h (+ h with the object's !Battle_ActorArcDown
; entry), doubled when its !Battle_ActorArcMode entry is 0; high bytes 0.
; Callers note: BattleCF_ObjMoverTable entry 1.
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleCF_Actor/2/4 set
; Exit:  M=1, X=0, DP=0, DB=$7E; X = the thread; A, Y clobbered; DP $04
;        and $CC-$CD written
; No calls.
org $CFF503
BattleCF_ObjMoveArc:
    LDX.b !BattleCF_Actor
    LDA.w !Battle_ActObjMoveDone,X
    BEQ .moving
    JMP .done
.moving:
    LDA.w !Battle_ActorArcSteps+!Battle_NumSlots,X
    BNE .step
    JMP .end
.step:
    LDX.b !BattleCF_Actor2
    REP #$21
    LDA.w !Battle_ActorStepX+(2*!Battle_NumSlots),X
    ADC.w !Battle_ActorOfsX+(2*!Battle_NumSlots),X
    STA.w !Battle_ActorOfsX+(2*!Battle_NumSlots),X
    CLC
    LDA.w !Battle_ActorStepY+(2*!Battle_NumSlots),X
    ADC.w !Battle_ActorOfsY+(2*!Battle_NumSlots),X
    STA.w !Battle_ActorOfsY+(2*!Battle_NumSlots),X
    TDC
    SEP #$20
    LDX.b !BattleCF_Actor
    LDA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,X
    TAX
    STX.b !BattleCF_ArcLoop
    REP #$20
    LDX.b !BattleCF_Actor2
    LDY.b !BattleCF_Actor4
.arc_loop:
    LDA.w !Battle_ActorArcFalling+(2*!Battle_NumSlots),X
    BNE .falling_speed
    SEC
    LDA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),Y
    SBC.w !Battle_ActorArcAccel+(2*!Battle_NumSlots),X
    STA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),Y
    BCS .height
    TDC
    STA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),Y
    STA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots)+2,Y
    INC A
    STA.w !Battle_ActorArcFalling+(2*!Battle_NumSlots),X
    BRA .height
.falling_speed:
    CLC
    LDA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),Y
    ADC.w !Battle_ActorArcAccel+(2*!Battle_NumSlots),X
    STA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),Y
    BCC .height
    LDA.w !Battle_ActorArcSpeed0+(2*!Battle_NumSlots),X
    STA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),Y
    TDC
    STA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots)+2,Y
    STA.w !Battle_ActorArcFalling+(2*!Battle_NumSlots),X
.height:
    LDA.w !Battle_ActorArcFalling+(2*!Battle_NumSlots),X
    BNE .falling_height
    CLC
    LDA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),Y
    ADC.w !Battle_ActorArcHeight+(4*!Battle_NumSlots),Y
    STA.w !Battle_ActorArcHeight+(4*!Battle_NumSlots),Y
    LDA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots)+2,Y
    ADC.w !Battle_ActorArcHeight+(4*!Battle_NumSlots)+2,Y
    STA.w !Battle_ActorArcHeight+(4*!Battle_NumSlots)+2,Y
    BRA .arc_next
.falling_height:
    SEC
    LDA.w !Battle_ActorArcHeight+(4*!Battle_NumSlots),Y
    SBC.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),Y
    STA.w !Battle_ActorArcHeight+(4*!Battle_NumSlots),Y
    LDA.w !Battle_ActorArcHeight+(4*!Battle_NumSlots)+2,Y
    SBC.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots)+2,Y
    STA.w !Battle_ActorArcHeight+(4*!Battle_NumSlots)+2,Y
.arc_next:
    DEC.b !BattleCF_ArcLoop
    BNE .arc_loop
    LDA.w !Battle_ActorArcHeight+(4*!Battle_NumSlots)+2,Y
    STA.b !BattleCF_SinProduct          ; the height in pixels (scratch)
    TDC
    SEP #$20
    LDX.b !BattleCF_Actor
    LDY.b !BattleCF_Actor2
    CLC
    LDA.w !Battle_ActorOfsX+(2*!Battle_NumSlots)+1,Y
    ADC.w !Battle_ActorFromX+!Battle_NumSlots,X
    STA.w !Battle_ActObjX,Y
    TDC
    STA.w !Battle_ActObjX+1,Y
    LDA.w !Battle_ActorArcDown+!Battle_NumSlots,X
    BNE .down
    LDA.w !Battle_ActorArcMode+(2*!Battle_NumSlots),Y
    BEQ .up_double
    CLC
    LDA.w !Battle_ActorOfsY+(2*!Battle_NumSlots)+1,Y
    ADC.w !Battle_ActorFromY+!Battle_NumSlots,X
    SEC
    SBC.b !BattleCF_SinProduct
    STA.w !Battle_ActObjY,Y
    BRA .y_hi
.up_double:
    CLC
    LDA.w !Battle_ActorOfsY+(2*!Battle_NumSlots)+1,Y
    ADC.w !Battle_ActorFromY+!Battle_NumSlots,X
    SEC
    SBC.b !BattleCF_SinProduct
    SEC
    SBC.b !BattleCF_SinProduct
    STA.w !Battle_ActObjY,Y
    BRA .y_hi
.down:
    LDA.w !Battle_ActorArcMode+(2*!Battle_NumSlots),Y
    BEQ .down_double
    CLC
    LDA.w !Battle_ActorOfsY+(2*!Battle_NumSlots)+1,Y
    ADC.w !Battle_ActorFromY+!Battle_NumSlots,X
    CLC
    ADC.b !BattleCF_SinProduct
    STA.w !Battle_ActObjY,Y
    BRA .y_hi
.down_double:
    CLC
    LDA.w !Battle_ActorOfsY+(2*!Battle_NumSlots)+1,Y
    ADC.w !Battle_ActorFromY+!Battle_NumSlots,X
    CLC
    ADC.b !BattleCF_SinProduct
    CLC
    ADC.b !BattleCF_SinProduct
    STA.w !Battle_ActObjY,Y
.y_hi:
    TDC
    STA.w !Battle_ActObjY+1,Y
    LDX.b !BattleCF_Actor
    DEC.w !Battle_ActorArcSteps+!Battle_NumSlots,X
    BNE .done
.end:
    LDA.b #$01
    STA.w !Battle_ActObjMoveDone,X
.done:
    RTS

; $CF:F61F — BattleCF_ObjMoveHeading (110 bytes, $F61F–$F68C)
; Object kind 2: BattleCF_MoveHeading for an object (its cell from
; !Battle_ActObjY/X, the distance in !Battle_ActObjUnkA31C, the angle in
; !Battle_ActObjMoveAngle copied to !Battle_ActObjUnkA5B5); the position
; goes to !Battle_ActObjX/Y with high bytes 0.
; Callers note: BattleCF_ObjMoverTable entry 2.
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleCF_Actor/2 set
; Exit:  M=1, X=0, DP=0, DB=$7E; X = the thread when it ends or is done,
;        else thread * 2; Y = thread * 2 (the thread after a step); A
;        clobbered; DP $00-$06, $CC-$CD written when it steps
; Callees: BattleCF_PixelToCell, Battle_SinLookupCF
org $CFF61F
BattleCF_ObjMoveHeading:
    LDX.b !BattleCF_Actor
    LDY.b !BattleCF_Actor2
    LDA.w !Battle_ActObjMoveDone,X
    BNE .done
    LDA.w !Battle_ActObjY,Y
    JSR BattleCF_PixelToCell
    BEQ .end
    CMP.b #!Battle_CellRowBottom
    BEQ .end
    LDA.w !Battle_ActObjX,Y
    JSR BattleCF_PixelToCell
    BEQ .end
    CMP.b #!Battle_CellColRight
    BEQ .end
    DEC.w !Battle_ActorHeadSteps+!Battle_NumSlots,X
    BEQ .end
    CLC
    LDA.w !Battle_ActObjUnkA31C,X
    ADC.w !Battle_ActorMoveSpeed+!Battle_NumSlots,X
    STA.w !Battle_ActObjUnkA31C,X
    STA.b !BattleCF_SinScale
    LDA.w !Battle_ActObjMoveAngle,X
    STA.w !Battle_ActObjUnkA5B5,X
    JSR Battle_SinLookupCF
    STA.b !BattleCF_SinPart
    LDX.b !BattleCF_Actor
    CLC
    LDA.w !Battle_ActObjMoveAngle,X
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookupCF
    STA.b !BattleCF_CosPart
    LDY.b !BattleCF_Actor
    LDX.b !BattleCF_Actor2
    CLC
    LDA.w !Battle_ActorFromY+!Battle_NumSlots,Y
    ADC.b !BattleCF_SinPart
    STA.w !Battle_ActObjY,X
    STZ.w !Battle_ActObjY+1,X
    CLC
    LDA.w !Battle_ActorFromX+!Battle_NumSlots,Y
    ADC.b !BattleCF_CosPart
    STA.w !Battle_ActObjX,X
    STZ.w !Battle_ActObjX+1,X
    BRA .done
.end:
    LDA.b #$01
    STA.w !Battle_ActObjMoveDone,X
.done:
    RTS

; $CF:F68D — BattleCF_ObjMoveCircle (85 bytes, $F68D–$F6E1)
; Object kind 3: unlike the battlers' BattleCF_MoveCircle, it moves the
; object itself: adds the step to its angle and puts !Battle_ActObjX/Y
; (low bytes only) at the centre (!Battle_ActorCircleX/Y) + radius *
; (cos, sin) of the angle; counts the steps down and counts
; !Battle_ActObjMoveDone up at 0.
; Callers note: BattleCF_ObjMoverTable entry 3.
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleCF_Actor/2 set
; Exit:  M=1, X=0, DP=0, DB=$7E; Y = the thread; X = the thread when the
;        steps run out, thread * 2 after another step, unchanged when
;        already done; A clobbered; DP $00-$06, $CC-$CD written when it
;        steps
; Callees: Battle_SinLookupCF
org $CFF68D
BattleCF_ObjMoveCircle:
    LDY.b !BattleCF_Actor
    LDA.w !Battle_ActObjMoveDone,Y
    BNE .done
    LDA.w !Battle_ActorCircleRadius+!Battle_NumSlots,Y
    STA.b !BattleCF_SinScale
    CLC
    LDA.w !Battle_ActorCircleAngle+!Battle_NumSlots,Y
    ADC.w !Battle_ActorCircleStep+!Battle_NumSlots,Y
    STA.w !Battle_ActorCircleAngle+!Battle_NumSlots,Y
    JSR Battle_SinLookupCF
    STA.b !BattleCF_SinPart
    CLC
    LDA.w !Battle_ActorCircleAngle+!Battle_NumSlots,Y
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookupCF
    STA.b !BattleCF_CosPart
    LDX.b !BattleCF_Actor2
    CLC
    LDA.w !Battle_ActorCircleX+!Battle_NumSlots,Y
    ADC.b !BattleCF_CosPart
    STA.w !Battle_ActObjX,X
    CLC
    LDA.w !Battle_ActorCircleY+!Battle_NumSlots,Y
    ADC.b !BattleCF_SinPart
    STA.w !Battle_ActObjY,X
    SEC
    LDA.w !Battle_ActorCircleSteps+(2*!Battle_NumSlots),X
    SBC.b #$01
    STA.w !Battle_ActorCircleSteps+(2*!Battle_NumSlots),X
    LDA.w !Battle_ActorCircleSteps+(2*!Battle_NumSlots)+1,X
    SBC.b #$00
    STA.w !Battle_ActorCircleSteps+(2*!Battle_NumSlots)+1,X
    ORA.w !Battle_ActorCircleSteps+(2*!Battle_NumSlots),X
    BNE .done
    TYX
    INC.w !Battle_ActObjMoveDone,X
.done:
    RTS

; $CF:F6E2 — BattleCF_ObjMoveKind4 (282 bytes, $F6E2–$F7FB)
; Object kind 4: BattleCF_MoveKind4 for an object, with these
; differences: the first test once falling uses a 24-pixel margin
; (!Battle_ObjNearMargin) and no height test (it counts
; !Battle_ActObjMoveDone and the object's !Battle_ActorUnkAB00 entry up);
; the height goes into !Battle_ActObjY: start y + the offset's high byte
; - h when the object's !Battle_ActorArcMode entry is non-zero, - 2h
; when it is 0 (no fall-through quirk here); high bytes 0.
; Callers note: BattleCF_ObjMoverTable entry 4.
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleCF_Actor/2/4 set
; Exit:  M=1, X=0, DP=0, DB=$7E; X = the thread; A, Y clobbered; DP $04
;        and $CC-$D1 written
; Callees: BattleCF_PointsNear
org $CFF6E2
BattleCF_ObjMoveKind4:
    LDY.b !BattleCF_Actor2
    LDA.w !Battle_ActorArcFalling+(2*!Battle_NumSlots),Y
    BEQ .step
    LDX.b !BattleCF_Actor
    LDA.w !Battle_ActObjX,Y
    STA.b !BattleCF_NearX1
    LDA.w !Battle_ActObjY,Y
    STA.b !BattleCF_NearY1
    LDA.w !Battle_ActorToX+!Battle_NumSlots,X
    STA.b !BattleCF_NearX2
    LDA.w !Battle_ActorToY+!Battle_NumSlots,X
    STA.b !BattleCF_NearY2
    LDA.w !Battle_ActorUnkAB00+!Battle_NumSlots,X
    BNE .landed
    LDA.b #!Battle_ObjNearMargin
    STA.b !BattleCF_NearMargin
    JSR BattleCF_PointsNear
    LDA.b !BattleCF_Near
    BEQ .step
    INC.w !Battle_ActObjMoveDone,X
    INC.w !Battle_ActorUnkAB00+!Battle_NumSlots,X
    RTS
.landed:
    LDA.b #$01
    STA.b !BattleCF_NearMargin
    JSR BattleCF_PointsNear
    LDA.b !BattleCF_Near
    BEQ .step
    INC.w !Battle_ActObjMoveDone,X
    RTS
.step:
    LDX.b !BattleCF_Actor2
    REP #$21
    LDA.w !Battle_ActorStepX+(2*!Battle_NumSlots),X
    ADC.w !Battle_ActorOfsX+(2*!Battle_NumSlots),X
    STA.w !Battle_ActorOfsX+(2*!Battle_NumSlots),X
    CLC
    LDA.w !Battle_ActorStepY+(2*!Battle_NumSlots),X
    ADC.w !Battle_ActorOfsY+(2*!Battle_NumSlots),X
    STA.w !Battle_ActorOfsY+(2*!Battle_NumSlots),X
    TDC
    SEP #$20
    LDX.w #!Battle_Kind4ArcSteps
    STX.b !BattleCF_ArcLoop
    REP #$20
    LDX.b !BattleCF_Actor2
    LDY.b !BattleCF_Actor4
.arc_loop:
    LDA.w !Battle_ActorArcFalling+(2*!Battle_NumSlots),X
    BNE .falling_speed
    SEC
    LDA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),Y
    SBC.w !Battle_ActorArcAccel+(2*!Battle_NumSlots),X
    STA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),Y
    BCS .height
    TDC
    STA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),Y
    STA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots)+2,Y
    INC A
    STA.w !Battle_ActorArcFalling+(2*!Battle_NumSlots),X
    PHX
    LDX.b !BattleCF_Actor
    INC.w !Battle_ActObjMoveDone,X      ; the top of the rise
    PLX
    BRA .height
.falling_speed:
    CLC
    LDA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),Y
    ADC.w !Battle_ActorArcAccel+(2*!Battle_NumSlots),X
    STA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),Y
    BCC .height
    LDA.w !Battle_ActorArcSpeed0+(2*!Battle_NumSlots),X
    STA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),Y
    TDC
    STA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots)+2,Y
    STA.w !Battle_ActorArcFalling+(2*!Battle_NumSlots),X
.height:
    LDA.w !Battle_ActorArcFalling+(2*!Battle_NumSlots),X
    BNE .falling_height
    CLC
    LDA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),Y
    ADC.w !Battle_ActorArcHeight+(4*!Battle_NumSlots),Y
    STA.w !Battle_ActorArcHeight+(4*!Battle_NumSlots),Y
    LDA.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots)+2,Y
    ADC.w !Battle_ActorArcHeight+(4*!Battle_NumSlots)+2,Y
    STA.w !Battle_ActorArcHeight+(4*!Battle_NumSlots)+2,Y
    BRA .arc_next
.falling_height:
    SEC
    LDA.w !Battle_ActorArcHeight+(4*!Battle_NumSlots),Y
    SBC.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots),Y
    STA.w !Battle_ActorArcHeight+(4*!Battle_NumSlots),Y
    LDA.w !Battle_ActorArcHeight+(4*!Battle_NumSlots)+2,Y
    SBC.w !Battle_ActorArcSpeed+(4*!Battle_NumSlots)+2,Y
    STA.w !Battle_ActorArcHeight+(4*!Battle_NumSlots)+2,Y
.arc_next:
    DEC.b !BattleCF_ArcLoop
    BNE .arc_loop
    LDA.w !Battle_ActorArcHeight+(4*!Battle_NumSlots)+2,Y
    STA.b !BattleCF_SinProduct          ; the height in pixels (scratch)
    TDC
    SEP #$20
    LDX.b !BattleCF_Actor
    LDY.b !BattleCF_Actor2
    CLC
    LDA.w !Battle_ActorOfsX+(2*!Battle_NumSlots)+1,Y
    ADC.w !Battle_ActorFromX+!Battle_NumSlots,X
    STA.w !Battle_ActObjX,Y
    TDC
    STA.w !Battle_ActObjX+1,Y
    LDA.w !Battle_ActorArcMode+(2*!Battle_NumSlots),Y
    BEQ .double
    CLC
    LDA.w !Battle_ActorOfsY+(2*!Battle_NumSlots)+1,Y
    ADC.w !Battle_ActorFromY+!Battle_NumSlots,X
    SEC
    SBC.b !BattleCF_SinProduct
    STA.w !Battle_ActObjY,Y
    BRA .y_hi
.double:
    CLC
    LDA.w !Battle_ActorOfsY+(2*!Battle_NumSlots)+1,Y
    ADC.w !Battle_ActorFromY+!Battle_NumSlots,X
    SEC
    SBC.b !BattleCF_SinProduct
    SEC
    SBC.b !BattleCF_SinProduct
    STA.w !Battle_ActObjY,Y
.y_hi:
    TDC
    STA.w !Battle_ActObjY+1,Y
    RTS

; $CF:F7FC — BattleCF_ObjMoveOrbit (136 bytes, $F7FC–$F883)
; Object kind 5: the ellipse of BattleCF_MoveEllipse, moving the object
; itself around the centre (!Battle_ActObjX/Y low bytes = centre + radius
; * cos, radius / 2 * sin), and first re-linking it to its battler
; (!Battle_ActObjLinkSlot): the !Battle_ActObjLinks entry thread * 11 +
; slot (the * 11 through Battle_Mul8x16CF) gets bit 7 while the angle is
; below $80 (the lower half of the ellipse, nearer the viewer) and bit 6
; otherwise, its low 6 bits kept; BattleCF_BuildSprites draws bit-7
; objects in front of the battler and bit-6 ones behind it. "Orbit" is
; inferred from that.
; Callers note: BattleCF_ObjMoverTable entry 5.
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleCF_Actor/2 set
; Exit:  M=1, X=0, DP=0, DB=$7E; Y = the thread; A, X clobbered; DP
;        $00-$06, $CC-$CD written when it steps
; Callees: Battle_Mul8x16CF, Battle_SinLookupCF
org $CFF7FC
BattleCF_ObjMoveOrbit:
    LDA.b !BattleCF_Actor
    TAY
    STA.b !BattleCF_SinScale            ; multiplicand: the thread
    LDA.w !Battle_ActObjMoveDone,Y
    BNE .done
    LDA.b #!Battle_NumSlots
    STA.b !BattleCF_SinFactor16
    STZ.b !BattleCF_SinFactor16+1
    JSR Battle_Mul8x16CF                ; thread * 11
    CLC
    LDA.b !BattleCF_SinProduct
    ADC.w !Battle_ActObjLinkSlot,Y
    TAX
    LDA.w !Battle_ActorCircleAngle+!Battle_NumSlots,Y
    CMP.b #!Battle_AngleHalfTurn
    BCS .behind
    LDA.w !Battle_ActObjLinks,X
    AND.b #!Battle_ActObjLinkThreadMask
    ORA.b #!Battle_ActLinkFront
    BRA .link
.behind:
    LDA.w !Battle_ActObjLinks,X
    AND.b #!Battle_ActObjLinkThreadMask
    ORA.b #!Battle_ActLinkBehind
.link:
    STA.w !Battle_ActObjLinks,X
    LDA.w !Battle_ActorCircleRadius+!Battle_NumSlots,Y
    LSR A
    STA.b !BattleCF_SinScale
    CLC
    LDA.w !Battle_ActorCircleAngle+!Battle_NumSlots,Y
    ADC.w !Battle_ActorCircleStep+!Battle_NumSlots,Y
    STA.w !Battle_ActorCircleAngle+!Battle_NumSlots,Y
    JSR Battle_SinLookupCF
    STA.b !BattleCF_SinPart
    LDA.w !Battle_ActorCircleRadius+!Battle_NumSlots,Y
    STA.b !BattleCF_SinScale
    CLC
    LDA.w !Battle_ActorCircleAngle+!Battle_NumSlots,Y
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookupCF
    STA.b !BattleCF_CosPart
    LDX.b !BattleCF_Actor2
    CLC
    LDA.w !Battle_ActorCircleX+!Battle_NumSlots,Y
    ADC.b !BattleCF_CosPart
    STA.w !Battle_ActObjX,X
    CLC
    LDA.w !Battle_ActorCircleY+!Battle_NumSlots,Y
    ADC.b !BattleCF_SinPart
    STA.w !Battle_ActObjY,X
    SEC
    LDA.w !Battle_ActorCircleSteps+(2*!Battle_NumSlots),X
    SBC.b #$01
    STA.w !Battle_ActorCircleSteps+(2*!Battle_NumSlots),X
    LDA.w !Battle_ActorCircleSteps+(2*!Battle_NumSlots)+1,X
    SBC.b #$00
    STA.w !Battle_ActorCircleSteps+(2*!Battle_NumSlots)+1,X
    ORA.w !Battle_ActorCircleSteps+(2*!Battle_NumSlots),X
    BNE .done
    TYX
    INC.w !Battle_ActObjMoveDone,X
.done:
    RTS

; $CF:F884 — BattleCF_ObjMoveCurve (211 bytes, $F884–$F956)
; Object kind 7: BattleCF_MoveCurve for an object. Its x and y are taken
; as 0 when their high byte is negative; the heading is the object's
; !Battle_ActorHeading entry, the facing goes to !Battle_ActObjFacing,
; and the step speed * (sin, cos) is sign-extended and added to the
; 16-bit !Battle_ActObjY / !Battle_ActObjX.
; Callers note: BattleCF_ObjMoverTable entry 7.
; Entry: M=1, X=0, DP=0, DB=$7E; !BattleCF_Actor/2 set
; Exit:  M=1, X=0, DP=0, DB=$7E; X = the thread when it arrives, else
;        thread * 2; A, Y clobbered; DP $00-$06, $CA-$D1 and
;        !BattleCF_GeoOriginX..!BattleCF_GeoAngleIndex written ($CA is
;        !BattleCF_Actor4, no longer needed)
; Callees: BattleCF_PointsNear, Battle_CalcAngleCF, Battle_SinLookupCF
!BattleCF_SinPart16 = !BattleCF_TmpCA   ; 2 B: sign-extended sine part (added to y)
!BattleCF_CosPart16 = !BattleCF_TmpCC   ; 2 B: sign-extended cosine part (added to x)
org $CFF884
BattleCF_ObjMoveCurve:
    LDX.b !BattleCF_Actor
    LDY.b !BattleCF_Actor2
    LDA.w !Battle_ActObjX+1,Y
    BPL .x_ok
    TDC
    BRA .x_set
.x_ok:
    LDA.w !Battle_ActObjX,Y
.x_set:
    STA.b !BattleCF_NearX1
    STA.w !BattleCF_GeoOriginX
    LDA.w !Battle_ActObjY+1,Y
    BPL .y_ok
    TDC
    BRA .y_set
.y_ok:
    LDA.w !Battle_ActObjY,Y
.y_set:
    STA.b !BattleCF_NearY1
    STA.w !BattleCF_GeoOriginY
    LDA.w !Battle_ActorToX+!Battle_NumSlots,X
    STA.b !BattleCF_NearX2
    STA.w !BattleCF_GeoPointX
    LDA.w !Battle_ActorToY+!Battle_NumSlots,X
    STA.b !BattleCF_NearY2
    STA.w !BattleCF_GeoPointY
    LDA.b #!Battle_NearMargin
    STA.b !BattleCF_NearMargin
    JSR BattleCF_PointsNear
    LDA.b !BattleCF_Near
    BEQ .steer
    INC.w !Battle_ActObjMoveDone,X
    RTS
.steer:
    JSR Battle_CalcAngleCF
    LDX.b !BattleCF_Actor
    LDA.w !Battle_ActorMoveSpeed+!Battle_NumSlots,X
    STA.b !BattleCF_SinScale
    TAY                                 ; Y = turn units left
    LDA.w !Battle_ActorOnCourse+!Battle_NumSlots,X
    BEQ .turn
    LDA.w !BattleCF_GeoAngle
    BRA .heading
.turn:
    LDA.w !Battle_ActorHeading+!Battle_NumSlots,X
    CMP.w !BattleCF_GeoAngle
    BEQ .heading
    LDA.w !Battle_ActorTurnDir+!Battle_NumSlots,X
    BNE .turn_down
    LDA.w !Battle_ActorHeading+!Battle_NumSlots,X
.turn_up:
    CLC
    ADC.b #$01
    CMP.w !BattleCF_GeoAngle
    BEQ .on_course
    DEY
    BNE .turn_up
    BRA .heading
.turn_down:
    LDA.w !Battle_ActorHeading+!Battle_NumSlots,X
.turn_down_loop:
    SEC
    SBC.b #$01
    CMP.w !BattleCF_GeoAngle
    BEQ .on_course
    DEY
    BNE .turn_down_loop
    BRA .heading
.on_course:
    INC.w !Battle_ActorOnCourse+!Battle_NumSlots,X
.heading:
    STA.w !Battle_ActorHeading+!Battle_NumSlots,X
    TAX
    LDA.l !BattleRom_FacingByAngle,X
    LDX.b !BattleCF_Actor
    STA.w !Battle_ActObjFacing,X
    STZ.b !BattleCF_SinPart16+1
    STZ.b !BattleCF_CosPart16+1
    LDA.w !Battle_ActorHeading+!Battle_NumSlots,X
    JSR Battle_SinLookupCF
    STA.b !BattleCF_SinPart16
    BPL .sin_pos
    LDA.b #!Battle_SignFill
    STA.b !BattleCF_SinPart16+1
.sin_pos:
    LDX.b !BattleCF_Actor
    CLC
    LDA.w !Battle_ActorHeading+!Battle_NumSlots,X
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookupCF
    STA.b !BattleCF_CosPart16
    BPL .cos_pos
    LDA.b #!Battle_SignFill
    STA.b !BattleCF_CosPart16+1
.cos_pos:
    LDX.b !BattleCF_Actor2
    REP #$21
    LDA.w !Battle_ActObjY,X
    ADC.b !BattleCF_SinPart16
    STA.w !Battle_ActObjY,X
    CLC
    LDA.w !Battle_ActObjX,X
    ADC.b !BattleCF_CosPart16
    STA.w !Battle_ActObjX,X
    TDC
    SEP #$20
    RTS

; ============================================================
; Mover helpers and the enemy stepper ($CF:F957–$CF:F9FA)
; ============================================================

; $CF:F957 — BattleCF_PointsNear (33 bytes, $F957–$F977)
; Sets !BattleCF_Near to 1 when the points (!BattleCF_NearX1, NearY1) and
; (!BattleCF_NearX2, NearY2) are less than !BattleCF_NearMargin apart in x
; and in y, else to 0.
; Quirk: each difference is taken as a signed byte and negated when
; negative, so a difference of 128 or more counts as 256 less it (points
; 241-255 pixels apart in an axis count as within 16).
; Callers (6 JSR sites): BattleCF_MoveKind4 ($CF:F263, $CF:F27C), BattleCF_MoveCurve ($CF:F42B),
;   BattleCF_ObjMoveKind4 ($CF:F708, $CF:F71A) and BattleCF_ObjMoveCurve ($CF:F8BC).
; Entry: M=1, X=0, DP=0, DB any; the five inputs set
; Exit:  M=1, X=0; X, Y unchanged; A = the last |difference| taken;
;        !BattleCF_Near = 1 or 0
; No calls.
org $CFF957
BattleCF_PointsNear:
    STZ.b !BattleCF_Near
    SEC
    LDA.b !BattleCF_NearX1
    SBC.b !BattleCF_NearX2
    BPL .x_abs
    EOR.b #!Battle_SignFill
    INC A
.x_abs:
    CMP.b !BattleCF_NearMargin
    BCS .done
    SEC
    LDA.b !BattleCF_NearY1
    SBC.b !BattleCF_NearY2
    BPL .y_abs
    EOR.b #!Battle_SignFill
    INC A
.y_abs:
    CMP.b !BattleCF_NearMargin
    BCS .done
    INC.b !BattleCF_Near
.done:
    RTS

; $CF:F978 — BattleCF_StepEnemies (91 bytes, $F978–$F9D2)
; The enemy stepper of the enemy movers (run while no action runs): for
; enemies 7 down to 0 with !Enemy_Stepping set, every
; !Battler_DefMoveDelay frames (!Enemy_StepTimer counts them) adds the
; enemy's !Battler_DefMoveSpeed to its distance (!Battler_PathStep entry)
; and puts it at !Enemy_StepStartX/Y + distance * (cos, sin) of
; !Enemy_MoveAngle. When the distance reaches !Battle_MoveStepLen (8) the
; step ends: !Enemy_Stepping and the distance are zeroed, and the enemy
; is still placed at the full 8 pixels (the scale was stored before).
; Quirk: only a distance of exactly 8 ends the step; a speed that does
; not divide 8 runs past it (the byte wraps at 256).
; Callers (1 JMP site): BattleCF_RunMovers ($CF:EFBA).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X clobbered; Y unchanged; DP $00-$06
;        and $C6-$C9 written
; Callees: Battle_SinLookupCF
!BattleCF_Enemy = !BattleCF_TmpC6       ; 2 B: enemy 0-7
!BattleCF_StepDY = !BattleCF_TmpC8      ; 1 B: distance * sin
!BattleCF_StepDX = !BattleCF_TmpC8+1    ; 1 B: distance * cos
org $CFF978
BattleCF_StepEnemies:
    LDX.w #!Battle_NumEnemies-1
    STX.b !BattleCF_Enemy
.enemy:
    LDX.b !BattleCF_Enemy
    LDA.w !Enemy_Stepping,X
    BEQ .next
    DEC.w !Enemy_StepTimer,X
    BNE .next
    LDA.w !Battler_DefMoveDelay+!Battle_FirstEnemySlot,X
    STA.w !Enemy_StepTimer,X
    CLC
    LDA.w !Battler_PathStep+!Battle_FirstEnemySlot,X
    ADC.w !Battler_DefMoveSpeed+!Battle_FirstEnemySlot,X
    STA.w !Battler_PathStep+!Battle_FirstEnemySlot,X
    STA.b !BattleCF_SinScale
    CMP.b #!Battle_MoveStepLen
    BNE .place
    STZ.w !Enemy_Stepping,X
    STZ.w !Battler_PathStep+!Battle_FirstEnemySlot,X
.place:
    LDA.w !Enemy_MoveAngle,X
    JSR Battle_SinLookupCF
    STA.b !BattleCF_StepDY
    LDX.b !BattleCF_Enemy
    CLC
    LDA.w !Enemy_MoveAngle,X
    ADC.b #!Battle_AngleQuarter
    JSR Battle_SinLookupCF
    STA.b !BattleCF_StepDX
    LDX.b !BattleCF_Enemy
    CLC
    LDA.w !Enemy_StepStartY,X
    ADC.b !BattleCF_StepDY
    STA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    CLC
    LDA.w !Enemy_StepStartX,X
    ADC.b !BattleCF_StepDX
    STA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
.next:
    DEC.b !BattleCF_Enemy
    BPL .enemy
    RTS

; $CF:F9D3 — BattleCF_PlaceEnemyParts (36 bytes, $F9D3–$F9F6)
; Keeps the enemies at fixed offsets from one of them: for each present
; enemy, !Battler_ScreenX/Y = the screen position of enemy
; !Battle_PartsAnchor + its !Enemy_PartOfsX/Y (8-bit adds; the anchor
; itself too). Run by BattleCF_FrameUpdate while !Battle_EnemyPartsOn is
; set; an enemy made of several parts, probably (not traced).
; Callers (1 JSR site): BattleCF_FrameUpdate ($CF:E761).
; Entry: M=1, X=0, DP any, DB=$7E
; Exit:  M=1, X=0; A clobbered; X = $FFFF; Y = !Battle_PartsAnchor
; No calls.
org $CFF9D3
BattleCF_PlaceEnemyParts:
    LDA.w !Battle_PartsAnchor
    TAY
    LDX.w #!Battle_NumEnemies-1
.enemy:
    LDA.w !Battler_Present+!Battle_FirstEnemySlot,X
    BEQ .next
    CLC
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,Y
    ADC.w !Enemy_PartOfsX,X
    STA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    CLC
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,Y
    ADC.w !Enemy_PartOfsY,X
    STA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
.next:
    DEX
    BPL .enemy
    RTS

; $CF:F9F7 — BankCF_DeadShift3 (4 bytes, $F9F7–$F9FA)
; Four bytes between BattleCF_PlaceEnemyParts and Battle_SinLookupCF that
; decode as LSR A three times and RTS (A / 8). No reference to $CF:F9F7
; was found (tools/xref.py: none), so it is probably never run: a
; leftover like the LSR-four-times helpers BattleCF_PixelToCell and
; BattleCF_PixelToTile (inferred).
; Entry: (as code) M=1 or 0, X any, DP any, DB any; never reached as far as
;        known
; Exit:  (as code) A shifted right by 3; X, Y unchanged
; No calls.
BankCF_DeadShift3:
    LSR A
    LSR A
    LSR A
    RTS

; ============================================================
; Battle Math ($CF:F9FB–$CF:FAE1)
; ============================================================

; $CF:F9FB — Battle_SinLookupCF (72 bytes, $F9FB–$FA42)
; Bank $CF's own scaled sine: returns (sin(A) × !BattleCF_SinScale) >> 8
; in A. It is Battle_SinLookup ($C1:01F9) with Battle_Mul8x16 ($C1:00A7)
; written inline after it (a JSR cannot leave the bank), and with its
; own direct-page slots: the scale at $00 instead of $AE, the factor and
; product at $02-$06 instead of $A5-$AB, and no MulMirror copies. The
; first 24 bytes (through the negate) are byte-identical to
; Battle_SinLookup's. !BattleRom_SineTable holds |sin|
; for 1024 steps per turn; angle × 4 picks every fourth entry, negated for
; the second half turn.
; Callers note: the movers call it in pairs, with an angle and then
;   angle + $40 (the cosine), and add the two results to a y and an x: a
;   point at that distance along the angle.
; Sub-entry: Battle_Mul8x16CF ($CF:FA17), the inline multiply on its own:
;   !BattleCF_SinScale (8-bit) x !BattleCF_SinFactor16 (16-bit) -> the
;   24-bit !BattleCF_SinProduct, A = product >> 8; same Entry/Exit as
;   below without the angle (BattleCF_ObjMoveOrbit uses it for thread x
;   11).
; Callers (20 JSR sites): BattleCF_MoveHeading ($CF:F1CA, $CF:F1D7), BattleCF_MoveCircle ($CF:F20E,
;   $CF:F21A), BattleCF_MoveEllipse ($CF:F36B, $CF:F37C), BattleCF_ShakeStep ($CF:F3F2, $CF:F3FE),
;   BattleCF_MoveCurve ($CF:F48B, $CF:F498), BattleCF_ObjMoveHeading ($CF:F657, $CF:F664),
;   BattleCF_ObjMoveCircle ($CF:F6A3, $CF:F6AE), BattleCF_ObjMoveOrbit ($CF:F840, $CF:F850),
;   BattleCF_ObjMoveCurve ($CF:F920, $CF:F933) and BattleCF_StepEnemies ($CF:F9A8, $CF:F9B5).
; Callers of Battle_Mul8x16CF (1 JSR site): BattleCF_ObjMoveOrbit ($CF:F80C).
; Entry: M=1 (8-bit A), X=0 (16-bit; LDX.w RDMPYL / STX.b move the
;        16-bit first product), DP=0 (assumed, as for the bank $C1 battle
;        code; PHB / TDC / PHA / PLB sets DB to D's low byte, which must be
;        0 for STA.w to reach the multiply registers), DB any (restored);
;        angle in A, scale in !BattleCF_SinScale
; Exit:  M=1, X=0 (P restored by PLP; the SEP #$20 after it is
;        redundant, as in Battle_Mul8x16); A = !BattleCF_SinProduct+1
;        (product >> 8); X = the first partial product; Y and DB
;        unchanged; DP $02-$06 written
; No calls.
org $CFF9FB
Battle_SinLookupCF:
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
    STA.b !BattleCF_SinFactor16 ; signed sine (16-bit store)
    SEP #$20                    ; A → 8-bit
    ; inline Battle_Mul8x16: SinScale × SinFactor16 → 24-bit SinProduct
Battle_Mul8x16CF:                       ; header: see Battle_SinLookupCF
    PHB
    TDC
    PHA
    PLB                         ; DB = 0 (hardware regs reachable with .w)
    LDA.b !BattleCF_SinScale
    STA.w WRMPYA
    LDA.b !BattleCF_SinFactor16
    STA.w WRMPYB                ; first multiply: scale × sine low byte
    PHP
    LDA.b !BattleCF_SinFactor16+1
    STZ.b !BattleCF_SinProduct+2
    LDX.w RDMPYL                ; first 16-bit partial product
    STA.w WRMPYB                ; second multiply: scale × sine high byte
    STX.b !BattleCF_SinProduct
    REP #$21                    ; A → 16-bit, C=0 for the ADC
    LDA.b !BattleCF_SinProduct+1
    ADC.w RDMPYL                ; add the second partial product, shifted up 8 bits
    STA.b !BattleCF_SinProduct+1
    TDC
    PLP
    SEP #$20                    ; A → 8-bit
    PLB
    LDA.b !BattleCF_SinProduct+1 ; return product >> 8
    RTS

; $CF:FA43 — Battle_CalcAngleCF (154 bytes, $FA43–$FADC)
; Bank $CF's copy of Battle_CalcAngle ($C1:0222), working on WRAM
; instead of the direct page: the angle (256 units per turn) between
; !BattleCF_GeoOriginX/Y and !BattleCF_GeoPointX/Y, from dx = Origin -
; Point and dy likewise: the base angle from !BattleRom_AngleTable at
; (|dy| & ~7) * 4 + (|dx| >> 3), placed in its quadrant by the signs
; ($80 + base, $80 - base, 0 - base, or base when both are negative).
; Used by the curving movers with the actor as the origin.
; Quirk: !BattleCF_GeoAngleIndex is stored 16-bit at $AC59, so its high
; byte also lands on $AC5A, !Battle_HitNumActive: non-zero whenever |dy|
; is 64 or more, which would start BattleCF_BounceHitNumbers (as in the
; original; whether a curving move ever runs with numbers out is not
; traced).
; Quirk: as in Battle_CalcAngle, the index is doubled into X and then X is
; loaded again with the plain index (the doubling is dead).
; Callers (2 JSR sites): BattleCF_MoveCurve ($CF:F436) and BattleCF_ObjMoveCurve ($CF:F8C7).
; Entry: M=1 (8-bit A), X=0, DP=0 (TDC as zero), DB=$7E (the variables are
;        .w); the four inputs set
; Exit:  M=1, X=0; angle in A and !BattleCF_GeoAngle; X = the table index;
;        Y unchanged; !BattleCF_GeoDeltaX..!BattleCF_GeoAngleIndex and
;        !Battle_HitNumActive written
; No calls.
org $CFFA43
Battle_CalcAngleCF:
    SEC
    LDA.w !BattleCF_GeoOriginX
    SBC.w !BattleCF_GeoPointX
    STA.w !BattleCF_GeoDeltaX
    LDA.b #$00
    SBC.b #$00                          ; borrow → high byte (0 or $FF)
    STA.w !BattleCF_GeoDeltaX+1
    SEC
    LDA.w !BattleCF_GeoOriginY
    SBC.w !BattleCF_GeoPointY
    STA.w !BattleCF_GeoDeltaY
    LDA.b #$00
    SBC.b #$00
    STA.w !BattleCF_GeoDeltaY+1
    LDA.w !BattleCF_GeoDeltaX
    EOR.w !BattleCF_GeoDeltaX+1
    SEC
    SBC.w !BattleCF_GeoDeltaX+1         ; |dx|
    STA.w !BattleCF_GeoAbsDeltaX
    STZ.w !BattleCF_GeoAbsDeltaX+1
    LDA.w !BattleCF_GeoDeltaY
    EOR.w !BattleCF_GeoDeltaY+1
    SEC
    SBC.w !BattleCF_GeoDeltaY+1         ; |dy|
    STA.w !BattleCF_GeoAbsDeltaY
    STZ.w !BattleCF_GeoAbsDeltaY+1
    REP #$20
    LDA.w !BattleCF_GeoAbsDeltaX
    LSR A
    LSR A
    LSR A
    STA.w !BattleCF_GeoTmp
    LDA.w !BattleCF_GeoAbsDeltaY
    AND.w #!Battle_GeoRowMask
    ASL A
    ASL A
    CLC
    ADC.w !BattleCF_GeoTmp
    STA.w !BattleCF_GeoAngleIndex       ; (16-bit: also writes $AC5A, see the quirk)
    ASL A                               ; dead: X is loaded again below
    TAX
    TDC
    SEP #$20
    LDX.w !BattleCF_GeoAngleIndex
    LDA.l !BattleRom_AngleTable,X
    STA.w !BattleCF_GeoAngle
    LDA.w !BattleCF_GeoDeltaX+1
    BMI .dx_negative
    LDA.w !BattleCF_GeoDeltaY+1
    BMI .dy_negative
    CLC
    LDA.b #!Battle_AngleHalfTurn
    ADC.w !BattleCF_GeoAngle
    STA.w !BattleCF_GeoAngle
    RTS
.dy_negative:
    SEC
    LDA.b #!Battle_AngleHalfTurn
    SBC.w !BattleCF_GeoAngle
    STA.w !BattleCF_GeoAngle
    RTS
.dx_negative:
    LDA.w !BattleCF_GeoDeltaY+1
    BMI .both_negative
    TDC
    SEC
    SBC.w !BattleCF_GeoAngle
    STA.w !BattleCF_GeoAngle
.both_negative:
    LDA.w !BattleCF_GeoAngle
    RTS

; $CF:FADD — BattleCF_PixelToCell (5 bytes, $FADD–$FAE1)
; A / 16: a screen coordinate to its 16-pixel cell (the !Battle_CellMap
; grid); the heading movers test the result for the edge cells.
; Callers (4 JSR sites): BattleCF_MoveHeading ($CF:F19E, $CF:F1AA) and BattleCF_ObjMoveHeading
;   ($CF:F62B, $CF:F637).
; Entry: M=1 (8-bit A), X any, DP any, DB any; A = pixel coordinate
; Exit:  M=1; A = cell (0-15), Z set for cell 0; X, Y unchanged
; No calls.
org $CFFADD
BattleCF_PixelToCell:
    LSR A
    LSR A
    LSR A
    LSR A
    RTS

; ============================================================
; Items, battle entry and exit, VRAM queue ($CF:FAE2–$CF:FDAC)
; ============================================================

; $CF:FAE2 — Battle_MergePendingEntries1580 (131 bytes, $FAE2–$FB64)
; For the highest PC slot (2, 1, 0) whose !Pc_UnkA0B5 is set, merges its
; Battle_PcItem record into the battle item list (Item_BattleList, 256
; records of 5 bytes): a record with the same .Id gets one more
; .Quantity (unless that would reach !Battle_ItemQtyLimit: 99 stays),
; else the record is copied to the first empty one (.Id 0). Then clears
; the PC's !Pc_UnkA0B5 and the 5 record bytes, and bumps
; !BattleMenu_ItemRefresh when a PC's item menu is open (!BattleMenu_ActivePc
; not negative and !BattleMenu_Submenu = !BattleMenu_SubmenuItem). One PC
; per call. BattleFD_UnkB655 fills the record (an item a tech left,
; probably: !Battle_UnkB3BF bit 1); "pending" is from the reference name.
; Quirk: an empty record (.Id 0) matches the first empty list entry and
; bumps its quantity. With no empty entry the copy goes to offset $500,
; just past the list ($1A80, Tech_MenuEntry).
; Callers (1 JSL site): BattleMenu_ProcessInput ($C1:1153).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered (Y = $FFFF when no PC
;        is pending); DP $80-$87 written when one is
; Callers note: JSL from BattleMenu_ProcessInput, first thing each frame.
; No calls.
org $CFFAE2
Battle_MergePendingEntries1580:
    LDY.w #!Battle_LastPcSlot
.find:
    LDA.w !Pc_UnkA0B5,Y
    BNE .found
    DEY
    BPL .find
    RTL
.found:
    STY.b !BattleTmp_80                 ; PC slot
    TYA
    ASL A
    ASL A
    ASL A
    TAX
    STX.b !BattleTmp_86                 ; its Battle_PcItem record (8 B per slot)
    LDA.w Battle_PcItem.Id,X
    STA.b !BattleTmp_84
    TDC
    TAY
.same_id:
    LDA.w Item_BattleList.Id,Y
    CMP.b !BattleTmp_84
    BEQ .add_one
    INY
    INY
    INY
    INY
    INY
    CPY.w #!Battle_ItemListBytes
    BNE .same_id
    TDC
    TAY
.empty:
    LDA.w Item_BattleList.Id,Y
    BEQ .copy
    INY
    INY
    INY
    INY
    INY
    CPY.w #!Battle_ItemListBytes
    BNE .empty
.copy:
    LDA.b #!Battle_ItemRecBytes
    STA.b !BattleTmp_82
.copy_byte:
    LDA.w Battle_PcItem.Id,X
    STA.w Item_BattleList.Id,Y
    INX
    INY
    DEC.b !BattleTmp_82
    BNE .copy_byte
    BRA .clear
.add_one:
    CLC
    LDA.w Item_BattleList.Quantity,Y
    ADC.b #$01
    CMP.b #!Battle_ItemQtyLimit
    BCS .clear
    STA.w Item_BattleList.Quantity,Y
.clear:
    LDX.b !BattleTmp_80
    STZ.w !Pc_UnkA0B5,X
    LDX.b !BattleTmp_86
    STZ.w Battle_PcItem.Id,X
    STZ.w Battle_PcItem.TargetMode,X
    STZ.w Battle_PcItem.Flags,X
    STZ.w Battle_PcItem.Quantity,X
    STZ.w Battle_PcItem.PcMask,X
    LDA.w !BattleMenu_ActivePc
    BMI .done
    LDA.w !BattleMenu_Submenu
    CMP.b #!BattleMenu_SubmenuItem
    BNE .done
    INC.w !BattleMenu_ItemRefresh
.done:
    RTL

; $CF:FB65 — BattleCF_EnterBattle (128 bytes, $FB65–$FBE4)
; The battle's start, reached from EngCall_BattleMain ($C1:0000, JSL from
; the field's DefaultHandler) through the JML at $C1:001B. Saves P, DB,
; D, A, X and Y (16-bit) on the stack for BattleCF_ExitBattle, sets D = 0
; and DB = $7E, zeroes !Battle_FramePending, !Battle_Unk9F,
; !Battle_VramQPending and !Battle_Unk98CA, sets !Battle_UnkEC to
; !Battle_Unk2989 bit 1, runs BattleSys_VecCD0000, then clears battle RAM
; ($7E:2D01-$ACEC by words) and DP $80-$EB, sets !Battle_UnkB9 to
; !Battle_UnkB9Init and !Battle_ActAttrBits to !Battle_ActAttrInit |
; (!Battle_Unk2989 bit 4). When !Battle_Flag7F00BA bit 0 is set (copied to
; !Battle_UnkA0A6) each PC's !Battler_Untargetable comes from
; !Battle_Unk7F00B4 by its character id, and !BattleMenu_Lock is set
; unless bit 1 is set too. Then JMLs to BankC1_BattleStartVec ($C1:8000,
; BattleSys_Main), which leaves through BattleCF_ExitBattle.
; Quirk: the clear loop starts at X = $7FEB and goes down by 2, so the
; words start on odd addresses and $7E:2D00 itself is not cleared.
; Callers (1 JML site): BankC1_EnterBattleJml ($C1:001B).
; Entry: M any, X any, DP any, DB any (P, registers, D and DB are saved
;        and set here); the stack holds the JSL's return address
; Exit:  never returns: JML BankC1_BattleStartVec with M=1, X=0, DP=0,
;        DB=$7E and 10 bytes pushed (P, DB, D, A, X, Y)
; Callers note: reached only by the JML at $C1:001B
;   (BankC1_EnterBattleJml).
; Callees: BattleSys_VecCD0000; BankC1_BattleStartVec (JML)
org $CFFB65
BattleCF_EnterBattle:
    PHP
    REP #$30
    PHB
    PHD
    PHA
    PHX
    PHY
    LDA.w #$0000
    SEP #$20
    REP #$10
    LDX.w #$0000
    PHX
    PLD                                 ; D = 0
    LDA.b #!Battle_WramBank
    PHA
    PLB                                 ; DB = $7E
    STZ.b !Battle_FramePending
    STZ.b !Battle_Unk9F
    STZ.b !Battle_VramQPending
    STZ.w !Battle_Unk98CA
    LDA.w !Battle_Unk2989
    AND.b #!Battle_2989Bit1
    LSR A
    STA.b !Battle_UnkEC
    JSL BattleSys_VecCD0000
    REP #$20
    LDX.w #!Battle_ClearRamLast
.clear_ram:
    STZ.w !Battle_ActFrameBuf,X
    DEX
    DEX
    BPL .clear_ram
    LDX.w #!Battle_ClearDpLast
.clear_dp:
    STZ.b !BattleTmp_80,X
    DEX
    DEX
    BPL .clear_dp
    TDC
    SEP #$20
    LDA.b #!Battle_UnkB9Init
    STA.b !Battle_UnkB9
    LDA.w !Battle_Unk2989
    AND.b #!Battle_2989Bit4
    ORA.b #!Battle_ActAttrInit
    STA.w !Battle_ActAttrBits
    LDA.l !Battle_Flag7F00BA
    AND.b #!Battle_Flag7F00BABit0
    STA.w !Battle_UnkA0A6
    BEQ .start
    LDY.w #!Battle_LastPcSlot
.pc:
    LDA.w !Pc_CharId,Y
    AND.b #!Battle_CharIdMask
    TAX
    LDA.l !Battle_Unk7F00B4,X
    STA.w !Battler_Untargetable,Y
    DEY
    BPL .pc
    LDA.l !Battle_Flag7F00BA
    AND.b #!Battle_Flag7F00BABit1
    EOR.b #!Battle_Flag7F00BABit1
    STA.w !BattleMenu_Lock
.start:
    JML BankC1_BattleStartVec

; $CF:FBE5 — BattleCF_ExitBattle (273 bytes, $FBE5–$FCF5)
; The battle's end, reached through the JML at $C1:001F when
; BattleSys_Main JMPs to BattleSys_ExitVec. In order:
;   - for PC slots 2-0: clears !Battler_FxCycleOn and copies
;     !Battle_PaletteTintCopyLen saved colour bytes (from byte 2) of its
;     palette unit back over the live ones (undoing the status colours);
;   - writes the battlers' positions back for the field engine: for the
;     PCs Battle_FieldPc (screen x and y / 16, x and y & 15, the frame
;     shown), for the eight enemies Battle_FieldObj (the same fields);
;   - keeps each present PC's menu rows in !Battle_MenuMemRow.. by
;     character id: the menu row when !BattleMenu_CfgCursorMemory is set,
;     the tech scroll, row and tech when !BattleMenu_CfgListMemory is
;     set; with the latter also the item list's scroll and row;
;   - with !Battle_UnkE5 cleared and set on alternate frames
;     (BattleCF_WaitFrame), waits until !Battle_UnkA4 is 3 (the vblank
;     graphics steps; see BattleCF_VblankUploads); then clears
;     !Battle_UnkE5, sets OAM high-table byte 0 to $FF (sprites 0-3 off
;     screen and large) and waits one more frame;
;   - gives each of the 7 character records with word 3 at 0 a 1 there
;     (!Battle_CharRecWord3, probably the current HP: so no one leaves
;     the battle at 0);
;   - runs BattleSys_VecCD0006, restores Y, X, A, D, DB and P as
;     BattleCF_EnterBattle saved them and returns (RTL) to the code that
;     called EngCall_BattleMain.
; Callers (1 JML site): BankC1_ExitBattleJml ($C1:001F).
; Entry: M=1, X=0, DP=0 (DP $80, $A4, $E5), DB=$7E (as BattleSys_Main
;        leaves); the stack as BattleCF_EnterBattle left it
; Exit:  A, X, Y, D, DB and P as at the battle's start; RTL to the field
;        code that started the battle
; Callers note: reached only by the JML at $C1:001F
;   (BankC1_ExitBattleJml).
; Callees: BattleCF_PixelToTile, BattleCF_WaitFrame, BattleSys_VecCD0006
org $CFFBE5
BattleCF_ExitBattle:
    LDX.w #!Battle_LastPcSlot
    STX.b !BattleTmp_80
.palette:
    LDX.b !BattleTmp_80
    STZ.w !Battler_FxCycleOn,X
    LDA.w !Battler_Palette,X
    ASL A
    ASL A
    ASL A
    ASL A
    TAY
    LDX.w #!Battle_PaletteTintCopyLen
.palette_byte:
    LDA.w !Battle_PaletteSaved+2,Y
    STA.w !Battle_PaletteLive+2,Y
    INY
    DEX
    BNE .palette_byte
    DEC.b !BattleTmp_80
    BPL .palette
    TDC
    TAX
    TAY
.pc:
    LDA.w !Battler_ScreenX,X
    JSR BattleCF_PixelToTile
    STA.w Battle_FieldPc.TileX,Y
    LDA.w !Battler_ScreenX,X
    AND.b #!Battle_TilePixelMask
    STA.w Battle_FieldPc.SubX,Y
    LDA.w !Battler_ScreenY,X
    JSR BattleCF_PixelToTile
    STA.w Battle_FieldPc.TileY,Y
    LDA.w !Battler_ScreenY,X
    AND.b #!Battle_TilePixelMask
    STA.w Battle_FieldPc.SubY,Y
    LDA.w !Battler_FrameShown,X
    STA.w Battle_FieldPc.Frame,Y
    TYA
    CLC
    ADC.b #!Battle_FieldPcBytes
    TAY
    INX
    CPX.w #!Battle_FirstEnemySlot       ; PC slots 0-2
    BNE .pc
    TDC
    TAX
    TAY
.enemy:
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    JSR BattleCF_PixelToTile
    STA.w Battle_FieldObj.TileX,Y
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    AND.b #!Battle_TilePixelMask
    STA.w Battle_FieldObj.SubX,Y
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    JSR BattleCF_PixelToTile
    STA.w Battle_FieldObj.TileY,Y
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    AND.b #!Battle_TilePixelMask
    STA.w Battle_FieldObj.SubY,Y
    LDA.w !Battler_FrameShown+!Battle_FirstEnemySlot,X
    STA.w Battle_FieldObj.Frame,Y
    TYA
    CLC
    ADC.b #!Battle_FieldObjBytes
    TAY
    INX
    CPX.w #!Battle_NumEnemies
    BNE .enemy
    LDX.w #!Battle_LastPcSlot
.memory:
    LDA.w !Pc_CharId,X
    BMI .memory_next
    ASL A
    ASL A
    TAY                                 ; Y = character id * 4
    LDA.w !BattleMenu_CfgCursorMemory
    BEQ .memory_lists
    LDA.w !Pc_SavedMenuRow,X
    STA.w !Battle_MenuMemRow,Y
.memory_lists:
    LDA.w !BattleMenu_CfgListMemory
    BEQ .memory_next
    LDA.w !Pc_SavedTechScroll,X
    STA.w !Battle_MenuMemTechScroll,Y
    LDA.w !Pc_SavedTechRow,X
    STA.w !Battle_MenuMemTechRow,Y
    LDA.w !Pc_SavedTech,X
    STA.w !Battle_MenuMemTech,Y
.memory_next:
    DEX
    BPL .memory
    LDA.w !BattleMenu_CfgListMemory
    BEQ .gfx_wait
    LDA.w !BattleMenu_ItemScroll
    STA.w !Battle_MenuMemItemScroll
    LDA.w !BattleMenu_ItemRow
    STA.w !Battle_MenuMemItemRow
.gfx_wait:
    STZ.b !Battle_UnkE5
    JSR BattleCF_WaitFrame
    INC.b !Battle_UnkE5
    JSR BattleCF_WaitFrame
    LDA.b !Battle_UnkA4
    CMP.b #!Battle_GfxSteps-1
    BNE .gfx_wait
    STZ.b !Battle_UnkE5
    LDA.b #!Battle_OamHighAllSet
    STA.w !BattleOam_HighTable
    JSR BattleCF_WaitFrame
    REP #$20
    LDY.w #!Battle_LastCharRecOfs
.char:
    TYX
    LDA.l !BattleRom_CharRecOffset,X
    TAX
    LDA.w !Battle_CharRecWord3,X
    BNE .char_next
    INC.w !Battle_CharRecWord3,X
.char_next:
    DEY
    DEY
    BPL .char
    TDC
    SEP #$20
    JSL BattleSys_VecCD0006
    PLY
    PLX
    REP #$30
    PLA
    PLD
    PLB
    PLP
    RTL

; $CF:FCF6 — BattleCF_PixelToTile (5 bytes, $FCF6–$FCFA)
; A / 16: a screen coordinate to the field's 16-pixel tile (the
; Battle_FieldPc / Battle_FieldObj .TileX/.TileY); the same code as
; BattleCF_PixelToCell.
; Callers (4 JSR sites): BattleCF_ExitBattle ($CF:FC0E, $CF:FC1F, $CF:FC44, $CF:FC55).
; Entry: M=1 (8-bit A), X any, DP any, DB any; A = pixel coordinate
; Exit:  M=1; A = tile (0-15); X, Y unchanged
; No calls.
BattleCF_PixelToTile:
    LSR A
    LSR A
    LSR A
    LSR A
    RTS

; $CF:FCFB — BattleCF_WaitFrame (7 bytes, $FCFB–$FD01)
; Waits one frame: counts !Battle_FramePending up and loops until the
; frame update (BattleCF_FrameUpdate) clears it.
; Callers (3 JSR sites): BattleCF_ExitBattle ($CF:FCB7, $CF:FCBC, $CF:FCCC).
; Entry: M=1, X any, DP=0, DB any
; Exit:  M=1; A = 0; X, Y unchanged
; No calls.
BattleCF_WaitFrame:
    INC.b !Battle_FramePending
.wait:
    LDA.b !Battle_FramePending
    BNE .wait
    RTS

; $CF:FD02 — Battle_QueueVramUpload_0CC0 (52 bytes, $FD02–$FD35)
; Describes the upload of the status-bar map (BattleUI_StatusTile(0, 0),
; $00:0CC0, $180 bytes) to VRAM word !Battle_PanelMapVram in the queue
; bytes !Battle_VramQDmap.., and sets !Battle_VramQPending for
; BattleCF_VblankUploads.
; Callers (1 JSL site): BattleMenu_UpdateMainWindow ($C1:0C79).
; Entry: M=1, X=0 (TDC / TAX: X = 0, the queue entry), DP=0, DB=$7E
; Exit:  M=1, X=0; X = 0; A = !Battle_VramQRun; Y unchanged
; No calls.
org $CFFD02
Battle_QueueVramUpload_0CC0:
    TDC
    TAX
    LDA.b #!DMAP_TwoRegs
    STA.w !Battle_VramQDmap,X
    LDA.b #!BBAD_VMDATAL
    STA.w !Battle_VramQBbad,X
    LDA.b #BattleUI_StatusTile(0,0)&$FF
    STA.w !Battle_VramQSrcLo,X
    LDA.b #BattleUI_StatusTile(0,0)>>8
    STA.w !Battle_VramQSrcHi,X
    LDA.b #$00                          ; bank $00 (the low WRAM mirror)
    STA.w !Battle_VramQSrcBank,X
    LDA.b #!BattleMenu_WindowBytes&$FF
    STA.w !Battle_VramQSizeLo,X
    LDA.b #!BattleMenu_WindowBytes>>8
    STA.w !Battle_VramQSizeHi,X
    LDA.b #!Battle_PanelMapVram&$FF
    STA.w !Battle_VramQAddrLo,X
    LDA.b #!Battle_PanelMapVram>>8
    STA.w !Battle_VramQAddrHi,X
    LDA.b #!Battle_VramQRun
    STA.b !Battle_VramQPending
    RTL

; $CF:FD36 — Battle_QueueVramUpload_A6E1 (52 bytes, $FD36–$FD69)
; The same for the tech window map (BattleMenu_TechTile(0, 0),
; $7E:A6E1, $180 bytes) to the same VRAM address.
; Callers (1 JSL site): BattleMenu_DrawTechCursorRow ($C1:0E99).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0; X = 0; A = !Battle_VramQRun; Y unchanged
; No calls.
org $CFFD36
Battle_QueueVramUpload_A6E1:
    TDC
    TAX
    LDA.b #!DMAP_TwoRegs
    STA.w !Battle_VramQDmap,X
    LDA.b #!BBAD_VMDATAL
    STA.w !Battle_VramQBbad,X
    LDA.b #BattleMenu_TechTile(0,0)&$FF
    STA.w !Battle_VramQSrcLo,X
    LDA.b #BattleMenu_TechTile(0,0)>>8
    STA.w !Battle_VramQSrcHi,X
    LDA.b #!Battle_WramBank
    STA.w !Battle_VramQSrcBank,X
    LDA.b #!BattleMenu_WindowBytes&$FF
    STA.w !Battle_VramQSizeLo,X
    LDA.b #!BattleMenu_WindowBytes>>8
    STA.w !Battle_VramQSizeHi,X
    LDA.b #!Battle_PanelMapVram&$FF
    STA.w !Battle_VramQAddrLo,X
    LDA.b #!Battle_PanelMapVram>>8
    STA.w !Battle_VramQAddrHi,X
    LDA.b #!Battle_VramQRun
    STA.b !Battle_VramQPending
    RTL

; $CF:FD6A — Battle_QueueVramUpload_0E80 (52 bytes, $FD6A–$FD9D)
; The same for the item list map (BattleMenu_ItemTile(0, 0), $00:0E80,
; $180 bytes) to the same VRAM address.
; Callers (2 JSL sites): BattleMenu_OpenItemList ($C1:1302) and BattleMenu_UpdateCursorOverlay
;   ($C1:1972).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0; X = 0; A = !Battle_VramQRun; Y unchanged
; No calls.
org $CFFD6A
Battle_QueueVramUpload_0E80:
    TDC
    TAX
    LDA.b #!DMAP_TwoRegs
    STA.w !Battle_VramQDmap,X
    LDA.b #!BBAD_VMDATAL
    STA.w !Battle_VramQBbad,X
    LDA.b #BattleMenu_ItemTile(0,0)&$FF
    STA.w !Battle_VramQSrcLo,X
    LDA.b #BattleMenu_ItemTile(0,0)>>8
    STA.w !Battle_VramQSrcHi,X
    LDA.b #$00                          ; bank $00
    STA.w !Battle_VramQSrcBank,X
    LDA.b #!BattleMenu_WindowBytes&$FF
    STA.w !Battle_VramQSizeLo,X
    LDA.b #!BattleMenu_WindowBytes>>8
    STA.w !Battle_VramQSizeHi,X
    LDA.b #!Battle_PanelMapVram&$FF
    STA.w !Battle_VramQAddrLo,X
    LDA.b #!Battle_PanelMapVram>>8
    STA.w !Battle_VramQAddrHi,X
    LDA.b #!Battle_VramQRun
    STA.b !Battle_VramQPending
    RTL

; $CF:FD9E — BattleFx_SetPtrA2FromTable (15 bytes, $FD9E–$FDAC)
; A = battler slot: stores !BattleRom_StatsOffset[slot] (the slot's
; BattlerStats offset, 2 B per slot) in DP $A2 (!BattleTmp_A2, which
; its callers read as !Battle_PoseStatsOffset and the like) and leaves
; it in X. The name is the reference's and its callers'.
; Callers (3 JSL sites): BattleMenu_UpdateWindows ($C1:0C30), BattleMenu_ConfirmCommand ($C1:1283)
;   and Battle_PoseStep ($C1:36B4).
; Entry: M=1, X=0, DP=0, DB any (the table is read .l); A = slot; A's
;        high byte is shifted in too, so it must be 0 (not checked
;        here)
; Exit:  M=1, X=0; X = !BattleTmp_A2 = the offset; A = 0 (TDC; DP is 0);
;        Y unchanged
; No calls.
org $CFFD9E
BattleFx_SetPtrA2FromTable:
    REP #$20
    ASL A
    TAX
    LDA.l !BattleRom_StatsOffset,X
    TAX
    TDC
    SEP #$20
    STX.b !BattleTmp_A2
    RTL

; ============================================================
; Battle Number Formatting ($CF:FDAD–$CF:FE1F)
; ============================================================

; $CF:FDAD — BattleMsg_FormatNumber4Digits (115 bytes, $FDAD–$FE1F)
; A four-digit, long-call version of BattleMsg_FormatNumberDigits
; ($C1:011F): the same subtract-and-count loops with one more for the
; thousands, and the digits looked up in !BattleRom_DigitTilesB (tiles
; $90-$99) instead of !BattleRom_DigitTiles. Formats the 16-bit value in
; !BattleMsg_NumValue (0-9999; a larger value indexes past the table)
; into Digit1000 / Digit100 / Digit10 / Digit1, all four as digit tiles:
; nothing is blanked here (the caller counts the leading $90 tiles
; itself). NumValue is consumed. Ends in RTL, so bank $C1 can reach it.
; Callers (1 JSL site): BattleAct_OpShowHitNumbers ($C1:5BB9).
; Callers note: JSL from $C1:5BB9 (unmatched; it stores a word from
;   $AD9C,X to NumValue first, then counts the leading $90 tiles in
;   Digit1000, Digit100, Digit10 (stopping at the first other tile) and
;   indexes a 4-byte table at $CC:F5C4 with that count, which looks like
;   the placement of a number drawn with these tiles; not traced).
; Entry: M=0 (16-bit A; set by the caller, so the SBC/ADC immediates
;        carry an explicit .w), X=0 (16-bit), DP=0 (TDC / TAX zeroes the
;        digit counters only because D=0), DB=$7E (NumValue and the digit
;        bytes are absolute WRAM)
; Exit:  M=1 (8-bit A), X=0; X and Y unchanged (PHX/PLX); A = the
;        thousands tile; !BattleMsg_NumValue consumed
; No JSR/JSL calls.
org $CFFDAD
BattleMsg_FormatNumber4Digits:
    PHX
    TDC
    TAX
.thousands_loop:
    SEC
    LDA.w !BattleMsg_NumValue
    SBC.w #!BattleMsg_Thousand  ; subtract 1000
    STA.w !BattleMsg_NumValue
    INX
    BCS .thousands_loop
    CLC
    LDA.w !BattleMsg_NumValue
    ADC.w #!BattleMsg_Thousand  ; restore overshoot
    STA.w !BattleMsg_NumValue
    DEX
    PHX                         ; push thousands digit count
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
    LDA.l !BattleRom_DigitTilesB,X
    STA.w !BattleMsg_Digit1
    PLX                         ; X = tens count
    LDA.l !BattleRom_DigitTilesB,X
    STA.w !BattleMsg_Digit10
    PLX                         ; X = hundreds count
    LDA.l !BattleRom_DigitTilesB,X
    STA.w !BattleMsg_Digit100
    PLX                         ; X = thousands count
    LDA.l !BattleRom_DigitTilesB,X
    STA.w !BattleMsg_Digit1000
    PLX
    RTL
; ============================================================
; Service 6 and the end of the bank ($CF:FE20–$CF:FFFF)
; ============================================================

; $CF:FE20 — BattleCF_RemoveMarkedEnemies (101 bytes, $FE20–$FE84)
; Service 6 (BattleSys_Service6): for enemy slots 10 down to 3 marked in
; !Battle_UnkAEB3 (BattleSys_Main's debug win marks each enemy it
; removes), by path:
;   - !Battler_Unk9FF7 set: only !Battler_Present is cleared (the mark
;     in !Battle_UnkAEB3 stays, !Battler_KoFlag is not counted, the
;     Battle_FieldObj flag is not tested);
;   - else counts !Battler_KoFlag up and clears the mark and the enemy's
;     !Enemy_Stepping; then with !Battler_ActAttr 0 clears
;     !Battler_Present (the flag again not tested);
;   - else, when its Battle_FieldObj record has !Battle_FieldObjKind6Flag
;     set, the enemy stays present (marked as KO);
;   - else copies !Battle_SpecialPalLen colour bytes (from byte 2) of its
;     palette unit into the !Battle_SpecialPalette unit, live and saved,
;     switches the enemy to that palette, runs BattleSys_VecCD0024 with
;     A = the slot (a fade-out, probably; not traced) and clears
;     !Battler_Present.
; So a marked enemy stays present only when !Battler_Unk9FF7 is 0,
; !Battler_ActAttr is non-zero and the record has the flag set.
; Callers (1 JSL site): BattleSys_Service6 ($C1:006D).
; Entry: M=1, X=0, DP=0 (DP $80-$83), DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; X = 2; A, Y clobbered; DP $80 and
;        $82-$83 (the 16-bit STX) written; and what BattleSys_VecCD0024
;        changes (not traced)
; Callees: BattleSys_VecCD0024
org $CFFE20
BattleCF_RemoveMarkedEnemies:
    LDX.w #!Battle_NumSlots-1
.slot:
    LDA.w !Battle_UnkAEB3Base,X
    BEQ .next
    LDA.w !Battler_Unk9FF7,X
    BNE .absent
    INC.w !Battler_KoFlag,X
    STZ.w !Battle_UnkAEB3Base,X
    STZ.w !Enemy_Stepping-!Battle_FirstEnemySlot,X
    LDA.w !Battler_ActAttr,X
    BEQ .absent
    TXA
    SEC
    SBC.b #!Battle_FirstEnemySlot
    ASL A
    ASL A
    STA.b !BattleTmp_80
    ASL A
    CLC
    ADC.b !BattleTmp_80
    TAY                                 ; Y = enemy * 12: its Battle_FieldObj record
    LDA.w Battle_FieldObj.Flags,Y
    AND.b #!Battle_FieldObjKind6Flag
    BNE .next
    LDA.w !Battler_Palette,X
    ASL A
    ASL A
    ASL A
    ASL A
    TAY
    LDA.b #!Battle_SpecialPalette
    STA.w !Battler_Palette,X
    PHX
    STX.b !BattleTmp_82
    TDC
    TAX
    LDA.b #!Battle_SpecialPalLen
    STA.b !BattleTmp_80
.colour:
    LDA.w !Battle_PaletteLive+2,Y
    STA.w !Battle_PaletteLive+(!Battle_SpecialPalette*16)+2,X
    STA.w !Battle_PaletteSaved+(!Battle_SpecialPalette*16)+2,X
    INY
    INX
    DEC.b !BattleTmp_80
    BNE .colour
    LDA.b !BattleTmp_82
    JSL BattleSys_VecCD0024
    PLX
.absent:
    STZ.w !Battler_Present,X
.next:
    DEX
    CPX.w #!Battle_LastPcSlot
    BNE .slot
    RTL

; $CF:FE85 — BankCF_EndFill (376 bytes, $FE85–$FFFC)
; $FF fill after the last routine. No reference found.
BankCF_EndFill:
    db $FF
    fillbyte $FF
    fill $CFFFFD-$CFFE86

; $CF:FFFD — BattleCF_ActForceBytes (3 bytes, $FFFD–$FFFF)
; The three bytes service 4 reads as !BattleRom_ActForceNone ($FFFD),
; !BattleRom_ActForceSecond ($FFFE) and !BattleRom_ActForceAlt ($FFFF):
; non-zero would force !Battle_ActUnkAE9B / !Battle_ActFlags (build
; switches, probably); all 0 in this ROM.
BattleCF_ActForceBytes:
    db $00, $00, $00
