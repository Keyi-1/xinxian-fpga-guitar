# Native Android/iPhone importer prototype

Shared XG3 transport and UI; board BLE firmware is not yet available. The app
does not make a stock debugger advertise this service.

From this directory, install the pinned packages with `pnpm install --frozen-lockfile`.
`pnpm test` runs the shared protocol fault model (generate the formal example
first per `docs/P5_BL616_BLUETOOTH_IMPORT.md`). These tests require only Node24.
`pnpm android` requires Android SDK/tooling. `pnpm ios` requires macOS/Xcode and
device signing. BLE requires a custom native development build; Expo Go is
insufficient. This task did not upload builds to a cloud service or install an
app on any device.

The native workflow is scan/select device → HELLO/five slots → choose one
`.xgscore` package → select a slot/confirm replacement → upload progress →
matching final FPGA COMMIT ACK → refresh catalog → disconnect. System
permissions and file picking use native APIs. No web Bluetooth fallback.

The package parser and wire code are in `src/protocol.js`. GATT uses Write with
response and Notify with conservative 20-byte fragments. The adapter bounds
each native write; write failure closes the connection, without overlapping
half-frame retries. It stops on backgrounding. Pending COMMIT metadata is
written to app storage before transmission and retained on ambiguous failure
or process exit. There is no automatic resume/retry across reconnects.

A successful COMMIT ACK is authoritative. A later LIST failure does not turn
that into a rollback. LIST has no content CRC, so matching metadata after a
lost ACK cannot by itself prove which content committed. UI requires explicit
manual confirmation to clear an unresolved marker. The board still displays
USER1..5; phone titles are local metadata. Imported RAM is volatile.

Validation levels (PC protocol tests, dual-platform JS bundles, native
APK/IPA builds and physical BLE acceptance) are reported separately in
`build/p5_bluetooth/verification.json`.
