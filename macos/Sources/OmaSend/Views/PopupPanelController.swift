import AppKit
import SwiftUI

@MainActor
final class PopupPanelController {
    static let contentWidth: CGFloat = 320
    private let panel: PopupPanel
    private let hostingController: NSHostingController<AnyView>
    private var globalMonitor: Any?
    private var anchorFrame: NSRect = .zero
    private var dismissedAt = Date.distantPast
    private let onDismiss: () -> Void

    var isVisible: Bool { panel.isVisible }
    var wasJustDismissed: Bool { Date().timeIntervalSince(dismissedAt) < 0.25 }

    init<Content: View>(content: Content, onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
        hostingController = NSHostingController(rootView: AnyView(content))
        hostingController.sizingOptions = [.preferredContentSize]
        panel = PopupPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 400),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .utilityWindow
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.position() }
        }
    }

    func show(below anchor: NSRect) {
        anchorFrame = anchor
        panel.setContentSize(hostingController.view.fittingSize)
        position()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    func dismiss() {
        guard panel.isVisible else { return }
        dismissedAt = Date()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        panel.orderOut(nil)
        onDismiss()
    }

    private func position() {
        guard anchorFrame != .zero else { return }
        let size = panel.frame.size
        var origin = NSPoint(x: anchorFrame.midX - size.width / 2, y: anchorFrame.minY - size.height - 6)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchorFrame) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }
        panel.setFrameOrigin(origin)
    }
}
