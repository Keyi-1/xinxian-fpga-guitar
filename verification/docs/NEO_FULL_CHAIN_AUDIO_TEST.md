# 双 PCB 全链路上板验证工程

日期：2026-10-03。当前为**双 PCB 同接实物通过，用户确认测试结果理想**。功能实物结论来自用户反馈；未新增定量声学测量。

同一行为现已同步到正式主工程，入口与说明见 [主工程同步](MAIN_ENGINE_SYNC.md)。本独立验证源码作为成功基线保留。

打开 `gowin/neo_full_chain_audio_test/neo_full_chain_audio_test.gprj`，顶层为
`neo_full_chain_audio_test_top`，器件为 `GW5AT-LV60PG484AC1/I0`、Version B。
工程内已平铺全部源码、CST、SDC 和两份 ROM 初始化文件，可以独立构建。

## 1. 采用的已验证基础

- GitHub 最新提交与本地 HEAD 均为 `2cb7419`：复用 `gowin/test3/src` 的
  `mcp3208_spi`、`mcp3208_four_channel_reader`、`four_string_pluck_detector`。
- 音频采用 `27cace8` 中实物通过的 `neo_four_string_matrix_audio_test` 版本：
  四个并行正弦声部、自然拨弦包络、动态左右硬分离、每声道除以二、
  PCM24→PCM16→PT8211，以及复位后功放常开。
- 复用品位扫描、防抖和音高表；滑音复用仓库的 `phase_slide_smoother`。
- 音频与矩阵的 12 份辅助文件、ADC 的 3 份辅助文件与对应已验证来源逐字节一致。
  新增演奏控制和顶层负责整合；原先两个实物工程没有修改。
- 两个工程的 `guitar_config.vh` 存在 ADC 分频差异：矩阵版为 25，`test3` 为 4。
  本工程明确采用 `test3` 的 4，实际 SCLK 为 12.288 MHz / (2×4) = **1.536 MHz**。
  原配置中的 `ADC_SPI_HZ=1000000` 只是未参与硬件运算的旧标记；此副本已改为实际值。

## 2. 演奏规则

1. 左手按品只更新该弦的最高品位，静音弦不会因此发声。没有按品为第 0 品。
2. MCP3208 CH0～CH3 分别触发 ROW0～ROW3，即第 1～4 弦 E4/B3/G3/D3。
   ADC 与矩阵的物理弦序必须对应。
3. 真正的压电触发被保存到下一次音频 sample tick，按当前已去抖的品位产生 Attack。
   发生在 sample tick 上的事件也会消费，不会丢失或重复触发。
4. 每根弦绑定一个独立声部。再次拨同一弦会重启该声部的包络，不打断其余弦。
5. 活跃弦的非零最高品位发生变化时，按 960 个音频采样、约 20 ms 平滑滑音，
   不重新产生 Attack。松开最高品但仍按较低品时，滑向剩余最高品。
6. 释放最后一个品位时，冻结当时的实际相位增量并进入快速 Release；
   不把正在衰减的尾音跳到空弦。随后再次拨弦才会发出空弦。
7. Release 尾音期间重新按品不产生无拨弦击弦；需要新拨弦才重启。
   空弦正常响音期间按品可以改变其音高，而不会重启包络。
8. 同一采样边界同时出现松品和拨弦时，拨弦优先，使用当时的选品。
9. 删除了矩阵测试的 30 ms 捕获窗口。扫弦保留真实四通道事件的先后关系。
   按品后需要经过矩阵去抖；过早拨弦会使用上一次稳定品位，这是既定输入规则。
10. 新启动声部按当前较少声部的一侧分配，第一对声部左右分离。
    活跃声部重拨时保持声道，四声部最多每侧两个，Release 尾音也计入占用。

本次使用矩阵工程已听音验证的固定力度 **2**。`test3` 也是固定力度检测；
四级力度标定、32 分量谐波、音效、FFT/LCD 和揉弦手势不在本验证工程中启用。

## 3. 引脚结论与接线

**没有冲突，可以同时沿用两套最新实物测试接线。**
合并后的 CST 共 26 个唯一球位；两个来源中共用的时钟、复位、DAC 和 PA
仅声明一次。实际布局布线 Pin Report 已逐项与 CST 核对一致。

