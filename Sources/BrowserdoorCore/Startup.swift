import Foundation

/// Which bundle ID a build runs under. Only the release build (from Homebrew) owns the default
/// browser setting, the login item and the data of earlier versions; dev builds stay apart.
public enum BundleIdentity {
    public static let release = "io.github.schowave.browserdoor"
    /// Up to 0.4.x.
    public static let legacy = "io.github.schowave.doorman"
    /// `mise run app` builds, and `swift run` (no bundle).
    public static let dev = "\(release).dev"

    /// The ID of a build: its bundle's, or the dev ID without a bundle.
    public static func of(bundleIdentifier: String?) -> String {
        bundleIdentifier ?? dev
    }

    public static func isRelease(_ bundleId: String) -> Bool {
        bundleId == release
    }
}

/// What a launch needs from the system. The app implements it with `UserDefaults`,
/// `NSRunningApplication` and LaunchServices; tests use a fake.
public protocol StartupPort {
    /// The preferences stored under a bundle ID (its own domain only), nil when there are none.
    func preferences(of bundleId: String) -> [String: Any]?
    /// Replaces the preferences stored under a bundle ID; nil removes them.
    func setPreferences(_ values: [String: Any]?, of bundleId: String)
    /// Bundle ID recorded as the `https` handler, as stored (its app may be gone).
    func httpsHandlerBundleId() -> String?
    /// Asks running instances of an app to quit and waits briefly for them.
    func quitApps(bundleId: String)
    /// Registers the running bundle with LaunchServices.
    func registerWithLaunchServices()
    /// Removes a bundle's LaunchServices entry.
    func unregisterFromLaunchServices(_ app: URL)
}

/// Everything that happens when Browserdoor starts, before any UI: carrying over what earlier
/// versions left (`Legacy`), keeping the installation reachable, cleaning up after an update, and
/// deciding whether to onboard. Runs once per launch.
public struct Startup {
    /// What the app should show after `run()`.
    public enum Next: Equatable, Sendable {
        case nothing
        /// First launch: offer to become the default browser and turn on the login item.
        case onboard
        /// The old bundle ID was the default browser: ask macOS to make this one the default.
        case reclaimDefaultBrowser
    }

    static let onboardedKey = "didOnboard"
    static let lastBundlePathKey = "lastBundlePath"

    public var bundleId: String
    public var installation: Installation
    public var legacyLoginItem: LegacyLoginItem?
    public var port: StartupPort

    public init(bundleId: String, installation: Installation, legacyLoginItem: LegacyLoginItem? = nil, port: StartupPort) {
        self.bundleId = bundleId
        self.installation = installation
        self.legacyLoginItem = legacyLoginItem
        self.port = port
    }

    public func run() -> Next {
        let release = BundleIdentity.isRelease(bundleId)
        let home = installation.home

        // First, so every later step sees the preferences carried over.
        let reclaim = release && Legacy.moveIdentity(home: home, to: bundleId, port: port)
        Legacy.moveConfigFolder(home: home)

        port.registerWithLaunchServices()
        Legacy.removeDoormanLink(installation: installation)
        installation.prepare()
        if release {
            Legacy.moveLoginItem(installation: installation)
            Legacy.replaceLoginItem(legacyLoginItem, installation: installation)
        }
        forgetPreviousBundle()

        guard release else { return .nothing }
        if preference(Self.onboardedKey) as? Bool != true {
            setPreference(true, Self.onboardedKey)
            return .onboard
        }
        return reclaim ? .reclaimDefaultBrowser : .nothing
    }

    /// After an update, removes the LaunchServices entry of the bundle Browserdoor ran from last
    /// time if it is gone (`brew cleanup`), then remembers the current one.
    private func forgetPreviousBundle() {
        let previous = preference(Self.lastBundlePathKey) as? String
        if let stale = installation.staleRegistration(previousBundlePath: previous) {
            port.unregisterFromLaunchServices(stale)
        }
        setPreference(installation.bundleURL.path, Self.lastBundlePathKey)
    }

    private func preference(_ key: String) -> Any? {
        port.preferences(of: bundleId)?[key]
    }

    private func setPreference(_ value: Any, _ key: String) {
        var values = port.preferences(of: bundleId) ?? [:]
        values[key] = value
        port.setPreferences(values, of: bundleId)
    }

    /// The `https` handler recorded in LaunchServices' preferences
    /// (`com.apple.launchservices.secure.plist`, array `LSHandlers`). Read from the file because
    /// the only API that returns a handler whose app is gone (`LSCopyDefaultHandlerForURLScheme`)
    /// is deprecated.
    public static func httpsHandler(launchServicesPlist data: Data) -> String? {
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let handlers = plist["LSHandlers"] as? [[String: Any]]
        else { return nil }
        return handlers.first { ($0["LSHandlerURLScheme"] as? String)?.lowercased() == "https" }?["LSHandlerRoleAll"] as? String
    }
}
