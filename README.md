# 芯弦 FPGA 电子吉他

> 2026-10-25：旧短包络版本已先推送为 `3803129`。演奏尾音锁定已通过受影响 RTL/音频、当前实际音频网表和原工程完整 P&R/STA；原 `impl/pnr/neo_guitar_touch_game.fs` 为当前版本，独立发布为 [neo_guitar_touch_game_tail_lock.fs](build/releases/touch_game/neo_guitar_touch_game_tail_lock.fs)。松品后的旧尾音不再被下一次按品改音高，连续滑音、空弦重拨、三次松按颤音和钢琴半时长保留。系统／音频 Fmax 50.057／17.771 MHz，setup／hold为0；系统余量较窄。见 [尾音锁定说明](docs/TAIL_PITCH_LOCK.md)。旧固定发布保留，本轮新改动未推送、未烧录。

> 2026-10-25：钢琴自然时长减半、松品保持原音、三次松按颤音保留，已通过原工程 P&R/STA 和当前实际网表整机验证。原 `impl/pnr/neo_guitar_touch_game.fs` 可用，独立副本为 `build/releases/touch_game/neo_guitar_touch_game_piano_short_hold.fs`；系统／音频 Fmax 为 51.657／17.396 MHz，setup／hold 为0。下板听感待确认，旧 V6 与 ID70 发布保留。见 [本轮说明](docs/PIANO_SHORT_HOLD.md)。

> 演奏颤音 V6 已完成原工程综合、P&R/STA、RTL 与实际综合网表整机验证；独立位流为 `build/releases/touch_game/neo_guitar_touch_game_vibrato.fs`，SHA256 `997baf9cfa57e3e6fd65250a3ab0452cde10802f53405043b50a3b748269566b`。系统 Fmax 50.003 MHz（要求 50.000 MHz），达标但余量极窄；颤音手感仍需下板确认。已验收 ID70 发布 `neo_guitar_touch_game_p4_posture.fs` 保持不变，可随时回退。详见 [颤音说明](docs/PERFORMANCE_VIBRATO.md)。

> 四弦实时电子乐器：双 PCB 输入、FPGA 音色合成、双音频输出、触控与四轨引导演奏

**当前版本（2026-10-23）：P4 完整吉他固件已兼容 ID70 IMU，用户确认重力传感器正常工作，并已完成外部 Flash 烧录及断电重启使用验证。** 正式入口为
[neo_guitar_touch_game.gprj](gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj)，Top=`neo_guitar_touch_game_top`。
当前包含 GT911 触控、全宽四轨游戏、《情歌》完整主旋律、五槽可写曲库／UART 导入、真实拨弦四档力度和空闲姿态切音色；演奏模式继续保留三音色、四声部、全部音效、松品续音、四弦渐变、环形真实频谱及莉萨如渐暗。
最终立体声 PCM 同时送往板载 PT8211 和 J9 标准 I²S。蓝牙仍按下文单独记录，Flash 启动通过不代表蓝牙实物闭环通过。
旧版与新版资源数据同时保留在第 0 节，历史双输出和全宽舞台的归档记录继续保留。

钢琴击弦现由 FPGA 实时噪声激励、低通滤波和三个阻尼谐振器生成；生产链已移除录音残差 PCM ROM，保留钢琴模态主体。旧录音回放实现仅用于独立仿真 A/B。模型及赛题条款对照见 [程序生成击弦说明](docs/PROCEDURAL_PIANO_HAMMER.md)。

| 当前入口与接口 | 配置 |
| --- | --- |
| FPGA / 底板 | Tang Mega 60K，GW5AT-LV60PG484AC1/I0，Device B / NEO Dock 31005 |
| 工程操作与构建 | [触控／全宽舞台工程 README](gowin/neo_guitar_touch_game/README.md) |
| LCD | J5，480×272 RGB666，DCLK 8.333 MHz；J17 的 1–2 针保持牢固连接，无需 HDMI |
| 电容触控 | GT911 独立六针直插 J6；RST=T15、INT=T16、SDA=U16、SCL=W16，3.3 V |
| 重力／姿态传感器 | ID68／ID70 配置兼容，I²C 地址 0x68；SCL=J8-11/Y21、SDA=J8-12/Y22，3.3 V，共地，AD0 接 GND |
| 固件断电保存 | Gowin Programmer 外部 Flash／GAO-Bridge Arora V；用户已确认断电重新上电可启动 |
| 板载音频 | 原 PT8211 / 3.5 mm 输出，48 kHz、16 bit |
| 标准 I²S | J9-11 BCLK / P19，J9-12 WS / R19，J9-9 DATA / T21；J9-3 或 4 共地 |
| I²S 格式 | 48 kHz、每声道 32 位时隙、16 位有效数据；BCLK 3.072 MHz，WS 切换后延迟一位发送 MSB |

详细接线与协议验证见 [标准 I²S 接口说明](docs/STANDARD_I2S_VALIDATION.md)。本次实物验收按用户对当前程序的反馈记录；外接 DAC 的型号和专项测量结果尚未单独记录。

芯弦 FPGA 电子吉他是一套以 Sipeed Tang Mega 60K FPGA 为硬件核心的四弦实时电子乐器。系统通过琴颈按弦矩阵和桥位压电传感器采集演奏动作，由 FPGA 内部可综合 HDL 逻辑完成音高选择、力度分级、声部管理、谐波／模态加法合成、包络、数字音效、频谱分析和音频输出。演奏期间，音频生成主链路不依赖软核 CPU、外部 MCU 或上位机程序。

当前音色为钢琴、明亮弦音和哇音。演奏模式下，品位矩阵只选择音高，压电拨弦才触发起音；松品保持最后按住的音高并继续自然衰减，不由按品时长决定声音时长。三个 USER_BUTTON 用于音色／音效控制，没有外部复位键。

演奏模式的屏幕左侧为 208×272 的蓝／绿／橙／红四弦渐变区；右侧为 272×272 显示区，内含 150×150 莉萨如图形和 64 根环形谱柱。曲线快速亮起、缓慢变暗，自然结束后保留约 150 ms 尾迹。

游戏模式无需按品：看色块中心到达 x=96 判定线，拨对应弦后，由谱面选择音高并实时合成声音；保留计分、连击、Miss 提示和双击退出。曲谱生成器避免同弦重叠冲突，临近音优先换弦。4×9 矩阵与后续折线动效未加入。

当前按真实拨弦峰值分为四档，声部增益为 25%／50%／75%／100%；第一弦触发偏差 220、第三弦 60，试听仍使用固定力度编码 2（75%）。队友阈值已接入，重复拨弦统计、实际声压和长期串扰测试仍需补充。旧音频、显示及独立击弦工程继续保留作阶段参考。

项目最终目标日期为 **2026-11-01**，计划以 Apache License 2.0 公开源码。

## 蓝牙与手机曲谱传输（BL616）

2026-10-21 已加入 Android 手机客户端和 BL616 BLE↔UART 二级固件源码。该功能复用 FPGA
现有的 P3 XG3 UART 曲谱导入协议，不改变 FPGA 的实时音频生成主链路。手机传输的是曲谱、
槽位查询和应答数据，不是实时蓝牙音频；正常演奏和音频输出仍完全由 FPGA RTL 完成。

> 当前状态：BL616 固件已经使用 BouffaloSDK 编译并生成正式二级镜像，Android 客户端源码已完成；
> 尚未把二级镜像烧入实物，也尚未完成手机→BLE→BL616→UART→FPGA 的实物闭环验证。
> 下文将“已实现的软件”与“仍待下板验证的项目”分开说明。

### 系统分工与数据链路

```mermaid
flowchart LR
    A[Android 手机 App] <-->|BLE GATT / NUS| B[BL616 BLE-UART 透明桥]
    B <-->|UART 115200 / 8N1| C[高云 FPGA]
    C --> D[XG3 协议解析]
    D --> E[曲谱暂存、CRC 与 BSRAM 读回校验]
    E --> F[五槽曲库原子更新]
```

- **Android App**：扫描和连接 BLE 设备、选择 `.bin` 曲谱、进行本地格式检查、发送 XG3
  命令，并显示上传进度和 FPGA 应答。
- **BL616**：只负责 BLE 字节流与 UART 字节流的双向透明转发，不解析、不修改 XG3 帧，
  也不参与音色合成。
- **FPGA**：负责 XG3 帧解析、会话与序号检查、曲谱约束检查、CRC32、实际 BSRAM 读回校验，
  以及曲目目录的跨时钟域原子提交。

BL616 与 FPGA 使用 NEO Dock 已有 UART 网络连接：

| 数据方向 | BL616 端 | FPGA 端 | 行为 |
| --- | --- | --- | --- |
| 手机 → FPGA | UART1 TX，GPIO28 | RX，V14 | 手机写 BLE RX，BL616 原样从 UART 发给 FPGA |
| FPGA → 手机 | UART1 RX，GPIO27 | TX，U15 | FPGA 应答进入 BL616，再以 BLE Notify 发给手机 |

UART 固定为 `115200 / 8N1`、无校验、无硬件流控。BL616 两个方向各使用 2048 字节
FreeRTOS Stream Buffer，避免 BLE 分包与 UART 连续字节流的时序差异导致丢包。BLE 分包边界
不是 XG3 帧边界；手机端会连续收集通知字节、搜索 XG3 帧头并重组固定 32 字节帧。

### BLE 服务

BL616 广播名称为 `XINXIAN-BL616`，使用 Nordic UART Service（NUS）兼容 UUID：

| 用途 | UUID | 属性与方向 |
| --- | --- | --- |
| Service | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` | BLE 串口主服务 |
| RX | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` | 手机 Write / Write Without Response → BL616 |
| TX | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` | BL616 Notify → 手机 |

手机连接后请求 MTU 247；实际 BLE 负载按协商后的 `MTU-3` 分块，单次通知最大 244 字节。
如果仍使用默认 MTU 23，程序会自动退回 20 字节分块。断开连接后 BL616 会重新广播。
手机端必须先成功订阅 TX Notify，才会进入 XG3 握手。

### 手机连接与 XG3 握手

1. App 申请附近设备/蓝牙权限并扫描附近 BLE 设备。
2. 用户选择 `XINXIAN-BL616`，App 建立 GATT 连接并发现 NUS 服务。
3. App 请求 MTU 247，找到 RX/TX 特征并写入 CCC 描述符以订阅 TX Notify。
4. BLE 串口就绪后，App 自动发送 XG3 `HELLO`。
5. BL616 把完整字节流原样转发给 FPGA；FPGA 返回能力信息。
6. App 确认事件格式为 v2、槽数为 5、帧长为 32、采样时间基准为 48 kHz，握手成功后
   才开放槽位查询和曲谱上传按钮。

Android 客户端支持 Android 8.0（API 26）及以上。工程当前使用 JDK 17、`compileSdk=35`、
`targetSdk=35`；API 37 手机可以运行该应用，但构建机仍应安装项目指定的 Android SDK 35。

### 曲谱检查与可靠上传流程

App 选择由现有编谱工具生成的 `.bin` 后，会先在手机本地检查：

- 文件必须由完整的 16 字节 v2 事件组成，总事件数不得超过 2048；
- MIDI 范围为 50～79，轨道为 0～3，力度为 0～3；
- 起音时间必须升序，同轨事件不得重叠；
- 同轨相邻起音和滑动窗口事件密度必须满足 FPGA 的实时播放约束；
- 单个事件时长非零，整曲不得超过 10 分钟；
- 计算与 Python `zlib.crc32` 一致的整曲 CRC32。

上传使用固定 32 字节 XG3 帧和停等 ACK：

```mermaid
flowchart TD
    A[选择并本地校验 .bin] --> B[HELLO 握手]
    B --> C[BEGIN: 槽号/音色/事件数/时长/CRC]
    C --> D{FPGA 接受 BEGIN?}
    D -- 否 --> X[显示 FPGA 错误并停止]
    D -- 是 --> E[发送一条 DATA 事件]
    E --> F{收到成功 ACK?}
    F -- 否且未到上限 --> E
    F -- 连续失败 --> G[尝试 ABORT 并报告失败]
    F -- 是 --> H{还有事件?}
    H -- 是 --> E
    H -- 否 --> I[发送 COMMIT]
    I --> J[FPGA 检查整曲 CRC]
    J --> K[从实际 BSRAM 逐条读回并重算 CRC]
    K --> L{两次校验均通过?}
    L -- 否 --> X
    L -- 是 --> M[原子发布新目录并返回 ACK]
    M --> N[App 再发 LIST 查询槽位]
    N --> O[显示经 FPGA RAM 读回校验，上传完成]
