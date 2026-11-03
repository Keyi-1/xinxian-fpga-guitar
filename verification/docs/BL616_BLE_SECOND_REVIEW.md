# BLE第二轮代码检查（2026-10-25）

后续扫描排查更新：用户确认诊断v1在正常模式无USB设备，UPDATE模式仍有下载端口。
已增加诊断v2，在收到USB shell的ble_start命令前不初始化RF，用于避免RF卡住掩盖日志。
同时修正Android扫描显示：从广播包取名称并显示无名称设备，新增独立扫描诊断APK。
以下可靠性发现仍未修复；本段之后的“未修改”描述指第二轮检查完成当时的范围。

基于当前26MHz候选及原Android客户端。生产固件/Android代码未在本轮修改；
只添加复现材料和独立诊断工程。未烧录、未访问物理COM。

## 需修复的发现

### P1：安卓旧连接回调能修改新连接状态

`mobile/android/app/src/main/java/com/keyi/xinxian/guitar/BleUartClient.java:221`。
所有BluetoothGattCallback均缺少active==gatt或连接代次校验。用户快速重连时，
旧连接延迟到达的DISCONNECTED会failWrite当前新请求；旧订阅回调可把ready设true；
旧写回调还会移除新连接的chunks队头。修复应统一串行调度状态、检查连接身份/代次，
重连时清理rx/mtu和未完成请求；不能只在一个回调加判断。

### P1：COMMIT传输失败未按提交结果未知处理

`Xg3Client.java:99`只把RequestTimeout转成CommitUnknown，而115行的
transport.write(...).get会抛ExecutionException、TimeoutException或InterruptedException。
若COMMIT实际到达FPGA后BLE断开，MainActivity会落入普通“上传失败”，然后重新启用上传。
即便捕获CommitUnknown，也只有一条临时日志，没有持久化待核对记录及重传阻止。

已用原Xg3Client/Xg3Protocol源码与可控假传输执行Java复现：BEGIN/DATA正常ACK，
COMMIT先标记已到设备再使传输Future失败，实际抛ExecutionException，未转换CommitUnknown。
材料在 `build/p5_bluetooth/review_20261025/java/`。这是主机逻辑复现，不是FPGA实物提交测试。
修复应在可能送出COMMIT前记录待确认状态，凡不能证明未提交的错误都要求重连查询，
明确核对后才能清除，不能把连接错误视为回滚。

### P2：断线不会撤销旧UART队列或在途块

`firmware/bl616_ble_uart_bridge/ble_nus.c:95`只清连接指针/通知开关。
`uart_bridge.c:61`继续把断线前队列写给FPGA；90行收到的旧ACK队列则在下次订阅后继续发出。
98行重试中的局部块也没有绑定连接代次，快速重连后有机会发给新连接。
XG3的随机会话/CRC会拒绝许多陈旧ACK，但不能阻止旧命令继续执行，也不能代替桥层隔离。
修复应让串行任务管理连接代次及队列清理，拒绝旧代次的工作；不能直接在回调中无同步
地reset正被任务/ISR使用的StreamBuffer。

### P2：固件跨任务共享连接指针缺少引用及同步

`ble_nus.c:88,163,176`直接保存并使用SDK回调提供的连接指针，断线回调则改为NULL，
UART任务同时取MTU/发送通知。没有bt_conn_ref/unref或临界区/串行任务保护。
SDK连接池会按ref复用对象；快速断线重连时存在访问失效或已复用连接的风险。
应在同步边界取得连接引用并在调用完成后释放，结合连接代次避免将旧数据用于新连接。
本项为代码和SDK实现确认的竞争风险，未在实物复现重启；不宣称其解释初次无广播。

### P2：安卓write可能返回null而不是失败Future

`BleUartClient.java:126`调用writeNext后返回字段pendingWrite。
若系统写操作立即拒绝，writeNext→failWrite会把该字段置null；空数据写也会同步清空。
调用方随后的.get发生NullPointerException，丢失真实错误。应把新Future保存在局部变量后返回，
并保证异步写超时后取消/关闭当前传输，否则pendingWrite可能永久占位。

## 与无法扫描的关系

上述连接/传输问题不解释尚未建立连接时完全没有广播。26MHz修复仍是实际适配缺陷，
但用户报告修正版依旧搜不到，因此不能把其当作已解决实物故障。

用户报告SW2第5 OFF、第6 ON。核对31005原理图第7页：R2/R3下拉、R53/R54经开关
接3V3；第6 ON使EN=1，第5 OFF使MODE=0，即Game模式，不能反说第6 ON会拉低使能。
C186/C187 NC是正常预留匹配，L9应为0Ω；尚无实物导通或RF电压测量。

独立诊断工程 `firmware/bl616_ble_diagnostic/`使用相同26MHz适配，取消FPGA UART，
广播XINXIAN-DIAG，并通过USB CDC每2秒报告RF/HCI/ready/adv状态。诊断镜像的
成功编译、命令返回0、USB枚举及真正的空口广播是不同层次，分别验证，不混称已成功。
