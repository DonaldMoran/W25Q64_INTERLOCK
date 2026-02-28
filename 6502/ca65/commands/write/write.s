; write.s - Simple text editor (FINAL VERSION with special key handling)
; Location: 6502/ca65/commands/write/write.s

; ---------------------------------------------------------------------------
; External symbols
; ---------------------------------------------------------------------------
.include "pico_def.inc"

.import pico_send_request, send_byte, read_byte
.import CMD_ID, ARG_LEN, ARG_BUFF, LAST_STATUS, RESP_LEN, RESP_BUFF

; ---------------------------------------------------------------------------
; System calls & Constants
; ---------------------------------------------------------------------------
OUTCH = $FFEF    ; Print character in A
ACIA_DATA = $5000


INPUT_BUFFER   = $0300

; ---------------------------------------------------------------------------
; Zero page (USE ONLY $58-$5F)
; ---------------------------------------------------------------------------
t_arg_ptr    = $58  ; 2 bytes - Argument pointer
t_str_ptr1   = $5A  ; 2 bytes - Text Buffer Pointer (current position)
t_str_ptr2   = $5C  ; 2 bytes - String Printing / Streaming Pointer
t_ptr_temp   = $5E  ; 2 bytes - Temp / Length Counter

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
TEXT_BUFFER_SIZE = 4096  ; 4KB text buffer

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
    ; Preserve registers
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

    ; Initialize text buffer pointer to start of FIXED buffer
    lda #<text_buffer_fixed
    sta t_str_ptr1
    lda #>text_buffer_fixed
    sta t_str_ptr1+1
    
    ; Clear the entire buffer at startup
    lda #<text_buffer_fixed
    sta t_str_ptr2
    lda #>text_buffer_fixed
    sta t_str_ptr2+1
    ldx #0
    ldy #0
@clear_buffer:
    lda #0
    sta (t_str_ptr2), y
    iny
    bne @clear_buffer
    inc t_str_ptr2+1
    inx
    cpx #(TEXT_BUFFER_SIZE / 256)  ; Clear full buffer size
    bne @clear_buffer

    ; Reset pointer to start
    lda #<text_buffer_fixed
    sta t_str_ptr1
    lda #>text_buffer_fixed
    sta t_str_ptr1+1

    ; Parse Filename Argument
    jsr parse_filename
    
    ; Initialize UI
    jsr init_ui
    
    ; --- Editor Loop ---
editor_loop:
    jsr CHRIN
    
    ; Check for escape sequences (arrow keys, function keys)
    cmp #$1B  ; ESC
    bne @check_ctrlx
    jmp handle_escape
@check_ctrlx:
    
    ; Control characters
    cmp #$18 ; Ctrl+X
    bne @check_find
    jmp exit_check
@check_find:
    cmp #$06 ; Ctrl+F
    bne @check_bs
    jmp handle_find
@check_bs:
    cmp #$08 ; Backspace
    bne @check_del
    jmp handle_bs
@check_del:
    cmp #$7F ; Delete
    bne @check_enter
    jmp handle_bs
@check_enter:
    cmp #$0D ; Enter
    bne @check_tab
    jmp handle_enter
@check_tab:
    cmp #$09 ; Tab
    bne @check_lf
    jmp handle_tab
@check_lf:
    cmp #$0A ; LF (ignore, we handle with CR)
    beq editor_loop  ; This is fine if editor_loop is close

    ; Check for other control characters (0x00-0x1F except those we handle)
    cmp #$20
    bcc editor_loop  ; This is fine if editor_loop is close

    ; Printable Char (0x20-0x7E)
    jsr insert_and_redraw_char
    jmp loop_continue
handle_escape:
    ; Handle escape sequences (arrow keys, etc.)
    jsr CHRIN  ; Get next character (usually '[')
    cmp #'['
    beq @is_escape
    jmp editor_loop  ; Not an arrow key sequence
@is_escape:
    
    jsr CHRIN  ; Get the arrow key code
    cmp #'A'   ; Up arrow
    bne @check_B
    jmp handle_up_arrow
@check_B:
    cmp #'B'   ; Down arrow
    bne @check_C
    jmp handle_down_arrow
@check_C:
    cmp #'C'   ; Right arrow
    bne @check_D
    jmp handle_right_arrow
@check_D:
    cmp #'D'   ; Left arrow
    bne @check_H
    jmp handle_left_arrow
@check_H:
    cmp #'H'   ; Home key
    bne @check_F
    jmp handle_home
@check_F:
    cmp #'F'   ; End key
    bne @check_3
    jmp handle_end
@check_3:
    cmp #'3'   ; Delete key
    bne @check_5
    jmp handle_del_key_entry
@check_5:
    cmp #'5'   ; Page Up
    bne @check_6
    jmp handle_pgup_entry
@check_6:
    cmp #'6'   ; Page Down
    bne @ignore_escape
    jmp handle_pgdn_entry
    
    ; If it's not an arrow key, maybe it's a function key
    ; Just ignore it
@ignore_escape:
    jmp loop_continue

