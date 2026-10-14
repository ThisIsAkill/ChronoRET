; ============================================================
; Bank $C7 — sound driver interface (65816 side)
; File offset 0x070000 (bank $C7 = ROM offset $70000)
;
; The 65816 half of the sound system: it boots the SPC700 through the
; APU's IPL ROM (Audio_Boot), then takes commands from the 4-byte block
; Audio_CmdId..Audio_CmdArg2 ($1E00-$1E03) and either passes them to the
; driver or loads a song: the song's samples into ARAM sample slots, their
; directory and parameter words, the song data and a 36-byte extra block
; (Audio_CmdLoadSong and the routines it falls into). The other banks
; reach it only through the four JMP vectors at $C7:0000; nothing here
; calls out of the bank.
;
; Matched: $C7:0000-$C7:0E10, the code ($0000-$0A97) and the tables it
; reads ($0010-$0037, $0A98-$0E10). The rest of the bank (from $0E11:
; per-song tables, the SPC700 program at $24C3, the upload blocks and
; the samples) is still original bytes; the code names what it reads
; there with the !AudioRom_* defines (constants_engine.inc).
;
; Every routine here runs with DP = !DP_Audio ($1E00) and DB = 0 once
; Audio_Boot or Audio_RunCommand has set them; their RAM is the
; Audio_* page in ram_engine.inc, used as dp operands !Name-!DP_Audio.
; The port protocol (header step, data steps, sequence values) is
; described above the !Audio_Xfer* constants; it is read from the 65816
; side only, the SPC700 program is not disassembled.
; ============================================================

arch snes.cpu
hirom

incsrc "../hardware.inc"

; ============================================================
; Callers (1 JSL site): GameLoop ($C0:0053).
; Callers of Audio_DriverCommand (57 JSL sites): LocLoad_AudioSetup ($C0:1B73, $C0:1B8B),
;   Audio_PlaySfxAtLeader ($C0:1BA2), MusicCueDispatch ($C0:1BCE, $C0:1BDF), AudioFadeDispatch
;   ($C0:1C2A, $C0:1C3A, $C0:1C52, $C0:1C65, $C0:1C78, $C0:1C89, $C0:1CA9, $C0:1CB7, $C0:1CCF,
;   $C0:1CE2, $C0:1CF5), Evt_OpE8_SoundCmd18 ($C0:3C26), Evt_OpEA_PlayMusic ($C0:3C43),
;   Evt_OpEB_SoundCmds81To83 ($C0:3C69, $C0:3C7C, $C0:3C8F), Evt_OpEC_SoundCmd ($C0:3CB4),
;   BattleMenu_EnqueueReadyBattler ($C1:1B50), Battle_PlaySfx0 ($C1:1B62), BattleSys_RunAction
;   ($C1:40DD), BattleAct_OpSound ($C1:61B5), BattleAct_OpSoundCalc ($C1:61DF),
;   BattleAct_PlayPcAttackSfx ($C1:620F), C2Scene_WaitFrames ($C2:0462), C2Scene_ModeIdle
;   ($C2:23F9), C2Scene_Mode2 ($C2:24F0, $C2:2501), C2Scene_Mode8 ($C2:264E),
;   C2Scene_ZoneSoundAtEntry ($C2:2F49), C2Scene_DialInput ($C2:6BE9), Menu_InitSystems ($C2:80B2,
;   $C2:80C5, $C2:80CE, $C2:80E1, $C2:80EA), Menu_SendSoundArg ($C2:EB1A), C3_SongCheck ($C3:09D1),
;   C3_RunScript ($C3:0BE9), BattleCD_ApuCmd81 ($CD:03AB), BattleCD_RunEndFx ($CD:0D70, $CD:0D81)
;   and unmatched ($C2:C033, $C2:CBF3, $C2:CC09, $C2:E6A1, $CD:3B7D, $CD:3E54, $CD:3E70, $FF:FC82,
;   $FF:FC97, $FF:FF24, $FF:FF39).
; Callers of Audio_VecSendSampleDir (1 JSL site): unmatched ($E6:F15C).
; Entry vectors and boot tables ($C7:0000–$C7:0037)
; ============================================================

; $C7:0000 — Audio_DriverInit (16 bytes, $0000–$000F)
; The bank's entry block: four 3-byte JMPs, each followed by a NOP.
; The names are the ones the callers use:
;   - $0000 Audio_DriverInit: JMP Audio_Boot (JSL from GameLoop at
;     boot and on each re-entry through $C0:02CA).
;   - $0004 Audio_DriverCommand: JMP Audio_RunCommand, the command
;     entry. Bank $C1 calls the same address Audio_ProcessEntry, set
;     equal to it after this block (asar cannot alias one label to
;     another, so the address is given), so the battle code keeps its
;     name.
;   - $0008 Audio_VecLoadNewSamples: JMP Audio_LoadNewSamples, the
;     middle of a song load. No caller found. A JSL here would end in
;     Audio_CommandDone, which pulls ten bytes of registers that were
;     never pushed, and it would run with the caller's DP and DB.
;   - $000C Audio_VecSendSampleDir: JMP Audio_SendSampleDir, the same
;     kind of mid-load entry, with the same problem.
; Callers note: xref also reports one JSL to $C7:000C at $E6:F15C as
;   CONFIRMED, by its sweep only; tools/code_survey.py finds no code in
;   bank $E6, so it is probably data. Not checked further.
; Entry: M any, X any, DP any, DB any (nothing is used here; each
;        target sets up its own state)
; Exit:  through the jump target; nothing is changed here
; Sub-entries: Audio_DriverCommand, Audio_VecLoadNewSamples,
;   Audio_VecSendSampleDir.
org $C70000
Audio_DriverInit:
    JMP Audio_Boot
    NOP
Audio_DriverCommand:                    ; header: see Audio_DriverInit
    JMP Audio_RunCommand
    NOP
Audio_VecLoadNewSamples:                ; header: see Audio_DriverInit
    JMP Audio_LoadNewSamples
    NOP
Audio_VecSendSampleDir:                 ; header: see Audio_DriverInit
    JMP Audio_SendSampleDir
    NOP

Audio_ProcessEntry = $C70004            ; bank $C1's name for Audio_DriverCommand

; $C7:0010 — Audio_BootBlockPtrs (12 bytes, $0010–$001B)
; The six blocks Audio_Boot sends through the IPL ROM, in this order, as
; bank $C7 addresses. Each block starts with its 16-bit length; the
; bytes after it go to the ARAM address in the same slot of
; Audio_BootBlockAram. Block 0 is the SPC700 program ($1BEF bytes), and
; Audio_Boot starts it at !AudioAram_Driver afterwards.
Audio_BootBlockPtrs:
    dw !AudioRom_SpcDriver              ; $C7:24C3, $1BEF bytes -> $0200
    dw !AudioRom_Block2F00              ; $C7:4309, $1800 bytes -> $2F00
    dw !AudioRom_Block4700              ; $C7:40B4, $0201 bytes -> $4700
    dw !AudioRom_Block1E00              ; $C7:42B7, $0024 bytes -> $1E00
    dw !AudioRom_Block1F80              ; $C7:42DD, $0014 bytes -> $1F80
    dw !AudioRom_Block1F00              ; $C7:42F3, $0014 bytes -> $1F00

