; cmd_shell.s - 6502 Shell for Pico W Smart Peripheral
; Target: RAM @ $1000
; Target: ROM @ $E000 (DDOS Segment)

.include "common/pico_def.inc"

.export DDOS_START

; Compatibility: If RESET is not defined (e.g. RAM build), default to $FF00
.ifndef RESET
RESET = $FF00
.endif

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

; --- BSS variables for RENAME/COPY ---
path_buf1:        .res 128 ; Temp buffer for first path
path_buf2:        .res 128 ; Temp buffer for second path
path_idx:         .res 1   ; Index for search path loop
line_count:       .res 1   ; Counter for paging

.segment "DDOS"

DDOS_START:
    ; Start on a fresh line
    jsr CRLF

    ; -----------------------------------------------------------------------
    ; Debug: Print Start Marker "STR"
    ; -----------------------------------------------------------------------
    lda #<START_MSG
    sta ptr_temp
    lda #>START_MSG
    sta ptr_temp+1
    jsr print_string
    jsr CRLF

    ; Initialize the VIA and Pico interface
    jsr pico_init

    ; --- Auto-Mount / Check Mount Status ---
    ; We send a MOUNT command. If the Pico is already mounted (via boot logic),
    ; it will return OK immediately. If not, it will try to mount/format.
    lda #CMD_FS_MOUNT
    sta CMD_ID
    lda #0
    sta ARG_LEN
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    bne @no_mount
    lda #1
    sta is_mounted_flag
    jmp @mount_done
@no_mount:
    lda #0
    sta is_mounted_flag
@mount_done:

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
    lda #0
    sta line_count      ; Reset paging counter at prompt

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
    lda #0
    sta path_idx

@path_search_loop:
    ldx path_idx
    lda search_paths, x
    sta ptr_temp
    inx
    lda search_paths, x
    sta ptr_temp+1
    
    ; Check for end of list
    lda ptr_temp
    ora ptr_temp+1
    bne @path_valid
    jmp unknown_command
@path_valid:

    ; 1. Construct "<PREFIX><CMD>.BIN" in ARG_BUFF
    ldx #0 ; reset ARG_BUFF index

    ; Check for special "." prefix which means current directory
    ldy #0
    lda (ptr_temp), y
    cmp #'.'
    bne @copy_prefix_literal
    iny
    lda (ptr_temp), y
    bne @copy_prefix_literal ; Not exactly "."

    ; --- Use current_path as prefix ---
@use_current_path:
    ; Ensure we start with a slash to guarantee absolute path
    lda current_path
    cmp #'/'
    beq @copy_cwd_start
    lda #'/'
    sta ARG_BUFF, x
    inx
@copy_cwd_start:
    ldy #0
@copy_cwd:
    lda current_path, y
    beq @cwd_copied
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_cwd
@cwd_copied:
    ; Append a separator if current_path is not "/"
    cpx #1
    bne @append_separator
    lda ARG_BUFF
    cmp #'/'
    beq @prefix_done ; It is root, don't add another slash
@append_separator:
    lda #'/'
    sta ARG_BUFF, x
    inx
    jmp @prefix_done

@copy_prefix_literal:
    ; Fallback to copying the literal prefix string
    ldy #0
@copy_loop:
    lda (ptr_temp), y
    beq @prefix_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_loop

@prefix_done:
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
    ; If we stopped at a space, include it in savemem_len so it gets consumed/overwritten
    lda INPUT_BUFFER, y
    cmp #' '
    bne @save_len
    iny
@save_len:
    sty savemem_len ; Save command length (using savemem_len as temp)

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
    inx
    stx ARG_LEN

    ; 2. Check if file exists (CMD_FS_STAT)
    lda #CMD_FS_STAT
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @found_file

    ; Not found, try next path
    inc path_idx
    inc path_idx
    jmp @path_search_loop

