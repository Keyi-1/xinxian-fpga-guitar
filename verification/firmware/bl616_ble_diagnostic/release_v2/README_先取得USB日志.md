# 诊断v2：先USB，后手动启动BLE

用户确认：UPDATE模式能出现下载端口，烧录v1后正常启动既无新USB设备也无可见广播。
这说明ROM下载通路可用，但尚未确认二级程序是否启动或卡在哪个初始化函数。
v1在启动后立即初始化RF，可能在USB日志可读前卡住。v2先只提供USB日志，收到
`ble_start`命令后才进入RF和BLE初始化，每次调用前输出阶段并留出USB发送时间。

## 这次按顺序操作

1. 完全断开USB和12V，按住UPDATE，再接DEBUG-USB2和12V；若主板未开机，保持
   UPDATE按住并长按PWR约2秒开机。下载端口出现后松开UPDATE。
2. DevCube Single Download选择本包 **xinxian_ble_diag_v2_manual_start_0x40000.bin**，
   地址 **0x40000**，仅擦除写入区域。保留0x0一级固件。
3. 下载成功后拔掉USB和12V，完全断电。SW2第5 OFF、第6 ON保持。
4. 不按UPDATE，用12V正常开机（需要时长按PWR约2秒），等5秒，再保持供电接上DEBUG-USB2。
5. **先看设备管理器，此时还没有蓝牙广播是预期行为。**
   若出现新的USB Serial Device/USB Console COM口，继续第6步；如果仍完全没有新设备，
   则尚未走到可观测的USB运行状态，应查二级跳转/BSP/USB初始化，不能归罪于BLE空口。
6. 关闭DevCube对端口的占用，进入本包目录，在PowerShell运行：

   `powershell -ExecutionPolicy Bypass -File .\read_diagnostic.ps1 -Port COM12`

   COM12换为实际新增端口。应看到重复的 **XINXIAN-DIAG v2 ... stage=1 ...**。
7. Ctrl+C停止读取，再运行：

   `powershell -ExecutionPolicy Bypass -File .\read_diagnostic.ps1 -Port COM12 -StartBle`

   这个参数会发送一次ble_start，不烧录。用其他串口终端也可直接发送ble_start加回车。
8. 把日志从stage=1开始的数行完整发回，尤其最后停住的一行；再用nRF Connect扫描
   **XINXIAN-DIAG**。当前项目App旧版可能隐藏无缓存名称且无NUS服务的设备，应优先用nRF Connect。

## 阶段

- 1：已进入应用任务，USB运行，等待手动命令；rf/host/ready/adv=-999属正常。
- 2：即将调用rfparam_init。停在这里或rf为非0可缩小到RF初始化。
- 3：RF已返回，进入控制器初始化。
- 4：控制器已返回，进入HCI驱动初始化。
- 5：进入主机bt_enable；等待ready。
- -2/-5/-6/-7：对应RF/主机同步/异步ready/首次广播开启错误。
- 7且rf=host=ready=adv=0：初始化和广播命令返回成功，仍需手机确认真实广播。

如果v2仍无USB，先不要反复改射频匹配元件或手机App来推断固件已运行。下载成功只证明
Flash写入操作通过，不证明一级跳转或二级执行通过；必要时保存0x40000起的Flash读回文件比对。

该镜像不初始化FPGA UART、不提供NUS、不支持导谱。测试后可写回原26MHz桥接候选。
已实际编译、镜像头及CRC校验；尚未实物验证USB枚举和RF。
