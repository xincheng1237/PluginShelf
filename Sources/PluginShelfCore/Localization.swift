import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case system, simplifiedChinese = "zh-Hans", english = "en"
    public func resolved(preferredLanguages: [String]) -> String {
        switch self {
        case .simplifiedChinese: "zh-Hans"
        case .english: "en"
        case .system: preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? "zh-Hans" : "en"
        }
    }
}

/// Keeps interpolated values separate from translation keys and permits reordering.
public struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let key: String
    let arguments: [String]
    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation: StringInterpolation) { key = stringInterpolation.key; arguments = stringInterpolation.arguments }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity) }
        public mutating func appendLiteral(_ literal: String) { key += literal }
        public mutating func appendInterpolation<T>(_ value: T) {
            key += "{\(arguments.count)}"; arguments.append(String(describing: value))
        }
    }
}
public enum L10n {
    @TaskLocal public static var overrideLanguage: AppLanguage?
    public static var language: AppLanguage { overrideLanguage ?? AppLanguage(rawValue: UserDefaults.standard.string(forKey: "app.language") ?? "system") ?? .system }
    private static let systemLanguages = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String] ?? Locale.preferredLanguages
    public static var identifier: String { language.resolved(preferredLanguages: systemLanguages) }
    public static var isEnglish: Bool { identifier == "en" }
    public static var locale: Locale { Locale(identifier: identifier) }
    public static var listSeparator: String { isEnglish ? ", " : "、" }
    public static let english: [String: String] = {
        let packaged = Bundle.main.resourceURL?.appendingPathComponent("PluginShelf_PluginShelfCore.bundle")
        let bundle = packaged.flatMap(Bundle.init(url:)) ?? Bundle.module
        guard let url = bundle.url(forResource: "English", withExtension: "json"),
              let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }()
    public static func text(_ key: String) -> String { isEnglish ? (english[key] ?? key) : key }
    static func render(_ key: String, arguments: [String]) -> String {
        let template = text(key)
        return replacing(template, arguments: arguments)
    }
    private static func replacing(_ template: String, arguments: [String]) -> String {
        // Replace in a single pass so placeholders inside user data stay literal.
        var template = template
        if isEnglish {
            let singulars = ["items": "item", "plug-ins": "plug-in", "components": "component", "records": "record", "scan notices": "scan notice", "selected plug-ins": "selected plug-in", "manageable items": "manageable item"]
            for index in arguments.indices where arguments[index] == "1" {
                for (plural, singular) in singulars {
                    template = template.replacingOccurrences(of: "{\(index)} " + plural, with: "{\(index)} " + singular)
                }
            }
        }
        let parts = template.split(separator: "{", omittingEmptySubsequences: false)
        return parts.enumerated().map { index, part in
            guard index > 0, let end = part.firstIndex(of: "}"), let number = Int(part[..<end]), arguments.indices.contains(number) else { return index == 0 ? String(part) : "{" + part }
            return arguments[number] + part[part.index(after: end)...]
        }.joined()
    }
    /// Re-localizes cached human-readable metadata, preserving user names and paths.
    public static func rendered(_ value: String) -> String {
        if let translated = english[value] { return isEnglish ? translated : value }
        if let original = english.first(where: { $0.value == value })?.key { return isEnglish ? value : original }
        for (zh, en) in english where zh.hasSuffix(" · ") {
            if value.hasPrefix(zh) { return (isEnglish ? en : zh) + value.dropFirst(zh.count) }
            if value.hasPrefix(en) { return (isEnglish ? en : zh) + value.dropFirst(en.count) }
        }
        for pattern in patterns {
            guard let match = pattern.regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { continue }
            var arguments = Array(repeating: "", count: (pattern.indices.max() ?? -1) + 1)
            for (offset, index) in pattern.indices.enumerated() {
                if let range = Range(match.range(at: offset + 1), in: value) { arguments[index] = String(value[range]) }
            }
            return replacing(isEnglish ? pattern.en : pattern.zh, arguments: arguments)
        }
        return value
    }
    private struct Pattern {
        let regex: NSRegularExpression
        let indices: [Int]
        let zh: String
        let en: String
    }
    private static let patterns: [Pattern] = {
        let placeholders = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)
        return english.flatMap { zh, en -> [Pattern] in
            [zh, en].compactMap { source in
                let matches = placeholders.matches(in: source, range: NSRange(source.startIndex..., in: source))
                guard !matches.isEmpty else { return nil }
                let text = source as NSString
                var pattern = "^"; var cursor = 0; var indices: [Int] = []
                for match in matches {
                    pattern += NSRegularExpression.escapedPattern(for: text.substring(with: NSRange(location: cursor, length: match.range.location - cursor))) + "(.+?)"
                    indices.append(Int(text.substring(with: match.range(at: 1)))!)
                    cursor = match.range.location + match.range.length
                }
                pattern += NSRegularExpression.escapedPattern(for: text.substring(from: cursor)) + "$"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
                return Pattern(regex: regex, indices: indices, zh: zh, en: en)
            }
        }
    }()
    public static func configureSystemMenus() {
        UserDefaults.standard.set([identifier], forKey: "AppleLanguages")
    }
}
public func L(_ message: LocalizedMessage) -> String { L10n.render(message.key, arguments: message.arguments) }
public extension Date {
    func appFormatted(date: Date.FormatStyle.DateStyle = .numeric, time: Date.FormatStyle.TimeStyle = .shortened) -> String {
        formatted(Date.FormatStyle(date: date, time: time).locale(L10n.locale))
    }
}
