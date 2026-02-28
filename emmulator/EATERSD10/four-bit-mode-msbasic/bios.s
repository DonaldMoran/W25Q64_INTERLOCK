.setcpu "65c02"
.debuginfo

.zeropage
                .org ZP_START0
.export READ_PTR, WRITE_PTR
READ_PTR:       .res 1
WRITE_PTR:      .res 1

; MSBASIC Zero Page Variables
ZP_PTR      = $50
ptr_temp    = $56

.segment "INPUT_BUFFER"
.export INPUT_BUFFER
INPUT_BUFFER:   .res $100

.include "common/pico_def.inc"


.segment "BIOS"

ACIA_DATA       = $5000
ACIA_STATUS     = $5001
ACIA_CMD        = $5002
ACIA_CTRL       = $5003
SKIP_MOUNT_FLAG = $02   ; Flag set by Emulator if user skipped sync
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
        
        ;LDA #$1F        ; 8-N-1, 19200 bps
        ;STA ACIA_CTRL
        ;LDY #$8B
        ;STY ACIA_CMD    ; No parity, no echo, rx interrupts DISABLED.

        ; Initialize Krusader variables (since we skip MAIN)
        LDA #$03
        STA z:CODEH
        LDA #$20
        STA z:SRCSTH
        LDA #$7C
        STA z:TABLEH

        jsr pico_init
        
        ; Check if Emulator requested skip (Flag at $02)
        lda SKIP_MOUNT_FLAG
        bne @mount_skipped_by_user
        
        ; Attempt Mount
        lda #CMD_FS_MOUNT
        sta CMD_ID
        lda #0
        sta ARG_LEN
        jsr pico_send_request
        
        ; After mount attempt, go to the shell
        JMP DDOS_START

@mount_skipped_by_user:
        ; Print warning message
        ldy #0
@print_warning:
        lda msg_skip_mount, y
        beq @warning_done
        jsr MONCOUT
        iny
        jmp @print_warning
@warning_done:
        JMP RESET   

msg_skip_mount: .byte $0D, $0A, "Mount skipped. Shell requires a mounted chip.", $0D, $0A, 0

LOAD:
    jsr PARSE_FILENAME_LITERAL
    bcs @cancel
    jsr PICO_LOAD
@cancel:
    rts

SAVE:
    jsr PARSE_FILENAME_LITERAL
    bcs @cancel
    jsr PICO_SAVE
@cancel:
    rts

; ---------------------------------------------------------------------------
; PARSE_FILENAME_LITERAL
; Parses a string literal "FILENAME" from BASIC text stream.
; Stores in INPUT_BUFFER.
; ---------------------------------------------------------------------------
PARSE_FILENAME_LITERAL:
    ; Skip spaces
    ldy #0
@skip_space:
    lda (TXTPTR),y
    cmp #$20
    bne @check_quote
    inc TXTPTR
    bne @skip_space
    inc TXTPTR+1
    jmp @skip_space
@check_quote:
    cmp #'"'
    bne @error
    
    inc TXTPTR
    bne :+
    inc TXTPTR+1
:
    ldx #0
@loop:
    lda (TXTPTR),y
    cmp #'"'
    beq @done
    cmp #0
    beq @error
    sta INPUT_BUFFER,x
    inx
    inc TXTPTR
    bne :+
    inc TXTPTR+1
:
    jmp @loop
@done:
    lda #0
    sta INPUT_BUFFER,x
    
    ; Skip closing quote
    inc TXTPTR
    bne :+
    inc TXTPTR+1
:
    clc
    rts
@error:
    sec
    rts

; ---------------------------------------------------------------------------
; PICO_SAVE
; Saves BASIC program from TXTTAB to VARTAB
; ---------------------------------------------------------------------------
PICO_SAVE:
    ; Save ptr_temp as it is modified during save and BASIC might rely on it
    lda ptr_temp
    pha
    lda ptr_temp+1
    pha

    ; Calculate Length = VARTAB - TXTTAB
    sec
    lda VARTAB
    sbc TXTTAB
    sta savemem_len
    lda VARTAB+1
    sbc TXTTAB+1
    sta savemem_len+1

    ; Prepare Command
    lda #CMD_FS_SAVEMEM
    sta CMD_ID

    ; Copy Filename to ARG_BUFF
    ldx #0
@copy_name:
    lda INPUT_BUFFER, x
    sta ARG_BUFF, x
    beq @name_done
    inx
    jmp @copy_name
@name_done:
    ; Append Length (Little Endian)
    inx
    lda savemem_len
    sta ARG_BUFF, x
    inx
    lda savemem_len+1
    sta ARG_BUFF, x
    inx
    stx ARG_LEN

    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    bne @error_restore

    ; Stream Data
    lda TXTTAB
    sta ptr_temp
    lda TXTTAB+1
    sta ptr_temp+1
    
    lda savemem_len
    sta savemem_cnt
    lda savemem_len+1
    sta savemem_cnt+1

    jsr common_write_stream_from_mem
    
    ; Read Final Status
    lda #$00
    sta DDRA
    jsr read_byte
    sta LAST_STATUS
    jsr read_byte ; len_lo
    jsr read_byte ; len_hi
    lda #$FF
    sta DDRA

@error_restore:
    pla
    sta ptr_temp+1
    pla
    sta ptr_temp
@error:
    rts

