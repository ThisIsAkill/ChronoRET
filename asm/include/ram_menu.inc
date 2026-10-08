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
                                         ; and $C2:E65D sets it to 1 after their own unguarded calls
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
!Menu_Unk29AF = $29AF                    ; 16-bit; set to $0080 by Menu_InitNewGameData; use unknown
!Menu_Unk2C53 = $2C53                    ; 3 B $2C53-$2C55 zeroed by Menu_InitNewGameData (two 16-bit STZs)
!Menu_Unk2C7C = $2C7C                    ; 30 B $2C7C-$2C99 zeroed by Menu_InitNewGameData

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
!C2Scene_Unk4D = $4D                     ; 8-bit; zeroed by the NMI after C2Scene_Unk0C4D
!C2Scene_VramQLock = $5E                 ; 8-bit; non-zero: C2Scene_VramQFlush does nothing
!C2Scene_VramQEnd = $5F                  ; 8-bit byte offset past the last C2Scene_VramQ entry (0 = empty)
!C2Scene_VramQBufPtr = $E0               ; 24-bit; reset to C2Scene_VramQBuf after each flush (probably
                                         ; where the next queued data is written; unverified)

; One VRAM DMA request, 8 B, at dp $60 + 8 * n (C2Scene_VramQFlush).
struct C2Scene_VramQ $0060
.Src:   skip 2          ; A-bus source address
.Bank:  skip 1          ; A-bus source bank
.Dest:  skip 2          ; VRAM word address
.Size:  skip 2          ; byte count
.Vmain: skip 1          ; VMAIN value for the transfer
endstruct align 8

; --- Scene mode absolute RAM ---
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

endif
