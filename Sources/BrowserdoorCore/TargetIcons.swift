import Foundation

/// What a target looks like in the picker and the settings, before any image is loaded.
public enum TargetIcon: Equatable, Sendable {
    /// The app's own icon.
    case app(URL)
    /// A Zen space: a glyph on the space's color (nil: neutral).
    case zenSpace(glyph: Glyph, color: RGB?)

    public enum Glyph: Equatable, Sendable {
        /// A monochrome SVG from Zen's icon set.
        case svg(URL)
        /// An emoji, or the space's initial.
        case text(String)
    }
}

/// Decides each target's icon. A Zen space shows its emoji, else its bundled SVG, else its initial
/// (SPEC §3.1). The SVGs are extracted from Zen once per Zen version: the first time one is
/// missing, extraction starts in the background and the initial shows until it is done.
@MainActor
public final class TargetIcons {
    private let cache: ZenIconCache
    /// Extractions running right now, by Zen version.
    private(set) var preparing: [String: Task<ZenIconCache.State, Never>] = [:]
    /// Called when an extraction ends (e.g. to log a failure).
    public var onPrepared: ((_ zenVersion: String, ZenIconCache.State) -> Void)?

    public init(cache: ZenIconCache) {
        self.cache = cache
    }

    public func icon(for target: Target) -> TargetIcon {
        switch target.kind {
        case let .app(app), let .chromium(app, _), let .firefox(app, _):
            return .app(app)
        case let .zenSpace(app, _, space, _, version):
            if let emoji = space.emojiIcon {
                return .zenSpace(glyph: .text(emoji), color: space.color)
            }
            if let name = space.bundledIconName, let file = svg(name, zenApp: app, version: version.isEmpty ? "unknown" : version) {
                return .zenSpace(glyph: .svg(file), color: space.color)
            }
            return .zenSpace(glyph: .text(String(space.name.prefix(1)).uppercased()), color: space.color)
        }
    }

    private func svg(_ name: String, zenApp: URL, version: String) -> URL? {
        if let file = cache.iconFile(named: name, zenVersion: version) {
            return file
        }
        guard cache.state(zenVersion: version) == .missing, preparing[version] == nil else { return nil }
        let cache = cache
        preparing[version] = Task {
            let state = await Task.detached(priority: .utility) {
                cache.prepare(zenApp: zenApp, zenVersion: version)
            }.value
            preparing[version] = nil
            onPrepared?(version, state)
            return state
        }
        return nil
    }
}
