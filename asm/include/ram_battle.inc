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
!BattleCF_SinScale       = $00   ; 1 B: scale (radius) multiplied into the sine by Battle_SinLookupCF (bank $CF's own slot)
!BattleCF_SinFactor16    = $02   ; 2 B: signed sine fed to WRMPYB a byte at a time by Battle_SinLookupCF
!BattleCF_SinProduct     = $04   ; 3 B: 24-bit product of Battle_SinLookupCF ($04 low .. $06 high)
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
!Battle_FramePending     = $9E   ; 1 B: set by BattleSys_PumpFrames, which waits for it to clear; likely cleared once a frame by
                                 ; the STZ $9E at $CF:E77B, before the RTL of a bank-$CF routine that reads JOY1 and bumps the
                                 ; 32-bit counter at $96F1 (entry not traced); also zeroed once by the battle entry $CF:FB65
!Battle_ArgSlot          = $A1   ; 1 B: battler slot argument of the $C10045 services (Enqueue/RemoveBattlerFromReady; same-bank JSR only)
!Battle_UnkE5            = $E5   ; 1 B: zeroed by both menu dirty-flag gates before the menu rebuild; purpose unknown
                                 ; Battle_PoseStep, which steps only when it finds 1 (every second frame); purpose unknown
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
                                 ; (UpdateTechMpAvail); BattleAct_LoadAttack reads the byte at PC slot * 5 as the PC's
                                 ; attack record number; purpose unknown
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
!Battle_PathMap          = $7CFD ; 256 B: copy of !Battle_CellMap with $40 in each battler's cell (Battle_BuildOccupiedCellMap,
                                 ; $CC:F110); BattleAct_FindPath labels it with wave numbers and marks the path ($E0 bits)
!Battle_PathFrontier     = $7DFD ; up to 256 B: BattleAct_FindPath's cells to expand this wave, 0-ended
!Battle_PathNextFrontier = $7EFD ; up to 256 B: the cells found in this wave, 0-ended, copied to !Battle_PathFrontier
!Battle_PathStartCell    = $A513 ; 1 B: start cell of the last BattleAct_FindPath (also read by BattleAct_PathToPoint)
!Battle_PathGoalCell     = $A515 ; 1 B: goal cell of the last BattleAct_FindPath; no reader found

!Pc_PoseTimer            = $5DBD ; 1 B per PC: pose steps until the next entry (Battle_PoseStep); the same bytes are
                                 ; !Battle_ActThreadPtr while an action plays
!Pc_PoseEntry            = $5DC1 ; 1 B per PC: current entry 0-7 of its pose list ($FF = before the first)
!Battle_PoseSlot         = $5DC5 ; 2 B: PC slot Battle_PoseStep is on (zeroed 16-bit, counted 8-bit)
!Battle_PoseFramesLeft   = $5DC9 ; 1 B: frames left in Battle_RunPcPose's loop
!Battle_PoseUnk5DDD      = $5DDD ; 1 B: 1 for the battle-start pose, 0 for services 8/9; Battle_PoseStep tests it with no
                                 ; effect (both branches meet)
!Battle_PoseIncludeKo    = $5DDE ; 1 B: non-zero = Battle_PoseStep also animates KO'd PCs (service 9 only)
!Pc_PoseListOfs          = $5DF1 ; 2 B per PC: animation * 4, offset of the PC's pose list in its bank $E4 lists
!Enemy_AnimWanted        = $5E0D ; 1 B per enemy (0-7): animation it should show; Battle_TickEnemyGroup reloads the lists
                                 ; when it differs from !Enemy_Anim. Lies in the first $30 bytes of BattlerStats[0],
                                 ; which the struct leaves unnamed; written by unmatched code ($C1:8806, ...) and by
                                 ; Battle_MoverIdle (from !Enemy_ResumeAnim)
!Enemy_TargetWanted      = $5E15 ; 1 B per enemy: battler slot the enemy should move relative to; Battle_RunEnemyMover
                                 ; copies it into !Enemy_MoveTarget. Same unnamed area as !Enemy_AnimWanted; no
                                 ; absolute write to it found, so who sets it is not traced