@found_file:
    ; 3. File exists! Rewrite INPUT_BUFFER.
    ; We need to shift arguments to make room for "RUN " + PATH + " ".
    ; Destination Index for args = 4 ("RUN ") + ARG_LEN + 1 (" ").
    ; ARG_LEN includes the null terminator.
    lda ARG_LEN
    clc
    adc #4
    sta ptr_temp ; Dest Index for start of args
    
    ; Setup Source Pointer (str_ptr1) = $0300
    lda #<INPUT_BUFFER
    sta str_ptr1
    lda #>INPUT_BUFFER
    sta str_ptr1+1
    
    ; Setup Dest Pointer (str_ptr2) = $0300 + Shift
    ; Shift = Dest Index - Source Index (savemem_len)
    lda ptr_temp
    sec
    sbc savemem_len
    clc
    adc #<INPUT_BUFFER
    sta str_ptr2
    lda #>INPUT_BUFFER
    adc #0
    sta str_ptr2+1
    
    ; Find end of INPUT_BUFFER (null terminator) to know how much to copy
    ldx savemem_len
@find_end_dynamic:
    lda INPUT_BUFFER, x
    beq @found_end_dynamic
    inx
    jmp @find_end_dynamic
@found_end_dynamic:
    ; X is index of null terminator.
    ; Copy backwards from X down to savemem_len.
    ; We use Y as index for (str_ptr) addressing, so Y = X.
    txa
    tay
    
@shift_loop_zp:
    lda (str_ptr1), y
    sta (str_ptr2), y
    cpy savemem_len
    beq @shift_done_zp
    dey
    jmp @shift_loop_zp
@shift_done_zp:

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
    ; ARG_BUFF contains the full path to the executable
    ldy #0
@write_path:
    lda ARG_BUFF, y
    beq @write_path_done
    sta INPUT_BUFFER, x
    inx
    iny
    jmp @write_path
@write_path_done:
    ; Check if there are arguments to separate
    ; The arguments start at x+1 (since x points to where the null/space goes)
    inx
    lda INPUT_BUFFER, x
    beq @no_args
    dex
    lda #' '
    sta INPUT_BUFFER, x
    jmp @exec
@no_args:
    dex
    lda #0
    sta INPUT_BUFFER, x
@exec:

    ; 6. Execute
    jmp do_run

unknown_command:
    lda #<UNK_MSG
    sta ptr_temp
    lda #>UNK_MSG
    sta ptr_temp+1
    jsr print_string
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
    ldx #0
    jsr resolve_path_to_arg_buff
    bcs @dir_path_error
    
    lda #0
    sta ARG_BUFF, x
    inx
    stx ARG_LEN

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

@dir_path_error:
    jsr print_command_failed
    rts

do_pwd:
    jsr guard_requires_mount
    bcc @proceed
    rts
@proceed:

   lda #<current_path
    sta ptr_temp
    lda #>current_path
    sta ptr_temp+1
    jsr print_string
    
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
    lda #<MOUNT_OK_MSG
    sta ptr_temp
    lda #>MOUNT_OK_MSG
    sta ptr_temp+1
    jsr print_string
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
    lda #<FORMAT_OK_MSG
    sta ptr_temp
    lda #>FORMAT_OK_MSG
    sta ptr_temp+1
    jsr print_string
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
    lda #<WAIT_MSG
    sta ptr_temp
    lda #>WAIT_MSG
    sta ptr_temp+1
    jsr print_string
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
    lda #<CONNECT_OK_MSG
    sta ptr_temp
    lda #>CONNECT_OK_MSG
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    rts

do_help:
    lda #<HELP_MSG
    sta ptr_temp
    lda #>HELP_MSG
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    rts

