import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case menuBar
    case clipboard
    case devices
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .menuBar: "Menu Bar"
        case .clipboard: "Clipboard"
        case .devices: "Devices"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .clipboard: "doc.on.clipboard"
        case .devices: "desktopcomputer.and.macbook"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .menuBar: .indigo
        case .clipboard: .green
        case .devices: .blue
        case .about: .orange
        }
    }
}