!Enemy_ResumeAnim        = $5E1D ; 1 B per enemy: !Enemy_AnimWanted saved when a move ends (the movers' "done" paths);
                                 ; Battle_MoverIdle puts it back once the target has moved away (same unnamed area)

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

!Pc_PoseTicks            = $922D ; 8 B per PC (24 B): pose steps per entry, halved durations (Battle_RunPcPose); the
                                 ; same bytes hold the hit-number sprites (Battle_HitNumSprite, opcodes $50-$55)
!Pc_PoseFrames           = $9245 ; 8 B per PC: frame id per pose entry (Battle_RunPcPose)
!Pc_NameTiles            = $9412 ; 10 B per PC slot (offset from BattleRom_PcNameOffset): 5 lower-row then 5 upper-row name tiles
!BattleMsg_NumValue      = $9499 ; 2 B: value to format (BattleMsg_FormatNumberDigits / BattleMsg_FormatTwoDigits)
!BattleMsg_Digit1000     = $949C ; 1 B: thousands digit tile (blank, $FF, except from BattleMsg_FormatNumber4Digits)
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
!Battler_PathStep        = $9734 ; 11 B per battler slot: added to the probe radius on each BattlePos_PathClear pass
                                 ; (to |dy| of the last check, not a running sum: see its header); inferred: movement
                                 ; step; who sets it is not traced
!Battler_BoxLeft         = $975A ; 11 B per battler slot: box left edge, clamped at 0 (Battle_CalcBattlerBox)
!Battler_BoxTop          = $9765 ; 11 B per battler slot: box top edge, clamped at 0
!Battler_BoxRight        = $9770 ; 11 B per battler slot: box right edge, clamped at $FF
!Battler_BoxBottom       = $977B ; 11 B per battler slot: box bottom edge: probe y, + 8 unless !Battle_Unk2989 bit 2
!Enemy_Anim              = $974A ; 1 B per enemy: animation its lists were loaded for (Battle_TickEnemyGroup; battle init
                                 ; $CC:E34E writes it). The same id ($00-$19 seen in the tables) also picks the enemy's
                                 ; mover (!BattleRom_EnemyMover, Battle_RunEnemyMover); 0 = no mover runs
                                 ; (Battle_TickEnemyMovers), negative = none either
!Enemy_MoveTarget        = $9752 ; 1 B per enemy: battler slot the movers steer by (copy of !Enemy_TargetWanted)
!Enemy_MoveAngle         = $9786 ; 1 B per enemy: heading of the current 8-pixel step (256 units per turn); the
                                 ; unmatched stepper at $CF:F978 moves the enemy along it
!Enemy_Detour            = $9791 ; 1 B per enemy: non-zero = the last step was blocked and !Enemy_MoveAngle was turned
                                 ; a quarter; the next step keeps that heading instead of aiming again
!Enemy_AnimTicks         = $9799 ; 8 B per enemy (index enemy * 8): frames per list entry, 0 = end of the list
!Enemy_AnimFrames        = $97D9 ; 8 B per enemy: frame id per list entry (!Battle_FrameId)
!Enemy_MoveDone          = $9829 ; 1 B per enemy: non-zero = the current move has ended (target reached, or a step
                                 ; blocked for the charge, axis and fixed-direction movers); incremented by the movers,
                                 ; cleared when a kind-1 list is loaded (Battle_TickEnemyGroup) and by Battle_MoverIdle.
                                 ; Inferred from the movers; what reads it outside bank $C1 is not traced
!Enemy_DoneTargetX       = $9831 ; 1 B per enemy: target's screen x when the move ended (Battle_MoverIdle compares)
!Enemy_DoneTargetY       = $9839 ; 1 B per enemy: target's screen y when the move ended
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
                                 ; zeroed before each check, set to 1 by the movers for moves 3, $0C and $0F
!BattlePos_DistLimit     = $9893 ; 2 B: squared-distance limit of the BattlePos_WithinDist* checks (set by each entry)
!Enemy_MoveTimer         = $9897 ; 1 B per enemy: frames until its mover runs again (Battle_TickEnemyMovers); battle
                                 ; init writes it at $CC:E3F3/$CC:EBFA
!Enemy_MoveInterval      = $989F ; 1 B per enemy: reload value of !Enemy_MoveTimer (battle init, $CC:EBF4)
!Enemy_Stepping          = $98A7 ; 1 B per enemy: non-zero = an 8-pixel step is under way: the unmatched stepper at
                                 ; $CF:F978 moves the enemy from !Enemy_StepStartX/Y along !Enemy_MoveAngle and clears
                                 ; it after 8 pixels. Set by the movers, cleared by BattleSys_VictoryPose
!Enemy_StepStartX        = $98AF ; 1 B per enemy: screen x the current step starts from (the stepper adds to it)
!Enemy_StepStartY        = $98B7 ; 1 B per enemy: screen y the current step starts from
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
!Battle_Unk99CF          = $99CF ; 2 B (with $99D0): count of frames L+R are held, kept by the bank-$CF frame
                                 ; routine ($CF:E715 INC, compared with $78 at $CF:E71D); non-zero with
                                 ; !Battle_Unk2989 bit 7 makes BattleSys_UpkeepTwoFrames show message $75
!Battle_Unk99D0          = $99D0 ; high byte of the !Battle_Unk99CF count
!Battle_Unk99D1          = $99D1 ; 1 B: latch: set when that message is shown; $CF:E732 clears it (and the count)
                                 ; whenever L+R are not both held and $A013 is 0, so once per hold
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
!Battle_UnkA0FE          = $A0FE ; 1 B: incremented by services 8 and 9 (the end-of-battle poses); read at $CF:EDC5;
                                 ; meaning unknown
!Battle_UnkA0FF          = $A0FF ; 2 B: index into !Battle_Unk1C48; purpose unknown
!Battle_StatusAnimWraps  = $A102 ; 1 B: counts Battle_PickNextStatusAnim's wraps past slot 10 (BattleSys_RunAction zeroes
                                 ; it and waits for 1)
!Battler_AnimShown       = $A103 ; 1 B per battler slot: animation id last drawn (Battle_TickPcSlots)
!Battle_UnkA10E          = $A10E ; 1 B: non-zero skips the message check in BattleSys_UpkeepTwoFrames; purpose unknown
!BattleUI_LowHp          = $A10F ; 1-2 B: non-zero while drawing a PC whose HP is 0, or 1..MaxHP/8 with !BattleUI_UnkA110 set
!BattleUI_UnkA110        = $A110 ; 1-2 B: non-zero lets HP 1..MaxHP/8 count as low (HP 0 always does); otherwise unknown
!BattleMenu_KeepRow      = $A114 ; 1 B: set by alt-confirm; CommitAction then keeps !Pc_SavedMenuRow
!BattleUI_UnkA115        = $A115 ; 1-2 B: PC slot compared with the drawn slot in DrawCommandList; purpose unknown
!BattleUI_UnkA117        = $A117 ; 1 B: zero lets DrawCommandList show the Combo list without the A115 test; purpose unknown
!Battler_UnkA119         = $A119 ; 1 B per battler slot: non-zero = Battle_PickStatusAnim treats the battler as KO'd
                                 ; (first record forced, !Battler_KoFlag set); set for PCs by BattleAct_FlagLethalPcHits (pending hit
                                 ; reaches the HP) and cleared again by BattleSys_RunAction when it draws the KO frame
!Battle_AnimFrameList    = $A1E8 ; 2 B: offset in !BattleRom_AnimData of the frame-id list being stepped; 2 B per
                                 ; battler slot (index slot*2) in BattleAct_StepBattlerAnims
!Battle_AnimDurList      = $A1FE ; 2 B: offset of the frame-duration list being stepped (per slot there too)
!Battle_MoverAnim        = $A2B5 ; 1 B: !Enemy_Anim of the enemy being moved (Battle_RunEnemyMover); the movers test it
                                 ; for their variants (!Enemy_Move* constants)
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
!Enemy_RingGoalX         = $A5E4 ; 1 B per enemy: x of the point on the ring around the target that the ring movers
                                 ; (Battle_MoverKeepRange, Battle_MoverOrbit) head for
!Enemy_RingGoalY         = $A5EC ; 1 B per enemy: y of that point
!Enemy_OrbitReverse      = $A5F4 ; 1 B per enemy: 0 = Battle_MoverOrbit circles with the angle growing, 1 = shrinking;
                                 ; flipped when an orbit step is blocked
!Battle_OrbitRadius      = $A5FC ; 1 B: ring radius of the enemy Battle_MoverOrbit is moving ($20, or $40 for move $0E)
!Enemy_LoopStarted       = $A5FD ; 1 B per enemy: non-zero = Battle_MoverLoop has set up its loop; cleared by the other
                                 ; movers except the fixed-direction and centre ones (Battle_MoverIdle only once a
                                 ; move has ended)
!Enemy_LoopCentreX       = $A605 ; 1 B per enemy: x of the centre of Battle_MoverLoop's loop (its x at the start)
!Enemy_LoopCentreY       = $A60D ; 1 B per enemy: y of that centre (its y at the start + 16)
!Enemy_LoopPhase         = $A615 ; 1 B per enemy: angle of the loop point it heads for (starts at $C0, straight up)
!Enemy_LoopReverse       = $A61D ; 1 B per enemy: 0 = the phase grows by $10 per step, 1 = it shrinks
!Battle_LoopRadius       = $A625 ; 1 B: vertical loop radius of the enemy Battle_MoverLoop is moving ($20, or $10 for
                                 ; move $0A); the horizontal one is $20 more
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
; Actions (service 4: BattleSys_RunAction and its loaders)
; ------------------------------------------------------------
; The action block !Battle_ActCaster..!Battle_ActUnkAE9B is filled by the
; unmatched code at $C1:ACF0 from the chosen command; the meanings below
; come from that code and from what service 4 does with the values.
!Battle_ActCaster        = $AE91 ; 1 B: battler slot that acts (copied from $B18B at $C1:ACF9); 0-2 = a PC, so the
                                 ; loaders pick the PC or the enemy records by it
