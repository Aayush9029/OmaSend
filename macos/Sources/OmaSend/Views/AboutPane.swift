import AppKit
import SwiftUI

struct AboutPane: View {
    let model: AppModel

    var body: some View {
        SettingsForm {
            Section {
                HStack(spacing: 14) {
                    appIcon
                        .frame(width: 56, height: 56)
                        .omaGlass(cornerRadius: 14)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("OmaSend").font(.title2.weight(.semibold))
                        Text("Version \(appVersion)").font(.caption).foregroundStyle(.secondary)
                        Text("Shares clipboard history between your Mac and Linux computers.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }

            Section("This Mac") {
                LabeledContent("Name", value: model.deviceName)
                LabeledContent("Connected Devices", value: "\(model.peers.count)")
                LabeledContent("Clipboard Items", value: "\(model.history.count)")
            }
        }
    }

    @ViewBuilder private var appIcon: some View {
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png", subdirectory: "Resources"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "paperplane.fill").font(.system(size: 30)).foregroundStyle(.blue)
        }
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
