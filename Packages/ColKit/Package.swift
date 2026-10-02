// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ColKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ColCore", targets: ["ColCore"]),
        .library(name: "ColShell", targets: ["ColShell"]),
        .library(name: "ColPrompter", targets: ["ColPrompter"]),
    ],
    targets: [
        // Geometry and interaction rules, free of AppKit so they run under `swift test`.
        .target(name: "ColCore"),
        // The prompter: its window in the notch, speech, the library of scripts, the phone remote.
        .target(name: "ColPrompter", dependencies: ["ColCore"], resources: [.process("Resources")]),
        // The window, the island's drawing and its motion.
        .target(name: "ColShell", dependencies: ["ColCore", "ColPrompter"], resources: [.process("Resources")]),
        .testTarget(name: "ColCoreTests", dependencies: ["ColCore"]),
        .testTarget(name: "ColShellTests", dependencies: ["ColCore", "ColShell"]),
        .testTarget(name: "ColPrompterTests", dependencies: ["ColCore", "ColPrompter"]),
    ]
)
