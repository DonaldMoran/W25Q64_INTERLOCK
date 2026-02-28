#include <stdio.h>
#include "pico/stdlib.h"
#include "hardware/pio.h"
// Include the header generated from our unified PIO file
#include "via_handshake.pio.h"
#include "bus.h"

#define PIO_INST   pio0
#define RX_SM      0
#define TX_SM      1

#define DATA_BASE  6    // GPIO6..13
#define CA2_PIN    14   // VIA CA2 -> Pico
#define CA1_PIN    15   // Pico -> VIA CA1

void bus_init(void) {
    // ============================================================
    PIO pio = PIO_INST;

    // ============================================================
    // 2. Assign pins to PIO
    //    Use Real Hardware settings (Slew Rate/Drive Strength)
    //    These are ignored by Emulator but vital for Real HW.
    // ============================================================
    for (int i = 0; i < 8; i++) {
        uint pin = DATA_BASE + i;
        pio_gpio_init(pio, pin);
        gpio_set_slew_rate(pin, GPIO_SLEW_RATE_SLOW);
        gpio_set_drive_strength(pin, GPIO_DRIVE_STRENGTH_4MA);
        gpio_pull_down(pin); // Ensure bus reads 0x00 when 6502 is High-Z (Sync)
    }
    pio_gpio_init(pio, CA2_PIN);
    pio_gpio_init(pio, CA1_PIN);
    gpio_set_slew_rate(CA1_PIN, GPIO_SLEW_RATE_SLOW);
    gpio_set_drive_strength(CA1_PIN, GPIO_DRIVE_STRENGTH_4MA);

    // ============================================================
    // 3. RX STATE MACHINE (6502 -> Pico)
    // ============================================================
    pio_sm_set_consecutive_pindirs(pio, RX_SM, DATA_BASE, 8, false);
    pio_sm_set_consecutive_pindirs(pio, RX_SM, CA2_PIN, 1, false);
    pio_sm_set_consecutive_pindirs(pio, RX_SM, CA1_PIN, 1, true);

    uint offset_rx = pio_add_program(pio, &via_handshake_rx_program);
    pio_sm_config c_rx = via_handshake_rx_program_get_default_config(offset_rx);

    sm_config_set_in_pins(&c_rx, DATA_BASE);
    sm_config_set_jmp_pin(&c_rx, CA2_PIN);
    sm_config_set_set_pins(&c_rx, CA1_PIN, 1);
    sm_config_set_in_shift(&c_rx, false, true, 8);
    
    // Use FAST Clock (10MHz) for precision timing defined in PIO
    sm_config_set_clkdiv(&c_rx, 12.5f);

    pio_sm_init(pio, RX_SM, offset_rx, &c_rx);
    pio_sm_set_enabled(pio, RX_SM, false);

    // ============================================================
    // 4. TX STATE MACHINE (Pico -> 6502)
    // ============================================================
    uint offset_tx = pio_add_program(pio, &via_handshake_tx_program);
    pio_sm_config c_tx = via_handshake_tx_program_get_default_config(offset_tx);

    sm_config_set_out_pins(&c_tx, DATA_BASE, 8);
    sm_config_set_in_pins(&c_tx, DATA_BASE); // Used for WAIT instruction (CA2 is at index 8)
    sm_config_set_set_pins(&c_tx, CA1_PIN, 1);
    sm_config_set_out_shift(&c_tx, true, false, 32);
    
    // Use FAST Clock (10MHz)
    sm_config_set_clkdiv(&c_tx, 12.5f);

    pio_sm_init(pio, TX_SM, offset_tx, &c_tx);

    // ============================================================
    // 5. Put CA1 into BUSY state (Low) until Main Loop is ready
    // ============================================================
    pio_sm_set_pins_with_mask(pio, TX_SM, 0, 1u << CA1_PIN); // Drive Low
    pio_sm_set_pindirs_with_mask(pio, TX_SM, 1u << CA1_PIN, 1u << CA1_PIN);
    pio_sm_set_enabled(pio, TX_SM, false);

    printf("Unified Bus Initialized (Mode C, Fast Clock, Robust Handshake)\n");
}

