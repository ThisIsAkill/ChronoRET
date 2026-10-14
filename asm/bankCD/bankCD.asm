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
; bank-$D1 routines are matched (bankD1.asm, BattleFx_*), the bank-$CE
; ones and this bank's $CD:2A4A-$CD:3B5E are not (stubs in
; asm/include/unmatched_battle.asm).
;
; Unless a header says otherwise the code runs as the rest of the battle
; engine does: M=1, X=0, DP=0, DB=$7E. The exceptions are the NMI parts
; (BattleCD_NmiDispatch and what it runs), entered from the bank-$D1 NMI
; handler with DB=$00.
;
; Matched so far: $CD:0000-$CD:2A49 (up to the layer-effect script's
; opcode table and the handlers from $CD:17A9 to $CD:2A49) and
; $CD:3B5F-$CD:3FFF (the sound, math, frame-wait and VRAM-queue helpers
; and the bank's tail). The next part, from $CD:2A4A, is opcode $80's
; handler with its 29-word sub-table at $CD:2A51, then the handlers of
; opcodes $81-$86, $89-$8B and $90-$A0 (the last at $CD:30BE) and the
; code they call.
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
; The bank-$CD step of the battle's start: JSL BattleFx_Init
; ($D1:F1B0: it sets DB=$7E and DP=0, installs JML $D1:E77C / JML
; $D1:FE97 (BattleFx_Nmi / BattleFx_Irq) as the NMI and IRQ trampolines
; at $0500/$0504, runs BattleCD_ScrollStepL and BattleCD_InitHdmaDataL and
; zeroes or sets many of this bank's variables), then RTL.
; Callers (1 JMP site): BattleSys_VecCD0000 ($CD:0000).
; Entry: M=1, X=0 (as BattleCF_EnterBattle leaves them), DP any, DB any
;        (the callee sets DP=0 and DB=$7E itself, from its first bytes)
; Exit:  as BattleFx_Init leaves it: M=1, X=0, DP=0, DB=$7E; A = 0; X
;        and Y clobbered
BattleCD_EnterBattle:
    JSL BattleFx_Init
    RTL

; $CD:003E — BattleCD_ActOp80 (5 bytes, $003E–$0042)
; Action opcode $80's long call (BattleAct_OpRunVecCD001B, after it
; copied its operand bytes to !Battle_ActOp80Args): JSL BattleFx_Op80Dispatch
; ($D1:F67A), then RTL.
; Callers (1 JMP site): BattleAct_UnkVecCD001B ($CD:001B).
; Entry: M=1, X=0, DP=0, DB=$7E (as the action code runs)
; Exit:  as BattleFx_Op80Dispatch leaves it: M=1, X=0, DP=0, DB=$7E; A,
;        X and Y as its handler leaves them
BattleCD_ActOp80:
    JSL BattleFx_Op80Dispatch
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
; while one is up; the bank-$D1 NMI handler (BattleFx_Nmi, $D1:E7EC) counts
; !Battle_MsgTimer down while !Battle_MsgTiming is set and at 0 clears
; !Battle_MsgShown and !Battle_MsgTiming (and !Battle_ScriptMsgUp,
; setting !Battle_LastScriptMsg to $FF when it was set) and bumps
; !BattleFx_CeSetReload.

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
; it: plays the message's sound (BattleFx_MsgSfx entry A, unless $FF)
; through BattleCD_ApuCmd18 with X = !BattleCD_SfxArgCentre, starts the
; text (BattleCD_StartText, BattleCD_ShowText), waits 16 frames, then:
; message !Battle_EndUnkCD0021Arg waits !BattleCD_MsgFixedWait frames;
; any other waits up to BattleCD_GetMsgTime frames, and stops early on a
; frame that sees !Battle_PadHeld bit 7 (a button held). Then
; !Battle_MsgShown and !Battle_MsgTiming = 0, !BattleFx_CeSetReload + 1, and
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
    LDA.l BattleFx_MsgSfx,X
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
    INC.w !BattleFx_CeSetReload
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
; BattleCD_ClearTextGfx as a long call (JSL from BattleFx_Init at
; $D1:F3FE).
; Callers (1 JSL site): BattleFx_Init ($D1:F3FE).
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
; !Battle_MsgShown = !BattleCD_MsgShownOn and !BattleFx_CeSetReload + 1.
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
    INC.w !BattleFx_CeSetReload
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
; as the last one and nothing is shown; then nothing closes it here.
; BattleFx_Nmi's message timer (when !Battle_MsgTimer runs out while
; !Battle_MsgTiming is set) and BattleFx_Init (at the battle's start)
; clear it. Kept as found.
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
; sets !Battle_MsgShown = !BattleCD_MsgShownOn, !BattleFx_CeSetReload + 1, and
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
    INC.w !BattleFx_CeSetReload
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
; !BattleFx_CeSetReload + 1, !Battle_TextStepping = 1.
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
    INC.w !BattleFx_CeSetReload
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
;   - !BattleFx_CeSetBase = !BattleCD_CA25Unk0E, !BattleFx_CeSetReload + 1, a frame;
;   - with !Battle_Unk2A21 bit 0 set: BattleCD_LayerFx84 when
;     FieldBtl_Result is 0, else BattleCD_LayerFx87; with bit 4 set (and
;     bit 0 clear): BattleCD_LayerFx87 when FieldBtl_Result is non-zero;
;   - !BattleFx_CeSetBase = !BattleCD_CA25Unk08, !BattleFx_CeSetReload + 1, a frame;
;   - the NMI trampoline's target becomes BattleFx_NmiAlt ($D1:F4C0);
;     DP $45 = !Battle_Brightness (the brightness, which that handler
;     writes to INIDISP every NMI); waits
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
    STA.w !BattleFx_CeSetBase
    INC.w !BattleFx_CeSetReload
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
    STA.w !BattleFx_CeSetBase
    INC.w !BattleFx_CeSetReload
    JSR BattleCD_WaitFrame
    LDA.b #BattleFx_NmiAlt>>16
    STA.w !NmiTrampoline+3
    LDX.w #BattleFx_NmiAlt&$FFFF
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
; DP $47 = 1, then waits until something else sets it back to 0 (at
; both call sites the NMI handler is BattleFx_NmiAlt, which
; BattleCD_ExitBattle installs just before and which zeroes DP $47).
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
; (!Battle_ActRunning 0); and when !BattleFx_BgRequest is set and
; !BattleFx_BgLoading is 0, JSL BattleFx_LoadBgSet ($D1:ECF3) with
; A = !Battle_UnkCD45 and !BattleFx_BgRequest = 0. Last, always, the text
; step (BattleCD_StepText).
; Callers (5 sites: 4 JSL, 1 JMP): BattleSys_FrameTickVec (JMP $CD:0009), BattleCD_EnemyDissolve
;   (JSL $CD:0049), BattleCD_EnemyDissolveFx (JSL $CD:00FB), BattleCD_LayerFx84 (JSL $CD:0DDE) and
;   BattleCD_RunLayerFx (JSL $CD:0E1C).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E (RTL; as the callees leave them); A, X,
;        Y clobbered
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
    LDA.w !BattleFx_BgRequest
    BEQ .text
    LDA.w !BattleFx_BgLoading
    BNE .text
    LDA.w !Battle_UnkCD45
    JSL BattleFx_LoadBgSet
    STZ.w !BattleFx_BgRequest
.text:
    JSR BattleCD_StepText
    RTL

; $CD:04DF — BattleCD_StepText (30 bytes, $04DF–$04FC)
; When !Battle_TextStepping is set: one TextWin_Step (through
; BankC2_Entry0009) with TextWin_StepCount = 1; !Battle_TextStepping =
; TextWin_Status after it (0 once the string is done, so the stepping
; stops); !Battle_MsgTimer = BattleCD_GetMsgTime and !Battle_MsgTiming +
; 1 (the NMI closes the panel when the time is up).
; Callers (2 JSR sites): BattleCD_FrameTick ($CD:04DB) and BattleCD_WaitFrame ($CD:3E89).
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
; !BattleFx_CeSetBase = !BattleCD_CA25Unk0C and !BattleFx_CeSetReload + 1, a frame,
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
    STA.w !BattleFx_CeSetBase
    INC.w !BattleFx_CeSetReload
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
;     !BattleFx_CeSetBase = 0 and JSL BattleCE_UnkEE6E ($CE:EE6E, not matched;
;     A = !BattleFx_CeSet, set up the tables, probably), then the mode
;     becomes 1;
;   - 1-$7F: while !Battle_WipeSteps is non-zero, BattleCD_WipeStepOpen
;     and a step less; when that reaches 0, !BattleFx_CeSetBase =
;     !BattleCD_CA25Unk02 and !BattleFx_CeSetReload + 1; on the next call (no
;     steps left) !Battle_UnkCE16 = 0 and the mode = 0;
;   - $80-$FE (!BattleCD_WipeClose): BattleCD_WipeStepClose and a step
;     less; at 0, !BattleFx_CeSetBase = 0, !BattleFx_CeSetReload + 1 and the mode =
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
    STA.w !BattleFx_CeSetBase
    INC.w !BattleFx_CeSetReload
    BRA .done
.closing:
    CMP.b #!BattleCD_WipeOpen
    BNE .close_step
    STZ.w !BattleFx_CeSetBase
    LDA.w !BattleFx_CeSet
    JSL BattleCE_UnkEE6E
    LDA.b #1
    STA.w !Battle_WipeMode
    BRA .done
.close_step:
    JSR BattleCD_WipeStepClose
    DEC.w !Battle_WipeSteps
    BNE .done
    STZ.w !BattleFx_CeSetBase
    INC.w !BattleFx_CeSetReload
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
; The bank-$D1 NMI handler (BattleFx_Nmi, $D1:E77C) runs
; BattleCD_NmiDispatch every frame with M=1, X=0, DP=0 and DB=$00; it
; picks BattleCD_NmiSetup or BattleCD_NmiMain by !Battle_NmiMode.

; $CD:0607 — BattleCD_NmiUploadText (171 bytes, $0607–$06B1)
; BattleCD_NmiMain's uploads while no wipe runs:
;   - a tilemap page requested by the layer-effect script
;     (!Battle_TilePageReq, set by BattleCD_RunFxScript): unless it is
;     the same slot (!Battle_TilePageSlot) and page (!Battle_TilePageSrc)
;     as the last one (!Battle_LastPageSlot / !Battle_LastPageSrc),
;     JSL BattleFx_UploadMapBlock ($D1:E8D9) with A:X = $7E:the
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
    JSL BattleFx_UploadMapBlock
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
; !BattleFx_ShakeX + !Battle_FxScrollAddX + !Battle_ShakeOfs3X and
; !BattleFx_ShakeY + !BattleFx_BounceOut + !Battle_ShakeOfs3Y; then
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
    LDA.w !BattleFx_ShakeX
    CLC
    ADC.w !Battle_FxScrollAddX
    CLC
    ADC.w !Battle_ShakeOfs3X
    STA.b !BattleCD_Tmp4D
    LDA.w !BattleFx_ShakeY
    CLC
    ADC.w !BattleFx_BounceOut
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
    LDA.w !BattleFx_ShakeX
    CLC
    ADC.w !Battle_FxScrollAddX
    CLC
    ADC.w !Battle_ShakeOfs3X
    STA.b !BattleCD_Tmp4D
    LDA.w !BattleFx_ShakeY
    CLC
    ADC.w !BattleFx_BounceOut
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
;     unless the ROM byte !BattleRom_DebugSlowMo is non-zero (it is
;     0, so the screen is dimmed); the pad (BankC2_Entry8002,
;     BattleCD_PadRepeat); RTS;
;   - else INIDISP = !Battle_Brightness; the scroll data
;     (BattleCD_NmiLayerScroll); the shake (BattleCD_StepShake); on even
;     frames with no wipe: when !Battle_UnkEC differs from
;     !BattleFx_CeSetWant, the latter toggles (0/1) and !Battle_UnkEC takes
;     its value; and while
;     !BattleFx_Unk2989Copy bit 5 is clear a new press of !Battle_PadHeld bit 0
;     toggles them once more (!Battle_UnkCA23 holds it until the button
;     is let go);
;   - with !Battle_Unk2A21 bit 0: JSL BattleCE_UnkE18E, and on the frames
;     where !Battle_FrameCount AND !BattleFx_GradTickMask is 0 JSL
;     BattleFx_HpGradientTick;
;   - unless !Battle_UnkCD2D or !Battle_UnkA028: JSL BattleCE_UnkF066;
;     BankC1_VecCFE58A (the bank-$CF frame update); unless !Battle_UnkCD2E
;     or !Battle_UnkA028, while an action runs, BattleCD_WaitScanline with A =
;     !BattleCD_NmiWaitLine;
;   - the layer effect's script channels (BattleCD_StepFxChannels);
;     !Battle_UnkA028 = !Battle_UnkCD29; BattleCD_ClampPalAnims; JSL
;     BattleFx_HoldAnimsTick and FdVec_FFF7 (the palette
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
    LDA.l !BattleRom_DebugSlowMo
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
    CMP.w !BattleFx_CeSetWant
    BEQ .button
    LDA.w !BattleFx_CeSetWant
    INC A
    AND.b #1
    STA.w !BattleFx_CeSetWant
    STA.b !Battle_UnkEC
.button:
    LDA.w !BattleFx_Unk2989Copy
    AND.b #!Battle_2989NoPause
    BNE .released
    LDA.b !Battle_PadHeld
    AND.b #!BattleCD_PadToggleBit
    BEQ .released
    LDA.w !Battle_UnkCA23
    BNE .bank_ce
    LDA.w !BattleFx_CeSetWant
    INC A
    AND.b #1
    STA.w !BattleFx_CeSetWant
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
    AND.w !BattleFx_GradTickMask
    BNE .unk_ce_f066
    JSL BattleFx_HpGradientTick
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
    LDA.b #!BattleCD_NmiWaitLine
    JSR BattleCD_WaitScanline
.channels:
    JSR BattleCD_StepFxChannels
    LDA.w !Battle_UnkCD29
    STA.w !Battle_UnkA028
    JSR BattleCD_ClampPalAnims
    JSL BattleFx_HoldAnimsTick
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
; Callers (3 JSL sites): BattleCD_NmiMain ($CD:0893), BattleCD_NmiSetup ($CD:09F1) and
;   BattleFx_NmiAlt ($D1:F4DE).
; Entry: M=1, X=0 (the 16-bit STX pairs), DP any, DB=$00 (the registers
;        are written .w; both callers in this bank have DB=$00;
;        BattleFx_NmiAlt calls it with the interrupted code's DB, see
;        its header)
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
; (BattleCD_ScrollPlain), BattleCD_ClampPalAnims, JSL BattleFx_HoldAnimsTick
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
    JSL BattleFx_HoldAnimsTick
    JSL FdVec_FFF7
    JSR BattleCD_TickCDC9
    RTS

; $CD:0ADE — BattleCD_TickCDC9 (16 bytes, $0ADE–$0AED)
; While FieldAnimB[0].Unk4 (palette animation record 0's frame counter)
; is 0: !BattleFx_GradStart counts down and wraps from
; below 0 to !BattleCD_CDC9Period (a 14-frame cycle, 13 down to 0;
; BattleFx_HpGradientTick rotates the gradient's colours by it).
; Callers (2 JSR sites): BattleCD_NmiMain ($CD:09C3) and BattleCD_NmiSetup ($CD:0ADA).
; Entry: M=1, X any, DP any, DB=$7E
; Exit:  M=1; A clobbered; X, Y unchanged
BattleCD_TickCDC9:
    LDA.w FieldAnimB[0].Unk4
    BNE .done
    DEC.w !BattleFx_GradStart
    BPL .done
    LDA.b #!BattleCD_CDC9Period
    STA.w !BattleFx_GradStart
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
; Callers (8 JSR sites): BattleCD_StepShake ($CD:0B72, $CD:0BD7) and BattleCD_FxOpDrift ($CD:1A14,
;   $CD:1A1E, $CD:1A28, $CD:1A32, $CD:1A3C, $CD:1A46).
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
; (BattleFx_Nmi unless !Battle_Paused, BattleFx_Init and
; BattleFx_NmiAlt).
; Callers (3 JSL sites): BattleFx_Nmi ($D1:E7E3), BattleFx_Init ($D1:F1D7) and BattleFx_NmiAlt
;   ($D1:F549).
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
; the bank-$D1 NMI handler (BattleFx_Nmi, $D1:E7DA).
; Callers (1 JSL site): BattleFx_Nmi ($D1:E7DA).
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
; BattleCD_InitHdmaData as a long call (JSL from BattleFx_Init at
; $D1:F1DB).
; Callers (1 JSL site): BattleFx_Init ($D1:F1DB).
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
; !BattleFx_GradTickMask = 3, !BattleFx_GradForce = $80; the wait below once; 128
; more frames; effect !BattleCD_FxEnd84 (BattleCD_RunEndFx); and the wait
; again. The wait (.wait): two frames and a BattleCD_FrameTick, again
; while !BattleFx_GradLevel is 2 or more or any of !BattleFx_GradFading,
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
    STA.w !BattleFx_GradTickMask
    LDA.b #!BattleCD_CE0EInit
    STA.w !BattleFx_GradForce
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
    LDA.w !BattleFx_GradLevel
    CMP.b #2
    BCC .flags
    BRA .wait
.flags:
    LDA.w !BattleFx_GradFading
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
; BattleFx_Init) back to bytes $30-$3F of both !Battle_PaletteSavedLo
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
;     the wave flags !Battle_WaveBg1-3 and the words at
;     !BattleFx_BoxHalfHeight and !BattleFx_CountA = 0;
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
; Callers of BattleCD_LoadLayerFx_colours (2 JMP sites): BattleCD_FxOpColoursFromVar0A ($CD:1ABB)
;   and BattleCD_FxOpColours ($CD:1F44).
; BattleCD_LoadLayerFx_colours ($1004) is the colour-set step alone,
; entered by script opcodes $B9 and $D2 (BattleCD_FxOpColours,
; BattleCD_FxOpColoursFromVar0A) after they set both sets.
; Entry: M=1, X=0, DP=0, DB=$7E; X = the effect (not read by
;        BattleCD_LoadLayerFx_colours)
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered; DP $53-$75 written
;        (BattleCD_LoadLayerFx_colours: none)
; Sub-entry: BattleCD_LoadLayerFx_colours.
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
    STX.w !BattleFx_BoxHalfHeight
    STX.w !BattleFx_CountA
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
BattleCD_LoadLayerFx_colours:           ; header: see BattleCD_LoadLayerFx
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
; 8-bit ASL drops bit 7; the handlers start at $CD:17A9, the last at
; $CD:30BE, those from $CD:2A4A on not matched yet; $FA-$FE have no
; entry, see the banner after this routine), and X back from DP $43.
; Callers (1 JSR site): BattleCD_RunFxScript ($CD:1695).
; Entry: M=1, X=0, DP=0, DB=$7E; A = the opcode, B = 0 (the 16-bit TAX
;        of the doubled opcode); X = the channel's offset
; Exit:  M and the X flag as the handler leaves them (M=1, X=0 for the
;        matched handlers that call no unmatched code; the rest assumed,
;        not traced); X = the channel's offset (from DP $43); A, Y as the
;        handler leaves them
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

; ============================================================
; The layer-effect script opcodes ($CD:16B5 on)
; ============================================================
; BattleCD_RunFxOp runs opcode A ($80-$FE) through BattleCD_FxOpTable
; with: M=1, X=0, DP=0, DB=$7E; B = 0; DP $40-$42 pointing at the
; opcode's first operand byte (Y = the same low word); DP $43 = the
; channel's offset (0 or $10; X is put back from it afterwards); X =
; (opcode - $80) * 2. When the handler returns, BattleCD_RunFxScript
; moves DP $40 one byte on and reads the next script byte in the same
; step. So a handler with one operand byte leaves DP $40 alone, one with
; n bytes adds n - 1, one with none subtracts 1, and a branch sets DP
; $40 to its target - 1. The branch-back opcodes subtract an operand n
; from DP $40 (at the operand): the next byte read is n - 2 bytes before
; the opcode (n = 2 runs the opcode again: a wait). DP $40 is stepped
; 16-bit, never into the bank byte. RunFxScript also needs M=1, X=0 and
; B = 0 back (its page arithmetic); the handlers that call bank $D1 leave
; M=1, X=0 (each one's Exit gives A; opcode $88's leaves B = its fill
; word's high byte).
; Opcodes $FA-$FE have no entry: BattleCD_RunFxOp would read the words
; of the handler code after the table as their addresses (not traced
; whether any script uses them).
; The script opcodes share the action scripts' variables
; (!Battle_ActVars) and calculation results (!Battle_ActCalcResult).

; $CD:16B5 — BattleCD_FxOpTable (122 words, $16B5–$17A8)
; The handler of each script opcode $80-$F9, by (opcode - $80) * 2
; (JSR (T,X) in BattleCD_RunFxOp). $B5 and $B6 share a handler.
BattleCD_FxOpTable:
    dw BattleCD_FxOp80                 ; $80
    dw BattleCD_FxOp81                 ; $81
    dw BattleCD_FxOp82                 ; $82
    dw BattleCD_FxOp83                 ; $83
    dw BattleCD_FxOp84                 ; $84
    dw BattleCD_FxOp85                 ; $85
    dw BattleCD_FxOp86                 ; $86
    dw BattleCD_FxOpBumpCA24           ; $87
    dw BattleCD_FxOpFillWindow             ; $88
    dw BattleCD_FxOp89                 ; $89
    dw BattleCD_FxOp8A                 ; $8A
    dw BattleCD_FxOp8B                 ; $8B
    dw BattleCD_FxOpRegToWork          ; $8C
    dw BattleCD_FxOpWorkToReg          ; $8D
    dw BattleCD_FxOpPalAnim            ; $8E
    dw BattleCD_FxOpWaves              ; $8F
    dw BattleCD_FxOp90                 ; $90
    dw BattleCD_FxOp91                 ; $91
    dw BattleCD_FxOp92                 ; $92
    dw BattleCD_FxOp93                 ; $93
    dw BattleCD_FxOp94                 ; $94
    dw BattleCD_FxOp95                 ; $95
    dw BattleCD_FxOp96                 ; $96
    dw BattleCD_FxOp97                 ; $97
    dw BattleCD_FxOp98                 ; $98
    dw BattleCD_FxOp99                 ; $99
    dw BattleCD_FxOp9A                 ; $9A
    dw BattleCD_FxOp9B                 ; $9B
    dw BattleCD_FxOp9C                 ; $9C
    dw BattleCD_FxOp9D                 ; $9D
    dw BattleCD_FxOp9E                 ; $9E
    dw BattleCD_FxOp9F                 ; $9F
    dw BattleCD_FxOpA0                 ; $A0
    dw BattleCD_FxOp3657               ; $A1
    dw BattleCD_FxOpSetEllipse         ; $A2
    dw BattleCD_FxOpStepEllipse        ; $A3
    dw BattleCD_FxOpSetObjPhases       ; $A4
    dw BattleCD_FxOpSaveObjs           ; $A5
    dw BattleCD_FxOpLoadObjs           ; $A6
    dw BattleCD_FxOpSetObjAngles       ; $A7
    dw BattleCD_FxOpStepRing3d         ; $A8
    dw BattleCD_FxOpWaitVarSet         ; $A9
    dw BattleCD_FxOpScrollToCalc       ; $AA
    dw BattleCD_FxOpCalcToValues       ; $AB
    dw BattleCD_FxOpBeam               ; $AC
    dw BattleCD_FxOpTriCentre          ; $AD
    dw BattleCD_FxOpFillTriangle       ; $AE
    dw BattleCD_FxOpTriangleOfPcs      ; $AF
    dw BattleCD_FxOpBgMode             ; $B0
    dw BattleCD_FxOpScaleObj           ; $B1
    dw BattleCD_FxOpCEE000             ; $B2
    dw BattleCD_FxOpWaveTable          ; $B3
    dw BattleCD_FxOpCentreAndScroll    ; $B4
    dw BattleCD_FxOpWindowBand         ; $B5
    dw BattleCD_FxOpWindowBand         ; $B6
    dw BattleCD_FxOpTilePageSlot       ; $B7
    dw BattleCD_FxOp3924               ; $B8
    dw BattleCD_FxOpColours            ; $B9
    dw BattleCD_FxOpSpinModel          ; $BA
    dw BattleCD_FxOpDrawModel          ; $BB
    dw BattleCD_FxOpTurnObj            ; $BC
    dw BattleCD_FxOpSetObjD1           ; $BD
    dw BattleCD_FxOpDrawModel2         ; $BE
    dw BattleCD_FxOpWaitPalAnims       ; $BF
    dw BattleCD_FxOpShake              ; $C0
    dw BattleCD_FxOpWaitLine           ; $C1
    dw BattleCD_FxOpObjStepCapped      ; $C2
    dw BattleCD_FxOpIncVar0F           ; $C3
    dw BattleCD_FxOpCircleGrow         ; $C4
    dw BattleCD_FxOpCircleAtCalc       ; $C5
    dw BattleCD_FxOpWobble             ; $C6
    dw BattleCD_FxOpObjYToEnemy        ; $C7
    dw BattleCD_FxOpScrollYToEnemy     ; $C8
    dw BattleCD_FxOpSwapPalettes       ; $C9
    dw BattleCD_FxOpJump               ; $CA
    dw BattleCD_FxOpJumpIf99D2Is1      ; $CB
    dw BattleCD_ClampCalcAngle         ; $CC
    dw BattleCD_FxOpSetupBounce            ; $CD
    dw BattleCD_FxOpStepBounce             ; $CE
    dw BattleCD_FxOpMirrorWin1ToWin2             ; $CF
    dw BattleCD_FxOpSwitchLow          ; $D0
    dw BattleCD_FxOpSwitchHigh         ; $D1
    dw BattleCD_FxOpColoursFromVar0A   ; $D2
    dw BattleCD_FxOpValueAddVar0C      ; $D3
    dw BattleCD_FxOpValueSubVar09      ; $D4
    dw BattleCD_FxOpWaitValueZero      ; $D5
    dw BattleCD_FxOpWaitValueIsVar0E   ; $D6
    dw BattleCD_FxOpDrift              ; $D7
    dw BattleCD_FxOpAddVar             ; $D8
    dw BattleCD_FxOpBeamFromPair       ; $D9
    dw BattleCD_FxOpWedge              ; $DA
    dw BattleCD_FxOpCopyWin1ToWin2             ; $DB
    dw BattleCD_FxOpSound              ; $DC
    dw BattleCD_FxOpSaveCalcPoints             ; $DD
    dw BattleCD_FxOpSetCD29            ; $DE
    dw BattleCD_FxOpRandomShake             ; $DF
    dw BattleCD_FxOpSetCD2D            ; $E0
    dw BattleCD_FxOpSwapObjPalettes             ; $E1
    dw BattleCD_FxOpSetCD2E            ; $E2
    dw BattleCD_FxOpCalcToTriangle     ; $E3
    dw BattleCD_FxOpSoundAtCalc        ; $E4
    dw BattleCD_FxOpIncVar             ; $E5
    dw BattleCD_FxOpSetHoldAnims            ; $E6
    dw BattleCD_FxOpWaveBg3            ; $E7
    dw BattleCD_FxOpGrowBox             ; $E8
    dw BattleCD_FxOpAddBoxInset             ; $E9
    dw BattleCD_FxOpSetBackdrop        ; $EA
    dw BattleCD_FxOpWaveWindowBByFrame             ; $EB
    dw BattleCD_FxOpRampWin2             ; $EC
    dw BattleCD_FxOpWaveWindowA             ; $ED
    dw BattleCD_FxOpGrowBand             ; $EE
    dw BattleCD_FxOpCountCD3C          ; $EF
    dw BattleCD_FxOpValueFromVar0F     ; $F0
    dw BattleCD_FxOpWaitBgSet         ; $F1
    dw BattleCD_FxOpRequestBgSet         ; $F2
    dw BattleCD_FxOpWaveWindowB             ; $F3
    dw BattleCD_FxOpSwayQuad             ; $F4
    dw BattleCD_FxOpSetCD46            ; $F5
    dw BattleCD_FxOpWaitCE10           ; $F6
    dw BattleCD_FxOpSetCE0E            ; $F7
    dw BattleCD_FxOpCopyColour         ; $F8
    dw BattleCD_FxOpPokeByte           ; $F9

; $CD:17A9 — BattleCD_FxOpPokeByte (21 bytes, $17A9–$17BD)
; Opcode $F9 (value, address word): stores the value at that address in
; bank $7E. Quirk: DP $40 is stepped one byte only, so with the step
; BattleCD_RunFxScript adds the address's high byte is read as the next
; script byte (whether any script uses the opcode is not traced).
; Callers note: BattleCD_FxOpTable entry $F9 (as every handler below:
;   see the banner).
; Entry: M=1, X=0, DP=0, DB=$7E (the store is .w in bank $7E); DP $40 at
;        the operand
; Exit:  M=1, X=0; A = the value (B = 0, TDC); X = the address; Y = 1;
;        DP $40 + 1
BattleCD_FxOpPokeByte:
    LDA.b [!BattleCD_FxScriptPtr]
    PHA
    LDY.w #1
    REP #$20
    LDA.b [!BattleCD_FxScriptPtr],Y
    TAX
    INC.b !BattleCD_FxScriptPtr
    TDC
    SEP #$20
    PLA
    STA.w !Battle_WramAbs,X
    RTS

; $CD:17BE — BattleCD_FxOpCopyColour (33 bytes, $17BE–$17DE)
; Opcode $F8 (source, destination): copies colour source to colour
; destination (0-255) in both !Battle_PaletteSavedLo and
; !Battle_PaletteLiveLo.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX of the source);
;        DP $40 at the operands
; Exit:  M=1, X=0; A = 0 (B = 0); X = source * 2, Y = destination * 2;
;        DP $40 + 1 (two operand bytes)
BattleCD_FxOpCopyColour:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDY.w #1
    LDA.b [!BattleCD_FxScriptPtr],Y
    REP #$20
    ASL A
    TAY
    TXA
    ASL A
    TAX
    LDA.w !Battle_PaletteSavedLo,X
    STA.w !Battle_PaletteSavedLo,Y
    LDA.w !Battle_PaletteLiveLo,X
    STA.w !Battle_PaletteLiveLo,Y
    INC.b !BattleCD_FxScriptPtr
    TDC
    SEP #$20
    RTS

; $CD:17DF — BattleCD_FxOpSetCE0E (6 bytes, $17DF–$17E4)
; Opcode $F7 (value): !BattleFx_GradForce = the value.
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operand
; Exit:  M=1, X=0; A = the value; X, Y unchanged
BattleCD_FxOpSetCE0E:
    LDA.b [!BattleCD_FxScriptPtr]
    STA.w !BattleFx_GradForce
    RTS

; $CD:17E5 — BattleCD_FxOpWaitCE10 (26 bytes, $17E5–$17FE)
; Opcode $F6 (n): while !BattleFx_GradRotRaw is 0, branches back n (see the
; banner); then (and always) !BattleFx_GradRotRaw = 0. Who sets
; !BattleFx_GradRotRaw is not traced.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  M=1, X=0; branch: A = 0 (B = 0), X = n, DP $40 - n; else A =
;        the non-zero byte, X unchanged; Y unchanged
BattleCD_FxOpWaitCE10:
    LDA.w !BattleFx_GradRotRaw
    BNE .clear
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    STX.b !BattleCD_Tmp45
    REP #$20
    LDA.b !BattleCD_FxScriptPtr
    SEC
    SBC.b !BattleCD_Tmp45
    STA.b !BattleCD_FxScriptPtr
    TDC
    SEP #$20
.clear:
    STZ.w !BattleFx_GradRotRaw
    RTS

; $CD:17FF — BattleCD_FxOpSetCD46 (6 bytes, $17FF–$1804)
; Opcode $F5 (value): !BattleFx_UnkCD46 = the value.
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operand
; Exit:  M=1, X=0; A = the value; X, Y unchanged
BattleCD_FxOpSetCD46:
    LDA.b [!BattleCD_FxScriptPtr]
    STA.w !BattleFx_UnkCD46
    RTS

; $CD:1805 — BattleCD_FxOpSwayQuad (5 bytes, $1805–$1809)
; Opcode $F4 (quad): JSL BattleFx_SwayQuad, which reads the operand
; through DP $40: fills that quad of !BattleFx_Quads with a beam from
; the top of the screen, swaying with the frame count, down to the
; point in !Battle_ActCalcResult, and draws it (BattleFx_DrawQuad).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  as BattleFx_DrawQuad leaves it: M=1, X=0; A = 0; X, Y clobbered;
;        DP $03-$19 and $45-$4A written
BattleCD_FxOpSwayQuad:
    JSL BattleFx_SwayQuad
    RTS

; $CD:180A — BattleCD_FxOpRequestBgSet (9 bytes, $180A–$1812)
; Opcode $F2 (value): asks BattleCD_FrameTick for one JSL
; BattleFx_LoadBgSet with A = the value (!Battle_UnkCD45 = the value,
; !BattleFx_BgRequest + 1).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operand
; Exit:  M=1, X=0; A = the value; X, Y unchanged
BattleCD_FxOpRequestBgSet:
    LDA.b [!BattleCD_FxScriptPtr]
    STA.w !Battle_UnkCD45
    INC.w !BattleFx_BgRequest
    RTS

; $CD:1813 — BattleCD_FxOpWaitBgSet (23 bytes, $1813–$1829)
; Opcode $F1 (n): while !BattleFx_BgRequest is set (the call opcode $F2
; asked for has not run yet), branches back n (see the banner).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  M=1, X=0; branch: A = 0 (B = 0), X = n, DP $40 - n; else A =
;        0, X unchanged; Y unchanged
BattleCD_FxOpWaitBgSet:
    LDA.w !BattleFx_BgRequest
    BEQ .done
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    STX.b !BattleCD_Tmp45
    REP #$20
    LDA.b !BattleCD_FxScriptPtr
    SEC
    SBC.b !BattleCD_Tmp45
    STA.b !BattleCD_FxScriptPtr
    TDC
    SEP #$20
.done:
    RTS

; $CD:182A — BattleCD_FxOpValueFromVar0F (10 bytes, $182A–$1833)
; Opcode $F0 (n): !Battle_FxValues entry n = variable $0F
; (!Battle_ActVars).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  M=1, X=0; A = the variable; X = n; Y unchanged
BattleCD_FxOpValueFromVar0F:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.w !Battle_ActVar0F
    STA.w !Battle_FxValues,X
    RTS

; $CD:1834 — BattleCD_FxOpCountCD3C (23 bytes, $1834–$184A)
; Opcode $EF (no operand): !Battle_UnkCD3C + 1; when it wraps to 0, the
; palette animation records 8-11 are stopped (FieldAnimB .Unk0 = 0).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 past the opcode
; Exit:  M=1, X=0; A, X unchanged; Y = DP $40 - 1 (no operand byte)
BattleCD_FxOpCountCD3C:
    INC.w !Battle_UnkCD3C
    BNE .done
    STZ.w FieldAnimB[11].Unk0
    STZ.w FieldAnimB[10].Unk0
    STZ.w FieldAnimB[9].Unk0
    STZ.w FieldAnimB[8].Unk0
.done:
    LDY.b !BattleCD_FxScriptPtr
    DEY
    STY.b !BattleCD_FxScriptPtr
    RTS

; $CD:184B — BattleCD_FxOpWaveWindowB (5 bytes, $184B–$184F)
; Opcode $F3 (step): JSL BattleFx_WaveWindowB, which reads the operand
; through DP $40: !BattleFx_CountA grows by it and window table 0 gets
; wavy edges (angles from !BattleFx_CountB, which counts up).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  as BattleFx_WaveWindowB leaves it: M=1, X=0; A = 0; X
;        clobbered; Y = !BattleFx_WinUsedBytes; DP $45-$52 written
BattleCD_FxOpWaveWindowB:
    JSL BattleFx_WaveWindowB
    RTS

; $CD:1850 — BattleCD_FxOpGrowBand (5 bytes, $1850–$1854)
; Opcode $EE (kind): JSL BattleFx_GrowBand, which reads the operand
; through DP $40: a band around the point in !Battle_ActCalcResult, one
; step wider per run, into this frame's window table (0 a column, else
; a row).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  as BattleFx_GrowBand leaves it: M=1, X=0; A = 0; X clobbered;
;        Y unchanged; DP $45/$46 written
BattleCD_FxOpGrowBand:
    JSL BattleFx_GrowBand
    RTS

; $CD:1855 — BattleCD_FxOpWaveWindowA (5 bytes, $1855–$1859)
; Opcode $ED (step): JSL BattleFx_WaveWindowA, which reads the operand
; through DP $40: !BattleFx_CountA grows by it and window table 0 gets
; wavy edges (angles from the frame count).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  as BattleFx_WaveWindowA leaves it: M=1, X=0; A = 0; X
;        clobbered; Y = !BattleFx_WinUsedBytes; DP $45-$52 written
BattleCD_FxOpWaveWindowA:
    JSL BattleFx_WaveWindowA
    RTS

; $CD:185A — BattleCD_FxOpRampWin2 (5 bytes, $185A–$185E)
; Opcode $EC (one operand byte, which nothing reads): JSL
; BattleFx_RampWin2 (a ramp of left edges into the second pairs of
; window table 0, up from line !BattleFx_RampBottom - !BattleFx_CountA;
; !BattleFx_CountA counts up).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX)
; Exit:  as BattleFx_RampWin2 leaves it: M=1, X=0; A = 0; X unchanged;
;        Y clobbered
BattleCD_FxOpRampWin2:
    JSL BattleFx_RampWin2
    RTS

