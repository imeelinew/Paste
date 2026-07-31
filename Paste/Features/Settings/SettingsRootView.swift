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
        AppKitSettingsSidebar(
            tabs: SettingsTab.allCases,
            selectedTab: $tab,
            locale: settings.language.locale
        )
        .navigationSplitViewColumnWidth(
            min: 150,
            ideal: Theme.Size.settingsSidebar,
            max: Theme.Size.settingsSidebar
        )
    }
}
