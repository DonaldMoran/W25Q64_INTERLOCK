/*
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 * Copyright (c) 2022 Donald Moran.
 * SPDX-License-Identifier: BSD-3-Clause
 *
 * This software is provided under the BSD-3-Clause license:
 * - You are free to use, modify, and distribute the code.
 * - Redistributions must retain the copyright notice, this list of conditions, and the disclaimer.
 * - The names of the project and contributors may not be used to endorse or promote products without prior permission.
 * - The software is provided "as is", without warranties or liabilities.
 */


#include <stdio.h>
#include "pico/stdlib.h"
#include "pico/time.h"
#include "hardware/clocks.h"
#include "hardware/vreg.h"
#include "hardware/gpio.h"
#include "hardware/spi.h"
#include "pico/multicore.h"
#include "pico/binary_info.h"

#define CHIPS_IMPL
#include "6502.c"
#include "6522.h"

// UART1 configuration
#define tx1  8
#define rx1  9
// UART0 configuration
#define tx0  26
#define rx0  27

//#define BAUD_RATE 19200
#define BAUD_RATE 115200

// GPIO pin definitions
#define PIN_0 0
#define PIN_1 1
#define PIN_2 2
#define PIN_3 3
#define PIN_4 4
#define PIN_5 5
#define PIN_6 6
#define PIN_7 7
#define PIN_8 8
#define PIN_9 9
#define PIN_10 10
#define PIN_11 11
#define PIN_12 12
#define PIN_13 13
#define PIN_14 14
#define PIN_15 15
#define PIN_16 16
#define PIN_17 17
#define PIN_18 18
#define PIN_19 19
#define PIN_20 20
#define PIN_21 21
#define PIN_22 22

// START of added code for VIA control lines
#define PIN_CA1 10
#define PIN_CA2 11
#define PIN_CB1 12
#define PIN_CB2 13
// END of added code for VIA control lines

//#define VIA_BASE_ADDRESS UINT16_C(0x200)
#define VIA_BASE_ADDRESS UINT16_C(0x6000)
//#define ACIA_BASE UINT16_C(0x0210)
#define ACIA_BASE UINT16_C(0x5000)

// If this is active, then an overclock will be applied
#define OVERCLOCK

// ROM configuration
#define START_DELAY 0
#define ROM_START 0x8000
#define ROM_SIZE 0x8000

#define ROM_FILE "eater.h"
#define ROM_VAR eater


#ifdef VIA_BASE_ADDRESS
m6522_t via;
uint32_t gpio_dirs;
uint32_t gpio_outs;
#define GPIO_PORTA_MASK 0xFF     // PORTA of VIA is translated to GPIO pins 0 to 7
#define GPIO_PORTB_MASK 0x7F8000 // PORTB of VIA is translated to GPIO pins 8 to 15
#define GPIO_PORTA_BASE_PIN 0
#define GPIO_PORTB_BASE_PIN 15
#endif

#include ROM_FILE
#define R_VAR ROM_VAR
#define R_START ROM_START
#define R_SIZE ROM_SIZE
uint32_t old_ticks = 0;

uint8_t mem[0x10000];
absolute_time_t start;
bool running = true;
uint64_t via_pins = 0;

// ACIA state
static uint8_t acia_cmd = 0;
static uint8_t acia_ctrl = 0;
static volatile bool acia_irq_pending = false;

// DEBUG
// [FIFO_BUFFER] START: Added circular buffer to prevent data loss during fast typing/pasting.
// The 6502 is too slow to handle USB speeds byte-by-byte without buffering.
#define RX_BUFFER_SIZE 1024
static uint8_t rx_buffer[RX_BUFFER_SIZE];
static volatile uint16_t rx_head = 0;
static volatile uint16_t rx_tail = 0;
// [FIFO_BUFFER] END

// DEBUG
static bool debug_next_callback = false;


uint8_t read_acia(uint16_t address) {
    uint8_t status = 0;
    switch (address) {
        case 0x5000: // Data register (RX)
            // [FIFO_BUFFER] START: Read from FIFO instead of single register
            if (rx_head != rx_tail) {
                uint8_t data = rx_buffer[rx_tail];
                rx_tail = (rx_tail + 1) % RX_BUFFER_SIZE;
                // If buffer is now empty, clear IRQ. Otherwise, leave it pending (Level Triggered behavior)
                if (rx_head == rx_tail) acia_irq_pending = false;
                return data;
            }
            return 0;
            // [FIFO_BUFFER] END
        case 0x5001: // Status register
            // Bit 3: RDRF (Receive Data Register Full)
            // [FIFO_BUFFER] START: Check FIFO state
            if (rx_head != rx_tail) {
                status |= (1 << 3);
            }
            // [FIFO_BUFFER] END
            // Bit 4: TDRE (Transmit Data Register Empty)
            status |= (1 << 4); // Always ready to transmit
            // Bit 7: IRQ
            if (acia_irq_pending) {
                status |= (1 << 7);
            }
            return status;
        case 0x5002: // Command register is write-only
        case 0x5003: // Control register is write-only
            return 0;
    }
    return 0; // Should not happen
}

