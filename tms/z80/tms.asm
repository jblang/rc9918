; TMS9918A graphics subroutines
; Copyright 2018 J.B. Langston
;
; Permission is hereby granted, free of charge, to any person obtaining a 
; copy of this software and associated documentation files (the "Software"), 
; to deal in the Software without restriction, including without limitation 
; the rights to use, copy, modify, merge, publish, distribute, sublicense, 
; and/or sell copies of the Software, and to permit persons to whom the 
; Software is furnished to do so, subject to the following conditions:
; 
; The above copyright notice and this permission notice shall be included in
; all copies or substantial portions of the Software.
; 
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING 
; FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
; DEALINGS IN THE SOFTWARE.

PUBLIC asm_tmsintenable
PUBLIC asm_tmsintdisable

PUBLIC asm_tmswrite
PUBLIC asm_tmsfill

PUBLIC asm_tmsbackground
PUBLIC asm_tmstextcolor
PUBLIC asm_tmstextpos
PUBLIC asm_tmsstrout
PUBLIC asm_tmschrrpt
PUBLIC asm_tmschrout

PUBLIC asm_tmspixelop
PUBLIC asm_tmsplotpixel
PUBLIC asm_tmspixelcolor

PUBLIC asm_tmsmulticolor
PUBLIC asm_tmsbitmap
PUBLIC asm_tmstextmode
PUBLIC asm_tmstile

; ---------------------------------------------------------------------------
; configuration parameters

tmsram:         equ $be                 ; TMS9918A VRAM port
tmsreg:         equ $bf                 ; TMS9918A register port

tmswait:        equ 1                   ; wait divisor

; How this works: in the worst case scenario, the TMS9918A needs a delay of
; at least 8us between VRAM accesses from the CPU.  I have counted CPU cycles
; used by the code in this library and when the code doesn't produce enough
; of a delay between memory accesses naturally, I inserted nops to increase
; the delay.  The maximum number of nops added assume a 10MHz clock. When
; using a slower clock, fewer nops would be required.  tmswait is used as
; the divisor when calculating the number of nops, so a higher divisor 
; results in fewer nops being inserted into the code. Conservative values:
;
;    1 for <= 10 MHz
;    2 for <= 5 MHz
;    3 for <= 3.33 MHz
;    ... and so on

; ---------------------------------------------------------------------------
; register constants

tmswritebit:    equ $40                 ; bit to indicate memory write
tmsregbit:      equ $80                 ; bit to indicate register write

tmsctrl0:       equ 0                   ; control bits
tmsmode3:       equ 1                   ;       mode bit 3
tmsextvid:      equ 0                   ;       external video

tmsctrl1:       equ 1                   ; control bits
tms4k16k:       equ 7                   ;       4/16K RAM
tmsblank:       equ 6                   ;       screen blank
tmsinten:       equ 5                   ;       interrupt enable
tmsmode1:       equ 4                   ;       mode bit 1
tmsmode2:       equ 3                   ;       mode bit 2
tmssprsize:     equ 1                   ;       sprite size
tmssprmag:      equ 0                   ;       sprite magnification

tmsnametbl:     equ 2                   ; name table location (* $400)
tmscolortbl:    equ 3                   ; color table location (* $40)
                                        ;       graphics 2 mode: MSB 0 = $0000, MSB 1 = $2000
tmspattern:     equ 4                   ; pattern table location (* $800)
tmsspriteattr:  equ 5                   ; sprite attribute table (* $80)
tmsspritepttn:  equ 6                   ; sprite pattern table (* $800)
tmscolor:       equ 7                   ; screen colors (upper = text, lower = background)

; ---------------------------------------------------------------------------
; color constants

tmstransparent: equ 0
tmsblack:       equ 1
tmsmedgreen:    equ 2
tmslightgreen:  equ 3
tmsdarkblue:    equ 4
tmslightblue:   equ 5
tmsdarkred:     equ 6
tmscyan:        equ 7
tmsmedred:      equ 8
tmslightred:    equ 9
tmsdarkyellow:  equ $A
tmslightyellow: equ $B
tmsdarkgreen:   equ $C
tmsmagenta:     equ $D
tmsgray:        equ $E
tmswhite:       equ $F

; ---------------------------------------------------------------------------
; register configuration routines

