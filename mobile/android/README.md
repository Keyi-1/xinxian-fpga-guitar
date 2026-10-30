# 弦心 FPGA 吉他 Android 客户端

## 当前 JDY-23 方案（2026-10-27）

已增加JDY-23的FFE0/FFE1、20字节/35ms发送节奏、连接代次与超时保护，以及COMMIT前持久化待核对标记。
使用新“弦心吉他·JDY23”APK和9600/J8-9/10位流，完整步骤见[JDY-23说明](../../firmware/jdy23/README.md)。下文BL616专用流程为历史资料。

## 2026-10-25 扫描显示修复

旧扫描回调只读取BluetoothDevice缓存名称，并隐藏无缓存名称且无NUS服务的设备。
诊断固件不广播NUS，因此可能被旧App隐藏。现在优先读取ScanRecord.getDeviceName，
回退到系统缓存名称，并保留未命名设备。此改动不能证明板端已正常广播。

新增 `scanCheck` 构建类型，包名后缀`.scancheck`，显示名“弦心吉他·扫描诊断”，可与原App并存。
本机已用现有SDK aapt2/javac/D8/zipalign/apksigner直接完成APK编译和签名验证；
Gradle离线构建因Kotlin依赖缓存不全失败，不能称Gradle构建通过。
独立APK与验证记录在 `build/releases/android/scancheck_20261025/`（相对仓库根目录）。
它只用于当前扫描定位，连接/导谱可靠性问题仍见 `docs/BL616_BLE_SECOND_REVIEW.md`，
本轮未实机安装、未进行BLE扫描或上传。

这个目录是现有 P3 UART 导入协议的 Android BLE 客户端。它不修改 FPGA RTL，手机端与 BL616 之间使用 BLE，BL616 再把收到的原始字节透明转发到 FPGA UART。

## 先说明：天线不是蓝牙固件

只焊好天线还不能让手机连接。BL616 必须运行一个 BLE-UART 透明桥固件，并提供下面的 Nordic UART Service（NUS）兼容服务：

| 用途 | UUID | BL616 行为 |
| --- | --- | --- |
| Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` | 广播此服务，建议设备名 `XINXIAN-BL616` |
| RX | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` | 手机 Write；原样写到 BL616 GPIO28 → FPGA RX |
| TX | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` | 收到 FPGA TX → BL616 GPIO27 后，以 Notify 原样发给手机 |

UART 固定为 `115200 / 8N1`，不得添加换行、长度头或 AT 命令。BLE 分包边界不是 XG3 帧边界；桥接固件必须把字节流原样、按顺序转发。建议协商 MTU 247，并在 BL616 两个方向各放至少 256 字节环形缓冲区。

如果 BL616 当前仍是底板出厂调试器固件，应用通常只能扫描到设备，却找不到上述 NUS 服务；此时需要先完成 BL616 的 BLE-UART 固件，手机应用本身无法替代它。

## 手机端功能

- 扫描并连接 Android 8.0 以上手机附近的 BLE 设备。
- 连接 NUS 服务后自动发送 XG3 `HELLO`，确认事件格式、槽数、容量、MIDI 范围和 48 kHz 时间基准。
- 查询五个 FPGA 曲目槽。
- 从手机文件中选择现有 `tools/compile_p2_score.py` 产生的 `.bin` 曲谱。
- 上传前在手机本地检查 16 字节记录、音域、力度、排序、同轨冲突和密度，并计算与 `zlib.crc32` 相同的整曲 CRC32。
- 按 `BEGIN → DATA（逐条 ACK）→ COMMIT → LIST` 上传；丢包会以同一会话/序号重发，利用 FPGA 的幂等缓存避免重复写入。
- COMMIT 最终确认包全部丢失时明确显示“提交结果未知”，不会错误宣称已回滚。

## 编译与安装

1. 用 Android Studio 打开本目录 `mobile/android`。
2. 让 Android Studio 使用 JDK 17，并安装 Android SDK 35。
3. 连接 Android 手机，运行 `app`；或者用 **Build → Build APK(s)** 生成 APK。
4. 首次启动允许“附近的设备/蓝牙”权限。

项目只使用 Android 系统 API，没有第三方运行库。当前仓库没有提交 Gradle Wrapper 二进制；Android Studio 会使用其自带的 Gradle/JDK 环境。

## 实机顺序

1. FPGA 使用已经验证过的 P3 位流，停留在主页或选曲页，音频保持空闲。
2. 给整板供电，确认 BL616 正在广播 `XINXIAN-BL616` 和 NUS 服务。
3. 手机点击“扫描蓝牙”，选择带 `[BLE 串口]` 标记的设备并连接。
4. 日志出现“XG3 握手成功”后，先点“读取 5 个曲目槽”。
5. 选择 `.bin`，建议先写 `USER 2` 或 `USER 5`，再开始上传。
6. 日志只有出现“经 FPGA RAM 读回校验”才表示导入完成。断电、复位或重新配置 FPGA 后，RAM 曲目会丢失。

协议来源见仓库根目录的 `docs/P3_WRITABLE_SONG_IMPORT.md`，手机实现位于 `app/src/main/java/com/keyi/xinxian/guitar/`。
