; bench.s - Filesystem Benchmark
; Usage: BENCH
;
; This command performs a simple benchmark by:
; 1. Writing 4KB to a temporary file.
; 2. Reading 4KB from the temporary file.
; 3. Deleting the temporary file.
;
; It follows the definitive transient command pattern.

.include "pico_def.inc"
.import pico_send_request, send_byte, read_byte

; ---------------------------------------------------------------------------
; System calls
; ---------------------------------------------------------------------------
OUTCH = $FFEF
CRLF  = $FED1

; ---------------------------------------------------------------------------
; Zero Page (USE ONLY $58-$5F)
; ---------------------------------------------------------------------------
t_file_handle = $58     ; 1 byte - Stores the file handle from the Pico
t_str_ptr1    = $5A     ; 2 bytes - Pointer for print_string helper
t_byte_count  = $5C     ; 2 bytes - for robust streaming loops
t_ptr_temp    = $5E     ; 2 bytes - Unused, but reserved per convention

; ---------------------------------------------------------------------------
; Imported Buffers & Variables
; ---------------------------------------------------------------------------
.import CMD_ID, ARG_LEN, ARG_BUFF, LAST_STATUS, RESP_BUFF, RESP_LEN

; ---------------------------------------------------------------------------
; HEADER - MUST be first
; ---------------------------------------------------------------------------
.segment "HEADER"
    .word $0800        ; Load address

; ---------------------------------------------------------------------------
; CODE - Program starts here
; ---------------------------------------------------------------------------
.segment "CODE"
start:
    ; 1. Standard Entry: Preserve registers and sanitize CPU state
    php
    pha
    txa
    pha
    tya
    pha
    cld
    sei

    ; Announce start of benchmark
    lda #<msg_start
    sta t_str_ptr1
    lda #>msg_start
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF

    ; -----------------------------------------------------------------------
    ; STAGE 1: WRITE TEST
    ; -----------------------------------------------------------------------
    lda #<msg_write
    sta t_str_ptr1
    lda #>msg_write
    sta t_str_ptr1+1
    jsr print_string

    ; Start timer
    lda #CMD_TIMER_START
    sta CMD_ID
    lda #0
    sta ARG_LEN
    jsr pico_send_request

    ; Use CMD_FS_SAVEMEM streaming protocol
    ; 1. Build arguments: "filename\0" + length (2 bytes)
    lda #<bench_file
    sta t_str_ptr1
    lda #>bench_file
    sta t_str_ptr1+1
    ldy #0
@copy_w_fname:
    lda (t_str_ptr1),y
    sta ARG_BUFF,y
    iny
    cmp #0
    bne @copy_w_fname

    ; Append length to write (4064 bytes = $0FE0)
    lda #$E0
    sta ARG_BUFF,y
    iny
    lda #$0F
    sta ARG_BUFF,y
    iny
    sty ARG_LEN

    ; 2. Manually send command and args
    lda #CMD_FS_SAVEMEM
    jsr send_cmd_manual

    ; 3. Read initial response (should be STATUS_OK)
    jsr read_response_manual
    cmp #STATUS_OK
    beq @write_init_ok
    jmp @error
@write_init_ok:

    ; Set Port A to output for streaming bytes. This is the critical fix.
    lda #$FF
    sta VIA_DDRA

    ; 4. Stream the data bytes
    ; Use robust zero-page counter instead of registers
    lda #$E0
    sta t_byte_count
    lda #$0F
    sta t_byte_count+1
@stream_write_loop:
    lda #'B'
    jsr send_byte

    dec t_byte_count
    lda t_byte_count
    cmp #$FF
    bne @write_loop_cont
    dec t_byte_count+1
@write_loop_cont:
    lda t_byte_count
    ora t_byte_count+1
    bne @stream_write_loop
    ; 5. Read final response
    jsr read_response_manual
    cmp #STATUS_OK
    beq @write_final_ok
    jmp @error
