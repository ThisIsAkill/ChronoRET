; ============================================================
; Bank $FD — Main hardware initialization + engine jump
;
; The entry point of this bank is MainInit ($FD:C000), jumped to
; from the reset routine in bank $00 (JML $FDC000 at $00:FF03).
;
; MainInit puts the CPU and PPU into a known state in five steps:
;   1.  CPU mode, stack, data bank, DP=$4200   ($FD:C000–$C013)
;   2.  CPU I/O registers through DP=$4200     ($FD:C014–$C035)
;   3.  DP=$2100, screen into forced blank     ($FD:C036–$C041)
;   4.  PPU registers through DP=$2100         ($FD:C042–$C0D2)
;   5.  Long jump into the engine at $C0:000E  ($FD:C0D3–$C0D6)
;
; Total: 215 bytes ($FD:C000–$C0D6 inclusive).
;
; Also matched: the battle helpers BattleFD_* ($FD:A982 on) that bank
; $C1 calls with JSL, RandomTableFD ($FD:BA61), a copy of bank $C0's
; RandomTable read by the battle engine, and Ppu_SetBgLayout right after
; MainInit ($FD:C0D7).
; ============================================================

arch snes.cpu
hirom

incsrc "../hardware.inc"

; ============================================================
; Battle helpers, part 1 ($FD:A982–$FD:AF7F)
; Long routines the battle engine in bank $C1 calls (JSL) for its setup,
; its turns and its ends. All of them run with the battle's state: M=1,
; X=0, DP=0, DB=$7E, and use the same direct-page scratch and math cells
; as bank $C1 (!BattleTmp_xx, !Battle_MathA..MathRem). The multiplies
; and random numbers go through the bank-$C1 long veneers
; Battle_Mul16Long and Battle_RandRangeLong.
; ============================================================

; $FD:A982 — BattleFD_UnkA982 (14 bytes, $A982–$A98F)
; Zeroes $7E:AD89-$B3F4: the battle's working variables from
; !Battle_UnkAD89 to !Battle_UnkB3F4 (the turn lists, the action
; block, the reward sums and most of the other !Battle_Unk* bytes this
; file and bank $C1 use). BattleSys_Main calls it first.
; Callers (1 JSL site): BattleSys_Main ($C1:8006).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E (.w stores through DB)
; Exit:  M=1, X=0; A = 0 (B too: TDC); X = !Battle_UnkB3F4+1; Y unchanged
org $FDA982
BattleFD_UnkA982:
    TDC
    LDX.w #!Battle_UnkAD89
.clear:
    STA.w !Battle_WramAbs,X
    INX
    CPX.w #!Battle_UnkB3F4+1
    BCC .clear
    RTL

; $FD:A990 — BattleFD_RestoreEnemies (264 bytes, $A990–$AA97)
; Probably a script command that brings removed enemies back: the
; caller ($C1:A3B6, unmatched) leaves the script read address in
; !Battle_UnkB1D2 (bank $CC) and the record id in !BattleTmp_12.
;   - Script bytes +3..+10 are four (offset, value) pairs: each value is
;     written to the stat block of slot !Battle_UnkB18B (the address in
;     !BattleRom_PcStatBlock, BattlerStats + $2D) plus the offset.
;   - Each enemy entry 0-7 that has an id in !Battler_UnkAF0A but is
;     empty in !Battler_UnkAEFF, with !Battle_UnkAF15 bit 7 clear, is put
;     back: its slot (entry + 3) is appended to !Battle_UnkAECC, the id
;     copied back to !Battler_UnkAEFF, !Battle_UnkB158 copied to
;     !Battler_UnkAFAB, !Battle_UnkB26B set to $FF, !Battle_UnkAE6D to the
;     entry, !Battle_UnkAE85 zeroed, and BattleFD_UnkB438 rebuilds its
;     stats (full HP). Then its HP is set by DP $0E, which still holds the
;     fourth pair's offset byte (script +9): 1 = half its max HP, 2 = a
;     quarter, 3 = 1, anything else leaves the full HP.
;   - !Battle_UnkAECB = the number of entries put back; the action block
;     is set to caster !Battle_UnkB18B, kind 2, record !BattleTmp_12,
;     flags 0.
; "Removed enemies" rests on the two id arrays: BattleSys_Main's victory
; test treats an empty !Battler_UnkAEFF entry as gone, and this copies
; the id back from !Battler_UnkAF0A.
; Quirk: the HP choice reuses DP $0E, the offset of the fourth pair, so
; the same script byte both picks a stat-block byte and the HP.
; Callers (1 JSL site): unmatched ($C1:A3B6).
; Entry: M=1, X=0, DP=0, DB=$7E; !Battle_UnkB1D2 = script address in bank
;        $CC, !Battle_UnkB18B = the slot whose stat block is written,
;        !BattleTmp_12 = record id for !Battle_ActId
; Exit:  M=1, X=0; A, X, Y, DP $00-$04, $0C, $0E and $10 clobbered (with
;        what BattleFD_UnkB438 changes); the action block set as above
; Callee: BattleFD_UnkB438
!BattleFDRestore_Ofs   = !BattleTmp_0E  ; 2 B: stat-block offset of the pair being written; then the HP mode
!BattleFDRestore_Count = !BattleTmp_0C  ; 1 B: entries put back so far (index into !Battle_UnkAECC)
!BattleFDRestore_Enemy = !BattleTmp_10  ; 1-2 B: enemy entry 0-7
!BattleFDRestore_ActId = !BattleTmp_12  ; 1 B: record id the caller leaves for !Battle_ActId
org $FDA990
BattleFD_RestoreEnemies:
    TDC
    LDA.w !Battle_UnkB18B
    ASL A
    TAX
    REP #$20
    LDA.l !BattleRom_PcStatBlock,X
    TAY                                 ; Y = the slot's stat block
    TDC
    SEP #$20
    LDX.w !Battle_UnkB1D2
    LDA.l !BattleRom_ScriptBank+3,X
    TAX
    STX.b !BattleFDRestore_Ofs
    LDX.w !Battle_UnkB1D2
    LDA.l !BattleRom_ScriptBank+4,X
    STA.b (!BattleFDRestore_Ofs),Y
    LDX.w !Battle_UnkB1D2
    LDA.l !BattleRom_ScriptBank+5,X
    TAX
    STX.b !BattleFDRestore_Ofs
    LDX.w !Battle_UnkB1D2
    LDA.l !BattleRom_ScriptBank+6,X
    STA.b (!BattleFDRestore_Ofs),Y
    LDX.w !Battle_UnkB1D2
    LDA.l !BattleRom_ScriptBank+7,X
    TAX
    STX.b !BattleFDRestore_Ofs
    LDX.w !Battle_UnkB1D2
    LDA.l !BattleRom_ScriptBank+8,X
    STA.b (!BattleFDRestore_Ofs),Y
    LDX.w !Battle_UnkB1D2
    LDA.l !BattleRom_ScriptBank+9,X
    TAX
    STX.b !BattleFDRestore_Ofs          ; kept: the HP mode below
    LDX.w !Battle_UnkB1D2
    LDA.l !BattleRom_ScriptBank+10,X
    STA.b (!BattleFDRestore_Ofs),Y
    TDC
    TAX
    STX.b !BattleFDRestore_Enemy
    STX.b !BattleFDRestore_Count
.enemy:
    LDX.b !BattleFDRestore_Enemy
    LDA.w !Battler_UnkAF0A+!Battle_FirstEnemySlot,X
    CMP.b #!Battle_EntryNone
    BEQ .next
    LDA.w !Battler_UnkAEFF+!Battle_FirstEnemySlot,X
    CMP.b #!Battle_EntryNone
    BNE .next
    LDA.w !Battle_UnkAF15,X
    BIT.b #!Battle_AF15Bit7
    BNE .next
    LDY.b !BattleFDRestore_Count
    TXA
    CLC
    ADC.b #!Battle_FirstEnemySlot
    STA.w !Battle_UnkAECC,Y
    INC.b !BattleFDRestore_Count
    LDA.w !Battler_UnkAF0A+!Battle_FirstEnemySlot,X
    STA.w !Battler_UnkAEFF+!Battle_FirstEnemySlot,X
    LDA.w !Battle_UnkB158+!Battle_FirstEnemySlot,X
    STA.w !Battler_UnkAFAB+!Battle_FirstEnemySlot,X
    LDA.b #!Battle_EntryNone
    STA.w !Battle_UnkB26B,X
    TXA
    STA.w !Battle_UnkAE6D,X
    STZ.w !Battle_UnkAE85,X
    STX.b !BattleTmp_02                 ; BattleFD_UnkB438's enemy entry
    JSL BattleFD_UnkB438
    REP #$20
    LDA.b !BattleFDRestore_Enemy
    XBA
    LSR A
    TAX                                 ; X = entry * $80
    TDC
    SEP #$20
    LDA.b !BattleFDRestore_Ofs
    CMP.b #!Battle_RestoreHpHalf
    BNE .not_half
    REP #$20
    LDA.w BattlerStats[3].MaxHp,X
    LSR A
    STA.w BattlerStats[3].CurHp,X
    TDC
    SEP #$20
    BRA .next
.not_half:
    CMP.b #!Battle_RestoreHpQuarter
    BNE .not_quarter
    REP #$20
    LDA.w BattlerStats[3].MaxHp,X
    LSR A
    LSR A
    STA.w BattlerStats[3].CurHp,X
    TDC
    SEP #$20
    BRA .next
.not_quarter:
    CMP.b #!Battle_RestoreHpOne
    BNE .next
    REP #$20
    LDA.w #1
    STA.w BattlerStats[3].CurHp,X
    TDC
    SEP #$20
    BRA .next
.next:
    INC.b !BattleFDRestore_Enemy
    LDA.b !BattleFDRestore_Enemy
    CMP.b #!Battle_NumEnemies
    BCS .done
    JMP .enemy
.done:
    LDA.b !BattleFDRestore_Count
    STA.w !Battle_UnkAECB
    LDA.w !Battle_UnkB18B
    STA.w !Battle_ActCaster
    LDA.b #!Battle_RestoreActKind
    STA.w !Battle_ActKind
    LDA.b !BattleFDRestore_ActId
    STA.w !Battle_ActId
    STZ.w !Battle_ActFlags
    RTL

; $FD:AA98 — BattleFD_UnkAA98 (24 bytes, $AA98–$AAAF)
; Sets BattlerStats.Status of all 8 enemy slots (3-10) to
; !Battle_StatusKo ($80, the other status bits cleared). BattleSys_Main
; runs it on its !Battle_Unk99CD end.
; Callers (1 JSL site): BattleSys_Main ($C1:81FD).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A = 0 (B too); X = $400; Y unchanged
org $FDAA98
BattleFD_UnkAA98:
    TDC
    TAX
.enemy:
    LDA.b #!Battle_StatusKo
    STA.w BattlerStats[3].Status,X
    REP #$20
    TXA
    CLC
    ADC.w #!Battle_StatsStride
    TAX
    TDC
    SEP #$20
    CPX.w #!Battle_NumEnemies*!Battle_StatsStride
    BCC .enemy
    RTL

; $FD:AAB0 — BattleFD_UnkAAB0 (34 bytes, $AAB0–$AAD1)
; Builds !Battle_Unk7F01EE: bit n set for each enemy entry n (0-7) whose
; !Battle_UnkAE85 byte is non-zero. BattleSys_Main's last call before it
; leaves the battle, so probably a result handed to the field (not traced).
; Callers (1 JSL site): BattleSys_Main ($C1:845A).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0; A = !Battle_Unk7F01EE or 0 (the last byte read); X = 8;
;        Y unchanged; DP $00 = 0 (the bit shifted out)
!BattleFDBits_Bit = !BattleTmp_00       ; 1 B: the bit of the entry tested
org $FDAAB0
BattleFD_UnkAAB0:
    TDC
    STA.l !Battle_Unk7F01EE
    TAX
    LDA.b #1
    STA.b !BattleFDBits_Bit
.enemy:
    LDA.w !Battle_UnkAE85,X
    BEQ .next
    LDA.l !Battle_Unk7F01EE
    ORA.b !BattleFDBits_Bit
    STA.l !Battle_Unk7F01EE
.next:
    ASL.b !BattleFDBits_Bit
    INX
    CPX.w #!Battle_NumEnemies
    BCC .enemy
    RTL

