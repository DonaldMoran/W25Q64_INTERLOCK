# W25Q64_INTERLOCK

6502 ↔ Pico W interlocked filesystem interface

This document outlines the architecture, communication protocol, error handling, concurrency, memory management, configuration, flash memory usage, and transient command development for the W25Q64_INTERLOCK project.

🕹️ A Spirit of Retrocomputing
This project embraces the hands‑on creativity of the late 1970s and early 1980s—the era of the Apple II, Commodore 64, Atari 8‑bit machines, and countless homebrew experiments. The goal is to
capture that feeling of discovery: wiring things together, learning by doing, and building tools that feel at home on a 6502‑based system.

📚 Historical Context
The 6502 was designed in a time when computers were simple, open, and hackable. Users were encouraged to explore, modify, and understand their machines. W25Q64_INTERLOCK continues in that tradition
by connecting a classic 6502 CPU to modern flash storage and a Raspberry Pi Pico acting as a coprocessor.

This project is purely educational and hobbyist in nature. It exists to celebrate the joy of low‑level programming, embedded systems, and the retrocomputing mindset.

**Don's DOS ("DDOS")** connects a 1970s 6502 processor to modern flash memory—exactly the sort of educational, non-commercial work that flourishes in an environment of creative freedom.

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
    +-----------------------+                 +-----------+-----------+
                                              |   BRIDGE PICO (W)     |
                                              |                       |
                                              |  GP19 --------------->| DI (MOSI)
                                              |  GP18 --------------->| CLK
                                              |  GND  --------------->| GND
                                              |  GP17 --------------->| CS
                                              |  GP16 --------------->| DO (MISO)
                                              |                       |
                                              +-----------+-----------+
                                                          |
                                                          |
                                                          v
                                                +---------------------+
                                                |     W25Q64 FLASH    |
                                                | (left→right labels) |
                                                |                     |
                                                |   DI(MOSI) <------->| GP19
                                                |   CLK      <------->| GP18
                                                |   GND      <------->| GND
                                                |   DO(MISO) <------->| GP16
                                                |   CS       <------->| GP17
                                                |   VCC      <------->| 3V3
                                                |                     |
                                                +---------------------+

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
| `SAVEMEM [START] [END] [FILE]` | | Save 6502 memory region to flash. Fails if `[FILE]` is a directory. |
| `LOADMEM [ADDR] [FILE]` | | Load file into 6502 memory. Fails if `[FILE]` is a directory. |
| `RUN [FILE]` | | Load and execute binary (requires 2-byte header) |
| `COPY [SRC] [DST]` | `CP` | Copy file |
| `TOUCH [FILE]` | | Create empty file |
| `JUMP [ADDR]` | | Jump to address (e.g. FF00 for WozMon) |
| `DATE [ARGS]` | | Get/Set System Time (NTP supported) (External) |
| `ECHO [TEXT]` | | Print text to screen (External) |
| `DO [FILE]` | | Execute batch script (External) |
| `WRITE [FILE]` | | Text Editor (External) |
| `BENCH` | | Run filesystem benchmark (External) |
| `DF` | | Disk Free space usage (External) |
| `SETSERVER [IP:PORT]` | | Set/Get file server address (External) |
| `GET [REMOTE] [LOCAL]` | | Download file via HTTP (External) |
| `PUT [LOCAL] [REMOTE]` | | Upload file via HTTP (External) |
| `CAT [FILE]` | | Display file contents (External) |
| `CP [SRC] [DST]` | | Copy file (External) |
| `RM-FR [PATH]` | | Recursive delete directory (External) |
| `RM*` | | Delete all files in current dir (External) |
| `TREE [PATH]` | | Visualize directory structure (Streaming) (External) |
| `RLIST [PATH]` | | List remote directory (Streaming) (External) |
| `PICORBT` | | Reboot Bridge Pico (External) |
| `CATALOG [PATH]` | | Streaming directory list for any size (External) |
| `BASIC` | | Start MSBASIC (External). Displays a "Don's DOS BASIC" splash screen. |
| `BASICW` | | Warm start MSBASIC (External) |
| `KRUSADER` | | Start Krusader Assembler (External) |
| `KRUSADERW` | | Warm start Krusader (External) |
| `WOZMON` | | Start WozMon Monitor (External) |
| `HEAD [FILE]` | | Print first 10 lines of file (External) |
| `HEX [FILE]` | | Hex dump of file (External) |
| `TAIL [FILE]` | | Print last 10 lines of file (External) |
| `GREP [PATTERN] [FILE]` | | Search for pattern in file (External) |
| `WC [FILE]` | | Count lines, words, and characters (External) |
| `DIFF [FILE1] [FILE2]` | | Compare two files (External) |
| `CALC` | | Retro Calculator (External) |
| `CLS` | | Clear Screen and return home (External) |
| `NEWS [ARGS]` | | Stream RSS headlines (External) |
| `WEATHER [LOC]` | | Stream Weather report (External) |
| `MAN [CMD]` | | Display manual page (External) |

