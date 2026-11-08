import Foundation

/// User configuration, `~/.config/doorman/config.json`. Every field is optional.
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
        home.appendingPathComponent(".config/doorman/config.json")
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

    /// A starter config listing every currently discovered target with its name as label.
    public static func template(for targets: [Target]) throws -> Data {
        let config = Config(
            order: targets.map(\.id),
            hidden: [],
            extraApps: [],
            targets: Dictionary(targets.map { ($0.id, TargetOverride(label: $0.name)) }, uniquingKeysWith: { first, _ in first })
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(config)
    }
}

/// A target as shown in the picker, with config applied.
public struct PickerEntry: Equatable, Sendable, Identifiable {
    public var target: Target
    public var label: String
    public var hotkey: Character?
    public var id: String {
        target.id
    }
}

public extension Config {
    internal static let autoHotkeys: [Character] = Array("1234567890")

    /// Orders, filters, labels and assigns hotkeys.
    func entries(for discovered: [Target]) -> [PickerEntry] {
        let hiddenSet = Set(hidden ?? [])
        let sorted = ordered(discovered).filter { !hiddenSet.contains($0.id) }

        var entries = sorted.map { target in
            let override = targets?[target.id]
            let label = override?.label.flatMap { $0.isEmpty ? nil : $0 } ?? target.name
            let hotkey = override?.hotkey.flatMap { $0.count == 1 ? Character($0.lowercased()) : nil }
            return PickerEntry(target: target, label: label, hotkey: hotkey)
        }

        // Explicit hotkeys win; a duplicate explicit hotkey stays only on the first entry.
        var used = Set<Character>()
        for i in entries.indices {
            if let key = entries[i].hotkey {
                if used.contains(key) {
                    entries[i].hotkey = nil
                } else {
                    used.insert(key)
                }
            }
        }
        var free = Self.autoHotkeys.filter { !used.contains($0) }.makeIterator()
        for i in entries.indices where entries[i].hotkey == nil {
            guard let key = free.next() else { break }
            entries[i].hotkey = key
        }
        return entries
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

    /// Index of the entry preselected for Enter.
    func defaultIndex(in entries: [PickerEntry]) -> Int? {
        guard !entries.isEmpty else { return nil }
        if let id = defaultTarget, let index = entries.firstIndex(where: { $0.id == id }) {
            return index
        }
        return 0
    }
}