!Battle_ActKind          = $AE92 ; 1 B: loader 0-3 in BattleAct_LoaderTable (4 and up act as 0); from $AEE3
!Battle_ActId            = $AE93 ; 1 B: record number for the loader (tech id for kind 2, inferred); from $AEE4
!Battle_ActFlags         = $AE94 ; 1 B: bit 6 = also start the script's second thread group (!Battle_ActSecondGroup);
                                 ; non-zero also skips BattleAnim_UnkVecCD0018 unless the id is $37
!Battle_ActUnkAE9B       = $AE9B ; 1 B: bit 7 = a PC attack uses its third record set (the "Alt" fields); also
                                 ; written at $C1:EDB5; purpose unknown
!Battle_ActSecondGroup   = $A0B3 ; 2 B: bit 6 of !Battle_ActFlags (stored 16-bit by service 4); non-zero = the loaders
                                 ; skip the first thread group and start the second; cleared (low byte) after use
!Battle_ActRunning       = $A013 ; 1 B: counted up when service 4 starts the script, zeroed when it returns
!Battle_ActFrameHold     = $A012 ; 1 B: set to 2 when BattleAct_StepBattlerAnims decodes a frame; non-zero = it decodes
                                 ; none (zeroed by service 4 and $CC:F0EF, counted down at $CF:E775, unmatched)
!Battle_UnkA028          = $A028 ; 1 B: non-zero = BattleAct_StepBattlerAnims decodes no frame; purpose unknown
!Battle_ActScriptDone    = $9876 ; 1 B: non-zero = the action's script has ended (counted up at $C1:4D00 in
                                 ; BattleAct_OpEndScript, zeroed by BattleAct_ResetState); service 4 waits for it
!Battle_ActScriptId      = $9877 ; 1 B: script number of the action; first byte of the 16-byte parameter block
                                 ; ($9877-$9886) that BattleAct_LoadScript clears
!Battle_ActUnkArg987C    = $987C ; 1 B: A for BattleAnim_UnkVecCD0018 ($FF = do not call it); set to $FF by
                                 ; BattleAct_LoadScript, from the record by the tech loaders; meaning unknown
!Battle_Unk5D9B          = $5D9B ; 1 B: service 4 waits for it to be 0 after the script; zeroed by the $CD:0018
                                 ; vector, counted up at $CD:0D8F/$CD:0E11 (unmatched); purpose unknown
