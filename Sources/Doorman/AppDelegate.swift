import AppKit
import DoormanCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let picker = PickerController()
    private var statusItem: NSStatusItem?
    private let defaults = UserDefaults.standard
    private static let onboardedKey = "didOnboard"

    func applicationDidFinishLaunching(_: Notification) {
        setUpStatusItem()
        setUpMainMenu()
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        CurrentInstallation.shared.prepare()
        LaunchServicesCleanup.run()
        picker.prewarm()
        UpdateChecker.shared.startAutomaticChecks()
        if !defaults.bool(forKey: Self.onboardedKey) {
            defaults.set(true, forKey: Self.onboardedKey)
            onboard()
        }
    }

    /// Opening Doorman again (Finder, Spotlight, `doorman`) while it runs shows the settings.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    /// Both URL clicks (http/https) and opened files (.html, .webloc) arrive here.
    func application(_: NSApplication, open urls: [URL]) {
        let links = Links.opener.links(from: urls)
        if links.count < urls.count {
            log.notice("ignored \(urls.count - links.count) item(s) that aren't allowed links")
        }
        picker.show(urls: links)
    }

    // MARK: Onboarding

    private func onboard() {
        if !DefaultBrowser.isDoorman {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = L("Use Doorman as your default browser?")
            alert.informativeText = L("Doorman then asks for every link which browser, profile or Zen space should open it.")
            alert.addButton(withTitle: L("Make Default"))
            alert.addButton(withTitle: L("Later"))
            if alert.runModal() == .alertFirstButtonReturn {
                DefaultBrowser.makeDoorman()
            }
        }
        if !CurrentInstallation.shared.launchesAtLogin {
            try? CurrentInstallation.shared.setLaunchAtLogin(true)
        }
    }

    // MARK: Main menu

    /// Doorman shows no menu bar of its own, but key equivalents in the settings window
    /// (⌘C/⌘V in text fields, ⌘W, ⌘,) come from the main menu.
    private func setUpMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(item(L("Settings…"), #selector(settingsAction), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Quit Doorman"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: AppIdentity.name, action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: L("Edit"))
        edit.addItem(withTitle: L("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: L("Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: L("Edit"), action: nil, keyEquivalent: "").submenu = edit

        let window = NSMenu(title: L("Window"))
        window.addItem(withTitle: L("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: L("Window"), action: nil, keyEquivalent: "").submenu = window

        NSApp.mainMenu = main
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBarImage()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// The door glyph from the bundle as a template image (tinted by macOS for light and dark
    /// menu bars); an SF Symbol when running outside the bundle, e.g. via `swift run`.
    private static func menuBarImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "svg"),
           let image = NSImage(contentsOf: url)
        {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            image.accessibilityDescription = AppIdentity.name
            return image
        }
        return NSImage(systemSymbolName: "door.left.hand.open", accessibilityDescription: AppIdentity.name)
    }

    /// Rebuilt on every open so the status lines are current. Kept to cheap calls only.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if case let .available(release) = UpdateChecker.shared.status {
            menu.addItem(item(L("Update to Doorman %@…", release.version.description), #selector(checkForUpdatesAction)))
            menu.addItem(.separator())
        }
        if !DefaultBrowser.isDoorman {
            menu.addItem(withTitle: L("Doorman isn't your default browser"), action: nil, keyEquivalent: "").isEnabled = false
            menu.addItem(item(L("Make Default Browser"), #selector(setDefaultAction)))
            menu.addItem(.separator())
        }
        menu.addItem(item(L("Settings…"), #selector(settingsAction), key: ","))
        menu.addItem(item(L("Check for Updates…"), #selector(checkForUpdatesAction)))
        menu.addItem(.separator())
        menu.addItem(withTitle: "\(AppIdentity.name) \(RunningApp.version)", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(item(L("Quit Doorman"), #selector(quitAction), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func setDefaultAction() {
        DefaultBrowser.makeDoorman()
    }

    @objc private func settingsAction() {
        SettingsWindowController.shared.show()
    }

    @objc private func checkForUpdatesAction() {
        Task { await UpdateChecker.shared.checkNow() }
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
