# 给下一对话的交接提示词

日期：2026-10-15。下面正文可以整体复制给新对话。本文件记录已核对的状态，不表示后续各阶段已经实现。

---

请继续 `T:\Documents\AMD\xinxian-fpga-guitar` 的 Mega 60K FPGA 吉他工程。

优先状态补充：此前交接提示词写好后，完成了实物反馈修复 `a13fd79`，又按用户审核实现了全宽舞台 `246b146` 及显示缓冲／计分复用 `98ba437`。请从包含这些提交的当前状态继续，下文 `2eef7f9` 只是历史快照，不要回退或重复实施已完成工作。

修复内容：游戏布局的动态数组计数在 Gowin 网表中第二帧未正确清零，现改为四个显式计数器；新增整首 364 帧综合后布局对照通过。已删除每 32 像素闪现的 UI 背景点阵；《茉莉花》按常见 2/4 单旋律修正为 67 音符、33.75 s，保留句尾休止和后段低音；增加不占音乐声部的 30 ms／750 Hz Miss 提示。

修复基线 a13fd79 的资源：Logic 57620、Register 22432、CLS 29744/29952（约 99.31%）、BSRAM 95/118、DSP 115.5/118。系统 Fmax 52.511 MHz，音频 Fmax 12.596 MHz，要求仍为 50／12.288 MHz，setup/hold=0/0。以下最新全宽舞台数据优先于此历史数值。

已归档参考位流是 `T:\Documents\AMD\xinxian-fpga-guitar\build\releases\touch_game\neo_guitar_touch_game_j6_gamefix.fs`，SHA256 `db1e7578e676d4cdbd0de375c46f016e744386f7fd1cfc45d340205f99ce849a`。2026-10-15 用户确认当前修复版无已知问题、可提交，实物验收已记录；不需要重复本轮修复。现场烧录文件哈希未单独记录；没有新增定量声学或长期稳定性测量。旧 J6 位流未覆盖。

此前本地 IDE 曾重新生成与归档不同的产物，旧网表日志不能认证它们。本次全宽舞台已重新完成当前源码、综合网表、仿真日志、P&R／STA 和新位流的哈希绑定；旧归档位流继续保留，不能混用两代验证记录。

2026-10-15 最新授权：用户已选择最初的“全宽舞台”，要求接入板上工程，暂不加入 4×9 矩阵及后来新增的折线动效。本次已实现四轨全宽 RTL，并把共用的避冲突／相邻换弦规则接入电脑端曲谱生成器；四轨继续无需按品。详情见 `docs/FULL_WIDTH_GAME_STAGE.md`，以其发布记录和当前 `verification.json` 为准。不要把旧的“尚未审核、只能画预览”边界沿用到已获授权的全宽舞台，也不要把矩阵／品位判定误记为已实现。

新显示为四级像素流水线，24 像素标题复用原字库空余槽；进度、计分、局部辉光、尾迹和短暂判定反馈已接入。快照原保留位 245:238 增加逐弦 2 bit 判定代号，连续 Perfect 可以重新触发反馈。三音色／音效及原演奏模式保持，8192 样本基线对照仍通过。新版《茉莉花》仅弦号改变，全部原时间／音高位一致；CSV/BIN/ROM 结构未变，每个事件对应品位另记 JSON，尚未接矩阵玩法。

最新可烧录文件：`build/releases/touch_game/neo_guitar_touch_game_full_width.fs`，SHA256 `9c161ac673cd1c081831075f4f84d4ff2067f6a20797119b9a65d9623b770883`。当前源码构建对应 Logic 58178、Register 22239、CLS 29842/29952（99.63%）、BSRAM 95、DSP 115.5；系统／音频 Fmax 54.636／13.441 MHz，未布通／setup／hold／latch 均为 0。九项 RTL、六帧整机网表 783,360 像素和 364 次连续布局均通过。全宽舞台**尚待实物验收**，不得沿用 a13fd79 的下板结论。P1 余量目标仍未完成。

