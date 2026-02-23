# W25Q64_INTERLOCK

6502 ↔ Pico W interlocked filesystem interface

This document outlines the architecture, communication protocol, error handling, concurrency, memory management, configuration, flash memory usage, and transient command development for the W25Q64_INTERLOCK project.

---

## 1. Overall Architecture

The system comprises the following main components:

- **65C02 Computer:** Hosts a shell and initiates commands.
- **6522 VIA (Versatile Interface Adapter):** Provides a parallel interface for communication between the 65C02 and the Raspberry Pi Pico W.
- **Raspberry Pi Pico W:** Receives commands from the 6522, interacts with the W25Q64 flash memory, manages the LittleFS filesystem, and handles Wi-Fi connectivity.
- **W25Q64 Flash Memory:** Stores the LittleFS filesystem, providing persistent storage for files.
- **LittleFS:** A lightweight filesystem optimized for microcontrollers, managing file storage and retrieval on the W25Q64 flash memory.

The 65C02 computer issues commands, which are transmitted through the 6522 VIA to the Raspberry Pi Pico W. The Pico W interprets these commands, performs actions such as reading from or writing to the W25Q64 flash memory, and sends responses back to the 65C02 for display.

```text
       HOST PICO (Emulator)                     BRIDGE PICO (Pico W)
    +-----------------------+                 +-----------------------+
    |                       |                 |                       |
    | GP0  (PA0) <--------->| [DATA BUS] <--->| GP6  (PA0)            |
    | GP1  (PA1) <--------->| [DATA BUS] <--->| GP7  (PA1)            |
    | GP2  (PA2) <--------->| [DATA BUS] <--->| GP8  (PA2)            |
    | GP3  (PA3) <--------->| [DATA BUS] <--->| GP9  (PA3)            |
    | GP4  (PA4) <--------->| [DATA BUS] <--->| GP10 (PA4)            |
    | GP5  (PA5) <--------->| [DATA BUS] <--->| GP11 (PA5)            |
    | GP6  (PA6) <--------->| [DATA BUS] <--->| GP12 (PA6)            |
    | GP7  (PA7) <--------->| [DATA BUS] <--->| GP13 (PA7)            |
    |                       |                 |                       |
    | GP11 (CA2) ---------->| [REQUEST]  ---->| GP14 (Input)          |
    | GP10 (CA1) <----------| [ACK]      <----| GP15 (Output)         |
    |                       |                 |                       |
    | GND  -----------------| [COMMON GND] ---|--- GND                |
    |                       |                 |                       |
    +-----------------------+                 +-----------------------+
```

---

## 2. Implemented Commands

| Command | Alias | Description |
| ------- | ----- | ----------- |
| `DIR [PATH]` | `LS` | List files in a directory (root if omitted) |
| `MOUNT` | | Mount the file system |
| `PWD` | | Show current directory |
| `CD [PATH]` | | Change current directory |
| `MKDIR [PATH]` | | Create directory |
| `DEL [PATH]` | `RM` | Delete file |
| `RENAME [OLD] [NEW]` | `MV` | Rename or move file |
| `TYPE [FILENAME]` | `CAT` | Display file contents (`.BIN` shows hex dump) |
| `FORMAT` | | Format the W25Q64 flash |
| `PING` | | Ping the Raspberry Pi Pico W |
| `HELP` | | List available commands |
| `CONNECT [SSID] [PASSWORD]` | | Connect to Wi-Fi (stores credentials) |
| `EXIT` | | Exit shell to WozMon |
| `SAVEMEM [START] [END] [FILE]` | | Save 6502 memory region to flash |
| `LOADMEM [ADDR] [FILE]` | | Load file into 6502 memory |
| `RUN [FILE]` | | Load and execute binary (requires 2-byte header) |
| `COPY [SRC] [DST]` | `CP` | Copy file |
| `TOUCH [FILE]` | | Create empty file |
| `BENCH` | | Run filesystem benchmark (External) |
| `SETSERVER [IP:PORT]` | | Set/Get file server address (External) |
| `GET [REMOTE] [LOCAL]` | | Download file via HTTP (External) |
| `PUT [LOCAL] [REMOTE]` | | Upload file via HTTP (External) |
| `CAT [FILE]` | | Display file contents (External) |

## Command Protocol Reference

For complete command definitions including hex values for network commands (GET, PUT, SETSERVER) and File I/O operations, please see:

- [`src/cmd_defs.h`](src/cmd_defs.h) - Contains all command ID definitions including:
  - System commands (0x00-0x0F)
  - Filesystem commands (0x10-0x2F) - including CMD_FS_OPEN (0x12), CMD_FS_READ (0x13), CMD_FS_CLOSE (0x1C), CMD_FS_SAVEMEM (0x23), etc.
  - Network commands (0x30-0x4F) - including CMD_NET_HTTP_GET (0x34), CMD_NET_HTTP_POST (0x35)
  - Status codes

- The implementation code in src/main.c show:
  - How arguments are packed
  - Argument order
  - Return data format
  - File handle usage

---

## 3. External Commands (Transient Programs)

Commands marked as **(External)** are transient programs loaded from the filesystem.

If a command is not found internally, the shell automatically searches in the following order:

1. **Current Directory:** `[CWD]/[COMMAND].BIN`
2. **Bin Directory:** `/BIN/[COMMAND].BIN`

Example:

```sh
BENCH
```

Executes `/BIN/BENCH.BIN`

Source code for all transient commands is located in:

6502/ca65/commands/

---

## 4. Communication Protocol

Communication between the 65C02 and Raspberry Pi Pico W occurs over a fully interlocked parallel bus via the 6522 VIA.

### Core Functions

- `bus_read_byte()` – Read a byte from the parallel bus  
- `bus_write_byte()` – Write a byte to the parallel bus

### Handshaking

- 65C02 uses **CA2** to signal frame start  
- Pico uses **CA1** to acknowledge (ACK)

### Streaming Protocol (SAVEMEM / LOADMEM)

Large transfers use Pico-side state machines:

- `STATE_SAVEMEM_STREAM`
- `STATE_LOADMEM_STREAM`

#### SAVEMEM Flow

1. 6502 sends header  
2. Pico enters stream mode  
3. 6502 streams bytes  
4. Pico writes to flash  
5. Pico sends status  

#### LOADMEM Flow

1. 6502 sends header  
2. Pico enters stream mode  
3. Pico streams bytes from flash  
4. 6502 writes to RAM  

---

## 5. Error Handling

Errors detected by the Pico W are propagated back to the 65C02 using status codes and displayed by the shell. This centralizes error reporting and keeps the Pico-side implementation simple.

### Status Codes

| Code | Meaning |
| ------ | --------- |
| `$00` | STATUS_OK |
| `$01` | STATUS_ERR |
| `$02` | STATUS_NO_FILE |
| `$03` | STATUS_EXIST |

---

## 6. Concurrency and Timing

Parallel bus communication is fully hardware-interlocked. No software delays are required.

### Critical Rules

- **Do NOT restart Pico PIO state machines during active transactions**  
- **6502 must correctly switch VIA Port A direction before reading responses**

---

## 7. Writing and Running Programs

Programs can be written on the 6502 using the Krusader assembler, saved to disk, and executed with `RUN`.

### RUN File Format

The first 2 bytes must be the **Load Address** (little-endian). Program code follows immediately.

### Example: Creating `ABC.BIN`

1. **Enter Krusader**

```sh
F000R
```

1. **Write Program**

```asm
000 LOAD .M $38FE
001 .W $3900
002 START .M $3900
003 LDA #'A'
004 LOOP JSR $FFEF
005 CLC
006 ADC #$1
007 CMP #'Z'+1
008 BNE LOOP
009 RTS
```

1. **Assemble**

```sh
ASM
```

1. **Save**

```sh
SAVEMEM 38FE 390C ABC.BIN
```

1. **Run**

```sh
RUN ABC.BIN
```

Output: `ABCDEFGHIJKLMNOPQRSTUVWXYZ`

---

## 8. Memory Management

- `http_buf` – 32KB static buffer for HTTP downloads  
- `savemem_buf` – 256-byte streaming buffer for flash operations  
- LittleFS handles internal flash allocation automatically  

---

## 9. Configuration

Wi-Fi credentials are configured in:

src/main.c

Defines:

- `WIFI_SSID`
- `WIFI_PASSWORD`

---

## 10. W25Q64 Flash Usage

The full 8MB capacity of the W25Q64 flash chip is used for the LittleFS filesystem.

---

## 11. Transient Command Development (CURRENT PRIORITY)

> **Note:** The following section documents the definitive pattern for creating transient commands, validated by the working `PING` command.

---

### 11.1 Project Structure

