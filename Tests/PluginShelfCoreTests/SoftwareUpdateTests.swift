import Foundation
import Testing
import CryptoKit
@testable import PluginShelfCore

private func releaseData(tag: String = "v1.2", draft: Bool = false, prerelease: Bool = false,
                         page: String? = nil, download: String? = nil, digest: String? = nil) throws -> Data {
    let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    let name = "PluginShelf-\(version)-macOS-Universal.dmg"
    let json: [String: Any] = [
        "tag_name": tag, "draft": draft, "prerelease": prerelease, "body": "新增功能\n新增测试功能。",
        "html_url": page ?? "https://github.com/xincheng1237/PluginShelf/releases/tag/\(tag)",
        "assets": [["name": name, "state": "uploaded", "size": 4,
                    "digest": digest ?? "sha256:" + String(repeating: "a", count: 64),
                    "browser_download_url": download ?? "https://github.com/xincheng1237/PluginShelf/releases/download/\(tag)/\(name)"]]
    ]
    return try JSONSerialization.data(withJSONObject: json)
}

@Test func releaseVersionsCompareNumericallyAndNormalizeMissingPatch() throws {
    #expect(ReleaseVersion("v1.1") == ReleaseVersion("1.1.0"))
    let newer = try #require(ReleaseVersion("1.10"))
    let older = try #require(ReleaseVersion("1.9.99"))
    #expect(newer > older)
    for value in ["", "1", "1..2", "1.2-beta", "1.2.3+test", "../1.2", "1.２", "1.2/3", "1.2.3.4"] {
        #expect(ReleaseVersion(value) == nil)
    }
}
@Test func sameOrOlderReleaseDoesNotOfferAnUpdate() throws {
    let current = try #require(ReleaseVersion("1.1"))
    for tag in ["v1.0", "v1.1", "v1.1.0"] {
        #expect(try GitHubUpdates.parse(releaseData(tag: tag), after: current) == nil)
    }
}
@Test func stableFutureReleaseProvidesVerifiedDMGAndPlainNotes() throws {
    let current = try #require(ReleaseVersion("1.1"))
    let parsed = try GitHubUpdates.parse(releaseData(), after: current)
    let update = try #require(parsed)
    #expect(update.version.text == "1.2")
    #expect(update.installer?.name == "PluginShelf-1.2-macOS-Universal.dmg")
    #expect(update.notes.contains("新增功能"))
}
@Test func draftsPrereleasesAndMalformedResponsesCannotLookCurrent() throws {
    let current = try #require(ReleaseVersion("1.1"))
    #expect(throws: UpdateError.self) { try GitHubUpdates.parse(releaseData(draft: true), after: current) }
    #expect(throws: UpdateError.self) { try GitHubUpdates.parse(releaseData(prerelease: true), after: current) }
    #expect(throws: UpdateError.self) { try GitHubUpdates.parse(Data("{}".utf8), after: current) }
}
@Test func releaseLinksCannotEscapeTheConfiguredRepository() throws {
    let current = try #require(ReleaseVersion("1.1"))
    for page in ["http://github.com/xincheng1237/PluginShelf/releases/tag/v1.2", "https://evil.example/release", "https://github.com/other/repo/releases/tag/v1.2", "https://github.com/xincheng1237/PluginShelf/releases/tag/v1.2?next=bad"] {
        #expect(throws: UpdateError.self) { try GitHubUpdates.parse(releaseData(page: page), after: current) }
    }
    for download in ["https://evil.example/update.dmg", "https://github.com/other/repo/releases/download/v1.2/PluginShelf-1.2-macOS-Universal.dmg", "http://github.com/xincheng1237/PluginShelf/releases/download/v1.2/PluginShelf-1.2-macOS-Universal.dmg"] {
        #expect(try GitHubUpdates.parse(releaseData(download: download), after: current)?.installer == nil)
    }
}
@Test func missingOrInvalidDigestPreventsInAppDownload() throws {
    let current = try #require(ReleaseVersion("1.1"))
    for digest in ["", "sha256:xyz", "md5:" + String(repeating: "a", count: 32)] {
        let parsed = try GitHubUpdates.parse(releaseData(digest: digest), after: current)
        let update = try #require(parsed)
        #expect(update.installer == nil)
    }
}
@Test func automaticChecksHonorDailyIntervalOptOutAndClockCorrection() {
    let now = Date(timeIntervalSince1970: 100_000)
    #expect(UpdateSchedule.isDue(enabled: true, lastAttempt: nil, now: now))
    #expect(!UpdateSchedule.isDue(enabled: false, lastAttempt: nil, now: now))
    #expect(!UpdateSchedule.isDue(enabled: true, lastAttempt: now.addingTimeInterval(-86_399), now: now))
    #expect(UpdateSchedule.isDue(enabled: true, lastAttempt: now.addingTimeInterval(-86_400), now: now))
    #expect(UpdateSchedule.isDue(enabled: true, lastAttempt: now.addingTimeInterval(100), now: now))
}
private struct TestUpdateTransport: UpdateTransport {
    let status: Int
    func fetch(_ request: URLRequest) async throws -> UpdateResponse {
        #expect(request.url?.absoluteString == "https://api.github.com/repos/xincheng1237/PluginShelf/releases/latest")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.httpBody == nil && (request.httpMethod == "GET"))
        return try UpdateResponse(data: releaseData(), status: status)
    }
}
@Test func inaccessibleAndRateLimitedFeedsNeverReportLatest() async throws {
    let current = try #require(ReleaseVersion("1.1"))
    for status in [404, 403, 429, 500] {
        await #expect(throws: UpdateError.self) {
            try await GitHubUpdates(transport: TestUpdateTransport(status: status)).latest(after: current)
        }
    }
    #expect(try await GitHubUpdates(transport: TestUpdateTransport(status: 200)).latest(after: current)?.version.text == "1.2")
}
@Test func installerDigestAndLengthMustMatchBeforeUse() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("sample.dmg")
    let bytes = Data("test".utf8)
    try bytes.write(to: file)
    let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    let installer = UpdateInstaller(name: "test.dmg", url: GitHubUpdates.releasesURL, bytes: 4, sha256: digest)
    try GitHubUpdates.verifyInstaller(file, installer: installer)
    try Data("evil".utf8).write(to: file)
    #expect(throws: UpdateError.self) { try GitHubUpdates.verifyInstaller(file, installer: installer) }
    try Data("test-extra".utf8).write(to: file)
    #expect(throws: UpdateError.self) { try GitHubUpdates.verifyInstaller(file, installer: installer) }
}
