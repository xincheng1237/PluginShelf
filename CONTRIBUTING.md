# 开发与维护

需要 macOS 14+、支持 Swift 6 的 Xcode 或 Command Line Tools。

```sh
swift test
./Packaging/build.sh
python3 -m pip install --target work/dmg-design/tools dmgbuild==1.6.5
./Packaging/dmg.sh
```

修改通过分支和 Pull Request 进入 main；CI 检查核心测试与 Universal 2 构建。文件操作变更必须覆盖原路径还原、冲突、符号链接、备份校验和系统废纸篓记录同步，使用临时目录或隔离样本，不使用真实插件做破坏性测试。

发布前更新 Packaging/Info.plist、CHANGELOG.md，核对两个架构、严格签名检查、镜像校验、实际安装画面及基本交互。安装包放在 GitHub Releases，源码中不提交构建缓存、用户设置、插件文件或本机扫描清单。保留源代码与发行附件的对应关系；现有 1.0 安装包对应本仓库首次导入的应用源码。

仓库源码公开，但暂未提供开源许可证；变更授权方式需由所有者决定。

## 发布约定

用户更新内容在 CHANGELOG.md 与 CHANGELOG.en.md 分别维护。初版只介绍已有能力，后续版本按实际变化列出新增、优化、修复；小调整累计到所有者确认的正式版本中。

安装附件命名为 `PluginShelf-版本号-macOS-Universal.dmg`，同时提供 `.sha256`。发布必须使用稳定版标签（例如 `v1.1`），并确认 GitHub 为 DMG 提供 `sha256:` 摘要。只有公开、非草稿、非预发布的最新 Release 才能作为应用的更新源。

公开发布后不要替换相同版本的安装包；后续修改使用经所有者确认的更高版本号。同版本号的内部构建差异不会触发应用更新。公开首发 1.1 的来源是本次合并的源码与构建 13。

发布后以不带凭证的请求核对 latest Release、附件下载、文件大小与 SHA-256，并确认当前版本不提示升级、较旧版本能读取新包。检查更新的详细协议见 [docs/UPDATES.md](docs/UPDATES.md)。