; $C7:001C — Audio_BootBlockAram (12 bytes, $001C–$0027)
; The ARAM destination of each Audio_BootBlockPtrs block (sent in
; APUIO2/3 with the IPL ROM's transfer command).
Audio_BootBlockAram:
    dw !AudioAram_Driver
    dw !AudioAram_Block2F00
    dw !AudioAram_Block4700
    dw !AudioAram_Dir
    dw !AudioAram_ParamB
    dw !AudioAram_ParamA

; $C7:0028 — Audio_TableDirectory (16 bytes, $0028–$0037)
; Eight bank $C7 addresses: the tables the code below reads. No reader
; of this list was found in 65816 code (a byte search of the ROM for
; LDA long / LDA long,X operands in $C7:0028-$0037 finds none); a list
; for an outside tool, probably.
Audio_TableDirectory:
    dw Audio_SongTable
    dw Audio_SampleTable
    dw Audio_SampleLoop
    dw Audio_SampleParamB
    dw Audio_SampleParamA
    dw !AudioRom_SongSamples
    dw Audio_SongCount
    dw !AudioRom_Block2F00Alt

; ============================================================
; Boot and command dispatch ($C7:0038–$C7:01A0)
; ============================================================

; $C7:0038 — Audio_Boot (264 bytes, $0038–$013F)
; Starts the sound driver from nothing, through the APU's IPL ROM:
;   1. Pushes B, D, P, A, X, Y (16-bit) for Audio_CommandDone, sets
;      DB = 0 and DP = !DP_Audio.
;   2. Writes !Audio_ResetKick1 to APUIO1 and !Audio_ResetKick0 to
;      APUIO0, again and again, until APUIO0/1 read as a word give the
;      IPL's ready signature !Audio_IplReady ($AA, $BB). The two values
;      probably make a driver that is already running jump back to the
;      IPL ROM (the re-entry case; not traced in the SPC700 program).
;   3. Block 0: APUIO2/3 = its ARAM address, APUIO1 = APUIO0 =
;      !Audio_IplKick; waits for APUIO0 to echo it.
;   4. Each block (Audio_BootBlockPtrs, length word first): for each
;      byte, APUIO1 = the byte and APUIO0 = a counter that starts at 0;
;      waits for the echo, then counts up. After the last byte the next
;      value is the last one sent + 4 (+ 5 if that gives 0: the IPL
;      protocol wants a nonzero value at least 2 above the last). For blocks
;      1-5: APUIO2/3 = the next ARAM address, APUIO1 = APUIO0 = that
;      counter (nonzero: "another block"), wait for the echo, and the
;      next block starts again from 0.
;   5. After block 5: APUIO2/3 = !AudioAram_Driver, APUIO1 = 0 (start
;      the program there), APUIO0 = the counter; waits for the echo,
;      then writes 0 to APUIO0.
;   6. Clears the page !DP_Audio ($1E00-$1EFF, A = 0), sets
;      Audio_SlotAram (slot 0's start), Audio_SampleBase and
;      Audio_FreeAram to !AudioAram_Block4700 + block 2's length (the
;      samples go right after that block), runs a delay loop of
;      !Audio_BootDelay, sets Audio_Unk1EFA = 0, Audio_Unk1EFB = $C7,
;      Audio_EchoDelay = !Audio_DefaultEchoDelay with its
;      Audio_EchoPage, Audio_Unk1EF1 = 0 and Audio_SongLoading =
;      !Audio_SongIdle, and leaves through Audio_CommandDone.
; Every wait for an echo here is unbounded (no timeout).
; Callers (1 JMP site): Audio_DriverInit ($C7:0000).
; Entry: M any, X any, DP any, DB any (all saved; it sets M=1, X=0
;        (16-bit), DP=!DP_Audio and DB=0 itself)
; Exit:  through Audio_CommandDone: A, X, Y, P, DP and DB as on entry
;        (pulled at 16 bits, then P); Audio_CmdId and the rest of
;        $1E00-$1EFF as set above (the clear also zeroes
;        Audio_Unk1E10 and Audio_BlockInAram, which matches the $2F00
;        block it has just sent)
; Callees: Audio_CommandDone (JMP)
Audio_Boot:
    PHB
    PHD
    PHP
    REP #$20
    REP #$10
    PHA
    PHX
    PHY
    SEP #$20
    LDA.b #$00
    PHA
    PLB                                 ; DB = 0
    LDX.w #!DP_Audio
    PHX
    PLD                                 ; DP = $1E00
    LDX.w #!Audio_IplReady
.wait_ipl:
    LDA.b #!Audio_ResetKick1
    STA.w APUIO1
    LDA.b #!Audio_ResetKick0
    STA.w APUIO0
    CPX.w APUIO0                        ; 16-bit: APUIO0 and APUIO1
    BNE .wait_ipl
    LDX.w #$0000                        ; X = block number x 2
    LDA.l Audio_BootBlockAram
    STA.w APUIO2
    LDA.l Audio_BootBlockAram+1
    STA.w APUIO3
    LDA.b #!Audio_IplKick
    STA.w APUIO1
    STA.w APUIO0
.wait_kick:
    CMP.w APUIO0
    BNE .wait_kick
.next_block:
    LDA.b #$00
    XBA                                 ; B = the byte counter, from 0
    LDA.l Audio_BootBlockPtrs,X
    STA.b !Audio_Ptr-!DP_Audio
    LDA.l Audio_BootBlockPtrs+1,X
    STA.b !Audio_Ptr+1-!DP_Audio
    LDA.b #!AudioRom_SpcDriver>>16
    STA.b !Audio_Ptr+2-!DP_Audio
    LDY.w #$0000
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    CLC
    ADC.b #2
    STA.b !Audio_Count-!DP_Audio        ; Audio_Count = length + 2: the end index
    INY
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    ADC.b #0
    STA.b !Audio_Count+1-!DP_Audio
    INY
.send_byte:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO1
    XBA
    STA.w APUIO0
.wait_byte:
    CMP.w APUIO0
    BNE .wait_byte
    INC A
    XBA
    INY
    CPY.b !Audio_Count-!DP_Audio
    BNE .send_byte
    XBA
    INC A
    INC A
    INC A
    BNE .kick_ok
    INC A                               ; never 0
.kick_ok:
    INX
    INX
    CPX.w #!Audio_NumBootBlocks
    BEQ .start_driver
    XBA
    LDA.l Audio_BootBlockAram,X
    STA.w APUIO2
    LDA.l Audio_BootBlockAram+1,X
    STA.w APUIO3
    XBA
    STA.w APUIO1
    STA.w APUIO0
.wait_next:
    CMP.w APUIO0
    BNE .wait_next
    BRA .next_block
.start_driver:
    XBA
    LDA.b #!AudioAram_Driver>>8
    STA.w APUIO3
    LDA.b #!AudioAram_Driver
    STA.w APUIO2
    LDA.b #$00
    STA.w APUIO1                        ; 0: start the program at APUIO2/3
    XBA
    STA.w APUIO0
.wait_start:
    CMP.w APUIO0
    BNE .wait_start
    XBA                                 ; A = 0
    STA.w APUIO0
    LDX.w #!Audio_PageBytes
.clear_page:
    STA.w !DP_Audio-1,X
    DEX
    BNE .clear_page
    REP #$20
    LDA.l !AudioRom_Block4700           ; block 2's length
    CLC
    ADC.w #!AudioAram_Block4700
    STA.b !Audio_SampleBase-!DP_Audio
    STA.b !Audio_SlotAram-!DP_Audio
    STA.b !Audio_FreeAram-!DP_Audio
    LDX.w #!Audio_BootDelay
.delay:
    DEX
    BNE .delay
    SEP #$20
    LDA.b #$00
    STA.b !Audio_Unk1EFA-!DP_Audio
    LDA.b #!AudioRom_SpcDriver>>16
    STA.b !Audio_Unk1EFB-!DP_Audio
    LDA.b #!Audio_DefaultEchoDelay
    STA.b !Audio_EchoDelay-!DP_Audio
    ASL A
    ASL A
    ASL A
    EOR.b #!Eng_Invert8
    INC A
    CLC
    ADC.b #!Audio_EchoTopPage
    STA.b !Audio_EchoPage-!DP_Audio     ; $F1 - 8 x delay
    STZ.b !Audio_Unk1EF1-!DP_Audio
    LDA.b #!Audio_SongIdle
    STA.b !Audio_SongLoading-!DP_Audio
    JMP Audio_CommandDone

; $C7:0140 — Audio_RunCommand (97 bytes, $0140–$01A0)
; Runs the command in Audio_CmdId (arguments Audio_CmdArg0-2), then
; clears Audio_CmdId. Saves B, D, P, A, X, Y (16-bit), sets DB = 0 and
; DP = !DP_Audio. While Audio_SongLoading has bit 7 clear (a song load
; is running, so this is a nested call) or Audio_CmdId is 0 it does
; nothing; the command is dropped all the same (Audio_CommandDone zeroes
; Audio_CmdId). Otherwise by command:
;   $80-$FF and $18-$2F: Audio_CmdSend (to the APU as it is);
;   $10-$17: Audio_SongCmdTable entry (command & $0F) ($10, $11, $14,
;            $15 load a song; the others do nothing);
;   $30-$3F: Audio_CmdSongAlias (becomes a $10 command, then comes
;            back to Audio_RunCommand_Dispatch);
;   $70: Audio_CmdBlockVariant; $71: Audio_CmdSwapSample;
;   $01-$0F, $40-$6F, $72-$7F: nothing.
; Audio_CommandDone ($0192) is the common exit of every command (and of
; Audio_Boot): it zeroes Audio_CmdId and pulls Y, X, A (16-bit), P, D
; and B. Audio_RunCommand_Dispatch ($0155) is the sort above, entered
; again by Audio_CmdSongAlias.
; Callers note: reached through Audio_DriverCommand (also called
;   Audio_ProcessEntry), the JMP at $C7:0004. Audio_CommandDone is the
;   tail of Audio_Boot and of every command routine; Audio_StartSong also
;   reaches it after dropping its own return address.
; Callers (1 JMP site): Audio_DriverCommand ($C7:0004).
; Callers of Audio_RunCommand_Dispatch (1 JMP site): Audio_CmdSongAlias ($C7:0731).
; Callers of Audio_CommandDone (8 JMP sites): Audio_Boot ($C7:013D), Audio_SendSongData ($C7:0619),
;   Audio_CmdSend ($C7:0652), Audio_CmdSwapSample ($C7:075F, $C7:07AB, $C7:08E0),
;   Audio_CmdBlockVariant ($C7:091F) and Audio_StartSong ($C7:0A93).
; Entry: M any, X any, DP any, DB any (all saved; it sets M=1, X=0
;        (16-bit), DP=!DP_Audio and DB=0); the command block
;        Audio_CmdId-Audio_CmdArg2 filled. Audio_CommandDone: DP=!DP_Audio,
;        DB=0, and the stack as Audio_Boot / Audio_RunCommand pushed it
; Exit:  A, X, Y, P, DP and DB as on entry (pulled at 16 bits, then P);
;        Audio_CmdId = 0; Audio_CmdArg0-2 may be overwritten (a song
;        load, the $30-$3F aliases and command $71 do); the APU and the
;        Audio_* page as the
;        command leaves them
; Sub-entries: Audio_RunCommand_Dispatch, Audio_CommandDone.
Audio_RunCommand:
    PHB
    PHD
    PHP
    REP #$20
    REP #$10
    PHA
    PHX
    PHY
    SEP #$20
    LDA.b #$00
    PHA
    PLB                                 ; DB = 0
    LDX.w #!DP_Audio
    PHX
    PLD                                 ; DP = $1E00
Audio_RunCommand_Dispatch:              ; header: see Audio_RunCommand
    SEP #$20
    LDA.b !Audio_SongLoading-!DP_Audio
    BPL Audio_CommandDone               ; a song load is running
    LDA.b !Audio_CmdId-!DP_Audio
    BEQ Audio_CommandDone
    BMI .send                           ; $80-$FF
    CMP.b #!Audio_CmdFirstSong
    BCC Audio_CommandDone               ; $01-$0F
    CMP.b #!Audio_CmdFirstSend
    BCS .from_18
    AND.b #!Audio_CmdIndexMask          ; $10-$17
    ASL A
    XBA
    LDA.b #$00
    PHA
    XBA
    PHA
    PLX                                 ; X = (command & $0F) x 2
    JMP (Audio_SongCmdTable,X)
.from_18:
    CMP.b #!Audio_CmdFirstAlias
    BCS .from_30
.send:
    JMP Audio_CmdSend                   ; $18-$2F, $80-$FF
.from_30:
    CMP.b #!Audio_CmdAliasEnd
    BCS .from_40
    JMP Audio_CmdSongAlias              ; $30-$3F
.from_40:
    CMP.b #!Audio_Cmd70
    BNE .not_70
    JMP Audio_CmdBlockVariant
.not_70:
    CMP.b #!Audio_Cmd71
    BNE Audio_CommandDone
    JMP Audio_CmdSwapSample
Audio_CommandDone:                      ; header: see Audio_RunCommand
    SEP #$20
    STZ.b !Audio_CmdId-!DP_Audio
    REP #$20
    REP #$10
    PLY
    PLX
    PLA
    PLP
    PLD
    PLB
    RTL

; ============================================================
; Song load ($C7:01A1–$C7:061B)
; Audio_CmdLoadSong falls into Audio_LoadNewSamples, which falls into
; Audio_SendSampleDir, which falls into Audio_SendSongData. Each step
; ends a transfer with Audio_Seq = !Audio_SeqHeader for the next one.
; ============================================================

; $C7:01A1 — Audio_CmdLoadSong (389 bytes, $01A1–$0325)
; Commands $10, $11, $14 and $15 (Audio_SongCmdTable): load song
; Audio_CmdArg0. A song number not below Audio_SongCount ($53) does
; nothing. Otherwise:
;   1. Audio_AdjustSongCmd (no effect, as the list is empty), then
;      Audio_StartSong sends the command to the APU; when APUIO1
;      bit 7 is set after the echo (probably: nothing more needed; not
;      traced into the SPC700 program), the load ends there
;      (Audio_StartSong leaves to Audio_CommandDone itself).
;   2. Audio_SongLoading = the song (so further commands are ignored
;      until the end of Audio_SendSongData).
;   3. Copies the song's sample list (AudioRom_SongSamples, 16 words,
;      0-ended) to Audio_SongSamples, and the ones not in
;      Audio_SlotSample to Audio_NewSamples (both cleared first). With
;      nothing new it goes straight to Audio_SendSampleDir.
;   4. Frees every slot (up to the first free one) whose sample the
;      song does not use. If that leaves a gap (the last slot in use is
;      not just before the first free one) it compacts the slots: one
;      move transfer (!Audio_XferMove) with, for each used slot after a
;      free one, three steps in APUIO2/3: its ARAM address, the free
;      slot's address, its length; the slot's entries move down. The
;      first step is the header (APUIO1 = !Audio_XferMove, sent once
;      before it); if APUIO1 does not echo the mode after that step it
;      sends one more step with APUIO2/3 = 0, empties all the slots and
;      puts the song's whole list in Audio_NewSamples (everything is
;      loaded again), also clearing Audio_SlotAram entries 1-16.
;   5. Audio_Seq = !Audio_SeqHeader; falls into Audio_LoadNewSamples.
; Callers note: reached through Audio_SongCmdTable (entries 0, 1, 4, 5)
;   from Audio_RunCommand_Dispatch.
; Entry: M=1 (8-bit), X=0 (16-bit), DP=!DP_Audio, DB=0 (as
;        Audio_RunCommand_Dispatch leaves them); the command block set
; Exit:  does not return: falls into Audio_LoadNewSamples with M=1,
;        X=0 (or leaves through Audio_CommandDone: song number too big,
;        or Audio_StartSong's early end), or JMPs to Audio_LoadNewSamples
;        with M=0 (no gap) or Audio_SendSampleDir (no new sample)
; Callees: Audio_AdjustSongCmd, Audio_StartSong, Audio_SendSeq (JSR);
;   Audio_CommandDone, Audio_LoadNewSamples, Audio_SendSampleDir (JMP)
Audio_CmdLoadSong:
    SEP #$20
    LDA.b !Audio_CmdArg0-!DP_Audio
    CMP.l Audio_SongCount
    BCS Audio_CommandDone
    JSR Audio_AdjustSongCmd
    JSR Audio_StartSong
    LDA.b !Audio_CmdArg0-!DP_Audio
    STA.b !Audio_SongLoading-!DP_Audio
    REP #$20
    LDX.w #!Audio_SongListBytes
.clear_lists:
    STZ.w !Audio_SongSamples-2,X
    STZ.w !Audio_NewSamples-2,X
    DEX
    DEX
    BNE .clear_lists
    LDY.w #!Audio_NumSlots
.find_used_end:
    LDA.w !Audio_SlotSample-2,Y
    BNE .found_used_end
    DEY
    DEY
    BNE .find_used_end
.found_used_end:
    STY.b !Audio_Count-!DP_Audio        ; slots in use x 2
    LDA.w #!Audio_SongSamples
    STA.b !Audio_Ptr-!DP_Audio
    LDA.w #!Audio_NewSamples
    STA.b !Audio_Ptr2-!DP_Audio
    LDA.b !Audio_SongLoading-1-!DP_Audio ; 16-bit: the song in the high byte
    AND.w #!Eng_HighByteMask
    LSR A
    LSR A
    LSR A
    TAX                                 ; X = song x 32
    ADC.w #!Audio_SongListBytes
    STA.b !Audio_ListEnd-!DP_Audio
.copy_list:
    LDA.l !AudioRom_SongSamples,X
    BEQ .list_done
    STA.b (!Audio_Ptr-!DP_Audio)
    INC.b !Audio_Ptr-!DP_Audio
    INC.b !Audio_Ptr-!DP_Audio
    LDY.b !Audio_Count-!DP_Audio
    BEQ .is_new
.search_slots:
    CMP.w !Audio_SlotSample-2,Y
    BEQ .next_entry                     ; already in a slot
    DEY
    DEY
    BNE .search_slots
.is_new:
    STA.b (!Audio_Ptr2-!DP_Audio)
    INC.b !Audio_Ptr2-!DP_Audio
    INC.b !Audio_Ptr2-!DP_Audio
.next_entry:
    INX
    INX
    CPX.b !Audio_ListEnd-!DP_Audio
    BNE .copy_list
.list_done:
    LDA.w !Audio_NewSamples
    BNE .free_unused
    JMP Audio_SendSampleDir
.free_unused:
    REP #$20
    LDX.w #$0000
.free_loop:
    LDA.b !Audio_SlotSample-!DP_Audio,X
    BEQ .free_done
    LDY.w #$0000
.free_search:
    CMP.w !Audio_SongSamples,Y
    BEQ .free_next                      ; the song uses it: keep
    INY
    INY
    CPY.w #!Audio_SongListBytes
    BNE .free_search
    STZ.b !Audio_SlotSample-!DP_Audio,X
.free_next:
    INX
    INX
    CPX.w #!Audio_NumSlots
    BNE .free_loop
.free_done:
    LDX.w #$0000
.find_free:
    LDA.b !Audio_SlotSample-!DP_Audio,X
    BEQ .found_free
    INX
    INX
    CPX.w #!Audio_NumSlots
    BNE .find_free
.found_free:
    STX.b !Audio_Count-!DP_Audio        ; the first free slot x 2
    LDX.w #!Audio_NumSlots
.find_last:
    LDA.b !Audio_SlotSample-2-!DP_Audio,X
    BNE .found_last
    DEX
    DEX
    BNE .find_last
.found_last:
    CPX.b !Audio_Count-!DP_Audio
    BNE .compact
    JMP Audio_LoadNewSamples            ; no gap
.compact:
    SEP #$20
    LDA.b #!Audio_XferMove
    STA.w APUIO1
    LDY.w #$0000                        ; Y = the slot to fill
    STY.b !Audio_Count-!DP_Audio        ; 0 until the first step is sent
.compact_loop:
    REP #$20
    LDA.w !Audio_SlotSample,Y
    BNE .compact_next
    TYX
    BRA .find_move
.find_move_loop:
    LDA.b !Audio_SlotSample-!DP_Audio,X
    BNE .move
.find_move:
    INX
    INX
    CPX.w #!Audio_NumSlots
    BNE .find_move_loop
    BRL .compact_done                   ; nothing left above the gap
.move:
    LDA.b !Audio_SlotAram-!DP_Audio,X
    SEP #$20
    STA.w APUIO2
    XBA
    STA.w APUIO3                        ; step 1: the sample's ARAM address
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    LDA.b !Audio_Count-!DP_Audio
    BNE .move_accepted
    INC.b !Audio_Count-!DP_Audio
    LDA.b #!Audio_XferMove
    CMP.w APUIO1
    BNE .move_refused
.move_accepted:
    REP #$20
    LDA.b !Audio_SlotSample-!DP_Audio,X
    STA.w !Audio_SlotSample,Y
    STZ.b !Audio_SlotSample-!DP_Audio,X
    LDA.w !Audio_SlotAram,Y
    SEP #$20
    STA.w APUIO2
    XBA
    STA.w APUIO3                        ; step 2: its new ARAM address
    XBA
    REP #$20
    CLC
    ADC.b !Audio_SlotLen-!DP_Audio,X
    STA.w !Audio_SlotAram+2,Y           ; the next slot starts after it
    SEP #$20
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    REP #$20
    LDA.b !Audio_SlotLen-!DP_Audio,X
    STA.w !Audio_SlotLen,Y
    SEP #$20
    STA.w APUIO2
    XBA
    STA.w APUIO3                        ; step 3: its length
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
.compact_next:
    INY
    INY
    CPY.w #!Audio_NumSlots
    BNE .compact_loop
    BRA .compact_done
.move_refused:
    SEP #$20
    LDA.b #$00
    STA.w APUIO2
    STA.w APUIO3
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq                   ; (Audio_Seq not updated: reset below)
    REP #$20
    LDY.w #!Audio_NumSlots
    LDA.b !Audio_SongLoading-!DP_Audio
    INC A
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    TAX                                 ; X = (song + 1) x 32
.reload_all:
    LDA.l !AudioRom_SongSamples-2,X
    STA.w !Audio_SongSamples-2,Y
    STA.w !Audio_NewSamples-2,Y
    LDA.w #$0000
    STA.w !Audio_SlotSample-2,Y
    STA.w !Audio_SlotLen-2,Y
    STA.w !Audio_SlotAram,Y             ; entries 1-16 (entry 0, the base, kept)
    DEX
    DEX
    DEY
    DEY
    BNE .reload_all
.compact_done:
    SEP #$20
    LDA.b #!Audio_SeqHeader
    STA.b !Audio_Seq-!DP_Audio

; $C7:0326 — Audio_LoadNewSamples (85 bytes, $0326–$037A)
; Song load, part 2: puts each sample of Audio_NewSamples in the next
; free slot with Audio_UploadSample, in list order. If no slot is free
; it first empties them all (Audio_SlotSample only) and starts at slot
; 0. Nothing bounds the slot index. It stays below 16 because the slots
; still in use hold only samples of the song's list (at most 16, no
; repeats in the ROM's lists), which Audio_CmdLoadSong's free step
; ensures as long as the slots had no gap before it (they are kept
; without one); not checked beyond that. When the list
; ends before 16 entries, Audio_FreeAram = the ARAM address after the
; last loaded sample, and Audio_SlotLen and the end (the next entry of
; Audio_SlotAram) of every slot from there on are zeroed. Ends with
; Audio_Seq = !Audio_SeqHeader and falls into Audio_SendSampleDir.
; Callers note: also falls in from Audio_CmdLoadSong (its JMP is the
;   no-gap case); the JMP from Audio_VecLoadNewSamples is unused (see
;   Audio_DriverInit).
; Audio_Unk1E0A, zeroed first, has no reader.
; Callers (2 JMP sites): Audio_VecLoadNewSamples ($C7:0008) and Audio_CmdLoadSong ($C7:0257).
; Entry: M=0 or 1 (it sets M=1), X=0 (16-bit), DP=!DP_Audio, DB=0
; Exit:  falls into Audio_SendSampleDir with M=1, X=0; A, X, Y
;        clobbered
; Callees: Audio_UploadSample
Audio_LoadNewSamples:
    SEP #$20
    STZ.b !Audio_Unk1E0A-!DP_Audio
    LDX.w #$0000
.find_free:
    LDA.b !Audio_SlotSample-!DP_Audio,X
    BEQ .slots_ready
    INX
    INX
    CPX.w #!Audio_NumSlots
    BNE .find_free
    LDA.b #$00
.empty_all:
    STA.b !Audio_SlotSample-1-!DP_Audio,X ; bytes $1E3F down to $1E20
    DEX
    BNE .empty_all
.slots_ready:
    LDY.w #$0000
.load_loop:
    REP #$20
    LDA.w !Audio_NewSamples,Y
    BEQ .list_end
    STA.b !Audio_SlotSample-!DP_Audio,X
    STX.b !Audio_SaveX-!DP_Audio
    STY.b !Audio_SaveY-!DP_Audio
    JSR Audio_UploadSample
    LDX.b !Audio_SaveX-!DP_Audio
    LDY.b !Audio_SaveY-!DP_Audio
    INY
    INY
    INX
    INX
    CPY.w #!Audio_SongListBytes
    BNE .load_loop
    BRA .done
.list_end:
    REP #$20
    LDA.b !Audio_SlotAram-!DP_Audio,X
    STA.b !Audio_FreeAram-!DP_Audio
.clear_rest:
    LDA.w #$0000
    STA.b !Audio_SlotAram+2-!DP_Audio,X
    STA.b !Audio_SlotLen-!DP_Audio,X
    INX
    INX
    CPX.w #!Audio_NumSlots
    BNE .clear_rest
.done:
    SEP #$20
    LDA.b #!Audio_SeqHeader
    STA.b !Audio_Seq-!DP_Audio

; $C7:037B — Audio_SendSampleDir (325 bytes, $037B–$04BF)
; Song load, part 3: sends the song's samples' directory entries and
; parameter words.
;   1. Fills Audio_DirBuf: for each Audio_SongSamples entry (up to the
;      first 0) the ARAM start of the slot holding it and that start +
;      its Audio_SampleLoop offset; 0, 0 if no slot holds it. Entries
;      after a 0 keep what they held. Quirk: the slot search runs over
;      32 words (!Audio_SlotSearchEnd), on through Audio_SlotLen, so a
;      length equal to the sample number would match there and the
;      address would be read from Audio_SlotAram + that offset, past
;      the table; it cannot happen once Audio_LoadNewSamples has put
;      every sample in a slot.
;   2. Three word transfers (!Audio_XferWords), each retried after
;      Audio_AbortXfer until APUIO1 echoes the mode: all 64 bytes of
;      Audio_DirBuf to !AudioAram_SongDir; the 16 Audio_SampleParamA
;      words of the song's samples to !AudioAram_SongParamA; the
;      Audio_SampleParamB words to !AudioAram_SongParamB. Quirk: the
;      last two index the table by sample - 1 without stopping at a 0
;      entry, so an unused entry has X = $FFFE and reads $C8:0C1E or
;      $C8:0C9A (the long address + $FFFE runs into bank $C8, sample
;      data) and sends that word.
;   3. Audio_FirstSlot = the slot offset (x 2) of the slot whose sample
;      matches Audio_SongSamples' first entry (low bytes compared,
;      slots 15 down to 0; $FFFE when none matches). Left as it was when
;      the song has no samples.
; Falls into Audio_SendSongData.
; Callers note: also falls in from Audio_LoadNewSamples; the JMP from
;   Audio_CmdLoadSong is its nothing-new-to-load case, the one from
;   Audio_VecSendSampleDir is unused (see Audio_DriverInit).
; Callers (2 JMP sites): Audio_VecSendSampleDir ($C7:000C) and Audio_CmdLoadSong ($C7:0214).
; Entry: M=0 or 1 (it sets M=0), X=0 (16-bit), DP=!DP_Audio, DB=0;
;        Audio_Seq = the next sequence value (!Audio_SeqHeader when it
;        falls in; (command + 1) & $7F from Audio_StartSong on the JMP)
; Exit:  falls into Audio_SendSongData with M=1, X=0; A, X, Y
;        clobbered; Audio_Seq = !Audio_SeqHeader
; Callees: Audio_SendSeq, Audio_AbortXfer
Audio_SendSampleDir:
    REP #$20
    LDA.w #!Audio_DirBuf
    STA.b !Audio_Ptr-!DP_Audio
    LDX.w #$0000