!Battle_UnkAB4E          = $AB4E ; 1 B: zeroed by service 4 after the script; set by opcode $6B, zeroed by opcode $6D:
                                 ; non-zero = $CF:E602 rotates colours (probably the palette cycle's on flag)
!Battle_ActUnkA1A8       = $A1A8 ; 8 B lists ($A1A8 flags, $A1B0 timers, ...): $CC:F278 counts each set entry's
                                 ; timer down and runs $CC:F2A9 at 0; service 4 clears 40 bytes from here
!Battle_ActBattlers      = $A014 ; list of battler slots, $FF-ended ($CC:F156): caster, the two slots from $AE97/$AE98
                                 ; (for a PC caster $FF there becomes the other two PCs), the main target, the others
!Battle_ActMainTarget    = !Battle_ActBattlers+3 ; 1 B: entry 3 of !Battle_ActBattlers, the main target (the first set bit
                                 ; of the 16-bit mask at $AE95, $CC:F186)
!Battle_ActTargetSet     = !Battle_ActBattlers+4 ; entries 4 on: the slots of the 16-bit target mask at $AE99, $FF-ended
                                 ; ($CC:F1AA; bit 15 = slot 0)
!Battle_ActTargets       = $AC5C ; list of the target slots (main target first), $FF-ended ($CC:F156)
!Battle_ActPcHitAmount   = $AD9C ; 2 B, 4-byte record per PC: amount compared with the PC's HP by
                                 ; BattleAct_FlagLethalPcHits (inferred: damage about to be dealt); opcodes $50-$55
                                 ; read six sets of 11 such records (one per battler slot, !BattleRom_HitSetOffset)
!Battle_ActPcHitKind     = $AD9E ; 2 B, same records: kind of the amount; only kind 3 is checked
!Battle_UnkA118          = $A118 ; 1 B: set to 2 at the end of service 4 when a PC was among the targets; purpose unknown
!Battler_ActAnimMode     = $A124 ; 1 B per battler slot: action animation on (non-zero); 2 = loop at the end of the
                                 ; list, else stop (BattleAct_StepBattlerAnims)
!Battler_ActAnimTimer    = $A12F ; 1 B per battler slot: frames until the next entry of its action animation
!Battler_ActAnimEntry    = $A13A ; 1 B per battler slot: current entry of its action animation lists
!Battler_ActAnimStop     = $A150 ; 1 B per battler slot: non-zero = show entry (value - 1) and switch the animation off
!Battler_ActFacing       = $A214 ; 1 B per battler slot: facing its action animation was last stepped with
!Battle_ActAnimNextSlot  = $A21F ; 1 B: slot BattleAct_StepBattlerAnims starts its search at (round robin)
!Battle_ActCalcSel       = $A4E8 ; 6 B: per entry, 0 = off, n = run BattleAct_RunCalc handler n - 1 every frame
!Battle_ActCalcOutA      = $A2B0 ; 1 B: first result a BattleAct_RunCalc handler leaves (not analysed)
!Battle_ActCalcOutB      = $A2B2 ; 1 B: second result
!Battle_ActCalcResult    = $5DA0 ; 2 B per !Battle_ActCalcSel entry: the two results copied by BattleAct_TickCalcs
!Battle_ActScriptOfs     = $9878 ; 2 B: offset of the script in its bank ($CE or $CD; see the loaders); zeroed first,
                                 ; so the 16-bit read of !Battle_ActScriptId sees 0 above it
!Battle_ActGfxSetA       = $987A ; 1 B: graphics set for BattleAnim_LoadGfx4Vec
!Battle_ActGfxSetB       = $987B ; 1 B: graphics set for BattleAnim_LoadGfx2Vec
!Battle_ActFramesIdx     = $987E ; 1 B: index into the sprite-frame pointer table (read 16-bit, $987F zeroed)
!Battle_ActFramesPtr     = $987F ; 2 B: pointer in bank $D1 to the packed sprite frames (BattleAct_LoadCommon)
!Battle_ActPalIdx        = $9881 ; 1 B: index into the palette-step pointer table (read 16-bit, $9882 zeroed)
!Battle_ActPalPtr        = $9882 ; 2 B: offset in bank $CD of the palette steps BattleAct_StepPalettes reads
!Battle_ActObjIdx        = $9884 ; 1 B: index into the object-record pointer table (read 16-bit, $9885 zeroed)
!Battle_ActObjPtr        = $9885 ; 2 B: offset in bank $CE of the object records (BattleAct_IndexObjLists)
!Battle_ActNear          = $9930 ; 1 B: set by BattleAct_CheckReach: 1 when a path to the main target was found (searched
                                 ; only when it is within 40 pixels or for characters with !BattleRom_PcPathAlways), else 0;
                                 ; picks a PC attack's "Near" or "Far" records
!Battle_ActPcAttackRec   = $A4E7 ; 1 B: record number of the PC attack (from !Battle_Unk1C48); not read in bank $C1's
                                 ; matched code
!Battle_ActThreadOn      = $5DAC ; 1 B per script thread 0-15: non-zero = BattleAct_RunThreads runs it (stored 16-bit)
!Battle_ActThreadPtr     = $5DBD ; 4 B per thread: offset word of its script position, then the bank ($CE or $CD,
                                 ; !Battle_ActThreadBank) and 0; same bytes as !Pc_PoseTimer and the pose variables
!Battle_ActThreadBank    = $5DBF ; 2 B per thread (same 4-byte records): bank byte and 0
!Battle_ActThreadWait    = $5DFD ; 1 B per thread 0-15: frames BattleAct_RunThread only counts down before running the
                                 ; thread again (set at $C1:571A, unmatched)
!Battle_ActScriptPtr     = $E6   ; 3 B (DP long): script position of the thread being run (BattleAct_RunThread); $E9 is
                                 ; also touched by BattleAct_AdvanceScript's 16-bit add
!Battle_ActThreadOfs     = $A00E ; 1 B: thread * 4, its !Battle_ActThreadPtr offset, while it runs
!Battle_ActNextOp        = $A00F ; 1 B: zeroed before each opcode; a handler counts it up to have the next opcode run
                                 ; in the same frame
!Battle_ActThread        = $A010 ; 1 B: thread being run (0-15); the handlers pick the actor by it
!Battle_ActOpcode        = $9895 ; 1 B: opcode being run
!Battle_ActObjThread     = $A2B6 ; 1 B: object thread 0-7 (thread - 8) while threads 8-15 run (BattleAct_RunThreads)
!Battle_ActUnkA3D1       = $A3D1 ; 1 B: non-zero = object threads are not run and BattleAct_OpEndScript waits; the state
                                 ; of BattleAct_OpShowHitNumbers (0 idle, 1 build, 2 wait for the bounce), also zeroed by
                                 ; BattleAct_ResetState
!Battle_ActTargetMask    = $AE99 ; 2 B: target set as a mask, bit 15 = slot 0 (expanded into !Battle_ActTargetSet by
                                 ; $CC:F1AA); thread 4 runs only while it is non-zero
!Battler_ActAnimStarted  = $A145 ; 1 B per battler slot: set when opcode $03 has started the battler's animation, cleared
                                 ; when it has ended (BattleAct_OpPlayAnim)
!Battle_ActObjAnimTimer  = $A1B0 ; 1 B per object thread 0-7: timer of its object list (zeroed on start; the mode is
                                 ; !Battle_ActUnkA1A8, stepped at $CC:F278, unmatched)
!Battle_ActObjAnimEntry  = $A1B8 ; 1 B per object thread: current entry ($FF on start)
!Battle_ActObjAnimStarted = $A1C0 ; 1 B per object thread: opcode $03's started flag (BattleAct_OpPlayAnim)
!Battle_ActObjAnimStop   = $A1C8 ; 1 B per object thread: opcodes $04-$06's flag (BattleAct_OpShowAnimFrame); read at
                                 ; $CC:F2DB (unmatched)
!Battle_ActObjUnkA1D8    = $A1D8 ; 1 B per object thread: counted up by opcode $70 and by opcode $03's start, zeroed when
                                 ; opcode $03 ends; read at $CF:EDDF; purpose unknown
!Battle_ActObjAnimList   = $A220 ; 2 B per object thread: !Battle_ActObjListStart of the object list it plays
!Battle_ActObjAnimCount  = $A238 ; 1 B per object thread: !Battle_ActObjMarkCount of that list
!Battle_ActObjAnimUnkA2B8 = $A2B8 ; 1 B per object thread: $FF on start, compared at $CC:F2AE (presumably as
                                 ; !Battler_ActFacing is for the battlers)
!Battle_ActorMoveDelay   = $A2FE ; 1 B per actor (11 battler slots, then object threads 0-7): frames per move step; the
                                 ; movers at $CF:EFC4/$CF:EFF4 reload !Battle_ActorMoveTimer from it (opcodes $07-$0F)
!Battle_ActorMoveSpeed   = $A324 ; 1 B per actor: pixels per move step along the major axis (the move opcodes divide the
                                 ; distance by it for the step count and scale the unit step by it)
!Battle_ActorMoving      = $A337 ; 1 B per actor: 1 while a move started by a move opcode runs (the movers at $CF:EFC4
                                 ; step only these); cleared by the opcode when the move is done
!Battle_ActorMoveTimer   = $A2EB ; 1 B per actor: frames to the next move step, reloaded from !Battle_ActorMoveDelay
!Battle_ActorMoveKind    = $A86D ; 1 B per actor: mover the $CF:EFE6 dispatch runs (table at $CF:F01E); 0 = straight
!Battle_ActorMoveSteps   = $ABEB ; 1 B per actor: steps left; the straight mover sets the done flag at 0 ($CF:F07C)
!Battle_ActorFromX       = $A35D ; 1 B per actor: x at the start of the move (the mover writes it + the offset to x)
!Battle_ActorFromY       = $A370 ; 1 B per actor: y at the start
!Battle_ActorToX         = $A383 ; 1 B per actor: the point moved to
!Battle_ActorToY         = $A396 ; 1 B per actor
!Battle_ActorStepX       = $A888 ; 2 B per actor (index actor * 2): signed 8.8 pixels added to the offset each step
!Battle_ActorStepY       = $A8AE ; 2 B per actor
!Battle_ActorOfsX        = $A8D4 ; 2 B per actor: signed 8.8 offset from the start; the high byte is added ($CF:F069)
!Battle_ActorOfsY        = $A8FA ; 2 B per actor
!Battler_MoveDone        = $A19D ; 1 B per battler slot: set to 1 by the straight mover when the steps run out
                                 ; ($CF:F083); the move opcodes wait for it
!Battle_ActObjMoveDone   = $A1E0 ; 1 B per object thread: the same for the objects (written at $CF:F4FF and others)
!Battle_ActObjX          = $A240 ; 2 B per object thread (index j * 2): the object's x (low byte read as a screen x)
!Battle_ActObjY          = $A250 ; 2 B per object thread: its y
!Battle_ActObjMoveAngle  = $A355 ; 1 B per object thread: angle of its last move (Battle_CalcAngle)
!Battle_ActObjUnkA5B5    = $A5B5 ; 1 B per object thread: also set to that angle; purpose unknown
!Battle_ActObjFacing     = $A230 ; 1 B per object thread: !BattleRom_FacingByAngle of that angle
!Battle_ActObjUnkA31C    = $A31C ; 1 B per object thread: zeroed when an object's move starts; purpose unknown
!Battle_ActThreadOpLen   = $A3A9 ; 1 B per thread: length of the move opcode it waits on, advanced by when it ends
!Battle_ActUnkPointX     = $5D9E ; 1 B: x of the point opcodes $11, $14, $17 and $1A use (variable $1E of
                                 ; !Battle_ActVars); set by opcodes $33 (BattleAct_OpCalcToUnkPoint),
                                 ; BattleAct_OpOffsetToUnkPoint and BattleAct_OpActorPosToUnkPoint; purpose otherwise unknown
!Battle_ActUnkPointY     = $5D9F ; 1 B: its y (variable $1F); opcode $21 also tests it for 0
!Battle_ActVars          = $5D80 ; script variables, 1 B each, index n from the operand (opcodes $22, $30, $34, $37,
                                 ; $3A, $3C, $41, $42, $49); just after the 16 BattleActObj records, cleared by BattleAct_ResetState
                                 ; ($5D80-$5E0C); entries $1C-$1F have opcodes of their own
!Battle_ActVar1C         = $5D9C ; 1 B: variable $1C (opcodes $23, $31, $35, $38, $3B, $3C; also BattleAct_OpCopyVar1C and
                                 ; the swap opcodes)
!Battle_ActVar1D         = $5D9D ; 1 B: variable $1D (opcodes $24, $32, $36, $39)
!Battle_ActThreadReturn  = $A569 ; 2 B per thread (index thread * 4): offset to return to from a subscript (opcode $1E)
!Battle_ActThreadReturnBank = $A56B ; 2 B per thread (same records): its bank byte, then 0
!Battle_ActObjFollow     = $A437 ; 1 B per object thread: what the object follows ($CF:ECC2 copies its position each
                                 ; frame): a battler slot, or !Battle_ActFollowObj + object thread; $FF = nothing
                                 ; (set by BattleAct_ResetState)
!Battle_ActUnkCFFF       = $CFFF ; 1 B: set to 1 by opcode $2D, to 0 by opcode $2E; also written at $CD:18C4
                                 ; (unmatched); purpose unknown
!Battler_UnkA4A4         = $A4A4 ; 1 B per battler slot: zeroed by opcode $2B; used by the movers in bank $CF ($CF:F21D and
                                 ; others); purpose unknown
!Battler_UnkA4AF         = $A4AF ; 1 B per actor: the same ($CF:F158 and others; also $C1:6FBF, unmatched)
; The curving move (opcodes $13-$15, mover kind 7 at $CF:F405, unmatched):
!Battle_ActorHeading     = $AC11 ; 1 B per actor: heading angle of a curving move; the opcode sets the start heading,
                                 ; the mover turns it towards the point by up to !Battle_ActorMoveSpeed per step and
                                 ; moves along it (sine lookups at $CF:F48D)
!Battle_ActorTurnDir     = $AC37 ; 1 B per actor: 0 = the heading turns by increasing the angle, 1 = by decreasing it
                                 ; (BattleAct_CurveTurnDir picks the shorter way)
!Battle_ActorOnCourse    = $AC24 ; 1 B per actor: zeroed at the start; the mover counts it up when the heading reaches
                                 ; the angle to the point, and from then on stops turning
!Battle_ActorUnkA311     = $A311 ; 1 B per actor: zeroed when a curving move starts (the object part is
                                 ; !Battle_ActObjUnkA31C); read and written at $CF:F1B9; purpose unknown
!Battle_ActorUnkA5AA     = $A5AA ; 1 B per actor: start heading of a curving move whose operand is $FF; for the objects
                                 ; ($A5B5, !Battle_ActObjUnkA5B5) the straight move stores its angle there, so probably
                                 ; the last heading; written by many unmatched handlers ($C1:60BF and on)
; The path walk (opcodes $16-$18, stepped by $CF:EC78, unmatched):
!Battler_PathMaps        = $7FFD ; 256 B per battler slot (offset !BattleRom_SlotTimes256): the battler's copy of
                                 ; !Battle_PathMap with its path marked, kept for the whole walk
!Battle_PathWalkMap      = $8AFD ; 256 B: the walking battler's map, copied back from !Battler_PathMaps before each step
!Battler_PathWalking     = $A15B ; 1 B per battler slot: 1 while it walks a path; $CF:EC78 steps only these
!Battler_UnkA166         = $A166 ; 1 B per battler slot: counted up when a path walk starts; no reader found
!Battle_ActThreadPathLen = $A4F0 ; 1 B per thread: length of the path opcode it runs, kept because
                                 ; BattleAct_FindPath overwrites DP $8E
!Battler_PathStepFrame   = $A500 ; 1 B per battler slot: frames left of the step to the next cell, 7 down to 0;
                                 ; negative = the step is done ($CF:EC78 counts it down; $FF on start)
!Battler_PathStepKind    = $A517 ; 1 B per battler slot: kind of the step, direction * 8 + 0-4 (straight, two
                                 ; diagonals, two curved diagonals); $CF:EC78 adds entry kind * 8 + frame of the
                                 ; tables at $CC:F494 (x) and $CC:F594 (y) to !Battler_ScreenX/Y
!Battler_UnkA522         = $A522 ; 1 B per battler slot: zeroed when a path walk starts; no other access found
!Battler_PathCell        = $A53D ; 1 B per battler slot: cell the battler walks from (the one it steps to, once
                                 ; the step is chosen)
!Battler_PathFromDir     = $A548 ; 1 B per battler slot: direction of the cell it came from (!Battle_PathDirUp..),
                                 ; not looked at for the next step; !Battle_PathDirNone at the start
!Battler_PathStartX      = $A553 ; 1 B per battler slot: x when the path walk started; no reader found
!Battler_PathStartY      = $A55E ; 1 B per battler slot: y
!Battle_ActMoveUnitX     = $A880 ; 2 B: signed 8.8 unit step x from BattleAct_CalcMoveStep (scaled by the speed after)
!Battle_ActMoveUnitY     = $A882 ; 2 B: the same for y
!Battle_MoveMajorDist    = $AAFE ; 1 B: the larger of |dx| and |dy| of the last BattleAct_CalcMoveStep
!Battler_DefMoveDelay    = $973F ; 1 B per battler slot: default !Battle_ActorMoveDelay (set at $CC:E3E8, unmatched)
!Battler_DefMoveSpeed    = $98BF ; 1 B per battler slot: default !Battle_ActorMoveSpeed (set at $CC:E3E3)
!Battle_DecompSrc        = $0300 ; 2 B: Decomp_ToWramVec source address (DP $00 of that routine, which sets DP=$0300)
!Battle_DecompSrcBank    = $0302 ; 1 B: its bank
!Battle_DecompDest       = $0303 ; 2 B: WRAM destination address (written to WMADDL)
!Battle_DecompDestBank   = $0305 ; 1 B: its bank (bit 0 to WMADDH)
!Battle_DecompLen        = $0306 ; 2 B: read back as the end offset of the output (inferred: BattleAct_LoadCommon
                                 ; marks the end of the data there)
!Battle_ActFrameBuf      = $2D00 ; bank $7E buffer the packed sprite frames are unpacked into (also the source of the
                                 ; graphics uploads at $CD:1314/$CD:1323, unmatched)
!Battle_ActFrameNum      = $A650 ; 2 B: next frame BattleAct_UnpackFrames builds (0-31)
!Battle_ActFrameReadOfs  = $A652 ; 2 B: read offset in !Battle_ActFrameBuf
!Battle_ActFrameSprites  = $A05B ; 1 B per frame 0-31: sprites built for it
!Battle_ActRowMasks      = $A2D3 ; up to 15 B: column masks of the frame being built, one per row
!Battle_ActAttrBits      = $A5E3 ; 1 B: ORed into the attribute byte of every action sprite and into byte +3 of the
                                 ; action objects; who sets it is not traced
!Battle_ActObjListStart  = $A280 ; 2 B per action object 0-15: offset of its first record (bank $CE)
!Battle_ActObjMarkCount  = $A2A0 ; 1 B per action object: record count at its last mark (BattleAct_IndexObjLists)
!Battle_ActObjUnkA07B    = $A07B ; 1 B per action object: set to 1 by BattleAct_LoadCommon; meaning unknown

; Hit numbers (opcodes $50-$55, BattleAct_OpShowHitNumbers): up to four
; digit sprites per battler slot, then bounced by $CF:E781 (unmatched).
; "Number" is inferred from the digit tiles BattleMsg_FormatNumber4Digits
; gives; that they show damage is inferred from !Battle_ActPcHitAmount.
struct Battle_HitNumSprite $922D ; 4 B per sprite, 4 sprites (16 B) per battler slot, 11 slots ($B0 B); the same
                                 ; bytes as !Pc_PoseTicks, which the pose code uses at other times
.X:         skip 1      ; +0: screen x
.Y:         skip 1      ; +1: screen y ($CF:E7BA adds the bounce step to it)
.Tile:      skip 1      ; +2: digit tile
.Attr:      skip 1      ; +3: attribute byte
endstruct
!Battle_HitNumHigh       = $92DD ; 1 B per battler slot: OAM high-table bits of its four number sprites (2 bits each;
                                 ; read at $CF:EEB0, unmatched)
!Battler_HitNumShown     = $A3D4 ; 1 B per battler slot: set to 1 when numbers were built for it (read at $CF:EEA5)
!Battler_HitNumAltBounce = $A0DC ; 1 B per battler slot: set to 1 for hit kinds other than 1, 3 and 5; $CF:E794 then
                                 ; takes the bounce steps from $D1:5E49 instead of $D1:5E10
!Battler_UnkA003         = $A003 ; 1 B per battler slot: non-zero = its numbers are placed at !Battler_ScreenX/Y plus
                                 ; !Battler_ScreenOffsetX/Y, else at !Battler_ScreenX/Y; who sets it is not traced
!Battle_HitNumActive     = $AC5A ; 1 B: set to 1 once the numbers are built; $CF:E781 bounces them each frame and
                                 ; clears it at the end of its step table; opcodes $50-$55 wait for that
!Battle_HitNumStep       = $A3D2 ; 1 B: step in the bounce table ($CF:E786 reads it, $CF:E7AF counts it up)
!Battle_HitNumSet        = $A3D3 ; 1 B: record set of the numbers shown (opcode & 7); no reader found in bank $C1
!Battle_HitNumColoursA   = $999F ; 8 B: colour bytes copied to the start of !Battle_PaletteLive (the palette of
                                 ; attribute !Battle_HitNumAttr); also written at $CC:EF0D (unmatched)
!Battle_HitNumColoursB   = $99A7 ; 8 B: the same, copied to !Battle_PaletteLive+$80 (the palette of
                                 ; !Battle_HitNumAttrAlt)

; Palettes of the action (opcodes $60-$6D):
!Battle_PaletteSavedLo   = $2000 ; 256 B just before !Battle_PaletteSaved (probably the background half of the same
                                 ; buffer); opcodes $6A/$6C copy it back over !Battle_PaletteLiveLo
!Battle_PaletteLiveLo    = $2200 ; 256 B just before !Battle_PaletteLive: the live half that goes with it
!Battle_ActPalSeqOn      = $A3B9 ; 1 B per palette sequence 0-3: non-zero = BattleAct_StepPalettes ($CC:F1E7) steps it
!Battle_ActPalSeqStep    = $A3BD ; 1 B per sequence: entries stepped past the first ($FF on start, so the first step
                                 ; shows the first entry)
!Battle_ActPalSeqTimer   = $A3C1 ; 1 B per sequence: frames to the next step (1 on start)
!Battle_ActPalSeqDelay   = $A3C5 ; 1 B per sequence: frames per step (reloads the timer)
!Battle_ActPalSeqFirst   = $A3C9 ; 1 B per sequence: first palette-list entry; the step wraps back to it
!Battle_ActPalSeqLast    = $A3CD ; 1 B per sequence: last palette-list entry
!Battle_Unk99D2          = $99D2 ; 1 B: non-zero = enemies with !Battler_UnkA08C set also get the palette opcodes'
                                 ; colours in !Battle_PaletteLiveLo from colour !Battle_Unk99D3 on (probably an
                                 ; enemy drawn on a background layer; not traced)
!Battle_Unk99D3          = $99D3 ; 1 B: first colour (index of a 2-byte colour) of that part of !Battle_PaletteLiveLo
!Battler_UnkA08C         = $A08C ; 1 B per battler slot: see !Battle_Unk99D2
!Battler_BasePalette     = $9888 ; 1 B per battler slot: !Battler_Palette value opcodes $6A and $6C put back
!Battler_BlinkTimer      = $A17C ; 1 B per battler slot: frames to the next toggle of opcode $6C's blink
!Battler_BlinkOn         = $A187 ; 1 B per battler slot: opcode $6C's blink state, toggled 0/1 (1 = special palette)
!Battle_PalCycleTimer    = $AB4A ; 1 B: frames to the next colour rotation ($CF:E60A counts it down)
!Battle_PalCycleDelay    = $AB4B ; 1 B: frames per rotation (reloads the timer)
!Battle_PalCycleLo       = $A08B ; 1 B: non-zero = the rotation at $CF:E634 also turns the !Battle_Unk99D3 colours of
                                 ; !Battle_PaletteLiveLo

; Headings, facings and links (opcodes $72-$77, $85):
!Battle_ActFacingOut     = $A2B4 ; 1 B: facing left by the BattleAct_CalcFacing handlers
!Battle_ActObjLinkSlot   = $AB4F ; 1 B per object thread: battler slot opcodes $73/$74 linked it to
!Battle_ActObjLinks      = $A3DF ; 11 B per object thread (index thread * 11 + battler slot): opcodes $73/$74 store
                                 ; the object thread with bit 7 or bit 6 there; read at $CF:EDD4 and $CF:F81D (unmatched)
!Battle_ActHeadToX       = $A5BE ; 1 B: opcode $76: x of the point the heading is taken to
!Battle_ActHeadFromCalc  = $A5BF ; 1 B: opcode $76: calc handler of the point it is taken from
!Battle_ActHeadToY       = $A5C0 ; 1 B: opcode $76: y of the point it is taken to
!Battle_ActOp80Args      = $53   ; up to 15 B (DP): bytes opcode $80 copies from its script (from its length byte on)
                                 ; for BattleAct_UnkVecCD001B

; Sprites of the action's frames: 4 bytes per sprite, $C0 bytes (48
; sprites) per frame at the offset !BattleRom_ActFrameBase gives
; (BattleAct_UnpackFrames). "Sprite" is inferred from the layout.
struct BattleActSprite $4500
.X:         skip 1      ; +0: x in the frame, column * 16
.Y:         skip 1      ; +1: y in the frame, row * 16
.Tile:      skip 1      ; +2: tile byte from the frame data
.Attr:      skip 1      ; +3: attribute byte from the frame data, with !Battle_ActAttrBits
endstruct

