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

/// Chromium browsers: one target per profile, opened with `--profile-directory`.
struct ChromiumFamily: BrowserFamily {
    var bundleIds: [String] {
        ChromiumBrowser.known.map(\.bundleId)
    }

    /// Profiles from `Local State`. A single profile keeps its `chromium:` ID but shows only the
    /// app name; an unreadable `Local State` gives one plain entry.
    func targets(app: URL, bundleId: String, discovery: Discovery) -> [Target] {
        let environment = discovery.environment
        let appName = discovery.appName(app, fallback: bundleId)
        guard let browser = ChromiumBrowser.known.first(where: { $0.bundleId == bundleId }) else { return [] }
        let profiles = environment.contents(of: browser.localStateURL(home: environment.home))
            .flatMap { try? ChromiumProfiles.parse(localState: $0) } ?? []

        guard !profiles.isEmpty else {
            return [Target.plain(app: app, bundleId: bundleId, name: appName)]
        }
        return profiles.map { profile in
            Target(
                id: TargetID.chromium(bundleId: bundleId, profileDirectory: profile.directory).string,
                name: profiles.count == 1 ? appName : "\(appName) › \(profile.name)",
                kind: .chromium(app: app, profileDirectory: profile.directory)
            )
        }
    }
}

/// A Chromium profile, opened with `--profile-directory`.
struct ChromiumProfileKind: TargetKind {
    var app: URL
    var profileDirectory: String

    func launchCommands(for urls: [URL], appIsRunning _: Bool) -> [LaunchCommand] {
        [.run(
            executable: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: ["-na", app.path, "--args", "--profile-directory=\(profileDirectory)"] + urls.map(\.absoluteString)
        )]
    }
}

extension TargetKind where Self == ChromiumProfileKind {
    static func chromium(app: URL, profileDirectory: String) -> ChromiumProfileKind {
        ChromiumProfileKind(app: app, profileDirectory: profileDirectory)
    }
}
