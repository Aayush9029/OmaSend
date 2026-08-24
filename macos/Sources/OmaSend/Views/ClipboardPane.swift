import SwiftUI

struct ClipboardPane: View {
    let model: AppModel

    var body: some View {
        SettingsForm {
            Section("Sync") {
                Toggle("Automatically copy incoming items", isOn: Binding(get: { model.autoCopy }, set: model.setAutoCopy))
                Text(model.autoCopy
                     ? "New items from paired devices replace the current clipboard."
                     : "New items stay in history until you select one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                LabeledContent("Saved Items", value: "\(model.history.count)")
                if let newest = model.history.first {
                    LabeledContent("Latest Device", value: newest.originName)
                }
            }

            Section("Limits") {
                LabeledContent("Maximum Items", value: "50")
                LabeledContent("Maximum Item Size", value: "10 MB")
            }
        }
    }
}
