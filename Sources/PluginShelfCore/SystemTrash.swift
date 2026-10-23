import Foundation

/// Only handles URLs owned by a deletion journal, never enumerates the Trash.
public protocol TrashHandling: Sendable {
    func bookmark(_ url: URL) throws -> Data
    func resolve(_ bookmark: Data) throws -> URL
    func moveToTrash(_ url: URL) throws -> URL
    func contains(_ url: URL) throws -> Bool
}

public struct SystemTrash: TrashHandling {
    public init() {}
    public func bookmark(_ url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    public func resolve(_ bookmark: Data) throws -> URL {
        var stale = false
        return try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                       relativeTo: nil, bookmarkDataIsStale: &stale)
    }
    public func moveToTrash(_ url: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        guard let result else { throw ShelfError.invalid(L("系统未返回废纸篓位置；删除记录已保留，请在 Finder 中检查。")) }
        return result as URL
    }
    public func contains(_ url: URL) throws -> Bool {
        var relationship: FileManager.URLRelationship = .other
        // Empty domain chooses the appropriate Trash on the item's volume.
        try FileManager.default.getRelationship(&relationship, of: .trashDirectory, in: [], toItemAt: url)
        return relationship == .contains
    }
}

public struct FileIdentity: Codable, Sendable, Equatable {
    public let device: UInt64
    public let inode: UInt64
    public init(at url: URL) throws {
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        guard values[.type] as? FileAttributeType != .typeSymbolicLink,
              let device = values[.systemNumber] as? NSNumber,
              let inode = values[.systemFileNumber] as? NSNumber else {
            throw ShelfError.invalid(L("无法确认废纸篓项目的文件身份。"))
        }
        self.device = device.uint64Value; self.inode = inode.uint64Value
    }
}

public struct TrashReference: Codable, Sendable {
    public var bookmark: Data
    public let identity: FileIdentity
    public init(bookmark: Data, identity: FileIdentity) { self.bookmark = bookmark; self.identity = identity }
}

public enum RecoveryAvailability: String, Codable, Sendable {
    case available, unavailable, outsideTrash, changed
}
