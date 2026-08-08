// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeNotifierManager",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeNotifierManager",
            path: "Sources/ClaudeNotifierManager"
        )
    ]
)