当前矩阵使用 J13，不使用早期 ROW0/PMOD1 的列接法。
旧文档 `NEO_31005_60K_PIN_MATRIX.md` 中 PMOD 矩阵候选表不适用于本工程。

### 矩阵板：沿用 J13

| 矩阵信号 | PCB H1 | NEO J13 | FPGA 球位 |
| --- | ---: | ---: | --- |
| ROW0 | 3 | 1 | E14 |
| ROW1 | 4 | 2 | E13 |
| ROW2 | 5 | 3 | C15 |
| ROW3 | 6 | 4 | C14 |
| COL0 | 7 | 5 | B13 |
| COL1 | 8 | 6 | C13 |
| COL2 | 9 | 7 | A14 |
| COL3 | 10 | 8 | A13 |
| COL4 | 11 | 18 | B21 |
| COL5 | 12 | 17 | A21 |
| COL6 | 13 | 16 | B20 |
| COL7 | 14 | 15 | A20 |

矩阵 H1-1 接 3.3 V（如 J8-1/J9-1），H1-2 接 GND（如 J13-12）。
J13-11 是 5 V，不能接矩阵 3.3 V 电源。列线沿用 PCB 外部上拉；
行线只输出低电平或高阻。J13 同时不接 SDRAM0 模块。

### MCP3208 板：沿用 test3 的 PMOD1

| 本工程端口 | ADC 板信号 | NEO J8 | FPGA 球位 |
| --- | --- | ---: | --- |
| adc_cs_n | CS | 7 | AA20 |
| adc_sclk | CLK | 8 | AA21 |
| adc_mosi | DIN | 5 | AA19 |
| adc_miso | DOUT | 6 | AB20 |

MOSI 对 ADC 的 DIN，MISO 对 ADC 的 DOUT。电源、参考电压和模拟前端保持
`test3` 已通过的接法，两块 PCB 与 Mega 60K 共地。保持板上数字接口为 3.3 V。
PMOD1 与 SDRAM1/DVP 复用的相应信号不能同时接其他有源外设。

### 板载音频、复位与可选调试 LED

| 信号 | FPGA 球位 | 说明 |
| --- | --- | --- |
| audio_clk_12m288 | V13 | 已配置的 MS5351M CLK2 12.288 MHz |
| rst_n | AA13 | KEY0，低有效，LVCMOS15；其余信号 LVCMOS33 |
| dac_bclk / dac_lrck / dac_din | Y17 / AB17 / AA16 | 板载 PT8211 |
| pa_en_n | AB16 | 复位时 1；复位释放后一直 0 |
| event_led[0..3] | P16 / R17 / R18 / T18 | 与 test3 一致，低有效，约 0.1 s |

四路 LED 对应 PMOD0 J9-7/J9-8/J9-5/J9-6，是可选外接诊断信号；
没有 LED 时不影响演奏链路。只按品不会点亮拨弦 LED。

## 4. 默认参数与调参位置

在 `src/neo_full_chain_audio_test_top.v` 参数区调整，重新构建后生效。

| 参数 | 默认值 | 含义 |
| --- | ---: | --- |
| MATRIX_CLK_DIV / SETTLE / DEBOUNCE | 768 / 3 / 5 | 约 1 ms 整帧，五帧一致后更新选品 |
| ADC_SPI_CLK_DIV | 4 | 保留 test3 的 SPI 时序 |
| ADC_BASELINE_CODE | 2053 | 已验证的静止 ADC 基线 |
| TRIGGER_THRESHOLD / REARM_THRESHOLD | 100 / 30 | 对基线绝对偏差的触发/再武装阈值 |
| PLUCK_DEAD_SAMPLES / SETTLE_SAMPLES | 400 / 80 | 每通道计数，保留 test3 的防连击处理 |
| AUDIO_SAMPLE_DIV / PT8211_REF_DIV | 256 / 4 | 48 kHz PCM，1.536 MHz BCLK |
| SLIDE_SAMPLES | 960 | 20 ms 滑音 |
| FIXED_VELOCITY | 2 | 已听音验证的固定音量 |
| PLUCK_ATTACK_SAMPLES | 96 | 2 ms 起音 |
| PLUCK_FAST_DECAY_SAMPLES | 9600 | 200 ms 初始自然衰减段 |
| PLUCK_FAST_SHIFT / SLOW_SHIFT | 13 / 16 | 与优化版一致的自然尾音 |
| PLUCK_RELEASE_SHIFT / IDLE_LEVEL | 10 / 64 | 松品快速阻尼与静音门槛 |

