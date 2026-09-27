# Tang Mega NEO Dock 31005 / Mega 60K 板级连接矩阵

更新日期：2026-09-27

## 1. 适用硬件与使用规则

| 项目 | 状态 |
| --- | --- |
| NEO Dock | `31005`，实物已确认 |
| Tang Mega 60K 核心板 | `30353` 或 `30354`，核心板被底板遮挡，暂时无法确认 |
| FPGA | `GW5AT-LV60PG484AC1/I0`，PG484 |
| Bank 1 | **禁止分配**，在核心板版本确认前不依赖其供电状态 |
| LCD | 尚未购买；只记录接口事实，不冻结 LCD 引脚与时序 |
| 现有自动引脚 `.fs` | **禁止烧录** |

本表是正式 CST/SDC 的前置真值表。信息优先级依次为：实物测量、NEO Dock 31005 原理图、30353 与 30354 两份核心板原理图的共同部分、官方 60K CST、当前 RTL 端口。任一来源不一致时保持 `TBD`，不得猜测。

状态定义：

- `CONFIRMED`：31005 原理图、两版核心板共同部分和官方 CST 可以相互印证；
- `MEASURED`：除 `CONFIRMED` 外，已在实物上完成指定测量；
- `PROPOSED`：电压、Bank 和复用检查通过的安全候选分配，尚待实际线束确认；
- `BLOCKED`：存在尚未解决的硬件资源冲突；
- `DEFERRED`：本阶段不进入正式 CST。

## 2. 固定板载接口

| RTL 顶层端口/功能 | 方向/有效电平 | 底板器件或连接器 | 底板网络 | BTB | FPGA 球位 | 实际 Bank | VCCIO / IO_TYPE | 复用与限制 | 状态 |
| --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- |
| `sys_clk_50m` | 输入，50 MHz | 核心板 Y1100 有源晶振 | `EMCCLK_50Mhz` | 核心板内部 | V22 | 7 | 3.3 V / LVCMOS33 | 固定板载时钟 | `CONFIRMED` |
| `audio_clk_12m288` | 输入，12.288 MHz | NEO Dock MS5351M U7 `CLK2` | `USR_CLK_IN` | J2-88 | V13 | 7 | 3.3 V / LVCMOS33 | CLK2 经 2.2 ohm 与 100 nF 串联耦合；仍需确认断电重启后无需上位机或 BL616 运行时配置 | `MEASURED`：CLK2 对 GND 示波器实测 12.288 MHz |
| `dac_bclk` | 输出 | PT8211-S U16 pin 1 | `I2S_BCLK` | J2-26 | Y17 | 7 | 3.3 V / LVCMOS33 | 板载音频专用 | `CONFIRMED` |
| `dac_lrck` | 输出 | PT8211-S U16 pin 2 | `I2S_LRCK` | J2-28 | AB17 | 7 | 3.3 V / LVCMOS33 | 板载音频专用 | `CONFIRMED` |
| `dac_din` | 输出 | PT8211-S U16 pin 3 | `I2S_DIN` | J2-30 | AA16 | 7 | 3.3 V / LVCMOS33 | 板载音频专用 | `CONFIRMED` |
| `pa_en_n` | 输出，低有效 | 功放 U20 | `PA_EN` | J2-36 | AB16 | 7 | 3.3 V / LVCMOS33 | `1`=功放关闭，`0`=功放开启；复位和空闲保持高 | `CONFIRMED` |

### 2.1 板载按键资源

| 底板按键 | 电气语义 | 底板网络 | BTB | FPGA 球位 | 实际 Bank | VCCIO / IO_TYPE | 可分配 RTL 功能 | 状态 |
| --- | --- | --- | --- | --- | ---: | --- | --- | --- |
| S4 / USER_BUTTON0 | 按下接地，需内部上拉 | `EX_KEY.0` | J2-60 | AA13 | 9 | 1.5 V / LVCMOS15 / PULL_UP | `rst_n`、`key_timbre_n`、`key_chorus_n`、`key_sustain_n` 四者之一 | `BLOCKED`：逻辑映射未冻结 |
| S2 / USER_BUTTON1 | 按下接地，需内部上拉 | `EX_KEY.1` | J2-62 | AB13 | 9 | 1.5 V / LVCMOS15 / PULL_UP | 同上 | `BLOCKED`：逻辑映射未冻结 |
| S1 / USER_BUTTON2 | 按下接地，需内部上拉 | `EX_KEY.2` | J2-64 | Y12 | 9 | 1.5 V / LVCMOS15 / PULL_UP | 同上 | `BLOCKED`：逻辑映射未冻结 |
| SW7 | 配置/重配置按钮 | `BANK10_N12_RECONFIG` | J0-61 | N12 | 配置专用 | 配置专用 | 不作为普通用户复位或功能键 | `CONFIRMED`：禁止分配为普通 GPIO |