handle_tab:
    ; Handle tab - store a space or multiple spaces
    ; For simplicity, store a single space
    lda #' '
    jsr insert_and_redraw_char
    jmp loop_continue

handle_del_key_entry:
    jsr CHRIN ; Consume '~'
    jmp handle_del_char

handle_pgup_entry:
    jsr CHRIN ; Consume '~'
    jmp handle_pgup

handle_pgdn_entry:
    jsr CHRIN ; Consume '~'
    jmp handle_pgdn

handle_left_arrow:
    ; Check if we are at the start of the buffer
    lda t_str_ptr1
    cmp #<text_buffer_fixed
    bne @do_left
    lda t_str_ptr1+1
    cmp #>text_buffer_fixed
    bne @do_left
    jmp loop_continue ; At start, do nothing

@do_left:
    ; Decrement pointer
    lda t_str_ptr1
    bne @dec_ptr_lo
    dec t_str_ptr1+1
@dec_ptr_lo:
    dec t_str_ptr1
    lda #<ansi_left
    ldy #>ansi_left
    jsr print_str_ay
    jmp loop_continue

handle_right_arrow:
    ; Check if we are at the end of the text (pointing to null)
    ldy #0
    lda (t_str_ptr1), y
    bne @do_right
    jmp loop_continue ; At end, do nothing

@do_right:
    ; Increment pointer
    inc t_str_ptr1
    bne @no_inc_ptr_hi
    inc t_str_ptr1+1
@no_inc_ptr_hi:
    lda #<ansi_right
    ldy #>ansi_right
    jsr print_str_ay
    jmp loop_continue

handle_home:
    jsr move_to_bol
    ; Visual update: Carriage Return moves cursor to start of line
    lda #$0D
    jsr OUTCH
    jmp loop_continue

handle_end:
    ; Initialize temp pointer with current position
    lda t_str_ptr1
    sta t_ptr_temp
    lda t_str_ptr1+1
    sta t_ptr_temp+1

@scan_loop:
    ; Check char at temp pointer
    ldy #0
    lda (t_ptr_temp), y
    beq @found_end      ; Null terminator (EOF)
    cmp #$0A            ; LF
    beq @found_end
    cmp #$0D            ; CR
    beq @found_end
    
    ; Print char to move cursor visually
    jsr OUTCH
    
    ; Increment temp pointer
    inc t_ptr_temp
    bne @no_inc_hi
    inc t_ptr_temp+1
@no_inc_hi:
    jmp @scan_loop

@found_end:
    ; Update t_str_ptr1 to new position
    lda t_ptr_temp
    sta t_str_ptr1
    lda t_ptr_temp+1
    sta t_str_ptr1+1
    jmp loop_continue

; ---------------------------------------------------------------------------
; Page Up / Down Logic
; ---------------------------------------------------------------------------
handle_pgup:
    jsr move_to_bol ; Start of current line
    ldx #16         ; Move up 16 lines
@loop:
    ; Check if at start of buffer
    lda t_str_ptr1
    cmp #<text_buffer_fixed
    bne @go_prev
    lda t_str_ptr1+1
    cmp #>text_buffer_fixed
    beq @done
@go_prev:
    ; Move back one char (into previous line)
    lda t_str_ptr1
    bne @dec
    dec t_str_ptr1+1
@dec:
    dec t_str_ptr1
    
    jsr move_to_bol
    dex
    bne @loop
@done:
    jsr redraw_screen
    jmp loop_continue

handle_pgdn:
    ldx #16         ; Move down 16 lines
@line_loop:
    ; Scan current line until newline or EOF
@char_loop:
    ldy #0
    lda (t_str_ptr1), y
    beq @done ; EOF
    cmp #$0A
    beq @found_nl
    cmp #$0D
    beq @found_nl
    
    inc t_str_ptr1
    bne @char_loop
    inc t_str_ptr1+1
    jmp @char_loop

@found_nl:
    ; Skip the newline char to start of next line
    inc t_str_ptr1
    bne @check_count
    inc t_str_ptr1+1
@check_count:
    dex
    bne @line_loop

@done:
    jsr redraw_screen
    jmp loop_continue

; ---------------------------------------------------------------------------
; Up / Down Arrow Logic
; ---------------------------------------------------------------------------
handle_up_arrow:
    jsr get_current_column ; Returns col in t_arg_ptr
    jsr move_to_bol        ; Go to start of current line
    
    ; Check if at start of buffer
    lda t_str_ptr1
    cmp #<text_buffer_fixed
    bne @go_up
    lda t_str_ptr1+1
    cmp #>text_buffer_fixed
    beq @done ; At start, can't go up
    
@go_up:
    ; Move back one char to get into previous line
    jsr dec_str_ptr1
    
    jsr move_to_bol ; Go to start of previous line
    jsr apply_column ; Advance by t_arg_ptr
    
    lda #<ansi_up
    ldy #>ansi_up
    jsr print_str_ay
@done:
    jmp loop_continue