SECTION data_lib

; shadow copy of register values
tmsshadow:
        defs    8, 0

SECTION code_lib

; set a single register value
;       A = register value
;       E = register to set
asm_tmssetreg:
        ld      hl, tmsshadow           ; get shadow table address
        ld      d, 0
        add     hl, de                  ; add offset to selected register
        ld      (hl), a                 ; save to shadow slot
        out     (tmsreg), a             ; send to TMS
        ld      a, tmsregbit            ; select requested register
        or      e
        out     (tmsreg), a
        ret

; set the background color
;       A = requested color
asm_tmsbackground:
        and     $0F                     ; mask off high nybble
        ld      b, a                    ; save for later
        ld      a, (tmsshadow+tmscolor) ; get current colors
        and     $F0                     ; mask off old background
        or      b                       ; set new background
        ld      e, tmscolor
        jp      asm_tmssetreg           ; set the color

; enable vblank interrupts
asm_tmsintenable:
        ld      a, (tmsshadow+tmsctrl1) ; get current control register value
        set     tmsinten, a             ; set interrupt enable bit
        ld      e, tmsctrl1
        jp      asm_tmssetreg           ; save it back

; disable vblank interrupts
asm_tmsintdisable:
        ld      a, (tmsshadow+tmsctrl1) ; get current control register value
        res     tmsinten, a             ; clear interrupt enable bit
        ld      e, tmsctrl1
        jp      asm_tmssetreg           ; save it back

; configure tms from specified register table
;       HL = register table
asm_tmsconfig:
        ld      de, tmsshadow           ; start of shadow area
	    ld      c, 8                    ; 8 registers
regloop:
  	    ld      a, (hl)                 ; get register value from table
	    out     (tmsreg), a             ; send it to the TMS
	    ld      a, 8                    ; calculate current register number
	    sub     c
	    or      tmsregbit               ; set high bit to indicate a register
        ldi                             ; shadow, then inc pointers and dec counter
	    out     (tmsreg), a             ; send it to the TMS
        xor     a                       ; continue until count reaches 0
        or      c
	    jr      nz, regloop
	    ret

; ---------------------------------------------------------------------------
; memory access routines

SECTION code_lib

; set the next address of vram to write
;       DE = address
asm_tmswriteaddr:
        ld      a, e                    ; send lsb
        out     (tmsreg), a
        ld      a, d                    ; mask off msb to max of 16KB
        and     $3F
        or      $40                     ; set second highest bit to indicate write
        out     (tmsreg), a             ; send msb
        ret

; set the next address of vram to read
;       DE = address
asm_tmsreadaddr:
        ld      a, e                    ; send lsb
        out     (tmsreg), a
        ld      a, d                    ; mask off msb to max of 16KB
        and     $3F
        out     (tmsreg), a             ; send msb
        ret

; copy bytes from ram to vram
;       HL = ram source address
;       DE = vram destination address
;       BC = byte count
asm_tmswrite:
        call    asm_tmswriteaddr        ; set the starting address
writeloop:
        ld      a, (hl)                 ; get the current byte from ram
        out     (tmsram), a             ; send it to vram
        defs    11/tmswait, 0           ; nops to waste time
        inc     hl                      ; next byte
        dec     bc                      ; continue until count is zero
        ld      a, b
        or      c
        jr      nz, writeloop
        ret

; fill a section of memory with a single value
;       A = value to fill
;       DE = vram destination address
;       BC = byte count
asm_tmsfill:
        push    af
        call    asm_tmswriteaddr        ; set the starting address
        pop     af
fillloop:
        out     (tmsram), a             ; send it to vram
        defs    11/tmswait, 0           ; nops to waste time
        dec     c
        jp      nz, fillloop
        djnz    fillloop                ; continue until count is zero
        ret

; ---------------------------------------------------------------------------
; text routines

SECTION code_lib

; set text color
;       A = requested color
asm_tmstextcolor:
        add     a, a                    ; shift text color into high nybble
        add     a, a
        add     a, a
        add     a, a
        ld      b, a                    ; save for later
        ld      a, (tmsshadow+tmscolor) ; get current colors
        and     $0F                     ; mask off old text color
        or      b                       ; set new text color
        ld      e, tmscolor
        jp      asm_tmssetreg           ; save it back

