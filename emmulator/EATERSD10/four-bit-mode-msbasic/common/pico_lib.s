; pico_lib.s - Driver for Raspberry Pi Pico W Smart Peripheral
; Updated to match the "Mode C" handshake from universal.s (no timeouts,
; CA2 toggled for every byte, defensive reads).

.include "common/pico_def.inc"

.export pico_init, pico_send_request, pico_read_bytes, send_byte, read_byte
.export CMD_ID, ARG_LEN, ARG_BUFF, LAST_STATUS, RESP_LEN, RESP_BUFF, TEMP_LEN
.export PCR_CA2_LOW, PCR_CA2_HIGH

; PCR Constants for Manual Handshake (Matches UNIVERSAL.S)
PCR_CA2_LOW  = $CC      ; CA2 Output Low (Idle)
PCR_CA2_HIGH = $CE      ; CA2 Output High (Data Ready / Ready to Receive)
IFR_CA1_BIT  = $02      ; Bit 1 is CA1 interrupt flag

.segment "BSS"
CMD_ID:         .res 1
ARG_LEN:        .res 1
ARG_BUFF:       .res 256
LAST_STATUS:    .res 1
RESP_LEN:       .res 2
RESP_BUFF:      .res 1024
TEMP_LEN:       .res 2

.segment "CODE"

; ---------------------------------------------------------------------------
; pico_init
; Initialize the VIA for communication with the Pico
; ---------------------------------------------------------------------------
pico_init:
    ; Disable VIA interrupts (we will poll)
    lda #$7F
    sta VIA_IER

    ; Set Port A to Output (Default state for sending commands)
    lda #$FF
    sta VIA_DDRA

    ; Configure PCR for Manual Mode (Matches UNIVERSAL.S)
    ; CA1: Negative Active Edge
    ; CA2: Manual Output Low (Idle)
    lda #PCR_CA2_LOW
    sta VIA_PCR

    ; Clear any pending CA1 interrupt
    lda VIA_PORTA       ; dummy read
    lda VIA_IFR
    sta VIA_IFR         ; write to clear (if supported)

    rts

; ---------------------------------------------------------------------------
; pico_send_request
; Sends CMD_ID and ARG_LEN to Pico, then reads the response.
; ---------------------------------------------------------------------------
pico_send_request:
    ; --- Step 1: Send Command ID ---
    lda CMD_ID
    bne @cmd_ok
    ; Invalid ID
    lda #PCR_CA2_LOW
    sta VIA_PCR
    lda #$FF
    sta VIA_DDRA
    sec
    rts
@cmd_ok:
    lda #$FF            ; Ensure Port A is Output
    sta VIA_DDRA
    
    lda CMD_ID
    jsr send_byte
    
    lda #0
    sta CMD_ID          ; prevent accidental re‑entry

    ; --- Step 2: Send Argument Length ---
    lda ARG_LEN
    jsr send_byte

    ; --- Step 3: Send Arguments (if any) ---
    ldy ARG_LEN
    beq @skip_args
    ldx #0
@arg_loop:
    lda ARG_BUFF, x
    jsr send_byte
    inx
    dey
    bne @arg_loop
@skip_args:

    ; --- Step 4: Switch to Receive Mode ---
    lda #$00
    sta VIA_DDRA        ; Port A = Input

    ; --- Step 5: Read Response Header (byte by byte) ---
    jsr read_byte
    sta LAST_STATUS

    jsr read_byte
    sta RESP_LEN

    jsr read_byte
    sta RESP_LEN+1

    ; --- Safety Check: Prevent Buffer Overflow ---
    lda RESP_LEN+1
    cmp #4
    bcc @len_ok
    bne @len_bad
    lda RESP_LEN
    cmp #1
    bcs @len_bad
@len_ok:
    ; --- Step 6: Read Payload (if any) ---
    lda RESP_LEN
    ora RESP_LEN+1
    beq @done
    jsr pico_read_bytes

@done:
    ; Restore Port A to Output for next command
    lda #$FF
    sta VIA_DDRA
    clc
    rts

@len_bad:
    ; On buffer overflow, abort (CA2 is already low after last read_byte)
    lda #$FF
    sta VIA_DDRA
    sec
    rts

; ---------------------------------------------------------------------------
; send_byte
; Sends the byte in A to the Pico using Mode C handshake (no timeout).
; ---------------------------------------------------------------------------
send_byte:
    sta VIA_PORTA       ; 1. Put data on bus

    lda #PCR_CA2_HIGH
    sta VIA_PCR         ; 2. Signal Ready (CA2 High)

@wait_ack:
    lda VIA_IFR
    and #IFR_CA1_BIT    ; Wait for CA1 Low (Ack)
    beq @wait_ack

    ; ACK received
    lda VIA_PORTA       ; Clear interrupt flag (dummy read)
    lda VIA_IFR         ; Defensive read

    lda #PCR_CA2_LOW
    sta VIA_PCR         ; 4. Drop Ready signal (CA2 Low)

    lda VIA_PORTA       ; Defensive clear (remove spurious IRQ)
    rts

; ---------------------------------------------------------------------------
; read_byte
; Reads a byte from the Pico using Mode C handshake (no timeout).
; Returns byte in A.
; ---------------------------------------------------------------------------
read_byte:
    lda #PCR_CA2_HIGH
    sta VIA_PCR         ; 1. Signal Ready to Receive (CA2 High)

@wait_data:
    lda VIA_IFR
    and #IFR_CA1_BIT    ; Wait for CA1 Low (Data Valid)
    beq @wait_data

    lda VIA_PORTA       ; 3. Read Data (clears interrupt flag)
    pha                 ; save it

    lda VIA_IFR         ; Defensive read

    lda #PCR_CA2_LOW
    sta VIA_PCR         ; 4. Signal ACK (CA2 Low)

    lda VIA_PORTA       ; Defensive clear
    pla                 ; restore data
    rts

; ---------------------------------------------------------------------------
; pico_read_bytes
; Reads RESP_LEN bytes from Pico into RESP_BUFF.
; Assumes RESP_LEN > 0.
; ---------------------------------------------------------------------------
pico_read_bytes:
    ; Copy length to TEMP_LEN so we can modify it
    lda RESP_LEN
    sta TEMP_LEN
    lda RESP_LEN+1
    sta TEMP_LEN+1

    ldx #0
@loop:
    jsr read_byte
    sta RESP_BUFF, x
    inx

    ; Decrement TEMP_LEN
    lda TEMP_LEN
    bne @dec_low
    dec TEMP_LEN+1
@dec_low:
    dec TEMP_LEN

    lda TEMP_LEN
    ora TEMP_LEN+1
    bne @loop
    rts