; ============================================================
; ram_menu.inc — Named WRAM / direct-page locations used by bank $C2
; (the menu/scene bank entered through BankC2_Entry0000/8000/8004).
;
; Why a file of its own: bank $C2 runs with its own direct page
; (DP=$0000, set by its entry code) and DB=$7E, and gives low WRAM a
; layout of its own: $0A00, $0D00 and the direct page mean other things
; here than in the field engine (ram_engine.inc: Obj_ScreenX at $0A00,
; Obj_VramTile at $0D00, the field direct page at $0100). Where both
; banks really share a location (the party list at $2980, the play-time
; bytes at $0400), the name here says so.
;
; Names start with `Menu` so they never collide with the engine and
; battle sets (asar lets a later define silently replace an earlier
; one). Conventions as ram_engine.inc: `!Name = $addr`, one comment per
; name with width, meaning and how it was inferred. Direct-page names
; are full addresses (DP=$0000 makes them the same); absolute ones are
; the bank-$7E offset, read with DB=$7E.
; ============================================================
!ram_menu_inc ?= 0
if !ram_menu_inc == 0
!ram_menu_inc = 1

; --- New-game data (Menu_InitNewGameData / Menu_ClearConfigAndFlags) ---
!Menu_FlagBlock7F = $7F0000              ; 512 B at $7F:0000-$01FF, zeroed for a new game. Its first byte
                                         ; is Eng_Unk7F0000 (gates Field_FadeToBankC2Mode5); probably the
                                         ; story/event flags (unverified)
!Menu_DataInitDone = $7F0061             ; 8-bit; the call at $C2:8048 runs Menu_InitNewGameData only while it
                                         ; is 0 (and the mode is 0), then sets it to 1; $C2:8D7E clears it
                                         ; and $C2:E65D sets it to 1 after their own unguarded calls;
                                         ; $C2:8D85 sets it to 2 when a slot check returns 0 (after JSR $C2:95BB)
!Menu_PlayTime = $0400                   ; 6 B: play-time counter, one byte per digit group, lowest first
                                         ; (Menu_TickPlayTime: frames, then up to the limits in
                                         ; Menu_PlayTimeLimits); the field engine calls the first byte
                                         ; Eng_Unk0400
!Menu_PlayTimeMaxed = $0406              ; 8-bit; set to 1 by Menu_TickPlayTime when the top group wraps
!Menu_PlayTimePaused = $0407             ; 8-bit; non-zero stops Menu_TickPlayTime (the field engine's
                                         ; Field_FadeBusy, $FF while it pauses); BankC2_MenuEntry clears it
!Menu_Unk0408 = $0408                    ; 9 B; a second copy of the default button map (and the byte
                                         ; after it), Menu_ClearConfigAndFlags; not read in matched code
!Menu_Unk2400 = $2400                    ; 512 B $2400-$25FF zeroed by Menu_InitNewGameData; use unknown
!Menu_CharRecords = $2600                ; character records, $50 B each (stride of the loops at $C2:8142
                                         ; and $C2:82F6); Menu_InitNewGameData fills $2600-$287F from
                                         ; MenuRom_CharRecordInit
