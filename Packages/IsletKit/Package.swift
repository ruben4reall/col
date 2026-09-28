// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IsletKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IsletCore", targets: ["IsletCore"]),
        .library(name: "IsletShell", targets: ["IsletShell"]),
    ],
    targets: [
        // Geometry and interaction rules, free of AppKit so they run under `swift test`.
        .target(name: "IsletCore"),
        // The window, the island's drawing and its motion.
        .target(name: "IsletShell", dependencies: ["IsletCore"], resources: [.process("Resources")]),
        .testTarget(name: "IsletCoreTests", dependencies: ["IsletCore"]),
        .testTarget(name: "IsletShellTests", dependencies: ["IsletCore", "IsletShell"]),
    ]
)