; The 16 action objects, 8 bytes each (index object * 8), set up by
; BattleAct_LoadCommon; what they are is not established.
struct BattleActObj $5D00
.Unk0:      skip 1      ; +0: zeroed
.Unk1:      skip 1      ; +1: zeroed
.Unk2:      skip 1      ; +2: from BattleRom_ActObjInit.Unk0
.Unk3:      skip 1      ; +3: from BattleRom_ActObjInit.Unk1, with !Battle_ActAttrBits
            skip 4
endstruct

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
!BattleRom_PcPathAlways   = $CCF63C  ; 1 B per character id 0-6: non-zero = BattleAct_CheckReach searches a path even to a
                                      ; target beyond 40 pixels (01 00 00 01 01 01 01: all but characters 1 and 2)
!BattleRom_ActSubscripts  = $CE0000  ; 2 B per subscript: its offset in bank $CE (opcode $1E)
!BattleRom_SlotTimes256   = $CCF67C  ; 2 B per battler slot: slot * $100 (offset in !Battler_PathMaps)
!BattleRom_PathFromDir    = $CCF414  ; 1 B per path step kind: the !Battler_PathFromDir it leaves (opposite of the move; for a
                                      ; diagonal, of its sideways part)
!BattleRom_PathFacing     = $CCF434  ; 1 B per path step kind: !Battler_Facing for it (the direction: 0-3)
!BattleRom_PathAhead      = $CCF454  ; 8 B per direction: cell index steps +0 two cells ahead, +1/+2 the two diagonals
                                      ; ahead (for up: -32, -17, -15)
