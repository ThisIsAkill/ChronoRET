; ============================================================
; Bank $CC — battle tables, the battle set-up and the action helpers
; File offset 0x0C0000 (bank $CC = ROM offset $C0000)
;
; $CC:0000-$CC:DFFF is data (item, tech and enemy records, names and
; text, read by banks $C1/$C2/$FD) and stays as ROM bytes. $CC:E000-
; $CC:F382 is battle-engine code, matched below: the set-up steps of
; BattleSys_SceneSetup (Battle_InitScene, Battle_InitSceneGfx), the staged
; VRAM uploads they start (Battle_InitUploadStep, reached through the
; bank-$C1 vector at $C1:000F), the helpers BattleSys_RunAction and
; BattleAct_LoadAttack call by JSL, and the multiply Battle_Mul8CC. From
; $CC:F383 on the bank is data again (the !BattleRom_* tables), left as
; ROM bytes. The code uses the battle's direct-page scratch (DP=0) and
; runs with DB=$7E.
; ============================================================

arch snes.cpu
hirom

org $CCE000
; ============================================================
; Battle set-up: the staged VRAM uploads ($CC:E000–$CC:E2E3)
; ============================================================

; $CC:E000 — Battle_InitUploadStep (558 bytes, $E000–$E22D)
; One stage of the battle's opening VRAM uploads, run once per call while
; !Battle_InitUploadStage is 1-3 (each stage counts it up; 0 and 4 on do
; nothing). Battle_InitSceneGfx sets the stage to 1 and waits until it
; reads 4, so the three stages run on three successive calls from the
; interrupt side. All go through DMA channel 7 (mode !DMAP_TwoRegs to
; VMDATAL; VMAIN is not set here):
;   stage 1: !BattleRom_InitGfxA ($1000 B) to VRAM $5800, then
;            !BattleRom_InitTilesB / C ($40 B each) to $0060 / $0020;
;   stage 2: the status-bar map buffer ($0CC0, $780 B through bank $00)
;            to $7820, !BattleRom_InitTilesD twice to $0160 and $0120,
;            !Battle_InitMapBuf ($1C0 B) to $7B00 and its last row
;            ($40 B) to $7800, then Battle_InitUploadObjTiles;
;   stage 3: !BattleMenu_WindowMap ($180 B through bank $00) to $7A00 and
;            !Battle_ActFrameBuf ($C00 B, with !Battle_InitTileBuf) to
;            $1800.
; The second and later blocks of a stage keep the mode and B-bus address
; of the first. Which layers the VRAM places belong to is not traced.
; Callers note: the JML at $C1:0072 is reached by JSL $C1:000F from the
;   unmatched code at $CD:0AB4, which runs it while $7E:CAD3 is non-zero
;   (DB=$7E there, X 16-bit; probably the battle's NMI handler).
; Callers (1 JML site): BankC1_JmlCCE000 ($C1:0072).
; Entry: M=1 (8-bit A), X any (no index register used), DP=0 assumed (TDC
;        gives the zero bytes written to VMADDL/VMADDH; the caller's DP is
;        not traced), DB=$7E (!Battle_InitUploadStage is absolute; the
;        DMA registers are written long)
; Exit:  RTL; M=1, X, Y, DP and DB unchanged; A clobbered; DMA channel 7
;        registers, VMADDL/H and !Battle_InitUploadStage changed
Battle_InitUploadStep:
    LDA.w !Battle_InitUploadStage
    BNE .stage_1
    RTL
.stage_1:
    DEC A
    BEQ .do_stage_1
    JMP .stage_2
    ; Stage 1.
.do_stage_1:
    LDA.b #!DMAP_TwoRegs
    STA.l DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.l BBAD7
    LDA.b #!BattleRom_InitGfxA&$FF
    STA.l A1T7L
    LDA.b #(!BattleRom_InitGfxA>>8)&$FF
    STA.l A1T7H
    LDA.b #!BattleRom_InitGfxA>>16
    STA.l A1B7
    LDA.b #!Battle_InitGfxABytes&$FF
    STA.l DAS7L
    LDA.b #!Battle_InitGfxABytes>>8
    STA.l DAS7H
    TDC
    STA.l VMADDL
    LDA.b #!Battle_InitGfxAVram>>8
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    ; The next two blocks keep the mode and B-bus target set above.
    LDA.b #!BattleRom_InitTilesB&$FF
    STA.l A1T7L
    LDA.b #(!BattleRom_InitTilesB>>8)&$FF
    STA.l A1T7H
    LDA.b #!BattleRom_InitTilesB>>16
    STA.l A1B7
    LDA.b #!Battle_InitPieceBytes&$FF
    STA.l DAS7L
    LDA.b #!Battle_InitPieceBytes>>8
    STA.l DAS7H
    LDA.b #!Battle_InitTilesBVram&$FF
    STA.l VMADDL
    TDC
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    LDA.b #!BattleRom_InitTilesC&$FF
    STA.l A1T7L
    LDA.b #(!BattleRom_InitTilesC>>8)&$FF
    STA.l A1T7H
    LDA.b #!BattleRom_InitTilesC>>16
    STA.l A1B7
    LDA.b #!Battle_InitPieceBytes&$FF
    STA.l DAS7L
    LDA.b #!Battle_InitPieceBytes>>8
    STA.l DAS7H
    LDA.b #!Battle_InitTilesCVram&$FF
    STA.l VMADDL
    TDC
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    INC.w !Battle_InitUploadStage
    RTL
.stage_2:
    DEC A
    BEQ .do_stage_2
    JMP .stage_3
    ; Stage 2.
.do_stage_2:
    LDA.b #!DMAP_TwoRegs
    STA.l DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.l BBAD7
    LDA.b #BattleUI_StatusTile(0,0)&$FF
    STA.l A1T7L
    LDA.b #(BattleUI_StatusTile(0,0)>>8)&$FF
    STA.l A1T7H
    LDA.b #!Bank00
    STA.l A1B7
    LDA.b #!Battle_InitStatusMapBytes&$FF
    STA.l DAS7L
    LDA.b #!Battle_InitStatusMapBytes>>8
    STA.l DAS7H
    LDA.b #!Battle_InitStatusMapVram&$FF
    STA.l VMADDL
    LDA.b #!Battle_InitStatusMapVram>>8
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    LDA.b #!BattleRom_InitTilesD&$FF
    STA.l A1T7L
    LDA.b #(!BattleRom_InitTilesD>>8)&$FF
    STA.l A1T7H
    LDA.b #!BattleRom_InitTilesD>>16
    STA.l A1B7
    LDA.b #!Battle_InitPieceBytes&$FF
    STA.l DAS7L
    LDA.b #!Battle_InitPieceBytes>>8
    STA.l DAS7H
    LDA.b #!Battle_InitTilesDVram&$FF
    STA.l VMADDL
    LDA.b #!Battle_InitTilesDVram>>8
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    LDA.b #!BattleRom_InitTilesD&$FF
    STA.l A1T7L
    LDA.b #(!BattleRom_InitTilesD>>8)&$FF
    STA.l A1T7H
    LDA.b #!BattleRom_InitTilesD>>16
    STA.l A1B7
    LDA.b #!Battle_InitPieceBytes&$FF
    STA.l DAS7L
    LDA.b #!Battle_InitPieceBytes>>8
    STA.l DAS7H
    LDA.b #!Battle_InitTilesEVram&$FF
    STA.l VMADDL
    LDA.b #!Battle_InitTilesEVram>>8
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    ; !Battle_InitMapBuf: rows 0-6 to $7B00, row 7 to $7800.
    LDA.b #!Battle_InitMapBuf&$FF
    STA.l A1T7L
    LDA.b #(!Battle_InitMapBuf>>8)&$FF
    STA.l A1T7H
    LDA.b #!Bank7E
    STA.l A1B7
    LDA.b #!Battle_InitMapBufHead&$FF
    STA.l DAS7L
    LDA.b #!Battle_InitMapBufHead>>8
    STA.l DAS7H
    TDC
    STA.l VMADDL
    LDA.b #!Battle_InitMapBufVram>>8
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    LDA.b #!Battle_InitMapBufTail&$FF
    STA.l A1T7L
    LDA.b #(!Battle_InitMapBufTail>>8)&$FF
    STA.l A1T7H
    LDA.b #!Bank7E
    STA.l A1B7
    LDA.b #!Battle_InitPieceBytes&$FF
    STA.l DAS7L
    LDA.b #!Battle_InitPieceBytes>>8
    STA.l DAS7H
    TDC
    STA.l VMADDL
    LDA.b #!Battle_InitMapTailVram>>8
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    JSR Battle_InitUploadObjTiles
    INC.w !Battle_InitUploadStage
    RTL
.stage_3:
    DEC A
    BNE .done
    ; Stage 3 (A = stage - 2; anything else past 3 returns at .done).
    LDA.b #!DMAP_TwoRegs
    STA.l DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.l BBAD7
    LDA.b #!BattleMenu_WindowMap&$FF
    STA.l A1T7L
    LDA.b #(!BattleMenu_WindowMap>>8)&$FF
    STA.l A1T7H
    LDA.b #!Bank00
    STA.l A1B7
    LDA.b #!BattleMenu_WindowBytes&$FF
    STA.l DAS7L
    LDA.b #!BattleMenu_WindowBytes>>8
    STA.l DAS7H
    TDC
    STA.l VMADDL
    LDA.b #!Battle_WindowMapVram>>8
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    LDA.b #!DMAP_TwoRegs
    STA.l DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.l BBAD7
    LDA.b #!Battle_ActFrameBuf&$FF
    STA.l A1T7L
    LDA.b #(!Battle_ActFrameBuf>>8)&$FF
    STA.l A1T7H
    LDA.b #!Bank7E
    STA.l A1B7
    LDA.b #!Battle_InitFrameBufBytes&$FF
    STA.l DAS7L
    LDA.b #!Battle_InitFrameBufBytes>>8
    STA.l DAS7H
    LDA.b #!Battle_InitFrameBufVram&$FF
    STA.l VMADDL
    LDA.b #!Battle_InitFrameBufVram>>8
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    INC.w !Battle_InitUploadStage
.done:
    RTL
; $CC:E22E — Battle_InitUploadObjTiles (98 bytes, $E22E–$E28F)
; Sends the first two 64-byte pieces of !BattleRom_ObjTilePieces (the four
; pieces bank $C0's Field_UploadUnk0000 sends) to VRAM $0000 and $0100,
; with the DMA channel 7 mode and target its caller set. It ends at the
; RTS after the second piece: the uploads of the third and fourth pieces
; follow it as unreached code (Battle_InitUploadObjTilesDead).
; Callers (1 JSR site): Battle_InitUploadStep ($CC:E1A9).
; Entry: M=1, X any, DP=0 (TDC as zero), DB any (registers written long);
;        DMAP7/BBAD7 already set (stage 2 of Battle_InitUploadStep)
; Exit:  RTS; M=1, X, Y unchanged; A clobbered; VMADDL/H, A1T7, A1B7, DAS7
;        changed
Battle_InitUploadObjTiles:
    LDA.b #!DMAP_TwoRegs
    STA.l DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.l BBAD7
    LDA.b #!BattleRom_ObjTilePieces&$FF
    STA.l A1T7L
    LDA.b #(!BattleRom_ObjTilePieces>>8)&$FF
    STA.l A1T7H
    LDA.b #!BattleRom_ObjTilePieces>>16
    STA.l A1B7
    LDA.b #!Battle_InitPieceBytes&$FF
    STA.l DAS7L
    LDA.b #!Battle_InitPieceBytes>>8
    STA.l DAS7H
    TDC
    STA.l VMADDL
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    LDA.b #!BattleRom_ObjTilePieces+$40&$FF
    STA.l A1T7L
    LDA.b #(!BattleRom_ObjTilePieces+$40>>8)&$FF
    STA.l A1T7H
    LDA.b #!Battle_InitPieceBytes&$FF
    STA.l DAS7L
    LDA.b #!Battle_InitPieceBytes>>8
    STA.l DAS7H
    TDC
    STA.l VMADDL
    INC A
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    RTS
; $CC:E290 — Battle_InitUploadObjTilesDead (84 bytes, $E290–$E2E3)
; Never reached (no call or jump to it was found; Battle_InitUploadObjTiles
; returns just before it): the uploads of pieces 3 and 4 of
; !BattleRom_ObjTilePieces to VRAM $0060 and $0160 (bank $C0 sends them to
; $0030 and $0130), and an RTS. Kept as found.
; Entry: (never entered) as Battle_InitUploadObjTiles: M=1, X any, DP=0,
;        DB any
; Exit:  RTS; A clobbered
Battle_InitUploadObjTilesDead:
    LDA.b #!BattleRom_ObjTilePieces+$80&$FF
    STA.l A1T7L
    LDA.b #(!BattleRom_ObjTilePieces+$80>>8)&$FF
    STA.l A1T7H
    LDA.b #!Battle_InitPieceBytes&$FF
    STA.l DAS7L
    LDA.b #!Battle_InitPieceBytes>>8
    STA.l DAS7H
    LDA.b #!Battle_ObjPiece2Vram&$FF
    STA.l VMADDL
    TDC
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    LDA.b #!BattleRom_ObjTilePieces+$C0&$FF
    STA.l A1T7L
    LDA.b #(!BattleRom_ObjTilePieces+$C0>>8)&$FF
    STA.l A1T7H
    LDA.b #!Battle_InitPieceBytes&$FF
    STA.l DAS7L
    LDA.b #!Battle_InitPieceBytes>>8
    STA.l DAS7H
    LDA.b #!Battle_ObjPiece3Vram&$FF
    STA.l VMADDL
    LDA.b #!Battle_ObjPiece3Vram>>8
    STA.l VMADDH
    LDA.b #!MDMAEN_Ch7
    STA.l MDMAEN
    RTS
; ============================================================
; Battle set-up: the scene ($CC:E2E4–$CC:F06A)
; ============================================================
;
; $CC:E2E4 — Battle_InitScene (2723 bytes, $E2E4–$ED86)
; The first step of BattleSys_SceneSetup: puts the battle's RAM into its
; starting state. In order:
;   - per-enemy animation timers (1 for enemies 0-3, 2 for 4-7), zeroes
;     $1D00-$1DFF, and sets the "none" value $FF in the command queue,
;     menu roster, tech lists, enemy and battler bytes listed below;
;   - the config bytes (!Battle_Config0-2) into the battle's copies;
;   - PC defaults (screen offsets, box size, move speed and delay), the
;     attribute bytes from !Battle_ActAttrBits, and three OAM helper tables
;     (!Battle_OamHighXBit, !Battle_OamHighXClear, !Battle_OamHighIdx);
;   - !Battle_CellMap: a frame of blocked cells from ROM, ORed with bit 7
;     of the field's tile attributes under each cell;
;   - clears the tech-text, tech-window and status-bar map buffers, copies
;     the command window map, and builds !Battle_InitMapBuf;
;   - names: all seven characters' names re-encoded into !Pc_CharNameTiles,
;     the party's into !Pc_NameTiles (noting Frog's slot in
;     !Battle_UnkA0FF and Magus's in !BattleUI_UnkA115);
;   - colours from ROM into !Battle_PaletteSavedLo, its copy to
;     !Battle_PaletteLiveLo, the PCs' palettes and weapon colours;
;   - each PC's tech list (singles, a double header and the doubles, a
;     triple header and the triple) and line count, and the saved cursor
;     positions when the config keeps them;
;   - PC positions from FieldBtlPc and sprite pointers from the bank $E4
;     tables; then for each enemy from its FieldBtlObj record and its
;     BattleRom_EnemySpr record: position, frame layout, palette,
;     sprite pointers, box, move speed, delay and interval;
;   - the !BattleRom_EnemyKindList kinds of the enemies present, the
;     enemy-name lines (one per distinct enemy id, up to three, with the
;     number of enemies on each) and their re-encoded names.
; The meaning of many of the bytes written is not known; the RAM names
; say what was observed.
; Quirks kept as found: the duration-list stride is computed next to each
; facing stride (DP $84 for PCs, $86 for enemies) and never stored; the
; name lines have no bound: a fourth distinct enemy id would be written to
; !Enemy_NameLineId + 6 and its count would land in DP $86, the search's
; own next-line offset.
; Callers (1 JSL site): BattleSys_SceneSetup ($C1:0023).
; Entry: M=1 (8-bit A), X=0 (16-bit X/Y; loops up to $200), DP=0 (scratch
;        !BattleTmp_80-8E; TDC as zero), DB=$7E (absolute RAM)
; Exit:  RTL; M=1, X=0, DP=0, DB=$7E (also what BattleMsg_ReencodeTextBuffer
;        leaves); A, X, Y and DP $80-$8E clobbered; WMADDH = 0
; Calls: Battle_ReencodeText.
Battle_InitScene:
    LDA.b #!Battle_UnkE4Init
    STA.b !Battle_UnkE4
    ; Enemy animation timers: 1 for enemies 0-3, 2 for 4-7 (staggered steps, probably).
    LDA.b #$01
    LDX.w #$0003
.enemy_timers_lo:
    STA.w !Enemy_AnimTimer,X
    DEX
    BPL .enemy_timers_lo
    INC A
    LDX.w #$0003
.enemy_timers_hi:
    STA.w !Enemy_AnimTimer+4,X
    DEX
    BPL .enemy_timers_hi
    ; A = 0 (DP=0): WMADDH = 0 (nothing else of the WRAM port is set here), and zero $1D00-$1DFF.
    TDC
    STA.l WMADDH
    LDX.w #!Battle_Block1D00Bytes-1
.clear_1d00:
    STA.w !Battle_Block1D00,X
    DEX
    BPL .clear_1d00
    ; A = $FF: the "none" value in the command queue, menu state, tech lists and per-slot bytes.
    DEC A
    STA.w Tech_CursorEntry.Partners
    STA.w !Battle_CmdQueue
    STA.w !Battle_CmdQueue+1
    STA.w !Battle_CmdQueue+2
    STA.w !Battle_CmdQueue+3
    STA.w !Battle_Unk95D2
    STA.w !BattleMenu_ItemScrollDrawn
    STA.w !Battle_CursorGlowStep
    STA.w !BattleMenu_Roster
    STA.w !BattleMenu_Roster+1
    STA.w !BattleMenu_Roster+2
    STA.w !BattleMenu_UnkA6DC
    STA.w !BattleMenu_RosterIdx
    STA.w !BattleMenu_RosterIdxDrawn
    STA.w !BattleUI_NextPanelSlot
    ; !BattleMenu_ActivePc and the 4-byte !BattleMenu_ReadyQueue after it.
    LDX.w #$0004
.clear_menu_queue:
    STA.w !BattleMenu_ActivePc,X
    DEX
    BPL .clear_menu_queue
    LDX.w #!Battle_TechListsBytes-1
.clear_tech_lists:
    STA.w !Tech_ListCode,X
    DEX
    BPL .clear_tech_lists
    LDX.w #$0007
.clear_enemy_bytes:
    STA.w !Enemy_Anim,X
    STA.w !Enemy_MoveTarget,X
    STA.w !Enemy_Unk988B,X
    STA.w !Enemy_NameLineId,X
    STA.w !Battle_ActObjFollow,X
    DEX
    BPL .clear_enemy_bytes
    LDX.w #!Battle_LastSlot
.clear_battler_bytes:
    STA.w !Battler_FrameShown,X
    STA.w !Battler_FxWanted,X
    STA.w !Battler_FxApplied,X
    DEX
    BPL .clear_battler_bytes
    LDX.w #$0006
.clear_9919:
    STA.w !Battle_Unk9919,X
    DEX
    BPL .clear_9919
    LDA.b #$08
    STA.w !Battle_UnkA112
    LDA.b #$02
    STA.w !BattleMenu_CursorPalette
    LDA.b #!Battle_FirstEnemySlot
    STA.w !Battle_StatusAnimNext
    ; The config bytes into the battle's settings.
    LDA.w !Battle_Config0
    AND.b #!Battle_Cfg0ModeBit
    EOR.b #!Battle_Cfg0ModeBit
    STA.w !Battle_CfgBattleMode
    LDA.w !Battle_Config2
    TAX
    LDA.l !BattleRom_GaugeLayoutByCfg,X
    STA.w !BattleUI_GaugeLayout
    LDA.w !Battle_Config1
    AND.b #!Battle_Cfg1CursorBit
    STA.w !BattleMenu_CfgCursorMemory
    LDA.w !Battle_Config1
    AND.b #!Battle_Cfg1ListBit
    STA.w !BattleMenu_CfgListMemory
    LDA.w !Battle_Config0
    AND.b #!Battle_Cfg0InfoBit
    STA.w !BattleMenu_CfgInfoPanel
    LDX.w #!Battle_Unk9842Bytes-1
    LDA.b #!Battle_Unk9842Empty
.clear_9842:
    STA.w !Battle_Unk9842,X
    DEX
    BPL .clear_9842
    STZ.w !Battle_Unk9851
    ; PC defaults: screen offsets (0, -16), an 8-pixel box, move speed 2 and delay 1.
    LDX.w #$0002
    LDA.b #!Battle_PcOffsetYInit
.pc_offsets:
    STZ.w !Battler_ScreenOffsetX,X
    STA.w !Battler_ScreenOffsetY,X
    DEX
    BPL .pc_offsets
    LDX.w #$0002
.pc_boxes:
    LDA.b #$08
    STA.w !Battler_HalfWidth,X
    STA.w !Battler_Height,X
    DEX
    BPL .pc_boxes
    LDX.w #$0002
.pc_move_defaults:
    LDA.b #$02
    STA.w !Battler_DefMoveSpeed,X
    LDA.b #$01
    STA.w !Battler_DefMoveDelay,X
    DEX
    BPL .pc_move_defaults
    ; Enemy move timers and intervals ($20 until each enemy present gets its own).
    LDX.w #!Enemy_MoveBytes-1
    LDA.b #!Enemy_MoveTimerInit
.enemy_move_timers:
    STA.w !Enemy_MoveTimer,X
    DEX
    BPL .enemy_move_timers
    LDX.w #!Battle_LastSlot
    LDA.w !Battle_ActAttrBits
.battler_attrs:
    STA.w !Battler_ActAttr,X
    STA.w !Battler_ActAttrInit,X
    DEX
    BPL .battler_attrs
    LDX.w #$0007
.object_attrs:
    STA.w !Battle_ActObjAttr,X
    STA.w !Battle_ActObjAttrInit,X
    DEX
    BPL .object_attrs
    ; Fill the OAM helper tables: for each low-table offset (4 B per sprite) the
    TDC
    TAY
    ; high-table x bit 8 of that sprite and the mask that clears it.
.pattern_block:
    TDC
    TAX
.pattern_byte:
    LDA.l !BattleRom_Unk8E2DPattern,X
    STA.w !Battle_OamHighXBit,Y
    STA.w !Battle_OamHighXBit+1,Y
    STA.w !Battle_OamHighXBit+2,Y
    STA.w !Battle_OamHighXBit+3,Y
    LDA.l !BattleRom_Unk8C2DPattern,X
    STA.w !Battle_OamHighXClear,Y
    STA.w !Battle_OamHighXClear+1,Y
    STA.w !Battle_OamHighXClear+2,Y
    STA.w !Battle_OamHighXClear+3,Y
    INY
    INY
    INY
    INY
    INX
    CPX.w #$0004
    BNE .pattern_byte
    CPY.w #!Battle_OamTableBytes
    BNE .pattern_block
    LDX.w #!Battle_LastSlot
    LDA.b #!Battler_UnkA5C2Init
.fill_a5c2:
    STA.w !Battler_UnkA5C2,X
    DEX
    BPL .fill_a5c2
    ; !Battle_OamHighIdx: entry n = n / 16.
    TDC
    TAX
.div16_entry:
    REP #$20
    TXA
    LSR A
    LSR A
    LSR A
    LSR A
    SEP #$20
    STA.w !Battle_OamHighIdx,X
    INX
    CPX.w #!Battle_OamTableBytes
    BNE .div16_entry
    TDC
    TAX
    TAY
.cellmap_top:
    LDA.l !BattleRom_CellMapEdge,X
    STA.w !Battle_CellMap,Y
    INY
    INX
    CPX.w #!Battle_CellRowBytes*2
    BNE .cellmap_top
    LDA.b #!Battle_CellMapMidRows
    STA.b !BattleTmp_80
.cellmap_row:
    TDC
    TAX
.cellmap_row_byte:
    LDA.l !BattleRom_CellMapRow,X
    STA.w !Battle_CellMap,Y
    INY
    INX
    CPX.w #!Battle_CellRowBytes
    BNE .cellmap_row_byte
    DEC.b !BattleTmp_80
    BNE .cellmap_row
    TDC
    TAX
.cellmap_bottom:
    LDA.l !BattleRom_CellMapEdge,X
    STA.w !Battle_CellMap,Y
    INY
    INX
    CPX.w #!Battle_CellRowBytes*3
    BNE .cellmap_bottom
    ; ... then each cell gets bit 7 of the field's attribute A byte and, as bit 6 (!Battle_CellBlocked),
    LDX.w #!Battle_CellMapBytes-1
    ; bit 7 of its attribute B byte.
.cellmap_field_attrs:
    LDA.w !Battle_FieldAttrB,X
    AND.b #!Battle_FieldAttrBBit7
    LSR A
    STA.b !BattleTmp_80
    LDA.w !Battle_FieldAttrA,X
    AND.b #!Battle_FieldAttrABit7
    ORA.b !BattleTmp_80
    ORA.w !Battle_CellMap,X
    STA.w !Battle_CellMap,X
    DEX
    BPL .cellmap_field_attrs
    ; Clear the map buffers to tile 0 with !BattleUI_AttrPal2 and copy the command window map.
    TDC
    TAX
    LDA.b #!BattleUI_AttrPal2
.clear_tech_text:
    STZ.w BattleMenu_TechTextTile(0,0),X
    STA.w BattleMenu_TechTextAttr(0,0),X
    INX
    INX
    CPX.w #!BattleMenu_TechTextBytes
    BNE .clear_tech_text
    TDC
    TAX
    LDA.b #!BattleUI_AttrPal2
.clear_tech_window:
    STZ.w BattleMenu_TechTile(0,0),X
    STA.w BattleMenu_TechAttr(0,0),X
    INX
    INX
    CPX.w #!BattleMenu_WindowBytes
    BNE .clear_tech_window
    TDC
    TAX
    LDA.b #!BattleUI_AttrPal2
.clear_status_map:
    STZ.w BattleUI_StatusTile(0,0),X
    STA.w BattleUI_StatusAttr(0,0),X
    INX
    INX
    CPX.w #!BattleUI_StatusMapBytes
    BNE .clear_status_map
    TDC
    TAX
.copy_window_map:
    LDA.l !BattleRom_CommandWindowMap,X
    STA.w !BattleMenu_WindowMap,X
    INX
    CPX.w #!BattleMenu_WindowBytes
    BNE .copy_window_map
    ; !Battle_InitMapBuf: blank cells, then tiles $00-$0F and $30-$3F in map row 1, $10-$1F and
    TDC
    TAX
    ; $40-$4F in row 2 (the attribute bytes keep $29), then three rows from ROM and blank cells.
.blank_init_map:
    LDA.b #!BattleUI_TileBlank
    STA.w !Battle_InitMapBuf,X
    LDA.b #!BattleUI_AttrPal2
    STA.w !Battle_InitMapBuf+1,X
    INX
    INX
    CPX.w #!BattleUI_MapRowBytes*4
    BNE .blank_init_map
    TDC
    LDX.w #!BattleUI_MapRowBytes
.init_map_row1a:
    STA.w !Battle_InitMapBuf,X
    INC A
    INX
    INX
    CPX.w #!BattleUI_MapRowBytes+$20
    BNE .init_map_row1a
    LDA.b #!Battle_InitMapTiles1B
.init_map_row1b:
    STA.w !Battle_InitMapBuf,X
    INC A
    INX
    INX
    CPX.w #!BattleUI_MapRowBytes*2
    BNE .init_map_row1b
    LDA.b #!Battle_InitMapTiles2A
.init_map_row2a:
    STA.w !Battle_InitMapBuf,X
    INC A
    INX
    INX
    CPX.w #!BattleUI_MapRowBytes*2+$20
    BNE .init_map_row2a
    LDA.b #!Battle_InitMapTiles2B
.init_map_row2b:
    STA.w !Battle_InitMapBuf,X
    INC A
    INX
    INX
    CPX.w #!BattleUI_MapRowBytes*3
    BNE .init_map_row2b
    TDC
    TAX
.init_map_rom_rows:
    LDA.l !BattleRom_InitMapRows,X
    STA.w !Battle_InitMapBufRow4,X
    INX
    CPX.w #!Battle_InitMapRomBytes
    BNE .init_map_rom_rows
.init_map_blank_tail:
    LDA.b #!BattleUI_TileBlank
    STA.w !Battle_InitMapBufRow4,X
    LDA.b #!BattleUI_AttrPal2
    STA.w !Battle_InitMapBufRow4+1,X
    INX
    INX
    CPX.w #!BattleUI_MapRowBytes*8
    BNE .init_map_blank_tail
    ; Copy the 5 letters of each character's name, then re-encode each into its two tile rows.
    TDC
    TAX
    TAY
.copy_char_names:
    LDA.w !Pc_CharNames,Y
    STA.w !Pc_CharNameCopy,X
    LDA.w !Pc_CharNames+1,Y
    STA.w !Pc_CharNameCopy+1,X
    LDA.w !Pc_CharNames+2,Y
    STA.w !Pc_CharNameCopy+2,X
    LDA.w !Pc_CharNames+3,Y
    STA.w !Pc_CharNameCopy+3,X
    LDA.w !Pc_CharNames+4,Y
    STA.w !Pc_CharNameCopy+4,X
    TYA
    CLC
    ADC.b #$06
    TAY
    TXA
    CLC
    ADC.b #$05
    TAX
    CPX.w #!Pc_NumChars*!Pc_NameRowLen
    BNE .copy_char_names
    TDC
    TAY
    STY.b !BattleTmp_80
.encode_char_name:
    LDA.b !BattleTmp_80
    TAX
    LDA.l !BattleRom_SlotTimes5,X
    TAY
    LDA.w !Pc_CharNameCopy,Y
    STA.w !BattleMsg_TextTiles
    LDA.w !Pc_CharNameCopy+1,Y
    STA.w !BattleMsg_TextTiles+1
    LDA.w !Pc_CharNameCopy+2,Y
    STA.w !BattleMsg_TextTiles+2
    LDA.w !Pc_CharNameCopy+3,Y
    STA.w !BattleMsg_TextTiles+3
    LDA.w !Pc_CharNameCopy+4,Y
    STA.w !BattleMsg_TextTiles+4
    STZ.w !BattleMsg_TextTiles+5
    JSR Battle_ReencodeText
    LDA.b !BattleTmp_80
    TAX
    LDA.l !BattleRom_PcNameOffset,X
    TAY
    TDC
    TAX
.char_name_lower:
    LDA.w !BattleMsg_TextTiles,X
    STA.w !Pc_CharNameTiles,Y
    INY
    INX
    CPX.w #$0005
    BNE .char_name_lower
    TDC
    TAX
.char_name_upper:
    LDA.w !BattleMsg_TextTopTiles,X
    STA.w !Pc_CharNameTiles,Y
    INY
    INX
    CPX.w #$0005
    BNE .char_name_upper
    INC.b !BattleTmp_80
    LDA.b !BattleTmp_80
    CMP.b #!Pc_NumChars
    BNE .encode_char_name
    ; The party: note Frog's slot (!Battle_UnkA0FF, then times 5 below) and Magus's
    TDC
    TAX
    STX.b !BattleTmp_80
    STX.b !BattleTmp_82
    ; (!BattleUI_UnkA115, with !BattleUI_UnkA117 counted up), copy each PC's name and mark the
.party_slot:
    LDX.b !BattleTmp_80
    ; slot present.
    LDA.w !Pc_CharId,X
    BMI .next_party_slot
    AND.b #$07
    CMP.b #!Pc_CharFrog
    BNE .not_frog
    STX.w !Battle_UnkA0FF
    BRA .copy_pc_name
.not_frog:
    CMP.b #!Pc_CharMagus
    BNE .copy_pc_name
    STX.w !BattleUI_UnkA115
    INC.w !BattleUI_UnkA117
.copy_pc_name:
    TAX
    LDA.l !BattleRom_CharTimes6,X
    TAX
    LDY.b !BattleTmp_82
    LDA.w !Pc_CharNames,X
    STA.w !Pc_NameCopy,Y
    LDA.w !Pc_CharNames+1,X
    STA.w !Pc_NameCopy+1,Y
    LDA.w !Pc_CharNames+2,X
    STA.w !Pc_NameCopy+2,Y
    LDA.w !Pc_CharNames+3,X
    STA.w !Pc_NameCopy+3,Y
    LDA.w !Pc_CharNames+4,X
    STA.w !Pc_NameCopy+4,Y
    LDX.b !BattleTmp_80
    INC.w !Battler_Present,X
.next_party_slot:
    INC.b !BattleTmp_80
    CLC
    LDA.b !BattleTmp_82
    ADC.b #$05
    STA.b !BattleTmp_82
    CMP.b #!Battle_NumPcSlots*!Pc_NameRowLen
    BNE .party_slot
    LDA.w !Battle_UnkA0FF
    ASL A
    ASL A
    CLC
    ADC.w !Battle_UnkA0FF
    STA.w !Battle_UnkA0FF
    ; Re-encode the party's names into !Pc_NameTiles.
    TDC
    TAY
    STY.b !BattleTmp_80
.encode_pc_name:
    LDA.b !BattleTmp_80
    TAX
    LDA.l !BattleRom_SlotTimes5,X
    TAY
    LDA.w !Pc_NameCopy,Y
    STA.w !BattleMsg_TextTiles
    LDA.w !Pc_NameCopy+1,Y
    STA.w !BattleMsg_TextTiles+1
    LDA.w !Pc_NameCopy+2,Y
    STA.w !BattleMsg_TextTiles+2
    LDA.w !Pc_NameCopy+3,Y
    STA.w !BattleMsg_TextTiles+3
    LDA.w !Pc_NameCopy+4,Y
    STA.w !BattleMsg_TextTiles+4
    STZ.w !BattleMsg_TextTiles+5
    JSR Battle_ReencodeText
    LDA.b !BattleTmp_80
    TAX
    LDA.l !BattleRom_PcNameOffset,X
    TAY
    TDC
    TAX
.pc_name_lower:
    LDA.w !BattleMsg_TextTiles,X
    STA.w !Pc_NameTiles,Y
    INY
    INX
    CPX.w #$0005
    BNE .pc_name_lower
    TDC
    TAX
.pc_name_upper:
    LDA.w !BattleMsg_TextTopTiles,X
    STA.w !Pc_NameTiles,Y
    INY
    INX
    CPX.w #$0005
    BNE .pc_name_upper
    INC.b !BattleTmp_80
    LDA.b !BattleTmp_80
    CMP.b #!Battle_NumPcSlots
    BNE .encode_pc_name
    ; Colours from bank $FF into the saved palette, then the saved $200 bytes into the live one.
    TDC
    TAX
.colours_a:
    LDA.l !BattleRom_ColoursA,X
    STA.w !Battle_PaletteSavedLo+16,X
    INX
    CPX.w #$0008
    BNE .colours_a
    TDC
    TAX
.colours_b:
    LDA.l !BattleRom_ColoursB,X
    STA.w !Battle_PaletteSavedLo+24,X
    INX
    CPX.w #$0008
    BNE .colours_b
    TDC
    TAX
.colours_c:
    LDA.l !BattleRom_ColoursC,X
    STA.w !Battle_PaletteSavedLo+314,X
    INX
    LDA.l !BattleRom_ColoursC,X
    STA.w !Battle_PaletteSavedLo+314,X
    INX
    CPX.w #$0006
    BNE .colours_c
    LDX.w #!Battle_PaletteCopyBytes-1
.copy_palette:
    LDA.w !Battle_PaletteSavedLo,X
    STA.w !Battle_PaletteLiveLo,X
    DEX
    BPL .copy_palette
    ; PC palettes $0A/$0C/$0E (base and current).
    LDA.b #!Battle_PcPalette0
    STA.w !Battler_BasePalette
    STA.w !Battler_Palette
    INC A
    INC A
    STA.w !Battler_BasePalette+1
    STA.w !Battler_Palette+1
    INC A
    INC A
    STA.w !Battler_BasePalette+2
    STA.w !Battler_Palette+2
    ; Weapon colours: each PC's !Battle_Unk1C48 byte (its record of 5 B) indexes
    TDC
    TAX
    STX.b !BattleTmp_82
    STX.b !BattleTmp_84
    ; !BattleRom_WeaponColourIdx; 6 B to !Battle_PaletteLive + $BA + PC * 32.
.weapon_colours:
    LDY.b !BattleTmp_82
    LDA.w !Battle_Unk1C48,Y
    TAX
    LDA.l !BattleRom_WeaponColourIdx,X
    REP #$20
    STA.b !BattleTmp_80
    ASL A
    CLC
    ADC.b !BattleTmp_80
    ASL A
    TAX
    TDC
    SEP #$20
    LDA.b !BattleTmp_84
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    TAY
    LDA.b #$06
    STA.b !BattleTmp_80
.weapon_colour_byte:
    LDA.l !BattleRom_WeaponColours,X
    STA.w !Battle_PaletteLive+186,Y
    INX
    INY
    DEC.b !BattleTmp_80
    BNE .weapon_colour_byte
    CLC
    LDA.b !BattleTmp_82
    ADC.b #$05
    STA.b !BattleTmp_82
    INC.b !BattleTmp_84
    LDA.b !BattleTmp_84
    CMP.b #$03
    BNE .weapon_colours
    ; Pc_Unk9F25 / Pc_Unk9F28 = 1 when the PC's Tech_MenuEntry 10 (first double) / 18 (triple) holds a tech.
    LDY.w #$0002
.find_combo_entries:
    TYA
    ASL A
    TAX
    LDA.l !BattleRom_TechEntryBase,X
    STA.b !BattleTmp_80
    LDA.l !BattleRom_TechEntryBase+1,X
    STA.b !BattleTmp_81
    LDX.b !BattleTmp_80
    LDA.w Tech_MenuEntry[!Tech_FirstDoubleEntry].TechId,X
    BMI .no_double
    LDA.b #$01
    STA.w !Pc_Unk9F25,Y
.no_double:
    LDA.w Tech_MenuEntry[!Tech_FirstTripleEntry].TechId,X
    BMI .no_triple
    LDA.b #$01
    STA.w !Pc_Unk9F28,Y
.no_triple:
    DEY
    BPL .find_combo_entries
    ; Tech lists, pass 1: each PC's single techs (entries 0-7), then the double-tech header when
    TDC
    TAX
    STX.b !BattleTmp_80
    STX.b !BattleTmp_82
    ; Pc_Unk9F25 is set. DP $86 + PC * 2 keeps where each list goes on.
.singles_pc:
    STZ.b !BattleTmp_82
    STZ.b !BattleTmp_8C
    LDA.b !BattleTmp_83
    TAX
    LDA.l !BattleRom_TechListBase,X
    TAY
    LDA.b !BattleTmp_83
    ASL A
    TAX
    LDA.l !BattleRom_TechEntryBase,X
    STA.b !BattleTmp_84
    LDA.l !BattleRom_TechEntryBase+1,X
    STA.b !BattleTmp_85
    LDX.b !BattleTmp_84
.single_entry:
    LDA.w Tech_MenuEntry.TechId,X
    CMP.b #!Tech_EntryNone
    BEQ .next_single
    STA.w !Tech_ListCode,Y
    LDA.b !BattleTmp_82
    STA.w !Tech_ListEntry,Y
    INY
    INC.b !BattleTmp_8C
.next_single:
    REP #$21
    TXA
    ADC.w #$0007
    TAX
    TDC
    SEP #$20
    INC.b !BattleTmp_82
    LDA.b !BattleTmp_82
    CMP.b #!Tech_SingleEntries
    BNE .single_entry
    LDA.b !BattleTmp_83
    TAX
    LDA.w !Pc_Unk9F25,X
    BEQ .singles_done
    LDA.b #!Tech_CodeDoubleHeader
    STA.w !Tech_ListCode,Y
    INY
.singles_done:
    STY.b !BattleTmp_84
    LDA.b !BattleTmp_83
    ASL A
    TAX
    LDA.b !BattleTmp_84
    STA.b !BattleTmp_86,X
    LDA.b !BattleTmp_85
    STA.b !BattleTmp_87,X
    INC.b !BattleTmp_83
    LDA.b !BattleTmp_83
    CMP.b #!Battle_NumPcSlots
    BNE .singles_pc
    ; Pass 2: the doubles (entries 10-15), then the triple-tech header when Pc_Unk9F28 is set.
    TDC
    TAX
    STX.b !BattleTmp_80
    STX.b !BattleTmp_82
.doubles_pc:
    LDA.b #!Tech_FirstDoubleEntry
    STA.b !BattleTmp_82
    STZ.b !BattleTmp_8C
    LDA.b !BattleTmp_83
    ASL A
    TAX
    LDA.b !BattleTmp_86,X
    STA.b !BattleTmp_84
    LDA.b !BattleTmp_87,X
    STA.b !BattleTmp_85
    LDY.b !BattleTmp_84
    LDA.b !BattleTmp_83
    ASL A
    TAX
    LDA.l !BattleRom_TechEntryBase,X
    STA.b !BattleTmp_84
    LDA.l !BattleRom_TechEntryBase+1,X
    STA.b !BattleTmp_85
    LDX.b !BattleTmp_84
.double_entry:
    LDA.w Tech_MenuEntry[!Tech_FirstDoubleEntry].TechId,X
    CMP.b #!Tech_EntryNone
    BEQ .next_double
    STA.w !Tech_ListCode,Y
    LDA.b !BattleTmp_82
    STA.w !Tech_ListEntry,Y
    INY
    INC.b !BattleTmp_8C
.next_double:
    REP #$21
    TXA
    ADC.w #$0007
    TAX
    TDC
    SEP #$20
    INC.b !BattleTmp_82
    LDA.b !BattleTmp_82
    CMP.b #!Tech_FirstDoubleEntry+!Tech_DoubleEntries
    BNE .double_entry
    LDA.b !BattleTmp_83
    TAX
    LDA.w !Pc_Unk9F28,X
    BEQ .doubles_done
    LDA.b #!Tech_CodeTripleHeader
    STA.w !Tech_ListCode,Y
    INY
.doubles_done:
    STY.b !BattleTmp_84
    LDA.b !BattleTmp_83
    ASL A
    TAX
    LDA.b !BattleTmp_84
    STA.b !BattleTmp_86,X
    LDA.b !BattleTmp_85
    STA.b !BattleTmp_87,X
    INC.b !BattleTmp_83
    LDA.b !BattleTmp_83
    CMP.b #!Battle_NumPcSlots
    BEQ .triples
    JMP .doubles_pc
    ; Pass 3: the triple (entry 18) on the line after the header, with entry number 18 when it is
.triples:
    TDC
    TAX
    STX.b !BattleTmp_80
    STX.b !BattleTmp_82
    ; a tech; Y is not moved on.
.triples_pc:
    LDA.b !BattleTmp_83
    TAX
    LDA.w !Pc_Unk9F28,X
    BEQ .next_triples_pc
    LDA.b #!Tech_FirstTripleEntry
    STA.b !BattleTmp_82
    LDA.b !BattleTmp_83
    ASL A
    TAX
    LDA.b !BattleTmp_86,X
    STA.b !BattleTmp_84
    LDA.b !BattleTmp_87,X
    STA.b !BattleTmp_85
    LDY.b !BattleTmp_84
    LDA.b !BattleTmp_83
    ASL A
    TAX
    LDA.l !BattleRom_TechEntryBase,X
    STA.b !BattleTmp_84
    LDA.l !BattleRom_TechEntryBase+1,X
    STA.b !BattleTmp_85
    LDX.b !BattleTmp_84
    LDA.w Tech_MenuEntry[!Tech_FirstTripleEntry].TechId,X
    STA.w !Tech_ListCode,Y
    BMI .next_triples_pc
    LDA.b #!Tech_FirstTripleEntry
    STA.w !Tech_ListEntry,Y
.next_triples_pc:
    INC.b !BattleTmp_83
    LDA.b !BattleTmp_83
    CMP.b #!Battle_NumPcSlots
    BNE .triples_pc
    ; !Pc_TechCount: lines before the first !Tech_CodeBlank, at most !Tech_ListLen.
    LDX.w #$0002
    STX.b !BattleTmp_80
.count_pc:
    LDA.b !BattleTmp_80
    TAX
    LDA.l !BattleRom_TechListBase,X
    TAY
    LDX.b !BattleTmp_80
    STZ.w !Pc_TechCount,X
.count_line:
    LDA.w !Tech_ListCode,Y
    CMP.b #!Tech_CodeBlank
    BEQ .count_done
    INY
    INC.w !Pc_TechCount,X
    LDA.w !Pc_TechCount,X
    CMP.b #!Tech_ListLen
    BNE .count_line
.count_done:
    DEC.b !BattleTmp_80
    BPL .count_pc
    ; Saved cursors per character (Battle_SavedCursor), when the config keeps them; the tech
    LDX.w #$0002
    STX.b !BattleTmp_80
    ; row and scroll are dropped when the line they point to no longer holds the saved code.
.restore_cursor:
    LDX.b !BattleTmp_80
    LDA.w !Pc_CharId,X
    BMI .next_restore
    ASL A
    ASL A
    TAY
    LDA.w !BattleMenu_CfgCursorMemory
    BEQ .restore_list_cursor
    LDA.w Battle_SavedCursor.MenuRow,Y
    STA.w !Pc_SavedMenuRow,X
.restore_list_cursor:
    LDA.w !BattleMenu_CfgListMemory
    BEQ .next_restore
    LDA.w Battle_SavedCursor.TechId,Y
    STA.w !Pc_SavedTech,X
    LDA.w Battle_SavedCursor.TechRow,Y
    STA.w !Pc_SavedTechRow,X
    LDA.w Battle_SavedCursor.TechScroll,Y
    STA.w !Pc_SavedTechScroll,X
    CLC
    ADC.w !Pc_SavedTechRow,X
    LDX.b !BattleTmp_80
    ADC.l !BattleRom_TechListBase,X
    TAX
    LDA.w Battle_SavedCursor.TechId,Y
    CMP.w !Tech_ListCode,X
    BEQ .next_restore
    LDX.b !BattleTmp_80
    STZ.w !Pc_SavedTechRow,X
    STZ.w !Pc_SavedTechScroll,X
.next_restore:
    DEC.b !BattleTmp_80
    BPL .restore_cursor
    LDA.w !BattleMenu_CfgListMemory
    BEQ .copy_pc_starts
    LDA.w !Battle_SavedItemScroll
    STA.w !BattleMenu_ItemScroll
    LDA.w !Battle_SavedItemRow
    STA.w !BattleMenu_ItemRow
    ; PC positions: !Battler_ScreenX/Y = cell * 16 + sub-cell offset, start frame, facing 0.
.copy_pc_starts:
    TDC
    TAX
.copy_pc_start_byte:
    LDA.w FieldBtlPc.TileX,X
    STA.w Battler_StartRec.TileX,X
    INX
    CPX.w #!Battle_NumPcSlots*!Battler_StartRecBytes
    BNE .copy_pc_start_byte
    TDC
    TAY
    TAX
.place_pc:
    LDA.w Battler_StartRec.TileX,X
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC.w Battler_StartRec.SubX,X
    STA.w !Battler_ScreenX,Y
    LDA.w Battler_StartRec.TileY,X
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC.w Battler_StartRec.SubY,X
    STA.w !Battler_ScreenY,Y
    LDA.b #!Battler_SprBytesPc
    STA.w !Battler_SprBytes,Y
    LDA.w Battler_StartRec.Frame,X
    STA.w !Battler_StartFrame,Y
    TDC
    STA.w !Battler_Facing,Y
    TXA
    CLC
    ADC.b #!Battler_StartRecBytes
    TAX
    INY
    CPY.w #!Battle_NumPcSlots
    BNE .place_pc
    ; PC sprites, by character id: tile and frame-record pointers, frame-id and duration list
    STZ.b !BattleTmp_80
    STZ.b !BattleTmp_81
    ; offsets in bank $E4, and the facing block size (next set's offset minus this one, / 4).
.pc_sprite:
    LDY.b !BattleTmp_80
    LDA.w !Pc_CharId,Y
    ASL A
    PHA
    CLC
    ADC.w !Pc_CharId,Y
    TAX
    TYA
    ASL A
    CLC
    ADC.b !BattleTmp_80
    TAY
    LDA.l !BattleRom_SprTilesPtr,X
    STA.w !Battler_TileGfxPtr,Y
    LDA.l !BattleRom_SprTilesPtr+1,X
    STA.w !Battler_TileGfxPtr+1,Y
    LDA.l !BattleRom_SprTilesPtr+2,X
    STA.w !Battler_TileGfxPtr+2,Y
    LDA.l !BattleRom_SprFramesPtr,X
    STA.w !Battler_FramesPtr,Y
    LDA.l !BattleRom_SprFramesPtr+1,X
    STA.w !Battler_FramesPtr+1,Y
    LDA.l !BattleRom_SprFramesPtr+2,X
    STA.w !Battler_FramesPtr+2,Y
    PLA
    TAX
    LDA.l !BattleRom_SprAnimFrames,X
    STA.w !Battler_AnimFrameBase,Y
    STA.b !BattleTmp_82
    LDA.l !BattleRom_SprAnimFrames+1,X
    STA.w !Battler_AnimFrameBase+1,Y
    STA.b !BattleTmp_83
    LDA.b #!BattleRom_SprAnimFrames>>16
    STA.w !Battler_AnimFrameBase+2,Y
    LDA.l !BattleRom_SprAnimDurs,X
    STA.w !Battler_AnimDurBase,Y
    STA.b !BattleTmp_84
    LDA.l !BattleRom_SprAnimDurs+1,X
    STA.w !Battler_AnimDurBase+1,Y
    STA.b !BattleTmp_85
    LDA.b #!BattleRom_SprAnimDurs>>16
    STA.w !Battler_AnimDurBase+2,Y
    TXA
    LSR A
    INC A
    ASL A
    TAX
    LDA.l !BattleRom_SprAnimFrames,X
    STA.b !BattleTmp_86
    LDA.l !BattleRom_SprAnimFrames+1,X
    STA.b !BattleTmp_87
    LDA.l !BattleRom_SprAnimDurs,X
    STA.b !BattleTmp_88
    LDA.l !BattleRom_SprAnimDurs+1,X
    STA.b !BattleTmp_89
    REP #$20
    SEC
    LDA.b !BattleTmp_86
    SBC.b !BattleTmp_82
    LSR A
    LSR A
    STA.b !BattleTmp_82
    SEC
    LDA.b !BattleTmp_88
    SBC.b !BattleTmp_84
    STA.b !BattleTmp_84
    TDC
    SEP #$20
    LDX.b !BattleTmp_80
    LDA.b !BattleTmp_82
    STA.w !Battler_FacingStrideLo,X
    LDA.b !BattleTmp_83
    STA.w !Battler_FacingStrideHi,X
    INC.b !BattleTmp_80
    LDA.b !BattleTmp_80
    CMP.b #!Battle_NumPcSlots
    BEQ .enemy_starts
    JMP .pc_sprite
    ; Enemy positions: the first 5 bytes of each 12-byte FieldBtlObj record.
.enemy_starts:
    TDC
    TAX
    TAY
    STZ.b !BattleTmp_80
.enemy_start_rec:
    STZ.b !BattleTmp_81
.enemy_start_byte:
    LDA.w FieldBtlObj.TileX,X
    STA.w Battler_StartRec[3].TileX,Y
    INX
    INY
    INC.b !BattleTmp_81
    LDA.b !BattleTmp_81
    CMP.b #!Battler_StartRecBytes
    BNE .enemy_start_byte
    CLC
    TXA
    ADC.b #$07
    TAX
    INC.b !BattleTmp_80
    LDA.b !BattleTmp_80
    CMP.b #!Battle_NumEnemies
    BNE .enemy_start_rec
    ; Enemies: for each record with an id (BattleEnemyInit.Unk1, the id's high byte, not negative).
    STZ.b !BattleTmp_80
    STZ.b !BattleTmp_81
.enemy_slot:
    LDX.b !BattleTmp_80
    LDA.l !BattleRom_EnemyRecOfs,X
    TAX
    LDA.w BattleEnemyInit.Unk1,X
    BPL .enemy_present
    JMP .next_enemy
.enemy_present:
    CLC
    LDA.b !BattleTmp_80
    ADC.b #$03
    TAY
    LDA.w FieldBtlObj.Flags,X
    AND.b #$07
    STA.w !Battler_FrameLayout,Y
    PHX
    TAX
    LDA.l !BattleRom_LayoutSprBytes,X
    STA.w !Battler_SprBytes,Y
    PLX
    LDA.w FieldBtlObj.TileX,X
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC.w FieldBtlObj.SubX,X
    STA.w !Battler_ScreenX,Y
    LDA.w FieldBtlObj.TileY,X
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC.w FieldBtlObj.SubY,X
    STA.w !Battler_ScreenY,Y
    LDA.w FieldBtlObj.Frame,X
    STA.w !Battler_StartFrame,Y
    TDC
    STA.w !Battler_Facing,Y
    STA.w !Battler_Unk96E6,Y
    LDA.w FieldBtlObj.Attr,X
    ASL A
    STA.w !Battler_BasePalette,Y
    STA.w !Battler_Palette,Y
    LDA.w FieldBtlObj.Flags,X
    AND.b #!Battle_Unk9FF7Skip
    STA.w !Battler_Unk9FF7,Y
    LDA.b !BattleTmp_80
    ASL A
    CLC
    ADC.b !BattleTmp_80
    TAY
    ; Tiles where the field object had them; the id's BattleRom_EnemySpr record (id * 10) gives
    LDA.w FieldBtlObj.GfxBank,X
    STA.w !Battler_TileGfxPtr+(3*!Battle_FirstEnemySlot)+2,Y
    ; the frame-record set and the animation set.
    REP #$20
    LDA.w FieldBtlObj.GfxOfs,X
    STA.w !Battler_TileGfxPtr+(3*!Battle_FirstEnemySlot),Y
    LDA.w BattleEnemyInit.Id,X
    STA.b !BattleTmp_8C
    ASL A
    STA.b !BattleTmp_82
    ASL A
    ASL A
    CLC
    ADC.b !BattleTmp_82
    TAX
    LDA.l BattleRom_EnemySpr.AnimSet,X
    AND.w #!Battle_LowByteMask
    STA.b !BattleTmp_8E
    LDA.l BattleRom_EnemySpr.FrameSet,X
    AND.w #!Battle_LowByteMask
    STA.b !BattleTmp_82
    ASL A
    CLC
    ADC.b !BattleTmp_82
    TAX
    LDA.l !BattleRom_SprFramesPtr,X
    STA.w !Battler_FramesPtr+(3*!Battle_FirstEnemySlot),Y
    TDC
    SEP #$20
    LDA.l !BattleRom_SprFramesPtr+2,X
    STA.w !Battler_FramesPtr+(3*!Battle_FirstEnemySlot)+2,Y
    REP #$20
    LDA.b !BattleTmp_8E
    ASL A
    TAX
    LDA.l !BattleRom_SprAnimFrames,X
    STA.w !Battler_AnimFrameBase+(3*!Battle_FirstEnemySlot),Y
    STA.b !BattleTmp_84
    LDA.l !BattleRom_SprAnimDurs,X
    STA.w !Battler_AnimDurBase+(3*!Battle_FirstEnemySlot),Y
    STA.b !BattleTmp_86
    TDC
    SEP #$20
    LDA.b #!BattleRom_SprAnimFrames>>16
    STA.w !Battler_AnimFrameBase+(3*!Battle_FirstEnemySlot)+2,Y
    LDA.b #!BattleRom_SprAnimDurs>>16
    STA.w !Battler_AnimDurBase+(3*!Battle_FirstEnemySlot)+2,Y
    REP #$20
    LDA.b !BattleTmp_8E
    INC A
    ASL A
    TAX
    LDA.l !BattleRom_SprAnimFrames,X
    STA.b !BattleTmp_88
    LDA.l !BattleRom_SprAnimDurs,X
    STA.b !BattleTmp_8A
    SEC
    LDA.b !BattleTmp_88
    SBC.b !BattleTmp_84
    LSR A
    LSR A
    STA.b !BattleTmp_84
    SEC
    LDA.b !BattleTmp_8A
    SBC.b !BattleTmp_86
    STA.b !BattleTmp_86
    TDC
    SEP #$20
    CLC
    LDA.b !BattleTmp_80
    ADC.b #!Battle_FirstEnemySlot
    TAX
    LDA.b !BattleTmp_84
    STA.w !Battler_FacingStrideLo,X
    LDA.b !BattleTmp_85
    STA.w !Battler_FacingStrideHi,X
    ; The BattleRom_EnemySpr flags, offsets, box and move byte.
    REP #$20
    LDA.b !BattleTmp_8C
    ASL A
    STA.b !BattleTmp_82
    ASL A
    ASL A
    CLC
    ADC.b !BattleTmp_82
    TAX
    TDC
    SEP #$20
    LDY.b !BattleTmp_80
    LDA.l BattleRom_EnemySpr.Flags,X
    STA.w !Enemy_SprFlags,Y
    AND.b #!Enemy_SprFlag80
    BEQ .not_flag80
    STA.w !Battler_UnkA5C2+!Battle_FirstEnemySlot,Y
    STA.w !Battler_UnkA5CD+!Battle_FirstEnemySlot,Y
.not_flag80:
    LDA.w !Enemy_SprFlags,Y
    AND.b #!Enemy_SprFlag08
    BEQ .not_flag8
    INC.w !Battle_EnemyPartsOn
    LDA.b !BattleTmp_80
    STA.w !Battle_PartsAnchor
.not_flag8:
    LDA.w !Enemy_SprFlags,Y
    AND.b #!Enemy_SprFlag20
    BEQ .not_flag20
    PHX
    LDA.b !BattleTmp_80
    TAX
    INC.w !Enemy_UnkA006,X
    PLX
.not_flag20:
    LDA.w !Enemy_SprFlags,Y
    AND.b #!Enemy_SprFlag04
    STA.w !Battler_UnkA08C+!Battle_FirstEnemySlot,Y
    TDC
    STA.w !Battler_UnkA5D8+!Battle_FirstEnemySlot,Y
    LDA.l BattleRom_EnemySpr.OffsetX,X
    STA.w !Battler_ScreenOffsetX+!Battle_FirstEnemySlot,Y
    LDA.l BattleRom_EnemySpr.OffsetY,X
    STA.w !Battler_ScreenOffsetY+!Battle_FirstEnemySlot,Y
    LDA.l BattleRom_EnemySpr.HalfWidth,X
    STA.w !Battler_HalfWidth+!Battle_FirstEnemySlot,Y
    LDA.l BattleRom_EnemySpr.Height,X
    STA.w !Battler_Height+!Battle_FirstEnemySlot,Y
    LDA.l BattleRom_EnemySpr.Move,X
    AND.b #$07
    STA.w !Battler_DefMoveSpeed+!Battle_FirstEnemySlot,Y
    LDA.l BattleRom_EnemySpr.Move,X
    LSR A
    LSR A
    LSR A
    LSR A
    STA.w !Battler_DefMoveDelay+!Battle_FirstEnemySlot,Y
    STA.w !Battler_Unk9816+!Battle_FirstEnemySlot,Y
    ; !Enemy_MoveInterval from the delay and speed; the timer starts staggered by enemy number.
    LSR A
    ASL A
    ASL A
    STA.b !BattleTmp_82
    LDA.w !Battler_DefMoveSpeed+!Battle_FirstEnemySlot,Y
    LSR A
    CLC
    ADC.b !BattleTmp_82
    TAX
    LDA.l !BattleRom_EnemyMoveInterval,X
    STA.w !Enemy_MoveInterval,Y
    CLC
    ADC.b !BattleTmp_80
    STA.w !Enemy_MoveTimer,Y
    ; !Enemy_Id; ids $D8, $94 and $AD (high byte 0) stand one pixel lower; mark the enemy present.
    LDA.b !BattleTmp_80
    ASL A
    TAX
    LDA.b !BattleTmp_8C
    STA.w !Enemy_Id,X
    LDA.b !BattleTmp_8D
    STA.w !Enemy_Id+1,X
    BNE .count_enemy
    LDA.w !Enemy_Id,X
    CMP.b #!Enemy_IdLowerA
    BEQ .nudge_y
    CMP.b #!Enemy_IdLowerB
    BEQ .nudge_y
    CMP.b #!Enemy_IdLowerC
    BNE .count_enemy
.nudge_y:
    LDX.b !BattleTmp_80
    INC.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
.count_enemy:
    LDX.b !BattleTmp_80
    INC.w !Battler_Present+!Battle_FirstEnemySlot,X
.next_enemy:
    INC.b !BattleTmp_80
    LDA.b !BattleTmp_80
    CMP.b #!Battle_NumEnemies
    BEQ .enemies_done
    JMP .enemy_slot
    ; With an !Enemy_SprFlag08 enemy, every enemy's offset from the last such one.
.enemies_done:
    LDA.w !Battle_EnemyPartsOn
    BEQ .kind_list
    LDA.w !Battle_PartsAnchor
    TAX
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    STA.b !BattleTmp_80
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    STA.b !BattleTmp_81
    TDC
    TAX
.enemy_offset:
    LDA.w !Battler_Present+!Battle_FirstEnemySlot,X
    BEQ .next_enemy_offset
    SEC
    LDA.w !Battler_ScreenX+!Battle_FirstEnemySlot,X
    SBC.b !BattleTmp_80
    STA.w !Enemy_PartOfsX,X
    SEC
    LDA.w !Battler_ScreenY+!Battle_FirstEnemySlot,X
    SBC.b !BattleTmp_81
    STA.w !Enemy_PartOfsY,X
.next_enemy_offset:
    INX
    CPX.w #!Battle_NumEnemies
    BNE .enemy_offset
    ; !BattleRom_EnemyKindList: for each enemy id in the list: kind 3 locks the tech and item lists
.kind_list:
    TDC
    TAX
    TAY
    STY.b !BattleTmp_80
    STY.b !BattleTmp_82
    REP #$20
    ; (!BattleMenu_Lock bit 0), kind 4 sets !Battle_UnkA113, any other kind word goes to
.kind_record:
    LDA.l !BattleRom_EnemyKindList,X
    BMI .next_kind_enemy
    CMP.w !Enemy_Id,Y
    BNE .next_kind_record
    LDA.l !BattleRom_EnemyKindList+2,X
    CMP.w #!Enemy_KindLockMenus
    BNE .not_kind3
    LDA.w #1
    STA.b !BattleTmp_80
    BRA .next_kind_record
.not_kind3:
    CMP.w #!Enemy_KindUnkA113
    BNE .other_kind
    STA.b !BattleTmp_82
    BRA .next_kind_record
.other_kind:
    STA.w !Battle_Unk99D2
.next_kind_record:
    INX
    INX
    INX
    INX
    BRA .kind_record
.next_kind_enemy:
    TDC
    TAX
    INY
    INY
    CPY.w #!Battle_NumEnemies*2
    BNE .kind_record
    TDC
    SEP #$20
    LDA.w !BattleMenu_Lock
    ORA.b !BattleTmp_80
    STA.w !BattleMenu_Lock
    LDA.b !BattleTmp_82
    STA.w !Battle_UnkA113
    ; Enemy-name lines: one per distinct id of the enemies present and not skipped (!Battler_Unk9FF7),
    TDC
    TAY
    STY.b !BattleTmp_80
    STY.b !BattleTmp_82
    STY.b !BattleTmp_84
    STY.b !BattleTmp_86
    STY.b !BattleTmp_88
    ; with a 16-bit count per line in DP $80/$82/$84; no bound on the number of lines (see the header).
.name_lines_enemy:
    LDX.b !BattleTmp_88
    LDA.w !Battler_Present+!Battle_FirstEnemySlot,X
    BEQ .next_name_enemy
    LDA.w !Battler_Unk9FF7+!Battle_FirstEnemySlot,X
    BMI .next_name_enemy
    REP #$20
    TDC
    TAX
.name_line_search:
    LDA.w !Enemy_Id,Y
    CMP.w !Enemy_NameLineId,X
    BEQ .count_in_line
    INX
    INX
    CPX.w #!Enemy_NameLines*2
    BNE .name_line_search
    LDX.b !BattleTmp_86
    STA.w !Enemy_NameLineId,X
    INC.b !BattleTmp_86
    INC.b !BattleTmp_86
.count_in_line:
    INC.b !BattleTmp_80,X
    TDC
    SEP #$20
.next_name_enemy:
    INC.b !BattleTmp_88
    INY
    INY
    CPY.w #!Battle_NumEnemies*2
    BNE .name_lines_enemy
    LDA.b !BattleTmp_80
    STA.w !Enemy_NameLineUsed
    LDA.b !BattleTmp_82
    STA.w !Enemy_NameLineUsed+1
    LDA.b !BattleTmp_84
    STA.w !Enemy_NameLineUsed+2
    ; The name of each line's enemy id (11 B at id * 11, an end byte), re-encoded into !Enemy_NameTiles.
    TDC
    TAX
    STX.b !BattleTmp_80
.name_line:
    LDX.b !BattleTmp_80
    LDA.w !Enemy_NameLineId+1,X
    BMI .next_name_line
    REP #$20
    LDA.w !Enemy_NameLineId,X
    ASL A
    ASL A
    STA.b !BattleTmp_82
    ASL A
    CLC
    ADC.b !BattleTmp_82
    SEC
    SBC.w !Enemy_NameLineId,X
    TAX
    LDA.l !BattleRom_EnemyNames,X
    STA.w !BattleMsg_TextTiles
    LDA.l !BattleRom_EnemyNames+2,X
    STA.w !BattleMsg_TextTiles+2
    LDA.l !BattleRom_EnemyNames+4,X
    STA.w !BattleMsg_TextTiles+4
    LDA.l !BattleRom_EnemyNames+6,X
    STA.w !BattleMsg_TextTiles+6
    LDA.l !BattleRom_EnemyNames+8,X
    STA.w !BattleMsg_TextTiles+8
    LDA.l !BattleRom_EnemyNames+10,X
    STA.w !BattleMsg_TextTiles+10
    TDC
    STA.w !BattleMsg_TextTiles+11
    SEP #$20
    JSR Battle_ReencodeText
    LDA.b !BattleTmp_80
    ASL A
    ASL A
    STA.b !BattleTmp_82
    ASL A
    CLC
    ADC.b !BattleTmp_82
    TAY
    TDC
    TAX
.enemy_name_lower:
    LDA.w !BattleMsg_TextTiles,X
    STA.w !Enemy_NameTiles,Y
    INY
    INX
    CPX.w #!Enemy_NameBytes
    BNE .enemy_name_lower
    TDC
    TAX
.enemy_name_upper:
    LDA.w !BattleMsg_TextTopTiles,X
    STA.w !Enemy_NameTiles,Y
    INY
    INX
    CPX.w #!Enemy_NameBytes
    BNE .enemy_name_upper
.next_name_line:
    INC.b !BattleTmp_80
    INC.b !BattleTmp_80
    LDA.b !BattleTmp_80
    CMP.b #!Enemy_NameLines*2
    BNE .name_line
    RTL
; $CC:ED87 — Battle_InitSceneGfx (732 bytes, $ED87–$F062)
; The fourth step of BattleSys_SceneSetup: sprite and tile set-up, then the
; VRAM uploads. In order:
;   - !Battle_SprRec: 44 records at x = y = 0 with tile and attribute from
;     !BattleRom_SprRecInit;
;   - for each battler present, $AA in its !Battle_Unk0B24 byte and in
;     the bytes after it: 1, 2, 3 or 6 bytes in all for frame layout 0,
;     1, 2 or 3 on; the scan goes on after them, so the slots they cover
;     are not tested themselves;
;   - the attribute bytes of records 12-43 of !Battle_SprRec, 16 B (four
;     records) per row and one row per enemy entry: !Enemy_Unk988B + $20
;     for an enemy present, in 1, 2, 3 or 6 rows by its frame layout as
;     above, the next entries being skipped the same way;
;   - !Battle_InitTileBuf: 16 2bpp tiles widened to 4bpp with zero planes,
;     then 64 4bpp tiles;
;   - OAM sprites 0-3 (the target cursors' entries): at 0,0, tile 0,
;     !BattleOam_CursorAttr, high-table byte $FF;
;   - !Battle_HitNumColoursA/B and six colours from bank $D1;
;   - the six !Battler_FrameDmaSrcA... words of each battler present: two fixed
;     sets for frame layout 2 (one for slot 3, one for the others), else
;     from ROM by slot and layout;
;   - !Battle_Unk9F34 counted up when a PC's BattlerStats.Unk57 is $A4 or
;     $B8;
;   - then sets !Battle_InitUploadStage (0 -> 1) and loops until the
;     uploads (Battle_InitUploadStep, from the interrupt side) leave it at
;     4.
; Why a large enemy's rows cover the next enemy entries is not traced
; (probably the entries of its parts).
; Callers (1 JSL site): BattleSys_SceneSetup ($C1:002D).
; Entry: M=1 (8-bit A), X=0 (16-bit X/Y), DP=0 (scratch !BattleTmp_80-82;
;        TDC as zero), DB=$7E (absolute RAM)
; Exit:  RTL; M=1, X=0, DP=0, DB=$7E; A, X, Y, DP $80-$82 clobbered;
;        !Battle_InitUploadStage = 4
Battle_InitSceneGfx:
    TDC
    TAX
    TAY
.spr_rec:
    TDC
    STA.w Battle_SprRec.X,Y
    INY
    STA.w Battle_SprRec.X,Y
    INY
    LDA.l !BattleRom_SprRecInit,X
    STA.w Battle_SprRec.X,Y
    INY
    INX
    LDA.l !BattleRom_SprRecInit,X
    STA.w Battle_SprRec.X,Y
    INY
    INX
    CPY.w #!Battle_SprRecCount*4
    BNE .spr_rec
    TDC
    TAX
.battler_hi:
    LDA.w !Battler_Present,X
    BEQ .next_battler_hi
    LDA.b #!Battle_HiTableLarge4
    STA.w !Battle_Unk0B24,X
    LDA.w !Battler_FrameLayout,X
    STA.b !BattleTmp_80
    BEQ .next_battler_hi
    INX
    LDA.b #!Battle_HiTableLarge4
    STA.w !Battle_Unk0B24,X
    DEC.b !BattleTmp_80
    BEQ .next_battler_hi
    INX
    LDA.b #!Battle_HiTableLarge4
    STA.w !Battle_Unk0B24,X
    DEC.b !BattleTmp_80
    BEQ .next_battler_hi
    INX
    LDA.b #!Battle_HiTableLarge4
    STA.w !Battle_Unk0B24,X
    INX
    LDA.b #!Battle_HiTableLarge4
    STA.w !Battle_Unk0B24,X
    INX
    LDA.b #!Battle_HiTableLarge4
    STA.w !Battle_Unk0B24,X
.next_battler_hi:
    INX
    CPX.w #!Battle_NumSlots
    BNE .battler_hi
    ; Attribute bytes of the enemy rows of !Battle_SprRec (16 B = four records per row).
    TDC
    TAX
    TAY
.enemy_attrs:
    LDA.w !Battler_Present+!Battle_FirstEnemySlot,X
    BNE .enemy_present
    JMP .next_enemy_attrs
.enemy_present:
    LDA.w !Enemy_Unk988B,X
    CLC
    ADC.b #!Battle_SprAttrPriority2
    STA.b !BattleTmp_80
    STA.w Battle_SprRec[12].Attr,Y
    STA.w Battle_SprRec[13].Attr,Y
    STA.w Battle_SprRec[14].Attr,Y
    STA.w Battle_SprRec[15].Attr,Y
    LDA.w !Battler_FrameLayout+!Battle_FirstEnemySlot,X
    STA.b !BattleTmp_82
    BNE .enemy_more_rows
    JMP .next_enemy_attrs
.enemy_more_rows:
    TYA
    CLC
    ADC.b #!Battle_SprRecRowBytes
    TAY
    LDA.b !BattleTmp_80
    STA.w Battle_SprRec[12].Attr,Y
    STA.w Battle_SprRec[13].Attr,Y
    STA.w Battle_SprRec[14].Attr,Y
    STA.w Battle_SprRec[15].Attr,Y
    INX
    DEC.b !BattleTmp_82
    BEQ .next_enemy_attrs
    TYA
    CLC
    ADC.b #!Battle_SprRecRowBytes
    TAY
    LDA.b !BattleTmp_80
    STA.w Battle_SprRec[12].Attr,Y
    STA.w Battle_SprRec[13].Attr,Y
    STA.w Battle_SprRec[14].Attr,Y
    STA.w Battle_SprRec[15].Attr,Y
    INX
    DEC.b !BattleTmp_82
    BEQ .next_enemy_attrs
    TYA
    CLC
    ADC.b #!Battle_SprRecRowBytes
    TAY
    LDA.b !BattleTmp_80
    STA.w Battle_SprRec[12].Attr,Y
    STA.w Battle_SprRec[13].Attr,Y
    STA.w Battle_SprRec[14].Attr,Y
    STA.w Battle_SprRec[15].Attr,Y
    TYA
    CLC
    ADC.b #!Battle_SprRecRowBytes
    TAY
    LDA.b !BattleTmp_80
    STA.w Battle_SprRec[12].Attr,Y
    STA.w Battle_SprRec[13].Attr,Y
    STA.w Battle_SprRec[14].Attr,Y
    STA.w Battle_SprRec[15].Attr,Y
    TYA
    CLC
    ADC.b #!Battle_SprRecRowBytes
    TAY
    LDA.b !BattleTmp_80
    STA.w Battle_SprRec[12].Attr,Y
    STA.w Battle_SprRec[13].Attr,Y
    STA.w Battle_SprRec[14].Attr,Y
    STA.w Battle_SprRec[15].Attr,Y
    INX
    INX
    INX
.next_enemy_attrs:
    TYA
    CLC
    ADC.b #!Battle_SprRecRowBytes
    TAY
    INX
    CPX.w #!Battle_NumEnemies
    BEQ .attrs_done
    JMP .enemy_attrs
    ; !Battle_InitTileBuf: 16 2bpp tiles, each followed by 16 zero bytes (planes 2-3) ...
.attrs_done:
    TDC
    TAY
    TAX
    LDA.b #!Battle_InitTiles2bppCount
    STA.b !BattleTmp_80
.tiles2bpp_tile:
    LDA.b #!Battle_Tile2bppBytes
    STA.b !BattleTmp_81
.tiles2bpp_byte:
    LDA.l !BattleRom_InitTiles2bpp,X
    STA.w !Battle_InitTileBuf,Y
    INX
    INY
    DEC.b !BattleTmp_81
    BNE .tiles2bpp_byte
    LDA.b #!Battle_Tile2bppBytes
    STA.b !BattleTmp_81
    TDC
.tiles2bpp_zero:
    STA.w !Battle_InitTileBuf,Y
    INY
    DEC.b !BattleTmp_81
    BNE .tiles2bpp_zero
    DEC.b !BattleTmp_80
    BNE .tiles2bpp_tile
    ; ... then 64 4bpp tiles.
    TDC
    TAX
    LDA.b #!Battle_InitTiles4bppCount
    STA.b !BattleTmp_80
.tiles4bpp_tile:
    LDA.b #!Battle_Tile4bppBytes
    STA.b !BattleTmp_81
.tiles4bpp_byte:
    LDA.l !BattleRom_InitTiles4bpp,X
    STA.w !Battle_InitTileBuf,Y
    INX
    INY
    DEC.b !BattleTmp_81
    BNE .tiles4bpp_byte
    DEC.b !BattleTmp_80
    BNE .tiles4bpp_tile
    ; OAM sprites 0-3 at 0,0 with tile 0, !BattleOam_CursorAttr; high-table byte $FF.
    STZ.w BattleOam[0].Tile
    STZ.w BattleOam[1].Tile
    STZ.w BattleOam[2].Tile
    STZ.w BattleOam[3].Tile
    LDA.b #!BattleOam_CursorAttr
    STA.w BattleOam[0].Attr
    STA.w BattleOam[1].Attr
    STA.w BattleOam[2].Attr
    STA.w BattleOam[3].Attr
    LDA.b #!BattleOam_HideCursorBits|!BattleOam_CursorSizeBits
    STA.w !BattleOam_HighTable
    STZ.w BattleOam[0].X
    STZ.w BattleOam[1].X
    STZ.w BattleOam[2].X
    STZ.w BattleOam[3].X
    STZ.w BattleOam[0].Y
    STZ.w BattleOam[1].Y
    STZ.w BattleOam[2].Y
    STZ.w BattleOam[3].Y
    ; Hit-number colours and two sets of three colours.
    TDC
    TAX
.hitnum_colours:
    LDA.l !BattleRom_HitNumColours,X
    STA.w !Battle_HitNumColoursA,X
    INX
    CPX.w #!Battle_HitNumColourBytes*2
    BNE .hitnum_colours
    TDC
    TAX
.colours_38f2:
    LDA.l !BattleRom_UnkColours38F2,X
    STA.w !Battle_PaletteLive+90,X
    INX
    CPX.w #$0006
    BNE .colours_38f2
    TDC
    TAX
.colours_38fa:
    LDA.l !BattleRom_UnkColours38FA,X
    STA.w !Battle_PaletteLive+122,X
    INX
    CPX.w #$0006
    BNE .colours_38fa
    ; The six !Battler_FrameDmaSrcA... words of each battler present (Y = slot * 2).
    TDC
    TAX
    STX.b !BattleTmp_80
.battler_vram:
    LDX.b !BattleTmp_80
    LDA.w !Battler_Present,X
    BNE .battler_present
    JMP .next_battler_vram
.battler_present:
    LDA.b !BattleTmp_80
    ASL A
    TAY
    LDA.w !Battler_FrameLayout,X
    CMP.b #$02
    BEQ .layout2
    JMP .layout_table
.layout2:
    TYX
    CPY.w #$0006
    BNE .layout2_other
    LDA.b #!Battler_FrameDmaVramASlot3&$FF
    STA.w !Battler_FrameDmaVramA,Y
    LDA.b #!Battler_FrameDmaVramASlot3>>8
    STA.w !Battler_FrameDmaVramA+1,Y
    LDA.b #!Battler_FrameDmaVramBSlot3&$FF
    STA.w !Battler_FrameDmaVramB,Y
    LDA.b #!Battler_FrameDmaVramBSlot3>>8
    STA.w !Battler_FrameDmaVramB+1,Y
    LDA.b #!Battler_FrameDmaSizeASlot3&$FF
    STA.w !Battler_FrameDmaSizeA,Y
    LDA.b #!Battler_FrameDmaSizeASlot3>>8
    STA.w !Battler_FrameDmaSizeA+1,Y
    LDA.b #!Battler_FrameDmaSizeBSlot3&$FF
    STA.w !Battler_FrameDmaSizeB,Y
    LDA.b #!Battler_FrameDmaSizeBSlot3>>8
    STA.w !Battler_FrameDmaSizeB+1,Y
    LDA.b #!Battler_FrameDmaSrcASlot3&$FF
    STA.w !Battler_FrameDmaSrcA,Y
    LDA.b #!Battler_FrameDmaSrcASlot3>>8
    STA.w !Battler_FrameDmaSrcA+1,Y
    LDA.b #!Battler_FrameDmaSrcBSlot3&$FF
    STA.w !Battler_FrameDmaSrcB,Y
    LDA.b #!Battler_FrameDmaSrcBSlot3>>8
    STA.w !Battler_FrameDmaSrcB+1,Y
    BRA .layout2_done
.layout2_other:
    LDA.b #!Battler_FrameDmaVramAOther&$FF
    STA.w !Battler_FrameDmaVramA,Y
    LDA.b #!Battler_FrameDmaVramAOther>>8
    STA.w !Battler_FrameDmaVramA+1,Y
    LDA.b #!Battler_FrameDmaVramBOther&$FF
    STA.w !Battler_FrameDmaVramB,Y
    LDA.b #!Battler_FrameDmaVramBOther>>8
    STA.w !Battler_FrameDmaVramB+1,Y
    LDA.b #!Battler_FrameDmaSizeAOther&$FF
    STA.w !Battler_FrameDmaSizeA,Y
    LDA.b #!Battler_FrameDmaSizeAOther>>8
    STA.w !Battler_FrameDmaSizeA+1,Y
    LDA.b #!Battler_FrameDmaSizeBOther&$FF
    STA.w !Battler_FrameDmaSizeB,Y
    LDA.b #!Battler_FrameDmaSizeBOther>>8
    STA.w !Battler_FrameDmaSizeB+1,Y
    LDA.b #!Battler_FrameDmaSrcAOther&$FF
    STA.w !Battler_FrameDmaSrcA,Y
    LDA.b #!Battler_FrameDmaSrcAOther>>8
    STA.w !Battler_FrameDmaSrcA+1,Y
    LDA.b #!Battler_FrameDmaSrcBOther&$FF
    STA.w !Battler_FrameDmaSrcB,Y
    LDA.b #!Battler_FrameDmaSrcBOther>>8
    STA.w !Battler_FrameDmaSrcB+1,Y
.layout2_done:
    BRA .next_battler_vram
.layout_table:
    ASL A
    TAX
    LDA.l !BattleRom_FrameDmaSizeA,X
    STA.w !Battler_FrameDmaSizeA,Y
    LDA.l !BattleRom_FrameDmaSizeA+1,X
    STA.w !Battler_FrameDmaSizeA+1,Y
    LDA.l !BattleRom_FrameDmaSizeB,X
    STA.w !Battler_FrameDmaSizeB,Y
    LDA.l !BattleRom_FrameDmaSizeB+1,X
    STA.w !Battler_FrameDmaSizeB+1,Y
    TYX
    LDA.l !BattleRom_FrameDmaVramA,X
    STA.w !Battler_FrameDmaVramA,Y
    LDA.l !BattleRom_FrameDmaVramA+1,X
    STA.w !Battler_FrameDmaVramA+1,Y
    LDA.l !BattleRom_FrameDmaVramB,X
    STA.w !Battler_FrameDmaVramB,Y
    LDA.l !BattleRom_FrameDmaVramB+1,X
    STA.w !Battler_FrameDmaVramB+1,Y
    LDA.l !BattleRom_FrameDmaSrcA,X
    STA.w !Battler_FrameDmaSrcA,Y
    LDA.l !BattleRom_FrameDmaSrcA+1,X
    STA.w !Battler_FrameDmaSrcA+1,Y
    LDA.l !BattleRom_FrameDmaSrcB,X
    STA.w !Battler_FrameDmaSrcB,Y
    LDA.l !BattleRom_FrameDmaSrcB+1,X
    STA.w !Battler_FrameDmaSrcB+1,Y
.next_battler_vram:
    INC.b !BattleTmp_80
    LDA.b !BattleTmp_80
    CMP.b #!Battle_NumSlots
    BEQ .check_unk57
    JMP .battler_vram
    ; !Battle_Unk9F34 when a PC's BattlerStats.Unk57 is !Battle_Unk57ValueA or B.
.check_unk57:
    LDA.w BattlerStats[0].Unk57
    CMP.b #!Battle_Unk57ValueA
    BEQ .unk57_found
    CMP.b #!Battle_Unk57ValueB
    BEQ .unk57_found
    LDA.w BattlerStats[1].Unk57
    CMP.b #!Battle_Unk57ValueA
    BEQ .unk57_found
    CMP.b #!Battle_Unk57ValueB
    BEQ .unk57_found
    LDA.w BattlerStats[2].Unk57
    CMP.b #!Battle_Unk57ValueA
    BEQ .unk57_found
    CMP.b #!Battle_Unk57ValueB
    BNE .start_uploads
.unk57_found:
    INC.w !Battle_Unk9F34
    ; Start the uploads and wait for Battle_InitUploadStep to run all three stages.
.start_uploads:
    INC.w !Battle_InitUploadStage
.wait_uploads:
    LDA.w !Battle_InitUploadStage
    CMP.b #!Battle_InitUploadDone
    BNE .wait_uploads
    RTL
; $CC:F063 — Battle_ReencodeText (8 bytes, $F063–$F06A)
; Re-encodes the text in !BattleMsg_TextTiles into its two tile rows:
; BankC1_LongDispatch entry 0 (BattleMsg_ReencodeTextBuffer) through the
; bank-$C1 vector, with A = 0. The BRA goes to the next instruction (it
; does nothing; kept as found).
; Callers (3 JSR sites): Battle_InitScene ($CC:E5C2, $CC:E686, $CC:ED50).
; Entry: M=1, X=0, DP=0 (TDC as A = 0; the bank-$C1 code needs it), DB
;        any; the text in !BattleMsg_TextTiles
; Exit:  RTS; M=1, X=0, DB=$7E (BattleMsg_ReencodeTextBuffer's MVN); A, X,
;        Y clobbered; !BattleMsg_TextTiles / TextTopTiles hold the tiles
Battle_ReencodeText:
    TDC
    BRA .call
.call:
    JSL BankC1_VecLongDispatch
    RTS
; ============================================================
; Action helpers ($CC:F06B–$CC:F364)
; ============================================================
;
; $CC:F06B — BattleAct_ResetState (151 bytes, $F06B–$F101)
; Clears the action state before and after an action (BattleSys_RunAction):
; zeroes !Battle_ActVars ($5D80-$5E0C), $A240-$A27F (object x and offsets),
; $A124-$A1A7 (!Battler_ActAnimMode and what follows), $A1A8-$A1E7 (the
; object-list state from !Battle_ActUnkA1A8), $A337-$A3A8 (from
; !Battle_ActorMoving), the four palette sequences' on, step and calc
; bytes, !Battle_ActCalcSel 0-5, !Battle_ActObjLinks; sets
; !Battle_ActBattlers entries 0-10 and !Battle_ActObjFollow to $FF, the
; position history to $F0, zeroes the battlers' hit-number and mover bytes
; and the single flags at the end.
; Callers (2 JSL sites): BattleSys_RunAction ($C1:405B, $C1:4119).
; Entry: M=1 (8-bit A), X=0 (16-bit X for the $8D-byte loop), DP any (no
;        direct-page operand), DB=$7E (absolute RAM)
; Exit:  RTL; M=1, X=0; A = $F0, X = $FFFF (16-bit); Y, DP and DB unchanged
BattleAct_ResetState:
    LDX.w #!Battle_ActVarsBytes-1
.clear_vars:
    STZ.w !Battle_ActVars,X
    DEX
    BPL .clear_vars
    LDX.w #!Battle_ActObjPosBytes-1
.clear_obj_x:
    STZ.w !Battle_ActObjX,X
    DEX
    BPL .clear_obj_x
    LDX.w #!Battle_ActAnimBytes-1
.clear_anim_modes:
    STZ.w !Battler_ActAnimMode,X
    DEX
    BPL .clear_anim_modes
    LDX.w #!Battle_LastSlot
    LDA.b #!Battle_ActListEnd
.clear_battler_bytes:
    STA.w !Battle_ActBattlers,X
    STZ.w !Battler_HitNumShown,X
    STZ.w !Battler_UnkA4A4,X
    STZ.w !Battler_UnkA4AF,X
    STZ.w !Battler_HitNumAltBounce,X
    DEX
    BPL .clear_battler_bytes
    LDX.w #!Battle_ActObjAnimBytes-1
.clear_a1a8:
    STZ.w !Battle_ActUnkA1A8,X
    DEX
    BPL .clear_a1a8
    LDX.w #!Battle_ActorMoveBytes-1
.clear_moving:
    STZ.w !Battle_ActorMoving,X
    DEX
    BPL .clear_moving
    LDX.w #$0003
.clear_pal_seqs:
    STZ.w !Battle_ActPalSeqOn,X
    STZ.w !Battle_ActPalSeqStep,X
    STZ.w !Battle_ActCalcSel,X
    DEX
    BPL .clear_pal_seqs
    STZ.w !Battle_ActCalcSel+4
    STZ.w !Battle_ActCalcSel+5
    LDX.w #!Battle_ActLinkBytes-1
.clear_links:
    STZ.w !Battle_ActObjLinks,X
    DEX
    BPL .clear_links
    LDX.w #$0007
    LDA.b #!Battle_ActFollowNone
.clear_follow:
    STA.w !Battle_ActObjFollow,X
    DEX
    BPL .clear_follow
    LDX.w #!Battle_PosHistBytes-1
    LDA.b #!Battle_PosHistInit
.clear_history:
    STA.w !Battler_PosHistX,X
    DEX
    BPL .clear_history
    STZ.w !Battle_ActUnkA3D1
    STZ.w !Battle_FrameCount8
    STZ.w !Battle_ActScriptDone
    STZ.w !Battle_ActAnimNextSlot
    STZ.w !Battle_ActFrameHold
    STZ.w !Battle_ActUnkAAFB
    STZ.w !Battle_ActUnkAAFC
    STZ.w !Battle_ActUnkAAFD
    STZ.w !Battle_HitNumActive
    STZ.w !Battle_UnkA2B7
    RTL
; $CC:F102 — BattleAct_ResetFxApplied (14 bytes, $F102–$F10F)
; Sets !Battler_FxApplied of all 11 battler slots to !Battle_FxAppliedStale
; ($55, a value no effect has), so the next effect picked is applied again.
; Callers (1 JSL site): BattleSys_RunAction ($C1:409C).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  RTL; M=1, X=0; A = $55, X = !Battle_NumSlots; Y unchanged
BattleAct_ResetFxApplied:
    TDC
    TAX
    LDA.b #!Battle_FxAppliedStale
.loop:
    STA.w !Battler_FxApplied,X
    INX
    CPX.w #!Battle_NumSlots
    BNE .loop
    RTL
; $CC:F110 — Battle_BuildOccupiedCellMap (70 bytes, $F110–$F155)
; Copies !Battle_CellMap to !Battle_PathMap (MVN, 256 B) and marks with
; !Battle_CellBlocked ($40) the cell under each present battler
; ((y & $F0) | x / 16). It scans 11 entries from slot 0, or from slot 3
; (the enemies) when !Battle_Unk2989 bit 2 is set. Quirk kept: with bit 2
; set the scan still runs 11 entries, so slots 11-13 are tested too: their
; "present" bytes are !Enemy_SprFlags 0-2 and their x / y bytes lie past
; !Battler_ScreenX / ScreenY (not traced whether such a cell is ever marked
; in play).
; Callers (2 JSL sites): BattleSys_RunAction ($C1:40C4) and BattleAct_LoadAttack ($C1:4336).
; Entry: M=1, X=0 (16-bit MVN addresses), DP=0 (scratch !BattleTmp_80-84),
;        DB any (set to $7E by the MVN before the absolute reads)
; Exit:  RTL; M=1, X=0; DB=$7E; A, X, Y and DP $80-$84 clobbered
Battle_BuildOccupiedCellMap:
    REP #$20
    LDX.w #!Battle_CellMap
    LDY.w #!Battle_PathMap
    LDA.w #!Battle_CellMapBytes-1
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    TDC
    SEP #$20
    ; Mark the cells of the battlers present (from slot 3 when !Battle_Unk2989 bit 2 is set).
    STZ.b !BattleTmp_80
    LDA.w !Battle_Unk2989
    AND.b #$04
    BEQ .start_slot
    LDA.b #!Battle_FirstEnemySlot
    STA.b !BattleTmp_80
.start_slot:
    LDA.b #!Battle_NumSlots
    STA.b !BattleTmp_82
    LDA.b !BattleTmp_80
    TAY
.slot:
    LDA.w !Battler_Present,Y
    BEQ .next_slot
    LDA.w !Battler_ScreenY,Y
    AND.b #!Battle_PathRowMask
    STA.b !BattleTmp_84
    LDA.w !Battler_ScreenX,Y
    LSR A
    LSR A
    LSR A
    LSR A
    ORA.b !BattleTmp_84
    TAX
    LDA.b #!Battle_CellBlocked
    STA.w !Battle_PathMap,X
.next_slot:
    INY
    DEC.b !BattleTmp_82
    BNE .slot
    RTL
; $CC:F156 — BattleAct_BuildBattlerList (145 bytes, $F156–$F1E6)
; Builds the action's battler lists from the action block:
; !Battle_ActBattlers = caster, !Battle_ActUnkAE97, !Battle_ActUnkAE98 (for
; a PC caster a negative one becomes one of the other two PCs,
; !BattleRom_PcPartners), the main target (the first set bit of
; !Battle_ActMainMask, bit 15 = slot 0; slot 0 when the mask is 0), then
; every slot set in !Battle_ActTargetMask, $FF-ended. !Battle_ActTargets
; gets the main target and the same set. Then !Battle_ActSavedX/Y take the
; screen position of entries 0-2 (stopping at a negative entry).
; Callers (1 JSL site): BattleSys_RunAction ($C1:40A9).
; Entry: M=1, X=0 (16-bit index stores), DP=0 (scratch !BattleTmp_80-81),
;        DB=$7E
; Exit:  RTL; M=1, X=0; A, X, Y and DP $80-$81 clobbered
BattleAct_BuildBattlerList:
    LDA.w !Battle_ActUnkAE97
    STA.w !Battle_ActBattlers+1
    LDA.w !Battle_ActUnkAE98
    STA.w !Battle_ActBattlers+2
    LDA.w !Battle_ActCaster
    STA.w !Battle_ActBattlers
    CMP.b #!Battle_NumPcSlots
    BCS .main_target
    ASL A
    TAX
    LDA.w !Battle_ActBattlers+1
    BPL .second_partner
    LDA.l !BattleRom_PcPartners,X
    STA.w !Battle_ActBattlers+1
.second_partner:
    LDA.w !Battle_ActBattlers+2
    BPL .main_target
    LDA.l !BattleRom_PcPartners+1,X
    STA.w !Battle_ActBattlers+2
.main_target:
    TDC
    TAX
    REP #$20
    LDA.w !Battle_ActMainMask
    STA.b !BattleTmp_80
    BEQ .store_main
.find_main_bit:
    ASL.b !BattleTmp_80
    BCS .store_main
    INX
    BRA .find_main_bit
.store_main:
    STX.w !Battle_ActMainTarget
    STX.w !Battle_ActTargets
    LDA.w !Battle_ActMainTarget
    ORA.w #!Battle_ActListEnd<<8
    STA.w !Battle_ActMainTarget
    STA.w !Battle_ActTargets
    ; The target set: each slot stored with $FF above it, so the list stays ended.
    TDC
    TAX
    TAY
    LDA.w !Battle_ActTargetMask
    STA.b !BattleTmp_80
    BEQ .save_xy
.target_bit:
    ASL.b !BattleTmp_80
    BCC .next_target_bit
    TXA
    ORA.w #!Battle_ActListEnd<<8
    STA.w !Battle_ActTargetSet,Y
    STA.w !Battle_ActTargets+1,Y
    INY
.next_target_bit:
    INX
    CPX.w #!Battle_NumSlots
    BNE .target_bit
.save_xy:
    TDC
    SEP #$20
    TDC
    TAX
.save_xy_entry:
    LDA.w !Battle_ActBattlers,X
    BMI .done
    TAY
    LDA.w !Battler_ScreenX,Y
    STA.w !Battle_ActSavedX,X
    LDA.w !Battler_ScreenY,Y
    STA.w !Battle_ActSavedY,X
    INX
    CPX.w #!Battle_NumPcSlots
    BNE .save_xy_entry
.done:
    RTL
; $CC:F1E7 — BattleAct_StepPalettes (145 bytes, $F1E7–$F277)
; Steps the four palette sequences: for each one on, counts its timer
; down; at 0 reloads it from the delay, moves the step on (back to the
; first entry past the last) and copies the entry's colour set into
; !Battle_PaletteLive + 2 + (flags & 3) * 8: 3 colours from
; !BattleRom_PalSets6, or 7 from !BattleRom_PalSets14 when the entry's
; flags byte has bit 7. The entries are 2 B (set, flags) in bank $CD at
; !Battle_ActPalPtr.
; Callers (1 JSL site): BattleSys_RunAction ($C1:40BD).
; Entry: M=1, X=0, DP=0 (scratch !BattleTmp_80-84 and Battle_Mul8CC's),
;        DB=$7E
; Exit:  RTL; M=1, X=0; A, X, Y, DP $80-$84, $77-$78 and $AD-$B0 clobbered
; Calls: Battle_Mul8CC.
BattleAct_StepPalettes:
    TDC
    TAX
    STX.b !BattleTmp_80
.sequence:
    LDX.b !BattleTmp_80
    LDA.w !Battle_ActPalSeqOn,X
    BEQ .next_sequence
    DEC.w !Battle_ActPalSeqTimer,X
    BNE .next_sequence
    LDA.w !Battle_ActPalSeqDelay,X
    STA.w !Battle_ActPalSeqTimer,X
    INC.w !Battle_ActPalSeqStep,X
    CLC
    LDA.w !Battle_ActPalSeqFirst,X
    ADC.w !Battle_ActPalSeqStep,X
    CMP.w !Battle_ActPalSeqLast,X
    BCC .read_entry
    BEQ .read_entry
    STZ.w !Battle_ActPalSeqStep,X
    LDA.w !Battle_ActPalSeqFirst,X
.read_entry:
    ASL A
    REP #$21
    ADC.w !Battle_ActPalPtr
    TAX
    TDC
    STA.b !BattleTmp_82
    SEP #$20
    LDA.l !BattleRom_PalListSet,X
    STA.b !BattleTmp_82
    LDA.l !BattleRom_PalListFlags,X
    STA.b !BattleTmp_84
    AND.b #$03
    ASL A
    ASL A
    ASL A
    TAY
    LDA.b !BattleTmp_84
    BMI .sets14
    LDA.b #!BattleRom_PalSets6Bytes
    STA.b !Battle_Mul8A
    LDA.b !BattleTmp_82
    STA.b !Battle_Mul8B
    JSR Battle_Mul8CC
    LDX.b !Battle_Mul8Product
.copy6:
    LDA.l !BattleRom_PalSets6,X
    STA.w !Battle_PaletteLive+2,Y
    INX
    INY
    DEC.b !Battle_Mul8A
    BNE .copy6
    BRA .next_sequence
.sets14:
    LDA.b #!BattleRom_PalSets14Bytes
    STA.b !Battle_Mul8A
    LDA.b !BattleTmp_82
    STA.b !Battle_Mul8B
    JSR Battle_Mul8CC
    LDX.b !Battle_Mul8Product
.copy14:
    LDA.l !BattleRom_PalSets14,X
    STA.w !Battle_PaletteLive+2,Y
    INX
    INY
    DEC.b !Battle_Mul8A
    BNE .copy14
.next_sequence:
    INC.b !BattleTmp_80
    LDA.b !BattleTmp_80
    CMP.b #!Battle_NumPalSeqs
    BEQ .done
    JMP .sequence
.done:
    RTL
; $CC:F278 — BattleAct_TickUnkA1A8 (49 bytes, $F278–$F2A8)
; For the 8 object threads: counts down !Battle_ActObjAnimTimer of each
; whose !Battle_ActUnkA1A8 is set; then runs BattleAct_StepObjAnim for each
; set one whose timer is 0.
; Callers (1 JSL site): BattleSys_RunAction ($C1:40B9).
; Entry: M=1, X=0, DP=0 (DP $80 = the thread for BattleAct_StepObjAnim),
;        DB=$7E
; Exit:  RTL; M=1, X=0; A, X, Y, DP $80-$85, $8E-$8F, $77-$78 and $AD-$B0
;        clobbered
BattleAct_TickUnkA1A8:
    TDC
    TAX
.count_down:
    LDA.w !Battle_ActUnkA1A8,X
    BEQ .next_count
    LDA.w !Battle_ActObjAnimTimer,X
    BEQ .next_count
    DEC.w !Battle_ActObjAnimTimer,X
.next_count:
    INX
    CPX.w #!Battle_ActObjThreads
    BNE .count_down
    TDC
    TAX
    STX.b !BattleTmp_80
.run_entry:
    LDX.b !BattleTmp_80
    LDA.w !Battle_ActUnkA1A8,X
    BEQ .next_run
    LDA.w !Battle_ActObjAnimTimer,X
    BNE .next_run
    JSR BattleAct_StepObjAnim
.next_run:
    INC.b !BattleTmp_80
    LDA.b !BattleTmp_80
    CMP.b #!Battle_ActObjThreads
    BNE .run_entry
    RTL
; $CC:F2A9 — BattleAct_StepObjAnim (188 bytes, $F2A9–$F364)
; Moves object thread DP $80 to the next record of its object list: the
; record (4 B in bank $CE, BattleRom_ActObjRec) is entry
; !Battle_ActObjAnimEntry + 1 of the facing's block (facing *
; !Battle_ActObjAnimCount * 4 past !Battle_ActObjAnimList). Its time byte
; reloads !Battle_ActObjAnimTimer, its offset bytes (sign-extended) go to
; !Battle_ActObjOfsX/Y, and its first byte's low bits to
; !Battle_ActObjFrame. A record with a type (bits 5-7) ends the list:
; in mode !Battle_ActAnimLoop the entry goes back to $FF (start again),
; else !Battle_ActUnkA1A8 is cleared and !Battle_ActObjFrame gets bit 7.
; When the entry wraps from $FF to 0 and !Battle_ActObjAnimStop is set,
; the thread is switched off as well.
; Quirk kept: the facing test at the start stores !Battle_ActObjFacing back
; into itself when it differs from !Battle_ActObjAnimUnkA2B8 (both paths
; leave A = the facing), probably meant to latch it into A2B8.
; Callers note: only BattleAct_TickUnkA1A8.
; Callers (1 JSR site): BattleAct_TickUnkA1A8 ($CC:F29D).
; Entry: M=1, X=0, DP=0 (DP $80 = the thread 0-7, high byte $81 = 0),
;        DB=$7E
; Exit:  RTS; M=1, X=0; A, X, Y, DP $82-$85, $8E-$8F, $77-$78 and $AD-$B0
;        clobbered
; Calls: Battle_Mul8CC.
BattleAct_StepObjAnim:
    LDX.b !BattleTmp_80
    LDA.w !Battle_ActObjFacing,X
    CMP.w !Battle_ActObjAnimUnkA2B8,X
    BEQ .same_facing
    STA.w !Battle_ActObjFacing,X
    BRA .facing_ready
.same_facing:
    LDA.w !Battle_ActObjFacing,X
.facing_ready:
    STA.b !Battle_Mul8A
    LDA.w !Battle_ActObjAnimCount,X
    ASL A
    ASL A
    STA.b !Battle_Mul8B
    JSR Battle_Mul8CC
    LDX.b !Battle_Mul8Product
    STX.b !BattleTmp_82
    LDA.b !BattleTmp_80
    ASL A
    TAY
    STY.b !BattleTmp_84
    ; Next entry; on the wrap from $FF to 0 a set stop flag ends the thread.
    LDX.b !BattleTmp_80
    CLC
    LDA.w !Battle_ActObjAnimEntry,X
    ADC.b #1
    BNE .store_entry
    LDA.w !Battle_ActObjAnimStop,X
    BEQ .wrapped
    STZ.w !Battle_ActUnkA1A8,X
.wrapped:
    TDC
.store_entry:
    STA.w !Battle_ActObjAnimEntry,X
    ; X = the record: entry * 4 + facing block + the list start.
    REP #$20
    ASL A
    ASL A
    CLC
    ADC.b !BattleTmp_82
    CLC
    ADC.w !Battle_ActObjAnimList,Y
    TAX
    TDC
    SEP #$20
    STZ.b !BattleTmp_8E
    STZ.b !BattleTmp_8F
    LDY.b !BattleTmp_80
    LDA.l BattleRom_ActObjRec.Time,X
    BPL .store_timer
    INC.b !BattleTmp_8F
    AND.b #!Battle_ActObjTimeMask
.store_timer:
    STA.w !Battle_ActObjAnimTimer,Y
    LDY.b !BattleTmp_84
    LDA.l BattleRom_ActObjRec.OfsX,X
    STA.w !Battle_ActObjOfsX,Y
    BPL .ofs_x_positive
    LDA.b #!Battle_SignExtendNeg
    BRA .store_ofs_x_hi
.ofs_x_positive:
    TDC
.store_ofs_x_hi:
    STA.w !Battle_ActObjOfsX+1,Y
    LDA.l BattleRom_ActObjRec.OfsY,X
    STA.w !Battle_ActObjOfsY,Y
    BPL .ofs_y_positive
    LDA.b #!Battle_SignExtendNeg
    BRA .store_ofs_y_hi
.ofs_y_positive:
    TDC
.store_ofs_y_hi:
    STA.w !Battle_ActObjOfsY+1,Y
    ; A record with a type ends the list: loop in mode 2, else stop.
    LDY.b !BattleTmp_80
    LDA.l BattleRom_ActObjRec.Flags,X
    AND.b #!Battle_ActObjRecTypeMask
    BEQ .store_flags
    LDA.w !Battle_ActUnkA1A8,Y
    CMP.b #!Battle_ActAnimLoop
    BEQ .loop_list
    TDC
    STA.w !Battle_ActUnkA1A8,Y
    LDA.b #!Battle_ActObjFrameStop
    STA.b !BattleTmp_8E
    BRA .store_flags
.loop_list:
    LDA.b #!Battle_ActObjEntryRestart
    STA.w !Battle_ActObjAnimEntry,Y
.store_flags:
    LDA.l BattleRom_ActObjRec.Flags,X
    AND.b #!Battle_ActObjRecLowMask
    ORA.b !BattleTmp_8E
    STA.w !Battle_ActObjFrame,Y
    LDA.b !BattleTmp_8F
    BEQ .done
    LDA.w !Battle_ActObjFrame,Y
    ORA.b #!Battle_ActObjFrameBit5
    STA.w !Battle_ActObjFrame,Y
.done:
    RTS


; ============================================================
; Battle Math ($CC:F365–$CC:F382)
; ============================================================

; $CC:F365 — Battle_Mul8CC (30 bytes, $F365–$F382)
; A byte-identical copy of Battle_Mul8 ($C1:0089): 8×8→16 hardware
; multiply through WRMPYA/WRMPYB/RDMPYL. It ends in RTS, so each bank
; that needs it keeps its own copy (a JSR cannot leave the bank).
; In:  !Battle_Mul8A = multiplicand, !Battle_Mul8B = multiplier
; Out: !Battle_Mul8Product = 16-bit product; operands mirrored to
;      !Battle_MulMirrorA/B
; The two NOPs after REP are multiply latency: the 8x8 product is only
; valid in RDMPYL 8 cycles after the WRMPYB write.
; Entry: M=1, X either width, DP=0 (assumed, as for Battle_Mul8: the
;        operands are the battle direct-page bytes; the callers' DP is not
;        traced), DB any (the HW registers are reached with STA.l/LDA.l)
; Exit:  M=1; A=0 (TDC with DP=0); X/Y and DB unchanged; DP $77/$78 and
;        $AF/$B0 written
; Callers (3 JSR sites): BattleAct_StepPalettes ($CC:F23E, $CC:F25A) and BattleAct_StepObjAnim
;   ($CC:F2C4).
; Callers note: JSR from $CC:F23E, $CC:F25A and $CC:F2C4 (searched: no other
;          JSR/JMP/JSL reaches $F365). No calls.
org $CCF365
Battle_Mul8CC:
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