; set the address to place text at X/Y coordinate
;       A = X
;       E = Y
asm_tmstextpos:
        ld      d, 0
        ld      hl, 0
        add     hl, de                  ; Y x 1
        add     hl, hl                  ; Y x 2
        add     hl, hl                  ; Y x 4
        add     hl, de                  ; Y x 5
        add     hl, hl                  ; Y x 10
        add     hl, hl                  ; Y x 20
        add     hl, hl                  ; Y x 40
        ld      e, a
        add     hl, de                  ; add column for final address
        ex      de, hl                  ; send address to TMS
        call    asm_tmswriteaddr
        ret

; copy a null-terminated string to VRAM
;       HL = ram source address
asm_tmsstrout:
        ld      a, (hl)                 ; get the current byte from ram
        cp      0                       ; return when NULL is encountered
        ret     z
        out     (tmsram), a             ; send it to vram
        defs    14/tmswait, 0           ; nops to waste time
        inc     hl                      ; next byte
        jr      asm_tmsstrout

; repeat a character a certain number of times
;       A = character to output
;       B = count
asm_tmschrrpt:
        out     (tmsram), a
        defs    14/tmswait, 0
        djnz    asm_tmschrrpt
        ret

; output a character
;       A = character to output
asm_tmschrout:
        out     (tmsram), a
        defs    14/tmswait, 0
        ret

; ---------------------------------------------------------------------------
; bitmap routines

SECTION code_lib

tmsclearpixel:  equ $A02F               ; cpl, and b
tmssetpixel:    equ $00B0               ; nop, or b

; set operation for asm_tmsplotpixel to perform
;       HL = pixel operation (tmsclearpixel, tmssetpixel)
asm_tmspixelop:
        ld      (maskop), hl
        ret

; set or clear pixel at X, Y position
;       B = Y position
;       C = X position
asm_tmsplotpixel:
        ld      a, b                    ; don't plot Y coord > 191
        cp      192
        ret     nc
        call    asm_tmsxyaddr               ; get address for X/Y coord
        call    asm_tmsreadaddr         ; set read within pattern table
        ld      hl, masklookup          ; address of mask in table
        ld      a, c                    ; get lower 3 bits of X coord
        and     7
        ld      b, 0
        ld      c, a
        add     hl, bc
        ld      a, (hl)                 ; get mask in A
        ld      c, tmsram               ; get previous byte in B
        in      b, (c)
maskop:
        or      b                       ; mask bit in previous byte
        ld      b, a
        call    asm_tmswriteaddr        ; set write address within pattern table
        out     (c), b
        ret
masklookup:
        defb 80h, 40h, 20h, 10h, 8h, 4h, 2h, 1h

; set the color for a block of pixels in bitmap mode
;       B = Y position
;       C = X position
;       A = foreground/background color to set
asm_tmspixelcolor:
        call    asm_tmsxyaddr
        ld      hl, 2000h               ; add the color table base address
        add     hl, de
        ex      de, hl
        call    asm_tmswriteaddr        ; set write address within color table
        out     (tmsram), a             ; send to TMS
        ret

; calculate address byte containing X/Y coordinate
;       B = Y position
;       C = X position
;       returns address in DE
asm_tmsxyaddr:
        ld      a, b                    ; d = (y / 8)
        rrca
        rrca
        rrca
        and     1fh
        ld      d, a

        ld      a, c                    ; e = (x & f8)
        and     0f8h
        ld      e, a

        ld      a, b                    ; e += (y & 7)
        and     7
        or      e
        ld      e, a
        ret

; ---------------------------------------------------------------------------
; initialization routines

SECTION data_lib

; register values for blanked screen with 16KB RAM enabled
tmsblankreg:
        defb    $00, $80, $00, $00, $00, $00, $00, $00

SECTION code_lib

; reset registers and clear all 16KB of video memory
asm_tmsreset:
        ld      hl, tmsblankreg         ; blank the screen with 16KB enabled
        call    asm_tmsconfig
        ld      de, 0                   ; start a address 0000H
        call    asm_tmswriteaddr
        ld      de, $4000               ; write 16KB
        ld      bc, tmsram              ; writing 0s to vram
