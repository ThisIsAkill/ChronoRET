; ============================================================
; ram_engine.inc — Named WRAM / direct-page locations used by the
; engine core (banks $00, $C0, $FD).
;
; Conventions:
;   !Name = $addr            single variable or per-index array
;   struct Name $addr ...    multi-field records (asar struct; index
;                            with Name[i].Field when the record repeats)
; Every name carries a short comment: width, meaning, and how it was
; inferred (which routine reads/writes it).
;
; Direct page: bank $C0 code often runs with DP=$2100 (hardware
; registers). A dp operand there is a PPU register, not WRAM, so those
; use hardware.inc names via the !DP_ prefix defined below, never a
; WRAM name.
; ============================================================
!ram_engine_inc ?= 0
if !ram_engine_inc == 0
!ram_engine_inc = 1

; --- Stack / fixed RAM ---
!StackTop        = $06FF     ; initial S (MainInit); stack grows down from $06FF
!NmiTrampoline   = $000500   ; 4 B: JML target of the native NMI stub ($00:FF10). Installed by
                             ; InstallNMI ($C0:0B64, from the GameLoop init path) as JML $C0:EA63;
                             ; set to RTI ($40) by $C0:2E4B and repointed into bank $FD by
                             ; $FD:EAF4 (JML $FD:DE15; called from $FD:DBB8). Not touched by MainInit.
!IrqTrampoline   = $000504   ; 4 B: JML target of the native IRQ stub ($00:FF14). Installed by
                             ; InstallIRQ ($C0:0B75) as JML $C0:ECCC; set to RTI by $C0:2E4B and
                             ; repointed by $FD:EAF4 (JML $FD:DE87), the routine that also
                             ; repoints the NMI trampoline.

; ==== Field direct page and bank $C0 names ====

;
; Field direct page. Field/engine code runs with DP = !DP_Field;
; these values are dp offsets (WRAM address = $0100 + offset). An
; absolute access to one of them writes !DP_Field+!Name.
;
!DP_Field = $0100                        ; direct page of field/engine code (GameLoop TCDs it)

; --- Location (current / return / destination) (dp) ---
!Loc_Id = $00                            ; 16-bit current location index; GameLoop_Main dispatches on
                                         ; it ($01F0-$81EF -> bank $C2, $81F0-$81FE -> Sys_HaltWithColor)
!Loc_EntryX = $02                        ; 8-bit entry tile X (Field_SaveState stores the leader's
                                         ; $1801 here); 16-bit loads also take Loc_EntryY
!Loc_EntryY = $03                        ; 8-bit entry tile Y (Field_SaveState stores the leader's
                                         ; $1881 here)
!Loc_EntryFacing = $04                   ; 8-bit entry facing (Field_SaveState stores the leader's
                                         ; Obj_Facing here)
!Loc_ReturnId = $05                      ; 16-bit location to come back to (Field_SceneChangeTick
                                         ; saves Loc_Id here before warping)
!Loc_ReturnX = $07                       ; 8-bit return tile X (leader X saved by
                                         ; Field_SceneChangeTick)
!Loc_ReturnY = $08                       ; 8-bit return tile Y (leader Y saved by
                                         ; Field_SceneChangeTick)
!Loc_ReturnFacing = $09                  ; 8-bit return facing (leader facing EOR 1 = turned around,
                                         ; Field_SceneChangeTick)
!Loc_PrevId = $0A                        ; 16-bit Loc_Id as it was at the last location load
                                         ; (Field_InitLoadState)
!Loc_PrevX = $0C                         ; 16-bit store of Loc_EntryX/Y at the last location load
                                         ; (Field_InitLoadState)
!Loc_PrevFacing = $0E                    ; 8-bit Loc_EntryFacing at the last location load
                                         ; (Field_InitLoadState)
!Loc_DestId = $12                        ; 16-bit warp destination location; Field_SceneChangeTick
                                         ; copies it to Loc_Id before restarting
!Loc_DestX = $14                         ; 16-bit load: destination tile X/Y, copied to Loc_EntryX/Y
                                         ; by Field_SceneChangeTick
!Loc_DestFacing = $16                    ; 8-bit destination facing, copied to Loc_EntryFacing by
                                         ; Field_SceneChangeTick

; --- Field state flags (dp) ---
!Field_Unk0F = $0F                       ; 8-bit; only zeroed (Field_InitLoadState) in matched code
!Field_Unk10 = $10                       ; 8-bit; must be 0 for the menu/pause entry paths in
                                         ; Field_PauseAndMenuInput and Field_FadeToBankC2Mode5
!Field_Unk11 = $11                       ; 8-bit; must be 0 for the Start-pause loop in
                                         ; Field_PauseAndMenuInput
!Field_SceneFlags = $17                  ; 8-bit scene-change request flags read by
                                         ; Field_SceneChangeTick: bit 7 = fade out then warp to
                                         ; Loc_Dest*, bit 6 = fade out then reload, bit 4 = run a
                                         ; tile-animation mode handler; DefaultHandler also uses bits
                                         ; 0/1/5
!Field_FadeFlags = $18                   ; 8-bit active-fader flags: bit 1 = brightness fade running
                                         ; (Fade_StepBrightness), bit 3 = fixed-colour fade running
                                         ; (Fade_StepFixedColor), bit 6 = set after a reload
                                         ; (Field_SceneChangeTick/Field_RunBankC2Mode5)
!Fade_BrightnessSaved = $1A              ; 8-bit Fade_Brightness saved while the Start-pause dims the
                                         ; screen (Field_PauseAndMenuInput)
!Field_Unk1E = $1E                       ; 8-bit; cleared when the post-load fade-in finishes
                                         ; (Field_FadeInAfterReload)
!Field_ControlEnabled = $1F              ; 8-bit; nonzero lets the pause/menu paths run
                                         ; (Field_PauseAndMenuInput, Field_FadeToBankC2Mode5); saved
                                         ; and cleared around Field_FrameUpdate during fades.
                                         ; Inferred: player control enable
!Field_Unk20 = $20                       ; 8-bit; set to 1 by Field_InitLoadState; nonzero makes
                                         ; Field_FrameUpdate run Map_Unk8A6D
!Field_BankC2Arg = $25                   ; 8-bit; picks the BankC2_Entry8000 argument on the fade-out
                                         ; path of Field_SceneChangeTick (0 -> Field_RunBankC2Mode5
                                         ; with 5; bit 7 -> bits 7-6 as A, bits 5-0 as X; else bit 0
                                         ; ? 0 : 6). What bank $C2 does with it is not traced (was
                                         ; Field_ExitMenuArg; nothing shows it picks a menu)
!Field_Unk26 = $26                       ; 8-bit state index; EngFD_UnkC2C1 dispatches on it;
                                         ; Field_FadeToBankC2Mode5 toggles bits 0-1
!Field_Unk27 = $27                       ; 8-bit; cleared with Field_Unk26 by Field_SaveState
!Field_HdmaEnable = $28                  ; 8-bit HDMA channel mask: the NMI handler writes it to HDMAEN
                                         ; ($C0:EC48); Field_InitLoadState sets $5F (was Field_Unk28)
!Field_Unk29 = $29                       ; 8-bit countdown; Field_Unk1F87 dispatches on it;
                                         ; Field_SaveState forces it to 1 when nonzero
!Field_Unk2A = $2A                       ; 8-bit; Field_CheckTileInFront stores the treasure outcome
                                         ; here (TreasureKind_*) as it starts Field_Unk29 = 1
!Field_Unk2B = $2B                       ; 16-bit; only zeroed (Field_InitLoadState) in matched code
!Field_Unk2D = $2D                       ; 8-bit; only zeroed (Field_InitLoadState) in matched code
!Field_Unk2E = $2E                       ; 8-bit; Field_CheckTileInFront stores the leader's object
                                         ; slot here as it starts Field_Unk29 = 1
!Field_Unk2F = $2F                       ; 8-bit; only zeroed (Field_InitLoadState) in matched code
!Field_Unk30 = $30                       ; 8-bit; zeroed by Field_InitLoadState and by
                                         ; Field_CheckTileInFront as it starts Field_Unk29 = 1
