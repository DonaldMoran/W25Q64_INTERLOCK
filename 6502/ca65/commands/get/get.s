; get.s - Full working GET command for DDOS shell
; Location: 6502/ca65/commands/get/get.s

; ---------------------------------------------------------------------------
; External symbols
; ---------------------------------------------------------------------------
.import pico_send_request
.import CMD_ID, ARG_LEN, ARG_BUFF, LAST_STATUS, RESP_LEN, RESP_BUFF

; ---------------------------------------------------------------------------
; System calls
; ---------------------------------------------------------------------------
OUTCH = $FFEF    ; Print character in A
OUTHEX = $FFDC   ; Print hex byte in A
CRLF  = $FED1    ; Print CR/LF

; ---------------------------------------------------------------------------
; Zero page - Using shell's ptr_temp ($56-$57) which is saved/restored
; ---------------------------------------------------------------------------
ptr_temp = $56   ; 2 bytes - Shell's temporary pointer (safe to use)

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
CMD_FS_OPEN      = $12
CMD_FS_READ      = $13
CMD_FS_CLOSE     = $1C
CMD_NET_HTTP_GET = $34

STATUS_OK      = $00
STATUS_ERR     = $01
STATUS_NO_FILE = $02

INPUT_BUFFER  = $0300

; ---------------------------------------------------------------------------
; HEADER
; ---------------------------------------------------------------------------
.segment "HEADER"
    .word $0800

; ---------------------------------------------------------------------------
; CODE
; ---------------------------------------------------------------------------
.segment "CODE"

start:
    ; Preserve registers
    php
    pha
    txa
    pha
    tya
    pha

    ; Save CWD pointer from shell ($5E/$5F)
    lda $5E
    sta cwd_ptr
    lda $5F
    sta cwd_ptr+1

    ; -----------------------------------------------------------------------
    ; 1. Parse Arguments - Handle "RUN /BIN/GET.BIN filename" format
    ; -----------------------------------------------------------------------
    ldx #0
    
    ; Skip first word (RUN)
@skip_run:
    lda INPUT_BUFFER, x
    beq @goto_usage1
    cmp #' '
    beq @skip_run_space
    inx
    jmp @skip_run
@goto_usage1:
    jmp usage
    
@skip_run_space:
    inx
    
    ; Skip second word (/BIN/GET.BIN)
@skip_path:
    lda INPUT_BUFFER, x
    beq @goto_usage2
    cmp #' '
    beq @skip_path_space
    inx
    jmp @skip_path
@goto_usage2:
    jmp usage
    
@skip_path_space:
    inx
    
    ; Skip any spaces before filename
@skip_spaces:
    lda INPUT_BUFFER, x
    beq @goto_usage3
    cmp #' '
    bne @found_filename
    inx
    jmp @skip_spaces
@goto_usage3:
    jmp usage
    
@found_filename:
    ; X now points to start of actual filename
    stx remote_start
    
    ; Find end of filename
    ldy #0
@find_end:
    lda INPUT_BUFFER, x
    beq @filename_done
    cmp #' '
    beq @filename_done
    inx
    iny
    jmp @find_end
@filename_done:
    sty remote_len
    
    ; Check for second argument (local filename)
    lda INPUT_BUFFER, x
    beq @no_local
    inx
    lda INPUT_BUFFER, x
    beq @no_local
    cmp #' '
    beq @no_local
    stx local_start
    
    ldy #0
@find_local_end:
    lda INPUT_BUFFER, x
    beq @local_done
    cmp #' '
    beq @local_done
    inx
    iny
    jmp @find_local_end
@local_done:
    sty local_len
    jmp @args_parsed
    
@no_local:
    lda #0
    sta local_len
    sta local_start