handle_down_arrow:
    jsr get_current_column
    jsr move_to_eol ; Go to end of current line (points to CR or LF or EOF)
    
    ; Check if at EOF
    ldy #0
    lda (t_str_ptr1), y
    beq @done ; EOF
    
    ; Skip CR/LF to get to start of next line
    cmp #$0D
    bne @check_lf
    jsr inc_str_ptr1
    ldy #0
    lda (t_str_ptr1), y
    cmp #$0A
    bne @check_done ; Just CR?
    jsr inc_str_ptr1
    jmp @next_line
@check_lf:
    cmp #$0A
    bne @next_line ; Should be at next line if not CR/LF
    jsr inc_str_ptr1

@next_line:
    ; Check if we hit EOF immediately (empty last line?)
    ldy #0
    lda (t_str_ptr1), y
    beq @done
    
    jsr apply_column
    
    lda #<ansi_down
    ldy #>ansi_down
    jsr print_str_ay
@check_done:
@done:
    jmp loop_continue

; --- Navigation Helpers ---

get_current_column:
    ; Save current pos to t_str_ptr2
    lda t_str_ptr1
    sta t_str_ptr2
    lda t_str_ptr1+1
    sta t_str_ptr2+1
    
    jsr move_to_bol ; t_str_ptr1 is now at BOL
    
    ; Calculate diff (t_str_ptr2 - t_str_ptr1) -> t_arg_ptr
    sec
    lda t_str_ptr2
    sbc t_str_ptr1
    sta t_arg_ptr
    lda t_str_ptr2+1
    sbc t_str_ptr1+1
    sta t_arg_ptr+1
    
    ; Restore current pos
    lda t_str_ptr2
    sta t_str_ptr1
    lda t_str_ptr2+1
    sta t_str_ptr1+1
    rts

apply_column:
    ; Advance t_str_ptr1 by t_arg_ptr, stopping at EOL
@loop:
    lda t_arg_ptr
    ora t_arg_ptr+1
    beq @done
    
    ; Check char at current pos
    ldy #0
    lda (t_str_ptr1), y
    beq @done ; EOF
    cmp #$0D
    beq @done
    cmp #$0A
    beq @done
    
    jsr inc_str_ptr1
    
    ; Dec counter
    lda t_arg_ptr
    bne @dec_lo
    dec t_arg_ptr+1
@dec_lo:
    dec t_arg_ptr
    jmp @loop
@done:
    rts

move_to_eol:
    ldy #0
@loop:
    lda (t_str_ptr1), y
    beq @done
    cmp #$0D
    beq @done
    cmp #$0A
    beq @done
    
    jsr inc_str_ptr1
    jmp @loop
@done:
    rts

dec_str_ptr1:
    lda t_str_ptr1
    bne @skip
    dec t_str_ptr1+1
@skip:
    dec t_str_ptr1
    rts

inc_str_ptr1:
    inc t_str_ptr1
    bne @skip
    inc t_str_ptr1+1
@skip:
    rts

inc_str_ptr2:
    inc t_str_ptr2
    bne @skip
    inc t_str_ptr2+1
@skip:
    rts

; Helper: Move t_str_ptr1 to beginning of current line
move_to_bol:
    lda t_str_ptr1
    sta t_ptr_temp
    lda t_str_ptr1+1
    sta t_ptr_temp+1
@scan:
    lda t_ptr_temp
    cmp #<text_buffer_fixed
    bne @check
    lda t_ptr_temp+1
    cmp #>text_buffer_fixed
    beq @at_start
@check:
    ; Back up one
    lda t_ptr_temp
    bne @dec
    dec t_ptr_temp+1
@dec:
    dec t_ptr_temp
    
    ldy #0
    lda (t_ptr_temp), y
    cmp #$0A
    beq @found_nl
    cmp #$0D
    beq @found_nl
    jmp @scan
@found_nl:
    ; Forward one to get to start of line
    inc t_ptr_temp
    bne @at_start
    inc t_ptr_temp+1
@at_start:
    lda t_ptr_temp
    sta t_str_ptr1
    lda t_ptr_temp+1
    sta t_str_ptr1+1
    rts

handle_bs:
    ; Non-destructive backspace: move cursor left, then delete char under it.
    ; First, check if we are at the start of the buffer.
    lda t_str_ptr1
    cmp #<text_buffer_fixed
    bne @proceed
    lda t_str_ptr1+1
    cmp #>text_buffer_fixed
    beq @done ; At start, do nothing

@proceed:
    jsr dec_str_ptr1
    lda #<ansi_left
    ldy #>ansi_left
    jsr print_str_ay
    
    jmp handle_del_char ; handle_del_char does a full redraw, which is fine.
@done:
    jmp loop_continue

;---------------------------------------------------------------------------
; handle_del_char: Deletes the character at the current cursor position
; by shifting the remainder of the text buffer one byte to the left.
;---------------------------------------------------------------------------
handle_del_char:
    ; 1. Check if we are at the end of the text (cursor is on the null terminator).
    ;    If so, there is nothing to delete.
    ldy #0
    lda (t_str_ptr1), y
    beq @del_done ; Nothing to delete, just return to loop

    ; 2. Shift buffer contents left by one, starting from the cursor position.
    ;    DST = t_ptr_temp (set to current cursor position)
    ;    SRC = t_str_ptr2 (set to one position after cursor)
    lda t_str_ptr1
    sta t_ptr_temp
    sta t_str_ptr2
    lda t_str_ptr1+1
    sta t_ptr_temp+1
    sta t_str_ptr2+1
    inc t_str_ptr2
    bne @no_inc_hi
    inc t_str_ptr2+1
