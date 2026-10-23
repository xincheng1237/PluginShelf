import Foundation
import Testing
import PluginShelfCore
@testable import PluginShelf

private actor Feed: UpdateTransport {
    var requests = 0
    let status: Int
    init(status: Int = 200) { self.status = status }
    func fetch(_ request: URLRequest) async throws -> UpdateResponse {
        requests += 1
        let json = """
        {"tag_name":"v1.2","html_url":"https://github.com/xincheng1237/PluginShelf/releases/tag/v1.2","body":"测试说明","draft":false,"prerelease":false,"assets":[]}
        """
        return UpdateResponse(data: Data(json.utf8), status: status)
    }
}
@MainActor
private struct UpdaterFixture {
    let suite = "PluginShelf.UpdaterTests." + UUID().uuidString
    let defaults: UserDefaults
    let feed: Feed
    let updater: SoftwareUpdater
    init(status: Int = 200) throws {
        defaults = try #require(UserDefaults(suiteName: suite)); feed = Feed(status: status)
        updater = SoftwareUpdater(defaults: defaults, client: GitHubUpdates(transport: feed))
    }
    func cleanup() { defaults.removePersistentDomain(forName: suite) }
}
@Test @MainActor func automaticResultIsQuietlyAvailableAndDailyChecksAreDeduplicated() async throws {
    let f = try UpdaterFixture(); defer { f.cleanup() }
    await f.updater.check(manual: false)
    #expect(f.updater.showBanner && f.updater.available?.version.text == "1.2")
    await f.updater.check(manual: false)
    #expect(await f.feed.requests == 1)
    // Manual checks bypass the automatic schedule, without showing a second banner.
    await f.updater.check(manual: true)
    #expect(await f.feed.requests == 2)
    #expect(!f.updater.showBanner)
}
@Test @MainActor func optOutPersistsAndManualCheckingStillWorks() async throws {
    let f = try UpdaterFixture(); defer { f.cleanup() }
    f.updater.automatic = false
    await f.updater.check(manual: false)
    #expect(await f.feed.requests == 0)
    #expect(!f.defaults.bool(forKey: "updates.automatic"))
    await f.updater.check(manual: true)
    #expect(await f.feed.requests == 1)
    #expect(f.updater.available?.version.text == "1.2")
}
@Test @MainActor func snoozeAndSkipPersistButDoNotBlockManualChecks() async throws {
    let f = try UpdaterFixture(); defer { f.cleanup() }
    await f.updater.check(manual: false)
    f.updater.dismissBanner()
    #expect(!f.updater.showBanner)
    f.defaults.removeObject(forKey: "updates.lastAttempt")
    let snoozed = SoftwareUpdater(defaults: f.defaults, client: GitHubUpdates(transport: f.feed))
    await snoozed.check(manual: false)
    #expect(!snoozed.showBanner && snoozed.available != nil)
    snoozed.skip(try #require(snoozed.available))
    f.defaults.removeObject(forKey: "updates.lastAttempt")
    f.defaults.removeObject(forKey: "updates.snoozedUntil")
    let skipped = SoftwareUpdater(defaults: f.defaults, client: GitHubUpdates(transport: f.feed))
    await skipped.check(manual: false)
    #expect(!skipped.showBanner)
    await skipped.check(manual: true)
    #expect(skipped.available != nil)
}
@Test @MainActor func failedAutomaticCheckNeverOpensBannerOrClaimsCurrent() async throws {
    let f = try UpdaterFixture(status: 404); defer { f.cleanup() }
    await f.updater.check(manual: false)
    guard case .failed(let message) = f.updater.state else { Issue.record("不可访问的更新源被误报"); return }
    #expect(message == UpdateError.unavailableSource.localizedDescription)
    #expect(!f.updater.showBanner)
    await f.updater.check(manual: false)
    #expect(await f.feed.requests == 1)
}

@Test @MainActor func fileSizesFollowTheSelectedAppLanguage() {
    L10n.$overrideLanguage.withValue(.english) { #expect(byteString(706).contains("bytes")) }
    L10n.$overrideLanguage.withValue(.simplifiedChinese) { #expect(byteString(706).contains("字节")) }
}
