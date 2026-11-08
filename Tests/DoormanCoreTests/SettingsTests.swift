@testable import DoormanCore
import Foundation
import Testing

struct SettingsTests {
    let targets = ["a", "b", "c"].map {
        Target(id: $0, name: $0.uppercased(), kind: .app(URL(fileURLWithPath: "/Applications/\($0).app")))
    }

    @Test func rowsIncludeHiddenInConfigOrder() {
        let config = Config(order: ["c", "a"], hidden: ["a"], targets: ["c": .init(label: "Sea", hotkey: "S")])
        let rows = config.settings(for: targets)
        #expect(rows.map(\.id) == ["c", "a", "b"])
        #expect(rows.map(\.hidden) == [false, true, false])
        #expect(rows[0].label == "Sea")
        #expect(rows[0].hotkey == "s")
        #expect(rows[0].displayName == "Sea")
        #expect(rows[2].displayName == "B")
    }

    @Test func labelEqualToDetectedNameIsNoCustomLabel() {
        let rows = Config(targets: ["a": .init(label: "A")]).settings(for: targets)
        #expect(rows[0].label == nil)
    }

    @Test func applyWritesOrderHiddenAndOverrides() {
        var config = Config()
        var rows = config.settings(for: targets)
        rows.swapAt(0, 2) // c, b, a
        rows[1].hidden = true
        rows[2].label = "Ay"
        rows[0].hotkey = "x"
        config.apply(rows)
        #expect(config.order == ["c", "b", "a"])
        #expect(config.hidden == ["b"])
        #expect(config.targets == ["a": .init(label: "Ay"), "c": .init(hotkey: "x")])
        #expect(config.entries(for: targets).map(\.id) == ["c", "a"])
    }

    @Test func applyKeepsSettingsOfTargetsNotDiscoveredNow() {
        var config = Config(order: ["gone", "a"], hidden: ["gone"], targets: ["gone": .init(label: "G")])
        config.apply(config.settings(for: targets))
        #expect(config.order == ["a", "b", "c", "gone"])
        #expect(config.hidden == ["gone"])
        #expect(config.targets?["gone"]?.label == "G")
    }

    @Test func clearingLabelAndHotkeyRemovesOverride() {
        var config = Config(targets: ["a": .init(label: "Ay", hotkey: "x")])
        var rows = config.settings(for: targets)
        rows[0].label = nil
        rows[0].hotkey = nil
        config.apply(rows)
        #expect(config.targets?["a"] == nil)
    }

    @Test func hotkeyNormalization() {
        #expect(TargetSetting.normalizeHotkey("") == nil)
        #expect(TargetSetting.normalizeHotkey("  ") == nil)
        #expect(TargetSetting.normalizeHotkey("P") == "p")
        #expect(TargetSetting.normalizeHotkey("ab") == "b")
    }

    @Test func saveAndLoadRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("config.json")
        let config = Config(defaultTarget: "a", order: ["b"], extraApps: ["x.y"], zen: .init(profilePath: "/p"))
        try config.save(to: url)
        #expect(try Config.load(from: url) == config)
    }
}

struct UpdateCheckTests {
    @Test func versionParsingAndOrder() throws {
        #expect(AppVersion("v0.1.1")?.parts == [0, 1, 1])
        #expect(AppVersion("1.2")?.parts == [1, 2])
        #expect(AppVersion("0.2.0-rc.1")?.parts == [0, 2, 0])
        #expect(AppVersion("dev") == nil)
        #expect(AppVersion("") == nil)
        #expect(try #require(AppVersion("0.1.10")) > #require(AppVersion("0.1.9")))
        #expect(try #require(AppVersion("1.0")) == #require(AppVersion("1.0.0")))
    }

    @Test func parsesLatestRelease() throws {
        let json = #"{"tag_name":"v0.2.0","html_url":"https://github.com/schowave/doorman/releases/tag/v0.2.0","draft":false,"prerelease":false}"#
        let release = try UpdateCheck.parseLatestRelease(Data(json.utf8))
        #expect(release.version.description == "0.2.0")
        #expect(release.tag == "v0.2.0")
        #expect(UpdateCheck.isUpdate(release, over: "0.1.1"))
        #expect(!UpdateCheck.isUpdate(release, over: "0.2.0"))
        #expect(!UpdateCheck.isUpdate(release, over: "0.3.0"))
        #expect(!UpdateCheck.isUpdate(release, over: "0.0.0")) // dev build
    }

    @Test func rejectsPrereleaseAndGarbage() {
        let pre = #"{"tag_name":"v0.3.0-rc.1","html_url":"https://x.invalid","prerelease":true}"#
        #expect(throws: (any Error).self) { try UpdateCheck.parseLatestRelease(Data(pre.utf8)) }
        #expect(throws: (any Error).self) { try UpdateCheck.parseLatestRelease(Data("{}".utf8)) }
    }

    @Test func dueOncePerDay() {
        let now = Date()
        #expect(UpdateCheck.isDue(lastCheck: nil, now: now))
        #expect(!UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-3600), now: now))
        #expect(UpdateCheck.isDue(lastCheck: now.addingTimeInterval(-25 * 3600), now: now))
    }
}
