@testable import BrowserdoorCore
import Foundation
import Testing

struct PickerSessionTests {
    let a = URL(string: "https://a.example")!
    let b = URL(string: "https://b.example")!

    let entries: [PickerEntry] = [("w", "1"), ("c", "2"), ("p", "p"), ("s", nil)].map { id, key in
        PickerEntry(target: Target(id: id, name: id, kind: .app(URL(fileURLWithPath: "/Applications/\(id).app"))),
                    label: id, hotkey: key)
    }

    func session(default index: Int? = nil) -> PickerSession {
        PickerSession(links: [a], entries: entries, defaultIndex: index)
    }

    func key(_ code: UInt16, _ chars: String?, _ modifiers: KeyModifiers = []) -> PickerInput {
        .key(keyCode: code, characters: chars, modifiers: modifiers)
    }

    @Test func startsOnTheDefaultTarget() {
        #expect(session(default: 2).selection == 2)
        #expect(session(default: 9).selection == 0)
        #expect(session().selection == 0)
    }

    @Test func enterOpensTheSelection() {
        var s = session(default: 1)
        #expect(s.handle(key(36, "\r")) == [.close, .open([a], in: entries[1].target)])
    }

    @Test func arrowsWrapAround() {
        var s = session()
        #expect(s.handle(key(126, nil)) == [])
        #expect(s.selection == 3)
        _ = s.handle(key(125, nil))
        #expect(s.selection == 0)
    }

    @Test func hotkeysPickTheirRow() {
        var s = session()
        #expect(s.handle(key(35, "p")) == [.close, .open([a], in: entries[2].target)])
        #expect(s.handle(key(35, "P", .shift)) == [.close, .open([a], in: entries[2].target)])
        #expect(s.handle(key(0, "a")) == nil)
    }

    @Test func capsLockDoesNotBreakShortcuts() {
        var s = session()
        #expect(s.handle(key(8, "c", [.command, .ignorable])) == [.copy(a.absoluteString)])
        #expect(s.handle(key(35, "p", .ignorable)) == [.close, .open([a], in: entries[2].target)])
    }

    @Test func modifiedKeysAreNotTheSessions() {
        var s = session()
        #expect(s.handle(key(18, "1", .command)) == nil)
        #expect(s.handle(key(18, "1", .control)) == nil)
        #expect(s.handle(key(18, "1", .option)) == nil)
        #expect(s.handle(key(8, "c", [.command, .shift])) == nil)
    }

    @Test func escapeAndLostFocusClose() {
        var s = session()
        #expect(s.handle(key(53, "\u{1b}")) == [.close])
        #expect(s.handle(.lostFocus) == [.close])
    }

    @Test func clickAndHover() {
        var s = session()
        #expect(s.handle(.hover(row: 3, pointer: .zero)) == [])
        #expect(s.selection == 3)
        #expect(s.handle(.hover(row: 99, pointer: .zero)) == [])
        #expect(s.selection == 3)
        #expect(s.handle(.click(row: 1)) == [.close, .open([a], in: entries[1].target)])
        #expect(s.handle(.click(row: 99)) == [])
    }

    @Test func linksArrivingLaterJoinTheSession() {
        var s = session()
        s.add([b, a])
        #expect(s.links == [a, b])
        #expect(s.handle(.copyButton) == [.copy("\(a.absoluteString)\n\(b.absoluteString)")])
        #expect(s.copied)
        #expect(s.handle(.click(row: 0)) == [.close, .open([a, b], in: entries[0].target)])
    }

    @Test func emptyPickerDoesNothing() {
        var s = PickerSession(links: [a], entries: [], defaultIndex: nil)
        #expect(s.handle(key(36, "\r")) == [])
        #expect(s.handle(key(125, nil)) == [])
    }

    @Test func takesRowsDefaultAndWarningFromTheCatalog() {
        let targets = entries.map(\.target)
        let catalog = CatalogState(base: Config(defaultTarget: "p", hidden: ["c"]), targets: targets, configIsUnreadable: true)
        let s = PickerSession(links: [a], catalog: catalog)
        #expect(s.entries.map(\.id) == ["w", "p", "s"])
        #expect(s.selection == 1)
        #expect(s.configIsUnreadable)
    }

    @Test func hoverSelectsOnlyOnceTheMouseMoved() {
        var s = PickerSession(links: [a], entries: entries, defaultIndex: 2, pointer: CGPoint(x: 100, y: 100))
        _ = s.handle(.hover(row: 0, pointer: CGPoint(x: 100, y: 100)))
        _ = s.handle(.hover(row: 0, pointer: CGPoint(x: 101, y: 100)))
        #expect(s.selection == 2)
        _ = s.handle(.hover(row: 0, pointer: CGPoint(x: 100, y: 103)))
        #expect(s.selection == 0)
        // Once it has moved, the pointer may come back to where it started.
        _ = s.handle(.hover(row: 1, pointer: CGPoint(x: 100, y: 100)))
        #expect(s.selection == 1)
    }

    @Test func tabHomeAndEndMoveTheSelection() {
        var s = session(default: 1)
        _ = s.handle(key(48, "\t"))
        #expect(s.selection == 2)
        _ = s.handle(key(48, "\t", .shift))
        #expect(s.selection == 1)
        #expect(s.handle(key(48, "\t", .option)) == nil)
        _ = s.handle(key(119, nil, .ignorable))
        #expect(s.selection == 3)
        _ = s.handle(key(115, nil, .ignorable))
        #expect(s.selection == 0)
    }

    @Test func commandCommaAndTheEmptyStateButtonOpenTheSettings() {
        var s = session()
        #expect(s.handle(key(43, ",", .command)) == [.close, .openSettings])
        var empty = PickerSession(links: [a], entries: [], defaultIndex: nil)
        #expect(empty.handle(.settingsButton) == [.close, .openSettings])
        #expect(empty.handle(key(115, nil)) == [])
    }

    @Test func remembersTheDefaultRow() {
        #expect(session(default: 2).defaultRow == 2)
        #expect(session(default: 9).defaultRow == nil)
        #expect(session().defaultRow == nil)
    }
}
