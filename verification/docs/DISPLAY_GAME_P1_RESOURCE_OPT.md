# P1 显示／游戏资源优化

基线为全宽舞台合并提交 `efdcf24277ab560b527ef1b24ab4348f77c9ae61`。
工作分支 `experiment/display-game-resource-opt`；保留已有全宽四轨、训练配置及所有声音／操作。
本轮仅修改 `guitar_radial_palette.v` 的柱高／峰值更新调度。

## 实现与等价性

原来的 64 份展开算术改为一份共享算术，`visual_update` 锁存全部 160 bit 目标、
峰值衰减相位及插值边界状态，随后 64 拍完成。每两根柱推进一次频带移位寄存器。
邻柱插值、先空间平滑再攻击平滑的顺序、整数舍入、每帧下降一级及四帧峰值下降相位均保留。
第 0／63 根柱采用原有边界规则。曲线包络、颜色／字模／mask／RGB／坐标流水线和六拍扫描不变。

柱状态直接在垂直消隐内更新；无新增 RAM、帧缓冲或整套双份柱状态。
允许消隐中间值不同，有效视频开始前全部完成。集成测试实测更新到有效视频最少 38,451 拍，
64 拍使用约 0.167% 的该预算；有效期间柱状态与曲线增益保持稳定。
依赖条件是生产 renderer 每帧消隐内发出一次 `visual_update`；回归检查无重叠、无 deadline 违例。

独立参考保存在 `sim/reference/display_game_p1`，调色器从上述合并提交冻结，
校验器用 `git show` 验证参考只改了模块名。仅在 `--p1` 且独立证据通过时，
允许这个显示模块偏离原音频基线；其余旧 RTL／ROM 和音频保护继续检查。

已完成 RTL 数字检查：

- 512 组状态；64 根柱高／峰值逐项一致，1,108,992 像素一致；包含全幅、单点、交替、随机、
  零目标、攻击／衰减、目标中途变化、复位打断及恰好 64 拍完成。
- 真实双时钟、CDC、1024 点 FFT／频带、曲线行 RAM、游戏 UI 和 LCD 扫描集成；
  15 帧共 1,958,400 有效像素与冻结调色器一致，12 次真实 FFT 目标更新、峰值衰减、
  八帧曲线渐暗、单弦重触发和页面切换，显示／PCM deadline 均通过。
- 九项触控／游戏 RTL 与五项 Python 分弦回归通过。
- 冻结音频 `655458f32ba4f7e06403fd6c5c4da0b6f0dad8a7`：
  2,097,153 参考时钟／8192 样本一致，三音色与全部已有音效保留；延音退出 1452 样本。

## 完整实现结果

2026-10-15，Gowin V1.9.12.03、GW5AT-LV60PG484AC1/I0 Device B，
独立构建 `build/display_game_p1/attempt2` 已完成完整 P&R／STA 和位流生成。
前值取已归档的 `full_width_verification.json` 及 SHA256 为 `9c161ac6…70883` 的原全宽舞台发布，
不取后来重建的 IDE 结果；后值均为本次完整实现报告。

| 同一口径指标 | 全宽舞台归档基线 | P1 本次完整实现 | 变化 |
| --- | ---: | ---: | ---: |
| Logic / 59904 | 58178 | 50159 | −8019，−13.78% |
| Register / 60780 | 22239 | 22405 | +166 |
| CLS / 29952 | 29842，99.63% | 27943，93.29% | −1899 |
| BSRAM / 118 | 95 | 95 | 0 |
| DSP / 118 | 115.5 | 115.5 | 0 |
| 系统 Fmax，运行 50 MHz | 54.636 MHz | 58.765 MHz | +4.129 MHz |
| 音频 Fmax，运行 12.288 MHz | 13.441 MHz | 14.442 MHz | +1.001 MHz |
| setup / hold / 未布通 / latch | 0 / 0 / 0 / 0 | 0 / 0 / 0 / 0 | 保持 |

