import Foundation

public enum PluginCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case effect = "效果器", instrument = "虚拟乐器", other = "其他", unknown = "未识别"
    public var id: String { rawValue }
    public var route: String { "category:" + rawValue }
    public var symbol: String {
        switch self { case .effect: "slider.horizontal.3"; case .instrument: "pianokeys"; case .other: "wrench.and.screwdriver"; case .unknown: "questionmark.folder" }
    }
    public static func normalized(_ categories: [Self]) -> [Self] {
        let result = allCases.filter { categories.contains($0) }
        return result.isEmpty ? [.unknown] : result
    }
}

public struct PluginComponent: Codable, Hashable, Sendable {
    public let identifier: String
    public let name: String
    public let categories: [PluginCategory]
    public let declaration: String
}

public enum ClassificationBasis: String, Codable, Sendable {
    case declaration, catalog, relatedFormat
}

public struct ClassificationEvidence: Codable, Hashable, Sendable {
    public let title: String
    public let detail: String
    public let referenceURL: String?
    public let pluginPath: String?
}

public struct PluginClassification: Codable, Hashable, Sendable {
    public let components: [PluginComponent]
    public let source: String
    // Optional fields keep snapshots from earlier 1.0 builds readable.
    public var basis: ClassificationBasis? = nil
    public var supplementalCategories: [PluginCategory]? = nil
    public var evidence: [ClassificationEvidence]? = nil
    public var categories: [PluginCategory] {
        PluginCategory.normalized(supplementalCategories ?? components.flatMap(\.categories))
    }
}

public struct CategoryOverride: Codable, Sendable {
    public let bundleID: String
    public let categories: [PluginCategory]
    public init(bundleID: String, categories: [PluginCategory]) {
        self.bundleID = bundleID; self.categories = PluginCategory.normalized(categories)
    }
}

/// Reads declarations only: never opens a plug-in executable or guesses from names.
public enum PluginClassifier {
    static func classify(url: URL, format: PluginFormat, info: [String: Any]) -> PluginClassification? {
        switch format {
        case .au, .auv3: return audioUnit(info)
        case .vst3: return vst3(url)
        case .lv2: return LV2Metadata.classify(url)
        default: return nil
        }
    }
    private static func audioUnit(_ info: [String: Any]) -> PluginClassification? {
        let ext = info["NSExtension"] as? [String: Any]
        let attributes = ext?["NSExtensionAttributes"] as? [String: Any]
        guard let entries = info["AudioComponents"] as? [[String: Any]] ?? attributes?["AudioComponents"] as? [[String: Any]], !entries.isEmpty else { return nil }
        let components = entries.enumerated().map { index, entry in
            let type = entry["type"] as? String ?? ""
            let category: PluginCategory
            switch type {
            case "aumu": category = .instrument
            case "aufx", "aumf", "auol": category = .effect
            case "augn", "aumi", "aumx", "aupn", "aufc", "auou": category = .other
            default: category = .unknown
            }
            let identifier = [type, entry["subtype"] as? String ?? "", entry["manufacturer"] as? String ?? "", String(index)].joined(separator: ":")
            return PluginComponent(identifier: identifier, name: entry["name"] as? String ?? "组件 \(index + 1)", categories: [category], declaration: type.isEmpty ? "未声明组件类型" : type)
        }
        return PluginClassification(components: components, source: "插件声明 · AudioComponents")
    }
    private struct ModuleInfo: Decodable {
        let classes: [ModuleClass]
        enum CodingKeys: String, CodingKey { case classes = "Classes" }
    }
    private struct ModuleClass: Decodable {
        let cid: String?
        let category: String
        let name: String?
        let subcategories: [String]?
        enum CodingKeys: String, CodingKey {
            case cid = "CID", category = "Category", name = "Name", subcategories = "Sub Categories"
        }
    }
    private static func vst3(_ url: URL) -> PluginClassification? {
        // Current SDK location first, then the SDK 3.7.5 legacy location.
        for path in ["Contents/Resources/moduleinfo.json", "Contents/moduleinfo.json"] {
            guard let data = metadata(url.appendingPathComponent(path), in: url), let module = try? json5Decoder().decode(ModuleInfo.self, from: data) else { continue }
            let components = module.classes.filter { $0.category == "Audio Module Class" }.enumerated().map { index, item in
                let tags = (item.subcategories ?? []).flatMap { $0.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) } }
                var categories: [PluginCategory] = []
                if tags.contains("Fx") { categories.append(.effect) }
                if tags.contains("Instrument") { categories.append(.instrument) }
                if categories.isEmpty, tags.contains(where: { ["Analyzer", "Generator", "Tools", "Note Effect"].contains($0) }) { categories = [.other] }
                return PluginComponent(identifier: item.cid ?? String(index), name: item.name ?? "组件 \(index + 1)", categories: PluginCategory.normalized(categories), declaration: tags.isEmpty ? "未声明子类别" : tags.joined(separator: " | "))
            }
            if !components.isEmpty { return PluginClassification(components: components, source: "插件声明 · moduleinfo.json") }
        }
        return nil
    }
    private static func json5Decoder() -> JSONDecoder { let decoder = JSONDecoder(); decoder.allowsJSON5 = true; return decoder }
    /// Bounded local metadata reads. External symlinks and URL references are never followed.
    static func metadata(_ file: URL, in root: URL) -> Data? {
        let target = file.resolvingSymlinksInPath().standardizedFileURL
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard target.path.hasPrefix(base), let size = try? target.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), size.isRegularFile == true, let bytes = size.fileSize, bytes <= 2_000_000 else { return nil }
        return try? Data(contentsOf: target, options: .mappedIfSafe)
    }
}
