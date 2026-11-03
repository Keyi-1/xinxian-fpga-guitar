# Tang Mega NEO Dock 31005 / Mega 60K 板级连接矩阵

更新日期：2026-09-27

> **2026-10-05 FULL 更新：** 用户已确认钢琴实物音色成功。新的音频 FULL 使用
> `constraints/neo_guitar_audio_full.cst`，三键 AA13/AB13/Y12，均为 LVCMOS15 上拉输入；
> AA13 为音色键，AB13 短按合唱／长按和声，Y12 循环无效果／延音／轻混响。
> 没有独立复位引脚，28 个球位唯一且固定引脚实现通过。LCD 尚未采购，FULL 自动引脚位流仍仅作逻辑验收。
> [最新 FULL 说明](FULL_PIANO_EFFECTS.md) 优先于下面的旧按键／复位冲突记录。
>
> **2026-10-03 更新：** 用户已确认双 PCB 全链路实物测试结果理想，正式主工程已同步。
> 当前矩阵使用已实测的 **J13**、ADC 使用 **J8**；以
> [主工程同步说明](MAIN_ENGINE_SYNC.md)、[全链路接线表](NEO_FULL_CHAIN_AUDIO_TEST.md)
> 和 `constraints/neo_guitar_main.cst` 为当前接线依据。下面 2026-09-27 的 PMOD 候选、
> Bank 1 通用禁用、MCP3208 待验证以及按音符关闭 PA 的描述均是历史记录，
> 不再约束已实测的这套 J13/J8 方案。当前 PA 仅在复位期间关闭。
> 核心板版本仍未进一步确认；LCD、效果按键和新增外设分配继续单独审核。


## 1. 适用硬件与使用规则

| 项目 | 状态 |
| --- | --- |
| NEO Dock | `31005`，实物已确认 |
| Tang Mega 60K 核心板 | `30353` 或 `30354`，核心板被底板遮挡，暂时无法确认 |
| FPGA | `GW5AT-LV60PG484AC1/I0`，PG484 |
| Bank 1 | 当前实测 J13 矩阵使用其中部分 GPIO，沿用当前 CST 和既有供电；旧通用禁用记录见历史候选章节 |
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
| `audio_clk_12m288` | 输入，12.288 MHz | NEO Dock MS5351M U7 `CLK2` | `USR_CLK_IN` | J2-88 | V13 | 7 | 3.3 V / LVCMOS33 | CLK2 经 2.2 ohm 与 100 nF 串联耦合；完整断电后可独立恢复，不依赖电脑、MCU、BL616 运行时服务或软核 CPU | `CONFIRMED`：示波器及 MINIMAL 实物音频链验证 |
| `dac_bclk` | 输出 | PT8211-S U16 pin 1 | `I2S_BCLK` | J2-26 | Y17 | 7 | 3.3 V / LVCMOS33 | 板载音频专用 | `CONFIRMED` |
| `dac_lrck` | 输出 | PT8211-S U16 pin 2 | `I2S_LRCK` | J2-28 | AB17 | 7 | 3.3 V / LVCMOS33 | 板载音频专用 | `CONFIRMED` |
| `dac_din` | 输出 | PT8211-S U16 pin 3 | `I2S_DIN` | J2-30 | AA16 | 7 | 3.3 V / LVCMOS33 | 板载音频专用 | `CONFIRMED` |
| `pa_en_n` | 输出，低有效 | 功放 U20 | `PA_EN` | J2-36 | AB16 | 7 | 3.3 V / LVCMOS33 | `1`=功放关闭，`0`=功放开启；复位和空闲保持高 | `CONFIRMED` |

### 2.1 板载按键资源

| 底板按键 | 电气语义 | 底板网络 | BTB | FPGA 球位 | 实际 Bank | VCCIO / IO_TYPE | 可分配 RTL 功能 | 状态 |
| --- | --- | --- | --- | --- | ---: | --- | --- | --- |
| S4 / USER_BUTTON0 | 按下接地，需内部上拉 | `EX_KEY.0` | J2-60 | AA13 | 9 | 1.5 V / LVCMOS15 / PULL_UP | `rst_n` | `CONFIRMED`：MINIMAL 按下静音、释放重新发声 |
| S2 / USER_BUTTON1 | 按下接地，需内部上拉 | `EX_KEY.1` | J2-62 | AB13 | 9 | 1.5 V / LVCMOS15 / PULL_UP | 同上 | `BLOCKED`：逻辑映射未冻结 |
| S1 / USER_BUTTON2 | 按下接地，需内部上拉 | `EX_KEY.2` | J2-64 | Y12 | 9 | 1.5 V / LVCMOS15 / PULL_UP | 同上 | `BLOCKED`：逻辑映射未冻结 |
| SW7 | 配置/重配置按钮 | `BANK10_N12_RECONFIG` | J0-61 | N12 | 配置专用 | 配置专用 | 不作为普通用户复位或功能键 | `CONFIRMED`：禁止分配为普通 GPIO |

