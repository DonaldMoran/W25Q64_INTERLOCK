#ifndef BUS_H
#define BUS_H

#include <stdint.h>

void bus_init(void);
uint8_t bus_read_byte(void);
void bus_write_byte(uint8_t b);
void bus_reset_handshake(void);

#endif