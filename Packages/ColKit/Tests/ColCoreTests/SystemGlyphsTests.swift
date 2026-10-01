import Testing
@testable import ColCore

struct SystemGlyphsTests {
    @Test func volumeSymbols() {
        #expect(SystemGlyphs.volume(level: 0.5, muted: true) == "speaker.slash.fill")
        #expect(SystemGlyphs.volume(level: 0, muted: false) == "speaker.slash.fill")
        #expect(SystemGlyphs.volume(level: 0.2, muted: false) == "speaker.wave.1.fill")
        #expect(SystemGlyphs.volume(level: 0.5, muted: false) == "speaker.wave.2.fill")
        #expect(SystemGlyphs.volume(level: 1, muted: false) == "speaker.wave.3.fill")
    }

    @Test func deviceSymbols() {
        #expect(SystemGlyphs.audioDevice(name: "AirPods Pro de Ruben", transport: .bluetooth) == "airpodspro")
        #expect(SystemGlyphs.audioDevice(name: "Ruben's AirPods Max", transport: .bluetooth) == "airpodsmax")
        #expect(SystemGlyphs.audioDevice(name: "WH-1000XM5", transport: .bluetooth) == "headphones")
        #expect(SystemGlyphs.audioDevice(name: "Haut-parleurs MacBook Pro", transport: .builtIn) == "laptopcomputer")
    }

    @Test func shortNamesDropTheOwner() {
        #expect(SystemGlyphs.shortDeviceName("AirPods Pro de Ruben") == "AirPods Pro")
        #expect(SystemGlyphs.shortDeviceName("Ruben’s AirPods Pro") == "AirPods Pro")
        #expect(SystemGlyphs.shortDeviceName("WH-1000XM5") == "WH-1000XM5")
    }

    @Test func decodesMediaKeys() {
        let down = MediaKeyPress(data1: (0 << 16) | (0x0A << 8))
        #expect(down == MediaKeyPress(key: .soundUp, isDown: true, isRepeat: false))
        let repeated = MediaKeyPress(data1: (1 << 16) | (0x0A << 8) | 1)
        #expect(repeated?.key == .soundDown && repeated?.isRepeat == true)
        let up = MediaKeyPress(data1: (7 << 16) | (0x0B << 8))
        #expect(up?.key == .mute && up?.isDown == false)
        #expect(MediaKeyPress(data1: 16 << 16) == nil)
    }

    @Test func stepsLikeTheSystem() {
        #expect(LevelStep.apply(to: 0.5, up: true, fine: false) == 0.5625)
        #expect(LevelStep.apply(to: 0.51, up: true, fine: false) == 0.5625)
        #expect(LevelStep.apply(to: 1, up: true, fine: false) == 1)
        #expect(LevelStep.apply(to: 0, up: false, fine: false) == 0)
        #expect(LevelStep.apply(to: 0.5, up: false, fine: true) == 0.484375)
    }
}

extension MediaKeyPress {
    init(key: Key, isDown: Bool, isRepeat: Bool) {
        self.init(data1: (key.rawValue << 16) | ((isDown ? 0x0A : 0x0B) << 8) | (isRepeat ? 1 : 0))!
    }
}
