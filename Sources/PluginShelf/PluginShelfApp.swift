import SwiftUI
import AppKit

@main
struct PluginShelfApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            LibraryView(model: model)
                .frame(minWidth: 760, minHeight: 480)
                .task { await model.start() }
                .task { await model.periodic() }
                .onAppear { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1240, height: 790)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(after: .newItem) {
                Button("重新扫描插件") { Task { await model.scan() } }.keyboardShortcut("r").disabled(model.busy)
                Button("从备份恢复…") { NotificationCenter.default.post(name: .chooseShelfBackup, object: nil) }.keyboardShortcut("o").disabled(model.busy)
            }
            CommandGroup(replacing: .help) {
                Button("PluginShelf 使用说明") {
                    model.detailMessage = "自动扫描标准音频插件目录。用 ⌘ 点选或 Shift 连选后，可批量备份或移到废纸篓。\n\n右上角可搜索名称、厂商或路径，空格分词时所有词均须匹配。\n\n添加时间来自文件系统的加入目录日期或创建日期，不等同于准确安装日期。\n\n备份为 .pluginshelfbackup 文件夹，可直接放入网盘；如需压缩，可在 Finder 压缩，恢复前先解压。外置音色库、授权与独立预设不包含在内。\n\n删除需两步确认，文件进入系统废纸篓。自动清理由 Finder 的“30 天后移除废纸篓中的项目”设置控制；手动清空会提前永久删除。应用内可查看删除记录、还原或经过两次确认后永久删除。1.0 的旧版废纸篓项目仍可还原或手动永久删除，不再自动清理。"
                }
            }
        }
        Settings { PreferencesView(model: model) }
    }
}
extension Notification.Name { static let chooseShelfBackup = Notification.Name("chooseShelfBackup") }
