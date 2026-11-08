import Foundation
import Testing
@testable import DoormanCore

struct DiscoveryTests {
    func environment(zenVersion: String = "1.24.1b") -> FakeEnvironment {
        var env = FakeEnvironment()
        env.addApp("io.github.schowave.doorman", name: "Doorman")
        env.addApp("com.apple.Safari", name: "Safari")
        env.addApp("app.zen-browser.zen", name: "Zen", version: zenVersion, executable: "zen")
        env.addApp("com.google.Chrome", name: "Google Chrome")
        env.addApp("com.google.Chrome.beta", name: "Google Chrome Beta")
        env.addApp("org.mozilla.firefox", name: "Firefox")
        env.addApp("com.googlecode.iterm2", name: "iTerm")
        env.addApp("se.johnste.finicky", name: "Finicky")
        env.addApp("com.webcatalog.juli.gmail", name: "Gmail", folder: "/Users/test/Applications/WebCatalog Apps")
        // A test browser in a cache dir, registered before the real Chrome.
        let cached = URL(fileURLWithPath: "/Users/test/.cache/puppeteer/chrome/Google Chrome.app")
        env.extraHandlers = [cached]
        env.extraInfos[cached] = AppInfo(bundleId: "com.google.Chrome", name: "Cached Chrome")

        let zenRoot = "/Users/test/Library/Application Support/zen"
        env.files["\(zenRoot)/profiles.ini"] = Data("[Install1]\nDefault=Profiles/p1\n".utf8)
        env.files["\(zenRoot)/Profiles/p1/zen-sessions.jsonlz4"] = mozLz4(json: sessionJSON)

        let chrome = "/Users/test/Library/Application Support/Google/Chrome/Local State"
        env.files[chrome] = Data(#"{"profile":{"info_cache":{"Default":{"name":"Work"},"Profile 2":{"name":"David"}}}}"#.utf8)
        let beta = "/Users/test/Library/Application Support/Google/Chrome Beta/Local State"
        env.files[beta] = Data(#"{"profile":{"info_cache":{"Default":{"name":"Person 1"}}}}"#.utf8)
        return env
    }

    @Test func discoversInDefaultOrder() {
        let targets = Discovery(environment: environment()).discover()
        #expect(targets.map(\.id) == [
            "zen:{aaaa}", "zen:{bbbb}", "zen:{cccc}",
            "chromium:com.google.Chrome:Default", "chromium:com.google.Chrome:Profile 2",
            "chromium:com.google.Chrome.beta:Default",
            "app:org.mozilla.firefox", "app:com.apple.Safari",
        ])
        #expect(targets.map(\.name) == [
            "Work", "Home", "Bare",
            "Google Chrome › Work", "Google Chrome › David",
            "Google Chrome Beta",
            "Firefox", "Safari",
        ])
    }

    @Test func onlyKnownBrowsersAndExtraApps() {
        let ids = Discovery(environment: environment(), extraApps: ["com.googlecode.iterm2", "com.webcatalog.juli.gmail"])
            .discover().map(\.id)
        #expect(ids.contains("app:com.googlecode.iterm2"))
        #expect(ids.contains("app:com.webcatalog.juli.gmail")) // ~/Applications counts
        #expect(!ids.contains("app:se.johnste.finicky"))
        #expect(!ids.contains { $0.contains("doorman") })
    }

    @Test func ignoresCopiesOutsideApplicationFolders() {
        let chrome = Discovery(environment: environment()).discover().first { $0.id.hasPrefix("chromium:com.google.Chrome:") }
        #expect(chrome?.appURL.path == "/Applications/Google Chrome.app")
    }

    @Test func zenSpaceTargetUsesExecutable() throws {
        let zen = try #require(Discovery(environment: environment()).discover().first)
        guard case .zenSpace(_, let executable, let space) = zen.kind else {
            Issue.record("expected zen space")
            return
        }
        #expect(executable.path == "/Applications/Zen.app/Contents/MacOS/zen")
        #expect(space.uuid == "{aaaa}")
    }

    @Test func oldZenFallsBackToPlainApp() {
        let targets = Discovery(environment: environment(zenVersion: "1.23.9")).discover()
        #expect(targets.first?.id == "app:app.zen-browser.zen")
        #expect(targets.first?.name == "Zen")
    }

    @Test func unreadableSessionFallsBackToPlainApp() {
        var env = environment()
        env.files = env.files.filter { !$0.key.hasSuffix("jsonlz4") }
        #expect(Discovery(environment: env).discover().first?.id == "app:app.zen-browser.zen")
    }

    @Test func profileOverrideWins() {
        var env = environment()
        env.files["/custom/zen-sessions.jsonlz4"] = mozLz4(json: #"{"spaces":[{"uuid":"{x}","name":"X"}]}"#)
        let targets = Discovery(environment: env, zenProfileOverride: URL(fileURLWithPath: "/custom")).discover()
        #expect(targets.first?.id == "zen:{x}")
    }

    @Test func versionComparison() {
        #expect(Discovery.versionAtLeast("1.24.1b", [1, 24]))
        #expect(Discovery.versionAtLeast("1.24", [1, 24]))
        #expect(Discovery.versionAtLeast("2.0", [1, 24]))
        #expect(!Discovery.versionAtLeast("1.23.99", [1, 24]))
        #expect(!Discovery.versionAtLeast(nil, [1, 24]))
    }
}