@no_inc_hi:

@shift_loop:
    ldy #0
    lda (t_str_ptr2), y ; Load char from source
    sta (t_ptr_temp), y ; Store it at destination

    ; If we just moved the null terminator, the shift is complete.
    beq @shift_done

    ; Increment pointers and continue shifting.
    inc t_ptr_temp
    bne @no_inc_dst
    inc t_ptr_temp+1
@no_inc_dst:
    inc t_str_ptr2
    bne @no_inc_src
    inc t_str_ptr2+1
@no_inc_src:
    jmp @shift_loop

@shift_done:
    jsr redraw_screen
@del_done:
    jmp loop_continue

handle_enter:
    lda #$0A             ; Line Feed
    jsr insert_char_mem  ; Insert LF into the memory buffer
    
    ; For newlines, a full redraw is necessary because all subsequent
    ; lines on the screen are shifted down.
    jsr redraw_screen
    
    jmp loop_continue

; ---------------------------------------------------------------------------
; handle_find: Search for text
; ---------------------------------------------------------------------------
handle_find:
    ; 1. Prompt for search string
    jsr CRLF
    lda #<search_prompt
    ldy #>search_prompt
    jsr print_str_ay
    
    ; 2. Read input
    ldy #0
@read_search:
    jsr CHRIN
    cmp #$0D ; Enter
    beq @search_start
    cmp #$1B ; ESC - Cancel
    beq @cancel_search
    cmp #$08 ; Backspace
    beq @search_bs
    cmp #$7F ; Delete
    beq @search_bs
    cmp #$20
    bcc @read_search
    
    sta search_buf, y
    jsr OUTCH
    iny
    cpy #63
    bcc @read_search
    jmp @read_search
    
@search_bs:
    cpy #0
    beq @read_search
    dey
    lda #$08
    jsr OUTCH
    lda #' '
    jsr OUTCH
    lda #$08
    jsr OUTCH
    jmp @read_search

@cancel_search:
    jsr redraw_screen
    jmp loop_continue

@search_start:
    lda #0
    sta search_buf, y ; Null terminate
    sta search_len    ; Use search_len as wrap flag (0=no wrap yet)
    
    ; 3. Search loop
    ; Start from current cursor (t_str_ptr1)
    ; Use t_str_ptr2 for scanning
    lda t_str_ptr1
    sta t_str_ptr2
    lda t_str_ptr1+1
    sta t_str_ptr2+1
    
@scan_loop:
    ; Check for end of buffer
    ldy #0
    lda (t_str_ptr2), y
    beq @check_wrap
    
    ; Compare with search_buf
    jsr check_match
    bcc @found_match ; Carry clear = match found
    
    ; Advance ptr2
    jsr inc_str_ptr2
    jmp @scan_loop

@found_match:
    ; Move cursor to found location
    lda t_str_ptr2
    sta t_str_ptr1
    lda t_str_ptr2+1
    sta t_str_ptr1+1
    jsr redraw_screen
    jmp loop_continue

@check_wrap:
    lda search_len
    bne @not_found      ; Already wrapped? Then truly not found.
    
    ; Wrap to start of buffer
    inc search_len      ; Set wrap flag
    lda #<text_buffer_fixed
    sta t_str_ptr2
    lda #>text_buffer_fixed
    sta t_str_ptr2+1
    jmp @scan_loop

@not_found:
    jsr CRLF
    lda #<not_found_msg
    ldy #>not_found_msg
    jsr print_str_ay
    jsr CRLF
    
    ; Wait for key
    jsr CHRIN
    jsr redraw_screen
    jmp loop_continue

; Helper: Check if string at t_str_ptr2 matches search_buf
; Returns: Carry Clear if match, Carry Set if no match
check_match:
    tya
    pha ; Save Y
    
    ldy #0
@cmp_loop:
    lda search_buf, y
    beq @match_ok ; End of search string = Match
    
    ; Get char from buffer (ptr2 + Y)
    ; We can't use (zp),y easily if Y is large, but search_buf is small (<64)
    ; However, t_str_ptr2 is the base.
    lda (t_str_ptr2), y
    cmp search_buf, y
    bne @no_match_cmp
    
    iny
    jmp @cmp_loop

@match_ok:
    pla
    tay
    clc
    rts
@no_match_cmp:
    pla
    tay
    sec
    rts

loop_continue:
    jsr update_status_bar
    jmp editor_loop

; ---------------------------------------------------------------------------
; insert_and_redraw_char: Inserts char in A and redraws the current line
; ---------------------------------------------------------------------------
insert_and_redraw_char:
    jsr insert_char_mem ; Inserts char from A and advances t_str_ptr1
    
    ; After insertion, the internal pointer is one position ahead of the
    ; visual cursor. We need to back it up to redraw from the right spot.
    jsr dec_str_ptr1
    
    ; Redraw the line from the current cursor position
    jsr redraw_line_from_cursor
    
    ; Now, advance the internal pointer and the visual cursor to match.
    jsr inc_str_ptr1
    lda #<ansi_right
    ldy #>ansi_right
    jsr print_str_ay
    rts

