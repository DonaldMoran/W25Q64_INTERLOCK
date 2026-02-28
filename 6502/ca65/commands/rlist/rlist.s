; rlist.s - List remote directory from file server
; Usage: RLIST [remote_path]
;
; Workflow:
; 1. Read server.cfg to get IP:PORT
; 2. Download remote listing to /RLIST.TMP using CMD_NET_HTTP_GET
; 3. Display /RLIST.TMP using streaming (like TYPE)
; 4. Delete /RLIST.TMP

.include "../../common/pico_def.inc"

.import read_byte, send_byte, pico_send_request
.import ARG_BUFF, CMD_ID, ARG_LEN, LAST_STATUS, RESP_BUFF, RESP_LEN

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
INPUT_BUFFER = $0300
ACIA_DATA    = $5000

; ---------------------------------------------------------------------------
; Zero Page (Transient Safe Area $58-$5F)
; ---------------------------------------------------------------------------
t_ptr_temp   = $58 ; 2 bytes
t_count      = $5A ; 2 bytes for length
t_line_cnt   = $5C ; 1 byte for paging
t_cfg_ptr    = $5E ; 2 bytes for config parsing

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

    ; Initialize paging counter
    lda #0
    sta t_line_cnt

    ; -----------------------------------------------------------------------
    ; 1. Read server.cfg
    ; -----------------------------------------------------------------------
    ; We use CMD_FS_LOADMEM to read server.cfg into our local buffer
    lda #<str_server_cfg
    sta t_ptr_temp
    lda #>str_server_cfg
    sta t_ptr_temp+1
    
    ; Copy filename to ARG_BUFF
    ldy #0
@copy_cfg_name:
    lda (t_ptr_temp), y
    sta ARG_BUFF, y
    beq @cfg_name_done
    iny
    jmp @copy_cfg_name
@cfg_name_done:
    sty ARG_LEN

    lda #CMD_FS_LOADMEM
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @read_cfg
    
    ; Error: server.cfg not found
    lda #<msg_no_server
    jsr print_error_and_exit
    jmp done

@read_cfg:
    ; pico_send_request has already read the response into RESP_BUFF
    ; Copy RESP_BUFF to cfg_buffer
    ldx #0
@copy_cfg:
    cpx RESP_LEN ; Check low byte of length (server.cfg is small)
    bcs @copy_done
    lda RESP_BUFF, x
    sta cfg_buffer, x
    inx
    jmp @copy_cfg
@copy_done:
    lda #0
    sta cfg_buffer, x ; Null terminate

    ; -----------------------------------------------------------------------
    ; 2. Parse IP and Port from cfg_buffer (Format: IP:PORT)
    ; -----------------------------------------------------------------------
    ; Find ':' and replace with null
    ldx #0
@find_colon:
    lda cfg_buffer, x
    bne @check_colon
    jmp bad_cfg         ; End of string before colon
@check_colon:
    cmp #':'
    beq @found_colon
    inx
    jmp @find_colon

@found_colon:
    lda #0
    sta cfg_buffer, x   ; Terminate IP string
    inx
    stx t_cfg_ptr       ; Save index of Port string start (low byte is enough for small buffer)

    ; -----------------------------------------------------------------------
    ; 3. Construct CMD_NET_HTTP_GET Arguments
    ; Format: IP\0PORT\0REMOTE_PATH\0LOCAL_PATH\0
    ; -----------------------------------------------------------------------
    ldx #0 ; ARG_BUFF index

    ; Copy IP
    ldy #0
@pack_ip:
    lda cfg_buffer, y
    beq @pack_ip_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @pack_ip
@pack_ip_done:
    lda #0
    sta ARG_BUFF, x
    inx

    ; Copy Port
    ldy t_cfg_ptr
@pack_port:
    lda cfg_buffer, y
    beq @pack_port_done
    cmp #$0D ; Filter CR/LF if present in file
    beq @skip_cr
    cmp #$0A
    beq @skip_cr
    sta ARG_BUFF, x
    inx
@skip_cr:
    iny
    jmp @pack_port
@pack_port_done:
    lda #0
    sta ARG_BUFF, x
    inx

    ; Copy Remote Path (Argument or Default "/")
    lda #<INPUT_BUFFER
    sta t_ptr_temp
    lda #>INPUT_BUFFER
    sta t_ptr_temp+1

    jsr skip_word ; Skip "RUN"
    jsr skip_word ; Skip "/BIN/RLIST.BIN"

    ldy #0
    lda (t_ptr_temp), y
    beq @use_default_root

@copy_remote_path:
    lda (t_ptr_temp), y
    beq @remote_path_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_remote_path

@use_default_root:
    lda #'/'
    sta ARG_BUFF, x
    inx
@remote_path_done:
    lda #0
    sta ARG_BUFF, x
    inx

    ; Copy Local Temp Path
    ldy #0
