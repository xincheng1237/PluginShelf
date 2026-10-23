# 分类资料库与同产品关联

版本：2026.10.21，随 PluginShelf 1.0 构建 7 离线发布。代码位于 `Sources/PluginShelfCore/ClassificationCatalog.swift` 和 `ClassificationResolver.swift`。这是产品用途资料库，不是对插件签名、授权或文件真实性的验证。

## 识别顺序

1. 保留插件自己的声明，包含多组件、混合用途及部分未识别的结果。
2. 仅对无分类或全部未识别的插件，尝试关联本机 AU/AUv3/VST3 的原始声明。
3. 没有合适关联时查已核实资料库。
4. 没有依据时保持未识别；手动设置始终覆盖自动结果。

关联须同时满足同一产品、同一数值版本、不同格式。通用匹配要求 Bundle ID 完全相同，名称仅规范大小写和空白；不同 Bundle ID 只允许资料库中逐项登记的别名。目前明确登记 Melodyne 的 AU/VST3/AAX 标识；不会自动删掉 `.au`、`.aax` 等后缀。名称里的 Lite、GE 等版本/产品区别不会去掉。

来源必须有完整的单组件、单用途声明；不把多组件包或 Fx/Instrument 混合声明套给其他格式。手动分类、资料库结果、其他关联结果都不会成为来源，避免链式推断。多个来源互相矛盾，或来源与已核实资料冲突时，显示“分类依据冲突 · 待确认”，不强行归类。每次完整扫描重新计算，不保存上一次关联；来源移除后不会保留陈旧推断。

关联结果只标识目标文件包用途，不伪造目标包组件清单。原先已读取的组件信息保留，备份、删除始终按完整文件包操作。

## 首批记录（33 个产品）

| 产品 | 用途映射 | 适用插件主版本 | 依据 |
| --- | --- | --- | --- |
| AutoPan、BF-76、ChannelStrip、DVerb、Dither、DownMixer、DynamicsIII、EQIII、Eleven Lite、LoFi、Maxim、ModDelay_III、Normalize-Gain、Pitch Shift Legacy、PitchII、RectiFi、Reverse-DC Removal、SansAmp PSA-1、SciFi、Time Shift、TimeAdjuster、Trim、VariFi、Invert-Duplicate | 效果器（含音频处理工具；组合包整体归类） | 25 | Avid 指南中的对应产品与处理功能 |
| ClickII | 虚拟乐器（节拍器声音发生器） | 25 | Avid 指南 Instrument Plug-Ins，第 57 章 |
| InTune、MasterMeter、SignalGenerator | 其他（调音、计量、测试信号） | 25 | Avid 指南 Other Plug-Ins，第 59–61 章 |
| NoteStack、PitchControl、VelocityControl | 效果器（MIDI 处理） | 25 | Avid 官方 MIDI 效果器介绍 |
| Melodyne | 效果器 | 5 | Celemony 官方音频编辑说明，及本机 AU 声明 |
| TDR Nova | 效果器 | 2 | Tokyo Dawn Labs 官方均衡与动态处理说明，及本机 AU 声明 |

Avid 标识逐条登记为 `com.AVID.plugin.<产品名>`；Invert-Duplicate 使用实际 `com.digidesign.plugin.Invert-Duplicate`。名称也须与已登记产品匹配。并未对整个 `com.AVID` 厂商前缀批量设分类。仅支持本次实际读取到的插件主版本 25，未知旧/新主版本不会套用资料库。

Melodyne 登记 `com.celemony.melodyne.au`、`.vst3`、`.aax`；TDR Nova 登记 AU/VST2/VST3/AAX 下的 `com.TokyoDawnLabs.TDRNova`。这些身份字段来自本机对应包内 Info.plist，版本与格式限制写在每条记录中；官网资料用于确认用途，不宣称官网发布了这些 Bundle ID。

## 官方来源（核对日期 2026-10-21）

- [Avid Audio Plug-Ins Guide 2018.1](https://resources.avid.com/SupportFiles/PT/Audio_Plug-Ins_Guide_2018.1.pdf)：历史产品的功能说明和章节分类。只保存映射与链接，没有随应用转载指南。
- [Avid 当前 Pro Tools Studio 插件清单](https://www.avid.com/pro-tools/whats-included-studio)：产品及 MIDI 效果器类别交叉核对。
- [Avid MIDI effects](https://www.avid.com/resource-center/midi-plugins)：Note Stack、Pitch Control、Velocity Control 处理 MIDI。
- [Celemony：What is Melodyne](https://www.celemony.com/en/melodyne/what-is-melodyne)：录制音频的音高、时间和音色编辑。
- [Tokyo Dawn Labs：NOVA Manual](https://docs.tokyodawn.net/nova-manual/)：动态均衡与压缩处理。

## 验证与维护

单元测试覆盖误用 Bundle ID、同名不同产品、Lite 名称、未知/格式错误版本、版本不匹配、不同后缀不能擅自归一、来源冲突、多组件/混合用途、原始声明优先、手动覆盖和重置、来源移除及旧数据解码。新增资料须逐项提供官方用途来源、身份观测和版本范围，并补充防误匹配检查。

本机只读扫描结果见 `classification-audit-20261021.json`：46 项中 40 项已分类，其中 AAX 37 项中 33 项已分类。分类来源为原始声明 4 项、已核实资料 31 项、关联 AU 5 项。没有加载任何插件可执行代码，也未移动或改写真实插件。