```

每条请求最多发送 4 次，失败重试保持相同会话号、序号和帧内容。FPGA 对上一条成功请求保存
幂等响应，因此 ACK 丢失后的重发不会重复写入或重复提交。只有收到成功响应才推进序号。
DATA 期间出现异常时 App 会尝试发送 `ABORT`。如果 `COMMIT` 已执行但最终 ACK 连续丢失，
App 会明确显示“提交结果未知”，要求重新连接后用 `LIST` 查询，不能错误宣称已经回滚。

导入曲谱当前位于 FPGA 运行时 RAM；断电、FPGA 复位或重新配置位流后，RAM 导入曲目会丢失，
内置曲目不受影响。完整 XG3 格式、错误码、CRC 和 FPGA 侧验证见
[P3 可写曲库与 UART 导入说明](docs/P3_WRITABLE_SONG_IMPORT.md)。

### Android 工程

手机源码位于 [`mobile/android`](mobile/android/README.md)，核心文件包括：

- `BleUartClient.java`：BLE 扫描、GATT 连接、MTU、NUS 服务和双向分包；
- `Xg3Protocol.java`：32 字节帧、CRC32、曲谱本地约束检查与槽位描述符；
- `Xg3Client.java`：HELLO/LIST/BEGIN/DATA/COMMIT/ABORT、停等 ACK 与重试；
- `MainActivity.java`：设备选择、文件选择、槽位/音色选择、进度和日志界面。

用 Android Studio 打开 `mobile/android`，选择 JDK 17 并安装 Android SDK 35，可直接运行 `app`
到手机或使用 **Build → Build APK(s)** 生成 APK。应用只依赖 Android 系统 API，没有第三方运行库。

### BL616 固件、镜像与编译

BL616 工程位于 [`firmware/bl616_ble_uart_bridge`](firmware/bl616_ble_uart_bridge/README.md)，包含
BLE NUS 服务、UART1 驱动、两个方向的 FreeRTOS 转发任务、构建脚本和只写二级区的 DevCube
配置审核模板。仓库不提交 SDK 中间构建目录。

在已安装 BouffaloSDK 与 T-Head RISC-V 工具链的 Windows PowerShell 中运行：

```powershell
cd firmware/bl616_ble_uart_bridge
./build_firmware.ps1
```

脚本只编译，不执行烧录、串口访问或 DevCube。当前正式镜像为：

| 项目 | 值 |
| --- | --- |
| 文件 | `firmware/bl616_ble_uart_bridge/release/xinxian_ble_uart_bl616_secondary_0x40000.bin` |
| 大小 | 281,968 字节（`0x44D70`） |
| SHA-256 | `753dc6f96b7a64e75d547262f4d821e7dbc7371ac50d191a8b5830d6b84d6001` |
| 计划写入地址 | `0x40000` |
| 计划占用范围 | `0x40000`～`0x84D6F` |

BouffaloSDK 会把编译日期和时间写入镜像中的 `BLFBVER` 字符串，因此以后从相同源码重新编译的
文件级 SHA-256 可能不同。本表哈希用于唯一标识仓库提交的正式发布镜像；本次复编成功，复编文件
与发布镜像等长，二进制差异仅为两处内嵌构建时间字符串的 11 个字节。

### 烧录安全边界与未完成验证

BL616 固件采用二级镜像方案：NEO Dock 官方调试器固件保留在低地址区域，BLE-UART 镜像计划只写
`0x40000`。仓库中的 `flash_secondary_only.template.ini` 是供人工审核的模板，不是自动烧录脚本。

首次操作前必须确认：

1. 实物 BL616 调试器固件版本支持 `0x40000` 二级启动；
2. 已保存并核对 NEO Dock 官方 BL616 恢复固件；
3. DevCube 仅使用 Single Download 写正式二级 `.bin` 到 `0x40000`；
4. 使用分段擦除，不使用整片擦除；
5. 不使用 SDK 自动生成的多镜像 `build/flash_prog_cfg.ini`，也不烧录 `helloworld_bl616.bin`。

当前二级固件没有实现 Sipeed USB-JTAG 或 USB 串口复合设备功能。地址上保留官方一级固件，
不代表两个固件能够同时运行；一级固件何时跳转二级固件，以及 BLE 运行时 USB-JTAG/USB 串口是否
继续枚举，都必须通过实物验证。若最终要求 BLE、USB-JTAG 和 USB 串口同时工作，需要进一步移植
相应 USB 功能，当前代码尚不包含这一部分。

实物验收应依次记录：原 USB 枚举和 FPGA 下载状态、只写 `0x40000` 后的启动情况、手机扫描、
NUS 订阅、XG3 HELLO、32 字节请求/ACK 一致性、完整曲谱上传、连续双向传输、断线重连、
仅供电与连接 USB 两种启动方式，以及必要时使用官方恢复镜像恢复 `0x0`。在完成这些步骤前，
本仓库只能声明“源码完成、BL616 镜像编译通过”，不能声明蓝牙已下板验收。

## 0. 当前实际进度与待验收项目

2026-10-23 用户确认：当前完整吉他固件的重力传感器已能正常工作，固件写入外部 Flash 后，断电再上电也能重新启动使用。此处记录用户实物反馈；未另行采集现场烧录文件哈希、定量姿态精度或长期稳定性数据。
当前主工程包含触控模式菜单、全宽四轨舞台、《情歌》38 小节／60 BPM 完整主旋律、可写曲库和 UART 导入；第 10／18 小节使用用户试听确认的修订节奏。演奏模式保留原三音色、音效和环形显示，IMU 自动切音色仅在演奏空闲时执行，手动操作优先。
工程入口、接线和操作见 [`neo_guitar_touch_game`](gowin/neo_guitar_touch_game/README.md)，ID70 修复及数字验证范围见 [兼容说明](docs/IMU_ID70_COMPATIBILITY.md)。

原工程可直接烧录：[neo_guitar_touch_game.fs](gowin/neo_guitar_touch_game/impl/pnr/neo_guitar_touch_game.fs)。同名发布副本为 [neo_guitar_touch_game_p4_posture.fs](build/releases/touch_game/neo_guitar_touch_game_p4_posture.fs)，固定新版归档为 [p4_imu_id70_20261023](build/releases/touch_game/p4_imu_id70_20261023/README.md)。三份位流 SHA256 均为 `967e52a35f81a3eb03aa21a621ea47d668f02485b34bb41dec0bfb56c43ba917`。

**旧版与新版完整实现资源／时序并列保留：** 两次均为 Gowin V1.9.12.03、GW5AT-LV60PG484AC1/I0 Device B，使用原 `.gprj`／原 `impl`，数据取各自完整 P&R／STA 报告，实际时钟均为 50／12.288 MHz。

| 项目 | 旧版 P4 四档力度（2026-10-19） | 新版 P4 ID70 兼容（2026-10-23） |
| --- | --- | --- |
| Logic | 50432/59904（84.19%） | 50605/59904（84.48%） |
| Register | 20139/60780（33.13%） | 20140/60780（33.14%） |
| CLS | 28650/29952（95.65%） | 28295/29952（94.47%） |
| BSRAM | 113/118（95.76%） | 113/118（95.76%） |
| DSP | 115.5/118（97.88%） | 115.5/118（97.88%） |
| 系统 Fmax（运行 50 MHz） | 53.171 MHz | 50.072 MHz |
| 音频 Fmax（运行 12.288 MHz） | 14.051 MHz | 13.687 MHz |
| Setup / Hold / 未布通 / latch | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 |
| 已测试运算 deadline 违例 | 0 | 0 |

旧版对应 [quarter_dynamics_verification.json](gowin/neo_guitar_touch_game/quarter_dynamics_verification.json) 和 [固定旧位流](build/releases/touch_game/p4_quarter_dynamics_20261019/evidence/gowin/neo_guitar_touch_game/impl/pnr/neo_guitar_touch_game.fs)，SHA256 `cfda7ead63703142876e10776a38f86237188aeb4a4d910b02aa0927df611a30`；新版对应 [imu_id70_verification.json](gowin/neo_guitar_touch_game/imu_id70_verification.json) 及上述新版位流。旧认证只用于旧归档，同名发布文件已更新为新版。
新版比旧版减少 355 CLS，Logic 增加 173、Register 增加 1，BSRAM／DSP 不变；系统／音频 Fmax 分别降低 3.099／0.364 MHz。新版满足实际运行要求，CLS 已低于 95%，但系统 Fmax 距 55 MHz 余量目标仍差 4.928 MHz，不能宣称余量目标全部完成。两次构建均保留既有 2 条 PR1014 时钟通用布线提示，STA 已计入实际布线延迟。

**Flash 烧录与重启：** 在 Gowin Programmer 扫描 `GW5AT-60B`，双击 Operation，Access Mode 选择 `External Flash Mode Arora V`，Operation 选择 `exFlash Erase,Program thru GAO-Bridge Arora V`（也可用同名带 Verify 的选项），选择上述完整 `.fs`，Flash 类型可保留 `Generic Flash`，起始地址 `0x000000`，Save 后执行 Program/Configure。成功后完全断电再上电，确认自动进入吉他界面。以后更新固件可用同样流程擦除并重新写入；临时调试仍可用 `SRAM Program`，断电重启将恢复 Flash 中保存的版本。步骤依据 [Sipeed Mega 60K 说明](https://wiki.sipeed.com/hardware/en/tang/tang-mega-60k/mega-60k.html) 和 [Gowin Programmer 指南](https://cdn.gowinsemi.com.cn/SUG502E.pdf)。

Flash 保存的是固件和内置曲目。UART 导入曲谱仍位于运行时 RAM，断电后恢复默认曲库；IMU 校准和 AUTO 状态也不会自动保存。每次启动默认 `AUTO OFF`，先将模块正 Z 向上水平静置，点一次 `CALIBRATE`，待 `CAL...`／`SETTLING` 结束后再手动开启 AUTO。当前校准需连续 256 份合格样本，若一直停在 `CAL...`，先检查放置方向及静止数据。

以下为**历史全宽舞台阶段（2026-10-15）**的验收与资源记录，继续保留，不作为当前新版的构建结果。

2026-10-15 用户先确认 `a13fd79` 修复版无已知问题，随后反馈全宽舞台“现在效果还可以”，授权 push 并合入 master。
该反馈记录在 [hardware_acceptance.json](gowin/neo_guitar_touch_game/hardware_acceptance.json)；现场烧录文件的哈希没有另行采集，未新增定量声学或长期稳定性测量。
全宽舞台源码为 `246b146`＋`98ba437`，发布审计为 `4bf7e0c`，详细实现见 [全宽舞台说明](docs/FULL_WIDTH_GAME_STAGE.md)。

![全宽舞台实际 RTL 像素预览，计分为仿真数据](docs/images/full_width_game_stage.png)

历史全宽舞台已通过完整数字验证，固定归档为 [neo_guitar_touch_game_full_width.fs](T:/Documents/AMD/xinxian-fpga-guitar/build/releases/touch_game/neo_guitar_touch_game_full_width.fs)，
SHA256 `9c161ac673cd1c081831075f4f84d4ff2067f6a20797119b9a65d9623b770883`。
六帧综合网表显示、364 次连续布局、九项 RTL 回归及音频 8192 样本对照通过，未布通／setup／hold 均为 0。
CLS 29842/29952（99.63%），BSRAM 95/118、DSP 115.5/118；系统／音频 Fmax 54.636／13.441 MHz。
该历史版本面积余量较小，随后已实施 P1 及曲库／姿态功能；其数字验证、用户认可和发布记录继续保留。当前完整版本资源以本节并列表为准。
默认是训练配置，试听与短促 Miss 提示开启；严格比赛配置和展示边界见 [合规说明](docs/TOUCH_GAME_COMPLIANCE_NOTES.md)。

### 0.1 已完成

- **双 PCB 全链路已实物通过：** 4×8 矩阵与 MCP3208 CH0～CH3 同接 Mega 60K，支持空弦、最高品优先、真实拨弦触发、四声部并发、换品滑音及松品续空弦。只按品不发声，当前按真实拨弦峰值分为四档，使用 25%／50%／75%／100% 声部增益。
- **重力传感与 Flash 启动实物通过：** 2026-10-23 用户确认 ID70 兼容后的完整固件可正常使用 IMU，并可从外部 Flash 断电重启；校准／AUTO 和 RAM 导入曲目仍需每次启动重新设置／导入。
- **多曲目与可写曲库已接入：** 保留《茉莉花》、Seven Nation Army riff 和《情歌》完整主旋律，删除原创慢练；五槽目录通过 UART 暂存、CRC／实际 RAM 读回校验后原子提交。
- **三音色完整保留：** 钢琴保留 8 个主体模态，击弦改为实时随机激励、滤波及阻尼谐振器；明亮弦音和哇音最多各 32 个分量，哇音保留半倍频模态和三个音区动态包络。生产音源不读取预录击弦 PCM。
- **哇音 V4 已获实物听感认可：** 无效果自然尾音约 1.16 秒，延音约 4.50 秒；前 2048 样本（42.67 ms）与 V3 相同。本轮松品保持原音并继续自然包络，哇音算术与衰减参数保持不变。
- **三键控制已上板验证：** USER_BUTTON1 循环三音色；USER_BUTTON2 短按切换合唱、长按约一秒切换自动五度和声；USER_BUTTON3 循环无效果／延音／轻量混响。上电默认钢琴且音效关闭，内部自动初始化。
- **每声部最多 32／每帧最多 128 个分量已实现：** 四声部并行、声部内分时计算；128 个非零分量的预算测试通过，音源调度为 233／256 个 12.288 MHz 时钟。自动和声使用每声部 16 主音 + 16 五度分量，保持原预算。
- **双音频输出已实现：** 固定窄弦位声像、合唱与公共轻混响后，最终 PCM24→PCM16 同时送给 PT8211 和标准 I²S。两个发送器共享音源和音效计算；新增 I²S 不增加 DSP 或 BSRAM。普通音符之间功放保持开启。
- **显示与演奏已整合：** 实际品位、拨弦和滑音驱动四弦渐变与莉萨如；1024 点 FFT 分析最终音效后的 PCM，生成 64 根环形谱柱。松品续音、曲线渐暗和当前双输出程序均已有用户实物验收反馈。
- **双输出基线数字验证通过：** I²S 独立协议测试检查 309 对样本；完整链路的 8192 对 I²S 样本与 PT8211 解码一致，原音频运算在 2,097,153 个参考时钟上逐周期一致。覆盖左右声道、帧边界、补零、复位、音色和全部音效。
- **双输出基线固定引脚与网表验证通过：** 7632 个 PT8211 帧与 RTL 一致，7631 对完整 I²S 样本与 PT8211 一致；7,949,456 个系统时钟及 1,115,060 个 LCD 有效像素与 RTL 一致。当前触控游戏另有前述六帧显示及音频保真回归。

历史双输出基线的数字验证构建资源及时序（Gowin V1.9.12.03，GW5AT-LV60PG484AC1/I0，Device B；当前完整版本资源见第 0 节的新旧并列表）：

| 项目 | 历史双输出基线 `neo_guitar_i2s` |
| --- | --- |
| Logic / 59904 | 47470 |
| Register / 60780 | 18733 |
| CLS / 29952 | 26282 |
| BSRAM / 118 | 86 |
| DSP / 118 | 115.5 |
| 音频 Fmax（目标 12.288 MHz） | 14.340 MHz |
| 系统／显示 Fmax（目标 50 MHz） | 59.995 MHz |
| Setup / Hold 违例 | 0 / 0 |

双输出基线移除预录击弦 ROM 后，BSRAM 从旧环形版本的 118 降为 86，释放 32 块；后来的全宽舞台为 95/118，当前曲库／姿态完整版为 113/118。
DSP 仍为 115.5/118；扩展功能前需评估复用和调度，现有实现尚未达到第 11.3 节的全部资源余量目标。

当前原工程位流与同名发布副本已完成所需数字回归、完整综合、P&R／STA 和源码／ROM／网表／日志／位流哈希绑定；可直接用 Programmer 烧录，无需为下载再运行综合布线。
以后修改 RTL 时，继续打开 `gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj`，在原工程执行 Synthesize、Place & Route，并完成对应版本回归后更新认证。沿用现有 CST／SDC 和用户配置，不运行旧 `configure_ide.ps1` 来覆盖当前设置。
当前配置保留 Place=4、Route=2、Clock Route Order=0、Route_Maxfan=32，以及 hold 修复和 CPU／SSPI／I2C 引脚 GPIO 复用。

`build/`、`impl/`、`sim/temp/` 中的位流、WAV 和完整报告为本地生成产物，不随 Git 提交；工程配置与各阶段精简认证随源码保存。新克隆需构建自己的产物并重新验证；本机未来 IDE 重建的新网表／位流也不能用旧门级日志认证。历史 `gowin/build_full.tcl` 是自动引脚逻辑构建，不用于实物下载。

详细证据见：

- [当前触控／游戏工程与验收记录](gowin/neo_guitar_touch_game/README.md)
- [双音频输出基线与验收记录](gowin/neo_guitar_i2s/README.md)
- [标准 I²S 接线、时序与验证](docs/STANDARD_I2S_VALIDATION.md)
- [当前 ID70 完整版资源、时序与哈希记录](gowin/neo_guitar_touch_game/imu_id70_verification.json)
- [旧版四档力度资源、时序与哈希记录](gowin/neo_guitar_touch_game/quarter_dynamics_verification.json)
- [历史 P1 资源、时序与哈希记录](gowin/neo_guitar_touch_game/verification.json)
- [实时滤波／模态击弦与赛题条款对照](docs/PROCEDURAL_PIANO_HAMMER.md)
- [环形显示、曲线渐暗与松品续音](gowin/neo_guitar_radial/README.md)
- [历史三键音频 FULL 上板说明](gowin/neo_guitar_audio_full/README.md)
- [哇音 V4 分析、实现及试听说明](docs/WAH_REFERENCE_TIMBRE.md)
- [历史哇音 V4 资源、回归与门级 DAC 证据](docs/evidence/wah_long_decay_acceptance.txt)
- [钢琴／明亮弦音的 V2 音效基线](docs/FULL_EFFECTS_V2.md)
- [FULL 复位、时序与资源证据](docs/evidence/full_reset_timing_acceptance.txt)
- [FULL 实时耐久证据](docs/evidence/full_realtime_acceptance.txt)
- [输入覆盖与内部延迟证据](docs/evidence/full_input_latency_acceptance.txt)
- [NEO MINIMAL 仿真、实现与实物验收证据](docs/evidence/neo_minimal_audio_acceptance.txt)
- [NEO ROW0 单组触点仿真、实现与实物证据](docs/evidence/neo_row0_led_acceptance.txt)
- [四弦矩阵音频优化交接记录](docs/HANDOFF_NEO_MATRIX_AUDIO_OPTIMIZATION.md)
- [NEO 四弦矩阵音频测试说明](docs/NEO_FOUR_STRING_MATRIX_AUDIO_TEST.md)
- [双 PCB 全链路接线、参数与上板步骤](docs/NEO_FULL_CHAIN_AUDIO_TEST.md)
- [双 PCB 全链路仿真与固定引脚实现证据](docs/evidence/neo_full_chain_audio_acceptance.txt)
- [主工程同步、构建与可选功能说明](docs/MAIN_ENGINE_SYNC.md)
- [三音以上减拍频策略、参数及 A/B 试听](docs/ANTI_BEAT_AUDIO.md)
- [古典大钢琴参考录音分析与离线音色样音](docs/PIANO_REFERENCE_ANALYSIS.md)
- [钢琴音源、击弦起音与 FPGA 主工程试验](docs/PIANO_FPGA_TRIAL.md)
- [早期主工程同步数字验收证据](docs/evidence/main_engine_sync_acceptance.txt)
- [Tang Mega 60K / NEO Dock 板级集成审查](docs/BOARD_INTEGRATION_REVIEW.md)
- [NEO Dock 31005 / Mega 60K 板级连接矩阵](docs/NEO_31005_60K_PIN_MATRIX.md)

### 0.2 当前板级集成门槛

| 实物项目 | 当前状态 | 说明与后续工作 |
| --- | --- | --- |
| MS5351M CLK2 / 12.288 MHz | 已验证 | 已确认示波器频率、FPGA 音频链使用及完整断电自动恢复 |
| `MINIMAL` PT8211 音频 | 已验证 | E4 约 329.63 Hz、左右声道、连续发声及无明显周期性爆音/断音均已通过 |
| 三枚 USER_BUTTON | **音频 FULL 实物通过** | AA13 音色、AB13 合唱／五度和声、Y12 无效果／延音／轻混响；当前工程无外部复位键 |
| 品位板 ROW0 单组选音与发声 | **实物通过** | 已确认空弦及第1～8品选音、PT8211 实际发声和同组多品最高品优先；不代表完整矩阵通过 |
| 四弦矩阵音频优化版 | **实物通过** | 2026-10-02 已确认 4×8 扫描、四声部并行发声、和弦捕获、动态硬立体声、自然衰减和 PT8211 输出 |
| 品位板 ROW1～ROW3 | 已在四弦矩阵音频测试中覆盖 | 已随完整 4×8 扫描完成实物发声验证；早期 ROW0 单行记录仍作为独立诊断证据保留 |
| 完整 4×8 矩阵扫描 | **双板全链路实物通过** | 已与 MCP3208 拨弦和优化音频同接验证 |
| MCP3208 采集板 | **单板及双板集成实物通过** | 已接入队友实测阈值和真实峰值四档；重复性／串扰／声压定量测试仍待补充 |
| 双 PCB 输入与三音色／音效 | **实物通过** | 当前 `neo_guitar_touch_game` 演奏模式复用原链路；继续补充长时间演奏、串扰和音频定量测试 |
| 松品续音 | **实物通过** | 松品滑向空弦，保持原自然衰减；只有拨弦重新触发包络 |
| 环形频谱／莉萨如／渐暗 | **用户已验收当前程序** | 480×272；左四弦渐变，右 150×150 曲线及 64 根谱柱 |
| 程序生成钢琴击弦 | **固定三音干声试听及当前程序实物通过** | 生产链无预录击弦 PCM；旧版仅用于仿真参考 |
| PT8211＋标准 I²S 双输出程序 | **2026-10-13 用户下板验收通过** | 协议及完整网表对照通过；外接 DAC 型号和专项实测结果尚未单独记录 |
| LCD 接线与供电 | **显示已通过** | J5、J17 1–2、8.333 MHz、RGB666；背光额定电流匹配仍待单独确认 |
| GT911／模式选择／四轨游戏 | **2026-10-15 用户认可并批准发布** | 修复版 `a13fd79` 已验收；全宽舞台 `246b146`＋`98ba437` 获效果认可，本次纳入 master |
| 四档力度 | **真实峰值四档已实现并通过数字回归** | 当前 25%／50%／75%／100%，第一弦阈值 220、第三弦 60；实物统计和声压标定仍待补充 |
| 重力／姿态传感器 | **2026-10-23 用户确认正常工作** | 完整吉他固件支持 ID68／ID70 配置；保持 J8 独立 I²C 接线，开机先校准再启用 AUTO |
| 外部 Flash 固件启动 | **2026-10-23 用户确认断电重启可用** | 固件与内置曲目保留；UART 导入 RAM 曲谱、IMU 校准及 AUTO 状态不随之持久保存 |

- 底板为 NEO Dock 31005，核心板仍标为 30353/30354 之一。当前 J13 矩阵接线已实物通过并包含 Bank 1；沿用其既有 LVCMOS33、电源与接线，本次没有修改供电或扩展其它 Bank 1 接口。早期连接矩阵中的通用禁用规则和 PMOD 候选分配由此实测方案取代。
- 50 MHz、PT8211、功放、三枚用户按键和 `USR_CLK_IN` 已由 31005 原理图、两版核心板共同部分及官方 60K CST 交叉核对。
- NEO Dock MS5351M 的 CLK2 已设置为 12.288 MHz；示波器及 MINIMAL 实物音频链均已确认 FPGA 可稳定使用该时钟，完整断电后会独立自动恢复，不需要电脑、MCU、BL616 运行时配置或软核 CPU。
- 当前 CST/SDC 为 `constraints/neo_guitar_touch_game.cst` / `constraints/neo_guitar_touch_game.sdc`：沿用 J13 矩阵、J8 ADC、J5 LCD、板载音频、三枚用户键、LED 和 J9 I²S，包含 J6 四根触控 GPIO，并增加 DEBUG-USB2 UART（TX=U15、RX=V14）及独立 IMU（SCL=Y21、SDA=Y22），共 63 个固定且互不冲突的球位。I²S 三根为 Bank 7 的 LVCMOS33，不能与 SDRAM1/DVP 等复用外设同时驱动。
- LCD 已到货。31005 的 J5 40-pin 连接器采用 RGB888 针脚排列，FPGA 连接 R2-R7、G2-G7、B2-B7 共 18 bit，每色低两位在底板接地；线路与 CH569 HSPI 共用。独立演示固定引脚见 `constraints/neo_lcd_lissajous.cst`，使用 J17 1–2 跳帽关闭 CH569。
- 当前 `USER_BUTTON1=AA13` 用于音色切换；USER_BUTTON2=AB13、USER_BUTTON3=Y12 用于音效。旧工程中的 AA13/KEY0 复位定义不适用于当前音频 FULL。`SW7/RECONFIG=N12` 是 FPGA 专用重配置按钮，会触发重新加载配置，区别于 RTL 内部复位；临时 SRAM 程序会丢失，Flash 中已保存固件时可重新加载它。内部上电初始化不占用用户键。
- ROW0 LED 初测曾使用 PMOD1 的全部八根 GPIO 作为 COL0～COL7、PMOD0 的八根 GPIO 作为调试 LED。随后进行的 ROW0 音频闭环测试已移除 LED，只保留 PMOD1 八列输入，ROW0 直接接地、ROW1～ROW3 悬空，并通过 PT8211 输出判断所选音高。两种临时接法都与最终 12 线矩阵分配互斥，只能用于逐组诊断。

现有 **FULL 自动引脚** `.fs` 只能证明逻辑规模与时序可实现，**严禁烧录到实物板**。原始与复位修正后的 FULL 结果均已保留，不应覆盖。`neo_minimal_audio`、`neo_row0_led_test`、`neo_row0_audio_test` 与 `neo_four_string_matrix_audio_test` 是采用各自专用约束的独立实物测试构建，不属于这条自动引脚禁令，但仍应保留在各自工程中且不得混烧。

### 0.3 当前实物工作顺序

1. 使用当前 ID70 兼容的完整 `neo_guitar_touch_game` 固件；Flash 烧录及断电重启已由用户确认，保持 J17 1–2 跳帽牢固，历史位流继续保留用于排错。
2. 每次上电先水平静置模块并校准，再按需开启 AUTO；检查空闲姿态切音色、手动优先及持续音结束后的切换。
3. 现已启用真实四档力度，继续补充四弦阈值重复性、串扰、快速重拨、三／四音和弦及各音效组合的实物记录。
4. 用逻辑分析仪记录 J9 标准 I²S 和 PT8211 帧，补充外接 DAC 联调、物理拨弦到模拟输出延迟及长时间演奏测试。早期 [输入延迟记录](docs/evidence/full_input_latency_acceptance.txt)不作为当前三音色整机延迟实测值。
5. 蓝牙实物闭环、UART 导入曲谱断电保存和后续音色继续按各自阶段记录，等待用户明确指令；当前 Flash 启动反馈不替代这些项目的验收。

以下 0.4～0.10 为各阶段的历史验收记录；其中当时的工程入口、复位键、音色和待办状态不代表当前 master 配置。

### 0.4 历史：2026-09-27 板级交接记录

- 已完成 NEO Dock 31005、两版候选 60K 核心板原理图和官方 CST 的交叉核对，并建立完整连接矩阵；核心板版本继续标记为 30353/30354 未确认，Bank 1 禁用。
- 已记录 MS5351M CLK2 到 `USR_CLK_IN=V13` 的 12.288 MHz 示波器测量结果；该条目记录时尚待验证的 FPGA 音频链和完整断电恢复，随后已在 0.5 节的 MINIMAL 实物验收中完成。
- 已审查官方 138K `audio_i2s` 示例。其 PT8211 帧格式和共用底板网络可用于 MINIMAL 波形对照，但 138K 器件原语、PLL、CST、复位脚和工程顶层不得移植到 60K。
- 已发现首次 MINIMAL 上板需要单独处理功放极性：`minimal_top.pa_en` 是高有效请求，物理 `PA_EN=AB16` 为低有效；在保持现有音频 RTL 不变的前提下，由板级包装层输出复位安全的 `pa_en_n`。
- 本次只更新审查资料，没有修改 RTL、CST/SDC 或现有综合/布局布线结果；自动引脚 `.fs` 仍不可烧录。

### 0.5 历史：2026-09-27 NEO MINIMAL 实物验收

- 成功工程：`gowin/neo_minimal_audio/neo_minimal_audio`；顶层为 `neo_minimal_audio_top`，当前只通过 SRAM Program/Configure 下载，没有写入外部 Flash。
- 已把成功工程中的音频域异步复位/同步释放和低有效 `pa_en_n` 包装正式同步回 `rtl/top/neo_minimal_audio_top.v`；实物 CST/SDC 位于 `constraints/neo_minimal_audio.cst` 与 `constraints/neo_minimal_audio.sdc`。Gowin 工程平铺源码中的 include/readmemh 路径调整不反向带入仓库标准目录结构。
- 实物闭环为 12.288 MHz CLK2→E4 phase increment→`voice_audio_core`→PCM24/PCM16→`pt8211_tx`→PT8211→3.5 mm 左右声道；实测约 329.63 Hz，可持续发声，无明显周期性爆音或断音。
- KEY0/AA13 是 RTL 低有效复位：按住静音，松开后 E4 自动恢复。RECONFIG/N12 会清除 SRAM 配置，作用与 RTL reset 不同。
- 板级运行中复位 testbench 已通过：`PASS: MINIMAL runtime reset mutes and retriggers continuous E4`。EX3791 本轮未修改；在需要显式位宽清理前必须先后执行 PCM 黄金模型与相关 testbench。

### 0.6 历史：2026-09-27 ROW0 单组初步实物验收

- 独立工程：`gowin/neo_row0_led_test/neo_row0_led_test`；它与成功音频工程分开保存。工程启用 `CPU pins as regular I/O`，即 `process_config` 中 `"CPU": true`，只把 P19/R19/T21/U21 用作普通 FPGA GPIO，不使用任何 CPU。
- 临时接法为 ROW0 直接接地、ROW1～ROW3 不连接、PMOD1 全部八线输入 COL0～COL7、PMOD0 全部八线输出 LED0～LED7。ROW0 八个触点的对应测试未发现问题。
- 最新 P&R 中 PR2017=0、PR2028=0、setup/hold 违例均为 0；Pin Report 的 16 个 COL/LED 端口全部位于指定球位。详细结果见 `docs/evidence/neo_row0_led_acceptance.txt`。
- 仓库 testbench 按真实防抖周期通过：`PASS: ROW0 columns debounce, mapping, multi-press and reset`。
- 当时的验收边界：该 LED 测试不能证明 ROW1～ROW3、完整 4×8 扫描、未选中行高阻、多行防鬼键、四弦同时按键或选音/滑音/声部控制实物集成；后续 0.7 节已补充完成 ROW0 单组的最高品优先和选音到音频实物验证。

### 0.7 历史：2026-09-28 ROW0 选音到音频实物验收

- 独立工程：`gowin/neo_row0_audio_test/neo_row0_audio_test`；保留已经成功的 `neo_minimal_audio` 和 FULL 自动引脚 P&R 基线，不在原工程上覆盖修改。
- 实物接法为 ROW0 直接接地、ROW1～ROW3 不连接、PMOD1 全部八线输入 COL0～COL7；本阶段不再连接 PMOD0 LED。音频仍使用已验证的 12.288 MHz CLK2、PT8211 和 3.5 mm 输出链路。
- 选音链路为 COL 输入→两级同步→约 5 ms 的 8-bit 整体防抖→最高品优先编码→`note_phase_table`→`voice_audio_core`→PCM24/PCM16→`pt8211_tx`→PT8211。无按键对应第0品 E4，COL0～COL7 分别对应第1～8品 F4～C5。
- 实物测试已确认空弦及八个品位能够控制实际输出音高；同组多个品位同时按下时选择最高品，松开最高品但保留较低品时回到剩余按键中的最高品，全部松开后回到 E4 空弦音。
- 该工程使用 FPGA RTL 产生持续测试音，目的只是证明品位选择与音频链连接正确；不使用 MCU 或软核 CPU，也尚未接入 MCP3208 拨弦事件、滑音、Release 或四声部控制。
- 验收边界：ROW1～ROW3、4 ROW 的低电平/高阻逐行扫描、跨行多键、防鬼键、四弦同时发声及最终 `fret_note_event`/`four_string_voice_control` 集成仍需实物验证。

### 0.8 历史：2026-10-02 四弦矩阵音频优化版实物验收

- 当前四弦矩阵音频优化版已完成实物上板验证。独立工程为 `gowin/neo_four_string_matrix_audio_test/neo_four_string_matrix_audio_test.gprj`，顶层为 `neo_four_string_matrix_audio_test_top`；该结果补充了 0.7 节当时尚未完成的 ROW1～ROW3、真实 4×8 扫描和四声部实物发声验证，但不覆盖或替代此前各独立工程。
- 当前上板链路包括 4×8 品位矩阵扫描、四个独立 RTL 音频声部、约 30 ms 和弦捕获、PCM24→PCM16、`pt8211_tx`、NEO Dock PT8211 和左右声道输出。全部运行时处理由 FPGA RTL 完成，不使用 MCU 或软核 CPU。
- 拨弦测试包络参数为：约 2 ms Attack、约 200 ms 初始快速衰减、延长约 2 倍的慢速自然尾音以及松品时独立快速阻尼；不设置固定 Sustain 平台。通用 `voice_envelope`、`voice_audio_core` 和 `four_voice_audio_core` 的 `PLUCK_MODE` 默认仍为 0，只有该矩阵音频测试顶层显式设置为 1，因此当时 MINIMAL/FULL 的默认 ADSR 行为没有改变。2026-10-03 主工程同步后，当前主顶层显式启用拨弦模式，底层模块默认仍为 0 以兼容旧实验。
- `pa_en_n` 在复位期间关闭 PA，复位释放后保持 PA 开启，不再随普通 `note_on`/`note_off` 反复切换。KEY0 释放或 FPGA 刚配置时仍可能出现一次模拟启动瞬态，但普通音符之间不应重复产生 PA 启动爆破音。
- 声道策略为 note-on 时动态选择负载较小的声道，最先出现的两个声部优先分配到相反声道；声部生命周期内不换声道，不加入 crossfeed，每个声道的主声部和除以 2 以保留四声部余量。两个相近但不同的真实频率仍会产生物理拍频，后级合成单声道时拍频也可能重新出现。
- 主回归已覆盖连续四声部、相同 F4 phase increment、捕获窗口、首对声部硬分离、PA 常开和无 Sustain 的自然衰减；兼容性回归继续通过原 ADSR、四级力度、KEY3 延音及四声部独立生命周期。具体 PASS 信息与实现说明见 `docs/HANDOFF_NEO_MATRIX_AUDIO_OPTIMIZATION.md` 和 `docs/NEO_FOUR_STRING_MATRIX_AUDIO_TEST.md`。
- 本次实物验收只记录已观察到的功能结果，没有示波器截图、精确噪声、THD、SNR 或其他定量音频指标，不据此虚构数值结论。
- 约 30 ms 和弦捕获窗口只是没有接入真实拨弦传感器时的测试办法，不是最终产品方案。此条记录时 MCP3208 尚未实物测试，2026-10-03 已补充完成独立验证；最终产品仍应由矩阵负责音高、MCP3208 负责真实拨弦检测并产生 `note_on` 和 velocity，再驱动四个持续并行声部。

### 0.9 历史：2026-10-03 MCP3208 独立验证与双 PCB 集成工程

- 最新提交 `2cb7419` 与用户确认表明 `gowin/test3` 已实物通过：MCP3208 CH0～CH3 分别用压电拨弦触发 E4/B3/G3/D3，采用固定音量。
- 新增独立工程 `gowin/neo_full_chain_audio_test`：矩阵只选品，ADC 才触发起音；复用优化音频链，增加约 20 ms 平滑滑音与最后品位释放时的音高保持/阻尼。
- 两套最新实物 CST 共用的时钟、复位和音频引脚一致，其余引脚无冲突；合并后 26 个端口使用 26 个球位，实际 Pin Report 全部符合约束。
- 三组 ModelSim 回归均为 Errors=0、Warnings=0；最终固定引脚 Gowin 实现分析 4750 个端点，setup/hold 违例均为 0。用户随后确认双 PCB 同接测试结果理想；该功能验收来自用户实物反馈，没有新增定量声学测量。
- 当前集成工程保留固定力度 2，未宣称四级力度、谐波/音效或显示功能完成整机验收。详情见 [全链路说明](docs/NEO_FULL_CHAIN_AUDIO_TEST.md)。

### 0.10 历史：2026-10-03 正式主工程同步

- 主 `guitar_audio_top` 改用单一音频域输入处理；复用实测 ADC 偏置/迟滞和音频参数。
  新 `guitar_play_control` / `four_string_board_audio_chain` 管理真实拨弦、滑音、立即松品阻尼、
  自然声部结束及动态硬立体声。PA 在复位后常开。
- `xinxian_mega60k.gprj` 已从 LED 顶层改为标准 RTL 的 `neo_guitar_main_top`；
  使用当前 26 引脚 CST/SDC，不需要改现有线束。新主工程本身尚未替用户实际下载。
- 可选 FULL 保留谐波、音色切换、延音和独立双声道音效，FFT 读取最终左右平均 PCM；
  当前物理主入口默认正弦，不增加未接入的 LCD/效果键端口。
- 关闭新增减拍频混音时，主工程与成功验证工程在对齐复位释放后逐周期一致，覆盖 36 个音高、所有六种首对双弦、
  双向拨弦、重拨、松品/空弦和自然尾音。完整记录和复现命令见 [同步说明](docs/MAIN_ENGINE_SYNC.md)。
- 新减拍频混音保持四声部及原音高；优先把频差较大的组合放入同侧，必要时将较早起音的近邻声部平滑降至半幅。已完成实际 RTL PCM A/B 导出及针对性回归，默认开启，实际听感待用户复核。

## 1. 项目目标

首版整机需要完成以下闭环：

- 4 根弦、每弦 8 个有品触点，并支持无按键时的空弦音；
- 4 根弦可同时发声，每根弦固定对应一个独立声部；
- 每个声部最多包含 32 个逻辑谐波／模态分量，单个 48 kHz 样本内最多计算 128 个分量；
- 4 级拨弦力度，不采用 MIDI 0～127 力度精度；
- 支持持续音中的跨品滑音；
- 支持钢琴、明亮弦音和哇音三套实时合成音色；
- 支持合唱、延音、轻量混响和自动五度和声；
- 通过板载 PT8211 DAC 输出至 3.5 mm 耳机和 2×3 W 扬声器接口；
- 通过已到货的 4.3 寸 480×272 并行 RGB LCD 显示实时频谱；FULL 内部颜色保持 RGB888，板级输出使用 NEO Dock 31005 实际可控的 RGB666/18-bit DPI；
- FPGA 内部数字链路最坏延迟不超过 5 ms，整机最坏延迟不超过 10 ms；
- `FULL` 配置下通过综合、时序、资源和整机演示验收。

### 1.1 非目标与扩展项

以下内容不属于首版强制验收：

- Karplus–Strong 弦模型；
- 无拨弦击弦、勾弦；
- 运行时 UART 在线调参；
- MIDI 0～127 连续力度；
- DDR3 图形帧缓存、图片或复杂 GUI；
- 外接 24-bit 标准 I²S DAC；
- 6 弦或更多品位；
- 软核 CPU、外部 MCU 参与运行时音频处理。

### 1.2 可选附加功能（不纳入首版 `FULL` 强制验收）

在首版 `FULL` 音频、显示、时序和板级接口稳定后，可增加以下两个 FPGA 原生扩展。扩展功能不得回退或破坏已有四声部音频主链路，运行期间仍必须由可综合 Verilog/SystemVerilog RTL 完成，不得引入软核 CPU、外部 MCU 或软件运行时算法。

#### 1.2.1 FM/PM Lite 音色模式

作为现有波表加法合成之外的可选音色模式，每个声部可以增加：

- 一个调制相位累加器；
- 一个调制频率比；
- 一个调制深度；
- 一条额外的正弦查表路径；
- 一个载波相位调制计算路径。

该模式应复用现有声部的包络、力度、滑音、PCM24 混音和 PT8211 输出链路，并通过模式选择或参数配置启用。它可以提供更明显的金属、铃声和合成器类音色，同时不要求大规模新增波表存储。

新增 FM/PM 逻辑必须验证调制深度边界、相位溢出、音量归一化、切换无爆音、样本截止时间和资源变化；不得因为增加该模式而降低现有三音色的验收结果。

#### 1.2.2 FPGA 原生节奏指导演奏模式

当前已实现全宽四轨判定、《情歌》完整主旋律、静态多曲目及可写曲库／UART 导入，见 [当前工程](gowin/neo_guitar_touch_game/README.md)。以下保留原节奏指导的设计范围，当前游戏仍无需按品：

- 四条轨道，对应四根弦；
- 由 `.mem`/ROM/片上 B-SRAM 保存的预编译音符时间表；
- 音符滚动、判定线和有限数量的视觉提示；
- 基于现有矩阵和拨弦事件的命中窗口判定；
- `Perfect/Good/Miss`、连击和分数计数；
- 复用现有 RGB 时序和坐标驱动显示，在频谱显示与指导模式之间切换或叠加。

该模式不得依赖运行时 CPU、MCU、联网谱面解析或完整帧缓存。若需要大量歌曲、复杂图片、触摸菜单或动态资源加载，应另行评审 Flash/DDR3 和板级接口，不自动纳入本扩展项。

两个附加功能均须满足以下条件后才能合入正式 `FULL` 分支：

- 原有音频链路仿真全部通过，且无 `deadline_miss`、FIFO underflow/overflow 或音频掉样；
- 所有目标时钟域 WNS ≥ 0；
- LUT、DSP、B-SRAM 和 CLS 仍保留 README 要求的资源余量；
- 新增独立 testbench、频谱/判定证据和综合/布局布线报告；
- 没有确认的板卡引脚不得写入正式 CST，新增显示或输入接口只能先以仿真和无引脚 RTL 形式验证。

## 2. “纯硬件音频主链路”的边界

运行期间，下列功能必须由 FPGA 内部可综合 HDL 逻辑实时完成：

1. 左手按弦状态扫描与最高品位判定；
2. 右手拨弦触发、峰值检测结果读取和 4 级力度判定；
3. 音高选择、滑音和四声部状态管理；
4. 谐波／模态加法合成、包络衰减和四声部混音；
5. 软削波、合唱、延音和轻量混响；
6. PCM 格式转换与 PT8211 串行音频输出；
7. FFT、频谱柱生成和并行 RGB 显示时序输出。

允许离线软件生成频率控制字、谐波系数、衰减系数、正弦表和 Hann 窗等 ROM 文件；允许使用 Gowin EDA 完成综合、烧录和一次性外设配置。外部 MCP3208 与 PT8211 只负责信号转换，不参与音符判断、音色生成或音效计算。

## 3. 硬件基线

### 3.1 FPGA 与底板

| 项目 | 固定配置 |
| --- | --- |
| 核心板 | Sipeed Tang Mega 60K SOM，实物为 30353/30354 之一，版本暂未确认 |
| 底板 | 官方 Tang Mega NEO Dock 31005，实物已确认 |
| FPGA | `GW5AT-LV60PG484AC1/I0` |
| Gowin 器件选择 | `GW5AT-60B`，封装 `PBG484A`，Device Version `B` |
| 逻辑资源 | 59,904 LUT4、59,904 FF |
| B-SRAM | 2,124 Kbit，118 块 |
| 18×18 DSP | 118 个 |
| 板载存储 | 512 MiB DDR3、64 Mbit Flash |
| 板载 DAC | PT8211-S，双声道 16-bit、LSB-justified |
| 主要供电 | 12 V DC5521，适配器额定电流至少 3 A |

当前外部 GPIO 按已实测的 J13 矩阵和 J8 ADC CST 分配，保留其 3.3 V 电平。三枚板载按键位于 1.5 V Bank 9，全部用于当前音频 FULL 的音色／音效控制；新的外设接线须核对球位、电压和复用关系。

### 3.2 左手琴颈

琴颈使用 32 个导电橡胶触点、PCB 电极和逐键二极管，构成 4×8 矩阵：

- 4 条扫描线对应 4 根弦；
- 8 条返回线对应第 1～8 品；
- 每次只激活一条扫描线，其余扫描线置高阻，避免输出冲突；
- 返回线使用约 10 kΩ 外部上拉，扫描线串联约 220 Ω～1 kΩ 保护电阻；
- 每个触点串联 1N4148 或同类小信号二极管，方向随最终有效电平统一；
- FPGA 内部执行双触发器同步、扫描、积分式去抖和最高品位优先编码；
- 同一根弦允许多品同时按下，但只用最高品位决定音高；
- 没有品位按下时，该弦的选音状态为第 0 品空弦。

长排线或外露琴颈接口应增加 ESD 防护。矩阵完整 8-bit 状态需保留为调试信号，不能只保留编码后的品位号。

### 3.3 右手拨弦结构

每根弦使用一条独立 TPU 弹性条：

- TPU 条建议初始尺寸：长 30～60 mm、宽 2～5 mm、高 2～6 mm、间距 8～12 mm；
- 两端夹持并施加轻微预张力，中间悬空供拨片或手指拨动；
- 每根 TPU 条的一端连接独立桥码；
- 桥码向贴有压电片的 FR-4 或薄金属弯曲梁传力；
- 四个桥码进行机械隔离，压电陶瓷不承受拨片直接冲击；
- 一端夹具应可调，以统一四根“弦”的张力和回弹手感。

尺寸、材料硬度、桥码质量和弯曲梁厚度均属于样机标定项，不能仅依靠理论值冻结。

### 3.4 压电模拟前端与 ADC

四路信号链如下：

```text
TPU 条 → 独立桥码 → 弯曲梁/压电片
      → 输入限流与双向限幅 → 高阻缓冲/增益
      → 包络检波与峰值保持 → MCP3208 → FPGA SPI
