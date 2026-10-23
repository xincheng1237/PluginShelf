import SwiftUI
import AppKit
import PluginShelfCore

@MainActor
final class SoftwareUpdater: ObservableObject {
    enum State {
        case idle, checking, current, available(AvailableUpdate), downloading(AvailableUpdate)
        case ready(AvailableUpdate, URL), failed(String)
    }
    @Published private(set) var state: State = .idle
    @Published private(set) var lastAttempt: Date?
    @Published private(set) var showBanner = false
    @Published var automatic: Bool {
        didSet { defaults.set(automatic, forKey: "updates.automatic") }
    }
    let currentVersion: String
    private let defaults: UserDefaults
    private let client: GitHubUpdates
    private let downloader = UpdateDownloader()
    private var didCheckLaunch = false
    private var downloadTask: Task<Void, Never>?
    init(defaults: UserDefaults = .standard, client: GitHubUpdates = GitHubUpdates()) {
        self.defaults = defaults; self.client = client
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1"
        automatic = defaults.object(forKey: "updates.automatic") as? Bool ?? true
        lastAttempt = defaults.object(forKey: "updates.lastAttempt") as? Date
    }
    var isWorking: Bool {
        switch state { case .checking, .downloading: true; default: false }
    }
    var available: AvailableUpdate? {
        switch state { case .available(let update), .downloading(let update), .ready(let update, _): update; default: nil }
    }
    var statusText: String {
        switch state {
        case .idle: lastAttempt == nil ? L("尚未检查更新") : L("可手动检查更新")
        case .checking: L("正在检查更新…")
        case .current: L("已是最新版本")
        case .available(let update): L("发现新版本 \(update.version.text)")
        case .downloading: L("正在下载并校验安装包…")
        case .ready: L("更新已下载")
        case .failed: L("暂时无法检查或下载更新")
        }
    }
    func checkAtLaunch() async {
        guard !didCheckLaunch else { return }
        didCheckLaunch = true
        do { try await Task.sleep(for: .seconds(8)) } catch { return }
        await check(manual: false)
    }
    func check(manual: Bool) async {
        guard !isWorking, let installed = ReleaseVersion(currentVersion) else { return }
        let now = Date()
        if !manual && !UpdateSchedule.isDue(enabled: automatic, lastAttempt: lastAttempt, now: now) { return }
        // Persist attempts as well as successes, so offline launches remain quiet.
        lastAttempt = now; defaults.set(now, forKey: "updates.lastAttempt")
        state = .checking; showBanner = false
        do {
            if let update = try await client.latest(after: installed) {
                state = .available(update)
                let snoozedUntil = defaults.object(forKey: "updates.snoozedUntil") as? Date ?? .distantPast
                let skipped = defaults.string(forKey: "updates.skippedVersion")
                showBanner = !manual && skipped != update.version.text && now >= snoozedUntil
            } else { state = .current }
        } catch is CancellationError { state = .idle }
        catch { state = .failed(error.localizedDescription) }
    }
    func dismissBanner() {
        showBanner = false
        defaults.set(Date().addingTimeInterval(UpdateSchedule.interval), forKey: "updates.snoozedUntil")
    }
    func skip(_ update: AvailableUpdate) {
        defaults.set(update.version.text, forKey: "updates.skippedVersion")
        showBanner = false
    }
    func chooseDownload(_ update: AvailableUpdate) {
        guard !isWorking, let installer = update.installer else { return }
        let panel = NSSavePanel()
        panel.title = L("下载 PluginShelf 更新"); panel.prompt = L("下载")
        panel.nameFieldStringValue = installer.name
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            state = .failed(L("该位置已有同名文件，请使用新的文件名或选择其他位置。"))
            return
        }
        state = .downloading(update); showBanner = false
        downloadTask = Task {
            do {
                try await downloader.download(installer, to: destination)
                state = .ready(update, destination)
                NSWorkspace.shared.open(destination)
            } catch is CancellationError { state = .available(update) }
            catch let error as URLError where error.code == .cancelled { state = .available(update) }
            catch { state = .failed(error.localizedDescription) }
            downloadTask = nil
        }
    }
    func cancelDownload() { downloadTask?.cancel() }
}
