import Foundation

struct AppConfiguration: Codable {
    var deviceId: String
    var deviceName: String
    var pairingCode: String
    var autoCopy: Bool
    var history: [ClipboardItem]

    static func fresh() -> AppConfiguration {
        AppConfiguration(
            deviceId: UUID().uuidString.lowercased(),
            deviceName: Host.current().localizedName ?? "Mac",
            pairingCode: ProtocolCrypto.generateSecret(),
            autoCopy: false,
            history: []
        )
    }
}

final class ConfigurationStore {
    private let url: URL

    init(url: URL? = nil) {
        if let url { self.url = url; return }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.url = root.appendingPathComponent("OmaSend/config.json")
    }

    func load() -> AppConfiguration {
        guard let data = try? Data(contentsOf: url),
              let configuration = try? JSONDecoder().decode(AppConfiguration.self, from: data)
        else {
            let configuration = AppConfiguration.fresh()
            try? save(configuration)
            return configuration
        }
        return configuration
    }

    func save(_ configuration: AppConfiguration) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder.pretty.encode(configuration)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