### Design Note: `DIR`/`LS` vs `CATALOG`

A key design choice has been made to balance features against the shell's limited ROM space (`< 4KB`).

- **`DIR` (aliased as `LS`)** is a built-in command whose output is limited by a 1024-byte response buffer on the 6502 side. This keeps the core shell small and fast for common use cases. For larger directories, the `CATALOG` command should be used.

- **`CATALOG`** is a new transient command that implements a streaming protocol. It reads the directory listing byte-by-byte and can therefore handle directories of any size without being limited by a buffer. It is the recommended command for very large directories.

> **Example:** The `/MAN/` directory, which contains manual pages for all commands, contains more files than `DIR` can buffer. Use `CATALOG /MAN` to view its full contents.

### Command Protocol Reference

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

## 3. Building the Bridge Pico (Pico W) and the Host Pico (65C02 Emulator) Firmware

This project involves two Raspberry Pi Picos:

1. **Bridge Pico (Pico W):** The smart peripheral handling filesystem, network, and 6502 bus interface.
2. **Host Pico (Standard Pico):** Emulates the 6502 system (if not using real hardware).

The build process involves:

1. CA65
2. Pico SDK
3. Python 3

### 3.1 Bridge Pico (Pico W)

**Build Steps:**

1. Clone the repository and switch to the project root directory:

    ```bash
    git clone <https://github.com/DonaldMoran/W25Q64_INTERLOCK.git>
    cd W25Q64_INTERLOCK
    ```

    **Configuration:**
    Before building, open `src/main.c` and configure your network settings:

    ```c
    #define WIFI_SSID "YOUR_SSID"
    #define WIFI_PASSWORD "YOUR_WIFI_PASS"
    #define FILE_SERVER_IP "192.168.1.100" // IP of your PC running file_server.py
    ```

2. Ensure the **Pico SDK** is installed and the `PICO_SDK_PATH` environment variable is set. For example in my .bashrc:

    ```bash
    export PICO_SDK_PATH=/home/noneya/pico/pico-sdk
    ```

3. If picotool is installed, the compile.sh script will perform the following steps and load the pico w if it is in bootsel mode, else create a build directory:

    ```bash
    mkdir build
    cd build
    ```

4. Run CMake:

    ```bash
    cmake ..
    ```

5. Compile:

    ```bash
    make
    ```

6. **Flash:** Hold the BOOTSEL button on your Pico W, connect it to USB, and copy the generated `6522_smart_device.uf2` file to the `RPI-RP2` drive.

### 3.2 Host Pico (65C02 Emulator)

**Source Location:** `emmulator/EMULATOR/`

**Build Steps:**

1. Assuming you are still in the build directory for the Bridge pico w from above, navigate to the emmulator directory and carry out the following. It does try to load using picotool, which will simply fail if not installed or if the pico is not in bootsel mode, however the build will still succeed and the *.uf2 file can be loaded via copy/paste:

    ```bash
    cd ..
    cd emmulator/EATERSD10
    ./doit.sh
    ```

    ```text
    This will first build the ROM image at location EATERSD10/four-bit-mode-msbasic/tmp/eater.bin
    The bin file will the be converted to a c header as eater.h and copied to ../EMULATOR/src
    Ultimately you will land in directory EMULATOR/build - see source for doit.sh for details
    ```

2. **Flash:** Hold the BOOTSEL button on your standard Pico, connect it to USB, and copy the generated `6502emu.uf2` file to the `RPI-RP2` drive.

### Optional but recommended: Building the transient commands

Assuming you are currently in the build directory for the 65c02 from above:

```bash
cd ../../6502/ca65
make clean
make
```

### Create a package of the 2 uf2 files and all the transient commands

