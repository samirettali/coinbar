// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "Pulse",
            path: "Sources/Pulse"
        ),
    ]
)
