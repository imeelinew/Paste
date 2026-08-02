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

// MARK: - Row

/// A single settings line (title and trailing control); fixed vertical rhythm keeps every card
/// aligned regardless of the control.
struct SettingsRow<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        LabeledContent {
            trailing
        } label: {
            Text(title)
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
            .contentShape(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            )
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