; ---------------------------------------------------------------------------
; insert_char_mem: Shifts buffer and inserts character in A
; ---------------------------------------------------------------------------
insert_char_mem:
    pha ; Save char to insert (from A)
    
    ; 1. Find end of buffer (null terminator)
    lda #<text_buffer_fixed
    sta t_ptr_temp ; Use t_ptr_temp to scan
    lda #>text_buffer_fixed
    sta t_ptr_temp+1
@find_end:
    ldy #0
    lda (t_ptr_temp), y
    beq @found_end
    inc t_ptr_temp
    bne @find_end
    inc t_ptr_temp+1
    jmp @find_end
@found_end:
    ; t_ptr_temp now points to the null terminator.
    
    ; 2. Shift buffer contents right by one, starting from the end.
@shift_loop:
    ; Check if our destination pointer (t_ptr_temp) has reached the cursor.
    lda t_ptr_temp
    cmp t_str_ptr1
    bne @do_shift
    lda t_ptr_temp+1
    cmp t_str_ptr1+1
    beq @shift_done

@do_shift:
    ; Get char from t_ptr_temp-1 and store it at t_ptr_temp
    ; First, back up t_ptr_temp
    lda t_ptr_temp
    bne @dec_lo
    dec t_ptr_temp+1
@dec_lo:
    dec t_ptr_temp
    
    ; Now copy
    ldy #0
    lda (t_ptr_temp), y
    iny
    sta (t_ptr_temp), y
    
    ; Go back to start of loop to check position again
    jmp @shift_loop

@shift_done:
    ; 3. Store new character at cursor position
    pla
    ldy #0
    sta (t_str_ptr1), y
    
    ; 4. Increment cursor
    inc t_str_ptr1
    bne @ret
    inc t_str_ptr1+1
    
@ret:
    rts

; ---------------------------------------------------------------------------
; redraw_line_from_cursor: Redraws the current line without a full redraw
; ---------------------------------------------------------------------------
redraw_line_from_cursor:
    ; Assumes visual cursor is already at the correct position.
    ; Saves cursor, clears to EOL, prints rest of line, restores cursor.
    lda #<ansi_save
    ldy #>ansi_save
    jsr print_str_ay

    lda #<ansi_clear_line
    ldy #>ansi_clear_line
    jsr print_str_ay

    ; Use t_str_ptr2 as a temporary printing pointer
    lda t_str_ptr1
    sta t_str_ptr2
    lda t_str_ptr1+1
    sta t_str_ptr2+1

@print_loop:
    ldy #0
    lda (t_str_ptr2), y
    beq @done_print ; End of buffer
    cmp #$0A
    beq @done_print ; End of line
    
    jsr OUTCH
    jsr inc_str_ptr2
    jmp @print_loop

@done_print:
    lda #<ansi_restore
    ldy #>ansi_restore
    jsr print_str_ay
    rts

exit_check:
    ; Move to a safe line (23) at bottom of screen for prompt
    lda #<ansi_line23
    ldy #>ansi_line23
    jsr print_str_ay

    ; Clear the line to prevent artifacts
    lda #<ansi_clear_line
    ldy #>ansi_clear_line
    jsr print_str_ay

    lda #<save_prompt
    ldy #>save_prompt
    jsr print_str_ay
    
@ask_loop:
    jsr CHRIN
    and #$DF ; To Upper
    cmp #'N'
    beq exit_editor
    cmp #'Y'
    beq save_sequence
    cmp #$0D ; Enter (default to No)
    beq exit_editor
    jmp @ask_loop

save_sequence:
    ; Check if filename exists
    lda filename_buf
    bne @has_filename
    
    ; Ask for filename
    jsr CRLF
    lda #<filename_prompt
    ldy #>filename_prompt
    jsr print_str_ay
    
    ; Read filename
    ldy #0
@read_fname:
    jsr CHRIN
    cmp #$0D
    beq @fname_read_done
    cmp #$08  ; Backspace during filename entry
    beq @fname_bs
    cmp #$7F  ; Delete
    beq @fname_bs
    cmp #$20
    bcc @read_fname  ; Ignore other controls
    sta filename_buf, y
    jsr OUTCH  ; Echo
    iny
    cpy #126
    bcc @read_fname
    jmp @read_fname  ; Buffer full, just read and discard
    
@fname_bs:
    ; Handle backspace in filename entry
    cpy #0
    beq @read_fname  ; At start, ignore
    dey
    lda #$08
    jsr OUTCH
    lda #' '
    jsr OUTCH
    lda #$08
    jsr OUTCH
    jmp @read_fname
    
@fname_read_done:
    lda #0
    sta filename_buf, y
    jsr CRLF
    
    ; Check if empty
    lda filename_buf
    beq exit_editor

@has_filename:
    jsr perform_save
    ; Fall through to exit_editor
    
