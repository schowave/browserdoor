import Foundation

/// One entry the user can pick: a Zen workspace, a Chromium profile, or a plain browser.
public struct Target: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case zenSpace(app: URL, executable: URL, space: ZenSpace)
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
        case .zenSpace(let app, _, _), .chromium(let app, _), .app(let app): app
        }
    }

    public static func zenID(_ uuid: String) -> String { "zen:\(uuid)" }
    public static func chromiumID(_ bundleId: String, _ dir: String) -> String { "chromium:\(bundleId):\(dir)" }
    public static func appID(_ bundleId: String) -> String { "app:\(bundleId)" }
}

public enum LaunchCommand: Equatable, Sendable {
    /// Run an executable directly.
    case run(executable: URL, arguments: [String])
    /// Hand the URLs to an app via LaunchServices.
    case open(urls: [URL], app: URL)
}

extension Target {
    /// - Parameter appIsRunning: whether the target app already runs. Only matters for Zen:
    ///   a running Zen gets the command via its remote service (direct exec returns at once);
    ///   a cold start goes through LaunchServices so Zen isn't a child of this process.
    public func launchCommands(for urls: [URL], appIsRunning: Bool = true) -> [LaunchCommand] {
        guard !urls.isEmpty else { return [] }
        let strings = urls.map(\.absoluteString)
        switch kind {
        case .zenSpace(let app, let executable, let space):
            guard appIsRunning else {
                // Zen stores the space for startup; extra URLs open in the same window.
                return [.run(
                    executable: URL(fileURLWithPath: "/usr/bin/open"),
                    arguments: ["-a", app.path, "--args", "--space", space.uuid] + strings
                )]
            }
            // `--space <space> [<url>]` takes a single URL, so one call per URL.
            return strings.map { .run(executable: executable, arguments: ["--space", space.uuid, $0]) }
        case .chromium(let app, let dir):
            return [.run(
                executable: URL(fileURLWithPath: "/usr/bin/open"),
                arguments: ["-na", app.path, "--args", "--profile-directory=\(dir)"] + strings
            )]
        case .app(let app):
            return [.open(urls: urls, app: app)]
        }
    }
}
