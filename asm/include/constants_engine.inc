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
!BankF6 = $F6                            ; ROM bank $F6 (location tables; MVN source bank)
!BankC0 = $C0                            ; ROM bank $C0 (this bank; MVN source bank)
!BankFF = $FF                            ; ROM bank $FF (MVN source bank of Pal_LoadUnkRow0)
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
!Audio_CmdPlayMusic = $10                ; Audio_CmdId LocLoad_AudioSetup sends with LocRom.Music in
                                         ; Audio_CmdArg0 (probably: start that music track)
!Audio_CmdUnk81 = $81                    ; Audio_CmdId LocLoad_AudioSetup sends first, with
                                         ; arguments 0, Audio_Cmd81Arg, Audio_Cmd81Arg (not traced)
!Audio_Cmd81Arg = $FF                    ; Audio_CmdArg1/Arg2 for Audio_CmdUnk81

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
!MapRedraw_Step1 = $01                   ; Field_MapRedrawDone values 1-4 (DefaultHandler's redraw
!MapRedraw_Step2 = $02                   ; steps): NmiHandler uploads Map_BufC800 (2 KB) to
!MapRedraw_Step3 = $03                   ; Map_TilemapVram, Map_TilemapVram3, Map_TilemapVram2 and
!MapRedraw_Step4 = $04                   ; Map_TilemapVramL3 for them, then zeroes it
!MapRedraw_UploadTo7000 = $08            ; Field_MapRedrawDone bit 3 (Field54_MapReq): the NMI uploads
                                         ; Map_BufC800 to VRAM $7000 (Map_UploadBufTo7000)
!MapRedraw_UploadTo7400 = $10            ; bit 4: the same to VRAM $7400 (Map_UploadBufTo7400)
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

; --- Map_Unk8A6D and its probes (leader collision) ---
!Map_BoxHalfW = $0070                    ; Obj_PosX units: from the leader's X to the left / right
                                         ; edge of the box Map_Unk8A6D tests (7 pixels)
!Map_BoxHeight = $0070                   ; from the leader's Y up to the top edge of that box
!Map_BoxMidY = $0040                     ; from the leader's Y up to the point a sideways step
                                         ; tests for objects
!Map_StepNeg16 = $FFF0                   ; Map_StepNeg as a 16-bit value (a slide of -$10)
!Map_StepHiNeg = $FF                     ; Map_Unk1D2EHi / 1D30Hi for a negative step
!Map_StepSign16 = $0080                  ; bit 7 of Map_Unk1D30 tested with a 16-bit BIT
!Map_ObjNear = $00E0                     ; an object closer than this in both X and Y to the probe
                                         ; is touched (Map_ProbeHitsObj; 14 pixels)
!Obj_Unk1B01Solid = $01                  ; Obj_Unk1B01 bit 0: a touched object blocks (C=1)
!Map_ShapeMask = $FC                     ; Map_TileHiBits bits 2-7: the tile's shape number
!Map_ShapeTables = $16                   ; shapes 2-$17 (Map_ProbeShape below this) use the line
                                         ; tables Map_SlopeShift/Base/Side
!Map_SlopeShiftMask = $7F                ; Map_SlopeShift bits 0-6: the shift count (bit 7: invert)
!MapShape_LeftB = $16                    ; Map_ProbeShape values (shape - 2) of the split shapes:
                                         ; half B is the left half
!MapShape_TopB = $17                     ; half B is the top half
!MapShape_BottomLeftB = $18              ; half B is the bottom-left quarter
!MapShape_BottomRightB = $19             ; half B is the bottom-right quarter
!MapShape_TopRightB = $1A                ; half B is the top-right quarter
!MapShape_TopLeftB = $1B                 ; half B is the top-left quarter
!MapShape_Unk1E = $1C                    ; shape $1E: half A, Map_ProbeShape1E, and a nonzero Y step
                                         ; cut to Map_StepPos / Map_StepNeg
!Map_ProbeShape1E = $04                  ; Map_ProbeMoveFlags bit 2: the tile has shape $1E
!Map_ProbePushing = $08                  ; Map_ProbeMoveFlags bit 3: the tile pushes
!TileAttrB_LevelA = $03                  ; Map_TileAttrB bits 0-1: half A's level
!TileAttrB_NoLevelA = $04                ; Map_TileAttrB bit 2: half A's "no level" bit
!TileAttrB_LevelB = $18                  ; Map_TileAttrB bits 3-4: half B's level
!TileAttrB_NoLevelB = $20                ; Map_TileAttrB bit 5: half B's "no level" bit
!TileAttr_PrioBit = $10                  ; Map_TileAttrA/B bit 6 after two LSRs: OAM priority bit 0
!Oam_Prio2 = $20                         ; OAM attribute bits 4-5 = 2 (priority 2)
!Map_LevelAny = $03                      ; Map_ProbeLevel / Field_Unk55 value that meets any level
!SceneFlag_Warp = $80                    ; Field_SceneFlags bit 7: fade out then warp to Loc_Dest*
!Map_ExitRecSize = $07                   ; bytes per ExitRom record
!Map_ExitRowRange = $3F                  ; an exit record in the probe's column matches when its row
                                         ; is less than this far from the probe's
!Exit_DestHiBit = $01                    ; ExitRom.DestHiFacing bit 0: Loc_DestId bit 8
!Exit_FacingMask = $0F                   ; ExitRom.DestHiFacing bits 1-4 after one LSR: the facing
!Exit_FacingBit7 = $80                   ; ExitRom.DestHiFacing bit 7, kept in Loc_DestFacing
!TileAttrA_AnimNear = $10                ; Map_TileAttrA bit 4: start a tile animation
!TileAttrA_PushSpeed = $0C               ; Map_TileAttrA bits 2-3: push speed (0 = none)
!TileAttrA_PushSlow = $04                ; push speed 1: Map_PushSlow
!TileAttrA_PushMid = $08                 ; push speed 2: Map_PushMid (3: Map_PushFast)
!TileAttrA_PushDir = $03                 ; Map_TileAttrA bits 0-1: push direction
!Map_ProbeIsChest = $01                  ; A from Map_Unk8A6D's tile test: C=1 because of a treasure
!Map_ProbeIsTile = $00                   ; A from that test otherwise (C=1: the half tile blocks)
!Map_PushSlow = $08                      ; push amounts written to Map_Unk1D2A/1D2B (1/16 pixel)
!Map_PushMid = $10                       ; push amount for push speed 2
!Map_PushFast = $20                      ; push amount for push speed 3
; --- Location map setup (LocLoad_UnkA33B, Map_InitMasksAndLimits, Map_UnpackTilePlanes,
;     Map_LoadExitTiles, Map_LoadTreasureTiles) ---
!Loc_IdMask = $01FF                      ; Loc_Id bits 0-8: the location number (indexes
                                         ; ExitRom_LocOfs / TreasureRom_LocOfs by word)
