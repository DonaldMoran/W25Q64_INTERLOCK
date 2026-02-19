.segment "CODE"
.ifdef EATER

;~ DDRB = $6002
;~ PORTB = $6000

BEEP:
  ; --- Parameter Parsing (from original sound.s) ---
  jsr FRMEVL  ; Evaluate first parameter (frequency)
  jsr MKINT   ; Convert to integer
  lda FAC+3   ; Get high byte of integer
  sta SND1    ; Store in SND1 (high byte)
  lda FAC+4   ; Get low byte of integer
  sta SND1+1  ; Store in SND1+1 (low byte)

  jsr CHKCOM  ; Check for comma
  jsr FRMEVL  ; Evaluate second parameter (duration)
  jsr MKINT   ; Convert to integer
  lda FAC+3   ; Get high byte of integer
  sta SND2    ; Store in SND2 (high byte)
  lda FAC+4   ; Get low byte of integer
  sta SND2+1  ; Store in SND2+1 (low byte)

  ; --- Bit-Bang Sound Generation ---
  ; Set PB7 as output
  LDA #%10000000
  STA DDRB

  ; Use SND2 (duration) as outer loop counter
  ; Use SND1 (frequency) as inner loop delay
  LDX SND2+1  ; Low byte of duration for outer loop (number of toggles)
  LDY SND2    ; High byte of duration for outer loop (if duration > 255)

duration_loop:
  ; Toggle PB7
  LDA #%10000000
  EOR PORTB
  STA PORTB

  ; Delay for frequency (controlled by SND1)
  PHA         ; Save A
  LDX SND1+1  ; Low byte of frequency for inner loop delay
  LDY SND1    ; High byte of frequency for inner loop delay (if frequency > 255)

freq_delay_loop:
  DEY
  BNE freq_delay_loop
  DEX
  BNE freq_delay_loop
  PLA         ; Restore A

  ; Decrement duration counter
  DEY         ; Decrement low byte of duration
  BNE duration_loop
  DEX         ; Decrement high byte of duration
  BNE duration_loop

  ; Turn pin off
  LDA #0
  STA PORTB

  RTS

.endif
