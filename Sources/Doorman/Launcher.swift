import AppKit
import DoormanCore
import OSLog

let log = Logger(subsystem: AppIdentity.bundleId, category: "app")

/// Opens links for the running app.
@MainActor
enum Links {
    static let opener = LinkOpener(port: SystemLaunchPort())
}

/// `LaunchPort` adapter backed by LaunchServices, `Process` and `NSRunningApplication`.
struct SystemLaunchPort: LaunchPort {
    func bundleIdentifier(of app: URL) -> String? {
        SystemEnvironment.infoPlist(of: app)?["CFBundleIdentifier"] as? String
    }

    func isRunning(bundleId: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    func contents(of file: URL) -> Data? {
        try? Data(contentsOf: file)
    }

    func run(_ executable: URL, arguments: [String]) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            log.error("launch failed: \(executable.path, privacy: .public) \(error.localizedDescription, privacy: .public)")
        }
    }

    func open(_ urls: [URL], with app: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: configuration)
    }

    /// `NSRunningApplication.activate()` from a non-active app is ignored under macOS 14's
    /// cooperative activation; asking LaunchServices to open the running app is not.
    func activate(_ app: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app, configuration: configuration)
    }
}