@write_final_ok:

    ; Stop timer and get duration
    lda #CMD_TIMER_STOP
    sta CMD_ID
    lda #0
    sta ARG_LEN
    jsr pico_send_request

    lda LAST_STATUS
    beq @write_time_ok
    jmp @error
@write_time_ok:

    ; Print duration
    lda #<msg_time
    sta t_str_ptr1
    lda #>msg_time
    sta t_str_ptr1+1
    jsr print_string

    ldx #3 ; Print 32-bit hex value from RESP_BUFF (MSB first)
@print_write_time:
    lda RESP_BUFF, x
    jsr print_hex
    dex
    bpl @print_write_time

    lda #<msg_us
    sta t_str_ptr1
    lda #>msg_us
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    
    ; Calculate and print Bytes/sec
    ; dividend = 4064000000 ($F2540400)
    lda #$00
    sta dividend
    lda #$04
    sta dividend+1
    lda #$54
    sta dividend+2
    lda #$F2
    sta dividend+3
    ; divisor = time from RESP_BUFF
    lda RESP_BUFF
    sta divisor
    lda RESP_BUFF+1
    sta divisor+1
    lda RESP_BUFF+2
    sta divisor+2
    lda RESP_BUFF+3
    sta divisor+3
    jsr divide32
    jsr print_bytes_per_sec

    ; -----------------------------------------------------------------------
    ; STAGE 2: READ TEST
    ; -----------------------------------------------------------------------
    lda #<msg_read
    sta t_str_ptr1
    lda #>msg_read
    sta t_str_ptr1+1
    jsr print_string

    ; Start timer
    lda #CMD_TIMER_START
    sta CMD_ID
    lda #0
    sta ARG_LEN
    jsr pico_send_request

    ; Use CMD_FS_LOADMEM streaming protocol
    ; 1. Build arguments: "filename\0"
    lda #<bench_file
    sta t_str_ptr1
    lda #>bench_file
    sta t_str_ptr1+1
    ldy #0
@copy_r_fname:
    lda (t_str_ptr1),y
    sta ARG_BUFF,y
    iny
    cmp #0
    bne @copy_r_fname
    sty ARG_LEN
    
    ; 2. Manually send command and args
    lda #CMD_FS_LOADMEM
    jsr send_cmd_manual

    ; 3. Read initial response (Status + 2-byte length)
    jsr read_response_manual
    cmp #STATUS_OK
    beq @read_init_ok
    jmp @error
@read_init_ok:
    ; RESP_BUFF+0 has len_lo, RESP_BUFF+1 has len_hi
    lda RESP_BUFF
    sta t_byte_count      ; Store low byte of count
    lda RESP_BUFF+1
    sta t_byte_count+1    ; Store high byte of count

    ; 4. Stream the data bytes from Pico
@stream_read_loop:
    jsr read_byte

    ; Decrement 16-bit zero-page counter
    dec t_byte_count
    lda t_byte_count
    cmp #$FF
    bne @read_loop_cont
    dec t_byte_count+1
@read_loop_cont:
    lda t_byte_count
    ora t_byte_count+1
    bne @stream_read_loop

    ; Stop timer and get duration
    lda #CMD_TIMER_STOP
    sta CMD_ID
    lda #0
    sta ARG_LEN
    jsr pico_send_request

    lda LAST_STATUS
    beq @read_time_ok
    jmp @error
@read_time_ok:

    ; Print duration
    lda #<msg_time
    sta t_str_ptr1
    lda #>msg_time
    sta t_str_ptr1+1
    jsr print_string

    ldx #3 ; Print 32-bit hex value from RESP_BUFF (MSB first)
