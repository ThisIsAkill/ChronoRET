; ============================================================
; hardware.inc — SNES hardware register constants
;
; All addresses are SNES bus addresses.
; Include guard prevents double-definition when multiple bank
; files include this file.
; ============================================================
!hardware_inc ?= 0
if !hardware_inc == 0
!hardware_inc = 1

; ------------------------------------------------------------
; PPU — Picture Processing Unit ($2100–$213F)
; ------------------------------------------------------------
INIDISP  = $2100   ; Screen display (brightness + forced blank)
OBSEL    = $2101   ; OAM size and base address select
OAMADDL  = $2102   ; OAM address (low byte)
OAMADDH  = $2103   ; OAM address (high byte) + priority rotation
OAMDATA  = $2104   ; OAM data write port

BGMODE   = $2105   ; BG mode (0–7) and character sizes
MOSAIC   = $2106   ; Mosaic size and BG enable
BG1SC    = $2107   ; BG1 tilemap base address + size
BG2SC    = $2108   ; BG2 tilemap base address + size
BG3SC    = $2109   ; BG3 tilemap base address + size
BG4SC    = $210A   ; BG4 tilemap base address + size
BG12NBA  = $210B   ; BG1/2 character data base addresses
BG34NBA  = $210C   ; BG3/4 character data base addresses

BG1HOFS  = $210D   ; BG1 horizontal scroll (write twice: lo then hi)
BG1VOFS  = $210E   ; BG1 vertical scroll
BG2HOFS  = $210F   ; BG2 horizontal scroll
BG2VOFS  = $2110   ; BG2 vertical scroll
BG3HOFS  = $2111   ; BG3 horizontal scroll
BG3VOFS  = $2112   ; BG3 vertical scroll
BG4HOFS  = $2113   ; BG4 horizontal scroll
BG4VOFS  = $2114   ; BG4 vertical scroll

VMAIN    = $2115   ; VRAM address increment mode
VMADDL   = $2116   ; VRAM address (low byte)
VMADDH   = $2117   ; VRAM address (high byte)
VMDATAL  = $2118   ; VRAM data write (low byte)
VMDATAH  = $2119   ; VRAM data write (high byte)

M7SEL    = $211A   ; Mode 7 settings (flip, fill)
M7A      = $211B   ; Mode 7 matrix A (and multiply operand)
M7B      = $211C   ; Mode 7 matrix B (and multiply operand)
M7C      = $211D   ; Mode 7 matrix C
M7D      = $211E   ; Mode 7 matrix D
M7X      = $211F   ; Mode 7 center X
M7Y      = $2120   ; Mode 7 center Y

CGADD    = $2121   ; CGRAM (palette) address
CGDATA   = $2122   ; CGRAM data write

W12SEL   = $2123   ; Window 1/2 mask settings for BG1/2
W34SEL   = $2124   ; Window 1/2 mask settings for BG3/4
WOBJSEL  = $2125   ; Window 1/2 mask settings for OBJ/color window
WH0      = $2126   ; Window 1 left position
WH1      = $2127   ; Window 1 right position
WH2      = $2128   ; Window 2 left position
WH3      = $2129   ; Window 2 right position
WBGLOG   = $212A   ; Window mask logic for BGs
WOBJLOG  = $212B   ; Window mask logic for OBJ/color

TM       = $212C   ; Main screen layer enable
TS       = $212D   ; Subscreen layer enable
TMW      = $212E   ; Window mask for main screen
TSW      = $212F   ; Window mask for subscreen

CGWSEL   = $2130   ; Color math control (which screens)
CGADSUB  = $2131   ; Color math enable per layer
COLDATA  = $2132   ; Fixed color data (for color math)
SETINI   = $2133   ; Screen mode init (interlace, overscan, etc.)

; PPU read registers
MPYL     = $2134   ; Multiply result low  (M7A * M7B)
MPYM     = $2135   ; Multiply result mid
MPYH     = $2136   ; Multiply result high
SLHV     = $2137   ; Software H/V latch (read to latch H/V counter)
RDOAM    = $2138   ; OAM data read
RDVRAML  = $2139   ; VRAM data read (low byte, post-increment)
RDVRAMH  = $213A   ; VRAM data read (high byte)
RDCGRAM  = $213B   ; CGRAM data read
OPHCT    = $213C   ; Horizontal scanline counter (read twice)
OPVCT    = $213D   ; Vertical scanline counter (read twice)
STAT77   = $213E   ; PPU1 status and version
STAT78   = $213F   ; PPU2 status and version

