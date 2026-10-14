arch snes.cpu
hirom

; ============================================================
; Bank $CD — battle display, messages and background effects
; File offset 0x0D0000 (bank $CD = ROM offset $D0000)
;
; $CD:0000-$CD:3FE5 is battle-engine code with tables inside it; from
; $CD:4000 on the bank is data (the action scripts and their tables,
; read by bank $C1). Other banks reach the code through the JMP vectors
; at $CD:0000-$CD:0038; inside the bank it calls itself by JSR and, for
; a few routines, by JSL. Banks $CD, $CE and $D1 call each other; the
; bank-$CE/$D1 routines are not matched (stubs in
; asm/include/unmatched_battle.asm).
;
; Unless a header says otherwise the code runs as the rest of the battle
; engine does: M=1, X=0, DP=0, DB=$7E. The exceptions are the NMI parts
; (BattleCD_NmiDispatch and what it runs), entered from the bank-$D1 NMI
; handler with DB=$00.
;
; Matched so far: $CD:0000-$CD:16B4. The next part, from $CD:16B5, is
; the 122-word table that BattleCD_RunFxOp dispatches through and the
; handlers it points to.
; ============================================================

; ============================================================
; Callers (1 JSL site): BattleCF_EnterBattle ($CF:FB8E).
; Callers of BattleSys_VecCD0003 (1 JSL site): BattleSys_SceneSetup ($C1:0034).
; Callers of BattleSys_VecCD0006 (1 JSL site): BattleCF_ExitBattle ($CF:FCE9).
; Callers of BattleSys_FrameTickVec (6 JSL sites): BattleSys_UpkeepTwoFrames ($C1:10A0, $C1:10C0),
;   BattleMenu_RefreshIfDirtyAndTick ($C1:1110), BattleSys_DefeatPose ($C1:354D),
;   BattleSys_VictoryPose ($C1:356D) and Battle_RunPcPose ($C1:3689).
; Callers of BattleSys_VecCD000C (1 JSL site): BattleSys_SceneSetup ($C1:0038).
; Callers of BattleSys_VecCD0012 (1 JSL site): BattleSys_SceneSetup ($C1:003C).
; Callers of BattleAnim_LoadGfx4Vec (1 JSL site): BattleAct_LoadCommon ($C1:4836).
; Callers of BattleAnim_UnkVecCD0018 (1 JSL site): BattleAct_LoadCommon ($C1:4857).
; Callers of BattleAct_UnkVecCD001B (1 JSL site): BattleAct_OpRunVecCD001B ($C1:6230).
; Callers of BattleSys_UnkVecCD0021 (12 JSL sites): BattleSys_Main ($C1:8203), BattleSys_UpdateKo
;   ($C1:B386), BattleSys_UnkB967 ($C1:BC30, $C1:BC46) and BattleFD_UnkAD17 ($FD:AD2E, $FD:AD4B,
;   $FD:AD63, $FD:AD7C, $FD:ADAE, $FD:ADF4, $FD:AE20, $FD:AE3F).
; Callers of BattleSys_VecCD0024 (1 JSL site): BattleCF_RemoveMarkedEnemies ($CF:FE76).
; Callers of BattleMsg_ShowFromTableCC3A09Vec (3 JSL sites): BattleMenu_DrawTechCursorRow ($C1:0E95)
;   and BattleSys_UpkeepTwoFrames ($C1:1093, $C1:1099).
; Callers of BattleAnim_LoadGfx2Vec (1 JSL site): BattleAct_LoadCommon ($C1:483D).
; Callers of BattleMsg_ShowMsg0BIfKeyChangedVec (2 JSL sites): BattleMenu_ChooseAttack ($C1:129E)
;   and BattleMenu_UpdateCursorOverlay ($C1:1A47).
; Callers of BattleMsg_UnkVecCD0030 (1 JSL site): BattleMenu_UpdateCursorOverlay ($C1:1A16).
; Callers of BattleMsg_UnkVecCD0033 (12 JSL sites): BattleAi_RunTech ($C1:9B35), BattleAi_RunKoSelf
;   ($C1:9D0E), BattleAi_RunSetStatByte ($C1:9D68), BattleAi_RunAddStatByte ($C1:9DC4),
;   BattleAi_RunSetFlags ($C1:9E58), BattleAi_RunMessage ($C1:9E6E), BattleAi_RunRestoreEnemies
;   ($C1:9F50), BattleAi_RunSetStatBytes ($C1:9FC8), BattleAi_RunSetStatsTech ($C1:A13D),
;   BattleAi_RunAddStatBytes ($C1:A201), BattleAi_RunAddStatsTech ($C1:A385) and
;   BattleAi_RunRestoreAndSetStats ($C1:A3C7).
; Callers of BattleSys_IdleVecCD0036 (1 JSL site): BattleSys_PumpFrames ($C1:0080).
; Entry vectors ($CD:0000–$CD:0038)
; ============================================================

; $CD:0000 — BattleSys_VecCD0000 (57 bytes, $0000–$0038)
; The bank's entry block: 19 three-byte JMPs, all but two ($000F and
; $001E, see the Callers note) reached by JSL from other banks (their
; targets end in RTL). The names are the ones the callers already use.
; By entry:
;   - $0000 BattleSys_VecCD0000 → BattleCD_EnterBattle (JSL from
;     BattleCF_EnterBattle, before it clears battle RAM);
;   - $0003 BattleSys_VecCD0003 → BattleCD_SetNmiMode1
;     (BattleSys_SceneSetup);
;   - $0006 BattleSys_VecCD0006 → BattleCD_ExitBattle
;     (BattleCF_ExitBattle);
;   - $0009 BattleSys_FrameTickVec → BattleCD_FrameTick (the battle
;     menu's per-frame tick and many more);
;   - $000C BattleSys_VecCD000C → BattleCD_StartOpenWipe
;     (BattleSys_SceneSetup);
;   - $000F BattleSys_VecCD000F → BattleCD_StartCloseWipe (no caller
;     found through the vector; BattleCD_ExitBattle JSLs the routine
;     itself);
;   - $0012 BattleSys_VecCD0012 → BattleCD_WipeRunning
;     (BattleSys_SceneSetup, while it returns Z clear);
;   - $0015 BattleAnim_LoadGfx4Vec → $CD:1323 BattleCD_LoadFxGfx4;
;   - $0018 BattleAnim_UnkVecCD0018 → BattleCD_StartLayerFx;
;   - $001B BattleAct_UnkVecCD001B → BattleCD_ActOp80 (action opcode
;     $80);
;   - $001E BattleSys_VecCD001E → BattleCD_ShowMessageTimed (no caller
;     found);
;   - $0021 BattleSys_UnkVecCD0021 → BattleCD_ShowMessage;
;   - $0024 BattleSys_VecCD0024 → BattleCD_EnemyDissolve
;     (BattleCF_RemoveMarkedEnemies);
;   - $0027 BattleMsg_ShowFromTableCC3A09Vec → BattleCD_ShowTechInfo;
;   - $002A BattleAnim_LoadGfx2Vec → BattleCD_LoadFxGfx2;
;   - $002D BattleMsg_ShowMsg0BIfKeyChangedVec → BattleCD_ShowTargetInfo;
;   - $0030 BattleMsg_UnkVecCD0030 → BattleCD_ShowEnemyInfo;
;   - $0033 BattleMsg_UnkVecCD0033 → BattleCD_ShowScriptMessage;
;   - $0036 BattleSys_IdleVecCD0036 → BattleCD_IdleTick
;     (BattleSys_PumpFrames).
; None of the JMPs touches a register or flag.
; Callers note: the JSL sites are listed in the generated blocks; the
;   vectors at $000F and $001E have none.
; Entry: M any, X any, DP any, DB any (nothing is used here; each target
;        has its own needs)
; Exit:  through the jump target; nothing is changed here
; Sub-entries: BattleSys_VecCD0003, BattleSys_VecCD0006,
;   BattleSys_FrameTickVec, BattleSys_VecCD000C, BattleSys_VecCD000F,
;   BattleSys_VecCD0012, BattleAnim_LoadGfx4Vec, BattleAnim_UnkVecCD0018,
;   BattleAct_UnkVecCD001B, BattleSys_VecCD001E, BattleSys_UnkVecCD0021,
;   BattleSys_VecCD0024, BattleMsg_ShowFromTableCC3A09Vec,
;   BattleAnim_LoadGfx2Vec, BattleMsg_ShowMsg0BIfKeyChangedVec,
;   BattleMsg_UnkVecCD0030, BattleMsg_UnkVecCD0033,
;   BattleSys_IdleVecCD0036.
org $CD0000
BattleSys_VecCD0000:
    JMP BattleCD_EnterBattle
BattleSys_VecCD0003:                    ; header: see BattleSys_VecCD0000
    JMP BattleCD_SetNmiMode1
BattleSys_VecCD0006:                    ; header: see BattleSys_VecCD0000
    JMP BattleCD_ExitBattle
BattleSys_FrameTickVec:                 ; header: see BattleSys_VecCD0000
    JMP BattleCD_FrameTick
BattleSys_VecCD000C:                    ; header: see BattleSys_VecCD0000
    JMP BattleCD_StartOpenWipe
BattleSys_VecCD000F:                    ; header: see BattleSys_VecCD0000
    JMP BattleCD_StartCloseWipe
BattleSys_VecCD0012:                    ; header: see BattleSys_VecCD0000
    JMP BattleCD_WipeRunning
BattleAnim_LoadGfx4Vec:                 ; header: see BattleSys_VecCD0000
    JMP BattleCD_LoadFxGfx4
BattleAnim_UnkVecCD0018:                ; header: see BattleSys_VecCD0000
    JMP BattleCD_StartLayerFx
BattleAct_UnkVecCD001B:                 ; header: see BattleSys_VecCD0000
    JMP BattleCD_ActOp80
BattleSys_VecCD001E:                    ; header: see BattleSys_VecCD0000
    JMP BattleCD_ShowMessageTimed
BattleSys_UnkVecCD0021:                 ; header: see BattleSys_VecCD0000
    JMP BattleCD_ShowMessage
BattleSys_VecCD0024:                    ; header: see BattleSys_VecCD0000
    JMP BattleCD_EnemyDissolve
BattleMsg_ShowFromTableCC3A09Vec:       ; header: see BattleSys_VecCD0000
    JMP BattleCD_ShowTechInfo
BattleAnim_LoadGfx2Vec:                 ; header: see BattleSys_VecCD0000
    JMP BattleCD_LoadFxGfx2
BattleMsg_ShowMsg0BIfKeyChangedVec:     ; header: see BattleSys_VecCD0000
    JMP BattleCD_ShowTargetInfo
BattleMsg_UnkVecCD0030:                 ; header: see BattleSys_VecCD0000
    JMP BattleCD_ShowEnemyInfo
BattleMsg_UnkVecCD0033:                 ; header: see BattleSys_VecCD0000
    JMP BattleCD_ShowScriptMessage
BattleSys_IdleVecCD0036:                ; header: see BattleSys_VecCD0000
    JMP BattleCD_IdleTick

; ============================================================
; Battle entry and the action opcode $80 hook ($CD:0039–$CD:0042)
; ============================================================

; $CD:0039 — BattleCD_EnterBattle (5 bytes, $0039–$003D)
; The bank-$CD step of the battle's start: JSL BattleD1_InitBattle
; ($D1:F1B0, not matched: from its first bytes it sets DB=$7E and DP=0,
; installs JML $D1:E77C / JML $D1:FE97 as the NMI and IRQ trampolines at
; $0500/$0504, runs BattleCD_ScrollStepL and BattleCD_InitHdmaDataL and
; zeroes many of this bank's variables), then RTL.
; Callers (1 JMP site): BattleSys_VecCD0000 ($CD:0000).
; Entry: M=1, X=0 (as BattleCF_EnterBattle leaves them), DP any, DB any
;        (the callee sets DP=0 and DB=$7E itself, from its first bytes)
; Exit:  as BattleD1_InitBattle leaves it (not traced; DP=0 and DB=$7E
;        from its first bytes)
BattleCD_EnterBattle:
    JSL BattleD1_InitBattle
    RTL

; $CD:003E — BattleCD_ActOp80 (5 bytes, $003E–$0042)
; Action opcode $80's long call (BattleAct_OpRunVecCD001B, after it
; copied its operand bytes to !Battle_ActOp80Args): JSL BattleD1_ActOp80
; ($D1:F67A, not matched), then RTL.
; Callers (1 JMP site): BattleAct_UnkVecCD001B ($CD:001B).
; Entry: M=1, X=0, DP=0, DB=$7E (as the action code runs)
; Exit:  as BattleD1_ActOp80 leaves it (not traced)
BattleCD_ActOp80:
    JSL BattleD1_ActOp80
    RTL

; ============================================================
; An enemy's exit: the dissolve ($CD:0043–$CD:01A4)
; ============================================================

; $CD:0043 — BattleCD_EnemyDissolve (199 bytes, $0043–$0109)
; Takes an enemy off the screen, for BattleCF_RemoveMarkedEnemies (A =
; its battler slot, after that moved it to the special palette). It
; first waits frames (BattleCD_WaitFrameRefresh, BattleCD_FrameTick)
; until !Battle_BgFxEnded is 0, then picks one of three ways:
;   - !Battle_Unk99D2 non-zero and not 2, !Battle_Unk2A21 bit 4 clear
;     and the enemy's !Battler_UnkA08C set: BattleCD_EnemyDissolveFx (X
;     = its !Battler_ScreenX), then layer effect !BattleCD_FxExit40
;     (BattleCD_RunLayerFx), and !Hdma_Unk7F1520 = !Battle_HdmaScreens
;     without bit 0 (BG1 off the main screen, if it is a TM image as
;     the name of FieldBtlPpu.MainScreen suggests);
;   - else, when !Battle_Unk99D2 is 0 or 2 or the enemy's
;     !Battler_UnkA08C is 0, and its !Battler_UnkA01D bit 0 is set: JMP
;     to BattleCD_RunLayerFx with layer effect !BattleCD_FxExit38;
;   - else (and at once when !Battle_Unk99D2 is non-zero and not 2 and
;     !Battle_Unk2A21 bit 4 is set): sound
;     !BattleCD_SfxDissolve through BattleCD_ApuCmd18 with X = the
;     enemy's !Battler_ScreenX (the APU argument, a pan by the screen
;     x, probably), then falls into BattleCD_EnemyDissolveFx.
; BattleCD_EnemyDissolveFx ($00A0, also JSL'd from the first path; X is
; not used there): !Battle_DissolvePattern = !BattleCD_DissolvePattern;
; with !Battle_Unk99D2 0 it copies !BattleCD_DissolveRecBytes bytes of
; !BattleRom_DissolveRec to !Battle_PalAnimRec10 (the table's bytes
; 1-9, a palette animation record: kind 4, colours $C0-$CE, by its first
; bytes) and sets !Battle_PalAnimCopy bit 7 (BattleCD_StepShake copies it
; on to FieldAnimB record 10 in the NMI);
; waits !BattleCD_DissolveDelay frames; then !BattleCD_DissolveSteps
; times: BattleCD_DissolveStep twice (each clears one pixel column of
; one row in every tile of the enemy's decoded frame), uploads the
; frame buffer (BattleCD_QueueVramDma: !BattleRom_LayoutFrameBytes by
; the enemy's !Battler_FrameLayout from !BattleRom_SlotFrameBuf to VRAM
; !BattleRom_SlotFrameVram, by its slot) and runs a BattleCD_FrameTick.
; 64 column/row positions are cleared in all (see BattleCD_DissolveStep),
; so the enemy's tiles end blank: a pixel dissolve, probably.
; Callers (1 JMP site): BattleSys_VecCD0024 ($CD:0024).
; Entry: M=1, X=0, DP=0, DB=$7E (as BattleCF_RemoveMarkedEnemies runs);
;        A = the enemy's battler slot, B = 0 (the 16-bit TAX of the
;        slot: BattleCF_RemoveMarkedEnemies' TDC leaves it; the callees
;        run before the later TAXs are assumed to keep it 0, not traced)
; Exit:  M=1, X=0, DP=0, DB=$7E (RTL; what the callees leave, assumed);
;        A, X, Y clobbered; !Battle_ExitFxSlot = the slot; DP $53-$59,
;        $73 and $75 written on the dissolve path
; Sub-entry: BattleCD_EnemyDissolveFx ($00A0), JSL'd from the first path
;   with M=1, X=0, DP=0, DB=$7E and !Battle_ExitFxSlot set; exits as
;   above (RTL).
BattleCD_EnemyDissolve:
    STA.w !Battle_ExitFxSlot
.wait_fx_end:
    JSR BattleCD_WaitFrameRefresh
    JSL BattleCD_FrameTick
    LDA.w !Battle_BgFxEnded
    BNE .wait_fx_end
    LDA.w !Battle_Unk99D2
    BEQ .no_mask
    CMP.b #2
    BEQ .no_mask
    LDA.w !Battle_Unk2A21
    AND.b #!Battle_2A21Bit4
    BNE .dissolve
    LDA.w !Battle_ExitFxSlot
    TAX
    LDA.w !Battler_UnkA08C,X
    BEQ .no_mask
    LDA.w !Battler_ScreenX,X
    TAX
    JSL BattleCD_EnemyDissolveFx
    LDA.b #!BattleCD_FxExit40
    JSL BattleCD_RunLayerFx
    LDA.w !Battle_HdmaScreens
    AND.b #!BattleCD_MainNoBg1
    STA.l !Hdma_Unk7F1520
    RTL
.no_mask:
    LDA.w !Battle_ExitFxSlot
    TAX
    LDA.w !Battler_UnkA01D,X
    AND.b #!Battle_A01DBit0
    BEQ .dissolve
    LDA.b #!BattleCD_FxExit38
    JMP BattleCD_RunLayerFx
.dissolve:
    LDA.w !Battle_ExitFxSlot
    TAX
    LDA.w !Battler_ScreenX,X
    TAX
    LDA.b #!BattleCD_SfxDissolve
    JSR BattleCD_ApuCmd18
BattleCD_EnemyDissolveFx:               ; header: see BattleCD_EnemyDissolve
    LDA.b #!BattleCD_DissolvePattern
    STA.w !Battle_DissolvePattern
    LDA.w !Battle_Unk99D2
    BNE .wait
    LDX.w #!BattleCD_DissolveRecBytes
.copy_rec:
    LDA.l !BattleRom_DissolveRec,X
    STA.w !Battle_PalAnimRec10-1,X
    DEX
    BNE .copy_rec
    LDA.w !Battle_PalAnimCopy
    ORA.b #!Battle_PalAnimCopy10
    STA.w !Battle_PalAnimCopy
.wait:
    LDA.b #!BattleCD_DissolveDelay
    JSR BattleCD_WaitFrames
    STZ.w !Battle_DissolveStepNum
    STZ.w !Battle_DissolvePhase
.step:
    JSR BattleCD_DissolveStep
    JSR BattleCD_DissolveStep
    LDA.w !Battle_ExitFxSlot
    TAX
    LDA.w !Battler_FrameLayout,X
    REP #$20
    ASL A
    TAX
    LDA.l !BattleRom_LayoutFrameBytes,X
    STA.b !BattleCD_Tmp53                ; byte count for BattleCD_QueueVramDma
    LDA.w !Battle_ExitFxSlot
    AND.w #!Battle_LowByteMask
    ASL A
    TAX
    LDA.l !BattleRom_SlotFrameVram,X
    TAY
    LDA.l !BattleRom_SlotFrameBuf,X
    TAX
    TDC
    SEP #$20
    LDA.b #!Battle_WramBank
    JSR BattleCD_QueueVramDma
    JSL BattleCD_FrameTick
    INC.w !Battle_DissolveStepNum
    LDA.w !Battle_DissolveStepNum
    CMP.b #!BattleCD_DissolveSteps
    BNE .step
    RTL

; $CD:010A — BattleCD_DissolveStep (147 bytes, $010A–$019C)
; One step of BattleCD_EnemyDissolve: advances !Battle_DissolvePhase by
; the !BattleRom_DissolvePhaseStep entry !Battle_DissolvePattern & 7
; ($17 for the pattern 7 the dissolve uses: odd, so 64 steps visit all
; 64 phases mod 64); then, with the new phase, mask = the
; !BattleRom_DissolveMask word phase & 7 (both bytes with one bit clear:
; $7F7F for bit 7 down to $FEFE for bit 0) and row offset = (phase & $38)
; / 4, and for each of the two tile ranges of the enemy's frame layout
; (the !BattleRom_DissolveRanges record layout * 8: a byte offset and a
; tile count at +0/+2 and +4/+6) ANDs the mask into the words at row
; offset and row offset + $10 of each tile (bit planes 0-1 and 2-3 of
; one pixel row of a 4bpp tile) in the enemy's frame buffer
; (!BattleRom_SlotFrameBuf by slot). Layout 2 in slot 6 uses the ranges
; of layout 5 (a special case kept as found).
; The inner part from $0154 (.range) is JSR'd once with X = 0 and then
; run with X = 4.
; Callers (2 JSR sites): BattleCD_EnemyDissolveFx ($CD:00CA, $CD:00CD).
; Entry: M=1, X=0, DP=0, DB=$7E (the frame buffer is read .w in bank
;        $7E); !Battle_ExitFxSlot = the enemy's slot (B = 0 for its TAX,
;        as BattleCD_EnemyDissolve leaves it, assumed)
; Exit:  M=1, X=0; A = 0 (TDC; B = 0); X = the last tile's offset + $20;
;        Y unchanged; DP $53-$59, $73 and $75 written
BattleCD_DissolveStep:
    LDA.w !Battle_ExitFxSlot
    TAX
    STX.b !BattleCD_Tmp59               ; the slot (16-bit)
    LDA.w !Battler_FrameLayout,X
    CMP.b #2
    BNE .have_layout
    CPX.w #!BattleCD_DissolveSlot6
    BNE .have_layout
    LDA.b #5
.have_layout:
    TAX
    STX.b !BattleCD_Tmp53               ; the layout (16-bit)
    LDA.w !Battle_DissolvePattern
    AND.b #7
    TAX
    LDA.w !Battle_DissolvePhase
    CLC
    ADC.l !BattleRom_DissolvePhaseStep,X
    STA.w !Battle_DissolvePhase
    REP #$20
    PHA
    AND.w #7
    ASL A
    TAX
    LDA.l !BattleRom_DissolveMask,X
    STA.b !BattleCD_Tmp73               ; the mask word
    PLA
    AND.w #!BattleCD_DissolveRowBits
    LSR A
    LSR A
    STA.b !BattleCD_Tmp75               ; the row offset
    TDC
    SEP #$20
    LDX.w #0
    JSR .range
    LDX.w #4
.range:
    STX.b !BattleCD_Tmp55
    LDA.b !BattleCD_Tmp53
    ASL A
    ASL A
    ASL A
    REP #$20
    AND.w #!Battle_LowByteMask
    CLC
    ADC.b !BattleCD_Tmp55
    TAX
    LDA.l !BattleRom_DissolveRanges,X
    STA.b !BattleCD_Tmp55               ; the range's byte offset
    LDA.l !BattleRom_DissolveRanges+2,X
    STA.b !BattleCD_Tmp57               ; its tile count
    LDA.b !BattleCD_Tmp59
    ASL A
    TAX
    LDA.l !BattleRom_SlotFrameBuf,X
    CLC
    ADC.b !BattleCD_Tmp55
    CLC
    ADC.b !BattleCD_Tmp75
    TAX
.tile:
    LDA.w !Battle_WramAbs,X
    AND.b !BattleCD_Tmp73
    STA.w !Battle_WramAbs,X
    LDA.w !Battle_WramAbs+!BattleCD_TilePlanes23,X
    AND.b !BattleCD_Tmp73
    STA.w !Battle_WramAbs+!BattleCD_TilePlanes23,X
    TXA
    CLC
    ADC.w #!Battle_TileBytes
    TAX
    DEC.b !BattleCD_Tmp57
    BNE .tile
    TDC
    SEP #$20
    RTS

; $CD:019D — BattleCD_MsgTimeTable (8 bytes, $019D–$01A4)
; Frames a battle message stays up, by the message-speed setting
; (BattleCD_GetMsgTime: bits 3-5 of config byte $2991): $20, $40, ...,
; $E0, then $FF.
BattleCD_MsgTimeTable:
    db $20,$40,$60,$80,$A0,$C0,$E0,$FF

; ============================================================
; Battle messages ($CD:01A5–$CD:033F)
; ============================================================
; The messages are bank $C2's text window (TextWin_Init / TextWin_Step
; through BankC2_Entry0003 / 0009) drawn into !Battle_TextGfxBuf, with
; the string tables named below. !Battle_MsgShown = !BattleCD_MsgShownOn
; while one is up; the bank-$D1 NMI handler ($D1:E7EC, not matched) counts
; !Battle_MsgTimer down while !Battle_MsgTiming is set and at 0 clears
; !Battle_MsgShown and !Battle_MsgTiming (and !Battle_ScriptMsgUp,
; setting !Battle_LastScriptMsg to $FF when it was set) and bumps
; !Battle_UnkCA24.

