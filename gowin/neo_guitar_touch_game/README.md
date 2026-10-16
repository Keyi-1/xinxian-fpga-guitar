# 触控四轨游戏：neo_guitar_touch_game

**P2 静态多曲目集成（2026-10-16）：** 原工程综合、完整 P&R/STA 和所需回归已通过，等待本次下板确认。
原工程位流：[impl/pnr/neo_guitar_touch_game.fs](impl/pnr/neo_guitar_touch_game.fs)。
发布副本：[neo_guitar_touch_game_p2_static_songs.fs](../../build/releases/touch_game/neo_guitar_touch_game_p2_static_songs.fs)，
SHA256 `8d78cf9005fadfa9aa863adf4e9c17fc494521c68b828ddce6269b8091d87292`。
前四行触控选曲、帧级显示和实际三种推荐音色已连接，原音色按键与音效保留。
完整实现：Logic **51513**、Register **23030**、
CLS **28455/29952（95.002%）**、BSRAM **99**、DSP **115.5**；
系统／音频 Fmax **55.880／15.042 MHz**。
setup／hold、未布通、latch 和已测 deadline 均为 0。
P2 符合实际 50 MHz／12.288 MHz 运行与合法资源门槛；CLS 95.002% 超过 95% 余量目标（还需至少减少 1 CLS）。不宣称所有余量目标仍达标。
[本次验证记录](p2_integration_verification.json)；[集成、验证范围和下板步骤](../../docs/P2_STATIC_SONG_INTEGRATION.md)。
《情歌》为 60 BPM 前奏和弦慢练循环，Seven Nation Army 为升八度短 riff 循环；完整原曲伴奏尚未转录。
P1 历史归档保持原样，本次没有推送或代理烧录。

**已验收的 P1 发布基线（2026-10-15）：** 已验证的实现和记录已推送至 `origin/master`，
将 64 根频谱柱高／峰值改为消隐期 64 拍串行复用，保持原三音色、音效、画面及游戏操作。
完整 P&R：Logic **50159**，Register **22405**，CLS **27943/29952（93.29%）**，BSRAM **95**，DSP **115.5**；
系统／音频 Fmax **58.765／14.442 MHz**，运行时钟仍为 50／12.288 MHz。
未布通、latch、setup／hold 和已检查运算 deadline 均为 0，三项余量目标均达到。

本轮位流：[neo_guitar_touch_game_p1_display_opt.fs](../../build/releases/touch_game/neo_guitar_touch_game_p1_display_opt.fs)，
SHA256 `e8ddbbc64dc81cf61c3037039b54752bf3a21ecca155264bfe6db907f9354c86`。
九项 RTL、五项分弦 Python、512 组柱状态／1,108,992 像素、15 帧真实 FFT 集成／1,958,400 像素、
21 帧整机网表／2,741,760 像素及 364 次连续布局通过；音频 8192 样本与冻结基线一致，延音退出仍为 1452 样本。
[实现、完整资源对比与下板步骤](../../docs/DISPLAY_GAME_P1_RESOURCE_OPT.md)，
[本轮验证记录](verification.json)。用户反馈“现在的版本好像没什么问题”，之后授权本地合入 master 并推送 GitHub。
现场位流哈希未另行采集，未由代理烧录硬件；历史实物反馈范围见 [hardware_acceptance.json](hardware_acceptance.json)。
该次 P1 使用独立快照构建，原 IDE 网表／位流和原全宽舞台归档均保留。
用户现要求以后改为直接使用本 `.gprj` 及其原 `impl` 目录构建，流程见下文。
后续频带小实验收益不足，已停止并保留在 `experiment/radial-bands-resource-opt`，未合入本工程。

