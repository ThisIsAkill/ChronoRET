; ============================================================
; ram_battle.inc — Named WRAM / direct-page locations used by the
; battle engine (bank $C1). Same conventions as ram_engine.inc.
;
; Battler slots: 0-2 = party (PCs), 3-10 = enemies. Arrays indexed by
; battler slot are named !Battler_<Field>; arrays indexed by PC slot
; only are named !Pc_<Field>.
;
; Every name carries width, meaning and how it was inferred. "Unk"
; names mark locations whose purpose is not established; their comment
; says what the code was seen doing with them.
;
; Direct page $80-$A2 is per-routine scratch in this bank. It is named
; !BattleTmp_xx here; bank $C1 gives each slot a routine-specific alias
; next to the routine header (e.g. !BattleTgt_P0X = !BattleTmp_80).
;
; Tilemap buffers are named by cell: BattleUI_StatusTile(row, col) is
; the tile byte of the 2-byte entry at (row, col), ...Attr(row, col) its
; attribute byte. A row is $40 bytes (32 entries). Used with ,X/,Y the
; cell is relative to the index (Tile(0,1),Y = the entry after Y).
; ============================================================
!ram_battle_inc ?= 0
if !ram_battle_inc == 0
!ram_battle_inc = 1

; ------------------------------------------------------------
; Direct page: math helpers (Battle_Mul8 / Mul8x16 / Divide)
; ------------------------------------------------------------
!Battle_MulMirrorA       = $77   ; 1 B: copy of the WRMPYA operand (Mul8, Mul8x16 write it; no reader seen in $C1)
!Battle_MulMirrorB       = $78   ; 1 B: copy of the WRMPYB operand (Mul8, Mul8x16)
!Battle_DivMirrorLo      = $79   ; 1 B: copy of the dividend low byte (Battle_Divide)
!Battle_DivMirrorHi      = $7A   ; 1 B: copy of the dividend high byte (Battle_Divide)
!Battle_DivMirrorDivisor = $7B   ; 1 B: copy of the divisor (Battle_Divide)
!Battle_MulFactor8       = $A5   ; 1 B: 8-bit factor of Battle_Mul8x16 (WRMPYA); Battle_SinLookup also zeroes $A6
!Battle_MulFactor16      = $A7   ; 2 B: 16-bit factor of Battle_Mul8x16 ($A7 low, $A8 high, each fed to WRMPYB)
!Battle_MulProduct       = $A9   ; 3 B: 24-bit product of Battle_Mul8x16 ($A9 low .. $AB high)
!Battle_Mul8A            = $AD   ; 1 B: Battle_Mul8 multiplicand (callers zero $AE when they store it 16-bit)
!Battle_Mul8B            = $AE   ; 1 B: Battle_Mul8 multiplier
!Battle_Mul8Product      = $AF   ; 2 B: Battle_Mul8 16-bit product (RDMPYL)
!Battle_DivDividend      = $B1   ; 2 B: Battle_Divide 16-bit dividend
!Battle_DivDivisor       = $B3   ; 1 B: Battle_Divide 8-bit divisor ($B4 is zeroed by DrawSlotGaugeBar, unused by Divide)
!Battle_DivQuotient      = $B5   ; 2 B: Battle_Divide 16-bit quotient (RDDIVL)
!Battle_DivRemainder     = $B7   ; 2 B: Battle_Divide 16-bit remainder (RDMPYL)

; ------------------------------------------------------------
; Direct page: geometry (Battle_CalcAngle and its callers)
; ------------------------------------------------------------
!Battle_GeoOriginX       = $D3   ; 1 B: screen x of the point the angle is measured from
!Battle_GeoOriginY       = $D4   ; 1 B: screen y of that point
!Battle_GeoPointX        = $D5   ; 1 B: screen x of the point the angle is measured to
!Battle_GeoPointY        = $D6   ; 1 B: screen y of that point
!Battle_GeoDeltaX        = $D7   ; 2 B: signed OriginX - PointX (high byte = sign)
!Battle_GeoDeltaY        = $D9   ; 2 B: signed OriginY - PointY (high byte = sign)
!Battle_GeoAngle         = $DB   ; 1 B: result angle, 256 units per turn (also returned in A)
!Battle_GeoTmp           = $DC   ; 2 B: |dx| >> 3 while building the table index
!Battle_GeoAbsDeltaX     = $DE   ; 2 B: |dx| (high byte zeroed)
!Battle_GeoAbsDeltaY     = $E0   ; 2 B: |dy| (high byte zeroed)
!Battle_GeoAngleIndex    = $E2   ; 2 B: index into BattleRom_AngleTable: (|dy| & ~7) * 4 + (|dx| >> 3)

; ------------------------------------------------------------
; Direct page: battler frame decoder (Battle_DrawBattlerFrame)
; ------------------------------------------------------------
!BattleTmp_BA            = $BA   ; 3 B scratch: long pointer ($BA low .. $BC bank)
!BattleTmp_BD            = $BD   ; 2 B scratch

; ------------------------------------------------------------
; Direct page: other fixed roles
; ------------------------------------------------------------
!Battle_UnkA4            = $A4   ; 1 B: 1-3 = Battle_TickPcSlots ticks enemy group n (Battle_TickEnemyGroup) instead of
                                 ; the PCs; copied to !Battle_Unk993B around the tick and copied back if that changed it
                                 ; (BattleSys_UpkeepTwoFrames); set to 1 during each Battle_PoseStep; who sets it otherwise
                                 ; is not traced
!Battle_FramePending     = $9E   ; 1 B: set by BattleSys_PumpFrames, cleared by the interrupt handler at $CF:FB65 (reached
                                 ; through $C1:0000/$C1:001B; it saves every register, inferred: the battle NMI)
!Battle_ArgSlot          = $A1   ; 1 B: battler slot argument of the $C10045 services (Enqueue/RemoveBattlerFromReady; same-bank JSR only)
!Battle_UnkE5            = $E5   ; 1 B: zeroed by both menu dirty-flag gates before the menu rebuild; purpose unknown
!Battle_UnkEC            = $EC   ; 1 B: set when the single target cursor's OAM y is below $2D, cleared at $9C or above
                                 ;      (UpdateCursorOverlay, only right after the target moved); purpose unknown
!Battle_PadEdgeButtons   = $EE   ; 1 B: buttons pressed this frame (bit 7 confirm, 6 alt-confirm, 5/4 page, 3 cancel);
                                 ;      cleared by Battle_ClearPadEdges once consumed
!Battle_PadEdgeDpad      = $EF   ; 1 B: D-pad pressed this frame (bit 3 up, 2 down, 1 left, 0 right)

