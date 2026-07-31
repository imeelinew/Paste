import SwiftUI

extension Notification.Name {
    static let pasteSelectSettingsTab = Notification.Name("PasteSelectSettingsTab")
}

enum SettingsTab: Int, CaseIterable, Identifiable {
    case clipboard, permissions, about

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .clipboard: return "Clipboard"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .clipboard: return "doc.on.clipboard"
        case .permissions: return "lock.shield"
        case .about: return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .clipboard: return .orange
        case .permissions: return .blue
        case .about: return .pink
        }
    }
}

struct SettingsRootView: View {
    @State private var tab: SettingsTab

    init(initialTab: SettingsTab = .clipboard) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Group {
                switch tab {
                case .clipboard: ClipboardSettingsView()
                case .permissions: PermissionsSettingsView()
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                VisualEffectView(material: .contentBackground, blending: .behindWindow)
                    .ignoresSafeArea()
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .pasteSelectSettingsTab)) { note in
            if let target = note.object as? SettingsTab { tab = target }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs / 2) {
            ForEach(SettingsTab.allCases) { item in
                SidebarRow(
                    title: item.title,
                    systemImage: item.systemImage,
                    tint: item.tint,
                    isSelected: tab == item
                ) { tab = item }
            }
            Spacer()
        }
        .padding(.top, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.md)
        .frame(width: Theme.Size.settingsSidebar)
        .frame(maxHeight: .infinity)
        .background(
            ZStack(alignment: .trailing) {
                VisualEffectView(material: .sidebar, blending: .behindWindow)
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
            }
            .ignoresSafeArea()
        )
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.lg) {
                RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                    .fill(tint.gradient)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
                Text(title).font(Theme.Typography.rowTitle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(background)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if isSelected { return Theme.Colors.selection }
        if hovering { return Theme.Colors.rowHover }
        return .clear
    }
}