void write_acia(uint16_t address, uint8_t value) {
    switch (address) {
        case 0x5000: // Data register (TX)
            // Send to both USB and UART1 for monitoring
            putchar(value);
            uart_putc_raw(uart1, value);
            break;
        case 0x5001: // Writing to status register is a soft reset
            acia_cmd = 0;
            acia_ctrl = 0;
            acia_irq_pending = false;
            // [FIFO_BUFFER] START: Reset FIFO on soft reset
            rx_head = 0;
            rx_tail = 0;
            // [FIFO_BUFFER] END
            break;
        case 0x5002: // Command register
            acia_cmd = value;
            break;
        case 0x5003: // Control register
            acia_ctrl = value;
            break;
    }
}

void check_acia_irq() {
    // [FIFO_BUFFER] START: Drain USB/UART into FIFO

    // 1. Drain USB/UART into FIFO
    while (true) {
        int c = PICO_ERROR_TIMEOUT;
        if (uart_is_readable(uart1)) {
            c = uart_getc(uart1);
        } else {
            c = getchar_timeout_us(0);
        }

        if (c == PICO_ERROR_TIMEOUT) break;

        uint16_t next_head = (rx_head + 1) % RX_BUFFER_SIZE;
        if (next_head != rx_tail) {
            rx_buffer[rx_head] = (uint8_t)c;
            rx_head = next_head;
        }
    }
    // [FIFO_BUFFER] END

    // Check if receive interrupts are enabled in ACIA command register
    // [FIFO_BUFFER] START: Trigger IRQ if FIFO has data
    if ((acia_cmd & 0x80) && (rx_head != rx_tail)) {
                acia_irq_pending = true;
                irq6502(); // Trigger the 6502 IRQ line
            }
    // [FIFO_BUFFER] END
}


#ifdef VIA_BASE_ADDRESS
void update_via_gpios() {
    // =========================================================================
    // PORTA (GPIO 0-7) and PORTB (GPIO 15-22) HANDLING
    // =========================================================================
    
    // Gemini: Debug tracking for direction changes
    static uint32_t prev_gpio_dirs = 0;

    // Clear previous direction settings for VIA-controlled pins
    gpio_dirs &= ~((uint32_t)GPIO_PORTA_MASK | (uint32_t)GPIO_PORTB_MASK);
    
    // Apply new direction settings from VIA DDR registers
    gpio_dirs |= (uint32_t)(via.pa.ddr << GPIO_PORTA_BASE_PIN) & (uint32_t)GPIO_PORTA_MASK;
    gpio_dirs |= (uint32_t)(via.pb.ddr << GPIO_PORTB_BASE_PIN) & (uint32_t)GPIO_PORTB_MASK;
    
    if (gpio_dirs != prev_gpio_dirs) {
        //printf("VIA DIRS CHANGED: %08X -> %08X (PA_DDR=%02X PB_DDR=%02X)\n", 
        //       prev_gpio_dirs, gpio_dirs, via.pa.ddr, via.pb.ddr);
        prev_gpio_dirs = gpio_dirs;
    }

    // Clear previous output states for VIA-controlled pins
    gpio_outs &= ~((uint32_t)GPIO_PORTA_MASK | (uint32_t)GPIO_PORTB_MASK);
    
    // Apply new output states from VIA output registers
    gpio_outs |= (uint32_t)(via.pa.outr << GPIO_PORTA_BASE_PIN) & (uint32_t)GPIO_PORTA_MASK;
    gpio_outs |= (uint32_t)(via.pb.outr << GPIO_PORTB_BASE_PIN) & (uint32_t)GPIO_PORTB_MASK;
    
    // Gemini: Safe update sequence to match hardware behavior.
    // 1. Pre-load output latches (gpio_put) BEFORE enabling output drivers.
    //    This prevents momentary glitches (driving 0) when switching from Input to Output.
    gpio_put_masked(gpio_dirs, gpio_outs);

    // 2. Apply direction settings ONLY to VIA ports (masked).
    //    Using gpio_set_dir_all_bits() here would accidentally reset UART pins to inputs.
    gpio_set_dir_masked(GPIO_PORTA_MASK | GPIO_PORTB_MASK, gpio_dirs);

    // =========================================================================
    // CONTROL LINES HANDLING - CA2 / CB2
    // =========================================================================
    
    // CA2 (GPIO 11)
    if (M6522_PCR_CA2_OUTPUT(&via)) {
        gpio_set_dir(PIN_CA2, GPIO_OUT);
        bool ca2_out = via.pa.c2_out;   // MOS 6522 uses c2_out directly
        gpio_put(PIN_CA2, ca2_out);
    } else {
        gpio_set_dir(PIN_CA2, GPIO_IN);
    }

    // CB2 (GPIO 13)
    if (M6522_PCR_CB2_OUTPUT(&via)) {
        gpio_set_dir(PIN_CB2, GPIO_OUT);
        bool cb2_out = via.pb.c2_out;   // same logic as CA2 for MOS core
        gpio_put(PIN_CB2, cb2_out);
    } else {
        gpio_set_dir(PIN_CB2, GPIO_IN);
    }

    // CA1 (GPIO 10) and CB1 (GPIO 12) remain inputs, driven externally

    // Gemini: Debug tracking for control line changes
    static int prev_ca1 = -1;
    static int prev_ca2 = -1;
    int curr_ca1 = (via_pins & M6522_CA1) ? 1 : 0;
    int curr_ca2 = (via_pins & M6522_CA2) ? 1 : 0;
    if (curr_ca1 != prev_ca1 || curr_ca2 != prev_ca2) {
        //printf("VIA CTRL CHANGED: CA1=%d CA2=%d (PCR=%02X IFR=%02X)\n", curr_ca1, curr_ca2, via.pcr, via.intr.ifr);
        prev_ca1 = curr_ca1;
        prev_ca2 = curr_ca2;
    }
}