!Map_PropsPtrSize = $03                  ; bytes per Map_PropsPtrs entry (a long pointer)
!MapProps_WidthBits = $03                ; MapProps.Size1 / Size3 bits 0-1: (n + 1) x 16
!MapProps_HeightBits = $0C               ; bits 2-3: (n + 4) x 4, i.e. (n / 4 + 1) x 16
!MapProps_HeightAdd = $04                ; added to the height bits before the two ASLs
!MapProps_L2WidthBits = $30              ; MapProps.Size1 bits 4-5: n + $10
!MapProps_L2HeightBits = $C0             ; MapProps.Size1 bits 6-7: n / 4 + $10
!MapProps_OwnStep2 = $10                 ; MapProps.Size3 bit 4: Map_OwnStep2 in Map_OwnStepFlags
!MapProps_OwnStep3 = $20                 ; MapProps.Size3 bit 5: Map_OwnStep3
!MapProps_HalfRate2 = $40                ; MapProps.Size3 bit 6: Map_Unk0BC9 = Map_Unk0BC9Set
!Map_Unk0BC9Set = $80                    ; Map_Unk0BC9 with bit 7 set (half-rate layer 2)
!Map_Unk0BCAOn = $01                     ; Map_Unk0BCA value for MapProps.Size3 bit 7
!MapMove_XBits = $07                     ; MapProps.Move2/3 bits 0-2: X step 1 << (n - 1)
!MapMove_XNeg = $08                      ; bit 3: the X step is negative
!MapMove_YBits = $70                     ; bits 4-6: as MapMove_XBits for Y
!MapMove_YNeg = $80                      ; bit 7: the Y step is negative
!MapScreens_MainBgs = $07                ; MapProps.Screens bits 0-2: BG1-3 on the main screen
!MapScreens_MainObj = $08                ; bit 3: OBJ on the main screen (moved to TM bit 4)
!MapScreens_SubBgs = $70                 ; bits 4-6: BG1-3 on the sub screen
!MapScreens_SubObj = $80                 ; bit 7: OBJ on the sub screen (moved to TS bit 4)
!Map_Metatiles32 = $20                   ; a layer size of two screens (Map_Unk0BCB ...)
!Map_Metatiles48 = $30                   ; three screens
!Map_Metatiles64 = $40                   ; four screens
!Map_WrapMask16 = $0F                    ; Map_ColMask*/RowMask* for a 16-metatile layer
!Map_WrapMask32 = $1F                    ; for a 32-metatile layer
!Map_WrapMask64 = $3F                    ; for a 48- or 64-metatile layer
!Map_PlaneBytes = $0040                  ; bytes of one plane in each 256-byte map row (64
                                         ; columns; layer 1, 2, 3 and Map_TileHiBits side by side)
!Map_PlaneCopyLen = $003F                ; MVN count for one plane row (Map_PlaneBytes - 1)
!Map_PlaneRows = $40                     ; map rows a plane spans
!Map_RunFlagMask = $7F                   ; Map_TileHiBits byte with bit 7 set: bits 0-6 are the
                                         ; value of a run (Map_UnpackTilePlanes)
!Map_RunLen256 = $0100                   ; a run count byte of 0 means 256
!Map_ExitNone = $80                      ; Map_TileExitIdx value of a tile that is no exit
!Map_TreasureNone = $80                  ; Map_TreasureIdx value of a tile with no treasure
!Exit_SpanLenMask = $7F                  ; ExitRom.Span bits 0-6: tiles after the first
!Map_TreasureRecSize = $0004             ; bytes per TreasureRom record
!TileHiBits_L1Bit8 = $01                 ; Map_TileHiBits bit 0: bit 8 of the layer-1 metatile
!TileAnim_StateE1 = $E1                  ; Map_TileProps value TileAnim_StateE0 steps to
!TileAnim_StateFF = $FF                  ; Map_TileProps value TileAnim_StateFE steps to

