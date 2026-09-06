import Foundation
import Testing
@testable import OmaSend

@Test func trustedLANProtocolIsolation() throws {
    let key = "test-key-01234567890123456789"
    let message = WireMessage(version: 1, type: "clipboard", id: "lan-1", originId: "web", originName: "Web", createdAt: 1, text: "hello 👋", filePath: "/private/file")
    let frame = try ProtocolCrypto.seal(message, secret: key, trustedLAN: true)
    let opened = try ProtocolCrypto.open(frame, secret: "different", trustedLAN: true)
    #expect(opened.text == message.text)
    #expect(opened.filePath == nil)
    #expect((try? ProtocolCrypto.open(frame, secret: key)) == nil)
    #expect((try? ProtocolCrypto.open(ProtocolCrypto.seal(message, secret: key), secret: key, trustedLAN: true)) == nil)
    let plain = Data("OmaSend file chunk".utf8)
    let chunk = try ProtocolCrypto.sealFileChunk(plain, transferId: "x", offset: 4096, secret: key, trustedLAN: true)
    #expect(chunk == Data([79,83,76,49,0,0,0,0,0,0,16,0]) + plain)
    #expect(try ProtocolCrypto.openFileChunk(chunk, transferId: "x", expectedOffset: 4096, secret: "different", trustedLAN: true) == plain)
    #expect((try? ProtocolCrypto.openFileChunk(chunk, transferId: "x", expectedOffset: 4096, secret: key)) == nil)
    #expect((try? ProtocolCrypto.openFileChunk(chunk, transferId: "x", expectedOffset: 0, secret: key, trustedLAN: true)) == nil)
    #expect((try? ProtocolCrypto.openFileChunk(Data(chunk.prefix(5)), transferId: "x", expectedOffset: 4096, secret: key, trustedLAN: true)) == nil)
    for ip in ["127.0.0.1", "192.168.1.2", "172.16.0.1", "10.1.2.3", "::1", "fe80::1", "fd00::1"] { #expect(NetworkService.isLAN(ip)) }
    for ip in ["8.8.8.8", "100.64.1.2", "172.32.0.1", "example.com", "ff02::1", ""] { #expect(!NetworkService.isLAN(ip)) }
}

@Test func oldConfigurationRemainsEncrypted() throws {
    let json = #"{"deviceId":"keep-id","deviceName":"My Mac","pairingCode":"keep-this-key-0123456789","autoCopy":true,"history":[]}"#
    let config = try JSONDecoder().decode(AppConfiguration.self, from: Data(json.utf8))
    #expect(config.trustedLAN == nil)
    #expect(config.deviceId == "keep-id")
    #expect(config.pairingCode == "keep-this-key-0123456789")
    #expect(config.autoCopy)
}
