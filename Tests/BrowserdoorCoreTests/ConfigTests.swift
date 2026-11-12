@testable import BrowserdoorCore
import Foundation
import Testing

/// How a config turns into picker entries, through the catalog state the picker reads.
struct ConfigTests {
    let targets = ["a", "b", "c", "d"].map {
        Target(id: $0, name: $0.uppercased(), kind: .app(URL(fileURLWithPath: "/Applications/\($0).app")))
    }

    func state(_ config: Config, _ targets: [Target]? = nil) -> CatalogState {
        CatalogState(base: config, targets: targets ?? self.targets, configIsUnreadable: false)
    }

    @Test func defaultsKeepOrderAndNumberHotkeys() {
        let entries = state(Config()).pickerEntries
        #expect(entries.map(\.id) == ["a", "b", "c", "d"])
        #expect(entries.map(\.label) == ["A", "B", "C", "D"])
        #expect(entries.map(\.hotkey) == ["1", "2", "3", "4"])
    }

    @Test func orderPutsListedFirstRestInDiscoveryOrder() {
        let config = Config(order: ["c", "unknown", "a"])
        #expect(state(config).pickerEntries.map(\.id) == ["c", "a", "b", "d"])
    }

    @Test func hiddenAreRemoved() {
        #expect(state(Config(hidden: ["b"])).pickerEntries.map(\.id) == ["a", "c", "d"])
    }

    @Test func overridesLabelAndHotkey() {
        let config = Config(targets: [
            "b": .init(label: "Bee", hotkey: "B"),
            "c": .init(label: "", hotkey: "1"),
            "d": .init(hotkey: "1"), // duplicate → dropped, gets auto key
        ])
        let entries = state(config).pickerEntries
        #expect(entries.map(\.label) == ["A", "Bee", "C", "D"])
        #expect(entries.map(\.hotkey) == ["2", "b", "1", "3"])
    }

    @Test func autoHotkeysRunOut() {
        let many = (0 ..< 12).map { Target(id: "t\($0)", name: "T", kind: .app(URL(fileURLWithPath: "/x"))) }
        let keys = state(Config(), many).pickerEntries.map(\.hotkey)
        #expect(keys.prefix(10).map { $0.map(String.init) } == ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
        #expect(keys.suffix(2) == [nil, nil])
    }

    @Test func defaultIndex() {
        #expect(state(Config(defaultTarget: "c")).defaultIndex == 2)
        #expect(state(Config(defaultTarget: "gone")).defaultIndex == 0)
        #expect(state(Config(defaultTarget: "c", hidden: ["c"])).defaultIndex == 0)
        #expect(state(Config(), []).defaultIndex == nil)
    }

    @Test func decodesIgnoringUnknownFields() throws {
        let json = #"{"defaultTarget":"zen:{x}","future":true,"targets":{"zen:{x}":{"label":"X","hotkey":"x"}},"zen":{"profilePath":"/p"}}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        #expect(config.defaultTarget == "zen:{x}")
        #expect(config.targets?["zen:{x}"]?.hotkey == "x")
        #expect(config.zen?.profilePath == "/p")
    }

    @Test func missingFileIsEmptyConfig() throws {
        #expect(try Config.load(from: URL(fileURLWithPath: "/nonexistent/config.json")) == Config())
    }
}
