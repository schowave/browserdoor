import AppKit
import BrowserdoorCore
import SwiftUI
import UniformTypeIdentifiers

/// State behind the settings window. Every change is written to `config.json` right away;
/// the picker reads that file each time it opens.
@MainActor @Observable
final class SettingsModel {
    /// Loaded targets plus the edits made here; saved on every change.
    var state: CatalogState
    var isDefaultBrowser = false
    var launchesAtLogin = false
    var loginItemError: String?
    var configError: String?
    /// A short note after an edit, e.g. that a key moved from another target.
    var notice: String?
    var selection: String?
    /// The row whose name field should take the focus ("Rename" in the context menu).
    var renaming: String?

    private let environment = SystemEnvironment()
    private var catalog: TargetCatalog {
        TargetCatalog(environment: environment)
    }

    private var noticeReset: Task<Void, Never>?

    init() {
        state = TargetCatalog(environment: SystemEnvironment()).load()
        NotificationCenter.default.addObserver(forName: DefaultBrowser.mayHaveChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isDefaultBrowser = DefaultBrowser.isBrowserdoor }
        }
    }

    func reload() {
        state = catalog.load()
        configError = state.configIsUnreadable ? L("config.json can't be read; saving here will replace it.") : nil
        isDefaultBrowser = DefaultBrowser.isBrowserdoor
        launchesAtLogin = CurrentInstallation.shared.launchesAtLogin
        loginItemError = nil
    }

    /// The selected row is an app the user added (and can remove with −).
    var selectionIsExtraApp: Bool {
        selection.flatMap(state.extraApp(forTarget:)) != nil
    }

    func removeSelectedExtraApp() {
        guard let bundleId = selection.flatMap(state.extraApp(forTarget:)) else { return }
        removeExtraApp(bundleId)
        selection = nil
    }

    /// Applies an edit to the state and saves.
    func edit(_ change: (inout CatalogState) -> Void) {
        change(&state)
        save()
    }

    func icon(for target: Target) -> EntryIcon {
        IconProvider.shared.icon(for: target)
    }

    /// Profile badges for every row, hidden ones included, as the settings list shows them.
    var badges: [String: ProfileBadge] {
        ProfileBadge.badges(for: state.rows.map { ($0.target, $0.displayName) })
    }

    // MARK: Edits

    func save() {
        do {
            state = try catalog.save(state)
            configError = nil
        } catch {
            configError = L("Couldn't save settings: %@", error.localizedDescription)
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        edit { $0.move(fromOffsets: source, toOffset: destination) }
    }

    func setHotkey(_ id: String, typed: String) {
        var previous: String?
        edit { previous = $0.setHotkey(id, typed: typed) }
        if let previous, let key = TargetSetting.normalizeHotkey(typed) {
            show(notice: L("Key %@ moved here from “%@”.", String(key).uppercased(), previous))
        }
    }

    private func show(notice text: String) {
        notice = text
        noticeReset?.cancel()
        noticeReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }

    func addExtraApp() {
        let panel = NSOpenPanel()
        panel.title = L("Choose an App")
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        edit { $0.addExtraApps(panel.urls.compactMap { environment.appInfo(at: $0)?.bundleId }) }
    }

    func removeExtraApp(_ id: String) {
        edit { $0.removeExtraApp(id) }
    }

    func chooseZenProfile() {
        let panel = NSOpenPanel()
        panel.title = L("Choose a Zen Profile Folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = ZenProfile.defaultRoot(home: environment.home).appendingPathComponent("Profiles")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        edit { $0.setZenProfile(url.path) }
    }

    func resetZenProfile() {
        edit { $0.setZenProfile(nil) }
    }

    func revealConfig() {
        let url = catalog.configURL
        if !FileManager.default.fileExists(atPath: url.path) {
            save()
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func makeDefaultBrowser() {
        DefaultBrowser.makeBrowserdoor()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try CurrentInstallation.shared.setLaunchAtLogin(enabled)
            loginItemError = nil
        } catch {
            log.error("login item: \(error.localizedDescription, privacy: .public)")
            loginItemError = L("Couldn't change the login item: %@", error.localizedDescription)
        }
        launchesAtLogin = CurrentInstallation.shared.launchesAtLogin
    }
}

// MARK: - Window

/// The settings window: one pane per toolbar tab, as in most Mac apps. The window takes each
/// pane's size and title; only Targets can be resized, and it keeps the size it was left at.
@MainActor
final class SettingsWindowController: NSObject, NSToolbarDelegate {
    enum Tab: String, CaseIterable {
        case general, targets, advanced
    }

    private struct Pane {
        var label: String
        var symbol: String
        var view: NSView
        /// Fixed content size; nil for the resizable Targets pane.
        var size: NSSize?
    }

    static let shared = SettingsWindowController()
    private static let targetsSizeKey = "SettingsTargetsSize"
    /// Where the window was; the pane decides its size.
    private static let frameName = "BrowserdoorSettings"
    private static let targetsMinSize = NSSize(width: 560, height: 400)

    private let model = SettingsModel()
    private var window: NSWindow?
    private var panes: [Tab: Pane] = [:]
    private var shown: Tab?

    var isShowing: Bool {
        window?.isVisible == true
    }

    func show(tab: Tab? = nil) {
        model.reload()
        if window == nil {
            makeWindow()
        }
        select(tab ?? shown ?? .general, animated: false)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func revealConfig() {
        model.revealConfig()
    }

    private func makeWindow() {
        panes = [
            .general: Pane(label: L("General"), symbol: "gearshape",
                           view: Self.host(GeneralTab(model: model, updates: UpdateChecker.shared)),
                           size: NSSize(width: 560, height: 300)),
            .targets: Pane(label: L("Targets"), symbol: "list.bullet", view: Self.host(TargetsTab(model: model)), size: nil),
            .advanced: Pane(label: L("Advanced"), symbol: "slider.horizontal.3",
                            view: Self.host(AdvancedTab(model: model)), size: NSSize(width: 560, height: 260)),
        ]
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 560, height: 300)),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        let toolbar = NSToolbar(identifier: "BrowserdoorSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
        for name in [NSWindow.didEndLiveResizeNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rememberTargetsSize() }
            }
        }
        self.window = window
        let restored = window.setFrameUsingName(Self.frameName)
        window.setFrameAutosaveName(Self.frameName)
        select(.general, animated: false)
        if !restored {
            window.center()
        }
    }

    private static func host(_ view: some View) -> NSView {
        let hosting = NSHostingView(rootView: view)
        // The window's size comes from the pane, not from SwiftUI's ideal size.
        hosting.sizingOptions = []
        return hosting
    }

    /// Shows a pane, sizing the window to it with its top edge in place.
    private func select(_ tab: Tab, animated: Bool) {
        guard let window, let pane = panes[tab] else { return }
        window.toolbar?.selectedItemIdentifier = NSToolbarItem.Identifier(tab.rawValue)
        guard tab != shown else { return }
        rememberTargetsSize()
        shown = tab
        window.title = pane.label
        let size = pane.size ?? Self.storedTargetsSize
        if pane.size == nil {
            window.styleMask.insert(.resizable)
            window.contentMinSize = Self.targetsMinSize
        } else {
            window.styleMask.remove(.resizable)
            window.contentMinSize = size
        }
        // Swap the content first at its new size, so the old pane doesn't stretch while the
        // window animates.
        window.contentView = NSView()
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
        window.contentView = pane.view
    }

    private static var storedTargetsSize: NSSize {
        guard let string = UserDefaults.standard.string(forKey: targetsSizeKey) else {
            return NSSize(width: 620, height: 520)
        }
        let size = NSSizeFromString(string)
        return NSSize(width: max(size.width, targetsMinSize.width), height: max(size.height, targetsMinSize.height))
    }

    private func rememberTargetsSize() {
        guard shown == .targets, let window, window.isVisible else { return }
        let size = window.contentRect(forFrameRect: window.frame).size
        UserDefaults.standard.set(NSStringFromSize(size), forKey: Self.targetsSizeKey)
    }

    @objc private func toolbarItemClicked(_ item: NSToolbarItem) {
        if let tab = Tab(rawValue: item.itemIdentifier.rawValue) {
            select(tab, animated: true)
        }
    }

    // MARK: NSToolbarDelegate

    func toolbar(_: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar _: Bool) -> NSToolbarItem?
    {
        guard let tab = Tab(rawValue: identifier.rawValue), let pane = panes[tab] else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = pane.label
        item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.label)
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }

    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        Tab.allCases.map { NSToolbarItem.Identifier($0.rawValue) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }
}

