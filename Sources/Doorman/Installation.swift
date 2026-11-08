import AppKit
import DoormanCore
import ServiceManagement

/// Keeps Doorman reachable under a path that survives `brew upgrade`, and manages the
/// login item on top of that path.
@MainActor
enum Installation {
    private static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    /// The path used for the login item: `~/Applications/Doorman.app` (a link to Homebrew's
    /// `opt` path) for Homebrew installs, otherwise the running bundle itself.
    static var stableAppURL: URL {
        ensureUserApplicationsLink() ?? Bundle.main.bundleURL
    }

    /// For a Homebrew install, makes `~/Applications/Doorman.app` a symlink to the `opt` path.
    /// Leaves anything that is not a symlink alone (e.g. a manually copied app).
    @discardableResult
    static func ensureUserApplicationsLink() -> URL? {
        guard let opt = InstallLocation.homebrewOptPath(forBundlePath: Bundle.main.bundlePath),
              FileManager.default.fileExists(atPath: opt)
        else { return nil }

        let fm = FileManager.default
        let link = InstallLocation.userApplicationsLink(home: home, appName: AppIdentity.name)
        if let existing = try? fm.destinationOfSymbolicLink(atPath: link.path) {
            if existing == opt {
                return link
            }
            try? fm.removeItem(at: link) // our own stale link
        } else if fm.fileExists(atPath: link.path) {
            return nil // a real app is there; don't touch it
        }
        do {
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: opt)
            return link
        } catch {
            log.error("could not link \(link.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Login item

    private static var agentURL: URL {
        LoginAgent.fileURL(home: home, label: AppIdentity.bundleId)
    }

    static var launchesAtLogin: Bool {
        FileManager.default.fileExists(atPath: agentURL.path)
    }

    static func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                let data = try LoginAgent.plist(label: AppIdentity.bundleId, appPath: stableAppURL.path)
                try FileManager.default.createDirectory(
                    at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try data.write(to: agentURL, options: .atomic)
            } else if launchesAtLogin {
                try FileManager.default.removeItem(at: agentURL)
            }
        } catch {
            log.error("login item: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Rewrites the agent if it points somewhere else (e.g. the app moved), and drops a
    /// path-bound SMAppService login item left over from earlier builds.
    static func refreshLoginItem() {
        if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
            if !launchesAtLogin {
                setLaunchAtLogin(true)
            }
        }
        guard launchesAtLogin,
              let data = try? Data(contentsOf: agentURL),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let args = dict["ProgramArguments"] as? [String]
        else { return }
        if args.last != stableAppURL.path {
            setLaunchAtLogin(true)
        }
    }
}
