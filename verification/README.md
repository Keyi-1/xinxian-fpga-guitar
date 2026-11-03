# 验证与历史代码

当前生产代码在仓库根目录的 `rtl/`、`constraints/`、`mem/`、`gowin/neo_guitar_touch_game/`、`mobile/android/` 和 `tools/`。本目录统一保存过程性验证代码、旧工程、实验原型和冻结证据。

| 目录 | 内容 |
| --- | --- |
| sim/ | SystemVerilog testbench、参考模型、ModelSim脚本 |
| tools/ | 历史构建/审阅/音频分析脚本，以及客户端与协议回归测试 |
| mobile/ | Android单元和界面测试、旧手机端原型 |
| rtl/、mem/、constraints/、gowin/ | 未进入最终140份依赖清单的旧代码与工程 |
| firmware/ | BL616实验、桥接原型、历史JDY交付包与配置记录 |
| docs/、scores/ | 设计过程、阶段验收、旧谱面与转录依据 |
| build/ | 受版本管理的固定发布包、日志、收据；其余本地中间产物忽略 |
| previous_entrypoints/、misc/ | 整理前的入口文档、旧README PDF、硬件工程与计划 |
| organization/ | 迁移清单，逐文件保留原路径和SHA256 |
| local/、results/ | 本地草稿备份与新检查输出，均不入库 |

## 当前轻量检查

在仓库根目录运行：

```powershell
python verification/check_repository.py
python verification/run_client_checks.py
python tools/build_android_jdy23.py --check-tools
```

客户端回归需先安装 `tools/windows_score_uploader/requirements.txt`。运行器给原测试注入当前仓库根路径，不改写测试内容；不会打开实体COM或BLE。Android测试源码通过原Gradle工程sourceSets引用。

ModelSim生产源码编译与展开：`python verification/compile_rtl.py`，工具路径及范围见[构建指南](../docs/BUILDING.md)。该检查不冒充完整音频/菜单/传谱仿真。

## 历史脚本的适用版本

整理前基线提交为 **58cae9d472e527b87db03c8eb918da26bf108b7d**。历史脚本与收据保留原字节，其中的 `build/`、`sim/`、`tools/`、本机绝对路径、HEAD保护等表示当时目录和工具环境；迁移不会让这些冻结脚本自动适用于新目录。

需要审计或复现旧批次时，可在另外目录检出该提交，例如：

```powershell
git worktree add ../xinxian-verified-baseline 58cae9d472e527b87db03c8eb918da26bf108b7d
```

随后根据对应收据检查工具版本、源码、测试输入和产物；早期测试还需使用收据记录的当时提交。Git只分发已跟踪文件，旧仿真器work库、完整本地网表、PCM和一些激励副本需要在对应环境重新生成。不要删除哈希或HEAD检查来把旧认证套到新构建。

最终双接口位流证据在 `build/dual_score_transport/`，其实际资源/STA报告亦包含于[当前固定发布包](../releases/fpga/verified_release_20261102.zip)。旧不可用候选和失败记录作为过程资料保存，不作为当前下载推荐。用户本轮实物验收反馈见[版本说明](../docs/VALIDATION.md)。

## 整理说明

982份原跟踪文件移入本目录，迁移表见 [organization/relocations.json](organization/relocations.json)。迁移不修改其字节、原发布ZIP或旧证书。两个受保护文件仍在原位置：主工程process_config和MPU6050设计计划；后者保留为历史参考，当前使用步骤以根README和docs/HARDWARE为准。

README信息组织参考了 [raylib](https://github.com/raysan5/raylib) 和 [NESTang](https://github.com/nand2mario/nestang) 的项目介绍、快速使用和开发说明布局，文字按本项目实际实现重写。
