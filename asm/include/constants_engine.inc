; ============================================================
; constants_engine.inc — Named constants for the engine core (banks $00, $C0, $FD).
; Same conventions as constants.inc: !Subsystem_Thing, grouped, each
; with a one-line note on what it means and how that was inferred.
; ============================================================
!constants_engine_inc ?= 0
if !constants_engine_inc == 0
!constants_engine_inc = 1

; --- Crash trap ---
!CrashMarkerRead = $ABCDEF               ; read forever by BRK_Handler; a ROM address (HiROM mirror of
                             ; file offset $2BCDEF), value discarded. Inferred: chosen to be
                             ; recognizable on a bus trace, not to fetch data.

; --- Addressing ---
!BankWrap = $10000                       ; one bank: a BRL whose 16-bit offset wraps around the bank
                     ; boundary is written `BRL Target-!BankWrap` so asar computes
                     ; the same (in-range, wrapped) offset the ROM has

; ==== Field direct page and bank $C0 constants ====


; --- Banks and direct-page bases ---
!Bank7E = $7E                            ; WRAM bank $7E (PHA/PLB, DmaFill_Bank)
!Bank00 = $00                            ; bank $00 (MVN bank operand for the low-WRAM mirror)
!BankE4 = $E4                            ; ROM bank $E4 (bank byte of the Field_E4Ptr pointers)
!DP_Map = $1D00                          ; direct page of the map/BG routines (Field_BuildC800*,
                                         ; Field_FrameUpdate)
!DP_SprBufPage = $0B00                   ; direct page SprBuf_FreeAll points at to reach SprBuf_Owner
                                         ; with dp stores
!DP_VramQ = $0900                        ; direct page VramQ_Flush points at to reach the VramQ_* queue
                                         ; ($0940-$09AF) with dp loads
!BankD2 = $D2                            ; ROM bank $D2 (object tile graphics)
!Bank7F = $7F                            ; WRAM bank $7F (PHA/PLB, DmaFill_Bank, Obj_GfxBank for
                                         ; graphics already in WRAM)

; --- Boot WRAM clear (GameLoop) ---
!Boot_ClearLowSize = $0500               ; bytes cleared from $7E:0000 (stops before the interrupt
                                         ; trampolines at $0500)
!Boot_ClearMainStart = $0700             ; first address of the second cleared block (after the stack
                                         ; page)
!Boot_ClearMainSize = $E900              ; bytes cleared from $7E:0700 to the end of bank $7E
!Boot_Clear7FStart = $5080               ; first address of the cleared bank-$7F block; also its byte
                                         ; count
!BankC2_BootArg = $09                    ; A for the BankC2_Entry8004 call in GameLoop (boot, and again on the $C0:02CA re-entry)

; --- Locations ---
!Loc_FirstBankC2 = $01F0                 ; GameLoop_Main CPX limit: Loc_Id $01F0-$81EF goes to BankC2_Entry0000
                                         ; (GameLoop_Main)
!Loc_HaltLimit = $01FF                   ; GameLoop_NotBankC2's CPX limit: Loc_Id $81F0-$81FE reach Sys_HaltWithColor
                                         ; (GameLoop_Main)
!Halt_ColorBadLoc = $7C00                ; Sys_HaltWithColor colour (BGR555 blue) for Loc_Id $81F0-$81FE

; --- Field save block ---
!Field_SaveBlockSize = $14E0             ; bytes in Field_SaveBlock (Field_RestoreSaveBlock /
                                         ; Field_StashSaveBlock MVN count + 1)

