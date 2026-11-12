import CoreGraphics
import Foundation

/// What the user does in the picker.
public enum PickerInput: Equatable, Sendable {
    /// A key press: `characters` ignoring modifiers (`NSEvent.charactersIgnoringModifiers`).
    case key(keyCode: UInt16, characters: String?, modifiers: KeyModifiers)
    case click(row: Int)
    /// The mouse is over a row, at `pointer` (screen coordinates).
    case hover(row: Int, pointer: CGPoint)
    case copyButton
    /// The settings button of an empty picker.
    case settingsButton
    /// The panel lost keyboard focus (click outside).
    case lostFocus
}

/// What the picker's host has to do, in order.
public enum PickerEffect: Equatable, Sendable {
    case close
    case open([URL], in: Target)
    case copy(String)
    /// Show the settings window (on its targets tab).
    case openSettings
}

/// One appearance of the picker: the links waiting to be opened, the targets on offer and the
/// selection. Turns input into effects; the host only renders and performs them.
public struct PickerSession: Equatable, Sendable {
    public private(set) var links: [URL]
    public let entries: [PickerEntry]
    public private(set) var selection: Int
    /// The links were copied during this session (the copy button shows a checkmark).
    public private(set) var copied = false
    /// The config couldn't be read and defaults are in use; the picker says so.
    public let configIsUnreadable: Bool
    /// The row `Enter` opens until the selection moves; it carries the ↩ mark.
    public let defaultRow: Int?
    /// Profile badges by target ID (see `ProfileBadge`).
    public let badges: [String: ProfileBadge]
    /// Where the mouse was when the picker opened. Hover only selects once it has moved away, so
    /// a pointer that happens to rest on a row doesn't override the default.
    private let openingPointer: CGPoint?
    private var pointerMoved = false

    public init(links: [URL], entries: [PickerEntry], defaultIndex: Int?, configIsUnreadable: Bool = false,
                pointer: CGPoint? = nil)
    {
        self.links = links
        self.entries = entries
        self.configIsUnreadable = configIsUnreadable
        defaultRow = defaultIndex.flatMap { entries.indices.contains($0) ? $0 : nil }
        selection = defaultRow ?? 0
        badges = ProfileBadge.badges(for: entries.map { ($0.target, $0.label) })
        openingPointer = pointer
    }

    public init(links: [URL], catalog: CatalogState, pointer: CGPoint? = nil) {
        let entries = catalog.pickerEntries
        self.init(links: links, entries: entries, defaultIndex: catalog.defaultIndex(in: entries),
                  configIsUnreadable: catalog.configIsUnreadable, pointer: pointer)
    }

    /// More links arrived while the picker is open; one choice opens them all.
    public mutating func add(_ more: [URL]) {
        links += more.filter { !links.contains($0) }
    }

    /// Effects to perform, or nil if the input isn't the picker's (let the system handle it).
    public mutating func handle(_ input: PickerInput) -> [PickerEffect]? {
        switch input {
        case let .key(keyCode, characters, modifiers):
            let action = PickerKeys.action(
                keyCode: keyCode, characters: characters, modifiers: modifiers, hotkeys: entries.map(\.hotkey)
            )
            switch action {
            case .ignore: return nil
            case .cancel: return [.close]
            case .confirm: return pick(selection)
            case .moveUp: moveSelection(-1)
            case .moveDown: moveSelection(1)
            case .moveFirst: select(0)
            case .moveLast: select(entries.count - 1)
            case .copy: return copy()
            case .settings: return [.close, .openSettings]
            case let .pick(row): return pick(row)
            }
            return []
        case let .click(row):
            return pick(row)
        case let .hover(row, pointer):
            if !pointerMoved, let openingPointer {
                guard hypot(pointer.x - openingPointer.x, pointer.y - openingPointer.y) >= Self.moveThreshold else {
                    return []
                }
            }
            pointerMoved = true
            if entries.indices.contains(row) {
                selection = row
            }
            return []
        case .copyButton:
            return copy()
        case .settingsButton:
            return [.close, .openSettings]
        case .lostFocus:
            return [.close]
        }
    }

    /// How far (points) the mouse has to move before hover selects.
    static let moveThreshold: CGFloat = 2

    private mutating func select(_ row: Int) {
        if entries.indices.contains(row) {
            selection = row
        }
    }

    private mutating func moveSelection(_ delta: Int) {
        guard !entries.isEmpty else { return }
        selection = (selection + delta + entries.count) % entries.count
    }

    private func pick(_ row: Int) -> [PickerEffect] {
        guard entries.indices.contains(row) else { return [] }
        return [.close, .open(links, in: entries[row].target)]
    }

    private mutating func copy() -> [PickerEffect] {
        copied = true
        return [.copy(links.map(\.absoluteString).joined(separator: "\n"))]
    }
}
