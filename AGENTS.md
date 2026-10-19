# Windows UART 桌面上传软件（2026-10-19）

- 用户另授权实现 Windows 曲谱上传软件；界面要求米白底、大幅淡吉他线稿覆盖页面底部、三步明确引导。当前分支接续实际 `experiment/p5-bluetooth-import`，不切回旧快照、不推进 BL616 刷写。
- 入口 `tools/run_windows_score_uploader.py`，源码 `tools/windows_score_uploader/`，文档 `docs/WINDOWS_SCORE_UPLOADER.md`。复用并保持原 XG3 Client/事件校验/分弦器字节不变；支持 xgscore、BIN+JSON、CSV，附修订节奏情歌 CRC c3451bbc。COMMIT 前持久写记录，最终结果不明确则保留并阻止重传。
- 便携包在 `build/releases/windows/FPGA_Guitar_Uploader_1.0.0.zip`，解压后运行 `FPGA_Guitar_Uploader/FPGA_Guitar_Uploader.exe`；无需安装 Python。验证与哈希见 `docs/windows_score_uploader_verification.json` 及 `build/windows_uploader/`。电脑模型/Qt 控件流程与冻结 EXE 检查不代表实物串口验收。
- 未打开实物 COM、未改 FPGA 源码/曲库/位流/约束/两个保护文件，不重复综合布线；未跟踪的 `tools/score_uploader_web.py`、`scores/user/` 为进入任务前已有文件，保持不动、不暂存。本批只本地提交，不 push/merge/烧录，交付后等用户实测反馈。

# P5 手机蓝牙导谱最新接续点（2026-10-19）

- 用户本轮明确授权在独立分支研究板载BL616，覆盖下文P4结束后等待决定；分支 `experiment/p5-bluetooth-import`，起点与实时远端master均为e0b2ff2。用户确认31005底板、首版同时兼容Android/iPhone，天线/调试器固件版本未知；比赛限制辅助MCU，不能保证合规或宣传FPGA独立实现BLE栈。
- 本轮生产RTL/ROM/曲谱/约束/原工程及两个保护文件/index保持，P4原FS/发布FS仍cfda7ead...。不重复P4构建/旧回归，不推送/合并/烧录/开实物COM/刷BL616。本轮仅本地提交，完成后等用户反馈。
- 可行性为“有硬件/SDK/二级启动研究路径，尚无实物BLE桥”。31005第8页ANT→L9 0Ω→U35 U.FL、C186/187 NC；实装未知。通用SDK bl616dk默认40MHz/控制台GPIO21/22，本板26MHz且UART28TX/27RX，不能直接刷通用例程或TangCore。官方二级应用0x40000需匹配调试器版本/启动条件/分区/恢复，不能据此宣称JTAG/UART/BLE并行。
- 交付代码：`firmware/p5_bridge`是互斥USB/BLE模式、epoch/新会话、有限分片/真实ACK转发的C核心，电脑GCC DLL已测试；不是RISC-V镜像。`mobile/p5-import`为双平台原生手机原型/共享协议，Android/iOS JS打包及原生配置检查通过，未生成APK/IPA或实物运行。最终ACK不明保留持久标记。单包工具 `tools/p5_score_package.py`，现行正式情歌包212事件/152秒/CRC c3451bbc（不使用旧P3节奏样例）。
- 证据与边界见 `docs/P5_BL616_BLUETOOTH_IMPORT.md` 和 `build/p5_bluetooth/verification.json`。C9项、手机PC模型16项、新增真实P3 RTL回放17帧分别验证；RTL位于 `p5_bridge_rtl_02`，01只因沙箱vlib启动失败未跑RTL。不要重复已通过且同源的RTL；目标SDK/GATT适配器、26MHz RF/启动/恢复仍待实现/确认。固件变更审批须在具体镜像和恢复包可审阅后，当前不请求或执行刷写。

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
  从 1 改为 0；其他配置与原暂存对象不变。第三次失败记录在 `build/p2_integration/impl_a4_route32_clock0/`，
  该次使用相同网表，仍剩一条未布通网络。失败证据保留。
- Clock_Route_Order=0 的重试仍有一条未布通网络。2026-10-16 用户第三次单独授权仅把 `Route_Option`
  从 "2" 改为 "1"；仍保留 Maxfan32、ClockOrder0 及所有其余字节和原暂存对象。
  该试验已失败（376 条未布通），证据在 `build/p2_integration/impl_a4_route32_clock0_algo1/`；
  已仅回退试验字段 Route_Option 到 "2"，当前为 Maxfan32、ClockOrder0、Route2。
  A5 控制器内部位宽/掩码等价优化的最终通过构建在 `build/p2_integration/impl_a5_bound_time/`。
  恢复先查已有进程、stdout 和 stderr；Tcl 异常也须标记结束，禁止重复构建。
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
  生产顶层 `USE_P2=1`，旧默认兼容路径留作回归。P2 最终网表、原工程 P&R/STA 及所需回归已通过；2026-10-16 用户反馈片段练习循环通过。