已实施的复用不要重做：布局和 UI 共享 CDC 目的端帧快照，删掉布局里的两份复制；score 与四个计数共用一个 20 bit double-dabble，105 时钟一轮。CDC 握手仍完整，快照在 update 之外保持；所有转换在消隐期稳定。

本机还保留了一项**未并入生产 RTL**的频谱复用备选实验，位于 `build/touch_game/full_width_stage/area_probe/`，生成脚本为上一级 `probe_prepare.py`。它用目标移位寄存器及相邻插值轮流计算 64 根柱的平滑／峰值，在 64 时钟内完成，保留输入起始快照、边界、舍入及每四帧衰减相位。512 组目标／拨弦状态、全部柱高／峰值和 1,108,992 像素与原组件一致，包括计算期间 targets 改变；独立综合为 2809 LUT＋861 ALU、1476 寄存器，DSP 不变。这里只是组件实验，不是整机 P&R 证明；产物在 Git 忽略的本地目录。若后续采用，需先把源码／回归正式纳入分支，调整原资产保持校验的明确例外，补真实消隐边界、完整网表及 P&R／STA，不能把这项实验说成本次发布已应用的优化。

训练默认顶层参数 `ALLOW_AUTOPLAY_PREVIEW=1`、`ENABLE_MISS_CUE=1`。保守比赛配置两者均置 0，重新完整构建；真人拨弦游戏及演奏模式保留。规则解释见 `T:\Documents\AMD\xinxian-fpga-guitar\docs\TOUCH_GAME_COMPLIANCE_NOTES.md`。主游戏的无品位音高映射不等于预录 PCM，自动试听／计时提示与真人演奏合规展示区分；不要宣称训练位流已经做了全部比赛合规认证。

用户原有的 `gowin/neo_guitar_touch_game/impl/neo_guitar_touch_game_process_config.json` 改动已保留，MPU 原方案未改。请重新检查工作区；规划文档可能仍未跟踪，不要清理或覆盖。以下历史段落与本补充冲突时，以本补充和最新验证为准。

请先阅读：

1. `T:\Documents\AMD\xinxian-fpga-guitar\docs\FOLLOWUP_MODULE_IMPLEMENTATION_ROADMAP.md`
2. `T:\Documents\AMD\xinxian-fpga-guitar\gowin\neo_guitar_touch_game\README.md`
3. `T:\Documents\AMD\xinxian-fpga-guitar\gowin\neo_guitar_touch_game\verification.json`
4. `T:\Documents\AMD\xinxian-fpga-guitar\docs\MPU6050_POSTURE_TIMBRE_DESIGN_PLAN.md`
5. `T:\Documents\AMD\xinxian-fpga-guitar\docs\NEXT_VERSION_PERFORMANCE_TOUCH_GAME_PLAN.md`

这次交接的第一项任务是 **P0／P1：优化现有显示和游戏控制的缓冲、运算复用及流水线时序，同时保持当前音色、音效和视觉效果**。我授权你开展这一阶段的代码修改、仿真和完整构建；先不要把长曲、UART、蓝牙、MPU 或第四音色全部叠加到同一次修改。完成一个可验收的资源优化版本后报告结果，让我下板验收，再推进下一阶段。不要自行 push／merge。

请在实际工作开始时读取 Git 状态、日志和适用的 AGENTS.md，保护已有修改。交接时分支是 `experiment/touch-rhythm-game`，HEAD 为 `2eef7f9`，已验收 master 音频／显示基线是 `655458f32ba4f7e06403fd6c5c4da0b6f0dad8a7`。如果当前状态已经变化，应以实际状态为准，不能 reset 或回退到交接快照。MPU 方案在研究开始时是用户已有的未跟踪文件，请保留。

建议从包含 `2eef7f9` 的当前触控游戏版本创建 `experiment/display-game-resource-opt`；如果已有适用分支就沿用。不要从旧 master 开始遗漏触控／游戏功能。上一轮只研究并新增路线和本提示词，没有修改 RTL／CST／工程配置，也没有新建实施分支。

