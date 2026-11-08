@testable import DoormanCore
import Foundation
import Testing

/// Scenarios on a real temporary file system: a fake Homebrew prefix and a fake home.
struct InstallationTests {
    let root: URL
    let home: URL
    let prefix: URL
    let fm = FileManager.default

    init() throws {
        root = fm.temporaryDirectory.appendingPathComponent("doorman-install-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        prefix = root.appendingPathComponent("brew")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
    }

    /// Creates `<prefix>/Cellar/doorman/<version>/Doorman.app` and points opt at it.
    func installHomebrew(_ version: String) throws -> URL {
        let cellarApp = prefix.appendingPathComponent("Cellar/doorman/\(version)/Doorman.app")
        try fm.createDirectory(at: cellarApp, withIntermediateDirectories: true)
        let opt = prefix.appendingPathComponent("opt/doorman")
        try? fm.removeItem(at: opt)
        try fm.createDirectory(at: opt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: opt, withDestinationURL: cellarApp.deletingLastPathComponent())
        return cellarApp
    }

    func installation(_ bundle: URL, legacy: LegacyLoginItem? = nil) -> Installation {
        Installation(home: home, bundleURL: bundle, label: "test.doorman", legacyLoginItem: legacy)
    }

    var optApp: String {
        prefix.appendingPathComponent("opt/doorman/Doorman.app").path
    }

    func agentTarget(_ inst: Installation) throws -> String? {
        let data = try Data(contentsOf: inst.agentURL)
        let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return (dict?["ProgramArguments"] as? [String])?.last
    }

    @Test func homebrewInstallGetsStableLinkAndAgent() throws {
        let inst = try installation(installHomebrew("0.1.0"))
        inst.prepare()
        #expect(try fm.destinationOfSymbolicLink(atPath: inst.linkURL.path) == optApp)
        #expect(inst.stableAppURL == inst.linkURL)
        try inst.setLaunchAtLogin(true)
        #expect(inst.launchesAtLogin)
        #expect(try agentTarget(inst) == inst.linkURL.path)
        try inst.setLaunchAtLogin(false)
        #expect(!inst.launchesAtLogin)
    }

    @Test func upgradeKeepsLinkAndAgentValid() throws {
        let inst = try installation(installHomebrew("0.1.0"))
        inst.prepare()
        try inst.setLaunchAtLogin(true)
        let upgraded = try installation(installHomebrew("0.2.0"))
        upgraded.prepare()
        #expect(try fm.destinationOfSymbolicLink(atPath: upgraded.linkURL.path) == optApp)
        #expect(try agentTarget(upgraded) == upgraded.linkURL.path)
    }

    @Test func staleOwnLinkIsReplaced() throws {
        let inst = try installation(installHomebrew("0.2.0"))
        try fm.createDirectory(at: inst.linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: inst.linkURL.path,
                                  withDestinationPath: prefix.appendingPathComponent("Cellar/doorman/0.1.0/Doorman.app").path)
        inst.prepare()
        #expect(try fm.destinationOfSymbolicLink(atPath: inst.linkURL.path) == optApp)
    }

    @Test func foreignLinkAndRealAppStayUntouched() throws {
        let inst = try installation(installHomebrew("0.1.0"))
        try fm.createDirectory(at: inst.linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: inst.linkURL.path, withDestinationPath: "/repo/build/Doorman.app")
        inst.prepare()
        #expect(try fm.destinationOfSymbolicLink(atPath: inst.linkURL.path) == "/repo/build/Doorman.app")
        #expect(inst.stableAppURL.path == optApp)

        try fm.removeItem(at: inst.linkURL)
        try fm.createDirectory(at: inst.linkURL, withIntermediateDirectories: true) // a real app folder
        inst.prepare()
        #expect((try? fm.destinationOfSymbolicLink(atPath: inst.linkURL.path)) == nil)
    }

    @Test func devBuildCreatesNoLinkAndLeavesAgentAlone() throws {
        let installed = try installation(installHomebrew("0.1.0"))
        installed.prepare()
        try installed.setLaunchAtLogin(true)

        let dev = installation(root.appendingPathComponent("repo/build/Doorman.app"))
        dev.prepare()
        #expect(dev.stableAppURL == dev.bundleURL)
        #expect(try agentTarget(dev) == installed.linkURL.path)
    }

    @Test func agentIsRepointedWhenItsAppIsGone() throws {
        let inst = installation(root.appendingPathComponent("Applications/Doorman.app"))
        try fm.createDirectory(at: inst.agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let gone = try PropertyListSerialization.data(
            fromPropertyList: ["Label": "x", "ProgramArguments": ["/usr/bin/open", "-a", "/nowhere/Doorman.app"]],
            format: .xml, options: 0
        )
        try gone.write(to: inst.agentURL)
        inst.prepare()
        #expect(try agentTarget(inst) == inst.bundleURL.path)
    }

    @Test func legacyLoginItemIsMigrated() throws {
        final class Legacy: LegacyLoginItem {
            var isEnabled = true
            func unregister() {
                isEnabled = false
            }
        }
        let legacy = Legacy()
        let inst = try installation(installHomebrew("0.1.0"), legacy: legacy)
        inst.prepare()
        #expect(!legacy.isEnabled)
        #expect(inst.launchesAtLogin)
        #expect(try agentTarget(inst) == inst.linkURL.path)
    }

    @Test func upgradeLeavesTheOldCellarVersionStale() throws {
        let old = try installHomebrew("0.2.1")
        let current = try installation(installHomebrew("0.2.2"))
        try fm.removeItem(at: old.deletingLastPathComponent()) // brew cleanup
        #expect(current.staleRegistration(previousBundlePath: old.path) == old)
    }

    @Test func nothingIsStaleWithoutAnUpdate() throws {
        let inst = try installation(installHomebrew("0.2.2"))
        #expect(inst.staleRegistration(previousBundlePath: nil) == nil)
        #expect(inst.staleRegistration(previousBundlePath: "") == nil)
        #expect(inst.staleRegistration(previousBundlePath: inst.bundleURL.path) == nil)
    }

    @Test func anExistingPreviousCopyIsNotStale() throws {
        let dev = root.appendingPathComponent("repo/build/Doorman.app")
        try fm.createDirectory(at: dev, withIntermediateDirectories: true)
        let inst = try installation(installHomebrew("0.2.2"))
        #expect(inst.staleRegistration(previousBundlePath: dev.path) == nil)
    }

    @Test func detectsHomebrewPaths() {
        let brew = HomebrewInstall.detect(bundlePath: "/opt/homebrew/Cellar/doorman/0.1.0/Doorman.app")
        #expect(brew?.prefix.path == "/opt/homebrew")
        #expect(brew?.brew.path == "/opt/homebrew/bin/brew")
        #expect(brew?.optApp.path == "/opt/homebrew/opt/doorman/Doorman.app")
        #expect(HomebrewInstall.detect(bundlePath: "/usr/local/Cellar/doorman/1.2.3_1/Doorman.app")?.optApp.path
            == "/usr/local/opt/doorman/Doorman.app")
        #expect(HomebrewInstall.detect(bundlePath: "/Applications/Doorman.app") == nil)
        #expect(HomebrewInstall.detect(bundlePath: "/opt/homebrew/Cellar/doorman/Doorman.app") == nil)
    }
}
