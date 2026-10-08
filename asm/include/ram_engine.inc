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
!Field_Unk31 = $31                       ; 8-bit; Field_UploadUnk5800 uploads to VRAM word
                                         ; $5800 + this x $200 (no writer traced)
!Field_Unk32 = $32                       ; 8-bit; zeroed by Field_CheckTileInFront as it starts
                                         ; Field_Unk29 = 1
!Field_Unk34 = $34                       ; 16-bit; when $FFFF, Field_ActionButton swallows one press
                                         ; of Pad_Unk00F6 bit 7 and resets it to 0; Sub_1ADF
                                         ; clears it on button bit 7 of Pad_Unk00F6
!Field_Unk36 = $36                       ; 8-bit; NmiHandler runs Field_UploadUnk5800 while it is
                                         ; nonzero: every frame while bit 7 is clear, once (it is
                                         ; zeroed first) when bit 7 is set; no writer traced
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
!Field_Unk44 = $44                       ; 8-bit flags: the planes Field_UnkAF4E copies (MapCopy_*
                                         ; bits); the event handler at $C0:3D97 stores it; zeroed at
                                         ; load (Field_InitLoadState)
!Pad_Unk00F6Latch = $50                  ; 8-bit; GameLoop_FrameBody ORs Pad_Unk00F6 into it every
                                         ; frame
!Pad_PressedLatch = $51                  ; 8-bit; GameLoop_FrameBody ORs the low byte of Pad_Pressed
                                         ; into it every frame
!Nmi_FramePending = $52                  ; 8-bit; Field_WaitFrame INCs it and spins until it is 0 again;
                                         ; NmiHandler does the frame's uploads only while it is
                                         ; nonzero and zeroes it after them (the frame handshake)
!Field_Unk53 = $53                       ; 8-bit flags; EngFD_UnkC2C1 skips when bit 0 is set;
                                         ; DefaultHandler sets/clears bit 7; Field_PauseAndMenuInput
                                         ; clears it in the pause loop
!Field_Unk54 = $54                       ; 8-bit request flags read by Field_ServiceUnk54: bit 4 = write
                                         ; one staff-credits line per frame, bits 2-3 = run
                                         ; Map_ClearBufC800, bit 5 = watch Field_TileStepX/Y against the
                                         ; Map_Unk1D0A-1D10 box; zeroed at load
!Field_Unk55 = $55                       ; 8-bit; set to 1 by Field_InitLoadState; Map_StepTileEffects
                                         ; stores Map_ProbeLevel here and Map_ProbeLevelBlocked
                                         ; compares with it (looks like the leader's current level)
!Field_Unk58 = $58                       ; 16-bit; zeroed by Field_InitLoadState; Field_WaitFrame counts
                                         ; it up once per frame wait, ANDed with Field_Unk58Mask
                                         ; (bits 0-9 wrap at $400, bit 15 kept); no reader traced
!Field_Unk62 = $62                       ; 8-bit selector handed to Sub_1ADF in A (1, 2, else);
                                         ; blocks the pause/menu paths and Field_DpadDispatch when
                                         ; nonzero
!Field_Unk63 = $63                       ; 8-bit index stepped up/down by Sub_1ADF and clamped to
                                         ; Field_Unk64/65; $80 at load
!Field_Unk64 = $64                       ; 8-bit wrap value for Field_Unk63 (Sub_1ADF)
!Field_Unk65 = $65                       ; 8-bit limit for Field_Unk63 (Sub_1ADF)
!Field_Unk66 = $66                       ; 8-bit; Sub_1ADF saves Field_Unk63 here before forcing it
                                         ; to 4
!Evt_StepsLeft = $67                     ; 8-bit: opcodes Evt_RunObjScriptSteps may still run for
                                         ; the current object this frame
!Field_Unk68 = $68                       ; 8-bit; set to 5 by Field_InitLoadState: the opcodes
                                         ; Evt_RunObjScriptSteps runs per object per frame, at most
!Field_UnkAB = $AB                       ; 8-bit; saved to/restored from SceneSave_UnkAB by
                                         ; Field_SaveState/Party_ReinitIfChanged
!Field_UnkAC = $AC                       ; 8-bit; saved/restored with Field_UnkAB
!Field_UnkAD = $AD                       ; 8-bit; saved/restored with Field_UnkAB
!Field_E4Ptr0 = $AF                      ; 24-bit pointer into bank $E4; low word from RomE4_PtrInit,
                                         ; bank byte $E4 (Field_InitLoadState)
!Field_E4Ptr1 = $B2                      ; 24-bit pointer into bank $E4 (as Field_E4Ptr0)
!Field_E4Ptr2 = $B5                      ; 24-bit pointer into bank $E4 (as Field_E4Ptr0)
!Field_E4Ptr3 = $B8                      ; 24-bit pointer into bank $E4 (as Field_E4Ptr0)
!Evt_ObjSlotEnd = $BD                    ; 16-bit Evt_ObjCount x 2: end of the object-slot loops
                                         ; (Evt_InitObjects)
!Field_UnkBB = $BB                       ; 8-bit; zeroed at load; LocLoad_Unk6DCF sets 1 when the
                                         ; location has no LocRom.Tileset3; LocLoad_Unk0A14 then skips
                                         ; the layer-3 metatiles and LocLoad_UnkA33B drops BG3 from
                                         ; the screens (so probably "no layer 3")
!Field_UnkBC = $BC                       ; 8-bit; zeroed by Field_InitLoadState; nonzero makes
                                         ; Map_Unk91AC set Map_ShakeX/Y from Eng_Unk0400
!Field_UnkEB = $EB                       ; 8-bit object slot the action button acts on, $80 = none:
                                         ; Field_FindObjInFront stores the object it finds;
                                         ; Field_ActionButton reads it. $80 at load; Field_FrameUpdate
                                         ; resets it to $80 every frame
!Field_Unk0400Copy = $F8                 ; 8-bit copy of Eng_Unk0400 taken by Field_InitLoadState
                                         ; then stepped as a RandomTable index (Obj_SetVelocityChecked
                                         ; INCs it before each read; $C0:6D0B does too)
!Loc_RecOfs = $FE                        ; 16-bit offset of the current location's LocRom record:
                                         ; Loc_Id x 14 (LocLoad_Unk092B at $C0:095B; Loc_Id bit 8
                                         ; adds $E00); read by the location-load steps
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
!FieldBtl_ObjSlots = $A3                ; 8 B: object slot behind each FieldBtlObj record ($FF =
                                         ; none); FieldBtl_SaveObjs sets all 8 to $FF, then
                                         ; FieldBtl_SaveObj fills them; FieldBtl_RestoreObjs reads
                                         ; them back after the battle. Overlaps Field_BattleObjList
                                         ; entries 6-11 (only entries 0-5 are read by then)
!FieldBtl_RestOriginX = $F0             ; 8-bit Map_TileOriginX / 2 while FieldBtl_SaveObjs and
                                         ; FieldBtl_Restore work (the FieldBtl* tile positions are
                                         ; kept relative to it)
!FieldBtl_RestOriginY = $F1             ; 8-bit Map_TileOriginY / 2 (as FieldBtl_RestOriginX)
!FieldBtl_OriginX = $DB                  ; alias of Oam_Range1LoPtr's slot in the battle hand-off
                                         ; (FieldBtl_SaveTileAttrs, FieldBtl_SavePartyPos,
                                         ; Field_Unk0617): Map_TileOriginX / 2
!FieldBtl_OriginY = $DD                  ; alias of Oam_Range2LoPtr's slot there: Map_TileOriginY / 2
!FieldBtl_RowsLeft = $D9                 ; alias of Eng_Scratch in FieldBtl_SaveTileAttrs: 16-bit
                                         ; rows still to copy after the current one
!FieldBtl_RecIdx = $D9                   ; alias of Eng_Scratch in FieldBtl_SaveObj: 8-bit, first the
                                         ; record number - 4 part, then the size class
!FieldBtl_RecFlags = $EE                 ; alias of Spr_NewFrame's slot in FieldBtl_SaveObj: the
                                         ; record's Flags byte being built
!Field_Unk47 = $47                       ; 8-bit; Scene_Unk0283 sets bits 0 and 3 after
                                         ; Field_Unk29F7 and bit 1 after Field_Unk2B78; no matched
                                         ; reader
!Obj_DrawBucketOfs = $C5                 ; alias of Spr_BaseY's slot in Obj_DrawLink: the bucket's
                                         ; Obj_DrawBucket offset while the links are rewritten
!Field_UnkAEObj = $AE                    ; 8-bit object slot (or $80 = none) that Field_RestoreState
                                         ; runs Spr_LoadLargeObj on after a reload

; --- Object motion, view test and screen position (Vblank_UnkA810 and its steps) ---
!Obj_VelX = $1900                        ; alias of Obj_Unk1900 (the page Evt_InitObjects clears):
                                         ; per object, signed X step added to Obj_PosX each frame
                                         ; while Obj_MoveFrames runs. The move steps use the low
                                         ; byte only, the arc step the word (Obj_MoveStep); set from
                                         ; a direction by Obj_SetVelocity / Obj_SetVelocityChecked
!Obj_VelXHi = $1901                      ; high byte of Obj_VelX: its sign extension
!Obj_VelY = $1980                        ; per object, signed Y step (as Obj_VelX, for Obj_PosY)
!Obj_VelYHi = $1981                      ; high byte of Obj_VelY; the arc step carries into it
!Obj_Speed = $1A00                       ; alias of Obj_Unk1A00: per object, the speed
                                         ; Obj_SetVelocity* multiplies the direction's sine and
                                         ; cosine by (step = speed x sin / 256)
!Obj_MoveFrames = $1A01                  ; alias of Obj_Unk1A01: per object, frames of movement
                                         ; left; Obj_MoveStep* decrement it and move while it is
                                         ; nonzero (an event handler at $C0:4D7C sets it to the
                                         ; distance / the step)
!Obj_ArcMode = $1B80                     ; alias of Obj_Unk1B80: per object, low byte nonzero =
                                         ; Obj_MoveStep moves with the 16-bit steps and adds
                                         ; Obj_ArcGravity to Obj_VelY every frame (an arc, probably
                                         ; a jump)
!Obj_ArcGravity = $1B81                  ; per object, 8-bit amount added to Obj_VelY per frame in
                                         ; arc mode (an event handler at $C0:4D87 stores it)
!ObjX_CallWait = $7F0980                 ; 8-bit per object in bank $7F (the table after the eight
                                         ; ObjX_Unk7F0580 levels): nonzero while opcode $04/$07 of the
                                         ; object waits for the function it called to end
!ObjX_Unk7F0A80 = $7F0A80                ; 16-bit per object in bank $7F: set from an event word or
                                         ; a bank-$7F word by opcodes $19 / $1C, its low byte compared
                                         ; by opcode $1A (meaning not traced)
!ObjX_EvtWait = $7F0A01                  ; 8-bit per object in bank $7F (the odd byte beside
                                         ; ObjX_LeaveView): the script-run counter of the wait
                                         ; opcodes $AD and $B9-$BD
!ObjX_LeaveView = $7F0A00                ; per object in bank $7F: nonzero = when the object leaves
                                         ; the view window (Obj_UpdateInView) and Field_Unk30 is 0,
                                         ; Field_Unk29 becomes Field_Unk29State0D. No writer traced
!ObjFront_SavedY = $C7                   ; Evt_FindSolidObjInFront: 16-bit, the caller's Y
!ObjFront_FacingX2 = $D9                 ; alias of Eng_Scratch there: 8-bit Obj_Facing x 2 of
                                         ; Obj_Cur (index into Evt_InFrontTests)
!ObjFront_X = $DB                        ; alias of Oam_Range1LoPtr's slot there: 16-bit Obj_PosX of
                                         ; Obj_Cur
!ObjFront_Y = $DD                        ; alias of Oam_Range2LoPtr's slot there: 16-bit Obj_PosY of
                                         ; Obj_Cur
!ObjFront_Other = $E9                    ; 16-bit: the object being tested (high byte $EA zeroed
                                         ; first, the low byte stored with 8-bit X)
!ObjFront_OtherHi = $EA                  ; high byte of ObjFront_Other
!Evt_Unk0920Key = $E3                    ; 8-bit value Evt_FindOrAddUnk0920 looks up in Evt_Unk0920
                                         ; (set by its callers, event code at $C0:4626 / $C0:4781)
!EvtArc_Gravity = $C1                    ; alias of Anim_RowAddr in Evt_Op7A_ArcToTile: 8-bit, its
                                         ; third operand (Obj_ArcGravity, and the frames when there
                                         ; is no distance)
!EvtFollow_ScrCol = $DB                  ; alias of Oam_Range1LoPtr's slot in Evt_Op8F_FollowPc: 8-bit
                                         ; Map_TileOriginX / 2 (the screen's first map column)
!EvtFollow_ScrRow = $DD                  ; as EvtFollow_ScrCol: Map_TileOriginY / 2
!EvtFace_Target = $D9                    ; alias of Eng_Scratch in Evt_OpA8_FaceObj: 16-bit, the
                                         ; target's slot
!EvtCall_Level = $D9                     ; alias of Eng_Scratch in the call opcodes $02-$07: 8-bit,
                                         ; the target's Obj_Unk1C00 (its current level)
!EvtCall_Slot = $DB                      ; alias of Oam_Range1LoPtr's slot: 16-bit, the target's slot
                                         ; (low byte stored, EvtCall_SlotHi zeroed)
!EvtCall_SlotHi = $DC                    ; high byte of EvtCall_Slot
!EvtCall_Arg = $DD                       ; alias of Oam_Range2LoPtr's slot: 8-bit, the level/function
                                         ; operand (level in the high nibble, function in the low)
!EvtCall_NewLevel = $DF                  ; 8-bit: EvtCall_Arg >> 4, the level the call runs at
!EvtCall_SaveIdx = $E1                   ; 16-bit: level x Evt_PrioStride + the target's slot (index
                                         ; into ObjX_Unk7F0580)
!EvtCall_FuncTbl = $E3                   ; 16-bit: the target's slot x 16 (its function table in
                                         ; Evt_Data); Evt_Unk0920Key's slot
