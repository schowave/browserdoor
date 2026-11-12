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

        model.session = PickerSession(links: urls, catalog: TargetCatalog(environment: SystemEnvironment()).load(),
                                      pointer: NSEvent.mouseLocation)

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
        if session != model.session {
            model.session = session
        }
        let opensSettings = effects.contains(.openSettings)
        for effect in effects {
            switch effect {
            case .close:
                // The settings window takes the focus; otherwise it goes back where the click came from.
                close(returnFocus: !opensSettings)
            case .openSettings:
                SettingsWindowController.shared.show()
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

    private func close(returnFocus: Bool = true) {
        panel?.orderOut(nil)
        model.session = nil
        if returnFocus, NSApp.isActive {
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
            PickerHeader(session: session, onInput: onInput)
            Divider()
            if session.entries.isEmpty {
                EmptyPicker(onInput: onInput)
            } else {
                rows(session)
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

    private func rows(_ session: PickerSession) -> some View {
        VStack(spacing: 2) {
            ForEach(Array(session.entries.enumerated()), id: \.element.id) { index, entry in
                RowView(
                    entry: entry,
                    badge: session.badges[entry.id],
                    selected: index == session.selection,
                    isDefault: index == session.defaultRow,
                    onPick: { onInput(.click(row: index)) }
                )
                .onContinuousHover { phase in
                    if case .active = phase {
                        onInput(.hover(row: index, pointer: NSEvent.mouseLocation))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("Targets"))
    }
}

/// The link(s) waiting: host in bold, the rest in gray; and the copy button.
private struct PickerHeader: View {
    var session: PickerSession
    var onInput: (PickerInput) -> Void

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    var body: some View {
        let displays = session.links.map { LinkDisplay($0, home: Self.home) }
        HStack(spacing: 6) {
            Group {
                if displays.count == 1, let link = displays.first {
                    (Text(link.primary).fontWeight(.semibold).foregroundStyle(.primary)
                        + Text(link.secondary).foregroundStyle(.secondary))
                        .accessibilityLabel(link.line)
                } else {
                    Text(L("%ld links", displays.count)).foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(displays.map(\.line).joined(separator: "\n"))
            Spacer(minLength: 4)
            Button { onInput(.copyButton) } label: {
                Image(systemName: session.copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .help(L("Copy URL (⌘C)"))
            .accessibilityLabel(session.copied ? L("Copied") : L("Copy URL"))
        }
        .padding(.horizontal, 4)
    }
}

/// Shown when every target is hidden.
private struct EmptyPicker: View {
    var onInput: (PickerInput) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(L("No visible targets")).foregroundStyle(.secondary)
            Button(L("Settings…")) { onInput(.settingsButton) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct RowView: View {
    var entry: PickerEntry
    var badge: ProfileBadge?
    var selected: Bool
    var isDefault: Bool
    var onPick: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            BadgedIcon(icon: IconProvider.shared.icon(for: entry.target), badge: badge, size: 24)
            Text(entry.label).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            if isDefault {
                KeyCap(text: "↩", selected: selected)
            }
            if let key = entry.hotkey {
                KeyCap(text: String(key).uppercased(), selected: selected)
            }
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color(nsColor: .selectedContentBackgroundColor) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onPick)
        .help(entry.label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.label)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onPick)
    }

    private var accessibilityHint: String {
        var parts: [String] = []
        if let key = entry.hotkey {
            parts.append(L("Key %@", String(key).uppercased()))
        }
        if isDefault {
            parts.append(L("Opens with Return"))
        }
        return parts.joined(separator: ", ")
    }
}

/// A key shown as a small cap, e.g. the hotkey or ↩.
private struct KeyCap: View {
    var text: String
    var selected: Bool

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(selected ? AnyShapeStyle(Color.white.opacity(0.25)) : AnyShapeStyle(.quaternary))
            )
    }
}

/// A target's icon with its profile badge, if it has one, in the bottom-right corner.
struct BadgedIcon: View {
    var icon: EntryIcon
    var badge: ProfileBadge?
    var size: CGFloat

    var body: some View {
        IconView(icon: icon)
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if let badge {
                    let diameter = (size * 0.55).rounded()
                    Text(badge.letter)
                        .font(.system(size: diameter * 0.62, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: diameter, height: diameter)
                        .background(Circle().fill(Color(rgb: badge.color)))
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1))
                        .offset(x: diameter * 0.25, y: diameter * 0.2)
                        .accessibilityHidden(true)
                }
            }
    }
}

extension Color {
    init(rgb: RGB) {
        self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
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
