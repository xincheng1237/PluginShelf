import Foundation
import PluginShelfCore

enum LibrarySort: String, CaseIterable, Identifiable {
    case nameAscending = "名称 A–Z"
    case nameDescending = "名称 Z–A"
    case newest = "添加时间：从新到旧"
    case oldest = "添加时间：从旧到新"
    case largest = "大小：从大到小"
    case smallest = "大小：从小到大"
    var id: String { rawValue }
    var displayName: String { L10n.text(rawValue) }
    var comparators: [KeyPathComparator<Plugin>] {
        let name = KeyPathComparator(\Plugin.alphabeticalName)
        switch self {
        case .nameAscending: return [name]
        case .nameDescending: return [KeyPathComparator(\Plugin.alphabeticalName, order: .reverse)]
        case .newest: return [KeyPathComparator(\Plugin.addedAt, order: .reverse), name]
        case .oldest: return [KeyPathComparator(\Plugin.addedAt), name]
        case .largest: return [KeyPathComparator(\Plugin.bytes, order: .reverse), name]
        case .smallest: return [KeyPathComparator(\Plugin.bytes), name]
        }
    }
    static func matching(_ comparators: [KeyPathComparator<Plugin>]) -> Self? {
        guard let first = comparators.first else { return nil }
        return allCases.first { $0.comparators.first?.keyPath == first.keyPath && $0.comparators.first?.order == first.order }
    }
}
