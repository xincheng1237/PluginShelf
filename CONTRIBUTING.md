# 开发与维护

需要 macOS 14+、支持 Swift 6 的 Xcode 或 Command Line Tools。

```sh
swift test
./Packaging/build.sh
python3 -m pip install --target work/dmg-design/tools dmgbuild==1.6.5
./Packaging/dmg.sh
```

修改通过分支和 Pull Request 进入 main；CI 检查核心测试与 Universal 2 构建。文件操作变更必须覆盖原路径还原、冲突、符号链接、备份校验和到期清理，使用临时目录或隔离样本，不使用真实插件做破坏性测试。

发布前更新 Packaging/Info.plist、CHANGELOG.md，核对两个架构、严格签名检查、镜像校验、实际安装画面及基本交互。安装包放在 GitHub Releases，源码中不提交构建缓存、用户设置、插件文件或本机扫描清单。保留源代码与发行附件的对应关系；现有 1.0 安装包对应本仓库首次导入的应用源码。

本仓库暂未选定开源许可证；公开或改变授权方式前由所有者决定。
