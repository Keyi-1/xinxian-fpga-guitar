# 弦心 Android 客户端

配套芯弦 FPGA 四弦电子吉他的原生 Android 应用，显示名“弦心”，当前版本 **0.3.0**。支持 Android 8.0+，通过 JDY-23 FFE0/FFE1 蓝牙串口管理曲库、导入曲谱。

安装[当前 APK](../../releases/android/xinxian_jdy23_0.3.0.apk)，允许蓝牙/附近设备权限，在设备页连接 JDY-23；握手完成后选择内置曲谱或手机 `.bin`，设置目标槽位和音色，再上传。内置生日快乐歌、我不难过、City of Stars。设置中可关闭音符背景动画。

主代码在 `app/src/main/java/com/keyi/xinxian/guitar/`：

| 类 | 职责 |
| --- | --- |
| MainActivity / CompanionUi / MusicBackdropView | 页面、系统安全区、音符背景 |
| BleUartClient / BleSerialProfile | BLE 连接、服务发现、串口分片及通知 |
| Xg3Client / Xg3Protocol | 握手、五槽查询、停等传输、重试与校验 |
| ScoreLibrary | 内置曲谱与手机文件读取 |

从仓库根目录运行 `python tools/build_android_jdy23.py`，设置 `JAVA_HOME` 和 `ANDROID_SDK_ROOT`，需要 JDK17、SDK35、Build Tools35.0.1。`--check-tools` 只检查工具路径。Gradle 工程保留 AGP8.7.3；当前交付 APK 实际由 SDK 命令行工具生成，签名密钥不入库。测试源码集中在 `verification/mobile/android/`，Gradle sourceSets 指向该位置。

完整说明：[构建与签名](../../docs/BUILDING.md)、[硬件接线](../../docs/HARDWARE.md)、[传谱与提交结果核对](../../docs/TRANSFER.md)。

原创客户端代码采用 Apache-2.0，版权归芯弦项目贡献者；内置第三方曲谱不由此重新授权，部分再分发权待核实。详见[许可范围](../../LICENSING.md)和[第三方说明](../../THIRD_PARTY_NOTICES.md)。
