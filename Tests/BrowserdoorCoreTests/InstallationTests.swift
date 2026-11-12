@testable import BrowserdoorCore
import Foundation
import Testing

/// Scenarios on a real temporary file system: a fake Homebrew prefix and a fake home.
struct InstallationTests {
    let root: URL
    let home: URL
    let prefix: URL
    let fm = FileManager.default

    init() throws {
        root = fm.temporaryDirectory.appendingPathComponent("browserdoor-install-\(UUID().uuidString)")
        home = root.appendingPathComponent("home")
        prefix = root.appendingPathComponent("brew")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
    }

    /// Creates `<prefix>/Cellar/browserdoor/<version>/Browserdoor.app` and points opt at it.
    func installHomebrew(_ version: String) throws -> URL {
        let cellarApp = prefix.appendingPathComponent("Cellar/browserdoor/\(version)/Browserdoor.app")
        try fm.createDirectory(at: cellarApp, withIntermediateDirectories: true)
        let opt = prefix.appendingPathComponent("opt/browserdoor")
        try? fm.removeItem(at: opt)
        try fm.createDirectory(at: opt.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: opt, withDestinationURL: cellarApp.deletingLastPathComponent())
        return cellarApp
    }

    func installation(_ bundle: URL) -> Installation {
        Installation(home: home, bundleURL: bundle, label: "test.browserdoor")
    }

    var optApp: String {
        prefix.appendingPathComponent("opt/browserdoor/Browserdoor.app").path
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
                                  withDestinationPath: prefix.appendingPathComponent("Cellar/browserdoor/0.1.0/Browserdoor.app").path)
        inst.prepare()
        #expect(try fm.destinationOfSymbolicLink(atPath: inst.linkURL.path) == optApp)
    }

    @Test func foreignLinkAndRealAppStayUntouched() throws {
        let inst = try installation(installHomebrew("0.1.0"))
        try fm.createDirectory(at: inst.linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: inst.linkURL.path, withDestinationPath: "/repo/build/Browserdoor.app")
        inst.prepare()
        #expect(try fm.destinationOfSymbolicLink(atPath: inst.linkURL.path) == "/repo/build/Browserdoor.app")
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

        let dev = installation(root.appendingPathComponent("repo/build/Browserdoor.app"))
        dev.prepare()
        #expect(dev.stableAppURL == dev.bundleURL)
        #expect(try agentTarget(dev) == installed.linkURL.path)
    }

    @Test func agentIsRepointedWhenItsAppIsGone() throws {
        let inst = installation(root.appendingPathComponent("Applications/Browserdoor.app"))
        try fm.createDirectory(at: inst.agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let gone = try PropertyListSerialization.data(
            fromPropertyList: ["Label": "x", "ProgramArguments": ["/usr/bin/open", "-a", "/nowhere/Browserdoor.app"]],
            format: .xml, options: 0
        )
        try gone.write(to: inst.agentURL)
        inst.prepare()
        #expect(try agentTarget(inst) == inst.bundleURL.path)
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
        let dev = root.appendingPathComponent("repo/build/Browserdoor.app")
        try fm.createDirectory(at: dev, withIntermediateDirectories: true)
        let inst = try installation(installHomebrew("0.2.2"))
        #expect(inst.staleRegistration(previousBundlePath: dev.path) == nil)
    }

    @Test func detectsHomebrewPaths() {
        let brew = HomebrewInstall.detect(bundlePath: "/opt/homebrew/Cellar/browserdoor/0.1.0/Browserdoor.app")
        #expect(brew?.prefix.path == "/opt/homebrew")
        #expect(brew?.brew.path == "/opt/homebrew/bin/brew")
        #expect(brew?.optApp.path == "/opt/homebrew/opt/browserdoor/Browserdoor.app")
        #expect(HomebrewInstall.detect(bundlePath: "/usr/local/Cellar/browserdoor/1.2.3_1/Browserdoor.app")?.optApp.path
            == "/usr/local/opt/browserdoor/Browserdoor.app")
        #expect(HomebrewInstall.detect(bundlePath: "/Applications/Browserdoor.app") == nil)
        #expect(HomebrewInstall.detect(bundlePath: "/opt/homebrew/Cellar/browserdoor/Browserdoor.app") == nil)
    }
}