!EvtIf_OfsPos = $C3                      ; alias of Spr_BaseX in the condition opcodes $12-$16:
                                         ; 16-bit, the Evt_Data offset of the opcode's jump-distance
                                         ; byte (its last byte)
!EvtIf_Left = $D9                        ; alias of Eng_Scratch in the condition opcodes: 8- or 16-bit,
                                         ; the value tested (Evt_CmpTable8 / Evt_CmpTable16 compare
                                         ; it with EvtIf_Right)
!EvtIf_Right = $DB                       ; alias of Oam_Range1LoPtr's slot there: 8- or 16-bit, the
                                         ; value it is compared with
!EvtIf_Cmp = $DD                         ; alias of Oam_Range2LoPtr's slot in Evt_Op16_IfMemByte:
                                         ; 8-bit, the comparison number
!EvtJump_Dist = $D9                      ; alias of Eng_Scratch in the jump opcodes: 16-bit, the
                                         ; jump distance (an operand byte, zero-extended)
!EvtGet_First = $D9                      ; alias of Eng_Scratch in the get opcodes $21-$24: 8-bit, the
                                         ; object's Obj_TileX (or Obj_Facing) on its way to an event word
!EvtGet_Second = $DB                     ; alias of Oam_Range1LoPtr's slot there: 8-bit, its Obj_TileY
!EvtMem_Src = $CD                        ; alias of Spr_GfxPtr in opcodes $48/$49: 24-bit pointer read
                                         ; from the operands (the byte or word to load)
!EvtMem_Dst = $D0                        ; alias of Spr_WramPtr in opcodes $4A-$4D: 24-bit pointer read
                                         ; from the operands (where to store)
!EvtMem_Pos = $D9                        ; alias of Eng_Scratch in opcodes $48/$49/$4C/$4D: 16-bit, the
                                         ; Evt_Data offset of the opcode's last byte
!EvtMem_Value = $D9                      ; alias of Eng_Scratch in opcodes $4F-$5B: 8- or 16-bit, the
                                         ; value on its way
!EvtBit_Arg = $DB                        ; alias of Oam_Range1LoPtr's slot in opcodes $65/$66: 8-bit,
                                         ; the bit operand (bit number in bits 0-3, page in bit 7)
!EvtCopy_Count = $C1                     ; alias of Anim_RowAddr in Evt_Op4E_CopyData: 16-bit MVN count
                                         ; (bytes - 1)
!ObjPal_Slot = $C3                       ; alias of Spr_BaseX in the palette-slot handlers
                                         ; (Obj_PalSlotKind0, Obj_PalSlotAny, Obj_Unk72B4): 8-bit,
                                         ; the slot being tried
!ObjPal_Owner = $DB                      ; alias of Oam_Range1LoPtr's slot there: 8-bit, the taken
                                         ; slot's owner while its Obj_PalSrc is compared
!ObjView_Left = $C3                      ; alias of Spr_BaseX in Obj_UpdateInView / Obj_FlagInView /
                                         ; Obj_ActivateIfInView: 8-bit first column of the view
                                         ; window, in 8-pixel columns (Map_TileOriginX units)
!ObjView_Right = $C4                     ; 8-bit column past the window (Spr_BaseX+1)
!ObjView_Top = $C5                       ; 8-bit first row of the window (Spr_BaseY)
!ObjView_Bottom = $C6                    ; 8-bit row past the window (Spr_BaseYHi)
!ObjMove_Step = $D9                      ; alias of Eng_Scratch in Obj_MoveStep: 8-bit size of a
                                         ; negative step being subtracted
!ObjScr_FineX = $D9                      ; alias of Eng_Scratch in Obj_CalcScreenPos: 16-bit
                                         ; Map_Unk1D87 & 7 (the pixel within the 8-pixel column)
!ObjScr_FineY = $DB                      ; 16-bit Map_Unk1D89 & 7 (Obj_CalcScreenPos)
!ObjScr_ViewX = $DD                      ; 16-bit Map_TileOriginX x 8 + ObjScr_FineX: the view's
                                         ; left edge in pixels (Obj_CalcScreenPos)
!ObjScr_ViewY = $DF                      ; 16-bit Map_TileOriginY x 8 + ObjScr_FineY: the top edge
!Obj_Direction = $EE                     ; alias of Spr_NewFrame's slot: 8-bit direction, 256 per
                                         ; turn, $00 = +X, $40 = +Y, $80 = -X, $C0 = -Y; result of
                                         ; Obj_CalcDirection, input of Obj_SetVelocity*
!Obj_DirectionHi = $EF                   ; zeroed by Obj_CalcDirection (no reader in the cluster)
!ObjDir_FromX = $F0                      ; alias of FieldBtl_RestOriginX in Obj_CalcDirection: 8-bit
                                         ; column of the start point (callers store Obj_TileX)
!ObjDir_FromY = $F1                      ; 8-bit row of the start point (callers store Obj_TileY)
!ObjDir_ToX = $F2                        ; 8-bit column of the target (script bytes in the event
                                         ; handler at $C0:4D22)
!ObjDir_ToY = $F3                        ; 8-bit row of the target
!ObjDir_Index = $F4                      ; 16-bit: the run part of the Rom_AngleTable index
!ObjDir_Run = $F6                        ; 8-bit distance along the octant's first axis
!ObjDir_Rise = $F7                       ; 8-bit distance along the second axis
!ObjVel_Y = $DB                          ; alias of Oam_Range1LoPtr's slot in Obj_SetVelocity*:
                                         ; 8-bit Y step, $DC = its sign extension
