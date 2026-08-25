import AppKit
import Observation
import SwiftUI

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let model: AppModel
    private let hostingView: PassthroughHostingView<StatusItemView>
    private var popup: PopupPanelController!

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: model.menuBarStyle.itemWidth)
        self.hostingView = PassthroughHostingView(rootView: StatusItemView(model: model))

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.toolTip = "OmaSend"
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: button.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
        }

        popup = PopupPanelController(content: PopupView(model: model)) { [weak self] in
            self?.statusItem.button?.highlight(false)
            self?.model.setPopupVisible(false)
        }
        observeWidth()
    }

    private func observeWidth() {
        withObservationTracking {
            let style = model.menuBarStyle
            statusItem.isVisible = style != .hidden
            statusItem.length = style.itemWidth
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeWidth() }
        }
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem.button, let window = button.window else { return }
        if NSApp.currentEvent?.type == .rightMouseDown {
            model.clearHistoryEverywhere()
            return
        }
        if popup.isVisible || popup.wasJustDismissed { popup.dismiss(); return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        button.highlight(true)
        popup.show(below: anchor)
        model.setPopupVisible(true)
    }
}

private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    @MainActor required init(rootView: Content) { super.init(rootView: rootView) }
    @MainActor required dynamic init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
