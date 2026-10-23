import SwiftUI
import AppKit
import PluginShelfCore

@MainActor
final class AppModel: ObservableObject {
    @Published var plugins: [Plugin] = []
    @Published var recovery: [RecoveryRecord] = []
    @Published var selection = Set<String>()
    @Published var recoverySelection = Set<UUID>()
    @Published var route: String? = "all"
    @Published var search = ""
    @Published var days = 0
    @Published var sortOrder = LibrarySort.nameAscending.comparators
    @Published var busy = false
    @Published var activity = "准备就绪"
    @Published var lastScan: Date?
    @Published var scanWarnings: [String] = []
    @Published var notice = ""
    @Published var detailMessage: String?
    @Published var showInspector = true
    @Published var customRoots: [ScanRoot] = []
    @Published var retentionDays: Int { didSet { UserDefaults.standard.set(retentionDays, forKey: "retentionDays") } }
    @Published var autoRefresh: Bool { didSet { UserDefaults.standard.set(autoRefresh, forKey: "autoRefresh") } }
    let engine: LibraryEngine
    let dataDirectory: URL
    let isDemo: Bool
    private var started = false
    init() {
        let defaults = UserDefaults.standard
        retentionDays = max(1, min(defaults.object(forKey: "retentionDays") as? Int ?? 30, 365))
        autoRefresh = defaults.object(forKey: "autoRefresh") as? Bool ?? true
        isDemo = ProcessInfo.processInfo.arguments.contains("--demo")
        if let data = defaults.data(forKey: "customRoots"), let roots = try? JSONDecoder().decode([ScanRoot].self, from: data) { customRoots = roots }
        if let override = ProcessInfo.processInfo.environment["PLUGINSHELF_DATA_DIR"] {
            dataDirectory = URL(fileURLWithPath: override)
        } else {
            dataDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PluginShelf")
        }
        engine = LibraryEngine(dataDirectory: dataDirectory)
    }
    var roots: [ScanRoot] { isDemo ? [ScanRoot(path: dataDirectory.appendingPathComponent("DemoPlugins").path, title: "演示样本")] : ScanRoot.standard + customRoots }
    var filtered: [Plugin] {
        var query = PluginQuery(); query.text = search
        query.days = route == "recent" ? max(1, days == 0 ? 30 : days) : days
        query.format = PluginFormat.allCases.first { route == $0.rawValue }
        query.category = PluginCategory.allCases.first { route == $0.route }
        return plugins.filter { query.matches($0) }.sorted(using: sortOrder)
    }
    var currentSort: LibrarySort? { LibrarySort.matching(sortOrder) }
    var selected: [Plugin] { filtered.filter { selection.contains($0.id) } }
    var manageable: [Plugin] { selected.filter(\.canManage) }
    var title: String {
        if let category = PluginCategory.allCases.first(where: { route == $0.route }) { return category.rawValue }
        return switch route {
        case "recent": "最近添加"
        case "recovery": "废纸篓"
        case "all", nil: "所有插件"
        default: "\(route ?? "") 插件"
        }
    }
    var totalBytes: Int64 { plugins.reduce(0) { $0 + $1.bytes } }
    var selectedBytes: Int64 { selected.reduce(0) { $0 + $1.bytes } }
    var hostNames: [String] {
        let hostIDs = ["com.apple.logic10", "com.apple.mobilelogic", "com.apple.garageband10", "com.avid.ProTools", "com.cockos.reaper", "com.ableton.live", "com.steinberg.cubase", "com.bitwig.BitwigStudio", "com.presonus.studioone"]
        return NSWorkspace.shared.runningApplications.filter { app in hostIDs.contains { (app.bundleIdentifier ?? "").localizedCaseInsensitiveContains($0) } }.compactMap(\.localizedName)
    }
    func start() async {
        guard !started else { return }; started = true
        if isDemo { makeDemo() }
        await scan()
        await checkExpiry()
    }
    func scan() async {
        guard !busy else { return }
        busy = true; activity = "正在扫描插件…"
        defer { busy = false; activity = "准备就绪" }
        do {
            let apps = isDemo ? [] : [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
            let report = try await engine.scan(roots: roots, applications: apps)
            plugins = report.plugins; scanWarnings = report.warnings; lastScan = Date()
            selection.formIntersection(Set(plugins.map(\.id)))
            recovery = try await engine.recoveryRecords()
        } catch { present(error) }
    }
    func checkExpiry() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let report = try await engine.purgeExpired()
            recovery = try await engine.recoveryRecords()
            if !report.completed.isEmpty || !report.failures.isEmpty { showReport(report, action: "到期清理") }
        } catch { present(error) }
    }
    func setCategories(_ categories: [PluginCategory]?, for items: [Plugin]) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await engine.setCategories(categories, for: items)
            let ids = Set(items.map(\.id))
            for index in plugins.indices where ids.contains(plugins[index].id) {
                plugins[index].categoryOverride = categories.map(PluginCategory.normalized)
            }
            selection.formIntersection(Set(filtered.map(\.id)))
            notice = categories == nil ? "已恢复自动分类" : "已更新 \(items.count) 项插件的分类"
        } catch { present(error) }
    }
    func periodic() async {
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            await checkExpiry()
            if autoRefresh, Date().timeIntervalSince(lastScan ?? .distantPast) >= 300 { await scan() }
        }
    }
    func exportSelection() {
        let items = manageable
        guard !items.isEmpty, !busy else { return }
        let panel = NSSavePanel()
        panel.title = "导出插件备份文件夹"; panel.prompt = "导出备份"
        let stamp = Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
        panel.nameFieldStringValue = "PluginShelf-\(stamp)-\(items.count)项.pluginshelfbackup"
        panel.canCreateDirectories = true
        panel.message = "备份包含插件文件、原路径与 SHA-256 校验清单。不包含外置音色库、许可证或独立预设。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard !FileManager.default.fileExists(atPath: url.path) else { detailMessage = "请选择一个不存在的新文件夹名称，备份不会覆盖已有文件。"; return }
        busy = true; activity = "正在复制并校验备份…"
        Task {
            defer { busy = false; activity = "准备就绪" }
            do {
                _ = try await engine.export(items, to: url, roots: roots)
                notice = "已备份 \(items.count) 项插件"
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch { present(error) }
        }
    }
    func chooseBackup() async -> (URL, BackupManifest)? {
        guard !busy else { return nil }
        let panel = NSOpenPanel(); panel.title = "选择 PluginShelf 备份文件夹"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.message = "选择含 manifest.json 的 .pluginshelfbackup 文件夹；若已压缩，请先在 Finder 中解压。"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return await inspectBackup(url)
    }
    func inspectBackup(_ url: URL) async -> (URL, BackupManifest)? {
        guard !busy else { return nil }
        busy = true; activity = "正在验证备份完整性…"
        defer { busy = false; activity = "准备就绪" }
        do { return (url, try await engine.inspectBackup(url, roots: roots)) }
        catch { present(error); return nil }
    }
    func restoreBackup(_ url: URL) async {
        guard !busy else { return }; busy = true; activity = "正在恢复插件…"
        do { showReport(try await engine.restoreBackup(url, roots: roots), action: "备份恢复") } catch { present(error) }
        busy = false; await scan()
    }
    func delete(_ snapshot: [Plugin], retentionDays: Int) async {
        guard !busy else { return }; busy = true; activity = "正在移到废纸篓…"
        do { showReport(try await engine.remove(snapshot, roots: roots, retentionDays: retentionDays), action: "移到废纸篓") }
        catch { present(error) }
        selection.removeAll(); busy = false; await scan()
    }
    func restoreDeleted() async {
        guard !busy, !recoverySelection.isEmpty else { return }; busy = true; activity = "正在还原…"
        do { showReport(try await engine.restoreRecovery(recoverySelection, roots: roots), action: "还原") } catch { present(error) }
        recoverySelection.removeAll(); busy = false; await scan()
    }
    func addRoot() {
        let panel = NSOpenPanel(); panel.title = "添加自定义插件目录"; panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.message = "选择专门的插件目录，避免选择整个磁盘、用户目录或应用程序目录。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.resolvingSymlinksInPath().path
        let forbidden = ["/", "/Library", "/Applications", "/Users", FileManager.default.homeDirectoryForCurrentUser.path, "/Volumes"]
        guard !forbidden.contains(path), !path.hasPrefix("/System"), !url.pathComponents.contains(where: { $0.hasSuffix(".app") }) else { detailMessage = "请选择专门用于安装插件的文件夹。"; return }
        guard !roots.contains(where: { $0.path == path }) else { return }
        customRoots.append(ScanRoot(path: path, title: "自定义目录")); saveRoots()
        Task { await scan() }
    }
    func removeRoot(_ root: ScanRoot) { customRoots.removeAll { $0 == root }; saveRoots(); Task { await scan() } }
    private func saveRoots() { UserDefaults.standard.set(try? JSONEncoder().encode(customRoots), forKey: "customRoots") }
    private func showReport(_ report: OperationReport, action: String) {
        notice = "\(action)：\(report.summary)"
        if !report.failures.isEmpty { detailMessage = notice + "\n\n" + report.failures.joined(separator: "\n\n") + "\n\n若目录受权限保护，请在 Finder 中核对权限；本版本不会绕过系统权限。" }
    }
    private func present(_ error: any Error) { detailMessage = error.localizedDescription }
    private func makeDemo() {
        let root = dataDirectory.appendingPathComponent("DemoPlugins")
        guard !FileManager.default.fileExists(atPath: root.path) else { return }
        let demos = [("Aurora", "vst3", "North Audio"), ("Paper Piano", "component", "Small Hours"), ("Tape Study", "clap", "Field Notes"), ("Room No. 8", "vst3", "North Audio"), ("Low Tide", "aaxplugin", "Still Sound"), ("Glass Echo", "vst", "Field Notes")]
        for (name, ext, vendor) in demos {
            let bundle = root.appendingPathComponent(name + "." + ext).appendingPathComponent("Contents")
            do {
                try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
                let plist: [String: Any] = ["CFBundleName": name, "CFBundleShortVersionString": "1.0.0", "CFBundleIdentifier": "studio.\(vendor.replacingOccurrences(of: " ", with: "")).\(name.replacingOccurrences(of: " ", with: ""))", "AudioComponents": [["name": vendor + ": " + name, "type": "aumu"]]]
                try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: bundle.appendingPathComponent("Info.plist"))
                if ext == "vst3" {
                    let resources = bundle.appendingPathComponent("Resources")
                    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
                    let info: [String: Any] = ["Classes": [["CID": name, "Name": name, "Category": "Audio Module Class", "Sub Categories": [name == "Aurora" ? "Instrument" : "Fx"]]]]
                    try JSONSerialization.data(withJSONObject: info).write(to: resources.appendingPathComponent("moduleinfo.json"))
                }
                try Data("PluginShelf demo fixture; not an executable plug-in.".utf8).write(to: bundle.appendingPathComponent("Sample.txt"))
            } catch { present(error) }
        }
    }
}

func byteString(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
