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
*   **DIR**: Lists files in a directory.
*   **MOUNT**: Mounts the file system.
*   **PWD**: Shows the current directory.
*   **CD**: Change the current directory
*   **MKDIR**: Make a new directory.
*   **DEL**: Delete a file.
*   **FORMAT**: Format the W25Q64 Flash Memory
*   **PING**: Ping the Raspberry Pi Pico W
*   **HELP**: Lists available commands.
*   **CONNECT**: Connects to the configured WIFI Network
*   **EXIT**: Exits the shell and returns to the WozMon


## Target Commands
*   **SAVEMEM [START ADDRESS IN HEX] [END ADDRESS IN HEX] FILENAME**: Save a region of 6502 memory to a file on the W25Q64 flash.


## 2. Communication Protocol

The communication between the 65C02 and the Raspberry Pi Pico W occurs over a parallel bus via the 6522 VIA. The protocol is fully interlocked, ensuring reliable data transfer through hardware handshaking:

*   `bus_read_byte()`: Reads a byte from the parallel bus.
*   `bus_write_byte()`: Writes a byte to the parallel bus.

The 65C02 uses CA2 to signal frame start and the Pico uses CA1 to ACK.

## 3. Error Handling

The project employs a centralized error reporting strategy. Errors detected by the Raspberry Pi Pico W are propagated back to the 65C02 computer, which then presents them on a screen. This allows for a simple and consolidated view of system status and errors.

## 4. Concurrency and Timing

The parallel bus communication is fully interlocked, removing the need for software delays or complex timing management. Each byte transfer is synchronized using hardware handshaking signals.

## 5. Memory Management

*   `http_buf`: A static buffer of size `HTTP_BUF_SIZE` (32768 bytes) used for HTTP downloads.
*   LittleFS manages memory allocation and deallocation within the W25Q64 flash memory, but further investigation is required to determine the specifics.

## 6. Configuration

Wi-Fi SSID and password can be configured in `src/main.c` through the `WIFI_SSID` and `WIFI_PASSWORD` definitions.

## 7. W25Q64 Flash Usage

The filesystem utilizes the full capacity of the W25Q64 flash chip, providing the maximum available storage space.
