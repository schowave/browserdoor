import Foundation

/// How the picker names a link: the part that decides where it goes (the host, or a file's
/// name) prominently, the rest quietly. A host shows as Foundation parsed it, so a name with
/// non-ASCII letters appears in Punycode (`xn--…`) and a look-alike such as `аpple.com` with a
/// Cyrillic а doesn't pass for the real one. User info (`https://bank.com@evil.io`) isn't shown.
/// A host whose decoded form has characters a host name can't have (`apple.com%2Fsignin.evil.io`)
/// stays percent-encoded, so it can't fake a path or user info.
public struct LinkDisplay: Equatable, Sendable {
    /// Host (with port), or the file name.
    public var primary: String
    /// Path, query and fragment; for a file its folder, `~` for the home folder.
    public var secondary: String

    public init(primary: String, secondary: String) {
        self.primary = primary
        self.secondary = secondary
    }

    public init(_ url: URL, home: URL) {
        if url.isFileURL {
            let path = url.path(percentEncoded: false)
            let folder = (path as NSString).deletingLastPathComponent
            let homePath = home.path(percentEncoded: false).trimmingSuffix("/")
            let shown = folder == homePath || folder.hasPrefix(homePath + "/")
                ? "~" + folder.dropFirst(homePath.count)
                : folder
            self.init(primary: (path as NSString).lastPathComponent, secondary: shown)
            return
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let decoded = url.host(percentEncoded: false), !decoded.isEmpty
        else {
            self.init(primary: url.absoluteString, secondary: "")
            return
        }
        let plain = decoded.unicodeScalars.allSatisfy(Self.hostCharacters.contains)
        let shown = plain ? decoded : (url.host(percentEncoded: true) ?? decoded)
        let host = plain && decoded.contains(":") ? "[\(decoded)]" : shown
        var rest = components.percentEncodedPath
        if let query = components.percentEncodedQuery {
            rest += "?" + query
        }
        if let fragment = components.percentEncodedFragment {
            rest += "#" + fragment
        }
        self.init(primary: url.port.map { "\(host):\($0)" } ?? host,
                  secondary: rest == "/" ? "" : rest)
    }

    /// What a host name (or an IPv6 address) consists of after IDNA: ASCII letters, digits,
    /// `-`, `.`, `_` and `:`.
    static let hostCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._:")

    /// One line, e.g. for a tooltip.
    public var line: String {
        primary + secondary
    }
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) && count > suffix.count ? String(dropLast(suffix.count)) : self
    }
}
