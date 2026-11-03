# NEO Dock 31005 手机扫描不到BLE：代码检查与修复

2026-10-25。仅修改BL616固件与构建、交付文档；未改Android、FPGA RTL、约束或位流。
没有打开物理COM口、烧录、提交或推送。

用户反馈的镜像是旧 `xinxian_ble_uart_bl616_secondary_0x40000.bin`，烧录地址0x40000，
项目App可发现其他设备，12V独立供电仍无法发现吉他。用户随后确认一级固件已满足
2025030317的二级启动最低版本要求，因此不能把缺少Partner当作已确认原因。

## 已确认的问题

1. **板级时钟错误。** 31005官方原理图第8页Y2为26MHz，旧工程没有覆盖SDK
   `bl616dk/board.c`中的GLB_XTAL_40M。该函数还设置HBN的晶振类型；RF适配器
   `rfparam_init`通过HBN_Get_Xtal_Value取得RF晶振频率，因此系统、UART、RF都受影响。
   这是明确的适配缺陷，但未取得现场运行日志，尚不能证明它是本次故障的唯一原因。
2. **错误的控制台引脚。** SDK board_init调用console_init，将GPIO21/22复用成UART0；
   原理图对应CW2015中断/SDA。新BSP不调用该控制台初始化，也不把日志送入FPGA UART。
   编译器和链接器已移除未引用的console_init，ELF中无该符号。
3. **初始化错误未处理。** 原代码丢弃bt_enable及bt_gatt_service_register的同步返回值。
   现在检查返回值，服务注册失败时不继续广播。由于当前镜像不提供USB日志，printf
   不是可通过原DEBUG-USB2串口查看的诊断接口。

## 未发现导致无法扫描的问题

- 主广播Flags+128位NUS服务UUID共21字节；扫描响应设备名共14字节，各自小于31字节。
- 广播为connectable；名称XINXIAN-BL616。Android端扫描无硬编码MAC过滤，NUS UUID与固件一致。
- TX属性值索引4正确；BLE接收、连接及断线恢复广播的基本接口存在。
- UART映射GPIO28 TX / GPIO27 RX与31005一致；FPGA端V14 RX / U15 TX。

## 修复实现和构建证据

CMake从固定SDK生成neo_board.c，把40MHz改为26MHz、移除console_init调用；生成
neo_fw_header.c显式设置晶振类型5（26MHz）。替换app目标中原board.c和fw_header.c，
不会同时链接两个board_init。保留SDK原有Flash、堆和中断初始化。

固定SDK：`41bf338a57be53919d99f6c6715a96100428c97d`。工具链：官方Xuantie 2.6.1 / GCC10.2.0。
实际ELF反汇编显示system_clock_init在调用GLB_Power_On_XTAL_And_PLL_CLK前设置a0=5，
即GLB_XTAL_26M。镜像PCFG字节104=5，时钟CRC及完整256字节bootheader CRC通过。
SDK combine完整成功；其中生成的Boot2、partition、efusedata均未放入交付烧录列表。

验证入口：`tools/verify_bl616_neo26.py`。结果、ELF、map、反汇编和最终构建日志存于
`build/p5_bluetooth/neo26_20261025/`。检查范围是实际编译产物及静态检查，不能代替RF实测。
新版281968字节，SHA256：
`f156ce09d8487525c76f9a18dee59b0352ca71574fe7d08a57415ecc78df55ac`。
旧版及原manifest、SHA文件保持；旧版SHA256仍是753dc6f9…6001。

## 下一步实物验证

只把新BLE镜像写到0x40000，分段擦除，确认下载成功后完全断电再用12V独立供电，
不要按住UPDATE。通过项目App或nRF Connect扫描XINXIAN-BL616/NUS。
已确认一级版本>=2025030317时不重复刷0x0；官方NeoDock Partner仅作恢复备用。

如果仍不可见，先记录SW2的5/6位置、重新核对USB设备父系版本、下载日志和Flash读回哈希，
再判断一级跳转与RF电源/天线链路；不要通过更改Android UUID或盲目重刷FPGA来掩盖问题。
GPIO17 ModeSel及BL616_EN可能影响一级模式，但本次没有证据确定该实物的拨码状态或
一级闭源固件的具体切换条件，因此不提供未经核实的ON/OFF组合。

若能扫描到但连接或导谱失败，再检查连接对象生命周期、断线残留缓冲及高负载丢包；
本次不将扫描修复扩大宣称为完整BLE-UART长期可靠性验收。

资料：[官方31005原理图](https://dl.sipeed.com/fileList/TANG/Mega_138K_60K/02_Schematic/DOCK/Tang_Mega_NEO_Dock-138K_31005_Schematics.pdf)、
[固定SDK的board.c](https://github.com/bouffalolab/bouffalo_sdk/blob/41bf338a57be53919d99f6c6715a96100428c97d/bsp/board/bl616dk/board.c)、
[固定SDK的RF适配器](https://github.com/bouffalolab/bouffalo_sdk/blob/41bf338a57be53919d99f6c6715a96100428c97d/drivers/rfparam/Src/rfparam_adapter.c)、
[Sipeed二级启动说明](https://wiki.sipeed.com/hardware/zh/tang/common-doc/update_debugger.html)。
# 2026-10-25 诊断 v2 实物反馈与 v3 对照

用户在队友电脑用 COM7 读到 `XINXIAN-DIAG v2 xtal=26000000 stage=1`，
执行 `ble_start` 后进入 stage=2，RF TLV 参数输出至 tcap_cap 数组，然后 COM7
消失，PowerShell ReadExisting 报端口关闭。未收到 stage=3。整板没有明显重启；
只拔插 DEBUG-USB2 后出现原 COM4/COM5。用户只报告项目 App 未找到诊断名，
尚未确认使用不筛选的扫描器。上述现象不证明二级 Flash 丢失，也不足以区分
CPU 停止、复位、USB 时钟改变或只丢失 USB 观测。

SDK rfparam_init 调用 wl_init，参数加载后会执行晶振 capcode 回调，随后进入
PHY 校准。当前 TLV 值 36/36，实际启动值尚未知。PHY 还会写 WIFIPLL 寄存器，
而 BSP 使用 WIFIPLL 系统时钟并派生 USB 时钟；这是待验证方向，不能宣称根因。

诊断 v3 位于 `firmware/bl616_ble_diagnostic/release_v3/`，压缩包
`xinxian_ble_diag_usb_v3_20261025.zip`。`ble_keepcap` 保留启动时电容设置，
`ble_start` 保持原设置路径；两者每次开机只能执行一种。新增参数回调返回、
电容调用前后及 PHY 日志，RF 任务栈增至16KB。固定 PHY 的 wl_logger 反汇编
确认回调传递 `(format, va_list)`，因此接 SDK vprintf；不可直接接普通 printf。

v3 BIN SHA256：`669fc1d1fa2fe6b096ef392368716d0c84b714a0b28697e3f25cffe01a4e9678`。
已检查编译、镜像26MHz标识/CRC/长度及最终ELF中rfparam_init调用跟踪钩子，
v2原镜像哈希保持。第一次链接发现 app 静态库的 link_options 未传播至最终 ELF，
已改用 sdk_add_link_options 并通过实际反汇编确认；未发布失败候选。
证据 `build/p5_bluetooth/diagnostic_v3_20261025/`。没有连接或烧录开发板，
尚无 v3 实物结果。保留电容是诊断对照，不能代替后续频偏和连接验证。

