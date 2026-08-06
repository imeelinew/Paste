import AppKit
import SwiftUI

/// Layout metrics for the Preferences-style settings form (visual only).
enum PreferencesMetrics {
    static let labelWidth: CGFloat = 132
    static let gutter: CGFloat = 12
    static let contentPaddingH: CGFloat = 28
    static let contentPaddingV: CGFloat = 22
    static let rowSpacing: CGFloat = 18
    static let appListMaxWidth: CGFloat = 280
}

/// Vertical stack used by each settings tab.
struct PreferencesForm<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: PreferencesMetrics.rowSpacing) {
            content
        }
        .padding(.horizontal, PreferencesMetrics.contentPaddingH)
        .padding(.vertical, PreferencesMetrics.contentPaddingV)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Two-column Preferences row: trailing-aligned label, leading-aligned control.
struct PreferencesRow<Content: View>: View {
    let label: LocalizedStringKey
    var alignment: VerticalAlignment = .center
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: alignment, spacing: PreferencesMetrics.gutter) {
            Text(label)
                .font(.body)
                .multilineTextAlignment(.trailing)
                .frame(width: PreferencesMetrics.labelWidth, alignment: .trailing)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PreferencesDivider: View {
    var body: some View {
        Divider()
    }
}
