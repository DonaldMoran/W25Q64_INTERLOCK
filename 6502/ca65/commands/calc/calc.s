; calc.s - Retro calculator transient command
; Location: 6502/ca65/commands/calc/calc.s

; ---------------------------------------------------------------------------
; External symbols
; ---------------------------------------------------------------------------
.import pico_send_request
.import CMD_ID, ARG_LEN, LAST_STATUS

; ---------------------------------------------------------------------------
; System calls
; ---------------------------------------------------------------------------
OUTCH = $FFEF    ; Print character in A
ACIA_DATA = $5000

; ---------------------------------------------------------------------------
; Zero page (USE ONLY $58-$5F)
; ---------------------------------------------------------------------------
t_str_ptr1   = $5A  ; 2 bytes - String pointer 1
t_str_ptr2   = $5C  ; 2 bytes - Temporary pointer
t_ptr_temp   = $5E  ; 2 bytes - Temporary pointer

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
CMD_CALC        = $20   ; Example command ID (adjust as needed)
CR              = $0D
LF              = $0A

; ---------------------------------------------------------------------------
; HEADER - MUST be first
; ---------------------------------------------------------------------------
.segment "HEADER"
    .word start        ; Entry point at $0800

; ---------------------------------------------------------------------------
; BSS - Uninitialized data
; ---------------------------------------------------------------------------
.segment "BSS"
INPUT_BUFFER:  .res 128  ; Input buffer for hex/dec/str strings

; Moved from Zero Page to BSS to comply with $58-$5F limit
temp1:         .res 2
temp2:         .res 2
; input_ptr was unused

dec_value_lo:           .res 1
dec_value_hi:           .res 1
dec_temp_ten_thousands: .res 1
dec_temp_thousands:     .res 1
dec_temp_hundreds:      .res 1
dec_temp_tens_ones:     .res 1

math_operator: .res 1
math_num1_lo:  .res 1
math_num1_hi:  .res 1
math_num2_lo:  .res 1
math_num2_hi:  .res 1

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

    ; Sanitize CPU state
    cld
    sei

main_loop:
    ; Display the full menu
    jsr display_menu

    ; Get user input (waits for valid key)
    jsr get_menu_choice

    ; Process the choice
    cmp #'1'
    bne @check2
    jmp hex_to_bin      ; Use JMP instead of BEQ for long jumps
@check2:
    cmp #'2'
    bne @check3
    jmp bin_to_hex
@check3:
    cmp #'3'
    bne @check4
    jmp hex_to_dec
@check4:
    cmp #'4'
    bne @check5
    jmp dec_to_hex
@check5:
    cmp #'5'
    bne @check6
    jmp addr_range
@check6:
    cmp #'6'
    bne @check7
    jmp math_eval
@check7:
    cmp #'7'
    bne invalid_choice
    jmp quit

invalid_choice:    
    ; Invalid choice
    lda #<msg_invalid_choice
    sta t_str_ptr1
    lda #>msg_invalid_choice
    sta t_str_ptr1+1
    jsr print_string
    jsr print_crlf
   
    jmp main_loop

; ---------------------------------------------------------------------------
; Hex to Binary conversion
; ---------------------------------------------------------------------------
hex_to_bin:
    ; Get hex input from user
    lda #<prompt_hex_input
    sta t_str_ptr1
    lda #>prompt_hex_input
    sta t_str_ptr1+1
    jsr print_string

    jsr get_hex_input       ; Get input, store in INPUT_BUFFER
    bcc @process
    jmp hex_to_bin_error

@process:
    ; Convert hex string to number in temp1
    jsr hex_string_to_decimal
    bcs hex_to_bin_error

    ; Print "Hex XX = Binary YY"
    lda #<msg_hex_binary_result_prefix
    sta t_str_ptr1
    lda #>msg_hex_binary_result_prefix
    sta t_str_ptr1+1
    jsr print_string

    ; Print original hex input (INPUT_BUFFER)
    lda #<INPUT_BUFFER
    sta t_str_ptr1
    lda #>INPUT_BUFFER
    sta t_str_ptr1+1
    jsr print_string

    lda #<msg_hex_binary_result_infix
    sta t_str_ptr1
    lda #>msg_hex_binary_result_infix
    sta t_str_ptr1+1
    jsr print_string

    ; Print binary result
    jsr print_binary_16

    jsr print_crlf
    jsr print_crlf
    
    ; Add prompt before waiting
    lda #<msg_press_any_key
    sta t_str_ptr1
    lda #>msg_press_any_key
    sta t_str_ptr1+1
    jsr print_string

    jsr wait_for_key
    jmp main_loop

hex_to_bin_error:
    lda #<msg_invalid_hex
    sta t_str_ptr1
    lda #>msg_invalid_hex
    sta t_str_ptr1+1
    jsr print_string
    jsr print_crlf
    jsr wait_for_key
    jmp main_loop

; ---------------------------------------------------------------------------
; Binary to Hex conversion
; ---------------------------------------------------------------------------
bin_to_hex:
    ; Get binary input from user
    lda #<prompt_binary_input
    sta t_str_ptr1
    lda #>prompt_binary_input
    sta t_str_ptr1+1
    jsr print_string

    jsr get_binary_input    ; Get input, store in INPUT_BUFFER
    bcc @process
    jmp bin_to_hex_error

@process:
    ; Convert binary string to number in temp1
    jsr binary_string_to_hex
    bcs bin_to_hex_error

    ; Print "Binary XX = Hex YY"
    lda #<msg_binary_hex_result_prefix
    sta t_str_ptr1
    lda #>msg_binary_hex_result_prefix
    sta t_str_ptr1+1
    jsr print_string

    ; Print original binary input (INPUT_BUFFER)
    lda #<INPUT_BUFFER
    sta t_str_ptr1
    lda #>INPUT_BUFFER
    sta t_str_ptr1+1
    jsr print_string

    lda #<msg_binary_hex_result_infix
    sta t_str_ptr1
    lda #>msg_binary_hex_result_infix
    sta t_str_ptr1+1
    jsr print_string

    ; Print hex result (from temp1)
    lda temp1+1          ; High byte
    jsr print_hex
    lda temp1            ; Low byte
    jsr print_hex

    jsr print_crlf
    jsr print_crlf
    
    ; Prompt before waiting
    lda #<msg_press_any_key
    sta t_str_ptr1
    lda #>msg_press_any_key
    sta t_str_ptr1+1
    jsr print_string

    jsr wait_for_key
    jmp main_loop

