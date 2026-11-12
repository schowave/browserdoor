import Foundation

/// The small lettered circle on a target's icon that tells apart targets of the same app
/// (Chromium and Firefox profiles, a browser's several installs). Zen spaces have their own
/// glyph and color and get none; neither does an app that appears only once.
public struct ProfileBadge: Equatable, Sendable {
    public var letter: String
    public var color: RGB

    /// Colors that carry white text and stand out on app icons, in light and dark mode.
    static let palette: [RGB] = [
        RGB(0xD9, 0x3A, 0x3A), RGB(0xE0, 0x7A, 0x10), RGB(0x2E, 0x9E, 0x4F), RGB(0x16, 0x8C, 0x8C),
        RGB(0x2F, 0x6F, 0xDB), RGB(0x6E, 0x4B, 0xD8), RGB(0xC2, 0x3E, 0x9E), RGB(0x6B, 0x72, 0x80),
    ]

    /// Badges by target ID for the targets as listed, each with its display name.
    public static func badges(for targets: [(target: Target, label: String)]) -> [String: ProfileBadge] {
        let eligible = targets.filter { !($0.target.kind is ZenSpaceKind) }
        let perApp = Dictionary(grouping: eligible, by: { $0.target.appURL.standardizedFileURL })
        var result: [String: ProfileBadge] = [:]
        for group in perApp.values where group.count > 1 {
            for (target, label) in group {
                result[target.id] = ProfileBadge(letter: initial(of: label), color: color(for: target.id))
            }
        }
        return result
    }

    /// The first letter or digit of the profile's part of the name ("Firefox › Work" → "W"),
    /// uppercased; "?" if it has none.
    static func initial(of name: String) -> String {
        let profile = name.components(separatedBy: " › ").last ?? name
        return profile.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
    }

    /// The same color for a target ID on every launch (FNV-1a; Swift's `hashValue` is seeded).
    static func color(for id: String) -> RGB {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in id.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return palette[Int(hash % UInt64(palette.count))]
    }
}
