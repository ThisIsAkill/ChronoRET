; ============================================================
; SPC700 sound driver (bank $C7 boot block 0)
; ROM $C7:24C3: a length word ($1BEF), then the program, $C7:24C5-$40B3,
; which Audio_Boot sends through the IPL ROM to ARAM $0200-$1DEE and
; starts at $0200 (Audio_BootBlockPtrs / Audio_BootBlockAram).
;
; Assembled in asar's spc700 mode: %SpcOrg(aram) puts the bytes at the
; ROM address of an ARAM address (ROM = $C7:24C5 + aram - $0200) while
; labels take the ARAM address (asar's `base`). Every direct-page and
; absolute operand has an explicit .b / .w width.
;
; Layout of the block (tools/spc700.py traces it from $0200 and the
; dispatch tables; NEXT.md, the SPC700 item, has the evidence):
;   $0200-$1543  code
;   $1544-$1721  tables: transfer modes, sequence commands $C4-$FF (handlers,
;                operand counts, second handlers), CPU commands
;                (Spc_CmdTable10, Spc_CmdFirstTable10, Spc_CmdTable80), the
;                DSP shadow lists (Spc_ShadowRegs / Spc_ShadowSources)
;   $1722-$1D6C  code (sequence command handlers and helpers)
;   $1D6D-$1DEE  tables (pitch, FIR sets, ...) and Spc_BuiltinSample
; Matched so far: $0200-$0376, $07A3-$07AE, $0B96-$0E10. The rest of the
; block (and its length word) is still original bytes; the names this
; code uses there are in asm/spc700/unmatched.asm.
;
; Header convention (STYLE.md's, with the SPC700's state):
;   Entry/Exit: P (the direct-page flag: P=0 puts the direct page at
;   $0000, P=1 at $0100), A, X, Y (YA for word results), SP when moved,
;   and the PSW flags callers branch on; the DSP registers written
;   ("DSP:") and the port protocol with the 65816 side ("Ports:") where
;   a routine reads or writes CPUIO0-3. The driver runs with I=0
;   (interrupts are never used: DI at the start) and P=0 except where a
;   header says otherwise.
; Callers are hand-written (`; Callers note:`): tools/callers.py and
; tools/xref.py read 65816 code only.
; ============================================================

macro SpcOrg(aram)
    base off
    org !AudioRom_SpcDriver+2+<aram>-!AudioAram_Driver
    base <aram>
endmacro

arch spc700

; ============================================================
; Start and main loop ($0200-$0376)
; ============================================================

; $0200 — Spc_Start (153 bytes, $0200–$0298; ROM $C7:24C5–$255D)
; The driver's entry point: the IPL ROM jumps here when Audio_Boot's
; last step names $0200. It sets the stack, clears the direct page
; $00-$EF and sets up:
;   - !Spc_CurSong, !Spc_SavedSong and !Spc_NewSong = $FF (none);
;   - echo volume 0 (EVOLL/EVOLR), the !Spc_CmdQueue entries free;
;   - DIR = the page of !AudioAram_Dir, every voice's GAIN =
;     !DSP_GAIN_Start;
;   - the port latches cleared, timer 0 every 5.25 ms (one main-loop
;     pass), timer 1 every 16 ms, both on;
;   - the echo delay !Spc_StartEchoDelay through command $FC's handler
;     (Spc_CmdSetEchoDelay with !Spc_CmdArg0 = 5);
;   - !Spc_KofShadow = $FF (every voice keyed off on the first pass),
;     !Spc_FadeTimer = 7, the three !Spc_GroupVol volumes $FF with no
;     fade running;
;   - directory entry !Spc_BuiltinDirEntry ($1E40) = Spc_BuiltinSample /
;     Spc_BuiltinSampleLoop, its ParamB word $FF $E0 ($1FA0) and its
;     ParamA word $E1 $00 ($1F20) (boot block 3 holds entries 0-8, a
;     song load writes entries $20-$2F);
;   - main volume !DSP_MVOL_Start on both sides, !Spc_UnkD8 = 2;
; then falls into Spc_MainLoop.
; Callers note: no CALL or JMP; reached from the IPL ROM (Audio_Boot).
; Entry: SP, P, A, X, Y any (all set here); ARAM as the boot blocks left
;        it
; Exit:  falls into Spc_MainLoop with P=0, I=0, SP=$FF, X=0, A =
;        !DSP_MVOL_Start, Y = !DSP_MVOLR
; DSP:   EVOLL, EVOLR, DIR, GAIN of voices 0-7, MVOLL, MVOLR (and what
;        Spc_CmdSetEchoDelay writes)
; Callees: Spc_WriteDsp, Spc_CmdSetEchoDelay
%SpcOrg($0200)
Spc_Start:
    clrp
    di
    mov x,#!Spc_StackTop
    mov sp,x
    mov a,#$00
    mov x,a
.clear:
    mov (x+),a
    cmp x,#!Spc_ClearEnd
    bne .clear
    dec.b !Spc_CurSong                  ; $FF: none
    decw.b !Spc_SavedSong               ; and !Spc_NewSong: $FF
    mov y,#!DSP_EVOLL
    call Spc_WriteDsp
    mov y,#!DSP_EVOLR
    call Spc_WriteDsp
    mov x,#!Spc_QueueBytes
.free_queue:
    mov.w !Spc_CmdQueue-!Spc_QueueEntry+x,a ; the entry's id byte
    dec x
    dec x
    dec x
    dec x
    bne .free_queue
    mov a,#!AudioAram_Dir>>8
    mov y,#!DSP_DIR
    call Spc_WriteDsp
    mov y,#!DSP_GAIN
    mov x,#!DSP_GAIN_Start
.gain:
    mov.b !SPC_DSPADDR,y
    mov.b !SPC_DSPDATA,x
    mov a,y
    clrc
    adc a,#!DSP_VoiceStride
    mov y,a
    bpl .gain                           ; voices 0-7 ($07-$77)
    mov.b !SPC_CONTROL,#!SPC_CONTROL_ClearPorts
    mov.b !SPC_T0TARGET,#!SPC_Timer0Divider
    mov.b !SPC_T1TARGET,#!SPC_Timer1Divider
    mov.b !SPC_CONTROL,#!SPC_CONTROL_Timers01
    mov.b !Spc_CmdArg0,#!Spc_StartEchoDelay
    call Spc_CmdSetEchoDelay
    dec.b !Spc_KofShadow                ; $FF: key off every voice on the first pass
    mov.b !Spc_FadeTimer,#!Spc_FadeTicks
    mov x,#6                            ; groups 2, 1, 0 (X = 2 x (group + 1))
.groups:
    mov a,#$FF
    mov.w !Spc_GroupVol+1-2+x,a         ; the volume (high byte)
    inc a
    mov.w !Spc_GroupFadeSteps-2+x,a     ; no fade running
    dec x
    dec x
    bne .groups
    mov a,#Spc_BuiltinSample&$FF
    mov.w !Spc_BuiltinDir,a
    mov a,#Spc_BuiltinSample>>8
    mov.w !Spc_BuiltinDir+1,a
    mov a,#Spc_BuiltinSampleLoop&$FF
    mov.w !Spc_BuiltinDir+2,a
    mov a,#Spc_BuiltinSampleLoop>>8
    mov.w !Spc_BuiltinDir+3,a
    mov a,#!Spc_BuiltinParamB0
    mov.w !Spc_BuiltinParamB,a
    mov a,#!Spc_BuiltinParamB1
    mov.w !Spc_BuiltinParamB+1,a
    mov a,#!Spc_BuiltinParamA0
    mov.w !Spc_BuiltinParamA,a
    mov a,#!Spc_BuiltinParamA1
    mov.w !Spc_BuiltinParamA+1,a
    mov a,#!DSP_MVOL_Start
    mov y,#!DSP_MVOLL
    call Spc_WriteDsp
    mov y,#!DSP_MVOLR
    call Spc_WriteDsp
    mov.b !Spc_UnkD8,#!Spc_UnkD8Start

; $0299 — Spc_MainLoop (222 bytes, $0299–$0376; ROM $C7:255E–$263B)
; The driver's loop: one pass per tick of timer 0 (5.25 ms).
;   1. Spc_PollCommand until timer 0 has ticked (a command that came in
;      runs at once).
;   2. Writes the 17 DSP registers of Spc_ShadowRegs from their shadows
;      (Spc_ShadowSources: FIR7 ... FIR0 from !Spc_FirShadow, EFB, EVOLR
;      and EVOLL from !Spc_EvolShadow, EON, KOF, FLG, NON, PMON, KON last),
;      then clears !Spc_KonShadow and !Spc_KofShadow. !Spc_EvolShadow is
;      !Spc_EchoVolume, doubled when !Spc_Flags87 bit 3 is set (to $7F
;      only when the shift carries out: a volume of $40-$7F doubles to
;      $80-$FE). Quirk: the BRA after `mov a,#!Spc_EvolMax` branches to
;      the next instruction.
;   3. Unless !Spc_Flags88 bit 7 is set (then Spc_Unk1438 instead), the
;      ports the 65816 reads: CPUIO0 = 0, CPUIO1 = the song's fade steps
;      left (!Spc_GroupFadeSteps), CPUIO2 = !Spc_UnkD3 (nibbles swapped)
;      OR !Spc_Unk7B, CPUIO3 = the voices in use: (!Spc_SongTracks' two
;      nibbles ORed, low nibble) OR !Spc_SfxVoices.
;   4. With !Spc_Flags87 bit 4 set, back to 1. Every 7th pass
;      (!Spc_FadeTimer) the fades (Spc_Unk1492); then the tempo step
;      (Spc_Unk0377) and the queued commands (Spc_Unk08CD); bit 4 again.
;   5. The song's tracks (voice bits !Spc_SongTracks AND !Spc_Unk24,
;      less !Spc_SfxVoices), X = 0, 2, ...: Spc_Unk0903, or Spc_Unk09F6
;      while any effect plays, with !Spc_GroupVolume = the song's volume;
;      Spc_Unk0892 after each.
;   6. The effect tracks (!Spc_SfxVoices AND !Spc_Unk25), X = $1E down:
;      tracks 15-14 with the second volume, 13-8 with the third,
;      Spc_Unk0903 and Spc_Unk0892 for each.
;   7. Clears !Spc_UnkD0/!Spc_UnkD1, runs the queue again (Spc_Unk08CD)
;      and Spc_Unk0B5C, and goes back to 1.
; Callers note: Spc_Start falls in; JMP from Spc_StartSong ($0CF3, with
;   SP reset); the pass loops back here (JMP $0374, BEQ/BBS inside).
; Entry: P=0; SP as Spc_Start or Spc_StartSong leaves it
; Exit:  does not return
; Ports: CPUIO0-3 as in 3; commands through Spc_PollCommand
; DSP:   the 17 shadowed registers each pass
; Callees: Spc_PollCommand, Spc_Unk1438, Spc_Unk1492, Spc_Unk0377,
;   Spc_Unk08CD, Spc_Unk0903, Spc_Unk09F6, Spc_Unk0892, Spc_Unk0B5C
Spc_MainLoop:
    call Spc_PollCommand
    mov.b y,!SPC_T0OUT
    beq Spc_MainLoop
    mov y,#!Spc_NumShadowRegs
    mov.b a,!Spc_EchoVolume
    bbc.b !Spc_Flags87.3,.set_evol
    asl a
    bcc .set_evol
    mov a,#!Spc_EvolMax
    bra .set_evol                       ; to the next instruction