当前 `neo_full_guitar_top` 需要 `rst_n` 加三个独立功能键，共四路输入；底板只有三枚普通用户按键。正式 CST 前必须从以下方案中明确选择一种：增加外部按键、改变复位来源，或经过单独需求评审后修改交互方式。现在不在 RTL 中猜测解决方案。

## 3. PMOD0/PMOD1 安全候选分配

下面的分配避开 Bank 1，并且每个球位都由两版核心板共同部分与官方 60K CST 的 3.3 V 配置支持。它使用两组 PMOD 的全部 16 根 GPIO：4 根矩阵行、8 根矩阵列和 4 根 MCP3208 SPI。确认线束之前状态保持 `PROPOSED`。

### 3.1 4x8 琴颈矩阵

| RTL 顶层端口 | 方向/驱动 | 底板连接器针脚 | 底板网络及复用 | BTB | FPGA 球位 | 实际 Bank | VCCIO / IO_TYPE | 状态 |
| --- | --- | --- | --- | --- | --- | ---: | --- | --- |
| `fret_row_n[0]` | inout；仅低电平或高阻 | J9-11 / PMOD0_IO0 | `SDRAM1_D1` / SDRAM1、DVP、PMOD | J0-25 | P19 | 7 | 3.3 V / LVCMOS33 | `PROPOSED` |
| `fret_row_n[1]` | inout；仅低电平或高阻 | J9-12 / PMOD0_IO1 | `SDRAM1_D0` / SDRAM1、DVP、PMOD | J0-23 | R19 | 7 | 3.3 V / LVCMOS33 | `PROPOSED` |
| `fret_row_n[2]` | inout；仅低电平或高阻 | J9-9 / PMOD0_IO2 | `SDRAM1_D3` / SDRAM1、DVP、PMOD | J0-15 | T21 | 7 | 3.3 V / LVCMOS33 | `PROPOSED` |
| `fret_row_n[3]` | inout；仅低电平或高阻 | J9-10 / PMOD0_IO3 | `SDRAM1_D2` / SDRAM1、DVP、PMOD | J0-13 | U21 | 7 | 3.3 V / LVCMOS33 | `PROPOSED` |
| `fret_col_in_n[0]` | 输入，低有效 | J9-7 / PMOD0_IO4 | `SDRAM1_D5` / SDRAM1、DVP、PMOD | J0-20 | P16 | 6 | 3.3 V / LVCMOS33 | `PROPOSED` |
| `fret_col_in_n[1]` | 输入，低有效 | J9-8 / PMOD0_IO5 | `SDRAM1_D4` / SDRAM1、DVP、PMOD | J0-18 | R17 | 6 | 3.3 V / LVCMOS33 | `PROPOSED` |
| `fret_col_in_n[2]` | 输入，低有效 | J9-5 / PMOD0_IO6 | `SDRAM1_D7` / SDRAM1、DVP、PMOD | J0-14 | R18 | 8 | 3.3 V / LVCMOS33 | `PROPOSED` |
| `fret_col_in_n[3]` | 输入，低有效 | J9-6 / PMOD0_IO7 | `SDRAM1_D6` / SDRAM1、DVP、PMOD | J0-12 | T18 | 8 | 3.3 V / LVCMOS33 | `PROPOSED` |
| `fret_col_in_n[4]` | 输入，低有效 | J8-11 / PMOD1_IO0 | `CAM0_VSYNC` / `SDRAM1_A11` / 摄像头、SDRAM1、PMOD | J2-5 | Y21 | 8 | 3.3 V / LVCMOS33 | `PROPOSED` |
| `fret_col_in_n[5]` | 输入，低有效 | J8-12 / PMOD1_IO1 | `CAM0_RST` / `SDRAM1_A9` / 摄像头、SDRAM1、PMOD | J2-3 | Y22 | 8 | 3.3 V / LVCMOS33 | `PROPOSED` |
| `fret_col_in_n[6]` | 输入，低有效 | J8-9 / PMOD1_IO2 | `CAM0_HSYNC` / `SDRAM1_A8` / 摄像头、SDRAM1、PMOD | J2-9 | AB21 | 8 | 3.3 V / LVCMOS33 | `PROPOSED` |
| `fret_col_in_n[7]` | 输入，低有效 | J8-10 / PMOD1_IO3 | `CAM0_PWDN` / `SDRAM1_A7` / 摄像头、SDRAM1、PMOD | J2-7 | AB22 | 8 | 3.3 V / LVCMOS33 | `PROPOSED` |

### 3.2 MCP3208 SPI

