; ============================================================
; The bank $C3 module (BankC3_PackedModule), unpacked
; WRAM $7E:3000-$7E:B57E ($857F bytes), stored packed at $C3:1313-$7A2B
;
; C3_BootModule unpacks the module with Decomp_ToWram to $7E:3000
; (C3Mod_Code) and jumps there; it is the jet-bike race program, about
; half code. Its source is matched here in unpacked form: this file is
; assembled on its own (asar, base $7E:3000) by tools/c3pack.py, which
; packs the result with the original packer's rules back to the 26,393
; bytes in ROM (build/c3pack/module.lz, incbin'd by bankC3.asm). The
; source must write every byte; what is not matched yet is incbin'd
; from the ROM's module, unpacked by the same tool to
; build/c3pack/rom_module.bin, as unmatched bytes are left as ROM bytes
; elsewhere.
;
; Labels take the WRAM address ($7E:xxxx); %C3ModOrg(addr) starts a
; block at one.
; ============================================================

incsrc "module.inc"

%C3ModOrg($7E3000)
C3Mod_Module:               ; not matched yet: the ROM's bytes
    %C3ModRomBytes($7E3000, $7EB57F)