硬件与当前工程：

- FPGA：`GW5AT-LV60PG484AC1/I0`，Device B；Gowin V1.9.12.03。
- 项目：`T:\Documents\AMD\xinxian-fpga-guitar\gowin\neo_guitar_touch_game\neo_guitar_touch_game.gprj`。
- 480×272 并行 RGB LCD，像素时钟约 8.333 MHz，帧率约 53.745 Hz；原演奏界面是左 208×272 四弦彩条，右 272×272，中央 150×150 莉萨如及环形真实频谱。
- 保持 J17 的 1、2 脚可靠短接；先前音频插孔导致白屏的现象已确认是跳帽松动，问题已解决，不要重复诊断成音频冲突。
- GT911 独立六针接口可以原生直插 J6：RST=T15、INT=T16、SDA=U16、SCL=W16；J6-2 为 3.3 V，J6-3 为 GND。用户已确认 J6 IO 电压兼容。此前 U21 转接方案已替换，不要恢复它或再要求使用转接线。
- J6 电源与 INT 所属 Bank 电源是不同网络，电压确认来自用户，并非本代理独立测量。实际 FPC 针序／接触面仍按实物检查。
- 标准 I²S 保留 J9-11/P19 BCLK、J9-12/R19 WS、J9-9/T21 DATA 和共地；48 kHz、32 bit 时隙、16 bit 有效、3.072 MHz BCLK。板载 PT8211 同时输出相同最终左右 PCM。
- ADC 使用 J8，品位矩阵使用 J13；以当前 CST 为准，历史连接矩阵包含过时阶段，不要照抄旧按键或 GPIO 分配。

必须保留三音色主体、实时钢琴击弦模型、四声部、五度和声、合唱、延音／混响、松品变为空弦继续自然衰减、按键职责、功放状态、显示渐暗和当前画面。不要减少钢琴模态、明亮／哇音分量、FFT 点数，或降低采样率来腾资源。实物前端目前仍固定力度编码 2，四档力度标定尚未完成。

当前资源：Logic 57357/59904，Register 22339/60780，CLS 29648/29952（98.99%），BSRAM 95/118，DSP 115.5/118；系统 Fmax 50.010 MHz（要求 50 MHz），音频 Fmax 13.247 MHz（要求 12.288 MHz），setup/hold=0/0，无未布通网络。系统时序余量极小，不要因为还有 23 块 RAM 就直接叠加全部功能。

已完成的优化不要重复开发：`game_chart_layout.v` 已利用消隐期单坐标缓存，`game_note_controller.v` 已只保存实际事件数的消费位；合计少 1047 寄存器，实际 CLS 少 119。此前 J6 改针后曾有 PR0004，后来这一压缩版才布通；不要只换布局算法并宣称优化完成。

重点先研究 `rtl/display/guitar_radial_palette.v` 中 64 柱高度／峰值更新的串行复用、小 RAM 替代数组，以及频谱选择→颜色的流水线。当前最紧系统路径在 `u_display/u_palette`，另有 `u_display/u_bands`，请阅读实际 timing_paths。现有 64 柱更新展开大量重复算术，频带数组存在宽动态选择器；这是候选收益，未做综合证明。

若改 RAM：确认实际映射到 BSRAM、同步读延迟、同地址连续读改写转发和提交原子性。若串行更新：保留旧值、舍入、峰值衰减相位，在消隐内完成或统一提交，不能在有效显示期间出现半新半旧状态。RGB、mask、坐标和 DE 等流水线对齐，满足既有六系统时钟／像素节奏。不得通过放宽 SDC 或不成立的 false path 消掉问题。

规划优化目标是 CLS≤95%、系统报告 Fmax≥55 MHz、音频报告 Fmax≥13.5 MHz，实际运行时钟不变。目标未达到时请如实说明，继续评估可行的小范围改造；不牺牲原音色和画面追求数字。硬门槛是资源合法、无未布通网络、无 latch、真实 setup/hold 和 deadline 零违例。

验证基础：

