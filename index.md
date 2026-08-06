# Chrono Trigger (SNES) — Matching Decompilation

An in-progress byte-exact reconstruction of the original 1995 SNES release of Chrono Trigger.
The goal is hand-labeled 65816 assembly that assembles back to a byte-identical ROM.

## Current Progress

| Bank | Region | Status | Bytes |
|------|--------|--------|-------|
| `$00` | Boot vectors, wave tables, ROM header | Partial | 256 |
| `$C0` | Engine core — GameLoop, VBlank, OAM | Partial | 435 |
| `$FD` | MainInit (CPU/PPU init sequence) | Partial | 215 |
| Everything else | — | Unmapped | 0 |

**Total matched: ~1009 bytes out of 4,194,304 (0.024%)**

This is instruction-count verified via `make diff` — the built ROM is byte-identical to the original for every matched byte.

## Quick Links

- [Devlog](devlog/index.md) — session-by-session notes in plain English
- [Bank Map](docs/BANK_MAP.md) — what lives where in the ROM
- [Progress](docs/PROGRESS.md) — matched function table
- [Glossary](devlog/posts/glossary.md) — SNES/65816 terms explained
- [Contributing](CONTRIBUTING.md) — how to help

## Legal

Tools and source only. No ROM data, no copyrighted assets. You need your own legally-dumped copy of Chrono Trigger (US 1.0).

```
SHA-256: 06d1c2b06b716052c5596aaa0c2e5632a027fee1a9a28439e509f813c30829a9
```
