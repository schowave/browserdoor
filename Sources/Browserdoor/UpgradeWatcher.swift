import AppKit
import BrowserdoorCore

/// Restarts Browserdoor once `brew upgrade` has installed a new version. Homebrew repoints
/// `<prefix>/opt/<formula>` as one of the last steps of an upgrade, so this watches the `opt`
/// folder and, shortly after it changes, asks `Installation.upgradedBundle` whether that was us.
/// Release builds from Homebrew only.
@MainActor
final class UpgradeWatcher {
    static let shared = UpgradeWatcher()

    /// Homebrew may still be linking and running `post_install` when `opt` changes.
    private static let settleDelay: TimeInterval = 3
    /// How long to wait before trying again while the user is busy.
    private static let busyDelay: TimeInterval = 10

    /// True while restarting would lose what the user is doing (an open picker or settings).
    /// A modal dialog counts as busy, too.
    var isBusy: () -> Bool = { false }

    private var source: DispatchSourceFileSystemObject?
    private var pendingCheck: DispatchWorkItem?
    private var restartOnQuit = false
    private var quitObserver: NSObjectProtocol?

    func start() {
        guard source == nil, BundleIdentity.isRelease(AppIdentity.bundleId),
              let homebrew = CurrentInstallation.shared.homebrew else { return }
        let opt = homebrew.prefix.appendingPathComponent("opt", isDirectory: true)
        let fd = open(opt.path, O_EVTONLY)
        guard fd >= 0 else {
            log.error("can't watch \(opt.path, privacy: .public) for upgrades: errno \(errno)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: .main
        )
        source.setEventHandler { [weak self, weak source] in
            let event = source?.data ?? []
            MainActor.assumeIsolated { self?.handle(event) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        if quitObserver == nil {
            quitObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.spawnRestartIfAsked() }
            }
        }
        // An upgrade may have landed between launch and now.
        scheduleCheck(after: 0)
    }

    private func handle(_ event: DispatchSource.FileSystemEvent) {
        if !event.isDisjoint(with: [.delete, .rename]) {
            // `opt` itself was replaced: watch the new one.
            source?.cancel()
            source = nil
            start()
            return
        }
        scheduleCheck(after: Self.settleDelay)
    }

    private func scheduleCheck(after delay: TimeInterval) {
        pendingCheck?.cancel()
        let check = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.restartIfUpgraded() }
        }
        pendingCheck = check
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: check)
    }

    private func restartIfUpgraded() {
        guard let new = CurrentInstallation.shared.upgradedBundle else { return }
        if isBusy() || NSApp.modalWindow != nil {
            scheduleCheck(after: Self.busyDelay)
            return
        }
        log.notice("upgraded to \(new.path, privacy: .public), restarting")
        restartOnQuit = true
        NSApp.terminate(nil)
        // Only returns when quitting was refused.
        restartOnQuit = false
        scheduleCheck(after: Self.busyDelay)
    }

    /// The restart starts only once quitting is certain, so a refused quit leaves nothing behind.
    private func spawnRestartIfAsked() {
        guard restartOnQuit else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = CurrentInstallation.shared.restartArguments(waitingFor: ProcessInfo.processInfo.processIdentifier)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            log.error("restart after upgrade failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