do_exit:
    jmp RESET

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
    lda savemem_len
    sta savemem_cnt
    lda savemem_len+1
    sta savemem_cnt+1

    ; Print "Saving..." message
    lda #<SAVING_MSG
    sta ptr_temp
    lda #>SAVING_MSG
    sta ptr_temp+1
    jsr print_string

    ; Restore pointer to memory start for streaming
    lda savemem_start
    sta ptr_temp
    lda savemem_start+1
    sta ptr_temp+1

    jsr common_write_stream_from_mem

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
    lda #<SAVED_MSG
    sta ptr_temp
    lda #>SAVED_MSG
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
@done:
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
    jsr common_send_loadmem_request
    cmp #STATUS_OK
    beq @status_ok
    
    ; Handle Error (VIA_DDRA is already Output)
    cmp #STATUS_NO_FILE
    bne @loadmem_fail
    jsr print_file_not_found
    rts
@loadmem_fail:
    jsr print_command_failed
    rts

@status_ok:
    jsr common_read_stream_to_mem
    
    jsr CRLF
    lda #<SAVED_MSG ; Reuse "Done" message
    sta ptr_temp
    lda #>SAVED_MSG
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    rts

cmd_parse_error:
    lda #<PARSE_ERROR_MSG
    sta ptr_temp
    lda #>PARSE_ERROR_MSG
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    rts

cmd_arg_error:
    lda #<ARG_ERROR_MSG
    sta ptr_temp
    lda #>ARG_ERROR_MSG
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    rts

cmd_invalid_range:
    lda #<RANGE_ERROR_MSG
    sta ptr_temp
    lda #>RANGE_ERROR_MSG
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    rts

timeout_error:
    jsr CRLF
    lda #<ERR_MSG
    sta ptr_temp
    lda #>ERR_MSG
    sta ptr_temp+1
    jsr print_string
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
    ; Check if target is a directory
    lda RESP_BUFF
    cmp #2          ; LFS_TYPE_DIR
    bne @is_file
    jsr print_command_failed
    rts
@is_file:
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
    jsr common_send_loadmem_request
    cmp #STATUS_OK
    beq @status_ok
    
    ; Handle Error (VIA_DDRA is already Output)
    cmp #STATUS_NO_FILE
    bne @type_fail
    jsr print_file_not_found
    rts
@type_fail:
    jsr print_command_failed
    rts

@status_ok:
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
    jsr shell_outch
    
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
    jsr shell_outch

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
    jsr shell_outch
    jsr shell_outch
    jsr shell_outch
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
    jsr shell_outch
    lda #' '
    jsr shell_outch
    rts

print_hex_ascii:
    lda #' '
    jsr shell_outch
    lda #'|'
    jsr shell_outch
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
    jsr shell_outch
    inx
    jmp @ascii_loop
@ascii_done:
    lda #'|'
    jsr shell_outch
    jsr shell_crlf
    rts

; ---------------------------------------------------------------------------
; do_rename - Rename a file
; do_copy - Copy a file
; Format: RENAME/COPY <old> <new>
; ---------------------------------------------------------------------------
do_copy:
    lda #CMD_FS_COPY
    sta pending_cmd
    jmp common_transfer

do_rename:
    lda #CMD_FS_RENAME
    sta pending_cmd
    ; Fall through

common_transfer:
    jsr guard_requires_mount
    bcc @proceed
    rts
@proceed:
    ; --- 1. Parse and resolve the OLD path into path_buf1 ---
    jsr get_first_arg
    bcc @old_arg_ok
    jmp cmd_arg_error
@old_arg_ok:
    ldx #0
    jsr resolve_path_to_arg_buff
    bcc @old_path_ok
    jmp cmd_arg_error ; Path too long
@old_path_ok:
    lda #0
    sta ARG_BUFF, x
    ; Copy resolved OLD path from ARG_BUFF to path_buf1
    ldy #0
@copy_old_to_buf:
    lda ARG_BUFF, y
    sta path_buf1, y
    beq @old_copied
    iny
    jmp @copy_old_to_buf
@old_copied:

    ; --- 2. Parse and resolve the NEW path into path_buf2 ---
    jsr get_next_arg
    bcc @new_ok_arg
    jmp cmd_arg_error
@new_ok_arg:
    ldx #0
    jsr resolve_path_to_arg_buff
    bcc @new_path_ok
    jmp cmd_arg_error ; Path too long