.set_evol:
    mov.b !Spc_EvolShadow,a
.write_dsp:
    mov.w a,Spc_ShadowRegs-1+y
    mov.b !SPC_DSPADDR,a
    mov.w a,Spc_ShadowSources-1+y
    mov x,a
    mov a,(x)
    mov.b !SPC_DSPDATA,a
    dbnz y,.write_dsp
    mov.b !Spc_KofShadow,y
    mov.b !Spc_KonShadow,y
    bbs.b !Spc_Flags88.7,.report
    mov.b a,!Spc_SongTracks
    xcn a
    or.b a,!Spc_SongTracks
    and a,#$0F                          ; voice n or n+4
    or.b a,!Spc_SfxVoices
    mov y,a
    mov.b a,!Spc_UnkD3
    xcn a
    or.b a,!Spc_Unk7B
    movw.b !SPC_CPUIO2,ya
    mov.w y,!Spc_GroupFadeSteps
    mov a,#$00
    movw.b !SPC_CPUIO0,ya
    bra .ports_done
.report:
    call Spc_Unk1438
.ports_done:
    bbs.b !Spc_Flags87.4,Spc_MainLoop
    dec.b !Spc_FadeTimer
    bne .no_fade
    mov.b !Spc_FadeTimer,#!Spc_FadeTicks
    call Spc_Unk1492
