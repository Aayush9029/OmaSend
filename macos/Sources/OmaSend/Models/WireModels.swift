import Foundation

enum OmaSendConstants {
    static let protocolVersion = 1
    static let defaultPort: UInt16 = 53_317
    static let maxClipboardBytes = 10_485_760
    static let maxFrameBytes = 14_680_064
    static let fileChunkBytes = 1_048_576
    static let maxHistory = 50
    static let serviceType = "_omasend._tcp."
}

struct WireMessage: Codable, Equatable {
    let version: Int
    let type: String
    let id: String
    let originId: String
    let originName: String
    let createdAt: Int64
    let text: String?
    let contentType: String?
    let data: String?
    let fileName: String?
    let fileSize: Int64?
    let fileSHA256: String?
    let resumeOffset: Int64?
    let filePath: String?

    enum CodingKeys: String, CodingKey {
        case version, type, id, originName, createdAt, text
        case contentType, data, fileName, fileSize, fileSHA256, resumeOffset, filePath
        case originId = "originId"
    }

    init(
        version: Int, type: String, id: String, originId: String,
        originName: String, createdAt: Int64, text: String?,
        contentType: String? = nil, data: String? = nil,
        fileName: String? = nil, fileSize: Int64? = nil,
        fileSHA256: String? = nil, resumeOffset: Int64? = nil,
        filePath: String? = nil
    ) {
        self.version = version
        self.type = type
        self.id = id
        self.originId = originId
        self.originName = originName
        self.createdAt = createdAt
        self.text = text
        self.contentType = contentType
        self.data = data
        self.fileName = fileName
        self.fileSize = fileSize
        self.fileSHA256 = fileSHA256
        self.resumeOffset = resumeOffset
        self.filePath = filePath
    }
}

struct WireEnvelope: Codable {
    let version: Int
    let nonce: String
    let ciphertext: String
}

struct ClipboardItem: Codable, Identifiable, Equatable {
    let id: String
    let text: String
    let originId: String
    let originName: String
    let createdAt: Int64
    let isLocal: Bool
    let contentType: String?
    let data: String?
    var thumbnail: String?
    let fileName: String?
    let fileSize: Int64?
    let filePath: String?

    init(
        id: String, text: String, originId: String, originName: String,
        createdAt: Int64, isLocal: Bool, contentType: String? = nil,
        data: String? = nil, thumbnail: String? = nil,
        fileName: String? = nil, fileSize: Int64? = nil,
        filePath: String? = nil
    ) {
        self.id = id
        self.text = text
        self.originId = originId
        self.originName = originName
        self.createdAt = createdAt
        self.isLocal = isLocal
        self.contentType = contentType
        self.data = data
        self.thumbnail = thumbnail
        self.fileName = fileName
        self.fileSize = fileSize
        self.filePath = filePath
    }

    var date: Date { Date(timeIntervalSince1970: Double(createdAt) / 1_000) }
    var isImage: Bool { thumbnail?.isEmpty == false || (contentType?.hasPrefix("image/") == true && data != nil) }
    var isFile: Bool { fileName != nil && filePath != nil }
    var preview: String {
        if let fileName { return fileName }
        if isImage { return "Image" }
        let collapsed = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return collapsed.count > 110 ? String(collapsed.prefix(107)) + "..." : collapsed
    }
}

struct PeerDevice: Identifiable, Equatable {
    let id: String
    var name: String
    var host: String
    var port: UInt16
    var via: String
    var lastSeen: Date
}