```

基线 ADC 为 3.3 V 供电的 MCP3208：12-bit、8 通道、SPI。首版使用 4 个通道，剩余通道可扩展旋钮或其他传感器。FPGA 读取的是处理后的包络／峰值，不是原始压电振动音频。

要求：

- ADC 总轮询速率不低于 40 kS/s，每根弦有效采样率不低于 10 kS/s；
- 四根弦分别配置静态偏置、噪声门限和 4 级力度阈值；
- 上电后先测基线，再开放触发；
- 使用迟滞、峰值保持释放时间和再触发死区抑制回弹连击；
- 使用短时峰值对比识别机械串扰，但不得吞掉真实快速扫弦；
- 原始 ADC、包络、峰值、力度级和时间戳均保留调试观测点。

力度接口不使用“0 表示未触发”的模糊约定，而采用独立有效位：

```verilog
pluck_valid
string_id[1:0]
velocity_level[1:0]   // 四级力度
event_timestamp
```

### 3.5 显示器

实际显示器为 **4.3 寸、480×272、并行 RGB、带独立 GT911 电容触摸接口**。NEO Dock 31005 的 J5 包含 R0-R7、G0-G7、B0-B7，FPGA 连接 R2-R7、G2-G7、B2-B7 共 18 根颜色数据；六根颜色低位在底板接地。LCD 数据/控制线路与 CH569 HSPI 共用，测试时使用 J17 的 1–2 跳帽关闭 CH569。该接口是并行 TTL/DPI RGB。

当前整机沿用已验证的 50 MHz 六分频、8.333 MHz DCLK、531×292 总时序、480×272 有效区及下降沿更新，约 53.745 Hz，板级输出为 RGB666。演奏模式左侧为四弦渐变，右侧为 150×150 莉萨如和 64 根环形频谱柱；游戏模式切换为全宽四轨。仍需单独完成的核对为：

- 到货模组准确型号及商品 ST7625/IPS 信息与 PDF 的差异；
- 面板端实际信号完整性及 setup/hold 裕量；
- 背光额定电流与底板恒流设置的匹配；
- GT911 多场景、长时间操作和故障恢复的追加实测；原生 J6 触控与菜单已经接入。

当前固定引脚音频／FFT／LCD／I²S／触控入口为 `neo_guitar_touch_game_top`；独立 [莉萨如演示](gowin/neo_lcd_lissajous/README.md)保留作显示排错。RGB 屏无需 HDMI，当前显示不依赖 GT911 初始化；历史 FULL 自动引脚位流不用于实物。

此前候选的 540×960 MCU888/RGB888 屏不作为固定基线，除非卖家补齐上述资料，并确认其 RGB 模式、扫描方向、时序、电平和 FPC 与实际 NEO Dock／转接板兼容。

480×272×24-bit 完整帧缓存约 3.13 Mbit，超过片上 BSRAM。当前频谱采用坐标绘图，莉萨如使用轨迹／扫描行缓存；当前曲库／姿态完整版共使用 113/118 个 BSRAM，历史全宽舞台为 95/118、旧双输出基线为 86/118。独立全屏莉萨如演示的双缓冲方案仅用于历史显示测试。

### 3.6 时钟与供电

音频参考当前使用 NEO Dock 31005 上 MS5351M 的 CLK2，经 `USR_CLK_IN` 进入 V13。CLK2 对 GND 已用示波器实测为 12.288 MHz：

- `12.288 MHz / 8 = 1.536 MHz` PT8211 位时钟；
- `12.288 MHz / 4 = 3.072 MHz` 标准 I²S 位时钟；
- `12.288 MHz / 256 = 48 kHz` 音频采样节拍；
- 当前矩阵、ADC、声部计算、音效及 FFT 都使用 12.288 MHz，无需 100 MHz 计算 PLL；
- LCD DCLK 由 50 MHz 六分频得到 8.333 MHz；
- 音频到显示域用握手同步；三枚效果键由 50 MHz 域处理并同步到音频域。

CLK2 的 FPGA 稳定接收和完整断电自动恢复已在 MINIMAL 实物验证中完成；当前双板主链继续使用同一时钟来源。

整机首版使用 12 V DC5521 供电，不把单 USB 或锂电池供电纳入验收。适配器、电源极性和底板版本必须在上电前复核。

## 4. 定音与演奏规则

### 4.1 标准调弦

采用十二平均律与 `A4 = 440 Hz`：

| 弦号 | 物理含义 | 空弦音 | 频率 |
| --- | --- | --- | ---: |
| 第 1 弦 | 最高音细弦 | E4 | 329.63 Hz |
| 第 2 弦 |  | B3 | 246.94 Hz |
| 第 3 弦 |  | G3 | 196.00 Hz |
| 第 4 弦 | 最低音弦 | D3 | 146.83 Hz |

每弦支持空弦和第 1～8 品，因此选音表覆盖 4×9 个状态。频率控制字由离线工具按实际采样率和相位累加器位宽生成。

### 4.2 状态机规则

1. 拨弦时读取该弦当前最高按下品位；没有按品时触发空弦。
2. 每根弦固定绑定一个声部，不需要跨弦抢占。
3. 同一弦再次拨动时重新激励该声部并重启包络。
4. 声部发声期间，只要仍有品位按下，最高品位变化就触发滑音，不重启起音包络。
5. 释放最高品后若较低品仍按住，则滑向新的最高品。
6. 释放最后一个按弦触点时，保持释放前音高并产生 `note_off`，不自动跳回空弦；无效果时进入阻尼，延音开启时继续自然衰减，关闭延音后恢复阻尼。
7. 无拨弦击弦与勾弦仅作为扩展功能。

滑音时间为集中配置参数；必须对相位增量进行逐样本平滑，不能直接跳变造成音高台阶或爆音。

## 5. 音频架构

```mermaid
flowchart LR
    A[4×8 按弦矩阵] --> C[演奏事件与每弦状态]
    B[4 路压电前端<br/>MCP3208] --> C
    C --> D[4 个固定声部]
    D --> E[每声部最多 32 路<br/>谐波/模态合成]
    E --> F[包络与力度映射]
    F --> G[固定窄弦位声像<br/>每侧除以二]
    G --> H[三音色效果链<br/>合唱与公共轻混响]
    H --> I[24-bit 内部 PCM]
    I --> J[16-bit 饱和舍入]
    J --> K[PT8211 LSB-justified]
    J --> O[标准 I²S<br/>16 有效位 / 32 位时隙]
    I --> L[左右平均/1024 点 FFT]
    L --> M[64 柱环形频谱]
    M --> N[480×272 RGB LCD<br/>四弦渐变与莉萨如渐暗]
    C --> N
