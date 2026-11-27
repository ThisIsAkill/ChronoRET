#!/usr/bin/env python3
"""
music.py — The music sequences (the songs of Audio_SongTable and the two
sound-effect blocks for ARAM $2F00) as readable text, extracted from your
own ROM into the ignored build/assets/music/, and an assembler that rebuilds
their exact bytes, which the build incbins (DATA_PLAN.md, step 7).

No sequence is ever committed (README, "Legal"); this tool holds only how
the SPC700 driver reads them, and takes even that from the matched source:

  * What each byte of a track does is what the driver's score reader does
    with it: tools/spcwalk.py runs Spc_TrackStep on asm/spc700/driver.asm
    with the byte known and the rest of the track unknown. A byte below
    !Spc_SeqFirstCmd takes one byte and the track waits (a note, a tie or a
    rest, by !Spc_SeqFirstTie / !Spc_SeqFirstRest; its length in steps is
    Spc_DurationTable[byte % !Spc_NumDurations], a note's index byte /
    !Spc_NumDurations). A command ($C4-$FF) is named after its handler in
    Spc_SeqCmdTable (Spc_ and a Seq prefix dropped; a handler several
    commands share gets the command added) and has, from the walk:
      length     where it steps on (the bytes it read, when it does not),
      next       it steps on to the byte after it,
      jump       it can set the pointer to a word of two of its operands
                 plus the song's move (!Spc_Scratch00): written as a label,
      end        it can return to the track step's caller with the track
                 ended (the end commands; $E9/$EA with no track),
      elsewhere  it can set the pointer to a place its bytes do not give
                 (a loop's saved start, $E3; an effect's track, $E9/$EA).
    The result is kept in build/music/format.json (format.key holds the
    inputs' hash and the file's sha256: a file changed by hand is refused).
  * A song (Audio_SendSongData sends it to !AudioAram_Song): a length word,
    then the header the driver reads in Spc_StartSong: the origin word
    (!SpcSong_Origin; the track pointers and jump words assume the data at
    that address, the driver moves them by !AudioAram_Song + !SpcSong_Data
    - origin), the "no track" word (!SpcSong_NoTrack) and two sets of
    track pointers, !Spc_NumSongTracks bytes each (!SpcSong_Tracks; set A
    for commands $10/$14, B for $11/$15), then the data from !SpcSong_Data.
    A song may span two survey rows (at a bank end): one unit.
  * An effect block (Audio_UploadBlock2F00 sends it to !AudioAram_Block2F00):
    a length word, then the effect table (!Spc_SfxEntry bytes per effect,
    two track pointers; an effect number is one byte, Spc_SfxTrackPtr, so
    256 entries; a pointer with high byte 0 is no track, Spc_StartSfx),
    then the tracks. Its pointers are ARAM addresses. A jump in an effect
    track would be moved by the song's offset; the blocks have none, and
    one is refused.
  Track entries and jump targets are code; what they reach through next and
  jump is code; bytes nothing reaches are data, and may only follow a
  command that does not step on (an end, a jump, $E9/$EA).

The readable form, one file per song or block (build/assets/music/<unit>.mus):

  ; comments
  @song                       a song (or @effects: an effect block)
  @origin $8B18               the header's origin word
  @notrack $8FB3              its "no track" word
  @tracks A L_2024 none ...   set A (and B): 8 labels, none = the no-track word
  @effect $00 L_3300 none     an effect: its two pointers (none = $0000, or
                              $00XX for another word with high byte 0)
  L_2024:                     a label: its ARAM address once loaded
      Volume $64              a command by its handler's name and its operand
                              bytes; ->LABEL for a jump's word
      note 3 48               a note: its index (0-11) and its length in steps
      tie 48                  a tie, a rest: their length
      rest 24
  @bytes EB 00                bytes nothing reaches (data)

The assembler checks the structure, not only the bytes: each line has its
command's operands (the count, and ->LABEL exactly at a jump's word), every
label is referenced and every reference defined, the header comes before
the tracks, and the assembled bytes are walked again from the track
entries: every byte that walk reaches as a command must start a line,
every line must be reached, and @bytes may only follow a command that does
not step on. A unit cannot be kept as bytes: one the tool cannot follow
fails the extraction. The orphan at $CB:F164, which no table or pointer
reaches (where its tracks start is unknown), is not a music piece: it stays
extracted and is counted so.

    python3 tools/music.py check      disassemble every song and effect block
                                      afresh and assemble it back, every line
                                      checked: byte-exact?
    python3 tools/music.py format     print the command table the walk gives
"""

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
import spcwalk  # noqa: E402

