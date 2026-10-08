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
; !BattleRom_UnkCC88CB. What the records hold is not traced (the bytes
; are read by $C1:AC89, unmatched, which ORs a slot + 3 into B18E).
; Callers (3 JSL sites): unmatched ($C1:9B1C, $C1:A128, $C1:A370).
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
; Callers (1 JSL site): unmatched ($C1:9A25).
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
;     BattleSys_UnkBFAA runs (through BattleSys_UnkBFAALong). Then (also
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
;        !Battle_UnkAE4C = 0; A, X clobbered; Y unchanged (this code;
;        BattleSys_UnkBFAA not analysed); DP $12 = the slot on the
;        Status2 path; what BattleSys_UnkBFAA changes
; Callees: Battle_RandRangeLong, BattleSys_UnkBFAALong
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
    JSL BattleSys_UnkBFAALong
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
    JSL BattleSys_UnkBFAALong
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
; Callers (1 JSL site): unmatched ($C1:ECFE).
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
;     left by BattleSys_Unk8461), BattleSys_UnkBFAA (through
;     BattleSys_UnkBFAALong); if that target is then KO'd the loop stops.
; Then !Battle_UnkB3B9 = 0.
; Callers (1 JSL site): BattleSys_Unk8461 ($C1:8650).
; Entry: M=1, X=0, DP=0, DB=$7E; DP $22 = the slot that just acted
; Exit:  M=1, X=0; !Battle_UnkB3B9 = 0; A, X, Y clobbered; DP $0C
;        written; !Battle_UnkB315 = the last entry looked at; Battle_RandRange's
;        and BattleSys_UnkBFAA's changes
; Callees: Battle_RandRangeLong, BattleSys_UnkBFAALong
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
    JSL BattleSys_UnkBFAALong
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
;   BattleSys_ListHandler9 ($C1:8BB4), Battle_SetupBattle ($C1:FBAC) and unmatched ($C1:8E88,
;   $C1:B38A, $C1:BB29, $C1:BC56, $C1:C01D).
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
; Zeroes the $84 bytes of !Battle_UnkB328 ($B328-$B3AB). BattleSys_Main
; runs it every pass; what the block holds is not traced.
; Callers (6 JSL sites): BattleSys_Main ($C1:812C), Battle_SetupBattle ($C1:FD12) and unmatched
;   ($C1:D523, $C1:D7C4, $C1:D8D1, $C1:ED84).
; Entry: M=1, X=0, DP=0 (TDC as zero), DB=$7E
; Exit:  M=1, X=0; A = 0 (B too); X = $84; Y unchanged
org $FDACFD
BattleFD_UnkACFD:
    TDC
    TAX
.clear:
    STA.w !Battle_UnkB328,X
    INX
    CPX.w #!Battle_UnkB328Bytes
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
; The bits are set elsewhere (not traced). Messages 2 and 3 show the
; gold and items BattleSys_Main pays; 0, 1 and 4-7 probably show the
; other rewards (experience, tech points, level-ups, new techs; not
; traced).
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
; Callers (3 JSL sites): Battle_SetupBattle ($C1:FB84) and unmatched ($C1:BCD8, $C1:CE36).
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
; $FD:BA61 — RandomTableFD (256 bytes, $FD:BA61–$BB60)
; A byte-identical copy of RandomTable ($C0:FE00): the same shuffle of
; 0-255. Read with LDA.l $FDBA61,X by battle code in bank $C1: at
; $C1:AF56/AF60 and $C1:AFAE/AFB8 (unmatched), two copies of a roll that
; take X from a counter (dp $26 in the first, $B3E6 in the second). When
; the range is $FF they use the entry as is (the reads at $AF56/$AFAE) and
; leave the counter alone; otherwise they step the counter and reduce the
; entry with the shift-and-subtract divide at $C1:C92A, using the
; remainder plus dp $25 (entry mod range, plus a base). What the rolls
; are for is not traced. The 6 bytes after the table
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
; resets, and JML $FDC000 at $C0:418D (unmatched; after JSR InitHW and
; S=$06FF). The bytes at $FD:851D read as JSR $C000 but sit in a block of
; packed data ($FD:8480 onwards does not decode as code), not a caller.
; Callers (3 sites: 1 JSR, 2 JML): Reset (JML $C0:FF03) and unmatched (JML $C0:418D, JSR $FD:851D).
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
