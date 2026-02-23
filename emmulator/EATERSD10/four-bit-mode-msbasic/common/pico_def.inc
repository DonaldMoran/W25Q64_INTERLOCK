; pico_def.inc - Definitions for 6502 Smart Peripheral

.ifndef PICO_DEF_INC
PICO_DEF_INC = 1

; ---------------------------------------------------------------------------
; 6522 VIA Hardware Definitions (Base $6000)
; ---------------------------------------------------------------------------
VIA_BASE    = $6000
VIA_PORTB   = VIA_BASE + $00
VIA_PORTA   = VIA_BASE + $01
VIA_DDRB    = VIA_BASE + $02
VIA_DDRA    = VIA_BASE + $03
VIA_PCR     = VIA_BASE + $0C
VIA_IFR     = VIA_BASE + $0D
VIA_IER     = VIA_BASE + $0E

; ---------------------------------------------------------------------------
; Command IDs
; ---------------------------------------------------------------------------
CMD_SYS_PING    = $01
CMD_SYS_VER     = $02
CMD_SYS_STATUS  = $03
CMD_SYS_RESET   = $0F

CMD_FS_MOUNT    = $10
CMD_FS_LIST     = $11
CMD_FS_OPEN     = $12
CMD_FS_READ     = $13
CMD_FS_WRITE    = $14
CMD_FS_FORMAT   = $15
CMD_FS_REMOVE   = $16
CMD_FS_RENAME   = $17
CMD_FS_MKDIR    = $18
CMD_FS_COPY     = $19
CMD_FS_TOUCH    = $1A
CMD_FS_APPEND   = $1B
CMD_FS_CLOSE    = $1C
CMD_FS_SEEK     = $1D
CMD_FS_TELL     = $1E
CMD_FS_STAT     = $1F
CMD_FS_SIZE     = $20
CMD_FS_SYNC     = $21
CMD_FS_UNMOUNT  = $22
CMD_FS_SAVEMEM  = $23
CMD_FS_LOADMEM  = $24

CMD_NET_STATUS  = $30
CMD_NET_CONNECT    = $31
CMD_NET_GET_IP     = $32
CMD_NET_DISCONNECT = $33
CMD_NET_HTTP_GET   = $34
CMD_NET_HTTP_POST  = $35
CMD_NET_TIME       = $36
CMD_DOWNLOAD_SIMPLE = $37

; ---------------------------------------------------------------------------
; Status Codes
; ---------------------------------------------------------------------------
STATUS_OK       = $00
STATUS_ERR      = $FF
STATUS_BUSY     = $01
STATUS_NO_FILE  = $02
STATUS_EXIST    = $03

.endif ; PICO_DEF_INC