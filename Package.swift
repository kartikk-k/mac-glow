// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacGlow",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacGlow",
            path: "Sources/MacGlow"
        )
    ]
)
