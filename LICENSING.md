# 许可证与适用范围

本项目采用按组件授权的方式。根目录 [LICENSE](LICENSE) 为 **Apache License 2.0** 正文，适用于下表中团队拥有授权权利的原创部分；Windows 客户端采用 **GNU GPL version 3 only（GPL-3.0-only）**。第三方材料的既有许可优先，本说明不为其另行授予权利。

版权署名为 **Copyright (c) 2026 芯弦项目贡献者 / Xinxian project contributors**。仓库维护者已于 2026-11-04 确认取得团队对本方案及署名方式的同意。各贡献者仍保留对其贡献的版权，详见 [COPYRIGHT.md](COPYRIGHT.md)。

## 原创代码的许可

| 范围 | 许可 |
| --- | --- |
| `rtl/`、`constraints/`、`gowin/` 中的原创设计与工程配置 | Apache-2.0；高云 IP 文件及下表中的嵌入数据除外 |
| `mobile/android/` 中的原创 Java、资源和构建配置 | Apache-2.0；内置第三方曲谱除外 |
| `tools/` 中的原创独立编谱、协议及构建脚本 | Apache-2.0；下行 Windows 客户端除外 |
| `tools/windows_score_uploader/` 中的原创应用代码，以及 `tools/run_windows_score_uploader.py` | GPL-3.0-only；目录内 `LICENSE` 为完整正文，示例曲谱和依赖除外 |
| `mem/` 中原创的相位、数值计算及音色参数数据 | Apache-2.0；曲谱和字体数据除外 |
| 原创项目文档、图示、界面设计，以及 `verification/` 中可明确归属于本项目贡献者的原创建模、测试与分析代码 | Apache-2.0；引用材料、第三方文件及来源尚未确认的归档除外 |

Windows 程序可使用 Apache-2.0 的共享协议模块；与开源版 PyQt5 组合分发的应用整体遵守 GPLv3，相应 Apache 版权与许可声明仍须保留。Windows 通过 UART 协议与 FPGA 通信，不据此将独立 FPGA 工程改为 GPL。

Apache-2.0 与 GPLv3 均允许商业使用，修改和分发时应分别遵守其声明、对应源码等条件。这里不另加“禁止商用”或“仅限学习”的限制。完整权利、义务、专利条款及无担保条款以正式许可证文本为准。

## 第三方和未重授权内容

| 文件或内容 | 处理方式 |
| --- | --- |
| `rtl/synth/ks_compute_pll.v`，以及归档中带高云版权的 IP 文件 | 原文件保留 Gowin Semiconductor 版权头；**不授予 Apache-2.0 许可**，使用和再分发须依据适用高云 EDA/IP 条款 |
| `scores/`、Android `assets/scores/`、Windows `examples/`、谱面图片，以及归档中的曲谱 | 音乐作品、编配、转录或原谱权利归各自权利人；本项目的源码许可证不授权这些内容 |
| `mem/game_p2_static.mem`、`mem/game_p3_initial.mem`、`mem/jasmine_game.mem`，以及 `rtl/config/game_p2_bsram_init.vh`、`game_p3_bsram_init.vh` 中的曲谱数据 | 同上；打包成 ROM 或初始化常量不改变曲谱的权利归属 |
| `mem/game_font_16.mem` 及其归档副本 | 生成脚本引用 Windows `simhei.ttf` 进行字形栅格化；位图字库的分发授权**待核实**，不以 Apache-2.0 重新授权。字体文件本身未在本仓库分发 |
| 第三方原理图、手册、参考工程、截图中的他人作品、库及运行时 | 保留原作者和原许可；不能仅凭被收录于本仓库而认为其已采用本项目协议 |

对来源或授权尚未确认的材料，记录为待核实，不把“仅供学习”“已注明来源”或仓库可见性当作已获授权。具体清单见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 发布文件

- `.fs`、APK 以及源码 ZIP 的原创程序部分按对应源码许可；其中的曲谱、字库或第三方 IP 仍遵守上述例外。
- 已验收的原始二进制和冻结 ZIP 保持原字节，许可通过本说明及 [发布许可补充包](releases/license_notices_20261104.zip)与其对应。
- Windows `1.2.0_licensed.zip` 在原验收包基础上增加许可正文、版权说明、第三方源码索引及带许可的对应源码副本。原程序、DLL、资源、原清单及原源码 ZIP 均逐字节保留。
- 发布者应持续提供与二进制版本对应的完整源码、构建说明及所需第三方来源，并满足适用 GPL/LGPL 条款；源代码下载说明见 [第三方说明](THIRD_PARTY_NOTICES.md)。

本次更新不改变仓库的可见性，也不代表已完成所有第三方曲谱、字体和 IP 的再分发授权核实。它们不因新增许可证而变成团队原创或已获许可的内容。