@copy_local_path:
    lda str_tmp_file, y
    beq @local_path_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_local_path
@local_path_done:
    lda #0
    sta ARG_BUFF, x
    inx
    stx ARG_LEN

    ; -----------------------------------------------------------------------
    ; 4. Execute Download
    ; -----------------------------------------------------------------------
    lda #<msg_downloading
    jsr print_msg

    lda #CMD_NET_HTTP_GET
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @download_ok
    
    lda #<msg_fail
    jsr print_error_and_exit
    jmp done

@download_ok:
    ; -----------------------------------------------------------------------
    ; 5. Display File (Streaming)
    ; -----------------------------------------------------------------------
    jsr CRLF
    
    ; Setup ARG_BUFF with temp filename for LOADMEM
    ldx #0
@setup_read_arg:
    lda str_tmp_file, x
    sta ARG_BUFF, x
    beq @read_arg_done
    inx
    jmp @setup_read_arg
@read_arg_done:
    stx ARG_LEN

    ; Manual send for streaming (to handle >1KB and avoid buffering)
    lda #$FF
    sta VIA_DDRA

    lda #CMD_FS_LOADMEM
    jsr send_byte
    
    lda ARG_LEN
    jsr send_byte

    ldx #0
@send_args_loop:
    cpx ARG_LEN
    beq @send_args_done
    lda ARG_BUFF, x
    jsr send_byte
    inx
    jmp @send_args_loop
@send_args_done:

    ; Switch to input
    lda #$00
    sta VIA_DDRA

    jsr read_byte   ; Status
    cmp #STATUS_OK
    bne @display_fail

    ; Read Length
    lda #$00
    sta VIA_DDRA
    jsr read_byte
    sta t_count
    jsr read_byte
    sta t_count+1

@stream_loop:
    lda t_count
    ora t_count+1
    beq @stream_done

    jsr read_byte
    jsr paging_outch

    lda t_count
    bne @dec_stream
    dec t_count+1
@dec_stream:
    dec t_count
    jmp @stream_loop

@stream_done:
    lda #$FF
    sta VIA_DDRA

@display_fail:
    ; -----------------------------------------------------------------------
    ; 6. Cleanup (Delete Temp File)
    ; -----------------------------------------------------------------------
    ; ARG_BUFF already has str_tmp_file from step 5
    lda #CMD_FS_REMOVE
    sta CMD_ID
    jsr pico_send_request

done:
    ; Restore registers
    pla
    tay
    pla
    tax
    pla
    plp
    clc
    rts

bad_cfg:
    lda #<msg_bad_cfg
    jsr print_error_and_exit
    jmp done

; ---------------------------------------------------------------------------
; Helpers
; ---------------------------------------------------------------------------
skip_word:
    ldy #0
@skip_char:
    lda (t_ptr_temp), y
    beq @done
    cmp #' '
    beq @found_space
    inc t_ptr_temp
    bne @skip_char
    inc t_ptr_temp+1
    jmp @skip_char
@found_space:
@skip_spaces:
    lda (t_ptr_temp), y
    beq @done
    cmp #' '
    bne @done
    inc t_ptr_temp
    bne @skip_spaces
    inc t_ptr_temp+1
    jmp @skip_spaces
@done:
    rts

print_msg:
    sta t_ptr_temp
    stx t_ptr_temp+1 ; Assumes high byte passed in X or set before
    ; Fallthrough to print_string_zp

print_string_zp:
    ldy #0
@loop:
    lda (t_ptr_temp), y
    beq @done
    jsr OUTCH
    iny
    jmp @loop
@done:
    rts

print_error_and_exit:
    sta t_ptr_temp
    lda #>msg_fail ; Just use high byte of any string in RODATA
    sta t_ptr_temp+1
    jsr print_string_zp
    jsr CRLF
    rts

paging_outch:
    pha
    jsr OUTCH
    pla
    cmp #$0A
    bne @done
    jsr check_paging
@done:
    rts

check_paging:
    inc t_line_cnt
    lda t_line_cnt
    cmp #22
    bcc @done
    
    lda #<msg_more
    sta t_ptr_temp
    lda #>msg_more
    sta t_ptr_temp+1
    jsr print_string_zp
    
@wait_key:
    lda ACIA_DATA
    beq @wait_key
    jsr CRLF
    lda #0
    sta t_line_cnt
@done:
    rts

.segment "RODATA"
str_server_cfg:  .asciiz "server.cfg"
str_tmp_file:    .asciiz "/RLIST.TMP"
msg_no_server:   .asciiz "Error: server.cfg not found. Use SETSERVER first."
msg_bad_cfg:     .asciiz "Error: Invalid server.cfg format."
msg_downloading: .asciiz "Fetching list..."
msg_fail:        .asciiz "Failed."
msg_more:        .asciiz "--More--"

.segment "BSS"
cfg_buffer:      .res 64 ; Buffer for IP:PORT string