import CoreGraphics
import Foundation
import Testing
@testable import ColShell

@MainActor
struct DesktopPictureTests {
    private let light = DesktopPicture.Kept.Key(url: URL(fileURLWithPath: "/System/Library/CoreServices/DefaultDesktop.heic"), pixels: 3024, dark: false)
    private var dark: DesktopPicture.Kept.Key {
        var key = light
        key.dark = true
        return key
    }

    private func picture() throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try #require(context.makeImage())
    }

    @Test func thePictureGoesWithTheLastStageThatShowsIt() throws {
        let welcomeStage = NSObject(), settingsStage = NSObject()
        let welcome = ObjectIdentifier(welcomeStage), settings = ObjectIdentifier(settingsStage)
        var kept = DesktopPicture.Kept()
        let none = kept.image(for: light, holder: welcome)
        #expect(none == nil)
        kept.keep(try picture(), for: light, holder: welcome)
        let shared = kept.image(for: light, holder: settings)
        #expect(shared != nil)

        // The welcome closes while Settings still shows the picture: it stays.
        let welcomeWasLast = kept.letGo(welcome)
        #expect(!welcomeWasLast)
        kept.forgetUnlessHeld()
        #expect(kept.image != nil)

        // Settings closes too: nobody shows it, it goes, and letting go twice changes nothing.
        let settingsWasLast = kept.letGo(settings)
        let twice = kept.letGo(settings)
        #expect(settingsWasLast && !twice)
        kept.forgetUnlessHeld()
        #expect(kept.image == nil && kept.key == nil)
    }

    @Test func aStageThatTakesOverKeepsThePicture() throws {
        let oldStage = NSObject(), newStage = NSObject()
        let before = ObjectIdentifier(oldStage), after = ObjectIdentifier(newStage)
        var kept = DesktopPicture.Kept()
        kept.keep(try picture(), for: light, holder: before)
        // A pane change: the old stage lets go, and the new one asks before the picture is freed on the next turn.
        let last = kept.letGo(before)
        #expect(last)
        let again = kept.image(for: light, holder: after)
        #expect(again != nil)
        kept.forgetUnlessHeld()
        #expect(kept.image != nil)
    }

    @Test func onlyOnePictureIsKept() throws {
        let view = NSObject()
        let stage = ObjectIdentifier(view)
        var kept = DesktopPicture.Kept()
        kept.keep(try picture(), for: light, holder: stage)
        // The Mac turns dark: the dark picture takes the light one's place, which is not kept beside it.
        let other = kept.image(for: dark, holder: stage)
        #expect(other == nil)
        kept.keep(try picture(), for: dark, holder: stage)
        let lightAgain = kept.image(for: light, holder: stage)
        #expect(lightAgain == nil)
        #expect(kept.key == dark)
    }
}