; $CD:185F — BattleCD_FxOpWaveWindowBByFrame (5 bytes, $185F–$1863)
; Opcode $EB (step): JSL BattleFx_WaveWindowB_ByFrame (BattleFx_WaveWindowB
; with the angles from the frame count), which reads the operand
; through DP $40.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  as BattleFx_WaveWindowB_ByFrame leaves it: M=1, X=0; A = 0; X
;        clobbered; Y = !BattleFx_WinUsedBytes; DP $45-$52 written
BattleCD_FxOpWaveWindowBByFrame:
    JSL BattleFx_WaveWindowB_ByFrame
    RTS

; $CD:1864 — BattleCD_FxOpSetBackdrop (16 bytes, $1864–$1873)
; Opcode $EA (colour word): colour 0 (the backdrop) of both
; !Battle_PaletteSavedLo and !Battle_PaletteLiveLo = the word.
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operands
; Exit:  M=1, X=0; A = 0 (B = 0); X, Y unchanged; DP $40 + 1 (two
;        operand bytes)
BattleCD_FxOpSetBackdrop:
    REP #$20
    LDA.b [!BattleCD_FxScriptPtr]
    STA.w !Battle_PaletteSavedLo
    STA.w !Battle_PaletteLiveLo
    INC.b !BattleCD_FxScriptPtr
    TDC
    SEP #$20
    RTS

; $CD:1874 — BattleCD_FxOpGrowBox (5 bytes, $1874–$1878)
; Opcode $E8 (step): JSL BattleFx_GrowBox, which reads the operand
; through DP $40: !BattleFx_BoxHalfHeight grows by it and this frame's
; window table gets a box centred on line 106.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  as BattleFx_GrowBox leaves it: M=1, X=0; A = 0; X clobbered; Y
;        unchanged; DP $45/$46, $49, $4A written
BattleCD_FxOpGrowBox:
    JSL BattleFx_GrowBox
    RTS

; $CD:1879 — BattleCD_FxOpAddBoxInset (5 bytes, $1879–$187D)
; Opcode $E9 (step): JSL BattleFx_AddBoxInset, which adds the operand
; (read through DP $40) to !BattleFx_BoxInset.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  as BattleFx_AddBoxInset leaves it: M=1; A = the new inset; X, Y
;        unchanged
BattleCD_FxOpAddBoxInset:
    JSL BattleFx_AddBoxInset
    RTS

; $CD:187E — BattleCD_FxOpWaveBg3 (68 bytes, $187E–$18C1)
; Opcode $E7 (n): layer 3's wave scroll. !Battle_LayerFxMode = 3,
; !Battle_WaveBg3's low byte = n. n $00-$7F adds n to
; !Battle_FxWaveOfs, $FF keeps it, $80-$FE zeroes it. Then the scroll
; entries 0-31 of !Battle_WaveOffsets get the offset (0-255) as their x
; word and entries 32-63 (!Battle_WaveOffsets2) its negation; the
; entries' second words are zeroed.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit offset; the $00-$7F
;        path keeps the entry B); DP $40 at the operand
; Exit:  M=1, X=0; A = 0 (B = 0); X = $80; Y unchanged; DP $45 = the
;        offset, DP $47 = its negation
BattleCD_FxOpWaveBg3:
    LDA.b #!BattleCD_ScrollWavesBg3Mode
    STA.w !Battle_LayerFxMode
    LDA.b [!BattleCD_FxScriptPtr]
    STA.w !Battle_WaveBg3
    BPL .add
    CMP.b #!BattleCD_FxWaveKeep
    BEQ .keep
    STZ.w !Battle_FxWaveOfs
.keep:
    TDC
.add:
    CLC
    ADC.w !Battle_FxWaveOfs
    STA.w !Battle_FxWaveOfs
    REP #$20
    STA.b !BattleCD_Tmp45
    EOR.w #!Battle_Invert16
    INC A
    STA.b !BattleCD_Tmp47
    TDC
    TAX
.entry:
    LDA.b !BattleCD_Tmp45
    STA.w !Battle_WaveOffsets,X
    STZ.w !Battle_WaveOffsets+2,X
    LDA.b !BattleCD_Tmp47
    STA.w !Battle_WaveOffsets2,X
    STZ.w !Battle_WaveOffsets2+2,X
    INX
    INX
    INX
    INX
    CPX.w #!BattleCD_ScrollFillEnd
    BNE .entry
    TDC
    SEP #$20
    RTS

; $CD:18C2 — BattleCD_FxOpSetHoldAnims (6 bytes, $18C2–$18C7)
; Opcode $E6 (value): !BattleFx_HoldAnims = the value (non-zero holds the
; palette animations, BattleFx_HoldAnimsTick; action opcodes $2D/$2E set
; it too).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operand
; Exit:  M=1, X=0; A = the value; X, Y unchanged
BattleCD_FxOpSetHoldAnims:
    LDA.b [!BattleCD_FxScriptPtr]
    STA.w !BattleFx_HoldAnims
    RTS

; $CD:18C8 — BattleCD_FxOpIncVar (7 bytes, $18C8–$18CE)
; Opcode $E5 (n): variable n (!Battle_ActVars) + 1.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  M=1, X=0; A = n; X = n; Y unchanged
BattleCD_FxOpIncVar:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    INC.w !Battle_ActVars,X
    RTS

; $CD:18CF — BattleCD_FxOpSoundAtCalc (16 bytes, $18CF–$18DE)
; Opcode $E4 (sound): leaves the sound pending for
; BattleCD_PlayPendingSfx (BattleCD_FrameTick) with X = the first byte
; of !Battle_ActCalcResult (an x, probably: the pan).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  M=1, X=0; A, X = that byte; Y unchanged
BattleCD_FxOpSoundAtCalc:
    LDA.b [!BattleCD_FxScriptPtr]
    STA.w !Battle_SfxPendingId
    LDA.w !Battle_ActCalcResult
    TAX
    STX.w !Battle_SfxPendingArg
    INC.w !Battle_SfxPending
    RTS

; $CD:18DF — BattleCD_FxOpCalcToTriangle (40 bytes, $18DF–$1906)
; Opcode $E3 (object 0/1): the object's three screen points
; (!Battle_FxTriX0-Y2) = the six bytes of !Battle_ActCalcResult entries
; 0-2 (x, y of each).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  M=1, X=0; A = the last byte copied; X = the object; Y unchanged
BattleCD_FxOpCalcToTriangle:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.w !Battle_ActCalcResult
    STA.w !Battle_FxTriX0,X
    LDA.w !Battle_ActCalcResult+2
    STA.w !Battle_FxTriX1,X
    LDA.w !Battle_ActCalcResult+4
    STA.w !Battle_FxTriX2,X
    LDA.w !Battle_ActCalcResult+1
    STA.w !Battle_FxTriY0,X
    LDA.w !Battle_ActCalcResult+3
    STA.w !Battle_FxTriY1,X
    LDA.w !Battle_ActCalcResult+5
    STA.w !Battle_FxTriY2,X
    RTS

; $CD:1907 — BattleCD_FxOpSetCD2E (6 bytes, $1907–$190C)
; Opcode $E2 (value): !Battle_UnkCD2E = the value (non-zero: the NMI
; skips its BattleCD_WaitScanline).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operand
; Exit:  M=1, X=0; A = the value; X, Y unchanged
BattleCD_FxOpSetCD2E:
    LDA.b [!BattleCD_FxScriptPtr]
    STA.w !Battle_UnkCD2E
    RTS

; $CD:190D — BattleCD_FxOpSetCD2D (6 bytes, $190D–$1912)
; Opcode $E0 (value): !Battle_UnkCD2D = the value (non-zero: the NMI
; skips BattleCE_UnkF066).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operand
; Exit:  M=1, X=0; A = the value; X, Y unchanged
BattleCD_FxOpSetCD2D:
    LDA.b [!BattleCD_FxScriptPtr]
    STA.w !Battle_UnkCD2D
    RTS

; $CD:1913 — BattleCD_FxOpRandomShake (5 bytes, $1913–$1917)
; Opcode $DF (base x, base y, mask): JSL BattleFx_RandomShake, which
; reads the three operand bytes through DP $40 (and moves DP $40 on by
; 2): the channel's !BattleFx_ShakeX/Y = -(random & mask + base).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operands, DP $43 = the channel
; Exit:  as BattleFx_RandomShake leaves it: M=1, X=0; A = 0; X = the
;        channel; Y = DP $40's new low word; DP $45, $47, $49 written
BattleCD_FxOpRandomShake:
    JSL BattleFx_RandomShake
    RTS

; $CD:1918 — BattleCD_FxOpSetCD29 (6 bytes, $1918–$191D)
; Opcode $DE (value): !Battle_UnkCD29 = the value (the NMI copies it
; to !Battle_UnkA028 every frame).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operand
; Exit:  M=1, X=0; A = the value; X, Y unchanged
BattleCD_FxOpSetCD29:
    LDA.b [!BattleCD_FxScriptPtr]
    STA.w !Battle_UnkCD29
    RTS

; $CD:191E — BattleCD_FxOpSaveCalcPoints (5 bytes, $191E–$1922)
; Opcode $DD (object): JSL BattleFx_SaveCalcPoints, which reads the
; operand through DP $40: the object's triangle (!Battle_FxTriX0-Y2) =
; the six bytes of !Battle_ActCalcResult.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  as BattleFx_SaveCalcPoints leaves it: M=1, X=0; A =
;        !Battle_ActCalcResult+5; X = the object; Y unchanged
BattleCD_FxOpSaveCalcPoints:
    JSL BattleFx_SaveCalcPoints
    RTS

; $CD:1923 — BattleCD_FxOpSound (15 bytes, $1923–$1931)
; Opcode $DC (sound): leaves the sound pending for
; BattleCD_PlayPendingSfx with X = !BattleCD_SfxArgCentre.
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operand
; Exit:  M=1, X=0; A = the sound; X = !BattleCD_SfxArgCentre; Y
;        unchanged
BattleCD_FxOpSound:
    LDA.b [!BattleCD_FxScriptPtr]
    STA.w !Battle_SfxPendingId
    LDX.w #!BattleCD_SfxArgCentre
    STX.w !Battle_SfxPendingArg
    INC.w !Battle_SfxPending
    RTS

; $CD:1932 — BattleCD_FxOpCopyWin1ToWin2 (5 bytes, $1932–$1936)
; Opcode $DB (one operand byte, which nothing reads): JSL
; BattleFx_CopyWin1ToWin2 (the other window table's first pairs into
; this frame's table's second pairs).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX)
; Exit:  as BattleFx_CopyWin1ToWin2 leaves it: M=1, X=0; A = 0; X =
;        !BattleFx_WinBlockBytes; Y's high byte cleared
BattleCD_FxOpCopyWin1ToWin2:
    JSL BattleFx_CopyWin1ToWin2
    RTS

; $CD:1937 — BattleCD_FxOpWedge (122 bytes, $1937–$19B0)
; Opcode $DA (unused byte, pair n): fills a triangle (BattleCD_FillTriangle,
; object 0, DP $20 = 0) from the point P = !Battle_ActCalcResult entry 2n
; to the two points Q +/- w at right angles to !Battle_FxAngle around Q
; = entry 2n+1, w = variable $0E (signed; the offsets are
; BattleCD_CosMul / BattleCD_SinMul of angle - $40 and angle + $40).
; The angle comes first from entries 2 and 3 (BattleCD_ClampCalcAngle,
; X = 4, which also clamps entries 0 and 1 to the screen). The first
; operand is put in X (8-bit) and not read again here (whether
; BattleCD_FillTriangle reads X is not traced).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operands
;        (BattleCD_ClampCalcAngle runs BattleCE_UnkE7CF, assumed to
;        return M=1, X=0)
; Exit:  M and X as BattleCD_FillTriangle leaves them (not traced; X=0
;        when it is called); Y = DP $40 + 1 (two operand bytes); DP
;        $12-$17, $23-$26, $45-$4C written
BattleCD_FxOpWedge:
    LDX.w #4
    JSR BattleCD_ClampCalcAngle
    LDA.w !Battle_ActVar0E
    TAY
    LDA.w !Battle_FxAngle
    SEC
    SBC.b #!Battle_AngleQuarter
    STA.b !BattleCD_Tmp45
    CLC
    ADC.b #!Battle_AngleHalfTurn
    STA.b !BattleCD_Tmp47
    SEP #$10
    LDA.b !BattleCD_Tmp45
    JSR BattleCD_CosMul
    STA.b !BattleCD_Tmp49
    LDA.b !BattleCD_Tmp45
    JSR BattleCD_SinMul
    STA.b !BattleCD_Tmp4B
    LDA.b !BattleCD_Tmp47
    JSR BattleCD_CosMul
    STA.b !BattleCD_Tmp45
    LDA.b !BattleCD_Tmp47
    JSR BattleCD_SinMul
    STA.b !BattleCD_Tmp47
    LDY.b #1
    LDA.b [!BattleCD_FxScriptPtr],Y
    ASL A
    ASL A
    TAY
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.w !Battle_ActCalcResult+2,Y
    CLC
    ADC.b !BattleCD_Tmp49
    STA.b !BattleCD_TriX0
    LDA.w !Battle_ActCalcResult+3,Y
    CLC
    ADC.b !BattleCD_Tmp4B
    STA.b !BattleCD_TriY0
    LDA.w !Battle_ActCalcResult+2,Y
    CLC
    ADC.b !BattleCD_Tmp45
    STA.b !BattleCD_TriX1
    LDA.w !Battle_ActCalcResult+3,Y
    CLC
    ADC.b !BattleCD_Tmp47
    STA.b !BattleCD_TriY1
    LDA.w !Battle_ActCalcResult,Y
    STA.b !BattleCD_TriX2
    LDA.w !Battle_ActCalcResult+1,Y
    STA.b !BattleCD_TriY2
    REP #$10
    STZ.w !BattleFx_QuadSlot
    STZ.w !BattleCD_TriUnk20
    JSR BattleCD_FillTriangle
    LDY.b !BattleCD_FxScriptPtr
    INY
    STY.b !BattleCD_FxScriptPtr
    RTS

