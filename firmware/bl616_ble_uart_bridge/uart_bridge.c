#include <stddef.h>
#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"
#include "stream_buffer.h"

#include "board.h"
#include "bflb_gpio.h"
#include "bflb_irq.h"
#include "bflb_uart.h"

#include "bridge_config.h"
#include "ble_nus.h"
#include "uart_bridge.h"

#define UART_TO_BLE_TASK_PRIORITY (configMAX_PRIORITIES - 4)
#define BLE_TO_UART_TASK_PRIORITY (configMAX_PRIORITIES - 4)

static struct bflb_device_s *s_uart;
static StreamBufferHandle_t s_ble_to_uart;
static StreamBufferHandle_t s_uart_to_ble;

static void uart_rx_isr(int irq, void *arg)
{
    uint8_t bytes[BRIDGE_UART_ISR_CHUNK_SIZE];
    size_t count = 0U;
    uint32_t status;
    BaseType_t higher_priority_task_woken = pdFALSE;

    (void)irq;
    (void)arg;

    status = bflb_uart_get_intstatus(s_uart);
    while (bflb_uart_rxavailable(s_uart) && count < sizeof(bytes)) {
        bytes[count++] = (uint8_t)bflb_uart_getchar(s_uart);
    }

    if ((status & UART_INTSTS_RTO) != 0U) {
        bflb_uart_int_clear(s_uart, UART_INTCLR_RTO);
    }

    if (count != 0U) {
        (void)xStreamBufferSendFromISR(s_uart_to_ble,
                                       bytes,
                                       count,
                                       &higher_priority_task_woken);
    }

    portYIELD_FROM_ISR(higher_priority_task_woken);
}

static void ble_to_uart_task(void *parameter)
{
    uint8_t bytes[128];
    size_t count;

    (void)parameter;

    for (;;) {
        count = xStreamBufferReceive(s_ble_to_uart,
                                     bytes,
                                     sizeof(bytes),
                                     portMAX_DELAY);
        if (count != 0U) {
            bflb_uart_put_block(s_uart, bytes, count);
        }
    }
}

static void uart_to_ble_task(void *parameter)
{
    uint8_t bytes[BRIDGE_BLE_NOTIFY_MAX];
    size_t count;
    size_t limit;

    (void)parameter;

    for (;;) {
        while (!ble_nus_can_notify()) {
            vTaskDelay(pdMS_TO_TICKS(10));
        }

        limit = ble_nus_notify_limit();
        if (limit == 0U || limit > sizeof(bytes)) {
            vTaskDelay(pdMS_TO_TICKS(2));
            continue;
        }

        count = xStreamBufferReceive(s_uart_to_ble,
                                     bytes,
                                     limit,
                                     pdMS_TO_TICKS(20));
        if (count == 0U) {
            continue;
        }

        while (ble_nus_can_notify() && ble_nus_notify(bytes, count) != 0) {
            vTaskDelay(pdMS_TO_TICKS(2));
        }
    }
}

int uart_bridge_init(void)
{
    struct bflb_device_s *gpio;
    struct bflb_uart_config_s config = {
        .baudrate = BRIDGE_UART_BAUDRATE,
        .direction = UART_DIRECTION_TXRX,
        .data_bits = UART_DATA_BITS_8,
        .stop_bits = UART_STOP_BITS_1,
        .parity = UART_PARITY_NONE,
        .bit_order = UART_LSB_FIRST,
        .flow_ctrl = 0,
        .tx_fifo_threshold = 7,
        .rx_fifo_threshold = 7,
    };

    s_ble_to_uart = xStreamBufferCreate(BRIDGE_STREAM_BUFFER_SIZE, 1U);
    s_uart_to_ble = xStreamBufferCreate(BRIDGE_STREAM_BUFFER_SIZE, 1U);
    if (s_ble_to_uart == NULL || s_uart_to_ble == NULL) {
        return -1;
    }

    gpio = bflb_device_get_by_name("gpio");
    s_uart = bflb_device_get_by_name("uart1");
    if (gpio == NULL || s_uart == NULL) {
        return -1;
    }

    bflb_gpio_uart_init(gpio, BRIDGE_UART_TX_PIN, GPIO_UART_FUNC_UART1_TX);
    bflb_gpio_uart_init(gpio, BRIDGE_UART_RX_PIN, GPIO_UART_FUNC_UART1_RX);
    bflb_uart_init(s_uart, &config);

    bflb_irq_attach(s_uart->irq_num, uart_rx_isr, NULL);
    bflb_irq_enable(s_uart->irq_num);
    bflb_uart_rxint_mask(s_uart, false);

    return 0;
}

size_t uart_bridge_write_from_ble(const uint8_t *data, size_t len)
{
    if (s_ble_to_uart == NULL || data == NULL || len == 0U) {
        return 0U;
    }

    /* GATT writes are atomic at the bridge boundary. Never enqueue a prefix
     * and then ask the phone to retry the whole write. */
    if (xStreamBufferSpacesAvailable(s_ble_to_uart) < len) {
        return 0U;
    }

    return xStreamBufferSend(s_ble_to_uart, data, len, 0U);
}

void uart_bridge_start_tasks(void)
{
    configASSERT(xTaskCreate(ble_to_uart_task,
                             "ble2uart",
                             512,
                             NULL,
                             BLE_TO_UART_TASK_PRIORITY,
                             NULL) == pdPASS);
    configASSERT(xTaskCreate(uart_to_ble_task,
                             "uart2ble",
                             768,
                             NULL,
                             UART_TO_BLE_TASK_PRIORITY,
                             NULL) == pdPASS);
}
