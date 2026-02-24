; transient.inc - shared definitions for all transient commands

; Zero-page / BSS
        .segment "BSS"

; 32-byte response buffer for transient commands
RESP_BUFF:      .res 32

; Memory-mapped server communication
        .segment "CODE"
SERVER_CMD:     .byte $00      ; write command to server
SERVER_STATUS:  .byte $00      ; read status from server
