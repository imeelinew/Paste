import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @ObservedObject private var systemClipboardHistory = AppCore.shared.systemClipboardHistory

    var body: some View {
        SettingsPane(
            title: "General",
            subtitle: "Customize Paste's language, appearance, and system behavior."
        ) {
            SettingsCard(header: "Language") {
                SettingsRow(
                    title: "App Language",
                    subtitle: "Choose the language used by Paste.",
                    systemImage: "globe",
                    tint: .blue
                ) {
                    Picker("App Language", selection: $settings.language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(LocalizedStringKey(language.title)).tag(language)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsCard(header: "Appearance") {
                SettingsRow(
                    title: "Theme",
                    subtitle: "Choose Paste's visual appearance.",
                    systemImage: "circle.lefthalf.filled",
                    tint: .purple
                ) {
                    Picker("Theme", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(LocalizedStringKey(appearance.title)).tag(appearance)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsCard(header: "Startup") {
                SettingsRow(
                    title: "Launch at Login",
                    subtitle: "Open Paste automatically when you log in.",
                    systemImage: "power",
                    tint: .green
                ) {
                    Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("Launch at Login")
                }
            }

            SettingsCard(header: "System Clipboard") {
                SettingsRow(
                    title: "Disable System Clipboard History",
                    subtitle: "Stop Spotlight from saving and searching clipboard history. Copy and paste keep working.",
                    systemImage: "magnifyingglass",
                    tint: .blue
                ) {
                    Toggle(
                        "Disable System Clipboard History",
                        isOn: Binding(
                            get: { systemClipboardHistory.isDisabled },
                            set: { systemClipboardHistory.setDisabled($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Disable System Clipboard History")
                }
            }
        }
        .onAppear {
            settings.launchAtLogin = LaunchAtLogin.isEnabled
            systemClipboardHistory.refresh()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            systemClipboardHistory.refresh()
        }
    }
}