.dir_loop:
    LDA.w !Audio_SongSamples,X
    BEQ .send_dir
    LDY.w #$0000
.dir_search:
    CMP.w !Audio_SlotSample,Y
    BEQ .dir_found
    INY
    INY
    CPY.w #!Audio_SlotSearchEnd
    BNE .dir_search
    LDA.w #$0000
    BRA .dir_none
.dir_found:
    PHX
    DEC A
    ASL A
    TAX
    LDA.w !Audio_SlotAram,Y
    STA.b (!Audio_Ptr-!DP_Audio)        ; start
    INC.b !Audio_Ptr-!DP_Audio
    INC.b !Audio_Ptr-!DP_Audio
    CLC
    ADC.l Audio_SampleLoop,X
    STA.b (!Audio_Ptr-!DP_Audio)        ; loop start
    PLX
    BRA .dir_next
.dir_none:
    STA.b (!Audio_Ptr-!DP_Audio)
    INC.b !Audio_Ptr-!DP_Audio
    INC.b !Audio_Ptr-!DP_Audio
    STA.b (!Audio_Ptr-!DP_Audio)
.dir_next:
    INC.b !Audio_Ptr-!DP_Audio
    INC.b !Audio_Ptr-!DP_Audio
    INX
    INX
    CPX.w #!Audio_SongListBytes
    BNE .dir_loop
