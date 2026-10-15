# 频带模块独立资源／时序实验

## 基线与结论

2026-10-15，按用户“先把现在的版本合并到 master，然后再展开对频带模块的独立实验”的授权，
本地 `master` 从 `efdcf24277ab560b527ef1b24ab4348f77c9ae61` 快进到
`8230217e56952ee2793b97d98ef90e2740fff54b`，包含已验证的 P1 实现、发布记录和用户反馈。
无分歧提交，无需额外 merge commit。未 push；原实施分支保留。
随后从该基线建立 `experiment/radial-bands-resource-opt`。

**两种对数量化改写均保持组件行为，但本次收益不足以集成。**
直接尾数选择只节省 1 个综合 ALU；平衡树候选略省面积，独立实装时序反而下降。
实验源码留在 `experiments/radial_bands/`，未替换生产 `rtl/display/guitar_radial_bands.v`。
后续优先评估工作数组存储／动态选择，再评估保持发布时间的流水线。

当前可下板版本仍是 P1：CLS 27943/29952（93.29%）、系统 Fmax 58.765 MHz、
音频 Fmax 14.442 MHz，运行时钟为 50 MHz／12.288 MHz。
位流仍为 `build/releases/touch_game/neo_guitar_touch_game_p1_display_opt.fs`，
SHA256 `e8ddbbc64dc81cf61c3037039b54752bf3a21ecca155264bfe6db907f9354c86`。
上述是原完整实现结果；以下表格是本次独立模块实验，二者口径不同。

## 改动范围与冻结参考

当前已验证整机最紧系统路径经过 `u_display/u_bands/index_2_s0` →
`pending_targets_146_s0`，包含工作数组选择、对数量化、差值和衰减，共 25 级逻辑。
本次先隔离对数量化，未调整数组、AGC、状态机、原子提交或发布时刻：

- 冻结参考：`sim/reference/radial_bands/guitar_radial_bands_frozen.v`，
  与上述基线的生产模块逐字一致，仅重命名模块。
- 直接尾数候选：`experiments/radial_bands/guitar_radial_bands_direct_log.v`。
  按最高有效位直接选择其下三位，代替通用移位。
- 平衡树候选：`experiments/radial_bands/guitar_radial_bands_balanced_log.v`。
  用分组归约与平衡分支查找最高有效位，再选择相同的三位尾数。
- 两个候选均保留最终加法以保持原 X/Z 传播；低值 0～7 的结果也完全保留。
  `prepare_radial_bands_experiment.py` 自动检查：去掉 `log2q3` 函数后，候选与冻结参考相同。

首版直接拼接对所有二进制输入正确，但 X/Z 探针发现其传播与原加法不同。
修正后全部探针通过；初版失败日志保留，没有删除或放宽相应断言。

## 组件等价验证

测试入口为 `tools/run_radial_bands_experiment_checks.ps1`，测试台为
`sim/tb/tb_radial_bands_equivalence.sv`。两个候选各完成：

1. `log2q3` 全部 524288 个 19 位二进制输入，以及 722 组 X/Z 探针。
2. RTL 逐时钟比较全部 `targets`、`update`、工作数组、AGC、最大值、参考值、
   索引、归约状态和待提交数组，共 209515 个时钟、734 次发布。
3. 实际 Gowin 综合网表与同参数冻结基线综合网表比较外部输出，同样为
   209515 个时钟、734 次发布；未强制内部状态或跳过复位序列。

覆盖 DC 排除、Nyquist、频带边界、同频带连续输入及重复／逆序 bin、
0／7／8／31／32／1023／1024／最大值和幂次边缘、随机间隔、192 帧静音 AGC 衰减、
末 bin 与 frame_done 同拍、无有效 bin 的 frame_done、归约期间输入和清零冲突、
连续 frame_done 重启、累积／归约期间复位及随机恢复。
目标只在 update 时原子改变；正常及重启后的归约发布均保持第 32 拍。

### 保留的 RTL／独立网表复位差异

