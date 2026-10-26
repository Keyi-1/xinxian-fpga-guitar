#ifndef XINXIAN_BLE_NUS_H
#define XINXIAN_BLE_NUS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

int ble_nus_init(void);
int ble_nus_start_advertising(void);
bool ble_nus_can_notify(void);
size_t ble_nus_notify_limit(void);
int ble_nus_notify(const uint8_t *data, size_t len);

#endif
