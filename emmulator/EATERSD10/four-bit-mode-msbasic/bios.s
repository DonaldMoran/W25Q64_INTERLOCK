.setcpu "65c02"
.debuginfo

.zeropage
                .org ZP_START0
.export READ_PTR, WRITE_PTR
READ_PTR:       .res 1
WRITE_PTR:      .res 1

.segment "INPUT_BUFFER"
.export INPUT_BUFFER
INPUT_BUFFER:   .res $100


.segment "BIOS"

ACIA_DATA       = $5000
ACIA_STATUS     = $5001
ACIA_CMD        = $5002
ACIA_CTRL       = $5003
PORTA           = $6001
DDRA            = $6003
T1LL        = $6006
T1LH        = $6007
IFR         = $600D

START:
        LDX #$FF    ; Load X with $FF (top of stack)
        TXS         ; Transfer X to Stack Pointer
        ;~ LDA     #$1F            ; 8-N-1, 19200 bps
        ;~ STA     ACIA_CTRL
        ;~ LDA     #$89            ; No parity, no echo, rx interrupts.
        ;~ STA     ACIA_CMD  
        LDA #$1F        ; 8-N-1, 19200 bps
        STA ACIA_CTRL
        LDY #$8B
        STY ACIA_CMD
        JMP     RESET        

LOAD:
                rts

SAVE:
                rts

MON:
            LDA #$0D
            JSR MONCOUT
            LDA #$0A
            JSR MONCOUT 
            JMP $FF00
            
;ISCNTC:
;           rts

; Input a character from the serial interface.
; On return, carry flag indicates whether a key was pressed
; If a key was pressed, the key value will be in the A register
;
; Modifies: flags, A
.export MONRDKEY
MONRDKEY:
;CHRIN:
;                 phx
;                jsr     BUFFER_SIZE
;                 beq     @no_keypressed
;                jsr     READ_BUFFER
;                 jsr     CHROUT                  ; echo
;                 pha
;                jsr     BUFFER_SIZE
;                cmp     #$B0
;                bcs     @mostly_full
;                lda     #$fe
;            	sta	ACIA_CMD            ;Re-enable transmitter
;            	;lda                    #$00
;            	;sta                    PORTA
;@mostly_full:
;                pla
;                plx
;                sec
;                rts
;@no_keypressed:
;                plx
;                clc
;                rts
CHRIN:									      
  LDA ACIA_DATA	
  beq @no_keypressed	
  jsr CHROUT								  ;echo
  sec
  rts
@no_keypressed:
  clc
  rts

; Output a character (from the A register) to the serial interface.
;
; Modifies: flags
.export MONCOUT
MONCOUT:
CHROUT:
                ;~ pha
                sta     ACIA_DATA
                ;~ lda     #$FF
;~ @txdelay:       dec
                ;~ bne     @txdelay
                ;~ pla
                rts

; Initialize the circular input buffer
; Modifies: flags, A
.export INIT_BUFFER
INIT_BUFFER:
                sta READ_PTR
                sta WRITE_PTR
                LDA #$01
                STA DDRA
                LDA #$00
                sta PORTA
                rts

; Write a character (from the A register) to the circular input buffer
; Modifies: flags, X
WRITE_BUFFER:
                ldx WRITE_PTR
                sta INPUT_BUFFER,x
                inc WRITE_PTR
                rts

; Read a character from the circular input buffer and put it in the A register
; Modifies: flags, A, X
.export READ_BUFFER
READ_BUFFER:
                ldx READ_PTR
                lda INPUT_BUFFER,x
                inc READ_PTR
                rts

; Return (in A) the number of unread bytes in the circular input buffer
; Modifies: flags, A
.export BUFFER_SIZE
BUFFER_SIZE:
                lda WRITE_PTR
                sec
                sbc READ_PTR
                rts


; Interrupt request handler
;  What is Good
;
;   * Register Preservation: You correctly save and restore the A and X registers using pha/phx and pla/plx. This is
;     critical for preventing interrupts from corrupting your main program.
;   * Prioritized Polling: The routine checks for different interrupt sources (ACIA first, then VIA) in a clear,
;     prioritized order.
;   * Prevents Interference: My previous change, which you've kept, ensures that if a keyboard interrupt occurs, the
;     handler deals with it and exits immediately. This prevents keyboard handling from delaying the time-sensitive sound
;     generation routine.
;   * Circular Buffer: Your keyboard input routine uses a circular buffer, which is the proper way to handle serial input
;     to ensure characters aren't lost if the main program is busy.
;
;  Points for Consideration
;
;  These are not bugs, but rather areas you could make even more robust if you wanted to expand your system's capabilities
;   in the future:
;
;   1. More Specific Interrupt Checks: The code checks if any interrupt has occurred from the ACIA or VIA. It assumes a
;      VIA interrupt is always for sound, and an ACIA interrupt is always a new character. For a dedicated system this is
;      fine, but for more robustness, you could check the specific flags within the status registers (e.g., checking bit 6
;       of the VIA's IFR to be sure it was Timer 1).
;   2. Sound Generation Logic: As we discussed, the sound routine checks the state of PORTB to decide whether to load
;      SND1 or SND2. This is designed to create complex tones. However, the timer mode used (ACR = $C0) creates a simple
;      pulse train, which means the SND2 value is rarely used. The sound works, but this part of the code isn't quite
;      living up to its full potential. This is not an error, but just an interesting observation about the design.
;
;  In conclusion, you have a solid, working interrupt handler that is perfectly suited for its purpose. The points above
;  are simply food for thought if you ever decide to build on this routine.
IRQ_HANDLER:
                pha
                phx
                lda	ACIA_STATUS ; Ack interrupt
                bpl @not_full ; Skip UART handling if no UART interrut
                lda     ACIA_DATA
                jsr     WRITE_BUFFER
                jsr     BUFFER_SIZE
                cmp     #$F0
                ;bcc	@not_full
                bcc @irq_exit
                lda     #$01
                sta	ACIA_CMD    ;De-assert CTS to stop transmitter
                ;lda    #$01
                ;sta    PORTA	;De-assert CTS
                jmp @irq_exit
@not_full:
            lda IFR
            bpl @irq_exit ; No interrupt from 6522
            lda PORTB ; PB7 will be the current phase
            bmi @snd2 ; if PB7 (minus flag) is set, set timer to SND2
            ; otherwise set timer to SND1
            lda SND1+1
            sta T1LL
            lda SND1
            sta T1LH
            jmp @irq_exit
@snd2:
            lda SND2+1
            sta T1LL
            lda SND2
            sta T1LH                
@irq_exit:
                plx
                pla
                rti

.include "Krusader_1.3_65C02.asm"
.include "cmd_shell.s"
.include "common/pico_lib.s"

;~ .segment "RESETVEC"
                ;~ .word   $0F00           ; NMI vector
                ;~ .word   RESET           ; RESET vector
                ;~ .word   IRQ_HANDLER     ; IRQ vector
    
