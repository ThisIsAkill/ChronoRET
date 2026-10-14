; ============================================================
; unmatched.asm — names for SPC700 driver code and data not matched yet
;
; Label-only (no bytes): each is an ARAM address in the driver block that
; asm/spc700/driver.asm calls, jumps to or reads before its own source
; exists. Delete a name here when its source lands in driver.asm.
; ============================================================

; --- Code ---
Spc_Unk0377 = $0377             ; the song's tempo step; called once a pass by Spc_MainLoop
Spc_Unk0415 = $0415             ; a pass of the track stepping (Spc_XferLive runs it while
                                ; it waits), probably
Spc_Unk0903 = $0903             ; steps the track in X (probably)
Spc_Unk09F6 = $09F6             ; Spc_MainLoop's step for a song track while effects play
Spc_Unk0A78 = $0A78             ; per-track update (Spc_StartSong, resume path)
Spc_Unk0B5C = $0B5C             ; rewrites bytes of Spc_BuiltinSampleLoop each pass
Spc_Unk1326 = $1326             ; adds timer 1's count to !Spc_Unk83
Spc_Unk12F9 = $12F9             ; waits (stepping commands) for the count at X
Spc_CmdSetEchoDelay = $132E     ; command $FC: echo delay = !Spc_CmdArg0 & $0F
Spc_Unk1316 = $1316             ; starts an echo change (Spc_StartSong)
Spc_Unk1397 = $1397             ; restarts timer 1 and clears FLG bit 5 (echo writes on)
Spc_SaveSong = $13A9            ; copies $F200-$F7FF, $0000-$007F and $0100-$018F aside
                                ; ($F800-$FF8F) and sets !Spc_SavedSong
Spc_RestoreSong = $13E5         ; copies them back, fades the song's volume in
Spc_Unk1438 = $1438             ; Spc_MainLoop's port report when !Spc_Flags88 bit 7 is set
Spc_Unk1492 = $1492             ; the volume fades (!Spc_GroupVol)
Spc_SetTrackSample = $1ACF      ; track X's sample = A, with its ParamA/ParamB words
Spc_Unk1AED = $1AED             ; writes track X's sample to its voice's SRCN, then more
Spc_EndTrack = $1D4C            ; ends the track in X (clears its bit in !Spc_SongTracks or
                                ; !Spc_SfxVoices)

; --- Data ---
Spc_XferModeTable = $1544       ; 8 words: the transfer modes' handlers (Spc_XferHeader)
Spc_CmdTable10 = $1680          ; 16 words: handlers of commands $10-$1F
Spc_CmdFirstTable10 = $16A0     ; 16 words: run before them (0: none)
Spc_CmdTable80 = $16C0          ; 32 words: handlers of $80-$8F and $F0-$FF
Spc_ShadowRegs = $1700          ; 17 bytes: the DSP registers Spc_MainLoop writes each pass
Spc_ShadowSources = $1711       ; 17 bytes: the direct-page byte each one is written from
Spc_TrackEndCmd = $1DC1         ; a lone sequence command $EB (ends a track, probably): the
                                ; last byte of the table at $1DB3
Spc_BuiltinSample = $1DC2       ; BRR: one silent block, then the loop
Spc_BuiltinSampleLoop = $1DCB   ; BRR: four blocks, the last with the end and loop flags