三项余量目标（CLS≤95%、系统≥55 MHz、音频≥13.5 MHz）均达到。
目标快照和串行控制使寄存器增加，但实装 Logic 和 CLS 均显著下降；不以寄存器数代替面积收益。
本次综合的整机 LUT／ALU 为 41261／8579；生产上下文调色器含子模块为 2767 LUT、846 ALU、1476 寄存器。
这些综合数据只作结构说明，最终资源表以 P&R 为准。

本次系统最紧 setup 路径已位于 `u_display/u_bands/index_2_s0` →
`u_display/u_bands/pending_targets_146_s0`，slack 2.983 ns，25 级逻辑，
涉及频带工作数组动态选择、量化和衰减。当前目标已满足，本轮不再继续改变该数组或像素流水线。
两个原时钟仍有 PR1014 通用路由提示；本次真实 STA 的 setup／hold 均为 0 违例。

新位流 SHA256：`e8ddbbc64dc81cf61c3037039b54752bf3a21ecca155264bfe6db907f9354c86`。
综合网表已通过 19,511,019 个系统时钟／21 帧／2,741,760 个有效像素对照，
覆盖原六帧游戏场景，以及动态频谱、运算中目标变化、峰值衰减、八帧曲线渐暗和页面切换。
全曲综合网表另通过 364 次连续布局更新；错误为 0，已知原厂 RAM 仿真警告按原有精确行号规则检查。

本轮独立交付位流：
[neo_guitar_touch_game_p1_display_opt.fs](../build/releases/touch_game/neo_guitar_touch_game_p1_display_opt.fs)。
[独立验证记录](../build/releases/touch_game/p1_display_opt/verification.json) 及该目录内的源码快照 ZIP、
综合网表、综合／P&R／STA、RTL 和网表仿真日志共同绑定本次构建；主工程 `verification.json` 保存同一份发布记录。
本轮数字交付门槛及三项余量目标已满足。归档时下板反馈尚待采集；随后用户反馈当前版本好像没有问题，并授权本地保存，记录见下文。

本轮未执行硬件烧录、定量声学、长时间稳定性或有声演奏的全链门级仿真。
声音由 8192 样本 RTL 对照及原 RTL／ROM 保护认证；整机网表音频范围是静音 PT8211／I²S 引脚。
触控和判定语义由九项 RTL 回归覆盖；网表显示测试采用受控显示快照，未模拟全部实物手势。

## 可重复构建与证据

`tools/prepare_display_game_p1_build.py` 创建新的 `build/` 下独立源码／ROM／约束快照，
保留所有源哈希及受保护用户文件哈希。`tools/start_display_game_p1_build.ps1` 记录 PID、
阶段、日志及开始时间；再次启动前检查已有进程，禁止覆盖同阶段日志。
原 IDE `impl` 和旧发布位流不作为新证据，也不被构建覆盖。

完整综合 PID=23116，真正 P&R PID=22640，日志为 `attempt2/synthesis.log` 和 `attempt2/route.log`。
首次 Tcl `run pnr` 在新进程内意外重启综合，已于布局前停止；显式 `-type vg` 不被该安装支持，
最终按扩展名自动导入已完成网表，只执行了一次完整 P&R。前置失败／停止日志及脚本一并保留，
完整综合认证使用本次 `synthesis.log`，不使用被停止重试覆盖的内部综合日志。
网表仿真 PID=28080，完整 21 帧于 18:30:05 结束，364 次布局检查于 18:30:17 结束。
因会话用量限制中断后，恢复时确认原进程已结束且新日志／证据为 PASS，直接复用这些结果，未重跑回归或 P&R。

```powershell
./tools/run_display_game_p1_checks.ps1
./tools/run_touch_game_checks.ps1
E:/anaconda3/python.exe tools/prepare_display_game_p1_build.py build/display_game_p1/new_run
./tools/start_display_game_p1_build.ps1 -RunDir build/display_game_p1/new_run -Stage synthesis
# 检查新综合报告和进程结束后，再启动一次 route：
./tools/start_display_game_p1_build.ps1 -RunDir build/display_game_p1/new_run -Stage route
$project = 'build/display_game_p1/new_run/workspace/gowin/neo_guitar_touch_game'
./gowin/neo_guitar_touch_game/run_gate_check.ps1 -P1 -ImplementationDir $project -GateDir sim/temp/display_game_p1_gate
E:/anaconda3/python.exe gowin/neo_guitar_touch_game/check_result.py --p1 --implementation-dir $project --gate-dir sim/temp/display_game_p1_gate --output build/display_game_p1/new_run/verification.json
```

