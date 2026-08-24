import SwiftUI

struct GeneralPane: View {
    let model: AppModel

    var body: some View {
        SettingsForm {
            Section {
                HStack(alignment: .top, spacing: 20) {
                    ToggleCard(
                        title: "Open at Login",
                        description: "OmaSend starts when you log in.",
                        icon: "power",
                        isOn: model.launchAtLogin,
                        action: { model.setLaunchAtLogin(!model.launchAtLogin) }
                    ) {
                        AnimatedImage(resource: "launch-at-login")
                    }

                    ToggleCard(
                        title: "Show in Dock",
                        description: "Adds a Dock icon and an app switcher entry.",
                        icon: "dock.rectangle",
                        isOn: model.showsDockIcon,
                        action: { model.setShowsDockIcon(!model.showsDockIcon) }
                    ) {
                        AnimatedImage(resource: "dock-icon")
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }

            Section("Clipboard") {
                Toggle("Automatically copy incoming items", isOn: Binding(get: { model.autoCopy }, set: model.setAutoCopy))
                LabeledContent("Saved Items", value: "\(model.history.count)")
                LabeledContent("Connected Devices", value: "\(model.peers.count)")
            }
        }
    }
}
