; -----------------------------------------------------------------------------
; BENCH.S - System Benchmark Utility (External Command)
; -----------------------------------------------------------------------------
; Description:
;   Measures data transfer throughput from Pico to 6502.
;   Acts as a standalone binary that can be loaded via BLOAD/BRUN.
;
; Architecture:
;   - Load Address: $4000 (Default)
;   - Header:       2 bytes (Load Address) for DOS compatibility
;   - Dependencies: Statically links pico_lib.s for Phase 1
; -----------------------------------------------------------------------------

.include "pico_lib.s"   ; Include the driver (Phase 1: Self-contained binary)

; -----------------------------------------------------------------------------
; CONFIGURATION
; -----------------------------------------------------------------------------
LOAD_ADDR   = $4000     ; Target load address in RAM
CHUNK_SIZE  = 256       ; Bytes to read per burst (Max 65535)
ITERATIONS  = 16        ; Number of chunks to read (Total = 4 KB)

; -----------------------------------------------------------------------------
; BINARY HEADER (Required for BRUN)
; -----------------------------------------------------------------------------
; This ensures the first 2 bytes of the file are the load address.
.segment "HEADER"
    .word   Main

; -----------------------------------------------------------------------------
; MAIN ENTRY POINT
; -----------------------------------------------------------------------------
.segment "CODE"
.org LOAD_ADDR

Main:
    ; 1. Print Banner
    ldx #<MsgStart
    ldy #>MsgStart
    jsr PICO_PRINT_STR

    ; 2. Open Benchmark File
    ; We attempt to open "BENCH.DAT". If it doesn't exist, we error out.
    ldx #<CmdOpen
    ldy #>CmdOpen
    lda #CmdOpenEnd - CmdOpen
    jsr PICO_SEND_CMD

    ; Check Open Status
    jsr PICO_READ_RESP
    cmp #0              ; Status 0 = OK
    beq FileOpened

    ; Error: File Not Found
    ldx #<MsgError
    ldy #>MsgError
    jsr PICO_PRINT_STR
    rts                 ; Exit to monitor/shell

FileOpened:
    ; The Handle is returned in the response payload.
    ; Response format: [STATUS] [LEN_LO] [LEN_HI] [HANDLE] [...]
    ; We must extract the handle and patch our READ command template.
    ; The response data from PICO_READ_RESP is in the library's RESP_BUF.
    lda RESP_BUF+3      ; Load the handle (4th byte of response payload)
    sta FileHandle      ; Save for later (CLOSE)
    sta CmdRead+2       ; Patch the handle byte in our read command template

    ldx #<MsgRun
    ldy #>MsgRun
    jsr PICO_PRINT_STR

    ; 3. Benchmark Loop
    ; We will read CHUNK_SIZE bytes, ITERATIONS times.
    lda #ITERATIONS
    sta LoopCount

BenchLoop:
    ; Send READ Command
    ldx #<CmdRead
    ldy #>CmdRead
    lda #CmdReadEnd - CmdRead
    jsr PICO_SEND_CMD

    ; Receive Burst Data
    ; This is the critical section being measured.
    jsr PICO_READ_RESP

    dec LoopCount
    bne BenchLoop

    ; 4. Done
    ldx #<MsgDone
    ldy #>MsgDone
    jsr PICO_PRINT_STR

    ; 5. Close the file to release resources on the Pico
    lda FileHandle
    sta CmdClose+2      ; Patch the handle into the close command template
    ldx #<CmdClose
    ldy #>CmdClose
    lda #CmdCloseEnd - CmdClose
    jsr PICO_SEND_CMD
    ; We don't wait for a response on CLOSE for this simple bench utility

    rts                 ; Return to caller

; -----------------------------------------------------------------------------
; DATA & BUFFERS
; -----------------------------------------------------------------------------
LoopCount:  .res 1
FileHandle: .res 1

MsgStart:   .asciiz "BENCHMARK: READING 4KB..."
MsgRun:     .asciiz "RUNNING..."
MsgError:   .asciiz "ERR: BENCH.DAT MISSING."
MsgDone:    .asciiz "DONE."

; Command: OPEN "BENCH.DAT"
CmdOpen:
    .byte $12           ; CMD_FS_OPEN
    .byte 9             ; Arg Len
    .asciiz "BENCH.DAT"
CmdOpenEnd:

; Command: CLOSE (Handle ?)
CmdClose:
    .byte $1C           ; CMD_FS_CLOSE
    .byte 1             ; Arg Len
    .byte 0             ; Handle ID (placeholder)
CmdCloseEnd:

; Command Template: READ (Handle ?, 256 Bytes)
; Note: The handle byte is patched at runtime after opening the file.
CmdRead:
    .byte $13           ; CMD_FS_READ
    .byte 3             ; Arg Len
    .byte 0             ; Handle ID (placeholder)
    .word CHUNK_SIZE    ; Length to read
CmdReadEnd: