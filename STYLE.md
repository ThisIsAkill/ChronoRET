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
code line and the label (the same span `tools/progress.py` hashes, less the generated Callers
block). The lint requires:

- `HEADER`: a comment line starting `Entry:` or `On entry:` and one starting `Exit:` (a
  parenthesis before the colon is fine, as in `Exit (both entries):`; `Entry/Exit:` counts as
  both).
- `CALLERS`: the Callers block is exactly what `tools/callers.py` generates. Never write it by
  hand: run `python3 tools/callers.py --update` after matching code (and after merging
  `origin/main`), and it rewrites every block from the call sites `tools/xref.py` CONFIRMS
  (`JSR`/`JSL`/`JMP`/`JML`/`BRL`), outside the routine and its sub-entries. Each site is named by
  the matched routine that contains it, or `unmatched`, with its address, and the block keeps the
  count:

  ```asm
  ; Callers (4 JSR sites): BattleMenu_ChooseAttack ($C1:12B0), BattleMenu_TechConfirm ($C1:1379),
  ;   BattleMenu_ItemConfirm ($C1:14C5) and unmatched ($C1:5561).
  ```

  Sites of different kinds carry their kind (`Name (JSR $C0:1234, JMP $C0:1240)`, count
  `5 sites: 4 JSR, 1 JMP`); a sub-entry's sites are listed in its parent's header as
  `; Callers of <Sub-entry> (...)`; a routine with no confirmed site has no block. The block is
  left out of the source hash, so new callers never void a review. Anything a person adds about
  callers goes on its own line, which the tool leaves alone and the reviewer judges:

  ```asm
  ; Callers note: also reached through BattleAct_OpcodeTable entry $1C; the JSR byte
  ;   pattern at $C1:8F02 is inside a data table.
  ```

  Use a note for a site xref confirms that is not a real call (data that decodes as `JSR`), for
  tables that dispatch to the routine and for fall-ins.

- `SIZE`: a header claim `Name (N bytes, $XXXX–$YYYY)` agrees with the assembled layout (the
  routine alone, or with its sub-entries). A combined claim `Name (N bytes with A and B,
  $XXXX–$YYYY)` must give the range's size, start at the routine and end where a row of the
  layout ends; every routine inside the range is named in it or is a `header: see` sub-entry.
- `UNMATCHED`: no header or banner calls an address `unmatched` (`unmatched code at $C1:0027`,
  `$C1:3819 (unmatched)`) once that address lies inside matched code; name the routine instead.
- `DPDB`: the Entry line states DP and DB itself (`DP any` and `DB any` are statements too).
  "as Field_Unk74D4" or "see the banner" does not count unless the text it points to is in the
  same header.
- `INDEX`: an Exit claim that X or Y is unchanged (kept, preserved, intact, as on entry) holds
  for a caller entering with X=0: no path through the routine or its callees sets the X flag
  (`SEP #$10`/`#$30`, a `PLP` restoring X=1, a callee returning with X=1) and leaves the
  register without its high byte (a `PHY`/`PLY` pair at 16 bits brings it back; at 8 bits it
  does not). Say what happens instead: `Y's low byte kept, high byte cleared (SEP #$10 at
  $C0:AC69)`, or `with X=1 at entry`, or declare X=1 on the Entry line. A claim limited to
  some paths (`else Y unchanged`) fails only when no exit keeps the register.
  `python3 tools/index_claims.py --explain NAME` shows the reasoning.

Two kinds of label are exempt from `HEADER`:

- **Tables**: a label whose body is only `db`/`dw`/`dl`/`dd` data (no instruction or macro).
- **Sub-entries** (a fall-through entry, shared tail or loop label that has to be global): mark
  it `; header: see <Parent>` on or above the label line. `<Parent>` must be a routine in the
  same file with an Entry/Exit header that names the sub-entry (outside the generated Callers
  block); the sub-entry's callers are listed there. Sites inside the parent or a sibling sub-entry are internal flow and need no
  mention.

  ```asm
  BattleMenu_ItemListScrollUp_RenderTail:     ; header: see BattleMenu_ItemListScrollUp
  ```

## SPC700 (the sound driver)

The SPC700 program in bank $C7 (`asm/spc700/`) follows the same rules, checked by
`tools/lint_spc700.py` (run by the lint), with the SPC700's state in place of the 65816's:

- **Assembly.** asar's `arch spc700`; `%SpcOrg(aram)` puts the bytes at the ROM address of an
  ARAM address while labels take the ARAM address. Every direct-page and absolute operand says
  `.b` or `.w` (`mov.b !Spc_CurSong,a`, `mov.w !Spc_TrackF220+x,a`); branches, `call`, `jmp`,
  `pcall`, `tcall` and the `mov1`-style bit instructions have one encoding and need none.
- **Names.** `!SPC_*` for the I/O registers (`!SPC_CPUIO0`, `!SPC_DSPADDR`), `!DSP_*` for S-DSP
  register numbers (`mov y,#!DSP_KOF`), `!Spc_*` for the driver's RAM, other values and
  constants, `Spc_*` for labels; all in `asm/spc700/spc700.inc`, label-only stubs for what is
  not matched yet in `asm/spc700/unmatched.asm`. The prefixes keep them apart from the 65816
  names.
- **Headers.** The title gives both addresses: `; $0B96 — Spc_PollCommand (22 bytes,
  $0B96–$0BAB; ROM $C7:2E5B–$2E70)` (`SIZE` checks both against
  `symbols/spc700_functions.csv`). The Entry line states P, the direct-page flag (`P=0`: direct
  page $00xx, `P=1`: $01xx; `STATE`), where a 65816 header states DP and DB; Entry and Exit name
  A, X, Y (YA for word values), SP when it moves, and the PSW flags a caller branches on. Where a
  routine writes S-DSP registers a `; DSP:` line names them, and where it uses CPUIO0-3 a
  `; Ports:` line gives the protocol and its 65816 counterpart (the `Audio_*` routine).
- **Callers.** Until a generator exists they are hand-written on `; Callers note:` lines, and
  the lint checks that every `call`, `jmp` and `pcall` site the driver's trace finds
  (`tools/spc700.py`) outside the routine and its sub-entries is named there by its ARAM
  address (`$0299`). Table dispatch (a pushed address and `ret`) is said in words.

## Layout

- One file per bank, `asm/bank<NN>/bank<NN>.asm`, in address order, grouped by subsystem with a
  banner per cluster.
- Shared names in `asm/include/`: `ram_engine.inc` / `constants_engine.inc` for banks $00,
  $C0 and $FD; `ram_battle.inc` / `constants_battle.inc` for the battle engine. Battle names
  start with `Battle`, `Battler`, `Pc`, `Enemy`, `Tech`, `Item` or `Sfx`, and engine names never
  do. asar lets a later define silently replace an earlier one, so the prefixes keep the two
  sets apart.
- Each define gets a one-line comment: width, meaning, how it was inferred.