直接尾数综合网表最初与冻结 RTL 对照，在运行期再次复位后的首个发布出现差异：
第 187145 拍，双方 update 均为 1，但部分频带高度不同。
将候选替换为**未修改的冻结基线综合网表**，在完全相同的输入下得到同一差异：

```text
RTL:      0000000000000000000006c00000000000000000
baseline: d801b0000006f600036006c00000000000000000
candidate:d801b0000006f600036006c00000000000000000
```

因此不能声称整个压力序列的 RTL 对网表对照通过，也不能把该差异归因于此次函数改写。
当前证据尚未确立根因。新增的基线网表对候选网表比较通过完整序列，是另一项明确区分的证据。
原失败对照及诊断记录全部保留，没有以它们认证候选为新的整机可下板版本。

当前生产顶层的 `startup_count` 饱和后保持，显示复位由该上电链生成，
页面切换不重新拉低频带复位。上述实验再次复位场景超出当前正常页面操作；
它仍是以后更改复位契约、存储结构或集成候选时必须复查的项目。
本次没有新增实物异常证据，也没有修改已验收的生产版本。

## 同口径综合与独立 P&R

Gowin V1.9.12.03，GW5AT-LV60PG484AC1/I0、Device B、Verilog 2001。
每组基线与候选采用同一顶层名称和选项。P&R 使用 Place=4、Route=2、Clock Route Order=1，
生成命令确认 `correct_hold 1`。模块仅有 clk，P&R SDC 为 20 ns。
未使用板级 CST，IO 自动放置；此处结果只认证模块寄存器路径，不能预测整机实装收益或 IO 时序。

| 独立综合 | 基线 | 直接尾数 | 平衡树 |
|---|---:|---:|---:|
| Register | 968 | 968 | 968 |
| LUT | 1638 | 1638 | 1612 |
| ALU | 76 | 75 | 77 |
| BSRAM／DSP | 0／0 | 0／0 | 0／0 |
| 综合估计 Fmax | 70.732 MHz | 72.878 MHz | 69.131 MHz |

两组独立基线综合资源相同。综合报告采用工具默认 100 MHz 估计约束，
这些估计值不替代下表的 50 MHz 约束真实 STA。
独立模块资源也不等于生产上下文模块的 967 Register／1580 LUT／77 ALU。

| 独立模块完整实现 | 基线 | 平衡树 | 变化 |
|---|---:|---:|---:|
| Logic | 1718 | 1693 | −25 |
| Register | 968 | 968 | 0 |
| CLS | 1435 | 1403 | −32（−2.23%） |
| BSRAM／DSP | 0／0 | 0／0 | 0 |
| Fmax | 59.407 MHz | 53.343 MHz | −6.064 MHz（−10.21%） |
| 最紧 setup slack | 3.167 ns | 1.254 ns | −1.913 ns |
| setup／hold／未布通／latch | 0／0／0／0 | 0／0／0／0 | 保持 |

基线最紧路径是 `index_4_s0/Q` → `pending_targets_78_s0/D`，
候选为 `index_4_s0/Q` → `targets_158_s1/D`；动态选择到量化／提交的长路径仍在。
这是一组同选项布局布线的观测，不是多种布局种子的统计结论。
两者满足实验 50 MHz，但平衡树时序明显回退，故不集成。
直接尾数面积变化很小，本次未继续对其 P&R，也未对任何候选启动整机 P&R。

原有 map 表达式产生的 EX3791 位宽截断提示在基线与候选中均存在；
P&R 的 PA1001 悬空算术中间位提示保留在原日志中，无 ERROR。
没有为通过实验修改生产校验器、音频保护、CST／SDC、音色、FFT 点数、玩法或接线。

## 进程、归档与复现