- 主工程仍是原 `.gprj` 和原 `impl`。当前 A5 实现源码清单在 `build/p2_integration/impl_a5_bound_time/`，
  此构建综合已完成；最终 P&R 在 `build/p2_integration/impl_a5_bound_time/`。认证在 `p2_integration_verification.json`，发布副本为 `build/releases/touch_game/neo_guitar_touch_game_p2_static_songs.fs`。无新改动不重复启动完整 P&R。
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
  当前状态与入口见 `docs/P2_STATIC_SONG_INTEGRATION.md`。片段位流已认证，用户已反馈片段循环通过；完整主旋律是下一批内容，不由旧证据认证。

## 完整主旋律输入准备（历史，已由下节用户简谱接续）

- 2026-10-16 用户选择《情歌》完整主旋律、第二音色、60 BPM；本批不继续整首分解和弦伴奏方向。
- 准备阶段尚未取得完整主旋律输入；之后用户已提供下节两页简谱，当前槽 3 已替换。历史前奏循环不能当作完整曲目。
- 已实现 `tools/import_p2_melody_midi.py`，仅转换用户提供的独立 MIDI 到新文件，不自动写生产曲库。
  十项测试及生产源码/ROM/约束/两个用户文件保持证据在 `build/p2_full_melody_prepare/20261016/`。
  使用说明与待完成项在 `docs/P2_FULL_MELODY_IMPORT.md`；需要用户提供完整 MIDI 或简谱后再转写并集成。
- 固定 60 BPM 保留分数拍与全部休止，不自动删音、重复、截短或移调；超现有音域时先审阅并确认统一移调。
  总库仍 2048 事件，不为完整曲目直接扩大 ROM。拿到数据前不重复构建已通过的片段版本。
- 用户最新提交 `924ad7b` 已保存之前两个用户文件；以当前 Git 状态为准，继续保护其后续修改和暂存状态。

## 用户两页简谱主旋律实施（2026-10-16 当前）

- 用户已提供两张 EOP/Wuyangr 双声部简谱，完整38小节。按此前选择仅做上行主旋律，第二音色、60 BPM；不新增伴奏玩法。
- 用户明确同意整曲降一八度，保留所有音程，将游戏音域扩为 D3～G5；原演奏模式品位表不动。
- 用户另明确同意第10、18小节的“5”由半拍改为一拍，作为待试听核对修订。其他音高/连音/休止不擅改。
- 原图、原始读谱与两条许可在 `scores/p2/source/`，212次起音/152秒。第36小节双高音点照图保留，不暗中改八度。
- 用户追加要求可见曲名只写“情歌”；准备/结果页按两字宽度居中。最终 M2 已纳入，20屏冻结像素对照通过；网表边界变化后已重新完成本批六项实际新 VG 验证，不复用旧网表结果。
- 实施/验证边界见 `docs/QING_GE_USER_MELODY.md`。本批原工程数字验证及完整 P&R/STA 已通过；新认证 `p2_qing_ge_melody_verification.json`，独立位流 `build/releases/touch_game/neo_guitar_touch_game_qing_ge_melody.fs`，SHA256 `c0a138912edbf2504f64143049066234c4f10ea381fd974b9c58f6b147bd3bf4`。旧片段认证/归档留存。
- P2 DDS有效位及滑音参数从26扩到27，其他工程默认仍26。音源模态/音效/采样率不变；完整32位参考、冻结演奏音频、当前 RTL/实际VG和STA均已通过。
- 新增精确有限源码例外校验器 `tools/check_qing_ge_melody_result.py`；不要放宽旧 P1/P2 校验器。无源变化不重复构建。
- 2026-10-18 用户报告当前主旋律版本已经过下板验证、整体可以接受；第10/18小节仍有轻微节奏偏差，影响不大，先保留当前时值并登记为已知待改进项。未采集现场烧录哈希或新的定量声学/长期稳定性数据，不将此反馈扩称为每项专项实测。
- 下一主线按 roadmap 为 P3 可写曲库/可靠 UART 导入；主旋律发布时显式 DPB 曲库无运行时写口，应先补暂存、校验和原子提交。加速度计已到货，可先做独立读取/安装校准；正式姿态联动为 P4。
- 2026-10-18 用户已授权先补可写曲库、再接 UART，有线成功后再尝试蓝牙；UART 优先使用开发板 DEBUG-USB2。按此顺序实施和验收，不将蓝牙或 MPU 混入本批有线曲库改动。保留第10/18小节当前时值、已验收主旋律归档和保护文件；不推送或代理烧录。

## P3 当前实施与恢复（2026-10-18）

