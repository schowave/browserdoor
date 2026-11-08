import AppKit
import DoormanCore
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

    var rows: [TargetSetting] = []
    var defaultTarget: String?
    var extraApps: [ExtraApp] = []
    var zenProfilePath: String?
    var isDefaultBrowser = false
    var launchesAtLogin = false
    var configError: String?

    private var config = Config()
    private let environment = SystemEnvironment()
    private var configURL: URL {
        Config.fileURL(home: environment.home)
    }

    func reload() {
        do {
            config = try Config.load(from: configURL)
            configError = nil
        } catch {
            config = Config()
            configError = L("config.json can't be read; saving here will replace it.")
        }
        let targets = discovery().discover()
        rows = config.settings(for: targets)
        defaultTarget = config.defaultTarget
        extraApps = (config.extraApps ?? []).map(Self.extraApp)
        zenProfilePath = config.zen?.profilePath
        isDefaultBrowser = DefaultBrowser.isDoorman
        launchesAtLogin = Installation.launchesAtLogin
    }

    private func discovery() -> Discovery {
        let profile = config.zen?.profilePath.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
        }
        return Discovery(environment: environment, zenProfileOverride: profile, extraApps: config.extraApps ?? [])
    }

    func icon(for target: Target) -> EntryIcon {
        IconProvider.shared.icon(for: target)
    }

    // MARK: Edits

    func save() {
        config.apply(rows)
        config.defaultTarget = defaultTarget
        config.extraApps = extraApps.map(\.bundleId)
        config.zen = zenProfilePath.map { Config.Zen(profilePath: $0) }
        do {
            try config.save(to: configURL)
            configError = nil
        } catch {
            configError = L("Couldn't save settings: %@", error.localizedDescription)
        }
    }

    func move(from source: IndexSet, to destination: Int) {
        rows.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func setDefault(_ id: String?) {
        defaultTarget = id
        save()
    }

    func addExtraApp() {
        let panel = NSOpenPanel()
        panel.title = L("Choose an App")
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = environment.appInfo(at: url)?.bundleId,
                  !extraApps.contains(where: { $0.bundleId == id }) else { continue }
            extraApps.append(Self.extraApp(id))
        }
        save()
        // New apps only show up as targets if they open web links; refresh the list.
        rows = config.settings(for: discovery().discover())
    }

    func removeExtraApp(_ id: String) {
        extraApps.removeAll { $0.bundleId == id }
        save()
        rows = config.settings(for: discovery().discover())
    }

    func chooseZenProfile() {
        let panel = NSOpenPanel()
        panel.title = L("Choose a Zen Profile Folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = ZenProfile.defaultRoot(home: environment.home).appendingPathComponent("Profiles")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        zenProfilePath = url.path
        save()
        reload()
    }

    func resetZenProfile() {
        zenProfilePath = nil
        save()
        reload()
    }

    func revealConfig() {
        if !FileManager.default.fileExists(atPath: configURL.path) {
            save()
        }
        NSWorkspace.shared.activateFileViewerSelecting([configURL])
    }

    func makeDefaultBrowser() {
        DefaultBrowser.makeDoorman { [weak self] in self?.isDefaultBrowser = DefaultBrowser.isDoorman }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        Installation.setLaunchAtLogin(enabled)
        launchesAtLogin = Installation.launchesAtLogin
    }

    private static func extraApp(_ bundleId: String) -> ExtraApp {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        let name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
        return ExtraApp(bundleId: bundleId, name: name ?? bundleId, icon: url.map { NSWorkspace.shared.icon(forFile: $0.path) })
    }
}

/// Hosts the SwiftUI settings in a regular window (Doorman has no Dock icon or main menu).
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
            window.title = L("Doorman Settings")
            window.contentView = NSHostingView(rootView: SettingsView(model: model, updates: UpdateChecker.shared))
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("DoormanSettings")
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
                        Label(L("Doorman handles links"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button(L("Make Doorman the Default Browser")) { model.makeDefaultBrowser() }
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
                        Button(L("Check Now")) { Task { await updates.check(userInitiated: true) } }
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
            List {
                ForEach($model.rows) { $row in
                    TargetRow(row: $row, model: model)
                }
                .onMove { model.move(from: $0, to: $1) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            if let error = model.configError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
    }
}

private struct TargetRow: View {
    @Binding var row: TargetSetting
    let model: SettingsModel

    private var isDefault: Bool {
        model.defaultTarget == row.id
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            Toggle("", isOn: Binding(
                get: { !row.hidden },
                set: { row.hidden = !$0; model.save() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help(L("Show in picker"))
            IconView(icon: model.icon(for: row.target)).frame(width: 22, height: 22)
            TextField(row.target.name, text: Binding(
                get: { row.label ?? "" },
                set: { row.label = $0.isEmpty ? nil : $0; model.save() }
            ))
            .textFieldStyle(.plain)
            .opacity(row.hidden ? 0.5 : 1)
            Spacer(minLength: 8)
            TextField(L("Key"), text: Binding(
                get: { row.hotkey ?? "" },
                set: { row.hotkey = TargetSetting.normalizeHotkey($0); model.save() }
            ))
            .frame(width: 44)
            .multilineTextAlignment(.center)
            .font(.system(.body, design: .monospaced))
            .help(L("Shortcut key in the picker"))
            Button {
                model.setDefault(isDefault ? nil : row.id)
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
                        Text(model.zenProfilePath.map { ($0 as NSString).lastPathComponent } ?? L("Automatic (default profile)"))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(L("Choose…")) { model.chooseZenProfile() }
                        if model.zenProfilePath != nil {
                            Button(L("Reset")) { model.resetZenProfile() }
                        }
                    }
                }
            } header: {
                Text("Zen")
            }
            Section {
                LabeledContent("~/.config/doorman/config.json") {
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