void via_update(uint64_t pins) {
    if (pins & M6522_IRQ) {
        irq6502();
    }
}

#else

void via_update() {}

#endif

uint8_t read6502(uint16_t address) {
    if (address >= ACIA_BASE && address < ACIA_BASE + 4) {
        return read_acia(address);
    }
#ifdef VIA_BASE_ADDRESS
    else if ((address & 0xFFF0) == VIA_BASE_ADDRESS) {
        // Populate via_pins with current GPIO input states before calling m6522_tick
        uint32_t current_gpio_state = gpio_get_all();

        via_pins &= ~(M6522_PA_PINS | M6522_PB_PINS | M6522_CA1 | M6522_CA2 | M6522_CB1 | M6522_CB2);
        via_pins |= (uint64_t)((current_gpio_state >> GPIO_PORTA_BASE_PIN) & 0xFF) << 48;
        via_pins |= (uint64_t)((current_gpio_state >> GPIO_PORTB_BASE_PIN) & 0xFF) << 56;
        if (gpio_get(PIN_CA1)) via_pins |= M6522_CA1;
        if (gpio_get(PIN_CA2)) via_pins |= M6522_CA2;
        if (gpio_get(PIN_CB1)) via_pins |= M6522_CB1;
        if (gpio_get(PIN_CB2)) via_pins |= M6522_CB2;

        // Clear RW, RS pins, and CS2
        via_pins &= ~(M6522_RW | M6522_RS_PINS | M6522_CS2);

        // Set CS1 high and RW=read
        via_pins |= (M6522_CS1 | M6522_RW);

        // Correct RS decoding from low 4 bits of address
        if (address & 1) via_pins |= M6522_RS0;
        if (address & 2) via_pins |= M6522_RS1;
        if (address & 4) via_pins |= M6522_RS2;
        if (address & 8) via_pins |= M6522_RS3;

        via_pins = m6522_tick(&via, via_pins);

        update_via_gpios();
        via_update(via_pins);

        return M6522_GET_DATA(via_pins);
    }
#endif
    return mem[address];
}