@args_parsed:

    ; -----------------------------------------------------------------------
    ; 2. Read server.cfg
    ; -----------------------------------------------------------------------
    lda #CMD_FS_OPEN
    sta CMD_ID
    
    ; Copy "/server.cfg" to ARG_BUFF
    lda #'/'
    sta ARG_BUFF
    lda #'s'
    sta ARG_BUFF+1
    lda #'e'
    sta ARG_BUFF+2
    lda #'r'
    sta ARG_BUFF+3
    lda #'v'
    sta ARG_BUFF+4
    lda #'e'
    sta ARG_BUFF+5
    lda #'r'
    sta ARG_BUFF+6
    lda #'.'
    sta ARG_BUFF+7
    lda #'c'
    sta ARG_BUFF+8
    lda #'f'
    sta ARG_BUFF+9
    lda #'g'
    sta ARG_BUFF+10
    lda #0
    sta ARG_BUFF+11
    
    lda #12
    sta ARG_LEN
    
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @open_ok
    
    lda #<msg_no_cfg
    sta ptr_temp
    lda #>msg_no_cfg
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp done

@open_ok:
    ; Save handle
    lda RESP_BUFF
    sta file_handle
    
    ; Read file
    lda #CMD_FS_READ
    sta CMD_ID
    lda file_handle
    sta ARG_BUFF
    lda #32
    sta ARG_BUFF+1
    lda #0
    sta ARG_BUFF+2
    lda #3
    sta ARG_LEN
    
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @read_ok
    
    lda #<msg_bad_cfg
    sta ptr_temp
    lda #>msg_bad_cfg
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp close_file

@read_ok:
    ; Copy response to buffer
    ldx #0
@copy_resp:
    cpx RESP_LEN
    bcs @copy_done
    lda RESP_BUFF, x
    sta cfg_data, x
    inx
    jmp @copy_resp
@copy_done:
    lda #0
    sta cfg_data, x
    
    ; Find colon and split
    ldx #0
@find_colon:
    lda cfg_data, x
    beq cfg_invalid
    cmp #':'
    beq colon_found
    inx
    jmp @find_colon
    
cfg_invalid:
    jmp close_and_fail

colon_found:
    lda #0
    sta cfg_data, x
    stx cfg_ip_len
    inx
    stx cfg_port_start

close_file:
    ; Close file
    lda #CMD_FS_CLOSE
    sta CMD_ID
    lda file_handle
    sta ARG_BUFF
    lda #1
    sta ARG_LEN
    jsr pico_send_request

    ; -----------------------------------------------------------------------
    ; 3. Build request packet in ARG_BUFF
    ; Format: IP\0Port\0RemotePath\0LocalPath
    ; -----------------------------------------------------------------------
    ldx #0
    
    ; Copy IP
    ldy #0
@copy_ip:
    lda cfg_data, y
    beq @ip_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_ip
@ip_done:
    lda #0
    sta ARG_BUFF, x
    inx
    
    ; Copy Port
    ldy cfg_port_start
@copy_port:
    lda cfg_data, y
    beq @port_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_port
@port_done:
    lda #0
    sta ARG_BUFF, x
    inx
    
    ; Copy Remote Path (filename)
    ldy remote_start
@copy_remote:
    lda INPUT_BUFFER, y
    beq @remote_done
    cmp #' '
    beq @remote_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_remote
@remote_done:
    lda #0
    sta ARG_BUFF, x
    inx
    
    ; Handle Local Path
    lda local_len
    beq @use_remote_name
    
    ; Check if provided local path is absolute
    ldy local_start
    lda INPUT_BUFFER, y
    cmp #'/'
    beq @copy_local_abs

    ; Relative path - prepend CWD
    lda cwd_ptr
    sta ptr_temp
    lda cwd_ptr+1
    sta ptr_temp+1
    
    phy ; Save Y (local_start)
    ldy #0
@copy_cwd_explicit:
    lda (ptr_temp), y
    beq @cwd_done_explicit
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_cwd_explicit
@cwd_done_explicit:
    ; Add slash if needed
    lda (ptr_temp)
    cmp #'/'
    bne @add_slash_explicit
    ldy #1
    lda (ptr_temp), y
    beq @no_slash_explicit
@add_slash_explicit:
    lda #'/'
    sta ARG_BUFF, x
    inx
@no_slash_explicit:
    ply ; Restore Y (local_start)

