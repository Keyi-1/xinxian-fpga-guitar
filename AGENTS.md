# 本项目的用户工作流约定

## 默认分支与构建入口

- 用户要求日常工作默认回到 `master`，默认推送目标为 `origin/master`。
  另开实验分支仅在任务确有实验需求时进行；不要将已拒绝的实验集成到生产。
- 用户于 2026-10-15 明确要求：以后使用他平时打开的
  `gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj`，在原工程中综合、布局布线。
  优先使用 Gowin IDE 的 Synthesize、Place & Route 流程，不再把独立构建目录作为默认交付方式。
- 主工程顶层为 `neo_guitar_touch_game_top`，器件为
  `GW5AT-LV60PG484AC1/I0`、Device B，工具为 Gowin V1.9.12.03。
- 构建结果直接生成在该工程原有的 `impl/gwsynthesis/` 与 `impl/pnr/`。
  若当前工具只能命令行操作，也须使用同一原工程及现有配置，在原目录生成结果，说明实际执行方式；
  不静默创建源码副本或另一个工程来代替用户的 `.gprj`。
- 主工程的一次新构建会正常更新原 `impl` 下的生成产物，这是用户选定的工作流。
  构建前保留已有的已验证发布位流及证据，不手工伪造 IDE 完成状态，也不把别处产物直接覆盖进来冒充本次构建。
- 交付时首先指出原工程下可用的 `.fs` 和报告位置，再提供独立命名的发布归档、哈希与验证范围。
  发布归档仍可放在 `build/releases/`；归档不等于另建工程进行综合布局布线。
- 完成必需检查后不重复启动完整构建；恢复中断时先查现有进程和日志。

## 保留用户内容与版本边界

- Git 的暂存区与 FPGA 的综合／布局布线进度无关。向用户解释时使用清楚的表述。
- 保留以下两个用户文件的本地内容及暂存状态，不自动提交、撤销或覆盖：
  `gowin/neo_guitar_touch_game/impl/neo_guitar_touch_game_process_config.json`、
  `docs/MPU6050_POSTURE_TIMBRE_DESIGN_PLAN.md`。使用现有工程设置构建，不为方便运行重写该 JSON。
- 2026-10-16 用户对一次实际布线失败作出明确例外授权：仅将上述原工程 JSON 的 `Route_Maxfan`
  从 23 改为 32；其余字节和已暂存对象不变，不自动提交该用户文件。
  原工程重试与配置前后哈希在 `build/p2_integration/impl_a4_route32/`；Gowin 自动重综合改变了命名和拆分端口，
  已用 `tools/compare_synth_graph.py` 全量证明重建 VG 与已验证 A4 的原语、参数、全部引脚连接等价。
  两份原始 VG 和结构证明分别绑定；不要只用旧日志认证重建产物，不重复已完成的等价功能仿真。
- Route_Maxfan=32 的重试仍有一条未布通网络。2026-10-16 用户再单独授权仅把 `Clock_Route_Order`
  从 1 改为 0；其他配置与原暂存对象不变。当前运行记录在 `build/p2_integration/impl_a4_route32_clock0/`，
  该次直接使用现有网表，仅重做 P&R。先查进程和结果，不重复启动。
- 用户已拒绝继续频带模块的优化路线，原因是收益小且平衡树候选时序回退。
  不继续频带 RAM／选择器／流水线实验；历史实验和停止决定保留在远程分支
  `experiment/radial-bands-resource-opt`。
- 当前已验证 P1 归档为 `build/releases/touch_game/neo_guitar_touch_game_p1_display_opt.fs`，
  SHA256 为 `e8ddbbc64dc81cf61c3037039b54752bf3a21ecca155264bfe6db907f9354c86`。
  它来自此前独立构建，不能把其日志当作以后原 IDE 重建产物的认证。
- 不为说明工作流或刷新 IDE 状态重复综合布局布线。用户可以用 Gowin Programmer 直接选择已验证 `.fs`。
  未获用户明确授权，不替用户烧录硬件。

## P2 静态多曲目集成状态

- 用户已明确报告使用 P1.fs 完成下板确认。当前 P2 源码已连接触控选曲、帧级显示与推荐音色握手；
  生产顶层 `USE_P2=1`，旧默认兼容路径留作回归。P2 的最终网表、P&R/STA 正在验证，未认证新发布。
- 主工程仍是原 `.gprj` 和原 `impl`。当前实现源码清单在 `build/p2_integration/impl_a4/`，
  恢复时先查其进程、日志与位流状态，禁止重复启动完整 P&R。
- P2 采用 64 事件有界窗口、32 位时间/得分、16 位计数和静态多曲目录。
  曲谱使用显式 DPB16 切片；更改曲谱后同时生成并校验 `game_p2_bsram_init.vh`。
  自动推断的宽 ROM 曾在网表中把第二条 MIDI 59 读为 29，该构建已经停止，不用于发布。
  显式 ROM 的两个异步端口全部 2048 条 96 位记录已做 4096 次综合网表对照。
- `gw_sh open_project` 后调用 `set_option` 会写回工程 process_config。
  不得把单元顶层/输出名覆盖写进受保护设置；本次单元实验写回的两项已恢复为原字节和原暂存对象。
- 用户选择《情歌》吉他伴奏分解和弦版、第二音色、慢速。当前只有 60 BPM 四小节前奏和声练习循环，
  不是完整原曲伴奏；Seven Nation Army 也仅为升八度短 riff 慢练。
  菜单另保留茉莉花和原创慢练，第五行十分钟诊断曲禁用。
- 推荐音色在旧声释放/确认后真正加载，手动音色按键继续可用；原声部、钢琴模态、音效、FFT 和时钟保持。
- P2 独立验证使用 `p2_integration_verification.json`，P1 的 `verification.json` 和发布位流保留。
  当前状态与入口见 `docs/P2_STATIC_SONG_INTEGRATION.md`。完成新位流认证后等待用户下板反馈。