; $CD:19B1 — BattleCD_FxOpBeamFromPair (17 bytes, $19B1–$19C1)
; Opcode $D9 (object, pair n): as opcode $AC (BattleCD_FxOpBeam), but
; the angle is taken from the points of pair n itself: entries 2n and
; 2n+1 of !Battle_ActCalcResult clamped to the screen
; (BattleCD_ClampCalcPair) and their angle (BattleCD_CalcAngle), then
; BattleCD_FxOpBeamQuad (the rest of BattleCD_FxOpBeam, tail jump).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operands
; Exit:  as BattleCD_FxOpBeam
BattleCD_FxOpBeamFromPair:
    LDY.w #1
    LDA.b [!BattleCD_FxScriptPtr],Y
    ASL A
    ASL A
    TAX
    JSR BattleCD_ClampCalcPair
    JSR BattleCD_CalcAngle
    JMP BattleCD_FxOpBeamQuad

; $CD:19C2 — BattleCD_FxOpAddVar (35 bytes, $19C2–$19E4)
; Opcode $D8 (n, value): variable n (!Battle_ActVars) + value; with n's
; bit 7 set, variable n AND $7F = 0 instead (the value is skipped).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operands
; Exit:  M=1, X=0; A = the variable's new value (0 for a clear); X = DP
;        $40 + 1 (two operand bytes, stepped through X); Y = 1 on the add
;        path, else unchanged; DP $45 = the value on the add path
BattleCD_FxOpAddVar:
    LDA.b [!BattleCD_FxScriptPtr]
    BMI .clear
    TAX
    LDY.w #1
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.b !BattleCD_Tmp45
    LDA.w !Battle_ActVars,X
    CLC
    ADC.b !BattleCD_Tmp45
    STA.w !Battle_ActVars,X
    BRA .next
.clear:
    AND.b #!BattleCD_FxVarMask
    TAX
    STZ.w !Battle_ActVars,X
.next:
    LDX.b !BattleCD_FxScriptPtr
    INX
    STX.b !BattleCD_FxScriptPtr
    RTS

; $CD:19E5 — BattleCD_FxOpDrift (108 bytes, $19E5–$1A50)
; Opcode $D7 (b), on the channel's !Battle_FxChanWork bytes:
;   - b bit 7 set: six random values 0-31 (BattleCD_RandByte, each
;     seeded with the one before, the first with b) into work bytes 0-5;
;   - else, with X = the channel + (b AND $0B): work byte X+0 is added
;     to the channel's !BattleFx_BounceOut and work byte X+3 to its
;     !Battle_FxScrollAddX (b bit 6 set), or both are subtracted (bit 6
;     clear), through the opcode-$82 helpers BattleCD_FxAddScrollY /
;     BattleCD_FxAddScrollX / BattleCD_FxSubScrollY /
;     BattleCD_FxSubScrollX (the last one a tail jump). Quirk: the
;     helpers add the word at DP $45, but only its low byte is set here
;     (DP $46 is left as it was).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAXs); C=1 (from
;        BattleCD_RunFxOp's ASL: the first random draw's carry); DP $40
;        at the operand, DP $43 = the channel
; Exit:  random path: M=1, X=0; A = the last value; X = the channel; Y
;        unchanged. Else as the helpers leave it (not matched: not
;        traced); DP $45 written
BattleCD_FxOpDrift:
    LDA.b [!BattleCD_FxScriptPtr]
    BMI .random
    AND.b #!BattleCD_FxDriftPick
    CLC
    ADC.b !BattleFx_RecOfs
    TAX
    LDA.w !Battle_FxChanWork,X
    STA.b !BattleCD_Tmp45
    LDA.b [!BattleCD_FxScriptPtr]
    AND.b #!BattleCD_FxDriftAdd
    BEQ .subtract
    PHX
    JSR BattleCD_FxAddScrollY
    PLX
    LDA.w !Battle_FxChanWork+3,X
    STA.b !BattleCD_Tmp45
    JMP BattleCD_FxAddScrollX
.subtract:
    PHX
    JSR BattleCD_FxSubScrollY
    PLX
    LDA.w !Battle_FxChanWork+3,X
    STA.b !BattleCD_Tmp45
    JMP BattleCD_FxSubScrollX
.random:
    JSR BattleCD_RandByte
    LDX.b !BattleFx_RecOfs
    AND.b #!BattleCD_FxDriftMask
    STA.w !Battle_FxChanWork,X
    JSR BattleCD_RandByte
    LDX.b !BattleFx_RecOfs
    AND.b #!BattleCD_FxDriftMask
    STA.w !Battle_FxChanWork+1,X
    JSR BattleCD_RandByte
    LDX.b !BattleFx_RecOfs
    AND.b #!BattleCD_FxDriftMask
    STA.w !Battle_FxChanWork+2,X
    JSR BattleCD_RandByte
    LDX.b !BattleFx_RecOfs
    AND.b #!BattleCD_FxDriftMask
    STA.w !Battle_FxChanWork+3,X
    JSR BattleCD_RandByte
    LDX.b !BattleFx_RecOfs
    AND.b #!BattleCD_FxDriftMask
    STA.w !Battle_FxChanWork+4,X
    JSR BattleCD_RandByte
    LDX.b !BattleFx_RecOfs
    AND.b #!BattleCD_FxDriftMask
    STA.w !Battle_FxChanWork+5,X
    RTS

; $CD:1A51 — BattleCD_FxBranchBack2 (21 bytes, $1A51–$1A65)
; The taken branch of the two-operand tests (opcodes $D6 and $D5):
; branches back by the second operand n (DP $40 - n with DP $40 at the
; first operand; see the banner).
; Callers note: the JMPs from BattleCD_FxOpWaitValueIsVar0E and
;   BattleCD_FxOpWaitValueZero are its only callers.
; Callers (2 JMP sites): BattleCD_FxOpWaitValueIsVar0E ($CD:1A71) and BattleCD_FxOpWaitValueZero
;   ($CD:1A82).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        first operand
; Exit:  M=1, X=0; A = 0 (B = 0); X = n; Y = 1; DP $40 - n; DP $45 = n
BattleCD_FxBranchBack2:
    LDY.w #1
    LDA.b [!BattleCD_FxScriptPtr],Y
    TAX
    STX.b !BattleCD_Tmp45
    REP #$20
    LDA.b !BattleCD_FxScriptPtr
    SEC
    SBC.b !BattleCD_Tmp45
    STA.b !BattleCD_FxScriptPtr
    TDC
    SEP #$20
    RTS

; $CD:1A66 — BattleCD_FxOpWaitValueIsVar0E (20 bytes, $1A66–$1A79)
; Opcode $D6 (index, n): while !Battle_FxValues entry index differs
; from variable $0E, branches back n (BattleCD_FxBranchBack2); else
; skips both operands.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operands
; Exit:  branch: as BattleCD_FxBranchBack2. Else M=1, X=0; A = the value;
;        X = the index; Y = DP $40 + 1 (two operand bytes)
BattleCD_FxOpWaitValueIsVar0E:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.w !Battle_FxValues,X
    CMP.w !Battle_ActVar0E
    BEQ .next
    JMP BattleCD_FxBranchBack2
.next:
    LDY.b !BattleCD_FxScriptPtr
    INY
    STY.b !BattleCD_FxScriptPtr
    RTS

; $CD:1A7A — BattleCD_FxOpWaitValueZero (17 bytes, $1A7A–$1A8A)
; Opcode $D5 (index, n): while !Battle_FxValues entry index is not 0,
; branches back n (BattleCD_FxBranchBack2); else skips both operands.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operands
; Exit:  branch: as BattleCD_FxBranchBack2. Else M=1, X=0; A = 0; X = the
;        index; Y = DP $40 + 1 (two operand bytes)
BattleCD_FxOpWaitValueZero:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.w !Battle_FxValues,X
    BEQ .next
    JMP BattleCD_FxBranchBack2
.next:
    LDY.b !BattleCD_FxScriptPtr
    INY
    STY.b !BattleCD_FxScriptPtr
    RTS

; $CD:1A8B — BattleCD_FxOpValueSubVar09 (17 bytes, $1A8B–$1A9B)
; Opcode $D4 (index): !Battle_FxValues entry index - variable $09, not
; below 0.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  M=1, X=0; A = the new value; X = the index; Y unchanged
BattleCD_FxOpValueSubVar09:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.w !Battle_FxValues,X
    SEC
    SBC.w !Battle_ActVar09
    BCS .store
    TDC
.store:
    STA.w !Battle_FxValues,X
    RTS

; $CD:1A9C — BattleCD_FxOpValueAddVar0C (22 bytes, $1A9C–$1AB1)
; Opcode $D3 (index): !Battle_FxValues entry index + variable $0C, at
; most variable $0E (the 8-bit sum is compared: a sum past $FF wraps
; first).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  M=1, X=0; A = the new value; X = the index; Y unchanged
BattleCD_FxOpValueAddVar0C:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.w !Battle_FxValues,X
    CLC
    ADC.w !Battle_ActVar0C
    CMP.w !Battle_ActVar0E
    BCC .store
    LDA.w !Battle_ActVar0E
.store:
    STA.w !Battle_FxValues,X
    RTS

; $CD:1AB2 — BattleCD_FxOpColoursFromVar0A (12 bytes, $1AB2–$1ABD)
; Opcode $D2 (one operand byte, not read): both colour sets
; (!Battle_FxScriptIds+2/+3) = variable $0A, then the colour copy of
; BattleCD_LoadLayerFx (BattleCD_LoadLayerFx_colours, tail jump):
; colours 25-27 and 29-31 of both palette buffers from
; !BattleRom_FxColours.
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  as BattleCD_LoadLayerFx_colours (M=1, X=0; A, X, Y clobbered)
BattleCD_FxOpColoursFromVar0A:
    LDA.w !Battle_ActVar0A
    STA.w !Battle_FxScriptIds+2
    STA.w !Battle_FxScriptIds+3
    JMP BattleCD_LoadLayerFx_colours

; $CD:1ABE — BattleCD_FxOpSwitchHigh (13 bytes, $1ABE–$1ACA)
; Opcode $D1 (n, then a list of script addresses): jumps to the address
; in word (variable n's high nibble) of the list after the operand
; (DP $40 = that word - 1; see the banner). BattleCD_FxOpSwitchLow ($1ACB,
; opcode $D0) is the same with the low nibble.
; Sub-entry: BattleCD_FxOpSwitchLow.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX and INC); DP $40
;        at the operand
; Exit:  M=1, X=0; A = 0 (B = 0); X = n; Y = nibble * 2 + 1; DP $40 =
;        the target - 1
BattleCD_FxOpSwitchHigh:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.w !Battle_ActVars,X
    AND.b #!BattleFx_HighNibble
    LSR A
    LSR A
    LSR A
    BRA BattleCD_FxOpSwitchLow_jump
BattleCD_FxOpSwitchLow:                 ; header: see BattleCD_FxOpSwitchHigh
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.w !Battle_ActVars,X
    AND.b #!BattleFx_LowNibble
    ASL A
.jump:
    REP #$20
    INC A
    TAY
    LDA.b [!BattleCD_FxScriptPtr],Y
    DEC A
    STA.b !BattleCD_FxScriptPtr
    TDC
    SEP #$20
    RTS

; $CD:1AE1 — BattleCD_FxOpMirrorWin1ToWin2 (5 bytes, $1AE1–$1AE5)
; Opcode $CF (offset): JSL BattleFx_MirrorWin1ToWin2, which reads the
; operand through DP $40: as opcode $DB, mirrored left to right, for 28
; lines of each 28-line block from line offset the operand.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  as BattleFx_MirrorWin1ToWin2 leaves it: M=1, X=0; A = 0; X = the
;        end offset; Y's high byte cleared; DP $45/$46 written
BattleCD_FxOpMirrorWin1ToWin2:
    JSL BattleFx_MirrorWin1ToWin2
    RTS

; $CD:1AE6 — BattleCD_FxOpStepBounce (5 bytes, $1AE6–$1AEA)
; Opcode $CE (one operand byte, which nothing reads): JSL
; BattleFx_StepBounce, one step of the channel's bounce (set up by
; opcode $CD): !BattleFx_BounceOut moves.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $43 = the
;        channel
; Exit:  as BattleFx_StepBounce leaves it: M=1, X=0; A = 0; X = the
;        channel; Y unchanged
BattleCD_FxOpStepBounce:
    JSL BattleFx_StepBounce
    RTS

