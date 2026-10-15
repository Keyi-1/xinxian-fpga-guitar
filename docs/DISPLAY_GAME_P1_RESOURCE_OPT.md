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

综合、P&R、STA 及综合网表结果在完成后写入本文件与独立验证记录；
上述 RTL 检查本身不认证位流，也不表示余量目标已经达成。

## 可重复构建与证据

`tools/prepare_display_game_p1_build.py` 创建新的 `build/` 下独立源码／ROM／约束快照，
保留所有源哈希及受保护用户文件哈希。`tools/start_display_game_p1_build.ps1` 记录 PID、
阶段、日志及开始时间；再次启动前检查已有进程，禁止覆盖同阶段日志。
原 IDE `impl` 和旧发布位流不作为新证据，也不被构建覆盖。

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
