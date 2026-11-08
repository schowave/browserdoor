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
}
