; ============================================================
; Bank $CE — battle data, and battle display code bank $CD and $D1 call
; File offset 0x0E0000 (bank $CE = ROM offset $0E0000)
;
; Most of bank $CE is data, left as ROM bytes: the action scripts and
; object records bank $C1 reads (!BattleRom_ScriptsCE), and, after the
; code, the strings and tables banks $CD and $D1 read
; (!BattleRom_MsgStrings at $CE:EF11, the layer-effect and dissolve
; tables from $CE:EFE0, opcode $80's tables from $CE:F0E6, the HDMA
; sets !BattleRom_HdmaSetOfs / !BattleRom_HdmaSetRecs).
;
; $CE:E000-$CE:EF10 and $CE:F066-$CE:F0E5 are code with one table
; (BattleCE_WaveTable) inside it. The calls found are JSLs from banks
; $CD and $D1: four of the entries from the layer-effect code
; (BattleCD_FxOpHalfPlane, opcode $97; BattleCD_FxCopyLines, the window
; shapes' line copy; BattleCD_FxOpCopyWindowEdges, opcode $B2; and
; BattleCD_CalcAngle, part of opcode $CC's handler), the others from BattleCD_NmiMain,
; BattleCD_StepWipe, BattleFx_Init and BattleFx_ReloadCeSet. Inside
; the bank, BattleCE_DrawHalfPlane calls BattleCE_PresetWinEdges by JSR
; ($CE:EA88).
; (tools/xref.py's other hits into this range, from $C7:CCEA, $C7:E0CC,
; $C8:151E and $CA:81BB, sit in data, by symbols/code_survey.csv, and
; aim at the middle of an instruction, into BattleCE_WaveTable or at the
; data after the code: byte patterns, not calls.)
;
; The routines draw into the two window tables (!BattleFx_WinTable0/1,
; 4 bytes per line: the left and right edge of window 1, then of window
; 2; the table written is picked by bit 0 of !Battle_FrameCount,
; WinTable1 when it is set), load the HDMA tables' first entries,
; scroll layer 2 in a wave, take the angle between two points and park
; the sprites.
;
; The code runs as the battle engine's does: M=1, X=0, DP=0, DB=$7E
; unless a header says otherwise. Three entries keep the names their
; stubs had (BattleCE_UnkE18E, BattleCE_UnkEE6E, BattleCE_UnkF066):
; matched bank-$CD code calls them by those names.
; ============================================================

arch snes.cpu
hirom

org $CEE000

; ============================================================
; Window tables and the layer-2 wave ($CE:E000–$CE:E1C6)
; ============================================================

; $CE:E000 — BattleCE_CopyWindowEdges (142 bytes, $E000–$E08D)
; Copies one window's edge pair of 216 lines from the window table not
; written this frame into the one that is: from !BattleFx_WinTable0
; into !BattleFx_WinTable1 when bit 0 of !Battle_FrameCount is set,
; the other way when it is clear. The script byte at
; !BattleCD_FxScriptPtr (not stepped past here) times 2 is the byte
; offset s it starts at: s = 0 is window 1 of line 0, s = 2 window 2 of
; line 0. The copy runs with 8-bit X over s, s+4, ... up to s +
; !BattleCE_BlockBytes (exclusive), 27 steps, and moves the word at
; that offset in each of the eight blocks of !BattleCE_BlockLines lines:
; line 27j + X/4 (s/4 rounded down below). For s <= 150 (X does not
; wrap) that is the same pair of lines s/4 to s/4 + 215: lines 0-215
; for s < 4 (lines 216-223 are not copied), and for larger s also lines
; 216 to s/4 + 215. With s >= 36 (s/4 > 8) the copy runs past line 223
; (up to line 252 at most): into WinTable1 it reads WinTable1's own
; first lines (past WinTable0's end) and writes past its end
; ($7E:C861 on, !Battle_WinRegs); into WinTable0 it reads from $7E:C861
; on and writes over WinTable1's first lines. With s >= 152 X wraps:
; block j gets lines 27j + s/4 to 27j + 63 and 27j to 27j + s/4 - 38.
; The script bytes used are not traced. The ASL drops bit 7 of the
; byte (s is at most $FE).
; Callers note: the JSL at $CD:20D3 is the whole handler of layer-effect
;   script opcode $B2 (BattleCD_FxOpCopyWindowEdges, BattleCD_FxOpTable
;   entry $32; JSL, RTS).
; Callers (1 JSL site): BattleCD_FxOpCopyWindowEdges ($CD:20D3).
; Entry: M=1, X=0, DP=0 (DP operands; TDC as zero), DB=$7E (the tables
;        .w); the script pointer at DP $40, at the operand byte
;        (BattleCD_FxOpCopyWindowEdges calls it so)
; Exit:  M=1, X=0; A = 0; X = (s + $6C) & $FF; Y's low byte kept, high
;        byte cleared (SEP #$10); DP $45-$46 = s + $6C; DB unchanged
BattleCE_CopyWindowEdges:
    LDA.b [!BattleCD_FxScriptPtr]
    ASL A
    TAX
    REP #$20
    SEP #$10
    TXA
    CLC
    ADC.w #!BattleCE_BlockBytes
    STA.b !BattleCD_Tmp45                ; end offset (CPX reads its low byte)
    LDA.b !Battle_FrameCount
    AND.w #$0001
    BEQ .into_table0
.into_table1:
    LDA.w !BattleFx_WinTable0+(!BattleCE_BlockBytes*0),X
    STA.w !BattleFx_WinTable1+(!BattleCE_BlockBytes*0),X
    LDA.w !BattleFx_WinTable0+(!BattleCE_BlockBytes*1),X
    STA.w !BattleFx_WinTable1+(!BattleCE_BlockBytes*1),X
    LDA.w !BattleFx_WinTable0+(!BattleCE_BlockBytes*2),X
    STA.w !BattleFx_WinTable1+(!BattleCE_BlockBytes*2),X
    LDA.w !BattleFx_WinTable0+(!BattleCE_BlockBytes*3),X
    STA.w !BattleFx_WinTable1+(!BattleCE_BlockBytes*3),X
    LDA.w !BattleFx_WinTable0+(!BattleCE_BlockBytes*4),X
    STA.w !BattleFx_WinTable1+(!BattleCE_BlockBytes*4),X
    LDA.w !BattleFx_WinTable0+(!BattleCE_BlockBytes*5),X
    STA.w !BattleFx_WinTable1+(!BattleCE_BlockBytes*5),X
    LDA.w !BattleFx_WinTable0+(!BattleCE_BlockBytes*6),X
    STA.w !BattleFx_WinTable1+(!BattleCE_BlockBytes*6),X
    LDA.w !BattleFx_WinTable0+(!BattleCE_BlockBytes*7),X
    STA.w !BattleFx_WinTable1+(!BattleCE_BlockBytes*7),X
    INX
    INX
    INX
    INX
    CPX.b !BattleCD_Tmp45
    BNE .into_table1
    BRA .done
.into_table0:
    LDA.w !BattleFx_WinTable1+(!BattleCE_BlockBytes*0),X
    STA.w !BattleFx_WinTable0+(!BattleCE_BlockBytes*0),X
    LDA.w !BattleFx_WinTable1+(!BattleCE_BlockBytes*1),X
    STA.w !BattleFx_WinTable0+(!BattleCE_BlockBytes*1),X
    LDA.w !BattleFx_WinTable1+(!BattleCE_BlockBytes*2),X
    STA.w !BattleFx_WinTable0+(!BattleCE_BlockBytes*2),X
    LDA.w !BattleFx_WinTable1+(!BattleCE_BlockBytes*3),X
    STA.w !BattleFx_WinTable0+(!BattleCE_BlockBytes*3),X
    LDA.w !BattleFx_WinTable1+(!BattleCE_BlockBytes*4),X
    STA.w !BattleFx_WinTable0+(!BattleCE_BlockBytes*4),X
    LDA.w !BattleFx_WinTable1+(!BattleCE_BlockBytes*5),X
    STA.w !BattleFx_WinTable0+(!BattleCE_BlockBytes*5),X
    LDA.w !BattleFx_WinTable1+(!BattleCE_BlockBytes*6),X
    STA.w !BattleFx_WinTable0+(!BattleCE_BlockBytes*6),X
    LDA.w !BattleFx_WinTable1+(!BattleCE_BlockBytes*7),X
    STA.w !BattleFx_WinTable0+(!BattleCE_BlockBytes*7),X
    INX
    INX
    INX
    INX
    CPX.b !BattleCD_Tmp45
    BNE .into_table0
.done:
    TDC
    SEP #$20
    REP #$10
    RTL

; $CE:E08E — BattleCE_WaveTable (256 bytes, $E08E–$E18D)
; 128 signed words: a coarse wave of amplitude 2 (0, 1, 2, 1, 0, -1, -2,
; -1, each held for several words) with a period of 64 words, written
; twice so that any 64-word window of the first half reads on without a
; seam. BattleCE_UnkE18E copies a 64-word window of it, moved one
; (x, y) pair at a time, to !BattleCE_Bg2WaveLines.
BattleCE_WaveTable:
    dw 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2
    dw 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 0, 0
    dw 0, 0, 0, 0, -1, -1, -1, -1, -2, -2, -2, -2, -2, -2, -2, -2
    dw -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -1, -1, -1, -1, 0, 0
    dw 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2  ; the second period
    dw 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 0, 0
    dw 0, 0, 0, 0, -1, -1, -1, -1, -2, -2, -2, -2, -2, -2, -2, -2
    dw -2, -2, -2, -2, -2, -2, -2, -2, -2, -2, -1, -1, -1, -1, 0, 0

; $CE:E18E — BattleCE_UnkE18E (57 bytes, $E18E–$E1C6)
; The layer-2 wave, a frame's step (the name is the stub's: matched
; bank-$CD code calls it so). With !BattleFx_UnkCDC8 non-zero it zeroes
; the $80 bytes of !BattleCE_Bg2WaveLines; else it copies $80 bytes of
; BattleCE_WaveTable from pair ((!BattleFx_UnkCDC7 >> 2) & 31) into
; them and counts the byte !BattleFx_UnkCDC7 up, so the window moves on
; by one (x, y) pair every fourth call and comes round every 128 (that
; the bytes are layer-2 scroll lines is read from the HDMA sets in bank
; $CE: with !Battle_Unk2A21 bit 0 channel 2, BG2HOFS, points there; see
; !BattleCE_Bg2WaveLines).
; Callers (1 JSL site): BattleCD_NmiMain ($CD:097A).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E (BattleCD_NmiMain calls it
;        so, with !Battle_Unk2A21 bit 0 set); B = 0 assumed: the copy
;        path's 16-bit ASL/ADC/TAX after the 8-bit AND uses it (from
;        BattleCD_NmiMain's TDC, if its earlier callees keep it; not
;        traced)
; Exit:  M=1, X=0, DB unchanged (PHB/PLB around the MVN); A = 0; zeroing:
;        X = !BattleCE_WaveBytes, Y unchanged; copying: X = the end of
;        the source, Y = !BattleCE_Bg2WaveLines + $80
BattleCE_UnkE18E:
    LDA.w !BattleFx_UnkCDC8
    BEQ .copy
    TDC
    TAX
    REP #$20
.zero:
    STZ.w !BattleCE_Bg2WaveLines,X
    INX
    INX
    CPX.w #!BattleCE_WaveBytes
    BNE .zero
    TDC
    SEP #$20
    RTL
.copy:
    PHB
    LDA.w !BattleFx_UnkCDC7
    INC.w !BattleFx_UnkCDC7
    LSR A
    LSR A
    AND.b #!BattleCE_WaveSteps
    REP #$20
    ASL A
    ASL A
    CLC
    ADC.w #BattleCE_WaveTable
    TAX
    LDY.w #!BattleCE_Bg2WaveLines
    LDA.w #!BattleCE_WaveBytes-1
    MVN !Battle_WramBank,!BattleCE_RomBank ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    TDC
    SEP #$20
    PLB
    RTL

; ============================================================
; The word copier and the angle ($CE:E1C7–$CE:E884)
; ============================================================

; $CE:E1C7 — BattleCE_CopyWordsToLines (1537 bytes, $E1C7–$E7C7)
; 256 unrolled pairs LDA (2k),Y / STA (4k),X for k = 255 down to 0, then
; RTS. It is entered part way: BattleCE_RunCopyWords jumps to $E7C7 -
; 6n (each pair is 6 bytes), which runs the last n pairs: word k of the
; source at Y goes to X + 4k for k = n-1 down to 0, i.e. one word a
; line into a 4-byte-per-line table. Its one caller, BattleCD_FxCopyLines
; (through BattleCE_RunCopyWords), passes X = !BattleFx_WinTable1 or
; WinTable0 (by the frame bit) plus a line's offset and the window's
; byte, Y in !Battle_FxWinLines ($7E:B900 on), and n = the lines of a
; window shape (BattleCD_FxCopyShape and its kin).
; Callers note: none by call; entered through BattleCE_RunCopyWords'
;   JMP (!BattleCE_CopyEntry), at any multiple of 6 before $E7C7.
; Entry: M=0 (16-bit words; BattleCD_FxCopyLines runs 16-bit), X=0, DP
;        any (no DP operand), DB=$7E (both sides .w)
; Exit:  RTS (to BattleCE_RunCopyWords); M, X, DB unchanged; A = the
;        source's word 0 (n > 0); X and Y unchanged
BattleCE_CopyWordsToLines:
    LDA.w 2*255,Y
    STA.w 4*255,X
    LDA.w 2*254,Y
    STA.w 4*254,X
    LDA.w 2*253,Y
    STA.w 4*253,X
    LDA.w 2*252,Y
    STA.w 4*252,X
    LDA.w 2*251,Y
    STA.w 4*251,X
    LDA.w 2*250,Y
    STA.w 4*250,X
    LDA.w 2*249,Y
    STA.w 4*249,X
    LDA.w 2*248,Y
    STA.w 4*248,X
    LDA.w 2*247,Y
    STA.w 4*247,X
    LDA.w 2*246,Y
    STA.w 4*246,X
    LDA.w 2*245,Y
    STA.w 4*245,X
    LDA.w 2*244,Y
    STA.w 4*244,X
    LDA.w 2*243,Y
    STA.w 4*243,X
    LDA.w 2*242,Y
    STA.w 4*242,X
    LDA.w 2*241,Y
    STA.w 4*241,X
    LDA.w 2*240,Y
    STA.w 4*240,X
    LDA.w 2*239,Y
    STA.w 4*239,X
    LDA.w 2*238,Y
    STA.w 4*238,X
    LDA.w 2*237,Y
    STA.w 4*237,X
    LDA.w 2*236,Y
    STA.w 4*236,X
    LDA.w 2*235,Y
    STA.w 4*235,X
    LDA.w 2*234,Y
    STA.w 4*234,X
    LDA.w 2*233,Y
    STA.w 4*233,X
    LDA.w 2*232,Y
    STA.w 4*232,X
    LDA.w 2*231,Y
    STA.w 4*231,X
    LDA.w 2*230,Y
    STA.w 4*230,X
    LDA.w 2*229,Y
    STA.w 4*229,X
    LDA.w 2*228,Y
    STA.w 4*228,X
    LDA.w 2*227,Y
    STA.w 4*227,X
    LDA.w 2*226,Y
    STA.w 4*226,X
    LDA.w 2*225,Y
    STA.w 4*225,X
    LDA.w 2*224,Y
    STA.w 4*224,X
    LDA.w 2*223,Y
    STA.w 4*223,X
    LDA.w 2*222,Y
    STA.w 4*222,X
    LDA.w 2*221,Y
    STA.w 4*221,X
    LDA.w 2*220,Y
    STA.w 4*220,X
    LDA.w 2*219,Y
    STA.w 4*219,X
    LDA.w 2*218,Y
    STA.w 4*218,X
    LDA.w 2*217,Y
    STA.w 4*217,X
    LDA.w 2*216,Y
    STA.w 4*216,X
    LDA.w 2*215,Y
    STA.w 4*215,X
    LDA.w 2*214,Y
    STA.w 4*214,X
    LDA.w 2*213,Y
    STA.w 4*213,X
    LDA.w 2*212,Y
    STA.w 4*212,X
    LDA.w 2*211,Y
    STA.w 4*211,X
    LDA.w 2*210,Y
    STA.w 4*210,X
    LDA.w 2*209,Y
    STA.w 4*209,X
    LDA.w 2*208,Y
    STA.w 4*208,X
    LDA.w 2*207,Y
    STA.w 4*207,X
    LDA.w 2*206,Y
    STA.w 4*206,X
    LDA.w 2*205,Y
    STA.w 4*205,X
    LDA.w 2*204,Y
    STA.w 4*204,X
    LDA.w 2*203,Y
    STA.w 4*203,X
    LDA.w 2*202,Y
    STA.w 4*202,X
    LDA.w 2*201,Y
    STA.w 4*201,X
    LDA.w 2*200,Y
    STA.w 4*200,X
    LDA.w 2*199,Y
    STA.w 4*199,X
    LDA.w 2*198,Y
    STA.w 4*198,X
    LDA.w 2*197,Y
    STA.w 4*197,X
    LDA.w 2*196,Y
    STA.w 4*196,X
    LDA.w 2*195,Y
    STA.w 4*195,X
    LDA.w 2*194,Y
    STA.w 4*194,X
    LDA.w 2*193,Y
    STA.w 4*193,X
    LDA.w 2*192,Y
    STA.w 4*192,X
    LDA.w 2*191,Y
    STA.w 4*191,X
    LDA.w 2*190,Y
    STA.w 4*190,X
    LDA.w 2*189,Y
    STA.w 4*189,X
    LDA.w 2*188,Y
    STA.w 4*188,X
    LDA.w 2*187,Y
    STA.w 4*187,X
    LDA.w 2*186,Y
    STA.w 4*186,X
    LDA.w 2*185,Y
    STA.w 4*185,X
    LDA.w 2*184,Y
    STA.w 4*184,X
    LDA.w 2*183,Y
    STA.w 4*183,X
    LDA.w 2*182,Y
    STA.w 4*182,X
    LDA.w 2*181,Y
    STA.w 4*181,X
    LDA.w 2*180,Y
    STA.w 4*180,X
    LDA.w 2*179,Y
    STA.w 4*179,X
    LDA.w 2*178,Y
    STA.w 4*178,X
    LDA.w 2*177,Y
    STA.w 4*177,X
    LDA.w 2*176,Y
    STA.w 4*176,X
    LDA.w 2*175,Y
    STA.w 4*175,X
    LDA.w 2*174,Y
    STA.w 4*174,X
    LDA.w 2*173,Y
    STA.w 4*173,X
    LDA.w 2*172,Y
    STA.w 4*172,X
    LDA.w 2*171,Y
    STA.w 4*171,X
    LDA.w 2*170,Y
    STA.w 4*170,X
    LDA.w 2*169,Y
    STA.w 4*169,X
    LDA.w 2*168,Y
    STA.w 4*168,X
    LDA.w 2*167,Y
    STA.w 4*167,X
    LDA.w 2*166,Y
    STA.w 4*166,X
    LDA.w 2*165,Y
    STA.w 4*165,X
    LDA.w 2*164,Y
    STA.w 4*164,X
    LDA.w 2*163,Y
    STA.w 4*163,X
    LDA.w 2*162,Y
    STA.w 4*162,X
    LDA.w 2*161,Y
    STA.w 4*161,X
    LDA.w 2*160,Y
    STA.w 4*160,X
    LDA.w 2*159,Y
    STA.w 4*159,X
    LDA.w 2*158,Y
    STA.w 4*158,X
    LDA.w 2*157,Y
    STA.w 4*157,X
    LDA.w 2*156,Y
    STA.w 4*156,X
    LDA.w 2*155,Y
    STA.w 4*155,X
    LDA.w 2*154,Y
    STA.w 4*154,X
    LDA.w 2*153,Y
    STA.w 4*153,X
    LDA.w 2*152,Y
    STA.w 4*152,X
    LDA.w 2*151,Y
    STA.w 4*151,X
    LDA.w 2*150,Y
    STA.w 4*150,X
    LDA.w 2*149,Y
    STA.w 4*149,X
    LDA.w 2*148,Y
    STA.w 4*148,X
    LDA.w 2*147,Y
    STA.w 4*147,X
    LDA.w 2*146,Y
    STA.w 4*146,X
    LDA.w 2*145,Y
    STA.w 4*145,X
    LDA.w 2*144,Y
    STA.w 4*144,X
    LDA.w 2*143,Y
    STA.w 4*143,X
    LDA.w 2*142,Y
    STA.w 4*142,X
    LDA.w 2*141,Y
    STA.w 4*141,X
    LDA.w 2*140,Y
    STA.w 4*140,X
    LDA.w 2*139,Y
    STA.w 4*139,X
    LDA.w 2*138,Y
    STA.w 4*138,X
    LDA.w 2*137,Y
    STA.w 4*137,X
    LDA.w 2*136,Y
    STA.w 4*136,X
    LDA.w 2*135,Y
    STA.w 4*135,X
    LDA.w 2*134,Y
    STA.w 4*134,X
    LDA.w 2*133,Y
    STA.w 4*133,X
    LDA.w 2*132,Y
    STA.w 4*132,X
    LDA.w 2*131,Y
    STA.w 4*131,X
    LDA.w 2*130,Y
    STA.w 4*130,X
    LDA.w 2*129,Y
    STA.w 4*129,X
    LDA.w 2*128,Y
    STA.w 4*128,X
    LDA.w 2*127,Y
    STA.w 4*127,X
    LDA.w 2*126,Y
    STA.w 4*126,X
    LDA.w 2*125,Y
    STA.w 4*125,X
    LDA.w 2*124,Y
    STA.w 4*124,X
    LDA.w 2*123,Y
    STA.w 4*123,X
    LDA.w 2*122,Y
    STA.w 4*122,X
    LDA.w 2*121,Y
    STA.w 4*121,X
    LDA.w 2*120,Y
    STA.w 4*120,X
    LDA.w 2*119,Y
    STA.w 4*119,X
    LDA.w 2*118,Y
    STA.w 4*118,X
    LDA.w 2*117,Y
    STA.w 4*117,X
    LDA.w 2*116,Y
    STA.w 4*116,X
    LDA.w 2*115,Y
    STA.w 4*115,X
    LDA.w 2*114,Y
    STA.w 4*114,X
    LDA.w 2*113,Y
    STA.w 4*113,X
    LDA.w 2*112,Y
    STA.w 4*112,X
    LDA.w 2*111,Y
    STA.w 4*111,X
    LDA.w 2*110,Y
    STA.w 4*110,X
    LDA.w 2*109,Y
    STA.w 4*109,X
    LDA.w 2*108,Y
    STA.w 4*108,X
    LDA.w 2*107,Y
    STA.w 4*107,X
    LDA.w 2*106,Y
    STA.w 4*106,X
    LDA.w 2*105,Y
    STA.w 4*105,X
    LDA.w 2*104,Y
    STA.w 4*104,X
    LDA.w 2*103,Y
    STA.w 4*103,X
    LDA.w 2*102,Y
    STA.w 4*102,X
    LDA.w 2*101,Y
    STA.w 4*101,X
    LDA.w 2*100,Y
    STA.w 4*100,X
    LDA.w 2*99,Y
    STA.w 4*99,X
    LDA.w 2*98,Y
    STA.w 4*98,X
    LDA.w 2*97,Y
    STA.w 4*97,X
    LDA.w 2*96,Y
    STA.w 4*96,X
    LDA.w 2*95,Y
    STA.w 4*95,X
    LDA.w 2*94,Y
    STA.w 4*94,X
    LDA.w 2*93,Y
    STA.w 4*93,X
    LDA.w 2*92,Y
    STA.w 4*92,X
    LDA.w 2*91,Y
    STA.w 4*91,X
    LDA.w 2*90,Y
    STA.w 4*90,X
    LDA.w 2*89,Y
    STA.w 4*89,X
    LDA.w 2*88,Y
    STA.w 4*88,X
    LDA.w 2*87,Y
    STA.w 4*87,X
    LDA.w 2*86,Y
    STA.w 4*86,X
    LDA.w 2*85,Y
    STA.w 4*85,X
    LDA.w 2*84,Y
    STA.w 4*84,X
    LDA.w 2*83,Y
    STA.w 4*83,X
    LDA.w 2*82,Y
    STA.w 4*82,X
    LDA.w 2*81,Y
    STA.w 4*81,X
    LDA.w 2*80,Y
    STA.w 4*80,X
    LDA.w 2*79,Y
    STA.w 4*79,X
    LDA.w 2*78,Y
    STA.w 4*78,X
    LDA.w 2*77,Y
    STA.w 4*77,X
    LDA.w 2*76,Y
    STA.w 4*76,X
    LDA.w 2*75,Y
    STA.w 4*75,X
    LDA.w 2*74,Y
    STA.w 4*74,X
    LDA.w 2*73,Y
    STA.w 4*73,X
    LDA.w 2*72,Y
    STA.w 4*72,X
    LDA.w 2*71,Y
    STA.w 4*71,X
    LDA.w 2*70,Y
    STA.w 4*70,X
    LDA.w 2*69,Y
    STA.w 4*69,X
    LDA.w 2*68,Y
    STA.w 4*68,X
    LDA.w 2*67,Y
    STA.w 4*67,X
    LDA.w 2*66,Y
    STA.w 4*66,X
    LDA.w 2*65,Y
    STA.w 4*65,X
    LDA.w 2*64,Y
    STA.w 4*64,X
    LDA.w 2*63,Y
    STA.w 4*63,X
    LDA.w 2*62,Y
    STA.w 4*62,X
    LDA.w 2*61,Y
    STA.w 4*61,X
    LDA.w 2*60,Y
    STA.w 4*60,X
    LDA.w 2*59,Y
    STA.w 4*59,X
    LDA.w 2*58,Y
    STA.w 4*58,X
    LDA.w 2*57,Y
    STA.w 4*57,X
    LDA.w 2*56,Y
    STA.w 4*56,X
    LDA.w 2*55,Y
    STA.w 4*55,X
    LDA.w 2*54,Y
    STA.w 4*54,X
    LDA.w 2*53,Y
    STA.w 4*53,X
    LDA.w 2*52,Y
    STA.w 4*52,X
    LDA.w 2*51,Y
    STA.w 4*51,X
    LDA.w 2*50,Y
    STA.w 4*50,X
    LDA.w 2*49,Y
    STA.w 4*49,X
    LDA.w 2*48,Y
    STA.w 4*48,X
    LDA.w 2*47,Y
    STA.w 4*47,X
    LDA.w 2*46,Y
    STA.w 4*46,X
    LDA.w 2*45,Y
    STA.w 4*45,X
    LDA.w 2*44,Y
    STA.w 4*44,X
    LDA.w 2*43,Y
    STA.w 4*43,X
    LDA.w 2*42,Y
    STA.w 4*42,X
    LDA.w 2*41,Y
    STA.w 4*41,X
    LDA.w 2*40,Y
    STA.w 4*40,X
    LDA.w 2*39,Y
    STA.w 4*39,X
    LDA.w 2*38,Y
    STA.w 4*38,X
    LDA.w 2*37,Y
    STA.w 4*37,X
    LDA.w 2*36,Y
    STA.w 4*36,X
    LDA.w 2*35,Y
    STA.w 4*35,X
    LDA.w 2*34,Y
    STA.w 4*34,X
    LDA.w 2*33,Y
    STA.w 4*33,X
    LDA.w 2*32,Y
    STA.w 4*32,X
    LDA.w 2*31,Y
    STA.w 4*31,X
    LDA.w 2*30,Y
    STA.w 4*30,X
    LDA.w 2*29,Y
    STA.w 4*29,X
    LDA.w 2*28,Y
    STA.w 4*28,X
    LDA.w 2*27,Y
    STA.w 4*27,X
    LDA.w 2*26,Y
    STA.w 4*26,X
    LDA.w 2*25,Y
    STA.w 4*25,X
    LDA.w 2*24,Y
    STA.w 4*24,X
    LDA.w 2*23,Y
    STA.w 4*23,X
    LDA.w 2*22,Y
    STA.w 4*22,X
    LDA.w 2*21,Y
    STA.w 4*21,X
    LDA.w 2*20,Y
    STA.w 4*20,X
    LDA.w 2*19,Y
    STA.w 4*19,X
    LDA.w 2*18,Y
    STA.w 4*18,X
    LDA.w 2*17,Y
    STA.w 4*17,X
    LDA.w 2*16,Y
    STA.w 4*16,X
    LDA.w 2*15,Y
    STA.w 4*15,X
    LDA.w 2*14,Y
    STA.w 4*14,X
    LDA.w 2*13,Y
    STA.w 4*13,X
    LDA.w 2*12,Y
    STA.w 4*12,X
    LDA.w 2*11,Y
    STA.w 4*11,X
    LDA.w 2*10,Y
    STA.w 4*10,X
    LDA.w 2*9,Y
    STA.w 4*9,X
    LDA.w 2*8,Y
    STA.w 4*8,X
    LDA.w 2*7,Y
    STA.w 4*7,X
    LDA.w 2*6,Y
    STA.w 4*6,X
    LDA.w 2*5,Y
    STA.w 4*5,X
    LDA.w 2*4,Y
    STA.w 4*4,X
    LDA.w 2*3,Y
    STA.w 4*3,X
    LDA.w 2*2,Y
    STA.w 4*2,X
    LDA.w 2*1,Y
    STA.w 4*1,X
    LDA.w 2*0,Y
    STA.w 4*0,X
    RTS

; $CE:E7C8 — BattleCE_RunCopyWords (7 bytes, $E7C8–$E7CE)
; JSL entry for BattleCE_CopyWordsToLines: JSR to a JMP
; (!BattleCE_CopyEntry), so that the copy's RTS comes back here for the
; RTL. JMP (abs) reads its pointer from bank $00, so the callers' store
; to DP $4B (DP=0) is what it reads.
; Callers note: both JSLs ($CD:3640, $CD:3652) are in
;   BattleCD_FxCopyLines, one per window table (by the frame bit).
; Callers (2 JSL sites): BattleCD_FxCopyLines ($CD:3640, $CD:3652).
; Entry: M=0 (as BattleCE_CopyWordsToLines), X=0, DP=0 (the pointer at
;        $00:004B is DP $4B), DB=$7E; X, Y and !BattleCE_CopyEntry as
;        BattleCE_CopyWordsToLines takes them (BattleCD_FxCopyLines
;        enters so)
; Exit:  as BattleCE_CopyWordsToLines: M, X, DB unchanged; A = the
;        source's word 0; X and Y unchanged
BattleCE_RunCopyWords:
    JSR .jump
    RTL
.jump:
    JMP (!BattleCE_CopyEntry)

; $CE:E7CF — BattleCE_CalcAngle (182 bytes, $E7CF–$E884)
; The direction from the second point to the first, 256 per turn, as
; Battle_CalcAngle (bank $C1) works it out: the signed differences dx =
; AX - BX and dy = AY - BY, the base angle from !BattleRom_AngleTable at
; (|dy| / 8) x 32 + |dx| / 8, and the quadrant from the signs: $80 +
; base (dx >= 0, dy >= 0), $80 - base (dx >= 0, dy < 0), 0 - base (dx <
; 0, dy >= 0) or base (both < 0). Differences from that routine:
;   - first both x are lowered by AX & 7 and both y by AY & 7 (written
;     back to DP $23-$26). The difference is the same unless the second
;     point's coordinate wraps below 0, which turns it into the
;     difference - 256 (a quirk, kept as found);
;   - |dx| and |dy| get + 8 when their bit 2 is set, so the /8 rounds
;     to the nearest instead of down;
;   - the result is left in DP $45.
; A difference of 252 or more rounds to 32 eighths: the run then reads
; into the next row of the table, the rise past its end (not guarded).
; Callers note: the JSL at $CD:1B37 is in BattleCD_CalcAngle (the
;   sub-entry of BattleCD_ClampCalcAngle, $CD:1B1F, which is also
;   layer-effect script opcode $CC's handler); it loads the two points
;   from the 4-byte entry !Battle_ActCalcResult + X ($7E:5DA0 + X) and
;   stores DP $45 in !Battle_FxAngle ($CD08).
; Callers (1 JSL site): BattleCD_CalcAngle ($CD:1B37).
; Entry: M=1, X=0 (16-bit index), DP=0 (DP operands; TDC as zero), DB
;        any (the table read long; BattleCD_CalcAngle has DB=$7E);
;        !BattleCE_AngleAX/AY and !BattleCE_AngleBX/BY (BattleCD_CalcAngle
;        sets them)
; Exit:  M=1, X=0; !BattleCE_Angle (DP $45) = the angle; A = the angle
;        too, except with dx and dy both negative (A = $FF, dy's sign
;        byte); X = the table index; Y and DB unchanged; DP $23-$2A and
;        $45-$4D written
BattleCE_CalcAngle:
    LDA.b !BattleCE_AngleAX
    AND.b #$07
    STA.b !BattleCE_AngleLowBits
    LDA.b !BattleCE_AngleAX
    SEC
    SBC.b !BattleCE_AngleLowBits
    STA.b !BattleCE_AngleAX
    LDA.b !BattleCE_AngleBX
    SEC
    SBC.b !BattleCE_AngleLowBits
    STA.b !BattleCE_AngleBX
    LDA.b !BattleCE_AngleAY
    AND.b #$07
    STA.b !BattleCE_AngleLowBits
    LDA.b !BattleCE_AngleAY
    SEC
    SBC.b !BattleCE_AngleLowBits
    STA.b !BattleCE_AngleAY
    LDA.b !BattleCE_AngleBY
    SEC
    SBC.b !BattleCE_AngleLowBits
    STA.b !BattleCE_AngleBY
    LDA.b !BattleCE_AngleAX
    SEC
    SBC.b !BattleCE_AngleBX
    STA.b !BattleCE_AngleDX
    LDA.b #$00
    SBC.b #$00                          ; the borrow into the high byte
    STA.b !BattleCE_AngleDX+1
    LDA.b !BattleCE_AngleAY
    SEC
    SBC.b !BattleCE_AngleBY
    STA.b !BattleCE_AngleDY
    LDA.b #$00
    SBC.b #$00
    STA.b !BattleCE_AngleDY+1
    LDA.b !BattleCE_AngleDX             ; |dx|: EOR and subtract the sign byte
    EOR.b !BattleCE_AngleDX+1
    SEC
    SBC.b !BattleCE_AngleDX+1
    STA.b !BattleCE_AngleAbsDX
    STZ.b !BattleCE_AngleAbsDX+1
    LDA.b !BattleCE_AngleDY
    EOR.b !BattleCE_AngleDY+1
    SEC
    SBC.b !BattleCE_AngleDY+1
    STA.b !BattleCE_AngleAbsDY
    STZ.b !BattleCE_AngleAbsDY+1
    REP #$20
    LDA.b !BattleCE_AngleAbsDX
    BIT.w #!BattleCE_RunMask
    BEQ .dx_rounded
    CLC
    ADC.w #!BattleCE_RoundUp
    STA.b !BattleCE_AngleAbsDX
.dx_rounded:
    LDA.b !BattleCE_AngleAbsDY
    BIT.w #!BattleCE_RunMask
    BEQ .dy_rounded
    CLC
    ADC.w #!BattleCE_RoundUp
    STA.b !BattleCE_AngleAbsDY
.dy_rounded:
    LDA.b !BattleCE_AngleAbsDX
    LSR A
    LSR A
    LSR A
    STA.b !BattleCE_AngleRun
    LDA.b !BattleCE_AngleAbsDY
    AND.w #!BattleCE_AngleMask
    ASL A
    ASL A
    CLC
    ADC.b !BattleCE_AngleRun
    STA.b !BattleCE_AngleIndex
    TDC
    SEP #$20
    LDX.b !BattleCE_AngleIndex
    LDA.l !BattleRom_AngleTable,X
    STA.b !BattleCE_Angle
    LDA.b !BattleCE_AngleDX+1
    BMI .dx_negative
    LDA.b !BattleCE_AngleDY+1
    BMI .dy_negative
    LDA.b #!BattleCE_HalfTurn           ; dx >= 0, dy >= 0: $80 + base
    CLC
    ADC.b !BattleCE_Angle
    STA.b !BattleCE_Angle
    RTL
.dy_negative:                           ; dx >= 0, dy < 0: $80 - base
    LDA.b #!BattleCE_HalfTurn
    SEC
    SBC.b !BattleCE_Angle
    STA.b !BattleCE_Angle
    RTL
.dx_negative:
    LDA.b !BattleCE_AngleDY+1
    BMI .both_negative
    LDA.b #$00                          ; dx < 0, dy >= 0: 0 - base
    SEC
    SBC.b !BattleCE_Angle
    STA.b !BattleCE_Angle
.both_negative:                         ; both < 0: the base as it is
    RTL

; ============================================================
; The half-plane window (layer-effect opcode $97) ($CE:E885–$CE:EE6D)
; ============================================================

; $CE:E885 — BattleCE_PresetWinEdges (505 bytes, $E885–$EA7D)
; The first step of BattleCE_DrawHalfPlane: sets the edge the line will
; not draw, on all 224 lines of this frame's window table (WinTable1
; when bit 0 of !Battle_FrameCount is set), for the window picked by
; bit 1 of !BattleCE_EdgeOfs (0: window 1, bytes 0-1; 1: window 2,
; bytes 2-3):
;   - !BattleCE_LineAngle $00-$7F (the line's far point in the lower
;     half): the right edge = !BattleCE_EdgeMax;
;   - $80-$FF (upper half): the left edge = 0, and !BattleCE_EdgeOfs + 1,
;     so that the line is then drawn into the right edge.
; The loops write 16 blocks of !BattleCE_PresetLines lines, Y (8-bit)
; from !BattleCE_PresetBytes down to 4 (operand line 14k - 1 + Y / 4).
; Callers (1 JSR site): BattleCE_DrawHalfPlane ($CE:EA88).
; Entry: M=1, X=1 (8-bit Y), DP=0, DB=$7E (the tables .w);
;        !BattleCE_EdgeOfs = 0 or 2 (window 1 or 2)
; Exit:  M=1, X=1; Y = 0; X unchanged; A = the value written
;        (!BattleCE_EdgeMax or 0); !BattleCE_EdgeOfs + 1 on the $80-$FF
;        paths; DB unchanged
BattleCE_PresetWinEdges:
    LDY.b #!BattleCE_PresetBytes
    LDA.b !Battle_FrameCount
    AND.b #$01
    BNE .table1
    JMP .table0
.table1:
    LDA.w !BattleCE_LineAngle
    BMI .t1_left_edges
    LDA.b !BattleCE_EdgeOfs
    AND.b #$02
    BEQ .t1_right1
    LDA.b #!BattleCE_EdgeMax
.t1_right2:
    STA.w !BattleFx_WinTable1+((14*0-1)*4)+3,Y
    STA.w !BattleFx_WinTable1+((14*1-1)*4)+3,Y
    STA.w !BattleFx_WinTable1+((14*2-1)*4)+3,Y
    STA.w !BattleFx_WinTable1+((14*3-1)*4)+3,Y
    STA.w !BattleFx_WinTable1+((14*4-1)*4)+3,Y
    STA.w !BattleFx_WinTable1+((14*5-1)*4)+3,Y
    STA.w !BattleFx_WinTable1+((14*6-1)*4)+3,Y
    STA.w !BattleFx_WinTable1+((14*7-1)*4)+3,Y
    STA.w !BattleFx_WinTable1+((14*8-1)*4)+3,Y
    STA.w !BattleFx_WinTable1+((14*9-1)*4)+3,Y
    STA.w !BattleFx_WinTable1+((14*10-1)*4)+3,Y
    STA.w !BattleFx_WinTable1+((14*11-1)*4)+3,Y
    STA.w !BattleFx_WinTable1+((14*12-1)*4)+3,Y
    STA.w !BattleFx_WinTable1+((14*13-1)*4)+3,Y
    STA.w !BattleFx_WinTable1+((14*14-1)*4)+3,Y
    STA.w !BattleFx_WinTable1+((14*15-1)*4)+3,Y
    DEY
    DEY
    DEY
    DEY
    BNE .t1_right2
    RTS
.t1_right1:
    LDA.b #!BattleCE_EdgeMax
.t1_right1_loop:
    STA.w !BattleFx_WinTable1+((14*0-1)*4)+1,Y
    STA.w !BattleFx_WinTable1+((14*1-1)*4)+1,Y
    STA.w !BattleFx_WinTable1+((14*2-1)*4)+1,Y
    STA.w !BattleFx_WinTable1+((14*3-1)*4)+1,Y
    STA.w !BattleFx_WinTable1+((14*4-1)*4)+1,Y
    STA.w !BattleFx_WinTable1+((14*5-1)*4)+1,Y
    STA.w !BattleFx_WinTable1+((14*6-1)*4)+1,Y
    STA.w !BattleFx_WinTable1+((14*7-1)*4)+1,Y
    STA.w !BattleFx_WinTable1+((14*8-1)*4)+1,Y
    STA.w !BattleFx_WinTable1+((14*9-1)*4)+1,Y
    STA.w !BattleFx_WinTable1+((14*10-1)*4)+1,Y
    STA.w !BattleFx_WinTable1+((14*11-1)*4)+1,Y
    STA.w !BattleFx_WinTable1+((14*12-1)*4)+1,Y
    STA.w !BattleFx_WinTable1+((14*13-1)*4)+1,Y
    STA.w !BattleFx_WinTable1+((14*14-1)*4)+1,Y
    STA.w !BattleFx_WinTable1+((14*15-1)*4)+1,Y
    DEY
    DEY
    DEY
    DEY
    BNE .t1_right1_loop
    RTS
.t1_left_edges:
    LDA.b !BattleCE_EdgeOfs
    AND.b #$02
    BEQ .t1_left1
    TDC
.t1_left2:
    STA.w !BattleFx_WinTable1+((14*0-1)*4)+2,Y
    STA.w !BattleFx_WinTable1+((14*1-1)*4)+2,Y
    STA.w !BattleFx_WinTable1+((14*2-1)*4)+2,Y
    STA.w !BattleFx_WinTable1+((14*3-1)*4)+2,Y
    STA.w !BattleFx_WinTable1+((14*4-1)*4)+2,Y
    STA.w !BattleFx_WinTable1+((14*5-1)*4)+2,Y
    STA.w !BattleFx_WinTable1+((14*6-1)*4)+2,Y
    STA.w !BattleFx_WinTable1+((14*7-1)*4)+2,Y
    STA.w !BattleFx_WinTable1+((14*8-1)*4)+2,Y
    STA.w !BattleFx_WinTable1+((14*9-1)*4)+2,Y
    STA.w !BattleFx_WinTable1+((14*10-1)*4)+2,Y
    STA.w !BattleFx_WinTable1+((14*11-1)*4)+2,Y
    STA.w !BattleFx_WinTable1+((14*12-1)*4)+2,Y
    STA.w !BattleFx_WinTable1+((14*13-1)*4)+2,Y
    STA.w !BattleFx_WinTable1+((14*14-1)*4)+2,Y
    STA.w !BattleFx_WinTable1+((14*15-1)*4)+2,Y
    DEY
    DEY
    DEY
    DEY
    BNE .t1_left2
    INC.b !BattleCE_EdgeOfs
    RTS
.t1_left1:
    TDC
.t1_left1_loop:
    STA.w !BattleFx_WinTable1+((14*0-1)*4)+0,Y
    STA.w !BattleFx_WinTable1+((14*1-1)*4)+0,Y
    STA.w !BattleFx_WinTable1+((14*2-1)*4)+0,Y
    STA.w !BattleFx_WinTable1+((14*3-1)*4)+0,Y
    STA.w !BattleFx_WinTable1+((14*4-1)*4)+0,Y
    STA.w !BattleFx_WinTable1+((14*5-1)*4)+0,Y
    STA.w !BattleFx_WinTable1+((14*6-1)*4)+0,Y
    STA.w !BattleFx_WinTable1+((14*7-1)*4)+0,Y
    STA.w !BattleFx_WinTable1+((14*8-1)*4)+0,Y
    STA.w !BattleFx_WinTable1+((14*9-1)*4)+0,Y
    STA.w !BattleFx_WinTable1+((14*10-1)*4)+0,Y
    STA.w !BattleFx_WinTable1+((14*11-1)*4)+0,Y
    STA.w !BattleFx_WinTable1+((14*12-1)*4)+0,Y
    STA.w !BattleFx_WinTable1+((14*13-1)*4)+0,Y
    STA.w !BattleFx_WinTable1+((14*14-1)*4)+0,Y
    STA.w !BattleFx_WinTable1+((14*15-1)*4)+0,Y
    DEY
    DEY
    DEY
    DEY
    BNE .t1_left1_loop
    INC.b !BattleCE_EdgeOfs
    RTS
.table0:
    LDA.w !BattleCE_LineAngle
    BMI .t0_left_edges
    LDA.b !BattleCE_EdgeOfs
    AND.b #$02
    BEQ .t0_right1
    LDA.b #!BattleCE_EdgeMax
.t0_right2:
    STA.w !BattleFx_WinTable0+((14*0-1)*4)+3,Y
    STA.w !BattleFx_WinTable0+((14*1-1)*4)+3,Y
    STA.w !BattleFx_WinTable0+((14*2-1)*4)+3,Y
    STA.w !BattleFx_WinTable0+((14*3-1)*4)+3,Y
    STA.w !BattleFx_WinTable0+((14*4-1)*4)+3,Y
    STA.w !BattleFx_WinTable0+((14*5-1)*4)+3,Y
    STA.w !BattleFx_WinTable0+((14*6-1)*4)+3,Y
    STA.w !BattleFx_WinTable0+((14*7-1)*4)+3,Y
    STA.w !BattleFx_WinTable0+((14*8-1)*4)+3,Y
    STA.w !BattleFx_WinTable0+((14*9-1)*4)+3,Y
    STA.w !BattleFx_WinTable0+((14*10-1)*4)+3,Y
    STA.w !BattleFx_WinTable0+((14*11-1)*4)+3,Y
    STA.w !BattleFx_WinTable0+((14*12-1)*4)+3,Y
    STA.w !BattleFx_WinTable0+((14*13-1)*4)+3,Y
    STA.w !BattleFx_WinTable0+((14*14-1)*4)+3,Y
    STA.w !BattleFx_WinTable0+((14*15-1)*4)+3,Y
    DEY
    DEY
    DEY
    DEY
    BNE .t0_right2
    RTS
.t0_right1:
    LDA.b #!BattleCE_EdgeMax
.t0_right1_loop:
    STA.w !BattleFx_WinTable0+((14*0-1)*4)+1,Y
    STA.w !BattleFx_WinTable0+((14*1-1)*4)+1,Y
    STA.w !BattleFx_WinTable0+((14*2-1)*4)+1,Y
    STA.w !BattleFx_WinTable0+((14*3-1)*4)+1,Y
    STA.w !BattleFx_WinTable0+((14*4-1)*4)+1,Y
    STA.w !BattleFx_WinTable0+((14*5-1)*4)+1,Y
    STA.w !BattleFx_WinTable0+((14*6-1)*4)+1,Y
    STA.w !BattleFx_WinTable0+((14*7-1)*4)+1,Y
    STA.w !BattleFx_WinTable0+((14*8-1)*4)+1,Y
    STA.w !BattleFx_WinTable0+((14*9-1)*4)+1,Y
    STA.w !BattleFx_WinTable0+((14*10-1)*4)+1,Y
    STA.w !BattleFx_WinTable0+((14*11-1)*4)+1,Y
    STA.w !BattleFx_WinTable0+((14*12-1)*4)+1,Y
    STA.w !BattleFx_WinTable0+((14*13-1)*4)+1,Y
    STA.w !BattleFx_WinTable0+((14*14-1)*4)+1,Y
    STA.w !BattleFx_WinTable0+((14*15-1)*4)+1,Y
    DEY
    DEY
    DEY
    DEY
    BNE .t0_right1_loop
    RTS
.t0_left_edges:
    LDA.b !BattleCE_EdgeOfs
    AND.b #$02
    BEQ .t0_left1
    TDC
.t0_left2:
    STA.w !BattleFx_WinTable0+((14*0-1)*4)+2,Y
    STA.w !BattleFx_WinTable0+((14*1-1)*4)+2,Y
    STA.w !BattleFx_WinTable0+((14*2-1)*4)+2,Y
    STA.w !BattleFx_WinTable0+((14*3-1)*4)+2,Y
    STA.w !BattleFx_WinTable0+((14*4-1)*4)+2,Y
    STA.w !BattleFx_WinTable0+((14*5-1)*4)+2,Y
    STA.w !BattleFx_WinTable0+((14*6-1)*4)+2,Y
    STA.w !BattleFx_WinTable0+((14*7-1)*4)+2,Y
    STA.w !BattleFx_WinTable0+((14*8-1)*4)+2,Y
    STA.w !BattleFx_WinTable0+((14*9-1)*4)+2,Y
    STA.w !BattleFx_WinTable0+((14*10-1)*4)+2,Y
    STA.w !BattleFx_WinTable0+((14*11-1)*4)+2,Y
    STA.w !BattleFx_WinTable0+((14*12-1)*4)+2,Y
    STA.w !BattleFx_WinTable0+((14*13-1)*4)+2,Y
    STA.w !BattleFx_WinTable0+((14*14-1)*4)+2,Y
    STA.w !BattleFx_WinTable0+((14*15-1)*4)+2,Y
    DEY
    DEY
    DEY
    DEY
    BNE .t0_left2
    INC.b !BattleCE_EdgeOfs
    RTS
.t0_left1:
    TDC
.t0_left1_loop:
    STA.w !BattleFx_WinTable0+((14*0-1)*4)+0,Y
    STA.w !BattleFx_WinTable0+((14*1-1)*4)+0,Y
    STA.w !BattleFx_WinTable0+((14*2-1)*4)+0,Y
    STA.w !BattleFx_WinTable0+((14*3-1)*4)+0,Y
    STA.w !BattleFx_WinTable0+((14*4-1)*4)+0,Y
    STA.w !BattleFx_WinTable0+((14*5-1)*4)+0,Y
    STA.w !BattleFx_WinTable0+((14*6-1)*4)+0,Y
    STA.w !BattleFx_WinTable0+((14*7-1)*4)+0,Y
    STA.w !BattleFx_WinTable0+((14*8-1)*4)+0,Y
    STA.w !BattleFx_WinTable0+((14*9-1)*4)+0,Y
    STA.w !BattleFx_WinTable0+((14*10-1)*4)+0,Y
    STA.w !BattleFx_WinTable0+((14*11-1)*4)+0,Y
    STA.w !BattleFx_WinTable0+((14*12-1)*4)+0,Y
    STA.w !BattleFx_WinTable0+((14*13-1)*4)+0,Y
    STA.w !BattleFx_WinTable0+((14*14-1)*4)+0,Y
    STA.w !BattleFx_WinTable0+((14*15-1)*4)+0,Y
    DEY
    DEY
    DEY
    DEY
    BNE .t0_left1_loop
    INC.b !BattleCE_EdgeOfs
    RTS

; $CE:EA7E — BattleCE_DrawHalfPlane (1008 bytes, $EA7E–$EE6D)
; Layer-effect opcode $97's drawing: one window of this frame's window
; table (WinTable1 when bit 0 of !Battle_FrameCount is set, else
; WinTable0; the two halves of the code are the same but for the table)
; becomes the half of the screen on one side of a line through the
; screen centre. The bank-$CD handler BattleCD_FxOpHalfPlane has set the
; line: !BattleCE_LineP1/P2 are a point read by angle from
; !BattleRom_HalfPlaneEdge ($CE:F28E, on the screen's edge: angle 0 at (255, 112), $40 at the
; bottom, $80 at (0, 112), $C0 at the top) and the centre (128, 112),
; the upper one first; !BattleCE_LineDirX, !BattleCE_LineAbsDX/DY and
; !BattleCE_LineAngle (the angle); DP !BattleCE_LineX/Y = P1. Steps:
;   1. BattleCE_PresetWinEdges (with 8-bit X): the edge not drawn, on
;      every line (right = 255 for angles $00-$7F, left = 0 and the
;      offset + 1 for $80-$FF); !BattleCE_EdgeStart = P1's line offset
;      plus the edge's byte.
;   2. Angles $80-$FF with P1 below line 0: the right edges of lines 0
;      to P1.y - 1 are P1.x; or, with P1.x = 0, those lines get the pair
;      (255, 0) (empty); with P1.x = 255, right edge 255 and, from line
;      223 up over as many lines, the left edge 255.
;   3. The line walk, |dy| lines from P1.y: x starts at P1.x; on each
;      line, while the remainder (started at |dx|) is |dy| or more, take
;      |dy| off and step x by the direction; then add |dx|, and store x
;      (its low byte) as the line's edge. Nothing with |dy| = 0 (X then
;      holds 0 for step 4).
;   4. By A's bit 1 (window 1 or 2) and the angle:
;      - angle 0: lines 112-223 of the window get (255, 0), empty; RTS
;        (the upper half's left edges are not written);
;      - $01-$7F: unless the walk ended on the table's end, the lines
;        after it to line 223 get the last x as left edge; with x = 255
;        the pair (255, 0) instead; with x = 0 the left edge 0, and a
;        STZ also clears the right edge of lines 0 on (X counting up by
;        4 from the last x, here 0; kept as found: the mirror below
;        overwrites only the left edges of lines 0-111). Then lines
;        0-111 take the left edge of lines 223-112, mirrored (255 - x);
;      - $80-$FF: lines 223-112 take the right edge of lines 0-111,
;        mirrored.
;   So the window is the part right of the line (angles $00-$7F) or
;   left of it ($80-$FF), point-symmetric about the centre.
; Callers note: the JSL at $CD:3129 is in opcode $97's handler
;   (BattleCD_FxOpHalfPlane), with A = the script byte & $7F; B = 0 there
;   (TDC at $CD:30FC, then only 8-bit code, BattleCD_FxLineDeltas
;   included).
; Callers (1 JSL site): BattleCD_FxOpHalfPlane ($CD:3129).
; Entry: M=1, X=0, DP=0 (DP operands; TDC as zero), DB=$7E (the tables
;        and line bytes .w); A = !BattleCE_EdgeOfs: 0 or 2, the window's
;        left edge byte (bit 1 picks the window in step 4; other values
;        are not checked), B = 0 (the 16-bit TAY)
; Exit:  M=1, X=0; A, X, Y clobbered; DB unchanged; DP $45-$4C written
BattleCE_DrawHalfPlane:
    JSR .main
    RTL
.main:
    PHA
    TAY
    STY.b !BattleCE_EdgeOfs
    SEP #$10
    JSR BattleCE_PresetWinEdges
    REP #$10
    LDA.b !BattleCE_LineY
    REP #$20
    ASL A
    ASL A
    CLC
    ADC.b !BattleCE_EdgeOfs
    STA.b !BattleCE_EdgeStart
    TDC
    SEP #$20
    LDA.b !Battle_FrameCount
    AND.b #$01
    BEQ .table0
    JMP .table1
.table0:
    LDA.w !BattleCE_LineAngle
    BPL .t0_walk
    LDY.b !BattleCE_EdgeOfs
    CPY.b !BattleCE_EdgeStart
    BEQ .t0_walk
    LDA.b !BattleCE_LineX
    BEQ .t0_top_empty
    CMP.b #!BattleCE_EdgeMax
    BNE .t0_top_x
    REP #$20
    LDA.w #!BattleCE_LastLineOfs
    CLC
    ADC.b !BattleCE_EdgeOfs
    TAX
    TDC
    SEP #$20
    LDA.b #!BattleCE_EdgeMax
.t0_top_max:
    STA.w !BattleFx_WinTable0,Y
    STA.w !BattleFx_WinTable0-1,X                ; the left edge, from line 223 up
    DEX
    DEX
    DEX
    DEX
    INY
    INY
    INY
    INY
    CPY.b !BattleCE_EdgeStart
    BNE .t0_top_max
    BRA .t0_walk
.t0_top_empty:
    REP #$20
    LDA.w #!BattleFx_WinEmpty
.t0_top_empty_loop:
    STA.w !BattleFx_WinTable0-1,Y                ; the pair (255, 0)
    INY
    INY
    INY
    INY
    CPY.b !BattleCE_EdgeStart
    BNE .t0_top_empty_loop
    TDC
    SEP #$20
    BRA .t0_walk
.t0_top_x:
    STA.w !BattleFx_WinTable0,Y
    INY
    INY
    INY
    INY
    CPY.b !BattleCE_EdgeStart
    BNE .t0_top_x
.t0_walk:
    LDY.b !BattleCE_EdgeStart
    LDA.w !BattleCE_LineAbsDX
    TAX
    STX.b !BattleCE_StepAcc
    STX.b !BattleCE_StepDX
    LDA.w !BattleCE_LineAbsDY
    TAX
    STX.b !BattleCE_StepDY
    STX.b !BattleCE_StepRows
    BNE .t0_walk_start
    BRA .t0_tail
.t0_walk_start:
    LDA.b !BattleCE_LineX
    TAX
    LDA.w !BattleCE_LineDirX
    BMI .t0_walk_left
.t0_walk_right:
    LDA.b !BattleCE_StepAcc
.t0_step_right:
    CMP.b !BattleCE_StepDY
    BCC .t0_store_right
    SBC.b !BattleCE_StepDY
    INX
    BRA .t0_step_right
.t0_store_right:
    ADC.b !BattleCE_StepDX               ; C = 0 here
    STA.b !BattleCE_StepAcc
    TXA
    STA.w !BattleFx_WinTable0,Y
    INY
    INY
    INY
    INY
    DEC.b !BattleCE_StepRows
    BNE .t0_walk_right
    BRA .t0_tail
.t0_walk_left:
    LDA.b !BattleCE_StepAcc
.t0_step_left:
    CMP.b !BattleCE_StepDY
    BCC .t0_store_left
    SBC.b !BattleCE_StepDY
    DEX
    BRA .t0_step_left
.t0_store_left:
    ADC.b !BattleCE_StepDX
    STA.b !BattleCE_StepAcc
    TXA
    STA.w !BattleFx_WinTable0,Y
    INY
    INY
    INY
    INY
    DEC.b !BattleCE_StepRows
    BNE .t0_walk_left
.t0_tail:
    PLA
    AND.b #$02
    BEQ .t0_window1
    JMP .t0_window2
.t0_window1:
    LDA.w !BattleCE_LineAngle
    BMI .t0_w1_mirror_right
    BNE .t0_w1_rest
    TDC                                 ; angle 0: the lower half emptied
    TAY
    REP #$20
    LDA.w #!BattleFx_WinEmpty
.t0_w1_empty_lower:
    STA.w !BattleFx_WinTable0+!BattleCE_HalfTableBytes+0,Y
    INY
    INY
    INY
    INY
    CPY.w #!BattleCE_HalfTableBytes
    BNE .t0_w1_empty_lower
    TDC
    SEP #$20
    RTS
.t0_w1_rest:
    CPY.w #!BattleFx_WinTableBytes
    BEQ .t0_w1_mirror_left
    TXA
    CMP.b #!BattleCE_EdgeMax
    BNE .t0_w1_rest_not_max
    REP #$20
    LDA.w #!BattleFx_WinEmpty
.t0_w1_rest_empty:
    STA.w !BattleFx_WinTable0,Y
    INY
    INY
    INY
    INY
    CPY.w #!BattleFx_WinTableBytes
    BCC .t0_w1_rest_empty
    TDC
    SEP #$20
    BRA .t0_w1_mirror_left
.t0_w1_rest_not_max:
    CMP.b #0
    BNE .t0_w1_rest_x
.t0_w1_rest_zero:
    STA.w !BattleFx_WinTable0,Y
    STZ.w !BattleFx_WinTable0+1,X              ; X from 0 up: right edges of lines 0 on (kept as found)
    INX
    INX
    INX
    INX
    INY
    INY
    INY
    INY
    CPY.w #!BattleFx_WinTableBytes
    BCC .t0_w1_rest_zero
    BRA .t0_w1_mirror_left
.t0_w1_rest_x:
    STA.w !BattleFx_WinTable0,Y
    INY
    INY
    INY
    INY
    CPY.w #!BattleFx_WinTableBytes
    BCC .t0_w1_rest_x
.t0_w1_mirror_left:
    TDC
    TAY
    LDX.w #!BattleCE_LastLineOfs
.t0_w1_mirror_left_loop:
    LDA.w !BattleFx_WinTable0+0,X
    EOR.b #!BattleCE_MirrorX
    STA.w !BattleFx_WinTable0+0,Y
    DEX
    DEX
    DEX
    DEX
    INY
    INY
    INY
    INY
    CPY.w #!BattleCE_HalfTableBytes
    BNE .t0_w1_mirror_left_loop
    RTS
.t0_w1_mirror_right:
    TDC
    TAX
    LDY.w #!BattleCE_LastLineOfs
.t0_w1_mirror_right_loop:
    LDA.w !BattleFx_WinTable0+1,X
    EOR.b #!BattleCE_MirrorX
    STA.w !BattleFx_WinTable0+1,Y
    INX
    INX
    INX
    INX
    DEY
    DEY
    DEY
    DEY
    CPX.w #!BattleCE_HalfTableBytes
    BNE .t0_w1_mirror_right_loop
    RTS
.t0_window2:
    LDA.w !BattleCE_LineAngle
    BMI .t0_w2_mirror_right
    BNE .t0_w2_rest
    TDC                                 ; angle 0: the lower half emptied
    TAY
    REP #$20
    LDA.w #!BattleFx_WinEmpty
.t0_w2_empty_lower:
    STA.w !BattleFx_WinTable0+!BattleCE_HalfTableBytes+2,Y
    INY
    INY
    INY
    INY
    CPY.w #!BattleCE_HalfTableBytes
    BNE .t0_w2_empty_lower
    TDC
    SEP #$20
    RTS
.t0_w2_rest:
    CPY.w #!BattleFx_WinTableBytes+2
    BEQ .t0_w2_mirror_left
    TXA
    CMP.b #!BattleCE_EdgeMax
    BNE .t0_w2_rest_not_max
    REP #$20
    LDA.w #!BattleFx_WinEmpty
.t0_w2_rest_empty:
    STA.w !BattleFx_WinTable0,Y
    INY
    INY
    INY
    INY
    CPY.w #!BattleFx_WinTableBytes+2
    BCC .t0_w2_rest_empty
    TDC
    SEP #$20
    BRA .t0_w2_mirror_left
.t0_w2_rest_not_max:
    CMP.b #0
    BNE .t0_w2_rest_x
.t0_w2_rest_zero:
    STA.w !BattleFx_WinTable0,Y
    STZ.w !BattleFx_WinTable0+3,X              ; X from 0 up: right edges of lines 0 on (kept as found)
    INX
    INX
    INX
    INX
    INY
    INY
    INY
    INY
    CPY.w #!BattleFx_WinTableBytes+2
    BCC .t0_w2_rest_zero
    BRA .t0_w2_mirror_left
.t0_w2_rest_x:
    STA.w !BattleFx_WinTable0,Y
    INY
    INY
    INY
    INY
    CPY.w #!BattleFx_WinTableBytes+2
    BCC .t0_w2_rest_x
.t0_w2_mirror_left:
    TDC
    TAY
    LDX.w #!BattleCE_LastLineOfs
.t0_w2_mirror_left_loop:
    LDA.w !BattleFx_WinTable0+2,X
    EOR.b #!BattleCE_MirrorX
    STA.w !BattleFx_WinTable0+2,Y
    DEX
    DEX
    DEX
    DEX
    INY
    INY
    INY
    INY
    CPY.w #!BattleCE_HalfTableBytes
    BNE .t0_w2_mirror_left_loop
    RTS
.t0_w2_mirror_right:
    TDC
    TAX
    LDY.w #!BattleCE_LastLineOfs
.t0_w2_mirror_right_loop:
    LDA.w !BattleFx_WinTable0+3,X
    EOR.b #!BattleCE_MirrorX
    STA.w !BattleFx_WinTable0+3,Y
    INX
    INX
    INX
    INX
    DEY
    DEY
    DEY
    DEY
    CPX.w #!BattleCE_HalfTableBytes
    BNE .t0_w2_mirror_right_loop
    RTS
.table1:
    LDA.w !BattleCE_LineAngle
    BPL .t1_walk
    LDY.b !BattleCE_EdgeOfs
    CPY.b !BattleCE_EdgeStart
    BEQ .t1_walk
    LDA.b !BattleCE_LineX
    BEQ .t1_top_empty
    CMP.b #!BattleCE_EdgeMax
    BNE .t1_top_x
    REP #$20
    LDA.w #!BattleCE_LastLineOfs
    CLC
    ADC.b !BattleCE_EdgeOfs
    TAX
    TDC
    SEP #$20
    LDA.b #!BattleCE_EdgeMax
.t1_top_max:
    STA.w !BattleFx_WinTable1,Y
    STA.w !BattleFx_WinTable1-1,X                ; the left edge, from line 223 up
    DEX
    DEX
    DEX
    DEX
    INY
    INY
    INY
    INY
    CPY.b !BattleCE_EdgeStart
    BNE .t1_top_max
    BRA .t1_walk
.t1_top_empty:
    REP #$20
    LDA.w #!BattleFx_WinEmpty
.t1_top_empty_loop:
    STA.w !BattleFx_WinTable1-1,Y                ; the pair (255, 0)
    INY
    INY
    INY
    INY
    CPY.b !BattleCE_EdgeStart
    BNE .t1_top_empty_loop
    TDC
    SEP #$20
    BRA .t1_walk
.t1_top_x:
    STA.w !BattleFx_WinTable1,Y
    INY
    INY
    INY
    INY
    CPY.b !BattleCE_EdgeStart
    BNE .t1_top_x
.t1_walk:
    LDY.b !BattleCE_EdgeStart
    LDA.w !BattleCE_LineAbsDX
    TAX
    STX.b !BattleCE_StepAcc
    STX.b !BattleCE_StepDX
    LDA.w !BattleCE_LineAbsDY
    TAX
    STX.b !BattleCE_StepDY
    STX.b !BattleCE_StepRows
    BNE .t1_walk_start
    BRA .t1_tail
.t1_walk_start:
    LDA.b !BattleCE_LineX
    TAX
    LDA.w !BattleCE_LineDirX
    BMI .t1_walk_left
.t1_walk_right:
    LDA.b !BattleCE_StepAcc
.t1_step_right:
    CMP.b !BattleCE_StepDY
    BCC .t1_store_right
    SBC.b !BattleCE_StepDY
    INX
    BRA .t1_step_right
.t1_store_right:
    ADC.b !BattleCE_StepDX               ; C = 0 here
    STA.b !BattleCE_StepAcc
    TXA
    STA.w !BattleFx_WinTable1,Y
    INY
    INY
    INY
    INY
    DEC.b !BattleCE_StepRows
    BNE .t1_walk_right
    BRA .t1_tail
.t1_walk_left:
    LDA.b !BattleCE_StepAcc
.t1_step_left:
    CMP.b !BattleCE_StepDY
    BCC .t1_store_left
    SBC.b !BattleCE_StepDY
    DEX
    BRA .t1_step_left
.t1_store_left:
    ADC.b !BattleCE_StepDX
    STA.b !BattleCE_StepAcc
    TXA
    STA.w !BattleFx_WinTable1,Y
    INY
    INY
    INY
    INY
    DEC.b !BattleCE_StepRows
    BNE .t1_walk_left
.t1_tail:
    PLA
    AND.b #$02
    BEQ .t1_window1
    JMP .t1_window2
.t1_window1:
    LDA.w !BattleCE_LineAngle
    BMI .t1_w1_mirror_right
    BNE .t1_w1_rest
    TDC                                 ; angle 0: the lower half emptied
    TAY
    REP #$20
    LDA.w #!BattleFx_WinEmpty
.t1_w1_empty_lower:
    STA.w !BattleFx_WinTable1+!BattleCE_HalfTableBytes+0,Y
    INY
    INY
    INY
    INY
    CPY.w #!BattleCE_HalfTableBytes
    BNE .t1_w1_empty_lower
    TDC
    SEP #$20
    RTS
.t1_w1_rest:
    CPY.w #!BattleFx_WinTableBytes
    BEQ .t1_w1_mirror_left
    TXA
    CMP.b #!BattleCE_EdgeMax
    BNE .t1_w1_rest_not_max
    REP #$20
    LDA.w #!BattleFx_WinEmpty
.t1_w1_rest_empty:
    STA.w !BattleFx_WinTable1,Y
    INY
    INY
    INY
    INY
    CPY.w #!BattleFx_WinTableBytes
    BCC .t1_w1_rest_empty
    TDC
    SEP #$20
    BRA .t1_w1_mirror_left
.t1_w1_rest_not_max:
    CMP.b #0
    BNE .t1_w1_rest_x
.t1_w1_rest_zero:
    STA.w !BattleFx_WinTable1,Y
    STZ.w !BattleFx_WinTable1+1,X              ; X from 0 up: right edges of lines 0 on (kept as found)
    INX
    INX
    INX
    INX
    INY
    INY
    INY
    INY
    CPY.w #!BattleFx_WinTableBytes
    BCC .t1_w1_rest_zero
    BRA .t1_w1_mirror_left
.t1_w1_rest_x:
    STA.w !BattleFx_WinTable1,Y
    INY
    INY
    INY
    INY
    CPY.w #!BattleFx_WinTableBytes
    BCC .t1_w1_rest_x
.t1_w1_mirror_left:
    TDC
    TAY
    LDX.w #!BattleCE_LastLineOfs
.t1_w1_mirror_left_loop:
    LDA.w !BattleFx_WinTable1+0,X
    EOR.b #!BattleCE_MirrorX
    STA.w !BattleFx_WinTable1+0,Y
    DEX
    DEX
    DEX
    DEX
    INY
    INY
    INY
    INY
    CPY.w #!BattleCE_HalfTableBytes
    BNE .t1_w1_mirror_left_loop
    RTS
.t1_w1_mirror_right:
    TDC
    TAX
    LDY.w #!BattleCE_LastLineOfs
.t1_w1_mirror_right_loop:
    LDA.w !BattleFx_WinTable1+1,X
    EOR.b #!BattleCE_MirrorX
    STA.w !BattleFx_WinTable1+1,Y
    INX
    INX
    INX
    INX
    DEY
    DEY
    DEY
    DEY
    CPX.w #!BattleCE_HalfTableBytes
    BNE .t1_w1_mirror_right_loop
    RTS
.t1_window2:
    LDA.w !BattleCE_LineAngle
    BMI .t1_w2_mirror_right
    BNE .t1_w2_rest
    TDC                                 ; angle 0: the lower half emptied
    TAY
    REP #$20
    LDA.w #!BattleFx_WinEmpty
.t1_w2_empty_lower:
    STA.w !BattleFx_WinTable1+!BattleCE_HalfTableBytes+2,Y
    INY
    INY
    INY
    INY
    CPY.w #!BattleCE_HalfTableBytes
    BNE .t1_w2_empty_lower
    TDC
    SEP #$20
    RTS
.t1_w2_rest:
    CPY.w #!BattleFx_WinTableBytes+2
    BEQ .t1_w2_mirror_left
    TXA
    CMP.b #!BattleCE_EdgeMax
    BNE .t1_w2_rest_not_max
    REP #$20
    LDA.w #!BattleFx_WinEmpty
.t1_w2_rest_empty:
    STA.w !BattleFx_WinTable1,Y
    INY
    INY
    INY
    INY
    CPY.w #!BattleFx_WinTableBytes+2
    BCC .t1_w2_rest_empty
    TDC
    SEP #$20
    BRA .t1_w2_mirror_left
.t1_w2_rest_not_max:
    CMP.b #0
    BNE .t1_w2_rest_x
.t1_w2_rest_zero:
    STA.w !BattleFx_WinTable1,Y
    STZ.w !BattleFx_WinTable1+3,X              ; X from 0 up: right edges of lines 0 on (kept as found)
    INX
    INX
    INX
    INX
    INY
    INY
    INY
    INY
    CPY.w #!BattleFx_WinTableBytes+2
    BCC .t1_w2_rest_zero
    BRA .t1_w2_mirror_left
.t1_w2_rest_x:
    STA.w !BattleFx_WinTable1,Y
    INY
    INY
    INY
    INY
    CPY.w #!BattleFx_WinTableBytes+2
    BCC .t1_w2_rest_x
.t1_w2_mirror_left:
    TDC
    TAY
    LDX.w #!BattleCE_LastLineOfs
.t1_w2_mirror_left_loop:
    LDA.w !BattleFx_WinTable1+2,X
    EOR.b #!BattleCE_MirrorX
    STA.w !BattleFx_WinTable1+2,Y
    DEX
    DEX
    DEX
    DEX
    INY
    INY
    INY
    INY
    CPY.w #!BattleCE_HalfTableBytes
    BNE .t1_w2_mirror_left_loop
    RTS
.t1_w2_mirror_right:
    TDC
    TAX
    LDY.w #!BattleCE_LastLineOfs
.t1_w2_mirror_right_loop:
    LDA.w !BattleFx_WinTable1+3,X
    EOR.b #!BattleCE_MirrorX
    STA.w !BattleFx_WinTable1+3,Y
    INX
    INX
    INX
    INX
    DEY
    DEY
    DEY
    DEY
    CPX.w #!BattleCE_HalfTableBytes
    BNE .t1_w2_mirror_right_loop
    RTS

; ============================================================
; HDMA sets and the sprites ($CE:EE6E–$CE:EF10, $CE:F066–$CE:F0E5)
; ============================================================

; $CE:EE6E — BattleCE_UnkEE6E (163 bytes, $EE6E–$EF10)
; Loads HDMA set A (the name is the stub's: matched bank-$CD and bank-$D1
; code calls it so): the first !BattleCE_HdmaHeadBytes (30) bytes, ten
; entries, of each of the nine indirect HDMA tables at
; !Battle_HdmaTables (!BattleCD_HdmaTableBytes apart; channels 0-6,
; then two for channel 7, as BattleCD_NmiSetup uses them), each from
; the bank-$CE address in word n of the set's record
; (!BattleRom_HdmaSetRecs + the set's !BattleRom_HdmaSetOfs entry).
; With !Battle_Unk2A21 bit 0 table 2 (channel 2, BG2HOFS) comes from the
; record's tenth word instead of its third (in the sets looked at, those
; tables point their lines at !BattleCE_Bg2WaveLines). The copies are
; nine MVNs of 30 bytes; the shorter tables in ROM carry the bytes after
; them along.
; Callers (3 JSL sites): BattleCD_StepWipe ($CD:05DA), BattleFx_Init ($D1:F3F6) and
;   BattleFx_ReloadCeSet ($D1:FE69).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E (!Battle_Unk2A21 .w, read
;        before the MVNs); A = the set; B = 0 (the 16-bit TAX after the
;        8-bit ASL; BattleFx_Init and BattleFx_Irq's path through
;        BattleFx_ReloadCeSet set it with TDC, and BattleCD_NmiMain's
;        TDC comes before BattleCD_StepWipe's call, its callees assumed
;        to keep it)
; Exit:  M=1, X=0, DB unchanged (PHB/PLB around the MVNs); A = 0; X = the
;        end of the ninth source; Y = !Battle_HdmaTables + 8 tables +
;        30 ($C9ED)
BattleCE_UnkEE6E:
    PHB
    ASL A
    TAX
    REP #$20
    LDA.l !BattleRom_HdmaSetOfs,X
    TAX
    LDA.l !BattleRom_HdmaSetRecs+(2*8),X ; the sources of tables 8 down to 1, on the stack
    PHA
    LDA.l !BattleRom_HdmaSetRecs+(2*7),X
    PHA
    LDA.l !BattleRom_HdmaSetRecs+(2*6),X
    PHA
    LDA.l !BattleRom_HdmaSetRecs+(2*5),X
    PHA
    LDA.l !BattleRom_HdmaSetRecs+(2*4),X
    PHA
    LDA.l !BattleRom_HdmaSetRecs+(2*3),X
    PHA
    LDA.w !Battle_Unk2A21
    AND.w #!Battle_2A21Bit0
    BEQ .table2_plain
    LDA.l !BattleRom_HdmaSetRecs+(2*9),X
    BRA .table2
.table2_plain:
    LDA.l !BattleRom_HdmaSetRecs+(2*2),X
.table2:
    PHA
    LDA.l !BattleRom_HdmaSetRecs+(2*1),X
    PHA
    LDA.l !BattleRom_HdmaSetRecs+(2*0),X
    TAX
    LDY.w #!Battle_HdmaTables+(!BattleCD_HdmaTableBytes*0)
    LDA.w #!BattleCE_HdmaHeadBytes-1
    MVN !Battle_WramBank,!BattleCE_RomBank ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDY.w #!Battle_HdmaTables+(!BattleCD_HdmaTableBytes*1)
    LDA.w #!BattleCE_HdmaHeadBytes-1
    PLX
    MVN !Battle_WramBank,!BattleCE_RomBank ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDY.w #!Battle_HdmaTables+(!BattleCD_HdmaTableBytes*2)
    LDA.w #!BattleCE_HdmaHeadBytes-1
    PLX
    MVN !Battle_WramBank,!BattleCE_RomBank ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDY.w #!Battle_HdmaTables+(!BattleCD_HdmaTableBytes*3)
    LDA.w #!BattleCE_HdmaHeadBytes-1
    PLX
    MVN !Battle_WramBank,!BattleCE_RomBank ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDY.w #!Battle_HdmaTables+(!BattleCD_HdmaTableBytes*4)
    LDA.w #!BattleCE_HdmaHeadBytes-1
    PLX
    MVN !Battle_WramBank,!BattleCE_RomBank ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDY.w #!Battle_HdmaTables+(!BattleCD_HdmaTableBytes*5)
    LDA.w #!BattleCE_HdmaHeadBytes-1
    PLX
    MVN !Battle_WramBank,!BattleCE_RomBank ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDY.w #!Battle_HdmaTables+(!BattleCD_HdmaTableBytes*6)
    LDA.w #!BattleCE_HdmaHeadBytes-1
    PLX
    MVN !Battle_WramBank,!BattleCE_RomBank ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDY.w #!Battle_HdmaTables+(!BattleCD_HdmaTableBytes*7)
    LDA.w #!BattleCE_HdmaHeadBytes-1
    PLX
    MVN !Battle_WramBank,!BattleCE_RomBank ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    LDY.w #!Battle_HdmaTables+(!BattleCD_HdmaTableBytes*8)
    LDA.w #!BattleCE_HdmaHeadBytes-1
    PLX
    MVN !Battle_WramBank,!BattleCE_RomBank ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    TDC
    SEP #$20
    PLB
    RTL

; $CE:EF11-$CE:F065 is data read by bank $CD (!BattleRom_MsgStrings and the
; layer-effect and dissolve tables after it), left as ROM bytes.

org $CEF066

; $CE:F066 — BattleCE_UnkF066 (128 bytes, $F066–$F0E5)
; Parks sprites 4-127 (the name is the stub's: matched bank-$CD code
; calls it so): their y in BattleOam = !BattleOam_OffscreenY, and the
; high-table bytes 1-31 (!BattleOam_HighTable+1 on) =
; !BattleCE_OamHighAllLarge (every sprite large, x bit 8 clear).
; Sprites 0-3 (the cursors) and high-table byte 0 are not touched. The
; first loop runs X (8-bit) from !BattleCE_OamBlockBytes down to 4 over
; 31 bases (sprite 4k + 3's y, + X: sprites 4k+4 to 4k+7; k = 0-30).
; Callers (1 JSL site): BattleCD_NmiMain ($CD:0993).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E (the OAM buffer .w; any
;        bank that maps low WRAM would do); BattleCD_NmiMain calls it
;        so, unless !Battle_UnkCD2D or !Battle_UnkA028 is set
; Exit:  M=1, X=0; A = 0; X = 0; Y's low byte kept, high byte cleared
;        (SEP #$10); DB unchanged
BattleCE_UnkF066:
    SEP #$10
    LDX.b #!BattleCE_OamBlockBytes
    LDA.b #!BattleOam_OffscreenY
.park:
    STA.w BattleOam[3].Y,X
    STA.w BattleOam[7].Y,X
    STA.w BattleOam[11].Y,X
    STA.w BattleOam[15].Y,X
    STA.w BattleOam[19].Y,X
    STA.w BattleOam[23].Y,X
    STA.w BattleOam[27].Y,X
    STA.w BattleOam[31].Y,X
    STA.w BattleOam[35].Y,X
    STA.w BattleOam[39].Y,X
    STA.w BattleOam[43].Y,X
    STA.w BattleOam[47].Y,X
    STA.w BattleOam[51].Y,X
    STA.w BattleOam[55].Y,X
    STA.w BattleOam[59].Y,X
    STA.w BattleOam[63].Y,X
    STA.w BattleOam[67].Y,X
    STA.w BattleOam[71].Y,X
    STA.w BattleOam[75].Y,X
    STA.w BattleOam[79].Y,X
    STA.w BattleOam[83].Y,X
    STA.w BattleOam[87].Y,X
    STA.w BattleOam[91].Y,X
    STA.w BattleOam[95].Y,X
    STA.w BattleOam[99].Y,X
    STA.w BattleOam[103].Y,X
    STA.w BattleOam[107].Y,X
    STA.w BattleOam[111].Y,X
    STA.w BattleOam[115].Y,X
    STA.w BattleOam[119].Y,X
    STA.w BattleOam[123].Y,X
    DEX
    DEX
    DEX
    DEX
    BNE .park
    REP #$20
    LDX.b #!BattleCE_OamHighBytes-2
    LDA.w #!BattleCE_OamHighAllLarge
.high:
    STA.w !BattleOam_HighTable,X
    DEX
    DEX
    BNE .high
    STA.w !BattleOam_HighTable+1          ; bytes 1-2 (byte 2 again)
    TDC
    SEP #$20
    REP #$10
    RTL