bin_to_hex_error:
    lda #<msg_invalid_binary
    sta t_str_ptr1
    lda #>msg_invalid_binary
    sta t_str_ptr1+1
    jsr print_string
    jsr print_crlf
    jsr wait_for_key
    jmp main_loop

; ---------------------------------------------------------------------------
; Hex to Decimal conversion
; ---------------------------------------------------------------------------
hex_to_dec:
    ; Get hex input from user
    lda #<prompt_hex_input
    sta t_str_ptr1
    lda #>prompt_hex_input
    sta t_str_ptr1+1
    jsr print_string

    jsr get_hex_input       ; Get input, store in INPUT_BUFFER
    bcc hex_to_dec_process  ; Carry clear means valid input

    ; Handle invalid input
    lda #<msg_invalid_hex
    sta t_str_ptr1
    lda #>msg_invalid_hex
    sta t_str_ptr1+1
    jsr print_string
    jsr print_crlf

    jsr wait_for_key

    jmp main_loop

hex_to_dec_process:
    ; Convert hex string to decimal
    jsr hex_string_to_decimal   ; Converts INPUT_BUFFER to decimal, result in temp1 (16-bit)

    ; Print "Hex XX = Decimal YY"
    lda #<msg_hex_decimal_result_prefix
    sta t_str_ptr1
    lda #>msg_hex_decimal_result_prefix
    sta t_str_ptr1+1
    jsr print_string

    ; Print original hex input (INPUT_BUFFER)
    lda #<INPUT_BUFFER
    sta t_str_ptr1
    lda #>INPUT_BUFFER
    sta t_str_ptr1+1
    jsr print_string

    lda #<msg_hex_decimal_result_infix
    sta t_str_ptr1
    lda #>msg_hex_decimal_result_infix
    sta t_str_ptr1+1
    jsr print_string

    ; Print decimal result using 16-bit routine
    jsr print_dec_16

    jsr print_crlf
    jsr print_crlf
    
    ; Add prompt before waiting
    lda #<msg_press_any_key
    sta t_str_ptr1
    lda #>msg_press_any_key
    sta t_str_ptr1+1
    jsr print_string

    jsr wait_for_key    ; Pause so user can read message

    jmp main_loop

; ---------------------------------------------------------------------------
; Decimal to Hex conversion
; ---------------------------------------------------------------------------
dec_to_hex:
    ; Get decimal input from user
    lda #<prompt_decimal_input
    sta t_str_ptr1
    lda #>prompt_decimal_input
    sta t_str_ptr1+1
    jsr print_string

    jsr get_decimal_input    ; Get input, store in INPUT_BUFFER
    bcc dec_to_hex_process   ; Carry clear means valid input

    ; Handle invalid input
    lda #<msg_invalid_decimal
    sta t_str_ptr1
    lda #>msg_invalid_decimal
    sta t_str_ptr1+1
    jsr print_string
    jsr print_crlf

    jsr wait_for_key
    jmp main_loop

dec_to_hex_process:
    ; Convert decimal string to binary in temp1
    jsr decimal_string_to_hex
    
    ; Print "Decimal XX = Hex YY"
    lda #<msg_decimal_hex_result_prefix
    sta t_str_ptr1
    lda #>msg_decimal_hex_result_prefix
    sta t_str_ptr1+1
    jsr print_string

    ; Print original decimal input (INPUT_BUFFER)
    lda #<INPUT_BUFFER
    sta t_str_ptr1
    lda #>INPUT_BUFFER
    sta t_str_ptr1+1
    jsr print_string

    lda #<msg_decimal_hex_result_infix
    sta t_str_ptr1
    lda #>msg_decimal_hex_result_infix
    sta t_str_ptr1+1
    jsr print_string

    ; Print hex result (from temp1)
    lda temp1+1          ; High byte
    jsr print_hex
    lda temp1            ; Low byte
    jsr print_hex

    jsr print_crlf
    jsr print_crlf
    
    ; Prompt before waiting
    lda #<msg_press_any_key
    sta t_str_ptr1
    lda #>msg_press_any_key
    sta t_str_ptr1+1
    jsr print_string

    jsr wait_for_key
    jmp main_loop

; ---------------------------------------------------------------------------
; Simple Math Expression Evaluation (SIMPLIFIED VERSION)
; Supports: + - * / on two 16-bit numbers
; Format: <digits><operator><digits> (no spaces)
; ---------------------------------------------------------------------------
math_eval:
    ; Prompt user
    lda #<prompt_simple_expr
    sta t_str_ptr1
    lda #>prompt_simple_expr
    sta t_str_ptr1+1
    jsr print_string
    
    ; Read the entire line into INPUT_BUFFER (simple line editor)
    ldx #0
@read_loop:
    jsr CHRIN
    bcc @read_loop
    
    cmp #CR
    beq @done_read
    
    cmp #$08            ; Backspace
    beq @backspace
    
    ; Store and echo character
    sta INPUT_BUFFER, x
    jsr OUTCH
    inx
    cpx #120
    bcc @read_loop
    
@backspace:
    cpx #0
    beq @read_loop
    dex
    lda #$08
    jsr OUTCH
    lda #$20
    jsr OUTCH
    lda #$08
    jsr OUTCH
    jmp @read_loop

@done_read:
    lda #0
    sta INPUT_BUFFER, x
    jsr print_crlf
    
    ; Initialize variables
    ldx #0
    lda #0
    sta math_num1_lo
    sta math_num1_hi
    sta math_num2_lo
    sta math_num2_hi
    sta math_operator
    
    ; Parse first number
@parse_first:
    lda INPUT_BUFFER, x
    beq @invalid_expr_branch1
    jmp @continue_parse1
@invalid_expr_branch1:
    jmp @invalid_expr
@continue_parse1:
    
@parse_first_loop:
    lda INPUT_BUFFER, x
    beq @invalid_expr_branch2
    jmp @continue_parse2
@invalid_expr_branch2:
    jmp @invalid_expr
@continue_parse2:
    
    cmp #'+'
    beq @got_operator
    cmp #'-'
    beq @got_operator
    cmp #'*'
    beq @got_operator
    cmp #'/'
    beq @got_operator
    
    ; It's a digit - convert and add to first number
    sec
    sbc #'0'            ; Convert ASCII to value
    bmi @invalid_expr_branch3
    jmp @continue_parse3
@invalid_expr_branch3:
    jmp @invalid_expr
@continue_parse3:
    
    cmp #10
    bcs @invalid_expr_branch4
    jmp @continue_parse4
@invalid_expr_branch4:
    jmp @invalid_expr