@new_path_ok:
    lda #0
    sta ARG_BUFF, x
    stx ptr_temp ; Save length of new path
    ; Copy resolved NEW path from ARG_BUFF to path_buf2
    ldy #0
@copy_new_to_buf:
    lda ARG_BUFF, y
    sta path_buf2, y
    beq @new_copied
    iny
    jmp @copy_new_to_buf
@new_copied:

    ; --- 3. Check if NEW path is a directory and construct full dest path ---
    ; Syntactic check: does path_buf2 end with a '/'?
    ldx ptr_temp ; length of new path
    cpx #0
    beq @stat_check ; empty path, let stat handle it
    dex
    lda path_buf2, x
    cmp #'/'
    beq @is_dir_target

@stat_check:
    ; Semantic check: is it a directory according to the filesystem?
    ; For the STAT check, ARG_BUFF already contains the new path
    ldx ptr_temp
    stx ARG_LEN
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
    ; --- 4. Construct final argument buffer for Pico: old_path\0new_path\0 ---
    ; Copy path_buf1 to ARG_BUFF
    ldx #0
@copy_old_final:
    lda path_buf1, x
    sta ARG_BUFF, x
    beq @old_final_done
    inx
    jmp @copy_old_final
@old_final_done:
    inx ; Skip null terminator

    ; Append path_buf2
    ldy #0
@copy_new_final:
    lda path_buf2, y
    sta ARG_BUFF, x
    beq @new_final_done
    inx
    iny
    jmp @copy_new_final
@new_final_done:
    stx ARG_LEN
    jmp @send_command

@is_dir_target:
    ; It IS a directory target. Append source filename from path_buf1 to path_buf2.
    ; Find end of path_buf2
    ldx #0
@find_end_new:
    lda path_buf2, x
    beq @found_end_new
    inx
    jmp @find_end_new
@found_end_new:
    ; Ensure separator if not present
    cpx #0
    beq @find_filename
    dex
    lda path_buf2, x
    inx
    cmp #'/'
    beq @find_filename
    lda #'/'
    sta path_buf2, x
    inx

@find_filename:
    ; Find last component of path_buf1 (the source filename)
    ldy #0
    sty ptr_temp ; ptr_temp will hold index of start of filename in path_buf1
@scan_old:
    lda path_buf1, y
    beq @copy_filename
    cmp #'/'
    bne @next_char
    tya
    clc
    adc #1
    sta ptr_temp ; Point after slash
@next_char:
    iny
    jmp @scan_old

@copy_filename:
    ; Append filename from path_buf1 to path_buf2
    ldy ptr_temp
@copy_loop:
    lda path_buf1, y
    beq @copy_done
    sta path_buf2, x
    inx
    iny
    jmp @copy_loop
@copy_done:
    ; path_buf2 now holds the complete destination path
    jmp @not_dir_target ; Go to construct final args

@send_command:
    ; --- 5. Send command to Pico ---
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
    jsr common_send_loadmem_request
    cmp #STATUS_OK
    beq @status_ok
    
    ; Handle Error (VIA_DDRA is already Output)
    cmp #STATUS_NO_FILE
    bne @run_fail
    jsr print_file_not_found
    rts
@run_fail:
    jsr print_command_failed
    rts

@status_ok:
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

    ; Pass CWD pointer to transient command in $5E/$5F (t_ptr_temp)
    lda #<current_path
    sta $5E
    lda #>current_path
    sta $5F

    jsr common_read_stream_to_mem

    ; Execute via trampoline
    lda savemem_start
    sta str_ptr1
    lda savemem_start+1
    sta str_ptr1+1

    jsr call_handler_indirect
    jsr shell_crlf  ; Add a newline after the program finishes
    rts

; ---------------------------------------------------------------------------
; do_jump - Jump to address
; Format: JUMP <address>
; ---------------------------------------------------------------------------
do_jump:
    jsr get_first_arg
    jsr parse_hex_word
    bcc @ok
    jmp cmd_parse_error
