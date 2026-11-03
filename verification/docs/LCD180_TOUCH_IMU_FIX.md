# LCD180 触控与 MPU 姿态修复

本次基于已发布的 KS 五度 V2 + LCD180 版本 a320a95。保留根音/五度增益128/80、四独立声部/32模型状态、48kHz输出和100MHz内部KS计算。传感器安装方向保持用户原来的位置，不因显示旋转而更换IMU轴。

`rtl/config/display_orientation.vh` 的 `GUITAR_DISPLAY_ROTATE_180` 为1，同时控制显示扫描/曲线方向与触控。触控保留原坐标映射器的安装轴交换/缩放/镜像，在其9位像素输出端单独按 `(479-x,271-y)` 进入手势和逻辑界面。显示实例直接展开为编译常量，避免层层传递参数影响原渲染器的映射。原来点击旋转后的校准/AUTO/菜单按钮会落入错误区域，本次统一两端方向。

旧姿态代码在斜抱判定中还要求 `X>=-0.15g`，保持斜抱要求 `X>=-0.25g`。沿负X方向倾斜约47°，虽然倾角和静止条件已满足，仍判为UNKNOWN并保留上一次FLAT。新代码按平方比判定琴面/琴颈倾角，对正负X方向采用同一标准；反向竖抱也显示UPRIGHT，仍不生成一个不存在的音色。正负Y方向原来就对称，保持其行为。

本次不修改原角度阈值（斜抱进入约45°、琴颈不超过约60°）、校准/滤波/运动过滤/稳定与冷却时间或自动切换策略。启动仍为MANUAL：平放静止后点击CALIBRATE，256包校准及健康恢复完成，再打开AUTO并进入演奏。姿态切换不产生拨弦事件，存在尾音时仍等待安全切换，手动选择优先。

验证使用原始GT911注册帧进入完整坐标/手势链路，以及真实MPU I2C引脚模型；不直接注入校准、点击结果、姿态、音色或PCM结果。组件测试同时运行冻结旧分类器，证明负X倾斜的旧FLAT现象和修复结果。生产256包及各时间计数保留，整机仿真仅加速毫秒/I2C等待计数器，不改变音频时钟或样本方程。仿真不能判定实物传感器是否实际输出新加速度，最终仍需下板核对。

旧成功位流和认证保留于固定发布 `build/releases/touch_game/ks_fifth_v2_lcd180_20261101.zip`，独立回退FS位于 `build/input_rotation_imu/before/known_good_ks_lcd180.fs`，SHA256 `523659582b19be709e70d8544cfd0db4920dc2708b36ac481df2d08c7ad63760`。本轮过程与最终结果记录于 `build/input_rotation_imu/`。

首版 `synth_01/route_01` 功能完整通过，实际网表触控/MPU和四声部KS两项对照均PASS；但实际STA为系统49.177MHz、KS96.607MHz，44个setup违规端点，不能发布为合格位流。原始报告/源快照/位流保存在 `candidate_01`、`synth_01`、`route_01` 和两个测试目录，不改写。第二版改为像素输出端旋转和共用编译常量；音频生产代码、频带模块、时钟/约束和保护配置不动。

第二版 `synth_02/route_02` 已完成原工程综合、完整P&R/STA，实际Fmax为系统50.020MHz、音频20.131MHz、KS101.645MHz，满足50/12.288/100MHz；setup/hold违规均0。资源Logic50328、FF22902、CLS28592/29952、BSRAM118/118、DSP106.5/118。两条原PR1014保留并计入实际STA，不因系统时序余量小而重复构建。

`components_03` 通过131297触控帧（全部130560原生像素及缩放/换轴/组合镜像/边界）和双向姿态回归；`rtl_top_68_02/rtl_top_70_02` 均通过。新实际VG与完整RTL的 `gate_02` 通过7611音频帧/6671436 LCD时钟/1199 MPU包/4次原始触控点击/3次实际自动音色加载；`input_fix_full_gate_02` 通过3346帧/3345PCM/7组起音/1471406 LCD时钟及五度ON/OFF。两项网表测试各238条厂商RAM/PLL模型警告经源位置审阅，应用错误0；未使用SDF，另以实际布线STA验收。未改变的KS试听/TDM仅以相同源哈希复用。

原工程可用位流为 `gowin/neo_guitar_touch_game/impl/pnr/neo_guitar_touch_game.fs`，SHA256 `1be03302c47a9d1c50b673a0d637eb3aa638e43b852b3d8f25e111ad3eae9a3e`。新独立[位流与报告包](../build/releases/touch_game/ks_fifth_v2_lcd180_inputfix_20261101.zip)，以及[137文件纯源码包](../build/exports/neo_guitar_touch_game_ks_fifth_v2_lcd180_inputfix_code_only_20261101.zip)（RTL、头文件、ROM、约束，无README/位流/报告）。严格入口 `tools/check_input_rotation_imu_result.py publish`；完整认证和打包核对位于 `build/input_rotation_imu/verification.json`、`release_check.json`。未烧录/打开COM/提交/推送；下板时上电平放校准后打开AUTO，进入演奏并在约45～55°斜抱姿态保持1秒以上，核对音色与触控实际位置。