```text
6502/ca65/
├── commands/ # Transient commands directory
│   ├── ping/ # Working example command
│   │   └── ping.s
│   ├── get/ # GET command (in progress)
│   │   └── get.s
│   ├── put/ # PUT command (in progress)
│   │   └── put.s
│   ├── setserver/ # SETSERVER command (in progress)
│   │   └── setserver.s
│   ├── Makefile # Auto-discovery build system
│   ├── transient.cfg # Linker configuration
│   ├── bin/ # Output directory for .bin files
│   └── obj/ # Object files directory
│
├── common/ # Shared 6502 code
│   ├── pico_def.inc # Constants and status codes
│   ├── pico_lib.s # Pico communication library
│   └── pico_lib.o # Compiled object
│
└── shell/ # Main shell (DO NOT MODIFY)
└── cmd_shell.s
```

---

### 11.2 Memory Layout (from `transient.cfg`)

$07FE-$07FF: HEADER segment (2 bytes: load address $0800, little-endian)
$0800-... : CODE segment (program code starts here)
$3000-... : BSS segment (uninitialized data - NOT in .bin file)

This layout ensures:

- **No zero bytes** in the middle of the binary  
- **Clean separation** of code and data  
- **BSS is excluded** from the binary file  

---

### 11.3 Zero Page Usage — CRITICAL

The shell reserves `$50-$57`. Transient commands **MUST** use `$58-$5F` only.

```asm
$50-$57 RESERVED FOR SHELL - DO NOT USE
$58-$5F AVAILABLE FOR TRANSIENT COMMANDS
```

### Standard Zero Page Pointers for Transients

```assembly
t_arg_ptr    = $58  ; 2 bytes - Argument pointer
t_str_ptr1   = $5A  ; 2 bytes - String pointer 1
t_str_ptr2   = $5C  ; 2 bytes - String pointer 2
t_ptr_temp   = $5E  ; 2 bytes - Temporary pointer
```

⚠️ IMPORTANT  
Do NOT use shell's arg_ptr, str_ptr1, str_ptr2, or ptr_temp
Do NOT call shell's argument parsing functions
Implement your own simple parsing

### 11.4 Shared Buffers and Functions

```assembly
; Buffers (from pico_lib.s)
ARG_BUFF    = $0400  ; 256-byte argument buffer
INPUT_BUFFER = $0300 ; Shell input buffer (contains command line)
LAST_STATUS = $??    ; Status from last Pico command

; Imported functions
.import pico_send_request, send_byte, read_byte
.import CMD_ID, ARG_LEN, ARG_BUFF, LAST_STATUS, RESP_LEN, RESP_BUFF
```

### 11.5 The Definitive Transient Command Pattern

Based on the working PING command, all transient commands should follow this exact structure:

```assembly
; command.s - Definitive pattern for transient commands
; Location: 6502/ca65/commands/command/command.s

; ---------------------------------------------------------------------------
; External symbols
; ---------------------------------------------------------------------------
.import pico_send_request
.import CMD_ID, ARG_LEN, LAST_STATUS

; ---------------------------------------------------------------------------
; System calls
; ---------------------------------------------------------------------------
OUTCH = $FFEF    ; Print character in A
CRLF  = $FED1    ; Print CR/LF

; ---------------------------------------------------------------------------
; Zero page (USE ONLY $58-$5F)
; ---------------------------------------------------------------------------
t_str_ptr1   = $5A
t_str_ptr2   = $5C
t_ptr_temp   = $5E

; ---------------------------------------------------------------------------
; HEADER - MUST be first
; ---------------------------------------------------------------------------
.segment "HEADER"
    .word $0800        ; Load at $0800

; ---------------------------------------------------------------------------
; CODE - Program starts here
; ---------------------------------------------------------------------------
.segment "CODE"

start:
    ; ALWAYS preserve registers
    php
    pha
    txa
    pha
    tya
    pha
    
    ; ========== Debug: Show we're running ==========
    lda #<debug_prefix
    sta t_str_ptr1
    lda #>debug_prefix
    sta t_str_ptr1+1
    jsr print_string
    ; ================================================
    
    ; Your command logic here
    ; - Set up CMD_ID and ARG_LEN
    ; - Call pico_send_request
    ; - Check LAST_STATUS
    ; - Print result
    
    ; ALWAYS restore registers before returning
done:
    pla
    tay
    pla
    tax
    pla
    plp
    clc              ; Return with carry clear
    rts

; ---------------------------------------------------------------------------
; Helper: Print null-terminated string
; Uses 65C02 PHY/PLY instructions
; ---------------------------------------------------------------------------
print_string:
    pha
    phy              ; 65C02 instruction
    ldy #0
@loop:
    lda (t_str_ptr1), y
    beq @done
    jsr OUTCH
    iny
    jmp @loop
@done:
    ply              ; 65C02 instruction
    pla
    rts

; ---------------------------------------------------------------------------
; Helper: Print byte in A as hex
; ---------------------------------------------------------------------------
print_hex:
    pha
    lsr a
    lsr a
    lsr a
    lsr a
    jsr print_nibble
    pla
    and #$0F
    jsr print_nibble
    rts

print_nibble:
    cmp #10
    bcc @digit
    adc #6
@digit:
    adc #'0'
    jsr OUTCH
    rts

; ---------------------------------------------------------------------------
; RODATA - All strings at the END of the file
; ---------------------------------------------------------------------------
.segment "RODATA"

debug_prefix:    .asciiz "CMD: "
msg_success:     .asciiz "SUCCESS"
msg_fail:        .asciiz "FAIL"
```

