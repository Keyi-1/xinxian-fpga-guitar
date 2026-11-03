# 构建与仿真指南

以下命令均从仓库根目录执行。已验证主机为 Windows 11 x64；源码编辑可使用 VS Code、Gowin IDE 和 Android Studio。发布包可以直接使用，无需配置所有开发工具。

## FPGA：Gowin EDA V1.9.12.03

1. 安装 Gowin EDA **V1.9.12.03 x64**，配置可用许可证及下载驱动。
2. 打开 `gowin/neo_guitar_touch_game/neo_guitar_touch_game.gprj`。器件应为 `GW5AT-LV60PG484AC1/I0`，`GW5AT-60B / Device B`，顶层 `neo_guitar_touch_game_top`。
3. 工程已引用 `../../rtl/`、`../../mem/` 与 `../../constraints/`。保留目录相对位置；不要只复制 gprj。
4. 在 IDE 运行 Synthesize、Place & Route，检查 Error、未布通、setup/hold 及资源报告。
5. 新 FS 在 `gowin/neo_guitar_touch_game/impl/pnr/neo_guitar_touch_game.fs`，综合网表在 `impl/gwsynthesis/`。下载步骤见[硬件说明](HARDWARE.md)。

原工程保留受保护的 `impl/neo_guitar_touch_game_process_config.json`。既有约束为系统 50 MHz、音频 12.288 MHz、KS 100 MHz；BSRAM 已满，不应靠放宽时钟或删除约束掩盖新改动的资源、时序问题。

发布文件保存在 `releases/`，独立于 IDE 会更新的 impl 目录。旧位流报告与旧网表仿真只认证其冻结版本，不能用来认证后来重新生成的 FS。

## HDL 仿真：ModelSim SE-64 10.6d

生产 RTL 使用 Verilog；测试平台使用 SystemVerilog。Gowin PLL、DPB、GSR 等实例需要与 EDA 配套的 `IDE/simlib/gw5a/prim_sim.v`，不能只编译用户模块。

当前源码的编译、顶层展开入口：

```powershell
$env:MODELSIM_BIN = 'C:\path\to\modelsim\win64'
$env:GOWIN_IDE = 'C:\path\to\Gowin_V1.9.12.03_x64\IDE'
python verification/compile_rtl.py
```

此入口从原 gprj 读取启用的 Verilog 文件，编译原语与生产 RTL，在独立 `verification/results/hdl/` 建 work 库并展开顶层，不覆盖 Gowin 产物。它检查当前工程能否被仿真器加载，不等于完整演奏场景仿真。

`verification/sim/tb/` 保存组件、KS、触控、MPU、曲库及整机测试平台；`verification/tools/` 保存当时的准备、运行和结果审阅脚本。许多旧脚本固定了当时 HEAD、绝对工具路径、原目录及预期哈希，复现实验请在[归档说明](../verification/README.md)指定的旧提交检出运行，不直接在新目录放宽保护条件。

最终整机功能验证使用实际综合网表与 RTL 对照。网表仿真不回标 SDF；实际频率、setup/hold 和完整布通由独立的 P&R/STA 检查。UART 门级测试登记了计时加速范围，原始 9600/115200 波特率另由生产 RTL 场景验证，不能把加速仿真称为真实串口速率测试。

## Windows：Python 3.12 x64、PyQt5、PyInstaller

```powershell
py -3.12 -m venv .venv
.venv\Scripts\python -m pip install -r tools/windows_score_uploader/requirements-build.txt
.venv\Scripts\python tools/run_windows_score_uploader.py
.venv\Scripts\python verification/run_client_checks.py
.venv\Scripts\python tools/build_windows_score_uploader.py
```

只运行源码界面时可安装 `requirements.txt`。锁定依赖包括 PyQt5=5.15.10、Qt=5.15.2、sip=12.13.0、pyserial=3.5、PyInstaller=6.16.0、hooks=2026.8。

新便携包输出在 `build/releases/windows/FPGA_Guitar_Uploader_1.2.0.zip`，同时包含示例、说明、对应源码和第三方许可证。版本号沿用源码定义，重新构建不会覆盖 `releases/windows/` 中已验收的固定包。

客户端回归使用软件设备模型和 Qt 控件，不打开实物 COM，不等于硬件传输验收。需要查看源码界面冒烟结果可运行：

```powershell
$env:QT_QPA_PLATFORM = 'offscreen'
.venv\Scripts\python tools/run_windows_score_uploader.py --smoke-test verification/results/windows_ui
```

该入口仅做窗口、资源和参考 WAV 生成检查，不播放声音。随软件打包的 smoke/media_smoke 模块是启动器保留的诊断入口；其余独立测试脚本已统一归档。

## Android：JDK17、SDK35、Build Tools35.0.1

安装 Android SDK Platform35 与 Build Tools35.0.1，设置 SDK/JDK 根目录：

```powershell
$env:JAVA_HOME = 'C:\path\to\jdk-17'
$env:ANDROID_SDK_ROOT = 'C:\path\to\Android\Sdk'
python tools/build_android_jdy23.py --check-tools
python tools/build_android_jdy23.py
```

SDK 路径优先读取 `ANDROID_SDK_ROOT`，其次 `ANDROID_HOME`。构建入口保留原开发机路径作为最后回退；新机器应显式设置环境变量。当前交付工具链依次使用 aapt2 编译资源、javac `--release 17`、D8、zipalign、apksigner，并逐字节核对 APK 内三首曲谱资源。

输出为 `build/releases/android/xinxian_jdy23_0.3.0/xinxian_jdy23_0.3.0.apk`。包名 `com.keyi.xinxian.guitar.jdy23`，版本0.3.0，minSdk26，targetSdk35。

### 签名与 Gradle 工程

签名密钥默认在本地忽略目录 `build/companion_ui/signing/jdy23-debug.jks`；也可用 `XINXIAN_KEYSTORE` 指向兼容的原调试密钥，别名 `androiddebugkey`、调试口令 `android`。默认文件不存在时会生成新的开发密钥，**不会得到原发布签名**。已有应用只能被同签名 APK 覆盖安装；使用新密钥可另改包名，或先备份应用记录、卸载旧应用再安装开发版。正式发布应自行管理独立签名及版本号，不提交密钥。

Android Studio 可打开 `mobile/android/`，工程使用 AGP8.7.3 / Java17。当前仓库没有 Gradle Wrapper，曾因离线 Kotlin 缓存不全而无法完成 Gradle 构建，交付 APK 的成功构建依据是上述 SDK 命令行流程。

单元与 instrumentation 测试源码位于 `verification/mobile/android/app/src/`，Gradle sourceSets 已指向其新位置。历史界面自动检查使用 Android API35 模拟器，覆盖普通屏幕、小屏、大字体、横屏、挖孔五种配置，冻结记录见[验证说明](VALIDATION.md)。
