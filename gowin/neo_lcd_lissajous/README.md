# 4.3 寸 480×272 RGB 莉萨如演示

适用：Tang Mega 60K `GW5AT-LV60PG484AC1/I0`、NEO Dock 31005，以及用户已用彩条测试点亮的 4.3 寸 RGB 屏。**保持 J17 的 1–2 针用跳帽连接，关闭共用 LCD 线路的 CH569。** 使用原来的 J5 40 针排线，无需 HDMI。6 针 GT911 触摸接口不参与本演示。

直接下载本目录 `impl/pnr/neo_lcd_lissajous.fs`。Gowin Programmer 中确认器件是 **GW5AT-60**，选择 **SRAM Program/Configure**，下载后会自动开始动画。GUI 工程为 `neo_lcd_lissajous.gprj`，顶层为 `neo_lcd_lissajous_top`。这份位流是独立显示演示；下载后 FPGA 运行显示程序，恢复音频时重新下载原正式音频位流。

画面包含全分辨率发光曲线、约 0.45 秒拖尾、沿曲线移动的白色亮点、流动彩虹配色、深蓝网格与星点。曲线比例自动在 **3:2 → 5:4 → 7:5 → 9:8** 之间切换，每种约 9.53 秒。相位不断变化，曲线会逐渐展开、收拢和变形。右上角显示 `LIVE/HOLD` 与当前比例，底部四段指示当前图形。

| 用户按键 | 原理图 / FPGA 球位 | 功能 |
| --- | --- | --- |
| KEY0 | S4 / AA13 | 按住复位并熄灭背光，释放清空拖尾、恢复初始动画 |
| KEY1 | S2 / AB13 | 切换到下一种曲线比例，自动轮换仍继续 |
| KEY2 | S1 / Y12 | 暂停/继续，右上角 `LIVE` 与 `HOLD` 切换 |

按下再松开，每次间隔至少 0.1 秒。暂停时保留图形和颜色，自动轮换也停止；正在完成的一帧可能显示后再冻结。暂停期间按 KEY1 的选择会在继续后生效。KEY2 在这份演示中已用于暂停，像素时钟保持已点亮测试的默认相位。

## 时序与接线

- V22 板载 50 MHz 晶振，整数六分频得到 DCLK=8.333333 MHz、50% 占空比；无 PLL、外部 DDR、MCU 或 HDMI 编码。
- 水平 SYNC/BACK/ACTIVE/FRONT = 4/39/480/8，总长 531。
- 垂直 SYNC/BACK/ACTIVE/FRONT = 4/8/272/8，总高 292；约 53.745 Hz。
- HSYNC、VSYNC 低有效，DE 高有效；RGB/DE/HS/VS 在 DCLK 下降沿更新，下一个上升沿前保留 60 ns。
- 每色输出 6 bit 接 J5 的 R2–R7、G2–G7、B2–B7；底板每色低两位已接地。DISP 第 31 针由底板接 3.3 V。

| 输出 | J5 针号 | FPGA 球位（按颜色低位到高位） |
| --- | --- | --- |
| R2–R7 | 7–12 | G18、G17、H22、J22、K22、K21 |
| G2–G7 | 15–20 | K18、L21、M21、M22、N22、L18 |
| B2–B7 | 23–28 | M18、N19、N18、K16、L16、M20 |
| DCLK | 30 | L19 |
| HSYNC / VSYNC / DE | 32 / 33 / 34 | N20 / L15 / L14 |
| 背光使能 | LP3320 EN | P20 |

三键使用 1.5 V IO，其余使用 3.3 V IO。JTAG 保持专用；I2C/SSPI 配置复用脚设为普通 IO，构建脚本已固定这些设置。屏幕点亮不代替背光电流匹配核对：P20 只控制使能，底板 R48 决定 LED 电流，仍需按到货屏实际规格确认。

## 构建与验证

在 Gowin 命令行运行：

```powershell
& 'S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe' 'T:\Documents\AMD\xinxian-fpga-guitar\gowin\neo_lcd_lissajous\build.tcl'
```

GUI 使用同样的顶层、器件与 I2C/SSPI 普通 IO 设置。文件可移植：工程中的源码路径均相对仓库根目录。

仿真使用 ModelSim：

```powershell
./run_sim.ps1 -ModelSimBin 'S:\BaiduNetdiskDownload\modelsim\win64'
```

13 个完整输出帧已核对：480×272 有效区、531×292 总长、120 ns 时钟周期、同步脉宽、消隐黑色、采样前稳定时间、双缓冲切换、写地址边界、手动/自动切换、防抖、暂停/继续及清空复位。仿真缩短上电/按键延时和自动切换间隔，扫描及绘图参数保持实际值。`temp/simulation/*.ppm` 为真实 RTL 输出逐像素采集；`check_result.py` 可将其转换为 PNG。

仓库显示默认参数已同步到 480×272：`rgb_spectrum_timing`、`spectrum_display_top`、`full_guitar_top`、`neo_full_guitar_top`；32 根频谱柱每槽 15 像素、柱宽 12 像素。四项原有显示/FULL 回归及新增默认参数整帧检查已通过。原正式音频功能、约束与位流保留；后来新增的只读显示观察端口不改变其行为。

本次 Gowin 实现：27 个端口的球位/IO 电平核对通过，setup/hold 零违例，目标 50 MHz 的实际 Fmax 为 54.651 MHz；逻辑 1171/59904、BSRAM 66/118、DSP 4/118。V22 仍有 PR1014 通用时钟输入路由告警，内部 STA 已通过；外部面板的精确 setup/hold 限值尚未提供。新演示仍待用户上板确认，既有彩条测试的物理引脚/时序已由用户验证。

运行 `python check_result.py` 可重新检查已生成的报告、配置、仿真日志、引脚和位流 SHA-256，结果写入 `verification.json`。完整检查还读取仓库 `sim/temp/` 中的五项显示回归日志。`impl/` 与 `temp/` 为本地生成产物，Git 已忽略，克隆仓库后重新构建。

双缓冲用于防止画面撕裂，占用 66 个 BSRAM。本演示保持独立，包含原来的自动图案和拖尾效果。
需要演奏联动时使用 [四弦莉萨如整合工程](../neo_guitar_lissajous/README.md)：以仅 4 BSRAM 的原分辨率逐行绘图保留完整音频，图形缩为居中的正方形。
现有 FULL 自动引脚位流仍不能直接下载到实物。
