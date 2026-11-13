@testable import BrowserdoorCore
import Foundation
import Testing

/// Records what a launch does to the system; preferences live in a dictionary per bundle ID.
private final class FakeStartupPort: StartupPort {
    var domains: [String: [String: Any]] = [:]
    var handler: String?
    var calls: [String] = []

    func preferences(of bundleId: String) -> [String: Any]? {
        domains[bundleId]
    }

    func setPreferences(_ values: [String: Any]?, of bundleId: String) {
        domains[bundleId] = values
    }

    func httpsHandlerBundleId() -> String? {
        handler
    }

    func quitApps(bundleId: String) {
        calls.append("quit \(bundleId)")
    }

    func registerWithLaunchServices() {
        calls.append("register")
    }

    func unregisterFromLaunchServices(_ app: URL) {
        calls.append("unregister \(app.lastPathComponent)")
    }
}

private final class FakeLoginItem: LegacyLoginItem {
    var isEnabled = true
    func unregister() {
        isEnabled = false
    }
}

/// Launch scenarios on a temporary home and Homebrew prefix.
struct StartupTests {
    let root: URL
    let home: URL
    let prefix: URL
    let fm = FileManager.default
    private let port = FakeStartupPort()

    init() throws {
        root = fm.temporaryDirectory.appendingPathComponent("browserdoor-startup-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        prefix = root.appendingPathComponent("brew")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
    }

    func installHomebrew(_ version: String, formula: String = "browserdoor", app: String = "Browserdoor.app") throws -> URL {
        let cellarApp = prefix.appendingPathComponent("Cellar/\(formula)/\(version)/\(app)")
        try fm.createDirectory(at: cellarApp, withIntermediateDirectories: true)
        let opt = prefix.appendingPathComponent("opt/\(formula)")
        try? fm.removeItem(at: opt)
        try fm.createDirectory(at: opt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: opt, withDestinationURL: cellarApp.deletingLastPathComponent())
        return cellarApp
    }

    func startup(_ bundleId: String = BundleIdentity.release, app: URL, loginItem: LegacyLoginItem? = nil) -> Startup {
        Startup(bundleId: bundleId, installation: Installation(home: home, bundleURL: app, label: bundleId),
                legacyLoginItem: loginItem, port: port)
    }

    func agentTarget(_ inst: Installation) throws -> String? {
        let data = try Data(contentsOf: inst.agentURL)
        let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return (dict?["ProgramArguments"] as? [String])?.last
    }

    // MARK: Onboarding and identity

    @Test func firstLaunchOnboardsOnce() throws {
        let app = try installHomebrew("0.5.0")
        #expect(startup(app: app).run() == .onboard)
        #expect(startup(app: app).run() == .nothing)
        #expect(port.calls.filter { $0 == "register" }.count == 2)
    }

    @Test func devBuildsNeitherOnboardNorTouchOldData() throws {
        port.domains[BundleIdentity.legacy] = ["didOnboard": true]
        port.handler = BundleIdentity.legacy
        let legacyAgent = home.appendingPathComponent("Library/LaunchAgents/\(BundleIdentity.legacy).plist")
        try fm.createDirectory(at: legacyAgent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: legacyAgent)

        let dev = root.appendingPathComponent("repo/build/Browserdoor.app")
        #expect(startup(BundleIdentity.dev, app: dev).run() == .nothing)
        #expect(port.domains[BundleIdentity.legacy] != nil)
        #expect(fm.fileExists(atPath: legacyAgent.path))
        #expect(!port.calls.contains { $0.hasPrefix("quit") })
    }

    @Test func noBundleCountsAsDevBuild() {
        #expect(BundleIdentity.of(bundleIdentifier: nil) == BundleIdentity.dev)
        #expect(!BundleIdentity.isRelease(BundleIdentity.of(bundleIdentifier: nil)))
        #expect(BundleIdentity.isRelease(BundleIdentity.of(bundleIdentifier: "io.github.schowave.browserdoor")))
    }

    @Test func updateFromOldIdentityMovesEverythingAndReclaimsDefaultOnce() throws {
        let cache = home.appendingPathComponent("Library/Caches/\(BundleIdentity.legacy)/zen-icons")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        port.domains[BundleIdentity.legacy] = ["didOnboard": true, "skippedUpdateVersion": "v0.4.0", "AppleLanguages": ["de"]]
        port.domains[BundleIdentity.release] = ["skippedUpdateVersion": "v0.5.1"]
        port.handler = BundleIdentity.legacy
        let app = try installHomebrew("0.5.0")

        #expect(startup(app: app).run() == .reclaimDefaultBrowser)
        let moved = try #require(port.domains[BundleIdentity.release])
        #expect(moved["didOnboard"] as? Bool == true)
        #expect(moved["AppleLanguages"] as? [String] == ["de"])
        #expect(moved["skippedUpdateVersion"] as? String == "v0.5.1") // values under the new ID win
        #expect(port.domains[BundleIdentity.legacy] == nil)
        #expect(!fm.fileExists(atPath: cache.deletingLastPathComponent().path))
        #expect(port.calls.first == "quit \(BundleIdentity.legacy)")

        #expect(startup(app: app).run() == .nothing) // nothing left to move: no second question
    }

    @Test func anotherDefaultBrowserIsLeftAlone() throws {
        port.domains[BundleIdentity.legacy] = ["didOnboard": true]
        port.handler = "app.zen-browser.zen"
        #expect(try startup(app: installHomebrew("0.5.0")).run() == .nothing)
    }

    @Test func readsHttpsHandlerFromLaunchServicesPreferences() throws {
        let plist: [String: Any] = ["LSHandlers": [
            ["LSHandlerURLScheme": "gather2", "LSHandlerRoleAll": "com.gather"],
            ["LSHandlerURLScheme": "https", "LSHandlerRoleAll": BundleIdentity.legacy],
        ]]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        #expect(Startup.httpsHandler(launchServicesPlist: data) == BundleIdentity.legacy)
        #expect(Startup.httpsHandler(launchServicesPlist: Data()) == nil)
    }

    // MARK: Login item

    @Test func loginItemUnderTheOldLabelMovesToTheNewOne() throws {
        let app = try installHomebrew("0.5.0")
        let old = Installation(home: home, bundleURL: app, label: BundleIdentity.legacy)
        try old.setLaunchAtLogin(true)
        let start = startup(app: app)
        _ = start.run()
        #expect(!fm.fileExists(atPath: old.agentURL.path))
        #expect(try agentTarget(start.installation) == start.installation.linkURL.path)
    }

    @Test func noOldLoginItemMeansNoNewOne() throws {
        let start = try startup(app: installHomebrew("0.5.0"))
        _ = start.run()
        #expect(!start.installation.launchesAtLogin)
    }

    @Test func smAppServiceLoginItemBecomesALaunchAgent() throws {
        let item = FakeLoginItem()
        let start = try startup(app: installHomebrew("0.1.0"), loginItem: item)
        _ = start.run()
        #expect(!item.isEnabled)
        #expect(try agentTarget(start.installation) == start.installation.linkURL.path)
    }

    // MARK: Doorman (up to 0.2.x)

    @Test func doormanLinkIsRemovedAndLoginItemRepointed() throws {
        let start = try startup(app: installHomebrew("0.3.0"))
        let inst = start.installation
        let apps = inst.linkURL.deletingLastPathComponent()
        let legacy = apps.appendingPathComponent("Doorman.app")
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: legacy.path,
                                  withDestinationPath: prefix.appendingPathComponent("opt/doorman/Doorman.app").path)
        try fm.createDirectory(at: inst.agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(
            fromPropertyList: ["Label": "x", "ProgramArguments": ["/usr/bin/open", "-a", legacy.path]],
            format: .xml, options: 0
        ).write(to: inst.agentURL)
        _ = start.run()
        #expect((try? fm.destinationOfSymbolicLink(atPath: legacy.path)) == nil)
        #expect(try agentTarget(inst) == inst.linkURL.path)
    }

    @Test func foreignDoormanAppStaysUntouched() throws {
        let start = try startup(app: installHomebrew("0.3.0"))
        let apps = start.installation.linkURL.deletingLastPathComponent()
        let other = apps.appendingPathComponent("Doorman.app")
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: other.path, withDestinationPath: "/Applications/Doorman.app")
        _ = start.run()
        #expect(try fm.destinationOfSymbolicLink(atPath: other.path) == "/Applications/Doorman.app")
    }