!Field_Unk32 = $32                       ; 8-bit; zeroed by Field_CheckTileInFront as it starts
                                         ; Field_Unk29 = 1
!Field_Unk34 = $34                       ; 16-bit; when $FFFF, Field_ActionButton swallows one press
                                         ; of Pad_Unk00F6 bit 7 and resets it to 0; Sub_1ADF
                                         ; clears it on button bit 7 of Pad_Unk00F6
!Field_Unk38 = $38                       ; 8-bit step of Field_Unk885A (1, 2; it clears it when done);
                                         ; DefaultHandler sets it to 1. Field_DpadDispatch does
                                         ; nothing while it is nonzero
!Field_EventHook = $39                   ; 8-bit; Field_EventHookDispatch runs table entry (value -
                                         ; 1) when nonzero; most handlers drive window (masking)
                                         ; effects and clear it (or move it on) when done; hooks 3
                                         ; and 11 never clear it themselves
!WinFx_CenterX = $3A                     ; 8-bit; hooks 1, 2, 4 and 5 hand it to BankC3_Entry0008 as
                                         ; WinFx_ArgX (inferred: the shape's centre X)
!WinFx_CenterY = $3B                     ; 8-bit; handed over as WinFx_ArgY (inferred: centre Y)
!WinFx_Size = $3C                        ; 8-bit; handed over as WinFx_ArgSize; hooks 1/4 count it up
                                         ; to WinFx_SizeLimit, hooks 2/5 down to 0, hook 12 by 2s.
                                         ; Hdma_InitChannelsFD also reads its bit 0 (channel 7's
                                         ; register)
!WinFx_SizeLimit = $3D                   ; 8-bit; WinFx_Size limit for hooks 1 and 4
!Field_Unk44 = $44                       ; 8-bit flags; Field_UnkAF4E acts on bits 0/1
!Pad_Unk00F6Latch = $50                  ; 8-bit; GameLoop_FrameBody ORs Pad_Unk00F6 into it every
                                         ; frame
!Pad_PressedLatch = $51                  ; 8-bit; GameLoop_FrameBody ORs the low byte of Pad_Pressed
                                         ; into it every frame
!Field_Unk53 = $53                       ; 8-bit flags; EngFD_UnkC2C1 skips when bit 0 is set;
                                         ; DefaultHandler sets/clears bit 7; Field_PauseAndMenuInput
                                         ; clears it in the pause loop
!Field_Unk54 = $54                       ; 8-bit request flags read by Field_ServiceUnk54: bit 4 = write
                                         ; one staff-credits line per frame, bits 2-3 = run
                                         ; Map_ClearBufC800, bit 5 = watch Field_TileStepX/Y against the
                                         ; Map_Unk1D0A-1D10 box; zeroed at load
!Field_Unk55 = $55                       ; 8-bit; set to 1 by Field_InitLoadState, no other matched use
!Field_Unk58 = $58                       ; 16-bit; only zeroed (Field_InitLoadState) in matched code
!Field_Unk62 = $62                       ; 8-bit selector handed to Sub_1ADF in A (1, 2, else);
                                         ; blocks the pause/menu paths and Field_DpadDispatch when
                                         ; nonzero
!Field_Unk63 = $63                       ; 8-bit index stepped up/down by Sub_1ADF and clamped to
                                         ; Field_Unk64/65; $80 at load
!Field_Unk64 = $64                       ; 8-bit wrap value for Field_Unk63 (Sub_1ADF)
!Field_Unk65 = $65                       ; 8-bit limit for Field_Unk63 (Sub_1ADF)
!Field_Unk66 = $66                       ; 8-bit; Sub_1ADF saves Field_Unk63 here before forcing it
                                         ; to 4
!Field_Unk68 = $68                       ; 8-bit; set to 5 by Field_InitLoadState, no other matched use
!Field_UnkAB = $AB                       ; 8-bit; saved to/restored from SceneSave_UnkAB by
                                         ; Field_SaveState/Party_ReinitIfChanged
!Field_UnkAC = $AC                       ; 8-bit; saved/restored with Field_UnkAB
!Field_UnkAD = $AD                       ; 8-bit; saved/restored with Field_UnkAB
!Field_E4Ptr0 = $AF                      ; 24-bit pointer into bank $E4; low word from RomE4_PtrInit,
                                         ; bank byte $E4 (Field_InitLoadState)
!Field_E4Ptr1 = $B2                      ; 24-bit pointer into bank $E4 (as Field_E4Ptr0)
!Field_E4Ptr2 = $B5                      ; 24-bit pointer into bank $E4 (as Field_E4Ptr0)
!Field_E4Ptr3 = $B8                      ; 24-bit pointer into bank $E4 (as Field_E4Ptr0)
!Field_UnkBB = $BB                       ; 8-bit; zeroed at load; LocLoad_Unk0A14 skips its work when
                                         ; nonzero
!Field_UnkBC = $BC                       ; 8-bit; only zeroed (Field_InitLoadState) in matched code
!Field_UnkEB = $EB                       ; 8-bit object slot the action button acts on, $80 = none:
                                         ; Field_FindObjInFront stores the object it finds;
                                         ; Field_ActionButton reads it. $80 at load; Field_FrameUpdate
                                         ; resets it to $80 every frame
!Field_Unk0400Copy = $F8                 ; 8-bit copy of Eng_Unk0400 taken by Field_InitLoadState
!Field_MapRedrawSel = $45                ; 8-bit; DefaultHandler (Field_SceneFlags bit 5) runs
                                         ; Field_BuildC800Mode1/2/4 for 1/2/4, modes 1 and 2
                                         ; (swapping the two tilemap bases) for 3, then clears it
!Field_MapRedrawDone = $46               ; 8-bit; DefaultHandler stores the redraw step just done
                                         ; (1-4)

; --- Fades (dp) ---
!Fade_Brightness = $19                   ; 8-bit screen brightness 0-15: Fade_StepBrightness steps it
                                         ; toward Fade_BrightnessTarget, Field_FadeInAfterReload
                                         ; raises it to 15, Field_PauseAndMenuInput halves it while
                                         ; paused; Field_SceneChangeTick counts it down before a warp
!Fade_BrightnessTarget = $1B             ; 8-bit target for Fade_Brightness (Fade_StepBrightness)
!Fade_BrightnessDelay = $1C              ; 8-bit frames between Fade_Brightness steps
                                         ; (Fade_StepBrightness reload value)
!Fade_BrightnessTimer = $1D              ; 8-bit countdown to the next Fade_Brightness step
                                         ; (Fade_StepBrightness)
!Fade_FixedColor = $21                   ; 8-bit COLDATA-style value ($E0 = all channels, intensity 0
                                         ; at load) stepped toward Fade_FixedColorTarget by
                                         ; Fade_StepFixedColor
!Fade_FixedColorTarget = $22             ; 8-bit target for Fade_FixedColor (Fade_StepFixedColor)
!Fade_FixedColorDelay = $23              ; 8-bit frames between Fade_FixedColor steps
                                         ; (Fade_StepFixedColor reload value)
!Fade_FixedColorTimer = $24              ; 8-bit countdown to the next Fade_FixedColor step
                                         ; (Fade_StepFixedColor)

; --- DMA arguments (ClearRAMDMA, VramDma_Upload) (dp) ---
!VramDma_Addr = $48                      ; 16-bit VRAM word address for VramDma_Upload (VMADDL)
!VramDma_Mode = $4A                      ; 8-bit DMAP7 value for VramDma_Upload (callers seen store 1:
                                         ; word writes to VMDATAL/H)
!DmaFill_Dest = $4B                      ; 16-bit WRAM destination address for ClearRAMDMA
!DmaFill_Bank = $4D                      ; 8-bit WRAM destination bank for ClearRAMDMA
!DmaFill_Size = $4E                      ; 16-bit byte count for ClearRAMDMA
!VramDma_Src = $4B                       ; alias of DmaFill_Dest: 16-bit A-bus source address for
                                         ; VramDma_Upload
!VramDma_SrcBank = $4D                   ; alias of DmaFill_Bank: 8-bit source bank for VramDma_Upload
!VramDma_Size = $4E                      ; alias of DmaFill_Size: 16-bit byte count for VramDma_Upload

; --- Party and object slots (dp) ---
!Obj_Cur = $6D                           ; 16-bit current object slot offset (object number x 2; high
                                         ; byte kept 0); index into the Obj_* tables
!Obj_CurHi = $6E                         ; 8-bit high byte of Obj_Cur; zeroed so 16-bit X loads of
                                         ; Obj_Cur work (Oam_BuildShadow, Party_ReinitIfChanged)
!Chr_ObjSlot = $8D                       ; 7 bytes, one per playable character: that character's
                                         ; object slot, $80 = none (Field_InitLoadState sets $80;
                                         ; Party_ReinitIfChanged re-inits each live one when the
                                         ; party changes)
!Party_MembersCache = $94                ; 3 bytes: copy of Party_Members taken at load;
                                         ; Party_ReinitIfChanged compares to detect a party change
!Party_ObjSlot = $97                     ; 3 words ($97/$99/$9B): object slot of each party member,
                                         ; $80 = none (Field_SaveState, Field_RestoreState,
                                         ; Party_ReinitIfChanged); $97 is the leader
!Party_ObjSlot1 = $99                    ; 16-bit object slot of party member 2 (= Party_ObjSlot+2)
!Party_ObjSlot2 = $9B                    ; 16-bit object slot of party member 3 (= Party_ObjSlot+4)
!Field_BattleObjList = $9D               ; up to 12 object offsets + $80 end marker, filled by Field_Unk0617
                                         ; (objects of kind 5/6 near the screen); Scene_Unk024C treats a
                                         ; negative first entry as "no battle"
!Field_UnkAEObj = $AE                    ; 8-bit object slot (or $80 = none) that Field_RestoreState
                                         ; runs Spr_LoadLargeObj on after a reload

; --- OAM shadow build (Oam_BuildShadow / Spr_AppendToOam) (dp) ---
!Oam_Range1PrevEnd = $7B                 ; 16-bit OAM shadow address where range 1 ended last frame;
                                         ; Oam_BuildShadow hides entries from the new end up to here
!Oam_Range2PrevEnd = $7D                 ; 16-bit previous-frame end of range 2 (as
                                         ; Oam_Range1PrevEnd)
!Oam_Range3PrevEnd = $7F                 ; 16-bit previous-frame end of range 3 (as
                                         ; Oam_Range1PrevEnd)
!Oam_Range1HiPtr = $81                   ; 16-bit write pointer into the OAM high-table shadow for
                                         ; range 1 (starts $0907); Spr_AppendToOam stores one byte
                                         ; per 4 tiles
!Oam_Range1HiUnk = $83                   ; 16-bit; zeroed with Oam_Range1HiPtr each frame
                                         ; (Oam_BuildShadow), no other matched use
!Oam_Range2HiPtr = $85                   ; 16-bit high-table write pointer for range 2 (starts $091A)
!Oam_Range2HiUnk = $87                   ; 16-bit; zeroed each frame (Oam_BuildShadow), no other matched
                                         ; use
!Oam_Range3HiPtr = $89                   ; 16-bit high-table write pointer for range 3 (starts $0901)
!Oam_Range3HiUnk = $8B                   ; 16-bit; zeroed each frame (Oam_BuildShadow), no other matched
                                         ; use
!Oam_Range1LoPtr = $DB                   ; 16-bit write pointer into the OAM low-table shadow for
                                         ; range 1 (starts $0770); Spr_AppendToOam aims WMADD here
                                         ; and advances it 4 bytes per tile
!Oam_Range2LoPtr = $DD                   ; 16-bit low-table write pointer for range 2 (starts $08A0)
!Oam_Range3LoPtr = $DF                   ; 16-bit low-table write pointer for range 3 (starts $0710)

; --- Audio (dp) ---
!Audio_SfxUnkFA = $FA                    ; 8-bit sound-effect id, $45 at load; no matched reader
!Audio_SfxTileAnimB = $FB                ; 8-bit sound-effect id passed by Audio_PlayTileSfxB
                                         ; (DefaultHandler tile animation); $65 at load
!Audio_SfxTileAnimA = $FC                ; 8-bit sound-effect id passed by Audio_PlayTileSfxA (Mode*
                                         ; tile-animation handlers); $53 at load

; --- Generic (dp) ---
!Dp_TableStart = $00                     ; offset 0 from DP, for loops that point DP at a table
                                         ; (Obj_ResetStates points it at Obj_State); not a field-page
                                         ; variable

; --- Tile animation (door/switch tiles; Field_SceneChangeTick bit 4, DefaultHandler bit 1) (dp) ---
!Field_TileAnimX = $5B                   ; 8-bit map column of the tile that started the animation; a
                                         ; 16-bit load takes Field_TileAnimY as the high byte, giving
                                         ; the Map_TileProps index
!Field_TileAnimY = $5C                   ; 8-bit map row of that tile (high byte of the Map_TileProps
                                         ; index). Earlier comments swapped row and column
!Field_TileStepX = $5D                   ; 8-bit map column for DefaultHandler's single-tile step;
                                         ; 16-bit load = Map_TileProps index
!Field_TileStepY = $5E                   ; 8-bit map row for DefaultHandler's single-tile step
!Field_VramQueueFlags = $5F              ; 8-bit; bit 4 = TileAnim_VramAddrs filled by a
                                         ; Mode*_Handler, bit 1 = TileAnim_StepVramAddrs filled by
                                         ; DefaultHandler (inferred: picked up by the tilemap
                                         ; uploader)
!TileAnim_PairCount = $60                ; 8-bit tiles changed / 2, minus 1: 0 for ModeE6 (2 tiles),
                                         ; 1 for ModeEC/EE (4), 2 for ModeFA/FC (6). Inferred from
                                         ; the setters and the VRAM uploader at $C0:ED24, which
                                         ; sends 8/16/24 VRAM words for 0/1/2 (not converted yet)
!TileAnim_StepKind = $61                 ; 8-bit; DefaultHandler sets 0 when the stepped tile was
                                         ; $FE, 1 when it was $E0

; --- Scratch (dp) ---
!Eng_Scratch = $D9                       ; 16-bit general scratch, reused by many routines
!TileAnim_OriginX = $DB                  ; alias of Oam_Range1LoPtr's slot used as scratch by the
                                         ; tile-animation handlers: copy of Map_TileOriginX
!TileAnim_OriginY = $DD                  ; alias of Oam_Range2LoPtr's slot used as scratch by the
                                         ; tile-animation handlers: copy of Map_TileOriginY
!Bg_RowWordOfs = $D9                     ; $D9 in Bg_TilemapIndex64x32: row * 32
!Field_FindFacing2 = $DB                 ; alias of Oam_Range1LoPtr's slot in Field_FindObjInFront:
                                         ; 16-bit leader facing x 2 (Field_ObjInReachTable offset)
!Field_FindLeaderX = $C3                 ; alias of Spr_BaseX in Field_FindObjInFront: 16-bit
                                         ; leader Obj_PosX
!Field_FindLeaderY = $C5                 ; alias of Spr_BaseY in Field_FindObjInFront: 16-bit
                                         ; leader Obj_PosY
!Field_FrontTile = $DB                   ; alias of Oam_Range1LoPtr's slot in Field_CheckTileInFront:
                                         ; 16-bit map index (row << 8 | column) of the tile the
                                         ; Field_TileInFront* handlers looked at
!Field_TreasureRec = $DD                 ; alias of Oam_Range2LoPtr's slot in Field_CheckTileInFront:
                                         ; 16-bit TreasureRom offset of the record found

; --- Sprite build scratch (Spr_AppendToOam .. Spr_Place24) (dp) ---
!Spr_BaseX = $C3                         ; 16-bit: Obj_ScreenX of the object being built; each tile's
                                         ; SprTile.OfsX is added to it
!Spr_BaseY = $C5                         ; 8-bit: low byte of the object's 9-bit Obj_ScreenY; 16-bit
                                         ; stores also write Spr_BaseYHi
!Spr_BaseYHi = $C6                       ; 8-bit: bit 8 of Obj_ScreenY; nonzero selects the "below
                                         ; the screen" Y clamp
!Spr_TileCount = $C9                     ; 8-bit loop counter: tiles left to copy/clamp
!Spr_HiBits = $E5                        ; 8-bit: OAM high-table bits being packed, 2 per tile (X bit
                                         ; 8 of each tile)
!Spr_HiBitTmp = $E6                      ; 8-bit: one tile's X bit 8 while packing Spr_HiBits
!Spr_HiBitTmp2 = $E7                     ; 8-bit: another tile's X bit 8 while packing Spr_HiBits
!Spr_FirstRec = $D9                      ; alias of Eng_Scratch in the sprite builders: the object's
                                         ; first SprTile record offset (Obj_TileRecOfs)
!Spr_GroupRec = $E7                      ; alias of Spr_HiBitTmp2 in the 8/12-tile builders: 16-bit
                                         ; record offset where the current group of 4 tiles starts

; --- Object graphics load scratch (Spr_LoadLargeObj, Spr_CopyTile*, the frame builders) (dp) ---
!Spr_GfxPtr = $CD                        ; 24-bit pointer (bank in byte +2) to the object's tile
                                         ; graphics: Obj_GfxOfs / Obj_GfxBank
!Spr_WramPtr = $D0                       ; 24-bit pointer (bank $7F in byte +2) to where the next
                                         ; tile is written in the WRAM tile buffer
!Spr_FramePtr = $D3                      ; 24-bit pointer (bank in byte +2) to the object's frame
                                         ; data: tile words, then position bytes
!Spr_SavedY = $C5                        ; alias of Spr_BaseY in the tile copiers: the caller's Y
                                         ; (frame-data index) saved across the copy

; --- Object frame queue and animation (Obj_AnimTickAndQueue, Field_ProcessAnimQueue) (dp) ---
!ObjQ_ScanlineLimit = $6B                ; 16-bit: Field_ProcessAnimQueue stops building frames once
                                         ; the V counter reaches this (unless past line 240)
!ObjQ_Head = $76                         ; 8-bit: first object waiting for a frame build ($80 = queue
                                         ; empty); objects are linked through Obj_QueueNext
!ObjQ_Tail = $77                         ; 8-bit: last object in the frame-build queue ($80 = empty)
!ObjQ_Unk78 = $78                        ; 8-bit; when 2, Obj_AnimTickAndQueue queues kind-1/2
                                         ; objects at the head and clears it; zeroed at load
!VramQ_Pos = $79                         ; 8-bit byte offset of the next free entry in the VRAM
                                         ; upload queue (VramQ_*); cleared by Field_ProcessAnimQueue
!Anim_RowAddr = $C1                      ; 16-bit scratch: Obj_AnimTimeTbl + row*4, the current
                                         ; animation row in bank $E4 (Obj_AnimTickAndQueue)
!Anim_FramePtr = $D6                     ; 24-bit pointer (bank $E4 in byte +2) to the current frame-
                                         ; number entry (Obj_AnimFrameLookup)
!Spr_NewFrame = $EE                      ; 8-bit: frame number being built (saved across
                                         ; SprBuf_Alloc*)
!Anim_Column = $D9                       ; alias of Eng_Scratch in Obj_AnimFrameLookup: the column
                                         ; (frame within the row)
!Spr_AttrBase = $D9                      ; alias of Eng_Scratch in the frame builders: Obj_OamAttr |
                                         ; Obj_VramTile high byte, before the priority bits

;
; Absolute names. Low WRAM ($0000-$1FFF) is given as a 16-bit address
; (reached through the bank-$00 mirror); other WRAM and ROM as a full
; 24-bit address. A `.w` access to a 24-bit name keeps the low 16 bits:
; the routine sets DB to the name's bank (each such routine says so).
;

; --- Engine / interrupts ---
!Pad_Pressed = $00F0                     ; 16-bit newly pressed buttons, remapped: low = A X L R B Y
                                         ; Select Start (bits 7-0), high = Up Down Left Right (bits
                                         ; 3-0). Inferred from the pad reader at $C2:84F0 and Start
                                         ; (bit 0) toggling the pause loop in Field_PauseAndMenuInput
!Pad_Unk00F6 = $00F6                     ; 8-bit button-style flags (same layout as Pad_Pressed?):
                                         ; bit 6 opens the menu path and bit 0 the
                                         ; Field_FadeToBankC2Mode5 path in Field_PauseAndMenuInput;
                                         ; bit 7 clears Field_Unk34 (Sub_1ADF) and is the action
                                         ; button of Field_ActionButton
!Pad_Unk00F7 = $00F7                     ; 8-bit; Sub_1ADF: bit 2 steps Field_Unk63 up, bit 3 steps
                                         ; it down (Down/Up in the Pad_Pressed layout?)
!Pad_Unk00F8 = $00F8                     ; 8-bit; Sub_1ADF: bit 7 sets Field_Unk62 = 3
!Pad_Unk00F9 = $00F9                     ; 8-bit; bits 0-3 index Field_DpadDispatch's handler table
                                         ; (Up Down Left Right in the Pad_Pressed high-byte layout?)
!Eng_Unk0400 = $0400                     ; 8-bit; Field_InitLoadState copies it to Field_Unk0400Copy
!Field_FadeBusy = $0407                  ; 8-bit; $FF while a pause/fade loop runs
                                         ; (Field_PauseAndMenuInput, Field_FadeToBankC2Mode5),
                                         ; cleared after (Field_FadeInAfterReload,
                                         ; Field_RunBankC2Mode5)
!Ppu_Unk0BD7 = $0BD7                     ; 8-bit; probably the TM (main screen) value: $C0:0691 copies
                                         ; it, Ppu_Unk0BD8, 0, 0, 2 and Ppu_Unk0BDF to $7E:2C66-6B,
                                         ; the order of TM, TS, TMW, TSW, CGWSEL, CGADSUB (not traced
                                         ; to the register)
!Ppu_Unk0BD8 = $0BD8                     ; 8-bit; probably the TS (sub screen) value (as Ppu_Unk0BD7)
!Ppu_W12SelShadow = $0BD9                ; 8-bit; the NMI handler writes it to W12SEL ($C0:EC19)
!Ppu_W34SelShadow = $0BDA                ; 8-bit; the NMI handler writes it to W34SEL ($C0:EC1F)
!Ppu_WObjSelShadow = $0BDB               ; 8-bit; the NMI handler writes it to WOBJSEL ($C0:EC25)
!Ppu_Wh2Shadow = $0BDC                   ; 8-bit; the NMI handler writes it to WH2 ($C0:EC2B)
!Ppu_Wh3Shadow = $0BDD                   ; 8-bit; the NMI handler writes it to WH3 ($C0:EC31)
!Ppu_CgwSelShadow = $0BDE                ; 8-bit; the NMI handler writes it to CGWSEL ($C0:EC37); 2
                                         ; at load (Field_InitLoadState)
!Ppu_Unk0BDF = $0BDF                     ; 8-bit; probably the CGADSUB value: copied after the CGWSEL
                                         ; slot into $7E:2C6B by $C0:06AF (see Ppu_Unk0BD7)
!Ppu_Unk0BE0 = $0BE0                     ; 8-bit; written with Ppu_Unk0BDF by Field_HookWinFixedB,
                                         ; and by event code at $C0:3D2C-3D74; no reader traced
!Field_Unk0BD9 = !Ppu_W12SelShadow       ; older name of Ppu_W12SelShadow, still used by
                                         ; Field_InitLoadState (rename there on its next edit)
!Field_Unk0BDA = !Ppu_W34SelShadow       ; older name of Ppu_W34SelShadow (as Field_Unk0BD9)
!Field_Unk0BDB = !Ppu_WObjSelShadow      ; older name of Ppu_WObjSelShadow (as Field_Unk0BD9)
!Field_Unk0BDE = !Ppu_CgwSelShadow       ; older name of Ppu_CgwSelShadow (as Field_Unk0BD9)
!Credits_TextPos = $0BE1                 ; 16-bit offset of the next staff-credits character in
                                         ; Credits_Text; Field_ServiceUnk54 advances it one line per call
                                         ; (set by event code at $C0:3ECF)
!Credits_Column = $0BE3                  ; 8-bit; bits 0-4 = first tilemap column of each credits line
                                         ; (Field_ServiceUnk54; set by event code at $C0:3F18)
!Credits_Row = $0BE4                     ; 8-bit credits line counter; bits 0-5 pick the tilemap row
                                         ; (Field_ServiceUnk54 counts it up; set at $C0:3F20)
!Credits_VramAddr = $0BE5                ; 16-bit VRAM word address of the credits line just built;
                                         ; the NMI routine at $C0:EC77 DMAs the line there
!Credits_DmaSize = $0BE7                 ; 16-bit byte count of that DMA ($C0:EC77)
!Field_Unk0BE9 = $0BE9                   ; 8-bit; zeroed by Field_InitLoadState, no other matched use
!Field_Unk1DF9 = $1DF9                   ; 8-bit; saved to SceneSave_Unk1DF9 around the menu
                                         ; (Field_SaveState / Field_RestoreState)
!Audio_CmdId = $1E00                     ; 8-bit sound-driver command byte ($19 = play sound effect),
                                         ; sent by Audio_DriverCommand
!Audio_CmdArg0 = $1E01                   ; 8-bit first command argument (sound-effect id in
                                         ; Audio_PlayTileSfxA)
!Audio_CmdArg1 = $1E02                   ; 8-bit second command argument (low byte of the leader's
                                         ; Obj_ScreenX in Audio_PlaySfxAtLeader)
!Field_Unk7E2000 = $7E2000               ; 16-bit; zeroed by Field_InitLoadState, no other matched use
!Treasure_Gold = $0200                   ; 16-bit gold amount of the last treasure taken
                                         ; (Field_CheckTileInFront, DB=$00; reader not traced)
!Field_Unk02A1 = $02A1                   ; 8-bit; zeroed by Field_CheckTileInFront as it starts
                                         ; Field_Unk29 = 1
!Map_TreasureIdx = $7E70C0               ; one byte per map tile, index row << 8 | column (as
                                         ; Map_TileProps): bit 7 clear = the tile holds treasure
                                         ; record (value & $7F) of the location; set = none
!Party_Members = $7E2980                 ; 3 bytes: character id of each party member
                                         ; (Party_ReinitIfChanged re-inits the character objects when
                                         ; they change)
!Field_Unk7E2989 = $7E2989               ; 8-bit; zeroed by Field_InitLoadState, no other matched use
!Eng_Unk7F0000 = $7F0000                 ; 8-bit; Field_FadeToBankC2Mode5 only proceeds when it is >=
                                         ; $49 (purpose unknown)
!Treasure_Flags = $7F0001                ; 64 bytes: one bit per treasure number (bit n & 7 of byte
                                         ; n >> 3, BitSet order), set by Field_CheckTileInFront when
                                         ; the treasure is taken; a set bit means already opened
!Treasure_ItemId = $7F0200               ; 16-bit item id of the last treasure item taken
                                         ; (Field_CheckTileInFront; reader not traced, probably the
                                         ; message)
!Field_Unk7F03FE = $7F03FE               ; 8-bit; when 1-2 Field_RestoreState stacks party members
                                         ; 2/3 on the leader and sets it to 3
!Rom_SineTable = $C0F900                 ; 1024 B in ROM: |sin| for 1024 steps per turn, $00 at +$000/+$200,
                                         ; $FF at +$100/+$300 (the table the battle code calls !BattleRom_SineTable)
!RomE4_PtrInit = $E4FFE0                 ; 4 words in ROM: initial low words of Field_E4Ptr0-3
                                         ; (Field_InitLoadState)

; --- Location event data / saved field state ---
!Evt_ObjCount = $7F2000                  ; 8-bit count of location objects; Obj_ResetStates clears
                                         ; that many Obj_State entries
!Evt_Data = $7F2001                      ; location event data; begins with 16 word function offsets
                                         ; per object (32 bytes, index Obj_Cur*16), and all offsets
                                         ; are relative to it; opcode streams end at opcode $00
                                         ; (Evt_RunObjInit)
!SceneSave_PartyPosX = $7F1D09           ; 3 words: party members' Obj_PosX saved by Field_SaveState,
                                         ; restored by Party_ReinitIfChanged
!SceneSave_PartyPosY = $7F1D0F           ; 3 words: party members' Obj_PosY (as above)
!SceneSave_PartyPrio = $7F1D15           ; 3 words: party members' Obj_PrioLow/High word (as above)
!SceneSave_UnkAB = $7F1D1B               ; 3 bytes: Field_UnkAB/AC/AD saved by Field_SaveState,
                                         ; restored by Party_ReinitIfChanged
!SceneSave_MapWords = $7F1D1E            ; 4 words: Map_Unk7F3728/3748/3768/3781 saved by
                                         ; Field_SaveState, restored by Field_RestoreState
!SceneSave_Unk1DF9 = $7F1D26             ; 8-bit Field_Unk1DF9 saved by Field_SaveState, restored by
                                         ; Field_RestoreState
!Map_Unk7F3728 = $7F3728                 ; 16-bit; saved/restored around bank $C2 (Field_SaveState,
                                         ; Field_RestoreState). An event opcode handler at $C0:3311
                                         ; stores two script bytes AND $7F into its low and high
                                         ; byte (an X/Y-like pair, inferred). Earlier notes called
                                         ; it scroll X0; nothing shows it is a scroll value
!Map_Unk7F3748 = $7F3748                 ; 16-bit; as Map_Unk7F3728 (event handler at $C0:3398)
!Map_Unk7F3768 = $7F3768                 ; 16-bit; as Map_Unk7F3728 (event handler at $C0:3421)
!Map_Unk7F3781 = $7F3781                 ; 16-bit; saved/restored with Map_Unk7F3728; no event
                                         ; handler stores it in matched or traced code
!ObjX_Unk7F0580 = $7F0580                ; per-object word ($80-byte table in bank $7F), zeroed by
                                         ; Evt_RunObjInit. With the seven tables after it, one per
                                         ; Obj_Unk1C00 level (Evt_PrioStride apart):
                                         ; Evt_StartTargetFunc1 saves Obj_ScriptPos at +level*$80
!ObjX_Unk7F0600 = $7F0600                ; per-object word, zeroed by Evt_RunObjInit
!ObjX_Unk7F0680 = $7F0680                ; per-object word, zeroed by Evt_RunObjInit
!ObjX_Unk7F0700 = $7F0700                ; per-object word, zeroed by Evt_RunObjInit
!ObjX_Unk7F0780 = $7F0780                ; per-object word, zeroed by Evt_RunObjInit
!ObjX_Unk7F0800 = $7F0800                ; per-object word, zeroed by Evt_RunObjInit
!ObjX_Unk7F0880 = $7F0880                ; per-object word, zeroed by Evt_RunObjInit
!ObjX_Unk7F0900 = $7F0900                ; per-object word, zeroed by Evt_RunObjInit

; --- OAM shadow ---
!Oam_LowTable = $0700                    ; 512-byte OAM low-table shadow (4 bytes per sprite: X, Y,
                                         ; tile, attr)
!Oam_HighTable = $0900                   ; 32-byte OAM high-table shadow (2 bits per sprite)

; --- Per-object tables (index = object number x 2, Obj_Cur) ---
!Obj_ScreenX = $0A00                     ; 16-bit per object: screen X of the sprite origin (sprite
                                         ; builders add each tile's SprTile.OfsX);
                                         ; Audio_PlaySfxAtLeader passes the leader's low byte as
                                         ; Audio_CmdArg1, presumably for panning
!Obj_DrawBucket = $0E00                  ; 64 words: first object of each draw bucket (low byte; bit
                                         ; 7 = empty); Oam_BuildShadow walks them from the last
!Obj_DrawNext = $0E81                    ; 8-bit per object: next object in the same draw bucket (bit
                                         ; 7 = end)
!Obj_ScriptPos = $1180                   ; 16-bit per object: Evt_Data offset where the object's
                                         ; script continues (Evt_RunObjInit sets it past the init
                                         ; function)
!Obj_Facing = $1600                      ; 8-bit per object facing; EOR 1 turns it around
                                         ; (Field_SceneChangeTick); Obj_AnimFrameLookup uses facing
                                         ; 0-3 as the multiple of Obj_AnimFacingStride (its tests
                                         ; also send $80/$81 to 3 and $82-$FF to 1)
!Obj_PosX = $1800                        ; 16-bit per object X position; the high byte is the tile
                                         ; column (Field_SaveState copies it to Loc_EntryX)
!Obj_TileX = $1801                       ; 8-bit high byte of Obj_PosX: tile column
!Obj_PosY = $1880                        ; 16-bit per object Y position; high byte is the tile row
!Obj_TileY = $1881                       ; 8-bit high byte of Obj_PosY: tile row
!Obj_State = $1B00                       ; per-object byte read by Spr_PrepareTiles: 0 = nothing to
                                         ; draw; bits 0-6 count finished Obj_BuildFrame* passes (INC
                                         ; per pass); $80 = SprTile records up to date.
                                         ; Obj_ResetStates zeroes it for every location object
!Obj_Unk1C00 = $1C00                     ; 8-bit per object; Evt_RunObjInit sets 7 after the init
                                         ; function; Evt_StartTargetFunc1 needs it >= 2, saves
                                         ; Obj_ScriptPos in the ObjX_Unk7F0580 table of that level
                                         ; and sets 1 (looks like the priority of the running
                                         ; function, lower = more urgent; not established)
!Obj_Unk1C01 = $1C01                     ; 8-bit per object; nonzero blocks Evt_StartTargetFunc1
!Obj_Unk1000 = $1000                     ; 8-bit per object; bit 7 blocks Evt_StartTargetFunc1
!Obj_Unk1001 = $1001                     ; 8-bit per object; zeroed by Evt_StartTargetFunc1
!Obj_Unk1A01 = $1A01                     ; 8-bit per object; zeroed by Evt_StartTargetFunc1
!Obj_Unk1A80 = $1A80                     ; 8-bit per object; zeroed by Evt_StartTargetFunc1
!Obj_ScreenY = $0A80                     ; 16-bit per object: screen Y of the sprite origin; the
                                         ; builders use the low 9 bits
!Obj_OamFlags = $0F80                    ; 8-bit per object; bits 2-3 pick the OAM shadow range (0 =
                                         ; range 1, bit 2 = range 2, bit 3 = range 3) in
                                         ; Spr_AppendToOam
!Obj_SprSize = $1201                     ; 8-bit per object; bits 0-1 = sprite size class: 0/1/2/3 =
                                         ; 4/8/12/24 tiles (Spr_PrepareTiles, Spr_AppendToOam)
!Obj_TileRecOfs = $1700                  ; 16-bit per object: offset of its first 8-byte record in
                                         ; SprTile/SprTileSrc
!Obj_OamHiA = $7F4F00                    ; 2 bytes per object (bank $7F): packed OAM high-table bytes
                                         ; for tiles 0-3 and 4-7. Lies where SprTile[104] would
                                         ; be, so the SprTile records stop below it
!Obj_OamHiB = $7F4B40                    ; 2 bytes per object (bank $7F): high-table bytes for tiles
                                         ; 8-11 and 12-15 (12-tile objects use the first, 24-tile
                                         ; objects both). Where SprTileSrc[104] would be
!Obj_OamHiC = $7F4F80                    ; 2 bytes per object (bank $7F): high-table bytes for tiles
                                         ; 16-23 (24-tile objects). Where SprTile[120] would be
!Eng_PtrBase = $0000                     ; base 0 for abs,X / abs,Y accesses whose index register
                                         ; holds the full address (e.g. Spr_AppendToOam storing at
                                         ; Oam_Range1HiPtr)
!Obj_TileBuf = $0D80                     ; 16-bit per object: address in bank $7F of its chunk of the
                                         ; WRAM tile buffer (SprBuf_Base + n*$200, set by
                                         ; SprBuf_Alloc*)
!Obj_LastFrame = $0F01                   ; 8-bit per object: frame number last built (frame builders
                                         ; skip when unchanged); Spr_LoadLargeObj clears it
!Obj_GfxBank = $1200                     ; 8-bit per object: bank of its tile graphics ($D2-$D5 ROM,
                                         ; or $7F WRAM); selects the Spr_CopyTile* variant
!Obj_GfxOfs = $1280                      ; 16-bit per object: offset of its tile graphics in
                                         ; Obj_GfxBank
!Obj_FrameBank = $1300                   ; 8-bit per object: bank of its frame data
!Obj_FrameOfs = $1380                    ; 16-bit per object: offset of its frame data in
                                         ; Obj_FrameBank
!Obj_PrioLow = $0C00                     ; 8-bit per object: attribute bits ORed into some of its
                                         ; tiles: in the 4-tile builders those with OfsY < $E8
                                         ; (Spr_UpperOfsY), in the 8/12-tile builders records 0-3.
                                         ; OAM priority bits by inference; which part of the
                                         ; sprite they cover is not established. Saved (as a word
                                         ; with Obj_PrioHigh) with the party positions
!Obj_PrioHigh = $0C01                    ; 8-bit per object: the same for the other tiles: OfsY >=
                                         ; $E8 in the 4-tile builders, records 4 and up in the
                                         ; 8/12-tile builders
!Obj_VramTile = $0D00                    ; 16-bit per object: first OAM tile number of its graphics
                                         ; (bits 0-8); the high byte also feeds the attributes. $68
                                         ; selects the alternate layout in the 12-tile builders
!Obj_VramTileHi = $0D01                  ; high byte of Obj_VramTile, ORed into the OAM attributes
                                         ; (tile bit 8)
!Obj_Unk0F00 = $0F00                     ; 8-bit per object; 0 = no frame to build
                                         ; (Obj_BuildSpriteFrameStep, Obj_BuildFrameLayout)
!Obj_OamAttr = $0F81                     ; 8-bit per object: OAM attribute bits (palette/priority)
                                         ; ORed into every tile
!Obj_QueueNext = $1081                   ; 8-bit per object: next object in the frame-build queue
                                         ; ($80 = not queued / end)
!Obj_Unk1100 = $1100                     ; 8-bit per object; bit 7 = skip; 0 = queue at the head; 1/2
                                         ; = queue at the tail (head when ObjQ_Unk78 = 2)
!Obj_FixedFrame = $1301                  ; 8-bit per object: frame number used when Obj_AnimMode = 3
                                         ; (no animation lookup)
!Obj_AnimFacingStride = $1480            ; 16-bit per object: bytes per facing in its frame-number
                                         ; table (Obj_AnimFrameLookup multiplies by the facing)
!Obj_AnimFrameTbl = $1500                ; 16-bit per object: offset in bank $E4 of its frame-number
                                         ; table
!Obj_AnimTimeTbl = $1580                 ; 16-bit per object: offset in bank $E4 of its frame-
                                         ; duration table
!Obj_AnimTimer = $1601                   ; 8-bit per object: frames until the next animation step
                                         ; (Obj_AnimTickAndQueue)
!Obj_AnimRow = $1680                     ; 8-bit per object: current animation (row of 4 frames) for
                                         ; modes 0/1
!Obj_AnimColumn = $1681                  ; 8-bit per object: frame within the animation row; $FF
                                         ; after the row ran out
!Obj_AnimMode = $1780                    ; 8-bit per object: 0/1 = normal, 2 = counted loops
                                         ; (ObjX_AnimLoops, row Obj_AnimRowAlt), 3 = fixed frame
!Obj_AnimRowAlt = $1781                  ; 8-bit per object: animation row used in mode 2
!Obj_Unk1A81 = $1A81                     ; 8-bit per object; must be 1..$7F for a frame build
!ObjX_AnimLoops = $7F0B01                ; 8-bit per object in bank $7F: loops left for animation
                                         ; mode 2
!AnimRom = $E40000                       ; bank $E4: object animation tables (frame numbers and
                                         ; durations), reached through Obj_AnimFrameTbl /
                                         ; Obj_AnimTimeTbl

; --- Saved field block (menu round trip) ---
!Field_SaveBlock = $0920                 ; start of the $14E0-byte WRAM block Field_StashSaveBlock
                                         ; copies to SceneSave_Buffer before the menu and
                                         ; Field_RestoreSaveBlock copies back
!SceneSave_Buffer = $7F2000              ; $7F:2000: destination of the Field_SaveBlock copy (same
                                         ; address as Evt_ObjCount, used at a different time)

; --- Map ---
!Map_TileProps = $7E3000                 ; one byte per map tile, row stride $100 (index = row*256 +
                                         ; column); values $E6/$EC/$EE/$FA/$FC select tile-animation
                                         ; modes. "Props" is a guess: matched code only uses it for
                                         ; tile-animation states

; --- Map / BG (page $1D00, also used as a direct page) ---
!Map_TileOriginX = $1D0A                 ; 16-bit; subtracted from (map column x 2) before wrapping
                                         ; into the 64x32 tilemap (inferred: BG scroll origin in 8x8
                                         ; tiles)
!Map_TileOriginY = $1D0E                 ; 16-bit; as Map_TileOriginX for rows
!Map_TilemapVram = $1D7C                 ; 16-bit VRAM word address of the tilemap the tile
                                         ; animations write to; DefaultHandler swaps it with
                                         ; Map_TilemapVram2 for redraw mode 3
!Map_TilemapVram2 = $1D82                ; 16-bit second tilemap base (swapped with Map_TilemapVram
                                         ; by DefaultHandler)
!Map_BgColBias = $1D99                   ; 8-bit (read through a 16-bit ADC, high byte masked off)
                                         ; added to the tilemap column
!Map_BgRowBias = $1D9A                   ; 8-bit (read through a 16-bit ADC, high byte masked off)
                                         ; added to the tilemap row
!TileAnim_StepVramAddrs = $09B2          ; 4 words: VRAM addresses of the four 8x8 tiles of
                                         ; DefaultHandler's stepped map tile (TL, TR, BL, BR)
!TileAnim_VramAddrs = $09CA              ; up to 24 words: VRAM addresses of the 8x8 tiles of each
                                         ; animated map tile, 4 per tile (TL, TR, BL, BR)

; --- Object tile buffer (bank $7F) ---
!SprBuf_Base = $7F3800                   ; WRAM tile buffer for object graphics, $0C00 bytes in
                                         ; $200-byte chunks handed out by SprBuf_Alloc*; chunks reach
                                         ; VRAM through the VramQ_* queue, except that
                                         ; Spr_LoadLargeObj DMAs the whole buffer to VRAM word $0400
!SprBuf_Owner = $0BC0                    ; 8 bytes: object slot owning each $200-byte chunk of
                                         ; SprBuf_Base ($80 = free); SprBuf_Alloc*/Free* only use
                                         ; entries 0-3. SprBuf_FreeAll clears all 8, but 8 chunks
                                         ; would not fit the $0C00 buffer: entries 4-7 look unused
                                         ; (inferred)

; --- ROM tables ---
!GfxRom_D2 = $D20000                     ; object tile graphics in ROM bank $D2 (Spr_CopyTileD2 reads
                                         ; 32 bytes at +X)
!GfxRom_D3 = $D30000                     ; object tile graphics in ROM bank $D3
!GfxRom_D4 = $D40000                     ; object tile graphics in ROM bank $D4
!GfxRom_D5 = $D50000                     ; object tile graphics in ROM bank $D5
!Wram7F_PtrBase = $7F0000                ; base 0 of bank $7F for abs,X / abs,Y accesses whose index
                                         ; holds the full address (DB = $7F)

; --- VRAM upload queue ($0940; 8 entries, index VramQ_Pos) ---
!VramQ_SrcA = $0940                      ; 16-bit: bank-$7F source address of the first half
                                         ; (Obj_TileBuf)
!VramQ_DestA = $0950                     ; 16-bit: VRAM word address for the first half (Obj_VramTile
                                         ; * 16)
!VramQ_SrcB = $0960                      ; 16-bit: source of the second half (first + $100 bytes)
!VramQ_DestB = $0970                     ; 16-bit: VRAM address of the second half (first + $100
                                         ; words: the next row of 16 tiles)
!VramQ_SizeA = $0980                     ; 16-bit byte count of the first half
!VramQ_SizeB = $0990                     ; 16-bit byte count of the second half
!VramQ_Valid = $09A0                     ; 16-bit: nonzero for a pending entry, 0 ends the queue;
                                         ; Field_ProcessAnimQueue waits while the first entry is
                                         ; pending

;
; --- Window effects (Field_EventHook handlers, $C0:220E-$C0:274C) ---
!WinFx_ArgX = $0350                      ; 8-bit argument block for BankC3_Entry0008, which reads it
                                         ; with DP=$0300 ($50); hooks 1, 2, 4 and 5 copy WinFx_CenterX here
!WinFx_ArgY = $0352                      ; 8-bit (BankC3_Entry0008's $52); WinFx_CenterY
!WinFx_ArgSize = $0354                   ; 8-bit (BankC3_Entry0008's $54); WinFx_Size
!WinFx_TablePtr = $0356                  ; 16-bit address of the table BankC3_Entry0008 writes;
                                         ; bit 0 of WinFx_TableBank picks bank $7F over $7E
!WinFx_TableBank = $0358                 ; 8-bit bank byte of WinFx_TablePtr
!WinFx_Busy = $0350                      ; alias of WinFx_ArgX read by hook 3 after BankC3_Entry000E:
                                         ; nonzero while that effect runs (BankC3_Entry000E clears
                                         ; it after $20 frames)
!WinFx_QuadTablePtr = $0350              ; alias of WinFx_ArgX for hook 6: 16-bit table address for
                                         ; BankC3_Entry0011
!WinFx_QuadTableBank = $0352             ; alias of WinFx_ArgY for hook 6: its bank byte
!WinFx_QuadPoints = $0360                ; 8 bytes for BankC3_Entry0011: X, Y of 4 points (the high
                                         ; bytes of WinFx_QuadPos); it picks the smallest Y first
!WinFx_QuadTimer = $7F1CE8               ; 8-bit frames left for hook 6
!WinFx_QuadPos = $7F1CE9                 ; 4 x (16-bit X, 16-bit Y), 8.8 fixed point: hook 6's points
!WinFx_QuadVel = $7F1CF9                 ; 4 x (16-bit X, 16-bit Y): added to WinFx_QuadPos per frame
!Hdma_Unk7F14F1 = $7F14F1                ; 8-bit; the NMI handler stores a tilemap base | 1 at
                                         ; $7F:14F0 (inferred: BG1SC data for HDMA channel 0, which
                                         ; Hdma_InitChannelsFD points at BG1SC-BG4SC); hook 12
                                         ; stores Map_TilemapVram3's high byte here (BG2SC?)
!Hdma_Unk7F1520 = $7F1520                ; 8-bit; set with Ppu_Unk0BD7 by hook 9/10 and to $13 by
                                         ; hook 12. By analogy with $7F:14F0, probably HDMA data;
                                         ; which register is not traced
!Hdma_Unk7F1521 = $7F1521                ; 8-bit; set with Ppu_Unk0BD8 (hooks 9/10)
!Hdma_Unk7F1522 = $7F1522                ; 8-bit; $17 (BG1-3 + OBJ bits) while a window effect runs,
                                         ; 0 after; probably the TMW byte of HDMA data
!Hdma_Unk7F1523 = $7F1523                ; 8-bit; as Hdma_Unk7F1522 (probably TSW)

; --- Staff credits (Field_ServiceUnk54) ---
!Credits_Text = $FDA000                  ; ROM: staff credits in ASCII ("PRODUCER//KAZUHIKO
                                         ; AOKI"...): '/' ends a line, a byte >= $80 ends a block
!Map_BufC800 = $7EC800                   ; 2 KB WRAM buffer ($7E:C800-$CFFF) that Field_BuildC800Mode1/2/4
                                         ; write through WMDATA; Map_ClearBufC800 zeroes it
!Credits_LineBuf = $7ED800               ; 64 bytes: one tilemap row (32 words) built by
                                         ; Field_ServiceUnk54, DMAed to VRAM by the NMI ($C0:EC77)

; --- Map page $1D00 (absolute, or dp with DP = !DP_Map) ---
!Map_TreasureRec0 = $1D06                ; 16-bit TreasureRom offset that treasure numbers count from:
                                         ; Field_CheckTileInFront numbers a record (offset -
                                         ; this) / 4 for Treasure_Flags. Setter not matched
!Map_TreasureLocRecs = $1D08             ; 16-bit TreasureRom offset of the current location's
                                         ; record 0 (Map_TreasureIdx values index from it). Setter
                                         ; not matched
!Map_Unk1D0C = $1D0C                     ; 16-bit; its low byte / 2 is the upper column bound of
                                         ; Field_ServiceUnk54's bit-5 box (Map_TileOriginX the lower)
!Map_Unk1D10 = $1D10                     ; 16-bit; as Map_Unk1D0C for rows (Map_TileOriginY lower)
!Map_Unk1D1A = $1D1A                     ; 8-bit column: Map_Unk9175 keeps a leftward Map_Unk1D2E
                                         ; out of Map_Unk1D32 once the leader's Obj_TileX <= it;
                                         ; Map_StepStopLeft compares Map_TileOriginX / 2 with it
                                         ; (looks like a left scroll limit; not established)
!Map_Unk1D1B = $1D1B                     ; 8-bit column: as Map_Unk1D1A to the right (leader
                                         ; Obj_TileX >= it; Map_StepStopRight against
                                         ; Map_Unk1D0C / 2)
!Map_Unk1D1C = $1D1C                     ; 8-bit row: as Map_Unk1D1A upwards (leader Obj_TileY <=
                                         ; it + 1; Map_StepStopUp against Map_TileOriginY / 2)
!Map_Unk1D1D = $1D1D                     ; 8-bit row: as Map_Unk1D1A downwards (leader Obj_TileY >
                                         ; it; Map_StepStopDown against Map_Unk1D10 / 2)
!Map_Unk1D2A = $1D2A                     ; 8-bit; copied to Map_Unk1D2E each frame by
                                         ; Map_ResetUnk1D2E
!Map_Unk1D2B = $1D2B                     ; 8-bit; copied to Map_Unk1D30 each frame (as above)
!Map_Unk1D2C = $1D2C                     ; 8-bit; zeroed each frame by Field_FrameUpdate, then set
                                         ; to the signed D-pad X step (+/-$10, $20 running) by the
                                         ; Field_Dpad* handlers
!Map_Unk1D2D = $1D2D                     ; 8-bit; as Map_Unk1D2C for the Y step (down positive)
!Map_Unk1D2E = $1D2E                     ; 8-bit; Map_Unk1D2A each frame, plus the D-pad X step
                                         ; (Field_Dpad*); Field_Unk885A sets it to
                                         ; +/-$10 by which half of the screen the leader is in
                                         ; (X >= $80 -> $10) (inferred: a horizontal step)
!Map_Unk1D30 = $1D30                     ; 8-bit; as Map_Unk1D2E vertically (screen Y >= $88 -> $10)
!Map_Unk1D32 = $1D32                     ; 8-bit; zeroed by Field_Unk885A; Map_Unk9175 zeroes it and
                                         ; copies Map_Unk1D2E into it when the leader is inside
                                         ; Map_Unk1D1A/1D1B in that direction
!Map_Unk1D33 = $1D33                     ; 8-bit; as Map_Unk1D32 for Map_Unk1D30 (rows
                                         ; Map_Unk1D1C/1D1D)
!Map_StepTestN = $1D52                   ; 8-bit scratch of the Map_StepStop* tests: the step / 16
                                         ; (Down, Right) or Map_TileOriginY/X / 2 (Up, Left)
!Map_StepTestN2 = $1D54                  ; 8-bit scratch of Map_StepStopUp/Left: the step / 16
!Map_TilemapVram3 = $1D7E                ; 16-bit tilemap VRAM base the NMI uses for redraw step 2
                                         ; (Field_MapRedrawDone = 2)
!Map_TilemapVram4 = $1D84                ; 16-bit; its high byte is ORed into Hdma_Unk7F14F1 when
                                         ; hook 12 ends
!Map_Unk1D8D = $1D8D                     ; 16-bit; one of six words $1D87-$1D91 that $C0:06F1 copies
                                         ; to $7E:2C5A (BG scroll values? unverified); hooks 7-10
                                         ; set it to $0100
!Map_Unk1D8F = $1D8F                     ; 16-bit; as Map_Unk1D8D (hooks 7/8 set $F01D)
!Map_Unk1D91 = $1D91                     ; 16-bit; as Map_Unk1D8D (hooks 7/8 set $01C0)
!Map_Unk1D93 = $1D93                     ; 8-bit; nonzero lets Field_Unk885A set Map_Unk1D2E; at the
                                         ; limit column Map_StepStopRight/Left keep the X step only
                                         ; while it plus / minus the step / 16 stays within 0-$F
                                         ; (a pixel offset inside a 16-pixel tile?)
!Map_Unk1D96 = $1D96                     ; 8-bit; nonzero lets Field_Unk885A set Map_Unk1D30; as
                                         ; Map_Unk1D93 for the Y step (Map_StepStopDown/Up)
!Map_Unk1DFD = $1DFD                     ; 8-bit; $11 during hook 12, 0 after; no reader in bank $C0
!Map_HookTimer = $1DFF                   ; 8-bit frame countdown for hook 12's loops

; One OAM low-table entry; used as abs,X with X = the entry's address (Oam_BuildShadow)
struct OamEntry $0000
    .X: skip 1           ; X position (low 8 bits)
    .Y: skip 1           ; Y position
    .Tile: skip 1        ; tile number (low 8 bits)
    .Attr: skip 1        ; vhppccct attributes
endstruct align 4

; One tile of an object's sprite as built for OAM (bank $7F, 8-byte records; an object's
; tiles start at Obj_TileRecOfs). Spr_AppendToOam copies X, Y, Tile, Attr into the OAM shadow.
struct SprTile $7F4BC0
    .X: skip 1           ; OAM X (low 8 bits) after adding Spr_BaseX
    .Y: skip 1           ; OAM Y after adding Spr_BaseY and clamping
    .OfsX: skip 2        ; 16-bit X offset of the tile from the object origin
    .OfsY: skip 2        ; Y offset of the tile (low byte used)
    .Tile: skip 1        ; OAM tile number
    .Attr: skip 1        ; OAM attributes (vhppccct)
endstruct align 8

; Source records with the SprTile layout (bank $7F, same Obj_TileRecOfs index); the
; "init" builders copy OfsX/OfsY/Tile/Attr from here into SprTile.
struct SprTileSrc $7F4800
    .X: skip 1           ; not read by the Spr_Load* routines (they set SprTile.X)
    .Y: skip 1           ; not read by the Spr_Load* routines (they set SprTile.Y)
    .OfsX: skip 2        ; 16-bit X offset of the tile from the object origin
    .OfsY: skip 2        ; Y offset of the tile (low byte used)
    .Tile: skip 1        ; OAM tile number
    .Attr: skip 1        ; OAM attributes (vhppccct)
endstruct align 8

; One treasure record in ROM bank $F5 (4 bytes; Field_CheckTileInFront reaches record n of
; the location at Map_TreasureLocRecs + n*4). "Treasure" rests on what the code gives: an item
; through BankC1_Entry8003 service 1 (adds one to the inventory at $7E:2400/$2500, max 99) or
; gold through service 4 (adds to the 24-bit sum at $7E:2C53, capped at 9,999,999), once per
; record (Treasure_Flags), with the tile changed through SceneFlag_TileStep.
struct TreasureRom $F50000
    .Tile: skip 2        ; map index (row << 8 | column) the record belongs to
    .Contents: skip 2    ; bit 15 set: gold, amount = bits 0-14 x 2; else bit 14 set
                         ; (Treasure_Empty): nothing given; else item id in bits 0-8
endstruct align 4

endif
