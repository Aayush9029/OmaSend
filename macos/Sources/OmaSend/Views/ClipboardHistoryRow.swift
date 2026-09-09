import SwiftUI

struct ClipboardHistoryRow: View {
    let item: ClipboardItem
    let onCopy: () -> Void
    let onPreview: () -> Void
    @State private var isHovering = false
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: item.isImage ? onPreview : copy) {
                HStack(spacing: 8) {
                    leadingImage
                        .frame(width: 38, height: 38)

                    Text(item.preview)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect(cornerRadius: 6))
            }
            .help(item.isImage ? "Quick Look · Space" : "Copy")
            .accessibilityLabel("\(item.isImage ? "Preview" : "Copy") \(item.preview)")

            Button(action: copy) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(didCopy ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 26, height: 38)
                    .contentShape(.rect)
            }
            .help("Copy")
            .accessibilityLabel("Copy \(item.preview)")
        }
        .buttonStyle(.plain)
        .padding(.vertical, 5)
        .background(isHovering ? Color.accentColor.opacity(0.12) : Color.clear, in: .rect(cornerRadius: 8))
        .contentShape(.rect(cornerRadius: 8))
        .onHover { isHovering = $0 }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            if item.isImage { onPreview() } else { copy() }
            return .handled
        }
        .onKeyPress(.return) { copy(); return .handled }
        .task(id: didCopy) {
            guard didCopy else { return }
            do { try await Task.sleep(for: .seconds(1.5)) }
            catch { return }
            didCopy = false
        }
        .animation(.easeInOut(duration: 0.15), value: didCopy)
    }

    @ViewBuilder private var leadingImage: some View {
        if item.isImage {
            ClipboardThumbnail(encodedImage: item.thumbnail)
        } else if item.isFile {
            Image(systemName: "doc.fill")
                .foregroundStyle(.secondary)
        } else if item.isLocal {
            Image(systemName: "laptopcomputer")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        } else {
            ArchLinuxMark()
                .frame(width: 16, height: 16)
        }
    }

    private func copy() {
        onCopy()
        didCopy = true
    }
}
