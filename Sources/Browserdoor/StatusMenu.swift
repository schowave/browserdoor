import AppKit
import BrowserdoorCore

/// The menu bar icon and its menu. The icon carries a dot while Browserdoor isn't the default
/// browser. It can be hidden in the settings or by ⌘-dragging it out of the menu bar; macOS
/// keeps that choice (and the position) in the user defaults under the item's autosave name.
@MainActor @Observable
final class StatusMenu: NSObject, NSMenuDelegate {
    static let shared = StatusMenu()

    /// Picks up links from the clipboard (shows the picker).
    @ObservationIgnored var openLinks: (([URL]) -> Void)?

    /// Whether the icon is in the menu bar. Follows ⌘-drag removal.
    var isVisible: Bool {
        get {
            access(keyPath: \.isVisible)
            return item?.isVisible ?? false
        }
        set {
            withMutation(keyPath: \.isVisible) {
                item?.isVisible = newValue
            }
        }
    }

    @ObservationIgnored private var item: NSStatusItem?
    @ObservationIgnored private var visibility: NSKeyValueObservation?
    @ObservationIgnored private var showsDot = false
    @ObservationIgnored private var clipboardItem: NSMenuItem?

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.behavior = .removalAllowed
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        self.item = item
        visibility = item.observe(\.isVisible) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.withMutation(keyPath: \.isVisible) {}
            }
        }
        refreshIcon()
        // The default browser can change in System Settings without telling anyone.
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIcon() }
        }.tolerance = 30
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIcon() }
        }
    }

    /// Redraws the icon if the default-browser state changed. Cheap: one LaunchServices query.
    func refreshIcon() {
        let dot = !DefaultBrowser.isBrowserdoor
        guard let button = item?.button, button.image == nil || dot != showsDot else { return }
        showsDot = dot
        button.image = Self.image(withDot: dot)
        button.setAccessibilityLabel(dot ? L("Browserdoor – not the default browser") : AppIdentity.name)
    }

    // MARK: Icon

    /// The door glyph as a template image (tinted by macOS for light and dark menu bars), with a
    /// dot in its top-right corner, cut out of the glyph so it stays readable.
    private static func image(withDot dot: Bool) -> NSImage? {
        guard let glyph = glyph() else { return nil }
        guard dot else { return glyph }
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            glyph.draw(in: rect)
            let diameter: CGFloat = 7
            let circle = NSRect(x: rect.maxX - diameter, y: rect.maxY - diameter, width: diameter, height: diameter)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: circle.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: circle).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The door from the bundle; an SF Symbol when running outside the bundle (`swift run`).
    private static func glyph() -> NSImage? {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg"),
           let image = NSImage(contentsOf: url)
        {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return image
        }
        return NSImage(systemSymbolName: "door.left.hand.open", accessibilityDescription: AppIdentity.name)
    }

    // MARK: Menu

    /// Rebuilt on every open so the status lines are current. Kept to cheap calls only.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        refreshIcon()

        menu.addItem(item(L("About Browserdoor"), #selector(aboutAction)))
        menu.addItem(alternate(item(L("Report an Issue…"), #selector(reportIssueAction))))
        menu.addItem(.separator())

        let clipboard = item(L("Open Link from Clipboard…"), #selector(openClipboardAction))
        clipboard.isEnabled = false
        clipboardItem = clipboard
        menu.addItem(clipboard)
        updateClipboardItem()
        menu.addItem(.separator())

        if !DefaultBrowser.isBrowserdoor {
            let makeDefault = item(L("Make Default Browser"), #selector(setDefaultAction))
            makeDefault.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                        accessibilityDescription: L("Browserdoor isn't your default browser"))
            makeDefault.toolTip = L("Browserdoor isn't your default browser")
            menu.addItem(makeDefault)
        }
        if case let .available(release) = UpdateChecker.shared.status {
            menu.addItem(item(L("Update to Browserdoor %@…", release.version.description), #selector(checkForUpdatesAction)))
        } else {
            menu.addItem(item(L("Check for Updates…"), #selector(checkForUpdatesAction)))
        }
        menu.addItem(item(L("Settings…"), #selector(settingsAction), key: ","))
        menu.addItem(alternate(item(L("Show Configuration in Finder"), #selector(revealConfigAction), key: ",")))
        menu.addItem(.separator())
        menu.addItem(item(L("Quit Browserdoor"), #selector(quitAction), key: "q"))
    }

    func menuDidClose(_: NSMenu) {
        clipboardItem = nil
    }

    /// Enables "Open Link from Clipboard…" if the clipboard holds a web link. From macOS 15.4 this
    /// asks the system without reading the clipboard (which would show a privacy notice); before,
    /// any text on the clipboard enables it.
    private func updateClipboardItem() {
        guard NSPasteboard.general.availableType(from: [.string, .URL]) != nil else { return }
        if #available(macOS 15.4, *) {
            Task {
                let patterns = try? await NSPasteboard.general.detectedPatterns(for: [\.probableWebURL])
                clipboardItem?.isEnabled = patterns?.contains(\.probableWebURL) == true
            }
        } else {
            clipboardItem?.isEnabled = true
        }
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// Shown in place of the item above it while ⌥ is held.
    private func alternate(_ item: NSMenuItem) -> NSMenuItem {
        item.isAlternate = true
        item.keyEquivalentModifierMask = item.keyEquivalent.isEmpty ? [.option] : [.command, .option]
        return item
    }

    // MARK: Actions

    @objc private func aboutAction() {
        About.show()
    }

    @objc private func reportIssueAction() {
        About.reportIssue()
    }

    @objc private func openClipboardAction() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        let links = Links.opener.links(from: urls + LinkOpener.urls(inText: text))
        var seen = Set<URL>()
        let unique = links.filter { seen.insert($0).inserted }
        if unique.isEmpty {
            NSSound.beep()
        } else {
            openLinks?(unique)
        }
    }

    @objc private func setDefaultAction() {
        DefaultBrowser.makeBrowserdoor { [weak self] in self?.refreshIcon() }
    }

    @objc private func settingsAction() {
        SettingsWindowController.shared.show()
    }

    @objc private func revealConfigAction() {
        SettingsWindowController.shared.revealConfig()
    }

    @objc private func checkForUpdatesAction() {
        Task { await UpdateChecker.shared.checkNow() }
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}

/// The About panel and the issue link, from the menu bar menu and the app menu.
@MainActor
enum About {
    static func show() {
        NSApp.activate()
        let credits = NSMutableAttributedString(
            string: L("Picks the browser, profile or Zen space for every link."),
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                         .foregroundColor: NSColor.secondaryLabelColor]
        )
        credits.append(NSAttributedString(string: "\n\n"))
        credits.append(NSAttributedString(
            string: "github.com/schowave/browserdoor",
            attributes: [.link: URL(string: "https://github.com/schowave/browserdoor")!,
                         .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        ))
        credits.append(NSAttributedString(
            string: "\n" + L("MIT License"),
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                         .foregroundColor: NSColor.secondaryLabelColor]
        ))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    static func reportIssue() {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let macOS = "\(os.majorVersion).\(os.minorVersion)" + (os.patchVersion > 0 ? ".\(os.patchVersion)" : "")
        NSWorkspace.shared.open(IssueReport.url(appVersion: RunningApp.version, macOSVersion: macOS))
    }
}
