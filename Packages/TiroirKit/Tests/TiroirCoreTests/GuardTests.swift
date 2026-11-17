import Foundation
import Testing

/// Source-level promises (spec 10). A failure here is a broken promise, not a style nit.
@Suite struct GuardTests {
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    /// The repository: the app shell lives in `App/`, two levels above the package.
    static let repositoryRoot = packageRoot.deletingLastPathComponent().deletingLastPathComponent()
    static let privateAPIFile = "/Sources/TiroirSystem/PrivateAPI.swift"
    static let updaterFile = "/App/SparkleUpdater.swift"

    static func sources(in directory: String, under root: URL = packageRoot) -> [(path: String, text: String)] {
        let base = root.appendingPathComponent(directory)
        guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .compactMap { url in (try? String(contentsOf: url, encoding: .utf8)).map { (url.path, $0) } }
    }

    /// Shipped code: the package's sources and the app shell.
    static var shipped: [(path: String, text: String)] {
        sources(in: "Sources") + sources(in: "App", under: repositoryRoot)
    }

    /// The frameworks the core may use: no interface, nothing that needs a window server.
    static let coreFrameworks: Set<String> = ["import Foundation", "import CoreGraphics"]

    /// Every import declaration in `text` other than a plain `import Foundation`, whatever its attributes or
    /// access level (`@preconcurrency public import Darwin` counts).
    static func importsOtherThanFoundation(in text: String) -> [String] {
        let modifiers: Set<Substring> = ["public", "package", "internal", "fileprivate", "private"]
        return text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            let words = line.split(separator: " ")
            guard let index = words.firstIndex(of: "import"),
                  words[..<index].allSatisfy({ $0.hasPrefix("@") || modifiers.contains($0) }) else { return nil }
            return line == "import Foundation" ? nil : line
        }
    }

    @Test func thereAreSourcesToCheck() {
        #expect(Self.sources(in: "Sources").count >= 4)
        #expect(!Self.sources(in: "App", under: Self.repositoryRoot).isEmpty)
    }

    @Test func theImportCheckSeesEveryKindOfImport() {
        let text = """
        import Foundation
        import Combine
        @preconcurrency import Darwin
        public import simd
        import struct os.OSAllocatedUnfairLock
        // import AppKit
        let important = "import AppKit"
        """
        #expect(Self.importsOtherThanFoundation(in: text) == [
            "import Combine", "@preconcurrency import Darwin", "public import simd", "import struct os.OSAllocatedUnfairLock",
        ])
    }

    /// The rules run under `swift test` alone: Foundation and CoreGraphics's geometry, never AppKit or SwiftUI.
    @Test func coreStaysFoundationAndGeometryOnly() {
        let files = Self.sources(in: "Sources/TiroirCore")
        #expect(files.contains { $0.text.contains("import Foundation") })
        for file in files {
            let others = Self.importsOtherThanFoundation(in: file.text).filter { !Self.coreFrameworks.contains($0) }
            #expect(others.isEmpty, "\(file.path) imports \(others)")
        }
    }

    /// The only connection Tiroir makes is Sparkle's update check.
    @Test func noNetworkingOutsideTheUpdater() {
        for file in Self.shipped where !file.path.hasSuffix(Self.updaterFile) {
            for forbidden in ["URLSession", "NWConnection", "import Network", "NSURLConnection", "CFNetwork", "WebSocket"] {
                #expect(!file.text.contains(forbidden), "\(file.path) contains \(forbidden)")
            }
        }
    }

    /// Tiroir never takes a picture of the screen or of the menu bar, and never asks for Screen Recording.
    @Test func noScreenCapture() {
        for file in Self.shipped {
            for forbidden in [
                "ScreenCaptureKit", "SCScreenshotManager", "SCStream", "SCShareableContent", "CGWindowListCreateImage",
                "CGDisplayCreateImage", "CGRequestScreenCaptureAccess", "CGPreflightScreenCaptureAccess",
            ] {
                #expect(!file.text.contains(forbidden), "\(file.path) contains \(forbidden)")
            }
        }
    }

    /// Private functions are looked up in one file, so a missing one turns its feature off instead of crashing.
    @Test func privateSymbolsLiveInOneFile() {
        for file in Self.shipped where !file.path.hasSuffix(Self.privateAPIFile) {
            for forbidden in ["dlopen(", "dlsym(", "@_silgen_name", "NSClassFromString", "NSSelectorFromString"] {
                #expect(!file.text.contains(forbidden), "\(file.path) contains \(forbidden)")
            }
        }
    }

    @Test func onlyTheUpdaterUsesSparkle() {
        for file in Self.shipped where file.text.contains("import Sparkle") {
            #expect(file.path.hasSuffix(Self.updaterFile), "\(file.path) imports Sparkle")
        }
    }

    @Test func theOnlyExternalDependencyIsSparkle() throws {
        let project = try String(contentsOf: Self.repositoryRoot.appendingPathComponent("project.yml"), encoding: .utf8)
        let urls = project.split(whereSeparator: \.isNewline).filter { $0.contains("url:") }
        #expect(urls.count == 1)
        #expect(urls.first?.contains("github.com/sparkle-project/Sparkle") == true)
        let manifest = try String(contentsOf: Self.packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        #expect(!manifest.contains(".package("), "TiroirKit must not depend on other packages")
    }

    @Test func noAnalyticsLibraries() {
        for file in Self.shipped {
            for forbidden in ["Firebase", "Mixpanel", "Amplitude", "Segment", "Sentry", "Crashlytics", "TelemetryDeck", "PostHog"] {
                #expect(!file.text.contains("import \(forbidden)"), "\(file.path) imports \(forbidden)")
            }
        }
    }

    /// Visible text never uses an em dash (house style).
    /// Tests name their preferences domains with scratchDefaultsName(), in the temporary folder. A domain named like an
    /// app's leaves a file in ~/Library/Preferences on every run of the tests, however carefully the test removes it.
    @Test func testsKeepTheirPreferencesInTheTemporaryFolder() {
        let tests = Self.sources(in: "Tests").filter { !$0.path.hasSuffix("/GuardTests.swift") }
        #expect(tests.contains { $0.text.contains("scratchDefaultsName()") })
        for file in tests {
            #expect(!file.text.contains("UserDefaults(suiteName: \""), "\(file.path) names a preferences domain in place")
            #expect(!file.text.contains("\"ch.rubencatalao.tiroir."), "\(file.path) names a preferences domain like an app's")
        }
    }

    @Test func noEmDashInSources() {
        for file in Self.shipped {
            #expect(!file.text.contains("\u{2014}"), "\(file.path) contains an em dash")
        }
    }
}
