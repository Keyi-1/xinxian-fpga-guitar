# 程序生成击弦瞬态试验

分支：`experiment/procedural-piano-hammer`；基线：`fb574a4`。
目标板卡仍为 Tang Mega 60K，GW5AT-LV60PG484AC1/I0、Device B。
本工程沿用已验收的四条渐变、环形频谱、150×150 莉萨如、曲线渐暗和松品续音。

## 下载与构建

本次只构建这个独立目录，输出 `impl/pnr/neo_guitar_procedural.fs`。
已验收的 `neo_guitar_radial` 位流和下载别名不被本构建覆盖。
LCD 接线、J17 1–2、输入双 PCB、PT8211、音箱供电和三键操作均沿用原方案。
共享音源 RTL 在本试验分支中已替换，重新构建本分支的旧工程也会采用新音源。

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

全部保持原增益和 48 kHz 立体声，不归一化、不额外添加软件音效。
序列含四档力度、四音、松品、快速重拨、延音、合唱、混响、亮弦和 wah。
起音波形会改变；瞬态结束后的主体和纯亮弦/wah 输出按样本比较，
旧版参考只用于仿真。最终听感与上板验收仍需要实物确认。

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
```

常规构建不需要原录音、历史残差或科学计算环境。
`tools/generate_piano_assets.py` 现在只输出模态参数与幅度包络。
`tools/fit_procedural_hammer.py` 是可选的离线频谱/RMS 参数拟合，
写出的始终是少量系数和标量，绝不生成可回放的声音样本表。
