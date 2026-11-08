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

    /// URLs read from a `.webloc` file: web only. A downloaded `.webloc` must not be able to
    /// open a local file (with file-origin rights) in a browser.
    public static func isAllowedFromWebloc(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && isAllowed(url)
    }

    public static func filter(_ urls: [URL]) -> [URL] {
        urls.filter(isAllowed)
    }
}
