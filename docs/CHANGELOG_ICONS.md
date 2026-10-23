# 更新日志图标来源

采用用户提供的 changelog-icons-matched 素材包，并对照原项目 Views.swift 中的 ChangelogView 与 ChangelogItemKind。新素材保留原应用的 13 pt 常规字体和 `.foregroundStyle(.primary, color)` 双层配色；上一份素材的白色对勾与整体染色不再采用。

| 分类 | 原生符号 | 配色 |
| --- | --- | --- |
| 首版功能 / 新增功能 | checkmark.circle.fill | primary 对勾、绿色圆面 |
| 优化改进 | wand.and.stars | primary 魔杖、蓝色星星 |
| 问题修复 | wrench.and.screwdriver.fill | primary 扳手、橙色螺丝刀 |

应用直接使用原生 `Label`，符号随正文系统字号显示，不再使用 resizable、固定图标画布、额外底板、渐变和阴影。primary 随浅色与深色外观适配；PNG 仅作参考，不作为固定浅色位图嵌入应用。

日志使用系统文本内容背景色、系统字体与原生完成按钮；中文和英文复用同一组件。应用不依赖另一项目的绝对路径或外部导出目录。
