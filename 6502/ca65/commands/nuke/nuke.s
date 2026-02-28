; nuke.s - Delete the file "ABC.S" (with quotes)
; Usage: NUKE

.import pico_send_request
.import CMD_ID, ARG_LEN, LAST_STATUS, ARG_BUFF

CMD_FS_REMOVE = $16

t_str_ptr1 = $5A
OUTCH = $FFEF
CRLF  = $FED1

.segment "HEADER"
    .word $0800

.segment "CODE"
start:
    ; Print "Nuking..."
    lda #<msg_nuke
    sta t_str_ptr1
    lda #>msg_nuke
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF

    ; Copy hardcoded filename to ARG_BUFF
    ldx #0
@copy:
    lda filename, x
    sta ARG_BUFF, x
    beq @done_copy
    inx
    jmp @copy
@done_copy:
    stx ARG_LEN

    ; Send Command
    lda #CMD_FS_REMOVE
    sta CMD_ID
    jsr pico_send_request

    ; Check Status
    lda LAST_STATUS
    cmp #$00
    beq @success
    
    lda #'!' ; Error
    jsr OUTCH
    jsr CRLF
    rts

@success:
    lda #'O'
    jsr OUTCH
    lda #'K'
    jsr OUTCH
    jsr CRLF
    rts

print_string:
    ldy #0
@loop:
    lda (t_str_ptr1), y
    beq @rts
    jsr OUTCH
    iny
    jmp @loop
@rts: rts

.segment "RODATA"
msg_nuke: .byte "Nuking ", $22, "ABC.S", $22, "...", 0
;filename: .byte $22, 'A', 'B', 'C', '.', 'S', $22, 0
filename: .byte $22,$7f,$41,$42,$43,$2e,$53,$22
