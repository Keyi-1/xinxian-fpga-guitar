# 完整吉他固件的 ID70 兼容修复

## 实物依据与范围

用户使用独立诊断程序报告 `68 ACK:1 ID:70 ERR:0`、`69 ACK:0 ID:-- ERR:1`。采用 ID70 的 6500 寄存器配置后，用户进一步确认 `PASS LIVE`、计数持续增加、倾斜时加速度变化。这说明该模块可按当前 6500 配置通信和采样，不据此认证芯片真伪。

2026-10-23 用户授权将这套兼容支持接回完整吉他工程，生成完整位流并覆盖当前错误的原工程位流及同名发布副本。不烧录实物，不打开 COM，不推送、合并或改动 Git 暂存区。

生产工程仍为 `gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj`，顶层 `neo_guitar_touch_game_top`，GW5AT-LV60PG484AC1/I0 Device B，Gowin V1.9.12.03。综合与布线直接在该工程 `impl` 中完成；`build/imu_id70/` 只存证据和旧版本快照。

## 代码变化

唯一生产源码变化为 `rtl/input/mpu6050_reader.v`：

- 接受明确的身份值 0x68 或 0x70，其他 ID 仍报故障。
- ID68 沿用原 10 项配置和 30 ms 唤醒等待，不访问 0x1D。
- ID70 增加写入和读回 `ACCEL_CONFIG2 (0x1D)=0x03`，唤醒等待 50 ms；其余共同配置保持。
- 加速度继续 ±4g、8192 LSB/g，陀螺仪 ±250°/s，采样配置 100 Hz。14 字节完整读取、符号和字节序、温度跳过、序号、超时及恢复规则保持。

地址仍为 0x68，AD0 继续接地。SCL=J8-11/Y21、SDA=J8-12/Y22，供电及其余接线保持。音色模型、四档力度/增益、音效、曲谱、触控、显示、校准/姿态分类/空闲切音色策略、CST/SDC、工程配置均保持。

依据 InvenSense [MPU-6500 寄存器说明](https://www.tinytronics.nl/product_files/001439_MPU-6500-Register-Map2%20%281%29.pdf)核对身份、地址、加速度配置和数据寄存器；[产品规格](https://invensense.tdk.com/wp-content/uploads/2020/06/PS-MPU-6500A-01-v1.3.pdf)给出陀螺仪典型唤醒时间 35 ms，本程序留出 50 ms。

测试模型增加独立 WHO_AM_I、总线地址和故障读回参数。旧 `bad_id` 从原来的 70 改为不支持的 71，因为 70 现在有明确配置支持；故障检查并未移除。冻结原读取器位于 `sim/reference/imu_id70/`，不参与生产综合。

## 构建与证据

旧完整版本 SHA256：`cfda7ead63703142876e10776a38f86237188aeb4a4d910b02aa0927df611a30`。旧源码、原工程 VG/位流/报告/认证及两个保护文件快照在 `build/imu_id70/before_20261023/`，既有季度增益固定发布归档也保留。

本批构建证据 `build/imu_id70/v1/`，脚本记录 PID、启动时间、源码哈希与日志。恢复时先检查 `process.json`、`route_process.json` 及其日志；不得重复启动仍在运行的综合或 P&R。

入口：

```powershell
./tools/start_original_imu_id70_build.ps1 -Stage Synthesis -RunName v1
E:/anaconda3/python.exe -X utf8 tools/check_imu_id70_result.py review
./tools/start_original_imu_id70_build.ps1 -Stage Route -RunName v1
```

工具只读取原工程配置，不调用 `set_option`；两个用户保护文件的字节和暂存对象都核对。完整交付认证为 `gowin/neo_guitar_touch_game/imu_id70_verification.json`，仅在新实际网表、回归及 P&R/STA 全部通过后签出。旧 `quarter_dynamics_verification.json` 只认证旧快照，不能用于认证新位流。

新检查只为已独立通过的 MPU 读取器提供明确源码例外。全部音源/显示/曲库/ADC 仍按旧源码哈希保护；综合网表比较发现相同 RTL 的部分 LUT 映射发生变化，因此不宣称新旧网表结构相同，也不复用旧门级结果认证新映射。本批重新做当前实际 VG 的 ADC、UART/游戏/声音/LCD 和 ID70 姿态整机验证，不通过寄存器数量或旧日志替代新实现验证。

## 回归范围与现场检查

- 读取器：ID70 的两个地址、独立加速度配置、动态有符号数据、未知 ID、配置读回错误、NACK、stale、半包丢弃和恢复；ID68 与独立冻结参考逐周期一致。
- 校准、姿态三状态、健康/迟滞/运动拒绝、空闲/尾音/手动优先、CDC、触控与 I²C 故障回归。
- 完整 RTL：ID68/ID70 校准、AUTO、物理音色键、延音等待、取消/退出/重入/掉线恢复；原显示对照。
- 冻结音频继续使用 655458f32ba4f7e06403fd6c5c4da0b6f0dad8a7，仅保留此前已经授权的增益 112/160/208→64/128/192 例外；扩展音域、游戏判定和按键职责也检查。
- 当前实际 VG：完整吉他 UART/曲库/游戏/声音/LCD，以及 ID70 实际 MPU 引脚/校准/音色切换；测试等待加速、触控刺激及完整生产校准计数的边界随认证记录。

门级检查保留既有入口对 Gowin `prim_sim.v` 指定 12 行的 `vopt-2697` 存储器切片提示例外；不屏蔽其他告警、工程 HDL 告警或断言失败。P&R 的两条既有 PR1014 时钟路由提示也保留，STA 使用真实布线延迟，不能把它们写成“零告警”。

新完整位流还需用户下板：保持接线，先在主页看状态由 OFFLINE 变为 `NEED CAL`（正常的未校准提示）；将模块放平并保持静止，点 `CALIBRATE`，等待 `CAL...`、`SETTLING` 结束，再启用 `AUTO ON`。缓慢改变姿态，在声音结束后观察自动切音色。演奏页使用 healthy 状态，未校准前可能仍显示 OFFLINE，因此先完成主页校准再判断修复是否生效。再确认三音色、四弦力度、手动切换、游戏选曲/试听/退出、UART 导入等现有功能。独立诊断的实物通过不等于新完整固件全部现场验收。
