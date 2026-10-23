import PluginShelfCore
import SwiftUI
import AppKit

@main
struct PluginShelfApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updater = SoftwareUpdater()
    @AppStorage("app.language") private var language = "system"
    init() { L10n.configureSystemMenus() }
    var body: some Scene {
        WindowGroup {
            LibraryView(model: model, updater: updater)
                .environment(\.locale, L10n.locale)
                .frame(minWidth: 760, minHeight: 480)
                .task { await model.start() }
                .task { await model.periodic() }
                .task { if !model.isDemo { await updater.checkAtLaunch() } }
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1240, height: 790)
        .windowStyle(.automatic)
        .onChange(of: language) { _, _ in
            L10n.configureSystemMenus()
            Task { await model.scan() }
        }
        .commands {
            UpdateCommands(language: language, updater: updater)
            CommandGroup(after: .newItem) {
                Button(L("重新扫描插件")) { Task { await model.scan() } }.keyboardShortcut("r").disabled(model.busy)
                Button(L("从备份恢复…")) { NotificationCenter.default.post(name: .chooseShelfBackup, object: nil) }.keyboardShortcut("o").disabled(model.busy)
            }
            CommandGroup(replacing: .help) {
                Button(L("PluginShelf 使用说明")) {
                    model.detailMessage = L("自动扫描标准音频插件目录。用 ⌘ 点选或 Shift 连选后，可批量备份或移到废纸篓。\n\n右上角可搜索名称、厂商或路径，空格分词时所有词均须匹配。\n\n添加时间来自文件系统的加入目录日期或创建日期，不等同于准确安装日期。\n\n备份为 .pluginshelfbackup 文件夹，可直接放入网盘；如需压缩，可在 Finder 压缩，恢复前先解压。外置音色库、授权与独立预设不包含在内。\n\n删除需两步确认，文件进入系统废纸篓。自动清理由 Finder 的“30 天后移除废纸篓中的项目”设置控制；手动清空会提前永久删除。应用内可查看删除记录、还原或经过两次确认后永久删除。1.0 的旧版废纸篓项目仍可还原或手动永久删除，不再自动清理。")
                }
            }
        }
        Settings { PreferencesView(model: model, updater: updater).environment(\.locale, L10n.locale) }
        Window(L("软件更新"), id: "software-update") { SoftwareUpdateView(updater: updater).environment(\.locale, L10n.locale) }
            .windowResizability(.contentSize)
        Window(L("更新日志"), id: "release-notes") { ReleaseNotesView().environment(\.locale, L10n.locale) }
            .windowResizability(.contentSize)
    }
}
extension Notification.Name { static let chooseShelfBackup = Notification.Name("chooseShelfBackup") }