; $CD:1AEB — BattleCD_FxOpSetupBounce (52 bytes, $1AEB–$1B1E)
; Opcode $CD (d): sets up the channel's bounce for BattleFx_StepBounce
; (opcode $CE): !BattleFx_BounceDir = 0 (rising), !BattleFx_BounceBase
; = the channel's !BattleFx_BounceOut, !BattleFx_BounceSpeed = $FFFF,
; the 32-bit !BattleFx_BouncePos = $0000FFFF, !BattleFx_BounceAccel =
; $FFFF / d (the CPU's divider, read back after the stores between).
; Entry: M=1, X=0, DP=0, DB=$7E (the divider is accessed long); DP $40
;        at the operand, DP $43 = the channel
; Exit:  M=1, X=0; A = 0 (B = 0); X = the channel; Y unchanged
BattleCD_FxOpSetupBounce:
    LDA.b #!BattleCD_FxDivMax
    STA.l WRDIVL
    STA.l WRDIVH
    LDA.b [!BattleCD_FxScriptPtr]
    STA.l WRDIVB
    LDX.b !BattleFx_RecOfs
    REP #$20
    STZ.w !BattleFx_BounceDir,X
    LDA.w #!Battle_Invert16
    STA.w !BattleFx_BounceSpeed,X
    STA.w !BattleFx_BouncePos,X
    STZ.w !BattleFx_BouncePos+2,X
    LDA.l RDDIVL
    STA.w !BattleFx_BounceAccel,X
    LDA.w !BattleFx_BounceOut,X
    STA.w !BattleFx_BounceBase,X
    TDC
    SEP #$20
    RTS

; $CD:1B1F — BattleCD_ClampCalcAngle (35 bytes, $1B1F–$1B41)
; Clamps the points of !Battle_ActCalcResult entries 0 and 1 to the
; screen (BattleCD_ClampCalcPair), then falls into BattleCD_CalcAngle
; ($1B22): DP $23-$26 = the two points at !Battle_ActCalcResult+X (x,
; y, x, y), JSL BattleCE_UnkE7CF (not matched), !Battle_FxAngle = the
; DP $45 it leaves (the angle from the first point to the second,
; probably).
; Sub-entry: BattleCD_CalcAngle.
; Callers note: also BattleCD_FxOpTable entry $CC. Run as that opcode X
;   = $98 (the doubled opcode), so the points come from
;   !Battle_ActCalcResult+$98 ($5E38), past the results; the operand
;   byte is skipped (whether a script uses the opcode is not traced).
; Callers (2 JSR sites): BattleCD_FxOpWedge ($CD:193A) and BattleCD_FxOpBeam ($CD:2463).
; Callers of BattleCD_CalcAngle (2 JSR sites): BattleCD_FxOpBeamFromPair ($CD:19BC) and unmatched
;   ($CD:BDE0).
; Entry: M=1, X=0, DP=0, DB=$7E; X = the first point's offset in
;        !Battle_ActCalcResult (2 per entry)
; Exit:  M and X as BattleCE_UnkE7CF leaves them (assumed M=1, X=0); X
;        as on entry (PHX/PLX, at 16 bits with that X=0); A =
;        !Battle_FxAngle; Y as BattleCE_UnkE7CF leaves it
BattleCD_ClampCalcAngle:
    JSR BattleCD_ClampCalcPair01
BattleCD_CalcAngle:                     ; header: see BattleCD_ClampCalcAngle
    PHX
    LDA.w !Battle_ActCalcResult,X
    STA.b !BattleCD_MathA
    LDA.w !Battle_ActCalcResult+1,X
    STA.b !BattleCD_MathA+1
    LDA.w !Battle_ActCalcResult+2,X
    STA.b !BattleCD_MathB
    LDA.w !Battle_ActCalcResult+3,X
    STA.b !BattleCD_MathB+1
    JSL BattleCE_UnkE7CF
    LDA.b !BattleCD_Tmp45
    STA.w !Battle_FxAngle
    PLX
    RTS

; $CD:1B42 — BattleCD_ClampX (14 bytes, $1B42–$1B4F)
; A clamped to !BattleCD_ScreenXMin-!BattleCD_ScreenXMax (8-$F8).
; Callers (2 JSR sites): BattleCD_ClampCalcPair01 ($CD:243D, $CD:244F).
; Entry: M=1, X any, DP any, DB any; A = the x
; Exit:  M=1; A clamped; X, Y unchanged
BattleCD_ClampX:
    CMP.b #!BattleCD_ScreenXMin
    BCS .max
    LDA.b #!BattleCD_ScreenXMin
    RTS
.max:
    CMP.b #!BattleCD_ScreenXMax
    BCC .done
    LDA.b #!BattleCD_ScreenXMax
.done:
    RTS

; $CD:1B50 — BattleCD_ClampY (14 bytes, $1B50–$1B5D)
; A clamped to !BattleCD_ScreenYMin-!BattleCD_ScreenYMax (8-$D4).
; Callers (2 JSR sites): BattleCD_ClampCalcPair01 ($CD:2446, $CD:2458).
; Entry: M=1, X any, DP any, DB any; A = the y
; Exit:  M=1; A clamped; X, Y unchanged
BattleCD_ClampY:
    CMP.b #!BattleCD_ScreenYMin
    BCS .max
    LDA.b #!BattleCD_ScreenYMin
    RTS
.max:
    CMP.b #!BattleCD_ScreenYMax
    BCC .done
    LDA.b #!BattleCD_ScreenYMax
.done:
    RTS

; $CD:1B5E — BattleCD_FxOpJumpIf99D2Is1 (15 bytes, $1B5E–$1B6C)
; Opcode $CB (address word): with !Battle_Unk99D2 AND $7F = 1, jumps to
; the address (BattleCD_FxOpJump); else skips it.
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operands
; Exit:  jump: as BattleCD_FxOpJump. Else M=1, X=0; A = the masked byte;
;        X unchanged; Y = DP $40 + 1
BattleCD_FxOpJumpIf99D2Is1:
    LDA.w !Battle_Unk99D2
    AND.b #!BattleCD_99D2Mask
    CMP.b #1
    BEQ BattleCD_FxOpJump
    LDY.b !BattleCD_FxScriptPtr
    INY
    STY.b !BattleCD_FxScriptPtr
    RTS

; $CD:1B6D — BattleCD_FxOpJump (11 bytes, $1B6D–$1B77)
; Opcode $CA (address word): jumps to the script address (in the
; script's bank; DP $40 = the address - 1, see the banner).
; Callers note: also the BEQ in BattleCD_FxOpJumpIf99D2Is1.
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operands
; Exit:  M=1, X=0; A = 0 (B = 0); X, Y unchanged
BattleCD_FxOpJump:
    REP #$20
    LDA.b [!BattleCD_FxScriptPtr]
    DEC A
    STA.b !BattleCD_FxScriptPtr
    TDC
    SEP #$20
    RTS

; $CD:1B78 — BattleCD_FxOpSwapPalettes (34 bytes, $1B78–$1B99)
; Opcode $C9 (no operand): !Battle_UnkA101 + 1, and bit 3 of the eleven
; battlers' !Battler_Palette and of !BattleMenu_CursorPalette flipped
; (palette number +/- 8).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 past the opcode
; Exit:  M=1, X=0; A = the cursor palette; X = !Battle_NumSlots; Y
;        unchanged; DP $40 - 1 (no operand)
BattleCD_FxOpSwapPalettes:
    INC.w !Battle_UnkA101
    TDC
    TAX
.slot:
    LDA.w !Battler_Palette,X
    EOR.b #!BattleCD_PaletteFlip
    STA.w !Battler_Palette,X
    INX
    CPX.w #!Battle_NumSlots
    BNE .slot
    LDA.w !BattleMenu_CursorPalette
    EOR.b #!BattleCD_PaletteFlip
    STA.w !BattleMenu_CursorPalette
    REP #$20
    DEC.b !BattleCD_FxScriptPtr
    SEP #$20
    RTS

; $CD:1B9A — BattleCD_FxOpSwapObjPalettes (5 bytes, $1B9A–$1B9E)
; Opcode $E1 (no operand: BattleFx_SwapObjPalettes moves DP $40 back
; by one): JSL BattleFx_SwapObjPalettes, which swaps OBJ palette rows
; 1-3 with rows 5-7 (live and saved).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX)
; Exit:  as BattleFx_SwapObjPalettes leaves it: M=1, X=0; A = 0; X =
;        !Battle_RowBytes; Y = the last colour moved; DP $40 one less
BattleCD_FxOpSwapObjPalettes:
    JSL BattleFx_SwapObjPalettes
    RTS

; $CD:1B9F — BattleCD_FxOpScrollYToEnemy (12 bytes, $1B9F–$1BAA)
; Opcode $C8 (one operand byte, not read): the channel's
; !BattleFx_BounceOut + (!BattleCD_FxEnemyLine - slot 3's
; !Battler_ScreenY) (DP $45, 16-bit), through BattleCD_FxAddScrollY
; (tail jump). Slot 3 is the first enemy's.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $43 = the
;        channel
; Exit:  as BattleCD_FxAddScrollY leaves it (not matched: not traced)
BattleCD_FxOpScrollYToEnemy:
    LDA.b #!BattleCD_FxEnemyLine
    SEC
    SBC.w !Battler_ScreenY+3
    TAX
    STX.b !BattleCD_Tmp45
    JMP BattleCD_FxAddScrollY

; $CD:1BAB — BattleCD_FxOpObjYToEnemy (21 bytes, $1BAB–$1BBF)
; Opcode $C7 (object): the object's !Battle_FxObjCentreY -
; (!BattleCD_FxEnemyLine - slot 3's !Battler_ScreenY).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  M=1, X=0; A = the new centre y; X = the object; Y unchanged; DP
;        $45 written
BattleCD_FxOpObjYToEnemy:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.b #!BattleCD_FxEnemyLine
    SEC
    SBC.w !Battler_ScreenY+3
    STA.b !BattleCD_Tmp45
    LDA.w !Battle_FxObjCentreY,X
    SEC
    SBC.b !BattleCD_Tmp45
    STA.w !Battle_FxObjCentreY,X
    RTS

; $CD:1BC0 — BattleCD_SinMul45 (14 bytes, $1BC0–$1BCD)
; A = DP $45 * sin(A) / 256 (BattleCD_SinMul with Y = DP $45) for
; 16-bit-index callers: X and Y are saved at 16 bits around the SEP
; #$10.
; Callers (3 JSR sites): BattleCD_FxOpWobble ($CD:1BF9, $CD:1C0A, $CD:1C1B).
; Entry: M=1, X=0, DP=0, DB any; A = the angle, DP $45 = the factor
;        (signed byte)
; Exit:  M=1, X=0; A = the product; X, Y unchanged (pulled at 16 bits)
BattleCD_SinMul45:
    PHX
    PHY
    SEP #$10
    LDY.b !BattleCD_Tmp45
    JSR BattleCD_SinMul
    REP #$10
    PLY
    PLX
    RTS

; $CD:1BCE — BattleCD_FxOpWobble (100 bytes, $1BCE–$1C31)
; Opcode $C6 (object, three phase steps, three angle bases): the
; object's phases !Battle_FxObjPhaseA/B/C + the steps; then its angles
; !Battle_FxObjAngleX = base 1 + $20 * sin(phase A) / 256,
; !Battle_FxObjAngleY = base 2 + $20 * sin(phase B) / 256,
; !Battle_FxObjAngleZ = base 3 + $24 * sin(phase C) / 256
; (BattleCD_SinMul45).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operands
; Exit:  M=1, X=0; A = 0 (B = 0); X = the object; Y = 6; DP $40 + 6
;        (seven operand bytes); DP $45 = !BattleCD_FxWobbleAmpZ
BattleCD_FxOpWobble:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDY.w #1
    LDA.w !Battle_FxObjPhaseA,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjPhaseA,X
    INY
    LDA.w !Battle_FxObjPhaseB,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjPhaseB,X
    INY
    LDA.w !Battle_FxObjPhaseC,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjPhaseC,X
    INY
    LDA.b #!BattleCD_FxWobbleAmpXY
    STA.b !BattleCD_Tmp45
    LDA.w !Battle_FxObjPhaseA,X
    JSR BattleCD_SinMul45
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjAngleX,X
    INY
    LDA.b #!BattleCD_FxWobbleAmpXY
    STA.b !BattleCD_Tmp45
    LDA.w !Battle_FxObjPhaseB,X
    JSR BattleCD_SinMul45
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjAngleY,X
    INY
    LDA.b #!BattleCD_FxWobbleAmpZ
    STA.b !BattleCD_Tmp45
    LDA.w !Battle_FxObjPhaseC,X
    JSR BattleCD_SinMul45
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjAngleZ,X
    REP #$20
    LDA.b !BattleCD_FxScriptPtr
    CLC
    ADC.w #6
    STA.b !BattleCD_FxScriptPtr
    TDC
    SEP #$20
    RTS

; $CD:1C32 — BattleCD_FxOpScrollToCalc (41 bytes, $1C32–$1C5A)
; Opcode $AA (n): layer 3 scrolled so that the point of
; !Battle_ActCalcResult entry n is its origin: the channel's
; !BattleFx_ShakeX/Y = -x, -y (16-bit). Entries 0 and 1 are clamped to
; the screen first (BattleCD_ClampCalcPair01). BattleCD_ScrollToCalc
; ($1C34) is the same with A = n.
; Sub-entry: BattleCD_ScrollToCalc.
; Callers of BattleCD_ScrollToCalc (1 JSR site): BattleCD_FxOpCircleAtCalc ($CD:1C64).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAY); DP $40 at the
;        operand (BattleCD_ScrollToCalc: A = n), DP $43 = the channel
; Exit:  M=1, X=0; A = 0 (B = 0); X = the channel; Y = n * 2
BattleCD_FxOpScrollToCalc:
    LDA.b [!BattleCD_FxScriptPtr]
BattleCD_ScrollToCalc:                  ; header: see BattleCD_FxOpScrollToCalc
    ASL A
    TAY
    JSR BattleCD_ClampCalcPair01
    LDX.b !BattleFx_RecOfs
    REP #$20
    LDA.w !Battle_ActCalcResult,Y
    AND.w #!Battle_LowByteMask
    EOR.w #!Battle_Invert16
    INC A
    STA.w !BattleFx_ShakeX,X
    LDA.w !Battle_ActCalcResult+1,Y
    AND.w #!Battle_LowByteMask
    EOR.w #!Battle_Invert16
    INC A
    STA.w !BattleFx_ShakeY,X
    TDC
    SEP #$20
    RTS

; $CD:1C5B — BattleCD_FxCircleRadii (8 bytes, $1C5B–$1C62)
; Radius sets of BattleCD_FxCircleFromTable, 4 bytes each: the first
; circle's x and y radius, the second's x and y radius.
BattleCD_FxCircleRadii:
    db $20,$20,$4B,$20                  ; 0
    db $08,$08,$10,$08                  ; 1

; $CD:1C63 — BattleCD_FxOpCircleAtCalc (24 bytes, $1C63–$1C7A)
; Opcode $C5 (radius set): layer 3 circles around the point of
; !Battle_ActCalcResult entry 0: the point (BattleCD_ScrollToCalc, A =
; 0) as the centre (DP $4D/$4E, the scroll negated back), then
; BattleCD_FxCircleFromTable with the operand's radius set.
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operand, DP $43 = the
;        channel
; Exit:  as BattleCD_FxCircleFromTable
BattleCD_FxOpCircleAtCalc:
    TDC
    JSR BattleCD_ScrollToCalc
    LDX.b !BattleFx_RecOfs
    LDA.w !BattleFx_ShakeX,X
    EOR.b #!Battle_Invert8
    INC A
    STA.b !BattleCD_FxCentreX
    LDA.w !BattleFx_ShakeY,X
    EOR.b #!Battle_Invert8
    INC A
    STA.b !BattleCD_FxCentreY
    BRA BattleCD_FxCircleFromTable

; $CD:1C7B — BattleCD_FxOpCircleGrow (68 bytes, $1C7B–$1CBE)
; Opcode $C4 (k): layer 3 circles around !BattleCD_FxCircleX/Y. Every
; fourth frame (!Battle_FrameCount AND 3 = 0) !Battle_UnkCD28 + 1; the
; radii are !Battle_UnkCD28 (the second circle's x radius twice that).
; k = 0 uses radius set 0 instead (BattleCD_FxCircleFromTable: the
; growing radii are then overwritten); else BattleCD_FxCircleStep. On
; odd frames the low bytes of the channel's !BattleFx_ShakeX/Y are
; negated afterwards (8-bit: the high bytes stay).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operand, DP $43 = the
;        channel
; Exit:  M=1, X=0; A = the frame count AND 1, or the negated x; X = the
;        channel; Y = DP $4C (high byte 0); DP $45-$4E written
BattleCD_FxOpCircleGrow:
    LDA.b #!BattleCD_FxCircleX
    STA.b !BattleCD_FxCentreX
    LDA.b #!BattleCD_FxCircleY
    STA.b !BattleCD_FxCentreY
    LDA.b !Battle_FrameCount
    AND.b #3
    BNE .radii
    INC.w !Battle_UnkCD28
.radii:
    LDA.w !Battle_UnkCD28
    STA.b !BattleCD_FxRadius1X
    STA.b !BattleCD_FxRadius1Y
    STA.b !BattleCD_FxRadius2Y
    ASL A
    STA.b !BattleCD_FxRadius2X
    LDA.b [!BattleCD_FxScriptPtr]
    BNE .grow
    JSR BattleCD_FxCircleFromTable
    BRA .flip
.grow:
    JSR BattleCD_FxCircleStep
.flip:
    LDA.b !Battle_FrameCount
    AND.b #1
    BEQ .done
    LDX.b !BattleFx_RecOfs
    LDA.w !BattleFx_ShakeY,X
    EOR.b #!Battle_Invert8
    INC A
    STA.w !BattleFx_ShakeY,X
    LDA.w !BattleFx_ShakeX,X
    EOR.b #!Battle_Invert8
    INC A
    STA.w !BattleFx_ShakeX,X
.done:
    RTS

; $CD:1CBF — BattleCD_FxCircleFromTable (142 bytes, $1CBF–$1D4C)
; DP $49-$4C = BattleCD_FxCircleRadii set k (the script's operand),
; then falls into BattleCD_FxCircleStep ($1CD5): the channel's angles
; (!Battle_FxChanWork bytes 5, 6, 7) + 2, + 5, + 6; the point x = DP
; $4D + cos(angle 5) * DP $49 / 256 + cos(angle 7) * DP $4B / 256, y =
; DP $4E + sin(angle 5) * DP $4A / 256 + sin(angle 6) * DP $4C / 256
; (BattleCD_CosMul / BattleCD_SinMul, 8-bit sums); the channel's
; !BattleFx_ShakeX/Y = -x, -y (16-bit): layer 3's origin goes round
; the centre.
; Sub-entry: BattleCD_FxCircleStep.
; Callers (1 JSR site): BattleCD_FxOpCircleGrow ($CD:1C9C).
; Callers of BattleCD_FxCircleStep (1 JSR site): BattleCD_FxOpCircleGrow ($CD:1CA1).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX and negations);
;        DP $40 at the operand (BattleCD_FxCircleStep: DP $49-$4C the
;        radii), DP $43 = the channel, DP $4D/$4E the centre
; Exit:  M=1, X=0; A = 0 (B = 0); X = the channel; Y = DP $4C (high
;        byte 0); DP $45-$48 written
BattleCD_FxCircleFromTable:
    LDA.b [!BattleCD_FxScriptPtr]
    ASL A
    ASL A
    TAX
    REP #$20
    LDA.l BattleCD_FxCircleRadii,X
    STA.b !BattleCD_FxRadius1X
    LDA.l BattleCD_FxCircleRadii+2,X
    STA.b !BattleCD_FxRadius2X
    TDC
    SEP #$20
BattleCD_FxCircleStep:                  ; header: see BattleCD_FxCircleFromTable
    LDX.b !BattleFx_RecOfs
    LDA.w !Battle_FxChanWork+7,X
    CLC
    ADC.b #6
    STA.w !Battle_FxChanWork+7,X
    LDA.w !Battle_FxChanWork+6,X
    CLC
    ADC.b #5
    STA.w !Battle_FxChanWork+6,X
    LDA.w !Battle_FxChanWork+5,X
    CLC
    ADC.b #2
    STA.w !Battle_FxChanWork+5,X
    TDC
    TAY
    SEP #$10
    LDX.b !BattleFx_RecOfs
    LDY.b !BattleCD_FxRadius1X
    LDA.w !Battle_FxChanWork+5,X
    JSR BattleCD_CosMul
    STA.b !BattleCD_Tmp45
    LDX.b !BattleFx_RecOfs
    LDY.b !BattleCD_FxRadius1Y
    LDA.w !Battle_FxChanWork+5,X
    JSR BattleCD_SinMul
    STA.b !BattleCD_Tmp47
    LDX.b !BattleFx_RecOfs
    LDY.b !BattleCD_FxRadius2X
    LDA.w !Battle_FxChanWork+7,X
    JSR BattleCD_CosMul
    LDX.b !BattleFx_RecOfs
    CLC
    ADC.b !BattleCD_FxCentreX
    CLC
    ADC.b !BattleCD_Tmp45
    REP #$20
    EOR.w #!Battle_Invert16
    INC A
    STA.w !BattleFx_ShakeX,X
    TDC
    SEP #$20
    LDX.b !BattleFx_RecOfs
    LDY.b !BattleCD_FxRadius2Y
    LDA.w !Battle_FxChanWork+6,X
    JSR BattleCD_SinMul
    LDX.b !BattleFx_RecOfs
    CLC
    ADC.b !BattleCD_FxCentreY
    CLC
    ADC.b !BattleCD_Tmp47
    REP #$20
    EOR.w #!Battle_Invert16
    INC A
    STA.w !BattleFx_ShakeY,X
    TDC
    SEP #$20
    REP #$10
    RTS

; $CD:1D4D — BattleCD_FxOpIncVar0F (9 bytes, $1D4D–$1D55)
; Opcode $C3 (no operand): variable $0F + 1.
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 past the opcode
; Exit:  M=1, X=0; A, X unchanged; Y = DP $40 - 1 (no operand)
BattleCD_FxOpIncVar0F:
    INC.w !Battle_ActVar0F
    LDY.b !BattleCD_FxScriptPtr
    DEY
    STY.b !BattleCD_FxScriptPtr
    RTS

; $CD:1D56 — BattleCD_FxOpObjStepCapped (61 bytes, $1D56–$1D92)
; Opcode $C2 (object, limit, three steps): the object's
; !Battle_FxObjUnkDA/DC/DE each + its step, stored only while the
; 8-bit sum stays below the limit. What reads the three bytes is not
; traced.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operands
; Exit:  M=1, X=0; A = the last sum; X = the object; Y = DP $40 + 4
;        (five operand bytes); DP $45 = the limit
BattleCD_FxOpObjStepCapped:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDY.w #1
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.b !BattleCD_Tmp45
    INY
    LDA.w !Battle_FxObjUnkDA,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    CMP.b !BattleCD_Tmp45
    BCS .second
    STA.w !Battle_FxObjUnkDA,X
.second:
    INY
    LDA.w !Battle_FxObjUnkDC,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    CMP.b !BattleCD_Tmp45
    BCS .third
    STA.w !Battle_FxObjUnkDC,X
.third:
    INY
    LDA.w !Battle_FxObjUnkDE,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    CMP.b !BattleCD_Tmp45
    BCS .next
    STA.w !Battle_FxObjUnkDE,X
.next:
    LDY.b !BattleCD_FxScriptPtr
    INY
    INY
    INY
    INY
    STY.b !BattleCD_FxScriptPtr
    RTS

; $CD:1D93 — BattleCD_FxOpWaitLine (5 bytes, $1D93–$1D97)
; Opcode $C1 (line): busy-waits for that scanline (BattleCD_WaitScanline,
; tail jump).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operand
; Exit:  as BattleCD_WaitScanline (M=1; A = the line reached; X, Y
;        unchanged; DP $45 = the line)
BattleCD_FxOpWaitLine:
    LDA.b [!BattleCD_FxScriptPtr]
    JMP BattleCD_WaitScanline

; $CD:1D98 — BattleCD_FxOpShake (111 bytes, $1D98–$1E06)
; Opcode $C0 (flag, then seven bytes): the screen shake
; (BattleCD_StepShake). Flag bit 7 set: stopped (!Battle_ShakeXOn,
; !Battle_ShakeYOn, !Battle_ShakeLayers = 0; the seven bytes are
; skipped). Else the counters !Battle_ShakeXRandTime/StepTime and the y
; ones = 0, both random periods = 1, then !Battle_ShakeXAmp,
; !Battle_ShakeXTarget, !Battle_ShakeXStepPeriod, !Battle_ShakeYAmp,
; !Battle_ShakeYTarget, !Battle_ShakeYStepPeriod, !Battle_ShakeLayers
; from the seven bytes, and each axis on (non-zero) when its amplitude
; or target is.
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operands
; Exit:  M=1, X=0; A = 0 (B = 0); X unchanged; Y = 7 on the start path,
;        unchanged on the stop path; DP $40 + 7 (eight operand bytes)
BattleCD_FxOpShake:
    LDA.b [!BattleCD_FxScriptPtr]
    BMI .stop
    STZ.w !Battle_ShakeXRandTime
    STZ.w !Battle_ShakeXStepTime
    STZ.w !Battle_ShakeYRandTime
    STZ.w !Battle_ShakeYStepTime
    LDA.b #1
    STA.w !Battle_ShakeXRandPeriod
    STA.w !Battle_ShakeYRandPeriod
    LDY.w #1
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_ShakeXAmp
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_ShakeXTarget
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_ShakeXStepPeriod
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_ShakeYAmp
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_ShakeYTarget
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_ShakeYStepPeriod
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_ShakeLayers
    LDA.w !Battle_ShakeXAmp
    ORA.w !Battle_ShakeXTarget
    STA.w !Battle_ShakeXOn
    LDA.w !Battle_ShakeYAmp
    ORA.w !Battle_ShakeYTarget
    STA.w !Battle_ShakeYOn
    BRA .next
.stop:
    STZ.w !Battle_ShakeXOn
    STZ.w !Battle_ShakeYOn
    STZ.w !Battle_ShakeLayers
.next:
    REP #$20
    LDA.b !BattleCD_FxScriptPtr
    CLC
    ADC.w #7
    STA.b !BattleCD_FxScriptPtr
    TDC
    SEP #$20
    RTS

; $CD:1E07 — BattleCD_FxOpWaitPalAnims (32 bytes, $1E07–$1E26)
; Opcode $BF (n): while any of the palette animation records 8-11 runs
; (FieldAnimB .Unk0 non-zero), branches back n (see the banner).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  M=1, X=0; branch: A = 0 (B = 0), X = n, DP $40 - n; else A =
;        0, X unchanged; Y unchanged
BattleCD_FxOpWaitPalAnims:
    LDA.w FieldAnimB[11].Unk0
    ORA.w FieldAnimB[10].Unk0
    ORA.w FieldAnimB[9].Unk0
    ORA.w FieldAnimB[8].Unk0
    BEQ .done
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    STX.b !BattleCD_Tmp45
    REP #$20
    LDA.b !BattleCD_FxScriptPtr
    SEC
    SBC.b !BattleCD_Tmp45
    STA.b !BattleCD_FxScriptPtr
    TDC
    SEP #$20
.done:
    RTS

; $CD:1E27 — BattleCD_FxOpDrawModel2 (15 bytes, $1E27–$1E35)
; Opcode $BE (object): draws model 2 (DP $4F = $20) for the object with
; its !Battle_FxObjDepth (BattleCD_FxDrawModel, tail jump).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  as BattleCD_FxDrawModel
BattleCD_FxOpDrawModel2:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.b #!BattleCD_FxModel2
    STA.b !BattleCD_FxModelOfs
    LDA.w !Battle_FxObjDepth,X
    STA.b !BattleCD_FxDepth
    JMP BattleCD_FxDrawModel

; $CD:1E36 — BattleCD_FxOpSetObjD1 (15 bytes, $1E36–$1E44)
; Opcode $BD (b): !Battle_FxObjUnkD1 of object (b AND 1) = b >> 4.
; What reads it is not traced.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  M=1, X=0; A = b >> 4; X = the object; Y unchanged
BattleCD_FxOpSetObjD1:
    LDA.b [!BattleCD_FxScriptPtr]
    AND.b #1
    TAX
    LDA.b [!BattleCD_FxScriptPtr]
    LSR A
    LSR A
    LSR A
    LSR A
    STA.w !Battle_FxObjUnkD1,X
    RTS

; $CD:1E45 — BattleCD_FxOpTurnObj (55 bytes, $1E45–$1E7B)
; Opcode $BC (object, four steps): the object's !Battle_FxObjAngleX,
; !Battle_FxObjAngleY, !Battle_FxObjAngleZ and !Battle_FxObjDepth each
; + its step.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operands
; Exit:  M=1, X=0; A = the new depth; X = the object; Y = DP $40 + 4
;        (five operand bytes)
BattleCD_FxOpTurnObj:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDY.w #1
    LDA.w !Battle_FxObjAngleX,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjAngleX,X
    INY
    LDA.w !Battle_FxObjAngleY,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjAngleY,X
    INY
    LDA.w !Battle_FxObjAngleZ,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjAngleZ,X
    INY
    LDA.w !Battle_FxObjDepth,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjDepth,X
    INY                                 ; not used (Y is reloaded)
    LDY.b !BattleCD_FxScriptPtr
    INY
    INY
    INY
    INY
    STY.b !BattleCD_FxScriptPtr
    RTS

; $CD:1E7C — BattleCD_FxOpDrawModel (21 bytes, $1E7C–$1E90)
; Opcode $BB (b): draws model (b AND $0F) (DP $4F = b << 4, 8-bit) for
; object (b AND 1) with its !Battle_FxObjDepth (BattleCD_FxDrawModel,
; tail jump).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  as BattleCD_FxDrawModel
BattleCD_FxOpDrawModel:
    LDA.b [!BattleCD_FxScriptPtr]
    AND.b #1
    TAX
    LDA.b [!BattleCD_FxScriptPtr]
    ASL A
    ASL A
    ASL A
    ASL A
    STA.b !BattleCD_FxModelOfs
    LDA.w !Battle_FxObjDepth,X
    STA.b !BattleCD_FxDepth
    JMP BattleCD_FxDrawModel

; $CD:1E91 — BattleCD_FxOpSpinModel (102 bytes, $1E91–$1EF6)
; Opcode $BA (b): turns object b (the whole byte as the index; the
; scripts presumably pass 0 or 1) a step (!Battle_FxObjAngleY + 1,
; !Battle_FxObjAngleX + 2, !Battle_FxObjAngleZ + 1) and draws model (b
; AND $0F) at depth 0; then BattleCD_FxDrawModel ($1EAA), which the
; other model opcodes JMP to: the model's three vertices
; (BattleCD_FxRotateVertex 0-2), each rotated point plus the object's
; !Battle_FxObjCentreX/Y into its triangle (!Battle_FxTriX0-Y2), then
; the triangle filled (BattleCD_FxOpFillTriangle, tail jump; it reads
; the operand's bit 0 as the object again).
; Sub-entry: BattleCD_FxDrawModel.
; Callers of BattleCD_FxDrawModel (2 JMP sites): BattleCD_FxOpDrawModel2 ($CD:1E33) and
;   BattleCD_FxOpDrawModel ($CD:1E8E).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand (BattleCD_FxDrawModel: X = the object, DP $4F = the
;        model * 16, DP $51 = the depth)
; Exit:  as BattleCD_FxOpFillTriangle
BattleCD_FxOpSpinModel:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.b [!BattleCD_FxScriptPtr]
    ASL A
    ASL A
    ASL A
    ASL A
    STA.b !BattleCD_FxModelOfs
    STZ.b !BattleCD_FxDepth
    INC.w !Battle_FxObjAngleY,X
    INC.w !Battle_FxObjAngleX,X
    INC.w !Battle_FxObjAngleX,X
    INC.w !Battle_FxObjAngleZ,X
BattleCD_FxDrawModel:                   ; header: see BattleCD_FxOpSpinModel
    TDC
    JSR BattleCD_FxRotateVertex
    LDA.w !Battle_FxRotOutX
    CLC
    ADC.w !Battle_FxObjCentreX,X
    STA.w !Battle_FxTriX0,X
    LDA.w !Battle_FxRotOutY
    CLC
    ADC.w !Battle_FxObjCentreY,X
    STA.w !Battle_FxTriY0,X
    LDA.b #1
    JSR BattleCD_FxRotateVertex
    LDA.w !Battle_FxRotOutX
    CLC
    ADC.w !Battle_FxObjCentreX,X
    STA.w !Battle_FxTriX1,X
    LDA.w !Battle_FxRotOutY
    CLC
    ADC.w !Battle_FxObjCentreY,X
    STA.w !Battle_FxTriY1,X
    LDA.b #2
    JSR BattleCD_FxRotateVertex
    LDA.w !Battle_FxRotOutX
    CLC
    ADC.w !Battle_FxObjCentreX,X
    STA.w !Battle_FxTriX2,X
    LDA.w !Battle_FxRotOutY
    CLC
    ADC.w !Battle_FxObjCentreY,X
    STA.w !Battle_FxTriY2,X
    JMP BattleCD_FxOpFillTriangle

; $CD:1EF7 — BattleCD_FxRotateVertex (69 bytes, $1EF7–$1F3B)
; Rotates vertex A (0-2) of a model of BattleFx_FxModels (16 bytes
; per model, DP $4F = its offset; 4 bytes per vertex: x, y, z, unused)
; by object X's angles: !Battle_FxRotInX/Y = the vertex's x and y,
; !Battle_FxRotInZ = z + DP $51 (the depth); DP $49/$4B/$4D = the
; object's !Battle_FxObjAngleX/Y/Z and DP $21 = its !Battle_FxObjScale
; (16-bit stores, high bytes 0); then BattleCD_Rotate3d.
; Callers (3 JSR sites): BattleCD_FxDrawModel ($CD:1EAB, $CD:1EC4, $CD:1EDD).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX/TAY stores); A =
;        the vertex, X = the object, DP $4F = the model's offset, DP $51
;        = the depth
; Exit:  M=1, X=0; X as on entry (pulled at 16 bits); A =
;        !Battle_FxRotOutX; Y = BattleCD_Rotate3d's (high byte 0);
;        !Battle_FxRotOut* written; DP $21-$22, $47, $49-$4E written
BattleCD_FxRotateVertex:
    PHX
    ASL A
    ASL A
    CLC
    ADC.b !BattleCD_FxModelOfs
    TAX
    LDA.l BattleFx_FxModels,X
    TAY
    STY.w !Battle_FxRotInX
    LDA.l BattleFx_FxModels+1,X
    TAY
    STY.w !Battle_FxRotInY
    LDA.l BattleFx_FxModels+2,X
    CLC
    ADC.b !BattleCD_FxDepth
    TAY
    STY.w !Battle_FxRotInZ
    PLX
    PHX
    LDA.w !Battle_FxObjAngleX,X
    TAY
    STY.b !BattleCD_RotAngleX
    LDA.w !Battle_FxObjAngleY,X
    TAY
    STY.b !BattleCD_RotAngleY
    LDA.w !Battle_FxObjAngleZ,X
    TAY
    STY.b !BattleCD_RotAngleZ
    LDA.w !Battle_FxObjScale,X
    TAY
    STY.b !BattleCD_FxScale
    SEP #$10
    JSR BattleCD_Rotate3d
    REP #$10
    PLX
    RTS

; $CD:1F3C — BattleCD_FxOpColours (11 bytes, $1F3C–$1F46)
; Opcode $B9 (set): both colour sets (!Battle_FxScriptIds+2/+3) = the
; operand, then the colour copy of BattleCD_LoadLayerFx
; (BattleCD_LoadLayerFx_colours, tail jump): colours 25-27 and 29-31
; of both palette buffers from !BattleRom_FxColours.
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operand
; Exit:  as BattleCD_LoadLayerFx_colours (M=1, X=0; A, X, Y clobbered)
BattleCD_FxOpColours:
    LDA.b [!BattleCD_FxScriptPtr]
    STA.w !Battle_FxScriptIds+2
    STA.w !Battle_FxScriptIds+3
    JMP BattleCD_LoadLayerFx_colours

; $CD:1F47 — BattleCD_FxOp3924 (6 bytes, $1F47–$1F4C)
; Opcode $B8 (value): BattleCD_Unk3924 (not matched) with A = the value.
; Entry: M=1, X=0, DP=0, DB=$7E (what BattleCD_Unk3924 needs is not
;        traced); DP $40 at the operand
; Exit:  as BattleCD_Unk3924 leaves it (not traced)
BattleCD_FxOp3924:
    LDA.b [!BattleCD_FxScriptPtr]
    JSR BattleCD_Unk3924
    RTS

; $CD:1F4D — BattleCD_FxOpTilePageSlot (6 bytes, $1F4D–$1F52)
; Opcode $B7 (slot): !Battle_TilePageSlot = the slot (which
; BattleCD_TileUploadVram address the script's tilemap pages go to).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operand
; Exit:  M=1, X=0; A = the slot; X, Y unchanged
BattleCD_FxOpTilePageSlot:
    LDA.b [!BattleCD_FxScriptPtr]
    STA.w !Battle_TilePageSlot
    RTS

; $CD:1F53 — BattleCD_FxOpWindowBand (77 bytes, $1F53–$1F9F)
; Opcodes $B5 and $B6 (index): a band of !Battle_FxWinLines around the
; middle line. With v = !Battle_FxValues entry index and c = entry
; index + 2: when v is not 0, the v words from the middle
; (!Battle_FxWinLinesMid) on and the v words before it all get the
; byte pair (c - v, not below 0; c + v, at most $FF): a left and a
; right edge, probably; then !Battle_FxValues+6 = 0 and
; BattleCD_Unk35A5 (not matched). With v = 0 nothing is written.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX and the doubled
;        v); DP $40 at the operand
; Exit:  v = 0: M=1, X=0; A = 0; X = the index; Y unchanged. Else as
;        BattleCD_Unk35A5 leaves it (not traced). DP $45-$49 written
BattleCD_FxOpWindowBand:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.w !Battle_FxValues+2,X
    STA.b !BattleCD_Tmp49
    LDA.w !Battle_FxValues,X
    STA.b !BattleCD_Tmp45
    STA.b !BattleCD_Tmp45+1
    LDA.b !BattleCD_Tmp49
    SEC
    SBC.b !BattleCD_Tmp45
    BCS .low
    TDC
.low:
    STA.b !BattleCD_Tmp45
    LDA.b !BattleCD_Tmp45+1
    CLC
    ADC.b !BattleCD_Tmp49
    BCC .high
    LDA.b #!BattleCD_FxEdgeMax
.high:
    STA.b !BattleCD_Tmp45+1
    LDA.w !Battle_FxValues,X
    BEQ .done
    REP #$20
    ASL A
    STA.b !BattleCD_Tmp47
    TDC
    TAX
    LDY.w #!BattleCD_FxWinLastWord
    LDA.b !BattleCD_Tmp45
.line:
    STA.w !Battle_FxWinLinesMid,X
    STA.w !Battle_FxWinLines,Y
    INX
    INX
    DEY
    DEY
    CPX.b !BattleCD_Tmp47
    BNE .line
    TDC
    SEP #$20
    STZ.w !Battle_FxValues+6
    JSR BattleCD_Unk35A5
.done:
    RTS

; $CD:1FA0 — BattleCD_FxOpCentreAndScroll (40 bytes, $1FA0–$1FC7)
; Opcode $B4 (object): the object's centre from its triangle
; (BattleCD_FxOpTriCentre, same operand), then layer 3 scrolled so that
; the centre is its origin: the channel's !BattleFx_ShakeX/Y =
; -!Battle_FxObjCentreX, -!Battle_FxObjCentreY (16-bit).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0; DP $40 at the operand, DP $43 =
;        the channel
; Exit:  M=1, X=0; A = 0 (B = 0); X = the channel; Y = the object;
;        written as BattleCD_FxOpTriCentre writes
BattleCD_FxOpCentreAndScroll:
    JSR BattleCD_FxOpTriCentre
    LDA.b [!BattleCD_FxScriptPtr]
    TAY
    LDX.b !BattleFx_RecOfs
    REP #$20
    LDA.w !Battle_FxObjCentreX,Y
    AND.w #!Battle_LowByteMask
    EOR.w #!Battle_Invert16
    INC A
    STA.w !BattleFx_ShakeX,X
    LDA.w !Battle_FxObjCentreY,Y
    AND.w #!Battle_LowByteMask
    EOR.w #!Battle_Invert16
    INC A
    STA.w !BattleFx_ShakeY,X
    TDC
    SEP #$20
    RTS

; $CD:1FC8 — BattleCD_FxOpWaveTable (131 bytes, $1FC8–$204A)
; Opcode $B3 (an operand byte, stored to DP $45 and overwritten: not
; used): fills the 106 entries of !Battle_FxWaveTable (8 bytes each: an
; x word and a y word, twice) for this frame. With f =
; !Battle_FrameCount and entry i: x = sin(4f + i) * !BattleCD_FxWaveAmpX
; / 256 (signed, BattleCD_FxWaveStoreX), y = channel 0's
; !BattleFx_ShakeY + !BattleFx_BounceOut + $20 + sin(f + i) *
; !BattleCD_FxWaveAmpY / 256 (BattleCD_FxWaveStoreY). The sines are
; taken on the multiplier from !BattleRom_AbsSine. What reads the
; table is not traced (an HDMA table, probably).
; Entry: M=1, X=0, DP=0, DB=$7E (the multiplier is accessed long); B = 0
;        (the 16-bit TAX/STX of the frame count)
; Exit:  M=1, X=0; A = 0 (B = 0); X = the last y angle; Y =
;        !BattleCD_FxWaveTableEnd; DP $45-$4A written
BattleCD_FxOpWaveTable:
    LDA.b [!BattleCD_FxScriptPtr]
    STA.b !BattleCD_Tmp45
    REP #$20
    LDA.w !BattleFx_ShakeY
    CLC
    ADC.w !BattleFx_BounceOut
    STA.b !BattleCD_Tmp49
    TDC
    SEP #$20
    LDA.b !Battle_FrameCount
    TAX
    STX.b !BattleCD_Tmp45
    ASL A
    ASL A
    TAX
    STX.b !BattleCD_Tmp47
    TDC
    TAY
.entry:
    LDA.b !BattleCD_Tmp47
    BPL .x_positive
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b #!BattleCD_FxWaveAmpX
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    EOR.b #!Battle_Invert8
    INC A
    JSR BattleCD_FxWaveStoreX
    BCC .y_positive
.y_negative:
    LDA.l RDMPYH
    EOR.b #!Battle_Invert8
    INC A
    JSR BattleCD_FxWaveStoreY
    BRA .next
.x_positive:
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b #!BattleCD_FxWaveAmpX
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    JSR BattleCD_FxWaveStoreX
    BCS .y_negative
.y_positive:
    LDA.l RDMPYH
    JSR BattleCD_FxWaveStoreY
.next:
    INC.b !BattleCD_Tmp45
    INC.b !BattleCD_Tmp47
    REP #$20
    TYA
    CLC
    ADC.w #8
    TAY
    TDC
    SEP #$20
    CPY.w #!BattleCD_FxWaveTableEnd
    BNE .entry
    RTS

; $CD:204B — BattleCD_FxWaveStoreX (102 bytes, $204B–$20B0)
; BattleCD_FxOpWaveTable's x: stores A (signed, widened to 16 bits) as
; entry Y's two x words, then starts |sin(DP $45)| *
; !BattleCD_FxWaveAmpY on the multiplier for the y and returns C=1 when
; that sine is negative (DP $45 = $80-$FF).
; Callers (2 JSR sites): BattleCD_FxOpWaveTable ($CD:2003, $CD:202A).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0; A = the x, Y = the entry's
;        offset, DP $45 = the y angle
; Exit:  M=1, X=0; C = the y sine's sign; A = !BattleCD_FxWaveAmpY; X =
;        DP $45; Y unchanged
BattleCD_FxWaveStoreX:
    BPL .positive
    REP #$20
    ORA.w #!BattleFx_SignExtend
    STA.w !Battle_FxWaveTable,Y
    STA.w !Battle_FxWaveTable+4,Y
    TDC
    SEP #$20
    LDA.b !BattleCD_Tmp45
    BPL .neg_sin_positive
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b #!BattleCD_FxWaveAmpY
    STA.l WRMPYB
    SEC
    RTS
.neg_sin_positive:
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b #!BattleCD_FxWaveAmpY
    STA.l WRMPYB
    CLC
    RTS
.positive:
    REP #$20
    STA.w !Battle_FxWaveTable,Y
    STA.w !Battle_FxWaveTable+4,Y
    SEP #$20
    LDA.b !BattleCD_Tmp45
    BPL .pos_sin_positive
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b #!BattleCD_FxWaveAmpY
    STA.l WRMPYB
    SEC
    RTS
.pos_sin_positive:
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b #!BattleCD_FxWaveAmpY
    STA.l WRMPYB
    CLC
    RTS

; $CD:20B1 — BattleCD_FxWaveStoreY (34 bytes, $20B1–$20D2)
; BattleCD_FxOpWaveTable's y: A + $20, widened to 16 bits as signed,
; plus DP $49, stored as entry Y's two y words.
; Callers (2 JSR sites): BattleCD_FxOpWaveTable ($CD:200F, $CD:2033).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0; A = the signed offset, Y = the
;        entry's offset, DP $49 = the base (16-bit)
; Exit:  M=1, X=0; A = the y's low byte (B = its high byte); X, Y
;        unchanged
BattleCD_FxWaveStoreY:
    CLC
    ADC.b #!BattleCD_FxWaveBaseY
    BPL .positive
    REP #$21
    ORA.w #!BattleFx_SignExtend
    ADC.b !BattleCD_Tmp49
    STA.w !Battle_FxWaveTable+2,Y
    STA.w !Battle_FxWaveTable+6,Y
    SEP #$20
    RTS
.positive:
    REP #$21
    ADC.b !BattleCD_Tmp49
    STA.w !Battle_FxWaveTable+2,Y
    STA.w !Battle_FxWaveTable+6,Y
    SEP #$20
    RTS

; $CD:20D3 — BattleCD_FxOpCEE000 (5 bytes, $20D3–$20D7)
; Opcode $B2 (one operand byte, not read here): JSL BattleCE_UnkE000
; (not matched).
; Entry: M=1, X=0, DP=0, DB=$7E (what the bank-$CE routine needs is not
;        traced)
; Exit:  as BattleCE_UnkE000 leaves it (not traced)
BattleCD_FxOpCEE000:
    JSL BattleCE_UnkE000
    RTS

; $CD:20D8 — BattleCD_FxOpScaleObj (21 bytes, $20D8–$20EC)
; Opcode $B1 (object, step): the object's !Battle_FxObjScale + step.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operands
; Exit:  M=1, X=0; A = the new scale; X = the object; Y = DP $40 + 1
;        (two operand bytes)
BattleCD_FxOpScaleObj:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDY.w #1
    LDA.w !Battle_FxObjScale,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjScale,X
    LDY.b !BattleCD_FxScriptPtr
    INY
    STY.b !BattleCD_FxScriptPtr
    RTS

; $CD:20ED — BattleCD_FxOpBgMode (6 bytes, $20ED–$20F2)
; Opcode $B0 (value): !Battle_HdmaMode (the BGMODE line data) = the
; value.
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operand
; Exit:  M=1, X=0; A = the value; X, Y unchanged
BattleCD_FxOpBgMode:
    LDA.b [!BattleCD_FxScriptPtr]
    STA.w !Battle_HdmaMode
    RTS

; $CD:20F3 — BattleCD_FxOpTriangleOfPcs (40 bytes, $20F3–$211A)
; Opcode $AF (object): the object's triangle (!Battle_FxTriX0-Y2) = the
; screen positions of PC slots 0, 1 and 2 (!Battler_ScreenX/Y).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  M=1, X=0; A = slot 2's y; X = the object; Y unchanged
BattleCD_FxOpTriangleOfPcs:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.w !Battler_ScreenX
    STA.w !Battle_FxTriX0,X
    LDA.w !Battler_ScreenX+1
    STA.w !Battle_FxTriX1,X
    LDA.w !Battler_ScreenX+2
    STA.w !Battle_FxTriX2,X
    LDA.w !Battler_ScreenY
    STA.w !Battle_FxTriY0,X
    LDA.w !Battler_ScreenY+1
    STA.w !Battle_FxTriY1,X
    LDA.w !Battler_ScreenY+2
    STA.w !Battle_FxTriY2,X
    RTS

; $CD:211B — BattleCD_ScaleToCentre (88 bytes, $211B–$2172)
; A = c + (A - c) * DP $21 / 256, with c = DP $47 (the centre): moves a
; coordinate towards the centre by the scale (BattleCD_FxOpFillTriangle).
; The difference is taken 16-bit (DP $45 = A, DP $48 = 0), its
; magnitude multiplied on the CPU's multiplier. Quirk: the non-negative
; path stays at 16 bits for the multiplier (the store to WRMPYA also
; writes WRMPYB, the scale's store also writes DP $22 to WRDIVL, and the
; read takes JOY1L as the high byte); only the low byte is returned, so
; the result is the same.
; Callers (6 JSR sites): BattleCD_FxOpFillTriangle ($CD:2188, $CD:2190, $CD:2198, $CD:21A5,
;   $CD:21AD, $CD:21B5).
; Entry: M=1, X=0, DP=0, DB any (the registers are accessed long); B =
;        0 (the 16-bit TAY); A = the coordinate, DP $47 = the centre, DP
;        $21 = the scale
; Exit:  M=1, X=0; A = the moved coordinate (B = 0); X unchanged; Y = the
;        coordinate; DP $45-$4C written
BattleCD_ScaleToCentre:
    TAY
    STY.b !BattleCD_Tmp45
    STZ.b !BattleCD_Tmp47+1
    REP #$20
    LDA.b !BattleCD_Tmp45
    SEC
    SBC.b !BattleCD_Tmp47
    STA.b !BattleCD_Tmp49
    LDA.b !BattleCD_Tmp49
    BPL .positive
    EOR.w #!Battle_Invert16
    INC A
    SEP #$20
    STA.l WRMPYA
    LDA.b !BattleCD_FxScale
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    REP #$20
    EOR.w #!Battle_Invert16
    INC A
    CLC
    ADC.b !BattleCD_Tmp47
    STA.b !BattleCD_Tmp4B
    TDC
    SEP #$20
    LDA.b !BattleCD_Tmp4B
    RTS
.positive:
    STA.l WRMPYA
    LDA.b !BattleCD_FxScale
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    REP #$20
    CLC
    ADC.b !BattleCD_Tmp47
    STA.b !BattleCD_Tmp4B
    TDC
    SEP #$20
    LDA.b !BattleCD_Tmp4B
    RTS

; $CD:2173 — BattleCD_FxOpFillTriangle (77 bytes, $2173–$21BF)
; Opcode $AE (b): fills the triangle of object (b AND 1)
; (!BattleFx_QuadSlot = it): its three points, each moved towards
; !Battle_FxObjCentreX/Y by !Battle_FxObjScale (BattleCD_ScaleToCentre),
; into DP $12-$17; DP $20 = 0; then BattleCD_FillTriangle (tail jump).
; Also the tail of BattleCD_FxDrawModel.
; Callers (1 JMP site): BattleCD_FxDrawModel ($CD:1EF4).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  as BattleCD_FillTriangle leaves it (not traced); DP $12-$17,
;        $20, $21 and $45-$4C written
BattleCD_FxOpFillTriangle:
    LDA.b [!BattleCD_FxScriptPtr]
    AND.b #1
    STA.w !BattleFx_QuadSlot
    TAX
    LDA.w !Battle_FxObjScale,X
    STA.b !BattleCD_FxScale
    LDA.w !Battle_FxObjCentreX,X
    STA.b !BattleCD_Tmp47
    LDA.w !Battle_FxTriX0,X
    JSR BattleCD_ScaleToCentre
    STA.b !BattleCD_TriX0
    LDA.w !Battle_FxTriX1,X
    JSR BattleCD_ScaleToCentre
    STA.b !BattleCD_TriX1
    LDA.w !Battle_FxTriX2,X
    JSR BattleCD_ScaleToCentre
    STA.b !BattleCD_TriX2
    LDA.w !Battle_FxObjCentreY,X
    STA.b !BattleCD_Tmp47
    LDA.w !Battle_FxTriY0,X
    JSR BattleCD_ScaleToCentre
    STA.b !BattleCD_TriY0
    LDA.w !Battle_FxTriY1,X
    JSR BattleCD_ScaleToCentre
    STA.b !BattleCD_TriY1
    LDA.w !Battle_FxTriY2,X
    JSR BattleCD_ScaleToCentre
    STA.b !BattleCD_TriY2
    STZ.w !BattleCD_TriUnk20
    JMP BattleCD_FillTriangle

; $CD:21C0 — BattleCD_FxOpTriCentre (461 bytes, $21C0–$238C)
; Opcode $AD (object): the object's !Battle_FxObjScale = $FF and its
; centre !Battle_FxObjCentreX/Y = where two medians of its triangle
; meet (the centroid): the line from the midpoint of points 0-1 to
; point 2 and the one from the midpoint of points 0-2 to point 1 (DP
; $12-$19; each midpoint rounded towards the second point; when the
; first midpoint's x, or y, is -4 to +3 from the second's, it is moved
; 4 right, or down). With DB = $00, each line's end points are put in x
; order and its slope taken by BattleCD_Unk38E5 (not matched; DP $0B =
; the end y, $0C = the start y, $0D = the x distance; it returns the
; slope in Y, 256 per pixel, probably); each line's value at x = 0 is b
; = y - x * slope / 256 (BattleCD_Mul8x16); x = (b2 - b1) * 256 / (s1
; - s2) (BattleCD_NormaliseDiv, BattleCD_Div16, the sign put back: the
; slopes being 256 per pixel, that is the x, probably), y = x * s1 / 256
; + b1.
; Callers (1 JSR site): BattleCD_FxOpCentreAndScroll ($CD:1FA0).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  M=1, X=0, DB=$7E (restored); A = the centre y; X = the object;
;        Y as BattleCD_Unk38E5 left it (the second slope, probably); DP
;        $0B-$0D, $12-$19, $23-$2A, $45-$4C written
BattleCD_FxOpTriCentre:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.b #!BattleCD_FxScaleWhole
    STA.w !Battle_FxObjScale,X
    LDA.w !Battle_FxTriX0,X
    SEC
    SBC.w !Battle_FxTriX1,X
    BCS .mid01x_down
    EOR.b #!Battle_Invert8
    INC A
    LSR A
    EOR.b #!Battle_Invert8
    INC A
    BRA .mid01x
.mid01x_down:
    LSR A
.mid01x:
    CLC
    ADC.w !Battle_FxTriX1,X
    STA.b !BattleCD_LineAX0
    LDA.w !Battle_FxTriY0,X
    SEC
    SBC.w !Battle_FxTriY1,X
    BCS .mid01y_down
    EOR.b #!Battle_Invert8
    INC A
    LSR A
    EOR.b #!Battle_Invert8
    INC A
    BRA .mid01y
.mid01y_down:
    LSR A
.mid01y:
    CLC
    ADC.w !Battle_FxTriY1,X
    STA.b !BattleCD_LineAY0
    LDA.w !Battle_FxTriX2,X
    STA.b !BattleCD_LineAX1
    LDA.w !Battle_FxTriY2,X
    STA.b !BattleCD_LineAY1
    LDA.w !Battle_FxTriX0,X
    SEC
    SBC.w !Battle_FxTriX2,X
    BCS .mid02x_down
    EOR.b #!Battle_Invert8
    INC A
    LSR A
    EOR.b #!Battle_Invert8
    INC A
    BRA .mid02x
.mid02x_down:
    LSR A
.mid02x:
    CLC
    ADC.w !Battle_FxTriX2,X
    STA.b !BattleCD_LineBX0
    LDA.w !Battle_FxTriY0,X
    SEC
    SBC.w !Battle_FxTriY2,X
    BCS .mid02y_down
    EOR.b #!Battle_Invert8
    INC A
    LSR A
    EOR.b #!Battle_Invert8
    INC A
    BRA .mid02y
.mid02y_down:
    LSR A
.mid02y:
    CLC
    ADC.w !Battle_FxTriY2,X
    STA.b !BattleCD_LineBY0
    LDA.w !Battle_FxTriX1,X
    STA.b !BattleCD_LineBX1
    LDA.w !Battle_FxTriY1,X
    STA.b !BattleCD_LineBY1
    PHB
    TDC
    PHA
    PLB
    LDA.b !BattleCD_LineAX0
    SEC
    SBC.b !BattleCD_LineBX0
    CMP.b #!BattleCD_FxNearNeg
    BCS .nudge_x
    CMP.b #!BattleCD_FxNear
    BCS .check_y
.nudge_x:
    LDA.b !BattleCD_LineAX0
    CLC
    ADC.b #!BattleCD_FxNear
    STA.b !BattleCD_LineAX0
.check_y:
    LDA.b !BattleCD_LineAY0
    SEC
    SBC.b !BattleCD_LineBY0
    CMP.b #!BattleCD_FxNearNeg
    BCS .nudge_y
    CMP.b #!BattleCD_FxNear
    BCS .order_a
.nudge_y:
    LDA.b !BattleCD_LineAY0
    CLC
    ADC.b #!BattleCD_FxNear
    STA.b !BattleCD_LineAY0
.order_a:
    LDA.b !BattleCD_LineAX0
    CMP.b !BattleCD_LineAX1
    BCC .order_b
    LDX.b !BattleCD_LineAX0
    LDY.b !BattleCD_LineAX1
    STY.b !BattleCD_LineAX0
    STX.b !BattleCD_LineAX1
.order_b:
    LDA.b !BattleCD_LineBX0
    CMP.b !BattleCD_LineBX1
    BCC .slopes
    LDX.b !BattleCD_LineBX0
    LDY.b !BattleCD_LineBX1
    STY.b !BattleCD_LineBX0
    STX.b !BattleCD_LineBX1
.slopes:
    LDA.b !BattleCD_LineAY1
    STA.b !BattleCD_SlopeEndY
    LDA.b !BattleCD_LineAY0
    STA.b !BattleCD_SlopeStartY
    LDA.b !BattleCD_LineAX1
    SEC
    SBC.b !BattleCD_LineAX0
    STA.b !BattleCD_SlopeDx
    JSR BattleCD_Unk38E5
    STY.b !BattleCD_SlopeA
    LDA.b !BattleCD_LineBY1
    STA.b !BattleCD_SlopeEndY
    LDA.b !BattleCD_LineBY0
    STA.b !BattleCD_SlopeStartY
    LDA.b !BattleCD_LineBX1
    SEC
    SBC.b !BattleCD_LineBX0
    STA.b !BattleCD_SlopeDx
    JSR BattleCD_Unk38E5
    STY.b !BattleCD_SlopeB
    LDA.b !BattleCD_LineAX0
    STA.b !BattleCD_MathA
    REP #$20
    LDA.b !BattleCD_SlopeA
    BPL .a_positive
    EOR.w #!Battle_Invert16
    INC A
    STA.b !BattleCD_MathB
    SEP #$20
    TDC
    JSR BattleCD_Mul8x16
    REP #$20
    LDA.b !BattleCD_MathOut+1
    EOR.w #!Battle_Invert16
    INC A
    STA.b !BattleCD_MathOut+1
    BRA .a_base
.a_positive:
    STA.b !BattleCD_MathB
    SEP #$20
    TDC
    JSR BattleCD_Mul8x16
    REP #$20
.a_base:
    LDA.b !BattleCD_LineAY0
    AND.w #!Battle_LowByteMask
    SEC
    SBC.b !BattleCD_MathOut+1
    STA.b !BattleCD_BaseA
    TDC
    SEP #$20
    LDA.b !BattleCD_LineBX0
    STA.b !BattleCD_MathA
    REP #$20
    LDA.b !BattleCD_SlopeB
    BPL .b_positive
    EOR.w #!Battle_Invert16
    INC A
    STA.b !BattleCD_MathB
    SEP #$20
    TDC
    JSR BattleCD_Mul8x16
    REP #$20
    LDA.b !BattleCD_MathOut+1
    EOR.w #!Battle_Invert16
    INC A
    STA.b !BattleCD_MathOut+1
    BRA .b_base
.b_positive:
    STA.b !BattleCD_MathB
    SEP #$20
    TDC
    JSR BattleCD_Mul8x16
    REP #$20
.b_base:
    LDA.b !BattleCD_LineBY0
    AND.w #!Battle_LowByteMask
    SEC
    SBC.b !BattleCD_MathOut+1
    STA.b !BattleCD_BaseB
    LDA.b !BattleCD_BaseB
    SEC
    SBC.b !BattleCD_BaseA
    BPL .rise_positive
    EOR.w #!Battle_Invert16
    INC A
    STA.b !BattleCD_MathA
    LDA.b !BattleCD_SlopeA
    SEC
    SBC.b !BattleCD_SlopeB
    BPL .divide_negated
    EOR.w #!Battle_Invert16
    INC A
    BRA .divide
.divide_negated:
    STA.b !BattleCD_MathB
    BRA .negated
.rise_positive:
    STA.b !BattleCD_MathA
    LDA.b !BattleCD_SlopeA
    SEC
    SBC.b !BattleCD_SlopeB
    BPL .divide
    EOR.w #!Battle_Invert16
    INC A
    STA.b !BattleCD_MathB
.negated:
    JSR BattleCD_NormaliseDiv
    JSR BattleCD_Div16
    LDA.b !BattleCD_MathOut
    EOR.w #!Battle_Invert16
    INC A
    STA.b !BattleCD_MathOut
    BRA .centre
.divide:
    STA.b !BattleCD_MathB
    JSR BattleCD_NormaliseDiv
    JSR BattleCD_Div16
.centre:
    TDC
    SEP #$20
    PLB
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.b !BattleCD_MathOut
    STA.w !Battle_FxObjCentreX,X
    PHX
    STA.b !BattleCD_MathA
    LDX.b !BattleCD_SlopeA
    STX.b !BattleCD_MathB
    JSR BattleCD_Mul8x16
    REP #$20
    LDA.b !BattleCD_MathOut+1
    CLC
    ADC.b !BattleCD_BaseA
    STA.b !BattleCD_MathOut+1
    TDC
    SEP #$20
    PLX
    LDA.b !BattleCD_MathOut+1
    STA.w !Battle_FxObjCentreY,X
    RTS

; $CD:238D — BattleCD_NormaliseDiv (166 bytes, $238D–$2432)
; Prepares BattleCD_Div16 for a quotient scaled by 256: shifts the
; dividend DP $23 left by n, its leading zero bits (at most 8), and the
; divisor DP $25 right by 8 - n. Laid out as a JMP to the test ladder
; at the end, with one shift step per case before it.
; Callers (2 JSR sites): BattleCD_FxOpTriCentre ($CD:234C, $CD:235E).
; Entry: M=0 (16-bit shifts and masks), X any, DP=0, DB any; DP $23 the
;        dividend, DP $25 the divisor
; Exit:  M=0; DP $23 and $25 shifted; A = the last value shifted; X, Y
;        unchanged
BattleCD_NormaliseDiv:
    JMP .ladder
.lead2:
    LDA.b !BattleCD_MathA
    ASL A
    ASL A
    STA.b !BattleCD_MathA
    LDA.b !BattleCD_MathB
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !BattleCD_MathB
    RTS
.lead1:
    LDA.b !BattleCD_MathA
    ASL A
    STA.b !BattleCD_MathA
    LDA.b !BattleCD_MathB
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !BattleCD_MathB
    RTS
.lead0:
    LDA.b !BattleCD_MathB
    XBA
    AND.w #!Battle_LowByteMask
    STA.b !BattleCD_MathB
    RTS
.ladder:
    LDA.b !BattleCD_MathA
    ASL A
    BCS .lead0
    ASL A
    BCS .lead1
    ASL A
    BCS .lead2
    ASL A
    BCS .lead3
    ASL A
    BCS .lead4
    ASL A
    BCS .lead5
    ASL A
    BCS .lead6
    ASL A
    BCS .lead7
    LDA.b !BattleCD_MathA
    XBA
    AND.w #!BattleCD_HighByteMask
    STA.b !BattleCD_MathA
    RTS
.lead7:
    LDA.b !BattleCD_MathA
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    STA.b !BattleCD_MathA
    LDA.b !BattleCD_MathB
    LSR A
    STA.b !BattleCD_MathB
    RTS
.lead6:
    LDA.b !BattleCD_MathA
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    STA.b !BattleCD_MathA
    LDA.b !BattleCD_MathB
    LSR A
    LSR A
    STA.b !BattleCD_MathB
    RTS
.lead5:
    LDA.b !BattleCD_MathA
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    STA.b !BattleCD_MathA
    LDA.b !BattleCD_MathB
    LSR A
    LSR A
    LSR A
    STA.b !BattleCD_MathB
    RTS
.lead4:
    LDA.b !BattleCD_MathA
    ASL A
    ASL A
    ASL A
    ASL A
    STA.b !BattleCD_MathA
    LDA.b !BattleCD_MathB
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !BattleCD_MathB
    RTS
.lead3:
    LDA.b !BattleCD_MathA
    ASL A
    ASL A
    ASL A
    STA.b !BattleCD_MathA
    LDA.b !BattleCD_MathB
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !BattleCD_MathB
    RTS

; $CD:2433 — BattleCD_ClampCalcPair (45 bytes, $2433–$245F)
; Clamps the two points at !Battle_ActCalcResult+X (x, y, x, y) to the
; screen: the x bytes with BattleCD_ClampX (8-$F8), the y bytes with
; BattleCD_ClampY (8-$D4). BattleCD_ClampCalcPair01 ($2436) does it
; for entries 0 and 1 (X = 0 inside).
; Sub-entry: BattleCD_ClampCalcPair01.
; Callers (1 JSR site): BattleCD_FxOpBeamFromPair ($CD:19B9).
; Callers of BattleCD_ClampCalcPair01 (4 JSR sites): BattleCD_ClampCalcAngle ($CD:1B1F),
;   BattleCD_ScrollToCalc ($CD:1C36), BattleCD_FxOpCalcToValues ($CD:24F3) and unmatched ($CD:CCE4).
; Entry: M=1, X=0, DP any, DB=$7E; X = the first point's offset (not
;        read by BattleCD_ClampCalcPair01)
; Exit:  M=1, X=0; X as on entry (PHX/PLX at 16 bits); A = the second
;        y; Y unchanged
BattleCD_ClampCalcPair:
    PHX
    BRA BattleCD_ClampCalcPair01_clamp
BattleCD_ClampCalcPair01:               ; header: see BattleCD_ClampCalcPair
    PHX
    LDX.w #0
.clamp:
    LDA.w !Battle_ActCalcResult,X
    JSR BattleCD_ClampX
    STA.w !Battle_ActCalcResult,X
    LDA.w !Battle_ActCalcResult+1,X
    JSR BattleCD_ClampY
    STA.w !Battle_ActCalcResult+1,X
    LDA.w !Battle_ActCalcResult+2,X
    JSR BattleCD_ClampX
    STA.w !Battle_ActCalcResult+2,X
    LDA.w !Battle_ActCalcResult+3,X
    JSR BattleCD_ClampY
    STA.w !Battle_ActCalcResult+3,X
    PLX
    RTS

; $CD:2460 — BattleCD_FxOpBeam (147 bytes, $2460–$24F2)
; Opcode $AC (object, pair n): a beam of half-width w (variable $0E,
; signed) between P = !Battle_ActCalcResult entry 2n and Q = entry
; 2n+1, at right angles to !Battle_FxAngle (from entries 2 and 3 here,
; BattleCD_ClampCalcAngle with X = 4, which also clamps entries 0 and 1):
; the object's four corners !Battle_FxQuadX0-Y3 = P + o1, P + o2, Q +
; o1, Q + o2, with o1/o2 = w times cos/sin of angle - $40 and angle +
; $40 (BattleCD_CosMul / BattleCD_SinMul); then JSL BattleFx_DrawQuad
; (draws the object's quad into this frame's window table). BattleCD_FxOpBeamQuad
; ($2466) is everything after the angle, the tail of opcode $D9
; (BattleCD_FxOpBeamFromPair).
; Sub-entry: BattleCD_FxOpBeamQuad.
; Callers of BattleCD_FxOpBeamQuad (1 JMP site): BattleCD_FxOpBeamFromPair ($CD:19BF).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operands
;        (BattleCD_ClampCalcAngle runs BattleCE_UnkE7CF, assumed to
;        return M=1, X=0)
; Exit:  M=1, X=0 (as BattleFx_DrawQuad leaves them); Y = DP $40 + 1
;        (two operand bytes); DP $03-$19, $23-$26 and $45-$4C written
BattleCD_FxOpBeam:
    LDX.w #4
    JSR BattleCD_ClampCalcAngle
BattleCD_FxOpBeamQuad:                  ; header: see BattleCD_FxOpBeam
    LDA.w !Battle_ActVar0E
    TAY
    LDA.w !Battle_FxAngle
    SEC
    SBC.b #!Battle_AngleQuarter
    STA.b !BattleCD_Tmp45
    CLC
    ADC.b #!Battle_AngleHalfTurn
    STA.b !BattleCD_Tmp47
    SEP #$10
    LDA.b !BattleCD_Tmp45
    JSR BattleCD_CosMul
    STA.b !BattleCD_Tmp49
    LDA.b !BattleCD_Tmp45
    JSR BattleCD_SinMul
    STA.b !BattleCD_Tmp4B
    LDA.b !BattleCD_Tmp47
    JSR BattleCD_CosMul
    STA.b !BattleCD_Tmp45
    LDA.b !BattleCD_Tmp47
    JSR BattleCD_SinMul
    STA.b !BattleCD_Tmp47
    LDY.b #1
    LDA.b [!BattleCD_FxScriptPtr],Y
    ASL A
    ASL A
    TAY
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.w !Battle_ActCalcResult,Y
    CLC
    ADC.b !BattleCD_Tmp49
    STA.w !Battle_FxQuadX0,X
    LDA.w !Battle_ActCalcResult+1,Y
    CLC
    ADC.b !BattleCD_Tmp4B
    STA.w !Battle_FxQuadY0,X
    LDA.w !Battle_ActCalcResult,Y
    CLC
    ADC.b !BattleCD_Tmp45
    STA.w !Battle_FxQuadX1,X
    LDA.w !Battle_ActCalcResult+1,Y
    CLC
    ADC.b !BattleCD_Tmp47
    STA.w !Battle_FxQuadY1,X
    LDA.w !Battle_ActCalcResult+2,Y
    CLC
    ADC.b !BattleCD_Tmp49
    STA.w !Battle_FxQuadX2,X
    LDA.w !Battle_ActCalcResult+3,Y
    CLC
    ADC.b !BattleCD_Tmp4B
    STA.w !Battle_FxQuadY2,X
    LDA.w !Battle_ActCalcResult+2,Y
    CLC
    ADC.b !BattleCD_Tmp45
    STA.w !Battle_FxQuadX3,X
    LDA.w !Battle_ActCalcResult+3,Y
    CLC
    ADC.b !BattleCD_Tmp47
    STA.w !Battle_FxQuadY3,X
    REP #$10
    JSL BattleFx_DrawQuad
    LDY.b !BattleCD_FxScriptPtr
    INY
    STY.b !BattleCD_FxScriptPtr
    RTS

; $CD:24F3 — BattleCD_FxOpCalcToValues (37 bytes, $24F3–$2517)
; Opcode $AB (b): the point of !Battle_ActCalcResult entry (b AND $7F)
; (entries 0 and 1 clamped to the screen first,
; BattleCD_ClampCalcPair01) into !Battle_FxValues: x to entry 2 and y
; to entry 4, or with b bit 7 set to entries 3 and 5.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAY); DP $40 at the
;        operand
; Exit:  M=1, X=0; A = the y; X unchanged; Y = (b AND $7F) * 2
BattleCD_FxOpCalcToValues:
    JSR BattleCD_ClampCalcPair01
    LDA.b [!BattleCD_FxScriptPtr]
    ASL A
    TAY
    LDA.b [!BattleCD_FxScriptPtr]
    BMI .odd
    LDA.w !Battle_ActCalcResult,Y
    STA.w !Battle_FxValues+2
    LDA.w !Battle_ActCalcResult+1,Y
    STA.w !Battle_FxValues+4
    RTS
