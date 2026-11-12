import Foundation

/// User configuration, `~/.config/browserdoor/config.json`. Every field is optional.
public struct Config: Codable, Equatable, Sendable {
    public struct TargetOverride: Codable, Equatable, Sendable {
        public var label: String?
        public var hotkey: String?
        public init(label: String? = nil, hotkey: String? = nil) {
            self.label = label
            self.hotkey = hotkey
        }
    }

    public struct Zen: Codable, Equatable, Sendable {
        public var profilePath: String?
        public init(profilePath: String? = nil) {
            self.profilePath = profilePath
        }
    }

    public var defaultTarget: String?
    public var order: [String]?
    public var hidden: [String]?
    /// Bundle IDs of non-browser apps to offer as targets too.
    public var extraApps: [String]?
    public var targets: [String: TargetOverride]?
    public var zen: Zen?

    public init(
        defaultTarget: String? = nil,
        order: [String]? = nil,
        hidden: [String]? = nil,
        extraApps: [String]? = nil,
        targets: [String: TargetOverride]? = nil,
        zen: Zen? = nil
    ) {
        self.defaultTarget = defaultTarget
        self.order = order
        self.hidden = hidden
        self.extraApps = extraApps
        self.targets = targets
        self.zen = zen
    }

    public static func fileURL(home: URL) -> URL {
        home.appendingPathComponent(".config/browserdoor/config.json")
    }

    /// Missing file → empty config. Malformed file → throws, so the user gets told.
    public static func load(from url: URL) throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return Config() }
        return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
    }

    /// Writes the config as pretty, key-sorted JSON (stable diffs for dotfiles), atomically.
    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

extension Config {
    /// A label that differs from the detected name, or nil.
    static func customLabel(_ label: String?, detected: String) -> String? {
        guard let label, !label.isEmpty, label != detected else { return nil }
        return label
    }

    /// A single-character hotkey, lowercased, or nil.
    static func customHotkey(_ hotkey: String?) -> Character? {
        guard let hotkey, hotkey.count == 1, let key = hotkey.lowercased().first else { return nil }
        return key
    }

    /// `discovered` in config order: listed IDs first, the rest in discovery order.
    func ordered(_ discovered: [Target]) -> [Target] {
        let rank = Dictionary((order ?? []).enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return discovered.enumerated().sorted { a, b in
            switch (rank[a.element.id], rank[b.element.id]) {
            case let (ra?, rb?): ra < rb
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.offset < b.offset
            }
        }.map(\.element)
    }
}
