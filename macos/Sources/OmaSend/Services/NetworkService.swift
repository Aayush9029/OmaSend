import CryptoKit
import Foundation
import Network

final class NetworkService: NSObject, @unchecked Sendable {
    var onMessage: ((WireMessage) -> Void)?
    var onPeersChanged: (([PeerDevice]) -> Void)?
    var onError: ((String) -> Void)?

    private let queue = DispatchQueue(label: "art.aayush.OmaSend.network", qos: .userInitiated)
    private let fileQueue = DispatchQueue(label: "art.aayush.OmaSend.files", qos: .utility)
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

    func broadcastFile(_ url: URL, message: WireMessage) {
        fileQueue.async { [weak self] in
            guard let self, let fileHash = self.sha256File(url) else { return }
            self.queue.async {
                let transfer = self.fileMessage(
                    type: "file", source: message, fileSHA256: fileHash, filePath: url.path
                )
                let current = self.peers.values.filter { Date().timeIntervalSince($0.lastSeen) < 90 }
                for peer in current {
                    self.sendFileWithRetry(url, message: transfer, peer: peer, attempt: 0)
                }
            }
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
        case "file_offer":
            receiveFile(message, from: connection)
        default:
            connection.cancel()
        }
    }

    private func sendFileWithRetry(_ url: URL, message: WireMessage, peer: PeerDevice, attempt: Int) {
        sendFile(url, message: message, peer: peer) { [weak self] success in
            guard let self, !success, attempt < 5 else { return }
            self.queue.asyncAfter(deadline: .now() + .seconds(attempt + 1)) {
                self.sendFileWithRetry(url, message: message, peer: peer, attempt: attempt + 1)
            }
        }
    }

    private func sendFile(
        _ url: URL, message: WireMessage, peer: PeerDevice,
        completion: @escaping (Bool) -> Void
    ) {
        guard let nwPort = NWEndpoint.Port(rawValue: peer.port) else { completion(false); return }
        let offer = fileMessage(type: "file_offer", source: message, filePath: nil)
        guard let sealed = try? ProtocolCrypto.seal(offer, secret: pairingCode),
              let framed = try? ProtocolCrypto.frame(sealed)
        else { completion(false); return }
        let connection = NWConnection(host: NWEndpoint.Host(peer.host), port: nwPort, using: .tcp)
        var started = false
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready where !started:
                started = true
                connection.send(content: framed, completion: .contentProcessed { error in
                    guard error == nil else { connection.cancel(); completion(false); return }
                    self.receiveFrame(connection) { result in
                        guard case .success(let data) = result,
                              let reply = try? ProtocolCrypto.open(data, secret: self.pairingCode),
                              reply.type == "file_resume", reply.id == message.id,
                              (reply.resumeOffset ?? 0) >= 0,
                              let fileSize = message.fileSize,
                              (reply.resumeOffset ?? 0) <= fileSize,
                              let handle = try? FileHandle(forReadingFrom: url)
                        else { connection.cancel(); completion(false); return }
                        let offset = reply.resumeOffset ?? 0
                        do { try handle.seek(toOffset: UInt64(offset)) }
                        catch { try? handle.close(); connection.cancel(); completion(false); return }
                        self.sendFileChunks(
                            connection, handle: handle, message: message,
                            offset: offset, completion: completion
                        )
                    }
                })
            case .failed:
                connection.cancel()
                completion(false)
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func sendFileChunks(
        _ connection: NWConnection, handle: FileHandle, message: WireMessage,
        offset: Int64, completion: @escaping (Bool) -> Void
    ) {
        let total = message.fileSize ?? 0
        if offset < total {
            let count = min(OmaSendConstants.fileChunkBytes, Int(total - offset))
            guard let chunk = try? handle.read(upToCount: count), !chunk.isEmpty,
                  let payload = try? ProtocolCrypto.sealFileChunk(
                    chunk, transferId: message.id, offset: offset, secret: pairingCode
                  ),
                  let framed = try? ProtocolCrypto.frame(payload)
            else { try? handle.close(); connection.cancel(); completion(false); return }
            connection.send(content: framed, completion: .contentProcessed { [weak self] error in
                guard let self, error == nil else {
                    try? handle.close(); connection.cancel(); completion(false); return
                }
                self.sendFileChunks(
                    connection, handle: handle, message: message,
                    offset: offset + Int64(chunk.count), completion: completion
                )
            })
            return
        }
        try? handle.close()
        let complete = fileMessage(
            type: "file_complete", source: message,
            fileSHA256: message.fileSHA256, filePath: nil
        )
        guard let sealed = try? ProtocolCrypto.seal(complete, secret: pairingCode),
              let framed = try? ProtocolCrypto.frame(sealed)
        else { connection.cancel(); completion(false); return }
        connection.send(content: framed, completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else { connection.cancel(); completion(false); return }
            self.receiveFrame(connection) { result in
                defer { connection.cancel() }
                guard case .success(let data) = result,
                      let done = try? ProtocolCrypto.open(data, secret: self.pairingCode),
                      done.type == "file_done", done.id == message.id
                else { completion(false); return }
                completion(true)
            }
        })
    }

