import AppKit
import BrowserdoorCore

/// Localized string from the app bundle's `Localizable.strings`. Keys are the English text,
/// so a missing translation falls back to English.
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Localized format string, e.g. `L("Version %@", version)`.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
}

enum RunningApp {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }
}

/// Default-browser status and registration.
@MainActor
enum DefaultBrowser {
    static var isBrowserdoor: Bool {
        guard
            let probe = URL(string: "https://example.com"),
            let handler = NSWorkspace.shared.urlForApplication(toOpen: probe)
        else { return false }
        return Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// macOS asks the user to confirm; `completion` runs on the main actor afterwards.
    static func makeBrowserdoor(completion: (@MainActor () -> Void)? = nil) {
        let app = Bundle.main.bundleURL
        NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "http") { error in
            if let error {
                log.error("set default browser: \(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor in completion?() }
        }
        NSWorkspace.shared.setDefaultApplication(at: app, toOpen: .html) { error in
            if let error {
                log.error("set html handler: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
