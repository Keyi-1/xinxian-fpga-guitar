# P5：31005 板载 BL616 手机导谱探索

2026-10-19，分支 `experiment/p5-bluetooth-import`，起点 `e0b2ff2a3fb9350e52c76322f03eff95436e2b0c`。本轮实时 `git ls-remote` 已确认远端 master 同为该提交。用户确认底板 31005、首版同时面向 Android/iPhone；天线装配和调试器版本未知，比赛限制辅助 MCU，需以具体赛规判定。

**结论：板载方案有可研究的硬件和公开 SDK 路径，但尚未实现实物 BLE 导入。** 现有调试器不能假定支持 BLE，无证据证明 BLE 与原 JTAG/DEBUG-USB2 可同时运行。当前可安全交付曲谱包、手机原型、可在电脑编译的 C 传输核心和新增 RTL 回放；未生成 BL616 可刷写固件，也未请求用户批准刷写。

## 证据与未决条件

| 核查项 | 已确认 | 尚待确认 |
| --- | --- | --- |
| 31005 射频 | 原理图 Rev1.3（2024-10-15）第8页：U9 BL616C，ANT→L9 0Ω→U35 U.FL；C186/C187 标 NC | U35/L9/射频供电实装、2.4GHz 适配天线、实际射频链路 |
| UART | FPGA U15 TX→BL616 GPIO27 RX；GPIO28 TX→FPGA V14 RX；3.3V，当前115200/8N1 | 二级应用实际引脚复用、波特率及启动期间不污染 UART |
| 时钟 | 同页 Y2 为26MHz；当前 SDK `bl616dk/board.c` 默认40MHz | 26MHz系统/射频/PLL/启动头/校准参数的完整板级适配 |
| BLE SDK | BouffaloSDK `examples/btble/peripheral` 明列支持 BL616/BL618，含 GATT、连接、写和通知示例 | 完整 SDK/无线库/RISC-V 工具链配置、31005板级链接和实测 |
| 二级启动 | 官方说明部分固件支持，应用位置0x40000、调试器0x0；版本门槛2025030317 | 本板现有版本、实际切换条件、Flash分区与恢复可达性 |
| 源码 | 官方链接的 TangCore 有 `TANG_MEGA60K` 目标和GPIO28/27 UART初始化 | 调试器本身的可重建源码及 BLE 共存接口未获证实 |
| 当前设备 | 只读 `pnputil` 枚举未见对应串口/USB Converter | 由用户正常连接 DEBUG-USB2 后识别版本 |

原理图见本地 `build/p3_import/board_evidence/Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf`，已检查完整第8页图。只有缺天线或L9等无源/连接器时，列为补装需求，由用户决定；不能据原理图断言实物已具备。C186/C187 的 NC 是设计状态，不是需要自动补焊的缺件。

原始资料和下载错误均保存在 `build/p5_bluetooth/research/downloads.json`，成功下载项有URL、字节数、SHA256；未把404内容当成固件或校验文件。

主要依据：