.send_dir:
    SEP #$20
    LDA.b #!AudioAram_SongDir>>8
    STA.w APUIO3
    LDA.b #!AudioAram_SongDir
    STA.w APUIO2
    LDA.b #!Audio_XferWords
    STA.w APUIO1
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    LDA.b #!Audio_XferWords
    CMP.w APUIO1
    BEQ .dir_accepted
    JSR Audio_AbortXfer
    BRA .send_dir
.dir_accepted:
    LDX.w #$0000
.dir_send_loop:
    LDA.w !Audio_DirBuf,X
    STA.w APUIO1
    LDA.w !Audio_DirBuf+1,X
    STA.w APUIO2
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    INX
    INX
    CPX.w #!Audio_DirBufBytes
    BNE .dir_send_loop
    LDA.b #!Audio_SeqHeader
    STA.b !Audio_Seq-!DP_Audio
.send_param_a:
    SEP #$20
    LDA.b #!AudioAram_SongParamA>>8
    STA.w APUIO3
    LDA.b #!AudioAram_SongParamA
    STA.w APUIO2
    LDA.b #!Audio_XferWords
    STA.w APUIO1
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    LDA.b #!Audio_XferWords
    CMP.w APUIO1
    BEQ .param_a_accepted
    JSR Audio_AbortXfer
    BRA .send_param_a
.param_a_accepted:
    LDY.w #$0000
.param_a_loop:
    REP #$20
    LDA.w !Audio_SongSamples,Y
    DEC A
    ASL A
    TAX
    LDA.l Audio_SampleParamA,X
    SEP #$20
    STA.w APUIO1
    XBA
    STA.w APUIO2
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    INY
    INY
    CPY.w #!Audio_SongListBytes
    BNE .param_a_loop
    LDA.b #!Audio_SeqHeader
    STA.b !Audio_Seq-!DP_Audio
.send_param_b:
    SEP #$20
    LDA.b #!AudioAram_SongParamB>>8
    STA.w APUIO3
    LDA.b #!AudioAram_SongParamB
    STA.w APUIO2
    LDA.b #!Audio_XferWords
    STA.w APUIO1
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    LDA.b #!Audio_XferWords
    CMP.w APUIO1
    BEQ .param_b_accepted
    JSR Audio_AbortXfer
    BRA .send_param_b
.param_b_accepted:
    LDY.w #$0000
.param_b_loop:
    REP #$20
    LDA.w !Audio_SongSamples,Y
    DEC A
    ASL A
    TAX
    LDA.l Audio_SampleParamB,X
    SEP #$20
    STA.w APUIO1
    XBA
    STA.w APUIO2
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    INY
    INY
    CPY.w #!Audio_SongListBytes
    BNE .param_b_loop
    LDA.b #!Audio_SeqHeader
    STA.b !Audio_Seq-!DP_Audio
    LDA.w !Audio_SongSamples            ; 8-bit: the first sample's low byte
    BNE .find_first
    JMP Audio_SendSongData
.find_first:
    LDX.w #!Audio_NumSlots
.first_search:
    CMP.b !Audio_SlotSample-2-!DP_Audio,X
    BEQ .first_found
    DEX
    DEX
    BNE .first_search
.first_found:
    DEX
    DEX
    STX.b !Audio_FirstSlot-!DP_Audio

; $C7:04C0 — Audio_SendSongData (348 bytes, $04C0–$061B)
; Song load, part 4, and its end:
;   1. Takes Audio_Unk1E10 as 0/1; if that differs from
;      Audio_BlockInAram both get it and Audio_BlockDirty is counted up.
;      With Audio_BlockDirty nonzero, Audio_UploadBlock2F00 sends the
;      $2F00 block (mode 3 here) and clears it.
;   2. A triples transfer (!Audio_XferTriples) to !AudioAram_Song,
;      retried after Audio_AbortXfer until APUIO1 echoes the mode: the
;      song's data from Audio_SongTable (a 16-bit length, then the
;      bytes), 3 bytes per step. A length of !Audio_SongRoom or more
;      counts Audio_BlockDirty up (the data reaches $2F00; the block is
;      sent again at the next load). Quirk: the step loop counts the
;      length down by 3 while it stays >= 0 (BPL), so it sends
;      length / 3 + 1 steps (rounded down), 1-3 bytes past the data;
;      Audio_UploadSample's loop stops at 0. When the data crosses a
;      bank boundary it uses a slower copy of the loop that steps the
;      pointer's bank.
;   3. Another triples transfer, retried the same way, to
;      !AudioAram_SongExtra: the song's 36 bytes of AudioRom_SongExtra
;      (12 steps).
;   4. The end: APUIO1 = APUIO0 = !Audio_SeqHeader, then up to
;      !Audio_Timeout reads of APUIO0 waiting for the echo (it goes on
;      either way); Audio_SongLoading = !Audio_SongIdle (commands are
;      taken again); Audio_DropEchoSlots; leaves through
;      Audio_CommandDone.
; Callers note: also falls in from Audio_SendSampleDir.
; Callers (1 JMP site): Audio_SendSampleDir ($C7:04AE).
; Entry: M=1 (8-bit), X=0 (16-bit), DP=!DP_Audio, DB=0;
;        Audio_SongLoading = the song
; Exit:  does not return: leaves through Audio_CommandDone (A, X, Y, P,
;        DP, DB pulled; Audio_CmdId = 0)
; Callees: Audio_UploadBlock2F00, Audio_SendSeq, Audio_AbortXfer,
;   Audio_DropEchoSlots (JSR); Audio_CommandDone (JMP)
Audio_SendSongData:
    SEP #$20
    LDA.b !Audio_Unk1E10-!DP_Audio
    CLC
    ADC.b #!Audio_CarryIfNonzero        ; C = (Audio_Unk1E10 != 0)
    LDA.b #$00
    ROL A
    CMP.b !Audio_BlockInAram-!DP_Audio
    BEQ .same_block
    STA.b !Audio_Unk1E10-!DP_Audio
    STA.b !Audio_BlockInAram-!DP_Audio
    INC.b !Audio_BlockDirty-!DP_Audio
.same_block:
    LDA.b !Audio_BlockDirty-!DP_Audio
    BEQ .send_song
    JSR Audio_UploadBlock2F00
.send_song:
    SEP #$20
    LDA.b #!AudioAram_Song>>8
    STA.w APUIO3
    LDA.b #!AudioAram_Song
    STA.w APUIO2
    LDA.b #!Audio_XferTriples
    STA.w APUIO1
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    LDA.b #!Audio_XferTriples
    CMP.w APUIO1
    BEQ .song_accepted
    JSR Audio_AbortXfer
    BRA .send_song
.song_accepted:
    REP #$20
    LDA.b !Audio_SongLoading-!DP_Audio
    AND.w #!Eng_LowByteMask
    STA.b !Audio_Tmp82-!DP_Audio
    ASL A
    CLC
    ADC.b !Audio_Tmp82-!DP_Audio
    TAX                                 ; X = song x 3
    SEP #$20
    LDA.l Audio_SongTable,X
    STA.b !Audio_Ptr-!DP_Audio
    LDA.l Audio_SongTable+1,X
    STA.b !Audio_Ptr+1-!DP_Audio
    LDA.l Audio_SongTable+2,X
    STA.b !Audio_Ptr+2-!DP_Audio
    LDY.b !Audio_Ptr-!DP_Audio          ; Y = the offset, the pointer keeps the bank
    STZ.b !Audio_Ptr-!DP_Audio
    STZ.b !Audio_Ptr+1-!DP_Audio
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.b !Audio_Count-!DP_Audio
    INY
    BNE .len_hi
    INC.b !Audio_Ptr+2-!DP_Audio
