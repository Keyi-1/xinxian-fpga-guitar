# 硬件连接与启动

适用硬件：Tang Mega 60K，`GW5AT-LV60PG484AC1/I0 / Device B`，NEO Dock **31005**。引脚以当前 [CST](../constraints/neo_guitar_touch_game.cst) 为准；历史试验工程的接口分配不可混用。

## 品位、压电输入和按键

品位板使用 J13 的 SDRAM0 数据引脚。只驱动当前扫描行为低，其余行高阻；矩阵板提供外部 3.3 V 上拉。本工程使用这组引脚作 GPIO。

| 信号 | FPGA 球位 |
| --- | --- |
| ROW0 / ROW1 / ROW2 / ROW3 | E14 / E13 / C15 / C14 |
| COL0 / COL1 / COL2 / COL3 | B13 / C13 / A14 / A13 |
| COL4 / COL5 / COL6 / COL7 | B21 / A21 / B20 / A20 |
| ADC CS / SCLK / MOSI / MISO | AA20 / AA21 / AA19 / AB20 |
| ADC 对应底板针号 | J8-7 / J8-8 / J8-5 / J8-6 |
| USER_BUTTON1 / 2 / 3 | AA13 / AB13 / Y12，低有效、Bank9 1.5 V |

四路压电信号先经过模拟前端，再连接 MCP3208 CH0～CH3；模拟传感器不能直接接 FPGA 数字引脚。按键功能为音色、合唱/和声、空间效果，无独立用户复位键。

## 屏幕、触控与姿态

- RGB666 屏接 J5，480×272，像素时钟约 8.333 MHz；每色使用高 6 位。J17 的 **1–2** 跳线保持可靠接通；本界面不走 HDMI。
- GT911 使用 J6 六针直连：RST=T15、INT=T16、SDA=U16、SCL=W16。显示与触控映射均已旋转 180°，保持当前屏幕倒置安装方式。
- MPU6050 使用 3.3 V、公共 GND，SCL 接 J8-11/Y21，SDA 接 J8-12/Y22，AD0 接 GND，I²C 地址 0x68。当前读取器兼容 WHO_AM_I=0x68/0x70 的已验收模块配置。传感器安装位置和朝向保持原设置，不跟随屏幕翻转。
- 开机后先将模块正 Z 向上平放，点击 `CALIBRATE`，静置约 4 秒；完成后开启 `AUTO`。平放对应钢琴，持琴姿态对应明亮弦音。校准和 AUTO 状态不会跨断电保存。

## JDY-23 与 DEBUG-USB2

| JDY-23 引脚 | 底板连接 | FPGA 方向 |
| --- | --- | --- |
| VCC | J8-1 或 J8-2，3.3 V | 电源 |
| GND | J8-3 或 J8-4，或公共地分线 | 公共地 |
| TXD | J8-10 / AB22 | FPGA 接收 |
| RXD | J8-9 / AB21 | FPGA 发送 |

JDY-23 固定 9600/8N1，BLE 服务 FFE0、串口特征 FFE1。默认名称的 JDY-23 也可连接；需要一次性 AT 配置时可使用 [configure_jdy23.ps1](../tools/configure_jdy23.ps1)。该脚本应通过独立 3.3 V USB-UART 适配器连接模块，先断开模块与 FPGA 的 TX/RX，且断开手机；具体命令及接线细节保存在[模块原始配置说明](../verification/firmware/jdy23/README.md)第 3 节，其旧单串口位流下载章节不适用于当前版本。

Windows 传谱直接用开发板 **DEBUG-USB2**。其 UART 桥连接 FPGA U15(TX)/V14(RX)，115200/8N1、无硬件流控。无需额外 USB-TTL，也无需刷 BL616 蓝牙固件；保留已验收的板载 USB-UART 桥和时钟配置。

## 音频与时钟

| 时钟 / 接口 | 配置 |
| --- | --- |
| 系统时钟 | 50 MHz，V22 |
| 音频参考 | MS5351 CLK2，12.288 MHz，V13 |
| KS 内部时钟 | FPGA PLL，由 50 MHz 产生 100 MHz |
| 板载 PT8211 | BCLK=Y17、LRCK=AB17、DIN=AA16；3.5 mm 输出 |
| J9 标准 I²S | J9-11/P19 BCLK，J9-12/R19 WS，J9-9/T21 DATA；J9-3/4 GND |

标准 I²S 为 48 kHz、每声道 32 bit 时隙、16 bit 有效数据，BCLK=3.072 MHz，WS 跳变后延迟一位发送 MSB。PT8211 使用自己的发送格式，两路来自同一 FPGA 音频链。

板上原有时钟初始化必须提供 12.288 MHz。JDY 模块能广播并不能说明音频参考已启动；如果整机不出声或无法握手，应同时检查时钟和供电。保持已工作的初始化配置，不用历史蓝牙诊断固件替换它。

## 下载和断电启动

Gowin Programmer 扫描选择 GW5AT-60B。临时测试用 `SRAM Mode / SRAM Program`；需要断电保留则选择 `External Flash Mode Arora V` → `exFlash Erase,Program thru GAO-Bridge Arora V`，Generic Flash，地址 0x000000，写入 [当前 FS](../releases/fpga/neo_guitar_touch_game.fs)。写入成功后完全断电再上电检查。

Flash 保存 FPGA 配置和内置曲谱；运行时导入的 USER 曲谱仍在 RAM，断电后清除。