void write6502(uint16_t address, uint8_t value) {
    if (address >= ACIA_BASE && address < ACIA_BASE + 4) {
        write_acia(address, value);
    }
#ifdef VIA_BASE_ADDRESS
    else if ((address & 0xFFF0) == VIA_BASE_ADDRESS) {
        // Populate via_pins with current GPIO input states before calling m6522_tick
        uint32_t current_gpio_state = gpio_get_all();
        via_pins &= ~(M6522_PA_PINS | M6522_PB_PINS | M6522_CA1 | M6522_CA2 | M6522_CB1 | M6522_CB2);
        via_pins |= (uint64_t)((current_gpio_state >> GPIO_PORTA_BASE_PIN) & 0xFF) << 48;
        via_pins |= (uint64_t)((current_gpio_state >> GPIO_PORTB_BASE_PIN) & 0xFF) << 56;
        if (gpio_get(PIN_CA1)) via_pins |= M6522_CA1;
        if (gpio_get(PIN_CA2)) via_pins |= M6522_CA2;
        if (gpio_get(PIN_CB1)) via_pins |= M6522_CB1;
        if (gpio_get(PIN_CB2)) via_pins |= M6522_CB2;

        // Clear RW, RS pins, and CS2
        via_pins &= ~(M6522_RW | M6522_RS_PINS | M6522_CS2);

        // Set CS1 high, RW=write (RW=0)
        via_pins |= M6522_CS1;

        // Correct RS decoding from low 4 bits of address
        if (address & 1) via_pins |= M6522_RS0;
        if (address & 2) via_pins |= M6522_RS1;
        if (address & 4) via_pins |= M6522_RS2;
        if (address & 8) via_pins |= M6522_RS3;

        M6522_SET_DATA(via_pins, value);
        via_pins = m6522_tick(&via, via_pins);

        update_via_gpios();
        via_update(via_pins);
        
        // DEBUG: only when writing to PORTA
        //if ((address & 0x000F) == 1) {
        //     uint8_t porta_out = via.pa.outr;
        //     uint8_t ddra = via.pa.ddr;
        //     uint32_t g = gpio_get_all();
        //     printf("DBG VIA: ORA=%02X DDRA=%02X GPIO0-7=%02X dirs=%08X outs=%08X\n", 
        //     porta_out, 
        //     ddra, (uint8_t)(g & 0xFF), 
        //     gpio_dirs, 
        //     gpio_outs); 
        //    // ⭐ NEW: trigger one-time callback debug 
        //    debug_next_callback = true;
        //}        
    }
#endif
    else {
        mem[address] = value;
    }
}

void callback() {
#ifdef VIA_BASE_ADDRESS
    // Read current GPIO states before ticking VIA
    uint32_t current_gpio_state = gpio_get_all();


    // Start with base pins (preserving internal state flags)
    uint64_t tick_pins = via_pins & ~(M6522_PA_PINS | M6522_PB_PINS |
                                      M6522_CA1 | M6522_CA2 |
                                      M6522_CB1 | M6522_CB2);

    // Update with current GPIO input states
    tick_pins |= (uint64_t)((current_gpio_state >> GPIO_PORTA_BASE_PIN) & 0xFF) << 48;
    tick_pins |= (uint64_t)((current_gpio_state >> GPIO_PORTB_BASE_PIN) & 0xFF) << 56;

    // Update control lines from GPIO (CA1/CB1 driven by bridge)
    if (gpio_get(PIN_CA1)) tick_pins |= M6522_CA1;
    if (gpio_get(PIN_CA2)) tick_pins |= M6522_CA2;
    if (gpio_get(PIN_CB1)) tick_pins |= M6522_CB1;
    if (gpio_get(PIN_CB2)) tick_pins |= M6522_CB2;

    // De-assert chip selects for non-access ticks
    tick_pins &= ~(M6522_CS1 | M6522_CS2);

    // Gemini: Force RW high (Read mode) during idle ticks.
    // This prevents inadvertent writes to registers (like DDRA/DDRB) if RS pins
    // are left selecting them from a previous instruction.
    tick_pins |= M6522_RW;

    // Gemini: Determine which control lines are inputs to enforce them in the loop.
    // CA1 and CB1 are ALWAYS inputs.
    uint64_t input_mask = M6522_CA1 | M6522_CB1;
    
    // CA2 and CB2 are inputs if not configured as outputs in PCR
    if (!M6522_PCR_CA2_OUTPUT(&via)) input_mask |= M6522_CA2;
    if (!M6522_PCR_CB2_OUTPUT(&via)) input_mask |= M6522_CB2;

    // Capture the stable input state from the initial GPIO read (tick_pins has it)
    uint64_t stable_inputs = tick_pins & input_mask;

    // Tick VIA for each clock cycle since last callback
    for (uint16_t i = 0; i < clockticks6502 - old_ticks; i++) {
        // Gemini: Enforce physical input state. 
        // m6522_tick return value might not preserve undriven input bits,
        // so we must re-apply them to prevent false edges (0->1->0) inside the loop.
        tick_pins &= ~input_mask;
        tick_pins |= stable_inputs;
        
        tick_pins = m6522_tick(&via, tick_pins);
    }

    //if (debug_next_callback) {
    //    printf("CALLBACK VIA ORA=%02X DDRA=%02X\n", via.pa.outr, via.pa.ddr);
    //    debug_next_callback = false;
    //}


    // Save updated state back to global variable
    via_pins = tick_pins;

    // Update GPIO outputs based on VIA's new state
    update_via_gpios();

    // Check for interrupts
    if (tick_pins & M6522_IRQ) {
        irq6502();
    }

    old_ticks = clockticks6502;
#endif
}



