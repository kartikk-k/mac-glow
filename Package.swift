// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacGlow",
    platforms: [.macOS(.v13)],
    targets: [
        // Tiny Objective-C shim to catch NSExceptions (e.g. AVAudioEngine's
        // installTap), which Swift's do/catch cannot handle.
        .target(name: "ObjCGuard", path: "Sources/ObjCGuard"),
        .executableTarget(
            name: "MacGlow",
            dependencies: ["ObjCGuard"],
            path: "Sources/MacGlow"
        )
    ]
)