; $CD:01A5 — BattleCD_GetMsgTime (14 bytes, $01A5–$01B2)
; A = BattleCD_MsgTimeTable entry by bits 3-5 of !Menu_Config+1: the
; frames a message stays up at the configured speed (inferred from the
; uses: BattleCD_ShowMessage waits that long, the others load
; !Battle_MsgTimer with it).
; Callers (4 JSR sites): BattleCD_ShowMessage ($CD:01DB), BattleCD_ShowMessageTimed ($CD:0228),
;   BattleCD_ShowScriptMessage ($CD:02B8) and BattleCD_StepText ($CD:04F3).
; Entry: M=1, X=0 (16-bit TAX with B = 0: the LSRs of an 8-bit A leave
;        B as it was, so B = 0 is assumed from the callers), DP any, DB=$7E
; Exit:  M=1, X=0; A = the frame count; X = the setting (0-7)
BattleCD_GetMsgTime:
    LDA.w !Menu_Config+1
    LSR A
    LSR A
    LSR A
    AND.b #7
    TAX
    LDA.l BattleCD_MsgTimeTable,X
    RTS

; $CD:01B3 — BattleCD_ShowMessage (87 bytes, $01B3–$0209)
; Shows battle message A (string A of !BattleRom_MsgStrings, its
; arguments at $0200, BattleMsg_InfoArgs / !Battle_MsgArg0) and waits for
; it: plays the message's sound (!BattleRom_MsgSfx entry A, unless $FF)
; through BattleCD_ApuCmd18 with X = !BattleCD_SfxArgCentre, starts the
; text (BattleCD_StartText, BattleCD_ShowText), waits 16 frames, then:
; message !Battle_EndUnkCD0021Arg waits !BattleCD_MsgFixedWait frames;
; any other waits up to BattleCD_GetMsgTime frames, and stops early on a
; frame that sees !Battle_PadHeld bit 7 (a button held). Then
; !Battle_MsgShown and !Battle_MsgTiming = 0, !Battle_UnkCA24 + 1, and
; 16 more frames.
; Callers (1 JMP site): BattleSys_UnkVecCD0021 ($CD:0021).
; Entry: M=1, X=0, DP=0, DB=$7E (as BattleSys_Main, BattleSys_UnkB967
;        and BattleFD_UnkAD17 run); A = the message, B = 0 (the 16-bit
;        TAX of it)
; Exit:  M=1, X=0, DP=0, DB=$7E (RTL; as the callees leave them); A, X,
;        Y clobbered; DP $53 written
BattleCD_ShowMessage:
    PHA
    PHA
    PHA
    LDX.w #!BattleRom_MsgStrings&$FFFF
    STX.w !TextWin_Dp+!TextWin_StrTable
    LDA.b #!BattleRom_MsgStrings>>16
    STA.w !TextWin_Dp+!TextWin_StrTable+2
    PLA
    TAX
    LDA.l !BattleRom_MsgSfx,X
    CMP.b #!BattleCD_MsgNoSfx
    BEQ .text
    LDX.w #!BattleCD_SfxArgCentre
    JSR BattleCD_ApuCmd18
.text:
    PLA
    JSR BattleCD_StartText
    JSR BattleCD_ShowText
    JSR BattleCD_Wait16Frames
    JSR BattleCD_GetMsgTime
    STA.b !BattleCD_Tmp53               ; frames to wait
    PLA
    CMP.b #!Battle_EndUnkCD0021Arg
    BNE .timed
    LDA.b #!BattleCD_MsgFixedWait
    JSR BattleCD_WaitFrames
    BRA .close
.timed:
    LDA.b !BattleCD_Tmp53
.wait:
    PHA
    JSR BattleCD_WaitFrameRefresh
    LDA.b !Battle_PadHeld
    BPL .not_pressed
    PLA
    BRA .close
.not_pressed:
    PLA
    DEC A
    BNE .wait
.close:
    STZ.w !Battle_MsgShown
    STZ.w !Battle_MsgTiming
    INC.w !Battle_UnkCA24
    JSR BattleCD_Wait16Frames
    RTL

; $CD:020A — BattleCD_Wait16Frames (11 bytes, $020A–$0214)
; Waits 16 frames (BattleCD_WaitFrameRefresh 16 times).
; Callers (3 JSR sites): BattleCD_ShowMessage ($CD:01D8, $CD:0206) and unmatched ($CD:7C94).
; Callers note: the JSR byte pattern at $CD:7C94 lies in the bank's data
;   ($CD:4000 on), not a call.
; Entry: M=1, X=0, DP=0, DB=$7E (what BattleCD_WaitFrameRefresh needs)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y as the waits leave them
BattleCD_Wait16Frames:
    LDA.b #!BattleCD_WaitShort
.frame:
    PHA
    JSR BattleCD_WaitFrameRefresh
    PLA
    DEC A
    BNE .frame
    RTS

; $CD:0215 — BattleCD_ShowMessageTimed (32 bytes, $0215–$0234)
; As BattleCD_ShowMessage without the sound and without waiting: starts
; message A of !BattleRom_MsgStrings (BattleCD_StartText,
; BattleCD_ShowText), loads !Battle_MsgTimer with BattleCD_GetMsgTime,
; sets !Battle_MsgTiming (+1) so the NMI closes it, waits a frame, RTL.
; Reached only through BattleSys_VecCD001E (no caller of that found).
; Callers (1 JMP site): BattleSys_VecCD001E ($CD:001E).
; Entry: M=1, X=0, DP=0, DB=$7E (assumed: as BattleCD_ShowMessage); A =
;        the message
; Exit:  M=1, X=0, DP=0, DB=$7E (RTL; as the callees leave them); A, X,
;        Y clobbered
BattleCD_ShowMessageTimed:
    LDX.w #!BattleRom_MsgStrings&$FFFF
    STX.w !TextWin_Dp+!TextWin_StrTable
    PHA
    LDA.b #!BattleRom_MsgStrings>>16
    STA.w !TextWin_Dp+!TextWin_StrTable+2
    PLA
    JSR BattleCD_StartText
    JSR BattleCD_ShowText
    JSR BattleCD_GetMsgTime
    STA.w !Battle_MsgTimer
    INC.w !Battle_MsgTiming
    JSR BattleCD_WaitFrameRefresh
    RTL

; $CD:0235 — BattleCD_ClearTextGfxL (4 bytes, $0235–$0238)
; BattleCD_ClearTextGfx as a long call (JSL from the bank-$D1 code at
; $D1:F3FE, not matched).
; Callers (1 JSL site): unmatched ($D1:F3FE).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E (as BattleCD_ClearTextGfx needs)
; Exit:  as BattleCD_ClearTextGfx (M=1, X=0; A = 0; X = 0; Y unchanged),
;        returning with RTL
BattleCD_ClearTextGfxL:
    JSR BattleCD_ClearTextGfx
    RTL

; $CD:0239 — BattleCD_ClearTextGfx (37 bytes, $0239–$025D)
; Zeroes the message graphics buffer !Battle_TextGfxBuf ($7E:B400-$B7FF,
; $400 bytes) by words: eight stores per pass, each
; covering one $80-byte eighth of it, for X = $80 down to 2.
; Callers (2 JSR sites): BattleCD_ClearTextGfxL ($CD:0235) and BattleCD_StartText ($CD:0275).
; Entry: M=1 (REP/SEP #$20 here), X=0 (16-bit X loop), DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A = 0 (B = 0: the 16-bit TDC); X = 0; Y unchanged
BattleCD_ClearTextGfx:
    REP #$20
    TDC
    LDX.w #!BattleCD_TextGfxPart
.word:
    STA.w !Battle_TextGfxBuf-2,X
    STA.w !Battle_TextGfxBuf+(!BattleCD_TextGfxPart*1)-2,X
    STA.w !Battle_TextGfxBuf+(!BattleCD_TextGfxPart*2)-2,X
    STA.w !Battle_TextGfxBuf+(!BattleCD_TextGfxPart*3)-2,X
    STA.w !Battle_TextGfxBuf+(!BattleCD_TextGfxPart*4)-2,X
    STA.w !Battle_TextGfxBuf+(!BattleCD_TextGfxPart*5)-2,X
    STA.w !Battle_TextGfxBuf+(!BattleCD_TextGfxPart*6)-2,X
    STA.w !Battle_TextGfxBuf+(!BattleCD_TextGfxPart*7)-2,X
    DEX
    DEX
    BNE .word
    SEP #$20
    RTS

; $CD:025E — BattleCD_StartText (33 bytes, $025E–$027E)
; Starts string A of the table the caller put in TextWin_StrTable:
; TextWin_StrIndex = A, !Battle_MsgTiming = 0, !Battle_TextUnkA1 = 0,
; TextWin_GfxBuf = !Battle_TextGfxBuf (bank $7E), TextWin_Mode = 0, the
; buffer cleared (BattleCD_ClearTextGfx), TextWin_Init (through
; BankC2_Entry0003). Returns A = !BattleCD_TextStepCount, which the
; three message callers (BattleCD_ShowMessage, BattleCD_ShowMessageTimed,
; BattleCD_ShowScriptMessage) pass straight to BattleCD_ShowText;
; BattleCD_ShowTargetInfo and BattleCD_ShowTechInfo drop it.
; Callers (5 JSR sites): BattleCD_ShowMessage ($CD:01D2), BattleCD_ShowMessageTimed ($CD:0222),
;   BattleCD_ShowScriptMessage ($CD:02AD), BattleCD_ShowTargetInfo ($CD:02FF) and
;   BattleCD_ShowTechInfo ($CD:032F).
; Entry: M=1, X=0, DP=0, DB=$7E (the block at $0200 is written .w in
;        bank $7E's low mirror); A = the string number; TextWin_StrTable
;        set
; Exit:  M=1, X=0, DP=0, DB=$7E (TextWin_Init saves and restores P and
;        DP); A = !BattleCD_TextStepCount; X, Y clobbered
BattleCD_StartText:
    STA.w !TextWin_Dp+!TextWin_StrIndex
    STZ.w !Battle_MsgTiming
    STZ.w !Battle_TextUnkA1
    LDX.w #!Battle_TextGfxBuf
    STX.w !TextWin_Dp+!TextWin_GfxBuf
    LDA.b #!Battle_WramBank
    STA.w !TextWin_Dp+!TextWin_GfxBuf+2
    STZ.w !TextWin_Dp+!TextWin_Mode
    JSR BattleCD_ClearTextGfx
    JSL BankC2_Entry0003
    LDA.b #!BattleCD_TextStepCount
    RTS

; $CD:027F — BattleCD_ShowText (22 bytes, $027F–$0294)
; Draws the started string: TextWin_StepCount = A (the callers pass
; !BattleCD_TextStepCount from BattleCD_StartText), one TextWin_Step
; (through BankC2_Entry0009), two BattleCD_WaitFrame, then
; !Battle_MsgShown = !BattleCD_MsgShownOn and !Battle_UnkCA24 + 1.
; Callers (3 JSR sites): BattleCD_ShowMessage ($CD:01D5), BattleCD_ShowMessageTimed ($CD:0225) and
;   BattleCD_ShowScriptMessage ($CD:02B0).
; Entry: M=1, X=0, DP=0, DB=$7E; A = the step count
; Exit:  M=1, X=0, DP=0, DB=$7E; A = !BattleCD_MsgShownOn; X, Y as
;        TextWin_Step and the waits leave them
BattleCD_ShowText:
    STA.w !TextWin_Dp+!TextWin_StepCount
    JSL BankC2_Entry0009
    JSR BattleCD_WaitFrame
    JSR BattleCD_WaitFrame
    LDA.b #!BattleCD_MsgShownOn
    STA.w !Battle_MsgShown
    INC.w !Battle_UnkCA24
    RTS

; $CD:0295 — BattleCD_ShowScriptMessage (54 bytes, $0295–$02CA)
; An enemy script's message (the run handlers pass a script byte in A:
; most pass !Battle_UnkB3C7; BattleAi_RunTech, BattleAi_RunSetFlags and
; BattleAi_RunMessage pass one read straight from the script,
; !BattleRom_ScriptBank+1/+2,X): !Battle_ScriptMsgUp + 1, string table
; !BattleRom_ScriptMsgStrings; unless A is !Battle_LastScriptMsg (the
; last one shown, which the NMI resets to $FF when the message closes):
; !Battle_NextScriptMsg = A, the text started and drawn
; (BattleCD_StartText, BattleCD_ShowText), 8 frames, !Battle_MsgTimer =
; BattleCD_GetMsgTime, !Battle_LastScriptMsg = the message,
; !Battle_MsgTiming + 1 (the NMI closes it), one more frame.
; Quirk: !Battle_ScriptMsgUp goes up even when the message is the same
; as the last one and nothing is shown; then nothing closes it here
; (what clears it then is not traced). Kept as found.
; Callers (1 JMP site): BattleMsg_UnkVecCD0033 ($CD:0033).
; Entry: M=1, X=0, DP=0, DB=$7E (as the enemy-script run handlers run);
;        A = the message (non-zero)
; Exit:  M=1, X=0, DP=0, DB=$7E (RTL); A, X, Y clobbered
BattleCD_ShowScriptMessage:
    INC.w !Battle_ScriptMsgUp
    LDX.w #!BattleRom_ScriptMsgStrings&$FFFF
    STX.w !TextWin_Dp+!TextWin_StrTable
    PHA
    LDA.b #!BattleRom_ScriptMsgStrings>>16
    STA.w !TextWin_Dp+!TextWin_StrTable+2
    PLA
    CMP.w !Battle_LastScriptMsg
    BEQ .done
    STA.w !Battle_NextScriptMsg
    JSR BattleCD_StartText
    JSR BattleCD_ShowText
    LDA.b #8
    JSR BattleCD_WaitFrames
    JSR BattleCD_GetMsgTime
    STA.w !Battle_MsgTimer
    LDA.w !Battle_NextScriptMsg
    STA.w !Battle_LastScriptMsg
    INC.w !Battle_MsgTiming
    JSR BattleCD_WaitFrameRefresh
.done:
    RTL

; $CD:02CB — BattleCD_ShowEnemyInfo (69 bytes, $02CB–$030F)
; The battle menu's info panel for the highlighted enemy target
; (BattleMenu_UpdateCursorOverlay; BattleMenu_ChooseAttack also calls
; BattleCD_ShowTargetInfo): A = a key, the target slot
; (!BattleMsg_ArgNone = none). Unless a script message is up
; (!Battle_ScriptMsgUp, read as a word, see the quirk) or the key is the
; one shown last (!Battle_InfoKey) or none, it starts string
; !BattleCD_InfoEnemy (BattleCD_ShowEnemyInfo) or !BattleCD_InfoTarget
; (BattleCD_ShowTargetInfo: the caller's path that also puts the
; target's HP in BattleMsg_InfoArgs) of !BattleRom_MsgStrings
; (BattleCD_StartText),
; sets !Battle_MsgShown = !BattleCD_MsgShownOn, !Battle_UnkCA24 + 1, and
; !Battle_TextStepping = 1 so BattleCD_StepText draws it a step a frame.
; The key itself only goes to !Battle_InfoKey (the string's arguments
; are at $0200). DP $53 holds the string number.
; Quirk: the LDX of !Battle_ScriptMsgUp is 16-bit, so the byte after it
; ($CD1E) also blocks the panel when non-zero. Kept as found.
; Callers (1 JMP site): BattleMsg_UnkVecCD0030 ($CD:0030).
; Callers of BattleCD_ShowTargetInfo (1 JMP site): BattleMsg_ShowMsg0BIfKeyChangedVec ($CD:002D).
; Entry: M=1, X=0, DP=0, DB=$7E (as BattleMenu_UpdateCursorOverlay runs);
;        A = the key
; Exit:  M=1, X=0, DP=0, DB=$7E (RTL); A, X, Y clobbered (X = the word
;        at !Battle_ScriptMsgUp on the early exits); DP $53 written
; Sub-entry: BattleCD_ShowTargetInfo ($02D8), the same with string
;   !BattleCD_InfoTarget.
BattleCD_ShowEnemyInfo:
    LDX.w !Battle_ScriptMsgUp
    BEQ .enemy
    RTL
.enemy:
    PHA
    LDA.b #!BattleCD_InfoEnemy
    STA.b !BattleCD_Tmp53               ; the string
    BRA BattleCD_ShowTargetInfo_show
BattleCD_ShowTargetInfo:                ; header: see BattleCD_ShowEnemyInfo
    LDX.w !Battle_ScriptMsgUp
    BEQ .target
    RTL
.target:
    PHA
    LDA.b #!BattleCD_InfoTarget
    STA.b !BattleCD_Tmp53
.show:
    PLA
    CMP.w !Battle_InfoKey
    BEQ .done
    STA.w !Battle_InfoKey
    CMP.b #!BattleMsg_ArgNone
    BEQ .done
    LDX.w #!BattleRom_MsgStrings&$FFFF
    STX.w !TextWin_Dp+!TextWin_StrTable
    LDA.b !BattleCD_Tmp53
    PHA
    LDA.b #!BattleRom_MsgStrings>>16
    STA.w !TextWin_Dp+!TextWin_StrTable+2
    PLA
    JSR BattleCD_StartText
    LDA.b #!BattleCD_MsgShownOn
    STA.w !Battle_MsgShown
    INC.w !Battle_UnkCA24
    LDA.b #1
    STA.w !Battle_TextStepping
.done:
    RTL

; $CD:0310 — BattleCD_ShowTechInfo (48 bytes, $0310–$033F)
; The info panel for the tech (or item) under the menu cursor: A = the
; key, string A of !BattleRom_TechInfoStrings. As BattleCD_ShowEnemyInfo:
; nothing while the word at !Battle_ScriptMsgUp is non-zero, when A is
; !Battle_InfoKey or when it is !BattleMsg_InfoNone; else !Battle_InfoKey
; = A, BattleCD_StartText, !Battle_MsgShown = !BattleCD_MsgShownOn,
; !Battle_UnkCA24 + 1, !Battle_TextStepping = 1.
; Callers (2 sites: 1 JSR, 1 JMP): BattleMsg_ShowFromTableCC3A09Vec (JMP $CD:0027) and unmatched
;   (JSR $CD:7EDA).
; Callers note: the JSR byte pattern at $CD:7EDA lies in the bank's data
;   ($CD:4000 on), not a call.
; Entry: M=1, X=0, DP=0, DB=$7E (as the battle menu runs); A = the key
; Exit:  M=1, X=0, DP=0, DB=$7E (RTL); A, X, Y clobbered
BattleCD_ShowTechInfo:
    LDX.w !Battle_ScriptMsgUp
    BEQ .check
    RTL
.check:
    CMP.w !Battle_InfoKey
    BEQ .done
    STA.w !Battle_InfoKey
    CMP.b #!BattleMsg_InfoNone
    BEQ .done
    LDX.w #!BattleRom_TechInfoStrings&$FFFF
    STX.w !TextWin_Dp+!TextWin_StrTable
    PHA
    LDA.b #!BattleRom_TechInfoStrings>>16
    STA.w !TextWin_Dp+!TextWin_StrTable+2
    PLA
    JSR BattleCD_StartText
    LDA.b #!BattleCD_MsgShownOn
    STA.w !Battle_MsgShown
    INC.w !Battle_UnkCA24
    LDA.b #1
    STA.w !Battle_TextStepping
.done:
    RTL

; ============================================================
; Joypad auto-repeat ($CD:0340–$CD:0398)
; ============================================================

; $CD:0340 — BattleCD_PadRepeat (89 bytes, $0340–$0398)
; Turns the held buttons into presses with auto-repeat, once a frame
; (BattleCD_NmiMain runs it on both its paths, after BankC2_Entry8002
; read the pad), all
; 16-bit: !Battle_PadPrev = the last frame's !Battle_PadNow, which takes
; !Battle_PadHeld. The result in !Battle_PadPrev (the name keeps its
; first use) is:
;   - nothing held now or before: 0, and the delay !Battle_PadDelay =
;     !BattleCD_PadDelayFirst;
;   - no button held in both frames: the newly held buttons;
;   - some held in both: the delay counts down; while it runs, only the
;     newly held buttons; at 0 every held button, and the delay = 1 (a
;     repeat every frame from then on).
; The result is ORed into !Battle_PadEdgeButtons/!Battle_PadEdgeDpad;
; when its low byte has bit 7 (a new or repeated press of that button)
; the delay is set to !BattleCD_PadDelayRepeat.
; Callers (2 JSR sites): BattleCD_NmiMain ($CD:091E, $CD:09CA).
; Entry: M=1 (REP/SEP #$20 here), X any, DP=0 (!Battle_PadHeld and the
;        edge bytes), DB=$7E (BattleCD_NmiMain sets it before the call)
; Exit:  M=1; A = !Battle_PadPrev's low byte, or
;        !BattleCD_PadDelayRepeat when that byte has bit 7 set; B = 0
;        (TDC); X, Y unchanged
BattleCD_PadRepeat:
    REP #$20
    LDA.w !Battle_PadNow
    STA.w !Battle_PadPrev
    LDA.b !Battle_PadHeld
    STA.w !Battle_PadNow
    ORA.w !Battle_PadPrev
    BNE .something
    STA.w !Battle_PadPrev
    LDA.w #!BattleCD_PadDelayFirst
    STA.w !Battle_PadDelay
    BRA .merge
.something:
    LDA.w !Battle_PadPrev
    AND.w !Battle_PadNow
    BNE .held
.new_only:
    LDA.w !Battle_PadPrev
    EOR.w #!Battle_Invert16
    AND.w !Battle_PadNow
    STA.w !Battle_PadPrev
    BRA .merge
.held:
    DEC.w !Battle_PadDelay
    BNE .new_only
    LDA.w #1
    STA.w !Battle_PadDelay
    LDA.w !Battle_PadNow
    STA.w !Battle_PadPrev
.merge:
    LDA.w !Battle_PadPrev
    ORA.b !Battle_PadEdgeButtons
    STA.b !Battle_PadEdgeButtons
    TDC
    SEP #$20
    LDA.w !Battle_PadPrev
    BPL .done
    LDA.b #!BattleCD_PadDelayRepeat
    STA.w !Battle_PadDelay
.done:
    RTS

; ============================================================
; Battle start and exit ($CD:0399–$CD:053B)
; ============================================================

; $CD:0399 — BattleCD_SetNmiMode1 (5 bytes, $0399–$039D)
; !Battle_NmiMode = 1: from the next NMI, BattleCD_NmiDispatch runs
; BattleCD_NmiMain instead of BattleCD_NmiSetup (service 0's first
; bank-$CD step).
; Callers (1 JMP site): BattleSys_VecCD0003 ($CD:0003).
; Entry: M=1, X any, DP=0, DB any
; Exit:  M=1; A = 1; X, Y, DP, DB unchanged
BattleCD_SetNmiMode1:
    LDA.b #1
    STA.b !Battle_NmiMode
    RTL

; $CD:039E — BattleCD_ApuCmd81 (22 bytes, $039E–$03B3)
; Sends APU command !Audio_CmdUnk81 with arguments
; !BattleCD_Cmd81Arg1 and 0 (Audio_ProcessEntry; the field's
; AudioFadeDispatch sends the same command with other arguments around
; its music changes: a volume fade, probably), then waits 15 frames
; (BattleCD_WaitFrames).
; Callers (3 JSR sites): BattleCD_ExitBattle ($CD:03D3), BattleCD_LayerFx87 ($CD:0D96) and
;   BattleCD_LayerFx84 ($CD:0DB1).
; Entry: M=1, X=0, DP=0, DB=$7E (the command bytes are written .w)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y as the waits leave them
BattleCD_ApuCmd81:
    LDA.b #!Audio_CmdUnk81
    STA.w !Sfx_Command
    LDA.b #!BattleCD_Cmd81Arg1
    STA.w !Sfx_Param1
    STZ.w !Sfx_Param2
    JSL Audio_ProcessEntry
    LDA.b #!BattleCD_ExitFadeFrames
    JMP BattleCD_WaitFrames

; $CD:03B4 — BattleCD_ExitBattle (150 bytes, $03B4–$0449)
; The bank-$CD part of the battle's end (BattleCF_ExitBattle runs it
; just before it returns to the field). In order:
;   - !Battle_Unk2A21 bit 7 set: FieldBtl_EvtFlags bit 6 cleared;
;   - a layer effect still loaded (!Battle_LayerFxLoaded): ended
;     (BattleCD_EndLayerFx); !Battle_SfxPending = 0;
;   - FieldBtl_EvtFlags bit 6 clear: BattleCD_ApuCmd81;
;   - the closing wipe (BattleCD_StartCloseWipe), waited for frame by
;     frame (BattleCD_WaitFrame, BattleCD_WipeRunning);
;   - !Battle_UnkCA25 = !BattleCD_CA25Unk0E, !Battle_UnkCA24 + 1, a frame;
;   - with !Battle_Unk2A21 bit 0 set: BattleCD_LayerFx84 when
;     FieldBtl_Result is 0, else BattleCD_LayerFx87; with bit 4 set (and
;     bit 0 clear): BattleCD_LayerFx87 when FieldBtl_Result is non-zero;
;   - !Battle_UnkCA25 = !BattleCD_CA25Unk08, !Battle_UnkCA24 + 1, a frame;
;   - the NMI trampoline's target becomes BattleD1_NmiExit ($D1:F4C0, not
;     matched); DP $45 = !Battle_Brightness (the brightness, for that
;     handler to fade from, probably: not traced); waits
;     (BattleCD_WaitNmiAck) until APUIO1 reads
;     0, unless FieldBtl_EvtFlags bit 6 is set (one wait then);
;   - !Battle_Unk2A21 = 0, AudioFadeDispatch (through ReentryVectors
;     vector [4]) between PHB/PHD/PHP and PLP/PLD/PLB: that routine
;     returns with D and DB swapped about (see there), and this puts
;     them back; then A = 0 and one more BattleCD_WaitNmiAck.
; Callers (1 JMP site): BattleSys_VecCD0006 ($CD:0006).
; Entry: M=1, X=0, DP=0, DB=$7E (as BattleCF_ExitBattle runs)
; Exit:  M=1, X=0, DP=0, DB=$7E (RTL; restored around AudioFadeDispatch,
;        the other callees assumed to keep them); A, X, Y clobbered; DP
;        $45 and $47 written
BattleCD_ExitBattle:
    LDA.w !Battle_Unk2A21
    BPL .keep_flags
    LDA.w !FieldBtl_EvtFlags
    AND.b #!BattleCD_EvtNoBit6
    STA.w !FieldBtl_EvtFlags