; $FD:AAD2 — BattleFD_LoadUnkB18E (47 bytes, $AAD2–$AB00)
; Fills the 4 bytes !Battle_UnkB18E-B191 from the 11-byte record
; !Battle_UnkB18C of !BattleRom_UnkCC6FCB: B18E = record byte 0, B18F =
; the record number, B190 = record byte 1, B191 = 0; !Battle_UnkB2C3 =
; the record's offset. BattleFD_LoadUnkB18E2 is the same for the table at
; !BattleRom_UnkCC88CB. What the records hold is not traced
; (BattleAi_SetCmdBits, $C1:AC89, ORs a slot + 3 into B18E).
; Callers (3 JSL sites): BattleAi_RunTech ($C1:9B1C) and unmatched ($C1:A128, $C1:A370).
; Entry: M=1, X=0, DP=0, DB=$7E; B (A's high byte) = 0, presumably: both
;        TAX copy it into the Mul16 factors (not traced at the callers)
; Exit:  M=1, X=0; A = record byte 1; X = record offset; Y unchanged;
;        !Battle_MathA/B/Lo/Hi as Battle_Mul16 leaves them
; Callee: Battle_Mul16Long
org $FDAAD2
BattleFD_LoadUnkB18E:
    LDA.w !Battle_UnkB18C
    TAX
    STX.b !Battle_MathA
    LDA.b #!BattleRom_UnkB18ERecSize
    TAX
    STX.b !Battle_MathB
    JSL Battle_Mul16Long
    LDX.b !Battle_MathLo
    STX.w !Battle_UnkB2C3
    LDX.w !Battle_UnkB2C3
    LDA.l !BattleRom_UnkCC6FCB,X
    STA.w !Battle_UnkB18E
    LDA.w !Battle_UnkB18C
    STA.w !Battle_UnkB18F
    LDA.l !BattleRom_UnkCC6FCB+1,X
    STA.w !Battle_UnkB190
    STZ.w !Battle_UnkB191
    RTL

; $FD:AB01 — BattleFD_LoadUnkB18E2 (47 bytes, $AB01–$AB2F)
; BattleFD_LoadUnkB18E with the records of !BattleRom_UnkCC88CB.
; Callers (1 JSL site): BattleAi_RunAttack ($C1:9A25).
; Entry: M=1, X=0, DP=0, DB=$7E; B = 0, presumably (as BattleFD_LoadUnkB18E)
; Exit:  M=1, X=0; A = record byte 1; X = record offset; Y unchanged;
;        !Battle_MathA/B/Lo/Hi as Battle_Mul16 leaves them
; Callee: Battle_Mul16Long
org $FDAB01
BattleFD_LoadUnkB18E2:
    LDA.w !Battle_UnkB18C
    TAX
    STX.b !Battle_MathA
    LDA.b #!BattleRom_UnkB18ERecSize
    TAX
    STX.b !Battle_MathB
    JSL Battle_Mul16Long
    LDX.b !Battle_MathLo
    STX.w !Battle_UnkB2C3
    LDX.w !Battle_UnkB2C3
    LDA.l !BattleRom_UnkCC88CB,X
    STA.w !Battle_UnkB18E
    LDA.w !Battle_UnkB18C
    STA.w !Battle_UnkB18F
    LDA.l !BattleRom_UnkCC88CB+1,X
    STA.w !Battle_UnkB190
    STZ.w !Battle_UnkB191
    RTL

; $FD:AB30 — BattleFD_UnkAB30 (114 bytes, $AB30–$ABA1)
; Run by BattleSys_Unk8461 for a PC whose turn is due, before the menu:
; decides whether the PC acts on its own.
;   - BattlerStats.Unk4C+2 or .Unk4C+7 bit 7 set: for a PC slot (Y < 3)
;     a random slot 3-10 is drawn until one with an id in
;     !Battler_UnkAEFF comes up; it becomes the target (!Battle_UnkAD8E),
;     !Battle_UnkB3C9 = $80, !Battle_UnkB18B = the PC, and
;     BattleSys_RunPcAttack runs (through BattleSys_RunPcAttackLong). Then (also
;     for Y >= 3) !Battle_UnkAF23 = 1.
;   - else Status2 bit 2 set: the same with a random slot 0-10 other than
;     the PC itself, so allies too.
;   - else nothing: !Battle_UnkAF23 stays 0 and the PC gets the menu.
; So probably two statuses that make a PC attack by itself (an enemy at
; random, or anyone at random); the statuses are not named in the code.
; Quirk: the draws loop until a slot qualifies, so with no enemy entry
; left (or no other battler) they would never end.
; Callers (1 JSL site): BattleSys_Unk8461 ($C1:8526).
; Entry: M=1, X=0, DP=0, DB=$7E; X = slot * $80, Y = slot
; Exit:  M=1, X=0; !Battle_UnkAF23 = 1 if the PC acted on its own, else 0;
;        !Battle_UnkAE4C = 0; A, X clobbered; Y unchanged when no attack
;        runs, else as BattleSys_RunPcAttack's callees leave it; DP $12 =
;        the slot on the Status2 path; what BattleSys_RunPcAttack changes
; Callees: Battle_RandRangeLong, BattleSys_RunPcAttackLong
!BattleFDAuto_Slot = !BattleTmp_12      ; 2 B: the PC's slot (the Status2 path)
org $FDAB30
BattleFD_UnkAB30:
    STZ.w !Battle_UnkAE4C
    STZ.w !Battle_UnkAF23
    LDA.w BattlerStats.Unk4C+2,X
    ORA.w BattlerStats.Unk4C+7,X
    BIT.b #!Battle_AutoEnemyBit
    BNE .at_enemy
    LDA.w BattlerStats.Status2,X
    BIT.b #!Battle_AutoAnyBit
    BNE .at_anyone
    BRA .done
.at_enemy:
    CPY.w #!Battle_NumPcSlots
    BCC .draw_enemy
    BRA .acted
.draw_enemy:
    LDX.w #!Battle_FirstEnemySlot
    LDA.b #!Battle_NumSlots
    JSL Battle_RandRangeLong
    TAX
    LDA.w !Battler_UnkAEFF,X
    CMP.b #!Battle_EntryNone
    BEQ .draw_enemy
    TXA
    STA.w !Battle_UnkAD8E
    LDA.b #!Battle_UnkB3C9Auto
    STA.w !Battle_UnkB3C9
    TYA
    STA.w !Battle_UnkB18B
    JSL BattleSys_RunPcAttackLong
.acted:
    INC.w !Battle_UnkAF23
    BRA .done
.at_anyone:
    STY.b !BattleFDAuto_Slot
.draw_any:
    TDC
    TAX
    LDA.b #!Battle_NumSlots
    JSL Battle_RandRangeLong
    TAX
    CPX.b !BattleFDAuto_Slot
    BEQ .draw_any
    LDA.w !Battler_UnkAEFF,X
    CMP.b #!Battle_EntryNone
    BEQ .draw_any
    TXA
    STA.w !Battle_UnkAD8E
    LDA.b #!Battle_UnkB3C9Auto
    STA.w !Battle_UnkB3C9
    TYA
    STA.w !Battle_UnkB18B
    JSL BattleSys_RunPcAttackLong
    INC.w !Battle_UnkAF23
.done:
    RTL

; $FD:ABA2 — BattleFD_AddEnemyRewards (204 bytes, $ABA2–$AC6D)
; Adds the rewards of the enemy in slot DP $0E to the battle's sums,
; unless its !Battle_UnkAF15 bit 6 is set (!Battle_AF15NotCounted) or
; its !Battler_UnkAF0A entry is empty. The enemy's 7-byte record in
; BattleRom_EnemyReward (index: the !Battler_UnkAF0A id):
;   - .Unk0 is added to !Battle_UnkB28C (16-bit) and .Gold to
;     !Battle_RewardGold (16-bit; the victory path pays it);
;   - .Unk6 (8-bit) is added to the 24-bit !Battle_UnkB2DB/B2DD;
;   - .ItemA (0 = none): when it equals .ItemB it is added to the
;     second item list (!Battle_RewardItems+3..+5) unless already there;
;     otherwise, if the enemy's !Battle_UnkAE5D bit 6 is set, with a
;     random number 0-99 below 90 it is added to the first list
;     (!Battle_RewardItems+0..+2) unless already there. Adding an item
;     sets !Battle_UnkB2AF bit 5. A full list (3 items) takes no more.
; The gold and items are proven by what BattleSys_Main pays out; that
; .Unk0 and .Unk6 are the other two rewards shown by BattleFD_UnkAD17
; (messages 0 and 1) is probable, not traced.
; Callers (1 JSL site): Battle_ApplyHits ($C1:ECFE).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $0E (16-bit) = the enemy's slot
; Exit:  M=1, X=0; A, X, Y clobbered; DP $04, $06, $10 written;
;        !Battle_MathA..MathHi as Battle_Mul16 leaves them; on the item
;        draw Battle_RandRange's changes
; Callees: Battle_Mul16Long, Battle_RandRangeLong
!BattleFDReward_Slot  = !BattleTmp_0E   ; 2 B: the enemy's slot (argument)
!BattleFDReward_Enemy = !BattleTmp_04   ; 2 B: slot - 3
!BattleFDReward_Rec   = !BattleTmp_06   ; 2 B: offset of its reward record
!BattleFDReward_Item  = !BattleTmp_10   ; 1 B: the item id
org $FDABA2
BattleFD_AddEnemyRewards:
    TDC
    LDX.b !BattleFDReward_Slot
    LDA.w !Battle_UnkAF15-!Battle_FirstEnemySlot,X
    BIT.b #!Battle_AF15NotCounted
    BEQ .counted
    JMP .done
.counted:
    LDA.w !Battler_UnkAF0A,X
    CMP.b #!Battle_EntryNone
    BNE .has_id
    JMP .done
.has_id:
    TAX
    STX.b !Battle_MathA
    LDX.w #!Battle_EnemyRecUnk5E04Size
    STX.b !Battle_MathB
    JSL Battle_Mul16Long
    LDX.b !Battle_MathLo
    STX.b !BattleFDReward_Rec
    TDC
    LDA.b !BattleFDReward_Slot
    SEC
    SBC.b #!Battle_FirstEnemySlot
    TAX
    STX.b !BattleFDReward_Enemy
    REP #$20
    LDX.b !BattleFDReward_Rec
    LDA.l BattleRom_EnemyReward.Unk0,X
    CLC
    ADC.w !Battle_UnkB28C
    STA.w !Battle_UnkB28C
    LDA.l BattleRom_EnemyReward.Gold,X
    CLC
    ADC.w !Battle_RewardGold
    STA.w !Battle_RewardGold
    TDC
    SEP #$20
    LDA.l BattleRom_EnemyReward.Unk6,X
    REP #$20
    CLC
    ADC.w !Battle_UnkB2DB
    BCC .unk6_no_carry
    SEP #$20
    INC.w !Battle_UnkB2DD
    REP #$20
.unk6_no_carry:
    STA.w !Battle_UnkB2DB
    TDC
    SEP #$20
    LDA.l BattleRom_EnemyReward.ItemA,X
    BEQ .no_item
    STA.b !BattleFDReward_Item
    CMP.l BattleRom_EnemyReward.ItemB,X
    BEQ .second_list
    LDX.b !BattleFDReward_Enemy
    LDA.w !Battle_UnkAE5D,X
    BIT.b #!Battle_AE5DBit6
    BEQ .no_item
    TDC
    TAX
    LDA.b #!Battle_PercentRange
    JSL Battle_RandRangeLong
    CMP.b #!Battle_ItemDrawBelow
    BCS .no_item
    TDC
    TAY
.first_find:
    LDA.w !Battle_RewardItems,Y
    BEQ .first_add
    CMP.b !BattleFDReward_Item
    BEQ .no_item
    INY
    CPY.w #!Battle_RewardListLen
    BCC .first_find
    BRA .no_item
.first_add:
    LDA.b !BattleFDReward_Item
    STA.w !Battle_RewardItems,Y
    LDA.w !Battle_UnkB2AF
    ORA.b #!Battle_RewardBitItem
    STA.w !Battle_UnkB2AF
.no_item:
    BRA .done
.second_list:
    TDC
    TAY
.second_find:
    LDA.w !Battle_RewardItems+!Battle_RewardListLen,Y
    BEQ .second_add
    CMP.b !BattleFDReward_Item
    BEQ .done
    INY
    CPY.w #!Battle_RewardListLen
    BCC .second_find
    BRA .done
.second_add:
    LDA.b !BattleFDReward_Item
    STA.w !Battle_RewardItems+!Battle_RewardListLen,Y
    LDA.w !Battle_UnkB2AF
    ORA.b #!Battle_RewardBitItem
    STA.w !Battle_UnkB2AF
.done:
    RTL

; $FD:AC6E — BattleFD_UnkAC6E (128 bytes, $AC6E–$ACED)
; Run by BattleSys_Unk8461 after a turn when !Battle_UnkB2C0 is 0 (no
; enemy reaction scripts): probably the PCs' counter-attacks. Only when
; !Battle_UnkB3B9 is set ($C1:9B13, unmatched, sets it when the target in
; !Battle_UnkAD8E is a PC slot). For the first three entries of
; !Battle_UnkB3AC (!Battle_UnkB315 = 0-2), each a slot or $FF:
;   - skipped when the slot is KO'd, has any Status2 bit of
;     !Battle_NoReactMask set, has BattlerStats.Unk78 bit 6 clear, or a
;     random number 0-99 is not below its BattlerStats.Unk7B;
;   - else, with BattlerStats.Unk7A bit 7 clear, its !Battler_UnkAFAB
;     is set to 1; with it set, the slot acts at once: !Battle_UnkB18B =
;     the slot, !Battle_UnkAD8E = DP $22 (the slot whose turn it was,
;     left by BattleSys_Unk8461), BattleSys_RunPcAttack (through
;     BattleSys_RunPcAttackLong); if that target is then KO'd the loop stops.
; Then !Battle_UnkB3B9 = 0.
; Callers (1 JSL site): BattleSys_Unk8461 ($C1:8650).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $22 = the slot that just acted
; Exit:  M=1, X=0; !Battle_UnkB3B9 = 0; A, X, Y clobbered; DP $0C
;        written; !Battle_UnkB315 = 3 after a full pass, the entry (0-2)
;        whose action left its target KO'd when the loop stops early, and
;        unchanged when !Battle_UnkB3B9 was 0; Battle_RandRange's and
;        BattleSys_RunPcAttack's changes
; Callees: Battle_RandRangeLong, BattleSys_RunPcAttackLong
!BattleFDCounter_Ofs = !BattleTmp_0C    ; 2 B: slot * $80
org $FDAC6E
BattleFD_UnkAC6E:
    LDA.w !Battle_UnkB3B9
    BEQ .done
    TDC
    STA.w !Battle_UnkB315
.entry:
    TDC
    LDA.w !Battle_UnkB315
    TAX
    LDA.w !Battle_UnkB3AC,X
    CMP.b #!Battle_EntryNone
    BEQ .next
    TAY
    REP #$20
    XBA
    LSR A
    TAX                                 ; X = slot * $80
    STA.b !BattleFDCounter_Ofs
    TDC
    SEP #$20
    LDA.w BattlerStats.Status,X
    BIT.b #!Battle_StatusKo
    BNE .next
    LDA.w BattlerStats.Status2,X
    BIT.b #!Battle_NoReactMask
    BNE .next
    LDA.w BattlerStats.Unk78,X
    BIT.b #!Battle_Unk78CounterBit
    BEQ .next
    TDC
    TAX
    LDA.b #!Battle_PercentRange
    JSL Battle_RandRangeLong
    LDX.b !BattleFDCounter_Ofs
    CMP.w BattlerStats.Unk7B,X
    BCS .next
    LDA.w BattlerStats.Unk7A,X
    BIT.b #!Battle_Unk7AActNowBit
    BNE .act
    LDA.b #1
    STA.w !Battler_UnkAFAB,Y
    BRA .next
.act:
    TYA
    STA.w !Battle_UnkB18B
    LDA.b !BattleTmp_22
    STA.w !Battle_UnkAD8E
    JSL BattleSys_RunPcAttackLong
    TDC
    LDA.w !Battle_UnkAD8E
    REP #$20
    XBA
    LSR A
    TAX                                 ; X = target * $80
    TDC
    SEP #$20
    LDA.w BattlerStats.Status,X
    BIT.b #!Battle_StatusKo
    BNE .done
.next:
    INC.w !Battle_UnkB315
    LDA.w !Battle_UnkB315
    CMP.b #!Battle_NumPcSlots
    BCC .entry
.done:
    STZ.w !Battle_UnkB3B9
    RTL

; $FD:ACEE — BattleFD_UnkACEE (15 bytes, $ACEE–$ACFC)
; Zeroes !Battle_UnkAD9B and the $B0 bytes from !Battle_ActPcHitAmount
; ($AD9C-$AE4B: the first four of the $2C-byte record sets the hit
; opcodes read).
; Callers (9 JSL sites): BattleSys_Unk8461 ($C1:8835), BattleSys_ListHandler1 ($C1:8948),
;   BattleSys_ListHandler9 ($C1:8BB4), BattleAi_EnemyTurn ($C1:8E88), BattleSys_UpdateKo ($C1:B38A),
;   BattleSys_UnkB967 ($C1:BB29, $C1:BC56), BattleSys_RunPcAttack ($C1:C01D) and Battle_SetupBattle
;   ($C1:FBAC).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A = 0 (B too); X = $B0; Y unchanged
org $FDACEE
BattleFD_UnkACEE:
    TDC
    TAX
    STA.w !Battle_UnkAD9B
.clear:
    STA.w !Battle_ActPcHitAmount,X
    INX
    CPX.w #!Battle_HitRecClearBytes
    BCC .clear
    RTL

; $FD:ACFD — BattleFD_UnkACFD (12 bytes, $ACFD–$AD08)
; Zeroes the $84 bytes from !Battle_HitAmount ($B328-$B3AB): the three
; $2C-byte hit sets (!Battle_HitAmount/!Battle_HitFlags per battler slot)
; that Battle_RecordHit fills and Battle_ApplyHits applies, which runs it
; at its end. BattleSys_Main also runs it every pass.
; Callers (6 JSL sites): BattleSys_Main ($C1:812C), BattleSys_RunTechParts ($C1:D523),
;   BattleSys_UnkD7C4 ($C1:D7C4), BattleSys_UnkD8D1 ($C1:D8D1), Battle_ApplyHits ($C1:ED84) and
;   Battle_SetupBattle ($C1:FD12).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A = 0 (B too); X = $84; Y unchanged
org $FDACFD
BattleFD_UnkACFD:
    TDC
    TAX
.clear:
    STA.w !Battle_HitAmount,X
    INX
    CPX.w #!Battle_HitSetsBytes
    BCC .clear
    RTL

; $FD:AD09 — BattleFD_UnkAD09 (14 bytes, $AD09–$AD16)
; Sets the three PCs' Tech_MenuEntry blocks ($1A80-$1C23, 3 x $8C
; bytes) to $FF.
; Callers (1 JSL site): Battle_SetupBattle ($C1:FB59).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A = $FF (B = 0); X = $1A4; Y unchanged
org $FDAD09
BattleFD_UnkAD09:
    TDC
    TAX
    LDA.b #!Battle_TechEntryEmpty
.fill:
    STA.w Tech_MenuEntry.TechId,X
    INX
    CPX.w #!Battle_TechEntryBlocksBytes
    BCC .fill
    RTL

; $FD:AD17 — BattleFD_UnkAD17 (315 bytes, $AD17–$AE51)
; BattleSys_Main's victory path, after the gold: shows the end-of-battle
; messages, each one a JSL BattleSys_UnkVecCD0021 with A = the message
; and its arguments in !Battle_MsgArg0.. ($0200):
;   - 0: !Battle_UnkB2AF bit 7 set and !Battle_UnkB28C non-zero; args =
;     B28C (16-bit), byte 2 = 0;
;   - 1: !Battle_UnkB2AF bit 4 set and !Battle_UnkB2DB non-zero; args =
;     B2DB (16-bit), byte 2 = !Battle_UnkB2DD;
;   - 2: bit 6 (the gold paid) and !Battle_RewardGold non-zero; args =
;     the gold, byte 2 = 0;
;   - 3: bit 5 (an item): once per non-zero !Battle_RewardItems entry,
;     with the item id in !Battle_Unk7F0200 (see the quirks);
;   - then for each PC slot 0-2 with an id in !Battler_UnkAEFF (arg 0 =
;     that id): 4 when !Battle_UnkB2B0 bit 7 is set, repeated
;     !Battle_UnkB311 times (at least once; the count is used up); 5 when
;     !Battle_UnkB2B3 bit 3 is set, once per entry of the PC's 8-byte list
;     at !Battle_UnkB3CE (arg 1 = the entry) up to an $FF or the eighth;
;     6 when bit 2 is set, once per entry of !Battle_UnkB305 up to an $FF
;     (arg 0 = the entry); 7 when bit 1 is set (arg 0 = !Battle_UnkB310).
; Messages 2 and 3 show the gold and items BattleSys_Main pays; the
; bits and lists of 0, 1 and 4-7 are set by BattleSys_AwardExpAndTp and
; its callees (BattleSys_ApplyExpStep: bit 7 and !Battle_UnkB2B0 /
; B311, level-ups; BattleSys_TryNextTech: bit 4; BattleSys_LearnSingleTech
; / LearnComboTechs: !Battle_UnkB2B3 and the lists, new techs), so they
; probably show the experience, tech points, level-ups and new single,
; double and triple techs.
; Quirks: message 1 tests only the low 16 bits (LDX sets Z), so a sum
; of exactly a multiple of $10000 shows nothing; message 3 writes its
; argument to $7F:0200, not $7E:0200 like the others (whether
; $CD:0021 reads it there is not traced); message 6 walks !Battle_UnkB305
; with one counter (!Battle_UnkB30F) for all three PCs and no bound, so
; a later PC goes on where the earlier one stopped.
; Callers (1 JSL site): BattleSys_Main ($C1:83F5).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A, X, Y clobbered; !Battle_UnkB1F4 = 3,
;        !Battle_UnkB30F advanced, !Battle_UnkB311 entries used up,
;        !Battle_UnkB3CC written; what $CD:0021 changes
; Callee: BattleSys_UnkVecCD0021 (A = message 0-7)
org $FDAD17
BattleFD_UnkAD17:
    STZ.w !Battle_UnkB30F
    LDA.w !Battle_UnkB2AF
    BIT.b #!Battle_RewardBitUnk0
    BEQ .msg1
    LDX.w !Battle_UnkB28C
    BEQ .msg1
    STX.w !Battle_MsgArg0
    STZ.w !Battle_MsgArg2
    LDA.b #!Battle_EndMsgUnk0
    JSL BattleSys_UnkVecCD0021
.msg1:
    LDA.w !Battle_UnkB2AF
    BIT.b #!Battle_RewardBitUnk6
    BEQ .msg2
    LDA.w !Battle_UnkB2DD
    LDX.w !Battle_UnkB2DB
    BNE .msg1_show
    BEQ .msg2
.msg1_show:
    STX.w !Battle_MsgArg0
    STA.w !Battle_MsgArg2
    LDA.b #!Battle_EndMsgUnk1
    JSL BattleSys_UnkVecCD0021
.msg2:
    LDA.w !Battle_UnkB2AF
    BIT.b #!Battle_RewardBitGold
    BEQ .msg3
    LDX.w !Battle_RewardGold
    BEQ .msg3
    STX.w !Battle_MsgArg0
    STZ.w !Battle_MsgArg2
    LDA.b #!Battle_EndMsgGold
    JSL BattleSys_UnkVecCD0021
.msg3:
    LDA.w !Battle_UnkB2AF
    BIT.b #!Battle_RewardBitItem
    BEQ .pcs
    TDC
    TAY
.item:
    LDA.w !Battle_RewardItems,Y
    BEQ .item_next
    STA.l !Battle_Unk7F0200
    LDA.b #!Battle_EndMsgItem
    PHY
    JSL BattleSys_UnkVecCD0021
    PLY
.item_next:
    INY
    CPY.w #!Battle_NumRewardItems
    BCC .item
.pcs:
    TDC
    TAX
    STX.w !Battle_UnkB1F4
.pc:
    LDX.w !Battle_UnkB1F4
    LDA.w !Battler_UnkAEFF,X
    CMP.b #!Battle_EntryNone
    BNE .msg4
    JMP .pc_next
.msg4:
    LDX.w !Battle_UnkB1F4
    LDA.w !Battle_UnkB2B0,X
    BIT.b #!Battle_B2B0Msg4Bit
    BEQ .msg5
    LDX.w !Battle_UnkB1F4
    LDA.w !Battler_UnkAEFF,X
    STA.w !Battle_MsgArg0
    LDA.b #!Battle_EndMsgUnk4
    JSL BattleSys_UnkVecCD0021
    LDX.w !Battle_UnkB1F4
    DEC.w !Battle_UnkB311,X
    LDA.w !Battle_UnkB311,X
    CMP.b #0
    BNE .msg4
.msg5:
    LDX.w !Battle_UnkB1F4
    LDA.w !Battle_UnkB2B3,X
    BIT.b #!Battle_B2B3Msg5Bit
    BEQ .msg6
    TDC
    LDA.w !Battle_UnkB1F4
    ASL A
    ASL A
    ASL A
    STA.w !Battle_UnkB3CC               ; the PC's list: entry PC * 8
.msg5_entry:
    LDA.w !Battle_UnkB3CC
    TAX
    LDA.w !Battle_UnkB3CE,X
    CMP.b #!Battle_EntryNone
    BEQ .msg6
    LDX.w !Battle_UnkB1F4
    LDA.w !Battler_UnkAEFF,X
    STA.w !Battle_MsgArg0
    TDC
    LDA.w !Battle_UnkB3CC
    TAX
    LDA.w !Battle_UnkB3CE,X
    STA.w !Battle_MsgArg1
    LDA.b #!Battle_EndMsgUnk5
    JSL BattleSys_UnkVecCD0021
    LDA.w !Battle_UnkB3CC
    INC A
    STA.w !Battle_UnkB3CC
    AND.b #!Battle_UnkB3CEListMask
    BEQ .msg6
    BRA .msg5_entry
.msg6:
    LDX.w !Battle_UnkB1F4
    LDA.w !Battle_UnkB2B3,X
    BIT.b #!Battle_B2B3Msg6Bit
    BEQ .msg7
.msg6_entry:
    TDC
    LDA.w !Battle_UnkB30F
    TAX
    LDA.w !Battle_UnkB305,X
    CMP.b #!Battle_EntryNone
    BEQ .msg7
    STA.w !Battle_MsgArg0
    LDA.b #!Battle_EndMsgUnk6
    JSL BattleSys_UnkVecCD0021
    LDA.w !Battle_UnkB30F
    INC A
    STA.w !Battle_UnkB30F
    BRA .msg6_entry
.msg7:
    LDX.w !Battle_UnkB1F4
    LDA.w !Battle_UnkB2B3,X
    BIT.b #!Battle_B2B3Msg7Bit
    BEQ .pc_next
    LDA.w !Battle_UnkB310
    STA.w !Battle_MsgArg0
    LDA.b #!Battle_EndMsgUnk7
    JSL BattleSys_UnkVecCD0021
.pc_next:
    LDA.w !Battle_UnkB1F4
    INC A
    STA.w !Battle_UnkB1F4
    CMP.b #!Battle_NumPcSlots
    BCS .done
    JMP .pc
.done:
    RTL

; $FD:AE52 — BattleFD_UnkAE52 (71 bytes, $AE52–$AE98)
; Builds a PC's stat block from its character record: for PC slot Y
; with a character id in !Battler_UnkAEFF (not negative), copies the
; id's $50-byte record at !Menu_CharRecords + id * $50 to the slot's
; stat block (the !BattleRom_PcStatBlock address, BattlerStats + $2D)
; and zeroes the next $30 bytes. Battle_SetupBattle runs it for PCs 0-2
; (the ids are the ones BattleFD_UnkB22E took from !Pc_CharId).
; The $80 bytes from +$2D run $2D bytes into the next slot's record
; (PC 2's into BattlerStats[3], which Battle_SetupBattle does not clear:
; its clear starts at BattlerStats[3].Unk2D).
; Callers (3 JSL sites): Battle_SetupBattle ($C1:FAC1, $C1:FAD9, $C1:FAF1).
; Entry: M=1, X=0, DP=0, DB=$7E; Y = PC slot (0-2)
; Exit:  M=1, X=0; A = $80 (B = 0) after a copy, else the negative id;
;        X, Y clobbered on a copy, else X unchanged, Y unchanged;
;        DP $00 = $80, $02 = the id; !Battle_MathA..MathHi as
;        Battle_Mul16 leaves them
; Callee: Battle_Mul16Long
!BattleFDCopy_Count = !BattleTmp_00     ; 1 B: bytes done (also the table offset at first)
!BattleFDCopy_Id    = !BattleTmp_02     ; 2 B: the character id
org $FDAE52
BattleFD_UnkAE52:
    TDC
    LDA.w !Battler_UnkAEFF,Y
    BMI .done
    TAX
    STX.b !BattleFDCopy_Id
    TYA
    ASL A
    TAX
    STX.b !BattleFDCopy_Count
    REP #$20
    LDX.b !BattleFDCopy_Count
    LDA.l !BattleRom_PcStatBlock,X
    TAY                                 ; Y = the slot's stat block
    TDC
    SEP #$20
    STA.b !BattleFDCopy_Count
    LDX.b !BattleFDCopy_Id
    STX.b !Battle_MathB
    LDX.w #!Battle_CharRecordSize
    STX.b !Battle_MathA
    JSL Battle_Mul16Long
    LDX.b !Battle_MathLo
.copy:
    LDA.w !Menu_CharRecords,X
    STA.w !Battle_WramAbs,Y
    INY
    INX
    INC.b !BattleFDCopy_Count
    LDA.b !BattleFDCopy_Count
    CMP.b #!Battle_CharRecordSize
    BCC .copy
.zero:
    TDC
    STA.w !Battle_WramAbs,Y
    INY
    INC.b !BattleFDCopy_Count
    LDA.b !BattleFDCopy_Count
    BPL .zero                           ; up to $80 bytes in all
.done:
    RTL

; $FD:AE99 — BattleFD_UnkAE99 (43 bytes, $AE99–$AEC3)
; Copies BattlerStats.Unk57 of PCs 0-2 to !Battle_UnkB3BA-B3BC and
; counts in !Battle_UnkB3BD how many of them are !Battle_Unk57CountId
; ($A9). BattlerStats.Unk57 is byte $2A of the character record
; (BattleFD_UnkAE52); what it and the count mean is not traced.
; Callers (1 JSL site): Battle_SetupBattle ($C1:FB55).
; Entry: M=1, X=0, DP any, DB=$7E
; Exit:  M=1, X=0; A = PC 2's BattlerStats.Unk57; X, Y unchanged
org $FDAE99
BattleFD_UnkAE99:
    STZ.w !Battle_UnkB3BD
    LDA.w BattlerStats.Unk57
    STA.w !Battle_UnkB3BA
    CMP.b #!Battle_Unk57CountId
    BNE .pc1
    INC.w !Battle_UnkB3BD
