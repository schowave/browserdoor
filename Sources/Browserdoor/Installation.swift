import AppKit
import BrowserdoorCore
import ServiceManagement

/// The installation of the running app.
@MainActor
enum CurrentInstallation {
    static let shared = Installation(
        home: FileManager.default.homeDirectoryForCurrentUser,
        bundleURL: Bundle.main.bundleURL,
        label: AppIdentity.bundleId
    )
}

/// `StartupPort` backed by `UserDefaults`, `NSRunningApplication` and LaunchServices.
struct SystemStartupPort: StartupPort {
    private static let lsregister = URL(fileURLWithPath:
        "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister")

    func preferences(of bundleId: String) -> [String: Any]? {
        UserDefaults.standard.persistentDomain(forName: bundleId)
    }

    func setPreferences(_ values: [String: Any]?, of bundleId: String) {
        if let values {
            UserDefaults.standard.setPersistentDomain(values, forName: bundleId)
        } else {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
        }
    }

    func httpsHandlerBundleId() -> String? {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist")
        return (try? Data(contentsOf: file)).flatMap(Startup.httpsHandler(launchServicesPlist:))
    }

    func quitApps(bundleId: String) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        guard !apps.isEmpty else { return }
        apps.forEach { $0.terminate() }
        // Its preferences are written on quit; wait so they are moved over complete.
        let deadline = Date().addingTimeInterval(3)
        while apps.contains(where: { !$0.isTerminated }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        log.notice("quit \(apps.count) instance(s) of \(bundleId, privacy: .public)")
    }

    func registerWithLaunchServices() {
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
    }

    func unregisterFromLaunchServices(_ app: URL) {
        let process = Process()
        process.executableURL = Self.lsregister
        process.arguments = ["-u", app.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            log.notice("unregistered stale \(app.path, privacy: .public)")
        } catch {
            log.error("lsregister -u failed: \(error.localizedDescription, privacy: .public)")
        }
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
