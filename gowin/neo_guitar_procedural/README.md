# 程序生成击弦瞬态试验

分支：`experiment/procedural-piano-hammer`；基线：`fb574a4`。
目标板卡仍为 Tang Mega 60K，GW5AT-LV60PG484AC1/I0、Device B。
本工程沿用已验收的四条渐变、环形频谱、150×150 莉萨如、曲线渐暗和松品续音。

## 下载与构建

本次只构建这个独立目录，输出 `impl/pnr/neo_guitar_procedural.fs`。
已验收的 `neo_guitar_radial` 位流和下载别名不被本构建覆盖。
LCD 接线、J17 1–2、输入双 PCB、PT8211、音箱供电和三键操作均沿用原方案。
共享音源 RTL 在本试验分支中已替换，重新构建本分支的旧工程也会采用新音源。

直接下载已核对的文件可使用仓库
`build/releases/procedural_piano/neo_guitar_procedural_c5e58ec.fs`，
SHA256 为 `ba16d65fedfd658a2a640be6b87c34153ff9d3f87b55db502a9ddfce95b8c4f4`。
该文件独立于 IDE 的临时输出，可在 Gowin Programmer 中加载，无须先重新编译。

### 在 IDE 中编译

IDE 不会自动读取 `build.tcl` 的选项。本工程将
`impl/neo_guitar_procedural_process_config.json` 加入版本管理：
Place Option=4、Route Option=2、Clock Route Order=1，Correct Hold Violation 开启。
2026-10-13 的 IDE 默认 0/0/0 构建曾出现 804 条未布通网络；同一 RTL 的
4/2/1 布局已布通并通过原时钟约束。资源尚有余量也可能遇到布线拥塞。

请先关闭该工程，运行本目录的 `configure_ide.ps1`，再重新打开
`neo_guitar_procedural.gprj`。在 Configuration > Place & Route 核对上述三项。
运行脚本可避免 IDE 在关闭时把缓存的旧配置写回；脚本保留其他设置。
失败的 PnR 不会生成新位流，输出目录中的旧 `.fs` 或时序报告不能代表本轮成功。

```powershell
# 当前目录：gowin/neo_guitar_procedural
& 'S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe' build.tcl *> build_console_shared_lp.log
# 该脚本指定 Top=neo_guitar_radial_top、两个原时钟约束和原引脚。
```

最终资源、setup/hold、Fmax、引脚、位流 SHA256 与仿真结果记录在
`verification.json`，由 `check_result.py` 检查后生成。
构建使用布局选项 4、布线选项 2、按时钟频率排序，保留原 SDC/CST 与 hold 修复。
本次物理结果：Logic 47596/59904，Register 18674/60780，BSRAM 86/118，
DSP 115.5/118；音频/系统 Fmax 为 14.148/52.895 MHz，setup/hold 均为 0。
滤波器时分复用每声部已有的模态 DSP，音源调度仍为 233/256 个时钟；
三组 2048 点录音残差 ROM 已退出生产源文件和工程资源列表。

## 试听与验收

生成的 WAV 在仓库 `build/procedural_piano/`：

- `piano_ab_old_then_new.wav`：旧版 2.833 秒，静音 0.5 秒，再新版 2.833 秒。
- `piano_attack_ab_pairs.wav`：三个独立单音及四音和弦，各段按“旧、静音、新”排列。
- `procedural_hammer.wav`：新版实际完整 RTL 输出，可单独播放。

上述和弦段来自功能压力测试：四个声部同时拨弦，在起音后约 0.292 秒
松品滑回空弦，0.375 秒开启音效，0.417/0.425 秒重拨。因此其中的音高
变化是测试指令产生的，不适合作为固定三音和弦的听感对照。

针对这一问题，另提供 `build/procedural_piano/static_triad/`：

- `piano_C4_E4_G4_dry_ab.wav`：固定 C/E/G 三音，每版 2 秒，先旧后新。
- `piano_fixed_notes_dry_ab.wav`：C、E、G 单音及三音和弦，逐组先旧后新。
- 各音独立的旧/新 WAV 可用于比较泛音与齐奏，不修改原增益或追加软件效果。

这组使用实物默认力度 2，关闭和声、合唱、混响、延音，不松品或重拨。
三单音相加与齐奏的差异最多 1 个 PCM16 量化单位，没有削波；
起音后从第 2112 帧（44 ms）起，新旧最终干声逐样本一致。
用户已确认这组对照中原先的“额外声音”消失，生产音源 RTL 无需因此改变。

全部保持原增益和 48 kHz 立体声，不归一化、不额外添加软件音效。
序列含四档力度、四音、松品、快速重拨、延音、合唱、混响、亮弦和 wah。
起音波形会改变；瞬态结束后的主体和纯亮弦/wah 输出按样本比较，
旧版参考只用于仿真。2026-10-13，采用同一击弦模型、增加标准 I²S 输出的
[neo_guitar_i2s 整机工程](../neo_guitar_i2s/README.md)已通过用户下板验收，现为当前入口。

不要将 `sim/reference/piano_legacy/` 加入 FPGA 工程或作为参赛音源。
赛题对应条款、模型、固定点和复用时序见
[实现说明](../../docs/PROCEDURAL_PIANO_HAMMER.md)。

## 重现检查

```powershell
# 仓库根目录；独立仿真工作库与哈希证据，黄金模型仅需 Python 标准库。
& '.\tools\run_procedural_piano_checks.ps1' -ModelSimBin 'S:\BaiduNetdiskDownload\modelsim\win64' `
  -PythonExe 'E:\anaconda3\python.exe'
# 从真实 RTL PCM 导出试听需要 NumPy、SciPy、Matplotlib。
& 'E:\anaconda3\python.exe' tools/generate_procedural_piano_preview.py
& '.\gowin\neo_guitar_procedural\run_gate_check.ps1' `
  -ModelSimBin 'S:\BaiduNetdiskDownload\modelsim\win64'
& 'E:\anaconda3\python.exe' gowin/neo_guitar_procedural/check_result.py
# 固定三音专项试听；与原压力回归使用独立工作目录。
& '.\tools\run_static_piano_diagnostic.ps1'
& 'E:\anaconda3\python.exe' tools/generate_static_piano_diagnostic.py
```

若 IDE 失败构建覆盖了当前报告，可以保留该失败现场，并核对本机保存的
成功布局：

```powershell
& 'E:\anaconda3\python.exe' gowin/neo_guitar_procedural/check_result.py `
  --implementation-root gowin/neo_guitar_procedural/temp/place4/impl `
  --build-log gowin/neo_guitar_procedural/temp/place4/build_console.log
```

该路径是本机的历史构建缓存；新检出仓库仍需正常构建及运行网表检查。

常规构建不需要原录音、历史残差或科学计算环境。
`tools/generate_piano_assets.py` 现在只输出模态参数与幅度包络。
`tools/fit_procedural_hammer.py` 是可选的离线频谱/RMS 参数拟合，
写出的始终是少量系数和标量，绝不生成可回放的声音样本表。