    @Test func doormanConfigFolderMovesOnce() throws {
        let old = home.appendingPathComponent(".config/doorman/config.json")
        try fm.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: old)
        let app = try installHomebrew("0.3.0")
        _ = startup(app: app).run()
        #expect(fm.fileExists(atPath: Config.fileURL(home: home).path))
        #expect(!fm.fileExists(atPath: old.path))

        try fm.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"old\":1}".utf8).write(to: old)
        _ = startup(app: app).run() // a new config exists: leave both alone
        #expect(try String(contentsOf: Config.fileURL(home: home), encoding: .utf8) == "{}")
        #expect(fm.fileExists(atPath: old.path))
    }

    // MARK: After an update

    @Test func previousBundleGoneAfterUpdateIsUnregistered() throws {
        let old = try installHomebrew("0.4.0")
        _ = startup(app: old).run()
        let new = try installHomebrew("0.5.0")
        try fm.removeItem(at: old.deletingLastPathComponent()) // brew cleanup
        _ = startup(app: new).run()
        #expect(port.calls.contains("unregister Browserdoor.app"))
        #expect(port.domains[BundleIdentity.release]?["lastBundlePath"] as? String == new.path)
    }

    // MARK: Updating

    @Test func upgradeScriptLeavesTheRestartToTheAppAndQuitsThisProcessOnly() throws {
        let homebrew = try #require(HomebrewInstall.detect(bundlePath: "/opt/my brew/Cellar/browserdoor/0.5.0/Browserdoor.app"))
        let script = homebrew.upgradeScript(runningPID: 4242)
        #expect(script.contains("'/opt/my brew/bin/brew' update --quiet && '/opt/my brew/bin/brew' upgrade browserdoor"))
        #expect(script.contains("before=\"$(readlink '/opt/my brew/opt/browserdoor')\""))
        #expect(script.contains("if [ \"$(readlink '/opt/my brew/opt/browserdoor')\" = \"$before\" ]; then"))
        #expect(script.contains("while kill -0 4242 2>/dev/null && [ $i -lt 75 ]; do sleep 0.2;"))
        #expect(script.contains("if kill -0 4242 2>/dev/null; then\n  kill 4242 2>/dev/null\n"))
        #expect(script.contains("\n  '/opt/my brew/bin/browserdoor'\nfi\n"))
        #expect(!script.contains("pkill"))
    }
}