!Menu_PartyOrder = $2980                 ; 9 B: character id per party position, $80 = empty; the first 3
                                         ; are the active party (the field's Party_Members), inferred
                                         ; from Menu_BuildPartyLists
!Menu_Config = $2990                     ; 32 B $2990-$29AF zeroed by Menu_ClearConfigAndFlags; the first
                                         ; 12 get MenuRom_DefaultConfig
!Menu_ButtonMap = $2993                  ; 8 B: the JOY1 mask behind each mapped button bit (Menu_MapButtons)
!Menu_Config1E = $7E29AE                 ; 8-bit; Menu_Config+$1E as a long address; C2Scene_LoadScene copies it
                                         ; to C2Scene_Unk02AE; use unknown
!Menu_Unk29AF = $29AF                    ; 16-bit; set to $0080 by Menu_InitNewGameData; use unknown
!Menu_Unk2C53 = $2C53                    ; 3 B $2C53-$2C55 zeroed by Menu_InitNewGameData (two 16-bit STZs)
!Menu_Unk2C7C = $2C7C                    ; 30 B $2C7C-$2C99 zeroed by Menu_InitNewGameData

; --- Joypad (Menu_PollPad / Menu_MapButtons), dp $F0-$FF with DP=$0000 ---
; Pad_Pressed ($00F0) and Pad_Unk00F6-$00F9 are named in ram_engine.inc,
; where the field reads them.
!Menu_PadHeld = $00F2                    ; 16-bit buttons held now (layout as Pad_Pressed)
!Menu_PadRepeat = $00F4                  ; 16-bit; newly pressed, plus the held buttons each time
                                         ; Menu_PadRepeatTimer runs out (auto-repeat)
!Menu_PadRepeatMapped = $00FA            ; 8-bit Menu_PadRepeat through the button map (Menu_MapButtons)
!Menu_PadRepeatDpad = $00FB              ; 8-bit copy of Menu_PadRepeat's high byte (the D-pad)
!Menu_PadRepeatDelay = $00FC             ; 8-bit; frames before (and between) auto-repeats: what
                                         ; Menu_PadRepeatTimer reloads from (the menu's NMI code sets it
                                         ; at $C2:847C and $C2:84B8)
!Menu_PadRepeatTimer = $00FD             ; 8-bit auto-repeat countdown
!Menu_PadPrevHeld = $00FE                ; 16-bit Menu_PadHeld of the frame before

; ==== Scene mode (BankC2_Entry0000) direct page ====
; BankC2_SceneBoot sets DP=$0000; C2Scene_ClearDp zeroes $00-$EF and
; C2Scene_NmiHandler copies the shadows below to the PPU every frame (that
; copy is how each one was identified). Names are dp offsets.
!C2Scene_DpClearStart = $00              ; first byte C2Scene_ClearDp zeroes ($00-$EF)
!C2Scene_InidispShadow = $1C             ; 8-bit; ORed with C2Scene_Brightness into INIDISP each NMI
                                         ; (C2Scene_ClearDp sets FORCED_BLANK)
!C2Scene_Brightness = $1D                ; 8-bit; see C2Scene_InidispShadow
!C2Scene_BgModeShadow = $1E              ; 8-bit BGMODE
!C2Scene_MosaicShadow = $1F              ; 8-bit MOSAIC
!C2Scene_Bg1HScroll = $20                ; 16-bit BG1HOFS
!C2Scene_Bg2HScroll = $22                ; 16-bit BG2HOFS
!C2Scene_Bg3HScroll = $24                ; 16-bit BG3HOFS
!C2Scene_Bg1VScroll = $26                ; 16-bit BG1VOFS
!C2Scene_Bg2VScroll = $28                ; 16-bit BG2VOFS
!C2Scene_Bg3VScroll = $2A                ; 16-bit BG3VOFS
!C2Scene_M7A = $2C                       ; 16-bit M7A (C2Scene_ClearDp: $0100 = 1.0)
!C2Scene_M7B = $2E                       ; 16-bit M7B
!C2Scene_M7C = $30                       ; 16-bit M7C
!C2Scene_M7D = $32                       ; 16-bit M7D (C2Scene_ClearDp: $0100 = 1.0)
!C2Scene_M7X = $34                       ; 16-bit M7X
!C2Scene_M7Y = $36                       ; 16-bit M7Y
!C2Scene_W12SelShadow = $38              ; 8-bit W12SEL
!C2Scene_W34SelShadow = $39              ; 8-bit W34SEL
!C2Scene_WObjSelShadow = $3A             ; 8-bit WOBJSEL
!C2Scene_WH0Shadow = $3B                 ; 8-bit WH0 (C2Scene_ClearDp: 1)
!C2Scene_WH1Shadow = $3C                 ; 8-bit WH1
!C2Scene_WH2Shadow = $3D                 ; 8-bit WH2 (C2Scene_ClearDp: 1)
!C2Scene_WH3Shadow = $3E                 ; 8-bit WH3
!C2Scene_WBgLogShadow = $3F              ; 8-bit WBGLOG
!C2Scene_WObjLogShadow = $40             ; 8-bit WOBJLOG
!C2Scene_TmShadow = $41                  ; 8-bit TM
!C2Scene_TsShadow = $42                  ; 8-bit TS
!C2Scene_TmwShadow = $43                 ; 8-bit TMW
!C2Scene_TswShadow = $44                 ; 8-bit TSW
!C2Scene_CgwselShadow = $45              ; 8-bit CGWSEL
!C2Scene_CgadsubShadow = $46             ; 8-bit CGADSUB
!C2Scene_FixedBlue = $47                 ; 8-bit fixed-color blue intensity (COLDATA with the blue bit)
!C2Scene_FixedRed = $48                  ; 8-bit fixed-color red intensity
!C2Scene_FixedGreen = $49                ; 8-bit fixed-color green intensity
!C2Scene_HdmaenShadow = $4A              ; 8-bit HDMAEN, written at the end of the NMI register copy
!C2Scene_FrameCounter = $4B              ; 8-bit; +1 every NMI, even when the update is skipped
                                         ; (C2Scene_WaitFrame waits for it to change)
!C2Scene_NmiFlags = $4C                  ; 8-bit; bit 0: run the NMI update (set again at its end),
                                         ; bit 1: upload C2Scene_PaletteBuf (one-shot); C2Scene_Main sets
                                         ; both ($C2:23C6)
!C2Scene_OamNext = $4D                   ; 8-bit; next OAM slot C2Scene_SprDrawNode fills (it uses the
                                         ; low 7 bits for the low table); the NMI zeroes it after
                                         ; C2Scene_SprResetLists with a 16-bit STZ (M=0 there), which
                                         ; zeroes C2Scene_TaskCur's low byte too
!C2Scene_TaskCur = $4E                   ; 16-bit address of the C2Scene_Task record being run
                                         ; (C2Scene_TaskRunAll); C2Scene_TaskSpawn copies a new task's
                                         ; parameters from it
!C2Scene_TaskHandler = $50               ; 16-bit; the running task's .Handler, the target of
                                         ; C2Scene_TaskCallHandler's JMP (abs)
!C2Scene_SprFramePtr = $55               ; 24-bit pointer to a sprite frame (a count byte, then 4-byte
                                         ; pieces): input of C2Scene_SprAdd, and the walk pointer of
                                         ; C2Scene_SprDrawNode
!C2Scene_VramQLock = $5E                 ; 8-bit; non-zero: C2Scene_VramQFlush does nothing
!C2Scene_VramQEnd = $5F                  ; 8-bit byte offset past the last C2Scene_VramQ entry (0 = empty)
!C2Scene_BgTileX = $E3                   ; 2 words, X in tiles (C2Scene_SetStartScroll sets both alike);
                                         ; word 0 for BG1, word 1 for BG2: C2Scene_DrawBgLayer stores 8x
                                         ; them into the scroll shadows and draws the map from them
!C2Scene_BgTileY = $E7                   ; 2 words, Y in tiles (as C2Scene_BgTileX)
!C2Scene_VramQBufPtr = $E0               ; 24-bit; reset to C2Scene_VramQBuf after each flush (probably
                                         ; where the next queued data is written; unverified)
                                         ; C2Scene_DrawBgLayer builds each tilemap column at this address
                                         ; (DB=$7E) and DMAs it from there to VRAM
!C2Scene_HeaderPtr = $ED                 ; 24-bit pointer to this scene's header in bank $C6 (set by
                                         ; C2Scene_GetHeaderPtr from C2SceneRom_HeaderTable); each header
                                         ; byte picks a pack for one C2Scene_Load* routine
                                         ; (C2Scene_Hdr* offsets in constants_menu.inc)

