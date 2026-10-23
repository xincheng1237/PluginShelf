import Foundation
import Testing
@testable import PluginShelfCore

struct Fixture {
    let directory: URL
    let root: ScanRoot
    let engine: LibraryEngine
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PluginShelf-test-" + UUID().uuidString)
        root = ScanRoot(path: directory.appendingPathComponent("Plugins").path, title: "Test")
        engine = LibraryEngine(dataDirectory: directory.appendingPathComponent("Data"))
        try FileManager.default.createDirectory(at: root.url, withIntermediateDirectories: true)
    }
    func plugin(_ name: String = "琴 Piano", ext: String = "vst3") throws -> URL {
        let url = root.url.appendingPathComponent(name + "." + ext)
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleName": name, "CFBundleIdentifier": "com.example.instrument", "CFBundleShortVersionString": "1.2.3"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        try Data("original audio binary fixture".utf8).write(to: contents.appendingPathComponent("binary"))
        return url
    }
    func scan() -> [Plugin] { PluginScanner.scan(roots: [root]).plugins }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

@Test func recognizesIndependentFormatsWithoutEnteringBundles() throws {
    let f = try Fixture(); defer { f.cleanup() }
    for ext in ["vst3", "vst", "component", "clap", "aaxplugin", "lv2", "dpm"] { _ = try f.plugin(ext, ext: ext) }
    let nested = f.root.url.appendingPathComponent("vst3.vst3/Contents/Hidden.vst3")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let plugins = f.scan()
    #expect(plugins.count == 7)
    #expect(Set(plugins.map(\.format)).count == 7)
}

@Test func filtersCombineANDSearchORBatchInitialAndDate() throws {
    let f = try Fixture(); defer { f.cleanup() }
    _ = try f.plugin("Piano Room"); _ = try f.plugin("Tape")
    let plugin = try #require(f.scan().first(where: { $0.name == "Piano Room" }))
    var q = PluginQuery(); q.text = "piano ROOM"; q.batch = "No match\nPiano"; q.initial = "P"; q.days = 7
    #expect(q.matches(plugin))
    q.initial = "T"; #expect(!q.matches(plugin))
    q.initial = ""; q.text = "piano missing"; #expect(!q.matches(plugin))
    q.text = ""; q.batch = "Tape,No match"; #expect(!q.matches(plugin))
    q.batch = ""; #expect(!q.matches(plugin, now: Date().addingTimeInterval(10 * 86400)))
}

@Test func exportRestoreRoundTripAndNeverOverwrite() async throws {
    let f = try Fixture(); defer { f.cleanup() }
    let plugin = try f.plugin()
    let before = try FileSafety.digest(plugin)
    let backup = f.directory.appendingPathComponent("Session backup.pluginshelfbackup")
    let manifest = try await f.engine.export(f.scan(), to: backup, roots: [f.root])
    #expect(manifest.entries.count == 1)
    let conflict = try await f.engine.restoreBackup(backup, roots: [f.root])
    #expect(conflict.completed.isEmpty && conflict.failures.count == 1)
    #expect(try FileSafety.digest(plugin) == before)
    try FileManager.default.removeItem(at: plugin)
    let restored = try await f.engine.restoreBackup(backup, roots: [f.root])
    #expect(restored.completed.count == 1 && restored.failures.isEmpty)
    #expect(try FileSafety.digest(plugin) == before)
    #expect(FileManager.default.fileExists(atPath: backup.appendingPathComponent("manifest.json").path))
}

@Test func tamperedPayloadCannotBeRestored() async throws {
    let f = try Fixture(); defer { f.cleanup() }; _ = try f.plugin()
    let backup = f.directory.appendingPathComponent("Backup")
    let manifest = try await f.engine.export(f.scan(), to: backup, roots: [f.root])
    let entry = try #require(manifest.entries.first)
    try Data("tampered".utf8).write(to: backup.appendingPathComponent(entry.payloadPath + "/Contents/binary"))
    await #expect(throws: (any Error).self) { try await f.engine.inspectBackup(backup, roots: [f.root]) }
}

