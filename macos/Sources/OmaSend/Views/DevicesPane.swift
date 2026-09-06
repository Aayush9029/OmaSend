import SwiftUI

struct DevicesPane: View {
    let model: AppModel

    var body: some View {
        SettingsForm {
            Section("Pairing") {
                LabeledContent("This Mac", value: model.deviceName)
                Toggle("Trusted LAN · no pairing key", isOn: Binding(get: { model.trustedLAN }, set: { model.setTrustedLAN($0) }))
                if model.trustedLAN {
                    Text("Unencrypted. Anyone on this local network can read or send items.").font(.callout).foregroundStyle(.secondary)
                } else {
                HStack {
                    Button("Copy Pairing Code") { model.copyPairingCode() }
                    Button("Pair Another Device...") { model.promptForPairingCode() }
                    Spacer()
                    Button("Reset Code...", role: .destructive) { model.regeneratePairingCode() }
                }
                .controlSize(.small)
                }
            }

            Section("Connected Devices") {
                if model.peers.isEmpty {
                    ContentUnavailableView(
                        "No Devices Found",
                        systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                        description: Text("Use the same sharing mode on your other devices.")
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
                Text(model.trustedLAN ? "Trusted LAN sharing is unencrypted." : "Clipboard and files are encrypted with your pairing code.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

