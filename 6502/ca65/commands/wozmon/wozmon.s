; wozmon.s - Jump to wozmon monitor
; Usage: WOZMON

; Wozmon is located at $FF00 in ROM
WOZMON = $FF00

.segment "HEADER"
    .word $0800

.segment "CODE"
start:
    ; Sanitize CPU state before jumping
    cld
    sei

    jmp WOZMON