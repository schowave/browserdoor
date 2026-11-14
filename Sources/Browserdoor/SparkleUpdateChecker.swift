#if SPARKLE
    import AppKit
    import BrowserdoorCore
    import Sparkle

    /// The download (DMG) build's updater: Sparkle reads the appcast attached to the latest GitHub
    /// release, checks the update's EdDSA signature, shows the release notes, replaces the app and
    /// restarts it. Its callbacks become `UpdateCycleEvent`s, and `UpdateStatus.after` decides what
    /// the menu and the settings show. Dev builds never start it.
    @MainActor @Observable
    final class UpdateChecker: NSObject {
        static let shared = UpdateChecker()

        private(set) var status: UpdateStatus = .idle

        /// The same setting as in the Homebrew build (same defaults key); Sparkle follows it.
        var automatic: Bool {
            didSet {
                preferences.checksAutomatically = automatic
                controller?.updater.automaticallyChecksForUpdates = automatic
            }
        }

        @ObservationIgnored private let preferences = UserDefaultsUpdatePreferences()
        @ObservationIgnored private var controller: SPUStandardUpdaterController?

        override private init() {
            automatic = preferences.checksAutomatically
            super.init()
        }

        /// Starts Sparkle; it checks on its own schedule (daily) while `automatic` is on.
        func startAutomaticChecks() {
            guard controller == nil, BundleIdentity.isRelease(AppIdentity.bundleId) else { return }
            let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
            controller.updater.automaticallyChecksForUpdates = automatic
            controller.startUpdater()
            self.controller = controller
        }

        /// A check the user asked for: Sparkle shows the result in its own window. While it can't
        /// start one (an update is already on screen, or it failed to start), `checkForUpdates`
        /// brings its window back or does nothing, and the status stays as it is. `async` only to
        /// match `UpdateChecking`; Sparkle reports back through the delegate.
        func checkNow() async {
            guard let controller else {
                NSApp.activate()
                let alert = NSAlert()
                alert.messageText = L("Development builds don't update themselves.")
                alert.runModal()
                return
            }
            if controller.updater.canCheckForUpdates {
                handle(.started)
            }
            controller.checkForUpdates(nil)
        }

        fileprivate func handle(_ event: UpdateCycleEvent) {
            status = status.after(event)
        }
    }

    extension UpdateChecker: SPUUpdaterDelegate {
        nonisolated func updater(_: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
            let version = item.displayVersionString
            MainActor.assumeIsolated { handle(.found(version: version)) }
        }

        nonisolated func updaterDidNotFindUpdate(_: SPUUpdater) {
            MainActor.assumeIsolated { handle(.notFound) }
        }

        nonisolated func updater(_: SPUUpdater, userDidMake choice: SPUUserUpdateChoice, forUpdate _: SUAppcastItem,
                                 state _: SPUUserUpdateState)
        {
            guard choice == .skip else { return }
            MainActor.assumeIsolated { handle(.skipped) }
        }

        /// Called at the end of every check, also one the user cancelled. Sparkle reports "nothing
        /// new" as `SUNoUpdateError` here.
        nonisolated func updater(_: SPUUpdater, didFinishUpdateCycleFor _: SPUUpdateCheck, error: Error?) {
            let error = error as NSError?
            let noUpdate = error?.domain == SUSparkleErrorDomain && error?.code == Int(SUError.noUpdateError.rawValue)
            let message = error?.localizedDescription
            MainActor.assumeIsolated { handle(noUpdate ? .notFound : .finished(error: message)) }
        }
    }

    /// Browserdoor runs in the background (menu bar only), so a scheduled check that finds an update
    /// would open Sparkle's window behind other apps. Like the Homebrew build's dialog, it comes to
    /// the front first.
    extension UpdateChecker: SPUStandardUserDriverDelegate {
        nonisolated var supportsGentleScheduledUpdateReminders: Bool {
            true
        }

        nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
            if !immediateFocus {
                MainActor.assumeIsolated { NSApp.activate() }
            }
            return true
        }
    }
#endif
