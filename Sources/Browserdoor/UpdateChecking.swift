import BrowserdoorCore

/// What the menu, the settings and the app delegate need from the updater. Each build compiles one
/// `UpdateChecker`: the Homebrew build's (`UpdateChecker.swift`, `brew upgrade` in Terminal) or the
/// download build's (`SparkleUpdateChecker.swift`). The conformance below makes the compiler check
/// that both keep this surface.
@MainActor
protocol UpdateChecking: AnyObject {
    var status: UpdateStatus { get }
    var automatic: Bool { get set }
    /// Called once at launch.
    func startAutomaticChecks()
    /// A check the user asked for; its result is always shown.
    func checkNow() async
}

extension UpdateChecker: UpdateChecking {}
