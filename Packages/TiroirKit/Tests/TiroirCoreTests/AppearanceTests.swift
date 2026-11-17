import Foundation
import Testing
@testable import TiroirCore

@Suite struct AppearanceTests {
    /// The appearance exactly as Tiroir 1.0 saves it (sorted keys): the main look in flat fields, no shape, no dark look.
    static let savedByOnePointZero = #"{"border":true,"color":{"alpha":1,"blue":0.6,"green":0.4,"red":0.2},"gradientEnd":{"alpha":1,"blue":0.1,"green":0.5,"red":0.9},"opacity":0.5,"shadow":false,"tint":"gradient"}"#

    /// What those settings meant, and still mean.
    static let meantByOnePointZero = Appearance(
        tint: .gradient, color: RGBA(red: 0.2, green: 0.4, blue: 0.6), gradientEnd: RGBA(red: 0.9, green: 0.5, blue: 0.1),
        opacity: 0.5, border: true, shadow: false)

    /// A whole settings value exactly as Tiroir 1.0's `SettingsStore` saves it.
    static let settingsSavedByOnePointZero = #"{"appearance":\#(savedByOnePointZero),"behavior":{"hoverDelay":0.25,"opensOnHover":false,"rehideDelay":0.5,"showsEverythingWithOption":true,"showsTiroirIcon":true},"hasCompletedWelcome":true,"layout":{"drawers":[],"newIconPolicy":"sortIntoDrawer","placements":[]},"pinned":[],"schemaVersion":1,"shortcuts":{"allDrawer":null,"focus":{"keyCode":3,"keyLabel":"F","modifiers":11},"search":{"keyCode":49,"keyLabel":"Space","modifiers":11}},"sortStrategy":"purpose","userCategories":{}}"#

    @Test func anAppearanceSavedByOnePointZeroReadsUnchanged() throws {
        let appearance = try JSONDecoder().decode(Appearance.self, from: Data(Self.savedByOnePointZero.utf8))
        #expect(appearance == Self.meantByOnePointZero)
        #expect(appearance.shape == .full)
        #expect(appearance.darkLook == nil)
        #expect(appearance.look(inDarkMode: true) == appearance.look(inDarkMode: false))
    }

    @Test func settingsSavedByOnePointZeroLoadUnchanged() {
        let name = scratchDefaultsName()
        let defaults = UserDefaults(suiteName: name)!
        defer { discardDefaults(name) }
        defaults.set(Data(Self.settingsSavedByOnePointZero.utf8), forKey: "settings")
        let (settings, outcome) = SettingsStore(defaults: defaults).load()
        #expect(outcome == .loaded)
        #expect(settings.hasCompletedWelcome)
        #expect(settings.appearance == Self.meantByOnePointZero)
        #expect(settings.appearance.shape == .full)
        #expect(settings.appearance.darkLook == nil)
    }

    @Test func aShapeAndADarkLookSurviveARoundTrip() throws {
        var appearance = Self.meantByOnePointZero
        appearance.shape = .split
        appearance.darkLook = Appearance.Look(tint: .color, color: RGBA(red: 0.1, green: 0.1, blue: 0.3), opacity: 0.8, shadow: true)
        let data = try JSONEncoder().encode(appearance)
        #expect(try JSONDecoder().decode(Appearance.self, from: data) == appearance)
    }

    /// Without a dark look nothing new is written, so the saved value stays what 1.0 wrote but for the shape.
    @Test func noDarkLookWritesNoDarkLook() throws {
        let json = String(decoding: try JSONEncoder().encode(Self.meantByOnePointZero), as: UTF8.self)
        #expect(!json.contains("darkLook"))
        #expect(json.contains(#""shape":"full""#))
    }

    @Test func anUnknownShapeIsTheFullWidth() throws {
        let appearance = try JSONDecoder().decode(Appearance.self, from: Data(#"{"tint":"color","shape":"hexagon"}"#.utf8))
        #expect(appearance.shape == .full)
        #expect(appearance.tint == .color)
    }

    @Test func anUnreadableDarkLookIsDropped() throws {
        let appearance = try JSONDecoder().decode(Appearance.self, from: Data(#"{"tint":"color","darkLook":"bright"}"#.utf8))
        #expect(appearance.darkLook == nil)
        #expect(appearance.tint == .color)
    }

    @Test func aDarkLookWithMissingFieldsTakesTheirDefaults() throws {
        let appearance = try JSONDecoder().decode(Appearance.self, from: Data(#"{"darkLook":{"tint":"gradient","opacity":0.6}}"#.utf8))
        #expect(appearance.darkLook == Appearance.Look(tint: .gradient, opacity: 0.6))
        #expect(appearance.look == .standard)
    }

    @Test func eachModeShowsItsLook() {
        let dark = Appearance.Look(tint: .color, color: RGBA(red: 0, green: 0, blue: 0.4))
        let appearance = Appearance(tint: .gradient, darkLook: dark)
        #expect(appearance.look(inDarkMode: false).tint == .gradient)
        #expect(appearance.look(inDarkMode: true) == dark)
        #expect(Appearance(tint: .gradient).look(inDarkMode: true).tint == .gradient)
    }

    @Test func aDarkLookAloneMakesTheAppearanceVisible() {
        #expect(!Appearance.standard.isVisible)
        #expect(Appearance(darkLook: Appearance.Look(tint: .color)).isVisible)
        #expect(Appearance(darkLook: Appearance.Look(border: true)).isVisible)
        #expect(!Appearance(darkLook: Appearance.Look()).isVisible)
        #expect(Appearance(tint: .color, darkLook: Appearance.Look()).isVisible)
    }

    @Test func clampingReachesTheDarkLook() {
        let appearance = Appearance(
            opacity: 3, darkLook: Appearance.Look(color: RGBA(red: 2, green: -1, blue: 0.5), opacity: -2)).clamped
        #expect(appearance.opacity == 1)
        #expect(appearance.darkLook?.opacity == 0)
        #expect(appearance.darkLook?.color == RGBA(red: 1, green: 0, blue: 0.5))
    }

    @Test func settingTheMainLookSetsTheFlatFields() {
        var appearance = Appearance.standard
        appearance.look = Appearance.Look(tint: .color, opacity: 0.7, border: true)
        #expect(appearance.tint == .color)
        #expect(appearance.opacity == 0.7)
        #expect(appearance.border)
        #expect(!appearance.shadow)
    }
}