| RTL 顶层端口 | 方向 | 底板连接器针脚 | 底板网络及复用 | BTB | FPGA 球位 | 实际 Bank | VCCIO / IO_TYPE | 状态 |
| --- | --- | --- | --- | --- | --- | ---: | --- | --- |
| `adc_cs_n` | 输出，低有效 | J8-7 / PMOD1_IO4 | `CAM0_D7` / `SDRAM1_A6` / 摄像头、SDRAM1、PMOD | J2-13 | AA20 | 7 | 3.3 V / LVCMOS33 | `PROPOSED` |
| `adc_sclk` | 输出 | J8-8 / PMOD1_IO5 | `CAM0_MCLK` / `SDRAM1_A5` / 摄像头、SDRAM1、PMOD | J2-11 | AA21 | 7 | 3.3 V / LVCMOS33 | `PROPOSED` |
| `adc_mosi` | 输出 | J8-5 / PMOD1_IO6 | `CAM0_D6` / `SDRAM1_A4` / 摄像头、SDRAM1、PMOD | J2-17 | AA19 | 8 | 3.3 V / LVCMOS33 | `PROPOSED` |
| `adc_miso` | 输入 | J8-6 / PMOD1_IO7 | `CAM0_PCLK` / `SDRAM1_WE` / 摄像头、SDRAM1、PMOD | J2-15 | AB20 | 8 | 3.3 V / LVCMOS33 | `PROPOSED` |

采用该分配时，`SDRAM1`、DVP 摄像头、J14 2x20 SDRAM1 排针与 PMOD0/1 不得同时使用。MCP3208 使用 3.3 V 供电；四路压电模拟前端连接 MCP3208 的模拟通道，不直接连接 FPGA。

## 4. LCD 边界与复用

NEO Dock 31005 的 J5 是 40-pin 并行 TTL/DPI RGB 连接器，针脚名称包含 R0-R7、G0-G7、B0-B7，但 FPGA/CH569 复用总线只连接每色高 6 位：

| 内部 FULL 信号 | J5 可控针脚 | 板级处理 | 状态 |
| --- | --- | --- | --- |
| `lcd_r[7:2]` | R2-R7，J5-7 至 J5-12 | 原样输出高 6 位 | `DEFERRED` |
| `lcd_g[7:2]` | G2-G7，J5-15 至 J5-20 | 原样输出高 6 位 | `DEFERRED` |
| `lcd_b[7:2]` | B2-B7，J5-23 至 J5-28 | 原样输出高 6 位 | `DEFERRED` |
| `lcd_r/g/b[1:0]` | R0/R1、G0/G1、B0/B1 | 这些连接器针脚未连接到 FPGA，不能约束 | `CONFIRMED` |
| `lcd_pclk` | CLK，J5-30 | 等面板时序确认 | `DEFERRED` |
| `lcd_hsync` | HSYNC，J5-32 | 等同步极性确认 | `DEFERRED` |
| `lcd_vsync` | VSYNC，J5-33 | 等同步极性确认 | `DEFERRED` |
| `lcd_de` | DEN，J5-34 | 等面板模式确认 | `DEFERRED` |
| `lcd_backlight` | 板载背光驱动 `LCD_DPI_BL` | 等背光要求确认 | `DEFERRED` |

FULL 内部继续保留 RGB888；未来仅在板级包装层截取 `[7:2]`。LCD 数据和控制线与 CH569 HSPI 总线复用，正式 CST 必须以互斥方式选择 `RGB_LCD`，不得同时启用 CH569 HSPI。面板型号、FPC、DPI 时序、像素时钟、同步极性及背光要求确认前，不生成 LCD 可烧录版本。

## 5. 尚未解除的约束门槛

1. 确认三枚用户按键如何覆盖复位和三个效果键，或提供第四路外部按键。
2. 确认上述 PMOD 线束分配与实际矩阵、MCP3208 模块接线一致。
3. 对 `USR_CLK_IN` 在 FPGA 侧执行时钟计数/锁定测试，并验证完整断电重启后 12.288 MHz 是否自动恢复，且不依赖上位机或 BL616 的运行时配置。
4. 首次 CST 仅包含已经达到 `CONFIRMED`、`MEASURED` 或经用户确认转为 `CONFIRMED` 的 `PROPOSED` 行；不包含 Bank 1 和 LCD。
5. 完成 I/O 电气审查、未约束端口检查、综合、布局布线和时序分析后，才允许生成 `MINIMAL` 首次上板 bitstream。

## 6. 资料来源

- NEO Dock 31005 原理图：重点为第 6、7、9、10、12、18、19 页；
- Tang Mega 60K 30353 与 30354 原理图：共同的 BTB、FPGA Bank、时钟和球位定义，以及第 6 页供电差异；
- 官方 `tang_mega_60K_pins.cst`；
- `rtl/top/neo_full_guitar_top.v`。
