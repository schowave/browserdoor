import Foundation

/// What the user does in the picker.
public enum PickerInput: Equatable, Sendable {
    /// A key press: `characters` ignoring modifiers (`NSEvent.charactersIgnoringModifiers`).
    case key(keyCode: UInt16, characters: String?, modifiers: KeyModifiers)
    case click(row: Int)
    case hover(row: Int)
    case copyButton
    /// The panel lost keyboard focus (click outside).
    case lostFocus
}

/// What the picker's host has to do, in order.
public enum PickerEffect: Equatable, Sendable {
    case close
    case open([URL], in: Target)
    case copy(String)
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

    public init(links: [URL], entries: [PickerEntry], defaultIndex: Int?, configIsUnreadable: Bool = false) {
        self.links = links
        self.entries = entries
        self.configIsUnreadable = configIsUnreadable
        selection = defaultIndex.flatMap { entries.indices.contains($0) ? $0 : nil } ?? 0
    }

    public init(links: [URL], catalog: CatalogState) {
        let entries = catalog.pickerEntries
        self.init(links: links, entries: entries, defaultIndex: catalog.defaultIndex(in: entries),
                  configIsUnreadable: catalog.configIsUnreadable)
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
            case .copy: return copy()
            case let .pick(row): return pick(row)
            }
            return []
        case let .click(row):
            return pick(row)
        case let .hover(row):
            if entries.indices.contains(row) {
                selection = row
            }
            return []
        case .copyButton:
            return copy()
        case .lostFocus:
            return [.close]
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
