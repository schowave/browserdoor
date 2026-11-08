import Foundation

/// A Zen workspace ("space") as stored in `zen-sessions.jsonlz4`.
public struct ZenSpace: Equatable, Sendable {
    /// UUID including braces, e.g. `{3d0f4d74-...}`, exactly as Zen stores it.
    public var uuid: String
    public var name: String
    /// `chrome://…/selectable/<name>.svg`, an emoji, or nil.
    public var icon: String?
    /// Primary theme color as RGB 0–255, if the space has one.
    public var color: RGB?

    public init(uuid: String, name: String, icon: String? = nil, color: RGB? = nil) {
        self.uuid = uuid
        self.name = name
        self.icon = icon
        self.color = color
    }

    /// Icon file name if `icon` points to one of Zen's bundled SVGs.
    public var bundledIconName: String? {
        guard let icon, icon.hasPrefix("chrome://"), icon.hasSuffix(".svg") else { return nil }
        return icon.split(separator: "/").last.map(String.init)
    }

    /// `icon` if it is an emoji (or any non-URL text).
    public var emojiIcon: String? {
        guard let icon, !icon.isEmpty, !icon.contains("://") else { return nil }
        return icon
    }
}

public struct RGB: Equatable, Sendable {
    public var r: Int, g: Int, b: Int
    public init(_ r: Int, _ g: Int, _ b: Int) { (self.r, self.g, self.b) = (r, g, b) }
}

public enum ZenSpaces {
    public static let sessionFileName = "zen-sessions.jsonlz4"

    public static func load(profileDirectory: URL) throws -> [ZenSpace] {
        let data = try Data(contentsOf: profileDirectory.appendingPathComponent(sessionFileName))
        return try parse(sessionJSON: MozLz4.decompress(data))
    }

    public static func parse(sessionJSON: Data) throws -> [ZenSpace] {
        try JSONDecoder().decode(Session.self, from: sessionJSON).spaces.map { space in
            let colors = space.theme?.gradientColors ?? []
            let primary = colors.first(where: { $0.isPrimary == true }) ?? colors.first
            let rgb = primary.flatMap { $0.c.count == 3 ? RGB($0.c[0], $0.c[1], $0.c[2]) : nil }
            return ZenSpace(uuid: space.uuid, name: space.name, icon: space.icon, color: rgb)
        }
    }

    private struct Session: Decodable {
        var spaces: [Space]

        private enum CodingKeys: String, CodingKey { case spaces }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            spaces = try c.decodeIfPresent([Space].self, forKey: .spaces) ?? []
        }
    }

    private struct Space: Decodable {
        var uuid: String
        var name: String
        var icon: String?
        var theme: Theme?
    }

    private struct Theme: Decodable {
        var gradientColors: [GradientColor]?
    }

    private struct GradientColor: Decodable {
        var c: [Int]
        var isPrimary: Bool?
    }
}
