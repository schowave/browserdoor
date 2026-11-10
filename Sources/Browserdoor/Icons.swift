import AppKit
import BrowserdoorCore
import SwiftUI

enum EntryIcon {
    case image(NSImage)
    /// A Zen space: monochrome SVG or emoji or initial, on the space's color.
    case zenSpace(glyph: Glyph, color: Color)

    enum Glyph {
        case svg(NSImage)
        case text(String)
    }
}

/// Resolves icons for targets. App icons come from LaunchServices; Zen's space icons are
/// SVGs inside Zen's `omni.ja`, extracted once per Zen version into the caches directory.
@MainActor
final class IconProvider {
    static let shared = IconProvider()

    private var appIcons: [URL: NSImage] = [:]
    private var svgs: [String: NSImage] = [:]
    /// Zen versions whose icons are being extracted right now.
    private var preparing: Set<String> = []
    private let environment = SystemEnvironment()
    private let zenIcons = ZenIconCache(
        root: (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("\(AppIdentity.bundleId)/zen-icons", isDirectory: true)
    )

    func icon(for target: Target) -> EntryIcon {
        switch target.kind {
        case let .app(app), let .chromium(app, _):
            return .image(appIcon(app))
        case let .zenSpace(app, _, space, _):
            let color = space.color.map { Color(red: Double($0.r) / 255, green: Double($0.g) / 255, blue: Double($0.b) / 255) }
                ?? Color.secondary.opacity(0.35)
            if let emoji = space.emojiIcon {
                return .zenSpace(glyph: .text(emoji), color: color)
            }
            if let name = space.bundledIconName, let svg = zenSVG(name, zenApp: app) {
                return .zenSpace(glyph: .svg(svg), color: color)
            }
            return .zenSpace(glyph: .text(String(space.name.prefix(1)).uppercased()), color: color)
        }
    }

    private func appIcon(_ app: URL) -> NSImage {
        if let cached = appIcons[app] {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        appIcons[app] = icon
        return icon
    }

    /// The space's SVG if Zen's icons are extracted. Starts the extraction in the background
    /// otherwise; until it finishes the picker shows the letter fallback.
    private func zenSVG(_ name: String, zenApp: URL) -> NSImage? {
        let version = environment.appInfo(at: zenApp)?.version ?? "unknown"
        guard let file = zenIcons.iconFile(named: name, zenVersion: version) else {
            prepareZenIcons(zenApp: zenApp, version: version)
            return nil
        }
        if let cached = svgs[file.path] {
            return cached
        }
        guard let image = NSImage(contentsOf: file) else { return nil }
        image.isTemplate = true
        svgs[file.path] = image
        return image
    }

    private func prepareZenIcons(zenApp: URL, version: String) {
        guard zenIcons.state(zenVersion: version) == .missing, preparing.insert(version).inserted else { return }
        let cache = zenIcons
        Task { [weak self] in
            let state = await Task.detached(priority: .utility) {
                cache.prepare(zenApp: zenApp, zenVersion: version)
            }.value
            self?.preparing.remove(version)
            if state == .failed {
                log.error("could not extract Zen icons for Zen \(version, privacy: .public)")
            }
        }
    }
}
