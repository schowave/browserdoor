import Foundation

/// The stable ID of a target, as stored in the config: the one place that formats and parses it.
public enum TargetID: Equatable, Hashable, Sendable {
    /// `zen:{uuid}`
    case zen(uuid: String)
    /// `chromium:<bundleId>:<profileDir>`
    case chromium(bundleId: String, profileDirectory: String)
    /// `firefox:<bundleId>:<profilePath>`
    case firefox(bundleId: String, profilePath: String)
    /// `app:<bundleId>`
    case app(bundleId: String)

    public var string: String {
        switch self {
        case let .zen(uuid): "zen:\(uuid)"
        case let .chromium(bundleId, dir): "chromium:\(bundleId):\(dir)"
        case let .firefox(bundleId, path): "firefox:\(bundleId):\(path)"
        case let .app(bundleId): "app:\(bundleId)"
        }
    }

    /// Nil for anything that isn't one of the four forms. The last field may contain `:`.
    public init?(_ string: String) {
        let parts = string.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        switch (parts.first, parts.count) {
        case ("zen", 2) where !parts[1].isEmpty:
            self = .zen(uuid: parts[1])
        case ("app", 2) where !parts[1].isEmpty:
            self = .app(bundleId: parts[1])
        case ("chromium", 3) where !parts[1].isEmpty && !parts[2].isEmpty:
            self = .chromium(bundleId: parts[1], profileDirectory: parts[2])
        case ("firefox", 3) where !parts[1].isEmpty && !parts[2].isEmpty:
            self = .firefox(bundleId: parts[1], profilePath: parts[2])
        default:
            return nil
        }
    }
}
