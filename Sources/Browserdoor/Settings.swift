import AppKit
import BrowserdoorCore
import SwiftUI
import UniformTypeIdentifiers

/// State behind the settings window. Every change is written to `config.json` right away;
/// the picker reads that file each time it opens.
@MainActor @Observable
final class SettingsModel {
    struct ExtraApp: Identifiable {
        var bundleId: String
        var name: String
        var icon: NSImage?
        var id: String {
            bundleId
        }
    }

    /// Loaded targets plus the edits made here; saved on every change.
    var state: CatalogState
    var isDefaultBrowser = false
    var launchesAtLogin = false
    var configError: String?
    var selection: String?

    private let environment = SystemEnvironment()
    private var catalog: TargetCatalog {
        TargetCatalog(environment: environment)
    }

    init() {
        state = TargetCatalog(environment: SystemEnvironment()).load()
    }

    func reload() {
        state = catalog.load()
        configError = state.configIsUnreadable ? L("config.json can't be read; saving here will replace it.") : nil
        isDefaultBrowser = DefaultBrowser.isBrowserdoor
        launchesAtLogin = CurrentInstallation.shared.launchesAtLogin
    }

    /// Apps the user added, with name and icon for display.
    var extraApps: [ExtraApp] {
        state.extraApps.map { bundleId in
            let info = catalog.extraAppInfo(bundleId)
            return ExtraApp(bundleId: bundleId, name: info.name, icon: info.url.map { NSWorkspace.shared.icon(forFile: $0.path) })
        }
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
        DefaultBrowser.makeBrowserdoor { [weak self] in self?.isDefaultBrowser = DefaultBrowser.isBrowserdoor }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try CurrentInstallation.shared.setLaunchAtLogin(enabled)
        } catch {
            log.error("login item: \(error.localizedDescription, privacy: .public)")
        }
        launchesAtLogin = CurrentInstallation.shared.launchesAtLogin
    }
}

/// Hosts the SwiftUI settings in a regular window (Browserdoor has no Dock icon or main menu).
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private let model = SettingsModel()
    private var window: NSWindow?

    func show() {
        model.reload()
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = L("Browserdoor Settings")
            window.contentView = NSHostingView(rootView: SettingsView(model: model, updates: UpdateChecker.shared))
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("BrowserdoorSettings")
            window.contentMinSize = NSSize(width: 560, height: 440)
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Views

struct SettingsView: View {
    @Bindable var model: SettingsModel
    @Bindable var updates: UpdateChecker

    var body: some View {
        TabView {
            GeneralTab(model: model, updates: updates)
                .tabItem { Label(L("General"), systemImage: "gearshape") }
            TargetsTab(model: model)
                .tabItem { Label(L("Targets"), systemImage: "list.bullet") }
            AdvancedTab(model: model)
                .tabItem { Label(L("Advanced"), systemImage: "slider.horizontal.3") }
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 440)
    }
}

private struct GeneralTab: View {
    @Bindable var model: SettingsModel
    @Bindable var updates: UpdateChecker

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
                Toggle(L("Start at login"), isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
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
            Text(L("Drag to reorder. Hidden targets don't appear in the picker. Without a custom key, targets get number keys."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                List(selection: $model.selection) {
                    let keys = model.state.effectiveKeys
                    ForEach(model.state.rows) { row in
                        TargetRow(row: row, key: keys[row.id], model: model).tag(row.id as String?)
                    }
                    .onMove { model.move(from: $0, to: $1) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                Divider()
                HStack(spacing: 0) {
                    Button { model.addExtraApp() } label: {
                        Image(systemName: "plus").frame(width: 24, height: 20)
                    }
                    .help(L("Add an app"))
                    Divider().frame(height: 16)
                    Button { model.removeSelectedExtraApp() } label: {
                        Image(systemName: "minus").frame(width: 24, height: 20)
                    }
                    .disabled(!model.selectionIsExtraApp)
                    .help(L("Remove the selected app (only apps you added)"))
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            if let error = model.configError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
    }
}

private struct TargetRow: View {
    let row: TargetSetting
    /// The key the picker shows for this row; nil when hidden or out of keys.
    let key: Character?
    let model: SettingsModel

    private var isDefault: Bool {
        model.state.defaultTarget == row.id
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            Toggle("", isOn: Binding(
                get: { !row.hidden },
                set: { visible in model.edit { $0.setHidden(row.id, !visible) } }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help(L("Show in picker"))
            IconView(icon: model.icon(for: row.target)).frame(width: 22, height: 22)
            TextField(row.target.name, text: Binding(
                get: { row.displayName },
                set: { name in model.edit { $0.rename(row.id, to: name) } }
            ))
            .textFieldStyle(.plain)
            .opacity(row.hidden ? 0.5 : 1)
            .help(row.label == nil ? L("Click to rename") : L("Renamed from “%@”", row.target.name))
            Spacer(minLength: 8)
            TextField(key.map { $0.uppercased() } ?? "–", text: Binding(
                get: { row.hotkey?.uppercased() ?? "" },
                set: { typed in model.edit { $0.setHotkey(row.id, typed: typed) } }
            ))
            .frame(width: 36)
            .multilineTextAlignment(.center)
            .font(.system(.body, design: .monospaced))
            .help(L("Shortcut key in the picker"))
            Button {
                model.edit { $0.toggleDefault(row.id) }
            } label: {
                Image(systemName: isDefault ? "star.fill" : "star")
                    .foregroundStyle(isDefault ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(isDefault ? L("Default target (Enter)") : L("Make default target (Enter)"))
        }
        .padding(.vertical, 2)
    }
}

private struct AdvancedTab: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                ForEach(model.extraApps) { app in
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                        }
                        Text(app.name)
                        Text(app.bundleId).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Remove")) { model.removeExtraApp(app.bundleId) }
                            .buttonStyle(.borderless)
                    }
                }
                Button(L("Add App…")) { model.addExtraApp() }
            } header: {
                Text(L("Additional apps"))
            } footer: {
                Text(L("Apps that aren't browsers but can open web links, e.g. a web-app wrapper."))
                    .foregroundStyle(.secondary)
            }
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
