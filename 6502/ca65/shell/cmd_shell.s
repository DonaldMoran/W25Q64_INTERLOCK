; cmd_shell.s - 6502 Shell for Pico W Smart Peripheral
; Target: RAM @ $1000

.include "common/pico_def.inc"

.import pico_init, pico_send_request, send_byte, read_byte
.import CMD_ID, ARG_LEN, ARG_BUFF, LAST_STATUS, RESP_LEN, RESP_BUFF

; ---------------------------------------------------------------------------
; System Constants (Derived from eater.lbl)
; ---------------------------------------------------------------------------
CHRIN        = $A231    ; Input character from console (A)
MONCOUT      = $A23D    ; Output character to console (A)
CRLF         = $FED1    ; Print Carriage Return / Line Feed
WOZMON       = $FF00    ; WozMon Entry Point
INPUT_BUFFER = $0300    ; Location of Input Buffer
OUTHEX       = $FFDC    ; Print byte in A as hex (Destroys A)
PRHEX        = $FFE5    ; Print low nibble of A as hex (Destroys A)
GETLINE      = $FF0E    ; Monitor entry point (CR + Prompt)
OUTCH        = $FFEF    ; Print char in A (Preserves A)
STATUS_EXIST = $03      ; Status code for "File exists"

; --- Zero Page pointers for strcmp ---
str_ptr1 = $52 ; 2 bytes
str_ptr2 = $54 ; 2 bytes
; --- Zero Page pointers for argument parsing ---
arg_ptr = $50 ; 2 bytes
; --- Temp pointer for general use ---
ptr_temp = $56 ; 2 bytes

.segment "BSS"
current_path: .res 128 ; Buffer for the current working directory
is_mounted_flag: .res 1 ; 0 = not mounted, 1 = mounted

; --- BSS variables for SAVEMEM ---
savemem_start:    .res 2   ; Start address
savemem_end:      .res 2   ; End address
savemem_len:      .res 2   ; Computed length
savemem_cnt:      .res 2   ; Remaining bytes counter

; --- BSS variables for TYPE ---
type_is_hex:      .res 1
hex_buf:          .res 16
hex_idx:          .res 1
hex_offset:       .res 2
pending_cmd:      .res 1

.segment "CMD_SHELL"


start:
    ; Start on a fresh line
    jsr CRLF

    ; -----------------------------------------------------------------------
    ; Debug: Print Start Marker "STR"
    ; -----------------------------------------------------------------------
    ldx #0
@sloop:
    lda START_MSG, x
    beq @sdone
    jsr OUTCH
    inx
    jmp @sloop
@sdone:
    jsr CRLF

    ; Initialize the VIA and Pico interface
    jsr pico_init

    ; Initialize mount status to not mounted
    lda #0
    sta is_mounted_flag

    ; Initialize current path to root "/"
    lda #'/'
    sta current_path
    lda #0
    sta current_path+1


shell_loop:
    ; Print Prompt
    lda #'>'
    jsr OUTCH
    lda #' '
    jsr OUTCH

    ; Read Line into INPUT_BUFFER
    ldx #0
@read_loop:
    jsr CHRIN
    bcc @read_loop      ; Loop if Carry Clear (No key pressed)

    ; --- Handle CR (End of Line) ---
    cmp #$0D            ; Check for CR
    beq @read_done

    ; --- Handle Backspace ---
    cmp #$08            ; Backspace character?
    beq @do_backspace
    cmp #$7F            ; Or Delete character?
    beq @do_backspace

    ; --- Filter out other control characters ---
    cmp #$20
    bcc @read_loop

    ; --- Handle printable characters ---
    ; (Assuming CHRIN echoes the character)
    cpx #$FF            ; Is buffer full? (max index is $FE for char, $FF for null)
    bcs @read_loop      ; If full, ignore character and wait for backspace or CR

    sta INPUT_BUFFER, x
    inx
    jmp @read_loop

