import Foundation

/// Where a Homebrew-installed app lives. Homebrew installs into a versioned Cellar directory
/// that `brew cleanup` deletes after an upgrade; `<prefix>/opt/<formula>` always points at the
/// current version.
public struct HomebrewInstall: Equatable, Sendable {
    /// e.g. `/opt/homebrew`
    public var prefix: URL
    public var formula: String
    /// e.g. `/opt/homebrew/opt/doorman/Doorman.app`
    public var optApp: URL

    public var brew: URL {
        prefix.appendingPathComponent("bin/brew")
    }

    public var bin: URL {
        prefix.appendingPathComponent("bin")
    }

    /// `/opt/homebrew/Cellar/doorman/0.1.0/Doorman.app` → prefix `/opt/homebrew`, formula `doorman`.
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

/// The login item Doorman used before (`SMAppService.mainApp`), which remembers the versioned
/// Cellar path. Only here to migrate away from it.
public protocol LegacyLoginItem {
    var isEnabled: Bool { get }
    func unregister()
}

/// Keeps Doorman reachable under a path that survives `brew upgrade`, and manages the login item
/// (a LaunchAgent running `open -a <app>`) on top of that path.
///
/// - For a Homebrew install, `~/Applications/<App>.app` is a symlink to the `opt` path. Doorman
///   only creates or replaces its *own* links; a real app or someone else's link stays untouched.
/// - The login item is only repointed when the app it starts is gone, so a second copy (e.g. a
///   dev build) never takes it over.
public struct Installation {
    public var home: URL
    public var bundleURL: URL
    public var label: String
    public var legacyLoginItem: LegacyLoginItem?

    public init(home: URL, bundleURL: URL, label: String, legacyLoginItem: LegacyLoginItem? = nil) {
        self.home = home
        self.bundleURL = bundleURL
        self.label = label
        self.legacyLoginItem = legacyLoginItem
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

    public var launchesAtLogin: Bool {
        fm.fileExists(atPath: agentURL.path)
    }

    /// Run at every launch: maintain the link, migrate the legacy login item, repoint an agent
    /// whose app disappeared.
    public func prepare() {
        ensureLink()
        if let legacy = legacyLoginItem, legacy.isEnabled {
            legacy.unregister()
            if !launchesAtLogin {
                try? setLaunchAtLogin(true)
            }
        }
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
