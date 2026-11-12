@testable import BrowserdoorCore
import Foundation
import Testing

struct DiscoveryTests {
    func environment(zenVersion: String = "1.24.1b") -> FakeEnvironment {
        sampleEnvironment(zenVersion: zenVersion)
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
        #expect(!ids.contains { $0.contains("browserdoor") })
    }

    @Test func extraAppWithoutHttpsHandlerStillAppears() {
        var env = environment()
        let url = URL(fileURLWithPath: "/Applications/Notes Tool.app")
        env.nonBrowserApps["com.example.notes"] = (url, AppInfo(bundleId: "com.example.notes", name: "Notes Tool"))
        #expect(!Discovery(environment: env).discover().contains { $0.id == "app:com.example.notes" })
        let targets = Discovery(environment: env, extraApps: ["com.example.notes"]).discover()
        #expect(targets.first { $0.id == "app:com.example.notes" }?.appURL == url)
    }

    @Test func ignoresCopiesOutsideApplicationFolders() {
        let chrome = Discovery(environment: environment()).discover().first { $0.id.hasPrefix("chromium:com.google.Chrome:") }
        #expect(chrome?.appURL.path == "/Applications/Google Chrome.app")
    }

    @Test func zenSpaceTargetUsesExecutable() throws {
        let zen = try #require(Discovery(environment: environment()).discover().first)
        let kind = try #require(zen.kind as? ZenSpaceKind)
        #expect(kind.executable.path == "/Applications/Zen.app/Contents/MacOS/zen")
        #expect(kind.space.uuid == "{aaaa}")
        #expect(kind.profile == nil)
        #expect(kind.version == "1.24.1b")
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

    @Test func profileOverrideWins() throws {
        var env = environment()
        env.files["/custom/zen-sessions.jsonlz4"] = mozLz4(json: #"{"spaces":[{"uuid":"{x}","name":"X"}]}"#)
        let targets = Discovery(environment: env, zenProfileOverride: URL(fileURLWithPath: "/custom")).discover()
        #expect(targets.first?.id == "zen:{x}")
        let kind = try #require(targets.first?.kind as? ZenSpaceKind)
        #expect(kind.profile?.path == "/custom")
    }

    @Test func duplicateSpaceIDsAreDropped() {
        var env = environment()
        let zenRoot = "/Users/test/Library/Application Support/zen"
        env.files["\(zenRoot)/Profiles/p1/zen-sessions.jsonlz4"] =
            mozLz4(json: #"{"spaces":[{"uuid":"{d}","name":"A"},{"uuid":"{d}","name":"B"}]}"#)
        let targets = Discovery(environment: env).discover()
        #expect(targets.filter { $0.id == "zen:{d}" }.map(\.name) == ["A"])
        #expect(Set(targets.map(\.id)).count == targets.count)
        #expect(!CatalogState(base: Config(), targets: targets + targets, configIsUnreadable: false).pickerEntries.isEmpty) // must not trap
    }

    @Test func dataVolumePathsAreNotSystem() {
        let discovery = Discovery(environment: FakeEnvironment())
        #expect(discovery.isInApplicationFolder(URL(fileURLWithPath: "/System/Applications/Safari.app")))
        #expect(discovery.isInApplicationFolder(URL(fileURLWithPath: "/Users/test/Applications/X.app")))
        #expect(!discovery.isInApplicationFolder(URL(fileURLWithPath: "/System/Volumes/Data/Users/test/Library/Caches/x/Chrome.app")))
        #expect(!discovery.isInApplicationFolder(URL(fileURLWithPath: "/Users/test/.cache/Chrome.app")))
    }

    @Test func versionComparison() {
        #expect(Discovery.versionAtLeast("1.24.1b", [1, 24]))
        #expect(Discovery.versionAtLeast("1.24", [1, 24]))
        #expect(Discovery.versionAtLeast("2.0", [1, 24]))
        #expect(!Discovery.versionAtLeast("1.23.99", [1, 24]))
        #expect(!Discovery.versionAtLeast(nil, [1, 24]))
    }

    @Test func everyFamilyBrowserIsAKnownBrowser() {
        for family in Discovery.families {
            for id in family.bundleIds {
                #expect(KnownBrowsers.bundleIds.contains(id), "\(id) is missing from KnownBrowsers")
            }
        }
    }
}

struct TargetIDTests {
    @Test func roundTripsEveryForm() {
        let ids: [TargetID] = [
            .zen(uuid: "{b4ac0402-9e47}"),
            .chromium(bundleId: "com.google.Chrome", profileDirectory: "Profile 2"),
            .firefox(bundleId: "org.mozilla.firefox", profilePath: "Profiles/x1.default-release"),
            .firefox(bundleId: "org.mozilla.firefox", profilePath: "/Volumes/a:b/ff"),
            .app(bundleId: "com.apple.Safari"),
        ]
        for id in ids {
            #expect(TargetID(id.string) == id)
        }
        #expect(TargetID.app(bundleId: "com.apple.Safari").string == "app:com.apple.Safari")
    }

    @Test func rejectsAnythingElse() {
        for string in ["", "app:", "zen", "chromium:com.google.Chrome", "firefox::x", "safari:x", "app"] {
            #expect(TargetID(string) == nil, "\(string)")
        }
    }
}
