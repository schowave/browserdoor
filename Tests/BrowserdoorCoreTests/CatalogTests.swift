@testable import BrowserdoorCore
import Foundation
import SwiftUI
import Testing

/// The target catalog against a temporary config file and the sample machine.
struct CatalogTests {
    let configURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("browserdoor-catalog-\(UUID().uuidString)/config.json")

    func catalog(_ env: FakeEnvironment = sampleEnvironment()) -> TargetCatalog {
        TargetCatalog(environment: env, configURL: configURL)
    }

    @Test func missingConfigMeansDefaults() {
        let state = catalog().load()
        #expect(!state.configIsUnreadable)
        #expect(state.pickerEntries.map(\.label).prefix(4) == ["Work", "Home", "Bare", "Google Chrome › Work"])
        #expect(state.pickerEntries.map(\.hotkey).prefix(3) == ["1", "2", "3"])
        #expect(state.defaultIndex == 0)
    }

    @Test func unreadableConfigIsFlaggedAndReplacedOnSave() throws {
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: configURL)
        let state = catalog().load()
        #expect(state.configIsUnreadable)
        #expect(!state.pickerEntries.isEmpty)
        let saved = try catalog().save(state)
        #expect(!saved.configIsUnreadable)
        #expect(!catalog().load().configIsUnreadable)
    }

    @Test func editsRoundTripIntoThePicker() throws {
        var state = catalog().load()
        let safari = try #require(state.rows.firstIndex { $0.id == "app:com.apple.Safari" })
        state.move(fromOffsets: [safari], toOffset: 0)
        state.setHidden("zen:{aaaa}", true) // Work
        state.rename("zen:{bbbb}", to: "Zuhause") // Home
        state.setHotkey("zen:{bbbb}", typed: "h")
        state.toggleDefault("zen:{bbbb}")
        try catalog().save(state)

        let reloaded = catalog().load()
        let entries = reloaded.pickerEntries
        #expect(entries.map(\.id).prefix(3) == ["app:com.apple.Safari", "zen:{bbbb}", "zen:{cccc}"])
        #expect(entries[1].label == "Zuhause")
        #expect(reloaded.effectiveKeys["zen:{bbbb}"] == "h")
        #expect(reloaded.effectiveKeys["app:com.apple.Safari"] == "1")
        #expect(reloaded.effectiveKeys["zen:{aaaa}"] == nil) // hidden
        #expect(reloaded.defaultIndex == 1)
        #expect(reloaded.rows.first { $0.id == "zen:{aaaa}" }?.hidden == true)
    }

    @Test func labelEqualToDetectedNameIsNotStored() throws {
        var state = catalog().load()
        state.rows[0].label = "Work" // the detected name
        try catalog().save(state)
        #expect(catalog().load().rows[0].label == nil)
    }

    @Test func addingAnExtraAppRediscovers() throws {
        var state = catalog().load()
        #expect(!state.targets.contains { $0.id == "app:com.googlecode.iterm2" })
        state.addExtraApps(["com.googlecode.iterm2"])
        let saved = try catalog().save(state)
        #expect(saved.targets.contains { $0.id == "app:com.googlecode.iterm2" })
        #expect(saved.pickerEntries.contains { $0.id == "app:com.googlecode.iterm2" })
        #expect(saved.unlistedExtraApps.isEmpty)
    }

    @Test func extraAppsWithoutATargetAreListedForRemoval() throws {
        var state = catalog().load()
        state.addExtraApps(["com.example.gone", "com.googlecode.iterm2"])
        let saved = try catalog().save(state)
        #expect(saved.unlistedExtraApps == ["com.example.gone"])
    }

    @Test func zenProfileOverrideExpandsTildeAgainstHome() throws {
        var env = sampleEnvironment()
        env.files["/Users/test/zen-alt/zen-sessions.jsonlz4"] = mozLz4(json: #"{"spaces":[{"uuid":"{alt}","name":"Alt"}]}"#)
        var state = catalog(env).load()
        state.setZenProfile("~/zen-alt")
        let saved = try catalog(env).save(state)
        #expect(saved.pickerEntries.contains { $0.id == "zen:{alt}" })
        #expect(!saved.pickerEntries.contains { $0.id == "zen:{aaaa}" })
    }

    @Test func settingsOfTargetsNotDiscoveredNowSurvive() throws {
        try Config(order: ["gone"], hidden: ["gone"], targets: ["gone": .init(label: "G")]).save(to: configURL)
        try catalog().save(catalog().load())
        let config = try Config.load(from: configURL)
        #expect(config.order?.last == "gone")
        #expect(config.hidden == ["gone"])
        #expect(config.targets?["gone"]?.label == "G")
    }

    @Test func hotkeyInputNormalization() {
        #expect(TargetSetting.normalizeHotkey("") == nil)
        #expect(TargetSetting.normalizeHotkey("P") == "p")
        #expect(TargetSetting.normalizeHotkey("ab") == "b")
    }
}

struct CatalogEditTests {
    func state(_ env: FakeEnvironment = sampleEnvironment()) -> CatalogState {
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("browserdoor-edits-\(UUID().uuidString)/config.json")
        return TargetCatalog(environment: env, configURL: configURL).load()
    }

