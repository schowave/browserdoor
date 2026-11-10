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

/// A loaded catalog plus pending edits. Edit the `var`s, read the derived values, hand it to
/// `TargetCatalog.save`.
public struct CatalogState {
    /// Every discovered target, hidden ones included.
    public private(set) var targets: [Target]
    /// Editable rows in picker order, hidden ones included.
    public var rows: [TargetSetting]
    public var defaultTarget: String?
    /// Bundle IDs of apps the user added.
    public var extraApps: [String]
    public var zenProfilePath: String?
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

    /// What the picker shows: visible targets, labelled, with hotkeys.
    public var pickerEntries: [PickerEntry] {
        config.entries(for: targets)
    }

    /// The entry `Enter` opens.
    public var defaultIndex: Int? {
        config.defaultIndex(in: pickerEntries)
    }

    /// The key each visible target gets in the picker (custom or automatic), by target ID.
    public var effectiveKeys: [String: Character] {
        Dictionary(pickerEntries.compactMap { entry in entry.hotkey.map { (entry.id, $0) } },
                   uniquingKeysWith: { first, _ in first })
    }
}
