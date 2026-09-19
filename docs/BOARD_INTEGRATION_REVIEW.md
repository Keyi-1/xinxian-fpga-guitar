# Tang Mega 60K / NEO Dock 板级集成审查

审查日期：2026-09-19

## 1. 审查结论

当前 `full_guitar_top` 已经覆盖产品的完整逻辑链路，但它此前仍是“逻辑顶层”，不是可直接烧录的 NEO Dock 板级顶层。现新增 `neo_full_guitar_top` 作为电气边界层，仅处理已确认的接口语义，不写入任何未经核验的物理引脚。

在取得实物底板版本号、LCD 模组/FPC 定义、琴颈与 MCP3208 的最终接线表之前，不应为该板级顶层创建 CST，也不应生成或烧录带自动引脚的 bitstream。

## 2. 已确认的硬件资源

- 核心器件：`GW5AT-LV60PG484AC1/I0`，Gowin 选择 `GW5AT-60B / PBG484A / Device Version B`。
- NEO Dock 与 Tang Mega 60K/138K 共用同一系列底板外设，但不同 SOM、底板修订版与复用接口仍需用对应版本资料核验。
- 核心板固定 50 MHz 输入在官方 60K 示例中使用 `V22`。
- NEO Dock 包含 PT8211、耳机/扬声器输出、3 个用户按键、并行 RGB LCD 接口、2 路差分 ADC、SD、HDMI、DDR3、USB3/CH569、以太网等资源。
- 板载 ADC 只有 2 路差分输入，不满足四根弦的独立采样需求；外接 MCP3208 方案合理且继续保留。
- NEO Dock 31004 音频原理图的功放控制语义为高电平关闭、低电平开启。板级输出因此使用 `pa_en_n`，并在复位及无声部活动时保持高电平静音。
- 官方 138K 共用底板音频示例给出的 PT8211 网络候选为 `BCLK=Y17`、`LRCK=AB17`、`DIN=AA16`、`PA_EN=AB16`。这些值只作为交叉核对证据，未直接写入本项目 60K CST。
- LCD 连接器宣称支持 RGB888，但官方示例常使用 RGB666；最终输出位宽、PCLK 极性、同步极性、背光控制和 FPC 引脚必须以实际面板和底板版本确认。
- MS5351 的用户时钟输入脚随 NEO Dock 修订版变化，31004 与 31005+ 不同；目前不把它作为产品固定时钟源。音频继续使用外部 12.288 MHz 有源晶振，显示时钟最终由 FPGA PLL 产生。

官方资料入口：

- Sipeed Tang Mega 60K Wiki：<https://wiki.sipeed.com/hardware/en/tang/tang-mega-60k/mega-60k.html>
- Sipeed 60K 示例：<https://github.com/sipeed/TangMega-60K-example>
- Sipeed 138K 共用底板示例：<https://github.com/sipeed/TangMega-138K-example>

## 3. 当前接口覆盖

| 板级功能 | FULL RTL 状态 | 板级处理 | 结论 |
| --- | --- | --- | --- |
| 50 MHz 系统时钟 | 已使用 | 顶层输入 | 待写入经核验 CST |
| 12.288 MHz 音频时钟 | 已使用 | 顶层输入 | 使用外部晶振，待确认接线脚 |
| LCD 像素时钟 | 已使用 | 输出 `lcd_pclk`，极性参数化 | 最终应由 PLL 提供 |
| 4×8 琴颈矩阵 | 已使用 | 四根扫描线实现低电平/高阻切换 | 待确认 12 根 GPIO |
| MCP3208 四通道 | 已使用 | SPI 已接入 FULL 链路 | 待确认外接插座和 SPI GPIO |
| KEY1/2/3 | 已接入 | 去抖、单次切换、2FF CDC | 对应音色/合唱/延音混响 |
| PT8211 | 已接入 | BCLK/LRCK/DIN 输出 | 待以 60K 对应资料确认物理脚 |
| 功放使能 | 已接入 | 修正为低有效 `pa_en_n` | 复位和空闲时静音 |
| RGB LCD | 已接入 | RGB888、HS/VS/DE/PCLK/BL | 位宽和面板时序待实物确认 |
| DDR3/HDMI/SD/USB3/网口 | 未使用 | 无 | 首版无需求，不为提高利用率而加入 |

## 4. 本阶段验证

板级封装 testbench 验证：

- 每个扫描周期恰好一根矩阵行拉低，其余三根保持高阻；
- 三个按键通过去抖后各产生一次状态切换，长按不会重复切换；
- 按键状态通过双触发器同步进入音频域；
- 功放脚在空闲/复位时为高电平静音，在声部活动请求时为低电平开启；
- LCD 背光复位安全状态和 PCLK 参数化极性正确。

ModelSim 通过信息：

```text
PASS: NEO board wrapper tri-state/buttons/CDC/PA/LCD boundary
PASS: FULL matrix/ADC/four-voice/effects/PT8211/FFT/RGB frames=2000 spectrum=1 pixels=8557
```

Gowin 综合确认板级顶层可综合，并推断出 4 个 `TBUF`，对应四根矩阵扫描线的真实三态驱动。综合资源为：

- Logic：25,731 / 59,904（43%）
- Register：11,443 / 60,780（19%，Latch=0）
- BSRAM：12 / 118（11%）
- I/O buffer：16 IBUF、36 OBUF、4 TBUF

## 5. 保留的 FULL 实现基线

现有逻辑顶层的完整 Gowin 布局布线结果保留在：

```text
T:\Documents\AMD\gowin_full_build\impl\pnr
```

该基线无 setup/hold 违例，三时钟最差结果如下：

| 时钟域 | 要求 | 实际 Fmax |
| --- | ---: | ---: |
| `sys_clk_50m` | 50.000 MHz | 126.622 MHz |
| `audio_clk_12m288` | 12.288 MHz | 21.989 MHz |
| `pixel_clk` | 33.333 MHz | 140.181 MHz |

该结果使用自动引脚，只证明逻辑规模和时序可实现；对应 `.fs` 不可烧录。

## 6. 下一步门槛与决定

下一项合理工作不是增加新音效或占用更多外设，而是完成“可核验的物理板级约束”。需要先取得：

1. 实物 NEO Dock PCB 版本（尤其 31004 或 31005+）；
2. Tang Mega 60K 对应版本的官方完整 pin constraints；
3. 实际 LCD 模组型号、FPC pinout、RGB666/888 位宽和时序；
4. 外部 12.288 MHz 晶振、MCP3208 和 4×8 琴颈矩阵的接线表。

上述资料确认后，才创建独立板级 CST，加入 PLL/复位时序，重新执行板级顶层布局布线与 I/O 电气检查。资料确认前停止继续猜测引脚，也不扩展 DDR3、HDMI、SD、USB3 或软核 CPU。
