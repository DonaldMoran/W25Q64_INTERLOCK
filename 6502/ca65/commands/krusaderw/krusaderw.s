; krusaderw.s - Warm Start Krusader Assembler
; Usage: KRUSADERW

WARM_START = $F01C

.segment "HEADER"
    .word $0800

.segment "CODE"
start:
    ; Sanitize CPU state before jumping
    cld
    sei

    jmp WARM_START