CACHE_DIR = Path('build/music')            # the format cache and the assembled pieces (relative to the root)
EFFECT_BLOCKS = ('AudioRom_Block2F00', 'AudioRom_Block2F00Alt')
SONG_NOTE = re.compile(r'^song 0x([0-9A-Fa-f]{2}) \(Audio_SongTable entry')
KINDS = ('song', 'effects')


class MusicError(Exception):
    pass


# ── The format, from the driver ─────────────────────────────────────────────

def _format_key(root: Path) -> str:
    h = hashlib.sha256(b'music format v2\0')
    for p in [spcwalk.DRIVER] + spcwalk.INCLUDES:
        h.update((Path(root) / p).read_bytes())
    for tool in ('spcwalk.py', 'spc700.py', 'music.py'):
        h.update((ROOT / 'tools' / tool).read_bytes())
    return h.hexdigest()


class Format:
    """What each track byte does (spcwalk.derive), the command names and
    the song and effect layout constants, all from the source."""

    def __init__(self, data: dict):
        self.first_cmd, self.first_tie, self.first_rest = data['first_cmd'], data['first_tie'], data['first_rest']
        self.durations, self.nd = list(data['durations']), data['num_durations']
        self.cmds = {int(b): c for b, c in data['commands'].items() if int(b) >= self.first_cmd}
        self.layout = dict(data['layout'])
        if len(self.durations) != self.nd or len(set(self.durations)) != self.nd:
            raise MusicError('Spc_DurationTable is not !Spc_NumDurations distinct lengths')
        if self.first_tie != 12 * self.nd or self.first_rest != self.first_tie + self.nd \
                or self.first_cmd != self.first_rest + self.nd or sorted(self.cmds) != list(range(self.first_cmd, 256)):
            raise MusicError('the note, tie and rest ranges are not 12, 1 and 1 sets of the lengths')
        handlers = [c['handler'] for c in self.cmds.values()]
        self.names = {}
        for b in sorted(self.cmds):
            h = self.cmds[b]['handler']
            n = h[4:] if h.startswith('Spc_') else h
            n = n[3:] if n.startswith('Seq') and n[3:4].isupper() else n
            self.names[b] = n if handlers.count(h) == 1 else f'{n}_{b:02X}'
        self.by_name = {n: b for b, n in self.names.items()}

    def length(self, b: int) -> int:
        return 1 if b < self.first_cmd else self.cmds[b]['length']

    def goes_on(self, b: int) -> bool:
        return b < self.first_cmd or self.cmds[b]['next']

    def jump(self, b: int):
        return None if b < self.first_cmd else self.cmds[b]['jump']


def derive_format(root: Path = ROOT) -> dict:
    root = Path(root)
    src = spcwalk.load_source(root)
    try:
        data = spcwalk.derive(src)
        d = src.define
        data['layout'] = {
            'song_aram': d('AudioAram_Song'), 'origin': d('SpcSong_Origin'), 'notrack': d('SpcSong_NoTrack'),
            'tracks': d('SpcSong_Tracks'), 'data': d('SpcSong_Data'),
            'num_tracks': d('Spc_NumSongTracks') // 2,          # (the define counts bytes)
            'set_a': d('Spc_SongSetA'), 'set_b': d('Spc_SongSetB'),
            'sfx_aram': d('AudioAram_Block2F00'), 'sfx_entry': d('Spc_SfxEntry'),
        }
    except spcwalk.WalkError as e:
        raise MusicError(f'the driver\'s score reader: {e}') from None
    data['commands'] = {str(b): c for b, c in data['commands'].items()}
    return data


