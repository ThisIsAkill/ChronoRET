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
!NmiTrampoline   = $000500   ; 4 B: JML to the NMI handler, installed at boot (bank $00 NMI_Stub jumps here)
!IrqTrampoline   = $000504   ; 4 B: JML to the IRQ handler, installed at boot
!CrashMarkerRead = $ABCDEF   ; BRK/COP trap reads this recognizable address in a loop;
                             ; inferred: a marker for bus traces/debuggers, not real data

; ==== Field direct page and bank $C0 names ====

;
; Field direct page. Field/engine code runs with DP = !DP_Field;
; these values are dp offsets (WRAM address = $0100 + offset). An
; absolute access to one of them writes !DP_Field+!Name.
;
!DP_Field = $0100                        ; direct page of field/engine code (GameLoop TCDs it)

; --- Location (current / return / destination) (dp) ---
!Loc_Id = $00                            ; 16-bit current location index; GameLoop_Main dispatches on
                                         ; it ($01F0+ -> bank $C2, $01FF+ -> LoadSavePath)
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
                                         ; (FrameStateInit)
!Loc_PrevX = $0C                         ; 16-bit store of Loc_EntryX/Y at the last location load
                                         ; (FrameStateInit)
!Loc_PrevFacing = $0E                    ; 8-bit Loc_EntryFacing at the last location load
                                         ; (FrameStateInit)
!Loc_DestId = $12                        ; 16-bit warp destination location; Field_SceneChangeTick
                                         ; copies it to Loc_Id before restarting
!Loc_DestX = $14                         ; 16-bit load: destination tile X/Y, copied to Loc_EntryX/Y
                                         ; by Field_SceneChangeTick
!Loc_DestFacing = $16                    ; 8-bit destination facing, copied to Loc_EntryFacing by
                                         ; Field_SceneChangeTick

; --- Field state flags (dp) ---
!Field_Unk0F = $0F                       ; 8-bit; only zeroed (FrameStateInit) in matched code
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
!Field_Unk20 = $20                       ; 8-bit; set to 1 by FrameStateInit, no other matched use
!Field_ExitMenuArg = $25                 ; 8-bit; picks the BankC2_Entry8000 argument on the fade-out
                                         ; path of Field_SceneChangeTick (0 -> Field_RunBankC2Mode5
                                         ; with 5; bit 7 -> bits 7-6 as A, bits 5-0 as X; else bit 0
                                         ; ? 0 : 6)
!Field_Unk26 = $26                       ; 8-bit state index; EngFD_UnkC2C1 dispatches on it;
                                         ; Field_FadeToBankC2Mode5 toggles bits 0-1
!Field_Unk27 = $27                       ; 8-bit; cleared with Field_Unk26 by Field_SaveState
!Field_Unk28 = $28                       ; 8-bit; set to $5F by FrameStateInit, no other matched use
!Field_Unk29 = $29                       ; 8-bit countdown; Field_Unk1F87 dispatches on it;
                                         ; Field_SaveState forces it to 1 when nonzero
!Field_Unk2B = $2B                       ; 16-bit; only zeroed (FrameStateInit) in matched code
!Field_Unk2D = $2D                       ; 8-bit; only zeroed (FrameStateInit) in matched code
!Field_Unk2F = $2F                       ; 8-bit; only zeroed (FrameStateInit) in matched code
!Field_Unk30 = $30                       ; 8-bit; only zeroed (FrameStateInit) in matched code
!Field_Unk34 = $34                       ; 16-bit counter; Field_Unk1AAC counts it up, Sub_1ADF
                                         ; clears it on button bit 7 of Pad_Unk00F6
!Field_Unk38 = $38                       ; 8-bit; Field_Unk885A dispatches on it ($0138);
                                         ; DefaultHandler sets it to 1
!Field_EventHook = $39                   ; 8-bit; Field_EventHookDispatch runs table entry (value -
                                         ; 1) when nonzero
!Field_Unk44 = $44                       ; 8-bit flags; Field_UnkAF4E acts on bits 0/1
!Pad_Unk00F6Latch = $50                  ; 8-bit; GameLoop_FrameBody ORs Pad_Unk00F6 into it every
                                         ; frame
!Pad_PressedLatch = $51                  ; 8-bit; GameLoop_FrameBody ORs the low byte of Pad_Pressed
                                         ; into it every frame
