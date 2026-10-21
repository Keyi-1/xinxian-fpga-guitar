#ifndef P5_BRIDGE_H
#define P5_BRIDGE_H
#include <stddef.h>
#include <stdint.h>

/* Portable transport core, not a flashable BL616 image. All calls serialized
 * by one adapter task. USB and BLE are exclusive boot modes. No chart logic. */
enum { P5_USB = 1, P5_BLE = 2, P5_OK = 0, P5_DENIED = -1,
       P5_BUSY = -2, P5_BAD_FRAME = -3 };
typedef struct {
    uint32_t epoch, until, last_byte;
    uint16_t session, retired_session;
    uint8_t mode, live, quarantine, host_n, uart_n;
    uint8_t pending, tx_ready, reply_ready;
    uint8_t host[32], uart[32], request[32], reply[32];
} p5_bridge;
void p5_init(p5_bridge *b, unsigned mode);
int p5_open(p5_bridge *b, unsigned channel, uint32_t epoch, uint32_t now);
void p5_close(p5_bridge *b, uint32_t epoch, uint32_t now);
int p5_host_bytes(p5_bridge *b, unsigned channel, uint32_t epoch,
                  const uint8_t *data, size_t n, uint32_t now);
void p5_uart_bytes(p5_bridge *b, const uint8_t *data, size_t n);
int p5_take_uart(p5_bridge *b, uint8_t out[32]);
int p5_take_reply(p5_bridge *b, unsigned channel, uint32_t epoch, uint8_t out[32]);
#endif
