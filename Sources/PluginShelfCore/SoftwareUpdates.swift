import Foundation
import CryptoKit

public struct ReleaseVersion: Comparable, Sendable, Equatable {
    public let text: String
    private let numbers: [Int]
    public init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              parts.allSatisfy({ Int($0) != nil }) else { return nil }
        self.text = value
        self.numbers = parts.map { Int($0)! } + Array(repeating: 0, count: 3 - parts.count)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.numbers == rhs.numbers }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.numbers.lexicographicallyPrecedes(rhs.numbers) }
}

public struct UpdateInstaller: Sendable {
    public let name: String
    public let url: URL
    public let bytes: Int64
    public let sha256: String
}
public struct AvailableUpdate: Sendable {
    public let version: ReleaseVersion
    public let page: URL
    public let notes: String
    public let installer: UpdateInstaller?
}
public struct UpdateResponse: Sendable {
    public let data: Data
    public let status: Int
    public init(data: Data, status: Int) { self.data = data; self.status = status }
}
public protocol UpdateTransport: Sendable {
    func fetch(_ request: URLRequest) async throws -> UpdateResponse
}
public struct GitHubUpdateTransport: UpdateTransport {
    public init() {}
    public func fetch(_ request: URLRequest) async throws -> UpdateResponse {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
        return UpdateResponse(data: data, status: response.statusCode)
    }
}
public enum UpdateError: LocalizedError, Sendable {
    case unavailableSource, rateLimited, invalidResponse, invalidRelease, checksum, http(Int)
    public var errorDescription: String? {
        switch self {
        case .unavailableSource: L("暂时无法访问更新源，请稍后重试或前往 GitHub 查看。")
        case .rateLimited: L("GitHub 暂时限制了检查频率，请稍后重试。")
        case .invalidResponse: L("未能读取更新信息，请稍后重试。")
        case .invalidRelease: L("更新信息不完整，请前往 GitHub 查看发布情况。")
        case .checksum: L("安装包校验未通过，文件未保留。请重新下载。")
        case .http(let status): L("更新服务暂不可用（\(status)），请稍后重试。")
        }
    }
}

public struct UpdateSchedule {
    public static let interval: TimeInterval = 24 * 60 * 60
    public static func isDue(enabled: Bool, lastAttempt: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        guard let lastAttempt else { return true }
        // A clock correction must not suppress checks indefinitely.
        return now < lastAttempt || now.timeIntervalSince(lastAttempt) >= interval
    }
}

/// Only reads public GitHub releases. No credential or plug-in inventory is sent.
public struct GitHubUpdates: Sendable {
    public static let owner = "xincheng1237"
    public static let repository = "PluginShelf"
    public static let releasesURL = URL(string: "https://github.com/\(owner)/\(repository)/releases")!
    private let transport: any UpdateTransport
    public init(transport: any UpdateTransport = GitHubUpdateTransport()) { self.transport = transport }
    public func latest(after installed: ReleaseVersion) async throws -> AvailableUpdate? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.owner)/\(Self.repository)/releases/latest")!)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("PluginShelf/\(installed.text)", forHTTPHeaderField: "User-Agent")
        let response = try await transport.fetch(request)
        switch response.status {
        case 200: break
        case 404: throw UpdateError.unavailableSource
        case 403, 429: throw UpdateError.rateLimited
        default: throw UpdateError.http(response.status)
        }
        return try Self.parse(response.data, after: installed)
    }
    public static func parse(_ data: Data, after installed: ReleaseVersion) throws -> AvailableUpdate? {
        guard data.count <= 5_000_000, let release = try? JSONDecoder().decode(Release.self, from: data),
              !release.draft, !release.prerelease, let version = ReleaseVersion(release.tag_name),
              trusted(release.html_url, path: "/\(owner)/\(repository)/releases/tag/\(release.tag_name)") else { throw UpdateError.invalidRelease }
        guard version > installed else { return nil }
        let name = "PluginShelf-\(version.text)-macOS-Universal.dmg"
        let asset = release.assets.first { asset in
            asset.name == name && asset.state == "uploaded" && asset.size > 0 && asset.size <= 1_000_000_000 &&
            trusted(asset.browser_download_url, path: "/\(owner)/\(repository)/releases/download/\(release.tag_name)/\(name)") && validDigest(asset.digest)
        }
        let installer = asset.map { UpdateInstaller(name: $0.name, url: $0.browser_download_url, bytes: $0.size, sha256: String($0.digest!.dropFirst(7)).lowercased()) }
        return AvailableUpdate(version: version, page: release.html_url, notes: String((release.body ?? "").prefix(20_000)), installer: installer)
    }
    private static func trusted(_ url: URL, path: String) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.port == nil && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil && url.path == path
    }
    private static func validDigest(_ value: String?) -> Bool {
        guard let value, value.hasPrefix("sha256:") else { return false }
        let hash = value.dropFirst(7)
        return hash.count == 64 && hash.allSatisfy { $0.isASCII && $0.isHexDigit }
    }
    public static func verifyInstaller(_ file: URL, installer: UpdateInstaller) throws {
        guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) == installer.bytes else { throw UpdateError.checksum }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == installer.sha256 else { throw UpdateError.checksum }
    }
    private struct Release: Decodable {
        let tag_name: String
        let html_url: URL
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }
    private struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let size: Int64
        let state: String
        let digest: String?
    }
}

/// Downloads into a staging file; only a verified result reaches the chosen path.
public actor UpdateDownloader {
    public init() {}
    public func download(_ installer: UpdateInstaller, to destination: URL) async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: installer.url); request.timeoutInterval = 120
        let (file, response) = try await session.download(for: request)
        defer { try? FileManager.default.removeItem(at: file) }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw UpdateError.invalidResponse }
        try GitHubUpdates.verifyInstaller(file, installer: installer)
        try Task.checkCancellation()
        // moveItem refuses to overwrite even if a file appears during download.
        try FileManager.default.moveItem(at: file, to: destination)
    }
}
