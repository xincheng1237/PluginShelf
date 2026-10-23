import Foundation

/// Serializes disk operations off the UI actor; no plug-in executable is loaded.
public actor LibraryEngine {
    public let dataDirectory: URL
    private let fm = FileManager.default
    private let trash: any TrashHandling
    public init(dataDirectory: URL, trash: any TrashHandling = SystemTrash()) {
        self.dataDirectory = dataDirectory; self.trash = trash
    }
    private var vault: URL { dataDirectory.appendingPathComponent("Recovery", isDirectory: true) }
    private var journals: URL { dataDirectory.appendingPathComponent("SystemTrashRecords", isDirectory: true) }
    private func prepare() throws {
        for directory in [vault, journals] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw ShelfError.invalid("废纸篓记录目录不能是符号链接。") }
        }
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
    public func remove(_ plugins: [Plugin], roots: [ScanRoot], now: Date = Date()) throws -> OperationReport {
        try prepare()
        var report = OperationReport()
        for plugin in plugins {
            var slot: URL?
            do {
                try FileSafety.validatePlugin(plugin, roots: roots)
                let hash = try FileSafety.digest(plugin.url)
                let id = UUID()
                let directory = journals.appendingPathComponent(id.uuidString, isDirectory: true)
                try fm.createDirectory(at: directory, withIntermediateDirectories: false)
                slot = directory
                let entry = BackupEntry(id: id, name: plugin.name, format: plugin.format, originalRoot: plugin.root.path,
                    relativePath: try FileSafety.relative(plugin.url, to: plugin.root.url), payloadPath: plugin.url.lastPathComponent,
                    digest: hash, bytes: plugin.bytes)
                var record = RecoveryRecord(id: id, entry: entry, now: now)
                // Persist a tracking bookmark BEFORE the move. A crash after the
                // system moves the file must not lose the only recovery reference.
                record.systemTrash = try TrashReference(bookmark: trash.bookmark(plugin.url), identity: FileIdentity(at: plugin.url))
                try save(record, directory: directory)
                try FileSafety.validatePlugin(plugin, roots: roots)
                guard try FileIdentity(at: plugin.url) == record.systemTrash?.identity,
                      try FileSafety.digest(plugin.url) == hash else { throw ShelfError.invalid("插件在操作期间发生变化，已取消。") }
                let moved = try trash.moveToTrash(plugin.url)
                record.systemTrash?.bookmark = try trash.bookmark(moved)
                try save(record, directory: directory)
                _ = try systemPayload(record)
                record.state = .active
                try save(record, directory: directory)
                report.completed.append(plugin.name)
            } catch {
                // Discard an intent only if the original is still present and
                // the slot contains metadata alone. Never discard a moved file.
                if let slot, let contents = try? fm.contentsOfDirectory(atPath: slot.path) {
                    if contents.isEmpty { try? fm.removeItem(at: slot) }
                    else if contents == ["record.json"],
                            let intent = try? FileSafety.readJSON(RecoveryRecord.self, from: slot.appendingPathComponent("record.json")),
                            let identity = try? FileIdentity(at: plugin.url), identity == intent.systemTrash?.identity {
                        try? fm.removeItem(at: slot)
                    }
                }
                report.failures.append("\(plugin.name)：\(error.localizedDescription)")
            }
        }
        return report
    }
    private func save(_ record: RecoveryRecord, directory: URL) throws {
        var durable = record; durable.availability = nil
        try FileSafety.writeJSON(durable, to: directory.appendingPathComponent("record.json"))
    }
    private func validatedSlot(_ record: RecoveryRecord) throws -> URL {
        let directory = try FileSafety.child(record.id.uuidString, of: record.systemTrash == nil ? vault : journals)
        guard record.entry.id == record.id, record.entry.payloadPath == URL(fileURLWithPath: record.entry.payloadPath).lastPathComponent else { throw ShelfError.invalid("恢复记录路径异常。") }
        try FileSafety.safeRelative(record.entry.payloadPath)
        return directory
    }
    private func systemPayload(_ record: RecoveryRecord) throws -> URL {
        guard let reference = record.systemTrash else { throw ShelfError.invalid("缺少系统废纸篓记录。") }
        let url = try trash.resolve(reference.bookmark)
        guard try trash.contains(url) else { throw ShelfError.invalid("该文件已移出系统废纸篓，未对其执行操作。") }
        guard try FileIdentity(at: url) == reference.identity,
              try FileSafety.digest(url) == record.entry.digest else { throw ShelfError.invalid("废纸篓文件已变化，未对其执行操作。") }
        return url
    }
    private func payload(_ record: RecoveryRecord) throws -> URL {
        if record.systemTrash != nil { return try systemPayload(record) }
        let url = try FileSafety.child(record.entry.payloadPath, of: validatedSlot(record))
        guard try FileSafety.digest(url) == record.entry.digest else { throw ShelfError.invalid("旧版废纸篓文件校验失败。") }
        return url
    }
    public func recoveryRecords() throws -> [RecoveryRecord] {
        try prepare()
        var records: [RecoveryRecord] = []
        let directories = try fm.contentsOfDirectory(at: vault, includingPropertiesForKeys: nil) + fm.contentsOfDirectory(at: journals, includingPropertiesForKeys: nil)
        for directory in directories where UUID(uuidString: directory.lastPathComponent) != nil {
            var record = try FileSafety.readJSON(RecoveryRecord.self, from: FileSafety.child("record.json", of: directory))
            guard directory.lastPathComponent == record.id.uuidString else { throw ShelfError.invalid("废纸篓记录不一致。") }
            guard try validatedSlot(record).standardizedFileURL == directory.standardizedFileURL else {
                throw ShelfError.invalid("删除记录的存储位置不一致。")
            }
            if record.state == .restored { continue }
            record.availability = .unavailable
            if let reference = record.systemTrash {
                do {
                    let url = try trash.resolve(reference.bookmark)
                    if try !trash.contains(url) { record.availability = .outsideTrash }
                    else if try FileIdentity(at: url) != reference.identity { record.availability = .changed }
                    else {
                        record.availability = .available
                        // Refresh tracking data while the volume is reachable.
                        record.systemTrash?.bookmark = try trash.bookmark(url)
                        try save(record, directory: directory)
                    }
                } catch { /* Keep the record for disconnected disks and missing files. */ }
            } else if let url = try? FileSafety.child(record.entry.payloadPath, of: directory), fm.fileExists(atPath: url.path) {
                record.availability = .available
                if record.state == .preparing { record.state = .restoring; try save(record, directory: directory) }
            }
            records.append(record)
        }
        return records.sorted { $0.deletedAt > $1.deletedAt }
    }
    public func restoreRecovery(_ ids: Set<UUID>, roots: [ScanRoot]) throws -> OperationReport {
        var report = OperationReport()
        for var record in try recoveryRecords() where ids.contains(record.id) {
            do {
                let directory = try validatedSlot(record)
                let source = try payload(record)
                if record.state == .restoredPendingCleanup {
                    let target = try restoreTarget(record.entry, roots: roots)
                    guard try FileSafety.digest(target) == record.entry.digest else { throw ShelfError.invalid("已还原的文件发生变化，废纸篓副本保留。") }
                } else {
                    record.state = .restoring; try save(record, directory: directory)
                    try install(source: source, entry: record.entry, roots: roots)
                    record.state = .restoredPendingCleanup; try save(record, directory: directory)
                }
                // Recheck the tracked file after copying. Never delete a file the
                // user has already taken out of Trash or replaced there.
                if record.systemTrash != nil { try fm.removeItem(at: systemPayload(record)) }
                record.state = .restored; try save(record, directory: directory)
                try fm.removeItem(at: directory)
                report.completed.append(record.entry.name)
            } catch { report.failures.append("\(record.entry.name)：\(error.localizedDescription)") }
        }
        return report
    }
    /// Called only after explicit UI confirmation. Never empties the whole Trash.
    public func permanentlyDelete(_ ids: Set<UUID>) throws -> OperationReport {
        var report = OperationReport()
        for record in try recoveryRecords() where ids.contains(record.id) {
            do {
                let directory = try validatedSlot(record)
                let source = try payload(record)
                try fm.removeItem(at: source)
                try fm.removeItem(at: directory)
                report.completed.append(record.entry.name)
            } catch { report.failures.append("\(record.entry.name)：\(error.localizedDescription)") }
        }
        return report
    }
    /// Removes metadata only; unavailable files are never searched for or deleted.
    public func forgetUnavailable(_ ids: Set<UUID>) throws -> OperationReport {
        var report = OperationReport()
        for record in try recoveryRecords() where ids.contains(record.id) {
            do {
                guard record.systemTrash != nil, !record.canRecover else { throw ShelfError.invalid("仍可还原的项目不能只移除记录。") }
                let directory = try validatedSlot(record)
                let contents = try fm.contentsOfDirectory(atPath: directory.path)
                guard contents.allSatisfy({ $0 == "record.json" }) else { throw ShelfError.invalid("记录目录内还有文件，已保留。") }
                try fm.removeItem(at: directory)
                report.completed.append(record.entry.name)
            } catch { report.failures.append("\(record.entry.name)：\(error.localizedDescription)") }
        }
        return report
    }
}