**直接使用现成位流：** 文首原工程 P2 `.fs` 和同哈希发布副本均可在 Programmer 直接加载，无需重新综合 `.gprj`。P1 归档继续保留。
在 Gowin Programmer 中扫描原 `GW5AT-60B`，双击设备的 Operation，
选择 `SRAM Mode`／`SRAM Program`，在 `File name` 中选取该 `.fs`，保存后执行 Program/Configure。
这是上电期间的临时配置；掉电保存需使用板上适用的 Flash 流程，不在此处修改 Flash 设置。
菜单步骤参考 [Gowin Programmer 官方指南](https://cdn.gowinsemi.com.cn/SUG502E.pdf)。

以下全宽舞台数据是已验收的历史基线，和本轮独立 P1 产物分别留存。

已验收的全宽舞台发布源自分支 `experiment/touch-rhythm-game`，基于已验收的双输出基线 `655458f`。主工程使用
`neo_guitar_touch_game.gprj` / `neo_guitar_touch_game_top`，器件为 Mega 60K
`GW5AT-LV60PG484AC1/I0`，Device B。此工程作为本次 master 发布入口，原双音频输出工程保留作历史基线。

**用户反馈与发布：** 2026-10-15 用户先确认 `a13fd79` 对应修复版无已知问题，随后认可当前全宽舞台效果并授权推送、合入 master。现场烧录文件的哈希未单独记录；详见 [hardware_acceptance.json](hardware_acceptance.json)。

**已验收全宽舞台基线：** 计分移到顶部，四轨中心 y=85／133／181／229，保留 x=96 判定线、渐变尾迹及实际判定反馈。仍是无需按品的游戏；4×9 矩阵和后来添加的折线动效未加入。曲谱同时更新为避同弦冲突、相邻音优先换弦的离线分配。本次用户反馈单独记录，详见 [实现和验证说明](../../docs/FULL_WIDTH_GAME_STAGE.md)。

全宽舞台基线位流：[neo_guitar_touch_game_full_width.fs](T:/Documents/AMD/xinxian-fpga-guitar/build/releases/touch_game/neo_guitar_touch_game_full_width.fs)，
SHA256 `9c161ac673cd1c081831075f4f84d4ff2067f6a20797119b9a65d9623b770883`。
九项 RTL 回归、六帧综合网表显示（783,360 像素）、364 次连续布局及完整 P&R／STA 通过；未布通、setup、hold 均为 0。
Logic 58178，Register 22239，CLS 29842/29952（99.63%），BSRAM 95，DSP 115.5；系统／音频 Fmax 54.636／13.441 MHz。
源代码为 `246b146`＋`98ba437`；原演奏音频 8192 样本仍与 master 一致，所有三音色及音效保留。
该基线面积余量很小，本轮 P1 优化结果见文首。全宽舞台已获用户效果认可；没有新增定量音频或长期稳定性测量。下面旧资源和位流按版本留存。

以上历史验证记录对应各自归档发布。IDE 重建的 `impl` 网表／位流不能由旧门级日志认证。
P2 使用单独的 `p2_integration_verification.json`、`tools/run_game_p2_gate.ps1` 和 `tools/check_game_p2_result.py`，
P1 的 `verification.json` 与 `check_result.py` 保留历史用途。

## 原生 J6 六针直连接线

用户已确认 J6 电压符合要求，当前 CST 改为 **J6-4 / T16（Bank 2，3.3 V IO）** 接屏幕触控 INT。
此前使用 J9-10/U21 是因为当时这一路 IO 电压待确认，并非 J6 不能使用。
LCD 的 40 针显示排线、J13 品位矩阵、J8 ADC、PT8211 和标准 I²S 接线保持原样；
J17 继续牢固短接 1、2 脚。

| 屏幕独立触控六针 | 当前原型接线 | FPGA 管脚 / Bank |
| --- | --- | --- |
| 1 CTP-RST | 底板 J6-1 | T15 / Bank 6，3.3 V |
| 2 CTP-VCC | 底板 J6-2，+3V3 | 电源 |
| 3 CTP-GND | 底板 J6-3 | 共地 |
| 4 CTP-INT | 底板 J6-4 | T16 / Bank 2，3.3 V |
| 5 CTP-SDA | 底板 J6-5 | U16 / Bank 6，3.3 V |
| 6 CTP-SCL | 底板 J6-6 | W16 / Bank 7，3.3 V |

**当前配置支持屏幕独立六针电容触控接口直接接入 J6，不再需要 INT 转接线。**
如先前曾把 INT 接到 J9-10，改用此版本时移除该转接线，避免把两个 FPGA GPIO 相连。
J6 是 0.5 mm 六针接口，需核对 FPC 接触面方向和实物 1 脚标记；不能用排线朝向猜针序。
底板 R192/R193 已给 SDA/SCL 提供 5.1 kΩ 到 3.3 V 的上拉；RTL 为开漏 0/Z。

J6-2 的供电和 J6-4 所属的 `VCCIO1_2` 是不同的网络；此原生配置按用户确认的兼容电压使用 3.3 V IO。
LCD J5 的 37～40 脚与触控控制 GPIO 在底板有共用网络：电容屏版本应确认这些脚未连接
电阻触控的 X/Y 电极。屏幕提供的通用 40 针图中有电阻触控定义，不能据此把它们再接到电容控制器。

来源：NEO Dock 31005 原理图第 8、13 页，Mega 60K 核心板原理图第 2 页。

## 当前操作

- 开机显示“模式选择”；手指抬起时确认点击。
- “演奏模式”保留已验收的左侧四弦渐变、150×150 莉萨如与环形频谱；三键音色/音效、松品续音和曲线渐暗保留。
- “游戏模式”进入五个曲目槽。前四项为《茉莉花》、原创慢练、SEVEN NATION ARMY 短 riff 和“情歌前奏”；第五项诊断槽不可启动。
- 选择曲目后，“开始”和“试听”都会加载该曲推荐音色：茉莉花用钢琴、慢练和情歌前奏用第二音色、riff 用哇音；原音色按键仍可手动切换。
- 曲目准备页的“开始”进入 2 秒倒计时，然后按移动色块拨对应弦；“试听”是显式自动演奏预览，不能取得游戏得分。
- 四轨从上到下对应第一～第四弦：蓝、绿、橙、红。色块从右向左移动，**中心到达 x=96 的竖线时拨弦**。
- 演奏模式、倒计时或游戏中，同一区域短按两次退出至主页：每次按住不超过 180 ms，
  两次抬起间隔 80～350 ms，横、纵方向各不超过 32 像素。拖动、多点触摸或跟踪 ID 改变会取消点击。
- 曲目结束后显示分数、最高连击、命中和漏音；可重玩、选曲或返回主页。
- 触控未接通或持续故障超过 2 秒时自动转为演奏模式，右下提示“触控未连接”。触控恢复后双击返回主页。

GT911 驱动使用约 100 kHz I²C，读取已有产品 ID、固件和坐标范围，
先按 0x5D 复位选择地址，失败后复位重试 0x14；正常运行轮询触点。
每份有效触摸报告在清零 `0x814E` 并收到 ACK 后才提交，不覆盖屏幕配置表。
NAK、时钟拉伸超时和总线异常均有退出路径。SDA 卡低时发九个恢复时钟及 STOP。
参考 [Goodix 官方驱动](https://github.com/goodix/gt9xx_driver_android/blob/master/gt9xx.c) 和
[GT911 编程指南](https://community.nxp.com/pwmxy87654/attachments/pwmxy87654/imx-processors/177678/1/GT911%20Programming%20Guide_v0.1%20%281%29.pdf)。

坐标默认按 GT911 范围串行缩放到 480×272；范围为 272×480 时自动交换轴。
若实物方向不符，用顶层 `TOUCH_SWAP_AXES`（-1 自动、0 不换、1 交换）、
`TOUCH_MIRROR_X/Y` 调整，先验证四角点击再进入游戏。

## 曲谱和音频行为

P2 使用静态多曲目录与 64 事件有界窗口，时间／得分为 32 位，计数为 16 位；曲谱容量为 2048 事件。
新增慢练内容均按 60 BPM 编排；范围和生成来源见 [P2 集成说明](../../docs/P2_STATIC_SONG_INTEGRATION.md)。

保留的《茉莉花》为常见单旋律编配：96 BPM、67 个音符、33.75 秒，27 小节 2/4，移调到 D3～G4，
无歌词、伴奏或录音回放。不是对某份完整出版曲谱的逐音转录。
当前由离线分弦器分配轨号，蓝／绿／橙／红仍对应第 1～4 弦；同一个音高可分到不同弦，不再使用旧版按音高固定分组。保持原音高／时刻／时长，避免同时或重叠保持的音落在同一弦，临近音优先换弦。音域候选来自 E4／B3／G3／D3 空弦至八品，当前游戏只需拨弦，不检查品位。
节拍已按[常见单旋律谱](https://www.ysmen.org.tw/upload/info_center/f202111031038110.pdf#page=28)核对，保留四处句尾休止及后段低音。
原 53 音符／27.5 秒版本是早期手工教学短谱，其首音时值与停顿不用于本次修正版本。
`scores/jasmine.csv` 是可读谱，JSON 为元数据，BIN 为 16 字节事件记录，
`mem/jasmine_game.mem` 是时刻、时长、DDS 增量和轨号组成的 ROM，**不是 PCM**。
ROM 的时刻和时长由有理数节拍直接换算为 48 kHz 样本；CSV／v1 BIN 的毫秒字段经过取整，可能与 ROM 相差最多约 0.5 ms。

游戏音高直接取谱面 DDS；按品不会改变它。每根弦在未消耗音符中选择时间误差最小的一项：

| 判定 | 绝对时间误差 | 得分 |
| --- | --- | --- |
| Perfect | ≤35 ms | 100 |
| Good | >35 且 ≤90 ms | 70 |
| Bad | >90 且 ≤150 ms | 25，断连击 |
| Wrong | 本轨无 ±150 ms 内音符 | 0，断连击 |
| Miss | 超过音符时刻 150 ms 仍未命中 | 0，断连击 |

Wrong 播本轨未来一秒内最近音符，否则播该弦空弦音；不消耗、不推进曲谱。
正确拨弦立即发声，不等待色块；四弦同拨独立判定，同一事件只消费一次。
游戏时长触发正常 note_off；退出模式另有不受延音控制的约 30 ms 快速释放，
待声部结束才确认换模式，保留原混响尾音与音效设置，功放不中断。

演奏和游戏共享**一个**原有四声部音源及音效实例。钢琴 8 主体模态、实时击弦模型、
明亮/哇音各最多 32 分量、自动五度和声、合唱、混响全部保留；没有为了游戏简化音色。
当前实物演奏入口的固定力度 2 仍保留；四档力度校准是另一个待实施项目。

判定由 48 kHz 音频样本时钟驱动，P2 扫描有界窗口；最坏每轮 65 次读取、131 个参考时钟，
与原音源 233/256 的运算并行。显示每帧通过完整快照同步，消隐期复用常量除法器计算
四轨各最多 8 个块的位置和尾部长度；像素阶段只做并行区间比较和固定字模读取，没有帧缓冲。
坐标计算只在帧开始后的消隐期进行，直接更新一份坐标缓存，完成后提交有效掩码；统计数据复用 CDC 的整帧目的快照，
整首曲谱的计算时间检查低于 38200 个系统时钟，早于有效视频开始，不需要再复制一整份坐标寄存器。
已消费状态只保存实际 67 个事件，发布快照时再零扩展到 128 位。

## 2026-10-14 实物反馈修复

- 旧位流第二次更新游戏布局时，Gowin 网表中的动态数组计数未正确清零，导致块索引错位、最终提示丢失。已换成四个显式计数器；相同输入的失败／修复网表对照已复现并确认。
- 增加整首曲谱连续帧的综合后布局对照，覆盖倒计时、右向左运动、重复清零、尾长和消费状态。此前网表测试仅覆盖首页，不能发现这项问题。
- 删除 UI 的每 32 像素背景闪点动画，保留卡片渐变和呼吸效果；这层点阵与用户报告的矩阵闪点吻合，其他实物闪点仍需下板确认。
- Miss 增加约 30 ms／750 Hz 的低幅提示音，混在音效之后，两路音频共用。它不占用吉他声部、不播放漏掉的音符，也不读取录音。
- 顶层 `ALLOW_AUTOPLAY_PREVIEW` 和 `ENABLE_MISS_CUE` 默认均为 1，表示训练配置；保守比赛配置均置 0 并重新完整构建。严格模式拒绝试听命令并不实例化 Miss 音频模块，真人拨弦游戏保留。
- 合规判断和现场展示边界见 [TOUCH_GAME_COMPLIANCE_NOTES.md](T:/Documents/AMD/xinxian-fpga-guitar/docs/TOUCH_GAME_COMPLIANCE_NOTES.md)。

修复版训练位流已经通过完整 P&R、STA 和网表检查：
[neo_guitar_touch_game_j6_gamefix.fs](T:/Documents/AMD/xinxian-fpga-guitar/build/releases/touch_game/neo_guitar_touch_game_j6_gamefix.fs)。
SHA256：`db1e7578e676d4cdbd0de375c46f016e744386f7fd1cfc45d340205f99ce849a`。

| a13fd79 修复基线实现结果 | 数值 |
| --- | --- |
| Logic / Register | 57620 / 22432 |
| CLS | 29744 / 29952，约 99.31% |
| BSRAM / DSP | 95 / 115.5，与上一版相同 |
| 系统 Fmax（要求 50 MHz） | 52.511 MHz |
| 音频 Fmax（要求 12.288 MHz） | 12.596 MHz |
| setup / hold / 未布通网络 | 0 / 0 / 0 |
| 综合后移动布局 | 364 连续帧与 RTL 一致 |
| 综合后首页 | 2,765,403 系统时钟、391,680 像素，与 RTL 一致 |

下面保留的旧资源及位流哈希属于 `2eef7f9` 快照。本次修复已于 2026-10-15 获得用户实物验收反馈；没有新增定量声学或长期稳定性测量。CLK 通用路由提示仍需结合真实 STA 审查。后续添加模块前仍应进行资源与时序优化，尤其是 CLS 与音频时序余量。
固定文字索引另用同步 ROM 替代组合 case 树；连击/命中等计数共用一套移位加法 BCD 转换，
不使用逐像素除法或新增乘法器。曲谱时间寄存器按 24 位实际范围保存，快照输出时才扩展为 32 位。
曲谱上限由生成脚本限制为 120 项以满足采样预算；更长曲目需后续窗口缓存设计，不能直接扩大参数。

## 构建、验证与实物验收

**以后默认使用原 IDE 工程构建，不另建构建工程：**

1. 打开本目录 `neo_guitar_touch_game.gprj`，确认顶层、Device B 和现有工程设置。
2. 在 Gowin IDE 的 Process 中运行 Synthesize，再运行 Place & Route。
3. 综合结果位于 `impl/gwsynthesis/`，布线、STA 报告和最终位流位于 `impl/pnr/`；
   原工程的最终位流为 `impl/pnr/neo_guitar_touch_game.fs`。
4. 对这一次实际生成的产物完成必需回归、综合网表和 STA 检查后，再复制到
   `build/releases/touch_game/` 下独立命名归档，绑定本次源码及产物哈希。

原有 P1 发布文件及其证据保留，不用旧日志认证后来 IDE 重建的产物。
仅修改说明或已存在有效构建结果时，不为刷新 IDE 状态重跑综合布局布线。

以下命令保留用于复现**历史独立 P1 构建**，不是后续默认操作流程：

```powershell
# P1 使用新的独立目录，先综合，确认收益后再布局布线；日志和 PID 写入 manifest。
./tools/run_display_game_p1_checks.ps1
./tools/run_touch_game_checks.ps1
E:/anaconda3/python.exe tools/prepare_display_game_p1_build.py build/display_game_p1/new_run
./tools/start_display_game_p1_build.ps1 -RunDir build/display_game_p1/new_run -Stage synthesis
# 等上述进程结束并检查新综合报告后：
./tools/start_display_game_p1_build.ps1 -RunDir build/display_game_p1/new_run -Stage route
$project = 'build/display_game_p1/new_run/workspace/gowin/neo_guitar_touch_game'
./gowin/neo_guitar_touch_game/run_gate_check.ps1 -P1 -ImplementationDir $project -GateDir sim/temp/display_game_p1_gate
E:/anaconda3/python.exe gowin/neo_guitar_touch_game/check_result.py --p1 --implementation-dir $project --gate-dir sim/temp/display_game_p1_gate --output build/display_game_p1/new_run/verification.json
```

历史 P1 固定 Place=4、Route=2、Clock Route Order=1、hold 修复及 CPU/SSPI/I2C GPIO 复用。
P2 当前使用用户单独授权的 Route=1、Clock Route Order=0、Route Maxfan=32，Place=4、hold 修复和 GPIO 复用保持。
本轮独立构建输出位于 `build/display_game_p1/<run>/workspace/gowin/neo_guitar_touch_game/impl/pnr/`；
下板对象以文首独立归档和 SHA256 为准。主工程仍保留原 IDE 入口。
不能用综合成功代替布线/时序合格；
P2 当前认证结果与资源见 `p2_integration_verification.json`；`verification.json` 保存 P1 历史结果。
RTL 检查包括 I²C 故障恢复、GT911 设备模型、坐标/手势/页面、拨弦判定、
异步命令和快照、全曲滑块位置，以及完整音频链与 master `655458f` 的数字对照。
五幅界面预览来自 RTL 像素输出，保存在本地 `build/touch_game/previews/`；没有用绘图程序代替 RTL。

## 历史：2026-10-14 首次 J6 原型

以下资源、网表范围和位流对应修复前的 `2eef7f9`，已被后续修复及全宽舞台替代。

当时 RTL 检查通过；完整演奏链 8192 个样本、2,097,153 个参考时钟与已验收 master 完全一致，
覆盖三音色和全部音效，延音开启时退出需 1452 样本（30.25 ms）。综合网表另检查了
2,765,403 个系统时钟、391,680 个 LCD 像素，初始化主页、触控复位 GPIO、静音两路音频引脚均与完整 RTL 一致。
这项网表检查没有模拟实物触控或完整游戏的网表演奏，游戏判定和模式切换由上述 RTL 回归覆盖。
J6/T16 初次路由因高利用率出现 PR0004（234 条未布通网络）；随后移除冗余坐标缓存和未用状态位，
综合少用 1047 个寄存器。软件回归、五幅界面逐像素对照和新网表检查仍通过，音源及音效保持原样。

2026-10-14 J6/T16 直连版完整构建通过：无未布通网络，setup/hold 违例为 0/0。

| 项目 | 本次原型 |
| --- | --- |
| Logic | 57357 / 59904 |
| Register | 22339 / 60780 |
| CLS | 29648 / 29952 |
| BSRAM | 95 / 118 |
| DSP | 115.5 / 118，与原双输出工程相同 |
| 音频 Fmax，目标 12.288 MHz | 13.247 MHz |
| 显示 Fmax，目标 50 MHz | 50.010 MHz |

BSRAM 尚有余量，但 CLS 已占约 98.99%；继续添加逻辑前需要优化共享、寄存器位宽或缓冲结构，
不能仅按剩余 RAM 判断扩展空间。构建保留了固定时钟管脚，工具仍给出 PR1014 通用时钟路由提示；
当前实际布线的 STA 检查通过，后续任何实现变更仍需重新检查时序。
显示频率距离 50 MHz 目标仅约 0.02%，时序余量很小；当前为待实物验收的实验版，
先检查触控方向、操作和长期显示/演奏稳定性，再考虑合并到正式入口。

当时归档的直连版位流是 `build/releases/touch_game/neo_guitar_touch_game_j6.fs`。
SHA-256：`e5f923815c2dc8ef396ab291a757e8bcec7b99f0ee29a0c88192f28e885e0b83`。
此前 U21 转接版已另存为 `build/releases/touch_game/neo_guitar_touch_game_int_u21.fs`，
旧 SHA-256 为 `8fb51b95c4353f2832a616556e0e232db4441f4624f756e6ec69f1a83c299008`，用于历史留存。
以上 `j6` 与 `int_u21` 位流只作历史留存；位流及完整仿真日志是忽略的本地产物，
Git 提交保存源码、工程设置及 `verification.json`，新克隆需自行构建和验证。

下一步实物验收依次检查：J6 排线针序/接触面、GT911 四角/点击方向、菜单与双击返回、
试听完整旋律、四轨正确/错误拨弦、结束/重玩，以及延音开启时退出模式。
**此初版当时尚未经过用户实物验收；后续 a13fd79 修复版已获验收，全宽舞台的后续效果反馈见文首。** 蓝牙导入、完整五首曲目、多指 UI、长曲缓存和力度校准不在本次原型内。