!Field_Unk53 = $53                       ; 8-bit flags; EngFD_UnkC2C1 skips when bit 0 is set;
                                         ; DefaultHandler sets/clears bit 7; Field_PauseAndMenuInput
                                         ; clears it in the pause loop
!Field_Unk54 = $54                       ; 8-bit; only zeroed (FrameStateInit) in matched code;
                                         ; Field_Unk274D tests bits 2-5
!Field_Unk55 = $55                       ; 8-bit; set to 1 by FrameStateInit, no other matched use
!Field_Unk58 = $58                       ; 16-bit; only zeroed (FrameStateInit) in matched code
!Field_Unk62 = $62                       ; 8-bit selector handed to Sub_1ADF in A (1, 2, else);
                                         ; blocks the pause/menu paths when nonzero
!Field_Unk63 = $63                       ; 8-bit index stepped up/down by Sub_1ADF and clamped to
                                         ; Field_Unk64/65; $80 at load
!Field_Unk64 = $64                       ; 8-bit wrap value for Field_Unk63 (Sub_1ADF)
!Field_Unk65 = $65                       ; 8-bit limit for Field_Unk63 (Sub_1ADF)
!Field_Unk66 = $66                       ; 8-bit; Sub_1ADF saves Field_Unk63 here before forcing it
                                         ; to 4
!Field_Unk68 = $68                       ; 8-bit; set to 5 by FrameStateInit, no other matched use
!Field_UnkAB = $AB                       ; 8-bit; saved to/restored from SceneSave_UnkAB by
                                         ; Field_SaveState/Party_ReinitIfChanged
!Field_UnkAC = $AC                       ; 8-bit; saved/restored with Field_UnkAB
!Field_UnkAD = $AD                       ; 8-bit; saved/restored with Field_UnkAB
!Field_E4Ptr0 = $AF                      ; 24-bit pointer into bank $E4; low word from RomE4_PtrInit,
                                         ; bank byte $E4 (FrameStateInit)
!Field_E4Ptr1 = $B2                      ; 24-bit pointer into bank $E4 (as Field_E4Ptr0)
!Field_E4Ptr2 = $B5                      ; 24-bit pointer into bank $E4 (as Field_E4Ptr0)
!Field_E4Ptr3 = $B8                      ; 24-bit pointer into bank $E4 (as Field_E4Ptr0)
!Field_UnkBB = $BB                       ; 8-bit; zeroed at load; LocLoad_Unk0A14 skips its work when
                                         ; nonzero
!Field_UnkBC = $BC                       ; 8-bit; only zeroed (FrameStateInit) in matched code
!Field_UnkEB = $EB                       ; 8-bit; $80 at load; Field_FrameUpdate sets it to $80,
                                         ; Field_Unk1AAC reads it
!Field_Unk0400Copy = $F8                 ; 8-bit copy of Eng_Unk0400 taken by FrameStateInit
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

; --- DMA fill arguments (ClearRAMDMA) (dp) ---
!DmaFill_Dest = $4B                      ; 16-bit WRAM destination address for ClearRAMDMA
!DmaFill_Bank = $4D                      ; 8-bit WRAM destination bank for ClearRAMDMA
!DmaFill_Size = $4E                      ; 16-bit byte count for ClearRAMDMA

; --- Party and object slots (dp) ---
!Obj_Cur = $6D                           ; 16-bit current object slot offset (object number x 2; high
                                         ; byte kept 0); index into the Obj_* tables
!Obj_CurHi = $6E                         ; 8-bit high byte of Obj_Cur; zeroed so 16-bit X loads of
                                         ; Obj_Cur work (PostVBlank, Party_ReinitIfChanged)
!Chr_ObjSlot = $8D                       ; 7 bytes, one per playable character: that character's
                                         ; object slot, $80 = none (FrameStateInit sets $80;
                                         ; Party_ReinitIfChanged re-inits each live one when the
                                         ; party changes)
!Party_MembersCache = $94                ; 3 bytes: copy of Party_Members taken at load;
                                         ; Party_ReinitIfChanged compares to detect a party change
!Party_ObjSlot = $97                     ; 3 words ($97/$99/$9B): object slot of each party member,
                                         ; $80 = none (Field_SaveState, Field_RestoreState,
                                         ; Party_ReinitIfChanged); $97 is the leader
