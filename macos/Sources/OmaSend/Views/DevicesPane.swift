import SwiftUI

struct DevicesPane: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                devicesSection
                pairingSection
            }
            .padding(20)
        }
    }

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeviceCard(
                name: model.deviceName,
                isCurrentDevice: true,
                connection: "Local network",
                isEncrypted: !model.trustedLAN
            )

            HStack {
                Text("Connected Devices")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(model.peers.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            if model.peers.isEmpty {
                ContentUnavailableView(
                    "No Devices Connected",
                    systemImage: "laptopcomputer.and.iphone",
                    description: Text(model.trustedLAN
                        ? "Turn on Trusted LAN on your other devices to connect."
                        : "Use the same pairing code on your other devices to connect.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ForEach(model.peers) { peer in
                    DeviceCard(name: peer.name, connection: peer.via, isEncrypted: !model.trustedLAN)
                }
            }
        }
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sharing")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 14) {
                Toggle("Trusted LAN", isOn: Binding(get: { model.trustedLAN }, set: model.setTrustedLAN))
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Text(model.trustedLAN
                    ? "No pairing code required. Sharing is unencrypted, and anyone on this local network can read or send items."
                    : "Clipboard and files are encrypted. Use the same pairing code on each Mac, Windows, or Linux device.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !model.trustedLAN {
                    Divider()
                    HStack(spacing: 8) {
                        Button("Copy Pairing Code", action: model.copyPairingCode)
                        Button("Pair Device…", action: model.promptForPairingCode)
                        Spacer(minLength: 0)
                        Menu {
                            Button("Reset Pairing Code…", role: .destructive, action: model.regeneratePairingCode)
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .accessibilityLabel("Pairing options")
                    }
                    .controlSize(.small)
                }
            }
            .padding(16)
            .background(.primary.opacity(0.04), in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
            }
        }
    }
}
