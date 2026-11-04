# 第三方组件、素材及源码来源

本清单区分运行依赖、工具、参考资料和嵌入素材。项目自己的许可证不取代第三方条款。原始 Windows 包中的 [第三方声明](tools/windows_score_uploader/THIRD_PARTY_NOTICES.txt) 保留原文；新增的组件许可正文位于 [LICENSES](LICENSES/README.md)。

## Windows 运行与打包

| 组件 | 已验收包版本 | 许可及来源 |
| --- | --- | --- |
| PyQt5 | 5.15.10 | Riverbank Computing，开源版 GPLv3；不是 LGPL。应用按 GPL-3.0-only 分发 |
| Qt | 5.15.2 | The Qt Company 及贡献者，保留随包 GPL/LGPL 和组件许可；DLL 保持动态分离，可替换或重新链接 |
| PyQt5-sip | 12.13.0 | 保留 Riverbank SIP 原许可及随包文本 |
| Python | 3.12 系列运行时 | Python Software Foundation 及其依赖许可，原包 `licenses/Python_LICENSE.txt` 保留 |
| pyserial | 3.5 | Chris Liechti 及贡献者，BSD 条款保留 |
| PyInstaller | 6.16.0 | GPLv2-or-later 加 bootloader 特别例外，保留 COPYING 正文；打包并不把其许可自动套到独立 FPGA 代码 |
| pyinstaller-hooks-contrib | 2026.8 | 保留该版本随附许可，具体范围及例外以其正文为准 |

这些版本来自原发布 `manifest.json`，不是重新构建后猜测的版本。上述组件没有因本次许可更新而重新编译。

### 对应源码与使用者权利

应用的对应源码与构建说明在原包 `对应源代码.zip`，附加的 `对应源代码-含许可.zip` 保留其全部原成员并加入本次许可文件。当前完整仓库也提供源码和构建入口。发布 GPL 二进制时，源码应当同样便捷地获取并对应所发版本。

依赖的准确版本、直接源码下载 URL 和 SHA256 记录在 [source_downloads.json](LICENSES/third_party/source_downloads.json)。Qt 5.15.2 官方完整源码下载及散列来自 [Qt 官方归档](https://download.qt.io/archive/qt/5.15/5.15.2/single/qt-everywhere-src-5.15.2.tar.xz.mirrorlist)。PyQt5、SIP、pyserial 和打包工具的源码链接来自对应版本的 PyPI 发布元数据。

这些索引提供对应上游版本的源码，不声称本项目独立重建过上游全部 DLL。再分发者须核实并持续满足实际二进制对应源码、修改补丁、构建及安装信息等义务，维护源码的可获取性，不能只保留一个已失效的链接或只附许可证而省略义务。

本项目不另加禁止修改、调试、替换 Qt 库或为调试库修改而进行逆向工程的条款。Qt DLL 保留在 `_internal/`，应用源码、依赖版本和打包入口随分发提供。

官方许可依据：[Riverbank PyQt](https://www.riverbankcomputing.com/software/pyqt/)、[Qt GPL/LGPL 义务](https://www.qt.io/development/open-source-lgpl-obligations)、[GNU GPL FAQ](https://www.gnu.org/licenses/gpl-faq.html)。

## FPGA 工具与 IP

`rtl/synth/ks_compute_pll.v` 明确包含 `Copyright (C)2014-2024 Gowin Semiconductor Corporation` 和 `All rights reserved`，本项目保留该声明。此文件及归档中的类似 Gowin IP 文件不由团队授予 Apache-2.0 许可；使用和再分发应核对适用 Gowin EDA/IP 条款。原语仿真库由使用者已有的 Gowin 安装提供，不随本次许可补充包复制。

Gowin EDA、ModelSim、Android SDK、JDK 等工具仍受各自许可约束；它们不会因项目源码开放而自动获得新的分发许可。

## 曲谱、谱面与字体

曲谱库包括茉莉花、Seven Nation Army、情歌、生日快乐歌、我不难过、City of Stars 等演示/练习数据。作品、特定编配、转录和谱面可能分别具有权利人；不因为曲名、传统旋律、转录方式或“用于学习”便推定所有版本均可自由再分发。当前没有在本次核对中取得覆盖这些全部材料的明确再分发授权，列为**待核实**。

该例外包括 `scores/`、Android 内置 BIN、Windows 示例、相关 ROM/MEM、BSRAM 初始化头文件、原始谱面图片，以及位流/APK 中的嵌入数据。它们不受团队原创代码的开源许可覆盖。

`verification/tools/generate_game_ui_font.py` 引用 Windows `C:/Windows/Fonts/simhei.ttf`，生成 `mem/game_font_16.mem`。本仓库没有分发该字体文件；所生成字形位图的再分发许可仍应单独核实，本次不重新授权该字库。

## 参考资料与历史归档

synth8 的 TDM 说明、Sipeed/Gowin 板卡资料及其他链接用于说明设计参考；提供链接本身不表示原作者为本项目背书，也不表示本项目有权为原材料更换许可证。

`verification/` 包含多个时期的项目、第三方引用和冻结包。保留原来的版权和许可信息；对于归属明确的团队原创代码可按根目录方案使用，其余来源或授权未明确的部分不自动套用 Apache-2.0。旧包与证据的字节保持不变，新清单不伪造过去已有的授权或核验结论。
