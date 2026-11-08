@testable import DoormanCore
import Foundation
import Testing

struct StubSource: ReleaseSource {
    var result: Result<ReleaseInfo, URLError>
    func latestRelease() async throws -> ReleaseInfo {
        try result.get()
    }
}

@MainActor
final class MemoryPreferences: UpdatePreferences {
    var checksAutomatically = true
    var lastCheck: Date?
    var skippedTag: String?
}

func release(_ tag: String) -> ReleaseInfo {
    ReleaseInfo(version: AppVersion(tag)!, tag: tag, url: URL(string: "https://github.com/schowave/doorman/releases/tag/\(tag)")!)
}

@MainActor
struct UpdatePolicyTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let prefs = MemoryPreferences()

    func policy(_ result: Result<ReleaseInfo, URLError>, current: String = "0.1.1") -> UpdatePolicy {
        UpdatePolicy(currentVersion: current, source: StubSource(result: result), preferences: prefs, now: { now })
    }

    @Test func manualCheckReportsEveryOutcome() async {
        #expect(await policy(.success(release("v0.2.0"))).checkNow() == .available(release("v0.2.0")))
        #expect(await policy(.success(release("v0.1.1"))).checkNow() == .upToDate)
        #expect(await policy(.failure(URLError(.notConnectedToInternet))).checkNow() == .failed(URLError(.notConnectedToInternet).localizedDescription))
    }

    @Test func automaticCheckOnlyAnnouncesNewReleases() async {
        #expect(await policy(.success(release("v0.2.0"))).checkAutomatically() == .available(release("v0.2.0")))
        prefs.lastCheck = nil
        #expect(await policy(.success(release("v0.1.1"))).checkAutomatically() == nil)
        prefs.lastCheck = nil
        #expect(await policy(.failure(URLError(.timedOut))).checkAutomatically() == nil)
    }

    @Test func automaticCheckRunsOncePerDay() async {
        let p = policy(.success(release("v0.2.0")))
        #expect(p.isDue)
        _ = await p.checkAutomatically()
        #expect(prefs.lastCheck == now)
        #expect(!p.isDue)
        #expect(await p.checkAutomatically() == nil)
        prefs.lastCheck = now.addingTimeInterval(-25 * 3600)
        #expect(p.isDue)
    }

    @Test func failedCheckIsRetriedNextTime() async {
        _ = await policy(.failure(URLError(.timedOut))).checkAutomatically()
        #expect(prefs.lastCheck == nil)
    }

    @Test func turnedOffMeansNoAutomaticChecks() async {
        prefs.checksAutomatically = false
        let p = policy(.success(release("v0.2.0")))
        #expect(!p.isDue)
        #expect(await p.checkAutomatically() == nil)
        #expect(await p.checkNow() == .available(release("v0.2.0")))
    }

    @Test func putOffReleaseIsOnlyShownWhenAsked() async {
        let p = policy(.success(release("v0.2.0")))
        p.putOff(release("v0.2.0"))
        #expect(await p.checkAutomatically() == nil)
        #expect(p.available == release("v0.2.0"))
        #expect(await p.checkNow() == .available(release("v0.2.0")))
        prefs.lastCheck = nil
        #expect(await policy(.success(release("v0.3.0"))).checkAutomatically() == .available(release("v0.3.0")))
    }

    @Test func devBuildNeverUpdates() async {
        #expect(await policy(.success(release("v9.0.0")), current: "0.0.0").checkNow() == .upToDate)
    }

    @Test func versionOrder() throws {
        #expect(AppVersion("v0.1.1")?.parts == [0, 1, 1])
        #expect(AppVersion("0.2.0-rc.1")?.parts == [0, 2, 0])
        #expect(AppVersion("dev") == nil)
        #expect(try #require(AppVersion("0.1.10")) > #require(AppVersion("0.1.9")))
        #expect(try #require(AppVersion("1.0")) == #require(AppVersion("1.0.0")))
    }

    @Test func parsesGitHubLatestRelease() throws {
        let json = #"{"tag_name":"v0.2.0","html_url":"https://github.com/schowave/doorman/releases/tag/v0.2.0","draft":false,"prerelease":false}"#
        #expect(try GitHubReleaseSource.parse(Data(json.utf8)) == release("v0.2.0"))
        let pre = #"{"tag_name":"v0.3.0-rc.1","html_url":"https://x.invalid","prerelease":true}"#
        #expect(throws: (any Error).self) { try GitHubReleaseSource.parse(Data(pre.utf8)) }
        #expect(throws: (any Error).self) { try GitHubReleaseSource.parse(Data("{}".utf8)) }
    }
}
