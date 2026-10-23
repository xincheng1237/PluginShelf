import Foundation

/// A second pass over the complete scan; never loads code, follows names alone,
/// or uses a manually assigned / inferred category as a donor.
enum ClassificationResolver {
    private struct Identity: Hashable {
        let product: String
        let name: String
        let version: [Int]
    }

    private static func identity(_ plugin: Plugin) -> Identity? {
        guard !plugin.bundleID.isEmpty, let version = ClassificationCatalog.version(plugin.version) else { return nil }
        if let product = ClassificationCatalog.product(for: plugin) {
            return Identity(product: "catalog:" + product.key, name: "", version: version)
        }
        let name = ClassificationCatalog.productName(plugin.name)
        guard !name.isEmpty else { return nil }
        return Identity(product: "bundle:" + plugin.bundleID, name: name, version: version)
    }

    private static func isDonor(_ plugin: Plugin) -> Bool {
        guard [.au, .auv3, .vst3].contains(plugin.format), plugin.categoryOverride == nil,
              let classification = plugin.classification,
              classification.basis == nil || classification.basis == .declaration,
              classification.supplementalCategories == nil,
              classification.components.count == 1,
              classification.categories.count == 1, classification.categories != [.unknown] else { return false }
        return true
    }

    private static func evidence(for plugin: Plugin) -> ClassificationEvidence {
        ClassificationEvidence(title: L("关联 \(plugin.format.rawValue) · \(plugin.name)"),
            detail: L("同产品、同版本 \(plugin.version)；依据：\(plugin.classificationSource)"),
            referenceURL: nil, pluginPath: plugin.path)
    }

    static func enrich(_ plugins: [Plugin]) -> [Plugin] {
        var donors: [Identity: [Plugin]] = [:]
        for plugin in plugins where isDonor(plugin) {
            if let key = identity(plugin) { donors[key, default: []].append(plugin) }
        }
        return plugins.map { original in
            guard original.categoryOverride == nil,
                  original.classification == nil || original.classification?.categories == [.unknown] else { return original }
            let product = ClassificationCatalog.product(for: original)
            let candidates = identity(original).flatMap { donors[$0] }?.filter {
                $0.id != original.id && $0.format != original.format
            }.sorted { $0.path < $1.path } ?? []
            var result = original
            if !candidates.isEmpty {
                let categories = Set(candidates.compactMap { $0.classification?.categories.first })
                let catalogConflicts = product.map { Set($0.categories) != categories } ?? false
                if categories.count != 1 || catalogConflicts {
                    result.classification = PluginClassification(components: original.classification?.components ?? [],
                        source: L("分类依据冲突 · 待确认"), basis: .relatedFormat, supplementalCategories: [.unknown],
                        evidence: candidates.map(evidence) + (product.map { [$0.evidence] } ?? []))
                } else {
                    let formats = PluginFormat.allCases.filter { format in candidates.contains { $0.format == format } }
                    result.classification = PluginClassification(components: original.classification?.components ?? [],
                        source: L("关联其他格式 · ") + formats.map(\.rawValue).joined(separator: "、"),
                        basis: .relatedFormat, supplementalCategories: PluginCategory.normalized(Array(categories)),
                        evidence: candidates.map(evidence))
                }
            } else if let product {
                result.classification = PluginClassification(components: original.classification?.components ?? [],
                    source: L("已核实资料 · ") + product.names[0], basis: .catalog,
                    supplementalCategories: product.categories, evidence: [product.evidence])
            }
            return result
        }
    }
}