!Party_ObjSlot1 = $99                    ; 16-bit object slot of party member 2 (= Party_ObjSlot+2)
!Party_ObjSlot2 = $9B                    ; 16-bit object slot of party member 3 (= Party_ObjSlot+4)
!Field_UnkAEObj = $AE                    ; 8-bit object slot (or $80 = none) that Field_RestoreState
                                         ; runs Spr_LoadLargeObj on after a reload

; --- OAM shadow build (PostVBlank / Spr_AppendToOam) (dp) ---
!Oam_Range1PrevEnd = $7B                 ; 16-bit OAM shadow address where range 1 ended last frame;
                                         ; PostVBlank hides entries from the new end up to here
!Oam_Range2PrevEnd = $7D                 ; 16-bit previous-frame end of range 2 (as
                                         ; Oam_Range1PrevEnd)
!Oam_Range3PrevEnd = $7F                 ; 16-bit previous-frame end of range 3 (as
                                         ; Oam_Range1PrevEnd)
!Oam_Range1HiPtr = $81                   ; 16-bit write pointer into the OAM high-table shadow for
                                         ; range 1 (starts $0907); Spr_AppendToOam stores one byte
                                         ; per 4 tiles
!Oam_Range1HiUnk = $83                   ; 16-bit; zeroed with Oam_Range1HiPtr each frame
                                         ; (PostVBlank), no other matched use
!Oam_Range2HiPtr = $85                   ; 16-bit high-table write pointer for range 2 (starts $091A)
!Oam_Range2HiUnk = $87                   ; 16-bit; zeroed each frame (PostVBlank), no other matched
                                         ; use
!Oam_Range3HiPtr = $89                   ; 16-bit high-table write pointer for range 3 (starts $0901)
!Oam_Range3HiUnk = $8B                   ; 16-bit; zeroed each frame (PostVBlank), no other matched
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
                                         ; 1 for ModeEC/EE (4), 2 for ModeFA/FC (6)
!TileAnim_StepKind = $61                 ; 8-bit; DefaultHandler sets 0 when the stepped tile was
                                         ; $FE, 1 when it was $E0

; --- Scratch (dp) ---
!Eng_Scratch = $D9                       ; 16-bit general scratch, reused by many routines
!TileAnim_OriginX = $DB                  ; alias of Oam_Range1LoPtr's slot used as scratch by the
                                         ; tile-animation handlers: copy of Map_TileOriginX
!TileAnim_OriginY = $DD                  ; alias of Oam_Range2LoPtr's slot used as scratch by the
                                         ; tile-animation handlers: copy of Map_TileOriginY
!Bg_RowWordOfs = $D9                     ; $D9 in Bg_TilemapIndex64x32: row * 32

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
                                         ; bit 7 clears Field_Unk34 (Sub_1ADF)
!Pad_Unk00F7 = $00F7                     ; 8-bit; Sub_1ADF: bit 2 steps Field_Unk63 up, bit 3 steps
                                         ; it down (Down/Up in the Pad_Pressed layout?)
!Pad_Unk00F8 = $00F8                     ; 8-bit; Sub_1ADF: bit 7 sets Field_Unk62 = 3
!Eng_Unk0400 = $0400                     ; 8-bit; FrameStateInit copies it to Field_Unk0400Copy
!Field_FadeBusy = $0407                  ; 8-bit; $FF while a pause/fade loop runs
                                         ; (Field_PauseAndMenuInput, Field_FadeToBankC2Mode5),
                                         ; cleared after (Field_FadeInAfterReload,
                                         ; Field_RunBankC2Mode5)
!Field_Unk0BD9 = $0BD9                   ; 8-bit; zeroed by FrameStateInit, no other matched use
!Field_Unk0BDA = $0BDA                   ; 8-bit; zeroed by FrameStateInit, no other matched use
!Field_Unk0BDB = $0BDB                   ; 8-bit; zeroed by FrameStateInit, no other matched use
!Field_Unk0BDE = $0BDE                   ; 8-bit; set to 2 by FrameStateInit, no other matched use
!Field_Unk0BE9 = $0BE9                   ; 8-bit; zeroed by FrameStateInit, no other matched use
!Field_Unk1DF9 = $1DF9                   ; 8-bit; saved to SceneSave_Unk1DF9 around the menu
                                         ; (Field_SaveState / Field_RestoreState)
!Audio_CmdId = $1E00                     ; 8-bit sound-driver command byte ($19 = play sound effect),
                                         ; sent by Audio_DriverCommand
