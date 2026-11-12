@testable import BrowserdoorCore
import Foundation
import Testing

private final class FakePort: IdentityMigrationPort {
    var legacy: [String: Any]
    var current: [String: Any] = [:]
    var handler: String?

    init(legacy: [String: Any] = [:], handler: String? = nil) {
        self.legacy = legacy
        self.handler = handler
    }

    func legacyPreferences() -> [String: Any] {
        legacy
    }

    func importPreferences(_ values: [String: Any]) {
        current.merge(values) { kept, _ in kept }
    }

    func removeLegacyPreferences() {
        legacy = [:]
    }

    func httpsHandlerBundleId() -> String? {
        handler
    }
}

struct IdentityMigrationTests {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("browserdoor-id-\(UUID().uuidString)")

    var legacyCache: URL {
        home.appendingPathComponent("Library/Caches/io.github.schowave.doorman/zen-icons", isDirectory: true)
    }

    @Test func movesPreferencesCacheAndDefaultBrowserOnce() throws {
        try FileManager.default.createDirectory(at: legacyCache, withIntermediateDirectories: true)
        let port = FakePort(legacy: ["didOnboard": true, "skippedUpdateVersion": "v0.4.0"],
                            handler: "io.github.schowave.doorman")
        port.current["skippedUpdateVersion"] = "v0.5.1"

        let first = IdentityMigration(home: home, port: port).run()
        #expect(first == .init(migrated: true, reclaimDefaultBrowser: true))
        #expect(port.current["didOnboard"] as? Bool == true)
        #expect(port.current["skippedUpdateVersion"] as? String == "v0.5.1") // existing values win
        #expect(port.legacy.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: legacyCache.deletingLastPathComponent().path))

        #expect(IdentityMigration(home: home, port: port).run() == .init()) // nothing left to move
    }

    @Test func leavesAnotherDefaultBrowserAlone() {
        let port = FakePort(legacy: ["didOnboard": true], handler: "app.zen-browser.zen")
        #expect(IdentityMigration(home: home, port: port).run() == .init(migrated: true, reclaimDefaultBrowser: false))
    }

    @Test func freshInstallMigratesNothing() {
        let port = FakePort(handler: "io.github.schowave.doorman")
        #expect(IdentityMigration(home: home, port: port).run() == .init())
    }

    @Test func onlyTheReleaseBuildTakesOverTheOldLoginItem() {
        #expect(IdentityMigration.legacyLabel(for: "io.github.schowave.browserdoor") == "io.github.schowave.doorman")
        #expect(IdentityMigration.legacyLabel(for: "io.github.schowave.browserdoor.dev") == nil)
    }

    @Test func readsHttpsHandlerFromLaunchServicesPreferences() throws {
        let plist: [String: Any] = ["LSHandlers": [
            ["LSHandlerURLScheme": "gather2", "LSHandlerRoleAll": "com.gather"],
            ["LSHandlerURLScheme": "https", "LSHandlerRoleAll": "io.github.schowave.doorman"],
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        #expect(IdentityMigration.httpsHandler(launchServicesPlist: data) == "io.github.schowave.doorman")
        #expect(IdentityMigration.httpsHandler(launchServicesPlist: Data()) == nil)
    }
}
