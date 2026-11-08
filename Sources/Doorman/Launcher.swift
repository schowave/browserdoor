import AppKit
import DoormanCore
import OSLog

let log = Logger(subsystem: AppIdentity.bundleId, category: "app")

@MainActor
enum Launcher {
    static func open(_ urls: [URL], in target: Target) {
        let bundleId = Bundle(url: target.appURL)?.bundleIdentifier
        let running = bundleId.map { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false

        for command in target.launchCommands(for: urls, appIsRunning: running) {
            switch command {
            case let .run(executable, arguments):
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
            case let .open(urls, app):
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: configuration)
            }
        }

        // A remote command to a running Zen opens the tab but may leave Zen in the background.
        // `NSRunningApplication.activate()` from a non-active app is ignored under macOS 14's
        // cooperative activation; asking LaunchServices to open the running app is not.
        if running, case .zenSpace = target.kind {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: target.appURL, configuration: configuration)
        }
    }
}
