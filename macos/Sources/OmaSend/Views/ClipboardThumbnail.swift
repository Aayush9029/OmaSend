import AppKit
import SwiftUI

struct ClipboardThumbnail: View {
    let encodedImage: String?

    var body: some View {
        Group {
            if let encodedImage, let data = Data(base64Encoded: encodedImage),
               let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 38, height: 38)
        .background(.primary.opacity(0.06))
        .clipShape(.rect(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}