!Obj_LastFrameNone = $FF                 ; Obj_LastFrame after Obj_ResetFrameState (no frame built)
!Map_VramTilemap1 = $6000                ; Map_TilemapVram set by LocLoad_DrawMap (layer 1's tilemap)
!Map_VramTilemap2 = $6800                ; Map_TilemapVram3 set there (layer 2's tilemap)
!Map_VramTilemap3 = $7000                ; Map_TilemapVramL3 set there (layer 3's tilemap)
!Map_VramTilemapAlt = $7800              ; Map_TilemapVram2 set there
!Map_ScSizeInit = $01                    ; Map_TilemapVram4, its high byte and Map_Unk1D86 at a
                                         ; load (LocLoad_DrawMap; probably BGnSC size 1, 64x32)
!Map_EvenMask = $FE                      ; clears bit 0 (Map_InitOrigin's half-rate column)
!Map_ScreenTileRows = $1C                ; 8x8 rows the screen shows (28: 224 lines); bottom bound =
                                         ; top origin + this
!Map_OriginLeadX = $08                   ; metatiles from the screen's left edge to the entry column
                                         ; (Map_InitOriginX)
!Map_OriginLeadY = $08                   ; metatiles from the top edge to the entry row
!Map_OriginLeadYBelow = $06              ; metatile rows Map_InitOriginY keeps below the entry row

!Map_ProbeMidX = $80                     ; Map_ProbeX low byte Map_InitEntryTile probes: the middle
                                         ; of the tile across
!Map_ProbeBottomY = $FF                  ; Map_ProbeY low byte it probes: the bottom pixel row
!Map_EntryLevelMin = $01                 ; Field_Unk55 Map_InitEntryTile sets when the entry tile's
                                         ; level is 0


; --- Location-load graphics, metatile and palette steps (LocLoad_Unk092B, LocLoad_Unk0960,
;     LocLoad_Unk6DCF, LocLoad_Unk7084, LocLoad_Unk09DD, LocLoad_Unk0A14) ---
!LocRom_RecSize = $0E                    ; bytes per LocRom record (LocLoad_Unk092B's multiplier)
!Loc_IdHiBit8 = $01                      ; Loc_Id+1 bit 0: Loc_Id bit 8 (the second 256 records)
!LocRom_HalfOfs = $0E00                  ; LocRom offset of record 256 (256 x LocRom_RecSize)
!LocRom_SetNone = $FF                    ; LocRom.Tileset12 / Tileset3 value: nothing to load
!LocGfx_ListSize = $08                   ; bytes per LocGfx_Lists entry (pack numbers)
!LocGfx_PackPtrSize = $03                ; bytes per LocGfx_PackPtrs / LocGfx_Meta*Ptrs entry
!LocGfx_Vram0 = $2000                    ; VRAM word address of the first of the six packs
!LocGfx_VramStep = $0800                 ; VRAM words from one pack to the next ($1000 bytes)
!LocGfx_PackBytes = $1000                ; bytes uploaded for each of packs 0-4 and the layer-3 pack
!LocGfx_Pack5Bytes = $0F80               ; bytes uploaded for pack 5 ($80 short of a full pack)
!LocGfx_VramL3 = $5000                   ; VRAM word address of the LocRom.Tileset3 graphics pack
!LocPal_RowBytes = $1E                   ; bytes copied per palette row: colours 1-15
!LocPal_RowStep = $20                    ; bytes from one palette row to the next in Pal_Buf
!LocPal_SetBytes = $D2                   ; bytes per LocPal_Rom entry: 7 rows x LocPal_RowBytes

; --- Location objects and event data (Scene_PostLoadInit, LocLoad_Unk56D4, Evt_InitObjects,
;     LocLoad_CheckEvtData, LocLoad_InitUnk7F3700) ---
!ObjQ_Unk69Init = $0048                  ; ObjQ_Unk69 set by Scene_PostLoadInit
!ObjQ_ScanlineInit = $0078               ; ObjQ_ScanlineLimit set by Scene_PostLoadInit (line 120)
!BankC2_PostLoadArg = $0B                ; A for the BankC2_Entry8004 call ending Scene_PostLoadInit
                                         ; (the command is not traced)
!Evt_FuncTableBytes = $0020              ; bytes of one object's function table in Evt_Data (16 words)
!Evt_Unk7F0200Bytes = $0200              ; bytes of Evt_Unk7F0200 Evt_InitObjects clears
!Obj_Unk1000Init = $04                   ; Obj_Unk1000 set by Evt_InitObjects
!Obj_Unk1100SkipSlots = $3F              ; Obj_Unk1100 entries Evt_InitObjects first sets to
                                         ; Obj_Unk1100Skip (63 of the 64)
!Obj_Unk1100Skip = $80                   ; Obj_Unk1100 bit 7: the slot is skipped
!Obj_PosOffMap = $FF00                   ; Obj_PosX / Obj_PosY set by Evt_InitObjects: tile 255
                                         ; (probably "not placed yet")
!Obj_Unk1A00Init = $10                   ; Obj_Unk1A00 set by Evt_InitObjects
!Obj_Unk1A81Init = $01                   ; Obj_Unk1A81 set by Evt_InitObjects (a frame build
                                         ; needs 1..$7F)
!Obj_Unk1C80Init = $03                   ; Obj_Unk1C80 set by Evt_InitObjects
!Obj_OamFlagsInit = $80                  ; Obj_OamFlags set by Evt_InitObjects (bit 7; range 1)
!ObjX_Unk7F0B80Init = $FF                ; both bytes of ObjX_Unk7F0B80 per object (wiped again at once)
!Obj_Unk1900Bytes = $0100                ; bytes of Obj_Unk1900 Evt_InitObjects clears
!ObjX_ClearBytes = $15C0                 ; bytes Evt_InitObjects clears from ObjX_Unk7F0580
                                         ; ($7F:0580-$7F:1B3F)
!ObjQ_Unk71Init = $8000                  ; ObjQ_Unk71 set by Evt_InitObjects
!Evt_Unk0920Free = $FF                   ; Evt_Unk0920 entry value for "free"
!Evt_BadObjCount = $0D                   ; Evt_ObjCount LocLoad_CheckEvtData refuses together with
!Evt_BadFirstByte = $0A                  ; this first Evt_Data byte
!Halt_ColorEvtUnk = $01F0                ; Sys_HaltWithColor colour for that pair
!Evt_DataMax = $1700                     ; most bytes of event data: $7F:2000 up to Map_Unk7F3700
!Halt_ColorEvtLong = $000F               ; Sys_HaltWithColor colour (BGR555 red) for longer data
!Map_Unk7F3700RecBytes = $20             ; bytes of each of the four Map_Unk7F3700 blocks
!Map_Unk7F3700TailBytes = $06            ; bytes of the fifth block, at $7F:3780

; --- Scene reload (Scene_ReloadStep and its matched callees) ---
!Scene_VIrqLine = $00D3                  ; VTIMEL value Scene_ResumeNmi sets (line 211)
!Field_UploadVram1F00 = $1F00            ; VRAM word address of Field_UploadUnk1F00's first part
!Field_UploadUnk1F00Bytes = $0200        ; bytes of that part
!Field_UploadVram4FC0 = $4FC0            ; VRAM word address of its second part
!Field_UploadUnk4FC0Bytes = $0080        ; bytes of that part
!Field_UploadUnk0000Bytes = $0040        ; bytes of each Field_UploadUnk0000 upload
!Field_UploadVram0000 = $0000            ; its four VRAM word addresses
!Field_UploadVram0100 = $0100
!Field_UploadVram0030 = $0030
!Field_UploadVram0130 = $0130
!Field_UploadVram1D00 = $1D00            ; VRAM word address of Field_UploadUnk1D00
!Field_UploadUnk1D00Bytes = $0280        ; bytes it uploads
!Field_UploadVram1C00 = $1C00            ; VRAM word address of Field_UploadUnk1C00
!Field_UploadUnk1C00Bytes = $0200        ; bytes it uploads
!Field_UploadVram57E0 = $57E0            ; VRAM word address of Field_UploadUnk57E0
!Field_UploadUnk57E0Bytes = $0040        ; bytes it uploads
!Field_Unk0B88Bytes = $1E                ; bytes of Field_Unk0B88 (Field_ResetUnk0B88)
!Field_Unk0B80Empty = $80                ; value Field_ResetUnk0B80/0B88 store (probably "none")
!Pal_Row0SetMask = $0007                 ; Menu_Config+1 bits 0-2: the FieldRom_PalRow0Sets entry
!Pal_Grey9 = $0C63                       ; BGR555 (3,3,3): colour 9 of Pal_Buf row 0 (Pal_LoadUnkRow0)
!Pal_Grey10 = $18C6                      ; BGR555 (6,6,6): colour 10
!Pal_Grey11 = $739C                      ; BGR555 (28,28,28): colour 11
!Pal_BufBytes = $0200                    ; bytes of Pal_Buf / Pal_CgramBuf (16 rows x 16 colours x 2)
!Obj_DrawFillWords = $0010               ; words Obj_ResetDrawLists writes through WMDATA (32 bytes)

; --- Field/battle hand-off (Field_Unk038F, Scene_Unk0283) ---
!FieldBtl_EvtNoReset = $20               ; FieldBtl_EvtFlags bit 5: Scene_Unk0283 rebuilds the field
                                         ; instead of the FieldBtl_Result = 1 reset
!FieldBtl_EvtUnk80 = $80                 ; FieldBtl_EvtFlags bit 7: Field_Unk034B leaves members 2
                                         ; and 3 alone and sets Field_Unk7F03FE = 3
!Field47_Upload1D00 = $01                ; Field_Unk47 bits NmiHandler serves, one per frame in this
!Field47_Upload1C00 = $02                ; order, clearing it: Field_UploadUnk1D00, 1C00, 1F00 and
!Field47_Upload1F00 = $04                ; 57E0
!Field47_Upload57E0 = $08
!Field_Unk47Bits03 = $09                 ; bits 0 and 3 Scene_Unk0283 sets in Field_Unk47
!FieldBtl_AttrSide = $0010               ; FieldBtl_AttrA/B window: 16 rows of 16 tiles
!FieldBtl_SubMask = $0F                  ; low 4 bits of Obj_ScreenX/Y: pixel within the tile
!FieldBtl_PcPrio = $20                   ; OAM attribute bit 5 (priority bit 1) FieldBtl_SavePartyPos
                                         ; sets in the party's Obj_PrioLow/High
!FieldBtl_ViewTilesX = $0F               ; Field_Unk0617 keeps objects whose tile X - origin is
                                         ; 1 to this - 1
!FieldBtl_ViewTilesY = $0E               ; ... and tile Y - origin 1 to this - 1
!Field_BattleObjMax = $0C                ; entries Field_Unk0617 puts in Field_BattleObjList at most
!FieldBtl_PcRecSize = $05                ; bytes per FieldBtlPc record
!FieldBtl_ObjRecSize = $0C               ; bytes per FieldBtlObj record
!FieldBtl_ObjTileLimit = $C0             ; FieldBtl_SaveObj skips objects whose Obj_VramTile low
                                         ; byte is this or more
!FieldBtl_NoObj = $FFFF                  ; FieldBtlObj.Unk05/06 word (and two FieldBtl_ObjSlots) for
                                         ; no object
!FieldBtl_ObjKind6Flag = $40             ; FieldBtlObj.Flags bit 6: Obj_Unk1100 was 6
!FieldBtl_ObjUnk1A81Bit = $80            ; Obj_Unk1A81 bit 7, kept in FieldBtlObj.Flags; when set,
                                         ; FieldBtl_SaveObj calls Obj_Unk72B4 and
                                         ; FieldBtl_RestoreObj's removal calls Obj_Unk734C
!Obj_Unk1000Bit7 = $80                   ; Obj_Unk1000 bit 7 (blocks Evt_StartTargetFunc1); set by
                                         ; FieldBtl_RestoreObj on an object it removes
!Obj_DrawBucketMask = $FE                ; (Obj_ScreenY >> 1) & this = the Obj_DrawBucket offset
                                         ; (Obj_DrawLink / Obj_DrawUnlink)
!Obj_AnimModeFixed = $03                 ; Obj_AnimMode 3: show Obj_FixedFrame
!FieldBtl_PpuUnk6A = $02                 ; FieldBtlPpu.Unk6A (CGWSEL position)
!FieldBtl_PpuUnk6E = $09                 ; FieldBtlPpu.Unk6E
!Evt_RedirectPos = $16FF                 ; Obj_ScriptPos Evt_RedirectObjScript sets (an Evt_Data
                                         ; offset: Map_Unk7F3700's block 0, a walk to the leader;
                                         ; see the banner of Evt_OpD9_PartyWalkToTiles)

; --- Object motion and view test (Vblank_UnkA810 and its steps) ---
!Obj_Unk1100FreeMove = $03               ; Obj_Unk1100 below this: Vblank_UnkA810 moves the object
                                         ; with Obj_MoveStepFree (others with Obj_MoveStep)
!Obj_Unk1100Eight = $08                  ; Obj_Unk1100 value Vblank_UnkA810 leaves alone (no move,
                                         ; no view test, no redraw)
!Obj_Unk0F00Active = $80                 ; Obj_Unk0F00 bit 7: the object is in the view window and
                                         ; set up for drawing (Obj_UpdateInView sets and clears it)
!ObjView_MarginX = $04                   ; 8-pixel columns the view window reaches past the view on
                                         ; each side (two map tiles)
!ObjView_MarginTop = $02                 ; rows it reaches above Map_TileOriginY (Obj_UpdateInView)
!ObjView_MarginBottom = $05              ; rows it reaches below Map_Unk1D10
!ObjView_Max = $FF                       ; window bound clamped here when the margin overflows
!ObjX_AnimLoopsOut = $02                 ; ObjX_AnimLoops value set (when nonzero) as an object
                                         ; leaves the window
!Obj_ScreenWrap = $0100                  ; bit 8 of a 9-bit screen coordinate, set when the object
                                         ; lies left of / above the view (Obj_CalcScreenPos)
!Obj_ScreenXMask = $01FF                 ; low 9 bits of Obj_ScreenX
!Map_FineScrollMask = $0007              ; pixel within an 8-pixel column / row of the scroll
!Dir_QuarterTurn = $40                   ; a quarter turn in Obj_Direction units (256 per turn)
!Dir_HalfTurn = $80                      ; half a turn; also where the sine turns negative
!Dir_ThreeQuarters = $C0                 ; three quarters of a turn
!Dir_Over63 = $40                        ; a distance with this bit set is scaled by 1/4 for the
                                         ; angle lookup (Obj_CalcDirection)
!Dir_Over31 = $20                        ; one with this bit set (and not Dir_Over63) by 1/2
!Dir_Low5 = $001F                        ; a distance below 32 indexes Rom_AngleTable directly
!Dir_Low7 = $007F                        ; bits kept before the 1/4 scaling (bit 7 is dropped)
!Dir_Rise7Mask = $007C                   ; rise bits kept for the 1/4 scaling (shifted to x 32)
!Dir_Low6 = $003F                        ; bits kept before the 1/2 scaling
!Dir_Rise6Mask = $003E                   ; rise bits kept for the 1/2 scaling
!TileAttr_Prio = $40                     ; Map_TileAttrA/B bit 6: the tile's OAM priority bit
!Obj_OamFlagsTilePrio = $80              ; Obj_OamFlags bit 7: priorities follow the tile under
                                         ; the object (Obj_SetVelocityChecked)
!Obj_OamFlagsPrioMask = $30              ; Obj_OamFlags bits 4-5 (Obj_PrioHigh) and, shifted left 4,
                                         ; bits 0-1 (Obj_PrioLow): the fixed OAM priorities
!Obj_Unk1C80Block = $01                 ; Obj_Unk1C80 bit 0: Obj_SetVelocityChecked turns the object
                                         ; when the tile ahead blocks
!SprBuf_UsedEntries = $04                ; SprBuf_Owner entries the allocators use (0-3)

; --- Map region copy (Field_UnkAF4E: Field_Unk44 bits) ---
!MapCopy_L1 = $01                        ; copy the Map_TileProps plane (layer 1's tiles)
!MapCopy_L2 = $02                        ; copy Map_Layer2Tiles
!MapCopy_L3 = $04                        ; copy Map_Layer3Tiles
!MapCopy_HiBits = $08                    ; copy Map_TileHiBits (whole bytes)
!MapCopy_AttrA = $10                     ; copy Map_TileAttrA
!MapCopy_AttrB = $20                     ; copy Map_TileAttrB
!MapCopy_L1Bit8 = $40                    ; copy only Map_TileHiBits bit 0 (TileHiBits_L1Bit8)
!MapCopy_L2Bit8 = $80                    ; copy only Map_TileHiBits bit 1 (TileHiBits_L2Bit8)
!TileHiBits_L2Bit8 = $02                 ; Map_TileHiBits bit 1: bit 8 of the layer-2 metatile

; --- Field_Unk7EF000 tilemaps (Field_Unk29F7, Field_Unk2B78) ---
!Field_Unk7EF000Tile = $F0               ; first tile of Field_Unk29F7's map (it uses this + 0-15)
!Field_Unk7EF000Hi = $20                 ; tilemap high byte: priority, palette 0, tile bits 8-9 = 0
!Field_Unk7EF000HiAlt = $23              ; tilemap high byte: priority, palette 0, tile bits 8-9 = 3
!Field_Unk7EF000Pairs = $000F            ; tile pairs between the corners of Field_Unk29F7's top and
                                         ; bottom rows (30 tiles)
!Field_Unk7EF000HiGrid = $29             ; Field_Unk2B78's high byte: priority, palette 2, tile bit 8
!Field_Unk7EF000Run = $10                ; tiles per run in Field_Unk2B78
; --- Field HDMA (Hdma_InitChannelsFD, EngFD_UnkC124, EngFD_UnkD52D, EngFD_UnkC2C1) ---
!Hdma_TableSetA = $0F80                  ; bank-$7F address of the first set of 8 HDMA tables
!Hdma_TableSetB = $1238                  ; ... of the second set
!Hdma_TableBytes = $57                   ; bytes per table in a set
!Field_Unk53HdmaSetMask = $0F            ; Field_Unk53 bits: all clear = table set A
!Field_Unk53Phase = $01                  ; Field_Unk53 bit EngFD_UnkC2C1 flips each frame
!Hdma_ScRecord2Unk = $1C                 ; bytes 0 and 2 of Hdma_Unk7F14F4
!Hdma_ScrollPair0 = $0037                ; second words of the four Hdma_Unk7F14F8 pairs (the first are 0)
!Hdma_ScrollPair1 = $FFF1
!Hdma_ScrollPair2 = $FFBC
!Hdma_ScrollPair3 = $FF76
!Hdma_WhWholeLine = $FF00                ; a WH0/WH1 word: WH0 = 0, WH1 = $FF
!HdmaGrad_Lines = 40                     ; EngFD_UnkD52D: dividend ...
!HdmaGrad_Steps = 8                      ; ... and divisor of its run length (5)
!HdmaGrad_AddFirst = $E8                 ; COLDATA of its first step (then down to $E1)
!HdmaGrad_SubLast = $E9                  ; COLDATA of its last step
!Hdma_GradAdd = $01                      ; CGADSUB byte of the first half: add, BG1
!Hdma_GradSub = $81                      ; CGADSUB byte of the second half: subtract, BG1
!Hdma_GradBytes = $0100                  ; bytes EngFD_UnkD52D copies to Hdma_Unk7F1600

; --- Location animation set-up (FieldFD_LoadAnimSetA/B) ---
!FieldRom_AnimListAPtrs = $FDF290        ; 2 B per LocRom.Tileset12 & $3F: offset of its list from FieldRom_AnimListA
!FieldRom_AnimListA = $FDF310            ; the lists FieldFD_LoadAnimSetA reads
!FieldRom_AnimListBPtrs = $FDF9C7        ; 2 B per LocRom.Palette: offset of its list from FieldRom_AnimListB
!FieldRom_AnimListB = $FDFA77            ; the lists FieldFD_LoadAnimSetB reads
!LocRom_AnimSetMask = $3F                ; LocRom.Tileset12 bits that pick FieldFD_LoadAnimSetA's list
!FieldAnimA_Wram = $0400                 ; WMADD (with WMADDH = bank $7F) FieldFD_LoadAnimSetA writes from
!FieldAnim_NumRecs = 12                  ; records of FieldAnimA (and of FieldAnimB)
!FieldAnimA_Size = 5                     ; bytes per FieldAnimA record
!FieldAnim_EndRecord = $80               ; FieldFD_LoadAnimSetA list byte: the record only gets .Unk3 = $80
!FieldAnim_Kind2 = 2                     ; FieldFD_LoadAnimSetA record kinds with their own copy loops
!FieldAnim_Kind4 = 4
!FieldAnimB_KindMask = $F0               ; FieldFD_LoadAnimSetB: the kind nibble of a list byte
!FieldAnimB_Kind10 = $10                 ; kinds with 9-byte records
!FieldAnimB_Kind80 = $80                 ; ... the second also stores FieldAnimB.Ptr
!FieldAnimB_SkipMask = $0F               ; FieldAnimB.Unk0 bits: list bytes skipped (+ 1) after a kind-$80 record
!FieldAnimB_Size = 12                    ; bytes per FieldAnimB record
!FieldAnimB_Filled = 6                   ; records FieldFD_LoadAnimSetB fills (the other 6 get .Unk0 = 0)

endif

; --- NMI handler (NmiHandler, $C0:EA63) ---
!Nmi_Nmitimen = NMI_ENABLE|IRQ_HV_ENABLE|AUTOJOY_ENABLE ; $A1: NMI, the V-count IRQ (bit 5)
                                         ; and joypad auto-read, written at each NMI
!Nmi_BgMode = BG_MODE_1|BG3_HIGH_PRIO    ; $09: BG mode 1 with BG3 on top, written at each NMI
!Oam_ShadowBytes = $0220                 ; bytes Oam_UploadShadow sends: Oam_LowTable (512) and
                                         ; Oam_HighTable (32)
!Field_Unk58Mask = $83FF                 ; Field_WaitFrame's AND on Field_Unk58 after the INC
!Field_UploadVram5800 = $5800            ; VRAM word base of Field_UploadUnk5800 (plus Field_Unk31
                                         ; x $200)
!Field_UploadUnk5800Bytes = $0400        ; bytes Field_UploadUnk5800 sends from Field_Unk7EF000

; --- Object tile slots (Obj_Unk6F9A / Obj_Unk7056, Obj_TileSlot) ---
!ObjTile_SingleTop = $19                 ; the one-slot search tries slots $19 down to 1
!ObjTile_PairFirst = $0C                 ; the two-slot search tries the even slots $0C-$16
!ObjTile_PairEnd = $18                   ; ... and stops here
!ObjTile_PairMask = $00FE                ; slot & this: the even slot of a pair
!ObjTile_OddBit = $0001                  ; slot & this: the odd half (8 tiles further)

; --- Object palette slots (Obj_Unk7170 / Obj_Unk72B4 / Obj_Unk734C, Obj_PalSlot) ---
!ObjPal_SlotKind0 = $05                  ; Obj_Unk1100 = 0 always uses palette slot 5,
!ObjPal_SlotKind1 = $06                  ; 1 slot 6
!ObjPal_SlotKind2 = $07                  ; and 2 slot 7
!ObjPal_AnyEnd = $05                     ; kinds 3, 4 and 7-11 use slots 0-4
!ObjPal_BtlFirst = $01                   ; kinds 5 and 6 (and FieldBtl_SaveObj) use slots 1-3
!ObjPal_BtlEnd = $04
!ObjPal_AttrMask = $0E                   ; slot x 2 & this: Obj_OamAttr (palette bits 1-3)
!ObjPal_CopyCount = $0017                ; MVN count - 1: 24 bytes, colours 1-12

; --- Evt_FindSolidObjInFront / Evt_FindOrAddUnk0920 ---
!Obj_Unk1C80Front = $02                  ; Obj_Unk1C80 bit 1: Evt_FindSolidObjInFront looks for
                                         ; objects only when it is set
!ObjFront_Reach = $0100                  ; |distance| limit of the in-front tests (one tile: the
                                         ; positions' high byte is the tile)
!Evt_Unk0920Entries = $0010              ; entries of Evt_Unk0920 / Evt_Unk0930
!Halt_ColorUnk0920Full = $4010           ; Sys_HaltWithColor colour when Evt_Unk0920 has no free entry

; --- Event movement opcodes (Evt_Op7A_ArcToTile ... Obj_SetStandAnim) ---
!Evt_BlockedTurn = $30                   ; Obj_Direction step (3/16 of a turn) the movement opcodes add
                                         ; when Evt_FindSolidObjInFront finds an object in the way
!Obj1C81_CentreOnTile = $01              ; Obj_Unk1C81 bit 0: on arriving at a target tile, run
                                         ; Obj_Unk305D (steps toward the tile's centre, probably)
!Obj1C81_OntoObj = $02                   ; Obj_Unk1C81 bit 1: next to a target object, run
                                         ; Obj_Unk30B3 (steps onto its position, probably)
!ObjX_Unk7F0B00Dir = $80                 ; ObjX_Unk7F0B00 value the direction moves (opcodes $92,
                                         ; $9C, $9D) store; the others store their frame count
!EvtFollow_ColLimit = $0E                ; Evt_Op8F_FollowPc stops when the object's screen column is
                                         ; 2 to this - 1
!EvtFollow_RowLimit = $0D                ; ... and its screen row 2 to this - 1
!ObjAnim_RowStand = $00                  ; Obj_AnimRow Obj_SetMoveAnim / Obj_SetStandAnim use at rest
!ObjAnim_RowWalk = $01                   ; ... moving slower than ObjAnim_RunSpeed
!ObjAnim_RowRun = $06                    ; ... moving at ObjAnim_RunSpeed or more (kinds below
                                         ; ObjAnim_RunKinds only)
!ObjAnim_RunSpeed = $20                  ; |Obj_VelX| + |Obj_VelY| from which Obj_SetMoveAnim runs
!ObjAnim_RunKinds = $04                  ; Obj_Unk1100 kinds below this may take ObjAnim_RowRun
!Obj_AnimModeNormal = $01                ; Obj_AnimMode Obj_SetMoveAnim sets when it leaves
                                         ; Obj_AnimModeFixed (Obj_AnimRow not $FF)

; --- Event call opcodes ($00-$09) ---
!Halt_ColorBadOpcode = $1639             ; Sys_HaltWithColor colour for an unused event opcode
                                         ; (Evt_UnusedOpcode)
!Evt_CallFuncMask = $000F                ; low nibble of a call opcode's level/function operand: the
                                         ; function number (word index in the 16-word table)

; --- Event jump and condition opcodes ($10-$1C) ---
!EvtIf_Page1Flag = $80                   ; Evt_Op16_IfMemByte's comparison byte, bit 7: the byte tested
                                         ; is at $7F:0100 + the operand (else $7F:0000 + it)
!EvtIf_Page1 = $0100                     ; the offset bit 7 of that byte adds

; --- Event button opcodes ($2D-$44) ---
; Bits of Menu_PadHeld / Pad_PressedLatch, by Pad_Pressed's low-byte layout (A X L R B Y Select
; Start, bits 7-0; that layout is inferred from the pad reader at $C2:84F0)
!Pad_A = $80                             ; bit 7: A
!Pad_X = $40                             ; bit 6: X
!Pad_L = $20                             ; bit 5: L
!Pad_R = $10                             ; bit 4: R
!Pad_B = $08                             ; bit 3: B
!Pad_Y = $04                             ; bit 2: Y
!Pad_Unk00F6Bit1 = $02                   ; Pad_Unk00F6 (and Pad_Unk00F6Latch) bit 1, tested by event
                                         ; opcode $3B (which button the map puts there not traced)

; --- Event arithmetic and bit opcodes ($5B-$7F) ---
!EvtBit_NumMask = $0F                    ; bits of opcode $65/$66's bit operand that index BitSet /
                                         ; BitClear (8 entries each: 8-15 run into the next table)

; --- Event animation and wait opcodes ($AA-$BD) ---
!Obj_AnimModeLoops = $02                 ; Obj_AnimMode 2: counted passes of Obj_AnimRowAlt
                                         ; (ObjX_AnimLoops)
!Evt_AnimLoopsOnce = $02                 ; ObjX_AnimLoops Evt_OpAB_PlayAnimOnce starts with:
                                         ; Obj_AnimTickAndQueue leaves 1 after a pass of the row
!Evt_WaitRuns4 = $04                     ; script runs waited by opcode $B9 (Evt_OpB9_Wait4)
!Evt_WaitRuns8 = $08                     ; ... by opcode $BA
!Evt_WaitRuns16 = $10                    ; ... by opcode $BC
!Evt_WaitRuns32 = $20                    ; ... by opcode $BD

; --- Object steps onto a tile centre / another object, touch and push (Obj_Unk305D ...) ---
!Obj_SubTileMask = $F0                   ; Obj_PosX/Y low byte bits 4-7: the position within the tile
                                         ; that Obj_Unk305D compares
!Obj_TileCentreX = $80                   ; Obj_Unk305D's X target within the tile (the middle)
!Obj_TileFootY = $F0                     ; Obj_Unk305D's Y target within the tile (its last $10)
!Obj_CentreStep = $10                    ; Obj_VelX/Y step of Obj_Unk305D / Obj_Unk30B3 (+$10)
!Obj_CentreStepNeg = $F0                 ; ... and its negative (-$10)
!Obj_PosCoarseMask = $FFF0               ; Obj_PosX/Y bits Obj_Unk30B3 compares (the step grid)
!Evt_Func2Ofs = $0004                    ; offset of function 2 in an object's 16-word function table
!Obj_Unk1C00Func2 = $02                  ; Obj_Unk1C00 Evt_StartTargetFunc2 sets as it starts function 2
!Obj_Unk1C00Func2Min = $03               ; Evt_StartTargetFunc2 starts nothing while Obj_Unk1C00 is
                                         ; below this
!Obj_Unk1B01Push = $02                   ; Obj_Unk1B01 bit 1: Evt_PushTarget may move the object
!Field54_Push = $02                      ; Field_Unk54 bit 1: set by Evt_PushTarget when it sends an
                                         ; object off; no other push starts while it is set (event
                                         ; opcode $FF $9D, Evt_OpFF9D_ClearPush, clears it)
!Evt_PushScriptPos = $177F               ; Obj_ScriptPos Evt_PushTarget gives the object (an Evt_Data
                                         ; offset: Map_Unk7F3700's fifth block, seeded 96 col row,
                                         ; then FF 9D 00, from LocLoad_Unk7F3700Init_Rec4)
!Evt_PushTileOfs = $1780                 ; Evt_Data offset where Evt_PushTarget stores the target
                                         ; tile (column, row): the byte after Evt_PushScriptPos

; --- Event message opcodes ($B8-$C4) ---
!Halt_ColorNoMsgPtr = $7FE0              ; Sys_HaltWithColor colour when a message opcode runs with
                                         ; Field_Unk2D (the pointer's bank) 0
!Evt_ChoiceMask = $03                    ; bits 0-1 / 2-3 of a choice message's operand: Field_Unk65
                                         ; / Field_Unk64

; --- Event party walk / gather opcodes ($D9/$DA) ---
!Obj_FacingUp = $00                      ; Obj_Facing values (Rom_DirToFacing, Evt_OpA6_Face)
!Obj_FacingDown = $01
!Obj_FacingLeft = $02
!Obj_FacingRight = $03
!Evt_PartyWalkPos0 = $171F               ; Obj_ScriptPos Evt_OpD9 gives the leader: the Evt_Data
                                         ; offset of Map_Unk7F3700's block 1 ($7F:3720)
!Evt_PartyWalkPos1 = $173F               ; ... member 2: block 2 ($7F:3740)
!Evt_PartyWalkPos2 = $175F               ; ... member 3: block 3 ($7F:3760)
!EvtD9_TileMask = $7F                    ; Evt_OpD9's column / row operand bits 0-6 (bit 7: facing)
!EvtD9_AllThere = $04                    ; Evt_PartyWalkCount once every member sent has arrived
!EvtD9_Count3Sent = $01                  ; Evt_PartyWalkCount after sending three members
!EvtD9_Count2Sent = $02                  ; ... two
!EvtD9_Count1Sent = $03                  ; ... the leader alone
!Field54_Gather = $01                    ; Field_Unk54 bit 0: Evt_OpDA_PartyGather has sent members off
!EvtDA_AllThere = $03                    ; Field_Unk7F03FE once every member sent has arrived
!EvtDA_Count2Sent = $01                  ; Field_Unk7F03FE after sending members 2 and 3
!EvtDA_Count1Sent = $02                  ; ... member 2 alone

; --- Event item, gold, character and battle opcodes ($33, $C7-$D8) ---
!Field54_Unk80 = $80                     ; Field_Unk54 bit 7: set by Evt_Op33_SetPalette (no reader
                                         ; traced)
!BankC1Svc_FindItem = $00                ; BankC1_Entry8003 service: A = item Y's id when it is in the
                                         ; inventory ids at $7E:2400, else 0 ($C1:CFE9)
!BankC1Svc_RemoveItem = $02              ; ... one fewer of item Y ($C1:D056)
!BankC1Svc_HasGold = $03                 ; ... A nonzero when the gold is at least Y ($C1:D086)
!BankC1Svc_RemoveGold = $05              ; ... takes Y off the gold when there is that much ($C1:D0ED)
!BankC2Cmd_FindInParty = $00             ; BankC2_Entry8004 commands (Menu_Unk8C36's table at
                                         ; $C2:8C5B, Y = a character): A = 0 when it is in the party
!BankC2Cmd_AddToParty = $01              ; ... put it in the party
!BankC2Cmd_PartyToReserve = $02          ; ... move it from the party to the reserve
!BankC2Cmd_FindListed = $03              ; ... A = 0 when it is anywhere in Menu_PartyOrder
!BankC2Cmd_AddToReserve = $04            ; ... add it to the reserve unless listed
!BankC2Cmd_Unlist = $05                  ; ... empty its place in Menu_PartyOrder
!BankC2Cmd_Unk0A = $0A                   ; ... not traced (Y = a character, probably; X = an argument)
!BankC2Cmd_ItemCount = $0C               ; ... A = the count of item X held (X, not Y)
!ObjQ_Unk78Set1 = $01                    ; ObjQ_Unk78 value Evt_OpD3_AddCharToParty stores (only 2 is
                                         ; tested by Obj_AnimTickAndQueue)
!Obj_Unk1100Leader = $00                 ; Obj_Unk1100 of the leader's object (Evt_OpB0_PartyControl's
                                         ; kind 0)
!Obj_Unk1100Member2 = $01                ; ... of party member 2 (kind 1); member 3 is kind 2
!Obj_Unk1100Out = $03                    ; Obj_Unk1100 Evt_OpD4 / Evt_OpD6 give an object leaving
                                         ; the party
!Pal_PartyRow0 = $7E21A0                 ; Pal_Buf row of sprite palette slot 5 (party kind 0)
!Pal_PartyRow1 = $7E21C0                 ; ... slot 6 (kind 1)
!Pal_PartyRow2 = $7E21E0                 ; ... slot 7 (kind 2)
!Pal_RowCopyCount = $001F                ; MVN count - 1: one 16-colour palette row (32 bytes)

; --- Event location, sound, fade and map opcodes ($DC-$FA) ---
!Field_Unk1EOn = $01                     ; Field_Unk1E value Evt_OpDE / Evt_OpDF store
!Audio_Cmd18 = $18                       ; sound-driver command Evt_OpE8 sends (bank $C2's
                                         ; C2Scene_SoundCmd18; meaning not traced)
!Audio_Cmd18Arg1 = $80                   ; its Audio_CmdArg1
!Audio_Cmd82 = $82                       ; sound-driver commands Evt_OpEB sends after Audio_CmdUnk81
!Audio_Cmd83 = $83                       ; (meanings not traced)
!Audio_Cmd82Arg1 = $FF                   ; Audio_CmdArg1 of both
!Apuio3_BusyMask = $0F                   ; APUIO3 bits Evt_OpEE_WaitApuio3 waits on (not traced)
!EvtFade_DelayMask = $0F                 ; Evt_OpF0's operand bits 0-3: frames between steps
!EvtFade_DelayMask7 = $7F                ; Evt_OpF1's speed operand bits 0-6: frames between steps
!Fade_ChannelMask = $E0                  ; Fade_FixedColor bits 5-7: the COLDATA channel bits
!Fade_IntensityMask = $1F                ; Fade_FixedColor bits 0-4: the intensity
!FadeFlag_Unk10 = $10                    ; Field_FadeFlags bit 4: set with FadeFlag_FixedColor by
                                         ; Evt_OpF1_FadeFixedColor (no reader traced)
!EvtFade_MathAdd = !Layer_Bg123Obj       ; Ppu_Unk0BE0 for an adding fixed-colour fade: CGADSUB add
                                         ; on BG1-3 and OBJ
!EvtFade_MathSub = $97                   ; ... subtracting (CGADSUB bit 7 + BG1-3 and OBJ)
!MapCopy_LayerBits = $07                 ; Field_Unk44 bits 0-2 (MapCopy_L1-L3): the layers
!BankC2Cmd_Unk06 = $06                   ; BankC2_Entry8004 commands of Evt_OpF8-FA (see
!BankC2Cmd_Unk07 = $07                   ; Evt_OpF8_BankC2Cmd06And07)
!BankC2Cmd_Unk08 = $08                   ; ... of Evt_OpFF9F_BankC2Cmd08

; --- Event credits, layer-3 and window-effect opcodes ($29-$2F, $32, $FE, $FF) ---
!Credits_GfxPack = $FD0000               ; ROM pack Credits_LoadGfx unpacks (probably the credits font)
!Credits_GfxBytes = $0400                ; bytes of it Credits_LoadGfx uploads to VRAM
!Credits_BlockMask = $7F                 ; Evt_Op29's block operand bits 0-6 (bit 7 picks Field_Unk0BE9)
!Field_Unk0BE9Set1 = $01                 ; Field_Unk0BE9 by Evt_Op29: block operand bit 7 clear
!Field_Unk0BE9Set2 = $02                 ; ... bit 7 set
!Field54_Bit2 = $04                      ; Field_Unk54 bit 2 (Evt_Op2A): the low bit of Field54_MapReq
!Field54_Bit3 = $08                      ; Field_Unk54 bit 3 (Evt_Op2B): the high bit of Field54_MapReq
!EvtQuad_Values = $08                    ; Evt_OpFE's start/end pairs: X and Y of four points
!EventHook_WinGrow0 = $01                ; Field_EventHook values the $FF and $FE opcodes set: hook 1
!EventHook_WinShrink0 = $02              ; hook 2
!EventHook_WinC3E = $03                  ; hook 3
!EventHook_WinGrow1 = $04                ; hook 4
!EventHook_WinShrink1 = $05              ; hook 5
!EventHook_WinQuad = $06                 ; hook 6
!EventHook_LeaveToBankC3 = $0B           ; hook 11
!EventHook_WinPulse = $0C                ; hook 12 (it ends at EventHook_Idle)
!EventHook_WinShrink1Off = $0E           ; hook 14
!WinFx_C3EMode1 = $01                    ; WinFx_C3EMode values of opcodes $FF $92/$94 and $93/$95
!WinFx_C3EMode2 = $02                    ; (what BankC3_Entry000E does with them is not traced)
!WinFx_SizeBit0 = $01                    ; WinFx_Size bit 0 (Hdma_InitChannelsFD's channel-7 choice)
!WinFx_SizeBit1 = $02                    ; WinFx_Size bit 1: hook 3 leaves the window on when set
!EvtFF_FirstSub = $90                    ; opcode $FF's second byte: first Evt_OpFFTable entry
!EvtFF_SubFFF1 = $80                     ; ... JML FdVec_FFF1
!EvtFF_SubFFEB = $81                     ; ... JML FdVec_FFEB
!EvtFF_SubFFE8 = $82                     ; ... JML FdVec_FFE8 ($83-$8F: FdVec_FFE5)
!EvtFF_FadeLast = $01                    ; Evt_OpFF_Misc's fade steps while Fade_Brightness >= this
