import Foundation

/// What the move from bundle ID `io.github.schowave.doorman` (up to 0.4.x) needs from the system.
/// The app implements it with `UserDefaults` and LaunchServices; tests use a fake.
public protocol IdentityMigrationPort {
    /// The preferences stored under the old bundle ID (empty when there are none).
    func legacyPreferences() -> [String: Any]
    /// Writes preferences into the current domain.
    func importPreferences(_ values: [String: Any])
    func removeLegacyPreferences()
    /// Bundle ID LaunchServices has recorded as the `https` handler, as stored (it may no longer
    /// match an installed app).
    func httpsHandlerBundleId() -> String?
}

/// Moves what was kept under the old bundle ID to the current one, once, on the first launch
/// after the update: preferences (onboarding, update check, menu bar position), the cache, and
/// the default-browser setting. The login item moves in `Installation.prepare()`.
public struct IdentityMigration {
    public static let legacyBundleId = "io.github.schowave.doorman"
    public static let bundleId = "io.github.schowave.browserdoor"

    public struct Outcome: Equatable, Sendable {
        public var migrated = false
        /// The old ID was the default browser: macOS now sends links elsewhere until Browserdoor
        /// asks to become the default again.
        public var reclaimDefaultBrowser = false

        public init(migrated: Bool = false, reclaimDefaultBrowser: Bool = false) {
            self.migrated = migrated
            self.reclaimDefaultBrowser = reclaimDefaultBrowser
        }
    }

    public var home: URL
    public var port: IdentityMigrationPort

    public init(home: URL, port: IdentityMigrationPort) {
        self.home = home
        self.port = port
    }

    /// The login item label to migrate from, for the release build only (dev builds stay apart).
    public static func legacyLabel(for bundleId: String) -> String? {
        bundleId == Self.bundleId ? legacyBundleId : nil
    }

    public func run() -> Outcome {
        var outcome = Outcome()
        let fm = FileManager.default
        let legacy = port.legacyPreferences()
        let cache = home.appendingPathComponent("Library/Caches/\(Self.legacyBundleId)", isDirectory: true)
        guard !legacy.isEmpty || fm.fileExists(atPath: cache.path) else { return outcome }

        outcome.migrated = true
        if !legacy.isEmpty {
            port.importPreferences(legacy)
            port.removeLegacyPreferences()
        }
        try? fm.removeItem(at: cache)
        outcome.reclaimDefaultBrowser = port.httpsHandlerBundleId()?.lowercased() == Self.legacyBundleId
        return outcome
    }

    /// The `https` handler recorded in LaunchServices' preferences
    /// (`com.apple.launchservices.secure.plist`, array `LSHandlers`).
    public static func httpsHandler(launchServicesPlist data: Data) -> String? {
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let handlers = plist["LSHandlers"] as? [[String: Any]]
        else { return nil }
        return handlers.first { ($0["LSHandlerURLScheme"] as? String)?.lowercased() == "https" }?["LSHandlerRoleAll"] as? String
    }
}
