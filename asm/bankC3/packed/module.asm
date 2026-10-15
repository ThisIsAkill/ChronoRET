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
; routine's address over its operand ($3024: $51D1 at $3CE4, $7441 at
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
;     C3_Brightness, C3_HdmaEnable, C3_Unk0380/0381/0366 = 0;
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
    STZ.w !C3_Unk0380
    STZ.w !C3_Unk0381
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
; $F8 bit 7 is set (the callers leave $F8 as it is).
; Callers note: C3Mod_MulSigned16 ($33F0) and $3591, $35A7, $35C9,
;   $35E8, $4F4A, $56DE, $5BE7, $5C05, $5C22, $5CCD, $5CF0, $6025, $99CB
;   and $99EB (code not matched yet).
; Entry: M=0 (16-bit A for the product reads), X=0 (X and Y are pushed
;        and pulled as words), DP = the page of C3Math_A.. (the
;        script's page at C3Mod_BuildM7Tables' calls $3591-$35E8, the
;        caller's own at C3Mod_MulSigned16's; the others' not traced),
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
; Callers note: $4E30, $4E43, $4E55, $4EAB, $4EBF, $8210 and $896E (code
;   not matched yet).
; Entry: M=0, X any, DP = the page of C3Math_A.. (0 at the calls); DB
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
; at their bottom is not used).
; Callers note: $5C44 (code not matched yet).
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
; signs differed.
; Callers note: $4458, $446B, $4E61, $4ECB, $9939, $9953, $9B0A and
;   $9B1D (code not matched yet).
; Entry: M=0, X=0 (C3Mod_Mul16's), DP = the page of C3Math_A.. (0 at the
;        calls); DB any; C3Math_A, C3Math_B = the signed operands.
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
; Callers note: $577A, $5780, $5786, $57B3, $57B9, $7397, $7F85, $7FA0,
;   $80A6, $80D3, $98E3 and $98EE (code not matched yet).
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
; boundary (0 at the calls).
; Callers note: $3F59 (a script routine), $65AE, $65BF, $65C9, $728E
;   and $9BE1 (code not matched yet).
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
; The sine of the angle in A (1,024 steps per turn) as a signed 16-bit
; value of magnitude 0-$FF from Rom_SineTable's |sin| bytes, negative
; for angles $000-$1FF and positive for $200-$3FF (so -sin, probably
; for the screen's downward y). C3Mod_Cosine adds a quarter turn and
; falls into C3Mod_Sine ($3465).
; Callers note: $357F, $444F, $4D19, $56B6, $5867, $5BD7, $5BFB, $5CBC,
;   $73C9, $76DB, $994A, $9990, $99DB and $9B01 (code not matched yet).
;   C3Mod_Sine: $35B7, $4462, $4D26, $56C2, $585B, $5C11, $5CE0, $6014,
;   $73BD, $73FD, $76FE, $9930, $9983, $99BB and $9B14 (code not
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
; Callers note: a task: LDX #C3Mod_FadeInTask / JSR $395E at $6BD8;
;   added by script opcode $FA at $3F29, $554C, $6399, $6905, $7C93,
;   $918E, $933D, $9403, $9528 and $966B, removed by $F9 at $92C1 and
;   $961F (code and scripts not matched yet).
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
; Callers note: a task added by script opcode $FA at $41F6, $423F,
;   $9149, $91A0, $91F5, $9280, $94E6 and $96CB, and by LDX
;   #C3Mod_FadeOutTask / JSR $395E at $63E8 (code and scripts not
;   matched yet).
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
; Callers note: a task added by script opcode $FA at $5B92 and by LDX
;   #C3Mod_MusicFadeTask / JSR $395E at $5BA9 (M=1; code and script not
;   matched yet).
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
; Callers note: a task added by script opcode $FA at $562F, $6978,
;   $727F, $7EC1, $931F and $95FE, by LDX #C3Mod_FadeOutExitTask / JSR
;   $395E at $4684, and by LDX #C3Mod_FadeOutExitTask / JMP
;   C3Mod_TaskReplace at $6BF3 (code and scripts not matched yet).
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
; registers, so whole words cleared), $5AEE (DMAP $08 to VMDATAL: one
; register, only the low bytes cleared) and $90B0 (DMAP/BBAD from Y:
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
; Callers note: $53E1 (code not matched yet).
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
; M7D = the scaled cosine / X and M7B = -M7C = the scaled sine / X (the
; signs as the angle gives them): a ground plane in perspective,
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
;     columns in the order that puts the negated sine in M7C, by the
;     sine's sign;
;   - then the JSR at .setup calls the routine whose address the caller
;     wrote over its operand ($35FD; the assembled $0000 is
;     never called): $45B0, $801F, $8042 or $9B46 (not matched yet)
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
; Callers note: JMP (a tail call) from $4306, $82F2 and $9AF0 (code not
;   matched yet; script routines, with their page as DP).
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
; Callers note: $3B69, $3B75, $3BEF, $3DBF, $3DD1, $3DEA, $3DF7, $3E19,
;   $3E29, $3E39, $3E7D, $3E93, $3EA9, $53D2, $541B, $543A, $544A,
;   $5989, $599D, $59B9, $59C9, $59FA, $6259, $626B, $627F, $6295,
;   $62AA, $62B6, $62C2, $62D1, $6C3F, $78F2, $7905, $7945, $7987,
;   $7ADE, $7AFD, $7B0D, $8549, $857B, $8598, $85A5, $85C3, $85E4,
;   $85F0, $869B, $87B0, $87E9, $8A2C, $8A46, $8A5F, $8A78, $8A8A,
;   $8BE4, $8C48, $8C76, $8C8E, $8CF8, $8D04, $8D10, $8EF4, $8F04,
;   $8F14 and $8F2A (code not matched yet).
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
; Callers note: $540A, $5488, $5493, $7963, $8663, $866C, $8675, $867E,
;   $868C, $8841, $884A, $8AC1, $8BFC, $8E0B, $8E14, $8ED6 and $8F42
;   (code not matched yet).
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
; Callers note: $3C49, $67AD, $70E0, $7A2A, $7A5D, $8714, $8ACD, $8B12,
;   $8DAF, $8E7D and $8F7D (code not matched yet).
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
; Callers note: JSR from $3CD8, $54B4, $5A0A, $62F0, $6792, $70CE, $79AA,
;   $86E6 and $8F94 (code not matched yet); a task: the tables at $7EC7
;   and $7EDC (C3_TaskList), and the scripts' opcode $FA at $3F1A,
;   $4130, $5540, $5B05, $6393, $6984, $7157, $931C, $932E and $93E3.
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
;   tables at $7EC7 and $7EDC, and the scripts' opcode $FA at $3F1D,
;   $4133, $5543, $6987, $715A and $9331.
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
; Callers note: $3B5A, $5AA7 and $8FE6 (code not matched yet).
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
;   $318F, $3197, $319F, $31AD JMP) and $426D, $4BC8, $63E5 and $8EB2
;   (code not matched yet).
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
;   Its JSL callers each call C3Mod_UnpackPack ($3691) first (code not
; matched yet), which probably puts the picture at $7F:0200.
; Callers note: JSL from $3DED, $3DFA, $7908 and $87B3 (code not
;   matched yet).
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
; Callers note: JSL from $544D, $859B, $85A8 and $8A8D (code not
;   matched yet).
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
;   added by the scripts' opcode $FA at $5B0B, $6396, $6993, $7D04,
;   $7EB3, $9334 and $93E9 (removed again by $F9 at $7D0C).
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
;   $4145, $554F, $5B20, $639C, $699C, $7181, $7C73, $9325 and $93EC.
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
;   once a frame in vblank) added by script opcode $F8 at $3F32, $4148,
;   $5B23, $639F, $7184, $7C76, $9328 and $93EF (scripts not matched
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
;   yet); an NMI task (C3Mod_RunNmiTasks, once a frame in vblank) added
;   by script opcode $F8 at $5B1D, $63A2, $6999, $717E, $7CF9, $7EB6,
;   $932B and $93F5, and removed by $F7 at $7D0F (scripts not matched
;   yet).
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
; Callers note: $3DC2, $59FD, $62EB, $796F, $869E, $87A1, $8AC4, $8BFF,
;   $8C94, $8E17 and $8F48 (code not matched yet).
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
; Callers note: JSL from $3DDD, $3E1C, $3E2C, $3E3C, $3E86, $3E9C,
;   $3EB2, $53F7, $543D, $5996, $59A6, $59C2, $5AB2, $6278, $6288,
;   $6298, $6C48, $78FE, $7AF6, $7B06, $8586, $85D0, $8A39, $8A49,
;   $8A62, $8BE7, $8C51, $8EF7, $8F07, $8F1D and $8F2D (code not
;   matched yet; most right after C3Mod_UnpackPack).
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
; Callers note: $482E and $4879 (code not matched yet).
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
; Callers note: $4687, $4834, $489D, $5BAC, $5D54, $63EB, $6BDB and
;   $6BE1 (code not matched yet).
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
; Callers note: $46A1, $4897, $48BD, $48D7, $8652 and $9C69 (code not
;   matched yet).
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
;   C3Mod_FadeOutStopTask ($34E0), C3Mod_FadeOutExitTask ($34F8), and
;   $44F8, $48A6, $5BBB, $5BCB, $5CB7, $5D47, $6ACA, $9A9F, $9B7B and
;   $9EF9 (code not matched yet).
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
;   C3Mod_MusicFadeTask ($34BF, after LDX #C3Mod_FadeOutStopTask), and
;   $427F, $476E, $485A, $63F1, $6A71, $6A94, $6BF6 and $98A9 (code not
;   matched yet).
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
; Callers note: JMP from NMI tasks (the trace follows them): $4674,
;   $7A32, $7A65, $8DF0, $8E85, $9D22, $9F56 and $9F87 (code not matched
;   yet); also a JMP byte pattern at $78A8, right after the RTS at
;   $78A7, which no trace reaches (probably dead).
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
; Callers note: $5187 and $51AE (code not matched yet).
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
C3Mod_Rest3B48:
    %C3ModRomBytes($7E3B48, $7EA651)

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
