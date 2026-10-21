# P5 transport core

This is a portable C11 library, **not a BL616 firmware image**. There is no
flash target. See `docs/P5_BL616_BLUETOOTH_IMPORT.md` for evidence and blockers.

The single adapter task must serialize calls, tag all GATT/USB callbacks with
the current connection epoch, and choose one fixed transport mode at boot.
`p5_host_bytes` accepts arbitrary chunks of existing XG3 bytes. Drain
`p5_take_uart` as exactly one uninterrupted 32-byte UART frame at 115200/8N1.
Feed received UART bytes to `p5_uart_bytes`; only a matching real response can
be returned by `p5_take_reply`. Notify in chunks <=20 bytes, retaining the
response while the BLE stack reports congestion. A local write/queue success
is never an FPGA ACK.

On disconnect: stop/flush old UART DMA and hardware queues, discard unfinished
notifications, call `p5_close`, wait its six-second quarantine, then use a new
epoch/session. Quarantine does not imply rollback or bound a stalled COMMIT.
FPGA HELLO/BUSY is authoritative. Epoch values must be unique during the
adapter lifetime. No reconnect resume, simultaneous USB/BLE, or mode switch
within one library instance is supported.

Target adapter remains to be built: audited 31005 BSP/26MHz clock/RF settings,
GPIO28 TX and27 RX, GATT service in phone protocol, CCCD readiness, UART errors,
connection security policy, asynchronous queues, congestion and recovery.
The default `bl616dk` BSP and TangCore application cannot be used unchanged.
Debug logging must never share the score UART.

Host test: generate the current example per the main document, then
`python -m unittest discover -s tools -p test_p5_bridge.py -v` from repo root.
This compiles with GCC into `build/p5_bluetooth/host/p5_bridge.dll`. It neither
cross-compiles RISC-V nor demonstrates BLE radio operation.
