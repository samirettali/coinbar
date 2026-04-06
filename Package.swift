// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Coinbar",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "Coinbar",
            path: "Sources"
        ),
    ]
)
