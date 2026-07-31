import SwiftUI

extension Notification.Name {
    static let pasteSelectSettingsTab = Notification.Name("PasteSelectSettingsTab")
}

enum SettingsTab: Int, CaseIterable, Hashable, Identifiable {
    case general, clipboard, permissions, about

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .clipboard: return "Clipboard"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .permissions: return "lock.shield.fill"
        case .about: return "info.circle.fill"
        }
    }

    var iconGradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .general:
            colors = [
                Color(red: 0.52, green: 0.64, blue: 0.78),
                Color(red: 0.28, green: 0.38, blue: 0.52),
            ]
        case .clipboard:
            colors = [
                Color(red: 1.0, green: 0.50, blue: 0.40),
                Color(red: 0.96, green: 0.28, blue: 0.24),
            ]
        case .permissions:
            colors = [
                Color(red: 0.72, green: 0.52, blue: 1.0),
                Color(red: 0.42, green: 0.24, blue: 0.86),
            ]
        case .about:
            colors = [
                Color(red: 0.36, green: 0.72, blue: 1.0),
                Color(red: 0.12, green: 0.46, blue: 0.92),
            ]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct SettingsRootView: View {
    @State private var tab: SettingsTab
    @ObservedObject private var settings = AppCore.shared.settings

    init(initialTab: SettingsTab = .general) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            Group {
                switch tab {
                case .general: GeneralSettingsView()
                case .clipboard: ClipboardSettingsView()
                case .permissions: PermissionsSettingsView()
                case .about: AboutView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background {
            VisualEffectView(material: .hudWindow, blending: .behindWindow)
                .ignoresSafeArea()
            SettingsWindowConfigurator()
                .frame(width: 0, height: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteSelectSettingsTab)) { note in
            if let target = note.object as? SettingsTab { tab = target }
        }
        .environment(\.locale, settings.language.locale)
    }

    private var sidebar: some View {
        List(selection: tabSelection) {
            ForEach(SettingsTab.allCases) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.systemImage)
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(item.iconGradient)
                        .frame(width: 18, height: 18)
                    Text(item.title)
                        .fontWeight(tab == item ? .semibold : .regular)
                    Spacer(minLength: 0)
                }
                .tag(item)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .navigationSplitViewColumnWidth(
            min: 150,
            ideal: Theme.Size.settingsSidebar,
            max: Theme.Size.settingsSidebar
        )
    }

    private var tabSelection: Binding<SettingsTab?> {
        Binding(
            get: { tab },
            set: { if let newValue = $0 { tab = newValue } }
        )
    }
}