def load_format(root: Path = ROOT) -> Format:
    """The format, from build/music/format.json when it is current, else
    derived afresh (seconds) and written there. A file whose sha256 is not
    the one written beside it is refused."""
    root = Path(root)
    data_f, key_f = root / CACHE_DIR / 'format.json', root / CACHE_DIR / 'format.key'
    key = _format_key(root)
    if data_f.exists() and key_f.exists():
        want, _, digest = key_f.read_text().partition(' ')
        if want == key:
            raw = data_f.read_bytes()
            if hashlib.sha256(raw).hexdigest() != digest.strip():
                raise MusicError(f'{data_f} is not what tools/music.py wrote (changed by hand?); delete it '
                                 f'and {key_f.name} to derive the format again')
            try:
                return Format(json.loads(raw))
            except (ValueError, KeyError, TypeError) as e:
                raise MusicError(f'{data_f}: not a format file ({e}); delete it to derive it again') from None
    raw = json.dumps(derive_format(root), sort_keys=True, separators=(',', ':')).encode()
    data_f.parent.mkdir(parents=True, exist_ok=True)
    data_f.write_bytes(raw)
    key_f.write_text(f'{key} {hashlib.sha256(raw).hexdigest()}')
    return Format(json.loads(raw))


# ── Units ───────────────────────────────────────────────────────────────────

def unit_of_row(row: dict, label: str):
    """(unit, kind) of a survey row that is a music piece, else None: a song
    of Audio_SongTable (unit AudioSong_XX, its rows in address order) or an
    effect block. The orphan at $CB:F164 is not one (see the docstring)."""
    if row['kind'] != 'music_sequence':
        return None
    m = SONG_NOTE.match(row['notes'])
    if m:
        return f'AudioSong_{m.group(1).upper()}', 'song'
    if label in EFFECT_BLOCKS:
        return label, 'effects'
    return None


def unit_pieces(pieces: list[dict]) -> dict[str, list[dict]]:
    """{unit: its pieces in address order} of the manifest's music pieces."""
    out: dict[str, list[dict]] = {}
    for p in pieces:
        if p['piece'] == 'music':
            out.setdefault(Path(p['asset']).stem, []).append(p)
    return {u: sorted(ps, key=lambda p: p['offset']) for u, ps in out.items()}


class Unit:
    """The bytes of a song or effect block and where they sit once loaded."""

    def __init__(self, kind: str, data: bytes, fmt: Format):
        if kind not in KINDS:
            raise MusicError(f'unknown kind {kind!r}')
        self.kind, self.data, self.fmt = kind, bytes(data), fmt
        L = fmt.layout
        if len(data) < 2 or (data[0] | data[1] << 8) != len(data) - 2:
            raise MusicError('the length word is not the size of what follows')
        self.body = self.data[2:]
        if kind == 'song':
            self.aram, self.head = L['song_aram'], L['data']
            if len(self.body) < self.head:
                raise MusicError('shorter than the song header')
            self.origin = self.word(L['origin'])
            self.notrack = self.word(L['notrack'])
            self.delta = (self.origin - (self.aram + self.head)) & 0xFFFF
        else:
            self.aram, self.head, self.delta = L['sfx_aram'], 256 * L['sfx_entry'], 0
            if len(self.body) < self.head:
                raise MusicError('shorter than the effect table')

    def word(self, at: int) -> int:
        return self.body[at] | self.body[at + 1] << 8

    def pos(self, word: int):
        """The body offset a pointer word names (None when outside the data)."""
        y = (word - self.delta - self.aram) & 0xFFFF
        return y if self.head <= y < len(self.body) else None

    def entry_words(self) -> list[tuple[str, int]]:
        """(name, offset in the body) of every track pointer of the header."""
        L = self.fmt.layout
        if self.kind == 'song':
            n, out = L['num_tracks'], []
            for s, end in (('A', L['set_a']), ('B', L['set_b'])):
                first = L['tracks'] + end - 2 * n
                out += [(f'{s}{t}', first + 2 * t) for t in range(n)]
            return out
        return [(f'{e}.{k}', e * L['sfx_entry'] + 2 * k) for e in range(256) for k in range(2)]

    def is_none(self, w: int) -> bool:
        return w == self.notrack if self.kind == 'song' else w >> 8 == 0

    def entries(self) -> list[int]:
        out = []
        for name, at in self.entry_words():
            w = self.word(at)
            if self.is_none(w):
                continue
            y = self.pos(w)
            if y is None:
                raise MusicError(f'track pointer {name} ${w:04X} is outside the data')
            out.append(y)
        return out


