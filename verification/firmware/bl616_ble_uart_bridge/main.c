#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#include "board.h"
#include "btble_lib_api.h"
#include "bluetooth.h"
#include "hci_driver.h"
#include "rfparam_adapter.h"
#include "bl616_hbn.h"

#include "ble_nus.h"
#include "uart_bridge.h"

static void bluetooth_ready(int error)
{
    if (error != 0) {
        printf("BLE enable failed: %d\r\n", error);
        return;
    }

    error = ble_nus_init();
    if (error != 0) {
        printf("BLE service registration failed: %d\r\n", error);
        return;
    }
    error = ble_nus_start_advertising();
    if (error != 0) {
        printf("BLE advertising failed: %d\r\n", error);
    }
}

static void bluetooth_start_task(void *parameter)
{
    int error;
    (void)parameter;

    btble_controller_init(configMAX_PRIORITIES - 1);
    hci_driver_init();
    error = bt_enable(bluetooth_ready);
    if (error != 0) {
        printf("BLE host initialization failed: %d\r\n", error);
    }

    vTaskDelete(NULL);
}

int main(void)
{
    uint32_t xtal_hz = 0;
    board_init();

    HBN_Get_Xtal_Value(&xtal_hz);
    configASSERT(xtal_hz == 26000000U);

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