exit_editor:
    pla          ; Get Y
    tay
    pla          ; Get X
    tax
    pla          ; Get A
    plp          ; Get processor status
    clc
    rts

; ---------------------------------------------------------------------------
; Parse filename from command line
; ---------------------------------------------------------------------------
parse_filename:
    ldx #0
    ldy #0
    
@skip_spaces:
    lda INPUT_BUFFER, x
    beq @no_args
    cmp #' '
    bne @check_run
    inx
    bne @skip_spaces

@check_run:
    lda INPUT_BUFFER, x
    beq @no_args
    cmp #' '
    beq @found_space_1
    inx
    bne @check_run
    
@found_space_1:
    inx
    
@skip_path:
    lda INPUT_BUFFER, x
    beq @no_args
    cmp #' '
    beq @found_space_2
    inx
    bne @skip_path
    
@found_space_2:
    inx
    
@skip_filename_spaces:
    lda INPUT_BUFFER, x
    beq @no_args
    cmp #' '
    bne @copy_arg
    inx
    bne @skip_filename_spaces

@copy_arg:
    lda INPUT_BUFFER, x
    beq @arg_done
    cmp #' '
    beq @arg_done
    sta filename_buf, y
    inx
    iny
    cpy #126
    bcc @copy_arg
    
@arg_done:
    lda #0
    sta filename_buf, y
    rts

@no_args:
    lda #0
    sta filename_buf
    rts

; ---------------------------------------------------------------------------
; Initialize UI
; ---------------------------------------------------------------------------
init_ui:
    lda #<ansi_cls
    ldy #>ansi_cls
    jsr print_str_ay
    
    lda #<header_msg
    ldy #>header_msg
    jsr print_str_ay
    
    ; Print footer right after header
    jsr CRLF
    lda #<footer_msg
    ldy #>footer_msg
    jsr print_str_ay
    jsr CRLF
    
    lda filename_buf
    bne @has_filename
    
    lda #<no_file_msg
    ldy #>no_file_msg
    jsr print_str_ay
    jmp @continue
    
@has_filename:
    lda #<filename_buf
    ldy #>filename_buf
    jsr print_str_ay
    
@continue:
    jsr CRLF
    
    lda #<separator_msg
    ldy #>separator_msg
    jsr print_str_ay
    jsr CRLF
    rts

; ---------------------------------------------------------------------------
; Perform save operation
; ---------------------------------------------------------------------------
perform_save:
    ; Save current VIA state
    lda VIA_DDRA
    pha
    
    ; 1. Calculate Length by scanning for null terminator
    lda #<text_buffer_fixed
    sta t_str_ptr2
    lda #>text_buffer_fixed
    sta t_str_ptr2+1
    
    lda #0
    sta file_length_lo
    sta file_length_hi
    
@calc_len_loop:
    ldy #0
    lda (t_str_ptr2), y
    beq @len_done
    
    inc file_length_lo
    bne @no_inc_len_hi
    inc file_length_hi
@no_inc_len_hi:
    
    inc t_str_ptr2
    bne @calc_len_loop
    inc t_str_ptr2+1
    jmp @calc_len_loop
    
@len_done:
    ; 2. Construct Path in ARG_BUFF
    lda filename_buf
    cmp #'/'
    beq @abs_path
    
    ; Relative path
    ldx #0
    ldy #0
    
    lda cwd_ptr
    sta t_str_ptr2
    lda cwd_ptr+1
    sta t_str_ptr2+1
    
@copy_cwd:
    lda (t_str_ptr2), y
    beq @cwd_done
    sta ARG_BUFF, x
    inx
    iny
    cpx #240
    bcc @copy_cwd
    
@cwd_done:
    cpx #0
    beq @append_filename
    lda #'/'
    sta ARG_BUFF, x
    inx
    
@append_filename:
    ldy #0
@copy_fname:
    lda filename_buf, y
    beq @path_done
    sta ARG_BUFF, x
    inx
    iny
    cpx #250
    bcc @copy_fname
    jmp @path_done
    
@abs_path:
    ldx #0
    ldy #0
@copy_abs:
    lda filename_buf, y
    beq @path_done
    sta ARG_BUFF, x
    inx
    iny
    cpx #250
    bcc @copy_abs

@path_done:
    lda #0
    sta ARG_BUFF, x
    inx
    
    ; Append Length
    lda file_length_lo
    sta ARG_BUFF, x
    inx
    lda file_length_hi
    sta ARG_BUFF, x
    inx
    
    stx ARG_LEN
    
    ; 3. Send Command
    lda #<msg_saving
    ldy #>msg_saving
    jsr print_str_ay
    jsr CRLF
    
    lda #CMD_FS_SAVEMEM
    sta CMD_ID
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @start_stream
    
    lda #<msg_err
    ldy #>msg_err
    jsr print_str_ay
    jsr CRLF
    pla
    sta VIA_DDRA
    rts