.len_hi:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.b !Audio_Count+1-!DP_Audio
    INY
    BNE .len_done
    INC.b !Audio_Ptr+2-!DP_Audio
.len_done:
    LDX.b !Audio_Count-!DP_Audio        ; X = the length
    CPX.w #!Audio_SongRoom
    BCC .fits
    INC.b !Audio_BlockDirty-!DP_Audio
.fits:
    REP #$20
    TYA
    CLC
    ADC.b !Audio_Count-!DP_Audio
    SEP #$20
    BCC .song_fast                      ; no bank crossing
.song_slow:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO1
    INY
    BNE .slow_1
    INC.b !Audio_Ptr+2-!DP_Audio
.slow_1:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO2
    INY
    BNE .slow_2
    INC.b !Audio_Ptr+2-!DP_Audio
.slow_2:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO3
    INY
    BNE .slow_3
    INC.b !Audio_Ptr+2-!DP_Audio
.slow_3:
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    DEX
    DEX
    DEX
    BPL .song_slow
    BRA .song_sent
.song_fast:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO1
    INY
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO2
    INY
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO3
    INY
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    DEX
    DEX
    DEX
    BPL .song_fast
.song_sent:
    LDA.b #!Audio_SeqHeader
    STA.b !Audio_Seq-!DP_Audio
.send_extra:
    REP #$20
    LDA.b !Audio_SongLoading-!DP_Audio
    AND.w #!Eng_LowByteMask
    STA.b !Audio_Tmp82-!DP_Audio
    ASL A
    CLC
    ADC.b !Audio_Tmp82-!DP_Audio
    ASL A
    ASL A
    STA.b !Audio_Tmp82-!DP_Audio        ; song x 12
    ASL A
    CLC
    ADC.b !Audio_Tmp82-!DP_Audio
    TAY                                 ; Y = song x 36
    SEP #$20
    LDA.b #!AudioRom_SongExtra
    STA.b !Audio_Ptr-!DP_Audio
    LDA.b #!AudioRom_SongExtra>>8
    STA.b !Audio_Ptr+1-!DP_Audio
    LDA.b #!AudioRom_SongExtra>>16
    STA.b !Audio_Ptr+2-!DP_Audio
    LDA.b #!AudioAram_SongExtra>>8
    STA.w APUIO3
    LDA.b #!AudioAram_SongExtra
    STA.w APUIO2
    LDA.b #!Audio_XferTriples
    STA.w APUIO1
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    LDA.b #!Audio_XferTriples
    CMP.w APUIO1
    BEQ .extra_accepted
    JSR Audio_AbortXfer
    BRA .send_extra
.extra_accepted:
    LDX.w #!Audio_SongExtraSteps
.extra_loop:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO1
    INY
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO2
    INY
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO3
    INY
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    DEX
    BNE .extra_loop
    SEP #$20
    LDA.b #!Audio_SeqHeader
    LDX.w #!Audio_Timeout
    STA.w APUIO1
    STA.w APUIO0
.wait_end:
    CMP.w APUIO0
    BEQ .ended
    DEX
    BNE .wait_end
.ended:
    STA.b !Audio_SongLoading-!DP_Audio  ; !Audio_SongIdle (= !Audio_SeqHeader)
    JSR Audio_DropEchoSlots
    JMP Audio_CommandDone

; ============================================================
; Commands passed through, sample upload, aliases ($C7:061C–$C7:0754)
; ============================================================

; $C7:061C — Audio_CmdSend (57 bytes, $061C–$0654)
; Commands $18-$2F and $80-$FF: sends the block to the APU as it is:
; APUIO3 = Audio_CmdArg2, APUIO2 = Arg1, APUIO1 = Arg0, then APUIO0 =
; Audio_CmdId, and reads APUIO0 up to !Audio_Timeout times for the
; echo. On a timeout it starts again from the top, unless Audio_CmdId
; reads 0 by then (it is not 0 on entry, so only something outside this
; routine could clear it meanwhile: an interrupt handler running a
; command, probably; not traced), in which case it gives up. On the
; echo of command !Audio_CmdSetEcho, Audio_CmdArg0's low nibble becomes
; the echo delay (Audio_SetEchoDelay) when it differs from
; Audio_EchoDelay.
; Callers (1 JMP site): Audio_RunCommand_Dispatch ($C7:017A).
; Entry: M=1 (8-bit), X=0 (16-bit), DP=!DP_Audio, DB=0
; Exit:  does not return: leaves through Audio_CommandDone
; Callees: Audio_SetEchoDelay (JSR); Audio_CommandDone (JMP)
Audio_CmdSend:
    SEP #$20
    LDA.b !Audio_CmdArg2-!DP_Audio
    STA.w APUIO3
    LDA.b !Audio_CmdArg1-!DP_Audio
    STA.w APUIO2
    LDA.b !Audio_CmdArg0-!DP_Audio
    STA.w APUIO1
    LDA.b !Audio_CmdId-!DP_Audio
    LDX.w #!Audio_Timeout
    STA.w APUIO0
.wait_echo:
    CMP.w APUIO0
    BEQ .echoed
    DEX
    BNE .wait_echo
    LDA.b !Audio_CmdId-!DP_Audio
    BEQ .done
    BRA Audio_CmdSend
.echoed:
    CMP.b #!Audio_CmdSetEcho
    BNE .done
    LDA.b !Audio_CmdArg0-!DP_Audio
    AND.b #!Audio_EchoDelayMask
    CMP.b !Audio_EchoDelay-!DP_Audio
    BEQ .done
    JSR Audio_SetEchoDelay
.done:
    JMP Audio_CommandDone

; $C7:0655 — Audio_UploadSample (200 bytes, $0655–$071C)
; Sends the sample in slot Audio_SaveX (Audio_SlotSample entry, 1-62)
; to ARAM at the slot's Audio_SlotAram address: a triples transfer
; (!Audio_XferTriples), retried after Audio_AbortXfer until APUIO1
; echoes the mode, of the sample's bytes from Audio_SampleTable (a
; 16-bit length first). Sets the slot's Audio_SlotLen to the length and
; the next Audio_SlotAram entry to address + length. The loop sends
; length / 3 steps and stops when the count reaches exactly 0 (BNE):
; the lengths in the table are all multiples of 9 (BRR blocks), checked
; against the ROM. A sample that crosses a bank boundary goes through a
; slower copy of the loop that steps the pointer's bank.
; Callers (1 JSR site): Audio_LoadNewSamples ($C7:034F).
; Entry: M any (P saved; it sets M=0, then M=1), X=0 (16-bit),
;        DP=!DP_Audio, DB=0; Audio_SaveX = the slot x 2, its
;        Audio_SlotSample entry set
; Exit:  P as on entry (PLP); A, X, Y clobbered; Audio_Count = the
;        length; Audio_Seq = !Audio_SeqHeader
; Callees: Audio_SendSeq, Audio_AbortXfer
Audio_UploadSample:
    PHP
.send_header:
    REP #$20
    LDX.b !Audio_SaveX-!DP_Audio
    LDA.b !Audio_SlotSample-!DP_Audio,X
    DEC A
    STA.b !Audio_Tmp82-!DP_Audio
    ASL A
    CLC
    ADC.b !Audio_Tmp82-!DP_Audio
    TAX                                 ; X = (sample - 1) x 3
    SEP #$20
    LDA.l Audio_SampleTable,X
    STA.b !Audio_Ptr-!DP_Audio
    LDA.l Audio_SampleTable+1,X
    STA.b !Audio_Ptr+1-!DP_Audio
    LDA.l Audio_SampleTable+2,X
    STA.b !Audio_Ptr+2-!DP_Audio
    LDY.b !Audio_Ptr-!DP_Audio          ; Y = the offset, the pointer keeps the bank
    STZ.b !Audio_Ptr-!DP_Audio
    STZ.b !Audio_Ptr+1-!DP_Audio
    LDX.b !Audio_SaveX-!DP_Audio
    LDA.b !Audio_SlotAram-!DP_Audio,X
    STA.w APUIO2
    LDA.b !Audio_SlotAram+1-!DP_Audio,X
    STA.w APUIO3
    LDA.b #!Audio_XferTriples
    STA.w APUIO1
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    LDA.b #!Audio_XferTriples
    CMP.w APUIO1
    BEQ .accepted
    JSR Audio_AbortXfer
    BRA .send_header
.accepted:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.b !Audio_Count-!DP_Audio
    STA.b !Audio_SlotLen-!DP_Audio,X
    CLC
    ADC.b !Audio_SlotAram-!DP_Audio,X
    STA.b !Audio_SlotAram+2-!DP_Audio,X
    INY
    BNE .len_hi
    INC.b !Audio_Ptr+2-!DP_Audio
.len_hi:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.b !Audio_Count+1-!DP_Audio
    STA.b !Audio_SlotLen+1-!DP_Audio,X
    ADC.b !Audio_SlotAram+1-!DP_Audio,X
    STA.b !Audio_SlotAram+3-!DP_Audio,X
    INY
    BNE .len_done
    INC.b !Audio_Ptr+2-!DP_Audio
.len_done:
    LDX.b !Audio_Count-!DP_Audio        ; X = the length
    REP #$20
    TYA
    CLC
    ADC.b !Audio_Count-!DP_Audio
    SEP #$20
    BCC .fast                           ; no bank crossing
.slow:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO1
    INY
    BNE .slow_1
    INC.b !Audio_Ptr+2-!DP_Audio
.slow_1:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO2
    INY
    BNE .slow_2
    INC.b !Audio_Ptr+2-!DP_Audio
.slow_2:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO3
    INY
    BNE .slow_3
    INC.b !Audio_Ptr+2-!DP_Audio
.slow_3:
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    DEX
    DEX
    DEX
    BNE .slow
    BRA .sent
.fast:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO1
    INY
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO2
    INY
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO3
    INY
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    DEX
    DEX
    DEX
    BNE .fast
.sent:
    LDA.b #!Audio_SeqHeader
    STA.b !Audio_Seq-!DP_Audio
    PLP
    RTS

; $C7:071D — Audio_CmdSongAlias (23 bytes, $071D–$0733)
; Commands $30-$3F: replaces the whole command block with entry
; (command & $0F) of Audio_SongAliasTable (command $10, song = the low
; nibble, Arg1 = Arg2 = $FF) and sorts it again from
; Audio_RunCommand_Dispatch, so command $3n loads song n.
; Callers (1 JMP site): Audio_RunCommand_Dispatch ($C7:0181).
; Entry: M=1 (8-bit; it sets M=0), X=0 (16-bit), DP=!DP_Audio, DB=0;
;        A = Audio_CmdId (B whatever it is: the AND drops it)
; Exit:  does not return: JMPs to Audio_RunCommand_Dispatch with M=0;
;        A = the new Audio_CmdId/Arg0 word, X = (command & $0F) x 4
; Callees: Audio_RunCommand_Dispatch (JMP)
Audio_CmdSongAlias:
    REP #$20
    AND.w #!Audio_CmdIndexMask
    ASL A
    ASL A
    TAX
    LDA.l Audio_SongAliasTable+2,X
    STA.b !Audio_CmdArg1-!DP_Audio      ; Arg1 and Arg2
    LDA.l Audio_SongAliasTable,X
    STA.b !Audio_CmdId-!DP_Audio        ; command and Arg0
    JMP Audio_RunCommand_Dispatch

