#ifndef CMD_DEFS_H
#define CMD_DEFS_H

// --- SYSTEM COMMANDS (0x00 - 0x0F) ---
#define CMD_PING        0x01  // Args: None. Returns: "PONG"
#define CMD_GET_VERSION 0x02  // Args: None. Returns: Version String
#define CMD_SYS_STATUS  0x03  // Args: None. Returns: Status String
#define CMD_SYS_SET_TIME 0x04 // Args: "YYYY-MM-DD HH:MM:SS"
#define CMD_SYS_GET_TIME 0x05 // Args: None. Returns: Time String
#define CMD_RESET       0x0F  // Args: None. Resets Pico

// --- FILESYSTEM COMMANDS (0x10 - 0x2F) ---
#define CMD_FS_MOUNT    0x10  // Args: None. Mounts the W25Q64
#define CMD_FS_LIST     0x11  // Args: [Path]. Aliases: DIR, LS
#define CMD_FS_OPEN     0x12  // Args: [Filename]. Returns: File Handle / Size
#define CMD_FS_READ     0x13  // Args: [Handle][Len]. Returns: Bytes
#define CMD_FS_WRITE    0x14  // Args: [Handle][Data...]. Returns: Status
#define CMD_FS_FORMAT   0x15  // Args: None. Formats the disk.
#define CMD_FS_REMOVE   0x16  // Args: [Path]. Aliases: DEL, RM, RMDIR
#define CMD_FS_RENAME   0x17  // Args: [Old]\0[New]. Aliases: REN, MV
#define CMD_FS_MKDIR    0x18  // Args: [Path]. Aliases: MD, MKDIR
#define CMD_FS_COPY     0x19  // Args: [Src]\0[Dst]. Aliases: COPY, CP
#define CMD_FS_TOUCH    0x1A  // Args: [Path]. Aliases: TOUCH
#define CMD_FS_APPEND   0x1B  // Args: [Path]\0[Data]. Aliases: APPEND, >>
#define CMD_FS_CLOSE    0x1C  // Args: [Handle]. Returns: Status
#define CMD_FS_SEEK     0x1D  // Args: [Handle][Offset(4)][Whence]. Returns: NewPos
#define CMD_FS_TELL     0x1E  // Args: [Handle]. Returns: CurrentPos
#define CMD_FS_STAT     0x1F  // Args: [Path]. Returns: [Type][Size(4)]
#define CMD_FS_SIZE     0x20  // Args: None. Returns: [BlockSize(4)][BlockCount(4)]
#define CMD_FS_SYNC     0x21  // Args: [Handle]. Returns: Status
#define CMD_FS_UNMOUNT  0x22  // Args: None. Returns: Status

// Add with other filesystem commands (around line 30)
#define CMD_FS_SAVEMEM  0x23  // Args: [Filename]\0[Len(2)]. Streams memory bytes from 6502
#define CMD_FS_LOADMEM  0x24  // Args: [Filename]. Returns: [Status][Len(2)][Data...]

// --- NETWORK COMMANDS (0x30 - 0x4F) ---
#define CMD_NET_STATUS     0x30  // Args: None. Returns: Status (0=Down, 1=Up)
#define CMD_NET_CONNECT    0x31  // Args: [SSID]\0[PASS]. Returns: Status
#define CMD_NET_GET_IP     0x32  // Args: None. Returns: IP String
#define CMD_NET_DISCONNECT 0x33  // Args: None. Returns: Status
#define CMD_NET_HTTP_GET   0x34  // Args: [IP]\0[Port]\0[Src]\0[Dst]. Returns: Status
#define CMD_NET_HTTP_POST  0x35  // Args: [IP]\0[Port]\0[Src]\0[Dst]. Returns: Status
#define CMD_NET_TIME       0x36  // Args: None. Returns: Time String
#define CMD_DOWNLOAD_SIMPLE 0x37  // Args: [RemotePath]\0[LocalPath]. Returns: File Content (raw)

// --- STATUS CODES ---
#define STATUS_OK       0x00
#define STATUS_ERR      0xFF
#define STATUS_BUSY     0x01
#define STATUS_NO_FILE  0x02
#define STATUS_EXIST    0x03

#endif