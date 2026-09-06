import Foundation
import Testing
@testable import OmaSend

@MainActor @Test func nativeTCPFanout() async throws {
    let a = NetworkService(), b = NetworkService(), c = NetworkService()
    let secret = "omasend-test-secret-0123456789-abcdef"
    var peerCount = 0
    var receivedB: [WireMessage] = [], receivedC: [WireMessage] = []
    a.onPeersChanged = { peerCount = $0.count }
    b.onMessage = { receivedB.append($0) }
    c.onMessage = { receivedC.append($0) }
    a.start(deviceId: "test-a", deviceName: "Test A", pairingCode: secret, port: 59331, discover: false)
    b.start(deviceId: "test-b", deviceName: "Test B", pairingCode: secret, port: 59332, discover: false)
    c.start(deviceId: "test-c", deviceName: "Test C", pairingCode: secret, port: 59333, discover: false)
    defer { a.stop(); b.stop(); c.stop() }
    try await Task.sleep(nanoseconds: 250_000_000)
    a.connect(host: "127.0.0.1", port: 59332)
    a.connect(host: "127.0.0.1", port: 59333)
    for _ in 0..<50 {
        if peerCount == 2 { break }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    #expect(peerCount == 2)
    let message = WireMessage(version: 1, type: "clipboard", id: "fanout", originId: "test-a", originName: "Test A", createdAt: 1, text: "Three native Swift peers")
    a.broadcast(message)
    for _ in 0..<50 {
        if receivedB.count == 1 && receivedC.count == 1 { break }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    #expect(receivedB == [message])
    #expect(receivedC == [message])
}
@MainActor @Test func trustedLANTCPFanout() async throws {
    let a = NetworkService(), b = NetworkService(), c = NetworkService()
    let secret = "omasend-test-secret-0123456789-abcdef"
    var peerCount = 0
    var receivedB: [WireMessage] = [], receivedC: [WireMessage] = []
    a.onPeersChanged = { peerCount = $0.count }
    b.onMessage = { receivedB.append($0) }
    c.onMessage = { receivedC.append($0) }
    a.start(deviceId: "test-a", deviceName: "Test A", pairingCode: secret, port: 59341, discover: false, trustedLAN: true)
    b.start(deviceId: "test-b", deviceName: "Test B", pairingCode: "different-key-0123456789", port: 59342, discover: false, trustedLAN: true)
    c.start(deviceId: "test-c", deviceName: "Test C", pairingCode: secret, port: 59343, discover: false, trustedLAN: true)
    defer { a.stop(); b.stop(); c.stop() }
    try await Task.sleep(nanoseconds: 250_000_000)
    a.connect(host: "127.0.0.1", port: 59342)
    a.connect(host: "127.0.0.1", port: 59343)
    for _ in 0..<50 {
        if peerCount == 2 { break }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    #expect(peerCount == 2)
    let message = WireMessage(version: 1, type: "clipboard", id: "fanout", originId: "test-a", originName: "Test A", createdAt: 1, text: "Three native Swift peers")
    a.broadcast(message)
    for _ in 0..<50 {
        if receivedB.count == 1 && receivedC.count == 1 { break }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    #expect(receivedB == [message])
    #expect(receivedC == [message])
}
