; ============================================================
; constants_engine.inc — Named constants for the engine core (banks $00, $C0, $FD).
; Same conventions as constants.inc: !Subsystem_Thing, grouped, each
; with a one-line note on what it means and how that was inferred.
; ============================================================
!constants_engine_inc ?= 0
if !constants_engine_inc == 0
!constants_engine_inc = 1

; --- Addressing ---
!BankWrap = $10000   ; one bank: a BRL whose 16-bit offset wraps around the bank
                     ; boundary is written `BRL Target-!BankWrap` so asar computes
                     ; the same (in-range, wrapped) offset the ROM has

; ==== Field direct page and bank $C0 constants ====


; --- Banks and direct-page bases ---
!Bank7E = $7E                            ; WRAM bank $7E (PHA/PLB, DmaFill_Bank)
!Bank7F = $7F                            ; WRAM bank $7F (PHA/PLB, DmaFill_Bank, Obj_GfxBank for
                                         ; graphics already in WRAM)

; --- Banks ---
!Bank00 = $00                            ; bank $00 (MVN bank operand for the low-WRAM mirror)
!BankE4 = $E4                            ; ROM bank $E4 (bank byte of the Field_E4Ptr pointers)

; --- Boot WRAM clear (GameLoop) ---
!Boot_ClearLowSize = $0500               ; bytes cleared from $7E:0000 (stops before the interrupt
                                         ; trampolines at $0500)
!Boot_ClearMainStart = $0700             ; first address of the second cleared block (after the stack
                                         ; page)
!Boot_ClearMainSize = $E900              ; bytes cleared from $7E:0700 to the end of bank $7E
!Boot_Clear7FStart = $5080               ; first address of the cleared bank-$7F block; also its byte
                                         ; count
!BankC2_BootArg = $09                    ; A for the one-time BankC2_Entry8004 call at boot

; --- Locations ---
!Loc_FirstBankC2 = $01F0                 ; Loc_Id at or above this is handled by BankC2_Entry0000
                                         ; (GameLoop_Main)
!Loc_LoadSave = $01FF                    ; Loc_Id at or above this goes to LoadSavePath
                                         ; (GameLoop_Main)
!LoadSave_EntryX = $7C00                 ; X handed to LoadSavePath (meaning unknown)

; --- Field save block ---
!Field_SaveBlockSize = $14E0             ; bytes in Field_SaveBlock (Field_RestoreSaveBlock /
                                         ; Field_StashSaveBlock MVN count + 1)

; --- Interrupt trampolines ---
!Op_JML = $5C                            ; 65816 opcode JML long (written into the RAM trampolines)

; --- OAM shadow ranges (PostVBlank, FrameStateInit, Field_RestoreState) ---
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

; --- Field defaults (FrameStateInit) ---
!Fade_FixedColorInit = $E0               ; Fade_FixedColor at load: all colour channels, intensity 0
!Field_Unk28Init = $5F                   ; Field_Unk28 at load
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
!Field_ExitArgXMask = $003F              ; Field_ExitMenuArg bits 5-0 (handed over in X)
!Eng_Unk7F0000Min = $49                  ; Field_FadeToBankC2Mode5 runs only when Eng_Unk7F0000 >=
                                         ; this
!Pad_Start = $01                         ; Pad_Pressed bit 0: Start
!Pad_HiDown = $04                        ; high byte of Pad_Pressed, bit 2: Down
!Pad_HiUp = $08                          ; high byte of Pad_Pressed, bit 3: Up
!ExitMenu_Mode5 = $05                    ; BankC2_Entry8000 argument used by Field_RunBankC2Mode5
!ExitMenu_Mode6 = $06                    ; BankC2_Entry8000 argument when Field_ExitMenuArg bit 0 is
                                         ; clear

; --- Audio ---
!Audio_CmdPlaySfx = $19                  ; Audio_CmdId: play the sound effect in Audio_CmdArg0

; --- Generic ---
!Eng_LowByteMask = $00FF                 ; AND mask that zero-extends a byte in 16-bit A

; --- Tile animation modes (Field_SceneChangeTick dispatch on Map_TileProps) ---
!TileAnim_ModeE6 = $E6                   ; mode handled by ModeE6_Handler
!TileAnim_ModeEC = $EC                   ; mode handled by ModeEC_Handler
!TileAnim_ModeEE = $EE                   ; mode handled by ModeEE_Handler
!TileAnim_ModeFA = $FA                   ; mode handled by ModeFA_Handler
!TileAnim_ModeFC = $FC                   ; mode handled by ModeFC_Handler
!Obj_Unk1C00Init = $07                   ; value Evt_RunObjInit stores in Obj_Unk1C00 after the init
                                         ; function

; --- Pad ---
!Pad_Unk00F8Bit7 = $80                   ; Pad_Unk00F8 bit 7 (Sub_1ADF sets Field_Unk62 = 3 on it)
!Pad_Unk00F6Mode5 = $01                  ; Pad_Unk00F6 bit 0: run Field_FadeToBankC2Mode5
                                         ; (Field_PauseAndMenuInput)
!Pad_Unk00F6Menu = $40                   ; Pad_Unk00F6 bit 6: fade out and call BankC2_Entry8000 with
                                         ; 1 (Field_PauseAndMenuInput); X in the Pad_Pressed layout
!Pad_Unk00F6Bit7 = $80                   ; Pad_Unk00F6 bit 7: Sub_1ADF clears Field_Unk34 on it (A in
                                         ; the Pad_Pressed layout)

