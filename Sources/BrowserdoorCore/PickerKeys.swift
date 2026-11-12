/// Modifier keys, independent of AppKit so key handling can be tested.
public struct KeyModifiers: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let shift = KeyModifiers(rawValue: 1 << 3)
    /// Caps Lock, Fn and similar keys that must not change what a shortcut means.
    public static let ignorable = KeyModifiers(rawValue: 1 << 4)
}

enum PickerKeyAction: Equatable, Sendable {
    case cancel
    case confirm
    case moveUp
    case moveDown
    case moveFirst
    case moveLast
    case copy
    case settings
    case pick(Int)
    case ignore
}

/// Maps a key press in the picker to what it should do.
enum PickerKeys {
    static let escape: UInt16 = 53
    static let returnKey: UInt16 = 36
    static let enter: UInt16 = 76
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125
    static let tab: UInt16 = 48
    static let home: UInt16 = 115
    static let end: UInt16 = 119

    /// - Parameters:
    ///   - characters: the key's characters ignoring modifiers (`NSEvent.charactersIgnoringModifiers`).
    ///   - hotkeys: the hotkey of each row, in row order.
    static func action(
        keyCode: UInt16, characters: String?, modifiers: KeyModifiers, hotkeys: [Character?]
    ) -> PickerKeyAction {
        switch keyCode {
        case escape: return .cancel
        case returnKey, enter: return .confirm
        case upArrow: return .moveUp
        case downArrow: return .moveDown
        case home: return .moveFirst
        case end: return .moveLast
        case tab:
            switch modifiers.subtracting(.ignorable) {
            case []: return .moveDown
            case .shift: return .moveUp
            default: return .ignore
            }
        default: break
        }
        guard let characters = characters?.lowercased(), characters.count == 1, let key = characters.first else {
            return .ignore
        }
        let relevant = modifiers.subtracting(.ignorable)
        if relevant == .command, key == "c" {
            return .copy
        }
        if relevant == .command, key == "," {
            return .settings
        }
        guard relevant.isDisjoint(with: [.command, .control, .option]) else { return .ignore }
        if let index = hotkeys.firstIndex(where: { $0 == key }) {
            return .pick(index)
        }
        return .ignore
    }
}