; One VRAM DMA request, 8 B, at dp $60 + 8 * n (C2Scene_VramQFlush).
struct C2Scene_VramQ $0060
.Src:   skip 2          ; A-bus source address
.Bank:  skip 1          ; A-bus source bank
.Dest:  skip 2          ; VRAM word address
.Size:  skip 2          ; byte count
.Vmain: skip 1          ; VMAIN value for the transfer
endstruct align 8

; Scratch: the scene code uses dp $00-$1B as temporaries (the PPU shadows
; start at $1C). Each routine gives the slots it uses an alias next to its
; header.
!C2Tmp_00 = $00                          ; 1-2 B scratch
!C2Tmp_01 = $01                          ; 1 B scratch
!C2Tmp_02 = $02                          ; 1-2 B scratch
!C2Tmp_04 = $04                          ; 1-2 B scratch
!C2Tmp_05 = $05                          ; 1 B scratch
!C2Tmp_06 = $06                          ; 1-2 B scratch
!C2Tmp_08 = $08                          ; 1-2 B scratch
!C2Tmp_09 = $09                          ; 1-2 B scratch
!C2Tmp_0A = $0A                          ; 1-2 B scratch
!C2Tmp_0C = $0C                          ; 1-2 B scratch
!C2Tmp_0E = $0E                          ; 1-2 B scratch
!C2Tmp_10 = $10                          ; 1-2 B scratch
!C2Tmp_13 = $13                          ; 1-2 B scratch
!C2Tmp_12 = $12                          ; 1-2 B scratch
!C2Tmp_14 = $14                          ; 1-2 B scratch
!C2Tmp_16 = $16                          ; 1 B scratch
!C2Tmp_18 = $18                          ; 1-2 B scratch
!C2Tmp_1A = $1A                          ; 1-2 B scratch