ADC 不自动估计各通道基线，也不做力度标定。默认基线来自已通过实物验证的
`test3`。若某一路静止时即触发，先检查线束、共地和该路 ADC 静止码。

保留了已验证 reader 的位对齐补偿 `{spi_sample_data[10:0], 1'b1}`：
传输没有采到真正 B0，输出最低位固定为 1，静止基线与阈值均沿用该数据格式。
仿真用真实 ADC 的 null/B11～B0 时序覆盖了此行为。
时序参考 [Microchip MCP3204/3208 数据手册，图 5-1](https://ww1.microchip.com/downloads/aemDocuments/documents/APID/ProductDocuments/DataSheets/21298e.pdf)。
本次不更换 SPI 实现，便于上板结果与 test3 比较；以后若修复精确 12-bit 采样，
应同步重新检查基线、阈值、SPI 时序并单独实物验证。

## 5. 构建与下载

已生成位流：`gowin/neo_full_chain_audio_test/impl/pnr/neo_full_chain_audio_test.fs`。
验证证据和哈希见 `docs/evidence/neo_full_chain_audio_acceptance.txt`。

Gowin IDE 打开本工程，确认 Top 为 `neo_full_chain_audio_test_top`，然后执行
Synthesize → Place & Route。命令行也可在工程目录运行：

```powershell
& 'S:\BaiduNetdiskDownload\GOWIN\Gowin_V1.9.12.03_x64\IDE\bin\gw_sh.exe' build.tcl
```

ROM 文件放在 `src`，不要单独移动源码。工程已经带上专用 CST/SDC，
不再添加其他工程的约束。现有 MS5351M 12.288 MHz 配置继续使用。

首次双板联调先下载本工程 `.fs` 到 FPGA SRAM；可以沿用保守的 2 MHz JTAG。
本次代码工作没有自动烧录 FPGA，也没有更改 MS5351M 配置。

## 6. 本次验证与实物验收

ModelSim 用 `run_sim.ps1` 直接编译本工程源码，三组回归均通过，编译和运行
Errors=0、Warnings=0。主回归对扫描、ADC、包络计数进行加速；默认时序回归
不覆盖参数，使用 12.288 MHz 时钟复核 48 kHz、PT8211 和默认矩阵/ADC 行为。
完整记录见 evidence 文件。复现：

```powershell
cd T:\Documents\AMD\xinxian-fpga-guitar\gowin\neo_full_chain_audio_test
.\run_sim.ps1
# 若 vsim 不在 PATH：
.\run_sim.ps1 -ModelSimBin 'S:\BaiduNetdiskDownload\modelsim\win64'
```

双板实物验收按以下顺序记录结果：

1. 断电接线，两板共地；检查弦序 CH0↔ROW0 至 CH3↔ROW3。
2. 上电与释放 KEY0 后保持静音。只按矩阵，不拨压电，仍应静音且无拨弦 LED。
3. 不按品依次拨四路压电：E4、B3、G3、D3，LED 与弦序一致。
4. 同一弦从第 1 到 8 品，每次先按稳、再拨弦，确认音高递增。
5. 按四弦不同品位后扫弦，四个声部同时保留；扫描不造成周期断音。
6. 检查全部六种双弦组合，尤其 0+2 与 1+3，第一对声音应左右分离。
7. 发声中改品，听到平滑音高变化，起音不重复；保留较低品并松开最高品时同样滑音。
8. 松开某弦最后一个品位，只该弦衰减加快，尾音不跳到空弦；随后拨该弦产生空弦。
9. 按住品位等待自然静音，不能自行重新发声；重拨后可以再次起音。
10. 普通音符之间功放保持开启；区分重新配置/释放 KEY0 的单次启动瞬态
    与每次拨弦都发生的爆音。真实模拟延迟和听感由本次双板实物测试确认。

没有双板实测记录前，不把本工程标记为整机实物通过。
