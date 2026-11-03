#ifndef XINXIAN_UART_BRIDGE_H
#define XINXIAN_UART_BRIDGE_H

#include <stddef.h>
#include <stdint.h>

int uart_bridge_init(void);
size_t uart_bridge_write_from_ble(const uint8_t *data, size_t len);
void uart_bridge_start_tasks(void);

#endif
