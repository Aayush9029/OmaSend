import SwiftUI

struct StatusItemView: View {
    let model: AppModel

    var body: some View {
        Group {
            switch model.menuBarStyle {
            case .icon:
                icon
            case .iconAndCount:
                HStack(spacing: 4) {
                    icon
                    Text("\(model.peers.count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
            case .hidden:
                EmptyView()
            }
        }
        .frame(width: model.menuBarStyle.itemWidth, alignment: .center)
    }

    private var icon: some View {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 12, weight: .semibold))
    }
}
