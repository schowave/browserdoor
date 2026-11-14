@testable import BrowserdoorCore
import Foundation
import Testing

/// How the download build's updater (Sparkle) moves the status shown in the menu and settings.
struct UpdateCycleTests {
    @Test func checkTheUserAskedForEndsWithAnAnswer() {
        #expect(UpdateStatus.idle.after(.started) == .checking)
        #expect(UpdateStatus.checking.after(.notFound) == .upToDate)
        #expect(UpdateStatus.checking.after(.found(version: "1.2.3")) == .available(release("v1.2.3")))
        #expect(UpdateStatus.checking.after(.finished(error: "offline")) == .failed("offline"))
    }

    @Test func cancelledCheckDoesNotStayChecking() {
        #expect(UpdateStatus.checking.after(.finished(error: nil)) == .idle)
    }

    @Test func endOfCycleKeepsAnAnswerAlreadyGiven() {
        #expect(UpdateStatus.available(release("v1.2.3")).after(.finished(error: nil)) == .available(release("v1.2.3")))
        #expect(UpdateStatus.upToDate.after(.finished(error: nil)) == .upToDate)
    }

    @Test func failedBackgroundCheckKeepsWhatWasKnown() {
        #expect(UpdateStatus.upToDate.after(.finished(error: "offline")) == .upToDate)
        #expect(UpdateStatus.available(release("v1.2.3")).after(.finished(error: "offline")) == .available(release("v1.2.3")))
    }

    @Test func askingAgainForAFoundUpdateKeepsIt() {
        let found = UpdateStatus.available(release("v1.2.3"))
        #expect(found.after(.started) == found)
        #expect(found.after(.started).after(.finished(error: nil)) == found)
    }

    @Test func skippedUpdateIsNoLongerOffered() {
        #expect(UpdateStatus.available(release("v1.2.3")).after(.skipped) == .idle)
    }

    @Test func unreadableVersionChangesNothing() {
        #expect(UpdateStatus.checking.after(.found(version: "beta")) == .checking)
    }

    @Test func releasePageFollowsTheTag() {
        #expect(GitHubReleaseSource.releasePage(tag: "v1.2.3").absoluteString
            == "https://github.com/schowave/browserdoor/releases/tag/v1.2.3")
        #expect(GitHubReleaseSource.browserdoor.absoluteString == "https://github.com/schowave/browserdoor/releases/latest")
    }
}
