import AppKit
import Testing
@testable import IsletCore
@testable import IsletShell

@MainActor
struct AppIconsTests {
    @Test func everyLogoNamedIsCarried() {
        let marks = AICatalog.apps.compactMap(\.mark) + CodingAgent.allCases.compactMap(\.icon.mark)
            + ModelServerKind.allCases.compactMap(\.icon.mark)
        #expect(!marks.isEmpty)
        for mark in Set(marks) { #expect(AppIcons.carries(mark: mark), "no tile for \(mark)") }
    }

    @Test func aLogoIsDrawnAtTheSizeItShows() throws {
        let image = try #require(AppIcons.image(for: CodingAgent.copilot.icon, side: 23, scale: 2))
        // 46 pixels asked, the next step drawn: never the 256-pixel tile itself.
        #expect(image.width == 48 && image.height == 48)
        #expect(AppIcons.image(for: .islet, side: 23, scale: 2) == nil)
    }
}