; ------------------------------------------------------------
; APU — Audio Processing Unit ($2140–$2143)
; ------------------------------------------------------------
APUIO0   = $2140   ; APU communication port 0 (bidirectional)
APUIO1   = $2141   ; APU communication port 1
APUIO2   = $2142   ; APU communication port 2
APUIO3   = $2143   ; APU communication port 3

; ------------------------------------------------------------
; WRAM access registers ($2180–$2183)
; ------------------------------------------------------------
WMDATA   = $2180   ; WRAM data port (sequential access)
WMADDL   = $2181   ; WRAM address low byte
WMADDM   = $2182   ; WRAM address mid byte
WMADDH   = $2183   ; WRAM address high byte (bit 0 only)

; ------------------------------------------------------------
; CPU / Joypad ($4016–$4017)
; ------------------------------------------------------------
JOYA     = $4016   ; Joypad 1 data / strobe
JOYB     = $4017   ; Joypad 2 data / strobe (also: PPU status bits)

; ------------------------------------------------------------
; CPU internal registers ($4200–$421F)
; ------------------------------------------------------------
NMITIMEN = $4200   ; IRQ/NMI enable (NMI enable, IRQ mode, auto-joypad)
WRIO     = $4201   ; Programmable I/O port output
WRMPYA   = $4202   ; Multiplication: 8-bit multiplicand A
WRMPYB   = $4203   ; Multiplication: 8-bit multiplier B (triggers)
WRDIVL   = $4204   ; Division: 16-bit dividend low
WRDIVH   = $4205   ; Division: 16-bit dividend high
WRDIVB   = $4206   ; Division: 8-bit divisor (triggers)
HTIMEL   = $4207   ; H-count IRQ position low
HTIMEH   = $4208   ; H-count IRQ position high (bit 0 only)
VTIMEL   = $4209   ; V-count IRQ position low
VTIMEH   = $420A   ; V-count IRQ position high (bit 0 only)
MDMAEN   = $420B   ; DMA enable (bit N = channel N, one-shot)
HDMAEN   = $420C   ; HDMA enable (bit N = channel N, per-scanline)
MEMSEL   = $420D   ; ROM access speed (bit 0: 0=slow/2.68MHz, 1=fast/3.58MHz)

; CPU read registers
RDNMI    = $4210   ; NMI flag (bit 7) and CPU version (bits 3-0)
TIMEUP   = $4211   ; IRQ flag (bit 7, cleared on read)
HVBJOY   = $4212   ; H/V blank flags and auto-joypad busy
RDIO     = $4213   ; Programmable I/O port input
RDDIVL   = $4214   ; Division quotient low / multiply product low
RDDIVH   = $4215   ; Division quotient high / multiply product high
RDMPYL   = $4216   ; Division remainder low / multiply product low
RDMPYH   = $4217   ; Division remainder high
JOY1L    = $4218   ; Auto-joypad 1 data low
JOY1H    = $4219   ; Auto-joypad 1 data high
JOY2L    = $421A   ; Auto-joypad 2 data low
JOY2H    = $421B   ; Auto-joypad 2 data high
JOY3L    = $421C   ; Auto-joypad 3 data low (multitap)
JOY3H    = $421D   ; Auto-joypad 3 data high
JOY4L    = $421E   ; Auto-joypad 4 data low
JOY4H    = $421F   ; Auto-joypad 4 data high

; ------------------------------------------------------------
; DMA channels ($4300–$43FF, 8 channels × $10 registers)
; Use DMAP0..DMAP7, BBAD0..BBAD7, etc.
; ------------------------------------------------------------
DMAP0    = $4300   ; DMA channel 0 control
BBAD0    = $4301   ; Bus B (PPU bus) destination address, ch 0
A1T0L    = $4302   ; DMA source address low, ch 0
A1T0H    = $4303   ; DMA source address high, ch 0
A1B0     = $4304   ; DMA source bank, ch 0
DAS0L    = $4305   ; DMA transfer count low, ch 0
DAS0H    = $4306   ; DMA transfer count high, ch 0
DAS0B    = $4307   ; HDMA indirect bank, ch 0
A2A0L    = $4308   ; HDMA table address low, ch 0
A2A0H    = $4309   ; HDMA table address high, ch 0
NTRL0    = $430A   ; HDMA line counter, ch 0