@continue_parse4:
    
    pha                 ; Save digit
    
    ; Multiply current first number by 10
    lda math_num1_lo
    sta temp1
    lda math_num1_hi
    sta temp1+1
    jsr multiply_by_10_simple
    bcs @overflow_long
    
    ; Add new digit
    pla
    clc
    adc temp1
    sta math_num1_lo
    lda temp1+1
    adc #0
    sta math_num1_hi
    bcs @overflow_long
    
    inx
    jmp @parse_first_loop

@got_operator:
    sta math_operator
    inx                 ; Move past operator
    
    ; Parse second number
    lda INPUT_BUFFER, x
    beq @invalid_expr_branch5
    jmp @continue_parse5
@invalid_expr_branch5:
    jmp @invalid_expr
@continue_parse5:
    
@parse_second_loop:
    lda INPUT_BUFFER, x
    beq @calculate       ; End of string, go calculate
    
    ; It's a digit - convert and add to second number
    sec
    sbc #'0'            ; Convert ASCII to value
    bmi @invalid_expr_branch6
    jmp @continue_parse6
@invalid_expr_branch6:
    jmp @invalid_expr
@continue_parse6:
    
    cmp #10
    bcs @invalid_expr_branch7
    jmp @continue_parse7
@invalid_expr_branch7:
    jmp @invalid_expr
@continue_parse7:
    
    pha                 ; Save digit
    
    ; Multiply current second number by 10
    lda math_num2_lo
    sta temp1
    lda math_num2_hi
    sta temp1+1
    jsr multiply_by_10_simple
    bcs @overflow_long
    
    ; Add new digit
    pla
    clc
    adc temp1
    sta math_num2_lo
    lda temp1+1
    adc #0
    sta math_num2_hi
    bcs @overflow_long
    
    inx
    jmp @parse_second_loop

@calculate_long:
    jmp @calculate

@overflow_long:
    jmp @overflow

@calculate:
    ; Perform the calculation based on operator
    lda math_operator
    cmp #'+'
    beq @add
    cmp #'-'
    beq @subtract
    cmp #'*'
    beq @multiply
    cmp #'/'
    bne @not_divide
    jmp @divide
@not_divide:
    jmp @invalid_expr

@add:
    clc
    lda math_num1_lo
    adc math_num2_lo
    sta temp1
    lda math_num1_hi
    adc math_num2_hi
    sta temp1+1
    bcc @no_overflow
    jmp @overflow       ; Jump directly to overflow handler
@no_overflow:    
    jmp @show_result

@subtract:
    sec
    lda math_num1_lo
    sbc math_num2_lo
    sta temp1
    lda math_num1_hi
    sbc math_num2_hi
    sta temp1+1
    bcs @not_negative
    jmp @negative       ; If borrow after high byte, result is negative
@not_negative:    
    jmp @show_result

@multiply:
    ; Simple multiplication by repeated addition
    lda #0
    sta temp1
    sta temp1+1
    lda math_num2_lo
    sta temp2
    lda math_num2_hi
    sta temp2+1
    
@mult_loop:
    lda temp2
    ora temp2+1
    bne @mult_continue
    jmp @show_result
@mult_continue:
    clc
    lda temp1
    adc math_num1_lo
    sta temp1
    lda temp1+1
    adc math_num1_hi
    sta temp1+1
    bcc @not_an_overflow
    jmp @overflow       ; Jump directly to overflow handler
@not_an_overflow:    
    sec
    lda temp2
    sbc #1
    sta temp2
    lda temp2+1
    sbc #0
    sta temp2+1
    jmp @mult_loop

@divide:
    ; Check for division by zero
    lda math_num2_lo
    ora math_num2_hi
    bne @not_divide_zero
    jmp @div_zero

@not_divide_zero:
    ; Simple division by repeated subtraction
    lda #0
    sta temp1          ; Initialize quotient to 0
    sta temp1+1
    
    ; Copy dividend (num1) to temp2 for subtraction
    lda math_num1_lo
    sta temp2
    lda math_num1_hi
    sta temp2+1
    
@div_loop:
    ; Compare temp2 (remainder) with divisor
    ; We want to check if temp2 >= divisor
    
    ; First compare high bytes
    lda temp2+1
    cmp math_num2_hi
    bcc @show_result     ; If high byte less, we're done (temp2 < divisor)
    bne @do_subtract     ; If high byte greater, definitely subtract
    
    ; High bytes equal, compare low bytes
    lda temp2
    cmp math_num2_lo
    bcc @show_result     ; If low byte less, we're done (temp2 < divisor)
    ; If low byte greater or equal, fall through to subtract
    
@do_subtract:
    ; Subtract divisor from temp2
    sec
    lda temp2
    sbc math_num2_lo
    sta temp2
    lda temp2+1
    sbc math_num2_hi
    sta temp2+1
    
    ; Increment quotient
    inc temp1
    bne @div_loop
    inc temp1+1
    jmp @div_loop

@show_result:
    ; Print the result
    lda #<msg_result_prefix
    sta t_str_ptr1
    lda #>msg_result_prefix
    sta t_str_ptr1+1
    jsr print_string
    
    lda #<INPUT_BUFFER
    sta t_str_ptr1
    lda #>INPUT_BUFFER
    sta t_str_ptr1+1
    jsr print_string
    
    lda #<msg_result_infix
    sta t_str_ptr1
    lda #>msg_result_infix
    sta t_str_ptr1+1
    jsr print_string
    
    lda temp1+1
    sta temp2+1
    lda temp1
    sta temp2
    jsr print_dec_16
    
    jsr print_crlf
    jsr print_crlf
    lda #<msg_press_any_key
    sta t_str_ptr1
    lda #>msg_press_any_key
    sta t_str_ptr1+1
    jsr print_string
    jsr wait_for_key
    jmp main_loop

@invalid_expr:
    lda #<msg_invalid_expression
    sta t_str_ptr1
    lda #>msg_invalid_expression
    sta t_str_ptr1+1
    jsr print_string
    jsr print_crlf
    jsr wait_for_key
    jmp main_loop

@overflow:
    lda #<msg_overflow
    sta t_str_ptr1
    lda #>msg_overflow
    sta t_str_ptr1+1
    jsr print_string
    jsr print_crlf
    jsr wait_for_key
    jmp main_loop

@negative:
    lda #<msg_negative_result
    sta t_str_ptr1
    lda #>msg_negative_result
    sta t_str_ptr1+1
    jsr print_string
    jsr print_crlf
    jsr wait_for_key
    jmp main_loop

@div_zero:
    lda #<msg_divide_by_zero
    sta t_str_ptr1
    lda #>msg_divide_by_zero
    sta t_str_ptr1+1
    jsr print_string
    jsr print_crlf
    jsr wait_for_key
    jmp main_loop

