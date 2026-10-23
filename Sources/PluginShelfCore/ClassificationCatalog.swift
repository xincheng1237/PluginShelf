import Foundation

/// Curated product identities, not filename keywords or a list of vendor prefixes.
/// Identity observations and the category mapping are documented in
/// docs/CLASSIFICATION_CATALOG.md. Changes ship with the application, offline.
struct CatalogProduct: Sendable {
    let key: String
    let names: [String]
    let identifiers: [PluginFormat: Set<String>]
    let majorVersions: Set<Int>
    let categories: [PluginCategory]
    let referenceURL: String
    let detail: String

    func matches(_ plugin: Plugin) -> Bool {
        guard identifiers[plugin.format]?.contains(plugin.bundleID) == true,
              names.contains(where: { ClassificationCatalog.productName($0) == ClassificationCatalog.productName(plugin.name) }),
              let major = ClassificationCatalog.version(plugin.version)?.first else { return false }
        return majorVersions.contains(major)
    }

    var evidence: ClassificationEvidence {
        ClassificationEvidence(title: L("已核实资料 · \(names[0])"),
            detail: L10n.rendered(detail) + L("（资料库 2026.10.21；适用主版本：\(majorVersions.sorted().map(String.init).joined(separator: L10n.listSeparator))）"),
            referenceURL: referenceURL, pluginPath: nil)
    }
}

enum ClassificationCatalog {
    static let revision = "2026.10.21"
    static let avidGuide = "https://resources.avid.com/SupportFiles/PT/Audio_Plug-Ins_Guide_2018.1.pdf"
    static let avidMIDI = "https://www.avid.com/resource-center/midi-plugins"

    private static func avid(_ name: String, _ category: PluginCategory = .effect,
                             identifier: String? = nil, detail: String = L("Avid 官方文档中的音频处理插件。"),
                             reference: String = avidGuide) -> CatalogProduct {
        CatalogProduct(key: "avid:" + name, names: [name],
            identifiers: [.aax: [identifier ?? "com.AVID.plugin." + name]], majorVersions: [25],
            categories: [category], referenceURL: reference, detail: detail)
    }

    static let products: [CatalogProduct] = [
        avid("AutoPan"), avid("BF-76"), avid("ChannelStrip"), avid("DVerb"),
        avid("Dither"), avid("DownMixer"), avid("DynamicsIII"), avid("EQIII"),
        avid("Eleven Lite"), avid("LoFi"), avid("Maxim"), avid("ModDelay_III"),
        avid("Normalize-Gain"), avid("Pitch Shift Legacy"), avid("PitchII"),
        avid("RectiFi"), avid("Reverse-DC Removal"), avid("SansAmp PSA-1"),
        avid("SciFi"), avid("Time Shift"), avid("TimeAdjuster"), avid("Trim"), avid("VariFi"),
        avid("Invert-Duplicate", identifier: "com.digidesign.plugin.Invert-Duplicate",
             detail: L("包含反相与复制音频的处理工具；按文件包整体归类。")),
        avid("ClickII", .instrument, detail: L("节拍器声音发生器；Avid 指南列于 Instrument Plug-Ins。")),
        avid("InTune", .other, detail: L("调音工具；Avid 指南列于 Other Plug-Ins。")),
        avid("MasterMeter", .other, detail: L("音频电平分析工具；Avid 指南列于 Other Plug-Ins。")),
        avid("SignalGenerator", .other, detail: L("测试信号发生器；Avid 指南列于 Other Plug-Ins。")),
        avid("NoteStack", detail: L("MIDI 音符处理效果器，不属于虚拟乐器。"), reference: avidMIDI),
        avid("PitchControl", detail: L("MIDI 音高处理效果器，不属于虚拟乐器。"), reference: avidMIDI),
        avid("VelocityControl", detail: L("MIDI 力度处理效果器，不属于虚拟乐器。"), reference: avidMIDI),
        CatalogProduct(key: "celemony:melodyne", names: ["Melodyne"],
            identifiers: [.au: ["com.celemony.melodyne.au"], .vst3: ["com.celemony.melodyne.vst3"], .aax: ["com.celemony.melodyne.aax"]],
            majorVersions: [5], categories: [.effect],
            referenceURL: "https://www.celemony.com/en/melodyne/what-is-melodyne",
            detail: L("Celemony 官方资料：对录制音频的音高、时间与音色进行编辑。")),
        CatalogProduct(key: "tokyodawn:nova", names: ["TDR Nova"],
            identifiers: [.au: ["com.TokyoDawnLabs.TDRNova"], .vst3: ["com.TokyoDawnLabs.TDRNova"],
                          .vst2: ["com.TokyoDawnLabs.TDRNova"], .aax: ["com.TokyoDawnLabs.TDRNova"]],
            majorVersions: [2], categories: [.effect],
            referenceURL: "https://docs.tokyodawn.net/nova-manual/",
            detail: L("Tokyo Dawn Labs 官方资料：动态均衡与压缩处理器。"))
    ]

    static func product(for plugin: Plugin) -> CatalogProduct? {
        products.first { $0.matches(plugin) }
    }

    static func productName(_ name: String) -> String {
        // Preserve punctuation and edition names; only normalize case/spacing.
        name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func version(_ value: String) -> [Int]? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix(" Release") { text.removeLast(" Release".count) }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 5 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        // Semantically equivalent display versions, e.g. 2.2 and 2.2.0.
        while numbers.count > 1, numbers.last == 0 { numbers.removeLast() }
        return numbers
    }
}
