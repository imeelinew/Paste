import Combine
import SwiftUI

struct PermissionsSettingsView: View {
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsPane(tab: .permissions) {
            SettingsCard(header: "Accessibility") {
                SettingsRow(
                    title: "Accessibility"
                ) {
                    statusBadge
                }
                let actionTitle: LocalizedStringKey =
                    accessibilityTrusted ? "Manage in System Settings" : "Grant access"
                let buttonTitle: LocalizedStringKey =
                    accessibilityTrusted ? "Open…" : "Open Settings…"
                SettingsRow(
                    title: actionTitle
                ) {
                    Button(buttonTitle) {
                        Permissions.openAccessibilitySettings()
                    }
                }
            }
        }
        .onAppear { accessibilityTrusted = Permissions.isAccessibilityTrusted() }
        .onReceive(refreshTimer) { _ in
            let trusted = Permissions.isAccessibilityTrusted()
            if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        }
    }

    private var statusBadge: some View {
        HStack(spacing: Theme.Spacing.xs + 1) {
            Image(
                systemName: accessibilityTrusted
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            Text(
                accessibilityTrusted
                    ? LocalizedStringKey("Granted") : LocalizedStringKey("Not granted"))
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(accessibilityTrusted ? Color.green : Color.orange)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            Capsule().fill((accessibilityTrusted ? Color.green : Color.orange).opacity(0.14))
        )
    }
}