; ---------------------------------------------------------------------------
; Simple multiply by 10 helper
; Multiplies the 16-bit value in temp1 by 10
; Result in temp1, Carry set if overflow
; ---------------------------------------------------------------------------
multiply_by_10_simple:
    ; Save original
    lda temp1
    sta temp2
    lda temp1+1
    sta temp2+1
    
    ; Multiply by 8 (shift left 3)
    asl temp1
    rol temp1+1
    asl temp1
    rol temp1+1
    asl temp1
    rol temp1+1
    
    ; Multiply original by 2 (shift left 1)
    asl temp2
    rol temp2+1
    
    ; Add together (x8 + x2 = x10)
    clc
    lda temp1
    adc temp2
    sta temp1
    lda temp1+1
    adc temp2+1
    sta temp1+1
    bcs @overflow
    clc
    rts
@overflow:
    sec
    rts

; ---------------------------------------------------------------------------
; Subroutine: hex_string_to_decimal
; Converts the hex string in INPUT_BUFFER to a 16-bit decimal value in temp1
; ---------------------------------------------------------------------------
hex_string_to_decimal:
    ldx #0              ; Index into input buffer
    lda #0
    sta temp1
    sta temp1+1         ; Initialize result to 0

@loop:
    lda INPUT_BUFFER, x
    beq @done           ; End of string

    ; Convert ASCII hex digit to value (0-15)
    jsr ascii_hex_to_value
    bcs @invalid_hex_digit  ; Carry set if invalid

    ; Shift existing value left by 4 bits (multiply by 16)
    asl temp1
    rol temp1+1
    asl temp1
    rol temp1+1
    asl temp1
    rol temp1+1
    asl temp1
    rol temp1+1

    ; Add new digit to the result
    clc
    adc temp1
    sta temp1
    lda temp1+1
    adc #0
    sta temp1+1

    inx                 ; Next digit
    jmp @loop

@invalid_hex_digit:
    sec
    rts

@done:
    clc
    rts

; ---------------------------------------------------------------------------
; Subroutine: Get Decimal Input
; Gets a decimal string from the user (0-65535)
; Stores the result in INPUT_BUFFER.
; Returns Carry Clear if valid, Carry Set if invalid.
; ---------------------------------------------------------------------------
get_decimal_input:
    ldx #0              ; Index into INPUT_BUFFER
@input_loop:
    jsr CHRIN           ; Get a character
    bcc @input_loop     ; No character, loop back

    cmp #CR             ; Check for carriage return
    beq @input_done     ; End of input

    cmp #$08            ; Backspace
    beq @handle_backspace

    ; Validate input characters (0-9 only)
    cmp #'0'
    bcc @invalid_char
    cmp #'9'+1
    bcs @invalid_char

    sta INPUT_BUFFER, x ; Store the character
    inx                 ; Increment index
    cpx #5              ; Max 5 digits for 65535
    bcs @buffer_overflow

    jsr OUTCH           ; Echo the character
    jmp @input_loop     ; Get next character

@invalid_char:
    lda #$07            ; Bell character
    jsr OUTCH
    jmp @input_loop

@handle_backspace:
    cpx #0              ; Check if at start
    beq @input_loop     ; Don't backspace past the start
    
    dex                 ; Decrement index
    
    lda #$08            ; Backspace
    jsr OUTCH           ; Move cursor back
    lda #$20            ; Space
    jsr OUTCH           ; Overwrite with space
    lda #$08            ; Backspace again
    jsr OUTCH

    jmp @input_loop

@buffer_overflow:
    ; More than 5 digits - beep and ignore
    lda #$07            ; Bell character
    jsr OUTCH
    jmp @input_loop

@input_done:
    lda #0              ; Null-terminate the string
    sta INPUT_BUFFER, x
    
    jsr print_crlf

    ; Check if input is empty
    lda INPUT_BUFFER
    bne @check_range
    
    ; Empty input - treat as invalid
    sec
    rts

@check_range:
    ; Convert to number to check range (0-65535)
    jsr decimal_string_to_hex  ; This converts to temp1
    
    ; Check if result > 65535 (carry set means overflow)
    bcs @out_of_range
    
    ; Valid input
    clc
    rts

@out_of_range:
    lda #<msg_range_error
    sta t_str_ptr1
    lda #>msg_range_error
    sta t_str_ptr1+1
    jsr print_string
    jsr print_crlf
    sec
    rts

; ---------------------------------------------------------------------------
; Subroutine: decimal_string_to_hex
; Converts decimal string in INPUT_BUFFER to 16-bit binary in temp1
; Returns Carry Clear if valid, Carry Set if overflow (>65535)
; ---------------------------------------------------------------------------
decimal_string_to_hex:
    ldx #0              ; Index into input buffer
    lda #0
    sta temp1
    sta temp1+1         ; Initialize result to 0

@loop:
    lda INPUT_BUFFER, x
    beq @done           ; End of string

    ; Convert ASCII digit to value (0-9)
    sec
    sbc #'0'
    
    pha                 ; Save digit value
    
    ; Multiply current result by 10
    ; temp1 * 10 = (temp1 * 8) + (temp1 * 2)
    
    ; Save original value
    lda temp1
    sta temp2
    lda temp1+1
    sta temp2+1
    
    ; Multiply by 8 (shift left 3 times)
    asl temp1
    rol temp1+1
    asl temp1
    rol temp1+1
    asl temp1
    rol temp1+1
    
    ; Multiply original by 2 (shift left 1)
    asl temp2
    rol temp2+1
    
    ; Add them together (temp1 * 8) + (temp1 * 2) = temp1 * 10
    clc
    lda temp1
    adc temp2
    sta temp1
    lda temp1+1
    adc temp2+1
    sta temp1+1
    
    ; Check for overflow (carry set means > 65535)
    bcs @overflow
    
    ; Add the new digit
    pla                 ; Restore digit value
    clc
    adc temp1
    sta temp1
    lda temp1+1
    adc #0
    sta temp1+1
    
    ; Check for overflow again
    bcs @overflow
    
    inx                 ; Next digit
    jmp @loop

@overflow:
    pla                 ; Clean up stack
    sec                 ; Set carry to indicate overflow
    rts

@done:
    clc                 ; Success
    rts

; ---------------------------------------------------------------------------
; Address Range Calculation
; Takes start address (hex) and size in bytes (decimal)
; Calculates and displays start and end addresses in hex
; ---------------------------------------------------------------------------
addr_range:
    ; Get start address in hex
    lda #<prompt_start_address
    sta t_str_ptr1
    lda #>prompt_start_address
    sta t_str_ptr1+1
    jsr print_string

    jsr get_hex_input       ; Get start address, store in INPUT_BUFFER
    bcc @save_start
    jmp addr_range_error

