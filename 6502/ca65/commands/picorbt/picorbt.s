; picorbt.s - Reboot the Bridge Pico
; Usage: PICORBT

.import pico_send_request
.import CMD_ID, ARG_LEN, LAST_STATUS

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
CMD_RESET = $0F

; ---------------------------------------------------------------------------
; Zero Page
; ---------------------------------------------------------------------------
t_str_ptr1   = $5A
t_str_ptr2   = $5C
t_ptr_temp   = $5E

; ---------------------------------------------------------------------------
; System calls
; ---------------------------------------------------------------------------
OUTCH = $FFEF
CRLF  = $FED1

.segment "HEADER"
    .word $0800

.segment "CODE"
start:
    ; Save registers
    php
    pha
    txa
    pha
    tya
    pha

    ; Print "Rebooting..."
    lda #<msg_reboot
    sta t_str_ptr1
    lda #>msg_reboot
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF

    ; Send Command
    lda #CMD_RESET
    sta CMD_ID
    lda #0
    sta ARG_LEN
    
    jsr pico_send_request
    
    ; We expect the Pico to send OK and then die.
    ; The 6502 will return to the shell.

    ; Print "Waiting"
    lda #<msg_wait
    sta t_str_ptr1
    lda #>msg_wait
    sta t_str_ptr1+1
    jsr print_string

    lda #5          ; Reduced wait time significantly
    sta t_ptr_temp

wait_loop:
    ldy #0
delay_y:
    ldx #0
delay_x:
    dex
    bne delay_x
    dey
    bne delay_y
    
    lda #'.'
    jsr OUTCH
    
    dec t_ptr_temp
    bne wait_loop
    
    jsr CRLF
    
done:
    pla
    tay
    pla
    tax
    pla
    plp
    clc
    rts

; ---------------------------------------------------------------------------
; Helper: Print String
; ---------------------------------------------------------------------------
print_string:
    pha
    phy
    ldy #0
@loop:
    lda (t_str_ptr1), y
    beq @done
    jsr OUTCH
    iny
    jmp @loop
@done:
    ply
    pla
    rts

.segment "RODATA"
msg_reboot: .asciiz "Rebooting Bridge Pico..."
msg_wait:   .asciiz "Waiting"