### 11.6 Working Example: PING Command

The PING command validates this pattern:

```assembly
; ping.s - Working example
.segment "HEADER"
    .word $0800

.segment "CODE"
start:
    ; Save registers
    php
    pha
    txa
    pha
    tya
    pha
    
    ; Show we're running
    lda #<debug_prefix
    sta t_str_ptr1
    lda #>debug_prefix
    sta t_str_ptr1+1
    jsr print_string
    
    ; Send PING command
    lda #$01           ; CMD_SYS_PING
    sta CMD_ID
    lda #$00
    sta ARG_LEN
    
    ; Show command
    lda #<debug_cmd
    sta t_str_ptr1
    lda #>debug_cmd
    sta t_str_ptr1+1
    jsr print_string
    
    lda CMD_ID
    jsr print_hex
    
    jsr pico_send_request
    
    ; Show status
    lda #<debug_status
    sta t_str_ptr1
    lda #>debug_status
    sta t_str_ptr1+1
    jsr print_string
    
    lda LAST_STATUS
    jsr print_hex
    jsr CRLF
    
    ; Check result
    lda LAST_STATUS
    bne fail
    
    ; Success
    lda #<msg_pong
    sta t_str_ptr1
    lda #>msg_pong
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    jmp done
    
fail:
    ; Failure
    lda #<msg_fail
    sta t_str_ptr1
    lda #>msg_fail
    sta t_str_ptr1+1
    jsr print_string
    jsr CRLF
    
done:
    ; Restore registers
    pla
    tay
    pla
    tax
    pla
    plp
    clc
    rts

; ... helper functions ...

.segment "RODATA"
debug_prefix:    .asciiz "PING: "
debug_cmd:       .asciiz "Cmd="
debug_status:    .asciiz " Status="
msg_pong:        .asciiz "PONG"
msg_fail:        .asciiz "FAIL"
```

Sample Output:

```text
> PING
PING: Cmd=01 Status=00
PONG
```

## 12. Network File Access Extension

The following network commands have been implemented and validated:

### 12.1 SETSERVER (External)

```sh
SETSERVER <ip:port>
```

Writes server address to server.cfg

No argument → display current server

### 12.2 GET (External)

```sh
GET <remote-path> [local-path]
```

Reads server.cfg

Builds:
ip\0port\0remote\0local
Sends CMD_NET_HTTP_GET

### 12.3 PUT (External)

```sh
PUT <local-path> <remote-path>
```

Reads server.cfg

Verifies local file exists

Builds:
ip\0port\0local\0remote
Sends CMD_NET_HTTP_POST

> **Note:** Currently, transient commands (`GET`, `PUT`) require **full absolute paths** for local files (e.g., `/DOCS/FILE.TXT`) as they do not yet share the shell's Current Working Directory (CWD).

## 13. File Server (tools/file_server.py)

Runs on remote machine (default port 8000). Supports:

- HTTP GET for files/directories
- HTTP POST with file data
- X-Mkdir header for directory creation
- X-Append header for append mode

## 14. Building Transient Commands

```bash
cd 6502/ca65/commands
make clean
make all
```

Output:
bin/command.bin (binary for copying to /BIN/)
bin/command.mon (WozMon format for pasting)