```

### 5.1 四声部与 32 分量

系统包含 4 个并行声部，每声部最多 32 个逻辑谐波／模态通道。当前 `FULL` 已支持单个采样周期内最多 128 个分量的更新与累加；声部内分时计算的音源调度为 233／256 时钟。
开启自动五度和声后，在同一声部的 32 槽位内计算 16 个主音分量和 16 个五度分量，四声部总预算仍为 128。

“逻辑通道”不等于 128 套完全独立 DSP 乘法器。每个声部内部允许使用流水线和分时乘法，在 20.83 μs 的 48 kHz 样本截止时间内完成相位更新、查表、幅度衰减、加权与累加。综合报告必须分别说明逻辑分量数和实际 DSP 实例数。

每个分量至少包含：

- 模态频率比（可包含非整数倍）；
- 相位或由基频相位推导的相位地址；
- 初始幅度；
- 包络观察点或独立衰减系数；
- 音色与力度修正系数；
- 激活标志。

至少一个验收单音必须启用完整 32 个分量。其他音符允许根据音色、可听频段和资源预算关闭无贡献分量，但不得把“最多 32 路”误写成“所有音符始终 32 路”。

### 5.2 力度映射

当前板级使用 `BOARD_FIXED_VELOCITY_ENABLE=0`，按 MCP3208 真实拨弦峰值自动分档；
四弦触发偏差为 CH0～CH3 的 220／100／60／100，沿用已接入的队友力度分界、捕获与回落规则。试听仍使用固定力度编码 2。

当前三音色核心的四级声部幅度增益为 Q8 的 64／128／192／256，即 25%／50%／75%／100%，
先改变声部总幅度；不能据此宣称已经实现随力度改变频谱或衰减时间的四套录音参数。
后续力度音色联动需另行拟合、验证资源和听感。

### 5.3 音色

`USER_BUTTON1` 每按一次循环 **钢琴 → 明亮弦音 → 哇音 → 钢琴**：

- **钢琴**：8 个主要实测模态包络加 FPGA 实时噪声激励、滤波和三个阻尼谐振器生成的短击弦起音；当前主体包络双速推进，无效果自然时长约1.37秒。
- **明亮弦音**：32 个整数谐波及各分量衰减，保留明亮的拨弦质感。
- **哇音**：参考无混响 C4/E4/G4 录音，三个音区各 32 个主要模态，包含半整数倍频率比和动态包络。V4 在前 42.67 ms 后半速推进哇音包络，无效果自然尾音约 1.16 秒，延音约 4.50 秒；DDS 相位仍以原采样率推进。

哇音自然包络不由按品时长决定；松品保留原音并继续衰减，快速重拨才重新起音。
第三音色的 `rock_select`、`mem/rock_*` 名字保留以兼容原接口，实际音色已替换为哇音，
不再采用旧重金属 WAV、tanh 过驱动或旧版谐波滚降。

切换时使用参数平滑或短时交叉渐变。音符主体由 FPGA 实时模态／谐波合成，
当前钢琴击弦由 FPGA 实时随机激励和阻尼滤波器生成，已移除短起音 PCM ROM；演奏时不需要原始 WAV 或软件音源。主体和 wah 只保留模态参数及稀疏幅度包络，见 [实现与赛题依据](docs/PROCEDURAL_PIANO_HAMMER.md)。

### 5.4 包络与音效

包络采用适合拨弦乐器的快速 Attack、自然 Decay 和可控 Release；Sustain 可保留为配置项，但默认不维持恒定电平。

| 按键 | 功能 | 当前行为 |
| --- | --- | --- |
| `USER_BUTTON1` / AA13 | 循环三音色 | 钢琴 → 明亮弦音 → 哇音；约 5.33 ms 交叉渐变 |
| `USER_BUTTON2` / AB13 短按松手 | 合唱开／关 | 15～23 ms 左右反向调制延迟，干湿渐变 |
| `USER_BUTTON2` / AB13 长按约 1 秒 | 自动五度和声开／关 | 下一次拨弦锁存；松手不额外切换合唱 |
| `USER_BUTTON3` / Y12 | 循环三种空间状态 | 无效果 → 延音 → 轻量混响；与合唱／和声独立 |

上电默认钢琴、合唱／和声关闭、无效果；没有外部复位键。
延音放慢自然包络，松品仍滑回空弦并续音；轻混响使用公共片上 BSRAM 反馈延迟，
第三键的延音与轻混响互斥，合唱可叠加其中任一状态。
LED0 熄灭／常亮／2 Hz 闪烁对应钢琴／明亮弦音／哇音；LED1 表示合唱，LED2/3 表示延音／混响。
第三键无效果且和声启用时，LED2/3 同时亮。

首版不做卷积混响，不依赖 DDR3。反馈增益必须具有限幅和稳定性证明，旁路切换需淡入淡出。

### 5.5 定点与输出格式

- 声部内部建议使用至少 24-bit 有符号定点；
- 谐波累加器和四声部混音器必须增加保护位；
- 任意满幅组合不得发生二进制回绕，只允许饱和；
- 最终内部 PCM 保持 24-bit；
- 输出前执行饱和、舍入和可选 TPDF 抖动，转换为 16-bit；
- PT8211 输出为 48 kHz、双声道、16-bit、MSB-first、LSB-justified；当前三音色使用固定窄弦位声像，每个音在左右两侧均可听到；
- 同一对最终 PCM16 同时送给标准 I²S 发送器：48 kHz、32 位时隙、16 位有效数据、低 16 位补零，WS 低为左、高为右，切换后延迟一位发送 MSB。独立处理时序，原 PT8211 发送器保持原协议。

## 6. 实时频谱

频谱输入取最终效果后的内部 PCM，不回采模拟输出。当前整机配置为：

- 1024 点定点 FFT；
- Hann 窗；
- 约 30 FPS 刷新；
- 64 根环形近似对数频谱柱，12 点方向低频、顺时针升高；
- 具备峰值缓降；
- LCD 使用逐像素绘制，不申请完整帧缓存。

FFT 可以使用 Gowin 硬件 IP，但必须置于 wrapper 中，并为 ModelSim 提供厂商模型或行为级替代。显示开启后不得造成音频掉样或时序失败。

## 7. 软件与工具链

| 工具 | 固定版本／用途 |
| --- | --- |
| 操作系统 | Windows 64-bit |
| 综合与布局布线 | Gowin EDA Commercial `V1.9.12.03 (64-bit)` |
| 烧录 | 上述 Gowin 安装附带的 Programmer |
| RTL 仿真 | ModelSim SE-64 10.6d，本机完整回归脚本见 `sim/run_main_regression.ps1` |
| 可综合 HDL | Verilog-2001 |
| 测试平台 | SystemVerilog |
| 离线查表 | Python 3 脚本，版本在实现时锁定 |

允许使用 Gowin PLL、异步 FIFO、B-SRAM 和 FFT 等基础硬件 IP。所有 IP 必须通过独立 wrapper 隔离，不允许核心演奏逻辑依赖软核程序或整套黑盒音频算法。

## 8. 当前工程结构

以下为当前源码与主要入口；独立实物测试工程和历史文档继续保留。

```text
xinxian-fpga-guitar/
├─ README.md
├─ docs/
│  ├─ README_答辩版.md
│  ├─ CONFIGURATION_PLAN.md
│  ├─ WAH_REFERENCE_TIMBRE.md
│  ├─ PROCEDURAL_PIANO_HAMMER.md
│  ├─ STANDARD_I2S_VALIDATION.md
│  ├─ NEXT_VERSION_PERFORMANCE_TOUCH_GAME_PLAN.md
│  ├─ FULL_PIANO_EFFECTS.md
│  ├─ FULL_EFFECTS_V2.md
│  └─ evidence/
├─ firmware/
│  └─ bl616_ble_uart_bridge/     # BL616 BLE↔UART 二级固件、发布镜像与安全烧录模板
├─ mobile/
│  └─ android/                   # Android BLE 客户端与 XG3 曲谱上传界面
├─ gowin/
│  ├─ neo_guitar_touch_game/      # 当前入口：触控＋全宽四轨游戏＋完整演奏模式
│  ├─ neo_guitar_i2s/             # 已验收的双音频输出／环形显示基线
│  ├─ neo_guitar_procedural/      # 实时击弦模型独立工程
│  ├─ neo_guitar_radial/          # 环形显示与渐暗阶段工程
│  ├─ neo_guitar_lissajous/       # 早期居中莉萨如
│  ├─ neo_guitar_audio_full/      # 早期三键、三音色音频工程
│  ├─ build_full.tcl             # FFT/LCD FULL 逻辑构建，自动引脚
│  ├─ xinxian_mega60k/           # 旧固定八模态钢琴主工程
│  ├─ neo_full_chain_audio_test/ # 双 PCB 全链路实物基线
│  ├─ neo_four_string_matrix_audio_test/
│  └─ test3/                    # MCP3208 单板实物测试
├─ constraints/
│  ├─ neo_guitar_audio_full.cst
│  ├─ neo_guitar_audio_full.sdc
│  ├─ neo_guitar_i2s.cst
│  ├─ neo_guitar_i2s.sdc
│  ├─ neo_guitar_touch_game.cst
│  ├─ neo_guitar_touch_game.sdc
│  └─ full_timing.sdc
├─ rtl/
│  ├─ top/
│  ├─ input/
│  ├─ game/
│  ├─ control/
│  ├─ synth/
│  ├─ effects/
│  ├─ audio_io/
│  ├─ display/
│  ├─ common/
│  └─ config/                  # 公共配置及生成的音色系数
├─ ip/
│  ├─ gowin/
│  └─ wrappers/
├─ mem/
│  ├─ note_phase_inc.mem
│  ├─ sine_lut.mem
│  ├─ piano_*.mem              # 钢琴幅度包络、模态和明亮弦音参数；无击弦 PCM
│  ├─ rock_*.mem               # 当前哇音包络、模态、增益与相位
│  └─ hann1024_q15.mem
├─ sim/
│  ├─ tb/
│  ├─ models/
│  ├─ reference/
│  └─ run_main_regression.ps1
├─ tools/                     # 离线分析、ROM 生成、试听与门级核对
└─ build/                     # 本地生成产物，Git 忽略
```

`build/`、Gowin 中间产物、ModelSim 工作库和波形文件不得提交到版本库。

## 9. 配置策略

公共开关、时钟、输入阈值和滑音参数位于 `rtl/config/guitar_config.vh`；音色表位于 `mem/`，
部分系数函数位于 `rtl/config/piano_bright_coeffs.vh` 和 `rock_coeffs.vh`。
板级电平／引脚和时序分别在 CST／SDC 中。
哇音半速包络、声部分时调度等固定行为还位于 `piano_voice_core.v`，修改时需同步生成工具和数字验收。
修改编译配置后重新综合下载，首版不要求 UART 在线调参。

### 9.1 构建档位

| 档位 | 用途 | 主要功能 |
| --- | --- | --- |
| `MINIMAL` | 首次上板与音频闭环 | 单声部、少量谐波、无 FFT、无复杂音效、PT8211 输出 |
| `neo_guitar_touch_game` | 当前整机入口，IMU／Flash 启动已获用户实物确认 | GT911、全宽四轨多曲目、UART 可写曲库、真实四档力度、空闲姿态切音色；保留完整三音色／音效、双输出和 FFT 图形 |
| `neo_guitar_i2s` | 已验收的双输出基线 | 四声部、最多 128 分量、实时击弦、全部三音色／音效、PT8211＋标准 I²S、1024 点 FFT、四弦渐变和环形显示 |
| 音频 `FULL` | 历史音频阶段工程 | 三音色、合唱／延音／轻混响／五度和声；固定引脚，无 LCD，新增 I²S 默认关闭 |
| FFT/LCD `FULL` | 历史完整逻辑构建 | 相同音频核心加 FFT 和 RGB 时序；自动引脚，仅逻辑构建 |
| `neo_lcd_lissajous` | 480×272 动态显示与屏幕验收 | 固定 J5 引脚，8.333 MHz，彩虹莉萨如/拖尾/暂停；独立显示，无音频 |
| `DEBUG` | 故障定位 | 在选定档位上增加调试 GPIO、计数器和 GAO 观测点 |

当前正式入口复用公共 RTL，通过顶层参数和板级包装选择功能。
早期独立测试工程中保留的平铺源码用于重现其已验证行为。

### 9.2 关键配置项

| 参数组 | 需要集中管理的内容 |
| --- | --- |
| 系统 | 构建档位、时钟频率、复位延时、功能开关 |
| 音频 | 48 kHz、内部位宽、输出位宽、饱和与舍入方式 |
| 乐器 | 4 声部、每声部最多 32 分量、4×9 音高表 |
| 输入 | 矩阵扫描率、去抖、ADC SPI 时钟、四弦基线和力度阈值 |
| 演奏 | 滑音时间、再触发死区、最后品位释放规则 |
| 音色 | 三音色的模态频率比、增益、相位、动态包络、衰减及 4 级幅度映射 |
| 音效 | 合唱延迟／调制、Release 延长、多抽头延迟和反馈增益 |
| FFT | 1024 点、Hann 窗、32／64 柱、刷新率和峰值下降速度 |
| LCD | 分辨率、porch、同步极性、像素时钟、颜色与布局 |

详细迁移步骤见 [配置修改计划](docs/CONFIGURATION_PLAN.md)。

## 10. 开发阶段与里程碑

| 日期 | 阶段 | 退出条件 |
| --- | --- | --- |
| 2026-09-04 | 需求冻结 | README、接口、风险和配置计划评审完成 |
| 2026-09-05～09-21 | 仿真与硬件准备 | 单元 testbench、查表、BOM、原理图和引脚冲突检查完成 |
| 2026-09-22 | 首次上板 | `MINIMAL` 输出稳定测试音，板载 DAC 无持续爆音 |
| 2026-09-28 | ROW0 选音闭环 | 空弦及第1～8品控制 PT8211 实际音高；同组多键最高品优先通过 |
| 2026-09-23～10-04 | 基础闭环 | 4×8 输入、拨弦触发、四声部、音高和基础包络已通过；力度实物标定延后 |
| 2026-10-05 | 三音色音频阶段 | 三音色、三键控制与哇音 V4 尾音已上板；80 项回归和门级 DAC 核对通过 |
| 2026-10-12 | 环形显示与演奏更新 | 四弦渐变、环形频谱和松品续音获得用户实物认可，加入曲线渐暗 |
| 2026-10-13 | 当前整机基线 | 实时滤波／模态击弦替代预录 PCM，增加标准 I²S；数字验证及用户下板验收通过 |
| 2026-10-05～10-18 | `FULL` 功能 | 四级力度实物标定仍待完成；FFT/LCD 已整合，继续保持三音色和 128 分量实时预算 |
| 2026-10-19～10-25 | 整机优化 | 延迟、串扰、资源、WNS、长时间演奏和供电测试通过 |
| 2026-10-26～11-01 | 发布与答辩 | 回归、证据包、演示脚本、许可证和源码发布包完成 |

团队人数为 3 人，但本文不沿用旧 A/B/C 分工。实施启动时再为每个模块指定唯一负责人和不同的验证人。

## 11. 验收标准

### 11.1 功能验收

| 项目 | 通过门槛 | 主要证据 |
| --- | --- | --- |
| 4×8 琴颈 | 32 个位置映射正确；多键时最高品优先；无不可接受鬼键 | 矩阵测试日志、GAO 波形、演示视频 |
| 标准调弦 | 4×9 状态音高正确，建议频率误差 <0.5% | 仿真计数、频率计或频谱截图 |
| 四声部 | 四根弦同时发声且释放互不影响 | 四音和弦频谱、PCM 波形 |
| 四级力度 | 四弦均能稳定区分 4 级，映射方向正确 | 标定数据、重复拨弦统计、频谱对比 |
| 32 分量 | 至少一个单音启用 32 路，样本截止前完成计算 | 配置、调度计数、仿真日志、频谱 |
| 滑音 | 频率连续过渡，不重新触发 Attack，无明显阶梯或爆音 | phase increment 波形、录音 |
| 三种音色 | 钢琴、明亮弦音、哇音可循环切换，音高稳定、切换无明显爆音 | 同力度对照录音、频谱与参数表 |
| 音效 | 合唱独立开关，第三键循环无效果／延音／轻混响，不自激、不掉样 | 长时间波形、录音、溢出计数 |
| 自动和声 | USER_BUTTON2 长按开／关，下一次拨弦加入五度；不额外切换合唱，不超 128 分量预算 | 按键日志、频谱、实时调度计数 |
| PT8211 | 连续发送至少 10,000 帧无格式错误 | ModelSim 检查器、逻辑分析仪 |
| 标准 I²S | 48 kHz、32 位时隙、16 位有效数据、一位 MSB 延迟；与 PT8211 样本一致 | 独立协议解码、完整链路及网表对照、现场波形 |
| 频谱显示 | 1024 点 FFT、64 根环形谱柱、约 30 FPS 分析刷新，音频不断流 | LCD 视频、帧率计数、掉样计数 |

### 11.2 延迟验收

采用双层门槛：

- **内部数字链路 ≤5 ms**：从压电包络越过 FPGA 触发阈值，到首个有效 PCM 样本进入 PT8211 发送队列；
- **整机链路 ≤10 ms**：从物理拨弦形成有效传感信号，到耳机／扬声器模拟输出出现有效波形。

建议用 FPGA 调试 GPIO 标记 ADC 触发和样本提交，并用示波器同时观测压电前端、调试 GPIO、LRCK 和模拟音频输出。至少重复 30 次，报告最大值，不只报告平均值。

### 11.3 资源及时序验收

`FULL` 构建必须满足：

以下资源余量是整机优化目标。当前 ID70 完整版已满足器件容量、已测实时调度及 setup/hold 要求，
CLS 为 28295／29952（94.47%），BSRAM 为 113／118，DSP 为 115.5／118；系统／音频 Fmax 为 50.072／13.687 MHz，实际运行仍为 50／12.288 MHz，仍未达到全部资源使用率与余量目标。
该项仍需资源优化，不能仅凭已成功布局布线宣称整机全部验收完成。

- 所有目标时钟域 WNS ≥ 0，无未处理时序违例；
- LUT、DSP、B-SRAM 各自目标使用率不超过 85%；
- 至少保留 10% LUT 与 B-SRAM 修正余量；
- 每个 48 kHz 样本的最坏计算调度小于 20.83 μs；
- FIFO 无 underflow／overflow，音频无掉样；
- 数值累加无回绕，反馈音效不自激；
- 若某项超过 85%，先优化分时复用、FFT 柱数或缓存结构，不能直接删除最终功能。

## 12. 最终演示流程

1. 展示系统上电、自检和默认静音释放；
2. 依次演奏四根空弦，核对 D3、G3、B3、E4；
3. 展示各弦逐品选音和同弦多品最高品优先；
4. 演奏四音和弦与快速扫弦，证明四声部独立；
5. 每根弦展示从轻到重的 4 级力度；
6. 在持续音中跨品，展示不重启包络的连续滑音；
7. 用 `USER_BUTTON1` 循环对比钢琴、明亮弦音和哇音；
8. 用 `USER_BUTTON2` 短按展示合唱、长按展示自动五度和声；用 `USER_BUTTON3` 循环展示无效果／延音／轻混响；
9. 展示 1024 点 FFT 频谱随演奏变化；
10. 展示单音 32 分量的配置、频谱和调度证据；
11. 用示波器展示内部 ≤5 ms、整机 ≤10 ms；
12. 连续演奏，确认无卡音、错误串音、明显爆音或系统复位。
13. 展示 J9 标准 I²S 的 3.072 MHz BCLK、48 kHz WS 和一位 MSB 延迟；外接 DAC 联调完成后可演示两路同时发声。

第 5 项力度分档及第 11 项整机定量延迟仍需实物标定和测量，不由当前功能验收替代。

面向评委的精简说明见 [答辩版 README](docs/README_答辩版.md)。

## 13. 风险与降级原则

| 风险 | 预防与处置 |
| --- | --- |
| TPU 回弹造成重复触发 | 峰值保持、迟滞、死区、机械阻尼和重复测试共同调节 |
| 四桥码机械串扰 | 独立弯曲梁、隔离材料、短时峰值对比；不得用过长死区吞掉扫弦 |
| RGB 屏不兼容 | 采购前取得数据手册和 FPC 定义；未知型号不得写入固定约束 |
| 128 分量资源过高 | 逻辑通道保持 128，增加声部内分时复用并优化系数存储 |
| FFT 挤占资源 | 当前 64 柱环形显示已实现；继续优化调度和缓存，保持 1024 点分析及音频实时性 |
| 音效反馈自激 | 限制反馈系数、加入饱和和静音保护，进行长时间仿真 |
| 时钟域导致掉样 | 异步 FIFO、Gray 指针、CDC 评审和溢出计数器 |
| 供电不足或噪声 | 使用 12 V/≥3 A 供电，模拟与数字布线分区，整机满载测试 |
| 压电高压尖峰损坏器件 | 先限流与双向钳位，再进入运放和 ADC；禁止直接接 FPGA |

任何降级只能用于 `MINIMAL` 或排错构建。最终 `FULL` 的需求变更必须经过书面评审并同步更新 README、配置和验收证据。

## 14. 开源与第三方来源

项目计划使用 Apache License 2.0 发布。正式开源前需新增 `LICENSE` 和 `NOTICE`，并在 `NOTICE` 中列明：

- Sipeed Tang Mega 60K 官方示例及其许可证；
- Gowin 生成的 IP、仿真库及其再分发限制；
- MCP3208、PT8211 和 LCD 数据手册来源；
- 任何复制或修改的第三方 HDL、脚本、图标和字体。

厂商 IP 与仿真库不应在未确认许可时直接打包发布；开源仓库可提供生成步骤和本地路径说明。

## 15. 参考资料

- [Sipeed Tang Mega 60K 官方硬件页](https://wiki.sipeed.com/hardware/en/tang/tang-mega-60k/mega-60k.html)
- [Sipeed Tang Mega 60K 官方示例仓库](https://github.com/sipeed/TangMega-60K-example)
- [Sipeed Tang Mega 138K 官方示例仓库（NEO Dock LCD 示例使用 RGB666 命名，供接口复核）](https://github.com/sipeed/TangMega-138K-example)
- [Gowin／Sipeed 器件选择说明](https://wiki.sipeed.com/hardware/en/tang/common-doc/get_started/install-the-ide.html)
- [MCP3208 官方产品页](https://www.microchip.com/en-us/product/MCP3208)
- [PT8211 官方产品页](https://www.princeton.com.tw/%E7%94%A2%E5%93%81%E5%B0%88%E5%8D%80/Multi-Media-Audio/Digital-to-Analog-Converter/DTAC-PT8211)
- [Gowin Arora V Clock User Guide 文档入口](https://www.gowinsemi.com/en/document/main/database/2913/)

---

需求基线日期：2026-09-04

当前进度更新：2026-10-23，`neo_guitar_touch_game` 为整机入口，已包含完整主旋律、UART 可写曲库、真实四档力度及 ID70 姿态兼容；旧／新资源与时序同时保留

状态：用户已确认完整固件的重力传感器正常工作、外部 Flash 烧录与断电重启可用；串扰／声压／延迟／长期稳定性定量测试和蓝牙实物闭环仍需补充