.keep_flags:
    LDA.w !Battle_LayerFxLoaded
    BEQ .no_fx
    JSR BattleCD_EndLayerFx
.no_fx:
    STZ.w !Battle_SfxPending
    LDA.w !FieldBtl_EvtFlags
    AND.b #!BattleCD_EvtBit6
    BNE .wipe
    JSR BattleCD_ApuCmd81
.wipe:
    JSL BattleCD_StartCloseWipe
.wipe_wait:
    JSR BattleCD_WaitFrame
    JSL BattleCD_WipeRunning
    BNE .wipe_wait
    LDA.b #!BattleCD_CA25Unk0E
    STA.w !Battle_UnkCA25
    INC.w !Battle_UnkCA24
    JSR BattleCD_WaitFrame
    LDA.w !Battle_Unk2A21
    AND.b #!Battle_2A21Bit0|!Battle_2A21Bit4
    BEQ .no_end_fx
    AND.b #!Battle_2A21Bit0
    BEQ .bit4
    LDA.l !FieldBtl_Result
    BNE .fx87
    JSR BattleCD_LayerFx84
    BRA .no_end_fx
.bit4:
    LDA.l !FieldBtl_Result
    BEQ .no_end_fx
.fx87:
    JSR BattleCD_LayerFx87
.no_end_fx:
    LDA.b #!BattleCD_CA25Unk08
    STA.w !Battle_UnkCA25
    INC.w !Battle_UnkCA24
    JSR BattleCD_WaitFrame
    LDA.b #BattleD1_NmiExit>>16
    STA.w !NmiTrampoline+3
    LDX.w #BattleD1_NmiExit&$FFFF
    STX.w !NmiTrampoline+1
    LDA.w !Battle_Brightness
    STA.b !BattleCD_Tmp45
.wait_apu:
    JSR BattleCD_WaitNmiAck
    LDA.w !FieldBtl_EvtFlags
    AND.b #!BattleCD_EvtBit6
    BNE .audio
    LDA.l APUIO1
    BNE .wait_apu
.audio:
    STZ.w !Battle_Unk2A21
    PHB
    PHD
    PHP
    JSL ReentryVectors+!BattleCD_ReentryAudioFade
    PLP
    PLD
    PLB
    TDC
    JSR BattleCD_WaitNmiAck
    RTL

; $CD:044A — BattleCD_WaitNmiAck (9 bytes, $044A–$0452)
; DP $47 = 1, then waits until something else (an interrupt handler,
; probably BattleD1_NmiExit, which BattleCD_ExitBattle installs just
; before: not traced) sets it back to 0.
; Callers (2 JSR sites): BattleCD_ExitBattle ($CD:0428, $CD:0446).
; Entry: M=1, X any, DP=0, DB any
; Exit:  M=1; A = 0; X, Y, DP, DB unchanged
BattleCD_WaitNmiAck:
    LDA.b #1
    STA.b !BattleCD_Tmp47
.wait:
    LDA.b !BattleCD_Tmp47
    BNE .wait
    RTS

; $CD:0453 — BattleCD_EndLayerFx (83 bytes, $0453–$04A5)
; Ends a layer effect (BattleCD_FrameTick runs it when the effect is
; done, !Battle_BgFxEnded set, and no action runs; BattleCD_ExitBattle
; when one is still loaded): puts layer 3's tiles back (the battle
; background's, probably: !BattleCD_BgSaveBytes bytes from
; !Battle_BgTileSave in bank $7F to VRAM !BattleCD_BgTileVram, where the
; effect's tile sets went; BattleCD_QueueVramDma), !Battle_LayerFxLoaded
; = 0 and !Battle_LayerFxMode = 0; then, unless !Battle_Unk99D2 is
; negative or !Battle_UnkCD07 set: when the effect had its own layer
; settings (BattleCD_LayerFxSetsScreen C=1) and !Battle_Unk2A21 bit 0 or
; bit 2 of FieldBtlPpu.MainScreen/.SubScreen is set,
; BattleCD_LoadFxPalA; a frame; the screen settings back
; (BattleCD_RestoreScreen); 15 frames. Then !Battle_LayerFxId = 0,
; !Battle_BgFxEnded = 0, the palette rows back (BattleCD_RestorePalRows),
; a frame.
; Callers (2 JSR sites): BattleCD_ExitBattle ($CD:03C6) and BattleCD_FrameTick ($CD:04C4).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $53 written
BattleCD_EndLayerFx:
    LDX.w #!BattleCD_BgSaveBytes
    STX.b !BattleCD_Tmp53
    LDX.w #!Battle_BgTileSave&$FFFF
    LDY.w #!BattleCD_BgTileVram
    LDA.b #!Battle_BgTileSave>>16
    JSR BattleCD_QueueVramDma
    STZ.w !Battle_LayerFxLoaded
    STZ.w !Battle_LayerFxMode
    LDA.w !Battle_Unk99D2
    BMI .ids
    LDA.w !Battle_UnkCD07
    BNE .ids
    JSR BattleCD_LayerFxSetsScreen
    BCC .restore
    LDA.w !Battle_Unk2A21
    AND.b #!Battle_2A21Bit0
    BNE .pal
    LDA.w FieldBtlPpu.MainScreen
    ORA.w FieldBtlPpu.SubScreen
    AND.b #!BattleCD_ScreenBg3
    BEQ .restore
.pal:
    JSR BattleCD_LoadFxPalA
.restore:
    JSR BattleCD_WaitFrameRefresh
    JSR BattleCD_RestoreScreen
    LDA.b #!BattleCD_ExitFadeFrames
    JSR BattleCD_WaitFrames
.ids:
    TDC
    TAX
    STX.w !Battle_LayerFxId
    STZ.w !Battle_BgFxEnded
    JSR BattleCD_RestorePalRows
    JSR BattleCD_WaitFrameRefresh
    RTS

; $CD:04A6 — BattleCD_IdleTick (4 bytes, $04A6–$04A9)
; BattleSys_PumpFrames' long call while it waits for the frame:
; BattleCD_PauseWait, RTL.
; Callers (1 JMP site): BattleSys_IdleVecCD0036 ($CD:0036).
; Entry: M=1, X=0, DP=0, DB=$7E (as BattleSys_PumpFrames runs)
; Exit:  as BattleCD_PauseWait leaves it (RTL)
BattleCD_IdleTick:
    JSR BattleCD_PauseWait
    RTL

; $CD:04AA — BattleCD_FrameTick (53 bytes, $04AA–$04DE)
; The bank's per-frame work outside the NMI (BattleSys_FrameTickVec,
; and JSL from this bank's own waits): unless !Battle_Paused, the
; pending sound (BattleCD_PlayPendingSfx); BattleCD_PauseWait; then,
; unless !Battle_DmaQueueBusy is set: ends the layer effect
; (BattleCD_EndLayerFx) when !Battle_BgFxEnded is set and no action runs
; (!Battle_ActRunning 0); and when !Battle_UnkCD44 is set and
; !Battle_UnkCD43 is 0, JSL BattleD1_UnkECF3 ($D1:ECF3, not matched) with
; A = !Battle_UnkCD45 and !Battle_UnkCD44 = 0. Last, always, the text
; step (BattleCD_StepText).
; Callers (5 sites: 4 JSL, 1 JMP): BattleSys_FrameTickVec (JMP $CD:0009), BattleCD_EnemyDissolve
;   (JSL $CD:0049), BattleCD_EnemyDissolveFx (JSL $CD:00FB), BattleCD_LayerFx84 (JSL $CD:0DDE) and
;   BattleCD_RunLayerFx (JSL $CD:0E1C).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E (RTL; as the callees leave them,
;        assumed for the bank-$D1 one); A, X, Y clobbered
BattleCD_FrameTick:
    LDA.w !Battle_Paused
    BNE .pause
    JSR BattleCD_PlayPendingSfx
.pause:
    JSR BattleCD_PauseWait
    LDA.w !Battle_DmaQueueBusy
    BNE .text
    LDA.w !Battle_BgFxEnded
    BEQ .unk_cd44
    LDA.w !Battle_ActRunning
    BNE .unk_cd44
    JSR BattleCD_EndLayerFx
.unk_cd44:
    LDA.w !Battle_UnkCD44
    BEQ .text
    LDA.w !Battle_UnkCD43
    BNE .text
    LDA.w !Battle_UnkCD45
    JSL BattleD1_UnkECF3
    STZ.w !Battle_UnkCD44
.text:
    JSR BattleCD_StepText
    RTL

; $CD:04DF — BattleCD_StepText (30 bytes, $04DF–$04FC)
; When !Battle_TextStepping is set: one TextWin_Step (through
; BankC2_Entry0009) with TextWin_StepCount = 1; !Battle_TextStepping =
; TextWin_Status after it (0 once the string is done, so the stepping
; stops); !Battle_MsgTimer = BattleCD_GetMsgTime and !Battle_MsgTiming +
; 1 (the NMI closes the panel when the time is up).
; Callers (2 JSR sites): BattleCD_FrameTick ($CD:04DB) and unmatched ($CD:3E89).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered (after a step A =
;        the frame count and X = the setting, see BattleCD_GetMsgTime;
;        else A = 0)
BattleCD_StepText:
    LDA.w !Battle_TextStepping
    BEQ .done
    LDA.b #1
    STA.w !TextWin_Dp+!TextWin_StepCount
    JSL BankC2_Entry0009
    LDA.w !TextWin_Dp+!TextWin_Status
    STA.w !Battle_TextStepping
    JSR BattleCD_GetMsgTime
    STA.w !Battle_MsgTimer
    INC.w !Battle_MsgTiming
.done:
    RTS

; $CD:04FD — BattleCD_StartOpenWipe (25 bytes, $04FD–$0515)
; Service 0's start of the opening wipe: sound !BattleCD_SfxWipe
; (BattleCD_ApuCmd18, X = !BattleCD_SfxArgCentre), a frame,
; !Battle_WipeSteps = !BattleCD_WipeSteps and !Battle_WipeMode =
; !BattleCD_WipeOpen (BattleCD_StepWipe then runs it in the NMI), a
; frame.
; Callers (1 JMP site): BattleSys_VecCD000C ($CD:000C).
; Entry: M=1, X=0, DP=0, DB=$7E (as BattleSys_SceneSetup runs)
; Exit:  M=1, X=0, DP=0, DB=$7E (RTL); A, X, Y clobbered
BattleCD_StartOpenWipe:
    LDA.b #!BattleCD_SfxWipe
    LDX.w #!BattleCD_SfxArgCentre
    JSR BattleCD_ApuCmd18
    JSR BattleCD_WaitFrame
    LDA.b #!BattleCD_WipeSteps
    STA.w !Battle_WipeSteps
    LDA.b #!BattleCD_WipeOpen
    STA.w !Battle_WipeMode
    JSR BattleCD_WaitFrame
    RTL

; $CD:0516 — BattleCD_StartCloseWipe (30 bytes, $0516–$0533)
; The battle end's closing wipe: !Battle_UnkCE16 = 1, a frame,
; !Battle_UnkCA25 = !BattleCD_CA25Unk0C and !Battle_UnkCA24 + 1, a frame,
; !Battle_WipeSteps = !BattleCD_WipeSteps, !Battle_WipeMode =
; !BattleCD_WipeClose.
; Callers (2 sites: 1 JSL, 1 JMP): BattleSys_VecCD000F (JMP $CD:000F) and BattleCD_ExitBattle (JSL
;   $CD:03D6).
; Entry: M=1, X=0, DP=0, DB=$7E (as BattleCD_ExitBattle runs)
; Exit:  M=1, X=0, DP=0, DB=$7E (RTL); A = !BattleCD_WipeClose; X, Y as
;        the waits leave them
BattleCD_StartCloseWipe:
    LDA.b #1
    STA.w !Battle_UnkCE16
    JSR BattleCD_WaitFrame
    LDA.b #!BattleCD_CA25Unk0C
    STA.w !Battle_UnkCA25
    INC.w !Battle_UnkCA24
    JSR BattleCD_WaitFrame
    LDA.b #!BattleCD_WipeSteps
    STA.w !Battle_WipeSteps
    LDA.b #!BattleCD_WipeClose
    STA.w !Battle_WipeMode
    RTL

; $CD:0534 — BattleCD_WipeRunning (8 bytes, $0534–$053B)
; A = 1 while a wipe has steps left (!Battle_WipeSteps non-zero), else
; 0; Z set iff 0 (BattleSys_SceneSetup and BattleCD_ExitBattle loop on
; it).
; Callers (2 sites: 1 JSL, 1 JMP): BattleSys_VecCD0012 (JMP $CD:0012) and BattleCD_ExitBattle (JSL
;   $CD:03DD).
; Entry: M=1, X any, DP any, DB=$7E
; Exit:  M=1; A = 0 or 1, Z as A; X, Y unchanged
BattleCD_WipeRunning:
    LDA.w !Battle_WipeSteps
    BEQ .done
    LDA.b #1
.done:
    RTL

