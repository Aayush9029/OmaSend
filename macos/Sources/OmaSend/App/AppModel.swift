import AppKit
import CryptoKit
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppModel {
    private(set) var deviceName: String
    private(set) var autoCopy: Bool
    private(set) var history: [ClipboardItem]
    private(set) var peers: [PeerDevice] = []
    private(set) var lastError: String?
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var showsDockIcon: Bool
    private(set) var menuBarStyle: MenuBarStyle
    var settingsTab: SettingsTab? = .general

    private var configuration: AppConfiguration
    private let store: ConfigurationStore
    private let network: NetworkService
    private var pasteboardTimer: Timer?
    private var pasteboardChangeCount = NSPasteboard.general.changeCount
    private var lastClipboardFingerprint: Data?
    @ObservationIgnored private var settingsWindow: SettingsWindowController?

    init(store: ConfigurationStore = ConfigurationStore(), network: NetworkService = NetworkService()) {
        self.store = store
        self.network = network
        let configuration = store.load()
        self.configuration = configuration
        self.deviceName = configuration.deviceName
        self.autoCopy = configuration.autoCopy
        self.history = configuration.history
        self.showsDockIcon = UserDefaults.standard.bool(forKey: "showsDockIcon")
        self.menuBarStyle = MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: "menuBarStyle") ?? "") ?? .icon
    }

    func start() {
        applyActivationPolicy()
        lastClipboardFingerprint = readPasteboard()?.fingerprint
        network.onMessage = { [weak self] message in self?.receive(message) }
        network.onPeersChanged = { [weak self] peers in self?.peers = peers }
        network.onError = { [weak self] message in self?.lastError = message }
        network.start(
            deviceId: configuration.deviceId,
            deviceName: configuration.deviceName,
            pairingCode: configuration.pairingCode
        )
        pasteboardTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollPasteboard() }
        }
    }

    func stop() {
        pasteboardTimer?.invalidate()
        network.stop()
    }

    func setAutoCopy(_ value: Bool) {
        autoCopy = value
        configuration.autoCopy = value
        persist()
    }

    func setShowsDockIcon(_ value: Bool) {
        showsDockIcon = value
        UserDefaults.standard.set(value, forKey: "showsDockIcon")
        applyActivationPolicy()
    }

    func setMenuBarStyle(_ value: MenuBarStyle) {
        menuBarStyle = value
        UserDefaults.standard.set(value.rawValue, forKey: "menuBarStyle")
        applyActivationPolicy()
    }

    func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController(model: self) }
        settingsWindow?.show()
    }

    func copy(_ item: ClipboardItem) {
        writePasteboard(item)
    }

    func copyPairingCode() {
        writePasteboard(configuration.pairingCode)
    }

    func promptForPairingCode() {
        let alert = NSAlert()
        alert.messageText = "Pair Another Device"
        alert.informativeText = "Paste the pairing code from OmaSend on your Linux computer. Existing peers will reconnect automatically."
        alert.addButton(withTitle: "Pair")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "Pairing code"
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 20 else {
            lastError = "That pairing code is too short."
            return
        }
        configuration.pairingCode = value
        peers = []
        persist()
        network.updatePairingCode(value)
    }

    func regeneratePairingCode() {
        let alert = NSAlert()
        alert.messageText = "Reset Pairing Code?"
        alert.informativeText = "All devices will disconnect until you enter the new code on them."
        alert.addButton(withTitle: "Reset Code")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        configuration.pairingCode = ProtocolCrypto.generateSecret()
        peers = []
        persist()
        network.updatePairingCode(configuration.pairingCode)
        copyPairingCode()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = enabled ? "Could not add OmaSend to Login Items." : "Could not remove OmaSend from Login Items."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func quit() { NSApplication.shared.terminate(nil) }

    private func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != pasteboardChangeCount else { return }
        pasteboardChangeCount = pasteboard.changeCount
        guard let payload = readPasteboard(), payload.fingerprint != lastClipboardFingerprint else { return }
        lastClipboardFingerprint = payload.fingerprint
        let message = makeMessage(payload: payload)
        add(message)
        network.broadcast(message)
    }

    private func receive(_ message: WireMessage) {
        guard message.type == "clipboard", message.originId != configuration.deviceId else { return }
        guard add(message), autoCopy else { return }
        writePasteboard(message)
    }

    @discardableResult
    private func add(_ message: WireMessage) -> Bool {
        let isImage = message.contentType?.hasPrefix("image/") == true && message.data != nil
        guard (message.text != nil || isImage), !history.contains(where: { $0.id == message.id }) else { return false }
        let item = ClipboardItem(
            id: message.id, text: message.text ?? "", originId: message.originId,
            originName: message.originName, createdAt: message.createdAt,
            isLocal: message.originId == configuration.deviceId,
            contentType: message.contentType, data: message.data,
            thumbnail: thumbnailBase64(from: message.data)
        )
        history.insert(item, at: 0)
        if history.count > OmaSendConstants.maxHistory { history.removeLast(history.count - OmaSendConstants.maxHistory) }
        while history.reduce(0, { $0 + ($1.data?.utf8.count ?? $1.text.utf8.count) }) > 52_428_800,
              history.count > 1 {
            history.removeLast()
        }
        configuration.history = history
        persist()
        return true
    }

    private func writePasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboardChangeCount = pasteboard.changeCount
        lastClipboardFingerprint = ClipboardPayload(contentType: "text/plain", text: text, data: nil).fingerprint
    }

    private func writePasteboard(_ item: ClipboardItem) {
        writePasteboard(WireMessage(
            version: OmaSendConstants.protocolVersion, type: "clipboard",
            id: item.id, originId: item.originId, originName: item.originName,
            createdAt: item.createdAt, text: item.text.isEmpty ? nil : item.text,
            contentType: item.contentType, data: item.data
        ))
    }

    private func writePasteboard(_ message: WireMessage) {
        if message.contentType?.hasPrefix("image/") == true,
           let encoded = message.data, let data = Data(base64Encoded: encoded) {
            let clipboardData = pngData(from: data) ?? data
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(clipboardData, forType: .png)
            pasteboardChangeCount = pasteboard.changeCount
            lastClipboardFingerprint = ClipboardPayload(
                contentType: "image/png", text: nil, data: clipboardData
            ).fingerprint
        } else if let text = message.text {
            writePasteboard(text)
        }
    }

    private func makeMessage(payload: ClipboardPayload) -> WireMessage {
        WireMessage(
            version: OmaSendConstants.protocolVersion, type: "clipboard",
            id: UUID().uuidString.lowercased(), originId: configuration.deviceId,
            originName: configuration.deviceName,
            createdAt: Int64(Date().timeIntervalSince1970 * 1_000), text: payload.text,
            contentType: payload.contentType, data: payload.data?.base64EncodedString()
        )
    }

    private func readPasteboard() -> ClipboardPayload? {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png), data.count <= OmaSendConstants.maxClipboardBytes {
            return ClipboardPayload(contentType: "image/png", text: nil, data: data)
        }
        if let data = pasteboard.data(forType: .tiff),
           let png = pngData(from: data), png.count <= OmaSendConstants.maxClipboardBytes {
            return ClipboardPayload(contentType: "image/png", text: nil, data: png)
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty,
           text.utf8.count <= OmaSendConstants.maxClipboardBytes {
            return ClipboardPayload(contentType: "text/plain", text: text, data: nil)
        }
        return nil
    }

    private func pngData(from data: Data) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    private func thumbnailBase64(from encoded: String?) -> String? {
        guard let encoded, let data = Data(base64Encoded: encoded), let image = NSImage(data: data) else { return nil }
        let maxSide: CGFloat = 160
        let ratio = min(maxSide / max(image.size.width, 1), maxSide / max(image.size.height, 1), 1)
        let size = NSSize(width: max(1, image.size.width * ratio), height: max(1, image.size.height * ratio))
        let thumbnail = NSImage(size: size)
        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        thumbnail.unlockFocus()
        var rect = NSRect(origin: .zero, size: size)
        guard let cgImage = thumbnail.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
        else { return nil }
        return png.base64EncodedString()
    }

    private func persist() {
        do { try store.save(configuration); lastError = nil }
        catch { lastError = "Could not save OmaSend settings." }
    }

    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(showsDockIcon || menuBarStyle == .hidden ? .regular : .accessory)
    }
}

private struct ClipboardPayload {
    let contentType: String
    let text: String?
    let data: Data?

    var fingerprint: Data {
        var material = Data(contentType.utf8)
        if let data { material.append(data) }
        if let text { material.append(Data(text.utf8)) }
        return Data(SHA256.hash(data: material))
    }
}
