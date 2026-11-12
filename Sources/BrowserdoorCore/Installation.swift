import Foundation

/// Where a Homebrew-installed app lives. Homebrew installs into a versioned Cellar directory
/// that `brew cleanup` deletes after an upgrade; `<prefix>/opt/<formula>` always points at the
/// current version.
public struct HomebrewInstall: Equatable, Sendable {
    /// e.g. `/opt/homebrew`
    public var prefix: URL
    public var formula: String
    /// e.g. `/opt/homebrew/opt/browserdoor/Browserdoor.app`
    public var optApp: URL

    public var brew: URL {
        prefix.appendingPathComponent("bin/brew")
    }

    public var bin: URL {
        prefix.appendingPathComponent("bin")
    }

    /// A `.command` script for Terminal: upgrade the formula, quit the running app by its PID (a
    /// dev build with the same executable name keeps running), start the new version.
    public func upgradeScript(runningPID pid: Int32) -> String {
        let brew = Shell.quote(brew.path)
        let start = Shell.quote(bin.appendingPathComponent(formula).path)
        return """
        #!/bin/sh
        echo "Updating Browserdoor…"
        \(brew) update --quiet && \(brew) upgrade \(formula) || { echo; echo "Update failed."; exit 1; }
        kill \(pid) 2>/dev/null
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        \(start)
        echo; echo "Browserdoor updated and restarted. You can close this window."

        """
    }

    /// `/opt/homebrew/Cellar/browserdoor/0.1.0/Browserdoor.app` → prefix `/opt/homebrew`, formula `browserdoor`.
    /// Nil if the bundle is not inside a Cellar.
    public static func detect(bundlePath: String) -> HomebrewInstall? {
        let parts = bundlePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard
            let cellar = parts.lastIndex(of: "Cellar"),
            parts.count > cellar + 3,
            let last = parts.last, last.hasSuffix(".app")
        else { return nil }
        let prefix = parts[..<cellar].joined(separator: "/")
        let formula = parts[cellar + 1]
        let inside = parts[(cellar + 3)...].joined(separator: "/") // skip the version directory
        return HomebrewInstall(
            prefix: URL(fileURLWithPath: prefix, isDirectory: true),
            formula: formula,
            optApp: URL(fileURLWithPath: "\(prefix)/opt/\(formula)/\(inside)")
        )
    }

    /// Whether `path` is one of this formula's own app paths (any Cellar version or opt).
    func owns(_ path: String) -> Bool {
        let app = optApp.lastPathComponent
        return path.hasSuffix("/\(app)")
            && (path.contains("/Cellar/\(formula)/") || path.hasSuffix("/opt/\(formula)/\(app)"))
    }
}

/// Keeps Browserdoor reachable under a path that survives `brew upgrade`, and manages the login item
/// (a LaunchAgent running `open -a <app>`) on top of that path.
///
/// - For a Homebrew install, `~/Applications/<App>.app` is a symlink to the `opt` path. Browserdoor
///   only creates or replaces its *own* links; a real app or someone else's link stays untouched.
/// - The login item is only repointed when the app it starts is gone, so a second copy never
///   takes it over. What earlier versions left behind is handled in `Legacy`.
public struct Installation {
    public var home: URL
    public var bundleURL: URL
    public var label: String

    public init(home: URL, bundleURL: URL, label: String) {
        self.home = home
        self.bundleURL = bundleURL
        self.label = label
    }

    private var fm: FileManager {
        .default
    }

    public var homebrew: HomebrewInstall? {
        HomebrewInstall.detect(bundlePath: bundleURL.path)
    }

    /// `~/Applications/<App>.app`
    public var linkURL: URL {
        home.appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent(bundleURL.lastPathComponent, isDirectory: true)
    }

    public var agentURL: URL {
        home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    /// What the login item should start. No side effects; `prepare()` creates the link.
    public var stableAppURL: URL {
        guard let homebrew else { return bundleURL }
        if (try? fm.destinationOfSymbolicLink(atPath: linkURL.path)) == homebrew.optApp.path {
            return linkURL
        }
        return homebrew.optApp
    }

    /// The LaunchServices registration an update left behind: the bundle Browserdoor ran from last
    /// time, if that was elsewhere and is gone now (e.g. a Cellar version `brew cleanup` removed).
    /// A previous copy that still exists, such as a dev build, is not stale.
    public func staleRegistration(previousBundlePath: String?) -> URL? {
        guard let previous = previousBundlePath, !previous.isEmpty,
              previous != bundleURL.path, !fm.fileExists(atPath: previous)
        else { return nil }
        return URL(fileURLWithPath: previous)
    }

    public var launchesAtLogin: Bool {
        fm.fileExists(atPath: agentURL.path)
    }

    /// Run at every launch (`Startup` does): maintain the link, repoint an agent whose app
    /// disappeared.
    public func prepare() {
        ensureLink()
        if launchesAtLogin, agentTargetIsGone() {
            try? setLaunchAtLogin(true)
        }
    }

    public func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", "-a", stableAppURL.path],
                "RunAtLoad": true,
                "LimitLoadToSessionType": "Aqua",
                "ProcessType": "Interactive",
            ]
            try fm.createDirectory(at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: agentURL, options: .atomic)
        } else if launchesAtLogin {
            try fm.removeItem(at: agentURL)
        }
    }

    // MARK: Internals

    private func ensureLink() {
        guard let homebrew, fm.fileExists(atPath: homebrew.optApp.path) else { return }
        if let destination = try? fm.destinationOfSymbolicLink(atPath: linkURL.path) {
            guard destination != homebrew.optApp.path, homebrew.owns(destination) else { return }
            try? fm.removeItem(at: linkURL) // our own stale link
        } else if fm.fileExists(atPath: linkURL.path) {
            return // a real app is there
        }
        try? fm.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.createSymbolicLink(atPath: linkURL.path, withDestinationPath: homebrew.optApp.path)
    }

    private func agentTargetIsGone() -> Bool {
        guard
            let data = try? Data(contentsOf: agentURL),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let args = dict["ProgramArguments"] as? [String],
            args.count == 3, args[0] == "/usr/bin/open", args[1] == "-a"
        else { return true } // broken or foreign plist: rewrite
        return args[2] != stableAppURL.path && !fm.fileExists(atPath: args[2])
    }
}
