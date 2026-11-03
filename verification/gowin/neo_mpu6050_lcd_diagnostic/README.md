# MPU-6050 / MPU-6500 + LCD 最小诊断工程

这个独立工程用于排查吉他固件一直显示 `IMU OFFLINE` 的问题。只使用 50 MHz FPGA 时钟、原 LCD 和 MPU-6050；不需要触控、UART、电脑软件或姿态校准。功放保持关闭。原吉他工程、配置和发布位流不受影响。

## 下载和观察

1. 用原来的 Gowin Programmer 下载本工程的 `impl/pnr/neo_mpu6050_lcd_diagnostic.fs`，或者独立归档 `build/releases/mpu_lcd_diagnostic_id70/neo_mpu6050_6500_lcd_diagnostic.fs`。这是新版专用诊断程序，屏幕应显示 `MPU6050/6500 LCD DIAG`，不再是吉他菜单。原严格 ID68 诊断归档 `build/releases/mpu_lcd_diagnostic/` 保留，不能用它测试 ID70 的采样。
2. 保留当前已确认的接线，上电等待约 1 秒。程序会先探测两个地址，按 ID68 或 ID70 选择配置，再复位、唤醒和逐项读回配置，连续取得 10 包数据后显示绿色 `STATUS: PASS LIVE`。GZ 旁的 `CHIP:6050 / 6500` 表示所采用的寄存器配置，不是对芯片真伪的鉴定。
3. 观察 `COUNT HEX` 持续增加；缓慢倾斜模块，`AX / AY / AZ` 应变化。静止时三轴重力合成约为 8192，某一轴竖直时该轴约为 +8192 或 -8192；实际零偏和噪声会造成差异。`GX / GY / GZ` 是陀螺仪原始值，转动时应改变。
4. 若失败，拍下整个诊断页，尤其是两个地址的 `ACK / ID / ERR`、`STATUS`、`STEP / REG` 和 `CHECK`。程序约每秒自动重试，不必重新下载。

`PASS LIVE` 说明应答、身份、配置读回和新鲜数据通信通过；仍须用实物倾斜观察数据变化，不能据此证明精度、零偏、长期稳定性或原吉他程序全部功能正常。程序不要求按 `CALIBRATE` 或开启 `AUTO`。

## 接线不变

| MPU-6050 模块 | 开发板连接 | FPGA 管脚 |
| --- | --- | --- |
| VCC | J8-1，3.3 V | 电源 |
| GND | J8-3 或其他已确认的共地 GND | 地 |
| SCL | J8-11 | Y21 |
| SDA | J8-12 | Y22 |
| AD0 | GND，选择 0x68 | 无需接 FPGA |
| XDA / XCL / INT | 不接 | 不使用 |

如果 AD0 接 3.3 V，程序也会探测 0x69。AD0 只改变总线地址，不改变 WHO_AM_I。正常 MPU-6050 的身份值为 0x68，MPU-6500 为 0x70；两款的总线地址都可以为 0x68 或 0x69。只有一个地址有应答是正常的，另一行 `ACK:0 ID:-- ERR:1` 不表示整体失败。

## 诊断页含义

- `IDLE SCL / SDA`：一次探测开始前的总线电平快照；正常空闲时均为 1。这不是传输期间的实时电平。
- `68 / 69 ACK`：该地址的写地址阶段有没有应答。`ID` 是实际读出的 WHO_AM_I；`--` 表示该次读操作没有完整成功。
- `STATUS: NO ACK`：两个地址都没有完成身份读取；结合下面的错误码区别地址无应答、后续 NACK 和卡住的线路。
- `STATUS: WRONG CHIP ID`：总线已读到数据，但不是允许的 0x68 / 0x70。保留实际 ID，不直接跳过身份检查。
- `STATUS: CONFIG / BUS ERROR`：配置读回不匹配，或复位/配置/采样阶段通信失败。`CHECK EXP / GOT` 显示最近配置读回的期望值和实际值；失败时保留相关寄存器和阶段。
- `STATUS: DATA STALE`：超过 100 ms 没有得到新鲜完整数据包。旧轴值会保留，不能把旧值当成继续工作。
- `STEP`、`REG`、`ADDR`、`EXP`、`GOT`、`ERR`、`E`、`FAULT`、`AGE`、`COUNT HEX` 均为十六进制；`AX..GZ` 是带正负号的十进制。AGE 单位为毫秒，FFFF 表示尚无有效采样或已经饱和。计数器开机清零。
- 在正常采样时，`REG` 是当前轮询/数据寄存器，`EXP / GOT` 仍保留最近一次配置检查，所以不必与当前 `REG` 配对解读。