    private func receiveFile(_ offer: WireMessage, from connection: NWConnection) {
        guard let rawName = offer.fileName, !rawName.isEmpty, rawName.utf8.count <= 255,
              let fileSize = offer.fileSize, fileSize > 0
        else { connection.cancel(); return }
        let name = URL(fileURLWithPath: rawName).lastPathComponent
        guard !name.isEmpty, name != "." else { connection.cancel(); return }
        do {
            let root = try receivedFilesDirectory()
            let transferHash = SHA256.hash(data: Data(offer.id.utf8)).map { String(format: "%02x", $0) }.joined()
            let partialURL = root.appendingPathComponent(".\(transferHash).part")
            if !FileManager.default.fileExists(atPath: partialURL.path) {
                FileManager.default.createFile(atPath: partialURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forUpdating: partialURL)
            var offset = Int64(try handle.seekToEnd())
            if offset > fileSize {
                try handle.truncate(atOffset: 0)
                offset = 0
            }
            try handle.seek(toOffset: UInt64(offset))
            let resume = fileMessage(type: "file_resume", source: offer, resumeOffset: offset, filePath: nil)
            let sealed = try ProtocolCrypto.seal(resume, secret: pairingCode)
            let framed = try ProtocolCrypto.frame(sealed)
            connection.send(content: framed, completion: .contentProcessed { [weak self] error in
                guard let self, error == nil else { try? handle.close(); connection.cancel(); return }
                self.receiveFileChunks(
                    connection, handle: handle, offer: offer,
                    partialURL: partialURL, offset: offset
                )
            })
        } catch {
            connection.cancel()
            report("Could not prepare the incoming file.")
        }
    }

    private func receiveFileChunks(
        _ connection: NWConnection, handle: FileHandle, offer: WireMessage,
        partialURL: URL, offset: Int64
    ) {
        let total = offer.fileSize ?? 0
        if offset < total {
            receiveFrame(connection) { [weak self] result in
                guard let self, case .success(let frame) = result,
                      let chunk = try? ProtocolCrypto.openFileChunk(
                        frame, transferId: offer.id, expectedOffset: offset, secret: self.pairingCode
                      ),
                      Int64(chunk.count) <= total - offset
                else { try? handle.close(); connection.cancel(); return }
                do { try handle.write(contentsOf: chunk) }
                catch { try? handle.close(); connection.cancel(); return }
                self.receiveFileChunks(
                    connection, handle: handle, offer: offer,
                    partialURL: partialURL, offset: offset + Int64(chunk.count)
                )
            }
            return
        }
        do { try handle.synchronize(); try handle.close() }
        catch { connection.cancel(); return }
        receiveFrame(connection) { [weak self] result in
            guard let self, case .success(let frame) = result,
                  let complete = try? ProtocolCrypto.open(frame, secret: self.pairingCode),
                  complete.type == "file_complete", complete.id == offer.id,
                  let expectedHash = complete.fileSHA256, !expectedHash.isEmpty
            else { connection.cancel(); return }
            self.fileQueue.async { [self] in
                guard self.sha256File(partialURL) == expectedHash else { connection.cancel(); return }
                do {
                    let root = partialURL.deletingLastPathComponent()
                    let finalURL = self.availableFileURL(root: root, name: offer.fileName ?? "Shared File")
                    try FileManager.default.moveItem(at: partialURL, to: finalURL)
                    let received = self.fileMessage(
                        type: "file", source: offer,
                        fileSHA256: expectedHash, filePath: finalURL.path,
                        preserveOrigin: true
                    )
                    DispatchQueue.main.async { [self] in self.onMessage?(received) }
                    self.queue.async {
                        let done = self.fileMessage(type: "file_done", source: offer, filePath: nil)
                        if let sealed = try? ProtocolCrypto.seal(done, secret: self.pairingCode),
                           let framed = try? ProtocolCrypto.frame(sealed) {
                            connection.send(content: framed, completion: .contentProcessed { _ in connection.cancel() })
                        } else { connection.cancel() }
                    }
                } catch {
                    connection.cancel()
                    self.report("Could not finish the incoming file.")
                }
            }
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

    private func fileMessage(
        type: String, source: WireMessage, fileSHA256: String? = nil,
        resumeOffset: Int64? = nil, filePath: String? = nil,
        preserveOrigin: Bool = false
    ) -> WireMessage {
        WireMessage(
            version: OmaSendConstants.protocolVersion, type: type, id: source.id,
            originId: preserveOrigin ? source.originId : deviceId,
            originName: preserveOrigin ? source.originName : deviceName,
            createdAt: source.createdAt, text: nil,
            contentType: "application/x-omasend-file",
            fileName: source.fileName, fileSize: source.fileSize,
            fileSHA256: fileSHA256 ?? source.fileSHA256,
            resumeOffset: resumeOffset, filePath: filePath
        )
    }

    private func sha256File(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        do {
            while let data = try handle.read(upToCount: 4 * 1_048_576), !data.isEmpty {
                hasher.update(data: data)
            }
        } catch { return nil }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func receivedFilesDirectory() throws -> URL {
        let root = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let directory = root.appendingPathComponent("OmaSend", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    private func availableFileURL(root: URL, name: String) -> URL {
        let safeName = URL(fileURLWithPath: name).lastPathComponent
        let initial = root.appendingPathComponent(safeName)
        guard FileManager.default.fileExists(atPath: initial.path) else { return initial }
        let extensionName = initial.pathExtension
        let stem = initial.deletingPathExtension().lastPathComponent
        var index = 2
        while true {
            let suffix = extensionName.isEmpty ? "" : ".\(extensionName)"
            let candidate = root.appendingPathComponent("\(stem) \(index)\(suffix)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            index += 1
        }
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
