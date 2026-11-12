import Foundation

public struct AppInfo: Equatable, Sendable {
    public var bundleId: String
    public var name: String
    public var version: String?
    public var executableName: String?

    public init(bundleId: String, name: String, version: String? = nil, executableName: String? = nil) {
        self.bundleId = bundleId
        self.name = name
        self.version = version
        self.executableName = executableName
    }
}

/// Everything discovery needs from the system. The app implements it with
/// NSWorkspace and the file system; tests use a fake.
public protocol BrowserEnvironment {
    var home: URL { get }
    var ownBundleId: String { get }
    /// All apps registered to open `https` URLs.
    func httpsHandlers() -> [URL]
    func appInfo(at app: URL) -> AppInfo?
    func contents(of file: URL) -> Data?
    /// Where LaunchServices finds an app, for `extraApps` that don't register for web links.
    func applicationURL(bundleId: String) -> URL?
}

/// A browser family whose apps become targets of their own (Zen spaces, Chromium or Firefox
/// profiles). Everything about one family (where its data lives, how its targets are named and
/// opened) sits in that family's file.
protocol BrowserFamily: Sendable {
    /// Bundle IDs of the family's apps, in default order.
    var bundleIds: [String] { get }
    /// Targets for one installed app of the family. Falls back to a plain `app:` target when the
    /// app has nothing to split into.
    func targets(app: URL, bundleId: String, discovery: Discovery) -> [Target]
}

public struct Discovery {
    /// In default order: Zen spaces, then Chromium profiles, then Firefox profiles.
    static let families: [BrowserFamily] = [ZenBrowser(), ChromiumFamily(), FirefoxFamily()]

    public var environment: BrowserEnvironment
    public var zenProfileOverride: URL?
    /// Bundle IDs to list in addition to `KnownBrowsers` (config `extraApps`).
    public var extraApps: Set<String>

    public init(environment: BrowserEnvironment, zenProfileOverride: URL? = nil, extraApps: [String] = []) {
        self.environment = environment
        self.zenProfileOverride = zenProfileOverride
        self.extraApps = Set(extraApps)
    }

    /// Discovers all targets in default order: the families, then other browsers A–Z.
    public func discover() -> [Target] {
        let installed = installedApps()
        var covered: Set<String> = [environment.ownBundleId]
        var result: [Target] = []

        for family in Self.families {
            for bundleId in family.bundleIds {
                guard let app = installed[bundleId] else { continue }
                covered.insert(bundleId)
                result += family.targets(app: app.url, bundleId: bundleId, discovery: self)
            }
        }

        let wanted = KnownBrowsers.bundleIds.union(extraApps)
        var candidates = installed
        // Apps the user added explicitly count even if they don't register for https.
        for id in extraApps where candidates[id] == nil {
            if let url = environment.applicationURL(bundleId: id), let info = environment.appInfo(at: url) {
                candidates[id] = (url, info)
            }
        }
        let others = candidates.values
            .filter { wanted.contains($0.info.bundleId) && !covered.contains($0.info.bundleId) }
            .map { Target.plain(app: $0.url, bundleId: $0.info.bundleId, name: $0.info.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        // IDs must be unique (config keys, SwiftUI identity); keep the first occurrence.
        var seen = Set<String>()
        return (result + others).filter { seen.insert($0.id).inserted }
    }

    /// One app per bundle ID among the `https` handlers, ignoring copies outside the
    /// application folders (test browsers in caches, snapshots, build products, …).
    func installedApps() -> [String: (url: URL, info: AppInfo)] {
        var apps: [String: (url: URL, info: AppInfo)] = [:]
        for url in environment.httpsHandlers() where isInApplicationFolder(url) {
            guard let info = environment.appInfo(at: url), apps[info.bundleId] == nil else { continue }
            apps[info.bundleId] = (url, info)
        }
        return apps
    }

    func isInApplicationFolder(_ app: URL) -> Bool {
        let path = app.standardizedFileURL.path
        // /System/Volumes/Data is the firmlinked user volume (home dirs, caches), not the system.
        if path.hasPrefix("/System/Volumes/Data/") {
            return false
        }
        let roots = ["/Applications/", "/System/", environment.home.appendingPathComponent("Applications").path + "/"]
        return roots.contains { path.hasPrefix($0) }
    }

    /// The app's display name, or `fallback` when its Info.plist can't be read.
    func appName(_ app: URL, fallback: String) -> String {
        environment.appInfo(at: app)?.name ?? fallback
    }

    /// Compares the leading numeric components of a version like `1.24.1b`.
    static func versionAtLeast(_ version: String?, _ minimum: [Int]) -> Bool {
        guard let version else { return false }
        let parts = version.split(separator: ".").map { component in
            Int(component.prefix(while: \.isNumber)) ?? 0
        }
        for (i, min) in minimum.enumerated() {
            let value = i < parts.count ? parts[i] : 0
            if value != min {
                return value > min
            }
        }
        return true
    }
}
