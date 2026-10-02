import AppKit
import Testing
@testable import ColPrompter

@MainActor
struct GlowViewTests {
    @Test func aSteadyLightAddsNoAnimation() throws {
        let glow = GlowView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let layer = try #require(glow.layer)
        glow.setIntensity(0.45)
        let fade = try #require(layer.animation(forKey: "opacity"))
        // The level of a paused take arrives 20 times a second with the same light: nothing new is animated.
        glow.setIntensity(0.45)
        #expect(layer.animation(forKey: "opacity") === fade)
        // A change of light still eases to it.
        glow.setIntensity(0.9)
        #expect(layer.animation(forKey: "opacity") !== fade)
        #expect(layer.opacity == Float(0.9 / GlowView.ceiling))
    }

    @Test func anImmediateChangeAlwaysApplies() throws {
        let glow = GlowView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let layer = try #require(glow.layer)
        glow.setIntensity(1)
        glow.setIntensity(0, duration: 0.15)
        let fading = try #require(layer.animation(forKey: "opacity"))
        // Closing at once cuts a fade already on its way to the same light.
        glow.setIntensity(0, duration: 0)
        #expect(layer.animation(forKey: "opacity") !== fading)
        #expect(layer.opacity == 0)
    }
}
