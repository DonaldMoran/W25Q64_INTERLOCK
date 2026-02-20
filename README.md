# W25Q64_INTERLOCK
6502 ↔ Pico W interlocked filesystem interface

This document outlines the architecture, communication protocol, error handling, concurrency, memory management, configuration, and flash memory usage of the W25Q64_INTERLOCK project.

## 1. Overall Architecture

The system comprises the following main components:


*   **65C02 Computer:** Hosts a shell and initiates commands.
*   **6522 VIA (Versatile Interface Adapter):** Provides a parallel interface for communication between the 65C02 and the Raspberry Pi Pico W.
*   **Raspberry Pi Pico W:** Receives commands from the 6522, interacts with the W25Q64 flash memory, and manages the LittleFS filesystem. It also handles Wi-Fi connectivity.
*   **W25Q64 Flash Memory:** Stores the LittleFS filesystem, providing persistent storage for files.
*   **LittleFS:** A lightweight filesystem optimized for microcontrollers, managing file storage and retrieval on the W25Q64 flash memory.

The 65C02 computer issues commands, which are transmitted through the 6522 VIA to the Raspberry Pi Pico W. The Pico W interprets these commands, performs actions such as reading from or writing to the W25Q64 flash memory, and sends responses back to the 65C02 for display.


## Implemented Commands
*   **DIR [PATH]** (Alias: **LS**): Lists files in a directory. If no path is specified, lists the root directory.
*   **MOUNT**: Mounts the file system.
*   **PWD**: Shows the current directory.
*   **CD [PATH]**: Change the current directory.
*   **MKDIR [PATH]**: Make a new directory.
*   **DEL [PATH]** (Alias: **RM**): Delete a file.
*   **RENAME [OLD] [NEW]** (Alias: **MV**): Rename or move a file.
*   **TYPE [FILENAME]** (Alias: **CAT**): Display the contents of a file. If the file ends in `.BIN`, it displays a hex dump.
*   **FORMAT**: Format the W25Q64 Flash Memory
*   **PING**: Ping the Raspberry Pi Pico W
*   **HELP**: Lists available commands.
*   **CONNECT**: Connects to the configured WIFI Network
*   **EXIT**: Exits the shell and returns to the WozMon
*   **SAVEMEM [START_HEX] [END_HEX] [FILENAME]**: Save a region of 6502 memory to a file on the W25Q64 flash.
*   **LOADMEM [ADDRESS_HEX] [FILENAME]**: Load a file from flash into 6502 memory.
*   **RUN [FILENAME]**: Load a binary file and execute it. The file must contain a 2-byte header indicating the load address.
*   **COPY [SRC] [DST]**: Copy a file. (External)
*   **BENCH**: Run filesystem benchmark. (External)

### External Commands
Commands marked as (External) are transient programs. The shell supports implicit execution of these commands: if a command is not found internally, the shell looks for a file named `/BIN/[COMMAND].BIN`.

For example, typing `BENCH` will execute `/BIN/BENCH.BIN`.

## 2. Communication Protocol

The communication between the 65C02 and the Raspberry Pi Pico W occurs over a parallel bus via the 6522 VIA. The protocol is fully interlocked, ensuring reliable data transfer through hardware handshaking:

*   `bus_read_byte()`: Reads a byte from the parallel bus.
*   `bus_write_byte()`: Writes a byte to the parallel bus.

The 65C02 uses CA2 to signal frame start and the Pico uses CA1 to ACK.

### Streaming Protocol (SAVEMEM/LOADMEM)
For large data transfers, the system uses a streaming state machine on the Pico side (`STATE_SAVEMEM_STREAM`, `STATE_LOADMEM_STREAM`) to bypass the standard command buffer limits.
*   **SAVEMEM**: 6502 sends header -> Pico enters stream mode -> 6502 streams bytes -> Pico writes to flash -> Pico sends status.
*   **LOADMEM**: 6502 sends header -> Pico enters stream mode -> Pico reads from flash and streams bytes -> 6502 writes to RAM.

## 3. Error Handling

The project employs a centralized error reporting strategy. Errors detected by the Raspberry Pi Pico W are propagated back to the 65C02 computer, which then presents them on a screen. This allows for a simple and consolidated view of system status and errors.

## 4. Concurrency and Timing

The parallel bus communication is fully interlocked, removing the need for software delays or complex timing management. Each byte transfer is synchronized using hardware handshaking signals.
*   **Critical**: The PIO state machines on the Pico must NOT be restarted during active transactions to prevent bus glitches.
*   **Critical**: The 6502 must switch VIA Port A direction correctly before reading responses to avoid bus contention.

## 5. Writing and Running Programs

You can create programs directly on the 6502 using the Krusader assembler, save them to disk, and execute them later using the `RUN` command.

The `RUN` command expects the first 2 bytes of the file to be the **Load Address** (Little Endian). The code follows immediately after.

### Example: Creating "ABC.BIN"

1.  **Enter Krusader**: From the shell, type `EXIT` to return to WozMon, then run Krusader (usually at `$F000`).
    ```
    F000R
    ```

2.  **Write the Program**:
    We will use address `$38FE` to store the 2-byte header for our program which starts at `$3900`.

    ```
    000 LOAD   .M  $38FE    ; Set memory address to header location
    001        .W  $3900    ; Write Load Address ($3900) as header
    002 START  .M  $3900    ; Set memory address for code
    003        LDA #'A'     ; Load 'A'
    004 LOOP   JSR $FFEF    ; Print character (OUTCH)
    005        CLC 
    006        ADC #$1      ; Increment character
    007        CMP #'Z'+1   ; Check if past 'Z'
    008        BNE LOOP     ; Loop if not
    009        RTS          ; Return to Shell
    ```

3.  **Assemble**: Type `A` to assemble the code.

4.  **Save to Disk**: Return to the shell (Reset or Exit Krusader) and save the memory range including the header.
    ```
    SAVEMEM 38FE 390C ABC.BIN
    ```

5.  **Run**:
    ```
    RUN ABC.BIN
    ```
    Output: `ABCDEFGHIJKLMNOPQRSTUVWXYZ`

## 6. Memory Management

*   `http_buf`: A static buffer of size `HTTP_BUF_SIZE` (32768 bytes) used for HTTP downloads.
*   `savemem_buf`: A 256-byte buffer used for chunking flash writes/reads during streaming operations.
*   LittleFS manages memory allocation and deallocation within the W25Q64 flash memory, but further investigation is required to determine the specifics.

## 7. Configuration

Wi-Fi SSID and password can be configured in `src/main.c` through the `WIFI_SSID` and `WIFI_PASSWORD` definitions.

## 8. W25Q64 Flash Usage

The filesystem utilizes the full capacity of the W25Q64 flash chip, providing the maximum available storage space.
