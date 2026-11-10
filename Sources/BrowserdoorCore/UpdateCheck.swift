import Foundation

/// A dotted numeric version like `0.1.1` (a leading `v` is ignored).
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ string: String) {
        var trimmed = Substring(string.trimmingCharacters(in: .whitespaces))
        if trimmed.first == "v" || trimmed.first == "V" {
            trimmed = trimmed.dropFirst()
        }
        let core = trimmed.prefix { $0 != "-" && $0 != "+" }
        let parts = core.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        self.parts = parts.compactMap(\.self)
    }

    public var description: String {
        parts.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for i in 0 ..< max(lhs.parts.count, rhs.parts.count) {
            let l = i < lhs.parts.count ? lhs.parts[i] : 0
            let r = i < rhs.parts.count ? rhs.parts[i] : 0
            if l != r {
                return l < r
            }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

public struct ReleaseInfo: Equatable, Sendable {
    public var version: AppVersion
    public var tag: String
    public var url: URL
}

/// Where the latest release comes from.
public protocol ReleaseSource: Sendable {
    func latestRelease() async throws -> ReleaseInfo
}

/// What the update check remembers between launches.
@MainActor
public protocol UpdatePreferences: AnyObject {
    var checksAutomatically: Bool { get set }
    var lastCheck: Date? { get set }
    /// A release the user answered with "Later"; automatic checks don't announce it again.
    var skippedTag: String? { get set }
}

/// What to tell the user after a check.
public enum UpdateNotice: Equatable, Sendable {
    case upToDate
    case available(ReleaseInfo)
    case failed(String)
}

/// Decides when to check for updates and what to announce. Automatic checks run at most once
/// per day (if enabled) and only speak up for a new release the user hasn't put off; a check the
/// user asked for always reports its result.
@MainActor
public final class UpdatePolicy {
    public static let interval: TimeInterval = 24 * 60 * 60

    public let currentVersion: String
    public let source: ReleaseSource
    public let preferences: UpdatePreferences
    private let now: () -> Date

    /// The newer release found by the last check, if any.
    public private(set) var available: ReleaseInfo?

    public init(currentVersion: String, source: ReleaseSource, preferences: UpdatePreferences,
                now: @escaping () -> Date = Date.init)
    {
        self.currentVersion = currentVersion
        self.source = source
        self.preferences = preferences
        self.now = now
    }

    public var isDue: Bool {
        guard preferences.checksAutomatically else { return false }
        guard let last = preferences.lastCheck else { return true }
        return now().timeIntervalSince(last) >= Self.interval
    }

    /// A due automatic check. Nil: nothing to tell (not due, up to date, put off, or failed).
    public func checkAutomatically() async -> UpdateNotice? {
        guard isDue else { return nil }
        let notice = await check()
        if case let .available(release) = notice, release.tag != preferences.skippedTag {
            return notice
        }
        return nil
    }

    /// A check the user asked for; always returns what to show.
    public func checkNow() async -> UpdateNotice {
        await check()
    }

    /// The user answered "Later": don't announce this release automatically again.
    public func putOff(_ release: ReleaseInfo) {
        preferences.skippedTag = release.tag
    }

    private func check() async -> UpdateNotice {
        do {
            let release = try await source.latestRelease()
            preferences.lastCheck = now()
            guard Self.isUpdate(release, over: currentVersion) else {
                available = nil
                return .upToDate
            }
            available = release
            return .available(release)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Whether `release` is newer than `current`. A dev build (`0.0.0`) never updates.
    static func isUpdate(_ release: ReleaseInfo, over current: String) -> Bool {
        guard let current = AppVersion(current), current.parts != [0, 0, 0] else { return false }
        return current < release.version
    }
}

/// Production `ReleaseSource`: github.com's `releases/latest`, which redirects to the newest
/// release's tag page (drafts and pre-releases excluded). Unlike api.github.com it has no
/// per-IP rate limit (60 requests an hour without a token, often used up behind shared IPs).
public struct GitHubReleaseSource: ReleaseSource {
    public static let browserdoor = URL(string: "https://github.com/schowave/browserdoor/releases/latest")!

    public var url: URL
    public var userAgent: String

    public init(url: URL = GitHubReleaseSource.browserdoor, userAgent: String) {
        self.url = url
        self.userAgent = userAgent
    }

    public func latestRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "HEAD"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, let final = http.url
        else { throw URLError(.badServerResponse) }
        return try Self.parse(releaseURL: final)
    }

    /// Reads the release from the URL `releases/latest` redirected to: `…/releases/tag/<tag>`.
    /// Without any release GitHub stays on `…/releases`, which is not a release.
    static func parse(releaseURL url: URL) throws -> ReleaseInfo {
        let parts = url.pathComponents
        guard parts.count >= 2, parts[parts.count - 2] == "tag",
              let version = AppVersion(url.lastPathComponent)
        else { throw URLError(.cannotParseResponse) }
        return ReleaseInfo(version: version, tag: url.lastPathComponent, url: url)
    }
}

/// Production `UpdatePreferences`, in `UserDefaults`.
@MainActor
public final class UserDefaultsUpdatePreferences: UpdatePreferences {
    private let defaults: UserDefaults
    private enum Keys {
        static let automatic = "checkForUpdatesAutomatically"
        static let lastCheck = "lastUpdateCheck"
        static let skipped = "skippedUpdateVersion"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Keys.automatic: true])
    }

    public var checksAutomatically: Bool {
        get { defaults.bool(forKey: Keys.automatic) }
        set { defaults.set(newValue, forKey: Keys.automatic) }
    }

    public var lastCheck: Date? {
        get { defaults.object(forKey: Keys.lastCheck) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastCheck) }
    }

    public var skippedTag: String? {
        get { defaults.string(forKey: Keys.skipped) }
        set { defaults.set(newValue, forKey: Keys.skipped) }
    }
}
