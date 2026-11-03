# 钢琴短包络与松品保持音高

2026-10-24实施，2026-10-25完成数字验收。基于已完成数字验收的颤音 V6，本轮新增两项用户要求：第一钢琴音色自然时长约减半；松品不再滑回空弦，而是保持原音自然衰减。三次松按同一品位触发颤音的识别与调制继续保留。

## 行为

- 钢琴包络按两倍速度推进，明显收尾约从 1.6 秒提前到 0.8 秒；无效果自然声部寿命从 131072 样本（2.731 秒）变为 65536 样本（1.365 秒）。音高、力度、32 模态运算节奏和最初 42.67 ms 的程序击弦细节保持。
- 每次真实起音锁定是否为纯钢琴音色。音色交叉渐变中不改变当前声部的包络速度；下一次真实起音使用新音色策略。明亮弦音与哇音起音的原包络及寿命保持。
- 延音效果仍延长尾音。完整生产计数对照为旧 518141、新 255997 样本（约 10.795→5.333 秒，49.4%）；由于前 2048 样本仍按原速度计数以保留击弦，比例略小于一半。合唱／混响本身的延迟与反馈不变，因此效果器残响不保证正好减半。
- 松开品位只保留最后的目标音高，不产生新 Attack 或 note_off，不重置包络。重新按其他品位仍可滑音；松开全部品位后真实拨弦，会从空弦音高重新起音。
- 颤音仍只用于演奏模式：真实拨弦发声后，在约 600 ms 内三次松开／按回同一品位，每次松开 60～200 ms。第三次按回后启用约 6 Hz、±20 音分调制。松开仍取消当前颤音，保持原基础音高自然衰减；重新三次合格松按可再次启用。四弦独立，换品／重拨／自然结束／退出／复位的取消条件保持。

## 实现范围与验证

生产源码只改 `rtl/synth/piano_voice_core.v` 与 `rtl/control/guitar_play_control.v`。共享包络 ROM 不改，钢琴声部只在包络读地址与插值权重处使用双速年龄；自然寿命门控保证翻倍前年龄不超过65535，不会溢出17位。DDS、击弦及哇音仍使用原时间；播放控制器只忽略没有真实拨弦的零品位更新。约束、设备、工程设置及两个用户保护文件保持。

- `piano_short_rtl_01`：独立 ROM 地址／插值参考，三音区、四力度、三音色、延音／和声；170602 样本／43674112 时钟，26841 个非钢琴样本完全相同、14734 次击弦检查、自然寿命65536/131072样本，无deadline。
- `piano_short_sustain_01`：生产 MAX131072 延音计数全程，255997/518141 样本边界，无回绕或deadline。上述两项完成后播放控制器有变化，但其静态实例依赖闭包和原 ModelSim 加载日志都排除该模块，因此保留有效音源结果。
- `piano_hold_control_01`：四弦全部8品位松品保持、32次真实空弦重拨、同采样起音、无note_off；原33组颤音手势／时间边界／四弦独立／取消检查通过。
- `piano_hold_physical_01`：完整生产RTL与实体矩阵三次松按，检查保持音高、持续颤音、单弦换品／重拨取消、游戏／退出；最终结果以该目录收据为准。

V2 完整布线失败：Logic51080、Register20963、CLS28613/29952、BSRAM113、DSP115.5，533条未布通，没有新位流；源码／网表／失败报告保留于 `build/vibrato/piano_short_hold_v2/`。ADC、UART／显示和ID70姿态门级通过，但最后一个颤音门级长场景在候选被接续时主动停止，记录为FAIL而非PASS，不用于最终验收。

V3 将原本的整个frame_age转换及击弦反变换，改成只选择包络地址和插值权重。综合Logic50735（比V2多40，不宣称面积减少）、Register20963、逻辑BSRAM108，DSP原语保持。`piano_hold_audio_v3_01`重新通过相同独立包络／寿命／非钢琴对照（26841相同非钢琴样本、16782击弦检查）及生产延音全程；`piano_hold_physical_v3_01`通过23134音频样本／3685次MPU读包的完整生产矩阵颤音检查。控制器没有再次改变，继续使用全部输入字节未变的 `piano_hold_control_01`，不重跑该项。

原 `.gprj` 与原 `impl` 的V3综合／完整P&R／STA均已结束通过：Logic51119、Register20963、CLS28752/29952（96%）、物理BSRAM113/118、DSP115.5/118；系统要求50 MHz、实际Fmax51.657 MHz，音频要求12.288 MHz、实际17.396 MHz。setup／hold／latch／未布通和已测deadline均为0。保留两条既有PR1014通用时钟布线提示，STA已计入实际布线。

当前实际VG的四项门级收据均为PASS：`piano_hold_adc_gate_02`覆盖四弦四档力度／4739008时钟／32238转换；`piano_hold_full_gate_02`覆盖10次真实115200 UART事务／四声部／13397音频样本／16帧与5875200个LCD时钟样本；`piano_hold_posture_gate_02`覆盖ID70生产256包校准／12838音频样本／1773包／5次音色变化／11246883个LCD时钟样本；`piano_hold_gesture_gate_02`覆盖真实矩阵三次松按／松品保持音高／四弦独立／重拨／游戏／退出，26821音频样本／23500800个LCD时钟样本／4633包。LCD时钟样本不是独立像素数；仿真不带SDF，物理时序由单独的post-route STA验收。

证据目录 `build/vibrato/piano_short_hold_v3/`，最终检查器 `tools/check_piano_hold_result.py` 已PASS，认证 `gowin/neo_guitar_touch_game/piano_short_hold_verification.json`。原工程可用位流 `gowin/neo_guitar_touch_game/impl/pnr/neo_guitar_touch_game.fs`，独立发布 `build/releases/touch_game/neo_guitar_touch_game_piano_short_hold.fs`；SHA256 `16d1137fb6871eaaf3e25a4dc0e7df7d34c4ea777bfef05ce21443bafdb39b4e`，完整归档 `build/releases/touch_game/piano_short_hold_20261025/`。最初仅改钢琴的综合 `piano_short_v1` 因用户追加松品策略而停止，接续证据保留，未P&R或发布。

实际RTL输出的钢琴干声对照为 `build/piano_short/audio/piano_before_then_after.wav`，先旧音、静音0.3秒、后短音；相同24位／48k单声部PCM增益，不改变音高、不做响度归一化，非实物扬声器录音。

旧颤音 V6 固定发布 `build/releases/touch_game/neo_guitar_touch_game_vibrato.fs`（SHA256 `997baf9cfa57e3e6fd65250a3ab0452cde10802f53405043b50a3b748269566b`）和旧 ID70 发布保留。未自动推送、烧录或打开实物COM。