@do_backspace:
    cpx #0              ; Is buffer empty?
    beq @read_loop      ; If so, do nothing (can't backspace past prompt)

    dex                 ; 1. Decrement buffer index first.

    ; 2. Visually erase character by printing Backspace-Space-Backspace.
    ; This moves the cursor left, overwrites the character with a space,
    ; and then moves the cursor left again to the correct final position.
    lda #$08            ; Backspace
    jsr OUTCH
    lda #' '            ; Space
    jsr OUTCH
    lda #$08            ; Backspace again
    jsr OUTCH
    jmp @read_loop

@read_done:
    lda #0
    sta INPUT_BUFFER, x ; Null terminate
    jsr CRLF

    ; Check for empty line
    cpx #0
    beq shell_loop

    ; --- NEW: Command Dispatcher ---
    jsr dispatch_command
    jmp shell_loop ; All handlers should return to the main loop

; ---------------------------------------------------------------------------
; dispatch_command
; Parses the command from INPUT_BUFFER and calls the appropriate handler.
; ---------------------------------------------------------------------------
dispatch_command:
    ; First, convert the input buffer to uppercase for case-insensitive matching.
    ; This only converts the first word before a space.
    ldx #0
@toupper_loop:
    lda INPUT_BUFFER, x
    beq @toupper_done
    cmp #' '
    beq @toupper_done
    cmp #'a'
    bcc @not_lower
    cmp #'z'+1
    bcs @not_lower
    and #%11011111 ; Convert to uppercase
    sta INPUT_BUFFER, x
@not_lower:
    inx
    jmp @toupper_loop
@toupper_done:

    ; Now, iterate through the command table
    ldx #0 ; Use X as an index into the command table
@dispatch_loop:
    ; Get pointer to command string from table
    lda command_table, x
    sta str_ptr2
    inx
    lda command_table, x
    sta str_ptr2+1
    inx

    ; Check for end of table (null pointer)
    lda str_ptr2
    ora str_ptr2+1
    beq try_external    ; If not found in table, try external command in /BIN

    ; Set up pointer to user input
    lda #<INPUT_BUFFER
    sta str_ptr1
    lda #>INPUT_BUFFER
    sta str_ptr1+1

    ; Compare strings
    jsr strcmp_space
    beq @found_command ; If Z flag is set, they match

    ; No match, advance to next handler address and loop
    inx
    inx
    jmp @dispatch_loop

@found_command:
    ; The string matched. The handler address is next in the table.
    ; X is already pointing to the low byte of the handler address.
    ; We will JSR to the handler (via trampoline) and then RTS from here.
    lda command_table, x
    sta str_ptr1 ; Temp store for JMP indirect (use our ZP area)
    inx
    lda command_table, x
    sta str_ptr1+1
    jsr call_handler_indirect
    rts ; Return to shell_loop

; ---------------------------------------------------------------------------
; try_external
; Checks if /BIN/<COMMAND>.BIN exists. If so, rewrites INPUT_BUFFER
; to "RUN /BIN/<COMMAND>.BIN <ARGS>" and jumps to do_run.
; ---------------------------------------------------------------------------
try_external:
    ; 1. Construct "/BIN/<CMD>.BIN" in ARG_BUFF
    
    ; Copy "/BIN/" prefix
    ldx #0
@copy_prefix:
    lda str_bin_prefix, x
    beq @prefix_done
    sta ARG_BUFF, x
    inx
    jmp @copy_prefix
@prefix_done:
    ; X is now 5

    ; Copy Command from INPUT_BUFFER
    ldy #0
@copy_cmd:
    lda INPUT_BUFFER, y
    beq @cmd_done
    cmp #' '
    beq @cmd_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_cmd
@cmd_done:
    sty ptr_temp ; Save command length (Y) in ptr_temp

    ; Copy ".BIN" suffix
    ldy #0
@copy_suffix:
    lda str_bin_suffix, y
    beq @suffix_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_suffix
@suffix_done:
    ; Null terminate ARG_BUFF
    lda #0
    sta ARG_BUFF, x
    stx ARG_LEN

    ; 2. Check if file exists (CMD_FS_STAT)
    lda #CMD_FS_STAT
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    bne unknown_command ; File not found, report unknown command

    ; 3. File exists! Rewrite INPUT_BUFFER.
    ; We need to shift the arguments (if any) to the right by 13 bytes.
    ; Shift amount = len("/BIN/") + len(".BIN") + len("RUN ") = 5 + 4 + 4 = 13.
    
    ; Find end of INPUT_BUFFER
    ldx ptr_temp ; Start at end of command word
@find_end:
    lda INPUT_BUFFER, x
    beq @found_end
    inx
    jmp @find_end
@found_end:
    ; X points to null terminator. Copy backwards.
@shift_loop:
    lda INPUT_BUFFER, x
    sta INPUT_BUFFER + 13, x
    cpx ptr_temp
    beq @shift_done
    dex
    jmp @shift_loop
@shift_done:

    ; 4. Write "RUN " at start
    ldx #0
@write_run:
    lda str_run_prefix, x
    beq @write_run_done
    sta INPUT_BUFFER, x
    inx
    jmp @write_run
@write_run_done:

    ; 5. Copy path from ARG_BUFF to INPUT_BUFFER + 4
    ; ARG_BUFF contains "/BIN/<CMD>.BIN"
    ldy #0
@write_path:
    lda ARG_BUFF, y
    beq @write_path_done
    sta INPUT_BUFFER, x
    inx
    iny
    jmp @write_path
@write_path_done:
    ; Add a space between the program and its arguments
    lda #' '
    sta INPUT_BUFFER, x
    inx

    ; 6. Execute
    jmp do_run

unknown_command:
    ldx #0
@unk_loop:
    lda UNK_MSG, x
    beq @unk_done
    jsr OUTCH
    inx
    jmp @unk_loop
@unk_done:
    jsr CRLF
    rts ; Return to shell_loop

; --- JSR-indirect trampoline ---
call_handler_indirect:
    ; Jumps to the routine pointed to by str_ptr1.
    ; The RTS from the called handler will return to our caller.
    jmp (str_ptr1)

; ---------------------------------------------------------------------------
; Command Handlers
; ---------------------------------------------------------------------------
do_dir:
    jsr guard_requires_mount
    bcc @proceed
    rts
@proceed:

    ; The DIR command can take an optional path. If no path is provided,
    ; we must explicitly send "/" to list the root directory. Sending a
    ; zero-length string is not a valid path for LittleFS on the Pico.
    jsr get_first_arg
    ldy #0
    lda (arg_ptr),y     ; Check if the first character of the argument is null
    bne @arg_exists

    ; No argument: use current_path
    ldx #0
@copy_cwd:
    lda current_path, x
    sta ARG_BUFF, x
    beq @cwd_done
    inx
    jmp @copy_cwd
@cwd_done:
    inx                 ; Include null terminator in length
    stx ARG_LEN
    jmp @send_request

@arg_exists:
    ; Argument provided: copy it to the Pico's argument buffer.
    jsr get_first_arg_as_pico_arg

@send_request:
    lda #CMD_FS_LIST
    sta CMD_ID
    jsr pico_send_request
    bcc @dir_ok
    jsr timeout_error
    rts
@dir_ok:
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @dir_success
    cmp #STATUS_NO_FILE
    bne @dir_fail
    jsr print_file_not_found
    rts
@dir_fail:
    jsr print_command_failed
    rts
@dir_success:
    jsr CRLF
    ; Print the response string directly
    ; (The Pico formats the list as a string)
    jsr print_response
    rts

do_pwd:
    jsr guard_requires_mount
    bcc @proceed
    rts
@proceed:

    ldx #0
@pwd_loop:
    lda current_path, x
    beq @pwd_done
    jsr OUTCH
    inx
    jmp @pwd_loop
@pwd_done:
    jsr CRLF
    rts

do_cd:
    jsr guard_requires_mount
    bcc @proceed
    rts
@proceed:

    jsr get_first_arg
    
    ; 1. Check for empty argument (cd -> root)
    ldy #0
    lda (arg_ptr), y
    beq @go_root

    ; 2. Check for "." or ".."
    cmp #'.'
    bne @resolve_and_verify
    iny
    lda (arg_ptr), y
    beq @stay_here      ; Match "." exactly
    cmp #'.'
    bne @resolve_and_verify
    iny
    lda (arg_ptr), y
    beq @go_up          ; Match ".." exactly

@resolve_and_verify:
    ; Resolve path to ARG_BUFF
    ldx #0
    jsr resolve_path_to_arg_buff
    bcs @path_too_long

    ; Null terminate and set length
    lda #0
    sta ARG_BUFF, x
    stx ARG_LEN

    ; Verify existence (CMD_FS_STAT)
    lda #CMD_FS_STAT
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @update_path
    cmp #STATUS_NO_FILE
    bne @cd_fail
    jsr print_file_not_found
    rts

@cd_fail:
    jsr print_command_failed
    rts

@update_path:
    ; Copy ARG_BUFF to current_path
    ldx #0
@copy_loop:
    lda ARG_BUFF, x
    sta current_path, x
    beq @copy_done
    inx
    cpx #127
    bcc @copy_loop
    lda #0
    sta current_path, x
@copy_done:
    rts

@go_root:
    lda #'/'
    sta current_path
    lda #0
    sta current_path+1
    rts

@stay_here:
    rts

@go_up:
    ; Handle ".." - Strip last component
    ; Find end of string
    ldx #0
@up_find_end:
    lda current_path, x
    beq @up_found_end
    inx
    jmp @up_find_end
@up_found_end:
    ; X points to null. Scan back.
    dex
    bmi @go_root        ; Empty string -> root
@up_scan_back:
    cpx #0
    beq @go_root        ; Reached start -> root
    lda current_path, x
    cmp #'/'
    beq @up_cut
    dex
    jmp @up_scan_back
@up_cut:
    ; Found the separator.
    ; If it's the first char (index 0), we are at root parent (e.g. /Donald -> /)
    cpx #0
    beq @up_root_parent
    ; Otherwise (e.g. /A/B -> /A), terminate here
    lda #0
    sta current_path, x
    rts
@up_root_parent:
    ; We found the leading slash. Keep it.
    lda #0
    sta current_path+1
    rts

@path_too_long:
    jsr print_command_failed
    rts

do_mkdir:
    jsr guard_requires_mount
    bcc @proceed
    rts
@proceed:

    ; Parse the argument
    jsr get_first_arg

    ; Resolve the path against current_path
    ldx #0                  ; Start at beginning of ARG_BUFF
    jsr resolve_path_to_arg_buff
    bcs @path_error         ; Carry set means path too long

    ; Null terminate the resolved path
    lda #0
    sta ARG_BUFF, x
    inx
    stx ARG_LEN             ; Store length including null

    lda #CMD_FS_MKDIR
    sta CMD_ID
    jsr pico_send_request
    bcc @mkdir_ok
    jsr timeout_error
    rts
@mkdir_ok:
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @mkdir_success
    cmp #STATUS_NO_FILE
    bne @mkdir_fail
    jsr print_file_not_found
    rts
@mkdir_fail:
    cmp #STATUS_EXIST
    bne @mkdir_err
    jsr print_file_exists
    rts
@mkdir_err:
    jsr print_command_failed
@mkdir_success:
    rts

@path_error:
    jsr print_command_failed
    rts

; do_del:
;     jsr guard_requires_mount
;     bcc @proceed
;     rts
; @proceed:

;     ; For now, we assume the argument is an absolute path
;     ; A real implementation would call resolve_path here.
;     jsr get_first_arg_as_pico_arg

;     lda #CMD_FS_REMOVE
;     sta CMD_ID
;     ; ARG_LEN is set by get_first_arg_as_pico_arg
;     jsr pico_send_request
;     bcc @del_ok
;     jsr timeout_error
;     rts

; @del_ok:
;     jsr get_first_arg
;     lda LAST_STATUS
;     cmp #STATUS_OK
;     beq @del_success
;     cmp #STATUS_NO_FILE
;     bne @del_fail
;     jsr print_file_not_found
;     rts
; @del_fail:
;     jsr print_command_failed
;     rts
; @del_success:
;     rts
do_del:
    jsr guard_requires_mount
    bcc @proceed
    rts
@proceed:

    ; Parse the argument
    jsr get_first_arg
    
    ; Resolve the path against current_path
    ldx #0                  ; Start at beginning of ARG_BUFF
    jsr resolve_path_to_arg_buff
    bcs @path_error         ; Carry set means path too long
    
    ; Null terminate the resolved path
    lda #0
    sta ARG_BUFF, x
    inx
    stx ARG_LEN             ; Store length including null

    lda #CMD_FS_REMOVE
    sta CMD_ID
    jsr pico_send_request
    bcc @del_ok
    jsr timeout_error
    rts

@del_ok:
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @del_success
    cmp #STATUS_NO_FILE
    bne @del_fail
    jsr print_file_not_found
    rts
    
@del_fail:
    jsr print_command_failed
    rts
    
@del_success:
    rts

@path_error:
    jsr print_command_failed    ; Reuse existing argument error message
    rts


do_mount:
    lda #CMD_FS_MOUNT
    sta CMD_ID
    lda #0              ; No arguments
    sta ARG_LEN
    jsr pico_send_request
    bcc @mount_ok
    jsr timeout_error
    rts
@mount_ok:
    ; Check the actual status from the Pico
    lda LAST_STATUS
    cmp #STATUS_OK
    bne @mount_fail

    ; Success! Set the flag and print a message.
    lda #1
    sta is_mounted_flag
    ldx #0
@msg_loop:
    lda MOUNT_OK_MSG, x
    beq @msg_done
    jsr OUTCH
    inx
    jmp @msg_loop
@msg_done:
    jsr CRLF
    rts

@mount_fail:
    ; The pico reported an error, print a generic fail message
    jsr print_mount_fail
    rts

do_format:
    lda #CMD_FS_FORMAT
    sta CMD_ID
    lda #0
    sta ARG_LEN
    jsr pico_send_request
    bcc @format_ok
    jsr timeout_error
    rts
@format_ok:
    lda LAST_STATUS
    cmp #STATUS_OK
    bne @format_fail

    ldx #0
@msg_loop:
    lda FORMAT_OK_MSG, x
    beq @msg_done
    jsr OUTCH
    inx
    jmp @msg_loop
@msg_done:
    jsr CRLF
    rts
@format_fail:
    jsr print_format_fail
    rts

do_ping:
    lda #CMD_SYS_PING
    sta CMD_ID
    lda #0              ; Length 0
    sta ARG_LEN

    ; Clear Response Buffer to ensure we don't see "Ghost Data"
    lda #0
    sta RESP_BUFF
    sta RESP_BUFF+1
    sta RESP_BUFF+2
    sta RESP_BUFF+3

    jsr pico_send_request
    bcc @ping_ok
    jsr timeout_error
    rts
@ping_ok:

    ; Print the response (Expect "PONG")
    jsr print_response
    jsr CRLF
    rts

do_connect:
    jsr guard_requires_mount
    bcc @proceed
    rts
@proceed:
    ; Check for arguments (SSID PASSWORD)
    jsr get_first_arg
    ldy #0
    lda (arg_ptr), y
    beq @use_stored

    ; 1. Copy SSID
    ldx #0
@copy_ssid:
    lda (arg_ptr), y
    beq @ssid_done      ; End of string
    cmp #' '
    beq @ssid_done      ; Space separator
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_ssid
@ssid_done:
    lda #0
    sta ARG_BUFF, x     ; Null terminate
    inx ; Skip null
    
    ; 2. Get Password
    jsr get_next_arg
    bcc @has_pass
    jmp cmd_arg_error ; SSID provided but no password
@has_pass:
    ldy #0
@copy_pass:
    lda (arg_ptr), y
    sta ARG_BUFF, x
    beq @pass_done
    inx
    iny
    jmp @copy_pass
@pass_done:
    inx
    stx ARG_LEN
    jmp @send_req

@use_stored:
    lda #0              ; No arguments
    sta ARG_LEN

@send_req:
    ; Print wait message
    ldx #0
@wait_loop:
    lda WAIT_MSG, x
    beq @wait_done
    jsr OUTCH
    inx
    jmp @wait_loop
@wait_done:
    jsr CRLF

    lda #CMD_NET_CONNECT
    sta CMD_ID
    jsr pico_send_request
    bcc @connect_ok
    jsr timeout_error
    rts
@connect_ok:
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @connect_success
    jsr print_command_failed
    rts
@connect_success:
    ldx #0
@msg_loop:
    lda CONNECT_OK_MSG, x
    beq @done
    jsr OUTCH
    inx
    jmp @msg_loop
@done:
    jsr CRLF
    rts

do_help:
    ldx #0
@hloop:
    lda HELP_MSG, x
    beq @hdone
    jsr OUTCH
    inx
    jmp @hloop
@hdone:
    jsr CRLF
    rts

do_exit:
    jmp WOZMON

; ---------------------------------------------------------------------------
; do_savemem - Save memory range to file
; Format: SAVEMEM <start_hex> <end_hex> <filename>
; ---------------------------------------------------------------------------
do_savemem:
    ; First, ensure filesystem is mounted
    jsr guard_requires_mount
    bcc @proceed
    rts

@proceed:
    ; Parse start address (first argument)
    jsr get_first_arg
    jsr parse_hex_word
    bcc @ok1
    jmp cmd_parse_error
@ok1:
    sta savemem_start
    stx savemem_start+1

    ; Parse end address (second argument)
    jsr get_next_arg
    bcc @ok2
    jmp cmd_arg_error
@ok2:
    jsr parse_hex_word
    bcc @ok3
    jmp cmd_parse_error
@ok3:
    sta savemem_end
    stx savemem_end+1

    ; Compute length = end - start + 1
    sec
    lda savemem_end
    sbc savemem_start
    sta savemem_len
    lda savemem_end+1
    sbc savemem_start+1
    sta savemem_len+1

    ; Add 1
    clc
    lda savemem_len
    adc #1
    sta savemem_len
    lda savemem_len+1
    adc #0
    sta savemem_len+1

    ; Validate length (non-zero)
    lda savemem_len
    ora savemem_len+1
    bne @len_ok
    jmp cmd_invalid_range

@len_ok:
    ; Get filename (third argument)
    jsr get_next_arg
    bcc @ok4
    jmp cmd_arg_error
@ok4:
    ; Resolve path to ARG_BUFF
    ldx #0
    jsr resolve_path_to_arg_buff
    bcc @path_ok
    jmp cmd_arg_error

@path_ok:
    ; Null terminate
    lda #0
    sta ARG_BUFF, x
    inx

    ; Append length (2 bytes)
    lda savemem_len
    sta ARG_BUFF, x
    inx
    lda savemem_len+1
    sta ARG_BUFF, x
    inx
    stx ARG_LEN

    ; Send command to Pico
    lda #CMD_FS_SAVEMEM
    sta CMD_ID
    jsr pico_send_request
    bcc @cmd_sent
    jsr timeout_error
    rts

@cmd_sent:
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @start_stream
    cmp #STATUS_NO_FILE
    bne @savemem_fail
    jsr print_file_not_found
    rts
@savemem_fail:
    jsr print_command_failed
    rts

@start_stream:
    ; Initialize streaming pointers
    lda savemem_start
    sta ptr_temp
    lda savemem_start+1
    sta ptr_temp+1

    lda savemem_len
    sta savemem_cnt
    lda savemem_len+1
    sta savemem_cnt+1

    ; Print "Saving..." message
    ldx #0
@save_msg:
    lda SAVING_MSG, x
    beq @stream_loop
    jsr OUTCH
    inx
    jmp @save_msg

@stream_loop:
    ; Check if done
    lda savemem_cnt
    ora savemem_cnt+1
    beq @stream_done

    ; Send next byte
    ldy #0
    lda (ptr_temp), y
    jsr send_byte

    ; Increment pointer
    inc ptr_temp
    bne @no_carry
    inc ptr_temp+1
@no_carry:

    ; Decrement counter
    lda savemem_cnt
    bne @dec_low
    dec savemem_cnt+1
@dec_low:
    dec savemem_cnt

    ; Optional progress dot every 256 bytes
    lda savemem_cnt
    and #$FF
    cmp #$FF
    bne @no_dot
    lda #'.'
    jsr OUTCH
@no_dot:
    jmp @stream_loop

@stream_done:
    ; Read final 3-byte status header from Pico
    ; Switch Port A to Input to read response
    lda #$00
    sta VIA_DDRA

    jsr read_byte
    sta LAST_STATUS
    jsr read_byte       ; Read len_lo, ignored
    jsr read_byte       ; Read len_hi, ignored

    lda LAST_STATUS
    cmp #STATUS_OK
    bne @stream_error

    ; Restore Port A to Output
    lda #$FF
    sta VIA_DDRA

    ; Print success message
    jsr CRLF
    ldx #0
@success_msg:
    lda SAVED_MSG, x
    beq @done
    jsr OUTCH
    inx
    jmp @success_msg

@done:
    jsr CRLF
    rts

@stream_error:
    ; Restore Port A to Output
    lda #$FF
    sta VIA_DDRA

    jsr print_command_failed
    rts

; ---------------------------------------------------------------------------
; do_loadmem - Load file into memory
; Format: LOADMEM <address> <filename>
; ---------------------------------------------------------------------------
do_loadmem:
    jsr guard_requires_mount
    bcc @proceed
    rts
@proceed:
    ; Parse destination address
    jsr get_first_arg
    jsr parse_hex_word
    bcc @addr_ok
    jmp cmd_parse_error
@addr_ok:
    sta ptr_temp
    stx ptr_temp+1

    ; Parse filename
    jsr get_next_arg
    bcc @file_ok
    jmp cmd_arg_error
@file_ok:
    ; Resolve path to ARG_BUFF
    ldx #0
    jsr resolve_path_to_arg_buff
    bcc @path_ok
    jmp cmd_arg_error

@path_ok:
    lda #0
    sta ARG_BUFF, x
    inx
    stx ARG_LEN     ; Include null terminator

    ; Verify file exists using CMD_FS_STAT
    lda #CMD_FS_STAT
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @loadmem_file_exists
    cmp #STATUS_NO_FILE
    bne @loadmem_stat_fail
    jsr print_file_not_found
    rts
@loadmem_stat_fail:
    jsr print_command_failed
    rts

@loadmem_file_exists:
    ; --- Manually Send Command (Bypass pico_send_request buffer limit) ---
    lda #$FF
    sta VIA_DDRA    ; Set Port A to Output

    lda #CMD_FS_LOADMEM
    jsr send_byte

    lda ARG_LEN
    jsr send_byte

    ldx #0
@send_args:
    lda ARG_BUFF, x
    jsr send_byte
    inx
    cpx ARG_LEN
    bne @send_args

    ; --- Receive Response ---
    lda #$00
    sta VIA_DDRA    ; Set Port A to Input

    jsr read_byte   ; Read Status
    cmp #STATUS_OK
    beq @status_ok
    
    ; Handle Error
    pha             ; Save status for checking later
    jsr read_byte   ; Consume len_lo from bus
    jsr read_byte   ; Consume len_hi from bus
    lda #$FF
    sta VIA_DDRA    ; Restore bus to output
    pla             ; Restore status
    cmp #STATUS_NO_FILE
    bne @loadmem_fail
    jsr print_file_not_found
    rts
@loadmem_fail:
    jsr print_command_failed
    rts

@status_ok:
    jsr read_byte   ; Read Length Low
    sta savemem_cnt
    jsr read_byte   ; Read Length High
    sta savemem_cnt+1

@load_loop:
    lda savemem_cnt
    ora savemem_cnt+1
    beq @done

    jsr read_byte
    ldy #0
    sta (ptr_temp), y

    inc ptr_temp
    bne @no_inc
    inc ptr_temp+1
@no_inc:
    
    ; Decrement 16-bit counter
    lda savemem_cnt
    bne @dec_lo
    dec savemem_cnt+1
@dec_lo:
    dec savemem_cnt
    jmp @load_loop

@done:
    lda #$FF
    sta VIA_DDRA    ; Restore Port A to Output
    
    jsr CRLF
    ldx #0
@msg:
    lda SAVED_MSG, x ; Reuse "Done" message
    beq @msg_done
    jsr OUTCH
    inx
    jmp @msg
@msg_done:
    jsr CRLF
    rts

cmd_parse_error:
    ldx #0
@parse_err_msg:
    lda PARSE_ERROR_MSG, x
    beq @parse_err_done
    jsr OUTCH
    inx
    jmp @parse_err_msg
@parse_err_done:
    jsr CRLF
    rts

cmd_arg_error:
    ldx #0
@arg_err_msg:
    lda ARG_ERROR_MSG, x
    beq @arg_err_done
    jsr OUTCH
    inx
    jmp @arg_err_msg
@arg_err_done:
    jsr CRLF
    rts

cmd_invalid_range:
    ldx #0
@range_err_msg:
    lda RANGE_ERROR_MSG, x
    beq @range_err_done
    jsr OUTCH
    inx
    jmp @range_err_msg
@range_err_done:
    jsr CRLF
    rts

timeout_error:
    jsr CRLF
    ldx #0
@tloop:
    lda ERR_MSG, x
    beq @tdone
    jsr OUTCH
    inx
    jmp @tloop
@tdone:
    jsr CRLF
    rts

; ---------------------------------------------------------------------------
; do_type - Type file content to screen
; Format: TYPE <filename>
; ---------------------------------------------------------------------------
do_type:
    jsr guard_requires_mount
    bcc @proceed
    rts
@proceed:
    ; Parse filename
    jsr get_first_arg
    
    ; Resolve path to ARG_BUFF
    ldx #0
    jsr resolve_path_to_arg_buff
    bcc @path_ok
    jmp cmd_arg_error

@path_ok:
    ; Null terminate and set length
    lda #0
    sta ARG_BUFF, x
    txa             ; Transfer X to A
    tay             ; Transfer A to Y (X -> Y)
    inx
    stx ARG_LEN     ; Include null terminator

    ; Verify file exists using CMD_FS_STAT
    lda #CMD_FS_STAT
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @type_file_exists
    cmp #STATUS_NO_FILE
    bne @type_stat_fail
    jsr print_file_not_found
    rts
@type_stat_fail:
    jsr print_command_failed
    rts

@type_file_exists:
    ; Restore Y for extension check (ARG_LEN - 1)
    ldx ARG_LEN
    dex
    txa
    tay

    lda #0
    sta type_is_hex

@check_ext:
    ; Check for .BIN extension (Case insensitive)
    ; Y is length. We need at least 4 chars (.BIN)
    cpy #4
    bcc @not_bin
    
    ; Check last 4 chars: . B I N
    dey
    lda ARG_BUFF, y
    and #%11011111 ; To Upper
    cmp #'N'
    bne @not_bin
    
    dey
    lda ARG_BUFF, y
    and #%11011111
    cmp #'I'
    bne @not_bin
    
    dey
    lda ARG_BUFF, y
    and #%11011111
    cmp #'B'
    bne @not_bin
    
    dey
    lda ARG_BUFF, y
    cmp #'.'
    bne @not_bin
    
    ; It is .BIN
    lda #1
    sta type_is_hex

@not_bin:
    ; Send CMD_FS_LOADMEM (Reusing LOADMEM to stream file)
    lda #$FF
    sta VIA_DDRA    ; Set Port A to Output

    lda #CMD_FS_LOADMEM
    jsr send_byte

    lda ARG_LEN
    jsr send_byte

    ldx #0
@send_args:
    lda ARG_BUFF, x
    jsr send_byte
    inx
    cpx ARG_LEN
    bne @send_args

    ; Receive Response
    lda #$00
    sta VIA_DDRA    ; Set Port A to Input

    jsr read_byte   ; Read Status
    cmp #STATUS_OK
    beq @status_ok
    
    ; Handle Error
    pha             ; Save status for checking later
    jsr read_byte   ; Consume len_lo from bus
    jsr read_byte   ; Consume len_hi from bus
    lda #$FF
    sta VIA_DDRA    ; Restore bus to output
    pla             ; Restore status
    cmp #STATUS_NO_FILE
    bne @type_fail
    jsr print_file_not_found
    rts
@type_fail:
    jsr print_command_failed
    rts

@status_ok:
    jsr read_byte   ; Read Length Low
    sta savemem_cnt
    jsr read_byte   ; Read Length High
    sta savemem_cnt+1

    ; Init Hex Dump variables if needed
    lda type_is_hex
    beq @type_loop
    
    lda #0
    sta hex_idx
    sta hex_offset
    sta hex_offset+1

@type_loop:
    lda savemem_cnt
    ora savemem_cnt+1
    beq @done

    lda type_is_hex
    beq @read_next
    lda hex_idx
    bne @read_next
    jsr print_hex_offset
@read_next:
    jsr read_byte
    pha             ; Save byte

    lda type_is_hex
    beq @print_char

    ; Hex Mode
    pla
    ldx hex_idx
    sta hex_buf, x
    jsr OUTHEX      ; Print Hex
    lda #' '
    jsr OUTCH
    
    inc hex_idx
    lda hex_idx
    cmp #16
    bne @dec_cnt
    
    ; End of Hex Line
    jsr print_hex_ascii
    
    ; Increment Offset
    clc
    lda hex_offset
    adc #16
    sta hex_offset
    lda hex_offset+1
    adc #0
    sta hex_offset+1
    
    lda #0
    sta hex_idx
    jmp @dec_cnt

@print_char:
    pla
    jsr OUTCH

@dec_cnt:
    ; Decrement 16-bit counter
    lda savemem_cnt
    bne @dec_lo
    dec savemem_cnt+1
@dec_lo:
    dec savemem_cnt
    jmp @type_loop

@done:
    lda #$FF
    sta VIA_DDRA    ; Restore Port A to Output
    
    ; Final Hex Dump cleanup
    lda type_is_hex
    beq @finish
    
    lda hex_idx
    beq @finish
    
    ; Pad spaces
    ; Spaces needed = (16 - hex_idx) * 3
    lda #16
    sec
    sbc hex_idx
    tax
@pad_loop:
    lda #' '
    jsr OUTCH
    jsr OUTCH
    jsr OUTCH
    dex
    bne @pad_loop
    
    jsr print_hex_ascii

@finish:
    jsr CRLF
    rts

print_hex_offset:
    lda hex_offset+1
    jsr OUTHEX
    lda hex_offset
    jsr OUTHEX
    lda #':'
    jsr OUTCH
    lda #' '
    jsr OUTCH
    rts

print_hex_ascii:
    lda #' '
    jsr OUTCH
    lda #'|'
    jsr OUTCH
    ldx #0
@ascii_loop:
    cpx hex_idx
    beq @ascii_done
    lda hex_buf, x
    ; Filter non-printable
    cmp #$20
    bcc @dot
    cmp #$7F
    bcs @dot
    jmp @pr
@dot:
    lda #'.'
@pr:
    jsr OUTCH
    inx
    jmp @ascii_loop
@ascii_done:
    lda #'|'
    jsr OUTCH
    jsr CRLF
    rts

; ---------------------------------------------------------------------------
; do_rename - Rename a file
; Format: RENAME <old> <new>
; ---------------------------------------------------------------------------
do_copy:
    lda #CMD_FS_COPY
    sta pending_cmd
    jmp common_transfer

do_rename:
    lda #CMD_FS_RENAME
    sta pending_cmd

common_transfer:
    jsr guard_requires_mount
    bcc @proceed
    rts
@proceed:
    ; Parse and resolve old filename
    jsr get_first_arg
    ldx #0
    jsr resolve_path_to_arg_buff
    bcc @old_ok
    jmp cmd_arg_error
@old_ok:
    lda #0
    sta ARG_BUFF, x
    
    ; Move OLD path to ARG_BUFF + 128 to make room for NEW path
    ldy #0
@move_old:
    lda ARG_BUFF, y
    sta ARG_BUFF + 128, y
    beq @move_old_done
    iny
    jmp @move_old
@move_old_done:

    ; Parse and resolve new filename
    jsr get_next_arg
    bcc @new_ok_arg
    jmp cmd_arg_error
@new_ok_arg:
    ldx #0
    jsr resolve_path_to_arg_buff
    bcc @new_ok_resolve
    jmp cmd_arg_error
@new_ok_resolve:
    lda #0
    sta ARG_BUFF, x
    stx ARG_LEN     ; Length of NEW path
    stx ptr_temp    ; Save length of NEW path for @is_dir_target

    ; Check if NEW path is a directory (Syntactic check: trailing slash)
    cpx #0
    beq @check_stat
    dex
    lda ARG_BUFF, x
    cmp #'/'
    beq @is_dir_target
    inx ; Restore X

@check_stat:
    ; Check if NEW path is a directory (Semantic check: STAT)

    lda #CMD_FS_STAT
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    bne @not_dir_target
    
    lda RESP_BUFF ; Type
    cmp #2 ; LFS_TYPE_DIR
    beq @is_dir_target

@not_dir_target:
    ldx ptr_temp ; Restore len of NEW
    jmp @construct_args

@is_dir_target:
    ldx ptr_temp ; Restore len of NEW
    
    ; Ensure separator if not present
    cpx #0
    beq @find_filename
    dex
    lda ARG_BUFF, x
    inx
    cmp #'/'
    beq @find_filename
    lda #'/'
    sta ARG_BUFF, x
    inx

@find_filename:
    ; Find last '/' in OLD path (at ARG_BUFF + 128)
    ldy #128
    sty ptr_temp ; Start of filename candidate
@scan_old:
    lda ARG_BUFF, y
    beq @copy_filename
    cmp #'/'
    bne @next_char
    sty ptr_temp
    inc ptr_temp ; Point after slash
@next_char:
    iny
    jmp @scan_old

@copy_filename:
    ; Append filename to NEW path
    ldy ptr_temp
@copy_loop:
    lda ARG_BUFF, y
    beq @copy_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_loop
@copy_done:
    lda #0
    sta ARG_BUFF, x
    ; NEW path (at 0) is now "dir/filename"

@construct_args:
    ; We have NEW at 0. OLD at 128.
    ; We need OLD at 0, NEW after OLD.
    
    ; 1. Move NEW to RESP_BUFF (temp)
    ldy #0
@move_new_temp:
    lda ARG_BUFF, y
    sta RESP_BUFF, y
    beq @move_new_done
    iny
    jmp @move_new_temp
@move_new_done:

    ; 2. Move OLD (from 128) to 0
    ldy #128
    ldx #0
@move_old_back:
    lda ARG_BUFF, y
    sta ARG_BUFF, x
    beq @move_old_back_done
    inx
    iny
    jmp @move_old_back
@move_old_back_done:
    inx ; Skip null

    ; 3. Append NEW (from RESP_BUFF)
    ldy #0
@append_new:
    lda RESP_BUFF, y
    sta ARG_BUFF, x
    beq @append_new_done
    inx
    iny
    jmp @append_new
@append_new_done:
    stx ARG_LEN
    
    lda pending_cmd
    sta CMD_ID
    jsr pico_send_request
    bcc @rename_ok
    jsr timeout_error
    rts
@rename_ok:
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @rename_success
    cmp #STATUS_NO_FILE
    bne @rename_fail
    jsr print_file_not_found
    rts
@rename_fail:
    cmp #STATUS_EXIST
    bne @rename_err
    jsr print_file_exists
    rts
@rename_err:
    jsr print_command_failed
    rts

@rename_success:
    clc
    rts

; ---------------------------------------------------------------------------
; do_touch - Create an empty file
; Format: TOUCH <filename>
; ---------------------------------------------------------------------------
do_touch:
    jsr guard_requires_mount
    bcc @proceed
    rts
@proceed:
    jsr get_first_arg
    ldx #0
    jsr resolve_path_to_arg_buff
    bcs @path_error
    
    lda #0
    sta ARG_BUFF, x
    inx
    stx ARG_LEN

    lda #CMD_FS_TOUCH
    sta CMD_ID
    jsr pico_send_request
    bcc @touch_ok
    jsr timeout_error
    rts
@touch_ok:
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @touch_success
    jsr print_command_failed
@touch_success:
    rts
@path_error:
    jsr print_command_failed
    rts

; ---------------------------------------------------------------------------
; resolve_path_to_arg_buff
; Copies path from (arg_ptr) to ARG_BUFF starting at index X, resolving
; it against the current_path if it's relative. Stops at a space or null.
; In: X = starting offset in ARG_BUFF. arg_ptr points to path string.
; Out: X = new offset in ARG_BUFF after copying. Carry set on error.
; Clobbers: A, Y
; ---------------------------------------------------------------------------
resolve_path_to_arg_buff:
    ldy #0
    lda (arg_ptr), y
    cmp #'/'
    beq @abs_path

    ; --- Relative Path ---
    ; If current path is not root, copy it first.
    ldy #0
    lda current_path, y
    cmp #'/'
    bne @copy_current
    iny
    lda current_path, y
    beq @copy_arg_only ; It's root "/", so just append argument.
@copy_current:
    ldy #0
@copy_current_loop:
    lda current_path, y
    beq @append_separator
    sta ARG_BUFF, x
    iny
    inx
    cpx #127
    bcc @copy_current_loop
    jmp @path_toolong

@append_separator:
    ; Append a separator if needed
    dex
    lda ARG_BUFF, x
    inx
    cmp #'/'
    beq @copy_arg_only
    lda #'/'
    sta ARG_BUFF, x
    inx

@copy_arg_only:
    ; Now append the argument itself
    ldy #0
@copy_rel_arg:
    lda (arg_ptr), y
    beq @done
    cmp #' '
    beq @done
    sta ARG_BUFF, x
    iny
    inx
    cpx #127
    bcc @copy_rel_arg
    jmp @path_toolong

@abs_path:
    ; --- Absolute Path ---
    ldy #0
@copy_abs_arg:
    lda (arg_ptr), y
    beq @done
    cmp #' '
    beq @done
    sta ARG_BUFF, x
    iny
    inx
    cpx #127
    bcc @copy_abs_arg
    jmp @path_toolong

@done:
    clc
    rts
@path_toolong:
    sec
    rts

; ---------------------------------------------------------------------------
; get_next_arg - Advances arg_ptr to the next argument in the input buffer.
; In:  arg_ptr points to the beginning of the current argument.
; Out: arg_ptr points to the beginning of the next argument.
;      Carry is set if no more arguments are found.
;      Carry is clear if an argument was found.
; Clobbers: A, Y
; ---------------------------------------------------------------------------
get_next_arg:
    ldy #0
@find_end:
    lda (arg_ptr), y
    beq @no_more_args
    cmp #' '
    beq @found_end
    iny
    jmp @find_end

@found_end:
@skip_spaces:
    iny
    lda (arg_ptr), y
    beq @no_more_args
    cmp #' '
    beq @skip_spaces

    ; Found start of next arg
    tya
    clc
    adc arg_ptr
    sta arg_ptr
    lda arg_ptr+1
    adc #0
    sta arg_ptr+1
    clc                     ; Success - clear carry
    rts

@no_more_args:
    sec                     ; No more arguments - set carry
    rts

; ---------------------------------------------------------------------------
; do_run - Load and execute a file
; Format: RUN <filename>
; Expects first 2 bytes of file to be load address (Little Endian)
; ---------------------------------------------------------------------------
do_run:
    jsr guard_requires_mount
    bcc @proceed
    rts
@proceed:
    ; Parse filename
    jsr get_first_arg
    
    ; Resolve path to ARG_BUFF
    ldx #0
    jsr resolve_path_to_arg_buff
    bcc @path_ok
    jmp cmd_arg_error

@path_ok:
    lda #0
    sta ARG_BUFF, x
    inx
    stx ARG_LEN     ; Include null terminator

    ; Verify file exists using CMD_FS_STAT
    lda #CMD_FS_STAT
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @run_file_exists
    cmp #STATUS_NO_FILE
    bne @run_stat_fail
    jsr print_file_not_found
    rts
@run_stat_fail:
    jsr print_command_failed
    rts

@run_file_exists:
    ; --- Manually Send Command (Reuse LOADMEM protocol) ---
    lda #$FF
    sta VIA_DDRA    ; Set Port A to Output

    lda #CMD_FS_LOADMEM
    jsr send_byte

    lda ARG_LEN
    jsr send_byte

    ldx #0
@send_args:
    lda ARG_BUFF, x
    jsr send_byte
    inx
    cpx ARG_LEN
    bne @send_args

    ; --- Receive Response ---
    lda #$00
    sta VIA_DDRA    ; Set Port A to Input

    jsr read_byte   ; Read Status
    cmp #STATUS_OK
    beq @status_ok
    
    ; Handle Error
    pha             ; Save status for checking later
    jsr read_byte   ; Consume len_lo from bus
    jsr read_byte   ; Consume len_hi from bus
    lda #$FF
    sta VIA_DDRA    ; Restore bus to output
    pla             ; Restore status
    cmp #STATUS_NO_FILE
    bne @run_fail
    jsr print_file_not_found
    rts
@run_fail:
    jsr print_command_failed
    rts

@status_ok:
    jsr read_byte   ; Read Length Low
    sta savemem_cnt
    jsr read_byte   ; Read Length High
    sta savemem_cnt+1

    ; Check if length >= 2
    lda savemem_cnt+1
    bne @len_ok
    lda savemem_cnt
    cmp #2
    bcs @len_ok
    
    ; Error: File too short
    lda #$FF
    sta VIA_DDRA
    jsr print_command_failed
    rts

@len_ok:
    ; Read Load Address (2 bytes)
    jsr read_byte
    sta savemem_start     ; Low byte
    jsr read_byte
    sta savemem_start+1   ; High byte
    
    ; Adjust length counter (subtract 2)
    sec
    lda savemem_cnt
    sbc #2
    sta savemem_cnt
    lda savemem_cnt+1
    sbc #0
    sta savemem_cnt+1
    
    ; Set write pointer
    lda savemem_start
    sta ptr_temp
    lda savemem_start+1
    sta ptr_temp+1

@load_loop:
    lda savemem_cnt
    ora savemem_cnt+1
    beq @done

    jsr read_byte
    ldy #0
    sta (ptr_temp), y

    inc ptr_temp
    bne @no_inc
    inc ptr_temp+1
@no_inc:
    
    ; Decrement 16-bit counter
    lda savemem_cnt
    bne @dec_lo
    dec savemem_cnt+1
@dec_lo:
    dec savemem_cnt
    jmp @load_loop

@done:
    lda #$FF
    sta VIA_DDRA    ; Restore Port A to Output

    ; Execute via trampoline
    lda savemem_start
    sta str_ptr1
    lda savemem_start+1
    sta str_ptr1+1

    jsr call_handler_indirect
    jsr CRLF        ; Add a newline after the program finishes
    rts

; ---------------------------------------------------------------------------
; guard_requires_mount
; Checks if the filesystem is mounted. If not, prints an error message
; and returns with Carry SET. If mounted, returns with Carry CLEAR.
; ---------------------------------------------------------------------------
guard_requires_mount:
    lda is_mounted_flag
    cmp #1
    beq @mounted      ; Branch if is_mounted_flag == 1

    ; Not mounted, print error
    jsr print_not_mounted
    sec               ; Set Carry to indicate error
    rts

@mounted:
    clc               ; Clear Carry to indicate success
    rts

; ---------------------------------------------------------------------------
; Helper: Print Response Buffer
; ---------------------------------------------------------------------------
print_response:
    ; Setup pointer to RESP_BUFF
    lda #<RESP_BUFF
    sta str_ptr1
    lda #>RESP_BUFF
    sta str_ptr1+1

    ; Use RESP_LEN as counter
    lda RESP_LEN
    sta str_ptr2
    lda RESP_LEN+1
    sta str_ptr2+1

    ldy #0
@pr_loop:
    lda str_ptr2
    ora str_ptr2+1
    beq @pr_done    ; If length is 0, we are done

    lda (str_ptr1), y
    jsr OUTCH

    ; Increment Pointer
    inc str_ptr1
    bne @no_inc
    inc str_ptr1+1
@no_inc:

    ; Decrement Length
    lda str_ptr2
    sec
    sbc #1
    sta str_ptr2
    bcs @pr_loop
    dec str_ptr2+1
    jmp @pr_loop

@pr_done:
    jsr CRLF        ; Ensure we end on a new line
    rts

; --- Message Printing Helpers ---
print_not_mounted:
    ldx #0
@loop:
    lda NOT_MOUNTED_MSG, x
    beq @done
    jsr OUTCH
    inx
    jmp @loop
@done:
    jsr CRLF
    rts

print_mount_fail:
    ldx #0
@loop:
    lda MOUNT_FAIL_MSG, x
    beq @done
    jsr OUTCH
    inx
    jmp @loop
@done:
    jsr CRLF
    rts

print_format_fail:
    ldx #0
@loop:
    lda FORMAT_FAIL_MSG, x
    beq @done
    jsr OUTCH
    inx
    jmp @loop
@done:
    jsr CRLF
    rts

print_command_failed:
    ldx #0
@loop:
    lda COMMAND_FAILED_MSG, x
    beq @done
    jsr OUTCH
    inx
    jmp @loop
@done:
    jsr CRLF
    rts

print_file_not_found:
    ldx #0
@loop:
    lda FILE_NOT_FOUND_MSG, x
    beq @done
    jsr OUTCH
    inx
    jmp @loop
@done:
    jsr CRLF
    rts

print_file_exists:
    ldx #0
@loop:
    lda FILE_EXISTS_MSG, x
    beq @done
    jsr OUTCH
    inx
    jmp @loop
@done:
    jsr CRLF
    rts

; ---------------------------------------------------------------------------
; strcmp_space
; Compares two null-terminated strings. For the first string (user input),
; it treats a space character as a terminator. This allows matching "DIR foo"
; as the command "DIR". The second string (from the command table) must
; match exactly up to its null terminator.
;
; In:  str_ptr1 -> User input string
;      str_ptr2 -> Command table string
; Out: Z=1 if match, Z=0 if no match.
; Clobbers: A, Y
; ---------------------------------------------------------------------------
strcmp_space:
    ldy #0
@loop:
    lda (str_ptr2), y
    beq @check_input_end  ; End of command string

    cmp (str_ptr1), y
    bne @no_match

    iny
    jmp @loop

@check_input_end:
    ; Command string ended, check if input ended or has space
    lda (str_ptr1), y
    beq @match           ; Both ended
    cmp #' '
    beq @match           ; Input has space (command only)
    
@no_match:
    ; Clear Z flag to indicate no match
    lda #1
    cmp #0
    rts

@match:
    ; Set Z flag to indicate match
    lda #0
    cmp #0
    rts

; ---------------------------------------------------------------------------
; get_first_arg
; Finds the first argument in the INPUT_BUFFER after the command.
; Skips leading spaces.
; Out: arg_ptr points to the start of the null-terminated argument.
;      (modifies INPUT_BUFFER by inserting a null)
; Clobbers: A, X, Y
; ---------------------------------------------------------------------------
get_first_arg:
    ; Initialize arg_ptr to a safe empty string to prevent using stale data.
    lda #<empty_str
    sta arg_ptr
    lda #>empty_str
    sta arg_ptr+1
    ldx #0
    ; Skip command
@skip_cmd:
    lda INPUT_BUFFER, x
    beq @done ; No arguments
    cmp #' '
    beq @found_space
    inx
    jmp @skip_cmd
@found_space:
    ; Skip spaces
@skip_spaces:
    inx
    lda INPUT_BUFFER, x
    cmp #' '
    bne @found_arg
    jmp @skip_spaces
@found_arg:
    ; Set pointer to start of arg
    txa
    clc
    adc #<INPUT_BUFFER
    sta arg_ptr
    lda #>INPUT_BUFFER
    adc #0
    sta arg_ptr+1
@done:
    rts

; ---------------------------------------------------------------------------
; get_first_arg_as_pico_arg
; Copies the first argument from INPUT_BUFFER into ARG_BUFF for the pico.
; Sets ARG_LEN.
; ---------------------------------------------------------------------------
get_first_arg_as_pico_arg:
    jsr get_first_arg
    ldy #0
@copy_loop:
    lda (arg_ptr), y
    sta ARG_BUFF, y
    beq @done
    iny
    jmp @copy_loop
@done:
    sty ARG_LEN      ; Set ARG_LEN to length of string (excluding null)
    inc ARG_LEN      ; Add 1 for the null terminator
    rts

; ---------------------------------------------------------------------------
; parse_hex_word - Parse hex word from (arg_ptr)
; Returns: A/X = 16-bit value (A=lo, X=hi), Carry set on error
; Clobbers: Y, ptr_temp
; ---------------------------------------------------------------------------
parse_hex_word:
    ldy #0
    lda #0
    sta ptr_temp+1        ; Temp high byte
    sta ptr_temp          ; Temp low byte

@parse_loop:
    lda (arg_ptr), y
    beq @done
    cmp #' '
    beq @done

    jsr hex_nibble
    bcs @error

    ; Shift current value left 4 bits
    asl ptr_temp
    rol ptr_temp+1
    asl ptr_temp
    rol ptr_temp+1
    asl ptr_temp
    rol ptr_temp+1
    asl ptr_temp
    rol ptr_temp+1

    ; Add new nibble
    ora ptr_temp
    sta ptr_temp

    iny
    jmp @parse_loop

@done:
    lda ptr_temp
    ldx ptr_temp+1
    clc
    rts

@error:
    sec
    rts

hex_nibble: ; in: A, out: A=nibble, C=0 on success, C=1 on error
    cmp #'0'
    bcc @not_hex
    cmp #'9'+1
    bcc @is_digit
    and #%11011111 ; to upper case
    cmp #'A'
    bcc @not_hex
    cmp #'F'+1
    bcs @not_hex
    sec
    sbc #('A' - 10)
    clc
    rts
@is_digit:
    sec
    sbc #'0'
    clc
    rts
@not_hex:
    sec
    rts

; ===========================================================================
; DATA
; ===========================================================================



; --- Command Dispatch Table ---
; Format: .word string_address, handler_address
; Terminated by a .word 0
command_table:
    .word cmd_str_dir,   do_dir
    .word cmd_str_mount, do_mount
    .word cmd_str_pwd,   do_pwd
    .word cmd_str_cd,    do_cd
    .word cmd_str_mkdir, do_mkdir
    .word cmd_str_del,   do_del
    .word cmd_str_format, do_format
    .word cmd_str_ping,  do_ping
    .word cmd_str_help,  do_help
    .word cmd_str_connect, do_connect
    .word cmd_str_exit,  do_exit
    .word cmd_savemem_str, do_savemem
    .word cmd_loadmem_str, do_loadmem
    .word cmd_str_type,  do_type
    .word cmd_str_rename, do_rename
    .word cmd_str_run,   do_run
    .word cmd_str_copy,  do_copy
    .word cmd_str_touch, do_touch
    ; Aliases
    .word cmd_str_ls,    do_dir
    .word cmd_str_rm,    do_del
    .word cmd_str_cat,   do_type
    .word cmd_str_mv,    do_rename
    .word cmd_str_cp,    do_copy
    .word 0 ; End of table

; --- Command Strings ---
cmd_str_dir:   .asciiz "DIR"
cmd_str_mount: .asciiz "MOUNT"
cmd_str_pwd:   .asciiz "PWD"
cmd_str_cd:    .asciiz "CD"
cmd_str_mkdir: .asciiz "MKDIR"
cmd_str_del:   .asciiz "DEL"
cmd_str_format:.asciiz "FORMAT"
cmd_str_ping:  .asciiz "PING"
cmd_str_help:  .asciiz "HELP"
cmd_str_connect: .asciiz "CONNECT"
cmd_str_exit:  .asciiz "EXIT"
cmd_savemem_str: .asciiz "SAVEMEM"
cmd_loadmem_str: .asciiz "LOADMEM"
cmd_str_type:  .asciiz "TYPE"
cmd_str_ls:    .asciiz "LS"
cmd_str_rm:    .asciiz "RM"
cmd_str_cat:   .asciiz "CAT"
cmd_str_rename:.asciiz "RENAME"
cmd_str_mv:    .asciiz "MV"
cmd_str_copy:  .asciiz "COPY"
cmd_str_cp:    .asciiz "CP"
cmd_str_touch: .asciiz "TOUCH"
cmd_str_run:   .asciiz "RUN"
empty_str:     .asciiz ""
str_bin_prefix:.asciiz "/BIN/"
str_bin_suffix:.asciiz ".BIN"
str_run_prefix:.asciiz "RUN "

START_MSG:       .asciiz "6502 Shell Ready"
ERR_MSG:         .asciiz "TIMEOUT"
UNK_MSG:         .asciiz "Unknown Command"
HELP_MSG:
    .byte "BUILT-IN COMMANDS:", $0D, $0A
    .byte "  CD, CONNECT, COPY(cp), DEL(rm), DIR(ls), EXIT, FORMAT", $0D, $0A
    .byte "  HELP, LOADMEM, MKDIR, MOUNT, PING, PWD", $0D, $0A
    .byte "  RENAME(mv), RUN, SAVEMEM, TOUCH, TYPE(cat)", $0D, $0A, $0D, $0A
    .byte "EXTERNAL COMMANDS (/BIN):", $0D, $0A
    .byte "  BENCH", 0
NOT_MOUNTED_MSG: .asciiz "MEDIA NOT MOUNTED"
MOUNT_OK_MSG:    .asciiz "MEDIA MOUNTED"
CONNECT_OK_MSG: .asciiz "CONNECTED"
MOUNT_FAIL_MSG:  .asciiz "MOUNT FAILED"
FORMAT_OK_MSG:   .asciiz "FORMAT COMPLETE"
FORMAT_FAIL_MSG: .asciiz "FORMAT FAILED"
COMMAND_FAILED_MSG: .asciiz "COMMAND FAILED"
FILE_NOT_FOUND_MSG: .asciiz "NO SUCH FILE OR DIRECTORY"
FILE_EXISTS_MSG:    .asciiz "FILE EXISTS"
WAIT_MSG:           .asciiz "Please wait..."

; --- SAVEMEM Messages ---
SAVING_MSG:         .asciiz "Saving..."
SAVED_MSG:          .asciiz "Done"
PARSE_ERROR_MSG:    .asciiz "Parse error"
ARG_ERROR_MSG:      .asciiz "Argument error"
RANGE_ERROR_MSG:    .asciiz "Invalid range"