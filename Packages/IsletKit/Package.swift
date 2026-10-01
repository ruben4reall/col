// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IsletKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IsletCore", targets: ["IsletCore"]),
        .library(name: "IsletShell", targets: ["IsletShell"]),
        .library(name: "IsletPrompter", targets: ["IsletPrompter"]),
    ],
    targets: [
        // Geometry and interaction rules, free of AppKit so they run under `swift test`.
        .target(name: "IsletCore"),
        // The prompter: its window in the notch, speech, the library of scripts, the phone remote.
        .target(name: "IsletPrompter", dependencies: ["IsletCore"], resources: [.process("Resources")]),
        // The window, the island's drawing and its motion.
        .target(name: "IsletShell", dependencies: ["IsletCore", "IsletPrompter"], resources: [.process("Resources")]),
        .testTarget(name: "IsletCoreTests", dependencies: ["IsletCore"]),
        .testTarget(name: "IsletShellTests", dependencies: ["IsletCore", "IsletShell"]),
    ]
)