.no_fade:
    call Spc_Unk0377
    call Spc_Unk08CD
    bbs.b !Spc_Flags87.4,Spc_MainLoop
    mov x,#$00
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit0
    mov.b a,!Spc_SfxVoices
    eor a,#$FF
    and.b a,!Spc_SongTracks
    and.b a,!Spc_Unk24
    mov.b !Spc_TrackBits,a
    mov.w a,!Spc_GroupVol+1             ; group 0: the song
    mov.b !Spc_GroupVolume,a
    bra .song_next
.song_track:
    mov.b !Spc_CurTrack,x
    mov.b a,!Spc_SfxVoices
    bne .with_sfx
    call Spc_Unk0903
    bra .song_stepped
.with_sfx:
    call Spc_Unk09F6
.song_stepped:
    call Spc_Unk0892
.song_skip:
    inc x
    inc x
    asl.b !Spc_VoiceBit
.song_next:
    lsr.b !Spc_TrackBits
    bcs .song_track
    bne .song_skip
    mov x,#!Spc_TrackSfxLast
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit7
    mov.b a,!Spc_SfxVoices
    and.b a,!Spc_Unk25
    mov.b !Spc_TrackBits,a
    mov.w a,!Spc_GroupVol+3             ; group 1: tracks 15-14
    mov.b !Spc_GroupVolume,a
    bra .sfx_a_next
.sfx_a_track:
    mov.b !Spc_CurTrack,x
    call Spc_Unk0903
    call Spc_Unk0892
.sfx_a_skip:
    dec x
    dec x
    lsr.b !Spc_VoiceBit
    bbs.b !Spc_VoiceBit.5,.sfx_b        ; voices 7-6 done
.sfx_a_next:
    asl.b !Spc_TrackBits
    bcs .sfx_a_track
    bra .sfx_a_skip
.sfx_b:
    mov.w a,!Spc_GroupVol+5             ; group 2: tracks 13-8
    mov.b !Spc_GroupVolume,a
    bra .sfx_b_next
.sfx_b_track:
    mov.b !Spc_CurTrack,x
    call Spc_Unk0903
    call Spc_Unk0892
.sfx_b_skip:
    dec x
    dec x
    lsr.b !Spc_VoiceBit
.sfx_b_next:
    asl.b !Spc_TrackBits
    bcs .sfx_b_track
    bne .sfx_b_skip
    mov a,#$00
    mov y,a
    movw.b !Spc_UnkD0,ya                ; and !Spc_UnkD1
    call Spc_Unk08CD
    call Spc_Unk0B5C
    jmp Spc_MainLoop

; ============================================================
; DSP and port helpers ($07A3-$07AE)
; ============================================================

; $07A3 — Spc_WriteDsp (5 bytes, $07A3–$07A7; ROM $C7:2A68–$2A6C)
; Writes A to the DSP register Y.
; Callers note: CALL from Spc_Start ($0213, $0218, $022A, $028E, $0293),
;   Spc_StartSong ($0BEA, $0C37, $0C3B) and unmatched code ($0EF8, $12D4,
;   $135F, $1364, $1369, $136E, $137D, $138B, $1B20); JMP from unmatched
;   code ($0EFD, $1B27, and $12F6: command $FD, DSP register
;   !Spc_CmdArg0 = !Spc_CmdArg1).
; Entry: P=0; A = the value, Y = the register
; Exit:  A, X, Y unchanged; PSW unchanged
; DSP:   register Y
%SpcOrg($07A3)
Spc_WriteDsp:
    mov.b !SPC_DSPADDR,y
    mov.b !SPC_DSPDATA,a
    ret

