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
- 用户已拒绝继续频带模块的优化路线，原因是收益小且平衡树候选时序回退。
  不继续频带 RAM／选择器／流水线实验；历史实验和停止决定保留在远程分支
  `experiment/radial-bands-resource-opt`。
- 当前已验证 P1 归档为 `build/releases/touch_game/neo_guitar_touch_game_p1_display_opt.fs`，
  SHA256 为 `e8ddbbc64dc81cf61c3037039b54752bf3a21ecca155264bfe6db907f9354c86`。
  它来自此前独立构建，不能把其日志当作以后原 IDE 重建产物的认证。
- 不为说明工作流或刷新 IDE 状态重复综合布局布线。用户可以用 Gowin Programmer 直接选择已验证 `.fs`。
  未获用户明确授权，不替用户烧录硬件。
