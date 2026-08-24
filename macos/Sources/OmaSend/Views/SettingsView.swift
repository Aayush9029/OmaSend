import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            divider
                .padding(.vertical, -32)
            detail
        }
        .padding(.top, -12)
        .background {
            Rectangle()
                .fill(.thinMaterial)
                .ignoresSafeArea()
        }
        .frame(minWidth: 660, minHeight: 460)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSidebarSection(
                title: "OmaSend",
                tabs: [.general, .menuBar, .clipboard],
                selected: selectedTab,
                onSelect: select
            )

            SettingsSidebarSection(
                title: "Connections",
                tabs: [.devices, .about],
                selected: selectedTab,
                onSelect: select
            )

            Spacer()
        }
        .padding(14)
        .frame(width: 200, alignment: .topLeading)
    }

    private var divider: some View {
        Rectangle()
            .fill(.primary.opacity(0.1))
            .frame(width: 1)
    }

    private var selectedTab: SettingsTab { model.settingsTab ?? .general }

    private func select(_ tab: SettingsTab) {
        withAnimation(.easeInOut(duration: 0.18)) {
            model.settingsTab = tab
        }
    }

    @ViewBuilder private var detail: some View {
        SettingsDetailView(tab: selectedTab) {
            switch selectedTab {
            case .general: GeneralPane(model: model)
            case .menuBar: MenuBarPane(model: model)
            case .clipboard: ClipboardPane(model: model)
            case .devices: DevicesPane(model: model)
            case .about: AboutPane(model: model)
            }
        }
        .id(selectedTab)
        .transition(.opacity)
    }
}
