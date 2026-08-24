import SwiftUI

struct SettingsDetailView<Content: View>: View {
    let tab: SettingsTab
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsViewHeader(tab)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SettingsViewHeader: View {
    let tab: SettingsTab

    init(_ tab: SettingsTab) {
        self.tab = tab
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsTabIcon(tab: tab, isSelected: true)
            Text(tab.title)
                .font(.headline)
            Spacer()
        }
    }
}
