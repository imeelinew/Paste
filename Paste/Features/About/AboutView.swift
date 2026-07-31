import AppKit
import SwiftUI

struct AboutView: View {
    private static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "Version \(short) (\(build))"
    }

    @MainActor private static let appIcon: NSImage =
        NSApp.applicationIconImage ?? NSWorkspace.shared.icon(for: .applicationBundle)
    private static let iconSize: CGFloat = 88

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    hero
                    links
                    attribution
                }
                .padding(Theme.Spacing.xxl)
                .frame(maxWidth: .infinity)
                .overlayScroller()
            }
            footer.padding(.bottom, Theme.Spacing.xxl)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var hero: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Image(nsImage: Self.appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)

            VStack(spacing: Theme.Spacing.sm) {
                Text("Paste").font(.title.weight(.bold))
                Text(Self.version)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs / 2)
                    .background(Capsule().fill(Theme.Colors.cardFill))
                    .overlay(Capsule().strokeBorder(Theme.Colors.cardStroke, lineWidth: 1))
            }

            Text("A tiny, native macOS clipboard history.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var links: some View {
        SettingsCard(header: "Links") {
            VStack(spacing: 0) {
                ForEach(AboutLink.all) { link in
                    if link.id != AboutLink.all.first?.id { SettingsDivider() }
                    AboutLinkRow(link: link)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    private var attribution: some View {
        SettingsCallout(
            title: "Built from TinyCast",
            message: "Paste extracts TinyCast's clipboard experience and preserves its AGPL-3.0 license.",
            systemImage: "bolt.fill",
            tint: Theme.Colors.brand
        )
    }

    private var footer: some View {
        Text("Derived from TinyCast · Released under AGPL-3.0")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

private struct AboutLink: Identifiable {
    let id: String
    let systemImage: String
    let title: String
    let detail: String
    let url: URL

    static let all: [AboutLink] = [
        AboutLink(
            id: "source", systemImage: "chevron.left.forwardslash.chevron.right",
            title: "TinyCast Source", detail: "github.com/abue-ammar/tinycast",
            url: URL(string: "https://github.com/abue-ammar/tinycast")!),
        AboutLink(
            id: "license", systemImage: "doc.text", title: "License",
            detail: "GNU AGPL-3.0",
            url: URL(string: "https://github.com/abue-ammar/tinycast/blob/main/LICENSE")!),
    ]
}

private struct AboutLinkRow: View {
    let link: AboutLink
    @State private var hovered = false

    var body: some View {
        Button { NSWorkspace.shared.open(link.url) } label: {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: link.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: Theme.Size.settingsRowIcon)
                    .foregroundStyle(.secondary)
                Text(link.title).font(.body)
                Spacer(minLength: Theme.Spacing.xl)
                Text(link.detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hovered ? .secondary : .tertiary)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.lg)
            .background(hovered ? Theme.Colors.rowHover : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

@MainActor
final class AuxWindowController: NSObject, NSWindowDelegate {
    private var windows: [String: NSWindow] = [:]

    @discardableResult
    func show<Content: View>(
        id: String, title: String, size: CGSize, seamlessTitleBar: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> Bool {
        let window: NSWindow
        let isNew: Bool
        if let existing = windows[id] {
            window = existing
            isNew = false
        } else {
            isNew = true
            var style: NSWindow.StyleMask = [.titled, .closable]
            if seamlessTitleBar { style.insert(.fullSizeContentView) }
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: style,
                backing: .buffered,
                defer: false
            )
            window.title = title
            if seamlessTitleBar {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.isMovableByWindowBackground = true
            }
            window.isReleasedWhenClosed = false
            let hosting = NSHostingView(rootView: content())
            hosting.sizingOptions = []
            window.contentView = hosting
            window.delegate = self
            window.center()
            windows[id] = window
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { window.makeKeyAndOrderFront(nil) }
        return isNew
    }

    @discardableResult
    func focusExisting() -> Bool {
        guard let window = windows.values.first(where: { $0.isVisible }) ?? windows.values.first
        else { return false }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let id = windows.first(where: { $0.value === window })?.key
        else { return }
        windows.removeValue(forKey: id)
        if windows.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}
