; get.s - Download a file from the configured file server
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
CRLF  = $FED1    ; Print CR/LF

; ---------------------------------------------------------------------------
; Zero page (USE ONLY $58-$5F)
; ---------------------------------------------------------------------------
t_arg_ptr    = $58  ; 2 bytes - Argument pointer
t_str_ptr1   = $5A  ; 2 bytes - String pointer 1
t_str_ptr2   = $5C  ; 2 bytes - String pointer 2
t_ptr_temp   = $5E  ; 2 bytes - Temporary pointer (File Handle)

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
; HEADER - MUST be first
; ---------------------------------------------------------------------------
.segment "HEADER"
    .word $0800        ; Load at $0800

; ---------------------------------------------------------------------------
; CODE - Program starts here
; ---------------------------------------------------------------------------
.segment "CODE"

start:
    ; ALWAYS preserve registers
    php
    pha
    txa
    pha
    tya
    pha

    ; Save CWD pointer passed from shell in $5E/$5F
    lda t_ptr_temp
    sta cwd_ptr
    lda t_ptr_temp+1
    sta cwd_ptr+1

    ; 1. Parse Arguments
    ; -----------------------------------------------------------------------
    ; Scan INPUT_BUFFER for the command name and skip it
    ldx #0
@scan_cmd:
    lda INPUT_BUFFER, x
    beq @go_usage       ; No args -> Usage
    cmp #' '
    beq @skip_spaces
    inx
    bne @scan_cmd
@go_usage:
    jmp @usage

@skip_spaces:
    inx
    lda INPUT_BUFFER, x
    beq @go_usage       ; Trailing spaces only -> Usage
    cmp #' '
    beq @skip_spaces
    
    ; Found argument start at index X
    ; Save pointer to argument in t_arg_ptr
    txa
    clc
    adc #<INPUT_BUFFER
    sta t_arg_ptr
    lda #>INPUT_BUFFER
    adc #0
    sta t_arg_ptr+1
    
    ; Always skip the first argument (the executable path from RUN)

    ; Skip this argument (the path)
@skip_path:
    iny
    lda (t_arg_ptr), y
    beq @go_usage       ; End of line -> Usage
    cmp #' '
    bne @skip_path

@skip_spaces_2:
    iny
    lda (t_arg_ptr), y
    beq @go_usage       ; End of line -> Usage
    cmp #' '
    beq @skip_spaces_2

    ; Found real argument, update t_arg_ptr
    tya
    clc
    adc t_arg_ptr
    sta t_arg_ptr
    bcc @args_found
    inc t_arg_ptr+1

@args_found:
    ; 2. Read server.cfg
    ; -----------------------------------------------------------------------
    jsr read_server_config
    bcc @cfg_ok
    jmp done            ; Error printed in subroutine
@cfg_ok:

    ; 3. Build Request Packet in ARG_BUFF
    ; Format: IP \0 Port \0 RemotePath \0 LocalPath
    ; -----------------------------------------------------------------------
    
    ; A. Copy IP
    ldx #0              ; Target index in ARG_BUFF
    ldy #0              ; Source index in server_cfg_data
@copy_ip:
    lda server_cfg_data, y
    beq @ip_done        ; Null terminator (was colon)
    sta ARG_BUFF, x
    inx
    iny
    bne @copy_ip
@ip_done:
    lda #0
    sta ARG_BUFF, x
    inx
    iny                 ; Skip the null/colon in source
    
    ; B. Copy Port
@copy_port:
    lda server_cfg_data, y
    beq @port_done
    sta ARG_BUFF, x
    inx
    iny
    bne @copy_port
@port_done:
    lda #0
    sta ARG_BUFF, x
    inx
    
    ; C. Copy Remote Path (from t_arg_ptr)
    ldy #0
@copy_remote:
    lda (t_arg_ptr), y
    beq @remote_done
    cmp #' '
    beq @remote_done
    sta ARG_BUFF, x
    inx
    iny
    bne @copy_remote
