import BrowserdoorCore
import Foundation
import ServiceManagement

/// The installation of the running app.
@MainActor
enum CurrentInstallation {
    static let shared = Installation(
        home: FileManager.default.homeDirectoryForCurrentUser,
        bundleURL: Bundle.main.bundleURL,
        label: AppIdentity.bundleId,
        legacyLoginItem: SMAppServiceLoginItem()
    )
}

/// After an update, removes the LaunchServices entry of the version Browserdoor ran from before
/// (macOS keeps it after `brew cleanup` deletes the bundle), then remembers the current path.
@MainActor
enum LaunchServicesCleanup {
    private static let key = "lastBundlePath"
    private static let lsregister = URL(fileURLWithPath:
        "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister")

    static func run(defaults: UserDefaults = .standard) {
        let previous = defaults.string(forKey: key)
        if let stale = CurrentInstallation.shared.staleRegistration(previousBundlePath: previous) {
            let process = Process()
            process.executableURL = lsregister
            process.arguments = ["-u", stale.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                log.notice("unregistered stale \(stale.path, privacy: .public)")
            } catch {
                log.error("lsregister -u failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        defaults.set(Bundle.main.bundlePath, forKey: key)
    }
}

/// Adapter for the old `SMAppService.mainApp` login item.
struct SMAppServiceLoginItem: LegacyLoginItem {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func unregister() {
        try? SMAppService.mainApp.unregister()
    }
}
