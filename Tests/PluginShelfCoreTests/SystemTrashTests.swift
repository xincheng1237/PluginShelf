import Foundation
import Testing
@testable import PluginShelfCore

/// A local-volume stand-in; unit tests never touch the user's actual Trash.
struct FixtureTrash: TrashHandling {
    let directory: URL
    private struct Reference: Codable { let path: String; let identity: FileIdentity }
    func bookmark(_ url: URL) throws -> Data {
        try JSONEncoder().encode(Reference(path: url.path, identity: FileIdentity(at: url)))
    }
    func resolve(_ bookmark: Data) throws -> URL {
        let reference = try JSONDecoder().decode(Reference.self, from: bookmark)
        let original = URL(fileURLWithPath: reference.path)
        if (try? FileIdentity(at: original)) == reference.identity { return original }
        for candidate in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            if (try? FileIdentity(at: candidate)) == reference.identity { return candidate }
        }
        throw CocoaError(.fileNoSuchFile)
    }
    func moveToTrash(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }
    func contains(_ url: URL) throws -> Bool {
        FileSafety.contained(url.resolvingSymlinksInPath(), in: directory.resolvingSymlinksInPath())
    }
}

private func storedRecord(_ f: Fixture, _ record: RecoveryRecord) -> URL {
    f.directory.appendingPathComponent("Data/" + (record.systemTrash == nil ? "Recovery/" : "SystemTrashRecords/") + record.id.uuidString + "/record.json")
}
private func payload(_ f: Fixture, _ record: RecoveryRecord) throws -> URL {
    try FixtureTrash(directory: f.directory.appendingPathComponent("SystemTrash")).resolve(#require(record.systemTrash).bookmark)
}

@Test func permanentDeletionTouchesOnlySelectedTrackedPayload() async throws {
    let f = try Fixture(); defer { f.cleanup() }
    _ = try f.plugin("First"); _ = try f.plugin("Second")
    _ = try await f.engine.remove(f.scan(), roots: [f.root])
    let records = try await f.engine.recoveryRecords()
    let first = try #require(records.first), other = try #require(records.last)
    let firstURL = try payload(f, first), otherURL = try payload(f, other)
    let result = try await f.engine.permanentlyDelete([first.id])
    #expect(result.completed.count == 1 && result.failures.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: firstURL.path))
    #expect(FileManager.default.fileExists(atPath: otherURL.path))
}

@Test func filesTakenOutOfTrashAreNeverDeletedOrRestoredByTheApp() async throws {
    let f = try Fixture(); defer { f.cleanup() }; _ = try f.plugin()
    _ = try await f.engine.remove(f.scan(), roots: [f.root])
    let record = try #require(try await f.engine.recoveryRecords().first)
    let url = try payload(f, record)
    let outside = f.directory.appendingPathComponent("Kept.vst3")
    try FileManager.default.moveItem(at: url, to: outside)
    // Persist the externally moved file's bookmark to simulate system tracking.
    var movedRecord = record
    movedRecord.systemTrash?.bookmark = try FixtureTrash(directory: f.directory.appendingPathComponent("SystemTrash")).bookmark(outside)
    try FileSafety.writeJSON(movedRecord, to: storedRecord(f, record))
    #expect(try await f.engine.recoveryRecords().first?.availability == .outsideTrash)
    #expect(try await f.engine.permanentlyDelete([record.id]).completed.isEmpty)
    #expect(try await f.engine.restoreRecovery([record.id], roots: [f.root]).completed.isEmpty)
    #expect(FileManager.default.fileExists(atPath: outside.path))
}

@Test func clearedTrashRemainsVisibleAsUnavailableHistory() async throws {
    let f = try Fixture(); defer { f.cleanup() }; _ = try f.plugin()
    _ = try await f.engine.remove(f.scan(), roots: [f.root])
    let record = try #require(try await f.engine.recoveryRecords().first)
    try FileManager.default.removeItem(at: payload(f, record))
    let history = try #require(try await f.engine.recoveryRecords().first)
    #expect(history.availability == .unavailable && !history.canRecover)
    #expect(try await f.engine.restoreRecovery([record.id], roots: [f.root]).completed.isEmpty)
    #expect(try await f.engine.forgetUnavailable([record.id]).completed.count == 1)
    #expect(try await f.engine.recoveryRecords().isEmpty)
}

@Test func tamperedTrashPayloadAndReplacementAreProtected() async throws {
    let f = try Fixture(); defer { f.cleanup() }; _ = try f.plugin()
    _ = try await f.engine.remove(f.scan(), roots: [f.root])
    let record = try #require(try await f.engine.recoveryRecords().first)
    let url = try payload(f, record)
    try Data("changed".utf8).write(to: url.appendingPathComponent("Contents/binary"))
    #expect(try await f.engine.permanentlyDelete([record.id]).completed.isEmpty)
    #expect(try await f.engine.restoreRecovery([record.id], roots: [f.root]).completed.isEmpty)
    #expect(try await f.engine.forgetUnavailable([record.id]).completed.isEmpty)
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Test func legacyVaultRecordsRemainRecoverableWithoutExpiryCleanup() async throws {
    let f = try Fixture(); defer { f.cleanup() }; let original = try f.plugin()
    let id = UUID()
    let entry = BackupEntry(id: id, name: "Legacy", format: .vst3, originalRoot: f.root.path,
        relativePath: original.lastPathComponent, payloadPath: original.lastPathComponent,
        digest: try FileSafety.digest(original), bytes: FileSafety.size(original))
    var record = RecoveryRecord(id: id, entry: entry, days: 1, now: Date(timeIntervalSince1970: 0))
    record.state = .active
    let directory = storedRecord(f, record).deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: original, to: directory.appendingPathComponent(entry.payloadPath))
    // Serialize in the original 1.0 shape, with none of the new fields.
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    var json = try #require(JSONSerialization.jsonObject(with: encoder.encode(record)) as? [String: Any])
    json.removeValue(forKey: "systemTrash"); json.removeValue(forKey: "availability")
    try JSONSerialization.data(withJSONObject: json).write(to: storedRecord(f, record))
    let loaded = try #require(try await f.engine.recoveryRecords().first)
    #expect(loaded.systemTrash == nil && loaded.canRecover)
    #expect(try await f.engine.restoreRecovery([id], roots: [f.root]).completed.count == 1)
    #expect(FileManager.default.fileExists(atPath: original.path))
}

@Test func invalidJournalAndSymlinkedRecordCannotTargetOtherFiles() async throws {
    let f = try Fixture(); defer { f.cleanup() }; _ = try f.plugin()
    _ = try await f.engine.remove(f.scan(), roots: [f.root])
    let record = try #require(try await f.engine.recoveryRecords().first)
    let journal = storedRecord(f, record)
    let external = f.directory.appendingPathComponent("Private.json")
    try FileManager.default.moveItem(at: journal, to: external)
    try FileManager.default.createSymbolicLink(at: journal, withDestinationURL: external)
    await #expect(throws: (any Error).self) { try await f.engine.permanentlyDelete([record.id]) }
    #expect(FileManager.default.fileExists(atPath: external.path))
}

@Test func intentBookmarkRecoversCrashBetweenSystemMoveAndJournalUpdate() async throws {
    let f = try Fixture(); defer { f.cleanup() }; let original = try f.plugin()
    let before = try FixtureTrash(directory: f.directory.appendingPathComponent("SystemTrash")).bookmark(original)
    _ = try await f.engine.remove(f.scan(), roots: [f.root])
    var record = try #require(try await f.engine.recoveryRecords().first)
    record.state = .preparing; record.systemTrash?.bookmark = before
    try FileSafety.writeJSON(record, to: storedRecord(f, record))
    let restarted = LibraryEngine(dataDirectory: f.directory.appendingPathComponent("Data"), trash: FixtureTrash(directory: f.directory.appendingPathComponent("SystemTrash")))
    #expect(try await restarted.recoveryRecords().first?.canRecover == true)
    #expect(try await restarted.restoreRecovery([record.id], roots: [f.root]).completed.count == 1)
}

@Test func mismatchedIdentityCannotDeleteAnotherTrashItem() async throws {
    let f = try Fixture(); defer { f.cleanup() }
    _ = try f.plugin("One"); _ = try f.plugin("Two")
    _ = try await f.engine.remove(f.scan(), roots: [f.root])
    let records = try await f.engine.recoveryRecords()
    var first = try #require(records.first)
    let second = try #require(records.last)
    let secondURL = try payload(f, second)
    first.systemTrash?.bookmark = try #require(second.systemTrash).bookmark
    try FileSafety.writeJSON(first, to: storedRecord(f, first))
    #expect(try await f.engine.permanentlyDelete([first.id]).completed.isEmpty)
    #expect(FileManager.default.fileExists(atPath: secondURL.path))
}

@Test func restoredCopyCleanupCanResumeWithoutOverwritingOriginal() async throws {
    let f = try Fixture(); defer { f.cleanup() }; let original = try f.plugin()
    _ = try await f.engine.remove(f.scan(), roots: [f.root])
    var record = try #require(try await f.engine.recoveryRecords().first)
    try FileManager.default.copyItem(at: payload(f, record), to: original)
    record.state = .restoredPendingCleanup
    try FileSafety.writeJSON(record, to: storedRecord(f, record))
    let identity = try FileIdentity(at: original)
    #expect(try await f.engine.restoreRecovery([record.id], roots: [f.root]).completed.count == 1)
    #expect(try FileIdentity(at: original) == identity)
    #expect(try await f.engine.recoveryRecords().isEmpty)
}
