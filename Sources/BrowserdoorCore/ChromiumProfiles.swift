import Foundation

public struct ChromiumBrowser: Equatable, Sendable {
    public var bundleId: String
    /// Path relative to `~/Library/Application Support`.
    public var dataDirectory: String

    public static let known: [ChromiumBrowser] = [
        .init(bundleId: "com.google.Chrome", dataDirectory: "Google/Chrome"),
        .init(bundleId: "com.google.Chrome.beta", dataDirectory: "Google/Chrome Beta"),
        .init(bundleId: "com.google.Chrome.canary", dataDirectory: "Google/Chrome Canary"),
        .init(bundleId: "com.brave.Browser", dataDirectory: "BraveSoftware/Brave-Browser"),
        .init(bundleId: "com.microsoft.edgemac", dataDirectory: "Microsoft Edge"),
        .init(bundleId: "com.vivaldi.Vivaldi", dataDirectory: "Vivaldi"),
        .init(bundleId: "org.chromium.Chromium", dataDirectory: "Chromium"),
    ]

    public func localStateURL(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support")
            .appendingPathComponent(dataDirectory)
            .appendingPathComponent("Local State")
    }
}

public struct ChromiumProfile: Equatable, Sendable {
    /// Directory name, e.g. `Default` or `Profile 2` — the value for `--profile-directory`.
    public var directory: String
    public var name: String

    public init(directory: String, name: String) {
        self.directory = directory
        self.name = name
    }
}

public enum ChromiumProfiles {
    /// Parses `Local State`. Order follows `profile.profiles_order` when present,
    /// otherwise the profile directory names sorted naturally.
    public static func parse(localState: Data) throws -> [ChromiumProfile] {
        let state = try JSONDecoder().decode(LocalState.self, from: localState)
        guard let cache = state.profile?.info_cache else { return [] }

        let order = state.profile?.profiles_order ?? []
        let ordered = order.filter { cache[$0] != nil }
        let rest = cache.keys
            .filter { !order.contains($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        return (ordered + rest).map { dir in
            let name = cache[dir]?.name ?? ""
            return ChromiumProfile(directory: dir, name: name.isEmpty ? dir : name)
        }
    }

    private struct LocalState: Decodable {
        var profile: Profile?
    }

    private struct Profile: Decodable {
        var info_cache: [String: Info]?
        var profiles_order: [String]?
    }

    private struct Info: Decodable {
        var name: String?
    }
}
