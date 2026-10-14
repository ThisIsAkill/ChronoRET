; ============================================================
; spc700.inc — names for the SPC700 sound driver (asm/spc700/driver.asm)
;
; Everything here is an ARAM address or a value, as the SPC700 sees it;
; nothing is a SNES bus address. Prefixes keep these apart from the 65816
; names (asar lets a later define replace an earlier one silently):
;   !SPC_*    the SPC700's I/O registers ($F0-$FF) and their values
;   !DSP_*    S-DSP register numbers (written to !SPC_DSPADDR)
;   !Spc_*    the driver's RAM: direct page ($0000-$00EF, P=0), page 1
;             and the work area from $F100
;   !SpcCmd_* command ids as the driver sees them in !Spc_CmdId
;   !SpcSong_* offsets in the song header at !AudioAram_Song
; The ARAM layout shared with the 65816 side (!AudioAram_*) is in
; constants_engine.inc.
;
; A name or meaning marked "inferred" rests on the code cited; "Unk"
; names say what has been observed so far.
; ============================================================

; --- SPC700 I/O registers (direct page, P=0) ---
!SPC_CONTROL = $F1                       ; write: timer enables (bits 0-2), port latch clears
                                         ; (bit 4: ports 0/1, bit 5: ports 2/3), IPL ROM (bit 7)
!SPC_DSPADDR = $F2                       ; S-DSP register number for !SPC_DSPDATA
!SPC_DSPDATA = $F3                       ; S-DSP register data
!SPC_CPUIO0 = $F4                        ; port 0: read = what the 65816 wrote to APUIO0, write = what
                                         ; it reads there
!SPC_CPUIO1 = $F5                        ; port 1 (APUIO1)
!SPC_CPUIO2 = $F6                        ; port 2 (APUIO2)
!SPC_CPUIO3 = $F7                        ; port 3 (APUIO3)
!SPC_T0TARGET = $FA                      ; timer 0 divider (8 kHz ticks)
!SPC_T1TARGET = $FB                      ; timer 1 divider (8 kHz ticks)
!SPC_T0OUT = $FD                         ; timer 0 count (4 bits), cleared by the read
!SPC_T1OUT = $FE                         ; timer 1 count (4 bits), cleared by the read

!SPC_CONTROL_ClearPorts = $30            ; clear all four port latches, timers off, IPL ROM off
!SPC_CONTROL_Timers01 = $03              ; timers 0 and 1 on, IPL ROM off
!SPC_CONTROL_ClearPorts01 = $13          ; the same plus clear the port 0/1 latches
!SPC_Timer0Divider = $2A                 ; 42 x 125 us = 5.25 ms: one pass of the main loop
!SPC_Timer1Divider = $80                 ; 128 x 125 us = 16 ms

; --- S-DSP registers (per voice: + $10 x voice) ---
!DSP_GAIN = $07                          ; voice 0's GAIN
!DSP_VoiceStride = $10                   ; voice n's registers are at n x $10
!DSP_MVOLL = $0C                         ; main volume left
!DSP_MVOLR = $1C                         ; main volume right
!DSP_EVOLL = $2C                         ; echo volume left
!DSP_EVOLR = $3C                         ; echo volume right
!DSP_KOF = $5C                           ; key off (a bit per voice)
!DSP_DIR = $5D                           ; sample directory page

!DSP_GAIN_Start = $A0                    ; GAIN Spc_Start gives every voice (bits 7-5 = %101:
                                         ; exponential decrease; rate 0: the envelope does not move)
!DSP_MVOL_Start = $40                    ; main volume Spc_Start sets (both sides)
!DSP_KOF_All = $FF                       ; key off all eight voices

