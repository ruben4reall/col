// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TiroirKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TiroirCore", targets: ["TiroirCore"]),
        .library(name: "TiroirSystem", targets: ["TiroirSystem"]),
        .library(name: "TiroirUI", targets: ["TiroirUI"]),
        .library(name: "TiroirApp", targets: ["TiroirApp"]),
    ],
    targets: [
        // Drawers, Smart Sort, layout planning, settings: Foundation only, so `swift test` covers every rule.
        .target(name: "TiroirCore", resources: [.process("Resources")]),
        // The two menu bar engines (macOS 26 and 27) and the system services around them.
        .target(name: "TiroirSystem", dependencies: ["TiroirCore"]),
        // Drawers, search, the welcome and Settings windows.
        .target(name: "TiroirUI", dependencies: ["TiroirCore", "TiroirSystem"], resources: [.process("Resources")]),
        // The model and the coordinator that wire the engine, the interface and the services together.
        .target(name: "TiroirApp", dependencies: ["TiroirCore", "TiroirSystem", "TiroirUI"]),
        .testTarget(name: "TiroirCoreTests", dependencies: ["TiroirCore"]),
        .testTarget(name: "TiroirSystemTests", dependencies: ["TiroirSystem", "TiroirCore"]),
        .testTarget(name: "TiroirUITests", dependencies: ["TiroirUI", "TiroirSystem", "TiroirCore"]),
        .testTarget(name: "TiroirAppTests", dependencies: ["TiroirApp", "TiroirUI", "TiroirSystem", "TiroirCore"]),
    ]
)