@print_read_time:
    lda RESP_BUFF, x
    jsr print_hex
    dex
    bpl @print_read_time

    lda #<msg_us
    sta t_str_ptr1
    lda #>msg_us
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF

    ; Calculate and print Bytes/sec
    ; dividend = 4064000000 ($F2540400)
    lda #$00
    sta dividend
    lda #$04
    sta dividend+1
    lda #$54
    sta dividend+2
    lda #$F2
    sta dividend+3
    ; divisor = time from RESP_BUFF
    lda RESP_BUFF
    sta divisor
    lda RESP_BUFF+1
    sta divisor+1
    lda RESP_BUFF+2
    sta divisor+2
    lda RESP_BUFF+3
    sta divisor+3
    jsr divide32
    jsr print_bytes_per_sec

    ; -----------------------------------------------------------------------
    ; STAGE 3: CLEANUP
    ; -----------------------------------------------------------------------
    lda #<msg_cleanup
    sta t_str_ptr1
    lda #>msg_cleanup
    sta t_str_ptr1+1
    jsr print_string

    ; Remove the file
    lda #<bench_file
    sta t_str_ptr1
    lda #>bench_file
    sta t_str_ptr1+1
    ldy #0 ; Re-use y
@copy_filename3:
    lda (t_str_ptr1),y
    sta ARG_BUFF,y
    iny
    cmp #0
    bne @copy_filename3
    sty ARG_LEN
    
    lda #CMD_FS_REMOVE
    sta CMD_ID
    jsr pico_send_request

    lda LAST_STATUS
    beq @remove_ok
    jmp @error
@remove_ok:
    lda #<msg_ok
    sta t_str_ptr1
    lda #>msg_ok
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    jmp @done

@error:
    lda #<msg_fail
    sta t_str_ptr1
    lda #>msg_fail
    sta t_str_ptr1+1
    jsr print_string
    
    ; Print status code
    lda LAST_STATUS
    jsr print_hex
    jsr CRLF

@done:
    ; 2. Standard Exit: Restore registers and return
    pla
    tay
    pla
    tax
    pla
    plp
    clc              ; Return with carry clear
    rts

; ---------------------------------------------------------------------------
; Helper: Manually send command and arguments (for streaming)
; In: A = Command ID
; ---------------------------------------------------------------------------
send_cmd_manual:
    sta CMD_ID
    lda #$FF
    sta VIA_DDRA    ; Port A to Output

    lda CMD_ID
    jsr send_byte
    lda ARG_LEN
    jsr send_byte

    ldx #0
@send_args:
    cpx ARG_LEN
    beq @args_done
    lda ARG_BUFF, x
    jsr send_byte
    inx
    jmp @send_args
@args_done:
    rts

; ---------------------------------------------------------------------------
; Helper: Manually read response header (for streaming)
; Out: A = Status, RESP_BUFF = payload (len_lo, len_hi)
; ---------------------------------------------------------------------------
read_response_manual:
    lda #$00
    sta VIA_DDRA    ; Port A to Input

    jsr read_byte   ; Status
    sta LAST_STATUS
    jsr read_byte   ; Len Lo
    sta RESP_BUFF
    jsr read_byte   ; Len Hi
    sta RESP_BUFF+1

    lda LAST_STATUS
    rts

; ---------------------------------------------------------------------------
; Helper: Print null-terminated string
; ---------------------------------------------------------------------------
print_string:
    pha
    phy
    ldy #0
@ps_loop:
    lda (t_str_ptr1), y
    beq @ps_done
    jsr OUTCH
    iny
    jmp @ps_loop
@ps_done:
    ply
    pla
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
    adc #6
@digit:
    adc #'0'
    jsr OUTCH
    rts

; ---------------------------------------------------------------------------
; Helper: 32-bit by 32-bit Unsigned Division
; dividend / divisor -> quotient, remainder
; Uses BSS variables. Clobbers A,X,Y.
; ---------------------------------------------------------------------------
divide32:
    ; Clear quotient
    lda #0
    sta quotient
    sta quotient+1
    sta quotient+2
    sta quotient+3
    sta remainder
    sta remainder+1
    sta remainder+2
    sta remainder+3

    ldx #32 ; 32 bits
