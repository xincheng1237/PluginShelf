# 检查更新与语言维护

发布版本：1.1，构建 18，按所有者要求替换同版本构建 15。发布源为本仓库公开的 GitHub Releases。

更新源为 https://api.github.com/repos/xincheng1237/PluginShelf/releases/latest，仅请求公开正式 Release，不使用内置凭证。仓库私有、没有正式发布或网络不可达时显示检查失败，自动检查失败不弹窗。启动等待 8 秒后检查，成功与失败尝试都记录时间，24 小时内不自动重试；手动操作可以立即检查。

提示条的关闭会推迟提醒 24 小时；跳过版本保持到出现更高版本，手动检查仍可查看。关闭自动检查不影响手动入口。检查与下载都在现有应用进程中执行，没有登录项或常驻服务。

正式发布要求：

- 使用普通稳定版号，例如 v1.2 或 v1.2.0，不以草稿或预发布作为自动更新。
- 安装附件使用 PluginShelf-版本号-macOS-Universal.dmg，上传状态需为 uploaded。
- 应用读取 GitHub 提供的 sha256 摘要，下载后核对长度与内容，校验失败不保留文件。
- 用户选择保存位置后下载；不会覆盖已有文件。校验后打开 DMG，用户退出并拖动替换应用。
- 自动更新提示要求新版号高于安装版本；当前客户端不比较内部构建号。此次按所有者要求覆盖 1.1，因此旧 1.1 用户需手动下载构建 18；已安装 1.0 的更新检查仍可发现并下载 1.1。

语言资源：Sources/PluginShelfCore/Resources/English.json。界面与错误信息使用可插值的 L 消息，保留动态路径、名称与参数。分类枚举 rawValue、扫描路径、备份清单及用户数据不因界面语言改变。原生菜单语言使用应用自己的 AppleLanguages 偏好，重新打开后生效，不修改系统全局语言。

用户日志在应用中按当前语言选择，中文与英文文档分别维护为 CHANGELOG.md 与 CHANGELOG.en.md。仅收录实际完成的变化，不为每次修改增加版本条目。

参考：[GitHub Releases API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)、[Apple appInfo 命令位置](https://developer.apple.com/documentation/swiftui/commandgroupplacement/appinfo)、[Apple ByteCountFormatStyle](https://developer.apple.com/documentation/foundation/bytecountformatstyle)。