@start_stream:
    ; 4. Stream Data
    lda #<stream_start_msg
    ldy #>stream_start_msg
    jsr print_str_ay
    
    ; Use FIXED buffer address
    lda #<text_buffer_fixed
    sta t_str_ptr2
    lda #>text_buffer_fixed
    sta t_str_ptr2+1
    
    ; Set VIA to Output
    lda #$FF
    sta VIA_DDRA
    
    ; Set up counters
    lda file_length_lo
    sta bytes_remaining_lo
    lda file_length_hi
    sta bytes_remaining_hi
    
    ; Check if empty
    lda bytes_remaining_lo
    ora bytes_remaining_hi
    beq @stream_done
    
    lda #'['
    jsr OUTCH
    
@stream_loop:
    ldy #0
    lda (t_str_ptr2), y
    jsr send_byte
    
    inc t_str_ptr2
    bne @no_inc_ptr
    inc t_str_ptr2+1
@no_inc_ptr:
    
    lda bytes_remaining_lo
    bne @dec_lo
    dec bytes_remaining_hi
@dec_lo:
    dec bytes_remaining_lo
    
    lda bytes_remaining_lo
    ora bytes_remaining_hi
    beq @stream_done
    
    lda bytes_remaining_lo
    cmp #$FF
    bne @stream_loop
    
    lda #'.'
    jsr OUTCH
    jmp @stream_loop

@stream_done:
    lda #']'
    jsr OUTCH
    jsr CRLF
    
    ; 5. Read Status
    lda #$00
    sta VIA_DDRA
    
    ; Read status, discard length bytes, then check status
    jsr read_byte      ; Read status byte
    sta LAST_STATUS    ; Store it safely
    jsr read_byte      ; Read and discard len_lo
    jsr read_byte      ; Read and discard len_hi
    
    lda LAST_STATUS
    cmp #STATUS_OK
    bne @final_err
    
    lda #<msg_done
    ldy #>msg_done
    jsr print_str_ay
    jsr CRLF
    
    pla
    sta VIA_DDRA
    rts

@final_err:
    lda #<msg_err
    ldy #>msg_err
    jsr print_str_ay
    jsr CRLF
    pla
    sta VIA_DDRA
    rts

; ---------------------------------------------------------------------------
; Redraw Screen - Clears and reprints the entire UI and text buffer
; ---------------------------------------------------------------------------
redraw_screen:
    ; 1. Clear screen and reset cursor to home
    lda #<ansi_cls
    ldy #>ansi_cls
    jsr print_str_ay

    ; 2. Redraw UI header
    lda #<header_msg
    ldy #>header_msg
    jsr print_str_ay
    
    ; Print footer right after header
    jsr CRLF
    lda #<footer_msg
    ldy #>footer_msg
    jsr print_str_ay
    jsr CRLF
    
    lda filename_buf
    bne @redraw_has_filename
    lda #<no_file_msg
    ldy #>no_file_msg
    jsr print_str_ay
    jmp @redraw_continue
@redraw_has_filename:
    lda #<filename_buf
    ldy #>filename_buf
    jsr print_str_ay
@redraw_continue:
    jsr CRLF
    lda #<separator_msg
    ldy #>separator_msg
    jsr print_str_ay
    jsr CRLF

    ; 3. Print the current text buffer content
    lda #<text_buffer_fixed
    sta t_ptr_temp
    lda #>text_buffer_fixed
    sta t_ptr_temp+1
@print_loop:
    ; Check if we are at the cursor position
    lda t_ptr_temp
    cmp t_str_ptr1
    bne @check_char
    lda t_ptr_temp+1
    cmp t_str_ptr1+1
    bne @check_char

    ; Save cursor position
    lda #<ansi_save
    ldy #>ansi_save
    jsr print_str_ay

@check_char:
    ldy #0
    lda (t_ptr_temp), y
    beq @print_done
    jsr OUTCH
    inc t_ptr_temp
    bne @print_loop
    inc t_ptr_temp+1
    jmp @print_loop

@print_done:
    ; Check if cursor is at the very end (null terminator)
    lda t_ptr_temp
    cmp t_str_ptr1
    bne @draw_footer
    lda t_ptr_temp+1
    cmp t_str_ptr1+1
    bne @draw_footer
    
    ; Save cursor position (at end of file)
    lda #<ansi_save
    ldy #>ansi_save
    jsr print_str_ay

@draw_footer:
    ; Restore cursor position
    lda #<ansi_restore
    ldy #>ansi_restore
    jsr print_str_ay
    jsr update_status_bar
    rts
; ---------------------------------------------------------------------------
; Helper: Print String
; ---------------------------------------------------------------------------
print_str_ay:
    sta t_str_ptr2
    sty t_str_ptr2+1
    ldy #0
@loop:
    lda (t_str_ptr2), y
    beq @done
    jsr OUTCH
    iny
    jmp @loop
@done:
    rts

