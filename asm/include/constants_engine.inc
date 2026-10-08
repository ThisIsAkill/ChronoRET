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
!Bank7F = $7F                            ; WRAM bank $7F (PHA/PLB, DmaFill_Bank)

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
!Oam_HiddenY = $E0                       ; sprite Y that parks an entry below the visible screen
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

endif
