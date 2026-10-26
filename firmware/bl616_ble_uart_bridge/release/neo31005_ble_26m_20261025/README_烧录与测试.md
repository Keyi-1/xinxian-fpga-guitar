# NEO Dock 31005：26MHz BLE扫描修复候选

本包已经实际编译和检查镜像，尚未在实物上验证广播/连接/导谱。

## 本次只选这个文件

文件：`xinxian_ble_uart_neo31005_26m_0x40000.bin`

- 芯片：BL616/618。
- 工具：你们已安装的BouffaloLabDevCube 1.9.0，Single Download Options。
- 写入地址：**0x40000**。
- 文件大小：281968字节。
- SHA256：`f156ce09d8487525c76f9a18dee59b0352ca71574fe7d08a57415ecc78df55ac`。
- 擦除：仅所写区域/分段擦除，禁止整片擦除。
- 不要选择旧的`xinxian_ble_uart_bl616_secondary_0x40000.bin`。
- 不要选择SDK的whole、Boot2、partition或efusedata。

1. 先断开12V及USB，按住UPDATE，再连接DEBUG-USB2和12V；若主板尚未开机，保持UPDATE按住并长按PWR约2秒开机。下载端口出现后松开UPDATE。可以同时接12V和USB，不应假定单根USB一定足够供电。
2. Single Download中选上方新bin，地址填0x40000；下载并确认日志成功。烧录后可用工具的Flash Read核对0x40000起281968字节，SHA应与上方一致。
3. **拔掉调试USB并完全断电**，再用12V独立供电；这次不要按UPDATE。
4. 手机打开项目App或nRF Connect，开启蓝牙并授予扫描所需权限，重新扫描。
5. 目标广播名仍为 **XINXIAN-BL616**，没有改名。如果名称未显示，也可按下方NUS服务UUID识别。

Service：`6E400001-B5A3-F393-E0A9-E50E24DCCA9E`。
RX写入：`6E400002-B5A3-F393-E0A9-E50E24DCCA9E`。
TX订阅：`6E400003-B5A3-F393-E0A9-E50E24DCCA9E`。

先确认能扫描、连接和订阅TX，再用项目App测试已有XG3请求与FPGA ACK；原始数据不是文本串口终端协议。

## 官方一级固件只作恢复备用

你们已确认当前版本支持二级启动，因此**正常测试本次新版时无需写0x0**。
`recovery/bl616_fpga_partner_NeoDock.bin` 是官方2025030317版本的下载器/一级固件，
本身不会广播BLE；仅在确需恢复一级固件时使用，地址0x0，同样不能整片擦除。

官方文件SHA256：`4a7bae28bae18ae713a95177e1758954214253e5cdbb84d8436cba8bc1d085d7`。
来源：https://api.dl.sipeed.com/TANG/Debugger/onboard/BL616/2025030317/bl616_fpga_partner_NeoDock.bin

## 如果仍扫描不到

保留下载日志、读回结果及当前SW2第5/6位的实际位置；核对是否真的正常上电、是否仍在下载模式。
先用nRF Connect取消名称/服务过滤进行扫描；若仍完全无广播，需要区分一级未跳转、
RF供电/匹配/天线链路与运行异常。本包不能凭静态检查证明实物射频链路正常。
本二级程序没有实现USB-JTAG/USB串口，BLE运行时不能要求这两个功能同时存在。

## 这次改了什么

将通用BSP的40MHz晶振配置改为本板26MHz，显式设置镜像头26MHz，并停止把CW2015的
GPIO21/22复用成UART0；补查GATT服务注册及BLE主机初始化的错误。
FPGA UART仍为GPIO28 TX / GPIO27 RX、115200/8N1；NUS与Android App一致。
只交付固件，没有在本机执行任何烧录或物理COM访问。