; --- Driver RAM: direct page ---
; Tracks: 16 tracks, X = track x 2. Tracks 0-7 ($00-$0E) are the song's, one
; per voice; tracks 8-15 ($10-$1E) play sound effects on voices 0-7 (the
; voice of track t is t & 7). A track's voice bit is 1 << voice.
!Spc_Scratch00 = $00                     ; word: scratch (Spc_StartSong: the offset that moves the
                                         ; song's track pointers to where the song was loaded)
!Spc_TrackPtr = $02                      ; word per track ($02-$21): the track's read pointer in ARAM
!Spc_KonShadow = $22                     ; KON for the next pass (written by Spc_MainLoop, then 0)
!Spc_KofShadow = $23                     ; KOF for the next pass (written by Spc_MainLoop, then 0)
!Spc_Unk24 = $24                         ; voice bits; Spc_MainLoop runs the song's tracks only for
                                         ; these; a resumed song keys them on again (Spc_StartSong)
!Spc_Unk25 = $25                         ; voice bits; Spc_MainLoop runs the effect tracks only for
                                         ; these; Spc_StartSfx clears the new effect's
!Spc_TrackWait = $26                     ; byte per track (+X): passes until the track's next step
                                         ; (Spc_InitTrack sets 1, decremented by $03A5)
!Spc_TrackUnk27 = $27                    ; byte per track (+X): Spc_InitTrack sets it to X x 2
!Spc_Tempo = $47                         ; added to !Spc_TempoAccum each pass ($0377); a song step
                                         ; runs on the carry (inferred: tempo); 1 at a song's start
!Spc_TempoAccum = $48                    ; the accumulator; $FF at a song's start (first pass steps)
!Spc_Unk4D = $4D                         ; Spc_StartSong stores !Spc_CmdArg1 here (byte 1 of the
                                         ; song's AudioRom_SongEcho word on the 65816 side)
!Spc_EchoVolume = $4F                    ; source of both EVOL shadows (!Spc_EvolShadow)
!Spc_SongTracks = $53                    ; voice bits of the tracks the song uses (set by
                                         ; Spc_StartSong from the header's pointers)
!Spc_SongEon = $54                       ; copied to !Spc_EonShadow at a song's start (byte; $55 is
                                         ; cleared with it)
!Spc_SongNon = $56                       ; copied to !Spc_NonShadow at a song's start
!Spc_SongPmon = $58                      ; copied to !Spc_PmonShadow at a song's start
!Spc_Unk5A = $5A                         ; cleared at a song's start
!Spc_Unk5B = $5B                         ; voice bits; Spc_StartSfx clears the new effect's
!Spc_Unk5C = $5C                         ; cleared at a song's start
!Spc_Unk5D = $5D                         ; voice bits; Spc_StartSfx clears the new effect's
!Spc_Unk60 = $60                         ; cleared at a song's start
!Spc_Unk61 = $61                         ; voice bits; Spc_StartSfx clears the new effect's
!Spc_NoiseClock = $62                    ; ORed into !Spc_FlgShadow's low 5 bits (the FLG noise
                                         ; clock) when a song is resumed
!Spc_FirShadow = $66                     ; 8 words ($66-$75): FIR0-7 take the low bytes ($66, $68, ...)
!Spc_EfbShadow = $76                     ; EFB
!Spc_Unk7B = $7B                         ; low nibble of what Spc_MainLoop writes to CPUIO2
!Spc_Unk7C = $7C                         ; cleared at a song's start
!Spc_CurSong = $80                       ; the song playing ($FF: none); inferred: Spc_CmdSongCheck
                                         ; compares the requested song with it
!Spc_EchoDelay = $81                     ; the echo delay in effect (EDL), compared with each song
                                         ; command's !Spc_CmdArg2
!Spc_Unk82 = $82                         ; passed to $12F9 (X = its address) after an echo change
!Spc_Unk83 = $83                         ; cleared before that wait
!Spc_SfxVoices = $86                     ; voice bits taken by sound effects (set by Spc_StartSfx)
!Spc_Flags87 = $87                       ; bit 3: echo volume doubled; bit 4: no song step or new
                                         ; effect (Spc_MainLoop, Spc_StartSfx); other bits not traced
!Spc_Flags88 = $88                       ; bits 0/1: echo change to finish (Spc_StartSong; Spc_Unk1316
                                         ; clears bit 1 when the old EDL was 0); bit 5:
                                         ; $0377 steps the song every pass, without the tempo; bit 7:
                                         ; Spc_MainLoop leaves CPUIO0-3 to $1438 (not traced)
!Spc_EonShadow = $89                     ; EON for the next pass
!Spc_NonShadow = $8A                     ; NON
!Spc_PmonShadow = $8B                    ; PMON
!Spc_FlgShadow = $8C                     ; FLG
!Spc_CmdId = $8D                         ; the command being run: what the 65816 wrote to APUIO0
                                         ; (Audio_CmdId)
!Spc_CmdArg0 = $8E                       ; APUIO1 (Audio_CmdArg0)
!Spc_CmdArg1 = $8F                       ; APUIO2 (Audio_CmdArg1)
!Spc_CmdArg2 = $90                       ; APUIO3 (Audio_CmdArg2)
!Spc_VoiceBit = $91                      ; the voice bit of the track in hand (X)
!Spc_Ptr93 = $93                         ; word: a pointer (Spc_StartSfx: the effect's entry in the
                                         ; table at !AudioAram_Block2F00)
!Spc_Temp9B = $9B                        ; scratch byte
!Spc_Temp9C = $9C                        ; scratch byte
!Spc_TrackBits = $A3                     ; the voice bits a loop over tracks has still to visit
!Spc_TempA4 = $A4                        ; scratch byte
!Spc_TempA5 = $A5                        ; scratch byte
!Spc_CurTrack = $A6                      ; X of the track being stepped
!Spc_GroupVolume = $A8                   ; the volume of the track group being stepped (from
                                         ; !Spc_GroupVol)
!Spc_SongHeaderSet = $B9                 ; which track pointer set of the song header to start:
                                         ; !Spc_SongSetA or !Spc_SongSetB (the set's end offset)
!Spc_SavedSong = $BB                     ; the song saved by $13A9 ($FF: none)
!Spc_NewSong = $BC                       ; the song a song command asks for (!Spc_CmdArg0)
!Spc_FadeTimer = $BD                     ; counts passes down from 7; at 0, $1492 (the volume fades)
!Spc_UnkD0 = $D0                         ; voice bits; set to the song's tracks on a resume, cleared
                                         ; on a new start and each pass; $1492 ORs in the tracks whose
                                         ; group volume changed (inferred: volumes to rewrite)
!Spc_UnkD1 = $D1                         ; cleared with !Spc_UnkD0
!Spc_UnkD2 = $D2                         ; cleared at a song's start
!Spc_UnkD3 = $D3                         ; high nibble of what Spc_MainLoop writes to CPUIO2
!Spc_QueueEnd = $D7                      ; offset of the first free !Spc_CmdQueue entry
!Spc_UnkD8 = $D8                         ; 2 after Spc_Start
!Spc_EvolShadow = $D9                    ; EVOL (left and right both)

; --- Driver RAM: page 1 (per track, +X) ---
!Spc_Track150 = $0150                    ; word per track, cleared by Spc_InitTrack
!Spc_Track170 = $0170                    ; word per track, cleared by Spc_InitTrack

; --- Driver RAM: work area ---
!Spc_GroupVol = $F160                    ; 3 words: a volume for the song's tracks, for effect tracks
                                         ; 14-15 and for 8-13, in the high bytes (low byte: fraction);
                                         ; $FF after Spc_Start. Inferred: $1492 fades them and marks
                                         ; the group's tracks in !Spc_UnkD0
!Spc_GroupFadeSteps = $F166              ; 3 words: steps of each group's fade still to run (low byte)
!Spc_CmdQueue = $F172                    ; 16 x 4 bytes: commands received while the tracks are
                                         ; stepped ($0892), run later by $08CD; id 0 = free
!Spc_TrackF200 = $F200                   ; word per track: low byte $48 at an effect's start (Spc_StartSfx),
                                         ; high byte the track's sample (Spc_SetTrackSample)
!Spc_TrackF220 = $F220                   ; byte per track, Spc_StartSong sets $FF
!Spc_TrackF240 = $F240                   ; word per track, Spc_StartSfx sets the high byte to $46
!Spc_TrackF280 = $F280                   ; word per track, Spc_StartSfx sets the high byte to
                                         ; !Spc_CmdArg1
!Spc_TrackF2C0 = $F2C0                   ; word per track, cleared by Spc_StartSfx
!Spc_TrackF300 = $F300                   ; word per track: Spc_InitTrack sets $1000
!Spc_TrackF360 = $F360                   ; word per track: Spc_InitTrack clears the high byte
!Spc_TrackF3A0 = $F3A0                   ; byte per track, cleared by Spc_InitTrack
!Spc_TrackF3C0 = $F3C0                   ; word per track, cleared by Spc_InitTrack
!Spc_TrackF4C0 = $F4C0                   ; word per track, cleared by Spc_InitTrack
!Spc_TrackF4E0 = $F4E0                   ; byte per track, cleared by Spc_InitTrack

; --- Values ---
!Spc_StackTop = $FF                      ; SP at Spc_Start and at each song start (stack $01FF down)
!Spc_ClearEnd = $F0                      ; Spc_Start clears the direct page up to here
!Spc_None = $FF                          ; "no song" in !Spc_CurSong / !Spc_SavedSong
!Spc_QueueBytes = $40                    ; !Spc_CmdQueue: 16 entries x 4 bytes
!Spc_QueueEntry = 4                      ; bytes per !Spc_CmdQueue entry
!Spc_StartEchoDelay = $05                ; the echo delay Spc_Start sets (as Audio_Boot's
                                         ; !Audio_DefaultEchoDelay on the 65816 side)
!Spc_GroupVolStart = $FF                 ; each !Spc_GroupVol volume after Spc_Start (full)
!Spc_TempoAccumStart = $FF               ; !Spc_TempoAccum at a song's start: the first pass steps
!Spc_TrackF220Start = $FF                ; !Spc_TrackF220 at a song track's start
!Spc_LowNibble = $0F                     ; the low nibble
!Spc_InvertBits = $FF                    ; EOR mask: all eight bits inverted
!Spc_StartTempo = $01                    ; !Spc_Tempo at a song's start (a step every 256 passes until
                                         ; the song sets its own, probably)
!Spc_FadeTicks = 7                       ; passes per !Spc_FadeTimer round
!Spc_UnkD8Start = $02                    ; !Spc_UnkD8 after Spc_Start
!Spc_NumShadowRegs = $11                 ; DSP registers Spc_MainLoop writes each pass
!Spc_EvolMax = $7F                       ; a doubled echo volume is capped here
!Spc_FlgKeep = $E0                       ; FLG bits kept when !Spc_NoiseClock is ORed in
!Spc_SongSetA = $10                      ; !Spc_SongHeaderSet for commands $10/$14: the first set
!Spc_SongSetB = $20                      ; ... and for $11/$15: the second
!Spc_NumSongTracks = $10                 ; bytes of track pointers per set (8 words)
!Spc_TrackLast = $0E                     ; X of the song's last track
!Spc_TrackSfxLast = $1E                  ; X of the last effect track
!Spc_VoiceBit7 = $80                     ; voice 7's bit
!Spc_VoiceBit0 = $01                     ; voice 0's bit
!Spc_TrackF240Sfx = $46                  ; !Spc_TrackF240 high byte at an effect's start
!Spc_TrackF200Sfx = $48                  ; !Spc_TrackF200 at an effect's start
!Spc_TrackF300Start = $10                ; !Spc_TrackF300 high byte at a track's start
!Spc_SfxStartSample = $02               ; the sample an effect track starts with (Spc_StartSfx)
!Spc_TrackSfxB = $1A                     ; X of command $19's first track (track 13)
!Spc_VoiceBit5 = $20                     ; voice 5's bit
!Spc_SfxGroupA = $C0                     ; command $18's voices (7, 6)
!Spc_SfxGroupB = $30                     ; command $19's voices (5, 4)
!Spc_BuiltinDirEntry = $10               ; the directory entry Spc_Start fills itself
; its directory entry ($1E40), ParamA word ($1F20) and ParamB word ($1FA0)
!Spc_BuiltinDir = !AudioAram_Dir+(4*!Spc_BuiltinDirEntry)
!Spc_BuiltinParamA = !AudioAram_ParamA+(2*!Spc_BuiltinDirEntry)
!Spc_BuiltinParamB = !AudioAram_ParamB+(2*!Spc_BuiltinDirEntry)
!Spc_BuiltinParamA0 = $E1                ; the ParamA word's bytes (meaning not traced)
!Spc_BuiltinParamA1 = $00
!Spc_BuiltinParamB0 = $FF                ; the ParamB word's bytes (ADSR1/ADSR2, probably:
!Spc_BuiltinParamB1 = $E0                ; envelope on, fastest attack and decay)
!Spc_SfxEntry = 4                        ; bytes per entry of the effect table at $2F00: two track
                                         ; pointers

