;
; ANSI Clear Screen Program for 65C02
; Outputs ESC[2J to clear the screen
; Assumes a serial terminal or ANSI-compatible display
;

; Zero page variables
SCRATCH = $58          ; Temporary storage

; Memory-mapped I/O location for serial output
; Change this address to match your hardware
IO_PORT = $5000

; ---------------------------------------------------------------------------
; HEADER - MUST be first (2-byte load address for RUN command)
; ---------------------------------------------------------------------------
.segment "HEADER"
    .word $0800        ; Load at $0800 (little-endian)

; ---------------------------------------------------------------------------
; CODE - Program starts here at $0800
; ---------------------------------------------------------------------------
.segment "CODE"

RESET:
   
    ; Clear the screen with ANSI sequence
    JSR CLEAR_SCREEN
    
    ; Return to the monitor
    RTS 
;-----------------------------------------------------------
; CLEAR_SCREEN - Output ANSI escape sequence to clear screen
; Destroys: A
;-----------------------------------------------------------
CLEAR_SCREEN:
    ; Start with ESC character
    LDA #$1B           ; ESC character
    JSR OUT_CHAR
    
    ; Send the '[' character
    LDA #'['
    JSR OUT_CHAR
    
    ; Send the '2' character
    LDA #'2'
    JSR OUT_CHAR
    
    ; Send the 'J' character
    LDA #'J'
    JSR OUT_CHAR
    
    ; Optional: Move cursor to home position (1;1)
    ; Uncomment if you want cursor at top-left
    LDA #$1B
    JSR OUT_CHAR
    LDA #'['
    JSR OUT_CHAR
    LDA #'1'
    JSR OUT_CHAR
    LDA #';'
    JSR OUT_CHAR
    LDA #'1'
    JSR OUT_CHAR
    LDA #'H'
    JSR OUT_CHAR
    
    RTS

;-----------------------------------------------------------
; OUT_CHAR - Output character to I/O port
; Input: A = character to output
; Destroys: None (preserves A, X, Y)
;-----------------------------------------------------------
OUT_CHAR:
    PHA                ; Save accumulator
OUT_WAIT:
    ; Optional: Add hardware handshaking here if needed
    ; For example, check a status register for ready
    
    ; Output character to I/O port
    STA IO_PORT
    
    ; Optional: Add delay for slow serial implementations
    ; JSR DELAY
    
    PLA                ; Restore accumulator
    RTS

;-----------------------------------------------------------
; DELAY - Simple delay loop (optional)
; Destroys: X, Y
;-----------------------------------------------------------
DELAY:
    LDX #$FF
DELAY_LOOP1:
    LDY #$FF
DELAY_LOOP2:
    DEY
    BNE DELAY_LOOP2
    DEX
    BNE DELAY_LOOP1
    RTS
