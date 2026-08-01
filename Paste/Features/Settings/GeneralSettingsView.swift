import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings

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

            SettingsCard(header: "Input Method") {
                SettingsRow(
                    title: "Switch to English When Opening"
                ) {
                    Toggle(
                        "Switch to English When Opening",
                        isOn: $settings.switchToEnglishInputOnOpen
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Switch to English When Opening")
                }
            }

            SettingsCard(header: "Appearance") {
                AppearanceIconPicker(selection: $settings.appearance)
            }
        }
        .onAppear {
            settings.launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}