@ok:
    jmp (ptr_temp)

; ---------------------------------------------------------------------------
; common_send_loadmem_request
; Sends CMD_FS_LOADMEM and ARG_BUFF. Reads response header.
; Returns: A = Status.
;          If A == STATUS_OK:
;             savemem_cnt = Data Length
;             VIA_DDRA = Input ($00)
;          If A != STATUS_OK:
;             VIA_DDRA = Output ($FF)
; ---------------------------------------------------------------------------
common_send_loadmem_request:
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
    pha             ; Save status
    jsr read_byte   ; Consume len_lo
    jsr read_byte   ; Consume len_hi
    lda #$FF
    sta VIA_DDRA    ; Restore bus to output
    pla             ; Restore status
    rts

@status_ok:
    pha             ; Save status (STATUS_OK)
    jsr read_byte   ; Read Length Low
    sta savemem_cnt
    jsr read_byte   ; Read Length High
    sta savemem_cnt+1
    pla             ; Restore status
    rts

; ---------------------------------------------------------------------------
; common_read_stream_to_mem
; Reads savemem_cnt bytes from Pico and stores them at (ptr_temp).
; Restores VIA_DDRA to Output ($FF) when done.
; ---------------------------------------------------------------------------
common_read_stream_to_mem:
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
    rts

; ---------------------------------------------------------------------------
; common_write_stream_from_mem
; Writes savemem_cnt bytes from (ptr_temp) to Pico.
; Updates ptr_temp and savemem_cnt.
; ---------------------------------------------------------------------------
common_write_stream_from_mem:
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
    jsr OUTCH ; Direct OUTCH for dots (no paging needed)
@no_dot:
    jmp @stream_loop
@stream_done:
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
    jsr shell_outch

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
    jsr shell_crlf  ; Ensure we end on a new line
    rts

; ---------------------------------------------------------------------------
; Helper: Print String from ptr_temp (Paging Enabled)
; ---------------------------------------------------------------------------
print_string:
    ldy #0
@loop:
    lda (ptr_temp), y
    beq @done
    jsr shell_outch
    iny
    jmp @loop
@done:
    rts

; ---------------------------------------------------------------------------
; Helper: Print String Raw (No Paging) - Used for "More" prompt
; ---------------------------------------------------------------------------
print_string_raw:
    ldy #0
@loop:
    lda (ptr_temp), y
    beq @done
    jsr OUTCH
    iny
    jmp @loop
@done:
    rts

; ---------------------------------------------------------------------------
; Paging Wrappers
; ---------------------------------------------------------------------------
shell_outch:
    cmp #$0A        ; Check for LF
    bne @raw
    pha
    jsr check_paging
    pla
@raw:
    jmp OUTCH

shell_crlf:
    jsr CRLF
    ; Fall through to check_paging

check_paging:
    pha
    txa
    pha
    tya
    pha

    inc line_count
    lda line_count
    cmp #22         ; Screen Limit
    bcc @done

    ; Limit reached, pause
    lda ptr_temp    ; Save ptr_temp
    pha
    lda ptr_temp+1
    pha

    lda #<MORE_MSG
    sta ptr_temp
    lda #>MORE_MSG
    sta ptr_temp+1
    jsr print_string_raw

@wait_key:
    jsr CHRIN       ; Wait for key
    bcc @wait_key   ; Loop until key pressed (Carry Set)
    jsr CRLF        ; Newline after keypress
    lda #0
    sta line_count

    pla             ; Restore ptr_temp
    sta ptr_temp+1
    pla
    sta ptr_temp

@done:
    pla
    tay
    pla
    tax
    pla
    rts

; --- Message Printing Helpers ---
print_not_mounted:
    lda #<NOT_MOUNTED_MSG
    sta ptr_temp
    lda #>NOT_MOUNTED_MSG
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    rts

print_mount_fail:
    lda #<MOUNT_FAIL_MSG
    sta ptr_temp
    lda #>MOUNT_FAIL_MSG
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    rts

