import DoormanCore
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

/// Adapter for the old `SMAppService.mainApp` login item.
struct SMAppServiceLoginItem: LegacyLoginItem {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func unregister() {
        try? SMAppService.mainApp.unregister()
    }
}