@Test func deletionCanBeRestoredAndExpiresAtThirtyDays() async throws {
    let f = try Fixture(); defer { f.cleanup() }
    let original = try f.plugin(); let hash = try FileSafety.digest(original)
    let now = Date(timeIntervalSince1970: 1_780_000_000)
    let deleted = try await f.engine.remove(f.scan(), roots: [f.root], retentionDays: 30, now: now)
    #expect(deleted.completed.count == 1)
    #expect(!FileManager.default.fileExists(atPath: original.path))
    let records = try await f.engine.recoveryRecords(); let record = try #require(records.first)
    #expect(record.expiresAt.timeIntervalSince(now) == 30 * 86400)
    #expect(try await f.engine.purgeExpired(now: now.addingTimeInterval(29 * 86400)).completed.isEmpty)
    let restored = try await f.engine.restoreRecovery([record.id], roots: [f.root])
    #expect(restored.completed.count == 1)
    #expect(try FileSafety.digest(original) == hash)
    #expect(try await f.engine.recoveryRecords().isEmpty)
}

@Test func expiryPermanentlyRemovesOnlyExpiredPayloads() async throws {
    let f = try Fixture(); defer { f.cleanup() }; _ = try f.plugin()
    let now = Date()
    _ = try await f.engine.remove(f.scan(), roots: [f.root], retentionDays: 30, now: now)
    let future = now.addingTimeInterval(30 * 86400 + 1)
    _ = try f.plugin("NewPlugin")
    _ = try await f.engine.remove(f.scan(), roots: [f.root], retentionDays: 30, now: future)
    let result = try await f.engine.purgeExpired(now: future)
    #expect(result.completed.count == 1)
    let remaining = try await f.engine.recoveryRecords()
    #expect(remaining.count == 1 && remaining.first?.entry.name == "NewPlugin")
}

@Test func pathTraversalAndAbsolutePathsAreRejected() throws {
    let root = URL(fileURLWithPath: "/tmp/PluginShelf")
    for value in ["../outside.vst3", "/tmp/evil", "a/../../evil", "a//b", "a/./b", ""] {
        #expect(throws: (any Error).self) { try FileSafety.child(value, of: root) }
    }
    #expect(!FileSafety.contained(URL(fileURLWithPath: "/tmp/PluginShelf-evil/test"), in: root))
}

@Test func symbolicLinkEscapeIsRejected() async throws {
    let f = try Fixture(); defer { f.cleanup() }
    let plugin = try f.plugin()
    let external = f.directory.appendingPathComponent("secret")
    try Data("must never be copied".utf8).write(to: external)
    try FileManager.default.createSymbolicLink(at: plugin.appendingPathComponent("external"), withDestinationURL: external)
    #expect(throws: (any Error).self) { try FileSafety.digest(plugin) }
    await #expect(throws: (any Error).self) { try await f.engine.export(f.scan(), to: f.directory.appendingPathComponent("Backup"), roots: [f.root]) }
    #expect(FileManager.default.fileExists(atPath: external.path))
}

@Test func internalFrameworkLinksSurviveBackupAndRestore() async throws {
    let f = try Fixture(); defer { f.cleanup() }
    let plugin = try f.plugin()
    try FileManager.default.createSymbolicLink(atPath: plugin.appendingPathComponent("Contents/Alias").path, withDestinationPath: "binary")
    let backup = f.directory.appendingPathComponent("Backup")
    _ = try await f.engine.export(f.scan(), to: backup, roots: [f.root])
    try FileManager.default.removeItem(at: plugin)
    #expect(try await f.engine.restoreBackup(backup, roots: [f.root]).completed.count == 1)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: plugin.appendingPathComponent("Contents/Alias").path) == "binary")
}

