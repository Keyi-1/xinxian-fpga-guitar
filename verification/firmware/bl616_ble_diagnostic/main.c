#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "FreeRTOS.h"
#include "task.h"
#include "board.h"
#include "bl616_hbn.h"
#include "btble_lib_api.h"
#include "bluetooth.h"
#include "conn.h"
#include "conn_internal.h"
#include "hci_driver.h"
#include "rfparam_adapter.h"
#include "shell.h"
#include "wl_api.h"

/* Independent scan/boot diagnostic. Does not initialize the FPGA UART. */
static volatile int stage = 1;
static volatile int rf_error = -999;
static volatile int host_error = -999;
static volatile int ready_error = -999;
static volatile int adv_error = -999;
static volatile unsigned connections;
static volatile unsigned disconnects;
static volatile unsigned disconnect_reason;
static volatile int retry_advertising;
static uint32_t xtal_hz;
static TaskHandle_t start_handle;
static int keep_startup_capcode;
static int8_t (*original_param_load)(struct wl_param_t *);
static void (*original_capcode_set)(uint8_t, uint8_t);

static void checkpoint(const char *message)
{
    printf("XINXIAN-TRACE %s\r\n", message);
    /* Let the USB task drain before changing the crystal or entering PHY. */
    vTaskDelay(pdMS_TO_TICKS(200));
}

static int8_t traced_param_load(struct wl_param_t *param)
{
    int8_t result = original_param_load(param);
    printf("XINXIAN-TRACE param_load returned %d\r\n", result);
    checkpoint("parameter load complete");
    return result;
}

static void traced_capcode_set(uint8_t in, uint8_t out)
{
    uint8_t before_in = 0, before_out = 0;
    struct wl_cfg_t *cfg = rfparam_cfg_get();
    cfg->capcode_get(&before_in, &before_out);
    printf("XINXIAN-TRACE capcode current=%u/%u requested=%u/%u keep=%d\r\n",
           before_in, before_out, in, out, keep_startup_capcode);
    checkpoint("before capcode update");
    if (!keep_startup_capcode) {
        original_capcode_set(in, out);
    }
    checkpoint("after capcode update; entering PHY next");
}

int8_t __real_wl_init(void);
int8_t __wrap_wl_init(void)
{
    struct wl_cfg_t *cfg = rfparam_cfg_get();
    original_param_load = cfg->param_load;
    original_capcode_set = cfg->capcode_set;
    cfg->param_load = traced_param_load;
    cfg->capcode_set = traced_capcode_set;
    /* Pinned PHY wl_logger passes (format, va_list), verified in its ELF.
       Its header declares a variadic callback, but printf is NOT ABI-correct. */
    cfg->log_printf = (int (*)(const char *, ...))vprintf;
    cfg->log_level = WL_LOG_LEVEL_DEBUG;
    printf("XINXIAN-TRACE PHY=%s mode=%u keep_cap=%d\r\n",
           wl_get_version(), cfg->mode, keep_startup_capcode);
    checkpoint("before wl_init");
    int8_t result = __real_wl_init();
    printf("XINXIAN-TRACE wl_init returned %d\r\n", result);
    return result;
}

static void print_status(void)
{
    printf("XINXIAN-DIAG v3 xtal=%lu stage=%d rf=%d host=%d ready=%d adv=%d connected=%u disconnected=%u reason=%u\r\n",
           (unsigned long)xtal_hz, stage, rf_error, host_error, ready_error,
           adv_error, connections, disconnects, disconnect_reason);
}

static void request_start(int preserve_capcode)
{
    if (stage == 1 && start_handle != NULL) {
        keep_startup_capcode = preserve_capcode;
        printf("Starting BLE keep_cap=%d\r\n", keep_startup_capcode);
        xTaskNotifyGive(start_handle);
    } else {
        print_status();
    }
}
static void cmd_ble_start(int argc, char **argv)
{
    (void)argc; (void)argv;
    request_start(0);
}
SHELL_CMD_EXPORT_ALIAS(cmd_ble_start, ble_start, trace standard RF startup);

static void cmd_ble_keepcap(int argc, char **argv)
{
    (void)argc; (void)argv;
    request_start(1);
}
SHELL_CMD_EXPORT_ALIAS(cmd_ble_keepcap, ble_keepcap, preserve startup crystal capcode);

static int start_advertising(void)
{
    static const char name[] = "XINXIAN-DIAG";
    const struct bt_data data[] = {
        BT_DATA_BYTES(BT_DATA_FLAGS, BT_LE_AD_NO_BREDR | BT_LE_AD_GENERAL),
        BT_DATA(BT_DATA_NAME_COMPLETE, name, sizeof(name) - 1),
    };
    struct bt_le_adv_param param;
    memset(&param, 0, sizeof(param));
    param.options = BT_LE_ADV_OPT_CONNECTABLE | BT_LE_ADV_OPT_ONE_TIME;
    param.interval_min = BT_GAP_ADV_FAST_INT_MIN_2;
    param.interval_max = BT_GAP_ADV_FAST_INT_MAX_2;
    return bt_le_adv_start(&param, data, ARRAY_SIZE(data), NULL, 0);
}

static void connected(struct bt_conn *conn, u8_t error)
{
    (void)conn;
    if (error == 0) {
        connections++;
    } else {
        retry_advertising = 1;
    }
}

static void disconnected(struct bt_conn *conn, u8_t reason)
{
    (void)conn;
    disconnect_reason = reason;
    disconnects++;
    retry_advertising = 1;
}

static struct bt_conn_cb callbacks = {
    .connected = connected,
    .disconnected = disconnected,
};

static void ready(int error)
{
    ready_error = error;
    stage = error == 0 ? 6 : -6;
    if (error != 0) {
        return;
    }
    bt_conn_cb_register(&callbacks);
    (void)bt_set_name("XINXIAN-DIAG");
    adv_error = start_advertising();
    stage = adv_error == 0 ? 7 : -7;
}

static void start_task(void *unused)
{
    (void)unused;
    /* USB must be observable before any closed RF/controller init runs. */
    (void)ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
    stage = 2;
    print_status();
    vTaskDelay(pdMS_TO_TICKS(100));
    rf_error = rfparam_init(0, NULL, 0);
    if (rf_error != 0) {
        stage = -2;
        vTaskDelete(NULL);
        return;
    }
    stage = 3;
    print_status();
    vTaskDelay(pdMS_TO_TICKS(100));
    btble_controller_init(configMAX_PRIORITIES - 1);
    stage = 4;
    print_status();
    vTaskDelay(pdMS_TO_TICKS(100));
    hci_driver_init();
    stage = 5;
    print_status();
    vTaskDelay(pdMS_TO_TICKS(100));
    host_error = bt_enable(ready);
    if (host_error != 0) {
        stage = -5;
    }
    vTaskDelete(NULL);
}

static void report_task(void *unused)
{
    (void)unused;
    for (;;) {
        if (retry_advertising) {
            retry_advertising = 0;
            adv_error = start_advertising();
            if (adv_error != 0) {
                retry_advertising = 1;
            }
        }
        print_status();
        vTaskDelay(pdMS_TO_TICKS(2000));
    }
}

int main(void)
{
    board_init();
    HBN_Get_Xtal_Value(&xtal_hz);
    configASSERT(xTaskCreate(report_task, "diag_log", 1024, NULL, 2, NULL) == pdPASS);
    configASSERT(xTaskCreate(start_task, "diag_ble", 4096, NULL,
                             configMAX_PRIORITIES - 2, &start_handle) == pdPASS);
    vTaskStartScheduler();
    for (;;) {}
}
