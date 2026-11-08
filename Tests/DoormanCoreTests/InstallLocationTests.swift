@testable import DoormanCore
import Foundation
import Testing

struct InstallLocationTests {
    @Test func mapsCellarToOpt() {
        #expect(InstallLocation.homebrewOptPath(forBundlePath: "/opt/homebrew/Cellar/doorman/0.1.0/Doorman.app")
            == "/opt/homebrew/opt/doorman/Doorman.app")
        #expect(InstallLocation.homebrewOptPath(forBundlePath: "/usr/local/Cellar/doorman/1.2.3_1/Doorman.app")
            == "/usr/local/opt/doorman/Doorman.app")
    }

    @Test func ignoresNonCellarPaths() {
        #expect(InstallLocation.homebrewOptPath(forBundlePath: "/Applications/Doorman.app") == nil)
        #expect(InstallLocation.homebrewOptPath(forBundlePath: "/Users/x/repos/doorman/build/Doorman.app") == nil)
        #expect(InstallLocation.homebrewOptPath(forBundlePath: "/opt/homebrew/Cellar/doorman/Doorman.app") == nil)
    }

    let opt = "/opt/homebrew/opt/doorman/Doorman.app"

    @Test func linkDecisions() {
        #expect(InstallLocation.linkDecision(linkDestination: nil, pathExists: false, optPath: opt) == .create)
        #expect(InstallLocation.linkDecision(linkDestination: opt, pathExists: true, optPath: opt) == .keep)
        #expect(InstallLocation.linkDecision(
            linkDestination: "/opt/homebrew/Cellar/doorman/0.1.0/Doorman.app", pathExists: true, optPath: opt
        ) == .replace)
        #expect(InstallLocation.linkDecision(
            linkDestination: "/usr/local/opt/doorman/Doorman.app", pathExists: true, optPath: opt
        ) == .replace)
        // Somebody else's link (e.g. to a dev build) and real apps stay untouched.
        #expect(InstallLocation.linkDecision(
            linkDestination: "/Users/x/repos/doorman/build/Doorman.app", pathExists: true, optPath: opt
        ) == .leaveAlone)
        #expect(InstallLocation.linkDecision(
            linkDestination: "/opt/homebrew/Cellar/other/1.0/Doorman.app", pathExists: true, optPath: opt
        ) == .leaveAlone)
        #expect(InstallLocation.linkDecision(linkDestination: nil, pathExists: true, optPath: opt) == .leaveAlone)
    }

    @Test func agentRewrite() throws {
        let current = try LoginAgent.plist(label: "l", appPath: "/Users/x/Applications/Doorman.app")
        #expect(!LoginAgent.needsRewrite(existing: current, appPath: "/Users/x/Applications/Doorman.app"))
        #expect(LoginAgent.needsRewrite(existing: current, appPath: "/Applications/Doorman.app"))
        #expect(LoginAgent.needsRewrite(existing: Data("garbage".utf8), appPath: "/x"))
    }

    @Test func userApplicationsLink() {
        let link = InstallLocation.userApplicationsLink(home: URL(fileURLWithPath: "/Users/x"), appName: "Doorman")
        #expect(link.path == "/Users/x/Applications/Doorman.app")
    }

    @Test func loginAgentOpensStablePath() throws {
        let data = try LoginAgent.plist(label: "io.example.doorman", appPath: "/Users/x/Applications/Doorman.app")
        let dict = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(dict["Label"] as? String == "io.example.doorman")
        #expect(dict["ProgramArguments"] as? [String] == ["/usr/bin/open", "-a", "/Users/x/Applications/Doorman.app"])
        #expect(dict["RunAtLoad"] as? Bool == true)
        #expect(LoginAgent.fileURL(home: URL(fileURLWithPath: "/Users/x"), label: "l").path
            == "/Users/x/Library/LaunchAgents/l.plist")
    }
}
