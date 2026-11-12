@testable import BrowserdoorCore
import Foundation
import Testing

struct ZenIconCacheTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("browserdoor-icons-\(UUID().uuidString)")
    let zen = URL(fileURLWithPath: "/Applications/Zen.app")

    /// Counts extractor calls (the extractor runs as a @Sendable closure).
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() {
            lock.withLock { value += 1 }
        }

        var count: Int {
            lock.withLock { value }
        }
    }

    func cache(succeeds: Bool, counter: Counter) -> ZenIconCache {
        ZenIconCache(root: root) { omni, dir in
            counter.increment()
            #expect(omni.path == "/Applications/Zen.app/Contents/Resources/browser/omni.ja")
            guard succeeds else { return false }
            FileManager.default.createFile(atPath: dir.appendingPathComponent("briefcase.svg").path, contents: Data("<svg/>".utf8))
            return true
        }
    }

    @Test func extractsOncePerVersion() {
        let counter = Counter()
        let cache = cache(succeeds: true, counter: counter)
        #expect(cache.iconFile(named: "briefcase.svg", zenVersion: "1.24") == nil)
        #expect(cache.prepare(zenApp: zen, zenVersion: "1.24") == .ready)
        #expect(cache.prepare(zenApp: zen, zenVersion: "1.24") == .ready)
        #expect(counter.count == 1)
        #expect(cache.iconFile(named: "briefcase.svg", zenVersion: "1.24") != nil)
        #expect(cache.iconFile(named: "missing.svg", zenVersion: "1.24") == nil)
    }

    @Test func newZenVersionExtractsAgain() {
        let counter = Counter()
        let cache = cache(succeeds: true, counter: counter)
        cache.prepare(zenApp: zen, zenVersion: "1.24")
        #expect(cache.iconFile(named: "briefcase.svg", zenVersion: "1.25") == nil)
        cache.prepare(zenApp: zen, zenVersion: "1.25")
        #expect(counter.count == 2)
    }

    @Test func failureIsRememberedAndNeverRetried() {
        let counter = Counter()
        let failing = cache(succeeds: false, counter: counter)
        #expect(failing.prepare(zenApp: zen, zenVersion: "1.24") == .failed)
        #expect(failing.prepare(zenApp: zen, zenVersion: "1.24") == .failed)
        // Also across launches: a fresh cache on the same folder.
        #expect(cache(succeeds: true, counter: counter).prepare(zenApp: zen, zenVersion: "1.24") == .failed)
        #expect(counter.count == 1)
        #expect(failing.iconFile(named: "briefcase.svg", zenVersion: "1.24") == nil)
    }
}

@MainActor
struct TargetIconsTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("browserdoor-target-icons-\(UUID().uuidString)")
    let zen = URL(fileURLWithPath: "/Applications/Zen.app")
    let counter = ZenIconCacheTests.Counter()

    func icons(succeeds: Bool = true) -> TargetIcons {
        let counter = counter
        return TargetIcons(cache: ZenIconCache(root: root) { _, dir in
            counter.increment()
            guard succeeds else { return false }
            FileManager.default.createFile(atPath: dir.appendingPathComponent("briefcase.svg").path, contents: Data("<svg/>".utf8))
            return true
        })
    }

    func space(_ icon: String?, name: String = "work", color: RGB? = RGB(1, 2, 3), version: String = "1.24") -> Target {
        let space = ZenSpace(uuid: "{u}", name: name, icon: icon, color: color)
        return Target(id: "zen:{u}", name: name, kind: .zenSpace(app: zen, executable: zen, space: space, version: version))
    }

    @Test func browsersShowTheirAppIcon() {
        let chrome = URL(fileURLWithPath: "/Applications/Google Chrome.app")
        let target = Target(id: "c", name: "C", kind: .chromium(app: chrome, profileDirectory: "Default"))
        #expect(icons().icon(for: target) == .app(chrome))
    }

    @Test func emojiComesFirst() {
        #expect(icons().icon(for: space("🦊")) == .zenSpace(glyph: .text("🦊"), color: RGB(1, 2, 3)))
        #expect(counter.count == 0)
    }

    @Test func bundledSVGAfterExtractionInitialUntilThen() async throws {
        let icons = icons()
        let target = space("chrome://browser/skin/zen-icons/selectable/briefcase.svg")
        #expect(icons.icon(for: target) == .zenSpace(glyph: .text("W"), color: RGB(1, 2, 3)))
        _ = icons.icon(for: target) // a second request doesn't start a second extraction
        let task = try #require(icons.preparing["1.24"])
        #expect(await task.value == .ready)
        #expect(counter.count == 1)
        let file = root.appendingPathComponent("1.24/briefcase.svg")
        #expect(icons.icon(for: target) == .zenSpace(glyph: .svg(file), color: RGB(1, 2, 3)))
    }

    @Test func failedExtractionKeepsTheInitialAndIsNotRetried() async {
        let icons = icons(succeeds: false)
        var reported: [ZenIconCache.State] = []
        icons.onPrepared = { _, state in reported.append(state) }
        let target = space("chrome://browser/skin/zen-icons/selectable/briefcase.svg", color: nil)
        _ = icons.icon(for: target)
        _ = await icons.preparing["1.24"]?.value
        #expect(reported == [.failed])
        #expect(icons.icon(for: target) == .zenSpace(glyph: .text("W"), color: nil))
        #expect(icons.preparing.isEmpty)
        #expect(counter.count == 1)
    }
}