print_format_fail:
    lda #<FORMAT_FAIL_MSG
    sta ptr_temp
    lda #>FORMAT_FAIL_MSG
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    rts

print_command_failed:
    lda #<COMMAND_FAILED_MSG
    sta ptr_temp
    lda #>COMMAND_FAILED_MSG
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    rts

print_file_not_found:
    lda #<FILE_NOT_FOUND_MSG
    sta ptr_temp
    lda #>FILE_NOT_FOUND_MSG
    sta ptr_temp+1
    jsr print_string
    jsr CRLF
    rts

print_file_exists:
    lda #<FILE_EXISTS_MSG
    sta ptr_temp
    lda #>FILE_EXISTS_MSG
    sta ptr_temp+1
    jsr print_string
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
    .word cmd_str_dir,    do_dir
    .word cmd_str_mount,  do_mount
    .word cmd_str_pwd,    do_pwd
    .word cmd_str_cd,     do_cd
    .word cmd_str_mkdir,  do_mkdir
    .word cmd_str_del,    do_del
    .word cmd_str_format, do_format
    .word cmd_str_ping,   do_ping
    .word cmd_str_help,   do_help
    .word cmd_str_connect,do_connect
    .word cmd_str_exit,   do_exit
    .word cmd_savemem_str,do_savemem
    .word cmd_loadmem_str,do_loadmem
    .word cmd_str_type,   do_type
    .word cmd_str_rename, do_rename
    .word cmd_str_run,    do_run
    .word cmd_str_copy,   do_copy
    .word cmd_str_touch,  do_touch
    .word cmd_str_jump,   do_jump
    ; Aliases
    .word cmd_str_ls,    do_dir
    .word cmd_str_rm,    do_del
    .word cmd_str_cat,   do_type
    .word cmd_str_mv,    do_rename
    .word cmd_str_cp,    do_copy
    .word 0 ; End of table

; --- Search Paths ---
; Order: Current Directory, then /BIN/
search_paths:
    .word current_path_str
    .word str_bin_prefix
    .word 0

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
cmd_str_jump:  .asciiz "JUMP"
empty_str:     .asciiz ""
str_bin_prefix:.asciiz "/BIN/"
current_path_str: .asciiz "."
str_bin_suffix:.asciiz ".BIN"
str_run_prefix:.asciiz "RUN "

START_MSG:       .asciiz "6502 Shell Ready"
MORE_MSG:        .asciiz "--More--"
ERR_MSG:         .asciiz "TIMEOUT"
UNK_MSG:         .asciiz "UNKNOWN"
HELP_MSG:
    .byte "BUILT-IN: CD CONNECT CP DEL DIR EXIT FORMAT HELP LOADMEM MKDIR MOUNT PING PWD MV RUN SAVEMEM TOUCH CAT", $0D, $0A
    .byte "EXTERNAL: *See BIN/ or docs", 0
NOT_MOUNTED_MSG: .asciiz "NO MOUNT"
MOUNT_OK_MSG:    .asciiz "MEDIA MOUNTED"
CONNECT_OK_MSG: .asciiz "CONNECTED"
MOUNT_FAIL_MSG:  .asciiz "FAILED"
FORMAT_OK_MSG:   .asciiz "FORMAT COMPLETE"
FORMAT_FAIL_MSG: .asciiz "FAILED"
COMMAND_FAILED_MSG: .asciiz "FAILED"
FILE_NOT_FOUND_MSG: .asciiz "NOT FOUND"
FILE_EXISTS_MSG:    .asciiz "FILE EXISTS"
WAIT_MSG:           .asciiz "Please wait..."

; --- SAVEMEM Messages ---
SAVING_MSG:         .asciiz "Saving..."
SAVED_MSG:          .asciiz "Done"
PARSE_ERROR_MSG:    .asciiz "Parse error"
ARG_ERROR_MSG:      .asciiz "Argument error"
RANGE_ERROR_MSG:    .asciiz "Invalid range"
