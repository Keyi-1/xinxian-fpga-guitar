#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include "bluetooth.h"
#include "conn.h"
#include "conn_internal.h"
#include "gatt.h"
#include "att.h"
#include "bt_uuid.h"
#include "hci_core.h"

#include "bridge_config.h"
#include "uart_bridge.h"
#include "ble_nus.h"

#define NUS_TX_VALUE_ATTR_INDEX 4

#define BT_UUID_NUS_SERVICE \
    BT_UUID_DECLARE_128(BT_UUID_128_ENCODE(0x6e400001, 0xb5a3, 0xf393, 0xe0a9, 0xe50e24dcca9e))
#define BT_UUID_NUS_RX \
    BT_UUID_DECLARE_128(BT_UUID_128_ENCODE(0x6e400002, 0xb5a3, 0xf393, 0xe0a9, 0xe50e24dcca9e))
#define BT_UUID_NUS_TX \
    BT_UUID_DECLARE_128(BT_UUID_128_ENCODE(0x6e400003, 0xb5a3, 0xf393, 0xe0a9, 0xe50e24dcca9e))

static struct bt_conn *s_connection;
static volatile bool s_notify_enabled;

static int nus_rx_write(struct bt_conn *conn,
                        const struct bt_gatt_attr *attr,
                        const void *buf,
                        u16_t len,
                        u16_t offset,
                        u8_t flags)
{
    size_t accepted;

    (void)conn;
    (void)attr;

    if ((flags & BT_GATT_WRITE_FLAG_PREPARE) != 0U || offset != 0U) {
        return BT_GATT_ERR(BT_ATT_ERR_NOT_SUPPORTED);
    }

    accepted = uart_bridge_write_from_ble((const uint8_t *)buf, len);
    if (accepted != len) {
        return BT_GATT_ERR(BT_ATT_ERR_INSUFFICIENT_RESOURCES);
    }

    return len;
}

static void nus_tx_ccc_changed(const struct bt_gatt_attr *attr, u16_t value)
{
    (void)attr;
    s_notify_enabled = (value == BT_GATT_CCC_NOTIFY);
}

static struct bt_gatt_attr s_nus_attrs[] = {
    BT_GATT_PRIMARY_SERVICE(BT_UUID_NUS_SERVICE),

    BT_GATT_CHARACTERISTIC(BT_UUID_NUS_RX,
                           BT_GATT_CHRC_WRITE | BT_GATT_CHRC_WRITE_WITHOUT_RESP,
                           BT_GATT_PERM_WRITE,
                           NULL,
                           nus_rx_write,
                           NULL),

    BT_GATT_CHARACTERISTIC(BT_UUID_NUS_TX,
                           BT_GATT_CHRC_NOTIFY,
                           0,
                           NULL,
                           NULL,
                           NULL),

    BT_GATT_CCC(nus_tx_ccc_changed, BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
};

static struct bt_gatt_service s_nus_service = BT_GATT_SERVICE(s_nus_attrs);

static void ble_connected(struct bt_conn *conn, u8_t err)
{
    if (err != 0U || conn->type != BT_CONN_TYPE_LE) {
        return;
    }

    s_connection = conn;
    s_notify_enabled = false;

    /* Larger packets reduce BLE overhead. Failure is harmless: ATT MTU 23 remains valid. */
    (void)bt_le_set_data_len(conn, 0x00fb, 0x0848);
}

static void ble_disconnected(struct bt_conn *conn, u8_t reason)
{
    (void)reason;

    if (conn->type != BT_CONN_TYPE_LE) {
        return;
    }

    s_notify_enabled = false;
    s_connection = NULL;
    (void)ble_nus_start_advertising();
}

static struct bt_conn_cb s_connection_callbacks = {
    .connected = ble_connected,
    .disconnected = ble_disconnected,
};

void ble_nus_init(void)
{
    bt_conn_cb_register(&s_connection_callbacks);
    bt_gatt_service_register(&s_nus_service);
}

int ble_nus_start_advertising(void)
{
    static const uint8_t service_uuid[] = {
        BT_UUID_128_ENCODE(0x6e400001, 0xb5a3, 0xf393, 0xe0a9, 0xe50e24dcca9e)
    };
    static const char device_name[] = BRIDGE_DEVICE_NAME;
    const struct bt_data advertising_data[] = {
        BT_DATA_BYTES(BT_DATA_FLAGS, BT_LE_AD_NO_BREDR | BT_LE_AD_GENERAL),
        BT_DATA(BT_DATA_UUID128_ALL, service_uuid, sizeof(service_uuid)),
    };
    const struct bt_data scan_response[] = {
        BT_DATA(BT_DATA_NAME_COMPLETE, device_name, sizeof(device_name) - 1U),
    };
    struct bt_le_adv_param params;

    memset(&params, 0, sizeof(params));
    params.interval_min = BT_GAP_ADV_FAST_INT_MIN_2;
    params.interval_max = BT_GAP_ADV_FAST_INT_MAX_2;
    params.options = BT_LE_ADV_OPT_CONNECTABLE | BT_LE_ADV_OPT_ONE_TIME;

    return bt_le_adv_start(&params,
                           advertising_data,
                           ARRAY_SIZE(advertising_data),
                           scan_response,
                           ARRAY_SIZE(scan_response));
}

bool ble_nus_can_notify(void)
{
    return s_connection != NULL && s_notify_enabled;
}

size_t ble_nus_notify_limit(void)
{
    u16_t mtu;

    if (s_connection == NULL) {
        return 0U;
    }

    mtu = bt_gatt_get_mtu(s_connection);
    if (mtu <= 3U) {
        return 0U;
    }

    if ((size_t)(mtu - 3U) > BRIDGE_BLE_NOTIFY_MAX) {
        return BRIDGE_BLE_NOTIFY_MAX;
    }
    return (size_t)(mtu - 3U);
}

int ble_nus_notify(const uint8_t *data, size_t len)
{
    struct bt_conn *conn = s_connection;

    if (conn == NULL || !s_notify_enabled || len == 0U || len > UINT16_MAX) {
        return -1;
    }

    return bt_gatt_notify(conn,
                          &s_nus_attrs[NUS_TX_VALUE_ATTR_INDEX],
                          data,
                          (u16_t)len);
}
