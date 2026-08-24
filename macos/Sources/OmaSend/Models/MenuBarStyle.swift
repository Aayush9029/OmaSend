import CoreGraphics

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case icon
    case iconAndCount
    case hidden

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .icon: "Icon"
        case .iconAndCount: "Icon and Devices"
        case .hidden: "Hidden"
        }
    }

    var itemWidth: CGFloat {
        switch self {
        case .icon: 28
        case .iconAndCount: 44
        case .hidden: 0
        }
    }
}