; $C7:0734 — Audio_AdjustSongCmd (33 bytes, $0734–$0754)
; Sets bit 2 (!Audio_CmdListedBit) of Audio_CmdId when the command is
; $14 or above, or when Audio_CmdArg0 is on Audio_SongBit2List (bytes up
; to the first one with bit 7 set). For the commands that reach it
; ($10, $11, $14, $15) this changes nothing: $14/$15 already have the
; bit, and the list holds only its end marker, so $10/$11 are never
; changed. A hook left without entries, probably.
; Callers (1 JSR site): Audio_CmdLoadSong ($C7:01AB).
; Entry: M any (P saved), X=0 (16-bit), DP=!DP_Audio, DB=0
; Exit:  P as on entry (PLP); A and X clobbered; Y unchanged
Audio_AdjustSongCmd:
    PHP
    SEP #$20
    LDA.b !Audio_CmdId-!DP_Audio
    CMP.b #!Audio_Cmd14
    BCS .set_bit
    LDX.w #$0000
.search:
    LDA.l Audio_SongBit2List,X
    BMI .done
    CMP.b !Audio_CmdArg0-!DP_Audio
    BEQ .set_bit
    INX
    BRA .search
.set_bit:
    LDA.b #!Audio_CmdListedBit
    ORA.b !Audio_CmdId-!DP_Audio
    STA.b !Audio_CmdId-!DP_Audio
.done:
    PLP
    RTS

; ============================================================
; Commands $70/$71 and the $2F00 block ($C7:0755–$C7:09D9)
; ============================================================

; $C7:0755 — Audio_CmdSwapSample (398 bytes, $0755–$08E2)
; Command $71: puts sample Audio_CmdArg0 (1-62; not range-checked) in
; the slot of the current song's first sample (Audio_FirstSlot), so
; directory entry $20 plays it. Does nothing when slot 0 is empty or
; the argument is 0, or when the new sample does not fit in the slot's
; space (address + length - 1 not below the next Audio_SlotAram entry).
; Otherwise:
;   1. A step with APUIO0 = !Audio_SeqLive (waits for the echo; the
;      sequence goes on from $7F), then a header with APUIO2/3 = the
;      slot's address and APUIO1 = !Audio_XferLive (no check that APUIO1
;      echoes it), and the sample's bytes, 3 per step (BNE loop as in
;      Audio_UploadSample, with the same slow copy for a bank
;      crossing). The slot's Audio_SlotLen = the new length; its end
;      (the next Audio_SlotAram entry) is left as it was.
;   2. Three word transfers (!Audio_XferWords), each with an
;      !Audio_SeqHeader header and no check of APUIO1: two words to
;      !AudioAram_SongDir (the slot address and address + the sample's
;      Audio_SampleLoop offset), one to !AudioAram_SongParamA
;      (Audio_SampleParamA) and one to !AudioAram_SongParamB
;      (Audio_SampleParamB).
;   3. APUIO1 = APUIO0 = !Audio_SeqHeader, up to !Audio_Timeout reads
;      for the echo, then waits (no limit) until APUIO0 is no longer
;      !Audio_SeqHeader. The slot's Audio_SlotSample low byte = the new
;      sample.
; Audio_CmdArg1 is overwritten with (sample - 1) x 2, the index it uses
; for the word tables.
; Callers (1 JMP site): Audio_RunCommand_Dispatch ($C7:018F).
; Entry: M=1 (8-bit), X=0 (16-bit), DP=!DP_Audio, DB=0
; Exit:  does not return: leaves through Audio_CommandDone
; Callees: Audio_SendSeq (JSR); Audio_CommandDone (JMP)
Audio_CmdSwapSample:
    LDX.b !Audio_SlotSample-!DP_Audio   ; 16-bit: slot 0
    BEQ .give_up
    SEP #$20
    LDA.b !Audio_CmdArg0-!DP_Audio
    BNE .start
.give_up:
    JMP Audio_CommandDone
.start:
    REP #$20
    DEC A
    AND.w #!Eng_LowByteMask
    STA.b !Audio_Tmp82-!DP_Audio
    ASL A
    STA.b !Audio_CmdArg1-!DP_Audio      ; (sample - 1) x 2
    CLC
    ADC.b !Audio_Tmp82-!DP_Audio
    TAX                                 ; X = (sample - 1) x 3
    SEP #$20
    LDA.l Audio_SampleTable,X
    STA.b !Audio_Ptr-!DP_Audio
    LDA.l Audio_SampleTable+1,X
    STA.b !Audio_Ptr+1-!DP_Audio
    LDA.l Audio_SampleTable+2,X
    STA.b !Audio_Ptr+2-!DP_Audio
    LDY.b !Audio_Ptr-!DP_Audio          ; Y = the offset, the pointer keeps the bank
    STZ.b !Audio_Ptr-!DP_Audio
    STZ.b !Audio_Ptr+1-!DP_Audio
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.b !Audio_Count-!DP_Audio
    INY
    BNE .len_hi
    INC.b !Audio_Ptr+2-!DP_Audio
.len_hi:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.b !Audio_Count+1-!DP_Audio
    INY
    BNE .len_done
    INC.b !Audio_Ptr+2-!DP_Audio
.len_done:
    REP #$20
    LDX.b !Audio_FirstSlot-!DP_Audio
    LDA.b !Audio_Count-!DP_Audio
    CLC
    ADC.b !Audio_SlotAram-!DP_Audio,X
    DEC A
    CMP.b !Audio_SlotAram+2-!DP_Audio,X
    BCC .fits
    JMP Audio_CommandDone
.fits:
    SEP #$20
    LDA.b #!Audio_SeqLive
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    LDX.b !Audio_FirstSlot-!DP_Audio
    LDA.b !Audio_SlotAram-!DP_Audio,X
    STA.w APUIO2
    LDA.b !Audio_SlotAram+1-!DP_Audio,X
    STA.w APUIO3
    LDA.b #!Audio_XferLive
    STA.w APUIO1
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    REP #$20
    LDA.b !Audio_Count-!DP_Audio
    STA.b !Audio_SlotLen-!DP_Audio,X
    LDX.b !Audio_Count-!DP_Audio        ; X = the length
    TYA
    CLC
    ADC.b !Audio_Count-!DP_Audio
    SEP #$20
    BCC .fast                           ; no bank crossing
.slow:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO1
    INY
    BNE .slow_1
    INC.b !Audio_Ptr+2-!DP_Audio
.slow_1:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO2
    INY
    BNE .slow_2
    INC.b !Audio_Ptr+2-!DP_Audio
.slow_2:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO3
    INY
    BNE .slow_3
    INC.b !Audio_Ptr+2-!DP_Audio
.slow_3:
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    DEX
    DEX
    DEX
    BNE .slow
    BRA .sent
.fast:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO1
    INY
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO2
    INY
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO3
    INY
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    DEX
    DEX
    DEX
    BNE .fast
.sent:
    LDA.b #!AudioAram_SongDir>>8
    STA.w APUIO3
    LDA.b #!AudioAram_SongDir
    STA.w APUIO2
    LDA.b #!Audio_XferWords
    STA.w APUIO1
    LDA.b #!Audio_SeqHeader
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    LDX.b !Audio_FirstSlot-!DP_Audio
    REP #$20
    LDA.b !Audio_SlotAram-!DP_Audio,X
    SEP #$20
    STA.w APUIO1
    XBA
    STA.w APUIO2                        ; start
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    REP #$20
    LDA.b !Audio_SlotAram-!DP_Audio,X
    LDX.b !Audio_CmdArg1-!DP_Audio
    CLC
    ADC.l Audio_SampleLoop,X
    SEP #$20
    STA.w APUIO1
    XBA
    STA.w APUIO2                        ; loop start
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    LDA.b #!AudioAram_SongParamA>>8
    STA.w APUIO3
    LDA.b #!AudioAram_SongParamA
    STA.w APUIO2
    LDA.b #!Audio_XferWords
    STA.w APUIO1
    LDA.b #!Audio_SeqHeader
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    REP #$20
    LDA.l Audio_SampleParamA,X
    SEP #$20
    STA.w APUIO1
    XBA
    STA.w APUIO2
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    LDA.b #!AudioAram_SongParamB>>8
    STA.w APUIO3
    LDA.b #!AudioAram_SongParamB
    STA.w APUIO2
    LDA.b #!Audio_XferWords
    STA.w APUIO1
    LDA.b #!Audio_SeqHeader
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    REP #$20
    LDA.l Audio_SampleParamB,X
    SEP #$20
    STA.w APUIO1
    XBA
    STA.w APUIO2
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    LDA.b #!Audio_SeqHeader
    LDX.w #!Audio_Timeout
    STA.w APUIO1
    STA.w APUIO0
.wait_echo:
    CMP.w APUIO0
    BEQ .wait_change
    DEX
    BNE .wait_echo
.wait_change:
    CMP.w APUIO0
    BEQ .wait_change
    LDX.b !Audio_FirstSlot-!DP_Audio
    LDA.b !Audio_CmdArg0-!DP_Audio
    STA.b !Audio_SlotSample-!DP_Audio,X
    JMP Audio_CommandDone

; $C7:08E3 — Audio_CmdBlockVariant (63 bytes, $08E3–$0921)
; Command $70: picks the $2F00 block by Audio_CmdArg0 (0 =
; AudioRom_Block2F00, nonzero = AudioRom_Block2F00Alt; the battle
; music cues send 1 before a battle and 0 after it). When that is not
; the block already in ARAM (Audio_BlockInAram): Audio_Unk1E10 =
; Audio_BlockInAram = 0/1, a step with APUIO0 = !Audio_SeqLive (waits
; for the echo; the sequence goes on from $7F), Audio_UploadBlock2F00
; (mode !Audio_XferLive for this command), then APUIO1 = APUIO0 =
; !Audio_SeqHeader, up to !Audio_Timeout reads for the echo, and a wait
; (no limit) until APUIO0 is no longer !Audio_SeqHeader.
; Callers (1 JMP site): Audio_RunCommand_Dispatch ($C7:0188).
; Entry: M=1 (8-bit), X=0 (16-bit), DP=!DP_Audio, DB=0
; Exit:  does not return: leaves through Audio_CommandDone
; Callees: Audio_UploadBlock2F00 (JSR); Audio_CommandDone (JMP)
Audio_CmdBlockVariant:
    SEP #$20
    LDA.b !Audio_CmdArg0-!DP_Audio
    CLC
    ADC.b #!Audio_CarryIfNonzero        ; C = (Arg0 != 0)
    LDA.b #$00
    ROL A
    CMP.b !Audio_BlockInAram-!DP_Audio
    BEQ .done
    STA.b !Audio_Unk1E10-!DP_Audio
    STA.b !Audio_BlockInAram-!DP_Audio
    LDA.b #!Audio_SeqLive
    STA.w APUIO0
