import AppKit
import BrowserdoorCore
import SwiftUI

/// The picker on screen as it is after the last input; nil while it is closed.
@MainActor @Observable
final class PickerModel {
    var session: PickerSession?
}

/// Borderless floating panel that receives keys without activating other windows of the app.
final class PickerPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool {
        true
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class PickerController: NSObject, NSWindowDelegate {
    private let model = PickerModel()
    private var panel: PickerPanel?

    /// Resolves all icons once so slow work (extracting Zen's icons) starts before the first link.
    func prewarm() {
        for entry in TargetCatalog(environment: SystemEnvironment()).load().pickerEntries {
            _ = IconProvider.shared.icon(for: entry.target)
        }
    }

    /// Shows the picker for `urls`, or adds them to the picker that is already open.
    func show(urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let panel, panel.isVisible, model.session != nil {
            model.session?.add(urls)
            resize(panel)
            return
        }

        model.session = PickerSession(links: urls, catalog: TargetCatalog(environment: SystemEnvironment()).load())

        let panel = panel ?? makePanel()
        self.panel = panel
        resize(panel)
        position(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    /// Feeds input to the session and performs the resulting effects. False: not the picker's.
    @discardableResult
    private func handle(_ input: PickerInput) -> Bool {
        guard var session = model.session, let effects = session.handle(input) else { return false }
        model.session = session
        for effect in effects {
            switch effect {
            case .close:
                close()
            case let .open(links, target):
                Links.opener.open(links, in: target)
            case let .copy(text):
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
        return true
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
        panel.keyHandler = { [weak self] event in
            self?.handle(.key(
                keyCode: event.keyCode,
                characters: event.charactersIgnoringModifiers,
                modifiers: Self.modifiers(event.modifierFlags)
            )) ?? false
        }
        panel.contentView = NSHostingView(rootView: PickerView(
            model: model,
            onInput: { [weak self] input in self?.handle(input) }
        ))
        return panel
    }

    private func resize(_ panel: NSPanel) {
        guard let content = panel.contentView else { return }
        content.layoutSubtreeIfNeeded()
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        panel.setFrame(PickerPlacement.resized(panel.frame, to: content.fittingSize, visible: visible), display: true)
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        panel.setFrameOrigin(PickerPlacement.origin(mouse: mouse, size: panel.frame.size, visible: screen?.visibleFrame ?? .zero))
    }

    private static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var result: KeyModifiers = []
        if flags.contains(.command) {
            result.insert(.command)
        }
        if flags.contains(.control) {
            result.insert(.control)
        }
        if flags.contains(.option) {
            result.insert(.option)
        }
        if flags.contains(.shift) {
            result.insert(.shift)
        }
        if !flags.isDisjoint(with: [.capsLock, .function, .numericPad, .help]) {
            result.insert(.ignorable)
        }
        return result
    }

    private func close() {
        panel?.orderOut(nil)
        model.session = nil
        // Hand focus back to wherever the click came from.
        if NSApp.isActive {
            NSApp.hide(nil)
        }
    }

    func windowDidResignKey(_: Notification) {
        if panel?.isVisible == true {
            handle(.lostFocus)
        }
    }
}

struct PickerView: View {
    @Bindable var model: PickerModel
    var onInput: (PickerInput) -> Void

    var body: some View {
        if let session = model.session {
            content(session)
        }
    }

    private func content(_ session: PickerSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(session)
            Divider()
            VStack(spacing: 2) {
                ForEach(Array(session.entries.enumerated()), id: \.element.id) { index, entry in
                    RowView(entry: entry, selected: index == session.selection)
                        .contentShape(Rectangle())
                        .onTapGesture { onInput(.click(row: index)) }
                        .onHover { inside in
                            if inside {
                                onInput(.hover(row: index))
                            }
                        }
                }
            }
            if session.configIsUnreadable {
                Text(L("config.json is invalid; using defaults")).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(10)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
    }

    private func header(_ session: PickerSession) -> some View {
        HStack(spacing: 6) {
            Group {
                if session.links.count == 1, let url = session.links.first {
                    Text(url.absoluteString)
                } else {
                    Text(L("%ld links", session.links.count))
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .help(session.links.map(\.absoluteString).joined(separator: "\n"))
            Spacer(minLength: 4)
            Button { onInput(.copyButton) } label: {
                Image(systemName: session.copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help(L("Copy URL (⌘C)"))
        }
        .padding(.horizontal, 4)
    }
}

struct RowView: View {
    var entry: PickerEntry
    var selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            IconView(icon: IconProvider.shared.icon(for: entry.target)).frame(width: 24, height: 24)
            Text(entry.label).lineLimit(1)
            Spacer()
            if let key = entry.hotkey {
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
        case let .image(image):
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        case let .zenSpace(glyph, color):
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(color)
                switch glyph {
                case let .svg(image):
                    Image(nsImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(.black.opacity(0.75))
                        .padding(5)
                case let .text(text):
                    Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(.black.opacity(0.75))
                }
            }
        }
    }
}