@remote_done:
    lda #0
    sta ARG_BUFF, x
    inx
    
    ; Save Y (length of remote path) for local path logic
    sty t_ptr_temp
    
    ; D. Copy Local Path
    ; Check if a second argument exists
    lda (t_arg_ptr), y
    beq @use_remote_as_local ; End of string -> use remote
    
    ; Skip spaces to find second arg
@skip_spaces_3:
    iny
    lda (t_arg_ptr), y
    beq @use_remote_as_local
    cmp #' '
    beq @skip_spaces_3
    
    ; Found second arg, copy it
    ; Check if absolute
    lda (t_arg_ptr), y
    cmp #'/'
    beq @copy_local

    ; Relative: Prepend CWD
    ; Save Y (index in t_arg_ptr)
    sty t_ptr_temp
    
    ; Setup pointer to CWD
    lda cwd_ptr
    sta t_str_ptr2
    lda cwd_ptr+1
    sta t_str_ptr2+1
    
    ldy #0
@copy_cwd_local:
    lda (t_str_ptr2), y
    beq @cwd_local_done
    sta ARG_BUFF, x
    inx
    iny
    bne @copy_cwd_local
@cwd_local_done:
    ; Append '/' if not root
    lda (t_str_ptr2)
    cmp #'/'
    bne @add_slash
    ldy #1
    lda (t_str_ptr2), y
    beq @restore_y
@add_slash:
    lda #'/'
    sta ARG_BUFF, x
    inx
@restore_y:
    ldy t_ptr_temp ; Restore Y

@copy_local:
    lda (t_arg_ptr), y
    beq @local_done
    cmp #' '            ; Stop at space (ignore extra args)
    beq @local_done
    sta ARG_BUFF, x
    inx
    iny
    bne @copy_local
@local_done:
    jmp @finalize_packet

@use_remote_as_local:
    ; No local path provided, use filename from remote path
    ; We need to find the last '/' in the remote path
    ; t_arg_ptr points to start of remote path
    ; t_ptr_temp holds length of remote path
    
    ldy t_ptr_temp      ; Start at end
@find_slash:
    dey
    bmi @no_slash       ; Reached start, no slash
    lda (t_arg_ptr), y
    cmp #'/'
    bne @find_slash
    
    ; Found slash at Y. Filename starts at Y+1
    iny
    jmp @copy_filename_portion
    
@no_slash:
    ldy #0              ; Use full path
    
@copy_filename_portion:
    ; We are using a filename derived from remote path. It is relative.
    ; Prepend CWD.
    sty t_ptr_temp ; Save Y (start of filename in remote path)
    
    lda cwd_ptr
    sta t_str_ptr2
    lda cwd_ptr+1
    sta t_str_ptr2+1
    
    ldy #0
@copy_cwd_imp:
    lda (t_str_ptr2), y
    beq @cwd_imp_done
    sta ARG_BUFF, x
    inx
    iny
    bne @copy_cwd_imp
@cwd_imp_done:
    lda (t_str_ptr2)
    cmp #'/'
    bne @add_slash_imp
    ldy #1
    lda (t_str_ptr2), y
    beq @restore_y_imp
@add_slash_imp:
    lda #'/'
    sta ARG_BUFF, x
    inx
@restore_y_imp:
    ldy t_ptr_temp

    ; Copy from (t_arg_ptr + Y) until space or null
    ; Note: We can't easily index (ptr),y if y is large and we loop
    ; So we just loop and re-check chars
    
@copy_local_loop:
    lda (t_arg_ptr), y
    beq @finalize_packet
    cmp #' '
    beq @finalize_packet
    sta ARG_BUFF, x
    inx
    iny
    bne @copy_local_loop

@finalize_packet:
    lda #0
    sta ARG_BUFF, x
    inx
    stx ARG_LEN

    ; 4. Send Command
    ; -----------------------------------------------------------------------
    lda #<msg_downloading
    sta t_str_ptr1
    lda #>msg_downloading
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF

    lda #CMD_NET_HTTP_GET
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    bne @net_error
    
    lda #<msg_done
    sta t_str_ptr1
    lda #>msg_done
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    jmp done

