# P3 可写曲库与 DEBUG-USB2 UART 导入

2026-10-18：C7代码、原工程完整实现、全部所需数字验证及严格校验已通过，准备下板验收。使用原 `.gprj` / 原 `impl` 的 `gw_sh` 流程完成综合和P&R；本次未烧录实物、未打开COM口、未推送。交付后按用户要求暂停，等明确指令。

原工程位流：`gowin/neo_guitar_touch_game/impl/pnr/neo_guitar_touch_game.fs`。独立同哈希发布副本：`build/releases/touch_game/neo_guitar_touch_game_p3_uart_import.fs`；完整证据归档 `build/releases/touch_game/p3_uart_import_20261018/`。可以直接在Gowin Programmer选择位流，无需重新综合布线。

SHA256：`57f0860227ba6b4c0010bebbaca829dfeea4799289ff3f47f8bf3e328afca4e1`。认证：[p3_import_verification.json](../gowin/neo_guitar_touch_game/p3_import_verification.json)，明确绑定源码/ROM、当前实际VG、全部测试日志、原工程P&R/STA和位流，不复用不同网表日志。

## 同口径完整实现对比

| 项目 | 已下板M2主旋律 | 新P3 C7 |
| --- | ---: | ---: |
| Logic /59904 | 52286 | 45324 |
| Register /60780 | 23079 | 18449 |
| CLS /29952 | 28470（95.05%） | 26860（89.68%） |
| BSRAM /118 | 99 | 113 |
| DSP /118 | 115.5 | 115.5 |
| 系统Fmax MHz | 55.334 | 50.158 |
| 音频Fmax MHz | 13.143 | 13.068 |

新实现Logic减少6962、寄存器减少4630、CLS减少1610，增加14个物理BSRAM。实际运行仍为50/12.288MHz；setup/hold/latch/未布通及已测deadline均为0。CLS已低于95%，系统和音频仍比55/13.5MHz余量目标分别差4.842/0.432MHz，不能宣称旧P1余量目标全部完成。系统最紧路径为 `u_scan/v_count_5 -> u_ui/tails1_7`，setup余量0.063ns；后续仅在再获指令后按当前STA评估像素前级时序，不恢复用户已拒绝的频带优化路线。音频后续候选须依据当前报告单独定位。

两条PR1014通用时钟布线提示在已下板M2也存在；本次STA已按实际布线检查，未改CST原引脚、SDC或时钟以获得PASS。所有资源收益以上表完整实现为准。

用户指定顺序：可写曲库 → UART → 有线下板成功后尝试蓝牙。本批不加入 MPU、蓝牙、Flash/SD 或新音色。主工程保持原 `.gprj` 与原 `impl`，发布归档独立保存；不推送、不代理烧录。

## 曲库与操作

- 五个逻辑槽、合计 2048 条 96 位事件。按用户最新要求删除原创“慢练”，其第二行变为待导入；《茉莉花》、Seven Nation Army riff 和《情歌》仍在原来的第一、三、四行。第五行在导入后开放。其余页面、声音和按键职责保持。
- P3 初始库由原 P2 数据删除慢练的 256 条后紧凑排列：茉莉花 `0..66`、riff `67..234`、情歌 `235..446`、禁用诊断谱 `447..702`。后三者音符内容逐条保留；P2 历史资产与冻结验证路径不改。
- 前 703 条始终保留。运行时导入使用余下 **1345 条共享空间**，可替换任意一个槽的目录；导入曲目显示 `USER 1` 至 `USER 5` 和 `RAM`。这不是每槽独享 1345 条。
- 新曲先写空闲连续范围，提交前旧版本仍占用空间；空闲范围不足返回 `NO_SPACE`。成功后才释放旧导入范围供复用；内置前缀不回收。接口重置后恢复默认目录，旧导入数据不可达。
- 导入只允许主页/选曲页，且音频路由已确认空闲、触控可用、无模式切换。导入事务锁定触控操作；演奏/试听/游戏/准备/结果页返回 `BUSY`。
- 收到整曲后检查 CRC32，并从**实际 BSRAM 逐条读回重算 CRC**；成功后将目录描述符握手传到音频域，收到确认后在下一帧消隐开始发布系统域目录并 ACK。不能只靠电脑检查，也不能在半曲状态下选中。
- C5物理存储只保存合法记录的77个有效位（25位起音/25位时长/7位MIDI/两位轨道和力度/完整16位group），用10个DPB16承载；对外恢复完整96位逻辑记录及原一时钟读取。省去的高位/flags必须在写入前已验证为零；所有合法事件和CRC保持，不缩减时间/音域或音频位宽。
- 保持游戏 D3–G5/MIDI50–79、四轨无需按品、实际拨弦力度和实时合成。数据包含时间、音高和轨道，不传 PCM 或任意 DDS。第10/18小节目前时值按用户已接受版本保留。
- 导入数据仅在持续供电时保留，复位、重新配置或断电后丢失。拔电脑时需保留独立供电。持久化存储另行实施。