def walk(u: Unit) -> dict[int, int]:
    """{offset: length} of every command or note the tracks reach (next and
    jump from the entries); raises MusicError when two overlap, one runs
    past the data or a jump leaves it."""
    fmt, body = u.fmt, u.body
    reached: dict[int, int] = {}
    todo = u.entries()
    while todo:
        y = todo.pop()
        if y in reached:
            continue
        if y >= len(body):
            raise MusicError(f'${u.aram + y:04X}: a track runs past the data')
        b = body[y]
        n = fmt.length(b)
        if y + n > len(body):
            raise MusicError(f'${u.aram + y:04X}: {n} bytes run past the data')
        reached[y] = n
        if fmt.goes_on(b):
            todo.append(y + n)
        j = fmt.jump(b)
        if j is not None:
            if u.kind != 'song':
                raise MusicError(f'${u.aram + y:04X}: a jump in an effect track (moved by the song\'s offset)')
            w = body[y + j] | body[y + j + 1] << 8
            t = u.pos(w)
            if t is None:
                raise MusicError(f'${u.aram + y:04X}: a jump to ${w:04X}, outside the data')
            todo.append(t)
    end = -1
    for y in sorted(reached):
        if y < end:
            raise MusicError(f'${u.aram + y:04X}: reached inside the command before it')
        end = y + reached[y]
    return reached


def _label(u: Unit, y: int) -> str:
    return f'L_{(u.aram + y) & 0xFFFF:04X}'


def _ref_word(u: Unit, w: int, labels: dict[int, str]) -> str:
    if u.is_none(w):
        return 'none' if u.kind == 'song' or w == 0 else f'${w:04X}'
    return labels[u.pos(w)]


def _line(u: Unit, y: int, labels: dict[int, str]) -> str:
    fmt, b = u.fmt, u.body[y]
    if b < fmt.first_tie:
        return f'note {b // fmt.nd} {fmt.durations[b % fmt.nd]}'
    if b < fmt.first_rest:
        return f'tie {fmt.durations[b - fmt.first_tie]}'
    if b < fmt.first_cmd:
        return f'rest {fmt.durations[b - fmt.first_rest]}'
    n, j = fmt.length(b), fmt.jump(b)
    toks, k = [fmt.names[b]], 1
    while k < n:
        if k == j:
            toks.append('->' + labels[u.pos(u.body[y + k] | u.body[y + k + 1] << 8)])
            k += 2
        else:
            toks.append(f'${u.body[y + k]:02X}')
            k += 1
    return ' '.join(toks)


def render(u: Unit, title: str) -> str:
    """The readable file of a unit (raises MusicError when it cannot be
    followed, or bytes nothing reaches do not follow a command that stops)."""
    fmt, body = u.fmt, u.body
    reached = walk(u)
    targets = set(u.entries())
    for y in reached:
        j = fmt.jump(body[y])
        if j is not None:
            targets.add(u.pos(body[y + j] | body[y + j + 1] << 8))
    labels = {y: _label(u, y) for y in targets}
    out = [f'; {title}: {"a song" if u.kind == "song" else "a sound-effect block"}, disassembled from your own '
           f'ROM by tools/music.py',
           '; (never commit it). The build assembles it back into the bytes; the format is in tools/music.py.',
           '; This file is regenerated by extraction: an edit is lost when it runs again.']
    if u.kind == 'song':
        n = fmt.layout['num_tracks']
        out += ['@song', f'@origin ${u.origin:04X}', f'@notrack ${u.notrack:04X}']
        words = u.entry_words()
        for s in range(2):
            refs = [_ref_word(u, u.word(at), labels) for _, at in words[s * n:(s + 1) * n]]
            out.append(f'@tracks {"AB"[s]} ' + ' '.join(refs))
    else:
        out.append('@effects')
        for e in range(256):
            refs = [_ref_word(u, u.word(e * fmt.layout['sfx_entry'] + 2 * k), labels) for k in range(2)]
            out.append(f'@effect ${e:02X} ' + ' '.join(refs))
    y, last_goes_on = u.head, None
    while y < len(body):
        if y in labels:
            out.append(labels[y] + ':')
        if y in reached:
            out.append('    ' + _line(u, y, labels))
            last_goes_on = fmt.goes_on(body[y])
            y += reached[y]
            continue
        if last_goes_on is not False:
            raise MusicError(f'${u.aram + y:04X}: bytes nothing reaches that do not follow a command that stops')
        z = y
        while z < len(body) and z not in reached:
            z += 1
        chunk = body[y:z]
        for k in range(0, len(chunk), 16):
            out.append('@bytes ' + ' '.join(f'{c:02X}' for c in chunk[k:k + 16]))
        y, last_goes_on = z, None
    return '\n'.join(out) + '\n'


