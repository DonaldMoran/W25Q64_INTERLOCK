; krusader.s - Jump to Krusader Assembler
; Usage: KRUSADER

; Krusader is located at $F000 in ROM
KRUSADER_ENTRY = $F000
OUTCH          = $FFEF

.segment "HEADER"
    .word $0800

.segment "CODE"
start:
    jsr clear_screen
    jmp KRUSADER_ENTRY

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