- `T:\Documents\AMD\xinxian-fpga-guitar\tools\run_touch_game_checks.ps1`：当前七项 RTL bench PASS。
- `T:\Documents\AMD\xinxian-fpga-guitar\gowin\neo_guitar_touch_game\run_gate_check.ps1`：现有网表检查只覆盖首页等限定场景，不能当作完整游戏硬件验收。
- `T:\Documents\AMD\xinxian-fpga-guitar\gowin\neo_guitar_touch_game\check_result.py`：构建资源和时序结果检查。
- 当前原演奏音频与冻结 master 的 8192 样本、2,097,153 个参考时钟逐样本一致；退出释放 1452 样本，约 30.25 ms。
- 原有静态 UI 像素、整首茉莉花布局、CDC、触控恢复已有检查。P1 要补动态频谱、峰值衰减、渐暗和页面切换的严格对照，不只拍首页。
- 当前 J6 位流 `T:\Documents\AMD\xinxian-fpga-guitar\build\releases\touch_game\neo_guitar_touch_game_j6.fs`，SHA256 `e5f923815c2dc8ef396ab291a757e8bcec7b99f0ee29a0c88192f28e885e0b83`。
- 原演奏版本已有用户实物验收；截至交接，新增触控／游戏没有用户确认的实物验收。请尽早了解是否已完成，但继续可独立进行的资源分析，不要把已有仿真写成下板通过。

本机工具位置：Gowin `S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe`；ModelSim `S:\BaiduNetdiskDownload\modelsim\win64`；Python `E:\anaconda3\python.exe`。前次旧 Windows 工具在默认沙箱出现 DLL 初始化问题，经受控提升权限可运行；遇到实际错误再按工具权限处理，不要认为源码失败。不要后台重复启动多个完整 P&R。

未来路线已明确：优化 → 长曲多曲 → UART → MPU 监测／空闲自动切换 → 蓝牙 → 正式旧音隔离与琵琶；需要断电保存时在 UART 后另加安全 Flash／SD 阶段。

长曲不能只增大 ROM：目前每采样扫描整首谱，上限约 120 事件，24 bit 样本时间约 349.5 s，统计 8 bit 会回卷。计划采用有界活动窗口、全曲 32 bit 时间、扩宽／饱和统计、五槽共享曲库和原子提交，第一容量目标 2048 总事件／10 min 测试曲。先把静态长曲引擎做通，再接收导入。

电脑只整理 CSV／MIDI／MusicXML 并发送音高、时刻、时长、对应弦等事件；FPGA 保存曲谱、显示、判定拨弦并实时合成声音。导入提交后拔电脑仍能演奏；RAM 掉电失谱，断电保存单独实施。暂不做五线谱图片神经网络或 MP3 转谱。

UART 参考官方目录：
https://github.com/sipeed/TangMega-138K-example/tree/06e7d8b118d345915ab6f257b7c22226f81575cd/ddr_memory/ddr_memory_test_uart/src/uart

上次已读四个文件：通用 RTL 默认 50 MHz／115200，无需搬入 DDR 控制器；RX 判断引用第一级同步寄存器，需要适配；内部 ready 不能阻止实际 UART 连续到达，需 RX FIFO 和可靠分包 ACK；回显及周期字符串要从生产协议移除。不能复制 138K 引脚约束。

MPU 原方案可行：已购 GY-521；姿态稳定进入只选一次默认音色，原音色键手动优先，斜抱下按键选哇音不得被覆盖，竖抱待琵琶完成后才自动选择它。先独立读数据和分类，再空闲自动切音色；正式旧音隔离需要逐声部锁存和后混音音色相关处理隔离，不能只锁一个编号。共享 GT911 I²C 时需要 1／2 字节寄存器地址和仲裁，先确认模块供电和上拉。原姿态平方阈值需补符号／倒置边界实测。

请始终记录每阶段实测资源、整链周期、源码／网表／位流哈希和待实物项目。有疑问及时问我，但不要重复已完成的研究或把尚未验收的功能写成已完成。
