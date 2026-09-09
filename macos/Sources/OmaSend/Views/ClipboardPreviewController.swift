import AppKit
import QuickLookUI

@MainActor
final class ClipboardPreviewController: NSResponder, @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    private let store = ClipboardPreviewStore()
    private var previewURL: URL?
    private var previewedItemID: String?
    private var isOpening = false
    weak var sourceWindow: NSWindow?

    var isPresenting: Bool {
        isOpening || (QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible)
    }

    func installInResponderChain() {
        guard NSApp.nextResponder !== self else { return }
        // Quick Look must keep the same controller when focus moves between app windows.
        nextResponder = NSApp.nextResponder
        NSApp.nextResponder = self
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        previewURL != nil
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    func preview(_ item: ClipboardItem) {
        if previewedItemID == item.id, isPresenting {
            dismiss()
            sourceWindow?.makeKey()
            return
        }
        do {
            let url = try store.previewURL(for: item)
            previewURL = url
            previewedItemID = item.id
            isOpening = true
            defer { isOpening = false }
            guard let panel = QLPreviewPanel.shared() else { return }
            panel.updateController()
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Preview Unavailable"
            alert.informativeText = item.isFile
                ? "The original file could not be opened. It may have been moved or deleted."
                : "The original image could not be opened."
            if let sourceWindow { alert.beginSheetModal(for: sourceWindow) }
        }
    }

    func dismiss() {
        if QLPreviewPanel.sharedPreviewPanelExists() {
            QLPreviewPanel.shared().orderOut(nil)
        }
        previewURL = nil
        previewedItemID = nil
        store.removeTemporaryFiles()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURL == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURL as NSURL?
    }

    func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, event.keyCode == 49 || event.keyCode == 53 else { return false }
        dismiss()
        sourceWindow?.makeKey()
        return true
    }
}