; ==== Text window (TextWin_Init / TextWin_Step) ====
; A block at $0200 that both run on as their direct page; names are dp
; offsets (DP=!TextWin_Dp). The callers fill the first part (the field at
; $C0:20F4-$C0:2121, absolute $020C-$0214).
!TextWin_Dp = $0200                      ; the block's address, loaded into D
!TextWin_StrIndex = $0C                  ; 8-bit string number: index into TextWin_StrTable
!TextWin_StrTable = $0D                  ; 24-bit pointer to a table of 16-bit string addresses (in the
                                         ; table's bank)
!TextWin_GfxBuf = $10                    ; 24-bit output buffer (the field passes $7E:F000); probably the
                                         ; glyph pixels ($C2:5DC4 reads it, unmatched)
!TextWin_StepCount = $13                 ; 8-bit; the field sets 1 before each TextWin_Step; state 0
                                         ; decrements it per glyph and sets status $10 at 0 (probably
                                         ; characters per step)
!TextWin_Mode = $14                      ; 8-bit; the field passes 0. Bit 7 or the value TextWin_ModeUnk2:
                                         ; pen X starts at 0; low nibble 0 or not picks the glyph
                                         ; routine at $C2:5E10 (unmatched)
!TextWin_Status = $15                    ; 8-bit; TextWin_CheckStatus dispatches on it ($00-$20): 0
                                         ; = idle; TextWin_Init sets TextWin_StatusStart; the field
                                         ; reads it after each step
!TextWin_Unk17 = $17                     ; 8-bit; zeroed with each pen reset; +1 per glyph ($C2:5E30)
!TextWin_State = $30                     ; 8-bit index into TextWin_StateTable
!TextWin_TextPtr = $31                   ; 24-bit pointer to the next byte of the string
!TextWin_PenX = $34                      ; 8-bit pen X in pixels (inferred: $C2:5DC4 uses bits 0-2 as the
                                         ; shift within a tile and bits 3-7 as the tile)
!TextWin_Unk3D = $3D                     ; 24-bit; TextWin_Init sets it to $00:0200 (= TextWin_Dp); use not
                                         ; traced

; --- Scene mode absolute RAM ---
!C2Scene_Unk0B20 = $0B20                 ; 16 B $0B20-$0B2F zeroed by C2Scene_ClearPalette (right after
                                         ; C2Scene_PaletteBuf); use unknown
!C2Scene_TaskRecords = $0B30             ; 64 C2Scene_Task records, $0B30-$1B2F (C2Scene_TaskRunAll walks
                                         ; them all; C2Scene_TaskClearAll frees them all)
!C2Scene_TaskRecordsEnd = $1B30          ; first address past the records
!C2Scene_Unk1B30 = $1B30                 ; 8-bit; zeroed by C2Scene_ClearUnk1B30; use unknown
!C2Scene_Unk1B31 = $1B31                 ; 8-bit; zeroed by C2Scene_ClearUnk1B30; use unknown
!C2Scene_Flag0Copy = $1BA6               ; 8-bit copy of Eng_Unk7F0000 (C2Scene_SaveFlagTail)
!C2Scene_FlagTailCopy = $1BA7            ; 16 B copy of $7F:01F0-$01FF, the end of Menu_FlagBlock7F
                                         ; (C2Scene_SaveFlagTail; C2Scene_RestoreFlagTail writes it back)
!C2Scene_StartX = $0283                  ; 16-bit; Loc_EntryX * 8 (C2Scene_SetStartPos): probably pixels
!C2Scene_StartY = $0285                  ; 16-bit; Loc_EntryY * 8
!C2Scene_SoundCmdState = $1BEC           ; 8-bit: 0 = nothing to send; 1 = a command waits in the
                                         ; driver block $1E00-$1E03 (set by the unmatched code at
                                         ; $C2:2ED9, which copies it from $1BE8-$1BEB);
                                         ; C2Scene_SoundCmdSending while Audio_DriverCommand runs.
                                         ; C2Scene_WaitFrames and C2Scene_MainLoop send it, once per frame
!C2Scene_Unk1BF6 = $1BF6                 ; 8-bit; zeroed by C2Scene_Main; use unknown
!C2Scene_Mode = $027C                    ; 8-bit; selects C2Scene_MainLoop's handler (index into
                                         ; C2Scene_ModeTable); who sets it is not traced
