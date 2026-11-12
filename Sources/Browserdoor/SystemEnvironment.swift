import AppKit
import BrowserdoorCore

/// `BrowserEnvironment` backed by LaunchServices and the real file system.
struct SystemEnvironment: BrowserEnvironment {
    var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    var ownBundleId: String {
        AppIdentity.bundleId
    }

    func httpsHandlers() -> [URL] {
        guard let probe = URL(string: "https://example.com") else { return [] }
        return NSWorkspace.shared.urlsForApplications(toOpen: probe)
    }

    func appInfo(at app: URL) -> AppInfo? {
        guard let info = Self.infoPlist(of: app), let id = info["CFBundleIdentifier"] as? String else { return nil }
        var name = FileManager.default.displayName(atPath: app.path)
        if name.hasSuffix(".app") {
            name.removeLast(4)
        }
        return AppInfo(
            bundleId: id,
            name: name,
            version: info["CFBundleShortVersionString"] as? String,
            executableName: info["CFBundleExecutable"] as? String
        )
    }

    /// Reads Info.plist from disk every time. `Bundle(url:)` caches per path, so after an app
    /// updates itself (Zen does) it would keep reporting the old version until Browserdoor restarts.
    static func infoPlist(of app: URL) -> [String: Any]? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
    }

    func applicationURL(bundleId: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
    }

    func contents(of file: URL) -> Data? {
        try? Data(contentsOf: file)
    }
}

enum AppIdentity {
    /// `BundleIdentity.release` for the Homebrew build, `BundleIdentity.dev` otherwise. The
    /// login item label, cache folder and log subsystem follow it.
    static let bundleId = BundleIdentity.of(bundleIdentifier: Bundle.main.bundleIdentifier)
    static let name = "Browserdoor"
}
