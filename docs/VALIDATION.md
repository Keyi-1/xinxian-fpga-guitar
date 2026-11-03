# 当前版本与验证范围

当前配套版本：2026-11-02 双接口 FPGA 位流、Android0.3.0、Windows1.2.0。2026-11-04 整理仅迁移归档、重写文档、调整测试路径及构建入口，最终140份 FPGA 输入和已发布二进制保持原字节。

用户已在本次整理前确认 **DEBUG-USB2 串口与 JDY-23 蓝牙传谱均实物验收成功**。这是用户报告的板上验收结果，与之前冻结的数字验证收据分开记录；旧收据中的“尚未实测”是其生成时的状态，保留原文。

## 数字验证

| 范围 | 冻结结果 |
| --- | --- |
| RTL 协议与双接口 | 1025帧、643命令的冻结解析器/直接回放等价；真实双波特率事务、帧边界与错误处理 |
| 查询 TDM | 77帧、32组并发不同槽查询；相同会话与序号的缓存和错误上下文隔离 |
| 实际网表与完整 RTL 音频/菜单 | 10982音频帧、10981 PCM、4807275 LCD时钟、130560菜单像素；三内置曲、两空槽、四声部和五度开关 |
| 实际网表串口 | 15个 UART 事务；显式计时加速及输入刺激边界见原记录 |
| 布局布线 / STA | Logic50937、FF23686、CLS28807、BSRAM118、DSP106.5；setup/hold/latch/未布通0 |
| Android 界面 | API35五种屏幕场景，共195项检查 |
| Windows | 原发布34项回归、冻结EXE冒烟、依赖与分发源码核对 |
| 跨端曲谱 | 三首示例25+564+491=1080事件，Android/Windows逐字节相同 |

最终 FPGA 原始收据位于 [verification.json](../verification/build/dual_score_transport/verification.json)，其同目录包含 `rtl_10`、`query_tdm_02`、`full_gate_03`、`uart_gate_04`。客户端原始收据位于 [companion_ui/verification.json](../verification/build/companion_ui/verification.json)。完整资源、时序报告随[固定 FPGA 包](../releases/fpga/verified_release_20261102.zip)保存。

门级功能仿真没有 SDF 回标，实际时序单独由完整 P&R/STA 验收。保留两条已审阅 PR1014 时钟提示，并按实际布线报告检查时序。上述记录不代表硬件长期稳定性、所有外接 DAC 或所有手机型号的专项测量。

## 哈希与回退

| 文件 | SHA256 |
| --- | --- |
| 当前FS | `d0b0cee2425e11b0b0ec6720132c80bdaf9b2a5224d5974e321e01db0bdcb763` |
| 当前实际综合网表 | `04bd6d5a989979f870490bda3b6caf71c352be80044b69cd619d58524f0add6a` |
| Android APK | `9f685e9bb056fefa3e6428698f7bf85f3ddcc173306d43e5b395c6e9aed7f974` |
| Windows ZIP | `6410a8ca7dc1b3f2a980dfe69185711e249beca9711b3bc64b15df6a4605437e` |
| 上一成功槽位版FS | `59f3b31b111344b5aba31585de7ebb7071fcd77a9e63327744984fdcc1e315e3` |

[SHA256SUMS](../releases/SHA256SUMS)覆盖当前分发文件，[source_manifest.json](../releases/fpga/source_manifest.json)列出140份原工程输入。历史固定 ZIP 和认证记录统一放在 `verification/build/`，已受 Git 管理的归档仍随仓库保存。旧版本也可从对应 Git 提交获取；本地生成缓存、完整 WAV 和大规模仿真中间产物不作为 Git 分发内容。

目录迁移逐文件校验字节，原始收据不改写内部绝对路径或 HEAD。迁移表位于 [relocations.json](../verification/organization/relocations.json)。新构建必须产生自己的功能、网表和 STA 证据。

生产 FPGA 文件通过 `.gitattributes` 关闭自动换行转换，使新克隆也能逐字节匹配实际构建输入。客户端源文件与旧打包清单的比对只允许已知文本文件精确的 LF/CRLF 转换，二进制资源与安装包仍做严格原始字节校验。
