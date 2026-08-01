import SwiftUI

extension Notification.Name {
    static let pasteSelectSettingsTab = Notification.Name("PasteSelectSettingsTab")
}

enum SettingsTab: Int, CaseIterable, Hashable, Identifiable {
    case general, clipboard, permissions

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .general: return "General"
        case .clipboard: return "Clipboard"
        case .permissions: return "Permissions"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .permissions: return "lock.shield.fill"
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
        ScrollViewReader { proxy in
            Form {
                GeneralSettingsView()
                ClipboardSettingsView()
                PermissionsSettingsView()
                DangerZoneSettingsView()
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 20, for: .scrollContent)
            .contentMargins(.top, 8, for: .scrollContent)
            .overlayScroller()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo(tab, anchor: .top)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pasteSelectSettingsTab)) { note in
                if let target = note.object as? SettingsTab {
                    tab = target
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
        }
        .background {
            SettingsWindowConfigurator()
                .frame(width: 0, height: 0)
        }
        .environment(\.locale, settings.language.locale)
    }
}
