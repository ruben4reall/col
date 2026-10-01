/// Symbols and small rules for the system's live activities, kept here so they are tested.
public enum SystemGlyphs {
    public static func volume(level: Double, muted: Bool) -> String {
        if muted || level <= 0.001 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    public static func brightness(level: Double) -> String {
        level < 0.5 ? "sun.min.fill" : "sun.max.fill"
    }

    public enum Transport: Sendable, Equatable {
        case builtIn, bluetooth, usb, airPlay, display, other
    }

    /// A symbol for an audio output, from its name and how it is connected.
    public static func audioDevice(name: String, transport: Transport) -> String {
        let lowered = name.lowercased()
        if lowered.contains("airpods max") { return "airpodsmax" }
        if lowered.contains("airpods pro") { return "airpodspro" }
        if lowered.contains("airpods") { return "airpods" }
        if lowered.contains("beats") { return "beats.headphones" }
        if lowered.contains("homepod") { return "homepod.fill" }
        switch transport {
        case .builtIn: return "laptopcomputer"
        case .bluetooth: return "headphones"
        case .usb: return "cable.connector"
        case .airPlay: return "airplayaudio"
        case .display: return "tv"
        case .other: return "hifispeaker.fill"
        }
    }

    /// A short label for a device name, dropping the owner: "AirPods Pro de Ruben" and "Ruben's AirPods Pro" both
    /// read "AirPods Pro".
    public static func shortDeviceName(_ name: String) -> String {
        var result = name
        for separator in [" de ", " di ", " von ", " van "] {
            if let range = result.range(of: separator, options: .backwards) {
                result = String(result[..<range.lowerBound])
            }
        }
        if let range = result.range(of: "’s ") ?? result.range(of: "'s ") {
            result = String(result[range.upperBound...])
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}

/// The volume, brightness and mute keys, as macOS reports them in system-defined events.
public struct MediaKeyPress: Equatable, Sendable {
    public enum Key: Int, Sendable {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
    }

    public var key: Key
    public var isDown: Bool
    public var isRepeat: Bool

    /// Decodes `data1` of an auxiliary control button event (subtype 8). Nil for keys Col leaves alone.
    public init?(data1: Int) {
        let code = (data1 & 0xFFFF_0000) >> 16
        let flags = data1 & 0xFFFF
        guard let key = Key(rawValue: code) else { return nil }
        self.key = key
        isDown = (flags & 0xFF00) >> 8 == 0x0A
        isRepeat = flags & 0x1 == 1
    }
}

public enum LevelStep {
    /// Steps like macOS: sixteen notches, or sixty-four with Option and Shift held, snapped to the grid so repeated
    /// presses land on the same values as the system's.
    public static func apply(to level: Double, up: Bool, fine: Bool) -> Double {
        let steps = fine ? 64.0 : 16.0
        let notch = (level * steps).rounded()
        let next = up ? notch + 1 : notch - 1
        return min(max(next / steps, 0), 1)
    }
}
