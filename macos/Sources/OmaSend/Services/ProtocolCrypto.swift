import CryptoKit
import Foundation
import ImageIO

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
    private static let fileAdditionalData = Data("omasend-file-v1".utf8)

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
              validClipboardData(message.data),
              message.type != "clipboard" || validClipboardContent(message)
        else { throw ProtocolCryptoError.invalidMessage }
        return message
    }

    private static func validClipboardContent(_ message: WireMessage) -> Bool {
        if let text = message.text,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           message.contentType == nil || message.contentType?.hasPrefix("text/") == true {
            return true
        }
        guard let contentType = message.contentType,
              ["image/png", "image/jpeg", "image/gif"].contains(contentType),
              let encoded = message.data,
              let data = Data(base64Encoded: encoded),
              !data.isEmpty
        else { return false }
        return CGImageSourceCreateWithData(data as CFData, nil) != nil
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

    static func sealFileChunk(
        _ plaintext: Data, transferId: String, offset: Int64,
        secret: String, nonceData: Data? = nil
    ) throws -> Data {
        guard secret.count >= 20, offset >= 0, !plaintext.isEmpty,
              plaintext.count <= OmaSendConstants.fileChunkBytes
        else { throw ProtocolCryptoError.invalidMessage }
        let key = SymmetricKey(data: SHA256.hash(data: Data(secret.utf8)))
        var bigOffset = UInt64(offset).bigEndian
        let offsetData = Data(bytes: &bigOffset, count: MemoryLayout<UInt64>.size)
        let aad = fileAdditionalData + Data(transferId.utf8) + offsetData
        let sealed: AES.GCM.SealedBox
        if let nonceData {
            sealed = try AES.GCM.seal(
                plaintext, using: key, nonce: AES.GCM.Nonce(data: nonceData), authenticating: aad
            )
        } else {
            sealed = try AES.GCM.seal(plaintext, using: key, authenticating: aad)
        }
        return offsetData + Data(sealed.nonce) + sealed.ciphertext + sealed.tag
    }

    static func openFileChunk(
        _ payload: Data, transferId: String, expectedOffset: Int64, secret: String
    ) throws -> Data {
        guard secret.count >= 20,
              payload.count > MemoryLayout<UInt64>.size + 12 + 16
        else { throw ProtocolCryptoError.invalidMessage }
        let offset = payload.prefix(8).withUnsafeBytes {
            Int64(UInt64(bigEndian: $0.loadUnaligned(as: UInt64.self)))
        }
        guard offset == expectedOffset else { throw ProtocolCryptoError.invalidMessage }
        let nonce = payload.subdata(in: 8..<20)
        let combined = payload.dropFirst(20)
        let ciphertext = combined.dropLast(16)
        let tag = combined.suffix(16)
        var bigOffset = UInt64(offset).bigEndian
        let offsetData = Data(bytes: &bigOffset, count: MemoryLayout<UInt64>.size)
        let aad = fileAdditionalData + Data(transferId.utf8) + offsetData
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext, tag: tag
        )
        do {
            return try AES.GCM.open(box, using: SymmetricKey(data: SHA256.hash(data: Data(secret.utf8))), authenticating: aad)
        } catch {
            throw ProtocolCryptoError.authenticationFailed
        }
    }
}
