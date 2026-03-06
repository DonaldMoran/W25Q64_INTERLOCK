; basicw.s - Warm Start MSBASIC
; Usage: BASICW

; MSBASIC Cold Start
COLD_START = $A179
; MSBASIC Warm Start Vector (stored in ZP)
WARM_VECTOR = $0003

.segment "HEADER"
    .word $0800

.segment "CODE"
start:
    ; Check if Warm Start Vector is valid.
    ; We check the high byte ($04). If it is 0, it implies the address is in
    ; Zero Page ($00xx), which is invalid for code execution.
    ; This catches the uninitialized case (00 00).
    lda WARM_VECTOR+1
    beq @cold_start

    ; Jump indirect via the vector at $0003/$0004
    jmp (WARM_VECTOR)

@cold_start:
    ; Vector invalid, fall back to Cold Start
    jmp COLD_START