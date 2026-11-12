import Foundation

/// One entry the user can pick: a Zen workspace, a Chromium or Firefox profile, or a plain browser.
public struct Target: Equatable, Sendable, Identifiable {
    /// Stable id used in the config: `zen:{uuid}`, `chromium:<bundleId>:<dir>`,
    /// `firefox:<bundleId>:<profile path>`, `app:<bundleId>`.
    public var id: String
    public var name: String
    /// How the target opens; its browser family decides.
    var kind: any TargetKind

    init(id: String, name: String, kind: some TargetKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    public var appURL: URL {
        kind.app
    }

    /// A browser listed as a single entry.
    static func plain(app: URL, bundleId: String, name: String) -> Target {
        Target(id: TargetID.app(bundleId: bundleId).string, name: name, kind: .app(app))
    }

    public static func == (lhs: Target, rhs: Target) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.kind.isSame(as: rhs.kind)
    }
}

/// How one target opens, owned by its browser family (`ZenSpaceKind`, `ChromiumProfileKind`,
/// `FirefoxProfileKind`, or `AppKind` for a plain browser). Adding a family means adding one of
/// these next to its discovery; opening links needs nothing else. (Icons are the app's, except
/// for Zen spaces, which `TargetIcons` knows.)
protocol TargetKind: Equatable, Sendable {
    /// The app the target belongs to.
    var app: URL { get }
    /// Commands that open `urls` (already filtered by `URLPolicy`, never empty).
    /// - Parameter appIsRunning: whether `app` runs right now.
    func launchCommands(for urls: [URL], appIsRunning: Bool) -> [LaunchCommand]
    /// The app has to be brought forward after a command to the running app.
    var activatesAfterRemoteCommand: Bool { get }
}

extension TargetKind {
    var activatesAfterRemoteCommand: Bool {
        false
    }

    func isSame(as other: any TargetKind) -> Bool {
        (other as? Self) == self
    }
}

/// A plain browser or app: links go to it through LaunchServices.
struct AppKind: TargetKind {
    var app: URL

    func launchCommands(for urls: [URL], appIsRunning _: Bool) -> [LaunchCommand] {
        [.open(urls: urls, app: app)]
    }
}

extension TargetKind where Self == AppKind {
    static func app(_ app: URL) -> AppKind {
        AppKind(app: app)
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
        return kind.launchCommands(for: urls, appIsRunning: appIsRunning)
    }

    var activatesAfterRemoteCommand: Bool {
        kind.activatesAfterRemoteCommand
    }
}
