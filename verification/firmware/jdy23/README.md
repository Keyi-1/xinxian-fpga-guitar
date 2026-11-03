# JDY-23：3.3V 蓝牙广播与手机曲谱传输

适用：Tang Mega 60K、NEO Dock **31005**、带排针的 **JDY-23 转接板**、Android 手机。
JDY-23 使用自身 BLE 固件连接手机；FPGA处理原XG3协议、CRC、RAM读回校验和提交。
JDY-23不需要烧入旧BL616蓝牙BIN，上电广播由模块完成。UART保持默认 **9600/8N1**，FPGA50MHz/5208分频约为9600.61波特。
本地测试通过不代表实物射频验收，实际供电和手机连接仍需下板验证。

## 1. 先验证模块广播

断电接线，先只接 **VCC→底板3V3、GND→底板GND**，底板保持原12V供电。
用BLE调试助手或新App扫描，未改名时一般为 **JDY-23**，配置后为 **XINXIAN-JDY23**。
此步骤不需要新FPGA位流或DEBUG-USB2；先断开其他手机对模块的连接。
按转接板丝印接线，不能按裸模块编号推断排针顺序；3.3V模块不能接5V或12V。

## 2. 四线接入 FPGA

已核对31005底板原理图第7/19页及60K核心板30353/30354的BTB接口。
用户确认J8-9/10实物空闲；新上传串口不再连接BL616的U15/V14。

| JDY-23丝印 | NEO Dock 31005 | FPGA方向 |
| --- | --- | --- |
| VCC / 3V3 | **J8-1 或 J8-2：+3V3** | 电源 |
| GND | **J8-3 或 J8-4：GND**，或同板公共地分线 | 公共地 |
| TXD | **J8-10：PMOD1_IO3** | **AB22，接收** |
| RXD | **J8-9：PMOD1_IO2** | **AB21，发送** |

本底板J8的 **1/2是3V3，3/4是GND**，不能照搬其他PMOD板的通用编号。
上述是原理图针号，不是“从照片左边开始数”；按1脚标识/方焊盘核对，看不清方向先发照片。
原ADC仍使用J8-5～8，MPU-6050仍使用J8-11/12。PWRC、RST、STAT本方案不使用，保留模块默认状态。

### GND位置不够

**GND可以共用，无需每个模块独占一根底板地针。**
将现有GND接到一进多出的接线端子、可靠Y型分线或面包板公共地排，再分别接原模块和JDY的GND，保持原接地支路。
面包板地排中间可能断开，断电后确认导通；不要让第二个杜邦母头松搭在已占用的针上。
不要用FPGA普通IO输出0代替GND，不把地线接到3V3/5V/12V。
若3V3针也已占用，可从同一底板的3V3经分配端子分线；不要并联底板与CH340的两路电源输出。

## 3. 可选的一次性模块配置

默认模块不改名也能被新App发现。推荐用现有CH340检查并配置名称。
**配置时先断开JDY与FPGA间的TXD/RXD两线，断开手机连接。**
CH340的3.3V逻辑TXD→JDY RXD、RXD→JDY TXD、GND→公共GND。
JDY仍用底板3V3供电，CH340的VCC/3V3/5V电源输出均不接；核对CH340的TX逻辑电平，3V3供电输出标记不能代替电平确认。
在解压后含脚本的目录打开PowerShell，把COM10替换为实际CH340端口：

```powershell
powershell -ExecutionPolicy Bypass -File .\configure_jdy23.ps1 -Port COM10
```

默认仅查询版本、连接状态、名称、波特率、MAC。确认返回JDY-23后配置：
JDY-23有自己的MAC，不能沿用之前BL616的地址。

```powershell
powershell -ExecutionPolicy Bypass -File .\configure_jdy23.ps1 -Port COM10 -Configure
```

脚本逐条检查回复，命令以CRLF结束：

```text
AT+HOSTEN0             从机透传
AT+STARTEN1            上电唤醒
AT+ADVIN1              200ms广播
AT+ENLOG0              关闭额外串口状态文本
AT+MTU1                模块到手机20字节
AT+NAMEXINXIAN-JDY23   广播名称
```

不改波特率或MAC，不恢复出厂，不写模块固件。参数可能保存于模块非易失存储。
出现CONFIG_OK后断电，移除CH340的TX/RX，按第2节接回FPGA后重新上电。
无回复时停止，核对3.3V、共地、TX/RX交叉、9600与实际型号，不继续盲发设置。

