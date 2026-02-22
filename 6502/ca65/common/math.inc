; 16-bit addition subroutine
; Adds the 16-bit value in TEMP1 (low byte), TEMP1+1 (high byte)
; to the 16-bit value in TEMP2 (low byte), TEMP2+1 (high byte).
; The result is stored in TEMP1.
; Destroys A, X, and processor status flags.
_add16:
    lda temp1
    clc
    adc temp2
    sta temp1

    lda temp1+1
    adc temp2+1
    sta temp1+1
    rts

; 16-bit subtraction subroutine
; Subtracts the 16-bit value in TEMP2 (low byte), TEMP2+1 (high byte)
; from the 16-bit value in TEMP1 (low byte), TEMP1+1 (high byte).
; The result is stored in TEMP1.
_sub16:
sub16:
    lda temp1
    sec
    sbc temp2
    sta temp1

    lda temp1+1
    sbc temp2+1
    sta temp1+1
    rts

;temp1: .res 2
;temp2: .res 2