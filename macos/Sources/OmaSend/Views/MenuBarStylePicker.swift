import SwiftUI

struct MenuBarStylePicker: View {
    let selection: MenuBarStyle
    let peerCount: Int
    let action: (MenuBarStyle) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(MenuBarStyle.allCases) { style in
                VStack(spacing: 6) {
                    SelectableCard(isSelected: selection == style, isBlack: true) {
                        action(style)
                    } content: {
                        preview(style)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                    }
                    Text(style.displayName)
                        .font(.caption)
                        .foregroundStyle(selection == style ? .primary : .secondary)
                }
            }
        }
    }

    @ViewBuilder private func preview(_ style: MenuBarStyle) -> some View {
        switch style {
        case .icon:
            Image(systemName: "paperplane.fill").font(.system(size: 13, weight: .semibold))
        case .iconAndCount:
            HStack(spacing: 4) {
                Image(systemName: "paperplane.fill")
                Text("\(max(1, peerCount))").monospacedDigit()
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
        case .hidden:
            Image(systemName: "eye.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