沿用原 CST／SDC、器件 B、Place=4／Route=2／Clock Route Order=1 和 hold 修复。
默认 `ALLOW_AUTOPLAY_PREVIEW=1`、`ENABLE_MISS_CUE=1`。不改接线、采样率、模态／谐波／FFT 点数或音效参数。
本轮不 push、merge 或烧录；下板反馈与定量声学／长期稳定性测量仍需实测。

## 用户反馈与下板检查清单

2026-10-15，用户反馈：“现在的版本好像没什么问题，可以先提交保存。还有可以优化的空间吗？”
以当前 P1 版本作为后续实验基线，保存该反馈；实现仍为 `e169d93`，完整交付提交为 `c36689c`。
现场实际烧录文件哈希未另行采集，未新增定量声学或长时间稳定性数据。
已归档的数字证据、位流和源码快照保持原样，当前反馈单独写入主工程 `hardware_acceptance.json`。
以下清单保留供后续复测使用：

1. 对新独立位流执行 `Get-FileHash -Algorithm SHA256`，与交付记录一致后在 Gowin Programmer
   选择原器件 B。沿用接线，确认 J17 1–2 可靠连接；记录实际烧录文件哈希。
2. 开机检查触控四角、点击／拖动取消与双击返回。进入演奏模式，逐弦检查渐变条、
   150×150 莉萨如渐暗和环形真实频谱；三音色、和声／合唱／延音／混响、松品转空弦续音均检查。
3. 训练配置试听完整《茉莉花》，再真人拨弦检查四轨全宽舞台、x=96 判定线、顶部计分、
   正确／错误／Miss 反馈、尾迹、结算和重玩。延音开启时双击退出，检查释放及混响尾声。
4. 同时检查 PT8211 和标准 I²S 输出，随后连续演奏／游戏观察显示与声音稳定性。
   记录持续时间、接收端和异常；此轮数字验证不替代声学测量、接线接触或长时间实测。

当前 P1 已获用户无已知问题的初步反馈；进一步优化和后续功能按阶段另行实施。

## 后续优化空间（尚未实施）

完整实现尚余 CLS 2009/29952（6.71%）、BSRAM 23/118、DSP 2.5/118；寄存器余量较大。
DSP 仍接近上限，后续音频扩展需复用现有运算；不通过减少既有模态、谐波、FFT 点数或音效换资源。

1. **优先频带模块 `guitar_radial_bands`。** 本次关键路径为工作数组选择 → 对数量化 → 差值／衰减 →
   `pending_targets`，25 级逻辑、slack 2.983 ns。该模块综合为 967 寄存器、1580 LUT、77 ALU。
   可评估 `32×19 bit` 工作数组的 BSRAM 映射以及量化路径的分阶段计算，减少宽选择器或组合深度。
   必须验证同频带连续 bin 的读改写冲突、末 bin／frame_done、AGC 舍入和目标发布边界；不能让目标晚一拍导致显示跨帧变化。
2. **其次柱状态存储。** 当前 64 组柱高／峰值共 640 bit 仍为寄存器数组。
   可评估 RAM 和读取前取，减少 FF、动态选择器及写使能译码；必须保持六时钟像素节奏，
   同步读延迟、RGB／mask／坐标对齐及消隐更新期限均需逐值验证。已完成的 64 拍算术复用不重复实施。
3. **游戏布局缓存作为次级面积候选。** 当前布局模块约 746 寄存器、407 LUT，收益规模小于前两项。
   若继续改 RAM，必须保留每轨八块的像素判断吞吐量和整帧一致性，不能简单串行扫描所有块。

以上仅为基于当前源码、综合模块报告和实际 STA 的候选，不是已测得收益。
建议保持已反馈正常的 P1 版本不动，另开小实验，先局部等价与综合，再按收益决定完整 P&R。
本次反馈保存只更新文档，没有修改 RTL、重跑回归或启动新的优化构建。
