@testable import BrowserdoorCore
import Foundation
import SQLite3
import Testing

/// A typical `profiles.ini`: Firefox's unused `default`, the installation's `default-release`
/// and a profile the user created.
private let profilesIni = """
[Profile2]
Name=Client
IsRelative=1
Path=Profiles/c3.Client

[Profile1]
Name=default-release
IsRelative=1
Path=Profiles/b2.default-release

[Profile0]
Name=default
IsRelative=1
Path=Profiles/a1.default
Default=1

[Install2656FF1E876E9973]
Default=Profiles/b2.default-release
Locked=1

[General]
StartWithLastProfile=1
Version=2
"""

/// A profile group database as Firefox's profile manager writes it.
private func profileStore(_ rows: [(path: String, name: String)]) throws -> Data {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("store.sqlite")

    var db: OpaquePointer?
    try #require(sqlite3_open(file.path, &db) == SQLITE_OK)
    let create = """
    CREATE TABLE Profiles (id INTEGER NOT NULL, path TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
      avatar TEXT NOT NULL, themeId TEXT NOT NULL, themeFg TEXT NOT NULL, themeBg TEXT NOT NULL,
      PRIMARY KEY(id));
    """
    var sql = create
    for (i, row) in rows.enumerated() {
        sql += "INSERT INTO Profiles VALUES (\(i + 1), '\(row.path)', '\(row.name)', 'book', 'default', '', '');"
    }
    try #require(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
    sqlite3_close(db)
    return try Data(contentsOf: file)
}

struct FirefoxProfilesTests {
    @Test func installDefaultFirstAndLegacyDefaultSkipped() {
        let profiles = FirefoxProfiles.parse(profilesIni: profilesIni) { _ in nil }
        #expect(profiles == [
            FirefoxProfile(path: "Profiles/b2.default-release", name: "default-release"),
            FirefoxProfile(path: "Profiles/c3.Client", name: "Client"),
        ])
    }

    @Test func legacyDefaultStaysWhenAnInstallationUsesIt() {
        let ini = "[Profile0]\nName=default\nPath=Profiles/a1.default\n[Install1]\nDefault=Profiles/a1.default\n"
        #expect(FirefoxProfiles.parse(profilesIni: ini) { _ in nil }.map(\.name) == ["default"])
    }

    @Test func absolutePathIsKept() {
        let ini = "[Profile0]\nName=External\nIsRelative=0\nPath=/Volumes/Data/ff\n"
        let profile = FirefoxProfiles.parse(profilesIni: ini) { _ in nil }.first
        #expect(profile?.directory(root: URL(fileURLWithPath: "/root")).path == "/Volumes/Data/ff")
    }

    @Test func profileGroupReplacesItsIniEntry() {
        let ini = "[Profile0]\nName=Original\nPath=Profiles/o.default-release\nStoreID=s1\n[Install1]\nDefault=Profiles/o.default-release\n"
        let profiles = FirefoxProfiles.parse(profilesIni: ini) { id in
            id == "s1" ? [
                FirefoxProfile(path: "Profiles/o.default-release", name: "Original profile"),
                FirefoxProfile(path: "Profiles/w.Work", name: "Work"),
            ] : nil
        }
        #expect(profiles.map(\.name) == ["Original profile", "Work"])
    }

    @Test func unreadableGroupFallsBackToIniEntry() {
        let ini = "[Profile0]\nName=Original\nPath=Profiles/o\nStoreID=s1\n"
        #expect(FirefoxProfiles.parse(profilesIni: ini) { _ in nil }.map(\.name) == ["Original"])
    }

    @Test func readsProfileGroupDatabase() throws {
        let data = try profileStore([("Profiles/o.default-release", "Original profile"), ("Profiles/w.Work", "Work")])
        #expect(FirefoxProfiles.parseStore(database: data, wal: nil) == [
            FirefoxProfile(path: "Profiles/o.default-release", name: "Original profile"),
            FirefoxProfile(path: "Profiles/w.Work", name: "Work"),
        ])
        #expect(FirefoxProfiles.parseStore(database: Data("no database".utf8), wal: nil) == nil)
    }
}

struct FirefoxDiscoveryTests {
    let root = "/Users/test/Library/Application Support/Firefox"

    @Test func eachProfileBecomesATarget() throws {
        var env = sampleEnvironment()
        env.files["\(root)/profiles.ini"] = Data(profilesIni.utf8)
        let targets = Discovery(environment: env).discover()

        let firefox = targets.filter { $0.id.hasPrefix("firefox:") }
        #expect(firefox.map(\.id) == [
            "firefox:org.mozilla.firefox:Profiles/b2.default-release",
            "firefox:org.mozilla.firefox:Profiles/c3.Client",
        ])
        #expect(firefox.map(\.name) == ["Firefox › default-release", "Firefox › Client"])
        #expect(!targets.contains { $0.id == "app:org.mozilla.firefox" })
        // After the Chromium profiles, before the other browsers.
        let ids = targets.map(\.id)
        #expect(try #require(ids.firstIndex(of: "chromium:com.google.Chrome.beta:Default")) < #require(ids.firstIndex(of: firefox[0].id)))
        #expect(try #require(ids.firstIndex(of: firefox[1].id)) < #require(ids.firstIndex(of: "app:com.apple.Safari")))

        guard case let .firefox(app, profile) = firefox[1].kind else {
            Issue.record("expected a Firefox profile")
            return
        }
        #expect(app.path == "/Applications/Firefox.app")
        #expect(profile.path == "\(root)/Profiles/c3.Client")
    }

    @Test func profileGroupComesFromItsDatabase() throws {
        var env = sampleEnvironment()
        env.files["\(root)/profiles.ini"] = Data("[Profile0]\nName=default-release\nPath=Profiles/o\nStoreID=abc\n".utf8)
        env.files["\(root)/Profile Groups/abc.sqlite"] = try profileStore([("Profiles/o", "Me"), ("Profiles/w", "Work")])
        let names = Discovery(environment: env).discover().filter { $0.id.hasPrefix("firefox:") }.map(\.name)
        #expect(names == ["Firefox › Me", "Firefox › Work"])
    }

    @Test func singleProfileStaysPlainApp() {
        var env = sampleEnvironment()
        env.files["\(root)/profiles.ini"] = Data("[Profile0]\nName=default-release\nPath=Profiles/b2\n".utf8)
        let targets = Discovery(environment: env).discover()
        #expect(targets.contains { $0.id == "app:org.mozilla.firefox" && $0.name == "Firefox" })
        #expect(!targets.contains { $0.id.hasPrefix("firefox:") })
    }

    @Test func opensWithProfilePath() throws {
        let app = URL(fileURLWithPath: "/Applications/Firefox.app")
        let target = Target(id: "f", name: "F", kind: .firefox(app: app, profile: URL(fileURLWithPath: "/p/Client")))
        let a = try #require(URL(string: "https://a.example"))
        let b = try #require(URL(string: "https://b.example"))
        #expect(target.launchCommands(for: [a, b]) == [
            .run(executable: URL(fileURLWithPath: "/usr/bin/open"),
                 arguments: ["-na", app.path, "--args", "--profile", "/p/Client", a.absoluteString, b.absoluteString]),
        ])
        #expect(try target.launchCommands(for: [#require(URL(string: "--headless"))]).isEmpty)
    }
}
