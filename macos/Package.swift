// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OmaSend",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "OmaSend", targets: ["OmaSend"])],
    targets: [
        .executableTarget(
            name: "OmaSend",
            path: "Sources/OmaSend",
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OmaSendTests",
            dependencies: ["OmaSend"],
            path: "Tests/OmaSendTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
