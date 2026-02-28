; krusader.s - Jump to Krusader Assembler
; Usage: KRUSADER

; Krusader is located at $F000 in ROM
KRUSADER_ENTRY = $F000

.segment "HEADER"
    .word $0800

.segment "CODE"
start:
    jmp KRUSADER_ENTRY