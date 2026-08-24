import Foundation
import Testing
@testable import OmaSend

private let testSecret = "omasend-test-secret-0123456789-abcdef"

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
    let pixels = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    let message = WireMessage(
        version: 1, type: "clipboard", id: "image-1", originId: "mac",
        originName: "Mac", createdAt: 43, text: nil,
        contentType: "image/png", data: pixels.base64EncodedString()
    )
    let sealed = try ProtocolCrypto.seal(message, secret: testSecret)
    let opened = try ProtocolCrypto.open(sealed, secret: testSecret)
    #expect(opened == message)
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
