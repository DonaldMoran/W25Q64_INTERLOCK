#include <stdio.h>
#include "pico/stdlib.h"
#include "hardware/spi.h"
#include "lfs.h"
#include "../include/w25q64.h"

// --- HARDWARE CONFIGURATION ---
#define SPI_PORT spi0
#define PIN_MISO 16
#define PIN_CS   17
#define PIN_SCK  18
#define PIN_MOSI 19

// W25Q64 Commands
#define CMD_READ      0x03
#define CMD_PROG      0x02
#define CMD_ERASE_4K  0x20
#define CMD_WREN      0x06
#define CMD_WRDI      0x04
#define CMD_RDSR      0x05 // Read Status Register
#define CMD_JEDEC_ID  0x9F

// --- LOW LEVEL SPI HELPERS ---

static void cs_select() {
    asm volatile("nop \n nop \n nop");
    gpio_put(PIN_CS, 0);
    asm volatile("nop \n nop \n nop");

}

static void cs_deselect() {
    asm volatile("nop \n nop \n nop");
    gpio_put(PIN_CS, 1);
    asm volatile("nop \n nop \n nop");
}

void w25q_read_jedec_id(uint8_t *buffer) {
    uint8_t cmd = CMD_JEDEC_ID;
    cs_select();
    spi_write_blocking(SPI_PORT, &cmd, 1);
    spi_read_blocking(SPI_PORT, 0, buffer, 3);
    cs_deselect();
}

static void wait_busy(void) {
    uint8_t cmd = CMD_RDSR;
  uint8_t status;
    do {
        cs_select();
        spi_write_blocking(SPI_PORT, &cmd, 1);
        spi_read_blocking(SPI_PORT, 0, &status, 1);
        cs_deselect();
    } while (status & 0x01); // WIP bit


}


static void write_enable() {
    uint8_t cmd = CMD_WREN;
    cs_select();
    spi_write_blocking(SPI_PORT, &cmd, 1);
    cs_deselect();
}

// --- LITTLEFS CALLBACKS ---

int w25q_read(const struct lfs_config *c, lfs_block_t block, lfs_off_t off, void *buffer, lfs_size_t size) {
    uint8_t cmd[4];
    uint32_t addr = (block * c->block_size) + off;
    
    cmd[0] = CMD_READ;
    cmd[1] = (addr >> 16) & 0xFF;
    cmd[2] = (addr >> 8) & 0xFF;
    cmd[3] = addr & 0xFF;

    cs_select();
    spi_write_blocking(SPI_PORT, cmd, 4);
    spi_read_blocking(SPI_PORT, 0, (uint8_t*)buffer, size);
    cs_deselect();
    
    return LFS_ERR_OK;
}

int w25q_prog(const struct lfs_config *c, lfs_block_t block, lfs_off_t off, const void *buffer, lfs_size_t size) {
    uint8_t cmd[4];
    uint32_t addr = (block * c->block_size) + off;

    write_enable();
    
    cmd[0] = CMD_PROG;
    cmd[1] = (addr >> 16) & 0xFF;
    cmd[2] = (addr >> 8) & 0xFF;
    cmd[3] = addr & 0xFF;

    cs_select();
    spi_write_blocking(SPI_PORT, cmd, 4);
    spi_write_blocking(SPI_PORT, (const uint8_t*)buffer, size);
    cs_deselect();

    wait_busy();
    return LFS_ERR_OK;
}

int w25q_erase(const struct lfs_config *c, lfs_block_t block) {
    uint8_t cmd[4];
    uint32_t addr = block * c->block_size;

    write_enable();

    cmd[0] = CMD_ERASE_4K;
    cmd[1] = (addr >> 16) & 0xFF;
    cmd[2] = (addr >> 8) & 0xFF;
    cmd[3] = addr & 0xFF;

    cs_select();
    spi_write_blocking(SPI_PORT, cmd, 4);
    cs_deselect();

    wait_busy();
    return LFS_ERR_OK;
}

int w25q_sync(const struct lfs_config *c) {
    return LFS_ERR_OK;
}

// Verification function - now non-static and declared in header
bool test_spi_communication(uint32_t address, uint32_t test_pattern) {
    uint32_t read_value;
    uint8_t cmd[4];

    // Write the test pattern to the specified address
    write_enable();
    cmd[0] = CMD_PROG;
    cmd[1] = (address >> 16) & 0xFF;
    cmd[2] = (address >> 8) & 0xFF;
    cmd[3] = address & 0xFF;
    cs_select();
    spi_write_blocking(SPI_PORT, cmd, 4);
    spi_write_blocking(SPI_PORT, (const uint8_t*)&test_pattern, sizeof(test_pattern));
    cs_deselect();
    wait_busy();

    // Read back the value and compare
    cmd[0] = CMD_READ;
    cmd[1] = (address >> 16) & 0xFF;
    cmd[2] = (address >> 8) & 0xFF;
    cmd[3] = address & 0xFF;
    cs_select();
    spi_write_blocking(SPI_PORT, cmd, 4);
    spi_read_blocking(SPI_PORT, 0, (uint8_t*)&read_value, sizeof(read_value));
    cs_deselect();

    return (read_value == test_pattern);
}

// --- PUBLIC INIT ---

void w25q_init_hardware() {
    spi_init(SPI_PORT, 10 * 1000 * 1000); // 10 MHz
  gpio_set_function(PIN_MISO, GPIO_FUNC_SPI);
  gpio_set_function(PIN_SCK,  GPIO_FUNC_SPI);
  gpio_set_function(PIN_MOSI, GPIO_FUNC_SPI);

    gpio_init(PIN_CS);
    gpio_set_dir(PIN_CS, GPIO_OUT);
    gpio_put(PIN_CS, 1);
}

// Configuration struct for LittleFS
struct lfs_config w25q_cfg = {
    .read  = w25q_read,
    .prog  = w25q_prog,
    .erase = w25q_erase,
    .sync  = w25q_sync,
    .read_size = 1,
    .prog_size = 256,
    .block_size = 4096,
    .block_count = 2048, // 8MB / 4KB
    .cache_size = 256,
    .lookahead_size = 16,
    .block_cycles = 500,
};