!BattleRom_PathSide       = $CCF474  ; 8 B per direction: +1/+2 the side cell next to each diagonal (for up: -1, +1)
!BattleRom_ActMoveDelay   = $CCF5BC  ; 8 B: !Battle_ActorMoveDelay for opcodes $08-$0F (4, 2, then 1)
!BattleRom_ActMoveSpeed   = $CCF4BC  ; 8 B: !Battle_ActorMoveSpeed for them (1, 1, 1, 2, 4, 8, $10, $20)
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
!BattleRom_DigitTilesB     = $CCF90D  ; 10 B: a second set of digit tiles 0-9 ($90-$99), read by BattleMsg_FormatNumber4Digits
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
!BattleRom_EnemyMover     = $CCFBAB  ; 1 B per !Enemy_Anim id ($1A ids, up to $CC:FBC4): entry 0-8 of
                                      ; Battle_EnemyMoverTable (Battle_RunEnemyMover)
!BattleRom_Div5           = $CCFBCE  ; 1 B per n: n / 5 (checked for the first 32 bytes); duration byte -> frames
!BattleRom_ActForceAlt    = $CFFFFF  ; 1 B: non-zero = service 4 sets !Battle_ActUnkAE9B bit 7 and clears the flags (0 here)
!BattleRom_ActForceSecond = $CFFFFE  ; 1 B: non-zero = service 4 sets !Battle_ActFlags to bit 6 (0 in this ROM)
!BattleRom_ActForceNone   = $CFFFFD  ; 1 B: non-zero = service 4 clears both (0 in this ROM); the three look like
                                      ; build switches