; --- Map / BG ---
!Map_RowStride = $0100                   ; Map_TileProps bytes per map row (index - $100 = the tile
                                         ; above)
!Bg_ColMask64 = $003F                    ; wraps an 8x8 tile column into a 64-wide tilemap
!Bg_RowMask32 = $001F                    ; wraps an 8x8 tile row into a 32-tall tilemap
!Bg_ScreenWidth = $0020                  ; tiles per row of one 32x32 tilemap screen
!Bg_ScreenWords = $0400                  ; words in one 32x32 tilemap screen (offset of the right-
                                         ; hand screen)
!TileAnim_StateFE = $FE                  ; Map_TileProps value DefaultHandler steps to $FF
                                         ; (TileAnim_StepKind 0)
!TileAnim_StateE0 = $E0                  ; Map_TileProps value DefaultHandler steps to $E1
                                         ; (TileAnim_StepKind 1)
!SceneFlag_Battle = $01                  ; Field_SceneFlags bit 0: start a battle (DefaultHandler
                                         ; JSLs EngCall_BattleMain)
!SceneFlag_TileStep = $02                ; Field_SceneFlags bit 1: step one tile (DefaultHandler)
!SceneFlag_MapRedraw = $20               ; Field_SceneFlags bit 5: redraw map layers per
                                         ; Field_MapRedrawSel (DefaultHandler)
!FadeFlag_AfterBattle = $01              ; Field_FadeFlags bit 0: set when DefaultHandler finishes
                                         ; the battle path
!VramQueue_TileStep = $02                ; Field_VramQueueFlags bit 1: TileAnim_StepVramAddrs ready
!VramQueue_TileAnim = $10                ; Field_VramQueueFlags bit 4: TileAnim_VramAddrs ready
!Field_Unk53Bit7 = $80                   ; Field_Unk53 bit 7, set around one VBlankHandlerShort
                                         ; before the battle (DefaultHandler)
!DP_Map = $1D00                          ; direct page of the map/BG routines (Field_BuildC800*,
                                         ; Field_FrameUpdate)

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
!DP_SprBufPage = $0B00                   ; direct page SprBuf_FreeAll points at to reach SprBuf_Owner
                                         ; with dp stores
!SprBuf_Tiles = $0060                    ; tiles in the WRAM tile buffer (96 x 32 bytes = $0C00)
!SprBuf_Bytes = $0C00                    ; bytes in the WRAM tile buffer
!SprBuf_VramWord = $0400                 ; VRAM word address the tile buffer is uploaded to
!Gfx_Tile4bppBytes = $0020               ; bytes in one 8x8 4bpp tile
!SprFrame_TileMask = $07FF               ; tile number bits of a frame-data tile word
!SprFrame_HFlip = $4000                  ; frame-data tile word bit 14: copy the tile mirrored
                                         ; (Spr_CopyTileFlipped)
!LargeObj_LayoutOfs = $00C0              ; offset of the 24 position byte pairs in a large object's
                                         ; frame data (after 96 tile words)
!Eng_SignExtNeg = $FF                    ; high byte that sign-extends a negative 8-bit value
!LargeObj_TileRow0 = $40                 ; OAM tile number of the first 16x16 tile in row 0 of a
                                         ; large object (tiles step by 2)
!LargeObj_TileRow1 = $60                 ; OAM tile number of the first 16x16 tile in row 1
!LargeObj_TileRow2 = $80                 ; OAM tile number of the first 16x16 tile in row 2
!LargeObj_Attr = $22                     ; OAM attributes of every large-object tile: priority 2,
                                         ; palette 1
!BankD2 = $D2                            ; ROM bank $D2 (object tile graphics)
!Eng_HighByteMask = $FF00                ; AND mask keeping the high byte of 16-bit A

; --- Object frame build ---
!Obj_VramTileMask = $01FF                ; tile-number bits of Obj_VramTile
!ObjTile_AltLayout = $68                 ; Obj_VramTile value that selects the alternate VRAM layout
                                         ; in the 12-tile builders
!Frame4_Bytes = $28                      ; bytes per frame record of a 4-tile object: 16 tile words +
                                         ; 4 position pairs
!Frame8_Bytes = $50                      ; bytes per frame record of an 8-tile object
!Frame12_Bytes = $78                     ; bytes per frame record of a 12-tile object
!Spr_UpperOfsY = $E8                     ; tiles with OfsY >= this (the upper 24 lines) take
                                         ; Obj_PrioHigh
!Anim_EndMarker = $FF                    ; frame-number table entry that ends an animation row
!ObjQ_Empty = $80                        ; ObjQ_Head/ObjQ_Tail/Obj_QueueNext value for "none"
!Vram_TileRowWords = $0100               ; VRAM words in one row of sixteen 8x8 tiles (the next row
                                         ; holds the lower halves of 16x16 sprites)
!Gfx_8TilesBytes = $0100                 ; bytes in eight 4bpp 8x8 tiles
!SprBuf_ChunkTiles = $0010               ; tiles in one $200-byte SprBuf chunk
!Frame_TileWordBytes = $02               ; bytes per tile word in a frame record (offsets are written
                                         ; as this x tile index)
!Spr_TileRowStep = $10                   ; OAM tile-number step to the next row of 16 tiles
!Ppu_FirstHiddenLine = $00F0             ; V counter of the first line below the visible screen (240)

endif
