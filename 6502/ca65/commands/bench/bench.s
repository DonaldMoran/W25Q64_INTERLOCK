; -----------------------------------------------------------------------------
; BENCH.S - System Benchmark Utility (External Command)
; -----------------------------------------------------------------------------
; Description:
;   Measures data transfer throughput from Pico to 6502.
;   Acts as a standalone binary that can be loaded via BLOAD/BRUN.
;
; Architecture:
;   - Load Address: $0800
;   - Header:       2 bytes (Load Address) for DOS compatibility
;   - Dependencies: Statically links pico_lib.s for Phase 1
; -----------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; Explicitly declare external symbols from pico_lib.s
; ---------------------------------------------------------------------------
.import pico_send_request, send_byte, read_byte
.import pico_init  ; <-- ADD THIS LINE
.import CMD_ID, ARG_LEN, ARG_BUFF, LAST_STATUS, RESP_LEN, RESP_BUFF

; ---------------------------------------------------------------------------
; Include constants (optional - can use numeric values)
; ---------------------------------------------------------------------------
.include "../common/pico_def.inc"

; -----------------------------------------------------------------------------
; CONFIGURATION
; -----------------------------------------------------------------------------
LOAD_ADDR   = $0800     ; Target load address in RAM
CHUNK_SIZE  = 256       ; Bytes to read per burst (Max 65535)
ITERATIONS  = 16        ; Number of chunks to read (Total = 4 KB)

; Zero page pointers
print_ptr    = $5A
; bench/bench.s
; REMOVE this line if it exists:
; .include "../common/pico_lib.s"

; Rest of your code...
; -----------------------------------------------------------------------------
; BINARY HEADER (Required for BRUN)
; -----------------------------------------------------------------------------
;  This ensures the first 2 bytes of the file are the load address.
.segment "HEADER"
   .word   LOAD_ADDR

; -----------------------------------------------------------------------------
; MAIN ENTRY POINT
; -----------------------------------------------------------------------------
.segment "CODE"
Main:
    jsr pico_init

    ; 1. Print Banner
    ldx #<MsgStart
    ldy #>MsgStart
    jsr print_str

    ; 2. Open Benchmark File
    ; We attempt to open "BENCH.DAT". If it doesn't exist, we error out.
    lda #CMD_FS_OPEN
    sta CMD_ID
    
    ; Copy filename to ARG_BUFF
    ldx #0
@copy_name:
    lda Filename, x
    beq @done_name
    sta ARG_BUFF, x
    inx
    bne @copy_name
@done_name:
    stx ARG_LEN
    jsr pico_send_request

    ; Check Open Status
    lda LAST_STATUS
    cmp #STATUS_OK
    beq FileOpened

    ; Error: File Not Found
    ldx #<MsgError
    ldy #>MsgError
    jsr print_str
    rts                 ; Exit to monitor/shell

FileOpened:
    ; The Handle is returned in the response payload.
    ; Payload starts at RESP_BUFF[0]
    lda RESP_BUFF       ; Load the handle
    sta FileHandle      ; Save for later (CLOSE)

    ldx #<MsgRun
    ldy #>MsgRun
    jsr print_str

    ; 3. Benchmark Loop
    ; We will read CHUNK_SIZE bytes, ITERATIONS times.
    lda #ITERATIONS
    sta LoopCount

BenchLoop:
    ; Send READ Command
    lda #CMD_FS_READ
    sta CMD_ID
    
    ; Args: [Handle] [LenLO] [LenHI]
    lda FileHandle
    sta ARG_BUFF
    lda #<CHUNK_SIZE
    sta ARG_BUFF+1
    lda #>CHUNK_SIZE
    sta ARG_BUFF+2
    lda #3
    sta ARG_LEN

    jsr pico_send_request

    dec LoopCount
    bne BenchLoop

    ; 4. Done
    ldx #<MsgDone
    ldy #>MsgDone
    jsr print_str

    ; 5. Close the file to release resources on the Pico
    lda #CMD_FS_CLOSE
    sta CMD_ID
    lda FileHandle
    sta ARG_BUFF
    lda #1
    sta ARG_LEN
    jsr pico_send_request

    rts                 ; Return to caller

; -----------------------------------------------------------------------------
; UTILITIES
; -----------------------------------------------------------------------------
print_str:
    stx print_ptr
    sty print_ptr+1
    ldy #0
@loop:
    lda (print_ptr), y
    beq @exit
    jsr $FFEF ; OUTCH (Standard 6502 Monitor Output)
    iny
    bne @loop
@exit:
    rts

; -----------------------------------------------------------------------------
; DATA & BUFFERS
; -----------------------------------------------------------------------------
.segment "BSS"
LoopCount:  .res 1
FileHandle: .res 1

.segment "RODATA"
Filename:   .asciiz "BENCH.DAT"
MsgStart:   .asciiz "BENCHMARK: READING 4KB..."
MsgRun:     .asciiz "RUNNING..."
MsgError:   .asciiz "ERR: BENCH.DAT MISSING."
MsgDone:    .asciiz "DONE."