.odd:
    LDA.w !Battle_ActCalcResult,Y
    STA.w !Battle_FxValues+3
    LDA.w !Battle_ActCalcResult+1,Y
    STA.w !Battle_FxValues+5
    RTS

; $CD:2518 — BattleCD_FxOpWaitVarSet (35 bytes, $2518–$253A)
; Opcode $A9 (n, back): while variable n (!Battle_ActVars) is 0,
; branches back by the second operand (see the banner); else skips both
; operands.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAXs); DP $40 at the
;        operands
; Exit:  M=1, X=0; branch: A = 0 (B = 0), X = the distance, Y = 1, DP
;        $40 - the distance, DP $45 written; else A = the variable, X =
;        n, Y = DP $40 + 1
BattleCD_FxOpWaitVarSet:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDA.w !Battle_ActVars,X
    BNE .next
    LDY.w #1
    LDA.b [!BattleCD_FxScriptPtr],Y
    TAX
    STX.b !BattleCD_Tmp45
    REP #$20
    LDA.b !BattleCD_FxScriptPtr
    SEC
    SBC.b !BattleCD_Tmp45
    STA.b !BattleCD_FxScriptPtr
    TDC
    SEP #$20
    RTS
.next:
    LDY.b !BattleCD_FxScriptPtr
    INY
    STY.b !BattleCD_FxScriptPtr
    RTS