.wait_live:
    CMP.w APUIO0
    BNE .wait_live
    INC A
    AND.b #!Audio_SeqMask
    STA.b !Audio_Seq-!DP_Audio
    JSR Audio_UploadBlock2F00
    LDA.b #!Audio_SeqHeader
    LDX.w #!Audio_Timeout
    STA.w APUIO1
    STA.w APUIO0
.wait_echo:
    CMP.w APUIO0
    BEQ .wait_change
    DEX
    BNE .wait_echo
.wait_change:
    CMP.w APUIO0
    BEQ .wait_change
.done:
    JMP Audio_CommandDone

; $C7:0922 — Audio_UploadBlock2F00 (184 bytes, $0922–$09D9)
; Sends the $1800-byte block for ARAM !AudioAram_Block2F00:
; AudioRom_Block2F00 while Audio_Unk1E10 is 0, AudioRom_Block2F00Alt
; otherwise. Header: APUIO2/3 = $2F00, APUIO1 = !Audio_XferLive when
; Audio_CmdId is !Audio_Cmd70, else !Audio_XferTriples (kept in
; Audio_XferMode), APUIO0 = Audio_Seq; retried after Audio_AbortXfer
; until APUIO1 echoes the mode. Then the block's bytes, 3 per step
; (BNE loop; $1800 is a multiple of 3). Clears Audio_BlockDirty and
; sets Audio_Seq = !Audio_SeqHeader. The two blocks have their own copy
; of the loop.
; Callers (2 JSR sites): Audio_SendSongData ($C7:04D8) and Audio_CmdBlockVariant ($C7:0904).
; Entry: M any (it sets M=1), X=0 (16-bit), DP=!DP_Audio, DB=0
; Exit:  M=1, X=0; A, X, Y clobbered; Audio_Count = $1800; Audio_Ptr
;        set to the block
; Callees: Audio_SendSeq, Audio_AbortXfer
Audio_UploadBlock2F00:
    SEP #$20
    LDA.b #!AudioAram_Block2F00>>8
    STA.w APUIO3
    LDA.b #!AudioAram_Block2F00
    STA.w APUIO2
    LDA.b !Audio_CmdId-!DP_Audio
    CMP.b #!Audio_Cmd70
    BNE .load_mode
    LDA.b #!Audio_XferLive
    BRA .set_mode
.load_mode:
    LDA.b #!Audio_XferTriples
.set_mode:
    STA.w APUIO1
    STA.b !Audio_XferMode-!DP_Audio
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    LDA.b !Audio_XferMode-!DP_Audio
    CMP.w APUIO1
    BEQ .accepted
    JSR Audio_AbortXfer
    BRA Audio_UploadBlock2F00
.accepted:
    LDA.b !Audio_Unk1E10-!DP_Audio
    BNE .alt_block
    LDA.l !AudioRom_Block2F00
    STA.b !Audio_Count-!DP_Audio
    LDA.l !AudioRom_Block2F00+1
    STA.b !Audio_Count+1-!DP_Audio
    LDA.b #!AudioRom_Block2F00+2
    STA.b !Audio_Ptr-!DP_Audio
    LDA.b #(!AudioRom_Block2F00+2)>>8
    STA.b !Audio_Ptr+1-!DP_Audio
    LDA.b #!AudioRom_Block2F00>>16
    STA.b !Audio_Ptr+2-!DP_Audio
    LDX.b !Audio_Count-!DP_Audio
    LDY.w #$0000
.main_loop:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO1
    INY
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO2
    INY
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO3
    INY
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    DEX
    DEX
    DEX
    BNE .main_loop
    STZ.b !Audio_BlockDirty-!DP_Audio
    LDA.b #!Audio_SeqHeader
    STA.b !Audio_Seq-!DP_Audio
    RTS
.alt_block:
    LDA.l !AudioRom_Block2F00Alt
    STA.b !Audio_Count-!DP_Audio
    LDA.l !AudioRom_Block2F00Alt+1
    STA.b !Audio_Count+1-!DP_Audio
    LDA.b #!AudioRom_Block2F00Alt+2
    STA.b !Audio_Ptr-!DP_Audio
    LDA.b #(!AudioRom_Block2F00Alt+2)>>8
    STA.b !Audio_Ptr+1-!DP_Audio
    LDA.b #!AudioRom_Block2F00Alt>>16
    STA.b !Audio_Ptr+2-!DP_Audio
    LDX.b !Audio_Count-!DP_Audio
    LDY.w #$0000
.alt_loop:
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO1
    INY
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO2
    INY
    LDA.b [!Audio_Ptr-!DP_Audio],Y
    STA.w APUIO3
    INY
    LDA.b !Audio_Seq-!DP_Audio
    JSR Audio_SendSeq
    STA.b !Audio_Seq-!DP_Audio
    DEX
    DEX
    DEX
    BNE .alt_loop
    STZ.b !Audio_BlockDirty-!DP_Audio
    LDA.b #!Audio_SeqHeader
    STA.b !Audio_Seq-!DP_Audio
    RTS

; ============================================================
; Port helpers, echo delay, song start ($C7:09DA–$C7:0A97)
; ============================================================

; $C7:09DA — Audio_SendSeq (16 bytes, $09DA–$09E9)
; One step of a transfer: writes A to APUIO0 and waits (no limit) until
; APUIO0 reads back the same value, then returns the next sequence
; value, (A + 1) & !Audio_SeqMask. The data for the step must already
; be in APUIO1-3.
; Callers (32 JSR sites): Audio_CmdLoadSong ($C7:028B, $C7:02BF, $C7:02D6, $C7:02F0),
;   Audio_SendSampleDir ($C7:03DB, $C7:03FD, $C7:0420, $C7:044B, $C7:046E, $C7:0499),
;   Audio_SendSongData ($C7:04EE, $C7:056C, $C7:058C, $C7:05CF, $C7:05F7), Audio_UploadSample
;   ($C7:0691, $C7:06ED, $C7:070D), Audio_CmdSwapSample ($C7:07B2, $C7:07CA, $C7:07FF, $C7:081F,
;   $C7:083A, $C7:0850, $C7:086B, $C7:087F, $C7:0895, $C7:08A9, $C7:08BF) and Audio_UploadBlock2F00
;   ($C7:0941, $C7:0987, $C7:09C9).
; Entry: M any (P saved; it sets M=1), X any, DP any, DB=0 (APUIO0
;        through .w); A = the value to send
; Exit:  P as on entry (PLP); A's low byte = (value + 1) & $7F (B
;        unchanged); X, Y unchanged
Audio_SendSeq:
    PHP
    SEP #$20
    STA.w APUIO0
.wait:
    CMP.w APUIO0
    BNE .wait
    INC A
    AND.b #!Audio_SeqMask
    PLP
    RTS

; $C7:09EA — Audio_AbortXfer (19 bytes, $09EA–$09FC)
; Called when the APU did not echo a header's mode in APUIO1: sends one
; more step with APUIO0 = Audio_Seq (waits for the echo, no limit;
; APUIO1-3 as the header left them) and resets Audio_Seq to
; !Audio_SeqHeader, so the caller can send its header again. What the
; driver does with that step is not traced (probably it ends the
; transfer it did not take).
; Callers (7 JSR sites): Audio_SendSampleDir ($C7:03E7, $C7:042C, $C7:047A), Audio_SendSongData
;   ($C7:04FA, $C7:05DB), Audio_UploadSample ($C7:069D) and Audio_UploadBlock2F00 ($C7:094D).
; Entry: M any (P saved; it sets M=1), X any, DP=!DP_Audio, DB=0
; Exit:  P as on entry (PLP); A's low byte = !Audio_SeqHeader; X, Y
;        unchanged
Audio_AbortXfer:
    PHP
    SEP #$20
    LDA.b !Audio_Seq-!DP_Audio
    STA.w APUIO0
.wait:
    CMP.w APUIO0
    BNE .wait
    LDA.b #!Audio_SeqHeader
    STA.b !Audio_Seq-!DP_Audio
    PLP
    RTS

; $C7:09FD — Audio_SetEchoDelay (21 bytes, $09FD–$0A11)
; Audio_EchoDelay = A, Audio_EchoPage = !Audio_EchoTopPage - 8 x A,
; then Audio_DropEchoSlots. Nothing is sent to the APU here.
; Callers (2 JSR sites): Audio_CmdSend ($C7:064F) and Audio_StartSong ($C7:0A57).
; Entry: M any (P saved; it sets M=1), X=0 (16-bit, for
;        Audio_DropEchoSlots), DP=!DP_Audio, DB any; A = the delay (0-15)
; Exit:  P as on entry (PLP); A as Audio_DropEchoSlots leaves it; X
;        clobbered; Y unchanged
; Callees: Audio_DropEchoSlots
Audio_SetEchoDelay:
    PHP
    SEP #$20
    STA.b !Audio_EchoDelay-!DP_Audio
    ASL A
    ASL A
    ASL A
    EOR.b #!Eng_Invert8
    INC A
    CLC
    ADC.b #!Audio_EchoTopPage
    STA.b !Audio_EchoPage-!DP_Audio
    JSR Audio_DropEchoSlots
    PLP
    RTS

; $C7:0A12 — Audio_DropEchoSlots (39 bytes, $0A12–$0A38)
; Finds the first slot whose end (the next Audio_SlotAram entry; its
; high byte, the page) is on or above Audio_EchoPage and empties it and
; every slot after it: from there, byte by byte up to slot 16, zeroes
; Audio_SlotSample, Audio_SlotLen and the following Audio_SlotAram
; entries (through $1E81, the end of the 17-entry table). The slot's
; own start stays. Stops at the first slot whose end is 0 (no more
; slots in use).
; Callers (2 JSR sites): Audio_SendSongData ($C7:0616) and Audio_SetEchoDelay ($C7:0A0D).
; Entry: M any (P saved; it sets M=1), X=0 (16-bit), DP=!DP_Audio, DB
;        any
; Exit:  P as on entry (PLP); A = 0 or the last end page read; X
;        clobbered; Y unchanged
Audio_DropEchoSlots:
    PHP
    SEP #$20
    LDX.w #$0000
.find:
    LDA.b !Audio_SlotAram+3-!DP_Audio,X ; the slot's end page
    BEQ .done
    CMP.b !Audio_EchoPage-!DP_Audio
    BCS .drop
    INX
    INX
    CPX.w #!Audio_NumSlots
    BNE .find
    BRA .done
.drop:
    LDA.b #$00
.clear:
    STA.b !Audio_SlotSample-!DP_Audio,X
    STA.b !Audio_SlotLen-!DP_Audio,X
    STA.b !Audio_SlotAram+2-!DP_Audio,X
    INX
    CPX.w #!Audio_NumSlots
    BNE .clear
.done:
    PLP
    RTS

