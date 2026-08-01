import AppKit
import SwiftUI

/// Reusable building blocks for the Settings window; all metrics come from `Theme` so Settings shares one vocabulary with the palette.

// MARK: - Pane scaffold

/// Single-column settings page fragment: grouped sections for the parent Form.
/// `tab` is only a scroll anchor for deep-links (no page title chrome).
struct SettingsPane<Content: View>: View {
    var tab: SettingsTab? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content.id(tab)
    }
}

// MARK: - Grouped card

/// Native grouped Form section, matching System Settings inset cards and automatic separators.
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

// MARK: - Appearance picker

/// Icon-segment appearance control (System / Light / Dark), bound to the same `AppAppearance` values as before.
struct AppearanceIconPicker: View {
    @Binding var selection: AppAppearance

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(AppAppearance.allCases) { option in
                optionButton(option)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Theme")
    }

    private func optionButton(_ option: AppAppearance) -> some View {
        let selected = selection == option
        return Button {
            selection = option
        } label: {
            VStack(spacing: Theme.Spacing.sm) {
                appearancePreview(option)
                    .frame(width: 52, height: 36)
                Text(LocalizedStringKey(option.title))
                    .font(.caption)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.md)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(
                        selected ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: selected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(LocalizedStringKey(option.title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func appearancePreview(_ option: AppAppearance) -> some View {
        switch option {
        case .system:
            ZStack {
                previewWindow(fill: Color.white, stroke: Color.black.opacity(0.15))
                    .offset(x: -5, y: -3)
                previewWindow(fill: Color(white: 0.18), stroke: Color.white.opacity(0.12))
                    .offset(x: 5, y: 3)
            }
        case .light:
            previewWindow(fill: Color.white, stroke: Color.black.opacity(0.15))
        case .dark:
            previewWindow(fill: Color(white: 0.18), stroke: Color.white.opacity(0.12))
        }
    }

    private func previewWindow(fill: Color, stroke: Color) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 3) {
                    Circle().fill(Color.red.opacity(0.85)).frame(width: 4, height: 4)
                    Circle().fill(Color.yellow.opacity(0.85)).frame(width: 4, height: 4)
                    Circle().fill(Color.green.opacity(0.85)).frame(width: 4, height: 4)
                }
                .padding(5)
            }
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
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

/// Keeps the settings window on the standard opaque system surface (no HUD glass).
struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let window = nsView?.window else { return }
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
            window.invalidateShadow()
            window.contentView?.needsDisplay = true
        }
    }

    private final class Probe: NSView {
        override var isOpaque: Bool { true }
    }
}
