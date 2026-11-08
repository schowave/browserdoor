import Foundation

/// Which URLs Doorman hands to browsers.
///
/// URLs end up as command-line arguments (`zen --space … <url>`, `open --args … <url>`),
/// so anything that is not a plain web or file URL — e.g. a `.webloc` containing
/// `--remote-debugging-port=9222`, or `javascript:` — must never get through.
public enum URLPolicy {
    public static let allowedSchemes: Set<String> = ["http", "https", "file"]

    public static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else { return false }
        return !url.absoluteString.hasPrefix("-")
    }

    public static func filter(_ urls: [URL]) -> [URL] {
        urls.filter(isAllowed)
    }
}
