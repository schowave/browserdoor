import AppKit
import DoormanCore

/// `BrowserEnvironment` backed by LaunchServices and the real file system.
struct SystemEnvironment: BrowserEnvironment {
    var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    var ownBundleId: String { Bundle.main.bundleIdentifier ?? AppIdentity.bundleId }

    func httpsHandlers() -> [URL] {
        guard let probe = URL(string: "https://example.com") else { return [] }
        return NSWorkspace.shared.urlsForApplications(toOpen: probe)
    }

    func appInfo(at app: URL) -> AppInfo? {
        guard let bundle = Bundle(url: app), let id = bundle.bundleIdentifier else { return nil }
        var name = FileManager.default.displayName(atPath: app.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        return AppInfo(
            bundleId: id,
            name: name,
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            executableName: bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
        )
    }

    func contents(of file: URL) -> Data? {
        try? Data(contentsOf: file)
    }
}

enum AppIdentity {
    static let bundleId = "io.github.schowave.doorman"
    static let name = "Doorman"
}
