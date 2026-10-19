# Windows 曲谱上传软件

Windows 10/11 x64 便携桌面版，米白色背景、大幅淡吉他线稿横贯页面底部，三步引导。
使用现有 P3/P4 的 DEBUG-USB2 UART，不需要修改或重新生成 FPGA 位流。

## 开始使用

发布目录：`build/releases/windows/FPGA_Guitar_Uploader_1.0.0/FPGA_Guitar_Uploader/`。
同级 ZIP 为完整便携包。完整解压后双击 `FPGA_Guitar_Uploader.exe`，无需安装 Python。
请保留旁边的 `_internal` 和 `示例曲谱` 文件夹；不要从 ZIP 里只运行或拷贝 EXE。

1. 板子保持供电，DEBUG-USB2 接电脑，在琴上回到主页/选曲页。刷新并选择 COM，再点“检查设备”。不知道 COM 号时可拔插对照，或查看 Windows 设备管理器的“端口（COM 和 LPT）”。软件只枚举端口，点击检查/上传才打开所选端口。
2. 选择曲谱，等待本机校验。首次可选“打开示例曲谱”中的 `入门示例.csv`（8 秒），或 `情歌_60BPM.xgscore`（212 事件、152 秒、第二音色，已确认的第 10/18 小节修订节奏，CRC32 `c3451bbc`）。四轨图来自实际事件，表示整曲时间分布，不播放声音。
3. 推荐先选第 2 槽，点击“确认并上传”，核对曲名、音色和目标槽。进度按逐条 FPGA ACK 更新；提交成功后核对目录的槽号、valid/playable/imported 标志、数量、时长和音色才显示成功。在琴上选择对应 `USER n`，先试听，再开始练习。

导入曲保存在运行时 RAM，断电、复位或重新配置 FPGA 后丢失。拔 USB 时需保留独立供电。曲名暂不通过协议写入 FPGA，琴上仍显示 USER 1–5。

## 文件格式

| 格式 | 用法 |
| --- | --- |
| `.xgscore` | 与 P5 单文件包相同，含事件、元数据、CRC32、SHA256；直接打开。 |
| `.bin` + `.json` | 现有 v2 编译产物，同名放在一起；可选任一个。若 BIN 的 JSON 不同名，选择 BIN 后另选对应 JSON。 |
| `.csv` | UTF-8 音符事件表，支持分数拍或绝对 48 kHz 样本时间；留空全部 lane 时复用既有自动分弦器。 |

CSV 的 BPM 仅改变 `onset_beats` / `duration_beats` 列；`t_on_samples` / `duration_samples` 已经是绝对时间，BPM 不改变它们。CSV 可设置三种推荐音色。BIN/JSON/曲谱包保留文件的音色与节奏参数。完成校验后可“另存曲谱包”，必须使用新文件名，不覆盖已有曲谱。

完整列说明和模板见软件附带 `示例曲谱/CSV格式说明.txt`。支持 MIDI 50–79/D3–G5、最长 10 分钟、单首最多 1345 事件（五槽共享）；保留同弦不重叠、起音间隔、可见密度和原有临近音优先换弦规则。超限会明确拒绝，不自动删音或移调。图片、PDF、音频、通用 MIDI 不能直接上传，需先整理成事件表；仓库已有独立 MIDI 转换工具 `tools/import_p2_melody_midi.py`。

## 故障处理

- 找不到 COM：刷新，对照设备管理器，检查 DEBUG-USB2 的驱动与 USB 数据线。
- 无法打开：关闭占用该 COM 的串口助手或其他软件。
- 无有效响应：核对 COM、连接和支持 XG3 的当前位流。固定 115200/8N1，无流控；打开前将 DTR/RTS 置低。
- BUSY：退出演奏/试听/游戏，回主页或选曲页。
- NO_SPACE：五槽共享 1345 条；替换时旧导入区在提交前仍占空间，且需要连续新区域。软件不把总容量冒充可用空间。不自动复位琴；用户复位会清除所有导入曲。
- 取消：DATA 阶段允许取消，随后尝试 ABORT；若连接已断，暂存事务由 FPGA 超时释放。COMMIT 开始后等待最终结果，此时不能取消或直接关闭窗口。
- 提交结果未知：如果 COMMIT ACK 丢失或提交时断线，新曲可能已生效，不能报告回滚。软件在发送 COMMIT 前将记录持久写入本机；重启仍会提示“处理上次提交”，并禁止直接重传。可以继续检查设备，在琴上试听该槽。目录不含整曲 CRC，因此不会只靠数量/时长自动认定内容相同。实物核对或复位清空后，由用户明确清除记录。
- 已确认提交、回读失败：保留记录，说明 FPGA 已确认成功，重新查询/试听后再处理。

记录存于 Qt 返回的本机应用数据目录（组织名 `Xinxian`、应用名 `FPGAGuitarUploader`），文件为 `pending_commit.json`。软件有单实例锁，避免两个窗口同时使用该记录；无自动重传、断点续传或断电保存曲库功能。

## 源码、构建和验证

入口 `tools/run_windows_score_uploader.py`；界面和任务边界在 `tools/windows_score_uploader/`。
原协议 `tools/game_score_upload.py`、事件校验/分弦器保持字节不变。每次检查后关闭串口；上传重新握手/查询目录，目录较确认时变化则在 BEGIN 前拒绝。设备 IO 和文件编译在工作线程中，主窗口保持响应。曲谱校验失败立即清除旧就绪状态。

使用 Python 3.12 x64 建独立环境，安装 `tools/windows_score_uploader/requirements-build.txt`。仓库内环境示例：

```powershell
.\build\windows_uploader\venv\Scripts\python.exe -m unittest discover -s tools -p test_windows_score_uploader.py -v
.\build\windows_uploader\venv\Scripts\python.exe tools/build_windows_score_uploader.py
```

PyInstaller 在 `build/windows_uploader/pyinstaller/build.log` 留下构建日志。便携包附依赖许可、对应源码和 `manifest.json`，绑定每个源文件和分发文件哈希。冻结程序支持 `--smoke-test 输出目录`，不枚举/打开 COM，不触及用户配置，检查中文界面、示例校验、串口库加载并生成截图。PC 测试通过模型覆盖分片读写、噪声、丢 ACK 重试、BUSY/满库、取消、断线、COMMIT 不确定与重启锁定、目录变化及回读不符，并通过实际 Qt 控件驱动三步流程。

本批验证范围是 Windows 电脑端软件、协议模型及打包运行。没有向实物 COM 发送数据，没有代理烧录、修改 RTL/ROM/CST/SDC/原工程配置或重新综合布线。第一次实际串口上传和琴上试听由用户执行。
