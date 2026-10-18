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
