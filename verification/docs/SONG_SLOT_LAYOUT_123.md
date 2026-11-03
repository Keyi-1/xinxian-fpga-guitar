# 默认曲谱连续三槽

基于用户确认可用的 LCD180/触控/MPU 修复版本（原位流 SHA256 `1be03302c47a9d1c50b673a0d637eb3aa638e43b852b3d8f25e111ad3eae9a3e`）。默认曲谱变为：

| 可见槽号 | 默认内容 | 事件地址/数量 | 推荐音色 |
| --- | --- | --- | --- |
| 1 | 茉莉花 | 0 / 67 | 钢琴 |
| 2 | Seven Nation Army | 67 / 168 | 哇音 |
| 3 | 情歌 | 235 / 212 | 明亮弦音 |
| 4 | 待导入 | 空 | 导入时指定 |
| 5 | 待导入 | 空 | 导入时指定 |

只改变逻辑目录和显示映射，三个曲谱的音符/节奏/时长/推荐音色、物理RAM地址、全部ROM/字体字节保持。既有隐藏诊断记录仍在保留区，不再作为第五槽目录发布；共享导入区仍从703开始、容量1345条。4/5未导入不可选，QUERY返回空描述符；成功导入后显示对应USER4/USER5与RAM，按原有协议和原子提交机制选择/播放。断电/复位后恢复默认目录。其他槽仍可通过原协议覆盖导入。

生产改动为 `game_p3_default_catalog.v`、`game_p3_catalog.v`、`game_p2_mode_router.v`、`touch_game_ui.v`、`touch_game_renderer.v`，以及共享标题/进度表映射头 `game_p3_slot_map.vh`。同时调整选曲、准备、演奏和结果页标题/居中位置、进度条及命令拒绝规则。旧只读P2目录及其测试夹具保持原顺序，生产WRITABLE路径使用新顺序。

`build/song_slots_123/rtl_03` 已通过256目录案例/全部32种导入掩码、1958400像素/15场景对照（默认菜单精确换行、4/5相同待导入、每个USER行、准备/演奏/结果标题及半曲进度）、4和5槽分别17次真实UART请求/响应与CRC/RAM/CDC/QUERY导入前后验证。预览 `rtl_03/song_slots_123.png` 由RTL像素直接生成。01只因测试用了SV保留字作为实例名编译失败，02为增加半曲进度和空QUERY检查前的通过记录；均保留，不用它们替代当前03验证。

音色/四声部32状态/触控180°/MPU姿态、50/12.288/100MHz实际工作频率、物理引脚和保护配置保持。新构建使用原 `gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj` 和原impl。旧成功FS/输入清单/保护文件字节与index快照在 `build/song_slots_123/before/`，固定历史发布不覆盖；本轮记录与最终认证位于 `build/song_slots_123/`。不烧录/开COM/提交/推送。

首轮 `synth_01/route_01` 布通但实际STA失败：系统47.702MHz、KS91.271MHz、音频19.826MHz，33个setup违规、hold0。该FS `78164c86eb752fa8a1283f3173e7b30aebbf95d1e5ea2c69a03a7dee8da44bb7` 不能发布；报告和记录保留于 `route_01`、`candidate_01`。实际新网表 `full_gate_02` 已PASS：10982帧/10981PCM/4807275 LCD时钟，整页130560唯一菜单像素、三曲实际首音/推荐音色/地址/数量/时长、空4/5拦截，以及原四声部KS和五度开关。640块物理曲谱初始化已逐值核对。单独双完整RTL控制流程 `full_rtl_control_01` 同样通过，明确区别于实际网表证据。

为收敛时序，第二次 `route_02` 当时不修改任何RTL或已测VG，仅在原SDC追加系统/KS各0.500ns的setup保护预算；原周期、hold检查、CDC例外均保持。原SDC副本与试验追加块分别保留于 `before/source/constraints/neo_guitar_touch_game.sdc`、`setup_guard.sdc`，当时检查器要求试验SDC精确等于两者拼接。这是加严约束，不能用来掩盖首轮失败；最终仍要求实际50/12.288/100MHz及setup/hold全部合格。指令按[高云官方时序约束指南](https://cdn.gowinsemi.com.cn/SUG940E.pdf)的`set_clock_uncertainty -setup`语法。两个用户保护文件和原路由配置不变。

该约束试验最终剩127条网络未布通，已保留失败记录并撤销，原SDC逐字节恢复。后续改为KS计算内核的等价时序整理：利用既有stage8/10预先形成`first+previous`及总和，stage11只做原舍入；周期整数按高9位/半采样借位计算，容量比较显式9位，包含原有0/下溢语义。没有新增计算阶段或等待周期，也不改变32模型的持久状态、频率/增益/滤波/损耗规则。

`ks_pipeline_probe2` 通过32768次32模型上下文PCM逐值和busy逐周期对照（D3～G5、五度/延音/禁用/重触发），maxbusy仍176；周期计算穷举67108864组合全部相同。插值始终处于两端18位样本之间，因此19位加法重关联不溢出、舍入结果精确一致。`check_ks_pipeline_equivalence.py` 将原音色源、有限编辑、原型日志和当前生产源严格绑定。既有GUI/UART像素检查不加载KS，按完整依赖闭包复用；原音色试听/TDM通过这一相同输出/延迟边界组合复用，不冒称旧实际VG验证覆盖新网表。必须再完成新综合、P&R/STA和实际VG对照才交付。

最终 `synth_02/route_03/full_gate_03` 均已完成：实际sys/audio/KS Fmax为50.075/19.755/101.217MHz，满足50/12.288/100MHz，setup/hold违规均0；Logic50305、FF22978、CLS28482/29952、BSRAM118/118、DSP106.5/118。原两条PR1014按实际STA计入。新实际VG和当前RTL完整对照通过10982帧/10981PCM/4807275 LCD时钟、130560唯一菜单像素、三曲首音/元数据/音色、空4/5拒绝及四声部KS/五度开关；238条厂商RAM/PLL警告经源位置审阅、应用错误0。无SDF，另以完整实际布线STA验收。已测试VG/综合快照/当前VG逐字节相同，SHA256 `c1b9d13b2d38f1900067a03a99b730862d8139e62c2ca0ca7346f88992dcd7d0`。

原工程可用位流：`gowin/neo_guitar_touch_game/impl/pnr/neo_guitar_touch_game.fs`，SHA256 `59f3b31b111344b5aba31585de7ebb7071fcd77a9e63327744984fdcc1e315e3`。独立[新位流/报告包](../build/releases/touch_game/ks_fifth_v2_lcd180_slots123_20261102.zip)和[138文件纯源码包](../build/exports/neo_guitar_touch_game_ks_fifth_v2_lcd180_slots123_code_only_20261102.zip)；纯源码无README、报告、位流。严格入口`tools/check_song_slots_result.py publish`，本轮认证和归档清单位于`build/song_slots_123/verification.json`、`release_check.json`。原输入修复位流保留回退，本次未烧录/开COM/提交/推送，等待新槽位下板反馈。