### Makefile Features

- Auto-discovers command directories
- Links against ../common/pico_lib.o
- Generates .mon files for WozMon
- Uses --cpu W65C02 for proper 65C02 support

## 15. Testing Workflow

Start file server:

```bash
cd tools
python3 file_server.py
```

Build commands:

```bash
cd 6502/ca65/commands
make
```

On 6502:

```sh
> SETSERVER 192.168.100.197:8000
Server set to 192.168.100.197:8000

> GET /test.txt
Downloading...
Done

> TYPE test.txt
(contents displayed)

> PUT test.txt /uploaded.txt
Uploading...
Done
```

## 16. Future Ideas (Post-Network Access)

```text
WRITE [PATH]
Create or append to text files

Multi-line input mode

Relative path support

Exit via Ctrl+Z or Ctrl+X
```

## 17. Important Rules Summary

- **Zero Page:** NEVER use $50-$57 in transient commands
- **Header:** Every transient command must start with .word $0800
- **Registers:** Always save and restore all registers
- **Strings:** Store all messages in RODATA at the end of the file
- **Return:** Always return with CLC
- **CPU:** Use --cpu W65C02 for proper 65C02 support
- **Debug:** Include debug output during development
- **Pattern:** Follow the validated PING command structure

This combined README now:

Preserves all original content

Adds the validated transient command pattern from the working PING program

Clearly documents zero page rules

Shows the exact structure for GET, PUT, and SETSERVER

Includes build instructions and testing workflow

Maintains the future ideas section

```markdown
## 18. Changelog (On branch feature/transient-3)

### Feature: Transient Text Editor (WRITE)

A new transient command `WRITE` has been implemented, providing a Nano-like text editing experience on the 6502 system.

**Key Features:**
*   **User Interface:** Full-screen editor with a header displaying the filename and a footer showing command shortcuts.
*   **Input Handling:**
    *   Supports standard alphanumeric input.
    *   Handles `Enter` for newlines and `Tab` for spacing.
    *   **Backspace:** Implemented visual and buffer-level character deletion.
    *   **Arrow Keys:** Escape sequence detection is in place to gracefully handle cursor keys.
*   **File Management:**
    *   **Launch with Filename:** `WRITE <filename>` opens the editor with the target file pre-set.
    *   **Launch Empty:** `WRITE` opens a blank buffer.
    *   **Save & Exit:** Triggered via `Ctrl+X`.
    *   **Smart Prompting:** If a filename was not provided at launch, the editor prompts the user to enter one upon saving.
*   **Architecture:**
    *   Operates as a transient command loaded at `$0800`.
    *   Utilizes a 4KB fixed memory buffer for text storage.
    *   Integrates with the shell's Current Working Directory (CWD) for relative path resolution.
    *   Implements robust stack management to prevent corruption during execution.

**Previous Features (feature/transient-2):**

The following features were implemented on the `feature/transient-2` branch, building upon the transient command architecture established in `feature/transient-1`:

1.  **Shell Enhancements**:
    -   **Smart Execution Path**: The shell now searches for external commands in the **Current Working Directory** first, then falls back to `/BIN/`. This allows executing local binaries immediately.
    -   **Global Pagination**: Implemented a `--More--` prompt for commands with long output (`DIR`, `TYPE`, `HELP`, `PWD`). The output pauses every 22 lines and waits for a keypress.
    -   **Relative Path Support**: The shell now passes the Current Working Directory to transient commands via Zero Page ($5E/$5F), enabling them to resolve relative paths.
    -   **Robustness & Fixes**:
        -   Fixed a critical bug in `SAVEMEM` where the "Saving..." message overwrote the data pointer.
        -   Added safety checks to `TYPE` to prevent reading directories as files.
        -   Improved `try_external` logic to correctly handle argument shifting and ensure absolute paths are passed to the Pico.

2.  **Transient Command Updates**:
    -   **GET / PUT**: Updated to utilize the CWD pointer. Users can now use relative paths for local files (e.g., `GET file.txt` saves to the current directory).
    -   **Global Configuration**: Network commands now explicitly look for `/server.cfg` in the root directory, ensuring they function correctly from any subdirectory.

3.  **Previous Features (feature/transient-1)**:
    -   Transient Command Architecture (`/BIN` execution).
    -   Network Commands (`SETSERVER`, `GET`, `PUT`, `NETPING`).