int main() {

#ifdef OVERCLOCK
    vreg_set_voltage(VREG_VOLTAGE_1_20); // Safer for 280 MHz
    sleep_ms(1000);
    set_sys_clock_khz(270000, true);
#endif

    // Initialize USB only (skip UART initialization)
    stdio_usb_init();
    sleep_ms(2000); // Add delay for USB to initialize

    // Explicitly set UART pins
    uart_init(uart0, BAUD_RATE);
    uart_init(uart1, BAUD_RATE);

    gpio_set_function(tx0, GPIO_FUNC_UART);
    gpio_set_function(rx0, GPIO_FUNC_UART);
    uart_set_hw_flow(uart0, false, false);
    uart_set_fifo_enabled(uart0, false);
    uart_set_format(uart0, 8, 1, UART_PARITY_NONE);


    gpio_set_function(tx1, GPIO_FUNC_UART);
    gpio_set_function(rx1, GPIO_FUNC_UART);
    uart_set_hw_flow(uart1, false, false);
    uart_set_fifo_enabled(uart1, false);
    uart_set_format(uart1, 8, 1, UART_PARITY_NONE);

    printf("DEBUG: main() is running\n");


    if (R_START + R_SIZE > 0x10000) {
        printf("Your rom will not fit. Either adjust ROM_START or ROM_SIZE\n");
        while (1) {}
    }
    for (int i = R_START; i < R_SIZE + R_START; i++) {
        mem[i] = R_VAR[i - R_START];
    }

    hookexternal(callback);
    reset6502();

#ifdef VIA_BASE_ADDRESS
    /******************************************************************************
    * VIA CONTROL LINES INITIALIZATION - IMPORTANT DESIGN DECISION
    * 
    * All control lines (CA1, CA2, CB1, CB2) are initialized WITHOUT pull-up/down.
    * 
    * Reasons:
    * 1. OUTPUT MODE: When CA2/CB2 are outputs (PCR bits 3/7 = 1), pull resistors
    *    create voltage dividers that fight the GPIO drivers, especially for
    *    brief pulses in handshake mode.
    *    
    * 2. INPUT MODE: External devices should provide proper drive or pull resistors.
    *    The VIA has internal weak pull-ups on some inputs, but we emulate that
    *    in software, not with GPIO hardware pulls.
    *    
    * 3. NOISE IMMUNITY: If needed, add external 4.7kΩ-10kΩ pull-up resistors.
    *    This gives better control than internal GPIO pulls (approx. 50kΩ).
    *    
    * 4. CONSISTENCY: All four control lines behave the same way, avoiding
    *    asymmetrical behavior that could cause debugging confusion.
    * 
    * Note: CA1 and CB1 are input-only on the VIA, but we still disable pulls
    *       for consistency and to avoid any potential GPIO driver conflicts.
    ******************************************************************************/
    m6522_init(&via);
    m6522_reset(&via);
    
    // Gemini: Real 6522 Reset clears DDRs, setting all port pins to Inputs (High-Z).
    // We initialize as Inputs (0) here to match hardware and prevent bus contention.
    // (Previous code set them to Outputs, which risks shorting against external devices).
    gpio_init_mask(GPIO_PORTB_MASK | GPIO_PORTA_MASK);
    gpio_dirs = 0;
    gpio_outs = 0;
    gpio_set_dir_masked(GPIO_PORTB_MASK | GPIO_PORTA_MASK, gpio_dirs);

    // START of added code for VIA control lines
    gpio_init(PIN_CA1);
    gpio_set_dir(PIN_CA1, GPIO_IN);
    gpio_disable_pulls(PIN_CA1);
    
    gpio_init(PIN_CA2);
    gpio_set_dir(PIN_CA2, GPIO_IN);
    gpio_disable_pulls(PIN_CA2);  
    
    gpio_init(PIN_CB1);
    gpio_set_dir(PIN_CB1, GPIO_IN);
    gpio_disable_pulls(PIN_CB1);

    gpio_init(PIN_CB2);
    gpio_set_dir(PIN_CB2, GPIO_IN);
    gpio_disable_pulls(PIN_CB2);
    // END of added code for VIA control lines


#endif

    start = get_absolute_time();
    while (running) {
        step6502();
        check_acia_irq();
    }
    
    return 0;
}