; ------------------------------------------------------------
; Direct page: per-routine scratch (aliased per routine in bankC1.asm)
; ------------------------------------------------------------
!BattleTmp_80            = $80   ; 1-2 B scratch
!BattleTmp_81            = $81   ; 1 B scratch
!BattleTmp_82            = $82   ; 1-2 B scratch
!BattleTmp_83            = $83   ; 1 B scratch
!BattleTmp_84            = $84   ; 1-2 B scratch
!BattleTmp_85            = $85   ; 1 B scratch
!BattleTmp_86            = $86   ; 1-2 B scratch
!BattleTmp_87            = $87   ; 1 B scratch
!BattleTmp_88            = $88   ; 1-2 B scratch
!BattleTmp_89            = $89   ; 1 B scratch
!BattleTmp_8A            = $8A   ; 1 B scratch
!BattleTmp_8B            = $8B   ; 1 B scratch
!BattleTmp_8C            = $8C   ; 1 B scratch
!BattleTmp_8D            = $8D   ; 1 B scratch
!BattleTmp_8E            = $8E   ; 1-2 B scratch
!BattleTmp_90            = $90   ; 1-2 B scratch
!BattleTmp_92            = $92   ; 1-2 B scratch
!BattleTmp_93            = $93   ; 1 B scratch
!BattleTmp_94            = $94   ; 1 B scratch
!BattleTmp_96            = $96   ; 2 B scratch
!BattleTmp_98            = $98   ; 2 B scratch
!BattleTmp_9A            = $9A   ; 2 B scratch
!BattleTmp_9C            = $9C   ; 2 B scratch
!BattleTmp_A2            = $A2   ; 2 B scratch
!BattleTmp_C0            = $C0   ; 3 B scratch (a long pointer in Battle_TickEnemyGroup)
!BattleTmp_C3            = $C3   ; 3 B scratch (a long pointer in Battle_TickEnemyGroup)
!BattleTmp_AD            = $AD   ; 2 B scratch outside Battle_Mul8 (same bytes as !Battle_Mul8A/B)
!BattleTmp_AF            = $AF   ; 2 B scratch outside Battle_Mul8 (same byte as !Battle_Mul8Product)

; ------------------------------------------------------------
; Absolute WRAM (bank $7E; DB=$7E in all bank $C1 code)
; ------------------------------------------------------------
!Battle_WramAbs          = $0000 ; base 0 for "STA abs,Y" where Y already holds the full address (left by MVN)
!Battle_DataBankAbs      = $0000 ; base 0 for "LDA abs,Y" in whatever bank DB holds, where Y is the full address
!Battle_WramLong         = $7E0000 ; base 0 of bank $7E for "STA long,X" where X is the full address

; Argument block for the info-panel message calls (UpdateCursorOverlay
; fills it before JSL BattleMsg_ShowMsg0BIfKeyChangedVec).
struct BattleMsg_InfoArgs $0200
.Id:        skip 1      ; +0: !Battler_Unk984D value of the highlighted target
.CurHp:     skip 2      ; +1: target's BattlerStats.CurHp
.MaxHp:     skip 2      ; +3: target's BattlerStats.MaxHp
endstruct

; OAM shadow, low table: 4 bytes per sprite. Sprites 0-3 are the menu
; and target cursors (DrawCursorSprites, UpdateCursorOverlay).
struct BattleOam $0700
.X:         skip 1      ; +0: x position (bit 8 lives in the high table)
.Y:         skip 1      ; +1: y position ($F0 = parked below the screen)
.Tile:      skip 1      ; +2: tile number
.Attr:      skip 1      ; +3: vhoopppN attribute byte
endstruct
!BattleOam_HighTable     = $0900 ; 1 B: OAM high-table byte for sprites 0-3 (2 bits each: x bit 8, size)

!BattleMenu_WindowMap    = $0B40 ; $180 B: command-window tilemap buffer, 6 rows x $40 (copied from ROM maps)

; Status-bar tilemap buffer at $0CC0 (6 rows x 32 entries, uploaded by
; Battle_QueueVramUpload_0CC0).
function BattleUI_StatusTile(row, col) = $0CC0+(row*$40)+(col*2)
function BattleUI_StatusAttr(row, col) = $0CC1+(row*$40)+(col*2)

; Item-list tilemap buffer at $0E80 (6 rows x 32 entries, uploaded by
; Battle_QueueVramUpload_0E80).
function BattleMenu_ItemTile(row, col) = $0E80+(row*$40)+(col*2)
function BattleMenu_ItemAttr(row, col) = $0E81+(row*$40)+(col*2)
!BattleMenu_UpArrowTile   = $0EFC ; 1 B: item-list scroll-up arrow tile (row 1, col 30); $FF = hidden
!BattleMenu_UpArrowAttr   = $0EFD ; 1 B: its attribute
!BattleMenu_DownArrowTile = $0FFC ; 1 B: item-list scroll-down arrow tile (row 5, col 30); $FF = hidden
!BattleMenu_DownArrowAttr = $0FFD ; 1 B: its attribute (vertically flipped up-arrow tile)

