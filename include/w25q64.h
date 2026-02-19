#ifndef W25Q64_H
#define W25Q64_H

bool test_spi_communication(uint32_t address, uint32_t test_pattern);
void w25q_read_jedec_id(uint8_t *buffer);
#endif