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
    dependencies: [
        // The menu bar option's drawers, from Tiroir (macOS 26 and later; nothing of them runs while the option is off).
        .package(path: "../TiroirKit"),
    ],
    targets: [
        // Geometry and interaction rules, free of AppKit so they run under `swift test`.
        .target(name: "ColCore"),
        // The prompter: its window in the notch, speech, the library of scripts, the phone remote.
        .target(name: "ColPrompter", dependencies: ["ColCore"], resources: [.process("Resources")]),
        // The window, the island's drawing and its motion.
        .target(name: "ColShell", dependencies: [
            "ColCore", "ColPrompter",
            .product(name: "TiroirApp", package: "TiroirKit"),
            .product(name: "TiroirUI", package: "TiroirKit"),
            .product(name: "TiroirSystem", package: "TiroirKit"),
            .product(name: "TiroirCore", package: "TiroirKit"),
        ], resources: [.process("Resources")]),
        .testTarget(name: "ColCoreTests", dependencies: ["ColCore"]),
        .testTarget(name: "ColShellTests", dependencies: ["ColCore", "ColShell", .product(name: "TiroirCore", package: "TiroirKit")]),
        .testTarget(name: "ColPrompterTests", dependencies: ["ColCore", "ColPrompter"]),
    ]
)