@save_start:
    ; Convert hex string to number in temp1
    jsr hex_string_to_decimal
    bcc @save_start_valid
    jmp addr_range_error
    
@save_start_valid:
    ; Save start address in temp2 and also in dec_temp variables for safety
    lda temp1
    sta temp2               ; Save start low byte
    sta dec_temp_ten_thousands  ; Also save here for backup
    lda temp1+1
    sta temp2+1             ; Save start high byte
    sta dec_temp_thousands      ; Also save here for backup
    
    ; Get size in decimal
    lda #<prompt_size_bytes
    sta t_str_ptr1
    lda #>prompt_size_bytes
    sta t_str_ptr1+1
    jsr print_string

    jsr get_decimal_input    ; Get size, store in INPUT_BUFFER
    bcc @process_size
    jmp addr_range_error

@process_size:
    ; Convert decimal string to number in temp1
    jsr decimal_string_to_hex
    bcc @process_size_valid
    jmp addr_range_error
    
@process_size_valid:
    ; Save size
    lda temp1
    sta dec_temp_hundreds    ; Size low byte
    lda temp1+1
    sta dec_temp_tens_ones   ; Size high byte
    
    ; Restore start address from backup
    lda dec_temp_ten_thousands
    sta temp2
    lda dec_temp_thousands
    sta temp2+1
    
    ; Calculate end address = start + size - 1
    clc
    lda temp2
    adc temp1
    pha                     ; Save end low byte on stack
    lda temp2+1
    adc temp1+1
    pha                     ; Save end high byte on stack
    
    ; Check for carry (overflow beyond 16-bit)
    bcc @no_overflow
    
    ; Handle overflow (address > $FFFF)
    pla                     ; Clean up stack
    pla
    lda #<msg_range_overflow
    sta t_str_ptr1
    lda #>msg_range_overflow
    sta t_str_ptr1+1
    jsr print_string
    jsr print_crlf
    jmp addr_range_done
    
@no_overflow:
    ; Subtract 1 for end address
    pla                     ; Get end high byte
    sta temp1+1
    pla                     ; Get end low byte
    sta temp1
    
    ; Subtract 1
    lda temp1
    bne @dec_lo
    dec temp1+1
@dec_lo:
    dec temp1
    
    ; Display results
    jsr print_crlf
    lda #<msg_range_header
    sta t_str_ptr1
    lda #>msg_range_header
    sta t_str_ptr1+1
    jsr print_string
    jsr print_crlf
    jsr print_crlf
    
    ; Print start address
    lda #<msg_start_address
    sta t_str_ptr1
    lda #>msg_start_address
    sta t_str_ptr1+1
    jsr print_string
    
    lda temp2+1              ; Start address high byte
    jsr print_hex
    lda temp2                ; Start address low byte
    jsr print_hex
    jsr print_crlf
    
    ; Print end address
    lda #<msg_end_address
    sta t_str_ptr1
    lda #>msg_end_address
    sta t_str_ptr1+1
    jsr print_string
    
    lda temp1+1              ; End address high byte
    jsr print_hex
    lda temp1                ; End address low byte
    jsr print_hex
    jsr print_crlf
    
addr_range_done:
    jsr print_crlf
    lda #<msg_press_any_key
    sta t_str_ptr1
    lda #>msg_press_any_key
    sta t_str_ptr1+1
    jsr print_string
    jsr wait_for_key
    jmp main_loop

addr_range_error:
    lda #<msg_invalid_input
    sta t_str_ptr1
    lda #>msg_invalid_input
    sta t_str_ptr1+1
    jsr print_string
    jsr print_crlf
    jsr wait_for_key
    jmp main_loop

quit:
    lda #<msg_goodbye
    sta t_str_ptr1
    lda #>msg_goodbye
    sta t_str_ptr1+1
    jsr print_string
    jsr print_crlf
    jmp done

; ---------------------------------------------------------------------------
; Subroutines
; ---------------------------------------------------------------------------

display_menu:
    lda #<menu_text
    sta t_str_ptr1
    lda #>menu_text
    sta t_str_ptr1+1
    jsr print_string
    rts

; ---------------------------------------------------------------------------
; Wait for a single key press (blocking)
; ---------------------------------------------------------------------------
wait_for_key:
    jsr CHRIN
    bcc wait_for_key    ; Keep waiting if no key
    rts

; ---------------------------------------------------------------------------
; Get menu choice with echo (blocking until valid key)
; ---------------------------------------------------------------------------
get_menu_choice:
    jsr CHRIN
    bcc get_menu_choice ; Keep waiting if no key
    
    ; Key is in A, echo it
    pha                 ; Save key
    jsr OUTCH           ; Echo
    jsr print_crlf      ; Move to next line after echo
    pla                 ; Restore key
    rts

; ---------------------------------------------------------------------------
; Local System Call Implementations
; ---------------------------------------------------------------------------
CHRIN:
    lda ACIA_DATA
    beq @no_key
    sec                 ; Key available - set carry
    rts
@no_key:
    clc                 ; No key - clear carry
    rts

CRLF:
    lda #CR
    jsr OUTCH
    lda #LF
    jmp OUTCH

; ---------------------------------------------------------------------------
; Helper: Print CR/LF
; ---------------------------------------------------------------------------
print_crlf:
    lda #CR
    jsr OUTCH
    lda #LF
    jsr OUTCH
    rts

; ---------------------------------------------------------------------------
; Helper: Print null-terminated string
; Uses 65C02 PHY/PLY instructions
; ---------------------------------------------------------------------------
print_string:
    pha
    phy                 ; 65C02 instruction
    ldy #0
@loop:
    lda (t_str_ptr1), y
    beq @done
    jsr OUTCH
    iny
    bra @loop           ; 65C02 branch always
@done:
    ply                 ; 65C02 instruction
    pla
    rts

; ---------------------------------------------------------------------------
; Subroutine: Get Hex Input
; Gets a hex string from the user, handling $, 0x, and case-insensitivity.
; Stores the result in INPUT_BUFFER.
; Returns Carry Clear if valid, Carry Set if invalid.
; ---------------------------------------------------------------------------
get_hex_input:
    ldx #0              ; Index into INPUT_BUFFER
