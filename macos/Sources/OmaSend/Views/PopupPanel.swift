import AppKit

final class PopupPanel: NSPanel {
    var onCancel: (() -> Void)?
    var previewController: ClipboardPreviewController?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
