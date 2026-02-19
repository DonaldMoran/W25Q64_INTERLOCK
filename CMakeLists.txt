cmake_minimum_required(VERSION 3.13)

# Set the board to Pico W to enable Wi-Fi libraries
# This must be set before project() to ensure the toolchain picks it up correctly
set(PICO_BOARD pico_w CACHE STRING "Board type" FORCE)

# Pull in the Pico SDK
include(pico_sdk_import.cmake)

project(6522_smart_device C CXX ASM)

pico_sdk_init()

add_executable(6522_smart_device
    src/main.c
    src/bus.c
    src/w25q64.c
    lib/littlefs/lfs.c
    lib/littlefs/lfs_util.c
)

pico_generate_pio_header(6522_smart_device ${CMAKE_CURRENT_LIST_DIR}/src/via_handshake.pio)

target_include_directories(6522_smart_device PRIVATE include lib/littlefs)

target_link_libraries(6522_smart_device
    pico_stdlib
    hardware_pio
    hardware_spi
    hardware_rtc
    pico_cyw43_arch_lwip_threadsafe_background
)

# ⭐ Enable USB CDC, disable UART
pico_enable_stdio_usb(6522_smart_device 1)
pico_enable_stdio_uart(6522_smart_device 0)

pico_add_extra_outputs(6522_smart_device)