    @Test func renamingToTheDetectedNameOrNothingClearsTheLabel() {
        var state = state()
        state.rename("zen:{aaaa}", to: "Kunde")
        #expect(state.pickerEntries.first?.label == "Kunde")
        state.rename("zen:{aaaa}", to: "Work")
        #expect(state.rows.first?.label == nil)
        state.rename("zen:{aaaa}", to: "Kunde")
        state.rename("zen:{aaaa}", to: "")
        #expect(state.rows.first?.label == nil)
    }

    @Test func hotkeyKeepsTheLastTypedKeyLowercased() {
        var state = state()
        state.setHotkey("zen:{aaaa}", typed: "kW")
        #expect(state.rows.first?.hotkey == "w")
        #expect(state.effectiveKeys["zen:{aaaa}"] == "w")
        state.setHotkey("zen:{aaaa}", typed: "")
        #expect(state.rows.first?.hotkey == nil)
    }

    @Test func hidingAndTheDefaultTarget() {
        var state = state()
        state.setHidden("zen:{aaaa}", true)
        #expect(!state.pickerEntries.contains { $0.id == "zen:{aaaa}" })
        state.toggleDefault("zen:{bbbb}")
        #expect(state.defaultTarget == "zen:{bbbb}")
        state.toggleDefault("zen:{bbbb}")
        #expect(state.defaultTarget == nil)
    }

    @Test func movingRowsFollowsTheListsOffsets() {
        var state = state()
        let ids = state.rows.map(\.id)
        state.move(fromOffsets: [0], toOffset: 3) // down: lands before the old third row
        #expect(state.rows.map(\.id).prefix(3) == [ids[1], ids[2], ids[0]])
        state.move(fromOffsets: [1, 2], toOffset: 0) // several, upwards, order kept
        #expect(state.rows.map(\.id).prefix(3) == [ids[2], ids[0], ids[1]])
        state.move(fromOffsets: [0], toOffset: 99)
        #expect(state.rows.last?.id == ids[2])
        #expect(Set(state.rows.map(\.id)) == Set(ids))
    }

    @Test func zenProfileIsSetAndReset() {
        var state = state()
        state.setZenProfile("/p/work")
        #expect(state.zenProfilePath == "/p/work")
        state.setZenProfile("")
        #expect(state.zenProfilePath == nil)
    }

    @Test func aKeyMovesToTheTargetThatGetsItLast() {
        var state = state()
        #expect(state.setHotkey("zen:{aaaa}", typed: "x") == nil)
        #expect(state.setHotkey("zen:{bbbb}", typed: "x") == "Work")
        #expect(state.setHotkey("zen:{bbbb}", typed: "x") == nil)
        #expect(state.rows.first { $0.id == "zen:{aaaa}" }?.hotkey == nil)
        #expect(state.effectiveKeys["zen:{bbbb}"] == "x")
        #expect(state.effectiveKeys["zen:{aaaa}"] == "1")
        // An automatic number key counts too: the picker showed it on the other target.
        #expect(state.setHotkey("zen:{bbbb}", typed: "1") == "Work")
    }

    @Test func moveMatchesSwiftUIsListMove() {
        let base = state()
        let n = base.rows.count
        for source in [[0], [1], [n - 1], [0, 2], [1, 2], [0, n - 1]] {
            for destination in 0 ... n {
                var state = base
                state.move(fromOffsets: IndexSet(source), toOffset: destination)
                var expected = base.rows.map(\.id)
                expected.move(fromOffsets: IndexSet(source), toOffset: destination)
                #expect(state.rows.map(\.id) == expected, "move \(source) to \(destination)")
            }
        }
    }

    @Test func extraAppsAreAddedOnceAndRemovable() {
        var state = state()
        state.addExtraApps(["com.googlecode.iterm2", "com.googlecode.iterm2"])
        #expect(state.extraApps == ["com.googlecode.iterm2"])
        #expect(state.extraApp(forTarget: "app:com.googlecode.iterm2") == "com.googlecode.iterm2")
        #expect(state.extraApp(forTarget: "app:com.apple.Safari") == nil) // known browser, not added
        #expect(state.extraApp(forTarget: "zen:{aaaa}") == nil)
        state.removeExtraApp("com.googlecode.iterm2")
        #expect(state.extraApps.isEmpty)
    }
}

struct TargetListingTests {
    @Test func listsEveryTargetWithItsCommand() throws {
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("browserdoor-listing-\(UUID().uuidString)/config.json")
        var state = TargetCatalog(environment: sampleEnvironment(), configURL: configURL).load()
        let safari = try #require(state.rows.firstIndex { $0.id == "app:com.apple.Safari" })
        state.rows[safari].hidden = true
        let lines = state.listing { _ in false }.split(separator: "\n").map { $0.split(separator: "\t").map(String.init) }

        #expect(lines.count == state.rows.count)
        #expect(lines.first == ["1", "zen:{aaaa}", "Work", "default",
                                "/usr/bin/open -a /Applications/Zen.app --args --space {aaaa} https://example.com"])
        #expect(lines.contains(["-", "app:com.apple.Safari", "Safari", "hidden",
                                "open -a /Applications/Safari.app https://example.com"]))
        let chrome = try #require(lines.first { $0[1] == "chromium:com.google.Chrome:Profile 2" })
        #expect(chrome[4] == "/usr/bin/open -na '/Applications/Google Chrome.app' --args '--profile-directory=Profile 2' https://example.com")
    }
}
