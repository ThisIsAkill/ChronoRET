#!/usr/bin/env python3
"""
test_c3pack.py — Tests for the packer and unpacker of Decomp_ToWram's format
(tools/c3pack.py).

    python3 tools/test_c3pack.py          (from the repository root)

Without the ROM: packing then unpacking gives back the input, in both modes,
for inputs of every awkward length (empty, one partial group, whole groups,
longer than the ring buffer) and content (runs, repeats, noise), and the
framing follows the rules the docstring gives.

With the ROM: the module at $C3:1313 unpacks to $857F bytes and packs back
to its 26,393 bytes exactly; every pack C3Rom_PackPtrs points to that is in
the format (60 of 73 entries; 13 are raw blocks) is rebuilt byte for byte.
With asar too: the module's source builds to those bytes (tools/c3pack.py
build).
"""

import random
import shutil
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import c3pack  # noqa: E402

HAVE_ROM = c3pack.ROM_PATH.exists()
HAVE_ASAR = shutil.which('asar') is not None


def samples():
    rnd = random.Random(1995)
    noise = bytes(rnd.randrange(256) for _ in range(6000))
    text = b'CODE END C3 ' * 40
    return {
        'empty': b'',
        'one': b'\x42',
        'seven': bytes(range(7)),
        'eight': bytes(range(8)),
        'nine': bytes(range(9)),
        'run': bytes(5000),
        'repeats': text,
        'noise': noise,
        'mixed': noise[:3000] + text + noise[:2500] + bytes(300) + noise[1000:4000],
        'small alphabet': bytes(rnd.choice(b'\x00\x01\x02\xFF') for _ in range(9000)),
    }


class RoundTrip(unittest.TestCase):

    def test_round_trip(self):
        for mode in (12, 11):
            for name, data in samples().items():
                with self.subTest(mode=mode, sample=name):
                    packed = c3pack.pack(data, mode)
                    out, end, got_mode = c3pack.unpack(packed)
                    self.assertEqual(out, data)
                    self.assertEqual(end, len(packed))
                    self.assertEqual(got_mode, mode)

    def test_framing(self):
        # 9 literals: one full group (control $00) in segment 1, then a
        # marker with count 1, the last group (control $FE: bit 0 a literal,
        # the unused bits set) and the final marker.
        packed = c3pack.pack(bytes(range(9)))
        self.assertEqual(packed[:2], bytes([9, 0]))
        self.assertEqual(packed[2], 0x00)
        self.assertEqual(packed[11:14], bytes([0x01, 16, 0]))
        self.assertEqual(packed[14:], bytes([0xFE, 8, 0x00]))
        # whole groups only: segment 1 ends on the final marker
        self.assertEqual(c3pack.pack(bytes(range(8)))[-1], 0x00)
        self.assertEqual(c3pack.pack(bytes(range(8)), 11)[-1], 0x40)
        self.assertEqual(c3pack.pack(b''), bytes([0, 0, 0]))

    def test_greedy_reference(self):
        # a 4-byte pattern repeated: literals, then a reference of the
        # longest length (F = 18), then the 2 bytes left as literals (under
        # the threshold)
        items = c3pack.lzss_items(b'abcd' * 6)
        self.assertEqual(items[:4], [('L', c) for c in b'abcd'])
        self.assertEqual(items[4], ('R', 4, 18))
        self.assertEqual(items[5:], [('L', c) for c in b'cd'])


@unittest.skipUnless(HAVE_ROM, 'needs the ROM')
class Rom(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.rom = c3pack.ROM_PATH.read_bytes()

    def test_module(self):
        data, end, mode = c3pack.unpack(self.rom, c3pack.MODULE_ROM)
        self.assertEqual(len(data), c3pack.MODULE_SIZE)
        self.assertEqual(end - c3pack.MODULE_ROM, c3pack.MODULE_PACKED_SIZE)
        self.assertEqual(mode, 12)
        self.assertEqual(c3pack.pack(data), self.rom[c3pack.MODULE_ROM:end])

    def test_every_pack(self):
        same, differ, raw = c3pack.check_rom(self.rom)
        self.assertEqual(differ, [])
        self.assertEqual(len(same), 60)
        self.assertEqual(raw, [19, 20, 21, 37, 48, 49, 50, 51, 52, 54, 55, 56, 57])

    @unittest.skipUnless(HAVE_ASAR, 'needs asar')
    def test_build(self):
        out = c3pack.build()
        packed = self.rom[c3pack.MODULE_ROM:c3pack.MODULE_ROM + c3pack.MODULE_PACKED_SIZE]
        self.assertEqual(out.read_bytes(), packed)
        self.assertEqual(c3pack.MODULE_BIN.read_bytes(), c3pack.unpack(packed)[0])


if __name__ == '__main__':
    unittest.main(verbosity=1)
