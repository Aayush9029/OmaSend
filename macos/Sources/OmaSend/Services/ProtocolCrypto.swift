import CryptoKit
import Foundation

enum ProtocolCryptoError: Error, LocalizedError {
    case pairingCodeTooShort
    case malformedEnvelope
    case authenticationFailed
    case invalidMessage

    var errorDescription: String? {
        switch self {
        case .pairingCodeTooShort: "Pairing code must contain at least 20 characters."
        case .malformedEnvelope: "The encrypted message is malformed."
        case .authenticationFailed: "The message did not come from a paired device."
        case .invalidMessage: "The clipboard message is invalid."
        }
    }
}

enum ProtocolCrypto {
    private static let additionalData = Data("omasend-v1".utf8)

    static func seal(_ message: WireMessage, secret: String, nonceData: Data? = nil) throws -> Data {
        guard secret.count >= 20 else { throw ProtocolCryptoError.pairingCodeTooShort }
        let key = SymmetricKey(data: SHA256.hash(data: Data(secret.utf8)))
        let plain = try JSONEncoder().encode(message)
        let sealed: AES.GCM.SealedBox
        if let nonceData {
            sealed = try AES.GCM.seal(plain, using: key, nonce: AES.GCM.Nonce(data: nonceData), authenticating: additionalData)
        } else {
            sealed = try AES.GCM.seal(plain, using: key, authenticating: additionalData)
        }
        let ciphertext = sealed.ciphertext + sealed.tag
        return try JSONEncoder().encode(WireEnvelope(
            version: OmaSendConstants.protocolVersion,
            nonce: Data(sealed.nonce).base64EncodedString(),
            ciphertext: ciphertext.base64EncodedString()
        ))
    }

    static func open(_ data: Data, secret: String) throws -> WireMessage {
        guard secret.count >= 20 else { throw ProtocolCryptoError.pairingCodeTooShort }
        guard let envelope = try? JSONDecoder().decode(WireEnvelope.self, from: data),
              envelope.version == OmaSendConstants.protocolVersion,
              let nonceData = Data(base64Encoded: envelope.nonce),
              let combined = Data(base64Encoded: envelope.ciphertext),
              combined.count >= 16
        else { throw ProtocolCryptoError.malformedEnvelope }

        let key = SymmetricKey(data: SHA256.hash(data: Data(secret.utf8)))
        let ciphertext = combined.dropLast(16)
        let tag = combined.suffix(16)
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonceData),
            ciphertext: ciphertext,
            tag: tag
        )
        let plain: Data
        do { plain = try AES.GCM.open(box, using: key, authenticating: additionalData) }
        catch { throw ProtocolCryptoError.authenticationFailed }
        guard let message = try? JSONDecoder().decode(WireMessage.self, from: plain),
              message.version == OmaSendConstants.protocolVersion,
              !message.id.isEmpty,
              !message.originId.isEmpty,
              (message.text?.utf8.count ?? 0) <= OmaSendConstants.maxClipboardBytes,
              validClipboardData(message.data)
        else { throw ProtocolCryptoError.invalidMessage }
        return message
    }

    private static func validClipboardData(_ encoded: String?) -> Bool {
        guard let encoded else { return true }
        guard let data = Data(base64Encoded: encoded) else { return false }
        return data.count <= OmaSendConstants.maxClipboardBytes
    }

    static func frame(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= OmaSendConstants.maxFrameBytes else {
            throw ProtocolCryptoError.invalidMessage
        }
        var length = UInt32(data.count).bigEndian
        return Data(bytes: &length, count: 4) + data
    }

    static func generateSecret() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
