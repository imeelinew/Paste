import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings

    var body: some View {
        SettingsPane(
            title: "General",
            subtitle: "Customize Paste's language and startup behavior."
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
        }
        .onAppear { settings.launchAtLogin = LaunchAtLogin.isEnabled }
    }
}
