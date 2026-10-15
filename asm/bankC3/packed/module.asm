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
; routine's address over its operand ($3024: C3Mod_ScaleIdle at $3CE4, $7441 at
; $70D7, $8278 at $79B7, $8930 at $8794 and $87D0, and back to
; C3Mod_Return at $96FE), so the loop runs that routine once per pass
; between frames; C3Mod_Return, the default, does nothing (an RTS).
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
; Callers note: C3Mod_Start ($3010) and $710F (code not matched yet).
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
;   ($4EAB, $4EBF) and $8210 and $896E (code not matched yet).
; Entry: M=0, X any, DP = the page of C3Math_A.. (0 at the five
;        C3Mod_Size* calls; $8210's and $896E's not traced); DB
;        any; A = the dividend, C3Math_B = the divisor (not 0).
; Exit:  A = the remainder, C3Math_Lo = the quotient; C3Math_A shifted
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
;   ($57B3, $57B9) and $7397, $7F85, $7FA0, $80A6, $80D3, $98E3 and
;   $98EE (code not matched yet).
; Entry: M, X, DP and DB as C3_RandomByte needs; X=0 at the calls, M=1
;        at $577A, $5780, $5786, $57B3, $57B9, $7397 and $80A6, M=0 at
;        $7F85, $7FA0, $80D3, $98E3 and $98EE (there C3_RandomByte's adds
;        are 16-bit, it stores a word to C3_RandSeed, and the callers
;        mask the result with an AND).
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
; boundary ($0A00 at C3Mod_PickRun's call, the script's page; the
; others' not traced).
; Callers note: C3Mod_PickRun ($3F59, a script routine) and $65AE,
;   $65BF, $65C9, $728E and $9BE1 (code not matched yet).
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
;   C3Mod_SwingTask ($5CBC) and $73C9, $76DB,
;   $994A, $9990, $99DB and $9B01 (code not matched yet). C3Mod_Sine:
;   C3Mod_BuildM7Tables ($35B7), C3Mod_ViewOffsetTask ($4462),
;   C3Mod_ProjectTask ($4D26), C3Mod_SpinTask ($56C2),
;   C3Mod_StarDriftTask ($585B), C3Mod_RockTask ($5C11),
;   C3Mod_SwingTask ($5CE0), C3Mod_WaveTask ($6014) and $73BD, $73FD,
;   $76FE, $9930, $9983, $99BB and $9B14 (code not matched yet).
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
; Callers note: a task: LDX #C3Mod_FadeInTask / JSR $395E at $6BD8;
;   added by script opcode $FA at $3F29 (C3Mod_Prog0ScriptA), $554C
;   (C3Mod_Prog4ScriptA), $6399, $6905, $7C93, $918E, $933D, $9403, $9528
;   and $966B, removed by $F9 at $92C1 and $961F (the others: code and
;   scripts not matched yet).
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
;   $63E8 (the others: code and scripts not matched yet).
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
;   (C3Mod_Prog4End), $6978, $727F, $7EC1, $931F and $95FE, by LDX
;   #C3Mod_FadeOutExitTask / JSR $395E at $4684 (C3Mod_RaceTask), and by
;   LDX #C3Mod_FadeOutExitTask / JMP C3Mod_TaskReplace at $6BF3 (the
;   others: code and scripts not matched yet).
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
; Callers note: $7699 (code not matched yet).
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
; VRAM fills at $3D9D (DMAP $09 to VMDATAL: fixed address, two
; registers, so whole words cleared), $5AEE (C3Mod_MapToM7: DMAP $08
; to VMDATAL, one register, only the low bytes cleared; C3Mod_Prog2's
; fill after it keeps that source with DMAP $09) and $90B0 (DMAP/BBAD from Y:
; $1808 when entered at $90A7, $1809 from the callers of $90AA, at
; $8A50, $8A69 and $9F81); the $FF bytes around it have no reader found
; (probably fill bytes too).
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
; Callers note: $8A7E (code not matched yet).
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
; HDMA records at $3D4A, $7B9C, $7BBB and $8FEA (in C3Mod_SetupHdma's
; lists) name $355F; no reader of $3566 was found.
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
; the HDMA records at $3D4F, $7BA1, $7BC0 and $8FEF. C3Mod_M7HdmaCDNext
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
;     never called): C3Mod_Prog0Setup ($45B0), $801F, $8042 or $9B46
;     (not matched yet)
;     set the first divisor X and the first line's offset Y for their
;     view; $801F and $8042 also write the end offset over .end's CPY
;     operand ($3637).
; The loop's step is self-modifying too: the INX / NOP at .step can be
; INX / INX or DEX / DEX ($8066, $8051), NOP / INX ($45D1), or a BRA to
; one of the variants after the loop (a word of C3Mod_M7StepBranches):
;   - .blank_line: the next line all zeros (a blank line between each
;     two), X + 1;
;   - .double_d: this line's M7D doubled, X + 1;
;   - .stream_x: X = the next byte of a WRAM stream (WMDATA, set up by
;     $801F at $7E:E260): the distances come from a table;
;   - .copy_line: the next line a copy of this one, X + 2 (half the
;     vertical resolution).
; Quirk: the STX to WRDIVB writes 16 bits, so HTIMEL ($4207) gets X's
; high byte (0) each time.
; Callers note: JMP (a tail call) from C3Mod_ViewTask ($4306) and $82F2
;   and $9AF0 (code not matched yet): tasks that set DP = $0A00
;   themselves (LDA #$0A00 / TCD at $42CE, $82D1 and $9ABD).
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
; .copy_line. $368D is copied there at $7A0C, $368F at $45C5; no
; reader of the first two was found.
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
;   $599D, $59B9, $59C9, $59FA) and $6259, $626B, $627F, $6295, $62AA,
;   $62B6, $62C2, $62D1, $6C3F, $78F2, $7905, $7945, $7987, $7ADE, $7AFD,
;   $7B0D, $8549, $857B, $8598, $85A5, $85C3, $85E4, $85F0, $869B, $87B0,
;   $87E9, $8A2C, $8A46, $8A5F, $8A78, $8A8A, $8BE4, $8C48, $8C76, $8C8E,
;   $8CF8, $8D04, $8D10, $8EF4, $8F04, $8F14 and $8F2A (code not matched
;   yet).
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
; Callers note: C3Mod_Prog4 ($540A, $5488, $5493) and $7963, $8663,
;   $866C, $8675, $867E, $868C, $8841, $884A, $8AC1, $8BFC, $8E0B,
;   $8E14, $8ED6 and $8F42 (code not matched yet).
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
; Callers note: C3Mod_Prog0 ($3C49) and $67AD, $70E0, $7A2A, $7A5D,
;   $8714, $8ACD, $8B12, $8DAF, $8E7D and $8F7D (code not matched yet).
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
;   C3Mod_Prog2 ($5A0A) and $62F0, $6792, $70CE, $79AA, $86E6 and $8F94
;   (code not matched yet); a task: the tables at $7EC7 and $7EDC
;   (C3_TaskList), and the scripts' opcode $FA at $3F1A
;   (C3Mod_Prog0ScriptA), $4130 (C3Mod_Prog0Start), $5540
;   (C3Mod_Prog4ScriptA), $5B05 (C3Mod_Prog2Script), $6393, $6984,
;   $7157, $931C, $932E and $93E3.
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
; Callers note: JSR from $70D1 (code not matched yet); a task: the
;   tables at $7EC7 and $7EDC, and the scripts' opcode $FA at $3F1D
;   (C3Mod_Prog0ScriptA), $4133 (C3Mod_Prog0Start), $5543
;   (C3Mod_Prog4ScriptA), $6987, $715A and $9331.
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
; Callers note: C3Mod_Prog0 ($3B5A), C3Mod_Prog2 ($5AA7) and $8FE6
;   (code not matched yet).
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
;   C3Mod_RaceStepTask ($4BC8) and $63E5 and $8EB2 (code not matched
;   yet).
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
; Stretches a 64 x 64-byte bitmap in bank $7F to twice its height: each
; 64-byte row of $7F:0200-$11FF (C3_BitmapSrc) is copied twice in a row
; to $7F:2200-$41FF (C3_BitmapDest), 128 rows (two MVNs per row, the
; source pointer saved for the second). The row count lives in the
; caller's direct page (C3_RowCount). What the bitmap is (probably a
; picture for C3_ScaleBitmap, which reads 64-byte rows) is not traced.
;   Its JSL callers each call C3Mod_UnpackPack ($3691) first; at
; C3Mod_Prog0LoadGfx's calls ($3DED, $3DFA) that puts the pack at
; $7F:0200 (C3Mod_Unk89ED set Decomp_Dest there); at $7908 and $87B3
; (code not matched yet), probably the same.
; Callers note: JSL from C3Mod_Prog0LoadGfx ($3DED, $3DFA) and $7908
;   and $87B3 (code not matched yet).
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
; Callers note: JSL from C3Mod_Prog4 ($544D) and $859B, $85A8 and
;   $8A8D (code not matched yet).
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
; Callers note: JSR from $8319 and $8355 (code not matched yet); a task
;   added by the scripts' opcode $FA at $5B0B (C3Mod_Prog2Script), $6396,
;   $6993, $7D04, $7EB3, $9334 and $93E9 (removed again by $F9 at $7D0C).
; Entry: a task: M=0 (8-bit set here), X=0, DP=0 (C3_ScratchF0 is
;        direct page), DB = $00 (the registers are absolute).
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
; Callers note: an NMI task added by the scripts' opcode $F8 at $3F2F,
;   $4145, $554F (C3Mod_Prog4ScriptA), $5B20 (C3Mod_Prog2Script), $639C,
;   $699C, $7181, $7C73, $9325 and $93EC.
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
; not touched). M7B is set back to 0 after.
; Callers note: C3Mod_Init ($30F6); an NMI task (C3Mod_RunNmiTasks,
;   once a frame in vblank) added by script opcode $F8 at $3F32
;   (C3Mod_Prog0ScriptA), $4148 (C3Mod_Prog0Start), $5B23
;   (C3Mod_Prog2Script), $639F,
;   $7184, $7C76, $9328 and $93EF (the others: scripts not matched
;   yet).
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
; Callers note: C3Mod_Start ($300D) and $8AC7, $8C97 (code not matched
;   yet); an NMI task (C3Mod_RunNmiTasks, once a frame in vblank) added by
;   script opcode $F8 at $5B1D (C3Mod_Prog2Script), $63A2, $6999, $717E,
;   $7CF9, $7EB6, $932B and $93F5, and removed by $F7 at $7D0F (scripts
;   not matched yet).
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
; Callers note: C3Mod_Prog0LoadGfx ($3DC2), C3Mod_Prog2 ($59FD) and
;   $62EB, $796F,
;   $869E, $87A1, $8AC4, $8BFF, $8C94, $8E17 and $8F48 (code not
;   matched yet).
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
; Callers note: JSL from $792F and $7933 (code not matched yet).
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
;   $59A6, $59C2), C3Mod_MapToM7 ($5AB2) and $6278, $6288, $6298, $6C48,
;   $78FE, $7AF6, $7B06, $8586, $85D0, $8A39, $8A49, $8A62, $8BE7, $8C51,
;   $8EF7, $8F07, $8F1D and $8F2D (code not matched yet; most right after
;   C3Mod_UnpackPack).
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
;   C3Mod_RaceStepTask ($489D), C3Mod_SkipTask ($5BAC),
;   C3Mod_FirstPicTask ($5D54) and $63EB, $6BDB and $6BE1
;   (code not matched yet).
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
;   $48BD, $48D7) and $8652 and $9C69 (code not matched yet).
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
;   ($5CB7), C3Mod_FirstPicTask ($5D47), and $6ACA, $9A9F, $9B7B and $9EF9
;   (code not matched yet).
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
;   C3Mod_RaceFinish ($485A), and $63F1, $6A71, $6A94, $6BF6 and $98A9
;   (code not matched yet).
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
;   C3Mod_ClearColumnTask ($4674), and $7A32, $7A65, $8DF0, $8E85,
;   $9D22, $9F56 and $9F87 (code not matched yet); also a JMP byte
;   pattern at $78A8, right after the RTS at $78A7, which no trace
;   reaches (probably dead).
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
; Callers note: JSL from $7F9C, $7FB0, $7FBF, $8386 and $9A6A (code not
;   matched yet).
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
;   - pack 5 to C3_PaletteWork ($00:2000, Decomp_DestBank = 0) and
;     C3Mod_CommitPalette;
;   - C3Mod_Unk89ED: Decomp_Dest = $7F:0200 (C3_BitmapSrc) for the
;     rest; pack 7 to VRAM's high bytes from word 0 (VMAIN = $80 as
;     left by the clear: C3_DmaMode 0, C3_DmaBbad VMDATAH: the mode-7
;     tiles), packs 8 and 9 each doubled in height (C3Mod_DoubleRows)
;     and sent by C3Mod_Unk8752 (from VMADD 0 on; probably the mode-7
;     map in the low bytes, not traced);
;   - VMAIN = $80, two registers (VMDATAL/H): packs 13 and 14 to words
;     $7000 and $7100 (the BG tiles, BG12NBA = BG34NBA = $77), pack 6
;     to $5000 (the sprites' second tile page);
;   - $7E:E100-$E13F zeroed (a word stored, then an overlapping MVN),
;     $7F:0300-$09FF filled from MPYL by DMA (B to A; 0 if M7A x M7B
;     is, as C3Mod_Prog0's fills);
;   - the first $800 bytes (Decomp_OutLen set) of pack 10 to word
;     $6000, of pack 12 to $6800 and of pack 11 to $6400 (the maps of
;     BG1, BG3 and BG2: BG1SC $60, BG3SC $68, BG2SC $64).
; Callers note: C3Mod_Prog0 ($3B5D).
; Entry: M=1, X=0, DP with a low byte of 0 (the TDC that makes
;        C3_DmaMode 0; DP=0 at the call; the DMA arguments are
;        absolute), DB=$00 (absolute register and RAM stores).
; Exit:  M=1, X=0, DP and DB unchanged (the MVN's DB restored);
;        Decomp_DestBank = $7F, Decomp_Dest = C3_BitmapSrc;
;        C3_DmaMode = DMAP_TwoRegs, C3_DmaBbad = VMDATAL; A =
;        MDMAEN_Ch7, X = Decomp_OutLen ($0800), Y = $E140 (past the
;        MVN; Decomp_ToWram restores it).
; Calls: C3Mod_UnpackPack, C3Mod_CommitPalette, C3Mod_Unk89ED,
;   C3Mod_DmaUnpacked (JSL), C3Mod_DoubleRows (JSL), C3Mod_Unk8752.
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
    JSR C3Mod_Unk89ED
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
    JSR C3Mod_Unk8752
    LDX.w #9*!C3_PackPtrBytes
    JSR C3Mod_UnpackPack
    JSL C3Mod_DoubleRows
    JSR C3Mod_Unk8752
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
;   C3Mod_MirrorRows3 ($3ECD, $3ED0) and $8813, $8816 (code not matched
;   yet).
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
; .wipe_mode's operand (C3Mod_Prog0 writes 2 there, $683F writes 1),
; plays effect $BA (C3_SndSfxA) by C3Mod_AudioSend unless C3_SongBusy,
; sets C3_ExitTimer = 32 and C3_Unk7F0062 = 0 and hands over to
; C3Mod_ExitCountTask.
; Callers note: a task added by script opcode $FA at $405E
;   (C3Mod_Prog0WipeA), $40D9 (C3Mod_Prog0WipeB) and $68BD (code not
;   matched yet).
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
    LDA.b #!WinFx_C3EMode2              ; written by C3Mod_Prog0 and $683F
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
; mode 1 and 7.
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
; The HDMA record at $9008 (DMAP $41 to CGADSUB, in code not matched
; yet) points here too (its address at $900A), and $9090 and $90A2
; write the first and second counts ($452B, $452E), as
; C3Mod_HorizonNmiTask does ($4506, $4515).
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
; (half colour math on the sprites: the bottom of the screen; $87A6
; writes $05 over that CGADSUB byte), .sky: $42 / black (half on BG2),
; .fade: 32 pairs of $91
; (subtract, on BG1 and the sprites) with all three colours at 31 down
; to 0; C3Mod_MathHdma uses the last 15 (14 down to 0) under the
; horizon.
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
;     C3Mod_Unk90A7: a fixed zero to VMDATAL);
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
;   C3Mod_Unk90A7, C3Mod_ScriptTaskA, C3Mod_InitStars.
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
    JSR C3Mod_Unk90A7
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
;   from $8F8B (code not matched yet).
; Entry: M=0, X any, DP any, DB = $7E (the stores are absolute: the
;        code's bank for $582E; from the script, C3Mod_ScriptTaskB's
;        PHK / PLB, which C3_RunScript keeps; at $8F8B, its PEA $007E /
;        PLB).
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
; Callers note: C3Mod_Prog4 ($54BE) and $8BCB, $8EBE (code not matched
;   yet).
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
; The carries: the first depth add takes the carry as the task is
; entered (0 from C3Mod_TaskNext's CPX unless it is the list's first
; task), each next star the CPY's (0, Y below $200); the + $80 the
; CMP's (the sum >= $7F, unsigned) or the ADC's, or C3Mod_KernelRandom's
; after a new place; the X and Y adds the carry out of the one before.
; Quirk: C3_StarDivisor is C3_Prog9's byte ($44) reused.
; Callers note: a task added by script opcode $FA at $5546
;   (C3Mod_Prog4ScriptA) and $93E6 (script not matched yet); JMP from
;   $99B2 (code not matched yet: the code from $999C first, when
;   C3_OamPos - $100 has bit 15 set (CMP / BPL), calls $3870 and sets
;   C3_OamPos = $100, C3_OamHiPtr = $0910).
; Entry: a task (C3Mod_RunTasks): M=0 (8-bit set here), X=0 (16-bit
;        index), DP=0 (C3_OamPos, C3_StarDivisor), DB=$00 (the star
;        tables, the OAM shadow, the divider and page $0B00's words are
;        absolute).
; Exit:  M=1, X=0; A = the last star's OAM Y; Y = $200 (C3_StarBytes:
;        the loop ends on Y = $200 exactly, BEQ; C3_OamPos is a multiple
;        of 4); X unchanged; C3_RandSeed changed.
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
; Callers note: $7662 (code not matched yet).
; Entry: M any (REP #$20 here), X=0 (16-bit X and Y), DP = a page whose
;        C3_TmpF0/F2 the routine may use (the caller's, not traced), DB
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
;   - C3Mod_Unk89ED: the packs go to $7F:0200 (C3_BitmapSrc); VMAIN =
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
;   - pack 27 to C3_PaletteWork ($00:2000, Decomp_DestBank = 0) and
;     C3Mod_CommitPalette;
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
; Calls: C3Mod_Unk89ED, C3Mod_UnpackPack, C3Mod_DmaUnpacked (JSL),
;   C3Mod_TilesToM7, C3Mod_MapToM7, C3Mod_CommitPalette,
;   C3Mod_ScriptTaskA, FdVec_FFEE (JSL), C3Mod_PlaySong.
C3Mod_Prog2:
    JSR C3Mod_Unk89ED
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
; Callers note: C3Mod_Prog2 ($59D2) and $8C7F (code not matched yet).
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
; Callers note: script opcode $F0 at $5B83 (C3Mod_Prog2Wave) and $637A
;   and $63BF (scripts not matched yet).
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
; $8C5D / $8C63 (code not matched yet) write C3Mod_Tile8ToM7 over the
; JSR's operand (.convert + 1) and $8C69 writes $30 over the step's low
; byte (.step + 1: 16 + $30 = 64 bytes an 8bpp tile).
; Callers note: C3Mod_Prog2 ($59B3) and $8C70 (code not matched yet).
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
    JSR C3Mod_Tile4ToM7                 ; $8C5D / $8C63 write C3Mod_Tile8ToM7 here
    REP #$21
    TXA
.step:
    ADC.w #!C3_Tile4Skip                ; $8C69 writes $30 here
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
; Callers note: C3Mod_TilesToM7 ($5E43, the JSR that $8C5D / $8C63 may
;   patch).
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
;   $8C5D and $8C63, code not matched yet).
; Entry: M=1, X=0, DP = C3_TileRow's page (0: the code before $8C70
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
C3Mod_Rest6248:
    %C3ModRomBytes($7E6248, $7EA651)

; $7E:A651 — C3Mod_StaffTexts (3,886 bytes, $A651–$B57E)
; The staff credits the module shows, in two texts to the module's end:
;   - $A651-$AADA: "PRODUCER/KAZU`KO AOKI@DIRECTOR/..." up to "...KANAME
;     TANAKA@" and a $00: names after their job, "/" between names, "@"
;     between jobs, "`" standing for HI (and "[", "]", "^", "_" for
;     other pairs of letters, probably); $86BF and $86D1 load $A651
;     as a text pointer (into $0382) when C3_EntryArg bits 0-3 are $A
;     ($86BF) or $B ($86D1);
;   - $AADB on: a $1C, then "XEXECUTIVE PRODUCER/..." to the end, the
;     same list with "/" between names, then "CHRONO TRIGGER", the
;     translators, test players and special thanks; no reader of it was
;     found ("X" and the $1C are probably control bytes);
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
