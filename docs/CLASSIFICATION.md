# 插件类型识别 · 1.0

实现范围与使用方式见 README 的“类型识别”。当前阶段采用只读元数据识别与用户手动修正；没有加载二进制的深入识别。

## 依据

- Apple Audio Unit 类型：https://developer.apple.com/documentation/AudioToolbox/kAudioUnitType_MusicEffect
- Steinberg VST3 类别：https://steinbergmedia.github.io/vst3_doc/vstinterfaces/group__plugType.html
- VST3 JSON5 元数据与旧位置：https://steinbergmedia.github.io/vst3_dev_portal/pages/Technical%2BDocumentation/VST%2BModule%2BArchitecture/ModuleInfo-JSON.html
- LV2 标准分类：https://lv2plug.in/ns/lv2core
- LV2 manifest 与 seeAlso：https://lv2plug.in/pages/bundle-definition.html

## 覆盖率的含义

2026-10-20 本机只读扫描：46 个插件文件包，2 个效果器、2 个虚拟乐器、42 个未识别、0 个其他。该机器主要安装 AAX，很多插件没有可静态读取的类型声明。此数据是元数据识别覆盖率，不是准确率评估，也不代表其他机器。没有为了测试而改动、移动或删除真实插件文件。

## 存储与兼容

- 手动分类保存在 PluginShelf 自己的数据目录 category-overrides.json。
- 自动分类每次扫描重新读取，原始类型不因手动修正而消失。
- 旧 Plugin 快照缺少新增字段时仍可解码，原有 schema 1 备份保持可读取。分类是应用资料，不会被写入插件备份清单。
- 分类记录损坏时，扫描仍返回自动识别结果并提示；原文件保留，不自动覆盖。
- LV2 只读取包内本地 ttl，限制单文件 2 MB、总计 4 MB、最多 64 个文件。不支持的 Turtle/RDF 声明保守处理为未识别，不联网推理。

## 验证

arm64 与 Rosetta x86_64 均通过 33/33 项测试。新增测试覆盖 AU 多组件/MIDI 效果器/发生器、AUv3 扩展属性、VST3 JSON5/旧位置/忽略控制器/混合标签、缺失损坏与外部链接元数据、LV2 多主体与局部 seeAlso/注释及字符串误识别/越界和网络引用、手动分类持久化与恢复自动识别、批量修改与局部恢复、同路径不同 Bundle ID、旧快照兼容、分类记录损坏时不隐藏资料库。

原生界面用隔离演示样本验证四类筛选、双分类保存及数量联动、详情声明依据、多组件包删除第一页、重启后的手动分类保留与恢复自动识别；未确认或执行样本删除。