; Commands (!Spc_CmdId; the 65816 side's numbering, Audio_RunCommand)
!SpcCmd_FirstSong = $10                  ; $10-$1F: Spc_CmdTable10 (and Spc_CmdFirstTable10)
!SpcCmd_AfterSong = $20                  ; $20-$7F: nothing (echoed)
!SpcCmd_FirstHigh = $90                  ; $90-$EF: nothing (echoed); $80-$8F, $F0-$FF: Spc_CmdTable80
!SpcCmd_FirstTop = $F0                   ; first of the $F0-$FF range
!SpcCmd_HighIndexMask = $1F              ; $80-$8F -> 0-15, $F0-$FF -> 16-31
!SpcCmd_SongIndexMask = $0F              ; $10-$1F -> 0-15
!SpcCmd_EchoDelayMask = $0F              ; the delay in !Spc_CmdArg2 / !Spc_CmdArg0 (EDL: 0-15)
!SpcCmd_SameSong = $FF                   ; CPUIO1 after a song command asking for the song already
                                         ; playing (the 65816 then skips the load: Audio_StartSong)

; The song header at !AudioAram_Song (written by the 65816: Audio_SendSongData)
!SpcSong_Origin = 0                      ; word: the ARAM address the track pointers assume
!SpcSong_NoTrack = 2                     ; word: a track pointer equal to this is "no track"
!SpcSong_Tracks = 4                      ; two sets of 8 track pointers ($04-$13, $14-$23)
!SpcSong_Data = $24                      ; the song's data: where !SpcSong_Origin is moved to