!C2Scene_Unk027D = $027D                 ; 8-bit; zeroed by C2Scene_LoadScene (next to C2Scene_Mode); use unknown
!C2Scene_Unk0280 = $0280                 ; 3 B $0280-$0282 zeroed by C2Scene_LoadScene; use unknown
!C2Scene_Unk0294 = $0294                 ; 8-bit; C2Scene_LoadScene clears bit 2 (C2Scene_Unk0294Bit2); use
                                         ; unknown
!C2Scene_Unk02AE = $02AE                 ; 8-bit; C2Scene_LoadScene copies the byte at Menu_Config+$1E into it;
                                         ; use unknown
!C2Scene_Unk02B1 = $02B1                 ; 3 B $02B1-$02B3 zeroed by C2Scene_LoadScene; use unknown
!C2Scene_Unk1B32 = $1B32                 ; 3 words $1B32-$1B37 set to $FFFF by C2Scene_LoadScene; use unknown
!C2Scene_ListACount = $1B38              ; 8-bit entry count of C2Scene_ListA (C2Scene_LoadLists)
!C2Scene_ListBCount = $1B39              ; 8-bit entry count of C2Scene_ListB
!C2Scene_ListCCount = $1B3A              ; 8-bit entry count of C2Scene_ListC (ListD's count is not kept)
!C2Scene_Unk1B58 = $1B58                 ; 8-bit; zeroed by C2Scene_LoadScene; use unknown
!C2Scene_Unk1B59 = $1B59                 ; 8-bit; zeroed by C2Scene_LoadScene; use unknown
!C2Scene_Unk1BF7 = $1BF7                 ; 8-bit; zeroed by C2Scene_LoadScene; use unknown
!C2Scene_FlagTailByte1 = $1BA8           ; = C2Scene_FlagTailCopy+1, the copy of $7F:01F1; bit 7 picks the
                                         ; palette C2Scene_LoadLocExtraGfx loads for Loc_Id $01F1

; Parameter block of Decomp_ToWramVec (the same bytes as Battle_DecompSrc..
; in ram_battle.inc; the scene loaders fill it with DB=$00).
!Menu_DecompSrc = $0300                  ; 16-bit address of the packed data
!Menu_DecompSrcBank = $0302              ; 8-bit its bank
!Menu_DecompDest = $0303                 ; 16-bit WRAM destination address
!Menu_DecompDestBank = $0305             ; 8-bit its bank ($7E or $7F; $00 for low WRAM)

; Scene data unpacked into WRAM by the C2Scene_Load* routines (each name
; says what is inferred; "Unk" ones are only known by where they go).
!C2Scene_Metatiles = $7E3000             ; 8 B per 16x16 metatile: tile words top-left, top-right,
                                         ; bottom-left, bottom-right (C2Scene_DrawMetatile); BG1's set
                                         ; here, BG2's at $7E:3800 (C2Scene_LayerMetatiles)
!C2Scene_BgMaps = $7E4000                ; one byte (metatile number) per 16x16 cell, 96 x 64 cells per
                                         ; layer ($1800 B); BG1's map here, BG2's at $7E:5800
                                         ; (C2Scene_LayerMaps)
!C2Scene_Unk7000 = $7E7000               ; C2Scene_LoadUnk7000's pack; use unknown
!C2Scene_Unk7200 = $7E7200               ; C2Scene_LoadUnk7200's pack; use unknown
!C2Scene_ListA = $7E7E00                 ; 7-byte entries (C2Scene_LoadLists); use unknown
!C2Scene_ListC = $7E8180                 ; 3-byte entries; use unknown
!C2Scene_ListB = $7E8300                 ; 3-byte entries; use unknown
!C2Scene_ListD = $7E8480                 ; 2-byte entries; use unknown
!C2Scene_HdmaArea = $7E8621              ; $800 B $7E:8621-$8E20 zeroed by C2Scene_ClearHdmaArea (holds
                                         ; C2Scene_HdmaValues and C2Scene_HdmaTable)
!C2Scene_UnkB800 = $7EB800               ; C2Scene_LoadUnkB800's pack; use unknown
!C2Scene_UnkC000 = $7EC000               ; C2Scene_LoadUnkC000's pack; use unknown
!C2Scene_UnkC600 = $7EC600               ; C2Scene_LoadUnkC600's pack; use unknown
!C2Scene_UnkC800 = $7EC800               ; C2Scene_LoadUnkC800's pack; use unknown
!C2Scene_ListPack = $7F0400              ; C2Scene_LoadLists unpacks the four lists' source here
!C2Scene_ScriptBuf = $7F0400             ; then C2Scene_LoadScript unpacks the scene's script over it;
                                         ; C2Scene_LoadScene starts a C2Scene_TaskRunScript task on it
!C2Scene_SaveDp = $7F3F00                ; C2Scene_SaveState's copy of dp $00-$EF
!C2Scene_SaveLowRam = $7F2800            ; its copy of $0700-$1DFF
!C2Scene_SaveSprNodes = $7F4000          ; its copy of $7E:B000-$B507 (C2Scene_SprNodes to the list heads)
!C2Scene_SaveBgMaps = $7F4600            ; its copy of $7E:4000-$6FFF (C2Scene_BgMaps and after)
!C2Scene_SaveUnk7200 = $7F7600           ; its copy of $7E:7200-$7DFF
!C2Scene_SaveLists = $7F8200             ; its copy of $7E:7E00-$85FF (C2Scene_ListA to ListD)
!C2Scene_PaletteStage = $7F8C00          ; 512 B: the scene's palettes are built here, DMAed to CGRAM and
                                         ; copied to C2Scene_PaletteBuf (C2Scene_LoadVram)
!C2Scene_ObjPal0 = $7F8D00               ; colors $80-$83 of C2Scene_PaletteStage (sprite palette 0, colors
                                         ; 0-3): C2Scene_LoadVram sets black and three grays
!C2Scene_PartyPalDest = $7F8D80          ; colors $C0, $D0, $E0 (sprite palettes 4-6, 32 B apart): the
                                         ; party members' palettes (C2Scene_LoadPalettes)
!C2Scene_PartyPalSrc = $7F8E00           ; the party palettes pack, 32 B per character
                                         ; (C2Scene_LoadPalettes)
!C2Scene_DecompBuf = $7F9000             ; staging buffer for graphics packs before their VRAM DMA
!C2Scene_PartyGfxSrcB = $7FAC00          ; inside the unpacked party graphics pack: $40 B per character
                                         ; here and at +$200 (C2Scene_CopyPartyGfxB)
!C2Scene_PartyGfx = $7FB000              ; $1000 B: the party's graphics, built by C2Scene_LoadPartyGfx
!C2Scene_PartyGfxB = $7FBC00             ; inside it: the second part of each member's graphics, $40 B per
                                         ; member here and at +$200 (C2Scene_CopyPartyGfxB)

; One 16x16 metatile (C2Scene_DrawMetatile), 8 B, at the layer's
; C2Scene_LayerMetatiles base + 8 * the map byte; each field a BG tilemap
; word.
struct C2Scene_Metatile $0000
.TopLeft:     skip 2
.TopRight:    skip 2
.BottomLeft:  skip 2
.BottomRight: skip 2
endstruct

!C2Scene_PaletteBuf = $0920              ; 512 B CGRAM shadow, uploaded by the NMI when C2Scene_NmiFlags
                                         ; bit 1 is set
!C2Scene_VramQBuf = $7EF000              ; see C2Scene_VramQBufPtr
!C2Scene_HdmaValues = $7E8A21            ; 10 words copied by every NMI update into C2Scene_HdmaTable
!C2Scene_HdmaValueA916 = $7EA916         ; word copied by every NMI update into C2Scene_HdmaTableA918

; Five 13-byte records at $7E:8A35; the NMI writes the word after the
; first and the fourth byte of each from C2Scene_HdmaValues. Probably HDMA
; tables (a line count, then a value), inferred only from that layout.
struct C2Scene_HdmaTable $7E8A35
.Count0: skip 1
.Value0: skip 2
.Count1: skip 1
.Value1: skip 2
         skip 7
endstruct align 13
!C2Scene_HdmaTableA918 = $7EA918         ; probably an HDMA table of 3-byte entries (count, word):
                                         ; the NMI writes the word of entries 0-3

;
; A scene task: one 64-byte record of C2Scene_TaskRecords, run once per
; frame by C2Scene_TaskRunAll (from the NMI) while .Handler is non-zero.
; Fields from .Params on are copied from the spawning task by
; C2Scene_TaskSpawn; what most of them hold depends on the handler.
struct C2Scene_Task $0000
.Handler:    skip 2     ; +$00 handler address in bank $C2 (0 = free slot)
.Unk02:      skip 1     ; +$02 zeroed by C2Scene_TaskSpawn
.Frames:     skip 2     ; +$03 +1 after each frame the handler returns C=0
.Params:     skip 2     ; +$05 first byte copied from the spawner
.ScriptPtr:  skip 2     ; +$07 C2Scene_TaskSpawnScript: 16-bit address of the script
.ScriptBank: skip 1     ; +$09 C2Scene_TaskSpawnScript: its bank
.Unk0A:      skip 1     ; +$0A zeroed by C2Scene_TaskSpawnScript
             skip 4
.SprAttr:    skip 1     ; +$0F C2Scene_SprAdd: the new node's .Attr
.SprTile:    skip 2     ; +$10 C2Scene_SprAdd: the new node's .Tile
             skip 2
.SprX:       skip 2     ; +$14 C2Scene_SprAdd: the new node's .X
             skip 2
.SprY:       skip 2     ; +$18 C2Scene_SprAdd: the new node's .Y
             skip $26
endstruct

; One node of the scene's sprite list (C2Scene_SprAdd, C2Scene_SprDrawNode),
; 16 B, at C2Scene_SprNodes + $10 * n. The list heads C2Scene_SprActiveHead
; and C2Scene_SprFreeHead are only .Prev and .Next.
struct C2Scene_SprNode $0000
.Prev:  skip 2          ; address of the previous node (or of the head)
.Next:  skip 2          ; address of the next node (or of the head)
.X:     skip 2          ; 16-bit screen (or, with C2Scene_SprAttrScroll, BG2) X
.Y:     skip 2          ; 16-bit Y; the active list is kept in falling .Y order
.Attr:  skip 1          ; C2Scene_SprAttr* flags; bits 1-5 become OAM attribute bits 1-5
                        ; (palette and priority)
.Tile:  skip 2          ; bits 0-13 added to each piece's tile word; bit 14
                        ; (C2Scene_SprTileLarge in the high byte) large sprites; bit 15
                        ; (C2Scene_SprTileBehind) appended at the end of the list
.Frame: skip 3          ; 24-bit pointer to the frame (see C2Scene_SprFramePtr)
        skip 2
endstruct

!C2Scene_SprNodes = $7EB000              ; 64 C2Scene_SprNode records, $7E:B000-$B3FF
!C2Scene_SprLinkInit = $7EB400           ; 64 x 4 B: each node's .Prev and .Next on a free list
                                         ; (built by C2Scene_SprInitLinks, copied into the nodes every
                                         ; frame by C2Scene_SprResetLists)
!C2Scene_SprActiveHead = $7EB500         ; 4 B .Prev/.Next: head of the list C2Scene_SprDrawList draws
!C2Scene_SprFreeHead = $7EB504           ; 4 B .Prev/.Next: head of the free nodes

endif