@Test func topLevelLinkAndProtectedRootsCannotBeDeleted() async throws {
    let f = try Fixture(); defer { f.cleanup() }
    let original = try f.plugin()
    let alias = f.root.url.appendingPathComponent("Alias.vst3")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
    let linked = try #require(f.scan().first(where: { $0.path == alias.path }))
    #expect(!linked.canManage)
    let result = try await f.engine.remove([linked], roots: [f.root], retentionDays: 30)
    #expect(result.completed.isEmpty && result.failures.count == 1)
    let protected = ScanRoot(path: f.root.path, title: "Protected", protected: true)
    let readOnly = PluginScanner.scan(roots: [protected]).plugins
    #expect(readOnly.allSatisfy { !$0.canManage })
    #expect(try await f.engine.remove(readOnly, roots: [protected], retentionDays: 30).completed.isEmpty)
    #expect(FileManager.default.fileExists(atPath: original.path))
}

@Test func changedOriginalDuringRecoveryIsNeverOverwritten() async throws {
    let f = try Fixture(); defer { f.cleanup() }; let original = try f.plugin()
    _ = try await f.engine.remove(f.scan(), roots: [f.root], retentionDays: 30)
    let record = try #require(try await f.engine.recoveryRecords().first)
    _ = try f.plugin(); try Data("new install".utf8).write(to: original.appendingPathComponent("Contents/binary"))
    let result = try await f.engine.restoreRecovery([record.id], roots: [f.root])
    #expect(result.completed.isEmpty && result.failures.count == 1)
    #expect(try String(contentsOf: original.appendingPathComponent("Contents/binary"), encoding: .utf8) == "new install")
    #expect(try await f.engine.recoveryRecords().count == 1)
    #expect(try await f.engine.purgeExpired(now: Date().addingTimeInterval(100 * 86400)).completed.isEmpty)
}

@Test func unknownRestoreRootRejectedBeforeAnyWrite() async throws {
    let f = try Fixture(); defer { f.cleanup() }; _ = try f.plugin()
    let backup = f.directory.appendingPathComponent("Backup")
    _ = try await f.engine.export(f.scan(), to: backup, roots: [f.root])
    await #expect(throws: (any Error).self) { try await f.engine.restoreBackup(backup, roots: []) }
}

@Test func duplicateManifestDestinationRejected() async throws {
    let f = try Fixture(); defer { f.cleanup() }; _ = try f.plugin()
    let backup = f.directory.appendingPathComponent("Backup")
    let manifest = try await f.engine.export(f.scan(), to: backup, roots: [f.root])
    try FileSafety.writeJSON(BackupManifest(entries: manifest.entries + manifest.entries), to: backup.appendingPathComponent("manifest.json"))
    await #expect(throws: (any Error).self) { try await f.engine.inspectBackup(backup, roots: [f.root]) }
}

@Test func detectsAUv3WithoutAllowingExtensionRemoval() throws {
    let f = try Fixture(); defer { f.cleanup() }
    let appRoot = f.directory.appendingPathComponent("Applications")
    let extensionURL = appRoot.appendingPathComponent("Instrument.app/Contents/PlugIns/Synth.appex/Contents")
    try FileManager.default.createDirectory(at: extensionURL, withIntermediateDirectories: true)
    let plist: [String: Any] = ["CFBundleName": "Synth", "NSExtension": ["NSExtensionPointIdentifier": "com.apple.AudioUnit-UI"]]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: extensionURL.appendingPathComponent("Info.plist"))
    let report = PluginScanner.scan(roots: [], applicationRoots: [appRoot])
    #expect(report.plugins.count == 1 && report.plugins.first?.format == .auv3)
    #expect(report.plugins.first?.canManage == false)
}

