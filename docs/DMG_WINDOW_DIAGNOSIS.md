# Finder 安装窗口栏位对照记录

日期：2026-10-23。本机验证；不代表所有 macOS 版本的通用结论。

## 结果

PluginShelf 镜像中已存在 ShowStatusBar、ShowTabView、ShowPathbar、ShowToolbar 等隐藏默认值。当前 Finder 会将新窗口的部分显示偏好覆盖到只读安装卷。仅比较已经打开的窗口截图，会混入窗口保留状态和打开时偏好的差异。

测试中，在工作区测试窗口隐藏状态栏、路径栏时，Finder 同时改变了新窗口默认值；这一步干扰了随后部分对照窗口的显示。已通过 Finder 原生菜单还原原有显示，最终读取 ShowStatusBar=1、ShowPathbar=1，标签栏也恢复为可见。用户原来的其他 Finder 窗口未用于修改设置。

在还原的同一组偏好下，正常卸载并从 Finder 再次打开原始 Ollama.dmg 和 TheUnarchiver.dmg，两者均出现状态栏、标签栏、路径栏，与 PluginShelf 最终安装窗口一致。未安装或运行两款对照应用，未修改原 DMG。

## 排除的假设

| 对照 | 单独改变的条件 | 实际结果 |
| --- | --- | --- |
| A | 省略旧式默认视图 icvl 记录 | 多余栏位仍出现 |
| B | bwsp 仅保留正常镜像使用的窗口字段 | 多余栏位仍出现 |
| C | 背景书签按原生 1500 字节分段记录写入 | 多余栏位仍出现 |
| 原生内容副本 | 复制 The Unarchiver 全部内容及 DS_Store 到新镜像 | 同组偏好下仍出现栏位 |
| 原始对照包重新挂载 | 排除已有窗口保留状态 | Ollama、The Unarchiver 均复现 |

另验证了 HFS+ 自动打开目录标记的路径；本机 bless 明确返回 Apple Silicon 不支持 openfolder。没有将失败或未经验证的磁盘头修改加入打包流程。

## 本轮交付边界

- 保留标准 DMG 与隐藏默认参数，不更改安装用户的 Finder 全局设置，不添加安装启动脚本。
- 本机尚未找到可由 DMG 本身可靠强制隐藏这些栏位的方法；不将此项记录为“已修复”。
- 采用原生 Label、系统字号和双层前景色的更新日志已完成，独立验收副本的中英文、深浅色与完成按钮均已检查。
- 专用对照卷全部卸载，独立日志验收进程已退出。最终交付镜像在 Finder 打开供用户查看。

本地证据：work/finder-unarchiver-after-remount.txt、work/finder-final-1.1-review5.txt、work/finder-final-1.1-review5.png、work/1.1-native-review-verification.json。打包工具的隐藏选项见 [dmgbuild 官方文档](https://dmgbuild.readthedocs.io/en/latest/example.html)；以上现象结论来自本机复现，而非仅依据选项名称推断。

## 2026-10-24 本机偏好调整

用户随后明确要求直接修改本机 Finder 设置。已通过 Finder 原生“显示”菜单隐藏状态栏和标签页栏，并通过实际安装窗口截图确认两行额外区域消失。路径栏保留；这次是用户授权的本机显示偏好调整，不是修改 DMG，也不改变其他电脑的 Finder 偏好。