!Audio_CmdArg0 = $1E01                   ; 8-bit first command argument (sound-effect id in
                                         ; Audio_PlayTileSfxA)
!Audio_CmdArg1 = $1E02                   ; 8-bit second command argument (low byte of the leader's
                                         ; Obj_ScreenX in Audio_PlaySfxAtLeader)
!Field_Unk7E2000 = $7E2000               ; 16-bit; zeroed by FrameStateInit, no other matched use
!Party_Members = $7E2980                 ; 3 bytes: character id of each party member
                                         ; (Party_ReinitIfChanged re-inits the character objects when
                                         ; they change)
!Field_Unk7E2989 = $7E2989               ; 8-bit; zeroed by FrameStateInit, no other matched use
!Eng_Unk7F0000 = $7F0000                 ; 8-bit; Field_FadeToBankC2Mode5 only proceeds when it is >=
                                         ; $49 (purpose unknown)
!Field_Unk7F03FE = $7F03FE               ; 8-bit; when 1-2 Field_RestoreState stacks party members
                                         ; 2/3 on the leader and sets it to 3
!RomE4_PtrInit = $E4FFE0                 ; 4 words in ROM: initial low words of Field_E4Ptr0-3
                                         ; (FrameStateInit)

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
!SceneSave_Scroll = $7F1D1E              ; 4 words: Map_ScrollA-D saved by Field_SaveState, restored
                                         ; by Field_RestoreState
!SceneSave_Unk1DF9 = $7F1D26             ; 8-bit Field_Unk1DF9 saved by Field_SaveState, restored by
                                         ; Field_RestoreState
!Map_ScrollA = $7F3728                   ; 16-bit; one of four words saved/restored around the menu
                                         ; (Field_SaveState/Field_RestoreState); earlier notes call
                                         ; it scroll X0
!Map_ScrollB = $7F3748                   ; 16-bit; saved/restored with Map_ScrollA
!Map_ScrollC = $7F3768                   ; 16-bit; saved/restored with Map_ScrollA
!Map_ScrollD = $7F3781                   ; 16-bit; saved/restored with Map_ScrollA
!ObjX_Unk7F0580 = $7F0580                ; per-object word ($80-byte table in bank $7F), zeroed by
                                         ; Evt_RunObjInit
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
                                         ; 7 = empty); PostVBlank walks them from the last
!Obj_DrawNext = $0E81                    ; 8-bit per object: next object in the same draw bucket (bit
                                         ; 7 = end)
!Obj_ScriptPos = $1180                   ; 16-bit per object: Evt_Data offset where the object's
                                         ; script continues (Evt_RunObjInit sets it past the init
                                         ; function)
!Obj_Facing = $1600                      ; 8-bit per object facing; EOR 1 turns it around
                                         ; (Field_SceneChangeTick); Obj_AnimFrameLookup picks the
                                         ; facing block from it (0, negative, 2, other)
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
                                         ; function
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
                                         ; for tiles 0-7
!Obj_OamHiB = $7F4B40                    ; 2 bytes per object (bank $7F): high-table bytes for tiles
                                         ; 8-15 (24-tile objects)
!Obj_OamHiC = $7F4F80                    ; 2 bytes per object (bank $7F): high-table bytes for tiles
                                         ; 16-23 (24-tile objects)
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
!Obj_PrioLow = $0C00                     ; 8-bit per object: OAM priority bits for tiles whose OfsY
                                         ; is below $E8 (the lower body); saved with the party
                                         ; positions
!Obj_PrioHigh = $0C01                    ; 8-bit per object: OAM priority bits for tiles with OfsY >=
                                         ; $E8 (the upper 24 lines)
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
                                         ; modes

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
                                         ; SprBuf_Base ($80 = free); SprBuf_Alloc*/Free* scan the
                                         ; first 4

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

; One OAM low-table entry; used as abs,X with X = the entry's address (PostVBlank)
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
    .X: skip 1           ; OAM X (low 8 bits) after adding Spr_BaseX
    .Y: skip 1           ; OAM Y after adding Spr_BaseY and clamping
    .OfsX: skip 2        ; 16-bit X offset of the tile from the object origin
    .OfsY: skip 2        ; Y offset of the tile (low byte used)
    .Tile: skip 1        ; OAM tile number
    .Attr: skip 1        ; OAM attributes (vhppccct)
endstruct align 8

endif
