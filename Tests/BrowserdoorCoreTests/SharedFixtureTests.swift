@testable import BrowserdoorCore
import Foundation
import Testing

/// The fixtures in `fixtures/` are shared with the Windows app's Rust tests
/// (`windows/core/tests/shared_fixtures.rs`), so both read Zen's files the same way.
/// `fixtures/zen/zen-sessions.jsonlz4` was written by a real Zen (`contract/zen_contract.py`).
struct SharedFixtureTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures")

    private struct Expected: Decodable {
        var uuid: String
        var name: String
        var icon: String?
    }

    @Test func readsTheSessionFileZenWrote() throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("zen/zen-sessions.jsonlz4"))
        let spaces = try ZenSpaces.parse(sessionJSON: MozLz4.decompress(data))
        let expected = try JSONDecoder().decode(
            [Expected].self, from: Data(contentsOf: Self.root.appendingPathComponent("zen/spaces.json"))
        )
        #expect(spaces.map(\.uuid) == expected.map(\.uuid))
        #expect(spaces.map(\.name) == expected.map(\.name))
        #expect(spaces.map(\.emojiIcon) == expected.map(\.icon))
    }
}