; Item list shown in the battle item menu: 5-byte records, record
; offset = list index * 5 (ItemConfirm, RenderItemRow).
struct Item_BattleList $1580
.Id:         skip 1     ; +0: item id (0 = empty)
.TargetMode: skip 1     ; +1: target mode copied to !BattleTgt_Mode on confirm
.Flags:      skip 1     ; +2: bit 7 set = cannot be used here (ItemConfirm aborts; drawn grey
                        ;     unless .PcMask has the active PC's bit)
.Quantity:   skip 1     ; +3: count held (0 = empty); decremented by CommitAction
.PcMask:     skip 1     ; +4: bit 7/6/5 = PC slot 0/1/2 may use it (tested with BattleRom_PcBit)
endstruct

; Tech menu entries: 7-byte records, 20 per PC (PC base from
; BattleRom_TechEntryBase = 0/$8C/$118, entry offset i*7 from
; BattleRom_TechEntryOffset). Read by UpdateTechWindow / UpdateTechMpAvail.
struct Tech_MenuEntry $1A80
.TechId:     skip 1     ; +0: tech id; $39 and up are double/triple techs (UpdateCursorOverlay)
.TargetMode: skip 1     ; +1: target mode copied to !BattleTgt_Mode on confirm (TechConfirm)
.Flags:      skip 1     ; +2: bit 7 = unusable now (set/cleared by UpdateTechMpAvail; TechConfirm aborts)
.MpCost0:    skip 1     ; +3: MP cost for PC slot 0 ($80+ = slot 0 not involved)
.Partners:   skip 1     ; +4: partner PC slots, low nibble first, high nibble second ($F = none; $FF = no partners)
.MpCost1:    skip 1     ; +5: MP cost for PC slot 1 ($80+ = not involved)
.MpCost2:    skip 1     ; +6: MP cost for PC slot 2 ($80+ = not involved)
endstruct

!Battle_Unk1C48          = $1C48 ; 1 B array indexed by !Battle_UnkA0FF; must equal $42 for tech id $74 to be usable
                                 ; (UpdateTechMpAvail); purpose unknown
!Battler_TileGfxPtr      = $1C57 ; 3 B per battler slot (index slot*3): long pointer to the battler's 32-byte tiles,
                                 ; which Battle_DrawBattlerFrame copies by tile number; who fills it is not traced
!Battler_FramesPtr       = $1C78 ; 3 B per battler slot (index slot*3): long pointer to the battler's frame records
                                 ; (BattleRom_FrameBytes bytes each); who fills it is not traced
!Battler_AnimFrameBase   = $1C99 ; 3 B per battler slot (index slot*3; low word used): offset in !BattleRom_AnimData of
                                 ; the battler's frame-id lists (Battle_TickPcSlots); who fills it is not traced
!Battler_AnimDurBase     = $1CBA ; 3 B per battler slot (same layout): offset of its frame-duration lists
!Tech_ListAvail          = $1CDB ; 20 B: per tech-list entry of the active PC, 1 = selectable, 0 = blank/header
                                 ; (BuildTechAvailFlags; TechListPrev/Next skip zeros)
!Battler_ScreenX         = $1D0C ; 11 B per battler slot: base screen x (cursor and area-target geometry)
!Battler_ScreenY         = $1D23 ; 11 B per battler slot: base screen y
!Sfx_Command             = $1E00 ; 1 B: APU command byte for Audio_ProcessEntry (same block bank $C0's Audio_PlayTileSfxA uses)
!Sfx_Param1              = $1E01 ; 1 B: first APU command parameter (sound id for command $19)
!Sfx_Param2              = $1E02 ; 1 B: second APU command parameter
!Battle_Unk2989          = $2989 ; 1 B: bit 7 set lets BattleSys_UpkeepTwoFrames act on !Battle_Unk99CF/99D0;
                                 ; purpose unknown (near the config bytes $2990/$2991)
!Pc_CharId               = $2980 ; 3 B per PC slot: character id (0-6) of the PC in that slot; inferred from the
                                 ; target modes that search it for ids 3-6. (The field engine uses $2980 for other
                                 ; data; see the wiki's RAM table.)

!Battle_PaletteSaved     = $2100 ; 16 B per !Battler_Palette unit: saved palette bytes that Battle_FxReset copies back over
                                 ; !Battle_PaletteLive (inferred: a palette buffer; 26 B are copied per PC)
!Battle_PaletteLive      = $2300 ; 16 B per !Battler_Palette unit: live palette bytes; the colour cycle at $CF:E80F and
                                 ; Battle_FxOverlay2Tint write colours here (inferred: what is shown)
!Battle_CellMap          = $7BFD ; 256 B: one byte per 16x16-pixel screen cell, 16 cells per row (index row*16 + col);
                                 ; bit 6 = blocks a battler box, bit 7 = blocks it unless !Battle_PassCellBit7 is
                                 ; set (Battle_BoxHitsBlockedCell). Who fills it is not traced

!Enemy_AnimWanted        = $5E0D ; 1 B per enemy (0-7): animation it should show; Battle_TickEnemyGroup reloads the lists
                                 ; when it differs from !Enemy_Anim. Lies in the first $30 bytes of BattlerStats[0],
                                 ; which the struct leaves unnamed; written by unmatched code ($C1:3793, $C1:8806, ...)

; Battle stat records, $80 bytes per battler slot (BattleRom_StatsOffset
; lists slot*$80 for all 11 slots).
struct BattlerStats $5E00
            skip $2F
.Unk2F:     skip 1      ; +$2F: bit 0 set = Battle_PickStatusAnim picks animation $12 and effect $80 when no status
                        ; record matches; meaning unknown
.CurHp:     skip 2      ; +$30: current HP
.MaxHp:     skip 2      ; +$32: max HP
.CurMp:     skip 2      ; +$34: current MP
            skip $14
.Status:    skip 1      ; +$4A: status bits; bit 7 set = KO'd (by context: BattleTgt_SingleKoAlly lists these)
.Status2:   skip 1      ; +$4B: more status bits; bit 1 set = Battle_UpdatePcFacing leaves the facing alone (meaning unknown)
endstruct align $80

; Per-PC command records, 7 bytes each, PC slot 0/1/2 at +0/+7/+14
; (offsets from BattleRom_CmdOffset).
struct BattleCmd $93EE
.State:     skip 1      ; +0: bit 7 = waiting for a command (EnqueueReadyBattler), bit 6 = command queued (CommitAction)
.Kind:      skip 1      ; +1: command kind ($80 attack, $40 item, $20 tech) ORed with !Battle_Unk9F38
.Menu:      skip 1      ; +2: menu it came from (0 attack, 1 tech, 2 item; from !BattleMenu_CmdMenu)
.Target:    skip 1      ; +3: first selected target slot
.Unk4:      skip 1      ; +4: not written by bank $C1 code seen so far
.Partners:  skip 1      ; +5: tech partner nibbles ($FF for attack/item)
.ActionId:  skip 1      ; +6: tech id or item id (left stale for attack)
endstruct

!Pc_NameTiles            = $9412 ; 10 B per PC slot (offset from BattleRom_PcNameOffset): 5 lower-row then 5 upper-row name tiles
!BattleMsg_NumValue      = $9499 ; 2 B: value to format (BattleMsg_FormatNumberDigits / BattleMsg_FormatTwoDigits)
!BattleMsg_Digit1000     = $949C ; 1 B: thousands digit tile (always blank, $FF)
!BattleMsg_Digit100      = $949D ; 1 B: hundreds digit tile
!BattleMsg_Digit10       = $949E ; 1 B: tens digit tile
!BattleMsg_Digit1        = $949F ; 1 B: ones digit tile
!BattleMsg_TextTiles     = $94A0 ; 16 B: re-encoded text, lower-row tiles (BattleMsg_ReencodeTextBuffer)
!BattleMsg_TextTopTiles  = $94B0 ; 16 B: re-encoded text, upper-row tiles ($71/$72 marks, $FF blank)
!BattleMsg_TextSource    = $94C0 ; 16 B: copy of the raw text taken before re-encoding
!Tech_ListCode           = $94D0 ; 20 B per PC (base BattleRom_TechListBase): tech-list line codes; $FB-$FF are
                                 ; special lines (see constants), anything else is a real entry
!Tech_ListEntry          = $9551 ; 20 B per PC: menu-entry index (into the PC's Tech_MenuEntry records) of each line
!BattleMenu_ActivePc     = $95D5 ; 1 B: PC slot whose command menu is shown; negative = none
!BattleMenu_ReadyQueue   = $95D6 ; 4 B: PC slots waiting for the menu, head first ($FF/negative = empty)
!BattleMenu_ReadyQueueLen = $95DA ; 1 B: entries in !BattleMenu_ReadyQueue
!BattleMenu_Submenu      = $95DB ; 1 B: open submenu: 0 main, 1 tech list, 2 item list
!Pc_MenuRow              = $95DC ; 3 B per PC: command-menu cursor row (0 attack, 1 tech, 2 item)
!Pc_TechRow              = $95DF ; 3 B per PC: tech-list cursor row on screen (0-2)
!BattleMenu_ItemRow      = $95E5 ; 1 B: item-list cursor row on screen (0-2)
!BattleMenu_ItemScroll   = $95E6 ; 1 B: item-list scroll position (first visible line, max $FA)
!Pc_TechScroll           = $95EB ; 3 B per PC: tech-list scroll position (first visible line)
!BattleUI_OtherReady     = $95F1 ; 1 B: !BattleMenu_ReadyCount - 1, latched by BuildStatusBarFrame (0 = only one PC ready)

; Target selection (BattleMenu_BuildTargetList, BattleTgt_*)
!BattleTgt_AreaSide      = $9604 ; 1 B: area scan side: 0 = enemies (slots 3-10), else PCs (0-2)
!BattleTgt_AreaCentre    = $9605 ; 1 B: area source / centre battler slot
!BattleTgt_AreaAim       = $9606 ; 1 B: aimed-at battler slot (line areas)
!BattleTgt_AreaSize      = $9607 ; 1 B: area size: line half-width / 8, or circle radius squared in 16-px cells
!BattleTgt_AreaVariant   = $9608 ; 1 B: line variant: 0 = band from the source, else box ending at the aimed-at battler
!BattleMenu_TargetSelect = $9609 ; 1 B: non-zero while target selection is running
!BattleTgt_CanCycle      = $960A ; 1 B: non-zero = the player may move the target cursor
!BattleTgt_SweepResume   = $960B ; 1 B: selection-list index the multi-target cursor sweep resumes from next frame
!BattleTgt_TargetAll     = $960C ; 1 B: bit 7 set = every listed candidate is selected
!BattleTgt_Mode          = $960D ; 1 B: target mode: low 7 bits index BattleTgt_ModeTable; bit 7 set = leave the
                                 ; submenu while targeting and return to it on cancel (BuildTargetList)
!BattleTgt_Unk960E       = $960E ; 1 B: cleared on target cancel/commit and battler removal; no reader in bank $C1 yet
!BattleTgt_Caster        = $960F ; 2 B: battler slot that requested the target list (the active PC)
!BattleTgt_Result        = $9613 ; 1 B: 0 = a target exists, negative = no valid target ($80 from the handlers, $FF from BuildTargetList)
!BattleTgt_Cursor        = $9614 ; 1 B: cursor index into !BattleTgt_Candidates
!BattleMenu_CmdMenu      = $9615 ; 1 B: menu the pending command comes from (0 attack, 1 tech, 2 item)
!Pc_AnimTimer            = $9689 ; 3 B per PC: frames left before the next animation step (Battle_TickPcSlots;
                                 ; reloaded with duration / 5)
!Battler_AnimFrame       = $968C ; 1 B per PC slot (3 B; enemies use !Enemy_AnimFrame): index of the current entry in
                                 ; its animation lists; $FF = start again at 0 on the next step
!Battler_FacingStrideLo  = $966E ; 1 B per battler slot: low byte of the size of one facing's frame-id list block
                                 ; (multiplied by !Battler_Facing); high byte in !Battler_FacingStrideHi
!Battle_FrameSlot        = $9679 ; 1 B: argument of Battle_DrawBattlerFrame: battler slot whose frame to decode
!Battle_FrameId          = $967B ; 1 B: argument of Battle_DrawBattlerFrame: frame number (record index in
                                 ; !Battler_FramesPtr); callers read it from tables such as $E4:0000 and $D1:5F42
!Battler_FrameLayout     = $967C ; 1 B per battler slot: frame layout 0-4 (shape of the frame in tiles; indexes
                                 ; BattleRom_FrameBytes / BattleRom_FrameLayout / BattleRom_FrameExtraCount)
!Battler_Facing          = $96DB ; 1 B per battler slot: facing, from !BattleRom_FacingByAngle (Battle_UpdatePcFacing);
                                 ; picks the frame-id list block. "Facing" is inferred from the angle lookup
!Enemy_AnimTimer         = $9694 ; 1 B per enemy (0-7): frames left before its next animation step (Battle_TickEnemyGroup;
                                 ; battle init at $CC:E2ED also writes it)
!Enemy_AnimFrame         = $969C ; 1 B per enemy: entry 0-3 of its lists in !Enemy_AnimTicks/Frames
!Enemy_FacingShown       = $96E9 ; 1 B per enemy: facing its lists were loaded for (Battle_TickEnemyGroup; read at $CF:E845)
!Battler_Present         = $96F5 ; 11 B per battler slot: non-zero = battler exists
!Battler_ScreenOffsetX   = $9708 ; 11 B per battler slot: added to !Battler_ScreenX for the live cursor x
!Battler_ScreenOffsetY   = $9713 ; 11 B per battler slot: added to !Battler_ScreenY for the live cursor y
!Battler_HalfWidth       = $971E ; 11 B per battler slot: box half-width; the box spans probe x +/- this
                                 ; (Battle_CalcBattlerBox); who sets it is not traced
!Battler_Height          = $9729 ; 11 B per battler slot: box height above the probe y (top = y - this)
!Battler_PathStep        = $9734 ; 11 B per battler slot: pixels BattlePos_PathClear advances the probe per step (its
                                 ; radius grows by this each pass); inferred: movement step; who sets it is not traced
!Battler_BoxLeft         = $975A ; 11 B per battler slot: box left edge, clamped at 0 (Battle_CalcBattlerBox)
!Battler_BoxTop          = $9765 ; 11 B per battler slot: box top edge, clamped at 0
!Battler_BoxRight        = $9770 ; 11 B per battler slot: box right edge, clamped at $FF
!Battler_BoxBottom       = $977B ; 11 B per battler slot: box bottom edge: probe y, + 8 unless !Battle_Unk2989 bit 2
!Enemy_Anim              = $974A ; 1 B per enemy: animation its lists were loaded for (Battle_TickEnemyGroup; battle init
                                 ; $CC:E34E writes it); also selects the handler at $C1:375C
!Enemy_AnimTicks         = $9799 ; 8 B per enemy (index enemy * 8): frames per list entry, 0 = end of the list
!Enemy_AnimFrames        = $97D9 ; 8 B per enemy: frame id per list entry (!Battle_FrameId)
!Enemy_Unk9829           = $9829 ; 1 B per enemy: cleared when a kind-1 list is loaded (and at $C1:3796); also
                                 ; incremented by the unmatched code from $C1:3833 on; meaning unknown
!Battle_EnemyTickIdx     = $9841 ; 1 B: index into !Battle_TickOrder in Battle_TickEnemyGroup
!Battler_Unk984D         = $984D ; 2 B per battler slot (index slot*2): sent as the info-panel message id and used to
                                 ; index BattleRom_UnkE1DE80; inferred: per-battler type id. Unconfirmed.
; Position queries (service 5 of the $C10045 API, BattlePos_Query)
!BattlePos_Mode          = $986E ; 1 B in: query, 0-14 (index into BattlePos_ModeTable)
!BattlePos_Subject       = $986F ; 1 B in: battler slot the query is about
!BattlePos_Other         = $9870 ; 1 B in: second battler slot; the nearest/farthest scans overwrite it with each
                                 ; battler they examine
!BattlePos_Arg           = $9871 ; 1 B in: query 8: non-zero = also test other battlers' boxes; query 13: a third
                                 ; battler slot
!BattlePos_Result        = $9872 ; 1 B out: 0 = the condition holds, $FF = it does not (cleared by BattlePos_Query)
!BattlePos_Found         = $9873 ; 1 B out: slot found by queries 0-3 (they store 16-bit, so $9874 gets 0 too);
                                 ; query 13 stores a distance difference here
!Battle_PassCellBit7     = $9875 ; 1 B: non-zero = !Battle_CellMap bit 7 does not block (Battle_BoxHitsBlockedCell);
                                 ; zeroed before each check, set to 1 by the mover at $C1:3877 when $A2B5 is 3
!BattlePos_DistLimit     = $9893 ; 2 B: squared-distance limit of the BattlePos_WithinDist* checks (set by each entry)
!Enemy_NameLineUsed      = $98CC ; 3 B: non-zero = enemy-name line 0-2 of the status bar is in use
!Battler_FrameShown      = $9907 ; 1 B per battler slot: frame number last decoded (Battle_DrawBattlerFrame skips a repeat)
!Battle_FramesDecoded    = $9912 ; 1 B: frames decoded this pass; zeroed by Battle_TickPcSlots, and callers defer a battler
                                 ; (!Battler_FrameDeferred) once it is 1 (inferred: one decode per frame)
!Pc_SavedMenuRow         = $9916 ; 3 B per PC: command-menu row to restore when the PC's turn comes back
!Battler_FrameDeferred   = $9922 ; 1 B per battler slot: non-zero = its frame decode was put off; cleared when a decode
                                 ; starts (inferred: Battle_TickPcSlots starts with a deferred PC)
!BattleMenu_ItemRowDrawn = $991F ; 1 B: item cursor row last drawn ($FF = redraw)
!BattleMenu_ItemScrollDrawn = $9920 ; 1 B: item scroll position the arrows were last drawn for ($FF = redraw)
!Battle_TickOrder        = $992D ; 3 B: PC slots (Battle_TickPcSlots) or enemies (Battle_TickEnemyGroup; $FF = none)
                                 ; in the order this pass visits them
!BattleMenu_Dirty        = $993A ; 1 B: non-zero = rebuild the menu this frame (RefreshIfDirty gates)
!Battler_Palette         = $993C ; 1 B per battler slot: palette number; * 16 = offset in !Battle_PaletteSaved/Live
                                 ; (Battle_FxReset); 8 = none to the colour cycle at $CF:E802
!Battle_Unk993B          = $993B ; 1 B: copy of !Battle_UnkA4 (see there); also compared with it by Battle_TickEnemyGroup
!BattleTgt_Candidates    = $99C0 ; 12 B: candidate battler slots ($FF = empty); 11 used, cleared through index 11
!BattleTgt_AreaType      = $99CC ; 1 B: area shape for service 7 (index into BattleTgt_AreaTable, 0-6)
!Battle_Unk99CF          = $99CF ; 1 B: with !Battle_Unk99D0: either non-zero (and !Battle_Unk2989 bit 7) makes
                                 ; BattleSys_UpkeepTwoFrames clear both and show info message $75 once; purpose unknown
!Battle_Unk99D0          = $99D0 ; 1 B: see !Battle_Unk99CF
!Battle_Unk99D1          = $99D1 ; 1 B: latch: set when that message has been shown, so it is shown once
!Battle_CmdQueue         = $99D4 ; 4 B: PC slots with a committed command, in commit order
!Battle_CmdQueueLen      = $99D8 ; 1 B: entries in !Battle_CmdQueue
!Battle_StatusAnimNext   = $99D9 ; 1 B: battler slot Battle_PickNextStatusAnim picks next (3-10 after the first pass;
                                 ; battle init at $CC:E384 also writes it)
!Pc_FacingTarget         = $99DA ; 3 B per PC: enemy slot the PC last turned toward (Battle_UpdatePcFacing)
!Pc_AtbCur               = $99DD ; 3 B per PC: ATB gauge value
!Battle_MenuTimeHold     = $99E0 ; 1 B: = !Battle_CfgBattleMode while a tech/item list is open, 0 on the main menu;
                                 ; inferred: holds the battle clock in Wait mode
!Battle_CfgBattleMode    = $99E1 ; 1 B: battle-mode setting copied into !Battle_MenuTimeHold (inferred Active/Wait)
!BattleMenu_WindowMapDirty = $99E2 ; 1 B: incremented after !BattleMenu_WindowMap changes (upload request, inferred)

; Tech-list text buffer at $99E3 (same layout as the tech window map,
; tile/attr pairs; BattleMenu_RenderTechRow writes it, UpdateTechWindow
; copies its tile bytes to the window).
function BattleMenu_TechTextTile(row, col) = $99E3+(row*$40)+(col*2)
function BattleMenu_TechTextAttr(row, col) = $99E4+(row*$40)+(col*2)

; Copy of the Tech_MenuEntry under the tech cursor (UpdateTechWindow).
struct Tech_CursorEntry $9EE3
.TechId:     skip 1     ; +0
.TargetMode: skip 1     ; +1
.Flags:      skip 1     ; +2
.MpCost0:    skip 1     ; +3
.Partners:   skip 1     ; +4 ($FF also written when no entry is under the cursor)
.MpCost1:    skip 1     ; +5
.MpCost2:    skip 1     ; +6
endstruct

!BattleUI_GaugeLayout    = $9F20 ; 1-2 B: status-bar layout: 0 = name, HP/MaxHP, MP; 1 = HP, MP, name, ATB gauge;
                                 ; 2 = name, HP, MP, ATB gauge (1 and 2 differ in the name's side)
!Pc_AtbMax               = $9F22 ; 3 B per PC: ATB gauge full value (divisor in DrawSlotGaugeBar)
!Pc_Unk9F25              = $9F25 ; 3 B per PC: ORed with !Pc_Unk9F28; both zero = never the Combo command list (DrawCommandList)
!Pc_Unk9F28              = $9F28 ; 3 B per PC: see !Pc_Unk9F25
!Battler_Unk9F29         = $9F29 ; 1 B per battler slot: non-zero (with !Battle_Unk9F34) = the target info panel also
                                 ; gets the target's HP (UpdateCursorOverlay)
!Battle_Unk9F34          = $9F34 ; 1 B: enables the !Battler_Unk9F29 check above
!BattleMenu_ItemId       = $9F35 ; 1 B: item id chosen in the item list
!BattleMenu_ItemRecord   = $9F36 ; 2 B: Item_BattleList record offset of the chosen item
!Battle_Unk9F38          = $9F38 ; 1 B per PC: ORed into BattleCmd.Kind; cleared when the PC's menu opens
!BattleMenu_CursorPalette = $9F46 ; 1 B: palette bits merged into the cursor sprite attribute (flash cycle, inferred)
!Battler_FrameExtra      = $9F47 ; 16 B per battler slot (offset BattleRom_SlotTimes16): the signed bytes after the
                                 ; frame's tilemap, sign-extended to words; meaning not traced. Layouts 1-4 write
                                 ; more than 16 B, running into the next slots' blocks (as found)
!Battler_Unk9FF7         = $9FF7 ; 1 B per battler slot: bit 7 set = skipped by every target scan; meaning unknown
!Battle_DivBusy          = $A029 ; 1 B: non-zero while Battle_Divide runs
!Pc_TechCount            = $A02A ; 3 B per PC: number of lines in the PC's tech list
!Battler_ProbeX          = $A039 ; 11 B per battler slot: x the box and distance checks use; a copy of !Battler_ScreenX
                                 ; (Battle_CacheBattlerCoordsAll), moved ahead by path checks before the real move
                                 ; (inferred from the movers at $C1:3851 and BattlePos_PathClear)
!Battler_ProbeY          = $A050 ; 11 B per battler slot: y counterpart of !Battler_ProbeX
!Battle_FacingTurn       = $A098 ; 1 B: PC slot whose facing Battle_UpdatePcFacing updates next; bit 7 = handed on,
                                 ; not taken yet (inferred from the code; who else writes it is not traced)
!BattleMenu_TechAvailDone = $A099 ; 1 B: set once UpdateTechMpAvail has graded the visible rows; TechConfirm needs it
!BattleUI_ForceDigitRefresh      = $A09A ; 1 B: non-zero = BattleUI_UpdateNextPcPanel always refreshes HP/MP digits (no gauges-only
                                 ; shortcut); set when targeting starts from a submenu (BuildTargetList), cleared on return
!Battler_Untargetable    = $A09B ; 1 B per battler slot: non-zero = never offered as a target (inferred: hidden)
!BattleMenu_Lock         = $A0A7 ; 1 B: non-zero blocks the item list; bit 0 also blocks the tech list
!Battler_KoFlag          = $A0A8 ; 1 B per battler slot: non-zero = only target mode $04 may pick it (inferred: KO'd)
!BattleMenu_ItemRefresh  = $A0D0 ; 1 B: non-zero = re-render the item list (ItemListInput)
!Pc_LockStatus           = $A0D1 ; 1 B per PC: non-zero = PC can't join techs (inferred: Lock status)
!BattleMenu_CfgCursorMemory = $A0D4 ; 1 B: config: non-zero = keep each PC's command-menu row between turns (inferred:
                                 ; battle init $CC:E39C copies it from config byte $2991 bit 6)
!BattleMenu_CfgListMemory = $A0D5 ; 1 B: config: non-zero = keep tech/item list cursor positions between turns (inferred:
                                 ; battle init $CC:E3A4 copies it from config byte $2991 bit 7)
!BattleUI_UnkA0D7        = $A0D7 ; 1 B: compared with !BattleTgt_Selected by BuildStatusBarFrame; ConfirmCommand
                                 ; sets $FF; purpose unknown
!Pc_SavedTech            = $A0D8 ; 3 B per PC: tech id under the cursor at commit (with CfgListMemory)
!BattleMenu_CfgInfoPanel = $A0DB ; 1 B: config: bit 7 = show the tech/item info panel (battle init $CC:E3AC copies $2990 bit 7)
!Battle_UnkA0FD          = $A0FD ; 1 B: zeroed by BattleSys_UpkeepTwoFrames unless !Battle_UnkA10E is set; purpose unknown
!Battle_UnkA0FF          = $A0FF ; 2 B: index into !Battle_Unk1C48; purpose unknown
!Battle_StatusAnimWraps  = $A102 ; 1 B: counts Battle_PickNextStatusAnim's wraps past slot 10 ($C1:4124 zeroes it and
                                 ; waits for 1)
!Battler_AnimShown       = $A103 ; 1 B per battler slot: animation id last drawn (Battle_TickPcSlots)
!Battle_UnkA10E          = $A10E ; 1 B: non-zero skips the message check in BattleSys_UpkeepTwoFrames; purpose unknown
!BattleUI_LowHp          = $A10F ; 1-2 B: non-zero while drawing a PC whose HP is 0, or 1..MaxHP/8 with !BattleUI_UnkA110 set
!BattleUI_UnkA110        = $A110 ; 1-2 B: non-zero lets HP 1..MaxHP/8 count as low (HP 0 always does); otherwise unknown
!BattleMenu_KeepRow      = $A114 ; 1 B: set by alt-confirm; CommitAction then keeps !Pc_SavedMenuRow
!BattleUI_UnkA115        = $A115 ; 1-2 B: PC slot compared with the drawn slot in DrawCommandList; purpose unknown
!BattleUI_UnkA117        = $A117 ; 1 B: zero lets DrawCommandList show the Combo list without the A115 test; purpose unknown
!Battler_UnkA119         = $A119 ; 1 B per battler slot: non-zero = Battle_PickStatusAnim treats the battler as KO'd
                                 ; (first record forced, !Battler_KoFlag set); written at $C1:4153/$C1:4204; meaning unknown
!Battle_AnimFrameList    = $A1E8 ; 2 B: offset in !BattleRom_AnimData of the frame-id list being stepped
!Battle_AnimDurList      = $A1FE ; 2 B: offset of the frame-duration list being stepped
!Battler_FacingStrideHi  = $A2C8 ; 1 B per battler slot: high byte for !Battler_FacingStrideLo
!BattleUI_PanelRedraw    = $A43F ; 1 B: non-zero = redraw the command cursor column (ClearActivePanelColumn)
!Battle_AnimId           = $A440 ; 1 B: animation picked for the battler being ticked (Battle_PickStatusAnim; 3 =
                                 ; default, $2B replaces it while !Battle_Unk99CF/99D0 is set)
!Battler_FxWanted        = $A441 ; 1 B per battler slot: status effect picked by Battle_PickStatusAnim (0-$0E, index
                                 ; into Battle_FxHandlerTable; $FF none, $80 the Unk2F path); also indexes the colour table
                                 ; at $CC:F754 for the cycle at $CF:E7EC
!Battler_FxApplied       = $A44C ; 1 B per battler slot: effect Battle_ApplyPendingEffect last started; battle init
                                 ; ($CC:E369) and $CC:F106 also write it
!Battler_UnkA457         = $A457 ; 1 B per battler slot: cleared by Battle_FxReset; no other access found in banks
                                 ; $C1/$CC/$CD/$CF
!Battler_FxCycleOn       = $A46D ; 1 B per battler slot: non-zero = run the colour cycle ($CF:E7E0; Battle_FxColourCycle)
!Battler_FxTinted        = $A478 ; 1 B per battler slot: set by Battle_FxOverlay2Tint, cleared by Battle_FxReset; no
                                 ; reader found
!Battler_UnkA483         = $A483 ; 1 B per battler slot: cleared by Battle_FxReset; no other access found
!Battler_FxOverlayOn     = $A48E ; 1 B per battler slot: non-zero = draw the status overlay ($CF:EE38)
!Battler_FxCycleStep     = $A499 ; 1 B per battler slot: colour-cycle position; $CF:E821 adds 2 and wraps at $7C
!Battler_FxOverlayTimer  = $A4BA ; 1 B per battler slot: frames until the overlay's next frame ($CF:EE47)
!Battler_FxOverlayPeriod = $A4C5 ; 1 B per battler slot: reload value of !Battler_FxOverlayTimer
!Battler_FxOverlayBase   = $A4D0 ; 1 B per battler slot: overlay block * $10, added to frame * 4 to index $CC:F6D4
!Battler_FxOverlayFrame  = $A4DB ; 1 B per battler slot: overlay frame 0-3 ($FF = before the first; $CF:EE52 counts it)
!Battler_StartFrame      = $A4DC ; 1 B per battler slot: frame drawn by Battle_DrawAllBattlerFrames (battle init writes it
                                 ; at $CC:E968/$CC:EAA1). Lies inside !Battler_FxOverlayFrame, one slot up; the overlay
                                 ; handlers run only after the start frames are drawn (inferred)
!BattleMenu_TargetMoved  = $A4EE ; 1 B: set when a target list opens or the cursor moves (UpdateCursorOverlay)
!Battler_UnkA5CD         = $A5CD ; 1 B per battler slot: bit 7 set = ignored by Battle_BoxOverlapsOthers; meaning unknown
!BattleTgt_Selected      = $A62D ; 12 B: selected battler slots ($FF = empty); +0 is the command's target
!BattleTgt_Highlight     = $A64E ; 1 B: battler slot under the single-target cursor
!BattleTgt_UnkA64F       = $A64F ; 1 B: cleared by BuildTargetList; no reader in bank $C1 yet
!BattleTgt_UnkA6D8       = $A6D8 ; 1 B: cleared by BuildTargetList; no reader in bank $C1 yet
!BattleMenu_Roster       = $A6D9 ; 3 B: ready PCs; entry i = slot i when PC i waits for a command, negative = not
!BattleMenu_RosterIdx    = $A6DD ; 1 B: roster entry whose menu is shown (negative = none)
!BattleMenu_ReadyCount   = $A6DE ; 1 B: PCs in the roster
!BattleMenu_RosterIdxDrawn = $A6DF ; 1 B: !BattleMenu_RosterIdx the window was last built for ($FE/$FF = rebuild)
!BattleUI_NextPanelSlot  = $A6E0 ; 1 B: PC slot UpdateNextPcPanel refreshes this frame (round robin 0-2)

; Tech window tilemap buffer at $A6E1 (6 rows x 32 entries, uploaded by
; Battle_QueueVramUpload_A6E1).
function BattleMenu_TechTile(row, col) = $A6E1+(row*$40)+(col*2)
function BattleMenu_TechAttr(row, col) = $A6E2+(row*$40)+(col*2)

!BattleMenu_UnkA862      = $A862 ; 1 B: non-zero makes ProcessInput confirm at once; OpenTechList sets it only around
                                 ; its list rendering; purpose unknown
!Pc_SavedTechRow         = $A863 ; 3 B per PC: !Pc_TechRow to restore when the tech list reopens
!Pc_SavedTechScroll      = $A866 ; 3 B per PC: !Pc_TechScroll to restore
!BattleMenu_UnkA869      = $A869 ; 1 B: cleared whenever the tech list (re)opens; no reader in bank $C1 yet
!BattleMenu_TechWindowNew = $A86A ; 1 B: non-zero = copy the tech box frame into !BattleMenu_WindowMap once
!BattleMenu_ReturnSubmenu = $A86B ; 1 B: submenu + 1 to return to when targeting is cancelled (0 = main menu)
!Enemy_NameTiles         = $ACBC ; 24 B per enemy-name line: 11 lower-row tiles, 1 gap byte, 11 upper-row tiles

; ------------------------------------------------------------
; Banks and ROM data read by bank $C1
; ------------------------------------------------------------
!Battle_WramBank           = $7E      ; WRAM bank (MVN destination)
!BattleRom_TextBank        = $CC      ; bank holding the item/tech name tables (MVN source)
!BattleRom_AngleTable      = $C0F300  ; direction angle by (|dy| & ~7) * 4 + |dx| >> 3 (Battle_CalcAngle)
!BattleRom_SineTable       = $C0F900  ; |sin| table: 1024 entries of 1 B per turn, peak $FF at +$100 (Battle_SinLookup)
!BattleRom_FacingByAngle  = $C0F700  ; 1 B per angle (256 per turn): facing for that direction (Battle_UpdatePcFacing)
!BattleRom_TechListBase    = $CCF38C  ; 1 B per PC slot: first line of the PC in the 20-line tech lists (0/$14/$28)
!BattleRom_TechEntryBase   = $CCF395  ; 2 B per PC slot: offset of the PC's Tech_MenuEntry block (0/$8C/$118)
!BattleRom_TechRowMapOffset = $CCF39B ; 2 B per visible tech row: offset of the row in the tech window map
!BattleRom_TechEntryOffset = $CCF3A1  ; 1 B per menu-entry index: index * 7
struct BattleRom_FrameLayout $CCF3B6 ; 14 B per frame layout (0-5), index layout * 14 (Battle_DrawBattlerFrame)
.RowOffset: skip 12     ; +0: 6 words: offset of each tile row in the battler's tile buffer (only Height used)
.Width:     skip 1      ; +12: tiles per row
.Height:    skip 1      ; +13: rows
endstruct
!BattleRom_FrameBytes      = $CCF40A  ; 2 B per frame layout 0-4: bytes per frame record (2 B per tile cell + 1 B per two cells)
!BattleRom_FrameExtraCount = $CCF4FC  ; 1 B per frame layout 0-4: signed bytes after the frame's tilemap (cells / 2)
!BattleRom_FxOverlayPeriod = $CCF5FD ; 1 B per overlay block 1-7 (entry n-1): frames per overlay frame
struct BattleRom_CursorSprite $CCF604 ; command cursor, 4 sprites x 4 B
.X:         skip 1      ; +0: x offset from !Battler_ScreenX
.Y:         skip 1      ; +1: y offset from !Battler_ScreenY
.Tile:      skip 1      ; +2: tile
.Attr:      skip 1      ; +3: attribute (palette replaced by !BattleMenu_CursorPalette)
endstruct
!BattleRom_FxTintColours  = $CCF77B  ; 4 B: written into live palette bytes 6-9 by Battle_FxOverlay2Tint (inferred: two colours)
struct BattleRom_StatusAnim $CCF77F ; 4 B per record, ended by a negative .StatusByte (Battle_PickStatusAnim)
.StatusByte: skip 1    ; +0: byte to test, as an offset from BattlerStats.Status; negative = end of table
.Mask:     skip 1      ; +1: bits to test
.Effect:   skip 1      ; +2: status effect id (Battle_FxHandlerTable index); negative = none
.Anim:     skip 1      ; +3: animation id; $FF = none of its own
endstruct
!BattleRom_EnemyListOffset = $CCF82F ; 1 B per enemy: enemy * 8, its block in !Enemy_AnimTicks/Frames
!BattleRom_PcNameOffset    = $CCF837  ; 1 B per PC slot: offset of the PC in !Pc_NameTiles (0/10/20)
!BattleRom_StatsOffset     = $CCF8ED  ; 2 B per battler slot: slot * $80, offset of its BattlerStats record
!BattleRom_SlotTimes16     = $CCF917  ; 2 B per battler slot: slot * $10, offset of its !Battler_FrameExtra block
!BattleRom_SlotTimes3      = $CCF92D  ; 1 B per battler slot: slot * 3, offset into the 3-byte pointer arrays
!BattleRom_FrameDestBase   = $CCF941  ; 2 B per battler slot: bank $7E address its decoded frame tiles go to
                                      ; ($64AD, $67AD, $68AD, ...); what reads that buffer is not traced
!BattleRom_DigitTiles      = $CCF903  ; 10 B: tile for digits 0-9 ($73-$7C)
!BattleRom_PcBit           = $CCF9FB  ; 1 B per PC slot: $80/$40/$20, the PC's bit in Item_BattleList.PcMask
!BattleRom_NameAttrL1    = $CCFA23  ; 2 B per PC slot: map offset of the PC's name block's first attribute byte, layout 1
!BattleRom_NameAttrL02   = $CCFA29  ; 2 B per PC slot: same for layouts 0 and 2 (BattleUI_HighlightPcName)
!BattleRom_HpCellL0        = $CCFA2F  ; 2 B per PC slot: map offset of the HP digits, layout 0
!BattleRom_HpCellL1        = $CCFA35  ; 2 B per PC slot: same, layout 1 (also the gauge base for every layout)
!BattleRom_HpCellL2        = $CCFA3B  ; 2 B per PC slot: same, layout 2
!BattleRom_CmdListTech      = $CCFA41  ; 42 B: 6x7 command-list tiles: Attack / Tech / Item (rows 1, 3, 5)
!BattleRom_CmdListCombo      = $CCFA6B  ; 42 B: same with Combo in place of Tech (text "Comb")
!BattleRom_TechBorder      = $CCFA95  ; 54 B: 6x9 tiles of the tech window's right part (row 0 holds "MP")
!BattleRom_MenuCursorCell  = $CCFADD  ; 2 B per command row: map offset of the command cursor
!BattleRom_TechCursorCell  = $CCFAE3  ; 2 B per tech row: map offset of the tech cursor
!BattleRom_ItemCursorCell  = $CCFAE9  ; 2 B per item row: map offset of the item cursor
!BattleRom_CmdOffset       = $CCFAF0  ; 1 B per battler slot: offset of its BattleCmd record (PCs 0/7/14)
!BattleRom_TechFixedText   = $CCFB4B  ; 2 x 18 B: "Double Technique" and "Triple Technique" header lines, each between
                                 ; end glyphs $5B and $5C
!BattleRom_Squares         = $CCFB6F  ; 16 B: n*n for n = 0-15 (BattleTgt_AreaCircle)
!BattleRom_OamShowMask     = $CCFB8D  ; 4 B: high-table mask clearing x bit 8 of cursor sprite 0-3
!BattleRom_EnemyAnimKind  = $CCFB91  ; 1 B per enemy animation id (0-8 seen): which list block Battle_TickEnemyGroup loads
                                      ; (0 = list 3, 1 = list 1, else list 6); meaning unknown
!BattleRom_Div5           = $CCFBCE  ; 1 B per n: n / 5 (checked for the first 32 bytes); duration byte -> frames
!BattleRom_CommandWindowMap = $D15800 ; $180 B: command window tilemap
!BattleRom_CommandWindowFrame     = $D159FC  ; 84 B: one 7x6 command-window frame, 2 B (tile, attribute) per cell
!BattleRom_TechBoxMap      = $D15A50  ; $180 B: tech window frame tilemap
!BattleRom_ItemBoxMap      = $D15BD0  ; $180 B: item window frame tilemap
!BattleRom_AnimData       = $E40000  ; bank $E4 (the engine's !AnimRom): battler frame-id and frame-duration lists;
                                      ; a duration of 0 ends a list
!BattleRom_UnkE1DE80       = $E1DE80  ; 1 B per !Battler_Unk984D value: non-zero = send $FF instead of the target slot
                                      ; to the info-panel message call; purpose unknown

endif
