#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#include "board.h"
#include "btble_lib_api.h"
#include "bluetooth.h"
#include "hci_driver.h"
#include "rfparam_adapter.h"

#include "ble_nus.h"
#include "uart_bridge.h"

static void bluetooth_ready(int error)
{
    if (error != 0) {
        printf("BLE enable failed: %d\r\n", error);
        return;
    }

    ble_nus_init();
    error = ble_nus_start_advertising();
    if (error != 0) {
        printf("BLE advertising failed: %d\r\n", error);
    }
}

static void bluetooth_start_task(void *parameter)
{
    (void)parameter;

    btble_controller_init(configMAX_PRIORITIES - 1);
    hci_driver_init();
    (void)bt_enable(bluetooth_ready);

    vTaskDelete(NULL);
}

int main(void)
{
    board_init();

    configASSERT(configMAX_PRIORITIES > 4);
    configASSERT(uart_bridge_init() == 0);

    if (rfparam_init(0, NULL, 0) != 0) {
        printf("RF parameter initialization failed\r\n");
        return 0;
    }

    uart_bridge_start_tasks();
    configASSERT(xTaskCreate(bluetooth_start_task,
                             "ble_start",
                             1024,
                             NULL,
                             configMAX_PRIORITIES - 2,
                             NULL) == pdPASS);

    vTaskStartScheduler();

    for (;;) {
    }
}
