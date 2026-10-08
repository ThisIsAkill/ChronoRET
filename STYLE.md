# Style

Code under `asm/` is read far more often than it is written: by people learning how Chrono
Trigger works, by reviewers, and by whoever matches the next routine. A routine is only done
when it is **matched, readable and reviewed** (CONTRIBUTING.md, "Definition of done"). A literal
transcription of the disassembly can live on a work branch while you work, never on `main`.

`tools/lint_readability.py` checks the mechanical rules below (pre-commit and CI); the
independent review checks the rest. Routines matched before this rule are listed in
`tools/readability_baseline.txt`, which may only shrink.

## What readable means

**Names, not addresses.** Every memory operand, call and jump target is a name:

```asm
    LDA.w !Battle_ActivePcSlot          ; not LDA $95D5
    LDA.w !Battler_Present,X            ; per-slot array, not LDA $96F5,X
    JSR BattleTgt_CycleNext             ; not JSR $27FA
    JSL Audio_ProcessEntry              ; not JSL $C70004
    STA.b INIDISP-!DP_PPU               ; a register through a relocated direct page
```

RAM lives in `asm/include/ram_engine.inc` and `ram_battle.inc` (`!Name = $addr`), registers in
`asm/hardware.inc`. A routine that is called but not matched yet gets a label-only stub in
`asm/include/unmatched*.asm`, never an address at the call site. Raw `BRL $offset` becomes
`BRL Label`.

**Structs, not offsets.** Records that repeat are asar structs with named fields; index them,
don't add offsets by hand:

```asm
struct PcBattleStats $5E00
.CurHp:     skip 2
            skip $48
.Status:    skip 1          ; bit 7: down (inferred from the revive target list)
endstruct align $80

    LDA.w PcBattleStats[1].Status       ; not LDA $5ECA
```

A field or variable whose meaning is unknown still gets a name that says what is known
(`!Battle_Unk9F38`, `.Flags2C`) and a comment with what has been observed; rename it when
someone finds out.

**Named constants.** A number that means something gets a name (`!TargetMode_AllFlag = $80`,
`!NumBattlerSlots = 11`, `!Sfx_TurnReady = $42`): flag bits, modes, counts, tile and palette
ids, sentinels. Literals left in code are small values whose meaning is the literal itself (a
shift count, an index into a table declared right there). `REP`/`SEP` masks are exempt.

**Explicit widths.** Every data instruction whose operand uses a define or struct field says
`.b`, `.w` or `.l`. (Jumps and calls are exempt: `JSR`, `JMP`, `JSL`, `JML` and branches have one
encoding each, so their width can't drift.) Defines are textual and asar doesn't track the M/X flags, so without a suffix the
encoding would depend on how the value happens to be written.

**No hand-encoded instructions.** No `db $A9,$7F ; LDA #$7F`: write the instruction with the
width suffix that gives the original encoding (`LDA.b #!Name`). If an encoding truly can't be
written as an instruction, it gets a named macro in `asm/include/macros.inc`.

**No test plumbing in game code.** No `print`, `assert` or `warnpc`, and no label-only stubs in
bank files. Verification is the tools' job (`make gate`), not the routine's.

**Faithful, then clear.** The bytes must match, so the code keeps the original's quirks: dead
bytes after a `JMP`, a branch that can never be taken, a list cleared one entry too long.
Keep the quirk, name it, and say in a comment why it is there and how you know.

**Comments say why.** The header comment says what the routine is for, who calls it, its CPU
state on entry and exit (M, X, DP, DB), and anything a reader would not guess. When a name or
meaning is inferred, say from what ("inferred: only written by the revive path"). Comments inside
explain the non-obvious; they don't narrate each line or repeat what a name already says.

**Headers are checked.** The header is the comment block between the previous routine's last
code line and the label (the same span `tools/progress.py` hashes). The lint requires:

- `HEADER`: a comment line starting `Entry:` or `On entry:` and one starting `Exit:` (a
  parenthesis before the colon is fine, as in `Exit (both entries):`; `Entry/Exit:` counts as
  both).
- `CALLERS`: every caller site `tools/xref.py` CONFIRMS (`JSR`/`JSL`/`JMP`/`JML`/`BRL`) is
  accounted for, by its address (`$C1:2ECF`, `$C12ECF`, `$2ECF` in the routine's own bank, or a
  `/AAAA` continuation such as `$FD:DA5B/DABA`), by the full name of the matched routine that
  contains it, or by a count such as `19 JSR sites` or `20 call sites` that is at least the
  confirmed count. Prefer one `Callers:` line:

  ```asm
  ; Callers (4 JSR sites): BattleMenu_ChooseAttack ($C1:12B0),
  ;   BattleMenu_TechConfirm ($C1:1379), BattleMenu_ItemConfirm ($C1:14C5) and
  ;   BattleMenu_TargetSelectInput ($C1:1561).
  ```

  A routine reached only through a table or by falling in needs no list. If xref confirms a site
  that is not a real call (data that decodes as `JSR`), name its address and say so; that is
  accounted for too.

Two kinds of label are exempt from `HEADER`:

- **Tables**: a label whose body is only `db`/`dw`/`dl`/`dd` data (no instruction or macro).
- **Sub-entries** (a fall-through entry, shared tail or loop label that has to be global): mark
  it `; header: see <Parent>` on or above the label line. `<Parent>` must be a routine in the
  same file with an Entry/Exit header that names the sub-entry; the sub-entry's callers may be
  listed there. Sites inside the parent or a sibling sub-entry are internal flow and need no
  mention.

  ```asm
  BattleMenu_ItemListScrollUp_RenderTail:     ; header: see BattleMenu_ItemListScrollUp
  ```

## Layout

- One file per bank, `asm/bank<NN>/bank<NN>.asm`, in address order, grouped by subsystem with a
  banner per cluster.
- Shared names in `asm/include/`: `ram_engine.inc` / `constants_engine.inc` for banks $00,
  $C0 and $FD; `ram_battle.inc` / `constants_battle.inc` for the battle engine. Battle names
  start with `Battle`, `Battler`, `Pc`, `Enemy`, `Tech`, `Item` or `Sfx`, and engine names never
  do. asar lets a later define silently replace an earlier one, so the prefixes keep the two
  sets apart.
- Each define gets a one-line comment: width, meaning, how it was inferred.
