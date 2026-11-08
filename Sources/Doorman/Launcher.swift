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
    /// NSWorkspace's list of running apps first; if the app isn't in it, the process table.
    /// The list is a snapshot that can lag behind (seen: a running Zen reported as not running,
    /// which sent a cold-start command and lost the link); the process table is always current.
    func isRunning(app: URL) -> Bool {
        let bundlePath = app.resolvingSymlinksInPath().path
        if NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleURL?.resolvingSymlinksInPath().path == bundlePath
        }) {
            return true
        }
        return Self.processRuns(under: bundlePath + "/Contents/MacOS/")
    }

    /// Whether any process's executable lies under `prefix`.
    static func processRuns(under prefix: String) -> Bool {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return false }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return false }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            if proc_pidpath(pid, &path, UInt32(path.count)) > 0, String(cString: path).hasPrefix(prefix) {
                return true
            }
        }
        return false
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
