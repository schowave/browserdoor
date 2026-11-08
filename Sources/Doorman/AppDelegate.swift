import AppKit
import ServiceManagement
import DoormanCore
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let picker = PickerController()
    private var statusItem: NSStatusItem?
    private let defaults = UserDefaults.standard
    private static let onboardedKey = "didOnboard"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        if !defaults.bool(forKey: Self.onboardedKey) {
            defaults.set(true, forKey: Self.onboardedKey)
            onboard()
        }
    }

    /// Both URL clicks (http/https) and opened files (.html, .webloc) arrive here.
    func application(_ application: NSApplication, open urls: [URL]) {
        log.debug("open event: \(urls.count) url(s)")
        let resolved = urls.compactMap { url -> URL? in
            if url.isFileURL, url.pathExtension.lowercased() == "webloc" {
                return (try? Data(contentsOf: url)).flatMap(WeblocParser.url(fromWebloc:))
            }
            return url
        }
        let allowed = URLPolicy.filter(resolved)
        if allowed.count < resolved.count {
            log.notice("ignored \(resolved.count - allowed.count) url(s) with a disallowed scheme")
        }
        picker.show(urls: allowed)
    }

    // MARK: Onboarding

    private func onboard() {
        if !isDefaultBrowser {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = "\(AppIdentity.name) als Standardbrowser verwenden?"
            alert.informativeText = "Dann fragt \(AppIdentity.name) bei jedem Link, in welchem Browser oder Zen-Space er geöffnet werden soll."
            alert.addButton(withTitle: "Als Standard setzen")
            alert.addButton(withTitle: "Später")
            if alert.runModal() == .alertFirstButtonReturn { makeDefaultBrowser() }
        }
        if SMAppService.mainApp.status != .enabled { setLaunchAtLogin(true) }
    }

    // MARK: Default browser

    private var isDefaultBrowser: Bool {
        guard
            let probe = URL(string: "https://example.com"),
            let handler = NSWorkspace.shared.urlForApplication(toOpen: probe)
        else { return false }
        return Bundle(url: handler)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    private func makeDefaultBrowser() {
        let app = Bundle.main.bundleURL
        // macOS asks the user to confirm; http covers https as well.
        NSWorkspace.shared.setDefaultApplication(at: app, toOpenURLsWithScheme: "http") { error in
            if let error { log.error("set default browser: \(error.localizedDescription, privacy: .public)") }
        }
        NSWorkspace.shared.setDefaultApplication(at: app, toOpen: .html) { error in
            if let error { log.error("set html handler: \(error.localizedDescription, privacy: .public)") }
        }
    }

    // MARK: Login item

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            log.error("login item: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Status item

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: AppIdentity.name)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Rebuilt on every open so the status lines are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()

        if isDefaultBrowser {
            menu.addItem(withTitle: "Standardbrowser: ja", action: nil, keyEquivalent: "").isEnabled = false
        } else {
            menu.addItem(withTitle: "Standardbrowser: nein", action: nil, keyEquivalent: "").isEnabled = false
            menu.addItem(item("Als Standardbrowser setzen", #selector(setDefaultAction)))
        }

        let login = item("Beim Login starten", #selector(toggleLoginAction))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("Konfiguration öffnen…", #selector(openConfigAction)))
        menu.addItem(.separator())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        menu.addItem(withTitle: "\(AppIdentity.name) \(version)", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(item("Beenden", #selector(quitAction), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func setDefaultAction() { makeDefaultBrowser() }

    @objc private func toggleLoginAction() {
        setLaunchAtLogin(SMAppService.mainApp.status != .enabled)
    }

    @objc private func openConfigAction() {
        let environment = SystemEnvironment()
        let url = Config.fileURL(home: environment.home)
        if !FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Config.template(for: Discovery(environment: environment).discover()).write(to: url)
            } catch {
                log.error("write config template: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        // Open as text: a .json default handler might be an IDE that takes ages to start.
        let textEdit = NSWorkspace.shared.urlForApplication(toOpen: UTType.plainText) ?? URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func quitAction() { NSApp.terminate(nil) }
}