; $CD:253B — BattleCD_FxOpWaves (293 bytes, $253B–$265F)
; Opcode $8F (layers, amplitude, speed): the per-line wave offsets
; (!Battle_WaveOffsets) of the wave scroll. On frames where
; !Battle_FrameCount AND (layers AND $1F) is 0 the phase
; !Battle_WavePhase + the speed. Then, from the phase on:
;   - speed bit 7 set (speed AND $7F is added): 64 entries, the angle
;     stepped by 4 each, !Battle_LayerFxMode = 3;
;   - else 32 entries stepped by 8, !Battle_LayerFxMode = 2;
; each entry's word = amplitude * sin(angle) / 256 (signed, on the
; multiplier from !BattleRom_AbsSine, widened to 16 bits). Last
; !Battle_WaveBg3/2/1 = layers bits 7/6/5 (words), except that
; !Battle_WaveBg1 stays 0 while !Battle_Unk99D2 AND $7F is 1.
; Entry: M=1, X=0, DP=0, DB=$7E (the multiplier is accessed long); DP
;        $40 at the operands
; Exit:  M=1, X=0; A = 0 or the masked byte; X = 0; Y = DP $40 + 2
;        (three operand bytes); DP $45-$49 written
BattleCD_FxOpWaves:
    LDY.w #1
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.b !BattleCD_Tmp45
    INY
    LDA.b [!BattleCD_FxScriptPtr]
    AND.b #!BattleCD_FxWaveFrameMask
    STA.b !BattleCD_Tmp47
    LDA.b [!BattleCD_FxScriptPtr],Y
    BPL .narrow
    AND.b #!BattleCD_FxWaveSpeedMask
    STA.b !BattleCD_Tmp49
    SEP #$10
    LDA.b !Battle_FrameCount
    AND.b !BattleCD_Tmp47
    BNE .wide_phase
    LDA.w !Battle_WavePhase
    CLC
    ADC.b !BattleCD_Tmp49
    STA.w !Battle_WavePhase
.wide_phase:
    LDA.w !Battle_WavePhase
    TAX
    TDC
    TAY
.wide_entry:
    TXA
    BPL .wide_sin_positive
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp45
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    EOR.b #!Battle_Invert8
    INC A
.wide_store:
    BPL .wide_store_positive
    STA.w !Battle_WaveOffsets,Y
    LDA.b #!BattleCD_FxSignByte
    STA.w !Battle_WaveOffsets+1,Y
    BRA .wide_next
.wide_store_positive:
    STA.w !Battle_WaveOffsets,Y
    TDC
    STA.w !Battle_WaveOffsets+1,Y
    BRA .wide_next
.wide_sin_positive:
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp45
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    BRA .wide_store
.wide_next:
    TXA
    CLC
    ADC.b #4
    TAX
    INY
    INY
    INY
    INY
    BNE .wide_entry
    LDA.b #!BattleCD_ScrollWavesBg3Mode
    STA.w !Battle_LayerFxMode
    JMP .layers
.narrow:
    SEP #$10
    LDA.b !Battle_FrameCount
    AND.b !BattleCD_Tmp47
    BNE .narrow_phase
    LDA.w !Battle_WavePhase
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_WavePhase
.narrow_phase:
    LDA.w !Battle_WavePhase
    TAX
    TDC
    TAY
.narrow_entry:
    TXA
    BPL .narrow_sin_positive
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp45
    STA.l WRMPYB
    INY
    INY
    INY
    INY
    LDA.l RDMPYH
    EOR.b #!Battle_Invert8
    INC A
.narrow_store:
    BPL .narrow_store_positive
    STA.w !Battle_WaveOffsets-4,Y
    LDA.b #!BattleCD_FxSignByte
    STA.w !Battle_WaveOffsets-3,Y
    BRA .narrow_next
.narrow_store_positive:
    STA.w !Battle_WaveOffsets-4,Y
    TDC
    STA.w !Battle_WaveOffsets-3,Y
    BRA .narrow_next
.narrow_sin_positive:
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp45
    STA.l WRMPYB
    INY
    INY
    INY
    INY
    LDA.l RDMPYH
    BRA .narrow_store
.narrow_next:
    TXA
    CLC
    ADC.b #8
    TAX
    CPY.b #!BattleCD_ScrollFillEnd
    BNE .narrow_entry
    LDA.b #!BattleCD_ScrollWavesMode
    STA.w !Battle_LayerFxMode
.layers:
    REP #$10
    TDC
    TAX
    STX.w !Battle_WaveBg1
    STX.w !Battle_WaveBg2
    STX.w !Battle_WaveBg3
    LDA.b [!BattleCD_FxScriptPtr]
    ASL A
    ROL.w !Battle_WaveBg3
    ASL A
    ROL.w !Battle_WaveBg2
    ASL A
    ROL.w !Battle_WaveBg1
    LDY.b !BattleCD_FxScriptPtr
    INY
    INY
    STY.b !BattleCD_FxScriptPtr
    LDA.w !Battle_Unk99D2
    AND.b #!BattleCD_99D2Mask
    CMP.b #1
    BNE .done
    TDC
    TAX
    STX.w !Battle_WaveBg1
.done:
    RTS

; $CD:2660 — BattleCD_FxOpSetObjAngles (39 bytes, $2660–$2686)
; Opcode $A7 (object, three angles): the object's
; !Battle_FxObjAngleX/Y/Z = the angles, !Battle_FxObjDepth = 0,
; !Battle_FxObjScale = $FF.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operands
; Exit:  M=1, X=0; A = $FF; X = the object; Y = DP $40 + 3 (four
;        operand bytes)
BattleCD_FxOpSetObjAngles:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDY.w #1
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjAngleX,X
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjAngleY,X
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjAngleZ,X
    STZ.w !Battle_FxObjDepth,X
    LDA.b #!BattleCD_FxScaleWhole
    STA.w !Battle_FxObjScale,X
    LDY.b !BattleCD_FxScriptPtr
    INY
    INY
    INY
    STY.b !BattleCD_FxScriptPtr
    RTS

; $CD:2687 — BattleCD_FxOpBumpCA24 (9 bytes, $2687–$268F)
; Opcode $87 (value): !BattleFx_CeSetBase = the value and !BattleFx_CeSetReload +
; 1 (as the message and wipe code bump them).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $40 at the operand
; Exit:  M=1, X=0; A = the value; X, Y unchanged
BattleCD_FxOpBumpCA24:
    LDA.b [!BattleCD_FxScriptPtr]
    STA.w !BattleFx_CeSetBase
    INC.w !BattleFx_CeSetReload
    RTS

; $CD:2690 — BattleCD_FxOpSaveObjs (32 bytes, $2690–$26AF)
; Opcode $A5 (slot 0-7): copies the two objects' fields
; (!Battle_FxObjCentreX on, !BattleCD_FxObjBytes bytes) to save slot
; slot of !Battle_FxObjSaves (offset from BattleCD_FxObjSaveOfs).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  M=1, X=0; A = 0 (B = 0); X = the slot's end; Y =
;        !BattleCD_FxObjBytes
BattleCD_FxOpSaveObjs:
    LDA.b [!BattleCD_FxScriptPtr]
    ASL A
    TAX
    REP #$20
    LDA.l BattleCD_FxObjSaveOfs,X
    TAX
    TDC
    TAY
.word:
    LDA.w !Battle_FxObjCentreX,Y
    STA.w !Battle_FxObjSaves,X
    INX
    INX
    INY
    INY
    CPY.w #!BattleCD_FxObjBytes
    BNE .word
    TDC
    SEP #$20
    RTS

; $CD:26B0 — BattleCD_FxObjSaveOfs (8 words, $26B0–$26BF)
; Offset of each save slot in !Battle_FxObjSaves (slot *
; !BattleCD_FxObjBytes).
BattleCD_FxObjSaveOfs:
    dw $0000,$002A,$0054,$007E,$00A8,$00D2,$00FC,$0126

; $CD:26C0 — BattleCD_FxOpLoadObjs (32 bytes, $26C0–$26DF)
; Opcode $A6 (slot 0-7): the two objects' fields back from save slot
; slot (the reverse of BattleCD_FxOpSaveObjs).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  M=1, X=0; A = 0 (B = 0); X = the slot's end; Y =
;        !BattleCD_FxObjBytes
BattleCD_FxOpLoadObjs:
    LDA.b [!BattleCD_FxScriptPtr]
    ASL A
    TAX
    REP #$20
    LDA.l BattleCD_FxObjSaveOfs,X
    TAX
    TDC
    TAY
.word:
    LDA.w !Battle_FxObjSaves,X
    STA.w !Battle_FxObjCentreX,Y
    INX
    INX
    INY
    INY
    CPY.w #!BattleCD_FxObjBytes
    BNE .word
    TDC
    SEP #$20
    RTS

; $CD:26E0 — BattleCD_FxOpSetObjPhases (55 bytes, $26E0–$2716)
; Opcode $A4 (object, six values): the object's
; !Battle_FxObjPhaseA/B/C and !Battle_FxObjUnkDA/DC/DE (the radii of the
; ring opcodes) = the values.
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operands
; Exit:  M=1, X=0; A = 0 (B = 0); X = the object; Y = 6; DP $40 + 6
;        (seven operand bytes)
BattleCD_FxOpSetObjPhases:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDY.w #1
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjPhaseA,X
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjPhaseB,X
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjPhaseC,X
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjUnkDA,X
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjUnkDC,X
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjUnkDE,X
    REP #$20
    LDA.b !BattleCD_FxScriptPtr
    CLC
    ADC.w #6
    STA.b !BattleCD_FxScriptPtr
    TDC
    SEP #$20
    RTS

