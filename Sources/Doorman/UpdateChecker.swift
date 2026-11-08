import AppKit
import DoormanCore

/// Asks GitHub for the latest release, once a day (if enabled) and on request. Doorman can't
/// replace itself (Homebrew install, unsigned), so an update runs `brew upgrade` in Terminal.
@MainActor @Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case failed(String)
    }

    private(set) var status: Status = .idle

    var automatic: Bool {
        didSet { preferences.checksAutomatically = automatic }
    }

    private let preferences = UserDefaultsUpdatePreferences()
    private let policy: UpdatePolicy
    private var timer: Timer?

    private init() {
        policy = UpdatePolicy(
            currentVersion: RunningApp.version,
            source: GitHubReleaseSource(userAgent: "Doorman/\(RunningApp.version)"),
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
        guard policy.isDue else { return }
        status = .checking
        let notice = await policy.checkAutomatically()
        updateStatus()
        if case let .available(release) = notice {
            showAvailable(release)
        }
    }

    /// A check the user asked for: always shows the result.
    func checkNow() async {
        status = .checking
        let notice = await policy.checkNow()
        switch notice {
        case .upToDate: status = .upToDate; showUpToDate()
        case let .available(release): status = .available(release); showAvailable(release)
        case let .failed(message): status = .failed(message); showFailed(message)
        }
    }

    private func updateStatus() {
        status = policy.available.map(Status.available) ?? (preferences.lastCheck == nil ? .idle : .upToDate)
    }

    // MARK: Alerts

    private func showUpToDate() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = L("Doorman is up to date")
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
        alert.messageText = L("Doorman %@ is available", release.version.description)
        let canUpgrade = Self.brewExecutable != nil
        alert.informativeText = canUpgrade
            ? L("You have version %@. The update runs “brew upgrade doorman” in Terminal and restarts Doorman.", RunningApp.version)
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

    /// `<prefix>/bin/brew` when Doorman runs from a Homebrew Cellar.
    static var brewExecutable: URL? {
        guard let brew = CurrentInstallation.shared.homebrew?.brew,
              FileManager.default.isExecutableFile(atPath: brew.path) else { return nil }
        return brew
    }

    /// Opens a `.command` script in Terminal: upgrade, quit this Doorman, start the new one.
    private func upgradeInTerminal() {
        guard let brew = Self.brewExecutable else { return }
        let doorman = brew.deletingLastPathComponent().appendingPathComponent("doorman").path
        let script = """
        #!/bin/sh
        echo "Updating Doorman…"
        "\(brew.path)" update --quiet && "\(brew.path)" upgrade doorman || { echo; echo "Update failed."; exit 1; }
        pkill -x Doorman
        sleep 1
        "\(doorman)"
        echo; echo "Doorman updated and restarted. You can close this window."
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("doorman-update.command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            log.error("write update script: \(error.localizedDescription, privacy: .public)")
        }
    }
}
