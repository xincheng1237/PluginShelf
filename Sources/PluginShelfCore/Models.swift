import Foundation

public enum PluginFormat: String, Codable, CaseIterable, Sendable, Identifiable {
    case au = "AU", vst3 = "VST3", vst2 = "VST2", aax = "AAX", clap = "CLAP", lv2 = "LV2", rtas = "RTAS", auv3 = "AUv3"
    public var id: String { rawValue }
    public static func detect(_ url: URL) -> Self? {
        switch url.pathExtension.lowercased() {
        case "component": .au
        case "vst3": .vst3
        case "vst": .vst2
        case "aaxplugin": .aax
        case "clap": .clap
        case "lv2": .lv2
        case "dpm": .rtas
        default: nil
        }
    }
}

public struct ScanRoot: Codable, Hashable, Sendable, Identifiable {
    public let path: String
    public let title: String
    public let protected: Bool
    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }
    public init(path: String, title: String, protected: Bool = false) {
        self.path = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        self.title = title
        self.protected = protected
    }
    public static var standard: [Self] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var roots: [Self] = []
        for (prefix, title) in [("/Library", "本机共享"), (home + "/Library", "当前用户"), ("/Network/Library", "网络资源库")] {
            for folder in ["Components", "VST3", "VST", "CLAP", "LV2"] {
                roots.append(Self(path: prefix + "/Audio/Plug-Ins/" + folder, title: title))
            }
            roots.append(Self(path: prefix + "/Application Support/Avid/Audio/Plug-Ins", title: title))
            roots.append(Self(path: prefix + "/Application Support/Avid/Audio/Plug-Ins (Unused)", title: title + " · 停用"))
            roots.append(Self(path: prefix + "/Application Support/Digidesign/Plug-Ins", title: title))
        }
        roots.append(Self(path: home + "/.lv2", title: "当前用户"))
        return roots
    }
}

public struct Plugin: Codable, Hashable, Identifiable, Sendable {
    public let path: String
    public let name: String
    public let format: PluginFormat
    public let vendor: String
    public let version: String
    public let bundleID: String
    public let root: ScanRoot
    public let addedAt: Date
    public let firstSeenAt: Date
    public let bytes: Int64
    public let restriction: String?
    public var classification: PluginClassification? = nil
    public var categoryOverride: [PluginCategory]? = nil
    public var categories: [PluginCategory] { categoryOverride ?? classification?.categories ?? [.unknown] }
    public var categoryText: String { categories.map(\.rawValue).joined(separator: "、") }
    public var classificationSource: String { categoryOverride == nil ? (classification?.source ?? "暂无可靠的分类依据") : "手动设置" }
    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }
    public var canManage: Bool { restriction == nil }
    public var alphabeticalName: String {
        let latin = name.applyingTransform(.toLatin, reverse: false) ?? name
        let normalized = latin.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let first = String(normalized.prefix(1)).uppercased()
        // Numeric group prefixes keep non-letter initials after A–Z even with
        // Foundation's localized string comparator, which ignores punctuation.
        return (first.range(of: "^[A-Z]$", options: .regularExpression) == nil ? "1" : "0") + normalized
    }
    public var initial: String {
        let key = alphabeticalName
        return key.first == "1" ? "#" : String(key.dropFirst().prefix(1)).uppercased()
    }
}

public struct ScanReport: Sendable {
    public var plugins: [Plugin] = []
    public var warnings: [String] = []
    public var checkedRoots = 0
    public init() {}
}

public struct BackupEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let format: PluginFormat
    public let originalRoot: String
    public let relativePath: String
    public let payloadPath: String
    public let digest: String
    public let bytes: Int64
    public init(id: UUID, name: String, format: PluginFormat, originalRoot: String, relativePath: String, payloadPath: String, digest: String, bytes: Int64) {
        self.id = id; self.name = name; self.format = format; self.originalRoot = originalRoot
        self.relativePath = relativePath; self.payloadPath = payloadPath; self.digest = digest; self.bytes = bytes
    }
}

public struct BackupManifest: Codable, Sendable {
    public let product: String
    public let schema: Int
    public let createdAt: Date
    public let entries: [BackupEntry]
    public init(entries: [BackupEntry]) {
        product = "PluginShelf"; schema = 1; createdAt = Date(); self.entries = entries
    }
}

public enum RecoveryState: String, Codable, Sendable { case preparing, active, restoring, restoredPendingCleanup, restored }
public struct RecoveryRecord: Codable, Sendable, Identifiable {
    public let id: UUID
    public let entry: BackupEntry
    public let deletedAt: Date
    public let expiresAt: Date?
    public var state: RecoveryState
    // nil means a 1.0 private-vault record. Optional fields keep its JSON readable.
    public var systemTrash: TrashReference? = nil
    public var availability: RecoveryAvailability? = nil
    public var canRecover: Bool { availability == .available || availability == nil }
    public var locationText: String { systemTrash == nil ? "旧版废纸篓" : "系统废纸篓" }
    public var statusText: String {
        switch availability {
        case .unavailable: return "已清除或不可访问"
        case .outsideTrash: return "已移出废纸篓"
        case .changed: return "文件已变化 · 需检查"
        default: return state == .restoredPendingCleanup ? "已还原 · 待清理副本" : "可还原"
        }
    }
    public init(id: UUID, entry: BackupEntry, days: Int? = nil, now: Date = Date()) {
        self.id = id; self.entry = entry; deletedAt = now
        expiresAt = days.map { now.addingTimeInterval(Double(max(1, min($0, 365))) * 86400) }
        state = .preparing
    }
}

public struct OperationReport: Sendable {
    public var completed: [String] = []
    public var failures: [String] = []
    public init() {}
    public var summary: String {
        "完成 \(completed.count) 项" + (failures.isEmpty ? "" : "，\(failures.count) 项未完成")
    }
}

public enum ShelfError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { switch self { case .invalid(let text): text } }
}

public struct PluginQuery: Sendable {
    public var text = ""
    public var batch = ""
    public var initial = ""
    public var days = 0
    public var format: PluginFormat?
    public var category: PluginCategory?
    public init() {}
    public func matches(_ plugin: Plugin, now: Date = Date()) -> Bool {
        if let format, plugin.format != format { return false }
        if let category, !plugin.categories.contains(category) { return false }
        if !initial.isEmpty && plugin.initial != initial { return false }
        if days > 0 && plugin.addedAt < now.addingTimeInterval(-Double(days) * 86400) { return false }
        let haystack = [plugin.name, plugin.vendor, plugin.bundleID, plugin.path, plugin.format.rawValue].joined(separator: " ")
        let contains: (String) -> Bool = { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        if !words.allSatisfy(contains) { return false }
        let terms = batch.components(separatedBy: CharacterSet(charactersIn: "\n,，;；")).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return terms.isEmpty || terms.contains(where: contains)
    }
}
