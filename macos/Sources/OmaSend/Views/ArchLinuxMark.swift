import AppKit
import SwiftUI

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