@copy_local_abs:
    lda INPUT_BUFFER, y
    beq @local_done
    cmp #' '
    beq @local_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_local_abs
@local_done:
    lda #0
    sta ARG_BUFF, x
    inx
    jmp @packet_done

@use_remote_name:
    ; Use filename from remote path
    ; Prepend CWD
    lda cwd_ptr
    sta ptr_temp
    lda cwd_ptr+1
    sta ptr_temp+1
    ldy #0
@copy_cwd:
    lda (ptr_temp), y
    beq @cwd_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_cwd
@cwd_done:
    ; Add slash if needed
    lda (ptr_temp)
    cmp #'/'
    bne @add_slash
    ldy #1
    lda (ptr_temp), y
    beq @no_slash_needed
@add_slash:
    lda #'/'
    sta ARG_BUFF, x
    inx
@no_slash_needed:
    
    ; Find basename of remote path
    ldy remote_start
    sty ptr_temp      ; Store start index
    
@scan_slash:
    lda INPUT_BUFFER, y
    beq @scan_done
    cmp #' '
    beq @scan_done
    cmp #'/'
    bne @next_char
    sty ptr_temp      ; Found slash, update start index
    inc ptr_temp      ; Point to char after slash
@next_char:
    iny
    jmp @scan_slash
@scan_done:

    ; Copy remote filename (basename) as local filename
    ldy ptr_temp
@copy_remote_name:
    lda INPUT_BUFFER, y
    beq @remote_name_done
    cmp #' '
    beq @remote_name_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_remote_name
@remote_name_done:
    lda #0
    sta ARG_BUFF, x
    inx

@packet_done:
    stx ARG_LEN

    ; -----------------------------------------------------------------------
    ; 4. Send HTTP GET command
    ; -----------------------------------------------------------------------
    lda #<msg_downloading
    sta ptr_temp
    lda #>msg_downloading
    sta ptr_temp+1
    jsr print_string
    jsr CRLF

    lda #CMD_NET_HTTP_GET
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    bne @download_failed
    
    lda #<msg_done
    sta ptr_temp
    lda #>msg_done
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp done

@download_failed:
    lda #<msg_err
    sta ptr_temp
    lda #>msg_err
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp done

usage:
    lda #<msg_usage
    sta ptr_temp
    lda #>msg_usage
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp done

done:
    pla
    tay
    pla
    tax
    pla
    plp
    clc
    rts

close_and_fail:
    lda #<msg_bad_cfg
    sta ptr_temp
    lda #>msg_bad_cfg
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    jmp close_file

; ---------------------------------------------------------------------------
; Print string using ptr_temp ($56-$57)
; ---------------------------------------------------------------------------
print_string:
    pha
    phy
    ldy #0
@loop:
    lda (ptr_temp), y
    beq @done
    jsr OUTCH
    iny
    jmp @loop
@done:
    ply
    pla
    rts

; ---------------------------------------------------------------------------
; RODATA
; ---------------------------------------------------------------------------
.segment "RODATA"

msg_usage:       .asciiz "Usage: GET <remote_file> [local_file]"
msg_downloading: .asciiz "Downloading..."
msg_done:        .asciiz "Done"
msg_err:         .asciiz "Download failed"
msg_no_cfg:      .asciiz "Error: Run SETSERVER first"
msg_bad_cfg:     .asciiz "Error: Invalid server.cfg"

; ---------------------------------------------------------------------------
; BSS
; ---------------------------------------------------------------------------
.segment "BSS"

cwd_ptr:         .res 2   ; Saved CWD pointer
file_handle:     .res 1   ; File handle for server.cfg
cfg_data:        .res 32  ; Buffer for server.cfg contents
cfg_ip_len:      .res 1   ; Length of IP part
cfg_port_start:  .res 1   ; Start index of port
remote_start:    .res 1   ; Start of remote path in INPUT_BUFFER
remote_len:      .res 1   ; Length of remote path
local_start:     .res 1   ; Start of local path (0 if none)
local_len:       .res 1   ; Length of local path (0 if none)
