import AppKit
import BrowserdoorCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let picker = PickerController()

    func applicationDidFinishLaunching(_: Notification) {
        let next = Startup(
            bundleId: AppIdentity.bundleId,
            installation: CurrentInstallation.shared,
            legacyLoginItem: SMAppServiceLoginItem(),
            port: SystemStartupPort()
        ).run()
        StatusMenu.shared.openLinks = { [picker] links in picker.show(urls: links) }
        StatusMenu.shared.install()
        setUpMainMenu()
        picker.prewarm()
        UpdateChecker.shared.startAutomaticChecks()
        UpgradeWatcher.shared.isBusy = { [picker] in picker.isShowing || SettingsWindowController.shared.isShowing }
        UpgradeWatcher.shared.start()
        switch next {
        case .onboard:
            onboard()
        case .reclaimDefaultBrowser:
            NSApp.activate()
            DefaultBrowser.makeBrowserdoor()
        case .nothing:
            break
        }
    }

    /// Opening Browserdoor again (Finder, Spotlight, `browserdoor`) while it runs shows the settings.
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
        if !DefaultBrowser.isBrowserdoor {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = L("Use Browserdoor as your default browser?")
            alert.informativeText = L("Browserdoor then asks for every link which browser, profile or Zen space should open it.")
            alert.addButton(withTitle: L("Make Default"))
            alert.addButton(withTitle: L("Later"))
            if alert.runModal() == .alertFirstButtonReturn {
                DefaultBrowser.makeBrowserdoor()
            }
        }
        if !CurrentInstallation.shared.launchesAtLogin {
            try? CurrentInstallation.shared.setLaunchAtLogin(true)
        }
    }

    // MARK: Main menu

    /// Browserdoor shows no menu bar of its own, but key equivalents in the settings window
    /// (⌘C/⌘V in text fields, ⌘W, ⌘M, ⌘H, ⌘,) come from the main menu.
    private func setUpMainMenu() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(item(L("About Browserdoor"), #selector(aboutAction)))
        appMenu.addItem(.separator())
        appMenu.addItem(item(L("Settings…"), #selector(settingsAction), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Hide Browserdoor"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Quit Browserdoor"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        window.addItem(withTitle: L("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: L("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: L("Window"), action: nil, keyEquivalent: "").submenu = window

        NSApp.mainMenu = main
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func aboutAction() {
        About.show()
    }

    @objc private func settingsAction() {
        SettingsWindowController.shared.show()
    }
}