- 原创“慢练”按用户要求从生产初始曲库移除；第二行待导入，茉莉花/riff/情歌仍在第1/3/4行。历史 P2 资产不删除。初始保留703事件，2048条总库中1345条共享导入空间，五槽覆盖目录、暂存/实际RAM读回CRC/双时钟原子提交。
- DEBUG-USB2 官方31005底板和两版60K核心板网络核对后，新增TX=U15、RX=V14、LVCMOS33；仅追加两脚，SDC与原接线不变。证据在 `build/p3_import/board_evidence/`。115200/8N1，XG3固定32字节帧及停等ACK；尚未打开实物COM口。
- 原工程C1综合66497 Logic超限，未P&R。C2固定五槽选择/窄字节索引后综合通过，但完整P&R有2218未布通；Logic59282、CLS29937、BSRAM103，失败证据在 `build/p3_import/impl_c2/pnr_failed/`，不认证位流。C3合法高位显式常量只省270Logic，未P&R；C4精确力度移位算术虽通过百万乘积/25128样本等价，却增加601Logic，已否决并恢复原乘法。不要复活这些失败候选。
- C2所需20项RTL、4项新增P3 RTL（存储/UART/整机/冻结显示）、32项Python已通过；整机当前实际VG对当前完整RTL门级验证通过，7次真实115200请求/ACK、12503音频样本、15帧/5483520 LCD时钟样本。冻结M2显示2715456有效像素/22场景，删除慢练行是明确限定例外。综合网表与P&R不能混用旧证据。
- 对应 `sim/temp/p3_c2_readback_02/`、`p3_c2_full_top_01/`、`p3_c2_display_01/`、`p3_c2_final_rtl_01/`、`p3_c2_full_gate_03/`；Python `build/p3_import/pc_checks/`。20项回归曾缺少两份冻结P2参考，保留前10项成功日志后补编参考续跑；`resume.json`完整记录，无需重跑。
- 当前C5：合法96位逻辑曲谱无损打包为77有效位/10个DPB（全部group保留，公开读口仍96位一拍），哇音原96项增益表用每声部1个DPB在LOAD读出，现有LOOKUP使用，不加运算时钟、不改参数/模态。冻结原音源45096样本覆盖三音色/三频段轮廓/四力度、击弦/和声/延音/哇音年龄边界及释放通过；五项P3 RTL完整通过 `sim/temp/p3_c5_packed_rtl_02/`。
- C5原工程综合已通过：LUT48770+ALU9279=58049、寄存器25450、BSRAM100，DSP配置恢复为原值（不以综合值代替最终CLS）。同一进程PID27940已审查放行完整P&R；日志 `build/p3_import/impl_c5_packed_gainrom/build.stdout.log`。20项回归 `sim/temp/p3_c5_final_twenty_01/` 全部通过，旧音频bench因新增DPB需GSR，只加一行并精确审计后保留前六项续跑（`resume.json`）。32项Python和两个生成器在 `build/p3_import/pc_checks_c5/`，不重复已完成项。
- 当前实际完整VG门级对照 `sim/temp/p3_c5_full_gate_01/` 已通过：7次真实115200事务、12503音频样本、15帧/5483520 LCD时钟样本；实际增益ROM256读/128地址及一拍/使能保持也通过 `sim/temp/p3_c5_gain_gate_02/`。01因审查记录尚未写完而前置条件失败，未运行仿真，记录完整保留。完整严格 `tools/check_game_p3_result.py --preflight` 已PASS，勿重跑已完成测试。
- 当前只待原工程完整P&R/STA及独立位流归档，不能提前宣称P3可交付。PID27940仍在布线，等待session31185；恢复先查已有PID/日志，不重复构建。C5源码/验证工具本地提交9ace08c，UART主体83de34b。最终使用 `tools/check_game_p3_result.py` / `tools/archive_game_p3.py`，旧校验器不放宽。
- 用户要求完成当前任务后暂停，等明确指令再继续；即使有线下板成功，也不自动开始蓝牙、MPU或下一功能。

### 最新恢复点：C7（2026-10-18，优先于上文旧C5进度）