; --- Interrupt trampolines ---
!Op_JML = $5C                            ; 65816 opcode JML long (written into the RAM trampolines)
!Op_RTI = $40                            ; 65816 opcode RTI (Sys_HaltWithColor's trampolines)

; --- OAM shadow ranges (Oam_BuildShadow, Field_InitLoadState, Field_RestoreState) ---
!Oam_Range1Start = $0770                 ; low-table address where range 1 starts each frame (entry
                                         ; 28)
!Oam_Range1Limit = $08A0                 ; low-table address range 1 may not reach (entry 104)
!Oam_Range2Start = $08A0                 ; low-table address where range 2 starts (entry 104)
!Oam_Range2Limit = $0900                 ; end of the low table (range 2 limit)
!Oam_Range3Start = $0710                 ; low-table address where range 3 starts (entry 4)
!Oam_Range3Limit = $0770                 ; low-table address range 3 may not reach (=
                                         ; Oam_Range1Start)
!Oam_Range1HiStart = $0907               ; high-table byte for entries 28-31 (range 1 start)
!Oam_Range2HiStart = $091A               ; high-table byte for entries 104-107 (range 2 start)
!Oam_Range3HiStart = $0901               ; high-table byte for entries 4-7 (range 3 start)
!Obj_DrawBucketLast = $007E              ; offset of the last Obj_DrawBucket word (64 buckets x 2)

; --- Object / party slots ---
!Obj_None = $80                          ; empty object-slot marker (bit 7 set) in Party_ObjSlot,
                                         ; Chr_ObjSlot and similar
!Obj_Unk1C00Init = $07                   ; value Evt_RunObjInit stores in Obj_Unk1C00 after the init
                                         ; function
!Obj_Unk1C00Min = $02                    ; Evt_StartTargetFunc1 does nothing while Obj_Unk1C00 is
                                         ; below this
!Obj_Unk1C00Func1 = $01                  ; Obj_Unk1C00 set by Evt_StartTargetFunc1 as it starts
                                         ; function 1
!Evt_PrioStride = $80                    ; bytes from one ObjX_Unk7F0580 level table to the next
                                         ; (the multiplier of Obj_Unk1C00)
!Evt_Func1Ofs = $0002                    ; offset of function 1 in an object's 16-word function table
!ObjQ_Empty = $80                        ; ObjQ_Head/ObjQ_Tail/Obj_QueueNext value for "none"

; --- Field defaults (Field_InitLoadState) ---
!Fade_FixedColorInit = $E0               ; Fade_FixedColor at load: all colour channels, intensity 0
!Field_HdmaEnableInit = $5F              ; Field_HdmaEnable at load: HDMA channels 0-4 and 6
!Field_Unk63Idle = $80                   ; Field_Unk63 at load (negative = Sub_1ADF leaves it alone)
!Field_UnkEBInit = $80                   ; Field_UnkEB at load
!Audio_SfxDefaultA = $53                 ; Audio_SfxTileAnimA at load
!Audio_SfxDefaultB = $65                 ; Audio_SfxTileAnimB at load
!Audio_SfxDefaultFA = $45                ; Audio_SfxUnkFA at load

; --- Scene flags and fades ---
!SceneFlag_Reload = $40                  ; Field_SceneFlags bit 6: fade out then reload the location
!SceneFlag_TileAnim = $10                ; Field_SceneFlags bit 4: run a tile-animation mode handler
!FadeFlag_Brightness = $02               ; Field_FadeFlags bit 1: brightness fade running
!FadeFlag_FixedColor = $08               ; Field_FadeFlags bit 3: fixed-colour fade running
!FadeFlag_Reloaded = $40                 ; Field_FadeFlags bit 6: set after a reload
!Fade_BrightnessMax = $0F                ; full screen brightness (INIDISP bits 0-3)
!Field_FadeBusyOn = $FF                  ; Field_FadeBusy while a pause/fade loop runs
!Field_ExitArgXMask = $003F              ; Field_BankC2Arg bits 5-0 (handed over in X)
!Eng_Unk7F0000Min = $49                  ; Field_FadeToBankC2Mode5 runs only when Eng_Unk7F0000 >=
                                         ; this
!ExitMenu_Mode5 = $05                    ; BankC2_Entry8000 argument used by Field_RunBankC2Mode5
!ExitMenu_Mode6 = $06                    ; BankC2_Entry8000 argument when Field_BankC2Arg bit 0 is
                                         ; clear
!SceneFlag_Battle = $01                  ; Field_SceneFlags bit 0: start a battle (DefaultHandler
                                         ; JSLs EngCall_BattleMain)
!SceneFlag_TileStep = $02                ; Field_SceneFlags bit 1: step one tile (DefaultHandler)
!SceneFlag_MapRedraw = $20               ; Field_SceneFlags bit 5: redraw map layers per
                                         ; Field_MapRedrawSel (DefaultHandler)
!FadeFlag_AfterBattle = $01              ; Field_FadeFlags bit 0: set when DefaultHandler finishes
                                         ; the battle path
!VramQueue_TileStep = $02                ; Field_VramQueueFlags bit 1: TileAnim_StepVramAddrs ready
!VramQueue_TileAnim = $10                ; Field_VramQueueFlags bit 4: TileAnim_VramAddrs ready
!Field_Unk53Bit7 = $80                   ; Field_Unk53 bit 7, set around one Field_EndOfFrameShort
                                         ; before the battle (DefaultHandler)

; --- Pad ---
!Pad_Start = $01                         ; Pad_Pressed bit 0: Start
!Pad_HiDown = $04                        ; high byte of Pad_Pressed, bit 2: Down
!Pad_HiUp = $08                          ; high byte of Pad_Pressed, bit 3: Up
!Pad_DpadMask = $0F                      ; bits 0-3 of Pad_Unk00F9: Field_DpadDispatch's table index
!Pad_Unk00F8Bit1 = $02                   ; Pad_Unk00F8 bit 1: the Field_Dpad* handlers step $20
                                         ; instead of $10 (a run button? Select in the Pad_Pressed
                                         ; low-byte layout, so the layout may differ)
!Pad_Unk00F8Bit7 = $80                   ; Pad_Unk00F8 bit 7 (Sub_1ADF sets Field_Unk62 = 3 on it)
!Pad_Unk00F6Mode5 = $01                  ; Pad_Unk00F6 bit 0: run Field_FadeToBankC2Mode5
                                         ; (Field_PauseAndMenuInput)
!Pad_Unk00F6Menu = $40                   ; Pad_Unk00F6 bit 6: fade out and call BankC2_Entry8000 with
                                         ; 1 (Field_PauseAndMenuInput); X in the Pad_Pressed layout
!Pad_Unk00F6Bit7 = $80                   ; Pad_Unk00F6 bit 7: Field_ActionButton acts on it; Sub_1ADF
                                         ; clears Field_Unk34 on it (A in
                                         ; the Pad_Pressed layout)
!Field_Unk34Swallow = $FFFF              ; Field_Unk34 value that makes Field_ActionButton ignore
                                         ; one press (it then resets Field_Unk34 to 0)

; --- Audio ---
!Audio_CmdPlaySfx = $19                  ; Audio_CmdId: play the sound effect in Audio_CmdArg0

; --- Generic ---
!Eng_LowByteMask = $00FF                 ; AND mask that zero-extends a byte in 16-bit A
!Eng_SignExtNeg = $FF                    ; high byte that sign-extends a negative 8-bit value
!Eng_HighByteMask = $FF00                ; AND mask keeping the high byte of 16-bit A
!Eng_Invert16 = $FFFF                    ; EOR mask; with INC A negates a 16-bit value (without the
                                         ; INC: ones' complement, an absolute value one short)

; --- Sine table (Trig_Cos1024 / Trig_Sin1024) ---
!Trig_QuarterTurn = $0100                ; 90 degrees at 1024 steps per turn (cosine = sine + this)
!Trig_IndexMask = $03FF                  ; angle wrapped to the 1024-entry (1 B each) sine table
!Trig_HalfTable = $0200                  ; table offset of 180 degrees: from here the sine is negative

; --- Tile animation modes (Field_SceneChangeTick dispatch on Map_TileProps) ---
!TileAnim_ModeE6 = $E6                   ; mode handled by ModeE6_Handler
!TileAnim_ModeEC = $EC                   ; mode handled by ModeEC_Handler
!TileAnim_ModeEE = $EE                   ; mode handled by ModeEE_Handler
!TileAnim_ModeFA = $FA                   ; mode handled by ModeFA_Handler
!TileAnim_ModeFC = $FC                   ; mode handled by ModeFC_Handler
!TileAnim_StateFE = $FE                  ; Map_TileProps value DefaultHandler steps to $FF
                                         ; (TileAnim_StepKind 0)
!TileAnim_StateE0 = $E0                  ; Map_TileProps value DefaultHandler steps to $E1
                                         ; (TileAnim_StepKind 1)

; --- Map / BG ---
!Map_RowStride = $0100                   ; Map_TileProps bytes per map row (index - $100 = the tile
                                         ; above)
!Bg_ColMask64 = $003F                    ; wraps an 8x8 tile column into a 64-wide tilemap
!Bg_RowMask32 = $001F                    ; wraps an 8x8 tile row into a 32-tall tilemap
!Bg_ScreenWidth = $0020                  ; tiles per row of one 32x32 tilemap screen
!Bg_ScreenWords = $0400                  ; words in one 32x32 tilemap screen (offset of the right-
                                         ; hand screen)

; --- Sprite build ---
!ObjState_Ready = $80                    ; Obj_State value once the object's SprTile records are
                                         ; built
!ObjState_CountMask = $7F                ; Obj_State bits 0-6 (a count compared against 2 or 3 by
                                         ; Spr_PrepareTiles)
!ObjSpr_SizeMask = $03                   ; Obj_SprSize bits 0-1: size class
!ObjOam_RangeMask = $0C                  ; Obj_OamFlags bits 2-3: OAM shadow range
!ObjOam_Range2 = $04                     ; Obj_OamFlags bit 2: range 2 (bit 3 alone = range 3)
!SprTile_Stride = $0008                  ; bytes per SprTile / SprTileSrc record
!Spr_Size0Tiles = $04                    ; tiles in a size-0 object
!Spr_Size1Tiles = $08                    ; tiles in a size-1 object
!Spr_Size2Tiles = $0C                    ; tiles in a size-2 object
!Spr_Size3Tiles = $18                    ; tiles in a size-3 object
!Oam_EntrySize = $04                     ; bytes per OAM low-table entry
!Spr_YMask9 = $01FF                      ; low 9 bits of Obj_ScreenY
!Oam_HiLarge4 = $AA                      ; OAM high-table byte with the size bit set for all 4
                                         ; sprites
!Oam_HiddenY = $E0                       ; sprite Y that parks an entry below the visible screen
                                         ; (also the Y clamp limit)

; --- Object graphics ---
!SprBuf_Tiles = $0060                    ; tiles in the WRAM tile buffer (96 x 32 bytes = $0C00)
!SprBuf_Bytes = $0C00                    ; bytes in the WRAM tile buffer
!SprBuf_VramWord = $0400                 ; VRAM word address the tile buffer is uploaded to
!Gfx_Tile4bppBytes = $0020               ; bytes in one 8x8 4bpp tile
!SprFrame_TileMask = $07FF               ; tile number bits of a frame-data tile word
!SprFrame_HFlip = $4000                  ; frame-data tile word bit 14: copy the tile mirrored
                                         ; (Spr_CopyTileFlipped)
!LargeObj_LayoutOfs = $00C0              ; offset of the 24 position byte pairs in a large object's
                                         ; frame data (after 96 tile words)
!LargeObj_TileRow0 = $40                 ; OAM tile number of the first 16x16 tile in row 0 of a
                                         ; large object (tiles step by 2)
!LargeObj_TileRow1 = $60                 ; OAM tile number of the first 16x16 tile in row 1
!LargeObj_TileRow2 = $80                 ; OAM tile number of the first 16x16 tile in row 2
!LargeObj_Attr = $22                     ; OAM attributes of every large-object tile: priority 2,
                                         ; palette 1

; --- Object frame build ---
!Obj_VramTileMask = $01FF                ; tile-number bits of Obj_VramTile
!ObjTile_AltLayout = $68                 ; Obj_VramTile value that selects the alternate VRAM layout
                                         ; in the 12-tile builders: tile $68 is column 8 of a
                                         ; 16-tile VRAM row, so its first row of 16x16 tiles holds
                                         ; only 4, giving rows of 4 then 8 instead of 8 then 4
!Frame4_Bytes = $28                      ; bytes per frame record of a 4-tile object: 16 tile words +
                                         ; 4 position pairs
!Frame8_Bytes = $50                      ; bytes per frame record of an 8-tile object: 32 tile words
                                         ; + 8 position pairs
!Frame12_Bytes = $78                     ; bytes per frame record of a 12-tile object: 48 tile words
                                         ; + 12 position pairs
!Spr_UpperOfsY = $E8                     ; 4-tile builders: tiles with OfsY >= this (unsigned; as a
                                         ; signed byte -24..-1, the 24 lines just above the
                                         ; origin) take Obj_PrioHigh. Whether that is the upper or
                                         ; lower part of the sprite depends on where the origin
                                         ; is, which is not established
!Anim_EndMarker = $FF                    ; frame-number table entry that ends an animation row
!Vram_TileRowWords = $0100               ; VRAM words in one row of sixteen 8x8 tiles (the next row
                                         ; holds the lower halves of 16x16 sprites)
!Gfx_8TilesBytes = $0100                 ; bytes in eight 4bpp 8x8 tiles
!SprBuf_ChunkTiles = $0010               ; tiles in one $200-byte SprBuf chunk
!SprBuf_HalfChunkTiles = $0008           ; tiles in half a SprBuf chunk ($100 bytes): one copy run of
                                         ; the 12-tile builders
!Frame_TileWordBytes = $02               ; bytes per tile word in a frame record (offsets are written
                                         ; as this x tile index)
!Spr_TileRowStep = $10                   ; OAM tile-number step to the next row of 16 tiles
!Ppu_FirstHiddenLine = $00F0             ; V counter of the first line below the visible screen (240)

; --- Field_Unk885A ---
!Screen_HalfX = $80                      ; leader Obj_ScreenX low byte at or past this: right half
!Screen_SplitY = $88                     ; leader Obj_ScreenY low byte at or past this: lower part
!Map_StepPos = $10                       ; Map_Unk1D2E/1D30 value towards the right / bottom; also
                                         ; the walking D-pad step (Field_Dpad*)
!Map_StepNeg = $F0                       ; Map_Unk1D2E/1D30 value towards the left / top (-$10)
!Map_FineLimit = $10                     ; Map_Unk1D93/1D96 plus the step / 16 reaching this stops a
                                         ; right / down step at the limit tile (Map_StepStop*)
!Eng_Invert8 = $FF                       ; EOR mask: with INC A negates an 8-bit value
!Map_RunStepPos = $20                    ; D-pad step right / down with Pad_Unk00F8 bit 1 held
!Map_RunStepNeg = $E0                    ; D-pad step left / up with Pad_Unk00F8 bit 1 held (-$20)

; --- Map_Unk91AC / Map_Unk93E1 (layer scroll) ---
!Map_SubMask = $0F                       ; Map_Acc* bits 0-3: the remainder Map_Unk91AC keeps
!Map_SubSignExt = $F0                    ; ORed onto a negative Map_Acc* remainder (keeps it negative)
!Map_TilePixelMask = $0F                 ; Map_Unk1D87/1D89 bits 0-3 (pixel within a 16-pixel cell)
!ScrollTo_XDone = $01                    ; Map_ScrollToDone bit 0: X has arrived
!ScrollTo_YDone = $02                    ; Map_ScrollToDone bit 1: Y has arrived
!ScrollTo_BothDone = $03                 ; Map_ScrollToDone when both have arrived
!ScrollTo_Arrived = $02                  ; Map_ScrollToMode value once both have arrived
!Eng0400_Negative = $01                  ; Eng_Unk0400 bit 0: shake amounts negative
!Eng0400_ShakeY = $02                    ; Eng_Unk0400 bit 1: Y shake ($02 << 3 = $10)
!Eng0400_ShakeX = $04                    ; Eng_Unk0400 bit 2: X shake ($04 << 2 = $10)
!Map_OwnStep2 = $02                      ; Map_OwnStepFlags bit 1: set 2 without camera step / shake
!Map_OwnStep3 = $04                      ; Map_OwnStepFlags bit 2: set 3 without camera step / shake
!Map_Layer1 = $01                        ; Map_Edge* bit of layer 1
!Map_Layer2 = $02                        ; Map_Edge* / Map_LayerEdgeOff bit of layer 2
!Map_Layer3 = $04                        ; Map_Edge* / Map_LayerEdgeOff bit of layer 3
!Map_FineLast = $0F                      ; last value of a 16-pixel fine counter (Map_Unk1D93-1D98);
                                         ; also the half-way point of a half-rate (32-step) counter
!Map_FineMid = $07                       ; fine value below the 8-pixel boundary inside a cell
!Map_FineMidUp = $08                     ; fine value above it
!Map_FineWrapUp = $10                    ; one past Map_FineLast: DEC A then gives $0F
!Map_FineWrapDown = $FF                  ; -1: INC A then gives 0 (a fine counter wrapping upwards)
!Map_FineLastHalf = $1F                  ; last value of a half-rate fine counter (Map_Unk1D94/1D97)
!Map_BufColOfs = $0080                   ; column data starts this far into a layer's edge buffer
                                         ; (Map_BufC800/D000/D800); the row data at the start
!Map_EdgeRowLen = $12                    ; Map_BuildLen of a row builder (18 entries)
!Map_EdgeColLen = $0F                    ; Map_BuildLen of a column builder (15 entries)
!Map_FineWrapUpHalf = $20                ; one past Map_FineLastHalf: DEC A then gives $1F
!Map_HalfTileBit = $01                   ; bit 0 of Map_BuildRow / Map_BuildCol: the bottom / right
                                         ; 8x8 half of a 16x16 metatile
!Map_RedrawRows = $20                    ; 8x8 rows Field_BuildC800Mode1/2/4 write from the origin
!Map_RedrawLen = $10                     ; Map_BuildLen of a redraw row (16 metatiles, 32 words)
!Map_RedrawLastRow = $1F                 ; last 8x8 row of one 32x32 screen (redraw loops)
!Map_RedrawLastRow2 = $3F                ; last 8x8 row of a 32x64 build (rows 32-63)
!Map_ScreenMetatiles = $10               ; metatiles across one 32x32 screen (Map_Unk0BCF-0BD5
                                         ; compared with it)
!Bg_ScreenHeight = $20                   ; 8x8 rows in one 32x32 tilemap screen
!Bg_MapWidth64 = $0040                   ; 8x8 columns across a 64x32 tilemap (two screens)
!Map_EdgeRowTiles = $0022                ; 8x8 tiles in the edge row Bg_RowSpan64x32 splits (34)
!Map_RowsUp4 = $001C                     ; added to a tilemap row and masked to 32: 4 rows up
!Map_PageBytes = $0100                   ; bytes in the $1D00 page LocLoad_ClearPage1D00 clears
!Map_UploadVramA = $7400                 ; VRAM word address Map_UploadBufTo7400 uses
!Map_UploadVramB = $7000                 ; VRAM word address Map_UploadBufTo7000 uses
!Map_UploadSmall = $0800                 ; bytes of Map_BufC800 Map_UploadBuf2K sends (2 KB)
!Map_UploadLarge = $1000                 ; bytes Map_UploadBuf4K sends (4 KB: into Map_BufD000's space)

; --- Window effects (Field_EventHook handlers) ---
!EventHook_WinFixedA1 = $07              ; Field_EventHook value of Field_HookWinFixedA's first frame
                                         ; (it moves on to 8 for a second frame)
!EventHook_WinFixedB1 = $09              ; first-frame value of Field_HookWinFixedB (then 10)
!EventHook_Idle = $0D                    ; Field_EventHook value whose table entry is a bare RTS
                                         ; (hook 12 leaves it set)
!WinFx_TableA = $17C8                    ; bank-$7F address BankC3_Entry0008/0011 write to while
                                         ; Field_Unk53 is nonzero
!WinFx_TableB = $1AC8                    ; the same while Field_Unk53 is 0 (inferred: the two halves
                                         ; of a double buffer, as Hdma_InitChannelsFD picks its
                                         ; tables by Field_Unk53)
!WinFx_Mode0 = $00                       ; A for BankC3_Entry0008 from hooks 1-2 and 7-10 (what the
                                         ; mode selects is not traced)
!WinFx_Mode1 = $01                       ; A for BankC3_Entry0008 from hooks 4-5
!WinFx_Mode80 = $80                      ; A for BankC3_Entry0008 from hook 12
!WinFx_Hook3SizeMin = $02                ; hook 3 shuts the window off only when WinFx_Size < this
!WinFx_FixedX = $7C                      ; WinFx_ArgX of hooks 7-10
!WinFx_FixedY = $06                      ; WinFx_ArgY of hooks 7-10
!WinFx_FixedSizeA = $29                  ; WinFx_ArgSize of hooks 7/8
!WinFx_FixedSizeB = $27                  ; WinFx_ArgSize of hooks 9/10
!Map_Unk1D8DFixed = $0100                ; Map_Unk1D8D set by hooks 7-10
!Map_Unk1D8FFixed = $F01D                ; Map_Unk1D8F set by hooks 7/8
!Map_Unk1D91Fixed = $01C0                ; Map_Unk1D91 set by hooks 7/8
!Ppu_Unk0BDFHook9 = $04                  ; Ppu_Unk0BDF and Ppu_Unk0BE0 in hooks 9/10 (BG3 bit, if
                                         ; Ppu_Unk0BDF is CGADSUB)
!WinFx_Hook12X = $78                     ; WinFx_ArgX of hook 12
!WinFx_Hook12Y = $20                     ; WinFx_ArgY of hook 12
!WinFx_Hook12Size = $01                  ; WinFx_Size at the start of hook 12's growth
!Hook12_WaitFrames = $20                 ; frames hook 12 waits after the map redraw
!Hook12_RampFrames = $14                 ; frames of growth (WinFx_Size += 2) and of shrinking
!Hook12_HoldFrames = $20                 ; frames hook 12 holds the full size
!BankC3_HookArg = $85                    ; A for BankC3_Entry0000 from hook 11; bit 7 makes it set
                                         ; INIDISP to $0F, HDMAEN to 0 and an IRQ timer ($C3:0035)
!Field_Unk0FHook11 = $80                 ; Field_Unk0F set by hook 11 before it leaves for bank $C3

; --- Field_ServiceUnk54 (Field_Unk54 bits, staff credits) ---
!Field54_AnyWork = $1C                   ; Field_Unk54 bits 2-4: map request or credits line
!Field54_WatchBox = $20                  ; Field_Unk54 bit 5: check Field_TileStepX/Y against the box
!Field54_Credits = $10                   ; Field_Unk54 bit 4: write the next credits line
!Field54_MapReq = $0C                    ; Field_Unk54 bits 2-3: shifted left once into
                                         ; Field_MapRedrawDone bits 3-4, then Map_ClearBufC800
!Field_Unk29Start = $01                  ; Field_Unk29 value Field_CheckTileInFront sets to start
                                         ; Field_Unk1F87's sequence (not traced)
!Field_Unk29State0D = $0D                ; Field_Unk29 value set when the watched tile leaves the box
                                         ; (Field_Unk1F87's state $0D; not traced)
!MapRedraw_CreditsLine = $20             ; Field_MapRedrawDone bit 5: the NMI uploads the credits line
                                         ; (routine at $C0:EC77) and clears it
!Map_ZeroChunk = $0020                   ; bytes of zeros Map_ClearBufC800 takes from GfxRom_D2; its
                                         ; later MVNs copy 1, 2, 4 ... 32 times this
!Credits_ClearCount = $001F              ; MVN count - 1: 32 bytes of zeros from GfxRom_D2
!Credits_EndBlock = $80                  ; Credits_Text bytes >= this end a block (BMI)
!Credits_EndLine = $2F                   ; '/': ends a line
!Credits_Period = $2E                    ; '.'
!Credits_Space = $20                     ; ' '
!Credits_TileSpace = $00                 ; tile for a space
!Credits_TilePeriod = $1B                ; tile for '.'
!Credits_LetterBias = $40                ; subtracted from a letter: 'A' ($41) -> tile 1
!Credits_TileAttr = $2C                  ; tilemap high byte of every credits tile: priority 1,
                                         ; palette 3
!Credits_ColMask = $001F                 ; Credits_Column bits 0-4: first column
!Credits_RowMask = $003F                 ; Credits_Row bits 0-5: tilemap row
!Credits_TilemapVram = $7000             ; VRAM word address of the credits tilemap (row 0, column 0)
!Credits_LineBytes = $0040               ; bytes in a full tilemap row (32 words)

; --- Field_FindObjInFront / Field_CheckTileInFront ---
!Obj_FacingX2Mask = $0006                ; Obj_Facing x 2 kept to facings 0-3: offset into the
                                         ; per-facing handler tables
!Obj_Unk1100Seven = $07                  ; Obj_Unk1100 value that lets Field_FindObjInFront test the
                                         ; leader's own slot too (meaning unknown)
!Field_ReachAhead = $01C0                ; Obj_PosX/Y units (1/256 tile): how far ahead of the leader
                                         ; an object may be (1.75 tiles)
!Field_ReachSide = $00C0                 ; how far to the side of the facing line (0.75 tile)
!Map_TreasureIdxMask = $007F             ; Map_TreasureIdx bits 0-6 (16-bit AND also drops the row
                                         ; byte left in B)
!Treasure_FlagByteMask = $003F           ; treasure number >> 3 kept to the 64 Treasure_Flags bytes
!Treasure_FlagBitMask = $07              ; treasure number bits 0-2: bit within the flag byte
!Treasure_Empty = $4000                  ; TreasureRom.Contents bit 14 (with bit 15 clear): nothing
                                         ; given and no message started
!Treasure_ItemMask = $01FF               ; TreasureRom.Contents bits 0-8: item id
!BankC1Svc_AddItem = $01                 ; BankC1_Entry8003 service: add one of item Y to the
                                         ; inventory ($C1:D005)
!BankC1Svc_AddGold = $04                 ; BankC1_Entry8003 service: add Y to the gold sum
                                         ; ($C1:D0A2)
!TreasureKind_Item = $00                 ; Field_Unk2A: an item was taken
!TreasureKind_Gold = $01                 ; Field_Unk2A: gold was taken
!TreasureKind_Opened = $02               ; Field_Unk2A: the treasure was already taken

endif
