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

        /// Sparkle keeps this setting itself; on by default through `SUEnableAutomaticChecks`.
        var automatic = true {
            didSet { controller?.updater.automaticallyChecksForUpdates = automatic }
        }

        @ObservationIgnored private var controller: SPUStandardUpdaterController?

        override private init() {
            super.init()
        }

        /// Starts Sparkle; it checks on its own schedule (daily) while `automatic` is on.
        func startAutomaticChecks() {
            guard controller == nil, BundleIdentity.isRelease(AppIdentity.bundleId) else { return }
            let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
            self.controller = controller
            automatic = controller.updater.automaticallyChecksForUpdates
        }

        /// A check the user asked for: Sparkle shows the result in its own window. `async` only to
        /// match `UpdateChecking`; Sparkle reports back through the delegate.
        func checkNow() async {
            guard let controller else {
                NSApp.activate()
                let alert = NSAlert()
                alert.messageText = L("Development builds don't update themselves.")
                alert.runModal()
                return
            }
            handle(.started)
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
#endif