; $07A8 — Spc_ClearPorts01 (7 bytes, $07A8–$07AE; ROM $C7:2A6D–$2A73)
; Clears the latches of ports 0 and 1, so CPUIO0/1 read 0 until the
; 65816 writes APUIO0/1 again, keeping timers 0 and 1 running (CONTROL
; = !SPC_CONTROL_ClearPorts01, then !SPC_CONTROL_Timers01).
; Callers note: CALL from Spc_PollCommand ($0BA9) and Spc_Unk0892
;   ($08C7); JMP from Spc_CmdSongCheck ($0D42) and unmatched code ($1079,
;   the transfer code's end).
; Entry: P=0
; Exit:  A, X, Y unchanged; PSW unchanged
; Ports: CPUIO0/1 read 0 afterwards
Spc_ClearPorts01:
    mov.b !SPC_CONTROL,#!SPC_CONTROL_ClearPorts01
    mov.b !SPC_CONTROL,#!SPC_CONTROL_Timers01
    ret

; ============================================================
; CPU commands ($0B96-$0E10)
; ============================================================
; The 65816 writes a command's arguments to APUIO1-3 and its id to APUIO0
; (Audio_RunCommand / Audio_CmdSend / Audio_StartSong), then waits for
; APUIO0 to read the id back. Ids $80-$FF and $00-$0F / $20-$7F are
; echoed here at once; $10-$1F are echoed by their handlers.

; $0B96 — Spc_PollCommand (22 bytes, $0B96–$0BAB; ROM $C7:2E5B–$2E70)
; Takes a command if one is waiting: when CPUIO0 is nonzero, reads it
; until two reads agree, copies CPUIO0-3 to !Spc_CmdId-!Spc_CmdArg2,
; clears the port 0/1 latches (Spc_ClearPorts01) and runs it: falls into
; Spc_RunCommand.
; Spc_RunCommand (44 bytes, $0BAC–$0BD7) runs the command in !Spc_CmdId:
;   - $80-$FF: echoed (CPUIO0 = the id), then Spc_RunHighCommand;
;   - $10-$1F: Spc_CmdTable10's handler, with Spc_CmdFirstTable10's
;     (when nonzero) run first: both are pushed and the RET runs the
;     second, which returns into the first. Not echoed here;
;   - $00-$0F, $20-$7F: echoed only.
; Callers note: CALL from Spc_MainLoop ($0299); Spc_RunCommand is also
;   called by Spc_Unk08CD ($08E6) for the queued commands.
; Entry: P=0 (Spc_RunCommand: !Spc_CmdId-!Spc_CmdArg2 set)
; Exit:  no command: X = 0, Z=1; $00-$0F / $20-$7F: A = X = the id;
;        else as the handler leaves it (a song handler does not return:
;        Spc_StartSong)
; Ports: CPUIO0-3 read; CPUIO0 = the id (echo) as above
; Callees: Spc_ClearPorts01, Spc_RunHighCommand (JMP), the table's
;   handlers (RET)
; Sub-entries: Spc_RunCommand.
%SpcOrg($0B96)
Spc_PollCommand:
    mov.b x,!SPC_CPUIO0
    bne .read
    ret
.again:
    mov.b x,!SPC_CPUIO0
.read:
    cmp.b x,!SPC_CPUIO0
    bne .again
    movw.b ya,!SPC_CPUIO2
    movw.b !Spc_CmdArg1,ya              ; and !Spc_CmdArg2
    movw.b ya,!SPC_CPUIO0
    movw.b !Spc_CmdId,ya                ; and !Spc_CmdArg0
    call Spc_ClearPorts01
Spc_RunCommand:                         ; header: see Spc_PollCommand
    mov.b x,!Spc_CmdId
    mov a,x
    bpl .low
    mov.b !SPC_CPUIO0,x
    jmp Spc_RunHighCommand
.low:
    cmp x,#!SpcCmd_FirstSong
    bcc .echo
    cmp x,#!SpcCmd_AfterSong
    bcs .echo
    and a,#!SpcCmd_SongIndexMask
    asl a
    mov y,a
    mov.w a,Spc_CmdTable10+1+y
    push a
    mov.w a,Spc_CmdTable10+y
    push a
    mov.w a,Spc_CmdFirstTable10+1+y
    beq .run
    push a
    mov.w a,Spc_CmdFirstTable10+y
    push a
.run:
    ret
.echo:
    mov.b !SPC_CPUIO0,x
    ret

; $0BD8 — Spc_CmdSong14 (3 bytes, $0BD8–$0BDA; ROM $C7:2E9D–$2E9F)
; Commands $10, $11, $14 and $15 (Spc_CmdTable10), after
; Spc_CmdSongCheck has let them through:
;   - Spc_CmdSong14 ($14): Spc_SaveSong, then as $10;
;   - Spc_CmdSong10 ($10): !Spc_SongHeaderSet = !Spc_SongSetA, then
;     Spc_StartSong;
;   - Spc_CmdSong15 ($15): Spc_SaveSong, then as $11;
;   - Spc_CmdSong11 ($11): !Spc_SongHeaderSet = !Spc_SongSetB, falls into
;     Spc_StartSong.
; ($14 is what the battle music cue sends, !Audio_Cmd14: the song that
; was playing is kept aside, and Spc_StartSong resumes it when it is
; asked for again.)
; Callers note: reached only through Spc_CmdTable10 (pushed by
;   Spc_RunCommand, entered by RET).
; Entry: P=0; !Spc_CmdArg0-2 as Spc_StartSong wants them
; Exit:  through Spc_StartSong (does not return)
; Callees: Spc_SaveSong, Spc_StartSong (BRA / fall-through)
; Sub-entries: Spc_CmdSong10, Spc_CmdSong15, Spc_CmdSong11.
Spc_CmdSong14:
    call Spc_SaveSong
Spc_CmdSong10:                          ; header: see Spc_CmdSong14
    mov.b !Spc_SongHeaderSet,#!Spc_SongSetA
    bra Spc_StartSong
Spc_CmdSong15:                          ; header: see Spc_CmdSong14
    call Spc_SaveSong
Spc_CmdSong11:                          ; header: see Spc_CmdSong14
    mov.b !Spc_SongHeaderSet,#!Spc_SongSetB

; $0BE6 — Spc_StartSong (272 bytes, $0BE6–$0CF5; ROM $C7:2EAB–$2FBA)
; Starts the song the 65816 has just loaded (or the one saved aside):
;   1. Keys off every voice (KOF = $FF), !Spc_NewSong = !Spc_CmdArg0,
;      !Spc_Unk4D = !Spc_CmdArg1; when !Spc_CmdArg2's low nibble (the
;      song's echo delay) differs from !Spc_EchoDelay, takes it and
;      starts the echo change (!Spc_Flags88 bits 0 and 1, Spc_Unk1316).
;   2. Spc_Unk100E: takes the transfers that follow (the samples'
;      directory, the song data; Audio_LoadNewSamples ... on the 65816
;      side).
;   3. Clears !Spc_SfxVoices, !Spc_Flags88 bit 5 and !Spc_UnkD1-D3.
;   4. When !Spc_SavedSong = !Spc_NewSong (the song asked for is the
;      one Spc_SaveSong kept): Spc_RestoreSong, and when the song has
;      tracks, puts the noise clock back in FLG and, for each track 0-7,
;      adds 1 to its wait, writes its sample (Spc_Unk1AED), writes 0 to
;      its voice's VOLL and VOLR and runs Spc_Unk0A78 with !Spc_Temp9C =
;      the voice's next register number (PL); then clears $55/$57/$59,
;      keys on !Spc_Unk24 and marks the song's tracks in !Spc_UnkD0.
;      Else a new start: clears !Spc_SongTracks, the EON/NON/PMON words,
;      the KON/KOF shadows, !Spc_Unk24/25, !Spc_Unk5A, 5C, 60, 7C and 7B,
;      sets tempo 1 with the accumulator at $FF, copies the chosen set of 8 track pointers of
;      the header at !AudioAram_Song (!Spc_SongHeaderSet) and moves each
;      by (!AudioAram_Song + !SpcSong_Data) - the header's
;      !SpcSong_Origin; a track whose pointer equals !SpcSong_NoTrack is
;      left out, the others go into !Spc_SongTracks, Spc_InitTrack and
;      !Spc_TrackF220 = $FF; then !Spc_UnkD0 = 0.
;   5. With !Spc_Flags88 bit 0 set, finishes the echo change: with bit 1
;      set, Spc_Unk12F9 on !Spc_Unk82, !Spc_Unk83 = 0 and echo writes on
;      (Spc_Unk1397); then Spc_Unk12F9 on !Spc_EchoDelay, and clears bit
;      0 (bit 1 stays set).
;   6. Copies !Spc_SongEon/Non/Pmon to their shadows, resets SP and jumps
;      to Spc_MainLoop (with A = timer 0's count, discarding it).
; Callers note: Spc_CmdSong11 falls in; BRA from Spc_CmdSong10 ($0BDE).
; Entry: P=0; !Spc_CmdArg0 = the song, !Spc_CmdArg1 = byte 1 of its
;        AudioRom_SongEcho word, !Spc_CmdArg2 = the echo delay (low
;        nibble); !Spc_SongHeaderSet set
; Exit:  does not return: SP = $FF, JMP Spc_MainLoop
; DSP:   KOF; on a resume VOLL/VOLR of voices 0-7 and SRCN (Spc_Unk1AED);
;        FLG / EDL through the echo change routines
; Ports: through Spc_Unk100E and Spc_Unk12F9
; Callees: Spc_WriteDsp, Spc_Unk1316, Spc_Unk100E, Spc_RestoreSong,
;   Spc_Unk1AED, Spc_Unk0A78, Spc_InitTrack, Spc_Unk12F9, Spc_Unk1397,
;   Spc_MainLoop (JMP)
Spc_StartSong:
    mov a,#!DSP_KOF_All
    mov y,#!DSP_KOF
    call Spc_WriteDsp
    mov.b !Spc_NewSong,!Spc_CmdArg0
    mov.b a,!Spc_CmdArg1
    mov.b !Spc_Unk4D,a
    mov.b a,!Spc_CmdArg2
    and a,#!SpcCmd_EchoDelayMask
    cmp.b a,!Spc_EchoDelay
    beq .echo_same
    mov.b !Spc_EchoDelay,a
    set1.b !Spc_Flags88.0
    set1.b !Spc_Flags88.1
    call Spc_Unk1316
.echo_same:
    call Spc_Unk100E
    mov a,#$00
    mov y,a
    mov.b !Spc_SfxVoices,a
    clr1.b !Spc_Flags88.5
    movw.b !Spc_UnkD2,ya
    mov.b !Spc_UnkD1,a
    cmp.b !Spc_SavedSong,!Spc_NewSong
    bne .new_song
    call Spc_RestoreSong
    mov.b a,!Spc_SongTracks
    beq .new_song
    and.b !Spc_FlgShadow,#!Spc_FlgKeep
    or.b !Spc_FlgShadow,!Spc_NoiseClock
    mov x,#$00
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit0
.resume_track:
    inc.b !Spc_TrackWait+x
    mov.b !Spc_CurTrack,x
    call Spc_Unk1AED
    mov a,x
    xcn a
    lsr a                               ; voice x $10: its VOLL
    mov y,a
    mov a,#$00
    call Spc_WriteDsp
    inc y                               ; VOLR
    call Spc_WriteDsp
    inc y
    mov.b !Spc_Temp9C,y
    call Spc_Unk0A78
    inc x
    inc x
    asl.b !Spc_VoiceBit
    bne .resume_track
    mov a,#$00
    mov.b !Spc_SongEon+1,a
    mov.b !Spc_SongNon+1,a
    mov.b !Spc_SongPmon+1,a
    mov.b !Spc_KonShadow,!Spc_Unk24
    mov.b !Spc_KofShadow,a
    mov.b !Spc_Unk25,a
    mov.b !Spc_UnkD0,!Spc_SongTracks
    bra .echo_change
.new_song:
    mov a,#$00
    mov y,a
    mov.b !Spc_SongTracks,a
    movw.b !Spc_SongEon,ya
    movw.b !Spc_SongNon,ya
    movw.b !Spc_SongPmon,ya
    mov.b !Spc_KonShadow,a
    mov.b !Spc_KofShadow,a
    movw.b !Spc_Unk24,ya                ; and !Spc_Unk25
    mov.b !Spc_Unk5A,a
    mov.b !Spc_Unk5C,a
    mov.b !Spc_Unk60,a
    mov.b !Spc_Unk7C,a
    mov.b !Spc_Unk7B,a
    mov.b !Spc_Tempo,#!Spc_StartTempo
    mov.b !Spc_TempoAccum,#$FF          ; the first pass steps
    mov.b y,!Spc_SongHeaderSet
    mov x,#!Spc_NumSongTracks
.copy_set:
    mov.w a,!AudioAram_Song+!SpcSong_Tracks-1+y
    mov.b !Spc_TrackPtr-1+x,a
    dec y
    dec x
    bne .copy_set
    mov.w a,!AudioAram_Song+!SpcSong_Origin
    mov.b !Spc_Scratch00,a
    mov.w a,!AudioAram_Song+!SpcSong_Origin+1
    mov.b !Spc_Scratch00+1,a
    mov a,#(!AudioAram_Song+!SpcSong_Data)&$FF
    mov y,#(!AudioAram_Song+!SpcSong_Data)>>8
    subw.b ya,!Spc_Scratch00
    movw.b !Spc_Scratch00,ya            ; the move
    mov x,#!Spc_TrackLast
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit7
    mov.w a,!AudioAram_Song+!SpcSong_NoTrack
    mov.w y,!AudioAram_Song+!SpcSong_NoTrack+1
    movw.b !Spc_Temp9B,ya
.move_track:
    mov.b a,!Spc_TrackPtr+x
    mov.b y,!Spc_TrackPtr+1+x
    cmpw.b ya,!Spc_Temp9B
    beq .no_track
    or.b !Spc_SongTracks,!Spc_VoiceBit
    addw.b ya,!Spc_Scratch00
    mov.b !Spc_TrackPtr+x,a
    mov.b !Spc_TrackPtr+1+x,y
    call Spc_InitTrack
    mov a,#$FF
    mov.w !Spc_TrackF220+x,a
.no_track:
    dec x
    dec x
    lsr.b !Spc_VoiceBit
    bne .move_track
    mov.b !Spc_UnkD0,#$00
.echo_change:
    bbc.b !Spc_Flags88.0,.echo_done
    bbc.b !Spc_Flags88.1,.echo_wait
    mov x,#!Spc_Unk82
    call Spc_Unk12F9
    mov.b !Spc_Unk83,#$00
    call Spc_Unk1397
.echo_wait:
    mov x,#!Spc_EchoDelay
    call Spc_Unk12F9
    clr1.b !Spc_Flags88.0
.echo_done:
    mov.b !Spc_EonShadow,!Spc_SongEon
    mov.b !Spc_NonShadow,!Spc_SongNon
    mov.b !Spc_PmonShadow,!Spc_SongPmon
    mov x,#!Spc_StackTop
    mov sp,x
    mov.b a,!SPC_T0OUT
    jmp Spc_MainLoop

; $0CF6 — Spc_InitTrack (51 bytes, $0CF6–$0D28; ROM $C7:2FBB–$2FED)
; Resets track X's state before it starts: !Spc_TrackUnk27 = X x 2;
; clears its words in !Spc_Track150 / !Spc_Track170 and the work area
; (!Spc_TrackF3C0, !Spc_TrackF4C0, the bytes !Spc_TrackF4E0,
; !Spc_TrackF3A0, !Spc_TrackF360's high byte); !Spc_TrackF300 = $1000;
; !Spc_TrackWait = 1 (it steps on the next pass).
; Callers note: CALL from Spc_StartSong ($0CBC) and Spc_StartSfx ($0D88).
; Entry: P=0; X = the track (0-$1E, even)
; Exit:  A = !Spc_TrackF300Start; X, Y unchanged
Spc_InitTrack:
    mov a,x
    asl a
    mov.b !Spc_TrackUnk27+x,a
    mov a,#$00
    mov.w !Spc_Track150+x,a
    mov.w !Spc_TrackF3C0+x,a
    mov.w !Spc_TrackF3C0+1+x,a
    mov.w !Spc_TrackF4E0+x,a
    mov.w !Spc_Track150+1+x,a
    mov.w !Spc_Track170+x,a
    mov.w !Spc_Track170+1+x,a
    mov.w !Spc_TrackF4C0+x,a
    mov.w !Spc_TrackF4C0+1+x,a
    mov.w !Spc_TrackF3A0+x,a
    mov.w !Spc_TrackF360+1+x,a
    mov.w !Spc_TrackF300+x,a
    inc a
    mov.b !Spc_TrackWait+x,a
    mov a,#!Spc_TrackF300Start
    mov.w !Spc_TrackF300+1+x,a
    ret

; $0D29 — Spc_CmdSongCheck (28 bytes, $0D29–$0D44; ROM $C7:2FEE–$3009)
; Run first for commands $10, $11, $14 and $15 (Spc_CmdFirstTable10):
; compares the song asked for (!Spc_CmdArg0) with !Spc_CurSong and
; makes it the current song.
;   - A different song: CPUIO1 = the song (bit 7 clear for songs below
;     $80), CPUIO0 = the id (echo), and returns into the command's
;     handler (Spc_CmdSong10 ...), which takes the load.
;   - The same song: drops the handler's address from the stack, CPUIO1
;     = !SpcCmd_SameSong, CPUIO0 = the id, waits until CPUIO0 is nonzero
;     (the 65816's next step: Audio_StartSong sends Audio_Seq), and
;     leaves through Spc_ClearPorts01, returning to Spc_PollCommand's
;     caller. On the 65816 side Audio_StartSong sees APUIO1 bit 7 and
;     ends the load there.
; Callers note: reached only through Spc_CmdFirstTable10 (pushed by
;   Spc_RunCommand, entered by RET); it returns into the handler pushed
;   under it.
; Entry: P=0; X = the id (Spc_RunCommand), !Spc_CmdArg0 = the song
; Exit:  !Spc_CurSong = the song; A = the song (or !SpcCmd_SameSong /
;        CPUIO0's value), X unchanged
; Ports: CPUIO0 (echo), CPUIO1 (the answer); CPUIO0 read
; Callees: Spc_ClearPorts01 (JMP)
Spc_CmdSongCheck:
    mov.b a,!Spc_CmdArg0
    cmp.b a,!Spc_CurSong
    mov.b !Spc_CurSong,a
    beq .same
    mov.b !SPC_CPUIO1,a
    mov.b !SPC_CPUIO0,x
    ret
.same:
    pop a                               ; the handler's address
    pop a
    mov a,#!SpcCmd_SameSong
    mov.b !SPC_CPUIO1,a
    mov.b !SPC_CPUIO0,x
.wait:
    mov.b a,!SPC_CPUIO0
    beq .wait
    jmp Spc_ClearPorts01

; $0D45 — Spc_CmdSfx18 (12 bytes, $0D45–$0D50; ROM $C7:300A–$3015)
; Commands $18 and $19 (Spc_CmdTable10): echo the id, then start the
; sound effect !Spc_CmdArg0 in Spc_StartSfx on a group of tracks:
;   - Spc_CmdSfx18 ($18): tracks 15 and 14 (voices 7 and 6: X = $1E,
;     bits $C0);
;   - Spc_CmdSfx19 ($19, Audio_CmdPlaySfx): tracks 13 and 12 (voices 5
;     and 4: X = $1A, bits $30).
; Callers note: reached only through Spc_CmdTable10.
; Entry: P=0; X = the id; !Spc_CmdArg0 = the effect, !Spc_CmdArg1 = the
;        high byte for the tracks' !Spc_TrackF280
; Exit:  through Spc_StartSfx
; Ports: CPUIO0 = the id (echo)
; Callees: Spc_StartSfx (BRA / fall-through)
; Sub-entries: Spc_CmdSfx19.
Spc_CmdSfx18:
    mov.b !SPC_CPUIO0,x
    mov x,#!Spc_TrackSfxLast
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit7
    mov.b !Spc_CmdArg2,#!Spc_SfxGroupA
    bra Spc_StartSfx
Spc_CmdSfx19:                           ; header: see Spc_CmdSfx18
    mov.b !SPC_CPUIO0,x
    mov x,#!Spc_TrackSfxB
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit5
    mov.b !Spc_CmdArg2,#!Spc_SfxGroupB

; $0D5B — Spc_StartSfx (160 bytes, $0D5B–$0DFA; ROM $C7:3020–$30BF)
; Starts sound effect !Spc_CmdArg0 on the two tracks from X down (voice
; bit !Spc_VoiceBit); nothing while !Spc_Flags87 bit 4 is set.
;   1. The effect's entry in the table at !AudioAram_Block2F00: two
;      track pointers (4 bytes per effect), taken from the second down.
;      A pointer whose high byte is 0 is skipped and does not use up a
;      track (so a lone pointer lands on the upper track); each other one
;      goes to the track's !Spc_TrackPtr, adds its voice bit to
;      !Spc_TempA4, and the track starts: Spc_InitTrack, wait 2,
;      !Spc_TrackF240 high byte $46, !Spc_TrackF280 high byte =
;      !Spc_CmdArg1, !Spc_TrackF200 = $48, !Spc_TrackF2C0 = 0, sample 2
;      (Spc_SetTrackSample).
;      Quirk (a byte shared by two instructions): the skip branch lands
;      on the operand byte of `mov a,#$DC`, which is `dec y`, so both
;      paths step Y by 2 while only the taken one steps X.
;   2. The voices of the group already held by an effect, plus the new
;      ones: cleared from !Spc_KonShadow, !Spc_Unk5B, !Spc_Unk5D,
;      !Spc_Unk61, !Spc_UnkD0, !Spc_UnkD1 and !Spc_Unk25, set in
;      !Spc_KofShadow; Spc_EndTrack for each of them that is a voice 7-4
;      (tracks 15-12, the loop's reach: both groups' voices).
;   3. The new voices: set in !Spc_SfxVoices, cleared from the EON, PMON
;      and NON shadows and from !Spc_Unk24.
; Callers note: Spc_CmdSfx19 falls in; BRA from Spc_CmdSfx18 ($0D4F).
; Entry: P=0; X = the first track, !Spc_VoiceBit its voice bit,
;        !Spc_CmdArg2 = the group's voice bits, !Spc_CmdArg0/1 as in
;        Spc_CmdSfx18
; Exit:  A = the new voice bits; X = $16; Y = $FF (with !Spc_Flags87
;        bit 4 set: A, X, Y as on entry)
; Callees: Spc_InitTrack, Spc_SetTrackSample, Spc_EndTrack
Spc_StartSfx:
    bbc.b !Spc_Flags87.4,.start
    ret
.start:
    mov.b !Spc_Ptr93,!Spc_CmdArg0
    mov.b !Spc_Ptr93+1,#$00
    asl.b !Spc_Ptr93                    ; x 4 (!Spc_SfxEntry)
    rol.b !Spc_Ptr93+1
    asl.b !Spc_Ptr93
    rol.b !Spc_Ptr93+1
    mov a,#!AudioAram_Block2F00&$FF
    mov y,#!AudioAram_Block2F00>>8
    addw.b ya,!Spc_Ptr93
    movw.b !Spc_Ptr93,ya
    mov y,#!Spc_SfxEntry-1
    mov.b !Spc_TempA4,#$00
.pointer:
    mov.b a,(!Spc_Ptr93)+y
    beq .skip+1                         ; on the `dec y` inside .skip
    mov.b !Spc_TrackPtr+1+x,a
    dec y
    mov.b a,(!Spc_Ptr93)+y
    mov.b !Spc_TrackPtr+x,a
    or.b !Spc_TempA4,!Spc_VoiceBit
    call Spc_InitTrack
    inc.b !Spc_TrackWait+x
    mov a,#!Spc_TrackF240Sfx
    mov.w !Spc_TrackF240+1+x,a
    mov.b a,!Spc_CmdArg1
    mov.w !Spc_TrackF280+1+x,a
    mov a,#!Spc_TrackF200Sfx
    mov.w !Spc_TrackF200+x,a
    mov a,#$00
    mov.w !Spc_TrackF2C0+x,a
    mov.w !Spc_TrackF2C0+1+x,a
    mov.b !Spc_Temp9B,y
    mov a,#!Spc_SfxStartSample
    call Spc_SetTrackSample
    mov.b y,!Spc_Temp9B
    dec x
    dec x
    lsr.b !Spc_VoiceBit
.skip:
    mov a,#$DC                          ; $DC: the `dec y` the BEQ above lands on
    dec y
    bpl .pointer
    mov.b a,!Spc_SfxVoices
    and.b a,!Spc_CmdArg2
    or.b a,!Spc_TempA4
    tclr.w !Spc_KonShadow,a
    tclr.w !Spc_Unk5B,a
    tclr.w !Spc_Unk5D,a
    tclr.w !Spc_Unk61,a
    tclr.w !Spc_UnkD0,a
    tclr.w !Spc_UnkD1,a
    tset.w !Spc_KofShadow,a
    tclr.w !Spc_Unk25,a
    mov.b !Spc_TempA5,a
    mov x,#!Spc_TrackSfxLast
    mov.b !Spc_VoiceBit,#!Spc_VoiceBit7
.end_old:
    asl.b !Spc_TempA5
    bcc .end_next
    call Spc_EndTrack
.end_next:
    dec x
    dec x
    lsr.b !Spc_VoiceBit
    bbc.b !Spc_VoiceBit.3,.end_old      ; voices 7-4 (tracks 15-12)
    mov.b a,!Spc_TempA4
    tset.w !Spc_SfxVoices,a
    tclr.w !Spc_EonShadow,a
    tclr.w !Spc_PmonShadow,a
    tclr.w !Spc_NonShadow,a
    tclr.w !Spc_Unk24,a
    ret

; $0DFB — Spc_RunHighCommand (22 bytes, $0DFB–$0E10; ROM $C7:30C0–$30D5)
; Commands $80-$8F and $F0-$FF (already echoed by Spc_RunCommand): RET
; into Spc_CmdTable80's entry (id & $1F); $90-$EF do nothing.
; Callers note: JMP from Spc_RunCommand ($0BB3).
; Entry: P=0; X = the id ($80-$FF)
; Exit:  through the handler (RET into it); $90-$EF: returns with A, X,
;        Y unchanged, C=1
; Callees: the handlers of Spc_CmdTable80 (RET)
Spc_RunHighCommand:
    cmp x,#!SpcCmd_FirstTop
    bcs .dispatch
    cmp x,#!SpcCmd_FirstHigh
    bcs .done
.dispatch:
    mov a,x
    and a,#!SpcCmd_HighIndexMask
    asl a
    mov y,a
    mov.w a,Spc_CmdTable80+1+y
    push a
    mov.w a,Spc_CmdTable80+y
    push a
.done:
    ret

base off
arch 65816