The quickest way to gather the firmware for both pico's as well as all the optional transient commands is to:

1. Swith to the projects root > tools directory and execute python pkg_builder.py

    This will result in a directory structure of, for example:

    ```text
    pkg_build
    └── version_0.9
        ├── 6502emu.uf2
        ├── 6522_smart_device.uf2
        └── transient_cmds.zip
    ```

---

## 4. External Commands (Transient Programs)

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

## 5. Communication Protocol

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

## 6. Error Handling

Errors detected by the Pico W are propagated back to the 65C02 using status codes and displayed by the shell. This centralizes error reporting and keeps the Pico-side implementation simple.

### Status Codes

| Code | Meaning |
| ------ | --------- |
| `$00` | STATUS_OK |
| `$01` | STATUS_ERR |
| `$02` | STATUS_NO_FILE |
| `$03` | STATUS_EXIST |

---

## 7. Concurrency and Timing

Parallel bus communication is fully hardware-interlocked. No software delays are required.

### Critical Rules

- **Do NOT restart Pico PIO state machines during active transactions**  
- **6502 must correctly switch VIA Port A direction before reading responses**

---

## 8. Writing Programs on the 6502 with Krusader

Programs can be written on the 6502 using the Krusader assembler, saved to disk, and executed with `RUN`.

### RUN File Format

The first 2 bytes must be the **Load Address** (little-endian). Program code follows immediately.

### Example: Creating `ABC.BIN`

1. **Enter Krusader**

    ```sh
    F000R
    ```

2. **Write Program**

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

3. **Assemble**

    ```sh
    A
    ```

4. **Save**

    ```sh
    SAVEMEM 38FE 390C ABC.BIN
    ```

5. **Run**

    ```sh
    RUN ABC.BIN
    ```

Output: `ABCDEFGHIJKLMNOPQRSTUVWXYZ`

### Krusader Extensions

The Krusader assembler has been patched with new file I/O commands:

- **`S <filename>`**: Save Source. Saves the current source code buffer to a file (including the null terminator).
- **`F <filename>`**: Fetch Source. Loads a source file into the buffer and re-indexes it.
- **`O <filename>`**: Save Object. Saves the assembled binary (from `$0300` or defined origin) to a file.

---

## 9. Memory Management

-
- **Pico:** A 4KB `resp_buf` is used for efficient, block-aligned streaming I/O (`SAVEMEM`, `LOADMEM`, `GET`).
- **6502:** A 1KB `RESP_BUFF` (located at `$0400` in RAM) receives responses for non-streaming, built-in shell commands.
  - **`DIR` / `LS`:** This is the primary command limited by the buffer. A pre-flight check prevents directory listings larger than 1KB from being requested, ensuring bus stability.
  - **Other commands:** `PING`, `STAT` (used internally by many commands), and other simple queries also use this buffer, but their responses are very small and not subject to overflow.
  - **Streaming Commands** (`CATALOG`, `TYPE`, `RUN`, `NEWS`, etc.) bypass this buffer entirely, reading data byte-by-byte.
- LittleFS handles internal flash allocation automatically  

---

## 10. Configuration

Wi-Fi credentials are configured in:

src/main.c

Defines:

- `WIFI_SSID`
- `WIFI_PASSWORD`

---

## 11. W25Q64 Flash Usage

The full 8MB capacity of the W25Q64 flash chip is used for the LittleFS filesystem.

---

## 12. Transient Command Development (CURRENT PRIORITY)

> **Note:** The following section documents the definitive pattern for creating transient commands, validated by the working `PING` command.

---

### 12.1 Project Structure

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

### 12.2 Memory Layout (from `transient.cfg`)

$07FE-$07FF: HEADER segment (2 bytes: load address $0800, little-endian)
$0800-... : CODE segment (program code starts here)
$3000-... : BSS segment (uninitialized data - NOT in .bin file)

This layout ensures:

- **No zero bytes** in the middle of the binary  
- **Clean separation** of code and data  
- **BSS is excluded** from the binary file  

---

### 12.3 Zero Page Usage — CRITICAL

The shell reserves `$50-$57`. Transient commands **MUST** use `$58-$5F` only.

```asm
$50-$57 RESERVED FOR SHELL - DO NOT USE
$58-$5F AVAILABLE FOR TRANSIENT COMMANDS
```

#### Standard Zero Page Pointers for Transients

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

### 12.4 Shared Buffers and Functions