- C5最终失败1420未布通，Logic58396、CLS29815、BSRAM101；完整功能/实际VG均通过，但无可交付位流。失败实物资源报告在 `build/p3_import/impl_c5_packed_gainrom/pnr_failed/`。
- C6把钢琴32模态相位/亮弦衰减数组移到RAM，原冻结音源逐模态及45210样本、20+6项RTL全部通过，综合Logic44622、寄存器18321、逻辑BSRAM112；实际映射PA2017为121/118，未进入布局。每个SDPB32占两个物理块，故改C7合存两类状态；C6失败在 `build/p3_import/impl_c6_mode_state/`。不复活C4力度移位候选，原乘法仍保留。
- 当前C7：每声部一块SDPB32，两个相邻地址保存相位32位/衰减24位；在原LOAD/ENV_B读取，PHASE/ACC写入，无新增运算状态/时钟、无读写碰撞。复位和起音按样本边界锁存后逐模态惰性初始化，保持全部模态/参数/音效和原输出。独立冻结原数组45210样本、每次相位/增益使用前对照、帧中输入改变/运算中复位，以及352读对/384写/全部字节已通过：`sim/temp/p3_c7_mode_ram_proof_01/`。
- C7原工程综合Logic44962、寄存器18449、逻辑BSRAM108；最终物理值以下文完整实现为准。PID32616已结束，目录 `build/p3_import/impl_c7_shared_state/`；原工程/两个保护文件/约束哈希均保留。四项P3回归 `sim/temp/p3_c7_final_rtl_01/` 和20项 `sim/temp/p3_c7_final_twenty_01/` 均通过。Python32项和生成器与C5完全同源，继续用 `build/p3_import/pc_checks_c5/` 严格哈希复用，不重复运行。
- 音源有限改动封存在 `sim/reference/game_p3/piano_shared_state_edit_spec.json`（相对9ace08c十处精确变换），旧C6规格另留。冻结原源仍精确等于M2 `cc8dbb7` 的piano_voice_core，仅改模块名。主校验器/归档器已指向C7；实际VG准备器已审计合存SDPB/32相位DFF/全部数据mux/父级复位资格，状态RAM与增益ROM门级均PASS：`p3_c7_mode_gate_01`、`p3_c7_gain_gate_01`。全机新实际VG `sim/temp/p3_c7_full_gate_01/` 已PASS并结束：10次真实115200事务、四声部G5/D3/E4/C5、13397音频样本、16帧/5875200 LCD时钟样本，包含频谱和曲线渐暗；后者不是独立有效像素数。不要重启或用旧VG日志认证。
- 全机门级bench已加强为四轨同时G5/D3/E4/C5、十次真实115200事务；四档力度metadata存储/CRC保留，但既有试听固定力度2保持，不能误称metadata改变试听力度。原CLI/协议/公开接口不变。
- 六个其他既有含piano_voice_core的gprj仅补新共享模块/头文件依赖，未构建、未改器件/配置。记录 `build/p3_import/project_dependency_updates.json`。本批完整实现认证仍只覆盖触控主工程。
- C7原工程P&R/STA现已通过：Logic45324、Register18449、CLS26860/29952（89.6768%）、BSRAM113/118、DSP115.5/118；系统/音频Fmax50.158/13.068MHz，运行仍50/12.288，setup/hold/latch/未布通0。源码/约束不变；PR1014两条通用时钟布线提示在旧M2也有，STA已按实际布线计入。旧55/13.5余量目标仍未达，不宣称P1全部目标完成。
- 当前原impl已生成新C7位流，SHA256 `57f0860227ba6b4c0010bebbaca829dfeea4799289ff3f47f8bf3e328afca4e1`。严格最终 `tools/check_game_p3_result.py` 已PASS，认证 `gowin/neo_guitar_touch_game/p3_import_verification.json` 绑定源码、ROM、实际VG、全部证据、P&R/STA及位流；实际曲库384组布尔连线审计也已通过。PID32616、整机门级及最终校验均已结束，**不得重复构建或已通过的测试**；process.json为COMPLETE_VERIFICATION_PASS，C7运行时源码提交122d765。
- 发布副本使用 `build/releases/touch_game/neo_guitar_touch_game_p3_uart_import.fs`，完整证据目录 `build/releases/touch_game/p3_uart_import_20261018/`，以其中archive.json及认证哈希核对归档。原工程`.fs`可直接用Programmer选择，无需重综合布线。PC上传环境和同一情歌导入样例已准备在 `build/p3_import/uploader_venv/`、`upload_example/`，步骤见 `docs/P3_WRITABLE_SONG_IMPORT.md`；未打开实物COM口。数字验证后只作归档和本地发布提交，随后按用户要求停止等指令；实物UART/听感/长期稳定性待用户验收，不推送/烧录/自动开始蓝牙或MPU。

## P4 新授权与当前恢复点（2026-10-18，覆盖上节暂停决定）

