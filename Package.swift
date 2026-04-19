// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pulse",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Pulse",
            dependencies: ["Yams"],
            path: "Sources/Pulse"
        ),
    ]
)
