# 图标缓存与设置入口验证

日期：2026-10-24。环境：macOS 15.8.1，Apple 芯片。修正版为本地 1.1，构建 14；没有新增正式版本日志或替换 GitHub 已发布附件。

## 现场证据

- 运行进程来自 `/Applications/PluginShelf.app`，原构建为 1.1 (13)。包内图标的 SHA-256 与已确认的书架 ICNS 相同。
- 用原生 API 分别读取文件图标、运行中应用图标和包内资源：前两者返回旧图标，直接读取资源返回新书架图标。记录保存在本地 `work/settings-diagnostics/before-icon/`。
- 旧设置入口使用原生 `SettingsLink`，但无边框标签只有图标和文字本身可点击。窗口已激活后，点击设置行右侧空白（此现场截图像素坐标 220, 1728）没有打开设置；点击文字（95, 1728）可以打开。
- 三次原构建重启后，精确点击设置按钮均能打开窗口。未复现用户描述的额外数秒卡住。
- 捕获一次从启动后约 182 毫秒开始的 5 秒调用栈；没有发现插件扫描长时间占用主线程。采样中包含辅助功能遍历开销，不能将自动化工具调用总时长视作应用响应时间，也不能据此排除所有间歇性延迟。

## 修改

| Before | After | Why |
| --- | --- | --- |
| 设置链接仅图标和文字可点击 | 标签填满可用宽度，至少 30 点高并设置矩形命中区域 | 避免看似点中同一行却没有响应 |
| 资源内容更改但仍沿用构建 13 和 `AppIcon` 名称 | 构建 14 使用 `AppIconBookshelf`，打包脚本读取实际声明的图标文件名 | 使系统登记新的图标资源；只重新登记本应用 |

保留原生 `Settings` 场景、菜单和快捷键，没有添加延时重试或另建设置窗口。

## 完成验证

- 71 项 Swift Testing 用例通过；arm64 和 x86_64 发布编译通过，最终应用为 Universal 2，严格签名校验通过。未新增 Intel 实机验证。
- 本机原应用保存在 `outputs/rollback-before-build14/PluginShelf.app`，新构建安装至 `/Applications/PluginShelf.app`。
- 新构建两次启动后，单次点击原先无响应的右侧空白处均打开原生设置窗口；⌘, 也正常打开。对应辅助功能记录在 `work/settings-diagnostics/build14-*.txt`。
- 系统图标服务、运行中应用和包内资源现在均返回新图标，记录在 `work/settings-diagnostics/after-icon/`。
- 原生“关于”窗口实见新书架图标及版本 1.1 (14)，截图为 `work/settings-diagnostics/about-build14.png`。
- DMG 完整性校验、只读挂载后的应用严格签名校验、应用与卷图标一致性、构建号及“应用程序”安装链接检查通过。
- 最终安装包：`outputs/PluginShelf-1.1-build14/PluginShelf-1.1-macOS-Universal.dmg`。
- SHA-256：`4dace1529f86d7e4adedf678d6189222904302da013b701bc78422d16e6a98c3`。
