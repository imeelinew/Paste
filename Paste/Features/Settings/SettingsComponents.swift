import AppKit
import SwiftUI

/// Reusable building blocks for the Settings window; all metrics come from `Theme` so Settings shares one vocabulary with the palette.

// MARK: - Pane scaffold

/// Obelisk-style settings detail: a compact title followed by native grouped Form sections.
struct SettingsPane<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 18, for: .scrollContent)
            .contentMargins(.top, 0, for: .scrollContent)
            .overlayScroller()
            .navigationTitle(title)
    }
}

// MARK: - Grouped card

/// Native grouped Form section, matching Obelisk's settings surfaces and automatic separators.
struct SettingsCard<Content: View>: View {
    var header: LocalizedStringKey? = nil
    @ViewBuilder var content: Content

    var body: some View {
        if let header {
            Section(header) { content }
        } else {
            Section { content }
        }
    }
}

/// The identical top card of a feature pane (Custom Commands, Snippets): the master switch, then its launcher-visibility companion, which locks while the feature is off.
struct FeatureSwitchCard: View {
    let header: LocalizedStringKey
    let enableTitle: LocalizedStringKey
    @Binding var isEnabled: Bool
    @Binding var showsInLauncher: Bool

    var body: some View {
        SettingsCard(header: header) {
            SettingsRow(
                title: enableTitle
            ) {
                Toggle(enableTitle, isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel(enableTitle)
            }
            SettingsRow(
                title: "Show in launcher"
            ) {
                Toggle("Show in launcher", isOn: $showsInLauncher)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Show in launcher")
            }
            // Same dim as ShortcutsSettingsView's hidden-category card.
            .opacity(isEnabled ? 1 : 0.45)
            .disabled(!isEnabled)
        }
    }
}

// MARK: - Row

/// A single settings line (title and trailing control); fixed vertical rhythm keeps every card
/// aligned regardless of the control.
struct SettingsRow<Trailing: View>: View {
    let title: LocalizedStringKey
    /// Optional state indicator rendered after the title (green = active, orange = attention).
    var statusDot: Color? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        LabeledContent {
            trailing
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text(title)
                if let statusDot {
                    Circle()
                        .fill(statusDot)
                        .frame(width: Theme.Size.statusDot, height: Theme.Size.statusDot)
                }
            }
        }
    }
}

// MARK: - Callout

/// A tinted inset box for a notice or warning inside a `SettingsCard` — SF Symbol + title + optional message, with an optional trailing control (e.g. a fix-it button).
struct SettingsCallout<Trailing: View>: View {
    let title: LocalizedStringKey
    var message: LocalizedStringKey? = nil
    var systemImage: String = "info.circle"
    var tint: Color = .secondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: Theme.Size.settingsRowIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
                Text(title).font(.body)
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Spacing.xl)
            trailing
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
    }
}

extension SettingsCallout where Trailing == EmptyView {
    init(
        title: LocalizedStringKey, message: LocalizedStringKey? = nil,
        systemImage: String = "info.circle", tint: Color = .secondary
    ) {
        self.init(title: title, message: message, systemImage: systemImage, tint: tint) { EmptyView() }
    }
}

/// Makes the hosting NSWindow transparent so the root `.hudWindow` material samples content
/// behind the window, exactly like Obelisk's window-level transparency configurator.
struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.invalidateShadow()
            window.contentView?.needsDisplay = true
        }
    }

    private final class Probe: NSView {
        override var isOpaque: Bool { false }
        override func draw(_ dirtyRect: NSRect) {}
    }
}