; ============================================================
; The window wipe ($CD:053C–$CD:0606)
; ============================================================
; Nine indirect HDMA tables of !BattleCD_HdmaTableBytes bytes each lie
; from !Battle_HdmaTables (BattleCD_NmiSetup points channels 0-6 at the
; first seven, BattleCD_SetWh0Table channel 7 at the last two). Each
; holds 3-byte entries (a line count and the address of the line data);
; the wipe moves the line counts of entries 1-3 (bytes 3, 6 and 9): the
; middle band grows or shrinks by 2 lines a step while the bands above
; and below give or take one line each. "Open" and "close" are inferred
; from when the two run (the battle's start and its end) and from the
; middle band growing in the first.

; $CD:053C — BattleCD_WipeStepOpen (59 bytes, $053C–$0576)
; One step of the opening wipe in all nine tables: entry 1's line count
; - 1, entry 2's + 2, entry 3's - 1; then the entry-2 data addresses of
; tables 5 and 3 (!Battle_HdmaTables+$E8 and +$8E) - 4.
; Callers (1 JSR site): BattleCD_StepWipe ($CD:05BE).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E (the tables are bank $7E .w)
; Exit:  M=1, X=0; A = 0 (B = 0); X = !BattleCD_HdmaTablesEnd; Y unchanged
BattleCD_WipeStepOpen:
    TDC
    TAX
.table:
    DEC.w !Battle_HdmaTables+3,X
    LDA.w !Battle_HdmaTables+6,X
    CLC
    ADC.b #2
    STA.w !Battle_HdmaTables+6,X
    DEC.w !Battle_HdmaTables+9,X
    REP #$20
    TXA
    CLC
    ADC.w #!BattleCD_HdmaTableBytes
    TAX
    TDC
    SEP #$20
    CPX.w #!BattleCD_HdmaTablesEnd
    BNE .table
    REP #$20
    LDA.w !Battle_HdmaTable5Mid
    SEC
    SBC.w #4
    STA.w !Battle_HdmaTable5Mid
    LDA.w !Battle_HdmaTable3Mid
    SEC
    SBC.w #4
    STA.w !Battle_HdmaTable3Mid
    TDC
    SEP #$20
    RTS

; $CD:0577 — BattleCD_WipeStepClose (59 bytes, $0577–$05B1)
; The opposite step: entry 1's line count + 1, entry 2's - 2, entry 3's
; + 1 in all nine tables; tables 3 and 5's entry-2 data addresses + 4.
; Callers (1 JSR site): BattleCD_StepWipe ($CD:05E5).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A = 0 (B = 0); X = !BattleCD_HdmaTablesEnd; Y unchanged
BattleCD_WipeStepClose:
    TDC
    TAX
.table:
    INC.w !Battle_HdmaTables+3,X
    LDA.w !Battle_HdmaTables+6,X
    SEC
    SBC.b #2
    STA.w !Battle_HdmaTables+6,X
    INC.w !Battle_HdmaTables+9,X
    REP #$20
    TXA
    CLC
    ADC.w #!BattleCD_HdmaTableBytes
    TAX
    TDC
    SEP #$20
    CPX.w #!BattleCD_HdmaTablesEnd
    BNE .table
    REP #$20
    LDA.w !Battle_HdmaTable3Mid
    CLC
    ADC.w #4
    STA.w !Battle_HdmaTable3Mid
    LDA.w !Battle_HdmaTable5Mid
    CLC
    ADC.w #4
    STA.w !Battle_HdmaTable5Mid
    TDC
    SEP #$20
    RTS

; $CD:05B2 — BattleCD_StepWipe (77 bytes, $05B2–$05FE)
; One step of the wipe in progress (BattleCD_NmiMain runs it twice a
; frame), by !Battle_WipeMode:
;   - 0: nothing;
;   - !BattleCD_WipeOpen ($FF, set by BattleCD_StartOpenWipe): first
;     !Battle_UnkCA25 = 0 and JSL BattleCE_UnkEE6E ($CE:EE6E, not matched;
;     A = !Battle_UnkCA22, set up the tables, probably), then the mode
;     becomes 1;
;   - 1-$7F: while !Battle_WipeSteps is non-zero, BattleCD_WipeStepOpen
;     and a step less; when that reaches 0, !Battle_UnkCA25 =
;     !BattleCD_CA25Unk02 and !Battle_UnkCA24 + 1; on the next call (no
;     steps left) !Battle_UnkCE16 = 0 and the mode = 0;
;   - $80-$FE (!BattleCD_WipeClose): BattleCD_WipeStepClose and a step
;     less; at 0, !Battle_UnkCA25 = 0, !Battle_UnkCA24 + 1 and the mode =
;     0 (!Battle_UnkCE16 kept).
; Callers (2 JSR sites): BattleCD_NmiMain ($CD:08F5, $CD:08F8).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E (as BattleCD_NmiMain sets it)
; Exit:  M=1, X=0 (assumed after the bank-$CE call, not traced); A, X
;        clobbered; Y unchanged unless that call changes it
BattleCD_StepWipe:
    LDA.w !Battle_WipeMode
    BEQ .done
    BMI .closing
    LDA.w !Battle_WipeSteps
    BEQ .finish
    JSR BattleCD_WipeStepOpen
    DEC.w !Battle_WipeSteps
    BNE .done
    LDA.b #!BattleCD_CA25Unk02
    STA.w !Battle_UnkCA25
    INC.w !Battle_UnkCA24
    BRA .done
.closing:
    CMP.b #!BattleCD_WipeOpen
    BNE .close_step
    STZ.w !Battle_UnkCA25
    LDA.w !Battle_UnkCA22
    JSL BattleCE_UnkEE6E
    LDA.b #1
    STA.w !Battle_WipeMode
    BRA .done
.close_step:
    JSR BattleCD_WipeStepClose
    DEC.w !Battle_WipeSteps
    BNE .done
    STZ.w !Battle_UnkCA25
    INC.w !Battle_UnkCA24
.finish:
    LDA.w !Battle_WipeMode
    BMI .stop
    STZ.w !Battle_UnkCE16
.stop:
    STZ.w !Battle_WipeMode
.done:
    RTS

; $CD:05FF — BattleCD_TileUploadVram (8 bytes, $05FF–$0606)
; VRAM word addresses for BattleCD_NmiUploadText's tilemap-page upload,
; by !Battle_TilePageSlot * 2: $7C00, $7C10, $7E00, $7E10.
BattleCD_TileUploadVram:
    dw $7C00,$7C10,$7E00,$7E10

; ============================================================
; The NMI work ($CD:0607–$CD:0CA0)
; ============================================================
; The bank-$D1 NMI handler ($D1:E77C, not matched) runs
; BattleCD_NmiDispatch every frame with M=1, X=0, DP=0 and DB=$00; it
; picks BattleCD_NmiSetup or BattleCD_NmiMain by !Battle_NmiMode.

; $CD:0607 — BattleCD_NmiUploadText (171 bytes, $0607–$06B1)
; BattleCD_NmiMain's uploads while no wipe runs:
;   - a tilemap page requested by the layer-effect script
;     (!Battle_TilePageReq, set by BattleCD_RunFxScript): unless it is
;     the same slot (!Battle_TilePageSlot) and page (!Battle_TilePageSrc)
;     as the last one (!Battle_LastPageSlot / !Battle_LastPageSrc),
;     JSL BattleD1_UploadPage ($D1:E8D9, not matched) with A:X = $7E:the
;     page and DP $45 = the BattleCD_TileUploadVram word, and
;     !Battle_UnkA01F + 1; the request and slot are cleared;
;   - the message text, half a frame: !Battle_TextHalf + 1; with a
;     message up (!Battle_MsgShown = !BattleCD_MsgShownOn) the half of
;     !Battle_TextGfxBuf it picks ($B400 to VRAM $5800 on odd counts,
;     $B600 to $5980 on even) goes up through BattleCD_DmaToVram ($200
;     bytes, DP $45); without one the same VRAM half is zeroed by a
;     fixed-source DMA on channel 7 from BattleCD_ZeroWord.
; Callers (1 JSR site): BattleCD_NmiMain ($CD:08A9).
; Entry: M=1, X=0, DP=0, DB=$7E (BattleCD_NmiMain sets it); B = 0
;        assumed for the 16-bit TAX (the NMI's TDC/SEP pairs leave it)
; Exit:  M=1, X=0, DP=0, DB=$7E (the zero-fill path saves and restores
;        it around its DB=$00 register writes); A, X, Y clobbered; DP
;        $45 written
BattleCD_NmiUploadText:
    LDA.w !Battle_TilePageReq
    BEQ .text
    STZ.w !Battle_TilePageReq
    LDA.w !Battle_TilePageSlot
    ASL A
    PHA
    STZ.w !Battle_TilePageSlot
    TAX
    REP #$20
    LDA.l BattleCD_TileUploadVram,X
    STA.b !BattleCD_Tmp45               ; the VRAM address
    TDC
    SEP #$20
    PLA
    CMP.w !Battle_LastPageSlot
    BNE .new_slot
    LDX.w !Battle_TilePageSrc
    CPX.w !Battle_LastPageSrc
    BEQ .text
    STX.w !Battle_LastPageSrc
    BRA .upload
.new_slot:
    STA.w !Battle_LastPageSlot
    LDX.w !Battle_TilePageSrc
    STX.w !Battle_LastPageSrc
.upload:
    LDX.w !Battle_TilePageSrc
    LDA.b #!Battle_WramBank
    JSL BattleD1_UploadPage
    INC.w !Battle_UnkA01F
.text:
    LDX.w #!BattleCD_TextHalfBytes
    STX.b !BattleCD_Tmp45               ; byte count for BattleCD_DmaToVram
    INC.w !Battle_TextHalf
    LDA.w !Battle_MsgShown
    CMP.b #!BattleCD_MsgShownOn
    BEQ .message
    PHB
    LDA.b #0
    PHA
    PLB                                 ; DB = $00 for the registers
    LDA.l !Battle_WramLong+!Battle_TextHalf
    AND.b #1
    BEQ .zero_low
    LDX.w #!BattleCD_TextVramA
    BRA .zero
.zero_low:
    LDX.w #!BattleCD_TextVramB
.zero:
    STX.w VMADDL
    LDA.b #!DMAP_FixedSource|!DMAP_TwoRegs
    STA.w DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD7
    LDX.w #BattleCD_ZeroWord&$FFFF
    STX.w A1T7L
    LDA.b #BattleCD_ZeroWord>>16
    STA.w A1B7
    LDX.w #!BattleCD_TextHalfBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    PLB
    RTS
.message:
    LDA.l !Battle_WramLong+!Battle_TextHalf
    AND.b #1
    BEQ .message_low
    LDX.w #!Battle_TextGfxBuf
    LDY.w #!BattleCD_TextVramA
    LDA.b #!Battle_WramBank
    JMP BattleCD_DmaToVram
.message_low:
    LDX.w #!Battle_TextGfxBuf+!BattleCD_TextHalfBytes
    LDY.w #!BattleCD_TextVramB
    LDA.b #!Battle_WramBank
    JMP BattleCD_DmaToVram

; $CD:06B2 — BattleCD_ZeroWord (2 bytes, $06B2–$06B3)
; The fixed DMA source BattleCD_NmiUploadText clears VRAM from.
BattleCD_ZeroWord:
    dw $0000

; $CD:06B4 — BattleCD_NmiLayerScroll (8 bytes, $06B4–$06BB)
; Runs the BattleCD_ScrollModeTable entry !Battle_LayerFxMode (0-3; set
; to 0 or 1 by BattleCD_StepFxChannels and 0 by BattleCD_EndLayerFx; who
; sets 2 and 3 is not traced): the HDMA scroll data for this frame.
; Callers (1 JSR site): BattleCD_NmiMain ($CD:0929).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 assumed for the 16-bit TAX (the
;        NMI's TDC/SEP pairs leave it)
; Exit:  as the handler: M=1, X=0; A, X clobbered; Y's high byte cleared
;        (each handler's SEP #$10); DP $1A-$1F and $45-$50 written
BattleCD_NmiLayerScroll:
    LDA.w !Battle_LayerFxMode
    ASL A
    TAX
    JMP (BattleCD_ScrollModeTable,X)

; $CD:06BC — BattleCD_ScrollModeTable (4 words, $06BC–$06C3)
; BattleCD_NmiLayerScroll's handlers by !Battle_LayerFxMode.
BattleCD_ScrollModeTable:
    dw BattleCD_ScrollPlain             ; 0: the battle's scroll
    dw BattleCD_ScrollFxBg3             ; 1: layer 3 from the effect's scroll
    dw BattleCD_ScrollWaves             ; 2: with the per-line offsets
    dw BattleCD_ScrollWavesBg3          ; 3: 2, and a second half for layer 3

; $CD:06C4 — BattleCD_ScrollPlain (168 bytes, $06C4–$076B)
; Fills the HDMA scroll data of layers 1-3 (!Battle_HdmaScroll1-3, 32
; entries of 4 bytes, an x and a y word, each) with one x/y pair per
; layer: FieldBtlPpu.Scroll2's words (the battle's layer scroll) plus
; the shake offsets (!Battle_ShakeOfs1X ... !Battle_ShakeOfs3Y,
; BattleCD_StepShake), plus !Battle_ScrollAddX/Y for layer 1. The pairs
; go to DP $45-$4F first (layer 1 x, y; 2 x, y; 3 x, y). The fill loop
; from $0706 (BattleCD_ScrollFill) is shared with BattleCD_ScrollFxBg3.
; The loop counts X in 8 bits (SEP #$10) and stores four entries a pass.
; Callers (1 JSR site): BattleCD_NmiSetup ($CD:0ACC).
; Callers of BattleCD_ScrollFill (1 JMP site): BattleCD_ScrollFxBg3 ($CD:07B6).
; Callers note: also BattleCD_ScrollModeTable entry 0 (JMP (T,X) in
;   BattleCD_NmiLayerScroll).
; Entry: M=1, X=0 (SEP #$10 here, REP #$10 at the end), DP=0, DB=$7E
; Exit:  M=1, X=0 (X = $0080: the 8-bit loop ends at $80, and the high
;        byte was cleared by the SEP #$10); A = 0 (B = 0); Y's low byte
;        kept, its high byte cleared (SEP #$10 at $CD:06C4); DP $45-$50
;        written
; Sub-entry: BattleCD_ScrollFill ($0706), JMP'd from BattleCD_ScrollFxBg3
;   with M=0, X=1 and the pairs in DP $45-$4F; exits as above.
BattleCD_ScrollPlain:
    SEP #$10
    REP #$20
    LDA.w FieldBtlPpu.Scroll2
    CLC
    ADC.w !Battle_ShakeOfs1X
    CLC
    ADC.w !Battle_ScrollAddX
    STA.b !BattleCD_Tmp45
    LDA.w FieldBtlPpu.Scroll2+2
    CLC
    ADC.w !Battle_ShakeOfs1Y
    CLC
    ADC.w !Battle_ScrollAddY
    STA.b !BattleCD_Tmp47
    LDA.w FieldBtlPpu.Scroll2+4
    CLC
    ADC.w !Battle_ShakeOfs2X
    STA.b !BattleCD_Tmp49
    LDA.w FieldBtlPpu.Scroll2+6
    CLC
    ADC.w !Battle_ShakeOfs2Y
    STA.b !BattleCD_Tmp4B
    LDA.w FieldBtlPpu.Scroll2+8
    CLC
    ADC.w !Battle_ShakeOfs3X
    STA.b !BattleCD_Tmp4D
    LDA.w FieldBtlPpu.Scroll2+10
    CLC
    ADC.w !Battle_ShakeOfs3Y
    STA.b !BattleCD_Tmp4F
BattleCD_ScrollFill:                    ; header: see BattleCD_ScrollPlain
    LDX.b #0
.entries:
    LDA.b !BattleCD_Tmp45
    STA.w !Battle_HdmaScroll1,X
    STA.w !Battle_HdmaScroll1+4,X
    STA.w !Battle_HdmaScroll1+8,X
    STA.w !Battle_HdmaScroll1+12,X
    LDA.b !BattleCD_Tmp47
    STA.w !Battle_HdmaScroll1+2,X
    STA.w !Battle_HdmaScroll1+6,X
    STA.w !Battle_HdmaScroll1+10,X
    STA.w !Battle_HdmaScroll1+14,X
    LDA.b !BattleCD_Tmp49
    STA.w !Battle_HdmaScroll2,X
    STA.w !Battle_HdmaScroll2+4,X
    STA.w !Battle_HdmaScroll2+8,X
    STA.w !Battle_HdmaScroll2+12,X
    LDA.b !BattleCD_Tmp4B
    STA.w !Battle_HdmaScroll2+2,X
    STA.w !Battle_HdmaScroll2+6,X
    STA.w !Battle_HdmaScroll2+10,X
    STA.w !Battle_HdmaScroll2+14,X
    LDA.b !BattleCD_Tmp4D
    STA.w !Battle_HdmaScroll3,X
    STA.w !Battle_HdmaScroll3+4,X
    STA.w !Battle_HdmaScroll3+8,X
    STA.w !Battle_HdmaScroll3+12,X
    LDA.b !BattleCD_Tmp4F
    STA.w !Battle_HdmaScroll3+2,X
    STA.w !Battle_HdmaScroll3+6,X
    STA.w !Battle_HdmaScroll3+10,X
    STA.w !Battle_HdmaScroll3+14,X
    TXA
    CLC
    ADC.w #!BattleCD_ScrollPassBytes
    TAX
    CPX.b #!BattleCD_ScrollFillEnd
    BNE .entries
    TDC
    SEP #$20
    REP #$10
    RTS

; $CD:076C — BattleCD_ScrollFxBg3 (77 bytes, $076C–$07B8)
; As BattleCD_ScrollPlain, but layer 3's pair is the effect's scroll:
; !Battle_FxScrollX + !Battle_FxScrollAddX + !Battle_ShakeOfs3X and
; !Battle_FxScrollY + !Battle_FxScrollAddY + !Battle_ShakeOfs3Y; then
; JMP BattleCD_ScrollFill.
; Callers note: none by call; BattleCD_ScrollModeTable entry 1 (JMP (T,X)
;   in BattleCD_NmiLayerScroll).
; Entry: M=1, X=0 (SEP #$10 here), DP=0, DB=$7E
; Exit:  as BattleCD_ScrollPlain (through BattleCD_ScrollFill)
BattleCD_ScrollFxBg3:
    SEP #$10
    REP #$20
    LDA.w FieldBtlPpu.Scroll2
    CLC
    ADC.w !Battle_ShakeOfs1X
    CLC
    ADC.w !Battle_ScrollAddX
    STA.b !BattleCD_Tmp45
    LDA.w FieldBtlPpu.Scroll2+2
    CLC
    ADC.w !Battle_ShakeOfs1Y
    CLC
    ADC.w !Battle_ScrollAddY
    STA.b !BattleCD_Tmp47
    LDA.w FieldBtlPpu.Scroll2+4
    CLC
    ADC.w !Battle_ShakeOfs2X
    STA.b !BattleCD_Tmp49
    LDA.w FieldBtlPpu.Scroll2+6
    CLC
    ADC.w !Battle_ShakeOfs2Y
    STA.b !BattleCD_Tmp4B
    LDA.w !Battle_FxScrollX
    CLC
    ADC.w !Battle_FxScrollAddX
    CLC
    ADC.w !Battle_ShakeOfs3X
    STA.b !BattleCD_Tmp4D
    LDA.w !Battle_FxScrollY
    CLC
    ADC.w !Battle_FxScrollAddY
    CLC
    ADC.w !Battle_ShakeOfs3Y
    STA.b !BattleCD_Tmp4F
    JMP BattleCD_ScrollFill

; $CD:07B9 — BattleCD_ScrollWavesBg3 (41 bytes, $07B9–$07E1)
; BattleCD_ScrollWaves, then a second run of 32 entries for layer 3 only
; (X from $80 up to the 8-bit wrap): x = layer 3's x pair, plus the
; per-line offset in !Battle_WaveOffsets (the same X) when
; !Battle_WaveBg3 is set; y = layer 3's y.
; Callers note: none by call; BattleCD_ScrollModeTable entry 3 (JMP
;   (T,X) in BattleCD_NmiLayerScroll).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0 (X = 0: the 8-bit loop wraps to 0 before REP #$10); A
;        = 0 (B = 0); Y's low byte kept, its high byte cleared (the SEP
;        #$10 in BattleCD_ScrollWaves); DP $1A-$1F and $45-$50 written
BattleCD_ScrollWavesBg3:
    JSR BattleCD_ScrollWaves
    REP #$20
    SEP #$10
.entry:
    LDA.b !BattleCD_WaveBg3On
    BNE .wave
    LDA.b !BattleCD_Tmp4D
    BRA .store
.wave:
    LDA.w !Battle_WaveOffsets,X
    CLC
    ADC.b !BattleCD_Tmp4D
.store:
    STA.w !Battle_HdmaScroll3,X
    LDA.b !BattleCD_Tmp4F
    STA.w !Battle_HdmaScroll3+2,X
    INX
    INX
    INX
    INX
    BNE .entry
    TDC
    SEP #$20
    REP #$10
    RTS

; $CD:07E2 — BattleCD_ScrollWaves (171 bytes, $07E2–$088C)
; The pairs as BattleCD_ScrollFxBg3 computes them (in DP $45-$4F); then
; for each of the 32 entries the x of a layer gets the entry's per-line
; offset from !Battle_WaveOffsets (bank $7E, by the entry's byte offset)
; added when that layer's flag is set (!Battle_WaveBg1/2/3, copied to DP
; $1A/$1C/$1E first); the y words are stored as they are.
; Callers (1 JSR site): BattleCD_ScrollWavesBg3 ($CD:07B9).
; Callers note: also BattleCD_ScrollModeTable entry 2 (JMP (T,X) in
;   BattleCD_NmiLayerScroll).
; Entry: M=1, X=0 (SEP #$10 here), DP=0, DB=$7E
; Exit:  M=1, X=0 (X = $0080, as BattleCD_ScrollPlain); A = 0 (B = 0);
;        Y's low byte kept, its high byte cleared (SEP #$10 at $CD:07E2);
;        DP $1A-$1F and $45-$50 written
BattleCD_ScrollWaves:
    SEP #$10
    REP #$20
    LDA.w FieldBtlPpu.Scroll2
    CLC
    ADC.w !Battle_ShakeOfs1X
    CLC
    ADC.w !Battle_ScrollAddX
    STA.b !BattleCD_Tmp45
    LDA.w FieldBtlPpu.Scroll2+2
    CLC
    ADC.w !Battle_ShakeOfs1Y
    CLC
    ADC.w !Battle_ScrollAddY
    STA.b !BattleCD_Tmp47
    LDA.w FieldBtlPpu.Scroll2+4
    CLC
    ADC.w !Battle_ShakeOfs2X
    STA.b !BattleCD_Tmp49
    LDA.w FieldBtlPpu.Scroll2+6
    CLC
    ADC.w !Battle_ShakeOfs2Y
    STA.b !BattleCD_Tmp4B
    LDA.w !Battle_FxScrollX
    CLC
    ADC.w !Battle_FxScrollAddX
    CLC
    ADC.w !Battle_ShakeOfs3X
    STA.b !BattleCD_Tmp4D
    LDA.w !Battle_FxScrollY
    CLC
    ADC.w !Battle_FxScrollAddY
    CLC
    ADC.w !Battle_ShakeOfs3Y
    STA.b !BattleCD_Tmp4F
    LDA.w !Battle_WaveBg1
    STA.b !BattleCD_WaveBg1On
    LDA.w !Battle_WaveBg2
    STA.b !BattleCD_WaveBg2On
    LDA.w !Battle_WaveBg3
    STA.b !BattleCD_WaveBg3On
    LDX.b #0
.entry:
    LDA.b !BattleCD_WaveBg1On
    BNE .wave1
    LDA.b !BattleCD_Tmp45
    BRA .store1
.wave1:
    LDA.w !Battle_WaveOffsets,X
    CLC
    ADC.b !BattleCD_Tmp45
.store1:
    STA.w !Battle_HdmaScroll1,X
    LDA.b !BattleCD_WaveBg2On
    BNE .wave2
    LDA.b !BattleCD_Tmp49
    BRA .store2
.wave2:
    LDA.w !Battle_WaveOffsets,X
    CLC
    ADC.b !BattleCD_Tmp49
.store2:
    STA.w !Battle_HdmaScroll2,X
    LDA.b !BattleCD_WaveBg3On
    BNE .wave3
    LDA.b !BattleCD_Tmp4D
    BRA .store3
.wave3:
    LDA.w !Battle_WaveOffsets,X
    CLC
    ADC.b !BattleCD_Tmp4D
.store3:
    STA.w !Battle_HdmaScroll3,X
    LDA.b !BattleCD_Tmp47
    STA.w !Battle_HdmaScroll1+2,X
    LDA.b !BattleCD_Tmp4B
    STA.w !Battle_HdmaScroll2+2,X
    LDA.b !BattleCD_Tmp4F
    STA.w !Battle_HdmaScroll3+2,X
    INX
    INX
    INX
    INX
    CPX.b #!BattleCD_ScrollFillEnd
    BNE .entry
    TDC
    SEP #$20
    REP #$10
    RTS

; $CD:088D — BattleCD_NmiMain (321 bytes, $088D–$09CD)
; The NMI's work in modes 1 and 2 (BattleCD_NmiDispatch), entered with
; DB=$00:
;   - with !Battle_CgramPending ($7E:CE0F) set: the palette
;     (BattleCD_UploadCgram), DB=$7E, the queued VRAM upload
;     (BattleCD_RunQueuedDma), and on to the registers; else DB=$7E, the
;     text and tilemap uploads (BattleCD_NmiUploadText) unless a wipe
;     runs, BattleCD_RunQueuedDma, and the bank-$CF vblank uploads
;     (BankC1_VecCFE300) unless !Battle_Paused;
;   - the window registers W12SEL, W34SEL, WOBJSEL, WBGLOG, WOBJLOG from
;     !Battle_WinRegs; !Battle_HdmaColData = !Battle_WinRegs+5; the words
;     !Battle_UnkC151/C153 from !Battle_UnkC155/C157;
;   - channel 7's window table (BattleCD_SetWh0Table, with DB=$00 around
;     it); two wipe steps (BattleCD_StepWipe); HDMAEN = !Battle_HdmaEnable;
;   - paused (!Battle_Paused): INIDISP = !Battle_Brightness, halved
;     unless the ROM byte !BattleRom_PauseFullBright is non-zero (it is
;     0, so the screen is dimmed); the pad (BankC2_Entry8002,
;     BattleCD_PadRepeat); RTS;
;   - else INIDISP = !Battle_Brightness; the scroll data
;     (BattleCD_NmiLayerScroll); the shake (BattleCD_StepShake); on even
;     frames with no wipe: when !Battle_UnkEC differs from
;     !Battle_UnkCA21, the latter toggles (0/1) and !Battle_UnkEC takes
;     its value; and while
;     !Battle_UnkCD27 bit 5 is clear a new press of !Battle_PadHeld bit 0
;     toggles them once more (!Battle_UnkCA23 holds it until the button
;     is let go);
;   - with !Battle_Unk2A21 bit 0: JSL BattleCE_UnkE18E, and on the frames
;     where !Battle_FrameCount AND !Battle_UnkCE13 is 0 JSL
;     BattleD1_UnkEA4B (not matched);
;   - unless !Battle_UnkCD2D or !Battle_UnkA028: JSL BattleCE_UnkF066;
;     BankC1_VecCFE58A (the bank-$CF frame update); unless !Battle_UnkCD2E
;     or !Battle_UnkA028, while an action runs, BattleCD_Unk3B82 with A =
;     !BattleCD_Unk3B82Arg;
;   - the layer effect's script channels (BattleCD_StepFxChannels);
;     !Battle_UnkA028 = !Battle_UnkCD29; BattleCD_ClampPalAnims; JSL
;     BattleD1_UnkF426 (not matched) and FdVec_FFF7 (the palette
;     animations, PalAnim_TickAll);
;     BattleCD_TickCDC9; the pad (BankC2_Entry8002, BattleCD_PadRepeat).
; Callers note: none by call; BattleCD_NmiTable entries 1 and 2 (JSR (T,X)
;   in BattleCD_NmiDispatch).
; Entry: M=1, X=0, DP=0, DB=$00 (from the NMI handler; BattleCD_UploadCgram
;        writes the registers .w); B = 0 assumed for the 16-bit TAXs of
;        the callees
; Exit:  M=1, X=0, DP=0, DB=$7E (set here; the callees keep it, assumed
;        for the ones not matched); A, X, Y clobbered
BattleCD_NmiMain:
    LDA.l !Battle_WramLong+!Battle_CgramPending
    BEQ .uploads
    JSL BattleCD_UploadCgram
    LDA.b #!Battle_WramBank
    PHA
    PLB
    JSR BattleCD_RunQueuedDma
    BRA .regs
.uploads:
    LDA.b #!Battle_WramBank
    PHA
    PLB
    LDA.w !Battle_WipeMode
    BNE .queued
    JSR BattleCD_NmiUploadText
.queued:
    JSR BattleCD_RunQueuedDma
    LDA.w !Battle_Paused
    BNE .regs
    JSL BankC1_VecCFE300
.regs:
    LDA.w !Battle_WinRegs
    STA.l W12SEL
    LDA.w !Battle_WinRegs+1
    STA.l W34SEL
    LDA.w !Battle_WinRegs+2
    STA.l WOBJSEL
    LDA.w !Battle_WinRegs+3
    STA.l WBGLOG
    LDA.w !Battle_WinRegs+4
    STA.l WOBJLOG
    LDA.w !Battle_WinRegs+5
    STA.w !Battle_HdmaColData
    LDX.w !Battle_UnkC155
    STX.w !Battle_UnkC151
    LDX.w !Battle_UnkC157
    STX.w !Battle_UnkC153
    PHB
    TDC
    PHA
    PLB                                 ; DB = $00
    JSR BattleCD_SetWh0Table
    PLB
    JSR BattleCD_StepWipe
    JSR BattleCD_StepWipe
    LDA.w !Battle_HdmaEnable
    STA.l HDMAEN
    LDA.w !Battle_Paused
    BEQ .running
    LDA.l !BattleRom_PauseFullBright
    BEQ .dim
    LDA.w !Battle_Brightness
    BRA .brightness
.dim:
    LDA.w !Battle_Brightness
    LSR A
.brightness:
    STA.l INIDISP
    JSL BankC2_Entry8002
    JSR BattleCD_PadRepeat
    RTS
.running:
    LDA.w !Battle_Brightness
    STA.l INIDISP
    JSR BattleCD_NmiLayerScroll
    JSR BattleCD_StepShake
    LDA.b !Battle_FrameCount
    AND.b #1
    BNE .bank_ce
    LDA.w !Battle_WipeMode
    BNE .bank_ce
    LDA.b !Battle_UnkEC
    CMP.w !Battle_UnkCA21
    BEQ .button
    LDA.w !Battle_UnkCA21
    INC A
    AND.b #1
    STA.w !Battle_UnkCA21
    STA.b !Battle_UnkEC
.button:
    LDA.w !Battle_UnkCD27
    AND.b #!Battle_CD27Bit5
    BNE .released
    LDA.b !Battle_PadHeld
    AND.b #!BattleCD_PadToggleBit
    BEQ .released
    LDA.w !Battle_UnkCA23
    BNE .bank_ce
    LDA.w !Battle_UnkCA21
    INC A
    AND.b #1
    STA.w !Battle_UnkCA21
    STA.b !Battle_UnkEC
    LDA.b #1
    STA.w !Battle_UnkCA23
    BRA .bank_ce
.released:
    STZ.w !Battle_UnkCA23
.bank_ce:
    LDA.w !Battle_Unk2A21
    AND.b #!Battle_2A21Bit0
    BEQ .unk_ce_f066
    JSL BattleCE_UnkE18E
    LDA.b !Battle_FrameCount
    AND.w !Battle_UnkCE13
    BNE .unk_ce_f066
    JSL BattleD1_UnkEA4B
.unk_ce_f066:
    LDA.w !Battle_UnkCD2D
    BNE .frame_update
    LDA.w !Battle_UnkA028
    BNE .frame_update
    JSL BattleCE_UnkF066
.frame_update:
    JSL BankC1_VecCFE58A
    LDA.w !Battle_UnkCD2E
    BNE .channels
    LDA.w !Battle_ActRunning
    BEQ .channels
    LDA.w !Battle_UnkA028
    BNE .channels
    LDA.b #!BattleCD_Unk3B82Arg
    JSR BattleCD_Unk3B82
.channels:
    JSR BattleCD_StepFxChannels
    LDA.w !Battle_UnkCD29
    STA.w !Battle_UnkA028
    JSR BattleCD_ClampPalAnims
    JSL BattleD1_UnkF426
    JSL FdVec_FFF7
    JSR BattleCD_TickCDC9
    JSL BankC2_Entry8002
    JSR BattleCD_PadRepeat
    RTS

; $CD:09CE — BattleCD_UploadCgram (35 bytes, $09CE–$09F0)
; Copies the whole palette, !Battle_CgramBytes bytes of
; !Battle_PaletteLiveLo (bank $7E), to CGRAM from colour 0 by DMA on
; channel 7 (one register written twice: CGDATA). DAS7B is zeroed
; first.
; Callers (3 JSL sites): BattleCD_NmiMain ($CD:0893), BattleCD_NmiSetup ($CD:09F1) and unmatched
;   ($D1:F4DE).
; Entry: M=1, X=0 (the 16-bit STX pairs), DP any, DB=$00 (the registers
;        are written .w; both callers in this bank have DB=$00, the
;        bank-$D1 one is not traced)
; Exit:  M=1, X=0; A = !MDMAEN_Ch7; X = !Battle_CgramBytes; Y, DP, DB
;        unchanged
BattleCD_UploadCgram:
    STZ.w DAS7B
    STZ.w CGADD
    LDX.w #(!BBAD_CGDATA<<8)|!DMAP_OneRegTwice
    STX.w DMAP7
    LDX.w #!Battle_PaletteLiveLo
    STX.w A1T7L
    LDA.b #!Battle_WramBank
    STA.w A1B7
    LDX.w #!Battle_CgramBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    RTL

; $CD:09F1 — BattleCD_NmiSetup (237 bytes, $09F1–$0ADD)
; The NMI's work in mode 0 (the first frames, until BattleCD_SetNmiMode1):
; the palette (BattleCD_UploadCgram); HDMA channels 0-6 set up as
; indirect channels on the first seven tables of !Battle_HdmaTables (the
; line data in bank $7E): 0 BG1SC-BG4SC (4 registers), 1-3 the BG1, BG2
; and BG3 scroll pairs (2 registers each written twice), 4 TM-TSW, 5
; CGWSEL-SETINI (4 registers each), 6 BGMODE/MOSAIC (2 registers); then
; with DB=$7E: JSL BankC1_VecCCE000 when !Battle_UnkCAD3 is set; with
; DB=$00: channel 7 (BattleCD_SetWh0Table), HDMAEN = $FF (all eight),
; INIDISP = !Battle_Brightness; back to DB=$7E: the scroll data
; (BattleCD_ScrollPlain), BattleCD_ClampPalAnims, JSL BattleD1_UnkF426
; and FdVec_FFF7 (the palette animations), BattleCD_TickCDC9.
; Callers note: none by call; BattleCD_NmiTable entry 0 (JSR (T,X) in
;   BattleCD_NmiDispatch).
; Entry: M=1, X=0, DP=0, DB=$00 (from the NMI handler)
; Exit:  M=1, X=0, DP=0, DB=$7E (set here); A, X, Y clobbered
BattleCD_NmiSetup:
    JSL BattleCD_UploadCgram
    LDA.b #!DMAP_HdmaIndirect|!DMAP_FourRegs
    STA.w DMAP0
    LDA.b #!BBAD_BG1SC
    STA.w BBAD0
    LDX.w #!Battle_HdmaTables
    STX.w A1T0L
    LDA.b #!Battle_WramBank
    STA.w A1B0
    LDA.b #!Battle_WramBank
    STA.w DAS0B
    LDA.b #!DMAP_HdmaIndirect|!DMAP_TwoRegsTwice
    STA.w DMAP1
    LDA.b #!BBAD_BG1HOFS
    STA.w BBAD1
    LDX.w #!Battle_HdmaTables+(!BattleCD_HdmaTableBytes*1)
    STX.w A1T1L
    LDA.b #!Battle_WramBank
    STA.w A1B1
    LDA.b #!Battle_WramBank
    STA.w DAS1B
    LDA.b #!DMAP_HdmaIndirect|!DMAP_TwoRegsTwice
    STA.w DMAP2
    LDA.b #!BBAD_BG2HOFS
    STA.w BBAD2
    LDX.w #!Battle_HdmaTables+(!BattleCD_HdmaTableBytes*2)
    STX.w A1T2L
    LDA.b #!Battle_WramBank
    STA.w A1B2
    LDA.b #!Battle_WramBank
    STA.w DAS2B
    LDA.b #!DMAP_HdmaIndirect|!DMAP_TwoRegsTwice
    STA.w DMAP3
    LDA.b #!BBAD_BG3HOFS
    STA.w BBAD3
    LDX.w #!Battle_HdmaTables+(!BattleCD_HdmaTableBytes*3)
    STX.w A1T3L
    LDA.b #!Battle_WramBank
    STA.w A1B3
    LDA.b #!Battle_WramBank
    STA.w DAS3B
    LDA.b #!DMAP_HdmaIndirect|!DMAP_FourRegs
    STA.w DMAP4
    LDA.b #!BBAD_TM
    STA.w BBAD4
    LDX.w #!Battle_HdmaTables+(!BattleCD_HdmaTableBytes*4)
    STX.w A1T4L
    LDA.b #!Battle_WramBank
    STA.w A1B4
    LDA.b #!Battle_WramBank
    STA.w DAS4B
    LDA.b #!DMAP_HdmaIndirect|!DMAP_FourRegs
    STA.w DMAP5
    LDA.b #!BBAD_CGWSEL
    STA.w BBAD5
    LDX.w #!Battle_HdmaTables+(!BattleCD_HdmaTableBytes*5)
    STX.w A1T5L
    LDA.b #!Battle_WramBank
    STA.w A1B5
    LDA.b #!Battle_WramBank
    STA.w DAS5B
    LDA.b #!DMAP_HdmaIndirect|!DMAP_TwoRegs
    STA.w DMAP6
    LDA.b #!BBAD_BGMODE
    STA.w BBAD6
    LDX.w #!Battle_HdmaTables+(!BattleCD_HdmaTableBytes*6)
    STX.w A1T6L
    LDA.b #!Battle_WramBank
    STA.w A1B6
    LDA.b #!Battle_WramBank
    STA.w DAS6B
    LDA.b #!Battle_WramBank
    PHA
    PLB                                 ; DB = $7E
    LDA.w !Battle_UnkCAD3
    BEQ .no_cc
    JSL BankC1_VecCCE000
.no_cc:
    PHB
    TDC
    PHA
    PLB                                 ; DB = $00
    JSR BattleCD_SetWh0Table
    LDA.b #!BattleCD_AllHdma
    STA.w HDMAEN
    LDA.l !Battle_WramLong+!Battle_Brightness
    STA.w INIDISP
    PLB
    JSR BattleCD_ScrollPlain
    JSR BattleCD_ClampPalAnims
    JSL BattleD1_UnkF426
    JSL FdVec_FFF7
    JSR BattleCD_TickCDC9
    RTS

; $CD:0ADE — BattleCD_TickCDC9 (16 bytes, $0ADE–$0AED)
; While FieldAnimB[0].Unk4 (palette animation record 0's frame counter)
; is 0: !Battle_UnkCDC9 counts down and wraps from
; below 0 to !BattleCD_CDC9Period (a 14-frame cycle, 13 down to 0; what
; reads it is not traced).
; Callers (2 JSR sites): BattleCD_NmiMain ($CD:09C3) and BattleCD_NmiSetup ($CD:0ADA).
; Entry: M=1, X any, DP any, DB=$7E
; Exit:  M=1; A clobbered; X, Y unchanged
BattleCD_TickCDC9:
    LDA.w FieldAnimB[0].Unk4
    BNE .done
    DEC.w !Battle_UnkCDC9
    BPL .done
    LDA.b #!BattleCD_CDC9Period
    STA.w !Battle_UnkCDC9
.done:
    RTS

; $CD:0AEE — BattleCD_SetWh0Table (40 bytes, $0AEE–$0B15)
; Points HDMA channel 7 at one of the last two tables of
; !Battle_HdmaTables (indirect, 4 registers from WH0, line data in bank
; $7E): table 8 on odd frames of !Battle_FrameCount, table 7 on even
; ones (a double buffer, probably).
; Callers (2 JSR sites): BattleCD_NmiMain ($CD:08F1) and BattleCD_NmiSetup ($CD:0ABC).
; Entry: M=1, X=0 (16-bit STX), DP=0, DB=$00 (both callers set it; the
;        registers are written .w)
; Exit:  M=1, X=0; A, X clobbered; Y, DP, DB unchanged
BattleCD_SetWh0Table:
    LDA.b #!DMAP_HdmaIndirect|!DMAP_FourRegs
    STA.w DMAP7
    LDA.b #!BBAD_WH0
    STA.w BBAD7
    LDA.b #!Battle_WramBank
    STA.w DAS7B
    LDA.b #!Battle_WramBank
    STA.w A1B7
    LDA.b !Battle_FrameCount
    AND.b #1
    BEQ .even
    LDX.w #!Battle_HdmaTables+(!BattleCD_HdmaTableBytes*8)
    STX.w A1T7L
    RTS
.even:
    LDX.w #!Battle_HdmaTables+(!BattleCD_HdmaTableBytes*7)
    STX.w A1T7L
    RTS

; $CD:0B16 — BattleCD_RandByte (8 bytes, $0B16–$0B1D)
; A = RandomTable entry (A + !Battle_FrameCount + C) & $FF: a byte of
; the field's random table picked by the frame count.
; Callers (8 JSR sites): BattleCD_StepShake ($CD:0B72, $CD:0BD7) and unmatched ($CD:1A14, $CD:1A1E,
;   $CD:1A28, $CD:1A32, $CD:1A3C, $CD:1A46).
; Entry: M=1, X=0, DP=0, DB any (the table is read long); A and C as the
;        caller leaves them (both callers come with C=1); B = 0 (the
;        16-bit TAX; the NMI code's TDC/SEP pairs leave it, assumed)
; Exit:  M=1; A = the byte; X = the index; Y unchanged
BattleCD_RandByte:
    ADC.b !Battle_FrameCount
    TAX
    LDA.l RandomTable,X
    RTS

; $CD:0B1E — BattleCD_ClampPalAnims (51 bytes, $0B1E–$0B50)
; With !Battle_Unk99D2 positive and non-zero: for each of the palette
; animation records 8-11 (FieldAnimB, 12 bytes each, the ones the battle
; fills) with a kind (.Unk0 non-zero) and a first colour (.Unk1) below
; $80, the colour count (.Unk2) is cut down so that first colour + count
; is at most !Battle_Unk99D3 (8-bit sum, unsigned compare): the
; animations stay below the colours that start there.
; Callers (3 JSR sites): BattleCD_NmiMain ($CD:09B8), BattleCD_NmiSetup ($CD:0ACF) and unmatched
;   ($CD:702C).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E (the records at $0580 are read .w in
;        bank $7E's low mirror)
; Exit:  M=1, X=0; A clobbered; X = !BattleCD_PalAnims8To11 or unchanged
;        (when it returns at once); Y unchanged
BattleCD_ClampPalAnims:
    LDA.w !Battle_Unk99D2
    BMI .done
    BEQ .done
    TDC
    TAX
.record:
    LDA.w FieldAnimB[8].Unk0,X
    BEQ .next
    LDA.w FieldAnimB[8].Unk1,X
    BMI .next
    CLC
    ADC.w FieldAnimB[8].Unk2,X
    CMP.w !Battle_Unk99D3
    BEQ .next
    BCC .next
    LDA.w !Battle_Unk99D3
    SEC
    SBC.w FieldAnimB[8].Unk1,X
    STA.w FieldAnimB[8].Unk2,X
.next:
    TXA
    CLC
    ADC.b #!BattleCD_PalAnimBytes
    TAX
    CPX.w #!BattleCD_PalAnims8To11
    BNE .record
.done:
    RTS

; $CD:0B51 — BattleCD_StepShake (306 bytes, $0B51–$0C82)
; The screen shake, once a frame, for two axes:
;   - x (!Battle_ShakeXOn): every !Battle_ShakeXRandPeriod frames a new
;     random byte (BattleCD_RandByte) in !Battle_ShakeXRand; every
;     !Battle_ShakeXStepPeriod frames !Battle_ShakeXAmp steps one toward
;     !Battle_ShakeXTarget, and reaching 0 on the way down ends the shake
;     (!Battle_ShakeXOn = 0); the offset is the high byte of random *
;     amplitude (WRMPYA/WRMPYB, RDMPYH). With the axis off the offsets
;     !Battle_ShakeOfs1X/2X/3X are zeroed and the value is 0.
;   - y (!Battle_ShakeYOn ...): the same with its own bytes, the random
;     byte drawn with A = $40, offsets !Battle_ShakeOfs1Y/2Y/3Y.
; !Battle_ShakeLayers then picks which offsets get the values: bits 7-2
; for layer 1 x, 1 y, 2 x, 2 y, 3 x, 3 y (stored 16-bit: x value from Y,
; y value from X, the high bytes 0).
; Last, the !Battle_PalAnimCopy requests: bit 7 copies
; !Battle_PalAnimRec10 (12 bytes) to palette animation record 10
; (FieldAnimB[10]) by MVN and clears bit 7 (and returns); any other bit
; copies !Battle_PalAnimRecs89 (24 bytes) to records 8 and 9 and clears
; bit 0.
; Quirk: the x axis's random draw passes whatever A holds
; (!Battle_ShakeXRandTime, the frames since the last draw, at or above
; !Battle_ShakeXRandPeriod) to BattleCD_RandByte. Kept as found.
; Callers (1 JSR site): BattleCD_NmiMain ($CD:092C).
; Entry: M=1, X=0, DP=0, DB=$7E (as BattleCD_NmiMain runs; MVN sets
;        DB=$7E again); B = 0 assumed for the TAXs
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $45 and $47
;        written
BattleCD_StepShake:
    LDA.w !Battle_ShakeXOn
    BNE .x_on
    TAX
    STX.w !Battle_ShakeOfs1X
    STX.w !Battle_ShakeOfs2X
    STX.w !Battle_ShakeOfs3X
    STA.b !BattleCD_Tmp45
    BRA .y
.x_on:
    INC.w !Battle_ShakeXRandTime
    LDA.w !Battle_ShakeXRandTime
    CMP.w !Battle_ShakeXRandPeriod
    BCC .x_mul
    STZ.w !Battle_ShakeXRandTime
    JSR BattleCD_RandByte
    STA.w !Battle_ShakeXRand
.x_mul:
    LDA.w !Battle_ShakeXRand
    STA.l WRMPYA
    INC.w !Battle_ShakeXStepTime
    LDA.w !Battle_ShakeXStepTime
    CMP.w !Battle_ShakeXStepPeriod
    BCC .x_amp
    STZ.w !Battle_ShakeXStepTime
    LDA.w !Battle_ShakeXAmp
    CMP.w !Battle_ShakeXTarget
    BEQ .x_amp
    BCC .x_up
    DEC.w !Battle_ShakeXAmp
    BNE .x_amp
    STZ.w !Battle_ShakeXOn
    BRA .x_amp
.x_up:
    INC.w !Battle_ShakeXAmp
.x_amp:
    LDA.w !Battle_ShakeXAmp
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    STA.b !BattleCD_Tmp45               ; the x value
.y:
    LDA.w !Battle_ShakeYOn
    BNE .y_on
    TAX
    STX.w !Battle_ShakeOfs1Y
    STX.w !Battle_ShakeOfs2Y
    STX.w !Battle_ShakeOfs3Y
    STA.b !BattleCD_Tmp47
    BRA .apply
.y_on:
    INC.w !Battle_ShakeYRandTime
    LDA.w !Battle_ShakeYRandTime
    CMP.w !Battle_ShakeYRandPeriod
    BCC .y_mul
    STZ.w !Battle_ShakeYRandTime
    LDA.b #!BattleCD_ShakeYRandSeed
    JSR BattleCD_RandByte
    STA.w !Battle_ShakeYRand
.y_mul:
    LDA.w !Battle_ShakeYRand
    STA.l WRMPYA
    INC.w !Battle_ShakeYStepTime
    LDA.w !Battle_ShakeYStepTime
    CMP.w !Battle_ShakeYStepPeriod
    BCC .y_amp
    STZ.w !Battle_ShakeYStepTime
    LDA.w !Battle_ShakeYAmp
    CMP.w !Battle_ShakeYTarget
    BEQ .y_amp
    BCC .y_up
    DEC.w !Battle_ShakeYAmp
    BNE .y_amp
    STZ.w !Battle_ShakeYOn
    BRA .y_amp
.y_up:
    INC.w !Battle_ShakeYAmp
.y_amp:
    LDA.w !Battle_ShakeYAmp
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    STA.b !BattleCD_Tmp47               ; the y value
.apply:
    LDA.b !BattleCD_Tmp45
    TAY
    LDA.b !BattleCD_Tmp47
    TAX
    LDA.w !Battle_ShakeLayers
    BEQ .requests
    ASL A
    BCC .no_1x
    STY.w !Battle_ShakeOfs1X
.no_1x:
    ASL A
    BCC .no_1y
    STX.w !Battle_ShakeOfs1Y
.no_1y:
    ASL A
    BCC .no_2x
    STY.w !Battle_ShakeOfs2X
.no_2x:
    ASL A
    BCC .no_2y
    STX.w !Battle_ShakeOfs2Y
.no_2y:
    ASL A
    BCC .no_3x
    STY.w !Battle_ShakeOfs3X
.no_3x:
    ASL A
    BCC .requests
    STX.w !Battle_ShakeOfs3Y
.requests:
    LDA.w !Battle_PalAnimCopy
    BEQ .done
    BPL .copy_a
    REP #$20
    LDX.w #!Battle_PalAnimRec10
    LDY.w #FieldAnimB[10].Unk0
    LDA.w #!BattleCD_PalAnimBytes-1
    MVN !Battle_WramBank,!Battle_WramBank ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    TDC
    SEP #$20
    LDA.w !Battle_PalAnimCopy
    AND.b #!BattleCD_PalAnimClearB
    STA.w !Battle_PalAnimCopy
    RTS
.copy_a:
    REP #$20
    LDX.w #!Battle_PalAnimRecs89
    LDY.w #FieldAnimB[8].Unk0
    LDA.w #(!BattleCD_PalAnimBytes*2)-1
    MVN !Battle_WramBank,!Battle_WramBank ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    TDC
    SEP #$20
    LDA.w !Battle_PalAnimCopy
    AND.b #!BattleCD_PalAnimClearA
    STA.w !Battle_PalAnimCopy
.done:
    RTS

; $CD:0C83 — BattleCD_NmiTable (3 words, $0C83–$0C88)
; BattleCD_NmiDispatch's handler by !Battle_NmiMode.
BattleCD_NmiTable:
    dw BattleCD_NmiSetup                ; 0
    dw BattleCD_NmiMain                 ; 1
    dw BattleCD_NmiMain                 ; 2

; $CD:0C89 — BattleCD_ScrollStepL (12 bytes, $0C89–$0C94)
; The field's ScrollStepAccum (through ReentryVectors vector [1]: the
; drift of layers 2 and 3 in FieldBtlPpu.Scroll2) between PHB/PHD/PHP
; and PLP/PLD/PLB, then A = D (TDC) and RTL. JSL from the bank-$D1 code
; ($D1:E7E3 in the NMI handler unless !Battle_Paused, $D1:F1D7 and
; $D1:F549; not matched).
; Callers (3 JSL sites): unmatched ($D1:E7E3, $D1:F1D7, $D1:F549).
; Entry: M=1 (ScrollStepAccum needs it), X any, DP any, DB any (all
;        saved and restored)
; Exit:  M, X, DP, DB as on entry; A = D (0 when DP=0; B = 0 then); X, Y
;        unchanged
BattleCD_ScrollStepL:
    PHB
    PHD
    PHP
    JSL ReentryVectors+!BattleCD_ReentryScrollStep
    PLP
    PLD
    PLB
    TDC
    RTL

; $CD:0C95 — BattleCD_NmiDispatch (8 bytes, $0C95–$0C9C)
; The NMI's bank-$CD work: runs BattleCD_NmiTable entry !Battle_NmiMode
; (0 BattleCD_NmiSetup, 1 and 2 BattleCD_NmiMain), then RTL. JSL from
; the bank-$D1 NMI handler ($D1:E7DA, not matched).
; Callers (1 JSL site): unmatched ($D1:E7DA).
; Entry: M=1, X=0, DP=0, DB=$00 (the handler set them: REP #$30, D = 0,
;        DB = 0 from TDC, SEP #$20); B = 0 (the 16-bit TAX; the
;        handler's TDC leaves it)
; Exit:  as the handler returns: M=1, X=0, DP=0, DB=$7E; A, X, Y
;        clobbered (RTL)
BattleCD_NmiDispatch:
    LDA.b !Battle_NmiMode
    ASL A
    TAX
    JSR (BattleCD_NmiTable,X)
    RTL

; $CD:0C9D — BattleCD_InitHdmaDataL (4 bytes, $0C9D–$0CA0)
; BattleCD_InitHdmaData as a long call (JSL from BattleD1_InitBattle at
; $D1:F1DB, not matched).
; Callers (1 JSL site): unmatched ($D1:F1DB).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E (as BattleCD_InitHdmaData needs)
; Exit:  as BattleCD_InitHdmaData, returning with RTL
BattleCD_InitHdmaDataL:
    JSR BattleCD_InitHdmaData
    RTL

; $CD:0CA1 — BattleCD_InitHdmaData (135 bytes, $0CA1–$0D27)
; Sets the HDMA line data from the screen the field left (FieldBtlPpu):
; the tilemap bytes of channel 0 (!Battle_HdmaTilemaps: BG1SC, BG2SC,
; BG4SC from .Tilemap1, .Tilemap2, .Unk59; BG2SC's bit 0 cleared when
; !Battle_Unk2A21 bit 0 is set), the 32 scroll entries of each layer
; (!Battle_HdmaScroll1-3) from .Scroll2's six words, and then falls into
; BattleCD_RestoreScreen.
; BattleCD_RestoreScreen ($0CF6): BG3SC (!Battle_HdmaTilemaps+2) from
; .Tilemap3; the words !Battle_HdmaScreens (TM/TS), +2 (TMW/TSW),
; !Battle_HdmaColour (CGWSEL/CGADSUB), !Battle_HdmaColour+2 and
; !Battle_HdmaMode from .MainScreen, .Unk68, .Unk6A, .FixedColor and
; .Unk6E (the order of the FieldBtlPpu fields follows the PPU
; registers, so these are probably those registers' values); then
; !Battle_HdmaColData and !Battle_WinRegs+5 = !BattleCD_ColDataBlack
; and !Battle_Brightness = !BattleCD_FullBright.
; Callers (1 JSR site): BattleCD_InitHdmaDataL ($CD:0C9D).
; Callers of BattleCD_RestoreScreen (1 JSR site): BattleCD_EndLayerFx ($CD:048F).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A = !BattleCD_FullBright; X = FieldBtlPpu.FixedColor's
;        word; Y unchanged
; Sub-entry: BattleCD_RestoreScreen ($0CF6), JSR'd by
;   BattleCD_EndLayerFx; same state and exit.
BattleCD_InitHdmaData:
    LDA.w FieldBtlPpu.Tilemap1
    STA.w !Battle_HdmaTilemaps
    LDA.w FieldBtlPpu.Tilemap2
    STA.w !Battle_HdmaTilemaps+1
    LDA.w FieldBtlPpu.Unk59
    STA.w !Battle_HdmaTilemaps+3
    LDA.w !Battle_Unk2A21
    AND.b #!Battle_2A21Bit0
    BEQ .scroll
    LDA.w !Battle_HdmaTilemaps+1
    AND.b #!BattleCD_ClearBit0
    STA.w !Battle_HdmaTilemaps+1
.scroll:
    TDC
    TAX
    REP #$20
.entry:
    LDA.w FieldBtlPpu.Scroll2
    STA.w !Battle_HdmaScroll1,X
    LDA.w FieldBtlPpu.Scroll2+2
    STA.w !Battle_HdmaScroll1+2,X
    LDA.w FieldBtlPpu.Scroll2+4
    STA.w !Battle_HdmaScroll2,X
    LDA.w FieldBtlPpu.Scroll2+6
    STA.w !Battle_HdmaScroll2+2,X
    LDA.w FieldBtlPpu.Scroll2+8
    STA.w !Battle_HdmaScroll3,X
    LDA.w FieldBtlPpu.Scroll2+10
    STA.w !Battle_HdmaScroll3+2,X
    INX
    INX
    INX
    INX
    CPX.w #!BattleCD_ScrollFillEnd
    BNE .entry
    TDC
    SEP #$20
BattleCD_RestoreScreen:                 ; header: see BattleCD_InitHdmaData
    LDA.w FieldBtlPpu.Tilemap3
    STA.w !Battle_HdmaTilemaps+2
    LDX.w FieldBtlPpu.MainScreen
    STX.w !Battle_HdmaScreens
    LDX.w FieldBtlPpu.Unk68
    STX.w !Battle_HdmaScreens+2
    LDX.w FieldBtlPpu.Unk6A
    STX.w !Battle_HdmaColour
    LDX.w FieldBtlPpu.Unk6E
    STX.w !Battle_HdmaMode
    LDX.w FieldBtlPpu.FixedColor
    STX.w !Battle_HdmaColData
    LDA.b #!BattleCD_ColDataBlack
    STA.w !Battle_HdmaColData
    STA.w !Battle_WinRegs+5
    LDA.b #!BattleCD_FullBright
    STA.w !Battle_Brightness
    RTS

; ============================================================
; Layer effects: start, run and end ($CD:0D28–$CD:0EBC)
; ============================================================
; A layer effect (an id 0-$FF in !Battle_LayerFxId) is a background
; animation on layer 3: BattleCD_LoadLayerFx loads its record, tiles,
; tilemap frames and colours; two script channels
; (BattleCD_StartFxChannels / BattleCD_StepFxChannels) then pick the
; tilemap pages frame by frame, and BattleCD_EndLayerFx puts the battle's
; own layer 3 back. !Battle_Unk5D9B is set while the channels run.

; $CD:0D28 — BattleCD_StartLayerFx (11 bytes, $0D28–$0D32)
; Action set-up's call (BattleAct_LoadCommon, A = !Battle_ActUnkArg987C):
; !Battle_Unk5D9B = 0, loads layer effect A (BattleCD_LoadLayerFx)
; and starts its channels (BattleCD_StartFxChannels); RTL. It does not
; set !Battle_Unk5D9B again (the action's script does, probably:
; not traced).
; Callers (1 JMP site): BattleAnim_UnkVecCD0018 ($CD:0018).
; Entry: M=1, X=0, DP=0, DB=$7E; A = the effect, B = 0 (the 16-bit TAX;
;        BattleAct_LoadCommon's state, assumed)
; Exit:  M=1, X=0, DP=0, DB=$7E (RTL); A, X, Y clobbered; DP $53-$75
;        written by the loader
BattleCD_StartLayerFx:
    STZ.w !Battle_Unk5D9B
    TAX
    JSR BattleCD_LoadLayerFx
    JSR BattleCD_StartFxChannels
    RTL

; $CD:0D33 — BattleCD_StartFxChannels (47 bytes, $0D33–$0D61)
; Clears the three 32-byte channel blocks from !Battle_FxChannels
; ($CA32-$CA91, by words), then starts channel 0 (X = 0) with script
; !Battle_FxScriptIds+0 and channel 1 (X = $10) with +1, each unless $FF
; (BattleCD_StartFxChannel, Y = the channel number).
; Callers (3 JSR sites): BattleCD_StartLayerFx ($CD:0D2F), BattleCD_RunEndFx ($CD:0D8C) and
;   BattleCD_RunLayerFx ($CD:0E0E).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0; A clobbered; X = $20; Y = 2; DP $53-$55 written
BattleCD_StartFxChannels:
    REP #$20
    TDC
    TAX
.clear:
    STZ.w !Battle_FxChannels,X
    STZ.w !Battle_FxChannels+!BattleCD_ChannelBlockBytes,X
    STZ.w !Battle_FxChannels+(!BattleCD_ChannelBlockBytes*2),X
    INX
    INX
    CPX.w #!BattleCD_ChannelBlockBytes
    BNE .clear
    SEP #$20
    TDC
    TAX
    TAY
.channel:
    LDA.w !Battle_FxScriptIds,Y
    CMP.b #!BattleCD_NoScript
    BEQ .next
    JSR BattleCD_StartFxChannel
.next:
    INY
    TXA
    CLC
    ADC.b #!BattleCD_ChannelBytes
    TAX
    CPX.w #!BattleCD_ChannelBlockBytes
    BNE .channel
    RTS

; $CD:0D62 — BattleCD_RunEndFx (49 bytes, $0D62–$0D92)
; The battle end's effect X (BattleCD_LayerFx84 / BattleCD_LayerFx87):
; APU command !BattleCD_ApuCmd80 (arguments 0, $FF), a frame, then
; !Audio_CmdPlayMusic with !BattleCD_EndSong (bank $C7 loads that song;
; argument 2 left as it was); loads effect X (BattleCD_LoadLayerFx),
; starts its channels with !Battle_Unk5D9B = 0 meanwhile, and sets
; !Battle_Unk5D9B + 1.
; Callers (2 JSR sites): BattleCD_LayerFx87 ($CD:0DA5) and BattleCD_LayerFx84 ($CD:0DD5).
; Entry: M=1, X=0, DP=0, DB=$7E; X = the effect
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $53-$75 written
BattleCD_RunEndFx:
    PHX
    LDA.b #!BattleCD_ApuCmd80
    STA.w !Sfx_Command
    STZ.w !Sfx_Param1
    LDA.b #!BattleCD_Cmd80Arg2
    STA.w !Sfx_Param2
    JSL Audio_ProcessEntry
    JSR BattleCD_WaitFrame
    LDA.b #!Audio_CmdPlayMusic
    STA.w !Sfx_Command
    LDA.b #!BattleCD_EndSong
    STA.w !Sfx_Param1
    JSL Audio_ProcessEntry
    PLX
    JSR BattleCD_LoadLayerFx
    STZ.w !Battle_Unk5D9B
    JSR BattleCD_StartFxChannels
    INC.w !Battle_Unk5D9B
    RTS

; $CD:0D93 — BattleCD_LayerFx87 (30 bytes, $0D93–$0DB0)
; One of the battle end's effects (BattleCD_ExitBattle): !Battle_Unk99D2
; = 0, BattleCD_ApuCmd81, frames until APUIO1 reads 0, effect
; !BattleCD_FxEnd87 (BattleCD_RunEndFx), then frames until
; !Battle_Unk5D9B is 0.
; Callers (1 JSR site): BattleCD_ExitBattle ($CD:040A).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; X, Y clobbered
BattleCD_LayerFx87:
    STZ.w !Battle_Unk99D2
    JSR BattleCD_ApuCmd81
.wait_apu:
    JSR BattleCD_WaitFrame
    LDA.l APUIO1
    BNE .wait_apu
    LDX.w #!BattleCD_FxEnd87
    JSR BattleCD_RunEndFx
.wait_fx:
    JSR BattleCD_WaitFrame
    LDA.w !Battle_Unk5D9B
    BNE .wait_fx
    RTS

; $CD:0DB1 — BattleCD_LayerFx84 (73 bytes, $0DB1–$0DF9)
; The other end effect: BattleCD_ApuCmd81, frames until APUIO1 reads 0,
; !Battle_UnkCE13 = 3, !Battle_UnkCE0E = $80; the wait below once; 128
; more frames; effect !BattleCD_FxEnd84 (BattleCD_RunEndFx); and the wait
; again. The wait (.wait): two frames and a BattleCD_FrameTick, again
; while !Battle_UnkCE0B is 2 or more or any of !Battle_UnkCE0A,
; !Battle_BgFxEnded, !Battle_ActRunning and !Battle_Unk5D9B is
; non-zero.
; Callers (1 JSR site): BattleCD_ExitBattle ($CD:03FF).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered
BattleCD_LayerFx84:
    JSR BattleCD_ApuCmd81
.wait_apu:
    JSR BattleCD_WaitFrame
    LDA.l APUIO1
    BNE .wait_apu
    LDA.b #3
    STA.w !Battle_UnkCE13
    LDA.b #!BattleCD_CE0EInit
    STA.w !Battle_UnkCE0E
    JSR .wait
    LDA.b #!BattleCD_EndFxDelay
.delay:
    JSR BattleCD_WaitFrame
    DEC A
    BNE .delay
    LDX.w #!BattleCD_FxEnd84
    JSR BattleCD_RunEndFx
.wait:
    JSR BattleCD_WaitFrame
    JSR BattleCD_WaitFrame
    JSL BattleCD_FrameTick
    LDA.w !Battle_UnkCE0B
    CMP.b #2
    BCC .flags
    BRA .wait
.flags:
    LDA.w !Battle_UnkCE0A
    ORA.w !Battle_BgFxEnded
    ORA.w !Battle_ActRunning
    ORA.w !Battle_Unk5D9B
    BNE .wait
    RTS

; $CD:0DFA — BattleCD_WaitLayerFxIdle (11 bytes, $0DFA–$0E04)
; Waits (BattleCD_WaitFrameRefresh) while !Battle_Unk5D9B is set.
; Callers (1 JSR site): BattleCD_RunLayerFx ($CD:0E06).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0; B as on entry when there is
;        no wait, else as BattleCD_WaitFrameRefresh leaves it; X, Y as
;        the waits leave them
BattleCD_WaitLayerFxIdle:
    LDA.w !Battle_Unk5D9B
    BEQ .done
    JSR BattleCD_WaitFrameRefresh
    BRA BattleCD_WaitLayerFxIdle
.done:
    RTS

; $CD:0E05 — BattleCD_RunLayerFx (30 bytes, $0E05–$0E22)
; Runs layer effect A to its end: waits for the one before
; (BattleCD_WaitLayerFxIdle), loads A (BattleCD_LoadLayerFx), starts its
; channels, !Battle_Unk5D9B + 1, then frames
; (BattleCD_WaitFrameRefresh, BattleCD_FrameTick) until the channels
; clear !Battle_Unk5D9B. JSL from BattleCD_EnemyDissolve, which
; also JMPs here (its RTL then returns for it).
; Callers (2 sites: 1 JSL, 1 JMP): BattleCD_EnemyDissolve (JSL $CD:0075, JMP $CD:0090).
; Entry: M=1, X=0, DP=0, DB=$7E; A = the effect, B = 0 (the 16-bit TAX;
;        BattleCD_EnemyDissolve's state, assumed). That entry B reaches
;        the TAX only when BattleCD_WaitLayerFxIdle does not wait; after
;        a wait B is what BattleCD_WaitFrameRefresh's chain leaves
;        (assumed 0, not traced)
; Exit:  M=1, X=0, DP=0, DB=$7E (RTL); A = 0; X, Y clobbered; DP
;        $53-$75 written
BattleCD_RunLayerFx:
    PHA
    JSR BattleCD_WaitLayerFxIdle
    PLA
    TAX
    JSR BattleCD_LoadLayerFx
    JSR BattleCD_StartFxChannels
    INC.w !Battle_Unk5D9B
.wait:
    LDA.w !Battle_Unk5D9B
    BEQ .done
    JSR BattleCD_WaitFrameRefresh
    JSL BattleCD_FrameTick
    BRA .wait
.done:
    RTL

; $CD:0E23 — BattleCD_RestorePalRows (18 bytes, $0E23–$0E34)
; Copies the 16 bytes at !Battle_PalRowSave (colours 24-31, saved by
; code not matched) back to bytes $30-$3F of both !Battle_PaletteSavedLo
; and !Battle_PaletteLiveLo.
; Callers (2 JSR sites): BattleCD_EndLayerFx ($CD:049F) and BattleCD_FxRecSetup ($CD:0E35).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A = the last byte, B = 0; X = $10; Y unchanged
BattleCD_RestorePalRows:
    TDC
    TAX
.byte:
    LDA.w !Battle_PalRowSave,X
    STA.w !Battle_PaletteSavedLo+!BattleCD_PalRowOfs,X
    STA.w !Battle_PaletteLiveLo+!BattleCD_PalRowOfs,X
    INX
    CPX.w #!BattleCD_PalRowBytes
    BNE .byte
    RTS

; $CD:0E35 — BattleCD_FxRecSetup (44 bytes, $0E35–$0E60)
; Shared start of BattleCD_LoadFxPalA/B: the palette rows back
; (BattleCD_RestorePalRows); DP $55 = 1 when FieldBtlPpu.ColorMath bit 6
; (!BattleCD_CgadsubHalf, half colour math, if it is a CGADSUB image)
; is set, else 0; DP $53 = !BattleRom_FxRecByte0 entry DP $55; X = DP
; $55 * 16, + $20 when !Battle_Unk2A21 bit 0 is set; Y = 0.
; Callers (2 JSR sites): BattleCD_LoadFxPalA ($CD:0E61) and BattleCD_LoadFxPalB ($CD:0E79).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0; A = 0; X = the record offset; Y = 0; DP $53 and $55
;        written
BattleCD_FxRecSetup:
    JSR BattleCD_RestorePalRows
    STZ.b !BattleCD_Tmp55
    LDA.w FieldBtlPpu.ColorMath
    AND.b #!BattleCD_CgadsubHalf
    BEQ .index
    LDA.b #1
    STA.b !BattleCD_Tmp55
.index:
    TAX
    LDA.l !BattleRom_FxRecByte0,X
    STA.b !BattleCD_Tmp53
    TXA
    ASL A
    ASL A
    ASL A
    ASL A
    TAX
    LDA.w !Battle_Unk2A21
    AND.b #!Battle_2A21Bit0
    BEQ .done
    TXA
    CLC
    ADC.b #!BattleCD_FxRec2A21Ofs
    TAX
.done:
    TDC
    TAY
    RTS

; $CD:0E61 — BattleCD_LoadFxPalA (60 bytes, $0E61–$0E9C)
; Unless the half-colour-math flag of BattleCD_FxRecSetup (DP $55) is
; set: copies 8 bytes of !BattleRom_FxRecA (from the setup's offset X)
; to !Battle_PalAnimRec10+1, !Battle_PalAnimRec10 = DP $53, and sets
; !Battle_PalAnimCopy bit 7 (BattleCD_StepShake copies the record on to
; palette animation record 10). BattleCD_LoadFxPalB ($0E79) is the
; same from !BattleRom_FxRecB; both end in the shared tail .store.
; Callers (1 JSR site): BattleCD_EndLayerFx ($CD:0489).
; Callers of BattleCD_LoadFxPalB (2 JSR sites): BattleCD_LoadLayerFx ($CD:0F04, $CD:0F20).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0; A clobbered; X = the offset + 8 (or the offset);
;        Y = 8 (or 0); DP $53 and $55 written
; Sub-entry: BattleCD_LoadFxPalB ($0E79), JSR'd by BattleCD_LoadLayerFx;
;   same state and exit.
BattleCD_LoadFxPalA:
    JSR BattleCD_FxRecSetup
    LDA.b !BattleCD_Tmp55
    BEQ .copy
    RTS
.copy:
    LDA.l !BattleRom_FxRecA,X
    STA.w !Battle_PalAnimRec10+1,Y
    INX
    INY
    CPY.w #8
    BNE .copy
    BRA BattleCD_LoadFxPalB_store
BattleCD_LoadFxPalB:                    ; header: see BattleCD_LoadFxPalA
    JSR BattleCD_FxRecSetup
    LDA.b !BattleCD_Tmp55
    BEQ .copy_b
    RTS
.copy_b:
    LDA.l !BattleRom_FxRecB,X
    STA.w !Battle_PalAnimRec10+1,Y
    INX
    INY
    CPY.w #8
    BNE .copy_b
.store:
    LDA.b !BattleCD_Tmp53
    STA.w !Battle_PalAnimRec10
    LDA.w !Battle_PalAnimCopy
    ORA.b #!Battle_PalAnimCopy10
    STA.w !Battle_PalAnimCopy
    RTS

; $CD:0E9D — BattleCD_LayerFxSetsScreen (32 bytes, $0E9D–$0EBC)
; C=0 and A = 0 when the current layer effect (!Battle_LayerFxId) is
; !BattleCD_FxPlain86 or !BattleCD_FxPlainFirst-!BattleCD_FxPlainLast
; ($7B-$7F); else C=1 with A = the id. With C=1 the effect brings its own
; layer-3 screen settings (BattleCD_LoadLayerFx sets them, and
; BattleCD_EndLayerFx puts the battle's back); the named effects only
; replace the tiles and frames (inferred from those two callers).
; Callers (4 JSR sites): BattleCD_EndLayerFx ($CD:0473), BattleCD_LoadLayerFx ($CD:0EF8, $CD:0F89)
;   and BattleCD_StepFxChannels ($CD:1613).
; Entry: M=1, X any, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1; C and A as above; X, Y unchanged
BattleCD_LayerFxSetsScreen:
    LDA.w !Battle_LayerFxId
    CMP.b #!BattleCD_FxPlain86
    BEQ .plain
    CMP.b #!BattleCD_FxPlainFirst
    BEQ .plain
    CMP.b #!BattleCD_FxPlainFirst+1
    BEQ .plain
    CMP.b #!BattleCD_FxPlainFirst+2
    BEQ .plain
    CMP.b #!BattleCD_FxPlainFirst+3
    BEQ .plain
    CMP.b #!BattleCD_FxPlainLast
    BEQ .plain
    SEC
    RTS
.plain:
    TDC
    CLC
    RTS

; $CD:0EBD — BattleCD_LoadLayerFx (405 bytes, $0EBD–$1051)
; Loads layer effect X (0-$FF; X = !BattleCD_FxByBattle stays when
; !Battle_UnkA018 is 7, else becomes +1 when !Battle_UnkA017 is 7, else
; +2: a variant by the battle, probably):
;   - !Battle_LayerFxId = X; !Battle_UnkCD28 and !Battle_UnkCD3C = 0;
;     the wave flags !Battle_WaveBg1-3 and the words !Battle_UnkCD38/3A
;     = 0;
;   - when the effect sets the screen (BattleCD_LayerFxSetsScreen): with
;     !Battle_Unk2A21 bit 0, BattleCD_LoadFxPalB, 31 frames and BG2 off
;     the main screen (!Battle_HdmaScreens bit 1 cleared); else when
;     FieldBtlPpu.MainScreen or .SubScreen has bit 2 (BG3),
;     BattleCD_LoadFxPalB and 15 frames; then (both) main screen =
;     !BattleCD_FxMainScreen except on the first path; window screens
;     (!Battle_HdmaScreens+2) = 0, a frame, the colour words
;     !Battle_HdmaColour/+2 = 0, a frame;
;   - !Battle_FxScriptIds (4 bytes: the two channel scripts and two
;     colour sets) from !BattleRom_FxScripts entry X; $FF to
;     !Battle_LastPageSlot, !Battle_LastPageSrc and the byte after it (two
;     word stores), so the next page upload is never skipped;
;   - the effect's record (BattleCD_LoadFxRecord: !Battle_FxRecord ...),
;     !Battle_UnkCA1B = !Battle_FxRecUnkCA00's word, DP $53 = the record's
;     tile set and DP $54 = bit 6 of its block count byte (the tile word
;     the next steps use), !Battle_UnkCD04 = $1F;
;   - when the effect sets the screen (else it returns here): BG3's
;     tilemap at !BattleCD_FxBg3Sc, !Battle_HdmaMode = !BattleCD_FxBgMode,
;     !Battle_HdmaScreens+2 = !BattleCD_FxWinScreens; four tile sets
;     (BattleCD_LoadFxTiles from the tile word, + 2 each) through the
;     $7E:2D00 buffer to VRAM !BattleRom_FxTileVram (the fourth with
;     buffer bytes $2E0-$2FF and $3E0-$3FF zeroed before its upload: its
;     tiles $2E/$2F and $3E/$3F, i.e. layer-3 tiles $EE/$EF and $FE/$FF,
;     probably what makes tile $EE blank),
;     !Battle_LayerFxLoaded + 1 for each; the tilemap pages filled with
;     tile $EE (BattleCD_FillFxTilemaps) and the first $800 bytes sent to
;     VRAM !BattleCD_FxTilemapVram; the effect's tilemap pages built
;     (BattleCD_BuildFxTilemap with the tile word); then the two colour
;     sets !Battle_FxScriptIds+2/+3 (unless $FF): 6 bytes each of
;     !BattleRom_FxColours (8 bytes per set) to colours 25-27 and 29-31
;     of !Battle_PaletteSavedLo and !Battle_PaletteLiveLo.
; Callers (3 JSR sites): BattleCD_StartLayerFx ($CD:0D2C), BattleCD_RunEndFx ($CD:0D86) and
;   BattleCD_RunLayerFx ($CD:0E0B).
; Entry: M=1, X=0, DP=0, DB=$7E; X = the effect
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $53-$75 written
BattleCD_LoadLayerFx:
    CPX.w #!BattleCD_FxByBattle
    BNE .have_id
    LDA.w !Battle_UnkA018
    CMP.b #7
    BEQ .variant0
    LDA.w !Battle_UnkA017
    CMP.b #7
    BEQ .variant1
    LDX.w #!BattleCD_FxByBattle+2
    BRA .have_id
.variant1:
    LDX.w #!BattleCD_FxByBattle+1
    BRA .have_id
.variant0:
    LDX.w #!BattleCD_FxByBattle
.have_id:
    PHX
    STX.w !Battle_LayerFxId
    STZ.w !Battle_UnkCD28
    STZ.w !Battle_UnkCD3C
    TDC
    TAX
    STX.w !Battle_WaveBg1
    STX.w !Battle_WaveBg2
    STX.w !Battle_WaveBg3
    STX.w !Battle_UnkCD38
    STX.w !Battle_UnkCD3A
    JSR BattleCD_LayerFxSetsScreen
    BCC .record
    LDA.w !Battle_Unk2A21
    AND.b #!Battle_2A21Bit0
    BEQ .bg3_check
    JSR BattleCD_LoadFxPalB
    LDA.b #!BattleCD_FxPalDelayLong
    JSR BattleCD_WaitFrames
    LDA.w !Battle_HdmaScreens
    AND.b #!BattleCD_MainNoBg2
    STA.w !Battle_HdmaScreens
    BRA .windows
.bg3_check:
    LDA.w FieldBtlPpu.MainScreen
    ORA.w FieldBtlPpu.SubScreen
    AND.b #!BattleCD_ScreenBg3
    BEQ .main
    JSR BattleCD_LoadFxPalB
    LDA.b #!BattleCD_ExitFadeFrames
    JSR BattleCD_WaitFrames
.main:
    LDA.b #!BattleCD_FxMainScreen
    STA.w !Battle_HdmaScreens
.windows:
    LDX.w #0
    STX.w !Battle_HdmaScreens+2
    JSR BattleCD_WaitFrameRefresh
    LDX.w #0
    STX.w !Battle_HdmaColour+2
    STX.w !Battle_HdmaColour
    JSR BattleCD_WaitFrameRefresh
.record:
    PLX
    STX.w !Battle_LayerFxId
    PHX
    REP #$20
    TXA
    ASL A
    ASL A
    TAX
    TDC
    TAY
.script_ids:
    LDA.l !BattleRom_FxScripts,X
    STA.w !Battle_FxScriptIds,Y
    INX
    INX
    INY
    INY
    CPY.w #4
    BNE .script_ids
    TDC
    SEP #$20
    LDX.w #!BattleCD_NoPage
    STX.w !Battle_LastPageSlot          ; the slot and the source's low byte
    STX.w !Battle_LastPageSrc+1         ; the source's high byte and the byte after
    PLX
    JSR BattleCD_LoadFxRecord
    LDX.w !Battle_FxRecUnkCA00
    STX.w !Battle_UnkCA1B
    LDA.w !Battle_FxRecord+1
    STA.b !BattleCD_Tmp53               ; the tile word: set ...
    LDA.w !Battle_FxRecord
    ROL A
    ROL A
    ROL A
    AND.b #1
    STA.b !BattleCD_Tmp54               ; ... and bit 6 of the count byte
    LDA.b #!BattleCD_CD04Init
    STA.w !Battle_UnkCD04
    JSR BattleCD_LayerFxSetsScreen
    BCS .screen
    RTS
.screen:
    LDA.b #!BattleCD_FxBg3Sc
    STA.w !Battle_HdmaTilemaps+2
    LDA.b #!BattleCD_FxBgMode
    STA.w !Battle_HdmaMode
    LDX.w #!BattleCD_FxWinScreens
    STX.w !Battle_HdmaScreens+2
    STZ.w !Battle_FxTileSet
    LDX.b !BattleCD_Tmp53
    PHX
.tile_set:
    PHX
    JSR BattleCD_LoadFxTiles
    LDA.w !Battle_FxTileSet
    ASL A
    TAX
    CPX.w #!BattleCD_FxLastSetOfs
    BNE .upload
    PHX
    TDC
    TAX
    REP #$20
.blank:
    STZ.w !Battle_ActFrameBuf+!BattleCD_FxBlankOfsA,X
    STZ.w !Battle_ActFrameBuf+!BattleCD_FxBlankOfsB,X
    INX
    INX
    CPX.w #!BattleCD_FxBlankBytes
    BNE .blank
    PLX
.upload:
    REP #$20
    LDA.l !BattleRom_FxTileVram,X
    TAY
    TDC
    SEP #$20
    LDX.w #!BattleCD_FxSetBytes
    STX.b !BattleCD_Tmp53               ; byte count for BattleCD_QueueVramDma
    LDX.w #!Battle_ActFrameBuf
    LDA.b #!Battle_WramBank
    JSR BattleCD_QueueVramDma
    INC.w !Battle_LayerFxLoaded
    PLX
    INX
    INX
    INC.w !Battle_FxTileSet
    LDA.w !Battle_FxTileSet
    CMP.b #4
    BNE .tile_set
    JSR BattleCD_FillFxTilemaps
    LDX.w #!BattleCD_FxTilemapBytes
    STX.b !BattleCD_Tmp53
    LDX.w #!Battle_FxTilemaps
    LDA.b #!Battle_WramBank
    LDY.w #!BattleCD_FxTilemapVram
    JSR BattleCD_QueueVramDma
    PLX
    JSR BattleCD_BuildFxTilemap
    TDC
    TAY
    LDA.w !Battle_FxScriptIds+2
    CMP.b #!BattleCD_NoScript
    BEQ .colours_b
    REP #$20
    ASL A
    ASL A
    ASL A
    TAX
.colours_a:
    LDA.l !BattleRom_FxColours+2,X
    STA.w !Battle_PaletteSavedLo+!BattleCD_FxColoursA,Y
    STA.w !Battle_PaletteLiveLo+!BattleCD_FxColoursA,Y
    INX
    INX
    INY
    INY
    CPY.w #6
    BNE .colours_a
    TDC
    SEP #$20
.colours_b:
    TDC
    TAY
    LDA.w !Battle_FxScriptIds+3
    CMP.b #!BattleCD_NoScript
    BEQ .done
    REP #$20
    AND.w #!Battle_LowByteMask
    ASL A
    ASL A
    ASL A
    TAX
.colours_b_copy:
    LDA.l !BattleRom_FxColours+2,X
    STA.w !Battle_PaletteSavedLo+!BattleCD_FxColoursB,Y
    STA.w !Battle_PaletteLiveLo+!BattleCD_FxColoursB,Y
    INX
    INX
    INY
    INY
    CPY.w #6
    BNE .colours_b_copy
    TDC
    SEP #$20
.done:
    RTS

; $CD:1052 — BattleCD_FillFxTilemaps (43 bytes, $1052–$107C)
; Fills the effect's tilemap pages !Battle_FxTilemaps ($7E:D000-$FFFF)
; with the entry !BattleCD_FxBlankEntry (tile $EE, attribute 0), by words:
; .fill (JSR'd with X = 0 and $1000, run with X = $2000) does $D000+X to
; $D7FF+X and $D800+X to $DFFF+X.
; Callers (1 JSR site): BattleCD_LoadLayerFx ($CD:0FED).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0; A = 0 (B = 0); X = $2800; Y unchanged; DP $53
;        written
BattleCD_FillFxTilemaps:
    LDX.w #0
    JSR .fill
    LDX.w #!BattleCD_FxFillStep
    JSR .fill
    LDX.w #!BattleCD_FxFillStep*2
.fill:
    REP #$20
    TXA
    CLC
    ADC.w #!BattleCD_FxFillHalf
    STA.b !BattleCD_Tmp53               ; the end
    LDA.w #!BattleCD_FxBlankEntry
.word:
    STA.w !Battle_FxTilemaps,X
    STA.w !Battle_FxTilemaps+!BattleCD_FxFillHalf,X
    INX
    INX
    CPX.b !BattleCD_Tmp53
    BNE .word
    TDC
    SEP #$20
    RTS

; $CD:107D — BattleCD_BuildFxTilemap (315 bytes, $107D–$11B7)
; Builds the effect's tilemap pages into !Battle_FxTilemaps, one page of
; $200 bytes per block, !Battle_FxRecord's low 6 bits of blocks (the
; count byte is cut to them), from map !Battle_FxRecMap on (+1 a block;
; the address of each map from !BattleRom_FxMapPtrs, bank $D1). A map
; is a step byte (!Battle_FxMapStep), a bitmap of the cells present (2
; bytes per row; 32 bytes are copied to !Battle_FxMapBits) and the cell
; bytes from offset rows * 2 + 1 on. For each present cell, 16 cells a
; row and !Battle_FxRecRows rows: at byte offset row * 32 + the
; !BattleRom_FxColumnOfs entry (column * 2): tile = (cell AND 7) * 2 +
; (cell AND $38) * 4, attribute = the cell's flip bits | !BattleCD_FxAttr
; (priority, palette 6), | !BattleCD_FxAttrPal when the !BattleRom_FxPalBits
; byte (the tile word's low byte + (cell AND $38) / 4) has bit (cell AND
; 7). After each
; cell the map pointer moves on: by the step byte, or with step bit 7 set
; one byte, wrapping back 32 when !Battle_FxMapCount reaches a multiple
; of 32 (a 32-byte ring, probably).
; Callers (1 JSR site): BattleCD_LoadLayerFx ($CD:1001).
; Entry: M=1, X=0, DP=0, DB=$7E; X = the tile word (BattleCD_LoadLayerFx's
;        DP $53/$54)
; Exit:  M=1, X=0; A = 0 (B = 0); X, Y clobbered; !Battle_FxRecMap
;        advanced past the last map, the count byte at 0; DP $53-$75
;        written
BattleCD_BuildFxTilemap:
    STX.b !BattleCD_FxTileWord
    STZ.w !Battle_FxMapCount
    LDA.b #!BattleCD_FxAttr
    STA.b !BattleCD_FxAttrBase
    STZ.b !BattleCD_FxColumnBase
    STZ.b !BattleCD_FxFlipMask
    LDA.b #!BattleRom_FxMapPtrs>>16
    STA.b !BattleCD_Tmp53+2
    LDX.w #!Battle_FxTilemaps
    STX.b !BattleCD_FxDest
    LDA.b #!Battle_WramBank
    STA.b !BattleCD_FxDest+2
    LDA.w !Battle_FxRecord
    AND.b #!BattleCD_FxBlockMask
    STA.w !Battle_FxRecord
.block:
    LDA.w !Battle_FxRecRows
    STA.b !BattleCD_FxRowsLeft
    REP #$20
    LDA.w !Battle_FxRecMap
    ASL A
    TAX
    LDA.l !BattleRom_FxMapPtrs,X
    STA.b !BattleCD_Tmp53               ; the map
    LDA.b [!BattleCD_Tmp53]
    AND.w #!Battle_LowByteMask
    STA.w !Battle_FxMapStep
    LDY.w #1
.bits:
    LDA.b [!BattleCD_Tmp53],Y
    STA.w !Battle_FxMapBits-1,Y
    INY
    INY
    CPY.w #!BattleCD_FxMapBitsEnd
    BNE .bits
    LDA.w !Battle_FxRecRows
    AND.w #!Battle_LowByteMask
    ASL A
    INC A
    CLC
    ADC.b !BattleCD_Tmp53
    STA.b !BattleCD_Tmp53               ; the first cell byte
    STZ.b !BattleCD_FxColumn            ; and the row above it
    STZ.b !BattleCD_FxBitsPos
    TDC
    SEP #$20
    TAY
    INC A
    STA.b !BattleCD_FxBitsLeft
.cell:
    DEC.b !BattleCD_FxBitsLeft
    BNE .bit
    LDA.b #8
    STA.b !BattleCD_FxBitsLeft
    LDX.b !BattleCD_FxBitsPos
    INC.b !BattleCD_FxBitsPos
    LDA.w !Battle_FxMapBits,X
    STA.b !BattleCD_FxBits
.bit:
    ASL.b !BattleCD_FxBits
    BCS .present
    JMP .next
.present:
    LDA.b !BattleCD_FxColumn
    CLC
    ADC.b !BattleCD_FxColumnBase
    TAX
    LDA.l !BattleRom_FxColumnOfs,X
    TAX
    STX.b !BattleCD_Tmp69               ; the column's byte offset
    LDA.b !BattleCD_FxRow
    REP #$20
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC.b !BattleCD_Tmp69
    TAY
    TDC
    SEP #$20
    LDA.b [!BattleCD_Tmp53]
    STA.b !BattleCD_FxCell
    LDA.w !Battle_FxMapStep
    BPL .step
    INC.w !Battle_FxMapCount
    REP #$20
    INC.b !BattleCD_Tmp53
    LDA.w !Battle_FxMapCount
    AND.w #!BattleCD_FxRingMask
    BNE .stepped
    LDA.b !BattleCD_Tmp53
    SEC
    SBC.w #!BattleCD_FxRingBytes
    STA.b !BattleCD_Tmp53
.stepped:
    TDC
    SEP #$20
    BRA .entry
.step:
    REP #$20
    LDA.b !BattleCD_Tmp53
    CLC
    ADC.w !Battle_FxMapStep
    STA.b !BattleCD_Tmp53
    TDC
    SEP #$20
.entry:
    LDA.b !BattleCD_FxCell
    AND.b #7
    ASL A
    STA.b !BattleCD_Tmp6B
    LDA.b !BattleCD_FxCell
    AND.b #!BattleCD_FxCellRowBits
    ASL A
    ASL A
    CLC
    ADC.b !BattleCD_Tmp6B
    STA.b [!BattleCD_FxDest],Y          ; the tile
    LSR A
    PHA
    AND.b #7
    TAX
    LDA.l !BattleRom_FxBitMask,X
    STA.b !BattleCD_FxPalBit
    PLA
    LSR A
    LSR A
    LSR A
    CLC
    ADC.b !BattleCD_FxTileWord
    TAX
    LDA.l !BattleRom_FxPalBits,X
    AND.b !BattleCD_FxPalBit
    BEQ .pal0
    LDA.b #!BattleCD_FxAttrPal
    STA.b !BattleCD_FxPalBit
    BRA .attr
.pal0:
    STZ.b !BattleCD_FxPalBit
.attr:
    LDA.b !BattleCD_FxCell
    INY
    AND.b #!BattleCD_FxCellFlips
    EOR.b !BattleCD_FxFlipMask
    ORA.b !BattleCD_FxAttrBase
    ORA.b !BattleCD_FxPalBit
    STA.b [!BattleCD_FxDest],Y          ; the attribute
.next:
    INC.b !BattleCD_FxColumn
    LDA.b !BattleCD_FxColumn
    CMP.b #!BattleCD_FxColumns
    BEQ .row_end
    JMP .cell
.row_end:
    STZ.b !BattleCD_FxColumn
    INC.b !BattleCD_FxRow
    DEC.b !BattleCD_FxRowsLeft
    BEQ .block_end
    JMP .cell
.block_end:
    REP #$20
    CLC
    LDA.b !BattleCD_FxDest
    ADC.w #!BattleCD_FxPageBytes
    STA.b !BattleCD_FxDest
    INC.w !Battle_FxRecMap
    TDC
    SEP #$20
    DEC.w !Battle_FxRecord
    BEQ .done
    JMP .block
.done:
    RTS

; $CD:11B8 — BattleCD_LoadFxRecord (44 bytes, $11B8–$11E3)
; Copies the 6-byte !BattleRom_FxRecords entry X & $7FFF to
; !Battle_FxRecord ($C9FC-$CA01: the block count byte, the tile set, the
; first map word, !Battle_FxRecUnkCA00 and the rows per block), using
; !Battle_FxRecord as scratch for X * 2 on the way; then the word at
; !Battle_FxRecUnkCA00 to !Battle_FxChannels+1/+2 (dead: every caller
; next runs BattleCD_StartFxChannels, which clears them).
; Callers (1 JSR site): BattleCD_LoadLayerFx ($CD:0F6C).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E; X = the effect
; Exit:  M=1, X=0; A = 0 (B = 0); X = the entry's offset + 6; Y = 6
BattleCD_LoadFxRecord:
    REP #$20
    TXA
    AND.w #!BattleCD_FxIdMask
    ASL A
    STA.w !Battle_FxRecord              ; scratch: X * 2
    ASL A
    CLC
    ADC.w !Battle_FxRecord
    TAX
    TDC
    TAY
.word:
    LDA.l !BattleRom_FxRecords,X
    STA.w !Battle_FxRecord,Y
    INX
    INX
    INY
    INY
    CPY.w #6
    BNE .word
    LDA.w !Battle_FxRecUnkCA00
    STA.w !Battle_FxChannels+1
    TDC
    SEP #$20
    RTS

; $CD:11E4 — BattleCD_LoadFxTiles (53 bytes, $11E4–$1218)
; Builds one set of 64 2bpp tiles (16 bytes each, $400 bytes) in
; !Battle_ActFrameBuf ($7E:2D00, from Y = 0): the set's 64 entry words
; are at $CF:8000 + X * 64 (DP $53-$55); each names a source tile (bits
; 0-12) and its flips (bit 14 horizontal, bit 15 vertical), and
; BattleCD_TileHandlers2 entry (bits 14-15) copies it.
; Callers (1 JSR site): BattleCD_LoadLayerFx ($CD:0FA6).
; Entry: M=1 (REP/SEP #$20 here), X=0, DP=0, DB=$7E; X = the set (in
;        units of 32 entries)
; Exit:  M=1, X=0; A = 0 (B = 0); X clobbered; Y = $400; DP $53-$55 and
;        $67-$69 (and $61 on the flipped paths) written
BattleCD_LoadFxTiles:
    LDA.b #!BattleRom_FxTileLists>>16
    STA.b !BattleCD_Tmp53+2
    REP #$20
    TXA
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC.w #!BattleRom_FxTileLists&$FFFF
    STA.b !BattleCD_Tmp53               ; the entry
    TDC
    TAY
    LDA.w #!BattleCD_FxSetTiles
    STA.b !BattleCD_Tmp67               ; entries left
.entry:
    LDA.b [!BattleCD_Tmp53]
    XBA
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    AND.w #!BattleCD_FlipBits
    TAX
    JSR (BattleCD_TileHandlers2,X)
    INC.b !BattleCD_Tmp53
    INC.b !BattleCD_Tmp53
    DEC.b !BattleCD_Tmp67
    BNE .entry
    TDC
    SEP #$20
    RTS

; $CD:1219 — BattleCD_TileHandlers2 (4 words, $1219–$1220)
; BattleCD_LoadFxTiles' tile copiers by the entry's flip bits (bit 14 =
; 2, bit 15 = 4).
BattleCD_TileHandlers2:
    dw BattleCD_TileCopy2               ; no flip
    dw BattleCD_TileHFlip2              ; horizontal
    dw BattleCD_TileVFlip2              ; vertical
    dw BattleCD_TileVHFlip2             ; both

; $CD:1221 — BattleCD_TileVHFlip2 (8 bytes, $1221–$1228)
; A 2bpp tile flipped both ways: BattleCD_TileVFlip2 at Y, then the
; horizontal flip of BattleCD_TileHFlip2 (JMP BattleCD_TileReverse2) at
; the same Y.
; Callers note: none by call; BattleCD_TileHandlers2 entry 3 (JSR (T,X) in
;   BattleCD_LoadFxTiles).
; Entry: M=0, X=0 (as BattleCD_LoadFxTiles runs the handlers), DP=0,
;        DB=$7E; DP $53-$55 = the entry's address; Y = the tile's offset
; Exit:  M=0, X=0; Y + 16; A, X clobbered; DP $61 and $69 written
BattleCD_TileVHFlip2:
    PHY
    JSR BattleCD_TileVFlip2
    PLY
    JMP BattleCD_TileReverse2

; $CD:1229 — BattleCD_TileVFlip2 (76 bytes, $1229–$1274)
; A 2bpp tile flipped vertically: BattleCD_TileCopy2, then the eight row
; words swapped end for end (row 0 with 7, 1 with 6, ...), using DP $69.
; Callers (1 JSR site): BattleCD_TileVHFlip2 ($CD:1222).
; Callers note: also BattleCD_TileHandlers2 entry 2 (JSR (T,X) in
;   BattleCD_LoadFxTiles).
; Entry: M=0, X=0, DP=0, DB=$7E; DP $53-$55 = the entry's address; Y =
;        the tile's offset in !Battle_ActFrameBuf
; Exit:  M=0, X=0; Y + 16; A, X clobbered; DP $69 written
BattleCD_TileVFlip2:
    PHY
    JSR BattleCD_TileCopy2
    PLY
    LDA.w !Battle_ActFrameBuf,Y
    STA.b !BattleCD_Tmp69
    LDA.w !Battle_ActFrameBuf+14,Y
    STA.w !Battle_ActFrameBuf,Y
    LDA.b !BattleCD_Tmp69
    STA.w !Battle_ActFrameBuf+14,Y
    LDA.w !Battle_ActFrameBuf+2,Y
    STA.b !BattleCD_Tmp69
    LDA.w !Battle_ActFrameBuf+12,Y
    STA.w !Battle_ActFrameBuf+2,Y
    LDA.b !BattleCD_Tmp69
    STA.w !Battle_ActFrameBuf+12,Y
    LDA.w !Battle_ActFrameBuf+4,Y
    STA.b !BattleCD_Tmp69
    LDA.w !Battle_ActFrameBuf+10,Y
    STA.w !Battle_ActFrameBuf+4,Y
    LDA.b !BattleCD_Tmp69
    STA.w !Battle_ActFrameBuf+10,Y
    LDA.w !Battle_ActFrameBuf+6,Y
    STA.b !BattleCD_Tmp69
    LDA.w !Battle_ActFrameBuf+8,Y
    STA.w !Battle_ActFrameBuf+6,Y
    LDA.b !BattleCD_Tmp69
    STA.w !Battle_ActFrameBuf+8,Y
    TYA
    CLC
    ADC.w #!BattleCD_Tile2Bytes
    TAY
    RTS

; $CD:1275 — BattleCD_TileHFlip2 (67 bytes, $1275–$12B7)
; A 2bpp tile flipped horizontally: BattleCD_TileCopy2, then its 16
; bytes at Y through BitReverseTable (each byte's bits reversed: the
; row mirrored), 4 a pass with the count in DP $61. The reversing part
; BattleCD_TileReverse2 ($127A) switches to 8-bit A for it (TDC first,
; so B = 0 for the TAXs) and back.
; Callers of BattleCD_TileReverse2 (1 JMP site): BattleCD_TileVHFlip2 ($CD:1226).
; Callers note: none by call; BattleCD_TileHandlers2 entry 1 (JSR (T,X) in
;   BattleCD_LoadFxTiles).
; Entry: M=0, X=0, DP=0, DB=$7E; DP $53-$55 = the entry's address; Y =
;        the tile's offset
; Exit:  M=0, X=0; Y + 16; A, X clobbered; DP $61 written
; Sub-entry: BattleCD_TileReverse2 ($127A), JMP'd by BattleCD_TileVHFlip2
;   with Y = the tile's offset; reverses those 16 bytes; same exit.
BattleCD_TileHFlip2:
    PHY
    JSR BattleCD_TileCopy2
    PLY
BattleCD_TileReverse2:                  ; header: see BattleCD_TileHFlip2
    TDC
    SEP #$20
    LDA.b #4
    STA.b !BattleCD_Tmp61               ; passes left
.pass:
    LDA.w !Battle_ActFrameBuf,Y
    TAX
    LDA.l BitReverseTable,X
    STA.w !Battle_ActFrameBuf,Y
    LDA.w !Battle_ActFrameBuf+1,Y
    TAX
    LDA.l BitReverseTable,X
    STA.w !Battle_ActFrameBuf+1,Y
    LDA.w !Battle_ActFrameBuf+2,Y
    TAX
    LDA.l BitReverseTable,X
    STA.w !Battle_ActFrameBuf+2,Y
    LDA.w !Battle_ActFrameBuf+3,Y
    TAX
    LDA.l BitReverseTable,X
    STA.w !Battle_ActFrameBuf+3,Y
    INY
    INY
    INY
    INY
    DEC.b !BattleCD_Tmp61
    BNE .pass
    REP #$20
    RTS

; $CD:12B8 — BattleCD_TileCopy2 (72 bytes, $12B8–$12FF)
; Copies the entry's 2bpp tile: 16 bytes from $CF:0000 + (entry AND
; $1FFF) * 8 (!BattleRom_FxTileGfx) to !Battle_ActFrameBuf + Y, a word at
; a time (in the order 0, 8, 2, $A, ...), then Y + 16.
; Callers (2 JSR sites): BattleCD_TileVFlip2 ($CD:122A) and BattleCD_TileHFlip2 ($CD:1276).
; Callers note: also BattleCD_TileHandlers2 entry 0 (JSR (T,X) in
;   BattleCD_LoadFxTiles).
; Entry: M=0, X=0, DP=0, DB=$7E; DP $53-$55 = the entry's address
; Exit:  M=0, X=0; Y + 16; A = the new Y; X = the source offset
BattleCD_TileCopy2:
    LDA.b [!BattleCD_Tmp53]
    AND.w #!BattleCD_TileNumMask
    ASL A
    ASL A
    ASL A
    TAX
    LDA.l !BattleRom_FxTileGfx,X
    STA.w !Battle_ActFrameBuf,Y
    LDA.l !BattleRom_FxTileGfx+8,X
    STA.w !Battle_ActFrameBuf+8,Y
    LDA.l !BattleRom_FxTileGfx+2,X
    STA.w !Battle_ActFrameBuf+2,Y
    LDA.l !BattleRom_FxTileGfx+10,X
    STA.w !Battle_ActFrameBuf+10,Y
    LDA.l !BattleRom_FxTileGfx+4,X
    STA.w !Battle_ActFrameBuf+4,Y
    LDA.l !BattleRom_FxTileGfx+12,X
    STA.w !Battle_ActFrameBuf+12,Y
    LDA.l !BattleRom_FxTileGfx+6,X
    STA.w !Battle_ActFrameBuf+6,Y
    LDA.l !BattleRom_FxTileGfx+14,X
    STA.w !Battle_ActFrameBuf+14,Y
    TYA
    CLC
    ADC.w #!BattleCD_Tile2Bytes
    TAY
    RTS

; $CD:1300 — BattleCD_PlaneMasks (4 words, $1300–$1307)
; Masks for the upper two bit planes of a 4bpp tile built from a 2bpp
; one (BattleCD_Tile4Planes): by a 2-bit value, none, plane 2, plane 3,
; both (the pixels' colour + 0, 4, 8 or 12).
BattleCD_PlaneMasks:
    dw $0000,$00FF,$FF00,$FFFF

; $CD:1308 — BattleCD_FxGfxVram (6 words, $1308–$1313)
; VRAM word addresses of the six graphics parts BattleCD_LoadFxGfx2/4
; upload, $400 bytes each: $0C00, $0E00, ..., $1600.
BattleCD_FxGfxVram:
    dw $0C00,$0E00,$1000,$1200,$1400,$1600

; ============================================================
; Action graphics ($CD:1314–$CD:15D4)
; ============================================================

; $CD:1314 — BattleCD_LoadFxGfx2 (84 bytes, $1314–$1367)
; Loads the action's graphics sets (BattleAct_LoadCommon, A =
; !Battle_ActGfxSetB): sets A and A+1 as parts 4 and 5.
; BattleCD_LoadFxGfx4 ($1323, A = !Battle_ActGfxSetA): sets A to A+3 as
; parts 0-3. Both: a frame (BattleCD_WaitFrameRefresh), then per part:
; 32 4bpp tiles of the set built in !Battle_ActFrameBuf
; (BattleCD_ConvertFxGfx, X = the set) and uploaded ($400 bytes,
; BattleCD_QueueVramDma) to VRAM BattleCD_FxGfxVram entry part; the set
; (!Battle_FxTileSet) and part (!Battle_FxGfxPart) + 1, up to the end
; part (!Battle_FxGfxEnd).
; Callers (1 JMP site): BattleAnim_LoadGfx2Vec ($CD:002A).
; Callers of BattleCD_LoadFxGfx4 (1 JMP site): BattleAnim_LoadGfx4Vec ($CD:0015).
; Entry: M=1, X=0, DP=0, DB=$7E; A = the first set; B = 0 assumed for
;        the 16-bit TAX of the set (the waits before it are not traced)
; Exit:  M=1, X=0, DP=0, DB=$7E (RTL); A, X, Y clobbered; DP $53-$69
;        written
; Sub-entry: BattleCD_LoadFxGfx4 ($1323), as above.
BattleCD_LoadFxGfx2:
    STA.w !Battle_FxTileSet
    LDA.b #4
    STA.w !Battle_FxGfxPart
    LDA.b #6
    STA.w !Battle_FxGfxEnd
    BRA BattleCD_LoadFxGfx4_parts
BattleCD_LoadFxGfx4:                    ; header: see BattleCD_LoadFxGfx2
    STA.w !Battle_FxTileSet
    STZ.w !Battle_FxGfxPart
    LDA.b #4
    STA.w !Battle_FxGfxEnd
.parts:
    JSR BattleCD_WaitFrameRefresh
.part:
    LDX.w #!BattleCD_GfxPartTiles
    STX.b !BattleCD_Tmp67               ; tiles left
    LDA.w !Battle_FxTileSet
    TAX
    JSR BattleCD_ConvertFxGfx
    LDA.w !Battle_FxGfxPart
    ASL A
    TAX
    REP #$20
    LDA.l BattleCD_FxGfxVram,X
    TAY
    TDC
    SEP #$20
    LDX.w #!BattleCD_FxSetBytes
    STX.b !BattleCD_Tmp53               ; byte count for BattleCD_QueueVramDma
    LDX.w #!Battle_ActFrameBuf
    LDA.b #!Battle_WramBank
    JSR BattleCD_QueueVramDma
    INC.w !Battle_FxTileSet
    INC.w !Battle_FxGfxPart
    LDA.w !Battle_FxGfxPart
    CMP.w !Battle_FxGfxEnd
    BNE .part
    RTL

; $CD:1368 — BattleCD_ConvertFxGfx (98 bytes, $1368–$13C9)
; Builds DP $67 (the callers pass 32) 4bpp tiles of graphics set X in
; !Battle_ActFrameBuf from Y = 0: the set's entry words are at
; !BattleRom_FxGfxLists + X * 64 (DP $53-$55, bank $CF); the set's
; colour word from !BattleRom_FxGfxColours (X * 2) is put twice in
; !Battle_FxColourBits (4 bytes). For entry i (DP $5B), the 2-bit field
; (i AND 6) / 2 of byte (i AND $18) / 8 of those (BattleCD_PickPlaneBits)
; picks the BattleCD_PlaneMasks mask (DP $5F), and
; BattleCD_TileHandlers4 entry (bits 14-15 of the entry word) builds the
; tile. DP $59 is set to $CF too (not read on these paths).
; Callers (1 JSR site): BattleCD_LoadFxGfx4 ($CD:133A).
; Entry: M=1, X=0, DP=0, DB=$7E; X = the set; DP $67 = the tile count
; Exit:  M=1, X=0; A = 0 (B = 0); X clobbered; Y = 32 * the count; DP
;        $53-$69 written
BattleCD_ConvertFxGfx:
    LDA.b #!BattleRom_FxGfxLists>>16
    STA.b !BattleCD_Tmp53+2
    LDA.b #!BattleRom_FxGfxLists>>16
    STA.b !BattleCD_Tmp59
    REP #$20
    TXA
    ASL A
    STA.b !BattleCD_Tmp57               ; the set * 2
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC.w #!BattleRom_FxGfxLists&$FFFF
    STA.b !BattleCD_Tmp53               ; the entry
    LDX.b !BattleCD_Tmp57
    LDA.l !BattleRom_FxGfxColours,X
    STA.w !Battle_FxColourBits
    STA.w !Battle_FxColourBits+2
    TDC
    TAY
    STZ.b !BattleCD_FxTileNum
.tile:
    TDC
    SEP #$20
    LDA.b !BattleCD_FxTileNum
    AND.b #!BattleCD_ColourByteBits
    LSR A
    LSR A
    LSR A
    TAX
    LDA.w !Battle_FxColourBits,X
    STA.b !BattleCD_Tmp5D               ; the colour byte
    JSR BattleCD_PickPlaneBits
    TAX
    REP #$20
    LDA.l BattleCD_PlaneMasks,X
    STA.b !BattleCD_PlaneMask
    LDA.b [!BattleCD_Tmp53]
    XBA
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    AND.w #!BattleCD_FlipBits
    TAX
    JSR (BattleCD_TileHandlers4,X)
    INC.b !BattleCD_FxTileNum
    INC.b !BattleCD_Tmp53
    INC.b !BattleCD_Tmp53
    DEC.b !BattleCD_Tmp67
    BNE .tile
    TDC
    SEP #$20
    RTS

; $CD:13CA — BattleCD_PickPlaneBits (10 bytes, $13CA–$13D3)
; A = 2 * the 2-bit field (DP $5B AND 6) / 2 of the colour byte in DP $5D,
; through BattleCD_FieldShifts (a JMP into the shift chain
; BattleCD_ShiftField6, whose RTS returns for it).
; Callers (1 JSR site): BattleCD_ConvertFxGfx ($CD:13A1).
; Entry: M=1, X=0, DP=0, DB any; DP $5B = the tile number, DP $5D = the
;        byte; B = 0 for the 16-bit TAX (BattleCD_ConvertFxGfx's TDC)
; Exit:  M=1; A = the field * 2; X = (DP $5B AND 6); Y unchanged
BattleCD_PickPlaneBits:
    LDA.b !BattleCD_FxTileNum
    AND.b #6
    TAX
    LDA.b !BattleCD_Tmp5D
    JMP (BattleCD_FieldShifts,X)

; $CD:13D4 — BattleCD_FieldShifts (4 words, $13D4–$13DB)
; BattleCD_PickPlaneBits' entry points into the shift chain: field 0
; (bits 0-1, no shift), 1 (bits 2-3), 2 (bits 4-5), 3 (bits 6-7).
BattleCD_FieldShifts:
    dw BattleCD_ShiftField0
    dw BattleCD_ShiftField2
    dw BattleCD_ShiftField4
    dw BattleCD_ShiftField6

; $CD:13DC — BattleCD_ShiftField6 (10 bytes, $13DC–$13E5)
; A = (A >> 6 AND 3) * 2; the entries BattleCD_ShiftField4 ($13DE),
; BattleCD_ShiftField2 ($13E0) and BattleCD_ShiftField0 ($13E2) shift 4,
; 2 and 0 bits before the same AND and ASL.
; Callers note: none by call; BattleCD_FieldShifts' JMP (abs,X) in
;   BattleCD_PickPlaneBits reaches all four entries.
; Entry: M=1, X any, DP any, DB any; A = the byte
; Exit:  M=1; A = the field * 2; X, Y unchanged
; Sub-entries: BattleCD_ShiftField4, BattleCD_ShiftField2,
;   BattleCD_ShiftField0.
BattleCD_ShiftField6:
    LSR A
    LSR A
BattleCD_ShiftField4:                   ; header: see BattleCD_ShiftField6
    LSR A
    LSR A
BattleCD_ShiftField2:                   ; header: see BattleCD_ShiftField6
    LSR A
    LSR A
BattleCD_ShiftField0:                   ; header: see BattleCD_ShiftField6
    AND.b #3
    ASL A
    RTS

; $CD:13E6 — BattleCD_TileHandlers4 (4 words, $13E6–$13ED)
; BattleCD_ConvertFxGfx's tile builders by the entry's flip bits (bit 14
; = 2, bit 15 = 4).
BattleCD_TileHandlers4:
    dw BattleCD_Tile4Copy               ; no flip
    dw BattleCD_Tile4HFlip              ; horizontal
    dw BattleCD_Tile4VFlip              ; vertical
    dw BattleCD_Tile4VHFlip             ; both

; $CD:13EE — BattleCD_Tile4VHFlip (8 bytes, $13EE–$13F5)
; A 4bpp tile flipped both ways: BattleCD_Tile4VFlip at Y, then the
; horizontal flip (JMP BattleCD_TileReverse4) at the same Y.
; Callers note: none by call; BattleCD_TileHandlers4 entry 3 (JSR (T,X) in
;   BattleCD_ConvertFxGfx).
; Entry: M=0, X=0 (as BattleCD_ConvertFxGfx runs the handlers), DP=0,
;        DB=$7E; DP $53-$55 = the entry's address, DP $5F = the plane mask;
;        Y = the tile's offset
; Exit:  M=0, X=0; Y + 32; A, X clobbered; DP $57, $61, $65 and $69 written
BattleCD_Tile4VHFlip:
    PHY
    JSR BattleCD_Tile4VFlip
    PLY
    JMP BattleCD_TileReverse4

; $CD:13F6 — BattleCD_Tile4VFlip (79 bytes, $13F6–$1444)
; A 4bpp tile flipped vertically: BattleCD_Tile4Copy, then the eight
; row words of planes 0-1 swapped end for end (.rows, JSR'd), and those
; of planes 2-3 (.rows again, falling in, at Y + 16), using DP $69.
; Callers (1 JSR site): BattleCD_Tile4VHFlip ($CD:13EF).
; Callers note: also BattleCD_TileHandlers4 entry 2 (JSR (T,X) in
;   BattleCD_ConvertFxGfx).
; Entry: M=0, X=0, DP=0, DB=$7E; as BattleCD_Tile4Copy
; Exit:  M=0, X=0; Y + 32; A, X clobbered; DP $57, $65 and $69 written
BattleCD_Tile4VFlip:
    PHY
    JSR BattleCD_Tile4Copy
    PLY
    JSR .rows
.rows:
    LDA.w !Battle_ActFrameBuf,Y
    STA.b !BattleCD_Tmp69
    LDA.w !Battle_ActFrameBuf+14,Y
    STA.w !Battle_ActFrameBuf,Y
    LDA.b !BattleCD_Tmp69
    STA.w !Battle_ActFrameBuf+14,Y
    LDA.w !Battle_ActFrameBuf+2,Y
    STA.b !BattleCD_Tmp69
    LDA.w !Battle_ActFrameBuf+12,Y
    STA.w !Battle_ActFrameBuf+2,Y
    LDA.b !BattleCD_Tmp69
    STA.w !Battle_ActFrameBuf+12,Y
    LDA.w !Battle_ActFrameBuf+4,Y
    STA.b !BattleCD_Tmp69
    LDA.w !Battle_ActFrameBuf+10,Y
    STA.w !Battle_ActFrameBuf+4,Y
    LDA.b !BattleCD_Tmp69
    STA.w !Battle_ActFrameBuf+10,Y
    LDA.w !Battle_ActFrameBuf+6,Y
    STA.b !BattleCD_Tmp69
    LDA.w !Battle_ActFrameBuf+8,Y
    STA.w !Battle_ActFrameBuf+6,Y
    LDA.b !BattleCD_Tmp69
    STA.w !Battle_ActFrameBuf+8,Y
    TYA
    CLC
    ADC.w #!BattleCD_Tile2Bytes
    TAY
    RTS

; $CD:1445 — BattleCD_Tile4HFlip (67 bytes, $1445–$1487)
; A 4bpp tile flipped horizontally: BattleCD_Tile4Copy, then its 32
; bytes through BitReverseTable, 4 a pass (DP $61 counts 8 passes). The
; reversing part BattleCD_TileReverse4 ($144A) runs with 8-bit A (TDC
; first: B = 0 for the TAXs) and ends with REP #$20.
; Callers of BattleCD_TileReverse4 (1 JMP site): BattleCD_Tile4VHFlip ($CD:13F3).
; Callers note: none by call; BattleCD_TileHandlers4 entry 1 (JSR (T,X) in
;   BattleCD_ConvertFxGfx).
; Entry: M=0, X=0, DP=0, DB=$7E; as BattleCD_Tile4Copy
; Exit:  M=0, X=0; Y + 32; A, X clobbered; DP $57, $61 and $65 written
; Sub-entry: BattleCD_TileReverse4 ($144A), JMP'd by BattleCD_Tile4VHFlip
;   with Y = the tile's offset; same exit.
BattleCD_Tile4HFlip:
    PHY
    JSR BattleCD_Tile4Copy
    PLY
BattleCD_TileReverse4:                  ; header: see BattleCD_Tile4HFlip
    TDC
    SEP #$20
    LDA.b #8
    STA.b !BattleCD_Tmp61               ; passes left
.pass:
    LDA.w !Battle_ActFrameBuf,Y
    TAX
    LDA.l BitReverseTable,X
    STA.w !Battle_ActFrameBuf,Y
    LDA.w !Battle_ActFrameBuf+1,Y
    TAX
    LDA.l BitReverseTable,X
    STA.w !Battle_ActFrameBuf+1,Y
    LDA.w !Battle_ActFrameBuf+2,Y
    TAX
    LDA.l BitReverseTable,X
    STA.w !Battle_ActFrameBuf+2,Y
    LDA.w !Battle_ActFrameBuf+3,Y
    TAX
    LDA.l BitReverseTable,X
    STA.w !Battle_ActFrameBuf+3,Y
    INY
    INY
    INY
    INY
    DEC.b !BattleCD_Tmp61
    BNE .pass
    REP #$20
    RTS

; $CD:1488 — BattleCD_Tile4Planes (129 bytes, $1488–$1508)
; One 4bpp tile from a 2bpp one: for each of the 8 row words w at
; !BattleRom_FxGfxSrc + X (bank $D0): planes 0-1 = w, and planes 2-3
; (16 bytes on) = (w with its bytes swapped OR w) AND the plane mask in
; DP $5F, so each set pixel gets the colour offset the mask picks.
; Callers (2 JSR sites): BattleCD_Tile4Copy ($CD:151B, $CD:1525).
; Entry: M=0, X=0, DP=0, DB=$7E; X = the source offset; Y = the tile's
;        offset in !Battle_ActFrameBuf; DP $5F = the mask
; Exit:  M=0, X=0; A clobbered; X, Y unchanged
BattleCD_Tile4Planes:
    LDA.l !BattleRom_FxGfxSrc,X
    STA.w !Battle_ActFrameBuf,Y
    XBA
    ORA.w !Battle_ActFrameBuf,Y
    AND.b !BattleCD_PlaneMask
    STA.w !Battle_ActFrameBuf+16,Y
    LDA.l !BattleRom_FxGfxSrc+2,X
    STA.w !Battle_ActFrameBuf+2,Y
    XBA
    ORA.w !Battle_ActFrameBuf+2,Y
    AND.b !BattleCD_PlaneMask
    STA.w !Battle_ActFrameBuf+18,Y
    LDA.l !BattleRom_FxGfxSrc+4,X
    STA.w !Battle_ActFrameBuf+4,Y
    XBA
    ORA.w !Battle_ActFrameBuf+4,Y
    AND.b !BattleCD_PlaneMask
    STA.w !Battle_ActFrameBuf+20,Y
    LDA.l !BattleRom_FxGfxSrc+6,X
    STA.w !Battle_ActFrameBuf+6,Y
    XBA
    ORA.w !Battle_ActFrameBuf+6,Y
    AND.b !BattleCD_PlaneMask
    STA.w !Battle_ActFrameBuf+22,Y
    LDA.l !BattleRom_FxGfxSrc+8,X
    STA.w !Battle_ActFrameBuf+8,Y
    XBA
    ORA.w !Battle_ActFrameBuf+8,Y
    AND.b !BattleCD_PlaneMask
    STA.w !Battle_ActFrameBuf+24,Y
    LDA.l !BattleRom_FxGfxSrc+10,X
    STA.w !Battle_ActFrameBuf+10,Y
    XBA
    ORA.w !Battle_ActFrameBuf+10,Y
    AND.b !BattleCD_PlaneMask
    STA.w !Battle_ActFrameBuf+26,Y
    LDA.l !BattleRom_FxGfxSrc+12,X
    STA.w !Battle_ActFrameBuf+12,Y
    XBA
    ORA.w !Battle_ActFrameBuf+12,Y
    AND.b !BattleCD_PlaneMask
    STA.w !Battle_ActFrameBuf+28,Y
    LDA.l !BattleRom_FxGfxSrc+14,X
    STA.w !Battle_ActFrameBuf+14,Y
    XBA
    ORA.w !Battle_ActFrameBuf+14,Y
    AND.b !BattleCD_PlaneMask
    STA.w !Battle_ActFrameBuf+30,Y
    RTS

; $CD:1509 — BattleCD_Tile4Copy (204 bytes, $1509–$15D4)
; Builds the entry's 4bpp tile at Y from !BattleRom_FxGfxSrc + (entry
; AND $1FFF) * 8 (the entry word is kept in DP $65):
;   - entry bit 13 set: BattleCD_Tile4Planes (a 2bpp source);
;   - clear: BattleCD_Tile4Planes, then the 8 bytes after the 2bpp tile
;     (+16) as a third plane: for each row byte b, the planes-2/3 word w
;     becomes (w OR b) AND the mask, bytes swapped, OR b (b in DP $57).
; Then Y + 32.
; Callers (2 JSR sites): BattleCD_Tile4VFlip ($CD:13F7) and BattleCD_Tile4HFlip ($CD:1446).
; Callers note: also BattleCD_TileHandlers4 entry 0 (JSR (T,X) in
;   BattleCD_ConvertFxGfx).
; Entry: M=0, X=0, DP=0, DB=$7E; DP $53-$55 = the entry's address, DP
;        $5F = the plane mask; Y = the tile's offset
; Exit:  M=0, X=0; Y + 32; A = the new Y; X = the source offset (+ 16 on
;        the third-plane path); DP $57 and $65 written
BattleCD_Tile4Copy:
    LDA.b [!BattleCD_Tmp53]
    STA.b !BattleCD_Tmp65               ; the entry
    AND.w #!BattleCD_TileNumMask
    ASL A
    ASL A
    ASL A
    TAX
    LDA.b [!BattleCD_Tmp53]
    AND.w #!BattleCD_Tile2bppFlag
    BEQ .three_planes
    JSR BattleCD_Tile4Planes
    TYA
    CLC
    ADC.w #!BattleCD_Tile4Bytes
    TAY
    RTS
.three_planes:
    JSR BattleCD_Tile4Planes
    TXA
    CLC
    ADC.w #!BattleCD_Tile2Bytes
    TAX
    LDA.l !BattleRom_FxGfxSrc,X
    AND.w #!Battle_LowByteMask
    STA.b !BattleCD_Tmp57
    ORA.w !Battle_ActFrameBuf+16,Y
    AND.b !BattleCD_PlaneMask
    XBA
    ORA.b !BattleCD_Tmp57
    STA.w !Battle_ActFrameBuf+16,Y
    LDA.l !BattleRom_FxGfxSrc+1,X
    AND.w #!Battle_LowByteMask
    STA.b !BattleCD_Tmp57
    ORA.w !Battle_ActFrameBuf+18,Y
    AND.b !BattleCD_PlaneMask
    XBA
    ORA.b !BattleCD_Tmp57
    STA.w !Battle_ActFrameBuf+18,Y
    LDA.l !BattleRom_FxGfxSrc+2,X
    AND.w #!Battle_LowByteMask
    STA.b !BattleCD_Tmp57
    ORA.w !Battle_ActFrameBuf+20,Y
    AND.b !BattleCD_PlaneMask
    XBA
    ORA.b !BattleCD_Tmp57
    STA.w !Battle_ActFrameBuf+20,Y
    LDA.l !BattleRom_FxGfxSrc+3,X
    AND.w #!Battle_LowByteMask
    STA.b !BattleCD_Tmp57
    ORA.w !Battle_ActFrameBuf+22,Y
    AND.b !BattleCD_PlaneMask
    XBA
    ORA.b !BattleCD_Tmp57
    STA.w !Battle_ActFrameBuf+22,Y
    LDA.l !BattleRom_FxGfxSrc+4,X
    AND.w #!Battle_LowByteMask
    STA.b !BattleCD_Tmp57
    ORA.w !Battle_ActFrameBuf+24,Y
    AND.b !BattleCD_PlaneMask
    XBA
    ORA.b !BattleCD_Tmp57
    STA.w !Battle_ActFrameBuf+24,Y
    LDA.l !BattleRom_FxGfxSrc+5,X
    AND.w #!Battle_LowByteMask
    STA.b !BattleCD_Tmp57
    ORA.w !Battle_ActFrameBuf+26,Y
    AND.b !BattleCD_PlaneMask
    XBA
    ORA.b !BattleCD_Tmp57
    STA.w !Battle_ActFrameBuf+26,Y
    LDA.l !BattleRom_FxGfxSrc+6,X
    AND.w #!Battle_LowByteMask
    STA.b !BattleCD_Tmp57
    ORA.w !Battle_ActFrameBuf+28,Y
    AND.b !BattleCD_PlaneMask
    XBA
    ORA.b !BattleCD_Tmp57
    STA.w !Battle_ActFrameBuf+28,Y
    LDA.l !BattleRom_FxGfxSrc+7,X
    AND.w #!Battle_LowByteMask
    STA.b !BattleCD_Tmp57
    ORA.w !Battle_ActFrameBuf+30,Y
    AND.b !BattleCD_PlaneMask
    XBA
    ORA.b !BattleCD_Tmp57
    STA.w !Battle_ActFrameBuf+30,Y
    TYA
    CLC
    ADC.w #!BattleCD_Tile4Bytes
    TAY
    RTS

; ============================================================
; The layer effect's script channels ($CD:15D5–$CD:16B4)
; ============================================================
; Two channels, 16 bytes apart from !Battle_FxChannels: +0 running,
; +3-+5 the script pointer (24-bit), +6 the period, +7 the countdown,
; +8 a page base added to the script's page bytes. A script is a period
; byte (low nibble), then per step: $00-$7E a tilemap page (+ the base:
; !Battle_TilePageSrc = $D000 + page * $200, !Battle_TilePageReq + 1;
; BattleCD_NmiUploadText sends it), $7F a step with no page, $80-$FE an
; opcode (BattleCD_RunFxOp) and its operand, after which the next byte
; is read in the same step, $FF the end.

; $CD:15D5 — BattleCD_StartFxChannel (52 bytes, $15D5–$1608)
; Starts channel X (0 or $10) on script A: the pointer from
; !BattleRom_FxScriptPtrs entry A (bank $D1, through DP $53-$55), the
; period = its first byte AND $0F, the countdown + 1 (from 0: the first
; step comes on the next tick), the pointer + 1 stored, running + 1.
; Callers (1 JSR site): BattleCD_StartFxChannels ($CD:0D53).
; Entry: M=1, X=0, DP=0, DB=$7E; A = the script, B = 0 (the 16-bit ASL;
;        BattleCD_StartFxChannels' TDC leaves it); X = the channel's
;        offset
; Exit:  M=1, X=0; A = 0 (B = 0); X, Y as on entry; DP $53-$55 written
BattleCD_StartFxChannel:
    PHY
    PHX
    PHX
    REP #$20
    ASL A
    TAX
    LDA.l !BattleRom_FxScriptPtrs,X
    STA.b !BattleCD_Tmp53               ; the script
    TDC
    SEP #$20
    TAY
    PLX
    LDA.b #!BattleRom_FxScriptPtrs>>16
    STA.b !BattleCD_Tmp53+2
    STA.w !Battle_FxChannels+5,X
    LDA.b [!BattleCD_Tmp53],Y
    AND.b #!BattleCD_FxPeriodMask
    STA.w !Battle_FxChannels+6,X
    INC.w !Battle_FxChannels+7,X
    REP #$20
    LDA.b !BattleCD_Tmp53
    INC A
    STA.w !Battle_FxChannels+3,X
    TDC
    SEP #$20
    INC.w !Battle_FxChannels,X
    PLX
    PLY
    RTS

; $CD:1609 — BattleCD_StepFxChannels (75 bytes, $1609–$1653)
; The channels' tick (BattleCD_NmiMain, once a frame): nothing while
; !Battle_BgFxEnded is set or !Battle_Unk5D9B is 0. Else
; !Battle_LayerFxMode = 1 when the effect sets the screen
; (BattleCD_LayerFxSetsScreen), else 0; for each running channel the
; countdown - 1, and at 0 it is reloaded from the period and the script
; runs a step (BattleCD_RunFxScript). When neither channel runs (both
; counted idle in Y), !Battle_Unk5D9B = 0 and !Battle_BgFxEnded +
; 1 (BattleCD_FrameTick then ends the effect).
; Callers (1 JSR site): BattleCD_NmiMain ($CD:09AF).
; Entry: M=1, X=0, DP=0, DB=$7E (as BattleCD_NmiMain runs)
; Exit:  M=1, X=0 (assumed after the opcode handlers, not traced); A, X, Y
;        clobbered; DP $40-$43 written by the steps
BattleCD_StepFxChannels:
    LDA.w !Battle_BgFxEnded
    BNE .done
    LDA.w !Battle_Unk5D9B
    BEQ .done
    JSR BattleCD_LayerFxSetsScreen
    BCC .mode
    LDA.b #1
.mode:
    STA.w !Battle_LayerFxMode
    TDC
    TAX
    TAY
.channel:
    LDA.w !Battle_FxChannels,X
    BEQ .idle
    DEC.w !Battle_FxChannels+7,X
    BNE .next
    LDA.w !Battle_FxChannels+6,X
    STA.w !Battle_FxChannels+7,X
    PHY
    JSR BattleCD_RunFxScript
    PLY
    BRA .next
.idle:
    INY
.next:
    REP #$20
    TXA
    CLC
    ADC.w #!BattleCD_ChannelBytes
    TAX
    TDC
    SEP #$20
    CPX.w #!BattleCD_ChannelBlockBytes
    BNE .channel
    CPY.w #2
    BNE .done
    STZ.w !Battle_Unk5D9B
    INC.w !Battle_BgFxEnded
.done:
    RTS

; $CD:1654 — BattleCD_RunFxScript (82 bytes, $1654–$16A5)
; One step of channel X's script (see the banner), with the pointer in
; DP $40-$42: opcodes ($80-$FE) run (BattleCD_RunFxOp) and the pointer
; moves past their operand byte, until a page byte, $7F or $FF; a page
; byte or $7F stores the pointer past it; $FF stops the channel (running
; = 0) and leaves the pointer.
; Callers (1 JSR site): BattleCD_StepFxChannels ($CD:1631).
; Entry: M=1, X=0, DP=0, DB=$7E; X = the channel's offset; B = 0 for the
;        page arithmetic (the callers' TDC leaves it, and each opcode
;        handler is assumed to as well: not traced)
; Exit:  M=1, X=0 and X as on entry (assumed after the opcode handlers,
;        not traced); A, Y clobbered; DP $40-$43 written
BattleCD_RunFxScript:
    PHX
    LDY.w !Battle_FxChannels+3,X
    STY.b !BattleCD_FxScriptPtr
    LDA.w !Battle_FxChannels+5,X
    STA.b !BattleCD_FxScriptPtr+2
.byte:
    LDA.b [!BattleCD_FxScriptPtr]
    BMI .opcode
    CMP.b #!BattleCD_FxNoPage
    BNE .page
    REP #$20
    LDA.b !BattleCD_FxScriptPtr
    INC A
    STA.w !Battle_FxChannels+3,X
    TDC
    SEP #$20
    BRA .step_done
.page:
    CLC
    ADC.w !Battle_FxChannels+8,X
    REP #$20
    XBA
    ASL A
    CLC
    ADC.w #!Battle_FxTilemaps
    STA.w !Battle_TilePageSrc
    LDA.b !BattleCD_FxScriptPtr
    INC A
    STA.w !Battle_FxChannels+3,X
    TDC
    SEP #$20
    INC.w !Battle_TilePageReq
    BRA .step_done
.opcode:
    CMP.b #!BattleCD_FxEnd
    BEQ .end
    JSR BattleCD_RunFxOp
    LDY.b !BattleCD_FxScriptPtr
    INY
    STY.b !BattleCD_FxScriptPtr
    BRA .byte
.step_done:
    PLX
    RTS
.end:
    STZ.w !Battle_FxChannels,X
    PLX
    RTS

; $CD:16A6 — BattleCD_RunFxOp (15 bytes, $16A6–$16B4)
; Runs script opcode A ($80-$FE): DP $43 = X (the channel), the pointer
; in DP $40 past the opcode, then BattleCD_FxOpTable entry A - $80 (the
; 8-bit ASL drops bit 7; the 122 handlers, $CD:17A9 on, are not
; matched), and X back from DP $43.
; Callers (1 JSR site): BattleCD_RunFxScript ($CD:1695).
; Entry: M=1, X=0, DP=0, DB=$7E; A = the opcode, B = 0 (the 16-bit TAX
;        of the doubled opcode); X = the channel's offset
; Exit:  M=1 and X = the channel's offset as the handler leaves them
;        (assumed; not traced); A, Y as the handler leaves them
BattleCD_RunFxOp:
    STX.b !BattleCD_Tmp43
    ASL A
    TAX
    LDY.b !BattleCD_FxScriptPtr
    INY
    STY.b !BattleCD_FxScriptPtr
    JSR (BattleCD_FxOpTable,X)
    LDX.b !BattleCD_Tmp43
    RTS
