import Foundation

/// Zen: one target per space, opened with `zen --space` (Zen 1.24 or later).
struct ZenBrowser: BrowserFamily {
    static let bundleId = "app.zen-browser.zen"
    /// First Zen version shipping `--space` (zen-browser/desktop#15074).
    static let minimumSpaceVersion = [1, 24]

    var bundleIds: [String] {
        [Self.bundleId]
    }

    /// Spaces from the session file of the configured or default profile. Older Zen, an
    /// unreadable session or no spaces: one plain entry.
    func targets(app: URL, bundleId: String, discovery: Discovery) -> [Target] {
        let environment = discovery.environment
        let info = environment.appInfo(at: app)
        let plain = [Target.plain(app: app, bundleId: bundleId, name: info?.name ?? "Zen")]

        guard
            let info, Discovery.versionAtLeast(info.version, Self.minimumSpaceVersion),
            let executableName = info.executableName,
            let profile = discovery.zenProfileOverride ?? Self.defaultProfile(environment),
            let data = environment.contents(of: profile.appendingPathComponent(ZenSpaces.sessionFileName)),
            let json = try? MozLz4.decompress(data),
            let spaces = try? ZenSpaces.parse(sessionJSON: json),
            !spaces.isEmpty
        else { return plain }

        let executable = app.appendingPathComponent("Contents/MacOS").appendingPathComponent(executableName)
        return spaces.map { space in
            Target(
                id: TargetID.zen(uuid: space.uuid).string,
                name: space.name,
                kind: .zenSpace(app: app, executable: executable, space: space,
                                profile: discovery.zenProfileOverride, version: info.version ?? "")
            )
        }
    }

    static func defaultProfile(_ environment: BrowserEnvironment) -> URL? {
        let root = ZenProfile.defaultRoot(home: environment.home)
        guard
            let data = environment.contents(of: root.appendingPathComponent("profiles.ini")),
            let text = String(data: data, encoding: .utf8)
        else { return nil }
        return ZenProfile.defaultProfile(profilesIni: text, root: root)
    }
}

/// A Zen space. `profile` is set only when the config overrides Zen's default profile; the
/// command then has to address that profile's instance explicitly. `version` is Zen's, which its
/// icon cache is keyed by.
struct ZenSpaceKind: TargetKind {
    var app: URL
    var executable: URL
    var space: ZenSpace
    var profile: URL?
    var version: String

    /// A running Zen gets the command via its remote service (direct exec returns at once); a
    /// cold start goes through LaunchServices so Zen isn't a child of Browserdoor.
    func launchCommands(for urls: [URL], appIsRunning: Bool) -> [LaunchCommand] {
        let strings = urls.map(\.absoluteString)
        let base = (profile.map { ["--profile", $0.path] } ?? []) + ["--space", space.uuid]
        guard appIsRunning else {
            // Zen stores the space for startup; extra URLs open in the same window.
            return [.run(executable: URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-a", app.path, "--args"] + base + strings)]
        }
        // `--space <space> [<url>]` takes a single URL, so one call per URL.
        return strings.map { .run(executable: executable, arguments: base + [$0]) }
    }

    /// The remote command may leave Zen in the background.
    var activatesAfterRemoteCommand: Bool {
        true
    }
}

extension TargetKind where Self == ZenSpaceKind {
    static func zenSpace(app: URL, executable: URL, space: ZenSpace, profile: URL? = nil, version: String = "") -> ZenSpaceKind {
        ZenSpaceKind(app: app, executable: executable, space: space, profile: profile, version: version)
    }
}