# ── The assembler ───────────────────────────────────────────────────────────

LABEL_LINE = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*):$')
REF = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*$')
BYTE = re.compile(r'^\$([0-9A-Fa-f]{2})$')
WORD = re.compile(r'^\$([0-9A-Fa-f]{4})$')
HEX = re.compile(r'^[0-9A-Fa-f]{2}$')


def _encode(w: list[str], fmt: Format, where: str) -> tuple[int, list[str]]:
    """(the byte, its operand tokens) of a line, checked against the format."""
    op = w[0]
    if op in ('note', 'tie', 'rest'):
        if len(w) != (3 if op == 'note' else 2) or not all(t.isdigit() for t in w[1:]):
            raise MusicError(f'{where}: {op} {"N " if op == "note" else ""}LENGTH')
        d = int(w[-1])
        if d not in fmt.durations:
            raise MusicError(f'{where}: {d} is not a length of Spc_DurationTable')
        k = fmt.durations.index(d)
        if op == 'note':
            n = int(w[1])
            if not 0 <= n < 12:
                raise MusicError(f'{where}: note {n}: notes are 0-11')
            return n * fmt.nd + k, []
        return (fmt.first_tie if op == 'tie' else fmt.first_rest) + k, []
    if op not in fmt.by_name:
        raise MusicError(f'{where}: {op!r} is not a command, note, tie or rest')
    b = fmt.by_name[op]
    n, j = fmt.length(b), fmt.jump(b)
    k = 1
    for t in w[1:]:
        if k == j:
            if not (t.startswith('->') and REF.match(t[2:])):
                raise MusicError(f'{where}: {op}\'s operand {k} is its jump: ->LABEL')
            k += 2
        elif BYTE.match(t):
            k += 1
        else:
            raise MusicError(f'{where}: {t!r}: {op} takes $XX bytes' + (f' and ->LABEL at operand {j}' if j else ''))
    if k != n:
        raise MusicError(f'{where}: {op} takes {n - 1} operand bytes; the line gives {k - 1}')
    return b, w[1:]