| E / ERR | 含义 |
| --- | --- |
| 0 | 本次操作成功 |
| 1 | 写地址阶段没有 ACK |
| 2 | 寄存器地址阶段没有 ACK |
| 3 | 写数据阶段没有 ACK |
| 4 | 重复起始后的读地址阶段没有 ACK |
| 5 | SCL 无法拉高，10 ms 超时 |
| 6 | 起始前 SDA 被拉低，尝试总线恢复 |
| 7 | 配置寄存器读回不匹配 |
| 8 | 新鲜数据超时 |
| 9 | 事务超时或无效读长度 |
| A | WHO_AM_I 不等于 0x68 或 0x70 |

常见 STEP（十六进制）：02 / 04 为两个地址探测等待，05 为身份选择失败，07 为复位写入，0A 为配置写入，0C 为配置读回，10 为数据就绪读取，12 为 14 字节数据读取。故障页显示保存的失败阶段，正常页显示当前阶段。

## 实现和复现

主工程：`neo_mpu6050_lcd_diagnostic.gprj`，顶层 `neo_mpu6050_lcd_diagnostic_top`。器件 GW5AT-LV60PG484AC1/I0，Device B，工具 Gowin V1.9.12.03。可直接打开本 gprj；综合、布线和位流在本工程自己的 `impl` 中。

独立 I²C 主机由原主机分出诊断版本，只增加应答阶段和错误码记录，不修改生产主机。标称 100 kHz 开漏 I²C，先只读 WHO_AM_I，确认身份后使用加速度 ±4g（8192 LSB/g）、陀螺仪 ±250°/s、100 Hz 数据率。ID68 沿用原 10 项配置；ID70 额外写入并读回 `ACCEL_CONFIG2 (0x1D)=0x03`，启用 MPU-6500 的独立加速度低通，6050 路径不访问此寄存器。上电等待 200 ms、软复位等待 200 ms、唤醒等待 50 ms；无中断引脚依赖，通过 INT_STATUS 的 DATA_RDY 位取新数据，再连续读 14 字节，跳过温度字段并原子提交六轴。

依据 InvenSense [MPU-6500 寄存器说明](https://www.tinytronics.nl/product_files/001439_MPU-6500-Register-Map2%20%281%29.pdf)，ID70、通信地址、独立加速度配置与数据寄存器分别核对；唤醒等待参考 [MPU-6500 产品规格](https://invensense.tdk.com/wp-content/uploads/2020/06/PS-MPU-6500A-01-v1.3.pdf)。本程序采用 6500 寄存器配置测试 ID70 模块，不能仅凭身份值认证其制造商或内部型号。

LCD 沿用已经使用的 480×272 RGB666 扫描器，50 MHz / 6，DCLK 约 8.333 MHz。诊断值在消隐期按帧快照，六个有符号数共用十进制转换器；字体两级流水，在扫描器第六个系统时钟锁存前稳定。新 CST 只复制所需原引脚，原 CST/SDC 保持原样。SDC 约束内部 50 MHz 时钟，I²C 异步输入到同步器首级设假路径；并未用通用板级参数替代实际 LCD 外部时序测量。

在仓库根目录运行：

```powershell
# 两个命令都保留已有证据目录；再次运行须使用新 RunName。
./tools/run_mpu_lcd_diag_checks.ps1 -RunName rtl_new -Mode RTL
./tools/start_mpu_lcd_diag_build.ps1 -RunName impl_new
./tools/run_mpu_lcd_diag_checks.ps1 -RunName gate_new -Mode Gate
```

ModelSim 在受限运行环境可能遇到系统 DLL 重定位错误，需要由正常 Windows 终端运行；不要因此删除验证。构建脚本记录 PID、日志路径和所有构建输入 SHA256，检测到其他 Gowin 构建进程时停止，避免与吉他工程并行构建。

## 本批验证和限制

- RTL 引脚级故障注入：ID68/ID70 各自覆盖通信地址 0x68/0x69、未接模块、未知 ID71、各阶段 NACK、配置读回错误、无新数据、SCL/SDA 卡低与恢复；ID68 不写 0x1D，ID70 配置并读回该项。
- 显示：正负边界含 -32768、帧快照、完整 LCD 扫描；实际 LCD 引脚输出 130,560 个有效像素与独立字形栅格化逐点相同。
- 实际综合后网表对照采用 ID70 配置，覆盖真实默认等待和变化的六轴数据；完整实现结果见同目录 `verification.json`。它只认证本诊断程序，不认证原吉他工程或实物模块。
- 实物烧录、模块实际 ID、倾斜响应、供电/上拉电压、杜邦线接触与长期稳定性仍需现场检查。灯亮只说明指示灯供电支路有电，不能证明 I²C 或 MEMS 数据正常。

测试结束后可重新下载原 `gowin/neo_guitar_touch_game/impl/pnr/neo_guitar_touch_game.fs`，恢复吉他固件。该原位流本批保持 SHA256 `cfda7ead63703142876e10776a38f86237188aeb4a4d910b02aa0927df611a30`。
