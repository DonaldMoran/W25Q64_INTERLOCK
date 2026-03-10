; -----------------------------------------------------------------------------
; COPY Command for W25Q64_INTERLOCK
; Aliased as CP
;
; This is a transient program. Invoke with:
; RUN COPY.BIN <source_file> <destination_file>
; -----------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; Explicitly declare external symbols from pico_lib.s
; ---------------------------------------------------------------------------
.import pico_send_request, send_byte, read_byte
.import CMD_ID, ARG_LEN, ARG_BUFF, LAST_STATUS, RESP_LEN, RESP_BUFF

; ---------------------------------------------------------------------------
; Include constants (optional - can use numeric values)
; ---------------------------------------------------------------------------
.include "../../common/pico_def.inc"

; System Constants
LOAD_ADDR    = $0800   ; Standard load address for transient programs
INPUT_BUFFER = $0300    ; Location of Input Buffer from shell

; Zero page pointers for argument parsing
arg_scan_ptr = $58 ; Pointer for scanning INPUT_BUFFER
src_ptr      = $5A ; Pointer to source filename arg
dst_ptr      = $5C ; Pointer to destination filename arg

; -----------------------------------------------------------------------------
; Header (Load Address)
; -----------------------------------------------------------------------------
.segment "HEADER"
    .word   LOAD_ADDR

.segment "CODE"
start:
    ; Standard Entry: Preserve registers and sanitize CPU state
    php
    pha
    txa
    pha
    tya
    pha
    cld
    sei

    ; -------------------------------------------------------------------------
    ; 1. Parse Arguments
    ;    We assume the command line in INPUT_BUFFER ($0300) is:
    ;    "RUN <progname> <src> <dst>"
    ;    We need to find the <src> and <dst> arguments.
    ; -------------------------------------------------------------------------
    lda #<INPUT_BUFFER
    sta arg_scan_ptr
    lda #>INPUT_BUFFER
    sta arg_scan_ptr+1

    ; At start, arg_scan_ptr points to the command, e.g., "RUN"
    ; We need to skip the command ("RUN") and the program name ("COPY.BIN")
    ; to get to the first real argument.

    ; Skip "RUN" to get to "COPY.BIN"
    jsr find_next_word

    ; Skip "COPY.BIN" to get to <source_file>
    jsr find_next_word
    ; Now arg_scan_ptr points to the source file argument
    lda arg_scan_ptr
    sta src_ptr
    lda arg_scan_ptr+1
    sta src_ptr+1

    ; Skip <source_file> to get to <destination_file>
    jsr find_next_word
    ; Now arg_scan_ptr points to the destination file argument
    lda arg_scan_ptr
    sta dst_ptr
    lda arg_scan_ptr+1
    sta dst_ptr+1

    ; -------------------------------------------------------------------------
    ; 2. Prepare arguments for Pico: "SRC\0DST" in our local ARG_BUFF
    ; -------------------------------------------------------------------------
    ldx #0  ; Index into ARG_BUFF
    ldy #0  ; Index into src_ptr string
@copy_src:
    lda (src_ptr), y
    beq @src_done
    cmp #' '
    beq @src_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_src
@src_done:
    lda #0
    sta ARG_BUFF, x ; Null terminate SRC
    inx

    ldy #0 ; Index into dst_ptr string
@copy_dst:
    lda (dst_ptr), y
    beq @dst_done
    cmp #' '
    beq @dst_done
    sta ARG_BUFF, x
    inx
    iny
    jmp @copy_dst
@dst_done:
    ; Total length is now in X.
    stx ARG_LEN

    ; -------------------------------------------------------------------------
    ; 3. Send Command to Pico
    ; -------------------------------------------------------------------------
    lda #CMD_FS_COPY
    sta CMD_ID
    jsr pico_send_request
    bcc @request_ok
    jmp @done

@request_ok:
    lda LAST_STATUS
    cmp #STATUS_OK
    beq @copy_ok
    jmp @done

@copy_ok:
    ; Success! Just return to the shell.

@done:
    ; Standard Exit: Restore registers and return
    pla
    tay
    pla
    tax
    pla
    plp
    clc              ; Return with carry clear
    rts

; ---------------------------------------------------------------------------
; find_next_word
; Advances arg_scan_ptr past the current word and any subsequent spaces
; to point to the start of the next word.
; Clobbers A, Y
; ---------------------------------------------------------------------------
find_next_word:
    ldy #0
@find_space:
    lda (arg_scan_ptr), y
    beq @found_null     ; Handle null terminator
    cmp #' '
    beq @skip_spaces
    iny
    jmp @find_space
@skip_spaces:
    iny
    lda (arg_scan_ptr), y
    beq @found_null     ; Handle null after spaces
    cmp #' '
    beq @skip_spaces
    ; Found start of next word. Update pointer.
    tya
    clc
    adc arg_scan_ptr
    sta arg_scan_ptr
    bcc @done
    inc arg_scan_ptr+1
@done:
    rts

@found_null:
    ; Update pointer to the null so subsequent calls stay there
    tya
    clc
    adc arg_scan_ptr
    sta arg_scan_ptr
    bcc @done
    inc arg_scan_ptr+1
    rts
