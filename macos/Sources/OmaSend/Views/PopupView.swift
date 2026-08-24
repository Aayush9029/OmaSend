import AppKit
import SwiftUI

struct PopupView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ClipboardSummaryCard(model: model)

            if model.history.isEmpty {
                Text("Copy something on either computer to begin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(model.history) { item in
                            ClipboardHistoryRow(item: item) { model.copy(item) }
                        }
                    }
                }
                .scrollIndicators(.visible)
                .frame(height: historyHeight)
            }

            if let message = model.lastError {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
            }

            Divider().padding(.horizontal, 4)

            PopupMenuRow(
                title: model.autoCopy ? "Turn Off Auto Copy" : "Turn On Auto Copy",
                systemImage: model.autoCopy ? "pause.circle" : "arrow.triangle.2.circlepath.circle"
            ) {
                model.setAutoCopy(!model.autoCopy)
            }
            PopupMenuRow(title: "OmaSend Settings...", systemImage: "gearshape") {
                model.openSettings()
            }
            PopupMenuRow(title: "Quit OmaSend", systemImage: "power", shortcut: "Cmd Q") {
                model.quit()
            }
        }
        .padding(8)
        .frame(width: PopupPanelController.contentWidth)
        .background {
            VisualEffectBackground()
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
        }
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
    }

    private var historyHeight: CGFloat {
        min(model.history.prefix(6).reduce(0) { height, item in
            height + (item.isImage ? 80 : 48)
        }, 300)
    }
}

private struct ClipboardSummaryCard: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)
                transferTrack
                ArchLinuxMark()
                    .frame(width: 20, height: 20)
                    .opacity(model.peers.isEmpty ? 0.45 : 1)
            }
            .frame(height: 54)
            .padding(.horizontal, 8)
            .background(.primary.opacity(0.045), in: .rect(cornerRadius: 10, style: .continuous))

            HStack {
                Text(model.peers.isEmpty ? "Looking for paired devices" : connectedNames)
                Spacer()
                Text(model.peers.first?.via ?? "Local network")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(12)
        .omaGlass(cornerRadius: 14)
    }

    private var transferTrack: some View {
        HStack(spacing: 3) {
            ForEach(0..<9, id: \.self) { index in
                Capsule()
                    .fill(index == 4 && !model.peers.isEmpty ? Color.blue : Color.primary.opacity(0.13))
                    .frame(width: index == 4 ? 14 : 7, height: 4)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var connectedNames: String {
        model.peers.map(\.name).joined(separator: ", ")
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardItem
    let action: () -> Void
    @State private var isHovering = false
    @State private var didCopy = false

    var body: some View {
        Button(action: copy) {
            if item.isImage {
                imageRow
            } else {
                textRow
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var textRow: some View {
            HStack(alignment: .center, spacing: 6) {
                platformIcon
                    .frame(width: 22, height: 34, alignment: .center)

                if item.isFile {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Text(item.preview)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                copyIcon
                    .frame(width: 20, height: 38, alignment: .center)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(isHovering ? Color.accentColor.opacity(0.15) : Color.clear, in: .rect(cornerRadius: 8))
            .contentShape(.rect)
    }

    private var imageRow: some View {
        ZStack {
            if let encoded = item.thumbnail,
           let data = Data(base64Encoded: encoded), let image = NSImage(data: data) {
                GeometryReader { proxy in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: 72)
                        .clipped()
                }
                .frame(height: 72)
            } else {
                Rectangle()
                    .fill(.primary.opacity(0.06))
                    .frame(height: 72)
                    .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 72)
        .overlay {
            if isHovering {
                Color.accentColor.opacity(0.08)
            }
        }
        .overlay(alignment: .bottomLeading) {
            platformIcon
                .frame(width: 15, height: 15)
                .padding(5)
                .background(.regularMaterial, in: .circle)
                .padding(5)
        }
        .overlay(alignment: .topTrailing) {
            copyIcon
                .frame(width: 26, height: 26)
                .background(.regularMaterial, in: .circle)
                .padding(5)
        }
        .clipShape(.rect(cornerRadius: 9, style: .continuous))
        .contentShape(.rect(cornerRadius: 9, style: .continuous))
        .padding(.horizontal, 4)
    }

    @ViewBuilder private var platformIcon: some View {
        if item.isLocal {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        } else {
            ArchLinuxMark()
                .frame(width: 14, height: 14)
        }
    }

    private var copyIcon: some View {
        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(didCopy ? Color.green : Color.secondary)
            .contentTransition(.symbolEffect(.replace))
    }

    private func copy() {
        action()
        withAnimation(.easeInOut(duration: 0.15)) { didCopy = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeInOut(duration: 0.15)) { didCopy = false }
        }
    }
}

struct ArchLinuxMark: View {
    private static let image: NSImage? = {
        guard let url = Bundle.module.url(
            forResource: "ArchLinux", withExtension: "pdf", subdirectory: "Resources"
        ) else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .grayscale(1)
                    .opacity(0.72)
            } else {
                Image(systemName: "network")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
