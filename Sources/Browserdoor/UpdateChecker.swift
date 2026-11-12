import AppKit
import BrowserdoorCore

/// Asks GitHub for the latest release, once a day (if enabled) and on request. Browserdoor can't
/// replace itself (Homebrew install, unsigned), so an update runs `brew upgrade` in Terminal.
@MainActor @Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    /// Owned by the policy, which SwiftUI observes through this property.
    var status: UpdateStatus {
        policy.status
    }

    var automatic: Bool {
        didSet { preferences.checksAutomatically = automatic }
    }

    private let preferences = UserDefaultsUpdatePreferences()
    private let policy: UpdatePolicy
    private var timer: Timer?

    private init() {
        policy = UpdatePolicy(
            currentVersion: RunningApp.version,
            source: GitHubReleaseSource(userAgent: "Browserdoor/\(RunningApp.version)"),
            preferences: preferences
        )
        automatic = preferences.checksAutomatically
    }

    /// Checks now if due, then re-evaluates every hour.
    func startAutomaticChecks() {
        Task { await checkAutomatically() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in await UpdateChecker.shared.checkAutomatically() }
        }
    }

    private func checkAutomatically() async {
        if case let .available(release) = await policy.checkAutomatically() {
            showAvailable(release)
        }
    }

    /// A check the user asked for: always shows the result.
    func checkNow() async {
        switch await policy.checkNow() {
        case .upToDate: showUpToDate()
        case let .available(release): showAvailable(release)
        case let .failed(message): showFailed(message)
        }
    }

    // MARK: Alerts

    private func showUpToDate() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = L("Browserdoor is up to date")
        alert.informativeText = L("Version %@ is the latest version.", RunningApp.version)
        alert.runModal()
    }

    private func showFailed(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Couldn't check for updates")
        alert.informativeText = message
        alert.runModal()
    }

    private func showAvailable(_ release: ReleaseInfo) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = L("Browserdoor %@ is available", release.version.description)
        let canUpgrade = Self.homebrew != nil
        alert.informativeText = canUpgrade
            ? L("You have version %@. The update runs “brew upgrade browserdoor” in Terminal and restarts Browserdoor.", RunningApp.version)
            : L("You have version %@.", RunningApp.version)
        alert.addButton(withTitle: canUpgrade ? L("Update in Terminal") : L("Open Release Page"))
        alert.addButton(withTitle: L("Release Notes"))
        alert.addButton(withTitle: L("Later"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if canUpgrade {
                upgradeInTerminal()
            } else {
                NSWorkspace.shared.open(release.url)
            }
        case .alertSecondButtonReturn:
            NSWorkspace.shared.open(release.url)
        default:
            policy.putOff(release)
        }
    }

    // MARK: Upgrade

    /// The Homebrew install Browserdoor runs from, if `brew` is there to upgrade it.
    static var homebrew: HomebrewInstall? {
        guard let homebrew = CurrentInstallation.shared.homebrew,
              FileManager.default.isExecutableFile(atPath: homebrew.brew.path) else { return nil }
        return homebrew
    }

    /// Opens the upgrade script in Terminal.
    private func upgradeInTerminal() {
        guard let homebrew = Self.homebrew else { return }
        let script = homebrew.upgradeScript(runningPID: ProcessInfo.processInfo.processIdentifier)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("browserdoor-update.command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            log.error("write update script: \(error.localizedDescription, privacy: .public)")
        }
    }
}
