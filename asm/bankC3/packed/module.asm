; ============================================================
; The bank $C3 module (BankC3_PackedModule), unpacked
; WRAM $7E:3000-$7E:B57E ($857F bytes), stored packed at $C3:1313-$7A2B
;
; C3_BootModule unpacks the module with Decomp_ToWram to $7E:3000
; (C3Mod_Code) and jumps there; it is the jet-bike race program, about
; half code. Its source is matched here in unpacked form: this file is
; assembled on its own (asar, base $7E:3000) by tools/c3pack.py, which
; packs the result with the original packer's rules back to the 26,393
; bytes in ROM (build/c3pack/module.lz, incbin'd by bankC3.asm). The
; source must write every byte; what is not matched yet is incbin'd
; from the ROM's module, unpacked by the same tool to
; build/c3pack/rom_module.bin (%C3ModRomBytes), as unmatched bytes are
; left as ROM bytes elsewhere, under a label `C3Mod_Rest<addr>` that
; only marks where the block starts.
;
; Labels take the WRAM address ($7E:xxxx); %C3ModOrg(addr) starts a
; block at one. Headers give module addresses ($XXXX is $7E:XXXX).
; The module runs with DB = $00 (C3_BootModule keeps the field's) and,
; after C3Mod_Init, DP = 0 unless a header says otherwise. Callers are
; hand-written (`; Callers note:`): tools/c3module.py traces the module
; and tools/lint_c3module.py checks that every JSR, JSL, JMP, JML and
; BRL site the trace finds is named by its address.
; ============================================================

incsrc "module.inc"

; ============================================================
; Start, setup and leaving ($3000–$31BE)
; ============================================================

; $7E:3000 — C3Mod_Start (67 bytes, $3000–$3042)
; The module's entry point: C3_BootModule unpacks the module and jumps
; here. Sets everything up (C3Mod_Init), runs the program that
; C3_EntryArg bits 0-4 pick from C3Mod_ProgramTable (it returns once
; the program has set up its tasks, probably), uploads the palette
; (C3Mod_UploadPalette), waits for a vertical blank, runs one module
; frame by hand and turns on the NMI, the V-count IRQ and the
; auto-joypad read (Nmi_Nmitimen). From then on the module runs from
; its NMI (C3_ModuleNmi): this loop only waits for C3_ExitFlag. Then
; it turns the NMI, the IRQ and HDMA off and forces a blank, resets the
; sound (C3Mod_SoundReset), sets the stack back to StackTop and leaves
; through ReentryVectors entry [0], the warm restart into
; GameLoop_Main.
; The idle call at $3023 is self-modifying: programs write another
; routine's address over its operand ($3024: C3Mod_ScaleIdle at $3CE4,
; C3Mod_RotateMap at $70D7, C3Mod_Prog6ScaleIdle at $79B7,
; C3Mod_Prog10ScaleIdle at $8794 and $87D0, and back to C3Mod_Return at
; $96FE), so the loop runs that routine once per pass between frames; C3Mod_Return, the default, does nothing (an RTS).
; Callers note: reached only by C3_BootModule's JML !C3Mod_Code
;   ($C3:0073).
; Entry: M=1, X=0, DP any (C3Mod_Init sets DP = 0), DB=$00 (absolute
;        register and RAM stores); C3_EntryArg = the argument
;        C3_BootModule kept.
; Exit:  never returns: JML ReentryVectors with S = StackTop, M=1,
;        X=0, DP=0, DB=$00 (C3_ModuleFrame set it), A as
;        C3Mod_SoundReset leaves it, X = StackTop.
; Calls: C3Mod_Init, the program (JSR through C3Mod_ProgramTable),
;   C3Mod_UploadPalette, C3Mod_WaitVblank, C3_ModuleFrame (JSL),
;   C3Mod_Return, C3Mod_SoundReset.
%C3ModOrg($7E3000)
C3Mod_Start:
    JSR C3Mod_Init
    LDA.w !C3_EntryArg
    AND.b #!C3_ProgramMask
    ASL A
    TAX                                 ; B = 0 (C3Mod_Init leaves A = 0)
    JSR (C3Mod_ProgramTable,X)
    JSR C3Mod_UploadPalette
    JSR C3Mod_WaitVblank
    JSL !C3_ModuleFrame
    LDA.b #!Nmi_Nmitimen
    STA.w NMITIMEN
    REP #$20
    STZ.b !C3_ExitFlag
    STZ.w !C3_Paused
.wait_exit:
    JSR C3Mod_Return
    LDA.b !C3_ExitFlag
    BEQ .wait_exit
    LDA.w #FORCED_BLANK
    SEP #$20
    STZ.w NMITIMEN
    STZ.w HDMAEN
    STA.w INIDISP
    JSR C3Mod_SoundReset
    LDX.w #!StackTop
    TXS
    JML !ReentryVectors

; $7E:3043 — C3Mod_ProgramTable (32 bytes, $3043–$3062)
; The programs, by C3_EntryArg bits 0-4 (C3Mod_Start's JSR (table,X)
; at $300A). Only 16 entries: an argument of $10-$1F would read the
; code after the table. Several programs share an entry: 0 and 9; 7
; and 8; 10, 11, 14 and 15. What each program is has not been traced
; (the names are the entry numbers).
C3Mod_ProgramTable:
    dw C3Mod_Prog0, C3Mod_Prog1, C3Mod_Prog2, C3Mod_Prog3
    dw C3Mod_Prog4, C3Mod_Prog5, C3Mod_Prog6, C3Mod_Prog7
    dw C3Mod_Prog7, C3Mod_Prog0, C3Mod_Prog10, C3Mod_Prog10
    dw C3Mod_Prog12, C3Mod_Prog13, C3Mod_Prog10, C3Mod_Prog10

; $7E:3063 — C3Mod_Init (276 bytes, $3063–$3176)
; Sets the module up from whatever the field left:
;   - sets its variables: C3_FadeStep and C3_FadeTimer =
;     C3_FadeStepInit; the pause words, C3_NoSoftReset, C3_SongBusy,
;     C3_Brightness, C3_HdmaEnable, C3_RaceResult, C3_RacePrize and
;     C3_Unk0366 = 0;
;   - clears the direct page $0000-$00FF with DMA channel 7, reading
;     MPYL (M7A x M7B = $0404 x 0 = 0) the way ClearRAMDMA does;
;   - with C3_BootIrqOn in C3_EntryArg (entered from the field hook,
;     the display still on): clears $0920-$1DFF (from C3_TaskList,
;     the channel's other registers kept from the first fill) and
;     returns, with the PPU, the sound and the sprites as they were
;     and C3_OamHiPtr 0 (cleared with the direct page);
;   - else clears $0900-$1DFF (from Oam_HighTable); unless
;     C3_EntryNoSong is set, C3_SongReq = 0 and the sound is reset
;     (C3Mod_SoundReset); hides every sprite (C3Mod_HideSprites);
;     C3_OamHiPtr = Oam_HighTable; then sets the PPU registers
;     $2100-$2133 to a blank state: forced blank, OBSEL = C3_Obsel,
;     the others written 0 (mode 0, scrolls, mode-7 matrix, windows,
;     layers and colour math off; COLDATA first gets C3_ColdataBlack,
;     then 0, which selects no colour and so changes nothing). Left
;     untouched, never written: OAMDATA ($2104), VMADDL/H and
;     VMDATAL/H ($2116-$2119) and CGDATA ($2122).
; The 8-bit stores of the 16-bit pause words clear their high bytes
; one by one. The SEP #$20 / REP #$10 before the PPU part change
; nothing (M=1 and X=0 already). The scroll and mode-7 registers are
; written twice each (low, then high byte), M7Y once and then with
; STX, which also writes CGADD.
; Sub-entry: C3Mod_Return ($3176), its final RTS, which C3Mod_Start
; calls as an idle step and the script at $9450 adds as an NMI task
; (an empty one) and removes again.
; Callers note: C3Mod_Start ($3000). C3Mod_Return: C3Mod_Start
;   ($3023); the NMI task added by script opcode $F8 at $9453 and
;   removed by $F7 at $94C6 (script $9450, page $0A).
; Entry: M=1, X=0, DP any (set here: DP_DMA, DP_PPU, then 0), DB=$00
;        (absolute register and RAM stores).
; Exit:  M=1, X=0, DP=0, DB=$00; A = 0 (16-bit); X =
;        C3_ClearFromTasks on the C3_BootIrqOn path, else 0; Y
;        unchanged. C3Mod_Return: nothing changed.
; Calls: C3Mod_SoundReset, C3Mod_HideSprites.
C3Mod_Init:
    LDA.b #!C3_FadeStepInit
    STA.w !C3_FadeStep
    STA.w !C3_FadeTimer
    STZ.w !C3_RaceResult
    STZ.w !C3_RacePrize
    STZ.w !C3_PauseAllowed
    STZ.w !C3_Paused
    STZ.w !C3_PauseHeld
    STZ.w !C3_PauseAllowed+1
    STZ.w !C3_Paused+1
    STZ.w !C3_PauseHeld+1
    STZ.w !C3_NoSoftReset
    STZ.w !C3_SongBusy
    STZ.w !C3_Brightness
    STZ.w !C3_HdmaEnable
    STZ.w !C3_Unk0366
    PEA.w !DP_DMA
    PLD
    STA.w M7A
    STA.w M7A
    TDC                                 ; A = $00, the low byte of DP_DMA
    STA.w M7B
    STA.w M7B                           ; MPYL = 0 now
    LDX.w #!BBAD_MPYL<<8|!DMAP_BtoA
    STX.b DMAP7-!DP_DMA                 ; DMAP7 and BBAD7
    LDX.w #!DP_C3Zero                   ; destination $00:0000, the direct page
    STX.b A1T7L-!DP_DMA
    STZ.b A1B7-!DP_DMA
    LDX.w #!C3_DirectPageBytes
    STX.b DAS7L-!DP_DMA
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    PEA.w !DP_C3Zero
    PLD
    LDA.w !C3_EntryArg
    BIT.b #!C3_BootIrqOn
    BEQ .from_event
    LDX.w #!C3_TaskList
    STX.w A1T7L
    LDX.w #!C3_ClearFromTasks
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    TDC
    XBA
    RTS
.from_event:
    LDX.w #!Oam_HighTable
    STX.w A1T7L
    LDX.w #!C3_ClearFromOamHigh
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDA.w !C3_EntryArg
    BIT.b #!C3_EntryNoSong
    BNE .sound_done
    STZ.w !C3_SongReq
    JSR C3Mod_SoundReset
.sound_done:
    JSR C3Mod_HideSprites
    LDX.w #!Oam_HighTable
    STX.b !C3_OamHiPtr
    SEP #$20
    REP #$10
    PEA.w !DP_PPU
    PLD
    LDA.b #FORCED_BLANK
    STA.b INIDISP-!DP_PPU
    LDA.b #!C3_Obsel
    STA.b OBSEL-!DP_PPU
    LDA.b #!C3_ColdataBlack
    STA.b COLDATA-!DP_PPU
    LDX.w #0
    TDC
    XBA
    TXA                                 ; A = 0 (16-bit)
    STX.b OAMADDL-!DP_PPU
    STA.b BGMODE-!DP_PPU
    STA.b MOSAIC-!DP_PPU
    STX.b BG1SC-!DP_PPU                 ; and BG2SC
    STX.b BG3SC-!DP_PPU                 ; and BG4SC
    STX.b BG12NBA-!DP_PPU               ; and BG34NBA
    STA.b BG1HOFS-!DP_PPU
    STA.b BG1HOFS-!DP_PPU
    STA.b BG1VOFS-!DP_PPU
    STA.b BG1VOFS-!DP_PPU
    STA.b BG2HOFS-!DP_PPU
    STA.b BG2HOFS-!DP_PPU
    STA.b BG2VOFS-!DP_PPU
    STA.b BG2VOFS-!DP_PPU
    STA.b BG3HOFS-!DP_PPU
    STA.b BG3HOFS-!DP_PPU
    STA.b BG3VOFS-!DP_PPU
    STA.b BG3VOFS-!DP_PPU
    STA.b BG4HOFS-!DP_PPU
    STA.b BG4HOFS-!DP_PPU
    STA.b BG4VOFS-!DP_PPU
    STA.b BG4VOFS-!DP_PPU
    STA.b VMAIN-!DP_PPU
    STA.b M7SEL-!DP_PPU
    STA.b M7A-!DP_PPU
    STA.b M7A-!DP_PPU
    STA.b M7B-!DP_PPU
    STA.b M7B-!DP_PPU
    STA.b M7C-!DP_PPU
    STA.b M7C-!DP_PPU
    STA.b M7D-!DP_PPU
    STA.b M7D-!DP_PPU
    STA.b M7X-!DP_PPU
    STA.b M7X-!DP_PPU
    STA.b M7Y-!DP_PPU
    STX.b M7Y-!DP_PPU                   ; and CGADD
    STX.b W12SEL-!DP_PPU                ; and W34SEL
    STA.b WOBJSEL-!DP_PPU
    STX.b WH0-!DP_PPU                   ; and WH1
    STX.b WH2-!DP_PPU                   ; and WH3
    STX.b WBGLOG-!DP_PPU                ; and WOBJLOG
    STX.b TM-!DP_PPU                    ; and TS
    STX.b TMW-!DP_PPU                   ; and TSW
    STX.b CGWSEL-!DP_PPU                ; and CGADSUB
    STX.b COLDATA-!DP_PPU               ; and SETINI
    PEA.w !DP_C3Zero
    PLD
C3Mod_Return:                           ; header: see C3Mod_Init
    RTS

; $7E:3177 — C3Mod_SoundReset (57 bytes, $3177–$31AF)
; Unless C3_EntryNoSong is set in C3_EntryArg (then it returns at
; once, through C3Mod_Return), sends the sound driver five commands
; (C3Mod_AudioSend each): C3_SndTempoPitch and C3_SndSfxPitch with
; arguments 0, 0 (no pitch or tempo adjustment, probably), then
; C3_SndStopSfx with Arg0 0 and with Arg0 1 (both effect groups
; stopped), and last C3_SndFadeSong with Arg0 0 and Arg1 $FF (the
; song's volume to $FF at once, as LocLoad_AudioSetup sends it).
; Audio_CmdArg2 is never written here.
; Callers note: C3Mod_Start ($3038) and C3Mod_Init ($30F3).
; Entry: M=1, X=0, DP any, DB=$00 (the Audio_Cmd* block is absolute).
; Exit:  M=1, X=0, DP and DB unchanged; A = C3_SndFadeSong (or
;        C3_EntryArg on the early return); X = the polls C3Mod_AudioSend
;        left (unchanged on the early return); Y unchanged;
;        Audio_CmdId.. Arg1 = the last command.
; Calls: C3Mod_AudioSend (JMP for the last one).
C3Mod_SoundReset:
    LDA.w !C3_EntryArg
    BIT.b #!C3_EntryNoSong
    BNE C3Mod_Return
    STZ.w !Audio_CmdArg1
    LDX.w #!C3_SndTempoPitch
    STX.w !Audio_CmdId                  ; and Arg0 = 0
    JSR C3Mod_AudioSend
    LDA.b #!C3_SndSfxPitch
    STA.w !Audio_CmdId
    JSR C3Mod_AudioSend
    LDA.b #!C3_SndStopSfx
    STA.w !Audio_CmdId
    JSR C3Mod_AudioSend
    LDA.b #1
    STA.w !Audio_CmdArg0
    JSR C3Mod_AudioSend
    LDX.w #!C3_SndFullVolume
    STX.w !Audio_CmdArg0                ; and Arg1
    LDA.b #!C3_SndFadeSong
    STA.w !Audio_CmdId
    JMP C3Mod_AudioSend

; $7E:31B0 — C3Mod_WaitVblank (15 bytes, $31B0–$31BE)
; Waits for the start of a vertical blank: first for HVBJOY bit 7 to
; clear (out of any blank already under way), then for it to set.
; Callers note: C3Mod_Start ($3010) and C3Mod_Prog5 ($710F).
; Entry: M=1, X any, DP any, DB=$00 (HVBJOY is absolute).
; Exit:  M=1; A = HVBJOY; X, Y, DP and DB unchanged.
C3Mod_WaitVblank:
    LDA.w HVBJOY
    BIT.b #!HVBJOY_VBlank
    BNE C3Mod_WaitVblank
.wait_start:
    LDA.w HVBJOY
    BIT.b #!HVBJOY_VBlank
    BEQ .wait_start
    RTS

; ============================================================
; Math, random numbers, sine ($31BF–$347A)
; ============================================================

; $7E:31BF — C3Mod_Mul16 (74 bytes, $31BF–$3208)
; Unsigned 16 x 16-bit multiply with the CPU's 8 x 8 multiplier:
; C3Math_Lo/Hi ($F4-$F7) = C3Math_A x C3Math_B, from the four byte
; products (low x low, the two cross products added together, high x
; high). DB is set to 0 for the multiplier registers (and restored).
; Quirk: the carry of the cross-product sum is kept with a 16-bit ROL of
; $F7 (where the high word's high byte will be), which also shifts the
; byte after it, $F8, left by one, and brings its bit 7 in as the carry
; of the next add: the product is one too big in its bits 8-23 when
; $F8 bit 7 is set (the callers leave $F8 as it is). Second quirk: the
; carry out of ADC $F5 (the cross-product sum plus the low product's
; high byte) goes into the next ADC $F6, so it lands at bit 16 instead
; of bit 24: when that sum overflows the product is $00FF0000 too
; small (e.g. $24E1 x $FAFD gives $23292C5D, not $24282C5D).
; Callers note: C3Mod_MulSigned16 ($33F0) and $3591, $35A7, $35C9,
;   $35E8, C3Mod_Perspective ($4F4A), C3Mod_ScaleByVar0 ($56DE),
;   C3Mod_RockTask ($5BE7, $5C05, $5C22), C3Mod_SwingTask ($5CCD,
;   $5CF0), C3Mod_WaveTask ($6025) and $99CB and $99EB (code not matched
;   yet).
; Entry: M=0 (16-bit A for the product reads), X=0 (X and Y are pushed
;        and pulled as words), DP = the page of C3Math_A.. (the
;        script's page at C3Mod_BuildM7Tables' calls $3591-$35E8, the
;        caller's own at C3Mod_MulSigned16's, 0 at C3Mod_Perspective's
;        and at the tasks C3Mod_RockTask, C3Mod_SwingTask and
;        C3Mod_WaveTask, $0A00 at C3Mod_ScaleByVar0's; the others' not
;        traced),
;        DB any (saved); C3Math_A, C3Math_B = the operands.
; Exit:  P, X, Y, DB restored; A = the product's high word; C3Math_Lo
;        and C3Math_Hi = the product; $F8 shifted left (see above).
%C3ModOrg($7E31BF)
C3Mod_Mul16:
    PHP
    PHB
    PHX
    PHY
    SEP #$10
    LDY.b #0
    PHY
    PLB                                 ; DB = $00
    LDX.b !C3Math_B
    LDY.b !C3Math_A
    STX.w WRMPYA
    STY.w WRMPYB                        ; A low x B low
    LDY.b !C3Math_A+1
    STZ.b !C3Math_Hi
    LDA.w RDMPYL
    STY.w WRMPYB                        ; A high x B low
    STA.b !C3Math_Lo
    LDX.b !C3Math_B+1
    LDY.b !C3Math_A
    LDA.w RDMPYL
    STX.w WRMPYA
    STY.w WRMPYB                        ; A low x B high
    LDY.b !C3Math_A+1
    CLC
    ADC.w RDMPYL                        ; the cross products
    ROL.b !C3Math_Hi+1                  ; their carry to $F7 (and $F8 shifted: see above)
    STY.w WRMPYB                        ; A high x B high
    ADC.b !C3Math_Lo+1
    STA.b !C3Math_Lo+1
    LDA.w RDMPYL
    ADC.b !C3Math_Hi
    STA.b !C3Math_Hi
    REP #$10
    PLY
    PLX
    PLB
    PLP
    RTS

; $7E:3209 — C3Mod_Div16 (217 bytes, $3209–$32E1)
; Unsigned 16-bit divide, unrolled: C3Math_Lo = A / C3Math_B, A = the
; remainder; C3Math_A (the dividend, stored from A) is shifted out to
; 0. Quirk: a remainder from $8000 up loses its top bit in the ROL A,
; so the result is right only for divisors up to $8000.
; Callers note: only C3Mod_DivSigned16 ($3425), which nothing calls.
; Entry: M=0, X any, DP = the page of C3Math_A.. ; DB any; A = the
;        dividend, C3Math_B = the divisor (not 0).
; Exit:  A = the remainder, C3Math_Lo = the quotient, C3Math_A = 0;
;        C3Math_B, X, Y, P's M and X unchanged.
C3Mod_Div16:
    STA.b !C3Math_A
    LDA.w #0
    STA.b !C3Math_Lo
    CLC
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    %C3ModDivStep()
    RTS

; $7E:32E2 — C3Mod_DivHighByte (189 bytes, $32E2–$339E)
; Divides the dividend's high byte x 256 by C3Math_B, unrolled:
; C3Math_Lo = (A AND $FF00) / C3Math_B, A = the remainder. The first 8
; steps shift in the dividend's bits 15-8; the last 8 shift in zeros
; (ASL) where C3Mod_Div16 would take bits 7-0 (so the low byte is
; ignored: probably on purpose, a fraction of 256ths). It subtracts
; C3Math_B - 1 (in C3Math_Q) with the carry clear from the shift, one
; instruction less than SEC / SBC. Quirk: as for C3Mod_Div16, a remainder
; from $8000 up (a divisor above $8000) gives a wrong step.
; Callers note: C3Mod_SizeBike ($4E30, $4E43, $4E55), C3Mod_SizeRival
;   ($4EAB, $4EBF), C3Mod_Prog6Sprites ($8210) and C3Mod_Prog10ScaleIdle
;   ($896E).
; Entry: M=0, X any, DP = the page of C3Math_A.. (0 at the five
;        C3Mod_Size* calls and at C3Mod_Prog6Sprites' and
;        C3Mod_Prog10ScaleIdle's); DB any; A = the dividend, C3Math_B = the divisor.
;        A divisor of 0 (C3Mod_Prog6Sprites' first call, from
;        C3Mod_Prog6, with page $0B00's var 0 still 0) makes every step
;        fail: C3Math_Lo = 0, A = the dividend AND $FF00, C3Math_Q =
;        $FFFF.
; Exit:  A = the remainder (with a divisor of 0: see above),
;        C3Math_Lo = the quotient; C3Math_A shifted
;        left by 8, with the entry carry in bit 7 (the first ROL takes
;        it in, the next seven take in zeros); C3Math_Q = the divisor -
;        1; X, Y unchanged.
C3Mod_DivHighByte:
    STA.b !C3Math_A
    LDA.b !C3Math_B
    DEC A
    STA.b !C3Math_Q
    LDA.w #0
    STA.b !C3Math_Lo
    %C3ModDivHighStep()
    %C3ModDivHighStep()
    %C3ModDivHighStep()
    %C3ModDivHighStep()
    %C3ModDivHighStep()
    %C3ModDivHighStep()
    %C3ModDivHighStep()
    %C3ModDivHighStep()
    %C3ModDivZeroStep()
    %C3ModDivZeroStep()
    %C3ModDivZeroStep()
    %C3ModDivZeroStep()
    %C3ModDivZeroStep()
    %C3ModDivZeroStep()
    %C3ModDivZeroStep()
    %C3ModDivZeroStep()
    RTS

; $7E:339F — C3Mod_Div32 (55 bytes, $339F–$33D5)
; Unsigned 32-bit divide, 32 steps: C3Math_Q ($F8-$FB) = the dividend
; ($F0-$F3: C3Math_A low word, C3Math_B high word) / the divisor ($F4-$F7:
; C3Math_Lo, C3Math_Hi), C3Math_R ($FC-$FF) = the remainder. The
; dividend words are shifted left 32 times on the way (what comes in
; at their bottom is not used). Quirk: the remainder is shifted left
; (ROL) before the trial subtract and its top bit is lost, so the
; result is wrong for divisors of $80000000 or more (the only caller
; passes a high word of 0).
; Callers note: C3Mod_RockTask ($5C44).
; Entry: M=0, X=0 (the 16-bit step count), DP = the page of C3Math_A..
;        (0 at the call); DB any; the dividend and the divisor (not 0) as
;        above.
; Exit:  C3Math_Q = the quotient, C3Math_R = the remainder; A = the
;        remainder's high word; X = 0; Y unchanged; C3Math_A/B shifted.
C3Mod_Div32:
    STZ.b !C3Math_Q+2
    STZ.b !C3Math_Q
    STZ.b !C3Math_R+2
    STZ.b !C3Math_R
    LDX.w #!C3_Div32Steps
.step:
    ROL.b !C3Math_A
    ROL.b !C3Math_B
    ROL.b !C3Math_R
    ROL.b !C3Math_R+2
    SEC
    LDA.b !C3Math_R
    SBC.b !C3Math_Lo
    STA.b !C3Math_R
    LDA.b !C3Math_R+2
    SBC.b !C3Math_Hi
    STA.b !C3Math_R+2
    BCS .fits
    LDA.b !C3Math_R
    ADC.b !C3Math_Lo
    STA.b !C3Math_R
    LDA.b !C3Math_R+2
    ADC.b !C3Math_Hi
    STA.b !C3Math_R+2
    CLC
.fits:
    ROL.b !C3Math_Q
    ROL.b !C3Math_Q+2
    DEX
    BNE .step
    RTS

; $7E:33D6 — C3Mod_MulSigned16 (55 bytes, $33D6–$340C)
; Signed 16 x 16-bit multiply: the operands are made positive in place,
; multiplied (C3Mod_Mul16) and the 32-bit product negated when their
; signs differed. C3Mod_Mul16's two quirks carry over (the magnitudes'
; product one too big in bits 8-23 with $F8 bit 7 set, or $00FF0000
; too small when its middle sum overflows), before the negation.
; Callers note: C3Mod_ViewOffsetTask ($4458, $446B), C3Mod_SizeBike
;   ($4E61), C3Mod_SizeRival ($4ECB) and $9939, $9953, $9B0A and $9B1D
;   (code not matched yet).
; Entry: M=0, X=0 (C3Mod_Mul16's), DP = the page of C3Math_A.. ($0A00 at
;        C3Mod_ViewOffsetTask's calls, 0 at C3Mod_SizeBike's and
;        C3Mod_SizeRival's; the others' not traced); DB any;
;        C3Math_A, C3Math_B = the signed operands.
; Exit:  P restored; C3Math_Lo/Hi = the signed product; C3Math_A and
;        C3Math_B = the operands' magnitudes; A = the product's high
;        word; X, Y unchanged; $F8 as C3Mod_Mul16 leaves it.
; Calls: C3Mod_Mul16.
C3Mod_MulSigned16:
    PHP
    LDA.b !C3Math_A
    EOR.b !C3Math_B
    PHP                                 ; N: the signs differ
    LDA.b !C3Math_A
    BPL .a_positive
    EOR.w #!Eng_Invert16
    INC A
.a_positive:
    STA.b !C3Math_A
    LDA.b !C3Math_B
    BPL .b_positive
    EOR.w #!Eng_Invert16
    INC A
.b_positive:
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    PLP
    BPL .done
    CLC
    LDA.b !C3Math_Lo
    EOR.w #!Eng_Invert16
    ADC.w #1
    STA.b !C3Math_Lo
    LDA.b !C3Math_Hi
    EOR.w #!Eng_Invert16
    ADC.w #0
    STA.b !C3Math_Hi
.done:
    PLP
    RTS

; $7E:340D — C3Mod_DivSigned16 (54 bytes, $340D–$3442)
; A signed counterpart of C3Mod_Div16 that nothing calls (no call site,
; no table or stored address found): it takes the magnitudes of
; C3Math_B and C3Math_A, divides (C3Mod_Div16) and, when the signs
; differed, takes the magnitudes of C3Math_Lo and C3Math_Hi again
; instead of negating the quotient, so the sign is never applied. It
; also loads C3Math_Hi, which C3Mod_Div16 does not write, in place of
; the remainder. Kept as it is (dead code, probably unfinished).
; Entry: M=0, X any, DP = the page of C3Math_A..; DB any; C3Math_A,
;        C3Math_B = the signed dividend and divisor.
; Exit:  P restored; C3Math_Lo = |the quotient|; A = C3Math_Hi (or its
;        magnitude); C3Math_A = 0; C3Math_B = |the divisor|.
; Calls: C3Mod_Div16.
C3Mod_DivSigned16:
    PHP
    LDA.b !C3Math_A
    EOR.b !C3Math_B
    PHP                                 ; N: the signs differ
    LDA.b !C3Math_B
    BPL .b_positive
    EOR.w #!Eng_Invert16
    INC A
.b_positive:
    STA.b !C3Math_B
    LDA.b !C3Math_A
    BPL .a_positive
    EOR.w #!Eng_Invert16
    INC A
.a_positive:
    JSR C3Mod_Div16
    LDA.b !C3Math_Hi                    ; not the remainder (see above)
    PLP
    BPL .done
    LDA.b !C3Math_Lo
    BPL .lo_positive
    EOR.w #!Eng_Invert16
    INC A
.lo_positive:
    STA.b !C3Math_Lo
    LDA.b !C3Math_Hi
    BPL .hi_positive
    EOR.w #!Eng_Invert16
    INC A
.hi_positive:
    STA.b !C3Math_Hi
.done:
    PLP
    RTS

; $7E:3443 — C3Mod_KernelRandom (5 bytes, $3443–$3447)
; The kernel's random byte (C3_RandomByte) for code in the module (a JSR
; target for the JSL).
; Callers note: C3Mod_InitStars ($577A, $5780, $5786), C3Mod_StarsTask
;   ($57B3, $57B9), C3Mod_Prog5MosaicTask ($7397), C3Mod_Prog6HorizonTask
;   ($7F85, $7FA0), C3Mod_Prog6RandomPair ($80A6), C3Mod_Prog6RandomWord
;   ($80D3) and $98E3 and $98EE (code not matched yet).
; Entry: M, X, DP and DB as C3_RandomByte needs; X=0 at the calls, M=1
;        at $577A, $5780, $5786, $57B3, $57B9, $7397 and $80A6, M=0 at
;        $7F85, $7FA0, $80D3, $98E3 and $98EE (there C3_RandomByte's adds
;        are 16-bit, it stores a word to C3_RandSeed, and the callers
;        mask the result with an AND); DB = $00 at all but
;        C3Mod_Prog6RandomPair's and C3Mod_Prog6RandomWord's calls
;        ($80A6, $80D3), which run with DB = $7E: there C3_RandomByte's
;        absolute counter reads (SLHV, OPHCT, OPVCT) read WRAM bytes of
;        C3_PaletteWork instead (a quirk; see C3Mod_Prog6ShuffleTask).
; Exit:  as C3_RandomByte leaves them (A = the new C3_RandSeed, a byte
;        or a word by M).
; Calls: C3_RandomByte (JSL).
C3Mod_KernelRandom:
    JSL !C3_RandomByte
    RTS

; $7E:3448 — C3Mod_TableRandom (25 bytes, $3448–$3460)
; The next byte of RandomTable: C3_RandIndex goes up by one (wrapping at
; 256; the AND #$FF after the INC changes nothing) and indexes the
; table. B is set to DP's low byte first (TDC / XBA), so that the TAX
; makes a 16-bit index of the byte: right only with DP on a page
; boundary ($0A00 at C3Mod_PickRun's and C3Mod_PickDrift's calls, the
; scripts' page; 0 at C3Mod_NewSpark's; the others' not traced).
; Callers note: C3Mod_PickRun ($3F59, a script routine), C3Mod_NewSpark
;   ($65AE, $65BF, $65C9), C3Mod_PickDrift ($728E, a script routine) and
;   $9BE1 (code not matched yet).
; Entry: M any (saved; 8-bit here), X any (saved; with X=1 the TAX
;        takes the byte alone), DP = a page boundary, DB any (the reads
;        and the store are long).
; Exit:  P and X restored; A = the random byte, B = DP's low byte (so A
;        as a word is the byte when M=0 at the call).
C3Mod_TableRandom:
    PHP
    PHX
    SEP #$20
    TDC
    XBA                                 ; B = DP's low byte (0)
    LDA.l !C3_RandIndex
    INC A
    AND.b #!Eng_LowByteMask             ; changes nothing (the INC wraps at 256 already)
    STA.l !C3_RandIndex
    TAX
    LDA.l !RandomTable,X
    PLX
    PLP
    RTS

; $7E:3461 — C3Mod_Cosine (25 bytes with C3Mod_Sine, $3461–$3479)
; Minus the sine of the angle in A (1,024 steps per turn) as a signed
; 16-bit value of magnitude 0-$FF from Rom_SineTable's |sin| bytes,
; negative for angles $000-$1FF and positive for $200-$3FF (so -sin,
; probably for the screen's downward y). C3Mod_Cosine adds a quarter
; turn and falls into C3Mod_Sine ($3465), so it gives -cos.
; Callers note: C3Mod_BuildM7Tables ($357F), C3Mod_ViewOffsetTask
;   ($444F), C3Mod_ProjectTask ($4D19), C3Mod_SpinTask ($56B6),
;   C3Mod_StarDriftTask ($5867), C3Mod_RockTask ($5BD7, $5BFB),
;   C3Mod_SwingTask ($5CBC), C3Mod_RotateMatrixTask ($73C9),
;   C3Mod_CharSpin ($76DB) and $994A, $9990, $99DB and $9B01 (code not
;   matched yet). C3Mod_Sine: C3Mod_BuildM7Tables ($35B7),
;   C3Mod_ViewOffsetTask ($4462), C3Mod_ProjectTask ($4D26),
;   C3Mod_SpinTask ($56C2), C3Mod_StarDriftTask ($585B), C3Mod_RockTask
;   ($5C11), C3Mod_SwingTask ($5CE0), C3Mod_WaveTask ($6014),
;   C3Mod_Bg3WaveTask ($73BD), C3Mod_RotateMatrixTask ($73FD),
;   C3Mod_CharSpin ($76FE) and $9930, $9983, $99BB and $9B14 (code not
;   matched yet).
; Entry: M=0, X=0 (16-bit index), DP any, DB any (the read is long); A
;        = the angle (only bits 0-9 count).
; Exit:  A = the signed value; X = the angle AND C3_AngleMask entered
;        at C3Mod_Sine, (the angle + C3_QuarterTurn) AND C3_AngleMask
;        entered at C3Mod_Cosine; Y unchanged.
C3Mod_Cosine:
    CLC
    ADC.w #!C3_QuarterTurn
C3Mod_Sine:                             ; header: see C3Mod_Cosine
    AND.w #!C3_AngleMask
    TAX
    LDA.l !Rom_SineTable,X
    AND.w #!Eng_LowByteMask
    CPX.w #!C3_HalfTurn
    BCS .done
    EOR.w #!Eng_Invert16
    INC A
.done:
    RTS

; ============================================================
; Fade tasks ($347A–$34FA)
; ============================================================

; $7E:347A — C3Mod_FadeInTask (27 bytes, $347A–$3494)
; A task: every C3_FadeStep frames (C3_FadeTimer counts them down), one
; step brighter (C3_Brightness + 1); at full brightness it ends itself
; (C3Mod_TaskEnd).
; Callers note: a task: LDX #C3Mod_FadeInTask / JSR $395E at $6BD8
;   (C3Mod_Prog1); added by script opcode $FA at $3F29
;   (C3Mod_Prog0ScriptA), $554C (C3Mod_Prog4ScriptA), $6399
;   (C3Mod_Prog7Start), $6905 (C3Mod_Prog3ScriptA), $7C93
;   (C3Mod_Prog6Script), $918E, $933D, $9403, $9528 and $966B, removed by
;   $F9 at $92C1 and $961F (the others: code and scripts not matched yet).
; Entry: a task (C3Mod_RunTasks): M=0 (8-bit set here), X=0, DP any, DB
;        = $00 (the variables are absolute).
; Exit:  RTS with M=1; A = C3_Brightness after a step, else as on entry
;        (the DEC of C3_FadeTimer loads nothing); at the end JMP
;        C3Mod_TaskEnd.
C3Mod_FadeInTask:
    SEP #$20
    DEC.w !C3_FadeTimer
    BNE .wait
    LDA.w !C3_FadeStep
    STA.w !C3_FadeTimer
    INC.w !C3_Brightness
    LDA.w !C3_Brightness
    CMP.b #!C3_BrightnessFull
    BEQ .end
.wait:
    RTS
.end:
    JMP C3Mod_TaskEnd

; $7E:3495 — C3Mod_FadeOutTask (22 bytes, $3495–$34AA)
; A task: every C3_FadeStep frames one step darker (C3_Brightness - 1);
; at 0 (C3_ModuleFrame then shows forced blank) it ends itself.
; Callers note: a task added by script opcode $FA at $41F6
;   (C3Mod_Prog0Finish), $423F (C3Mod_Prog0Quit), $9149, $91A0, $91F5,
;   $9280, $94E6 and $96CB, and by LDX #C3Mod_FadeOutTask / JSR $395E at
;   $63E8 (C3Mod_ResetWaitTask; the others: code and scripts not matched
;   yet).
; Entry: a task: M=0 (8-bit set here), X=0, DP any, DB = $00.
; Exit:  RTS with M=1; A = C3_FadeStep after a step, else as on entry;
;        at the end JMP C3Mod_TaskEnd.
C3Mod_FadeOutTask:
    SEP #$20
    DEC.w !C3_FadeTimer
    BNE .wait
    LDA.w !C3_FadeStep
    STA.w !C3_FadeTimer
    DEC.w !C3_Brightness
    BEQ .end
.wait:
    RTS
.end:
    JMP C3Mod_TaskEnd

; $7E:34AB — C3Mod_MusicFadeTask (23 bytes, $34AB–$34C1)
; A task that runs once: it has the sound driver fade the song out
; (C3_SndFadeSong, $40 steps to volume 0, by Audio_DriverCommand) and
; hands its entry over to C3Mod_FadeOutStopTask (C3Mod_TaskReplace).
; Callers note: a task added by script opcode $FA at $5B92
;   (C3Mod_Prog2Wave) and by LDX #C3Mod_MusicFadeTask / JSR $395E at
;   $5BA9 (C3Mod_SkipTask, M=1).
; Entry: a task: M=0 (8-bit set here), X=0, DP any, DB = $00 (the
;        Audio_Cmd* block is absolute).
; Exit:  JMP C3Mod_TaskReplace with X = C3Mod_FadeOutStopTask.
; Calls: Audio_DriverCommand (JSL).
C3Mod_MusicFadeTask:
    SEP #$20
    LDX.w #!C3_SndFadeOut
    STX.w !Audio_CmdArg0                ; and Arg1 = 0
    LDA.b #!C3_SndFadeSong
    STA.w !Audio_CmdId
    JSL !Audio_DriverCommand
    LDX.w #C3Mod_FadeOutStopTask
    JMP C3Mod_TaskReplace

; $7E:34C2 — C3Mod_FadeOutStopTask (33 bytes, $34C2–$34E2)
; A task: fades out as C3Mod_FadeOutTask; at 0 it stops all sound
; (C3_SndStopAll) and sets C3_ExitFlag (INC of its low byte), so the
; module leaves (C3Mod_Start), and ends itself.
; Callers note: a task by replacement: LDX #C3Mod_FadeOutStopTask /
;   JMP C3Mod_TaskReplace in C3Mod_MusicFadeTask ($34BC).
; Entry: a task: M=0 (8-bit set here), X=0, DP=0 (C3_ExitFlag is
;        direct page), DB = $00.
; Exit:  RTS with M=1; at the end JMP C3Mod_TaskEnd.
; Calls: Audio_DriverCommand (JSL).
C3Mod_FadeOutStopTask:
    SEP #$20
    DEC.w !C3_FadeTimer
    BNE .wait
    LDA.w !C3_FadeStep
    STA.w !C3_FadeTimer
    DEC.w !C3_Brightness
    BEQ .end
.wait:
    RTS
.end:
    LDA.b #!C3_SndStopAll
    STA.w !Audio_CmdId
    JSL !Audio_DriverCommand
    INC.b !C3_ExitFlag
    JMP C3Mod_TaskEnd

; $7E:34E3 — C3Mod_FadeOutExitTask (24 bytes, $34E3–$34FA)
; A task: fades out as C3Mod_FadeOutTask; at 0 it sets C3_ExitFlag (the
; module leaves) and ends itself.
; Callers note: a task added by script opcode $FA at $562F
;   (C3Mod_Prog4End), $6978 (C3Mod_Prog3ScriptB), $727F
;   (C3Mod_Prog5ScriptB), $7EC1 (C3Mod_Prog6ScriptB), $931F and $95FE, by
;   LDX #C3Mod_FadeOutExitTask / JSR $395E at $4684 (C3Mod_RaceTask), and
;   by LDX #C3Mod_FadeOutExitTask / JMP C3Mod_TaskReplace at $6BF3
;   (C3Mod_CreditsTask; the others: code and scripts not matched yet).
; Entry: a task: M=0 (8-bit set here), X=0, DP=0, DB = $00.
; Exit:  RTS with M=1; at the end JMP C3Mod_TaskEnd.
C3Mod_FadeOutExitTask:
    SEP #$20
    DEC.w !C3_FadeTimer
    BNE .wait
    LDA.w !C3_FadeStep
    STA.w !C3_FadeTimer
    DEC.w !C3_Brightness
    BEQ .end
.wait:
    RTS
.end:
    INC.b !C3_ExitFlag
    JMP C3Mod_TaskEnd

; ============================================================
; Square root, fill bytes, nibble unpackers ($34FB–$355E)
; ============================================================

; $7E:34FB — C3Mod_SquareRoot (15 bytes, $34FB–$3509)
; The square root of A, rounded to the nearest: C3_SqrtRoot = k after
; subtracting 0, 0, 1, 1, 2, 2, ... (each k twice) until A would go
; below 0. With the carry clear on entry the first subtraction takes 1
; more, and the result is round(sqrt(A)) (checked for every 16-bit A);
; with it set, round(sqrt(A + 1)). Its caller enters with the carry of
; an ADC (clear unless the sum overflowed).
; Callers note: C3Mod_CharPolar ($7699).
; Entry: M=0, X any, DP = the page of C3_SqrtRoot (0 at the call); DB
;        any; A = the value; C as above.
; Exit:  C3_SqrtRoot = the root; A = A minus the sum taken, including
;        the failed last subtraction, so it has wrapped below 0
;        (16-bit); C clear; X, Y unchanged.
C3Mod_SquareRoot:
    STZ.b !C3_SqrtRoot
.take:
    SBC.b !C3_SqrtRoot
    BCC .done
    SBC.b !C3_SqrtRoot
    BCC .done
    INC.b !C3_SqrtRoot
    BRA .take
.done:
    RTS

; $7E:350A — C3Mod_FillBytes (4 bytes, $350A–$350D)
; DMA fill sources: the zero word at $350B is the fixed source of the
; VRAM fills at $3D9D (C3Mod_Prog0LoadGfx: DMAP $09 to VMDATAL: fixed
; address, two registers, so whole words cleared), $5AEE
; (C3Mod_MapToM7: DMAP $08 to VMDATAL, one register, only the low bytes
; cleared; C3Mod_Prog2's fill after it keeps that source with DMAP $09)
; and $90B0 (C3Mod_VramFillLow / C3Mod_VramFill: DMAP/BBAD from Y,
; $1808 when entered at $90A7, $1809 from the callers of $90AA, at
; $8A50, $8A69 and $9F81). Program 6's HDMA tables read the bytes too:
; the $FF / $00 pair at $350A as WH0 / WH1 (window 1 shut:
; C3Mod_Prog6WindowA) and the $FF as COLDATA (white:
; C3Mod_Prog6ColourB), the $00 at $350B as CGADSUB (C3Mod_Prog6MathB)
; and the one at $350C as COLDATA (no colour: C3Mod_Prog6ColourA);
; C3Mod_Prog3Bg2Vofs reads the zero word at $350B as BG2VOFS, and
; C3Mod_Prog10ScreenB's last entry ($905D) reads the $00 there as TS,
; and the table at $A00C (not matched yet), which C3Mod_Prog10HdmaGrid
; sends to COLDATA, names $350B three times.
; Nothing reads the $FF at $350D.
C3Mod_FillBytes:
    db $FF, $00, $00, $FF

; $7E:350E — C3Mod_UnpackNibbles (46 bytes, $350E–$353B)
; Unpacks Y bytes of 4-bit pixels from $0C00 up into one byte per pixel
; at $7F:0200 (C3_BitmapSrc, through WMDATA): the low nibble first, then
; the high. It reads the bytes with PLA, the stack pointed at
; C3_NibbleStack ($0BFF) and saved in C3_StackSave meanwhile. An
; interrupt then pushes onto the bytes already read (and, near the
; start, into page $0B below $0C00, the second script page), which does
; little harm unless its handler's stack reaches further (the module
; calls it with the screen off, probably).
; Callers note: C3Mod_Prog4 ($53E1).
; Entry: M=1 (set here), X=0, DP any (saved; DP_PPU inside), DB = $00
;        (C3_StackSave is absolute); Y = the byte count (not 0).
; Exit:  M=1, X=0, DP restored, S restored; A = the last high nibble, X
;        = S as saved after the PHD (the entry S - 2), Y = 0; WMADD past
;        the pixels.
C3Mod_UnpackNibbles:
    SEP #$20
    PHD
    PEA.w !DP_PPU
    PLD
    TSX
    STX.w !C3_StackSave
    LDX.w #!C3_NibbleStack
    TXS
    LDX.w #!C3_BitmapSrc
    STX.b WMADDL-!DP_PPU                ; and WMADDM
    LDA.b #!Bank7F
    STA.b WMADDH-!DP_PPU
.byte:
    PLA
    TAX
    AND.b #!C3_NibbleMask
    STA.b WMDATA-!DP_PPU
    TXA
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b WMDATA-!DP_PPU
    DEY
    BNE .byte
    LDX.w !C3_StackSave
    TXS
    PLD
    RTS

; $7E:353C — C3Mod_NibblesToVram (35 bytes, $353C–$355E)
; Sends Y bytes of 4-bit pixels from $7F:0200 (C3_BitmapSrc, read
; through WMDATA) to VRAM's high bytes (VMDATAH: mode-7 characters, one
; pixel per word), the low nibble first, then the high: two words per
; byte from the current VRAM address (set by the caller; VMAIN must
; step after the high byte).
; Callers note: C3Mod_Prog10Fill ($8A7E).
; Entry: M=1 (set here), X=0, DP any (saved; DP_PPU inside), DB any; Y
;        = the byte count (not 0).
; Exit:  M=1, X=0, DP restored; A = the last high nibble, X = the last
;        byte with B (A's high byte, as on entry) above it (TAX is
;        16-bit), Y = 0; WMADD past the bytes.
C3Mod_NibblesToVram:
    SEP #$20
    PHD
    PEA.w !DP_PPU
    PLD
    LDX.w #!C3_BitmapSrc
    STX.b WMADDL-!DP_PPU                ; and WMADDM
    LDA.b #!Bank7F
    STA.b WMADDH-!DP_PPU
.byte:
    LDA.b WMDATA-!DP_PPU
    TAX
    AND.b #!C3_NibbleMask
    STA.b VMDATAH-!DP_PPU
    TXA
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b VMDATAH-!DP_PPU
    DEY
    BNE .byte
    PLD
    RTS

; ============================================================
; The mode-7 plane, packs, HDMA, script tasks ($355F–$3779)
; ============================================================

; $7E:355F — C3Mod_M7HdmaAB (7 bytes, $355F–$3565)
; Indirect HDMA tables (DMAP $43: M7A/M7B written twice each) for the
; mode-7 matrix that C3Mod_BuildM7Tables computes: 112 lines from
; C3_M7ABLines ($7E:F100), 112 from its second half, then the end.
; C3Mod_M7HdmaABNext ($3566) is the same one line later (+4 bytes). The
; HDMA records at $3D4A, $7B9C (C3Mod_Prog6HdmaA), $7BBB
; (C3Mod_Prog6HdmaB) and $8FEA (C3Mod_Prog10Hdma) name $355F;
; no reader of $3566 was found.
C3Mod_M7HdmaAB:
    db !C3_HdmaRepeat112 : dw !C3_M7ABLines
    db !C3_HdmaRepeat112 : dw !C3_M7ABLines+!C3_M7HalfBytes
    db 0

; $7E:3566 — C3Mod_M7HdmaABNext (7 bytes, $3566–$356C)
; See C3Mod_M7HdmaAB.
C3Mod_M7HdmaABNext:
    db !C3_HdmaRepeat112 : dw !C3_M7ABLines+4
    db !C3_HdmaRepeat112 : dw !C3_M7ABLines+!C3_M7HalfBytes+4
    db 0

; $7E:356D — C3Mod_M7HdmaCD (7 bytes, $356D–$3573)
; As C3Mod_M7HdmaAB for M7C/M7D, from C3_M7CDLines ($7E:F488); named by
; the HDMA records at $3D4F, $7BA1 (C3Mod_Prog6HdmaA), $7BC0
; (C3Mod_Prog6HdmaB) and $8FEF (C3Mod_Prog10Hdma). C3Mod_M7HdmaCDNext
; ($3574) is one line later (no reader found).
C3Mod_M7HdmaCD:
    db !C3_HdmaRepeat112 : dw !C3_M7CDLines
    db !C3_HdmaRepeat112 : dw !C3_M7CDLines+!C3_M7HalfBytes
    db 0

; $7E:3574 — C3Mod_M7HdmaCDNext (7 bytes, $3574–$357A)
; See C3Mod_M7HdmaCD.
C3Mod_M7HdmaCDNext:
    db !C3_HdmaRepeat112 : dw !C3_M7CDLines+4
    db !C3_HdmaRepeat112 : dw !C3_M7CDLines+!C3_M7HalfBytes+4
    db 0

; $7E:357B — C3Mod_BuildM7Tables (270 bytes with its variants, $357B–$3688)
; Fills C3_M7ABLines / C3_M7CDLines with a mode-7 matrix per line for a
; plane turned by C3_M7Angle and seen in perspective: for each line,
; with a divisor X that steps from line to line (up, by default), M7A =
; M7D = C3Mod_Cosine's value (-cos) scaled / X and M7B = -M7C =
; C3Mod_Sine's value (-sin) scaled / X (the signs as the angle gives
; them): a ground plane in perspective,
; probably (the race track). The hardware
; divider does the divisions (DP = DP_CPU inside): each line starts the
; next division while it stores the last quotient.
; It is self-modifying, set up before the loop:
;   - the two dividends, C3_M7Scale's low byte x |cos| and x |sin|
;     (C3Mod_Mul16's low word), go into the LDA immediates .cos_dividend
;     and .sin_dividend;
;   - the BRA at .cos_sign gets offset 0 (the quotient is negated) or 4
;     (it is not), by the cosine's sign;
;   - the two STA operands .store_b / .store_c get M7B's and M7C's
;     columns in the order that puts the negated C3Mod_Sine value in
;     M7C, by the
;     sine's sign;
;   - then the JSR at .setup calls the routine whose address the caller
;     wrote over its operand ($35FD; the assembled $0000 is
;     never called): C3Mod_Prog0Setup ($45B0),
;     C3Mod_Prog6StreamSetup ($801F), C3Mod_Prog6HalfSetup ($8042) or
;     $9B46 (not matched yet) set the first divisor X and the first
;     line's offset Y for their view; C3Mod_Prog6StreamSetup and
;     C3Mod_Prog6HalfSetup also write the end offset over .end's CPY
;     operand ($3637).
; The loop's step is self-modifying too: the INX / NOP at .step can be
; INX / INX or DEX / DEX (C3Mod_Prog6HalfSetup: $8066, $8051), NOP /
; INX ($45D1), or a BRA to
; one of the variants after the loop (a word of C3Mod_M7StepBranches):
;   - .blank_line: the next line all zeros (a blank line between each
;     two), X + 1;
;   - .double_d: this line's M7D doubled, X + 1;
;   - .stream_x: X = the next byte of a WRAM stream (WMDATA, set up by
;     C3Mod_Prog6StreamSetup at $7E:E260): the distances come from a
;     table;
;   - .copy_line: the next line a copy of this one, X + 2 (half the
;     vertical resolution).
; Quirk: the STX to WRDIVB writes 16 bits, so HTIMEL ($4207) gets X's
; high byte (0) each time.
; Callers note: JMP (a tail call) from C3Mod_ViewTask ($4306),
;   C3Mod_Prog6PlaneTask ($82F2) and $9AF0 (code not matched yet): tasks
;   that set DP = $0A00 themselves (LDA #$0A00 / TCD at $42CE, $82D1 and
;   $9ABD).
; Entry: M=0, X=0 (16-bit X and Y), DP = the script's page
;        (C3_M7Angle, C3_M7Scale; C3Math_A.. at $F0 of it), DB any
;        (set to $7E: PHK / PLB).
; Exit:  M=0, X=0, DP = DP_CPU (not restored), DB = $7E; Y = the end
;        offset; A = what the last line left: the negated quotient
;        stored by .store_c, or, after a variant at .step, 0
;        (.blank_line), the doubled M7D word (.double_d), the WMDATA
;        byte (.stream_x) or the copied M7C word (.copy_line); X = the
;        divisor the next line would take (stepped after the last
;        line, or the WMDATA byte with .stream_x); C3Math_A.. as
;        C3Mod_Mul16 leaves them.
; Calls: C3Mod_Cosine, C3Mod_Sine, C3Mod_Mul16, the setup routine (JSR
;   over a written operand).
C3Mod_BuildM7Tables:
    PHK
    PLB
    LDA.b !C3_M7Angle
    JSR C3Mod_Cosine
    BPL .cos_positive
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C3Math_A
    LDA.b !C3_M7Scale
    AND.w #!Eng_LowByteMask
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    LDA.b !C3Math_Lo
    STA.w .cos_dividend+1
    LDA.w #!Op_BRA                      ; BRA +0: the negation runs
    BRA .set_cos_sign
.cos_positive:
    STA.b !C3Math_A
    LDA.b !C3_M7Scale
    AND.w #!Eng_LowByteMask
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    LDA.b !C3Math_Lo
    STA.w .cos_dividend+1
    LDA.w #!Op_BRA|((.store_a-.cos_negate)<<8)  ; BRA +4, over the negation
.set_cos_sign:
    STA.w .cos_sign
    LDA.b !C3_M7Angle
    JSR C3Mod_Sine
    BPL .sin_positive
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C3Math_A
    LDA.b !C3_M7Scale
    AND.w #!Eng_LowByteMask
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    LDA.b !C3Math_Lo
    STA.w .sin_dividend+1
    LDA.w #!C3_M7CDLines-4
    STA.w .store_b+1                    ; the quotient to M7C
    LDA.w #!C3_M7ABLines-2
    STA.w .store_c+1                    ; its negation to M7B
    BRA .setup
.sin_positive:
    STA.b !C3Math_A
    LDA.b !C3_M7Scale
    AND.w #!Eng_LowByteMask
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    LDA.b !C3Math_Lo
    STA.w .sin_dividend+1
    LDA.w #!C3_M7ABLines-2
    STA.w .store_b+1                    ; the quotient to M7B
    LDA.w #!C3_M7CDLines-4
    STA.w .store_c+1                    ; its negation to M7C
.setup:
    JSR !C3_NoCall                      ; the caller's setup routine (operand written at run time)
    LDA.w #!DP_CPU
    TCD
    LDA.w .cos_dividend+1
    STA.b WRDIVL-!DP_CPU                ; and WRDIVH
.line:
    STX.b WRDIVB-!DP_CPU                ; cosine / X (and HTIMEL = 0: see above)
.sin_dividend:
    LDA.w #0                            ; written above
    STA.b WRDIVL-!DP_CPU
    INY
    INY
    INY
    LDA.b RDDIVL-!DP_CPU
    STX.b WRDIVB-!DP_CPU                ; sine / X
.cos_sign:
    BRA .cos_negate                     ; written above: +0 or +4
.cos_negate:
    EOR.w #!Eng_Invert16
    INC A
.store_a:
    STA.w !C3_M7ABLines-3,Y             ; M7A
    STA.w !C3_M7CDLines+2-3,Y           ; M7D
.cos_dividend:
    LDA.w #0                            ; written above
    STA.b WRDIVL-!DP_CPU
    INY
    LDA.b RDDIVL-!DP_CPU
.store_b:
    STA.w !Eng_PtrBase,Y                ; operand written above (M7B or M7C)
    EOR.w #!Eng_Invert16
    INC A
.store_c:
    STA.w !Eng_PtrBase,Y                ; operand written above (the other)
.step:
    INX                                 ; or another step (see above)
    NOP
.end:
    CPY.w #!C3_M7EndDefault             ; operand written by the setup routine
    BNE .line
    RTS
.blank_line:
    LDA.w #0
    STA.w !C3_M7ABLines,Y
    STA.w !C3_M7CDLines+2,Y
    LDA.w #0
    STA.w !C3_M7ABLines+2,Y
    LDA.w #0
    STA.w !C3_M7CDLines,Y
    INY
    INY
    INY
    INY
    INX
    BRA .end
.double_d:
    LDA.w !C3_M7CDLines+2-4,Y
    ASL A
    STA.w !C3_M7CDLines+2-4,Y
    INX
    BRA .end
.stream_x:
    LDA.l WMDATA
    AND.w #!Eng_LowByteMask
    TAX
    BRA .end
.copy_line:
    LDA.w !C3_M7ABLines-4,Y
    STA.w !C3_M7ABLines,Y
    STA.w !C3_M7CDLines+2,Y
    LDA.w !C3_M7ABLines+2-4,Y
    STA.w !C3_M7ABLines+2,Y
    LDA.w !C3_M7CDLines-4,Y
    STA.w !C3_M7CDLines,Y
    INX
    INX
    INY
    INY
    INY
    INY
    BRA .end

; $7E:3689 — C3Mod_M7StepBranches (8 bytes, $3689–$3690)
; The BRA instructions written over C3Mod_BuildM7Tables' .step (at
; $3634) to pick a variant: .blank_line, .double_d, .stream_x,
; .copy_line. $368D is copied there at $7A0C (C3Mod_Prog6StreamNmi),
; $368F at $45C5; no reader of the first two was found.
C3Mod_M7StepBranches:
    dw !Op_BRA|((C3Mod_BuildM7Tables_blank_line-C3Mod_BuildM7Tables_end)<<8)
    dw !Op_BRA|((C3Mod_BuildM7Tables_double_d-C3Mod_BuildM7Tables_end)<<8)
    dw !Op_BRA|((C3Mod_BuildM7Tables_stream_x-C3Mod_BuildM7Tables_end)<<8)
    dw !Op_BRA|((C3Mod_BuildM7Tables_copy_line-C3Mod_BuildM7Tables_end)<<8)

; $7E:3691 — C3Mod_UnpackPack (25 bytes, $3691–$36A9)
; Unpacks a pack of C3Rom_PackPtrs (bank $FE) with Decomp_ToWram: X is
; the entry's offset (3 x its number); its long pointer goes to
; Decomp_Src / Decomp_SrcBank (two overlapping word copies). Where it
; goes, Decomp_Dest / Decomp_DestBank, is the caller's.
; Callers note: C3Mod_Prog0 ($3B69, $3B75, $3BEF), C3Mod_Prog0LoadGfx
;   ($3DBF, $3DD1, $3DEA, $3DF7, $3E19, $3E29, $3E39, $3E7D, $3E93,
;   $3EA9), C3Mod_Prog4 ($53D2, $541B, $543A, $544A), C3Mod_Prog2 ($5989,
;   $599D, $59B9, $59C9, $59FA), C3Mod_Prog7 ($6259, $626B, $627F, $6295,
;   $62AA, $62B6, $62C2, $62D1), C3Mod_CreditsGfx ($6C3F), C3Mod_Prog6
;   ($78F2, $7905, $7945, $7987), C3Mod_Prog6Setup ($7ADE, $7AFD, $7B0D),
;   C3Mod_Prog10 ($8549, $857B, $8598, $85A5, $85C3, $85E4, $85F0, $869B),
;   C3Mod_Prog10Turn ($87B0), C3Mod_Prog10TurnB ($87E9), C3Mod_Prog10Fill
;   ($8A2C, $8A46, $8A5F, $8A78, $8A8A), C3Mod_Prog10Stars ($8BE4),
;   C3Mod_Prog10M7Scene ($8C48, $8C76, $8C8E), C3Mod_Prog10Grid ($8CF8,
;   $8D04, $8D10) and C3Mod_Prog13 ($8EF4, $8F04, $8F14, $8F2A).
; Entry: M any (saved; M=1 at the calls), X=0 (16-bit offset), DP any,
;        DB any (Decomp_ToWram saves them; the stores are long); X = the
;        entry's offset; Decomp_Dest/DestBank set.
; Exit:  P restored; A, X, Y as Decomp_ToWram leaves them (restored);
;        Decomp_OutLen = the bytes written.
; Calls: Decomp_ToWram (JSL).
C3Mod_UnpackPack:
    PHP
    REP #$20
    LDA.l !C3Rom_PackPtrs,X
    STA.l !Decomp_Src
    LDA.l !C3Rom_PackPtrs+1,X
    STA.l !Decomp_Src+1                 ; and Decomp_SrcBank
    JSL !Decomp_ToWram
    PLP
    RTS

; $7E:36AA — C3Mod_CopyRawPack (34 bytes, $36AA–$36CB)
; Copies a block of bank $FE that C3Rom_PackPtrs points to, as it is
; (one of the raw entries): C3_CopyFEto7F when Decomp_DestBank bit 0 is
; set, else C3_CopyFEto7E, C3_RowCount bytes ($F0 of the caller's
; page) from the entry's address to Y. Only the pointer's low word is
; read: the bank is $FE.
; Callers note: C3Mod_Prog4 ($540A, $5488, $5493), C3Mod_Prog6 ($7963),
;   C3Mod_Prog10 ($8663, $866C, $8675, $867E, $868C), C3Mod_Prog10TurnB
;   ($8841, $884A), C3Mod_Prog10Fill ($8AC1), C3Mod_Prog10Stars ($8BFC),
;   C3Mod_Prog10Palette ($8E0B, $8E14) and C3Mod_Prog13 ($8ED6, $8F42).
; Entry: M any (saved; M=1 at the calls but $7963's, M=0), X=0 (16-bit
;        X and Y), DP = the page of the count, DB = $00 or $7E (a bank
;        that maps low WRAM: LDA.w Decomp_DestBank is absolute; saved,
;        and the table read is long); X =
;        the entry's offset (3 x its number), Y = the destination,
;        C3_RowCount = the byte count (not 0), Decomp_DestBank bit 0 =
;        the WRAM bank.
; Exit:  P and DB restored; A = $FFFF; X, Y past the copied bytes.
; Calls: C3_CopyFEto7E or C3_CopyFEto7F (JSL).
C3Mod_CopyRawPack:
    PHP
    PHB
    REP #$20
    LDA.l !C3Rom_PackPtrs,X
    TAX
    LDA.w !Decomp_DestBank
    LSR A
    BCC .to_7e
    LDA.b !C3_RowCount
    DEC A
    JSL !C3_CopyFEto7F
    BRA .done
.to_7e:
    LDA.b !C3_RowCount
    DEC A
    JSL !C3_CopyFEto7E
.done:
    PLB
    PLP
    RTS

; $7E:36CC — C3Mod_SetupHdma (61 bytes, $36CC–$3708)
; Sets up HDMA channels from a list of 5-byte records at Y (in bank $7E),
; channel 0 first: DMAPn and BBADn, the table's address (A1TnL/H) and
; bank (A1Bn, and DASBn, the indirect bank), until a record whose first
; byte is $FF. The 16-bit stores also write DASnL with the next record's
; first byte and A2AnL with the byte after the bank, which HDMA sets
; itself. The bank is set with PEA $007E / PLB, which leaves a $00 on the
; stack that the final PLB takes back: DB is $00 at the exit, whatever
; it was.
; Callers note: C3Mod_Prog0 ($3C49), C3Mod_Prog3 ($67AD), C3Mod_Prog5
;   ($70E0), C3Mod_Prog6StreamNmi ($7A2A), C3Mod_Prog6HalfNmi ($7A5D),
;   C3Mod_Prog10 ($8714), C3Mod_Prog10Fill ($8ACD), C3Mod_Prog10Strip
;   ($8B12), C3Mod_Prog10GridNmi ($8DAF), C3Mod_Prog10Mode4Nmi ($8E7D) and
;   C3Mod_Prog13 ($8F7D).
; Entry: M=1 (M=0 set here), X=0, DP any (saved), DB any; Y = the list.
; Exit:  M=1, X=0, DP restored, DB = $00; A = $00FF (the end record's
;        first byte, ANDed with $FF before the CMP); X = 16 x the
;        channels set, Y = the end record.
C3Mod_SetupHdma:
    PHD
    PEA.w !DP_DMA
    PLD
    PEA.w !Bank7E                       ; PLB takes the $7E; the $00 stays (see above)
    PLB
    REP #$20
    LDX.w #0
.record:
    LDA.w !Eng_PtrBase,Y
    AND.w #!Eng_LowByteMask
    CMP.w #!C3_HdmaListEnd
    BEQ .done
    LDA.w !Eng_PtrBase,Y
    STA.b DMAP0-!DP_DMA,X               ; and BBADn
    LDA.w !Eng_PtrBase+2,Y
    STA.b A1T0L-!DP_DMA,X               ; and A1TnH
    LDA.w !Eng_PtrBase+4,Y
    STA.b A1B0-!DP_DMA,X                ; and DASnL (the next record's first byte)
    STA.b DAS0B-!DP_DMA,X               ; and A2AnL
    TXA
    CLC
    ADC.w #!C3_DmaChannelBytes
    TAX
    TYA
    CLC
    ADC.w #!C3_HdmaRecordBytes
    TAY
    BRA .record
.done:
    SEP #$20
    PLB                                 ; the $00 from the PEA
    PLD
    RTS

; $7E:3709 — C3Mod_HdmaAlternate (64 bytes, $3709–$3748)
; Writes an HDMA table through WMDATA (DP = DP_PPU: WMDATA as $80): 112
; pairs of one-line entries, the first with the bytes at C3_ScratchF0
; and $00F1, the second with $00F2 and $00F3 (two values on alternate
; lines), then the end byte. The four bytes are copied into the LDA
; immediates of its loop first (long stores into its own code). No
; caller was found (no call, stored address or table entry).
; Entry: M=1, X=0 (the 16-bit count load), DP = DP_PPU, DB = $00 or $7E
;        (the $00F0 reads are absolute); WMADD = where the table goes.
; Exit:  P restored (X high byte cleared by the SEP #$30: X = 0 after
;        the loop anyway); A = the byte copied from $00F3 (the last
;        LDA immediate; STZ writes the end), X = 0, Y = 1; WMADD past
;        the table.
C3Mod_HdmaAlternate:
    LDA.w !C3_ScratchF0
    STA.l .first_a+1
    LDA.w !C3_ScratchF0+1
    STA.l .first_b+1
    LDA.w !C3_ScratchF2
    STA.l .second_a+1
    LDA.w !C3_ScratchF2+1
    STA.l .second_b+1
    LDX.w #!C3_HdmaPairs
    LDY.w #!C3_HdmaOneLine
    PHP
    SEP #$30
.pair:
    STY.b WMDATA-!DP_PPU                ; one line
.first_a:
    LDA.b #0                            ; written above
    STA.b WMDATA-!DP_PPU
.first_b:
    LDA.b #0
    STA.b WMDATA-!DP_PPU
    STY.b WMDATA-!DP_PPU
.second_a:
    LDA.b #0
    STA.b WMDATA-!DP_PPU
.second_b:
    LDA.b #0
    STA.b WMDATA-!DP_PPU
    DEX
    BNE .pair
    STZ.b WMDATA-!DP_PPU                ; the end
    PLP
    RTS

; $7E:3749 — C3Mod_ScriptTaskA (11 bytes, $3749–$3753)
; A task, and a subroutine: runs the script of page $0A00 (DP = $0A00,
; DB = $7E, C3_RunScript) until it yields.
; Callers note: JSR from C3Mod_Prog0 ($3CD8), C3Mod_Prog4 ($54B4),
;   C3Mod_Prog2 ($5A0A), C3Mod_Prog7 ($62F0), C3Mod_Prog3 ($6792),
;   C3Mod_Prog5 ($70CE), C3Mod_Prog6 ($79AA), C3Mod_Prog10 ($86E6) and
;   C3Mod_Prog13 ($8F94); a task: C3Mod_Prog6TableA and C3Mod_Prog6TableB
;   (copied to C3_TaskList), and the scripts' opcode $FA at $3F1A
;   (C3Mod_Prog0ScriptA), $4130 (C3Mod_Prog0Start), $5540
;   (C3Mod_Prog4ScriptA), $5B05 (C3Mod_Prog2Script), $6393
;   (C3Mod_Prog7Start), $6984 (C3Mod_Prog3Start), $7157
;   (C3Mod_Prog5Script), $931C, $932E and $93E3.
; Entry: M=0, X=0 (C3_RunScript's), DP any, DB any (both set here and
;        not restored: a task's are restored by C3Mod_RunTasks).
; Exit:  M=0, X=0, DP = $0A00, DB = $7E; A, X, Y as C3_RunScript leaves
;        them.
; Calls: C3_RunScript (JSL).
C3Mod_ScriptTaskA:
    LDA.w #!C3_ScriptPageA
    TCD
    PHK
    PLB
    JSL !C3_RunScript
    RTS

; $7E:3754 — C3Mod_ScriptTaskB (11 bytes, $3754–$375E)
; As C3Mod_ScriptTaskA, for the script of page $0B00.
; Callers note: JSR from C3Mod_Prog5 ($70D1); a task: C3Mod_Prog6TableA
;   and C3Mod_Prog6TableB, and the scripts' opcode $FA at $3F1D
;   (C3Mod_Prog0ScriptA), $4133 (C3Mod_Prog0Start), $5543
;   (C3Mod_Prog4ScriptA), $6987 (C3Mod_Prog3Start), $715A
;   (C3Mod_Prog5Script) and $9331.
; Entry: M=0, X=0, DP any, DB any (set here, not restored).
; Exit:  M=0, X=0, DP = $0B00, DB = $7E; A, X, Y as C3_RunScript leaves
;        them.
; Calls: C3_RunScript (JSL).
C3Mod_ScriptTaskB:
    LDA.w #!C3_ScriptPageB
    TCD
    PHK
    PLB
    JSL !C3_RunScript
    RTS

; $7E:375F — C3Mod_PlaySong (27 bytes, $375F–$3779)
; Plays the song in A: C3_SongReq and C3_SongCur = A (so C3_SongCheck
; sends nothing more), and Audio_CmdPlayMusic with it and arguments
; C3_SongArgs through Audio_DriverCommand.
; Callers note: C3Mod_Prog0 ($3B5A), C3Mod_Prog2 ($5AA7) and
;   C3Mod_Prog13 ($8FE6).
; Entry: M any (8-bit set here), X=0 (the 16-bit argument store), DP
;        any, DB = $00 (the variables and the Audio_Cmd* block are
;        absolute); A = the song.
; Exit:  M=1, X=0; A, X as Audio_DriverCommand leaves them (X =
;        C3_SongArgs).
; Calls: Audio_DriverCommand (JSL).
C3Mod_PlaySong:
    SEP #$20
    STA.w !C3_SongReq
    STA.w !C3_SongCur
    STA.w !Audio_CmdArg0
    LDA.b #!Audio_CmdPlayMusic
    STA.w !Audio_CmdId
    LDX.w #!C3_SongArgs
    STX.w !Audio_CmdArg1                ; and Arg2
    JSL !Audio_DriverCommand
    RTS


; ============================================================
; The sound port, bitmap row copies, the script's call ($377A–$37F9)
; ============================================================

; $7E:377A — C3Mod_AudioCommand (4 bytes, $377A–$377D)
; C3Mod_AudioSend for callers in other banks (JSL, RTL).
; Callers note: the kernel's C3_ReadPad (JSL !C3Mod_AudioCommand,
;   $C3:0AE1 and $C3:0AF3), sending the pause and resume sounds.
; Entry: as C3Mod_AudioSend: M any, X=0, DP any, DB=$00.
; Exit:  as C3Mod_AudioSend.
; Calls: C3Mod_AudioSend.
%C3ModOrg($7E377A)
C3Mod_AudioCommand:
    JSR C3Mod_AudioSend
    RTL

; $7E:377E — C3Mod_AudioSend (40 bytes, $377E–$37A5)
; Sends the command block Audio_CmdId, Arg0, Arg1, Arg2 to the sound
; driver: Arg2..Arg0 to APUIO3..APUIO1, then the command to APUIO0
; last, and waits for the driver to echo the command in APUIO0. After
; C3_ApuTries polls without the echo it writes the four ports again,
; for ever: there is no give-up. The block is not cleared afterwards
; (C3Mod_SoundReset relies on that, sending runs of commands that
; change one byte each).
; Callers note: C3Mod_AudioCommand ($377A), C3Mod_SoundReset ($3187,
;   $318F, $3197, $319F, $31AD JMP), C3Mod_ExitTask ($426D),
;   C3Mod_RaceStepTask ($4BC8), C3Mod_ResetWaitTask ($63E5) and
;   C3Mod_Prog13 ($8EB2).
; Entry: M any (SEP #$20 here), X=0 (the 16-bit poll count), DP any,
;        DB=$00 (the ports and the block are absolute).
; Exit:  M=1, X=0; A = Audio_CmdId; X = polls left (nonzero), Y, DP
;        and DB unchanged.
C3Mod_AudioSend:
    SEP #$20
.send:
    LDX.w #!C3_ApuTries
    LDA.w !Audio_CmdArg2
    STA.w APUIO3
    LDA.w !Audio_CmdArg1
    STA.w APUIO2
    LDA.w !Audio_CmdArg0
    STA.w APUIO1
    LDA.w !Audio_CmdId
    STA.w APUIO0
.poll:
    CMP.w APUIO0
    BEQ .done
    DEX
    BNE .poll
    BRA .send
.done:
    RTS

; $7E:37A6 — C3Mod_DoubleRows (36 bytes, $37A6–$37C9)
; Makes a 64 x 64-byte map half of a 128-wide mode-7 map: each 64-byte
; row of $7F:0200-$11FF (C3_BitmapSrc) is copied twice, one copy after
; the other, to $7F:2200-$41FF (C3_BitmapDest; two MVNs per row, the
; source pointer saved for the second), so each 128-byte map row is the
; source row twice side by side (repeated across, not stretched in
; height): 64 map rows. The row count lives in the caller's direct page
; (C3_RowCount). All four callers unpack a pack to $7F:0200 just before
; (C3Mod_UnpackPack) and send the result to the mode-7 map's low VRAM
; bytes with VMAIN = 0: C3Mod_SendM7Map after $3DED, $3DFA, $87B3
; ($3DF1, $3DFE, $87C4 / $87C7), and a C3Mod_DmaFromArgs DMA of $2000
; bytes from $7F:2200 to VMDATAL after $7908.
; Callers note: JSL from C3Mod_Prog0LoadGfx ($3DED, $3DFA), C3Mod_Prog6
;   ($7908) and C3Mod_Prog10Turn ($87B3).
; Entry: M any (REP #$20 here), X=0 (MVN's 16-bit X and Y), DP any
;        (its C3_RowCount word is used), DB any (saved).
; Exit:  M=1, X=0, DP and DB as on entry; A = $FFFF; X = $1200, Y =
;        $4200 (past the copies); C3_RowCount = 0.
C3Mod_DoubleRows:
    PHB
    REP #$20
    LDA.w #!C3_BitmapRows
    STA.b !C3_RowCount
    LDY.w #!C3_BitmapDest
    LDX.w #!C3_BitmapSrc
.row:
    PHX
    LDA.w #!C3_RowBytes-1
    MVN $7F,$7F                         ; lint-ok: MVN operands are bank bytes (WRAM bank $7F)
    PLX
    LDA.w #!C3_RowBytes-1
    MVN $7F,$7F                         ; lint-ok: MVN operands are bank bytes
    DEC.b !C3_RowCount
    BNE .row
    SEP #$20
    PLB
    RTL

; $7E:37CA — C3Mod_SpaceRows (41 bytes, $37CA–$37F2)
; Like C3Mod_DoubleRows, but each copied row is followed by a row of
; zeros: after the copy it stores a zero word at the next output row
; (STZ with DB = $7F from the MVN) and spreads it with an overlapping
; 63-byte MVN (each byte copied onto the next), so the 128 output rows
; at $7F:2200-$41FF alternate picture and blank.
; Callers note: JSL from C3Mod_Prog4 ($544D), C3Mod_Prog10 ($859B,
;   $85A8) and C3Mod_Prog10Fill ($8A8D).
; Entry: M any (REP #$20 here), X=0, DP any (its C3_RowCount word is
;        used), DB any (saved).
; Exit:  M=1, X=0, DP and DB as on entry; A = $FFFF; X = $1200, Y =
;        $4200; C3_RowCount = 0.
C3Mod_SpaceRows:
    PHB
    REP #$20
    LDA.w #!C3_BitmapRows
    STA.b !C3_RowCount
    LDY.w #!C3_BitmapDest
    LDX.w #!C3_BitmapSrc
.row:
    LDA.w #!C3_RowBytes-1
    MVN $7F,$7F                         ; lint-ok: MVN operands are bank bytes (WRAM bank $7F)
    PHX
    TYX
    INY
    STZ.w !Eng_PtrBase,X                ; the row X points at (DB = $7F after the MVN)
    LDA.w #!C3_RowBytes-2
    MVN $7F,$7F                         ; lint-ok: MVN operands are bank bytes
    PLX
    DEC.b !C3_RowCount
    BNE .row
    SEP #$20
    PLB
    RTL

; $7E:37F3 — C3Mod_CallW (7 bytes, $37F3–$37F9)
; Calls the module code at the address in C3_ScratchF0 and returns
; with RTL: the kernel's way into module code. JSR (abs,X) with X = 0
; reads the pointer in the program bank, at $7E:00F0, which is the same
; WRAM as $00:00F0.
; Callers note: the kernel's C3_RunScript (JSL !C3Mod_CallW at
;   $C3:0C58, script opcode 0, which puts its operand in C3_ScratchF0).
; Entry: X=0 (LDX.w #0 is three bytes, A2 00 00: with X=1 the last
;        $00 would run as BRK), M as the called code wants, DP any, DB
;        any (C3_RunScript calls it with M=0, X=0, DB=$7E); the address
;        in C3_ScratchF0.
; Exit:  what the called code leaves, X included.
C3Mod_CallW:
    LDX.w #0
    JSR (!C3_ScratchF0,X)
    RTL

%C3ModOrg($7E37FA)

; $7E:37FA — C3Mod_PalAnimTask (17 bytes, $37FA–$380A)
; A task: runs the field's palette animations once a frame
; (FdVec_FFF7: PalAnim_TickAll), keeping the multiplier operands around
; the call: WRMPYA/WRMPYB are read into C3_ScratchF0 and written back
; after. Quirk: those registers are write-only, so the read gives open
; bus and the "restore" writes whatever it read (harmless unless a
; product was pending, probably).
; Callers note: JSR from C3Mod_Prog6PalIn ($8319) and C3Mod_Prog6PalOut
;   ($8355); a task added by the scripts' opcode $FA at $5B0B
;   (C3Mod_Prog2Script), $6396 (C3Mod_Prog7Start), $6993
;   (C3Mod_Prog3Start), $7D04 and $7EB3 (C3Mod_Prog6ScriptB; the first
;   removed again by $F9 at $7D0C), $9334 and $93E9.
; Entry: a task: M=0 (8-bit set here), X=0, DP=0 (C3_ScratchF0 is
;        direct page), DB = $00 (the registers are absolute). The JSRs
;        from C3Mod_Prog6PalIn / PalOut come with DP = $0B00 and DB =
;        $7E: the save goes to $0BF0, and the two WRMPYA accesses are
;        WRAM at $7E:4202 (harmless; PalAnim_TickAll sets its DB from
;        DP's low byte, TDC / PHA at M=1 / PLB: $00 there too).
; Exit:  M=1, X=0; A, Y as PalAnim_TickAll leaves them; X =
;        C3_ScratchF0.
; Calls: FdVec_FFF7 (JSL).
C3Mod_PalAnimTask:
    SEP #$20
    LDX.w WRMPYA                        ; and WRMPYB (write-only: open bus)
    STX.b !C3_ScratchF0
    JSL !FdVec_FFF7
    LDX.b !C3_ScratchF0
    STX.w WRMPYA                        ; and WRMPYB
    RTS

; $7E:380B — C3Mod_OamUploadTask (56 bytes, $380B–$3842)
; An NMI task: closes the OAM high-table byte being filled
; (C3Mod_FinishOamHigh), sends all of OAM (Oam_LowTable and
; Oam_HighTable, C3_OamBytes) by DMA channel 7 from OAM address 0, then
; sets OAMADDH's priority-rotation bit with OAMADDL = C3_OamRotate (the
; sprite given the first priority, probably), and starts the next
; frame's sprites over: C3_OamPos = 0, C3_OamHiPtr = Oam_HighTable.
; Callers note: an NMI task added by the scripts' opcode $F8 at $3F2F
;   (C3Mod_Prog0ScriptA), $4145 (C3Mod_Prog0Start), $554F
;   (C3Mod_Prog4ScriptA), $5B20 (C3Mod_Prog2Script), $639C
;   (C3Mod_Prog7Start), $699C (C3Mod_Prog3Start), $7181
;   (C3Mod_Prog5Script), $7C73 (C3Mod_Prog6Script), $9325 and $93EC.
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X=0, DP=0 (C3_OamPos..
;        are direct page), DB = $00.
; Exit:  M=1, X=0; A = C3_OamRotate, X = Oam_HighTable.
; Calls: C3Mod_FinishOamHigh.
C3Mod_OamUploadTask:
    JSR C3Mod_FinishOamHigh
    LDX.w #0
    STX.w OAMADDL                       ; and OAMADDH
    STZ.w A1B7
    LDX.w #!BBAD_OAMDATA<<8             ; DMAP7 = 0 (one register), BBAD7 = OAMDATA
    STX.w DMAP7
    LDX.w #!Oam_LowTable
    STX.w A1T7L
    LDX.w #!C3_OamBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDA.b #!C3_OamPriorityRotate
    STA.w OAMADDH
    LDA.b !C3_OamRotate
    STA.w OAMADDL
    LDX.w #0
    STX.b !C3_OamPos
    LDX.w #!Oam_HighTable
    STX.b !C3_OamHiPtr
    RTS

; ============================================================
; Sprites hidden, the palette sent ($3843–$38AE)
; ============================================================

; $7E:3843 — C3Mod_HideSprites (45 bytes, $3843–$386F)
; Fills Oam_LowTable ($0700-$08FF) with C3_OamHideY by DMA channel 7
; from MPYL (M7A = 1, M7B = C3_OamHideY, so the product's low byte is
; C3_OamHideY): every byte $E0, so every sprite at X = Y = $E0, below
; the screen (the tile and attribute bytes $E0 too; the high table is
; not touched). M7B is set back to 0 after; M7A is left at 1.
; Callers note: C3Mod_Init ($30F6); an NMI task (C3Mod_RunNmiTasks, once
;   a frame in vblank) added by script opcode $F8 at $3F32
;   (C3Mod_Prog0ScriptA), $4148 (C3Mod_Prog0Start), $5B23
;   (C3Mod_Prog2Script), $639F (C3Mod_Prog7Start), $7184
;   (C3Mod_Prog5Script), $7C76 (C3Mod_Prog6Script), $9328 and $93EF (the
;   others: scripts not matched yet).
; Entry: M=1, X=0, DP any, DB=$00 (absolute register stores).
; Exit:  M=1, X=0, DP and DB unchanged; A = MDMAEN_Ch7, X =
;        C3_OamLowBytes; Y unchanged; DMA channel 7's registers set.
%C3ModOrg($7E3843)
C3Mod_HideSprites:
    LDA.b #1
    STA.w M7A
    STZ.w M7A                           ; M7A = $0001
    LDA.b #!C3_OamHideY
    STA.w M7B
    STZ.w A1B7
    LDA.b #!BBAD_MPYL
    STA.w BBAD7
    LDX.w #!Oam_LowTable
    STX.w A1T7L
    LDX.w #!C3_OamLowBytes
    STX.w DAS7L
    LDA.b #!DMAP_BtoA
    STA.w DMAP7
    STA.w MDMAEN                        ; DMAP_BtoA = MDMAEN_Ch7, the same bit 7
    STZ.w M7B
    RTS

%C3ModOrg($7E3870)

; $7E:3870 — C3Mod_FinishOamHigh (27 bytes, $3870–$388A)
; Closes the Oam_HighTable byte at C3_OamHiPtr when fewer than 4
; sprites have been put in it: (C3_OamPos / 4) AND 3 sprites are in, and
; for each slot left it shifts in a %01 pair from the top (SEC / ROR /
; LSR: X bit 8 set, small size), so the unused sprites of the byte sit
; off screen. B is cleared first (TDC / XBA, with DP = 0) for the 16-bit
; TAX.
; Callers note: C3Mod_OamUploadTask ($380B) and $99A3 (code not matched
;   yet).
; Entry: M any (8-bit set here, not restored), X=0 (16-bit compare), DP=0
;        (C3_OamPos, C3_OamHiPtr), DB any (the pointer is direct-page
;        indirect, bank DB: $00 at the calls).
; Exit:  M=1, X=0; A = the byte; X = 4; Y unchanged.
C3Mod_FinishOamHigh:
    TDC
    XBA
    SEP #$20
    LDA.b !C3_OamPos
    LSR A
    LSR A
    AND.b #!C3_OamSlotMask
    TAX
    LDA.b (!C3_OamHiPtr)
.fill:
    CPX.w #!C3_OamSlotsPerByte
    BEQ .done
    INX
    SEC
    ROR A
    LSR A                               ; a %01 pair in at the top
    BRA .fill
.done:
    STA.b (!C3_OamHiPtr)
    RTS

; $7E:388B — C3Mod_UploadPalette (36 bytes, $388B–$38AE)
; Sends the 256 colours of C3_PaletteBuf ($7E:2200) to CGRAM from
; colour 0, by DMA channel 7 (one register, CGDATA).
; Callers note: C3Mod_Start ($300D), C3Mod_Prog10Fill ($8AC7) and
;   C3Mod_Prog10M7Scene ($8C97); an NMI task (C3Mod_RunNmiTasks, once a
;   frame in vblank) added by script opcode $F8 at $5B1D
;   (C3Mod_Prog2Script), $63A2 (C3Mod_Prog7Start), $6999
;   (C3Mod_Prog3Start), $717E (C3Mod_Prog5Script), $7CF9 and $7EB6
;   (C3Mod_Prog6ScriptB), $932B and $93F5, and removed by $F7 at $7D0F
;   (C3Mod_Prog6ScriptB; the others: scripts not matched yet).
; Entry: M=1, X=0, DP any, DB=$00 (absolute register stores).
; Exit:  M=1, X=0, DP and DB unchanged; A = MDMAEN_Ch7, X =
;        C3_PaletteBytes; Y unchanged; DMA channel 7's registers set.
%C3ModOrg($7E388B)
C3Mod_UploadPalette:
    LDA.b #0
    STA.w DMAP7
    STA.w CGADD
    LDA.b #bank(!C3_PaletteBuf)
    STA.w A1B7
    LDA.b #!BBAD_CGDATA
    STA.w BBAD7
    LDX.w #!C3_PaletteBuf&$FFFF
    STX.w A1T7L
    LDX.w #!C3_PaletteBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    RTS

%C3ModOrg($7E38AF)

; $7E:38AF — C3Mod_CommitPalette (20 bytes, $38AF–$38C2)
; Copies the 512-byte palette at $7E:2000 (C3_PaletteWork) over
; C3_PaletteBuf ($7E:2200), the copy C3Mod_UploadPalette sends.
; Callers note: C3Mod_Prog0LoadGfx ($3DC2), C3Mod_Prog2 ($59FD),
;   C3Mod_Prog7 ($62EB), C3Mod_Prog6 ($796F), C3Mod_Prog10 ($869E),
;   C3Mod_Prog10Turn ($87A1), C3Mod_Prog10Fill ($8AC4), C3Mod_Prog10Stars
;   ($8BFF), C3Mod_Prog10M7Scene ($8C94), C3Mod_Prog10Palette ($8E17) and
;   C3Mod_Prog13 ($8F48).
; Entry: M any (16-bit set here), X=0 (MVN's X and Y), DP any, DB any
;        (saved).
; Exit:  M=1, X=0, DB restored; A = 0 (the MVN's $FFFF + 1); X =
;        $2200, Y = $2400.
C3Mod_CommitPalette:
    REP #$20
    PHB
    LDX.w #!C3_PaletteWork&$FFFF
    LDY.w #!C3_PaletteBuf&$FFFF
    LDA.w #!C3_PaletteBytes-1
    MVN $7E,$7E                         ; lint-ok: MVN operands are bank bytes (WRAM bank $7E)
    INC A
    PLB
    SEP #$20
    RTS

; $7E:38C3 — C3Mod_DmaFromArgs (36 bytes, $38C3–$38E6)
; Runs a DMA on channel 7 described by C3_DmaMode.. at $00F0-$00F9:
; DMAP7 and BBAD7 from the bytes at $00F0 and $00F2, the A-bus address
; and bank from $00F4 / $00F6, the count from $00F8. RTL: called with
; JSL from the module.
; Callers note: JSL from C3Mod_Prog6 ($792F, $7933).
; Entry: M=1, X=0 (16-bit address and count), DP any, DB = $00 (the
;        arguments are read absolute, the registers written absolute).
; Exit:  M=1, X=0; A = MDMAEN_Ch7, X = the count; Y unchanged.
C3Mod_DmaFromArgs:
    LDA.w !C3_DmaMode
    STA.w DMAP7
    LDA.w !C3_DmaBbad
    STA.w BBAD7
    LDX.w !C3_DmaAddr
    STX.w A1T7L
    LDA.w !C3_DmaBank
    STA.w A1B7
    LDX.w !C3_DmaCount
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    RTL

; $7E:38E7 — C3Mod_DmaUnpacked (36 bytes, $38E7–$390A)
; As C3Mod_DmaFromArgs, but the A-bus side is what Decomp_ToWram just
; wrote: Decomp_Dest / Decomp_DestBank, Decomp_OutLen bytes (the mode
; and B-bus register from $00F0 / $00F2).
; Callers note: JSL from C3Mod_Prog0LoadGfx ($3DDD, $3E1C, $3E2C, $3E3C,
;   $3E86, $3E9C, $3EB2), C3Mod_Prog4 ($53F7, $543D), C3Mod_Prog2 ($5996,
;   $59A6, $59C2), C3Mod_MapToM7 ($5AB2), C3Mod_Prog7 ($6278, $6288,
;   $6298), C3Mod_CreditsGfx ($6C48), C3Mod_Prog6 ($78FE),
;   C3Mod_Prog6Setup ($7AF6, $7B06), C3Mod_Prog10 ($8586, $85D0),
;   C3Mod_Prog10Fill ($8A39, $8A49, $8A62), C3Mod_Prog10Stars ($8BE7),
;   C3Mod_Prog10M7Scene ($8C51) and C3Mod_Prog13 ($8EF7, $8F07, $8F1D,
;   $8F2D); most right after C3Mod_UnpackPack.
; Entry: M=1, X=0, DP any, DB = $00.
; Exit:  M=1, X=0; A = MDMAEN_Ch7, X = Decomp_OutLen; Y unchanged.
C3Mod_DmaUnpacked:
    LDA.w !C3_DmaMode
    STA.w DMAP7
    LDA.w !C3_DmaBbad
    STA.w BBAD7
    LDX.w !Decomp_Dest
    STX.w A1T7L
    LDA.w !Decomp_DestBank
    STA.w A1B7
    LDX.w !Decomp_OutLen
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    RTL

; $7E:390B — C3Mod_SetM7Scroll (41 bytes, $390B–$3933)
; Writes BG1HOFS / BG1VOFS (the mode-7 scroll) and M7X / M7Y (the
; centre) from the direct page's bytes $02-$09 (script variables 1-4,
; C3Script_Vars + 2.. + 9, if DP is a script page, as the names
; assume), each register twice (low, then high byte). No caller was
; found (no call, stored address or script call), so the DP is an
; inference.
; Entry: M=1, X any, DP = the page of the values (a script page,
;        probably), DB = $00 (absolute register stores).
; Exit:  M=1; A = variable 4's high byte; X, Y unchanged.
C3Mod_SetM7Scroll:
    LDA.b !C3Script_Vars+2
    STA.w BG1HOFS
    LDA.b !C3Script_Vars+3
    STA.w BG1HOFS
    LDA.b !C3Script_Vars+4
    STA.w BG1VOFS
    LDA.b !C3Script_Vars+5
    STA.w BG1VOFS
    LDA.b !C3Script_Vars+6
    STA.w M7X
    LDA.b !C3Script_Vars+7
    STA.w M7X
    LDA.b !C3Script_Vars+8
    STA.w M7Y
    LDA.b !C3Script_Vars+9
    STA.w M7Y
    RTS

; $7E:3934 — C3Mod_TaskRemove (21 bytes, $3934–$3948)
; The module's copy of C3_TaskListRemove: clears the first word of
; C3_TaskList equal to X, searching without a bound (a value not in the
; list is searched for past its end).
; Callers note: C3Mod_RaceFinish ($482E) and C3Mod_RaceStepTask
;   ($4879).
; Entry: M any (P saved; 16-bit set here), X=0, DP any, DB = $00 or $7E
;        (the list is absolute); X = the task's address.
; Exit:  P restored; A = the address, X = its offset in the list; Y
;        unchanged.
C3Mod_TaskRemove:
    PHP
    REP #$20
    TXA
    LDX.w #0
.find:
    CMP.w !C3_TaskList,X
    BEQ .found
    INX
    INX
    BRA .find
.found:
    STZ.w !C3_TaskList,X
    PLP
    RTS

; $7E:3949 — C3Mod_NmiTaskRemove (21 bytes, $3949–$395D)
; As C3Mod_TaskRemove, for C3_NmiTaskList.
; Callers note: $9EF6 (code not matched yet).
; Entry: M any (P saved), X=0, DP any, DB = $00 or $7E; X = the task's
;        address.
; Exit:  P restored; A = the address, X = its offset; Y unchanged.
C3Mod_NmiTaskRemove:
    PHP
    REP #$20
    TXA
    LDX.w #0
.find:
    CMP.w !C3_NmiTaskList,X
    BEQ .found
    INX
    INX
    BRA .find
.found:
    STZ.w !C3_NmiTaskList,X
    PLP
    RTS

; $7E:395E — C3Mod_TaskAdd (22 bytes, $395E–$3973)
; The module's copy of C3_TaskListAdd: X into the first free (zero)
; word of C3_TaskList, searched without a bound.
; Callers note: C3Mod_RaceTask ($4687), C3Mod_RaceFinish ($4834),
;   C3Mod_RaceStepTask ($489D), C3Mod_SkipTask ($5BAC), C3Mod_FirstPicTask
;   ($5D54), C3Mod_ResetWaitTask ($63EB) and C3Mod_Prog1 ($6BDB, $6BE1).
; Entry: M any (P saved; 16-bit set here), X=0 (pushed and pulled as a
;        word), DP any, DB = $00 or $7E; X = the task's address.
; Exit:  P restored; A = the address, X = its offset; Y unchanged.
C3Mod_TaskAdd:
    PHP
    PHX
    LDX.w #0
    REP #$20
.find:
    LDA.w !C3_TaskList,X
    BEQ .found
    INX
    INX
    BRA .find
.found:
    PLA
    STA.w !C3_TaskList,X
    PLP
    RTS

; $7E:3974 — C3Mod_NmiTaskAdd (22 bytes, $3974–$3989)
; As C3Mod_TaskAdd, for C3_NmiTaskList.
; Callers note: C3Mod_RaceTask ($46A1), C3Mod_RaceStepTask ($4897,
;   $48BD, $48D7), C3Mod_Prog10 ($8652) and $9C69 (code not matched yet).
; Entry: M any (P saved), X=0, DP any, DB = $00 or $7E; X = the task's
;        address.
; Exit:  P restored; A = the address, X = its offset; Y unchanged.
C3Mod_NmiTaskAdd:
    PHP
    PHX
    LDX.w #0
    REP #$20
.find:
    LDA.w !C3_NmiTaskList,X
    BEQ .found
    INX
    INX
    BRA .find
.found:
    PLA
    STA.w !C3_NmiTaskList,X
    PLP
    RTS

; ============================================================
; The task lists ($398A–$39F5)
; ============================================================

; $7E:398A — C3Mod_RunTasks (29 bytes, $398A–$39A6)
; Runs the frame's tasks: JSRs each nonzero word of C3_TaskRun (the
; copy C3_ModuleFrame makes of C3_TaskList) in turn, saving DB, X, P
; and DP around each, with M=0 and DP and DB as the frame left them.
; A task can leave by JMP to C3Mod_TaskEnd (it frees its own entry of
; C3_TaskList) or to C3Mod_TaskReplace (it puts the address in X
; there) instead of returning; both come back into this loop at
; C3Mod_TaskNext. A task
; that changes C3_TaskList changes what runs next frame, not this
; one (C3_TaskRun is the copy).
; Sub-entry: C3Mod_TaskNext ($399F), the next entry.
; Callers note: the kernel's C3_ModuleFrame (JSL !C3Mod_RunTasks,
;   $C3:0938). C3Mod_TaskNext: C3Mod_TaskEnd, C3Mod_TaskReplace and,
;   by a slip, C3Mod_NmiTaskReplace (BRA).
; Entry: M any (REP #$20 here), X=0 (16-bit index), DP and DB as the
;        tasks expect (C3_ModuleFrame: DP=0, DB=$00).
; Exit:  M=0, X=0; A = 0 (the last entry was free) or what the last
;        task left; X = C3_TaskListBytes; Y as the tasks leave it; DP
;        and DB as on entry (restored after each task).
C3Mod_RunTasks:
    REP #$20
    LDX.w #0
.task:
    LDA.w !C3_TaskRun,X
    BEQ C3Mod_TaskNext
    PHB
    PHX
    PHP
    PHD
    JSR (!C3_TaskRun,X)
    PLD
    PLP
    PLX
    PLB
C3Mod_TaskNext:                         ; header: see C3Mod_RunTasks
    INX
    INX
    CPX.w #!C3_TaskListBytes
    BNE C3Mod_RunTasks_task             ; C3Mod_RunTasks' .task
    RTL

; $7E:39A7 — C3Mod_TaskEnd (10 bytes, $39A7–$39B0)
; A task's way out, reached by JMP from the task's own level (with
; nothing of the task's left on the stack): drops the task's return
; address (C3Mod_RunTasks' JSR), pulls what C3Mod_RunTasks saved (DP,
; P, X, DB),
; clears the task's entry of C3_TaskList and goes on with the next
; task (C3Mod_TaskNext).
; Callers note: JMP from tasks (reached through C3_TaskList; the trace
;   follows them): C3Mod_FadeInTask ($3492), C3Mod_FadeOutTask ($34A8),
;   C3Mod_FadeOutStopTask ($34E0), C3Mod_FadeOutExitTask ($34F8),
;   C3Mod_CountDownTask ($44F8), C3Mod_RaceStepTask ($48A6),
;   C3Mod_SkipTask ($5BBB), C3Mod_WaveCountTask ($5BCB), C3Mod_SwingTask
;   ($5CB7), C3Mod_FirstPicTask ($5D47), C3Mod_Prog3FadeTask3 ($6ACA), and
;   $9A9F, $9B7B and $9EF9 (code not matched yet).
; Entry: JMP from a task run by C3Mod_RunTasks, with the stack as the
;        task found it (C3Mod_RunTasks' JSR return address on top: a JSR
;        here would push a second one and misalign the pulls); X=0
;        (the first PLX must pull that 2-byte address), M any; DP, DB
;        any (restored).
; Exit:  into C3Mod_TaskNext with P, X, DP and DB as C3Mod_RunTasks
;        saved them (M=0, X=0); A unchanged.
C3Mod_TaskEnd:
    PLX                                 ; drop the return address
    PLD
    PLP
    PLX
    PLB
    STZ.w !C3_TaskList,X
    BRA C3Mod_TaskNext

; $7E:39B1 — C3Mod_TaskReplace (13 bytes, $39B1–$39BD)
; As C3Mod_TaskEnd, but the task's entry of C3_TaskList gets the
; address in X instead (the task hands itself over to another, from
; next frame).
; Callers note: JMP from tasks (the trace follows them):
;   C3Mod_MusicFadeTask ($34BF, after LDX #C3Mod_FadeOutStopTask),
;   C3Mod_ExitTask ($427F), C3Mod_WaitSongEndTask ($476E),
;   C3Mod_RaceFinish ($485A), C3Mod_ResetWaitTask ($63F1),
;   C3Mod_Prog3FadeTask1 ($6A71), C3Mod_Prog3FadeTask2 ($6A94),
;   C3Mod_CreditsTask ($6BF6), and $98A9 (code not matched yet).
; Entry: JMP from a task run by C3Mod_RunTasks, with the stack as the
;        task found it (C3Mod_RunTasks' JSR return address on top, as
;        for C3Mod_TaskEnd); X=0 (16-bit index: the address and the PLX
;        of the return address) with the new task's address in the X
;        register; M any; DP, DB any (restored).
; Exit:  into C3Mod_TaskNext with P, X, DP and DB as C3Mod_RunTasks
;        saved them (M=0, X=0); A = the new address.
C3Mod_TaskReplace:
    REP #$20
    TXA
    PLX                                 ; drop the return address
    PLD
    PLP
    PLX
    PLB
    STA.w !C3_TaskList,X
    BRA C3Mod_TaskNext

; $7E:39BE — C3Mod_RunNmiTasks (32 bytes, $39BE–$39DD)
; The NMI tasks: JSRs each nonzero word of C3_NmiTaskList (8 words,
; the list itself, not a copy) in turn, saving DB, X, P and DP around
; each, with M=1 and A = DP (TDC; C3_ModuleFrame's DP is 0). Ending
; or replacing an NMI task goes through C3Mod_NmiTaskEnd /
; C3Mod_NmiTaskReplace, which come back at C3Mod_NmiTaskNext.
; Sub-entry: C3Mod_NmiTaskNext ($39D6).
; Callers note: the kernel's C3_ModuleFrame (JSL !C3Mod_RunNmiTasks,
;   $C3:08F7), in the forced blank at the start of each frame.
;   C3Mod_NmiTaskNext: C3Mod_NmiTaskEnd (BRA).
; Entry: M any (REP #$20 here), X=0 (16-bit index), DP and DB as the
;        tasks expect (C3_ModuleFrame: DP=0, DB=$00).
; Exit:  M=0, X=0; A = 0 (the last entry was free) or what the last
;        task left; X = C3_NmiTaskListBytes; Y as the tasks leave it; DP
;        and DB as on entry (restored after each task).
C3Mod_RunNmiTasks:
    REP #$20
    LDX.w #0
.task:
    LDA.w !C3_NmiTaskList,X
    BEQ C3Mod_NmiTaskNext
    PHB
    PHX
    PHP
    PHD
    TDC
    SEP #$20
    JSR (!C3_NmiTaskList,X)
    PLD
    PLP
    PLX
    PLB
C3Mod_NmiTaskNext:                      ; header: see C3Mod_RunNmiTasks
    INX
    INX
    CPX.w #!C3_NmiTaskListBytes
    BNE C3Mod_RunNmiTasks_task          ; C3Mod_RunNmiTasks' .task
    RTL

; $7E:39DE — C3Mod_NmiTaskEnd (10 bytes, $39DE–$39E7)
; C3Mod_TaskEnd for an NMI task (reached by JMP the same way): clears
; its entry of C3_NmiTaskList and goes on with the next NMI task
; (C3Mod_NmiTaskNext).
; Callers note: JMP from NMI tasks (the trace follows them):
;   C3Mod_ClearColumnTask ($4674), C3Mod_Prog6StreamNmi ($7A32),
;   C3Mod_Prog6HalfNmi ($7A65), C3Mod_Prog10GridNmi ($8DF0),
;   C3Mod_Prog10Mode4Nmi ($8E85), and $9D22, $9F56 and $9F87 (code not
;   matched yet); also C3Mod_CharTilesDeadEnd ($78A8), right after
;   C3Mod_CharTilesNmiTask's RTS, which no trace reaches (probably dead).
; Entry: JMP from a task run by C3Mod_RunNmiTasks, with the stack as
;        the task found it (C3Mod_RunNmiTasks' JSR return address on
;        top: a JSR here would misalign the pulls); X=0 (the first PLX
;        must pull that 2-byte address), M any; DP, DB any (restored).
; Exit:  into C3Mod_NmiTaskNext with P, X, DP and DB as
;        C3Mod_RunNmiTasks saved them (M=0, X=0); A unchanged.
C3Mod_NmiTaskEnd:
    PLX                                 ; drop the return address
    PLD
    PLP
    PLX
    PLB
    STZ.w !C3_NmiTaskList,X
    BRA C3Mod_NmiTaskNext

; $7E:39E8 — C3Mod_NmiTaskReplace (13 bytes, $39E8–$39F4)
; C3Mod_TaskReplace for an NMI task (reached by JMP the same way): its
; entry of C3_NmiTaskList gets the address in X. Quirk: it then branches to C3Mod_TaskNext, the
; frame task loop, not to C3Mod_NmiTaskNext: the NMI tasks after it
; are skipped for this frame, and the C3_TaskRun entries after the
; replaced entry's index run instead, in the forced blank (C3_TaskRun
; still holds the previous frame's copy then: C3_ModuleFrame copies
; C3_TaskList after the NMI tasks), before the RTL; they run again
; later in the frame from C3Mod_RunTasks. Kept as it is (the bytes of
; the BRA say so: $80 $AA, to $399F).
; Callers note: none found: no JMP $39E8 byte pattern in the module.
;   It would be reached by JMP, as C3Mod_TaskReplace is.
; Entry: JMP from a task run by C3Mod_RunNmiTasks, with the stack as
;        the task found it (C3Mod_RunNmiTasks' JSR return address on
;        top); X=0 (16-bit index: the address and the PLX of the return
;        address) with the new task's address in the X register; M any;
;        DP, DB any (restored).
; Exit:  into C3Mod_TaskNext (see above) with P, X, DP and DB as
;        C3Mod_RunNmiTasks saved them (M=0, X=0); A = the new address.
C3Mod_NmiTaskReplace:
    REP #$20
    TXA
    PLX                                 ; drop the return address
    PLD
    PLP
    PLX
    PLB
    STA.w !C3_NmiTaskList,X
    BRA C3Mod_TaskNext

; ============================================================
; Sprites: a number, a list with mixed sizes ($39F5–$3B47)
; ============================================================

; $7E:39F5 — C3Mod_DrawNumber (136 bytes, $39F5–$3A7C)
; Draws C3_ScratchF0 as up to 5 decimal digits with C3_SprListSmall:
; the digits go into the tile bytes of C3Mod_NumberSprites (tile
; C3_DigitTile0 + the digit; its records place them right to left, 7
; pixels apart from C3_SprBaseX / C3_SprBaseY); the leading zeros are
; left out by the list's count (the ones digit always shows). The
; ten-thousands, thousands and hundreds come from subtraction loops, the
; tens and ones from the hardware divider (16-bit stores: WRDIVB's also
; writes HTIMEL with 0). DB is set to $7E for the list with PEA $007E /
; PLB, and to $00 for the sprite builder by the second PLB (the PEA's
; other byte).
; Callers note: C3Mod_DrawHud ($5187, $51AE JMP).
; Entry: M=0, X any (8-bit set here), DP=0 (C3_ScratchF0, and
;        C3_SprListSmall's C3_OamPos..), DB any (left $00); C3_ScratchF0
;        = the number; C3_SprBaseX/Y = where its left end goes.
; Exit:  M=0, X=0, DB = $00; A, X, Y as C3_SprListSmall leaves them;
;        C3Mod_NumberSprites rewritten.
; Calls: C3_SprListSmall (JSL).
C3Mod_DrawNumber:
    LDA.b !C3_ScratchF0
    SEP #$10
    PEA.w !Bank7E                       ; PLB takes the $7E; the $00 stays for the second PLB
    PLB
    LDY.b #!C3_DigitTile0-1
.ten_thousands:
    SEC
    SBC.w #!C3_Dec10000
    INY
    BCS .ten_thousands
    ADC.w #!C3_Dec10000
    STY.w C3Mod_NumberSprites_ten_thousands
    LDY.b #!C3_DigitTile0-1
.thousands:
    SEC
    SBC.w #!C3_Dec1000
    INY
    BCS .thousands
    ADC.w #!C3_Dec1000
    STY.w C3Mod_NumberSprites_thousands
    LDY.b #!C3_DigitTile0-1
.hundreds:
    SEC
    SBC.w #!C3_Dec100
    INY
    BCS .hundreds
    ADC.w #!C3_Dec100
    STY.w C3Mod_NumberSprites_hundreds
    STA.l WRDIVL                        ; and WRDIVH
    LDA.w #!C3_Dec10
    STA.l WRDIVB                        ; and HTIMEL (0)
    SEP #$20
    LDY.w C3Mod_NumberSprites_ten_thousands
    LDX.b #!C3_NumberRecords+1
    NOP                                 ; (the divider's time)
    LDA.b #!C3_DigitTile0
    CLC
    ADC.l RDDIVL
    STA.w C3Mod_NumberSprites_tens
    LDA.l RDMPYL                        ; the remainder
    CLC
    ADC.b #!C3_DigitTile0
    STA.w C3Mod_NumberSprites_ones
    TYA
    CMP.b #!C3_DigitTile0
    BNE .count
    DEX                                 ; a leading zero: one record less
    LDA.w C3Mod_NumberSprites_thousands
    CMP.b #!C3_DigitTile0
    BNE .count
    DEX
    LDA.w C3Mod_NumberSprites_hundreds
    CMP.b #!C3_DigitTile0
    BNE .count
    DEX
    LDA.w C3Mod_NumberSprites_tens
    CMP.b #!C3_DigitTile0
    BNE .count
    DEX
.count:
    STX.w C3Mod_NumberSprites
    PLB                                 ; DB = $00
    REP #$30
    LDA.w #C3Mod_NumberSprites
    JSL !C3_SprListSmall
    RTS

; $7E:3A7D — C3Mod_NumberSprites (21 bytes, $3A7D–$3A91)
; C3Mod_DrawNumber's sprite list for C3_SprListSmall: the count (records
; + 1, written) and 5 records of tile (written), attribute, X, Y: the
; ones, tens, hundreds, thousands and ten-thousands, X = $1C down to 0.
C3Mod_NumberSprites:
    db 0
.ones:
    db 0, !C3_DigitAttr, $1C, 0
.tens:
    db 0, !C3_DigitAttr, $15, 0
.hundreds:
    db 0, !C3_DigitAttr, $0E, 0
.thousands:
    db 0, !C3_DigitAttr, $07, 0
.ten_thousands:
    db 0, !C3_DigitAttr, $00, 0

; $7E:3A92 — C3Mod_SprListMixedEnd (5 bytes, $3A92–$3A96)
; C3Mod_SprListMixed's exit, placed before its entry.
C3Mod_SprListMixedEnd:                  ; header: see C3Mod_SprListMixed
    REP #$20
    STY.b !C3_OamPos
    RTL

; $7E:3A97 — C3Mod_SprListMixed (177 bytes, $3A97–$3B47)
; Adds a list of sprites to the OAM shadow, like the kernel's
; C3_SprListSmall / C3_SprListLarge but with both sizes and signed
; offsets: the list (in bank $7E at A, read through WMDATA) is a byte n +
; 1, then n records of tile, attribute, X, Y. The attribute's bit 4
; (C3_SprLargeBit) picks the large size and is cleared in OAM (so the
; sprites have priority 0 or 2 only). X and Y are signed bytes added to
; C3_SprBaseX / C3_SprBaseY: an X below 0 gets X bit 8 set, an X from
; $100 up hides the sprite (Y = $E0; its X byte is not written, and its
; high-table bits are small, X bit 8 clear); a Y below 0 or from $E0 up
; becomes $E0 (below the screen). Each sprite's two high-table bits are
; shifted in at the top of the byte at C3_OamHiPtr, which moves on after
; every 4 sprites; C3_OamPos is stored back at the end, through
; C3Mod_SprListMixedEnd ($3A92), placed before the entry. The Y byte
; is read with a 16-bit LDA (WMDATA and the write-only WMADDL: open bus
; in the high byte, which the sign extension drops).
; Sub-entry: C3Mod_SprListMixedEnd, the exit (RTL).
; Callers note: JSL from C3Mod_Prog6HorizonTask ($7F9C, $7FB0, $7FBF),
;   C3Mod_Prog6AnimTask ($8386) and $9A6A (code not matched yet).
; Entry: M=0 (A stored to WMADDL/M as a word), X=0 (16-bit Y), DP=0
;        (C3_OamPos.., C3_SprAttr), DB = $00-$3F (the ports and the
;        OAM shadow are absolute); A = the list's address.
; Exit:  RTL with M=0, X=0; Y = C3_OamPos (advanced); C3_OamHiPtr
;        advanced; C3_SprLeft = 0; C3_SprAttr = the last record's
;        attribute (unchanged for an empty list); A changed; WMADD after
;        the list.
C3Mod_SprListMixed:
    STA.w WMADDL                        ; and WMADDM
    LDY.b !C3_OamPos
    LDA.w #!Bank7E
    SEP #$20
    STA.w WMADDH
    LDA.w WMDATA
    STA.b !C3_SprLeft
.next:
    DEC.b !C3_SprLeft
    BEQ C3Mod_SprListMixedEnd
    LDA.w WMDATA
    STA.w !Oam_LowTable+2,Y             ; the tile
    LDA.w WMDATA
    STA.b !C3_SprAttr
    AND.b #!C3_SprLargeBit^$FF
    STA.w !Oam_LowTable+3,Y             ; the attribute
    LDA.w WMDATA                        ; X
    REP #$20
    ORA.w #!C3_SignExtend
    BIT.w #!C3_SignBit8
    BNE .x_signed
    AND.w #!Eng_LowByteMask
.x_signed:
    CLC
    ADC.b !C3_SprBaseX
    BMI .left
    CMP.w #!C3_ScreenRight
    BPL .off_right
    SEP #$20
    STA.w !Oam_LowTable,Y
    LDA.b !C3_SprAttr
    BIT.b #!C3_SprLargeBit
    BEQ .small
    LDA.b (!C3_OamHiPtr)
    LSR A
    SEC
    ROR A                               ; %10: large, X bit 8 clear
    BRA .high_bits
.small:
    LDA.b (!C3_OamHiPtr)
    LSR A
    LSR A                               ; %00
    BRA .high_bits
.left:
    SEP #$20
    STA.w !Oam_LowTable,Y
    LDA.b !C3_SprAttr
    BIT.b #!C3_SprLargeBit
    BEQ .left_small
    LDA.b (!C3_OamHiPtr)
    SEC
    ROR A
    SEC
    ROR A                               ; %11: large, X bit 8
    BRA .high_bits
.left_small:
    LDA.b (!C3_OamHiPtr)
    SEC
    ROR A
    LSR A                               ; %01: small, X bit 8
.high_bits:
    STA.b (!C3_OamHiPtr)
    REP #$20
    LDA.w WMDATA                        ; Y (the high byte: see above)
    ORA.w #!C3_SignExtend
    BIT.w #!C3_SignBit8
    BNE .y_signed
    AND.w #!Eng_LowByteMask
.y_signed:
    CLC
    ADC.b !C3_SprBaseY
    BMI .y_off
    CMP.w #!C3_SprHideY
    BMI .y_ok
.y_off:
    LDA.w #!C3_SprHideY
.y_ok:
    SEP #$20
.store_y:
    STA.w !Oam_LowTable+1,Y
    INY
    INY
    INY
    INY
    TYA
    AND.b #!C3_OamGroupMask
    BNE .same_byte
    INC.b !C3_OamHiPtr                  ; the next high-table byte after 4 sprites
.same_byte:
    JMP .next
.off_right:
    SEP #$20
    LDA.b (!C3_OamHiPtr)
    LSR A
    LSR A
    STA.b (!C3_OamHiPtr)
    LDA.w WMDATA                        ; the Y byte, unused
    LDA.b #!C3_SprHideY
    BRA .store_y

%C3ModOrg($7E3B48)
; ============================================================
; Program 0 (and 9): the set-up ($3B48–$3F13)
; ============================================================

; $7E:3B48 — C3Mod_Prog0 (509 bytes, $3B48–$3D44)
; The program of C3Mod_ProgramTable entries 0 and 9: sets up the race
; course scene and starts its scripts, then returns to C3Mod_Start.
;   - C3_Prog9 = 1 when C3_EntryArg bits 0-3 are not 0 (program 9);
;     unless C3_EntryNoSong, song C3_SongCourse (C3Mod_PlaySong);
;   - the graphics (C3Mod_Prog0LoadGfx, which also leaves
;     Decomp_DestBank = $7F); packs 2 and 3 unpacked to $7F:0A00 and
;     $7F:8A00; then, with DB = $7F (the MVN's): $7F:0A00-$37FF moved
;     to $3800 up (MVN), pack 3's four 8x8 blocks put into the 64-byte
;     rows from $3808 (the second one twice: C3Mod_CopyTileBlock), and
;     mirrored rows written through WMDATA (DP = DP_PPU; the row end in
;     C3_MirrorEnd, $7F:0200): 120 rows from $0A00 and $2C00 to
;     $7F:5A00, 72 from $3800 to $7800, then pack 4 (unpacked over pack
;     3 at $7F:8A00) as 96 rows to $AE00 (C3_MirrorLeft, $7F:0202,
;     counts the 12 calls);
;   - $7E:F000-$FFFF and $7E:0C00-$1DFF filled from MPYL by DMA (B to
;     A), zeroed: M7A x M7B is 0 (C3Mod_Init's PPU clear at
;     $3148-$314E writes M7A = M7B = 0 after its C3Mod_HideSprites
;     call; on the C3_BootIrqOn path, which returns before both, the
;     direct-page clear left $0404 x 0); C3Scale_PrevEnd = $0A00; the HDMA channels of
;     C3Mod_Prog0Hdma (C3Mod_SetupHdma) and C3_HdmaEnable = channels
;     0-5; C3Mod_Prog0Vars;
;   - C3_EntryArg bit 6 clear: page $0A00 runs C3Mod_Prog0ScriptA and
;     $0B00 C3Mod_Prog0ScriptB, C3_HdmaEnable without channel 0 and
;     C3_ResultWord = 0; set: the kernel's wipe set up (WinFx_C3E*:
;     table at $7E:E000, frame 0), wipe mode 2 written over
;     C3Mod_ExitTask's operand, the PPU windows (window 1 on BG1-BG4,
;     the sprites and the colour window, WH0 = 0, WH1 = $FF, WH2 = 0,
;     TMW = BG1-BG3 and OBJ, TSW = BG3), and page
;     $0A00 runs C3Mod_Prog0WipeA or C3Mod_Prog0WipeB in turn
;     (C3_StartCount bit 0) with $0B00 on C3Mod_Prog0WipeScriptB;
;     both: C3_FadeStep = C3_FadeTimer = 8;
;   - runs page $0A00's script once (C3Mod_ScriptTaskA: DP = $0A00,
;     DB = $7E until the PLB), writes C3Mod_Prog0Setup over
;     C3Mod_BuildM7Tables' setup call ($35FD) and C3Mod_ScaleIdle over
;     C3Mod_Start's idle call ($3024);
;   - builds the copy code at $7E:B574 (C3_BuildCopyCode, X = $0C00,
;     Y = $0200), sets the BG maps and tiles (BG1SC = $60, BG2SC =
;     $64, BG3SC = $68, BG12NBA = BG34NBA = $77), CGWSEL = add the sub
;     screen, TM = BG1-BG3 and OBJ, TS = BG3, and saves the low bytes
;     of 20 VRAM words from $0B00, 128 words apart (VMAIN = +128 after
;     the low byte), to C3_MapColumnSave by DMA (B to A, RDVRAML): a
;     column of the mode-7 map, which C3Mod_ClearColumnTask and
;     C3Mod_RestoreColumnTask rewrite.
; Callers note: C3Mod_ProgramTable entries 0 and 9 (C3Mod_Start's JSR
;   (table,X) at $300A).
; Entry: M=1, X=0, DP=0, DB=$00 (as C3Mod_Start calls the programs);
;        C3_EntryArg as the module was entered with.
; Exit:  M=1, X=0, DP=0, DB=$00 (C3_BuildCopyCode's); A = MDMAEN_Ch7,
;        X = C3_MapColumnBytes, Y = $0010 (C3_BuildCopyCode's).
; Calls: C3Mod_PlaySong, C3Mod_Prog0LoadGfx, C3Mod_UnpackPack,
;   C3Mod_CopyTileBlock, C3Mod_MirrorRows3, C3Mod_MirrorRows,
;   C3Mod_SetupHdma, C3Mod_Prog0Vars, C3Mod_ScriptTaskA,
;   C3_BuildCopyCode (JSL).
C3Mod_Prog0:
    LDA.w !C3_EntryArg
    AND.b #!C3_EntryLowNibble
    BEQ .prog0
    INC.b !C3_Prog9
.prog0:
    LDA.w !C3_EntryArg
    BIT.b #!C3_EntryNoSong
    BNE .no_song
    LDA.b #!C3_SongCourse
    JSR C3Mod_PlaySong
.no_song:
    JSR C3Mod_Prog0LoadGfx
    LDX.w #!C3_Prog0PicsA
    STX.w !Decomp_Dest
    LDX.w #2*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog0PicsB
    STX.w !Decomp_Dest
    LDX.w #3*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    REP #$20
    LDX.w #!C3_Prog0PicsA
    LDY.w #!C3_Prog0PicsMoved
    LDA.w #!C3_Prog0PicsBytes-1
    PHB
    MVN !Bank7F,!Bank7F                 ; lint-ok: MVN operands are bank bytes
    LDX.w #!C3_Prog0PicsB
    LDY.w #!C3_Prog0PicsMoved+8
    JSR C3Mod_CopyTileBlock
    PHX
    LDY.w #!C3_Prog0PicsMoved+$608
    JSR C3Mod_CopyTileBlock
    PLX                                 ; the same block again
    LDY.w #!C3_Prog0PicsMoved+$C08
    JSR C3Mod_CopyTileBlock
    LDY.w #!C3_Prog0PicsMoved+$140C
    JSR C3Mod_CopyTileBlock
    LDY.w #!C3_Prog0PicsMoved+$1A0C
    JSR C3Mod_CopyTileBlock
    SEP #$20
    PHD
    PEA.w !DP_PPU
    PLD
    LDA.b #!WMADDH_Bank7F
    STA.b WMADDH-!DP_PPU
    LDX.w #!C3_MirrorEnd32
    STX.w !C3_MirrorEnd                 ; $7F:0200 (DB = $7F)
    LDX.w #!C3_Prog0MirrorA
    STX.b WMADDL-!DP_PPU                ; and WMADDM
    LDY.w #!C3_Prog0PicsA
    JSR C3Mod_MirrorRows3
    JSR C3Mod_MirrorRows3
    JSR C3Mod_MirrorRows3
    LDY.w #!C3_Prog0PicsA+$2200
    JSR C3Mod_MirrorRows3
    JSR C3Mod_MirrorRows3
    LDX.w #!C3_Prog0MirrorB
    STX.b WMADDL-!DP_PPU
    LDY.w #!C3_Prog0PicsMoved
    JSR C3Mod_MirrorRows3
    JSR C3Mod_MirrorRows3
    JSR C3Mod_MirrorRows3
    LDX.w #!C3_MirrorEnd24
    STX.w !C3_MirrorEnd
    LDX.w #4*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog0MirrorC
    STX.b WMADDL-!DP_PPU
    LDY.w #!C3_Prog0PicsB
    LDA.b #!C3_Prog0MirrorCalls
    STA.w !C3_MirrorLeft                ; $7F:0202
.mirror:
    JSR C3Mod_MirrorRows
    DEC.w !C3_MirrorLeft
    BNE .mirror
    PLD
    PLB
    LDX.w #!BBAD_MPYL<<8|!DMAP_BtoA
    STX.w DMAP7                         ; and BBAD7
    LDX.w #!C3_M7Tables&$FFFF
    STX.w A1T7L
    LDA.b #bank(!C3_M7Tables)
    STA.w A1B7
    LDX.w #!C3_M7TablesBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDX.w #!BBAD_MPYL<<8|!DMAP_BtoA
    STX.w DMAP7
    LDX.w #!C3_Prog0Clear
    STX.w A1T7L
    LDA.b #!Bank7E
    STA.w A1B7
    LDX.w #!C3_Prog0ClearBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDX.w #!C3_Prog0PicsA
    STX.b !C3Scale_PrevEnd
    LDY.w #C3Mod_Prog0Hdma
    JSR C3Mod_SetupHdma
    LDA.b #!C3_Prog0HdmaOn
    STA.w !C3_HdmaEnable
    JSR C3Mod_Prog0Vars                 ; returns with M=0
    LDA.w !C3_EntryArg
    BIT.w #!C3_EntryWipeStart
    BNE .wipe_start
    LDA.w #C3Mod_Prog0ScriptA
    STA.w !C3_ScriptPageA+!C3Script_Ptr
    LDA.w #C3Mod_Prog0ScriptB
    STA.w !C3_ScriptPageB+!C3Script_Ptr
    LDA.w #!C3_Prog0Fade
    STA.w !C3_FadeStep                  ; and C3_FadeTimer
    SEP #$20
    LDA.b #!C3_Prog0HdmaNoWipe
    STA.w !C3_HdmaEnable
    REP #$20
    STZ.w !C3_ResultWord
    BRA .run_script
.wipe_start:
    LDA.w #!C3_Prog0Fade
    STA.w !C3_FadeStep
    LDA.w #!Bank7E
    STA.w !WinFx_C3ETableBank           ; and its high byte
    LDX.w #!C3_WipeTable&$FFFF
    STX.w !WinFx_C3ETablePtr
    STZ.w !WinFx_WipeFrame              ; and WinFx_C3ETablePtr's low byte (0 already)
    SEP #$20
    LDA.b #!WinFx_C3EMode2
    STA.l C3Mod_ExitTask_wipe_mode+1
    REP #$20
    LDA.w #!W12SEL_Bg12Win1             ; each store also zeroes the next register,
    STA.w W12SEL                        ; which the next store rewrites:
    STA.w W34SEL                        ; window 1 on BG1-BG4,
    STA.w WOBJSEL                       ; the sprites and the colour window; WH0 = 0
    LDA.w #!WH_RightEdge
    STA.w WH1                           ; and WH2 = 0
    LDX.w #!Layer_Bg123Obj|(!Layer_Bg3<<8)
    STX.w TMW                           ; and TSW
    LDA.w !C3_StartCount
    INC A
    STA.w !C3_StartCount
    LSR A
    BCS .wipe_b
    LDA.w #C3Mod_Prog0WipeA
    STA.w !C3_ScriptPageA+!C3Script_Ptr
    LDA.w #C3Mod_Prog0WipeScriptB
    STA.w !C3_ScriptPageB+!C3Script_Ptr
    BRA .run_script
.wipe_b:
    LDA.w #C3Mod_Prog0WipeB
    STA.w !C3_ScriptPageA+!C3Script_Ptr
    LDA.w #C3Mod_Prog0WipeScriptB
    STA.w !C3_ScriptPageB+!C3Script_Ptr
.run_script:
    PHB
    JSR C3Mod_ScriptTaskA
    LDA.w #C3Mod_Prog0Setup
    STA.w C3Mod_BuildM7Tables_setup+1   ; DB = $7E here
    LDA.w #C3Mod_ScaleIdle
    STA.w C3Mod_Start_wait_exit+1
    PLB
    SEP #$20
    LDA.b #!Bank7E
    STA.w WMADDH
    LDX.w #!C3_CopyCode&$FFFF
    STX.w WMADDL                        ; and WMADDM
    LDX.w #!C3_CopyCodeDest
    LDY.w #!C3_CopyCodeSrc
    JSL !C3_BuildCopyCode
    LDX.w #!C3_Prog0Bg1Sc|(!C3_Prog0Bg2Sc<<8)
    STX.w BG1SC                         ; and BG2SC
    LDA.b #!C3_Prog0Bg3Sc
    STA.w BG3SC
    LDA.b #!C3_Prog0Tiles
    STA.w BG12NBA
    STA.w BG34NBA
    LDA.b #!CGWSEL_AddSubscreen
    STA.w CGWSEL
    LDX.w #!Layer_Bg123Obj|(!Layer_Bg3<<8)
    STX.w TM                            ; and TS
    LDA.b #!VMAIN_Inc128
    STA.w VMAIN
    LDX.w #!C3_MapColumn
    STX.w VMADDL
    LDX.w #!BBAD_RDVRAML<<8|!DMAP_BtoA
    STX.w DMAP7
    LDX.w #!C3_MapColumnSave&$FFFF
    STX.w A1T7L
    LDA.b #bank(!C3_MapColumnSave)
    STA.w A1B7
    LDX.w #!C3_MapColumnBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    RTS

; $7E:3D45 — C3Mod_Prog0Hdma (31 bytes, $3D45–$3D63)
; Program 0's HDMA channels, records for C3Mod_SetupHdma (DMAP, BBAD,
; table, bank), channel 0 first:
;   0: indirect, WH0: C3Mod_WipeHdmaA (C3Mod_WipeTask switches it);
;   1: indirect, M7A/M7B: C3Mod_M7HdmaAB;
;   2: indirect, M7C/M7D: C3Mod_M7HdmaCD;
;   3: indirect, two registers twice (BG1HOFS/BG1VOFS):
;      C3Mod_ScrollHdma;
;   4: indirect, two registers (CGADSUB/COLDATA): C3Mod_MathHdma;
;   5: indirect, BGMODE: C3Mod_ModeHdma;
; then the end byte.
C3Mod_Prog0Hdma:
    db !DMAP_HdmaIndirect, !BBAD_WH0 : dw C3Mod_WipeHdmaA : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegsTwice, !BBAD_M7A : dw C3Mod_M7HdmaAB : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegsTwice, !BBAD_M7C : dw C3Mod_M7HdmaCD : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegsTwice, !BBAD_BG1HOFS : dw C3Mod_ScrollHdma : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegs, !BBAD_CGADSUB : dw C3Mod_MathHdma : db !Bank7E
    db !DMAP_HdmaIndirect, !BBAD_BGMODE : dw C3Mod_ModeHdma : db !Bank7E
    db !C3_HdmaListEnd

; $7E:3D64 — C3Mod_WipeHdmaA (7 bytes, $3D64–$3D6A)
; Indirect HDMA table for WH0 (window 1's left edge): 112 lines from
; $7E:E000 and 112 from $E070, one byte a line (the table the kernel's
; wipe, WinFx_StepWipe, writes on odd frames), then the end.
C3Mod_WipeHdmaA:
    db !C3_HdmaRepeat112 : dw !C3_WipeTable&$FFFF
    db !C3_HdmaRepeat112 : dw (!C3_WipeTable&$FFFF)+(!C3_WipeHalf)
    db 0

; $7E:3D6B — C3Mod_WipeHdmaB (7 bytes, $3D6B–$3D71)
; The same for the second buffer, $7E:E0E0 (WinFx_Lines on: even
; frames).
C3Mod_WipeHdmaB:
    db !C3_HdmaRepeat112 : dw (!C3_WipeTable&$FFFF)+(2*!C3_WipeHalf)
    db !C3_HdmaRepeat112 : dw (!C3_WipeTable&$FFFF)+(3*!C3_WipeHalf)
    db 0

; $7E:3D72 — C3Mod_WipeTask (26 bytes, $3D72–$3D8B)
; A task: one frame of the kernel's wipe (BankC3_Entry000E, i.e.
; WinFx_StepWipe, with the WinFx_C3E* arguments C3Mod_Prog0 set), then
; points HDMA channel 0's table (A1T0L) by WinFx_WipeFrame's parity:
; C3Mod_WipeHdmaA when it is odd, else C3Mod_WipeHdmaB.
; Callers note: a task added by script opcode $FA at $413F
;   (C3Mod_Prog0Start).
; Entry: a task (C3Mod_RunTasks): M=0, X=0, DP=0, DB=$00 (WinFx_StepWipe
;        restores what it saves; the stores are absolute).
; Exit:  RTS with M=1, X=0; A = WinFx_WipeFrame / 2, X = the table's
;        address; Y as WinFx_StepWipe leaves it (restored).
; Calls: BankC3_Entry000E (JSL).
C3Mod_WipeTask:
    JSL !BankC3_Entry000E
    SEP #$20
    LDA.w !WinFx_WipeFrame
    LSR A
    BCC .even
    LDX.w #C3Mod_WipeHdmaA
    STX.w A1T0L
    RTS
.even:
    LDX.w #C3Mod_WipeHdmaB
    STX.w A1T0L
    RTS

; $7E:3D8C — C3Mod_Prog0LoadGfx (299 bytes, $3D8C–$3EB6)
; Program 0's graphics, all with the screen off (the NMI is not on
; yet):
;   - VRAM words $4000-$47FF cleared (DMA of a fixed zero word,
;     C3Mod_FillBytes + 1, to VMDATAL/H; the sprite tiles, OBSEL
;     C3_Obsel);
;   - pack 5 to C3_PaletteWork ($7E:2000: Decomp_DestBank 0 is WRAM
;     bank $7E) and C3Mod_CommitPalette;
;   - C3Mod_DestBitmapSrc: Decomp_Dest = $7F:0200 (C3_BitmapSrc) for the
;     rest; pack 7 to VRAM's high bytes from word 0 (VMAIN = $80 as
;     left by the clear: C3_DmaMode 0, C3_DmaBbad VMDATAH: the mode-7
;     tiles), packs 8 and 9 (64 x 64 bytes each) each made 64 map rows
;     of 128 with every row twice side by side (C3Mod_DoubleRows) and
;     sent by C3Mod_SendM7Map to VRAM's low bytes (VMAIN = 0): the
;     mode-7 map, pack 8's rows from word 0, pack 9's from $2000;
;   - VMAIN = $80, two registers (VMDATAL/H): packs 13 and 14 to words
;     $7000 and $7100 (the BG tiles, BG12NBA = BG34NBA = $77), pack 6
;     to $5000 (the sprites' second tile page);
;   - $7E:E100-$E13F zeroed (a word stored, then an overlapping MVN),
;     $7F:0300-$09FF filled from MPYL by DMA (B to A; 0 if M7A x M7B
;     is, as C3Mod_Prog0's fills);
;   - $800 bytes (Decomp_OutLen set) from $7F:0200 after each of pack
;     10 to word $6000, pack 12 to $6800 and pack 11 to $6400 (the maps
;     of BG1, BG3 and BG2: BG1SC $60, BG3SC $68, BG2SC $64). Packs 10
;     and 12 unpack to only $100 bytes, so $700 of each $800 sent is the
;     $7F:0300-$09FF fill just made (from MPYL); pack 11 is $800 bytes
;     and overwrites that fill, so it comes last.
; Callers note: C3Mod_Prog0 ($3B5D).
; Entry: M=1, X=0, DP with a low byte of 0 (the TDC that makes
;        C3_DmaMode 0; DP=0 at the call; the DMA arguments are
;        absolute), DB=$00 (absolute register and RAM stores).
; Exit:  M=1, X=0, DP and DB unchanged (the MVN's DB restored);
;        Decomp_DestBank = $7F, Decomp_Dest = C3_BitmapSrc;
;        C3_DmaMode = DMAP_TwoRegs, C3_DmaBbad = VMDATAL; A =
;        MDMAEN_Ch7, X = Decomp_OutLen ($0800), Y = $E140 (past the
;        MVN; Decomp_ToWram restores it).
; Calls: C3Mod_UnpackPack, C3Mod_CommitPalette, C3Mod_DestBitmapSrc,
;   C3Mod_DmaUnpacked (JSL), C3Mod_DoubleRows (JSL), C3Mod_SendM7Map.
C3Mod_Prog0LoadGfx:
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDX.w #!C3_SprTilesVram
    STX.w VMADDL
    LDX.w #!BBAD_VMDATAL<<8|!DMAP_FixedSource|!DMAP_TwoRegs
    STX.w DMAP7                         ; and BBAD7
    LDX.w #C3Mod_FillBytes+1            ; the zero word
    STX.w A1T7L
    LDA.b #!Bank7E
    STA.w A1B7
    LDX.w #!C3_SprTilesBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    STZ.w !Decomp_DestBank
    LDX.w #!C3_PaletteWork&$FFFF
    STX.w !Decomp_Dest
    LDX.w #5*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSR C3Mod_CommitPalette
    JSR C3Mod_DestBitmapSrc
    LDX.w #0
    STX.w VMADDL
    LDX.w #7*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    TDC                                 ; A = 0 (DP = 0 at the call)
    STA.w !C3_DmaMode
    LDA.b #!BBAD_VMDATAH
    STA.w !C3_DmaBbad
    JSL C3Mod_DmaUnpacked
    LDX.w #0
    STX.w VMADDL
    LDX.w #8*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DoubleRows
    JSR C3Mod_SendM7Map
    LDX.w #9*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DoubleRows
    JSR C3Mod_SendM7Map
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDA.b #!DMAP_TwoRegs
    STA.w !C3_DmaMode
    LDA.b #!BBAD_VMDATAL
    STA.w !C3_DmaBbad
    LDX.w #!C3_Prog0BgTiles
    STX.w VMADDL
    LDX.w #13*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DmaUnpacked
    LDX.w #!C3_Prog0BgTiles+$100
    STX.w VMADDL
    LDX.w #14*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DmaUnpacked
    LDX.w #!C3_SprTilesHigh
    STX.w VMADDL
    LDX.w #6*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DmaUnpacked
    REP #$20
    LDX.w #!C3_WipeTable+$100&$FFFF
    TXY
    INY
    LDA.w #0
    STA.l !Eng_PtrBase|(!Bank7E<<16),X
    LDA.w #!C3_WipeClearBytes-2
    PHB
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes
    PLB
    SEP #$20
    LDX.w #!BBAD_MPYL<<8|!DMAP_BtoA
    STX.w DMAP7
    LDX.w #!C3_Prog0Clear7F&$FFFF
    STX.w A1T7L
    LDA.b #!Bank7F
    STA.w A1B7
    LDX.w #!C3_Prog0Clear7FBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDX.w #!C3_Prog0Bg1Map
    STX.w VMADDL
    LDX.w #10*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog0MapBytes
    STX.w !Decomp_OutLen
    JSL C3Mod_DmaUnpacked
    LDX.w #!C3_Prog0Bg3Map
    STX.w VMADDL
    LDX.w #12*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog0MapBytes
    STX.w !Decomp_OutLen
    JSL C3Mod_DmaUnpacked
    LDX.w #!C3_Prog0Bg2Map
    STX.w VMADDL
    LDX.w #11*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog0MapBytes
    STX.w !Decomp_OutLen
    JSL C3Mod_DmaUnpacked
    RTS

; $7E:3EB7 — C3Mod_CopyTileBlock (22 bytes, $3EB7–$3ECC)
; Copies a block of 8 rows of 8 bytes, stored one after the other at X,
; into a bitmap of 64-byte rows at Y (MVN in bank $7F, Y moved on by
; $38 after each row's 8).
; Callers note: C3Mod_Prog0 ($3B8D, $3B94, $3B9B, $3BA1, $3BA7).
; Entry: M=0, X=0 (MVN's 16-bit X and Y), DP = the page of C3_RowsLeft
;        (0 at the calls), DB any; X = the block, Y = where its first
;        row goes.
; Exit:  M=0, X=0, DB = $7F (the MVN's, not restored); A = Y = Y + 8 x
;        $40, X = X + 64; C3_RowsLeft = 0.
C3Mod_CopyTileBlock:
    LDA.w #!C3_TileRows
    STA.b !C3_RowsLeft
.row:
    LDA.w #!C3_TileRowBytes-1
    MVN !Bank7F,!Bank7F                 ; lint-ok: MVN operands are bank bytes
    TYA
    CLC
    ADC.w #!C3_RowBytes-!C3_TileRowBytes
    TAY
    DEC.b !C3_RowsLeft
    BNE .row
    RTS

; $7E:3ECD — C3Mod_MirrorRows3 (6 bytes with C3Mod_MirrorRows, $3ECD–$3F13)
; C3Mod_MirrorRows three times (JSR, JSR, and falling in): 24 rows.
; C3Mod_MirrorRows ($3ED3) writes 8 rows of 64 bytes through WMDATA,
; each the 32 bytes at Y + C3_MirrorEnd down to Y + C3_MirrorEnd - 31
; (read right to left: a 32-pixel row mirrored, if the bytes are
; pixels) and then 32 zero bytes; Y moves on by 64 (C3_RowBytes) per
; row. C3_MirrorEnd ($0200 of the source bank) is $20 or $18 at
; C3Mod_Prog0's calls.
; Callers note: C3Mod_Prog0 ($3BC3, $3BC6, $3BC9, $3BCF, $3BD2, $3BDD,
;   $3BE0, $3BE3). C3Mod_MirrorRows: C3Mod_Prog0 ($3BFF),
;   C3Mod_MirrorRows3 ($3ECD, $3ED0) and C3Mod_Prog10TurnB ($8813, $8816).
; Entry: M=1, X=0 (16-bit X and Y), DP = DP_PPU (WMDATA as $80), DB =
;        the source's bank ($7F at C3Mod_Prog0's calls: C3_MirrorEnd
;        and the rows are absolute); Y = the first source row; WMADD
;        = where the rows go.
; Exit:  M=1, X=0, DP and DB unchanged; A = Y (the last row's TYA /
;        ADC, 16-bit), X = 0, Y = Y + 8 x 64 per call (24 x 64 for
;        C3Mod_MirrorRows3); WMADD past the rows.
C3Mod_MirrorRows3:
    JSR C3Mod_MirrorRows
    JSR C3Mod_MirrorRows
C3Mod_MirrorRows:                       ; header: see C3Mod_MirrorRows3
    LDX.w #!C3_TileRows
.row:
    PHX
    REP #$20
    TYA
    CLC
    ADC.w !C3_MirrorEnd
    TAX
    SEP #$20
    PHY
    LDY.w #!C3_MirrorBytes
.byte:
    LDA.w !Eng_PtrBase,X
    STA.b WMDATA-!DP_PPU
    DEX
    DEY
    BNE .byte
    PLY
    LDX.w #!C3_MirrorBytes/8
    TDC                                 ; A = 0 (DP_PPU's low byte)
.zeros:
    STA.b WMDATA-!DP_PPU
    STA.b WMDATA-!DP_PPU
    STA.b WMDATA-!DP_PPU
    STA.b WMDATA-!DP_PPU
    STA.b WMDATA-!DP_PPU
    STA.b WMDATA-!DP_PPU
    STA.b WMDATA-!DP_PPU
    STA.b WMDATA-!DP_PPU
    DEX
    BNE .zeros
    REP #$21                            ; and C = 0
    TYA
    ADC.w #!C3_RowBytes
    TAY
    SEP #$20
    PLX
    DEX
    BNE .row
    RTS

; ============================================================
; Program 0's scripts and tasks ($3F14–$4318)
; ============================================================
; The scripts are C3_RunScript's (opcodes !C3Op_*, module.inc). Page
; $0A00's variables steer the mode-7 view (C3_View*: 0 the scale, 1 the
; X position, 2 the distance, 5 the angle, 6 the horizon line, 8 the
; first divisor, 9 the X speed, 11 the step mode, as the tasks below
; read them); page $0B00's variable 2 is the view's Y (C3_ViewY). A
; loop opcode runs its body limit + 1 times (counter 0 first).

; $7E:3F14 — C3Mod_Prog0ScriptA (69 bytes, $3F14–$3F58)
; Page $0A00's first script (C3_EntryArg bit 6 clear): adds the frame
; tasks (C3Mod_ViewTask, C3Mod_PadDelayTask, both scripts' tasks,
; C3Mod_TurnTask, C3Mod_DrawTask, C3Mod_ProjectTask, C3Mod_FadeInTask,
; C3Mod_ViewOffsetTask) and the NMI tasks (C3Mod_OamUploadTask,
; C3Mod_HideSprites, C3Mod_TilesNmiTask, C3Mod_ScrollNmiTask,
; C3Mod_HorizonNmiTask, C3Mod_ClearColumnTask), sets the view (speed 0,
; distance $4C, scale $50, first divisor $28, X -$8C, angle 0, horizon
; $38) and goes on in C3Mod_Prog0RunA or C3Mod_Prog0RunB, picked at
; random by C3Mod_PickRun.
C3Mod_Prog0ScriptA:
    db !C3Op_TaskAdd : dw C3Mod_ViewTask
    db !C3Op_TaskAdd : dw C3Mod_PadDelayTask
    db !C3Op_TaskAdd : dw C3Mod_ScriptTaskA
    db !C3Op_TaskAdd : dw C3Mod_ScriptTaskB
    db !C3Op_TaskAdd : dw C3Mod_TurnTask
    db !C3Op_TaskAdd : dw C3Mod_DrawTask
    db !C3Op_TaskAdd : dw C3Mod_ProjectTask
    db !C3Op_TaskAdd : dw C3Mod_FadeInTask
    db !C3Op_TaskAdd : dw C3Mod_ViewOffsetTask
    db !C3Op_NmiAdd : dw C3Mod_OamUploadTask
    db !C3Op_NmiAdd : dw C3Mod_HideSprites
    db !C3Op_NmiAdd : dw C3Mod_TilesNmiTask
    db !C3Op_NmiAdd : dw C3Mod_ScrollNmiTask
    db !C3Op_NmiAdd : dw C3Mod_HorizonNmiTask
    db !C3Op_NmiAdd : dw C3Mod_ClearColumnTask
    db !C3Op_Set|9 : dw $0000
    db !C3Op_Set|2 : dw $004C
    db !C3Op_Set|0 : dw $0050
    db !C3Op_Set|8 : dw $0028
    db !C3Op_Set|1 : dw -$8C
    db !C3Op_Set|5 : dw $0000
    db !C3Op_Set|6 : dw $0038
    db !C3Op_CallW : dw C3Mod_PickRun

; $7E:3F59 — C3Mod_PickRun (13 bytes, $3F59–$3F65)
; A script routine (opcode $x0, C3Mod_CallW): page $0A00's script goes
; on in C3Mod_Prog0RunA or C3Mod_Prog0RunB, by bit 1 of a random byte
; (C3Mod_TableRandom): C3Script_Ptr = the C3Mod_Prog0Runs entry, which
; is 2 bytes before the script (C3_RunScript adds 2 after the call).
; Callers note: script opcode $F0 at $3F56 (C3Mod_Prog0ScriptA).
; Entry: M=0, X=0 (the 16-bit table index), DP = the script's page
;        (C3Script_Ptr is direct page; $0A00 here), DB = $7E (the table
;        read is absolute; C3_RunScript runs with the module's bank).
; Exit:  M=0, X=0; A = C3Script_Ptr = the entry, X = 0 or 2; Y
;        unchanged.
; Calls: C3Mod_TableRandom.
C3Mod_PickRun:
    JSR C3Mod_TableRandom
    AND.w #!C3_PickRunBit
    TAX
    LDA.w C3Mod_Prog0Runs,X
    STA.b !C3Script_Ptr
    RTS

; $7E:3F66 — C3Mod_Prog0Runs (4 bytes, $3F66–$3F69)
; C3Mod_PickRun's two script entries, each 2 bytes before the script.
C3Mod_Prog0Runs:
    dw C3Mod_Prog0RunA-2, C3Mod_Prog0RunB-2

; $7E:3F6A — C3Mod_Prog0RunA (66 bytes, $3F6A–$3FAB)
; One of the two opening views (page $0A00): distance $D0, scale $50,
; first divisor 8, step mode 1 (C3Mod_Prog0Setup: every other line
; copied), var 12 = 1; 15 times eight frames of a turn (angle + $10)
; with the distance - 1, then divisor + 1 and scale + 1; var 12 = 0,
; eight more frames of it, divisor and scale + 1, step mode 0; then
; adds C3Mod_SteerTask and waits for good (a jump to itself).
C3Mod_Prog0RunA:
    db !C3Op_Set|2 : dw $00D0
    db !C3Op_Set|0 : dw $0050
    db !C3Op_Set|8 : dw $0008
    db !C3Op_Set|11 : dw $0001
    db !C3Op_Set|12 : dw $0001
.l3F79:
    db !C3Op_Add|5 : dw $0010
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|1 : dw $0007, .l3F79             ; 8 passes
    db !C3Op_Add|8 : dw $0001
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Loop|0 : dw $000E, .l3F79                  ; 15 passes
    db !C3Op_Set|12 : dw $0000
.l3F92:
    db !C3Op_Add|5 : dw $0010
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $0007, .l3F92             ; 8 passes
    db !C3Op_Add|8 : dw $0001
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Set|11 : dw $0000
    db !C3Op_TaskAdd : dw C3Mod_SteerTask
.l3FA9:
    db !C3Op_JumpYield : dw .l3FA9

; $7E:3FAC — C3Mod_Prog0RunB (94 bytes, $3FAC–$4009)
; The other opening view (page $0A00): angle $300, distance $10,
; divisor $18, scale $60; 64 frames of the distance + 2; step mode 1,
; var 12 = -1; four 16-frame turns (scale + 2, + 1, - 1, - 2; angle -
; $14, - $C, - $A, - 6; distance - 1 each frame), with var 12 = 0
; after the first; step mode 0, C3Mod_SteerTask added, then waits for
; good.
C3Mod_Prog0RunB:
    db !C3Op_Set|5 : dw $0300
    db !C3Op_Set|2 : dw $0010
    db !C3Op_Set|8 : dw $0018
    db !C3Op_Set|0 : dw $0060
.l3FB8:
    db !C3Op_Add|2 : dw $0002
    db !C3Op_LoopYield|0 : dw $003F, .l3FB8             ; 64 passes
    db !C3Op_Set|11 : dw $0001
    db !C3Op_Set|12 : dw -$1
.l3FC6:
    db !C3Op_Add|0 : dw $0002
    db !C3Op_Add|5 : dw -$14
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $000F, .l3FC6             ; 16 passes
    db !C3Op_Set|12 : dw $0000
.l3FD7:
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Add|5 : dw -$C
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $000F, .l3FD7             ; 16 passes
.l3FE5:
    db !C3Op_Add|0 : dw -$1
    db !C3Op_Add|5 : dw -$A
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $000F, .l3FE5             ; 16 passes
.l3FF3:
    db !C3Op_Add|0 : dw -$2
    db !C3Op_Add|5 : dw -$6
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $000F, .l3FF3             ; 16 passes
    db !C3Op_Set|11 : dw $0000
    db !C3Op_TaskAdd : dw C3Mod_SteerTask
.l4007:
    db !C3Op_JumpYield : dw .l4007

; $7E:400A — C3Mod_Prog0ScriptB (67 bytes, $400A–$404C)
; Page $0B00's first script: C3_ViewY = $18, vars 0 and 6 = $FF; the
; count-down: sound effect $96 (C3_SndSfxA) three times 60 frames
; apart, then effect $97 (Audio_CmdPlaySfx); 20 frames later
; C3_PauseAllowed = 1 (poke), var 13 = 1, sound effect $44, the task
; C3Mod_RaceStepTask added; then waits for good.
C3Mod_Prog0ScriptB:
    db !C3Op_Set|2 : dw $0018
    db !C3Op_Set|0 : dw $00FF
    db !C3Op_Set|6 : dw $00FF
    db !C3Op_Driver : dw !C3_SndSfxA|($96<<8), $0080
.l4018:
    db !C3Op_LoopYield|1 : dw $003B, .l4018             ; 60 passes
    db !C3Op_Driver : dw !C3_SndSfxA|($96<<8), $0080
.l4022:
    db !C3Op_LoopYield|1 : dw $003B, .l4022             ; 60 passes
    db !C3Op_Driver : dw !C3_SndSfxA|($96<<8), $0080
.l402C:
    db !C3Op_LoopYield|1 : dw $003B, .l402C             ; 60 passes
    db !C3Op_Driver : dw !Audio_CmdPlaySfx|($97<<8), $0080
.l4036:
    db !C3Op_LoopYield|1 : dw $0013, .l4036             ; 20 passes
    db !C3Op_Poke8 : dw !C3_PauseAllowed : db 1
    db !C3Op_Set|13 : dw $0001
    db !C3Op_Driver : dw !C3_SndSfxA|($44<<8), $0080
    db !C3Op_TaskAdd : dw C3Mod_RaceStepTask
.l404A:
    db !C3Op_JumpYield : dw .l404A

; $7E:404D — C3Mod_Prog0WipeA (118 bytes, $404D–$40C2)
; Page $0A00's first script with C3_EntryArg bit 6 (a run that ends by
; itself): the tasks (C3Mod_Prog0Start); distance $DE, scale $40,
; divisor $F; starts the kernel's wipe (WinFx_C3EMode = 1 by poke) and
; a frame later adds C3Mod_ExitTask, sets C3_Brightness = 15 and plays
; effect $BA; then the view moves (112 frames of distance - 1, turns of
; angle - 4 a frame, ...) and the wipe goes the other way
; (WinFx_C3EMode = 2, effect $BA again); after 8 more frames of moves
; and a 24-frame wait it ends (opcode $xF: C3_ExitFlag, the module
; leaves).
C3Mod_Prog0WipeA:
    db !C3Op_Call : dw C3Mod_Prog0Start
    db !C3Op_Set|2 : dw $00DE
    db !C3Op_Set|0 : dw $0040
    db !C3Op_Set|8 : dw $000F
    db !C3Op_Poke8 : dw !WinFx_C3EMode : db 1
    db !C3Op_Yield
    db !C3Op_TaskAdd : dw C3Mod_ExitTask
    db !C3Op_Poke8 : dw !C3_Brightness : db 15
    db !C3Op_Driver : dw !C3_SndSfxA|($BA<<8), $0080
.l406A:
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $006F, .l406A             ; 112 passes
.l4072:
    db !C3Op_Add|2 : dw -$1
    db !C3Op_Add|5 : dw -$4
    db !C3Op_LoopYield|0 : dw $002F, .l4072             ; 48 passes
.l407D:
    db !C3Op_Add|5 : dw -$4
    db !C3Op_LoopYield|0 : dw $002F, .l407D             ; 48 passes
.l4085:
    db !C3Op_Add|5 : dw -$4
    db !C3Op_Add|2 : dw $0001
    db !C3Op_LoopYield|0 : dw $001F, .l4085             ; 32 passes
    db !C3Op_Add|8 : dw $0001
.l4093:
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Yield
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Add|0 : dw $0001
    db !C3Op_LoopYield|0 : dw $0033, .l4093             ; 52 passes
    db !C3Op_Add|8 : dw $0001
    db !C3Op_Poke8 : dw !WinFx_C3EMode : db 2
    db !C3Op_Driver : dw !C3_SndSfxA|($BA<<8), $0080
.l40AE:
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Yield
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Add|0 : dw $0001
    db !C3Op_LoopYield|0 : dw $0003, .l40AE             ; 4 passes
.l40BD:
    db !C3Op_LoopYield|1 : dw $0017, .l40BD             ; 24 passes
    db !C3Op_End

; $7E:40C3 — C3Mod_Prog0WipeB (106 bytes, $40C3–$412C)
; As C3Mod_Prog0WipeA, with another flight (distance $40, scale $FF,
; divisor $30; turns of angle + 4 a frame, the scale and the divisor
; going down), the alternate run (C3_StartCount bit 0).
C3Mod_Prog0WipeB:
    db !C3Op_Call : dw C3Mod_Prog0Start
    db !C3Op_Set|2 : dw $0040
    db !C3Op_Set|0 : dw $00FF
    db !C3Op_Set|8 : dw $0030
.l40CF:
    db !C3Op_LoopYield|1 : dw $0007, .l40CF             ; 8 passes
    db !C3Op_Poke8 : dw !WinFx_C3EMode : db 1
    db !C3Op_Yield
    db !C3Op_TaskAdd : dw C3Mod_ExitTask
    db !C3Op_Poke8 : dw !C3_Brightness : db 15
    db !C3Op_Driver : dw !C3_SndSfxA|($BA<<8), $0080
.l40E5:
    db !C3Op_LoopYield|1 : dw $0007, .l40E5             ; 8 passes
.l40EA:
    db !C3Op_Add|0 : dw -$1
    db !C3Op_Add|5 : dw $0004
    db !C3Op_Add|2 : dw $0001
    db !C3Op_LoopYield|1 : dw $0003, .l40EA             ; 4 passes
    db !C3Op_Add|8 : dw -$1
    db !C3Op_Loop|0 : dw $001F, .l40EA                  ; 32 passes
.l4100:
    db !C3Op_Add|2 : dw -$1
    db !C3Op_Add|5 : dw $0004
    db !C3Op_Add|0 : dw -$1
    db !C3Op_LoopYield|0 : dw $003F, .l4100             ; 64 passes
.l410E:
    db !C3Op_LoopYield|1 : dw $0027, .l410E             ; 40 passes
.l4113:
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $005F, .l4113             ; 96 passes
    db !C3Op_Poke8 : dw !WinFx_C3EMode : db 2
    db !C3Op_Driver : dw !C3_SndSfxA|($BA<<8), $0080
.l4124:
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $001F, .l4124             ; 32 passes
    db !C3Op_End

; $7E:412D — C3Mod_Prog0Start (49 bytes, $412D–$415D)
; Called by script opcode $F3 (from C3Mod_Prog0WipeA and
; C3Mod_Prog0WipeB): adds the tasks of C3Mod_Prog0ScriptA, with
; C3Mod_WipeTask in place of C3Mod_FadeInTask and without
; C3Mod_PadDelayTask, and its NMI tasks but C3Mod_ClearColumnTask;
; X speed $11, angle 0, horizon $38; returns (opcode $F4). The $F3's
; return point goes to C3Script_Ret ($30), which is also
; C3_ViewCache's first word: C3Mod_ViewTask then sees a changed scale
; and rebuilds once more (and clears C3_DivisorCache).
C3Mod_Prog0Start:
    db !C3Op_TaskAdd : dw C3Mod_ViewTask
    db !C3Op_TaskAdd : dw C3Mod_ScriptTaskA
    db !C3Op_TaskAdd : dw C3Mod_ScriptTaskB
    db !C3Op_TaskAdd : dw C3Mod_TurnTask
    db !C3Op_TaskAdd : dw C3Mod_DrawTask
    db !C3Op_TaskAdd : dw C3Mod_ProjectTask
    db !C3Op_TaskAdd : dw C3Mod_WipeTask
    db !C3Op_TaskAdd : dw C3Mod_ViewOffsetTask
    db !C3Op_NmiAdd : dw C3Mod_OamUploadTask
    db !C3Op_NmiAdd : dw C3Mod_HideSprites
    db !C3Op_NmiAdd : dw C3Mod_TilesNmiTask
    db !C3Op_NmiAdd : dw C3Mod_ScrollNmiTask
    db !C3Op_NmiAdd : dw C3Mod_HorizonNmiTask
    db !C3Op_Set|9 : dw $0011
    db !C3Op_Set|5 : dw $0000
    db !C3Op_Set|6 : dw $0038
    db !C3Op_Return

; $7E:415E — C3Mod_Prog0WipeScriptB (15 bytes, $415E–$416C)
; Page $0B00's script for the C3_EntryArg bit 6 run: C3_ViewY = $18,
; vars 0 and 6 = $FF, var 13 = 1, then waits for good.
C3Mod_Prog0WipeScriptB:
    db !C3Op_Set|2 : dw $0018
    db !C3Op_Set|0 : dw $00FF
    db !C3Op_Set|6 : dw $00FF
    db !C3Op_Set|13 : dw $0001
.l416A:
    db !C3Op_JumpYield : dw .l416A

; $7E:416D — C3Mod_DriftTask (57 bytes, $416D–$41A5)
; A task: on the two frames in four that have C3_FrameCount bit 1
; clear, moves the view one step towards its rest: the scale (page
; $0A00's var 0) to $A0, the horizon (var 6) to $38, the distance (var
; 2) to $90 (each + 1 or - 1 by the sign of the difference, BMI: right
; while it is below $8000).
; Callers note: a task by replacement: LDX #C3Mod_DriftTask / JMP
;   C3Mod_TaskReplace at $476B (C3Mod_WaitSongEndTask); removed by
;   script opcode $F9 at $41AB (C3Mod_Prog0Finish).
; Entry: a task (C3Mod_RunTasks): M=0, X=0, DP=0 (C3_FrameCount; set to
;        $0A00 here, restored by C3Mod_RunTasks), DB any.
; Exit:  M=0, X=0, DP = $0A00 after a step (else 0); A = the distance
;        (or C3_FrameCount / 4 on the frames it waits); X, Y unchanged.
C3Mod_DriftTask:
    LDA.b !C3_FrameCount
    LSR A
    LSR A
    BCC .step
    RTS
.step:
    LDA.w #!C3_ScriptPageA
    TCD
    LDA.b !C3_ViewScale
    CMP.w #!C3_DriftScale
    BEQ .horizon
    BMI .scale_up
    DEC.b !C3_ViewScale
    BRA .horizon
.scale_up:
    INC.b !C3_ViewScale
.horizon:
    LDA.b !C3_ViewHorizon
    CMP.w #!C3_DriftHorizon
    BEQ .distance
    BMI .horizon_down
    DEC.b !C3_ViewHorizon
    BRA .distance
.horizon_down:
    INC.b !C3_ViewHorizon
.distance:
    LDA.b !C3_ViewDist
    CMP.w #!C3_DriftDist
    BEQ .done
    BMI .closer
    DEC.b !C3_ViewDist
    BRA .done
.closer:
    INC.b !C3_ViewDist
.done:
    RTS

; $7E:41A6 — C3Mod_Prog0Finish (107 bytes, $41A6–$4210)
; Page $0A00's last script, started by C3Mod_WaitSongEndTask: waits 320
; frames, removes C3Mod_DriftTask (opcode $F9), turns (angle + 2 a
; frame) while the distance and the scale go down, waits 112 frames,
; then moves the horizon down and raises the distance and the scale,
; adding C3Mod_FadeOutTask halfway, and ends (opcode $xF: the module
; leaves).
C3Mod_Prog0Finish:
    db !C3Op_LoopYield|1 : dw $013F, C3Mod_Prog0Finish  ; 320 passes
    db !C3Op_TaskRemove : dw C3Mod_DriftTask
.l41AE:
    db !C3Op_Add|5 : dw $0002
    db !C3Op_LoopYield|1 : dw $0006, .l41AE             ; 7 passes
    db !C3Op_Add|5 : dw $0002
    db !C3Op_Add|2 : dw -$1
    db !C3Op_Add|0 : dw -$1
    db !C3Op_LoopYield|0 : dw $001F, .l41AE             ; 32 passes
.l41C4:
    db !C3Op_Add|5 : dw $0002
    db !C3Op_LoopYield|1 : dw $0006, .l41C4             ; 7 passes
    db !C3Op_Add|5 : dw $0002
    db !C3Op_Add|2 : dw -$2
    db !C3Op_Add|0 : dw -$2
    db !C3Op_LoopYield|0 : dw $001F, .l41C4             ; 32 passes
.l41DA:
    db !C3Op_LoopYield|1 : dw $006F, .l41DA             ; 112 passes
.l41DF:
    db !C3Op_Add|6 : dw $0001
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Yield
    db !C3Op_Yield
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Yield
    db !C3Op_LoopYield|0 : dw $0017, .l41DF             ; 24 passes
    db !C3Op_TaskAdd : dw C3Mod_FadeOutTask
.l41F9:
    db !C3Op_Add|6 : dw $0001
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Yield
    db !C3Op_Yield
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Yield
    db !C3Op_LoopYield|0 : dw $0017, .l41F9             ; 24 passes
    db !C3Op_End

; $7E:4211 — C3Mod_Prog0Quit (60 bytes, $4211–$424C)
; Page $0A00's script when the race is lost (stored by
; C3Mod_RaceStepTask at $48A3):
; stops sound effect groups 0 and 1 (C3_SndStopSfx), sets the tempo
; adjustment ($40, $80), waits 32 frames, adds C3Mod_RestoreColumnTask
; (an NMI task) and jumps to .fade: C3Mod_FadeOutTask, 128 frames,
; C3_SndStopAll and the end (opcode $xF). The copy at .copy (the same
; three commands and wait, then .fade) is reached by nothing found.
C3Mod_Prog0Quit:
    db !C3Op_Driver : dw !C3_SndStopSfx|($00<<8), $0000
    db !C3Op_Driver : dw !C3_SndStopSfx|($01<<8), $0000
    db !C3Op_Driver : dw !C3_SndTempoPitch|($40<<8), $0080
.l4220:
    db !C3Op_LoopYield|1 : dw $001F, .l4220             ; 32 passes
    db !C3Op_NmiAdd : dw C3Mod_RestoreColumnTask
    db !C3Op_Jump : dw .fade
.copy:
    db !C3Op_Driver : dw !C3_SndStopSfx|($00<<8), $0000
    db !C3Op_Driver : dw !C3_SndStopSfx|($01<<8), $0000
    db !C3Op_Driver : dw !C3_SndTempoPitch|($40<<8), $0080
.l423A:
    db !C3Op_LoopYield|1 : dw $001F, .l423A             ; 32 passes
.fade:
    db !C3Op_TaskAdd : dw C3Mod_FadeOutTask
.l4242:
    db !C3Op_LoopYield|1 : dw $007F, .l4242             ; 128 passes
    db !C3Op_Driver : dw !C3_SndStopAll|($00<<8), $0000
    db !C3Op_End

; $7E:424D — C3Mod_ExitTask (54 bytes, $424D–$4282)
; A task of the C3_EntryArg bit 6 run: once any button is down (C3_Pad)
; while no wipe runs (WinFx_C3EMode 0), starts the wipe with mode
; .wipe_mode's operand (C3Mod_Prog0 writes 2 there, C3Mod_Prog3 1 at
; $683F),
; plays effect $BA (C3_SndSfxA) by C3Mod_AudioSend unless C3_SongBusy,
; sets C3_ExitTimer = 32 and C3_Unk7F0062 = 0 and hands over to
; C3Mod_ExitCountTask.
; Callers note: a task added by script opcode $FA at $405E
;   (C3Mod_Prog0WipeA), $40D9 (C3Mod_Prog0WipeB) and $68BD
;   (C3Mod_Prog3WipeB).
; Entry: a task: M=0 (8-bit set here), X=0 (the 16-bit pad and timer
;        loads), DP=0 (C3_Pad), DB=$00 (absolute RAM and Audio_Cmd*).
; Exit:  RTS with M=1, X = C3_Pad, A as on entry (no button) or
;        WinFx_C3EMode (a wipe runs); else JMP C3Mod_TaskReplace with X
;        = C3Mod_ExitCountTask.
; Calls: C3Mod_AudioSend.
C3Mod_ExitTask:
    SEP #$20
    LDX.b !C3_Pad
    BEQ .wait
    LDA.w !WinFx_C3EMode
    BNE .wait
.wipe_mode:
    LDA.b #!WinFx_C3EMode2              ; written by C3Mod_Prog0 and C3Mod_Prog3
    STA.w !WinFx_C3EMode
    LDA.w !C3_SongBusy
    BNE .no_sound
    LDX.w #!C3_SfxWipe|(!C3_SfxArg1<<8)
    STX.w !Audio_CmdArg0                ; and Audio_CmdArg1
    LDA.b #!C3_SndSfxA
    STA.w !Audio_CmdId
    JSR C3Mod_AudioSend
.no_sound:
    LDX.w #!C3_ExitFrames
    STX.w !C3_ExitTimer
    LDA.b #0
    STA.l !C3_Unk7F0062
    LDX.w #C3Mod_ExitCountTask
    JMP C3Mod_TaskReplace
.wait:
    RTS

; $7E:4283 — C3Mod_ExitCountTask (8 bytes, $4283–$428A)
; A task: counts C3_ExitTimer down and, when it reaches 0, adds 1 to
; C3_ExitFlag (the module leaves). It is not ended: past 0 the timer
; would wrap, but the module has left by then.
; Callers note: a task by replacement: LDX #C3Mod_ExitCountTask / JMP
;   C3Mod_TaskReplace at $427C (C3Mod_ExitTask).
; Entry: a task: M=0, X=0, DP=0 (C3_ExitFlag), DB=$00.
; Exit:  M=0; A, X, Y unchanged.
C3Mod_ExitCountTask:
    DEC.w !C3_ExitTimer
    BNE .wait
    INC.b !C3_ExitFlag
.wait:
    RTS

; $7E:428B — C3Mod_TurnTask (50 bytes, $428B–$42BC)
; A task: moves the view: C3_ViewX += C3_ViewSpeedX (page $0A00, kept
; to $000-$3FF), then the mode-7 plane's scroll and centre: X =
; C3_ViewX + C3_ViewOffsetX (centre + $7F), Y = C3_ViewY (page $0B00)
; + C3_ViewOffsetY (centre + $E0), for C3Mod_ScrollNmiTask.
; Callers note: a task added by script opcode $FA at $3F20
;   (C3Mod_Prog0ScriptA) and $4136 (C3Mod_Prog0Start).
; Entry: a task: M any (REP #$20 here), X any, DP any (set to $0A00
;        here, restored by C3Mod_RunTasks), DB=$00 (absolute RAM).
; Exit:  M=0, DP = $0A00; A = C3_PlaneCentreY; X, Y unchanged.
C3Mod_TurnTask:
    REP #$20
    PEA.w !C3_ScriptPageA
    PLD
    LDA.b !C3_ViewX
    CLC
    ADC.b !C3_ViewSpeedX
    AND.w #!C3_PlaneMask
    STA.b !C3_ViewX
    LDA.b !C3_ViewX
    CLC
    ADC.w !C3_ViewOffsetX
    STA.w !C3_PlaneScrollX
    CLC
    ADC.w #!C3_PlaneCentreDX
    STA.w !C3_PlaneCentreX
    LDA.w !C3_ScriptPageB+!C3_ViewY
    CLC
    ADC.w !C3_ViewOffsetY
    STA.w !C3_PlaneScrollY
    CLC
    ADC.w #!C3_PlaneCentreDY
    STA.w !C3_PlaneCentreY
    RTS

; $7E:42BD — C3Mod_PadDelayTask (17 bytes, $42BD–$42CD)
; A task: rotates the words C3_Pad, C3_PadPrev and C3_PadHeld (C3_Pad
; gets C3_PadPrev, C3_PadPrev gets C3_PadHeld, C3_PadHeld gets C3_Pad,
; through C3_TmpF0): as C3_ReadPad rewrites C3_Pad each frame before
; the tasks run, C3_PadHeld is this frame's pad and C3_PadPrev the
; last frame's.
; Callers note: a task added by script opcode $FA at $3F17
;   (C3Mod_Prog0ScriptA).
; Entry: a task: M=0, X any, DP=0 (the pad words), DB any.
; Exit:  M=0; A = C3_PadHeld (the pad); X, Y unchanged.
C3Mod_PadDelayTask:
    LDA.b !C3_Pad
    STA.b !C3_TmpF0
    LDA.b !C3_PadPrev
    STA.b !C3_Pad
    LDA.b !C3_PadHeld
    STA.b !C3_PadPrev
    LDA.b !C3_TmpF0
    STA.b !C3_PadHeld
    RTS

; $7E:42CE — C3Mod_ViewTask (59 bytes, $42CE–$4308)
; A task: rebuilds the mode-7 tables (JMP C3Mod_BuildM7Tables, with
; C3Mod_Prog0Setup written over its setup call) when the view changed:
; page $0A00's scale, angle, horizon, first divisor or step mode
; differs from its copy in C3_ViewCache (5 words). The copies from the
; first that differs on are updated (they enter at that one's store);
; a new scale also clears C3_DivisorCache (C3Mod_ClearDivisorCache).
; Callers note: a task added by script opcode $FA at $3F14
;   (C3Mod_Prog0ScriptA) and $412D (C3Mod_Prog0Start).
; Entry: a task: M=0, X=0 (C3Mod_BuildM7Tables'), DP any (set to $0A00
;        here, restored by C3Mod_RunTasks), DB=$00 (a task's: the STZ
;        before C3Mod_ClearDivisorCache's MVN is absolute, so DB must map
;        low WRAM; C3Mod_BuildM7Tables sets its own).
; Exit:  unchanged: RTS with A = the step mode, DP = $0A00; else as
;        C3Mod_BuildM7Tables leaves them (M=0, X=0, DP = DP_CPU, DB =
;        $7E).
; Calls: C3Mod_ClearDivisorCache, C3Mod_BuildM7Tables (JMP).
C3Mod_ViewTask:
    LDA.w #!C3_ScriptPageA
    TCD
    LDA.b !C3_ViewScale
    CMP.b !C3_ViewCache
    BNE .scale
    LDA.b !C3_ViewAngle
    CMP.b !C3_ViewCache+2
    BNE .angle
    LDA.b !C3_ViewHorizon
    CMP.b !C3_ViewCache+4
    BNE .horizon
    LDA.b !C3_ViewFirstDiv
    CMP.b !C3_ViewCache+6
    BNE .first_div
    LDA.b !C3_ViewStepMode
    CMP.b !C3_ViewCache+8
    BNE .step_mode
    RTS
.scale:
    STA.b !C3_ViewCache
    JSR C3Mod_ClearDivisorCache
    LDA.b !C3_ViewAngle
.angle:
    STA.b !C3_ViewCache+2
    LDA.b !C3_ViewHorizon
.horizon:
    STA.b !C3_ViewCache+4
    LDA.b !C3_ViewFirstDiv
.first_div:
    STA.b !C3_ViewCache+6
    LDA.b !C3_ViewStepMode
.step_mode:
    STA.b !C3_ViewCache+8
    JMP C3Mod_BuildM7Tables

; $7E:4309 — C3Mod_ClearDivisorCache (16 bytes, $4309–$4318)
; Zeroes the 256 bytes of C3_DivisorCache ($1446-$1545: a word stored, then
; an overlapping MVN in bank $00).
; Callers note: C3Mod_ViewTask ($42F3) and C3Mod_Prog0Vars ($4640,
;   JMP).
; Entry: M=0, X=0 (MVN's 16-bit X and Y), DP any, DB any (set to $00
;        by the MVN; the STZ before it is absolute, so DB must be $00
;        or $7E, or another bank that maps low WRAM: $00 at both
;        calls).
; Exit:  M=0, X=0, DB = $00; A = $FFFF; X = $1545, Y = $1546.
C3Mod_ClearDivisorCache:
    STZ.w !C3_DivisorCache
    LDX.w #!C3_DivisorCache
    LDY.w #!C3_DivisorCache+1
    LDA.w #!C3_DivisorCacheBytes-2
    MVN $00,$00                         ; lint-ok: MVN operands are bank bytes (bank $00)
    RTS

; $7E:4319 — C3Mod_SideMinusPads (16 bytes, $4319–$4328)
; The D-pad button (JOY1's high byte as a word) that steers the bike's
; side down (C3_PadSideMinus, read by C3Mod_RaceStepTask), by eighth
; of a turn of the view's angle (C3Mod_SteerTask's index: (angle +
; $40) / 64, even), as the track turns on the screen: Up, Up+Right,
; Right, Down+Right, Down, Down+Left, Left, Up+Left; C3Mod_SteerTask
; and C3Mod_Prog0Vars copy the entry.
C3Mod_SideMinusPads:
    dw !C3_PadUp, !C3_PadUp|!C3_PadRight, !C3_PadRight, !C3_PadDown|!C3_PadRight
    dw !C3_PadDown, !C3_PadDown|!C3_PadLeft, !C3_PadLeft, !C3_PadUp|!C3_PadLeft

; $7E:4329 — C3Mod_SidePlusPads (16 bytes, $4329–$4338)
; The opposite directions, for C3_PadSidePlus (the side up).
C3Mod_SidePlusPads:
    dw !C3_PadDown, !C3_PadDown|!C3_PadLeft, !C3_PadLeft, !C3_PadUp|!C3_PadLeft
    dw !C3_PadUp, !C3_PadUp|!C3_PadRight, !C3_PadRight, !C3_PadDown|!C3_PadRight

; $7E:4339 — C3Mod_SteerTask (127 bytes, $4339–$43B7)
; A task of the view, on page $0A00:
;   - program 9 only (C3_Prog9): the L and R buttons (C3_PadHeld) turn
;     the view: C3_ViewLeanR / C3_ViewLeanL count up while R / L is
;     held (to 12) and down otherwise (C3Mod_LeanR, C3Mod_LeanL), and
;     the angle moves by C3_ViewLeanR / 4 - C3_ViewLeanL / 4 a frame;
;   - C3_PadSideMinus / C3_PadSidePlus = the C3Mod_SideMinusPads /
;     C3Mod_SidePlusPads entry for the angle's eighth of a turn;
;   - on odd frames (C3_FrameCount bit 0), X held brings the view up
;     (distance, scale and horizon + 1, while the scale is below $7F),
;     else A held takes it down (- 1 each, while the scale is $60 or
;     more).
; Callers note: a task added by script opcode $FA at $3FA6
;   (C3Mod_Prog0RunA) and $4004 (C3Mod_Prog0RunB); removed by LDX
;   #C3Mod_SteerTask / JSR C3Mod_TaskRemove at $482B (C3Mod_RaceFinish)
;   and $4876 (C3Mod_RaceStepTask).
; Entry: a task (C3Mod_RunTasks): M=0, X=0 (16-bit counters), DP any
;        (set to $0A00 here, restored by C3Mod_RunTasks), DB=$00
;        (C3_Prog9, C3_PadHeld and C3_FrameCount are read absolute; the
;        16-bit LDA of the byte C3_Prog9 also reads $45, 0 from
;        C3Mod_Init's clear).
; Exit:  M=0, X=0, DP = $0A00; A, X changed (X = the pad table index);
;        Y unchanged; C3_TmpF0/F2 of page $0A00 changed in program 9.
; Calls: C3Mod_LeanR, C3Mod_LeanL.
C3Mod_SteerTask:
    LDA.w #!C3_ScriptPageA
    TCD
    LDA.w !C3_Prog9
    BEQ .pads
    LDA.w !C3_PadHeld
    JSR C3Mod_LeanR
    JSR C3Mod_LeanL
    LDA.b !C3_ViewLeanR
    LSR A
    LSR A
    STA.b !C3_TmpF0
    LDA.b !C3_ViewLeanL
    LSR A
    LSR A
    STA.b !C3_TmpF2
    LDA.b !C3_ViewAngle
    CLC
    ADC.b !C3_TmpF0
    SEC
    SBC.b !C3_TmpF2
    STA.b !C3_ViewAngle
.pads:
    LDA.w !C3_ScriptPageA+!C3_ViewAngle
    CLC
    ADC.w #!C3_EighthTurn/2
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    AND.w #!C3_PadTableMask
    TAX
    LDA.l C3Mod_SideMinusPads,X
    STA.w !C3_PadSideMinus
    LDA.l C3Mod_SidePlusPads,X
    STA.w !C3_PadSidePlus
    LDA.w !C3_PadHeld
    BIT.w #!C3_PadX
    BEQ .not_up
    LDA.w !C3_FrameCount
    LSR A
    BCC .not_up
    LDA.b !C3_ViewScale
    CMP.w #!C3_ViewScaleMax
    BPL .done
    INC.b !C3_ViewDist
    INC.b !C3_ViewScale
    INC.b !C3_ViewHorizon
    RTS
.not_up:
    LDA.w !C3_PadHeld
    BIT.w #!C3_PadA
    BEQ .done
    LDA.w !C3_FrameCount
    LSR A
    BCC .done
    LDA.b !C3_ViewScale
    CMP.w #!C3_ViewScaleMin
    BMI .done
    DEC.b !C3_ViewDist
    DEC.b !C3_ViewScale
    DEC.b !C3_ViewHorizon
.done:
    RTS

; $7E:43B8 — C3Mod_LeanR (29 bytes, $43B8–$43D4)
; C3_ViewLeanR + 1 (up to C3_LeanMax) while the R button is in A, else
; - 1 (down to 0).
; Callers note: C3Mod_SteerTask ($4345).
; Entry: M=0, X=0 (the 16-bit count), DP = page $0A00 (C3_ViewLeanR),
;        DB any; A = the pad.
; Exit:  M=0, X=0; A unchanged (saved), X = C3_ViewLeanR; Y unchanged.
C3Mod_LeanR:
    PHA
    LDX.b !C3_ViewLeanR
    BIT.w #!C3_PadR
    BEQ .release
    INX
    CPX.w #!C3_LeanMax
    BMI .store
    LDX.w #!C3_LeanMax
    BRA .store
.release:
    CPX.w #0
    BEQ .store
    DEX
.store:
    STX.b !C3_ViewLeanR
    PLA
    RTS

; $7E:43D5 — C3Mod_LeanL (29 bytes, $43D5–$43F1)
; The same for C3_ViewLeanL and the L button.
; Callers note: C3Mod_SteerTask ($4348).
; Entry: M=0, X=0, DP = page $0A00 (C3_ViewLeanL), DB any; A = the pad.
; Exit:  M=0, X=0; A unchanged (saved), X = C3_ViewLeanL; Y unchanged.
C3Mod_LeanL:
    PHA
    LDX.b !C3_ViewLeanL
    BIT.w #!C3_PadL
    BEQ .release
    INX
    CPX.w #!C3_LeanMax
    BMI .store
    LDX.w #!C3_LeanMax
    BRA .store
.release:
    CPX.w #0
    BEQ .store
    DEX
.store:
    STX.b !C3_ViewLeanL
    PLA
    RTS

; $7E:43F2 — C3Mod_ScrollNmiTask (85 bytes, $43F2–$4446)
; An NMI task: writes the mode-7 centre (M7X = C3_PlaneCentreX, M7Y =
; C3_PlaneCentreY), BG2HOFS = C3_Bg2ScrollX, BG3HOFS / BG3VOFS =
; C3_Bg3ScrollX / Y (each register low byte, then high byte), and
; copies the sky's and the plane's scroll (C3_SkyScrollX/Y,
; C3_PlaneScrollX/Y) to C3_SkyScrollHdma / C3_PlaneScrollHdma, which
; C3Mod_ScrollHdma's lines send to BG1HOFS/BG1VOFS this frame.
; Callers note: an NMI task added by script opcode $F8 at $3F38
;   (C3Mod_Prog0ScriptA) and $414E (C3Mod_Prog0Start).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X=0 (the word copies),
;        DP any, DB=$00 (absolute registers and RAM).
; Exit:  M=1, X=0; A = C3_Bg3ScrollY's high byte, X = C3_PlaneScrollY;
;        Y unchanged.
C3Mod_ScrollNmiTask:
    LDA.w !C3_PlaneCentreX
    STA.w M7X
    LDA.w !C3_PlaneCentreX+1
    STA.w M7X
    LDA.w !C3_PlaneCentreY
    STA.w M7Y
    LDA.w !C3_PlaneCentreY+1
    STA.w M7Y
    LDA.w !C3_Bg2ScrollX
    STA.w BG2HOFS
    LDA.w !C3_Bg2ScrollX+1
    STA.w BG2HOFS
    LDA.w !C3_Bg3ScrollX
    STA.w BG3HOFS
    LDA.w !C3_Bg3ScrollX+1
    STA.w BG3HOFS
    LDA.w !C3_Bg3ScrollY
    STA.w BG3VOFS
    LDA.w !C3_Bg3ScrollY+1
    STA.w BG3VOFS
    LDX.w !C3_SkyScrollX
    STX.w !C3_SkyScrollHdma
    LDX.w !C3_PlaneScrollX
    STX.w !C3_PlaneScrollHdma
    LDX.w !C3_SkyScrollY
    STX.w !C3_SkyScrollHdma+2
    LDX.w !C3_PlaneScrollY
    STX.w !C3_PlaneScrollHdma+2
    RTS

; $7E:4447 — C3Mod_ViewOffsetTask (85 bytes, $4447–$449B)
; A task: from page $0A00's view, C3_ViewOffsetY = -cos(angle) x
; distance / 256 (C3Mod_Cosine's value, which is -cos) and
; C3_ViewOffsetX = -sin(angle) x distance / 256 (C3Mod_Sine's)
; (C3Mod_MulSigned16's product bits 8-23, in page $0A00's C3Math_*),
; which C3Mod_TurnTask adds to the plane's position; the sky's vertical
; scroll C3_SkyScrollY = $17 - the horizon and C3_Bg3ScrollY = $15 -
; it; the sky's horizontal scroll C3_SkyScrollX = - the angle, with
; C3_Bg3ScrollX = it / 2 and C3_Bg2ScrollX = it / 4 (LSR of the
; negated word: right modulo the BG's 1,024 pixels).
; Callers note: a task added by script opcode $FA at $3F2C
;   (C3Mod_Prog0ScriptA) and $4142 (C3Mod_Prog0Start).
; Entry: a task: M any (REP #$20 here), X=0 (C3Mod_MulSigned16's), DP
;        any (set to $0A00 here), DB=$00 (absolute RAM).
; Exit:  M=0, X=0, DP = $0A00; A = C3_Bg2ScrollX; X = the angle AND
;        C3_AngleMask (C3Mod_Sine's; C3Mod_MulSigned16 keeps X); Y
;        unchanged; page $0A00's C3Math_* changed.
; Calls: C3Mod_Cosine, C3Mod_Sine, C3Mod_MulSigned16.
C3Mod_ViewOffsetTask:
    REP #$20
    LDA.w #!C3_ScriptPageA
    TCD
    LDA.b !C3_ViewAngle
    JSR C3Mod_Cosine
    STA.b !C3Math_A
    LDA.b !C3_ViewDist
    STA.b !C3Math_B
    JSR C3Mod_MulSigned16
    LDA.b !C3Math_Lo+1                  ; product / 256
    STA.w !C3_ViewOffsetY
    LDA.b !C3_ViewAngle
    JSR C3Mod_Sine
    STA.b !C3Math_A
    LDA.b !C3_ViewDist
    STA.b !C3Math_B
    JSR C3Mod_MulSigned16
    LDA.b !C3Math_Lo+1
    STA.w !C3_ViewOffsetX
    LDA.b !C3_ViewHorizon
    EOR.w #!Eng_Invert16
    INC A
    CLC
    ADC.w #!C3_SkyTopY
    STA.w !C3_SkyScrollY
    DEC A
    DEC A
    STA.w !C3_Bg3ScrollY
    LDA.w #0
    CLC
    ADC.w !C3_ScriptPageA+!C3_ViewAngle
    EOR.w #!Eng_Invert16
    INC A
    STA.w !C3_SkyScrollX
    LSR A
    STA.w !C3_Bg3ScrollX
    LSR A
    STA.w !C3_Bg2ScrollX
    RTS

; $7E:449C — C3Mod_SkyNmiTask (50 bytes, $449C–$44CD)
; An NMI task (once the race is lost): the sky's horizontal scroll from
; the pack's distance (C3_PackDist's bytes 1-2 / 4: the distance /
; 1024) and C3_ViewX / 2: C3_TmpF0 = -(C3_ViewX / 2 + the distance /
; 1024 + $88 + the carries of the shifts), C3_SkyScrollX = it +
; C3_Unk143E,
; C3_Bg2ScrollX = C3_SkyScrollX / 4 and C3_Bg3ScrollX = C3_SkyScrollX
; x 3/8 (/ 4 + / 8, plus the carry of the shift). Quirk: no CLC before
; the ADCs: C3_ViewX's shifted-out bit 0 is added (and the first ADC's
; carry-out goes into the + $88), and so is the bit the last LSR of
; C3_SkyScrollX shifts out; the bits C3_PackDist's LSRs shift out are
; lost (the STA in between).
; Callers note: an NMI task added by LDX #C3Mod_SkyNmiTask / JSR
;   C3Mod_NmiTaskAdd at $4894 (C3Mod_RaceStepTask, when the race is
;   lost).
; Entry: an NMI task: M any (REP #$20 here), X any, DP=0 (C3_TmpF0),
;        DB=$00 (absolute RAM).
; Exit:  M=0; A = C3_Bg3ScrollX; X, Y unchanged; C3_TmpF0 changed.
C3Mod_SkyNmiTask:
    REP #$20
    LDA.w !C3_PackDist+1
    LSR A
    LSR A
    STA.b !C3_TmpF0
    LDA.w !C3_ScriptPageA+!C3_ViewX
    LSR A
    ADC.b !C3_TmpF0
    ADC.w #!C3_SkyBaseX
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C3_TmpF0
    CLC
    ADC.w !C3_Unk143E
    STA.w !C3_SkyScrollX
    LSR A
    LSR A
    STA.w !C3_Bg2ScrollX
    LDA.w !C3_SkyScrollX
    LSR A
    LSR A
    STA.b !C3_TmpF0
    LSR A
    ADC.b !C3_TmpF0
    STA.w !C3_Bg3ScrollX
    RTS

; $7E:44CE — C3Mod_CountDownTask (48 bytes, $44CE–$44FD)
; A task: every fourth frame (C3_FrameCount bits 0-1 clear), takes
; 2000, 200, 20 or 2 off C3_Score (the first that fits, tried from
; the largest); when none fits (below 2) it ends itself
; (C3Mod_TaskEnd), C3_Score left as it is.
; Callers note: a task added by LDX #C3Mod_CountDownTask / JSR
;   C3Mod_TaskAdd at $489A (C3Mod_RaceStepTask, when the race is
;   lost).
; Entry: a task: M=0, X=0 (C3Mod_TaskEnd's), DP=0 (C3_FrameCount and
;        C3_Score are direct page), DB any.
; Exit:  RTS with A = C3_Score (after a step) or C3_FrameCount AND 3;
;        at the end JMP C3Mod_TaskEnd with A = C3_Score - 2 (wrapped
;        below 0).
C3Mod_CountDownTask:
    LDA.b !C3_FrameCount
    AND.w #!C3_CountDownEvery-1
    BNE .wait
    LDA.b !C3_Score
    SEC
    SBC.w #!C3_Dec1000*2
    BCS .store
    ADC.w #!C3_Dec1000*2
    SEC
    SBC.w #!C3_Dec100*2
    BCS .store
    ADC.w #!C3_Dec100*2
    SEC
    SBC.w #!C3_Dec10*2
    BCS .store
    ADC.w #!C3_Dec10*2
    SEC
    SBC.w #2
    BCS .store
    JMP C3Mod_TaskEnd
.store:
    STA.b !C3_Score
.wait:
    RTS

; $7E:44FE — C3Mod_HorizonNmiTask (33 bytes, $44FE–$451E)
; An NMI task: splits the horizon (page $0A00's C3_ViewHorizon, its low
; byte) into the line counts of the first two entries of
; C3Mod_ModeHdma, C3Mod_MathHdma and C3Mod_ScrollHdma: half of it, and
; half plus the bit shifted out (so the two add up to the horizon: the
; sky's lines in BG mode 1, the plane below in mode 7), then goes on
; at C3Mod_LampUpload. Quirk: a horizon of 0 or 1 gives a first count of
; 0, which ends the tables there.
; Callers note: an NMI task added by script opcode $F8 at $3F3B
;   (C3Mod_Prog0ScriptA) and $4151 (C3Mod_Prog0Start).
; Entry: an NMI task: M=1, X=0 (C3Mod_LampUpload's 16-bit loads), DP
;        any, DB=$00 (C3_ViewHorizon is read absolute; the stores are
;        long).
; Exit:  as C3Mod_LampUpload leaves them (JMP).
C3Mod_HorizonNmiTask:
    LDA.w !C3_ScriptPageA+!C3_ViewHorizon
    LSR A
    STA.l C3Mod_ModeHdma
    STA.l C3Mod_MathHdma
    STA.l C3Mod_ScrollHdma
    ADC.b #0
    STA.l C3Mod_ModeHdma+3
    STA.l C3Mod_MathHdma+3
    STA.l C3Mod_ScrollHdma+3
    JMP C3Mod_LampUpload

; $7E:451F — C3Mod_ModeHdma (12 bytes, $451F–$452A)
; Indirect HDMA table for BGMODE (C3Mod_Prog0Hdma channel 5): the
; horizon's lines (two entries, counts written by
; C3Mod_HorizonNmiTask) from .mode1, then one line from .mode7 (held
; to the bottom), then the end; .mode1 / .mode7 are the values, BG
; mode 1 and 7, which C3Mod_Prog10Mode and C3Mod_Prog10ModeStrip read
; too.
C3Mod_ModeHdma:
    db 0 : dw .mode1
    db 0 : dw .mode1
    db 1 : dw .mode7
    db 0
.mode1:
    db !C3_BgMode1
.mode7:
    db !BGMODE_Mode7

; $7E:452B — C3Mod_MathHdma (55 bytes, $452B–$4561)
; Indirect HDMA table for CGADSUB / COLDATA (channel 4, two registers):
; the horizon's lines from C3Mod_MathValues (.sky), then 15 entries of
; two lines from .fade + 34 on (one pair each, 30 lines), then one line
; from C3Mod_MathValues' first pair (held to the bottom), then the end.
; The HDMA record at $9008 (DMAP $41 to CGADSUB, in C3Mod_Prog10Hdma's
; .fill) points here too (its address at $900A), and
; C3Mod_Prog10SplitNmi ($9090, $90A2) writes the first and second
; counts ($452B, $452E), as C3Mod_HorizonNmiTask does ($4506, $4515).
C3Mod_MathHdma:
    db 0 : dw C3Mod_MathValues_sky
    db 0 : dw C3Mod_MathValues_sky
    db 2 : dw C3Mod_MathValues_fade+34
    db 2 : dw C3Mod_MathValues_fade+36
    db 2 : dw C3Mod_MathValues_fade+38
    db 2 : dw C3Mod_MathValues_fade+40
    db 2 : dw C3Mod_MathValues_fade+42
    db 2 : dw C3Mod_MathValues_fade+44
    db 2 : dw C3Mod_MathValues_fade+46
    db 2 : dw C3Mod_MathValues_fade+48
    db 2 : dw C3Mod_MathValues_fade+50
    db 2 : dw C3Mod_MathValues_fade+52
    db 2 : dw C3Mod_MathValues_fade+54
    db 2 : dw C3Mod_MathValues_fade+56
    db 2 : dw C3Mod_MathValues_fade+58
    db 2 : dw C3Mod_MathValues_fade+60
    db 2 : dw C3Mod_MathValues_fade+62
    db 1 : dw C3Mod_MathValues
    db 0

; $7E:4562 — C3Mod_MathValues (68 bytes, $4562–$45A5)
; CGADSUB / COLDATA pairs for C3Mod_MathHdma: $50 / black at the start
; (half colour math on the sprites: the bottom of the screen;
; C3Mod_Prog10Turn writes $05 over that CGADSUB byte at $87A6), .sky: $42 / black (half on BG2),
; .fade: 32 pairs of $91
; (subtract, on BG1 and the sprites) with all three colours at 31 down
; to 0; C3Mod_MathHdma uses the last 15 (14 down to 0) under the
; horizon. .sky's COLDATA byte ($E0) is also C3Mod_Prog1's fixed DMA
; source for OAM's low table (every sprite byte $E0), and the black of
; program 6's COLDATA tables (C3Mod_Prog6ColourA / ColourB, $4565).
C3Mod_MathValues:
    db !C3_MathTop, !COLDATA_AllZero
.sky:
    db !C3_MathSky, !COLDATA_AllZero
.fade:
    db !C3_MathFade, !COLDATA_AllZero|31, !C3_MathFade, !COLDATA_AllZero|30
    db !C3_MathFade, !COLDATA_AllZero|29, !C3_MathFade, !COLDATA_AllZero|28
    db !C3_MathFade, !COLDATA_AllZero|27, !C3_MathFade, !COLDATA_AllZero|26
    db !C3_MathFade, !COLDATA_AllZero|25, !C3_MathFade, !COLDATA_AllZero|24
    db !C3_MathFade, !COLDATA_AllZero|23, !C3_MathFade, !COLDATA_AllZero|22
    db !C3_MathFade, !COLDATA_AllZero|21, !C3_MathFade, !COLDATA_AllZero|20
    db !C3_MathFade, !COLDATA_AllZero|19, !C3_MathFade, !COLDATA_AllZero|18
    db !C3_MathFade, !COLDATA_AllZero|17, !C3_MathFade, !COLDATA_AllZero|16
    db !C3_MathFade, !COLDATA_AllZero|15, !C3_MathFade, !COLDATA_AllZero|14
    db !C3_MathFade, !COLDATA_AllZero|13, !C3_MathFade, !COLDATA_AllZero|12
    db !C3_MathFade, !COLDATA_AllZero|11, !C3_MathFade, !COLDATA_AllZero|10
    db !C3_MathFade, !COLDATA_AllZero|9, !C3_MathFade, !COLDATA_AllZero|8
    db !C3_MathFade, !COLDATA_AllZero|7, !C3_MathFade, !COLDATA_AllZero|6
    db !C3_MathFade, !COLDATA_AllZero|5, !C3_MathFade, !COLDATA_AllZero|4
    db !C3_MathFade, !COLDATA_AllZero|3, !C3_MathFade, !COLDATA_AllZero|2
    db !C3_MathFade, !COLDATA_AllZero|1, !C3_MathFade, !COLDATA_AllZero

; $7E:45A6 — C3Mod_ScrollHdma (10 bytes, $45A6–$45AF)
; Indirect HDMA table for BG1HOFS / BG1VOFS (channel 3, two registers
; twice): the horizon's lines from C3_SkyScrollHdma (the sky), then one
; line from C3_PlaneScrollHdma (the plane, held), then the end.
C3Mod_ScrollHdma:
    db 0 : dw !C3_SkyScrollHdma
    db 0 : dw !C3_SkyScrollHdma
    db 1 : dw !C3_PlaneScrollHdma
    db 0

; $7E:45B0 — C3Mod_Prog0Setup (38 bytes, $45B0–$45D5)
; C3Mod_BuildM7Tables' setup routine for program 0 (C3Mod_Prog0 writes
; it over the JSR operand at $35FD): the horizon (page $0A00's
; C3_ViewHorizon, made at least 1 and stored back) x 4 as the first
; line's offset Y, C3_ViewFirstDiv as the first divisor X; the step at
; $3634: C3Mod_M7StepBranches' .copy_line BRA when C3_ViewStepMode is
; set (each line after the first copies the one before: half the
; vertical detail), else NOP / INX.
; Callers note: the JSR at $35FC (C3Mod_BuildM7Tables' .setup, its
;   operand written at $3CDE by C3Mod_Prog0).
; Entry: M=0, X=0, DP = page $0A00 (C3Mod_BuildM7Tables' DP), DB any
;        (the code stores are long).
; Exit:  M=0, X=0; Y = the horizon x 4, X = C3_ViewFirstDiv; A = the
;        step written.
C3Mod_Prog0Setup:
    LDA.b !C3_ViewHorizon
    CMP.w #1
    BCS .horizon_ok
    LDA.w #1
    STA.b !C3_ViewHorizon
.horizon_ok:
    ASL A
    ASL A
    TAY
    LDX.b !C3_ViewFirstDiv
    LDA.b !C3_ViewStepMode
    BEQ .every_line
    LDA.l C3Mod_M7StepBranches+6        ; BRA .copy_line
    STA.l C3Mod_BuildM7Tables_step
    RTS
.every_line:
    LDA.w #!Op_NOP|(!Op_INX<<8)
    STA.l C3Mod_BuildM7Tables_step
    RTS

; $7E:45D6 — C3Mod_Prog0Vars (109 bytes, $45D6–$4642)
; Program 0's race variables (called by C3Mod_Prog0): program 9
; (C3_Prog9) writes $D8 over the low byte of the LDA #$00B8 operands
; at $4F74 and $50DA (they load $00D8) and into sprite-list data: $D8
; and $E8 into the X bytes at $53A0 and $53A4, 6 and 1 into the counts
; at $5395 and $53AE (C3Mod_HudSprites and C3Mod_HudSmall, the lists
; C3Mod_DrawHud passes by LDA #$5395 at $514B and LDA #$53AE at
; $5152); program 0 sets C3_BoostTimer = $80 and C3_BoostsLeft = 3.
; Then the words: C3_BikeTopSpeed = C3_BikeTopBehind = $4000,
; C3_RivalTopSpeed = $3000, C3_RivalTopAhead = $5000, C3_BikeSteer =
; 0, C3_BikeSide = $6000, C3_RivalSide = $2000, C3_BumpLast = $20,
; C3_ColumnCleared = C3_BoostHeld = 1, C3_Unk1444 = 0,
; C3_PadSideMinus / C3_PadSidePlus = the angle-0 entries (Up / Down),
; and C3_DivisorCache cleared (JMP C3Mod_ClearDivisorCache).
; Callers note: C3Mod_Prog0 ($3C51).
; Entry: M=1, X=0, DP=0, DB=$00 (absolute RAM; the code stores are
;        long).
; Exit:  M=0 (REP #$20: CALL_EXITS in tools/c3module.py), X=0, DB =
;        $00; as C3Mod_ClearDivisorCache leaves them (A = $FFFF, X = $1545,
;        Y = $1546).
; Calls: C3Mod_ClearDivisorCache (JMP).
C3Mod_Prog0Vars:
    LDA.b !C3_Prog9
    BEQ .prog0
    LDA.b #!C3_Prog9Unk53A0
    STA.l C3Mod_HudSprites+11
    STA.l C3Mod_DrawTask_bar+1
    STA.l C3Mod_MarkerX_base+1
    LDA.b #!C3_Prog9Unk53A4
    STA.l C3Mod_HudSprites+15
    LDA.b #!C3_Prog9Unk5395
    STA.l C3Mod_HudSprites
    LDA.b #!C3_Prog9Unk53AE
    STA.l C3Mod_HudSmall
    BRA .both
.prog0:
    LDA.b #!C3_BoostTimerStart
    STA.b !C3_BoostTimer
    LDA.b #!C3_BoostsStart
    STA.b !C3_BoostsLeft
.both:
    REP #$20
    LDA.w #!C3_BikeTopStart
    STA.b !C3_BikeTopSpeed
    STA.b !C3_BikeTopBehind
    LDA.w #!C3_RivalTopStart
    STA.b !C3_RivalTopSpeed
    LDA.w #!C3_RivalAheadStart
    STA.b !C3_RivalTopAhead
    STZ.b !C3_BikeSteer
    LDA.w #!C3_BikeSideStart
    STA.b !C3_BikeSide
    LDA.w #!C3_RivalSideStart
    STA.b !C3_RivalSide
    LDA.w #!C3_BumpLastStart
    STA.b !C3_BumpLast
    LDA.w #1
    STA.b !C3_ColumnCleared
    STA.b !C3_BoostHeld
    STZ.w !C3_Unk1444
    LDA.l C3Mod_SideMinusPads
    STA.w !C3_PadSideMinus
    LDA.l C3Mod_SidePlusPads
    STA.w !C3_PadSidePlus
    JMP C3Mod_ClearDivisorCache

; $7E:4643 — C3Mod_ClearColumnTask (52 bytes with C3Mod_RestoreColumnTask, $4643–$4676)
; NMI tasks that run once: DMA channel 7 writes 19 bytes to VRAM's low
; bytes from word $0B00 on, 128 words apart (VMAIN = +128 after the
; low byte): the column of the mode-7 map C3Mod_Prog0 saved, from
; GfxRom_D2's first bytes (zeros: the cells cleared) or, at
; C3Mod_RestoreColumnTask ($464D), from C3_MapColumnSave (put back);
; then C3Mod_NmiTaskEnd. Quirk: C3Mod_Prog0 saved 20 bytes, 19 are
; written back.
; Callers note: an NMI task added by script opcode $F8 at $3F3E
;   (C3Mod_Prog0ScriptA) and by LDX #C3Mod_ClearColumnTask / JSR
;   C3Mod_NmiTaskAdd at $48D4 (C3Mod_RaceStepTask).
;   C3Mod_RestoreColumnTask: added by script opcode $F8 at $4225
;   (C3Mod_Prog0Quit) and by LDX #C3Mod_RestoreColumnTask / JSR
;   C3Mod_NmiTaskAdd at $469E (C3Mod_RaceTask) and $48BA
;   (C3Mod_RaceStepTask).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X=0 (the 16-bit register
;        pairs; C3Mod_NmiTaskEnd's PLX), DP and DB as it ran them (DB =
;        $00: absolute registers).
; Exit:  JMP C3Mod_NmiTaskEnd with A = MDMAEN_Ch7, X =
;        C3_MapColumnBytes - 1; VMADD past the column.
C3Mod_ClearColumnTask:
    LDX.w #!GfxRom_D2&$FFFF
    STX.w A1T7L
    LDA.b #bank(!GfxRom_D2)
    BRA C3Mod_RestoreColumnTask_bank
C3Mod_RestoreColumnTask:                ; header: see C3Mod_ClearColumnTask
    LDX.w #!C3_MapColumnSave&$FFFF
    STX.w A1T7L
    LDA.b #bank(!C3_MapColumnSave)
.bank:
    STA.w A1B7
    LDX.w #!BBAD_VMDATAL<<8
    STX.w DMAP7                         ; DMAP7 = 0 (one register), BBAD7 = VMDATAL
    LDA.b #!VMAIN_Inc128
    STA.w VMAIN
    LDX.w #!C3_MapColumn
    STX.w VMADDL
    LDX.w #!C3_MapColumnBytes-1
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    JMP C3Mod_NmiTaskEnd

; $7E:4677 — C3Mod_RaceTask (222 bytes, $4677–$4754)
; A task, after the finish (C3Mod_RaceFinish hands over to it); it
; goes on at C3Mod_RaceStep:
;   - the A button (C3_PadHeld bit 7) once (C3_QuitSeen set): adds
;     C3Mod_FadeOutExitTask (the module leaves after the fade);
;   - while C3_ColumnCleared is set: once the pack (C3_PackDist) is in
;     lap 8 at $400 or more, clears it and adds C3Mod_RestoreColumnTask
;     (an NMI task: the map column put back);
;   - C3_PadHeld = 0;
;   - unless C3_RacePhase is 1, nothing more here. With it:
;     C3_RivalControl = $8000 (the rival keeps going) in program 9
;     (C3_Prog9, read as a word: the byte $45 above it too, 0 from
;     C3Mod_Init's clear),
;     else 0; program 9 (C3_EntryArg bits 0-3) moves C3_BikeSide to
;     $2000 and C3_RivalSide to $6000 (.bike_target / .rival_target,
;     swapped by C3Mod_RaceFinish when the bike was above) by $80 a
;     frame (rounded down to $80), not while C3_SongBusy (then
;     straight to C3Mod_RaceStep); program 0 clears C3_BikeHidden,
;     sets C3_RivalHidden = 1 once the low words' C3_BikeDist -
;     C3_RivalDist is $1000-$8FFF (CMP #$1000 / BMI: the sign of the
;     difference minus $1000) and, unless C3_SongBusy,
;     moves C3_BikeSide to $4000 the same way (with C3_SongBusy set it
;     goes straight to C3Mod_RaceStep, skipping the C3_FinishGap step
;     below too);
;   - C3_FinishGap (a byte) one step towards 0; once the word
;     C3_FinishGap is 0, C3_RivalHidden is set and C3_BikeSide (bit 0
;     aside) is $4000: C3_BikeSideUp = C3_BikeSideDown = 0 and
;     C3_RacePhase and C3_Unk1444 + 1.
; The SBC and ADC of the moves have no SEC / CLC: the CMP before each
; leaves the carry right (set when above, clear when below).
; Callers note: a task by replacement: LDX #C3Mod_RaceTask / JMP
;   C3Mod_TaskReplace at $4857 (C3Mod_RaceFinish).
; Entry: a task: M=0, X=0, DP=0 (the race words), DB=$00
;        (C3_EntryArg, C3_SongBusy and C3_Unk1444 are absolute).
; Exit:  JMP C3Mod_RaceStep with M=0, X=0.
; Calls: C3Mod_TaskAdd, C3Mod_NmiTaskAdd, C3Mod_RaceStep (JMP).
C3Mod_RaceTask:
    LDA.b !C3_QuitSeen
    BNE .no_quit
    LDA.b !C3_PadHeld
    BIT.w #!C3_PadA
    BEQ .no_quit
    INC.b !C3_QuitSeen
    LDX.w #C3Mod_FadeOutExitTask
    JSR C3Mod_TaskAdd
.no_quit:
    LDA.b !C3_ColumnCleared
    BEQ .pad_used
    LDA.b !C3_PackDist+2
    CMP.w #!C3_RaceLaps
    BNE .pad_used
    LDA.b !C3_PackDist                   ; C = 1 from the CMP
    SBC.w #!C3_ColumnBackFinish
    BCC .pad_used
    STZ.b !C3_ColumnCleared
    LDX.w #C3Mod_RestoreColumnTask
    JSR C3Mod_NmiTaskAdd
.pad_used:
    STZ.b !C3_PadHeld
    LDA.b !C3_RacePhase
    CMP.w #1
    BEQ .phase1
.to_next:
    JMP C3Mod_RaceStep
.phase1:
    STZ.b !C3_RivalControl
    LDA.b !C3_Prog9
    BEQ .prog
    LDA.w #!C3_RivalGo
    STA.b !C3_RivalControl
.prog:
    LDA.w !C3_EntryArg
    AND.w #!C3_EntryLowNibble
    BEQ .prog0
    LDA.w !C3_SongBusy
    AND.w #!Eng_LowByteMask
    BNE .to_next
    LDA.b !C3_BikeSide
.bike_target:
    CMP.w #!C3_FinishSideLow             ; written by C3Mod_RaceFinish
    BEQ .move_0073
    BMI .up_004E
    SBC.w #!C3_SideMoveStep
    BRA .round_004E
.up_004E:
    ADC.w #!C3_SideMoveStep
.round_004E:
    AND.w #!C3_SideMoveMask
    STA.b !C3_BikeSide
.move_0073:
    LDA.b !C3_RivalSide
.rival_target:
    CMP.w #!C3_FinishSideHigh            ; written by C3Mod_RaceFinish
    BEQ .moved
    BMI .up_0073
    SBC.w #!C3_SideMoveStep
    BRA .round_0073
.up_0073:
    ADC.w #!C3_SideMoveStep
.round_0073:
    AND.w #!C3_SideMoveMask
    STA.b !C3_RivalSide
.moved:
    BRA .count_00B2
.prog0:
    STZ.b !C3_BikeHidden
    LDA.b !C3_BikeDist                   ; C = 1 from the CMP #1
    SBC.b !C3_RivalDist
    CMP.w #!C3_HideLead
    BMI .song
    LDA.w #1
    STA.b !C3_RivalHidden
.song:
    LDA.w !C3_SongBusy
    AND.w #!Eng_LowByteMask
    BNE .done
    LDA.b !C3_BikeSide
    CMP.w #!C3_SideCentre
    BEQ .count_00B2
    BMI .up_004E_prog0
    SBC.w #!C3_SideMoveStep
    BRA .round_004E_prog0
.up_004E_prog0:
    ADC.w #!C3_SideMoveStep
.round_004E_prog0:
    AND.w #!C3_SideMoveMask
    STA.b !C3_BikeSide
.count_00B2:
    SEP #$20
    LDA.b !C3_FinishGap
    BEQ .test_end
    BPL .down_00B2
    INC A
    BRA .store_00B2
.down_00B2:
    DEC A
.store_00B2:
    STA.b !C3_FinishGap
.test_end:
    REP #$20
    LDA.b !C3_FinishGap
    BNE .done
    LDA.b !C3_RivalHidden
    BEQ .done
    LDA.b !C3_BikeSide
    AND.w #!C3_SideEvenMask
    CMP.w #!C3_SideCentre
    BNE .done
    STZ.b !C3_BikeSideUp
    STZ.b !C3_BikeSideDown
    INC.b !C3_RacePhase
    INC.w !C3_Unk1444
.done:
    JMP C3Mod_RaceStep

; $7E:4755 — C3Mod_WaitSongEndTask (29 bytes, $4755–$4771)
; A task: unless C3_SongBusy, once APUIO3's low nibble is not 0 (the
; sound driver's report on port 3; probably the song's end, not
; traced): C3_FrameCount's low byte = 0, page $0A00 runs
; C3Mod_Prog0Finish and this task hands over to C3Mod_DriftTask.
; Callers note: a task added by LDX #C3Mod_WaitSongEndTask / JSR
;   C3Mod_TaskAdd at $4831 (C3Mod_RaceFinish).
; Entry: a task: M any (8-bit set here), X=0 (the 16-bit pointer
;        store), DP=0 (C3_FrameCount), DB=$00 (absolute).
; Exit:  RTS with M=1, A = C3_SongBusy or the nibble (0); else JMP
;        C3Mod_TaskReplace with X = C3Mod_DriftTask.
C3Mod_WaitSongEndTask:
    SEP #$20
    LDA.w !C3_SongBusy
    BNE .wait
    LDA.w APUIO3
    AND.b #!C3_NibbleMask
    BEQ .wait
    STZ.b !C3_FrameCount
    LDX.w #C3Mod_Prog0Finish
    STX.w !C3_ScriptPageA+!C3Script_Ptr
    LDX.w #C3Mod_DriftTask
    JMP C3Mod_TaskReplace
.wait:
    RTS

; $7E:4772 — C3Mod_RepDigits (22 bytes, $4772–$4787)
; Eleven words, the numbers with repeated digits 111-666, 888, 999,
; 1111, 2222 and 3333 (no 777, which has a prize of its own): the
; scores of C3Mod_RaceFinish's prize 1, read by its CMP loop at $47F2
; (C3Mod_RepDigits - 2 + X, X = $16 down to 2).
C3Mod_RepDigits:
    dw 111, 222, 333, 444, 555, 666, 888, 999, 1111, 2222, 3333

%C3ModOrg($7E4788)
; ============================================================
; The race: the finish, the step of the two bikes, the bumps
; ($4788–$4D0C)
; ============================================================

; $7E:4788 — C3Mod_RaceFinish (213 bytes, $4788–$485C)
; The player's bike has done its 8 laps (C3Mod_RaceStepTask's JMP):
;   - C3_RaceResult = 1 (won), C3_FinishGap = C3_RaceGap's low byte;
;     the top speeds raised to $7000 (the bike's, program 0) or set to
;     $4000 (the rival's, program 9); page $0B00's var 6 = $FFF;
;     C3_FadeStep = C3_FadeTimer = 5;
;   - C3_ResultWord = C3_Score / 2 (the score shown) and C3_RacePrize:
;     2 for 777, 3 for 123 or 1234, 4 for 1000, 2000 or 3000, 1 for a
;     number of C3Mod_RepDigits (111-666, 888, 999, 1111, 2222, 3333),
;     else left as it is; then bits 5, 6 and 7 set for a score of 1300,
;     1500 and 2000 or more (signed compares); C3_SongReq = the
;     victory song (C3_SongWon);
;   - C3Mod_SteerTask removed, C3Mod_WaitSongEndTask added;
;     C3_ColumnCleared + 1, C3_RacePhase + 1 (to 1), C3_PauseAllowed =
;     0, the bike's side speeds 0; when the bike is not below the
;     rival on the side axis (C3_BikeSide >= C3_RivalSide, BMI), the
;     targets of C3Mod_RaceTask's program-9 moves are swapped ($6000
;     over its .bike_target's operand, $2000 over .rival_target's);
;   - hands the task over to C3Mod_RaceTask (C3Mod_TaskReplace).
; Callers note: JMP from C3Mod_RaceStepTask ($4866).
; Entry: JMP from a task (C3Mod_RaceStepTask's level: C3Mod_TaskReplace
;        needs the task's stack): M=0, X=0, DP=0, DB=$00.
; Exit:  JMP C3Mod_TaskReplace with X = C3Mod_RaceTask, M=0.
; Calls: C3Mod_TaskRemove, C3Mod_TaskAdd.
C3Mod_RaceFinish:
    LDA.w #!C3_RaceWon
    STA.w !C3_RaceResult                ; and C3_RacePrize = 0
    LDA.b !C3_RaceGap
    AND.w #!Eng_LowByteMask
    STA.b !C3_FinishGap
    LDA.w !C3_EntryArg
    AND.w #!C3_EntryLowNibble
    BNE .prog9
    LDA.w #!C3_TopSpeedFinish
    STA.b !C3_BikeTopSpeed
    STA.b !C3_BikeTopBehind
    BRA .vars
.prog9:
    LDA.w #!C3_RivalTopFinish9
    STA.b !C3_RivalTopSpeed
    LDA.w #!C3_RivalTopFinish9
    STA.b !C3_RivalTopAhead
.vars:
    LDA.w #!C3_FinishVarB6
    STA.w !C3_ScriptPageB+!C3_ScriptVar6
    LDA.w #!C3_FinishFade
    STA.w !C3_FadeStep                  ; and C3_FadeTimer
    LDA.b !C3_Score
    LSR A
    STA.w !C3_ResultWord
    CMP.w #!C3_Score777
    BNE .not_777
    LDA.w #!C3_Prize777
    BRA .prize
.not_777:
    CMP.w #!C3_Score123
    BEQ .run
    CMP.w #!C3_Score1234
    BNE .not_run
.run:
    LDA.w #!C3_PrizeRun
    BRA .prize
.not_run:
    CMP.w #!C3_Score1000
    BEQ .thousands
    CMP.w #!C3_Score1000*2
    BEQ .thousands
    CMP.w #!C3_Score1000*3
    BNE .rep_digits
.thousands:
    LDA.w #!C3_PrizeThousands
    BRA .prize
.rep_digits:
    LDX.w #!C3_RepDigitCount*2
.next_rep:
    CMP.l C3Mod_RepDigits-2,X
    BEQ .rep_found
    DEX
    DEX
    BNE .next_rep
    BRA .song
.rep_found:
    LDA.w #!C3_PrizeRepDigits
.prize:
    SEP #$20
    STA.w !C3_RacePrize
.song:
    SEP #$20
    LDA.b #!C3_SongWon
    STA.w !C3_SongReq
    TDC                                 ; A = 0 (DP = 0)
    LDX.w !C3_ResultWord
    CPX.w #!C3_Score1300
    BMI .high_bits
    LDA.b #!C3_Prize1300
    CPX.w #!C3_Score1500
    BMI .high_bits
    ORA.b #!C3_Prize1500
    CPX.w #!C3_Score1000*2
    BMI .high_bits
    ORA.b #!C3_Prize2000
.high_bits:
    TSB.w !C3_RacePrize
    REP #$20
    LDX.w #C3Mod_SteerTask
    JSR C3Mod_TaskRemove
    LDX.w #C3Mod_WaitSongEndTask
    JSR C3Mod_TaskAdd
    INC.b !C3_ColumnCleared
    INC.w !C3_RacePhase
    STZ.w !C3_PauseAllowed
    STZ.b !C3_BikeSideUp
    STZ.b !C3_BikeSideDown
    LDA.b !C3_BikeSide
    CMP.b !C3_RivalSide
    BMI .keep_targets
    LDA.w #!C3_FinishSideHigh
    STA.l C3Mod_RaceTask_bike_target+1
    LDA.w #!C3_FinishSideLow
    STA.l C3Mod_RaceTask_rival_target+1
.keep_targets:
    LDX.w #C3Mod_RaceTask
    JMP C3Mod_TaskReplace

; $7E:485D — C3Mod_RaceStepTask (994 bytes with C3Mod_RaceStep, $485D–$4C3E)
; A task, from the end of the count-down (C3Mod_Prog0ScriptB): one
; frame of the race. Compares below are 16-bit; "BMI" ones branch on
; bit 15 of the difference (signed, right while the values are within
; $8000 of each other), "BCC" ones are unsigned.
;   - C3_RaceFrames + 1. The bike's laps (C3_BikeDist's high word)
;     equal to 8: JMP C3Mod_RaceFinish. Else the rival's equal to 8:
;     the race is lost: C3_RaceResult = 2 (a word store, so
;     C3_RacePrize = 0 too, as it already is), C3Mod_SteerTask removed,
;     an RTS (Op_RTS) written over $510D, the shared end (.draw) of
;     C3Mod_RivalMarker and C3Mod_BikeMarker ($50F1, $5100), which
;     place the HUD's progress markers C3Mod_RivalMarkerSpr /
;     C3Mod_BikeMarkerSpr ($538D / $5391) with X from each bike's lap
;     progress and Y = its side's high byte / 8 + $C0 (the word at the
;     side + 1), next to C3Mod_DrawHud's boost icons: the markers are
;     no longer drawn; the view's X speed = (the two speeds + 1, the carry of
;     the equal CMP) / 2048, C3Mod_SkyNmiTask (NMI) and
;     C3Mod_CountDownTask (the score counted down) added, page $0A00 on
;     C3Mod_Prog0Quit, and the task ends (C3Mod_TaskEnd).
;   - Else the map column (C3_ColumnCleared): put back
;     (C3Mod_RestoreColumnTask) when the pack's (C3_PackDist) high word
;     is 0, its low word is $1000-$8FFF (CMP #$1000 / BMI) and the
;     column is cleared; cleared (C3Mod_ClearColumnTask) when the high
;     word is 7, the low word is $F200 or more (SBC #$F200 with C = 1
;     from the equal CMP, then BCC: unsigned) and it is not cleared.
;   - C3_BikeHidden = C3_RivalHidden = 1 when the 32-bit difference
;     bike - rival has a high word with bit 15 clear (CMP #0 / BMI) and
;     a low word of $1000-$8FFF (CMP #$1000 / BMI), else 0: a lead of a
;     whole lap with a low word outside that range does not count.
; Then C3Mod_RaceStep ($48FD, also C3Mod_RaceTask's tail):
;   - each speed - $80 (SEC), set to 0 when the result has bit 15 set
;     (BPL); then the bike's + C3_BikeAccel (CLC), and the rival's +
;     C3_RivalAccel (CLC) when C3_RivalControl bit 15 is set (BIT);
;   - the accelerations reset to $100 (bike) and $F8 (rival), each set
;     to 0 when cap - speed has bit 15 set (CMP / BPL: the speed above
;     the cap; equal keeps it);
;   - racing (C3_RacePhase 0) only: the boost. C3_BoostTimer not 0:
;     when C3_BoostsLeft is not 0 and C3_BoostTimer AND 7 is 0, the
;     lamp's rows rotate (C3_LampLeftRows / C3_LampRightRows, bit plane
;     3 of rows 0 and 1 of its two tiles: SEC / ROR, the second tile
;     taking the first one's carry out, a row of lit pixels filling
;     in); then C3_BoostTimer - 1. C3_BoostTimer 0: B (C3_PadHeld bit
;     15) not held clears C3_BoostHeld; held while C3_BoostHeld is 0
;     sets it and, when C3_BoostsLeft is not 0, uses a boost:
;     C3_BoostsLeft - 1, C3_BoostTimer = $80, the lamp rows cleared,
;     the bike's speed + $1700 + C (no CLC: C from the rival's cap CMP,
;     1 when the rival's cap >= its speed, unsigned), and $7FFF when
;     the sum has bit 15 set (BPL);
;   - the speed caps: the bike's C3_BikeTopSpeed, or C3_BikeTopBehind
;     when C3_RaceGap has bit 15 set; the rival's C3_RivalTopSpeed, or
;     C3_RivalTopAhead when it has not (a gap of 0 counts as ahead);
;   - C3_PackDist = the two distances' sum / 2 (32-bit: CLC / ADC /
;     ADC, then LSR / ROR); the view's X = (its low word / 16 + $374 +
;     1, SEC / ADC) AND $3FF;
;   - racing only: C3_RivalControl = $8000 (else 0). C3_RaceGap $0001-
;     $7FFF (not 0, BEQ; bit 15 clear, BMI): C3_Score + 2, and when
;     |the bike's side word at +1 - the rival's| is below $20 (SEC /
;     SBC, BPL, else the reverse; then CMP #$20 / BMI: values $00-$1F
;     with these small words; the words at C3_BikeSide+1 /
;     C3_RivalSide+1 are the high bytes, with $50 / $75 above them,
;     0 as far as program 0's traced code goes), the rival steers
;     away: down when that word is $40 or more (CMP #$40 / BMI), else
;     up. Otherwise (the gap 0 or bit 15 set): C3_Score - 1 and the
;     rival steers down when C3_BikeSide - C3_RivalSide has bit 15 set
;     (CMP / BMI: the bike below), else up (equal included);
;   - C3_BikeSteer = 0, then 1 while C3_PadSidePlus is held (BIT:
;     C3_BikeSideUp + $28 + C) and 2 while C3_PadSideMinus is
;     (C3_BikeSideDown + $28 + C); the rival's C3_RivalSideUp / Down +
;     $18 + C by C3_RivalControl bits 9 / 8. Each push is capped at
;     $210 (CMP #$210 / BMI: $210 when the sum is $210 or more) and
;     each of the four decays by $10, or $11 with C = 0 (SBC without
;     SEC), set to 0 when the result has bit 15 set (BPL). The C of
;     each push and decay is what the instruction before left: the
;     push's CMP #$210 (1 when capped) for its own decay, else the
;     decay before it (1 unless it borrowed; 0 after a set-to-0), and
;     for the first, the compare that ended the steering part (or the
;     view X's ADC, 0, when not racing);
;   - C3_RaceGap = (the bike's distance / 32) - (the rival's / 32) -
;     1 + C (the low words of the 32-bit values shifted right 5; no
;     SEC: C is the bike's last bit shifted out, its distance's bit 4);
;   - racing only, the bumps, on the distances' low words alone (the
;     laps are not compared: a bike a whole lap ahead or behind at the
;     same spot looks level). With the bike's front F = its distance +
;     $100 + C (C from the gap's SBC) and the rival's R = its distance
;     + $C0 + C (C from the ADC before, as is the next): along the
;     track, 1 (the bike ahead) when R + $200 + C - F has bit 15 set
;     (CMP / BMI), else 2 (behind) when R - $180 - (1 - C) - F has bit
;     15 clear (C from that CMP; BMI not taken), else 0 (overlapping);
;     across, $10 (the bike below) when C3_RivalSide - $1000 -
;     C3_BikeSide has bit 15 clear (SEC / SBC, CMP / BPL: the bike at
;     the rival's side - $1000 or lower, equal included), else $20 (the
;     bike above) when C3_RivalSide + $1000 + C - C3_BikeSide has bit
;     15 set (CMP / BEQ / BPL: the bike above the rival's side + $1000
;     + C, with C = 1 when the rival's side is below $1000, from the
;     CMP before; equal counts as overlapping), else 0. So the two
;     sides differ: $10 at a gap of $1000, $20 only past $1000 + C.
;     C3_BumpNow = across | along; when it is not 0 it goes to
;     C3_BumpLast; when it is 0 (overlapping both ways), C3_BumpLast
;     (equal compares) says how they came together: 1 the rival ran
;     into the bike from behind (C3Mod_BumpFromBehind, C3_Score + 20,
;     CLC), 2 the bike into the rival (C3Mod_BumpFromAhead, C3_Score -
;     10, SEC), $10 / $20 from the side (C3Mod_BumpFromBelow /
;     FromAbove), $11, $12, $21, $22 both; any other value no bump
;     routine; then sound effect $98 (Audio_CmdPlaySfx, C3Mod_AudioSend)
;     unless C3_SongBusy is not 0;
;   - racing only, after any bump sound: the engine sound:
;     C3_SndSfxPitch with the bike's speed's high byte, written to
;     APUIO1 and APUIO0 straight (no echo wait, unlike
;     C3Mod_AudioSend), unless C3_SongBusy is not 0;
;   - the bikes move: each distance + (its speed / 64 AND $1FF) (CLC,
;     32-bit); each side + its up speed (CLC), set to $7000 when the
;     sum - $7000 has bit 15 clear (CMP / BMI: $7000 or more), then -
;     its down speed (SEC), set to 0 when bit 15 is set (BPL).
; Sub-entry: C3Mod_RaceStep ($48FD).
; Callers note: a task added by script opcode $FA at $4047
;   (C3Mod_Prog0ScriptB). C3Mod_RaceStep: JMP from C3Mod_RaceTask
;   ($46AD, $4752).
; Entry: a task (C3Mod_RunTasks): M=0, X=0, DP=0 (the race words), DB =
;        $00 (C3_RaceResult, the script pages' words and the APU ports
;        are absolute).
; Exit:  RTS with M=0, X=0, DP=0, DB=$00; A = C3_RivalSide; X changed;
;        Y unchanged; C3_TmpF0/F2 changed (and the bump routines'
;        C3_TmpF6/F8); or JMP C3Mod_RaceFinish / C3Mod_TaskEnd (see
;        above).
; Calls: C3Mod_RaceFinish (JMP), C3Mod_TaskRemove, C3Mod_NmiTaskAdd,
;   C3Mod_TaskAdd, C3Mod_TaskEnd (JMP), the bump routines,
;   C3Mod_AudioSend.
C3Mod_RaceStepTask:
    INC.b !C3_RaceFrames
    LDA.b !C3_BikeDist+2
    CMP.w #!C3_RaceLaps
    BNE .rival_done
    JMP C3Mod_RaceFinish
.rival_done:
    LDA.b !C3_RivalDist+2
    CMP.w #!C3_RaceLaps
    BNE .column
    LDA.w #!C3_RaceLost
    STA.w !C3_RaceResult
    LDX.w #C3Mod_SteerTask
    JSR C3Mod_TaskRemove
    SEP #$20
    LDA.b #!Op_RTS
    STA.l C3Mod_BikeMarker_draw
    REP #$20
    LDA.b !C3_BikeSpeed                 ; C = 1 from the CMP
    ADC.b !C3_RivalSpeed
    XBA
    AND.w #!Eng_LowByteMask
    LSR A
    LSR A
    LSR A
    STA.w !C3_ScriptPageA+!C3_ViewSpeedX
    LDX.w #C3Mod_SkyNmiTask
    JSR C3Mod_NmiTaskAdd
    LDX.w #C3Mod_CountDownTask
    JSR C3Mod_TaskAdd
    LDA.w #C3Mod_Prog0Quit
    STA.w !C3_ScriptPageA+!C3Script_Ptr
    JMP C3Mod_TaskEnd
.column:
    LDA.b !C3_PackDist+2
    BNE .not_lap0
    LDA.b !C3_PackDist
    CMP.w #!C3_ColumnBackDist
    BMI .not_lap0
    LDA.b !C3_ColumnCleared
    BEQ .not_lap0
    STZ.b !C3_ColumnCleared
    LDX.w #C3Mod_RestoreColumnTask
    JSR C3Mod_NmiTaskAdd
.not_lap0:
    LDA.b !C3_PackDist+2
    CMP.w #!C3_RaceLaps-1
    BNE .lead
    LDA.b !C3_PackDist                  ; C = 1 from the CMP
    SBC.w #!C3_ColumnClearDist
    BCC .lead
    LDA.b !C3_ColumnCleared
    BNE .lead
    INC.b !C3_ColumnCleared
    LDX.w #C3Mod_ClearColumnTask
    JSR C3Mod_NmiTaskAdd
.lead:
    STZ.b !C3_RivalHidden
    STZ.b !C3_BikeHidden
    LDA.b !C3_BikeDist
    SEC
    SBC.b !C3_RivalDist
    STA.b !C3_TmpF0
    LDA.b !C3_BikeDist+2
    SBC.b !C3_RivalDist+2
    STA.b !C3_TmpF2
    LDA.b !C3_TmpF2
    CMP.w #0
    BMI C3Mod_RaceStep
    LDA.b !C3_TmpF0
    CMP.w #!C3_HideLead
    BMI C3Mod_RaceStep
    INC.b !C3_BikeHidden
    INC.b !C3_RivalHidden
C3Mod_RaceStep:                         ; header: see C3Mod_RaceStepTask
    LDA.b !C3_BikeSpeed
    SEC
    SBC.w #!C3_SpeedDrag
    BPL .bike_drag
    TDC                                 ; A = 0 (DP = 0)
.bike_drag:
    STA.b !C3_BikeSpeed
    LDA.b !C3_RivalSpeed
    SEC
    SBC.w #!C3_SpeedDrag
    BPL .rival_drag
    TDC
.rival_drag:
    STA.b !C3_RivalSpeed
    LDA.b !C3_BikeSpeed
    CLC
    ADC.b !C3_BikeAccel
    STA.b !C3_BikeSpeed
    LDA.b !C3_RivalControl
    BIT.w #!C3_RivalGo
    BEQ .accels
    LDA.b !C3_RivalSpeed
    CLC
    ADC.b !C3_RivalAccel
    STA.b !C3_RivalSpeed
.accels:
    LDA.w #!C3_BikeAccelOn
    STA.b !C3_BikeAccel
    LDA.w #!C3_RivalAccelOn
    STA.b !C3_RivalAccel
    LDA.b !C3_BikeSpeedCap
    CMP.b !C3_BikeSpeed
    BPL .bike_capped
    STZ.b !C3_BikeAccel
.bike_capped:
    LDA.b !C3_RivalSpeedCap
    CMP.b !C3_RivalSpeed
    BPL .rival_capped
    STZ.b !C3_RivalAccel
.rival_capped:
    LDA.b !C3_RacePhase
    BNE .caps
    LDA.b !C3_BoostTimer
    BEQ .boost_button
    LDA.b !C3_BoostsLeft
    BEQ .boost_count
    LDA.b !C3_BoostTimer
    AND.w #!C3_LampEvery-1
    BNE .boost_count
    SEP #$20
    PEA.w !Bank7E                       ; PLB takes the $7E; the second PLB the $00
    PLB
    LDA.w !C3_LampLeftRows
    SEC
    ROR A
    STA.w !C3_LampLeftRows
    STA.w !C3_LampLeftRows+2
    LDA.w !C3_LampRightRows
    ROR A
    STA.w !C3_LampRightRows
    STA.w !C3_LampRightRows+2
    PLB
    REP #$20
.boost_count:
    DEC.b !C3_BoostTimer
    BRA .caps
.boost_button:
    LDA.b !C3_PadHeld
    BIT.w #!C3_PadB
    BEQ .boost_released
    LDA.b !C3_BoostHeld
    BNE .caps
    INC.b !C3_BoostHeld
    LDA.b !C3_BoostsLeft
    BEQ .caps
    DEC A
    STA.b !C3_BoostsLeft
    LDA.w #!C3_BoostFrames
    STA.b !C3_BoostTimer
    SEP #$20
    PEA.w !Bank7E
    PLB
    STZ.w !C3_LampLeftRows
    STZ.w !C3_LampLeftRows+2
    STZ.w !C3_LampRightRows
    STZ.w !C3_LampRightRows+2
    PLB
    REP #$20
    LDA.b !C3_BikeSpeed                 ; C from the CMP of the rival's cap
    ADC.w #!C3_BoostSpeed
    BPL .boosted
    LDA.w #!C3_SpeedMax
.boosted:
    STA.b !C3_BikeSpeed
    BRA .caps
.boost_released:
    STZ.b !C3_BoostHeld
.caps:
    LDA.b !C3_BikeTopSpeed
    STA.b !C3_BikeSpeedCap
    LDA.b !C3_RivalTopSpeed
    STA.b !C3_RivalSpeedCap
    LDA.b !C3_RaceGap
    BMI .bike_behind
    LDA.b !C3_RivalTopAhead
    STA.b !C3_RivalSpeedCap
    BRA .pack
.bike_behind:
    LDA.b !C3_BikeTopBehind
    STA.b !C3_BikeSpeedCap
.pack:
    LDA.b !C3_BikeDist
    CLC
    ADC.b !C3_RivalDist
    STA.b !C3_PackDist
    LDA.b !C3_BikeDist+2
    ADC.b !C3_RivalDist+2
    LSR A
    STA.b !C3_PackDist+2
    LDA.b !C3_PackDist
    ROR A
    STA.b !C3_PackDist
    LSR A
    LSR A
    LSR A
    LSR A
    SEC
    ADC.w #!C3_ViewXBase
    AND.w #!C3_PlaneMask
    STA.w !C3_ScriptPageA+!C3_ViewX
    STZ.b !C3_RivalControl
    LDA.b !C3_RacePhase
    BNE .bike_steer
    LDA.w #!C3_RivalGo
    STA.b !C3_RivalControl
    LDA.b !C3_RaceGap
    BEQ .bike_not_ahead
    BMI .bike_not_ahead
    INC.b !C3_Score
    INC.b !C3_Score
    LDA.b !C3_BikeSide+1
    SEC
    SBC.b !C3_RivalSide+1
    BPL .side_gap
    LDA.b !C3_RivalSide+1
    SEC
    SBC.b !C3_BikeSide+1
.side_gap:
    CMP.w #!C3_SideNear
    BPL .bike_steer
    LDA.b !C3_BikeSide+1
    CMP.w #!C3_SideMiddle
    BMI .steer_up
.steer_down:
    LDA.w #!C3_RivalSteerDown
    BRA .rival_steer
.bike_not_ahead:
    DEC.b !C3_Score
    LDA.b !C3_BikeSide
    CMP.b !C3_RivalSide
    BMI .steer_down
.steer_up:
    LDA.w #!C3_RivalSteerUp
.rival_steer:
    TSB.b !C3_RivalControl
.bike_steer:
    STZ.b !C3_BikeSteer
    LDA.b !C3_PadHeld
    BIT.b !C3_PadSidePlus
    BEQ .side_up_decay
    LDA.w #!C3_BikeSteerPlus
    STA.b !C3_BikeSteer
    LDA.b !C3_BikeSideUp                ; C as left (no CLC)
    ADC.w #!C3_SidePush
    CMP.w #!C3_SideSpeedMax
    BMI .side_up_store
    LDA.w #!C3_SideSpeedMax
.side_up_store:
    STA.b !C3_BikeSideUp
.side_up_decay:
    LDA.b !C3_BikeSideUp                ; C as left (no SEC)
    SBC.w #!C3_SideDecay
    BPL .side_up_kept
    LDA.w #0
.side_up_kept:
    STA.b !C3_BikeSideUp
    LDA.b !C3_PadHeld
    BIT.b !C3_PadSideMinus
    BEQ .side_down_decay
    LDA.w #!C3_BikeSteerMinus
    STA.b !C3_BikeSteer
    LDA.b !C3_BikeSideDown
    ADC.w #!C3_SidePush
    CMP.w #!C3_SideSpeedMax
    BMI .side_down_store
    LDA.w #!C3_SideSpeedMax
.side_down_store:
    STA.b !C3_BikeSideDown
.side_down_decay:
    LDA.b !C3_BikeSideDown
    SBC.w #!C3_SideDecay
    BPL .side_down_kept
    LDA.w #0
.side_down_kept:
    STA.b !C3_BikeSideDown
    LDA.b !C3_RivalControl
    BIT.w #!C3_RivalSteerUp
    BEQ .rival_up_decay
    LDA.b !C3_RivalSideUp
    ADC.w #!C3_RivalSidePush
    CMP.w #!C3_SideSpeedMax
    BMI .rival_up_store
    LDA.w #!C3_SideSpeedMax
.rival_up_store:
    STA.b !C3_RivalSideUp
.rival_up_decay:
    LDA.b !C3_RivalSideUp
    SBC.w #!C3_SideDecay
    BPL .rival_up_kept
    LDA.w #0
.rival_up_kept:
    STA.b !C3_RivalSideUp
    LDA.b !C3_RivalControl
    BIT.w #!C3_RivalSteerDown
    BEQ .rival_down_decay
    LDA.b !C3_RivalSideDown
    ADC.w #!C3_RivalSidePush
    CMP.w #!C3_SideSpeedMax
    BMI .rival_down_store
    LDA.w #!C3_SideSpeedMax
.rival_down_store:
    STA.b !C3_RivalSideDown
.rival_down_decay:
    LDA.b !C3_RivalSideDown
    SBC.w #!C3_SideDecay
    BPL .rival_down_kept
    LDA.w #0
.rival_down_kept:
    STA.b !C3_RivalSideDown
    LDA.b !C3_RivalDist+2               ; the gap: both distances / 32
    STA.b !C3_TmpF0
    LDA.b !C3_RivalDist
    LSR.b !C3_TmpF0
    ROR A
    LSR.b !C3_TmpF0
    ROR A
    LSR.b !C3_TmpF0
    ROR A
    LSR.b !C3_TmpF0
    ROR A
    LSR.b !C3_TmpF0
    ROR A
    STA.b !C3_TmpF2
    LDA.b !C3_BikeDist+2
    STA.b !C3_TmpF0
    LDA.b !C3_BikeDist
    LSR.b !C3_TmpF0
    ROR A
    LSR.b !C3_TmpF0
    ROR A
    LSR.b !C3_TmpF0
    ROR A
    LSR.b !C3_TmpF0
    ROR A
    LSR.b !C3_TmpF0
    ROR A
    SBC.b !C3_TmpF2                     ; C = the bit the last ROR shifted out
    STA.b !C3_RaceGap
    LDA.b !C3_RacePhase
    BEQ .bumps
    JMP .move
.bumps:
    STZ.b !C3_BumpNow
    LDA.w #!C3_BikeLength               ; C as left
    ADC.b !C3_BikeDist
    STA.b !C3_TmpF0
    LDA.w #!C3_RivalLength
    ADC.b !C3_RivalDist
    STA.b !C3_TmpF2
    ADC.w #!C3_BumpAhead
    CMP.b !C3_TmpF0
    BMI .bike_ahead
    LDA.b !C3_TmpF2
    SBC.w #!C3_BumpBehind
    CMP.b !C3_TmpF0
    BMI .side
    INC.b !C3_BumpNow
.bike_ahead:
    INC.b !C3_BumpNow
.side:
    STZ.b !C3_BumpSide
    LDA.b !C3_RivalSide
    SEC
    SBC.w #!C3_BumpWidth
    CMP.b !C3_BikeSide
    BPL .bike_below
    LDA.b !C3_RivalSide                 ; C as left by the CMP
    ADC.w #!C3_BumpWidth
    CMP.b !C3_BikeSide
    BEQ .relation
    BPL .relation
    INC.b !C3_BumpSide
.bike_below:
    INC.b !C3_BumpSide
.relation:
    LDA.b !C3_BumpSide
    ASL A
    ASL A
    ASL A
    ASL A
    ORA.b !C3_BumpNow
    STA.b !C3_BumpNow
    BEQ .bump
    LDA.b !C3_BumpNow
    STA.b !C3_BumpLast
    JMP .engine
.bump:
    LDA.b !C3_BumpLast
    CMP.w #!C3_BumpAheadOnly
    BNE .not_1
    JSR C3Mod_BumpFromBehind
    LDA.b !C3_Score
    CLC
    ADC.w #!C3_BumpScoreUp
    STA.b !C3_Score
    BRA .bump_sound
.not_1:
    CMP.w #!C3_BumpBehindOnly
    BNE .not_2
    JSR C3Mod_BumpFromAhead
    LDA.b !C3_Score
    SEC
    SBC.w #!C3_BumpScoreDown
    STA.b !C3_Score
    BRA .bump_sound
.not_2:
    CMP.w #!C3_BumpBelowOnly
    BNE .not_10
    JSR C3Mod_BumpFromBelow
    BRA .bump_sound
.not_10:
    CMP.w #!C3_BumpBelowOnly|!C3_BumpAheadOnly
    BNE .not_11
    JSR C3Mod_BumpFromBehind
    JSR C3Mod_BumpFromBelow
    BRA .bump_sound
.not_11:
    CMP.w #!C3_BumpBelowOnly|!C3_BumpBehindOnly
    BNE .not_12
    JSR C3Mod_BumpFromBelow
    JSR C3Mod_BumpFromAhead
    BRA .bump_sound
.not_12:
    CMP.w #!C3_BumpAboveOnly
    BNE .not_20
    JSR C3Mod_BumpFromAbove
    BRA .bump_sound
.not_20:
    CMP.w #!C3_BumpAboveOnly|!C3_BumpAheadOnly
    BNE .not_21
    JSR C3Mod_BumpFromBehind
    JSR C3Mod_BumpFromAbove
    BRA .bump_sound
.not_21:
    CMP.w #!C3_BumpAboveOnly|!C3_BumpBehindOnly
    BNE .bump_sound
    JSR C3Mod_BumpFromAbove
    JSR C3Mod_BumpFromAhead
.bump_sound:
    SEP #$20
    LDA.w !C3_SongBusy
    BNE .engine
    LDA.b #!C3_SfxArg1
    STA.w !Audio_CmdArg1
    LDA.b #!C3_SfxBump
    STA.w !Audio_CmdArg0
    LDA.b #!Audio_CmdPlaySfx
    STA.w !Audio_CmdId
    JSR C3Mod_AudioSend
.engine:
    SEP #$20
    LDA.w !C3_SongBusy
    BNE .engine_done
    LDA.b !C3_BikeSpeed+1
    STA.w APUIO1
    LDA.b #!C3_SndSfxPitch
    STA.w APUIO0
.engine_done:
    REP #$20
.move:
    LDA.b !C3_BikeSpeed
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    AND.w #!C3_StepMask
    CLC
    ADC.b !C3_BikeDist
    STA.b !C3_BikeDist
    LDA.b !C3_BikeDist+2
    ADC.w #0
    STA.b !C3_BikeDist+2
    LDA.b !C3_RivalSpeed
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    AND.w #!C3_StepMask
    CLC
    ADC.b !C3_RivalDist
    STA.b !C3_RivalDist
    LDA.b !C3_RivalDist+2
    ADC.w #0
    STA.b !C3_RivalDist+2
    LDA.b !C3_BikeSide
    CLC
    ADC.b !C3_BikeSideUp
    CMP.w #!C3_SideMax
    BMI .bike_side_max
    LDA.w #!C3_SideMax
.bike_side_max:
    STA.b !C3_BikeSide
    LDA.b !C3_BikeSide
    SEC
    SBC.b !C3_BikeSideDown
    BPL .bike_side_min
    TDC                                 ; A = 0 (DP = 0)
.bike_side_min:
    STA.b !C3_BikeSide
    LDA.b !C3_RivalSide
    CLC
    ADC.b !C3_RivalSideUp
    CMP.w #!C3_SideMax
    BMI .rival_side_max
    LDA.w #!C3_SideMax
.rival_side_max:
    STA.b !C3_RivalSide
    LDA.b !C3_RivalSide
    SEC
    SBC.b !C3_RivalSideDown
    BPL .rival_side_min
    TDC
.rival_side_min:
    STA.b !C3_RivalSide
    RTS

; $7E:4C3F — C3Mod_BumpFromBehind (69 bytes, $4C3F–$4C83)
; A bump along the track with the bike ahead: the overlap ((the
; rival's distance + $C0) - (the bike's - $100), 32-bit, in
; C3_TmpF6/F8) is added to the bike's distance (with the carry of the
; subtraction), and the
; speeds are swapped (C3Mod_BumpFromAhead's .swap_speeds). Quirk: the
; rival's distance loses the overlap's high word C3_TmpF8 from both of
; its words (SBC C3_TmpF8 twice), not the overlap; with the overlap
; below $10000, the high word is 0 and the rival stays (bar the
; borrows).
; Callers note: C3Mod_RaceStepTask ($4B4D, $4B7B, $4B9F).
; Entry: M=0, X=0 (the swap's 16-bit LDX/STX), DP=0 (the race words,
;        C3_TmpF0..F8), DB any.
; Exit:  M=0; A = the rival's old speed, X = the bike's old speed; Y
;        unchanged; C3_TmpF0..F8 changed.
C3Mod_BumpFromBehind:
    LDA.b !C3_BikeDist
    SEC
    SBC.w #!C3_BikeLength
    STA.b !C3_TmpF0
    LDA.b !C3_BikeDist+2
    SBC.w #0
    STA.b !C3_TmpF2
    LDA.b !C3_RivalDist
    CLC
    ADC.w #!C3_RivalLength
    STA.b !C3_TmpF6
    LDA.b !C3_RivalDist+2
    ADC.w #0
    STA.b !C3_TmpF8
    LDA.b !C3_TmpF6
    SEC
    SBC.b !C3_TmpF0
    STA.b !C3_TmpF6
    LDA.b !C3_TmpF8
    SBC.b !C3_TmpF2
    STA.b !C3_TmpF8
    LDA.b !C3_BikeDist                  ; C from the SBC
    ADC.b !C3_TmpF6
    STA.b !C3_BikeDist
    LDA.b !C3_BikeDist+2
    ADC.b !C3_TmpF8
    STA.b !C3_BikeDist+2
    LDA.b !C3_RivalDist
    SBC.b !C3_TmpF8
    STA.b !C3_RivalDist
    LDA.b !C3_RivalDist+2
    SBC.b !C3_TmpF8
    STA.b !C3_RivalDist+2
    BRA C3Mod_BumpFromAhead_swap_speeds

; $7E:4C84 — C3Mod_BumpFromAhead (76 bytes, $4C84–$4CCF)
; The same with the rival ahead: the overlap ((the bike's distance +
; $100) - (the rival's - $C0)) is added to the rival's distance, and the
; bike's loses the overlap's high word from both words (the same
; quirk); then .swap_speeds: the bike's and the rival's speeds are
; swapped (also C3Mod_BumpFromBehind's end).
; Callers note: C3Mod_RaceStepTask ($4B5F, $4B8B, $4BAF).
;   .swap_speeds: C3Mod_BumpFromBehind (BRA).
; Entry: M=0, X=0, DP=0, DB any.
; Exit:  M=0; A = the bike's new speed (the rival's old one), X = the
;        rival's new speed; Y unchanged; C3_TmpF0..F8 changed.
C3Mod_BumpFromAhead:
    LDA.b !C3_RivalDist
    SEC
    SBC.w #!C3_RivalLength
    STA.b !C3_TmpF0
    LDA.b !C3_RivalDist+2
    SBC.w #0
    STA.b !C3_TmpF2
    LDA.b !C3_BikeDist
    CLC
    ADC.w #!C3_BikeLength
    STA.b !C3_TmpF6
    LDA.b !C3_BikeDist+2
    ADC.w #0
    STA.b !C3_TmpF8
    LDA.b !C3_TmpF6
    SEC
    SBC.b !C3_TmpF0
    STA.b !C3_TmpF6
    LDA.b !C3_TmpF8
    SBC.b !C3_TmpF2
    STA.b !C3_TmpF8
    LDA.b !C3_RivalDist
    ADC.b !C3_TmpF6
    STA.b !C3_RivalDist
    LDA.b !C3_RivalDist+2
    ADC.b !C3_TmpF8
    STA.b !C3_RivalDist+2
    LDA.b !C3_BikeDist
    SBC.b !C3_TmpF8
    STA.b !C3_BikeDist
    LDA.b !C3_BikeDist+2
    SBC.b !C3_TmpF8
    STA.b !C3_BikeDist+2
.swap_speeds:
    LDX.b !C3_BikeSpeed
    LDA.b !C3_RivalSpeed
    STA.b !C3_BikeSpeed
    STX.b !C3_RivalSpeed
    RTS

; $7E:4CD0 — C3Mod_BumpFromBelow (23 bytes, $4CD0–$4CE6)
; A bump across the track with the bike below the rival: the overlap
; C3_TmpF0 = the bike's side + $1000 - the rival's (with the carries
; as left) is taken off the bike's side and added to the rival's, then
; .swap_sides (C3Mod_BumpFromAbove's) swaps their side speeds (up with
; up, down with down).
; Callers note: C3Mod_RaceStepTask ($4B71, $4B7E, $4B88).
; Entry: M=0, X=0, DP=0, DB any.
; Exit:  as C3Mod_BumpFromAbove's .swap_sides.
C3Mod_BumpFromBelow:
    LDA.b !C3_BikeSide                  ; C as left
    ADC.w #!C3_BumpWidth
    SBC.b !C3_RivalSide
    STA.b !C3_TmpF0
    LDA.b !C3_BikeSide
    SBC.b !C3_TmpF0
    STA.b !C3_BikeSide
    LDA.b !C3_RivalSide
    ADC.b !C3_TmpF0
    STA.b !C3_RivalSide
    BRA C3Mod_BumpFromAbove_swap_sides

; $7E:4CE7 — C3Mod_BumpFromAbove (38 bytes, $4CE7–$4D0C)
; The same with the bike above: C3_TmpF0 = the rival's side + $1000 -
; the bike's, added to the bike's side and taken off the rival's; then
; .swap_sides: C3_BikeSideDown with C3_RivalSideDown and C3_BikeSideUp
; with C3_RivalSideUp (also C3Mod_BumpFromBelow's end).
; Callers note: C3Mod_RaceStepTask ($4B95, $4BA2, $4BAC).
;   .swap_sides: C3Mod_BumpFromBelow (BRA).
; Entry: M=0, X=0, DP=0, DB any.
; Exit:  M=0; A = C3_RivalSideUp's old value (the bike's new one), X =
;        C3_BikeSideUp's old value; Y unchanged; C3_TmpF0 changed.
C3Mod_BumpFromAbove:
    LDA.b !C3_RivalSide                 ; C as left
    ADC.w #!C3_BumpWidth
    SBC.b !C3_BikeSide
    STA.b !C3_TmpF0
    LDA.b !C3_BikeSide
    ADC.b !C3_TmpF0
    STA.b !C3_BikeSide
    LDA.b !C3_RivalSide
    SBC.b !C3_TmpF0
    STA.b !C3_RivalSide
.swap_sides:
    LDX.b !C3_BikeSideDown
    LDA.b !C3_RivalSideDown
    STA.b !C3_BikeSideDown
    STX.b !C3_RivalSideDown
    LDX.b !C3_BikeSideUp
    LDA.b !C3_RivalSideUp
    STA.b !C3_BikeSideUp
    STX.b !C3_RivalSideUp
    RTS

%C3ModOrg($7E4D0D)
; ============================================================
; The race on the screen: the two bikes' projection and sizes
; ($4D0D–$4F53)
; ============================================================
; The bike and the rival are placed around the view's centre: along
; the track by C3_RaceGap (its low byte, signed), across by their side
; positions' high bytes - $40, both turned by the view's angle with the
; C3_View* rotation words (C3_ViewNegCos = -cos, C3_ViewNegSin = -sin,
; C3_ViewCos, C3_ViewSin; C3Mod_Sine gives -sin). Then each one's
; height on the screen gives a depth from the hardware divider, and
; the depth the sprite's size and its scaled picture.

; $7E:4D0D — C3Mod_ProjectTask (65 bytes, $4D0D–$4D4D)
; A task: the rotation words from the view's angle a (page $0A00's
; C3_ViewAngle): x = $100 - a + C (EOR / INC, then ADC #$100 with the
; carry as the task is entered: 0, from C3Mod_TaskNext's CPX, unless
; it is the list's first task), C3_ViewNegSin = C3Mod_Cosine(x) =
; -sin(a) and C3_ViewSin its negation, C3_ViewNegCos = C3Mod_Sine(x) =
; -cos(a) and C3_ViewCos its negation (these hold for C = 0; with C =
; 1, x is one step further); then
; C3Mod_ProjectBike and C3Mod_ProjectRival, C3_DivisorStart = the
; horizon (page $0A00's C3_ViewHorizon), and the two sizes: when
; C3_BikeScrY - C3_RivalScrY has bit 15 set (CMP / BMI: the bike higher
; on the screen), C3Mod_SizeBike then C3Mod_SizeRival (JMP), else
; (equal included) C3Mod_SizeRival then C3Mod_SizeBike (JMP).
; Callers note: a task added by script opcode $FA at $3F26
;   (C3Mod_Prog0ScriptA) and $413C (C3Mod_Prog0Start).
; Entry: a task (C3Mod_RunTasks): M=0, X=0, DP=0 (the race words, the
;        C3_Mul* and C3Math_* scratch), DB=$00 (the page words and the
;        divider are absolute).
; Exit:  as C3Mod_SizeBike or C3Mod_SizeRival leaves them (JMP): M=0,
;        X=0, DP=0, DB=$00.
; Calls: C3Mod_Cosine, C3Mod_Sine, C3Mod_ProjectBike,
;   C3Mod_ProjectRival, C3Mod_SizeBike, C3Mod_SizeRival.
C3Mod_ProjectTask:
    LDA.w !C3_ScriptPageA+!C3_ViewAngle
    EOR.w #!Eng_Invert16
    INC A
    ADC.w #!C3_QuarterTurn              ; C as the task is entered
    STA.b !C3_TmpF0
    JSR C3Mod_Cosine
    STA.b !C3_ViewNegSin
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C3_ViewSin
    LDA.b !C3_TmpF0
    JSR C3Mod_Sine
    STA.b !C3_ViewNegCos
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C3_ViewCos
    JSR C3Mod_ProjectBike
    JSR C3Mod_ProjectRival
    LDA.w !C3_ScriptPageA+!C3_ViewHorizon
    STA.b !C3_DivisorStart
    LDA.b !C3_BikeScrY
    CMP.b !C3_RivalScrY
    BMI .bike_first
    JSR C3Mod_SizeRival
    JMP C3Mod_SizeBike
.bike_first:
    JSR C3Mod_SizeBike
    JMP C3Mod_SizeRival

; $7E:4D4E — C3Mod_ProjectBike (87 bytes, $4D4E–$4DA4)
; The bike's point: with g = C3_RaceGap's low byte (C3_FinishGap's
; once C3_RacePhase is not 0: LDA / BEQ) and s = the word at
; C3_BikeSide+1 - $40 (CLC / ADC #$FFC0; C3_MulB takes its low byte),
; both signed bytes for C3_MulSigned (a 16-bit x 8-bit multiply):
; C3_BikeScrX = (-cos) x g + (-sin) x s and C3_BikeScrY = (-sin) x g +
; cos x s (the low words of the products, added with CLC).
; Callers note: C3Mod_ProjectTask ($4D31).
; Entry: M=0, X=0 (C3_MulSigned's 16-bit LDX), DP=0 (the race words and
;        C3_MulA..), DB=$00 (C3_MulSigned's CPU registers).
; Exit:  M=0, X=0; A = C3_BikeScrY; X = |C3_MulB| x the low byte of
;        |C3_MulA| (the last C3_MulSigned's RDMPYL); Y unchanged; C =
;        the last ADC's carry out; C3_MulA.. changed.
; Calls: C3_MulSigned (JSL).
C3Mod_ProjectBike:
    LDX.b !C3_ViewNegCos
    STX.b !C3_MulA
    LDX.b !C3_RaceGap
    LDA.b !C3_RacePhase
    BEQ .gap_x
    LDX.b !C3_FinishGap
.gap_x:
    STX.b !C3_MulB
    JSL !C3_MulSigned
    LDA.b !C3_MulProduct
    PHA
    LDX.b !C3_ViewNegSin
    STX.b !C3_MulA
    LDA.b !C3_BikeSide+1
    CLC
    ADC.w #-!C3_SideMiddle
    STA.b !C3_MulB
    JSL !C3_MulSigned
    PLA
    CLC
    ADC.b !C3_MulProduct
    STA.b !C3_BikeScrX
    LDX.b !C3_ViewNegSin
    STX.b !C3_MulA
    LDX.b !C3_RaceGap
    LDA.b !C3_RacePhase
    BEQ .gap_y
    LDX.b !C3_FinishGap
.gap_y:
    STX.b !C3_MulB
    JSL !C3_MulSigned
    LDA.b !C3_MulProduct
    PHA
    LDX.b !C3_ViewCos
    STX.b !C3_MulA
    LDA.b !C3_BikeSide+1
    CLC
    ADC.w #-!C3_SideMiddle
    STA.b !C3_MulB
    JSL !C3_MulSigned
    PLA
    CLC
    ADC.b !C3_MulProduct
    STA.b !C3_BikeScrY
    RTS

; $7E:4DA5 — C3Mod_ProjectRival (97 bytes, $4DA5–$4E05)
; The rival's point, as C3Mod_ProjectBike's with the other sign along
; the track: C3_RivalScrX = cos x g + (-sin) x s and C3_RivalScrY =
; sin x g + cos x s, s from the word at C3_RivalSide+1; g =
; C3_FinishGap's low byte instead of C3_RaceGap's only when
; C3_RacePhase is not 0 and C3_Prog9 (read as a word, with $45) is
; not 0. Nothing is done while C3_Unk1444 is not 0 (BEQ).
; Quirk: no CLC before the four ADCs (C3_MulSigned restores P, so each
; carry goes through): s = the side word - $40 + C, C the carry
; C3Mod_ProjectBike's last ADC left (for the X term) or the X sum's
; carry out (for the Y term), and each sum takes the carry out of the
; ADC #$FFC0 before it.
; Callers note: C3Mod_ProjectTask ($4D34).
; Entry: M=0, X=0, DP=0, DB=$00, as C3Mod_ProjectBike; C = its last
;        carry (C3Mod_ProjectTask calls it right after).
; Exit:  M=0, X=0; A = C3_RivalScrY (or C3_Unk1444, not 0); X =
;        |C3_MulB| x the low byte of |C3_MulA| (the last C3_MulSigned's
;        RDMPYL; unchanged when nothing is done); Y unchanged;
;        C3_MulA.. changed.
; Calls: C3_MulSigned (JSL).
C3Mod_ProjectRival:
    LDA.w !C3_Unk1444
    BEQ .project
    RTS
.project:
    LDX.b !C3_ViewCos
    STX.b !C3_MulA
    LDX.b !C3_RaceGap
    LDA.b !C3_RacePhase
    BEQ .gap_x
    LDA.b !C3_Prog9
    BEQ .gap_x
    LDX.b !C3_FinishGap
.gap_x:
    STX.b !C3_MulB
    JSL !C3_MulSigned
    LDA.b !C3_MulProduct
    PHA
    LDX.b !C3_ViewNegSin
    STX.b !C3_MulA
    LDA.b !C3_RivalSide+1               ; C as left (no CLC)
    ADC.w #-!C3_SideMiddle
    STA.b !C3_MulB
    JSL !C3_MulSigned
    PLA
    ADC.b !C3_MulProduct
    STA.b !C3_RivalScrX
    LDX.b !C3_ViewSin
    STX.b !C3_MulA
    LDX.b !C3_RaceGap
    LDA.b !C3_RacePhase
    BEQ .gap_y
    LDA.b !C3_Prog9
    BEQ .gap_y
    LDX.b !C3_FinishGap
.gap_y:
    STX.b !C3_MulB
    JSL !C3_MulSigned
    LDA.b !C3_MulProduct
    PHA
    LDX.b !C3_ViewCos
    STX.b !C3_MulA
    LDA.b !C3_RivalSide+1
    ADC.w #-!C3_SideMiddle
    STA.b !C3_MulB
    JSL !C3_MulSigned
    PLA
    ADC.b !C3_MulProduct
    STA.b !C3_RivalScrY
    RTS

; $7E:4E06 — C3Mod_SizeBike (119 bytes, $4E06–$4E7C)
; The bike's size on the screen, from its projected Y:
;   - C3Mod_Perspective with C3_BikeScrY: A = the line under the bike
;     (bottom), and it starts the divider on (C3_ViewScale x 256) / A's
;     low byte (a 16-bit STA to WRDIVB: HTIMEL gets A's high byte);
;   - C3_BikeScrY = A + C3_TmpF8 + C (C: the borrow of
;     C3Mod_Perspective's SBC, as C3Mod_Mul16 restores P) - the last
;     C3_BikeHeight (SEC);
;   - C3_BikeDepth (page $0B00's var 0) = the quotient (RDDIVL, read
;     four instructions later) AND $FFF; h = C3_BikeDepth / 2, at
;     least $40 (CMP #$40 / BPL: kept when h - $40 has bit 15 clear);
;   - C3_BikeHeight = $0C00 / h (C3Mod_DivHighByte: the dividend's
;     high byte x 256 / h), C3_BikeBottom = C3_BikeScrY + it (CLC);
;     C3_BikeWidth = $1000 / h, low byte;
;   - C3_BikeScrX = ((2 x $8000 / C3_BikeDepth) x C3_BikeScrX (signed,
;     C3Mod_MulSigned16), bits 16-31) + $80 (CLC) - C3_BikeWidth / 2
;     (SBC with C = the bit the LSR shifted out); C3_BikeRight = it +
;     C3_BikeWidth (CLC).
; Callers note: C3Mod_ProjectTask ($4D45 JMP, $4D48).
; Entry: M=0, X=0 (set again after C3Mod_Perspective's SEP #$10), DP=0
;        (the race words, C3Math_*), DB=$00 (the divider and the page
;        words are absolute); C as the caller leaves it (it goes into
;        C3Mod_Perspective's first ADC).
; Exit:  M=0, X=0; A = C3_BikeRight; X as C3Mod_Perspective leaves it
;        (the divisor + 1); Y as it leaves it; C = the last ADC's
;        carry out; C3Math_* and C3_TmpF8 changed.
; Calls: C3Mod_Perspective, C3Mod_DivHighByte, C3Mod_MulSigned16.
C3Mod_SizeBike:
    LDA.b !C3_BikeScrY
    STA.b !C3_TmpF0
    JSR C3Mod_Perspective
    STA.w WRDIVB                        ; and HTIMEL (16-bit)
    ADC.b !C3_TmpF8                     ; C from C3Mod_Perspective's SBC
    SEC
    SBC.b !C3_BikeHeight
    STA.b !C3_BikeScrY
    LDA.w RDDIVL
    AND.w #!C3_DepthMask
    STA.w !C3_BikeDepth
    LSR A
    CMP.w #!C3_DepthMin
    BPL .depth_ok
    LDA.w #!C3_DepthMin
.depth_ok:
    STA.b !C3_TmpFC
    STA.b !C3Math_B
    LDA.w #!C3_SizeHeight
    JSR C3Mod_DivHighByte
    LDA.b !C3Math_Lo
    STA.b !C3_BikeHeight
    CLC
    ADC.b !C3_BikeScrY
    STA.b !C3_BikeBottom
    LDA.b !C3_TmpFC
    STA.b !C3Math_B
    LDA.w #!C3_SizeWidth
    JSR C3Mod_DivHighByte
    LDA.b !C3Math_Lo
    AND.w #!Eng_LowByteMask
    STA.b !C3_BikeWidth
    LDA.w !C3_BikeDepth
    STA.b !C3Math_B
    LDA.w #!C3_SizeDepthX
    JSR C3Mod_DivHighByte
    LDA.b !C3Math_Lo
    ASL A
    STA.b !C3Math_A
    LDA.b !C3_BikeScrX
    STA.b !C3Math_B
    JSR C3Mod_MulSigned16
    LDA.b !C3Math_Hi
    CLC
    ADC.w #!C3_ScreenMidX
    STA.b !C3Math_B
    LDA.b !C3_BikeWidth
    LSR A
    STA.b !C3Math_A
    LDA.b !C3Math_B
    SBC.b !C3Math_A                     ; C = the bit the LSR shifted out
    STA.b !C3_BikeScrX
    CLC
    ADC.b !C3_BikeWidth
    STA.b !C3_BikeRight
    RTS

; $7E:4E7D — C3Mod_SizeRival (110 bytes, $4E7D–$4EEA)
; As C3Mod_SizeBike for the rival (nothing while C3_Unk1444 is not 0,
; BEQ): C3_RivalScrY = A + C3_TmpF8 + C - the last C3_RivalHeight
; (SEC); C3_RivalDepth (page $0B00's var 6) = the quotient AND $FFF;
; h = C3_RivalDepth / 2, at least $40 (the same CMP / BPL);
; C3_RivalWidth = C3_RivalHeight = ($0C00 / h)'s low byte;
; C3_RivalScrX = (the product's bits 16-31) + $80 + C - C3_RivalWidth
; / 2 - (1 - C), C3_RivalRight = it + C3_RivalWidth + C and
; C3_RivalBottom = C3_RivalScrY + C3_RivalHeight + C. Quirk: unlike
; C3Mod_SizeBike there is no CLC before those three ADCs: the + $80
; takes C3Mod_MulSigned16's restored carry (the ASL's, bit 15 of $8000 /
; C3_RivalDepth: set only for a depth of 1), the SBC the LSR's bit,
; the other two the carry out of the add or subtract before.
; Callers note: C3Mod_ProjectTask ($4D42, $4D4B JMP).
; Entry: M=0, X=0, DP=0, DB=$00, as C3Mod_SizeBike (C as the caller
;        leaves it).
; Exit:  M=0, X=0; A = C3_RivalBottom (or C3_Unk1444, not 0, with X, Y
;        and C unchanged); X, Y as C3Mod_Perspective leaves them; C =
;        the last ADC's carry out; C3Math_* and C3_TmpF8 changed.
; Calls: C3Mod_Perspective, C3Mod_DivHighByte, C3Mod_MulSigned16.
C3Mod_SizeRival:
    LDA.w !C3_Unk1444
    BEQ .size
    RTS
.size:
    LDA.b !C3_RivalScrY
    STA.b !C3_TmpF0
    JSR C3Mod_Perspective
    STA.w WRDIVB                        ; and HTIMEL (16-bit)
    ADC.b !C3_TmpF8
    SEC
    SBC.b !C3_RivalHeight
    STA.b !C3_RivalScrY
    LDA.w RDDIVL
    AND.w #!C3_DepthMask
    STA.w !C3_RivalDepth
    LSR A
    CMP.w #!C3_DepthMin
    BPL .depth_ok
    LDA.w #!C3_DepthMin
.depth_ok:
    STA.b !C3Math_B
    LDA.w #!C3_SizeHeight
    JSR C3Mod_DivHighByte
    LDA.b !C3Math_Lo
    AND.w #!Eng_LowByteMask
    STA.b !C3_RivalWidth
    STA.b !C3_RivalHeight
    LDA.w !C3_RivalDepth
    STA.b !C3Math_B
    LDA.w #!C3_SizeDepthX
    JSR C3Mod_DivHighByte
    LDA.b !C3Math_Lo
    ASL A
    STA.b !C3Math_A
    LDA.b !C3_RivalScrX
    STA.b !C3Math_B
    JSR C3Mod_MulSigned16
    LDA.b !C3Math_Hi                    ; C from the ASL (no CLC)
    ADC.w #!C3_ScreenMidX
    STA.b !C3Math_B
    LDA.b !C3_RivalWidth
    LSR A
    STA.b !C3Math_A
    LDA.b !C3Math_B
    SBC.b !C3Math_A
    STA.b !C3_RivalScrX
    ADC.b !C3_RivalWidth
    STA.b !C3_RivalRight
    LDA.b !C3_RivalScrY
    ADC.b !C3_RivalHeight
    STA.b !C3_RivalBottom
    RTS

; $7E:4EEB — C3Mod_Perspective (105 bytes, $4EEB–$4F53)
; The line under a bike on the screen, from its projected Y (C3_TmpF0)
; and the view (page $0A00's scale, distance, horizon, first divisor):
;   - the dividend WRDIVL/H = C3_ViewScale's low byte x 256 (left set
;     for the callers' own division);
;   - t = (C3_ViewDist + ((-Y) >> 8, the high byte after an XBA) + C)
;     AND $FF, C as the caller left it; when t is not 0: k = t +
;     C3_ViewScale's low byte + C (the carry out of that 16-bit ADC),
;     to C3_ScratchF4, and the divisor d for k: from C3_DivisorCache at
;     k's low byte when that byte is not 0 (BNE), else counted up by
;     C3_FindDivisor (DP = DP_CPU, 8-bit X) from C3_DivisorStart's low
;     byte: the first d with (scale x 256) / d below k (unsigned), X
;     returned as d + 1 and kept in the cache. With t = 0, X is
;     whatever it was (its low byte: SEP #$10);
;   - C3_DivisorStart = X - 1 (the next search starts there);
;   - C3_TmpF8 = C3_TmpFE = the horizon - the first divisor - (1 - C)
;     (no SEC: C from the ADC before, or 0 after C3_FindDivisor);
;   - A = bits 16-31 of (X x 256) x ($E0 - C3_TmpF8 - (1 - C))
;     (C3Mod_Mul16; the C of its SBC is the borrow of the one before);
;     C3_TmpF8 is put back after it (C3Mod_Mul16 shifts it), but the
;     product is one too big in bits 8-23 when C3_TmpF8 bit 7 is set
;     (C3Mod_Mul16's quirk).
; Quirk: the cache is indexed by k's low byte though k goes to $1FF,
; and its entries were found from whatever C3_DivisorStart was then;
; C3Mod_ViewTask clears it (C3Mod_ClearDivisorCache) when the scale
; changes.
; Callers note: C3Mod_SizeBike ($4E0A), C3Mod_SizeRival ($4E87).
; Entry: M=0, X=0, DP=0 (set to DP_CPU and back), DB=$00 (the divider,
;        the page words and C3_DivisorCache are absolute); C3_TmpF0 =
;        the bike's projected Y; C as the caller left it.
; Exit:  M=0, X=0 (REP #$10), DP=0; A = the line; X = d + 1 (or, with
;        t = 0, its low byte as it came); Y = k's low byte (or, with
;        t = 0, its own low byte: the SEP #$10 clears the high bytes);
;        C as C3Mod_Mul16's entry (the SBC's borrow); C3_TmpF0, F2,
;        C3_ScratchF4 (with t not 0) and C3Math_* changed, C3_TmpF8 =
;        C3_TmpFE.
; Calls: C3_FindDivisor (JSL), C3Mod_Mul16.
C3Mod_Perspective:
    LDA.w !C3_ScriptPageA+!C3_ViewScale
    AND.w #!Eng_LowByteMask
    STA.b !C3_TmpF2
    XBA
    STA.w WRDIVL                        ; and WRDIVH: the scale x 256
    SEP #$10
    LDA.b !C3_TmpF0
    EOR.w #!Eng_Invert16
    INC A
    XBA
    ADC.w !C3_ScriptPageA+!C3_ViewDist  ; C as the caller left it
    AND.w #!Eng_LowByteMask
    BEQ .line
    ADC.b !C3_TmpF2
    STA.b !C3_ScratchF4                 ; C3_FindDivisor's bound
    TAY
    LDX.w !C3_DivisorCache,Y
    BNE .line
    LDA.w #!DP_CPU
    TCD
    LDX.w !C3_DivisorStart
    STX.b WRDIVB-!DP_CPU
    NOP
    JSL !C3_FindDivisor
    SEP #$20
    LDY.w !C3_ScratchF4
    TXA
    STA.w !C3_DivisorCache,Y
    REP #$20
.line:
    REP #$10
    LDA.w #0
    TCD
    LDA.w !C3_ScriptPageA+!C3_ViewHorizon
    SBC.w !C3_ScriptPageA+!C3_ViewFirstDiv
    STA.b !C3_TmpF8
    STA.b !C3_TmpFE
    TXA
    STA.b !C3_DivisorStart
    DEC.b !C3_DivisorStart
    XBA
    STA.b !C3Math_A
    LDA.w #!C3_LinesShown
    SBC.b !C3_TmpF8
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    LDA.b !C3_TmpFE
    STA.b !C3_TmpF8
    LDA.b !C3Math_Hi
    RTS

; ============================================================
; The race's sprites: the bikes, the HUD, the scaled pictures
; ($4F54–$5260)
; ============================================================
; Each bike is drawn from a scaled picture: a job record (C3_BikeJob,
; C3_RivalJob: 14 bytes, the C3Scale_* arguments from C3Scale_Groups
; on, with a state word where C3Scale_* has a gap: 1 to do, 2 done)
; is scaled in C3Mod_Start's idle loop (C3Mod_ScaleIdle), turned into
; tiles at $0C00 by the generated copy code ($B574) and sent to VRAM
; by C3Mod_TilesNmiTask; the sprite list then shows it.

; $7E:4F54 — C3Mod_DrawTask (89 bytes, $4F54–$4FAC)
; A task: the bikes' sprites and the HUD.
;   - C3_TmpFE = ((angle + $40 + C) / 128 + page $0A00's
;     C3_ViewFacing) x 2 AND $E: the bikes' facing (one of 8), from the
;     view's angle (ADC with the carry as the task is entered: 0 from
;     C3Mod_TaskNext's CPX, unless it is the list's first task; then
;     CLC before the facing's add);
;   - page $0B00's C3_RaceGo 0 (the count-down): C3_AnimFrame = 0;
;   - WRMPYA (a 16-bit store: WRMPYB gets 0, starting a multiply by 0)
;     = .bar's operand ($B8, or $D8 written by C3Mod_Prog0Vars in
;     program 9) - $21 - (1 - C) (no SEC: C is the ASL's bit, 1 only
;     when the facing sum is negative), the HUD bar's length for
;     C3Mod_MarkerX;
;   - when C3_BikeBottom - C3_RivalBottom has bit 15 clear (CMP / BMI:
;     the bike lower on the screen, so nearer; equal included): unless
;     C3_EntryArg bit 6 (BIT), C3Mod_BikeMarker, C3Mod_RivalMarker and
;     C3Mod_DrawHud; then C3Mod_DrawBike and C3Mod_DrawRival (JMP).
;     Else: C3Mod_RivalMarker, C3Mod_BikeMarker and C3Mod_DrawHud
;     (unless bit 6), C3Mod_DrawRival, then it falls into
;     C3Mod_DrawBike. The nearer bike goes first in OAM (in front).
; Callers note: a task added by script opcode $FA at $3F23
;   (C3Mod_Prog0ScriptA) and $4139 (C3Mod_Prog0Start).
; Entry: a task (C3Mod_RunTasks): M=0, X=0, DP=0 (the race words, the
;        sprite builders' C3_OamPos..), DB=$00 (the page words, the
;        multiplier and the module's words are absolute; the sprite
;        builders need a bank with the I/O registers).
; Exit:  as C3Mod_DrawBike or C3Mod_DrawRival leaves them.
; Calls: C3Mod_BikeMarker, C3Mod_RivalMarker, C3Mod_DrawHud,
;   C3Mod_DrawBike, C3Mod_DrawRival (JMP, or falling in).
C3Mod_DrawTask:
    LDA.w !C3_ScriptPageA+!C3_ViewAngle
    ADC.w #!C3_EighthTurn/2             ; C as the task is entered
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    CLC
    ADC.w !C3_ScriptPageA+!C3_ViewFacing
    ASL A
    AND.w #!C3_FacingMask
    STA.b !C3_TmpFE
    LDA.w !C3_ScriptPageB+!C3_RaceGo
    BNE .bar
    STZ.w !C3_ScriptPageA+!C3_AnimFrame
.bar:
    LDA.w #!C3_BarBase                  ; written by C3Mod_Prog0Vars (program 9)
    SBC.w #!C3_BarLeft                  ; C from the ASL
    STA.w WRMPYA                        ; and WRMPYB = 0
    LDA.b !C3_BikeBottom
    CMP.b !C3_RivalBottom
    BMI .rival_first
    LDA.w !C3_EntryArg
    BIT.w #!C3_EntryWipeStart
    BNE .bike_rival
    JSR C3Mod_BikeMarker
    JSR C3Mod_RivalMarker
    JSR C3Mod_DrawHud
.bike_rival:
    JSR C3Mod_DrawBike
    JMP C3Mod_DrawRival
.rival_first:
    LDA.w !C3_EntryArg
    BIT.w #!C3_EntryWipeStart
    BNE .rival_bike
    JSR C3Mod_RivalMarker
    JSR C3Mod_BikeMarker
    JSR C3Mod_DrawHud
.rival_bike:
    JSR C3Mod_DrawRival
                                        ; falls into C3Mod_DrawBike

; $7E:4FAD — C3Mod_DrawBike (154 bytes, $4FAD–$5046)
; The bike's sprite and its next picture:
;   - C3_BikeJob's state 1 (a job waiting): only the sprite. State 2
;     (scaled and turned into tiles): state = 0 and C3_BikeTilesReady +
;     1 (C3Mod_TilesNmiTask sends them); then, for state 2 or 0, a new
;     job: the limit and the rows from C3Mod_BikeLimits /
;     C3Mod_BikeRows by the facing (C3_TmpFE, also C3_TmpF0); the
;     sprite count (C3Mod_BikeSprites' first byte, the last picture's
;     size) from the job's old y step s: below $80 (CMP / BPL: kept
;     below when s - $80 has bit 15 set) C3Mod_BikeCounts' entry, $80-
;     $FF 5 (4 sprites), $100 up 2 (1 sprite); C3_BikeDepth made at
;     least $80 (CMP / BPL, stored back), y step = it / 2;
;     C3_AnimFrame + 1, and on odd values (LSR / BCC) the facing index
;     + $10 (ADC #$F with C = 1: the second frame); the picture
;     C3Mod_BikePics[C3_BikeSteer x 32 + the index] (ADC with C = 0,
;     the ASLs' last bit); groups 4; state 1;
;   - unless C3_BikeHidden (BNE): C3Mod_BikeSprites at C3_BikeScrX /
;     C3_BikeScrY (C3_SprListLarge).
; Callers note: C3Mod_DrawTask ($4F93; and it falls in at $4FAD).
; Entry: M=0, X=0, DP=0, DB=$00 (as C3Mod_DrawTask); C3_TmpFE = the
;        facing.
; Exit:  M=0, X=0; A, X, Y as C3_SprListLarge leaves them, or with
;        C3_BikeHidden set A = it, Y as before and X = the picture
;        index (new-job path) or as on entry (state 1); C3_TmpF0 = the
;        index on the new-job path only (state 1 leaves it).
; Calls: C3_SprListLarge (JSL).
C3Mod_DrawBike:
    LDA.w !C3_BikeJob+!C3_JobState
    CMP.w #!C3_JobWaiting
    BEQ .sprite
    CMP.w #!C3_JobDone
    BNE .new_job
    STZ.w !C3_BikeJob+!C3_JobState
    INC.b !C3_BikeTilesReady
.new_job:
    LDX.b !C3_TmpFE
    STX.b !C3_TmpF0
    LDA.l C3Mod_BikeLimits,X
    STA.w !C3_BikeJob+!C3_JobLimit
    LDA.l C3Mod_BikeRows,X
    STA.w !C3_BikeJob+!C3_JobRows
    LDA.w !C3_BikeJob+!C3_JobYStep
    CMP.w #!C3_StepMid
    BPL .not_near
    LDA.l C3Mod_BikeCounts,X
    BRA .count
.not_near:
    CMP.w #!C3_StepFar
    BPL .far
    LDA.w #!C3_Count4
    BRA .count
.far:
    LDA.w #!C3_Count1
.count:
    SEP #$20
    STA.l C3Mod_BikeSprites
    REP #$20
    LDA.w !C3_BikeDepth
    CMP.w #!C3_DepthNear
    BPL .depth_ok
    LDA.w #!C3_DepthNear
    STA.w !C3_BikeDepth
.depth_ok:
    LSR A
    STA.w !C3_BikeJob+!C3_JobYStep
    INC.w !C3_ScriptPageA+!C3_AnimFrame
    LDA.w !C3_ScriptPageA+!C3_AnimFrame
    LSR A
    BCC .steer
    LDA.b !C3_TmpF0
    ADC.w #!C3_SecondFrame-1            ; C = 1
    STA.b !C3_TmpF0
.steer:
    LDA.b !C3_BikeSteer
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    ADC.b !C3_TmpF0
    TAX
    LDA.l C3Mod_BikePics,X
    STA.w !C3_BikeJob+!C3_JobSrc
    LDA.w #!C3_BikeGroups
    STA.w !C3_BikeJob+!C3_JobGroups
    LDA.w #!C3_JobWaiting
    STA.w !C3_BikeJob+!C3_JobState
.sprite:
    LDA.b !C3_BikeHidden
    BNE .done
    LDA.b !C3_BikeScrX
    STA.b !C3_SprBaseX
    LDA.b !C3_BikeScrY
    STA.b !C3_SprBaseY
    LDA.w #C3Mod_BikeSprites
    JSL !C3_SprListLarge
.done:
    RTS

; $7E:5047 — C3Mod_DrawRival (140 bytes, $5047–$50D2)
; As C3Mod_DrawBike for the rival (C3_RivalJob, C3_RivalTilesReady,
; C3Mod_RivalSprites), with these differences: the y step is the new
; one, C3_RivalDepth / 2 AND $FFF, at least $40 (CMP / BPL; when it is
; raised, $40 is also stored to C3_RivalDepth itself, unhalved; the
; next C3Mod_ProjectTask rewrites it); the count from it: below $80
; (BPL) $0A (9 sprites), $80-$FF 5, $100 up 2; the picture
; C3Mod_RivalPics[the facing index, + $10 when C3_AnimFrame is even:
; LSR / BCS, ADC with C = 0], no steering; the limit $600, rows $30,
; groups 3; unless C3_RivalHidden. C3_AnimFrame is not stepped here.
; Callers note: C3Mod_DrawTask ($4F96 JMP, $4FAA).
; Entry: M=0, X=0, DP=0, DB=$00, as C3Mod_DrawBike; C3_TmpFE = the
;        facing.
; Exit:  M=0, X=0; A, X, Y as C3_SprListLarge leaves them, or with
;        C3_RivalHidden set A = it, Y as before and X = the picture
;        index (new-job path) or as on entry (state 1).
; Calls: C3_SprListLarge (JSL).
C3Mod_DrawRival:
    LDA.w !C3_RivalJob+!C3_JobState
    CMP.w #!C3_JobWaiting
    BEQ .sprite
    CMP.w #!C3_JobDone
    BNE .new_job
    STZ.w !C3_RivalJob+!C3_JobState
    INC.b !C3_RivalTilesReady
.new_job:
    LDA.w !C3_RivalDepth
    LSR A
    AND.w #!C3_DepthMask
    CMP.w #!C3_DepthMin
    BPL .step
    LDA.w #!C3_DepthMin
    STA.w !C3_RivalDepth
.step:
    STA.w !C3_RivalJob+!C3_JobYStep
    LDA.w !C3_RivalJob+!C3_JobYStep
    CMP.w #!C3_StepMid
    BPL .not_near
    LDA.w #!C3_Count9
    BRA .count
.not_near:
    LDA.w !C3_RivalJob+!C3_JobYStep
    CMP.w #!C3_StepFar
    BPL .far
    LDA.w #!C3_Count4
    BRA .count
.far:
    LDA.w #!C3_Count1
.count:
    SEP #$20
    STA.l C3Mod_RivalSprites
    REP #$20
    LDX.b !C3_TmpFE
    LDA.w !C3_ScriptPageA+!C3_AnimFrame
    LSR A
    BCS .picture
    TXA
    ADC.w #!C3_SecondFrame              ; C = 0
    TAX
.picture:
    LDA.l C3Mod_RivalPics,X
    STA.w !C3_RivalJob+!C3_JobSrc
    LDA.w #!C3_RivalLimit
    STA.w !C3_RivalJob+!C3_JobLimit
    LDA.w #!C3_RivalRows
    STA.w !C3_RivalJob+!C3_JobRows
    LDA.w #!C3_RivalGroups
    STA.w !C3_RivalJob+!C3_JobGroups
    LDA.w #!C3_JobWaiting
    STA.w !C3_RivalJob+!C3_JobState
.sprite:
    LDA.b !C3_RivalHidden
    BNE .done
    LDA.b !C3_RivalScrX
    STA.b !C3_SprBaseX
    LDA.b !C3_RivalScrY
    STA.b !C3_SprBaseY
    LDA.w #C3Mod_RivalSprites
    JSL !C3_SprListLarge
.done:
    RTS

; $7E:50D3 — C3Mod_MarkerX (20 bytes, $50D3–$50E6)
; A HUD marker's X from a distance's bytes 1-2 in A: WRMPYB = A / 8
; (its low byte: the laps x 32 + 1/2048ths, wrapping each 8 laps; a
; 16-bit store, so WRDIVL gets A / 8's high byte), times the bar's
; length that C3Mod_DrawTask put in WRMPYA; C3_SprBaseX = .base's
; operand ($B8, or $D8 written by C3Mod_Prog0Vars in program 9) + 6 -
; RDMPYH - 1 (SEC then CLC: C = 0 for the ADC and for the SBC). The
; SBC reads RDMPYH as a word, so JOY1L ($4218) is its high byte:
; C3_SprBaseX's high byte is not used by C3_SprOneSmall's 8-bit add.
; Callers note: C3Mod_RivalMarker ($50F3), C3Mod_BikeMarker ($5102).
; Entry: M=0, X any, DP=0 (C3_SprBaseX), DB=$00 (the multiplier); A =
;        the distance's bytes 1-2; WRMPYA set (C3Mod_DrawTask).
; Exit:  M=0; A = C3_SprBaseX; X, Y unchanged.
C3Mod_MarkerX:
    LSR A
    LSR A
    LSR A
    STA.w WRMPYB                        ; and WRDIVL (16-bit)
.base:
    LDA.w #!C3_BarBase                  ; written by C3Mod_Prog0Vars (program 9)
    SEC
    CLC
    ADC.w #!C3_BarRight
    SBC.w RDMPYH                        ; and JOY1L as the high byte
    STA.b !C3_SprBaseX
    RTS

; $7E:50E7 — C3Mod_MarkerY (10 bytes, $50E7–$50F0)
; A HUD marker's Y: C3_SprBaseY = A / 8 + $C0 (CLC), A = a side word at
; +1 (the high byte, with the byte above it).
; Callers note: C3Mod_RivalMarker ($50F8), C3Mod_BikeMarker ($5107).
; Entry: M=0, X any, DP=0, DB any; A = the side's high-byte word.
; Exit:  M=0; A = C3_SprBaseY; X, Y unchanged.
C3Mod_MarkerY:
    LSR A
    LSR A
    LSR A
    CLC
    ADC.w #!C3_MarkerTop
    STA.b !C3_SprBaseY
    RTS

; $7E:50F1 — C3Mod_RivalMarker (15 bytes, $50F1–$50FF)
; The rival's HUD marker: C3Mod_MarkerX of the word at C3_RivalDist+1,
; C3Mod_MarkerY of the word at C3_RivalSide+1, the sprite
; C3Mod_RivalMarkerSpr through C3Mod_BikeMarker's .draw.
; Callers note: C3Mod_DrawTask ($4F8D, $4FA1).
; Entry: M=0, X=0 (the record's 16-bit LDX), DP=0, DB=$00.
; Exit:  as C3Mod_BikeMarker's .draw.
; Calls: C3Mod_MarkerX, C3Mod_MarkerY, C3Mod_BikeMarker (BRA .draw).
C3Mod_RivalMarker:
    LDA.b !C3_RivalDist+1
    JSR C3Mod_MarkerX
    LDA.b !C3_RivalSide+1
    JSR C3Mod_MarkerY
    LDX.w #C3Mod_RivalMarkerSpr
    BRA C3Mod_BikeMarker_draw

; $7E:5100 — C3Mod_BikeMarker (22 bytes, $5100–$5115)
; The bike's HUD marker, as C3Mod_RivalMarker's with C3_BikeDist+1,
; C3_BikeSide+1 and C3Mod_BikeMarkerSpr; .draw ($510D, also the
; rival's): the sprite (C3_SprOneSmall) only while C3_RacePhase is 0
; (BNE). C3Mod_RaceStepTask writes an RTS (Op_RTS) over .draw when the
; race is lost: no markers after that.
; Callers note: C3Mod_DrawTask ($4F8A, $4FA4). .draw: C3Mod_RivalMarker
;   (BRA).
; Entry: M=0, X=0, DP=0, DB=$00.
; Exit:  M=0, X=0; A = C3_RacePhase or as C3_SprOneSmall leaves it; X =
;        the record; Y = C3_OamPos (or unchanged). With the RTS written
;        over .draw: A = C3_SprBaseY (C3Mod_MarkerY's), X = the record,
;        Y unchanged.
; Calls: C3Mod_MarkerX, C3Mod_MarkerY, C3_SprOneSmall (JSL).
C3Mod_BikeMarker:
    LDA.b !C3_BikeDist+1
    JSR C3Mod_MarkerX
    LDA.b !C3_BikeSide+1
    JSR C3Mod_MarkerY
    LDX.w #C3Mod_BikeMarkerSpr
.draw:
    LDA.b !C3_RacePhase                 ; an RTS is written here when the race is lost
    BNE .done
    JSL !C3_SprOneSmall
.done:
    RTS

; $7E:5116 — C3Mod_DrawHud (155 bytes, $5116–$51B0)
; The HUD:
;   - the boosts left (C3_BoostsLeft, while not 0: BEQ), one icon each
;     from X = $EA leftwards 8 pixels apart at Y = $D0:
;     C3Mod_BoostIcon, but C3Mod_BoostIconLast for the last one drawn
;     (count 1) while C3_BoostTimer is 0 (CMP #1 / BNE, BNE);
;   - C3Mod_HudSprites (C3_SprListLarge) and C3Mod_HudSmall
;     (C3_SprListSmall) at 0, 0;
;   - the distance left, while racing (C3_RacePhase 0, BNE): (8 laps -
;     C3_BikeDist, 32-bit, SEC / SBC) / 512 - .offset's operand ($18
;     at first; SEC), shown as is when it minus $3E9 has bit 15 set
;     (CMP / BMI: $3E8 or less, or bit 15 set, i.e. negative), else 0;
;     0 too after the race; at X $10, Y $0E (C3Mod_DrawNumber);
;   - every 64th frame (C3_RaceFrames + 1 AND $3F = 0) .offset's
;     operand goes down by 1 while it is not 0 (self-modifying: the
;     distance shown starts 24 too low, catching up over 24 x 64
;     frames);
;   - C3_Score made 0 when bit 15 is set (BPL; stored back), and
;     C3_Score / 2 shown at Y $18 (C3Mod_DrawNumber, JMP; X as it
;     left C3_SprBaseX).
; Callers note: C3Mod_DrawTask ($4F90, $4FA7).
; Entry: M=0, X=0, DP=0 (C3_TmpF0.., C3_SprBase*), DB=$00 (the sprite
;        builders; C3Mod_DrawNumber sets its own and leaves $00).
; Exit:  as C3Mod_DrawNumber leaves them (JMP).
; Calls: C3_SprOneSmall, C3_SprListLarge, C3_SprListSmall (JSL),
;   C3Mod_DrawNumber.
C3Mod_DrawHud:
    LDA.w #!C3_IconY
    STA.b !C3_SprBaseY
    LDA.w #!C3_IconX
    STA.b !C3_SprBaseX
    LDA.b !C3_BoostsLeft
    BEQ .lists
    STA.b !C3_TmpF0
.icon:
    LDX.w #C3Mod_BoostIcon
    LDA.b !C3_TmpF0
    CMP.w #1
    BNE .draw_icon
    LDA.b !C3_BoostTimer
    BNE .draw_icon
    LDX.w #C3Mod_BoostIconLast
.draw_icon:
    JSL !C3_SprOneSmall
    LDA.b !C3_SprBaseX
    SEC
    SBC.w #8
    STA.b !C3_SprBaseX
    DEC.b !C3_TmpF0
    BNE .icon
.lists:
    STZ.b !C3_SprBaseY
    STZ.b !C3_SprBaseX
    LDA.w #C3Mod_HudSprites
    JSL !C3_SprListLarge
    LDA.w #C3Mod_HudSmall
    JSL !C3_SprListSmall
    LDA.b !C3_RacePhase
    BNE .no_distance
    LDA.w #0
    SEC
    SBC.b !C3_BikeDist
    STA.b !C3_TmpF0
    LDA.w #!C3_RaceLaps
    SBC.b !C3_BikeDist+2
    STA.b !C3_TmpF2
    LDA.b !C3_TmpF0+1                   ; bits 8-23 of the distance left
    LSR A
    SEC
.offset:
    SBC.w #!C3_HudOffset                ; counted down below
    CMP.w #!C3_HudMax+1
    BMI .distance
.no_distance:
    LDA.w #0
.distance:
    STA.b !C3_TmpF0
    LDA.w #!C3_HudNumberX
    STA.b !C3_SprBaseX
    LDA.w #!C3_HudDistanceY
    STA.b !C3_SprBaseY
    JSR C3Mod_DrawNumber
    LDA.b !C3_RaceFrames
    INC A
    AND.w #!C3_HudEvery-1
    BNE .score
    LDA.l .offset+1
    BEQ .score
    DEC A
    STA.l .offset+1
.score:
    LDA.w #!C3_HudScoreY
    STA.b !C3_SprBaseY
    LDA.b !C3_Score
    BPL .score_ok
    LDA.w #0
    STA.b !C3_Score
.score_ok:
    LSR A
    STA.b !C3_TmpF0
    JMP C3Mod_DrawNumber

; $7E:51B1 — C3Mod_RivalPics (32 bytes, $51B1–$51D0)
; The rival's pictures for C3Mod_DrawRival: the address in bank $7F of
; a picture of 64-byte rows by the facing (8 words), then the second
; frame's (8 more). $8A00-$ADFF point into C3_Prog0PicsB (pack 4's own
; rows), $AE00 and up into C3_Prog0MirrorC (its mirrored rows).
C3Mod_RivalPics:
    dw $8A00, $9C00, $A800, $C000, $AE00, $BA00, $A200, $9600
    dw $9000, $9C00, $A800, $C000, $B400, $BA00, $A200, $9600

; $7E:51D1 — C3Mod_ScaleIdle (35 bytes, $51D1–$51F3)
; The idle routine C3Mod_Prog0 writes over C3Mod_Start's idle call
; ($3024): runs a waiting picture job of the bike and then of the
; rival (C3Mod_ScaleJob for each whose state is 1: CMP #1 / BNE) and
; sets its state to 2 (done).
; Callers note: the idle JSR at $3023 (C3Mod_Start's .wait_exit, its
;   operand written at $3CE4 by C3Mod_Prog0).
; Entry: M=0, X=0, DP=0, DB=$00 (as C3Mod_Start's loop runs: C3Mod_Init
;        and C3_ModuleFrame).
; Exit:  M=0, X=0, DP=0, DB=$00; A = 2 or the rival's state; X, Y as
;        C3Mod_ScaleJob leaves them (or unchanged).
; Calls: C3Mod_ScaleJob.
C3Mod_ScaleIdle:
    LDA.w !C3_BikeJob+!C3_JobState
    CMP.w #!C3_JobWaiting
    BNE .rival
    LDX.w #!C3_BikeJob
    JSR C3Mod_ScaleJob
    STA.w !C3_BikeJob+!C3_JobState
.rival:
    LDA.w !C3_RivalJob+!C3_JobState
    CMP.w #!C3_JobWaiting
    BNE .done
    LDX.w #!C3_RivalJob
    JSR C3Mod_ScaleJob
    STA.w !C3_RivalJob+!C3_JobState
.done:
    RTS

; $7E:51F4 — C3Mod_ScaleJob (45 bytes, $51F4–$5220)
; One picture job: the 14-byte record at X goes to C3Scale_Groups..
; ($1F-$2C, MVN in bank $00); with DB = $7F (PEA $007F / PLB: the $00
; stays for the last PLB), C3Scale_Dest = C3Scale_DestPos = $0200,
; C3Scale_XStep = C3Scale_YStep x 2, and C3_ScaleBitmap scales the
; picture to $7F:0200; then it waits (a loop on C3_TilesPending, which
; C3Mod_TilesNmiTask clears after the last upload), sets
; C3_TilesPending (INC) and runs the generated copy code at $B574
; (C3_BuildCopyCode's: the bitmap at $7F:0200 as 4bpp tiles at
; $0C00-$13FF), keeping DP around it; A = 2 (done).
; Callers note: C3Mod_ScaleIdle ($51DC, $51ED).
; Entry: M=0, X=0 (MVN's 16-bit X and Y), DP=0 (C3Scale_*), DB any (the
;        MVN sets $00); X = the record.
; Exit:  M=0, X=0, DP=0, DB=$00 (the PEA's $00); A = 2; X, Y as the
;        copy code and C3_ScaleBitmap leave them.
; Calls: C3_ScaleBitmap (JSL), the generated code at $B574.
C3Mod_ScaleJob:
    LDY.w #!C3Scale_Groups
    LDA.w #!C3_JobBytes-1
    MVN $00,$00                         ; lint-ok: MVN operands are bank bytes (bank $00)
    PEA.w !Bank7F                       ; PLB takes the $7F; the $00 stays for the last PLB
    PLB
    LDX.w #!C3_BitmapSrc
    STX.b !C3Scale_Dest
    STX.b !C3Scale_DestPos
    LDA.b !C3Scale_YStep
    ASL A
    STA.b !C3Scale_XStep
    JSL !C3_ScaleBitmap
.wait:
    LDA.b !C3_TilesPending
    BNE .wait
    INC.b !C3_TilesPending
    PHD
    JSR !C3_CopyCodeAddr
    PLD
    PLB
    LDA.w #!C3_JobDone
    RTS

; $7E:5221 — C3Mod_TilesNmiTask (64 bytes, $5221–$5260)
; An NMI task: when C3_BikeTilesReady is set (an 8-bit test and clear),
; the tiles at $00:0C00 ($800 bytes, the last picture's) go to VRAM
; word $4000; else when C3_RivalTilesReady is, to $4400; by DMA channel
; 7, two registers (VMDATAL/H), VMAIN = $80; then C3_TilesPending's low
; byte = 0. One upload a frame (the bike's first).
; Callers note: an NMI task added by script opcode $F8 at $3F35
;   (C3Mod_Prog0ScriptA) and $414B (C3Mod_Prog0Start).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X=0 (the 16-bit register
;        pairs), DP=0 (the flags), DB=$00 (absolute registers).
; Exit:  M=1, X=0; with an upload A = $80 (VMAIN and MDMAEN), X =
;        $0C00, Y = $0800; else A = C3_RivalTilesReady (0), X, Y
;        unchanged.
C3Mod_TilesNmiTask:
    LDA.b !C3_BikeTilesReady
    BEQ .rival
    STZ.b !C3_BikeTilesReady
    LDX.w #!C3_BikeTilesVram
    LDY.w #!C3_TilesBytes
    BRA .upload
.rival:
    LDA.b !C3_RivalTilesReady
    BEQ .done
    STZ.b !C3_RivalTilesReady
    LDX.w #!C3_RivalTilesVram
    LDY.w #!C3_TilesBytes
.upload:
    STX.w VMADDL
    STY.w DAS7L
    LDA.b #!DMAP_TwoRegs
    STA.w DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD7
    LDX.w #!C3_TilesBuffer
    STX.w A1T7L
    LDA.b #0
    STA.w A1B7
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    STA.w MDMAEN                        ; the same $80: channel 7
    STZ.b !C3_TilesPending
.done:
    RTS

%C3ModOrg($7E5261)
; $7E:5261 — C3Mod_LampUpload (42 bytes, $5261–$528A)
; Sends the boost lamp's two sprite tiles (C3_BoostTiles, 64 bytes) to
; VRAM word $5180 (the sprites' second tile page, tiles $18-$19 there)
; by DMA channel 7, two registers (VMDATAL/H), VMAIN = $80; the tail of
; C3Mod_HorizonNmiTask, so once a frame in the NMI.
; Callers note: JMP from C3Mod_HorizonNmiTask ($451C).
; Entry: M=1, X=0 (the 16-bit register pairs), DP any, DB=$00 (absolute
;        registers).
; Exit:  M=1, X=0; A = VMAIN_IncAfterHigh (= MDMAEN_Ch7, both $80), X =
;        the tiles' address; Y unchanged; VMADD past the tiles.
C3Mod_LampUpload:
    LDX.w #!C3_LampVram
    STX.w VMADDL
    LDX.w #!C3_BoostTilesBytes
    STX.w DAS7L
    LDA.b #!DMAP_TwoRegs
    STA.w DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD7
    LDX.w #!C3_BoostTiles&$FFFF
    STX.w A1T7L
    LDA.b #bank(!C3_BoostTiles)
    STA.w A1B7
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    STA.w MDMAEN                        ; the same $80: channel 7
    RTS

%C3ModOrg($7E528B)
; ============================================================
; The race's sprite data ($528B–$53BA)
; ============================================================

; $7E:528B — C3Mod_BikePics (96 bytes, $528B–$52EA)
; The bike's pictures for C3Mod_DrawBike: their addresses in bank $7F
; (the 64-byte rows C3Mod_Prog0 built), by C3_BikeSteer (32 bytes
; each), then the frame (16) and the facing (8 words).
C3Mod_BikePics:
    dw $0A00, $3200, $2400, $7200, $5A00, $6C00, $1C00, $2C00   ; steering 0, first frame
    dw $3800, $3200, $5200, $7200, $7800, $6C00, $4A00, $2C00   ; ... second frame
    dw $1000, $3200, $2400, $7200, $6600, $6C00, $1C00, $2C00   ; steering 1
    dw $3E00, $3200, $5200, $7200, $8400, $6C00, $4A00, $2C00
    dw $1600, $3200, $2400, $7200, $6000, $6C00, $1C00, $2C00   ; steering 2
    dw $4400, $3200, $5200, $7200, $7E00, $6C00, $4A00, $2C00

; $7E:52EB — C3Mod_BikeLimits (16 bytes, $52EB–$52FA)
; The bike's C3Scale_SrcLimit by the facing (C3Mod_DrawBike).
C3Mod_BikeLimits:
    dw $0600, $0600, $0620, $0600, $0600, $0600, $0700, $0600

; $7E:52FB — C3Mod_BikeRows (16 bytes, $52FB–$530A)
; The bike's C3Scale_Rows by the facing.
C3Mod_BikeRows:
    dw $0030, $0030, $0031, $0030, $0030, $0030, $0038, $0030

; $7E:530B — C3Mod_BikeCounts (16 bytes, $530B–$531A)
; C3Mod_BikeSprites' count (sprites + 1) by the facing, for a near
; bike: $0D (12 sprites, the top three rows) or $11 (all 16).
C3Mod_BikeCounts:
    dw $000D, $000D, $0011, $000D, $000D, $000D, $0011, $000D

; $7E:531B — C3Mod_BikeSprites (65 bytes, $531B–$535B)
; The bike's sprite list for C3_SprListLarge: a count (sprites + 1,
; written by C3Mod_DrawBike), then 16 records of tile, attribute, X, Y:
; 16x16 sprites in a 64x64 square, tiles $00-$2E of the first page
; (palette 0, priority 3; VRAM word $4000 on,
; where C3Mod_TilesNmiTask puts the bike's picture), the first four
; the top-left 32x32.
C3Mod_BikeSprites:
    db $11
    db $00, $30, $00, $00
    db $02, $30, $10, $00
    db $08, $30, $00, $10
    db $0A, $30, $10, $10
    db $04, $30, $20, $00
    db $06, $30, $30, $00
    db $0C, $30, $20, $10
    db $0E, $30, $30, $10
    db $20, $30, $00, $20
    db $22, $30, $10, $20
    db $24, $30, $20, $20
    db $26, $30, $30, $20
    db $28, $30, $00, $30
    db $2A, $30, $10, $30
    db $2C, $30, $20, $30
    db $2E, $30, $30, $30

; $7E:535C — C3Mod_RivalSprites (37 bytes, $535C–$5380)
; The rival's list: a count (written by C3Mod_DrawRival), then 9
; records: a 48x48 square of 16x16 sprites, tiles $40-$64 (VRAM word
; $4400 on), palette 5.
C3Mod_RivalSprites:
    db $0A
    db $40, $3A, $00, $00
    db $42, $3A, $10, $00
    db $48, $3A, $00, $10
    db $4A, $3A, $10, $10
    db $44, $3A, $20, $00
    db $4C, $3A, $20, $10
    db $60, $3A, $00, $20
    db $62, $3A, $10, $20
    db $64, $3A, $20, $20

; $7E:5381 — C3Mod_Unk5381 (4 bytes, $5381–$5384)
; A sprite record (tile $D1, attribute $3F, at 0, 0) that nothing reads
; (no reference to $5381 was found).
C3Mod_Unk5381:
    db $D1, $3F, $00, $00

; $7E:5385 — C3Mod_BoostIconLast (4 bytes, $5385–$5388)
; The last boost icon while no boost runs (C3Mod_DrawHud): tile $0A of
; the second tile page (attribute bit 0; VRAM word $5000 on), palette
; 2, priority 3.
C3Mod_BoostIconLast:
    db $0A, $35, $00, $00

; $7E:5389 — C3Mod_BoostIcon (4 bytes, $5389–$538C)
; The other boost icons: the same tile, palette 3.
C3Mod_BoostIcon:
    db $0A, $37, $00, $00

; $7E:538D — C3Mod_RivalMarkerSpr (4 bytes, $538D–$5390)
; The rival's HUD marker (C3Mod_RivalMarker): tile $08 of the second
; page, palette 1.
C3Mod_RivalMarkerSpr:
    db $08, $33, $00, $00

; $7E:5391 — C3Mod_BikeMarkerSpr (4 bytes, $5391–$5394)
; The bike's HUD marker (C3Mod_BikeMarker): tile $09 of the second
; page, palette 0.
C3Mod_BikeMarkerSpr:
    db $09, $31, $00, $00

; $7E:5395 — C3Mod_HudSprites (25 bytes, $5395–$53AD)
; The HUD's large sprites (C3Mod_DrawHud, at 0, 0): a count, then 6
; records. In program 9 C3Mod_Prog0Vars writes the count 6 (the last
; record left out) and the X bytes $D8 and $E8 into the third and the
; fourth records ($53A0, $53A4), moving them right by $20.
C3Mod_HudSprites:
    db $07
    db $00, $35, $08, $C8
    db $02, $35, $18, $C8
    db $04, $3F, $B8, $C8
    db $06, $3F, $C8, $C8
    db $0B, $35, $34, $10
    db $0D, $37, $DA, $C8

; $7E:53AE — C3Mod_HudSmall (13 bytes, $53AE–$53BA)
; The HUD's small sprites (C3_SprListSmall): a count, then 3 records;
; program 9 writes the count 1 (none drawn, C3Mod_Prog0Vars).
C3Mod_HudSmall:
    db $04
    db $18, $37, $DE, $CB
    db $19, $37, $E6, $CB
    db $0F, $37, $EA, $C8

%C3ModOrg($7E53BB)
; ============================================================
; Program 4: a mode-7 plane in a field of stars ($53BB–$5977)
; ============================================================

; $7E:53BB — C3Mod_Prog4 (303 bytes, $53BB–$54E9)
; The program of C3Mod_ProgramTable entry 4: a turning mode-7 plane
; (BG1) and a field of stars (sprites), then a large sprite picture.
;   - the mode-7 tiles: pack 15 to $7E:0C00 (Decomp_DestBank 0),
;     unpacked to one pixel a byte at $7F:0200 (C3Mod_UnpackNibbles,
;     Decomp_OutLen bytes; Decomp_OutLen doubled for the DMA) and sent
;     to VRAM's high bytes from word 0 (C3Mod_DmaUnpacked: C3_DmaMode 0,
;     C3_DmaBbad VMDATAH, Decomp_DestBank $7F, Decomp_Dest $0200; VMAIN
;     = $80);
;   - sprite tiles: the raw pack 21 ($60 bytes, C3Mod_CopyRawPack) to
;     $7E:0C00 and pack 22 (4bpp tiles) to $7F:0200, then
;     C3Mod_TileListToVram from VRAM word $4000: tile n of the list
;     (pack 21's bytes) is pack 22's tile n; pack 17 to word $4600
;     (C3Mod_DmaUnpacked, two registers);
;   - the mode-7 map: pack 16 to $7F:0200, spaced into 64-byte rows
;     (C3Mod_SpaceRows: $7F:2200 on); $380 bytes of it from $7F:2200 to
;     VRAM's low bytes from word 0 (VMAIN = 0: + 1 after the low byte),
;     the rest of the map's $4000 cleared ($3C80 bytes from word $380,
;     C3Mod_VramFillLow: a fixed zero to VMDATAL);
;   - the colours: the raw packs 20 ($20 bytes) and 18 ($40 bytes) to
;     C3_PaletteBuf ($7E:2200) and $7E:2300 (C3_RowCount at C3_TmpF0
;     the count), then colour 0 = black;
;   - page $0A00 runs C3Mod_Prog4ScriptA, $0B00 C3Mod_Prog4ScriptB; TM
;     = the sprites, TS = none; page $0A00's script runs once
;     (C3Mod_ScriptTaskA, DB kept around it), DP = 0 again;
;     C3Mod_InitStars; BGMODE = 7, M7SEL = $80 (outside the map:
;     transparent), C3_FadeStep = C3_FadeTimer = 6, BG1SC = $60, BG2SC
;     = $64, BG3SC = $68, BG12NBA = BG34NBA = $55, CGWSEL = add the sub
;     screen.
; Callers note: C3Mod_ProgramTable entry 4 (C3Mod_Start's JSR (table,X)
;   at $300A).
; Entry: M=1, X=0, DP=0, DB=$00 (as C3Mod_Start calls the programs).
; Exit:  M=1, X=0, DP=0, DB=$00; A = CGWSEL_AddSubscreen, X = the BG1SC
;        / BG2SC word; Y as C3_RunScript left it.
; Calls: C3Mod_UnpackPack, C3Mod_UnpackNibbles, C3Mod_DmaUnpacked (JSL),
;   C3Mod_CopyRawPack, C3Mod_TileListToVram, C3Mod_SpaceRows (JSL),
;   C3Mod_VramFillLow, C3Mod_ScriptTaskA, C3Mod_InitStars.
C3Mod_Prog4:
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDX.w #0
    STX.w VMADDL
    STZ.w !Decomp_DestBank
    LDX.w #!C3_TilesBuffer
    STX.w !Decomp_Dest
    LDX.w #15*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDY.w !Decomp_OutLen
    REP #$20
    TYA
    ASL A
    STA.w !Decomp_OutLen
    SEP #$20
    JSR C3Mod_UnpackNibbles
    LDA.b #!Bank7F
    STA.w !Decomp_DestBank
    LDX.w #!C3_BitmapSrc
    STX.w !Decomp_Dest
    STZ.w !C3_DmaMode
    LDA.b #!BBAD_VMDATAH
    STA.w !C3_DmaBbad
    JSL C3Mod_DmaUnpacked
    STZ.w !Decomp_DestBank
    STZ.b !C3_RowCount+1
    LDA.b #!C3_Prog4TileList
    STA.b !C3_RowCount
    LDY.w #!C3_TilesBuffer
    LDX.w #21*!C3_PackPtrBytes
    JSR C3Mod_CopyRawPack
    LDA.b #!Bank7F
    STA.w !Decomp_DestBank
    LDX.w #!C3_BitmapSrc
    STX.w !Decomp_Dest
    LDX.w #22*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_SprTilesVram
    STX.w VMADDL
    JSR C3Mod_TileListToVram
    LDA.b #!DMAP_TwoRegs
    STA.w !C3_DmaMode
    LDA.b #!BBAD_VMDATAL
    STA.w !C3_DmaBbad
    LDX.w #!C3_Prog4SprVram
    STX.w VMADDL
    LDX.w #17*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DmaUnpacked
    LDX.w #0
    STX.w VMADDL
    LDX.w #16*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_SpaceRows
    TDC                                 ; A = 0 (DP = 0)
    STA.w VMAIN
    STA.w DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD7
    LDX.w #!C3_BitmapDest
    STX.w A1T7L
    LDA.b #!Bank7F
    STA.w A1B7
    LDX.w #!C3_Prog4MapBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDX.w #!C3_Prog4MapClear
    JSR C3Mod_VramFillLow
    STZ.w !Decomp_DestBank
    STZ.b !C3_RowCount+1
    LDA.b #!C3_Prog4Colours
    STA.b !C3_RowCount
    LDY.w #!C3_PaletteBuf&$FFFF
    LDX.w #20*!C3_PackPtrBytes
    JSR C3Mod_CopyRawPack
    ASL.b !C3_RowCount
    LDY.w #(!C3_PaletteBuf&$FFFF)+$100
    LDX.w #18*!C3_PackPtrBytes
    JSR C3Mod_CopyRawPack
    TDC
    STA.l !C3_PaletteBuf
    STA.l !C3_PaletteBuf+1
    REP #$20
    LDA.w #C3Mod_Prog4ScriptA
    STA.w !C3_ScriptPageA+!C3Script_Ptr
    LDA.w #C3Mod_Prog4ScriptB
    STA.w !C3_ScriptPageB+!C3Script_Ptr
    LDX.w #!TM_Obj
    STX.w TM                            ; and TS = 0
    PHB
    JSR C3Mod_ScriptTaskA
    PLB
    SEP #$20
    PEA.w 0
    PLD
    JSR C3Mod_InitStars
    LDA.b #!BGMODE_Mode7
    STA.w BGMODE
    LDA.b #!C3_M7SelTransparent
    STA.w M7SEL
    LDX.w #!C3_Prog4Fade
    STX.w !C3_FadeStep                  ; and C3_FadeTimer
    LDX.w #!C3_Prog0Bg1Sc|(!C3_Prog0Bg2Sc<<8)
    STX.w BG1SC                         ; and BG2SC
    LDA.b #!C3_Prog0Bg3Sc
    STA.w BG3SC
    LDA.b #!C3_Prog4Tiles
    STA.w BG12NBA
    STA.w BG34NBA
    LDA.b #!CGWSEL_AddSubscreen
    STA.w CGWSEL
    RTS

; $7E:54EA — C3Mod_TileListToVram (64 bytes, $54EA–$5529)
; Sends tiles by a list: for each of 96 bytes read through WMDATA from
; $7E:0C00 (WMADDH = 0), the 4bpp tile of that number (32 bytes at
; $7F:0200 + n x 32) to VRAM (VMDATAL/H as a word, 16 times, from the
; current VRAM address; VMAIN as the caller set it). The list byte is
; read as a word (WMDATA, then the write-only WMADDL: open bus), and
; AND #$FF keeps the byte. The count is kept
; at $7F:FFFE (C3_TileListLeft, DB = $7F), DP = DP_PPU meanwhile.
; Callers note: C3Mod_Prog4 ($5424).
; Entry: M=1 (M=0 set here), X=0 (16-bit X and Y), DP any (set to
;        DP_PPU, then to 0, not restored), DB = a bank that maps the
;        I/O registers ($00-$3F, $80-$BF: the WMADDL/WMADDH stores come
;        before the PEA; $00 at C3Mod_Prog4's call), then $7F (PEA
;        $007F / PLB; the last PLB takes the $00: DB = $00 at the
;        exit).
; Exit:  M=1, X=0, DP=0, DB=$00; A = 0, X = the last tile's end offset,
;        Y = 0; C3_TileListLeft = 0; WMADD past the list.
C3Mod_TileListToVram:
    LDX.w #!C3_TilesBuffer
    STX.w WMADDL                        ; and WMADDM
    LDA.b #0
    STA.w WMADDH
    PEA.w !Bank7F                       ; PLB takes the $7F; the $00 stays for the last PLB
    PLB
    LDX.w #!C3_Prog4TileList
    STX.w !C3_TileListLeft
    REP #$20
    LDA.w #!DP_PPU
    TCD
.tile:
    LDA.b WMDATA-!DP_PPU                ; a word: WMDATA, then WMADDL (write-only: open bus)
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    TAX
    LDY.w #!C3_TileWords
.word:
    LDA.w !C3_BitmapSrc,X
    STA.b VMDATAL-!DP_PPU               ; and VMDATAH
    INX
    INX
    DEY
    BNE .word
    DEC.w !C3_TileListLeft
    BNE .tile
    LDA.w #0
    TCD
    SEP #$20
    PLB
    RTS

; $7E:552A — C3Mod_Prog4ScriptA (62 bytes, $552A–$5567)
; Page $0A00's first script in program 4: the plane's angle 0
; (C3_ViewAngle), scale $0F00 (var 0), scroll var 1 = -$80 + var 3 and
; var 2 = -$70 + var 4 (C3_PlaneScrollVarX/Y), centre $19, $1B (vars 3
; and 4); the tasks (both script tasks, C3Mod_StarsTask,
; C3Mod_SpinTask, C3Mod_FadeInTask) and the NMI tasks
; (C3Mod_OamUploadTask, C3Mod_PlaneNmiTask); 120 frames later TM = BG1
; and the sprites (opcode $FB), then 54 frames of the scale - $40 (the
; plane comes closer); then it waits for good.
C3Mod_Prog4ScriptA:
    db !C3Op_Set|5 : dw $0000
    db !C3Op_Set|0 : dw $0F00
    db !C3Op_Set|1 : dw -$80
    db !C3Op_Set|2 : dw -$70
    db !C3Op_Set|3 : dw $0019
    db !C3Op_Set|4 : dw $001B
    db !C3Op_AddVar|1, 6                                ; var 1 += var 3
    db !C3Op_AddVar|2, 8                                ; var 2 += var 4
    db !C3Op_TaskAdd : dw C3Mod_ScriptTaskA
    db !C3Op_TaskAdd : dw C3Mod_ScriptTaskB
    db !C3Op_TaskAdd : dw C3Mod_StarsTask
    db !C3Op_TaskAdd : dw C3Mod_SpinTask
    db !C3Op_TaskAdd : dw C3Mod_FadeInTask
    db !C3Op_NmiAdd : dw C3Mod_OamUploadTask
    db !C3Op_NmiAdd : dw C3Mod_PlaneNmiTask
.l5555:
    db !C3Op_LoopYield|1 : dw $0077, .l5555             ; 120 passes
    db !C3Op_Ppu, !Layer_Bg1Obj, TM-!DP_PPU
.l555D:
    db !C3Op_Add|0 : dw -$40
    db !C3Op_LoopYield|0 : dw $0035, .l555D             ; 54 passes
.l5565:
    db !C3Op_JumpYield : dw .l5565

; $7E:5568 — C3Mod_Prog4ScriptB (145 bytes, $5568–$55F8)
; Page $0B00's script in program 4 (its vars: 0 the stars' speed, 1
; and 2 their sideways and up drift, 5 the drift angle): speed -1,
; drift up -1; after 130 frames no drift and the speed up to 7 (+ 1
; every 3 frames: a $92 loop of 2 frames inside a $90 loop that
; yields too); 90 frames later C3Mod_StarDriftTask (speed and
; sideways drift from the drift angle) and the angle $200, + 2 a frame
; for 204 frames (68 x 3), then C3Mod_DriftTurnTask goes on with + 2 a
; frame; the up drift + 1, - 1, + 1 for 8, 16 and 8 steps of 16 frames;
; 52 frames later C3Mod_DriftTurnTask removed, 60 later
; C3Mod_StarDriftTask; page $0A00 moved on to C3Mod_Prog4ZoomOut
; (C3Mod_Prog4ToZoomOut), the speed + 1 every 5 frames 8 times; 60
; frames later C3Mod_Prog4ToEnd (page $0A00 on C3Mod_Prog4End, the
; stars' attribute fixed), vars 0-2 = 0; then it waits for good. A $9x
; loop opcode yields on every pass, the last one too.
C3Mod_Prog4ScriptB:
    db !C3Op_Set|0 : dw -$1
    db !C3Op_Set|2 : dw -$1
.l556E:
    db !C3Op_LoopYield|1 : dw $0081, .l556E             ; 130 passes
    db !C3Op_Set|2 : dw $0000
.l5576:
    db !C3Op_Add|0 : dw $0001
.l5579:
    db !C3Op_LoopYield|2 : dw $0001, .l5579             ; 2 passes
    db !C3Op_LoopYield|0 : dw $0007, .l5576             ; 8 passes
.l5583:
    db !C3Op_LoopYield|1 : dw $0059, .l5583             ; 90 passes
    db !C3Op_TaskAdd : dw C3Mod_StarDriftTask
    db !C3Op_Set|5 : dw $0200
.l558E:
    db !C3Op_Add|5 : dw $0002
    db !C3Op_LoopYield|1 : dw $0043, .l558E             ; 68 passes
    db !C3Op_Loop|0 : dw $0002, .l558E                  ; 3 passes
    db !C3Op_TaskAdd : dw C3Mod_DriftTurnTask
.l559E:
    db !C3Op_Add|2 : dw $0001
.l55A1:
    db !C3Op_LoopYield|2 : dw $000F, .l55A1             ; 16 passes
    db !C3Op_Loop|0 : dw $0007, .l559E                  ; 8 passes
.l55AB:
    db !C3Op_Add|2 : dw -$1
.l55AE:
    db !C3Op_LoopYield|2 : dw $000F, .l55AE             ; 16 passes
    db !C3Op_Loop|0 : dw $000F, .l55AB                  ; 16 passes
.l55B8:
    db !C3Op_Add|2 : dw $0001
.l55BB:
    db !C3Op_LoopYield|2 : dw $000F, .l55BB             ; 16 passes
    db !C3Op_Loop|0 : dw $0007, .l55B8                  ; 8 passes
.l55C5:
    db !C3Op_LoopYield|1 : dw $0033, .l55C5             ; 52 passes
    db !C3Op_TaskRemove : dw C3Mod_DriftTurnTask
.l55CD:
    db !C3Op_LoopYield|1 : dw $003B, .l55CD             ; 60 passes
    db !C3Op_TaskRemove : dw C3Mod_StarDriftTask
    db !C3Op_CallW : dw C3Mod_Prog4ToZoomOut
.l55D8:
    db !C3Op_Add|0 : dw $0001
.l55DB:
    db !C3Op_LoopYield|2 : dw $0003, .l55DB             ; 4 passes
    db !C3Op_LoopYield|0 : dw $0007, .l55D8             ; 8 passes
.l55E5:
    db !C3Op_LoopYield|1 : dw $003B, .l55E5             ; 60 passes
    db !C3Op_CallW : dw C3Mod_Prog4ToEnd
    db !C3Op_Set|0 : dw $0000
    db !C3Op_Set|1 : dw $0000
    db !C3Op_Set|2 : dw $0000
.l55F6:
    db !C3Op_JumpYield : dw .l55F6

; $7E:55F9 — C3Mod_DriftTurnTask (11 bytes, $55F9–$5603)
; A task: page $0B00's C3_DriftAngle + 2 (CLC) each frame (the stars'
; drift turns, C3Mod_StarDriftTask).
; Callers note: a task added by script opcode $FA at $559B
;   (C3Mod_Prog4ScriptB), removed by $F9 at $55CA.
; Entry: a task: M=0, X any, DP any, DB=$00 (absolute).
; Exit:  M=0; A = the new angle; X, Y unchanged.
C3Mod_DriftTurnTask:
    LDA.w !C3_ScriptPageB+!C3_DriftAngle
    CLC
    ADC.w #2
    STA.w !C3_ScriptPageB+!C3_DriftAngle
    RTS

; $7E:5604 — C3Mod_Prog4End (49 bytes, $5604–$5634)
; Page $0A00's last script in program 4 (started by C3Mod_Prog4ToEnd):
; C3Mod_PictureTask added, the scale 0, scroll X -$E0, Y 0; 184 times:
; scroll Y - 1, the scale + 7, a frame, scroll X + 1, the scale + 7
; (two frames each); 20 frames later TM = the sprites only (opcode
; $FB); 60 frames later C3Mod_FadeOutExitTask (the module leaves after
; the fade); then it waits for good.
C3Mod_Prog4End:
    db !C3Op_TaskAdd : dw C3Mod_PictureTask
    db !C3Op_Set|0 : dw $0000
    db !C3Op_Set|1 : dw -$E0
    db !C3Op_Set|2 : dw $0000
.l5610:
    db !C3Op_Add|2 : dw -$1
    db !C3Op_Add|0 : dw $0007
    db !C3Op_Yield
    db !C3Op_Add|1 : dw $0001
    db !C3Op_Add|0 : dw $0007
    db !C3Op_LoopYield|0 : dw $00B7, .l5610             ; 184 passes
.l5622:
    db !C3Op_LoopYield|1 : dw $0013, .l5622             ; 20 passes
    db !C3Op_Ppu, !TM_Obj, TM-!DP_PPU
.l562A:
    db !C3Op_LoopYield|1 : dw $003B, .l562A             ; 60 passes
    db !C3Op_TaskAdd : dw C3Mod_FadeOutExitTask
.l5632:
    db !C3Op_JumpYield : dw .l5632

; $7E:5635 — C3Mod_Prog4ZoomOut (11 bytes, $5635–$563F)
; Page $0A00's script from C3Mod_Prog4ToZoomOut: 54 frames of the scale
; + $40 (the plane moves away); then it waits for good.
C3Mod_Prog4ZoomOut:
    db !C3Op_Add|0 : dw $0040
    db !C3Op_LoopYield|0 : dw $0035, C3Mod_Prog4ZoomOut ; 54 passes
.l563D:
    db !C3Op_JumpYield : dw .l563D

; $7E:5640 — C3Mod_Prog4ToEnd (13 bytes, $5640–$564C)
; A script routine (opcode $x0), also called by code: writes $0080 over
; the BMI at $582E in C3Mod_StarsTask (.colour: $80 is BRA, offset 0),
; so every star gets attribute $02 from then on, and starts page
; $0A00's script at C3Mod_Prog4End (its pointer written directly: the
; other page's, when called from page $0B00's script).
; Callers note: script opcode $F0 at $55EA (C3Mod_Prog4ScriptB); JSR
;   from C3Mod_Prog13 ($8F8B).
; Entry: M=0, X any, DP any, DB = $7E (the stores are absolute: the
;        code's bank for $582E; from the script, C3Mod_ScriptTaskB's
;        PHK / PLB, which C3_RunScript keeps; at $8F8B, C3Mod_Prog13's
;        PEA $007E / PLB).
; Exit:  M=0; A = C3Mod_Prog4End; X, Y unchanged.
C3Mod_Prog4ToEnd:
    LDA.w #!Op_BRA
    STA.w C3Mod_StarsTask_colour        ; BMI -> BRA +0
    LDA.w #C3Mod_Prog4End
    STA.w !C3_ScriptPageA+!C3Script_Ptr
    RTS

; $7E:564D — C3Mod_Prog4ToZoomOut (7 bytes, $564D–$5653)
; A script routine: starts page $0A00's script at C3Mod_Prog4ZoomOut
; (called from page $0B00's script, so the other page).
; Callers note: script opcode $F0 at $55D5 (C3Mod_Prog4ScriptB).
; Entry: M=0, X any, DP any, DB = $7E or $00 (the store is absolute).
; Exit:  M=0; A = C3Mod_Prog4ZoomOut; X, Y unchanged.
C3Mod_Prog4ToZoomOut:
    LDA.w #C3Mod_Prog4ZoomOut
    STA.w !C3_ScriptPageA+!C3Script_Ptr
    RTS

; $7E:5654 — C3Mod_PlaneNmiTask (85 bytes, $5654–$56A8)
; An NMI task: the mode-7 registers from page $0A00 (DP = $0A00): M7A..
; M7D from C3_PlaneMatrix's four words, M7X / M7Y from vars 3 and 4
; (C3_PlaneCentreVarX/Y), BG1HOFS / BG1VOFS from vars 1 and 2
; (C3_PlaneScrollVarX/Y), each written low byte then high byte.
; Callers note: an NMI task added by script opcode $F8 at $5552
;   (C3Mod_Prog4ScriptA); JMP from $9DD6 (M=1, at the end of the NMI-task
;   code from $9DBC; code not matched yet).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X any, DP any (set to
;        $0A00 here, restored by C3Mod_RunNmiTasks), DB=$00 (absolute
;        registers).
; Exit:  M=1, DP = $0A00; A = var 2's high byte; X, Y unchanged.
C3Mod_PlaneNmiTask:
    PEA.w !C3_ScriptPageA
    PLD
    LDA.b !C3_PlaneMatrix
    STA.w M7A
    LDA.b !C3_PlaneMatrix+1
    STA.w M7A
    LDA.b !C3_PlaneMatrix+2
    STA.w M7B
    LDA.b !C3_PlaneMatrix+3
    STA.w M7B
    LDA.b !C3_PlaneMatrix+4
    STA.w M7C
    LDA.b !C3_PlaneMatrix+5
    STA.w M7C
    LDA.b !C3_PlaneMatrix+6
    STA.w M7D
    LDA.b !C3_PlaneMatrix+7
    STA.w M7D
    LDA.b !C3_PlaneCentreVarX
    STA.w M7X
    LDA.b !C3_PlaneCentreVarX+1
    STA.w M7X
    LDA.b !C3_PlaneCentreVarY
    STA.w M7Y
    LDA.b !C3_PlaneCentreVarY+1
    STA.w M7Y
    LDA.b !C3_PlaneScrollVarX
    STA.w BG1HOFS
    LDA.b !C3_PlaneScrollVarX+1
    STA.w BG1HOFS
    LDA.b !C3_PlaneScrollVarY
    STA.w BG1VOFS
    LDA.b !C3_PlaneScrollVarY+1
    STA.w BG1VOFS
    RTS

; $7E:56A9 — C3Mod_SpinTask (40 bytes with C3Mod_PlaneMatrixSet, $56A9–$56D0)
; A task: page $0A00's angle (var 5) + $16 + C (no CLC: the carry as
; the task is entered, 0 from C3Mod_TaskNext's CPX unless it is the
; list's first task), then C3Mod_PlaneMatrixSet ($56B4): with s =
; C3Mod_ScaleByVar0, M7A = M7D = s(C3Mod_Cosine(angle)) = -cos x var 0
; / 256, M7B = s(C3Mod_Sine(angle)) = -sin x var 0 / 256 and M7C =
; its negation (C3_PlaneMatrix, for C3Mod_PlaneNmiTask).
; Sub-entry: C3Mod_PlaneMatrixSet ($56B4).
; Callers note: a task added by script opcode $FA at $5549
;   (C3Mod_Prog4ScriptA). C3Mod_PlaneMatrixSet: JMP from $9AC6 (code
;   not matched yet; DP = $0A00 there, LDA #$0A00 / TCD at $9ABD).
; Entry: a task: M=0, X=0 (C3Mod_Mul16's), DP any (set to $0A00 here,
;        restored by C3Mod_RunTasks), DB any (DP and long reads only).
;        C3Mod_PlaneMatrixSet: M=0, X=0, DP = $0A00, DB any.
; Exit:  M=0, X=0, DP = $0A00; A = M7C's word; X = the angle AND
;        C3_AngleMask (C3Mod_Sine's); Y unchanged; page $0A00's
;        C3Math_* changed.
; Calls: C3Mod_Cosine, C3Mod_Sine, C3Mod_ScaleByVar0.
C3Mod_SpinTask:
    LDA.w #!C3_ScriptPageA
    TCD
    LDA.b !C3_ViewAngle
    ADC.w #!C3_SpinStep                 ; C as the task is entered
    STA.b !C3_ViewAngle
C3Mod_PlaneMatrixSet:                   ; header: see C3Mod_SpinTask
    LDA.b !C3_ViewAngle
    JSR C3Mod_Cosine
    JSR C3Mod_ScaleByVar0
    STA.b !C3_PlaneMatrix               ; M7A
    STA.b !C3_PlaneMatrix+6             ; M7D
    LDA.b !C3_ViewAngle
    JSR C3Mod_Sine
    JSR C3Mod_ScaleByVar0
    STA.b !C3_PlaneMatrix+2             ; M7B
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C3_PlaneMatrix+4             ; M7C
    RTS

; $7E:56D1 — C3Mod_ScaleByVar0 (26 bytes, $56D1–$56EA)
; A x var 0 / 256, signed: the sign of A (its N flag, kept with PHP) is
; taken off, |A| x var 0 (C3Mod_Mul16, in the DP page's C3Math_*), the
; product's bits 8-23 (C3Math_Lo + 1), and the sign put back (EOR /
; INC when N was set). C3Mod_Mul16's quirk applies (one too big in bits
; 8-23 when the page's $F8 has bit 7 set).
; Callers note: C3Mod_SpinTask ($56B9, $56C5).
; Entry: M=0, X=0 (C3Mod_Mul16's), DP = the page of var 0 and C3Math_*
;        ($0A00), DB any; A = the value, N as A sets it (a JSR right
;        after the load).
; Exit:  M=0, X=0; A = the result; P as on entry (PLP), then N and Z
;        from the negation when it ran; X, Y unchanged; C3Math_*
;        changed.
; Calls: C3Mod_Mul16.
C3Mod_ScaleByVar0:
    PHP
    BPL .positive
    EOR.w #!Eng_Invert16
    INC A
.positive:
    STA.b !C3Math_A
    LDA.b !C3_ViewScale
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    LDA.b !C3Math_Lo+1
    PLP
    BPL .done
    EOR.w #!Eng_Invert16
    INC A
.done:
    RTS

; $7E:56EB — C3Mod_PictureTask (18 bytes, $56EB–$56FC)
; A task: draws C3Mod_PictureSprites at X 0, Y $70 (C3_SprListLarge).
; Callers note: a task added by script opcode $FA at $5604
;   (C3Mod_Prog4End).
; Entry: a task: M=0, X=0, DP=0 (C3_SprBase*, C3_OamPos..), DB=$00
;        (C3_SprListLarge's).
; Exit:  M=0, X=0; as C3_SprListLarge leaves them.
; Calls: C3_SprListLarge (JSL).
C3Mod_PictureTask:
    LDA.w #0
    STA.b !C3_SprBaseX
    LDA.w #!C3_PictureY
    STA.b !C3_SprBaseY
    LDA.w #C3Mod_PictureSprites
    JSL !C3_SprListLarge
    RTS

; $7E:56FD — C3Mod_PictureSprites (109 bytes, $56FD–$5769)
; C3Mod_PictureTask's list for C3_SprListLarge: a count (sprites + 1),
; then 27 records of tile, attribute, X, Y: 16x16 sprites in rows 16
; pixels apart, widening from 1 to 6 (a wedge 96 x 112), tile $24
; repeated where the picture is plain.
C3Mod_PictureSprites:
    db $1C
    db $00, $00, $00, $00
    db $02, $00, $00, $10
    db $04, $00, $10, $10
    db $06, $00, $00, $20
    db $08, $00, $10, $20
    db $0A, $00, $20, $20
    db $0C, $00, $00, $30
    db $0E, $00, $10, $30
    db $20, $00, $20, $30
    db $22, $00, $30, $30
    db $24, $00, $00, $40
    db $24, $00, $10, $40
    db $28, $00, $20, $40
    db $2A, $00, $30, $40
    db $2C, $00, $40, $40
    db $24, $00, $00, $50
    db $40, $00, $10, $50
    db $42, $00, $20, $50
    db $44, $00, $30, $50
    db $46, $00, $40, $50
    db $48, $00, $50, $50
    db $24, $00, $00, $60
    db $24, $00, $10, $60
    db $24, $00, $20, $60
    db $4A, $00, $30, $60
    db $4C, $00, $40, $60
    db $4E, $00, $50, $60

; $7E:576A — C3Mod_Unk576A (13 bytes, $576A–$5776)
; An MVN of 32 bytes within bank $7E from X to Y with P and DB kept
; (PHB, PHP, REP #$20, LDA #$1F, MVN, PLP, PLB). Nothing reaches it
; (no call, stored address or script reference to $576A was found).
; Entry: M any (P saved), X=0 (MVN's 16-bit X and Y), DP any, DB any
;        (saved); X = the source, Y = the destination.
; Exit:  P and DB restored; A = $FFFF (its low byte with M=1); X, Y
;        past the 32 bytes.
C3Mod_Unk576A:
    PHB
    PHP
    REP #$20
    LDA.w #!C3_Unk576ABytes-1
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes
    PLP
    PLB
    RTS

; $7E:5777 — C3Mod_InitStars (36 bytes, $5777–$579A)
; Places the 128 stars at random: for star k (X = 4k, 0 to $1FC), its X
; and Y bytes (C3_StarXY, $0C00 + 4k, + 1) from C3Mod_KernelRandom and
; its depth (C3_StarDepth, $0E00 + 4k) a random byte AND $7F; X is also
; stored to C3_ScratchF2 each time (which C3_RandomByte mixes in).
; Callers note: C3Mod_Prog4 ($54BE), C3Mod_Prog10Stars ($8BCB) and
;   C3Mod_Prog13 ($8EBE).
; Entry: M=1 (8-bit stores; C3Mod_KernelRandom at M=1), X=0 (16-bit
;        index), DP any, DB=$00 (absolute RAM and C3_RandomByte's).
; Exit:  M=1, X=0; A = the last depth; X = $200 (C3_StarBytes); Y
;        unchanged; C3_RandSeed and C3_ScratchF2 changed.
; Calls: C3Mod_KernelRandom.
C3Mod_InitStars:
    LDX.w #0
.star:
    JSR C3Mod_KernelRandom
    STA.w !C3_StarXY,X
    JSR C3Mod_KernelRandom
    STA.w !C3_StarXY+1,X
    JSR C3Mod_KernelRandom
    AND.b #!C3_StarDepthMask
    STA.w !C3_StarDepth,X
    STX.w !C3_ScratchF2
    INX
    INX
    INX
    INX
    CPX.w #!C3_StarBytes
    BNE .star
    RTS

; $7E:579B — C3Mod_StarsTask (186 bytes, $579B–$5854)
; A task: moves and draws the stars straight into the OAM shadow, one
; sprite each from C3_OamPos on to the end ($200: the rest of the 128
; low-table slots; the high table is not touched). For star Y (8-bit
; arithmetic, M=1):
;   - its depth + the speed (page $0B00's C3_StarSpeed's low byte) + C:
;     with the speed's bit 7 clear (BMI), the star is kept when that
;     sum - $7F has bit 7 set (8-bit CMP #$7F / BMI: kept for sums
;     $00-$7E and $FF, respawned for $7F-$FE);
;     with it set, kept when the sum has bit 7 clear (BPL); else it
;     gets a new random X and Y (C3Mod_KernelRandom twice) and keeps
;     the sum;
;   - depth = the sum AND $7F; d = depth + $80 + C (C3_StarDivisor);
;     X byte + C3_DriftX's low byte + C, Y byte + C3_DriftY's + C (the
;     carries chain on);
;   - the sprite: tile $60 + d / 8 AND $F (OAM byte 2); X = |X byte| x
;     256 / d (the divider), / 2, its sign put back (EOR / INC), + $80
;     + C (C = the carry the PLP brings back: the carry out of the Y
;     byte's add); Y likewise + $70 + C (the carry out of the X's + $80
;     add); the attribute $32 when
;     the tile - $68 has bit 7 set (CMP #$68 / BMI at .colour: tiles
;     $60-$67), else $02 (C3Mod_Prog4ToEnd writes a BRA +0 over the BMI:
;     $02 always).
; The carries: the first depth add takes the carry as the routine is
; entered: as a task, 0 from C3Mod_TaskNext's CPX unless it is the
; list's first task; by the JMP at $99B2, 1 on both paths there (the
; CMP #$0100's carry when C3_OamPos is $100 or more and BPL is taken,
; else $3870's exit through CPX #4 / BEQ, with nothing after it that
; changes C). Each next star takes the CPY's (0, Y below $200); the + $80 the
; CMP's (the sum >= $7F, unsigned) or the ADC's, or C3Mod_KernelRandom's
; after a new place; the X and Y adds the carry out of the one before.
; Quirk: C3_StarDivisor is C3_Prog9's byte ($44) reused.
; Quirk: d wraps to $00 whenever the depth is $7F and the carry into
; ADC #$80 is 1, and the divider then divides by zero (quotient
; $FFFF). The depth (stored AND $7F) is never above $7F, and a later
; star enters with C = 0 (the CPY's), so the routes are:
;   - re-placed with a sum of $7F (speed bit 7 clear) or $FF (set):
;     the carry is the one C3_RandomByte's last SBC left (through
;     C3Mod_KernelRandom; STA and PLA keep it), 1 when that SBC did
;     not borrow; any star;
;   - speed bit 7 clear, kept sum $FF (CMP carry 1): needs depth $7F,
;     speed $7F and a carry in of 1, so only the first star (the JMP
;     entry, or the list's first task);
;   - speed bit 7 set: speed $FF, depth $7F and a carry in of 1 give
;     $17F, kept (BPL on $7F) with the carry out 1; the first star
;     only, likewise.
; Callers note: a task added by script opcode $FA at $5546
;   (C3Mod_Prog4ScriptA) and $93E6 (script not matched yet); JMP from
;   $99B2 (code not matched yet: the code from $999C first, when
;   C3_OamPos - $100 has bit 15 set (CMP / BPL), calls $3870 and sets
;   C3_OamPos = $100, C3_OamHiPtr = $0910).
; Entry: a task (C3Mod_RunTasks), or the JMP at $99B2 (M=0, C=1; the
;        tail of the task at $999C, so the same DP and DB): M=0 (8-bit
;        set here), X=0 (16-bit index), DP=0 (C3_OamPos,
;        C3_StarDivisor), DB=$00 (the star
;        tables, the OAM shadow, the divider and page $0B00's words are
;        absolute).
; Exit:  M=1, X=0; A = the last star's OAM Y; Y = $200 (C3_StarBytes:
;        the loop ends on Y = $200 exactly, BEQ; C3_OamPos is a multiple
;        of 4); X unchanged; C3_RandSeed changed only when a star is
;        re-placed (C3Mod_KernelRandom).
; Calls: C3Mod_KernelRandom.
C3Mod_StarsTask:
    SEP #$20
    LDY.b !C3_OamPos
.star:
    LDA.w !C3_ScriptPageB+!C3_StarSpeed
    BMI .closer
    ADC.w !C3_StarDepth,Y               ; C as left
    CMP.b #!C3_StarDepthMask
    BMI .place
    BRA .new_place
.closer:
    ADC.w !C3_StarDepth,Y
    BPL .place
.new_place:
    PHA
    JSR C3Mod_KernelRandom
    STA.w !C3_StarXY,Y
    JSR C3Mod_KernelRandom
    STA.w !C3_StarXY+1,Y
    PLA
.place:
    AND.b #!C3_StarDepthMask
    STA.w !C3_StarDepth,Y
    ADC.b #!C3_StarDepthBase
    STA.b !C3_StarDivisor
    LDA.w !C3_ScriptPageB+!C3_DriftX
    ADC.w !C3_StarXY,Y
    STA.w !C3_StarXY,Y
    LDA.w !C3_ScriptPageB+!C3_DriftY
    ADC.w !C3_StarXY+1,Y
    STA.w !C3_StarXY+1,Y
    LDA.w !C3_StarXY,Y
    PHP                                 ; N = the X byte's sign
    REP #$20
    XBA
    AND.w #!C3_HighByteMask
    BPL .x_positive
    EOR.w #!Eng_Invert16
    INC A
.x_positive:
    STA.w WRDIVL                        ; and WRDIVH: |X| x 256
    SEP #$20
    LDA.b !C3_StarDivisor
    STA.w WRDIVB
    LSR A
    LSR A
    LSR A
    AND.b #!C3_NibbleMask
    CLC
    ADC.b #!C3_StarTile0
    STA.w !Oam_LowTable+2,Y             ; the tile
    LDA.w RDDIVL
    LSR A
    PLP
    BPL .x_sign
    EOR.b #!Eng_Invert8
    INC A
.x_sign:
    ADC.b #!C3_StarMidX
    STA.w !Oam_LowTable,Y
    LDA.w !C3_StarXY+1,Y
    PHP
    REP #$20
    XBA
    AND.w #!C3_HighByteMask
    BPL .y_positive
    EOR.w #!Eng_Invert16
    INC A
.y_positive:
    STA.w WRDIVL
    SEP #$20
    LDA.b !C3_StarDivisor
    STA.w WRDIVB
    LDA.w !Oam_LowTable+2,Y
    CMP.b #!C3_StarTileFar
.colour:
    BMI .near                           ; C3Mod_Prog4ToEnd writes BRA +0 here
    LDA.b #!C3_StarAttrFar
    BRA .attribute
.near:
    LDA.b #!C3_StarAttrNear
.attribute:
    STA.w !Oam_LowTable+3,Y
    LDA.w RDDIVL
    LSR A
    PLP
    BPL .y_sign
    EOR.b #!Eng_Invert8
    INC A
.y_sign:
    ADC.b #!C3_StarMidY
    STA.w !Oam_LowTable+1,Y
    INY
    INY
    INY
    INY
    CPY.w #!C3_StarBytes
    BEQ .done
    JMP .star
.done:
    RTS

; $7E:5855 — C3Mod_StarDriftTask (29 bytes, $5855–$5871)
; A task: the stars' speed and sideways drift from page $0B00's
; C3_DriftAngle a: C3_StarSpeed (var 0) = C3Mod_Cosine(a) / 32 (-cos x
; 8 at most; LSR of the word, whose low byte C3Mod_StarsTask reads: the
; shifts do not reach it from the sign bits) and C3_DriftX (var 1) =
; C3Mod_Sine(a) / 32 (-sin).
; Callers note: a task added by script opcode $FA at $5588
;   (C3Mod_Prog4ScriptB), removed by $F9 at $55D2.
; Entry: a task: M=0, X=0 (C3Mod_Sine's TAX), DP any (set to $0B00
;        here, restored by C3Mod_RunTasks), DB any (the table read is
;        long).
; Exit:  M=0, DP = $0B00; A = C3_StarSpeed; X = the angle + C3_QuarterTurn
;        AND C3_AngleMask (C3Mod_Cosine's); Y unchanged.
; Calls: C3Mod_Sine, C3Mod_Cosine.
C3Mod_StarDriftTask:
    PEA.w !C3_ScriptPageB
    PLD
    LDA.b !C3_DriftAngle
    JSR C3Mod_Sine
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !C3_DriftX
    LDA.b !C3_DriftAngle
    JSR C3Mod_Cosine
    LSR A
    LSR A
    LSR A
    LSR A
    LSR A
    STA.b !C3_StarSpeed
    RTS

; $7E:5872 — C3Mod_Atan (134 bytes, $5872–$58F7)
; The angle (1,024 steps per turn) of the vector X, Y (signed words):
;   - the signs to C3_TmpF0 (X) and C3_TmpF2 (Y): 1 when negative
;     (bit 15: BPL), the values made positive;
;   - |X| - 1 below 1 (DEC, then BMI for |X| = 0, BNE for 1): $0100 when
;     Y was negative, else $0300;
;   - else the divider: (|Y| AND $FF) x 256 / (|X| - 1)'s low byte (a
;     division by |X| - 1, not |X|, and of |Y|'s low byte only),
;     waited for with five NOPs; k = the first index from 1 (Y = 2) up
;     where the quotient is below C3Mod_TanTable's entry (CMP / BCC:
;     unsigned), less 1 (k = 63 when none: Y reaches $80); 4k is the
;     angle within the quarter turn (the table's 64 steps x 4);
;   - by the signs (EOR / BEQ, AND / BNE, LDX / BNE): both positive 4k
;     + $200 (CLC), both negative 4k, X negative and Y not $400 - 4k,
;     Y negative and X not $200 - 4k.
; Callers note: C3Mod_CharPolar ($7662).
; Entry: M any (REP #$20 here), X=0 (16-bit X and Y), DP = a page whose
;        C3_TmpF0/F2 the routine may use (0 at C3Mod_CharPolar's), DB
;        = a bank with the CPU registers ($00-$3F, $80-$BF: the divider
;        is absolute; set to $7E with PHK / PLB for the table and back);
;        X, Y = the vector.
; Exit:  M=0, X=0, DB as on entry; A = the angle; X = |X| (or
;        C3_TmpF2 when the signs differ), Y = 2k (|Y| with |X| below
;        2); C3_TmpF0/F2 = the sign flags.
C3Mod_Atan:
    REP #$20
    STZ.b !C3_TmpF0
    TXA
    BPL .x_positive
    EOR.w #!Eng_Invert16
    INC A
    TAX
    INC.b !C3_TmpF0
.x_positive:
    STZ.b !C3_TmpF2
    TYA
    BPL .y_positive
    EOR.w #!Eng_Invert16
    INC A
    TAY
    INC.b !C3_TmpF2
.y_positive:
    TYA
    AND.w #!Eng_LowByteMask
    XBA
    STA.w WRDIVL                        ; and WRDIVH: |Y|'s low byte x 256
    TXA
    DEC A
    BMI .upright
    BNE .divide
.upright:
    LDA.b !C3_TmpF2
    BNE .y_negative
    LDA.w #!C3_AtanUp
    RTS
.y_negative:
    LDA.w #!C3_QuarterTurn
    RTS
.divide:
    SEP #$20
    STA.w WRDIVB                        ; |X| - 1
    NOP
    NOP
    NOP
    NOP
    NOP
    REP #$20
    LDY.w #2
    LDA.w RDDIVL
    PHB
    PHK
    PLB
.search:
    CMP.w C3Mod_TanTable,Y
    BCC .found
    INY
    INY
    CPY.w #!C3_TanTableBytes
    BNE .search
.found:
    PLB
    DEY
    DEY
    LDA.b !C3_TmpF0
    EOR.b !C3_TmpF2
    BEQ .same_signs
    TYA
    ASL A
    LDX.b !C3_TmpF2
    BNE .y_down
    SEC
    SBC.w #!C3_FullTurn
    EOR.w #!Eng_Invert16
    INC A
    RTS
.y_down:
    SEC
    SBC.w #!C3_HalfTurn
    EOR.w #!Eng_Invert16
    INC A
    RTS
.same_signs:
    LDA.b !C3_TmpF0
    AND.b !C3_TmpF2
    BNE .both_negative
    TYA
    ASL A
    CLC
    ADC.w #!C3_HalfTurn
    RTS
.both_negative:
    TYA
    ASL A
    RTS

; $7E:58F8 — C3Mod_TanTable (128 bytes, $58F8–$5977)
; tan(k x 90 / 64 degrees) x 256 for k = 0-63 (k = 32: $FF, 45
; degrees), for C3Mod_Atan's search, which starts at entry 1: entry 0
; is never read.
C3Mod_TanTable:
    dw $0000, $0006, $000C, $0012, $0019, $001F, $0025, $002C
    dw $0032, $0039, $0040, $0046, $004D, $0054, $005B, $0062
    dw $006A, $0071, $0079, $0080, $0088, $0091, $0099, $00A2
    dw $00AB, $00B4, $00BD, $00C7, $00D2, $00DC, $00E8, $00F3
    dw $00FF, $010C, $011A, $0128, $0137, $0148, $0159, $016B
    dw $017F, $0194, $01AB, $01C3, $01DE, $01FC, $021D, $0241
    dw $026A, $0297, $02CB, $0306, $034B, $039D, $03FD, $0473
    dw $0506, $05C3, $06BD, $081B, $0A27, $0D8E, $145A, $28B9

%C3ModOrg($7E5978)
; ============================================================
; Program 2: a mode-7 picture rocking, then mode 2 with a wave
; ($5978–$6247)
; ============================================================

; $7E:5978 — C3Mod_Prog2 (314 bytes, $5978–$5AB1)
; The program of C3Mod_ProgramTable entry 2: one picture, first as a
; rocking mode-7 plane, later (C3Mod_Prog2ToMode2) in mode 2 with a
; wave, and sprites over it.
;   - C3Mod_DestBitmapSrc: the packs go to $7F:0200 (C3_BitmapSrc); VMAIN =
;     $80; pack 24 to VRAM word $4000 (the sprite tiles) and pack 23 to
;     $5000 (C3Mod_DmaUnpacked, two registers from VMDATAL; $5000 is
;     also BG1's and BG2's tiles in mode 2); pack 23's first 160 tiles
;     made mode-7 characters 0-159 (C3Mod_TilesToM7, VRAM's high bytes
;     from word 0); pack 26 to $6400 (BG1's map in mode 2) and pack 25
;     to $6000 (BG2's map), its tile numbers also the mode-7 map
;     (C3Mod_MapToM7, which leaves DMA channel 7 on the zero byte of
;     C3Mod_FillBytes, fixed, BBAD VMDATAL);
;   - VMAIN = $80 again (A = MDMAEN_Ch7 = VMAIN_IncAfterHigh as
;     C3Mod_MapToM7 left it); $0F00 bytes of zero words from VRAM word
;     $6480 (DMAP = fixed source, two registers): BG1's map after its
;     first $80 words;
;   - pack 27 to C3_PaletteWork ($7E:2000: Decomp_DestBank 0 is WRAM
;     bank $7E) and C3Mod_CommitPalette;
;   - page $0A00 runs C3Mod_Prog2Script, once now (C3Mod_ScriptTaskA,
;     DP and DB kept around it);
;   - DP = 0: C3_SlideX = $5A0 for the five groups and C3_SlideStop =
;     $670, $770, $860, $9A0, $A90 (C3Mod_SlideTask); C3_SwingAngle =
;     $F8, C3_SwingX = $D8, C3_SwingY = $82; C3_RockPhase = $14C8,
;     C3_RockSwing = $200; colour $F1 white ($FFFF) in both
;     C3_PaletteWork and C3_PaletteBuf;
;   - DP = DP_PPU: BGMODE = 7, M7SEL = $80 (outside the map:
;     transparent), TM = BG1, TS = the sprites, BG1SC = $65, BG2SC =
;     $60, BG3SC = $70, BG12NBA = $55, CGWSEL = add the sub screen,
;     CGADSUB = add on BG1 and the backdrop, M7X = $0020, M7Y = -$40,
;     BG2HOFS = -$C0 (each written low byte, then high);
;     C3_Brightness = full, C3_FadeStep = C3_FadeTimer = 1;
;   - FdVec_FFEE (PalAnim_StopAll: every palette animation of
;     FieldAnimB stopped), song C3_SongProg2 (C3Mod_PlaySong), then it
;     waits for APUIO3's low nibble to be nonzero (AND / BEQ).
; Callers note: C3Mod_ProgramTable entry 2 (C3Mod_Start's JSR (table,X)
;   at $300A).
; Entry: M=1, X=0, DP=0, DB=$00 (as C3Mod_Start calls the programs).
; Exit:  M=1, X=0, DP = DP_PPU (not set back: C3Mod_Start's next calls
;        take any DP, and C3_ModuleFrame sets 0), DB=$00; A = APUIO3's
;        low nibble (not 0), X = C3_SongArgs (C3Mod_PlaySong's), Y =
;        $0090 (PalAnim_StopAll's).
; Calls: C3Mod_DestBitmapSrc, C3Mod_UnpackPack, C3Mod_DmaUnpacked (JSL),
;   C3Mod_TilesToM7, C3Mod_MapToM7, C3Mod_CommitPalette,
;   C3Mod_ScriptTaskA, FdVec_FFEE (JSL), C3Mod_PlaySong.
C3Mod_Prog2:
    JSR C3Mod_DestBitmapSrc
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDX.w #!C3_SprTilesVram
    STX.w VMADDL
    LDX.w #24*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDA.b #!DMAP_TwoRegs
    STA.w !C3_DmaMode
    LDA.b #!BBAD_VMDATAL
    STA.w !C3_DmaBbad
    JSL C3Mod_DmaUnpacked
    LDX.w #23*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_SprTilesHigh
    STX.w VMADDL
    JSL C3Mod_DmaUnpacked
    LDX.w #0
    STX.w VMADDL
    LDY.w #!C3_Prog2M7Tiles
    JSR C3Mod_TilesToM7
    LDX.w #26*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog2Bg1Map
    STX.w VMADDL
    JSL C3Mod_DmaUnpacked
    LDX.w #25*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog2Bg2Map
    STX.w VMADDL
    JSR C3Mod_MapToM7
    STZ.w !Decomp_DestBank
    STA.w VMAIN                         ; A = MDMAEN_Ch7 = VMAIN_IncAfterHigh
    LDA.b #!DMAP_FixedSource|!DMAP_TwoRegs
    STA.w DMAP7                         ; BBAD7 and A1T7/A1B7 as C3Mod_MapToM7 left them
    LDX.w #!C3_Prog2MapClear
    STX.w VMADDL
    LDX.w #!C3_Prog2MapClearBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDX.w #!C3_PaletteWork&$FFFF
    STX.w !Decomp_Dest
    LDX.w #27*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSR C3Mod_CommitPalette
    REP #$20
    PHD
    LDA.w #C3Mod_Prog2Script
    STA.w !C3_ScriptPageA+!C3Script_Ptr
    PHB
    JSR C3Mod_ScriptTaskA
    PLB
    PLD
    LDA.w #!C3_SlideStop0
    STA.b !C3_SlideStop
    LDA.w #!C3_SlideStop1
    STA.b !C3_SlideStop+2
    LDA.w #!C3_SlideStop2
    STA.b !C3_SlideStop+4
    LDA.w #!C3_SlideStop3
    STA.b !C3_SlideStop+6
    LDA.w #!C3_SlideStop4
    STA.b !C3_SlideStop+8
    LDA.w #!C3_SlideStart
    STA.b !C3_SlideX
    STA.b !C3_SlideX+2
    STA.b !C3_SlideX+4
    STA.b !C3_SlideX+6
    STA.b !C3_SlideX+8
    LDX.w #!C3_SwingAngleStart
    STX.b !C3_SwingAngle
    LDA.w #!C3_SwingXStart
    STA.b !C3_SwingX
    LDA.w #!C3_SwingYStart
    STA.b !C3_SwingY
    LDA.w #!C3_RockPhaseStart
    STA.b !C3_RockPhase
    LDA.w #!C3_RockSwingStart
    STA.b !C3_RockSwing
    LDA.w #!C3_ColourWhite
    STA.l !C3_PaletteBuf+!C3_Prog2WhiteOffset
    STA.l !C3_PaletteWork+!C3_Prog2WhiteOffset
    LDA.w #!DP_PPU
    TCD
    SEP #$20
    LDA.b #!BGMODE_Mode7
    STA.b BGMODE-!DP_PPU
    LDA.b #!C3_M7SelTransparent
    STA.b M7SEL-!DP_PPU
    LDX.w #!TM_Bg1|(!TM_Obj<<8)
    STX.b TM-!DP_PPU                    ; and TS
    LDX.w #!C3_Prog2Bg1Sc|(!C3_Prog2Bg2Sc<<8)
    STX.b BG1SC-!DP_PPU                 ; and BG2SC
    LDA.b #!C3_Prog2Bg3Sc
    STA.b BG3SC-!DP_PPU
    LDA.b #!C3_Prog2Tiles
    STA.b BG12NBA-!DP_PPU
    LDX.w #!CGWSEL_AddSubscreen|(!CGADSUB_AddBg1Backdrop<<8)
    STX.b CGWSEL-!DP_PPU                ; and CGADSUB
    LDA.b #!C3_Prog2M7X&$FF
    STA.b M7X-!DP_PPU
    LDA.b #!C3_Prog2M7X>>8
    STA.b M7X-!DP_PPU
    LDA.b #!C3_Prog2M7Y&$FF
    STA.b M7Y-!DP_PPU
    LDA.b #!C3_Prog2M7Y>>8
    STA.b M7Y-!DP_PPU
    LDA.b #!C3_Prog2Bg2Hofs&$FF
    STA.b BG2HOFS-!DP_PPU
    LDA.b #!C3_Prog2Bg2Hofs>>8
    STA.b BG2HOFS-!DP_PPU
    LDA.b #!C3_BrightnessFull
    STA.w !C3_Brightness
    LDX.w #!C3_Prog2Fade
    STX.w !C3_FadeStep                  ; and C3_FadeTimer
    JSL !FdVec_FFEE
    LDA.b #!C3_SongProg2
    JSR C3Mod_PlaySong
.wait_apu:
    LDA.w APUIO3
    AND.b #!C3_NibbleMask
    BEQ .wait_apu
    RTS

; $7E:5AB2 — C3Mod_MapToM7 (83 bytes, $5AB2–$5B04)
; Sends a pack's 32x32 BG map (at $7F:0200, unpacked by the caller) to
; VRAM with C3Mod_DmaUnpacked as the caller set it up, then makes its
; tile numbers the top-left 32x32 of the mode-7 map: through WMDATA
; (WMADDL/M = $0200; WMADDH, bank $7F, as Decomp_ToWram left it) the
; low byte of each map word to VMDATAL (the attribute byte read and
; dropped), each row of 32 followed by 96 zero bytes (the 128-wide
; map), VMAIN = 0 (+ 1 after the low byte) from word 0; then rows
; 32-63 ($1000 bytes) cleared by DMA channel 7 (fixed source: the zero
; byte of C3Mod_FillBytes, one register, VMDATAL). Rows 64-127 are not
; written.
; Callers note: C3Mod_Prog2 ($59D2) and C3Mod_Prog10M7Scene ($8C7F).
; Entry: M=1, X=0, DP any, DB=$00 (the registers are absolute); the
;        pack unpacked to $7F:0200 (WMADDH = 1 since then);
;        C3_DmaMode, C3_DmaBbad, VMAIN and VMADD set for the first
;        DMA.
; Exit:  M=1, X=0; A = MDMAEN_Ch7, X = C3_M7MapClear, Y = 0; VMAIN =
;        0, VMADD = $2000; WMADD = $7F:0A00; DMA channel 7 as set for
;        the clear.
; Calls: C3Mod_DmaUnpacked (JSL).
C3Mod_MapToM7:
    JSL C3Mod_DmaUnpacked
    LDX.w #!C3_BitmapSrc
    STX.w WMADDL                        ; and WMADDM
    LDA.b #0
    STA.w VMAIN                         ; + 1 after the low byte
    LDX.w #0
    STX.w VMADDL
    LDY.w #!C3_M7MapCells               ; rows
    TYX
.cell:
    LDA.w WMDATA
    STA.w VMDATAL
    LDA.w WMDATA                        ; the attribute byte, dropped
    DEX
    BNE .cell
    LDA.b #0
    LDX.w #!C3_M7MapRest
.blank:
    STA.w VMDATAL
    DEX
    BNE .blank
    LDX.w #!C3_M7MapCells
    DEY
    BNE .cell
    LDX.w #!BBAD_VMDATAL<<8|!DMAP_FixedSource
    STX.w DMAP7                         ; and BBAD7
    LDX.w #C3Mod_FillBytes+1            ; the zero byte
    STX.w A1T7L
    LDA.b #!Bank7E
    STA.w A1B7
    LDX.w #!C3_M7MapClear
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    RTS

; $7E:5B05 — C3Mod_Prog2Script (76 bytes, $5B05–$5B50)
; Page $0A00's script in program 2 (its vars: 0 the mode-7 scale
; C3_RockScale, 1 and 2 BG1's scroll C3_Prog2ScrollX/Y, 6 the wave's
; size C3_WaveSize): the tasks C3Mod_ScriptTaskA, C3Mod_RockTask,
; C3Mod_PalAnimTask, C3Mod_WaveTask and C3Mod_FirstPicTask (with
; C3_NoSoftReset = 1 and C3_FirstPicTimer = 110 poked first), the NMI
; tasks C3Mod_UploadPalette, C3Mod_OamUploadTask, C3Mod_HideSprites,
; C3Mod_RockNmiTask and C3Mod_WaveNmiTask (in that order, so the
; matrix is written after C3Mod_HideSprites' M7A / M7B); var 0 =
; $40, var 6 = 7, var 1 = -$C0, var 0 = $80 (the $40 is overwritten
; before it is read); then var 0 + 1 every 4 frames (three yields and
; the yielding $90 loop), 128 times ($80 to $100: a bigger matrix,
; so the picture gets smaller, down to its own size); 78 frames later
; C3Mod_SwingDrawTask and C3Mod_SwingTask, and it waits (a jump to
; itself) until C3Mod_SwingTask moves it on to C3Mod_Prog2Wave. A $9x
; loop opcode yields on every pass, the last one too.
C3Mod_Prog2Script:
    db !C3Op_TaskAdd : dw C3Mod_ScriptTaskA
    db !C3Op_TaskAdd : dw C3Mod_RockTask
    db !C3Op_TaskAdd : dw C3Mod_PalAnimTask
    db !C3Op_TaskAdd : dw C3Mod_WaveTask
    db !C3Op_Poke8 : dw !C3_NoSoftReset : db 1
    db !C3Op_Poke16 : dw !C3_FirstPicTimer, !C3_FirstPicFrames
    db !C3Op_TaskAdd : dw C3Mod_FirstPicTask
    db !C3Op_NmiAdd : dw C3Mod_UploadPalette
    db !C3Op_NmiAdd : dw C3Mod_OamUploadTask
    db !C3Op_NmiAdd : dw C3Mod_HideSprites
    db !C3Op_NmiAdd : dw C3Mod_RockNmiTask
    db !C3Op_NmiAdd : dw C3Mod_WaveNmiTask
    db !C3Op_Set|0 : dw $0040
    db !C3Op_Set|6 : dw $0007
    db !C3Op_Set|1 : dw -$C0
    db !C3Op_Set|0 : dw $0080
.l5B38:
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Yield
    db !C3Op_Yield
    db !C3Op_Yield
    db !C3Op_LoopYield|0 : dw $007F, .l5B38             ; 128 passes
.l5B43:
    db !C3Op_LoopYield|1 : dw $004D, .l5B43             ; 78 passes
    db !C3Op_TaskAdd : dw C3Mod_SwingDrawTask
    db !C3Op_TaskAdd : dw C3Mod_SwingTask
.l5B4E:
    db !C3Op_JumpYield : dw .l5B4E

; $7E:5B51 — C3Mod_Prog2Wave (72 bytes, $5B51–$5B98)
; Page $0A00's script from the end of the swing (C3Mod_SwingTask): 85
; frames later var 1 = -$100, C3Mod_SlideTask, C3Mod_RockTask
; removed; a frame later mode 2 (C3Mod_Prog2ToMode2); 184 frames
; later var 1 + 2 a frame for 104 frames (BG1 scrolls left); then a
; white flash on colours $B0-$BA that fades out (C3Mod_PalWhitenAnim)
; and C3Mod_SidePicTask; 120
; frames later C3Mod_WaveCountTask (the wave dies down); 120 frames
; later the colour fade (C3Mod_PalFadeAnim) and C3Mod_BottomPicTask;
; 720 frames later C3_Prog2Done = 1 (C3Mod_SkipTask does nothing more)
; and C3Mod_MusicFadeTask (the song and the screen fade out, then the
; module ends); then it waits for good. The C3Op_End after it is
; never reached.
C3Mod_Prog2Wave:
    db !C3Op_LoopYield|1 : dw $0054, C3Mod_Prog2Wave    ; 85 passes
    db !C3Op_Set|1 : dw -$100
    db !C3Op_TaskAdd : dw C3Mod_SlideTask
    db !C3Op_TaskRemove : dw C3Mod_RockTask
    db !C3Op_Yield
    db !C3Op_CallW : dw C3Mod_Prog2ToMode2
.l5B63:
    db !C3Op_LoopYield|1 : dw $00B7, .l5B63             ; 184 passes
.l5B68:
    db !C3Op_Add|1 : dw $0002
    db !C3Op_LoopYield|0 : dw $0067, .l5B68             ; 104 passes
    db !C3Op_CallW : dw C3Mod_PalWhitenAnim
    db !C3Op_TaskAdd : dw C3Mod_SidePicTask
.l5B76:
    db !C3Op_LoopYield|1 : dw $0077, .l5B76             ; 120 passes
    db !C3Op_TaskAdd : dw C3Mod_WaveCountTask
.l5B7E:
    db !C3Op_LoopYield|1 : dw $0077, .l5B7E             ; 120 passes
    db !C3Op_CallW : dw C3Mod_PalFadeAnim
    db !C3Op_TaskAdd : dw C3Mod_BottomPicTask
.l5B89:
    db !C3Op_LoopYield|1 : dw $02CF, .l5B89             ; 720 passes
    db !C3Op_Poke8 : dw !C3_Prog2Done : db 1
    db !C3Op_TaskAdd : dw C3Mod_MusicFadeTask
.l5B95:
    db !C3Op_JumpYield : dw .l5B95
    db !C3Op_End

; $7E:5B99 — C3Mod_SkipTask (38 bytes, $5B99–$5BBE)
; A task: a button skips the rest of program 2. It does nothing while
; C3_Prog2Done or C3_Prog2Skip is not 0 (16-bit LDA / BNE each) or
; while C3_Pad is 0 (16-bit LDA / BEQ: no button held); else, once:
; C3_Prog2Skip = 1 (8-bit INC), C3Mod_MusicFadeTask added (the song
; and the screen fade out, then the module ends), $7F:0060
; (C3_Prog2Skipped) = 1 unless R or L is held (C3_Pad's low byte BIT
; #$30 / BNE: either one set skips the store), and the task ends.
; Callers note: a task: LDX #C3Mod_SkipTask / JSR $395E at $5D51,
;   $5D54 (C3Mod_FirstPicTask).
; Entry: a task (C3Mod_RunTasks): M=0 (8-bit set before the add), X=0
;        (C3Mod_TaskAdd's and C3Mod_TaskEnd's), DP=0 (C3_Prog2Done..
;        and C3_Pad are direct page), DB=$00 (C3Mod_TaskAdd's list;
;        the flag store is long).
; Exit:  RTS with M=0, A = the word tested (C3_Prog2Done or
;        C3_Prog2Skip, not 0, or C3_Pad = 0); else JMP C3Mod_TaskEnd
;        with M=1, A = C3_Pad's low byte or 1.
; Calls: C3Mod_TaskAdd.
C3Mod_SkipTask:
    LDA.b !C3_Prog2Done
    BNE .done
    LDA.b !C3_Prog2Skip
    BNE .done
    LDA.b !C3_Pad
    BEQ .done
    SEP #$20
    INC.b !C3_Prog2Skip
    LDX.w #C3Mod_MusicFadeTask
    JSR C3Mod_TaskAdd
    LDA.b !C3_Pad
    BIT.b #!C3_PadR|!C3_PadL
    BNE .end
    LDA.b #1
    STA.l !C3_Prog2Skipped
.end:
    JMP C3Mod_TaskEnd
.done:
    RTS

; $7E:5BBF — C3Mod_WaveCountTask (16 bytes, $5BBF–$5BCE)
; A task: every 32 frames (C3_FrameCount AND $1F = 0: BNE skips the
; others) page $0A00's C3_WaveSize - 1 (16-bit DEC); at 0 (BNE) the
; task ends. From 7, the wave of C3Mod_WaveTask dies down in 7 steps.
; Callers note: a task added by script opcode $FA at $5B7B
;   (C3Mod_Prog2Wave).
; Entry: a task: M=0, X=0 (C3Mod_TaskEnd's), DP=0 (C3_FrameCount is
;        direct page), DB=$00 (the page's word is absolute).
; Exit:  RTS with M=0, A = C3_FrameCount AND $1F; at 0 JMP
;        C3Mod_TaskEnd.
C3Mod_WaveCountTask:
    LDA.b !C3_FrameCount
    AND.w #!C3_WaveEvery
    BNE .done
    DEC.w !C3_ScriptPageA+!C3_WaveSize
    BNE .done
    JMP C3Mod_TaskEnd
.done:
    RTS

; $7E:5BCF — C3Mod_RockTask (136 bytes, $5BCF–$5C56)
; A task: the mode-7 plane rocks, the swing dying down. With s the
; scale (page $0A00's var 0, C3_RockScale):
;   - p = C3_RockPhase + 7 (CLC); c = C3Mod_Cosine(p) (-cos);
;   - t = $200 (CLC) + (|c| x C3_RockSwing, bits 8-23, LSR twice: / 4)
;     with c's sign put back (PHP / BPL: bit 15 of c; EOR / INC), to
;     C3_TmpFE: within $200 +/- $7F while C3_RockSwing is at most
;     $200;
;   - M7A = M7D (C3_RockMatrix) = C3Mod_Cosine(t) x s, bits 8-23, + 1
;     (no sign handling: -cos of $181-$27F is never negative, so the
;     unsigned C3Mod_Mul16 is right);
;   - M7B = C3Mod_Sine(t) (-sin) x s, bits 8-23, the sign kept as for
;     t (PHP / BPL, |value| into C3Mod_Mul16, EOR / INC after the
;     PLP); M7C = -M7B;
;   - var 2 (C3_Prog2ScrollY, BG1VOFS) = $10000 / s (C3Mod_Div32: the
;     dividend $0001:0000, the divisor s with high word 0), the
;     quotient's low word - $100 (SEC);
;   - C3_RockSwing - 1 (16-bit DEC); at 0 (BNE) back to 1 (INC): it
;     never goes below 1.
; C3Mod_Mul16's quirk applies to its three calls (one too big in bits
; 8-23 when $F8 bit 7 is set): $F8 is C3Math_Q's low byte, last
; frame's quotient (C3Mod_WaveTask's call shares the page too), shifted
; left once by each call.
; Callers note: a task added by script opcode $FA at $5B08
;   (C3Mod_Prog2Script), removed by $F9 at $5B5C (C3Mod_Prog2Wave).
; Entry: a task: M=0, X=0 (C3Mod_Mul16's and C3Mod_Div32's), DP=0
;        (C3_RockPhase.., C3Math_* and C3_TmpFE are direct page),
;        DB=$00 (the page's words are absolute).
; Exit:  M=0, X=0 (C3Mod_Div32's); A = var 2's new value; Y unchanged;
;        C3Math_* and C3_TmpFE changed.
; Calls: C3Mod_Cosine, C3Mod_Sine, C3Mod_Mul16, C3Mod_Div32.
C3Mod_RockTask:
    LDA.b !C3_RockPhase
    CLC
    ADC.w #!C3_RockStep
    STA.b !C3_RockPhase
    JSR C3Mod_Cosine
    PHP
    BPL .phase_positive
    EOR.w #!Eng_Invert16
    INC A
.phase_positive:
    STA.b !C3Math_A
    LDA.b !C3_RockSwing
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    LDA.b !C3Math_Lo+1
    LSR A
    LSR A
    PLP
    BPL .tilt_positive
    EOR.w #!Eng_Invert16
    INC A
.tilt_positive:
    CLC
    ADC.w #!C3_HalfTurn
    STA.b !C3_TmpFE
    JSR C3Mod_Cosine
    STA.b !C3Math_A
    LDA.w !C3_ScriptPageA+!C3_RockScale
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    LDA.b !C3Math_Lo+1
    INC A
    STA.b !C3_RockMatrix                ; M7A
    STA.b !C3_RockMatrix+6              ; M7D
    LDA.b !C3_TmpFE
    JSR C3Mod_Sine
    PHP
    BPL .sine_positive
    EOR.w #!Eng_Invert16
    INC A
.sine_positive:
    STA.b !C3Math_A
    LDA.w !C3_ScriptPageA+!C3_RockScale
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    LDA.b !C3Math_Lo+1
    PLP
    BPL .sine_back
    EOR.w #!Eng_Invert16
    INC A
.sine_back:
    STA.b !C3_RockMatrix+2              ; M7B
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C3_RockMatrix+4              ; M7C
    STZ.b !C3Math_A                     ; the dividend's low word
    STZ.b !C3Math_Hi                    ; the divisor's high word
    LDA.w #1
    STA.b !C3Math_B                     ; the dividend's high word
    LDA.w !C3_ScriptPageA+!C3_RockScale
    STA.b !C3Math_Lo                    ; the divisor
    JSR C3Mod_Div32
    LDA.b !C3Math_Q
    SEC
    SBC.w #!C3_RockScrollBase
    STA.w !C3_ScriptPageA+!C3_Prog2ScrollY
    DEC.b !C3_RockSwing
    BNE .done
    INC.b !C3_RockSwing
.done:
    RTS

; $7E:5C57 — C3Mod_RockNmiTask (65 bytes, $5C57–$5C97)
; An NMI task: M7A-M7D from C3_RockMatrix's four words, BG1HOFS and
; BG1VOFS from page $0A00's vars 1 and 2 (C3_Prog2ScrollX/Y), each
; written low byte, then high byte. It stays on in mode 2, where only
; the scroll counts.
; Callers note: an NMI task added by script opcode $F8 at $5B26
;   (C3Mod_Prog2Script).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X=0, DP=0
;        (C3_RockMatrix is direct page), DB=$00 (the registers and the
;        page's words are absolute).
; Exit:  M=1, X=0; A = var 2's high byte; X, Y unchanged.
C3Mod_RockNmiTask:
    LDA.b !C3_RockMatrix
    STA.w M7A
    LDA.b !C3_RockMatrix+1
    STA.w M7A
    LDA.b !C3_RockMatrix+2
    STA.w M7B
    LDA.b !C3_RockMatrix+3
    STA.w M7B
    LDA.b !C3_RockMatrix+4
    STA.w M7C
    LDA.b !C3_RockMatrix+5
    STA.w M7C
    LDA.b !C3_RockMatrix+6
    STA.w M7D
    LDA.b !C3_RockMatrix+7
    STA.w M7D
    LDA.w !C3_ScriptPageA+!C3_Prog2ScrollX
    STA.w BG1HOFS
    LDA.w !C3_ScriptPageA+!C3_Prog2ScrollX+1
    STA.w BG1HOFS
    LDA.w !C3_ScriptPageA+!C3_Prog2ScrollY
    STA.w BG1VOFS
    LDA.w !C3_ScriptPageA+!C3_Prog2ScrollY+1
    STA.w BG1VOFS
    RTS

; $7E:5C98 — C3Mod_SwingTask (105 bytes, $5C98–$5D00)
; A task: moves C3Mod_SwingDrawTask's pictures along an arc. a =
; C3_SwingAngle - 2 (two DECs); CMP #$70 / BPL: a - $70 with bit 15
; clear (a from $70 up, as a 16-bit difference) goes on, else the
; swing is over: TM = BG1, BG2 and the sprites, TS = none (a 16-bit
; store), page $0A00's script on at C3Mod_Prog2Wave, C3_SwingX = $38,
; C3_SwingY = $3A, and the task ends (a not stored). Going on:
;   - C3_SwingAngle = a; c = C3Mod_Cosine(a) (-cos), kept with PHP;
;     C3_SwingX = |c| x $D8, bits 8-23, negated when c was negative
;     (the PLP's N: BPL), + $FFE0 + C: no CLC, and the PLP brings back
;     the carry C3Mod_Cosine left (C3Mod_Mul16 keeps P): 1 when its
;     index (a + $100, masked) is $200 or more (CPX / BCS, unsigned),
;     that is when c >= 0;
;   - s = C3Mod_Sine(a) (-sin), made positive (BPL / EOR / INC);
;     C3_SwingY = |s| x $C3, bits 8-23, + $FFC0 + C (C = C3Mod_Sine's
;     carry: 1 when a AND $3FF is $200 or more).
; Quirk: the second sign test (BPL) is on the product, which is never
; negative (below $C3), so the sine's sign is lost; for every a this
; task makes ($70-$F6) -sin is negative and its carry 0, as is
; C3Mod_Cosine's (index $170-$1F6). From $F8 the swing runs 68 frames
; and ends on the 69th.
; Callers note: a task added by script opcode $FA at $5B4B
;   (C3Mod_Prog2Script).
; Entry: a task: M=0, X=0 (C3Mod_Sine's TAX, C3Mod_TaskEnd's), DP=0
;        (C3_SwingAngle.., C3Math_* are direct page), DB=$00 (TM and
;        the page's pointer are absolute).
; Exit:  RTS with M=0, A = C3_SwingY, X = a AND C3_AngleMask
;        (C3Mod_Sine's), Y unchanged; or JMP C3Mod_TaskEnd with A =
;        C3_SwingEndY.
; Calls: C3Mod_Cosine, C3Mod_Sine, C3Mod_Mul16.
C3Mod_SwingTask:
    LDA.b !C3_SwingAngle
    DEC A
    DEC A
    CMP.w #!C3_SwingStop
    BPL .swing
    LDA.w #!TM_Bg1Bg2Obj
    STA.w TM                            ; and TS = 0
    LDA.w #C3Mod_Prog2Wave
    STA.w !C3_ScriptPageA+!C3Script_Ptr
    LDA.w #!C3_SwingEndX
    STA.b !C3_SwingX
    LDA.w #!C3_SwingEndY
    STA.b !C3_SwingY
    JMP C3Mod_TaskEnd
.swing:
    STA.b !C3_SwingAngle
    JSR C3Mod_Cosine
    PHP
    BPL .x_positive
    EOR.w #!Eng_Invert16
    INC A
.x_positive:
    STA.b !C3Math_A
    LDA.w #!C3_SwingRadiusX
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    LDA.b !C3Math_Lo+1
    PLP
    BPL .x_sign
    EOR.w #!Eng_Invert16
    INC A
.x_sign:
    ADC.w #!C3_SwingOffsetX             ; C as C3Mod_Cosine left it
    STA.b !C3_SwingX
    LDA.b !C3_SwingAngle
    JSR C3Mod_Sine
    BPL .y_positive
    EOR.w #!Eng_Invert16
    INC A
.y_positive:
    STA.b !C3Math_A
    LDA.w #!C3_SwingRadiusY
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    LDA.b !C3Math_Lo+1
    BPL .y_sign                         ; the product's sign: always taken
    EOR.w #!Eng_Invert16
    INC A
.y_sign:
    ADC.w #!C3_SwingOffsetY             ; C as C3Mod_Sine left it
    STA.b !C3_SwingY
    RTS

; $7E:5D01 — C3Mod_SwingDrawTask (31 bytes, $5D01–$5D1F)
; A task: draws C3Mod_SwingPicA at C3_SwingX, C3_SwingY and
; C3Mod_SwingPicB $40 lower (CLC), small sprites (C3_SprListSmall).
; Callers note: a task added by script opcode $FA at $5B48
;   (C3Mod_Prog2Script).
; Entry: a task: M=0, X=0 (C3_SprListSmall's), DP=0 (C3_SwingX..,
;        C3_SprBase* are direct page), DB=$00 (C3_SprListSmall's).
; Exit:  M=0, X=0; as C3_SprListSmall leaves them.
; Calls: C3_SprListSmall (JSL).
C3Mod_SwingDrawTask:
    LDA.b !C3_SwingX
    STA.b !C3_SprBaseX
    LDA.b !C3_SwingY
    STA.b !C3_SprBaseY
    LDA.w #C3Mod_SwingPicA
    JSL !C3_SprListSmall
    LDA.b !C3_SwingY
    CLC
    ADC.w #!C3_SwingPicBGap
    STA.b !C3_SprBaseY
    LDA.w #C3Mod_SwingPicB
    JSL !C3_SprListSmall
    RTS

; $7E:5D20 — C3Mod_SidePicTask (18 bytes, $5D20–$5D31)
; A task: draws C3Mod_SidePic at X $3A, Y $64 (C3_SprListSmall).
; Callers note: a task added by script opcode $FA at $5B73
;   (C3Mod_Prog2Wave).
; Entry: a task: M=0, X=0, DP=0 (C3_SprBase*), DB=$00
;        (C3_SprListSmall's).
; Exit:  M=0, X=0; as C3_SprListSmall leaves them.
; Calls: C3_SprListSmall (JSL).
C3Mod_SidePicTask:
    LDA.w #!C3_SidePicY
    STA.b !C3_SprBaseY
    LDA.w #!C3_SidePicX
    STA.b !C3_SprBaseX
    LDA.w #C3Mod_SidePic
    JSL !C3_SprListSmall
    RTS

; $7E:5D32 — C3Mod_FirstPicTask (43 bytes, $5D32–$5D5C)
; A task: draws C3Mod_FirstPic at X $90, Y $B0 (large sprites,
; C3_SprListLarge), then C3_FirstPicTimer - 1 (16-bit DEC): at 0 (BNE)
; the task ends; at $3C (CMP / BNE: equal) C3Mod_SkipTask is added and
; C3_NoSoftReset = 0 (the soft reset allowed again). From the script's
; 110 the picture is drawn for 110 frames and the skip is on from the
; 51st.
; Callers note: a task added by script opcode $FA at $5B1A
;   (C3Mod_Prog2Script).
; Entry: a task: M=0, X=0 (C3_SprListLarge's, C3Mod_TaskAdd's), DP=0
;        (C3_FirstPicTimer, C3_SprBase* are direct page), DB=$00
;        (C3_SprListLarge's; C3_NoSoftReset is absolute).
; Exit:  RTS with M=0, A = C3_FirstPicTimer, or with M=1 after the
;        add (A = C3Mod_SkipTask, X its offset in C3_TaskList); at 0
;        JMP C3Mod_TaskEnd.
; Calls: C3_SprListLarge (JSL), C3Mod_TaskAdd.
C3Mod_FirstPicTask:
    LDA.w #!C3_FirstPicX
    STA.b !C3_SprBaseX
    LDA.w #!C3_FirstPicY
    STA.b !C3_SprBaseY
    LDA.w #C3Mod_FirstPic
    JSL !C3_SprListLarge
    DEC.b !C3_FirstPicTimer
    BNE .count
    JMP C3Mod_TaskEnd
.count:
    LDA.b !C3_FirstPicTimer
    CMP.w #!C3_SkipFrom
    BNE .done
    LDX.w #C3Mod_SkipTask
    JSR C3Mod_TaskAdd
    SEP #$20
    STZ.w !C3_NoSoftReset
.done:
    RTS

; $7E:5D5D — C3Mod_SlidePics (10 bytes, $5D5D–$5D66)
; C3Mod_SlideTask's five pictures (small sprite lists), by group.
C3Mod_SlidePics:
    dw C3Mod_SlidePic0, C3Mod_SlidePic1, C3Mod_SlidePic2, C3Mod_SlidePic3
    dw C3Mod_SlidePic4

; $7E:5D67 — C3Mod_SlideSteps (10 bytes, $5D67–$5D70)
; Their speeds in sixteenths of a pixel a frame, by group.
C3Mod_SlideSteps:
    dw $0004, $0009, $000E, $0014, $0018

; $7E:5D71 — C3Mod_SlideTask (54 bytes, $5D71–$5DA6)
; A task: five pictures slide right from X 90 into place. For each
; group k = 0-4 (X = 2k; CPX #$0A / BNE: ends at 10 exactly):
; x = C3_SlideX[k] + C3Mod_SlideSteps[k] (CLC); CMP C3_SlideStop[k] /
; BMI: x is kept when x - the stop has bit 15 set (below it, as a
; 16-bit difference), else x = the stop; stored back; C3_SprBaseX =
; (x / 16) AND $FF (four LSRs), C3_SprBaseY = $52 (once, before the
; loop), and C3Mod_SlidePics[k] drawn (C3_SprListSmall, X kept on the
; stack). The stops are 103, 119, 134, 154 and 169 pixels; the task
; is never removed.
; Callers note: a task added by script opcode $FA at $5B59
;   (C3Mod_Prog2Wave).
; Entry: a task: M=0, X=0, DP=0 (C3_SprBase* are direct page), DB=$00
;        (C3_SlideX and C3_SlideStop are indexed absolute words at
;        $0046 / $0050, as C3Mod_Prog2 set them with DP = 0; the tables
;        are read long).
; Exit:  M=0, X=0; X = $0A; A, Y as C3_SprListSmall leaves them.
; Calls: C3_SprListSmall (JSL).
C3Mod_SlideTask:
    LDA.w #!C3_SlideY
    STA.b !C3_SprBaseY
    LDX.w #0
.group:
    LDA.w !C3_SlideX,X
    CLC
    ADC.l C3Mod_SlideSteps,X
    CMP.w !C3_SlideStop,X
    BMI .keep
    LDA.w !C3_SlideStop,X
.keep:
    STA.w !C3_SlideX,X
    LSR A
    LSR A
    LSR A
    LSR A
    AND.w #!Eng_LowByteMask
    STA.b !C3_SprBaseX
    LDA.l C3Mod_SlidePics,X
    PHX
    JSL !C3_SprListSmall
    PLX
    INX
    INX
    CPX.w #!C3_SlideBytes
    BNE .group
    RTS

; $7E:5DA7 — C3Mod_Prog2ToMode2 (13 bytes, $5DA7–$5DB3)
; A script routine (opcode $x0, C3Mod_CallW): BGMODE = 2 (BG1 and BG2
; 4bpp, BG3's map the offset-per-tile table) with a 16-bit long store
; that also writes MOSAIC ($2106) = 0, and var 2 of the script's page
; (C3_Prog2ScrollY, BG1VOFS) = -$47.
; Callers note: script opcode $F0 at $5B60 (C3Mod_Prog2Wave).
; Entry: M=0, X any, DP = the script's page ($0A00: var 2 is direct
;        page), DB any (the register store is long).
; Exit:  M=0; A = C3_Prog2Mode2Y; X, Y unchanged.
C3Mod_Prog2ToMode2:
    LDA.w #!C3_BgMode2NoMosaic
    STA.l BGMODE                        ; and MOSAIC = 0
    LDA.w #!C3_Prog2Mode2Y
    STA.b !C3_Prog2ScrollY
    RTS

; $7E:5DB4 — C3Mod_PalFadeAnim (53 bytes, $5DB4–$5DE8)
; A script routine: sets FieldAnimB record 0 (run each frame by
; C3Mod_PalAnimTask's PalAnim_TickAll): .Unk0 = $50 (kind 5,
; PalAnim_Fade), colours $C0-$CF (.Unk1 = $C0, .Unk2 = 16), .Unk3 =
; 4, .Unk4 = 0, every frame (.Unk5 = 1), .Unk6 = 0, level .Unk7 = 0,
; target .Unk8 = $FF. Quirk-like: PEA $7E00 pushes $7E then $00, so the
; first PLB takes $00 (DB = $00 for the stores) and the last one $7E:
; DB = $7E at the exit, whatever it was.
; Callers note: script opcode $F0 at $5B83 (C3Mod_Prog2Wave), $637A
;   (C3Mod_Prog7Script) and $63BF (C3Mod_Prog8Script).
; Entry: M=0 (8-bit set here), X any, DP any, DB any (set to $00, then
;        $7E: see above).
; Exit:  M=0, DB = $7E; A's low byte $FF; X, Y unchanged.
C3Mod_PalFadeAnim:
    SEP #$20
    PEA.w !Bank7E<<8
    PLB
    LDA.b #!C3_FadeAnimKind
    STA.w FieldAnimB.Unk0
    LDA.b #!C3_FadeAnimFirst
    STA.w FieldAnimB.Unk1
    LDA.b #!C3_FadeAnimCount
    STA.w FieldAnimB.Unk2
    LDA.b #4
    STA.w FieldAnimB.Unk3
    STZ.w FieldAnimB.Unk4
    LDA.b #1
    STA.w FieldAnimB.Unk5
    LDA.b #0
    STA.w FieldAnimB.Unk6
    LDA.b #0
    STA.w FieldAnimB.Unk7
    LDA.b #!C3_FadeAnimTarget
    STA.w FieldAnimB.Unk8
    PLB
    REP #$20
    RTS

; $7E:5DE9 — C3Mod_PalWhitenAnim (53 bytes, $5DE9–$5E1D)
; As C3Mod_PalFadeAnim: FieldAnimB record 0 = .Unk0 $40 (kind 4,
; PalAnim_FadeWhite), colours $B0-$BA (.Unk1 = $B0, .Unk2 = 11), .Unk3
; = 2, .Unk4 = 0, every frame (.Unk5 = 1), red and green lightened
; (.Unk6 = 3), level .Unk7 = $80, target .Unk8 = 0 (a white flash
; that fades out); DB = $7E at the exit the same way.
; Callers note: script opcode $F0 at $5B70 (C3Mod_Prog2Wave).
; Entry: M=0 (8-bit set here), X any, DP any, DB any.
; Exit:  M=0, DB = $7E; A's low byte 0; X, Y unchanged.
C3Mod_PalWhitenAnim:
    SEP #$20
    PEA.w !Bank7E<<8
    PLB
    LDA.b #!C3_WhitenAnimKind
    STA.w FieldAnimB.Unk0
    LDA.b #!C3_WhitenAnimFirst
    STA.w FieldAnimB.Unk1
    LDA.b #!C3_WhitenAnimCount
    STA.w FieldAnimB.Unk2
    LDA.b #2
    STA.w FieldAnimB.Unk3
    STZ.w FieldAnimB.Unk4
    LDA.b #1
    STA.w FieldAnimB.Unk5
    LDA.b #3
    STA.w FieldAnimB.Unk6
    LDA.b #!C3_WhitenAnimLevel
    STA.w FieldAnimB.Unk7
    LDA.b #0
    STA.w FieldAnimB.Unk8
    PLB
    REP #$20
    RTS

; $7E:5E1E — C3Mod_BottomPicTask (30 bytes, $5E1E–$5E3B)
; A task: draws C3Mod_BottomPicA at X $78 and C3Mod_BottomPicB at X
; $B8, both at Y $D0 (C3_SprListSmall).
; Callers note: a task added by script opcode $FA at $5B86
;   (C3Mod_Prog2Wave).
; Entry: a task: M=0, X=0, DP=0 (C3_SprBase*), DB=$00
;        (C3_SprListSmall's).
; Exit:  M=0, X=0; as C3_SprListSmall leaves them.
; Calls: C3_SprListSmall (JSL).
C3Mod_BottomPicTask:
    LDA.w #!C3_BottomPicY
    STA.b !C3_SprBaseY
    LDA.w #!C3_BottomPicAX
    STA.b !C3_SprBaseX
    LDA.w #C3Mod_BottomPicA
    JSL !C3_SprListSmall
    LDA.w #!C3_BottomPicBX
    STA.b !C3_SprBaseX
    LDA.w #C3Mod_BottomPicB
    JSL !C3_SprListSmall
    RTS

; $7E:5E3C — C3Mod_TilesToM7 (24 bytes, $5E3C–$5E53)
; Makes mode-7 characters of Y SNES tiles at $7F:0200 on: each tile by
; C3Mod_Tile4ToM7 (64 pixel bytes to VMDATAH), then X past it (+ 16
; after the converter's 16: 32 bytes a 4bpp tile). Self-modifying:
; C3Mod_Prog10M7Scene ($8C5D / $8C63) writes C3Mod_Tile8ToM7 over the
; JSR's operand (.convert + 1) and ($8C69) $30 over the step's low
; byte (.step + 1: 16 + $30 = 64 bytes an 8bpp tile), for good.
; Callers note: C3Mod_Prog2 ($59B3) and C3Mod_Prog10M7Scene ($8C70).
; Entry: M=1, X=0 (16-bit X, Y), DP = a page whose C3_TileRow.. bytes
;        the converter may use, with low byte 0 (C3Mod_Tile4ToM7's
;        TDC; 0 at both calls), DB any (set to $7F with PEA $007F /
;        PLB; the last PLB takes the $00: DB = $00 at the exit); Y =
;        the tile count (not 0); VMADD at the first character's word,
;        VMAIN = $80 (+ 1 after the high byte).
; Exit:  M=1, X=0, DB=$00; A = X (the TAX's word: low byte in A, high
;        in B), X = $0200 + the count x 32 (x 64 when patched), Y = 0.
; Calls: C3Mod_Tile4ToM7 (or C3Mod_Tile8ToM7, patched).
C3Mod_TilesToM7:
    PEA.w !Bank7F                       ; PLB takes the $7F; the $00 stays for the last PLB
    PLB
    LDX.w #!C3_BitmapSrc
.convert:
    JSR C3Mod_Tile4ToM7                 ; C3Mod_Prog10M7Scene writes C3Mod_Tile8ToM7 here
    REP #$21
    TXA
.step:
    ADC.w #!C3_Tile4Skip                ; C3Mod_Prog10M7Scene writes $30 here
    TAX
    SEP #$20
    DEY
    BNE .convert
    PLB
    RTS

; $7E:5E54 — C3Mod_Tile4ToM7 (164 bytes, $5E54–$5EF7)
; One 4bpp tile at X (DB's bank: planes 0-1 interleaved from X, 2-3
; from X + 16) to 64 mode-7 pixels: for each of its 8 rows the four
; plane bytes go to C3_TileRow (+0 to +3: planes 0, 1, 2, 3), X + 2,
; then each pixel, left first, is A = 0 (TDC: DP's low byte) with the
; top bits of planes 3, 2, 1, 0 shifted in (ASL / ROL), written to
; VMDATAH (a long store: DB is the tiles' bank). C3_TileRowsLeft
; counts the rows (DEC / BEQ; the loop is a JMP, too long for a
; branch).
; Callers note: C3Mod_TilesToM7 ($5E43, the JSR that $8C5D / $8C63,
;   C3Mod_Prog10M7Scene, may patch).
; Entry: M=1, X=0 (16-bit index), DP = C3_TileRow's page with low byte
;        0 (0 at the calls), DB = the tiles' bank ($7F); X = the tile.
; Exit:  M=1, X=0; A = the last pixel; X = the tile + 16; Y unchanged;
;        C3_TileRowsLeft = 0.
C3Mod_Tile4ToM7:
    LDA.b #8
    STA.b !C3_TileRowsLeft
.row:
    REP #$20
    LDA.w !Eng_PtrBase,X
    STA.b !C3_TileRow                   ; planes 0 and 1
    LDA.w !Eng_PtrBase+!C3_TilePlanes23,X
    STA.b !C3_TileRow+2                 ; planes 2 and 3
    INX
    INX
    SEP #$20
    %C3ModPixel4()
    %C3ModPixel4()
    %C3ModPixel4()
    %C3ModPixel4()
    %C3ModPixel4()
    %C3ModPixel4()
    %C3ModPixel4()
    %C3ModPixel4()
    DEC.b !C3_TileRowsLeft
    BEQ .done
    JMP .row
.done:
    RTS

; $7E:5EF8 — C3Mod_Tile8ToM7 (262 bytes, $5EF8–$5FFD)
; As C3Mod_Tile4ToM7 for an 8bpp tile (planes 0-1 from X, 2-3 from X +
; 16, 4-5 from X + 32, 6-7 from X + 48): eight plane bytes a row at
; C3_TileRow (+0 to +7), each pixel the top bits of planes 7 down to 0
; (eight ROLs fill A, so no TDC), the rows counted in
; C3_Tile8RowsLeft. Reached only through the patched JSR in
; C3Mod_TilesToM7.
; Callers note: the patched JSR at $5E43 (C3Mod_TilesToM7; patched by
;   C3Mod_Prog10M7Scene at $8C5D and $8C63).
; Entry: M=1, X=0, DP = C3_TileRow's page (0: C3Mod_Prog10M7Scene
;        sets it at $8C22), DB = the tiles' bank ($7F); X = the tile.
; Exit:  M=1, X=0; A = the last pixel; X = the tile + 16; Y unchanged;
;        C3_Tile8RowsLeft = 0.
C3Mod_Tile8ToM7:
    LDA.b #8
    STA.b !C3_Tile8RowsLeft
.row:
    REP #$20
    LDA.w !Eng_PtrBase,X
    STA.b !C3_TileRow                   ; planes 0 and 1
    LDA.w !Eng_PtrBase+!C3_TilePlanes23,X
    STA.b !C3_TileRow+2                 ; planes 2 and 3
    LDA.w !Eng_PtrBase+!C3_TilePlanes45,X
    STA.b !C3_TileRow+4                 ; planes 4 and 5
    LDA.w !Eng_PtrBase+!C3_TilePlanes67,X
    STA.b !C3_TileRow+6                 ; planes 6 and 7
    INX
    INX
    SEP #$20
    %C3ModPixel8()
    %C3ModPixel8()
    %C3ModPixel8()
    %C3ModPixel8()
    %C3ModPixel8()
    %C3ModPixel8()
    %C3ModPixel8()
    %C3ModPixel8()
    DEC.b !C3_Tile8RowsLeft
    BEQ .done
    JMP .row
.done:
    RTS

; $7E:5FFE — C3Mod_WaveTask (65 bytes, $5FFE–$603E)
; A task: the wave of mode 2's offset-per-tile table (C3_WaveTable at
; $0C00, sent each frame by C3Mod_WaveNmiTask). Its second row's words
; $0C40-$0C7C move up one word ($0C42-$0C7E: X from $7C down by 2,
; CPX #$3E / BNE: ends at $3E exactly), and the new first word ($0C40)
; = v - $4A (SEC), AND $3FF, OR $2000 (bit 13: the offset is BG1's),
; with v = C3Mod_Sine(C3_FrameCount x 16) (-sin) x C3_WaveSize (page
; $0A00's var 6), bits 8-23, the sign handled as in C3Mod_RockTask (PHP
; / BPL, EOR / INC). The first row ($0C00-$0C3F) is not written here
; (C3Mod_Init cleared it). C3Mod_Mul16's quirk applies ($F8: the page
; C3Mod_RockTask divides in).
; Callers note: a task added by script opcode $FA at $5B0E
;   (C3Mod_Prog2Script).
; Entry: a task: M=0, X=0 (16-bit index; C3Mod_Mul16's), DP=0 (C3Math_*
;        and C3_FrameCount are direct page), DB=$00 (the table and the
;        page's word are absolute).
; Exit:  M=0, X = (C3_FrameCount x 16) AND C3_AngleMask (C3Mod_Sine's);
;        A = the new word; Y unchanged; C3Math_* changed.
; Calls: C3Mod_Sine, C3Mod_Mul16.
C3Mod_WaveTask:
    LDX.w #!C3_WaveShiftLast
.shift:
    LDA.w !C3_WaveTable,X
    STA.w !C3_WaveTable+2,X
    DEX
    DEX
    CPX.w #!C3_WaveShiftEnd
    BNE .shift
    LDA.b !C3_FrameCount
    ASL A
    ASL A
    ASL A
    ASL A
    JSR C3Mod_Sine
    PHP
    BPL .positive
    EOR.w #!Eng_Invert16
    INC A
.positive:
    STA.b !C3Math_A
    LDA.w !C3_ScriptPageA+!C3_WaveSize
    STA.b !C3Math_B
    JSR C3Mod_Mul16
    LDA.b !C3Math_Lo+1
    PLP
    BPL .sign
    EOR.w #!Eng_Invert16
    INC A
.sign:
    SEC
    SBC.w #!C3_WaveBase
    AND.w #!C3_OffsetMask
    ORA.w #!C3_OffsetBg1
    STA.w !C3_WaveTable+!C3_WaveVRow
    RTS

; $7E:603F — C3Mod_SwingPicA (125 bytes, $603F–$60BB)
; C3Mod_SwingDrawTask's upper picture (C3_SprListSmall): a count
; (sprites + 1), then 31 records of tile, attribute, X, Y: 8x8 sprites
; with tiles $04-$68 of the first page, attribute 0 (palette 0,
; priority 0), X -32 to +8 and Y -32 to +24 from the base (signed
; bytes: C3_SprListSmall's adds wrap at 8 bits).
C3Mod_SwingPicA:
    db $20
    db $68, $00, $08, $18
    db $67, $00, $00, $18
    db $66, $00, $F8, $18
    db $65, $00, $F0, $18
    db $64, $00, $E8, $18
    db $63, $00, $F8, $10
    db $62, $00, $F0, $10
    db $61, $00, $E8, $10
    db $60, $00, $E0, $10
    db $52, $00, $F0, $08
    db $51, $00, $E8, $08
    db $50, $00, $E0, $08
    db $45, $00, $08, $00
    db $43, $00, $F8, $00
    db $42, $00, $F0, $00
    db $41, $00, $E8, $00
    db $35, $00, $08, $F8
    db $34, $00, $00, $F8
    db $33, $00, $F8, $F8
    db $32, $00, $F0, $F8
    db $31, $00, $E8, $F8
    db $25, $00, $08, $F0
    db $24, $00, $00, $F0
    db $23, $00, $F8, $F0
    db $22, $00, $F0, $F0
    db $21, $00, $E8, $F0
    db $15, $00, $08, $E8
    db $14, $00, $00, $E8
    db $13, $00, $F8, $E8
    db $05, $00, $08, $E0
    db $04, $00, $00, $E0

; $7E:60BC — C3Mod_SwingPicB (53 bytes, $60BC–$60F0)
; Its lower picture, drawn $40 below: 13 sprites, tiles $20-$6F,
; attribute 0, X -24 to +8, Y -32 to -8.
C3Mod_SwingPicB:
    db $0E
    db $44, $00, $08, $F8
    db $46, $00, $08, $F0
    db $36, $00, $08, $E8
    db $40, $00, $00, $F8
    db $30, $00, $00, $F0
    db $20, $00, $00, $E8
    db $6F, $00, $F8, $E8
    db $6E, $00, $F0, $E8
    db $6D, $00, $08, $E0
    db $6C, $00, $00, $E0
    db $6B, $00, $F8, $E0
    db $6A, $00, $F0, $E0
    db $69, $00, $E8, $E0

; $7E:60F1 — C3Mod_SlidePic0 (25 bytes, $60F1–$6109)
; C3Mod_SlideTask's first picture: 6 sprites (16 wide, 24 high),
; tiles $06-$27, attribute 0, X -32 / -24, Y -32 to -16.
C3Mod_SlidePic0:
    db $07
    db $27, $00, $E8, $F0
    db $26, $00, $E0, $F0
    db $17, $00, $E8, $E8
    db $16, $00, $E0, $E8
    db $07, $00, $E8, $E0
    db $06, $00, $E0, $E0

; $7E:610A — C3Mod_SlidePic1 (25 bytes, $610A–$6122)
; The second: 6 sprites, tiles $08-$29, attribute $02 (palette 1), X
; -31 / -23.
C3Mod_SlidePic1:
    db $07
    db $29, $02, $E9, $F0
    db $28, $02, $E1, $F0
    db $19, $02, $E9, $E8
    db $18, $02, $E1, $E8
    db $09, $02, $E9, $E0
    db $08, $02, $E1, $E0

; $7E:6123 — C3Mod_SlidePic2 (37 bytes, $6123–$6147)
; The third: 9 sprites (24 x 24), tiles $0A-$2C, palette 1.
C3Mod_SlidePic2:
    db $0A
    db $2C, $02, $F0, $F0
    db $2B, $02, $E8, $F0
    db $2A, $02, $E0, $F0
    db $1C, $02, $F0, $E8
    db $1B, $02, $E8, $E8
    db $1A, $02, $E0, $E8
    db $0C, $02, $F0, $E0
    db $0B, $02, $E8, $E0
    db $0A, $02, $E0, $E0

; $7E:6148 — C3Mod_SlidePic3 (25 bytes, $6148–$6160)
; The fourth: 6 sprites, tiles $0D-$2E, palette 1, X -31 / -23.
C3Mod_SlidePic3:
    db $07
    db $2E, $02, $E9, $F0
    db $2D, $02, $E1, $F0
    db $1E, $02, $E9, $E8
    db $1D, $02, $E1, $E8
    db $0E, $02, $E9, $E0
    db $0D, $02, $E1, $E0

; $7E:6161 — C3Mod_SlidePic4 (37 bytes, $6161–$6185)
; The fifth: 9 sprites (24 x 24), tiles $37-$59, palette 1.
C3Mod_SlidePic4:
    db $0A
    db $59, $02, $F0, $F0
    db $58, $02, $E8, $F0
    db $57, $02, $E0, $F0
    db $49, $02, $F0, $E8
    db $48, $02, $E8, $E8
    db $47, $02, $E0, $E8
    db $39, $02, $F0, $E0
    db $38, $02, $E8, $E0
    db $37, $02, $E0, $E0

; $7E:6186 — C3Mod_BottomPicA (33 bytes, $6186–$61A6)
; C3Mod_BottomPicTask's first picture: 8 sprites in a row (X -32 to
; +24, Y -32), tiles $01-$03, $10-$12, $53 and $54, attribute $08
; (palette 4).
C3Mod_BottomPicA:
    db $09
    db $54, $08, $18, $E0
    db $53, $08, $10, $E0
    db $12, $08, $08, $E0
    db $11, $08, $00, $E0
    db $10, $08, $F8, $E0
    db $03, $08, $F0, $E0
    db $02, $08, $E8, $E0
    db $01, $08, $E0, $E0

; $7E:61A7 — C3Mod_BottomPicB (13 bytes, $61A7–$61B3)
; Its second: 3 sprites in a row, tiles $55, $56 and $5A, attribute
; $28 (palette 4, priority 2).
C3Mod_BottomPicB:
    db $04
    db $5A, $28, $F0, $E0
    db $56, $28, $E8, $E0
    db $55, $28, $E0, $E0

; $7E:61B4 — C3Mod_SidePic (37 bytes, $61B4–$61D8)
; C3Mod_SidePicTask's picture: 9 sprites, a column (tiles $0F, $1F,
; $2F, $3F at X 0, Y -24 to 0) and a row (tiles $3A-$3E at Y -32, X
; -32 to 0), attribute $06 (palette 3).
C3Mod_SidePic:
    db $0A
    db $3F, $06, $00, $00
    db $2F, $06, $00, $F8
    db $1F, $06, $00, $F0
    db $0F, $06, $00, $E8
    db $3E, $06, $00, $E0
    db $3D, $06, $F8, $E0
    db $3C, $06, $F0, $E0
    db $3B, $06, $E8, $E0
    db $3A, $06, $E0, $E0

; $7E:61D9 — C3Mod_FirstPic (57 bytes, $61D9–$6211)
; C3Mod_FirstPicTask's picture (C3_SprListLarge): 14 16x16 sprites,
; 7 x 2 (112 x 32 pixels), tiles $70-$7C and $90-$9C, attribute $2A
; (palette 5, priority 2).
C3Mod_FirstPic:
    db $0F
    db $70, $2A, $00, $00
    db $72, $2A, $10, $00
    db $74, $2A, $20, $00
    db $76, $2A, $30, $00
    db $78, $2A, $40, $00
    db $7A, $2A, $50, $00
    db $7C, $2A, $60, $00
    db $90, $2A, $00, $10
    db $92, $2A, $10, $10
    db $94, $2A, $20, $10
    db $96, $2A, $30, $10
    db $98, $2A, $40, $10
    db $9A, $2A, $50, $10
    db $9C, $2A, $60, $10

; $7E:6212 — C3Mod_WaveNmiTask (54 bytes, $6212–$6247)
; An NMI task: C3_WaveTable ($00:0C00, $80 bytes: two rows of 32
; words) to VRAM word $7000 (BG3's map: mode 2's offset-per-tile
; table) by DMA channel 7 (two registers from VMDATAL, VMAIN = $80),
; then BG3HOFS from $0044 / $0045 (low byte, then high byte; nothing in
; program 2 writes them, so 0 from C3Mod_Init's direct-page clear;
; C3_Prog9 is $44 in program 0).
; Callers note: an NMI task added by script opcode $F8 at $5B29
;   (C3Mod_Prog2Script).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X=0, DP any (the reads
;        are absolute), DB=$00.
; Exit:  M=1, X=0; A = $0045's byte, X = C3_WaveTableBytes; Y
;        unchanged; DMA channel 7's registers set.
C3Mod_WaveNmiTask:
    LDX.w #!C3_Prog2Bg3Map
    STX.w VMADDL
    LDA.b #!DMAP_TwoRegs
    STA.w DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD7
    LDX.w #!C3_WaveTable
    STX.w A1T7L
    LDA.b #0
    STA.w A1B7
    LDX.w #!C3_WaveTableBytes
    STX.w DAS7L
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    STA.w MDMAEN                        ; MDMAEN_Ch7, the same value
    LDA.w !C3_Prog2Bg3Hofs
    STA.w BG3HOFS
    LDA.w !C3_Prog2Bg3Hofs+1
    STA.w BG3HOFS
    RTS

%C3ModOrg($7E6248)
; ============================================================
; Programs 7 and 8: "BUT... THE FUTURE REFUSED TO CHANGE."
; ($6248–$66DC)
; ============================================================

; $7E:6248 — C3Mod_Prog7 (245 bytes, $6248–$633C)
; The program of C3Mod_ProgramTable entries 7 and 8: a still picture
; with sparks, a palette that fades towards a second one, then the
; text "BUT... THE FUTURE REFUSED TO CHANGE." in sprites; a button
; ends it with a soft reset (C3Mod_ResetWaitTask).
;   - VMAIN = $80; C3Mod_DestBitmapSrc (the packs to $7F:0200); pack 33 (a
;     2bpp font) made 4bpp at VRAM word $4000 (C3Mod_Font2To4, $80
;     tiles); pack 31 to $4800, pack 69 to $5000 and pack 59 to $7000
;     (C3Mod_DmaUnpacked, two registers from VMDATAL);
;   - Decomp_DestBank = 0 (bank $7E) and $F1 = 0 (C3_DmaMode's high
;     byte; no reader of it as a word was found); pack 28 to
;     $7E:2020 (C3_PaletteWork from colour 16), packs 29 and 30 to
;     $7E:B574 and $B774 (the fade targets of C3Mod_PalFadeTask; the
;     generated copy code's place, unused here), C3Mod_SetGreys
;     (colours $F1-$F3 and colour 0 of C3_PaletteWork), pack 32 to
;     $7E:21C0 (colours $E0 on);
;   - page $0A00 runs C3Mod_Prog7Script, or C3Mod_Prog8Script when
;     C3_EntryArg AND $F is 8 (a 16-bit read; CMP #8 / BNE: equality);
;     C3Mod_CommitPalette; the script once (C3Mod_ScriptTaskA, DB kept
;     around it), DP = 0;
;   - C3Mod_InitSparks; FdVec_FFEE (PalAnim_StopAll); BGMODE = 3,
;     BG1SC = $70, BG12NBA = $05 (BG1's tiles at $5000), BG1HOFS =
;     -$48, BG1VOFS = -$34 (low byte, then high), CGWSEL = add the sub
;     screen, CGADSUB = add on BG1, TM = BG1, TS = the sprites, TMW =
;     TSW = all layers, C3_ExitTimer = $80.
; Callers note: C3Mod_ProgramTable entries 7 and 8 (C3Mod_Start's JSR
;   (table,X) at $300A).
; Entry: M=1, X=0, DP=0, DB=$00 (as C3Mod_Start calls the programs).
; Exit:  M=1, X=0, DP=0, DB=$00 (the PLB of the PHB); A = $FF, X =
;        C3_Prog7ExitFrames, Y = $0090 (PalAnim_StopAll's).
; Calls: C3Mod_DestBitmapSrc, C3Mod_UnpackPack, C3Mod_Font2To4,
;   C3Mod_DmaUnpacked (JSL), C3Mod_SetGreys, C3Mod_CommitPalette,
;   C3Mod_ScriptTaskA, C3Mod_InitSparks, FdVec_FFEE (JSL).
C3Mod_Prog7:
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    JSR C3Mod_DestBitmapSrc
    LDX.w #!C3_SprTilesVram
    STX.w VMADDL
    LDX.w #33*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog7FontTiles
    JSR C3Mod_Font2To4
    LDX.w #!C3_Prog7Tiles2
    STX.w VMADDL
    LDX.w #31*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDA.b #!DMAP_TwoRegs
    STA.w !C3_DmaMode
    LDA.b #!BBAD_VMDATAL
    STA.w !C3_DmaBbad
    JSL C3Mod_DmaUnpacked
    LDX.w #69*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_SprTilesHigh
    STX.w VMADDL
    JSL C3Mod_DmaUnpacked
    LDX.w #!C3_Prog0BgTiles
    STX.w VMADDL
    LDX.w #59*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DmaUnpacked
    STZ.w !Decomp_DestBank
    STZ.b !C3_DmaMode+1
    LDX.w #(!C3_PaletteWork&$FFFF)+$20
    STX.w !Decomp_Dest
    LDX.w #28*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog7FadeA
    STX.w !Decomp_Dest
    LDX.w #29*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog7FadeB
    STX.w !Decomp_Dest
    LDX.w #30*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSR C3Mod_SetGreys
    LDX.w #(!C3_PaletteWork&$FFFF)+$1C0
    STX.w !Decomp_Dest
    LDX.w #32*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    REP #$20
    PHB
    LDX.w #C3Mod_Prog7Script
    LDA.w !C3_EntryArg
    AND.w #!C3_EntryLowNibble
    CMP.w #8
    BNE .script
    LDX.w #C3Mod_Prog8Script
.script:
    STX.w !C3_ScriptPageA+!C3Script_Ptr
    JSR C3Mod_CommitPalette
    REP #$20
    JSR C3Mod_ScriptTaskA
    PLB
    SEP #$20
    PEA.w 0
    PLD
    JSR C3Mod_InitSparks
    JSL !FdVec_FFEE
    LDA.b #!C3_Prog7BgMode
    STA.w BGMODE
    LDA.b #!C3_Prog7Bg1Sc
    STA.w BG1SC
    LDA.b #!C3_Prog7Tiles
    STA.w BG12NBA
    LDA.b #!C3_Prog7Bg1Hofs&$FF
    STA.w BG1HOFS
    LDA.b #!C3_Prog7Bg1Hofs>>8
    STA.w BG1HOFS
    LDA.b #!C3_Prog7Bg1Vofs&$FF
    STA.w BG1VOFS
    LDA.b #!C3_Prog7Bg1Vofs>>8
    STA.w BG1VOFS
    LDX.w #!CGWSEL_AddSubscreen|(!CGADSUB_AddBg1<<8)
    STX.w CGWSEL                        ; and CGADSUB
    LDX.w #!TM_Bg1|(!TM_Obj<<8)
    STX.w TM                            ; and TS
    LDX.w #!TM_AllLayers|(!TM_AllLayers<<8)
    STX.w TMW                           ; and TSW
    LDX.w #!C3_Prog7ExitFrames
    STX.w !C3_ExitTimer
    RTS

; $7E:633D — C3Mod_Prog7Script (83 bytes, $633D–$638F)
; Page $0A00's script in program 7: C3Mod_Prog7Start (script call);
; C3Mod_SparksTask; 120 frames later C3Mod_PalFadeTask with
; C3Mod_Prog7Fade (colours 32-223 step towards pack 30's); 180 frames
; later C3_Prog9's byte ($0044) = 1 (C3Mod_NewSpark puts no more sparks
; on the screen); 120 frames later CGADSUB = add on BG1 and the
; backdrop, C3Mod_Prog7FadeSlow (back towards pack 29's, every 32
; frames), C3_EntryArg = 7 (what reads it afterwards is not traced);
; 230 frames later C3_SongReq = $3A (C3_SongCheck plays that song); 10
; frames later C3Mod_SparksTask removed, C3Mod_TextTask added, and
; FieldAnimB record 0 made a fade of colours $F0-$FF (C3Mod_PalFadeAnim,
; then .Unk3 = 2 and .Unk1 = $F0 poked over it); 128 frames later
; C3Mod_ResetWaitTask; then it waits for good. A $9x loop opcode yields
; on every pass, the last one too.
C3Mod_Prog7Script:
    db !C3Op_Call : dw C3Mod_Prog7Start
    db !C3Op_TaskAdd : dw C3Mod_SparksTask
.l6343:
    db !C3Op_LoopYield|1 : dw $0077, .l6343             ; 120 passes
    db !C3Op_TaskAdd : dw C3Mod_PalFadeTask
    db !C3Op_CallW : dw C3Mod_Prog7Fade
.l634E:
    db !C3Op_LoopYield|1 : dw $00B3, .l634E             ; 180 passes
    db !C3Op_Poke8 : dw !C3_Prog9 : db 1
.l6357:
    db !C3Op_LoopYield|1 : dw $0077, .l6357             ; 120 passes
    db !C3Op_Ppu, !CGADSUB_AddBg1Backdrop, CGADSUB-!DP_PPU
    db !C3Op_CallW : dw C3Mod_Prog7FadeSlow
    db !C3Op_Poke8 : dw !C3_EntryArg : db 7
.l6366:
    db !C3Op_LoopYield|1 : dw $00E5, .l6366             ; 230 passes
    db !C3Op_Poke8 : dw !C3_SongReq : db !C3_SongProg7
.l636F:
    db !C3Op_LoopYield|1 : dw $0009, .l636F             ; 10 passes
    db !C3Op_TaskRemove : dw C3Mod_SparksTask
    db !C3Op_TaskAdd : dw C3Mod_TextTask
    db !C3Op_CallW : dw C3Mod_PalFadeAnim
    db !C3Op_Poke8 : dw FieldAnimB.Unk3 : db 2
    db !C3Op_Poke8 : dw FieldAnimB.Unk1 : db !C3_TextColours
.l6385:
    db !C3Op_LoopYield|1 : dw $007F, .l6385             ; 128 passes
    db !C3Op_TaskAdd : dw C3Mod_ResetWaitTask
.l638D:
    db !C3Op_JumpYield : dw .l638D

; $7E:6390 — C3Mod_Prog7Start (22 bytes, $6390–$63A5)
; A script subroutine (opcode $F3) of both programs' scripts: var 0 =
; $100, the tasks C3Mod_ScriptTaskA, C3Mod_PalAnimTask and
; C3Mod_FadeInTask, the NMI tasks C3Mod_OamUploadTask,
; C3Mod_HideSprites and C3Mod_UploadPalette; then it returns.
C3Mod_Prog7Start:
    db !C3Op_Set|0 : dw $0100
    db !C3Op_TaskAdd : dw C3Mod_ScriptTaskA
    db !C3Op_TaskAdd : dw C3Mod_PalAnimTask
    db !C3Op_TaskAdd : dw C3Mod_FadeInTask
    db !C3Op_NmiAdd : dw C3Mod_OamUploadTask
    db !C3Op_NmiAdd : dw C3Mod_HideSprites
    db !C3Op_NmiAdd : dw C3Mod_UploadPalette
    db !C3Op_Return

; $7E:63A6 — C3Mod_Prog8Script (47 bytes, $63A6–$63D4)
; Page $0A00's script in program 8: C3Mod_Prog7Start; 120 frames
; later C3Mod_PalFadeTask with C3Mod_Prog8Fade (colours 32-223 step
; towards pack 29's, every 16 frames); 120 frames later CGADSUB = add
; on BG1 and the backdrop, C3Mod_TextTask and the fade of colours
; $F0-$FF (as in program 7); 128 frames later C3Mod_ResetWaitTask;
; then it waits for good. No sparks are drawn (C3Mod_SparksTask is
; never added) and the song is not changed.
C3Mod_Prog8Script:
    db !C3Op_Call : dw C3Mod_Prog7Start
.l63A9:
    db !C3Op_LoopYield|1 : dw $0077, .l63A9             ; 120 passes
    db !C3Op_TaskAdd : dw C3Mod_PalFadeTask
    db !C3Op_CallW : dw C3Mod_Prog8Fade
.l63B4:
    db !C3Op_LoopYield|1 : dw $0077, .l63B4             ; 120 passes
    db !C3Op_Ppu, !CGADSUB_AddBg1Backdrop, CGADSUB-!DP_PPU
    db !C3Op_TaskAdd : dw C3Mod_TextTask
    db !C3Op_CallW : dw C3Mod_PalFadeAnim
    db !C3Op_Poke8 : dw FieldAnimB.Unk3 : db 2
    db !C3Op_Poke8 : dw FieldAnimB.Unk1 : db !C3_TextColours
.l63CA:
    db !C3Op_LoopYield|1 : dw $007F, .l63CA             ; 128 passes
    db !C3Op_TaskAdd : dw C3Mod_ResetWaitTask
.l63D2:
    db !C3Op_JumpYield : dw .l63D2

; $7E:63D5 — C3Mod_ResetWaitTask (32 bytes, $63D5–$63F4)
; A task: waits for any button (C3_Pad, 16-bit: BEQ while 0); then the
; song fades out over $40 steps (Audio_CmdId = C3_SndFadeSong with
; Arg0 = 0 from the 16-bit store, then Arg0/Arg1 = C3_SndFadeOut;
; C3Mod_AudioSend), C3Mod_FadeOutTask is added and this task hands its
; entry to C3Mod_ResetTask (C3Mod_TaskReplace).
; Callers note: a task added by script opcode $FA at $638A
;   (C3Mod_Prog7Script) and $63CF (C3Mod_Prog8Script).
; Entry: a task (C3Mod_RunTasks): M=0, X=0, DP=0 (C3_Pad is direct
;        page), DB=$00 (the Audio_Cmd* block and the task list are
;        absolute).
; Exit:  RTS with M=0, A = 0 (no button); else JMP C3Mod_TaskReplace
;        with X = C3Mod_ResetTask.
; Calls: C3Mod_AudioSend, C3Mod_TaskAdd.
C3Mod_ResetWaitTask:
    LDA.b !C3_Pad
    BEQ .done
    LDA.w #!C3_SndFadeSong
    STA.w !Audio_CmdId                  ; and Arg0 = 0
    LDX.w #!C3_SndFadeOut
    STX.w !Audio_CmdArg0                ; and Arg1
    JSR C3Mod_AudioSend
    LDX.w #C3Mod_FadeOutTask
    JSR C3Mod_TaskAdd
    LDX.w #C3Mod_ResetTask
    JMP C3Mod_TaskReplace
.done:
    RTS

; $7E:63F5 — C3Mod_ResetTask (9 bytes, $63F5–$63FD)
; A task: C3_ExitTimer - 1 (16-bit DEC; $80 from C3Mod_Prog7); while
; not 0 (BNE, to C3Mod_ResetWaitTask's RTS) it waits; at 0 JML to the
; game's Reset at $00:FF00 (bank00.asm): a soft reset, with the
; module's NMI and V-count IRQ still enabled (C3Mod_Start's NMITIMEN;
; Reset's SEI masks the IRQ).
; Callers note: a task: LDX #C3Mod_ResetTask / JMP C3Mod_TaskReplace at
;   $63EE, $63F1 (C3Mod_ResetWaitTask).
; Entry: a task: M=0 (the 16-bit DEC), X=0 (as C3Mod_RunTasks runs
;        the tasks; only the JML's state needs it), DP any, DB=$00
;        (C3_ExitTimer is absolute).
; Exit:  RTS with M=0 while waiting; else never returns (JML Reset with
;        M=0, X=0, the task's DP and DB=$00).
C3Mod_ResetTask:
    DEC.w !C3_ExitTimer
    BNE C3Mod_ResetWaitTask_done
    JML !C3_SoftReset

; $7E:63FE — C3Mod_Prog7Fade (36 bytes with C3Mod_Prog8Fade, $63FE–$6421)
; A script routine (opcode $x0): C3Mod_PalFadeTask's arguments: the
; target colours at $7E:B7B4 (pack 30's, from colour 32), C3_FadeStep =
; C3_FadeTimer = 8, the colours at $2240 (C3_PaletteBuf from colour
; 32), $C0 of them (colours 32-223), $20 steps (a 16-bit store: $0367
; is zeroed too). C3Mod_Prog8Fade ($6403) is the same with the targets
; at $7E:B5B4 (pack 29's).
; Sub-entry: C3Mod_Prog8Fade ($6403).
; Callers note: script opcode $F0 at $634B (C3Mod_Prog7Script).
;   C3Mod_Prog8Fade: script opcode $F0 at $63B1 (C3Mod_Prog8Script).
; Entry: M=0, X any, DP any, DB = $7E or $00 (the stores are absolute;
;        C3_RunScript runs with $7E). C3Mod_Prog8Fade: the same.
; Exit:  M=0; A = C3_PalFadeColours; X, Y unchanged.
C3Mod_Prog7Fade:
    LDA.w #!C3_Prog7FadeB+$40
    BRA C3Mod_Prog8Fade_source
C3Mod_Prog8Fade:                        ; header: see C3Mod_Prog7Fade
    LDA.w #!C3_Prog7FadeA+$40
.source:
    STA.w !C3_PalFadeSrc
    LDA.w #!C3_Prog0Fade
    STA.w !C3_FadeStep                  ; and C3_FadeTimer
    LDA.w #(!C3_PaletteBuf&$FFFF)+$40
    STA.w !C3_PalFadeDest
    LDA.w #!C3_PalFadeSteps
    STA.w !C3_PalFadeLeft
    LDA.w #!C3_PalFadeColours
    STA.w !C3_PalFadeCount
    RTS

; $7E:6422 — C3Mod_Prog7FadeSlow (23 bytes, $6422–$6438)
; A script routine: C3Mod_PalFadeTask goes on towards $7E:B5B4 (pack
; 29's colours) with $20 more steps (a 16-bit store: $0367 zeroed too;
; the destination and the count as
; C3Mod_Prog7Fade set them), and $1F is written over the AND operand
; in C3Mod_PalFadeTask (.every + 1), so it steps every 32 frames
; instead of 16.
; Callers note: script opcode $F0 at $635F (C3Mod_Prog7Script).
; Entry: M=0 (8-bit set for the patch, then 16-bit again), X any, DP
;        any, DB = $7E or $00 (the stores are absolute; the patch is
;        long).
; Exit:  M=0; A's low byte = C3_PalFadeSlow; X, Y unchanged.
C3Mod_Prog7FadeSlow:
    LDA.w #!C3_Prog7FadeA+$40
    STA.w !C3_PalFadeSrc
    LDA.w #!C3_PalFadeSteps
    STA.w !C3_PalFadeLeft
    SEP #$20
    LDA.b #!C3_PalFadeSlow
    STA.l C3Mod_PalFadeTask_every+1
    REP #$20
    RTS

; $7E:6439 — C3Mod_PalFadeTask (134 bytes, $6439–$64BE)
; A task: every 16 frames (C3_FrameCount AND .every's operand, $0F or
; $1F once C3Mod_Prog7FadeSlow wrote it: BNE skips the others) and
; while C3_PalFadeLeft is not 0 (8-bit, BEQ; then - 1), each of
; C3_PalFadeCount colours at C3_PalFadeDest steps one unit towards the
; one at C3_PalFadeSrc, channel by channel (red bits 0-4, green 5-9,
; blue 10-14, each masked from both words): when the destination's
; channel - the source's has bit 15 set (CMP / BPL; equal: BEQ, kept)
; it goes up one unit (INC, or + $20 / + $400 with CLC), else down (DEC,
; or - $20 / - $400 with SEC); the three are put together (ORA, bit 15
; cleared) and stored. The channel values are below $8000, so bit 15 of
; the difference is its true sign. With DP = $0300 (C3_PalFadeSrc..
; are direct page) and DB = $7E (PHK / PLB; both banks of colours are
; there), the count in C3_PalFadeWork ($03FE, 16-bit DEC / BNE).
; Callers note: a task added by script opcode $FA at $6348
;   (C3Mod_Prog7Script), $63AE (C3Mod_Prog8Script) and $95B6 and $967D
;   (scripts not matched yet).
; Entry: a task (C3Mod_RunTasks): M=0 (8-bit set here), X=0 (16-bit
;        index), DP=0 (C3_FrameCount is direct page; set to $0300
;        here), DB any (set to $7E; both restored by C3Mod_RunTasks).
; Exit:  X=0. Skipped on the frame count: M=1, A = the AND's result,
;        DP and DB as on entry. With C3_PalFadeLeft 0: M=1, A = 0, DP
;        = $0300. After a step: M=0, DP = $0300, DB = $7E, A = the last
;        colour, X and Y past the colours, $03F0 / $03F2 changed.
C3Mod_PalFadeTask:
    SEP #$20
    LDA.b !C3_FrameCount
.every:
    AND.b #!C3_PalFadeEvery             ; C3Mod_Prog7FadeSlow writes $1F here
    BNE .done
    PEA.w !DP_C3PalFade
    PLD
    LDA.b !C3_PalFadeLeft-!DP_C3PalFade
    BEQ .done
    DEC.b !C3_PalFadeLeft-!DP_C3PalFade
    PHK
    PLB
    REP #$20
    LDX.b !C3_PalFadeSrc-!DP_C3PalFade
    LDY.b !C3_PalFadeDest-!DP_C3PalFade
    LDA.b !C3_PalFadeCount-!DP_C3PalFade
    STA.b !C3_PalFadeWork-!DP_C3PalFade
.colour:
    LDA.w !Eng_PtrBase,X
    AND.w #!C3_ColourRed
    STA.b !C3_TmpF0
    LDA.w !Eng_PtrBase,Y
    AND.w #!C3_ColourRed
    CMP.b !C3_TmpF0
    BEQ .red
    BPL .red_down
    INC A
    BRA .red
.red_down:
    DEC A
.red:
    STA.b !C3_TmpF2
    LDA.w !Eng_PtrBase,X
    AND.w #!C3_ColourGreen
    STA.b !C3_TmpF0
    LDA.w !Eng_PtrBase,Y
    AND.w #!C3_ColourGreen
    CMP.b !C3_TmpF0
    BEQ .green
    BPL .green_down
    CLC
    ADC.w #!C3_GreenUnit
    BRA .green
.green_down:
    SEC
    SBC.w #!C3_GreenUnit
.green:
    ORA.b !C3_TmpF2
    STA.b !C3_TmpF2
    LDA.w !Eng_PtrBase,X
    AND.w #!C3_ColourBlue
    STA.b !C3_TmpF0
    LDA.w !Eng_PtrBase,Y
    AND.w #!C3_ColourBlue
    CMP.b !C3_TmpF0
    BEQ .blue
    BPL .blue_down
    CLC
    ADC.w #!C3_BlueUnit
    BRA .blue
.blue_down:
    SEC
    SBC.w #!C3_BlueUnit
.blue:
    ORA.b !C3_TmpF2
    STA.w !Eng_PtrBase,Y
    INX
    INX
    INY
    INY
    DEC.b !C3_PalFadeWork-!DP_C3PalFade
    BNE .colour
.done:
    RTS

; $7E:64BF — C3Mod_TextTask (6 bytes, $64BF–$64C4)
; A task: draws C3Mod_Prog7Text (C3Mod_DrawText, JMP).
; Callers note: a task added by script opcode $FA at $6377
;   (C3Mod_Prog7Script) and $63BC (C3Mod_Prog8Script).
; Entry: a task: M=0, X=0, DP=0, DB=$00 (as C3Mod_DrawText wants).
; Exit:  as C3Mod_DrawText leaves them (JMP).
; Calls: C3Mod_DrawText (JMP).
C3Mod_TextTask:
    LDX.w #C3Mod_Prog7Text
    JMP C3Mod_DrawText

; $7E:64C5 — C3Mod_DrawTextDone (5 bytes, $64C5–$64C9)
; C3Mod_DrawText's exit, placed before it: C3_OamPos = Y, then the DB
; and P it saved back (PLB takes the $00 its PEA left).
; Callers note: reached by C3Mod_DrawText's BEQ at $64E3 (the end code).
; Entry: M=1, X=0, DP = C3_OamPos's page (0), DB = $7E; the stack as
;        C3Mod_DrawText left it (P, then $00); Y = the OAM offset.
; Exit:  P restored (M and X as C3Mod_DrawText was entered with), DB =
;        $00; A = C3_TextEnd (B = 0), X past the text, Y = C3_OamPos.
C3Mod_DrawTextDone:
    STY.b !C3_OamPos
    PLB
    PLP
    RTS

; $7E:64CA — C3Mod_DrawText (206 bytes, $64CA–$6597)
; Draws a text at X (bank $7E) as sprites from C3_OamPos on, with this
; font: by the byte c (CMP / BEQ or BNE: each an equality test):
;   - $40: the end (C3Mod_DrawTextDone);
;   - $00: the next two bytes are the place: C3_SprBaseX, C3_SprBaseY
;     and the operands of .line_x / .line_y (self-modifying: they keep
;     the line's start, also as the next call's first place);
;   - $2F: a new line: C3_SprBaseX = .line_x's operand, C3_SprBaseY +
;     $10 (CLC);
;   - $20: a space: C3_SprBaseX + 8 (CLC);
;   - else a glyph: its sprite at the place, tile C3Mod_FontTiles[c -
;     $41], attribute .attr's operand ($3E as assembled: palette 7,
;     priority 3; C3Mod_Prog10 writes $3F there at $8554, adding bit 0,
;     the sprites' second tile page); with its width w =
;     C3Mod_FontWidths[c - $41]: CMP #9 / BMI (8-bit: w - 9 with bit 7
;     set, so widths 0-8 for this table's $00-$0F) a narrow glyph: the
;     sprite 8x8 and a second one 8 lower with tile + $10 (CLC) and the
;     same attribute, so 8x16; else one 16x16 sprite. C3_SprBaseX + w
;     + 1 (SEC / ADC) after either.
; Each sprite's two high-table bits (through C3_OamHiPtr, which goes
; up after every 4 sprites: offset AND $F = 0) are made by shifting the
; byte right twice: LSR / SEC / ROR puts the size bit in for a 16x16
; sprite, LSR / LSR or LSR / CLC / ROR leaves both bits 0. X bit 8 is
; always 0.
; Callers note: JMP from C3Mod_TextTask ($64C2) and JSR from $9B5C (in
;   the task at $9B4F, code not matched yet, which the trace reaches).
; Entry: M any (P saved; 8-bit set here), X=0 (16-bit index), DP = the
;        page of C3_OamPos.. with low byte 0 (TDC / XBA makes B = DP's
;        low byte, so the TAX of c is c; 0 at both calls: C3Mod_TextTask
;        and the task at $9B4F run with C3Mod_RunTasks' DP 0), DB any (set to $7E with PEA $007E / PLB;
;        $00 at the exit); X = the text.
; Exit:  through C3Mod_DrawTextDone: P restored, DB = $00; A =
;        C3_TextEnd, X past the text, Y = C3_OamPos (advanced);
;        C3_OamHiPtr, C3_SprBaseX/Y changed.
C3Mod_DrawText:
    PHP
    TDC
    XBA                                 ; B = DP's low byte (0)
    SEP #$20
    LDY.b !C3_OamPos
    PEA.w !Bank7E                       ; PLB takes the $7E; the $00 stays for C3Mod_DrawTextDone
    PLB
.line_x:
    LDA.b #0                            ; a $00 code writes the line's X here
    STA.b !C3_SprBaseX
.line_y:
    LDA.b #0                            ; ... and its Y here
    STA.b !C3_SprBaseY
.char:
    LDA.w !Eng_PtrBase,X
    INX
    CMP.b #!C3_TextEnd
    BEQ C3Mod_DrawTextDone
    CMP.b #!C3_TextPlace
    BNE .not_place
    LDA.w !Eng_PtrBase,X
    INX
    STA.w .line_x+1
    STA.b !C3_SprBaseX
    LDA.w !Eng_PtrBase,X
    INX
    STA.w .line_y+1
    STA.b !C3_SprBaseY
    BRA .char
.not_place:
    CMP.b #!C3_TextNewLine
    BNE .not_new_line
    LDA.w .line_x+1
    STA.b !C3_SprBaseX
    LDA.b !C3_SprBaseY
    CLC
    ADC.b #!C3_TextLineGap
    STA.b !C3_SprBaseY
    BRA .char
.not_new_line:
    CMP.b #!C3_TextSpace
    BNE .glyph
    LDA.b !C3_SprBaseX
    CLC
    ADC.b #8
    STA.b !C3_SprBaseX
    BRA .char
.glyph:
    PHX
    TAX
    LDA.w C3Mod_FontTiles-!C3_FontFirst,X
    STA.w !Oam_LowTable+2,Y
.attr:
    LDA.b #!C3_TextAttr                 ; C3Mod_Prog10 writes $3F here
    STA.w !Oam_LowTable+3,Y
    LDA.b !C3_SprBaseX
    STA.w !Oam_LowTable,Y
    LDA.b !C3_SprBaseY
    STA.w !Oam_LowTable+1,Y
    LDA.w C3Mod_FontWidths-!C3_FontFirst,X
    CMP.b #!C3_GlyphWide
    BMI .narrow
    SEC
    ADC.b !C3_SprBaseX
    STA.b !C3_SprBaseX
    LDA.b (!C3_OamHiPtr)
    LSR A
    SEC                                 ; the size bit: 16x16
.high:
    ROR A
    STA.b (!C3_OamHiPtr)
    PLX
    INY
    INY
    INY
    INY
    TYA
    AND.b #!C3_OamGroupMask
    BNE .next
    REP #$20
    INC.b !C3_OamHiPtr
    SEP #$20
.next:
    JMP .char
.narrow:
    LDA.b (!C3_OamHiPtr)
    LSR A
    LSR A
    STA.b (!C3_OamHiPtr)
    INY
    INY
    INY
    INY
    TYA
    AND.b #!C3_OamGroupMask
    BNE .lower
    REP #$20
    INC.b !C3_OamHiPtr
    SEP #$20
.lower:
    LDA.b !C3_SprBaseX
    STA.w !Oam_LowTable,Y
    LDA.b !C3_SprBaseY
    CLC
    ADC.b #8
    STA.w !Oam_LowTable+1,Y
    LDA.w !Oam_LowTable-2,Y             ; the upper sprite's tile
    CLC
    ADC.b #!C3_GlyphLower
    STA.w !Oam_LowTable+2,Y
    LDA.w !Oam_LowTable-1,Y             ; ... and attribute
    STA.w !Oam_LowTable+3,Y
    LDA.w C3Mod_FontWidths-!C3_FontFirst,X
    SEC
    ADC.b !C3_SprBaseX
    STA.b !C3_SprBaseX
    LDA.b (!C3_OamHiPtr)
    LSR A
    CLC                                 ; small
    BRA .high

; $7E:6598 — C3Mod_InitSparks (22 bytes, $6598–$65AD)
; Starts the 24 spark records at $0C00-$0CBF (8 bytes each, C3_Sparks):
; C3Mod_NewSpark for each (X + 8 with CLC; CPX #$0CC0 / BNE: ends at
; $0CC0 exactly). The first record's carry in is C3Mod_Prog7's (what
; C3Mod_ScriptTaskA left), the others' the CPX's: 0 (X below $0CC0).
; Callers note: C3Mod_Prog7 ($62FA).
; Entry: M=1 (M=0 set for the add, then 1 again), X=0 (16-bit index),
;        DP=0 (C3Mod_NewSpark's), DB=$00 (the records are absolute).
; Exit:  M=1, X=0; A = C3_SparksEnd ($0CC0: the last pass's TXA / ADC
;        #8 / TAX; low byte $C0, B = $0C), X = C3_SparksEnd, Y = the
;        word at $0044 (C3Mod_NewSpark's).
; Calls: C3Mod_NewSpark.
C3Mod_InitSparks:
    LDX.w #!C3_Sparks
.spark:
    JSR C3Mod_NewSpark
    REP #$20
    TXA
    CLC
    ADC.w #!C3_SparkBytes
    TAX
    SEP #$20
    CPX.w #!C3_SparksEnd
    BNE .spark
    RTS

; $7E:65AE — C3Mod_NewSpark (47 bytes, $65AE–$65DC)
; A new spark at record X: X = (C3Mod_TableRandom AND $7F) + $40 + C
; (no CLC; C3Mod_TableRandom restores P, so C is the caller's: the
; first record's as C3Mod_InitSparks or C3Mod_SparksTask was entered,
; the others 0); Y = $E0 (off the screen) when the word at $0044
; (C3_Prog9's byte and the next) is not 0 (LDY / BNE: the scripts poke
; 1 there to stop the sparks), else (random AND $7F) + $30 + C (C = 0:
; the carry out of the first add, at most $C0); the delay = (random
; AND $3F) + 1 (1-64 frames), the life C3_SparkLife = $0A, the tick =
; 4.
; Callers note: C3Mod_InitSparks ($659B) and C3Mod_SparksTask ($6608).
; Entry: M=1 (8-bit stores), X=0 (16-bit index), DP = a page boundary
;        (C3Mod_TableRandom's; 0 at both), DB=$00 (the record and $0044
;        are absolute); X = the record; C as described.
; Exit:  M=1, X=0; A = 4, X unchanged, Y = the word at $0044; C = 0
; Calls: C3Mod_TableRandom.
C3Mod_NewSpark:
    JSR C3Mod_TableRandom
    AND.b #!C3_SparkRange
    ADC.b #!C3_SparkLeft0               ; C as the caller left it
    STA.w !Eng_PtrBase+!C3_SparkX,X
    LDA.b #!C3_SparkHidden
    LDY.w !C3_Prog9
    BNE .y
    JSR C3Mod_TableRandom
    AND.b #!C3_SparkRange
    ADC.b #!C3_SparkTop
.y:
    STA.w !Eng_PtrBase+!C3_SparkY,X
    JSR C3Mod_TableRandom
    AND.b #!C3_SparkDelayMask
    INC A
    STA.w !Eng_PtrBase+!C3_SparkDelay,X
    LDA.b #!C3_SparkLife
    STA.w !Eng_PtrBase+!C3_SparkLeft,X
    LDA.b #4
    STA.w !Eng_PtrBase+!C3_SparkTick,X
    RTS

; $7E:65DD — C3Mod_SparksTask (99 bytes, $65DD–$663F)
; A task: C3_SprBaseX = C3_SprBaseY = 0 (16-bit stores), then each spark
; record ($0C00 on, X + 8 with CLC, CPX #$0CC0 / BNE): while its delay
; is not 0 (BEQ) it only counts down; else its tick - 1, and at 0 (BNE)
; the tick = 4 and its life - 1, and at 0 (BNE) a new spark
; (C3Mod_NewSpark; C = the task's entry carry for the first record,
; else 0 from the CPX); otherwise it is drawn at its X, Y (the base's
; low bytes) with tile ($0A - life, SEC) OR $80 ($80-$89 as the life
; goes from 10 to 1) written into C3Mod_SparkSprite (long store) and
; C3_SprOneSmall.
; Callers note: a task added by script opcode $FA at $6340
;   (C3Mod_Prog7Script), removed by $F9 at $6374.
; Entry: a task: M=0 (8-bit set here), X=0, DP=0 (C3_SprBase* and
;        C3Mod_NewSpark's), DB=$00 (the records are absolute;
;        C3_SprOneSmall's).
; Exit:  M=1, X=0; A = X = C3_SparksEnd (the last pass's TXA / ADC #8
;        / TAX); Y as the last record left it (C3Mod_NewSpark's word at
;        $0044, or C3_SprOneSmall's C3_OamPos, or unchanged).
; Calls: C3Mod_NewSpark, C3_SprOneSmall (JSL).
C3Mod_SparksTask:
    SEP #$20
    LDX.w #0
    STX.b !C3_SprBaseX
    STX.b !C3_SprBaseY
    LDX.w #!C3_Sparks
.spark:
    LDA.w !Eng_PtrBase+!C3_SparkDelay,X
    BEQ .tick
    DEC.w !Eng_PtrBase+!C3_SparkDelay,X
    BRA .next
.tick:
    DEC.w !Eng_PtrBase+!C3_SparkTick,X
    LDA.w !Eng_PtrBase+!C3_SparkTick,X
    BNE .draw
    LDA.b #4
    STA.w !Eng_PtrBase+!C3_SparkTick,X
    DEC.w !Eng_PtrBase+!C3_SparkLeft,X
    LDA.w !Eng_PtrBase+!C3_SparkLeft,X
    BNE .draw
    JSR C3Mod_NewSpark
    BRA .next
.draw:
    LDA.w !Eng_PtrBase+!C3_SparkX,X
    STA.b !C3_SprBaseX
    LDA.w !Eng_PtrBase+!C3_SparkY,X
    STA.b !C3_SprBaseY
    LDA.b #!C3_SparkLife
    SEC
    SBC.w !Eng_PtrBase+!C3_SparkLeft,X
    ORA.b #!C3_SparkTile0
    STA.l C3Mod_SparkSprite
    REP #$20
    PHX
    LDX.w #C3Mod_SparkSprite
    JSL !C3_SprOneSmall
    PLX
    SEP #$20
.next:
    REP #$20
    TXA
    CLC
    ADC.w #!C3_SparkBytes
    TAX
    SEP #$20
    CPX.w #!C3_SparksEnd
    BNE .spark
    RTS

; $7E:6640 — C3Mod_SparkSprite (4 bytes, $6640–$6643)
; C3Mod_SparksTask's sprite record (tile, attribute, X, Y): the tile
; written each time, attribute $3C (palette 6, priority 3), at 0, 0
; from the base.
C3Mod_SparkSprite:
    db $00, $3C, $00, $00

; $7E:6644 — C3Mod_Prog7Text (44 bytes, $6644–$666F)
; The text C3Mod_TextTask draws (C3Mod_DrawText's codes; "[" is the
; full stop): "BUT..." at 16, 112, "THE FUTURE REFUSED" at 24, 132 and
; "TO CHANGE." at 144, 152.
C3Mod_Prog7Text:
    db !C3_TextPlace, $10, $70, "BUT[[["
    db !C3_TextPlace, $18, $84, "THE FUTURE REFUSED"
    db !C3_TextPlace, $90, $98, "TO CHANGE[", !C3_TextEnd

; $7E:6670 — C3Mod_FontWidths (32 bytes, $6670–$668F)
; C3Mod_DrawText's glyph widths in pixels for the codes $41-$60 ("A" to
; "Z", then "[" and the rest); 9 and up are 16x16 glyphs, below 9 8x16.
C3Mod_FontWidths:
    db $0B, $0A, $0A, $0B, $0B, $0B, $0A, $0B   ; A-H
    db $03, $09, $0B, $0A, $0E, $09, $0F, $0A   ; I-P
    db $0F, $0B, $0A, $0A, $0A, $0B, $0E, $0C   ; Q-X
    db $0B, $0A, $03, $00, $0F, $0F, $0F, $0F   ; Y, Z, [ ...

; $7E:6690 — C3Mod_FontTiles (32 bytes, $6690–$66AF)
; ... and their first sprite tiles (16x16 cells of the font at VRAM word
; $4000: 8 to a row of tiles).
C3Mod_FontTiles:
    db $00, $02, $04, $06, $08, $0A, $0C, $0E
    db $20, $22, $24, $26, $28, $2A, $2C, $2E
    db $40, $42, $44, $46, $48, $4A, $4C, $4E
    db $60, $62, $64, $66, $68, $6A, $6C, $6E

; $7E:66B0 — C3Mod_Font2To4 (45 bytes, $66B0–$66DC)
; Sends X 2bpp tiles read through WMDATA from Decomp_Dest (WMADDL/M set
; from it; WMADDH, the bank, as Decomp_ToWram left it) to VRAM as 4bpp
; tiles: each tile's 16 bytes go to VMDATAL / VMDATAH in pairs (planes
; 0 and 1), then 8 zero words (STY with Y = 0: planes 2 and 3), so
; VMAIN must step after the high byte. DP = DP_PPU meanwhile.
; Callers note: C3Mod_Prog7 ($625F), C3Mod_Prog1 ($6B1C) and
;   C3Mod_Prog10 ($854F).
; Entry: M=1 (the 8-bit port reads), X=0 (the 16-bit Y stores), DP any
;        (saved), DB=$00 (Decomp_Dest is absolute); X = the tile count
;        (not 0); the tiles unpacked just before; VMADD and VMAIN set.
; Exit:  M=1, X=0, DP restored; A = the last byte, X = 0, Y = 0; WMADD
;        and VMADD past the tiles.
C3Mod_Font2To4:
    PHD
    PEA.w !DP_PPU
    PLD
    LDY.w !Decomp_Dest
    STY.b WMADDL-!DP_PPU                ; and WMADDM
.tile:
    LDY.w #8
.row:
    LDA.b WMDATA-!DP_PPU
    STA.b VMDATAL-!DP_PPU
    LDA.b WMDATA-!DP_PPU
    STA.b VMDATAH-!DP_PPU
    DEY
    BNE .row
    STY.b VMDATAL-!DP_PPU               ; Y = 0: a zero word (and VMDATAH), 8 times
    STY.b VMDATAL-!DP_PPU
    STY.b VMDATAL-!DP_PPU
    STY.b VMDATAL-!DP_PPU
    STY.b VMDATAL-!DP_PPU
    STY.b VMDATAL-!DP_PPU
    STY.b VMDATAL-!DP_PPU
    STY.b VMDATAL-!DP_PPU
    DEX
    BNE .tile
    PLD
    RTS

%C3ModOrg($7E66DD)
; ============================================================
; Program 3: the field's picture waved, mosaicked and wiped
; ($66DD–$6B03)
; ============================================================

; $7E:66DD — C3Mod_Prog3NmiTask (66 bytes, $66DD–$671E)
; An NMI task of program 3: C3_OffsetTable ($00:0043, $80 bytes: two
; rows of 32 words) to VRAM word $7000 (BG3's map: mode 2's
; offset-per-tile table) by DMA channel 7 (two registers from VMDATAL,
; VMAIN = $80), then BG3HOFS from C3_Prog3Bg3Hofs ($003D / $003E) and
; BG1VOFS from page $0B00's var 1 (C3_Prog3ScrollY), each low byte, then
; high byte.
; Callers note: an NMI task added by script opcode $F8 at $699F
;   (C3Mod_Prog3Start).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X=0, DP any (the reads
;        are absolute), DB=$00.
; Exit:  M=1, X=0; A = var 1's high byte, X = C3_OffsetTableBytes; Y
;        unchanged; DMA channel 7's registers set.
C3Mod_Prog3NmiTask:
    LDX.w #!C3_Prog2Bg3Map
    STX.w VMADDL
    LDA.b #!DMAP_TwoRegs
    STA.w DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD7
    LDX.w #!C3_OffsetTable
    STX.w A1T7L
    LDA.b #0
    STA.w A1B7
    LDX.w #!C3_OffsetTableBytes
    STX.w DAS7L
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    STA.w MDMAEN                        ; MDMAEN_Ch7, the same value
    LDA.w !C3_Prog3Bg3Hofs
    STA.w BG3HOFS
    LDA.w !C3_Prog3Bg3Hofs+1
    STA.w BG3HOFS
    LDA.w !C3_ScriptPageB+!C3_Prog3ScrollY
    STA.w BG1VOFS
    LDA.w !C3_ScriptPageB+!C3_Prog3ScrollY+1
    STA.w BG1VOFS
    RTS

; $7E:671F — C3Mod_Prog3 (293 bytes, $671F–$6843)
; The program of C3Mod_ProgramTable entry 3. It loads no graphics: it
; works on what the field left in VRAM, in mode 2.
;   - M7A = $0100, M7B = 1 (MPYL/MPYM = $00/$01), then DMA channel 7
;     from the B bus (DMAP $81: MPYL and MPYM in turn) fills
;     $7E:1400-$167F with the words $0100;
;   - $580 bytes of VRAM from word $6140 read to $7E:1680 (DMA channel
;     7, B to A, RDVRAML/H; VMAIN = $80 for it). The RDVRAMH read before
;     it does not move the address while VMAIN steps after the low
;     byte, as C3Mod_Init's PPU clear leaves it (on its C3_BootIrqOn
;     path VMAIN is the field's);
;   - BG12NBA = $11; page $0A00 runs C3Mod_Prog3ScriptA and $0B00
;     C3Mod_Prog3ScriptB, or C3Mod_Prog3WipeA / WipeB when C3_EntryArg
;     bit 6 is set (16-bit BIT / BEQ); page $0A00's script once
;     (C3Mod_ScriptTaskA), and 0 written over the VRAM address of
;     C3Mod_MapNmiTask's LDX #$6000 (.vram, at $7840; a 16-bit STZ at
;     $7841 with C3Mod_ScriptTaskA's DB = $7E, before the PLB);
;   - DP = 0: C3_MapReady = 1 (INC from C3Mod_Init's 0) and
;     C3Mod_MapNmiTask (JSR), which, with C3_MapReady set, sends
;     $00:1400-$1BFF ($800 bytes, two registers) to VRAM from that
;     address, now word 0, and clears C3_MapReady: BG1's map (BG1SC =
;     0) is the field's map at $6000 with its first 10 rows made tile
;     $100 (the $0100 words); $1C (C3_Prog3TurnRows) written over
;     C3Mod_RotateMap's .rows operand, which is dead: program 3 never
;     installs C3Mod_RotateMap as the idle routine; the HDMA channels
;     of C3Mod_Prog3Hdma (C3Mod_SetupHdma: 0 window 2's left edge, 1
;     BG1HOFS, 2 BG2VOFS, 3 BG2SC); W12SEL = $33;
;   - C3_EntryArg bit 6 (8-bit BIT / BEQ): W12SEL = $FF, the fade steps
;     of C3Mod_Prog3FadeTask1-3 written over their operands (6, 8 and
;     8), C3_HdmaEnable = $0F (channels 0-3); else $0E (no window
;     channel);
;   - BGMODE = 2, BG1SC = 0, BG3SC = $70, TM = BG1, BG2 and the
;     sprites, TS = BG2 and the sprites, CGWSEL = add the sub screen,
;     CGADSUB = add on BG1, TMW = all layers, WH0 = 8, WH1 = $F8, WH3 =
;     $FF;
;   - FdVec_FFEE (PalAnim_StopAll); C3Mod_Prog3PalAnims with kind $50;
;     records 0 and 1: .Unk7 = .Unk8 = 0, .Unk5 = .Unk3 = 1; FdVec_FFF7
;     (PalAnim_TickAll, once); WinFx_C3ETableBank = $7E,
;     WinFx_C3ETablePtr = $F1C4, WinFx_WipeFrame = 0; 1 written over
;     C3Mod_ExitTask's .wipe_mode operand (the wipe out runs in mode
;     1).
; Callers note: C3Mod_ProgramTable entry 3 (C3Mod_Start's JSR (table,X)
;   at $300A).
; Entry: M=1, X=0, DP=0, DB=$00 (as C3Mod_Start calls the programs).
; Exit:  M=1, X=0, DP=0, DB=$00 (C3Mod_SetupHdma's); A = 1, X =
;        WinFx_C3ETablePtr's value, Y = $0090 (PalAnim_TickAll's).
; Calls: C3Mod_ScriptTaskA, C3Mod_MapNmiTask, C3Mod_SetupHdma, FdVec_FFEE
;   (JSL), C3Mod_Prog3PalAnims, FdVec_FFF7 (JSL).
C3Mod_Prog3:
    LDA.b #1
    STZ.w M7A
    STA.w M7A                           ; $0100
    LDA.b #1
    STA.w M7B
    STZ.w A1B7
    LDA.b #!BBAD_MPYL
    STA.w BBAD7
    LDX.w #!C3_Prog3Ones
    STX.w A1T7L
    LDX.w #!C3_Prog3OnesBytes
    STX.w DAS7L
    LDA.b #!DMAP_BtoA|!DMAP_TwoRegs
    STA.w DMAP7
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDX.w #!C3_Prog3MapSave
    STX.w VMADDL
    LDA.w RDVRAMH
    LDX.w #!BBAD_RDVRAML<<8|!DMAP_BtoA|!DMAP_TwoRegs
    STX.w DMAP7                         ; and BBAD7
    LDX.w #!C3_Prog3MapCopy
    STX.w A1T7L
    STZ.w A1B7
    LDX.w #!C3_Prog3MapBytes
    STX.w DAS7L
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    STA.w MDMAEN                        ; MDMAEN_Ch7, the same value
    LDA.b #!C3_Prog3Tiles
    STA.w BG12NBA
    REP #$20
    LDX.w #C3Mod_Prog3ScriptA
    LDY.w #C3Mod_Prog3ScriptB
    LDA.w !C3_EntryArg
    BIT.w #!C3_EntryWipeStart
    BEQ .scripts
    LDX.w #C3Mod_Prog3WipeA
    LDY.w #C3Mod_Prog3WipeB
.scripts:
    STX.w !C3_ScriptPageA+!C3Script_Ptr
    STY.w !C3_ScriptPageB+!C3Script_Ptr
    PHB
    JSR C3Mod_ScriptTaskA
    STZ.w C3Mod_MapNmiTask_vram+1       ; LDX #$6000's operand at $7841; DB = $7E here
    PLB
    LDA.w #0
    TCD
    SEP #$20
    INC.b !C3_MapReady
    JSR C3Mod_MapNmiTask
    LDA.b #!C3_Prog3TurnRows
    STA.l C3Mod_RotateMap_rows+1
    LDY.w #C3Mod_Prog3Hdma
    JSR C3Mod_SetupHdma
    LDA.b #!C3_Prog3Windows
    STA.w W12SEL
    LDX.w #!C3_Prog3HdmaOn
    LDA.w !C3_EntryArg
    BIT.b #!C3_EntryWipeStart
    BEQ .hdma
    LDA.b #!C3_Prog3WindowsWipe
    STA.w W12SEL
    LDA.b #!C3_WipeFadeStep1
    STA.l C3Mod_Prog3FadeTask1_step+1
    LDA.b #!C3_WipeFadeStep2
    STA.l C3Mod_Prog3FadeTask2_step+1
    LDA.b #!C3_WipeFadeStep2
    STA.l C3Mod_Prog3FadeTask3_step+1
    LDX.w #!C3_Prog3HdmaWipe
.hdma:
    TXA
    STA.w !C3_HdmaEnable
    LDA.b #!C3_Prog3BgMode
    STA.w BGMODE
    LDA.b #0
    STA.w BG1SC
    LDA.b #!C3_Prog2Bg3Sc
    STA.w BG3SC
    LDX.w #!TM_Bg1Bg2Obj|(!C3_Prog3Sub<<8)
    STX.w TM                            ; and TS
    LDX.w #!CGWSEL_AddSubscreen|(!CGADSUB_AddBg1<<8)
    STX.w CGWSEL                        ; and CGADSUB
    LDA.b #!TM_AllLayers
    STA.w TMW
    LDX.w #!C3_Prog3Window1
    STX.w WH0                           ; and WH1
    LDA.b #!C3_Prog3Window2Right
    STA.w WH3
    JSL !FdVec_FFEE
    LDA.b #!C3_FadeAnimKind
    JSR C3Mod_Prog3PalAnims
    TDC                                 ; A = 0 (DP = 0)
    STA.w FieldAnimB.Unk7
    STA.w FieldAnimB.Unk7+!FieldAnimB_Bytes
    STA.w FieldAnimB.Unk8
    STA.w FieldAnimB.Unk8+!FieldAnimB_Bytes
    INC A
    STA.w FieldAnimB.Unk5
    STA.w FieldAnimB.Unk5+!FieldAnimB_Bytes
    STA.w FieldAnimB.Unk3
    STA.w FieldAnimB.Unk3+!FieldAnimB_Bytes
    JSL !FdVec_FFF7
    LDA.b #!Bank7E
    STA.w !WinFx_C3ETableBank
    LDX.w #!C3_Prog3WipeTable
    STX.w !WinFx_C3ETablePtr
    STZ.w !WinFx_WipeFrame
    LDA.b #!WinFx_C3EMode1
    STA.l C3Mod_ExitTask_wipe_mode+1
    RTS

; $7E:6844 — C3Mod_Prog3WipeTask (26 bytes, $6844–$685D)
; A task of the C3_EntryArg bit 6 run: one frame of the kernel's wipe
; (WinFx_StepWipe, which writes the window table at $7E:F1C4 or
; $F2A4 in turn), then HDMA channel 0's table address (A1T0L/H) =
; C3Mod_WipeTableA (the buffer at $F1C4) when WinFx_WipeFrame is odd
; (LSR / BCC), else C3Mod_WipeTableB ($F2A4).
; Callers note: a task added by script opcode $FA at $689B
;   (C3Mod_Prog3WipeA).
; Entry: a task: M=0 (WinFx_StepWipe saves P; 8-bit set after), X=0,
;        DP any (WinFx_StepWipe sets its own), DB=$00 (WinFx_StepWipe's
;        C3_RandomByte; the variable and the register are absolute).
; Exit:  M=1, X=0; A = WinFx_WipeFrame / 2, X = the table's address; Y
;        as WinFx_StepWipe restores it.
; Calls: WinFx_StepWipe (JSL).
C3Mod_Prog3WipeTask:
    JSL !WinFx_StepWipe
    SEP #$20
    LDA.w !WinFx_WipeFrame
    LSR A
    BCC .even
    LDX.w #C3Mod_WipeTableA
    STX.w A1T0L
    RTS
.even:
    LDX.w #C3Mod_WipeTableB
    STX.w A1T0L
    RTS

; $7E:685E — C3Mod_Prog3Hdma (21 bytes, $685E–$6872)
; Program 3's HDMA channels (C3Mod_SetupHdma's records: DMAP, BBAD, the
; table and its bank): 0 indirect to WH2 (C3Mod_WipeTableA, the wipe's
; window edge per line), 1 indirect two writes to BG1HOFS
; (C3Mod_Prog3Bg1Hofs), 2 the same to BG2VOFS (C3Mod_Prog3Bg2Vofs), 3
; indirect to BG2SC (C3Mod_Prog3Bg2Sc); then the end.
C3Mod_Prog3Hdma:
    db !DMAP_HdmaIndirect, !BBAD_WH2 : dw C3Mod_WipeTableA : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_OneRegTwice, !BBAD_BG1HOFS : dw C3Mod_Prog3Bg1Hofs : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_OneRegTwice, !BBAD_BG2VOFS : dw C3Mod_Prog3Bg2Vofs : db !Bank7E
    db !DMAP_HdmaIndirect, !BBAD_BG2SC : dw C3Mod_Prog3Bg2Sc : db !Bank7E
    db !C3_HdmaListEnd

; $7E:6873 — C3Mod_Prog3Bg1Hofs (7 bytes, $6873–$6879)
; Channel 1's indirect table: 112 lines (repeat) from $7E:F000, 112
; from $F0E0 (C3Mod_LineShiftTask's words), then the end.
C3Mod_Prog3Bg1Hofs:
    db $F0 : dw !C3_LineShift
    db $F0 : dw !C3_LineShift+$E0
    db 0

; $7E:687A — C3Mod_Prog3Bg2Vofs (7 bytes, $687A–$6880)
; Channel 2's: BG2VOFS = 0 (the zero word of C3Mod_FillBytes) for 70
; lines, then C3_Prog3Bg2Vofs ($003F) from line 70; the end.
C3Mod_Prog3Bg2Vofs:
    db $46 : dw C3Mod_FillBytes+1
    db $01 : dw !C3_Prog3Bg2Vofs
    db 0

; $7E:6881 — C3Mod_Prog3Bg2Sc (7 bytes, $6881–$6887)
; Channel 3's: BG2SC = $60 for 70 lines, then $6A (the bytes of
; C3Mod_Prog3Bg2ScValues); the end.
C3Mod_Prog3Bg2Sc:
    db $46 : dw C3Mod_Prog3Bg2ScValues
    db $01 : dw C3Mod_Prog3Bg2ScValues+1
    db 0

; $7E:6888 — C3Mod_Prog3Bg2ScValues (2 bytes, $6888–$6889)
; The two BG2SC values: the map at $6000 (32x32), then at $6800
; (32x64).
C3Mod_Prog3Bg2ScValues:
    db $60, $6A

; $7E:688A — C3Mod_WipeTableA (7 bytes, $688A–$6890)
; Channel 0's indirect table for the wipe buffer at $7E:F1C4: 112 lines
; (repeat) from $F1C4, 112 from $F234; the end.
C3Mod_WipeTableA:
    db $F0 : dw !C3_Prog3WipeTable
    db $F0 : dw !C3_Prog3WipeTable+$70
    db 0

; $7E:6891 — C3Mod_WipeTableB (7 bytes, $6891–$6897)
; ... and for the second buffer, $F2A4 ($F1C4 + WinFx_Lines).
C3Mod_WipeTableB:
    db $F0 : dw !C3_Prog3WipeTable+!WinFx_Lines
    db $F0 : dw !C3_Prog3WipeTable+!WinFx_Lines+$70
    db 0

; $7E:6898 — C3Mod_Prog3WipeA (9 bytes, $6898–$68A0)
; Page $0A00's script in program 3 when C3_EntryArg bit 6 is set:
; C3Mod_Prog3Start (script call), C3Mod_Prog3WipeTask, then it waits for
; good.
C3Mod_Prog3WipeA:
    db !C3Op_Call : dw C3Mod_Prog3Start
    db !C3Op_TaskAdd : dw C3Mod_Prog3WipeTask
.l689E:
    db !C3Op_JumpYield : dw .l689E

; $7E:68A1 — C3Mod_Prog3WipeB (97 bytes, $68A1–$6901)
; Page $0B00's script in that run (its vars: 0 the wave's size
; C3_Prog3Wave, 1 BG1VOFS C3_Prog3ScrollY, 2 C3_Prog3Bg2Line): var 2 =
; $1B0, var 1 = -1, var 0 = 6; the wipe's sound (driver command
; C3_SndSfxA, C3_SfxWipe, C3_SfxArg1); a frame later C3_Brightness =
; full and WinFx_C3EMode = 2 (the wipe opens: WinFx_StepWipe lowers
; the window edges); 32 frames later C3Mod_ExitTask (a button wipes
; the screen out and ends the module) and, in the same frame, var 0 -
; 1; then var 0 - 1 five more times, after 60, 60, 25, 25 and 15 frames
; (the wave dies down); 30 frames later WinFx_C3EMode = 1 (the wipe
; closes) with the sound again; 32 frames
; later it ends the module (C3Op_End: C3_ExitFlag). The jump after it
; is never reached (C3Op_End does not move on). A $9x loop opcode
; yields on every pass, the last one too.
C3Mod_Prog3WipeB:
    db !C3Op_Set|2 : dw $01B0
    db !C3Op_Set|1 : dw -$1
    db !C3Op_Set|0 : dw $0006
    db !C3Op_Driver : dw !C3_SndSfxA|(!C3_SfxWipe<<8), !C3_SfxArg1
    db !C3Op_Yield
    db !C3Op_Poke8 : dw !C3_Brightness : db !C3_BrightnessFull
    db !C3Op_Poke8 : dw !WinFx_C3EMode : db !WinFx_C3EMode2
.l68B8:
    db !C3Op_LoopYield|1 : dw $001F, .l68B8             ; 32 passes
    db !C3Op_TaskAdd : dw C3Mod_ExitTask
    db !C3Op_Add|0 : dw -$1
.l68C3:
    db !C3Op_LoopYield|1 : dw $003B, .l68C3             ; 60 passes
    db !C3Op_Add|0 : dw -$1
.l68CB:
    db !C3Op_LoopYield|1 : dw $003B, .l68CB             ; 60 passes
    db !C3Op_Add|0 : dw -$1
.l68D3:
    db !C3Op_LoopYield|1 : dw $0018, .l68D3             ; 25 passes
    db !C3Op_Add|0 : dw -$1
.l68DB:
    db !C3Op_LoopYield|1 : dw $0018, .l68DB             ; 25 passes
    db !C3Op_Add|0 : dw -$1
.l68E3:
    db !C3Op_LoopYield|1 : dw $000E, .l68E3             ; 15 passes
    db !C3Op_Add|0 : dw -$1
.l68EB:
    db !C3Op_LoopYield|1 : dw $001D, .l68EB             ; 30 passes
    db !C3Op_Poke8 : dw !WinFx_C3EMode : db !WinFx_C3EMode1
    db !C3Op_Driver : dw !C3_SndSfxA|(!C3_SfxWipe<<8), !C3_SfxArg1
.l68F9:
    db !C3Op_LoopYield|1 : dw $001F, .l68F9             ; 32 passes
    db !C3Op_End
.l68FF:
    db !C3Op_JumpYield : dw .l68FF

; $7E:6902 — C3Mod_Prog3ScriptA (9 bytes, $6902–$690A)
; Page $0A00's script in program 3 otherwise: C3Mod_Prog3Start,
; C3Mod_FadeInTask, then it waits for good.
C3Mod_Prog3ScriptA:
    db !C3Op_Call : dw C3Mod_Prog3Start
    db !C3Op_TaskAdd : dw C3Mod_FadeInTask
.l6908:
    db !C3Op_JumpYield : dw .l6908

; $7E:690B — C3Mod_Prog3Unused (47 bytes, $690B–$6939)
; A page script that nothing starts (no reference to $690B was found;
; C3Mod_Prog3ScriptA never moves on): var 0 - 1 and var 5 + $B, + $A
; over 2 frames, 24 times; var 0 + 1 and var 5 + 6, 5, 5, 5 over 4
; frames, 24 times; var 0 = $20, var 5 = $200; then it waits.
C3Mod_Prog3Unused:
    db !C3Op_Add|0 : dw -$1
    db !C3Op_Add|5 : dw $000B
    db !C3Op_Yield
    db !C3Op_Add|5 : dw $000A
    db !C3Op_LoopYield|0 : dw $0017, C3Mod_Prog3Unused  ; 24 passes
.l691A:
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Add|5 : dw $0006
    db !C3Op_Yield
    db !C3Op_Add|5 : dw $0005
    db !C3Op_Yield
    db !C3Op_Add|5 : dw $0005
    db !C3Op_Yield
    db !C3Op_Add|5 : dw $0005
    db !C3Op_LoopYield|0 : dw $0017, .l691A             ; 24 passes
    db !C3Op_Set|0 : dw $0020
    db !C3Op_Set|5 : dw $0200
.l6937:
    db !C3Op_JumpYield : dw .l6937

; $7E:693A — C3Mod_Prog3ScriptB (74 bytes, $693A–$6983)
; Page $0B00's script in program 3 otherwise: var 2 = $1B0, var 1 = -1,
; var 0 = 6; var 0 - 1 six times, after 32, 120, 120, 50, 50 and 30
; frames; 120 frames later C3Mod_FadeOutExitTask (the screen fades out
; and the module ends); 64 frames later C3Op_End. A $9x loop opcode
; yields on every pass, the last one too.
C3Mod_Prog3ScriptB:
    db !C3Op_Set|2 : dw $01B0
    db !C3Op_Set|1 : dw -$1
    db !C3Op_Set|0 : dw $0006
.l6943:
    db !C3Op_LoopYield|1 : dw $001F, .l6943             ; 32 passes
    db !C3Op_Add|0 : dw -$1
.l694B:
    db !C3Op_LoopYield|1 : dw $0077, .l694B             ; 120 passes
    db !C3Op_Add|0 : dw -$1
.l6953:
    db !C3Op_LoopYield|1 : dw $0077, .l6953             ; 120 passes
    db !C3Op_Add|0 : dw -$1
.l695B:
    db !C3Op_LoopYield|1 : dw $0031, .l695B             ; 50 passes
    db !C3Op_Add|0 : dw -$1
.l6963:
    db !C3Op_LoopYield|1 : dw $0031, .l6963             ; 50 passes
    db !C3Op_Add|0 : dw -$1
.l696B:
    db !C3Op_LoopYield|1 : dw $001D, .l696B             ; 30 passes
    db !C3Op_Add|0 : dw -$1
.l6973:
    db !C3Op_LoopYield|1 : dw $0077, .l6973             ; 120 passes
    db !C3Op_TaskAdd : dw C3Mod_FadeOutExitTask
.l697B:
    db !C3Op_LoopYield|1 : dw $003F, .l697B             ; 64 passes
    db !C3Op_End
.l6981:
    db !C3Op_JumpYield : dw .l6981

; $7E:6984 — C3Mod_Prog3Start (43 bytes, $6984–$69AE)
; A script subroutine (opcode $F3) of both page $0A00 scripts: the
; tasks C3Mod_ScriptTaskA, C3Mod_ScriptTaskB, C3Mod_RotateMatrixTask
; (its C3_Turn* words, $1F-$2E, are read by nothing in program 3:
; C3Mod_RotateMap does not run there), C3Mod_LineShiftTask, C3Mod_Prog3OffsetTask,
; C3Mod_PalAnimTask and C3Mod_Prog3FadeTask1; the NMI tasks
; C3Mod_UploadPalette, C3Mod_OamUploadTask and C3Mod_Prog3NmiTask; page
; $0A00's var 0 = $20, var 1 = $10, var 2 = -$F, var 5 = $200; then it
; returns.
C3Mod_Prog3Start:
    db !C3Op_TaskAdd : dw C3Mod_ScriptTaskA
    db !C3Op_TaskAdd : dw C3Mod_ScriptTaskB
    db !C3Op_TaskAdd : dw C3Mod_RotateMatrixTask
    db !C3Op_TaskAdd : dw C3Mod_LineShiftTask
    db !C3Op_TaskAdd : dw C3Mod_Prog3OffsetTask
    db !C3Op_TaskAdd : dw C3Mod_PalAnimTask
    db !C3Op_TaskAdd : dw C3Mod_Prog3FadeTask1
    db !C3Op_NmiAdd : dw C3Mod_UploadPalette
    db !C3Op_NmiAdd : dw C3Mod_OamUploadTask
    db !C3Op_NmiAdd : dw C3Mod_Prog3NmiTask
    db !C3Op_Set|0 : dw $0020
    db !C3Op_Set|1 : dw $0010
    db !C3Op_Set|2 : dw -$F
    db !C3Op_Set|5 : dw $0200
    db !C3Op_Return

; $7E:69AF — C3Mod_Prog3OffsetTask (116 bytes, $69AF–$6A22)
; A task: the wave of mode 2's offset-per-tile table. s = page $0B00's
; var 0 AND 7 (stored back: C3_Prog3Wave); the first row of
; C3_OffsetTable (BG3's horizontal offsets, 32 words at $0043): the
; first 16 = -8s + s, + 2s, ... (CLC adds to C3_TmpF0, X to $20: CPX /
; BNE), the next 16 back down by s each (SEC), each AND $3FF OR $2000
; (bit 13: for BG1); C3_Prog3Bg3Hofs + s (CLC); C3_Prog3Bg2Vofs =
; page $0B00's var 2 / 4 (two LSRs), and var 2 - 1 (16-bit DEC). Then,
; 8-bit: C3_MosaicTimer - 1; at 0 (BNE), unless C3_MosaicSize is 0
; (BEQ), the size - 1 and MOSAIC = it x 16 + 1 (BG1 only; three ASLs,
; SEC / ROL), C3_MosaicTimer = 20. No other write to C3_MosaicSize was
; found in the traced module (C3Mod_MapNmiTask and
; C3Mod_RotateMatrixTask do not touch it), and this one runs only when it is not 0, so it stays 0
; from C3Mod_Init's clear and the mosaic steps never run; the timer
; counts from 0, a check every 256 frames.
; Callers note: a task added by script opcode $FA at $6990
;   (C3Mod_Prog3Start).
; Entry: a task: M=0, X=0 (16-bit index), DP=0 (C3_TmpF0, the mosaic
;        bytes), DB=$00 (the table and page $0B00 are absolute).
; Exit:  M=1, X=0; X = C3_OffsetTableRow; A = the low byte of page
;        $0B00's var 2 / 4 (the timer not at 0), or C3_MosaicSize (0),
;        or C3_MosaicFrames; Y unchanged.
C3Mod_Prog3OffsetTask:
    LDA.w !C3_ScriptPageB+!C3_Prog3Wave
    AND.w #!C3_Prog3WaveMask
    STA.w !C3_ScriptPageB+!C3_Prog3Wave
    EOR.w #!Eng_Invert16
    INC A
    ASL A
    ASL A
    ASL A
    STA.b !C3_TmpF0                     ; -8s
    LDX.w #0
.up:
    LDA.b !C3_TmpF0
    CLC
    ADC.w !C3_ScriptPageB+!C3_Prog3Wave
    STA.b !C3_TmpF0
    AND.w #!C3_OffsetMask
    ORA.w #!C3_OffsetBg1
    STA.w !C3_OffsetTable,X
    INX
    INX
    CPX.w #!C3_OffsetTableHalf
    BNE .up
.down:
    LDA.b !C3_TmpF0
    SEC
    SBC.w !C3_ScriptPageB+!C3_Prog3Wave
    STA.b !C3_TmpF0
    AND.w #!C3_OffsetMask
    ORA.w #!C3_OffsetBg1
    STA.w !C3_OffsetTable,X
    INX
    INX
    CPX.w #!C3_OffsetTableRow
    BNE .down
    LDA.w !C3_Prog3Bg3Hofs
    CLC
    ADC.w !C3_ScriptPageB+!C3_Prog3Wave
    STA.w !C3_Prog3Bg3Hofs
    LDA.w !C3_ScriptPageB+!C3_Prog3Bg2Line
    LSR A
    LSR A
    STA.w !C3_Prog3Bg2Vofs
    DEC.w !C3_ScriptPageB+!C3_Prog3Bg2Line
    SEP #$20
    DEC.b !C3_MosaicTimer
    BNE .done
    LDA.b !C3_MosaicSize
    BEQ .done
    DEC A
    STA.b !C3_MosaicSize
    ASL A
    ASL A
    ASL A
    SEC                                 ; BG1's mosaic bit
    ROL A
    STA.w MOSAIC
    LDA.b #!C3_MosaicFrames
    STA.b !C3_MosaicTimer
.done:
    RTS

; $7E:6A23 — C3Mod_LineShiftTask (46 bytes, $6A23–$6A50)
; A task: BG1HOFS per line for HDMA channel 1 (C3_LineShift, $7E:F000,
; 224 words): every other line = page $0B00's var 0 (C3_Prog3Wave),
; the others 0 (word k is line k, from 0). On odd frames (C3_FrameCount's
; bit 0 by LSR: C = 1, .odd) the wave goes to words 0, 2, 4.. (the even
; lines); on even frames (BCC, .even) to the odd words (the odd lines).
; X to $1C0 (CPX / BNE: equality).
; Callers note: a task added by script opcode $FA at $698D
;   (C3Mod_Prog3Start).
; Entry: a task: M=0, X=0 (16-bit index), DP=0 (C3_FrameCount), DB any
;        (set to $7E with PHK / PLB, restored by C3Mod_RunTasks).
; Exit:  M=0, X=0, DB = $7E; A = the size, X = C3_LineShiftBytes; Y
;        unchanged.
C3Mod_LineShiftTask:
    PHK
    PLB
    LDX.w #0
    LDA.b !C3_FrameCount
    LSR A
    LDA.w !C3_ScriptPageB+!C3_Prog3Wave
    BCC .even
.odd:
    STA.w !C3_LineShift,X
    INX
    INX
    STZ.w !C3_LineShift,X
    INX
    INX
    CPX.w #!C3_LineShiftBytes
    BNE .odd
    BRA .done
.even:
    STZ.w !C3_LineShift,X
    INX
    INX
    STA.w !C3_LineShift,X
    INX
    INX
    CPX.w #!C3_LineShiftBytes
    BNE .even
.done:
    RTS

; $7E:6A51 — C3Mod_Prog3FadeTask1 (35 bytes, $6A51–$6A73)
; A task: waits until FieldAnimB record 0 is done (.Unk0 = 0: BEQ; the
; palette animation clears it at its end), then C3Mod_Prog3PalAnims
; with kind $50 (a fade) and both records' step (.Unk3) = .step's
; operand (1, or 6 written by C3Mod_Prog3 in the C3_EntryArg bit 6
; run), .Unk5 = 1, and hands its entry to C3Mod_Prog3FadeTask2.
; Callers note: a task added by script opcode $FA at $6996
;   (C3Mod_Prog3Start).
; Entry: a task: M=0 (8-bit set here), X=0, DP any, DB=$00 (FieldAnimB
;        is absolute).
; Exit:  RTS with M=1, A = .Unk0 (not 0); else JMP C3Mod_TaskReplace
;        with X = C3Mod_Prog3FadeTask2.
; Calls: C3Mod_Prog3PalAnims.
C3Mod_Prog3FadeTask1:
    SEP #$20
    LDA.w FieldAnimB.Unk0
    BEQ .next
    RTS
.next:
    LDA.b #!C3_FadeAnimKind
    JSR C3Mod_Prog3PalAnims
.step:
    LDA.b #1                            ; C3Mod_Prog3 may write 6 here
    STA.w FieldAnimB.Unk3
    STA.w FieldAnimB.Unk3+!FieldAnimB_Bytes
    LDA.b #1
    STA.w FieldAnimB.Unk5
    STA.w FieldAnimB.Unk5+!FieldAnimB_Bytes
    LDX.w #C3Mod_Prog3FadeTask2
    JMP C3Mod_TaskReplace

; $7E:6A74 — C3Mod_Prog3FadeTask2 (35 bytes, $6A74–$6A96)
; As C3Mod_Prog3FadeTask1, then kind $40 (a fade towards white) with
; the step .step's operand (4, or 8), and hands over to
; C3Mod_Prog3FadeTask3.
; Callers note: a task: LDX #C3Mod_Prog3FadeTask2 / JMP
;   C3Mod_TaskReplace at $6A6E, $6A71 (C3Mod_Prog3FadeTask1).
; Entry: a task: M=0 (8-bit set here), X=0, DP any, DB=$00.
; Exit:  RTS with M=1, A = .Unk0 (not 0); else JMP C3Mod_TaskReplace
;        with X = C3Mod_Prog3FadeTask3.
; Calls: C3Mod_Prog3PalAnims.
C3Mod_Prog3FadeTask2:
    SEP #$20
    LDA.w FieldAnimB.Unk0
    BEQ .next
    RTS
.next:
    LDA.b #!C3_WhitenAnimKind
    JSR C3Mod_Prog3PalAnims
.step:
    LDA.b #4                            ; C3Mod_Prog3 may write 8 here
    STA.w FieldAnimB.Unk3
    STA.w FieldAnimB.Unk3+!FieldAnimB_Bytes
    LDA.b #1
    STA.w FieldAnimB.Unk5
    STA.w FieldAnimB.Unk5+!FieldAnimB_Bytes
    LDX.w #C3Mod_Prog3FadeTask3
    JMP C3Mod_TaskReplace

; $7E:6A97 — C3Mod_Prog3FadeTask3 (54 bytes, $6A97–$6ACC)
; As before, then TM = BG1, BG2 and the sprites and TS = none (a 16-bit
; store), kind $40 with the step .step's operand (3, or 8), .Unk5 = 1,
; level .Unk7 = $FF and target .Unk8 = 0 (back from white), and the
; task ends.
; Callers note: a task: LDX #C3Mod_Prog3FadeTask3 / JMP
;   C3Mod_TaskReplace at $6A91, $6A94 (C3Mod_Prog3FadeTask2).
; Entry: a task: M=0 (8-bit set here), X=0 (the 16-bit TM store,
;        C3Mod_TaskEnd's), DP any, DB=$00.
; Exit:  RTS with M=1, A = .Unk0 (not 0); else JMP C3Mod_TaskEnd with A
;        = 0.
; Calls: C3Mod_Prog3PalAnims.
C3Mod_Prog3FadeTask3:
    SEP #$20
    LDA.w FieldAnimB.Unk0
    BEQ .next
    RTS
.next:
    LDX.w #!TM_Bg1Bg2Obj
    STX.w TM                            ; and TS = 0
    LDA.b #!C3_WhitenAnimKind
    JSR C3Mod_Prog3PalAnims
.step:
    LDA.b #3                            ; C3Mod_Prog3 may write 8 here
    STA.w FieldAnimB.Unk3
    STA.w FieldAnimB.Unk3+!FieldAnimB_Bytes
    LDA.b #1
    STA.w FieldAnimB.Unk5
    STA.w FieldAnimB.Unk5+!FieldAnimB_Bytes
    LDA.b #!C3_FadeAnimTarget
    STA.w FieldAnimB.Unk7
    STA.w FieldAnimB.Unk7+!FieldAnimB_Bytes
    LDA.b #0
    STA.w FieldAnimB.Unk8
    STA.w FieldAnimB.Unk8+!FieldAnimB_Bytes
    JMP C3Mod_TaskEnd

; $7E:6ACD — C3Mod_Prog3PalAnims (55 bytes, $6ACD–$6B03)
; FieldAnimB records 0 and 1 (run by C3Mod_PalAnimTask) as palette
; animations of kind A: .Unk0 = A, colours $20-$3F (record 0) and
; $50-$6F (record 1): .Unk1 = $20 / $50, .Unk2 = $20; .Unk4 = 0, .Unk6
; = 0, level .Unk7 = 0, target .Unk8 = $FF. The callers set .Unk3 and
; .Unk5 (and the level and target to fade back).
; Callers note: C3Mod_Prog3 ($680E), C3Mod_Prog3FadeTask1 ($6A5B),
;   C3Mod_Prog3FadeTask2 ($6A7E) and C3Mod_Prog3FadeTask3 ($6AA7).
; Entry: M=1 (8-bit stores), X any, DP any, DB=$00 (FieldAnimB is
;        absolute); A = the kind byte.
; Exit:  M=1; A = $FF; X, Y unchanged.
C3Mod_Prog3PalAnims:
    STA.w FieldAnimB.Unk0
    STA.w FieldAnimB.Unk0+!FieldAnimB_Bytes
    LDA.b #!C3_Prog3Colours0
    STA.w FieldAnimB.Unk1
    LDA.b #!C3_Prog3Colours1
    STA.w FieldAnimB.Unk1+!FieldAnimB_Bytes
    LDA.b #!C3_Prog3AnimColours
    STA.w FieldAnimB.Unk2
    STA.w FieldAnimB.Unk2+!FieldAnimB_Bytes
    STZ.w FieldAnimB.Unk4
    STZ.w FieldAnimB.Unk4+!FieldAnimB_Bytes
    LDA.b #0
    STA.w FieldAnimB.Unk6
    STA.w FieldAnimB.Unk6+!FieldAnimB_Bytes
    LDA.b #0
    STA.w FieldAnimB.Unk7
    STA.w FieldAnimB.Unk7+!FieldAnimB_Bytes
    LDA.b #!C3_FadeAnimTarget
    STA.w FieldAnimB.Unk8
    STA.w FieldAnimB.Unk8+!FieldAnimB_Bytes
    RTS

%C3ModOrg($7E6B04)
; ============================================================
; Program 1: a page of the staff credits ($6B04–$6E41)
; ============================================================

; $7E:6B04 — C3Mod_Prog1 (225 bytes, $6B04–$6BE4)
; The program of C3Mod_ProgramTable entry 1: one page of the staff
; credits, the next one each time it runs (C3_ResultWord's low byte
; counts the pages 1-5).
;   - C3Mod_CreditsGfx (colours; pack 58's first $200 bytes to VRAM
;     word 0 as they are); pack 58 from its byte $100 on ($7F:0300,
;     inside the $200 already sent) made 4bpp at VRAM word $0100 ($36
;     tiles, C3Mod_Font2To4: $360 bytes, to $7F:065F, $60 past the
;     pack's $400);
;   - VRAM words $0400-$07FF (BG1's map) cleared, and OAM's high table
;     (32 bytes) cleared, both by DMA channel 7 from a fixed zero source
;     (GfxRom_D2's first byte: two registers for VRAM, OAMDATA for OAM,
;     OAMADD = $0100); OAM's low table (512 bytes, OAMADD = 0) filled
;     with $E0 (the same way, from C3Mod_MathValues' COLDATA byte at
;     .sky + 1: every sprite at X = Y = $E0, off the screen);
;   - WMADDH = 0 (bank $7E: the STA of $7E keeps only bit 0); the page
;     n = C3_ResultWord's low byte + 1, back to 1 after 5 (CMP #6 /
;     BNE: equality), stored as a word; C3Mod_CreditsNames[n - 1]
;     through WMDATA (C3Mod_CreditsBg: the names on BG1), then
;     C3Mod_CreditsRoles[n - 1] from OAM address 0 (C3Mod_CreditsSprites:
;     the roles as sprites);
;   - TM = BG1 and the sprites, BG1SC = $04, OBSEL = 0 (8x8 and 16x16
;     sprites, tiles from VRAM word 0), C3_FadeStep = C3_FadeTimer = 1,
;     the tasks C3Mod_FadeInTask and C3Mod_CreditsTask.
; Callers note: C3Mod_ProgramTable entry 1 (C3Mod_Start's JSR (table,X)
;   at $300A).
; Entry: M=1, X=0, DP=0, DB=$00 (as C3Mod_Start calls the programs).
; Exit:  M=1, X=0, DP = DP_PPU (C3Mod_CreditsBg and C3Mod_CreditsSprites
;        set it and nothing here restores it; C3Mod_Start's next calls
;        take any DP and C3_ModuleFrame sets 0), DB=$00; A =
;        C3Mod_CreditsTask's address, X its offset in C3_TaskList
;        (C3Mod_TaskAdd's); Y = 0 (C3Mod_Font2To4's).
; Calls: C3Mod_CreditsGfx, C3Mod_Font2To4, C3Mod_CreditsBg,
;   C3Mod_CreditsSprites, C3Mod_TaskAdd.
C3Mod_Prog1:
    LDX.w #0
    STX.w VMADDL
    JSR C3Mod_CreditsGfx
    LDX.w #!C3_CreditsFontVram
    STX.w VMADDL
    LDX.w #!C3_CreditsFont
    STX.w !Decomp_Dest
    LDX.w #!C3_CreditsFontTiles
    JSR C3Mod_Font2To4
    LDX.w #!C3_CreditsMap
    STX.w VMADDL
    LDX.w #!BBAD_VMDATAL<<8|!DMAP_FixedSource|!DMAP_TwoRegs
    STX.w DMAP7                         ; and BBAD7
    LDX.w #!GfxRom_D2&$FFFF             ; a zero byte
    STX.w A1T7L
    LDA.b #!GfxRom_D2>>16
    STA.w A1B7
    LDX.w #!C3_CreditsMapBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDX.w #!C3_OamHighAddr
    STX.w OAMADDL
    LDX.w #!BBAD_OAMDATA<<8|!DMAP_FixedSource
    STX.w DMAP7                         ; and BBAD7
    LDX.w #!GfxRom_D2&$FFFF
    STX.w A1T7L
    LDA.b #!GfxRom_D2>>16
    STA.w A1B7
    LDX.w #!C3_OamHighBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDX.w #0
    STX.w OAMADDL
    LDX.w #!BBAD_OAMDATA<<8|!DMAP_FixedSource
    STX.w DMAP7                         ; and BBAD7
    LDX.w #C3Mod_MathValues_sky+1       ; a $E0 byte
    STX.w A1T7L
    LDA.b #!Bank7E
    STA.w A1B7
    LDX.w #!C3_OamLowBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDA.b #!Bank7E
    STA.w WMADDH                        ; bit 0 only: bank $7E
    REP #$20
    LDA.w !C3_ResultWord
    AND.w #!Eng_LowByteMask
    INC A
    CMP.w #!C3_CreditsPages+1
    BNE .page
    LDA.w #1
.page:
    STA.w !C3_ResultWord
    DEC A
    ASL A
    TAX
    LDA.l C3Mod_CreditsNames,X
    STA.w WMADDL                        ; and WMADDM
    SEP #$20
    PHX
    JSR C3Mod_CreditsBg
    PLX
    REP #$20
    LDA.l C3Mod_CreditsRoles,X
    STA.w WMADDL
    LDA.w #0
    STA.w OAMADDL                       ; and OAMADDH
    SEP #$20
    JSR C3Mod_CreditsSprites
    LDA.b #!TM_Bg1|!TM_Obj
    STA.w TM
    LDA.b #!C3_CreditsBg1Sc
    STA.w BG1SC
    LDA.b #0
    STA.w OBSEL
    LDX.w #!C3_Prog2Fade
    STX.w !C3_FadeStep                  ; and C3_FadeTimer
    LDX.w #C3Mod_FadeInTask
    JSR C3Mod_TaskAdd
    LDX.w #C3Mod_CreditsTask
    JSR C3Mod_TaskAdd
.done:
    RTS

; $7E:6BE5 — C3Mod_CreditsTask (20 bytes, $6BE5–$6BF8)
; A task: C3_OamPos = 0 and C3_OamHiPtr = Oam_HighTable (each frame);
; when C3_FrameCount is $5A (16-bit CMP / BNE: equality, frame 90 of
; the module's count) it hands its entry to C3Mod_FadeOutExitTask (the
; screen fades out and the module ends); else RTS (C3Mod_Prog1's).
; Callers note: a task: LDX #C3Mod_CreditsTask / JSR $395E at $6BDE,
;   $6BE1 (C3Mod_Prog1).
; Entry: a task: M=0, X=0 (16-bit stores and C3Mod_TaskReplace's), DP=0
;        (C3_OamPos.., C3_FrameCount are direct page), DB any.
; Exit:  RTS with M=0, A = C3_FrameCount, X = Oam_HighTable; or JMP
;        C3Mod_TaskReplace with X = C3Mod_FadeOutExitTask.
C3Mod_CreditsTask:
    STZ.b !C3_OamPos
    LDX.w #!Oam_HighTable
    STX.b !C3_OamHiPtr
    LDA.b !C3_FrameCount
    CMP.w #!C3_CreditsFrames
    BNE C3Mod_Prog1_done
    LDX.w #C3Mod_FadeOutExitTask
    JMP C3Mod_TaskReplace

; $7E:6BF9 — C3Mod_CreditsGfx (84 bytes, $6BF9–$6C4C)
; The credits' colours and font: with DB = $7E (PEA $007E / PLB; the
; PLB after takes the $00), colours 0-3 and $80-$83 of C3_PaletteBuf =
; black, $77BD, $4631 and $1CE7 (16-bit stores); then pack 58 to
; $7F:0200 (C3Mod_UnpackPack) and its first $200 bytes (Decomp_OutLen
; set to $200) to VRAM from the address set by the caller
; (C3Mod_DmaUnpacked: C3_DmaMode two registers, C3_DmaBbad VMDATAL,
; VMAIN = $80).
; Callers note: C3Mod_Prog1 ($6B0A).
; Entry: M=1, X=0 (the 16-bit colour stores), DP any, DB any (set to $7E,
;        then $00); VMADD set.
; Exit:  M=1, X=0, DB=$00; A = MDMAEN_Ch7, X = Decomp_OutLen ($200)
;        (C3Mod_DmaUnpacked's); Y as C3Mod_UnpackPack leaves it.
; Calls: C3Mod_UnpackPack, C3Mod_DmaUnpacked (JSL).
C3Mod_CreditsGfx:
    PEA.w !Bank7E                       ; PLB takes the $7E; the $00 stays for the next PLB
    PLB
    LDX.w #0
    STX.w !C3_CreditsPalA
    STX.w !C3_CreditsPalB
    LDX.w #!C3_CreditsColour1
    STX.w !C3_CreditsPalA+2
    STX.w !C3_CreditsPalB+2
    LDX.w #!C3_CreditsColour2
    STX.w !C3_CreditsPalA+4
    STX.w !C3_CreditsPalB+4
    LDX.w #!C3_CreditsColour3
    STX.w !C3_CreditsPalA+6
    STX.w !C3_CreditsPalB+6
    PLB
    LDA.b #!DMAP_TwoRegs
    STA.w !C3_DmaMode
    LDA.b #!BBAD_VMDATAL
    STA.w !C3_DmaBbad
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDA.b #!Bank7F
    STA.w !Decomp_DestBank
    LDX.w #!C3_BitmapSrc
    STX.w !Decomp_Dest
    LDX.w #58*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_CreditsFontBytes
    STX.w !Decomp_OutLen
    JSL C3Mod_DmaUnpacked
    RTS

; $7E:6C4D — C3Mod_CreditsBg (36 bytes, $6C4D–$6C70)
; Writes text records read through WMDATA (WMADD set by the caller) to
; BG1's map, with DP = DP_PPU: a record is VMADDL, VMADDH, then
; characters to a 0; each character c to VMDATAL (c - $40, SEC: "A" is
; tile 1; a space, $20, is made $40 first: tile 0) with VMDATAH = 0;
; a first byte of $FF (CMP / BEQ) ends the list.
; Callers note: C3Mod_Prog1 ($6BAB).
; Entry: M=1 (8-bit port accesses), X any, DP any (set to DP_PPU, not
;        restored), DB any (all direct page); WMADD at the records;
;        VMAIN stepping after the high byte.
; Exit:  M=1, DP = DP_PPU; A = $FF; X, Y unchanged; WMADD past the list.
C3Mod_CreditsBg:
    PEA.w !DP_PPU
    PLD
.record:
    LDA.b WMDATA-!DP_PPU
    CMP.b #!C3_CreditsEnd
    BEQ .done
    STA.b VMADDL-!DP_PPU
    LDA.b WMDATA-!DP_PPU
    STA.b VMADDH-!DP_PPU
.char:
    LDA.b WMDATA-!DP_PPU
    BEQ .record
    CMP.b #!C3_TextSpace
    BNE .tile
    LDA.b #!C3_CreditsTile0
.tile:
    SEC
    SBC.b #!C3_CreditsTile0
    STA.b VMDATAL-!DP_PPU
    STZ.b VMDATAH-!DP_PPU
    BRA .char
.done:
    RTS

; $7E:6C71 — C3Mod_CreditsSprites (59 bytes, $6C71–$6CAB)
; Writes text records read through WMDATA as 8x8 sprites straight to
; OAM (OAMDATA, from the OAM address the caller set), with DP =
; DP_PPU: a record is X, Y (kept in C3_SprBaseX / C3_SprBaseY's low
; bytes, absolute), then characters to a 0; each one but a space ($20:
; BEQ) is a sprite at X, Y with tile c - $21 (SEC: "A" is tile $20)
; and attribute 0; X + 5 after every character (CLC), spaces too. A
; first byte of $FF (CMP / BEQ) ends the list.
; Callers note: C3Mod_Prog1 ($6BC0).
; Entry: M=1 (8-bit port accesses), X any, DP any (set to DP_PPU, not
;        restored), DB=$00 (C3_SprBaseX/Y are absolute); WMADD at the
;        records; OAMADD set.
; Exit:  M=1, DP = DP_PPU; A = $FF; X, Y unchanged; WMADD past the list,
;        OAMADD past the sprites.
C3Mod_CreditsSprites:
    PEA.w !DP_PPU
    PLD
.record:
    LDA.b WMDATA-!DP_PPU
    CMP.b #!C3_CreditsEnd
    BEQ .done
    STA.w !C3_SprBaseX
    LDA.b WMDATA-!DP_PPU
    STA.w !C3_SprBaseY
.char:
    LDA.b WMDATA-!DP_PPU
    BEQ .record
    CMP.b #!C3_TextSpace
    BEQ .next
    SEC
    SBC.b #!C3_CreditsSprTile0
    PHA
    LDA.w !C3_SprBaseX
    STA.b OAMDATA-!DP_PPU
    LDA.w !C3_SprBaseY
    STA.b OAMDATA-!DP_PPU
    PLA
    STA.b OAMDATA-!DP_PPU
    LDA.b #0
    STA.b OAMDATA-!DP_PPU               ; the attribute
.next:
    LDA.w !C3_SprBaseX
    CLC
    ADC.b #!C3_CreditsSprStep
    STA.w !C3_SprBaseX
    BRA .char
.done:
    RTS

; $7E:6CAC — C3Mod_CreditsNames (10 bytes, $6CAC–$6CB5)
; The pages' names (C3Mod_CreditsBg's records), by page - 1.
C3Mod_CreditsNames:
    dw C3Mod_Credits1Names, C3Mod_Credits2Names, C3Mod_Credits3Names
    dw C3Mod_Credits4Names, C3Mod_Credits5Names

; $7E:6CB6 — C3Mod_CreditsRoles (10 bytes, $6CB6–$6CBF)
; ... and their roles (C3Mod_CreditsSprites' records).
C3Mod_CreditsRoles:
    dw C3Mod_Credits1Roles, C3Mod_Credits2Roles, C3Mod_Credits3Roles
    dw C3Mod_Credits4Roles, C3Mod_Credits5Roles

; $7E:6CC0 — C3Mod_Credits1Names (70 bytes, $6CC0–$6D05)
; Page 1's names: each record the VRAM word of its first tile (low
; byte first: $0528 is row 9, column 8 of the map at $0400), then the
; text and a 0; $FF ends the list.
C3Mod_Credits1Names:
    dw $0528 : db "KAZUHIKO AOKI", 0
    dw $05A8 : db "TAKASHI TOKITA", 0
    dw $05C8 : db "YOSHINORI KITASE", 0
    dw $05E8 : db "AKIHIKO MATSUI", 0
    db !C3_CreditsEnd

; $7E:6D06 — C3Mod_Credits1Roles (23 bytes, $6D06–$6D1C)
; Page 1's roles: each record X, Y, the text, a 0; $FF ends it.
C3Mod_Credits1Roles:
    db $36, $3C, "PRODUCER", 0
    db $36, $5C, "DIRECTER", 0
    db !C3_CreditsEnd

; $7E:6D1D — C3Mod_Credits2Names (52 bytes, $6D1D–$6D50)
C3Mod_Credits2Names:
    dw $0528 : db "AKIRA TORIYAMA", 0
    dw $05A8 : db "YUJI HORII", 0
    dw $05C8 : db "HIRONOBU SAKAGUCHI", 0
    db !C3_CreditsEnd

; $7E:6D51 — C3Mod_Credits2Roles (33 bytes, $6D51–$6D71)
C3Mod_Credits2Roles:
    db $36, $3C, "CHARACTER DESIGN", 0
    db $36, $5C, "SUPERVISOR", 0
    db !C3_CreditsEnd

; $7E:6D72 — C3Mod_Credits3Names (50 bytes, $6D72–$6DA3)
C3Mod_Credits3Names:
    dw $0528 : db "YASUNORI MITSUDA", 0
    dw $05A8 : db "MINORU AKAO", 0
    dw $0628 : db "EIJI NAKAMURA", 0
    db !C3_CreditsEnd

; $7E:6DA4 — C3Mod_Credits3Roles (42 bytes, $6DA4–$6DCD)
C3Mod_Credits3Roles:
    db $36, $3C, "MUSIC", 0
    db $36, $5C, "SOUND PROGRAM", 0
    db $36, $7C, "SOUND ENGINEER", 0
    db !C3_CreditsEnd

; $7E:6DCE — C3Mod_Credits4Names (36 bytes, $6DCE–$6DF1)
C3Mod_Credits4Names:
    dw $0588 : db "KEIZO KOKUBO", 0
    dw $05A8 : db "KATSUHISA HIGUCHI", 0
    db !C3_CreditsEnd

; $7E:6DF2 — C3Mod_Credits4Roles (11 bytes, $6DF2–$6DFC)
C3Mod_Credits4Roles:
    db $36, $54, "PROGRAM", 0
    db !C3_CreditsEnd

; $7E:6DFD — C3Mod_Credits5Names (58 bytes, $6DFD–$6E36)
C3Mod_Credits5Names:
    dw $0588 : db "YASUHIKO KAMATA", 0
    dw $05A8 : db "MASANORI HOSHINO", 0
    dw $05C8 : db "TETSUYA TAKAHASHI", 0
    db !C3_CreditsEnd

; $7E:6E37 — C3Mod_Credits5Roles (11 bytes, $6E37–$6E41)
C3Mod_Credits5Roles:
    db $36, $54, "GRAPHIC", 0
    db !C3_CreditsEnd

%C3ModOrg($7E6E42)
; ============================================================
; Program 5: the party whirled into a gate ($6E42–$78DC)
; ============================================================
; Program 5 works on the field it was entered from: its BG1 map turned
; in software (C3Mod_RotateMap), two circular windows, a waving BG3 and
; the party's four sprites (three PCs and the field's first other
; object) spun round the screen's centre and drawn with the battle
; sprite sets of bank $E4. A sprite record is 22 bytes at
; C3_CharRecs ($51, DP=0) + 0, $16, $2C or $42 (the C3_Char* offsets).

; $7E:6E42 — C3Mod_LoadCharTiles (92 bytes, $6E42–$6E9D)
; A battle sprite frame's 16 tiles to $7E:1C00: with X = the sprite set
; x 3 and A = the frame x 40, C3_CharFramePtr (a long pointer at
; $1B-$1D) = C3_SprFramesPtr[set] + A (CLC; its bank byte from the table too),
; and the set's tile pointer C3_SprTilesPtr[set] written over
; C3Mod_CopyCharTile's operands (self-modifying: the low word over
; .base / .flip_base, the bank over the MVN's source bank .bank and
; the PEA .flip_bank); WMADDH = 0 (bank $7E), WMADDL/M = Y; then
; C3Mod_CopyCharTile 16 times (15 JSRs, then it falls in).
; Callers note: C3Mod_CharsTask ($774D).
; Entry: M=0 (8-bit set for the bank bytes), X=0 (16-bit X and Y), DP=0
;        (C3_CharFramePtr is direct page), DB=$00 (the STZ to WMADDH
;        and STY to WMADDL are absolute; C3Mod_CharsTask's DB; the table
;        reads and the patches are long); X = the set x 3, A = the frame
;        x 40, Y = the tiles' address ($1C00).
; Exit:  as the last C3Mod_CopyCharTile: M=0, X=0, DP=0, DB=$00; Y past
;        the 16 tiles ($1E00).
; Calls: C3Mod_CopyCharTile.
C3Mod_LoadCharTiles:
    CLC
    ADC.l !C3_SprFramesPtr,X
    STA.b !C3_CharFramePtr
    LDA.l !C3_SprTilesPtr,X
    STA.l C3Mod_CopyCharTile_base+1
    STA.l C3Mod_CopyCharTile_flip_base+1
    SEP #$20
    LDA.l !C3_SprFramesPtr+2,X
    STA.b !C3_CharFramePtr+2
    LDA.l !C3_SprTilesPtr+2,X
    STA.l C3Mod_CopyCharTile_bank+2
    STA.l C3Mod_CopyCharTile_flip_bank+1
    STZ.w WMADDH
    REP #$20
    STY.w WMADDL                        ; and WMADDM
    JSR C3Mod_CopyCharTile
    JSR C3Mod_CopyCharTile
    JSR C3Mod_CopyCharTile
    JSR C3Mod_CopyCharTile
    JSR C3Mod_CopyCharTile
    JSR C3Mod_CopyCharTile
    JSR C3Mod_CopyCharTile
    JSR C3Mod_CopyCharTile
    JSR C3Mod_CopyCharTile
    JSR C3Mod_CopyCharTile
    JSR C3Mod_CopyCharTile
    JSR C3Mod_CopyCharTile
    JSR C3Mod_CopyCharTile
    JSR C3Mod_CopyCharTile
    JSR C3Mod_CopyCharTile             ; and it falls into the 16th

; $7E:6E9E — C3Mod_CopyCharTile (384 bytes, $6E9E–$701D)
; One tile of the frame: the next word e of C3_CharFramePtr (+ 2). Bit
; 14 (the second ASL's carry: BCS) flips it; e's low 11 bits x 32 + the
; tiles' base (.base's or .flip_base's operand) is the 32-byte tile, the
; ADC taking bit 11 of e as its carry (five ASLs, no CLC: a quirk, + 1
; byte when bit 11 is set).
;   - unflipped: MVN from the tiles' bank (.bank's operand) to bank $00
;     at Y (32 bytes; Y + 32; DB = $00 after);
;   - flipped: WMADDL/M = Y (kept in C3_TmpF0), DB = the tiles' bank
;     (PEA .flip_bank / PLB; the second PLB takes the $00), DP = DP_PPU;
;     each of the 32 bytes through BitReverseTable to WMDATA (the
;     pixels of each row reversed: a horizontal flip; XBA after the
;     LDA #$2100 makes B = 0 for the TAX); then DP = 0 and WMADD = Y =
;     the saved Y + $20 (REP #$21: C = 0).
; Callers note: C3Mod_LoadCharTiles ($6E71, $6E74, $6E77, $6E7A, $6E7D,
;   $6E80, $6E83, $6E86, $6E89, $6E8C, $6E8F, $6E92, $6E95, $6E98, $6E9B;
;   the 16th falls in).
; Entry: M=0, X=0, DP=0 (C3_CharFramePtr), DB=$00 (the flipped path's
;        STY to WMADDL is absolute; C3Mod_LoadCharTiles' DB, and $00
;        after each tile); Y = the destination ($00 bank); WMADDH = 0
;        (bank $7E); the operands patched. WMADDL/M need not hold Y:
;        only the flipped path uses WMADD, and it sets it from Y first.
; Exit:  M=0, X=0, DP=0, DB=$00; Y = the destination + 32; WMADD = Y
;        after a flipped tile, but left where it was after an unflipped
;        one (the MVN moves Y only; harmless, as above); A, X changed
;        (unflipped: A = $FFFF, X past the source; flipped: A = Y, X =
;        the last byte read).
C3Mod_CopyCharTile:
    LDA.b [!C3_CharFramePtr]
    INC.b !C3_CharFramePtr
    INC.b !C3_CharFramePtr
    ASL A
    ASL A
    BCS .flip
    ASL A
    ASL A
    ASL A
.base:
    ADC.w #0                            ; the tiles' address (C3Mod_LoadCharTiles); C = bit 11 of e
    TAX
    LDA.w #!C3_TileBytes-1
.bank:
    MVN !Bank00,!Bank00                 ; lint-ok: MVN operands are bank bytes (the source written by C3Mod_LoadCharTiles)
    RTS
.flip:
    ASL A
    ASL A
    ASL A
.flip_base:
    ADC.w #0                            ; the tiles' address; C = bit 11 of e
    STY.w WMADDL                        ; and WMADDM
    STY.b !C3_TmpF0
    TAY
.flip_bank:
    PEA.w 0                             ; the tiles' bank written here; PLB takes it, the $00 stays
    PLB
    LDA.w #!DP_PPU
    TCD
    XBA                                 ; B = 0 for the TAX
    SEP #$20
    %C3ModFlipByte($00)
    %C3ModFlipByte($01)
    %C3ModFlipByte($02)
    %C3ModFlipByte($03)
    %C3ModFlipByte($04)
    %C3ModFlipByte($05)
    %C3ModFlipByte($06)
    %C3ModFlipByte($07)
    %C3ModFlipByte($08)
    %C3ModFlipByte($09)
    %C3ModFlipByte($0A)
    %C3ModFlipByte($0B)
    %C3ModFlipByte($0C)
    %C3ModFlipByte($0D)
    %C3ModFlipByte($0E)
    %C3ModFlipByte($0F)
    %C3ModFlipByte($10)
    %C3ModFlipByte($11)
    %C3ModFlipByte($12)
    %C3ModFlipByte($13)
    %C3ModFlipByte($14)
    %C3ModFlipByte($15)
    %C3ModFlipByte($16)
    %C3ModFlipByte($17)
    %C3ModFlipByte($18)
    %C3ModFlipByte($19)
    %C3ModFlipByte($1A)
    %C3ModFlipByte($1B)
    %C3ModFlipByte($1C)
    %C3ModFlipByte($1D)
    %C3ModFlipByte($1E)
    %C3ModFlipByte($1F)
    PLB
    REP #$21
    LDA.w #0
    TCD
    LDA.b !C3_TmpF0
    ADC.w #!C3_TileBytes
    STA.w WMADDL                        ; and WMADDM
    TAY
    RTS

; $7E:701E — C3Mod_CharSprites (116 bytes, $701E–$7091)
; Four 16x16 sprites of a battle sprite frame at C3_SprBaseX/Y, from
; C3_OamPos on: with X = the set x 3 and A = the frame x 40,
; C3_CharFramePtr = C3_SprFramesPtr[set] + A + $20 (CLC both: past the
; frame's 16 tile words, to its four X / Y byte pairs; the bank word
; from the table, a 16-bit store over $1D-$1E). The tiles are .tiles'
; operand (C3Mod_DrawChar writes the record's tile and attribute word
; there), + 2, 4 and 6 (16-bit stores of tile and attribute). For each
; sprite: X = its byte + C3_SprBaseX (16-bit, CLC), then CMP #$100:
; BMI (below $100 as a difference) or BCS ($100 or more, unsigned)
; both keep it, so the LDA #$9801 after them is never reached (a
; quirk); the word stored at the record (its high byte overwritten
; next); the high-table pair from the top of the byte at C3_OamHiPtr:
; ASL puts X's bit 15 in C, ROR moves it in, SEC / ROR adds the size
; bit, so X bit 8 is the sign of X, not its bit 8 (an X from $100 up
; shows at X - $100: a quirk); Y = its byte + C3_SprBaseY (8-bit,
; CLC). C3_OamHiPtr + 1 after every 4 sprites (offset AND $F = 0).
; Callers note: C3Mod_DrawChar ($77A9).
; Entry: M=0, X=0 (16-bit indexes), DP=0 (C3_CharFramePtr, C3_OamPos..,
;        C3_TmpF0), DB=$00 (the OAM shadow is absolute); X = the set x
;        3, A = the frame x 40; .tiles' operand written.
; Exit:  M=0, X=0; C3_OamPos advanced (X = it), C3_OamHiPtr as it
;        moved; Y = 8; A changed; C3_TmpF0 = 0.
C3Mod_CharSprites:
    CLC
    ADC.l !C3_SprFramesPtr,X
    CLC
    ADC.w #!C3_FrameTileBytes
    STA.b !C3_CharFramePtr
    LDA.l !C3_SprFramesPtr+2,X
    STA.b !C3_CharFramePtr+2               ; and the byte after it
    LDX.b !C3_OamPos
    LDY.w #0
.tiles:
    LDA.w #0                            ; C3Mod_DrawChar writes the tile and attribute word here
    STA.w !Oam_LowTable+2,X
    INC A
    INC A
    STA.w !Oam_LowTable+6,X
    INC A
    INC A
    STA.w !Oam_LowTable+10,X
    INC A
    INC A
    STA.w !Oam_LowTable+14,X
    SEP #$20
    LDA.b #4
    STA.b !C3_TmpF0
.sprite:
    LDA.b [!C3_CharFramePtr],Y
    INY
    REP #$20
    AND.w #!Eng_LowByteMask
    CLC
    ADC.b !C3_SprBaseX
    CMP.w #!C3_CharRightEdge
    BMI .x
    BCS .x
    LDA.w #!C3_CharHidden               ; never reached
.x:
    STA.w !Oam_LowTable,X
    ASL A                               ; X's bit 15 to C
    SEP #$20
    LDA.b (!C3_OamHiPtr)
    ROR A
    SEC                                 ; the size bit: 16x16
    ROR A
    STA.b (!C3_OamHiPtr)
    LDA.b [!C3_CharFramePtr],Y
    INY
    CLC
    ADC.b !C3_SprBaseY
    STA.w !Oam_LowTable+1,X
    INX
    INX
    INX
    INX
    TXA
    AND.b #!C3_OamGroupMask
    BNE .count
    REP #$20
    INC.b !C3_OamHiPtr
    SEP #$20
.count:
    DEC.b !C3_TmpF0
    BNE .sprite
    REP #$20
    STX.b !C3_OamPos
    RTS

; $7E:7092 — C3Mod_Prog5 (197 bytes, $7092–$7156)
; The program of C3Mod_ProgramTable entry 5:
;   - the circles' centre WinFx_ArgX / ArgY = $80, $70 and their table
;     bank WinFx_TableBank = $7E (bit 0 clear: bank $7E);
;   - the field's map buffer Map_BufC800 ($7E:C800, $800 bytes) copied
;     to $00:0C00 (C3_MapSource, C3Mod_RotateMap's source) and $00:1400
;     (C3_MapTurned) by two MVNs (bank $7E to $00);
;   - C3_FadeStep = C3_FadeTimer = 2; page $0A00 runs C3Mod_Prog5Script
;     and $0B00 C3Mod_Prog5ScriptB, each once now (C3Mod_ScriptTaskA,
;     C3Mod_ScriptTaskB; DB kept around them); C3Mod_RotateMap written
;     over C3Mod_Start's idle call (.wait_exit + 1: it runs between
;     frames);
;   - the HDMA channels of C3Mod_Prog5Hdma (C3Mod_SetupHdma), C3_Brightness
;     = full, the sprites' records (C3Mod_InitChars);
;   - DP = DP_PPU: $0C00's $800 bytes to VRAM word $6800 (DMA channel 7,
;     two registers from VMDATAL, VMAIN = $80; started after
;     C3Mod_WaitVblank, in a vertical blank: the screen is on); BG3SC =
;     $70, BG1SC = $60, CGWSEL = add the sub screen, CGADSUB = $42 (half
;     colour math on BG2), W12SEL = $8B, W34SEL = $0C, WOBJSEL = 0,
;     BG1HOFS / BG1VOFS / BG2HOFS / BG2VOFS = 0 (each written twice),
;     BGMODE = 1; C3_CircleR1 and C3_CircleR2's low bytes = 1 (so the
;     first C3Mod_CircleTask builds both circles), C3_HdmaEnable =
;     channels 0-3, TM = BG2, BG3 and the sprites, TS = BG1, TMW = BG1,
;     BG2, BG3 and the sprites, TSW = BG1.
; Callers note: C3Mod_ProgramTable entry 5 (C3Mod_Start's JSR (table,X)
;   at $300A).
; Entry: M=1, X=0, DP=0, DB=$00 (as C3Mod_Start calls the programs).
; Exit:  M=1, X=0, DP = DP_PPU (not restored: C3Mod_Start's next calls
;        take any DP and C3_ModuleFrame sets 0), DB=$00; A =
;        C3_Prog5HdmaOn, X = C3_Prog5Windows; Y as C3Mod_InitChars and
;        C3Mod_WaitVblank leave it.
; Calls: C3Mod_ScriptTaskA, C3Mod_ScriptTaskB, C3Mod_SetupHdma,
;   C3Mod_InitChars, C3Mod_WaitVblank.
C3Mod_Prog5:
    LDA.b #!C3_Prog5CentreX
    STA.w !WinFx_ArgX
    LDA.b #!C3_Prog5CentreY
    STA.w !WinFx_ArgY
    LDA.b #!Bank7E
    STA.w !WinFx_TableBank
    REP #$20
    LDX.w #!Map_BufC800&$FFFF
    LDY.w #!C3_MapSource
    LDA.w #!C3_MapBytes-1
    MVN !Bank00,!Bank7E                 ; lint-ok: MVN operands are bank bytes ($7E:C800 to $00:0C00)
    LDX.w #!Map_BufC800&$FFFF
    LDY.w #!C3_MapTurned
    LDA.w #!C3_MapBytes-1
    MVN !Bank00,!Bank7E                 ; lint-ok: MVN operands are bank bytes ($7E:C800 to $00:1400)
    LDX.w #!C3_Prog5Fade
    STX.w !C3_FadeStep                  ; and C3_FadeTimer
    LDA.w #C3Mod_Prog5ScriptB
    STA.w !C3_ScriptPageB+!C3Script_Ptr
    LDA.w #C3Mod_Prog5Script
    STA.w !C3_ScriptPageA+!C3Script_Ptr
    PHB
    JSR C3Mod_ScriptTaskA
    JSR C3Mod_ScriptTaskB
    LDA.w #C3Mod_RotateMap
    STA.w C3Mod_Start_wait_exit+1
    PLB
    SEP #$20
    LDY.w #C3Mod_Prog5Hdma
    JSR C3Mod_SetupHdma
    LDA.b #!C3_BrightnessFull
    STA.w !C3_Brightness
    JSR C3Mod_InitChars
    PEA.w !DP_PPU
    PLD
    LDX.w #!BBAD_VMDATAL<<8|!DMAP_TwoRegs
    STX.w DMAP7                         ; and BBAD7
    LDX.w #!C3_MapSource
    STX.w A1T7L
    LDX.w #!C3_Prog5Bg2Map
    STX.w VMADDL
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    STZ.w A1B7
    LDX.w #!C3_MapBytes
    STX.w DAS7L
    JSR C3Mod_WaitVblank
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDA.b #!C3_Prog2Bg3Sc
    STA.b BG3SC-!DP_PPU
    LDA.b #!C3_Prog5Bg1Sc
    STA.b BG1SC-!DP_PPU
    LDX.w #!CGWSEL_AddSubscreen|(!C3_Prog5Math<<8)
    STX.b CGWSEL-!DP_PPU                ; and CGADSUB
    LDX.w #!C3_Prog5W12Sel|(!C3_Prog5W34Sel<<8)
    STX.b W12SEL-!DP_PPU                ; and W34SEL
    LDA.b #0
    STA.b WOBJSEL-!DP_PPU
    STA.b BG1HOFS-!DP_PPU
    STA.b BG1HOFS-!DP_PPU
    STA.b BG1VOFS-!DP_PPU
    STA.b BG1VOFS-!DP_PPU
    STA.b BG2HOFS-!DP_PPU
    STA.b BG2HOFS-!DP_PPU
    STA.b BG2VOFS-!DP_PPU
    STA.b BG2VOFS-!DP_PPU
    LDA.b #!C3_BgMode1
    STA.b BGMODE-!DP_PPU
    STA.w !C3_CircleR1
    STA.w !C3_CircleR2
    LDA.b #!C3_Prog5HdmaOn
    STA.w !C3_HdmaEnable
    LDX.w #!C3_Prog5Screens
    STX.b TM-!DP_PPU                    ; and TS
    LDX.w #!C3_Prog5Windows
    STX.b TMW-!DP_PPU                   ; and TSW
    RTS

; $7E:7157 — C3Mod_Prog5Script (54 bytes, $7157–$718C)
; Page $0A00's script in program 5 (its vars: 0 the turn's scale
; C3_TurnScale, 5 its angle C3_TurnAngle, 1 and 2 its centre
; C3_TurnX / C3_TurnY): the tasks C3Mod_ScriptTaskA, ScriptTaskB,
; C3Mod_CircleTask, C3Mod_CharSpinTask, C3Mod_CharsTask,
; C3Mod_RotateMatrixTask and C3Mod_Bg3WaveTask; var 0 = $20, var 5 =
; $200, var 1 = var 2 = -$10, var 6 = 1 (not read in this program);
; the NMI tasks C3Mod_MapNmiTask, C3Mod_UploadPalette,
; C3Mod_OamUploadTask, C3Mod_HideSprites, C3Mod_CharTilesNmiTask and
; C3Mod_Prog5PalNmiTask; then C3Mod_Prog5Drift.
C3Mod_Prog5Script:
    db !C3Op_TaskAdd : dw C3Mod_ScriptTaskA
    db !C3Op_TaskAdd : dw C3Mod_ScriptTaskB
    db !C3Op_TaskAdd : dw C3Mod_CircleTask
    db !C3Op_TaskAdd : dw C3Mod_CharSpinTask
    db !C3Op_TaskAdd : dw C3Mod_CharsTask
    db !C3Op_TaskAdd : dw C3Mod_RotateMatrixTask
    db !C3Op_TaskAdd : dw C3Mod_Bg3WaveTask
    db !C3Op_Set|0 : dw $0020
    db !C3Op_Set|5 : dw $0200
    db !C3Op_Set|1 : dw -$10
    db !C3Op_Set|2 : dw -$10
    db !C3Op_Set|6 : dw $0001
    db !C3Op_NmiAdd : dw C3Mod_MapNmiTask
    db !C3Op_NmiAdd : dw C3Mod_UploadPalette
    db !C3Op_NmiAdd : dw C3Mod_OamUploadTask
    db !C3Op_NmiAdd : dw C3Mod_HideSprites
    db !C3Op_NmiAdd : dw C3Mod_CharTilesNmiTask
    db !C3Op_NmiAdd : dw C3Mod_Prog5PalNmiTask

; $7E:718D — C3Mod_Prog5Drift (6 bytes, $718D–$7192)
; Each frame C3Mod_PickDrift (which may move the script on to a drift
; script), then a jump to itself that yields; the drift scripts jump
; back here.
C3Mod_Prog5Drift:
    db !C3Op_CallW : dw C3Mod_PickDrift
    db !C3Op_JumpYield : dw C3Mod_Prog5Drift

; $7E:7193 — C3Mod_MosaicTimerTask (18 bytes, $7193–$71A4)
; A task: C3_MosaicDelay - 1 (8-bit); at 0 (BNE) it is reloaded from
; C3_MosaicEvery and C3_MosaicStep = (it + 1) AND 7 (the mosaic size
; C3Mod_Prog5MosaicTask shows).
; Callers note: a task added by script opcode $FA at $71AE
;   (C3Mod_Prog5ScriptB), removed by $F9 at $71DC.
; Entry: a task: M=0 (8-bit set here), X any, DP=0 (the bytes are
;        direct page), DB any.
; Exit:  M=1; A = the new step when the delay reached 0, else A as on
;        entry (the DEC is on memory); X, Y unchanged.
C3Mod_MosaicTimerTask:
    SEP #$20
    DEC.b !C3_MosaicDelay
    BNE .done
    LDA.b !C3_MosaicEvery
    STA.b !C3_MosaicDelay
    LDA.b !C3_MosaicStep
    INC A
    AND.b #!C3_MosaicStepMask
    STA.b !C3_MosaicStep
.done:
    RTS

; $7E:71A5 — C3Mod_Prog5ScriptB (225 bytes, $71A5–$7285)
; Page $0B00's script in program 5 (its vars: 0 the second circle's
; radius C3_Circle2, 6 the first's C3_Circle1, 2 the spin's speed
; C3_SpinSpeed, 8 the BG3 wave's step C3_WaveStep): var 0 = 0, var 6
; = $88, var 8 = 4; C3Mod_MosaicTimerTask and C3Mod_Prog5MosaicTask;
; the mosaic steps every 20 frames (C3_MosaicDelay = C3_MosaicEvery =
; 20), then every 10, 8 and 4 frames, 60 frames each; C3Mod_MosaicTimerTask
; removed; a frame later C3_MosaicStep = $FF (random sizes) and
; C3_DriftOn = 1 (C3Mod_PickDrift starts drift scripts); 120 frames
; later 32 times: 10 frames, then var 0 + 1 and var 2 - 1 (the inner
; $92 loop yields 10 times, the outer $80 loop does not yield); 16
; times: 4 frames, var 0 + 1; C3_SongReq = $3A; 48 times: 4 frames, var
; 0 + 1 (the second circle grows to 96); 40 frames later
; C3Mod_RadiusTask; 20 frames later WOBJSEL = $0C and C3_DriftOn = 0;
; var 0 - 3 a frame for 32 frames (to 0), then var 0 = var 2 = 0; the
; mosaic size 6, 5, 4, 3, 2, 1 and 0 for 6, 8, 10, 16, 20, 20 and 20
; frames; C3Mod_Prog5MosaicTask removed and C3Mod_FadeOutExitTask
; added; then it waits for good (the C3Op_End after it is never
; reached). A $9x loop opcode yields on every pass, the last one too.
C3Mod_Prog5ScriptB:
    db !C3Op_Set|0 : dw $0000
    db !C3Op_Set|6 : dw $0088
    db !C3Op_Set|8 : dw $0004
    db !C3Op_TaskAdd : dw C3Mod_MosaicTimerTask
    db !C3Op_TaskAdd : dw C3Mod_Prog5MosaicTask
    db !C3Op_Poke8 : dw !C3_MosaicDelay : db 20
    db !C3Op_Poke8 : dw !C3_MosaicEvery : db 20
.l71BC:
    db !C3Op_LoopYield|1 : dw $003B, .l71BC             ; 60 passes
    db !C3Op_Poke8 : dw !C3_MosaicEvery : db 10
.l71C5:
    db !C3Op_LoopYield|1 : dw $003B, .l71C5             ; 60 passes
    db !C3Op_Poke8 : dw !C3_MosaicEvery : db 8
.l71CE:
    db !C3Op_LoopYield|1 : dw $003B, .l71CE             ; 60 passes
    db !C3Op_Poke8 : dw !C3_MosaicEvery : db 4
.l71D7:
    db !C3Op_LoopYield|1 : dw $003B, .l71D7             ; 60 passes
    db !C3Op_TaskRemove : dw C3Mod_MosaicTimerTask
    db !C3Op_Yield
    db !C3Op_Poke8 : dw !C3_MosaicStep : db !C3_MosaicRandom
    db !C3Op_Poke8 : dw !C3_DriftOn : db 1
.l71E8:
    db !C3Op_LoopYield|1 : dw $0077, .l71E8             ; 120 passes
.l71ED:
    db !C3Op_LoopYield|2 : dw $0009, .l71ED             ; 10 passes
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Add|2 : dw -$1
    db !C3Op_Loop|0 : dw $001F, .l71ED                  ; 32 passes
.l71FD:
    db !C3Op_LoopYield|2 : dw $0003, .l71FD             ; 4 passes
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Loop|0 : dw $000F, .l71FD                  ; 16 passes
    db !C3Op_Poke8 : dw !C3_SongReq : db !C3_SongProg7
.l720E:
    db !C3Op_LoopYield|2 : dw $0003, .l720E             ; 4 passes
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Loop|0 : dw $002F, .l720E                  ; 48 passes
.l721B:
    db !C3Op_LoopYield|1 : dw $0027, .l721B             ; 40 passes
    db !C3Op_TaskAdd : dw C3Mod_RadiusTask
.l7223:
    db !C3Op_LoopYield|1 : dw $0013, .l7223             ; 20 passes
    db !C3Op_Ppu, !C3_Prog5ObjWindows, WOBJSEL-!DP_PPU
    db !C3Op_Poke8 : dw !C3_DriftOn : db 0
.l722F:
    db !C3Op_Add|0 : dw -$3
    db !C3Op_LoopYield|0 : dw $001F, .l722F             ; 32 passes
    db !C3Op_Set|0 : dw $0000
    db !C3Op_Set|2 : dw $0000
    db !C3Op_Poke8 : dw !C3_MosaicStep : db 6
.l7241:
    db !C3Op_LoopYield|1 : dw $0005, .l7241             ; 6 passes
    db !C3Op_Poke8 : dw !C3_MosaicStep : db 5
.l724A:
    db !C3Op_LoopYield|1 : dw $0007, .l724A             ; 8 passes
    db !C3Op_Poke8 : dw !C3_MosaicStep : db 4
.l7253:
    db !C3Op_LoopYield|1 : dw $0009, .l7253             ; 10 passes
    db !C3Op_Poke8 : dw !C3_MosaicStep : db 3
.l725C:
    db !C3Op_LoopYield|1 : dw $000F, .l725C             ; 16 passes
    db !C3Op_Poke8 : dw !C3_MosaicStep : db 2
.l7265:
    db !C3Op_LoopYield|1 : dw $0013, .l7265             ; 20 passes
    db !C3Op_Poke8 : dw !C3_MosaicStep : db 1
.l726E:
    db !C3Op_LoopYield|1 : dw $0013, .l726E             ; 20 passes
    db !C3Op_Poke8 : dw !C3_MosaicStep : db 0
.l7277:
    db !C3Op_LoopYield|1 : dw $0013, .l7277             ; 20 passes
    db !C3Op_TaskRemove : dw C3Mod_Prog5MosaicTask
    db !C3Op_TaskAdd : dw C3Mod_FadeOutExitTask
.l7282:
    db !C3Op_JumpYield : dw .l7282
    db !C3Op_End

; $7E:7286 — C3Mod_PickDrift (22 bytes, $7286–$729B)
; A script routine (opcode $x0, C3Mod_CallW): while C3_DriftOn's byte
; is 0 (16-bit read AND $FF / BEQ) nothing; else page $0A00's script
; goes on in one of C3Mod_DriftScripts' four, by bits 1-2 of a random
; byte (C3Mod_TableRandom AND 6: B = DP's low byte, 0 with DP =
; $0A00): C3Script_Ptr = the entry, 2 bytes before the script (C3_RunScript
; adds 2 after the call).
; Callers note: script opcode $F0 at $718D (C3Mod_Prog5Drift).
; Entry: M=0, X=0 (the 16-bit index), DP = $0A00 (C3Mod_TableRandom's
;        page boundary), DB = $7E (the table read and the store are
;        absolute; C3_RunScript's).
; Exit:  M=0, X=0; A = the entry (X = 0-6), or 0 with X unchanged; Y
;        unchanged.
; Calls: C3Mod_TableRandom.
C3Mod_PickDrift:
    LDA.w !C3_DriftOn
    AND.w #!Eng_LowByteMask
    BEQ .done
    JSR C3Mod_TableRandom
    AND.w #!C3_DriftPickMask
    TAX
    LDA.w C3Mod_DriftScripts,X
    STA.w !C3_ScriptPageA+!C3Script_Ptr
.done:
    RTS

; $7E:729C — C3Mod_DriftScripts (8 bytes, $729C–$72A3)
; C3Mod_PickDrift's four scripts, each entry 2 before it.
C3Mod_DriftScripts:
    dw C3Mod_Drift0-2, C3Mod_Drift1-2, C3Mod_Drift2-2, C3Mod_Drift3-2

; $7E:72A4 — C3Mod_Drift0 (31 bytes, $72A4–$72C2)
; Page $0A00's var 0 (the turn's scale) + 1 every 3 frames 8 times, - 1
; every 2 frames 20 times, + 1 every 2 frames 12 times; then back to
; C3Mod_Prog5Drift.
C3Mod_Drift0:
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Yield
    db !C3Op_Yield
    db !C3Op_LoopYield|0 : dw $0007, C3Mod_Drift0       ; 8 passes
.l72AE:
    db !C3Op_Add|0 : dw -$1
    db !C3Op_Yield
    db !C3Op_LoopYield|0 : dw $0013, .l72AE             ; 20 passes
.l72B7:
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Yield
    db !C3Op_LoopYield|0 : dw $000B, .l72B7             ; 12 passes
    db !C3Op_Jump : dw C3Mod_Prog5Drift

; $7E:72C3 — C3Mod_Drift1 (33 bytes, $72C3–$72E3)
; Var 5 (the angle) + $10 and var 0 + 2 a frame for 32 frames, var 5 +
; 8 a frame for 48, var 5 + 4 and var 0 - 2 a frame for 32; then back.
C3Mod_Drift1:
    db !C3Op_Add|5 : dw $0010
    db !C3Op_Add|0 : dw $0002
    db !C3Op_LoopYield|0 : dw $001F, C3Mod_Drift1       ; 32 passes
.l72CE:
    db !C3Op_Add|5 : dw $0008
    db !C3Op_LoopYield|0 : dw $002F, .l72CE             ; 48 passes
.l72D6:
    db !C3Op_Add|5 : dw $0004
    db !C3Op_Add|0 : dw -$2
    db !C3Op_LoopYield|0 : dw $001F, .l72D6             ; 32 passes
    db !C3Op_Jump : dw C3Mod_Prog5Drift

; $7E:72E4 — C3Mod_Drift2 (24 bytes, $72E4–$72FB)
; Var 5 - $20 a frame for 16 frames, - $10 for 24, - 8 for 16; then on
; into C3Mod_Drift3 (back).
C3Mod_Drift2:
    db !C3Op_Add|5 : dw -$20
    db !C3Op_LoopYield|0 : dw $000F, C3Mod_Drift2       ; 16 passes
.l72EC:
    db !C3Op_Add|5 : dw -$10
    db !C3Op_LoopYield|0 : dw $0017, .l72EC             ; 24 passes
.l72F4:
    db !C3Op_Add|5 : dw -$8
    db !C3Op_LoopYield|0 : dw $000F, .l72F4             ; 16 passes

; $7E:72FC — C3Mod_Drift3 (3 bytes, $72FC–$72FE)
; No drift: straight back to C3Mod_Prog5Drift.
C3Mod_Drift3:
    db !C3Op_Jump : dw C3Mod_Prog5Drift

; $7E:72FF — C3Mod_RadiusTask (23 bytes, $72FF–$7315)
; A task: C3Mod_RadiusStep for the four sprite records (X = 0, $16 and
; $2C by JSR, then $42 falling in).
; Callers note: a task added by script opcode $FA at $7220
;   (C3Mod_Prog5ScriptB).
; Entry: a task: M=0 (8-bit set here), X=0, DP=0 (the records), DB any.
; Exit:  as C3Mod_RadiusStep (falling in): M=1, X = $42.
; Calls: C3Mod_RadiusStep (and falls into it).
C3Mod_RadiusTask:
    SEP #$20
    LDX.w #!C3_Char0
    JSR C3Mod_RadiusStep
    LDX.w #!C3_Char1
    JSR C3Mod_RadiusStep
    LDX.w #!C3_Char2
    JSR C3Mod_RadiusStep
    LDX.w #!C3_Char3

; $7E:7316 — C3Mod_RadiusStep (15 bytes, $7316–$7324)
; One record's C3_CharRadius steps away from $80 (8-bit CMP #$80:
; equal kept, BEQ): r - $80 with bit 7 set, so r from $00 to $7F, goes
; down by one (BMI / DEC), else, $81-$FF, up (INC). A radius below $80
; shrinks to 0, then turns $FF, which the next step takes back to 0
; (wrapping): the sprite stays within a pixel of the centre (the
; signed multiply of C3Mod_CharSpin reads $FF as -1); one above $80
; grows to $FF, then 0, $FF, ...
; Callers note: C3Mod_RadiusTask ($7304, $730A, $7310; the fourth call
;   falls in).
; Entry: M=1, X=0 (16-bit index), DP=0, DB any; X = the record.
; Exit:  M=1; A = the new radius; X, Y unchanged.
C3Mod_RadiusStep:
    LDA.b !C3_CharRadius,X
    CMP.b #!C3_CharRadiusMid
    BEQ .store
    BMI .down
    INC A
    BRA .store
.down:
    DEC A
.store:
    STA.b !C3_CharRadius,X
    RTS

; $7E:7325 — C3Mod_CircleTask (47 bytes, $7325–$7353)
; A task: the two window circles, each rebuilt only when its radius
; changed (16-bit CMP / BEQ: equal keeps the table). Page $0B00's
; var 6 (C3_Circle1) against C3_CircleR1: when it differs, it is kept
; there and WinFx_BuildCircle (mode 0: TDC with DP = 0, a full circle,
; the rest of the table emptied) draws it at WinFx_ArgX / ArgY
; ($80, $70) into C3_Circle1Table ($7E:F000; WinFx_ArgSize from a
; 16-bit store, which also writes the radius's high byte to
; WinFx_ArgSizeHi; WinFx_BuildCircle zeroes that byte at once, so only
; the low byte counts); then var 0 (C3_Circle2) against C3_CircleR2
; the same way, into C3_Circle2Table ($7E:F280).
; Circle 1 overruns its table: C3Mod_Prog5ScriptB sets its radius to
; $88 around line $70, and WinFx_BuildCircle does not limit its rows,
; so (even table address: the top row is Yc - r - 1) rows -25 to -1
; are written before the table, 50 bytes at $7E:EFCE-$EFFF, and the
; mirror (mode 0, r + 1 rows from $70) writes rows $E0-$F8 past its
; 224 lines, 50 bytes at $7E:F1C0-$F1F1 (below C3_Circle2Table at
; $F280; no lower fill, Yc + r being past line $DF). No program 5 code
; uses either range; what the field keeps at $7E:EFCE is not traced.
; Circle 2 (radius 0 to 96) stays inside its table except at radius 0
; (built on the first frame, as C3_CircleR2 starts at 1, and again
; when the script sets var 0 back to 0): WinFx_BuildCircle's empty
; path stores the first entry and copies $1C1 more bytes, $1C3 in all,
; so it writes $7E:F280-$F442, 3 bytes past the 224 lines.
; Callers note: a task added by script opcode $FA at $715D
;   (C3Mod_Prog5Script).
; Entry: a task: M=0, X=0 (the 16-bit table address), DP=0 (C3_CircleR1
;        / R2 are direct page; TDC gives mode 0), DB=$00 (page $0B00 and
;        the WinFx_* block are absolute).
; Exit:  M=0, X=0; A = 0 after a build, else the radius; X as stored or
;        unchanged; Y unchanged.
; Calls: WinFx_BuildCircle (JSL).
C3Mod_CircleTask:
    LDA.w !C3_ScriptPageB+!C3_Circle1
    CMP.b !C3_CircleR1
    BEQ .second
    STA.b !C3_CircleR1
    STA.w !WinFx_ArgSize                ; and WinFx_ArgSizeHi
    LDX.w #!C3_Circle1Table
    STX.w !WinFx_TablePtr
    TDC                                 ; mode 0 (DP = 0)
    JSL !WinFx_BuildCircle
.second:
    LDA.w !C3_ScriptPageB+!C3_Circle2
    CMP.b !C3_CircleR2
    BEQ .done
    STA.b !C3_CircleR2
    STA.w !WinFx_ArgSize
    LDX.w #!C3_Circle2Table
    STX.w !WinFx_TablePtr
    TDC
    JSL !WinFx_BuildCircle
.done:
    RTS

; $7E:7354 — C3Mod_Prog5Hdma (21 bytes, $7354–$7368)
; Program 5's HDMA channels (C3Mod_SetupHdma's records): 0 indirect, two
; registers, to WH0 / WH1 (window 1: C3Mod_Prog5Window1), 1 the same to
; WH2 / WH3 (window 2: C3Mod_Prog5Window2), 2 indirect, one register
; twice, to BG3HOFS and 3 to BG3VOFS, both from C3Mod_Prog5Bg3Wave; the
; end.
C3Mod_Prog5Hdma:
    db !DMAP_HdmaIndirect|!DMAP_TwoRegs, !BBAD_WH0 : dw C3Mod_Prog5Window1 : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegs, !BBAD_WH2 : dw C3Mod_Prog5Window2 : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_OneRegTwice, !BBAD_BG3HOFS : dw C3Mod_Prog5Bg3Wave : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_OneRegTwice, !BBAD_BG3VOFS : dw C3Mod_Prog5Bg3Wave : db !Bank7E
    db !C3_HdmaListEnd

; $7E:7369 — C3Mod_Prog5Window1 (7 bytes, $7369–$736F)
; Channel 0's indirect table: 112 lines (repeat) from C3_Circle1Table,
; 112 from 224 bytes on (two bytes a line); the end.
C3Mod_Prog5Window1:
    db $F0 : dw !C3_Circle1Table
    db $F0 : dw !C3_Circle1Table+$E0
    db 0

; $7E:7370 — C3Mod_Prog5Window2 (7 bytes, $7370–$7376)
; Channel 1's, from C3_Circle2Table.
C3Mod_Prog5Window2:
    db $F0 : dw !C3_Circle2Table
    db $F0 : dw !C3_Circle2Table+$E0
    db 0

; $7E:7377 — C3Mod_Prog5Bg3Wave (7 bytes, $7377–$737D)
; Channels 2 and 3's: the same 224 words of C3_Bg3Wave ($7E:F500) for
; BG3HOFS and BG3VOFS; the end.
C3Mod_Prog5Bg3Wave:
    db $F0 : dw !C3_Bg3Wave
    db $F0 : dw !C3_Bg3Wave+$E0
    db 0

; $7E:737E — C3Mod_Prog5MosaicTask (44 bytes, $737E–$73A9)
; A task: BG1's mosaic. While C3_MosaicStep is not $FF (8-bit CMP /
; BEQ: equality), MOSAIC = the step x 16 + 1 (four ASLs, ORA #1: BG1
; only). At $FF, every 4 frames (C3_FrameCount AND 3 = 0; BNE skips the
; others) a random size: (C3Mod_KernelRandom AND $30) + $20 + C (no CLC:
; C as C3_RandomByte's last SBC left it), drawn again while it equals
; C3_MosaicLast (CMP / BEQ), kept there, and MOSAIC = it OR 1 (sizes
; 2-5). Quirk: the + C lands in bit 0, which the ORA sets anyway, but
; the CMP sees it, so the "new" size can be the last one again.
; Callers note: a task added by script opcode $FA at $71B1
;   (C3Mod_Prog5ScriptB), removed by $F9 at $727C.
; Entry: a task: M=0 (8-bit set here), X=0 (C3Mod_KernelRandom's), DP=0
;        (the bytes and C3_FrameCount are direct page), DB=$00 (MOSAIC
;        and C3_RandomByte's registers are absolute).
; Exit:  M=1; A = the MOSAIC value, or C3_FrameCount AND 3 (not 0); X,
;        Y unchanged; C3_RandSeed changed after a draw.
; Calls: C3Mod_KernelRandom.
C3Mod_Prog5MosaicTask:
    SEP #$20
    LDA.b !C3_MosaicStep
    CMP.b #!C3_MosaicRandom
    BEQ .random
    ASL A
    ASL A
    ASL A
    ASL A
    ORA.b #!C3_MosaicBg1
    STA.w MOSAIC
    BRA .done
.random:
    LDA.b !C3_FrameCount
    AND.b #!C3_MosaicRandomEvery
    BNE .done
.pick:
    JSR C3Mod_KernelRandom
    AND.b #!C3_MosaicRandomMask
    ADC.b #!C3_MosaicRandomBase         ; C as C3_RandomByte left it
    CMP.b !C3_MosaicLast
    BEQ .pick
    STA.b !C3_MosaicLast
    ORA.b #!C3_MosaicBg1
    STA.w MOSAIC
.done:
    RTS

; $7E:73AA — C3Mod_Bg3WaveTask (28 bytes, $73AA–$73C5)
; A task: BG3's wave (C3_Bg3Wave, 224 words at $7E:F500, both BG3HOFS
; and BG3VOFS per line): the words move down one (MVN in bank $7E,
; $1BF bytes from $F502 to $F500; DB = $7E after), C3_Bg3WavePhase +
; page $0B00's var 8 (C3_WaveStep; no CLC: the carry as the task is
; entered, 0 from C3Mod_TaskNext's CPX unless it is the list's first
; task: its only entry), and the last word = C3Mod_Sine(the phase)
; (-sin) / 4 (two LSRs: for a negative value $3Fxx, the same modulo
; $400, the scroll registers' 10 bits).
; Callers note: a task added by script opcode $FA at $7169
;   (C3Mod_Prog5Script).
; Entry: a task: M=0, X=0 (the MVN's 16-bit X and Y), DP=0
;        (C3_Bg3WavePhase), DB any (set to $7E by the MVN; restored by
;        C3Mod_RunTasks).
; Exit:  M=0, X=0, DB = $7E; A = the new word, X = the phase AND
;        C3_AngleMask (C3Mod_Sine's), Y = $F6BF (past the MVN).
; Calls: C3Mod_Sine.
C3Mod_Bg3WaveTask:
    LDA.w #!C3_Bg3WaveMove
    LDX.w #!C3_Bg3Wave+2
    LDY.w #!C3_Bg3Wave
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes (WRAM bank $7E)
    LDA.w !C3_ScriptPageB+!C3_WaveStep
    ADC.b !C3_Bg3WavePhase              ; C as the task is entered
    STA.b !C3_Bg3WavePhase
    JSR C3Mod_Sine
    LSR A
    LSR A
    STA.w !C3_Bg3WaveLast
    RTS

; $7E:73C6 — C3Mod_RotateMatrixTask (123 bytes, $73C6–$7440)
; A task: the coefficients C3Mod_RotateMap turns the map with, from
; page $0A00's var 5 (the angle, C3_TurnAngle) and var 0 (the scale,
; C3_TurnScale), by the PPU's signed multiplier (M7A 16-bit signed x
; the last byte written to M7B, 8-bit signed; MPYL / MPYM read as a
; word: the product's bits 0-15):
;   - c = C3Mod_Cosine(angle) (-cos), kept with PHP; M7A = |c| (low
;     byte, then high: 0-$FF, positive), M7B = the scale's low byte / 4
;     (two 8-bit LSRs, 0-$3F: positive; written twice, the second
;     counts); C3_TurnCos = C3_TurnCos2 = the product / 8 (three LSRs)
;     with c's sign put back (PLP / BPL: bit 15 of c; EOR / INC);
;   - the same with C3Mod_Sine (-sin): C3_TurnSin, and C3_TurnNegSin =
;     -C3_TurnSin;
;   - C3_TurnXUse = C3_TurnX2 = var 1 (C3_TurnX, the offset read),
;     C3_TurnYUse = C3_TurnY2 = var 2 (C3_TurnY); C3Mod_RotateMap reads
;     the *Use words, and nothing in this program reads C3_TurnX2 /
;     C3_TurnY2.
; Program 3 adds it too (C3Mod_Prog3Start), where nothing reads what
; it writes.
; Callers note: a task added by script opcode $FA at $698A
;   (C3Mod_Prog3Start) and $7166 (C3Mod_Prog5Script).
; Entry: a task: M=0 (8-bit set for the multiplier, then 16-bit), X=0
;        (C3Mod_Sine's TAX), DP=0 (the C3_Turn* words are direct page),
;        DB=$00 (page $0A00 and the registers are absolute).
; Exit:  M=0, X=0; A = var 2, X = the angle AND C3_AngleMask
;        (C3Mod_Sine's); Y unchanged; M7A / M7B as last written.
; Calls: C3Mod_Cosine, C3Mod_Sine.
C3Mod_RotateMatrixTask:
    LDA.w !C3_ScriptPageA+!C3_TurnAngle
    JSR C3Mod_Cosine
    PHP
    BPL .cos_positive
    EOR.w #!Eng_Invert16
    INC A
.cos_positive:
    SEP #$20
    STA.w M7A
    XBA
    STA.w M7A
    LDA.w !C3_ScriptPageA+!C3_TurnScale
    LSR A
    LSR A
    STA.w M7B
    STA.w M7B
    REP #$20
    LDA.w MPYL                          ; and MPYM
    LSR A
    LSR A
    LSR A
    PLP
    BPL .cos_sign
    EOR.w #!Eng_Invert16
    INC A
.cos_sign:
    STA.b !C3_TurnCos
    STA.b !C3_TurnCos2
    LDA.w !C3_ScriptPageA+!C3_TurnAngle
    JSR C3Mod_Sine
    PHP
    BPL .sin_positive
    EOR.w #!Eng_Invert16
    INC A
.sin_positive:
    SEP #$20
    STA.w M7A
    XBA
    STA.w M7A
    LDA.w !C3_ScriptPageA+!C3_TurnScale
    LSR A
    LSR A
    STA.w M7B
    STA.w M7B
    REP #$20
    LDA.w MPYL
    LSR A
    LSR A
    LSR A
    PLP
    BPL .sin_sign
    EOR.w #!Eng_Invert16
    INC A
.sin_sign:
    STA.b !C3_TurnSin
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C3_TurnNegSin
    LDA.w !C3_ScriptPageA+!C3_TurnX
    STA.b !C3_TurnX2
    STA.b !C3_TurnXUse
    LDA.w !C3_ScriptPageA+!C3_TurnY
    STA.b !C3_TurnY2
    STA.b !C3_TurnYUse
    RTS

; $7E:7441 — C3Mod_RotateMap (156 bytes, $7441–$74DC)
; The idle routine C3Mod_Prog5 writes over C3Mod_Start's idle call: it
; turns the field's BG1 map in software. With a = C3_TurnCos, b =
; C3_TurnSin, -b = C3_TurnNegSin, cx = C3_TurnXUse, cy = C3_TurnYUse
; (16-bit, 8.8-ish fixed point: the high bytes are map positions):
;   - its own operands written first (self-modifying): .col_x = 2a,
;     .row_x = 2b, .row_y = a, .col_y = -b;
;   - x0 = -((16cx + a + 1 + b) x 32) (SEC / ADC, SEC / SBC of -b, five
;     ASLs, EOR / INC) to C3_TurnRowX; y0 = -((16cy - b + a + 1) x 16)
;     (CLC / ADC of -b, SEC / ADC) to C3_TurnRowY;
;   - WRMPYA = $40 (a 16-bit store: WRMPYB = 0 too, a product started);
;     for each of .rows' operand rows ($1B = 27; C3Mod_Prog3 writes $1C
;     there, but never runs this routine): y0 + a, x0 + 2b, then 32
;     columns: y + -b, x + 2a; the entry at C3_MapSource + ((y's high
;     byte x $40: WRMPYB from a 16-bit store, which also writes WRDIVL)
;     + x's high byte + C) AND $7FE (even: words) goes to the next word
;     of C3_MapTurned ($1400 on, Y + 2);
;   - C3_MapReady + 1 (16-bit INC): C3Mod_MapNmiTask sends the map.
; Quirk: no CLC before five ADCs (.row_y $749D, .row_x $74A6, .col_y
; $74AF, .col_x $74BA and the ADC of RDMPYL at $74C3); each takes the
; carry out of the add before it (the row's first from the last ASL of
; y0 or, after the first row, the last column's map add), so a
; coordinate or map offset can be one more. The rows after the 27th keep Map_BufC800's copy.
; Callers note: the patched JSR at $3023 (C3Mod_Start's idle call,
;   written by C3Mod_Prog5 at $70D7).
; Entry: M=0, X=0 (16-bit indexes), DP=0 (the C3_Turn* words), DB=$00
;        (the map and the multiplier are absolute; the operand patches
;        are long STA.l), as
;        C3Mod_Start's loop runs (C3_ModuleFrame's DP and DB, REP #$20).
; Exit:  M=0, X=0; A = the last entry, X its offset, Y = C3_MapTurned +
;        the rows x $40; C3_TurnRow*, C3_TurnCol* and C3_TurnLeft/Rows
;        changed.
C3Mod_RotateMap:
.rows:
    LDA.w #!C3_TurnRowsDefault          ; C3Mod_Prog3 writes $1C here
    STA.b !C3_TurnRowsLeft
    LDA.b !C3_TurnCos
    ASL A
    STA.l .col_x+1
    LDA.b !C3_TurnSin
    ASL A
    STA.l .row_x+1
    LDA.b !C3_TurnCos2
    STA.l .row_y+1
    LDA.b !C3_TurnNegSin
    STA.l .col_y+1
    LDA.b !C3_TurnXUse
    ASL A
    ASL A
    ASL A
    ASL A
    SEC
    ADC.b !C3_TurnCos
    SEC
    SBC.b !C3_TurnNegSin
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C3_TurnRowX
    LDA.b !C3_TurnYUse
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC.b !C3_TurnNegSin
    SEC
    ADC.b !C3_TurnCos
    ASL A
    ASL A
    ASL A
    ASL A
    EOR.w #!Eng_Invert16
    INC A
    STA.b !C3_TurnRowY
    LDA.w #!C3_MapRowBytes
    STA.w WRMPYA                        ; and WRMPYB = 0
    LDY.w #!C3_MapTurned
.row:
    LDA.w #!C3_MapRowWords
    STA.b !C3_TurnColsLeft
    LDA.b !C3_TurnRowY
.row_y:
    ADC.w #0                            ; a, written above
    STA.b !C3_TurnRowY
    STA.b !C3_TurnColY
    LDA.b !C3_TurnRowX
.row_x:
    ADC.w #0                            ; 2b
    STA.b !C3_TurnRowX
    STA.b !C3_TurnColX
.column:
    LDA.b !C3_TurnColY
.col_y:
    ADC.w #0                            ; -b
    STA.b !C3_TurnColY
    XBA
    STA.w WRMPYB                        ; the row; WRDIVL = y's low byte
    LDA.b !C3_TurnColX
.col_x:
    ADC.w #0                            ; 2a
    STA.b !C3_TurnColX
    XBA
    AND.w #!Eng_LowByteMask
    ADC.w RDMPYL                        ; the row x $40
    AND.w #!C3_MapEntryMask
    TAX
    LDA.w !C3_MapSource,X
    STA.w !Eng_PtrBase,Y
    INY
    INY
    DEC.b !C3_TurnColsLeft
    BNE .column
    DEC.b !C3_TurnRowsLeft
    BNE .row
    INC.b !C3_MapReady
    RTS

; $7E:74DD — C3Mod_Times40 (14 bytes, $74DD–$74EA)
; A = (A AND $FF) x 40 (x 8 to C3_TmpF0, x 32 + it, CLC): a battle
; sprite frame's offset.
; Callers note: C3Mod_CharsTask ($7746) and C3Mod_DrawChar ($779E).
; Entry: M=0, X any, DP=0 (C3_TmpF0), DB any; A's low byte = the frame.
; Exit:  M=0; A = the frame x 40, C3_TmpF0 = x 8; X, Y unchanged.
C3Mod_Times40:
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A
    STA.b !C3_TmpF0
    ASL A
    ASL A
    CLC
    ADC.b !C3_TmpF0
    RTS

; $7E:74EB — C3Mod_Times3 (10 bytes, $74EB–$74F4)
; A = (A AND $FF) x 3 (CLC): a sprite set's offset in the 3-byte
; pointer tables.
; Callers note: C3Mod_CharsTask ($7740) and C3Mod_DrawChar ($77A4).
; Entry: M=0, X any, DP=0 (C3_TmpF0), DB any; A's low byte = the set.
; Exit:  M=0; A = the set x 3, C3_TmpF0 = the set; X, Y unchanged.
C3Mod_Times3:
    AND.w #!Eng_LowByteMask
    STA.b !C3_TmpF0
    ASL A
    CLC
    ADC.b !C3_TmpF0
    RTS

; $7E:74F5 — C3Mod_InitChars (313 bytes, $74F5–$762D)
; The four sprite records, with DP = 0 (PEA / PLD): records 0-2 the
; party's three members from the field's hand-off block (FieldBtlPc
; k), record 3 the field's first other object (FieldBtlObj 0). Each:
;   - C3_CharFrame = C3_CharShown = the record's .Frame (8-bit);
;   - C3_CharSet = the member's Party_Members word (16-bit: its high
;     byte, the next member's id, lands in the unused byte after it);
;     record 3 takes set 6. C3Mod_CharAnimSet picks the animation from
;     it;
;   - C3_CharVram = the tiles' VRAM word $0080, $0200, $0280 or $1880
;     and C3_CharTiles = the OAM tile and attribute word $3A08, $3C20,
;     $3E28 or $3388 (tiles $008, $020, $028 and $188: the same VRAM
;     words, x 16; palettes 5, 6, 7 and 1, priority 3);
;     C3_CharAnimPtr = $3000 (C3_CharAnimInit; overwritten by the
;     first C3Mod_CharAnimStep's restart before any read);
;   - C3_CharX = .TileX x 16 OR .SubX, C3_CharY = .TileY x 16 OR .SubY
;     (8-bit: four ASLs, ORA; a tile from 16 up loses its high bits);
;   - C3Mod_CharPolar: its angle and distance from the centre.
; The records are C3_CharRecBytes apart (TXA / CLC / ADC / TAX).
; Callers note: C3Mod_Prog5 ($70E8).
; Entry: M=1, X=0 (16-bit index), DP any (set to 0 here), DB=$00 (as
;        C3Mod_Prog5 runs: C3Mod_Atan's divider is absolute).
; Exit:  M=1, X=0, DP=0, DB=$00; X = C3_Char3; A = record 3's root, Y
;        its dy x dy word (as C3Mod_CharPolar leaves them).
; Calls: C3Mod_CharAnimSet, C3Mod_CharPolar.
C3Mod_InitChars:
    PEA.w 0
    PLD
    REP #$20
    LDX.w #!C3_Char0
    SEP #$20
    LDA.l FieldBtlPc[0].Frame
    STA.b !C3_CharFrame,X
    STA.b !C3_CharShown,X
    REP #$20
    LDA.l !Party_Members
    STA.b !C3_CharSet,X
    JSR C3Mod_CharAnimSet
    LDA.w #!C3_Char0Vram
    STA.b !C3_CharVram,X
    LDA.w #!C3_CharAnimInit
    STA.b !C3_CharAnimPtr,X
    LDA.w #!C3_Char0Tiles
    STA.b !C3_CharTiles,X
    SEP #$20
    LDA.l FieldBtlPc[0].TileX
    ASL A
    ASL A
    ASL A
    ASL A
    ORA.l FieldBtlPc[0].SubX
    STA.b !C3_CharX,X
    LDA.l FieldBtlPc[0].TileY
    ASL A
    ASL A
    ASL A
    ASL A
    ORA.l FieldBtlPc[0].SubY
    STA.b !C3_CharY,X
    REP #$20
    JSR C3Mod_CharPolar
    TXA
    CLC
    ADC.w #!C3_CharRecBytes
    TAX
    SEP #$20
    LDA.l FieldBtlPc[1].Frame
    STA.b !C3_CharFrame,X
    STA.b !C3_CharShown,X
    REP #$20
    LDA.l !Party_Members+1
    STA.b !C3_CharSet,X
    JSR C3Mod_CharAnimSet
    LDA.w #!C3_Char1Vram
    STA.b !C3_CharVram,X
    LDA.w #!C3_CharAnimInit
    STA.b !C3_CharAnimPtr,X
    LDA.w #!C3_Char1Tiles
    STA.b !C3_CharTiles,X
    SEP #$20
    LDA.l FieldBtlPc[1].TileX
    ASL A
    ASL A
    ASL A
    ASL A
    ORA.l FieldBtlPc[1].SubX
    STA.b !C3_CharX,X
    LDA.l FieldBtlPc[1].TileY
    ASL A
    ASL A
    ASL A
    ASL A
    ORA.l FieldBtlPc[1].SubY
    STA.b !C3_CharY,X
    REP #$20
    JSR C3Mod_CharPolar
    TXA
    CLC
    ADC.w #!C3_CharRecBytes
    TAX
    SEP #$20
    LDA.l FieldBtlPc[2].Frame
    STA.b !C3_CharFrame,X
    STA.b !C3_CharShown,X
    REP #$20
    LDA.l !Party_Members+2
    STA.b !C3_CharSet,X
    JSR C3Mod_CharAnimSet
    LDA.w #!C3_Char2Vram
    STA.b !C3_CharVram,X
    LDA.w #!C3_CharAnimInit
    STA.b !C3_CharAnimPtr,X
    LDA.w #!C3_Char2Tiles
    STA.b !C3_CharTiles,X
    SEP #$20
    LDA.l FieldBtlPc[2].TileX
    ASL A
    ASL A
    ASL A
    ASL A
    ORA.l FieldBtlPc[2].SubX
    STA.b !C3_CharX,X
    LDA.l FieldBtlPc[2].TileY
    ASL A
    ASL A
    ASL A
    ASL A
    ORA.l FieldBtlPc[2].SubY
    STA.b !C3_CharY,X
    REP #$20
    JSR C3Mod_CharPolar
    TXA
    CLC
    ADC.w #!C3_CharRecBytes
    TAX
    SEP #$20
    LDA.l FieldBtlObj[0].Frame
    STA.b !C3_CharFrame,X
    STA.b !C3_CharShown,X
    REP #$20
    LDA.w #!C3_CharObjSet
    STA.b !C3_CharSet,X
    JSR C3Mod_CharAnimSet
    LDA.w #!C3_Char3Vram
    STA.b !C3_CharVram,X
    LDA.w #!C3_CharAnimInit
    STA.b !C3_CharAnimPtr,X
    LDA.w #!C3_Char3Tiles
    STA.b !C3_CharTiles,X
    SEP #$20
    LDA.l FieldBtlObj[0].TileX
    ASL A
    ASL A
    ASL A
    ASL A
    ORA.l FieldBtlObj[0].SubX
    STA.b !C3_CharX,X
    LDA.l FieldBtlObj[0].TileY
    ASL A
    ASL A
    ASL A
    ASL A
    ORA.l FieldBtlObj[0].SubY
    STA.b !C3_CharY,X
    REP #$20
    JSR C3Mod_CharPolar
    SEP #$20
    RTS

; $7E:762E — C3Mod_CharAnimSet (20 bytes, $762E–$7641)
; C3_CharAnim = C3Mod_CharAnimSets[A AND 7] and C3_CharAnimNow = it +
; 1 (8-bit INC), so that the record's first C3Mod_CharAnimStep
; restarts its animation. An empty party slot (Party_Members $80)
; reads entry 0; A AND 7 = 7 (no character has it) would read the
; code byte after the table.
; Callers note: C3Mod_InitChars ($7510, $755D, $75AA, $75F6).
; Entry: M=0, X=0 (the record's 16-bit offset), DP=0 (the records),
;        DB any (the table read is long); A = the sprite set (its low
;        3 bits count).
; Exit:  M=0, X as on entry; A = the animation + 1 (B = 0 from the
;        AND); Y unchanged.
C3Mod_CharAnimSet:
    PHX
    AND.w #!C3_CharSetMask
    SEP #$20
    TAX
    LDA.l C3Mod_CharAnimSets,X
    PLX
    STA.b !C3_CharAnim,X
    INC A
    STA.b !C3_CharAnimNow,X
    REP #$20
    RTS

; $7E:7642 — C3Mod_CharAnimSets (7 bytes, $7642–$7648)
; The animation C3Mod_CharAnimSet gives each sprite set 0-6 (the
; characters' ids; set 6, record 3's, too).
C3Mod_CharAnimSets:
    db $41, $35, $22, $34, $03, $00, $3C

; $7E:7649 — C3Mod_CharPolar (92 bytes, $7649–$76A4)
; A record's position as an angle and a distance from the screen's
; centre ($80, $70):
;   - dy = (C3_CharY AND $FF) - $70 to C3_TmpF4 and Y, dx = (C3_CharX
;     AND $FF) - $80 to C3_TmpF6 and X (16-bit, SEC); C3Mod_Atan's
;     angle to C3_CharAngle (a word);
;   - the distance: for dy, then dx, d = the low byte, negated when
;     its bit 7 is set (8-bit BPL; so dy from $80 up, C3_CharY $F0 on,
;     gives $100 - dy, and dx = -$80, C3_CharX 0, gives $80); the PPU
;     multiplier: M7A = d (low byte, then STZ: a 16-bit positive
;     value), M7B = d (8-bit signed, written twice: the second byte
;     counts), so the product is d x d, or -$4000 when d = $80; the
;     first product's MPYL/MPYM word to Y (LDY, 16-bit), the second
;     added (REP #$21: C = 0; ADC MPYL/MPYM) and C3Mod_SquareRoot
;     entered with that ADC's carry (set only when a -$4000 term takes
;     the sum to $10000 or more): C3_CharRadius = the root's low byte
;     (from C3_SqrtRoot).
; The writes to M7A / M7B set mode 7's matrix A and B as well (no
; effect in program 5's mode 1).
; Callers note: C3Mod_InitChars ($7542, $758F, $75DC, $7628).
; Entry: M=0, X=0 (the record's 16-bit offset), DP=0 (the records and
;        the C3_Tmp* words), DB=$00 (the PPU multiplier and
;        C3Mod_Atan's divider are absolute).
; Exit:  M=0, X as on entry; A = the root (16-bit), Y = the dy x dy
;        word; C3_TmpF2 = C3Mod_Atan's sign flag, C3_SqrtRoot (C3_TmpF0)
;        = the root; C clear (C3Mod_SquareRoot's).
; Calls: C3Mod_Atan, C3Mod_SquareRoot.
C3Mod_CharPolar:
    PHX
    LDA.b !C3_CharY,X
    AND.w #!Eng_LowByteMask
    SEC
    SBC.w #!C3_Prog5CentreY
    STA.b !C3_TmpF4
    TAY
    LDA.b !C3_CharX,X
    AND.w #!Eng_LowByteMask
    SEC
    SBC.w #!C3_Prog5CentreX
    STA.b !C3_TmpF6
    TAX
    JSR C3Mod_Atan
    PLX
    STA.b !C3_CharAngle,X
    SEP #$20
    LDA.b !C3_TmpF4
    BPL .dy
    EOR.b #!Eng_Invert8
    INC A
.dy:
    STA.w M7A
    STZ.w M7A
    STA.w M7B
    STA.w M7B
    LDY.w MPYL                          ; and MPYM
    LDA.b !C3_TmpF6
    BPL .dx
    EOR.b #!Eng_Invert8
    INC A
.dx:
    STA.w M7A
    STZ.w M7A
    STA.w M7B
    STA.w M7B
    REP #$21
    TYA
    ADC.w MPYL                          ; and MPYM
    JSR C3Mod_SquareRoot
    LDA.b !C3_SqrtRoot
    SEP #$20
    STA.b !C3_CharRadius,X
    REP #$20
    RTS

; $7E:76A5 — C3Mod_CharSpinTask (23 bytes, $76A5–$76BB)
; A task: the spin. C3_SpinAngle + page $0B00's var 2 (C3_SpinSpeed;
; CLC), then C3Mod_CharSpin for records 0, 1 and 2 (the third falls
; in): only the party spins; record 3 keeps its place.
; Callers note: a task added by script opcode $FA at $7160
;   (C3Mod_Prog5Script).
; Entry: a task: M=0, X=0 (16-bit offsets), DP=0 (C3_SpinAngle and the
;        records), DB=$00 (page $0B00 and the PPU multiplier are
;        absolute).
; Exit:  as C3Mod_CharSpin's, with X = C3_Char2.
; Calls: C3Mod_CharSpin.
C3Mod_CharSpinTask:
    LDA.b !C3_SpinAngle
    CLC
    ADC.w !C3_ScriptPageB+!C3_SpinSpeed
    STA.b !C3_SpinAngle
    LDX.w #!C3_Char0
    JSR C3Mod_CharSpin
    LDX.w #!C3_Char1
    JSR C3Mod_CharSpin
    LDX.w #!C3_Char2                    ; and it falls into C3Mod_CharSpin

; $7E:76BC — C3Mod_CharSpin (97 bytes, $76BC–$771C)
; One record placed on its circle: a = C3_SpinAngle + C3_CharAngle
; (16-bit, CLC; 1,024 steps per turn in C3Mod_Sine);
;   - C3_CharFacing = C3Mod_CharFacings[((a + $80) >> 8) AND 3] AND 3
;     (CLC; XBA / AND: the quarter turn a is nearest to);
;   - x: M7A = C3Mod_Cosine(a) (-cos: a signed 16-bit value, -$FF to
;     $FF; low byte, then high), M7B = C3_CharRadius (8-bit signed,
;     written twice: a radius from $80 up counts as negative, the
;     sprite on the other side); C3_CharX = MPYM (bits 8-15 of the
;     signed product: floor(-cos x r / 256)'s low byte) + $80 + C,
;     where C is C3Mod_Cosine's carry (from its CPX #$200: set when
;     (a + $100) AND $3FF is $200 or more, the value 0 or positive);
;   - y: the same with C3Mod_Sine(a) (-sin; a again, REP #$21: C = 0)
;     and $70: C3_CharY = MPYM + $70 + C3Mod_Sine's carry (a AND $3FF
;     from $200 up).
; The writes to M7A / M7B set mode 7's matrix A and B as well (no
; effect in mode 1).
; Callers note: C3Mod_CharSpinTask ($76B0, $76B6; the third falls in).
; Entry: M=0, X=0 (the record's 16-bit offset; C3Mod_Sine's 16-bit
;        index), DP=0 (C3_SpinAngle and the records), DB=$00 (the PPU
;        multiplier is absolute).
; Exit:  M=0, X as on entry; A = C3Mod_Sine's low byte x 256 + the new
;        C3_CharY; Y unchanged.
; Calls: C3Mod_Cosine, C3Mod_Sine.
C3Mod_CharSpin:
    LDA.b !C3_SpinAngle
    CLC
    ADC.b !C3_CharAngle,X
    PHA
    PHX
    CLC
    ADC.w #!C3_FacingRound
    XBA
    AND.w #!C3_CharFacingMask
    TAX
    SEP #$20
    LDA.l C3Mod_CharFacings,X
    AND.b #!C3_CharFacingMask
    PLX
    STA.b !C3_CharFacing,X
    REP #$20
    PLA
    PHX
    JSR C3Mod_Cosine
    PLX
    SEP #$20
    STA.w M7A
    XBA
    STA.w M7A
    LDA.b !C3_CharRadius,X
    STA.w M7B
    STA.w M7B
    LDA.w MPYM
    ADC.b #!C3_Prog5CentreX             ; + C3Mod_Cosine's carry
    STA.b !C3_CharX,X
    REP #$21
    LDA.b !C3_SpinAngle
    ADC.b !C3_CharAngle,X
    PHX
    JSR C3Mod_Sine
    PLX
    SEP #$20
    STA.w M7A
    XBA
    STA.w M7A
    LDA.b !C3_CharRadius,X
    STA.w M7B
    STA.w M7B
    LDA.w MPYM
    ADC.b #!C3_Prog5CentreY             ; + C3Mod_Sine's carry
    STA.b !C3_CharY,X
    REP #$20
    RTS

; $7E:771D — C3Mod_CharFacings (4 bytes, $771D–$7720)
; The facing (the battle sprites' direction, 0-3) for each quarter
; turn of C3Mod_CharSpin's angle.
C3Mod_CharFacings:
    db 3, 1, 2, 0

; $7E:7721 — C3Mod_CharsTask (83 bytes, $7721–$7773)
; A task: the four sprites.
;   - C3_CharTilesVram = $FFFF (C3_CharNoTiles: no upload); from the
;     record C3_CharNext names, at most 4 tries (C3_CharTries, 16-bit
;     DEC / BNE): the first record whose C3_CharFrame differs from
;     C3_CharShown (8-bit CMP / BEQ: equal tries the next) gets its
;     frame's tiles: C3_CharShown = it, C3_CharTilesVram =
;     C3_CharVram, C3Mod_LoadCharTiles with X = C3_CharSet x 3, A =
;     the frame x 40 and Y = $1C00 (C3_CharTileBuf; sent by
;     C3Mod_CharTilesNmiTask); C3Mod_NextChar after each record tried,
;     so the search goes on from the next one in the next frame;
;   - then, for records 0-3 (16-bit CPX #$58 / BNE), C3Mod_DrawChar
;     and C3Mod_CharAnimStep: a frame the animation picks now is
;     loaded and drawn from the next frame on.
; Callers note: a task added by script opcode $FA at $7163
;   (C3Mod_Prog5Script).
; Entry: a task: M=0, X=0 (16-bit offsets), DP=0 (the records and
;        C3_Char* words), DB=$00 (the OAM shadow and WMADD are
;        absolute).
; Exit:  M=0, X=0, DB=$00 (C3Mod_CharAnimStep's PLB); X = C3_CharEnd;
;        A = X; Y = record 3's facing when its animation restarted,
;        else 8 (C3Mod_DrawChar's).
; Calls: C3Mod_Times3, C3Mod_Times40, C3Mod_LoadCharTiles,
;   C3Mod_NextChar, C3Mod_DrawChar, C3Mod_CharAnimStep.
C3Mod_CharsTask:
    LDA.w #!C3_CharNoTiles
    STA.b !C3_CharTilesVram
    LDA.w #!C3_CharTriesAll
    STA.b !C3_CharTries
    LDX.b !C3_CharNext
.try:
    SEP #$20
    LDA.b !C3_CharFrame,X
    CMP.b !C3_CharShown,X
    BEQ .same
    STA.b !C3_CharShown,X
    REP #$20
    PHX
    LDA.b !C3_CharVram,X
    STA.b !C3_CharTilesVram
    LDA.b !C3_CharSet,X
    JSR C3Mod_Times3
    TAY
    LDA.b !C3_CharFrame,X
    JSR C3Mod_Times40
    TYX
    LDY.w #!C3_CharTileBuf
    JSR C3Mod_LoadCharTiles
    PLX
    JSR C3Mod_NextChar
    BRA .draw
.same:
    REP #$20
    JSR C3Mod_NextChar
    DEC.b !C3_CharTries
    BNE .try
.draw:
    LDX.w #!C3_Char0
.record:
    JSR C3Mod_DrawChar
    JSR C3Mod_CharAnimStep
    TXA
    CLC
    ADC.w #!C3_CharRecBytes
    TAX
    CPX.w #!C3_CharEnd
    BNE .record
    RTS

; $7E:7774 — C3Mod_NextChar (19 bytes, $7774–$7786)
; X = the next record (X + C3_CharRecBytes, CLC; 0 after record 3: a
; 16-bit CMP #$58 / BNE), kept in C3_CharNext.
; Callers note: C3Mod_CharsTask ($7751, $7758).
; Entry: M=0, X=0 (16-bit offsets), DP=0 (C3_CharNext), DB any; X = a
;        record's offset.
; Exit:  M=0, X = C3_CharNext = the next record's offset; A, Y
;        unchanged (PHA / PLA).
C3Mod_NextChar:
    PHA
    TXA
    CLC
    ADC.w #!C3_CharRecBytes
    TAX
    CMP.w #!C3_CharEnd
    BNE .keep
    LDX.w #!C3_Char0
.keep:
    STX.b !C3_CharNext
    PLA
    RTS

; $7E:7787 — C3Mod_DrawChar (39 bytes, $7787–$77AD)
; One record's four sprites: C3_CharTiles written over
; C3Mod_CharSprites' .tiles operand (self-modifying, a long 16-bit
; store), C3_SprBaseX / Y = C3_CharX / C3_CharY (AND $FF), then
; C3Mod_CharSprites with A = C3_CharShown x 40 and X = C3_CharSet x 3
; (the frame whose tiles are in VRAM, or on their way there in this
; frame's vertical blank).
; Callers note: C3Mod_CharsTask ($7762).
; Entry: M=0, X=0 (the record's 16-bit offset), DP=0 (the records,
;        C3_SprBase*), DB=$00 (C3Mod_CharSprites' OAM shadow).
; Exit:  M=0, X as on entry; A, Y as C3Mod_CharSprites leaves them (Y
;        = 8).
; Calls: C3Mod_Times40, C3Mod_Times3, C3Mod_CharSprites.
C3Mod_DrawChar:
    PHX
    LDA.b !C3_CharTiles,X
    STA.l C3Mod_CharSprites_tiles+1
    LDA.b !C3_CharX,X
    AND.w #!Eng_LowByteMask
    STA.b !C3_SprBaseX
    LDA.b !C3_CharY,X
    AND.w #!Eng_LowByteMask
    STA.b !C3_SprBaseY
    LDA.b !C3_CharShown,X
    JSR C3Mod_Times40
    PHA
    LDA.b !C3_CharSet,X
    JSR C3Mod_Times3
    TAX
    PLA
    JSR C3Mod_CharSprites
    PLX
    RTS

; $7E:77AE — C3Mod_CharAnimStep (57 bytes, $77AE–$77E6)
; One record's animation, 8-bit, with DB = $E4 (PEA $00E4 / PLB; the
; PLB at the end takes the $00 back):
;   - C3_CharAnim not C3_CharAnimNow (CMP / BNE): restart;
;   - else C3_CharFacing not C3_CharFacingNow (BNE): the next entry at
;     once, without the wait (the facing is taken only at a restart, so
;     the old facing's list runs to its $FF a frame an entry: a quirk);
;   - else C3_CharAnimTime - 1; not 0 (BNE): nothing more;
;   - the next entry: the byte at C3_CharAnimPtr (bank $E4); $FF
;     (8-bit CMP / BNE) restarts;
;   - restart: C3_CharFacingNow = C3_CharFacing, C3_CharAnimNow =
;     C3_CharAnim, C3Mod_CharAnimStart (the list pointers), and its
;     first byte read (not checked for $FF);
;   - then C3_CharFrame = the byte, C3_CharAnimTime = the byte at
;     C3_CharAnimDurPtr (a time of 0 waits 256 frames), and both
;     pointers + 1 (16-bit INC).
; Callers note: C3Mod_CharsTask ($7765).
; Entry: M=0, X=0 (the record's 16-bit offset), DP=0 (the records; the
;        (dp,X) pointers are direct page), DB any (set here).
; Exit:  M=0, X as on entry, DB=$00 (the PEA's high byte); A = the new
;        C3_CharAnimTime in A's low byte, or C3_CharFacing's when the
;        wait goes on; Y = the facing after a restart, else unchanged.
; Calls: C3Mod_CharAnimStart.
C3Mod_CharAnimStep:
    SEP #$20
    PEA.w !BankE4
    PLB
    LDA.b !C3_CharAnim,X
    CMP.b !C3_CharAnimNow,X
    BNE .restart
    LDA.b !C3_CharFacing,X
    CMP.b !C3_CharFacingNow,X
    BNE .next
    DEC.b !C3_CharAnimTime,X
    BNE .done
.next:
    LDA.b (!C3_CharAnimPtr,X)
    CMP.b #!C3_AnimListEnd
    BNE .frame
.restart:
    LDA.b !C3_CharFacing,X
    STA.b !C3_CharFacingNow,X
    LDA.b !C3_CharAnim,X
    STA.b !C3_CharAnimNow,X
    JSR C3Mod_CharAnimStart
    LDA.b (!C3_CharAnimPtr,X)
.frame:
    STA.b !C3_CharFrame,X
    LDA.b (!C3_CharAnimDurPtr,X)
    STA.b !C3_CharAnimTime,X
    REP #$20
    INC.b !C3_CharAnimPtr,X
    INC.b !C3_CharAnimDurPtr,X
.done:
    PLB
    REP #$20
    RTS

; $7E:77E7 — C3Mod_CharAnimStart (85 bytes, $77E7–$783B)
; A record's animation lists in bank $E4 (DB = $E4, absolute reads),
; with s = C3_CharSet's low byte x 2 and n = C3_CharAnim x 4 (16-bit):
;   - f = C3_SprAnimFrames[s] (BattleRom_SprAnimFrames, $E4:2600) to
;     C3_TmpF6, n to C3_TmpF2;
;   - C3_CharAnimDurPtr = C3_TmpF4 = n + C3_SprAnimDurs[s] ($E4:2800;
;     CLC): the times;
;   - q = (the next set's entry ($2602 + s) - f) / 2 to C3_TmpFA (SEC;
;     LSR), q / 2 to C3_TmpF8: the set's frame lists are four facings'
;     equal parts, q / 2 bytes each;
;   - C3_CharAnimPtr = f + the facing's part + n (each add CLC): facing
;     0 adds 0, 1 adds q / 2, 2 adds q, 3 adds q + q / 2 (16-bit CPY #0,
;     #1, #2 / BEQ; else both).
; Callers note: C3Mod_CharAnimStep ($77D2).
; Entry: M=1 (REP #$20 here), X=0 (the record's 16-bit offset; Y as
;        16-bit index), DP=0 (the records and C3_Tmp* words), DB=$E4.
; Exit:  M=1, X as on entry, DB=$E4; A's low byte = C3_CharAnimPtr's;
;        Y = the facing; C3_TmpF2-FA as above.
C3Mod_CharAnimStart:
    REP #$20
    LDA.b !C3_CharSet,X
    AND.w #!Eng_LowByteMask
    ASL A
    TAY
    LDA.w !C3_SprAnimFrames,Y
    STA.b !C3_TmpF6
    LDA.b !C3_CharAnim,X
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    STA.b !C3_TmpF2
    CLC
    ADC.w !C3_SprAnimDurs,Y
    STA.b !C3_CharAnimDurPtr,X
    STA.b !C3_TmpF4
    LDA.w !C3_SprAnimFrames+2,Y
    SEC
    SBC.b !C3_TmpF6
    LSR A
    STA.b !C3_TmpFA
    LSR A
    STA.b !C3_TmpF8
    LDA.b !C3_CharFacing,X
    AND.w #!Eng_LowByteMask
    TAY
    LDA.b !C3_TmpF6
    CPY.w #0
    BEQ .anim
    CPY.w #1
    BEQ .quarter
    CPY.w #2
    BEQ .half
    CLC
    ADC.b !C3_TmpFA
.quarter:
    CLC
    ADC.b !C3_TmpF8
    BRA .anim
.half:
    CLC
    ADC.b !C3_TmpFA
.anim:
    CLC
    ADC.b !C3_TmpF2
    STA.b !C3_CharAnimPtr,X
    SEP #$20
    RTS

; $7E:783C — C3Mod_MapNmiTask (44 bytes, $783C–$7867)
; An NMI task, and a routine C3Mod_Prog3 calls once: when C3_MapReady
; is set (8-bit LDA / BEQ), the map C3Mod_RotateMap built,
; $00:1400-$1BFF (C3_MapTurned, C3_MapBytes; A1B7 = 0), to VRAM from
; .vram's operand ($6000, program 5's BG1 map; C3Mod_Prog3 writes 0
; over it first) by DMA channel 7 (two registers from VMDATAL, VMAIN =
; $80), then C3_MapReady = 0.
; Callers note: C3Mod_Prog3 ($67A1); an NMI task added by script
;   opcode $F8 at $717B (C3Mod_Prog5Script).
; Entry: M=1, X=0 (the 16-bit register stores), DP=0 (C3_MapReady),
;        DB=$00 (the registers are absolute): an NMI task
;        (C3Mod_RunNmiTasks), or C3Mod_Prog3 at DP = 0 after its TCD,
;        M=1.
; Exit:  M=1, X=0; sent: A = MDMAEN_Ch7, X = C3_MapBytes, Y = $1801
;        (DMAP7 / BBAD7's word); else A = 0, X and Y unchanged.
C3Mod_MapNmiTask:
    LDA.b !C3_MapReady
    BEQ .done
.vram:
    LDX.w #!C3_Prog5Bg1Map              ; C3Mod_Prog3 writes 0 here
    STX.w VMADDL                        ; and VMADDH
    LDY.w #!BBAD_VMDATAL<<8|!DMAP_TwoRegs
    LDX.w #!C3_MapTurned
    STY.w DMAP7                         ; and BBAD7
    STX.w A1T7L
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    STZ.w A1B7
    LDX.w #!C3_MapBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    STZ.b !C3_MapReady
.done:
    RTS

; $7E:7868 — C3Mod_CharTilesNmiTask (64 bytes, $7868–$78A7)
; An NMI task: when C3_CharTilesVram is not $FFFF (16-bit CPX / BEQ),
; the 16 tiles at $00:1C00 (C3_CharTileBuf; A1B7 = 0) in two parts of
; $100 bytes by DMA channel 7 (two registers from VMDATAL, VMAIN =
; $80): the first 8 to VRAM word C3_CharTilesVram, the next 8 (A1T7
; has moved on to $1D00) to C3_CharTilesVram + $100 (CLC; 16-bit
; store), the row of tiles below in the sprite table.
; Callers note: an NMI task added by script opcode $F8 at $7187
;   (C3Mod_Prog5Script).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X=0 (the 16-bit
;        address), DP=0 (C3_CharTilesVram), DB=$00 (the registers).
; Exit:  M=1, X=0; sent: A = MDMAEN_Ch7, X = $0100, Y = $1801; else X =
;        $FFFF, A and Y unchanged.
C3Mod_CharTilesNmiTask:
    LDX.b !C3_CharTilesVram
    CPX.w #!C3_CharNoTiles
    BEQ .done
    STX.w VMADDL                        ; and VMADDH
    LDY.w #!BBAD_VMDATAL<<8|!DMAP_TwoRegs
    STY.w DMAP7                         ; and BBAD7
    LDX.w #!C3_CharTileBuf
    STX.w A1T7L
    STZ.w A1B7
    LDX.w #!C3_CharTileHalf
    STX.w DAS7L
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    STA.w MDMAEN                        ; MDMAEN_Ch7, the same value
    REP #$20
    LDA.b !C3_CharTilesVram
    CLC
    ADC.w #!C3_CharTileRow
    STA.w VMADDL                        ; and VMADDH
    SEP #$20
    LDX.w #!C3_CharTileHalf
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
.done:
    RTS

; $7E:78A8 — C3Mod_CharTilesDeadEnd (3 bytes, $78A8–$78AA)
; JMP C3Mod_NmiTaskEnd right after C3Mod_CharTilesNmiTask's RTS: no
; code, table or script names $78A8 and no trace reaches it (probably
; dead, a leftover ending of that task).
; Callers note: none found (no JMP, JSR or script word names $78A8).
; Entry: never reached; it would need C3Mod_NmiTaskEnd's: an NMI task
;        with C3Mod_RunNmiTasks' return address on the stack, X=0, M
;        any, DP and DB any (C3Mod_RunNmiTasks restores them).
; Exit:  into C3Mod_NmiTaskEnd.
C3Mod_CharTilesDeadEnd:
    JMP C3Mod_NmiTaskEnd

; $7E:78AB — C3Mod_Prog5PalNmiTask (50 bytes, $78AB–$78DC)
; An NMI task: every 8 frames (C3_FrameCount AND 7 = 0: BNE skips),
; colours $15-$17 cycled: CGADD = $15 and the 6 bytes at $7E:222A
; (C3_PaletteBuf's colours $15-$17, C3_Prog5Cycle) to CGDATA (X to 6:
; CPX / BNE); then DB = $7E (PHK / PLB: the module's bank; restored by
; C3Mod_RunNmiTasks) and the three words turned: $222A = $222C, $222C
; = $222E, $222E = the old $222A. C3Mod_UploadPalette (an NMI task
; ahead of this one) has sent the same colours already this frame; the
; turned ones go with it in the next.
; Callers note: an NMI task added by script opcode $F8 at $718A
;   (C3Mod_Prog5Script).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X=0 (the 16-bit words),
;        DP=0 (C3_FrameCount), DB=$00 (the registers).
; Exit:  cycled: M=0, X=0, DB=$7E; A = the old $222E, X = the old $222A.
;        Skipped: M=1, A = the count AND 7, X unchanged. Y unchanged.
C3Mod_Prog5PalNmiTask:
    LDA.b !C3_FrameCount
    AND.b #!C3_Prog5CycleEvery
    BNE .done
    LDA.b #!C3_Prog5CycleColour
    STA.w CGADD
    LDX.w #0
.colour:
    LDA.l !C3_PaletteBuf+!C3_Prog5CycleOfs,X
    STA.w CGDATA
    INX
    CPX.w #!C3_Prog5CycleBytes
    BNE .colour
    REP #$20
    PHK
    PLB
    LDX.w !C3_Prog5Cycle
    LDA.w !C3_Prog5Cycle+2
    STA.w !C3_Prog5Cycle
    LDA.w !C3_Prog5Cycle+4
    STA.w !C3_Prog5Cycle+2
    STX.w !C3_Prog5Cycle+4
.done:
    RTS

%C3ModOrg($7E78DD)
; ============================================================
; Program 6: the picture on a turning mode-7 plane ($78DD–$8537)
; ============================================================
; Program 6 shows one picture (pack 34's mode-7 characters, pack 35's
; 64 x 64 map repeated 2 x 2 over the 128 x 128 mode-7 map) on a plane
; that C3Mod_BuildM7Tables tilts per line, two ways in turn: from a
; table of distances (C3Mod_Prog6StreamSetup) or in two halves built
; on alternate frames (C3Mod_Prog6HalfSetup), with a mode-1 strip
; under it; a scaled sprite picture (C3Mod_Prog6ScaleIdle,
; C3Mod_Prog6Sprites), three sprite rows along the horizon
; (C3Mod_Prog6HorizonTask with C3Mod_Prog6RowA, RowB and RowC) and an
; animated sprite group (C3Mod_Prog6AnimTask). Page $0A00's variables
; steer the plane, page
; $0B00's the sprites (see C3Mod_Prog6Script and C3Mod_Prog6ScriptB).

; $7E:78DD — C3Mod_Prog6 (283 bytes, $78DD–$79F7)
; The program of C3Mod_ProgramTable entry 6:
;   - VMADD = $2000, VMAIN = $80; C3Mod_DestBitmapSrc (the packs to
;     $7F:0200); pack 34 to VRAM's high bytes from word $2000
;     (C3Mod_DmaUnpacked with C3_DmaMode = 0, one register, C3_DmaBbad
;     = VMDATAH: mode-7 characters 128 on); pack 35 (the 64 x 64 map)
;     made 128 bytes a row by C3Mod_DoubleRows ($7F:2200-$41FF); VMADD
;     = 0, VMAIN = 0 (+ 1 after the low byte) and C3Mod_DmaFromArgs
;     twice with the same arguments (C3_DmaMode = 0, C3_DmaBbad =
;     VMDATAL, $7F:2200, $2000 bytes; the arguments are read again, so
;     the A-bus address starts at $2200 both times): the map's rows
;     0-63, then the same bytes as rows 64-127;
;   - pack 36 to $7E:2020 (C3_PaletteWork's colours $10 on); its
;     colours $50-$6F copied over $A0-$BF (MVN, bank $7E, DB kept
;     around it); raw pack 37's 32 bytes to $7E:2180 (colours $C0-$CF;
;     C3Mod_CopyRawPack with C3_RowCount = $20 at DP = 0, M=0); colour
;     0 = $6F69; C3Mod_CommitPalette; FdVec_FFEE (PalAnim_StopAll);
;   - C3Mod_Prog6Setup (the WRAM tables; pack 38, $1800 bytes, to
;     VRAM word $4400 ($4400-$4FFF: sprite tiles $40-$8F with OBSEL
;     $02, and BG1's tiles $90-$FF, at $4900-$4FFF with BG12NBA $04:
;     pack 39's attribute bytes all have bits 0-1 clear, so the map
;     uses only those), and pack 41, $C00 bytes, to $5000 (the sprites'
;     second tile page, which C3Mod_Prog6Frames' attribute $29 uses);
;     BG1's
;     mode-1 map; $7F:0200-$09FF filled; it leaves DP =
;     DP_DMA, which the calls up to C3_BuildCopyCode accept); pack 40
;     to $7F:0A00 (C3Mod_Prog6ScaleIdle's source bitmap);
;     C3_BuildCopyCode with WMADD = $7E:B574 (C3_CopyCode), X = $0C00,
;     Y = $0200;
;   - page $0A00 runs C3Mod_Prog6Script, once now (C3Mod_ScriptTaskA,
;     DB kept around it; it leaves DP = $0A00), page $0B00 gets
;     C3Mod_Prog6ScriptB; C3Mod_Prog6ScaleIdle written over
;     C3Mod_Start's idle call (.wait_exit + 1, a long store);
;     C3_Prog6Horizon and page $0B00's var 5 = $A8;
;   - DP = 0: C3_Prog6TilesReady + 1 (16-bit INC, from C3Mod_Init's
;     0), C3Mod_Prog6Sprites (its divisor, page $0B00's var 0, is
;     still 0: C3Mod_DivHighByte's quotient 0, so C3_SprBaseY = var 2
;     = 0, C3_Prog6Radius = 4 (0 + 3 + the SBC's carry) and
;     C3_SprBaseX = var 1 + 4 = 4; 8 sprites), then
;     C3Mod_Prog6ScaleIdle, which returns at once (C3_Prog6TilesReady
;     is set, so the first C3Mod_Prog6TilesNmiTask sends $0C00's $400
;     bytes as they are);
;   - DP = DP_PPU, DB = 0 (TDC / PHA / PLB: A's low byte): TM = TS =
;     TMW = $13 (BG1, BG2 and the sprites), COLDATA = $E0 (black),
;     SETINI = $41 (EXTBG and screen interlace), W12SEL = WOBJSEL =
;     $22 (window 1, not inverted, on BG1 and BG2, and on the sprites
;     and the colour window), BG1SC =
;     $60, BG12NBA = $04.
; Callers note: C3Mod_ProgramTable entry 6 (C3Mod_Start's JSR (table,X)
;   at $300A).
; Entry: M=1, X=0, DP=0, DB=$00 (as C3Mod_Start calls the programs).
; Exit:  M=1, X=0, DP = DP_PPU (not set back: C3Mod_Start's next calls
;        take any DP, and C3_ModuleFrame sets 0), DB=$00; A = $04; X,
;        Y as C3Mod_Prog6Sprites left them (C3Mod_Prog6ScaleIdle's
;        early RTS keeps them): C3_SprListLarge's X = C3_OamHiPtr, Y =
;        C3_OamPos.
; Calls: C3Mod_DestBitmapSrc, C3Mod_UnpackPack, C3Mod_DmaUnpacked (JSL),
;   C3Mod_DoubleRows (JSL), C3Mod_DmaFromArgs (JSL), C3Mod_CopyRawPack,
;   C3Mod_CommitPalette, FdVec_FFEE (JSL), C3Mod_Prog6Setup,
;   C3_BuildCopyCode (JSL), C3Mod_ScriptTaskA, C3Mod_Prog6Sprites,
;   C3Mod_Prog6ScaleIdle.
C3Mod_Prog6:
    SEP #$20
    REP #$10
    LDX.w #!C3_Prog6M7Chars
    STX.w VMADDL
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    JSR C3Mod_DestBitmapSrc
    LDX.w #34*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    TDC
    STA.w !C3_DmaMode                   ; 0: one register
    LDA.b #!BBAD_VMDATAH
    STA.w !C3_DmaBbad
    JSL C3Mod_DmaUnpacked
    LDX.w #35*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DoubleRows
    LDX.w #0
    STX.w VMADDL
    TDC
    STA.w VMAIN                         ; 0: + 1 after the low byte
    STA.w !C3_DmaMode
    LDA.b #!BBAD_VMDATAL
    STA.w !C3_DmaBbad
    LDX.w #!C3_BitmapDest
    STX.w !C3_DmaAddr
    LDA.b #!Bank7F
    STA.w !C3_DmaBank
    LDX.w #!C3_M7MapHalf
    STX.w !C3_DmaCount
    JSL C3Mod_DmaFromArgs
    JSL C3Mod_DmaFromArgs
    LDA.b #!Bank7E
    STA.w !Decomp_DestBank
    LDX.w #!C3_Prog6Colours
    STX.w !Decomp_Dest
    LDX.w #36*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    REP #$20
    PHB
    LDX.w #!C3_Prog6CopyFrom
    LDY.w #!C3_Prog6CopyTo
    LDA.w #!C3_Prog6CopyBytes-1
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes (bank $7E)
    PLB
    LDA.w #!C3_Prog6RawBytes
    STA.b !C3_RowCount
    LDY.w #!C3_Prog6RawTo
    LDX.w #37*!C3_PackPtrBytes
    JSR C3Mod_CopyRawPack
    LDA.w #!C3_Prog6Backdrop
    STA.l !C3_PaletteWork
    SEP #$20
    JSR C3Mod_CommitPalette
    JSL !FdVec_FFEE
    JSR C3Mod_Prog6Setup
    LDA.b #!Bank7F
    STA.w !Decomp_DestBank
    LDX.w #!C3_Prog6ScaleSrc
    STX.w !Decomp_Dest
    LDX.w #40*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    SEP #$20
    LDA.b #!Bank7E
    STA.w WMADDH
    LDX.w #!C3_CopyCodeAddr
    STX.w WMADDL                        ; and WMADDM
    LDX.w #!C3_CopyCodeDest
    LDY.w #!C3_CopyCodeSrc
    JSL !C3_BuildCopyCode
    REP #$30
    LDA.w #C3Mod_Prog6Script
    STA.w !C3_ScriptPageA+!C3Script_Ptr
    PHB
    JSR C3Mod_ScriptTaskA
    PLB
    LDA.w #C3Mod_Prog6ScriptB
    STA.w !C3_ScriptPageB+!C3Script_Ptr
    LDA.w #C3Mod_Prog6ScaleIdle
    STA.l C3Mod_Start_wait_exit+1
    LDA.w #!C3_Prog6HorizonStart
    STA.w !C3_Prog6Horizon
    STA.w !C3_ScriptPageB+!C3_Prog6SprVar5
    LDA.w #0
    TCD
    INC.b !C3_Prog6TilesReady
    JSR C3Mod_Prog6Sprites
    JSR C3Mod_Prog6ScaleIdle
    SEP #$20
    PEA.w !DP_PPU
    PLD
    TDC
    PHA                                 ; A's low byte: 0
    PLB
    LDA.b #!Layer_Bg12Obj
    STA.b TM-!DP_PPU
    STA.b TMW-!DP_PPU
    STA.b TS-!DP_PPU
    LDA.b #!COLDATA_AllZero
    STA.b COLDATA-!DP_PPU
    LDA.b #!C3_Prog6Setini
    STA.b SETINI-!DP_PPU
    LDA.b #!C3_Prog6Windows
    STA.b W12SEL-!DP_PPU
    STA.b WOBJSEL-!DP_PPU
    LDA.b #!C3_Prog6Bg1Sc
    STA.b BG1SC-!DP_PPU
    LDA.b #!C3_Prog6Tiles
    STA.b BG12NBA-!DP_PPU
    RTS

; $7E:79F8 — C3Mod_Prog6StreamNmi (61 bytes, $79F8–$7A34)
; A one-shot NMI task: the plane from the distance table. Page $0A00's
; var 0 (the scale) = $FF, var 2 = 0 and var 4 (M7Y) = $70 (16-bit
; stores); C3Mod_BuildM7Tables' .step = the .stream_x BRA (the word at
; C3Mod_M7StepBranches + 4, long copy) and its .setup operand =
; C3Mod_Prog6StreamSetup (self-modifying writes into
; C3Mod_BuildM7Tables); BGMODE = 7, COLDATA = $E0 (black); the HDMA
; channels of C3Mod_Prog6HdmaA (C3Mod_SetupHdma), C3_HdmaEnable =
; channels 0-4; then it ends itself (JMP C3Mod_NmiTaskEnd).
; Callers note: an NMI task added by script opcode $F8 at $7D29 and
;   $7DE9 (C3Mod_Prog6ScriptB).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1 (REP #$20 here), X=0,
;        DP any, DB=$00 (page $0A00 and the PPU registers are absolute;
;        the code patches are long).
; Exit:  JMP C3Mod_NmiTaskEnd with M=1, X=0, DB=$00 (C3Mod_SetupHdma's);
;        A = C3_Prog6HdmaOnA.
; Calls: C3Mod_SetupHdma.
C3Mod_Prog6StreamNmi:
    REP #$20
    LDA.w #!C3_Prog6StreamScale
    STA.w !C3_ScriptPageA+!C3_M7Scale
    LDA.w #0
    STA.w !C3_ScriptPageA+!C3_Prog6ScrollY
    LDA.w #!C3_Prog6StreamM7Y
    STA.w !C3_ScriptPageA+!C3_Prog6M7Y
    LDA.l C3Mod_M7StepBranches+4        ; BRA .stream_x
    STA.l C3Mod_BuildM7Tables_step
    LDA.w #C3Mod_Prog6StreamSetup
    STA.l C3Mod_BuildM7Tables_setup+1
    SEP #$20
    LDA.b #!BGMODE_Mode7
    STA.w BGMODE
    LDA.b #!COLDATA_AllZero
    STA.w COLDATA
    LDY.w #C3Mod_Prog6HdmaA
    JSR C3Mod_SetupHdma
    LDA.b #!C3_Prog6HdmaOnA
    STA.w !C3_HdmaEnable
    JMP C3Mod_NmiTaskEnd

; $7E:7A35 — C3Mod_Prog6HalfNmi (51 bytes, $7A35–$7A67)
; A one-shot NMI task: the plane in two halves with a mode-1 strip.
; C3Mod_BuildM7Tables' .setup operand = C3Mod_Prog6HalfSetup (a long
; store; .step is written by that setup), page $0A00's var 0 = $80;
; DP = DP_PPU: COLDATA = $E0 (black), TS = TMW = 0 (TDC: A's low byte
; of $2100), BGMODE = 1 (INC A), TM = $11 (BG1 and the sprites); the
; HDMA channels of C3Mod_Prog6HdmaB, C3_HdmaEnable = channels 0-5; then
; it ends itself (JMP C3Mod_NmiTaskEnd, which restores DP).
; Callers note: an NMI task added by script opcode $F8 at $7C82
;   (C3Mod_Prog6Script), $7DD6 and $7E90 (C3Mod_Prog6ScriptB).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1 (REP #$20 here), X=0,
;        DP any (set here), DB=$00 (page $0A00 and C3_HdmaEnable are
;        absolute; the code patch is long).
; Exit:  JMP C3Mod_NmiTaskEnd with M=1, X=0, DP = DP_PPU, DB=$00; A =
;        C3_Prog6HdmaOnB.
; Calls: C3Mod_SetupHdma.
C3Mod_Prog6HalfNmi:
    REP #$20
    LDA.w #C3Mod_Prog6HalfSetup
    STA.l C3Mod_BuildM7Tables_setup+1
    LDA.w #!C3_Prog6HalfScale
    STA.w !C3_ScriptPageA+!C3_M7Scale
    SEP #$20
    PEA.w !DP_PPU
    PLD
    LDA.b #!COLDATA_AllZero
    STA.b COLDATA-!DP_PPU
    TDC
    STA.b TS-!DP_PPU                    ; 0
    STA.b TMW-!DP_PPU
    INC A
    STA.b BGMODE-!DP_PPU                ; 1
    LDA.b #!Layer_Bg1Obj
    STA.b TM-!DP_PPU
    LDY.w #C3Mod_Prog6HdmaB
    JSR C3Mod_SetupHdma
    LDA.b #!C3_Prog6HdmaOnB
    STA.w !C3_HdmaEnable
    JMP C3Mod_NmiTaskEnd

; $7E:7A68 — C3Mod_Prog6Setup (308 bytes, $7A68–$7B9B)
; Program 6's tables and graphics:
;   - C3Scale_PrevEnd = $0A00 (16-bit, DP=0); WinFx_TablePtr = $E060,
;     WinFx_TableBank = $7E (bit 0 clear: bank $7E;
;     C3Mod_Prog6CircleTask's circles go to $7E:E060); DP = 0 (PEA /
;     PLD); C3_Prog6AnimTime = 1
;     and C3_Prog6AnimPtr = C3Mod_Prog6Anims - 2 (C3Mod_Prog6AnimTask
;     starts on the first entry);
;   - the distance table: through WMDATA from $7E:E260, 224 bytes ($E0,
;     8-bit C3_TmpF4 count): $FF - (Rom_SineTable[3n] >> 1) for n = 0
;     to 223 (SEC; X + 3: angles 0 to $29D, 1,024 a turn): $FF where
;     |sin| is 0, $80 at its peak (angle $100);
;   - DP = DP_PPU: through WMDATA, 32 bytes $E0, $E1, .. $FF from
;     $7E:E000 (INC A), then 32 bytes from $7E:E030 going down (DEC A)
;     from the $00 the first run ended on: $00, $FF, $FE, .. $E1
;     (COLDATA values: $E0-$FF all three colours at 0-31; $00 selects
;     no colour and changes nothing);
;   - DP = 0: C3Mod_DestBitmapSrc; VMAIN = $80; pack 38 to VRAM word
;     $4400 (C3_Prog6SprTiles: sprite tiles $40-$8F and BG1's tiles
;     $90-$FF) and pack 41 to $5000 (C3_Prog6SprPage2: the sprites'
;     second tile page with OBSEL $02) (C3Mod_DmaUnpacked with
;     C3_DmaMode = 1, two registers, C3_DmaBbad = VMDATAL); pack 39 to $7F:0200,
;     then BG1's map from VRAM word $6000: 7 rows of 32 words, each a
;     tile number from C3_TmpF0 (8-bit: $90 at first) and the next byte
;     of pack 39 (WMDATA from $7F:0200; WMADDH = 1 since the unpack)
;     as its attribute byte: the row's tiles t to t + 15 (INC after
;     each), then t + 15 down to t (DEC before each), t + $10 for the
;     next row (CLC); tiles $90-$FF in all;
;   - VMAIN = 0 (+ 1 after the low byte): tiles $B7-$B9 at words $6056-
;     $6058 and $C7-$C9 at $6076-$6078 (low bytes only: the attributes
;     kept);
;   - DP = DP_DMA: DMA channel 7 B to A from MPYL ($34, one register,
;     DMAP $80) into $7F:0200-$09FF ($800 bytes): every byte the low
;     byte of M7A x M7B, which is 0: C3Mod_Init writes M7A = $0404
;     and M7B = 0 on every path, before its C3_BootIrqOn test (and its
;     PPU clear writes both 0 again on the other path).
; Callers note: C3Mod_Prog6 ($7976).
; Entry: M=1, X=0 (16-bit addresses and counts), DP=0 (the
;        C3Scale_PrevEnd store comes before the PEA / PLD; then set
;        here), DB=$00 (the registers and the WinFx_* block are
;        absolute).
; Exit:  M=1, X=0, DP = DP_DMA (not restored), DB=$00; A = MDMAEN_Ch7,
;        X = $0800, Y = 0; WMADD at $7F:02E0 (the 224 attribute bytes
;        read); C3_TmpF0 = $00 ($90 + 7 x $10, 8-bit).
; Calls: C3Mod_DestBitmapSrc, C3Mod_UnpackPack, C3Mod_DmaUnpacked (JSL).
C3Mod_Prog6Setup:
    LDX.w #!C3_Prog6ScaleSrc
    STX.b !C3Scale_PrevEnd
    LDX.w #!C3_Prog6CircleTable
    STX.w !WinFx_TablePtr
    LDA.b #!Bank7E
    STA.w !WinFx_TableBank
    PEA.w 0
    PLD
    LDX.w #1
    STX.b !C3_Prog6AnimTime
    LDX.w #C3Mod_Prog6Anims-2
    STX.b !C3_Prog6AnimPtr
    LDA.b #!Bank7E
    STA.w WMADDH
    LDX.w #!C3_Prog6Distances
    STX.w WMADDL                        ; and WMADDM
    LDA.b #!WinFx_Lines
    STA.b !C3_TmpF4
    LDX.w #0
.distance:
    LDA.l !Rom_SineTable,X
    LSR A
    STA.b !C3_TmpF0
    LDA.b #!Eng_Invert8
    SEC
    SBC.b !C3_TmpF0
    STA.w WMDATA
    INX
    INX
    INX
    DEC.b !C3_TmpF4
    BNE .distance
    PEA.w !DP_PPU
    PLD
    LDA.b #!Bank7E
    STA.b WMADDH-!DP_PPU
    LDX.w #!C3_Prog6Ramp
    STX.b WMADDL-!DP_PPU                ; and WMADDM
    LDA.b #!COLDATA_AllZero
    LDX.w #!C3_Prog6RampBytes
.ramp_up:
    STA.b WMDATA-!DP_PPU
    INC A
    DEX
    BNE .ramp_up
    LDX.w #!C3_Prog6RampDown
    STX.b WMADDL-!DP_PPU                ; and WMADDM
    LDX.w #!C3_Prog6RampBytes
.ramp_down:
    STA.b WMDATA-!DP_PPU
    DEC A
    DEX
    BNE .ramp_down
    PEA.w 0
    PLD
    JSR C3Mod_DestBitmapSrc
    LDX.w #38*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDX.w #!C3_Prog6SprTiles
    STX.w VMADDL
    LDA.b #!DMAP_TwoRegs
    STA.w !C3_DmaMode
    LDA.b #!BBAD_VMDATAL
    STA.w !C3_DmaBbad
    JSL C3Mod_DmaUnpacked
    LDX.w #41*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog6SprPage2
    STX.w VMADDL
    JSL C3Mod_DmaUnpacked
    LDX.w #39*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog6Bg1Map
    STX.w VMADDL
    LDX.w #!C3_BitmapSrc
    STX.w WMADDL                        ; and WMADDM
    LDY.w #!C3_Prog6MapRows
    LDA.b #!C3_Prog6MapTile0
    STA.b !C3_TmpF0
.map_row:
    LDX.w #!C3_Prog6MapHalf
.map_left:
    LDA.b !C3_TmpF0
    STA.w VMDATAL
    LDA.w WMDATA
    STA.w VMDATAH
    INC.b !C3_TmpF0
    DEX
    BNE .map_left
    LDX.w #!C3_Prog6MapHalf
.map_right:
    DEC.b !C3_TmpF0
    LDA.b !C3_TmpF0
    STA.w VMDATAL
    LDA.w WMDATA
    STA.w VMDATAH
    DEX
    BNE .map_right
    LDA.b !C3_TmpF0
    CLC
    ADC.b #!C3_Prog6MapHalf
    STA.b !C3_TmpF0
    DEY
    BNE .map_row
    LDA.b #0
    STA.w VMAIN
    LDX.w #!C3_Prog6MapPatch1
    STX.w VMADDL
    LDA.b #!C3_Prog6PatchTile1
    STA.w VMDATAL
    INC A
    STA.w VMDATAL
    INC A
    STA.w VMDATAL
    LDX.w #!C3_Prog6MapPatch2
    STX.w VMADDL
    LDA.b #!C3_Prog6PatchTile2
    STA.w VMDATAL
    INC A
    STA.w VMDATAL
    INC A
    STA.w VMDATAL
    PEA.w !DP_DMA
    PLD
    LDA.b #!Bank7F
    STA.b A1B7-!DP_DMA
    LDX.w #!C3_BitmapSrc
    STX.b A1T7L-!DP_DMA
    LDA.b #!BBAD_MPYL
    STA.b BBAD7-!DP_DMA
    LDX.w #!C3_Prog6FillBytes
    STX.b DAS7L-!DP_DMA
    LDA.b #!DMAP_BtoA
    STA.b DMAP7-!DP_DMA
    STA.w MDMAEN                        ; MDMAEN_Ch7, the same value
    RTS

; $7E:7B9C — C3Mod_Prog6HdmaA (26 bytes, $7B9C–$7BB5)
; C3Mod_Prog6StreamNmi's HDMA channels (C3Mod_SetupHdma's records): 0
; and 1 the mode-7 matrix (indirect, two registers each written twice:
; M7A/M7B from C3Mod_M7HdmaAB, M7C/M7D from C3Mod_M7HdmaCD), 2 COLDATA
; (indirect, one register: C3Mod_Prog6ColourA), 3 WH0 / WH1 (indirect,
; two registers: C3Mod_Prog6WindowA), 4 CGWSEL / CGADSUB (indirect, two
; registers: C3Mod_Prog6MathA); the end.
C3Mod_Prog6HdmaA:
    db !DMAP_HdmaIndirect|!DMAP_TwoRegsTwice, !BBAD_M7A : dw C3Mod_M7HdmaAB : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegsTwice, !BBAD_M7C : dw C3Mod_M7HdmaCD : db !Bank7E
    db !DMAP_HdmaIndirect, !BBAD_COLDATA : dw C3Mod_Prog6ColourA : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegs, !BBAD_WH0 : dw C3Mod_Prog6WindowA : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegs, !BBAD_CGWSEL : dw C3Mod_Prog6MathA : db !Bank7E
    db !C3_HdmaListEnd

; $7E:7BB6 — C3Mod_Prog6HdmaB (31 bytes, $7BB6–$7BD4)
; C3Mod_Prog6HalfNmi's: 0 COLDATA (C3Mod_Prog6ColourB; channel 0 is
; the one C3Mod_Prog6ColourTask moves), 1 and 2 the mode-7 matrix as in
; C3Mod_Prog6HdmaA, 3 BG1HOFS / BG1VOFS (indirect, two registers each
; written twice: C3Mod_Prog6ScrollB), 4 BGMODE (indirect, one
; register: C3Mod_Prog6ModeB), 5 CGADSUB (indirect, one register:
; C3Mod_Prog6MathB); the end.
C3Mod_Prog6HdmaB:
    db !DMAP_HdmaIndirect, !BBAD_COLDATA : dw C3Mod_Prog6ColourB : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegsTwice, !BBAD_M7A : dw C3Mod_M7HdmaAB : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegsTwice, !BBAD_M7C : dw C3Mod_M7HdmaCD : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegsTwice, !BBAD_BG1HOFS : dw C3Mod_Prog6ScrollB : db !Bank7E
    db !DMAP_HdmaIndirect, !BBAD_BGMODE : dw C3Mod_Prog6ModeB : db !Bank7E
    db !DMAP_HdmaIndirect, !BBAD_CGADSUB : dw C3Mod_Prog6MathB : db !Bank7E
    db !C3_HdmaListEnd

; $7E:7BD5 — C3Mod_Prog6ColourA (13 bytes, $7BD5–$7BE1)
; Channel 2's indirect table under C3Mod_Prog6HdmaA (COLDATA, one byte
; a line): 26 lines that write the $00 of C3Mod_FillBytes ($350C: no
; colour selected, nothing changes), 32 lines (repeat) of the ramp down
; at $7E:E030 ($00, then $FF down to $E1), 108 lines that write black
; once ($E0, C3Mod_MathValues' .sky COLDATA byte, $4565), 32 lines
; (repeat) of the ramp up at $7E:E000 ($E0 to $FF); the end (198
; lines).
C3Mod_Prog6ColourA:
    db 26 : dw C3Mod_FillBytes+2
    db !C3_HdmaRepeat|32 : dw !C3_Prog6RampDown
    db 108 : dw C3Mod_MathValues_sky+1
    db !C3_HdmaRepeat|32 : dw !C3_Prog6Ramp
    db 0

; $7E:7BE2 — C3Mod_Prog6ColourB (16 bytes, $7BE2–$7BF1)
; Channel 0's under C3Mod_Prog6HdmaB (COLDATA): 80 lines of black
; (written once), 32 lines (repeat) of the ramp up from $7E:E000 (.ramp),
; 8 and 8 lines (.white, .white2) that write $FF once (C3Mod_FillBytes'
; first byte: all three colours at 31), 32 lines (repeat) of the ramp
; down from $7E:E030; the end (160 lines). C3Mod_Prog6ColourTask
; changes the counts and .ramp's address as it runs.
C3Mod_Prog6ColourB:
    db 80 : dw C3Mod_MathValues_sky+1
.ramp:
    db !C3_HdmaRepeat|32 : dw !C3_Prog6Ramp
.white:
    db 8 : dw C3Mod_FillBytes
.white2:
    db 8 : dw C3Mod_FillBytes
    db !C3_HdmaRepeat|32 : dw !C3_Prog6RampDown
    db 0

; $7E:7BF2 — C3Mod_Prog6ColourTask (62 bytes, $7BF2–$7C2F)
; A task: moves the bands of C3Mod_Prog6ColourB, with DB = $7E (PHK /
; PLB; the table is absolute), 8-bit:
;   - while its first count is not 2 (CMP / BEQ): that count - 2,
;     .white's count + 2 and .white2's + 1 (39 frames from 80: the
;     black band shrinks, the white ones grow to 86 and 47 lines);
;   - then, while .ramp's address low byte is not $1E (CMP / BEQ):
;     that byte + 2 (the ramp starts 2 lines further up it), .ramp's
;     count - 2 (it stays a repeat entry, $A0 down to $82) and
;     .white's count + 2 (to 116), and channel 0's table address
;     (A1T0L/H, 16-bit long store) = .ramp: from the next frame HDMA
;     starts the table there, past its first entry (15 frames);
;   - then nothing more (the task stays).
; Callers note: a task added by script opcode $FA at $7EAB
;   (C3Mod_Prog6ScriptB).
; Entry: a task: M=0 (8-bit set here), X any, DP any, DB any (set
;        here; restored by C3Mod_RunTasks).
; Exit:  M=1 (the first phase and the end), or M=0 after the A1T0
;        store; DB = $7E; A = the count or byte compared, or
;        C3Mod_Prog6ColourB_ramp; X, Y unchanged.
C3Mod_Prog6ColourTask:
    SEP #$20
    PHK
    PLB
    LDA.w C3Mod_Prog6ColourB
    CMP.b #!C3_Prog6BlackLeft
    BEQ .ramp
    DEC.w C3Mod_Prog6ColourB
    DEC.w C3Mod_Prog6ColourB
    INC.w C3Mod_Prog6ColourB_white
    INC.w C3Mod_Prog6ColourB_white
    INC.w C3Mod_Prog6ColourB_white2
    RTS
.ramp:
    LDA.w C3Mod_Prog6ColourB_ramp+1
    CMP.b #!C3_Prog6RampSkip
    BEQ .done
    INC.w C3Mod_Prog6ColourB_ramp+1
    INC.w C3Mod_Prog6ColourB_ramp+1
    DEC.w C3Mod_Prog6ColourB_ramp
    DEC.w C3Mod_Prog6ColourB_ramp
    INC.w C3Mod_Prog6ColourB_white
    INC.w C3Mod_Prog6ColourB_white
    REP #$20
    LDA.w #C3Mod_Prog6ColourB_ramp
    STA.l A1T0L                         ; and A1T0H
.done:
    RTS

; $7E:7C30 — C3Mod_Prog6MathB (14 bytes, $7C30–$7C3D)
; Channel 5's indirect table under C3Mod_Prog6HdmaB (CGADSUB): .value
; ($03: add on BG1 and BG2) for 84 + 83 lines and then .count's lines
; (C3Mod_Prog6StripNmi: C3_Prog6Horizon - $A7), written once each; then
; one line of the $00 of C3Mod_FillBytes ($350B: no colour math) under
; the plane; the end.
C3Mod_Prog6MathB:
    db 84 : dw .value
    db 83 : dw .value
.count:
    db 1 : dw .value
    db 1 : dw C3Mod_FillBytes+1
    db 0
.value:
    db !C3_Prog6PlaneMath

; $7E:7C3E — C3Mod_Prog6ModeB (14 bytes, $7C3E–$7C4B)
; Channel 4's (BGMODE): mode 7 (.mode7) for 84 + 83 + .count's lines,
; then one line written from .mode1's own count byte ($01: BGMODE 1),
; which stays for the rest of the frame; the end.
C3Mod_Prog6ModeB:
    db 84 : dw .mode7
    db 83 : dw .mode7
.count:
    db 1 : dw .mode7
.mode1:
    db 1 : dw .mode1
    db 0
.mode7:
    db !BGMODE_Mode7

; $7E:7C4C — C3Mod_Prog6ScrollB (16 bytes, $7C4C–$7C5B)
; Channel 3's (BG1HOFS and BG1VOFS, low and high byte each): page
; $0A00's var 1 and var 2 ($0A02-$0A05) for 84 + 83 + .count's lines;
; then one line from .strip: BG1HOFS = .strip's word, BG1VOFS =
; .strip + 2's (C3Mod_Prog6StripNmi writes $100 - page $0B00's var 1
; and $FF - C3_Prog6Horizon there), the mode-1 strip under the plane.
; .strip's first byte is also the table's end: it is $00 only while
; page $0B00's var 1 is 0 (C3Mod_Prog6StripNmi writes $100 - var 1
; there), and var 1 is 0 whenever C3Mod_Prog6StripNmi runs: the first
; $F8 ($7C85) is in page $0A00's script, run before page $0B00's, so
; var 1 is still C3Mod_Init's 0 (C3Mod_Prog6ScriptB's own var 1 = 0 at
; $7CF6 comes after); C3Mod_Prog6ScriptB sets var 1 = $E0 at $7D17,
; but removes the task ($F7 at $7D23) in the same run, with no yield
; between, so no NMI comes between; it sets var 1 = 0 at $7DCD and
; $7E87 before the next two $F8 ($7DD9, $7E93; no yield between
; either), and changes it again only after the $F7 at $7DEC ($7DFD;
; nothing after $7E93).
C3Mod_Prog6ScrollB:
    db 84 : dw !C3_ScriptPageA+!C3_Prog6ScrollX
    db 83 : dw !C3_ScriptPageA+!C3_Prog6ScrollX
.count:
    db 1 : dw !C3_ScriptPageA+!C3_Prog6ScrollX
    db 1 : dw .strip
.strip:
    dw 0                                ; the end, and BG1HOFS
    dw !C3_Prog6StripVofs

; $7E:7C5C — C3Mod_Prog6WindowA (10 bytes, $7C5C–$7C65)
; Channel 3's under C3Mod_Prog6HdmaA (WH0 / WH1): window 1 shut ($FF,
; $00 from C3Mod_FillBytes) for 80 lines (written once), then .circle
; (repeat) from $7E:E0E0 (C3_Prog6CircleCopy: a left edge, right $FF,
; per line), then one more shut line; the end. C3Mod_Prog6CircleTask
; writes both counts: the first var 2 - 1 - r, .circle's 2r + $80.
C3Mod_Prog6WindowA:
    db 80 : dw C3Mod_FillBytes
.circle:
    db !C3_HdmaRepeat|64 : dw !C3_Prog6CircleCopy
    db 1 : dw C3Mod_FillBytes
    db 0

; $7E:7C66 — C3Mod_Prog6MathA (13 bytes, $7C66–$7C72)
; Channel 4's (CGWSEL / CGADSUB): .outside (CGWSEL 0, CGADSUB $83:
; subtract the fixed colour on BG1 and BG2) for 80 lines, .inside
; (CGWSEL $02, add the sub screen; CGADSUB $22: add on BG2 and the
; backdrop) for 64, then .outside for 1, each written once; the end.
; .outside's first byte is also the end. C3Mod_Prog6CircleTask writes
; the first count (as C3Mod_Prog6WindowA's) and .inside's (2r, no
; repeat bit).
C3Mod_Prog6MathA:
    db 80 : dw .outside
.inside:
    db 64 : dw .math_in
    db 1 : dw .outside
.outside:
    db 0, !C3_Prog6MathOut              ; the end, and CGWSEL / CGADSUB
.math_in:
    db !CGWSEL_AddSubscreen, !C3_Prog6MathIn

; $7E:7C73 — C3Mod_Prog6Script (69 bytes, $7C73–$7CB7)
; Page $0A00's script in program 6 (its vars: 0 the plane's scale
; C3_M7Scale, 1 and 2 BG1HOFS / BG1VOFS C3_Prog6ScrollX / ScrollY, 3
; and 4 M7X / M7Y C3_Prog6M7X / M7Y, 5 the angle C3_M7Angle, 7
; C3_Prog6Rebuild, 8 the scroll step C3_Prog6ScrollStep): the NMI
; tasks C3Mod_OamUploadTask, C3Mod_HideSprites, C3Mod_Prog6ScrollNmi
; and C3Mod_Prog6TilesNmiTask; C3Mod_Prog6TasksB (the task list
; replaced); the one-shot NMI tasks C3Mod_Prog6HalfNmi and
; C3Mod_Prog6StripNmi; var 5 = 0, var 8 = $0D; C3_FadeStep =
; C3_FadeTimer = 2 (a word poke) and C3Mod_FadeInTask; sound effect
; $DB (C3_SndSfxA); var 0 = $FF; it yields (the end of what
; C3Mod_Prog6's own C3Mod_ScriptTaskA call runs); then var 2 = 0, var
; 4 = $70, var 1 = 0, var 3 = $80, var 9 = 0 (not read in this
; program), var 5 = $200, C3_Prog6HorizonMask = 0 (a byte poke); then
; it waits for good, until C3Mod_Prog6ScriptB moves it to
; C3Mod_Prog6Brake.
C3Mod_Prog6Script:
    db !C3Op_NmiAdd : dw C3Mod_OamUploadTask
    db !C3Op_NmiAdd : dw C3Mod_HideSprites
    db !C3Op_NmiAdd : dw C3Mod_Prog6ScrollNmi
    db !C3Op_NmiAdd : dw C3Mod_Prog6TilesNmiTask
    db !C3Op_CallW : dw C3Mod_Prog6TasksB
    db !C3Op_NmiAdd : dw C3Mod_Prog6HalfNmi
    db !C3Op_NmiAdd : dw C3Mod_Prog6StripNmi
    db !C3Op_Set|5 : dw $0000
    db !C3Op_Set|8 : dw $000D
    db !C3Op_Poke16 : dw !C3_FadeStep, !C3_Prog6Fade
    db !C3Op_TaskAdd : dw C3Mod_FadeInTask
    db !C3Op_Driver : dw !C3_SndSfxA|($DB<<8), $0080
    db !C3Op_Set|0 : dw $00FF
    db !C3Op_Yield
    db !C3Op_Set|2 : dw $0000
    db !C3Op_Set|4 : dw $0070
    db !C3Op_Set|1 : dw $0000
    db !C3Op_Set|3 : dw $0080
    db !C3Op_Set|9 : dw $0000
    db !C3Op_Set|5 : dw $0200
    db !C3Op_Poke8 : dw !C3_Prog6HorizonMask : db 0
.l7CB5:
    db !C3Op_JumpYield : dw .l7CB5

; $7E:7CB8 — C3Mod_Prog6Brake (28 bytes, $7CB8–$7CD3)
; Page $0A00's script from $7D12 on (C3Mod_Prog6ScriptB's word poke of
; its pointer): sound effect $DA; var 8 (the scroll step) = -6, var 10
; = 0 (not read in this program); 20 frames; then 6 times var 8 - 2,
; each over two frames (var 8 ends at -$12); then it waits for good.
C3Mod_Prog6Brake:
    db !C3Op_Driver : dw !C3_SndSfxA|($DA<<8), $0080
    db !C3Op_Set|8 : dw -$6
    db !C3Op_Set|10 : dw $0000
.l7CC3:
    db !C3Op_LoopYield|1 : dw $0013, .l7CC3             ; 20 passes
.l7CC8:
    db !C3Op_Add|8 : dw -$2
    db !C3Op_Yield
    db !C3Op_LoopYield|0 : dw $0005, .l7CC8             ; 6 passes
.l7CD1:
    db !C3Op_JumpYield : dw .l7CD1

; $7E:7CD4 — C3Mod_Prog6Dive (31 bytes, $7CD4–$7CF2)
; Page $0A00's script from $7DC8 on: C3_Prog6HorizonMask = 1; sound
; effect $DB; var 8 = $0D; var 0 (the scale) - 4 a frame for 32
; frames, then + 2 a frame for 64 (back where it was); then it waits
; for good.
C3Mod_Prog6Dive:
    db !C3Op_Poke8 : dw !C3_Prog6HorizonMask : db 1
    db !C3Op_Driver : dw !C3_SndSfxA|($DB<<8), $0080
    db !C3Op_Set|8 : dw $000D
.l7CE0:
    db !C3Op_Add|0 : dw -$4
    db !C3Op_LoopYield|0 : dw $001F, .l7CE0             ; 32 passes
.l7CE8:
    db !C3Op_Add|0 : dw $0002
    db !C3Op_LoopYield|0 : dw $003F, .l7CE8             ; 64 passes
.l7CF0:
    db !C3Op_JumpYield : dw .l7CF0

; $7E:7CF3 — C3Mod_Prog6ScriptB (468 bytes, $7CF3–$7EC6)
; Page $0B00's script in program 6 (its vars: 0 the scaled picture's
; size C3_Prog6SprSize, 1 and 2 the sprites' position C3_Prog6SprX /
; SprY, 5 C3_Prog6SprVar5, 6 the circle's radius C3_Prog6CircleR, 10
; a step added to var 1, C3_Prog6SprSpeed). In order (a frame is one
; yield; a $9x
; loop opcode yields on every pass, the last one too):
;   - var 5 = $A8 (not read in this program), var 1 = 0; the NMI task
;     C3Mod_UploadPalette and C3Mod_Prog6PalIn (a kind-4 palette
;     animation of colours $20-$3F, level $FF to 0); 60 frames;
;     C3Mod_PalAnimTask for 300 frames
;     (then removed, and C3Mod_UploadPalette with it);
;   - page $0A00 moved to C3Mod_Prog6Brake; var 1 = $E0, var 2 = $70,
;     var 0 = $61, var 6 = $0A; C3Mod_Prog6StripNmi removed;
;     C3Mod_Prog6TasksA; C3Mod_Prog6StreamNmi; C3Mod_Prog6RadiusTask
;     and C3Mod_Prog6CircleTask; one frame; TS = BG1 and the sprites,
;     TMW = BG1, BG2 and the sprites (opcode $FB);
;   - 23 frames of var 10 - 1, var 1 + var 10; 41 frames; 8 passes of
;     three frames each (var 1 + 3 each frame, var 2 + 1 once, var 0 +
;     2 each frame: var 0 to $91), 16 passes (var 1 + 2, var 2 - 1
;     once, var 0 - 2 each frame: to $31), 16 passes of two frames
;     (var 1 + 1 each, var 2 + 1 and var 0 + 2 once: to $51);
;   - C3Mod_Prog6RadiusTask removed (it still runs in the frame it is
;     removed, after this script, so the first var 6 - 1 below is
;     undone: var 6 = 16 again); var 6 - 1 for 6 frames, var 6 - 1 and
;     var 1 - 2 for 10 (var 6 down to 1, never 0); TMW = 0;
;     C3Mod_Prog6CircleTask removed; var 10 = 0, then 18 frames of var
;     10 - 1, var 1 + var 10; C3Mod_Prog6Sprites removed; 50 frames;
;   - page $0A00's var 5 (the angle) = $200 and page $0A00 moved to
;     C3Mod_Prog6Dive; var 1 = 0; C3Mod_Prog6TasksB;
;     C3Mod_Prog6ShuffleTask; C3Mod_Prog6HalfNmi and
;     C3Mod_Prog6StripNmi; 180 frames;
;   - page $0A00's var 8 = -$11; C3Mod_Prog6TasksA;
;     C3Mod_Prog6StreamNmi; C3Mod_Prog6StripNmi removed;
;     C3Mod_Prog6RiseTask; C3Mod_Prog6Sprites removed (C3Mod_Prog6TasksA
;     had put it back); C3Mod_Prog6AnimTask; sound effect $DA; var 1 =
;     $D0, var 0 = $60; then the moves of 24, 24, 16, 16 and 8 passes
;     of two frames and 32 single frames (vars 0, 1 and 2 by the
;     amounts below); 60 frames;
;   - page $0A00's var 5 = 0; var 1 = 0; C3Mod_Prog6TasksB;
;     C3Mod_Prog6ShuffleTask; C3Mod_Prog6HalfNmi and
;     C3Mod_Prog6StripNmi; C3_Prog6HorizonMask = 3; sound effect $DB;
;     it waits for APUIO2's low nibble to reach 4 (opcode $F5), then
;     driver command $F1 (stop the song) and sound effect $DC;
;     C3Mod_Prog6ColourTask; 60 frames;
;   - C3Mod_PalAnimTask, C3Mod_UploadPalette and C3Mod_Prog6PalOut (a
;     fade of colours $80-$BF and $50-$7F); 50 frames;
;     C3Mod_FadeOutExitTask; then it waits for good.
C3Mod_Prog6ScriptB:
    db !C3Op_Set|5 : dw $00A8
    db !C3Op_Set|1 : dw $0000
    db !C3Op_NmiAdd : dw C3Mod_UploadPalette
    db !C3Op_CallW : dw C3Mod_Prog6PalIn
.l7CFF:
    db !C3Op_LoopYield|1 : dw $003B, .l7CFF             ; 60 passes
    db !C3Op_TaskAdd : dw C3Mod_PalAnimTask
.l7D07:
    db !C3Op_LoopYield|1 : dw $012B, .l7D07             ; 300 passes
    db !C3Op_TaskRemove : dw C3Mod_PalAnimTask
    db !C3Op_NmiRemove : dw C3Mod_UploadPalette
    db !C3Op_Poke16 : dw !C3_ScriptPageA+!C3Script_Ptr, C3Mod_Prog6Brake
    db !C3Op_Set|1 : dw $00E0
    db !C3Op_Set|2 : dw $0070
    db !C3Op_Set|0 : dw $0061
    db !C3Op_Set|6 : dw $000A
    db !C3Op_NmiRemove : dw C3Mod_Prog6StripNmi
    db !C3Op_CallW : dw C3Mod_Prog6TasksA
    db !C3Op_NmiAdd : dw C3Mod_Prog6StreamNmi
    db !C3Op_TaskAdd : dw C3Mod_Prog6RadiusTask
    db !C3Op_TaskAdd : dw C3Mod_Prog6CircleTask
    db !C3Op_Yield
    db !C3Op_Ppu, !Layer_Bg1Obj, TS-!DP_PPU
    db !C3Op_Ppu, !Layer_Bg12Obj, TMW-!DP_PPU
.l7D39:
    db !C3Op_Add|10 : dw -$1
    db !C3Op_AddVar|1, 20                               ; var 1 += var 10
    db !C3Op_LoopYield|0 : dw $0016, .l7D39             ; 23 passes
.l7D43:
    db !C3Op_LoopYield|1 : dw $0028, .l7D43             ; 41 passes
.l7D48:
    db !C3Op_Add|1 : dw $0003
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Add|0 : dw $0002
    db !C3Op_Yield
    db !C3Op_Add|1 : dw $0003
    db !C3Op_Add|0 : dw $0002
    db !C3Op_Yield
    db !C3Op_Add|1 : dw $0003
    db !C3Op_Add|0 : dw $0002
    db !C3Op_LoopYield|0 : dw $0007, .l7D48             ; 8 passes
.l7D64:
    db !C3Op_Add|1 : dw $0002
    db !C3Op_Add|2 : dw -$1
    db !C3Op_Add|0 : dw -$2
    db !C3Op_Yield
    db !C3Op_Add|1 : dw $0002
    db !C3Op_Add|0 : dw -$2
    db !C3Op_Yield
    db !C3Op_Add|1 : dw $0002
    db !C3Op_Add|0 : dw -$2
    db !C3Op_LoopYield|0 : dw $000F, .l7D64             ; 16 passes
.l7D80:
    db !C3Op_Add|1 : dw $0001
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Add|0 : dw $0002
    db !C3Op_Yield
    db !C3Op_Add|1 : dw $0001
    db !C3Op_LoopYield|0 : dw $000F, .l7D80             ; 16 passes
    db !C3Op_TaskRemove : dw C3Mod_Prog6RadiusTask
.l7D95:
    db !C3Op_Add|6 : dw -$1
    db !C3Op_LoopYield|0 : dw $0005, .l7D95             ; 6 passes
.l7D9D:
    db !C3Op_Add|6 : dw -$1
    db !C3Op_Add|1 : dw -$2
    db !C3Op_LoopYield|0 : dw $0009, .l7D9D             ; 10 passes
    db !C3Op_Ppu, 0, TMW-!DP_PPU
    db !C3Op_TaskRemove : dw C3Mod_Prog6CircleTask
    db !C3Op_Set|10 : dw $0000
.l7DB1:
    db !C3Op_Add|10 : dw -$1
    db !C3Op_AddVar|1, 20                               ; var 1 += var 10
    db !C3Op_LoopYield|0 : dw $0011, .l7DB1             ; 18 passes
    db !C3Op_TaskRemove : dw C3Mod_Prog6Sprites
.l7DBE:
    db !C3Op_LoopYield|1 : dw $0031, .l7DBE             ; 50 passes
    db !C3Op_Poke16 : dw !C3_ScriptPageA+!C3_M7Angle, $0200
    db !C3Op_Poke16 : dw !C3_ScriptPageA+!C3Script_Ptr, C3Mod_Prog6Dive
    db !C3Op_Set|1 : dw $0000
    db !C3Op_CallW : dw C3Mod_Prog6TasksB
    db !C3Op_TaskAdd : dw C3Mod_Prog6ShuffleTask
    db !C3Op_NmiAdd : dw C3Mod_Prog6HalfNmi
    db !C3Op_NmiAdd : dw C3Mod_Prog6StripNmi
.l7DDC:
    db !C3Op_LoopYield|1 : dw $00B3, .l7DDC             ; 180 passes
    db !C3Op_Poke16 : dw !C3_ScriptPageA+!C3_Prog6ScrollStep, -$11
    db !C3Op_CallW : dw C3Mod_Prog6TasksA
    db !C3Op_NmiAdd : dw C3Mod_Prog6StreamNmi
    db !C3Op_NmiRemove : dw C3Mod_Prog6StripNmi
    db !C3Op_TaskAdd : dw C3Mod_Prog6RiseTask
    db !C3Op_TaskRemove : dw C3Mod_Prog6Sprites
    db !C3Op_TaskAdd : dw C3Mod_Prog6AnimTask
    db !C3Op_Driver : dw !C3_SndSfxA|($DA<<8), $0080
    db !C3Op_Set|1 : dw $00D0
    db !C3Op_Set|0 : dw $0060
.l7E03:
    db !C3Op_Add|1 : dw -$2
    db !C3Op_Add|2 : dw $0001
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Yield
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Add|1 : dw -$2
    db !C3Op_LoopYield|0 : dw $0017, .l7E03             ; 24 passes
.l7E18:
    db !C3Op_Add|1 : dw -$3
    db !C3Op_Add|2 : dw -$1
    db !C3Op_Add|0 : dw -$2
    db !C3Op_Yield
    db !C3Op_Add|0 : dw -$1
    db !C3Op_Add|1 : dw -$3
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $0017, .l7E18             ; 24 passes
.l7E30:
    db !C3Op_Add|1 : dw $0003
    db !C3Op_Add|2 : dw -$1
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Yield
    db !C3Op_Add|1 : dw $0003
    db !C3Op_Add|2 : dw -$1
    db !C3Op_LoopYield|0 : dw $000F, .l7E30             ; 16 passes
.l7E45:
    db !C3Op_Add|1 : dw $0004
    db !C3Op_Add|2 : dw $0002
    db !C3Op_Add|0 : dw -$1
    db !C3Op_Yield
    db !C3Op_Add|1 : dw $0004
    db !C3Op_Add|2 : dw $0001
    db !C3Op_LoopYield|0 : dw $000F, .l7E45             ; 16 passes
.l7E5A:
    db !C3Op_Add|1 : dw -$8
    db !C3Op_Add|2 : dw $0002
    db !C3Op_Add|0 : dw $0001
    db !C3Op_Yield
    db !C3Op_Add|1 : dw -$8
    db !C3Op_Add|2 : dw $0001
    db !C3Op_LoopYield|0 : dw $0007, .l7E5A             ; 8 passes
.l7E6F:
    db !C3Op_Add|1 : dw -$6
    db !C3Op_Add|2 : dw -$1
    db !C3Op_Add|0 : dw $0001
    db !C3Op_LoopYield|0 : dw $001F, .l7E6F             ; 32 passes
.l7E7D:
    db !C3Op_LoopYield|1 : dw $003B, .l7E7D             ; 60 passes
    db !C3Op_Poke16 : dw !C3_ScriptPageA+!C3_M7Angle, $0000
    db !C3Op_Set|1 : dw $0000
    db !C3Op_CallW : dw C3Mod_Prog6TasksB
    db !C3Op_TaskAdd : dw C3Mod_Prog6ShuffleTask
    db !C3Op_NmiAdd : dw C3Mod_Prog6HalfNmi
    db !C3Op_NmiAdd : dw C3Mod_Prog6StripNmi
    db !C3Op_Poke8 : dw !C3_Prog6HorizonMask : db 3
    db !C3Op_Driver : dw !C3_SndSfxA|($DB<<8), $0080
    db !C3Op_WaitApu, 4
    db !C3Op_Driver : dw !C3_SndStopSong, $0000
    db !C3Op_Driver : dw !C3_SndSfxA|($DC<<8), $0080
    db !C3Op_TaskAdd : dw C3Mod_Prog6ColourTask
.l7EAE:
    db !C3Op_LoopYield|1 : dw $003B, .l7EAE             ; 60 passes
    db !C3Op_TaskAdd : dw C3Mod_PalAnimTask
    db !C3Op_NmiAdd : dw C3Mod_UploadPalette
    db !C3Op_CallW : dw C3Mod_Prog6PalOut
.l7EBC:
    db !C3Op_LoopYield|1 : dw $0031, .l7EBC             ; 50 passes
    db !C3Op_TaskAdd : dw C3Mod_FadeOutExitTask
.l7EC4:
    db !C3Op_JumpYield : dw .l7EC4

; $7E:7EC7 — C3Mod_Prog6TableA (10 bytes, $7EC7–$7ED0)
; The task list C3Mod_Prog6TasksA installs: C3Mod_Prog6PlaneTask,
; C3Mod_ScriptTaskA, C3Mod_ScriptTaskB, C3Mod_Prog6ScrollXTask and
; C3Mod_Prog6Sprites (entries 0-4 of C3_TaskList).
C3Mod_Prog6TableA:
    dw C3Mod_Prog6PlaneTask, C3Mod_ScriptTaskA, C3Mod_ScriptTaskB
    dw C3Mod_Prog6ScrollXTask, C3Mod_Prog6Sprites

; $7E:7ED1 — C3Mod_Prog6TasksA (11 bytes, $7ED1–$7EDB)
; A script routine (opcode $F0): C3_TaskList cleared
; (C3Mod_ClearTaskList), then C3Mod_Prog6TableA's 10 bytes copied
; over its first five entries (MVN in bank $7E at C3Mod_Prog6TasksB's
; .copy). The tasks of this frame run on (C3Mod_RunTasks runs the copy
; C3_TaskRun); from the next frame these run, the script tasks among
; them, with what the script adds or removes after the call
; (C3Mod_Prog6RadiusTask and C3Mod_Prog6CircleTask after $7D26;
; C3Mod_Prog6RiseTask and C3Mod_Prog6AnimTask added and
; C3Mod_Prog6Sprites removed after $7DE6).
; Callers note: script opcode $F0 at $7D26 and $7DE6
;   (C3Mod_Prog6ScriptB).
; Entry: M=0, X=0 (16-bit MVN registers), DP any (the script's page),
;        DB any (the MVNs set $7E), as C3_RunScript calls its opcode 0
;        routines.
; Exit:  M=0, X=0, DB = $7E; A = $FFFF; X = C3Mod_Prog6TableA + 10, Y =
;        C3_TaskList + 10.
; Calls: C3Mod_ClearTaskList.
C3Mod_Prog6TasksA:
    JSR C3Mod_ClearTaskList
    LDX.w #C3Mod_Prog6TableA
    LDA.w #!C3_Prog6TableABytes-1
    BRA C3Mod_Prog6TasksB_copy

; $7E:7EDC — C3Mod_Prog6TableB (12 bytes, $7EDC–$7EE7)
; The task list C3Mod_Prog6TasksB installs: C3Mod_Prog6PlaneTask twice
; (when the first run builds, C3Mod_Prog6HalfSetup's odd call adds 1
; to C3_Prog6Rebuild, so the second builds the other half in the same
; frame; otherwise both return at once),
; C3Mod_Prog6HorizonTask, C3Mod_ScriptTaskA, C3Mod_ScriptTaskB and
; C3Mod_Prog6ScrollYTask (entries 0-5).
C3Mod_Prog6TableB:
    dw C3Mod_Prog6PlaneTask, C3Mod_Prog6PlaneTask, C3Mod_Prog6HorizonTask
    dw C3Mod_ScriptTaskA, C3Mod_ScriptTaskB, C3Mod_Prog6ScrollYTask

; $7E:7EE8 — C3Mod_Prog6TasksB (16 bytes, $7EE8–$7EF7)
; As C3Mod_Prog6TasksA with C3Mod_Prog6TableB (12 bytes, six
; entries); .copy ($7EF1) is the MVN both use: A + 1 bytes from X to
; C3_TaskList.
; Sub-entry: .copy ($7EF1), from C3Mod_Prog6TasksA (BRA).
; Callers note: script opcode $F0 at $7C7F (C3Mod_Prog6Script), $7DD0
;   and $7E8A (C3Mod_Prog6ScriptB). .copy: C3Mod_Prog6TasksA (BRA).
; Entry: M=0, X=0 (16-bit MVN registers), DP any (the script's page),
;        DB any (the MVNs set $7E); .copy: X = the table, A = its bytes
;        - 1.
; Exit:  M=0, X=0, DB = $7E; A = $FFFF; X past the table, Y =
;        C3_TaskList + its bytes.
; Calls: C3Mod_ClearTaskList.
C3Mod_Prog6TasksB:
    JSR C3Mod_ClearTaskList
    LDX.w #C3Mod_Prog6TableB
    LDA.w #!C3_Prog6TableBBytes-1
.copy:
    LDY.w #!C3_TaskList
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes (bank $7E)
    RTS

; $7E:7EF8 — C3Mod_ClearTaskList (13 bytes, $7EF8–$7F04)
; C3_TaskList ($0920, 16 words) cleared: 32 bytes copied from
; $D2:0000 (MVN, ROM bank $D2 to $7E), where GfxRom_D2's first 32
; bytes are zero.
; Callers note: C3Mod_Prog6TasksA ($7ED1), C3Mod_Prog6TasksB ($7EE8),
;   C3Mod_Prog10Fill ($8A02), C3Mod_Prog10Strip ($8AF6), C3Mod_Prog10Stars
;   ($8BB0), C3Mod_Prog10M7Scene ($8C15) and C3Mod_Prog10Grid ($8CD1).
; Entry: M=0, X=0 (16-bit MVN registers), DP any, DB any.
; Exit:  M=0, X=0, DB = $7E (the MVN's destination); A = $FFFF; X =
;        $0020, Y = C3_TaskList + $20.
C3Mod_ClearTaskList:
    LDX.w #!GfxRom_D2&$FFFF
    LDY.w #!C3_TaskList
    LDA.w #!C3_TaskListBytes-1
    MVN !Bank7E,!BankD2                 ; lint-ok: MVN operands are bank bytes ($D2:0000 to $7E)
    RTS

; $7E:7F05 — C3Mod_ClearNmiTaskList (13 bytes, $7F05–$7F11)
; C3_NmiTaskList ($0940, 8 words) cleared the same way: 16 zero bytes
; from $D2:0000.
; Callers note: C3Mod_Prog10Fill ($8A05), C3Mod_Prog10Strip ($8AF9),
;   C3Mod_Prog10Stars ($8BB3) and C3Mod_Prog10M7Scene ($8C18).
; Entry: M=0, X=0 (16-bit MVN registers), DP any, DB any.
; Exit:  M=0, X=0, DB = $7E; A = $FFFF; X = $0010, Y = C3_NmiTaskList
;        + $10.
C3Mod_ClearNmiTaskList:
    LDX.w #!GfxRom_D2&$FFFF
    LDY.w #!C3_NmiTaskList
    LDA.w #!C3_NmiTaskListBytes-1
    MVN !Bank7E,!BankD2                 ; lint-ok: MVN operands are bank bytes ($D2:0000 to $7E)
    RTS

; $7E:7F12 — C3Mod_Prog6ScrollXTask (35 bytes, $7F12–$7F34)
; A task (entry 3 of C3Mod_Prog6TableA), DP = $0A00 (PEA / PLD): var 1
; (C3_Prog6ScrollX) + var 8 (C3_Prog6ScrollStep) with the carry the
; task came in with (no CLC: 0 from C3Mod_TaskNext's CPX, the task
; not being first in the list), kept in 0-$3FF: from $400 up (signed:
; CMP / BMI) - $400 (SBC with C=1 from the CMP), below 0 (CMP #0 /
; BPL) + $401 (the CMP #0 sets C, so ADC adds one more: a quirk); var
; 3 (M7X) = var 1 + $80 (CLC).
; Callers note: a task: entry 3 of C3Mod_Prog6TableA (installed by
;   C3Mod_Prog6TasksA's MVN).
; Entry: a task: M=0, X any, DP any (set here; restored by
;        C3Mod_RunTasks), DB any; C = 0 (see above).
; Exit:  M=0, DP = $0A00; A = var 3; X, Y unchanged.
C3Mod_Prog6ScrollXTask:
    PEA.w !C3_ScriptPageA
    PLD
    LDA.b !C3_Prog6ScrollX
    ADC.b !C3_Prog6ScrollStep
    CMP.w #!C3_Prog6ScrollWrap
    BMI .low
    SBC.w #!C3_Prog6ScrollWrap
    BRA .store
.low:
    CMP.w #0
    BPL .store
    ADC.w #!C3_Prog6ScrollWrap          ; C = 1 from the CMP: + $401
.store:
    STA.b !C3_Prog6ScrollX
    CLC
    ADC.w #!C3_Prog6M7Centre
    STA.b !C3_Prog6M7X
    RTS

; $7E:7F35 — C3Mod_Prog6ScrollYTask (35 bytes, $7F35–$7F57)
; As C3Mod_Prog6ScrollXTask for var 2 (C3_Prog6ScrollY; entry 5 of
; C3Mod_Prog6TableB, C = 0 the same way), the same wrap and quirk;
; var 4 (M7Y) = var 2 - $81 (CLC / SBC #$80: one more off).
; Callers note: a task: entry 5 of C3Mod_Prog6TableB (installed by
;   C3Mod_Prog6TasksB's MVN).
; Entry: a task: M=0, X any, DP any (set here), DB any; C = 0.
; Exit:  M=0, DP = $0A00; A = var 4; X, Y unchanged.
C3Mod_Prog6ScrollYTask:
    PEA.w !C3_ScriptPageA
    PLD
    LDA.b !C3_Prog6ScrollY
    ADC.b !C3_Prog6ScrollStep
    CMP.w #!C3_Prog6ScrollWrap
    BMI .low
    SBC.w #!C3_Prog6ScrollWrap
    BRA .store
.low:
    CMP.w #0
    BPL .store
    ADC.w #!C3_Prog6ScrollWrap          ; C = 1 from the CMP: + $401
.store:
    STA.b !C3_Prog6ScrollY
    CLC
    SBC.w #!C3_Prog6M7Centre            ; C = 0: - $81
    STA.b !C3_Prog6M7Y
    RTS

; $7E:7F58 — C3Mod_Prog6StripNmi (37 bytes, $7F58–$7F7C)
; An NMI task: the mode-1 strip's place in C3Mod_Prog6HdmaB's tables,
; with DB = $7E (PHK / PLB), 8-bit from C3_Prog6Horizon h (dp, low
; byte): .strip + 2 (BG1VOFS's low byte) = $FF - h (SEC); the third
; counts of C3Mod_Prog6ModeB, C3Mod_Prog6ScrollB and C3Mod_Prog6MathB
; = h - $A7 (SEC; h is $A8-$AB, so 1-4 lines: mode 7 down to line h -
; 1); then .strip's word (BG1HOFS) = $100 - page $0B00's var 1 (a long
; read), the SBC's borrow from h - $A7 (C = 1: none, as h >= $A8).
; Callers note: an NMI task added by script opcode $F8 at $7C85
;   (C3Mod_Prog6Script), $7DD9 and $7E93 (C3Mod_Prog6ScriptB); removed
;   by $F7 at $7D23 and $7DEC (C3Mod_Prog6ScriptB).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X any, DP=0
;        (C3_Prog6Horizon), DB any (set here; restored by
;        C3Mod_RunNmiTasks).
; Exit:  M=0, DB = $7E; A = the BG1HOFS word; X, Y unchanged.
C3Mod_Prog6StripNmi:
    PHK
    PLB
    LDA.b #!Eng_Invert8
    SEC
    SBC.b !C3_Prog6Horizon
    STA.w C3Mod_Prog6ScrollB_strip+2
    LDA.b !C3_Prog6Horizon
    SEC
    SBC.b #!C3_Prog6PlaneLines
    STA.w C3Mod_Prog6ModeB_count
    STA.w C3Mod_Prog6ScrollB_count
    STA.w C3Mod_Prog6MathB_count
    REP #$20
    LDA.w #!C3_Prog6StripHofs
    SBC.l !C3_ScriptPageB+!C3_Prog6SprX
    STA.w C3Mod_Prog6ScrollB_strip
    RTS

; $7E:7F7D — C3Mod_Prog6HorizonTask (71 bytes, $7F7D–$7FC3)
; A task (entry 2 of C3Mod_Prog6TableB; C = 0 from C3Mod_TaskNext's
; CPX): three sprite rows along the horizon.
;   - C3_SprBaseX = page $0B00's var 1 + $80 (+ C = 0);
;   - C3_Prog6Horizon = page $0B00's var 5 = (C3Mod_KernelRandom at
;     M=0, a word, AND C3_Prog6HorizonMask's word: the mask byte 0, 1
;     or 3 and $4B's byte, 0 from C3Mod_Init) + $A8 (CLC); the line
;     where C3Mod_Prog6StripNmi starts the mode-1 strip;
;   - C3_SprBaseY = the horizon - $28 (SEC): C3Mod_Prog6RowA
;     (C3Mod_SprListMixed); C3_SprBaseY = the horizon + (another
;     random word AND 1) + $12, the ADCs taking C3Mod_KernelRandom's
;     carry (its last SBC's) and then the first ADC's:
;     C3Mod_Prog6RowC; C3_SprBaseY = the horizon - $28 again:
;     C3Mod_Prog6RowB.
; Callers note: a task: entry 2 of C3Mod_Prog6TableB (installed by
;   C3Mod_Prog6TasksB's MVN).
; Entry: a task: M=0, X=0 (C3Mod_SprListMixed's 16-bit Y), DP=0
;        (C3_SprBase*, C3_Prog6Horizon), DB=$00 (C3_RandomByte's
;        counters and C3Mod_SprListMixed's ports are absolute); C = 0.
; Exit:  M=0, X=0; as the last C3Mod_SprListMixed: Y = C3_OamPos, A
;        changed.
; Calls: C3Mod_KernelRandom, C3Mod_SprListMixed (JSL).
C3Mod_Prog6HorizonTask:
    LDA.w !C3_ScriptPageB+!C3_Prog6SprX
    ADC.w #!C3_Prog6RowsX
    STA.b !C3_SprBaseX
    JSR C3Mod_KernelRandom
    AND.b !C3_Prog6HorizonMask
    CLC
    ADC.w #!C3_Prog6HorizonStart
    STA.b !C3_Prog6Horizon
    STA.w !C3_ScriptPageB+!C3_Prog6SprVar5
    SEC
    SBC.w #!C3_Prog6RowsAbove
    STA.b !C3_SprBaseY
    LDA.w #C3Mod_Prog6RowA
    JSL C3Mod_SprListMixed
    JSR C3Mod_KernelRandom
    AND.w #1
    ADC.b !C3_Prog6Horizon
    ADC.w #!C3_Prog6RowsBelow
    STA.b !C3_SprBaseY
    LDA.w #C3Mod_Prog6RowC
    JSL C3Mod_SprListMixed
    LDA.b !C3_Prog6Horizon
    SEC
    SBC.w #!C3_Prog6RowsAbove
    STA.b !C3_SprBaseY
    LDA.w #C3Mod_Prog6RowB
    JSL C3Mod_SprListMixed
    RTS

; $7E:7FC4 — C3Mod_Prog6RadiusTask (7 bytes, $7FC4–$7FCA)
; A task: page $0B00's var 6 (C3_Prog6CircleR) = C3_Prog6Radius
; (C3Mod_Prog6Sprites' value, $0B38).
; Callers note: a task added by script opcode $FA at $7D2C, removed by
;   $F9 at $7D92 (C3Mod_Prog6ScriptB).
; Entry: a task: M=0, X any, DP any, DB=$00 (page $0B00 is absolute).
; Exit:  M=0; A = the radius; X, Y unchanged.
C3Mod_Prog6RadiusTask:
    LDA.w !C3_Prog6Radius
    STA.w !C3_ScriptPageB+!C3_Prog6CircleR
    RTS

; $7E:7FCB — C3Mod_Prog6CircleTask (84 bytes, $7FCB–$801E)
; A task: window 1's circle and the colour math beside it, DP = $0B00
; (PEA / PLD), r = var 6's low byte (C3_Prog6CircleR):
;   - WinFx_ArgSize = WinFx_ArgX = WinFx_ArgY = r; WinFx_BuildCircle
;     with A = $80 (WinFx_CircKeepRest, mode 0: a full circle, the
;     rows outside it left as they were) into WinFx_TablePtr's $7E:E060
;     (C3_Prog6CircleTable, set by C3Mod_Prog6Setup), centred on line r;
;   - with DB = $7E (PHK / PLB), 8-bit: C3Mod_Prog6WindowA's and
;     C3Mod_Prog6MathA's first counts = var 2 - 1 - r (CLC / SBC: the
;     line above the circle's top); C3Mod_Prog6MathA's .inside count =
;     2r and C3Mod_Prog6WindowA's .circle count = 2r + $80 (repeat):
;     right for r up to $3F;
;   - 16-bit: for the rows 0 to 2r + 1 ((r + 1) x 2 words, X + 2,
;     DEY / BNE; BEQ skips a count of 0, which var 6 never gives), the
;     left edge (the table word's low byte) + var 1 (the ADC with no CLC
;     takes the carry of
;     the ASL before the loop, 0, then of the ADC of the row before:
;     set when var 1 is negative and the sum is not, so one more
;     there), 0 if negative (BPL), with right edge $FF (ORA $FF00), to
;     C3_Prog6CircleCopy ($7E:E0E0, row 64 of the same table on): what
;     C3Mod_Prog6WindowA's .circle sends, a window from the circle's
;     left edge to the screen's right.
; Table overruns of the original: with the table at an even address
; WinFx_BuildCircle's first pass writes row r - r - 1 = -1 (its quirk),
; the word at $7E:E05E-$E05F just before C3_Prog6CircleTable (not read
; by anything in program 6: the ramp at $E030 ends at $E04F); the
; copy's last row 2r + 1 is a row the circle does not write (it keeps
; what an earlier, larger circle left there). C3Mod_Prog6ScriptB keeps
; r from 1 to 24 (var 6 from C3Mod_Prog6RadiusTask: $400 / var 0 + 4,
; var 0 between $31 and $91; then counted down to 1), so the mirror
; (rows r to 2r) stays below row 49 and the copy never meets its own
; destination (rows 64 on); a radius of 0 (which would empty the
; whole table, $1C3 bytes from $E060: 3 past it) is never reached.
; Callers note: a task added by script opcode $FA at $7D2F, removed by
;   $F9 at $7DAB (C3Mod_Prog6ScriptB).
; Entry: a task: M=0 (8-bit set here), X=0 (16-bit loop index), DP any
;        (set here), DB=$00 (the WinFx_* block is absolute; set to $7E
;        after the call).
; Exit:  M=0, X=0, DP = $0B00, DB = $7E; A = the last word stored; X
;        = 4 x (var 6 + 1), Y = 0 (var 6 16-bit; the loop count is
;        (var 6 + 1) x 2).
; Calls: WinFx_BuildCircle (JSL).
C3Mod_Prog6CircleTask:
    SEP #$20
    PEA.w !C3_ScriptPageB
    PLD
    LDA.b !C3_Prog6CircleR
    STA.w !WinFx_ArgSize
    STA.w !WinFx_ArgX
    STA.w !WinFx_ArgY
    LDA.b #!WinFx_CircKeepRest
    JSL !WinFx_BuildCircle
    PHK
    PLB
    LDA.b !C3_Prog6SprY
    CLC
    SBC.b !C3_Prog6CircleR
    STA.w C3Mod_Prog6WindowA
    STA.w C3Mod_Prog6MathA
    LDA.b !C3_Prog6CircleR
    ASL A
    STA.w C3Mod_Prog6MathA_inside
    ORA.b #!C3_HdmaRepeat
    STA.w C3Mod_Prog6WindowA_circle
    REP #$20
    LDA.b !C3_Prog6CircleR
    INC A
    ASL A
    BEQ .done
    TAY
    LDX.w #0
.row:
    LDA.w !C3_Prog6CircleTable,X
    AND.w #!Eng_LowByteMask
    ADC.b !C3_Prog6SprX
    BPL .keep
    LDA.w #0
.keep:
    ORA.w #!C3_Prog6RightEdge
    STA.w !C3_Prog6CircleCopy,X
    INX
    INX
    DEY
    BNE .row
.done:
    RTS

; $7E:801F — C3Mod_Prog6StreamSetup (35 bytes, $801F–$8041)
; C3Mod_BuildM7Tables' setup routine for C3Mod_Prog6StreamNmi's plane
; (its .setup JSR, the operand written there): .end's CPY operand =
; $0318 (line 198; a store into C3Mod_BuildM7Tables, DB = $7E), Y =
; $0068 (line 26 first); WMADD = $7E:E260 (C3_Prog6Distances: a 16-bit
; long store to WMADDL/M, then WMADDH), X = its first byte (WMDATA,
; AND $FF); the .stream_x step takes the next byte for each line.
; Callers note: the patched JSR at $35FC (C3Mod_BuildM7Tables' .setup,
;   written by C3Mod_Prog6StreamNmi at $7A17).
; Entry: M=0, X=0, DP any, DB = $7E (C3Mod_BuildM7Tables' PHK / PLB:
;        the .end store is absolute).
; Exit:  M=0, X=0; X = the first distance, Y = $0068; A = X.
C3Mod_Prog6StreamSetup:
    LDA.w #!C3_Prog6StreamEnd
    STA.w C3Mod_BuildM7Tables_end+1
    LDY.w #!C3_Prog6StreamFirst
    LDA.w #!C3_Prog6Distances
    STA.l WMADDL                        ; and WMADDM
    SEP #$20
    LDA.b #!Bank7E
    STA.l WMADDH
    LDA.l WMDATA
    REP #$20
    AND.w #!Eng_LowByteMask
    TAX
    RTS

; $7E:8042 — C3Mod_Prog6HalfSetup (55 bytes, $8042–$8078)
; C3Mod_BuildM7Tables' setup routine for C3Mod_Prog6HalfNmi's plane:
; half of it a call, in turn by C3_Prog6Half (a word at $0044, + 1
; each call; BIT #1 / BEQ):
;   - odd: .step = DEX / DEX ($CACA, self-modifying), C3_Prog6Rebuild
;     (page $0A00's var 7, dp) + 1, so the next C3Mod_Prog6PlaneTask
;     (the second entry of C3Mod_Prog6TableB, the same frame) builds
;     again; .end = $01C0; X = $FF, Y = 0: lines 0-111 with
;     the divisor from $FF down by 2;
;   - even: .step = INX / INX ($E8E8); .end = C3_Prog6Horizon x 4 (a
;     long word read, two ASLs); X = $20, Y = $0200: lines 128 to the
;     horizon - 1 with the divisor from $20 up by 2.
; Lines 112-127 are left as the last build put them.
; Callers note: the patched JSR at $35FC (C3Mod_BuildM7Tables' .setup,
;   written by C3Mod_Prog6HalfNmi at $7A3A).
; Entry: M=0, X=0, DP = $0A00 (C3Mod_BuildM7Tables' caller's:
;        C3_Prog6Rebuild is direct page), DB = $7E (the code stores and
;        C3_Prog6Half are absolute: $7E:0044 is $00:0044's WRAM).
; Exit:  M=0, X=0; X and Y as above; A = the .end value.
C3Mod_Prog6HalfSetup:
    LDA.w !C3_Prog6Half
    INC A
    STA.w !C3_Prog6Half
    BIT.w #1
    BEQ .even
    LDA.w #!Op_DEX|(!Op_DEX<<8)
    STA.w C3Mod_BuildM7Tables_step
    INC.b !C3_Prog6Rebuild
    LDA.w #!C3_Prog6TopEnd
    STA.w C3Mod_BuildM7Tables_end+1
    LDX.w #!C3_Prog6TopFirstX
    LDY.w #0
    RTS
.even:
    LDA.w #!Op_INX|(!Op_INX<<8)
    STA.w C3Mod_BuildM7Tables_step
    LDA.l !C3_Prog6Horizon
    ASL A
    ASL A
    STA.w C3Mod_BuildM7Tables_end+1
    LDX.w #!C3_Prog6LowFirstX
    LDY.w #!C3_Prog6LowFirst
    RTS

; $7E:8079 — C3Mod_Prog6ShuffleTask (45 bytes, $8079–$80A5)
; A task: new pieces for C3Mod_Prog6RowA, with DB = $7E (PHK / PLB;
; the lists are absolute): its records 0 and 1 get a tile and
; attribute word each from C3Mod_Prog6TileWords (C3Mod_Prog6RandomWord,
; 16-bit stores over the records' first two bytes); then, through
; WMDATA from $7E:8112 (WMADDL/M by a 16-bit long store, WMADDH = $7E;
; A = 0 first, so B = 0 for the TAXes below), records 2-5: two
; C3Mod_Prog6RandomPair calls, the first with X + $38 (C3_TmpF0, 8-bit)
; and the second (falling in) with X + $C0.
; Quirk: with DB = $7E C3_RandomByte's counter reads (SLHV $2137, OPHCT
; $213C, OPVCT $213D, absolute) read WRAM ($7E:2137-$213E: bytes of
; C3_PaletteWork's colours $9B-$9F) instead of the PPU's H and V
; counters, so the bytes are random only through C3_RandSeed, X,
; C3_FrameCount and C3_ScratchF0 / F2 / F4.
; Callers note: a task added by script opcode $FA at $7DD3 and $7E8D
;   (C3Mod_Prog6ScriptB).
; Entry: a task: M=0, X=0 (16-bit index; TAX at M=1 takes B too), DP=0
;        (C3_TmpF0; C3_ScratchF0 is written absolute), DB any (set
;        here; restored by C3Mod_RunTasks).
; Exit:  M=1, X=0, DB = $7E; as the last C3Mod_Prog6RandomPair: X =
;        the group + 8, A = its last byte; Y unchanged.
; Calls: C3Mod_Prog6RandomWord, C3Mod_Prog6RandomPair.
C3Mod_Prog6ShuffleTask:
    PHK
    PLB
    REP #$20
    JSR C3Mod_Prog6RandomWord
    STA.w C3Mod_Prog6RowA+1
    JSR C3Mod_Prog6RandomWord
    STA.w C3Mod_Prog6RowA+5
    LDA.w #C3Mod_Prog6RowA+9
    STA.l WMADDL                        ; and WMADDM
    LDA.w #0
    SEP #$20
    LDA.b #!Bank7E
    STA.l WMADDH
    LDA.b #!C3_Prog6PairX1
    STA.b !C3_TmpF0
    JSR C3Mod_Prog6RandomPair
    LDA.b #!C3_Prog6PairX2
    STA.b !C3_TmpF0                     ; and it falls into C3Mod_Prog6RandomPair

; $7E:80A6 — C3Mod_Prog6RandomPair (9 bytes, $80A6–$80AE)
; Two sprite records through WMDATA from one of C3Mod_Prog6Parts' four
; groups: X = C3Mod_KernelRandom AND $18 (8-bit; with B = 0, the TAX
; gives 0, 8, $10 or $18), then C3Mod_Prog6PartRecord twice (the
; second falls in).
; Callers note: C3Mod_Prog6ShuffleTask ($809F; the second call falls
;   in).
; Entry: M=1, X=0, DP=0 (C3_TmpF0, for C3Mod_Prog6PartRecord), DB =
;        $7E (the table; C3_RandomByte's reads: see
;        C3Mod_Prog6ShuffleTask); B = 0; C3_TmpF0 = the X offset.
; Exit:  M=1; X = the group + 8; A = the second record's last byte; Y
;        unchanged.
; Calls: C3Mod_KernelRandom, C3Mod_Prog6PartRecord.
C3Mod_Prog6RandomPair:
    JSR C3Mod_KernelRandom
    AND.b #!C3_Prog6GroupMask
    TAX
    JSR C3Mod_Prog6PartRecord           ; and it falls into the second

; $7E:80AF — C3Mod_Prog6PartRecord (36 bytes, $80AF–$80D2)
; One record (tile, attribute, X, Y) from C3Mod_Prog6Parts + X to
; WMDATA (long stores), the X byte + C3_TmpF0 (CLC); X + 4.
; Callers note: C3Mod_Prog6RandomPair ($80AC; the second falls in).
; Entry: M=1, X=0 (16-bit index), DP = the page of C3_TmpF0 (0), DB =
;        $7E (the table is absolute); WMADD set.
; Exit:  M=1; X + 4; A = the record's Y byte; Y unchanged.
C3Mod_Prog6PartRecord:
    LDA.w C3Mod_Prog6Parts,X
    STA.l WMDATA
    INX
    LDA.w C3Mod_Prog6Parts,X
    STA.l WMDATA
    INX
    LDA.w C3Mod_Prog6Parts,X
    CLC
    ADC.b !C3_TmpF0
    STA.l WMDATA
    INX
    LDA.w C3Mod_Prog6Parts,X
    STA.l WMDATA
    INX
    RTS

; $7E:80D3 — C3Mod_Prog6RandomWord (14 bytes, $80D3–$80E0)
; A = one of C3Mod_Prog6TileWords' four words (C3Mod_KernelRandom at
; M=0, AND 6), also kept in C3_ScratchF0 (absolute: $7E:00F0 with DB =
; $7E, the same WRAM).
; Callers note: C3Mod_Prog6ShuffleTask ($807D, $8083).
; Entry: M=0, X=0, DP any, DB = $7E (the table is absolute;
;        C3_RandomByte's reads: see C3Mod_Prog6ShuffleTask).
; Exit:  M=0; A = the word, X = its offset (0-6); Y unchanged.
; Calls: C3Mod_KernelRandom.
C3Mod_Prog6RandomWord:
    JSR C3Mod_KernelRandom
    AND.w #!C3_Prog6WordMask
    TAX
    LDA.w C3Mod_Prog6TileWords,X
    STA.w !C3_ScratchF0
    RTS

; $7E:80E1 — C3Mod_Prog6TileWords (8 bytes, $80E1–$80E8)
; Tile and attribute words for C3Mod_Prog6RowA's records 0 and 1.
C3Mod_Prog6TileWords:
    dw $7446, $3444, $3446, $3448

; $7E:80E9 — C3Mod_Prog6Parts (32 bytes, $80E9–$8108)
; Four groups of two sprite records (tile, attribute, X, Y) for
; C3Mod_Prog6RowA's records 2-5 (C3Mod_Prog6RandomPair).
C3Mod_Prog6Parts:
    db $41, $24, $00, $40
    db $4A, $24, $00, $38
    db $42, $24, $00, $40
    db $4B, $24, $00, $38
    db $43, $24, $00, $40
    db $4C, $24, $00, $38
    db $64, $24, $00, $40
    db $65, $24, $08, $40

; $7E:8109 — C3Mod_Prog6RowA (25 bytes, $8109–$8121)
; A C3Mod_SprListMixed list (n + 1, then n records of tile, attribute,
; X, Y; X and Y signed from C3_SprBaseX / Y): 6 sprites under the
; horizon h: C3Mod_Prog6HorizonTask's base Y is h - $28 and the Y
; bytes $38 / $40, so they sit at h + $10 and h + $18, in the mode-1
; strip. C3Mod_Prog6ShuffleTask rewrites records 0 and 1's tile and
; attribute words and records 2-5 whole (with the same Y bytes, from
; C3Mod_Prog6Parts).
C3Mod_Prog6RowA:
    db 7        ; 6 sprites
    db $46, $34, $A0, $38
    db $46, $34, $50, $38
    db $42, $24, $38, $40
    db $4B, $24, $38, $38
    db $43, $24, $C0, $40
    db $4C, $24, $C0, $38

; $7E:8122 — C3Mod_Prog6RowB (121 bytes, $8122–$819A)
; Its list of 30 sprites above the horizon (C3Mod_Prog6HorizonTask).
C3Mod_Prog6RowB:
    db 31        ; 30 sprites
    db $4D, $24, $E8, $00
    db $4E, $24, $F0, $00
    db $4F, $24, $F8, $00
    db $4F, $64, $00, $00
    db $4E, $64, $08, $00
    db $4D, $64, $10, $00
    db $5A, $36, $D0, $08
    db $5C, $36, $E0, $08
    db $5E, $36, $F0, $08
    db $5E, $76, $00, $08
    db $5C, $76, $10, $08
    db $5A, $76, $20, $08
    db $68, $24, $C0, $10
    db $69, $24, $C8, $10
    db $69, $64, $30, $10
    db $68, $64, $38, $10
    db $7F, $24, $F8, $18
    db $75, $36, $A8, $18
    db $77, $34, $B8, $18
    db $79, $36, $C8, $18
    db $7B, $36, $D8, $18
    db $7D, $36, $E8, $18
    db $7F, $64, $00, $18
    db $7D, $76, $08, $18
    db $7B, $76, $18, $18
    db $79, $76, $28, $18
    db $77, $74, $38, $18
    db $75, $76, $48, $18
    db $8F, $24, $F8, $20
    db $8F, $64, $00, $20

; $7E:819B — C3Mod_Prog6RowC (41 bytes, $819B–$81C3)
; Its list of 10 sprites, on a base Y of h + $12 to h + $14
; (C3Mod_Prog6HorizonTask: a random bit and C3Mod_KernelRandom's
; carry): records 0-3 (large, Y byte $F8: -8) at h + $A to h + $C and
; records 4-5 (small, $F0) at h + 2 to h + 4, under the horizon;
; records 6-9 (large, $E8 and $E0: -$18 and -$20) at h - 6 to h - 4
; and h - $E to h - $C, across the horizon line.
C3Mod_Prog6RowC:
    db 11        ; 10 sprites
    db $70, $30, $E0, $F8
    db $70, $70, $10, $F8
    db $72, $30, $F0, $F8
    db $72, $70, $00, $F8
    db $40, $20, $E0, $F0
    db $40, $60, $18, $F0
    db $52, $30, $F0, $E8
    db $52, $70, $00, $E8
    db $50, $30, $E0, $E0
    db $50, $70, $10, $E0

; $7E:81C4 — C3Mod_Prog6ScrollNmi (45 bytes, $81C4–$81F0)
; An NMI task, DP = $0A00 (PEA / PLD): BG1HOFS = var 1, BG1VOFS = var
; 2, M7X = var 3, M7Y = var 4 (low byte, then high byte, each 8-bit).
; Callers note: an NMI task added by script opcode $F8 at $7C79
;   (C3Mod_Prog6Script).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X any, DP any (set here;
;        restored by C3Mod_RunNmiTasks), DB=$00 (the registers are
;        absolute).
; Exit:  M=1, DP = $0A00; A = var 4's high byte; X, Y unchanged.
C3Mod_Prog6ScrollNmi:
    PEA.w !C3_ScriptPageA
    PLD
    LDA.b !C3_Prog6ScrollX
    STA.w BG1HOFS
    LDA.b !C3_Prog6ScrollX+1
    STA.w BG1HOFS
    LDA.b !C3_Prog6ScrollY
    STA.w BG1VOFS
    LDA.b !C3_Prog6ScrollY+1
    STA.w BG1VOFS
    LDA.b !C3_Prog6M7X
    STA.w M7X
    LDA.b !C3_Prog6M7X+1
    STA.w M7X
    LDA.b !C3_Prog6M7Y
    STA.w M7Y
    LDA.b !C3_Prog6M7Y+1
    STA.w M7Y
    RTS

; $7E:81F1 — C3Mod_Prog6RiseTask (10 bytes, $81F1–$81FA)
; A task: page $0A00's var 2 (C3_Prog6ScrollY) + 3, with the carry it
; came in with (no CLC: 0 from C3Mod_TaskNext's CPX; it is added into
; entry 5, not the first).
; Callers note: a task added by script opcode $FA at $7DEF
;   (C3Mod_Prog6ScriptB).
; Entry: a task: M=0, X any, DP any, DB=$00 (page $0A00 is absolute);
;        C = 0.
; Exit:  M=0; A = the new var 2; X, Y unchanged.
C3Mod_Prog6RiseTask:
    LDA.w !C3_ScriptPageA+!C3_Prog6ScrollY
    ADC.w #!C3_Prog6RiseStep
    STA.w !C3_ScriptPageA+!C3_Prog6ScrollY
    RTS

; $7E:81FB — C3Mod_Prog6UnusedTask (10 bytes, $81FB–$8204)
; The same for page $0A00's var 4 (C3_Prog6M7Y): + $FFFD (- 3, + the
; carry: no CLC). No reference to $81FB was found (no task list,
; script or code names it): probably unused.
; Callers note: none found (no JSR, JMP, task-list word or script
;   operand names $81FB).
; Entry: never reached; written as a task: M=0, X any, DP any, DB=$00
;        (absolute).
; Exit:  M=0; A = the new var 4.
C3Mod_Prog6UnusedTask:
    LDA.w !C3_ScriptPageA+!C3_Prog6M7Y
    ADC.w #-!C3_Prog6RiseStep
    STA.w !C3_ScriptPageA+!C3_Prog6M7Y
    RTS

; $7E:8205 — C3Mod_Prog6Sprites (69 bytes, $8205–$8249)
; The scaled picture's sprites, from page $0B00's var 0 (s, its size:
; C3_Prog6SprSize):
;   - C3Math_B and C3Scale_YStep ($0027, the scale step of
;     C3Mod_Prog6ScaleIdle) = s; C3Mod_DivHighByte: q = $0400 / s
;     (C3Math_Lo; 0 when s is 0, as at C3Mod_Prog6's call);
;   - C3_SprBaseY = var 2 - q (SEC); C3_Prog6Radius = q + 3 + the
;     SBC's carry (no CLC: + 4 while var 2 >= q, as in the scripts);
;     C3_SprBaseX = var 1 + 4 + the carry of that ADC (0 here);
;   - the list C3Mod_Prog6SprList: its count byte (a long store) = 9 (8
;     sprites), or 5 (the first 4) when s's low byte is $80 or more
;     (8-bit CMP / BCC: unsigned); C3_SprListLarge.
; Callers note: C3Mod_Prog6 ($79CA); a task: entry 4 of
;   C3Mod_Prog6TableA (installed by C3Mod_Prog6TasksA's MVN), removed
;   by script opcode $F9 at $7DBB and $7DF2 (C3Mod_Prog6ScriptB).
; Entry: M=0, X=0 (C3_SprListLarge's), DP=0 (C3Math_*, C3_SprBase*,
;        C3Scale_YStep's $0027 is absolute), DB=$00 (page $0B00, and
;        C3_SprListLarge's ports and OAM shadow, are absolute).
; Exit:  M=0, X=0; as C3_SprListLarge leaves them: X = C3_OamHiPtr, Y =
;        C3_OamPos, A changed; C3Math_Lo = q, C3Math_A and C3Math_Q as
;        C3Mod_DivHighByte leaves them.
; Calls: C3Mod_DivHighByte, C3_SprListLarge (JSL).
C3Mod_Prog6Sprites:
    LDA.w !C3_ScriptPageB+!C3_Prog6SprSize
    STA.b !C3Math_B
    STA.w !C3Scale_YStep
    LDA.w #!C3_Prog6SprDividend
    JSR C3Mod_DivHighByte
    LDA.w !C3_ScriptPageB+!C3_Prog6SprY
    SEC
    SBC.b !C3Math_Lo
    STA.b !C3_SprBaseY
    LDA.b !C3Math_Lo
    ADC.w #!C3_Prog6RadiusAdd
    STA.w !C3_Prog6Radius
    LDA.w !C3_ScriptPageB+!C3_Prog6SprX
    ADC.w #!C3_Prog6SprXAdd
    STA.b !C3_SprBaseX
    SEP #$20
    LDA.b #!C3_Prog6SprAll
    STA.l C3Mod_Prog6SprList
    LDA.w !C3Scale_YStep
    CMP.b #!C3_Prog6SprBig
    BCC .list
    LDA.b #!C3_Prog6SprFour
    STA.l C3Mod_Prog6SprList
.list:
    REP #$20
    LDA.w #C3Mod_Prog6SprList
    JSL !C3_SprListLarge
    RTS

; $7E:824A — C3Mod_Prog6TilesNmiTask (46 bytes, $824A–$8277)
; An NMI task: when C3_Prog6TilesReady is set (8-bit LDA / BEQ), the
; $400 bytes at $00:0C00 (the scaled picture's tiles, C3_CopyCode's
; output) to VRAM word $4000 by DMA channel 7 (two registers from
; VMDATAL, VMAIN = $80), then C3_Prog6TilesReady's low byte = 0.
; Callers note: an NMI task added by script opcode $F8 at $7C7C
;   (C3Mod_Prog6Script).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X=0 (the 16-bit register
;        pairs), DP=0 (C3_Prog6TilesReady), DB=$00 (the registers).
; Exit:  M=1, X=0; sent: A = $80 (VMAIN and MDMAEN), X = $0C00, Y =
;        $0400; else A = 0, X and Y unchanged.
C3Mod_Prog6TilesNmiTask:
    LDA.b !C3_Prog6TilesReady
    BEQ .done
    LDX.w #!C3_SprTilesVram
    STX.w VMADDL
    LDY.w #!C3_Prog6TileBytes
    STY.w DAS7L
    LDA.b #!DMAP_TwoRegs
    STA.w DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD7
    LDX.w #!C3_CopyCodeDest
    STX.w A1T7L
    STZ.w A1B7
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    STA.w MDMAEN                        ; MDMAEN_Ch7, the same value
    STZ.b !C3_Prog6TilesReady
.done:
    RTS

; $7E:8278 — C3Mod_Prog6ScaleIdle (56 bytes, $8278–$82AF)
; The idle routine C3Mod_Prog6 writes over C3Mod_Start's idle call:
; unless C3_Prog6TilesReady is set (16-bit LDA / BNE: the last tiles
; not sent yet), with DB = $7F (PEA $007F / PLB; the $00 stays for the
; last PLB): C3_ScaleBitmap with C3Scale_SrcBase = $0A00 (pack 40's
; bitmap), C3Scale_Dest = C3Scale_DestPos = $0200, C3Scale_XStep =
; C3Scale_YStep x 2 (C3Mod_Prog6Sprites' size), C3Scale_Rows = $21 (32
; rows), C3Scale_Groups = 4 (64 pixels), C3Scale_SrcLimit = $0400 (16
; source rows), entered with C = 0 (the ASL of the step); then the
; generated copy code (C3_CopyCode, $B574: the bitmap at $7F:0200 as
; 4bpp tiles at $0C00 on), DP kept around it; DB = $00 (PLB);
; C3_Prog6TilesReady = 1.
; Overrun of the original: C3Mod_Prog6Setup leaves C3Scale_PrevEnd =
; $0A00, so the first picture's closing clear (C3_ScaleBitmap: from
; its end, $0600 when the 32 rows run out, through the old end, C=0)
; zeroes $7F:0600-$0A00, the last byte of that being the first pixel
; of pack 40's bitmap at $7F:0A00 (the source it scales); later
; clears stay inside $0200-$0601 (the old ends are $0600 or less, one
; byte more when the source ran out first).
; Callers note: the patched JSR at $3023 (C3Mod_Start's idle call,
;   written by C3Mod_Prog6 at $79B7); C3Mod_Prog6 ($79CD).
; Entry: M=0, X=0 (16-bit), DP=0 (C3Scale_*, C3_Prog6TilesReady), DB=$00,
;        as C3Mod_Start's loop runs (and C3Mod_Prog6's call).
; Exit:  M=0, X=0, DP=0, DB=$00; A = 1 after a picture, else the flag
;        (not 0); X, Y as the copy code leaves them, or unchanged.
; Calls: C3_ScaleBitmap (JSL), the generated code at $B574.
C3Mod_Prog6ScaleIdle:
    LDA.b !C3_Prog6TilesReady
    BNE .done
    PEA.w !Bank7F                       ; PLB takes the $7F; the $00 stays for the last PLB
    PLB
    LDA.w #!C3_Prog6ScaleSrc
    STA.b !C3Scale_SrcBase
    LDX.w #!C3_BitmapSrc
    STX.b !C3Scale_Dest
    STX.b !C3Scale_DestPos
    LDA.b !C3Scale_YStep
    ASL A
    STA.b !C3Scale_XStep
    LDA.w #!C3_Prog6ScaleRows
    STA.b !C3Scale_Rows
    LDA.w #!C3_Prog6ScaleGroups
    STA.b !C3Scale_Groups
    LDA.w #!C3_Prog6ScaleLimit
    STA.b !C3Scale_SrcLimit
    JSL !C3_ScaleBitmap
    PHD
    JSR !C3_CopyCodeAddr
    PLD
    PLB
    LDA.w #1
    STA.b !C3_Prog6TilesReady
.done:
    RTS

; $7E:82B0 — C3Mod_Prog6SprList (33 bytes, $82B0–$82D0)
; C3_SprListLarge's list for C3Mod_Prog6Sprites: a count byte n + 1
; (9; C3Mod_Prog6Sprites writes 9 or 5), then tile, attribute, X, Y of
; 8 large sprites: tiles 0-$0E of the scaled picture's tiles (VRAM word
; $4000), a 64 x 32 block in two 32 x 32 halves (the first four make
; the left half).
C3Mod_Prog6SprList:
    db 9
    db $00, $32, $00, $00
    db $02, $32, $10, $00
    db $08, $32, $00, $10
    db $0A, $32, $10, $10
    db $04, $32, $20, $00
    db $06, $32, $30, $00
    db $0C, $32, $20, $10
    db $0E, $32, $30, $10

; $7E:82D1 — C3Mod_Prog6PlaneTask (36 bytes, $82D1–$82F4)
; A task, DP = $0A00 (LDA / TCD): when var 0 (the scale), var 5 (the
; angle) or var 7 (C3_Prog6Rebuild) differs from the copy kept at $30,
; $32 or $34 of the page (16-bit CMP / BNE, checked in that order),
; that copy and the ones after it are stored and C3Mod_BuildM7Tables
; runs (JMP: a tail call); else RTS.
; Callers note: a task: entry 0 of C3Mod_Prog6TableA and entries 0 and
;   1 of C3Mod_Prog6TableB (installed by the MVNs of
;   C3Mod_Prog6TasksA / TasksB).
; Entry: a task: M=0, X=0 (C3Mod_BuildM7Tables'), DP any (set here),
;        DB any (C3Mod_BuildM7Tables sets $7E).
; Exit:  M=0, X=0; unchanged: DP = $0A00, A = var 7; built: as
;        C3Mod_BuildM7Tables leaves them (DP = DP_CPU, DB = $7E;
;        C3Mod_RunTasks restores both).
C3Mod_Prog6PlaneTask:
    LDA.w #!C3_ScriptPageA
    TCD
    LDA.b !C3_M7Scale
    CMP.b !C3_Prog6BuiltScale
    BNE .scale
    LDA.b !C3_M7Angle
    CMP.b !C3_Prog6BuiltAngle
    BNE .angle
    LDA.b !C3_Prog6Rebuild
    CMP.b !C3_Prog6BuiltRebuild
    BNE .rebuild
    RTS
.scale:
    STA.b !C3_Prog6BuiltScale
    LDA.b !C3_M7Angle
.angle:
    STA.b !C3_Prog6BuiltAngle
    LDA.b !C3_Prog6Rebuild
.rebuild:
    STA.b !C3_Prog6BuiltRebuild
    JMP C3Mod_BuildM7Tables

; $7E:82F5 — C3Mod_Prog6PalIn (42 bytes, $82F5–$831E)
; A script routine (opcode $F0): FieldAnimB record 0 as a palette
; animation of kind 4 (.Unk0 = $40) on colours $20-$3F (.Unk1 = $20,
; .Unk2 = $20 colours), .Unk3 = 1, .Unk4 = 0, .Unk5 = 1, .Unk6 = 0,
; level .Unk7 = $FF, target .Unk8 = 0 (16-bit stores of byte pairs),
; with DB = $00 (PEA $7E00 / PLB: the $00; the $7E stays for the
; second PLB); then one C3Mod_PalAnimTask run at once, with DB = $7E
; and DP = $0B00 (the script's): its WRMPYA "save" reads and writes
; WRAM at $7E:4202 instead of the ports, its C3_ScratchF0 is page
; $0B00's $F0, and PalAnim_TickAll's DB is $00 (it takes DP's low
; byte: TDC / PHA at M=1 / PLB).
; Callers note: script opcode $F0 at $7CFC (C3Mod_Prog6ScriptB).
; Entry: M=0 (8-bit set here), X=0, DP = $0B00, DB = $7E (as
;        C3_RunScript calls opcode 0's routines).
; Exit:  M=0, X=0, DB = $7E; A, Y as PalAnim_TickAll leaves them, X =
;        what C3Mod_PalAnimTask read back.
; Calls: C3Mod_PalAnimTask.
C3Mod_Prog6PalIn:
    SEP #$20
    PEA.w !Bank7E<<8                    ; PLB takes the $00; the $7E stays for the second PLB
    PLB
    LDA.b #!C3_Prog6PalKind
    STA.w FieldAnimB.Unk0
    LDX.w #!C3_Prog6PalInColours
    STX.w FieldAnimB.Unk1               ; and .Unk2
    LDX.w #1
    STX.w FieldAnimB.Unk3               ; and .Unk4
    LDX.w #1
    STX.w FieldAnimB.Unk5               ; and .Unk6
    LDX.w #!C3_Prog6PalInLevel
    STX.w FieldAnimB.Unk7               ; and .Unk8
    PLB
    JSR C3Mod_PalAnimTask
    REP #$20
    RTS

; $7E:831F — C3Mod_Prog6PalOut (60 bytes, $831F–$835A)
; A script routine (opcode $F0), the same way for FieldAnimB records 0
; and 1: kind 4 both; record 0 on colours $80-$BF (.Unk1 = $80, .Unk2 =
; $40), record 1 on $50-$7F ($50, $30); both .Unk3 = 8, .Unk4 = 0,
; .Unk5 = 1, .Unk6 = 0, level .Unk7 = 0, target .Unk8 = $FF; then one
; C3Mod_PalAnimTask run (DB = $7E, DP = $0B00 as in C3Mod_Prog6PalIn).
; Callers note: script opcode $F0 at $7EB9 (C3Mod_Prog6ScriptB).
; Entry: as C3Mod_Prog6PalIn's.
; Exit:  as C3Mod_Prog6PalIn's.
; Calls: C3Mod_PalAnimTask.
C3Mod_Prog6PalOut:
    SEP #$20
    PEA.w !Bank7E<<8                    ; PLB takes the $00; the $7E stays for the second PLB
    PLB
    LDA.b #!C3_Prog6PalKind
    STA.w FieldAnimB.Unk0
    STA.w FieldAnimB.Unk0+!FieldAnimB_Bytes
    LDX.w #!C3_Prog6PalOutColours0
    STX.w FieldAnimB.Unk1               ; and .Unk2
    LDX.w #!C3_Prog6PalOutColours1
    STX.w FieldAnimB.Unk1+!FieldAnimB_Bytes
    LDX.w #!C3_Prog6PalOutStep
    STX.w FieldAnimB.Unk3               ; and .Unk4
    STX.w FieldAnimB.Unk3+!FieldAnimB_Bytes
    LDX.w #1
    STX.w FieldAnimB.Unk5               ; and .Unk6
    STX.w FieldAnimB.Unk5+!FieldAnimB_Bytes
    LDX.w #!C3_Prog6PalOutLevel
    STX.w FieldAnimB.Unk7               ; and .Unk8
    STX.w FieldAnimB.Unk7+!FieldAnimB_Bytes
    PLB
    JSR C3Mod_PalAnimTask
    REP #$20
    RTS

; $7E:835B — C3Mod_Prog6AnimTask (48 bytes, $835B–$838A)
; A task: an animated sprite group, with DB = $7E (PEA $007E / PLB; the
; $00 stays for the PLB before the JSL): C3_Prog6AnimTime - 1 (16-bit
; DEC); at 0 (BNE) the next entry of C3Mod_Prog6Anims (C3_Prog6AnimPtr
; + 2, at its count byte; a count of 0 ends the table: the pointer
; goes back to C3Mod_Prog6Anims - 2 and the same step finds the first
; entry), C3_Prog6AnimTime = the count, the pointer + 1 (at the
; entry's list address); then C3_SprBaseX / Y = page $0B00's var 1 /
; var 2, and C3Mod_SprListMixed with the entry's list (a 16-bit read
; through the pointer, DB = $7E), DB = $00 for it.
; Callers note: a task added by script opcode $FA at $7DF5
;   (C3Mod_Prog6ScriptB).
; Entry: a task: M=0, X=0 (C3Mod_SprListMixed's), DP=0 (C3_Prog6Anim*,
;        C3_SprBase*), DB any (set here; $00 at the JSL).
; Exit:  M=0, X=0, DB=$00; as C3Mod_SprListMixed leaves them: Y =
;        C3_OamPos, A changed.
; Calls: C3Mod_SprListMixed (JSL).
C3Mod_Prog6AnimTask:
    PEA.w !Bank7E                       ; PLB takes the $7E; the $00 stays for the PLB before the JSL
    PLB
    DEC.b !C3_Prog6AnimTime
    BNE .draw
.next:
    INC.b !C3_Prog6AnimPtr
    INC.b !C3_Prog6AnimPtr
    LDA.b (!C3_Prog6AnimPtr)
    AND.w #!Eng_LowByteMask
    BNE .found
    LDA.w #C3Mod_Prog6Anims-2
    STA.b !C3_Prog6AnimPtr
    BRA .next
.found:
    STA.b !C3_Prog6AnimTime
    INC.b !C3_Prog6AnimPtr
.draw:
    LDX.w !C3_ScriptPageB+!C3_Prog6SprX
    STX.b !C3_SprBaseX
    LDX.w !C3_ScriptPageB+!C3_Prog6SprY
    STX.b !C3_SprBaseY
    LDA.b (!C3_Prog6AnimPtr)
    PLB
    JSL C3Mod_SprListMixed
    RTS

; $7E:838B — C3Mod_Prog6Frames (365 bytes, $838B–$84F7)
; C3Mod_Prog6AnimTask's nine frames: C3Mod_SprListMixed lists (n + 1,
; then tile, attribute, X, Y; small sprites, attribute $29: palette 4,
; priority 2, the second tile page) of 8 to 15 sprites, labelled .f1-
; .f8 after the first.
C3Mod_Prog6Frames:
    db 9        ; 8 sprites
    db $23, $29, $F8, $F0
    db $22, $29, $F0, $F0
    db $21, $29, $E8, $F0
    db $20, $29, $E0, $F0
    db $13, $29, $F8, $E8
    db $12, $29, $F0, $E8
    db $11, $29, $E8, $E8
    db $10, $29, $E0, $E8
.f1:
    db 9        ; 8 sprites
    db $3B, $29, $F8, $F0
    db $3A, $29, $F0, $F0
    db $39, $29, $E8, $F0
    db $38, $29, $E0, $F0
    db $2B, $29, $F8, $E8
    db $2A, $29, $F0, $E8
    db $29, $29, $E8, $E8
    db $28, $29, $E0, $E8
.f2:
    db 9        ; 8 sprites
    db $1B, $29, $F8, $F0
    db $1A, $29, $F0, $F0
    db $19, $29, $E8, $F0
    db $18, $29, $E0, $F0
    db $0B, $29, $F8, $E8
    db $0A, $29, $F0, $E8
    db $09, $29, $E8, $E8
    db $08, $29, $E0, $E8
.f3:
    db 9        ; 8 sprites
    db $3F, $29, $F8, $F0
    db $3E, $29, $F0, $F0
    db $3D, $29, $E8, $F0
    db $3C, $29, $E0, $F0
    db $2F, $29, $F8, $E8
    db $2E, $29, $F0, $E8
    db $2D, $29, $E8, $E8
    db $2C, $29, $E0, $E8
.f4:
    db 9        ; 8 sprites
    db $1F, $29, $F8, $F0
    db $1E, $29, $F0, $F0
    db $1D, $29, $E8, $F0
    db $1C, $29, $E0, $F0
    db $0F, $29, $F8, $E8
    db $0E, $29, $F0, $E8
    db $0D, $29, $E8, $E8
    db $0C, $29, $E0, $E8
.f5:
    db 12        ; 11 sprites
    db $35, $29, $10, $F8
    db $37, $29, $08, $E8
    db $34, $29, $00, $F0
    db $5F, $29, $F8, $F0
    db $5E, $29, $F0, $F0
    db $5D, $29, $E8, $F0
    db $5C, $29, $E0, $F0
    db $4F, $29, $F8, $E8
    db $4E, $29, $F0, $E8
    db $4D, $29, $E8, $E8
    db $4C, $29, $E0, $E8
.f6:
    db 16        ; 15 sprites
    db $36, $29, $00, $E0
    db $37, $29, $10, $E8
    db $34, $29, $00, $F0
    db $27, $29, $F8, $F0
    db $26, $29, $F0, $F0
    db $25, $29, $E8, $F0
    db $24, $29, $E0, $F0
    db $17, $29, $F8, $E8
    db $16, $29, $F0, $E8
    db $15, $29, $E8, $E8
    db $14, $29, $E0, $E8
    db $07, $29, $F8, $E0
    db $06, $29, $F0, $E0
    db $05, $29, $E8, $E0
    db $04, $29, $E0, $E0
.f7:
    db 11        ; 10 sprites
    db $36, $29, $10, $F0
    db $37, $29, $00, $F0
    db $5B, $29, $F8, $F0
    db $5A, $29, $F0, $F0
    db $59, $29, $E8, $F0
    db $58, $29, $E0, $F0
    db $4B, $29, $F8, $E8
    db $4A, $29, $F0, $E8
    db $49, $29, $E8, $E8
    db $48, $29, $E0, $E8
.f8:
    db 14        ; 13 sprites
    db $36, $29, $08, $E8
    db $37, $29, $10, $F0
    db $52, $29, $F0, $F8
    db $51, $29, $E8, $F8
    db $50, $29, $E0, $F8
    db $43, $29, $F8, $F0
    db $42, $29, $F0, $F0
    db $41, $29, $E8, $F0
    db $40, $29, $E0, $F0
    db $33, $29, $F8, $E8
    db $32, $29, $F0, $E8
    db $31, $29, $E8, $E8
    db $30, $29, $E0, $E8

; $7E:84F8 — C3Mod_Prog6Anims (64 bytes, $84F8–$8537)
; C3Mod_Prog6AnimTask's sequence: a frame count and a
; C3Mod_Prog6Frames list per entry, 21 entries, then 0 (back to the
; first).
C3Mod_Prog6Anims:
    db 10 : dw C3Mod_Prog6Frames
    db 6 : dw C3Mod_Prog6Frames_f1
    db 6 : dw C3Mod_Prog6Frames_f2
    db 6 : dw C3Mod_Prog6Frames_f1
    db 6 : dw C3Mod_Prog6Frames
    db 6 : dw C3Mod_Prog6Frames_f3
    db 6 : dw C3Mod_Prog6Frames_f4
    db 6 : dw C3Mod_Prog6Frames_f3
    db 4 : dw C3Mod_Prog6Frames_f5
    db 4 : dw C3Mod_Prog6Frames_f6
    db 4 : dw C3Mod_Prog6Frames_f4
    db 6 : dw C3Mod_Prog6Frames_f7
    db 4 : dw C3Mod_Prog6Frames_f8
    db 6 : dw C3Mod_Prog6Frames_f7
    db 4 : dw C3Mod_Prog6Frames
    db 4 : dw C3Mod_Prog6Frames_f5
    db 4 : dw C3Mod_Prog6Frames_f6
    db 4 : dw C3Mod_Prog6Frames_f4
    db 4 : dw C3Mod_Prog6Frames_f7
    db 4 : dw C3Mod_Prog6Frames_f8
    db 4 : dw C3Mod_Prog6Frames_f7
    db 0

%C3ModOrg($7E8538)
; ============================================================
; Programs 10, 12 and 13 ($8538–$90A6)
; ============================================================
; Program 10 (C3Mod_ProgramTable entries 10, 11, 14 and 15) sets up one
; mode-7 scene and picks its scripts by C3_EntryArg's low nibble ($A:
; C3Mod_Prog10 with the scripts at $90CF / $9341, $B: $9450 / $97A6,
; else $9613 / $970F, all not matched yet). The script routines and NMI
; tasks after it (to $8E94) are those scripts' steps; programs 12 and
; 13 share one setup (C3Mod_Prog13's .setup).

; $7E:8538 — C3Mod_Prog10 (538 bytes, $8538–$8751)
; The program of C3Mod_ProgramTable entries 10, 11, 14 and 15:
;   - VMAIN = $80; C3Mod_DestBitmapSrc (the packs to $7F:0200); pack 33
;     (128 2bpp tiles) to VRAM word $5000 as 4bpp (C3Mod_Font2To4,
;     X = $80): the sprites' second tile page with C3Mod_Init's OBSEL
;     $02; $3F written over C3Mod_DrawText's attribute operand
;     (.attr + 1, a long store: palette 7, priority 3, and bit 0, the
;     second tile page); C3_BuildCopyCode with WMADD = $7E:B574
;     (C3_CopyCode), X = $0C00, Y = $0200;
;   - VMADD = 0, VMAIN = $80: pack 42 ($4000 bytes) to VRAM's high
;     bytes (C3Mod_DmaUnpacked with C3_DmaMode = 0, one register,
;     C3_DmaBbad = VMDATAH: all 256 mode-7 characters); VMAIN = 0,
;     VMADD = 0: pack 43 and then pack 70 (64 x 64 bytes each) through
;     C3Mod_SpaceRows (each 64-byte row followed by 64 zero bytes) and
;     C3Mod_SendM7Map: the mode-7 map's rows 0-63 and 64-127, each the
;     pack's row in columns 0-63 and zeros in 64-127; then
;     C3Mod_VramFillLow, $1000 zero low bytes from VRAM word $4000 on
;     (where the two sends left VMADD; the next DMA writes those words
;     whole: a fill with no effect);
;   - VMAIN = $80, VMADD = $4000: pack 45 ($2000 bytes; C3_DmaMode = 1,
;     two registers, VMDATAL): the sprites' first tile page;
;   - when C3_EntryArg's low nibble is $A (a long read, AND $0F / CMP /
;     BEQ; else JMP .common): pack 63 ($19A0 bytes of 4bpp tiles) to
;     $7F:0200 and pack 60 (320 tile numbers) to $7F:2200; with DB =
;     $7F (PEA $007F / PLB; the $00 stays for the second PLB) and DP =
;     DP_PPU, 320 times (a 16-bit count at $7F:8000): the next number n
;     (WMDATA from $7F:2200, AND $FF) and 32 bytes from $7F:0200 + 32n
;     to the next 32 at $7F:D800 on (MVN in bank $7F; Y + 32 each), so
;     $7F:D800-$FFFF holds the tiles in the numbers' order (an
;     overrun of the original: pack 60's entries 108-111 and 124-127
;     are tile 208, whose 32 bytes, $7F:1C00-$1C1F, lie past pack 63's
;     end at $7F:1B9F; they are zeros left by pack 45, so those eight
;     copies, at $7F:E580-$E5FF and $E780-$E7FF, are blank tiles, in
;     the part sent to VRAM below); DP = 0;
;     $7F:E000-$E7FF ($800 bytes) to VRAM word $5C00 (DMA channel 7,
;     two registers, VMDATAL; VMAIN still $80); the NMI task at $9CE2
;     (C3Mod_NmiTaskAdd; code not matched yet);
;   - .common: Decomp_DestBank = 0 (bank $7E for C3Mod_CopyRawPack);
;     C3_RowCount = $100: raw pack 50 to $7E:2000 (C3_PaletteWork's
;     colours 0-$7F) and raw packs 51, 52 and 53 to $7E:C995, $CA95 and
;     $CB95 (C3_MapColumnSave's place on: 768 bytes); C3_RowCount =
;     $40: raw pack 48 to $7E:2100 (colours $80-$9F); C3Mod_SetGreys;
;     pack 46 ($60 bytes) to $7E:2180 (colours $C0-$EF);
;     C3Mod_CommitPalette; then C3_PaletteBuf's $7E:2200-$22EF
;     (colours 0-$77) zeroed (STZ of its first byte, then an
;     overlapping MVN in bank $7E of $EF more: the count is B:A =
;     $00EE, B being 0 from C3Mod_CommitPalette): those colours are
;     sent black until a fade;
;   - the scripts: page $0A00 $9613 and page $0B00 $970F, or, by
;     C3_EntryArg's low nibble (8-bit CMP / BNE), for $A C3_ResultWord
;     = $A651 (C3Mod_StaffTexts) and $90CF / $9341, for $B the same
;     word and $9450 / $97A6; page $0A00's script runs once now
;     (C3Mod_ScriptTaskA, DB kept around it) and $9B46 (code not
;     matched yet) is written over C3Mod_BuildM7Tables' .setup operand
;     (DB = $7E there, from C3Mod_ScriptTaskA); FdVec_FFEE
;     (PalAnim_StopAll);
;   - DP = 0: C3_Prog10Word81 = 1, C3_Prog10Word7D = $40,
;     C3_Prog10Word7F = $140 (16-bit stores; read by code not matched
;     yet), C3_NoSoftReset = 1; JSR $9BB8 (not matched yet); the HDMA
;     channels of C3Mod_Prog10Hdma, C3_HdmaEnable = channels 0-4;
;     C3_FadeStep = C3_FadeTimer = 1; M7SEL = $C0 (outside the map:
;     character 0), BGMODE = 7, WOBJSEL = $03 (window 1 inverted on the
;     sprites), TMW = $11 (BG1 and the sprites), TM = BG1, TS = the
;     sprites, CGWSEL = $02 (add the sub screen), CGADSUB = $05 (on BG1
;     and BG3), BG1SC = $70, BG2SC = $74, BG12NBA = $66.
; Callers note: C3Mod_ProgramTable entries 10, 11, 14 and 15
;   (C3Mod_Start's JSR (table,X) at $300A).
; Entry: M=1, X=0, DP=0, DB=$00 (as C3Mod_Start calls the programs).
; Exit:  M=1, X=0, DP=0, DB=$00; A = $66; X = $0502, Y as C3Mod_SetupHdma
;        leaves it.
; Calls: C3Mod_DestBitmapSrc, C3Mod_UnpackPack, C3Mod_Font2To4,
;   C3_BuildCopyCode (JSL), C3Mod_DmaUnpacked (JSL), C3Mod_SpaceRows
;   (JSL), C3Mod_SendM7Map, C3Mod_VramFillLow, C3Mod_NmiTaskAdd,
;   C3Mod_CopyRawPack, C3Mod_SetGreys, C3Mod_CommitPalette,
;   C3Mod_ScriptTaskA, FdVec_FFEE (JSL), $9BB8, C3Mod_SetupHdma.
C3Mod_Prog10:
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    JSR C3Mod_DestBitmapSrc
    LDX.w #!C3_SprTilesHigh
    STX.w VMADDL
    LDX.w #33*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog10FontTiles
    JSR C3Mod_Font2To4
    LDA.b #!C3_Prog10TextAttr
    STA.l C3Mod_DrawText_attr+1
    LDA.b #!Bank7E
    STA.w WMADDH
    LDX.w #!C3_CopyCodeAddr
    STX.w WMADDL                        ; and WMADDM
    LDX.w #!C3_CopyCodeDest
    LDY.w #!C3_CopyCodeSrc
    JSL !C3_BuildCopyCode
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDX.w #0
    STX.w VMADDL
    LDX.w #42*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    STZ.w !C3_DmaMode
    LDA.b #!BBAD_VMDATAH
    STA.w !C3_DmaBbad
    JSL C3Mod_DmaUnpacked
    LDA.b #0
    STA.w VMAIN
    LDX.w #0
    STX.w VMADDL
    LDX.w #43*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_SpaceRows
    JSR C3Mod_SendM7Map
    LDX.w #70*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_SpaceRows
    JSR C3Mod_SendM7Map
    LDX.w #!C3_Prog10FillBytes
    JSR C3Mod_VramFillLow
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDX.w #!C3_SprTilesVram
    STX.w VMADDL
    LDX.w #45*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDA.b #!DMAP_TwoRegs
    STA.w !C3_DmaMode
    LDA.b #!BBAD_VMDATAL
    STA.w !C3_DmaBbad
    JSL C3Mod_DmaUnpacked
    LDA.l !C3_EntryArg
    AND.b #!C3_EntryLowNibble
    CMP.b #!C3_Prog10TextMode
    BEQ .text_tiles
    JMP .common
.text_tiles:
    LDX.w #63*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_BitmapDest
    STX.w !Decomp_Dest
    LDX.w #60*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_BitmapDest
    STX.w WMADDL                        ; and WMADDM
    PEA.w !Bank7F                       ; PLB takes the $7F; the $00 stays for the second PLB
    PLB
    REP #$20
    LDA.w #!C3_Prog10TileCount
    STA.w !C3_Prog10TilesLeft
    LDA.w #!DP_PPU
    TCD
    LDY.w #!C3_Prog10TileStrip
.tile:
    LDA.b WMDATA-!DP_PPU
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC.w #!C3_BitmapSrc
    TAX
    LDA.w #!C3_TileBytes-1
    MVN !Bank7F,!Bank7F                 ; lint-ok: MVN operands are bank bytes (bank $7F)
    DEC.w !C3_Prog10TilesLeft
    BNE .tile
    LDA.w #0
    TCD
    SEP #$20
    PLB
    LDX.w #!C3_Prog10TileSend
    STX.w A1T7L
    LDX.w #!C3_Prog10TileSendBytes
    STX.w DAS7L
    LDX.w #!C3_Prog10TileVram
    STX.w VMADDL
    LDX.w #!BBAD_VMDATAL<<8|!DMAP_TwoRegs
    STX.w DMAP7                         ; and BBAD7
    LDA.b #!Bank7F
    STA.w A1B7
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDX.w #C3Mod_Unk9CE2
    JSR C3Mod_NmiTaskAdd
.common:
    STZ.w !Decomp_DestBank
    LDX.w #!C3_Prog10ColoursBytes
    STX.b !C3_RowCount
    LDY.w #!C3_PaletteWorkLow
    LDX.w #50*!C3_PackPtrBytes
    JSR C3Mod_CopyRawPack
    LDY.w #!C3_Prog10Rows51
    LDX.w #51*!C3_PackPtrBytes
    JSR C3Mod_CopyRawPack
    LDY.w #!C3_Prog10Rows52
    LDX.w #52*!C3_PackPtrBytes
    JSR C3Mod_CopyRawPack
    LDY.w #!C3_Prog10Rows53
    LDX.w #53*!C3_PackPtrBytes
    JSR C3Mod_CopyRawPack
    LDX.w #!C3_Prog10Colours80Bytes
    STX.b !C3_RowCount
    LDY.w #!C3_Prog10Colours80
    LDX.w #48*!C3_PackPtrBytes
    JSR C3Mod_CopyRawPack
    JSR C3Mod_SetGreys
    LDX.w #!C3_Prog10ColoursC0
    STX.w !Decomp_Dest
    LDX.w #46*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSR C3Mod_CommitPalette
    STZ.w !C3_Prog10Black
    LDX.w #!C3_Prog10Black
    LDY.w #!C3_Prog10Black+1
    LDA.b #!C3_Prog10BlackBytes-1       ; with B = 0: $00EE
    MVN !Bank7E,!Bank7E                 ; lint-ok: MVN operands are bank bytes (bank $7E)
    LDX.w #C3Mod_Unk9613
    LDY.w #C3Mod_Unk970F
    LDA.l !C3_EntryArg
    AND.b #!C3_EntryLowNibble
    CMP.b #!C3_Prog10TextMode
    BNE .mode_b
    LDX.w #C3Mod_StaffTexts
    STX.w !C3_ResultWord
    LDX.w #C3Mod_Unk90CF
    LDY.w #C3Mod_Unk9341
    BRA .scripts
.mode_b:
    CMP.b #!C3_Prog10ModeB
    BNE .scripts
    LDX.w #C3Mod_StaffTexts
    STX.w !C3_ResultWord
    LDX.w #C3Mod_Unk9450
    LDY.w #C3Mod_Unk97A6
.scripts:
    STX.w !C3_ScriptPageA+!C3Script_Ptr
    STY.w !C3_ScriptPageB+!C3Script_Ptr
    REP #$20
    PHB
    JSR C3Mod_ScriptTaskA
    LDA.w #C3Mod_Unk9B46
    STA.w C3Mod_BuildM7Tables_setup+1
    PLB
    SEP #$20
    JSL !FdVec_FFEE
    PEA.w 0
    PLD
    LDX.w #1
    STX.b !C3_Prog10Word81
    LDX.w #!C3_Prog10Word7DStart
    STX.b !C3_Prog10Word7D
    LDX.w #!C3_Prog10Word7FStart
    STX.b !C3_Prog10Word7F
    LDA.b #1
    STA.w !C3_NoSoftReset
    JSR C3Mod_Unk9BB8
    LDY.w #C3Mod_Prog10Hdma
    JSR C3Mod_SetupHdma
    LDA.b #!C3_Prog10HdmaOn
    STA.w !C3_HdmaEnable
    LDX.w #!C3_Prog10Fade
    STX.w !C3_FadeStep                  ; and C3_FadeTimer
    LDA.b #!C3_Prog10M7Sel
    STA.w M7SEL
    LDA.b #!BGMODE_Mode7
    STA.w BGMODE
    LDA.b #!C3_Prog10ObjWindow
    STA.w WOBJSEL
    LDA.b #!Layer_Bg1Obj
    STA.w TMW
    LDX.w #!TM_Bg1|(!TM_Obj<<8)
    STX.w TM                            ; and TS
    LDX.w #!CGWSEL_AddSubscreen|(!C3_Prog10Math<<8)
    STX.w CGWSEL                        ; and CGADSUB
    LDA.b #!C3_Prog10Bg1Sc
    STA.w BG1SC
    LDA.b #!C3_Prog10Bg2Sc
    STA.w BG2SC
    LDA.b #!C3_Prog10Tiles
    STA.w BG12NBA
    RTS

%C3ModOrg($7E8752)
; ============================================================
; Small helpers of the later programs ($8752–$878F)
; ============================================================

; $7E:8752 — C3Mod_SendM7Map (32 bytes, $8752–$8771)
; Sends $7F:2200-$41FF (C3_BitmapDest: what C3Mod_DoubleRows or
; C3Mod_SpaceRows built) to VRAM's low bytes from
; the address the caller set: VMAIN = 0 (+ 1 after the low byte), DMA
; channel 7 one register to VMDATAL, $2000 bytes (64 rows of a 128-wide
; mode-7 map).
; Callers note: C3Mod_Prog0LoadGfx ($3DF1, $3DFE), C3Mod_Prog10 ($859F,
;   $85AC) and C3Mod_Prog10Turn ($87C4, $87C7).
; Entry: M=1, X=0 (the 16-bit register pairs), DP any, DB = a bank with
;        the I/O registers: $00 at all six calls (C3Mod_Prog0LoadGfx's
;        two, C3Mod_Prog10's $859F and $85AC, C3Mod_Prog10Turn's $87C4
;        and $87C7 after its PEA $7E00 / PLB); VMADD set.
; Exit:  M=1, X=0; A = MDMAEN_Ch7, X = C3_M7MapHalf ($2000); Y
;        unchanged; VMAIN = 0; VMADD past the bytes.
C3Mod_SendM7Map:
    STZ.w VMAIN
    LDX.w #!BBAD_VMDATAL<<8
    STX.w DMAP7                         ; and BBAD7
    LDX.w #!C3_BitmapDest
    STX.w A1T7L
    LDA.b #!Bank7F
    STA.w A1B7
    LDX.w #!C3_M7MapHalf
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    RTS

; $7E:8772 — C3Mod_SetGreys (30 bytes, $8772–$878F)
; With DB = $7E (PEA $007E / PLB; the second PLB takes the $00):
; C3_PaletteWork's colours $F1-$F3 = $77BD, $4631 and $1CE7 (light to
; dark grey) and colour 0 = black (16-bit stores).
; Callers note: C3Mod_Prog7 ($62C5) and C3Mod_Prog10 ($868F).
; Entry: M any, X=0 (the 16-bit stores), DP any, DB any (set to $7E,
;        then $00).
; Exit:  M as on entry, X=0, DB=$00; A unchanged, X = 0; Y unchanged.
C3Mod_SetGreys:
    PEA.w !Bank7E                       ; PLB takes the $7E; the $00 stays for the second PLB
    PLB
    LDX.w #!C3_CreditsColour1
    STX.w !C3_GreysColours
    LDX.w #!C3_CreditsColour2
    STX.w !C3_GreysColours+2
    LDX.w #!C3_CreditsColour3
    STX.w !C3_GreysColours+4
    LDX.w #0
    STX.w !C3_PaletteWorkLow
    PLB
    RTS

%C3ModOrg($7E8790)
; $7E:8790 — C3Mod_Prog10Turn (60 bytes, $8790–$87CB)
; A script routine (opcode $F0): the turning-picture scene of the
; scripts at $9450 and $9613 (not matched yet). C3Mod_Prog10ScaleIdle
; written over C3Mod_Start's idle call ($3024, DB = $7E as
; C3_RunScript keeps it); DB = $00 (PEA $7E00 / PLB: the $00; the $7E
; stays for .exit's PLB); HDMAEN = 0 (TDC: the script page's low byte);
; C3Mod_CommitPalette; C3Mod_MathValues' first CGADSUB byte = $05 (a
; long store); C3Mod_DestBitmapSrc; pack 44 ($1000 bytes, 64 rows of
; 64) made 128 bytes a row by C3Mod_DoubleRows; VMAIN = VMADDL =
; VMADDH = M7SEL = 0 (TDC); C3Mod_SendM7Map twice (its arguments set
; again each time: the same 64 map rows sent as rows 0-63 and 64-127);
; then .common.
; Callers note: script opcode $F0 at $94EE and $9613 (scripts not
;   matched yet).
; Entry: M=0 (8-bit set here), X=0, DP = the script's page (saved),
;        DB = $7E (C3_RunScript's; the idle-call store is absolute).
; Exit:  as .common's.
; Calls: C3Mod_CommitPalette, C3Mod_DestBitmapSrc, C3Mod_UnpackPack,
;   C3Mod_DoubleRows (JSL), C3Mod_SendM7Map.
C3Mod_Prog10Turn:
    PHD
    LDX.w #C3Mod_Prog10ScaleIdle
    STX.w C3Mod_Start_wait_exit+1
    PEA.w !Bank7E<<8                    ; PLB takes the $00; the $7E stays for .exit's PLB
    PLB
    SEP #$20
    TDC
    STA.w HDMAEN
    JSR C3Mod_CommitPalette
    LDA.b #!C3_Prog10Math
    STA.l C3Mod_MathValues
    JSR C3Mod_DestBitmapSrc
    LDX.w #44*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DoubleRows
    TDC
    STA.w VMAIN
    STA.w VMADDL
    STA.w VMADDH
    STA.w M7SEL
    JSR C3Mod_SendM7Map
    JSR C3Mod_SendM7Map
    BRA C3Mod_Prog10TurnB_common

; $7E:87CC — C3Mod_Prog10TurnB (132 bytes with .common, $87CC–$884F)
; A script routine (opcode $F0) of the script at $9450: as
; C3Mod_Prog10Turn without the map (C3Mod_Prog10ScaleIdle over the idle
; call, DB = $00 with the $7E kept, HDMAEN = 0), then .common ($87DD),
; both routines': C3Mod_DestBitmapSrc; pack 72 ($4C00 bytes: 19 blocks
; of 16 rows of 64 pixel bytes) to $7F:0A00; with DB = $7F (PEA $007F
; / PLB; its $00 kept for the PLB after) and DP = DP_PPU (PHD around):
; C3_MirrorEnd ($7F:0200) = $20; WMADD = $7F:5600; 15 times, from the
; block at $7F:4E00 back by $400 each time (the row pointer at
; $7F:0202, REP #$21 / SBC #$3FF: - $400; the count byte at $7F:0204,
; 8-bit DEC / BNE): C3Mod_MirrorRows twice (16 rows, each mirrored
; right to left with 32 zero bytes after it: the source's columns 32
; down to 1, C3_MirrorEnd being $20, so each row's column 0 is
; dropped; pack 72 has pixels in column 0 in 33 of its 304 rows, 24
; of them in the 15 blocks mirrored here); so $7F:5600-$91FF holds
; the blocks $4E00-$51FF down to $1600-$19FF, mirrored and in reverse
; order: with pack 72's blocks from $1200 on, 32 frames of $400 bytes
; from $7F:1200 (C3Mod_Prog10FrameTask's frame k at $1200 + k x
; $400); then DP and DB back (the page, $00); C3Scale_PrevEnd = $0A00;
; Decomp_DestBank = 0; C3_RowCount = $20 (at $F0 of the script's page:
; C3Mod_CopyRawPack reads it there): raw pack 55's 32 bytes to
; $7E:2100 (C3_PaletteWork's colours $80-$8F) and again to $7E:2300
; (C3_PaletteBuf's); then .exit (JMP: C3Mod_Prog10Fill's tail).
; Sub-entry: .common ($87DD), from C3Mod_Prog10Turn (BRA).
; Callers note: script opcode $F0 at $9450 (a script not matched yet).
;   .common: C3Mod_Prog10Turn (BRA).
; Entry: M=0 (8-bit set here), X=0, DP = the script's page (saved),
;        DB = $7E; .common: M=1, DB = $00 with $7E and the page's DP on
;        the stack.
; Exit:  through C3Mod_Prog10Fill's .exit: M=0, X=0, DP and DB as
;        entered (the PHD, the $7E); A = $FFFF (C3Mod_CopyRawPack's);
;        X, Y past the second copy.
; Calls: C3Mod_DestBitmapSrc, C3Mod_UnpackPack, C3Mod_MirrorRows,
;   C3Mod_CopyRawPack.
C3Mod_Prog10TurnB:
    PHD
    LDX.w #C3Mod_Prog10ScaleIdle
    STX.w C3Mod_Start_wait_exit+1
    PEA.w !Bank7E<<8                    ; PLB takes the $00; the $7E stays for .exit's PLB
    PLB
    SEP #$20
    TDC
    STA.w HDMAEN
.common:
    JSR C3Mod_DestBitmapSrc
    LDX.w #!C3_Prog10FramesSrc
    STX.w !Decomp_Dest
    LDX.w #72*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    PEA.w !Bank7F                       ; PLB takes the $7F; the $00 stays for the PLB after
    PLB
    PHD
    PEA.w !DP_PPU
    PLD
    LDX.w #!C3_MirrorEnd32
    STX.w !C3_MirrorEnd
    LDA.b #1                            ; bank $7F
    STA.b WMADDH-!DP_PPU
    LDX.w #!C3_Prog10Mirrored
    STX.b WMADDL-!DP_PPU                ; and WMADDM
    LDX.w #!C3_Prog10MirrorFrom
    STX.w !C3_Prog10MirrorRow
    LDX.w #!C3_Prog10MirrorBlocks
    STX.w !C3_Prog10MirrorLeft
.block:
    LDY.w !C3_Prog10MirrorRow
    JSR C3Mod_MirrorRows
    JSR C3Mod_MirrorRows
    REP #$21
    LDA.w !C3_Prog10MirrorRow
    SBC.w #!C3_Prog10FrameBytes-1       ; C = 0: - $400
    STA.w !C3_Prog10MirrorRow
    SEP #$20
    DEC.w !C3_Prog10MirrorLeft
    BNE .block
    PLD
    PLB
    LDX.w #!C3_Prog10FramesSrc
    STX.w !C3Scale_PrevEnd
    STZ.w !Decomp_DestBank
    LDX.w #!C3_Prog10Colours80Raw
    STX.b !C3_RowCount
    LDY.w #!C3_Prog10Colours80
    LDX.w #55*!C3_PackPtrBytes
    JSR C3Mod_CopyRawPack
    LDY.w #!C3_Prog10Buf80
    LDX.w #55*!C3_PackPtrBytes
    JSR C3Mod_CopyRawPack
    JMP C3Mod_Prog10Fill_exit

; $7E:8850 — C3Mod_Prog10SprNmi (105 bytes, $8850–$88B8)
; An NMI task: the scaled sprite picture and the window around it.
; With h = C3_Prog10Half / 2 (8-bit LSR, kept in C3Math_Lo's low byte):
; C3_SprBaseY = page $0B00's var 2 - h (SEC), and that / 2 (LSR) to the
; first count of C3Mod_Prog10Window, + the LSR's carry (ADC #0) to the
; second; C3_SprBaseX = var 1 - C3_Prog10Half (SEC), the left edge of
; both window lines, + $40 (CLC; $FF when that carries: BCC) their
; right edge; C3_SprBaseX / Y's high bytes = 0; by C3_Prog10Large
; (8-bit, BEQ): 0, the window lines' counts $10 and the list
; C3Mod_Prog10SprSmall (C3_SprListLarge), else $20 and
; C3Mod_Prog10SprLarge.
; Callers note: an NMI task added by script opcode $F8 at $94C9 and
;   $9619, removed by $F7 at $95B9 (scripts not matched yet); also a
;   task added by $FA at $95C2.
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, or a task (M=0; 8-bit
;        set here), X=0, DP=0 (C3_SprBase*, C3_Prog10Half,
;        C3Math_Lo), DB=$00 (page $0B00, C3_SprListLarge's ports and
;        OAM shadow are absolute; the table stores are long).
; Exit:  M=0, X=0; as C3_SprListLarge leaves them: X = C3_OamHiPtr, Y =
;        C3_OamPos; A changed.
; Calls: C3_SprListLarge (JSL).
C3Mod_Prog10SprNmi:
    SEP #$20
    LDA.b !C3_Prog10Half
    LSR A
    STA.b !C3Math_Lo
    LDA.w !C3_ScriptPageB+!C3_Prog10SprY
    SEC
    SBC.b !C3Math_Lo
    STA.b !C3_SprBaseY
    LSR A
    STA.l C3Mod_Prog10Window
    ADC.b #0
    STA.l C3Mod_Prog10Window_second
    LDA.w !C3_ScriptPageB+!C3_Prog10SprX
    SEC
    SBC.b !C3_Prog10Half
    STA.b !C3_SprBaseX
    STA.l C3Mod_Prog10Window_third+1
    STA.l C3Mod_Prog10Window_fourth+1
    CLC
    ADC.b #!C3_Prog10WindowWidth
    BCC .right
    LDA.b #!Eng_Invert8
.right:
    STA.l C3Mod_Prog10Window_third+2
    STA.l C3Mod_Prog10Window_fourth+2
    STZ.b !C3_SprBaseX+1
    STZ.b !C3_SprBaseY+1
    LDA.b !C3_Prog10Large
    BNE .large
    LDA.b #!C3_Prog10WindowSmall
    STA.l C3Mod_Prog10Window_third
    STA.l C3Mod_Prog10Window_fourth
    REP #$20
    LDA.w #C3Mod_Prog10SprSmall
    JSL !C3_SprListLarge
    RTS
.large:
    LDA.b #!C3_Prog10WindowLarge
    STA.l C3Mod_Prog10Window_third
    STA.l C3Mod_Prog10Window_fourth
    REP #$20
    LDA.w #C3Mod_Prog10SprLarge
    JSL !C3_SprListLarge
    RTS

; $7E:88B9 — C3Mod_Prog10SprSmall (33 bytes, $88B9–$88D9)
; C3_SprListLarge's list for the 64 x 32 picture: a count byte n + 1
; (C3Mod_Prog10ScaleIdle writes 9, 3 or 2: 8, 2 or 1 sprites), then
; tile, attribute, X, Y of 8 large sprites (tiles $180-$18E: VRAM word
; $5800, attribute $31, palette 0, priority 3, the second tile page).
C3Mod_Prog10SprSmall:
    db 9        ; 8 sprites
    db $80, $31, $00, $00
    db $82, $31, $10, $00
    db $88, $31, $00, $10
    db $8A, $31, $10, $10
    db $84, $31, $20, $00
    db $86, $31, $30, $00
    db $8C, $31, $20, $10
    db $8E, $31, $30, $10

; $7E:88DA — C3Mod_Prog10SprLarge (65 bytes, $88DA–$891A)
; The same for the 64 x 64 picture: n + 1 = $11, 5 or 2 (16, 4 or 1
; sprites), 16 records (tiles $180-$1AE).
C3Mod_Prog10SprLarge:
    db 17        ; 16 sprites
    db $80, $31, $00, $00
    db $82, $31, $10, $00
    db $88, $31, $00, $10
    db $8A, $31, $10, $10
    db $84, $31, $20, $00
    db $86, $31, $30, $00
    db $8C, $31, $20, $10
    db $8E, $31, $30, $10
    db $A0, $31, $00, $20
    db $A2, $31, $10, $20
    db $A8, $31, $00, $30
    db $AA, $31, $10, $30
    db $A4, $31, $20, $20
    db $A6, $31, $30, $20
    db $AC, $31, $20, $30
    db $AE, $31, $30, $30

; $7E:891B — C3Mod_Prog10FrameTask (21 bytes, $891B–$892F)
; A task: C3_Prog10Frame = $1200 + ((page $0A00's var 5 + $10, with
; the carry the task came in with: no CLC) AND $3E0) x 32 (five ASLs;
; the ADC after them takes the last ASL's carry, 0): one of the 32
; frames C3Mod_Prog10TurnB's .common builds ($7F:1200 + k x $400), by
; the angle rounded to the nearest of 32. .frame ($8921) is the same
; from A (no + $10).
; Sub-entry: .frame ($8921), JMP from $996C (code not matched yet).
; Callers note: a task added by script opcode $FA at $94F4 and $962B,
;   removed by $F9 at $959B (scripts not matched yet). .frame: JMP
;   from $996C (code not matched yet).
; Entry: a task: M=0, X any, DP any, DB=$00 (page $0A00 and
;        C3_Prog10Frame are absolute); C as C3Mod_RunTasks leaves it
;        (0 unless it is the first entry). .frame: A = the angle.
; Exit:  M=0; A = C3_Prog10Frame; X, Y unchanged.
C3Mod_Prog10FrameTask:
    LDA.w !C3_ScriptPageA+!C3_M7Angle
    ADC.w #!C3_Prog10FrameRound
.frame:
    AND.w #!C3_Prog10FrameMask
    ASL A
    ASL A
    ASL A
    ASL A
    ASL A
    ADC.w #!C3_Prog10Frame0
    STA.w !C3_Prog10Frame
.done:
    RTS

; $7E:8930 — C3Mod_Prog10ScaleIdle (144 bytes, $8930–$89BF)
; The idle routine C3Mod_Prog10Turn / TurnB write over C3Mod_Start's
; idle call: unless C3_Prog10TilesReady is set (16-bit LDA / BNE, to
; C3Mod_Prog10FrameTask's RTS):
;   - by C3_Prog10Large (16-bit, BNE): 0: C3Scale_Rows = $20 (31
;     rows), C3Scale_SrcLimit = $0400 (16 source rows); else $40 (63
;     rows) and $0800;
;   - C3Scale_YStep = C3_Prog10Size = page $0B00's var 0 AND $1FF;
;     C3Scale_SrcBase = C3_Prog10Frame; with DB = $7F (PEA $007F /
;     PLB; the $00 stays for the last PLB): C3Scale_Dest =
;     C3Scale_DestPos = $0200; C3Mod_DivHighByte: C3_Prog10Half =
;     $0800 / the step (0 when the step is 0); C3Scale_XStep = the step
;     x 2; C3Scale_Groups = 4 (64 pixels); C3_ScaleBitmap (C = 0 from
;     the ASL); the copy code at $B574 (C3_CopyCode), DP kept around
;     it; DB = $00;
;   - the list count by C3_Prog10Size s (16-bit X, CPX / BCC:
;     unsigned): C3Mod_Prog10SprSmall's = 9 (s below $80), 3 (below
;     $100) or 2; or, C3_Prog10Large set, C3Mod_Prog10SprLarge's = $11,
;     5 or 2 (long stores);
;   - C3_Prog10TilesReady + 1 (16-bit INC).
; Overruns of the original: C3Mod_Prog10TurnB leaves C3Scale_PrevEnd =
; $0A00, so the first picture's closing clear (C3_ScaleBitmap: from
; its end, $05E0 for 31 rows or $09E0 for 63, through the old end, or
; one byte past it when the source ran out first) zeroes up to
; $7F:0A00 or $0A01: pack 72's first bytes, in its block before the
; frames (they start at $1200), so no frame is touched; later clears
; end at or below $09E1.
; Callers note: the patched JSR at $3023 (C3Mod_Start's idle call,
;   written by C3Mod_Prog10Turn at $8794 and C3Mod_Prog10TurnB at
;   $87D0).
; Entry: M=0, X=0 (16-bit), DP=0 (C3Scale_*, C3Math_*, C3_Prog10*),
;        DB=$00, as C3Mod_Start's loop runs.
; Exit:  M=0, X=0, DP=0, DB=$00; after a picture A = the count byte
;        stored (B as the copy code left it), X = C3_Prog10Size, Y as
;        the copy code leaves it; else A = the flag (not 0), X and Y
;        unchanged.
; Calls: C3Mod_DivHighByte, C3_ScaleBitmap (JSL), the generated code
;   at $B574.
C3Mod_Prog10ScaleIdle:
    LDA.b !C3_Prog10TilesReady
    BNE C3Mod_Prog10FrameTask_done
    LDA.b !C3_Prog10Large
    BNE .large
    LDA.w #!C3_Prog10RowsSmall
    STA.b !C3Scale_Rows
    LDA.w #!C3_Prog10LimitSmall
    STA.b !C3Scale_SrcLimit
    BRA .scale
.large:
    LDA.w #!C3_Prog10LimitLarge
    STA.b !C3Scale_SrcLimit
    LDA.w #!C3_Prog10RowsLarge
    STA.b !C3Scale_Rows
.scale:
    LDA.w !C3_ScriptPageB+!C3_Prog10SprSize
    AND.w #!C3_Prog10SizeMask
    STA.b !C3Scale_YStep
    STA.b !C3_Prog10Size
    LDA.b !C3_Prog10Frame
    STA.b !C3Scale_SrcBase
    PEA.w !Bank7F                       ; PLB takes the $7F; the $00 stays for the last PLB
    PLB
    LDX.w #!C3_BitmapSrc
    STX.b !C3Scale_Dest
    STX.b !C3Scale_DestPos
    LDA.b !C3Scale_YStep
    STA.b !C3Math_B
    LDA.w #!C3_Prog10HalfDividend
    JSR C3Mod_DivHighByte
    LDA.b !C3Math_Lo
    STA.b !C3_Prog10Half
    LDA.b !C3Scale_YStep
    ASL A
    STA.b !C3Scale_XStep
    LDA.w #!C3_Prog10ScaleGroups
    STA.b !C3Scale_Groups
    JSL !C3_ScaleBitmap
    PHD
    JSR !C3_CopyCodeAddr
    PLD
    PLB
    LDX.b !C3_Prog10Size
    SEP #$20
    LDA.b !C3_Prog10Large
    BNE .large_list
    LDA.b #!C3_Prog10Small8
    CPX.w #!C3_Prog10SizeMid
    BCC .small_store
    LDA.b #!C3_Prog10Small2
    CPX.w #!C3_Prog10SizeBig
    BCC .small_store
    LDA.b #!C3_Prog10Small1
.small_store:
    STA.l C3Mod_Prog10SprSmall
    BRA .done
.large_list:
    LDA.b #!C3_Prog10Large16
    CPX.w #!C3_Prog10SizeMid
    BCC .large_store
    LDA.b #!C3_Prog10Large4
    CPX.w #!C3_Prog10SizeBig
    BCC .large_store
    LDA.b #!C3_Prog10Small1
.large_store:
    STA.l C3Mod_Prog10SprLarge
.done:
    REP #$20
    INC.b !C3_Prog10TilesReady
    RTS

; $7E:89C0 — C3Mod_Prog10TilesNmi (45 bytes, $89C0–$89EC)
; An NMI task: when C3_Prog10TilesReady is set (8-bit LDA / BEQ),
; C3Scale_SrcLimit's count of bytes ($400 or $800: the scaled tiles'
; size, 32 or 64 tiles) from $00:0C00 (C3_CopyCode's output) to VRAM
; word $5800 (DMA channel 7, two registers from VMDATAL, VMAIN = $80);
; C3_Prog10TilesReady's low byte = 0.
; Callers note: an NMI task added by script opcode $F8 at $946B and
;   $9637, removed by $F7 at $96C3 (scripts not matched yet).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X=0, DP=0, DB=$00.
; Exit:  M=1, X=0; sent: A = $80, X = $0C00, Y = the count; else A = 0,
;        X and Y unchanged.
C3Mod_Prog10TilesNmi:
    LDA.b !C3_Prog10TilesReady
    BEQ .done
    LDX.w #!C3_Prog10TilesVram
    STX.w VMADDL
    LDY.b !C3Scale_SrcLimit
    STY.w DAS7L
    LDA.b #!DMAP_TwoRegs
    STA.w DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD7
    LDX.w #!C3_CopyCodeDest
    STX.w A1T7L
    STZ.w A1B7
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    STA.w MDMAEN                        ; MDMAEN_Ch7, the same value
    STZ.b !C3_Prog10TilesReady
.done:
    RTS

%C3ModOrg($7E89ED)
; $7E:89ED — C3Mod_DestBitmapSrc (20 bytes, $89ED–$8A00)
; Decomp_DestBank / Decomp_Dest = $7F:0200 (C3_BitmapSrc): two
; overlapping 16-bit long stores ($7F00 at $0304, then $0200 at $0303).
; Callers note: C3Mod_Prog0LoadGfx ($3DC5), C3Mod_Prog2 ($5978),
;   C3Mod_Prog7 ($624D), C3Mod_Prog6 ($78EC), C3Mod_Prog6Setup ($7AD8),
;   C3Mod_Prog10 ($853D), C3Mod_Prog10Turn ($87AA), C3Mod_Prog10TurnB
;   ($87DD), C3Mod_Prog10Fill ($8A20), C3Mod_Prog10Stars ($8BCE),
;   C3Mod_Prog10M7Scene ($8C33), C3Mod_Prog10Grid ($8CF2) and C3Mod_Prog13
;   ($8ED9).
; Entry: M any (P saved; 16-bit set here), X any, DP any, DB any (the
;        stores are long).
; Exit:  P restored; A = $0002 (the XBA of $0200; A's low byte 2 at
;        M=1); X, Y unchanged.
C3Mod_DestBitmapSrc:
    PHP
    REP #$20
    LDA.w #!Bank7F<<8
    STA.l !Decomp_Dest+1                ; and Decomp_DestBank = $7F
    LDA.w #!C3_BitmapSrc
    STA.l !Decomp_Dest
    XBA
    PLP
    RTS

%C3ModOrg($7E8A01)
; $7E:8A01 — C3Mod_Prog10Fill (244 bytes, $8A01–$8AF4)
; A script routine (opcode $F0) of the script at $90CF (not matched
; yet): a new scene. DP kept (PHD); C3Mod_ClearTaskList and
; C3Mod_ClearNmiTaskList (from the next frame no task and no NMI task
; runs but what the script adds); DB = $00 (PEA $7E00 / PLB: the $00;
; the $7E stays for .exit), DP = 0; INIDISP = $80 (forced blank),
; HDMAEN = 0 (TDC); VMAIN = $80; C3Mod_DestBitmapSrc;
;   - with C3_DmaMode = 1 (two registers) and C3_DmaBbad = VMDATAL:
;     pack 66 ($C00 bytes) to VRAM word $6000, pack 67 ($100) to $7000
;     and then $700 zero bytes (C3Mod_VramFill, Y = $1809: fixed
;     source, two registers: words $7080-$73FF), pack 68 ($180) to
;     $7400 and $680 zero bytes ($74C0-$77FF);
;   - VMADD = 0: pack 61 ($AA0 bytes of 4-bit pixel pairs) to the
;     mode-7 characters (C3Mod_NibblesToVram with Y = Decomp_OutLen:
;     VRAM's high bytes, two pixels a byte, $1540 words);
;   - VMADD = 0: pack 62 (64 x 64) through C3Mod_SpaceRows, and its
;     $2000 bytes to VRAM's low bytes (VMAIN = 0, DMA channel 7, one
;     register, VMDATAL, from $7F:2200): the mode-7 map's rows 0-63
;     (each row the pack's 64 bytes, then 64 zeros; rows 64-127 kept);
;   - Decomp_DestBank = 0, C3_RowCount = $60 (DP = 0): raw pack 49 to
;     $7E:2000 (C3_PaletteWork's colours 0-$2F); C3Mod_CommitPalette
;     and C3Mod_UploadPalette (sent now, in the forced blank);
;   - the HDMA channels of C3Mod_Prog10Hdma_fill (channel 0: window 1;
;     1: colour math), C3_HdmaEnable = channel 0 only; M7SEL = $80
;     (outside the map transparent), BGMODE = 7, TMW = $11 / TSW =
;     $01, TM = $11 / TS = $10, CGADSUB = $21 (add on BG1 and the
;     backdrop);
;   - .exit ($8AF0): DB = $7E (PLB), M=0 (REP #$20), DP back (PLD).
; Sub-entry: .exit ($8AF0), JMP from the other routines of this group
;   (their DP and $7E pushed the same way).
; Callers note: script opcode $F0 at $91AC (a script not matched yet).
;   .exit: JMP from C3Mod_Prog10TurnB ($884D), C3Mod_Prog10Strip
;   ($8B4F), C3Mod_Prog10Stars ($8C02), C3Mod_Prog10M7Scene ($8CAF),
;   C3Mod_Prog10Grid ($8CEF, $8D53) and C3Mod_Prog10Palette ($8E41).
; Entry: M=0 (C3Mod_ClearTaskList's 16-bit MVN; 8-bit set here), X=0,
;        DP any (saved), DB any (C3Mod_ClearTaskList sets $7E); as
;        C3_RunScript calls opcode 0's routines. .exit: M=1 or 0, the
;        $7E and the DP on the stack.
; Exit:  M=0, X=0, DP as entered, DB = $7E; A = C3Mod_SetupHdma's $FF
;        with $21 stored (A = $0021 with B 0), X = $1011, Y as
;        C3Mod_SetupHdma leaves it.
; Calls: C3Mod_ClearTaskList, C3Mod_ClearNmiTaskList,
;   C3Mod_DestBitmapSrc, C3Mod_UnpackPack, C3Mod_DmaUnpacked (JSL),
;   C3Mod_VramFill, C3Mod_NibblesToVram, C3Mod_SpaceRows (JSL),
;   C3Mod_CopyRawPack, C3Mod_CommitPalette, C3Mod_UploadPalette,
;   C3Mod_SetupHdma.
C3Mod_Prog10Fill:
    PHD
    JSR C3Mod_ClearTaskList
    JSR C3Mod_ClearNmiTaskList
    PEA.w !Bank7E<<8                    ; PLB takes the $00; the $7E stays for .exit's PLB
    PLB
    LDA.w #0
    TCD
    SEP #$20
    LDA.b #!INIDISP_ForceBlank
    STA.w INIDISP
    TDC
    STA.w HDMAEN
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    JSR C3Mod_DestBitmapSrc
    LDX.w #!C3_Prog10FillMap
    STX.w VMADDL
    LDX.w #66*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDA.b #!DMAP_TwoRegs
    STA.w !C3_DmaMode
    LDA.b #!BBAD_VMDATAL
    STA.w !C3_DmaBbad
    JSL C3Mod_DmaUnpacked
    LDX.w #!C3_Prog10FillMapB
    STX.w VMADDL
    LDX.w #67*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DmaUnpacked
    LDX.w #!C3_Prog10FillZeroB
    LDY.w #!BBAD_VMDATAL<<8|!DMAP_FixedSource|!DMAP_TwoRegs
    JSR C3Mod_VramFill
    LDX.w #!C3_Prog10FillMapC
    STX.w VMADDL
    LDX.w #68*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DmaUnpacked
    LDX.w #!C3_Prog10FillZeroC
    LDY.w #!BBAD_VMDATAL<<8|!DMAP_FixedSource|!DMAP_TwoRegs
    JSR C3Mod_VramFill
    LDX.w #0
    STX.w VMADDL
    LDX.w #61*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDY.w !Decomp_OutLen
    JSR C3Mod_NibblesToVram
    LDX.w #0
    STX.w VMADDL
    LDX.w #62*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_SpaceRows
    TDC
    STA.w VMAIN
    STA.w DMAP7
    LDA.b #!BBAD_VMDATAL
    STA.w BBAD7
    LDX.w #!C3_BitmapDest
    STX.w A1T7L
    LDA.b #!Bank7F
    STA.w A1B7
    LDX.w #!C3_M7MapHalf
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    STZ.w !Decomp_DestBank
    LDX.w #!C3_Prog10FillColours
    STX.b !C3_RowCount
    LDY.w #!C3_PaletteWorkLow
    LDX.w #49*!C3_PackPtrBytes
    JSR C3Mod_CopyRawPack
    JSR C3Mod_CommitPalette
    JSR C3Mod_UploadPalette
    LDY.w #C3Mod_Prog10Hdma_fill
    JSR C3Mod_SetupHdma
    LDA.b #1
    STA.w !C3_HdmaEnable
    LDA.b #!C3_M7SelTransparent
    STA.w M7SEL
    LDA.b #!BGMODE_Mode7
    STA.w BGMODE
    LDX.w #!Layer_Bg1Obj|(!TM_Bg1<<8)
    STX.w TMW                           ; and TSW
    LDX.w #!Layer_Bg1Obj|(!TM_Obj<<8)
    STX.w TM                            ; and TS
    LDA.b #!CGADSUB_AddBg1Backdrop
    STA.w CGADSUB
.exit:
    PLB
    REP #$20
    PLD
    RTS

; $7E:8AF5 — C3Mod_Prog10Strip (93 bytes, $8AF5–$8B51)
; A script routine (opcode $F0) of the script at $90CF: DP kept; both
; task lists cleared; DB = $00 (the $7E kept), DP = 0; INIDISP = $80,
; HDMAEN = 0 (TDC); the HDMA channels of C3Mod_Prog10HdmaStrip,
; C3_HdmaEnable = channels 0-3; TM = $13 (BG1, BG2 and the sprites),
; TS = $10; WOBJSEL = 0; the first two counts of
; C3Mod_Prog10ModeStrip, C3Mod_Prog10Scroll and C3Mod_Prog10ScreenB
; = $64 (long stores: 100 lines each); C3_Prog10LowVofs = $FF70 (its
; two bytes, each also written to BG2VOFS: low, then high); .exit.
; Callers note: script opcode $F0 at $91FD (a script not matched yet).
; Entry: as C3Mod_Prog10Fill's.
; Exit:  through .exit: M=0, X=0, DP as entered, DB = $7E; A = $FF (B
;        0), X = $1013, Y as C3Mod_SetupHdma leaves it.
; Calls: C3Mod_ClearTaskList, C3Mod_ClearNmiTaskList, C3Mod_SetupHdma.
C3Mod_Prog10Strip:
    PHD
    JSR C3Mod_ClearTaskList
    JSR C3Mod_ClearNmiTaskList
    PEA.w !Bank7E<<8                    ; PLB takes the $00; the $7E stays for .exit's PLB
    PLB
    LDA.w #0
    TCD
    SEP #$20
    LDA.b #!INIDISP_ForceBlank
    STA.w INIDISP
    TDC
    STA.w HDMAEN
    LDY.w #C3Mod_Prog10HdmaStrip
    JSR C3Mod_SetupHdma
    LDA.b #!C3_Prog10StripHdmaOn
    STA.w !C3_HdmaEnable
    LDX.w #!Layer_Bg12Obj|(!TM_Obj<<8)
    STX.w TM                            ; and TS
    LDA.b #0
    STA.w WOBJSEL
    LDA.b #!C3_Prog10StripLines
    STA.l C3Mod_Prog10Scroll
    STA.l C3Mod_Prog10Scroll+3
    STA.l C3Mod_Prog10ModeStrip
    STA.l C3Mod_Prog10ModeStrip+3
    STA.l C3Mod_Prog10ScreenB
    STA.l C3Mod_Prog10ScreenB+3
    LDA.b #!C3_Prog10LowVofsLow
    STA.w !C3_Prog10LowVofs
    STA.w BG2VOFS
    LDA.b #!Eng_Invert8
    STA.w !C3_Prog10LowVofs+1
    STA.w BG2VOFS
    JMP C3Mod_Prog10Fill_exit

; $7E:8B52 — C3Mod_Prog10StripNmi (93 bytes, $8B52–$8BAE)
; An NMI task: with v = page $0A00's var 5 (C3_M7Angle's word here;
; 16-bit: CMP #$E0 / BMI keeps v when v - $E0 has bit 15 set, that
; is v in $0000-$00DF or $80E0-$FFFF, and makes it $E0 for
; $00E0-$80DF), 8-bit: n = v's low byte / 2 (LSR, C = its bit 0) to the
; two counts of C3Mod_Prog10Scroll and the first of
; C3Mod_Prog10ModeStrip, n + C (ADC #0) to C3Mod_Prog10ModeStrip's
; second and both of C3Mod_Prog10ScreenB (for v's low byte b:
; C3Mod_Prog10ModeStrip's two make b lines, C3Mod_Prog10Scroll's 2n,
; one less for an odd b, and C3Mod_Prog10ScreenB's 2n + 2C, one more
; for an odd b); then 16-bit (REP #$21: C =
; 0) with v again (unclamped): C3_Prog10LowVofs = -(v + $31) (EOR /
; INC; C3Mod_Prog10Scroll's BG1VOFS under the split), BG2VOFS = the
; low byte of that word + $20 + the ADC #$31's carry, then the stored
; word's high byte (not the sum's: a quirk when the + $20 carries);
; C3_Prog10TopVofs = $80 - v (EOR / SEC / ADC), C3_Prog10TopHofs =
; $FF50 (the BG1 scroll above the split).
; Callers note: an NMI task added by script opcode $F8 at $9206 (a
;   script not matched yet).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1 (REP #$20 here), X=0,
;        DP any, DB=$00 (page $0A00, the $1400 words and BG2VOFS are
;        absolute; the table stores are long).
; Exit:  M=0, X=0; A = C3_Prog10TopVofs, X = $FF50; Y unchanged.
C3Mod_Prog10StripNmi:
    REP #$20
    LDA.w !C3_ScriptPageA+!C3_M7Angle
    CMP.w #!C3_Prog10StripMax
    BMI .clamped
    LDA.w #!C3_Prog10StripMax
.clamped:
    SEP #$20
    LSR A
    STA.l C3Mod_Prog10Scroll
    STA.l C3Mod_Prog10Scroll+3
    STA.l C3Mod_Prog10ModeStrip
    ADC.b #0
    STA.l C3Mod_Prog10ModeStrip+3
    STA.l C3Mod_Prog10ScreenB
    STA.l C3Mod_Prog10ScreenB+3
    REP #$21
    LDA.w !C3_ScriptPageA+!C3_M7Angle
    ADC.w #!C3_Prog10Bg2Base
    EOR.w #!Eng_Invert16
    INC A
    STA.w !C3_Prog10LowVofs
    ADC.w #!C3_Prog10Bg2Add
    SEP #$20
    STA.w BG2VOFS
    LDA.w !C3_Prog10LowVofs+1
    STA.w BG2VOFS
    REP #$20
    LDA.w !C3_ScriptPageA+!C3_M7Angle
    EOR.w #!Eng_Invert16
    SEC
    ADC.w #!C3_Prog10Bg1Base
    STA.w !C3_Prog10TopVofs
    LDX.w #!C3_Prog10TopHofsStart
    STX.w !C3_Prog10TopHofs
    RTS
; $7E:8BAF — C3Mod_Prog10Stars (86 bytes, $8BAF–$8C04)
; A script routine (opcode $F0): DP kept; both task lists cleared; DB =
; $00 (the $7E kept), DP = 0; HDMAEN = C3_HdmaEnable = 0 (A's low byte
; from the LDA #0), INIDISP = $80; C3Mod_InitStars; C3Mod_DestBitmapSrc;
; pack 17 ($200 bytes) to VRAM word $4600 (C3_DmaMode = 1, two
; registers, VMDATAL; VMAIN as it was); Decomp_Dest's high byte and
; Decomp_DestBank = 0 (a 16-bit store at $0304: bank $7E for
; C3Mod_CopyRawPack); C3_RowCount = $20 (DP = 0): raw pack 19 to
; $7E:2120 (C3_PaletteWork's colours $90-$9F); C3Mod_CommitPalette;
; .exit.
; Callers note: script opcode $F0 at $926F (a script not matched yet).
; Entry: as C3Mod_Prog10Fill's.
; Exit:  through C3Mod_Prog10Fill's .exit: M=0, X=0, DP as entered, DB
;        = $7E; A = 0, X = $2200, Y = $2400 (C3Mod_CommitPalette's).
; Calls: C3Mod_ClearTaskList, C3Mod_ClearNmiTaskList, C3Mod_InitStars,
;   C3Mod_DestBitmapSrc, C3Mod_UnpackPack, C3Mod_DmaUnpacked (JSL),
;   C3Mod_CopyRawPack, C3Mod_CommitPalette.
C3Mod_Prog10Stars:
    PHD
    JSR C3Mod_ClearTaskList
    JSR C3Mod_ClearNmiTaskList
    PEA.w !Bank7E<<8                    ; PLB takes the $00; the $7E stays for .exit's PLB
    PLB
    LDA.w #0
    TCD
    SEP #$20
    STA.w HDMAEN
    STA.w !C3_HdmaEnable
    LDA.b #!INIDISP_ForceBlank
    STA.w INIDISP
    JSR C3Mod_InitStars
    JSR C3Mod_DestBitmapSrc
    LDA.b #!DMAP_TwoRegs
    STA.w !C3_DmaMode
    LDA.b #!BBAD_VMDATAL
    STA.w !C3_DmaBbad
    LDX.w #!C3_Prog10StarTiles
    STX.w VMADDL
    LDX.w #17*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DmaUnpacked
    LDX.w #0
    STX.w !Decomp_Dest+1                ; and Decomp_DestBank
    LDX.w #!C3_Prog10StarColoursBytes
    STX.b !C3_RowCount
    LDY.w #!C3_Prog10StarColours
    LDX.w #19*!C3_PackPtrBytes
    JSR C3Mod_CopyRawPack
    JSR C3Mod_CommitPalette
    JMP C3Mod_Prog10Fill_exit

; $7E:8C05 — C3Mod_ClearOamHigh (15 bytes, $8C05–$8C13)
; An NMI task: Oam_HighTable ($0900, 32 bytes) cleared: 32 bytes from
; $D2:0000 (GfxRom_D2's zero bytes; MVN, ROM bank $D2 to $00).
; Callers note: an NMI task added by script opcode $F8 at $9278 and
;   $93F2 (scripts not matched yet).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1 (REP #$20 here), X=0 (the
;        MVN's 16-bit registers), DP any, DB any (set by the MVN;
;        restored by C3Mod_RunNmiTasks).
; Exit:  M=0, X=0, DB=$00; A = $FFFF; X = $0020, Y = Oam_HighTable +
;        $20.
C3Mod_ClearOamHigh:
    REP #$20
    LDX.w #!GfxRom_D2&$FFFF
    LDY.w #!Oam_HighTable
    LDA.w #!C3_OamHighBytes-1
    MVN !Bank00,!BankD2                 ; lint-ok: MVN operands are bank bytes ($D2:0000 to $00)
    RTS

; $7E:8C14 — C3Mod_Prog10M7Scene (158 bytes, $8C14–$8CB1)
; A script routine (opcode $F0): DP kept; both task lists cleared; DB =
; $00 (the $7E kept), DP = 0; HDMAEN = C3_HdmaEnable = 0, INIDISP =
; M7SEL = $80 (forced blank; outside the mode-7 map transparent);
; C3Mod_DestBitmapSrc; C3_DmaMode = 1, C3_DmaBbad = VMDATAL, VMAIN =
; $80:
;   - pack 69 ($2D00 bytes) to $7F:0200 and to VRAM word $6000;
;   - VMADD = 0: C3Mod_TilesToM7 made 8bpp (self-modifying, for good:
;     its .convert JSR's operand = C3Mod_Tile8ToM7, $5EF8, by two long
;     byte stores, and its .step operand's low byte = $30, so 64 bytes
;     a tile) with Y = $A4: 164 tiles of pack 69 as mode-7 characters
;     0-163;
;   - pack 59 ($800 bytes: a 32 x 32 map) to VRAM word $4400 and as the
;     mode-7 map's top-left corner (C3Mod_MapToM7);
;   - Decomp_DestBank = 0, Decomp_Dest = $2020: pack 28 ($1C0 bytes) to
;     $7E:2020-$21DF (C3_PaletteWork's colours $10-$EF);
;     C3Mod_Prog10Greys (colours 0-3); C3Mod_CommitPalette and
;     C3Mod_UploadPalette (now, in the forced blank);
;   - DP = 0 (PEA / PLD: it is 0 already); TM = BG1, TS = the sprites,
;     TMW = TSW = 0, BGMODE = 7; .exit.
; Callers note: script opcode $F0 at $9290 (a script not matched yet).
; Entry: as C3Mod_Prog10Fill's.
; Exit:  through C3Mod_Prog10Fill's .exit: M=0, X=0, DP as entered, DB
;        = $7E; A = 7 (B as C3Mod_UploadPalette left it), X = 0, Y as
;        C3Mod_UploadPalette leaves it.
; Calls: C3Mod_ClearTaskList, C3Mod_ClearNmiTaskList,
;   C3Mod_DestBitmapSrc, C3Mod_UnpackPack, C3Mod_DmaUnpacked (JSL),
;   C3Mod_TilesToM7, C3Mod_MapToM7, C3Mod_Prog10Greys,
;   C3Mod_CommitPalette, C3Mod_UploadPalette.
C3Mod_Prog10M7Scene:
    PHD
    JSR C3Mod_ClearTaskList
    JSR C3Mod_ClearNmiTaskList
    PEA.w !Bank7E<<8                    ; PLB takes the $00; the $7E stays for .exit's PLB
    PLB
    LDA.w #0
    TCD
    SEP #$20
    STA.w HDMAEN
    STA.w !C3_HdmaEnable
    LDA.b #!INIDISP_ForceBlank
    STA.w INIDISP
    STA.w M7SEL                         ; $80: C3_M7SelTransparent
    JSR C3Mod_DestBitmapSrc
    LDA.b #!DMAP_TwoRegs
    STA.w !C3_DmaMode
    LDA.b #!BBAD_VMDATAL
    STA.w !C3_DmaBbad
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDX.w #69*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog10SceneBg
    STX.w VMADDL
    JSL C3Mod_DmaUnpacked
    LDX.w #0
    STX.w VMADDL
    LDA.b #C3Mod_Tile8ToM7
    STA.l C3Mod_TilesToM7_convert+1
    LDA.b #C3Mod_Tile8ToM7>>8
    STA.l C3Mod_TilesToM7_convert+2
    LDA.b #!C3_Tile8Skip
    STA.l C3Mod_TilesToM7_step+1
    LDY.w #!C3_Prog10SceneTiles
    JSR C3Mod_TilesToM7
    LDX.w #59*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog10SceneMap
    STX.w VMADDL
    JSR C3Mod_MapToM7
    STZ.w !Decomp_DestBank
    LDX.w #!C3_Prog10Colours10
    STX.w !Decomp_Dest
    LDX.w #28*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSR C3Mod_Prog10Greys
    JSR C3Mod_CommitPalette
    JSR C3Mod_UploadPalette
    PEA.w 0
    PLD
    LDX.w #!TM_Bg1|(!TM_Obj<<8)
    STX.w TM                            ; and TS
    LDX.w #0
    STX.w TMW                           ; and TSW
    LDA.b #!BGMODE_Mode7
    STA.w BGMODE
    JMP C3Mod_Prog10Fill_exit

; $7E:8CB2 — C3Mod_Prog10Greys (30 bytes, $8CB2–$8CCF)
; As C3Mod_SetGreys for colours 0-3: with DB = $7E (PEA $007E / PLB;
; the second PLB takes the $00), C3_PaletteWork's colour 0 = black and
; colours 1-3 = $77BD, $4631 and $1CE7 (16-bit stores).
; Callers note: C3Mod_Prog10M7Scene ($8C91) and C3Mod_Prog13 ($8F45).
; Entry: M any, X=0 (the 16-bit stores), DP any, DB any (set to $7E,
;        then $00).
; Exit:  M as on entry, X=0, DB=$00; A unchanged, X = $1CE7; Y
;        unchanged.
C3Mod_Prog10Greys:
    PEA.w !Bank7E                       ; PLB takes the $7E; the $00 stays for the second PLB
    PLB
    LDX.w #0
    STX.w !C3_PaletteWorkLow
    LDX.w #!C3_CreditsColour1
    STX.w !C3_PaletteWorkLow+2
    LDX.w #!C3_CreditsColour2
    STX.w !C3_PaletteWorkLow+4
    LDX.w #!C3_CreditsColour3
    STX.w !C3_PaletteWorkLow+6
    PLB
    RTS

; $7E:8CD0 — C3Mod_Prog10Grid (134 bytes, $8CD0–$8D55)
; A script routine (opcode $F0): DP kept; C3_TaskList cleared (the NMI
; tasks kept); DB = $00 (the $7E kept); HDMAEN = 0 (A = $5B00: the low
; byte); then by C3_EntryArg's low nibble (8-bit CMP / BNE):
;   - $F: page $0A00's script pointer = $9315 (not matched yet); .exit;
;   - else C3Mod_DestBitmapSrc; pack 58 ($400 bytes) to $7F:0200, pack
;     47 ($A00) to $7F:0400 (over pack 58's second half,
;     $0400-$05FF) and pack 64 ($100) to $7F:0F00 (Decomp_Dest set
;     before each); DP = DP_PPU: WMADD = $7F:1000 (WMADDH as the
;     unpack left it); 8 times (a byte count at $00F0, DEC / BNE), for
;     X = 0, 4, 8, $C (CPX #$10 / BNE): 8 times (the byte at $00F2) the
;     four map words X, X + 1, X + 2, X + 3 (TXA: X's low byte) with
;     attribute Y's high byte, 0 (each STA WMDATA, then a 16-bit STY to
;     $217F: Y's low byte to $217F, which is no register, its high byte
;     to WMDATA): a 32 x 32 map at $7F:1000-$17FF of tiles 0-15 in
;     4 x 4 blocks, repeated; .exit.
; Callers note: script opcode $F0 at $92BB (a script not matched yet).
; Entry: as C3Mod_Prog10Fill's (only C3Mod_ClearTaskList called).
; Exit:  through C3Mod_Prog10Fill's .exit: M=0, X=0, DP as entered, DB
;        = $7E; A = $0F (8-bit: the last TXA and three INCs, or the
;        AND / CMP on the $F path); X = $0010 and Y = 0 with the map,
;        X = $9315 on the $F path.
; Calls: C3Mod_ClearTaskList, C3Mod_DestBitmapSrc, C3Mod_UnpackPack.
C3Mod_Prog10Grid:
    PHD
    JSR C3Mod_ClearTaskList
    PEA.w !Bank7E<<8                    ; PLB takes the $00; the $7E stays for .exit's PLB
    PLB
    LDA.w #!C3_Prog10GridA
    SEP #$20
    STA.w HDMAEN
    LDA.w !C3_EntryArg
    AND.b #!C3_EntryLowNibble
    CMP.b #!C3_EntryLowNibble
    BNE .grid
    LDX.w #C3Mod_Unk9315
    STX.w !C3_ScriptPageA+!C3Script_Ptr
    JMP C3Mod_Prog10Fill_exit
.grid:
    JSR C3Mod_DestBitmapSrc
    LDX.w #58*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog10GridFrom47
    STX.w !Decomp_Dest
    LDX.w #47*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog10GridFrom64
    STX.w !Decomp_Dest
    LDX.w #64*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    PEA.w !DP_PPU
    PLD
    LDX.w #!C3_Prog10GridMap
    STX.b WMADDL-!DP_PPU                ; and WMADDM
    LDA.b #!C3_Prog10GridRepeat
    STA.w !C3_TmpF0
    LDY.w #0
.band:
    LDX.w #0
.row:
    LDA.b #!C3_Prog10GridRepeat
    STA.w !C3_TmpF2
.block:
    TXA
    STA.b WMDATA-!DP_PPU
    STY.b WMDATA-!DP_PPU-1              ; Y's high byte to WMDATA
    INC A
    STA.b WMDATA-!DP_PPU
    STY.b WMDATA-!DP_PPU-1
    INC A
    STA.b WMDATA-!DP_PPU
    STY.b WMDATA-!DP_PPU-1
    INC A
    STA.b WMDATA-!DP_PPU
    STY.b WMDATA-!DP_PPU-1
    DEC.w !C3_TmpF2
    BNE .block
    INX
    INX
    INX
    INX
    CPX.w #!C3_Prog10GridTiles
    BNE .row
    DEC.w !C3_TmpF0
    BNE .band
    JMP C3Mod_Prog10Fill_exit

; $7E:8D56 — C3Mod_Prog10GridNmi (157 bytes, $8D56–$8DF2)
; A one-shot NMI task: the mode-4 scene. $7F:0200-$03FF ($200 bytes:
; pack 58's first half, as C3Mod_Prog10Grid unpacked it) to VRAM word
; $4000 (DMA channel 7, two
; registers, VMDATAL, VMAIN = $80); VMADD = $4800, VMAIN = 0: $400 low
; bytes zeroed (C3Mod_VramFillLow, which leaves A1B7 = $7E); VMADD =
; $4800 again: $400 high bytes from the fixed byte at $7E:9E7A ($20,
; a byte between two routines not matched yet, used as data: DMAP $08,
; fixed source, one register, VMDATAH; VMAIN = $80): a 32 x 32 map of
; tile 0 with attribute $20 (priority); the HDMA channel of
; C3Mod_Prog10HdmaGrid (0: COLDATA), C3_HdmaEnable = channel 0;
; C3_Prog10TextPtr = $B099 (in C3Mod_StaffTexts' second text, at its
; "//////TRANSLATOR" part), C3_Prog10TextY = -$20 (16-bit, DP = 0); DP =
; DP_PPU: BG2HOFS = 0 (both bytes, TDC), BG12NBA = $46, BG34NBA = 0,
; BG1SC = $44, BG2SC = $48, BG3SC = $60, BGMODE = 4, CGADSUB = $82
; (subtract, on BG2), TM = $13 (BG1, BG2 and the sprites), TS = 0,
; TMW = TSW = 0 (16-bit stores); then it ends itself (JMP
; C3Mod_NmiTaskEnd, which restores DP).
; Callers note: an NMI task added by script opcode $F8 at $92C9 (a
;   script not matched yet).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X=0, DP=0 (the two
;        words; set to DP_PPU after), DB=$00 (the registers).
; Exit:  JMP C3Mod_NmiTaskEnd with M=1, X=0, DP = DP_PPU, DB=$00; A =
;        $82, X = 0.
; Calls: C3Mod_VramFillLow, C3Mod_SetupHdma.
C3Mod_Prog10GridNmi:
    LDX.w #!C3_SprTilesVram
    STX.w VMADDL
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDX.w #!BBAD_VMDATAL<<8|!DMAP_TwoRegs
    STX.w DMAP7                         ; and BBAD7
    LDX.w #!C3_BitmapSrc
    STX.w A1T7L
    LDA.b #!Bank7F
    STA.w A1B7
    LDX.w #!C3_Prog10GridTileBytes
    STX.w DAS7L
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    LDX.w #!C3_Prog10GridBgMap
    STX.w VMADDL
    STZ.w VMAIN
    LDX.w #!C3_Prog10GridMapBytes
    JSR C3Mod_VramFillLow
    LDX.w #!C3_Prog10GridBgMap
    STX.w VMADDL
    LDX.w #!C3_Prog10GridMapBytes
    STX.w DAS7L
    LDX.w #!BBAD_VMDATAH<<8|!DMAP_FixedSource
    STX.w DMAP7                         ; and BBAD7
    LDX.w #C3Mod_Unk9E7A
    STX.w A1T7L
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    STA.w MDMAEN                        ; MDMAEN_Ch7, the same value
    LDY.w #C3Mod_Prog10HdmaGrid
    JSR C3Mod_SetupHdma
    LDA.b #1
    STA.w !C3_HdmaEnable
    LDX.w #!C3_Prog10TextA
    STX.b !C3_Prog10TextPtr
    LDX.w #!C3_Prog10TextYStart
    STX.b !C3_Prog10TextY
    PEA.w !DP_PPU
    PLD
    TDC
    STA.b BG2HOFS-!DP_PPU
    STA.b BG2HOFS-!DP_PPU
    LDA.b #!C3_Prog10GridTiles12
    STA.b BG12NBA-!DP_PPU
    LDA.b #0
    STA.b BG34NBA-!DP_PPU
    LDA.b #!C3_Prog10GridBg1Sc
    STA.b BG1SC-!DP_PPU
    LDA.b #!C3_Prog10GridBg2Sc
    STA.b BG2SC-!DP_PPU
    LDA.b #!C3_Prog10Bg3Sc
    STA.b BG3SC-!DP_PPU
    LDA.b #!C3_Prog10Mode4
    STA.b BGMODE-!DP_PPU
    LDA.b #!C3_Prog10GridMath
    STA.b CGADSUB-!DP_PPU
    LDX.w #!Layer_Bg12Obj
    STX.b TM-!DP_PPU                    ; and TS
    LDX.w #0
    STX.b TMW-!DP_PPU                   ; and TSW
    JMP C3Mod_NmiTaskEnd

; $7E:8DF3 — C3Mod_Prog10Palette (81 bytes, $8DF3–$8E43)
; A script routine (opcode $F0): DP kept; DB = $00 (PEA $7E00 / PLB;
; the $7E kept for .exit); Decomp_Dest's high byte and Decomp_DestBank
; = 0 (bank $7E); C3_RowCount = $20 at $F0 of the script's page (DP
; is the script's: C3Mod_CopyRawPack reads it there): raw pack 54 to
; $7E:21E0 (colours $F0-$FF) and raw pack 57 to $7E:2000 (colours
; 0-$0F); C3Mod_CommitPalette; 32 zero bytes from $D2:0000 to
; $7E:23C0-$23DF (C3_PaletteBuf's colours $E0-$EF; MVN, DB saved
; around it); C3_Prog10Word71 = $E0 and C3_Prog10Word73, 75, 77, 79
; = $80 (16-bit absolute stores: dp 0's words, read by code not
; matched yet); .exit.
; Callers note: script opcode $F0 at $92E4 (a script not matched yet).
; Entry: M=0 (8-bit set here), X=0, DP = the script's page (saved),
;        DB = $7E (C3_RunScript's).
; Exit:  through C3Mod_Prog10Fill's .exit: M=0, X=0, DP as entered, DB
;        = $7E; A = $FFFF, X = $0080, Y = $23E0.
; Calls: C3Mod_CopyRawPack, C3Mod_CommitPalette.
C3Mod_Prog10Palette:
    PHD
    PEA.w !Bank7E<<8                    ; PLB takes the $00; the $7E stays for .exit's PLB
    PLB
    SEP #$20
    LDX.w #0
    STX.w !Decomp_Dest+1                ; and Decomp_DestBank
    LDX.w #!C3_Prog10PalBytes
    STX.b !C3_RowCount
    LDY.w #!C3_Prog10PalF0
    LDX.w #54*!C3_PackPtrBytes
    JSR C3Mod_CopyRawPack
    LDY.w #!C3_PaletteWorkLow
    LDX.w #57*!C3_PackPtrBytes
    JSR C3Mod_CopyRawPack
    JSR C3Mod_CommitPalette
    PHB
    REP #$20
    LDX.w #!GfxRom_D2&$FFFF
    LDY.w #!C3_Prog10PalClear
    LDA.w #!C3_Prog10PalBytes-1
    MVN !Bank7E,!BankD2                 ; lint-ok: MVN operands are bank bytes ($D2:0000 to $7E)
    SEP #$20
    PLB
    LDX.w #!C3_Prog10Word71Start
    STX.w !C3_Prog10Word71
    LDX.w #!C3_Prog10WordsStart
    STX.w !C3_Prog10Word73
    STX.w !C3_Prog10Word73+2
    STX.w !C3_Prog10Word73+4
    STX.w !C3_Prog10Word73+6
    JMP C3Mod_Prog10Fill_exit

; $7E:8E44 — C3Mod_Prog10Mode4Nmi (68 bytes, $8E44–$8E87)
; A one-shot NMI task, DP = DP_PPU: CGADSUB = $21 (add on BG1 and the
; backdrop), COLDATA = $E0 (black), TM = BG1, TS = $12 (BG2 and the
; sprites), BGMODE = 4, BG2SC = $4C, BG12NBA = $06, BG3SC = $60,
; W12SEL = $30 (window 1 on BG2, inverted), TSW = $02 (BG2), WH0 = WH2
; = 0, SETINI = 0; the HDMA channel of C3Mod_Prog10HdmaWindow (0: WH0 /
; WH1), C3_HdmaEnable = channel 0; then it ends itself.
; Callers note: an NMI task added by script opcode $F8 at $92F0 (a
;   script not matched yet).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X=0, DP any (set here),
;        DB=$00 (C3_HdmaEnable is absolute).
; Exit:  JMP C3Mod_NmiTaskEnd with M=1, X=0, DP = DP_PPU, DB=$00; A = 1.
; Calls: C3Mod_SetupHdma.
C3Mod_Prog10Mode4Nmi:
    PEA.w !DP_PPU
    PLD
    LDA.b #!CGADSUB_AddBg1Backdrop
    STA.b CGADSUB-!DP_PPU
    LDA.b #!COLDATA_AllZero
    STA.b COLDATA-!DP_PPU
    LDA.b #!TM_Bg1
    STA.b TM-!DP_PPU
    LDA.b #!C3_Prog10Mode4Sub
    STA.b TS-!DP_PPU
    LDA.b #!C3_Prog10Mode4
    STA.b BGMODE-!DP_PPU
    LDA.b #!C3_Prog10Mode4Bg2Sc
    STA.b BG2SC-!DP_PPU
    LDA.b #!C3_Prog10Mode4Tiles
    STA.b BG12NBA-!DP_PPU
    LDA.b #!C3_Prog10Bg3Sc
    STA.b BG3SC-!DP_PPU
    LDA.b #!C3_Prog10Mode4Win
    STA.b W12SEL-!DP_PPU
    LDA.b #!C3_Prog10Mode4SubWin
    STA.b TSW-!DP_PPU
    LDA.b #0
    STA.b WH0-!DP_PPU
    STA.b WH2-!DP_PPU
    LDA.b #0
    STA.b SETINI-!DP_PPU
    LDY.w #C3Mod_Prog10HdmaWindow
    JSR C3Mod_SetupHdma
    LDA.b #1
    STA.w !C3_HdmaEnable
    JMP C3Mod_NmiTaskEnd

; $7E:8E88 — C3Mod_Prog10Bg2VofsNmi (13 bytes, $8E88–$8E94)
; An NMI task: BG2VOFS = page $0A00's var 2 (low byte, then high).
; Callers note: an NMI task added by script opcode $F8 at $92F3 (a
;   script not matched yet).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X any, DP any, DB=$00.
; Exit:  M=1; A = var 2's high byte; X, Y unchanged.
C3Mod_Prog10Bg2VofsNmi:
    LDA.w !C3_ScriptPageA+!C3_Prog10Var2
    STA.w BG2VOFS
    LDA.w !C3_ScriptPageA+!C3_Prog10Var2+1
    STA.w BG2VOFS
    RTS
; $7E:8E95 — C3Mod_Prog12 (19 bytes, $8E95–$8EA7)
; The program of C3Mod_ProgramTable entry 12: page $0B00's var 0 =
; $FFFE; SETINI = 1 (screen interlace); $B0 (BCS) written over the BCC
; at $9EE3 (code not matched yet: the branch on STAT78's field bit
; there, the other field then); then C3Mod_Prog13's .setup (BRA).
; Callers note: C3Mod_ProgramTable entry 12 (C3Mod_Start's JSR (table,X)
;   at $300A).
; Entry: M=1, X=0, DP=0, DB=$00 (as C3Mod_Start calls the programs).
; Exit:  as C3Mod_Prog13's.
C3Mod_Prog12:
    LDX.w #!C3_Prog12Var0
    STX.w !C3_ScriptPageB+!C3_Prog10SprSize
    LDA.b #!C3_Prog12Setini
    STA.w SETINI
    LDA.b #!Op_BCS
    STA.l C3Mod_Unk9EE3
    BRA C3Mod_Prog13_setup

; $7E:8EA8 — C3Mod_Prog13 (322 bytes with its .setup, $8EA8–$8FE9)
; The program of C3Mod_ProgramTable entry 13: driver command $F6 with
; Audio_CmdArg0 = 1 (C3Mod_AudioSend); C3_Prog13Count ($00AD, 8-bit)
; + 1; page $0B00's var 0 = $FFF9; then .setup ($8EBE), both
; programs':
;   - C3Mod_InitStars; FdVec_FFEE (PalAnim_StopAll); Decomp_Dest's high
;     byte and Decomp_DestBank = 0 (bank $7E), C3_RowCount = $20 (DP =
;     0): raw pack 56 to $7E:2020 (C3_PaletteWork's colours $10-$1F);
;   - C3Mod_DestBitmapSrc; C3_DmaMode = 1, C3_DmaBbad = VMDATAL, VMAIN =
;     $80: pack 71 ($800 bytes: BG1's map) to VRAM word $6000, pack 17
;     ($200) to $4600, pack 58 to $4000 with Decomp_OutLen set to $200
;     first (only its first $200 of $400 bytes sent), pack 47 ($A00) to
;     $5000 (BG1's tiles, with BG12NBA $05);
;   - raw pack 19 to $7E:2120 (colours $90-$9F, C3_RowCount $20);
;     C3Mod_Prog10Greys; C3Mod_CommitPalette;
;   - VMADD = $4800 (BG3's map with BG3SC $48), VMAIN = 0: $400 zero low
;     bytes (C3Mod_VramFillLow); VMADD = $4800, VMAIN = $80: $400 high
;     bytes from the fixed byte $20 at $7E:9E7A (as in
;     C3Mod_Prog10GridNmi): tile 0, priority, everywhere; the HDMA
;     channel of C3Mod_Prog10HdmaGrid, C3_HdmaEnable = channel 0;
;   - 16-bit, DB = $7E (PEA $007E / PLB; the $00 stays for the PLB
;     after): C3Mod_Prog4ToEnd (C3Mod_StarsTask's BMI made a BRA, page
;     $0A00's pointer to C3Mod_Prog4End), then page $0A00's pointer =
;     $93E3 (not matched yet) and its script once (C3Mod_ScriptTaskA);
;     8-bit: $12 written over the low byte of the two STA BG2VOFS
;     operands at $9F23 and $9F28 (code not matched yet: they store
;     to BG3VOFS then); DB = $00 (PLB);
;   - DP = DP_PPU: BG1HOFS = $0090, BG1VOFS = $0048 (low, then high
;     byte), BG12NBA = $05, BG34NBA = $04, BG1SC = $60, BG3SC = $48,
;     BGMODE = 1, CGADSUB = $84 (subtract, on BG3), TM = $14 (BG3 and
;     the sprites), TS = 0, TMW = TSW = 0; DP = 0: C3_Prog10TextPtr =
;     $AB1A (in C3Mod_StaffTexts' second text, at its
;     "PRODUCER//KAZUHIKO AOKI" part), C3_Prog10TextY = -$20 (16-bit
;     absolute stores); song $1B (C3Mod_PlaySong).
; Sub-entry: .setup ($8EBE), from C3Mod_Prog12 (BRA).
; Callers note: C3Mod_ProgramTable entry 13 (C3Mod_Start's JSR (table,X)
;   at $300A). .setup: C3Mod_Prog12 (BRA).
; Entry: M=1, X=0, DP=0, DB=$00 (as C3Mod_Start calls the programs).
; Exit:  M=1, X=0, DP=0, DB=$00; A and X as C3Mod_PlaySong leaves them
;        (X = C3_SongArgs); Y as C3Mod_SetupHdma left it.
; Calls: C3Mod_AudioSend, C3Mod_InitStars, FdVec_FFEE (JSL),
;   C3Mod_CopyRawPack, C3Mod_DestBitmapSrc, C3Mod_UnpackPack,
;   C3Mod_DmaUnpacked (JSL), C3Mod_Prog10Greys, C3Mod_CommitPalette,
;   C3Mod_VramFillLow, C3Mod_SetupHdma, C3Mod_Prog4ToEnd,
;   C3Mod_ScriptTaskA, C3Mod_PlaySong.
C3Mod_Prog13:
    LDA.b #!C3_Prog13Cmd
    STA.w !Audio_CmdId
    LDA.b #1
    STA.w !Audio_CmdArg0
    JSR C3Mod_AudioSend
    INC.w !C3_Prog13Count
    LDX.w #!C3_Prog13Var0
    STX.w !C3_ScriptPageB+!C3_Prog10SprSize
.setup:
    JSR C3Mod_InitStars
    JSL !FdVec_FFEE
    LDX.w #0
    STX.w !Decomp_Dest+1                ; and Decomp_DestBank
    LDX.w #!C3_Prog10StarColoursBytes
    STX.b !C3_RowCount
    LDY.w #!C3_Prog10Colours10
    LDX.w #56*!C3_PackPtrBytes
    JSR C3Mod_CopyRawPack
    JSR C3Mod_DestBitmapSrc
    LDA.b #!DMAP_TwoRegs
    STA.w !C3_DmaMode
    LDA.b #!BBAD_VMDATAL
    STA.w !C3_DmaBbad
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    LDX.w #!C3_Prog10FillMap
    STX.w VMADDL
    LDX.w #71*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DmaUnpacked
    LDX.w #!C3_Prog10StarTiles
    STX.w VMADDL
    LDX.w #17*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DmaUnpacked
    LDX.w #!C3_SprTilesVram
    STX.w VMADDL
    LDX.w #58*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    LDX.w #!C3_Prog10GridTileBytes
    STX.w !Decomp_OutLen
    JSL C3Mod_DmaUnpacked
    LDX.w #!C3_SprTilesHigh
    STX.w VMADDL
    LDX.w #47*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DmaUnpacked
    LDX.w #0
    STX.w !Decomp_Dest+1                ; and Decomp_DestBank
    LDX.w #!C3_Prog10StarColoursBytes
    STX.b !C3_RowCount
    LDY.w #!C3_Prog10StarColours
    LDX.w #19*!C3_PackPtrBytes
    JSR C3Mod_CopyRawPack
    JSR C3Mod_Prog10Greys
    JSR C3Mod_CommitPalette
    LDX.w #!C3_Prog10GridBgMap
    STX.w VMADDL
    STZ.w VMAIN
    LDX.w #!C3_Prog10GridMapBytes
    JSR C3Mod_VramFillLow
    LDX.w #!C3_Prog10GridBgMap
    STX.w VMADDL
    LDX.w #!C3_Prog10GridMapBytes
    STX.w DAS7L
    LDX.w #!BBAD_VMDATAH<<8|!DMAP_FixedSource
    STX.w DMAP7                         ; and BBAD7
    LDX.w #C3Mod_Unk9E7A
    STX.w A1T7L
    LDA.b #!VMAIN_IncAfterHigh
    STA.w VMAIN
    STA.w MDMAEN                        ; MDMAEN_Ch7, the same value
    LDY.w #C3Mod_Prog10HdmaGrid
    JSR C3Mod_SetupHdma
    LDA.b #1
    STA.w !C3_HdmaEnable
    REP #$20
    PEA.w !Bank7E                       ; PLB takes the $7E; the $00 stays for the PLB after
    PLB
    JSR C3Mod_Prog4ToEnd
    LDX.w #C3Mod_Unk93E3
    STX.w !C3_ScriptPageA+!C3Script_Ptr
    JSR C3Mod_ScriptTaskA
    SEP #$20
    LDA.b #BG3VOFS-!DP_PPU
    STA.w C3Mod_Unk9F22+1
    STA.w C3Mod_Unk9F27+1
    PLB
    PEA.w !DP_PPU
    PLD
    LDA.b #!C3_Prog13Bg1Hofs
    STA.b BG1HOFS-!DP_PPU
    STZ.b BG1HOFS-!DP_PPU
    LDA.b #!C3_Prog13Bg1Vofs
    STA.b BG1VOFS-!DP_PPU
    STZ.b BG1VOFS-!DP_PPU
    LDA.b #!C3_Prog13Tiles12
    STA.b BG12NBA-!DP_PPU
    LDA.b #!C3_Prog13Tiles34
    STA.b BG34NBA-!DP_PPU
    LDA.b #!C3_Prog13Bg1Sc
    STA.b BG1SC-!DP_PPU
    LDA.b #!C3_Prog13Bg3Sc
    STA.b BG3SC-!DP_PPU
    LDA.b #!C3_BgMode1
    STA.b BGMODE-!DP_PPU
    LDA.b #!C3_Prog13Math
    STA.b CGADSUB-!DP_PPU
    LDX.w #!C3_Prog13Screens
    STX.b TM-!DP_PPU                    ; and TS
    LDX.w #0
    STX.b TMW-!DP_PPU                   ; and TSW
    PEA.w 0
    PLD
    LDX.w #!C3_Prog10TextB
    STX.w !C3_Prog10TextPtr
    LDX.w #!C3_Prog10TextYStart
    STX.w !C3_Prog10TextY
    LDA.b #!C3_Prog13Song
    JSR C3Mod_PlaySong
    RTS

; $7E:8FEA — C3Mod_Prog10Hdma (36 bytes, $8FEA–$900D)
; C3Mod_Prog10's HDMA channels (C3Mod_SetupHdma's records): 0 and 1 the
; mode-7 matrix (C3Mod_M7HdmaAB / HdmaCD), 2 BG1HOFS / BG1VOFS
; (indirect, two registers each written twice: C3Mod_Prog10Scroll), 3
; TM / TS / TMW / TSW (indirect, four registers: C3Mod_Prog10Screens),
; 4 BGMODE (indirect: C3Mod_Prog10Mode); then .fill ($9003), the list
; C3Mod_Prog10Fill sets up, also this one's tail: 5 (or 0) WH0 / WH1
; (direct, two registers: C3Mod_Prog10Window), 6 (or 1) CGADSUB /
; COLDATA (indirect, two registers: C3Mod_MathHdma); the end.
; C3Mod_Prog10 enables channels 0-4 only, C3Mod_Prog10Fill channel 0.
C3Mod_Prog10Hdma:
    db !DMAP_HdmaIndirect|!DMAP_TwoRegsTwice, !BBAD_M7A : dw C3Mod_M7HdmaAB : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegsTwice, !BBAD_M7C : dw C3Mod_M7HdmaCD : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegsTwice, !BBAD_BG1HOFS : dw C3Mod_Prog10Scroll : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_FourRegs, !BBAD_TM : dw C3Mod_Prog10Screens : db !Bank7E
    db !DMAP_HdmaIndirect, !BBAD_BGMODE : dw C3Mod_Prog10Mode : db !Bank7E
.fill:
    db !DMAP_TwoRegs, !BBAD_WH0 : dw C3Mod_Prog10Window : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegs, !BBAD_CGADSUB : dw C3Mod_MathHdma : db !Bank7E
    db !C3_HdmaListEnd

; $7E:900E — C3Mod_Prog10HdmaStrip (21 bytes, $900E–$9022)
; C3Mod_Prog10Strip's: 0 BGMODE (C3Mod_Prog10ModeStrip), 1 WH0 / WH1
; (direct: C3Mod_Prog10Window), 2 BG1HOFS / BG1VOFS
; (C3Mod_Prog10Scroll), 3 TS (indirect, one register:
; C3Mod_Prog10ScreenB); the end.
C3Mod_Prog10HdmaStrip:
    db !DMAP_HdmaIndirect, !BBAD_BGMODE : dw C3Mod_Prog10ModeStrip : db !Bank7E
    db !DMAP_TwoRegs, !BBAD_WH0 : dw C3Mod_Prog10Window : db !Bank7E
    db !DMAP_HdmaIndirect|!DMAP_TwoRegsTwice, !BBAD_BG1HOFS : dw C3Mod_Prog10Scroll : db !Bank7E
    db !DMAP_HdmaIndirect, !BBAD_TS : dw C3Mod_Prog10ScreenB : db !Bank7E
    db !C3_HdmaListEnd

; $7E:9023 — C3Mod_Prog10HdmaGrid (6 bytes, $9023–$9028)
; C3Mod_Prog10GridNmi's and C3Mod_Prog13's: 0 COLDATA (indirect, one
; register) from the table at $A00C (not matched yet); the end.
C3Mod_Prog10HdmaGrid:
    db !DMAP_HdmaIndirect, !BBAD_COLDATA : dw C3Mod_UnkA00C : db !Bank7E
    db !C3_HdmaListEnd

; $7E:9029 — C3Mod_Prog10HdmaWindow (6 bytes, $9029–$902E)
; C3Mod_Prog10Mode4Nmi's: 0 WH0 / WH1 (indirect, two registers) from
; C3Mod_Prog10WindowTable; the end.
C3Mod_Prog10HdmaWindow:
    db !DMAP_HdmaIndirect|!DMAP_TwoRegs, !BBAD_WH0 : dw C3Mod_Prog10WindowTable : db !Bank7E
    db !C3_HdmaListEnd

; $7E:902F — C3Mod_Prog10Mode (10 bytes, $902F–$9038)
; BGMODE (C3Mod_Prog10Hdma channel 4): mode 1 (C3Mod_ModeHdma's .mode1
; byte) for the first two entries' lines (0 as assembled;
; C3Mod_Prog10SplitNmi writes them: page $0A00's var 6 lines in all),
; then one line of mode 7 (.mode7), held to the bottom; the end.
C3Mod_Prog10Mode:
    db 0 : dw C3Mod_ModeHdma_mode1
    db 0 : dw C3Mod_ModeHdma_mode1
    db 1 : dw C3Mod_ModeHdma_mode7
    db 0

; $7E:9039 — C3Mod_Prog10ModeStrip (10 bytes, $9039–$9042)
; BGMODE (C3Mod_Prog10HdmaStrip channel 0): mode 7 for the first two
; entries' lines (C3Mod_Prog10Strip / StripNmi write them), then mode 1
; held; the end.
C3Mod_Prog10ModeStrip:
    db 0 : dw C3Mod_ModeHdma_mode7
    db 0 : dw C3Mod_ModeHdma_mode7
    db 1 : dw C3Mod_ModeHdma_mode1
    db 0

; $7E:9043 — C3Mod_Prog10Scroll (10 bytes, $9043–$904C)
; BG1HOFS / BG1VOFS (four bytes a line): C3_Prog10TopHofs / TopVofs
; ($140C, $140E) for the first two entries' lines (written by
; C3Mod_Prog10Strip, StripNmi and SplitNmi), then C3_Prog10LowHofs /
; LowVofs ($1404, $1406) for one line, held; the end.
C3Mod_Prog10Scroll:
    db 0 : dw !C3_Prog10TopHofs
    db 0 : dw !C3_Prog10TopHofs
    db 1 : dw !C3_Prog10LowHofs
    db 0

; $7E:904D — C3Mod_Prog10Screens (10 bytes, $904D–$9056)
; TM / TS / TMW / TSW (C3Mod_Prog10Hdma channel 3): .top for the first
; two entries' lines (C3Mod_Prog10SplitNmi), then .low for one line,
; held; the end.
C3Mod_Prog10Screens:
    db 0 : dw C3Mod_Prog10ScreenValues
    db 0 : dw C3Mod_Prog10ScreenValues
    db 1 : dw C3Mod_Prog10ScreenValues_low
    db 0

; $7E:9057 — C3Mod_Prog10ScreenB (10 bytes, $9057–$9060)
; TS (C3Mod_Prog10HdmaStrip channel 3): C3Mod_Prog10ScreenValues' first
; byte ($10: the sprites) for the first two entries' lines, then the
; $00 of C3Mod_FillBytes ($350B), held; the end.
C3Mod_Prog10ScreenB:
    db 0 : dw C3Mod_Prog10ScreenValues
    db 0 : dw C3Mod_Prog10ScreenValues
    db 1 : dw C3Mod_FillBytes+1
    db 0

; $7E:9061 — C3Mod_Prog10ScreenValues (8 bytes, $9061–$9068)
; TM, TS, TMW, TSW above the split ($10, $10, 0, 0: the sprites only)
; and under it (.low: $11, $10, $11, 0: BG1 and the sprites, the
; window on both on the main screen).
C3Mod_Prog10ScreenValues:
    db !TM_Obj, !TM_Obj, 0, 0
.low:
    db !Layer_Bg1Obj, !TM_Obj, !Layer_Bg1Obj, 0

; $7E:9069 — C3Mod_Prog10WindowTable (7 bytes, $9069–$906F)
; WH0 / WH1 for C3Mod_Prog10HdmaWindow: 112 lines (repeat) from
; $7E:E000, 112 from $7E:E0E0; the end.
C3Mod_Prog10WindowTable:
    db !C3_HdmaRepeat112 : dw !C3_Prog10WindowLines
    db !C3_HdmaRepeat112 : dw !C3_Prog10WindowLines+$E0
    db 0

; $7E:9070 — C3Mod_Prog10Window (16 bytes, $9070–$907F)
; A direct HDMA table for WH0 / WH1 (two bytes a line, after each
; count): window 1 shut (left 1, right 0) for the first two entries'
; lines (56 + 56 as assembled), then .third and .fourth (112 lines
; each as assembled, a left and right edge), then one shut line; the
; end. Two writers rewrite the counts and edges:
;   - C3Mod_Prog10SprNmi: the first two counts = the sprite picture's
;     top line / 2 and that + its bit 0; .third / .fourth's counts $10
;     or $20 (by C3_Prog10Large); edges C3_SprBaseX and + $40 ($FF
;     when that carries);
;   - the task at $9C58 (added by script opcode $FA at $9125, $91BF and
;     $9203; code not matched yet; M=1 there): the left edges ($9C77,
;     $9C7B) = -(page $0B00's var 1 + the byte at $6D) (8-bit, EOR /
;     INC), the right edges ($9C82, $9C86) = that + the byte at $AB
;     (CLC); the first two counts ($9C96, $9C9C) = -(var 2 + the byte
;     at $6F) / 2 and that + the LSR's carry; .third / .fourth's counts
;     ($9CA3, $9CA9) = the byte at $AC / 2 and that + the carry.
C3Mod_Prog10Window:
    db 56, 1, 0
.second:
    db 56, 1, 0
.third:
    db 112, 0, 1
.fourth:
    db 112, 0, 1
    db 1, 1, 0
    db 0

; $7E:9080 — C3Mod_Prog10SplitNmi (39 bytes, $9080–$90A6)
; An NMI task: the split line s = page $0A00's var 6's low byte: s / 2
; (8-bit LSR, C = s's bit 0) to the first counts of C3Mod_Prog10Mode,
; C3Mod_Prog10Screens, C3Mod_Prog10Scroll and C3Mod_MathHdma (long
; stores), s / 2 + C (ADC #0) to their second counts: s lines in all
; above the split.
; Callers note: an NMI task added by script opcode $F8 at $90DE, $9465
;   and $9631 (scripts not matched yet).
; Entry: an NMI task (C3Mod_RunNmiTasks): M=1, X any, DP any, DB=$00
;        (page $0A00 is absolute; the stores are long).
; Exit:  M=1; A = s / 2 + C; X, Y unchanged.
C3Mod_Prog10SplitNmi:
    LDA.w !C3_ScriptPageA+!C3_Prog10Split
    LSR A
    STA.l C3Mod_Prog10Mode
    STA.l C3Mod_Prog10Screens
    STA.l C3Mod_Prog10Scroll
    STA.l C3Mod_MathHdma
    ADC.b #0
    STA.l C3Mod_Prog10Screens+3
    STA.l C3Mod_Prog10Mode+3
    STA.l C3Mod_Prog10Scroll+3
    STA.l C3Mod_MathHdma+3
    RTS

%C3ModOrg($7E90A7)
; $7E:90A7 — C3Mod_VramFillLow (26 bytes with C3Mod_VramFill, $90A7–$90C0)
; Fills VRAM from the address the caller set with the zero byte of
; C3Mod_FillBytes ($7E:350B) by DMA channel 7: X bytes, DMAP / BBAD =
; Y (C3Mod_VramFillLow: $1808, fixed source, one register, VMDATAL:
; only the low bytes, as VMAIN steps). C3Mod_VramFill ($90AA) takes Y
; from the caller ($1809 at its calls: two registers, whole words).
; Sub-entry: C3Mod_VramFill ($90AA).
; Callers note: C3Mod_Prog4 ($5476), C3Mod_Prog10 ($85B2),
;   C3Mod_Prog10GridNmi ($8D89) and C3Mod_Prog13 ($8F57). C3Mod_VramFill:
;   C3Mod_Prog10Fill ($8A53, $8A6C) and $9F84 (code not matched yet).
; Entry: M=1, X=0 (16-bit X and Y), DP any, DB = a bank with the I/O
;        registers: $00 at C3Mod_Prog4's call ($5476), C3Mod_Prog10's
;        ($85B2), C3Mod_Prog10Fill's ($8A53, $8A6C: after its PEA $7E00
;        / PLB), C3Mod_Prog10GridNmi's ($8D89) and C3Mod_Prog13's
;        ($8F57); $9F84's not traced;
;        X = the byte count, VMADD and VMAIN set. C3Mod_VramFill: the
;        same, Y = DMAP7 | BBAD7 << 8.
; Exit:  M=1, X=0; A = MDMAEN_Ch7, X = C3Mod_FillBytes + 1, Y = the DMAP
;        / BBAD word; VMADD past the fill.
C3Mod_VramFillLow:
    LDY.w #!BBAD_VMDATAL<<8|!DMAP_FixedSource
C3Mod_VramFill:                         ; header: see C3Mod_VramFillLow
    STX.w DAS7L
    STY.w DMAP7                         ; and BBAD7
    LDX.w #C3Mod_FillBytes+1
    STX.w A1T7L
    LDA.b #!Bank7E
    STA.w A1B7
    LDA.b #!MDMAEN_Ch7
    STA.w MDMAEN
    RTS

%C3ModOrg($7E90C1)
C3Mod_Rest90C1:
    %C3ModRomBytes($7E90C1, $7EA651)

; $7E:A651 — C3Mod_StaffTexts (3,886 bytes, $A651–$B57E)
; The staff credits the module shows, in two texts to the module's end:
;   - $A651-$AADA: "PRODUCER/KAZU`KO AOKI@DIRECTOR/..." up to "...KANAME
;     TANAKA@" and a $00: names after their job, "/" between names, "@"
;     between jobs, "`" standing for HI (and "[", "]", "^", "_" for
;     other pairs of letters, probably); C3Mod_Prog10 ($86BF, $86D1)
;     stores $A651 in C3_ResultWord ($0382) when C3_EntryArg bits 0-3
;     are $A ($86BF) or $B ($86D1);
;   - $AADB on: a $1C, then "XEXECUTIVE PRODUCER/..." to the end, the
;     same list with "/" between names, then "CHRONO TRIGGER", the
;     translators, test players and special thanks ("X" and the $1C
;     are probably control bytes); C3_Prog10TextPtr gets $AB1A
;     (C3Mod_Prog13: its "PRODUCER//KAZUHIKO AOKI" part) or $B099
;     (C3Mod_Prog10GridNmi: "//////TRANSLATOR"), for code not matched
;     yet;
;   - it ends with the module's end marker "\CODE END 7E" (as the kernel
;     ends with "CODE END C3").
; The copy code C3_BuildCopyCode writes at run time ($B574) overwrites
; the last bytes (GENERATED in tools/c3module.py).
%C3ModOrg($7EA651)
C3Mod_StaffTexts:
    db "PRODUCER/KAZU`KO AOKI@DIRECTOR/TAKAS` TOKITA/YOS`NORI KI"
    db "TASE/AKI`KO MATSUI@CHARACTER DESIGN/AKIRA TORIYAMA@SUPER"
    db "VISOR/YUJI HORII/`RONOBU SAKAGUC`@MUSIC/YASUNORI MITSUDA"
    db "/NOBUO UEMATSU@MAIN PROGRAM/KEIZO KOKUBO/KATSU`SA `GUC`@"
    db "SOUND PROGRAM/MINORU AKAO@SOUND ENGINEER/EIJI NAKAMURA@G"
    db "RAP`C DIRECTOR/YASU`KO KAMATA/MASANORI HOS`NO/TETSUYA TA"
    db "K]^_`@STORY PLAN/MASATO KATO@EVENT PLAN/`ROYUKI ITOU/KEI"
    db "SUKE MATSUHARA/`ROKI C`BA@FIELD PLAN/KEITA ETO/KENIC` NI"
    db "S`@BATTLE PLAN/MAKOTO S`MAMOTO/HARUYUKI NIS`DA/TOS`AKI S"
    db "UZUKI@BATTLE PROGRAM/TOS`O ENDO/KIYOS` YOS`I@WORLDMAP PR"
    db "OGRAM/KAZUMI KOBAYAS`@MENU PROGRAM/AKI`RO S`MIZU@VISUAL "
    db "PROGRAM/KOJI SUGIMOTO/KEN NARITA@EFFECT GRAP`C/`ROKATSU "
    db "SASAKI/YUKIO NAKATANI@FIELD GRAP`C/S`NIC`RO OKANIWA/MANA"
    db "BU DAIS`MA/TOS`YA HASUI/MATSUZO ITAKURA@FIELD GRAP`C/TET"
    db "SUYA NOMURA/KAZU`RO OKAWA/YOS`NORI OGURA@FIELD GRAP`C/YU"
    db "SUKE NAORA/TAKAMIC` S`BUYA/S`NIC`RO HAMASAKA/AKIYOS` MAS"
    db "UDA@FIELD GRAP`C/MASAAKI HAYAS`/TAKAYUKI ODAC`/YASUYUKI "
    db "HONNE@CHARACTER GRAP`C/`ROS` UC`YAMA/TAIZO INUKAI/FUMI N"
    db "AKAS`MA@MONSTER GRAP`C/KOUIC` EBE/TSUTOMU TERADA/TADA`RO"
    db " USUDA@MAP DESIGN/MAMI KAWAI/AKANE HARUKI/`ROTO YAMAMOTO"
    db "@MAP DESIGN/`DETOS` KEZUKA/KANAME TANAKA@"
    db $00
    db $1C
    db "XEXECUTIVE PRODUCER/TETSUO MIZUNO/`TOS` TAKEMURA/`SAS` S"
    db "UZUKI@PRODUCER//KAZUHIKO AOKI/////DIRECTOR//TAKASHI TOKI"
    db "TA/YOSHINORI KITASE/AKIHIKO MATSUI/////CHARACTER DESIGN/"
    db "/AKIRA TORIYAMA/////SUPERVISOR//YUJI HORII/HIRONOBU SAKA"
    db "GUCHI/////MUSIC//YASUNORI MITSUDA/NOBUO UEMATSU/////MAIN"
    db " PROGRAM//KEIZO KOKUBO/KATSUHISA HIGUCHI/////SOUND PROGR"
    db "AM//MINORU AKAO/////SOUND ENGINEER//EIJI NAKAMURA/////GR"
    db "APHIC DIRECTOR//YASUHIKO KAMATA/MASANORI HOSHINO/TETSUYA"
    db " TAKAHASHI/////STORY PLAN//MASATO KATO/////EVENT PLAN//H"
    db "IROYUKI ITOU/KEISUKE MATSUHARA/HIROKI CHIBA/////FIELD PL"
    db "AN//KEITA ETO/KENICHI NISHI/////BATTLE PLAN//MAKOTO SHIM"
    db "AMOTO/HARUYUKI NISHIDA/TOSHIAKI SUZUKI/////BATTLE PROGRA"
    db "M//TOSHIO ENDO/KIYOSHI YOSHII/////WORLDMAP PROGRAM//KAZU"
    db "MI KOBAYASHI/////MENU PROGRAM//AKIHIRO SHIMIZU/////VISUA"
    db "L PROGRAM//KOJI SUGIMOTO/KEN NARITA/////EFFECT GRAPHIC//"
    db "HIROKATSU SASAKI/YUKIO NAKATANI/////FIELD GRAPHIC//SHINI"
    db "CHIRO OKANIWA/MANABU DAISHIMA/TOSHIYA HASUI/MATSUZO ITAK"
    db "URA//TETSUYA NOMURA/KAZUHIRO OKAWA/YOSHINORI OGURA/YUSUK"
    db "E NAORA/TAKAMICHI SHIBUYA/SHINICHIRO HAMASAKA/AKIYOSHI M"
    db "ASUDA/MASAAKI HAYASHI/TAKAYUKI ODACHI/YASUYUKI HONNE////"
    db "/CHARACTER GRAPHIC//HIROSHI UCHIYAMA/TAIZO INUKAI/FUMI N"
    db "AKASHIMA/////MONSTER GRAPHIC//KOUICHI EBE/TSUTOMU TERADA"
    db "/TADAHIRO USUDA/////MAP DESIGN//MAMI KAWAI/AKANE HARUKI/"
    db "HIROTO YAMAMOTO/HIDETOSHI KEZUKA/KANAME TANAKA/////EXECU"
    db "TIVE PRODUCER//TETSUO MIZUNO/HITOSHI TAKEMURA/HISASHI SU"
    db "ZUKI//////////////////////////////////      CHRONO TRIGG"
    db "ER//////////\\//////TRANSLATOR//TED WOOLSEY//WEIMIN LI/"
    db "AIKO ITO/RIKA MARUYA/NORIKO WADA/////SOUND EFFECT//YOSHITA"
    db "KA HIROTA/CHIHARU MINEKAWA/TADAKAZU OKANO/YASUAKI YABUTA"
    db "/////TEST PLAYER//KENICHI SHINODA/KEN SAKUYAMA/TOMOKO MO"
    db "RIYASU/HARUO OGURA/HIROTSUGU YAMAMOTO/REO NOMOTO/AKIHIRO"
    db " ICHIKAWA/AKITOSHI TAKAHASHI/////////ADVERTISEMENT//K[YA"
    db "MASHITA/Y[HIRATA/T[NOMURA/K[SOUSUI/T[TSURUZONO/M[OKAMIYA"
    db "/N[WATANABE/K[MAEDA/M[MIZUSHIMA/////SYSTEM ADMINISTER//M"
    db "[NAKAJIMA/M[OGURA/Y[ORIKASA/Y[OHDAIRA/////TEST COORDINAT"
    db "OR//S[KAJITANI/R[KODA/K[INAGI/N[HANADA/H[MASUDA/N[KANAI/"
    db "H[SAKURAI/////SPECIAL THANKS//K[TORISHIMA///N[HORIE/F[TA"
    db "KEDA/T[TAKAHASHI/T[KONDOH//S[HASHIMOTO////K[ADACHI/Y[KUW"
    db "AHARA/H[OKAWA/Y[UENISHI///N[MATSUEDA/I[DOBASHI/M[SAITO/H"
    db "[KAWAI///S[MORIYA/K[SUZUKI/T[KONDO/S[TANAKA////K[TANIKAW"
    db "A/J[SAITO/S[HIDAKI/K[OOGO/H[SUZUKI/M[ITOH/R[MIYAMOTO///H"
    db "[YOKOTA/M[YUMOTO/N[ISHIKAWA/H[KIZUKA/S[ARAI/K[MATSUMOTO/"
    db "K[HIRATA/M[KOUNO/R[TSUKAKOSHI/K[KANEKO/H[SHIMODAIRA/M[NO"
    db "UMURA/A[HINO/H[HAMADA///T[OHNO/H[NOGUCHI/M[HORIE/M[MORI/"
    db "M[KOBAYASHI///M[KANESHIGE/M[SOMENO/Y[TANAKA/R[TAKEDA///T"
    db "[MORITA/Y[SUEMITSU/W[SATO/H[NAKAMURA/S[AOYAMA/H[NAGAHARA"
    db "/H[SHINGU///R[SILVEIRA/J[YANAGIHARA/T[HORII/D[SMITH/C[CH"
    db "AMBERLAIN/E[GREGORY/D[ABRAHAM/C[BUDD/M[FREGUIA//////////"
    db "///////////////////////\\CODE END 7E"

incsrc "unmatched.asm"