DMAP1    = $4310   ; DMA channel 1 control
BBAD1    = $4311
A1T1L    = $4312
A1T1H    = $4313
A1B1     = $4314
DAS1L    = $4315
DAS1H    = $4316
DAS1B    = $4317
A2A1L    = $4318
A2A1H    = $4319
NTRL1    = $431A

DMAP2    = $4320
BBAD2    = $4321
A1T2L    = $4322
A1T2H    = $4323
A1B2     = $4324
DAS2L    = $4325
DAS2H    = $4326
DAS2B    = $4327
A2A2L    = $4328
A2A2H    = $4329
NTRL2    = $432A

DMAP3    = $4330
BBAD3    = $4331
A1T3L    = $4332
A1T3H    = $4333
A1B3     = $4334
DAS3L    = $4335
DAS3H    = $4336
DAS3B    = $4337
A2A3L    = $4338
A2A3H    = $4339
NTRL3    = $433A

DMAP4    = $4340
BBAD4    = $4341
A1T4L    = $4342
A1T4H    = $4343
A1B4     = $4344
DAS4L    = $4345
DAS4H    = $4346
DAS4B    = $4347
A2A4L    = $4348
A2A4H    = $4349
NTRL4    = $434A

DMAP5    = $4350
BBAD5    = $4351
A1T5L    = $4352
A1T5H    = $4353
A1B5     = $4354
DAS5L    = $4355
DAS5H    = $4356
DAS5B    = $4357
A2A5L    = $4358
A2A5H    = $4359
NTRL5    = $435A

DMAP6    = $4360
BBAD6    = $4361
A1T6L    = $4362
A1T6H    = $4363
A1B6     = $4364
DAS6L    = $4365
DAS6H    = $4366
DAS6B    = $4367
A2A6L    = $4368
A2A6H    = $4369
NTRL6    = $436A

DMAP7    = $4370
BBAD7    = $4371
A1T7L    = $4372
A1T7H    = $4373
A1B7     = $4374
DAS7L    = $4375
DAS7H    = $4376
DAS7B    = $4377
A2A7L    = $4378
A2A7H    = $4379
NTRL7    = $437A

; ------------------------------------------------------------
; Convenience bit masks
; ------------------------------------------------------------
; NMITIMEN bits
NMI_ENABLE      = %10000000
IRQ_H_ENABLE    = %00010000
IRQ_HV_ENABLE   = %00100000
AUTOJOY_ENABLE  = %00000001

; VMAIN bits
VRAM_INC_1      = %00000000   ; increment by 1 word after low byte access
VRAM_INC_32     = %00000001   ; increment by 32 words
VRAM_INC_128    = %00000010   ; increment by 128 words
VRAM_INC_HIGH   = %10000000   ; increment after HIGH byte access (vs low)

; INIDISP bits
FORCED_BLANK    = %10000000
BRIGHTNESS_MASK = %00001111

; BGMODE bits
BG_MODE_0       = %00000000
BG_MODE_1       = %00000001
BG_MODE_2       = %00000010
BG_MODE_3       = %00000011
BG_MODE_4       = %00000100
BG_MODE_5       = %00000101
BG_MODE_6       = %00000110
BG_MODE_7       = %00000111
BG3_HIGH_PRIO   = %00001000   ; mode 1 only: BG3 gets highest priority

; MDMAEN / HDMAEN channel bits
DMA_CH0         = %00000001
DMA_CH1         = %00000010
DMA_CH2         = %00000100
DMA_CH3         = %00001000
DMA_CH4         = %00010000
DMA_CH5         = %00100000
DMA_CH6         = %01000000
DMA_CH7         = %10000000

; DMAP transfer mode values (bits 2-0)
DMA_MODE_1BYTE       = %000   ; transfer 1 byte to 1 register
DMA_MODE_2BYTE       = %001   ; transfer 2 bytes to 2 consecutive regs
DMA_MODE_1BYTE_X2    = %010   ; transfer 1 byte to 1 reg, twice
DMA_MODE_4BYTE_ALT   = %011   ; transfer 4 bytes, alternating 2 regs
DMA_MODE_4BYTE       = %100   ; transfer 4 bytes to 4 consecutive regs

endif  ; !hardware_inc
