import SwiftUI

struct PopupView: View {
    let model: AppModel
    let onPreview: (ClipboardItem) -> Void
    @FocusState private var focusedItemID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.history.isEmpty {
                Text("Copy something on either computer to begin.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(model.history) { item in
                                ClipboardHistoryRow(
                                    item: item,
                                    onCopy: { model.copy(item) },
                                    onPreview: { onPreview(item) }
                                )
                                .focused($focusedItemID, equals: item.id)
                                .id(item.id)
                            }
                        }
                    }
                    .contentMargins(.horizontal, 8, for: .scrollContent)
                    .contentMargins(.horizontal, 0, for: .scrollIndicators)
                    .scrollIndicators(.visible)
                    .frame(height: min(CGFloat(model.history.count) * 50 - 2, 326))
                    .onKeyPress(.downArrow) { moveFocus(by: 1); return .handled }
                    .onKeyPress(.upArrow) { moveFocus(by: -1); return .handled }
                    .onChange(of: focusedItemID) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            }

            if let message = model.lastError {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
            }

            Divider().padding(.horizontal, 12)

            PopupMenuRow(title: "Settings…") {
                model.openSettings()
            }
            .padding(.horizontal, 8)
            PopupMenuRow(title: "Quit…", shortcut: "⌘Q") {
                model.quit()
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
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

    private func moveFocus(by offset: Int) {
        guard !model.history.isEmpty else { return }
        let current = model.history.firstIndex { $0.id == focusedItemID }
        let next = current.map { min(max($0 + offset, 0), model.history.count - 1) } ?? 0
        focusedItemID = model.history[next].id
    }
}