@net_error:
    lda #<msg_err
    sta t_str_ptr1
    lda #>msg_err
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    jmp done

@usage:
    lda #<msg_usage
    sta t_str_ptr1
    lda #>msg_usage
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    jmp done

; ---------------------------------------------------------------------------
; Subroutine: Read server.cfg
; Reads IP:Port into server_cfg_data and replaces ':' with 0
; Returns: Carry Clear on success, Carry Set on error
; ---------------------------------------------------------------------------
read_server_config:
    ; Open File
    lda #CMD_FS_OPEN
    sta CMD_ID
    ldx #0
@copy_fname:
    lda filename_cfg, x
    sta ARG_BUFF, x
    beq @fname_done
    inx
    bne @copy_fname
@fname_done:
    stx ARG_LEN
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @open_ok
    
    ; Error opening config
    lda #<msg_no_cfg
    sta t_str_ptr1
    lda #>msg_no_cfg
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    sec
    rts

@open_ok:
    lda RESP_BUFF       ; Handle
    sta t_ptr_temp
    
    ; Read File
    lda #CMD_FS_READ
    sta CMD_ID
    lda t_ptr_temp
    sta ARG_BUFF
    lda #32             ; Read up to 32 bytes
    sta ARG_BUFF+1
    lda #0
    sta ARG_BUFF+2
    lda #3
    sta ARG_LEN
    jsr pico_send_request

    ; Check Read Status
    lda LAST_STATUS
    cmp #STATUS_OK
    bne @close_and_fail
    
    ; Copy response to BSS buffer
    ldx #0
@copy_resp:
    cpx RESP_LEN
    bcs @copy_done
    lda RESP_BUFF, x
    sta server_cfg_data, x
    inx
    bne @copy_resp
@copy_done:
    lda #0
    sta server_cfg_data, x ; Ensure null termination

    ; Close File
    lda #CMD_FS_CLOSE
    sta CMD_ID
    lda t_ptr_temp
    sta ARG_BUFF
    lda #1
    sta ARG_LEN
    jsr pico_send_request
    
    ; Find colon and replace with null
    ldx #0
@find_colon:
    lda server_cfg_data, x
    beq @cfg_invalid    ; End reached, no colon
    cmp #':'
    beq @found_colon
    inx
    bne @find_colon
    
@found_colon:
    lda #0
    sta server_cfg_data, x ; Split IP and Port
    clc
    rts

@close_and_fail:
    lda #CMD_FS_CLOSE
    sta CMD_ID
    lda t_ptr_temp
    sta ARG_BUFF
    lda #1
    sta ARG_LEN
    jsr pico_send_request
@read_err:
@cfg_invalid:
    lda #<msg_bad_cfg
    sta t_str_ptr1
    lda #>msg_bad_cfg
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    sec
    rts

; ---------------------------------------------------------------------------
; Helper: Print null-terminated string
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

; ---------------------------------------------------------------------------
; Exit
; ---------------------------------------------------------------------------
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
; RODATA
; ---------------------------------------------------------------------------
.segment "RODATA"

filename_cfg:    .asciiz "/server.cfg"
msg_usage:       .asciiz "Usage: GET <remote_file> [local_file]"
msg_downloading: .asciiz "Downloading..."
msg_done:        .asciiz "Done"
msg_err:         .asciiz "Download failed"
msg_no_cfg:      .asciiz "Error: Run SETSERVER first"
msg_bad_cfg:     .asciiz "Error: Invalid server.cfg"

; ---------------------------------------------------------------------------
; BSS - Uninitialized Data
; ---------------------------------------------------------------------------
.segment "BSS"

server_cfg_data: .res 32  ; Buffer for IP:Port string
cwd_ptr:         .res 2   ; Pointer to CWD string
