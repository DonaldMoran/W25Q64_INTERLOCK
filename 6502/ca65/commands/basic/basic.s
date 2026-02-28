; basic.s - Jump to MSBASIC
; Usage: BASIC

; MSBASIC Cold Start is typically at $A147 in ROM
COLD_START = $A174

.segment "HEADER"
    .word $0800

.segment "CODE"
start:
    jmp COLD_START