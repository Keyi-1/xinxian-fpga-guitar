# 诊断 v3：跟踪射频初始化，比较晶振电容设置

已确认 v2 的二级应用、USB CDC 和任务能运行；软件晶振配置为26MHz。
用户执行 ble_start 后，RF参数加载日志结束，COM7消失，未收到stage=3。
只拔插USB后出现COM4/5不能证明二级Flash内容丢失；尚不知CPU是否继续运行。
本版不是已验证的修复，不提供NUS串口/导谱，不改FPGA固件，不写eFuse。

## 本次操作

1. 使用原来成功烧录的方法：完全断电，按住UPDATE，再接DEBUG-USB2与12V；
   如果需PWR开机，保持UPDATE按住并长按PWR约2秒。出现下载端口后松开UPDATE。
2. DevCube Single Download仅选择 xinxian_ble_diag_v3_trace_0x40000.bin，
   地址0x40000；仅擦除该写入区域，保留0x0的Partner一级固件。
3. USB和12V完全断电。不按UPDATE，用12V正常开机，SW2第5 OFF、第6 ON。
   等5秒再接DEBUG-USB2。关闭DevCube，记录实际新增的USB串行设备COM号。
4. 解压本包，进入目录运行下面一行，把COM7换成实际USB串行设备号：

   powershell -ExecutionPolicy Bypass -File .\read_diagnostic_v3.ps1 -Port COM7 -BleCommand ble_keepcap

5. 这次先测试 ble_keepcap：保留启动时的晶振电容设置，继续正常RF校准和BLE启动。
   同目录会自动保存 diagnostic_日期时间.txt；把这份文件发回，特别是最后30行。
   如果USB再断开，先保留12V供电，不要立即插拔USB，以免改变故障状态。
6. 用nRF Connect，或安装包内 xinxian_scancheck.apk（名称“弦心吉他·扫描诊断”，
   可与正式App共存）扫描XINXIAN-DIAG；不要仅用旧项目App判断是否存在广播。
   诊断App申请蓝牙/必要定位权限时允许，并按手机系统要求开启定位。

暂时只做上面一次对照，不必自行反复试验。
同一镜像也支持 -BleCommand ble_start，用于下一次完全断电后的标准电容写入路径；
两种路径每次开机只能启动一种。未给BleCommand只读日志，不启动BLE。

## 如何解读

- stage=1：等待手动命令，无广播属正常。
- XINXIAN-TRACE param_load returned：参数加载回调已返回。
- capcode current=A/B requested=C/D keep=1：保留当前值，不应用SDK参数值。
- after capcode update; entering PHY next：电容处理已返回，下一步进入PHY。
- wl_init returned / stage=3：RF初始化已返回。
- stage=7且rf=host=ready=adv=0：各软件初始化及广播命令成功，仍需手机确认。
- 端口断开只是观测结果，不能单凭它断言MCU复位或硬件损坏。

增加了闭源PHY日志和调用前后标记，RF任务栈由4KB加至16KB以减少诊断干扰。
日志回调按固定版本ELF中的(format, va_list)实际ABI接入，并非直接接printf。
保留启动电容仅用于定位：即使能广播，也需后续验证频偏与连接，不能直接作为正式参数。

## 验证范围

固定SDK提交41bf338a57be53919d99f6c6715a96100428c97d，GCC10.2.0。
已编译、检查镜像头/26MHz标识/两个CRC/长度、实际ELF调用诊断钩子；
v2镜像哈希保持。没有连接开发板、烧录或实测广播。