resetloop:
        out     (c), b                  ; send to vram
        dec     de                      ; continue until counter is 0
        ld      a, d
        or      e
        jr      nz, resetloop
        ret

SECTION data_lib

; register values for multicolor mode
asm_tmsmcreg:
	    defb      %00000000             ; external video disabled
        defb      %11001000             ; 16KB, display enabled, multicolor mode
        defb      $02                   ; name table at $8000
        defb      $00                   ; color table not used
        defb      $00                   ; pattern table at $0000
        defb      $76                   ; sprite attribute table at $3B00
        defb      $03                   ; sprite pattern table at $1800
        defb      $00                   ; black background

SECTION code_lib

; initialize tms for multicolor mode 
asm_tmsmulticolor:
        call    asm_tmsreset            ; blank the screen and clear vram
        ld      de, $0800               ; set name table start address
        call    asm_tmswriteaddr
        ld      d, 6                    ; nametable has 6 different sections
        ld      e, 0                    ; first section starts at 0
sectionloop:
        ld      c, 4                    ; each section has 4 identical lines
lineloop:
        ld      b, 32                   ; each line is 32 bytes long
        ld      a, e                    ; load the section's starting value
byteloop:
        out     (tmsram), a             ; output current name byte
        nop                             ; extra time to finish vram write
        inc     a                       ; increment name byte
        djnz    byteloop                ; next byte
        dec     c                       ; decrement line counter
        jr      nz, lineloop            ; next line
        ld      a, e                    ; next section's starting value is 32
        add     a, 32                   ; ...more than the previous section
        ld      e, a
        dec     d                       ; decrement section counter
        jr      nz, sectionloop         ; next section
        ld      hl, asm_tmsmcreg        ; switch to multicolor mode
        call    asm_tmsconfig
        ret

SECTION data_lib

; register values for bitmapped graphics
tmsbitmapreg:
        defb      %00000010             ; bitmap mode, no external video
        defb      %11000010             ; 16KB ram; enable display
        defb      $0e                   ; name table at $3800
        defb      $ff                   ; color table at $2000
        defb      $03                   ; pattern table at $0
        defb      $76                   ; sprite attribute table at $3B00
        defb      $03                   ; sprite pattern table at $1800
        defb      $01                   ; black background

SECTION code_lib

; initialize TMS for bitmapped graphics
asm_tmsbitmap:
        call    asm_tmsreset
        ld      de, $3800               ; initialize nametable with 3 sets
        call    asm_tmswriteaddr        ; of 256 bytes ranging from 00-FF
        ld      b, 3
        ld      a, 0
nameloop:
        out     (tmsram), a
        nop
        inc     a
        jr      nz, nameloop
        djnz    nameloop
        ld      hl, tmsbitmapreg        ; configure registers for bitmapped graphics
        call    asm_tmsconfig
        ret

SECTION data_lib

tmstilereg:
        defb      %00000000             ; graphics 1 mode, no external video
        defb      %11000000             ; 16K, enable display, disable interrupt
        defb      $05                   ; name table at $1400
        defb      $80                   ; color table at $2000
        defb      $01                   ; pattern table at $800
        defb      $20                   ; sprite attribute table at $1000
        defb      $00                   ; sprite pattern table at $0
        defb      $01                   ; black background

SECTION code_lib

; initialize TMS for tiled graphics
asm_tmstile:
        call    asm_tmsreset
        ld      hl, tmstilereg
        call    asm_tmsconfig
        ret

SECTION data_lib

tmstextreg:
        defb      %00000000               ; text mode, no external video
        defb      %11010000               ; 16K, Enable Display, Disable Interrupt
        defb      $00                     ; name table at $0000
        defb      $00                     ; color table not used
        defb      $01                     ; pattern table at $0800
        defb      $00                     ; sprite attribute table not used
        defb      $00                     ; sprite pattern table not used
        defb      $F1                     ; white text on black background

SECTION code_lib

; initialize TMS for text mode
;       HL = address of font to load
asm_tmstextmode:
        push    hl                      ; save address of font
        call    asm_tmsreset
        pop     hl                      ; load font into pattern table
        ld      de, $0800
        ld      bc, $0800
        call    asm_tmswrite
        ld hl,  tmstextreg
        call    asm_tmsconfig
        ret