; ---------------------------------------------------------------------------
; PICO_LOAD
; Loads BASIC program to TXTTAB
; ---------------------------------------------------------------------------
PICO_LOAD:
    lda #CMD_FS_LOADMEM
    sta CMD_ID
    
    ldx #0
@copy_name:
    lda INPUT_BUFFER, x
    sta ARG_BUFF, x
    beq @name_done
    inx
    jmp @copy_name
@name_done:
    inx
    stx ARG_LEN
    
    ; Send command manually to handle streaming response
    lda #$FF
    sta DDRA
    lda CMD_ID
    jsr send_byte
    lda ARG_LEN
    jsr send_byte
    ldx #0
@send_args:
    lda ARG_BUFF, x
    jsr send_byte
    inx
    cpx ARG_LEN
    bne @send_args
    
    lda #$00
    sta DDRA
    
    jsr read_byte ; Status
    cmp #STATUS_OK
    beq @ok
    ; Error
    jsr read_byte
    jsr read_byte
    lda #$FF
    sta DDRA
    rts
@ok:
    jsr read_byte ; Len Lo
    sta savemem_len
    jsr read_byte ; Len Hi
    sta savemem_len+1
    
    ; Stream to TXTTAB
    lda TXTTAB
    sta ptr_temp
    lda TXTTAB+1
    sta ptr_temp+1
    
    lda savemem_len
    sta savemem_cnt
    lda savemem_len+1
    sta savemem_cnt+1
    
    jsr common_read_stream_to_mem
    
    ; Update Pointers
    clc
    lda TXTTAB
    adc savemem_len
    sta VARTAB
    sta ARYTAB
    sta STREND
    lda TXTTAB+1
    adc savemem_len+1
    sta VARTAB+1
    sta ARYTAB+1
    sta STREND+1
    
    lda #$FF
    sta DDRA
    rts

; ---------------------------------------------------------------------------
; KRUSADER EXTENSIONS
; ---------------------------------------------------------------------------

; Helper: Parse filename from Krusader ARGS+2 into ARG_BUFF
; Returns Y = length (including null)
PARSE_KRU_FILENAME:
    ldx #2          ; Skip command char and space
    ldy #0
@loop:
    lda z:ARGS, x
    beq @done
    cmp #$0D        ; CR
    beq @done
    sta ARG_BUFF, y
    inx
    iny
    jmp @loop
@done:
    lda #0
    sta ARG_BUFF, y
    iny
    sty ARG_LEN
    rts

EXT_SAVE_SRC:
    jsr PARSE_KRU_FILENAME
    
    ; Calculate Source Size
    ; Call TOEND to ensure pointers are at the end
    jsr TOEND
    
    ; Length = CURLNL/H - SRCSTL/H
    sec
    lda z:CURLNL
    sbc z:SRCSTL
    sta savemem_len
    lda z:CURLNH
    sbc z:SRCSTH
    sta savemem_len+1
    
    ; Prepare Command
    lda #CMD_FS_SAVEMEM
    sta CMD_ID
    
    ; Append Length to ARG_BUFF (after filename)
    ldx ARG_LEN
    lda savemem_len
    sta ARG_BUFF, x
    inx
    lda savemem_len+1
    sta ARG_BUFF, x
    inx
    stx ARG_LEN
    
    jsr pico_send_request
    
    lda LAST_STATUS
    cmp #STATUS_OK
    bne @error
    
    ; Stream Data from SRCSTL
    lda z:SRCSTL
    sta ptr_temp
    lda z:SRCSTH
    sta ptr_temp+1
    
    lda savemem_len
    sta savemem_cnt
    lda savemem_len+1
    sta savemem_cnt+1
    
    jsr common_write_stream_from_mem
    
    ; Read Final Status
    lda #$00
    sta DDRA
    jsr read_byte
    sta LAST_STATUS
    jsr read_byte ; len_lo
    jsr read_byte ; len_hi
    lda #$FF
    sta DDRA
@error:
    rts

EXT_LOAD_SRC:
    jsr PARSE_KRU_FILENAME
    
    ; Load to SRCSTL
    lda z:SRCSTL
    sta ptr_temp
    lda z:SRCSTH
    sta ptr_temp+1
    
    jsr PICO_LOAD_RAW ; Reuse logic but for specific address
    
    ; Re-index Krusader lines
    jsr TOEND
    rts

; Helper to load to ptr_temp without parsing filename from BASIC stream
PICO_LOAD_RAW:
    lda #CMD_FS_LOADMEM
    sta CMD_ID
    
    ; ARG_BUFF already populated by PARSE_KRU_FILENAME
    
    ; Send command manually
    lda #$FF
    sta DDRA
    lda CMD_ID
    jsr send_byte
    lda ARG_LEN
    jsr send_byte
    ldx #0
@send_args:
    lda ARG_BUFF, x
    jsr send_byte
    inx
    cpx ARG_LEN
    bne @send_args
    
    lda #$00
    sta DDRA
    
    jsr read_byte ; Status
    cmp #STATUS_OK
    beq @ok
    ; Error
    jsr read_byte
    jsr read_byte
    lda #$FF
    sta DDRA
    rts
@ok:
    jsr read_byte ; Len Lo
    sta savemem_len
    jsr read_byte ; Len Hi
    sta savemem_len+1
    
    ; Stream to ptr_temp (already set by caller)
    lda savemem_len
    sta savemem_cnt
    lda savemem_len+1
    sta savemem_cnt+1
    
    jsr common_read_stream_to_mem
    
    lda #$FF
    sta DDRA
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
    