- 用户反馈当前版本没有明显问题，并明确要求先commit/push再修改。当前P3发布7837a24已成功推送origin/master（924ad7b..7837a24）；后续P4修改只在本地，不将此次许可扩展为自动推送新功能。未代理烧录、未采集实物文件哈希。
- 用户将10/18小节明确为四个拍格 `1_11|(1)5_3|(3)___|345`，括号连音不复弹、最后345一拍三连音。60BPM软件拨弦试听已生成在 `build/qing_ge_rhythm_review/preview_v1/`，用户明确回复“节奏正确，采用这版修改正式曲谱”。正式源码/CSV/BIN/双曲库BSRAM初值已更新：5仍半拍、3提前半拍并持续5/4拍；每小节8起音，整曲212起音/152秒不变。独立测试逐事件证明仅四条事件时间变化，原分弦全部保留，其他曲目保持；旧P3归档不改。试听是软件参考音，不是板上PCM或新音色等价证据。
- 用户授权尝试MPU-6050姿态切音色，确认GY-521，预计3V3，已有杜邦线但未接板/固定琴身。已读保护方案但不修改。选择独立GPIO：J8-11/Y21 SCL、J8-12/Y22 SDA、J8-1 3V3、J8-3 GND，AD0接模块GND；其他三脚不接。31005第19页及两版60K Bank8/已有官方约束已核对，ADC仍J8-5..8、原触控/I2S/矩阵不动。新渲染原图在 `build/p4_posture/board_evidence/`；模块供电/上拉电压和轴向仍待实测。
- 当前已实现独立一字节指针MPU读取（既有I2C默认两字节保持）、复位/ID/10配置回读/14字节包/故障重试；256包平放校准、Q4低通、幅度/陀螺/变化门控、回差/500ms稳定/1s间隔/健康恢复，36位串行算术无新增DSP乘法表达式；姿态持有握手CDC；仅演奏模式空闲自动切换，手动优先并取消待命目标，竖抱不冒充琵琶。主页底部CALIBRATE/AUTO、演奏页底部小状态区，开机手动、游戏保留推荐/手动音色。
- 组件 `sim/temp/p4_components_05/` 7项已PASS（含生产256包校准）；策略修订后 `p4_policy_06` PASS。整机 `p4_top_03` PASS：真实MPU GPIO、触控校准/AUTO、实际音色键、旧音待命/手动取消/退出/重入/故障恢复，2853音频样本/347读包/2次实际自动切换。明确刺激边界为触控/ADC注册输出与加速ms；真实音频时钟/采样方程保持。01/02发现正常PCM valid反复清空quiet计数而无法切换，已改采样边界排空、并加入脉冲/新拨弦优先回归，失败日志保留。
- P4尚待整机回归、像素边界检查、新综合/原工程P&R/STA及当前实际VG验证/归档，不能用旧P3认证新源码或宣称新位流可下板。构建仍用原gprj/impl，入口 `tools/start_original_posture_build.ps1`，证据 `build/p4_posture/`。恢复先查既有Gowin PID/process.json，禁止重复启动。保护两个用户文件字节/暂存对象；不改音源参数/时钟/SDC或路由配置，不复活频带实验。不开始蓝牙/Flash/新音色。
- P4二十项既有RTL与四项P3存储/UART/整机/冻结显示已通过：`sim/temp/p4_twenty_01/`、`p4_p3_rtl_01/`。仅补新增可选端口的明确常量/空连接后续跑，前序PASS日志保留，精确反向审计在各目录resume_imu_ports.json。33项Python/生成器已通过`build/p4_posture/pc_checks_a1/`。P4九项组件/生产256包校准/整机/冻结显示在`p4_final_rtl_01`通过。
- 用户在A1布线期间要求底部字体居中；已按可见字数居中CALIBRATE/AUTO/状态，并为右侧状态补底框。`p4_centered_display_01`对照12场景/1566720有效像素通过，RTL画面在`build/p4_posture/rtl_previews_centered/`。仅改渲染，触控区域/状态/音频不变；既有非渲染证据须按精确源码范围复用，不能伪称测试过新渲染。
- A1综合PASS但因上述UI修正于布线中主动停止，状态`SUPERSEDED_DURING_PNR_UI_CENTRING`，旧源码/VG/日志保留于`build/p4_posture/impl_a1/`；不作为最终位流证据。下一次原工程构建使用`impl_a2_centered`，先查已有PID及日志。实际新VG门级入口`tools/run_posture_gate.ps1`，含新增姿态整机与既有UART/音频/显示整机对照；不使用旧VG日志认证新VG。
- A2当前运行时源码`be885621daae47e73bbe6956256db95eb884b0d5`，Gowin PID18208，开始22:03:12+08，日志`build/p4_posture/impl_a2_centered/build.stdout.log`；已审查放行P&R，不能重复启动。综合Logic50211=39715LUT+10496ALU，FF20090，逻辑BSRAM108，新姿态模块DSP0；实际VG SHA256 `27ef25ca8683cc1881a74d9ce5eeeb9c26949c2ad93f428bd22649d0509507ee`。最终资源/STA仍待P&R，逻辑BSRAM不能冒充物理值。
- 当前实际新VG的增益ROM/模态状态RAM门级已PASS：`p4_a2_gain_gate_01`、`p4_a2_mode_gate_01`；384组曲库写连线布尔审计也PASS于A2目录。两个完整实际VG对照`p4_a2_full_gate_01`（真实UART/四声部/动态LCD）、`p4_a2_posture_gate_01`（生产256包校准、真实MPU引脚/物理音色键/待命尾音/恢复）已启动，恢复先查各verification.json/log和现有进程，不能重复。最终入口`tools/check_posture_result.py`、`tools/archive_posture.py`；有限音频观测和字体居中修改封存在`sim/reference/posture/*edit_spec.json`。旧音源45210样本仅按未变组件完整依赖闭包复用，不冒充新整机证据。新UART情歌样例`build/p4_posture/upload_example/`与修订后生产BIN逐字节相同，CRC32 c3451bbc，未打开COM。
- 两个A2完整VG入口现均已PASS且结束，不重启：姿态12815音频样本/1773MPU包/5次音色变化/11226240有效期系统时钟LCD采样，UART13397样本/16帧/5875200 LCD时钟采样。后两者不是独立像素数。发现旧45210组件记录遗漏音色ROM哈希后，仅补两项当前完整输入闭包组件`p4_audio_dependency_closure_01`，45210样本/全部原模态及352读/384写均PASS；旧组件记录保留但不再作为新认证所需证据。P4 runner已增加全部mem和自身工具哈希。当前严格`check_posture_result.py --preflight`已PASS，日志`build/p4_posture/impl_a2_centered/preflight.log`。现在只待PID18208原工程P&R/STA及最终绑定/归档；不要重跑任何已通过回归或完整门级。
- A2 PID18208现已结束，23:14:16完成完整P&R/STA，最终校验PASS。Logic50580、FF20090、CLS28585/29952（95.436%）、物理BSRAM113/118、DSP115.5/118；系统/音频Fmax50.020/13.858MHz，运行50/12.288，setup/hold/latch/未布通/已测deadline全部0。原FS SHA256 `34f8a86e942e291453159655c654fc72e5424167686cb2200dd659d4daf7229c`；新认证`p4_posture_verification.json`，发布名`neo_guitar_touch_game_p4_posture.fs`，证据归档`build/releases/touch_game/p4_posture_20261018/`。两个旧PR1014提示保持，STA计入真实布线；旧CLS≤95%/系统55MHz余量目标仍未达，不宣称旧P1全部目标完成。所有数字检查通过后只作归档/本地提交，禁止重复构建/回归。P4未下板、未打开COM/烧录；交付后等用户反馈，不自动继续蓝牙/Flash/新音色。

