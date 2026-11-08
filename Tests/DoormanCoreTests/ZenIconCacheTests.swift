@testable import DoormanCore
import Foundation
import Testing

struct ZenIconCacheTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("doorman-icons-\(UUID().uuidString)")
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