- [Sipeed 调试器文档](https://wiki.sipeed.com/hardware/en/tang/common-doc/update_debugger.html)：固件版本识别、Mega NEO UPDATE按钮、DevCube恢复、二级启动版本门槛与地址。这是官方支持入口，不是BLE桥已经存在的证明。
- [60K官方入口](https://wiki.sipeed.com/hardware/zh/tang/tang-mega-60k/mega-60k.html)：底板/核心板资料入口。芯片能力与当前固件功能分别核查。
- [固定 SDK 提交的 BLE 示例](https://github.com/bouffalolab/bouffalo_sdk/tree/41bf338a57be53919d99f6c6715a96100428c97d/examples/btble/peripheral)，[板级时钟/控制台](https://github.com/bouffalolab/bouffalo_sdk/blob/41bf338a57be53919d99f6c6715a96100428c97d/bsp/board/bl616dk/board.c)。通用控制台使用GPIO21/22，这两脚在31005有其他用途，不能照搬整个 `board_init`。
- [官方链接的 TangCore 板级初始化](https://github.com/nand2mario/firmware-bl616/blob/a5a6ea1cf7c81f32c1c3f0f91ea9d913be5ba078/utils/init.cpp)，[构建配置](https://github.com/nand2mario/firmware-bl616/blob/a5a6ea1cf7c81f32c1c3f0f91ea9d913be5ba078/CMakeLists.txt)，[启动分区配置](https://github.com/nand2mario/firmware-bl616/blob/a5a6ea1cf7c81f32c1c3f0f91ea9d913be5ba078/flash.ini)。这是维护者一手源码，包含USB host/SD/控制台，UART并非115200 XG3；不能直接刷入作为本项目BLE桥，也不能将其他板型的启动行为外推为31005实测。

## 职责与最小落地路径

手机负责文件选择、包格式预检、五槽显示、替换确认、停等请求及进度。BL616是**板载微控制器**，负责 BLE 协议栈、连接和有限帧缓冲/转发；FPGA继续执行会话/序号/CRC、事件范围/排序/同轨冲突/密度、空间分配、BSRAM实际读回CRC、原子提交，以及全部显示、判定、实时声音。CRC/哈希是传输完整性检查，不是用户身份认证。

1. 先识别固件版本、确认射频实装和具体赛规。不打开实物COM，不进入烧写模式进行试探。
2. 建立31005二级应用BSP：26MHz和RF参数正确，GPIO28 TX/27 RX=115200/8N1，JTAG脚不抢占，不初始化SD/USB host/CW2015，不向XG3 UART打印控制台日志。用匹配的RISC-V工具链和无线库构建、检查映射和分区，才能交付真正的目标镜像。
3. 在确认的二级启动路径接入本轮 C 核心与GATT。首版模式互斥：保留原有线调试/下载模式；进入BLE应用时独占UART，暂停USB UART转发，不宣称原JTAG仍可同时使用。具体进入/退出控制待确认，本轮不新增FPGA模式引脚或修改RTL。
4. 先准备可审阅镜像、哈希、改变区域、备份与恢复验证方案，再请求一次具体实物变更授权。当前既没有目标镜像，也没有完成本板恢复验证，故不进入该审批步骤。
5. 用户按批准的步骤操作后，分别验收Android/iPhone连接、导入、断开手机后独立演奏，以及返回原下载模式。保持吉他供电，RAM曲库不持久化。

若第2/3步在该调试器/底板上不可行，记录具体障碍并停止板载无线实施，不自行改用额外主控。FPGA没有蓝牙射频；不能靠Verilog直接与手机蓝牙通信。比赛是否允许现有BL616运行BLE栈，仍需赛规原文确认。

## GATT与通道约束（实验接口v1）

| 项目 | 值 |
| --- | --- |
| Service | `7ad10001-6e85-4cba-a0b6-d607ce2d3105` |
| RX | `7ad10002-6e85-4cba-a0b6-d607ce2d3105`；Write with response |
| TX | `7ad10003-6e85-4cba-a0b6-d607ce2d3105`；Notify，先订阅再HELLO |
| 分片 | 默认ATT MTU23；每片至多20字节；32字节XG3帧通常20+12 |
| 节奏 | 一帧停等最终FPGA ACK；GATT写成功不等于FPGA接受，更不等于提交 |
| 数据 | 完全复用P3 XG3和v2事件，无无线直写RAM接口 |

`firmware/p5_bridge/p5_bridge.c`是与SDK无关的C核心，调用必须在单一适配任务中串行执行。编译产物是**电脑测试DLL**，不是BL616固件。SDK适配器尚未实现：需将GATT回调排队到该任务、处理连接/CCCD/发送拥塞、UART FIFO/错误，并在断线时丢弃队列中未发送字节及旧通知；保留完整待通知ACK直至发送API接受，不能丢弃后伪报成功。不支持多中心同时连接。

核心固定boot mode和连接epoch。只接受当前模式/epoch；新连接第一帧须是HELLO/序号0；同连接不能换会话；重连排除刚退役会话；只允许一个未完成请求，允许精确重发交给FPGA去重。合并到达的第二个请求会被拒绝，不能当作流水协议。分片重复/CRC错误使用有界32字节滑窗重新同步，不造ACK，不解释音符。

断线丢弃半帧、待发帧、旧通知和接收缓冲，并隔离6秒，覆盖现有FPGA半帧0.5秒/RECEIVE空闲5秒。适配器还须停止旧UART DMA，清硬件FIFO。隔离期结束**不证明回滚**：COMMIT的PUBLISH握手不会中途放弃，新连接仍须由FPGA HELLO判断是否BUSY。FPGA复位/时钟故障另行恢复，不以固定延时保证提交结束。首版不实现跨连接续传或自动补发旧COMMIT。

手机只在匹配会话/序号/命令、CRC正确且状态0的COMMIT ACK后显示成功。最后确认丢失、断线、应用退出都保留“提交结果待确认”，不发ABORT声称回滚。新会话LIST只有目录元数据，没有内容CRC，不能据数量/时长一致消除不确定性；需用户试听核对。COMMIT已确认而随后LIST失败，报告“已确认提交，目录刷新失败”；确认后目录不匹配则提示可能已复位。

## 手机与单文件曲谱包

`mobile/p5-import`是React Native/Expo原生应用原型，共用同一协议实现。包含扫描/连接、文件选择、五槽查询、替换确认、进度、提交前持久标记、重启后待确认提示、刷新/断开；切后台时主动断开，避免首版依赖后台传输。曲名仅在手机展示，FPGA仍显示USER 1～5。

手机包 `.xgscore` 是有界JSON：包版本1、v2/16-byte/48kHz元数据、标题、事件Base64、CRC32和payload SHA256。最大64KiB、单曲最多1345事件，实际可用空间仍由FPGA裁定；替换须同时容纳旧曲和暂存新曲。五槽与703条内置前缀/2048总库均保持。手机预检不代替FPGA校验。

```powershell
python tools/compile_p2_score.py scores/p2/qing_ge_melody.csv build/p5_bluetooth/example/qing_ge --bpm 60 --timbre 1 --profile game_extended
python tools/p5_score_package.py --bin build/p5_bluetooth/example/qing_ge.bin --metadata build/p5_bluetooth/example/qing_ge.json --title 情歌 --out build/p5_bluetooth/example/qing_ge.xgscore
```

示例来自**当前正式CSV**，212事件/7296000样本/152秒，CRC32=`c3451bbc`。历史P3示例是旧节奏，不用于本轮新包。生成工具拒绝覆盖已有文件；本机示例已准备，无需重复生成。手机编谱、图片识谱、音频导入均不在本轮。

平台依据：[Android BLE权限](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions)、[GATT传输](https://developer.android.com/develop/connectivity/bluetooth/ble/transfer-ble-data)、[系统文件选择](https://developer.android.com/training/data-storage/shared/documents-files)、[Apple CoreBluetooth](https://developer.apple.com/documentation/corebluetooth)、[UIDocumentPicker](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller)。Android12+请求SCAN/CONNECT，较旧版本扫描涉及位置权限；应用不请求后台扫描。iOS使用蓝牙用途说明与系统文件选择。BLE连接从应用内发起。

[BLE库维护者文档](https://dotintent.github.io/react-native-ble-plx/)、[Expo文件选择](https://docs.expo.dev/versions/latest/sdk/document-picker/)、[development build说明](https://docs.expo.dev/develop/development-builds/introduction/)支撑原生实现条件。BLE库需自定义原生构建，Expo Go不足以运行；Windows不能本地编译iOS，iPhone实机还需macOS/Xcode及适当签名。未上传EAS、发布应用或生成可安装APK/IPA。依赖版本按本轮npm/Expo发布包兼容表固定，pnpm锁文件已保存；双平台JS打包和原生编译须分别报告。

## 安全识别、备份与恢复准备

正常连接DEBUG-USB2，在设备管理器中打开USB Converter A/B → 详细信息 → 父级，记录末尾版本序列号；官方示例2025102315仅为文档示例，不是本板版本。无需开串口或发送命令。本机本轮未枚举到设备，版本仍未知。

官方NeoDock 2025030317镜像已仅下载到 `build/p5_bluetooth/research/neo_2025030317.bin`，88672字节，本地SHA256=`4a7bae28bae18ae713a95177e1758954214253e5cdbb84d8436cba8bc1d085d7`。官网对应 `.sha256` 链接返回404，因此没有宣称通过厂商校验，也不把它当成当前板子的完整备份。调试器私有/加密启动和本板eFuse状态不明，不写eFuse，不用普通SDK镜像覆盖0x0。

后续另获硬件授权后，恢复前提是：正确NeoDock镜像/独立校验、本板Flash容量和分区、可达USB ROM恢复通道、可用驱动与DevCube版本。先关闭Programmer/串口工具，保存正常枚举信息；按官方Mega NEO步骤，掉电后按DEBUG-USB2旁UPDATE（原理图SW3）再接入，验证进入ROM CDC恢复模式。这里会改变硬件运行状态，本轮未执行。

在已授权的恢复会话中，使用工具的Flash读取功能按实测容量完整读取两次并比较SHA256，另存分区和安全配置的只读信息；读取受保护时停止，不承诺可绕过保护。研究已下载并仅审阅PyPI `bflb-mcu-tool 1.10.0`源码，发现 `read_flash_thread`/`flash_read`入口，sdist SHA256=`cd09a9b2a5652ad8623ae275a49179c48edd8c90a893851000b08e3b104a46ac`；未安装/运行它，未测试本板备份能力。

恢复采用官方BLDevCube、BL616/618选择与正确NeoDock镜像；具体写入范围、读回比对和恢复原JTAG/UART的步骤应随最终镜像审批包一起冻结。现阶段不提供一键刷写脚本，不执行下载自带的 `make flash`；示例TangCore配置会同时改0x0和0x40000，不能直接沿用。

## 验证与保留边界

- 电脑C核心：32种请求/ACK分片、CRC每字节损坏、噪声/半包超时、连接epoch、USB/BLE互斥、旧会话/ACK隔离、6秒隔离与计时回绕、重复请求和停等。只在内存运行，没有物理UART。
- 手机共享协议：Python黄金帧和正式曲谱跨语言对照、包范围/排序/冲突/密度、五槽/替换、延迟/丢ACK、断线/重连、重复COMMIT、BUSY/NO_SPACE、模拟读回CRC失败、日志写失败及最终ACK不明。这里的FPGA错误注入是PC模型，不是实际射频或网表证明。
- 新增 `tb_p5_bridge_replay`：C核心输出→实际P3 RTL UART→DPB/读回CRC/异步提交→真实RTL ACK→C核心返回。17帧验证重复DATA/COMMIT、BUSY、空间不足和CRC失败旧槽保护；UART分频24为加速，菜单/音频空闲和frame_begin为明确激励边界。未重跑旧整机/综合网表，也未认证无线硬件。
- 全部生产RTL、音源、正式曲谱、ROM、约束、原工程和两个保护文件/index保持；没有新综合/P&R/STA或位流。P4认证/发布副本仍对应 `cfda7ead63703142876e10776a38f86237188aeb4a4d910b02aa0927df611a30`，原余量目标与实物验收限制保持。

证据索引为 `build/p5_bluetooth/verification.json`，新增RTL证据 `build/p5_bluetooth/p5_bridge_rtl_02/`。01仅沙箱启动vlib失败，未跑RTL，失败记录保留。未来复现用 `tools/run_p5_rtl.ps1 -RunName p5_bridge_rtl_03`，不能覆盖已有证据；常规回归无需重复旧P4构建。

本轮结束后等待用户反馈。下一步所需最少信息仍是U35/天线实装、设备管理器版本、赛规相关条文；即使这些补齐，也须先构建/审阅板级镜像和恢复方案，不能跳过授权直接刷写。