div32_loop:
    ; Shift dividend left, high bit into carry
    asl dividend
    rol dividend+1
    rol dividend+2
    rol dividend+3

    ; Shift carry into remainder
    rol remainder
    rol remainder+1
    rol remainder+2
    rol remainder+3

    ; temp = remainder - divisor
    sec
    lda remainder
    sbc divisor
    sta temp
    lda remainder+1
    sbc divisor+1
    sta temp+1
    lda remainder+2
    sbc divisor+2
    sta temp+2
    lda remainder+3
    sbc divisor+3
    sta temp+3

    bcc @sub_failed ; if carry is clear, remainder < divisor

    ; Subtraction succeeded, so commit it by copying temp to remainder
    lda temp
    sta remainder
    lda temp+1
    sta remainder+1
    lda temp+2
    sta remainder+2
    lda temp+3
    sta remainder+3

@sub_failed:
    ; The carry from the subtraction is our quotient bit
    rol quotient
    rol quotient+1
    rol quotient+2
    rol quotient+3
    
    dex
    bne div32_loop
    rts


; ---------------------------------------------------------------------------
; Helper: Print 16-bit unsigned decimal from num_to_print
; ---------------------------------------------------------------------------
print_16bit_decimal:
    ldx #0 ; digit count
@div_loop:
    ; divide num_to_print by 10
    txa
    pha ; Save digit count (X)
    lda #10
    jsr divide16x8 ; remainder in A
    tay ; Save remainder
    pla
    tax ; Restore digit count (X)
    tya ; Restore remainder
    pha ; push remainder
    inx
    lda num_to_print
    ora num_to_print+1
    bne @div_loop

@print_loop:
    pla
    ora #'0'
    jsr OUTCH
    dex
    bne @print_loop
    rts

; ---------------------------------------------------------------------------
; Helper: 16-bit by 8-bit Unsigned Division
; In: num_to_print (16-bit), A (8-bit divisor)
; Out: quotient in num_to_print, remainder in A
; ---------------------------------------------------------------------------
divide16x8:
    sta divisor8
    lda #0
    sta remainder8
    ldx #16
div16x8_loop:
    asl num_to_print
    rol num_to_print+1
    rol remainder8
    
    lda remainder8
    cmp divisor8
    bcc div16x8_nosub
    
    sbc divisor8
    sta remainder8
    inc num_to_print
div16x8_nosub:
    dex
    bne div16x8_loop
    
    lda remainder8
    rts

; ---------------------------------------------------------------------------
; Helper: Print throughput summary
; ---------------------------------------------------------------------------
print_bytes_per_sec:
    ; Print " (~"
    lda #<msg_bps_pfx
    sta t_str_ptr1
    lda #>msg_bps_pfx
    sta t_str_ptr1+1
    jsr print_string

    ; Print the number
    lda quotient
    sta num_to_print
    lda quotient+1
    sta num_to_print+1
    jsr print_16bit_decimal

    ; Print " Bytes/sec)"
    lda #<msg_bps_sfx
    sta t_str_ptr1
    lda #>msg_bps_sfx
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    rts

.segment "BSS"
dividend:   .res 4
divisor:    .res 4
quotient:   .res 4
remainder:  .res 4
temp:       .res 4
num_to_print: .res 2
divisor8:   .res 1
remainder8: .res 1

; ---------------------------------------------------------------------------
; RODATA - All strings at the END of the file
; ---------------------------------------------------------------------------
.segment "RODATA"
msg_start:   .asciiz "Starting filesystem benchmark..."
msg_write:   .asciiz "  Write 4064 bytes... "
msg_read:    .asciiz "  Read 4064 bytes...  "
msg_cleanup: .asciiz "  Cleaning up... "
msg_ok:      .asciiz "OK"
msg_time:    .asciiz "Time: $"
msg_us:      .asciiz " us "
msg_bps_pfx: .asciiz "(~"
msg_bps_sfx: .asciiz " Bytes/sec)"
msg_fail:    .asciiz "FAIL! Status: $"
bench_file:  .asciiz "/bench.tmp"