// MARK: - Views

private struct GeneralTab: View {
    @Bindable var model: SettingsModel
    @Bindable var updates: UpdateChecker
    @Bindable var statusMenu = StatusMenu.shared

    var body: some View {
        Form {
            Section {
                LabeledContent(L("Default browser")) {
                    if model.isDefaultBrowser {
                        Label(L("Browserdoor handles links"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button(L("Make Browserdoor the Default Browser")) { model.makeDefaultBrowser() }
                    }
                }
                Toggle(isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )) {
                    Text(L("Start at login"))
                    if let error = model.loginItemError {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Toggle(isOn: $statusMenu.isVisible) {
                    Text(L("Show in menu bar"))
                    if !statusMenu.isVisible {
                        Text(L("To get back here, open Browserdoor again, e.g. from Spotlight."))
                    }
                }
            }
            Section(L("Updates")) {
                Toggle(L("Check for updates automatically"), isOn: $updates.automatic)
                LabeledContent(L("Version %@", RunningApp.version)) {
                    HStack {
                        statusText
                        Button(L("Check Now")) { Task { await updates.checkNow() } }
                            .disabled(updates.status == .checking)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var statusText: some View {
        switch updates.status {
        case .idle: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case .upToDate: Text(L("Up to date")).foregroundStyle(.secondary)
        case let .available(release): Text(L("%@ available", release.version.description)).foregroundStyle(.orange)
        case .failed: Text(L("Check failed")).foregroundStyle(.red)
        }
    }
}

private struct TargetsTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Drag to reorder. Hidden targets don't appear in the picker. Without a custom key, targets get number keys. Right-click a target for more."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                List(selection: $model.selection) {
                    let keys = model.state.effectiveKeys
                    let badges = model.badges
                    ForEach(model.state.rows) { row in
                        TargetRow(row: row, key: keys[row.id], badge: badges[row.id], model: model)
                            .tag(row.id as String?)
                    }
                    .onMove { model.move(from: $0, to: $1) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                Divider()
                HStack(spacing: 0) {
                    Button { model.addExtraApp() } label: {
                        Image(systemName: "plus").frame(width: 24, height: 20)
                    }
                    .help(L("Add an app that isn't a browser but can open web links, e.g. a web-app wrapper"))
                    .accessibilityLabel(L("Add App…"))
                    Divider().frame(height: 16)
                    Button { model.removeSelectedExtraApp() } label: {
                        Image(systemName: "minus").frame(width: 24, height: 20)
                    }
                    .disabled(!model.selectionIsExtraApp)
                    .help(L("Remove the selected app (only apps you added)"))
                    .accessibilityLabel(L("Remove"))
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            ForEach(model.state.unlistedExtraApps, id: \.self) { bundleId in
                HStack {
                    Text(L("Added app %@ isn't a target (not installed, or listed by its profiles).", bundleId))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Remove")) { model.removeExtraApp(bundleId) }
                }
            }
            if let error = model.configError {
                Text(error).font(.callout).foregroundStyle(.red)
            } else if let notice = model.notice {
                Text(notice).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
}

private struct TargetRow: View {
    let row: TargetSetting
    /// The key the picker shows for this row; nil when hidden or out of keys.
    let key: Character?
    let badge: ProfileBadge?
    let model: SettingsModel
    @FocusState private var nameFocused: Bool

    private var isDefault: Bool {
        model.state.defaultTarget == row.id
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).accessibilityHidden(true)
            Toggle(L("Show in picker"), isOn: Binding(
                get: { !row.hidden },
                set: { visible in model.edit { $0.setHidden(row.id, !visible) } }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help(L("Show in picker"))
            BadgedIcon(icon: model.icon(for: row.target), badge: badge, size: 22)
                .accessibilityHidden(true)
            TextField(row.target.name, text: Binding(
                get: { row.displayName },
                set: { name in model.edit { $0.rename(row.id, to: name) } }
            ))
            .textFieldStyle(.plain)
            .focused($nameFocused)
            .opacity(row.hidden ? 0.5 : 1)
            .help(row.label == nil ? L("Click to rename") : L("Renamed from “%@”", row.target.name))
            .accessibilityLabel(L("Name"))
            Spacer(minLength: 8)
            HotkeyRecorder(
                key: row.hotkey,
                placeholder: key.map { String($0).uppercased() } ?? "–",
                targetName: row.displayName,
                onSet: { model.setHotkey(row.id, typed: $0) }
            )
            Button {
                model.edit { $0.toggleDefault(row.id) }
            } label: {
                Image(systemName: isDefault ? "star.fill" : "star")
                    .foregroundStyle(isDefault ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(isDefault ? L("Default target (Enter)") : L("Make default target (Enter)"))
            .accessibilityLabel(L("Default target (Enter)"))
            .accessibilityValue(isDefault ? L("On") : L("Off"))
        }
        .padding(.vertical, 2)
        .contextMenu { contextMenu }
        .onChange(of: model.renaming) { _, id in
            if id == row.id {
                nameFocused = true
                model.renaming = nil
            }
        }
    }

    @ViewBuilder private var contextMenu: some View {
        Button(L("Rename")) { model.renaming = row.id }
        Button(isDefault ? L("Remove as Default Target") : L("Make Default Target")) {
            model.edit { $0.toggleDefault(row.id) }
        }
        Button(row.hidden ? L("Show in Picker") : L("Hide in Picker")) {
            model.edit { $0.setHidden(row.id, !row.hidden) }
        }
        if let bundleId = model.state.extraApp(forTarget: row.id) {
            Divider()
            Button(L("Remove App")) { model.removeExtraApp(bundleId) }
        }
    }
}

/// The key a target opens with: click, press a key. Esc cancels, ⌫ removes the custom key.
private struct HotkeyRecorder: View {
    /// The custom key, if any.
    let key: Character?
    /// What the picker shows without a custom key (the automatic number), or "–".
    let placeholder: String
    let targetName: String
    let onSet: (String) -> Void
    @State private var recording = false
    @FocusState private var focused: Bool

    var body: some View {
        Button { startRecording() } label: {
            Text(recording ? "…" : key.map { String($0).uppercased() } ?? placeholder)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(key == nil && !recording ? .secondary : .primary)
                .frame(width: 28, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(recording ? Color.accentColor : Color(nsColor: .separatorColor),
                                      lineWidth: recording ? 2 : 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Always focusable: a focus request in the same update that made it focusable can be
        // dropped, which would leave the field waiting for a key that never arrives.
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: .down) { press in handle(press) }
        .onChange(of: focused) { _, isFocused in
            if !isFocused {
                recording = false
            }
        }
        .help(recording ? L("Press a key; Esc cancels, ⌫ removes the key") : L("Shortcut key in the picker"))
        .accessibilityLabel(L("Shortcut key in the picker"))
        .accessibilityValue(key.map { String($0).uppercased() } ?? L("Automatic: %@", placeholder))
        .accessibilityHint(L("Press a key; Esc cancels, ⌫ removes the key"))
    }

    private func startRecording() {
        recording = true
        focused = true
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        guard recording else { return .ignored }
        switch press.key {
        case .escape:
            break
        case .delete, .deleteForward:
            onSet("")
        default:
            guard press.modifiers.isDisjoint(with: [.command, .control, .option]),
                  let typed = press.characters.last, !typed.isWhitespace, !typed.isNewline,
                  typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            else { return .handled }
            onSet(String(typed))
        }
        recording = false
        focused = false
        return .handled
    }
}

private struct AdvancedTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent(L("Profile")) {
                    HStack {
                        Text(model.state.zenProfilePath.map { ($0 as NSString).lastPathComponent } ?? L("Automatic (default profile)"))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(L("Choose…")) { model.chooseZenProfile() }
                        if model.state.zenProfilePath != nil {
                            Button(L("Reset")) { model.resetZenProfile() }
                        }
                    }
                }
            } header: {
                Text("Zen")
            }
            Section {
                LabeledContent("~/.config/browserdoor/config.json") {
                    Button(L("Show in Finder")) { model.revealConfig() }
                }
            } header: {
                Text(L("Configuration file"))
            } footer: {
                Text(L("The settings live in this file, so you can keep it in your dotfiles."))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
