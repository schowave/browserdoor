import Foundation

/// Which targets exist, what they're called, which key opens them, and how edits are saved.
/// The one place the picker and the settings window get their target list from.
///
/// Reads `~/.config/browserdoor/config.json` (missing = defaults; unreadable = defaults, flagged),
/// resolves the Zen profile override, discovers targets and applies the config.
public struct TargetCatalog {
    public var environment: BrowserEnvironment
    public var configURL: URL

    public init(environment: BrowserEnvironment, configURL: URL? = nil) {
        self.environment = environment
        self.configURL = configURL ?? Config.fileURL(home: environment.home)
    }

    public func load() -> CatalogState {
        let config: Config
        let unreadable: Bool
        do {
            config = try Config.load(from: configURL)
            unreadable = false
        } catch {
            config = Config()
            unreadable = true
        }
        return CatalogState(base: config, targets: discover(config), configIsUnreadable: unreadable)
    }

    /// Writes the edits. Re-discovers when the edit changes what can be discovered (extra apps,
    /// Zen profile); returns the state to continue editing with.
    @discardableResult
    public func save(_ state: CatalogState) throws -> CatalogState {
        let config = state.config
        try config.save(to: configURL)
        let rediscover = config.extraApps != state.base.extraApps || config.zen != state.base.zen
        let targets = rediscover ? discover(config) : state.targets
        return CatalogState(base: config, targets: targets, configIsUnreadable: false)
    }

    private func discover(_ config: Config) -> [Target] {
        let profile = config.zen?.profilePath.map { path -> URL in
            let expanded = path.hasPrefix("~/")
                ? environment.home.appendingPathComponent(String(path.dropFirst(2))).path
                : path
            return URL(fileURLWithPath: expanded, isDirectory: true)
        }
        return Discovery(environment: environment, zenProfileOverride: profile, extraApps: config.extraApps ?? [])
            .discover()
    }
}

/// A loaded catalog plus pending edits. Change it through the edits below, read the derived
/// values, hand it to `TargetCatalog.save`.
public struct CatalogState {
    /// Every discovered target, hidden ones included.
    public private(set) var targets: [Target]
    /// Editable rows in picker order, hidden ones included.
    public internal(set) var rows: [TargetSetting]
    public internal(set) var defaultTarget: String?
    /// Bundle IDs of apps the user added.
    public internal(set) var extraApps: [String]
    public internal(set) var zenProfilePath: String?
    /// The config file exists but couldn't be parsed; defaults are in use and saving replaces it.
    public let configIsUnreadable: Bool

    let base: Config

    init(base: Config, targets: [Target], configIsUnreadable: Bool) {
        self.base = base
        self.targets = targets
        self.configIsUnreadable = configIsUnreadable
        rows = base.settings(for: targets)
        defaultTarget = base.defaultTarget
        extraApps = base.extraApps ?? []
        zenProfilePath = base.zen?.profilePath
    }

    /// The config these edits amount to.
    var config: Config {
        var config = base
        config.apply(rows)
        config.defaultTarget = defaultTarget
        config.extraApps = extraApps
        config.zen = zenProfilePath.map { Config.Zen(profilePath: $0) }
        return config
    }

    static let autoHotkeys: [Character] = Array("1234567890")

    /// What the picker shows: the visible rows, labelled, with hotkeys. A custom key stays only on
    /// the first row that has it; rows without one get the free number keys in order.
    public var pickerEntries: [PickerEntry] {
        var used = Set<Character>()
        var entries = rows.filter { !$0.hidden }.map { row in
            PickerEntry(target: row.target, label: row.displayName,
                        hotkey: row.hotkey.flatMap { used.insert($0).inserted ? $0 : nil })
        }
        var free = Self.autoHotkeys.filter { !used.contains($0) }.makeIterator()
        for i in entries.indices where entries[i].hotkey == nil {
            guard let key = free.next() else { break }
            entries[i].hotkey = key
        }
        return entries
    }

    /// The entry `Enter` opens: the default target if it is visible, else the first.
    public var defaultIndex: Int? {
        defaultIndex(in: pickerEntries)
    }

