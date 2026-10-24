import SwiftUI
import PluginShelfCore
import AppKit

struct PreferencesView: View {
    @Environment(\.locale) private var interfaceLocale
    @AppStorage("app.language") private var language = "system"
    @ObservedObject var model: AppModel
    @ObservedObject var updater: SoftwareUpdater
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        TabView {
            Form {
                Section {
                    Picker(L("语言"), selection: $language) {
                        Text("简体中文").tag("zh-Hans")
                        Text("English").tag("en")
                        Text(L("跟随系统")).tag("system")
                    }
                    Text(L("系统为简体或繁体中文时显示简体中文，其他语言显示英文。系统菜单和文件对话框在重新打开应用后切换。"))
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Label(L("语言"), systemImage: "globe") }
                Section {
                    LabeledContent(L("版本"), value: updater.currentVersion)
                    Toggle(L("自动检查更新"), isOn: $updater.automatic)
                    HStack(spacing: 12) {
                        if updater.isWorking { ProgressView().controlSize(.small) }
                        Text(updater.statusText).font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(L("检查更新…")) {
                            openWindow(id: "software-update")
                            Task { await updater.check(manual: true) }
                        }.fixedSize()
                        Button(L("更新日志…")) { openWindow(id: "release-notes") }.fixedSize()
                    }
                    if let date = updater.lastAttempt {
                        Text(L("上次检查于 \(date.appFormatted(date: .abbreviated, time: .shortened))"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Label(L("软件更新"), systemImage: "arrow.down.circle") }
                Section {
                    Text(L("新删除的插件会进入系统废纸篓。"))
                    Text(L("如需自动清理，请在 Finder → 设置 → 高级中勾选“30 天后移除废纸篓中的项目”。此设置影响整个系统废纸篓；手动清空会提前永久删除。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(L("打开系统废纸篓"), action: model.openSystemTrash)
                } header: { Label(L("废纸篓"), systemImage: "trash") }
            }.formStyle(.grouped)
                .tabItem { Label(L("通用"), systemImage: "gearshape") }
            Form {
                Section {
                    Toggle(L("自动刷新插件资料库"), isOn: $model.autoRefresh)
                    Text(L("启动时自动扫描；启用后每 5 分钟重新扫描。"))
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(model.customRoots) { root in
                        HStack {
                            Text(root.path).font(.caption).textSelection(.enabled)
                            Spacer()
                            Button { model.removeRoot(root) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).help(L("移除扫描目录，不删除插件"))
                        }
                    }
                    Button(L("添加自定义插件目录…"), action: model.addRoot)
                    Text(L("自动扫描用户及共享资源库的 AU、VST2、VST3、AAX、CLAP、LV2、RTAS 目录，并查看应用内 AUv3。非标准目录可手动添加。宿主内置效果、部分脚本格式与云端插件不在管理范围。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
                .tabItem { Label(L("扫描"), systemImage: "magnifyingglass") }
            Form {
                Section {
                    Text(L("备份以命名文件夹导出，并附 SHA-256 校验清单。移动到网盘前请等待导出完成。恢复前先完整下载到本机；若自行压缩，请先解压。"))
                    Text(L("备份仅包含选中的插件文件，不包含授权、外置音色库、独立预设或安装器依赖。跨电脑恢复可能仍需厂商安装器与重新授权。"))
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Label(L("备份边界"), systemImage: "archivebox") }
            }.formStyle(.grouped)
                .tabItem { Label(L("备份"), systemImage: "archivebox") }
        }.padding(12).frame(width: 620, height: 650)
    }
}
