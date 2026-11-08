import Foundation

/// Everything opening links needs from the system. The app's adapter uses LaunchServices,
/// `Process` and `NSRunningApplication`; tests record the calls.
public protocol LaunchPort {
    func bundleIdentifier(of app: URL) -> String?
    func isRunning(bundleId: String) -> Bool
    func contents(of file: URL) -> Data?
    /// Starts an executable without waiting for it.
    func run(_ executable: URL, arguments: [String])
    /// Hands URLs to an app via LaunchServices and brings it to the front.
    func open(_ urls: [URL], with app: URL)
    /// Brings a running app to the front.
    func activate(_ app: URL)
}

/// Turns what macOS hands Doorman into links, and opens links in a target.
///
/// Links end up as command-line arguments for browsers, so only `http`, `https` and `file`
/// URLs get through, and `.webloc` files may only point to `http`/`https` (a downloaded
/// `.webloc` must not open a local file with file-origin rights). Both directions check.
public struct LinkOpener {
    public var port: LaunchPort

    public init(port: LaunchPort) {
        self.port = port
    }

    /// Items from an open event (URLs, `.html` files, `.webloc` files) → links to offer.
    public func links(from items: [URL]) -> [URL] {
        items.compactMap { item in
            if item.isFileURL, item.pathExtension.lowercased() == "webloc" {
                guard let link = port.contents(of: item).flatMap(WeblocParser.url(fromWebloc:)),
                      URLPolicy.isAllowedFromWebloc(link) else { return nil }
                return link
            }
            return URLPolicy.isAllowed(item) ? item : nil
        }
    }

    /// Opens `links` in `target`. A running Zen gets the command via its remote service and is
    /// then brought forward; a closed Zen starts through LaunchServices.
    public func open(_ links: [URL], in target: Target) {
        let running = port.bundleIdentifier(of: target.appURL).map(port.isRunning(bundleId:)) ?? false
        let commands = target.launchCommands(for: links, appIsRunning: running)
        for command in commands {
            switch command {
            case let .run(executable, arguments): port.run(executable, arguments: arguments)
            case let .open(urls, app): port.open(urls, with: app)
            }
        }
        // The remote command may leave Zen in the background.
        if running, !commands.isEmpty, case .zenSpace = target.kind {
            port.activate(target.appURL)
        }
    }
}
