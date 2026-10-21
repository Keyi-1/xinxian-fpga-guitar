# BL616 BLE ↔ FPGA UART 二级固件

这个工程把手机 BLE 字节流与 FPGA 的现有 UART 字节流透明互转，不解析或修改 XG3 帧。

## 已固定的接口

| 方向 | BL616 端 | FPGA 端 |
|---|---|---|
| 手机 → FPGA | BLE RX 写入 → UART1 TX GPIO28 | RX V14 |
| FPGA → 手机 | UART1 RX GPIO27 → BLE TX Notify | TX U15 |

UART 固定为 `115200 / 8N1`，无流控。两个方向各有 2048 字节缓冲区。BLE 使用与 Android App 一致的 Nordic UART Service：

- Service：`6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
- RX（手机写）：`6E400002-B5A3-F393-E0A9-E50E24DCCA9E`
- TX（手机订阅通知）：`6E400003-B5A3-F393-E0A9-E50E24DCCA9E`
- 广播名：`XINXIAN-BL616`

## 编译

已安装的软件默认位于：

- BouffaloSDK：`E:\BL616\bouffalo_sdk`
- T-Head RISC-V 工具链：`E:\BL616\toolchain_gcc_t-head_windows`

在 PowerShell 中运行：

```powershell
.\build_firmware.ps1
```

脚本只执行编译，不包含 `flash`、串口访问或 DevCube 调用。临时盘符用于绕过旧工具链不支持中文工程路径的问题，结束时会自动移除。

## 正式镜像

- 文件：`release\xinxian_ble_uart_bl616_secondary_0x40000.bin`
- 大小：281,968 字节（`0x44D70`）
- SHA-256：`753dc6f96b7a64e75d547262f4d821e7dbc7371ac50d191a8b5830d6b84d6001`
- 计划写入地址：`0x40000`
- 占用 Flash：`0x40000`～`0x84D6F`

镜像头为 Bouffalo `BFNP` 格式，和 TangCore 使用的普通 BouffaloSDK 二级镜像方式一致。
BouffaloSDK 会在镜像中写入 `BLFBVER` 编译日期和时间，因此以后从相同源码重新编译得到的
文件级 SHA-256 可能不同；上述哈希用于唯一标识仓库提交的正式发布镜像。2026-10-21 的复编
成功且文件等长，与正式镜像的二进制差异仅为两处内嵌构建时间字符串中的 11 个字节。

## 共存与烧录边界

Sipeed 官方说明 Mega NEO 的 BL616 调试器固件位于 `0x0`，支持二级启动的固件版本不得早于 `2025030317`，二级固件位于 `0x40000`。本机保存的恢复镜像：

- `E:\BL616\bl616_fpga_partner_NeoDock.bin`
- SHA-256：`4a7bae28bae18ae713a95177e1758954214253e5cdbb84d8436cba8bc1d085d7`
- 已与随附 `.sha256` 文件核对一致。

不要使用 SDK 自动生成的 `build\flash_prog_cfg.ini`。它会尝试写入 `0x0`、`0xE000` 和 `0x10000`，会碰到官方调试器区域。仓库中的 `flash_secondary_only.template.ini` 只是审核模板，只描述 `0x40000` 的单镜像写入；当前阶段不要执行它。

也不要烧录 `helloworld_bl616.bin`。

### USB-JTAG / USB 串口是否能同时保留

当前二级固件不初始化 USB，也没有实现 Sipeed 的 USB-JTAG 或 USB 串口协议。因此一旦官方一级固件把控制权交给本二级固件，二级固件本身不能继续提供那两个 USB 功能。能否在插着调试 USB 时进入二级固件，还取决于官方一级固件的切换条件，必须下板验证；不能把“地址共存”理解成“两个固件同时运行”。

如果最终必须同时拥有 BLE、USB-JTAG 和 USB 串口，需要把相应 USB 复合设备功能移植进二级固件，这不属于当前 BLE-UART 透明桥的范围。

## 将来的 DevCube 操作（现在不要执行）

在确认实物调试器版本和恢复流程后，DevCube 的 Single Download 应只选择正式二级 `.bin`，地址填 `0x40000`，使用分段擦除，不得使用整片擦除。首次试验前还应保存实物 Flash 或至少再次确认官方恢复包可用。

## 下板验收清单

1. 从 Windows 设备属性的父系/上层标识确认 BL616 调试器序列版本 `≥ 2025030317`。
2. 记录当前 USB-JTAG、USB 串口枚举状态和 FPGA 下载是否正常。
3. 仅写 `0x40000` 后断电重启，确认手机能发现 `XINXIAN-BL616`。
4. 手机订阅 TX，再发送一条已有 XG3 32 字节请求，核对 FPGA ACK 字节完全一致。
5. 连续双向传输并检查丢包、乱序和重连。
6. 分别测试带 USB 数据线和仅供电启动，记录一级固件是否会交给二级固件。
7. 检查 BLE 运行时 USB-JTAG/USB 串口的实际枚举；预计当前 BLE-only 二级固件不能同时提供它们。
8. 如启动失败，只用已核对哈希的 Mega NEO 官方恢复镜像恢复 `0x0`。
