import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @ObservedObject private var systemClipboardHistory = AppCore.shared.systemClipboardHistory

    var body: some View {
        SettingsPane(tab: .general) {
            SettingsCard(header: "Language") {
                SettingsRow(
                    title: "App Language"
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
                AppearanceIconPicker(selection: $settings.appearance)
            }

            SettingsCard(header: "Startup") {
                SettingsRow(
                    title: "Launch at Login"
                ) {
                    Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("Launch at Login")
                }
            }

            SettingsCard(header: "System Clipboard") {
                SettingsRow(
                    title: "Disable System Clipboard History"
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
