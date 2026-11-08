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

public enum UpdateCheck {
    public static let latestReleaseAPI = URL(string: "https://api.github.com/repos/schowave/doorman/releases/latest")!
    public static let interval: TimeInterval = 24 * 60 * 60

    /// Parses GitHub's `releases/latest` response. Drafts and pre-releases are not "latest".
    public static func parseLatestRelease(_ data: Data) throws -> ReleaseInfo {
        struct Response: Decodable {
            var tag_name: String
            var html_url: URL
            var draft: Bool?
            var prerelease: Bool?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.draft != true, response.prerelease != true,
              let version = AppVersion(response.tag_name)
        else { throw CocoaError(.coderInvalidValue) }
        return ReleaseInfo(version: version, tag: response.tag_name, url: response.html_url)
    }

    /// Whether `release` is newer than the running version. An unparsable current version
    /// (e.g. a dev build) never reports updates.
    public static func isUpdate(_ release: ReleaseInfo, over current: String) -> Bool {
        guard let current = AppVersion(current), current.parts != [0, 0, 0] else { return false }
        return current < release.version
    }

    /// Whether an automatic check is due.
    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }
}
