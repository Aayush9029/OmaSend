import AppKit
import Testing
@testable import OmaSend

@MainActor
@Test func previewExportsOriginalImageAndCleansUp() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = ClipboardPreviewStore(directory: directory)
    defer { store.removeTemporaryFiles() }
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 480,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ))
    let original = try #require(bitmap.representation(using: .png, properties: [:]))
    let item = ClipboardItem(
        id: "../../untrusted-id", text: "", originId: "peer", originName: "Desktop",
        createdAt: 1, isLocal: false, contentType: "image/png",
        data: original.base64EncodedString(), thumbnail: "not-the-original"
    )
    let url = try store.previewURL(for: item)
    #expect(url.path.hasPrefix(directory.path + "/"))
    let exported = try #require(NSBitmapImageRep(data: Data(contentsOf: url)))
    #expect(exported.pixelsWide == 640)
    #expect(exported.pixelsHigh == 480)
    store.removeTemporaryFiles()
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@MainActor
@Test func previewUsesExistingFileWithoutRemovingIt() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
    try Data("original file".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = ClipboardPreviewStore()
    let item = ClipboardItem(
        id: "file", text: "", originId: "mac", originName: "Mac",
        createdAt: 1, isLocal: true, thumbnail: "thumbnail",
        fileName: url.lastPathComponent, filePath: url.path
    )
    #expect(try store.previewURL(for: item) == url)
    store.removeTemporaryFiles()
    #expect(FileManager.default.fileExists(atPath: url.path))
    try FileManager.default.removeItem(at: url)
    #expect(throws: CocoaError.self) { try store.previewURL(for: item) }
}

@MainActor
@Test func previewRejectsInvalidDataInsteadOfUsingThumbnail() {
    let store = ClipboardPreviewStore()
    defer { store.removeTemporaryFiles() }
    let item = ClipboardItem(
        id: "invalid", text: "", originId: "peer", originName: "Desktop",
        createdAt: 1, isLocal: false, contentType: "image/png",
        data: "not an image", thumbnail: "thumbnail"
    )
    #expect(throws: CocoaError.self) { try store.previewURL(for: item) }
}
