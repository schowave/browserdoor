import Foundation

/// Where Doorman lives, and a path to it that survives `brew upgrade`.
///
/// Homebrew installs into a versioned Cellar directory that `brew cleanup` deletes after an
/// upgrade; `<prefix>/opt/<name>` always points at the current version.
public enum InstallLocation {
    /// `/opt/homebrew/Cellar/doorman/0.1.0/Doorman.app` → `/opt/homebrew/opt/doorman/Doorman.app`.
    /// Nil if the bundle is not inside a Homebrew Cellar.
    public static func homebrewOptPath(forBundlePath path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard
            let cellar = parts.lastIndex(of: "Cellar"),
            parts.count > cellar + 3,
            let last = parts.last, last.hasSuffix(".app")
        else { return nil }
        let prefix = parts[..<cellar]
        let formula = parts[cellar + 1]
        let inside = parts[(cellar + 3)...] // skip the version directory
        return (prefix + ["opt", formula] + inside).joined(separator: "/")
    }

    public enum LinkDecision: Equatable, Sendable {
        /// The link already points at the opt path.
        case keep
        case create
        /// One of Doorman's own Homebrew links pointing elsewhere (e.g. an old Cellar version).
        case replace
        /// A real app, or somebody else's link: never touch it.
        case leaveAlone
    }

    /// What to do with `~/Applications/<App>.app`.
    /// - Parameters:
    ///   - linkDestination: the symlink's target if the path is a symlink, else nil.
    ///   - pathExists: whether anything (file, folder, link) exists at the path.
    public static func linkDecision(linkDestination: String?, pathExists: Bool, optPath: String) -> LinkDecision {
        if let destination = linkDestination {
            if destination == optPath {
                return .keep
            }
            return isOwnHomebrewPath(destination, optPath: optPath) ? .replace : .leaveAlone
        }
        return pathExists ? .leaveAlone : .create
    }

    /// `…/Cellar/<formula>/<version>/<App>.app` or `…/opt/<formula>/<App>.app` of the same formula.
    static func isOwnHomebrewPath(_ path: String, optPath: String) -> Bool {
        let parts = optPath.split(separator: "/").map(String.init)
        guard parts.count >= 3, let app = parts.last else { return false }
        let formula = parts[parts.count - 2]
        return path.hasSuffix("/\(app)")
            && (path.contains("/Cellar/\(formula)/") || path.hasSuffix("/opt/\(formula)/\(app)"))
    }

    /// `~/Applications/<App>.app`, the stable link Doorman maintains for Homebrew installs.
    public static func userApplicationsLink(home: URL, appName: String) -> URL {
        home.appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("\(appName).app", isDirectory: true)
    }
}

/// A per-user LaunchAgent that starts Doorman at login through LaunchServices.
/// Unlike `SMAppService.mainApp`, it refers to a path, so pointing it at the stable link
/// keeps it working across upgrades.
public enum LoginAgent {
    public static func fileURL(home: URL, label: String) -> URL {
        home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public static func plist(label: String, appPath: String) throws -> Data {
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-a", appPath],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
        ]
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    /// The app an existing agent starts, if it is one of ours.
    public static func appPath(in existing: Data) -> String? {
        guard
            let dict = try? PropertyListSerialization.propertyList(from: existing, format: nil) as? [String: Any],
            let args = dict["ProgramArguments"] as? [String],
            args.count == 3, args[0] == "/usr/bin/open", args[1] == "-a"
        else { return nil }
        return args[2]
    }

    /// Whether to point an existing agent at `candidate`: only when the app it starts is gone
    /// (e.g. moved) or the plist is broken. A second copy of Doorman, such as a dev build,
    /// must not take over the login item of the installed one.
    public static func shouldRepoint(existing: Data, to candidate: String, appExists: (String) -> Bool) -> Bool {
        guard let current = appPath(in: existing) else { return true }
        return current != candidate && !appExists(current)
    }

    /// Whether an existing agent plist must be rewritten to start `appPath`.
    public static func needsRewrite(existing: Data, appPath: String) -> Bool {
        guard
            let dict = try? PropertyListSerialization.propertyList(from: existing, format: nil) as? [String: Any],
            let args = dict["ProgramArguments"] as? [String]
        else { return true }
        return args != ["/usr/bin/open", "-a", appPath]
    }
}
