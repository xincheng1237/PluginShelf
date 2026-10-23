import SwiftUI
import AppKit
import PluginShelfCore

struct UpdateCommands: Commands {
    let language: String
    @ObservedObject var updater: SoftwareUpdater
    @Environment(\.openWindow) private var openWindow
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(L("检查更新…")) {
                openWindow(id: "software-update")
                Task { await updater.check(manual: true) }
            }
        }
    }
}

struct UpdateBanner: View {
    @Environment(\.locale) private var interfaceLocale
    @ObservedObject var updater: SoftwareUpdater
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        if updater.showBanner, let update = updater.available {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle").foregroundStyle(Color.accentColor).accessibilityHidden(true)
                    Text(L("PluginShelf \(update.version.text) 可供更新")).font(.callout).lineLimit(1)
                    Spacer(minLength: 8)
                    Button(L("查看更新")) { updater.dismissBanner(); openWindow(id: "software-update") }
                    Button { updater.dismissBanner() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help(L("稍后提醒")).accessibilityLabel(L("稍后提醒更新"))
                }.padding(.horizontal, 20).padding(.vertical, 10)
                Divider()
            }.background(.bar)
        }
    }
}

struct SoftwareUpdateView: View {
    @Environment(\.locale) private var interfaceLocale
    @ObservedObject var updater: SoftwareUpdater
    @Environment(\.dismissWindow) private var dismissWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("软件更新")).font(.title2.bold())
                    Text(L("当前版本 \(updater.currentVersion)")).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            VStack(alignment: .leading, spacing: 14) { content }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            HStack {
                Link(L("前往 GitHub"), destination: GitHubUpdates.releasesURL)
                Spacer()
                if case .downloading = updater.state {
                    Button(L("取消下载"), action: updater.cancelDownload)
                } else if let update = updater.available {
                    if case .ready(_, let file) = updater.state {
                        Button(L("打开安装包")) { NSWorkspace.shared.open(file) }.buttonStyle(.borderedProminent)
                    } else {
                        Button(L("跳过此版本")) { updater.skip(update); dismissWindow(id: "software-update") }
                        Button(L("下载更新…")) { updater.chooseDownload(update) }
                            .buttonStyle(.borderedProminent).disabled(update.installer == nil)
                    }
                } else {
                    Button(L("检查更新")) { Task { await updater.check(manual: true) } }
                        .buttonStyle(.borderedProminent).disabled(updater.isWorking)
                }
            }
        }.padding(24).frame(width: 550, height: 470)
    }
    @ViewBuilder private var content: some View {
        switch updater.state {
        case .idle:
            Text(L("检查是否有可用的新版本。")).foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 12) { ProgressView().controlSize(.small); Text(L("正在检查更新…")) }
        case .current:
            Label(L("已是最新版本"), systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
            Text(L("你正在使用 PluginShelf \(updater.currentVersion)。")).foregroundStyle(.secondary)
        case .failed(let message):
            Label(L("暂时无法完成更新"), systemImage: "exclamationmark.triangle").font(.headline)
            Text(L10n.rendered(message)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .available(let update):
            Text(L("发现新版本 \(update.version.text)")).font(.headline)
            if update.installer == nil {
                Text(L("该版本暂未提供可校验的安装包，请前往 GitHub 查看。")).foregroundStyle(.secondary)
            } else {
                Text(L("下载后打开安装包，退出当前应用并拖入“应用程序”即可安装。")).font(.callout).foregroundStyle(.secondary)
            }
            ScrollView {
                Text(update.notes.isEmpty ? L("此版本暂未提供更新说明。") : update.notes)
                    .textSelection(.enabled).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            }
        case .downloading(let update):
            HStack(spacing: 12) { ProgressView().controlSize(.small); Text(L("正在下载 PluginShelf \(update.version.text)…")) }
            Text(L("下载完成后会校验文件并打开安装包。")).foregroundStyle(.secondary)
        case .ready(let update, _):
            Label(L("PluginShelf \(update.version.text) 已下载"), systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
            Text(L("请退出当前应用，将安装包中的 PluginShelf 拖入“应用程序”并替换旧版。")).foregroundStyle(.secondary)
        }
    }
}
