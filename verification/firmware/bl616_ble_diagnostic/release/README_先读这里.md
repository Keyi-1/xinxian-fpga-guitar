# XINXIAN-DIAG：仅诊断启动和蓝牙广播

这是独立诊断镜像，不是曲谱导入固件。不会初始化FPGA UART，不提供NUS服务，
因此项目App可以显示它，但连接后XG3握手失败是预期现象。不要用它上传曲谱。

## 测试顺序

进入下载模式时可以同时使用12V和DEBUG-USB2，不能假定单根USB一定足够供电。
先断开12V及USB，按住UPDATE，再连接DEBUG-USB2和12V；若主板尚未开机，
保持UPDATE按住并长按PWR约2秒开机。下载端口出现后松开UPDATE，再执行下面的烧录。
UPDATE是上电采样用的启动选择，不是整板电源键；已正常运行后单按它不等于重新进入下载模式。

1. 用现有DevCube Single Download烧录 `xinxian_ble_diag_usb_neo31005_26m_0x40000.bin`，
   地址仍为0x40000，仅擦除写入区域。当前一级版本已满足要求，不改0x0。
2. 拔掉调试USB，整板完全断电。SW2按壳体ON标志确认：第5位OFF、第6位ON，
   原理图对应EN=1、MODE=0（Game）。其他拨码保持。
3. 接12V正常开机，不按UPDATE，等待5秒。手机用nRF Connect取消过滤扫描，
   看是否有 **XINXIAN-DIAG**。也可用项目App看名称，但不进行导谱。
4. 保持12V供电，再把DEBUG-USB2用数据线连到电脑；不要复位或断电。
   观察设备管理器是否新增CDC串口，名称可能是Bouffalo Lab USB Console。
   先独立供电再插数据USB，是为了避免启动时一级固件因检测到USB主机而停留在下载器模式。
5. 关闭占用该端口的DevCube，用串口终端以115200/8N1打开新增的COM口，或运行
   `powershell -ExecutionPolicy Bypass -File .\read_diagnostic.ps1 -Port COM12`，
   将COM12换成实际新端口。脚本只读取日志，不发送数据、不烧录；Ctrl+C退出。
6. 复制以XINXIAN-DIAG开头的整行日志，用于下一步定位。

## 日志解释

每2秒重复输出，较晚打开串口也能看到当前状态。-999表示该调用尚未得到结果。

- `xtal=26000000`：程序读取的BSP晶振频率。只是配置状态，不是仪器实测频率。
- `stage=2`：进入RF初始化；`stage=-2`及`rf=错误码`：RF初始化失败。
- `stage=3`：进入控制器初始化，若一直停在这里，控制器初始化未返回。
- `stage=4`：进入HCI驱动初始化。
- `stage=5`：已进入BLE主机初始化，等待异步ready；host=0表示同步调用已接受。
- `stage=-5`：BLE主机初始化同步报错。
- `stage=-6`：异步ready回调报错。
- `stage=-7`：首次开启广播失败，查看adv错误码。
- `stage=7 rf=0 host=0 ready=0 adv=0`：初始化及广播命令返回成功。
  这不能单独证明空口有信号；若手机仍看不到，应继续查RF电源、L9、天线与实物时钟。
- connected/disconnected计数可辅助验证nRF Connect连接及断开，reason记录断线原因。

如果既无DIAG广播又没有诊断CDC串口，只能说明尚未观测到诊断程序正常工作；
不能仅据此断言一级未跳转，也可能卡在board_init或USB初始化。此时需结合
下载日志/Flash读回、一级版本、拨码、使能电压判断。

## 射频图中的电容

C186/C187为NC预留匹配元件，按图不装正常，不要将其焊盘短接。
L9标的是0Ω，即使位号以L开头也不是要求焊任意电感。
L9缺失/虚焊会中断BL616_ANT到U35的通路；原理图仅说明设计，不代表实物已测导通。

## 恢复与边界

测试后用上一包的 `xinxian_ble_uart_neo31005_26m_0x40000.bin` 同址写回，恢复BLE-UART候选。
此诊断镜像增加USB CDC日志，不提供USB-JTAG，也不是USB-UART复合桥。
已实际编译及镜像CRC检查；尚未在实物验证USB枚举、空口或连接。