## 4. 下载新 FPGA 位流

选交付包 **neo_guitar_touch_game_jdy23_9600.fs**；新串口位置和速率都在此FS中，旧FS不能按本表收发。
在Gowin Programmer中沿用已成功使用的60K器件/下载器配置，先选 **SRAM Program** 做可恢复测试，掉电后该配置丢失。
实物验收后，需要掉电保留时再沿用原SPI Flash下载流程。这里是FPGA FS，不用DevCube，不写BL616的0x40000。
只调整原工程的上传串口分频和两个引脚；触控、ADC、MPU、音色、尾音锁定、内置曲谱和RAM协议保持原源码。
本版上传走J8的JDY-23，不再走DEBUG-USB2串口；FPGA下载/JTAG仍走原硬件接口。

### 原板音频时钟仍需保留

不用BL616蓝牙，不等于可以取消原板 **MS5351 CLK2=12.288MHz** 的初始化。
如果仍装着自动启动BLE的诊断程序，可用包内 `optional_clock_restore/` 的原始时钟恢复V2 BIN退出旧诊断。
这是你们之前已验证的文件副本，不是新的蓝牙固件；SHA256：
`79ac33d154ebe64a7df91fcfa4f76df3f466ca2685d78c1f5f48e4250b8761b3`。
仅在需要退出旧诊断时，沿用原DevCube流程写入 **0x40000**，保留 **0x0**，不整片擦除。
若现有正常固件已稳定初始化时钟，无需再改BL616。JDY广播不依赖该音频时钟，吉他整机启动/声音仍依赖它。

## 5. 新 Android App 导谱

安装 **xinxian_jdy23.apk**，显示名“弦心吉他·JDY23”，可与旧App并存。
新App识别JDY的FFE0服务、FFE1收发特征，不向FFE2 IO控制特征发送曲谱；旧BL616专用App不能代替。

1. 底板正常供电，FPGA加载新FS，停留在主页/选曲页，音频空闲。
2. App允许蓝牙/附近设备权限，扫描并选择JDY-23或XINXIAN-JDY23。
3. 等待“JDY-23 串口已就绪”以及 **XG3握手成功**。
4. 读取5个曲目槽，确认确实收到FPGA回应。
5. 选择 `.bin`，先试USER 2或USER 5。包内 `example/qing_ge.bin` 是现有正式212事件曲谱，CRC32=c3451bbc，未重新编谱。
6. 只有获得FPGA的COMMIT成功确认并核对目录后，才显示“上传完成并经FPGA RAM读回校验”；在开发板选择对应USER槽试听。

32字节XG3帧分20+12发送，分片间隔至少35ms，逐帧等待FPGA ACK。
重连等待6秒并使用新会话；等待本身不保证回滚，仍由FPGA回应判定。
提交时断线会保存待核对标记并禁止重传，先查询/试听，再人工解除限制；目录条数相同不能证明内容相同。
手机断开后可独立演奏；RAM曲目在FPGA断电、复位或重配置后丢失。

## 故障分层

| 现象 | 下一步 |
| --- | --- |
| 默认JDY-23也扫不到 | 先只接3V3/GND，检查电压、型号及其他手机占用；此步骤不依赖FS |
| 没有FFE0/FFE1 | BLE助手查看服务、保存AT+VER，不套用其他模块UUID |
| BLE就绪但XG3握手失败 | 查新FS、J8-9/10、TX/RX交叉、共地、9600与12.288MHz时钟 |
| 上传中失败/待核对 | 保存App完整日志，保持板子供电，先查询试听，不反复上传 |
| JDY连接正常但整机无显示/声音 | 单独检查原音频时钟初始化 |

## 依据与验证

[Sipeed介绍](https://wiki.sipeed.com/hardware/en/maix/modules_spmod/spmod_bt.html)说明UART、供电、默认9600与CRLF。
[制造商手册副本](https://voltiq.ru/datasheets/JDY-23-datasheet.pdf)说明四线、默认广播、FFE0/FFE1及AT命令；实际以AT+VER和服务发现确认。
引脚依据31005原理图7/19页、60K核心板30353/30354的BTB表。
新增真实50MHz/9600 UART、XG3→BSRAM读回CRC→跨时钟提交测试，覆盖分片、DATA/COMMIT重复及CRC错误。
Android实际传输类用可控系统模型验证，APK另做编译/签名检查，未冒充手机实测。
最终FS仅在原工程综合、完整布局布线、时序及引脚检查通过后进入发布包；结果见verification.json。
