import SwiftUI

struct DeviceCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let name: String
    var isCurrentDevice = false
    let connection: String
    let isEncrypted: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: isCurrentDevice ? "laptopcomputer" : "desktopcomputer")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 32)

                Text(name)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(isCurrentDevice ? "This Mac" : "Connected")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(isCurrentDevice ? Color.blue : Color.green)
                    .background(isCurrentDevice ? Color.blue.opacity(0.15) : Color.green.opacity(0.15), in: .capsule)
            }
            .padding(16)
            .background(colorScheme == .dark ? Color.black.opacity(0.6) : Color.primary.opacity(0.06))

            HStack(spacing: 16) {
                Label(connection, systemImage: connection == "Tailscale" ? "network" : "wifi")
                Spacer(minLength: 0)
                Label(isEncrypted ? "Encrypted" : "Unencrypted", systemImage: isEncrypted ? "lock.shield" : "lock.open")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(colorScheme == .dark ? Color.black.opacity(0.9) : Color.primary.opacity(0.03))
        }
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.primary.opacity(0.1), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}
