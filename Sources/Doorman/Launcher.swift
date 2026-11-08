import AppKit
import OSLog
import DoormanCore

let log = Logger(subsystem: AppIdentity.bundleId, category: "app")

@MainActor
enum Launcher {
    static func open(_ urls: [URL], in target: Target) {
        let bundleId = Bundle(url: target.appURL)?.bundleIdentifier
        let running = bundleId.map { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false

        for command in target.launchCommands(for: urls, appIsRunning: running) {
            switch command {
            case .run(let executable, let arguments):
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
            case .open(let urls, let app):
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: configuration)
            }
        }

        // A remote command to a running Zen opens the tab but may leave Zen in the background.
        if running, let bundleId {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first?.activate()
        }
    }
}
