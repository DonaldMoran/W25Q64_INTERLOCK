; cmd_shell.s - 6502 Shell for Pico W Smart Peripheral
; Target: RAM @ $1000

.include "common/pico_def.inc"

.import pico_init, pico_send_request
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

; --- Zero Page pointers for strcmp ---
str_ptr1 = $FB ; 2 bytes
str_ptr2 = $FD ; 2 bytes
; --- Zero Page pointers for argument parsing ---
arg_ptr = $F9 ; 2 bytes

.segment "BSS"
current_path: .res 128 ; Buffer for the current working directory
is_mounted_flag: .res 1 ; 0 = not mounted, 1 = mounted

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
    beq unknown_command

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
    sta $FB ; Temp store for JMP indirect (use our ZP area)
    inx
    lda command_table, x
    sta $FC
    jsr call_handler_indirect
    rts ; Return to shell_loop

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
    ; Jumps to the routine pointed to by $FB/$FC.
    ; The RTS from the called handler will return to our caller.
    jmp ($FB)

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

    ; No argument: send "/" as the path.
    lda #'/'
    sta ARG_BUFF
    lda #0
    sta ARG_BUFF+1
    lda #2              ; Length is 2 (char + null terminator)
    sta ARG_LEN
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

    ; For CD, we just manipulate the local current_path buffer.
    ; No Pico communication is needed.
    ; This is a placeholder for the full path resolution logic.
    ; For now, it only supports absolute paths.
    jsr get_first_arg
    ldy #0
@copy_loop:
    lda (arg_ptr), y
    sta current_path, y
    beq @copy_done
    iny
    cpy #127 ; Don't overflow buffer
    bne @copy_loop
    lda #0
    sta current_path, y
@copy_done:
    rts

do_mkdir:
    jsr guard_requires_mount
    bcc @proceed
    rts
@proceed:

    ; For now, we assume the argument is an absolute path
    ; A real implementation would call resolve_path here.
    jsr get_first_arg_as_pico_arg
    lda #CMD_FS_MKDIR
    sta CMD_ID
    ; ARG_LEN is set by get_first_arg_as_pico_arg
    jsr pico_send_request
    bcc @mkdir_ok
    jsr timeout_error
    rts
@mkdir_ok:
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @mkdir_success
    jsr print_command_failed
@mkdir_success:
    rts

do_del:
    jsr guard_requires_mount
    bcc @proceed
    rts
@proceed:

    jsr get_first_arg_as_pico_arg
    lda #CMD_FS_REMOVE
    sta CMD_ID
    ; ARG_LEN is set by get_first_arg_as_pico_arg
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
@del_success:
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
    ;We should only attempt to connect to the network if we are not already mounted.
    ;Otherwise it does not function as expected.
    ;Note: the following is based on your previous implementation
    ;It hardcodes the network credentials

    ;No need for the mount requirement

    ; Copy to the Pico's argument buffer.
    lda #0              ; No arguments
    sta ARG_LEN

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
connect_msg_loop:
    lda CONNECT_OK_MSG, x
    beq @connect_done
    jsr OUTCH
    inx
@connect_done:
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
    sta $FB
    lda #>RESP_BUFF
    sta $FC

    ; Use RESP_LEN as counter
    lda RESP_LEN
    sta $FD
    lda RESP_LEN+1
    sta $FE

    ldy #0
@pr_loop:
    lda $FD
    ora $FE
    beq @pr_done    ; If length is 0, we are done

    lda ($FB), y
    jsr OUTCH

    ; Increment Pointer
    inc $FB
    bne @no_inc
    inc $FC
@no_inc:

    ; Decrement Length
    lda $FD
    sec
    sbc #1
    sta $FD
    bcs @pr_loop
    dec $FE
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
    cmp #0
    beq @end_of_str2 ; End of command table string

    cmp (str_ptr1), y
    bne @no_match

    iny
    jmp @loop

@end_of_str2:
    ; Table string ended. Check if input string also ends (or has a space)
    lda (str_ptr1), y
    cmp #0
    beq @match ; Match if both are null
    cmp #' '
    ; beq @match ; Match if input has a space (Z will be set)

@match:
    ; Z flag is set if they match
    rts

@no_match:
    ; Strings are different. Z flag is clear.
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
empty_str:     .asciiz ""

START_MSG:       .asciiz "6502 Shell Ready"
ERR_MSG:         .asciiz "TIMEOUT"
UNK_MSG:         .asciiz "Unknown Command"
HELP_MSG:        .asciiz "CMDS: CD, CONNECT, DEL, DIR, EXIT, FORMAT, HELP, MKDIR, MOUNT, PING, PWD"
NOT_MOUNTED_MSG: .asciiz "MEDIA NOT MOUNTED"
MOUNT_OK_MSG:    .asciiz "MEDIA MOUNTED"
CONNECT_OK_MSG: .asciiz "CONNECTING"
MOUNT_FAIL_MSG:  .asciiz "MOUNT FAILED"
FORMAT_OK_MSG:   .asciiz "FORMAT COMPLETE"
FORMAT_FAIL_MSG: .asciiz "FORMAT FAILED"
COMMAND_FAILED_MSG: .asciiz "COMMAND FAILED"
FILE_NOT_FOUND_MSG: .asciiz "FILE NOT FOUND"