@input_loop:
    jsr CHRIN           ; Get a character
    bcc @input_loop     ; No character, loop back

    cmp #CR             ; Check for carriage return
    beq @input_done     ; End of input

    cmp #$08            ; Backspace
    beq @handle_backspace

    ; Validate input characters (0-9, A-F, a-f, $, x, X)
    jsr is_valid_hex_char
    bcc @store_char     ; Valid character

    ; Invalid character - beep or ignore
    lda #$07            ; Bell character
    jsr OUTCH
    jmp @input_loop

@store_char:
    sta INPUT_BUFFER, x ; Store the character in INPUT_BUFFER
    inx                 ; Increment index
    cpx #120            ; Check for buffer overflow (leave room for null)
    bcs @buffer_overflow

    jsr OUTCH           ; Echo the character
    jmp @input_loop     ; Get next character

@handle_backspace:
    cpx #0              ; Check if at start
    beq @input_loop     ; Don't backspace past the start
    
    dex                 ; Decrement index
    
    lda #$08            ; Backspace
    jsr OUTCH           ; Move cursor back
    lda #$20            ; Space
    jsr OUTCH           ; Overwrite with space
    lda #$08            ; Backspace again
    jsr OUTCH

    jmp @input_loop     ; Continue input

@buffer_overflow:
    ; Buffer overflow - ignore extra characters and beep
    lda #$07            ; Bell character
    jsr OUTCH
    jmp @input_loop

@input_done:
    lda #0              ; Null-terminate the string
    sta INPUT_BUFFER, x
    
    jsr print_crlf

    ; Check for prefix and strip if necessary
    lda #<INPUT_BUFFER
    sta t_str_ptr1
    lda #>INPUT_BUFFER
    sta t_str_ptr1+1
    jsr strip_hex_prefix
    
    ; Check if input is empty
    lda INPUT_BUFFER
    bne @valid_input
    
    ; Empty input - treat as invalid
    sec
    rts
    
@valid_input:
    clc
    rts

; ---------------------------------------------------------------------------
; Subroutine: Get Binary Input
; Gets a binary string from the user (0/1 only)
; Stores the result in INPUT_BUFFER.
; Returns Carry Clear if valid, Carry Set if invalid.
; ---------------------------------------------------------------------------
get_binary_input:
    ldx #0              ; Index into INPUT_BUFFER
@input_loop:
    jsr CHRIN           ; Get a character
    bcc @input_loop     ; No character, loop back

    cmp #CR             ; Check for carriage return
    beq @input_done     ; End of input

    cmp #$08            ; Backspace
    beq @handle_backspace

    ; Validate input characters (0 or 1 only)
    cmp #'0'
    bcc @invalid_char
    cmp #'1'+1
    bcs @invalid_char

    sta INPUT_BUFFER, x ; Store the character
    inx                 ; Increment index
    cpx #16             ; Max 16 bits
    bcs @buffer_overflow

    jsr OUTCH           ; Echo the character
    jmp @input_loop     ; Get next character

@invalid_char:
    lda #$07            ; Bell character
    jsr OUTCH
    jmp @input_loop

@handle_backspace:
    cpx #0              ; Check if at start
    beq @input_loop     ; Don't backspace past the start
    
    dex                 ; Decrement index
    
    lda #$08            ; Backspace
    jsr OUTCH           ; Move cursor back
    lda #$20            ; Space
    jsr OUTCH           ; Overwrite with space
    lda #$08            ; Backspace again
    jsr OUTCH

    jmp @input_loop

@buffer_overflow:
    ; More than 16 bits - beep and ignore
    lda #$07            ; Bell character
    jsr OUTCH
    jmp @input_loop

@input_done:
    lda #0              ; Null-terminate the string
    sta INPUT_BUFFER, x
    
    jsr print_crlf

    ; Check if input is empty
    lda INPUT_BUFFER
    bne @valid_input
    
    ; Empty input - treat as invalid
    sec
    rts
    
@valid_input:
    clc
    rts

; ---------------------------------------------------------------------------
; Subroutine: binary_string_to_hex
; Converts binary string in INPUT_BUFFER to 16-bit value in temp1
; Returns Carry Clear if valid, Carry Set if invalid.
; ---------------------------------------------------------------------------
binary_string_to_hex:
    ldx #0              ; Index into input buffer
    lda #0
    sta temp1
    sta temp1+1         ; Initialize result to 0

@loop:
    lda INPUT_BUFFER, x
    beq @done           ; End of string

    ; Convert ASCII '0'/'1' to value (0 or 1)
    sec
    sbc #'0'
    cmp #2              ; Check if > 1 (shouldn't happen if validated)
    bcs @invalid
    
    ; Shift existing value left by 1 bit (multiply by 2)
    asl temp1
    rol temp1+1
    
    ; Add new bit to the result
    clc
    adc temp1
    sta temp1
    lda temp1+1
    adc #0
    sta temp1+1

    inx                 ; Next digit
    jmp @loop

@invalid:
    sec
    rts

@done:
    clc
    rts

; ---------------------------------------------------------------------------
; Subroutine: Print 16-bit value as binary with spaces every 4 bits
; Input: temp1 (low byte), temp1+1 (high byte)
; ---------------------------------------------------------------------------
print_binary_16:
    ; Save registers
    pha
    txa
    pha
    tya
    pha
    
    ldx #15              ; 16 bits, start from bit 15 (MSB)
    
@bit_loop:
    ; Check if we need a space (every 4 bits, but not at start)
    cpx #15              ; Don't print space before first bit
    beq @print_bit
    txa
    and #$03             ; Check if x is multiple of 4
    cmp #3               ; After bits 15,11,7,3 we need a space
    bne @print_bit
    lda #' '
    jsr OUTCH
    
@print_bit:
    ; Test the bit
    ; Check if bit in high byte (bits 8-15)
    cpx #8
    bcc @low_byte
    
    ; High byte bit
    txa
    sec
    sbc #8               ; Convert to 0-7 for high byte
    tay
    lda temp1+1
    jmp @test_bit
    
@low_byte:
    ; Low byte bit
    txa
    tay
    lda temp1
    
@test_bit:
    and bit_table, y
    beq @print_zero
    
    lda #'1'
    jsr OUTCH
    jmp @next_bit
    
@print_zero:
    lda #'0'
    jsr OUTCH
    
@next_bit:
    dex
    bpl @bit_loop
    
    ; Restore registers
    pla
    tay
    pla
    tax
    pla
    rts

; Bit test table for 8 bits
bit_table:
    .byte $80, $40, $20, $10, $08, $04, $02, $01

