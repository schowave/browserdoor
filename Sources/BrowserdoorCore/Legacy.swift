import Foundation

/// The login item Browserdoor used up to 0.1.x (`SMAppService.mainApp`), which remembers the
/// versioned Cellar path. Only here to migrate away from it.
public protocol LegacyLoginItem {
    var isEnabled: Bool { get }
    func unregister()
}

/// Everything earlier versions left behind, oldest first. `Startup` runs these steps; each is a
/// no-op once done. Delete a step when nobody upgrades from that version any more.
enum Legacy {
    // MARK: 0.1.x: login item via SMAppService

    /// Unregisters the old login item and keeps the login item on as a LaunchAgent.
    static func replaceLoginItem(_ item: LegacyLoginItem?, installation: Installation) {
        guard let item, item.isEnabled else { return }
        item.unregister()
        if !installation.launchesAtLogin {
            try? installation.setLaunchAtLogin(true)
        }
    }

    // MARK: Up to 0.2.x: named Doorman (formula `doorman`, `~/.config/doorman`)

    static let doorman = (app: "Doorman.app", formula: "doorman")

    /// Moves `~/.config/doorman` to the new place once, unless a new config already exists.
    static func moveConfigFolder(home: URL) {
        let fm = FileManager.default
        let new = Config.fileURL(home: home).deletingLastPathComponent()
        let old = home.appendingPathComponent(".config/doorman", isDirectory: true)
        guard !fm.fileExists(atPath: new.path), fm.fileExists(atPath: old.path) else { return }
        try? fm.moveItem(at: old, to: new)
    }

    /// Removes `~/Applications/Doorman.app` if it still points into the `doorman` formula, so only
    /// one entry remains. A login item that started it is repointed by `Installation.prepare()`.
    static func removeDoormanLink(installation: Installation) {
        let fm = FileManager.default
        let legacy = installation.linkURL.deletingLastPathComponent().appendingPathComponent(doorman.app)
        guard legacy != installation.linkURL,
              let destination = try? fm.destinationOfSymbolicLink(atPath: legacy.path),
              destination.hasSuffix("/\(doorman.app)"),
              destination.contains("/Cellar/\(doorman.formula)/")
              || destination.hasSuffix("/opt/\(doorman.formula)/\(doorman.app)")
        else { return }
        try? fm.removeItem(at: legacy)
    }

    // MARK: Up to 0.4.x: bundle ID io.github.schowave.doorman

    /// Quits a still-running old instance (it would keep writing the old preferences), moves its
    /// preferences over (values already set under the new ID win) and deletes its cache.
    /// - Returns: whether the old ID is still recorded as the default browser, so Browserdoor has
    ///   to ask macOS to make the new ID the default. Only checked when something was moved, so
    ///   the question comes once.
    static func moveIdentity(home: URL, to bundleId: String, port: StartupPort) -> Bool {
        let fm = FileManager.default
        port.quitApps(bundleId: BundleIdentity.legacy)
        let old = port.preferences(of: BundleIdentity.legacy) ?? [:]
        let cache = home.appendingPathComponent("Library/Caches/\(BundleIdentity.legacy)", isDirectory: true)
        guard !old.isEmpty || fm.fileExists(atPath: cache.path) else { return false }

        if !old.isEmpty {
            let current = port.preferences(of: bundleId) ?? [:]
            port.setPreferences(old.merging(current) { _, kept in kept }, of: bundleId)
            port.setPreferences(nil, of: BundleIdentity.legacy)
        }
        try? fm.removeItem(at: cache)
        return port.httpsHandlerBundleId()?.lowercased() == BundleIdentity.legacy
    }

    /// Replaces a LaunchAgent under the old label with one under the current label. Without one,
    /// none is created.
    static func moveLoginItem(installation: Installation) {
        let fm = FileManager.default
        let legacy = installation.agentURL.deletingLastPathComponent()
            .appendingPathComponent("\(BundleIdentity.legacy).plist")
        guard installation.label != BundleIdentity.legacy, fm.fileExists(atPath: legacy.path) else { return }
        try? fm.removeItem(at: legacy)
        if !installation.launchesAtLogin {
            try? installation.setLaunchAtLogin(true)
        }
    }
}
