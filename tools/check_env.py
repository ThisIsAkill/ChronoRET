#!/usr/bin/env python3
"""
check_env.py — Verify the local toolchain is ready for decomp work.
Run with: python3 tools/check_env.py
"""
import shutil
import sys

REQUIRED = {
    "asar": "65816 assembler — install via AUR: yay -S asar-git",
    "python3": "should already be present if you're running this",
}

OPTIONAL = {
    "bsnes": "cycle-accurate emulator for tracing — yay -S bsnes-hd-git",
    "mesen-s": "alternative debugger-focused emulator",
}


def check(name: str) -> bool:
    return shutil.which(name) is not None


def main() -> int:
    ok = True
    print("Required tools:")
    for tool, hint in REQUIRED.items():
        found = check(tool)
        status = "OK " if found else "MISSING"
        print(f"  [{status}] {tool}" + ("" if found else f"  — {hint}"))
        ok = ok and found

    print("\nOptional tools (for tracing/verification):")
    for tool, hint in OPTIONAL.items():
        found = check(tool)
        status = "OK " if found else "----"
        print(f"  [{status}] {tool}" + ("" if found else f"  — {hint}"))

    print()
    if ok:
        print("Environment looks ready. Drop a ROM in roms/ and run `make`.")
    else:
        print("Missing required tools — install them, then re-run this check.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
