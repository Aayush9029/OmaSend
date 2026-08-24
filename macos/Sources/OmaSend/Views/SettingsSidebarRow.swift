import SwiftUI

struct SettingsSidebarRow: View {
    let tab: SettingsTab
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                SettingsTabIcon(tab: tab, isSelected: isSelected)
                Text(tab.title)
                    .font(.callout)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(isSelected ? 0.05 : 0.005))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

struct SettingsSidebarSection: View {
    let title: String?
    let tabs: [SettingsTab]
    let selected: SettingsTab
    let onSelect: (SettingsTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                ForEach(tabs) { tab in
                    SettingsSidebarRow(
                        tab: tab,
                        isSelected: selected == tab,
                        onSelect: { onSelect(tab) }
                    )
                }
            }
        }
    }
}
