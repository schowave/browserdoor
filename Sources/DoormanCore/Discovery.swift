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

public struct Discovery {
    public static let zenBundleId = "app.zen-browser.zen"
    /// First Zen version shipping `--space` (zen-browser/desktop#15074).
    public static let zenMinimumSpaceVersion = [1, 24]

    public var environment: BrowserEnvironment
    public var zenProfileOverride: URL?
    /// Bundle IDs to list in addition to `KnownBrowsers` (config `extraApps`).
    public var extraApps: Set<String>

    public init(environment: BrowserEnvironment, zenProfileOverride: URL? = nil, extraApps: [String] = []) {
        self.environment = environment
        self.zenProfileOverride = zenProfileOverride
        self.extraApps = Set(extraApps)
    }

    /// Discovers all targets in default order: Zen spaces, Chromium browsers, other browsers A–Z.
    public func discover() -> [Target] {
        let installed = installedApps()
        var covered: Set<String> = [environment.ownBundleId]
        var result: [Target] = []

        if let zen = installed[Self.zenBundleId] {
            covered.insert(Self.zenBundleId)
            result += zenTargets(app: zen.url)
        }

        for browser in ChromiumBrowser.known {
            guard let app = installed[browser.bundleId] else { continue }
            covered.insert(browser.bundleId)
            result += chromiumTargets(browser: browser, app: app.url)
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
            .map { Target(id: Target.appID($0.info.bundleId), name: $0.info.name, kind: .app($0.url)) }
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

    func zenTargets(app: URL) -> [Target] {
        let info = environment.appInfo(at: app)
        let plain = [Target(id: Target.appID(Self.zenBundleId), name: info?.name ?? "Zen", kind: .app(app))]

        guard
            let info, Self.versionAtLeast(info.version, Self.zenMinimumSpaceVersion),
            let executableName = info.executableName,
            let profile = zenProfileOverride ?? zenDefaultProfile(),
            let data = environment.contents(of: profile.appendingPathComponent(ZenSpaces.sessionFileName)),
            let json = try? MozLz4.decompress(data),
            let spaces = try? ZenSpaces.parse(sessionJSON: json),
            !spaces.isEmpty
        else { return plain }

        let executable = app.appendingPathComponent("Contents/MacOS").appendingPathComponent(executableName)
        return spaces.map { space in
            Target(
                id: Target.zenID(space.uuid),
                name: space.name,
                kind: .zenSpace(app: app, executable: executable, space: space, profile: zenProfileOverride)
            )
        }
    }

    func zenDefaultProfile() -> URL? {
        let root = ZenProfile.defaultRoot(home: environment.home)
        guard
            let data = environment.contents(of: root.appendingPathComponent("profiles.ini")),
            let text = String(data: data, encoding: .utf8)
        else { return nil }
        return ZenProfile.defaultProfile(profilesIni: text, root: root)
    }

    func chromiumTargets(browser: ChromiumBrowser, app: URL) -> [Target] {
        let appName = environment.appInfo(at: app)?.name ?? browser.bundleId
        let profiles = environment.contents(of: browser.localStateURL(home: environment.home))
            .flatMap { try? ChromiumProfiles.parse(localState: $0) } ?? []

        guard !profiles.isEmpty else {
            return [Target(id: Target.appID(browser.bundleId), name: appName, kind: .app(app))]
        }
        return profiles.map { profile in
            Target(
                id: Target.chromiumID(browser.bundleId, profile.directory),
                name: profiles.count == 1 ? appName : "\(appName) › \(profile.name)",
                kind: .chromium(app: app, profileDirectory: profile.directory)
            )
        }
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
