import Foundation

/// One row of the settings window's target list: a discovered target plus its user settings.
public struct TargetSetting: Equatable, Sendable, Identifiable {
    public var target: Target
    /// Custom name; nil shows the detected name.
    public var label: String?
    /// Custom single-key shortcut; nil gets an automatic number key.
    public var hotkey: String?
    public var hidden: Bool

    public var id: String {
        target.id
    }

    public var displayName: String {
        label ?? target.name
    }

    public init(target: Target, label: String? = nil, hotkey: String? = nil, hidden: Bool = false) {
        self.target = target
        self.label = label
        self.hotkey = hotkey
        self.hidden = hidden
    }

    /// Normalizes user input for the hotkey field: the last typed character, lowercased; empty → nil.
    public static func normalizeHotkey(_ input: String) -> String? {
        guard let last = input.trimmingCharacters(in: .whitespaces).last else { return nil }
        return String(last).lowercased()
    }
}

extension Config {
    /// All discovered targets in config order, hidden ones included, for editing.
    func settings(for discovered: [Target]) -> [TargetSetting] {
        let hiddenSet = Set(hidden ?? [])
        return ordered(discovered).map { target in
            let override = targets?[target.id]
            return TargetSetting(
                target: target,
                label: Config.customLabel(override?.label, detected: target.name),
                hotkey: Config.customHotkey(override?.hotkey).map(String.init),
                hidden: hiddenSet.contains(target.id)
            )
        }
    }

    /// Writes edited rows back. Settings for targets that aren't discovered right now (e.g. a
    /// Zen space while Zen's session file is unreadable) are kept, after the edited ones.
    mutating func apply(_ rows: [TargetSetting]) {
        let ids = Set(rows.map(\.id))
        order = rows.map(\.id) + (order ?? []).filter { !ids.contains($0) }

        let keptHidden = (hidden ?? []).filter { !ids.contains($0) }
        hidden = rows.filter(\.hidden).map(\.id) + keptHidden

        var overrides = (targets ?? [:]).filter { !ids.contains($0.key) }
        for row in rows where row.label != nil || row.hotkey != nil {
            overrides[row.id] = TargetOverride(label: row.label, hotkey: row.hotkey)
        }
        targets = overrides
    }
}