@Test func interruptedMoveIsRecoverableButNeverAutomaticallyPurged() async throws {
    let f = try Fixture(); defer { f.cleanup() }; _ = try f.plugin()
    _ = try await f.engine.remove(f.scan(), roots: [f.root], retentionDays: 1)
    var record = try #require(try await f.engine.recoveryRecords().first)
    let slot = f.directory.appendingPathComponent("Data/Recovery/" + record.id.uuidString)
    record.state = .preparing
    try FileSafety.writeJSON(record, to: slot.appendingPathComponent("record.json"))
    let reconciled = try #require(try await f.engine.recoveryRecords().first)
    #expect(reconciled.state == .restoring)
    #expect(try await f.engine.purgeExpired(now: Date().addingTimeInterval(100 * 86400)).completed.isEmpty)
    #expect(try await f.engine.restoreRecovery([record.id], roots: [f.root]).completed.count == 1)
}

@Test func destinationParentSymlinkCannotEscapeRegisteredRoot() async throws {
    let f = try Fixture(); defer { f.cleanup() }
    let outside = f.directory.appendingPathComponent("Outside")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: f.root.url.appendingPathComponent("Vendor"), withDestinationURL: outside)
    #expect(throws: (any Error).self) { try FileSafety.child("Vendor/Injected.vst3", of: f.root.url) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
}

@Test func permissionFailureKeepsOriginalAndLeavesNoFalseRecoveryEntry() async throws {
    let f = try Fixture(); defer { f.cleanup() }; let original = try f.plugin()
    let hash = try FileSafety.digest(original)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: f.root.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.root.path) }
    let result = try await f.engine.remove(f.scan(), roots: [f.root], retentionDays: 30)
    #expect(result.completed.isEmpty && result.failures.count == 1)
    #expect(try FileSafety.digest(original) == hash)
    #expect(try await f.engine.recoveryRecords().isEmpty)
}

@Test func excludesScriptComponentsAndCodecsFromSystemAudioUnits() throws {
    let f = try Fixture(); defer { f.cleanup() }
    _ = try f.plugin("Script", ext: "component")
    let codecs = try f.plugin("Codecs", ext: "component")
    let effect = try f.plugin("Effect", ext: "component")
    for (url, type) in [(codecs, "adec"), (effect, "aufx")] {
        let info = url.appendingPathComponent("Contents/Info.plist")
        var data = try #require(try PropertyListSerialization.propertyList(from: Data(contentsOf: info), format: nil) as? [String: Any])
        data["AudioComponents"] = [["type": type, "name": "Test: " + url.lastPathComponent]]
        try PropertyListSerialization.data(fromPropertyList: data, format: .xml, options: 0).write(to: info)
    }
    let root = ScanRoot(path: f.root.path, title: "System", protected: true)
    let plugins = PluginScanner.scan(roots: [root]).plugins
    #expect(plugins.count == 1 && plugins.first?.name == "Effect")
    #expect(plugins.first?.canManage == false)
}

@Test func builtInApplePluginsAreNotListedEvenInCustomRoots() throws {
    let f = try Fixture(); defer { f.cleanup() }
    _ = try f.plugin("Third Party")
    let builtin = try f.plugin("Built In", ext: "component")
    let plist: [String: Any] = ["CFBundleName": "Built In", "CFBundleIdentifier": "com.apple.audio.units.Components", "AudioComponents": [["type": "aufx"]]]
    try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: builtin.appendingPathComponent("Contents/Info.plist"))
    let plugins = f.scan()
    #expect(plugins.count == 1 && plugins.first?.name == "Third Party")
    #expect(!ScanRoot.standard.contains { $0.path.hasPrefix("/System/") })
}

@Test func alphabeticalNavigationUsesLatinNamesAndPlacesOtherInitialsLast() throws {
    let f = try Fixture(); defer { f.cleanup() }
    for name in ["123", "琴", "Piano", "Écho"] { _ = try f.plugin(name) }
    let plugins = f.scan().sorted(using: KeyPathComparator(\Plugin.alphabeticalName))
    #expect(plugins.map(\.name) == ["Écho", "Piano", "琴", "123"])
    #expect(plugins.map(\.initial) == ["E", "P", "Q", "#"])
}