def assemble(text: str, fmt: Format, name: str = '<music>') -> bytes:
    """The bytes (length word included) of a readable file, its structure
    checked (see the docstring)."""
    lines = []
    for no, raw in enumerate(text.split('\n'), 1):
        code = raw.split(';', 1)[0].strip()
        if code:
            lines.append((f'{name}:{no}', code.split()))
    if not lines or lines[0][1] not in (['@song'], ['@effects']):
        raise MusicError(f'{name}: the first line must be @song or @effects')
    kind = 'song' if lines[0][1] == ['@song'] else 'effects'
    L = fmt.layout
    head: dict = {}
    body_lines: list = []
    n_eff = 0
    for where, w in lines[1:]:
        d = w[0]
        if d == '@raw':
            raise MusicError(f'{where}: a song or effect block cannot be kept as bytes')
        if not d.startswith('@') or d == '@bytes':
            body_lines.append((where, w))
            continue
        if body_lines:
            raise MusicError(f'{where}: {d} after the tracks have begun')
        if kind == 'song' and d in ('@origin', '@notrack'):
            if len(w) != 2 or not WORD.match(w[1]) or d in head:
                raise MusicError(f'{where}: {d} $XXXX, once')
            head[d] = int(w[1][1:], 16)
        elif kind == 'song' and d == '@tracks':
            if len(w) != 2 + L['num_tracks'] or w[1] not in ('A', 'B') or ('@tracks', w[1]) in head:
                raise MusicError(f'{where}: @tracks A|B and {L["num_tracks"]} track labels or none, once a set')
            head[('@tracks', w[1])] = (where, w[2:])
        elif kind == 'effects' and d == '@effect':
            if len(w) != 4 or not BYTE.match(w[1]):
                raise MusicError(f'{where}: @effect $NN P0 P1')
            if int(w[1][1:], 16) != n_eff:
                raise MusicError(f'{where}: effect {w[1]} out of order')
            head[('@effect', n_eff)] = (where, w[2:])
            n_eff += 1
        else:
            raise MusicError(f'{where}: unknown or misplaced {d}')
    if kind == 'song':
        for k in ('@origin', '@notrack', ('@tracks', 'A'), ('@tracks', 'B')):
            if k not in head:
                raise MusicError(f'{name}: no {k if isinstance(k, str) else " ".join(k)}')
        start, aram = L['data'], L['song_aram']
        delta = (head['@origin'] - (aram + start)) & 0xFFFF
    else:
        if n_eff != 256:
            raise MusicError(f'{name}: the effect table needs 256 @effect lines, not {n_eff}')
        start, aram, delta = 256 * L['sfx_entry'], L['sfx_aram'], 0

    # labels and places
    labels: dict[str, int] = {}
    defined_at: dict[str, str] = {}
    items = []                                   # (where, 'line' | 'bytes', words, offset)
    pending: list[tuple[str, str]] = []
    pos = start
    for where, w in body_lines:
        m = LABEL_LINE.match(w[0])
        if m and len(w) == 1:
            lab = m.group(1)
            if lab in labels:
                raise MusicError(f'{where}: label {lab} twice')
            labels[lab], defined_at[lab] = pos, where
            pending.append((where, lab))
            continue
        if w[0] == '@bytes':
            if pending:
                raise MusicError(f'{where}: label {pending[0][1]} on bytes nothing reaches')
            if len(w) == 1 or not all(HEX.match(t) for t in w[1:]):
                raise MusicError(f'{where}: @bytes takes hex bytes')
            items.append((where, 'bytes', w, pos))
            pos += len(w) - 1
            continue
        pending = []
        _, ops = _encode(w, fmt, where)
        items.append((where, 'line', w, pos))
        pos += 1 + sum(2 if t.startswith('->') else 1 for t in ops)
    if pending:
        raise MusicError(f'{pending[0][0]}: label {pending[0][1]} at the end, on nothing')

    used: set[str] = set()

    def word_of(ref: str, where: str) -> int:
        if ref not in labels:
            raise MusicError(f'{where}: no label {ref}')
        used.add(ref)
        return (labels[ref] + aram + delta) & 0xFFFF

    body = bytearray(start)
    starts: dict[int, tuple[str, int]] = {}
    jumps = []
    for where, k, w, at in items:
        if k == 'bytes':
            body += bytes(int(t, 16) for t in w[1:])
            continue
        b, ops = _encode(w, fmt, where)
        out = bytearray([b])
        for t in ops:
            if t.startswith('->'):
                jumps.append((where, t[2:]))
                out += word_of(t[2:], where).to_bytes(2, 'little')
            else:
                out.append(int(t[1:], 16))
        starts[at] = (where, b)
        body += out
    if kind == 'song':
        body[L['origin']:L['origin'] + 2] = head['@origin'].to_bytes(2, 'little')
        body[L['notrack']:L['notrack'] + 2] = head['@notrack'].to_bytes(2, 'little')
        n = L['num_tracks']
        for s, end in (('A', L['set_a']), ('B', L['set_b'])):
            where, refs = head[('@tracks', s)]
            first = L['tracks'] + end - 2 * n
            for t, ref in enumerate(refs):
                v = head['@notrack'] if ref == 'none' else word_of(ref, where)
                if ref != 'none' and v == head['@notrack']:
                    raise MusicError(f'{where}: {ref} is the "no track" word')
                body[first + 2 * t:first + 2 * t + 2] = v.to_bytes(2, 'little')
    else:
        for e in range(256):
            where, refs = head[('@effect', e)]
            for k, ref in enumerate(refs):
                if ref == 'none':
                    v = 0
                elif WORD.match(ref):
                    v = int(ref[1:], 16)
                    if v >> 8 or v == 0:
                        raise MusicError(f'{where}: {ref}: a word is written only for no track with high byte '
                                         f'0 other than $0000 (none); name a label')
                else:
                    v = word_of(ref, where)     # (never high byte 0: the tracks follow the table)
                at = e * L['sfx_entry'] + 2 * k
                body[at:at + 2] = v.to_bytes(2, 'little')
    for lab in labels:
        if lab not in used:
            raise MusicError(f'{defined_at[lab]}: label {lab} is not a track entry or a jump target')
    data = len(body).to_bytes(2, 'little') + bytes(body)

    # the structure: walk the result as the driver reads it
    try:
        reached = walk(Unit(kind, data, fmt))
    except MusicError as e:
        raise MusicError(f'{name}: {e}') from None
    # (a jump always lands on a line: a label stands before a line, since
    # one before @bytes or at the end is refused above)
    for y in sorted(reached):
        if y not in starts:
            raise MusicError(f'{name}: ${aram + y:04X} is reached as a command but is not a line\'s start '
                             f'(bytes written as data, or operands regrouped)')
    for y, (where, b) in sorted(starts.items()):
        if y not in reached:
            raise MusicError(f'{where}: no track reaches this line')
    # @bytes after a command that steps on are reached, and refused above;
    # this also refuses them before the first line
    prev = None
    for where, k, w, at in items:
        if k == 'line':
            prev = starts[at][1]
        elif prev is None or fmt.goes_on(prev):
            raise MusicError(f'{where}: @bytes must follow a command that does not step on')
    return data


