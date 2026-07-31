import SwiftUI

struct SectionHeader: View {
    let title: String
    var isFirst = false

    var body: some View {
        Text(LocalizedStringKey(title))
            .font(Theme.Typography.sectionHeader)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, isFirst ? Theme.Spacing.xs : Theme.Spacing.sectionSpacing)
            .padding(.bottom, Theme.Spacing.sectionHeaderBottom)
    }
}