; ---------------------------------------------------------------------------
; Update Status Bar (Line 2) with Line/Col
; ---------------------------------------------------------------------------
update_status_bar:
    ; Save cursor
    lda #<ansi_save
    ldy #>ansi_save
    jsr print_str_ay
    
    ; Move to Line 2
    lda #<ansi_line2
    ldy #>ansi_line2
    jsr print_str_ay
    
    ; Print Footer Msg
    lda #<footer_msg
    ldy #>footer_msg
    jsr print_str_ay
    
    ; Move to Col 50
    lda #<ansi_col50
    ldy #>ansi_col50
    jsr print_str_ay
    
    ; Clear rest of line
    lda #<ansi_clear_line
    ldy #>ansi_clear_line
    jsr print_str_ay
    
    ; Calc and Print Line/Col
    jsr calc_line_col
    
    lda #<msg_line
    ldy #>msg_line
    jsr print_str_ay
    
    lda current_line
    jsr print_dec_8
    
    lda #<msg_col
    ldy #>msg_col
    jsr print_str_ay
    
    lda current_col
    jsr print_dec_8
    
    ; Restore cursor
    lda #<ansi_restore
    ldy #>ansi_restore
    jsr print_str_ay
    rts

calc_line_col:
    lda #1
    sta current_line
    sta current_col
    
    lda #<text_buffer_fixed
    sta t_ptr_temp
    lda #>text_buffer_fixed
    sta t_ptr_temp+1
    
@scan_loop:
    ; Check if we reached cursor
    lda t_ptr_temp
    cmp t_str_ptr1
    bne @check_char
    lda t_ptr_temp+1
    cmp t_str_ptr1+1
    beq @done
    
@check_char:
    ldy #0
    lda (t_ptr_temp), y
    cmp #$0A ; LF
    bne @not_lf
    inc current_line
    lda #1
    sta current_col
    jmp @next
@not_lf:
    inc current_col
@next:
    inc t_ptr_temp
    bne @scan_loop
    inc t_ptr_temp+1
    jmp @scan_loop
@done:
    rts

print_dec_8:
    ; Print A as decimal (0-255)
    ; Uses t_arg_ptr ($58) as temp to avoid stack usage completely
    sta t_arg_ptr
    
    ldy #0 ; Hundreds flag
    ldx #0 ; Hundreds counter
@div100:
    lda t_arg_ptr
    cmp #100
    bcc @print_100
    sbc #100
    sta t_arg_ptr
    inx
    jmp @div100
@print_100:
    cpx #0
    beq @skip_100
    txa
    ora #'0'
    jsr OUTCH
    ldy #1
@skip_100:
    
    ldx #0 ; Tens counter
@div10:
    lda t_arg_ptr
    cmp #10
    bcc @print_10
    sbc #10
    sta t_arg_ptr
    inx
    jmp @div10
@print_10:
    ; Check if we should print tens
    cpy #1 ; Did we print hundreds?
    beq @do_print_10
    cpx #0 ; Is tens > 0?
    bne @do_print_10
    jmp @print_1
@do_print_10:
    txa
    ora #'0'
    jsr OUTCH
    
@print_1:
    lda t_arg_ptr
    ora #'0'
    jsr OUTCH
    rts

; ---------------------------------------------------------------------------
; Local System Call Implementations
; ---------------------------------------------------------------------------
CHRIN:
    lda ACIA_DATA
    beq @no_key
    sec
    rts
@no_key:
    clc
    rts

CRLF:
    lda #$0D
    jsr OUTCH
    lda #$0A
    jmp OUTCH

; ---------------------------------------------------------------------------
; RODATA
; ---------------------------------------------------------------------------
.segment "RODATA"

ansi_cls:        .byte $1B, "[2J", $1B, "[H", 0
ansi_line23:     .byte $1B, "[23;1H", 0
ansi_line2:      .byte $1B, "[2;1H", 0
ansi_col50:      .byte $1B, "[50G", 0
ansi_clear_line: .byte $1B, "[K", 0
ansi_left:       .byte $1B, "[D", 0
ansi_right:      .byte $1B, "[C", 0
ansi_up:         .byte $1B, "[A", 0
ansi_down:       .byte $1B, "[B", 0
ansi_save:       .byte $1B, "[s", 0
ansi_restore:    .byte $1B, "[u", 0
header_msg:      .asciiz "WRITE - Nano-like Editor "
no_file_msg:     .asciiz "[No File]"
separator_msg:   .asciiz "--------------------------------------------------------------------------------"
footer_msg:      .asciiz "^X Exit | ^F Search | Arrow Keys | BS DEL |"
msg_line:        .asciiz " Line: "
msg_col:         .asciiz " Col: "
save_prompt:     .asciiz "Save modified buffer? (Y/N) "
filename_prompt: .asciiz "Filename: "
msg_saving:      .asciiz "Saving..."
search_prompt:   .asciiz "Search: "
not_found_msg:   .asciiz "Not Found"
msg_done:        .asciiz "Done"
msg_err:         .asciiz "Error"
stream_start_msg: .asciiz "Sending data: "

; ---------------------------------------------------------------------------
; BSS
; ---------------------------------------------------------------------------
.segment "BSS"

; Control variables
current_line:      .res 1
current_col:       .res 1
cwd_ptr:           .res 2
file_length_lo:    .res 1
file_length_hi:    .res 1
bytes_remaining_lo:.res 1
bytes_remaining_hi:.res 1
filename_buf:      .res 128
search_buf:        .res 64
search_len:        .res 1

; FIXED SIZE TEXT BUFFER
text_buffer_fixed: .res 4096  ; 4KB fixed buffer
