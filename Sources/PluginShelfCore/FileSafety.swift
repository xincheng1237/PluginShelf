import Foundation
import CryptoKit

public enum FileSafety {
    public static func contained(_ candidate: URL, in root: URL) -> Bool {
        let base = root.standardizedFileURL.path
        let path = candidate.standardizedFileURL.path
        return path.hasPrefix(base + "/")
    }
    public static func safeRelative(_ path: String) throws {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0"), !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else {
            throw ShelfError.invalid("备份中包含不安全的相对路径。")
        }
    }
    public static func child(_ relative: String, of root: URL) throws -> URL {
        try safeRelative(relative)
        // resolvingSymlinksInPath may leave an unresolved parent when the final
        // component does not exist. Inspect each component before any creation.
        var cursor = root
        for part in relative.split(separator: "/") {
            cursor.appendPathComponent(String(part))
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: cursor.path)) != nil {
                throw ShelfError.invalid("目标路径包含符号链接：\(relative)")
            }
        }
        let url = root.appendingPathComponent(relative).standardizedFileURL
        guard contained(url, in: root), contained(url.resolvingSymlinksInPath(), in: root.resolvingSymlinksInPath()) else {
            throw ShelfError.invalid("路径越过了允许的目录：\(relative)")
        }
        return url
    }
    public static func relative(_ url: URL, to root: URL) throws -> String {
        guard contained(url, in: root) else { throw ShelfError.invalid("插件不在已登记的扫描目录内。") }
        let value = String(url.path.dropFirst(root.path.count + 1))
        try safeRelative(value)
        return value
    }
    public static func validatePlugin(_ plugin: Plugin, roots: [ScanRoot]) throws {
        guard plugin.canManage, let root = roots.first(where: { $0.path == plugin.root.path && !$0.protected }), PluginFormat.detect(plugin.url) == plugin.format else {
            throw ShelfError.invalid("此项目受保护或不属于已登记的插件目录。")
        }
        guard root.url.resolvingSymlinksInPath().path == root.path else { throw ShelfError.invalid("扫描目录已被替换为链接，请重新登记该目录。") }
        let relativePath = try relative(plugin.url, to: root.url)
        let destination = try child(relativePath, of: root.url)
        let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw ShelfError.invalid("符号链接插件仅供查看，请管理其真实安装位置。") }
        guard !destination.resolvingSymlinksInPath().path.hasPrefix("/System/") else { throw ShelfError.invalid("系统组件受保护。") }
    }
    public static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }
    public static func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }
    // Hash names, types, link targets, and streamed file contents. Never follow links.
    public static func digest(_ url: URL) throws -> String {
        let fm = FileManager.default
        var hash = SHA256()
        func update(_ string: String) { hash.update(data: Data((string + "\0").utf8)) }
        func visit(_ item: URL, relative: String) throws {
            let values = try item.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey])
            update(relative)
            if values.isSymbolicLink == true {
                let target = try fm.destinationOfSymbolicLink(atPath: item.path)
                guard !target.hasPrefix("/"), FileSafety.contained(item.resolvingSymlinksInPath(), in: url) else {
                    throw ShelfError.invalid("插件包含指向外部的链接，无法完整备份：\(relative)")
                }
                update("link"); update(target)
            } else if values.isDirectory == true {
                update("directory")
                for child in try fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    try visit(child, relative: relative + "/" + child.lastPathComponent)
                }
            } else if values.isRegularFile == true {
                update("file")
                update(String(values.fileSize ?? 0))
                let handle = try FileHandle(forReadingFrom: item)
                defer { try? handle.close() }
                while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
            } else { throw ShelfError.invalid("不支持的文件类型：\(item.lastPathComponent)") }
        }
        try visit(url, relative: "payload")
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func size(_ url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true { return Int64(values.fileSize ?? 0) }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            if let values = try? item.resourceValues(forKeys: keys), values.isRegularFile == true, values.isSymbolicLink != true { total += Int64(values.fileSize ?? 0) }
        }
        return total
    }
}