; $C7:0A39 — Audio_StartSong (95 bytes, $0A39–$0A97)
; The first part of a song load: sends the song command to the APU.
; Audio_CmdArg1 = byte 1 and Audio_CmdArg2 = byte 0's low nibble (the
; echo delay) of the song's AudioRom_SongEcho word (song & $7F); if
; that delay differs from Audio_EchoDelay, Audio_SetEchoDelay. Then
; APUIO3/2/1 = Arg2/Arg1/Arg0 and APUIO0 = Audio_CmdId, up to
; !Audio_Timeout reads for the echo; on a timeout the four writes are
; made again (no limit on the retries). After the echo, Audio_Seq =
; (command + 1) & $7F, and APUIO1 is read: with bit 7 clear it returns
; and the load goes on. With bit 7 set (the driver needs nothing more,
; probably: the song's data is already there; not traced) it sends
; APUIO0 = Audio_Seq, waits (no limit) while APUIO0 reads Audio_Seq - 1,
; then pulls P and its return address (three PLAs) and JMPs to
; Audio_CommandDone, ending the command without going back to
; Audio_CmdLoadSong.
; Callers (1 JSR site): Audio_CmdLoadSong ($C7:01AE).
; Entry: M any (P saved; it sets M=0, then M=1), X=0 (16-bit),
;        DP=!DP_Audio, DB=0; Audio_CmdArg0 = the song
; Exit:  bit 7 clear: P as on entry (PLP), A clobbered, X clobbered, Y
;        unchanged; bit 7 set: does not return to its caller (leaves
;        through Audio_CommandDone)
; Callees: Audio_SetEchoDelay (JSR); Audio_CommandDone (JMP)
Audio_StartSong:
    PHP
    REP #$20
    LDA.b !Audio_CmdArg0-!DP_Audio
    AND.w #!Audio_SongMask
    ASL A
    TAX
    SEP #$20
    LDA.l !AudioRom_SongEcho+1,X
    STA.b !Audio_CmdArg1-!DP_Audio
    LDA.l !AudioRom_SongEcho,X
    AND.b #!Audio_EchoDelayMask
    STA.b !Audio_CmdArg2-!DP_Audio
    CMP.b !Audio_EchoDelay-!DP_Audio
    BEQ .send
    JSR Audio_SetEchoDelay
.send:
    LDA.b !Audio_CmdArg2-!DP_Audio
    STA.w APUIO3
    LDA.b !Audio_CmdArg1-!DP_Audio
    STA.w APUIO2
    LDA.b !Audio_CmdArg0-!DP_Audio
    STA.w APUIO1
    LDA.b !Audio_CmdId-!DP_Audio
    STA.w APUIO0
    LDX.w #!Audio_Timeout
.wait_echo:
    CMP.w APUIO0
    BEQ .echoed
    DEX
    BNE .wait_echo
    BRA .send
.echoed:
    INC A
    AND.b #!Audio_SeqMask
    STA.b !Audio_Seq-!DP_Audio
    LDA.w APUIO1
    BPL .go_on
    LDA.b !Audio_Seq-!DP_Audio
    STA.w APUIO0
    DEC A
.wait_change:
    CMP.w APUIO0
    BEQ .wait_change
    PLA                                 ; P
    PLA                                 ; and the JSR's return address
    PLA
    JMP Audio_CommandDone
.go_on:
    PLP
    RTS

; ============================================================
; Tables ($C7:0A98–$C7:0E10)
; ============================================================

; $C7:0A98 — Audio_SongAliasTable (64 bytes, $0A98–$0AD7)
; Audio_CmdSongAlias: for command $30 + n, the command block it becomes
; (command, Arg0, Arg1, Arg2): $10, n, $FF, $FF.
Audio_SongAliasTable:
    db $10,$00,$FF,$FF, $10,$01,$FF,$FF, $10,$02,$FF,$FF, $10,$03,$FF,$FF
    db $10,$04,$FF,$FF, $10,$05,$FF,$FF, $10,$06,$FF,$FF, $10,$07,$FF,$FF
    db $10,$08,$FF,$FF, $10,$09,$FF,$FF, $10,$0A,$FF,$FF, $10,$0B,$FF,$FF
    db $10,$0C,$FF,$FF, $10,$0D,$FF,$FF, $10,$0E,$FF,$FF, $10,$0F,$FF,$FF

; $C7:0AD8 — Audio_SongBit2List (1 byte)
; Audio_AdjustSongCmd's song list, ended by a byte with bit 7 set. It
; holds only that end marker.
Audio_SongBit2List:
    db $FF

; $C7:0AD9 — Audio_SongCmdTable (16 bytes, $0AD9–$0AE8)
; Audio_RunCommand_Dispatch's jump table for commands $10-$17
; (JMP (T,X) with X = (command & $0F) x 2).
Audio_SongCmdTable:
    dw Audio_CmdLoadSong                ; $10
    dw Audio_CmdLoadSong                ; $11
    dw Audio_CommandDone                ; $12: nothing
    dw Audio_CommandDone                ; $13: nothing
    dw Audio_CmdLoadSong                ; $14
    dw Audio_CmdLoadSong                ; $15
    dw Audio_CommandDone                ; $16: nothing
    dw Audio_CommandDone                ; $17: nothing

; $C7:0AE9 — Audio_SongCount (1 byte)
; The number of songs (Audio_SongTable entries); Audio_CmdLoadSong
; ignores a song number not below it.
Audio_SongCount:
    db $53

; $C7:0AEA — Audio_SampleTable (186 bytes, $0AEA–$0BA3)
; 62 long pointers, one per sample (sample n at entry n - 1; 62 is the
; largest number in AudioRom_SongSamples): BRR data, probably (every
; length is a multiple of 9, the BRR block size), a 16-bit length first.
; Read by Audio_UploadSample and Audio_CmdSwapSample.
Audio_SampleTable:
    dl $C7730D, $C781AF, $C78952, $C78B82, $C79B68, $C7A314, $C7B4AA, $C7BEA8
    dl $C7CBD9, $C7DF94, $C7E3AA, $C7F540, $C803D0, $C80B2B, $C8139D, $C81CE7
    dl $C82E35, $C837FD, $C8467B, $C8567C, $C85A65, $C86DBD, $C87D64, $C8895A
    dl $C88F05, $C89696, $C8A2B9, $C8B218, $C8C648, $C8D4B4, $C8E1C1, $C8ECBB
    dl $C8FBAE, $C90E37, $C91B3B, $C939B8, $C9407A, $C94EC2, $C95959, $C96A05
    dl $C977AB, $C9A5DF, $C9B253, $C9BBF7, $C9D91E, $C9E496, $C9ED62, $C9F838
    dl $CA0797, $CA16F6, $CA21D5, $CA29F6, $CA300D, $CA3D3E, $CA42BC, $CA4867
    dl $CA52BF, $CA6122, $CA7C99, $CA7FD7, $CA831E, $CA8665

; $C7:0BA4 — Audio_SampleLoop (124 bytes, $0BA4–$0C1F)
; One word per sample: the loop start as an offset from the sample's
; ARAM start (Audio_SendSampleDir and Audio_CmdSwapSample add it to
; get the directory entry's second word).
Audio_SampleLoop:
    dw $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000
    dw $0000, $0000, $0000, $0000, $0000, $0000, $0000, $0000
    dw $057C, $0DF5, $0F5D, $037B, $0000, $0F6F, $07BC, $0573
    dw $0642, $0BAC, $0000, $13D4, $0477, $0546, $0000, $0A3B
    dw $0F6F, $0A5F, $001B, $069C, $0000, $0A71, $084C, $0678
    dw $0024, $0000, $0000, $001B, $0A9E, $0000, $0A83, $0000
    dw $0000, $0264, $0747, $05FA, $0000, $0000, $0573, $0A0E
    dw $001B, $0507, $0507, $0000, $0000, $0000

; $C7:0C20 — Audio_SampleParamA (124 bytes, $0C20–$0C9B)
; One word per sample, sent to !AudioAram_SongParamA for the song's
; samples (meaning not traced on the SPC700 side).
Audio_SampleParamA:
    dw $0000, $0020, $00A0, $0078, $0000, $0000, $0000, $0000
    dw $0043, $0000, $0000, $0000, $00C1, $00C0, $001E, $0000
    dw $00FE, $00D3, $9C52, $0052, $0000, $27A9, $00FF, $9C52
    dw $FCAD, $00B6, $0000, $74BB, $7FA0, $CC9F, $00C8, $0000
    dw $A4D7, $EC51, $0054, $6CE1, $007C, $00E1, $00AF, $00C9
    dw $0000, $0000, $0043, $F0E9, $74E1, $0000, $00FE, $0000
    dw $0000, $00EE, $00A9, $00A9, $0023, $0040, $C851, $00E1
    dw $00E1, $003C, $0000, $0000, $0000, $0000

; $C7:0C9C — Audio_SampleParamB (124 bytes, $0C9C–$0D17)
; One word per sample, sent to !AudioAram_SongParamB: first byte $FF or
; $FE; second byte $E0 for most, otherwise $EA-$F4; the ADSR pair,
; probably (from the values only).
Audio_SampleParamB:
    dw $E0FF, $E0FF, $E0FF, $E0FF, $E0FF, $E0FF, $E0FF, $E0FF
    dw $E0FF, $E0FF, $E0FF, $E0FF, $E0FF, $E0FF, $E0FF, $E0FF
    dw $E0FF, $E0FE, $EEFF, $EAFF, $E0FF, $E0FF, $E0FF, $EDFF
    dw $ECFF, $F0FF, $E0FF, $EEFF, $E0FF, $E0FF, $E0FF, $F3FF
    dw $EFFF, $E0FF, $E0FF, $E0FF, $E0FF, $E0FF, $EEFF, $EEFF
    dw $E0FF, $E0FF, $E0FF, $E0FF, $E0FF, $E0FF, $EEFF, $E0FF
    dw $E0FF, $E0FF, $ECFF, $E0FF, $F4FE, $F4FF, $EDFF, $E0FF
    dw $E0FF, $E0FF, $E0FF, $E0FE, $E0FE, $E0FE

; $C7:0D18 — Audio_SongTable (249 bytes, $0D18–$0E10)
; Audio_SongCount ($53) long pointers, one per song: its data, a 16-bit
; length first (Audio_SendSongData sends it to !AudioAram_Song).
Audio_SongTable:
    dl $CA8ACC, $CA8AF2, $CA8FB3, $CA944E, $CA9AB9, $CA9D85, $CA9EC3, $CAAAAA
    dl $CAABF4, $CAB1B2, $CAB522, $CAB94D, $CABC34, $CAC14E, $CAC8C0, $CAC67A
    dl $CAD0EC, $CAD213, $CAD355, $CAD3AE, $CADD81, $CAE0F4, $CAE6DD, $CAED54
    dl $CAF5FD, $CB010C, $CB0194, $CB0221, $CB05E3, $CB0788, $CB0B32, $CB10F4
    dl $CB13F2, $CB1456, $CB14D6, $CB156C, $CB1A31, $CB1AF2, $CB1C16, $CB1D59
    dl $CB22E1, $CB2C06, $CB340F, $CB3A38, $CB3B0B, $CB3E26, $CB4275, $CB430E
    dl $CB4796, $CB4A23, $CB4F0E, $CB5A6A, $CB60B1, $CB613F, $CB61FB, $CB658A
    dl $CB6627, $CB6F26, $CB7C50, $CB7D57, $CB8401, $CB8B50, $CB8C61, $CB9064
    dl $CBA338, $CBA454, $CBA56B, $CBA6CD, $CBA729, $CBAFA3, $CBB605, $CBBFD6
    dl $CBC186, $CBC2F9, $CBCC53, $CBCD4C, $CBCDBD, $CBCE33, $CBD315, $CBE040
    dl $CBE13E, $CBE88F, $CBEE21