`KEY0/S4=AA13` 已固定为本工程 `rst_n`。当前 `neo_full_guitar_top` 还需要三个独立功能键，但底板只剩两枚普通用户按键；FULL 正式 CST 前必须增加外部按键或经过单独需求评审修改交互方式。`SW7/RECONFIG=N12` 是配置专用按钮，SRAM 模式下按下会清除当前 FPGA 配置，不能代替 RTL reset。

## 3. PMOD0/PMOD1 安全候选分配

下面存在两种必须互斥的 PMOD 用法。当前已实测的是 ROW0 固定接地的临时 COL+LED 接法；最终候选是 4 ROW + 8 COL + MCP3208 SPI。不得把两者的约束合并到同一个 bitstream。

### 3.0 ROW0 单组临时实测接法

| 功能 | 品位板 H1 | NEO Dock | FPGA 球位 | 状态 |
| --- | --- | --- | --- | --- |
| 3.3 V | H1-1 | J8-1 | 电源 | `CONFIRMED` |
| GND | H1-2 | J8-3 | 地 | `CONFIRMED` |
| ROW0 固定低 | H1-3 | J8-4/GND | 非 FPGA GPIO | `CONFIRMED`：只用于单组测试 |
| ROW1～ROW3 | H1-4～H1-6 | 不连接 | 非 FPGA GPIO | `DEFERRED`：本次未测试 |
| COL0～COL3 | H1-7～H1-10 | J8-11/J8-12/J8-9/J8-10 | Y21/Y22/AB21/AB22 | `CONFIRMED`：ROW0 初测通过 |
| COL4～COL7 | H1-11～H1-14 | J8-7/J8-8/J8-5/J8-6 | AA20/AA21/AA19/AB20 | `CONFIRMED`：ROW0 初测通过 |
| LED0～LED3 | 外接调试 LED | J9-11/J9-12/J9-9/J9-10 | P19/R19/T21/U21 | `CONFIRMED`：`CPU=true` 后作为普通 GPIO |
| LED4～LED7 | 外接调试 LED | J9-7/J9-8/J9-5/J9-6 | P16/R17/R18/T18 | `CONFIRMED` |

该配置只证明 ROW0 八触点、COL 对应、同步/防抖/LED 和相关 PMOD 连接。它不包含行扫描。完整矩阵阶段必须释放 PMOD0 的 LED 用途。

下面的最终候选分配避开 Bank 1，并且每个球位都由两版核心板共同部分与官方 60K CST 的 3.3 V 配置支持。它使用两组 PMOD 的全部 16 根 GPIO：4 根矩阵行、8 根矩阵列和 4 根 MCP3208 SPI。完整线束确认前状态保持 `PROPOSED`。

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

1. MINIMAL 固定接口及专用 CST/SDC 已通过综合、布局布线、时序和实物验证；成功 `.fs` 只保留在现有 Gowin 工程中，目前使用 SRAM Program/Configure，不写外部 Flash。
2. FULL 仍需解决 KEY0 已用于复位后，只剩两枚板载用户按键却需要三个效果键的问题。
3. 在取得 MCP3208 模块型号、正反面照片、针脚标注、VDD/VREF/AGND/DGND 接法前，四根 SPI 候选保持 `PROPOSED`，不得上电接线或冻结 CST。
4. 确认 MCP3208 后先建立独立单通道测试工程，使用 3.3 V 逻辑和共地，输入限制在 0～VREF；不直接连接压电片，也不直接烧录 FULL。
5. Bank 1 和 LCD 继续排除在近期约束外；现有 FULL 自动引脚 `.fs` 仍禁止烧录。

## 6. 资料来源

- NEO Dock 31005 原理图：重点为第 6、7、9、10、12、18、19 页；
- Tang Mega 60K 30353 与 30354 原理图：共同的 BTB、FPGA Bank、时钟和球位定义，以及第 6 页供电差异；
- 官方 `tang_mega_60K_pins.cst`；
- `rtl/top/neo_full_guitar_top.v`。
