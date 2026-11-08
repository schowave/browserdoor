@testable import DoormanCore
import Testing

struct PickerKeysTests {
    let hotkeys: [Character?] = ["1", "2", "p", nil]

    func action(_ keyCode: UInt16, _ chars: String?, _ modifiers: KeyModifiers = []) -> PickerKeyAction {
        PickerKeys.action(keyCode: keyCode, characters: chars, modifiers: modifiers, hotkeys: hotkeys)
    }

    @Test func navigationKeys() {
        #expect(action(53, "\u{1b}") == .cancel)
        #expect(action(36, "\r") == .confirm)
        #expect(action(76, "\u{3}") == .confirm)
        #expect(action(126, nil) == .moveUp)
        #expect(action(125, nil) == .moveDown)
    }

    @Test func hotkeyPresses() {
        #expect(action(18, "1") == .pick(0))
        #expect(action(35, "p") == .pick(2))
        #expect(action(35, "P", .shift) == .pick(2))
        #expect(action(0, "a") == .ignore)
    }

    @Test func capsLockDoesNotBreakShortcuts() {
        #expect(action(8, "c", [.command, .ignorable]) == .copy)
        #expect(action(35, "p", .ignorable) == .pick(2))
    }

    @Test func modifiedKeysAreNotHotkeys() {
        #expect(action(8, "c", .command) == .copy)
        #expect(action(18, "1", .command) == .ignore)
        #expect(action(18, "1", .control) == .ignore)
        #expect(action(18, "1", .option) == .ignore)
        #expect(action(8, "c", [.command, .shift]) == .ignore)
    }
}