## 四弦力度校准新授权（2026-10-18，覆盖旧固定力度2约定）

- 用户提供微信目录三个旧工程文件，要求先保存当前P4，再按队友实测阈值接入当前四档力度/响度，综合仿真；之后明确允许新位流覆盖同名`build/releases/touch_game/neo_guitar_touch_game_p4_posture.fs`，不另建发布FS名。覆盖只在完整P&R/STA/验证PASS后进行。旧P4已保留标签`snapshot/p4-posture-before-velocity-20261018`（1bbab98）和完整原归档，其内部旧FS不能覆盖。无新push/烧录授权。
- 生产源码e5680ef：动态力度默认启用；基准2053，触发150/100/80/100，回落20，分界[280,430,620]/[250,400,600]/[150,280,400]/[220,380,600]。首样本+随后32通道样本取峰，400死区/80回落保持。当前voice_envelope与上传相同且不是主音源包络；所有主音源/音效/增益参数不动，用已有112/160/208/256增益。新增capture_pending接入姿态待处理音符观察，防止捕获期提前切音色。具体见`docs/VELOCITY_CALIBRATION.md`和`sim/reference/velocity_teammate/`原文/哈希。
- 原工程综合PID39028已PASS结束，证据`build/velocity_calibration/synth_v1/`。Logic50199、FF20146、逻辑BSRAM108，DSP原语与P4相同。新实际VG SHA256 f64a6960a33513f73e2c60006b31a0fdf18970cce2fd0a23a128eb81e816e3c2。原工程P&R已接续同一VG，PID24376，日志route.stdout.log/route_process.json，不能重复启动；配置/保护文件字节和index保持。
- 新RTL三项检测/实际SPI、三项真实音频/策略/顶层、四项冻结音频/判定/扩展音域/硬件按键回归均已PASS：velocity_detector_01、velocity_audio_02、velocity_legacy_01。真实音频12档每档1024样本，固定正确等级音源oracle逐PCM/数字口相同、声部能量递增、单声部干声无硬顶；01最后四弦测试oracle错设，失败留存，仅修正测试输入后通过。当前实际ADC VG四弦四档4739008时钟/32238转换PASS（velocity_adc_gate_01），384组曲库布尔连线审计也PASS。完整实际VG/UART和姿态整机正在velocity_full_gate_01/velocity_posture_gate_01运行，恢复先查验证记录和进程，已过测试不重跑。

### 力度校准最终交付（2026-10-19，优先于上文运行中状态）

