import Foundation

/// One entry the user can pick: a Zen workspace, a Chromium profile, or a plain browser.
public struct Target: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// `profile` is set only when the config overrides Zen's default profile;
        /// the command then has to address that profile's instance explicitly.
        case zenSpace(app: URL, executable: URL, space: ZenSpace, profile: URL? = nil)
        case chromium(app: URL, profileDirectory: String)
        case app(URL)
    }

    /// Stable id used in the config: `zen:{uuid}`, `chromium:<bundleId>:<dir>`, `app:<bundleId>`.
    public var id: String
    public var name: String
    public var kind: Kind

    public init(id: String, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    public var appURL: URL {
        switch kind {
        case let .zenSpace(app, _, _, _), let .chromium(app, _), let .app(app): app
        }
    }

    public static func zenID(_ uuid: String) -> String {
        "zen:\(uuid)"
    }

    public static func chromiumID(_ bundleId: String, _ dir: String) -> String {
        "chromium:\(bundleId):\(dir)"
    }

    public static func appID(_ bundleId: String) -> String {
        "app:\(bundleId)"
    }
}

public enum LaunchCommand: Equatable, Sendable {
    /// Run an executable directly.
    case run(executable: URL, arguments: [String])
    /// Hand the URLs to an app via LaunchServices.
    case open(urls: [URL], app: URL)
}

public extension Target {
    /// - Parameter appIsRunning: whether the target app already runs. Only matters for Zen:
    ///   a running Zen gets the command via its remote service (direct exec returns at once);
    ///   a cold start goes through LaunchServices so Zen isn't a child of this process.
    ///   URLs that `URLPolicy` rejects are dropped: they would become command-line flags.
    func launchCommands(for urls: [URL], appIsRunning: Bool = true) -> [LaunchCommand] {
        let urls = URLPolicy.filter(urls)
        guard !urls.isEmpty else { return [] }
        let strings = urls.map(\.absoluteString)
        switch kind {
        case let .zenSpace(app, executable, space, profile):
            let base = (profile.map { ["--profile", $0.path] } ?? []) + ["--space", space.uuid]
            guard appIsRunning else {
                // Zen stores the space for startup; extra URLs open in the same window.
                return [.run(
                    executable: URL(fileURLWithPath: "/usr/bin/open"),
                    arguments: ["-a", app.path, "--args"] + base + strings
                )]
            }
            // `--space <space> [<url>]` takes a single URL, so one call per URL.
            return strings.map { .run(executable: executable, arguments: base + [$0]) }
        case let .chromium(app, dir):
            return [.run(
                executable: URL(fileURLWithPath: "/usr/bin/open"),
                arguments: ["-na", app.path, "--args", "--profile-directory=\(dir)"] + strings
            )]
        case let .app(app):
            return [.open(urls: urls, app: app)]
        }
    }
}
