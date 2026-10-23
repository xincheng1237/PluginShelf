import Foundation

public enum PluginScanner {
    public static func scan(roots: [ScanRoot], firstSeen: [String: Date] = [:], applicationRoots: [URL] = [], now: Date = Date()) -> ScanReport {
        let fm = FileManager.default
        var report = ScanReport()
        var seen = Set<String>()
        for root in roots {
            guard !root.url.resolvingSymlinksInPath().path.hasPrefix("/System/") else { continue }
            guard fm.fileExists(atPath: root.path) else { continue }
            report.checkedRoots += 1
            guard fm.isReadableFile(atPath: root.path) else { report.warnings.append("无权读取：\(root.path)"); continue }
            var enumerationErrors: [String] = []
            let enumerator = fm.enumerator(at: root.url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: { url, error in
                enumerationErrors.append("\(url.path)：\(error.localizedDescription)")
                return true
            })
            guard let enumerator else { report.warnings.append("无法扫描：\(root.path)"); continue }
            for case let url as URL in enumerator {
                if let format = PluginFormat.detect(url) {
                    enumerator.skipDescendants()
                    guard !isBuiltIn(url) else { continue }
                    if format == .au && root.protected {
                        let infoData = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
                        let info = infoData.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] }
                        let components = info?["AudioComponents"] as? [[String: Any]] ?? []
                        guard components.contains(where: { ($0["type"] as? String)?.hasPrefix("au") == true }) else { continue }
                    }
                    guard seen.insert(url.standardizedFileURL.path).inserted else { continue }
                    report.plugins.append(makePlugin(url: url, format: format, root: root, firstSeen: firstSeen, now: now))
                } else if url.pathExtension.lowercased() == "app" || url.pathExtension.lowercased() == "bundle" { enumerator.skipDescendants() }
            }
            report.warnings.append(contentsOf: enumerationErrors)
        }
        // AUv3 is owned by its containing application. Never move an extension out of an app.
        for appRoot in applicationRoots {
            guard let apps = fm.enumerator(at: appRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let app as URL in apps where app.pathExtension == "app" {
                for folder in ["Contents/PlugIns", "Contents/Extensions"] {
                    guard let extensions = try? fm.contentsOfDirectory(at: app.appendingPathComponent(folder), includingPropertiesForKeys: nil) else { continue }
                    for url in extensions where url.pathExtension == "appex" {
                        guard !isBuiltIn(url) else { continue }
                        guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")), let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], let ext = info["NSExtension"] as? [String: Any], let point = ext["NSExtensionPointIdentifier"] as? String, point.hasPrefix("com.apple.AudioUnit"), seen.insert(url.path).inserted else { continue }
                        let root = ScanRoot(path: appRoot.path, title: "应用内扩展", protected: true)
                        report.plugins.append(makePlugin(url: url, format: .auv3, root: root, firstSeen: firstSeen, now: now))
                    }
                }
            }
        }
        report.plugins = ClassificationResolver.enrich(report.plugins)
        report.plugins.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return report
    }
    private static func isBuiltIn(_ url: URL) -> Bool {
        if url.resolvingSymlinksInPath().path.hasPrefix("/System/") { return true }
        guard let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let identifier = info["CFBundleIdentifier"] as? String else { return false }
        return identifier == "com.apple" || identifier.hasPrefix("com.apple.")
    }
    static func makePlugin(url: URL, format: PluginFormat, root: ScanRoot, firstSeen: [String: Date], now: Date) -> Plugin {
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .addedToDirectoryDateKey, .isSymbolicLinkKey])
        let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist"))
        let info = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] } ?? [:]
        let bundleID = info["CFBundleIdentifier"] as? String ?? ""
        let components = info["AudioComponents"] as? [[String: Any]]
        let auName = components?.first?["name"] as? String
        let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
        let vendor: String
        if let auName, auName.contains(":") { vendor = String(auName.split(separator: ":", maxSplits: 1)[0]) }
        else { vendor = info["CFBundleGetInfoString"] as? String ?? (bundleID.split(separator: ".").dropFirst().first.map(String.init) ?? "未知厂商") }
        let restriction: String?
        if format == .auv3 { restriction = "由宿主应用管理，请使用原安装器或卸载所属应用。" }
        else if root.protected { restriction = "macOS 系统组件，仅供查看。" }
        else if values?.isSymbolicLink == true { restriction = "符号链接，仅供查看。" }
        else { restriction = nil }
        var plugin = Plugin(path: url.standardizedFileURL.path, name: name, format: format, vendor: vendor, version: info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String ?? "—", bundleID: bundleID, root: root, addedAt: values?.addedToDirectoryDate ?? values?.creationDate ?? firstSeen[url.path] ?? now, firstSeenAt: firstSeen[url.path] ?? now, bytes: FileSafety.size(url), restriction: restriction)
        plugin.classification = PluginClassifier.classify(url: url, format: format, info: info)
        return plugin
    }
}