## 板载串口

用户选择 DEBUG-USB2。官方 60K 文档明确板载调试器提供 UART；重新下载的 31005 底板、30353/30354 两版 60K 核心板和官方全引脚 CST 在 `build/p3_import/board_evidence/`，下载 URL/SHA256 与相关页图留存。

| 信号 | FPGA 球位 | 底板路径 | IO |
| --- | --- | --- | --- |
| FPGA TX | U15 | J2-50 → FPGA_UART.TX → BL616 GPIO27 RX | Bank6，3.3 V |
| FPGA RX | V14 | BL616 GPIO28 TX → FPGA_UART.RX → J2-54 | Bank8，3.3 V |

官方全引脚 CST 的后期板 RX 注释行把 `LVCMOS15` 与 `BANK_VCCIO=3.3` 混写；本次以 31005 和两版 60K 实际网络、Bank8 及现有同 Bank 3.3 V 接口核对，使用 LVCMOS33。不采用 31002 的 Y14，也不改已有音频/触控/矩阵/ADC接线。SDC 与实际 50/12.288 MHz 时钟保持。

官方入口：[60K Wiki](https://wiki.sipeed.com/hardware/zh/tang/tang-mega-60k/mega-60k.html)，[全引脚约束](https://dl.sipeed.com/fileList/TANG/Mega_138K_60K/08_Misc/tang_mega_60K_pins.cst)。本批未升级 BL616 固件或改驱动，串口 COM 号需要现场确认。

## 传输格式

首版固定 **32 字节 XG3 帧、115200/8N1、停等 ACK**。每个 DATA 帧传一条 16 字节 v2 事件，避免大包缓冲和重放存储增加资源。实际物理 RX 有两级同步和 16 字节 FIFO，包内字节连续接收，不以内部 ready 要求串口暂停；溢出、坏停止位及半帧超时重新同步。尚不支持流水发送、断点续传或蓝牙会话。

| 字节 | 内容 |
| --- | --- |
| 0–3 | ASCII `XG3!` |
| 4 | 协议版本 3；事件记录仍是 v2 |
| 5 | 命令；响应为命令 OR `0x80` |
| 6–7 | 非零 u16 会话号，小端 |
| 8–9 | u16 连续序号，小端；HELLO 为 0 |
| 10–25 | 16 字节 payload，未用部分为零 |
| 26–27 | 保留，必须为零 |
| 28–31 | 字节4–27的 CRC-32/ISO-HDLC，小端，与 `zlib.crc32` 一致 |

命令 1 HELLO、2 LIST、3 BEGIN、4 DATA、5 COMMIT、6 ABORT、7 STATUS。BEGIN payload 为 `<BBHIII`：槽号0–4、音色0–2、事件数、总时长/48kHz样本、整曲v2 payload CRC、保留0。DATA 为原16字节事件。LIST payload 首字节槽号，余字节0。COMMIT/ABORT 为全零。

响应 payload 首字节状态：0成功，1 BUSY，2 NO_SPACE，3长度，4整曲/读回CRC，5排序/同轨冲突，6范围/元数据，7密度，8事务超时，9无事务，10命令，11帧格式，12帧CRC，13会话/序号。成功才推进序号。重复的上一成功帧须会话/序号/命令/CRC全部相同，返回缓存的原响应，不重复写或提交。失败帧重试保留原序号；新会话不能夺取正在进行的事务。

HELLO 成功响应字节1–15 为 `<BBBHHBBIH`：事件格式2、槽数5、帧长32、保留初始条数703、总条数2048、最低MIDI50、最高79、采样率48000、功能标志。LIST 成功响应字节1–12为96位目录，13为槽号，14低四位为valid/playable/imported/test_only，15保留0。

目录96位：`[31:0] ceil(duration/480)`、`[42:32] base`、`[54:43] count`、`[86:55] duration`、`[88:87] timbre`，其余零。CRC包含原始 v2 的 group_id；实际存储与读回保留它，不为腾空间丢弃字段。

FPGA 校验事件总时长≤10min、非零时长、结束时间不溢出且≤总时长、MIDI/轨道/力度/flags/reserved范围、非降序起音、同轨无重叠、同轨起音≥12000样本、任意108200样本窗口每轨≤8个可见块。原始事件完全校验后才写临时范围；完整RAM读回成功后才发布。

## 电脑工具与下板步骤

1. 用Gowin Programmer选择上述新P3位流烧录（由用户执行）。DEBUG-USB2连接电脑，确认UART COM口并关闭占用它的串口助手。
2. 用已有 `tools/compile_p2_score.py` 编译自己的 CSV，加 `--profile game_extended` 支持游戏 D3–G5，`--timbre 1` 为第二音色；产出同前缀 `.bin/.json`。保留全部音符，无法满足轨道/密度约束时明确报错。
3. 在主页或选曲页查询：`python tools/upload_game_score.py --port COM5 --list`。COM5仅为示例。
4. 导入：`python tools/upload_game_score.py --port COM5 --slot 2 --bin path/to/song.bin --metadata path/to/song.json`。槽号是界面1–5，推荐先用已清空的第二行或第五行。
5. 工具逐条等 ACK，收到 COMMIT 成功并再查目录后才报告完成。最终 ACK 全部丢失时明确报告“提交结果未知”，不能声称已回滚。
6. 触控选择对应 USER 行，核对推荐音色、试听、拨弦判定/Miss、进度、重玩及双击退出。保留独立供电后拔 USB，整曲应仍可演奏。
7. 现场再测中断导入/错包/满空间和旧曲保留。确认有线可靠后再评估具体蓝牙模块并复用协议；不把蓝牙透传当作已经实现。

Python 工具只有显式调用并指定 `--port` 才打开串口；本次未自动向实物发送、烧录或更新固件。

本机已在仓库内准备独立上传环境，不改 `E:\anaconda3`：`build/p3_import/uploader_venv/Scripts/python.exe`，已校验并安装 [PyPI pyserial 3.5](https://pypi.org/project/pyserial/3.5/)（wheel SHA256 `c4451db6ba391ca6ca299fb3ec7bae67a5c55dde170964c7a14ceefec02f2cf0`）。模块导入和CLI帮助通过，记录 `build/p3_import/pc_checks/runtime_environment.json`。若换机器，可重新建虚拟环境安装此依赖。

用户烧录并确认COM号后，在仓库根目录执行（COM5只是示例）：

```powershell
.\build\p3_import\uploader_venv\Scripts\python.exe tools/upload_game_score.py --port COM5 --list
.\build\p3_import\uploader_venv\Scripts\python.exe tools/upload_game_score.py --port COM5 --slot 2 --bin build/p3_import/upload_example/qing_ge.bin --metadata build/p3_import/upload_example/qing_ge.json
```

示例直接用已接受的同一份《情歌》CSV，以60BPM/第二音色/游戏扩展音域编译：212事件、7296000样本，CRC32 `49355fa2`；已经过上传器文件配对校验。它用于先验证导入到空第二槽的有线闭环，不替换内置第四槽，也未向实物发送。第二槽名称显示为 `USER 2`。

## 历史迭代证据（以下C1–C5不认证新位流）

- C1 整机综合失败：66497 Logic >59904；未启动 P&R。因失败未更新 VG/资源XML，原目录留下的旧 M2 网表/报告不能认证 C1。
- 组件诊断显示 C1 importer 为10218 LUT/291 ALU且意外使用1个MULT12X12，主要是 `scan_slot*96` 的动态位索引。C2 改成固定五槽选择及明确字节索引；完整资源收益待原工程报告，不用组件结果替代。
- `sim/temp/p3_c2_readback_02/`：1345条满容量、五槽替换/空洞复用、13698次读、1424条响应；错误CRC、损坏RAM读回、边界/冲突/密度、超时、ABORT和复位保护；17组真实UART请求/ACK、波特偏差、重放、CRC/序号和BUSY。
- `sim/temp/p3_c2_full_top_01/`：实际生产顶层 UART→DPB→双域目录→第五触控槽→实际第二音色→G5/D3试听及玩家两次命中/200分、结果/进度、BUSY与触控锁。43244个实际音频样本、49帧；仅触控输出/ADC事件为明确刺激边界，UART分频与倒计时为仿真加速参数。
- `sim/temp/p3_c2_display_01/`：冻结已下板 M2 renderer 的2715456有效像素/22场景对照；唯一内置菜单例外限定为用户删除的慢练行；导入标题/进度之外的游戏几何、渐变尾迹、反馈和六时钟像素节奏保持。
- 原九项RTL、P2有界窗口/全曲控制/判定、三音色冻结音频8192样本/2097153时钟、延音退出1452样本、D3–G5完整32位音频参考和按键回归已通过。与C2修改无关的既有音源证据保留；最终认证仍须逐项匹配当前源码或明确冻结边界。
- 32项电脑测试通过（其中8项协议/上传器），覆盖分弦/同轨约束、v2编谱、用户全曲/移调、MIDI输入、黄金CRC、32字节损坏/截断、分段写、丢ACK、噪声、重复提交、未知提交结果和编谱文件配对。证据 `build/p3_import/pc_checks/`；未打开实物串口。
- 实际完整VG与当前完整RTL：`sim/temp/p3_c2_full_gate_03/`，7次真实115200 UART请求/ACK、真实DPB写入及读回CRC/group、双域提交、第五行触控/实际第二音色/G5起音/退出、12503音频样本、15帧/5483520 LCD时钟样本（不是独立有效像素数），包括频谱和曲线渐暗。只在注册触控输出刺激和经审计的全部32位倒计时Q上加速；没有注入曲谱、DDS或起音。12个实际DPB的2048×96初值全部核对；实际门级动态导入为1事件，满1345事件及跨页写读属于RTL压力验证。
- 原工程C2 `build/p3_import/impl_c2/` 已结束，实际P&R Logic59282、CLS29937/29952、BSRAM103、2218未布通。C3仅显式高位常量省270Logic；C4精确力度移位加减虽等价但比C3增加601Logic，均审查否决、未P&R，原乘法已恢复。
- 历史C5 `build/p3_import/impl_c5_packed_gainrom/` 已失败归档。除曲库无损打包外，原哇音96项增益常量改为每声部1个DPB在LOAD提前读取，仍在现有LOOKUP使用，全部系数、模态和时钟计划不变。冻结原源 `sim/reference/game_p3/piano_voice_core_before_p3_rom.v`；当时45096样本和完整VG通过但不能认证新C7。最终C7重新验证45210样本、全部当前VG和实际物理实现。
- 20项最终C5回归 `sim/temp/p3_c5_final_twenty_01/` 已通过；从缺失vendor GSR处接续，旧音频bench只补全局GSR一行并保留已通过六项，源码/修订/旧失败在 `resume.json`，不忽略诊断或删除音频断言。实际新VG的增益ROM `sim/temp/p3_c5_gain_gate_02/` 256读/128地址、同步一拍和使能保持已通过；完整VG仿真 `sim/temp/p3_c5_full_gate_01/` 也已通过，7次真实115200事务、12503音频样本、15帧/5483520 LCD时钟样本，与当前完整RTL逐周期一致。严格预检 `tools/check_game_p3_result.py --preflight` PASS，剩P&R/STA和归档。旧C2记录只认证C2，不复用不同VG证明。
- 当前工作完成归档后按用户要求暂停，等进一步指令；不自动开始蓝牙或MPU。

## C7 状态RAM与最新恢复点

C5虽全部数字功能通过，完整布线仍有1420未布通（Logic58396、CLS29815、BSRAM101）。C6将模态寄存器数组换RAM后综合Logic44622，但每个SDPB32占两个物理块，实际BSRAM121超限，在布局前终止；全部失败证据保留。C7用每声部一块SDPB32的相邻两行存相位32位/衰减24位：LOAD读相位、ENV_B保存相位并读衰减，PHASE/ACC分别写回，全部利用已有状态，无新增模态运算时钟或读写碰撞。

复位和起音的并行数组赋值改为样本边界锁存参数后、每模态首次使用前选择精确初值；完整模态数、seed/gain/ratio/envelope及乘法/舍入不变。旧数组源冻结在 `sim/reference/game_p3/piano_voice_core_before_p3_rom.v`；`piano_shared_state_edit_spec.json` 封存十处有限修改。45210样本覆盖三音色/三频段/四力度/击弦/和声/延音/哇音年龄边界/释放，每次相位和衰减使用前对照旧数组，并测帧中输入变化与运算中复位。状态RAM另测352读对（704物理读）/384写、全部32地址和全部字节；一读对利用两拍，无额外音频时钟。

`build/p3_import/impl_c7_shared_state/` PID32616 已完成，禁止无源变化重复构建。26项RTL证据在 `p3_c7_final_rtl_01`、`p3_c7_final_twenty_01`、`p3_c7_mode_ram_proof_01`；新实际VG状态/增益组件 `p3_c7_mode_gate_01`、`p3_c7_gain_gate_01` 和全机 `p3_c7_full_gate_01` 全部通过。实际组件端口和全部LUT/SDPB/相位DFF连接均审计；子模块复位资格已由综合移入端口，组件测试按合法正常读写协议令其为高，整机覆盖启动复位、独立原源覆盖运算中复位。实际曲库另有384组穷举布尔证明：两页写隔离、全部10位写地址、字节使能及77位数据/完整group精确连线，记录 `bank_write_audit.json`。主校验器保留资源/未布通/STA/音频/其余源码保护，仅允许封存并独立验证的音源存储变换。

新完整VG对当前完整RTL：10次真实115200事务（连续DATA、重复请求、BUSY），实际四声部G5/D3/E4/C5译码和第二音色/退出、13397音频样本、16帧/5875200 LCD有效时钟样本逐周期相同，包含频谱与曲线渐暗。这里的LCD数是扫描时钟样本，不能当作独立有效像素数。冻结M2显示另有2715456有效像素/22场景对照。四档velocity metadata被完整存储/读回CRC校验；既有试听力度2、实物前端固定力度2保持，四档实物力度标定未实施。

其他六个引用共享钢琴核心的gprj只补模块/头文件依赖并核对器件不变，未进行这些工程的额外综合；本批完整实现只认证触控主工程。剩余实测：DEBUG-USB2枚举与实际传输/中断恢复、导入后试听和真实拨弦/音色/退出、独立供电拔USB、长期稳定性和声学听感。未升级调试器固件、未代理烧录、未采集本批实物文件哈希。完成本批归档后暂停，等待指令。
