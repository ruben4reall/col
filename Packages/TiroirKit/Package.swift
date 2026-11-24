// swift-tools-version: 6.2
import PackageDescription

// The drawers of Col's menu bar option. They need macOS 26 or later, and Col runs from macOS 14: the libraries are
// built for macOS 14 and every declaration outside TiroirCore is marked `@available(macOS 26, *)`, so nothing of them
// is reached on an older system. Swift Testing refuses suites marked that way, so the tests are compiled for macOS 26
// itself (they run on the Mac or CI runner that builds them). Swift 6.4's new build system ignores that target, so run
// them with the native one: `swift test --build-system native --package-path Packages/TiroirKit`.
#if arch(arm64)
let testTriple = "arm64-apple-macosx26.0"
#else
let testTriple = "x86_64-apple-macosx26.0"
#endif
let testSettings: [SwiftSetting] = [.unsafeFlags(["-target", testTriple])]

let package = Package(
    name: "TiroirKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
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
        // Drawers, search, the welcome and the drawers' settings window.
        .target(name: "TiroirUI", dependencies: ["TiroirCore", "TiroirSystem"], resources: [.process("Resources")]),
        // The coordinator that wires the engine, the interface and the services together, and the way Col runs it.
        .target(name: "TiroirApp", dependencies: ["TiroirCore", "TiroirSystem", "TiroirUI"]),
        .testTarget(name: "TiroirCoreTests", dependencies: ["TiroirCore"], swiftSettings: testSettings),
        .testTarget(name: "TiroirSystemTests", dependencies: ["TiroirSystem", "TiroirCore"], swiftSettings: testSettings),
        .testTarget(name: "TiroirUITests", dependencies: ["TiroirUI", "TiroirSystem", "TiroirCore"], swiftSettings: testSettings),
        .testTarget(name: "TiroirAppTests", dependencies: ["TiroirApp", "TiroirUI", "TiroirSystem", "TiroirCore"],
                    swiftSettings: testSettings),
    ]
)