; ---------------------------------------------------------------------------
; Subroutine: is_valid_hex_char
; Checks if a character in A is a valid hex character (0-9, A-F, a-f, $, x, X).
; Returns Carry Clear if valid, Carry Set if invalid.
; ---------------------------------------------------------------------------
is_valid_hex_char:
    cmp #'0'
    bcc @invalid
    cmp #'9'+1
    bcc @valid
    
    cmp #'A'
    bcc @invalid
    cmp #'F'+1
    bcc @valid
    
    cmp #'a'
    bcc @invalid
    cmp #'f'+1
    bcc @valid
    
    cmp #'$'
    beq @valid
    cmp #'x'
    beq @valid
    cmp #'X'
    beq @valid

@invalid:
    sec                 ; Invalid character
    rts
@valid:
    clc                 ; Valid character
    rts

; ---------------------------------------------------------------------------
; Helper: Print byte in A as hex
; ---------------------------------------------------------------------------
print_hex:
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr print_nibble
    pla
    and #$0F
    jsr print_nibble
    rts

print_nibble:
    cmp #10
    bcc @digit
    ; It's 10-15, convert to 'A'-'F'
    clc
    adc #'A'-10         ; Add 55 (since 'A' = 65, 65-10=55)
    jmp @print
@digit:
    ; It's 0-9, convert to '0'-'9'
    clc
    adc #'0'
@print:
    jsr OUTCH
    rts

; ---------------------------------------------------------------------------
; Helper: Print 8-bit number as decimal (kept for compatibility)
; ---------------------------------------------------------------------------
print_dec_8:
    sta t_ptr_temp
    
    ldy #0              ; Hundreds flag
    ldx #0              ; Hundreds counter
@div100:
    lda t_ptr_temp
    cmp #100
    bcc @print_100
    sbc #100
    sta t_ptr_temp
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
    
    ldx #0              ; Tens counter
@div10:
    lda t_ptr_temp
    cmp #10
    bcc @print_10
    sbc #10
    sta t_ptr_temp
    inx
    jmp @div10
@print_10:
    ; Check if we should print tens
    cpy #1              ; Did we print hundreds?
    beq @do_print_10
    cpx #0              ; Is tens > 0?
    bne @do_print_10
    jmp @print_1
@do_print_10:
    txa
    ora #'0'
    jsr OUTCH
    
@print_1:
    lda t_ptr_temp
    ora #'0'
    jsr OUTCH
    rts

; ---------------------------------------------------------------------------
; Helper: Print 16-bit number as decimal (0-65535)
; Input: temp1 (low byte), temp1+1 (high byte)
; ---------------------------------------------------------------------------
print_dec_16:
    ; Save registers
    pha
    txa
    pha
    tya
    pha
    
    ; Copy 16-bit value to work area
    lda temp1
    sta dec_value_lo
    lda temp1+1
    sta dec_value_hi
    
    ; Initialize digit counters
    lda #0
    sta dec_temp_ten_thousands
    sta dec_temp_thousands
    sta dec_temp_hundreds
    
    ; Calculate ten-thousands (10000)
    ldx #0
@calc_ten_thousands:
    ; Compare with 10000
    lda dec_value_hi
    cmp #>10000        ; Compare high byte ($27 = 10000>>8)
    bcc @done_ten_thousands
    bne @subtract_10000
    lda dec_value_lo
    cmp #<10000        ; Compare low byte ($10 = 10000 & $FF)
    bcc @done_ten_thousands
    
@subtract_10000:
    ; Subtract 10000
    lda dec_value_lo
    sec
    sbc #<10000        ; Subtract $10
    sta dec_value_lo
    lda dec_value_hi
    sbc #>10000        ; Subtract $27
    sta dec_value_hi
    inx
    jmp @calc_ten_thousands

@done_ten_thousands:
    stx dec_temp_ten_thousands
    
    ; Calculate thousands (1000)
    ldx #0
@calc_thousands:
    ; Compare with 1000
    lda dec_value_hi
    cmp #>1000         ; Compare high byte ($03 = 1000>>8)
    bcc @done_thousands
    bne @subtract_1000
    lda dec_value_lo
    cmp #<1000         ; Compare low byte ($E8 = 1000 & $FF)
    bcc @done_thousands
    
@subtract_1000:
    lda dec_value_lo
    sec
    sbc #<1000         ; Subtract $E8
    sta dec_value_lo
    lda dec_value_hi
    sbc #>1000         ; Subtract $03
    sta dec_value_hi
    inx
    jmp @calc_thousands

@done_thousands:
    stx dec_temp_thousands
    
    ; Calculate hundreds (100)
    ldx #0
@calc_hundreds:
    ; Compare with 100
    lda dec_value_hi
    bne @subtract_100   ; If high byte non-zero, definitely >=100
    lda dec_value_lo
    cmp #100
    bcc @done_hundreds
    
@subtract_100:
    lda dec_value_lo
    sec
    sbc #100
    sta dec_value_lo
    lda dec_value_hi
    sbc #0
    sta dec_value_hi
    inx
    jmp @calc_hundreds

@done_hundreds:
    stx dec_temp_hundreds
    
    ; Remaining value is tens and ones (0-99)
    lda dec_value_lo
    sta dec_temp_tens_ones
    
    ; Print ten-thousands digit (always print if non-zero)
    lda dec_temp_ten_thousands
    beq @check_thousands
    ora #'0'
    jsr OUTCH
    
@check_thousands:
    lda dec_temp_thousands
    beq @check_hundreds
    ora #'0'
    jsr OUTCH
    jmp @check_hundreds_continue
    
@check_hundreds:
    ; If we printed ten-thousands but not thousands, print a zero for thousands
    lda dec_temp_ten_thousands
    beq @check_hundreds_continue
    lda #'0'
    jsr OUTCH
    
@check_hundreds_continue:
    lda dec_temp_hundreds
    beq @check_tens
    ora #'0'
    jsr OUTCH
    jmp @check_tens_continue
    
@check_tens:
    ; If we printed any higher digits, print a zero for hundreds
    lda dec_temp_ten_thousands
    ora dec_temp_thousands
    beq @check_tens_continue
    lda #'0'
    jsr OUTCH
    
@check_tens_continue:
    ; Convert remaining 0-99 to tens and ones
    lda dec_temp_tens_ones
    ldx #0
@calc_tens:
    cmp #10
    bcc @print_tens_done
    sbc #10
    inx
    jmp @calc_tens
    
@print_tens_done:
    pha                 ; Save ones
    
    ; Print tens digit
    cpx #0
    bne @print_tens_digit
    ; If we printed any higher digits, print a zero for tens
    lda dec_temp_ten_thousands
    ora dec_temp_thousands
    ora dec_temp_hundreds
    beq @print_ones
    lda #'0'
    jsr OUTCH
    jmp @print_ones
    
@print_tens_digit:
    txa
    ora #'0'
    jsr OUTCH
    
