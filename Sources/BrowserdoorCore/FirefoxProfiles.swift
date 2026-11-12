import Foundation
import SQLite3

/// A Firefox-family browser whose profiles become targets of their own.
public struct FirefoxBrowser: Equatable, Sendable {
    public var bundleId: String
    /// Path relative to `~/Library/Application Support`.
    public var dataDirectory: String

    /// Firefox Developer Edition and Nightly share Firefox's data directory, so only release
    /// Firefox lists the profiles; the other channels stay single entries.
    public static let known: [FirefoxBrowser] = [
        .init(bundleId: "org.mozilla.firefox", dataDirectory: "Firefox"),
    ]

    public func root(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(dataDirectory, isDirectory: true)
    }
}

public struct FirefoxProfile: Equatable, Sendable {
    /// As Firefox stores it: relative to the data directory (`Profiles/x1y2.default-release`)
    /// or absolute.
    public var path: String
    public var name: String

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }

    public func directory(root: URL) -> URL {
        path.hasPrefix("/")
            ? URL(fileURLWithPath: path, isDirectory: true)
            : root.appendingPathComponent(path, isDirectory: true)
    }
}

public enum FirefoxProfiles {
    public static let groupsDirectory = "Profile Groups"

    /// Profiles from `profiles.ini`: the one an installation opens by default first, then the
    /// others in section order.
    ///
    /// Since Firefox 138 the profile manager keeps a group of profiles in
    /// `Profile Groups/<StoreID>.sqlite`; only one of them appears in `profiles.ini`, marked
    /// with `StoreID`. `store` returns that group's profiles, which take its place (nil keeps
    /// the entry from the ini). The empty `default` profile Firefox creates next to
    /// `default-release` is left out unless an installation uses it.
    public static func parse(profilesIni: String, store: (String) -> [FirefoxProfile]?) -> [FirefoxProfile] {
        let sections = INI.parse(profilesIni)
        let installDefaults = Set(sections.filter { $0.name.hasPrefix("Install") }.compactMap { $0.values["Default"] })

        let entries = sections
            .compactMap { section -> (number: Int, values: [String: String])? in
                guard section.name.hasPrefix("Profile"), section.values["Path"] != nil,
                      let number = Int(section.name.dropFirst("Profile".count)) else { return nil }
                return (number, section.values)
            }
            .sorted { $0.number < $1.number }
            .map(\.values)

        var result: [FirefoxProfile] = []
        for values in entries {
            guard let path = values["Path"] else { continue }
            let isLegacyDefault = values["Name"] == "default" && !installDefaults.contains(path)
            if let storeID = values["StoreID"], let group = store(storeID), !group.isEmpty {
                result += group
            } else if !isLegacyDefault {
                result.append(FirefoxProfile(path: path, name: values["Name"] ?? path))
            }
        }

        var seen = Set<String>()
        let unique = result.filter { seen.insert($0.path).inserted }
        let preferred = unique.filter { installDefaults.contains($0.path) }
        return preferred + unique.filter { !installDefaults.contains($0.path) }
    }

    /// Profiles in a profile group database (table `Profiles`: `id`, `path`, `name`, …), by id.
    /// Firefox keeps the database in WAL mode, so recent changes may only be in `wal`.
    public static func parseStore(database: Data, wal: Data?) -> [FirefoxProfile]? {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("browserdoor-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dir) }
        let file = dir.appendingPathComponent("store.sqlite")
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try database.write(to: file)
            try wal?.write(to: dir.appendingPathComponent("store.sqlite-wal"))
        } catch {
            return nil
        }

        // Read-write on the private copy, so SQLite can apply the WAL.
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return nil }

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT path, name FROM Profiles ORDER BY id", -1, &statement, nil) == SQLITE_OK
        else { return nil }

        var profiles: [FirefoxProfile] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let path = sqlite3_column_text(statement, 0), let name = sqlite3_column_text(statement, 1) else { continue }
            profiles.append(FirefoxProfile(path: String(cString: path), name: String(cString: name)))
        }
        return profiles
    }
}
