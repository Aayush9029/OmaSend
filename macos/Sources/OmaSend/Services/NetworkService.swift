import Foundation
import Network

final class NetworkService: NSObject, @unchecked Sendable {
    var onMessage: ((WireMessage) -> Void)?
    var onPeersChanged: (([PeerDevice]) -> Void)?
    var onError: ((String) -> Void)?

    private let queue = DispatchQueue(label: "art.aayush.OmaSend.network", qos: .userInitiated)
    private var listener: NWListener?
    private var browser: NetServiceBrowser?
    private var publishedService: NetService?
    private var resolving: [NetService] = []
    private var timer: DispatchSourceTimer?
    private var peers: [String: PeerDevice] = [:]
    private var deviceId = ""
    private var deviceName = "Mac"
    private var pairingCode = ""
    private var port = OmaSendConstants.defaultPort

    func start(deviceId: String, deviceName: String, pairingCode: String) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.pairingCode = pairingCode
        startListener()
        startBonjour()
        startMaintenanceTimer()
    }

    func stop() {
        browser?.stop()
        publishedService?.stop()
        timer?.cancel()
        queue.async { [weak self] in self?.listener?.cancel(); self?.listener = nil }
    }

    func updatePairingCode(_ value: String) {
        queue.async { [weak self] in
            self?.pairingCode = value
            self?.peers.removeAll()
            self?.publishPeers()
        }
    }

    func broadcast(_ message: WireMessage) {
        queue.async { [weak self] in
            guard let self else { return }
            let current = self.peers.values.filter { Date().timeIntervalSince($0.lastSeen) < 90 }
            for peer in current { self.send(message, host: peer.host, port: peer.port, expectsReply: false, via: peer.via) }
        }
    }

    private func startListener() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: self.port)!)
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.stateUpdateHandler = { [weak self] state in
                    if case .failed(let error) = state { self?.report("Network listener failed: \(error.localizedDescription)") }
                }
                self.listener = listener
                listener.start(queue: self.queue)
            } catch {
                self.report("Could not listen on port \(self.port): \(error.localizedDescription)")
            }
        }
    }

    private func startBonjour() {
        let suffix = String(deviceId.prefix(6))
        let service = NetService(domain: "local.", type: OmaSendConstants.serviceType, name: "\(deviceName)-\(suffix)", port: Int32(port))
        service.setTXTRecord(NetService.data(fromTXTRecord: [
            "v": Data("1".utf8), "id": Data(deviceId.utf8), "name": Data(deviceName.utf8),
        ]))
        service.delegate = self
        service.publish()
        publishedService = service

        let browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: OmaSendConstants.serviceType, inDomain: "local.")
        self.browser = browser
    }

    private func startMaintenanceTimer() {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 1, repeating: 8)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.probeTailscale()
            for peer in self.peers.values where Date().timeIntervalSince(peer.lastSeen) < 120 {
                self.sendHello(host: peer.host, port: peer.port, via: peer.via)
            }
            self.peers = self.peers.filter { Date().timeIntervalSince($0.value.lastSeen) < 180 }
            self.publishPeers()
        }
        timer = source
        source.resume()
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            if case .ready = state {
                self.receiveFrame(connection) { result in
                    switch result {
                    case .failure: connection.cancel()
                    case .success(let frame): self.handle(frame, from: connection)
                    }
                }
            }
        }
        connection.start(queue: queue)
    }

    private func handle(_ frame: Data, from connection: NWConnection) {
        let secret = pairingCode
        guard let message = try? ProtocolCrypto.open(frame, secret: secret), message.originId != deviceId else {
            connection.cancel(); return
        }
        let host = remoteHost(connection.endpoint)
        let via = host.hasPrefix("100.") ? "Tailscale" : "Local network"
        upsert(PeerDevice(id: message.originId, name: message.originName, host: host, port: port, via: via, lastSeen: Date()))
        switch message.type {
        case "hello":
            let reply = makeMessage(type: "hello_ack", text: nil)
            if let sealed = try? ProtocolCrypto.seal(reply, secret: secret), let framed = try? ProtocolCrypto.frame(sealed) {
                connection.send(content: framed, completion: .contentProcessed { _ in connection.cancel() })
            } else { connection.cancel() }
        case "clipboard":
            DispatchQueue.main.async { [weak self] in self?.onMessage?(message) }
            connection.cancel()
        default:
            connection.cancel()
        }
    }

    private func sendHello(host: String, port: UInt16, via: String) {
        send(makeMessage(type: "hello", text: nil), host: host, port: port, expectsReply: true, via: via)
    }

    private func send(_ message: WireMessage, host: String, port: UInt16, expectsReply: Bool, via: String) {
        guard !host.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port),
              let sealed = try? ProtocolCrypto.seal(message, secret: pairingCode),
              let framed = try? ProtocolCrypto.frame(sealed)
        else { return }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                connection.send(content: framed, completion: .contentProcessed { error in
                    if error != nil || !expectsReply { connection.cancel(); return }
                    self.receiveFrame(connection) { result in
                        defer { connection.cancel() }
                        guard case .success(let data) = result,
                              let reply = try? ProtocolCrypto.open(data, secret: self.pairingCode),
                              reply.type == "hello_ack"
                        else { return }
                        self.upsert(PeerDevice(id: reply.originId, name: reply.originName, host: host, port: port, via: via, lastSeen: Date()))
                    }
                })
            case .failed, .cancelled: connection.cancel()
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveFrame(_ connection: NWConnection, completion: @escaping (Result<Data, Error>) -> Void) {
        receiveExactly(connection, count: 4) { [weak self] headerResult in
            guard let self else { return }
            switch headerResult {
            case .failure(let error): completion(.failure(error))
            case .success(let header):
                let length = header.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
                guard length > 0, length <= UInt32(OmaSendConstants.maxFrameBytes) else {
                    completion(.failure(ProtocolCryptoError.invalidMessage)); return
                }
                self.receiveExactly(connection, count: Int(length), completion: completion)
            }
        }
    }

    private func receiveExactly(_ connection: NWConnection, count: Int, accumulated: Data = Data(), completion: @escaping (Result<Data, Error>) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: count - accumulated.count) { [weak self] data, _, complete, error in
            if let error { completion(.failure(error)); return }
            var result = accumulated
            if let data { result.append(data) }
            if result.count == count { completion(.success(result)); return }
            if complete { completion(.failure(ProtocolCryptoError.malformedEnvelope)); return }
            self?.receiveExactly(connection, count: count, accumulated: result, completion: completion)
        }
    }

    private func makeMessage(type: String, text: String?) -> WireMessage {
        WireMessage(
            version: OmaSendConstants.protocolVersion, type: type,
            id: UUID().uuidString.lowercased(), originId: deviceId,
            originName: deviceName, createdAt: Int64(Date().timeIntervalSince1970 * 1_000), text: text
        )
    }

    private func upsert(_ peer: PeerDevice) {
        guard !peer.id.isEmpty, peer.id != deviceId else { return }
        peers[peer.id] = peer
        publishPeers()
    }

    private func publishPeers() {
        let visible = peers.values.filter { Date().timeIntervalSince($0.lastSeen) < 20 }.sorted { $0.name < $1.name }
        DispatchQueue.main.async { [weak self] in self?.onPeersChanged?(visible) }
    }

    private func probeTailscale() {
        guard let executable = tailscaleExecutable() else { return }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = ["status", "--json"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() } catch { return }
        guard process.terminationStatus == 0,
              let object = try? JSONSerialization.jsonObject(with: pipe.fileHandleForReading.readDataToEndOfFile()) as? [String: Any],
              let peers = object["Peer"] as? [String: Any]
        else { return }
        for value in peers.values {
            guard let peer = value as? [String: Any], peer["Online"] as? Bool == true,
                  let addresses = peer["TailscaleIPs"] as? [String],
                  let host = addresses.first(where: { $0.hasPrefix("100.") })
            else { continue }
            sendHello(host: host, port: port, via: "Tailscale")
        }
    }

    private func tailscaleExecutable() -> URL? {
        let candidates = [
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
            "/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale", "/usr/bin/tailscale",
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }

    private func remoteHost(_ endpoint: NWEndpoint) -> String {
        guard case .hostPort(let host, _) = endpoint else { return "" }
        return String(describing: host).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    private func report(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.onError?(message) }
    }
}

extension NetworkService: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard service.name != publishedService?.name else { return }
        resolving.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        defer { resolving.removeAll { $0 === sender } }
        guard let host = sender.hostName else { return }
        let record = sender.txtRecordData().map(NetService.dictionary(fromTXTRecord:)) ?? [:]
        guard let idData = record["id"], let id = String(data: idData, encoding: .utf8), id != deviceId else { return }
        let resolvedPort = sender.port > 0 ? UInt16(sender.port) : port
        queue.async { [weak self] in self?.sendHello(host: host, port: resolvedPort, via: "Local network") }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolving.removeAll { $0 === sender }
    }
}
