import AppKit
import SwiftUI
import DoormanCore

@MainActor @Observable
final class PickerModel {
    struct Row: Identifiable {
        var entry: PickerEntry
        var icon: EntryIcon
        var id: String { entry.id }
    }

    var urls: [URL] = []
    var rows: [Row] = []
    var selection = 0
    var warning: String?
    var copied = false
}

/// Borderless floating panel that receives keys without activating other windows of the app.
final class PickerPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

@MainActor
final class PickerController: NSObject, NSWindowDelegate {
    private let model = PickerModel()
    private let icons = IconProvider()
    private var panel: PickerPanel?

    /// Shows the picker for `urls`, or adds them to the picker that is already open.
    func show(urls: [URL]) {
        guard !urls.isEmpty else { return }
        log.debug("show \(urls.count) url(s)")
        if let panel, panel.isVisible {
            model.urls += urls.filter { !model.urls.contains($0) }
            resize(panel)
            return
        }

        model.urls = urls
        model.copied = false
        reload()

        let panel = self.panel ?? makePanel()
        self.panel = panel
        resize(panel)
        position(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    private func reload() {
        let environment = SystemEnvironment()
        var config = Config()
        model.warning = nil
        do {
            config = try Config.load(from: Config.fileURL(home: environment.home))
        } catch {
            model.warning = "config.json fehlerhaft – Defaults aktiv"
        }
        let profileOverride = config.zen?.profilePath.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
        }
        let targets = Discovery(environment: environment, zenProfileOverride: profileOverride, extraApps: config.extraApps ?? []).discover()
        let entries = config.entries(for: targets)
        model.rows = entries.map { PickerModel.Row(entry: $0, icon: icons.icon(for: $0.target)) }
        model.selection = config.defaultIndex(in: entries) ?? 0
    }

    private func makePanel() -> PickerPanel {
        let panel = PickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        panel.contentView = NSHostingView(rootView: PickerView(
            model: model,
            onPick: { [weak self] index in self?.pick(index) },
            onCopy: { [weak self] in self?.copyURLs() }
        ))
        return panel
    }

    private func resize(_ panel: NSPanel) {
        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        var frame = panel.frame
        frame.origin.y += frame.height - size.height // keep the top edge in place
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    /// Top-left corner slightly below-right of the mouse, clamped to the screen.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let size = panel.frame.size
        var origin = NSPoint(x: mouse.x - 24, y: mouse.y - size.height + 12)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53: close(); return true // esc
        case 36, 76: pick(model.selection); return true // return, enter
        case 126: moveSelection(-1); return true // up
        case 125: moveSelection(1); return true // down
        default: break
        }
        guard let chars = event.charactersIgnoringModifiers?.lowercased(), chars.count == 1 else { return false }
        if flags == .command, chars == "c" { copyURLs(); return true }
        guard flags.isDisjoint(with: [.command, .control, .option]) else { return false }
        if let index = model.rows.firstIndex(where: { $0.entry.hotkey.map(String.init) == chars }) {
            pick(index)
            return true
        }
        return false
    }

    private func moveSelection(_ delta: Int) {
        guard !model.rows.isEmpty else { return }
        model.selection = (model.selection + delta + model.rows.count) % model.rows.count
    }

    private func pick(_ index: Int) {
        guard model.rows.indices.contains(index) else { return }
        let urls = model.urls
        let target = model.rows[index].entry.target
        close()
        Launcher.open(urls, in: target)
    }

    private func copyURLs() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.urls.map(\.absoluteString).joined(separator: "\n"), forType: .string)
        model.copied = true
    }

    private func close() {
        panel?.orderOut(nil)
        model.urls = []
        // Hand focus back to wherever the click came from.
        if NSApp.isActive { NSApp.hide(nil) }
    }

    func windowDidResignKey(_ notification: Notification) {
        log.debug("panel resigned key")
        if panel?.isVisible == true { close() }
    }
}

struct PickerView: View {
    @Bindable var model: PickerModel
    var onPick: (Int) -> Void
    var onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Divider()
            VStack(spacing: 2) {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    RowView(row: row, selected: index == model.selection)
                        .contentShape(Rectangle())
                        .onTapGesture { onPick(index) }
                        .onHover { if $0 { model.selection = index } }
                }
            }
            if let warning = model.warning {
                Text(warning).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(10)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Group {
                if model.urls.count == 1, let url = model.urls.first {
                    Text(url.absoluteString)
                } else {
                    Text("\(model.urls.count) Links")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(model.urls.map(\.absoluteString).joined(separator: "\n"))
            Spacer(minLength: 4)
            Button(action: onCopy) {
                Image(systemName: model.copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("URL kopieren (⌘C)")
        }
        .padding(.horizontal, 4)
    }
}

struct RowView: View {
    var row: PickerModel.Row
    var selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            IconView(icon: row.icon).frame(width: 24, height: 24)
            Text(row.entry.label).lineLimit(1)
            Spacer()
            if let key = row.entry.hotkey {
                Text(String(key).uppercased())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor.opacity(0.25) : .clear)
        )
    }
}

struct IconView: View {
    var icon: EntryIcon

    var body: some View {
        switch icon {
        case .image(let image):
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        case .zenSpace(let glyph, let color):
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(color)
                switch glyph {
                case .svg(let image):
                    Image(nsImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.black.opacity(0.75))
                        .padding(5)
                case .text(let text):
                    Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black.opacity(0.75))
                }
            }
        }
    }
}