# ── Extraction, the build, the figures ──────────────────────────────────────

def unit_data(rom: bytes, ps: list[dict]) -> bytes:
    return b''.join(rom[p['offset']:p['stop']] for p in ps)


def unit_kind(ps: list[dict]) -> str:
    return ps[0]['param'].split(',')[0]


def extract_unit(unit: str, rom: bytes, ps: list[dict], fmt: Format) -> str:
    """The readable file of a unit, checked to assemble back."""
    data = unit_data(rom, ps)
    try:
        text = render(Unit(unit_kind(ps), data, fmt), unit)
        back = assemble(text, fmt, unit)
    except MusicError as e:
        raise MusicError(f'{unit}: {e}') from None
    if back != data:
        raise MusicError(f'{unit}: the disassembly does not assemble to the same bytes')
    return text


def assemble_unit(unit: str, text: str, ps: list[dict], fmt: Format) -> dict[str, bytes]:
    """{label: bytes} of the unit's pieces, split in address order."""
    data = assemble(text, fmt, unit)
    out, k = {}, 0
    for p in ps:
        n = p['stop'] - p['offset']
        out[p['label']] = data[k:k + n]
        k += n
    if k != len(data):
        raise MusicError(f'{unit}: {len(data)} B, its pieces {k} B')
    return out


def stats(text: str) -> dict:
    """{'data': bytes in @bytes (nothing reaches them)}."""
    return {'data': sum(len(line.split()) - 1 for line in text.split('\n') if line.startswith('@bytes '))}


def check(rom: bytes, root: Path = ROOT, quiet: bool = True) -> list[str]:
    """Disassemble every music unit afresh and assemble it back: the problems."""
    import extract_data
    fmt = load_format(root)
    problems, n = [], 0
    for unit, ps in sorted(unit_pieces(extract_data.read_manifest()).items()):
        try:
            out = assemble_unit(unit, extract_unit(unit, rom, ps, fmt), ps, fmt)
        except MusicError as e:
            problems.append(str(e))
            continue
        problems += [f'{p["label"]}: does not assemble back to its bytes' for p in ps
                     if out[p['label']] != rom[p['offset']:p['stop']]]
        n += 1
    if not quiet:
        print(f'music: {n} songs and effect blocks disassembled and assembled back')
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('command', choices=('check', 'format'))
    args = ap.parse_args()
    import extract_data
    try:
        if args.command == 'format':
            fmt = load_format()
            for b in sorted(fmt.cmds):
                c = fmt.cmds[b]
                flow = [k for k in ('next', 'end', 'elsewhere') if c[k]] + ([f'jump@{c["jump"]}'] if c['jump'] else [])
                print(f'${b:02X} {fmt.names[b]:<18} {c["length"]} B  {" ".join(flow)}')
            return 0
        problems = check(extract_data.read_rom(), quiet=False)
    except (MusicError, extract_data.DataError) as e:
        print(f'music: {e}', file=sys.stderr)
        return 1
    for p in problems:
        print(f'music: {p}', file=sys.stderr)
    if problems:
        return 1
    print('OK: every song and effect block disassembles and assembles back byte-exact, every line checked '
          'against the driver\'s score reader')
    return 0


if __name__ == '__main__':
    sys.exit(main())