.pc1:
    LDA.w BattlerStats[1].Unk57
    STA.w !Battle_UnkB3BA+1
    CMP.b #!Battle_Unk57CountId
    BNE .pc2
    INC.w !Battle_UnkB3BD
.pc2:
    LDA.w BattlerStats[2].Unk57
    STA.w !Battle_UnkB3BA+2
    CMP.b #!Battle_Unk57CountId
    BNE .done
    INC.w !Battle_UnkB3BD
.done:
    RTL

; $FD:AEC4 — BattleFD_UnkAEC4 (46 bytes, $AEC4–$AEF1)
; For each PC 0-2 whose BattlerStats.Unk57 is !Battle_Unk57FlagId ($AB),
; sets bit 2 of its BattlerStats.Unk4C+4 (+$50). Battle_SetupBattle's
; last call; what the bit does is not traced.
; Callers (1 JSL site): Battle_SetupBattle ($C1:FDA9).
; Entry: M=1, X=0, DP any, DB=$7E
; Exit:  M=1, X=0; A clobbered; X, Y unchanged
org $FDAEC4
BattleFD_UnkAEC4:
    LDA.w BattlerStats.Unk57
    CMP.b #!Battle_Unk57FlagId
    BNE .pc1
    LDA.w BattlerStats.Unk4C+4
    ORA.b #!Battle_Unk50Bit2
    STA.w BattlerStats.Unk4C+4
.pc1:
    LDA.w BattlerStats[1].Unk57
    CMP.b #!Battle_Unk57FlagId
    BNE .pc2
    LDA.w BattlerStats[1].Unk4C+4
    ORA.b #!Battle_Unk50Bit2
    STA.w BattlerStats[1].Unk4C+4
.pc2:
    LDA.w BattlerStats[2].Unk57
    CMP.b #!Battle_Unk57FlagId
    BNE .done
    LDA.w BattlerStats[2].Unk4C+4
    ORA.b #!Battle_Unk50Bit2
    STA.w BattlerStats[2].Unk4C+4
.done:
    RTL

; $FD:AEF2 — BattleFD_UnkAEF2 (142 bytes, $AEF2–$AF7F)
; Fills the 5-byte records of !Battle_Unk1C48 (15 bytes, one record per
; PC 0-2) from the PCs' stat blocks. All 15 bytes are zeroed first; then
; for each PC whose PcStatBlk.Unk29 (BattlerStats.Unk56) is non-zero:
;   +0 = that value; +2 = $80; +3 = 1;
;   +4 = $80 >> n, where n = !Battle_UnkB1BE[k] and k is the number of
;        the highest set bit of byte 0 of the value's 6-byte record at
;        !BattleRom_UnkCC06A7 (bit 7 = 0 ... bit 0 = 7, 8 when none);
;        left as 0 when that !Battle_UnkB1BE byte is negative.
; !Battle_UnkB1BE is indexed by character id elsewhere (BattleSys_Main),
; so the record bit probably stands for a character. BattleSys_Main
; copies +0 back to BattlerStats.Unk56 at the battle's end. What the
; record and the bytes mean is not traced.
; Quirk: an LDX of DP $02 before the $80 store is overwritten by the
; next LDX and has no effect.
; Callers (3 JSL sites): BattleSys_UnkBC60 ($C1:BCD8), BattleSys_UnkCE36 ($C1:CE36) and
;   Battle_SetupBattle ($C1:FB84).
; Entry: M=1, X=0, DP=0, DB=$7E
; Exit:  M=1, X=0; A = 3 (B = 0); X, Y clobbered; DP $02 = 3, $04, $06
;        and $0A written; !Battle_MathA..MathHi as Battle_Mul16 leaves them
; Callee: Battle_Mul16Long
!BattleFD1C48_Pc   = !BattleTmp_02      ; 2 B: PC 0-2
!BattleFD1C48_Rec  = !BattleTmp_04      ; 2 B: value * 6, its record in !BattleRom_UnkCC06A7
!BattleFD1C48_Val  = !BattleTmp_06      ; 1 B: the PcStatBlk.Unk29 value
!BattleFD1C48_Ofs  = !BattleTmp_0A      ; 2 B: PC * 5, its record in !Battle_Unk1C48
org $FDAEF2
BattleFD_UnkAEF2:
    TDC
    TAX
.clear:
    STA.l !Battle_Unk1C48,X
    INX
    CPX.w #!Battle_Unk1C48Bytes
    BNE .clear
    TDC
    TAX
    STX.b !BattleFD1C48_Pc
    STX.b !BattleFD1C48_Ofs
.pc:
    LDX.b !BattleFD1C48_Pc
    REP #$20
    TXA
    ASL A
    TAX
    LDA.l !BattleRom_PcStatBlock,X
    TAX                                 ; X = the PC's stat block
    TDC
    SEP #$20
    LDA.w PcStatBlk.Unk29,X
    STA.b !BattleFD1C48_Val
    BEQ .pc_next
    TAX
    STX.b !Battle_MathA
    LDA.b #!BattleRom_UnkCC06A7Size
    TAX
    STX.b !Battle_MathB
    JSL Battle_Mul16Long
    LDX.b !Battle_MathLo
    STX.b !BattleFD1C48_Rec
    LDA.b !BattleFD1C48_Val
    LDX.b !BattleFD1C48_Ofs
    STA.l !Battle_Unk1C48,X
    TDC
    TAY
    LDX.b !BattleFD1C48_Rec
    LDA.l !BattleRom_UnkCC06A7,X
.find_bit:
    BIT.b #!Battle_HighBit
    BNE .found
    ASL A
    INY
    CPY.w #8
    BCC .find_bit
.found:
    LDA.w !Battle_UnkB1BE,Y
    BMI .no_bit
    TAX
    LDA.b #!Battle_HighBit
.shift:
    DEX
    BMI .store_bit
    LSR A
    BRA .shift
.store_bit:
    LDX.b !BattleFD1C48_Ofs
    STA.l !Battle_Unk1C48+4,X
.no_bit:
    LDX.b !BattleFD1C48_Pc              ; quirk: overwritten below
    LDA.b #!Battle_Unk1C4AInit
    LDX.b !BattleFD1C48_Ofs
    STA.w !Battle_Unk1C48+2,X
    LDA.b #1
    STA.w !Battle_Unk1C48+3,X
.pc_next:
    REP #$20
    LDA.b !BattleFD1C48_Ofs
    CLC
    ADC.w #!Battle_Unk1C48Stride
    STA.b !BattleFD1C48_Ofs
    TDC
    SEP #$20
    INC.b !BattleFD1C48_Pc
    LDA.b !BattleFD1C48_Pc
    CMP.b #!Battle_NumPcSlots
    BCS .done
    JMP .pc
.done:
    RTL

; ============================================================
; Battle helpers, part 2 ($FD:AF80–$FD:B956)
; More of the bank-$C1 battle engine's long callees: the item list
; entries, the per-item record offsets, the stat boosts, and most of
; Battle_SetupBattle's steps (the battlers' records, the enemies' stats,
; the turn-list timers, the clears, the first ATB values). Same state
; as part 1: M=1, X=0, DP=0, DB=$7E, bank-$C1 scratch and math cells.
; ============================================================

; $FD:AF80 — BattleFD_AddItemEntry (179 bytes, $AF80–$B032)
; Adds item A to the battle item list (Item_BattleList) at offset DP $04,
; with quantity DP $0E, when the item is one the list takes: an id of
; $BC or more whose byte 0 in !BattleRom_ItemUseFlags (3 B per id - $BC)
; has bit 7 set. The entry gets .Id = the id, .TargetMode from
; !BattleRom_ItemTargetMode, .Flags = that byte 0 without bit 7,
; .Quantity = DP $0E, and DP $04 moves on 5 bytes. Otherwise
; !Battle_UnkAF23 is set to 1 (it is zeroed first). Either way DP $00
; and $08 are counted up.
; Quirk: ids below $5A branch to the same place as the others (CMP, then
; BCS and BRA to one label), so the code for them at $AF8B-$AFD6 is
; never run; it would fill .Id, .Flags ($80) and .PcMask from the
; record of !BattleRom_UnkCC06A7 the way BattleFD_UnkAEF2 does.
; BattleFD_AddItemEntry_Skip ($FD:B01C, the step that moves DP $04 on)
; is a second entry: BattleSys_UnkCDFF calls it for an empty inventory
; entry, so the list keeps an entry there with whatever it held; DP $04
; moves on 5 bytes and DP $00 and $08 are counted up, nothing else is
; written.
; Callers (2 JSL sites): BattleSys_UnkCDFF ($C1:CE2A) and BattleSys_AddBattleItem ($C1:F012).
; Callers of BattleFD_AddItemEntry_Skip (1 JSL site): BattleSys_UnkCDFF ($C1:CE1C).
; Entry: M=1, X=0, DP=0, DB=$7E; A = item id; DP $04 = list offset,
;        DP $0E = quantity (BattleFD_AddItemEntry_Skip: M any, X=0, DP=0,
;        DB=$7E; DP $04 = list offset)
; Exit:  M=1, X=0; A, X, Y clobbered;
;        DP $00 and $08 + 1, $04 + 5 when added; DP $02, $06, $0A
;        written; !Battle_UnkAF23 = 0 added, 1 not
;        (BattleFD_AddItemEntry_Skip: M=1, X=0; A = 0 with B = 0; X, Y
;        unchanged; DP $04 + 5, DP $00 and $08 + 1)
; Callee: Battle_Mul16Long (only in the dead code)
!BattleFDItem_Rec  = !BattleTmp_02      ; 2 B: offset of the item's record (id - $BC) * 3
!BattleFDItem_Ofs  = !BattleTmp_04      ; 2 B: the list offset (argument)
!BattleFDItem_Id   = !BattleTmp_06      ; 1 B: the item id
!BattleFDItem_Idx  = !BattleTmp_0A      ; 2 B: id - $BC
!BattleFDItem_Qty  = !BattleTmp_0E      ; 1 B: the quantity (argument)
org $FDAF80
BattleFD_AddItemEntry:
    STZ.w !Battle_UnkAF23
    STA.b !BattleFDItem_Id
    CMP.b #!Battle_ItemClass1First
    BCS .battle_item
    BRA .battle_item                    ; quirk: the code below is never reached
.dead:
    LDX.b !BattleFDItem_Ofs
    STA.w Item_BattleList.Id,X
    TAX
    STX.b !Battle_MathA
    LDA.b #!BattleRom_UnkCC06A7Size
    TAX
    STX.b !Battle_MathB
    JSL Battle_Mul16Long
    LDX.b !Battle_MathLo
    STX.b !BattleFDItem_Rec
    TDC
    TAY
    LDX.b !BattleFDItem_Rec
    LDA.l !BattleRom_UnkCC06A7,X
.dead_find_bit:
    BIT.b #!Battle_HighBit
    BNE .dead_found
    ASL A
    INY
    CPY.w #8
    BCC .dead_find_bit
    TDC
    LDX.b !BattleFDItem_Ofs
    STA.w Item_BattleList.Id,X
    BRA BattleFD_AddItemEntry_Skip
.dead_found:
    LDA.w !Battle_UnkB1BE,Y
    BMI .dead_flags
    TAX
    LDA.b #!Battle_HighBit
.dead_shift:
    DEX
    BMI .dead_mask
    LSR A
    BRA .dead_shift
.dead_mask:
    LDX.b !BattleFDItem_Ofs
    STA.w Item_BattleList.PcMask,X
.dead_flags:
    LDA.b #!Battle_ItemFlagUnusable
    LDX.b !BattleFDItem_Ofs
    STA.w Item_BattleList.Flags,X
    BRA .quantity
.battle_item:
    LDA.b !BattleFDItem_Id
    CMP.b #!Battle_ItemClass4First
    BCC BattleFD_AddItemEntry_Skip_not_added
    LDA.b !BattleFDItem_Id
    SEC
    SBC.b #!Battle_ItemClass4First
    TAX
    STX.b !BattleFDItem_Idx
    ASL A
    CLC
    ADC.b !BattleFDItem_Idx
    TAX
    STX.b !BattleFDItem_Rec
    LDX.b !BattleFDItem_Rec
    LDA.l !BattleRom_ItemUseFlags,X
    BIT.b #!Battle_ItemListBit
    BEQ BattleFD_AddItemEntry_Skip_not_added
    LDA.b !BattleFDItem_Id
    LDX.b !BattleFDItem_Ofs
    STA.w Item_BattleList.Id,X
    LDX.b !BattleFDItem_Idx
    LDA.l !BattleRom_ItemTargetMode,X
    LDX.b !BattleFDItem_Ofs
    STA.w Item_BattleList.TargetMode,X
    LDX.b !BattleFDItem_Rec
    LDA.l !BattleRom_ItemUseFlags,X
    AND.b #!Battle_ItemListBit^$FF
    LDX.b !BattleFDItem_Ofs
    STA.w Item_BattleList.Flags,X
.quantity:
    LDA.b !BattleFDItem_Qty
    LDX.b !BattleFDItem_Ofs
    STA.w Item_BattleList.Quantity,X
BattleFD_AddItemEntry_Skip:             ; header: see BattleFD_AddItemEntry
    REP #$20
    LDA.b !BattleFDItem_Ofs
    CLC
    ADC.w #!Battle_ItemEntrySize
    STA.b !BattleFDItem_Ofs
    TDC
    SEP #$20
    BRA .count
.not_added:
    INC.w !Battle_UnkAF23
.count:
    INC.b !BattleTmp_00
    INC.b !BattleTmp_08
    RTL

; $FD:B033 — BattleFD_ItemRecOffset (162 bytes, $B033–$B0D4)
; Offset in bank $CC of item A's record, by id range:
;   below $5A: id * 5 + $0262;     $5A-$7A: (id - $5A) * 3 + $047E;
;   $7B-$93: (id - $7B) * 3 + $04E1; $94-$BB: (id - $94) * 4 + $052C;
;   $BC-$F1: (id - $BC) * 4 + $05CC; $F2 and up: X as it came.
; Five tables of records, one per id range (probably the item classes;
; what the records hold is not traced). Its caller, BattleSys_UnkCF15 ($C1:CF2F), reads
; LDA.l $CC0000,X with the result.
; Callers (1 JSL site): BattleSys_UnkCF15 ($C1:CF2F).
; Entry: M=1, X=0, DP=0, DB any; A = item id with B = 0 (TAX takes it into
;        the Mul16 factor)
; Exit:  M=1, X=0; X = the offset (unchanged for $F2 and up); A = 0 (B
;        too) after a multiply, else the id; Y unchanged; !Battle_MathA..
;        MathHi as Battle_Mul16 leaves them
; Callee: Battle_Mul16Long
org $FDB033
BattleFD_ItemRecOffset:
    CMP.b #!Battle_ItemClass1First
    BCS .not_class0
    TAX
    STX.b !Battle_MathA
    LDA.b #!Battle_ItemRec0Size
    TAX
    STX.b !Battle_MathB
    JSL Battle_Mul16Long
    REP #$20
    LDA.b !Battle_MathLo
    CLC
    ADC.w #!Battle_ItemRec0Ofs
    TAX
    TDC
    SEP #$20
    JMP .done
.not_class0:
    CMP.b #!Battle_ItemClass2First
    BCS .not_class1
    SEC
    SBC.b #!Battle_ItemClass1First
    TAX
    STX.b !Battle_MathA
    LDA.b #!Battle_ItemRec1Size
    TAX
    STX.b !Battle_MathB
    JSL Battle_Mul16Long
    REP #$20
    LDA.b !Battle_MathLo
    CLC
    ADC.w #!Battle_ItemRec1Ofs
    TAX
    TDC
    SEP #$20
    BRA .done
.not_class1:
    CMP.b #!Battle_ItemClass3First
    BCS .not_class2
    SEC
    SBC.b #!Battle_ItemClass2First
    TAX
    STX.b !Battle_MathA
    LDA.b #!Battle_ItemRec1Size
    TAX
    STX.b !Battle_MathB
    JSL Battle_Mul16Long
    REP #$20
    LDA.b !Battle_MathLo
    CLC
    ADC.w #!Battle_ItemRec2Ofs
    TAX
    TDC
    SEP #$20
    BRA .done
.not_class2:
    CMP.b #!Battle_ItemClass4First
    BCS .not_class3
    SEC
    SBC.b #!Battle_ItemClass3First
    TAX
    STX.b !Battle_MathA
    LDA.b #!Battle_ItemRec3Size
    TAX
    STX.b !Battle_MathB
    JSL Battle_Mul16Long
    REP #$20
    LDA.b !Battle_MathLo
    CLC
    ADC.w #!Battle_ItemRec3Ofs
    TAX
    TDC
    SEP #$20
    BRA .done
.not_class3:
    CMP.b #!Battle_ItemIdEnd
    BCS .done
    SEC
    SBC.b #!Battle_ItemClass4First
    TAX
    STX.b !Battle_MathA
    LDA.b #!Battle_ItemRec3Size
    TAX
    STX.b !Battle_MathB
    JSL Battle_Mul16Long
    REP #$20
    LDA.b !Battle_MathLo
    CLC
    ADC.w #!Battle_ItemRec4Ofs
    TAX
    TDC
    SEP #$20
.done:
    RTL

; $FD:B0D5 — BattleFD_UnkB0D5 (76 bytes, $B0D5–$B120)
; Turn-list and panel setup: zeroes the flags of all 13 turn lists
; (!Battle_ListFlags), sets every !Battle_ListRuns entry to 10
; (!Battle_ListRunsReset: this is where the runs are first set), zeroes
; the enemies' 8 !Battler_Unk9F29 bytes and !Battle_Unk9F34, then for
; each enemy entry with an id in !Battler_UnkAF0A sets its
; !Battler_Unk9F29 byte to 2 when its BattlerStats.Unk47 bit 1 is clear
; and to 0 when it is set.
; Callers (1 JSL site): Battle_SetupBattle ($C1:FCFE).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A = 0 (B too); X = $400; Y = 8
org $FDB0D5
BattleFD_UnkB0D5:
    TDC
    TAX
.clear_flags:
    STA.w !Battle_ListFlags,X
    INX
    CPX.w #!Battle_ListEntries
    BNE .clear_flags
    TDC
    TAX
    LDA.b #!Battle_ListRunsReset
.set_runs:
    STA.w !Battle_ListRuns,X
    INX
    CPX.w #!Battle_ListEntries
    BCC .set_runs
    TDC
    TAX
.clear_9f29:
    STZ.w !Battler_Unk9F29+!Battle_FirstEnemySlot,X
    INX
    CPX.w #!Battle_NumEnemies
    BCC .clear_9f29
    STZ.w !Battle_Unk9F34
    TDC
    TAX
    TAY
.enemy:
    LDA.w !Battler_UnkAF0A+!Battle_FirstEnemySlot,Y
    CMP.b #!Battle_EntryNone
    BEQ .next
    LDA.w BattlerStats[3].Unk47,X
    AND.b #!Battle_Unk47Bit1
    EOR.b #!Battle_Unk47Bit1
    STA.w !Battler_Unk9F29+!Battle_FirstEnemySlot,Y
.next:
    INY
    REP #$20
    TXA
    CLC
    ADC.w #!Battle_StatsStride
    TAX
    TDC
    SEP #$20
    CPY.w #!Battle_NumEnemies
    BCC .enemy
    RTL

; $FD:B121 — BattleFD_UnkB121 (32 bytes, $B121–$B140)
; Copies bits 0-1 of each enemy's BattlerStats.Unk47 (slots 3-10) to
; !Battle_UnkA020 (one byte per enemy entry). What they mean is not
; traced.
; Callers (1 JSL site): Battle_SetupBattle ($C1:FAB9).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A = 0 (B too); X = $580; Y = 8
org $FDB121
BattleFD_UnkB121:
    LDX.w #!Battle_FirstEnemySlot*!Battle_StatsStride
    LDY.w #0
.enemy:
    LDA.w BattlerStats.Unk47,X
    AND.b #!Battle_Unk47Bits01
    STA.w !Battle_UnkA020,Y
    REP #$20
    TXA
    CLC
    ADC.w #!Battle_StatsStride
    TAX
    TDC
    SEP #$20
    INY
    CPY.w #!Battle_NumEnemies
    BCC .enemy
    RTL