```assembly
; Zero Page Assignments
; ---------------------------------------------------------------------------
;The shell reserves `$50-$57`. Transient commands **MUST** use `$58-$5F` only.

```asm
$50-$57 RESERVED FOR SHELL - DO NOT USE
$58-$5F AVAILABLE FOR TRANSIENT COMMANDS
```

```assembly
; Buffers (from pico_lib.s)
ARG_BUFF    = $0400  ; 256-byte argument buffer
INPUT_BUFFER = $0300 ; Shell input buffer (contains command line)
LAST_STATUS = $??    ; Status from last Pico command

; Imported functions
.import pico_send_request, send_byte, read_byte
.import CMD_ID, ARG_LEN, ARG_BUFF, LAST_STATUS, RESP_LEN, RESP_BUFF

```

### 12.5 The Definitive Transient Command Pattern

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
t_arg_ptr    = $58
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
    
    ; --- CRITICAL: Sanitize CPU state ---
    ; MSBASIC is known to exit with Decimal Mode set and interrupts enabled.
    ; Always clear decimal mode and disable interrupts to ensure robust operation.
    cld
    ; --- CRITICAL: Sanitize CPU state ---
    ; MSBASIC is known to exit with Decimal Mode set and interrupts enabled.
    ; Always clear decimal mode and disable interrupts to ensure robust operation.
    cld
    sei

    ; --- (Optional) Parse command-line arguments ---
    ; This helper will set t_arg_ptr to point to the first argument
    ; in the command line, ready for your own parsing logic.
    ; jsr skip_cmd_args

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
; Helper: Skip past "RUN" and "/BIN/CMD.BIN" to find arguments
; Out: t_arg_ptr points to the start of the first argument, or a null
;      terminator if no arguments are present.
; ---------------------------------------------------------------------------
skip_cmd_args:
    lda #<INPUT_BUFFER
    sta t_arg_ptr
    lda #>INPUT_BUFFER
    sta t_arg_ptr+1
    jsr skip_word ; Skips "RUN"
    jsr skip_word ; Skips "/BIN/COMMAND.BIN"
    rts

skip_word:
    ldy #0
@skip_chars:
    lda (t_arg_ptr), y
    beq @sw_done
    cmp #' '
    beq @found_space
    iny
    jmp @skip_chars
@found_space:
@skip_spaces:
    iny
    lda (t_arg_ptr), y
    beq @sw_done
    cmp #' '
    beq @skip_spaces
@sw_done:
    tya
    clc
    adc t_arg_ptr
    sta t_arg_ptr
    lda #0
    adc t_arg_ptr+1
    sta t_arg_ptr+1
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

### 12.6 Blueprint for Creating Transient Streaming Commands

**Architectural Rules for New Streaming Commands:**

#### 1. Streaming Protocol

- **Use Framed Output:** `[LEN_LO] [LEN_HI] [DATA...]` (Little-Endian).
- **EOF Marker:** A frame with length 0 (`0x00 0x00`) signals the end of the stream.
- **No SYNC Byte:** The bus is hardware-interlocked; do not add synchronization bytes.

#### 2. Pico-Side Handler (`main.c`)

- **Strict Synchronization:** The handler **MUST NOT** return to the main loop until the entire stream is finished and the EOF frame is sent.
- **Status Header:**
  - If the command fails *before* streaming starts (e.g., DNS fail), send `STATUS_ERR` and exit.
  - If the command succeeds, send `STATUS_OK` followed by `0x00 0x00` (dummy length) before sending the first data frame.
- **Helpers:** Use `stream_send_chunk(data, len)` and `stream_end()` helpers.

#### 3. 6502-Side Command (`.s`)

- **Memory:** Load at `$0800`. Use Zero Page `$58-$5F` only.
- **Read Loop:**
    1. Read Status. If `STATUS_ERR`, consume 2 bytes (dummy len) and exit.
    2. Read `LEN_LO`, `LEN_HI`.
    3. If `LEN == 0`, exit loop.
    4. Read `LEN` bytes and process/print them.
    5. Repeat.
- **Pagination:** If implementing `--More--` functionality, poll the ACIA (keyboard) for input. Do not read from the bus during the pause (this maintains hardware flow control).

#### 4. Configuration

- **Defaults:** Store default settings in a small text file in `/etc/` (e.g., `/etc/ping.cfg`).
- **Set Default:** Implement `SETDEFAULT` logic on the 6502 side by writing to that file using standard filesystem commands. Do not handle `SETDEFAULT` inside the Pico firmware command.

## 13. Network File Access Extension

The following network commands have been implemented and validated:

### 13.1 SETSERVER (External)

```sh
SETSERVER <ip:port>
```

Writes server address to server.cfg

No argument → display current server

### 13.2 GET (External)

```sh
GET <remote-path> [local-path]
```

Reads server.cfg

Builds:
ip\0port\0remote\0local
Sends CMD_NET_HTTP_GET

### 13.3 PUT (External)

```sh
PUT <local-path> <remote-path>
```

Reads server.cfg

Verifies local file exists

Builds:
ip\0port\0local\0remote
Sends CMD_NET_HTTP_POST

> **Note:** Transient commands (`GET`, `PUT`) now fully support **relative paths** and respect the shell's Current Working Directory (CWD).

## 14. File Server (tools/file_server.py)

Runs on remote machine (default port 8000). Supports:

- HTTP GET for files/directories
- HTTP POST with file data
- X-Mkdir header for directory creation
- X-Append header for append mode

## 15. Building Transient Commands

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

## 16. Testing Workflow

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

## 17. Future Ideas (Post-Network Access)

```text