uint8_t bus_read_byte(void) {
    pio_sm_set_enabled(PIO_INST, TX_SM, false);
    pio_sm_set_consecutive_pindirs(PIO_INST, RX_SM, DATA_BASE, 8, false);
    
    // Strict Handover: TX stops driving CA1, RX starts driving CA1
    pio_sm_set_consecutive_pindirs(PIO_INST, TX_SM, CA1_PIN, 1, false);
    pio_sm_set_pins_with_mask(PIO_INST, RX_SM, 1u << CA1_PIN, 1u << CA1_PIN); // Pre-set High
    pio_sm_set_consecutive_pindirs(PIO_INST, RX_SM, CA1_PIN, 1, true);

    // REMOVED: pio_sm_clear_fifos(PIO_INST, RX_SM);
    // REMOVED: pio_sm_restart(PIO_INST, RX_SM);
    pio_sm_set_enabled(PIO_INST, RX_SM, true);

    uint32_t raw = pio_sm_get_blocking(PIO_INST, RX_SM);
    pio_sm_get_blocking(PIO_INST, RX_SM); // Wait for Handshake Completion Token

    pio_sm_set_enabled(PIO_INST, RX_SM, false);

    // FIX: Handover to TX_SM to actively drive CA1 High (Idle).
    // This prevents CA1 from floating (and causing phantom reads on 6502)
    // while the Pico is busy processing (e.g., writing to Flash).
    pio_sm_set_consecutive_pindirs(PIO_INST, RX_SM, CA1_PIN, 1, false);
    pio_sm_set_pins_with_mask(PIO_INST, TX_SM, 1u << CA1_PIN, 1u << CA1_PIN); // Force High
    pio_sm_set_consecutive_pindirs(PIO_INST, TX_SM, CA1_PIN, 1, true);        // Drive Output
    // REMOVED: pio_sm_restart(PIO_INST, TX_SM);                              // Reset to Idle
    pio_sm_set_enabled(PIO_INST, TX_SM, true);                                // Enable Drive

    return (uint8_t)raw;
}

void bus_write_byte(uint8_t b) {
    pio_sm_set_enabled(PIO_INST, RX_SM, false);

    // Strict Handover: RX stops driving CA1, TX starts driving CA1
    pio_sm_set_consecutive_pindirs(PIO_INST, RX_SM, CA1_PIN, 1, false);
    pio_sm_set_pins_with_mask(PIO_INST, TX_SM, 1u << CA1_PIN, 1u << CA1_PIN); // Pre-set High
    pio_sm_set_consecutive_pindirs(PIO_INST, TX_SM, CA1_PIN, 1, true);

    pio_sm_set_consecutive_pindirs(PIO_INST, TX_SM, DATA_BASE, 8, true);

    // Ensure SM is enabled (it should be waiting at 'pull' from previous wrap)
    // No need to restart, which can cause glitches.
    pio_sm_set_enabled(PIO_INST, TX_SM, true);

    pio_sm_put_blocking(PIO_INST, TX_SM, b);
    pio_sm_get_blocking(PIO_INST, TX_SM); // Wait for completion

    // CRITICAL FIX: Do NOT disable the SM here.
    // Leaving it enabled ensures CA1 is actively driven High (Idle) and
    // the Data Bus is actively driven (Last Byte) during the sleep_ms(5)
    // pacing delay. Disabling it would cause the bus to float (Phantom Bytes).
}

void bus_reset_handshake(void) {
    pio_sm_set_enabled(PIO_INST, RX_SM, false);
    pio_sm_set_enabled(PIO_INST, TX_SM, false);

    for (int i = 0; i < 8; i++) pio_gpio_init(PIO_INST, DATA_BASE + i);
    
    pio_sm_set_consecutive_pindirs(PIO_INST, RX_SM, DATA_BASE, 8, false);
    pio_sm_set_consecutive_pindirs(PIO_INST, TX_SM, DATA_BASE, 8, false);
    pio_sm_set_consecutive_pindirs(PIO_INST, RX_SM, CA1_PIN, 1, false);
    pio_sm_set_consecutive_pindirs(PIO_INST, TX_SM, CA1_PIN, 1, false);

    // CA2 as input (we only read it)
    pio_gpio_init(PIO_INST, CA2_PIN); // Keep assigned to PIO
    gpio_pull_down(CA2_PIN); // Ensure CA2 doesn't float high (spurious Start)
    
    pio_gpio_init(PIO_INST, CA1_PIN); // Keep assigned to PIO
    gpio_pull_up(CA1_PIN); // Ensure CA1 doesn't float low (spurious IRQ)

    sleep_ms(5);
}
