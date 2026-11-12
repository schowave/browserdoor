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

/// Loads the images for the icons `TargetIcons` decides on, and keeps them. Observable: a view
/// that asked for an icon is drawn again when Zen's icons become available, so an open picker
/// swaps the initials for the glyphs.
@MainActor @Observable
final class IconProvider {
    static let shared = IconProvider()

    /// Bumped when an extraction ends; `icon(for:)` reads it so views depend on it.
    private var revision = 0 {
        didSet { resolved = [:] }
    }

    @ObservationIgnored private var images: [URL: NSImage] = [:]
    /// Icons already worked out, by target ID, so redrawing a row (hover, arrow keys) doesn't
    /// ask the file system again. Cleared when Zen's icons arrive.
    @ObservationIgnored private var resolved: [String: (target: Target, icon: EntryIcon)] = [:]
    @ObservationIgnored private let icons: TargetIcons

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        icons = TargetIcons(cache: ZenIconCache(root: caches.appendingPathComponent("\(AppIdentity.bundleId)/zen-icons", isDirectory: true)))
        icons.onPrepared = { [weak self] version, state in
            if state == .failed {
                log.error("could not extract Zen icons for Zen \(version, privacy: .public)")
            }
            self?.revision += 1
        }
    }

    func icon(for target: Target) -> EntryIcon {
        _ = revision
        if let hit = resolved[target.id], hit.target == target {
            return hit.icon
        }
        let icon = load(icons.icon(for: target))
        resolved[target.id] = (target, icon)
        return icon
    }

    private func load(_ icon: TargetIcon) -> EntryIcon {
        switch icon {
        case let .app(app):
            return .image(image(app) { NSWorkspace.shared.icon(forFile: $0.path) })
        case let .zenSpace(glyph, rgb):
            let color = rgb.map { Color(rgb: $0) }
                ?? Color.secondary.opacity(0.35)
            switch glyph {
            case let .text(text):
                return .zenSpace(glyph: .text(text), color: color)
            case let .svg(file):
                let svg = image(file) { file in
                    let image = NSImage(contentsOf: file) ?? NSImage()
                    image.isTemplate = true
                    return image
                }
                return .zenSpace(glyph: .svg(svg), color: color)
            }
        }
    }

    private func image(_ url: URL, load: (URL) -> NSImage) -> NSImage {
        if let cached = images[url] {
            return cached
        }
        let image = load(url)
        images[url] = image
        return image
    }
}
