import SwiftUI

struct MenuBarPane: View {
    let model: AppModel

    var body: some View {
        SettingsForm {
            Section {
                MenuBarStylePicker(selection: model.menuBarStyle, peerCount: model.peers.count) {
                    model.setMenuBarStyle($0)
                }
                .padding(.vertical, 2)
            } header: {
                HStack {
                    Text("Appearance")
                    Spacer()
                    Text(model.menuBarStyle.displayName).foregroundStyle(.secondary)
                }
            }

            Section("Menu") {
                Toggle("Show device count", isOn: Binding(
                    get: { model.menuBarStyle == .iconAndCount },
                    set: { model.setMenuBarStyle($0 ? .iconAndCount : .icon) }
                ))
            }
        }
    }
}

