; cls.s - Clear Screen
; Usage: CLS

; System calls
OUTCH = $FFEF

; ---------------------------------------------------------------------------
; HEADER - MUST be first (2-byte load address for RUN command)
; ---------------------------------------------------------------------------
.segment "HEADER"
    .word $0800        ; Load at $0800 (little-endian)

; ---------------------------------------------------------------------------
; CODE - Program starts here at $0800
; ---------------------------------------------------------------------------
.segment "CODE"

start:
    ; Standard Entry: Preserve registers and sanitize CPU state
    php
    pha
    txa
    pha
    tya
    pha
    cld
    sei

    ; Clear the screen with ANSI sequence
    jsr clear_screen

done:
    ; Standard Exit: Restore registers and return
    pla
    tay
    pla
    tax
    pla
    plp
    clc              ; Return with carry clear
    rts

;-----------------------------------------------------------
; clear_screen - Output ANSI escape sequence to clear screen
;-----------------------------------------------------------
clear_screen:
    ; Start with ESC character
    LDA #$1B           ; ESC character
    JSR OUTCH
    LDA #'['
    JSR OUTCH
    LDA #'2'
    JSR OUTCH
    LDA #'J'
    JSR OUTCH

    ; Move cursor to home position (1;1)
    LDA #$1B
    JSR OUTCH
    LDA #'['
    JSR OUTCH
    LDA #'H'
    JSR OUTCH
    RTS