    /// `defaultIndex` for entries already taken from `pickerEntries`.
    func defaultIndex(in entries: [PickerEntry]) -> Int? {
        guard !entries.isEmpty else { return nil }
        return defaultTarget.flatMap { id in entries.firstIndex { $0.id == id } } ?? 0
    }

    /// The key each visible target gets in the picker (custom or automatic), by target ID.
    public var effectiveKeys: [String: Character] {
        Self.keys(of: pickerEntries)
    }

    static func keys(of entries: [PickerEntry]) -> [String: Character] {
        Dictionary(entries.compactMap { entry in entry.hotkey.map { (entry.id, $0) } },
                   uniquingKeysWith: { first, _ in first })
    }
}

/// Edits as the settings window makes them. Each keeps the config's rules (a name equal to the
/// detected one is no rename, a hotkey is one lowercase key, an app is added once).
public extension CatalogState {
    /// Renames a target; an empty name or the detected one removes the custom name.
    mutating func rename(_ id: String, to name: String) {
        edit(id) { row in row.label = (name.isEmpty || name == row.target.name) ? nil : name }
    }

    /// Sets a target's key from what was typed (the last character); empty removes it. A key
    /// belongs to one target: another target that had it loses it.
    /// - Returns: the display name of the target the picker showed the key on before, if another.
    @discardableResult
    mutating func setHotkey(_ id: String, typed input: String) -> String? {
        let key = TargetSetting.normalizeHotkey(input)
        let previous = key.flatMap { key in
            effectiveKeys.first { $0.key != id && $0.value == key }.flatMap { holder in
                rows.first { $0.id == holder.key }?.displayName
            }
        }
        if let key {
            for i in rows.indices where rows[i].id != id && rows[i].hotkey == key {
                rows[i].hotkey = nil
            }
        }
        edit(id) { row in row.hotkey = key }
        return previous
    }

    mutating func setHidden(_ id: String, _ hidden: Bool) {
        edit(id) { row in row.hidden = hidden }
    }

    /// Makes a target the one `Enter` opens, or, if it already is, removes the default.
    mutating func toggleDefault(_ id: String) {
        defaultTarget = defaultTarget == id ? nil : id
    }

    /// Adds apps by bundle ID, each once.
    mutating func addExtraApps(_ bundleIds: [String]) {
        for id in bundleIds where !extraApps.contains(id) {
            extraApps.append(id)
        }
    }

    mutating func removeExtraApp(_ bundleId: String) {
        extraApps.removeAll { $0 == bundleId }
    }

    /// Apps the user added that no target stands for: uninstalled ones, or a browser whose
    /// targets are its profiles. The settings list them so they can still be removed.
    var unlistedExtraApps: [String] {
        let listed = Set(rows.map(\.id))
        return extraApps.filter { !listed.contains(TargetID.app(bundleId: $0).string) }
    }

    /// The bundle ID behind a target the user added as an extra app (removable with −).
    func extraApp(forTarget id: String) -> String? {
        guard case let .app(bundleId) = TargetID(id), extraApps.contains(bundleId) else { return nil }
        return bundleId
    }

    /// Moves rows as a list's drag and drop reports it: `destination` is an offset in the list
    /// before the move. Same rules as SwiftUI's `MutableCollection.move(fromOffsets:toOffset:)`,
    /// which `List.onMove` assumes (a test compares the two).
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let offsets = source.sorted().filter(rows.indices.contains)
        let moving = offsets.map { rows[$0] }
        for offset in offsets.reversed() {
            rows.remove(at: offset)
        }
        let target = max(0, destination) - offsets.filter { $0 < destination }.count
        rows.insert(contentsOf: moving, at: min(target, rows.count))
    }

    /// Uses another Zen profile's spaces; nil or empty goes back to Zen's default profile.
    mutating func setZenProfile(_ path: String?) {
        zenProfilePath = path.flatMap { $0.isEmpty ? nil : $0 }
    }

    private mutating func edit(_ id: String, _ change: (inout TargetSetting) -> Void) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        change(&rows[index])
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
