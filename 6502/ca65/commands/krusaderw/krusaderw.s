; krusaderw.s - Warm Start Krusader Assembler
; Usage: KRUSADERW

WARM_START = $F01C

.segment "HEADER"
    .word $0800

.segment "CODE"
start:
    jmp WARM_START