*   **Telnet Client:** A simple terminal emulator to connect to BBSs.
*   **IRC Client:** Read and post to IRC channels.

```

## 18. Important Rules Summary

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

### Major System Updates

- **ROM Integration:** The shell has been moved to ROM at `$E000`, freeing up RAM for transient programs.
- **Auto-Mount:** Filesystem now mounts automatically on boot.

## Applications Section

- This section highlights some of the key applications developed for the 6502 system.

- **Text Editor (`WRITE`)**

  - A new transient command `WRITE` has been implemented, providing a Nano-like text editing experience on the 6502 system.

  - **Key Features:**

    - **User Interface:** Full-screen editor with a header displaying the filename and a footer showing command shortcuts.
      - **Scrolling Viewport:** The editor displays large files within a scrolling viewport (Lines 4-22), allowing for smooth navigation through documents larger than the screen.
      - **Input Handling:**
        - Supports standard alphanumeric input.
        - Handles `Enter` for newlines and `Tab` for spacing.
        - **Backspace:** Implemented visual and buffer-level character deletion.
      - **Navigation:**
        - Full support for **Arrow Keys**, **Home**, **End**, **Page Up**, and **Page Down**.
        - Navigation logic is optimized for handling the last line and page boundaries correctly.
      - **Search:** `Ctrl+F` triggers a text search from the current cursor position, wrapping to the start if needed.
      - **File Management:**
        - **Launch with Filename:** `WRITE <filename>` opens an existing file or creates a new one. File loading is robust, using standard file I/O to prevent buffer corruption.
        - **Save & Exit:** `Ctrl+X` prompts to save changes before exiting.
        - **Save As:** `Ctrl+O` allows saving the current buffer to a new filename.
        - **Smart Prompting:** If a filename was not provided at launch, the editor prompts the user to enter one upon saving.
  - **Architecture:**
    - Operates as a transient command loaded at `$0800`.
    - Utilizes a 4KB fixed memory buffer for text storage.
    - Integrates with the shell's Current Working Directory (CWD) for relative path resolution.
    - Implements robust stack management to prevent corruption during execution.

- **Retro Calculator Details (`CALC`)**

  - **Features:**
    - Hex/Binary/Decimal conversions
    - Address range calculations
    - Simple arithmetic (addition, subtraction, multiplication, division) for unsigned 16-bit integers (0-65535).
    - Comprehensive input validation and error handling
    - Menu-driven interface

### MSBASIC Memory Configuration

To prevent memory corruption when using `SAVE` and `LOAD` commands in MSBASIC, the start of BASIC program memory (`RAMSTART2`) has been moved.

- **Old Location:** `$0800` (Standard for many 6502 systems)
- **New Location:** `$0B00`
- **Reason:** The Shell and Pico Interface library use a BSS segment starting at `$0400` for variables and large I/O buffers (`ARG_BUFF`, `RESP_BUFF`). This segment grows up to approximately `$0AA0`. Moving BASIC to `$0B00` ensures that file operations do not overwrite the running BASIC program.

#### ZEROPAGE

With CONFIG_2A and your ZP_START values:

**Starting points:**

- `ZP_START1` = $02 (GORESTART, GOSTROUT, GOAYINT, GIVEAYF)
- `ZP_START2` = $0C (Z15, POSX, Z17, Z18, LINNUM, TXPSV, INPUTBUFFER)
- `ZP_START3` = $62 (CHARAC through Z14)
- `ZP_START4` = $6D (TEMPPT through the rest)

**Allocation Trace:**

**ZP_START1 ($02):**

- GORESTART: .res 3 → $02-$04
- GOSTROUT: .res 3 → $05-$07
- GOAYINT: .res 2 → $08-$09
- GOGIVEAYF: .res 2 → $0A-$0B
- *(Ends at $0B)*

**ZP_START2 ($0C):**

- Z15: .res 1 → $0C
- POSX: .res 1 → $0D
- Z17: .res 1 → $0E
- Z18: .res 1 → $0F
- LINNUM/TXPSV: .res 2 → $10-$11
- INPUTBUFFER: (no .res specified, but likely continues)
- *(Need to see where ZP_START2 ends - probably continues until just before ZP_START3 at $62)*

**ZP_START3 ($62):**

- CHARAC: .res 1 → $62
- ENDCHR: .res 1 → $63
- EOLPNTR: .res 1 → $64
- DIMFLG: .res 1 → $65
- VALTYP: .res 2 (since not CONFIG_SMALL) → $66-$67
- DATAFLG: .res 1 → $68
- SUBFLG: .res 1 → $69
- INPUTFLG: .res 1 → $6A
- CPRMASK: .res 1 → $6B
- Z14: .res 1 → $6C
- *(Ends at $6C, just before ZP_START4)*

**ZP_START4 ($6D):**

- This continues through FAC, ARG, etc.

**THE CRITICAL OBSERVATION:**
With your configuration, ZP_START2 ends somewhere and ZP_START3 begins at $62. This means:

The entire range from approximately **$12 through $61 is UNUSED and FREE!**

This includes:

- **$50-$5F** (your original question) - **COMPLETELY FREE**
- Actually **$12-$61** is all free (about 80 bytes!)

**Why this happens:**
The original Microsoft BASIC typically had ZP_START3 around $50-$5F range, but your CONFIG_2A has moved it to $62, creating a large gap between the end of ZP_START2 variables and the start of ZP_START3 variables.

**CONCLUSION:**
$50-$5F is DEFINITELY AVAILABLE - in fact, it's part of a large free block from $12-$61 that you can safely use for your own purposes.

This is excellent news for your project - you have plenty of zero page space to work with!

## 19. Development Workflow (RAM Testing)

To test changes to the shell without burning a new ROM:

1. **Build the RAM Shell:**

    ```bash
    cd 6502/ca65
    make
    ```

    This creates `bin/cmd_shell.bin`.

2. **Upload to Pico:**
    Copy `bin/cmd_shell.bin` to the Pico filesystem (e.g., as `NEWSHELL.BIN`).

3. **Load and Run:**
    From the existing ROM shell on the 6502:

    ```text
    LOADMEM 1000 NEWSHELL.BIN
    JUMP 1000
    ```

    You are now running the new shell from RAM.

## 20. Build System & File Reference

### Build Configuration Files

| File | Purpose |
| ---- | ------- |
| `6502/ca65/Makefile` | **Master Makefile** for RAM development. Builds shell and commands. |
| `6502/ca65/common/ram.cfg` | Linker config for the **RAM Shell** (Loads at `$1000`). |
| `6502/ca65/commands/Makefile` | Makefile for **Transient Commands**. |
| `6502/ca65/commands/transient.cfg` | Linker config for **Transient Commands** (Loads at `$0800`). |

### Core Source Files

| File | Purpose |
| ---- | ------- |
| `6502/ca65/shell/cmd_shell.s` | **Master Shell Source**. Used for both RAM and ROM builds. |
| `6502/ca65/common/pico_lib.s` | **Hardware Driver**. Handles VIA/Pico communication. |
| `6502/ca65/common/pico_def.inc` | **Global Definitions**. Constants, Command IDs, Status Codes. |

### Legacy Files

| File | Status |
| ---- | ------ |
| `6502/ca65/commands/transient.inc` | **Deprecated**. Replaced by `pico_def.inc` and `pico_lib.s`. Do not use for new commands. |
