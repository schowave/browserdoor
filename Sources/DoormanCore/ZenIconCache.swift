import Foundation

/// Zen's workspace icons, extracted from `omni.ja` once per Zen version into a cache folder.
/// A failed extraction is remembered per version (on disk), so it is never retried for it.
///
/// `prepare` is slow (it unzips); run it off the main thread. `iconFile` is cheap.
public struct ZenIconCache: Sendable {
    /// Unpacks the selectable icons (`*.svg`) from `omni` into a directory; true on success.
    public typealias Extractor = @Sendable (_ omni: URL, _ directory: URL) -> Bool

    public enum State: Equatable, Sendable {
        case ready
        case failed
        case missing
    }

    public var root: URL
    public var extract: Extractor

    public init(root: URL, extract: @escaping Extractor = ZenIconCache.unzipSelectableIcons) {
        self.root = root
        self.extract = extract
    }

    public func directory(zenVersion: String) -> URL {
        root.appendingPathComponent(zenVersion, isDirectory: true)
    }

    public func state(zenVersion: String) -> State {
        let dir = directory(zenVersion: zenVersion)
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".complete").path) {
            return .ready
        }
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".failed").path) {
            return .failed
        }
        return .missing
    }

    /// The SVG for a `selectable/<name>.svg` icon, if extracted.
    public func iconFile(named name: String, zenVersion: String) -> URL? {
        guard state(zenVersion: zenVersion) == .ready else { return nil }
        let file = directory(zenVersion: zenVersion).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// Extracts the icons for this Zen version unless done or failed before. Returns the state.
    @discardableResult
    public func prepare(zenApp: URL, zenVersion: String) -> State {
        let current = state(zenVersion: zenVersion)
        guard current == .missing else { return current }
        let dir = directory(zenVersion: zenVersion)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let omni = zenApp.appendingPathComponent("Contents/Resources/browser/omni.ja")
        let ok = extract(omni, dir)
        FileManager.default.createFile(atPath: dir.appendingPathComponent(ok ? ".complete" : ".failed").path, contents: nil)
        return ok ? .ready : .failed
    }

    /// Production extractor. `omni.ja` is a zip; `unzip` may warn about its optimized layout but
    /// extracts fine.
    public static let unzipSelectableIcons: Extractor = { omni, dir in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-j", "-qq", omni.path, "chrome/browser/skin/classic/browser/zen-icons/selectable/*", "-d", dir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return false
        }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.contains { $0.hasSuffix(".svg") }
    }
}
