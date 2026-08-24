import AppKit
import SwiftUI

struct AnimatedImage: NSViewRepresentable {
    let resource: String

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleAxesIndependently
        view.animates = true
        view.canDrawSubviewsIntoLayer = true
        view.image = image
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.image == nil { view.image = image }
    }

    private var image: NSImage? {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "gif", subdirectory: "Resources") else { return nil }
        return NSImage(contentsOf: url)
    }
}

