import AppKit
import SwiftUI
import DoormanCore

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
    private var appIcons: [URL: NSImage] = [:]
    private var svgs: [String: NSImage] = [:]
    private var extractedZenVersions: Set<String> = []

    static let omniPrefix = "chrome/browser/skin/classic/browser/zen-icons/selectable"

    func icon(for target: Target) -> EntryIcon {
        switch target.kind {
        case .app(let app), .chromium(let app, _):
            return .image(appIcon(app))
        case .zenSpace(let app, _, let space):
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
        if let cached = appIcons[app] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: app.path)
        appIcons[app] = icon
        return icon
    }

    private func zenSVG(_ name: String, zenApp: URL) -> NSImage? {
        guard let dir = zenIconDirectory(zenApp: zenApp) else { return nil }
        let key = dir.appendingPathComponent(name).path
        if let cached = svgs[key] { return cached }
        guard let image = NSImage(contentsOfFile: key) else { return nil }
        image.isTemplate = true
        svgs[key] = image
        return image
    }

    private func zenIconDirectory(zenApp: URL) -> URL? {
        let version = Bundle(url: zenApp)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("\(AppIdentity.bundleId)/zen-icons/\(version)", isDirectory: true)

        if extractedZenVersions.contains(version) { return dir }
        let marker = dir.appendingPathComponent(".complete")
        if !FileManager.default.fileExists(atPath: marker.path) {
            guard Self.extract(omni: zenApp.appendingPathComponent("Contents/Resources/browser/omni.ja"), to: dir) else {
                return nil
            }
            FileManager.default.createFile(atPath: marker.path, contents: nil)
        }
        extractedZenVersions.insert(version)
        return dir
    }

    /// `omni.ja` is a zip; `unzip` may warn about its optimized layout but extracts fine.
    private static func extract(omni: URL, to dir: URL) -> Bool {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-j", "-qq", omni.path, "\(omniPrefix)/*", "-d", dir.path]
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