- 综合PID39028、原工程同一VG的P&R PID24376及两个完整VG仿真均已结束PASS，禁止重复构建或重跑已完成测试。完整P&R于00:09:27完成：Logic50570、Register20146、CLS28316/29952（94.538%）、物理BSRAM113/118、DSP115.5/118，系统/音频Fmax50.089/13.638MHz，运行50/12.288不变；setup/hold/latch/未布通及已测deadline全部0。保留两条既有PR1014提示，STA计入实际布线；系统55MHz余量目标仍未达到。
- 当前实际VG整机UART对照velocity_full_gate_01已PASS：10次真实115200事务、四声部、13397样本、16帧/5875200 LCD时钟采样，含动态频谱/曲线渐暗。姿态velocity_posture_gate_01已PASS：生产256包校准、真实MPU引脚/物理音色键/待命尾音/恢复，12815样本/1773包/5次音色变化/11226240有效期系统时钟LCD采样。采样数不是独立像素数；刺激边界见各bench记录。
- 严格最终check_velocity_result.py已PASS，认证velocity_calibration_verification.json绑定本批源码/ROM/工具/输入/日志/当前VG/P&R/STA/FS。新FS SHA256为210877be3e236c36d431e67bd116a6c9b0c2ac4e6d7b18912b162473b2b5812c，原impl可直接使用；按明确许可覆盖同名neo_guitar_touch_game_p4_posture.fs，完整证据归档build/releases/touch_game/p4_velocity_calibration_20261019/。旧P4原归档内部FS仍34f8a86e...，旧认证只认证该固定快照。两个用户文件字节/暂存对象保持。
- 仅完成归档/本地提交后等待用户四档实物手感、噪声/串弦、实际声压与MPU联动反馈；不把数字能量测试当作独立声学标定。不自动推送、烧录、打开COM或开始蓝牙/Flash/新音色。

## 第一弦与最低档响度新授权（2026-10-19）

- 用户报告弹其他弦易触发第一弦，并要求最小音量更低；新授权覆盖上节等待决定。本批只改CH0/E4触发150→220和主音源最低档增益112→64，其余三弦触发、四弦力度分界/回落/捕获、增益160/208/256、音源模态/包络/音效/时钟/接线不变。旧力度版已保留标签snapshot/p4-velocity-before-ch0-threshold-20261019（df770fa）与完整固定归档p4_velocity_calibration_20261019，内部FS哈希210877be...不能覆盖。最终通过后继续按既有许可覆盖同名发布FS；不push/烧录/打开COM。
- 生产源码855e63d。四项检测/真实SPI回归dynamics_detector_01已PASS，16384码/132峰值，另140组150～219正负模拟串弦在新CH0抑制、旧150触发，其他三弦逐周期一致，220边界真实起音保持最低档。四项dynamics_audio_01已PASS：独立冻结上版主音源30024样本（档1～3的8694样本完全相同，档0的21330样本只作64/112缩放和整数舍入）、三音色×四档真实ADC到双音频口及姿态策略/整机。四项dynamics_legacy_01已PASS：8192冻结音频参考仅接受已授权的档0增益112→64这一处有限修改，不能声称档0也等于旧未改PCM；9032扩展音域/判定/按键通过，退出1452样本。旧参考和旧校验器保持。
- 原工程综合PID12236已启动，证据build/velocity_calibration/dynamics_v1/，恢复先查process.json/build.stdout.log，禁止重复启动。需要新实际VG/ADC/两项整机验证、同一VG完整P&R/STA和新认证dynamics_tuning_verification.json后才可发布；旧力度版认证不认证新产物。入口start_original_dynamics_synthesis.ps1、review_dynamics_synthesis.py、route_original_velocity.ps1 -RunName dynamics_v1、check_dynamics_result.py、archive_dynamics.py。两个用户文件字节/index继续保护。详细范围见docs/DYNAMICS_TUNING.md。
- 最新：PID12236综合已结束并审查PASS，Logic50200=LUT39700+ALU10500、FF20139、逻辑BSRAM108，DSP原语不变；实际VG SHA256 b5896b26820e9ff7d90c3e53d118a68f31fb6c8ca25682587b5bb2598c0e6769。同一VG原工程P&R PID31412已启动，route.stdout.log/route_process.json记录；384组本批曲库连线审计PASS。新实际VG三项在dynamics_adc_gate_01、dynamics_full_gate_01、dynamics_posture_gate_01，恢复先查verification.json/日志和既有进程，不重复启动或重跑本节已过RTL。完整门槛通过后才覆盖同名FS，旧固定归档不能覆盖。
- PID31412已于13:00:52结束完整P&R/STA并通过审查：Logic50570、FF20139、CLS28479/29952（95.082%）、BSRAM113/118、DSP115.5/118，系统/音频Fmax50.043/13.619MHz，运行50/12.288不变，setup/hold/latch/未布通0。旧CLS≤95%/系统55余量目标未达，不为此重复构建或扩大优化。新原FS哈希e97afee45346aad123a1ec525a2ddc0b344348898348eaf518fd7d9d7b0c4213，尚未覆盖发布副本。新ADC实际VG已PASS；四声部速度DSP的128组完整实际增益操作数/原流水参数审计PASS（audit_dynamics_gain.py）。仅待两个正在运行的完整VG及最终认证/归档，禁止重复其余已通过项。
- 最终恢复点：两个完整VG现均已结束PASS，UART/显示13397样本/16帧/5875200 LCD时钟采样，姿态12815样本/1773包/5次变化/11226240有效期系统时钟LCD采样；新严格check_dynamics_result.py已PASS，dynamics_tuning_verification.json完成本批哈希绑定。全部构建与仿真已结束，禁止重跑。按既有授权覆盖同名neo_guitar_touch_game_p4_posture.fs为e97afee4...，完整证据归档p4_dynamics_tuning_20261019；旧力度版210877be...及旧P4的34f8a86e...固定归档/标签保持。只作本地发布提交，然后等待用户试板比较第一弦误触/轻拨漏音和最低档响度，不自动push/烧录/COM或新功能。

