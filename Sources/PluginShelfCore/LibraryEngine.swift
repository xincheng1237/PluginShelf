import Foundation

/// Serializes disk operations off the UI actor; no plug-in executable is loaded.
public actor LibraryEngine {
    public let dataDirectory: URL
    private let fm = FileManager.default
    public init(dataDirectory: URL) { self.dataDirectory = dataDirectory }
    private var vault: URL { dataDirectory.appendingPathComponent("Recovery", isDirectory: true) }
    private func prepare() throws {
        try fm.createDirectory(at: vault, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard try vault.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw ShelfError.invalid("废纸篓不能是符号链接。") }
    }
    public func scan(roots: [ScanRoot], applications: [URL]) throws -> ScanReport {
        try prepare()
        let historyURL = dataDirectory.appendingPathComponent("first-seen.json")
        let history: [String: Date]
        if fm.fileExists(atPath: historyURL.path) { history = try FileSafety.readJSON([String: Date].self, from: historyURL) } else { history = [:] }
        var report = PluginScanner.scan(roots: roots, firstSeen: history, applicationRoots: applications)
        let overrides: [String: CategoryOverride]
        do { overrides = try readCategoryOverrides() }
        catch {
            overrides = [:]
            report.warnings.append("手动分类记录无法读取，暂时显示自动识别结果；原记录未覆盖：\(error.localizedDescription)")
        }
        for index in report.plugins.indices {
            let plugin = report.plugins[index]
            if let value = overrides[plugin.path], value.bundleID == plugin.bundleID {
                report.plugins[index].categoryOverride = value.categories
            }
        }
        var updated = history
        for plugin in report.plugins { updated[plugin.path] = plugin.firstSeenAt }
        try FileSafety.writeJSON(updated, to: historyURL)
        return report
    }
    private var categoriesURL: URL { dataDirectory.appendingPathComponent("category-overrides.json") }
    private func readCategoryOverrides() throws -> [String: CategoryOverride] {
        if !fm.fileExists(atPath: categoriesURL.path) { return [:] }
        return try FileSafety.readJSON([String: CategoryOverride].self, from: categoriesURL)
    }
    public func setCategories(_ categories: [PluginCategory]?, for plugins: [Plugin]) throws {
        try prepare()
        var values = try readCategoryOverrides()
        for plugin in plugins {
            if let categories { values[plugin.path] = CategoryOverride(bundleID: plugin.bundleID, categories: categories) }
            else { values.removeValue(forKey: plugin.path) }
        }
        try FileSafety.writeJSON(values, to: categoriesURL)
    }
    public func export(_ plugins: [Plugin], to destination: URL, roots: [ScanRoot]) throws -> BackupManifest {
        guard !plugins.isEmpty else { throw ShelfError.invalid("请先选择要备份的插件。") }
        guard !fm.fileExists(atPath: destination.path) else { throw ShelfError.invalid("备份位置已存在，请使用新的名称。") }
        for plugin in plugins {
            try FileSafety.validatePlugin(plugin, roots: roots)
            guard !FileSafety.contained(destination, in: plugin.url), destination != plugin.url else { throw ShelfError.invalid("备份不能保存在插件内部。") }
        }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".PluginShelf-export-" + UUID().uuidString)
        try fm.createDirectory(at: staging.appendingPathComponent("Payloads"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        var entries: [BackupEntry] = []
        for plugin in plugins {
            let id = UUID()
            let payload = "Payloads/" + id.uuidString + "/" + plugin.url.lastPathComponent
            let target = try FileSafety.child(payload, of: staging)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let hash = try FileSafety.digest(plugin.url)
            try fm.copyItem(at: plugin.url, to: target)
            guard try FileSafety.digest(target) == hash, try FileSafety.digest(plugin.url) == hash else { throw ShelfError.invalid("\(plugin.name) 在备份期间发生变化，备份已取消。") }
            entries.append(BackupEntry(id: id, name: plugin.name, format: plugin.format, originalRoot: plugin.root.path, relativePath: try FileSafety.relative(plugin.url, to: plugin.root.url), payloadPath: payload, digest: hash, bytes: plugin.bytes))
        }
        let manifest = BackupManifest(entries: entries)
        try FileSafety.writeJSON(manifest, to: staging.appendingPathComponent("manifest.json"))
        try fm.moveItem(at: staging, to: destination)
        return manifest
    }
    public func inspectBackup(_ folder: URL, roots: [ScanRoot]) throws -> BackupManifest {
        let manifestURL = try FileSafety.child("manifest.json", of: folder)
        guard (try manifestURL.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0 < 10_000_000 else { throw ShelfError.invalid("备份清单过大。") }
        let manifest = try FileSafety.readJSON(BackupManifest.self, from: manifestURL)
        guard manifest.product == "PluginShelf", manifest.schema == 1, !manifest.entries.isEmpty, manifest.entries.count <= 10000 else { throw ShelfError.invalid("不是受支持的 PluginShelf 备份。") }
        var targets = Set<String>(); var ids = Set<UUID>()
        for entry in manifest.entries {
            let target = try restoreTarget(entry, roots: roots)
            guard targets.insert(target.path).inserted, ids.insert(entry.id).inserted else { throw ShelfError.invalid("备份清单中包含重复项目。") }
            let payload = try FileSafety.child(entry.payloadPath, of: folder)
            guard entry.payloadPath.hasPrefix("Payloads/" + entry.id.uuidString + "/"), payload.lastPathComponent == target.lastPathComponent, PluginFormat.detect(payload) == entry.format else { throw ShelfError.invalid("备份载荷与清单不匹配。") }
            guard try FileSafety.digest(payload) == entry.digest else { throw ShelfError.invalid("\(entry.name) 校验失败：备份不完整或已被修改。") }
        }
        return manifest
    }
    public func restoreBackup(_ folder: URL, roots: [ScanRoot]) throws -> OperationReport {
        let manifest = try inspectBackup(folder, roots: roots)
        var report = OperationReport()
        for entry in manifest.entries {
            do {
                let source = try FileSafety.child(entry.payloadPath, of: folder)
                try install(source: source, entry: entry, roots: roots)
                report.completed.append(entry.name)
            } catch { report.failures.append("\(entry.name)：\(error.localizedDescription)") }
        }
        return report
    }
    private func restoreTarget(_ entry: BackupEntry, roots: [ScanRoot]) throws -> URL {
        guard let root = roots.first(where: { $0.path == entry.originalRoot && !$0.protected }), entry.format != .auv3 else { throw ShelfError.invalid("原目录未登记或受保护：\(entry.originalRoot)。请先在设置中添加原插件目录。") }
        guard root.url.resolvingSymlinksInPath().path == root.path else { throw ShelfError.invalid("恢复目录已被替换为链接，请重新登记。") }
        let target = try FileSafety.child(entry.relativePath, of: root.url)
        guard PluginFormat.detect(target) == entry.format, !target.path.hasPrefix("/System/"), !target.pathComponents.dropLast().contains(where: { $0.lowercased().hasSuffix(".app") || PluginFormat.detect(URL(fileURLWithPath: $0)) != nil }) else { throw ShelfError.invalid("恢复目标不是安全的独立插件路径。") }
        return target
    }
    private func install(source: URL, entry: BackupEntry, roots: [ScanRoot]) throws {
        let target = try restoreTarget(entry, roots: roots)
        guard !fm.fileExists(atPath: target.path), (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw ShelfError.invalid("原位置已有同名插件，已跳过，未覆盖：\(target.path)") }
        guard try FileSafety.digest(source) == entry.digest else { throw ShelfError.invalid("文件校验失败。") }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Stage on the target volume, verify, then commit without overwriting an existing path.
        let staging = target.deletingLastPathComponent().appendingPathComponent(".PluginShelf-restore-" + UUID().uuidString)
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: source, to: staging)
        guard try FileSafety.digest(staging) == entry.digest else { throw ShelfError.invalid("恢复副本校验失败，原备份保留。") }
        _ = try restoreTarget(entry, roots: roots)
        try fm.moveItem(at: staging, to: target)
    }
    public func remove(_ plugins: [Plugin], roots: [ScanRoot], retentionDays: Int, now: Date = Date()) throws -> OperationReport {
        try prepare()
        var report = OperationReport()
        for plugin in plugins {
            var slot: URL?
            do {
                try FileSafety.validatePlugin(plugin, roots: roots)
                let hash = try FileSafety.digest(plugin.url)
                let id = UUID()
                let directory = vault.appendingPathComponent(id.uuidString, isDirectory: true)
                try fm.createDirectory(at: directory, withIntermediateDirectories: false)
                slot = directory
                let entry = BackupEntry(id: id, name: plugin.name, format: plugin.format, originalRoot: plugin.root.path, relativePath: try FileSafety.relative(plugin.url, to: plugin.root.url), payloadPath: plugin.url.lastPathComponent, digest: hash, bytes: plugin.bytes)
                var record = RecoveryRecord(id: id, entry: entry, days: retentionDays, now: now)
                // Persist intent before moving any source. A crash can be reconciled on the next launch.
                try save(record, directory: directory)
                try FileSafety.validatePlugin(plugin, roots: roots)
                try fm.moveItem(at: plugin.url, to: directory.appendingPathComponent(entry.payloadPath))
                guard try FileSafety.digest(directory.appendingPathComponent(entry.payloadPath)) == hash else {
                    throw ShelfError.invalid("移动期间内容发生变化，文件已保留在废纸篓，暂停自动清理。")
                }
                record.state = .active
                try save(record, directory: directory)
                report.completed.append(plugin.name)
            } catch {
                // Never remove a payload after a partial failure; leave its durable journal for recovery.
                if let slot, let contents = try? fm.contentsOfDirectory(atPath: slot.path), contents.allSatisfy({ $0 == "record.json" }) { try? fm.removeItem(at: slot) }
                report.failures.append("\(plugin.name)：\(error.localizedDescription)")
            }
        }
        return report
    }
    private func save(_ record: RecoveryRecord, directory: URL) throws { try FileSafety.writeJSON(record, to: directory.appendingPathComponent("record.json")) }
    private func validatedSlot(_ record: RecoveryRecord) throws -> URL {
        let directory = try FileSafety.child(record.id.uuidString, of: vault)
        guard record.entry.id == record.id, record.entry.payloadPath == URL(fileURLWithPath: record.entry.payloadPath).lastPathComponent else { throw ShelfError.invalid("恢复记录路径异常。") }
        try FileSafety.safeRelative(record.entry.payloadPath)
        return directory
    }
    public func recoveryRecords() throws -> [RecoveryRecord] {
        try prepare()
        var records: [RecoveryRecord] = []
        for directory in try fm.contentsOfDirectory(at: vault, includingPropertiesForKeys: nil) where UUID(uuidString: directory.lastPathComponent) != nil {
            var record = try FileSafety.readJSON(RecoveryRecord.self, from: FileSafety.child("record.json", of: directory))
            guard directory.lastPathComponent == record.id.uuidString else { throw ShelfError.invalid("废纸篓记录不一致；已停止自动清理。") }
            let slot = try validatedSlot(record)
            let payload = try FileSafety.child(record.entry.payloadPath, of: slot)
            if record.state == .preparing && fm.fileExists(atPath: payload.path) {
                // Keep this recoverable, but do not purge an interrupted operation automatically.
                record.state = .restoring
                try save(record, directory: slot)
            }
            if record.state != .restored { records.append(record) }
        }
        return records.sorted { $0.deletedAt > $1.deletedAt }
    }
    public func restoreRecovery(_ ids: Set<UUID>, roots: [ScanRoot]) throws -> OperationReport {
        var report = OperationReport()
        for var record in try recoveryRecords() where ids.contains(record.id) {
            do {
                let directory = try validatedSlot(record)
                record.state = .restoring
                try save(record, directory: directory)
                try install(source: FileSafety.child(record.entry.payloadPath, of: directory), entry: record.entry, roots: roots)
                record.state = .restored
                try save(record, directory: directory)
                // Only remove the recovery copy once the installed file has been verified.
                try fm.removeItem(at: directory)
                report.completed.append(record.entry.name)
            } catch { report.failures.append("\(record.entry.name)：\(error.localizedDescription)") }
        }
        return report
    }
    public func purgeExpired(now: Date = Date()) throws -> OperationReport {
        var report = OperationReport()
        for record in try recoveryRecords() where record.state == .active && record.expiresAt <= now {
            do {
                let directory = try validatedSlot(record)
                try fm.removeItem(at: directory)
                report.completed.append(record.entry.name)
            } catch { report.failures.append("\(record.entry.name)：\(error.localizedDescription)") }
        }
        return report
    }
}