| 独立构建 | 阶段 | PID | 日志（仓库相对路径） |
|---|---|---:|---|
| 直接尾数基线 | 综合 | 15388 | `build/radial_bands_experiment/direct_log_attempt1/baseline/synthesis.log` |
| 直接尾数候选 | 综合 | 9784 | `build/radial_bands_experiment/direct_log_attempt1/direct_log/synthesis.log` |
| 平衡树基线 | 综合 | 33128 | `build/radial_bands_experiment/balanced_log_attempt1/baseline/synthesis.log` |
| 平衡树候选 | 综合 | 29352 | `build/radial_bands_experiment/balanced_log_attempt1/balanced_log/synthesis.log` |
| 平衡树基线 | P&R | 26308 | `build/radial_bands_experiment/balanced_log_attempt1/baseline/route.log` |
| 平衡树候选 | P&R | 25052 | `build/radial_bands_experiment/balanced_log_attempt1/balanced_log/route.log` |

所有构建已结束。启动时间、源码／Tcl／SDC 快照及 PID 见各 attempt 的 manifest.json。
第一次配对网表编译遇到运行器单元素数组展开错误，已修复；失败编译日志同样保留。

独立归档：`build/radial_bands_experiment/archive_20261015/verification.json`，
同目录包含 `source_snapshot.zip` 和 `evidence/`，绑定两个候选、冻结参考、测试源码、
综合网表、RTL／网表仿真、综合、P&R／STA 和诊断日志的 SHA256。
运行记录分别标明“RTL 对 RTL”和“综合网表对综合网表”的范围。
归档不包含实验模块的自动引脚位流；本轮没有新增可下板位流。

```powershell
# 每次使用新目录，工具拒绝覆盖已有证据。
./tools/run_radial_bands_experiment_checks.ps1 -RunDir sim/temp/radial_bands_experiment/new_rtl -Candidate balanced_log
E:/anaconda3/python.exe tools/prepare_radial_bands_experiment.py build/radial_bands_experiment/new_run --candidate balanced_log
./tools/start_radial_bands_experiment.ps1 -RunDir build/radial_bands_experiment/new_run -Variant baseline
# 检查基线进程已结束，再启动候选；综合收益足够时再依次 route。
./tools/start_radial_bands_experiment.ps1 -RunDir build/radial_bands_experiment/new_run -Variant balanced_log
./tools/run_radial_bands_experiment_checks.ps1 -RunDir sim/temp/radial_bands_experiment/new_gate -Candidate balanced_log -GateNetlist build/radial_bands_experiment/new_run/balanced_log/impl/gwsynthesis/bands.vg -BaselineNetlist build/radial_bands_experiment/new_run/baseline/impl/gwsynthesis/bands.vg
./tools/start_radial_bands_experiment.ps1 -RunDir build/radial_bands_experiment/new_run -Variant baseline -Stage route
# 等前一个进程结束，再运行候选 route。
./tools/start_radial_bands_experiment.ps1 -RunDir build/radial_bands_experiment/new_run -Variant balanced_log -Stage route
```

## 后续候选及验证边界

本轮新完成组件验证、配对网表验证和上述模块 P&R。生产 RTL／ROM／约束和已发布 P1 证据均未变化，
因此没有重复运行已经完成的音频、触控／游戏、整机有效像素对照或整机 P&R。
这两种改写均不计作整机资源或 Fmax 收益，当前生产版本的实装结果保持不变。

下一项更有希望的实验是 `32×19 bit` 工作数组的存储与动态选择结构。
若用 RAM，必须确认真实 BSRAM 映射、连续同频带 bin 的读改写前递、归约期间读写清零冲突、
末 bin／frame_done 提交和复位；若新增流水线，必须保持目标发布边界，不能跨过视觉帧快照。
采用前仍需真实 FFT／显示动态对照、完整整机综合网表验证和 P&R／STA，最后才能产生新可下板版本。

两个受保护用户文件的工作内容和暂存 blob 均保持原样，未纳入本次提交。
当前 P1 的下板复测步骤继续见 `docs/DISPLAY_GAME_P1_RESOURCE_OPT.md`；本实验无新增接线或烧录步骤。
