import AppKit

@MainActor
final class ClipboardPreviewStore {
    private let directory: URL

    init(directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("OmaSend-Previews-\(UUID().uuidString)", isDirectory: true)) {
        self.directory = directory
    }

    func previewURL(for item: ClipboardItem) throws -> URL {
        if let path = item.filePath {
            guard FileManager.default.fileExists(atPath: path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            return URL(fileURLWithPath: path)
        }
        guard let encoded = item.data, let data = Data(base64Encoded: encoded),
              let image = NSBitmapImageRep(data: data),
              let png = image.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let itemDirectory = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: itemDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = itemDirectory.appendingPathComponent("Clipboard Image.png")
        try png.write(to: url, options: .atomic)
        return url
    }

    func removeTemporaryFiles() {
        try? FileManager.default.removeItem(at: directory)
    }
}