; $FD:B141 — BattleFD_ApplyRecBoost (12 bytes, $B141–$B14C)
; Applies the stat boost an item record names: byte 4 of the record at
; DP $08 (an address in bank $CC; BattleSys_UnkCE3A points it at three
; equipment records of a PC, probably the weapon, armour and helmet, a
; guess from the id bases) is a boost number; when it is non-zero this
; falls into BattleFD_UnkB14D with it, else returns.
; Callers (3 JSL sites): BattleSys_UnkCE3A ($C1:CEA4, $C1:CED6, $C1:CF08).
; Entry: M=1, X=0, DP=0, DB=$7E (for BattleFD_UnkB14D's .w stores); DP $08 =
;        the record's address in bank $CC,
;        DP $0E = the boost table, DP $00 = the stat block (as
;        BattleFD_UnkB14D)
; Exit:  M=1, X=0; as BattleFD_UnkB14D when byte 4 is non-zero; else A = 0
;        (B too), X = DP $08
org $FDB141
BattleFD_ApplyRecBoost:
    TDC
    LDX.b !BattleTmp_08
    LDA.l !BattleRom_BankCC+4,X
    BNE BattleFD_UnkB14D
    JMP BattleFD_UnkB14D_Done

; $FD:B14D — BattleFD_UnkB14D (180 bytes, $B14D–$B200)
; Applies stat boost A to the stat block at DP $00: its 2-byte entry in
; bank $CC at DP $0E + A * 2 has a stat mask (byte 0) and an amount
; (byte 1); for each mask bit set, the amount is added to one of the
; block's stats with a cap: bit 7 .Unk36 (99), bit 6 .Unk38 (16), bit 5
; .Unk37 (99), bit 4 .Unk3A (99), bit 3 .Unk3B ($FF: kept at $FF when the
; add carries), bit 2 .Unk39 (99), bit 1 .Unk3C (99); bit 0 is not
; used. Battle_SetupBattle passes a PC's
; PcStatBlk.Unk4D with the table !Battle_Unk29D7 ($CC:29D7);
; BattleFD_ApplyRecBoost an item record's byte 4.
; BattleFD_UnkB14D_Done ($FD:B200, the RTL) is BattleFD_ApplyRecBoost's
; exit when there is no boost.
; The 7 bytes are the ones BattleSys_UnkCE3A copies from the block's
; +$0B..+$11 (PcStatBlk.Unk0B-.Unk11). The caps of 99 and 16 look like stat limits; which stats they are is
; not traced.
; Callers (1 JSL site): Battle_SetupBattle ($C1:FC92).
; Callers note: also entered by BattleFD_ApplyRecBoost's BNE at $FD:B148,
;   just before this label.
; Callers of BattleFD_UnkB14D_Done (1 JMP site): BattleFD_ApplyRecBoost ($FD:B14A).
; Entry: M=1, X=0, DP=0, DB=$7E (the stores are .w); A = boost number
;        with B = 0 (it is doubled 16-bit); DP $00 = stat block address
;        (PcStatBlk), DP $0E = table address in bank $CC
; Exit:  M=1, X=0; A, X clobbered; Y unchanged; DP $04 (the mask shifted
;        out), $0A (the amount) and $0C (the entry's offset) written
!BattleFDBoost_Block = !BattleTmp_00    ; 2 B: the stat block (argument)
!BattleFDBoost_Mask  = !BattleTmp_04    ; 1 B: the stat mask, shifted left once per stat
!BattleFDBoost_Add   = !BattleTmp_0A    ; 1 B: the amount
!BattleFDBoost_Entry = !BattleTmp_0C    ; 2 B: the entry's address in bank $CC
!BattleFDBoost_Table = !BattleTmp_0E    ; 2 B: the table (argument)
BattleFD_UnkB14D:
    REP #$20
    ASL A
    CLC
    ADC.b !BattleFDBoost_Table
    TAX
    TDC
    SEP #$20
    STX.b !BattleFDBoost_Entry
    LDA.l !BattleRom_BankCC+1,X
    STA.b !BattleFDBoost_Add
    LDA.l !BattleRom_BankCC,X
    STA.b !BattleFDBoost_Mask
    BPL .stat38
    LDX.b !BattleFDBoost_Block
    LDA.w PcStatBlk.Unk36,X
    CLC
    ADC.b !BattleFDBoost_Add
    CMP.b #!Battle_StatCap99
    BCC .set36
    LDA.b #!Battle_StatCap99
.set36:
    STA.w PcStatBlk.Unk36,X
.stat38:
    ASL.b !BattleFDBoost_Mask
    LDA.b !BattleFDBoost_Mask
    BPL .stat37
    LDX.b !BattleFDBoost_Block
    LDA.w PcStatBlk.Unk38,X
    CLC
    ADC.b !BattleFDBoost_Add
    CMP.b #!Battle_StatCap16
    BCC .set38
    LDA.b #!Battle_StatCap16
.set38:
    STA.w PcStatBlk.Unk38,X
.stat37:
    ASL.b !BattleFDBoost_Mask
    LDA.b !BattleFDBoost_Mask
    BPL .stat3a
    LDX.b !BattleFDBoost_Block
    LDA.w PcStatBlk.Unk37,X
    CLC
    ADC.b !BattleFDBoost_Add
    CMP.b #!Battle_StatCap99
    BCC .set37
    LDA.b #!Battle_StatCap99
.set37:
    STA.w PcStatBlk.Unk37,X
.stat3a:
    ASL.b !BattleFDBoost_Mask
    LDA.b !BattleFDBoost_Mask
    BPL .stat3b
    LDX.b !BattleFDBoost_Block
    LDA.w PcStatBlk.Unk3A,X
    CLC
    ADC.b !BattleFDBoost_Add
    CMP.b #!Battle_StatCap99
    BCC .set3a
    LDA.b #!Battle_StatCap99
.set3a:
    STA.w PcStatBlk.Unk3A,X
.stat3b:
    ASL.b !BattleFDBoost_Mask
    LDA.b !BattleFDBoost_Mask
    BPL .stat39
    LDX.b !BattleFDBoost_Block
    LDA.w PcStatBlk.Unk3B,X
    CLC
    ADC.b !BattleFDBoost_Add
    BCC .set3b
    LDA.b #!Battle_StatCapFF
.set3b:
    STA.w PcStatBlk.Unk3B,X
.stat39:
    ASL.b !BattleFDBoost_Mask
    LDA.b !BattleFDBoost_Mask
    BPL .stat3c
    LDX.b !BattleFDBoost_Block
    LDA.w PcStatBlk.Unk39,X
    CLC
    ADC.b !BattleFDBoost_Add
    CMP.b #!Battle_StatCap99
    BCC .set39
    LDA.b #!Battle_StatCap99
.set39:
    STA.w PcStatBlk.Unk39,X
.stat3c:
    ASL.b !BattleFDBoost_Mask
    LDA.b !BattleFDBoost_Mask
    BPL BattleFD_UnkB14D_Done
    LDX.b !BattleFDBoost_Block
    LDA.w PcStatBlk.Unk3C,X
    CLC
    ADC.b !BattleFDBoost_Add
    CMP.b #!Battle_StatCap99
    BCC .set3c
    LDA.b #!Battle_StatCap99
.set3c:
    STA.w PcStatBlk.Unk3C,X
BattleFD_UnkB14D_Done:                  ; header: see BattleFD_UnkB14D
    RTL

; $FD:B201 — BattleFD_UnkB201 (34 bytes, $B201–$B222)
; BattleSys_Main's victory path, before the gold is paid: when a PC has
; BattlerStats.Unk57 = $A9 (!Battle_UnkB3BD non-zero, BattleFD_UnkAE99),
; adds the !Battle_UnkB28C sum to !Battle_RewardGold, zeroes B28C, and in
; !Battle_UnkB2AF clears bit 7 (no message 0 in BattleFD_UnkAD17) and
; sets bit 6 (!Battle_RewardBitGold). So when any PC has $A9 (however
; many), the battle's whole B28C sum is paid as gold instead; there is no
; per-PC share (what B28C and the $A9 value are is not traced).
; Callers (1 JSL site): BattleSys_Main ($C1:83E0).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A = !Battle_UnkB2AF, or 0 when !Battle_UnkB3BD is 0;
;        X, Y unchanged
org $FDB201
BattleFD_UnkB201:
    LDA.w !Battle_UnkB3BD
    BEQ .done
    REP #$20
    LDA.w !Battle_UnkB28C
    CLC
    ADC.w !Battle_RewardGold
    STA.w !Battle_RewardGold
    TDC
    STA.w !Battle_UnkB28C
    SEP #$20
    LDA.w !Battle_UnkB2AF
    AND.b #!Battle_RewardBitUnk0^$FF
    ORA.b #!Battle_RewardBitGold
    STA.w !Battle_UnkB2AF
.done:
    RTL

; $FD:B223 — BattleFD_UnkB223 (11 bytes, $B223–$B22D)
; Sets !Battle_UnkAE6D entry n to n for n = 0-10.
; Callers (1 JSL site): Battle_SetupBattle ($C1:FDA5).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A = 11 (B = 0); X = 10; Y unchanged
org $FDB223
BattleFD_UnkB223:
    TDC
.entry:
    TAX
    STA.w !Battle_UnkAE6D,X
    INC A
    CMP.b #!Battle_NumSlots
    BCC .entry
    RTL

; $FD:B22E — BattleFD_UnkB22E (176 bytes, $B22E–$B2DD)
; Battle_SetupBattle's second step: the battlers' entries.
;   - zeroes $580 bytes from BattlerStats.Unk2D (+$2D of all 11 records
;     and on to $63AC);
;   - !Pc_AtbCur and !Pc_AtbMax of the 3 PCs = $FF;
;   - !Battler_UnkAEFF / !Battler_UnkAF0A of all 11 slots = $FF, the 8
;     !Battle_UnkAF15 bytes = 0;
;   - each PC slot whose !Pc_CharId is not negative: both entries = the
;     id, counted in !Battle_PcCount;
;   - !Battle_Unk24 = 0; !Battle_UnkB1BE (7 B, per character id) = $FF,
;     then the slot of each PC taking part at its character's entry;
;   - the enemies from the 8 records of BattleEnemyInit ($29C4, 12 B
;     each): a record whose .Unk1 is not negative gives its .Id to the
;     entry's !Battler_UnkAEFF and !Battler_UnkAF0A; when its .Unk2 is
;     negative too, !Battler_UnkAEFF is set back to $FF and !Battle_UnkAF15
;     bit 7 set (so the enemy is in the battle's list but absent at the
;     start). BattleFD_RestoreEnemies skips entries with that bit set,
;     so it does not bring these in; what does is not traced (in
;     matched code only BattleAi_UnkAED3, with no caller found, clears
;     the bit).
; !Battle_EnemyCount ends as 8 whatever the records hold: it is counted
; for every record, used or not.
; Callers (1 JSL site): Battle_SetupBattle ($C1:FA93).
; Entry: M=1, X=0, DP=0 (TDC as zero; .b store to !Battle_Unk24), DB=$7E
; Exit:  M=1, X=0; A = 0 (B too); X = $60; Y = 8
org $FDB22E
BattleFD_UnkB22E:
    TDC
    TAX
.clear_stats:
    STA.w BattlerStats.Unk2D,X
    INX
    CPX.w #!Battle_NumSlots*!Battle_StatsStride
    BCC .clear_stats
    LDA.b #!Battle_AtbEmpty
    STA.w !Pc_AtbCur
    STA.w !Pc_AtbCur+1
    STA.w !Pc_AtbCur+2
    STA.w !Pc_AtbMax
    STA.w !Pc_AtbMax+1
    STA.w !Pc_AtbMax+2
    TDC
    TAX
    LDA.b #!Battle_EntryNone
.clear_ids:
    STA.w !Battler_UnkAEFF,X
    STA.w !Battler_UnkAF0A,X
    INX
    CPX.w #!Battle_NumSlots
    BCC .clear_ids
    TDC
    TAX
.clear_af15:
    STA.w !Battle_UnkAF15,X
    INX
    CPX.w #!Battle_NumEnemies
    BCC .clear_af15
    STA.w !Battle_PcCount
    TAX
.pc:
    LDA.w !Pc_CharId,X
    BMI .pc_next
    STA.w !Battler_UnkAEFF,X
    STA.w !Battler_UnkAF0A,X
    INC.w !Battle_PcCount
.pc_next:
    INX
    CPX.w #!Battle_NumPcSlots
    BCC .pc
    STZ.b !Battle_Unk24
    TDC
    TAX
    LDA.b #!Battle_EntryNone
.clear_b1be:
    STA.w !Battle_UnkB1BE,X
    INX
    CPX.w #!Battle_NumCharIds
    BCC .clear_b1be
    TDC
    TAX
.char_slot:
    LDA.w !Battler_UnkAEFF,X
    CMP.b #!Battle_EntryNone
    BEQ .char_slot_next
    TAY
    TXA
    STA.w !Battle_UnkB1BE,Y
.char_slot_next:
    INX
    CPX.w #!Battle_NumPcSlots
    BCC .char_slot
    TDC
    STA.w !Battle_EnemyCount
    TAX
    TAY
.enemy:
    LDA.w BattleEnemyInit.Unk1,X
    BMI .enemy_next
    LDA.w BattleEnemyInit.Id,X
    STA.w !Battler_UnkAEFF+!Battle_FirstEnemySlot,Y
    STA.w !Battler_UnkAF0A+!Battle_FirstEnemySlot,Y
    LDA.w BattleEnemyInit.Unk2,X
    BPL .enemy_next
    LDA.b #!Battle_EntryNone
    STA.w !Battler_UnkAEFF+!Battle_FirstEnemySlot,Y
    LDA.w !Battle_UnkAF15,Y
    ORA.b #!Battle_AF15Bit7
    STA.w !Battle_UnkAF15,Y
.enemy_next:
    INC.w !Battle_EnemyCount
    INY
    REP #$20
    TXA
    CLC
    ADC.w #!Battle_EnemyInitSize
    TAX
    TDC
    SEP #$20
    CPX.w #!Battle_NumEnemies*!Battle_EnemyInitSize
    BCC .enemy
    RTL

; $FD:B2DE — BattleFD_UnkB2DE (97 bytes, $B2DE–$B33E)
; Battle_SetupBattle's first step. Only with !Battle_Unk2989 bit 5 set
; (the mode in which Battle_RandRange returns its low bound and
; BattleSys_Main ends after one pass): BattleFD_UnkB33F rebuilds the
; character records from ROM, then each of the 8 records
; (!Menu_CharRecords, $50 B apart) gets bytes +11 and +14 = $23, +12 =
; $80, and the words +3, +5, +7 and +9 from a list in bank $FD: four
; words per character, from the address !BattleRom_UnkFDB99C holds for
; !Menu_Config+28 (doubled in 8 bits, so values of $80 and up wrap). So probably a fixed party set-up
; for that mode; the fields are not traced.
; Callers (1 JSL site): Battle_SetupBattle ($C1:FA8F).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; with bit 5 set A = 0 (B too), X = list end, Y = $280,
;        !Battle_PcCount = 3, !Battle_UnkAF1D = 0, $2400-$25FF and
;        $2600-$282F written (BattleFD_UnkB33F); else A = !Battle_Unk2989,
;        X, Y unchanged
; Callee: BattleFD_UnkB33F
org $FDB2DE
BattleFD_UnkB2DE:
    LDA.w !Battle_Unk2989
    BIT.b #!Battle_2989Bit5
    BNE .set_up
    JMP .done
.set_up:
    JSR BattleFD_UnkB33F
    TDC
    LDA.w !Menu_Config+28
    ASL A
    TAX
    REP #$20
    LDA.l !BattleRom_UnkFDB99C,X
    TAX
    TDC
    SEP #$20
    TDC
    TAY
.record:
    LDA.b #!Battle_DemoRecUnk0B
    STA.w !Menu_CharRecords+11,Y
    STA.w !Menu_CharRecords+14,Y
    LDA.b #!Battle_DemoRecUnk0C
    STA.w !Menu_CharRecords+12,Y
    REP #$20
    LDA.l !BattleRom_BankFD,X
    STA.w !Menu_CharRecords+3,Y
    INX
    INX
    LDA.l !BattleRom_BankFD,X
    STA.w !Menu_CharRecords+5,Y
    INX
    INX
    LDA.l !BattleRom_BankFD,X
    STA.w !Menu_CharRecords+7,Y
    INX
    INX
    LDA.l !BattleRom_BankFD,X
    STA.w !Menu_CharRecords+9,Y
    TYA
    CLC
    ADC.w #!Battle_CharRecordSize
    TAY
    TDC
    INX
    INX
    SEP #$20
    CPY.w #!Menu_CharRecordInitSize
    BCC .record
.done:
    RTL

; $FD:B33F — BattleFD_UnkB33F (36 bytes, $B33F–$B362)
; BattleFD_UnkB2DE's helper: !Battle_UnkAF1D = 0, !Battle_PcCount = 3,
; copies $230 bytes from !MenuRom_CharRecordInit ($CC:0000, the new-game
; records Menu_InitNewGameData copies) to !Menu_CharRecords
; ($2600-$282F), and fills !Menu_Unk2400 ($2400-$25FF) with the low byte
; of each byte's index (0-255 twice).
; Callers (1 JSR site): BattleFD_UnkB2DE ($FD:B2E8).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A = $FF (B = 0); X = $200; Y unchanged
org $FDB33F
BattleFD_UnkB33F:
    STZ.w !Battle_UnkAF1D
    LDA.b #!Battle_NumPcSlots
    STA.w !Battle_PcCount
    TDC
    TAX
.copy:
    LDA.l !MenuRom_CharRecordInit,X
    STA.w !Menu_CharRecords,X
    INX
    CPX.w #!Battle_DemoRecordBytes
    BCC .copy
    TDC
    TAX
.fill:
    TXA
    STA.w !Menu_Unk2400,X
    INX
    CPX.w #!Menu_Unk2400Size
    BNE .fill
    RTS

; $FD:B363 — BattleFD_UnkB363 (136 bytes, $B363–$B3EA)
; For PC slot Y with an id in !Battler_UnkAEFF:
;   - BattlerStats.Unk79 bit 7 set: ORs .Unk7B into the byte at
;     BattlerStats.Status + .Unk7A (a status byte picked by .Unk7A);
;   - BattlerStats.Unk57 = $A0: MaxHp + MaxHp / 4, $A1: MaxHp + MaxHp / 2,
;     at most 999 (CurHp is left alone).
; Battle_SetupBattle runs it for PCs 0-2 after saving the max HP
; (!Battle_SavedMaxHp), which BattleSys_Main puts back at the end.
; Quirk: a BIT #$40 of .Unk79 branches (BEQ) to the very next
; instruction, so it has no effect.
; Callers (3 JSL sites): Battle_SetupBattle ($C1:FD41, $C1:FD48, $C1:FD4F).
; Entry: M=1, X=0, DP=0, DB=$7E; Y = PC slot
; Exit:  M=1, X=0; A = 0 (B too) unless the slot is empty ($FF); X =
;        the slot * $80, or 0 for an empty slot; Y unchanged;
;        DP $00 = .Unk7B or 0, $02 = slot * $80 or 0, $04 = .Unk7A or 0
!BattleFDHp_Bits = !BattleTmp_00        ; 1-2 B: .Unk7B, the status bits
!BattleFDHp_Ofs  = !BattleTmp_02        ; 2 B: slot * $80
!BattleFDHp_Byte = !BattleTmp_04        ; 2 B: .Unk7A, the status byte's offset
org $FDB363
BattleFD_UnkB363:
    TDC
    TAX
    STX.b !BattleFDHp_Bits
    STX.b !BattleFDHp_Ofs
    STX.b !BattleFDHp_Byte
    LDA.w !Battler_UnkAEFF,Y
    CMP.b #!Battle_EntryNone
    BEQ .done
    REP #$20
    TYA
    XBA
    LSR A
    TAX                                 ; X = slot * $80
    STA.b !BattleFDHp_Ofs
    TDC
    SEP #$20
    LDA.w BattlerStats.Unk79,X
    BIT.b #!Battle_Unk79StatusBit
    BEQ .no_status
    TDC
    LDA.w BattlerStats.Unk7B,X
    STA.b !BattleFDHp_Bits
    LDA.w BattlerStats.Unk7A,X
    STA.b !BattleFDHp_Byte
    REP #$20
    TXA
    CLC
    ADC.b !BattleFDHp_Byte
    TAX
    TDC
    SEP #$20
    LDA.w BattlerStats.Status,X
    ORA.b !BattleFDHp_Bits
    STA.w BattlerStats.Status,X
.no_status:
    LDX.b !BattleFDHp_Ofs
    LDA.w BattlerStats.Unk79,X
    BIT.b #!Battle_Unk79Bit6
    BEQ .hp                             ; quirk: branches to the next instruction
.hp:
    LDA.w BattlerStats.Unk57,X
    CMP.b #!Battle_Unk57HpQuarter
    BNE .not_quarter
    REP #$20
    LDA.w BattlerStats.MaxHp,X
    LSR A
    LSR A
    CLC
    ADC.w BattlerStats.MaxHp,X
    CMP.w #!Battle_MaxHpCap
    BCC .set_quarter
    LDA.w #!Battle_MaxHpCap
.set_quarter:
    STA.w BattlerStats.MaxHp,X
    BRA .hp_done
.not_quarter:
    SEP #$20
    LDA.w BattlerStats.Unk57,X
    CMP.b #!Battle_Unk57HpHalf
    BNE .hp_done
    REP #$20
    LDA.w BattlerStats.MaxHp,X
    LSR A
    CLC
    ADC.w BattlerStats.MaxHp,X
    CMP.w #!Battle_MaxHpCap
    BCC .set_half
    LDA.w #!Battle_MaxHpCap
.set_half:
    STA.w BattlerStats.MaxHp,X
.hp_done:
    TDC                                 ; M is 0 or 1 here, by path
    SEP #$20
.done:
    RTL

; $FD:B3EB — BattleFD_UnkB3EB (19 bytes, $B3EB–$B3FD)
; Sets BattlerStats.Unk72 of the slot at X to $32 when its .Unk56 is $3D
; or $42. Run by BattleFD_UnkB555 for each PC whose BattlerStats.Unk57 is
; $B3. What the values mean is not traced.
; Quirk: a BRA to the very next instruction after the store.
; Callers (3 JSL sites): BattleFD_UnkB555 ($FD:B578, $FD:B586, $FD:B594).
; Entry: M=1, X=0, DP any, DB=$7E; X = slot * $80
; Exit:  M=1, X=0; A = .Unk56 or $32; X, Y unchanged
org $FDB3EB
BattleFD_UnkB3EB:
    LDA.w BattlerStats.Unk56,X
    CMP.b #!Battle_Unk56SetA
    BEQ .set
    CMP.b #!Battle_Unk56SetB
    BNE .done
.set:
    LDA.b #!Battle_Unk72Value
    STA.w BattlerStats.Unk72,X
    BRA .done                           ; quirk: branches to the next instruction
.done:
    RTL

; $FD:B3FE — BattleFD_UnkB3FE (58 bytes, $B3FE–$B437)
; For PC X with an id in !Battler_UnkAEFF: sets the 4 bytes of its
; BattlerStats.Unk6C to 4, then the byte picked by the highest of
; BattlerStats.Unk2E bits 7-4 (bit 7: +0, 6: +1, 5: +2, 4: +3) to 5;
; none set leaves all four at 4.
; Callers (3 JSL sites): Battle_SetupBattle ($C1:FB3D, $C1:FB47, $C1:FB51).
; Entry: M=1, X=0, DP any, DB=$7E; X = PC slot, Y = slot * $80
; Exit:  M=1, X=0; A clobbered; X unchanged; Y + 0 to 3 (the byte set
;        to 5)
org $FDB3FE
BattleFD_UnkB3FE:
    LDA.w !Battler_UnkAEFF,X
    CMP.b #!Battle_EntryNone
    BEQ .done
    LDA.b #!Battle_Unk6CBase
    STA.w BattlerStats.Unk6C,Y
    STA.w BattlerStats.Unk6C+1,Y
    STA.w BattlerStats.Unk6C+2,Y
    STA.w BattlerStats.Unk6C+3,Y
    LDA.w BattlerStats.Unk2E,Y
    BIT.b #!Battle_Unk2EBit7
    BEQ .not_bit7
    BRA .set
.not_bit7:
    BIT.b #!Battle_Unk2EBit6
    BEQ .not_bit6
    INY
    BRA .set
.not_bit6:
    BIT.b #!Battle_Unk2EBit5
    BEQ .not_bit5
    INY
    INY
    BRA .set
.not_bit5:
    BIT.b #!Battle_Unk2EBit4
    BEQ .done
    INY
    INY
    INY
.set:
    LDA.b #!Battle_Unk6CRaised
    STA.w BattlerStats.Unk6C,Y
.done:
    RTL

; $FD:B438 — BattleFD_UnkB438 (158 bytes, $B438–$B4D5)
; Builds an enemy's stat record from ROM: for enemy entry X (also in
; DP $02), with the id in its !Battler_UnkAF0A entry, the 23-byte record
; at BattleRom_EnemyStats + id * 23 fills BattlerStats[entry + 3] after
; BattleFD_ZeroStatBlock clears $80 bytes from its .Unk2D:
;   .Unk2D = the id; .CurHp = .MaxHp = record +0 (16-bit); .Unk3F =
;   record +2; .Status, .Status2 and .Unk4C+0 = 0; .Unk4C+3..+7 =
;   record +3..+7, then .Unk4C+1/.Unk4C+2 = copies of .Unk4C+6/+7;
;   .Unk64..+$6F = record +8..+$13; .Unk46..+$48 = record +$14..+$16.
; Battle_SetupBattle runs it for each entry, BattleFD_RestoreEnemies for
; each enemy it brings back.
; Quirk: .Unk3F is stored twice.
; Callers (4 JSL sites): BattleAi_RunSwapInEnemy ($C1:9C30), Battle_SetupBattle ($C1:FAAC),
;   BattleFD_RestoreEnemies ($FD:AA2E) and unmatched ($C1:9EDA).
; Entry: M=1, X=0, DP=0, DB=$7E; X = enemy entry 0-7, DP $02 = the same
;        (16-bit)
; Exit:  M=1, X=0; A = 3 (B = 0); X, Y clobbered; DP $00 = 3, $04 =
;        the id
; Callee: BattleFD_ZeroStatBlock
!BattleFDEnemy_Count = !BattleTmp_00    ; 1 B: bytes copied in the current run
!BattleFDEnemy_Entry = !BattleTmp_02    ; 2 B: the enemy entry (argument)
!BattleFDEnemy_Id    = !BattleTmp_04    ; 2 B: the id
org $FDB438
BattleFD_UnkB438:
    TDC
    TAY
    STY.b !BattleFDEnemy_Id
    LDA.w !Battler_UnkAF0A+!Battle_FirstEnemySlot,X
    STA.b !BattleFDEnemy_Id
    REP #$20
    ASL A
    ASL A
    ASL A
    STA.b !BattleFDEnemy_Count          ; id * 8 for a moment
    ASL A
    CLC
    ADC.b !BattleFDEnemy_Count
    SEC
    SBC.b !BattleFDEnemy_Id
    TAX                                 ; X = id * 23
    LDA.b !BattleFDEnemy_Entry
    XBA
    LSR A
    TAY                                 ; Y = entry * $80
    TDC
    SEP #$20
    JSR BattleFD_ZeroStatBlock
    LDA.b !BattleFDEnemy_Id
    STA.w BattlerStats[3].Unk2D,Y
    LDA.l !BattleRom_EnemyStats,X
    STA.w BattlerStats[3].CurHp,Y
    STA.w BattlerStats[3].MaxHp,Y
    INX
    LDA.l !BattleRom_EnemyStats,X
    STA.w BattlerStats[3].CurHp+1,Y
    STA.w BattlerStats[3].MaxHp+1,Y
    INX
    LDA.l !BattleRom_EnemyStats,X
    STA.w BattlerStats[3].Unk3F,Y
    STA.w BattlerStats[3].Unk3F,Y       ; quirk: the same store again
    PHY
    TDC
    STA.b !BattleFDEnemy_Count
    STA.w BattlerStats[3].Status,Y
    STA.w BattlerStats[3].Status2,Y
    STA.w BattlerStats[3].Unk4C,Y
.copy_4f:
    INX
    LDA.l !BattleRom_EnemyStats,X
    STA.w BattlerStats[3].Unk4C+3,Y
    INY
    INC.b !BattleFDEnemy_Count
    LDA.b !BattleFDEnemy_Count
    CMP.b #!Battle_EnemyRec4FBytes
    BCC .copy_4f
    PLY
    LDA.w BattlerStats[3].Unk4C+6,Y
    STA.w BattlerStats[3].Unk4C+1,Y
    LDA.w BattlerStats[3].Unk4C+7,Y
    STA.w BattlerStats[3].Unk4C+2,Y
    PHY
    TDC
    STA.b !BattleFDEnemy_Count
.copy_64:
    INX
    LDA.l !BattleRom_EnemyStats,X
    STA.w BattlerStats[3].Unk64,Y
    INY
    INC.b !BattleFDEnemy_Count
    LDA.b !BattleFDEnemy_Count
    CMP.b #!Battle_EnemyRec64Bytes
    BCC .copy_64
    PLY
    TDC
    STA.b !BattleFDEnemy_Count
.copy_46:
    INX
    LDA.l !BattleRom_EnemyStats,X
    STA.w BattlerStats[3].Unk46,Y
    INY
    INC.b !BattleFDEnemy_Count
    LDA.b !BattleFDEnemy_Count
    CMP.b #!Battle_EnemyRec46Bytes
    BCC .copy_46
    RTL

; $FD:B4D6 — BattleFD_ZeroStatBlock (17 bytes, $B4D6–$B4E6)
; Zeroes $80 bytes from BattlerStats[3].Unk2D + Y (an enemy's stat block,
; running into the next record's first $2D bytes).
; Callers (1 JSR site): BattleFD_UnkB438 ($FD:B458).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E; Y = enemy entry * $80
; Exit:  M=1, X=0; A = 0 (B too); X, Y preserved (pushed and pulled)
org $FDB4D6
BattleFD_ZeroStatBlock:
    PHX
    PHY
    TDC
    TAX
.zero:
    STA.w BattlerStats[3].Unk2D,Y
    INX
    INY
    CPX.w #!Battle_StatsStride
    BCC .zero
    PLY
    PLX
    RTS

; $FD:B4E7 — BattleFD_UnkB4E7 (110 bytes, $B4E7–$B554)
; Sets the starting values of the turn lists for all 11 slots: the
; reload value (!Battle_ListReload) and the countdown
; (!Battle_ListTimers) of lists 0-11 get the same number per list: 0: 60,
; 1: 150, 2: 90, 3: 110, 4: 90, 5: 60, 6: 60, 7: 60, 8: 30, 9: 25,
; 10: 60, 11: 120; list 12 (the battlers' turns) gets only its reload
; value, 105 (!Battle_AtbBase; the same value BattleFD_UnkB7EB starts
; from).
; Callers (2 JSL sites): Battle_SetupBattle ($C1:FD02) and unmatched ($C1:FE96).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A = 120 (B = 0); X = 11; Y unchanged
org $FDB4E7
BattleFD_UnkB4E7:
    TDC
    TAX
.slot:
    LDA.b #!Battle_List0Time
    STA.w !Battle_ListReload,X
    STA.w !Battle_ListTimers,X
    LDA.b #!Battle_AtbBase
    STA.w !Battle_ListReload+(!Battle_NumSlots*!Battle_TurnList),X
    LDA.b #!Battle_List1Time
    STA.w !Battle_ListReload+(!Battle_NumSlots*1),X
    STA.w !Battle_ListTimers+(!Battle_NumSlots*1),X
    LDA.b #!Battle_List2Time
    STA.w !Battle_ListReload+(!Battle_NumSlots*2),X
    STA.w !Battle_ListTimers+(!Battle_NumSlots*2),X
    LDA.b #!Battle_List6Time
    STA.w !Battle_ListReload+(!Battle_NumSlots*6),X
    STA.w !Battle_ListTimers+(!Battle_NumSlots*6),X
    LDA.b #!Battle_List7Time
    STA.w !Battle_ListReload+(!Battle_NumSlots*7),X
    STA.w !Battle_ListTimers+(!Battle_NumSlots*7),X
    LDA.b #!Battle_List8Time
    STA.w !Battle_ListReload+(!Battle_NumSlots*8),X
    STA.w !Battle_ListTimers+(!Battle_NumSlots*8),X
    LDA.b #!Battle_List4Time
    STA.w !Battle_ListReload+(!Battle_NumSlots*4),X
    STA.w !Battle_ListTimers+(!Battle_NumSlots*4),X
    LDA.b #!Battle_List9Time
    STA.w !Battle_ListReload+(!Battle_NumSlots*9),X
    STA.w !Battle_ListTimers+(!Battle_NumSlots*9),X
    LDA.b #!Battle_List3Time
    STA.w !Battle_ListReload+(!Battle_NumSlots*3),X
    STA.w !Battle_ListTimers+(!Battle_NumSlots*3),X
    LDA.b #!Battle_List5Time
    STA.w !Battle_ListReload+(!Battle_NumSlots*5),X
    STA.w !Battle_ListTimers+(!Battle_NumSlots*5),X
    LDA.b #!Battle_List10Time
    STA.w !Battle_ListReload+(!Battle_NumSlots*10),X
    STA.w !Battle_ListTimers+(!Battle_NumSlots*10),X
    LDA.b #!Battle_List11Time
    STA.w !Battle_ListReload+(!Battle_NumSlots*11),X
    STA.w !Battle_ListTimers+(!Battle_NumSlots*11),X
    INX
    CPX.w #!Battle_NumSlots
    BCC .slot
    RTL

; $FD:B555 — BattleFD_UnkB555 (256 bytes, $B555–$B654)
; One of Battle_SetupBattle's last steps:
;   - zeroes !Battle_UnkAEE6 (17 B), !Battle_UnkB19E (32 B) and the 32
;     bytes from !Enemy_AnimWanted ($5E0D-$5E2C);
;   - BattleFD_UnkB3EB for each PC whose BattlerStats.Unk57 (as copied
;     to !Battle_UnkB3BA) is !Battle_Unk57B3EB ($B3);
;   - for each PC, twice: when its stat block's .Unk4A is 1, record
;     .Unk49 of !BattleRom_UnkCC2A05 (3 B each) is applied: record byte 1
;     is ORed into the byte at the block + record byte 0; the same with
;     .Unk71 / .Unk72.
; What the records stand for is not traced (they set bits in the stat
; block, probably equipment effects).
; Callers (1 JSL site): Battle_SetupBattle ($C1:FD0A).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A, X, Y clobbered
; Callee: BattleFD_UnkB3EB
org $FDB555
BattleFD_UnkB555:
    TDC
    TAX
.clear_aee6:
    STA.w !Battle_UnkAEE6,X
    INX
    CPX.w #!Battle_UnkAEE6Bytes
    BCC .clear_aee6
    TDC
    TAX
.clear_b19e:
    STA.w !Battle_UnkB19E,X
    STA.w !Enemy_AnimWanted,X
    INX
    CPX.w #!Battle_UnkB19EBytes
    BCC .clear_b19e
    LDA.w !Battle_UnkB3BA
    CMP.b #!Battle_Unk57B3EB
    BNE .pc1_b3eb
    LDX.w #0
    JSL BattleFD_UnkB3EB
.pc1_b3eb:
    LDA.w !Battle_UnkB3BA+1
    CMP.b #!Battle_Unk57B3EB
    BNE .pc2_b3eb
    LDX.w #!Battle_StatsStride
    JSL BattleFD_UnkB3EB
.pc2_b3eb:
    LDA.w !Battle_UnkB3BA+2
    CMP.b #!Battle_Unk57B3EB
    BNE .pc0_rec1
    LDX.w #!Battle_StatsStride*2
    JSL BattleFD_UnkB3EB
.pc0_rec1:
    TDC
    LDA.w BattlerStats.Unk2D+PcStatBlk.Unk4A
    CMP.b #1
    BNE .pc1_rec1
    LDA.w BattlerStats.Unk2D+PcStatBlk.Unk49
    ASL A
    CLC
    ADC.w BattlerStats.Unk2D+PcStatBlk.Unk49
    TAX
    LDA.l !BattleRom_UnkCC2A05,X
    TAY
    LDA.w BattlerStats.Unk2D,Y
    ORA.l !BattleRom_UnkCC2A05+1,X
    STA.w BattlerStats.Unk2D,Y
.pc1_rec1:
    LDA.w BattlerStats[1].Unk2D+PcStatBlk.Unk4A
    CMP.b #1
    BNE .pc2_rec1
    LDA.w BattlerStats[1].Unk2D+PcStatBlk.Unk49
    ASL A
    CLC
    ADC.w BattlerStats[1].Unk2D+PcStatBlk.Unk49
    TAX
    LDA.l !BattleRom_UnkCC2A05,X
    TAY
    LDA.w BattlerStats[1].Unk2D,Y
    ORA.l !BattleRom_UnkCC2A05+1,X
    STA.w BattlerStats[1].Unk2D,Y
.pc2_rec1:
    LDA.w BattlerStats[2].Unk2D+PcStatBlk.Unk4A
    CMP.b #1
    BNE .pc0_rec2
    LDA.w BattlerStats[2].Unk2D+PcStatBlk.Unk49
    ASL A
    CLC
    ADC.w BattlerStats[2].Unk2D+PcStatBlk.Unk49
    TAX
    LDA.l !BattleRom_UnkCC2A05,X
    TAY
    LDA.w BattlerStats[2].Unk2D,Y
    ORA.l !BattleRom_UnkCC2A05+1,X
    STA.w BattlerStats[2].Unk2D,Y
.pc0_rec2:
    TDC
    LDA.w BattlerStats.Unk2D+PcStatBlk.Unk72
    CMP.b #1
    BNE .pc1_rec2
    LDA.w BattlerStats.Unk2D+PcStatBlk.Unk71
    ASL A
    CLC
    ADC.w BattlerStats.Unk2D+PcStatBlk.Unk71
    TAX
    LDA.l !BattleRom_UnkCC2A05,X
    TAY
    LDA.w BattlerStats.Unk2D,Y
    ORA.l !BattleRom_UnkCC2A05+1,X
    STA.w BattlerStats.Unk2D,Y
.pc1_rec2:
    LDA.w BattlerStats[1].Unk2D+PcStatBlk.Unk72
    CMP.b #1
    BNE .pc2_rec2
    LDA.w BattlerStats[1].Unk2D+PcStatBlk.Unk71
    ASL A
    CLC
    ADC.w BattlerStats[1].Unk2D+PcStatBlk.Unk71
    TAX
    LDA.l !BattleRom_UnkCC2A05,X
    TAY
    LDA.w BattlerStats[1].Unk2D,Y
    ORA.l !BattleRom_UnkCC2A05+1,X
    STA.w BattlerStats[1].Unk2D,Y
.pc2_rec2:
    LDA.w BattlerStats[2].Unk2D+PcStatBlk.Unk72
    CMP.b #1
    BNE .done
    LDA.w BattlerStats[2].Unk2D+PcStatBlk.Unk71
    ASL A
    CLC
    ADC.w BattlerStats[2].Unk2D+PcStatBlk.Unk71
    TAX
    LDA.l !BattleRom_UnkCC2A05,X
    TAY
    LDA.w BattlerStats[2].Unk2D,Y
    ORA.l !BattleRom_UnkCC2A05+1,X
    STA.w BattlerStats[2].Unk2D,Y
.done:
    RTL

; $FD:B655 — BattleFD_UnkB655 (221 bytes, $B655–$B731)
; Puts item DP $06 in the 4-byte record of slot !Battle_UnkB18B in
; !Battle_PcItem (8 B per slot) when it is an item the battle list takes
; (as BattleFD_AddItemEntry: id $BC or more with bit 7 of its
; !BattleRom_ItemUseFlags byte): .Id = the id, .TargetMode from
; !BattleRom_ItemTargetMode, .Flags = that byte without bit 7, .Quantity
; = 1; then sets !Battle_UnkB3BF bit 1. Otherwise the item goes back to
; the inventory (BankC1_AddItemLong with Y = the id). !Battle_UnkAF23 is
; 0 at the end either way. Probably what happens to an item a PC uses up
; or takes (not traced).
; Quirk: as in BattleFD_AddItemEntry, ids below $5A branch to the same
; place as the others, so the code at $B67F-$B6CA is never run (it
; would fill the record from !BattleRom_UnkCC06A7 like the dead part of
; BattleFD_AddItemEntry).
; Callers (1 JSL site): BattleSys_StealItem ($C1:EA5D).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $06 = item id; !Battle_UnkB18B = slot
;        (its TAX takes B = 0 from the TDC at the start)
; Exit:  M=1, X=0; A, X, Y clobbered; DP $00, $02, $04, $08, $0A written;
;        !Battle_UnkAF23 = 0; !Battle_MathA..MathHi as Battle_Mul16 leaves
;        them; what BankC1_AddItem changes
; Callees: Battle_Mul16Long, BankC1_AddItemLong
!BattleFDPcItem_Rec = !BattleTmp_02     ; 2 B: offset of the item's record (id - $BC) * 3
!BattleFDPcItem_Ofs = !BattleTmp_04     ; 2 B: slot * 8
!BattleFDPcItem_Id  = !BattleTmp_06     ; 1 B: the item id (argument)
!BattleFDPcItem_Idx = !BattleTmp_0A     ; 2 B: id - $BC
org $FDB655
BattleFD_UnkB655:
    TDC
    TAX
    STX.b !BattleTmp_00
    STX.b !BattleFDPcItem_Rec
    STX.b !BattleFDPcItem_Ofs
    STX.b !BattleTmp_08
    STX.b !BattleFDPcItem_Idx
    LDA.w !Battle_UnkB18B
    TAX
    STX.b !Battle_MathA
    LDX.w #!Battle_PcItemSize
    STX.b !Battle_MathB
    JSL Battle_Mul16Long
    LDX.b !Battle_MathLo
    STX.b !BattleFDPcItem_Ofs
    STZ.w !Battle_UnkAF23
    LDA.b !BattleFDPcItem_Id
    CMP.b #!Battle_ItemClass1First
    BCS .battle_item
    BRA .battle_item                    ; quirk: the code below is never reached
.dead:
    LDX.b !BattleFDPcItem_Ofs
    STA.w Battle_PcItem.Id,X
    TAX
    STX.b !Battle_MathA
    LDA.b #!BattleRom_UnkCC06A7Size
    TAX
    STX.b !Battle_MathB
    JSL Battle_Mul16Long
    LDX.b !Battle_MathLo
    STX.b !BattleFDPcItem_Rec
    TDC
    TAY
    LDX.b !BattleFDPcItem_Rec
    LDA.l !BattleRom_UnkCC06A7,X
.dead_find_bit:
    BIT.b #!Battle_HighBit
    BNE .dead_found
    ASL A
    INY
    CPY.w #8
    BCC .dead_find_bit
    TDC
    LDX.b !BattleFDPcItem_Ofs
    STA.w Battle_PcItem.Id,X
    BRA .taken
.dead_found:
    LDA.w !Battle_UnkB1BE,Y
    BMI .dead_flags
    TAX
    LDA.b #!Battle_HighBit
.dead_shift:
    DEX
    BMI .dead_mask
    LSR A
    BRA .dead_shift
.dead_mask:
    LDX.b !BattleFDPcItem_Ofs
    STA.w Battle_PcItem.PcMask,X
.dead_flags:
    LDA.b #!Battle_ItemFlagUnusable
    LDX.b !BattleFDPcItem_Ofs
    STA.w Battle_PcItem.Flags,X
    BRA .quantity
.battle_item:
    LDA.b !BattleFDPcItem_Id
    CMP.b #!Battle_ItemClass4First
    BCC .not_taken
    LDA.b !BattleFDPcItem_Id
    SEC
    SBC.b #!Battle_ItemClass4First
    TAX
    STX.b !BattleFDPcItem_Idx
    ASL A
    CLC
    ADC.b !BattleFDPcItem_Idx
    TAX
    STX.b !BattleFDPcItem_Rec
    LDX.b !BattleFDPcItem_Rec
    LDA.l !BattleRom_ItemUseFlags,X
    BIT.b #!Battle_ItemListBit
    BEQ .not_taken
    LDA.b !BattleFDPcItem_Id
    LDX.b !BattleFDPcItem_Ofs
    STA.w Battle_PcItem.Id,X
    LDX.b !BattleFDPcItem_Idx
    LDA.l !BattleRom_ItemTargetMode,X
    LDX.b !BattleFDPcItem_Ofs
    STA.w Battle_PcItem.TargetMode,X
    LDX.b !BattleFDPcItem_Rec
    LDA.l !BattleRom_ItemUseFlags,X
    AND.b #!Battle_ItemListBit^$FF
    LDX.b !BattleFDPcItem_Ofs
    STA.w Battle_PcItem.Flags,X
.quantity:
    LDA.b #1
    LDX.b !BattleFDPcItem_Ofs
    STA.w Battle_PcItem.Quantity,X
.taken:
    LDA.w !Battle_UnkB3BF
    ORA.b #!Battle_B3BFPcItemBit
    STA.w !Battle_UnkB3BF
    BRA .clear_af23
.not_taken:
    INC.w !Battle_UnkAF23
    BRA .check_af23
.clear_af23:
    STZ.w !Battle_UnkAF23
.check_af23:
    LDA.w !Battle_UnkAF23
    BEQ .done
    LDA.b !BattleFDPcItem_Id
    TAY
    JSL BankC1_AddItemLong
    STZ.w !Battle_UnkAF23
.done:
    RTL

; $FD:B732 — BattleFD_UnkB732 (185 bytes, $B732–$B7EA)
; Clears the battle's per-battle state (Battle_SetupBattle):
;   - DP $16-$21 and !Battle_UnkAF25 (16-bit) = 0; !Battle_UnkB1FC,
;     !Battle_UnkB253, !Battle_UnkAECB, !Battle_UnkB2C0, !Battle_UnkB3B9 = 0;
;   - the reward state: !Battle_UnkB28C, !Battle_RewardGold, the 24-bit
;     !Battle_UnkB2DB/B2DD, !Battle_UnkB2AF, !Battle_UnkB2B0-B2B5 and the
;     6 !Battle_RewardItems = 0;
;   - the $30 bytes from !Battle_UnkB18E ($B18E-$B1BD) = 0;
;   - !Battle_UnkAECC and !Battle_UnkAED8 (11 B each) = $FF;
;   - !Battle_UnkAEB2 = 0, and per enemy !Battle_UnkB2B6, !Battle_UnkAEB3,
;     !Battle_UnkAE85, !Battle_UnkB320, !Battle_UnkAE7D = 0;
;   - !Battle_UnkB202 = 0; !Battle_UnkB3CE (24 B) = $FF; !Battle_UnkB30F,
;     !Battle_UnkB310 = 0; !Battle_UnkB3BE = 3;
;   - !Battle_UnkB263 and !Battle_UnkB26B (8 B each) = $FF;
;   - BattleCmd[0..2].Partners = $FF.
; Quirk: !Battle_UnkB263 is zeroed by an earlier loop and then set to
; $FF by the last one; !Battle_UnkB26B gets $FF both times.
; Callers (1 JSL site): Battle_SetupBattle ($C1:FD0E).
; Entry: M=1, X=0, DP=0 (TDC as zero; .b stores), DB=$7E
; Exit:  M=1, X=0; A = $FF (B = 0); X = 8; Y unchanged
org $FDB732
BattleFD_UnkB732:
    TDC
    TAX
    STX.b !BattleTmp_16
    STX.b !BattleTmp_18
    STX.b !BattleTmp_1A
    STX.b !BattleTmp_1C
    STX.b !BattleTmp_1E
    STX.b !BattleTmp_20
    STX.w !Battle_UnkAF25
    STA.w !Battle_UnkB1FC
    STA.w !Battle_UnkB253
    STA.w !Battle_UnkAECB
    STA.w !Battle_UnkB2C0
    STA.w !Battle_UnkB3B9
    STX.w !Battle_UnkB28C
    STX.w !Battle_RewardGold
    STX.w !Battle_UnkB2DB
    STA.w !Battle_UnkB2DD
    STA.w !Battle_UnkB2AF
    STX.w !Battle_UnkB2B0
    STX.w !Battle_UnkB2B0+2
    STX.w !Battle_UnkB2B0+4
.clear_b18e:
    STA.w !Battle_UnkB18E,X
    INX
    CPX.w #!Battle_UnkB18EBytes
    BCC .clear_b18e
    TAX
.clear_rewards:
    STA.w !Battle_RewardItems,X
    INX
    CPX.w #!Battle_NumRewardItems
    BCC .clear_rewards
    TAX
    LDA.b #!Battle_EntryNone
.clear_b263:
    STZ.w !Battle_UnkB263,X
    STA.w !Battle_UnkB26B,X
    INX
    CPX.w #!Battle_NumEnemies
    BCC .clear_b263
    TDC
    TAX
    LDA.b #!Battle_EntryNone
.fill_aecc:
    STA.w !Battle_UnkAECC,X
    STA.w !Battle_UnkAED8,X
    INX
    CPX.w #!Battle_NumSlots
    BCC .fill_aecc
    TDC
    STA.w !Battle_UnkAEB2
    TAX
.clear_enemy:
    STA.w !Battle_UnkB2B6,X
    STA.w !Battle_UnkAEB3,X
    STA.w !Battle_UnkAE85,X
    STA.w !Battle_UnkB320,X
    STA.w !Battle_UnkAE7D,X
    INX
    CPX.w #!Battle_NumEnemies
    BCC .clear_enemy
    STZ.w !Battle_UnkB202
    TDC
    TAX
    LDA.b #!Battle_EntryNone
.fill_b3ce:
    STA.w !Battle_UnkB3CE,X
    INX
    CPX.w #!Battle_NumPcSlots*8
    BCC .fill_b3ce
    STZ.w !Battle_UnkB30F
    STZ.w !Battle_UnkB310
    LDA.b #!Battle_UnkB3BEInit
    STA.w !Battle_UnkB3BE
    TDC
    TAX
    LDA.b #!Battle_EntryNone
.fill_b263:
    STA.w !Battle_UnkB263,X
    STA.w !Battle_UnkB26B,X
    INX
    CPX.w #!Battle_NumEnemies
    BCC .fill_b263
    STA.w BattleCmd.Partners
    STA.w BattleCmd[1].Partners
    STA.w BattleCmd[2].Partners
    RTL

; $FD:B7EB — BattleFD_UnkB7EB (364 bytes, $B7EB–$B956)
; The battlers' first turn values (Battle_SetupBattle):
;   - each PC with an id in !Battler_UnkAEFF, and each enemy entry below
;     !Battle_EnemyCount with an id in !Battler_UnkAF0A: its stat block's
;     .Unk38 is capped at 16; v = !BattleRom_UnkCC2E31[(!Menu_Config bits
;     0-2) * 16 + .Unk38 - 1]; !Battle_ListReload of list 12 and
;     !Battler_UnkAFAB = 105 - .Unk38 * 6 + v (8-bit). A PC's list-12 flag
;     (!Battle_ListFlags) is set to 1; an enemy's only when its
;     !Battler_UnkAEFF entry is not empty. An enemy whose block .Unk0A
;     bit 0 is set gets !Battle_UnkAF15 bit 6 (!Battle_AF15NotCounted).
;   - then the lowest non-zero !Battler_UnkAFAB of a present slot (slot
;     0 counts whatever it holds, see below) less 1 is taken off every
;     present non-zero !Battler_UnkAFAB, so the first battler due has 1;
;   - !Pc_AtbCur and !Pc_AtbMax of the 3 PCs = their !Battler_UnkAFAB.
; The 8-bit STA of .Unk38 to !Battle_MathA leaves its high byte 0 from
; the multiply before (Battle_Mul16 keeps MathA).
; So .Unk38 probably is the speed stat and !Menu_Config bits 0-2 the
; battle speed setting (a larger .Unk38 gives a smaller first value); not
; traced further.
; Quirk: the search for the lowest value starts from slot 0's without
; checking that slot 0 is present or non-zero; an absent PC 0 holds $FF
; there (Battle_SetupBattle), which does not change the result.
; Callers (1 JSL site): Battle_SetupBattle ($C1:FD06).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A = !Battler_UnkAFAB+2; X = 11; Y = the slot with the
;        lowest value; DP $00 = that value - 1, $02 = !Battle_EnemyCount
;        (at least 1: the enemy loop runs once before its test), $04
;        written;
;        !Battle_MathA..MathHi as Battle_Mul16 leaves them
; Callee: Battle_Mul16Long
!BattleFDAtb_Add   = !BattleTmp_00      ; 1 B: the table value v; then the amount taken off
!BattleFDAtb_Slot  = !BattleTmp_02      ; 2 B: PC slot, then enemy entry
!BattleFDAtb_Block = !BattleTmp_04      ; 2 B: its stat block
org $FDB7EB
BattleFD_UnkB7EB:
    TDC
    TAX
    STX.b !BattleFDAtb_Slot
.pc:
    LDX.b !BattleFDAtb_Slot
    LDA.w !Battler_UnkAEFF,X
    CMP.b #!Battle_EntryNone
    BEQ .pc_next
    REP #$20
    TXA
    ASL A
    TAX
    LDA.l !BattleRom_PcStatBlock,X
    TAX
    STX.b !BattleFDAtb_Block
    TDC
    SEP #$20
    LDA.w PcStatBlk.Unk38,X
    CMP.b #!Battle_StatCap16
    BCC .pc_capped
    LDA.b #!Battle_StatCap16
    STA.w PcStatBlk.Unk38,X
.pc_capped:
    TDC
    LDA.w !Menu_Config
    AND.b #!Battle_ConfigSpeedMask
    TAX
    STX.b !Battle_MathA
    LDX.w #!Battle_AtbTableRow
    STX.b !Battle_MathB
    JSL Battle_Mul16Long
    LDX.b !BattleFDAtb_Block
    LDA.w PcStatBlk.Unk38,X
    DEC A
    CLC
    ADC.b !Battle_MathLo
    TAX
    LDA.l !BattleRom_UnkCC2E31,X
    STA.b !BattleFDAtb_Add
    LDX.b !BattleFDAtb_Block
    LDA.w PcStatBlk.Unk38,X
    TAX
    STA.b !Battle_MathA
    LDA.b #!Battle_AtbStepPerUnk38
    TAX
    STX.b !Battle_MathB
    JSL Battle_Mul16Long
    LDA.b #!Battle_AtbBase
    SEC
    SBC.b !Battle_MathLo
    CLC
    ADC.b !BattleFDAtb_Add
    LDX.b !BattleFDAtb_Slot
    STA.w !Battle_ListReload+(!Battle_NumSlots*!Battle_TurnList),X
    STA.w !Battler_UnkAFAB,X
    LDA.b #1
    STA.w !Battle_ListFlags+(!Battle_NumSlots*!Battle_TurnList),X
.pc_next:
    INC.b !BattleFDAtb_Slot
    LDA.b !BattleFDAtb_Slot
    CMP.b #!Battle_NumPcSlots
    BCC .pc
    TDC
    TAX
    STX.b !BattleFDAtb_Slot
.enemy:
    LDX.b !BattleFDAtb_Slot
    LDA.w !Battler_UnkAF0A+!Battle_FirstEnemySlot,X
    CMP.b #!Battle_EntryNone
    BEQ .enemy_next
    REP #$20
    TXA
    ASL A
    TAX
    LDA.l !BattleRom_PcStatBlock+(!Battle_FirstEnemySlot*2),X
    TAX
    STX.b !BattleFDAtb_Block
    TDC
    SEP #$20
    LDA.w PcStatBlk.Unk38,X
    CMP.b #!Battle_StatCap16
    BCC .enemy_capped
    LDA.b #!Battle_StatCap16
    STA.w PcStatBlk.Unk38,X
.enemy_capped:
    TDC
    LDA.w !Menu_Config
    AND.b #!Battle_ConfigSpeedMask
    TAX
    STX.b !Battle_MathA
    LDX.w #!Battle_AtbTableRow
    STX.b !Battle_MathB
    JSL Battle_Mul16Long
    LDX.b !BattleFDAtb_Block
    LDA.w PcStatBlk.Unk38,X
    DEC A
    CLC
    ADC.b !Battle_MathLo
    TAX
    LDA.l !BattleRom_UnkCC2E31,X
    STA.b !BattleFDAtb_Add
    LDX.b !BattleFDAtb_Block
    LDA.w PcStatBlk.Unk0A,X
    BIT.b #!Battle_Unk0ANotCountedBit
    BEQ .counted
    LDY.b !BattleFDAtb_Slot
    LDA.w !Battle_UnkAF15,Y
    ORA.b #!Battle_AF15NotCounted
    STA.w !Battle_UnkAF15,Y
.counted:
    TDC
    LDA.w PcStatBlk.Unk38,X
    TAX
    STX.b !Battle_MathA
    LDA.b #!Battle_AtbStepPerUnk38
    TAX
    STX.b !Battle_MathB
    JSL Battle_Mul16Long
    LDA.b #!Battle_AtbBase
    SEC
    SBC.b !Battle_MathLo
    CLC
    ADC.b !BattleFDAtb_Add
    LDX.b !BattleFDAtb_Slot
    STA.w !Battle_ListReload+(!Battle_NumSlots*!Battle_TurnList)+!Battle_FirstEnemySlot,X
    STA.w !Battler_UnkAFAB+!Battle_FirstEnemySlot,X
    LDA.w !Battler_UnkAEFF+!Battle_FirstEnemySlot,X
    CMP.b #!Battle_EntryNone
    BEQ .enemy_next
    LDA.b #1
    STA.w !Battle_ListFlags+(!Battle_NumSlots*!Battle_TurnList)+!Battle_FirstEnemySlot,X
.enemy_next:
    INC.b !BattleFDAtb_Slot
    LDA.b !BattleFDAtb_Slot
    CMP.w !Battle_EnemyCount
    BCS .lowest
    JMP .enemy
.lowest:
    TDC
    TAX
    TAY
    STX.b !BattleFDAtb_Add
    LDA.w !Battler_UnkAFAB
.lowest_slot:
    INX
    CMP.w !Battler_UnkAFAB,X
    BCC .lowest_next
    LDA.w !Battler_UnkAFAB,X
    BEQ .lowest_keep
    LDA.w !Battler_UnkAEFF,X
    CMP.b #!Battle_EntryNone
    BEQ .lowest_keep
    TXY
.lowest_keep:
    LDA.w !Battler_UnkAFAB,Y
.lowest_next:
    CPX.w #!Battle_NumSlots-1
    BCC .lowest_slot
    LDA.w !Battler_UnkAFAB,Y
    DEC A
    STA.b !BattleFDAtb_Add
    TDC
    TAX
.shift:
    LDA.w !Battler_UnkAEFF,X
    CMP.b #!Battle_EntryNone
    BEQ .shift_next
    LDA.w !Battler_UnkAFAB,X
    BEQ .shift_next
    SEC
    SBC.b !BattleFDAtb_Add
    STA.w !Battler_UnkAFAB,X
.shift_next:
    INX
    CPX.w #!Battle_NumSlots
    BCC .shift
    LDA.w !Battler_UnkAFAB
    STA.w !Pc_AtbCur
    STA.w !Pc_AtbMax
    LDA.w !Battler_UnkAFAB+1
    STA.w !Pc_AtbCur+1
    STA.w !Pc_AtbMax+1
    LDA.w !Battler_UnkAFAB+2
    STA.w !Pc_AtbCur+2
    STA.w !Pc_AtbMax+2
    RTL

; ============================================================
; $FD:BA61 — RandomTableFD (256 bytes, $FD:BA61–$BB60)
; A byte-identical copy of RandomTable ($C0:FE00): the same shuffle of
; 0-255. Read with LDA.l $FDBA61,X by battle code in bank $C1: at
; $C1:AF56/AF60 in Battle_RandRange and at $C1:AFAE/AFB8 in
; Battle_RandRangeAlt, two copies of a roll that take X from a counter
; (!Battle_RandIdx in the first, !Battle_UnkB3E6 in the second). When the range is $FF they use
; the entry as is (the reads at $AF56/$AFAE) and leave the counter alone;
; otherwise they step the counter and reduce the entry with Battle_Div32,
; using the remainder plus !Battle_RandMin (entry mod range, plus the low
; bound). The second copy's one caller is BattleSys_HitModChanceMul's
; roll against the caster's .Unk72. The 6 bytes
; after the table
; ($FD:BB61–$BB66) repeat its last 6 entries; nothing reads them that
; xref finds, and they are left unmatched.
; ============================================================
org $FDBA61

RandomTableFD:
    db $B1,$CA,$EE,$6C,$5A,$71,$2E,$55,$D6,$00,$CC,$99,$90,$6B,$7D,$EB ; $00
    db $4F,$A0,$07,$AC,$DF,$8A,$56,$9E,$F1,$9A,$63,$75,$11,$91,$A3,$B8 ; $10
    db $94,$73,$F7,$54,$D9,$6E,$72,$C0,$F4,$80,$DE,$B9,$BB,$8D,$66,$26 ; $20
    db $D0,$36,$E1,$E9,$70,$DC,$CD,$2F,$4A,$67,$5D,$D2,$60,$B5,$9D,$7F ; $30
    db $45,$37,$50,$44,$78,$04,$19,$2C,$EF,$FD,$64,$81,$03,$DA,$95,$4C ; $40
    db $7A,$0B,$AD,$1F,$BA,$DD,$3E,$F9,$D7,$1A,$29,$F8,$18,$B3,$20,$F6 ; $50
    db $D1,$5E,$34,$92,$7B,$24,$43,$88,$97,$D4,$0F,$35,$AA,$83,$68,$27 ; $60
    db $A8,$D5,$BE,$FA,$14,$31,$AF,$10,$0D,$D8,$6A,$CE,$23,$61,$F3,$3D ; $70
    db $A4,$08,$33,$E3,$A9,$38,$E6,$93,$1D,$1C,$F0,$0E,$87,$59,$65,$82 ; $80
    db $BC,$FF,$FE,$7E,$8F,$C1,$1E,$F5,$CB,$49,$02,$32,$09,$C4,$8E,$C6 ; $90
    db $2B,$40,$A7,$17,$76,$3B,$16,$2A,$C8,$FB,$B2,$58,$A5,$15,$AE,$25 ; $A0
    db $CF,$46,$C7,$48,$B4,$0A,$3F,$C9,$06,$85,$51,$89,$62,$4D,$12,$8C ; $B0
    db $EA,$A2,$98,$4B,$79,$6F,$5C,$47,$30,$1B,$E7,$C5,$22,$9C,$E8,$96 ; $C0
    db $3A,$E4,$7C,$E0,$69,$A1,$B7,$05,$39,$74,$01,$9F,$BD,$C3,$84,$FC ; $D0
    db $77,$86,$13,$4E,$BF,$F2,$53,$5B,$ED,$21,$8B,$6D,$C2,$41,$B6,$DB ; $E0
    db $3C,$D3,$28,$EC,$2D,$E2,$9B,$A6,$42,$52,$57,$5F,$E5,$AB,$B0,$0C ; $F0

; ============================================================
; MainInit ($FD:C000)
; Called via: JML from Reset ($00:FF03), which also carries the soft
; resets, and JML $FDC000 at $C0:418D (Evt_OpFF96_Reset, after JSR
; InitHW and S=$06FF). The bytes at $FD:851D read as JSR $C000 but sit in a block of
; packed data ($FD:8480 onwards does not decode as code), not a caller.
; Callers (3 sites: 1 JSR, 2 JML): Evt_OpFF96_Reset (JML $C0:418D), Reset (JML $C0:FF03) and
;   unmatched (JSR $FD:851D).
; Entry: native mode; from a hardware reset M=1 X=1, D=$0000, DB=$00;
;        from $C0:418D M=1, X=0, DB=$00. Steps 1-3 set M, X, S, DB and DP,
;        so nothing else about the entry state matters
; Exit:  (jumps, never returns) M=1 X=0, D=$2100, DB=$00, S=$06FF,
;        screen in forced blank, NMI/IRQ/DMA/HDMA off
;
; Every register write goes through a relocated direct page so each
; store is two bytes: first DP=$4200 for the CPU I/O block, then
; DP=$2100 for the PPU. Most registers are simply zeroed; the non-zero
; register values are named in hardware.inc (the Mode 7 1.0 is a literal).
; ============================================================
org $FDC000

MainInit:

    ; Step 1 — 16-bit index, 8-bit A; S=$06FF (the top of page $06,
    ; growing down); data bank 0; DP onto the CPU I/O registers.
    REP #$10
    SEP #$20
    LDX.w #!StackTop
    TXS
    LDA #$00
    PHA
    PLB
    REP #$20
    LDA.w #!DP_CPU
    TCD
    SEP #$20

    ; Step 2 — FastROM on; NMI, IRQ, auto-joypad, DMA and HDMA off;
    ; multiplier, divider and H/V timers zeroed; I/O port pins high.
    LDA.b #!MEMSEL_FastRom
    STA.b MEMSEL-!DP_CPU
    LDA #$00
    STA.b NMITIMEN-!DP_CPU
    STA.b MDMAEN-!DP_CPU
    STA.b HDMAEN-!DP_CPU
    STA.b WRMPYA-!DP_CPU
    STA.b WRMPYB-!DP_CPU
    STA.b WRDIVL-!DP_CPU
    STA.b WRDIVH-!DP_CPU
    STA.b WRDIVB-!DP_CPU
    STA.b HTIMEL-!DP_CPU
    STA.b HTIMEH-!DP_CPU
    STA.b VTIMEL-!DP_CPU
    STA.b VTIMEH-!DP_CPU
    LDA.b #!WRIO_AllHigh
    STA.b WRIO-!DP_CPU

    ; Step 3 — DP onto the PPU registers; screen off so VRAM, CGRAM and
    ; OAM can be written freely.
    REP #$20
    LDA.w #!DP_PPU
    TCD
    SEP #$20
    LDA.b #FORCED_BLANK
    STA.b INIDISP-!DP_PPU

    ; Step 4 — PPU. Non-zero writes: sprite size/base (OBSEL), BG mode,
    ; the Mode 7 identity matrix (#$01 = 1.0 in the high bytes of A and D),
    ; W34SEL, the layer enables (TM/TS), and COLDATA (written $C0, which
    ; sets green and blue to 0). Everything else (tilemap and character
    ; bases, scroll, VRAM address, color math) starts at 0, presumably to
    ; be set by each scene later.
    LDA.b #!OBSEL_Size16And32_Base6000
    STA.b OBSEL-!DP_PPU
    LDA #$00
    STA.b OAMADDL-!DP_PPU
    STA.b OAMADDH-!DP_PPU
    LDA.b #BG_MODE_1|BG3_HIGH_PRIO
    STA.b BGMODE-!DP_PPU
    LDA #$00
    STA.b MOSAIC-!DP_PPU
    STA.b BG1SC-!DP_PPU
    STA.b BG2SC-!DP_PPU
    STA.b BG3SC-!DP_PPU
    STA.b BG4SC-!DP_PPU
    STA.b BG12NBA-!DP_PPU
    STA.b BG34NBA-!DP_PPU

    ; Scroll registers are write-twice (low byte, then high byte), hence
    ; each pair of stores.
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

    ; VMAIN = 0 is VRAM_INC_1 (step one word after the low byte); VRAM
    ; address $0000.
    STA.b VMAIN-!DP_PPU
    STA.b VMADDL-!DP_PPU
    STA.b VMADDH-!DP_PPU

    ; Mode 7 matrix to identity. Each element is write-twice: the first
    ; store is the low byte, the second the high byte, so A=$0100 (1.0)
    ; and D=$0100, B=C=0, centre (0,0). A is stepped with INC/DEC between
    ; the 0 and 1 high bytes instead of reloading.
    STA.b M7SEL-!DP_PPU
    STA.b M7A-!DP_PPU
    LDA #$01
    STA.b M7A-!DP_PPU
    DEC
    STA.b M7B-!DP_PPU
    STA.b M7B-!DP_PPU
    STA.b M7C-!DP_PPU
    STA.b M7C-!DP_PPU
    STA.b M7D-!DP_PPU
    INC
    STA.b M7D-!DP_PPU
    DEC
    STA.b M7X-!DP_PPU
    STA.b M7X-!DP_PPU
    STA.b M7Y-!DP_PPU
    STA.b M7Y-!DP_PPU

    STA.b CGADD-!DP_PPU

    ; Windows. W34SEL gets BG3 window 1 enable+invert, but no layer has
    ; windowing turned on (TMW = TSW = 0 below), so the setting has no
    ; visible effect yet. Why it is set here is unknown; presumably a
    ; later scene enables BG3 masking and relies on it.
    STA.b W12SEL-!DP_PPU
    LDA.b #!W34SEL_Bg3Win1Inv
    STA.b W34SEL-!DP_PPU
    LDA #$00
    STA.b WOBJSEL-!DP_PPU
    STA.b WH0-!DP_PPU
    STA.b WH1-!DP_PPU
    STA.b WH2-!DP_PPU
    STA.b WH3-!DP_PPU
    STA.b WBGLOG-!DP_PPU
    STA.b WOBJLOG-!DP_PPU
    STA.b TMW-!DP_PPU
    STA.b TSW-!DP_PPU

    ; Color math off.
    STA.b CGWSEL-!DP_PPU
    STA.b CGADSUB-!DP_PPU

    ; Layer enables: all BGs and sprites on, main and sub screen
    ; (overridden per scene).
    LDA.b #!TM_AllLayers
    STA.b TM-!DP_PPU
    STA.b TS-!DP_PPU

    ; Fixed color: green and blue set to 0. Red is not written here and
    ; keeps whatever value it had.
    LDA.b #!COLDATA_GreenBlueZero
    STA.b COLDATA-!DP_PPU

    ; No interlace, overscan or external sync.
    LDA #$00
    STA.b SETINI-!DP_PPU

    ; Step 5 — into the engine.
    JML GameLoop        ; $C0:000E (see the open question on this label in STATUS.md)

; ============================================================
; $FD:C0D7 — Ppu_SetBgLayout (77 bytes, $FD:C0D7–$C123)
; Sets a fixed background layout through DP=$2100, the way MainInit
; writes the PPU: mode 1 with BG3 on top, BG1/BG2 tiles at VRAM word
; $1000 and BG3 tiles at $5000, 64x32 maps at $6800 (BG1), $7000 (BG2)
; and $7800 (BG3), OBSEL and SETINI 0, the BG1-BG3 scroll registers 0
; (24 bytes the same as MainInit's scroll clears), BG1, BG2 and OBJ on
; the main screen, color math adding the sub screen, and the fixed color
; black. What the layout is used for is not traced.
; Callers (1 JSL site): LocLoad_DrawMap ($C0:0A5D).
; Callers note: JSL from $C0:0A5D (unmatched; in a routine at $C0:0A50,
;   called by JSR from $C0:286F, that
;   runs a DP=$1D00 step first and more setup after).
; Entry: M=1 (8-bit A; the immediates are 8-bit), X either width, DP any
;        (saved and restored), DB any (all stores are direct page)
; Exit:  M=1, DP restored, DB unchanged; A = COLDATA_AllZero ($E0); X, Y
;        unchanged
; No calls.
org $FDC0D7
Ppu_SetBgLayout:
    PHD
    REP #$20                ; A → 16-bit
    LDA.w #!DP_PPU
    TCD                     ; DP = $2100: two-byte register stores
    SEP #$20                ; A → 8-bit
    LDA.b #BG_MODE_1|BG3_HIGH_PRIO
    STA.b BGMODE-!DP_PPU
    LDA.b #!BG12NBA_Both1000
    STA.b BG12NBA-!DP_PPU
    LDA.b #!BG34NBA_Bg3At5000
    STA.b BG34NBA-!DP_PPU
    LDA.b #!BG1SC_6800_64x32
    STA.b BG1SC-!DP_PPU
    LDA.b #!BG2SC_7000_64x32
    STA.b BG2SC-!DP_PPU
    LDA.b #!BG3SC_7800_64x32
    STA.b BG3SC-!DP_PPU
    LDA.b #$00
    STA.b OBSEL-!DP_PPU
    STA.b SETINI-!DP_PPU
    ; Scroll registers are write-twice (low byte, then high byte).
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
    LDA.b #!TM_Bg1Bg2Obj
    STA.b TM-!DP_PPU
    LDA.b #!CGWSEL_AddSubscreen
    STA.b CGWSEL-!DP_PPU
    LDA.b #!COLDATA_AllZero
    STA.b COLDATA-!DP_PPU
    PLD
    RTL

; ============================================================
; Field HDMA set-up ($FD:C124–$FD:C2DE, $FD:D52D–$FD:D5D3)
; The field engine's HDMA: Hdma_InitChannelsFD points the 8 channels at
; their registers and at one of two sets of indirect tables in bank $7F
; ($7F:0F80 or $7F:1238, $57 bytes per channel); EngFD_UnkC124 fills
; the data block at $7F:14F0-$16FF that such tables point into, and
; EngFD_UnkC2C1 runs one per-frame builder each frame. Called by the
; field code in bank $C0 with DP=$0100 (!DP_Field) and DB=$00.
; ============================================================

; $FD:C124 — EngFD_UnkC124 (202 bytes, $C124–$C1ED)
; Fills the HDMA data block in bank $7F (DB = $7F while it runs). By the
; registers Hdma_InitChannelsFD gives each channel, the bytes are
; probably:
;   - $14F0-$14F3: BG1SC-BG4SC values (channel 0): the high bytes of
;     !Map_TilemapVram, !Map_TilemapVram3 and !Map_TilemapVramL3 ORed with
;     !Map_TilemapVram4, !Map_TilemapVram4Hi and !Map_Unk1D86, then 0;
;     $14F4-$14F7 a second such record: $1C, !Map_TilemapVram3's high
;     byte | 1, $1C, 0 (the same order FieldBtlPpu.Tilemap1-3 keeps);
;   - $14F8-$1507: four (16-bit, 16-bit) pairs, probably layer scroll
;     values for channels 1-3: (0, $37), (0, -$0F), (0, -$44), (0, -$8A);
;   - $1520-$1523: TM, TS (!Ppu_Unk0BD7 / Ppu_Unk0BD8), TMW, TSW = 0
;     (channel 4); $1524-$1527 = 5, 0, 0, 0 and $1528-$152B = 1, 0, 0, 0;
;   - $1531 and $1533 (COLDATA bytes of channel 6's pairs) = $E0, the
;     words $1534 and $1536 (WH0/WH1 pairs of channel 5) = $FF00, i.e.
;     WH0 = 0 and WH1 = $FF;
;   - then EngFD_UnkD52D builds the $B4-byte table at $7F:1538 and
;     copies $100 bytes from there to $7F:1600.
; !Field_Unk27 is zeroed. Which of these records the indirect tables use
; is not traced; the register reading rests on Hdma_InitChannelsFD.
; Callers (1 JSL site): Scene_ResumeNmi ($C0:0B28).
; Entry: M=1, X any (EngFD_UnkD52D sets it), DP=$0100 (.b store to
;        !Field_Unk27), DB any (saved; set to $7F, restored)
; Exit:  M=1, X=0; A = $FF (B = $FF, the MVN count left); X = $1638,
;        Y = $1700; DB restored; DP $DB-$E1 written (EngFD_UnkD52D)
; Callee: EngFD_UnkD52D
org $FDC124
EngFD_UnkC124:
    PHB
    LDA.b #!Bank7F
    PHA
    PLB
    LDA.l !Map_TilemapVram+1
    ORA.l !Map_TilemapVram4
    STA.w !Hdma_Unk7F14F0
    LDA.l !Map_TilemapVram3+1
    ORA.l !Map_TilemapVram4Hi
    STA.w !Hdma_Unk7F14F1
    LDA.l !Map_TilemapVramL3+1
    ORA.l !Map_Unk1D86
    STA.w !Hdma_Unk7F14F0+2
    LDA.b #0
    STA.w !Hdma_Unk7F14F0+3
    LDA.b #!Hdma_ScRecord2Unk
    STA.w !Hdma_Unk7F14F4
    LDA.l !Map_TilemapVram3+1
    ORA.b #1
    STA.w !Hdma_Unk7F14F4+1
    LDA.b #!Hdma_ScRecord2Unk
    STA.w !Hdma_Unk7F14F4+2
    LDA.b #0
    STA.l !Hdma_Unk7F14F4+3
    REP #$20
    LDA.w #0
    STA.w !Hdma_Unk7F14F8
    LDA.w #!Hdma_ScrollPair0
    STA.w !Hdma_Unk7F14F8+2
    LDA.w #0
    STA.w !Hdma_Unk7F14F8+4
    LDA.w #!Hdma_ScrollPair1
    STA.w !Hdma_Unk7F14F8+6
    LDA.w #0
    STA.w !Hdma_Unk7F14F8+8
    LDA.w #!Hdma_ScrollPair2
    STA.w !Hdma_Unk7F14F8+10
    LDA.w #0
    STA.w !Hdma_Unk7F14F8+12
    LDA.w #!Hdma_ScrollPair3
    STA.w !Hdma_Unk7F14F8+14
    LDA.w #!Hdma_WhWholeLine
    STA.w !Hdma_Unk7F1534
    STA.w !Hdma_Unk7F1534+2
    SEP #$20
    LDA.b #!COLDATA_AllZero
    STA.w !Hdma_Unk7F1530+1
    STA.w !Hdma_Unk7F1530+3
    LDA.l !Ppu_Unk0BD7
    STA.w !Hdma_Unk7F1520
    LDA.l !Ppu_Unk0BD8
    STA.w !Hdma_Unk7F1521
    LDA.b #0
    STA.w !Hdma_Unk7F1522
    STA.w !Hdma_Unk7F1523
    LDA.b #5
    STA.w !Hdma_Unk7F1524
    LDA.b #0
    STA.w !Hdma_Unk7F1524+1
    LDA.b #0
    STA.w !Hdma_Unk7F1524+2
    STA.w !Hdma_Unk7F1524+3
    LDA.b #1
    STA.w !Hdma_Unk7F1528
    LDA.b #0
    STA.w !Hdma_Unk7F1528+1
    LDA.b #0
    STA.w !Hdma_Unk7F1528+2
    STA.w !Hdma_Unk7F1528+3
    STZ.b !Field_Unk27
    JSR EngFD_UnkD52D
    PLB
    RTL

; $FD:C1EE — Hdma_InitChannelsFD (211 bytes, $C1EE–$C2C0)
; Sets up all 8 HDMA channels through DP=$4300 (saved and restored):
;   channel 0: indirect, 4 registers from BG1SC (BG1SC-BG4SC);
;   channels 1-3: indirect, 2 registers written twice, from BG1HOFS,
;     BG2HOFS, BG3HOFS (each layer's H and V scroll);
;   channel 4: indirect, 4 registers from TM (TM, TS, TMW, TSW);
;   channel 5: indirect, 2 registers from WH0 (WH0, WH1);
;   channel 6: indirect, 2 registers from CGADSUB (CGADSUB, COLDATA);
;   channel 7: indirect, 1 register: WH2, or WH3 when !WinFx_Size bit 0
;     is set.
; Table and indirect-data banks are $7F for all eight. The table
; addresses are the set at $7F:0F80 when !Field_Unk53 bits 0-3 are all
; clear, else the set at $7F:1238; each set holds one $57-byte table per
; channel. Which channels run is up to !Field_HdmaEnable (the NMI writes
; HDMAEN).
; Callers (10 JSL sites): Field_RestoreState ($C0:01B0), Field_RefreshHdmaLong ($C0:0B1F),
;   Scene_ResumeNmi ($C0:0B34) and NmiHandler ($C0:EAEF, $C0:EB0F, $C0:EB26, $C0:EB3D, $C0:EB51,
;   $C0:EB65, $C0:EC0F).
; Entry: M=1, X=0 (16-bit table addresses), DP any (saved), DB=$00 (reads
;        !DP_Field+!WinFx_Size and +!Field_Unk53 absolute)
; Exit:  M=1, X=0; DP restored; A clobbered; X = the channel 7 table
;        address; Y unchanged
org $FDC1EE
Hdma_InitChannelsFD:
    PHD
    REP #$20
    LDA.w #!DP_DMA
    TCD
    SEP #$20
    LDA.b #!DMAP_HdmaIndirect|!DMAP_FourRegs
    STA.b DMAP0-!DP_DMA
    LDA.b #!DMAP_HdmaIndirect|!DMAP_TwoRegsTwice
    STA.b DMAP1-!DP_DMA
    LDA.b #!DMAP_HdmaIndirect|!DMAP_TwoRegsTwice
    STA.b DMAP2-!DP_DMA
    LDA.b #!DMAP_HdmaIndirect|!DMAP_TwoRegsTwice
    STA.b DMAP3-!DP_DMA
    LDA.b #!DMAP_HdmaIndirect|!DMAP_FourRegs
    STA.b DMAP4-!DP_DMA
    LDA.b #!DMAP_HdmaIndirect|!DMAP_TwoRegs
    STA.b DMAP5-!DP_DMA
    LDA.b #!DMAP_HdmaIndirect|!DMAP_TwoRegs
    STA.b DMAP6-!DP_DMA
    LDA.b #!DMAP_HdmaIndirect
    STA.b DMAP7-!DP_DMA
    LDA.b #!BBAD_BG1SC
    STA.b BBAD0-!DP_DMA
    LDA.b #!BBAD_BG1HOFS
    STA.b BBAD1-!DP_DMA
    LDA.b #!BBAD_BG2HOFS
    STA.b BBAD2-!DP_DMA
    LDA.b #!BBAD_BG3HOFS
    STA.b BBAD3-!DP_DMA
    LDA.b #!BBAD_TM
    STA.b BBAD4-!DP_DMA
    LDA.b #!BBAD_WH0
    STA.b BBAD5-!DP_DMA
    LDA.b #!BBAD_CGADSUB
    STA.b BBAD6-!DP_DMA
    LDA.w !DP_Field+!WinFx_Size
    BIT.b #1
    BNE .wh3
    LDA.b #!BBAD_WH2
    BRA .set_ch7
.wh3:
    LDA.b #!BBAD_WH3
.set_ch7:
    STA.b BBAD7-!DP_DMA
    LDA.b #!Bank7F
    STA.b A1B0-!DP_DMA
    STA.b A1B1-!DP_DMA
    STA.b A1B2-!DP_DMA
    STA.b A1B3-!DP_DMA
    STA.b A1B4-!DP_DMA
    STA.b A1B5-!DP_DMA
    STA.b A1B6-!DP_DMA
    STA.b A1B7-!DP_DMA
    STA.b DAS0B-!DP_DMA
    STA.b DAS1B-!DP_DMA
    STA.b DAS2B-!DP_DMA
    STA.b DAS3B-!DP_DMA
    STA.b DAS4B-!DP_DMA
    STA.b DAS5B-!DP_DMA
    STA.b DAS6B-!DP_DMA
    STA.b DAS7B-!DP_DMA
    LDA.w !DP_Field+!Field_Unk53
    AND.b #!Field_Unk53HdmaSetMask
    BEQ .set_a
    BRA .set_b
.set_a:
    LDX.w #!Hdma_TableSetA
    STX.b A1T0L-!DP_DMA
    LDX.w #!Hdma_TableSetA+(!Hdma_TableBytes*1)
    STX.b A1T1L-!DP_DMA
    LDX.w #!Hdma_TableSetA+(!Hdma_TableBytes*2)
    STX.b A1T2L-!DP_DMA
    LDX.w #!Hdma_TableSetA+(!Hdma_TableBytes*3)
    STX.b A1T3L-!DP_DMA
    LDX.w #!Hdma_TableSetA+(!Hdma_TableBytes*4)
    STX.b A1T4L-!DP_DMA
    LDX.w #!Hdma_TableSetA+(!Hdma_TableBytes*5)
    STX.b A1T5L-!DP_DMA
    LDX.w #!Hdma_TableSetA+(!Hdma_TableBytes*6)
    STX.b A1T6L-!DP_DMA
    LDX.w #!Hdma_TableSetA+(!Hdma_TableBytes*7)
    STX.b A1T7L-!DP_DMA
    PLD
    RTL
.set_b:
    LDX.w #!Hdma_TableSetB
    STX.b A1T0L-!DP_DMA
    LDX.w #!Hdma_TableSetB+(!Hdma_TableBytes*1)
    STX.b A1T1L-!DP_DMA
    LDX.w #!Hdma_TableSetB+(!Hdma_TableBytes*2)
    STX.b A1T2L-!DP_DMA
    LDX.w #!Hdma_TableSetB+(!Hdma_TableBytes*3)
    STX.b A1T3L-!DP_DMA
    LDX.w #!Hdma_TableSetB+(!Hdma_TableBytes*4)
    STX.b A1T4L-!DP_DMA
    LDX.w #!Hdma_TableSetB+(!Hdma_TableBytes*5)
    STX.b A1T5L-!DP_DMA
    LDX.w #!Hdma_TableSetB+(!Hdma_TableBytes*6)
    STX.b A1T6L-!DP_DMA
    LDX.w #!Hdma_TableSetB+(!Hdma_TableBytes*7)
    STX.b A1T7L-!DP_DMA
    PLD
    RTL

; $FD:C2C1 — EngFD_UnkC2C1 (30 bytes, $C2C1–$C2DE)
; Once a frame: runs entry !Field_Unk26 (0-2) of one of two handler
; tables and flips !Field_Unk53 bit 0. With bit 0 clear it runs
; EngFD_UnkC2C1Table0 and sets the bit; with it set, EngFD_UnkC2C1Table1
; and clears it. So the two tables alternate frame by frame, probably
; filling the two HDMA table sets in turn (Hdma_InitChannelsFD picks a
; set by !Field_Unk53; not traced). The handlers are not analysed.
; Callers (9 JSL sites): Field_EndOfFrame ($C0:00C7), Field_EndOfFrameShort ($C0:00E0),
;   Field_RestoreState ($C0:01AA), Field_RefreshHdmaLong ($C0:0B11, $C0:0B15), Scene_ResumeNmi
;   ($C0:0B2E), Field_PauseAndMenuInput ($C0:1905, $C0:194D) and Field_FadeToBankC2Mode5 ($C0:19B6).
; Entry: M=1, X=1 (8-bit TAX of the doubled index), DP=$0100, DB=$00 at
;        all callers (what the handlers need is not traced)
; Exit:  M=1, X=1; !Field_Unk53 bit 0 flipped; A = 1; X and the rest as
;        the handler leaves them
; Callees: the 6 handlers of EngFD_UnkC2C1Table0/1 (JSR (table,X))
org $FDC2C1
EngFD_UnkC2C1:
    LDA.b !Field_Unk53
    BIT.b #!Field_Unk53Phase
    BNE .phase1
    LDA.b !Field_Unk26
    ASL A
    TAX
    JSR (EngFD_UnkC2C1Table0,X)
    LDA.b #!Field_Unk53Phase
    TSB.b !Field_Unk53
    RTL
.phase1:
    LDA.b !Field_Unk26
    ASL A
    TAX
    JSR (EngFD_UnkC2C1Table1,X)
    LDA.b #!Field_Unk53Phase
    TRB.b !Field_Unk53
    RTL

; $FD:C2DF — EngFD_UnkC2C1Table1 (6 bytes, $C2DF–$C2E4)
; EngFD_UnkC2C1's handlers by !Field_Unk26 when !Field_Unk53 bit 0 is set.
EngFD_UnkC2C1Table1:
    dw EngFD_UnkC2EB                    ; 0
    dw EngFD_UnkC995                    ; 1
    dw EngFD_UnkCFCF                    ; 2

; $FD:C2E5 — EngFD_UnkC2C1Table0 (6 bytes, $C2E5–$C2EA)
; The same when !Field_Unk53 bit 0 is clear.
EngFD_UnkC2C1Table0:
    dw EngFD_UnkC847                    ; 0
    dw EngFD_UnkCD0C                    ; 1
    dw EngFD_UnkD27E                    ; 2

; $FD:D52D — EngFD_UnkD52D (167 bytes, $D52D–$D5D3)
; EngFD_UnkC124's helper: builds a table of (CGADSUB, COLDATA) byte
; pairs at $7F:1538 (channel 6's registers in Hdma_InitChannelsFD), then
; copies $100 bytes from $7F:1538 to $7F:1600 (MVN; the source overlaps
; the destination, but the table's $B4 bytes are copied intact).
; The run length comes from the hardware divider: 40 / 8 = 5 entries per
; step (the remainder, 0, would lengthen the middle run). It writes:
;   - 8 steps of 5 entries ($01, v) with v = $E8 down to $E1;
;   - a middle run of 5 entries ($81, $E0): a step is added to its end
;     offset before the $E0 test, so it is a step plus remainder * 2
;     bytes;
;   - 9 steps of 5 entries ($81, v) with v = $E1 up to $E9;
; 90 pairs, $B4 bytes ($7F:1538-$15EB).
; With COLDATA $E0 + n (all three channels at intensity n) and CGADSUB
; $01 / $81 (add / subtract the fixed colour on BG1), this looks like a
; brightness gradient down the screen; whether and where the indirect
; tables use it is not traced.
; The 7 NOPs wait for the divider; the table is built with 8-bit X/Y.
; Callers (1 JSR site): EngFD_UnkC124 ($FD:C1E9).
; Entry: M=1, X any (set to 8-bit, then 16-bit), DP=$0100 (scratch
;        $DB-$E1), DB=$7F (the table stores)
; Exit:  M=1, X=0; A = $FFFF (MVN count spent); X = $1638, Y = $1700;
;        DB = $7F (MVN); DP $DB, $DD, $DF, $E1 written
org $FDD52D
EngFD_UnkD52D:
    LDA.b #!HdmaGrad_Lines
    STA.l WRDIVL
    LDA.b #0
    STA.l WRDIVH
    LDA.b #!HdmaGrad_Steps
    STA.l WRDIVB
    NOP                                 ; the divide takes 16 cycles
    NOP
    NOP
    NOP
    NOP
    NOP
    NOP
    SEP #$10
    LDX.b #0
    LDA.l RDDIVL
    ASL A
    STA.b !HdmaGrad_End
    STA.b !HdmaGrad_Step
    LDA.l RDMPYL
    ASL A
    STA.b !HdmaGrad_Extra
    LDA.b #!HdmaGrad_AddFirst
.add_step:
    STA.b !HdmaGrad_Value
.add_entry:
    CPX.b !HdmaGrad_End
    BEQ .add_next
    LDA.b !HdmaGrad_Value
    STA.w !Hdma_Unk7F1538+1,X
    LDA.b #!Hdma_GradAdd
    STA.w !Hdma_Unk7F1538,X
    INX
    INX
    BRA .add_entry
.add_next:
    LDA.b !HdmaGrad_End
    CLC
    ADC.b !HdmaGrad_Step
    STA.b !HdmaGrad_End
    LDA.b !HdmaGrad_Value
    DEC A
    CMP.b #!COLDATA_AllZero
    BEQ .middle
    BRA .add_step
.middle:
    LDA.b !HdmaGrad_End
    CLC
    ADC.b !HdmaGrad_Extra
    STA.b !HdmaGrad_End
.middle_entry:
    CPX.b !HdmaGrad_End
    BEQ .sub_start
    LDA.b #!COLDATA_AllZero
    STA.w !Hdma_Unk7F1538+1,X
    LDA.b #!Hdma_GradSub
    STA.w !Hdma_Unk7F1538,X
    INX
    INX
    BRA .middle_entry
.sub_start:
    LDA.b #!COLDATA_AllZero
    STA.b !HdmaGrad_Value
    BRA .sub_next
.sub_step:
    STA.b !HdmaGrad_Value
.sub_entry:
    CPX.b !HdmaGrad_End
    BEQ .sub_next
    LDA.b !HdmaGrad_Value
    STA.w !Hdma_Unk7F1538+1,X
    LDA.b #!Hdma_GradSub
    STA.w !Hdma_Unk7F1538,X
    INX
    INX
    BRA .sub_entry
.sub_next:
    LDA.b !HdmaGrad_End
    CLC
    ADC.b !HdmaGrad_Step
    STA.b !HdmaGrad_End
    LDA.b !HdmaGrad_Value
    CMP.b #!HdmaGrad_SubLast
    BEQ .copy
    INC A
    BRA .sub_step
.copy:
    REP #$30
    LDX.w #!Hdma_Unk7F1538
    LDY.w #!Hdma_Unk7F1600
    LDA.w #!Hdma_GradBytes-1
    MVN !Bank7F,!Bank7F                 ; lint-ok: MVN operands are bank bytes; asar rejects a width suffix on MVN
    SEP #$20
    RTS

; ============================================================
; Location animation set-up ($FD:DE98–$FD:E021, $FD:E292–$FD:E39B,
; vectors $FD:FFF4–$FD:FFFC)
; The last two steps of LoadLocation, reached through the bank's
; service vectors: FdVec_FFFA fills the 12 five-byte records at $05B0
; and their data at $7F:0400 from a list picked by the location's
; LocRom.Tileset12, FdVec_FFF4 the 12 twelve-byte records at $0520 from
; a list picked by its LocRom.Palette. Field_EndOfFrame runs FdVec_FFF7
; every frame, which works on the $0520 records (not analysed). So
; probably the location's tile and palette animations; what the
; records' bytes mean is not traced.
; ============================================================

; $FD:DE98 — FieldFD_LoadAnimSetA (394 bytes, $DE98–$E021)
; FdVec_FFFA's routine. Saves P, DP and DB; runs with DB=$00, DP=$0500,
; M=1, X=0. The list starts at !FieldRom_AnimListA + the word
; !FieldRom_AnimListAPtrs holds for LocRom.Tileset12 & $3F; the WRAM
; port is set to $7F:0400. Then, for each of the 12 FieldAnimA records
; at $05B0 (DP $18 counts them):
;   - a list byte of $80 sets .Unk3 = $80 and nothing else;
;   - otherwise the byte goes to .Unk0, the next two to .Unk2 and .Unk3,
;     and .Bank = $7F; then by the byte (kind):
;       2: .Unk0/.Unk1 = 0; the two next list bytes, each * 4 as a word,
;          go to the port 4 times over, then the 4 bytes after them, 4
;          times over (16 + 16 bytes; the list moves on 6);
;       4: .Unk0/.Unk1 = 0; the 4 next bytes * 4 as words, twice over
;          (16 bytes), then the 8 after them as 4 byte pairs, twice over
;          (16 bytes; the list moves on 12);
;       else: .Unk0/.Unk1 = 0; 8 bytes * 4 as words (16 bytes), then 8
;          byte pairs (16 bytes; the list moves on 24).
; So each record but an $80 one adds 32 bytes at $7F:0400 on.
; The word stores to WMDATA-1 ($217F) are 16-bit: their high byte lands
; in WMDATA, so XBA, STA, XBA, STA sends the word low byte first.
; Callers (1 JMP site): FdVec_FFFA ($FD:FFFA).
; Entry: M=1 (its first LDA #0 is 8-bit), X any (P saved; it sets X=0),
;        DP any (saved), DB any (saved)
; Exit:  P, DP and DB restored; A = 0, X = list end, Y = $3C (16-bit
;        values, with the caller's M/X back); $0510 and $0518 (DP $10,
;        $18) written
!FieldAnimA_Left  = $18                 ; 1 B dp (DP=$0500): records still to fill
!FieldAnimA_Count = $10                 ; 1 B dp (DP=$0500): words or byte groups left in a copy
org $FDDE98
FieldFD_LoadAnimSetA:
    PHP
    PHD
    PHB
    LDA.b #0
    PHA
    PLB
    REP #$10
    SEP #$20
    LDX.w #!DP_FieldAnim
    PHX
    PLD
    LDA.b #0
    XBA
    LDX.w !DP_Field+!Loc_RecOfs
    LDA.l LocRom.Tileset12,X
    AND.b #!LocRom_AnimSetMask
    ASL A
    TAX
    REP #$20
    LDA.l !FieldRom_AnimListAPtrs,X
    TAX
    LDA.w #!FieldAnimA_Wram
    STA.w WMADDL
    LDA.w #!FieldAnim_NumRecs
    STA.b !FieldAnimA_Left
    SEP #$20
    LDA.b #!Bank7F                      ; WMADDH bit 0 set: bank $7F
    STA.w WMADDH
    LDY.w #0
.record:
    LDA.l !FieldRom_AnimListA,X
    INX
    CMP.b #!FieldAnim_EndRecord
    BNE .kind
    LDA.b #!FieldAnim_EndRecord
    STA.w FieldAnimA.Unk3,Y
    JMP .next
.kind:
    STA.w FieldAnimA.Unk0,Y
    LDA.l !FieldRom_AnimListA,X
    STA.w FieldAnimA.Unk2,Y
    INX
    LDA.l !FieldRom_AnimListA,X
    STA.w FieldAnimA.Unk3,Y
    INX
    LDA.b #!Bank7F
    STA.w FieldAnimA.Bank,Y
    LDA.w FieldAnimA.Unk0,Y
    CMP.b #!FieldAnim_Kind2
    BNE .not_kind2
    LDA.b #0
    STA.w FieldAnimA.Unk0,Y
    STA.w FieldAnimA.Unk1,Y
    LDA.b #4
    STA.b !FieldAnimA_Count
.kind2_words:
    REP #$20
    LDA.l !FieldRom_AnimListA,X
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    XBA
    STA.w WMDATA-1                      ; the high byte (the word's low byte) to WMDATA
    XBA
    STA.w WMDATA-1                      ; and its high byte
    LDA.l !FieldRom_AnimListA+1,X
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    XBA
    STA.w WMDATA-1
    XBA
    STA.w WMDATA-1
    SEP #$20
    DEC.b !FieldAnimA_Count
    BNE .kind2_words
    INX
    INX
    LDA.b #4
    STA.b !FieldAnimA_Count
.kind2_bytes:
    LDA.l !FieldRom_AnimListA,X
    STA.w WMDATA
    LDA.l !FieldRom_AnimListA+1,X
    STA.w WMDATA
    LDA.l !FieldRom_AnimListA+2,X
    STA.w WMDATA
    LDA.l !FieldRom_AnimListA+3,X
    STA.w WMDATA
    DEC.b !FieldAnimA_Count
    BNE .kind2_bytes
    INX
    INX
    INX
    INX
    JMP .next
.not_kind2:
    CMP.b #!FieldAnim_Kind4
    BNE .other
    LDA.b #0
    STA.w FieldAnimA.Unk0,Y
    STA.w FieldAnimA.Unk1,Y
    LDA.b #8
    STA.b !FieldAnimA_Count
.kind4_word_pass:
    PHX
.kind4_word:
    REP #$20
    LDA.l !FieldRom_AnimListA,X
    INX
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    XBA
    STA.w WMDATA-1
    XBA
    STA.w WMDATA-1
    SEP #$20
    DEC.b !FieldAnimA_Count
    LDA.b !FieldAnimA_Count
    AND.b #3
    BNE .kind4_word
    PLX
    LDA.b !FieldAnimA_Count
    BNE .kind4_word_pass
    INX
    INX
    INX
    INX
    LDA.b #8
    STA.b !FieldAnimA_Count
.kind4_pair_pass:
    PHX
.kind4_pair:
    LDA.l !FieldRom_AnimListA,X
    STA.w WMDATA
    INX
    LDA.l !FieldRom_AnimListA,X
    STA.w WMDATA
    INX
    DEC.b !FieldAnimA_Count
    LDA.b !FieldAnimA_Count
    AND.b #3
    BNE .kind4_pair
    PLX
    LDA.b !FieldAnimA_Count
    BNE .kind4_pair_pass
    REP #$21
    TXA
    ADC.w #8
    TAX
    LDA.w #0
    SEP #$20
    JMP .next
.other:
    LDA.b #0
    STA.w FieldAnimA.Unk0,Y
    STA.w FieldAnimA.Unk1,Y
    LDA.b #8
    STA.b !FieldAnimA_Count
.other_word:
    REP #$20
    LDA.l !FieldRom_AnimListA,X
    AND.w #!Eng_LowByteMask
    ASL A
    ASL A
    SEP #$20
    STA.w WMDATA
    XBA
    STA.w WMDATA
    INX
    DEC.b !FieldAnimA_Count
    BNE .other_word
    LDA.b #8
    STA.b !FieldAnimA_Count
.other_pair:
    LDA.l !FieldRom_AnimListA,X
    STA.w WMDATA
    LDA.l !FieldRom_AnimListA+1,X
    STA.w WMDATA
    INX
    INX
    DEC.b !FieldAnimA_Count
    BNE .other_pair
.next:
    REP #$21
    TYA
    ADC.w #!FieldAnimA_Size
    TAY
    LDA.w #0
    SEP #$20
    DEC.b !FieldAnimA_Left
    BEQ .done
    JMP .record
.done:
    PLB
    PLD
    PLP
    RTL

; $FD:E292 — FieldFD_LoadAnimSetB (266 bytes, $E292–$E39B)
; FdVec_FFF4's routine. Saves P, DP and DB; runs with DB=$00, DP=$0500,
; M=1, X=0. The list starts at !FieldRom_AnimListB + the word
; !FieldRom_AnimListBPtrs holds for LocRom.Palette. It fills the first 6
; of the 12 FieldAnimB records at $0520, by the high nibble of each
; list byte:
;   - 0: .Unk0 = 0 (one byte used);
;   - $10 or $80: .Unk0-.Unk2 and .Unk5-.Unk8 from 7 bytes, .Unk3/.Unk4
;     = 0; with $80 also .Ptr = the long address of the bytes after them
;     in bank $FD, and the list then skips (.Unk0 & $0F) + 1 bytes;
;   - anything else: .Unk0-.Unk2 and .Unk5 from 4 bytes, .Unk3/.Unk4 = 0.
; Then .Unk0 of records 6-11 is set to 0.
; Quirk: it points the WRAM port at $00:0520 and sets DP $18 to 12 as
; FieldFD_LoadAnimSetA does, but writes the records with plain stores
; and never reads $0518 (the 6 records are counted by Y).
; Callers (1 JMP site): FdVec_FFF4 ($FD:FFF4).
; Entry: M=1 (its first LDA #0 is 8-bit), X any (P saved; it sets X=0),
;        DP any (saved), DB any (saved)
; Exit:  P, DP and DB restored; A = 0 (8-bit), X = list end, Y = $48
;        (with the caller's M/X back); $050E/$050F and $0518 written;
;        WMADD left at $00:0520
!FieldAnimB_Skip = $0E                  ; 2 B dp (DP=$0500): .Unk0 & $0F, bytes the list skips
org $FDE292
FieldFD_LoadAnimSetB:
    PHP
    PHD
    PHB
    LDA.b #0
    PHA
    PLB
    REP #$10
    SEP #$20
    LDX.w #!DP_FieldAnim
    PHX
    PLD
    LDA.b #0
    XBA
    LDX.w !DP_Field+!Loc_RecOfs
    LDA.l LocRom.Palette,X
    ASL A
    TAX
    REP #$20
    LDA.l !FieldRom_AnimListBPtrs,X
    TAX
    LDA.w #FieldAnimB.Unk0
    STA.w WMADDL                        ; quirk: the port is not used
    LDA.w #!FieldAnim_NumRecs
    STA.b !FieldAnimA_Left              ; quirk: not read here
    SEP #$20
    LDA.b #0
    STA.w WMADDH
    LDY.w #0
.record:
    LDA.l !FieldRom_AnimListB,X
    AND.b #!FieldAnimB_KindMask
    BEQ .empty
    CMP.b #!FieldAnimB_Kind10
    BEQ .long
    CMP.b #!FieldAnimB_Kind80
    BEQ .long
    LDA.l !FieldRom_AnimListB,X
    STA.w FieldAnimB.Unk0,Y
    INX
    LDA.l !FieldRom_AnimListB,X
    STA.w FieldAnimB.Unk1,Y
    INX
    LDA.l !FieldRom_AnimListB,X
    STA.w FieldAnimB.Unk2,Y
    INX
    LDA.b #0
    STA.w FieldAnimB.Unk3,Y
    STA.w FieldAnimB.Unk4,Y
    LDA.l !FieldRom_AnimListB,X
    STA.w FieldAnimB.Unk5,Y
    INX
    BRA .next
.empty:
    INX
    STA.w FieldAnimB.Unk0,Y
    BRA .next
.long:
    PHA
    LDA.l !FieldRom_AnimListB,X
    STA.w FieldAnimB.Unk0,Y
    INX
    LDA.l !FieldRom_AnimListB,X
    STA.w FieldAnimB.Unk1,Y
    INX
    LDA.l !FieldRom_AnimListB,X
    STA.w FieldAnimB.Unk2,Y
    INX
    LDA.b #0
    STA.w FieldAnimB.Unk3,Y
    STA.w FieldAnimB.Unk4,Y
    LDA.l !FieldRom_AnimListB,X
    STA.w FieldAnimB.Unk5,Y
    INX
    LDA.l !FieldRom_AnimListB,X
    STA.w FieldAnimB.Unk6,Y
    INX
    LDA.l !FieldRom_AnimListB,X
    STA.w FieldAnimB.Unk7,Y
    INX
    LDA.l !FieldRom_AnimListB,X
    STA.w FieldAnimB.Unk8,Y
    INX
    PLA
    CMP.b #!FieldAnimB_Kind80
    BNE .next
    REP #$21
    TXA
    ADC.w #!FieldRom_AnimListB&$FFFF
    STA.w FieldAnimB.Ptr,Y
    LDA.w #0
    SEP #$20
    LDA.b #!FieldRom_AnimListB>>16
    STA.w FieldAnimB.Ptr+2,Y
    LDA.w FieldAnimB.Unk0,Y
    AND.b #!FieldAnimB_SkipMask
    STA.b !FieldAnimB_Skip
    STZ.b !FieldAnimB_Skip+1
    REP #$20
    TXA
    SEC                                 ; + 1
    ADC.b !FieldAnimB_Skip
    TAX
    LDA.w #0
    SEP #$20
.next:
    TYA
    CLC
    ADC.b #!FieldAnimB_Size
    TAY
    CMP.b #!FieldAnimB_Size*!FieldAnimB_Filled
    BEQ .clear_rest
    JMP .record
.clear_rest:
    LDA.b #0
    STA.w FieldAnimB[0].Unk0,Y
    STA.w FieldAnimB[1].Unk0,Y
    STA.w FieldAnimB[2].Unk0,Y
    STA.w FieldAnimB[3].Unk0,Y
    STA.w FieldAnimB[4].Unk0,Y
    STA.w FieldAnimB[5].Unk0,Y
    PLB
    PLD
    PLP
    RTL

; $FD:FFF4 — FdVec_FFF4 (3 bytes, $FFF4–$FFF6)
; The bank's service vectors: three JMPs at fixed addresses near the end
; of the bank, so code in other banks can JSL them. The routines end with
; RTL.
; Callers (1 JSL site): LoadLocation ($C0:0116).
; Entry: as FieldFD_LoadAnimSetB: M=1, X any, DP any, DB any
; Exit:  as FieldFD_LoadAnimSetB
org $FDFFF4
FdVec_FFF4:
    JMP FieldFD_LoadAnimSetB

; $FD:FFF7 — FdVec_FFF7 (3 bytes, $FFF7–$FFF9)
; JMP to EngFD_UnkE39C (not analysed; Field_EndOfFrame runs it every
; frame, and its header says it ticks the counter table at $0520, the
; FieldAnimB records).
; Callers (10 JSL sites): Field_EndOfFrame ($C0:00CD), Field_EndOfFrameShort ($C0:00E6),
;   Scene_Unk0283 ($C0:02BA, $C0:02E1), Field_SceneChangeTick ($C0:0CE1), DefaultHandler ($C0:1793),
;   Evt_OpFF_Misc ($C0:3FC6) and unmatched ($CD:09BF, $CD:0AD6, $D1:F54D).
; Entry: M=1, X=0, DP=$0100, DB=$00 at the field callers (the callers in
;        banks $CD and $D1 not traced; what EngFD_UnkE39C needs is not
;        traced)
; Exit:  as EngFD_UnkE39C (not analysed)
FdVec_FFF7:
    JMP EngFD_UnkE39C

; $FD:FFFA — FdVec_FFFA (3 bytes, $FFFA–$FFFC)
; JMP to FieldFD_LoadAnimSetA.
; Callers (1 JSL site): LoadLocation ($C0:0112).
; Entry: as FieldFD_LoadAnimSetA: M=1, X any, DP any, DB any
; Exit:  as FieldFD_LoadAnimSetA
FdVec_FFFA:
    JMP FieldFD_LoadAnimSetA
