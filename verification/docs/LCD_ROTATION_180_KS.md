# 在 KS 推荐版上移植整屏 180° 翻转

从远端提交 [42f9c1fb73ba1e2260f889d4ba14fbfab07fc318](https://github.com/Keyi-1/xinxian-fpga-guitar/commit/42f9c1fb73ba1e2260f889d4ba14fbfab07fc318) 读取并移植显示改动，保留本地已确认的 KS 五度 V2 音色。没有拉取或合并整份远端树，HEAD 和用户现有未提交内容保留。

用户随后要求尝试编译布线并生成新位流，现已在原工程完成正式综合、完整P&R/STA和当前实际网表验证。[下载位流与报告](../build/releases/touch_game/ks_fifth_v2_lcd180_20261101.zip)，其中 `neo_guitar_touch_game_ks_fifth_v2_lcd180.fs` 为本次 KS 加翻转组合。本机原工程输出位于 `gowin/neo_guitar_touch_game/impl/pnr/neo_guitar_touch_game.fs`；此前未翻转的 KS V2 固定发布保持回退。

生产代码只改三份，忽略 CRLF 和末尾空行差异后，内容与该远端提交完全一致；远端原始副本另校验了 Git blob 身份。清理了远端多余末尾空行，使本地差异检查通过：

- `rtl/display/lcd_rgb_scan_480x272.v`：增加默认关闭的 `ROTATE_180`。开启时有效像素映射为 `(479-x,271-y)`；横坐标采用合并常量减法，纵坐标直接倒计数，保留原 DCLK、HSYNC、VSYNC、DE、帧起点及六时钟像素周期。
- `rtl/display/guitar_radial_curve_renderer.v`：倒序预渲染逻辑扫描行，同步调整左消隐区触发位置；保留双扫描行缓冲、重复触发过滤和截止时间检查，避免只翻坐标导致曲线错行。
- `rtl/game/guitar_touch_game_display.v`：为主显示的扫描器和曲线渲染器同时开启旋转。文字、菜单、游戏、色块、频谱、曲线及状态覆盖层共用翻转后的坐标。其他工程的模块默认方向保持。

音频源码、KS 延迟线与增益、四独立声部/32模型状态、包络、滑音、效果、ROM、PLL、时钟约束、工程文件均逐字节保持本地已成功的推荐 V2。触控坐标映射也按照远端做法保持原配置；本次翻转显示输出。没有修改用户拒绝优化的频带模块，两个保护文件的内容和暂存对象保持。

## 验证结果

使用本机 ModelSim 编译当前全部 RTL，运行远端两个原始测试，均通过且无错误/警告：

| 测试 | 本次实际结果 |
| --- | --- |
| `sim/tb_lcd_rotation.sv` | 两帧261120有效像素，坐标为 `(479-x,271-y)`；同步时序和RGB采样检查通过 |
| `sim/tb_lcd_rotation_curves.sv` | 八组场景2176行，解析交点、显示范围、停音/尾迹、重复触发通过；最慢2266/3186时钟，无超时 |

上述源码移植阶段入口为 `tools/check_lcd_rotation_ks.py rtl_clean_01`，结果已通过，不重复运行；它也核对构建前的原FS，因此不用于新位流验收。证据：[显示RTL验证](../build/lcd_rotate_ks/rtl_clean_01/verification.json)，远端提交和 blob 记录位于 `build/lcd_rotate_ks/remote_commit.json`，移植前源清单位于 `build/lcd_rotate_ks/before/`。测试和三份生产源均校验了远端原始副本及上述空白规范化后的身份；未修改输入的音频路径只复用已有验证，没有重跑音色试听或声部仿真。`rtl_01` 是清理末尾空行前已通过的记录，保留而不覆盖。

## 正式构建与实际网表

使用原 `gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj`、原 `impl`、GW5AT-LV60PG484AC1/I0 Device B 和 Gowin V1.9.12.03，经 `gw_sh open_project`、`run syn`、`run pnr` 完成。未修改约束或受保护的配置，Route_Maxfan32、ClockRouteOrder0、RouteOption2 保持。`build/karplus_strong/lcd_rotate_synth_01`、`lcd_rotate_route_01` 均退出0；严格最终入口为 `tools/check_lcd_rotation_ks_result.py`，完整认证在 [verification.json](../build/lcd_rotate_ks/verification.json)。

| 资源 | 本次使用 | 可用 |
| --- | --- | --- |
| Logic | 50348 | 59904 |
| Register | 22902 | 60780 |
| CLS | 28279 | 29952 |
| BSRAM | 118 | 118 |
| DSP | 106.5 | 118 |

| 时钟 | 实际要求 MHz | 本次布线 Fmax MHz |
| --- | --- | --- |
| 系统 | 50 | 52.586 |
| 音频 | 12.288 | 18.847 |
| KS运算 | 100 | 109.240 |

setup、hold、latch、未布通及已测采样截止时间溢出均为0。原两条 PR1014 通用时钟布线警告保留，验收依据本次实际布线报告。综合警告与未翻转 KS V2 相比仅源行号变化，无新增；推断LUT减少662，正式资源相对旧版减少659 Logic及345 CLS，未增加寄存器、DSP或BSRAM。不为额外时序余量重复构建。

本次实际综合网表与完整 RTL 的整机对照 `lcd_rotate_full_gate_01` 通过：3346帧/3345 PCM/1471406 LCD时钟/7组起音；五度开启1684帧、关闭1662帧，包含四路同时发声及独立拨弦、滑音和真实 PLL/I²S。被测VG与当前原impl VG字节一致，SHA256 `90e87e563d58e43a155a4752884681f470981aaf0419feb41fa55ee0f07755d7`。238条厂商仿真模型警告按已审阅源位置核对，无错误；触控、ADC、按钮和声命令的寄存输出仅作登记输入刺激，不强制频率、演奏事件或音频结果。网表仿真无SDF，另通过完整实际布线STA。

当前原工程位流 SHA256：`523659582b19be709e70d8544cfd0db4920dc2708b36ac481df2d08c7ad63760`。原资源/时序报告位于 `impl/pnr/neo_guitar_touch_game.rpt.txt` 和 `neo_guitar_touch_game_tr_content.html`。发布包内独立位流为 `neo_guitar_touch_game_ks_fifth_v2_lcd180.fs`。

本次认证不使用远端旧音色 STA 或本地旧 KS 证书替代新组合验证；旧证据只在音频输入源逐字节不变时复用。[未翻转KS V2回退包](../build/releases/touch_game/ks_fifth_v2_20261101.zip)保留，其中位流 SHA256 `48239256e8c700b0d2e147046880e9ffef06c023b7f536d2cdb20ae5c12b44ab`。旧固定证书/发布包保持不动；板上显示、触控、音频及断电启动仍待实测，本次没有烧录或访问实物串口。

## 仓库发布与复现

仓库包含源码、测试、参数生成器、原工程及三个固定KS发布ZIP；临时网表、仿真工作库、失败候选和完整本机build目录不上传。ZIP内包含位流、资源/时序报告及原认证，源码根README指向最新组合包。首次编译请使用同一原工程、器件和时钟配置，不能以远端旧音色位流替代KS组合位流。

提交及接续远端历史时不重新综合布线，而是核对当前构建输入与本次认证源清单一致、ZIP/位流哈希不变。原认证及ZIP保持构建时内容，不因Git HEAD变化而重写。`check_*_result.py` 是绑定原构建基线和本机历史证据的发布审计脚本，并非克隆后可直接运行的通用CI；其中绝对工具路径需匹配本机安装，审计还需要对应原始build证据。源码测试及RTL仍可按同一工具链复现。
