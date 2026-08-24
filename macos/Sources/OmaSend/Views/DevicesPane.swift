import SwiftUI

struct DevicesPane: View {
    let model: AppModel

    var body: some View {
        SettingsForm {
            Section("Pairing") {
                LabeledContent("This Mac", value: model.deviceName)
                HStack {
                    Button("Copy Pairing Code") { model.copyPairingCode() }
                    Button("Pair Another Device...") { model.promptForPairingCode() }
                    Spacer()
                    Button("Reset Code...", role: .destructive) { model.regeneratePairingCode() }
                }
                .controlSize(.small)
            }

            Section("Connected Devices") {
                if model.peers.isEmpty {
                    ContentUnavailableView(
                        "No Devices Found",
                        systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                        description: Text("Open OmaSend on a paired Linux computer.")
                    )
                } else {
                    ForEach(model.peers) { peer in
                        LabeledContent {
                            Text(peer.via).foregroundStyle(.secondary)
                        } label: {
                            Label(peer.name, systemImage: peer.via == "Tailscale" ? "network" : "wifi")
                        }
                    }
                }
            }

            Section("Privacy") {
                Text("Clipboard text is encrypted with your pairing code before it leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

