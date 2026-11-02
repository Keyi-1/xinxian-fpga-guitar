# 弦心曲谱软件界面更新

本次软件工作树为 `T:/Documents/AMD/xinxian-companion-ui`，分支 `feat/companion-ui`，基于 `a320a95e934dae00d9cc0dc22c2fe1b6653b2a15`。原工作树继续供 FPGA 开发使用，两者不共享工作文件、索引和构建产物。没有合并主对话尚未提交的硬件修改。

## 安卓 0.3.0

- 曲库、设备、设置和上传四个页面，深蓝背景、青紫点缀、可关闭的轻量音符粒子背景。页面支持滚动和系统字体缩放，内容根据真实系统栏及挖孔 Insets 留出安全区。
- 内置生日快乐歌（25事件、60BPM）、我不难过（564事件、64BPM）、City of Stars（491事件、100BPM），同时保留系统文件选择器导入 `.bin`。两个入口使用同一个实际事件解析器；内置文件还校验冻结的数量、时长和 CRC。
- 五槽和三种音色可以独立选择。界面统一使用钢琴、明亮弦音、哇音，对应协议值0/1/2。4、5空槽同样显示待导入，删除推荐槽位文案。
- 提交前显示目标槽与音色；逐事件 ACK 更新进度，提交前持久化待确认标记，结果未知时仍需人工核对。曲谱在 FPGA RAM 中，断电后需要重新上传。
- 新增四弦音符矢量应用图标，提供自适应及单色版本。
- APK 保持原包名 `com.keyi.xinxian.guitar.jdy23`，使用本机原有开发签名；签名文件只保存在忽略的本地构建目录，不随包分发。

## Windows 1.2.0

同步新槽位显示与音色中文名称，删除推荐槽位文案；保留原电脑试听功能与界面风格。示例曲库增加同样三首曲谱包。槽位名称按设备实际返回的曲谱数量、时长和音色识别，兼容旧位流的不同位置；已导入曲仍显示 USER n。

## 构建与验证

- 安卓：`python tools/build_android_jdy23.py`，使用已安装的 Android SDK 35、JDK17 编译、D8、对齐和签名；直接打包真实assets，逐字节检查APK内曲谱。
- 曲库检查：`python tools/check_companion_ui.py`，用实际Java解析器检查两入口事件一致、三个CRC、全部45种槽位/音色组合、坏文件与旧槽位识别，并核对底层协议/BLE以及FPGA输入未改动。
- SDK独立测试包：`python tools/build_companion_ui_test.py`。测试源码位于 `mobile/android/app/src/androidTest`，测试文档提供器不进入正式 APK。
- Windows：使用已有依赖环境运行上传和试听测试，再执行 `python tools/build_windows_score_uploader.py`。冻结 EXE 的 `--smoke-test` 不访问实体 COM 或音频设备。
- 本地验证与实际界面截图位于 `build/companion_ui/`。Android模拟器采用本工作树内独立的官方API35镜像和AVD，仅连接`emulator-5580`，ADB端口5041。

本轮不改变XG3协议、BLE串口参数、FPGA音色、RTL或时钟约束；软件测试不能替代实体蓝牙模块的上传实测。未提交、合并或推送。

## 本次最终结果

Android 15实测普通屏幕、小屏、1.5倍字体、横屏、挖孔五场景全部通过，共195项检查；实际安装的APK哈希与交付文件一致。Windows34项回归与最终冻结EXE检查通过，ZIP成员、分发清单和对应源码哈希一致。最终认证为`build/companion_ui/verification.json`。实体蓝牙/串口设备未连接，等待用户实测；独立模拟器和5041测试服务已经关闭。
