#include "p5_bridge.h"
#include <string.h>

static uint16_t le16(const uint8_t *p) { return (uint16_t)(p[0] | p[1] << 8); }
static uint32_t crc32(const uint8_t *p, size_t n) {
    uint32_t c = 0xffffffffu;
    while (n--) {
        c ^= *p++;
        for (unsigned i = 0; i < 8; ++i)
            c = (c >> 1) ^ (0xedb88320u & (0u - (c & 1u)));
    }
    return ~c;
}
static int valid(const uint8_t *p) {
    uint32_t c = crc32(p + 4, 24);
    return !memcmp(p, "XG3!", 4) && p[4] == 3 && le16(p + 6) &&
           !le16(p + 26) && p[28] == (uint8_t)c && p[29] == (uint8_t)(c >> 8) &&
           p[30] == (uint8_t)(c >> 16) && p[31] == (uint8_t)(c >> 24);
}
static int owned(const p5_bridge *b, unsigned channel, uint32_t epoch) {
    return b->live && b->mode == channel && b->epoch == epoch;
}
void p5_init(p5_bridge *b, unsigned mode) {
    memset(b, 0, sizeof(*b));
    b->mode = (uint8_t)mode;
}
int p5_open(p5_bridge *b, unsigned channel, uint32_t epoch, uint32_t now) {
    if (!epoch || channel != b->mode || (channel != P5_USB && channel != P5_BLE) ||
        b->live || epoch == b->epoch ||
        (b->quarantine && (int32_t)(now - b->until) < 0)) return P5_DENIED;
    b->epoch = epoch;
    b->live = 1;
    b->quarantine = 0;
    b->host_n = b->uart_n = b->pending = b->tx_ready = b->reply_ready = 0;
    b->session = 0;
    b->last_byte = now;
    return P5_OK;
}
void p5_close(p5_bridge *b, uint32_t epoch, uint32_t now) {
    if (!b->live || b->epoch != epoch) return;
    b->live = 0;
    b->retired_session = b->session;
    b->host_n = b->uart_n = b->pending = b->tx_ready = b->reply_ready = 0;
    b->session = 0;
    /* Quarantine covers the current 0.5s frame and 5s RECEIVE timeouts.
     * It is not proof of rollback: COMMIT publication can still be pending.
     * A new host must HELLO; FPGA remains authoritative about BUSY. */
    b->quarantine = 1;
    b->until = now + 6000u;
}
int p5_host_bytes(p5_bridge *b, unsigned channel, uint32_t epoch,
                  const uint8_t *data, size_t n, uint32_t now) {
    if (!owned(b, channel, epoch)) return P5_DENIED;
    if (b->host_n && (uint32_t)(now - b->last_byte) >= 1000u) b->host_n = 0;
    b->last_byte = now;
    int result = P5_OK;
    while (n--) {
        b->host[b->host_n++] = *data++;
        if (b->host_n < 32) continue;
        if (!valid(b->host)) {
            memmove(b->host, b->host + 1, 31);
            b->host_n = 31;
            result = P5_BAD_FRAME;
            continue;
        }
        b->host_n = 0;
        const uint8_t *p = b->host;
        uint16_t session = le16(p + 6);
        if ((!b->session && (p[5] != 1 || le16(p + 8) || session == b->retired_session)) ||
            (b->session && session != b->session) || p[5] < 1 || p[5] > 7) {
            result = P5_DENIED;
        } else if (b->reply_ready || b->tx_ready ||
                   (b->pending && memcmp(p, b->request, 32))) {
            result = P5_BUSY;
        } else {
            b->session = session;
            memcpy(b->request, p, 32);
            b->pending = b->tx_ready = 1;
        }
    }
    return result;
}
void p5_uart_bytes(p5_bridge *b, const uint8_t *data, size_t n) {
    if (!b->live) return;
    while (n--) {
        b->uart[b->uart_n++] = *data++;
        if (b->uart_n < 32) continue;
        if (!valid(b->uart)) {
            memmove(b->uart, b->uart + 1, 31);
            b->uart_n = 31;
            continue;
        }
        b->uart_n = 0;
        if (b->pending && !b->reply_ready &&
            b->uart[5] == (uint8_t)(b->request[5] | 0x80) &&
            !memcmp(b->uart + 6, b->request + 6, 4)) {
            memcpy(b->reply, b->uart, 32);
            b->reply_ready = 1;
        }
    }
}
int p5_take_uart(p5_bridge *b, uint8_t out[32]) {
    if (!b->live || !b->tx_ready) return 0;
    memcpy(out, b->request, 32);
    b->tx_ready = 0;
    return 32;
}
int p5_take_reply(p5_bridge *b, unsigned channel, uint32_t epoch, uint8_t out[32]) {
    if (!owned(b, channel, epoch) || !b->reply_ready) return 0;
    memcpy(out, b->reply, 32);
    b->reply_ready = b->pending = b->tx_ready = 0;
    return 32;
}