struct LaunchCommandTests {
    let urls = [URL(string: "https://a.example")!, URL(string: "https://b.example/x?y=1")!]
    let app = URL(fileURLWithPath: "/Applications/X.app")

    @Test func zenRunsOncePerURLWithSpace() {
        let exe = URL(fileURLWithPath: "/Applications/Zen.app/Contents/MacOS/zen")
        let target = Target(id: "zen:{u}", name: "U", kind: .zenSpace(app: app, executable: exe, space: ZenSpace(uuid: "{u}", name: "U")))
        #expect(target.launchCommands(for: urls) == [
            .run(executable: exe, arguments: ["--space", "{u}", "https://a.example"]),
            .run(executable: exe, arguments: ["--space", "{u}", "https://b.example/x?y=1"]),
        ])
    }

    @Test func zenColdStartGoesThroughLaunchServices() {
        let exe = URL(fileURLWithPath: "/Applications/Zen.app/Contents/MacOS/zen")
        let zenApp = URL(fileURLWithPath: "/Applications/Zen.app")
        let target = Target(id: "zen:{u}", name: "U", kind: .zenSpace(app: zenApp, executable: exe, space: ZenSpace(uuid: "{u}", name: "U")))
        #expect(target.launchCommands(for: urls, appIsRunning: false) == [
            .run(executable: URL(fileURLWithPath: "/usr/bin/open"),
                 arguments: ["-a", "/Applications/Zen.app", "--args", "--space", "{u}",
                             "https://a.example", "https://b.example/x?y=1"]),
        ])
    }

    @Test func chromiumUsesProfileDirectory() {
        let target = Target(id: "c", name: "C", kind: .chromium(app: app, profileDirectory: "Profile 2"))
        #expect(target.launchCommands(for: urls) == [
            .run(executable: URL(fileURLWithPath: "/usr/bin/open"),
                 arguments: ["-na", "/Applications/X.app", "--args", "--profile-directory=Profile 2",
                             "https://a.example", "https://b.example/x?y=1"]),
        ])
    }

    @Test func plainAppUsesLaunchServices() {
        let target = Target(id: "a", name: "A", kind: .app(app))
        #expect(target.launchCommands(for: urls) == [.open(urls: urls, app: app)])
    }

    @Test func noURLsNoCommands() {
        #expect(Target(id: "a", name: "A", kind: .app(app)).launchCommands(for: []).isEmpty)
    }
}