!BattleRom_PcKoFrame      = $D15F42  ; 1 B per character * 4 + facing: frame id service 4 draws for a PC whose
                                      ; pending hit reaches its HP (inferred from that use: the KO'd pose)
!BattleRom_ScriptBankPc   = $CE      ; bank of the scripts and object records of PC attacks, PC techs and kind 3
!BattleRom_ScriptBankEnemy = $CD     ; bank of the scripts of enemy actions
!BattleRom_ScriptsCE      = $CE0000  ; base for reads at a script offset in bank $CE (thread offsets, object records)
!BattleRom_ScriptsCD      = $CD0000  ; the same in bank $CD
; Script header: two 16-bit thread masks, high byte first (BattleAct_LoadAttack and the other loaders).
struct BattleRom_ScriptHdrCE $CE0000
.Mask1Hi:   skip 1      ; +0: first group, threads 0-7 (bit 7 = thread 0)
.Mask1Lo:   skip 1      ; +1: first group, threads 8-15
.Mask2Hi:   skip 1      ; +2: second group, threads 0-7
.Mask2Lo:   skip 1      ; +3: second group, threads 8-15
endstruct
struct BattleRom_ScriptHdrCD $CD0000
.Mask1Hi:   skip 1
.Mask1Lo:   skip 1
.Mask2Hi:   skip 1
.Mask2Lo:   skip 1
endstruct
; Script number of a PC's attack, 1 B per character (index !Pc_CharId) in each of three lists.
struct BattleRom_PcAttackScript $CD4000
.Far:       skip 7      ; !Battle_ActNear = 0
.Near:      skip 7      ; !Battle_ActNear set
.Alt:       skip 7      ; !Battle_ActUnkAE9B bit 7 set
endstruct
; PC attack records, 15 B per record number (!Battle_ActPcAttackRec): three sets of 5 bytes.
struct BattleRom_PcAttackAct $CD4015
.FarGfxA:   skip 1      ; +0: !Battle_ActGfxSetA
.FarGfxB:   skip 1      ; +1: !Battle_ActGfxSetB
.FarFrames: skip 1      ; +2: !Battle_ActFramesIdx
.FarPal:    skip 1      ; +3: !Battle_ActPalIdx
.FarObj:    skip 1      ; +4: !Battle_ActObjIdx
.NearGfxA:  skip 1      ; +5: the same five for "Near"
.NearGfxB:  skip 1
.NearFrames: skip 1
.NearPal:   skip 1
.NearObj:   skip 1
.AltGfxA:   skip 1      ; +10: the same five for "Alt"
.AltGfxB:   skip 1
.AltFrames: skip 1
.AltPal:    skip 1
.AltObj:    skip 1
endstruct
; Enemy attack records, 6 B per !Battler_Unk984D value: first attack (!Battle_ActId 0) and second.
struct BattleRom_EnemyAttackAct $CD4926
.Script:    skip 1      ; +0: !Battle_ActScriptId
.GfxA:      skip 1      ; +1: !Battle_ActGfxSetA
.GfxB:      skip 1      ; +2: !Battle_ActGfxSetB
.Frames:    skip 1      ; +3: !Battle_ActFramesIdx
.Pal:       skip 1      ; +4: !Battle_ActPalIdx
.Obj:       skip 1      ; +5: !Battle_ActObjIdx
endstruct
struct BattleRom_EnemyAttack2Act $CD4F26
.Script:    skip 1
.GfxA:      skip 1
.GfxB:      skip 1
.Frames:    skip 1
.Pal:       skip 1
.Obj:       skip 1
endstruct
; Tech records, 7 B per !Battle_ActId: the six above plus the argument of BattleAnim_UnkVecCD0018.
struct BattleRom_PcTechAct $CD45A6
.Script:    skip 1
.GfxA:      skip 1
.GfxB:      skip 1
.Frames:    skip 1
.Pal:       skip 1
.Obj:       skip 1
.Arg:       skip 1      ; +6: !Battle_ActUnkArg987C
endstruct
struct BattleRom_EnemyTechAct $CD5526
.Script:    skip 1
.GfxA:      skip 1
.GfxB:      skip 1
.Frames:    skip 1
.Pal:       skip 1
.Obj:       skip 1
.Arg:       skip 1
endstruct
struct BattleRom_Kind3Act $CD5C26   ; 7 B per !Battle_ActId - $BC
.Script:    skip 1
.GfxA:      skip 1
.GfxB:      skip 1
.Frames:    skip 1
.Pal:       skip 1
.Obj:       skip 1
.Arg:       skip 1
endstruct
!BattleRom_PcAttackScripts = $CD5EC6 ; 2 B per script number: script offset in bank $CE (PC attacks)
!BattleRom_PcTechScripts  = $CD5EF0  ; 2 B per script number: offset in bank $CE (PC techs)
!BattleRom_EnemyAttackScripts = $CD5FF0 ; 2 B per script number: offset in bank $CD (enemy attacks)
!BattleRom_EnemyTechScripts = $CD61F0 ; 2 B per script number: offset in bank $CD (enemy techs)
!BattleRom_Kind3Scripts   = $CD63F0  ; 2 B per script number: offset in bank $CE (kind 3)
!BattleRom_PcAttackObjs   = $CD64B0  ; 2 B per !Battle_ActObjIdx: object-record offset in bank $CE (PC attacks)
!BattleRom_TechObjs       = $CD656E  ; the same for PC techs and kind 3
!BattleRom_EnemyActObjs   = $CD666E  ; the same for enemy attacks and techs
!BattleRom_PcAttackPals   = $CD686E  ; 2 B per !Battle_ActPalIdx: palette-step offset in bank $CD (PC attacks)
!BattleRom_PcTechPals     = $CD692C  ; the same for PC techs
!BattleRom_EnemyActPals   = $CD6A2C  ; the same for enemy attacks and techs
!BattleRom_Kind3Pals      = $CD6C2C  ; the same for kind 3
!BattleRom_ActFramesBank  = $D1      ; bank of the sprite-frame pointer tables and the packed frames
!BattleRom_PcAttackFrames = $D10000  ; 2 B per !Battle_ActFramesIdx: packed sprite frames in bank $D1 (PC attacks)
!BattleRom_ActFrames      = $D10060  ; the same for every other action
; Initial bytes +2/+3 of the 16 action objects, 6 B per object.
struct BattleRom_ActObjInit $D150A2
.Unk0:      skip 1      ; +0: to BattleActObj.Unk2
.Unk1:      skip 1      ; +1: to BattleActObj.Unk3
            skip 4
endstruct
!BattleRom_SlotTimes5     = $CCF83F  ; 1 B per PC slot (7 entries, 0-$1E): n * 5
!BattleRom_ActFrameBase   = $CCF7C0  ; 2 B per action frame 0-31: frame * $C0, its block in BattleActSprite
!BattleRom_Times16        = $CCF820  ; 1 B per n 0-8: n * 16 (sprite column/row to pixels)
!BattleRom_HitSetOffset   = $CCF829  ; 1 B per record set 0-5: set * $2C (11 records of 4 B), its offset in
                                      ; !Battle_ActPcHitAmount/Kind (opcodes $50-$55)
!BattleRom_HitNumDigitX   = $CCF5C4  ; 4 B per count of leading zeros 0-3: x offset of each of the four digit
                                      ; sprites from the battler's x (-16, -8, 0, 8 for four digits; one zero more
                                      ; moves them 4 to the left, which centres the digits shown)
