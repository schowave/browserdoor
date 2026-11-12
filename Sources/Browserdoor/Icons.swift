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

/// Loads the images for the icons `TargetIcons` decides on, and keeps them.
@MainActor
final class IconProvider {
    static let shared = IconProvider()

    private var images: [URL: NSImage] = [:]
    private let icons: TargetIcons = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let icons = TargetIcons(cache: ZenIconCache(root: caches.appendingPathComponent("\(AppIdentity.bundleId)/zen-icons", isDirectory: true)))
        icons.onPrepared = { version, state in
            if state == .failed {
                log.error("could not extract Zen icons for Zen \(version, privacy: .public)")
            }
        }
        return icons
    }()

    func icon(for target: Target) -> EntryIcon {
        switch icons.icon(for: target) {
        case let .app(app):
            return .image(image(app) { NSWorkspace.shared.icon(forFile: $0.path) })
        case let .zenSpace(glyph, rgb):
            let color = rgb.map { Color(red: Double($0.r) / 255, green: Double($0.g) / 255, blue: Double($0.b) / 255) }
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