## 第三弦与四等分增益新授权（2026-10-19）

- 用户要求第三弦最低触发再低一点、第二/第三档增益50%/75%，本批选CH2/G3触发80→60，主音源档1/2增益160/208→128/192，形成64/128/192/256（25/50/75/100%）；CH0保持220、其他触发/分档/包络/音效/时钟/接线不变。试听仍编码2，因此变为75%。用户追问是否已有力度音量变化，已说明旧发布已按真实峰值四档发声，本次只改参数。旧版d0b57a4已保存标签snapshot/p4-before-quarter-gains-20261019和固定归档p4_dynamics_tuning_20261019（旧FS e97afee4...）。无push/烧录授权。
- 生产源码152a764。五项quarters_detector_01和四项quarters_audio_01已PASS：16384码/132峰值、原CH0的140组抑制、CH2新增40组正负60～79轻拨/59与60边界、真实SPI四弦四档；新旧音源48456样本，其中档0/3的5796样本相同、档1/2的42660样本仅授权缩放/舍入；真实ADC三音色四档及姿态策略/顶层通过。quarters_legacy_01使用原冻结655458f且只准已授权的三个增益常数变化，待检查结果，不能称改过增益的档与原未改PCM相同。
- 原工程综合PID23460已启动，build/velocity_calibration/quarters_v1/process.json/build.stdout.log，恢复先查进程与日志，禁止重复启动/已过测试。入口start_original_quarter_synthesis.ps1、review_quarter_synthesis.py、现有route_original_velocity.ps1 -RunName quarters_v1、run_velocity_gate.ps1 -ImplementationRun quarters_v1、check_quarter_result.py、archive_quarter.py。须新实际VG和完整P&R/STA/最终哈希绑定通过后才覆盖同名FS，旧固定归档保持。详细见docs/QUARTER_DYNAMICS.md。两个用户文件字节/index继续保护；完成后等待试板，不自动开新功能。
- 最新：quarters_legacy_01四项已PASS（8192/9032样本、判定、按键，退出1452样本）；全部13项本批RTL通过。PID23460综合已结束并审查PASS，Logic50053=LUT39553+ALU10500、FF20139、逻辑BSRAM108，DSP原语不变；新VG SHA256 543d2db4977ee1b141c179ac17ebb4d948d40fbf13fd6d82f441580547d72107。同一VG原工程P&R PID38532运行，route_process.json/route.stdout.log；本批384组曲库及128组四声部真实DSP增益64/128/192/256审计PASS。三项新VG正在quarters_adc_gate_01/quarters_full_gate_01/quarters_posture_gate_01，不重启或重复本批已过测试。最终门槛/绑定通过后才用archive_quarter.py覆盖同名FS并归档p4_quarter_dynamics_20261019。
- PID38532现已于14:37:34结束完整P&R/STA并审查PASS：Logic50432、FF20139、CLS28650/29952（95.653%）、物理BSRAM113/118、DSP115.5/118，系统/音频Fmax53.171/14.051MHz，运行50/12.288不变，setup/hold/latch/未布通0。CLS增加171，旧95%/55MHz余量目标未达，不重跑或扩大优化。原FS新哈希cfda7ead63703142876e10776a38f86237188aeb4a4d910b02aa0927df611a30，发布副本仍e97afee4...；实际ADC VG已PASS，仅待两个运行中的完整VG与最终认证/归档。恢复先查既有结果，不重复启动。
- 最终恢复点：两个完整VG均已结束PASS，UART/四声部/动态LCD13397样本/16帧/5875200时钟采样，姿态真实MPU生产256包校准/手动/尾音/恢复12815样本/1773包/5次变化/11226240有效期系统时钟采样；采样数不是独立像素数。check_quarter_result.py已最终PASS，新quarter_dynamics_verification.json完整绑定本批源码/ROM/冻结参考/工具/日志/当前VG/P&R/STA/FS。全部构建和仿真已结束，禁止重复。按既有许可覆盖同名neo_guitar_touch_game_p4_posture.fs为cfda7ead...，完整证据归档p4_quarter_dynamics_20261019；旧e97afee4...及更早归档/标签保持。完成本地发布提交后等用户试板第三弦轻拨/串弦与四档听感，不自动push/烧录/COM/下一功能。
