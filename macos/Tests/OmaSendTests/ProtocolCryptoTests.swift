import Foundation
import Testing
@testable import OmaSend

private let testSecret = "omasend-test-secret-0123456789-abcdef"

@Test func transferPulseDirections() {
    #expect(TransferDirection.outgoing.barIndices == Array(0..<9))
    #expect(TransferDirection.incoming.barIndices == Array((0..<9).reversed()))
}

@Test func roundTrip() throws {
    let message = WireMessage(version: 1, type: "clipboard", id: "item-1", originId: "mac", originName: "Mac", createdAt: 42, text: "hello 👋")
    let sealed = try ProtocolCrypto.seal(message, secret: testSecret)
    #expect(try ProtocolCrypto.open(sealed, secret: testSecret) == message)
}

@Test func decryptsGoInteropVector() throws {
    let json = #"{"version":1,"nonce":"AAECAwQFBgcICQoL","ciphertext":"BuLeQaS379eOUMKOqEQkmh/VItWh+DDVCEpm+aX9PgUW+hi7WSjtc1AkBkakzCrnyad5Iu8KDPnYSUCpct+jYu5X8nWbPJzO+zbgXMlzG7ZEigRZlzBagX3AnwmZH1Rk4wQw2kH62UJGHdtVLv43+3dwdsJVa/eQP+4yVhC/tmhANG7kw4iN7bjsz0q3aRHc0z1B+mf++WeF"}"#
    let message = try ProtocolCrypto.open(Data(json.utf8), secret: testSecret)
    #expect(message.id == "interop-1")
    #expect(message.originId == "go")
    #expect(message.text == "OmaSend interop")
}

@Test func rejectsWrongPairingCode() throws {
    let message = WireMessage(version: 1, type: "hello", id: "1", originId: "mac", originName: "Mac", createdAt: 1, text: nil)
    let sealed = try ProtocolCrypto.seal(message, secret: testSecret)
    #expect(throws: ProtocolCryptoError.self) {
        try ProtocolCrypto.open(sealed, secret: "another-long-secret-0123456789")
    }
}

@Test func imageRoundTrip() throws {
    let pixels = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    let message = WireMessage(
        version: 1, type: "clipboard", id: "image-1", originId: "mac",
        originName: "Mac", createdAt: 43, text: nil,
        contentType: "image/png", data: pixels.base64EncodedString()
    )
    let sealed = try ProtocolCrypto.seal(message, secret: testSecret)
    let opened = try ProtocolCrypto.open(sealed, secret: testSecret)
    #expect(opened == message)
}

@Test func rejectsEmptyClipboardItem() throws {
    let message = WireMessage(
        version: 1, type: "clipboard", id: "empty-1", originId: "mac",
        originName: "Mac", createdAt: 45, text: "  \n"
    )
    let sealed = try ProtocolCrypto.seal(message, secret: testSecret)
    #expect(throws: ProtocolCryptoError.self) {
        try ProtocolCrypto.open(sealed, secret: testSecret)
    }
}

@Test func rejectsInvalidImageEncoding() throws {
    let message = WireMessage(
        version: 1, type: "clipboard", id: "image-2", originId: "mac",
        originName: "Mac", createdAt: 44, text: nil,
        contentType: "image/png", data: "not base64"
    )
    let sealed = try ProtocolCrypto.seal(message, secret: testSecret)
    #expect(throws: ProtocolCryptoError.self) {
        try ProtocolCrypto.open(sealed, secret: testSecret)
    }
}

@Test func fileChunkRoundTrip() throws {
    let plaintext = Data("OmaSend file chunk".utf8)
    let payload = try ProtocolCrypto.sealFileChunk(
        plaintext, transferId: "transfer-1", offset: 4_096, secret: testSecret
    )
    #expect(try ProtocolCrypto.openFileChunk(
        payload, transferId: "transfer-1", expectedOffset: 4_096, secret: testSecret
    ) == plaintext)
    var tampered = payload
    tampered[tampered.index(before: tampered.endIndex)] ^= 1
    #expect(throws: ProtocolCryptoError.self) {
        try ProtocolCrypto.openFileChunk(
            tampered, transferId: "transfer-1", expectedOffset: 4_096, secret: testSecret
        )
    }
}

@Test func fileChunkMatchesGoVector() throws {
    let nonce = Data((0...11).map(UInt8.init))
    let payload = try ProtocolCrypto.sealFileChunk(
        Data("OmaSend file chunk".utf8), transferId: "transfer-1", offset: 4_096,
        secret: testSecret, nonceData: nonce
    )
    #expect(payload.map { String(format: "%02x", $0) }.joined() ==
        "0000000000001000000102030405060708090a0b32adc977b3aae298861b94daa405389601db437066285b755d54209de91e130af412")
}
