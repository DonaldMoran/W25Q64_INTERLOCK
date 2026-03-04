; basic.s - Jump to MSBASIC
; Usage: BASIC

; MSBASIC Cold Start is typically at $A147 in ROM
COLD_START = $A179
OUTCH      = $FFEF

.segment "HEADER"
    .word $0800

.segment "CODE"
start:
    jsr clear_screen
    
    ldy #0
@print_loop:
    lda splash_msg, y
    beq @start_basic
    jsr OUTCH
    iny
    jmp @print_loop

@start_basic:
    jmp COLD_START

clear_screen:
    lda #$1B
    jsr OUTCH
    lda #'['
    jsr OUTCH
    lda #'2'
    jsr OUTCH
    lda #'J'
    jsr OUTCH
    
    lda #$1B
    jsr OUTCH
    lda #'['
    jsr OUTCH
    lda #'H'
    jsr OUTCH
    rts

splash_msg:
    .byte "Don's DOS BASIC", $0D, $0A, 0