@print_ones:
    pla                 ; Restore ones
    ora #'0'
    jsr OUTCH
    
    ; Restore registers
    pla
    tay
    pla
    tax
    pla
    rts

; ---------------------------------------------------------------------------
; Subroutine: ASCII Hex to Value
; Converts an ASCII hex character (0-9, A-F, a-f) in A to its numeric value (0-15)
; Returns the value in A. Carry is set if the character is not a valid hex digit.
; ---------------------------------------------------------------------------
ascii_hex_to_value:
    cmp #'0'
    bcc @invalid
    cmp #'9'+1
    bcs @check_alpha
    ; It's 0-9
    sec
    sbc #'0'
    clc
    rts
    
@check_alpha:
    cmp #'A'
    bcc @invalid
    cmp #'F'+1
    bcs @check_lower
    ; It's A-F
    sec
    sbc #'A'-10
    clc
    rts
    
@check_lower:
    cmp #'a'
    bcc @invalid
    cmp #'f'+1
    bcs @invalid
    ; It's a-f
    sec
    sbc #'a'-10
    clc
    rts
    
@invalid:
    sec
    rts

; ---------------------------------------------------------------------------
; Subroutine: Strip Hex Prefix
; Checks for and strips the "0x" or "$" prefix from a hex string.
; t_str_ptr1 must point to the string.
; ---------------------------------------------------------------------------
strip_hex_prefix:
    lda (t_str_ptr1)    ; Load first character
    cmp #'$'
    beq @strip_dollar
    cmp #'0'
    bne @no_prefix
    
    ; Check for "0x" or "0X"
    ldy #1
    lda (t_str_ptr1),y
    cmp #'x'
    beq @strip_0x
    cmp #'X'
    beq @strip_0x
    rts                 ; Not "0x", so no prefix to strip
    
@strip_0x:
    ; Strip "0x" prefix - shift string left by 2
    ldy #2
@shift_0x_loop:
    lda (t_str_ptr1),y  ; Get character from position Y
    dey
    dey
    sta (t_str_ptr1),y  ; Store it 2 positions earlier
    iny
    iny
    iny
    cmp #0
    beq @done_0x
    jmp @shift_0x_loop
@done_0x:
    rts

@strip_dollar:
    ; Strip "$" prefix - shift string left by 1
    ldy #1
@shift_dollar_loop:
    lda (t_str_ptr1),y  ; Get character from position Y
    dey
    sta (t_str_ptr1),y  ; Store it 1 position earlier
    iny
    iny
    cmp #0
    beq @done_dollar
    jmp @shift_dollar_loop
@done_dollar:
    rts

@no_prefix:
    rts                 ; No prefix to strip

; ---------------------------------------------------------------------------
; RODATA - All strings
; ---------------------------------------------------------------------------
.segment "RODATA"

prompt_hex_input: 
    .asciiz "Enter hex number (max 4 digits, $ or 0x prefix allowed): "

prompt_decimal_input:
    .asciiz "Enter decimal number (0-65535): "

prompt_binary_input:
    .asciiz "Enter binary number (max 16 bits, 0/1 only): "

prompt_simple_expr:
    .asciiz "Enter simple expression (e.g., 7+4, 10-3, 6*5, 15/4): "

menu_text:
    .byte   CR, LF
    .byte   "Retro Calculator Menu:"
    .byte   CR, LF
    .byte   "1. Hex to Binary"
    .byte   CR, LF
    .byte   "2. Binary to Hex"
    .byte   CR, LF
    .byte   "3. Hex to Decimal"
    .byte   CR, LF
    .byte   "4. Decimal to Hex"
    .byte   CR, LF
    .byte   "5. Address Range Calculation"
    .byte   CR, LF
    .byte   "6. Math Expression Evaluation"
    .byte   CR, LF
    .byte   "7. Quit"
    .byte   CR, LF
    .byte   "Enter your choice (1-7): "
    .byte   CR, LF, 0  ; Final null terminator

msg_invalid_choice:
    .asciiz "Invalid choice. Please try again."

msg_invalid_hex:
    .asciiz "Error: Invalid hex digit. Please enter 0-9, A-F (prefixes $ or 0x allowed)"

msg_invalid_decimal:
    .asciiz "Error: Invalid decimal digit. Please enter 0-9 only."

msg_invalid_binary:
    .asciiz "Error: Invalid binary digit. Please enter 0 or 1 only."

msg_range_error:
    .asciiz "Error: Number out of range (0-65535 only)."

msg_hex_decimal_result_prefix:
    .asciiz "Hex "

msg_hex_decimal_result_infix:
    .asciiz " = Decimal "

msg_decimal_hex_result_prefix:
    .asciiz "Decimal "

msg_decimal_hex_result_infix:
    .asciiz " = Hex "

msg_hex_binary_result_prefix:
    .asciiz "Hex "

msg_hex_binary_result_infix:
    .asciiz " = Binary "

msg_binary_hex_result_prefix:
    .asciiz "Binary "

msg_binary_hex_result_infix:
    .asciiz " = Hex "

msg_result_prefix:
    .asciiz ""

msg_result_infix:
    .asciiz " = "

msg_invalid_expression:
    .asciiz "Error: Invalid expression. Use format: num+num, num-num, num*num, num/num (no spaces)"

msg_divide_by_zero:
    .asciiz "Error: Division by zero"

msg_overflow:
    .asciiz "Error: Result overflow (0-65535 only)"

msg_negative_result:
    .asciiz "Error: Negative result not supported"

msg_not_implemented:
    .asciiz "Feature not implemented yet."
    .byte   CR, LF
    .asciiz "Press any key to continue..."

msg_press_any_key:
    .asciiz "Press any key to continue..."

prompt_start_address:
    .asciiz "Enter start address in hex: "

prompt_size_bytes:
    .asciiz "Enter size in decimal bytes: "

msg_range_header:
    .asciiz "=== Address Range Calculation ==="

msg_start_address:
    .asciiz "Start address: $"

msg_end_address:
    .asciiz "End address: $"

msg_size_info:
    .asciiz "Size: "

msg_size_in_hex:
    .asciiz " bytes ("

msg_range_overflow:
    .asciiz "Error: Address range exceeds $FFFF (64K boundary)"

msg_invalid_input:
    .asciiz "Error: Invalid input. Please try again."

msg_goodbye:
    .asciiz "Goodbye!"

; ---------------------------------------------------------------------------
; END
; ---------------------------------------------------------------------------
done:
    ; Restore registers
    pla
    tay
    pla
    tax
    pla
    plp
    clc                 ; Return with carry clear
    rts
