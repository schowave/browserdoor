import Foundation

/// One entry the user can pick: a Zen workspace, a Chromium or Firefox profile, or a plain browser.
public struct Target: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// `profile` is set only when the config overrides Zen's default profile;
        /// the command then has to address that profile's instance explicitly.
        /// `version` is Zen's, which its icon cache is keyed by.
        case zenSpace(app: URL, executable: URL, space: ZenSpace, profile: URL? = nil, version: String = "")
        case chromium(app: URL, profileDirectory: String)
        case firefox(app: URL, profile: URL)
        case app(URL)
    }

    /// Stable id used in the config: `zen:{uuid}`, `chromium:<bundleId>:<dir>`,
    /// `firefox:<bundleId>:<profile path>`, `app:<bundleId>`.
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
        case let .zenSpace(app, _, _, _, _), let .chromium(app, _), let .firefox(app, _), let .app(app): app
        }
    }

    /// A browser listed as a single entry.
    static func plain(app: URL, bundleId: String, name: String) -> Target {
        Target(id: TargetID.app(bundleId: bundleId).string, name: name, kind: .app(app))
    }
}

enum LaunchCommand: Equatable, Sendable {
    /// Run an executable directly.
    case run(executable: URL, arguments: [String])
    /// Hand the URLs to an app via LaunchServices.
    case open(urls: [URL], app: URL)
}

extension Target {
    /// - Parameter appIsRunning: whether the target app already runs. Only matters for Zen:
    ///   a running Zen gets the command via its remote service (direct exec returns at once);
    ///   a cold start goes through LaunchServices so Zen isn't a child of this process.
    ///   URLs that `URLPolicy` rejects are dropped: they would become command-line flags.
    func launchCommands(for urls: [URL], appIsRunning: Bool = true) -> [LaunchCommand] {
        let urls = URLPolicy.filter(urls)
        guard !urls.isEmpty else { return [] }
        switch kind {
        case let .zenSpace(app, executable, space, profile, _):
            return ZenBrowser.launchCommands(app: app, executable: executable, space: space, profile: profile,
                                             urls: urls, appIsRunning: appIsRunning)
        case let .chromium(app, dir):
            return ChromiumFamily.launchCommands(app: app, profileDirectory: dir, urls: urls)
        case let .firefox(app, profile):
            return FirefoxFamily.launchCommands(app: app, profile: profile, urls: urls)
        case let .app(app):
            return [.open(urls: urls, app: app)]
        }
    }

    /// The app has to be brought forward after its remote command (Zen's leaves it behind).
    var activatesAfterRemoteCommand: Bool {
        if case .zenSpace = kind {
            return true
        }
        return false
    }
}