!ObjVel_YHi = $DC                        ; sign extension of ObjVel_Y
!ObjVel_X = $DD                          ; 8-bit X step (Oam_Range2LoPtr's slot)
!ObjVel_XHi = $DE                        ; sign extension of ObjVel_X
!ObjVel_NewX = $DF                       ; 16-bit Obj_PosX + the X step: the probed position
!ObjVel_NewTileX = $E0                   ; high byte of ObjVel_NewX: the probed tile column
!ObjVel_AttrA = $E1                      ; 8-bit Map_TileAttrA of the probed tile
!ObjVel_AttrB = $E5                      ; 8-bit Map_TileAttrB of the probed tile (Spr_HiBits' slot)
!ObjVel_Flags = $D9                      ; alias of Eng_Scratch: Obj_OamFlags while the fixed
                                         ; priorities are split
!ObjVel_AbsX = $D9                       ; alias of Eng_Scratch in Obj_SetVelocityAxis: |X step|

; --- Map region copy (Field_UnkAF4E, Map_CopyRegionPlane) (dp) ---
!MapCopy_SrcX = $3E                      ; 8-bit first column of the source rectangle (map tiles);
                                         ; with MapCopy_SrcY a 16-bit plane index (row << 8 | column).
                                         ; The event handler at $C0:3D97 loads $3E-$44 from 7 script
                                         ; bytes, then calls Field_UnkAF4E
!MapCopy_SrcY = $3F                      ; 8-bit first row of the source rectangle
!MapCopy_EndX = $40                      ; 8-bit last column of the source rectangle (inclusive)
!MapCopy_EndY = $41                      ; 8-bit last row of the source rectangle (inclusive)
!MapCopy_DstX = $42                      ; 8-bit first column of the destination; with
                                         ; MapCopy_DstY a 16-bit plane index
!MapCopy_DstY = $43                      ; 8-bit first row of the destination
!MapCopy_Width = $DB                     ; alias of Oam_Range1LoPtr's slot in the copy: 16-bit
                                         ; columns - 1 (MapCopy_EndX - MapCopy_SrcX, high byte 0)
!MapCopy_Rows = $DD                      ; 8-bit rows still to copy after the current one
                                         ; (Oam_Range2LoPtr's slot; $DE zeroed)
!MapCopy_RowsHi = $DE                    ; zeroed with MapCopy_Rows (not read)
!MapCopy_SrcCol = $DF                    ; 16-bit first source column (row index base)
!MapCopy_DstCol = $E1                    ; 16-bit first destination column
!MapCopy_ColsLeft = $E3                  ; 8-bit columns still to do in the row (bit copies)
!MapCopy_ColsLeftHi = $E4                ; zeroed by the bit copies (not read)
!MapCopy_Bit = $D9                       ; alias of Eng_Scratch: the source tile's bit being copied
!MapCopy_Plane = $F0                     ; alias of FieldBtl_RestOriginX's slot: 16-bit offset in
                                         ; bank $7E of the plane Map_CopyRegionPlane copies in
                                         ; (Map_TileProps, Map_Layer2Tiles, ... low word)

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
!ObjQ_Unk69 = $69                        ; 16-bit; Scene_PostLoadInit sets ObjQ_Unk69Init;
                                         ; Vblank_ReadScanlineCounters stops running scripts once the
                                         ; V counter reaches it (unless past line 240)
!ObjQ_Unk71 = $71                        ; 16-bit; Evt_InitObjects sets ObjQ_Unk71Init; no reader traced
!ObjQ_Unk73 = $73                        ; 8-bit; zeroed by Evt_InitObjects; no reader traced
!ObjQ_Unk74 = $74                        ; 8-bit; ObjQ_Empty at load (Evt_InitObjects): the head of
                                         ; the list of objects whose script is due (linked through
                                         ; Obj_Unk1080; Vblank_Unk59D9 fills it,
                                         ; Vblank_ReadScanlineCounters runs and empties it)
!ObjQ_Unk75 = $75                        ; 8-bit; as ObjQ_Unk74: that list's tail
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
!Eng_Unk0010 = $0010                     ; 8-bit at $00:0010 (not the field page); only Scene_Unk0283's
                                         ; BIT (probably meant as BIT #$10) reads it; no writer named
!Pad_Pressed = $00F0                     ; 16-bit newly pressed buttons, remapped: low = A X L R B Y
                                         ; Select Start (bits 7-0), high = Up Down Left Right (bits
                                         ; 3-0). Inferred from the pad reader at $C2:84F0 and Start
                                         ; (bit 0) toggling the pause loop in Field_PauseAndMenuInput
; Pad_Unk00F6-$00F9 are written once a frame by Menu_MapButtons ($C2:8545,
; through BankC2_Entry8002): $F6/$F8 = Pad_Pressed / Menu_PadHeld through
; the configured button map, $F7/$F9 = their high bytes (the D-pad).
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
!Eng_Unk0400 = $0400                     ; 8-bit; Field_InitLoadState copies it to Field_Unk0400Copy;
                                         ; with Field_UnkBC set, Map_Unk91AC reads bit 0 as the sign
                                         ; and bits 2 / 1 as X / Y shake on (Eng0400_*)
!Field_FadeBusy = $0407                  ; 8-bit; $FF while a pause/fade loop runs
                                         ; (Field_PauseAndMenuInput, Field_FadeToBankC2Mode5),
                                         ; cleared after (Field_FadeInAfterReload,
                                         ; Field_RunBankC2Mode5)
!Map_Unk0BCF = $0BCF                     ; 8-bit; Field_BuildC800Mode2 (layer edges off) compares it
                                         ; with 16: unequal builds the right-hand 32 columns
                                         ; (probably layer 2's width in metatiles); set by
                                         ; LocLoad_UnkA33B from MapProps.Size1 bits 4-5 ($10-$40)
!Map_Unk0BD1 = $0BD1                     ; 8-bit; as Map_Unk0BCF: unequal builds rows 32-63 (probably
                                         ; layer 2's height in metatiles)
!Map_Unk0BD3 = $0BD3                     ; 8-bit; as Map_Unk0BCF for layer 3 (Field_BuildC800Mode4)
!Map_Unk0BD5 = $0BD5                     ; 8-bit; as Map_Unk0BD1 for layer 3 (Field_BuildC800Mode4)
!Map_Unk0BC9 = $0BC9                     ; 8-bit; bit 7 set: Map_Unk93E1 moves layer 2 with the
                                         ; half-rate steppers (Map_Scroll2*Half) and the matching
                                         ; edge builders; LocLoad_UnkA33B sets it to $80 or 0 from
                                         ; MapProps.Size3 bit 6
!Map_Unk0BCA = $0BCA                     ; 8-bit; 1 or 0 from MapProps.Size3 bit 7 (LocLoad_UnkA33B):
                                         ; bit 0 set, Map_UnpackTilePlanes reads a layer-3 plane
                                         ; (Map_Layer3Tiles) and the loader at $C0:0ACC builds
                                         ; layer 3 (probably "the map has its own layer 3")
!Map_Unk0BCB = $0BCB                     ; 8-bit; $10/$20/$30/$40 from MapProps.Size1 bits 0-1
                                         ; (LocLoad_UnkA33B): the bytes Map_UnpackTilePlanes reads
                                         ; per row of layer 1's planes, and Map_InitMasksAndLimits
                                         ; makes Map_ColMask1 from it (probably layer 1's width in
                                         ; metatiles)
!Map_Unk0BCBHi = $0BCC                   ; 8-bit; zeroed with Map_Unk0BCB (LocLoad_UnkA33B), so a
                                         ; 16-bit read of it sees 0-$FF; no 16-bit reader traced
!Map_Unk0BCD = $0BCD                     ; 8-bit; as Map_Unk0BCB for layer 1's rows (MapProps.Size1
                                         ; bits 2-3; Map_RowMask1; probably its height)
!Map_Unk0BCDHi = $0BCE                   ; 8-bit; as Map_Unk0BCBHi
!Map_Unk0BCFHi = $0BD0                   ; 8-bit; as Map_Unk0BCBHi for Map_Unk0BCF
!Map_Unk0BD1Hi = $0BD2                   ; 8-bit; as Map_Unk0BCBHi for Map_Unk0BD1
!Map_Unk0BD3Hi = $0BD4                   ; 8-bit; as Map_Unk0BCBHi for Map_Unk0BD3
!Map_Unk0BD5Hi = $0BD6                   ; 8-bit; as Map_Unk0BCBHi for Map_Unk0BD5
!Ppu_Unk0BD7 = $0BD7                     ; 8-bit; the TM (main screen) value: Ppu_ApplyMapScreens
                                         ; writes it to TM; set by LocLoad_UnkA33B from
                                         ; MapProps.Screens. Also, $C0:0691 copies
                                         ; it, Ppu_Unk0BD8, 0, 0, 2 and Ppu_Unk0BDF to $7E:2C66-6B,
                                         ; the order of TM, TS, TMW, TSW, CGWSEL, CGADSUB (not traced
                                         ; to the register)
!Ppu_Unk0BD8 = $0BD8                     ; 8-bit; the TS (sub screen) value (as Ppu_Unk0BD7; written
                                         ; to TS by Ppu_ApplyMapScreens)
!Ppu_W12SelShadow = $0BD9                ; 8-bit; the NMI handler writes it to W12SEL ($C0:EC19)
!Ppu_W34SelShadow = $0BDA                ; 8-bit; the NMI handler writes it to W34SEL ($C0:EC1F)
!Ppu_WObjSelShadow = $0BDB               ; 8-bit; the NMI handler writes it to WOBJSEL ($C0:EC25)
!Ppu_Wh2Shadow = $0BDC                   ; 8-bit; the NMI handler writes it to WH2 ($C0:EC2B)
!Ppu_Wh3Shadow = $0BDD                   ; 8-bit; the NMI handler writes it to WH3 ($C0:EC31)
!Ppu_CgwSelShadow = $0BDE                ; 8-bit; the NMI handler writes it to CGWSEL ($C0:EC37); 2
                                         ; at load (Field_InitLoadState)
!Ppu_Unk0BDF = $0BDF                     ; 8-bit; the CGADSUB value (Ppu_ApplyMapScreens writes it
                                         ; there; LocLoad_UnkA33B sets it from MapProps.ColorMath):
                                         ; copied after the CGWSEL
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
!Audio_CmdArg2 = $1E03                   ; 8-bit third command argument (the last byte of the block
                                         ; Audio_DriverCommand sends; bank $C2's C2Scene_QueueSoundCmd
                                         ; fills all four bytes $1E00-$1E03)
!Field_Unk7E2000 = $7E2000               ; 16-bit; zeroed by Field_InitLoadState, no other matched use
!Pal_Buf = $7E2000                       ; alias of Field_Unk7E2000: a palette (16 rows of 16 BGR555
                                         ; colours) that Pal_LoadUnkRow0 copies to Pal_CgramBuf, the
                                         ; CGRAM upload source; LocLoad_Unk7084 fills rows 1-7
!Pal_LocRows = $7E2022                   ; Pal_Buf row 1, colour 1: where LocLoad_Unk7084 copies the
                                         ; location's seven rows (colour 0 of each row is skipped)
!Pal_SpriteRows = $7E2100               ; Pal_Buf row 8, the first sprite palette (Obj_PalSlot 0)
!Pal_CgramBuf = $7E2200                  ; Pal_BufBytes sent to CGRAM by Pal_UploadCgram (NMI side);
                                         ; Pal_LoadUnkRow0 copies all of Pal_Buf here
!FieldRom_PalRow0Sets = $FFB210          ; ROM: colour sets 16 bytes apart; Pal_LoadUnkRow0 copies 30
                                         ; bytes from entry + 2 to Pal_Buf row 0
!FieldRom_Unk9CF0 = $FF9CF0              ; ROM: four 64-byte pieces Field_UploadUnk0000 sends to VRAM
!FieldRom_Unk9260 = $FF9260              ; ROM: 64 bytes Field_UploadUnk57E0 sends to VRAM $57E0
!Field_Unk7EF000 = $7EF000               ; WRAM source of Field_UploadUnk1C00/1D00 (VRAM $1C00/$1D00);
                                         ; Field_Unk29F7 / Field_Unk2B78 write the two tilemaps
!Field_Unk7EF000RunEnd = $D9             ; alias of Eng_Scratch in Field_Unk2B78 (written absolute,
                                         ; $01D9): last tile of the current run
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
!Field_Unk7E2989 = $7E2989               ; 8-bit; zeroed by Field_InitLoadState; FieldBtl_SavePartyPos
                                         ; ORs its TileAttr_PrioBit with FieldBtl_PcPrio into the
                                         ; party's Obj_PrioLow/High
!FieldBtl_Result = $7F01EC               ; 8-bit; read by Scene_Unk0283 and FieldBtl_Restore after a
                                         ; battle: 0 = rebuild the field, 1 = wait for a button
                                         ; and restart through GameLoop, 2 = reload Loc_PrevId
                                         ; (each unless FieldBtl_EvtFlags says not). Bank $C1 stores 1 at
                                         ; $C1:813C and 0 at $C1:817B/81FA/8358; who stores 2 is not
                                         ; found. AudioFadeDispatch also reads it
!FieldBtl_EvtFlags = $7E2A1F             ; 8-bit; an event opcode copies it from the script
                                         ; ($C0:3A9F). Bit 5 (FieldBtl_EvtNoReset) and bit 7
                                         ; (FieldBtl_EvtUnk80) are tested by Scene_Unk0283 /
                                         ; Field_Unk034B, bit 4 probably meant to be (see
                                         ; Scene_Unk0283); MusicCueDispatch reads bit 6
!FieldBtl_AttrA = $7E2A23                ; 256 B: the 16 x 16 window of Map_TileAttrA at the screen
                                         ; origin, rows of 16 (FieldBtl_SaveTileAttrs); read by the
                                         ; battle code (not traced)
!FieldBtl_AttrB = $7E2B23                ; 256 B: the same window of Map_TileAttrB
!Audio_Unk7F01ED = $7F01ED               ; 8-bit; nonzero: LocLoad_AudioSetup sends Menu_Config1E
                                         ; again instead of the location's LocRom.Music (who sets it
                                         ; is not traced)
!Eng_Unk7F0000 = $7F0000                 ; 8-bit; Field_FadeToBankC2Mode5 only proceeds when it is >=
                                         ; $49 (purpose unknown)
!Treasure_Flags = $7F0001                ; 64 bytes: one bit per treasure number (bit n & 7 of byte
                                         ; n >> 3, BitSet order), set by Field_CheckTileInFront when
                                         ; the treasure is taken; a set bit means already opened
!Treasure_ItemId = $7F0200               ; 16-bit item id of the last treasure item taken
                                         ; (Field_CheckTileInFront; reader not traced, probably the
                                         ; message)
!Evt_Unk7F0200 = $7F0200                 ; alias of Treasure_ItemId: start of the Evt_Unk7F0200Bytes
                                         ; Evt_InitObjects clears at each location load
!Field_Unk7F03FE = $7F03FE               ; 8-bit; when 1-2 Field_RestoreState stacks party members
                                         ; 2/3 on the leader and sets it to 3
!Rom_DirToFacing = $C0F700               ; 256 bytes in ROM: the Obj_Facing (0 up, 1 down, 2 left, 3
                                         ; right) for each Obj_Direction: $E0-$1F right, $20-$5F
                                         ; down, $60-$9F left, $A0-$DF up; read absolute through
                                         ; the bank $00 mirror by the event movement opcodes
!Rom_AngleTable = $C0F300                ; 32 x 32 bytes in ROM: angle (256 per turn, $40 = a
                                         ; quarter) of the vector (run, rise) at rise x 32 + run;
                                         ; Obj_CalcDirection reads it through DB=$00 (the table the
                                         ; battle code calls !BattleRom_AngleTable)
!Rom_SineTable256 = $C0F800              ; 256 signed bytes in ROM: 127 x sin, 256 steps per turn
                                         ; ($00, $7F at +$40, $81 at +$C0); Obj_SetVelocity* read
                                         ; it through DB=$00 (sine at the direction, cosine at +$40)
!Rom_SineTable = $C0F900                 ; 1024 B in ROM: |sin| for 1024 steps per turn, $00 at +$000/+$200,
                                         ; $FF at +$100/+$300 (the table the battle code calls !BattleRom_SineTable)
!RomE4_PtrInit = $E4FFE0                 ; 4 words in ROM: initial low words of Field_E4Ptr0-3
                                         ; (Field_InitLoadState)

; --- Location event data / saved field state ---
!Evt_ObjCount = $7F2000                  ; 8-bit count of location objects; Obj_ResetStates clears
                                         ; that many Obj_State entries
!Evt_DataAddr = $2001                    ; Evt_Data's address within bank $7F (Evt_Op4E_CopyData
                                         ; turns offsets into MVN source addresses with it)
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
!Map_Unk7F3700 = $7F3700                 ; 4 blocks of Map_Unk7F3700RecBytes and one of 6 bytes,
                                         ; seeded from ROM at each location load
                                         ; (LocLoad_InitUnk7F3700); Map_Unk7F3728/3748/3768/3781 lie
                                         ; inside them
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
!ObjX_Unk7F0C00 = $7F0C00                ; 8-bit; Map_InitEntryTile zeroes byte 0 of it and of the three
                                         ; below at a location load (probably $80-byte per-object
                                         ; tables like the ObjX_* ones above; no reader traced)
!ObjX_Unk7F0C80 = $7F0C80                ; as ObjX_Unk7F0C00
!ObjX_Unk7F0D00 = $7F0D00                ; as ObjX_Unk7F0C00
!ObjX_Unk7F0D80 = $7F0D80                ; as ObjX_Unk7F0C00

; --- OAM shadow ---
!Obj_PalPrev = $0B00                     ; 8-bit per object (index Obj_Cur): the object before it in
                                         ; its palette slot's list ($80 = none); Obj_Unk7170 links,
                                         ; Obj_Unk734C unlinks
!Obj_PalNext = $0B01                     ; 8-bit per object: the object after it in that list ($80 =
                                         ; none, i.e. it is the slot's newest)
!Obj_PalSlot = $0B80                     ; 8 bytes, one per sprite palette (Pal_Buf rows 8-15): the
                                         ; newest object using it, $80 (Field_Unk0B80Empty) = free;
                                         ; claimed by Obj_Unk7170 / Obj_Unk72B4, freed by
                                         ; Obj_Unk734C; reset at load (Field_ResetUnk0B80)
!Field_Unk0B80 = !Obj_PalSlot            ; older name of Obj_PalSlot, still used by
                                         ; Field_ResetUnk0B80 (rename there on its next edit)
!Obj_TileSlot = $0B88                    ; Field_Unk0B88Bytes bytes: the object owning each OBJ tile
                                         ; slot (Obj_Unk6F9A's allocator), $80 = free; reset at load
                                         ; (Field_ResetUnk0B88)
!Field_Unk0B88 = !Obj_TileSlot           ; older name of Obj_TileSlot, still used by
                                         ; Field_ResetUnk0B88
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
!Obj_DrawPrev = $0E80                    ; 8-bit per object: previous object in its draw bucket (bit
                                         ; 7 = it is the first); Obj_DrawLink / Obj_DrawUnlink
!Obj_DrawOut = $0E01                     ; 8-bit per object, index object x 2, so it is the high
                                         ; byte of Obj_DrawBucket word n for object n: 0 = in a
                                         ; draw bucket, bit 7 = in none (Obj_DrawLink /
                                         ; Obj_DrawUnlink)
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
!Obj_Unk1B01 = $1B01                     ; 8-bit per object (the odd byte next to Obj_State); bit 0
                                         ; set: the object blocks the leader (Map_ProbeHitsObj)
!Obj_Unk1C00 = $1C00                     ; 8-bit per object; Evt_RunObjInit sets 7 after the init
                                         ; function; Evt_StartTargetFunc1 needs it >= 2, saves
                                         ; Obj_ScriptPos in the ObjX_Unk7F0580 table of that level
                                         ; and sets 1 (looks like the priority of the running
                                         ; function, lower = more urgent; not established)
!Obj_Unk1C01 = $1C01                     ; 8-bit per object; nonzero blocks Evt_StartTargetFunc1
!Obj_Unk1000 = $1000                     ; 8-bit per object; bit 7 blocks Evt_StartTargetFunc1 and
                                         ; Vblank_Unk59D9's timer; the low bits are the frames between
                                         ; script runs (reloaded into Obj_Unk1001)
!Obj_Unk1001 = $1001                     ; 8-bit per object; zeroed by Evt_StartTargetFunc1: the
                                         ; countdown to the object's next script run (Vblank_Unk59D9)
!Obj_Unk1A01 = $1A01                     ; 8-bit per object; zeroed by Evt_StartTargetFunc1
!Obj_Unk1A00 = $1A00                     ; 8-bit per object; Obj_Unk1A00Init at load (Evt_InitObjects)
!Obj_Unk1B80 = $1B80                     ; 16-bit per object; zeroed by Evt_InitObjects
!Obj_Unk1C80 = $1C80                     ; 8-bit per object; Obj_Unk1C80Init at load (Evt_InitObjects)
!Obj_Unk1C81 = $1C81                     ; 8-bit per object (odd byte of the $1C80 words): bit 0
                                         ; (Obj1C81_CentreOnTile) makes the walk-to-tile opcodes run
                                         ; Obj_Unk305D on arriving, bit 1 (Obj1C81_OntoObj) the
                                         ; walk-to-object ones Obj_Unk30B3
!Obj_Unk1900 = $1900                     ; a page ($100 bytes) cleared by Evt_InitObjects; probably a
                                         ; per-object table (the object tables lie around it)
!Obj_Unk1A80 = $1A80                     ; 8-bit per object; zeroed by Evt_StartTargetFunc1; the event
                                         ; movement opcodes keep it nonzero while a timed move they
                                         ; started (arc, direction, a single step) runs
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
!Obj_Unk1080 = $1080                     ; 8-bit per object; ObjQ_Empty at load (Evt_InitObjects):
                                         ; the next object in the ObjQ_Unk74 list ($80 = last / not
                                         ; queued)
!Obj_QueueNext = $1081                   ; 8-bit per object: next object in the frame-build queue
                                         ; ($80 = not queued / end)
!Obj_Unk1100 = $1100                     ; 8-bit per object; bit 7 = skip; 0 = queue at the head; 1/2
                                         ; = queue at the tail (head when ObjQ_Unk78 = 2)
!Obj_Unk1101 = $1101                     ; 8-bit per object (odd byte of the $1100 words);
                                         ; FieldBtl_SaveObj copies it to FieldBtlObj.Unk05
!Obj_FixedFrame = $1301                  ; 8-bit per object: frame number used when Obj_AnimMode = 3
                                         ; (no animation lookup)
!Obj_PalSrc = $1400                      ; 16-bit per object: offset in bank $E4 of its 12 sprite
                                         ; colours (Obj_Unk7170 / Obj_Unk72B4 copy them to colours
                                         ; 1-12 of its palette; objects with the same offset share a
                                         ; palette slot)
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
!ObjX_Unk7F0B00 = $7F0B00                ; 8-bit per object in bank $7F; Evt_InitObjects writes 0
                                         ; (then clears it again with the ObjX_* block)
!ObjX_Unk7F0B80 = $7F0B80                ; 16-bit per object in bank $7F; Evt_InitObjects writes
                                         ; ObjX_Unk7F0B80Init twice, then clears it again
!ObjX_AnimLoops = $7F0B01                ; 8-bit per object in bank $7F: loops left for animation
                                         ; mode 2
!AnimRom = $E40000                       ; bank $E4: object animation tables (frame numbers and
                                         ; durations), reached through Obj_AnimFrameTbl /
                                         ; Obj_AnimTimeTbl

; --- Saved field block (menu round trip) ---
!Field_SaveBlock = $0920                 ; start of the $14E0-byte WRAM block Field_StashSaveBlock
                                         ; copies to SceneSave_Buffer before the menu and
                                         ; Field_RestoreSaveBlock copies back
!Evt_Unk0920 = $0920                     ; 16 bytes at the start of Field_SaveBlock: a list, Evt_Unk0920Free
                                         ; = free (Evt_ClearUnk0920); Evt_FindOrAddUnk0920
                                         ; searches it for Evt_Unk0920Key and adds entries
!Evt_Unk0930 = $0930                     ; 16 bytes: the Obj_Cur of each Evt_Unk0920 entry
                                         ; (Evt_FindOrAddUnk0920)
!SceneSave_Buffer = $7F2000              ; $7F:2000: destination of the Field_SaveBlock copy (same
                                         ; address as Evt_ObjCount, used at a different time)

; --- Map ---
!LocGfx_Stage = $7E3000                  ; alias of Map_TileProps: each layer graphics pack is unpacked
                                         ; here and uploaded to VRAM (LocLoad_UploadPack), before the
                                         ; map's planes are unpacked over it
!LocGfx_Unk7F6000 = $7F6000              ; LocGfx_Lists pack 6 unpacked here; no reader traced
!LocGfx_Unk7F7000 = $7F7000              ; LocGfx_Lists pack 7 unpacked here; no reader traced
!LocGfx_StageL3 = $7F5080                ; the LocRom.Tileset3 pack is unpacked here and uploaded to
                                         ; VRAM LocGfx_VramL3 (LocLoad_Unk6DCF)
!LocGfx_PackListPtr = $D6                ; alias of Anim_FramePtr (dp, 24-bit): LocLoad_Unk0960 points it
                                         ; at the location's LocGfx_Lists entry, one pack per step
!Map_TileProps = $7E3000                 ; one byte per map tile, row stride $100 (index = row*256 +
                                         ; column); values $E6/$EC/$EE/$FA/$FC select tile-animation
                                         ; modes. "Props" is a guess: matched code only uses it for
                                         ; tile-animation states
!Map_Layer2Tiles = $7E3040              ; as Map_TileProps for layer 2: the low 8 bits of each
                                         ; tile's metatile number, row stride $100 (read by
                                         ; Map_WriteRow2/Col2; inferred: the three layers sit side by
                                         ; side in each 256-byte map row, layer 1 at +$00)
!Map_Layer3Tiles = $7E3080              ; as Map_Layer2Tiles for layer 3 (Map_WriteRow3/Col3); the
                                         ; full metatile number, 0-255
!Map_TileHiBits = $7E30C0               ; per map tile, same index as Map_TileProps: bit 0 is bit 8
                                         ; of the layer-1 metatile number, bit 1 of layer 2's
                                         ; (Map_WriteRow1/2, Map_WriteCol1/2)
!Map_TileAttrA = $7E7000                 ; one byte per map tile, index as Map_TileProps (masked
                                         ; with Map_ColMask1/RowMask1): bits 0-1 push direction (0
                                         ; up, 1 down, 2 left, 3 right), bits 2-3 push speed (0 none),
                                         ; bit 4 starts a tile animation when it is the tile one row
                                         ; ahead of the leader's new position, bit 6
                                         ; OAM priority for Obj_PrioLow (Map_ProbeTileLevel,
                                         ; Map_StepTileEffects; "push" inferred from Map_Unk1D2A/1D2B
                                         ; being the per-frame base step)
!Map_TileAttrB = $7E7040                 ; as Map_TileAttrA: bits 0-1 / 3-4 the level of the tile's
                                         ; half A / half B, bit 2 / bit 5 their "no level" bits, bit 6
                                         ; OAM priority for Obj_PrioHigh (Map_ProbeTileLevel)
!Map_TileExitIdx = $7E7080               ; as Map_TileAttrA: bit 7 clear = the tile is an exit,
                                         ; record (value) of the location's ExitRom list
!Map_Meta12TL = $7EB000                 ; metatile table of layers 1 and 2: 8 bytes per 16x16
                                         ; metatile (index = number x 8), four tilemap words;
                                         ; this one the top-left 8x8 tile (inferred from which
                                         ; words a top / bottom half and a left / right half write)
!Map_Meta12TR = $7EB002                 ; top-right word of a Map_Meta12TL entry
!Map_Meta12BL = $7EB004                 ; bottom-left word
!Map_Meta12BR = $7EB006                 ; bottom-right word
!Map_Meta3TL = $7EC000                  ; as Map_Meta12TL for layer 3 (256 metatiles)
!Map_Meta3TR = $7EC002                  ; as Map_Meta12TR for layer 3
!Map_Meta3BL = $7EC004                  ; as Map_Meta12BL for layer 3
!Map_Meta3BR = $7EC006                  ; as Map_Meta12BR for layer 3

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
!Evt_Mem7F = $7F0000                     ; start of bank $7F as the event opcodes address it: the byte
                                         ; or word at $7F:0000 + an operand (Eng_Unk7F0000,
                                         ; Treasure_Flags and Evt_Unk7F0200 lie there)
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
!Hdma_Unk7F14F0 = $7F14F0                ; 8-bit; NmiHandler stores Map_TilemapVram's high byte | 1
                                         ; here after redraw steps 1 and 2 (see Hdma_Unk7F14F1)
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
                                         ; write through WMDATA; Map_ClearBufC800 zeroes it. The
                                         ; layer-1 edge builders write a row at its start and a
                                         ; column at +Map_BufColOfs (Map_BuildRow*1/Col*1)
!Map_BufD000 = $7ED000                   ; as Map_BufC800 for the layer-2 edge builders
                                         ; (Map_BuildRow*2*/Col*2*)
!Map_BufD800 = $7ED800                   ; as Map_BufC800 for the layer-3 edge builders; the same
                                         ; address as Credits_LineBuf, used at another time
!Credits_LineBuf = $7ED800               ; 64 bytes: one tilemap row (32 words) built by
                                         ; Field_ServiceUnk54, DMAed to VRAM by the NMI ($C0:EC77)

; --- Map page $1D00 (absolute, or dp with DP = !DP_Map) ---
; Layer numbers 1-3 below follow Map_Unk93E1's three sets of scroll words
; (Map_Unk1D87/89, 1D8B/8D, 1D8F/91); set 1 follows the camera step
; Map_Unk1D2E/1D30. That they are BG1-BG3 is likely, not traced.
!Map_ScrollToMode = $1D00                ; 8-bit; nonzero makes Map_Unk91AC set Map_Unk1D2E/1D30 to
                                         ; +/-$10 towards Map_ScrollToX/Y; it stores 2 when both
                                         ; have arrived (inferred: a scroll-to request; who sets it
                                         ; is not traced)
!Map_ScrollToDone = $1D01                ; 8-bit; bit 0 / bit 1 set by Map_Unk91AC when X / Y has
                                         ; arrived; zeroed when both have
!Map_ScrollToX = $1D02                   ; 8-bit target compared with Map_TileOriginX's low byte
!Map_ScrollToY = $1D03                   ; 8-bit target compared with Map_TileOriginY's low byte
!Map_TreasureRec0 = $1D06                ; 16-bit TreasureRom offset that treasure numbers count from:
                                         ; Field_CheckTileInFront numbers a record (offset -
                                         ; this) / 4 for Treasure_Flags. Map_LoadTreasureTiles sets
                                         ; it to the first word of TreasureRom_LocOfs
!Map_TreasureLocRecs = $1D08             ; 16-bit TreasureRom offset of the current location's
                                         ; record 0 (Map_TreasureIdx values index from it); set by
                                         ; Map_LoadTreasureTiles
!Map_Unk1D0C = $1D0C                     ; 16-bit; its low byte / 2 is the upper column bound of
                                         ; Field_ServiceUnk54's bit-5 box (Map_TileOriginX the lower)
!Map_Unk1D10 = $1D10                     ; 16-bit; as Map_Unk1D0C for rows (Map_TileOriginY lower)
!Map_Unk1D12 = $1D12                     ; 8-bit; layer 2 at half rate, as Map_TileOriginX for
                                         ; layer 1: Map_Scroll2XIncHalf / XDecHalf step it with
                                         ; Map_Unk1D14 every 16 steps; the half-rate layer-2 builders
                                         ; take it minus 1 as a row's first column, and as the
                                         ; column of a left-edge column
!Map_Unk1D14 = $1D14                     ; 8-bit; as Map_Unk1D0C for half-rate layer 2: the column
                                         ; Map_BuildColXInc2Half builds
!Map_Unk1D16 = $1D16                     ; 8-bit; as Map_TileOriginY for half-rate layer 2
                                         ; (Map_Scroll2Y*Half; the row Map_BuildRowYDec2Half builds)
!Map_Unk1D18 = $1D18                     ; 8-bit; as Map_Unk1D10 for half-rate layer 2 (the row
                                         ; Map_BuildRowYInc2Half builds)
!Map_Unk1D1A = $1D1A                     ; 8-bit column: Map_Unk9175 keeps a leftward Map_Unk1D2E
                                         ; out of Map_Unk1D32 once the leader's Obj_TileX <= it;
                                         ; Map_StepStopLeft compares Map_TileOriginX / 2 with it
                                         ; (looks like a left scroll limit; not established). Set by
                                         ; Map_InitMasksAndLimits from LocRom.LimitLeft, or 0
!Map_Unk1D1B = $1D1B                     ; 8-bit column: as Map_Unk1D1A to the right (leader
                                         ; Obj_TileX >= it; Map_StepStopRight against
                                         ; Map_Unk1D0C / 2); LocRom.LimitRight, or Map_Unk0BCB - 1
!Map_Unk1D1C = $1D1C                     ; 8-bit row: as Map_Unk1D1A upwards (leader Obj_TileY <=
                                         ; it + 1; Map_StepStopUp against Map_TileOriginY / 2);
                                         ; LocRom.LimitTop, or 0
!Map_Unk1D1D = $1D1D                     ; 8-bit row: as Map_Unk1D1A downwards (leader Obj_TileY >
                                         ; it; Map_StepStopDown against Map_Unk1D10 / 2);
                                         ; LocRom.LimitBottom, or Map_Unk0BCD - 1
!Map_ColMask1 = $1D1E                    ; 8-bit AND mask on layer 1's metatile column in
                                         ; Map_WriteRow1/Col1 (wraps the column): $0F/$1F/$3F for
                                         ; a Map_Unk0BCB of $10/$20/$30-$40 (Map_InitMasksAndLimits;
                                         ; a 48-wide layer wraps at 64). A 16-bit AND with it also
                                         ; masks the row with Map_RowMask1
!Map_RowMask1 = $1D1F                    ; 8-bit; as Map_ColMask1 for layer 1's metatile row
!Map_ColMask2 = $1D20                    ; 8-bit; as Map_ColMask1 for layer 2 (Map_WriteRow2/Col2)
!Map_RowMask2 = $1D21                    ; 8-bit; as Map_RowMask1 for layer 2
!Map_ColMask3 = $1D22                    ; 8-bit; as Map_ColMask1 for layer 3 (Map_WriteRow3/Col3)
!Map_RowMask3 = $1D23                    ; 8-bit; as Map_RowMask1 for layer 3
!Map_Drift1X = $1D24                     ; 8-bit signed amount Map_Unk91AC adds to Map_Acc1X every
                                         ; frame; Map_Drift1X..Map_Drift3Y are zeroed when
                                         ; Map_DriftTimer runs out
!Map_Drift1Y = $1D25                     ; 8-bit; as Map_Drift1X for Map_Acc1Y
!Map_Drift2X = $1D26                     ; 8-bit; as Map_Drift1X for Map_Acc2X
!Map_Drift2Y = $1D27                     ; 8-bit; as Map_Drift1X for Map_Acc2Y
!Map_Drift3X = $1D28                     ; 8-bit; as Map_Drift1X for Map_Acc3X
!Map_Drift3Y = $1D29                     ; 8-bit; as Map_Drift1X for Map_Acc3Y
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
!Map_LayerEdgeOff = $1D35                ; 8-bit; bit 1 / bit 2: the normal-rate steppers of layer
                                         ; 2 / 3 don't set Map_Edge* bits for it (the half-rate
                                         ; layer-2 steppers ignore it)
!Map_OwnStepFlags = $1D36                ; 8-bit; bit 1 (bit 2): Map_Unk91AC moves set 2 (set 3) by
                                         ; its Map_OwnStep and drift only, without the camera step
                                         ; Map_Unk1D2E/1D30 and the shake
!Map_OwnStep2X = $1D37                   ; 8-bit signed X amount Map_Unk91AC adds to Map_Acc2X every
                                         ; frame (with or without Map_OwnStepFlags bit 1)
!Map_OwnStep2Y = $1D38                   ; 8-bit; as Map_OwnStep2X for Y
!Map_OwnStep3X = $1D39                   ; 8-bit; as Map_OwnStep2X for set 3 (flag bit 2)
!Map_OwnStep3Y = $1D3A                   ; 8-bit; as Map_OwnStep3X for Y
!Map_Acc1X = $1D3B                       ; 8-bit signed accumulator of set 1, X, in 1/16 pixel (a
                                         ; walking camera step of $10 moves 1): Map_Unk91AC adds the
                                         ; frame's amounts, moves the whole pixels out to
                                         ; Map_Move1XNeg/Pos and keeps the signed remainder
!Map_Acc1Y = $1D3C                       ; 8-bit; as Map_Acc1X for Y (Map_Move1YNeg/Pos)
!Map_Acc2X = $1D3D                       ; 8-bit; as Map_Acc1X for set 2
!Map_Acc2Y = $1D3E                       ; 8-bit; as Map_Acc1Y for set 2
!Map_Acc3X = $1D3F                       ; 8-bit; as Map_Acc1X for set 3
!Map_Acc3Y = $1D40                       ; 8-bit; as Map_Acc1Y for set 3
!Map_Move1XNeg = $1D41                   ; 8-bit pixels set 1 moves this frame in -X (0 when it
                                         ; moves in +X); written by Map_Unk91AC, used as the step
                                         ; count of Map_Scroll1XDec (Map_Unk93E1)
!Map_Move1XPos = $1D42                   ; 8-bit pixels in +X (0 when moving in -X); Map_Scroll1XInc
!Map_Move1YNeg = $1D43                   ; 8-bit; as Map_Move1XNeg for -Y (Map_Scroll1YDec)
!Map_Move1YPos = $1D44                   ; 8-bit; as Map_Move1XPos for +Y (Map_Scroll1YInc)
!Map_Move2XNeg = $1D45                   ; 8-bit; as Map_Move1XNeg for set 2 (Map_Scroll2XDec*)
!Map_Move2XPos = $1D46                   ; 8-bit; as Map_Move1XPos for set 2 (Map_Scroll2XInc*)
!Map_Move2YNeg = $1D47                   ; 8-bit; as Map_Move1YNeg for set 2 (Map_Scroll2YDec*)
!Map_Move2YPos = $1D48                   ; 8-bit; as Map_Move1YPos for set 2 (Map_Scroll2YInc*)
!Map_Move3XNeg = $1D49                   ; 8-bit; as Map_Move1XNeg for set 3 (Map_Scroll3XDec)
!Map_Move3XPos = $1D4A                   ; 8-bit; as Map_Move1XPos for set 3 (Map_Scroll3XInc)
!Map_Move3YNeg = $1D4B                   ; 8-bit; as Map_Move1YNeg for set 3 (Map_Scroll3YDec)
!Map_Move3YPos = $1D4C                   ; 8-bit; as Map_Move1YPos for set 3 (Map_Scroll3YInc)
!Map_DriftTimer = $1D4D                  ; 8-bit frame countdown; when Map_Unk91AC counts it to 0 it
                                         ; zeroes Map_Drift1X..Map_Drift3Y (0 = not running)
!Map_ShakeX = $1D4E                      ; 8-bit signed X amount Map_Unk91AC adds to sets 1-3 (not
                                         ; to a set with its Map_OwnStepFlags bit): +/-$10 from
                                         ; Eng_Unk0400 while Field_UnkBC is set, 0 while
                                         ; Map_TileOriginX is 0 (inferred: a screen shake)
!Map_ShakeY = $1D4F                      ; 8-bit; as Map_ShakeX for Y (Map_TileOriginY)
!Map_StepTestN = $1D52                   ; 8-bit scratch of the Map_StepStop* tests: the step / 16
                                         ; (Down, Right) or Map_TileOriginY/X / 2 (Up, Left)
!Map_StepTestN2 = $1D54                  ; 8-bit scratch of Map_StepStopUp/Left: the step / 16
!Map_WrCol = $1D52                       ; alias of Map_StepTestN: 8-bit scratch of the row / column
                                         ; writers (Map_WriteRow*/Col*): the metatile column
                                         ; (Map_BuildCol / 2, masked with the layer's column mask)
!Map_WrRow = $1D54                       ; alias of Map_StepTestN2: the writers' metatile row
!Map_SpanRowOfs = $1D52                  ; alias of Map_StepTestN, 16-bit: row x 32, the tilemap
                                         ; offset of a row, in the Bg_*Span64x32 helpers
!Map_BuildCol = $1D58                    ; 8-bit argument of the row / column writers ($C0:7612 ...):
                                         ; the first column of a row, or the column of a column
                                         ; (Map_Build*); units as the writers use them, not traced
!Map_BuildRow = $1D5A                    ; 8-bit; as Map_BuildCol: the row, or the first row of a
                                         ; column
!Map_BuildLen = $1D5C                    ; 8-bit; as Map_BuildCol: how many entries to write
                                         ; (in metatiles, two 8x8 tilemap words each; see the writers)
!Map_RowsLeft = $1D5E                    ; 8-bit row counter of Field_BuildC800Mode1/2/4
!Map_SpanWrapVram = $1D5E                ; 16-bit, the same bytes as Map_RowsLeft at another time:
                                         ; Bg_RowSpan64x32's third piece (row start of the first
                                         ; piece's screen), read by Sub_C07F9A
!Map_SpanCol = $1D62                     ; 16-bit argument copy of the Bg_*Span64x32 helpers: the
                                         ; tilemap column (0-63); scratch (Map_Unk8A6D uses
                                         ; $1D62-$1D68 for other things)
!Map_SpanRow = $1D64                     ; 16-bit; Bg_ColSpan64x32's row (0-31)
!Map_SpanLen3 = $1D6A                    ; 16-bit; Bg_RowSpan64x32: bytes in the third piece (2 or 0)
!Map_SpanLen1 = $1D6C                    ; 16-bit; Bg_RowSpan64x32 / Bg_ColSpan64x32: bytes in the
                                         ; first piece (to the end of the screen's row / column)
!Map_SpanLen2 = $1D6E                    ; 16-bit; as Map_SpanLen1 for the second piece
!Map_StepCount = $1D66                   ; 8-bit loop counter of the Map_Scroll* steppers (pixels
                                         ; left to step); a scratch byte, other unmatched code
                                         ; uses $1D66 as a 16-bit value
; --- Map_Unk8A6D and its tile / object probes ($1D04, $1D2F-$1D34, $1D52-$1D73 as their
;     scratch; most of these bytes have other names at other times, see above) ---
!Map_ExitRec0 = $1D04                    ; 16-bit ExitRom offset of the current location's exit
                                         ; record 0 (Map_TileExitIdx values x 7 are added to it in
                                         ; Map_StepTileEffects); set by Map_LoadExitTiles from
                                         ; ExitRom_LocOfs
!Map_Unk1D2EHi = $1D2F                   ; 8-bit high byte that makes Map_Unk1D2E a 16-bit signed
                                         ; step: Map_Unk8A6D sets it to $00 / $FF by the step's sign
                                         ; before its 16-bit adds (16-bit stores of Map_Unk1D2E also
                                         ; clear it)
!Map_Unk1D30Hi = $1D31                   ; 8-bit; as Map_Unk1D2EHi for Map_Unk1D30
!Map_Unk1D34 = $1D34                     ; 8-bit; Map_StepTileEffects stores Map_ProbeMoveFlags here
                                         ; for every step it commits (bit 2: a shape-$1E tile, bit 3:
                                         ; a pushing tile); readers not traced
!Map_PushSpeed = $1D52                   ; alias of Map_StepTestN: 8-bit scratch of
                                         ; Map_StepTileEffects, the push amount ($08/$10/$20)
!Map_ExitScratch = $1D52                 ; alias of Map_StepTestN: 8-bit; Map_StepTileEffects keeps
                                         ; ExitRom.DestHiFacing here while it splits it
!Map_SlopeTest = $1D54                   ; alias of Map_StepTestN2: 8-bit scratch of
                                         ; Map_ProbeTileLevel, the probe's side of a shape's line
!Map_ProbeFracY4 = $1D56                 ; 8-bit; Map_ProbeTileLevel: the low byte of Map_ProbeY / 4
                                         ; (the probe's height inside its tile, 0-63)
!Map_ProbeHiBits = $1D58                 ; alias of Map_BuildCol: 8-bit Map_TileHiBits of the probed
                                         ; tile (Map_ProbeTileAttrs); bits 2-7 are its shape number
!Map_ProbeAttrA = $1D5A                  ; alias of Map_BuildRow: 8-bit Map_TileAttrA of the probed
                                         ; tile
!Map_ProbeAttrB = $1D5C                  ; alias of Map_BuildLen: 8-bit Map_TileAttrB of the probed
                                         ; tile
!Map_ProbeMoveFlags = $1D5E              ; alias of Map_RowsLeft: 8-bit; Map_ProbeTileLevel sets it to
                                         ; 0, or Map_ProbeShape1E for a shape-$1E tile;
                                         ; Map_StepTileEffects adds Map_ProbePushing
!Map_ProbeShape = $1D60                  ; 8-bit; Map_ProbeTileLevel: shape number - 2 (left 0 for
                                         ; shapes 0 and 1)
!Map_LeaderX = $1D62                     ; 16-bit; Map_Unk8A6D's copy of the leader's Obj_PosX (the
                                         ; same bytes as Map_SpanCol at another time)
!Map_LeaderY = $1D64                     ; 16-bit; as Map_LeaderX for Obj_PosY (Map_SpanRow)
!Map_ProbeX = $1D66                      ; 16-bit Obj_PosX-style X of the point being tested (an edge
                                         ; of the leader's box plus the step); Map_StepTileEffects
                                         ; leaves the leader's new X here (Map_StepCount's bytes)
!Map_ProbeTileX = $1D67                  ; 8-bit high byte of Map_ProbeX: its map column
!Map_ProbeY = $1D68                      ; 16-bit; as Map_ProbeX for Y
!Map_ProbeTileY = $1D69                  ; 8-bit high byte of Map_ProbeY: its map row
!Map_ProbeLevel = $1D6A                  ; alias of Map_SpanLen3: 8-bit level of the probed half
                                         ; tile (0-3; Map_ProbeLevelBlocked; inferred from how it is
                                         ; compared with Field_Unk55)
!Map_ProbeNoLevel = $1D6C                ; alias of Map_SpanLen1: 8-bit, nonzero when the half tile's
                                         ; "no level" bit is set (Map_TileAttrB bit 2 / bit 5)
!Map_ProbePrio = $1D6E                   ; alias of Map_SpanLen2: 8-bit OAM priority bits for the
                                         ; leader's Obj_PrioLow ($20 or $30, from Map_TileAttrA bit 6)
!Map_ProbePrioHi = $1D6F                 ; 8-bit; as Map_ProbePrio for Obj_PrioHigh (Map_TileAttrB
                                         ; bit 6)
!Map_DestX = $1D70                       ; 16-bit; Map_StepTileEffects: the leader's new X
                                         ; (Map_LeaderX + the X step)
!Map_DestTileX = $1D71                   ; 8-bit high byte of Map_DestX: its map column
!Map_NextRowY = $1D72                    ; 16-bit; Map_StepTileEffects: the leader's new Y one tile
                                         ; further on (up for a negative Y step, else down)
!Map_NextRowTileY = $1D73                ; 8-bit high byte of Map_NextRowY: its map row
!Map_EdgeRowYInc = $1D74                 ; 8-bit; bit 0/1/2: layer 1/2/3 crossed an 8-pixel row
                                         ; boundary with its Y scroll rising this frame (set by the
                                         ; Map_Scroll*YInc steppers); Map_EdgeRowsYInc then runs that
                                         ; layer's row builder (inferred: a new row comes into view)
!Map_EdgeRowYDec = $1D75                 ; 8-bit; as Map_EdgeRowYInc, Y falling (Map_EdgeRowsYDec)
!Map_EdgeColXInc = $1D76                 ; 8-bit; as Map_EdgeRowYInc for columns, X rising
                                         ; (Map_EdgeColsXInc)
!Map_EdgeColXDec = $1D77                 ; 8-bit; as Map_EdgeColXInc, X falling (Map_EdgeColsXDec)
!Map_BuiltRowYInc = $1D78                ; 8-bit; bit 0/1/2: Map_BuildRowYInc1/2/3 (or 2Half) wrote a
                                         ; row for layer 1/2/3 into its buffer this frame; zeroed
                                         ; with the next three by Map_Unk93E1 first (probably for
                                         ; the NMI to copy; readers not traced)
!Map_BuiltRowYDec = $1D79                ; 8-bit; as Map_BuiltRowYInc for Map_BuildRowYDec*
!Map_BuiltColXInc = $1D7A                ; 8-bit; as Map_BuiltRowYInc for Map_BuildColXInc*
!Map_BuiltColXDec = $1D7B                ; 8-bit; as Map_BuiltRowYInc for Map_BuildColXDec*
!Map_TilemapVram3 = $1D7E                ; 16-bit tilemap VRAM base the NMI uses for redraw step 2
                                         ; (Field_MapRedrawDone = 2)
!Map_TilemapVramL3 = $1D80               ; 16-bit tilemap VRAM base of layer 3 (Sub_C07F9A adds it
                                         ; as Map_TilemapVram for layer 1; $C0:0AD5 uploads the
                                         ; Field_BuildC800Mode4 buffer there)
!Map_TilemapVram4 = $1D84                ; 16-bit; its high byte is ORed into Hdma_Unk7F14F1 when
                                         ; hook 12 ends
!Map_TilemapVram4Hi = $1D85              ; high byte of Map_TilemapVram4 (LocLoad_DrawMap stores it
                                         ; alone, as Map_ScSizeInit)
!Map_Unk1D86 = $1D86                     ; 8-bit; 1 from $C0:0A8B (with $1D84 and $1D85);
                                         ; Field_BuildC800Mode4 stores 2 when it builds rows 32-63
                                         ; (probably layer 3's BGnSC size bits, 2 = 32x64, as the
                                         ; high byte of Map_TilemapVram4 is for layer 2)
!Map_Unk1D87 = $1D87                     ; 16-bit; layer 1 X scroll in pixels (probably): first of
                                         ; the six words $1D87-$1D91 that $C0:06F1 copies to
                                         ; $7E:2C5A; Map_Scroll1XInc/XDec step it by 1 per pixel of
                                         ; Map_Move1XPos/Neg. Map_Unk91AC holds a scroll-to on X while
                                         ; its bits 0-3 are nonzero
!Map_Unk1D89 = $1D89                     ; 16-bit; as Map_Unk1D87, layer 1 Y (Map_Scroll1Y*)
!Map_Unk1D8B = $1D8B                     ; 16-bit; as Map_Unk1D87, layer 2 X (Map_Scroll2X*; at
                                         ; half rate it moves every second step)
!Map_Unk1D8D = $1D8D                     ; 16-bit; as Map_Unk1D87, layer 2 Y (Map_Scroll2Y*; at
                                         ; half rate every second step); hooks 7-10 set it to $0100
!Map_Unk1D8F = $1D8F                     ; 16-bit; as Map_Unk1D87, layer 3 X (Map_Scroll3X*);
                                         ; hooks 7/8 set $F01D
!Map_Unk1D91 = $1D91                     ; 16-bit; as Map_Unk1D87, layer 3 Y (Map_Scroll3Y*);
                                         ; hooks 7/8 set $01C0
!Map_Unk1D93 = $1D93                     ; 8-bit; layer 1 X scroll within a 16-pixel cell (0-$0F):
                                         ; Map_Scroll1XInc/XDec step it with Map_Unk1D87 and move
                                         ; Map_TileOriginX/Map_Unk1D0C when it crosses 7/8 or
                                         ; $0F/0. Nonzero lets Field_Unk885A set Map_Unk1D2E; at the
                                         ; limit column Map_StepStopRight/Left keep the X step only
                                         ; while it plus / minus the step / 16 stays within 0-$F
!Map_Unk1D94 = $1D94                     ; 8-bit; as Map_Unk1D93 for layer 2 X (0-$0F; 0-$1F with
                                         ; the half-rate steppers)
!Map_Unk1D95 = $1D95                     ; 8-bit; as Map_Unk1D93 for layer 3 X
!Map_Unk1D96 = $1D96                     ; 8-bit; as Map_Unk1D93 for layer 1 Y (Map_Scroll1Y*,
                                         ; Map_TileOriginY/Map_Unk1D10); nonzero lets Field_Unk885A
                                         ; set Map_Unk1D30; Map_StepStopDown/Up as for X
!Map_Unk1D97 = $1D97                     ; 8-bit; as Map_Unk1D96 for layer 2 Y (0-$0F; 0-$1F with
                                         ; the half-rate steppers)
!Map_Unk1D98 = $1D98                     ; 8-bit; as Map_Unk1D96 for layer 3 Y
!Map_BgColBias2 = $1D9B                  ; 8-bit; as Map_BgColBias for layer 2: Map_EdgeColsX* step
                                         ; it (wrapping at 64) after a layer-2 column build
!Map_BgRowBias2 = $1D9C                  ; 8-bit; as Map_BgRowBias for layer 2 (wraps at 32;
                                         ; Map_EdgeRowsY*)
!Map_BgColBias3 = $1D9D                  ; 8-bit; as Map_BgColBias2 for layer 3
!Map_BgRowBias3 = $1D9E                  ; 8-bit; as Map_BgRowBias2 for layer 3
!Map_EdgeVram1 = $1D9F                   ; 10 words: tilemap VRAM word addresses Sub_C07F9A computes
                                         ; for layer 1 (Map_TilemapVram + the Bg_*Span64x32
                                         ; results): +0/+2/+4 the row at Map_BgRowBias from column
                                         ; Map_BgColBias - 1 (three pieces), +6/+8/+10 the row
                                         ; 28 further down (mod 32), +12/+14 the column Map_BgColBias from row
                                         ; Map_BgRowBias - 1, +16/+18 the column 32 to the right.
                                         ; Probably the NMI's edge DMA targets; reader not traced
!Map_EdgeVram2 = $1DB3                   ; 10 words; as Map_EdgeVram1 for layer 2
                                         ; (Map_BgColBias2/RowBias2, Map_TilemapVram3)
!Map_EdgeVram3 = $1DC7                   ; 10 words; as Map_EdgeVram1 for layer 3
                                         ; (Map_BgColBias3/RowBias3, Map_TilemapVramL3)
!Map_EdgeSize1 = $1DDB                   ; 5 words: byte counts Sub_C07F9A stores with
                                         ; Map_EdgeVram1: +0/+2/+4 the row's three pieces, +6/+8
                                         ; the column's two (Map_SpanLen1/2/3)
!Map_EdgeSize2 = $1DE5                   ; 5 words; as Map_EdgeSize1 for layer 2
!Map_EdgeSize3 = $1DEF                   ; 5 words; as Map_EdgeSize1 for layer 3
!Map_Unk1DFB = $1DFB                     ; 8-bit; Map_Scroll3YInc / YDec add / subtract 4 per pixel
                                         ; of layer-3 Y scroll; readers not traced
!Map_Unk1DFD = $1DFD                     ; 8-bit; $11 during hook 12, 0 after; no reader in bank $C0
!Map_HookTimer = $1DFF                   ; 8-bit frame countdown for hook 12's loops

; --- Location map setup (LocLoad_UnkA33B and its callees, Map_LoadTreasureTiles; DP=$1D00).
;     Scratch bytes of the page under other names at other times ---
!Map_LoadScratch = $1D50                 ; 8-bit scratch: LocLoad_UnkA33B keeps the MapProps byte
                                         ; it is splitting here; Map_LoadTreasureTiles stores a
                                         ; table offset that nothing reads
!Map_TreasureNum = $1D50                 ; alias of Map_LoadScratch: 16-bit treasure number in
                                         ; Map_TreasureTaken, then (8-bit) its BitSet flag bit
!Map_PropsPart = $1D52                   ; alias of Map_StepTestN: 8-bit scratch of
                                         ; LocLoad_UnkA33B (a byte or bit field being assembled)
!Map_OriginTest = $1D52                  ; alias of Map_StepTestN: 8-bit scratch of Map_InitOriginX/Y
                                         ; (limit + lead, compared with the entry column / row)
!Map_PlaneEnd = $1D52                    ; alias of Map_StepTestN, 16-bit: Map_UnpackTilePlanes:
                                         ; rows << 8, the index that ends a plane
!Map_RecOfs = $1D52                      ; alias of Map_StepTestN, 16-bit: Map_LoadExitTiles /
                                         ; Map_LoadTreasureTiles: the record being read
!Map_RowEnd = $1D54                      ; alias of Map_StepTestN2, 16-bit: Map_UnpackTilePlanes:
                                         ; row << 8 | width, the index that ends the row
!Map_RowEndRow = $1D55                   ; high byte of Map_RowEnd: the row being filled
!Map_RecNum = $1D54                      ; alias of Map_StepTestN2: 8-bit number of the record
                                         ; being read (Map_LoadExitTiles, Map_LoadTreasureTiles)
!Map_RecEnd = $1D56                      ; alias of Map_ProbeFracY4, 16-bit: the offset that ends
                                         ; the location's records
!Map_RunHiBits = $1D58                   ; alias of Map_ProbeHiBits: Map_UnpackTilePlanes: the
                                         ; Map_TileHiBits byte of a run being repeated
!Map_RunAttrA = $1D5A                    ; alias of Map_ProbeAttrA: as Map_RunHiBits for Map_TileAttrA
!Map_RunAttrB = $1D5C                    ; alias of Map_ProbeAttrB: as Map_RunHiBits for Map_TileAttrB
!Decomp_Src = $0300                      ; 16-bit source offset for Decomp_ToWramVec (bank $C3's
                                         ; unpacker; the battle side names it Battle_DecompSrc)
!Decomp_SrcBank = $0302                  ; 8-bit source bank
!Decomp_Dest = $0303                     ; 16-bit WRAM destination offset
!Decomp_DestBank = $0305                 ; 8-bit WRAM destination bank
!Decomp_OutLen = $0306                   ; 16-bit, read back after Decomp_ToWramVec: the unpacked
                                         ; length, or end offset (LocLoad_CheckEvtData limits it to
                                         ; Evt_DataMax; ram_battle.inc reads it as the end offset)
!Map_PropsPtrs = $F61E00                 ; 3 bytes per entry: long pointer to a location's packed
                                         ; MapProps; LocRom.MapProps picks the entry
!LocGfx_Lists = $F61C00                  ; 8 bytes per LocRom.Tileset12: graphics pack numbers ($FF =
                                         ; none); 0-5 are unpacked to LocGfx_Stage and uploaded to
                                         ; VRAM $2000-$4800 (LocLoad_Unk0960), 6 / 7 only unpacked to
                                         ; LocGfx_Unk7F6000 / LocGfx_Unk7F7000 (LocLoad_UnpackPacks67)
!LocGfx_PackPtrs = $F62220               ; 3 bytes per graphics pack: long pointer to its packed data
                                         ; (the pack numbers above, and LocRom.Tileset3)
!LocGfx_Meta12Ptrs = $F62100             ; 3 bytes per LocRom.Tileset12: long pointer to the packed
                                         ; Map_Meta12TL table (LocLoad_Unk09DD)
!LocGfx_Meta3Ptrs = $F621C0              ; 3 bytes per LocRom.Tileset3: long pointer to the packed
                                         ; Map_Meta3TL table (LocLoad_Unk0A14)
!LocPal_Rom = $F624C0                    ; LocPal_SetBytes per LocRom.Palette: colours 1-15 of seven
                                         ; palette rows (LocLoad_Unk7084)
!Evt_PackPtrs = $FCF9F0                  ; 3 bytes per entry: long pointer to a location's packed event
                                         ; data; LocRom.Events picks the entry (LocLoad_Unk56D4)
!ExitRom_LocOfs = $E50000                ; one word per location (Loc_Id & Loc_IdMask): ExitRom
                                         ; offset of its first record; the next word ends the list
                                         ; (Map_LoadExitTiles)
!TreasureRom_LocOfs = $F5F000            ; as ExitRom_LocOfs for TreasureRom records
                                         ; (Map_LoadTreasureTiles); the first word is also the
                                         ; base treasure numbers count from (Map_TreasureRec0)

; One location record in ROM bank $F6 (14 bytes; record Loc_Id at Loc_RecOfs). Only the
; fields the matched location-load steps read are named.
struct LocRom $F60000
    .Music: skip 1       ; probably the music track: LocLoad_AudioSetup sends it with sound
                         ; command Audio_CmdPlayMusic and keeps it in Menu_Config1E; bit 7
                         ; set = leave the music alone
    .Tileset12: skip 1   ; layers 1/2 graphics: LocGfx_Lists entry (LocLoad_Unk0960) and
                         ; LocGfx_Meta12Ptrs entry (LocLoad_Unk09DD); $FF = none (both skip).
                         ; "Tileset" rests on it choosing both the graphics and the metatiles
    .Tileset3: skip 1    ; layer 3: LocGfx_PackPtrs entry uploaded to VRAM LocGfx_VramL3
                         ; (LocLoad_Unk6DCF) and LocGfx_Meta3Ptrs entry (LocLoad_Unk0A14);
                         ; $FF = none (LocLoad_Unk6DCF then sets Field_UnkBB)
    .Palette: skip 1     ; LocPal_Rom entry copied to Pal_LocRows (LocLoad_Unk7084)
    .MapProps: skip 2    ; 16-bit entry number in Map_PropsPtrs (LocLoad_UnkA33B)
    .Unk06: skip 2
    .Events: skip 2      ; 16-bit entry number in Evt_PackPtrs: the location's event data
                         ; (LocLoad_Unk56D4)
    .LimitLeft: skip 1   ; Map_Unk1D1A (column); bit 7 set: no limits from the record, the
                         ; four are 0, Map_Unk0BCB - 1, 0, Map_Unk0BCD - 1 instead
    .LimitTop: skip 1    ; Map_Unk1D1C (row)
    .LimitRight: skip 1  ; Map_Unk1D1B (column)
    .LimitBottom: skip 1 ; Map_Unk1D1D (row). "Limit" rests on how Map_Unk9175 and the
                         ; Map_StepStop* tests use them and on the defaults (the map's edges)
endstruct

; A location's map properties, unpacked by LocLoad_UnkA33B into WRAM at $7E:B500 (the area
; LocLoad_Unk09DD later unpacks Map_Meta12TL into, so it only lives through the load).
struct MapProps $7EB500
    .Size1: skip 1       ; bits 0-1 -> Map_Unk0BCB, 2-3 -> Map_Unk0BCD (layer 1), 4-5 ->
                         ; Map_Unk0BCF, 6-7 -> Map_Unk0BD1 (layer 2): sizes $10-$40
    .Size3: skip 1       ; bits 0-1 -> Map_Unk0BD3, 2-3 -> Map_Unk0BD5 (layer 3); bit 4 / 5:
                         ; Map_OwnStep2 / Map_OwnStep3; bit 6: Map_Unk0BC9; bit 7: Map_Unk0BCA
    .Move2: skip 1       ; layer set 2's own step: bits 0-2 n: X step 1 << (n - 1) (0: none),
                         ; bit 3: negative; bits 4-6 / 7: the same for Y -> Map_OwnStep2X/Y
    .Move3: skip 1       ; as Move2 for set 3 (Map_OwnStep3X/Y)
    .Screens: skip 1     ; bits 0-2: BG1-3 and bit 3: OBJ on the main screen; bits 4-7 the
                         ; same for the sub screen (Ppu_Unk0BD7 / Ppu_Unk0BD8)
    .ColorMath: skip 1   ; Ppu_Unk0BDF and Ppu_Unk0BE0 (the CGADSUB value)
    .Planes: skip 1      ; start of the packed tile planes Map_UnpackTilePlanes reads
endstruct

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

; One exit record in ROM bank $E5 (7 bytes; Map_StepTileEffects reaches record n of the
; location at Map_ExitRec0 + n*7, n from Map_TileExitIdx). "Exit" rests on what the code does:
; it fills Loc_DestId/DestX/DestFacing and requests SceneFlag_Warp.
struct ExitRom $E50000
    .TileX: skip 1       ; map column the record belongs to
    .TileY: skip 1       ; map row
    .Span: skip 1        ; Map_LoadExitTiles: bits 0-6 = tiles after the first the record
                         ; also covers, bit 7 set = down the column, clear = along the row
                         ; (not read by Map_StepTileEffects)
    .DestLo: skip 1      ; Loc_DestId low byte
    .DestHiFacing: skip 1 ; bit 0: Loc_DestId bit 8; bits 1-4: facing; bit 7: Loc_DestFacing bit 7
    .DestX: skip 1       ; Loc_DestX (destination tile X)
    .DestY: skip 1       ; Loc_DestX+1 (destination tile Y)
endstruct

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

; The field/battle hand-off block in bank $7E. Field_Unk038F fills it before a battle
; (the battle engine reads it absolute, e.g. $CC:E936 / $CC:EA3B / $CD:0CA2), and
; FieldBtl_Restore puts the objects back from it afterwards. Tile positions are relative to
; FieldBtl_OriginX/Y (the screen origin / 2).

; One party member (3 records: leader, member 2, member 3).
struct FieldBtlPc $7E29B0
    .TileX: skip 1       ; Obj_TileX - origin
    .TileY: skip 1       ; Obj_TileY - origin
    .SubX: skip 1        ; low 4 bits of Obj_ScreenX (the pixel within the tile)
    .SubY: skip 1        ; low 4 bits of Obj_ScreenY
    .Frame: skip 1       ; Obj_LastFrame
endstruct

; One other object on screen (8 records, right after the 3 FieldBtlPc). The record number
; comes from the object's Obj_VramTile (FieldBtl_SaveObj).
struct FieldBtlObj $7E29BF
    .TileX: skip 1       ; as FieldBtlPc
    .TileY: skip 1
    .SubX: skip 1
    .SubY: skip 1
    .Frame: skip 1       ; Obj_LastFrame, 0 for size class 3
    .Unk05: skip 1       ; Obj_Unk1101; $FF (with .Unk06) = no object
    .Unk06: skip 1       ; 0
    .Flags: skip 1       ; Obj_SprSize & ObjSpr_SizeMask, | FieldBtl_ObjKind6Flag for
                         ; kind 6, | Obj_Unk1A81 bit 7. 0 after the battle: FieldBtl_RestoreObj
                         ; removes the object
    .Attr: skip 1        ; Obj_OamAttr >> 1
    .GfxOfs: skip 2      ; Obj_GfxOfs
    .GfxBank: skip 1     ; Obj_GfxBank
endstruct

; Screen settings saved by FieldBtl_SavePpu. The order follows PPU registers $2107-$210A,
; $210D-$2112 and $212C-$2133 (probably a register image; the reader is not traced).
struct FieldBtlPpu $7E2C56
    .Tilemap1: skip 1    ; Map_TilemapVram high byte | Map_TilemapVram4 (BG1SC-like)
    .Tilemap2: skip 1    ; Map_TilemapVram3 high byte | Map_TilemapVram4Hi
    .Tilemap3: skip 1    ; Map_TilemapVramL3 high byte | Map_Unk1D86
    .Unk59: skip 1       ; 0
    .Scroll: skip 12     ; Map_Unk1D87-Map_Unk1D91: X/Y of layers 1-3, 16-bit each
    .MainScreen: skip 1  ; Ppu_Unk0BD7 (TM value)
    .SubScreen: skip 1   ; Ppu_Unk0BD8 (TS value)
    .Unk68: skip 1       ; 0
    .Unk69: skip 1       ; 0
    .Unk6A: skip 1       ; FieldBtl_PpuUnk6A
    .ColorMath: skip 1   ; Ppu_Unk0BDF (CGADSUB value)
    .FixedColor: skip 1  ; Fade_FixedColor
    .Unk6D: skip 1       ; 0
    .Unk6E: skip 1       ; FieldBtl_PpuUnk6E
    .Unk6F: skip 1       ; 0
    .Scroll2: skip 12    ; the same six words again
endstruct

endif