; Palette lists: 2 B per entry, at !Battle_ActPalPtr + entry * 2 in bank $CD (opcode $60 and BattleAct_StepPalettes).
!BattleRom_PalListSet     = $CD0000  ; +0: colour set number
!BattleRom_PalListFlags   = $CD0001  ; +1: bit 7 = a set from !BattleRom_PalSets14, else from !BattleRom_PalSets6;
                                      ; bits 0-2 (bits 0-1 in BattleAct_StepPalettes) * 8 = where in !Battle_PaletteLive
!BattleRom_PalSets6       = $D14100  ; 6 B per colour set (3 colours)
!BattleRom_PalSets14      = $D14400  ; 14 B per colour set (7 colours)
!BattleRom_SpecialPals    = $D14D90  ; 24 B (12 colours) per entry: opcode $69's palette
!BattleRom_PcAttackSfxA   = $CD6D4C  ; 1 B per !Battle_ActPcAttackRec: sound id opcode $7C sends
!BattleRom_PcAttackSfxB   = $CD6DAC  ; 1 B per !Battle_ActPcAttackRec: sound id opcode $7D sends
!BattleRom_CommandWindowMap = $D15800 ; $180 B: command window tilemap
!BattleRom_CommandWindowFrame     = $D159FC  ; 84 B: one 7x6 command-window frame, 2 B (tile, attribute) per cell
!BattleRom_TechBoxMap      = $D15A50  ; $180 B: tech window frame tilemap
!BattleRom_ItemBoxMap      = $D15BD0  ; $180 B: item window frame tilemap
!BattleRom_AnimData       = $E40000  ; bank $E4 (the engine's !AnimRom): battler frame-id and frame-duration lists;
                                      ; a duration of 0 ends a list
!BattleRom_UnkE1DE80       = $E1DE80  ; 1 B per !Battler_Unk984D value: non-zero = send $FF instead of the target slot
                                      ; to the info-panel message call; purpose unknown

endif