; $CD:2717 — BattleCD_FxOpStepEllipse (119 bytes, $2717–$278D)
; Opcode $A3 (object, then dx, dy, dr, dsx, dsy, dphase): steps the
; object's flat ring: !Battle_FxObjCentreX/Y + dx/dy, the three radii
; !Battle_FxObjUnkDA/DC/DE each + dr, !Battle_FxObjSquashX/Y + dsx/dsy,
; the three phases !Battle_FxObjPhaseA/B/C each + dphase; then the
; triangle from them (BattleCD_FxEllipseTriangle).
; Entry: M=1, X any (SEP #$10 here), DP=0, DB=$7E; DP $40 at the
;        operands
; Exit:  M=1, X=0 (REP #$30); A = 0 (B = 0); X = the object (high byte
;        0); Y as BattleCD_FxEllipseTriangle leaves it (high byte 0); DP
;        $40 + 6 (seven operand bytes); DP $45-$49 written
BattleCD_FxOpStepEllipse:
    SEP #$10
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDY.b #1
    LDA.w !Battle_FxObjCentreX,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjCentreX,X
    INY
    LDA.w !Battle_FxObjCentreY,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjCentreY,X
    INY
    LDA.w !Battle_FxObjUnkDA,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjUnkDA,X
    LDA.w !Battle_FxObjUnkDC,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjUnkDC,X
    LDA.w !Battle_FxObjUnkDE,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjUnkDE,X
    INY
    LDA.w !Battle_FxObjSquashX,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjSquashX,X
    INY
    LDA.w !Battle_FxObjSquashY,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjSquashY,X
    INY
    LDA.w !Battle_FxObjPhaseA,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjPhaseA,X
    LDA.w !Battle_FxObjPhaseB,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjPhaseB,X
    LDA.w !Battle_FxObjPhaseC,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjPhaseC,X
    JSR BattleCD_FxEllipseTriangle
    REP #$30
    LDA.b !BattleCD_FxScriptPtr
    CLC
    ADC.w #6
    STA.b !BattleCD_FxScriptPtr
    TDC
    SEP #$20
    RTS

; $CD:278E — BattleCD_FxOpSetEllipse (60 bytes, $278E–$27C9)
; Opcode $A2 (object, x, y, radius): the object's flat ring:
; !Battle_FxObjCentreX/Y = x, y; the three radii
; !Battle_FxObjUnkDA/DC/DE = radius; phases !Battle_FxObjPhaseA/B/C =
; !BattleCD_FxPhaseA/B/C ($C0, $15, $6A: a third of a turn apart);
; !Battle_FxObjSquashX/Y = !Battle_AngleQuarter (|sin| = 255: not
; squashed).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operands
; Exit:  M=1, X=0; A = !Battle_AngleQuarter; X = the object; Y = DP $40
;        + 3 (four operand bytes)
BattleCD_FxOpSetEllipse:
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDY.w #1
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjCentreX,X
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjCentreY,X
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjUnkDA,X
    STA.w !Battle_FxObjUnkDC,X
    STA.w !Battle_FxObjUnkDE,X
    LDA.b #!BattleCD_FxPhaseA
    STA.w !Battle_FxObjPhaseA,X
    LDA.b #!BattleCD_FxPhaseB
    STA.w !Battle_FxObjPhaseB,X
    LDA.b #!BattleCD_FxPhaseC
    STA.w !Battle_FxObjPhaseC,X
    LDA.b #!Battle_AngleQuarter
    STA.w !Battle_FxObjSquashX,X
    STA.w !Battle_FxObjSquashY,X
    LDY.b !BattleCD_FxScriptPtr
    INY
    INY
    INY
    STY.b !BattleCD_FxScriptPtr
    RTS

; $CD:27CA — BattleCD_FxOpStepRing3d (121 bytes, $27CA–$2842)
; Opcode $A8 (object, then dx, dy, dz, dr, dax, day, daz, dscale): steps
; the object's turning ring: !Battle_FxObjCentreX/Y and
; !Battle_FxObjDepth + dx/dy/dz, the three radii
; !Battle_FxObjUnkDA/DC/DE each + dr, !Battle_FxObjAngleX/Y/Z +
; dax/day/daz, !Battle_FxObjScale + dscale; then the triangle from them
; (BattleCD_FxRing3dTriangle).
; Entry: M=1, X any (SEP #$10 here), DP=0, DB=$7E; DP $40 at the
;        operands
; Exit:  M=1, X=0 (REP #$30); A = 0 (B = 0); X = the object (high byte
;        0); Y = BattleCD_Rotate3d's (high byte 0); DP $40 + 8 (nine
;        operand bytes); DP $21, $47, $49-$4E written
BattleCD_FxOpStepRing3d:
    SEP #$10
    LDA.b [!BattleCD_FxScriptPtr]
    TAX
    LDY.b #1
    LDA.w !Battle_FxObjCentreX,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjCentreX,X
    INY
    LDA.w !Battle_FxObjCentreY,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjCentreY,X
    INY
    LDA.w !Battle_FxObjDepth,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjDepth,X
    INY
    LDA.w !Battle_FxObjUnkDA,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjUnkDA,X
    LDA.w !Battle_FxObjUnkDC,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjUnkDC,X
    LDA.w !Battle_FxObjUnkDE,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjUnkDE,X
    INY
    LDA.w !Battle_FxObjAngleX,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjAngleX,X
    INY
    LDA.w !Battle_FxObjAngleY,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjAngleY,X
    INY
    LDA.w !Battle_FxObjAngleZ,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjAngleZ,X
    INY
    LDA.w !Battle_FxObjScale,X
    CLC
    ADC.b [!BattleCD_FxScriptPtr],Y
    STA.w !Battle_FxObjScale,X
    JSR BattleCD_FxRing3dTriangle
    REP #$30
    LDA.b !BattleCD_FxScriptPtr
    CLC
    ADC.w #8
    STA.b !BattleCD_FxScriptPtr
    TDC
    SEP #$20
    RTS

; $CD:2843 — BattleCD_FxRing3dTriangle (94 bytes, $2843–$28A0)
; The object's triangle from its turning ring: for each of the three
; vertices, radius !Battle_FxObjUnkDA/DC/DE and phase
; !Battle_FxObjPhaseA/B/C, the point BattleCD_FxRingVertex rotates,
; plus !Battle_FxObjCentreX/Y, into !Battle_FxTriX0-Y2.
; Callers (1 JSR site): BattleCD_FxOpStepRing3d ($CD:2832).
; Entry: M=1, X=1 (the callees' 8-bit index), DP=0, DB=$7E; X = the
;        object
; Exit:  M=1, X=1; A = the third point's y; X unchanged; Y =
;        BattleCD_Rotate3d's; DP $21, $47, $49-$4E written
BattleCD_FxRing3dTriangle:
    LDA.w !Battle_FxObjUnkDA,X
    STA.b !BattleCD_Tmp47
    LDA.w !Battle_FxObjPhaseA,X
    JSR BattleCD_FxRingVertex
    LDA.w !Battle_FxRotOutX
    CLC
    ADC.w !Battle_FxObjCentreX,X
    STA.w !Battle_FxTriX0,X
    LDA.w !Battle_FxRotOutY
    CLC
    ADC.w !Battle_FxObjCentreY,X
    STA.w !Battle_FxTriY0,X
    LDA.w !Battle_FxObjUnkDC,X
    STA.b !BattleCD_Tmp47
    LDA.w !Battle_FxObjPhaseB,X
    JSR BattleCD_FxRingVertex
    LDA.w !Battle_FxRotOutX
    CLC
    ADC.w !Battle_FxObjCentreX,X
    STA.w !Battle_FxTriX1,X
    LDA.w !Battle_FxRotOutY
    CLC
    ADC.w !Battle_FxObjCentreY,X
    STA.w !Battle_FxTriY1,X
    LDA.w !Battle_FxObjUnkDE,X
    STA.b !BattleCD_Tmp47
    LDA.w !Battle_FxObjPhaseC,X
    JSR BattleCD_FxRingVertex
    LDA.w !Battle_FxRotOutX
    CLC
    ADC.w !Battle_FxObjCentreX,X
    STA.w !Battle_FxTriX2,X
    LDA.w !Battle_FxRotOutY
    CLC
    ADC.w !Battle_FxObjCentreY,X
    STA.w !Battle_FxTriY2,X
    RTS

; $CD:28A1 — BattleCD_FxRingVertex (49 bytes, $28A1–$28D1)
; One ring vertex of object X at phase A, radius DP $47:
; !Battle_FxRotInX = sin(phase) / 2 * radius / 256 and
; !Battle_FxRotInY = the same with cos (BattleCD_HalfSinMul),
; !Battle_FxRotInZ = the object's !Battle_FxObjDepth, rotated by its
; !Battle_FxObjAngleX/Y/Z (DP $49/$4B/$4D) with DP $21 = its
; !Battle_FxObjScale (BattleCD_Rotate3d).
; Callers (3 JSR sites): BattleCD_FxRing3dTriangle ($CD:284B, $CD:286A, $CD:2889).
; Entry: M=1, X=1 (8-bit PHX/PLX and the callees), DP=0, DB=$7E; A =
;        the phase, X = the object, DP $47 = the radius
; Exit:  M=1, X=1; A = !Battle_FxRotOutX; X unchanged; Y =
;        BattleCD_Rotate3d's; DP $21, $47, $49, $4B, $4D written
BattleCD_FxRingVertex:
    PHX
    PHA
    CLC
    ADC.b #!Battle_AngleQuarter
    JSR BattleCD_HalfSinMul
    STA.w !Battle_FxRotInY
    PLA
    JSR BattleCD_HalfSinMul
    STA.w !Battle_FxRotInX
    LDA.w !Battle_FxObjDepth,X
    STA.w !Battle_FxRotInZ
    LDA.w !Battle_FxObjAngleX,X
    STA.b !BattleCD_RotAngleX
    LDA.w !Battle_FxObjAngleY,X
    STA.b !BattleCD_RotAngleY
    LDA.w !Battle_FxObjAngleZ,X
    STA.b !BattleCD_RotAngleZ
    LDA.w !Battle_FxObjScale,X
    STA.b !BattleCD_FxScale
    JSR BattleCD_Rotate3d
    PLX
    RTS

; $CD:28D2 — BattleCD_FxEllipseTriangle (128 bytes, $28D2–$2951)
; The object's triangle from its flat ring: for each vertex k (radius
; !Battle_FxObjUnkDA/DC/DE, phase !Battle_FxObjPhaseA/B/C), y =
; !Battle_FxObjCentreY + cos(phase) / 2 * radius / 256 * |sin(squash
; y)| / 256 and x = !Battle_FxObjCentreX + the same with sin(phase) and
; squash x (BattleCD_HalfSinMul2, with !Battle_FxObjSquashY/X in DP
; $45), into !Battle_FxTriX0-Y2.
; Callers (1 JSR site): BattleCD_FxOpStepEllipse ($CD:277D).
; Entry: M=1, X=1 (BattleCD_HalfSinMul2's 8-bit index), DP=0, DB=$7E; X
;        = the object
; Exit:  M=1, X=1; A = the third point's x; X unchanged; Y = the last
;        phase; DP $45, $47, $49 written
BattleCD_FxEllipseTriangle:
    LDA.w !Battle_FxObjSquashY,X
    STA.b !BattleCD_Tmp45
    LDA.w !Battle_FxObjUnkDA,X
    STA.b !BattleCD_Tmp47
    LDA.w !Battle_FxObjPhaseA,X
    CLC
    ADC.b #!Battle_AngleQuarter
    JSR BattleCD_HalfSinMul2
    CLC
    ADC.w !Battle_FxObjCentreY,X
    STA.w !Battle_FxTriY0,X
    LDA.w !Battle_FxObjUnkDC,X
    STA.b !BattleCD_Tmp47
    LDA.w !Battle_FxObjPhaseB,X
    CLC
    ADC.b #!Battle_AngleQuarter
    JSR BattleCD_HalfSinMul2
    CLC
    ADC.w !Battle_FxObjCentreY,X
    STA.w !Battle_FxTriY1,X
    LDA.w !Battle_FxObjUnkDE,X
    STA.b !BattleCD_Tmp47
    LDA.w !Battle_FxObjPhaseC,X
    CLC
    ADC.b #!Battle_AngleQuarter
    JSR BattleCD_HalfSinMul2
    CLC
    ADC.w !Battle_FxObjCentreY,X
    STA.w !Battle_FxTriY2,X
    LDA.w !Battle_FxObjSquashX,X
    STA.b !BattleCD_Tmp45
    LDA.w !Battle_FxObjUnkDA,X
    STA.b !BattleCD_Tmp47
    LDA.w !Battle_FxObjPhaseA,X
    JSR BattleCD_HalfSinMul2
    CLC
    ADC.w !Battle_FxObjCentreX,X
    STA.w !Battle_FxTriX0,X
    LDA.w !Battle_FxObjUnkDC,X
    STA.b !BattleCD_Tmp47
    LDA.w !Battle_FxObjPhaseB,X
    JSR BattleCD_HalfSinMul2
    CLC
    ADC.w !Battle_FxObjCentreX,X
    STA.w !Battle_FxTriX1,X
    LDA.w !Battle_FxObjUnkDE,X
    STA.b !BattleCD_Tmp47
    LDA.w !Battle_FxObjPhaseC,X
    JSR BattleCD_HalfSinMul2
    CLC
    ADC.w !Battle_FxObjCentreX,X
    STA.w !Battle_FxTriX2,X
    RTS

; $CD:2952 — BattleCD_FxOp3657 (6 bytes, $2952–$2957)
; Opcode $A1 (value): BattleCD_Unk3657 (not matched) with A = the value.
; Entry: M=1, X=0, DP=0, DB=$7E (what BattleCD_Unk3657 needs is not
;        traced); DP $40 at the operand
; Exit:  as BattleCD_Unk3657 leaves it (not traced)
BattleCD_FxOp3657:
    LDA.b [!BattleCD_FxScriptPtr]
    JSR BattleCD_Unk3657
    RTS

; $CD:2958 — BattleCD_FxOpRegToWork (9 bytes, $2958–$2960)
; Opcode $8C (n, 0-3): the channel's !Battle_FxChanReg word to its work
; word n (!Battle_FxChanWork + 2n), through BattleCD_FxRegToWorkTable
; (JMP (T,X); a larger n would read the handler code as addresses).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand, DP $43 = the channel
; Exit:  as the handlers: M=1, X=0; A = 0 (B = 0); X = n * 2; Y = the
;        channel
BattleCD_FxOpRegToWork:
    LDY.b !BattleFx_RecOfs
    LDA.b [!BattleCD_FxScriptPtr]
    ASL A
    TAX
    JMP (BattleCD_FxRegToWorkTable,X)

; $CD:2961 — BattleCD_FxRegToWorkTable (4 words, $2961–$2968)
; BattleCD_FxOpRegToWork's handler per work word.
BattleCD_FxRegToWorkTable:
    dw BattleCD_FxRegToWork0            ; 0
    dw BattleCD_FxRegToWork1            ; 1
    dw BattleCD_FxRegToWork2            ; 2
    dw BattleCD_FxRegToWork3            ; 3

; $CD:2969 — BattleCD_FxRegToWork0 (12 bytes, $2969–$2974)
; Work word 0 (!Battle_FxChanWork) of channel Y = its !Battle_FxChanReg.
; Callers note: BattleCD_FxRegToWorkTable entry 0 (JMP (T,X) in
;   BattleCD_FxOpRegToWork), as the next three are entries 1-3.
; Entry: M=1, X any, DP any, DB=$7E; Y = the channel
; Exit:  M=1; A = 0 (B = 0); X, Y unchanged
BattleCD_FxRegToWork0:
    REP #$20
    LDA.w !Battle_FxChanReg,Y
    STA.w !Battle_FxChanWork,Y
    TDC
    SEP #$20
    RTS

; $CD:2975 — BattleCD_FxRegToWork1 (12 bytes, $2975–$2980)
; Work word 1 (!Battle_FxChanWork+2) of channel Y = its
; !Battle_FxChanReg.
; Entry: M=1, X any, DP any, DB=$7E; Y = the channel
; Exit:  M=1; A = 0 (B = 0); X, Y unchanged
BattleCD_FxRegToWork1:
    REP #$20
    LDA.w !Battle_FxChanReg,Y
    STA.w !Battle_FxChanWork+2,Y
    TDC
    SEP #$20
    RTS

; $CD:2981 — BattleCD_FxRegToWork2 (12 bytes, $2981–$298C)
; Work word 2 (!Battle_FxChanWork+4) of channel Y = its
; !Battle_FxChanReg.
; Entry: M=1, X any, DP any, DB=$7E; Y = the channel
; Exit:  M=1; A = 0 (B = 0); X, Y unchanged
BattleCD_FxRegToWork2:
    REP #$20
    LDA.w !Battle_FxChanReg,Y
    STA.w !Battle_FxChanWork+4,Y
    TDC
    SEP #$20
    RTS

; $CD:298D — BattleCD_FxRegToWork3 (12 bytes, $298D–$2998)
; Work word 3 (!Battle_FxChanWork+6) of channel Y = its
; !Battle_FxChanReg.
; Entry: M=1, X any, DP any, DB=$7E; Y = the channel
; Exit:  M=1; A = 0 (B = 0); X, Y unchanged
BattleCD_FxRegToWork3:
    REP #$20
    LDA.w !Battle_FxChanReg,Y
    STA.w !Battle_FxChanWork+6,Y
    TDC
    SEP #$20
    RTS

; $CD:2999 — BattleCD_FxOpWorkToReg (9 bytes, $2999–$29A1)
; Opcode $8D (n, 0-3): the channel's work word n to its
; !Battle_FxChanReg, through BattleCD_FxWorkToRegTable (JMP (T,X)).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand, DP $43 = the channel
; Exit:  as the handlers: M=1, X=0; A = 0 (B = 0); X = n * 2; Y = the
;        channel
BattleCD_FxOpWorkToReg:
    LDY.b !BattleFx_RecOfs
    LDA.b [!BattleCD_FxScriptPtr]
    ASL A
    TAX
    JMP (BattleCD_FxWorkToRegTable,X)

; $CD:29A2 — BattleCD_FxWorkToRegTable (4 words, $29A2–$29A9)
; BattleCD_FxOpWorkToReg's handler per work word.
BattleCD_FxWorkToRegTable:
    dw BattleCD_FxWork0ToReg            ; 0
    dw BattleCD_FxWork1ToReg            ; 1
    dw BattleCD_FxWork2ToReg            ; 2
    dw BattleCD_FxWork3ToReg            ; 3

; $CD:29AA — BattleCD_FxWork0ToReg (12 bytes, $29AA–$29B5)
; !Battle_FxChanReg of channel Y = its work word 0 (!Battle_FxChanWork).
; Callers note: BattleCD_FxWorkToRegTable entry 0 (JMP (T,X) in
;   BattleCD_FxOpWorkToReg), as the next three are entries 1-3.
; Entry: M=1, X any, DP any, DB=$7E; Y = the channel
; Exit:  M=1; A = 0 (B = 0); X, Y unchanged
BattleCD_FxWork0ToReg:
    REP #$20
    LDA.w !Battle_FxChanWork,Y
    STA.w !Battle_FxChanReg,Y
    TDC
    SEP #$20
    RTS

; $CD:29B6 — BattleCD_FxWork1ToReg (12 bytes, $29B6–$29C1)
; !Battle_FxChanReg of channel Y = its work word 1 (!Battle_FxChanWork+2).
; Entry: M=1, X any, DP any, DB=$7E; Y = the channel
; Exit:  M=1; A = 0 (B = 0); X, Y unchanged
BattleCD_FxWork1ToReg:
    REP #$20
    LDA.w !Battle_FxChanWork+2,Y
    STA.w !Battle_FxChanReg,Y
    TDC
    SEP #$20
    RTS

; $CD:29C2 — BattleCD_FxWork2ToReg (12 bytes, $29C2–$29CD)
; !Battle_FxChanReg of channel Y = its work word 2 (!Battle_FxChanWork+4).
; Entry: M=1, X any, DP any, DB=$7E; Y = the channel
; Exit:  M=1; A = 0 (B = 0); X, Y unchanged
BattleCD_FxWork2ToReg:
    REP #$20
    LDA.w !Battle_FxChanWork+4,Y
    STA.w !Battle_FxChanReg,Y
    TDC
    SEP #$20
    RTS

; $CD:29CE — BattleCD_FxWork3ToReg (12 bytes, $29CE–$29D9)
; !Battle_FxChanReg of channel Y = its work word 3 (!Battle_FxChanWork+6).
; Entry: M=1, X any, DP any, DB=$7E; Y = the channel
; Exit:  M=1; A = 0 (B = 0); X, Y unchanged
BattleCD_FxWork3ToReg:
    REP #$20
    LDA.w !Battle_FxChanWork+6,Y
    STA.w !Battle_FxChanReg,Y
    TDC
    SEP #$20
    RTS

; $CD:29DA — BattleCD_FxOpFillWindow (9 bytes, $29DA–$29E2)
; Opcode $88 (n): JSL BattleFx_FillWindow with A and X = n * 2: this
; frame's window table all empty (0), first pairs empty (1), second
; pairs empty (2) or first pairs full (3).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0 (the 16-bit TAX); DP $40 at the
;        operand
; Exit:  as BattleFx_FillWindow leaves it: M=1, X=0; A = the fill word's
;        low byte (B its high byte); X = 0; Y's high byte cleared
BattleCD_FxOpFillWindow:
    LDA.b [!BattleCD_FxScriptPtr]
    ASL A
    TAX
    JSL BattleFx_FillWindow
    RTS

; $CD:29E3 — BattleCD_FxOpPalAnim (95 bytes, $29E3–$2A41)
; Opcode $8E (seven bytes b0-b6): fills a palette animation record
; (FieldAnimB, 4-11, picked by b5 AND 7 through BattleCD_FxPalAnimRecs:
; 0 is record 11, 7 is record 4): .Unk0 = b0 AND $F0 (the kind), .Unk6
; = b0 AND $0F, .Unk1 = b1 (the first colour), .Unk2 = b2 (the count),
; .Unk7 = b3, .Unk8 = b4, .Unk3 = b5 AND $F8, .Unk5 = b6 AND $0F (the
; frames between steps), .Unk4 = b6 >> 4.
; Entry: M=1, X=0, DP=0, DB=$7E (the records at $0550 are read .w in
;        bank $7E's low mirror); B = 0 (the 16-bit TAX); DP $40 at the
;        operands
; Exit:  M=1, X=0; A = 0 (B = 0); X = the record's offset; Y = 6; DP $40
;        + 6 (seven operand bytes); DP $45, $47 written
BattleCD_FxOpPalAnim:
    LDY.w #5
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.b !BattleCD_Tmp47
    AND.b #!BattleCD_FxPalAnimPick
    TAX
    LDA.l BattleCD_FxPalAnimRecs,X
    TAX
    LDA.b [!BattleCD_FxScriptPtr]
    STA.b !BattleCD_Tmp45
    AND.b #!BattleFx_HighNibble
    STA.w FieldAnimB[4].Unk0,X
    LDA.b !BattleCD_Tmp45
    AND.b #!BattleFx_LowNibble
    STA.w FieldAnimB[4].Unk6,X
    LDY.w #1
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w FieldAnimB[4].Unk1,X
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w FieldAnimB[4].Unk2,X
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w FieldAnimB[4].Unk7,X
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    STA.w FieldAnimB[4].Unk8,X
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    AND.b #!BattleCD_FxPalAnimStep
    STA.w FieldAnimB[4].Unk3,X
    INY
    LDA.b [!BattleCD_FxScriptPtr],Y
    AND.b #!BattleFx_LowNibble
    STA.w FieldAnimB[4].Unk5,X
    LDA.b [!BattleCD_FxScriptPtr],Y
    LSR A
    LSR A
    LSR A
    LSR A
    STA.w FieldAnimB[4].Unk4,X
    REP #$21
    LDA.b !BattleCD_FxScriptPtr
    ADC.w #6
    STA.b !BattleCD_FxScriptPtr
    TDC
    SEP #$20
    RTS

; $CD:2A42 — BattleCD_FxPalAnimRecs (8 bytes, $2A42–$2A49)
; Offset from palette animation record 4 (FieldAnimB[4]) of the record
; BattleCD_FxOpPalAnim fills, by b5 AND 7: records 11 down to 4.
BattleCD_FxPalAnimRecs:
    db $54,$48,$3C,$30,$24,$18,$0C,$00

; ============================================================
; Sound, scanline wait and math helpers ($CD:3B5F–$CD:3E3A)
; ============================================================
; The math helpers serve the layer effect's script opcodes: an 8-bit
; sine scale (BattleCD_SinMul and its relatives, on the 256-entry
; |sin| table !BattleRom_AbsSine in bank $CE: one turn is 256
; steps, 255 stands for 1), a 3D rotation built on them
; (BattleCD_Rotate3d), and a 16-bit division and an 8 x 16
; multiplication on DP $23-$29.

org $CD3B5F
; $CD:3B5F — BattleCD_PlayPendingSfx (18 bytes, $3B5F–$3B70)
; Plays the sound a script opcode left pending: when
; !Battle_SfxPending is set, clears it and sends
; !Battle_SfxPendingId with X = !Battle_SfxPendingArg through
; BattleCD_ApuCmd18 (tail jump).
; Callers (1 JSR site): BattleCD_FrameTick ($CD:04AF).
; Entry: M=1, X=0, DP any, DB=$7E
; Exit:  M=1, X=0. Nothing pending: A = 0, X and Y unchanged. Else as
;        BattleCD_ApuCmd18 leaves it: A = !Battle_SfxPendingArg's low
;        byte, X = !Battle_SfxPendingArg, Y unchanged;
;        !Battle_SfxPending = 0
BattleCD_PlayPendingSfx:
    LDA.w !Battle_SfxPending
    BEQ .done
    STZ.w !Battle_SfxPending
    LDA.w !Battle_SfxPendingId
    LDX.w !Battle_SfxPendingArg
    JMP BattleCD_ApuCmd18
.done:
    RTS

; $CD:3B71 — BattleCD_ApuCmd18 (17 bytes, $3B71–$3B81)
; Sends APU command !Sfx_CmdUnk18 (Audio_ProcessEntry) with
; !Sfx_Param1 = A and !Sfx_Param2 = X's low byte: a sound, probably
; (the callers pass the dissolve's and the wipe's sounds and the
; script opcodes' sound ids; X is a screen position or
; !BattleCD_SfxArgCentre, so the pan, probably).
; Callers (4 sites: 3 JSR, 1 JMP): BattleCD_EnemyDissolve (JSR $CD:009D), BattleCD_ShowMessage (JSR
;   $CD:01CE), BattleCD_StartOpenWipe (JSR $CD:0502) and BattleCD_PlayPendingSfx (JMP $CD:3B6D).
; Entry: M=1, X any, DP any, DB=$7E; A = the first argument, X's low
;        byte the second
; Exit:  M=1; A = X's low byte (TXA at 8 bits; B unchanged); X, Y
;        unchanged (Audio_ProcessEntry keeps A, X, Y, P, DP and DB)
BattleCD_ApuCmd18:
    STA.w !Sfx_Param1
    LDA.b #!Sfx_CmdUnk18
    STA.w !Sfx_Command
    TXA
    STA.w !Sfx_Param2
    JSL Audio_ProcessEntry
    RTS

; $CD:3B82 — BattleCD_WaitScanline (41 bytes, $3B82–$3BAA)
; Busy-waits for scanline A: past the vertical blank (HVBJOY bit 7),
; then at the end of each H-blank latches the counters (SLHV, STAT78
; resets the read order) and reads OPVCT's low byte, until it is at
; least A. BattleCD_NmiMain calls it with !BattleCD_NmiWaitLine while
; an action runs, and script opcode $C1 (BattleCD_FxOpWaitLine) with
; its operand; why they wait is not traced.
; Callers (2 sites: 1 JSR, 1 JMP): BattleCD_NmiMain (JSR $CD:09AC) and BattleCD_FxOpWaitLine (JMP
;   $CD:1D95).
; Entry: M=1, X any, DP=0, DB any (the registers are read long); A =
;        the line (0-255; the counter's high bit is not read)
; Exit:  M=1; A = the line reached (low byte); X, Y unchanged; DP $45 =
;        the line asked for; C=1
BattleCD_WaitScanline:
    STA.b !BattleCD_Tmp45
.vblank:
    LDA.l HVBJOY
    BMI .vblank
.hblank:
    LDA.l HVBJOY
    AND.b #!HVBJOY_HBlank
    BEQ .hblank
.line:
    LDA.l HVBJOY
    AND.b #!HVBJOY_HBlank
    BNE .line
    LDA.l SLHV
    LDA.l STAT78
    LDA.l OPVCT
    CMP.b !BattleCD_Tmp45
    BCC .line
    RTS

; $CD:3BAB — BattleCD_Div16 (41 bytes, $3BAB–$3BD3)
; 16-bit unsigned division by shift and subtract: !BattleCD_MathOut
; = !BattleCD_MathA / !BattleCD_MathB, !BattleCD_MathOutHi the
; remainder. Either operand 0 gives 0 and 0.
; Callers (2 JSR sites): BattleCD_FxOpTriCentre ($CD:234F, $CD:2361).
; Entry: M=0 (16-bit LDA/ROL/SBC), X=0 (the 16-bit LDX), DP=0, DB any;
;        !BattleCD_MathA (DP $23) the dividend, !BattleCD_MathB (DP $25)
;        the divisor
; Exit:  M=0, X=0; DP $27 the quotient, DP $29 the remainder; DP $23
;        shifted out (clobbered); A = the remainder (0 when an operand
;        is 0); X = 0, or unchanged when an operand is 0; Y unchanged
BattleCD_Div16:
    STZ.b !BattleCD_MathOut
    STZ.b !BattleCD_MathOutHi
    LDA.b !BattleCD_MathA
    BEQ .done
    LDA.b !BattleCD_MathB
    BEQ .done
    LDX.w #!BattleCD_Div16Bits
.bit:
    ROL.b !BattleCD_MathA
    ROL.b !BattleCD_MathOutHi
    SEC
    LDA.b !BattleCD_MathOutHi
    SBC.b !BattleCD_MathB
    STA.b !BattleCD_MathOutHi
    BCS .fits
    LDA.b !BattleCD_MathOutHi
    ADC.b !BattleCD_MathB
    STA.b !BattleCD_MathOutHi
    CLC
.fits:
    ROL.b !BattleCD_MathOut
    DEX
    BNE .bit
.done:
    RTS

; $CD:3BD4 — BattleCD_Mul8x16 (41 bytes, $3BD4–$3BFC)
; 8 x 16-bit unsigned multiplication on the CPU's multiplier: the
; 24-bit DP $27-$29 = DP $23 (a byte) * the word at DP $25, as $23 *
; $25 plus $23 * $26 shifted left 8. Quirk: the second WRMPYB store is
; 16-bit, so it also writes DP $27's old byte to WRDIVL (harmless: no
; division follows).
; Callers (5 JSR sites): BattleCD_FxOpTriCentre ($CD:22C3, $CD:22D7, $CD:22FC, $CD:2310, $CD:2377).
; Entry: M=1, X=0 (16-bit TAX/STX), DP=0, DB any (the registers are
;        accessed long); DP $23 the byte, DP $25-$26 the word
; Exit:  M=1, X=0; DP $27-$29 the product; A = 0 (B = 0, TDC); X = $23
;        * $25 (the low partial product); Y unchanged
BattleCD_Mul8x16:
    LDA.b !BattleCD_MathA
    STA.l WRMPYA
    LDA.b !BattleCD_MathB
    STA.l WRMPYB
    STZ.b !BattleCD_MathOutHi
    REP #$21
    LDA.l RDMPYL
    TAX
    LDA.b !BattleCD_MathB+1
    STA.l WRMPYB
    STX.b !BattleCD_MathOut
    LDA.b !BattleCD_MathOut+1
    ADC.l RDMPYL
    STA.b !BattleCD_MathOut+1
    TDC
    SEP #$20
    RTS

; $CD:3BFD — BattleCD_CosMul (3 bytes, $3BFD–$3BFF)
; A = Y * cos(A) / 256: adds a quarter turn ($40) and falls into
; BattleCD_SinMul ($3C00), which gives A = Y * sin(A) / 256 with the
; sine from !BattleRom_AbsSine (255 for 1; table index bit 7 =
; the negative half). The magnitudes are multiplied on WRMPYA/WRMPYB
; and the product's high byte (RDMPYH) is taken, then negated when
; exactly one of sin and Y is negative (so the result is rounded
; toward 0).
; Sub-entry: BattleCD_SinMul.
; Callers (6 JSR sites): BattleCD_FxOpWedge ($CD:1952, $CD:1960), BattleCD_FxCircleStep ($CD:1CFD,
;   $CD:1D15) and BattleCD_FxOpBeamQuad ($CD:247B, $CD:2489).
; Callers of BattleCD_SinMul (7 JSR sites): BattleCD_FxOpWedge ($CD:1959, $CD:1967),
;   BattleCD_SinMul45 ($CD:1BC6), BattleCD_FxCircleStep ($CD:1D09, $CD:1D33) and
;   BattleCD_FxOpBeamQuad ($CD:2482, $CD:2490).
; Entry: M=1, X=1 (the 8-bit TAX: the table index), DP any, DB any (the
;        registers and the table are read long); A = the angle (256 per
;        turn), Y = the factor (signed byte)
; Exit:  M=1, X=1; A = the signed product; X = the angle used (+ $40
;        for BattleCD_CosMul); Y unchanged; N and Z from A
BattleCD_CosMul:
    CLC
    ADC.b #!Battle_AngleQuarter
BattleCD_SinMul:                        ; header: see BattleCD_CosMul
    TAX
    BPL .sin_positive
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    TYA
    BPL .negate_product
    EOR.b #!Battle_Invert8
    INC A
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    RTS
.negate_product:
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    EOR.b #!Battle_Invert8
    INC A
    RTS
.sin_positive:
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    TYA
    BPL .positive
    EOR.b #!Battle_Invert8
    INC A
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    EOR.b #!Battle_Invert8
    INC A
    RTS
.positive:
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    RTS

; $CD:3C55 — BattleCD_CosMulStart (3 bytes, $3C55–$3C57)
; The first half of BattleCD_CosMul / BattleCD_SinMul for
; BattleCD_Rotate3d: adds a quarter turn and falls into
; BattleCD_SinMulStart ($3C58), which starts |sin(A)| * |Y| on the
; multiplier and returns C=1 when the product is to be negated. The
; caller reads RDMPYH itself.
; Sub-entry: BattleCD_SinMulStart.
; Callers (6 JSR sites): BattleCD_Rotate3d ($CD:3C94, $CD:3CDB, $CD:3D05, $CD:3D2C, $CD:3D56,
;   $CD:3D7D).
; Callers of BattleCD_SinMulStart (6 JSR sites): BattleCD_Rotate3d ($CD:3CA7, $CD:3CC8, $CD:3CF2,
;   $CD:3D19, $CD:3D43, $CD:3D6A).
; Entry: M=1, X=1 (the 8-bit TAX), DP any, DB any (long accesses); A =
;        the angle, Y = the factor (signed byte)
; Exit:  M=1, X=1; C=1: negate the product (exactly one of sin and Y is
;        negative), C=0: keep it; A = |Y|; X = the angle used; Y
;        unchanged; the product is in RDMPYL/RDMPYH 8 cycles later
BattleCD_CosMulStart:
    CLC
    ADC.b #!Battle_AngleQuarter
BattleCD_SinMulStart:                   ; header: see BattleCD_CosMulStart
    TAX
    BPL .sin_positive
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    TYA
    BPL .negate_product
    EOR.b #!Battle_Invert8
    INC A
    STA.l WRMPYB
    CLC
    RTS
.negate_product:
    STA.l WRMPYB
    SEC
    RTS
.sin_positive:
    LDA.l !BattleRom_AbsSine,X
    STA.l WRMPYA
    TYA
    BPL .positive
    EOR.b #!Battle_Invert8
    INC A
    STA.l WRMPYB
    SEC
    RTS
.positive:
    STA.l WRMPYB
    CLC
    RTS

; $CD:3C8F — BattleCD_Rotate3d (257 bytes, $3C8F–$3D8F)
; Rotates the point !Battle_FxRotInX/Y/Z (signed bytes) into
; !Battle_FxRotOutX/Y/Z: first by the angle in DP $4B about the y axis
; (x' = cos*x + sin*z, z' = cos*z - sin*x), then by DP $49 about the x
; axis (y'' = cos*y - sin*z', z'' = cos*z' + sin*y), last by DP $4D
; about the z axis (y''' = cos*y'' + sin*x', x'' = cos*x' - sin*y'').
; Each product is BattleCD_SinMulStart / BattleCD_CosMulStart's high
; byte, so sin and cos are scaled by 255/256, and the sums wrap at 8
; bits. The second product of the last two steps reuses Y, which still
; holds the coordinate before the step (the old y, then the old y'').
; Callers (2 JSR sites): BattleCD_FxRotateVertex ($CD:1F35) and BattleCD_FxRingVertex ($CD:28CD).
; Entry: M=1, X=1 (the 8-bit LDY of the coordinates and the callees'
;        8-bit TAX), DP=0, DB=$7E; DP $49, $4B, $4D the angles about x,
;        y and z
; Exit:  M=1, X=1; !Battle_FxRotOutX/Y/Z written; A = !Battle_FxRotOutX;
;        X = DP $4D + $40; Y = x' (!Battle_FxRotOutX before the last
;        step); DP $47 written
BattleCD_Rotate3d:
    LDY.w !Battle_FxRotInX
    LDA.b !BattleCD_RotAngleY
    JSR BattleCD_CosMulStart
    LDA.l RDMPYH
    BCC .y1
    EOR.b #!Battle_Invert8
    INC A
.y1:
    STA.b !BattleCD_Tmp47
    LDY.w !Battle_FxRotInZ
    LDA.b !BattleCD_RotAngleY
    JSR BattleCD_SinMulStart
    LDA.l RDMPYH
    BCC .y2
    EOR.b #!Battle_Invert8
    INC A
    CLC
.y2:
    ADC.b !BattleCD_Tmp47
    STA.w !Battle_FxRotOutX
    LDA.w !Battle_FxRotInY
    STA.w !Battle_FxRotOutY
    LDA.w !Battle_FxRotInX
    EOR.b #!Battle_Invert8
    INC A
    TAY
    LDA.b !BattleCD_RotAngleY
    JSR BattleCD_SinMulStart
    LDA.l RDMPYH
    BCC .y3
    EOR.b #!Battle_Invert8
    INC A
.y3:
    STA.b !BattleCD_Tmp47
    LDY.w !Battle_FxRotInZ
    LDA.b !BattleCD_RotAngleY
    JSR BattleCD_CosMulStart
    LDA.l RDMPYH
    BCC .y4
    EOR.b #!Battle_Invert8
    INC A
    CLC
.y4:
    ADC.b !BattleCD_Tmp47
    STA.w !Battle_FxRotOutZ
    LDY.w !Battle_FxRotOutZ
    LDA.b !BattleCD_RotAngleX
    JSR BattleCD_SinMulStart
    LDA.l RDMPYH
    BCC .x1
    EOR.b #!Battle_Invert8
    INC A
.x1:
    STA.b !BattleCD_Tmp47
    LDY.w !Battle_FxRotOutY
    LDA.b !BattleCD_RotAngleX
    JSR BattleCD_CosMulStart
    LDA.l RDMPYH
    BCC .x2
    EOR.b #!Battle_Invert8
    INC A
.x2:
    SEC
    SBC.b !BattleCD_Tmp47
    STA.w !Battle_FxRotOutY
    LDA.b !BattleCD_RotAngleX
    JSR BattleCD_SinMulStart            ; Y = the old y
    LDA.l RDMPYH
    BCC .x3
    EOR.b #!Battle_Invert8
    INC A
.x3:
    STA.b !BattleCD_Tmp47
    LDY.w !Battle_FxRotOutZ
    LDA.b !BattleCD_RotAngleX
    JSR BattleCD_CosMulStart
    LDA.l RDMPYH
    BCC .x4
    EOR.b #!Battle_Invert8
    INC A
    CLC
.x4:
    ADC.b !BattleCD_Tmp47
    STA.w !Battle_FxRotOutZ
    LDY.w !Battle_FxRotOutX
    LDA.b !BattleCD_RotAngleZ
    JSR BattleCD_SinMulStart
    LDA.l RDMPYH
    BCC .z1
    EOR.b #!Battle_Invert8
    INC A
.z1:
    STA.b !BattleCD_Tmp47
    LDY.w !Battle_FxRotOutY
    LDA.b !BattleCD_RotAngleZ
    JSR BattleCD_CosMulStart
    LDA.l RDMPYH
    BCC .z2
    EOR.b #!Battle_Invert8
    INC A
    CLC
.z2:
    ADC.b !BattleCD_Tmp47
    STA.w !Battle_FxRotOutY
    LDA.b !BattleCD_RotAngleZ
    JSR BattleCD_SinMulStart            ; Y = the old y''
    LDA.l RDMPYH
    BCC .z3
    EOR.b #!Battle_Invert8
    INC A
.z3:
    STA.b !BattleCD_Tmp47
    LDY.w !Battle_FxRotOutX
    LDA.b !BattleCD_RotAngleZ
    JSR BattleCD_CosMulStart
    LDA.l RDMPYH
    BCC .z4
    EOR.b #!Battle_Invert8
    INC A
.z4:
    SEC
    SBC.b !BattleCD_Tmp47
    STA.w !Battle_FxRotOutX
    RTS

; $CD:3D90 — BattleCD_HalfSinMul (51 bytes, $3D90–$3DC2)
; A = sin(A) / 2 * DP $47 / 256: the |sin| entry halved (LSR) times the
; unsigned byte at DP $47 on the multiplier, the high byte, negated
; for angles $80-$FF.
; Callers (2 JSR sites): BattleCD_FxRingVertex ($CD:28A6, $CD:28AD).
; Entry: M=1, X=1 (8-bit PHX/TAX/PLX), DP=0, DB any (long accesses); A
;        = the angle, DP $47 = the factor (unsigned)
; Exit:  M=1, X=1; A = the signed result; X, Y unchanged
BattleCD_HalfSinMul:
    PHX
    TAX
    BPL .positive
    LDA.l !BattleRom_AbsSine,X
    LSR A
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp47
    STA.l WRMPYB
    PLX
    NOP
    LDA.l RDMPYH
    EOR.b #!Battle_Invert8
    INC A
    RTS
.positive:
    LDA.l !BattleRom_AbsSine,X
    LSR A
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp47
    STA.l WRMPYB
    PLX
    NOP
    LDA.l RDMPYH
    RTS

; $CD:3DC3 — BattleCD_HalfSinMul2 (94 bytes, $3DC3–$3E20)
; As BattleCD_HalfSinMul, then the result's magnitude times |sin(DP
; $45)| (DP $49) / 256: A = sin(A) / 2 * DP $47 / 256 * |sin(DP $45)| /
; 256, negated for angles A of $80-$FF (the sign of sin(DP $45) is
; not used).
; Callers (6 JSR sites): BattleCD_FxEllipseTriangle ($CD:28E2, $CD:28F7, $CD:290C, $CD:2923,
;   $CD:2935, $CD:2947).
; Entry: M=1, X=1 (8-bit PHX/TAX/TYX/PLX), DP=0, DB any (long
;        accesses); A = the angle, DP $45 = the second angle, DP $47 =
;        the factor (unsigned)
; Exit:  M=1, X=1; A = the signed result; X unchanged; Y = the angle
;        (A on entry); DP $49 = |sin(DP $45)|
BattleCD_HalfSinMul2:
    PHX
    TAY
    LDA.b !BattleCD_Tmp45
    TAX
    LDA.l !BattleRom_AbsSine,X
    STA.b !BattleCD_Tmp49
    TYX
    BPL .positive
    LDA.l !BattleRom_AbsSine,X
    LSR A
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp47
    STA.l WRMPYB
    PLX
    LDA.l RDMPYH
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp49
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    EOR.b #!Battle_Invert8
    INC A
    RTS
.positive:
    LDA.l !BattleRom_AbsSine,X
    LSR A
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp47
    STA.l WRMPYB
    PLX
    NOP
    LDA.l RDMPYH
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp49
    STA.l WRMPYB
    NOP
    NOP
    NOP
    LDA.l RDMPYH
    RTS

; $CD:3E21 — BattleCD_Mul8Unused (26 bytes, $3E21–$3E3A)
; DP $49 = DP $45 * DP $47 (8 x 8-bit, on the multiplier). Nothing
; calls it (no site found by tools/xref.py, and the code before it
; ends in RTS). Quirk: REP #$20 twice.
; Entry: M=1, X any, DP=0, DB any (long accesses); DP $45 and DP $47
;        the factors
; Exit:  M=1; DP $49-$4A = the product; A = 0 (B = 0, TDC); X, Y
;        unchanged
BattleCD_Mul8Unused:
    LDA.b !BattleCD_Tmp45
    STA.l WRMPYA
    LDA.b !BattleCD_Tmp47
    STA.l WRMPYB
    REP #$20
    REP #$20
    LDA.l RDMPYL
    STA.b !BattleCD_Tmp49
    TDC
    SEP #$20
    RTS

; ============================================================
; Frame waits and VRAM uploads ($CD:3E3B–$CD:3FFF)
; ============================================================

; $CD:3E3B — BattleCD_WaitFrames (9 bytes, $3E3B–$3E43)
; Waits A frames: BattleCD_WaitFrameRefresh A times (A = 0 waits 256).
; Callers (7 sites: 6 JSR, 1 JMP): BattleCD_EnemyDissolveFx (JSR $CD:00C1), BattleCD_ShowMessage
;   (JSR $CD:01E7), BattleCD_ShowScriptMessage (JSR $CD:02B5), BattleCD_ApuCmd81 (JMP $CD:03B1),
;   BattleCD_EndLayerFx (JSR $CD:0494) and BattleCD_LoadLayerFx (JSR $CD:0F09, JSR $CD:0F25).
; Entry: M=1, X=0, DP=0, DB=$7E (what BattleCD_WaitFrameRefresh needs);
;        A = the frame count
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 0, Z=1; X, Y clobbered (as
;        BattleCD_WaitFrameRefresh leaves them)
BattleCD_WaitFrames:
    PHA
    JSR BattleCD_WaitFrameRefresh
    PLA
    DEC A
    BNE BattleCD_WaitFrames
    RTS

; $CD:3E44 — BattleCD_PauseWait (49 bytes, $3E44–$3E74)
; Holds the battle while !Battle_Paused is set: APU command
; !BattleCD_ApuCmdPause with argument !BattleCD_ApuCmdPause (and
; !Field_FadeBusy set to the same value), then frame by frame
; (!BattleFx_FrameWait set, waited back to 0) until !Battle_Paused is
; cleared, then !Field_FadeBusy = 0 and the command again with
; argument 0 (the music paused and resumed, probably). Returns at once
; when not paused.
; Callers (3 JSR sites): BattleCD_IdleTick ($CD:04A6), BattleCD_FrameTick ($CD:04B2) and
;   BattleCD_WaitFrame ($CD:3E81).
; Entry: M=1, X any, DP any, DB=$7E
; Exit:  M=1; A = 0 when not paused, else !BattleCD_ApuCmdPause; X, Y
;        unchanged (Audio_ProcessEntry keeps them)
BattleCD_PauseWait:
    LDA.w !Battle_Paused
    BEQ .done
    LDA.b #!BattleCD_ApuCmdPause
    STA.w !Sfx_Command
    STA.w !Sfx_Param1
    STA.w !Field_FadeBusy
    JSL Audio_ProcessEntry
.frame:
    INC.w !BattleFx_FrameWait
.wait:
    LDA.w !BattleFx_FrameWait
    BNE .wait
    LDA.w !Battle_Paused
    BNE .frame
    STZ.w !Field_FadeBusy
    LDA.b #!BattleCD_ApuCmdPause
    STA.w !Sfx_Command
    STZ.w !Sfx_Param1
    JSL Audio_ProcessEntry
.done:
    RTS

; $CD:3E75 — BattleCD_WaitFrameRefresh (8 bytes, $3E75–$3E7C)
; One frame (BattleCD_WaitFrame), then the battle menu's refresh
; (BankC1_VecRefreshMenu: BattleMenu_RefreshIfDirtyL).
; Callers (16 JSR sites): BattleCD_EnemyDissolve ($CD:0046), BattleCD_ShowMessage ($CD:01EF),
;   BattleCD_Wait16Frames ($CD:020D), BattleCD_ShowMessageTimed ($CD:0231),
;   BattleCD_ShowScriptMessage ($CD:02C7), BattleCD_EndLayerFx ($CD:048C, $CD:04A2),
;   BattleCD_WaitLayerFxIdle ($CD:0DFF), BattleCD_RunLayerFx ($CD:0E19), BattleCD_LoadLayerFx
;   ($CD:0F33, $CD:0F3F), BattleCD_LoadFxGfx4 ($CD:132E), BattleCD_WaitFrames ($CD:3E3C) and
;   BattleCD_QueueVramDma ($CD:3EE0, $CD:3F1D, $CD:3F67).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A, X, Y clobbered (A = 0 when the menu
;        was not dirty)
BattleCD_WaitFrameRefresh:
    JSR BattleCD_WaitFrame
    JSL BankC1_VecRefreshMenu
    RTS

; $CD:3E7D — BattleCD_WaitFrame (17 bytes, $3E7D–$3E8D)
; Waits for the next frame: !BattleFx_FrameWait + 1, then
; BattleCD_PauseWait until it is back to 0 (the bank-$D1 NMI handler
; clears it, probably: no matched code does), then the text step
; (BattleCD_StepText).
; Callers (17 JSR sites): BattleCD_ShowText ($CD:0286, $CD:0289), BattleCD_ExitBattle ($CD:03DA,
;   $CD:03EB, $CD:0415), BattleCD_StartOpenWipe ($CD:0505, $CD:0512), BattleCD_StartCloseWipe
;   ($CD:051B, $CD:0526), BattleCD_RunEndFx ($CD:0D74), BattleCD_LayerFx87 ($CD:0D99, $CD:0DA8),
;   BattleCD_LayerFx84 ($CD:0DB4, $CD:0DCC, $CD:0DD8, $CD:0DDB) and BattleCD_WaitFrameRefresh
;   ($CD:3E75).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0, DP=0, DB=$7E; A unchanged (PHA/PLA); X, Y clobbered
;        when BattleCD_StepText steps the text, else unchanged
BattleCD_WaitFrame:
    PHA
    INC.w !BattleFx_FrameWait
.wait:
    JSR BattleCD_PauseWait
    LDA.w !BattleFx_FrameWait
    BNE .wait
    JSR BattleCD_StepText
    PLA
    RTS

; $CD:3E8E — BattleCD_DmaToVram (38 bytes, $3E8E–$3EB3)
; DMA channel 7 from A:X to VRAM word address Y, DP $45 bytes (mode 1:
; VMDATAL/VMDATAH), with DB = $00 inside and put back. VMAIN is not
; set here.
; Callers (3 sites: 1 JSR, 2 JMP): BattleCD_NmiUploadText (JMP $CD:06A4, JMP $CD:06AF) and
;   BattleCD_RunQueuedDma (JSR $CD:3EC7).
; Entry: M=1, X=0 (16-bit STY/STX/LDX), DP=0, DB any; A:X = the source,
;        Y = the VRAM word address, DP $45 = the byte count
; Exit:  M=1, X=0, DB as on entry; A = !MDMAEN_Ch7; X = the byte count;
;        Y unchanged
BattleCD_DmaToVram:
    PHB
    PHA
    LDA.b #0
    PHA
    PLB
    PLA
    STY.w VMADDL
    STX.w A1T7L
    STA.w A1B7
    LDA.b #!DMAP_TwoRegs
    STA.w DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD7
    LDX.b !BattleCD_Tmp45
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    PLB
    RTS

; $CD:3EB4 — BattleCD_RunQueuedDma (26 bytes, $3EB4–$3ECD)
; The NMI's half of BattleCD_QueueVramDma: when !Battle_DmaQueueReq is
; set, sends the queued piece (!Battle_DmaQueueSrc / Bank to
; !Battle_DmaQueueVram, !Battle_DmaQueuePiece bytes) through
; BattleCD_DmaToVram and clears the request.
; Callers (2 JSR sites): BattleCD_NmiMain ($CD:089B, $CD:08AC).
; Entry: M=1, X=0, DP=0, DB=$7E (BattleCD_NmiMain sets it first)
; Exit:  M=1, X=0, DB=$7E; nothing queued: A = 0, X, Y unchanged; else
;        A = !MDMAEN_Ch7, X = the piece's size, Y = its VRAM address,
;        DP $45 = the size
BattleCD_RunQueuedDma:
    LDA.w !Battle_DmaQueueReq
    BEQ .done
    LDX.w !Battle_DmaQueuePiece
    STX.b !BattleCD_Tmp45
    LDX.w !Battle_DmaQueueSrc
    LDY.w !Battle_DmaQueueVram
    LDA.w !Battle_DmaQueueBank
    JSR BattleCD_DmaToVram
    STZ.w !Battle_DmaQueueReq
.done:
    RTS

; $CD:3ECE — BattleCD_QueueVramDmaL (4 bytes, $3ECE–$3ED1)
; BattleCD_QueueVramDma for long callers (bank $D1), RTL.
; Callers (2 JSL sites): BattleFx_LoadBgSet ($D1:ED49, $D1:EDC5).
; Entry: as BattleCD_QueueVramDma (M=1, X=0, DP=0, DB=$7E)
; Exit:  as BattleCD_QueueVramDma (RTL)
BattleCD_QueueVramDmaL:
    JSR BattleCD_QueueVramDma
    RTL

; $CD:3ED2 — BattleCD_QueueVramDma (204 bytes, $3ED2–$3F9D)
; Uploads A:X to VRAM word address Y, DP $53 bytes, through the NMI
; (BattleCD_RunQueuedDma), in pieces of at most $1000 bytes while
; !Battle_CgramPending is set and $400 bytes else (re-checked before
; each piece), waiting frames (BattleCD_WaitFrameRefresh) until each
; piece is sent. First waits until an earlier request is done.
; !Battle_DmaQueueBusy is set meanwhile (BattleCD_FrameTick then skips
; its effect work); !Battle_DmaQueueLast marks the last piece. After
; the last piece the source, address and count are still stepped by a
; full piece (unused).
; Callers (6 JSR sites): BattleCD_EnemyDissolveFx ($CD:00F8), BattleCD_EndLayerFx ($CD:0460),
;   BattleCD_LoadLayerFx ($CD:0FDA, $CD:0FFD), BattleCD_LoadFxGfx4 ($CD:1356) and
;   BattleCD_QueueVramDmaL ($CD:3ECE).
; Entry: M=1, X=0, DP=0, DB=$7E; A:X = the source, Y = the VRAM word
;        address, DP $53 = the byte count (a count of 0 is sent as one
;        piece of 0, which DMA takes as $10000 bytes)
; Exit:  M=1, X=0, DP=0, DB=$7E; A = 1 (B = 0); X, Y clobbered;
;        !Battle_DmaQueueBusy = 0
BattleCD_QueueVramDma:
    INC.w !Battle_DmaQueueBusy
    PHX
    PHY
    PHA
    LDX.b !BattleCD_Tmp53
    PHX
.wait_free:
    LDA.w !Battle_DmaQueueReq
    BEQ .start
    JSR BattleCD_WaitFrameRefresh
    BRA .wait_free
.start:
    PLX
    STX.w !Battle_DmaQueueLeft
    PLA
    STA.w !Battle_DmaQueueBank
    PLY
    STY.w !Battle_DmaQueueVram
    PLX
    STX.w !Battle_DmaQueueSrc
    STZ.w !Battle_DmaQueueLast
.piece:
    LDA.w !Battle_CgramPending
    BEQ .small
    REP #$20
    LDA.w !Battle_DmaQueueLeft
    CMP.w #!BattleCD_DmaPieceLarge
    BEQ .large_last
    BCC .large_last
    LDA.w #!BattleCD_DmaPieceLarge
    STA.w !Battle_DmaQueuePiece
    BRA .large_send
.large_last:
    STA.w !Battle_DmaQueuePiece
    INC.w !Battle_DmaQueueLast
.large_send:
    TDC
    SEP #$20
    INC.w !Battle_DmaQueueReq
.large_wait:
    JSR BattleCD_WaitFrameRefresh
    LDA.w !Battle_DmaQueueReq
    BNE .large_wait
    REP #$20
    LDA.w !Battle_DmaQueueSrc
    CLC
    ADC.w #!BattleCD_DmaPieceLarge
    STA.w !Battle_DmaQueueSrc
    LDA.w !Battle_DmaQueueVram
    CLC
    ADC.w #!BattleCD_DmaPieceLarge/2
    STA.w !Battle_DmaQueueVram
    LDA.w !Battle_DmaQueueLeft
    SEC
    SBC.w #!BattleCD_DmaPieceLarge
    STA.w !Battle_DmaQueueLeft
    BRA .next
.small:
    REP #$20
    LDA.w !Battle_DmaQueueLeft
    CMP.w #!BattleCD_DmaPieceSmall
    BEQ .small_last
    BCC .small_last
    LDA.w #!BattleCD_DmaPieceSmall
    STA.w !Battle_DmaQueuePiece
    BRA .small_send
.small_last:
    STA.w !Battle_DmaQueuePiece
    INC.w !Battle_DmaQueueLast
.small_send:
    TDC
    SEP #$20
    INC.w !Battle_DmaQueueReq
.small_wait:
    JSR BattleCD_WaitFrameRefresh
    LDA.w !Battle_DmaQueueReq
    BNE .small_wait
    REP #$20
    LDA.w !Battle_DmaQueueSrc
    CLC
    ADC.w #!BattleCD_DmaPieceSmall
    STA.w !Battle_DmaQueueSrc
    LDA.w !Battle_DmaQueueVram
    CLC
    ADC.w #!BattleCD_DmaPieceSmall/2
    STA.w !Battle_DmaQueueVram
    LDA.w !Battle_DmaQueueLeft
    SEC
    SBC.w #!BattleCD_DmaPieceSmall
    STA.w !Battle_DmaQueueLeft
.next:
    TDC
    SEP #$20
    LDA.w !Battle_DmaQueueLast
    BNE .done
    JMP .piece
.done:
    STZ.w !Battle_DmaQueueBusy
    RTS

; $CD:3F9E — BattleCD_OldBuildLeftovers (98 bytes, $3F9E–$3FFF)
; No code reaches these bytes. $3F9E-$3FE3 (70 bytes) are the last 70
; bytes of BattleCD_QueueVramDma again ($3F58-$3F9D: from the last
; byte of the $400-piece path's STA to the RTS), with the two internal
; addresses $46 higher (JSR $3EBB for $3E75, JMP $3F3E for $3EF8): the
; tail of an older assembly of the bank in which the routine sat $46
; bytes later, probably. Then $FF fill ($3FE4-$3FFE), and
; !BattleRom_DebugSlowMo at $3FFF (0; BattleCD_NmiMain reads it).
BattleCD_OldBuildLeftovers:
    db $CA,$80,$06,$8D,$2C,$CA,$EE,$30,$CA,$7B,$E2,$20,$EE,$26,$CA,$20
    db $BB,$3E,$AD,$26,$CA,$D0,$F8,$C2,$20,$AD,$27,$CA,$18,$69,$00,$04
    db $8D,$27,$CA,$AD,$2A,$CA,$18,$69,$00,$02,$8D,$2A,$CA,$AD,$2E,$CA
    db $38,$E9,$00,$04,$8D,$2E,$CA,$7B,$E2,$20,$AD,$30,$CA,$D0,$03,$4C
    db $3E,$3F,$9C,$11,$CE,$60
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF,$FF
    db $00                              ; $3FFF: !BattleRom_DebugSlowMo
