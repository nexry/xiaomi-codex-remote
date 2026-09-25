// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "XiaomiCodexRemote",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "XiaomiCodexRemote", targets: ["XiaomiCodexRemote"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "AudioExceptionGuard",
            path: "Sources/AudioExceptionGuard"
        ),
        .executableTarget(
            name: "XiaomiCodexRemote",
            dependencies: ["AudioExceptionGuard"],
            path: "Sources/XiaomiCodexRemote"
        ),
        .testTarget(
            name: "XiaomiCodexRemoteTests",
            dependencies: ["XiaomiCodexRemote"],
            path: "Tests/XiaomiCodexRemoteTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
