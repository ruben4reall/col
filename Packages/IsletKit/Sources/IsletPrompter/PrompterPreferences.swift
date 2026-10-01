import AppKit
import IsletCore

/// How the script moves.
public enum ScrollMode: String, CaseIterable, Identifiable, Sendable {
    /// Rolls at the chosen pace while you speak, waits while you are silent. Any language, no recognition. The default.
    case pace
    /// Speech recognition keeps the place, word by word.
    case voice
    /// Rolls at a constant pace.
    case auto
    /// Moves only with the shortcuts, a clicker, the remote or the trackpad.
    case manual

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .voice: String(localized: "Voice Follow", bundle: .module)
        case .pace: String(localized: "Voice Pace", bundle: .module)
        case .auto: String(localized: "Auto Scroll", bundle: .module)
        case .manual: String(localized: "Manual", bundle: .module)
        }
    }

    public var subtitle: String {
        switch self {
        case .voice: String(localized: "Follows your words as you read.", bundle: .module)
        case .pace: String(localized: "Rolls while you speak, waits when you pause.", bundle: .module)
        case .auto: String(localized: "Rolls at a steady pace.", bundle: .module)
        case .manual: String(localized: "Moves only when you move it.", bundle: .module)
        }
    }

    public var symbol: String {
        switch self {
        case .voice: "waveform"
        case .pace: "metronome"
        case .auto: "arrow.down.to.line.compact"
        case .manual: "hand.point.up.left"
        }
    }

    /// The modes that use the microphone.
    public var listens: Bool { self == .voice || self == .pace }
}

/// Where the prompter appears.
public enum PrompterPlacement: String, CaseIterable, Identifiable, Sendable {
    case notch, floating, fullScreen
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .notch: String(localized: "Notch", bundle: .module)
        case .floating: String(localized: "Floating", bundle: .module)
        case .fullScreen: String(localized: "Full Screen", bundle: .module)
        }
    }
}

/// The colours of the text on the prompter.
public enum PrompterTheme: String, CaseIterable, Identifiable, Sendable {
    case night, paper, contrast
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .night: String(localized: "Night", bundle: .module)
        case .paper: String(localized: "Paper", bundle: .module)
        case .contrast: String(localized: "Contrast", bundle: .module)
        }
    }
}

public enum PrompterFont: String, CaseIterable, Identifiable, Sendable {
    case system, rounded, serif, mono
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "SF Pro"
        case .rounded: "SF Pro Rounded"
        case .serif: "New York"
        case .mono: "SF Mono"
        }
    }

    public func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        let design: NSFontDescriptor.SystemDesign? = switch self {
        case .system: nil
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        }
        guard let design, let descriptor = base.fontDescriptor.withDesign(design) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}

/// The light around the prompter, and the colour of the next word. By default the Mac's accent, as in Apple's apps.
public enum StageLight: String, CaseIterable, Identifiable, Sendable {
    case accent, coral, violet, ocean, ember, mint, gold, off
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accent: String(localized: "Accent Color", bundle: .module)
        case .coral: String(localized: "Coral", bundle: .module)
        case .violet: String(localized: "Violet", bundle: .module)
        case .ocean: String(localized: "Ocean", bundle: .module)
        case .ember: String(localized: "Ember", bundle: .module)
        case .mint: String(localized: "Mint", bundle: .module)
        case .gold: String(localized: "Gold", bundle: .module)
        case .off: String(localized: "Off", bundle: .module)
        }
    }

    /// The colour of the light inside the prompter and of the halo beneath it, in sRGB: saturated, like a lamp.
    var lamp: (Double, Double, Double) {
        switch self {
        case .accent: Self.systemAccent
        case .coral, .off: (1, 0.478, 0.349)
        case .violet: (0.486, 0.231, 1)
        case .ocean: (0.051, 0.435, 1)
        case .ember: (1, 0.361, 0.114)
        case .mint: (0.063, 0.796, 0.561)
        case .gold: (1, 0.690, 0.176)
        }
    }

    /// The stops of the gradient on the swatches and the level meter, in sRGB, from its start round to the same colour.
    var stops: [(Double, Double, Double)] {
        switch self {
        case .accent: Self.accentStops(Self.systemAccent)
        case .coral, .off: [(1, 0.42, 0.30), (1, 0.55, 0.42), (1, 0.78, 0.66), (0.89, 0.28, 0.18), (1, 0.55, 0.42), (1, 0.42, 0.30)]
        case .violet: [(0.431, 0.357, 1), (0.643, 0.361, 1), (1, 0.353, 0.784), (1, 0.561, 0.690), (0.643, 0.361, 1), (0.431, 0.357, 1)]
        case .ocean: [(0.184, 0.420, 1), (0.247, 0.663, 1), (0.361, 0.882, 1), (0.561, 0.608, 1), (0.247, 0.663, 1), (0.184, 0.420, 1)]
        case .ember: [(1, 0.353, 0.212), (1, 0.541, 0.239), (1, 0.757, 0.361), (1, 0.435, 0.569), (1, 0.541, 0.239), (1, 0.353, 0.212)]
        case .mint: [(0.122, 0.796, 0.561), (0.231, 0.890, 0.753), (0.612, 0.961, 0.643), (0.298, 0.784, 1), (0.231, 0.890, 0.753), (0.122, 0.796, 0.561)]
        case .gold: [(1, 0.698, 0.247), (1, 0.827, 0.420), (1, 0.945, 0.659), (1, 0.616, 0.361), (1, 0.827, 0.420), (1, 0.698, 0.247)]
        }
    }

    /// A light tint of the colour that reads well on black, for the next word and figures.
    var highlight: (Double, Double, Double) {
        switch self {
        case .accent: Self.mix(Self.systemAccent, (1, 1, 1), 0.62)
        case .coral, .off: (1, 0.80, 0.70)
        case .violet: (0.804, 0.725, 1)
        case .ocean: (0.663, 0.847, 1)
        case .ember: (1, 0.788, 0.659)
        case .mint: (0.714, 0.961, 0.855)
        case .gold: (1, 0.890, 0.639)
        }
    }
}

extension StageLight {
    /// The accent chosen in System Settings, as it shows on black, in sRGB.
    static var systemAccent: (Double, Double, Double) {
        var color = NSColor.systemBlue
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            color = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        }
        return (Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent))
    }

    /// Round the accent and back: lighter, lighter still, a little deeper, as the other lights go round their colour.
    static func accentStops(_ accent: (Double, Double, Double)) -> [(Double, Double, Double)] {
        let white = (1.0, 1.0, 1.0), black = (0.0, 0.0, 0.0)
        return [accent, mix(accent, white, 0.2), mix(accent, white, 0.5), mix(accent, black, 0.2), mix(accent, white, 0.2), accent]
    }

    static func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ amount: Double) -> (Double, Double, Double) {
        (a.0 + (b.0 - a.0) * amount, a.1 + (b.1 - a.1) * amount, a.2 + (b.2 - a.2) * amount)
    }
}

public enum MirrorMode: String, CaseIterable, Identifiable, Sendable {
    case none, horizontal, vertical, both
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .none: String(localized: "Off", bundle: .module)
        case .horizontal: String(localized: "Horizontal", bundle: .module)
        case .vertical: String(localized: "Vertical", bundle: .module)
        case .both: String(localized: "Both", bundle: .module)
        }
    }
}

/// Every setting, read from and written to the user defaults. SwiftUI reads the same keys with `@AppStorage`.
public enum PrompterPreferences {
    /// The keys in the defaults. The prompter's settings share Islet's defaults, under a prefix of their own.
    public enum Key {
        public static let mode = "prompter.scrollMode"
        public static let placement = "prompter.placement"
        public static let wordsPerMinute = "prompter.wordsPerMinute"
        public static let fontSize = "prompter.fontSize"
        public static let font = "prompter.font"
        public static let lineSpacing = "prompter.lineSpacing"
        public static let theme = "prompter.theme"
        public static let notchWidth = "prompter.notchWidth"
        public static let notchLines = "prompter.notchLines"
        public static let floatingWidth = "prompter.floatingWidth"
        public static let floatingHeight = "prompter.floatingHeight"
        public static let fullScreenDisplay = "prompter.fullScreenDisplay"
        public static let fullScreenFontSize = "prompter.fullScreenFontSize"
        public static let mirror = "prompter.mirror"
        public static let alignment = "prompter.alignment"
        public static let stageLight = "prompter.stageLight"
        public static let countdown = "prompter.countdown"
        public static let hiddenFromCapture = "prompter.hiddenFromCapture"
        public static let dimsReadWords = "prompter.dimsReadWords"
        public static let showsTimer = "prompter.showsTimer"
        public static let voiceLanguage = "prompter.voiceLanguage"
        public static let hotKeys = "prompter.hotKeys"
        public static let clickerKeys = "prompter.clickerKeys"
        public static let remoteEnabled = "prompter.remoteEnabled"
        public static let remoteToken = "prompter.remoteToken"
        public static let selectedScript = "prompter.selectedScript"
        public static let lastSummary = "prompter.lastSummary"
    }

    /// The keys Souffleur, the prompter's former app, kept the same settings under.
    static let souffleurKeys: [String: String] = [
        "scrollMode": Key.mode,
        "placement": Key.placement,
        "wordsPerMinute": Key.wordsPerMinute,
        "fontSize": Key.fontSize,
        "font": Key.font,
        "lineSpacing": Key.lineSpacing,
        "theme": Key.theme,
        "notchWidth": Key.notchWidth,
        "notchLines": Key.notchLines,
        "floatingWidth": Key.floatingWidth,
        "floatingHeight": Key.floatingHeight,
        "fullScreenDisplay": Key.fullScreenDisplay,
        "fullScreenFontSize": Key.fullScreenFontSize,
        "mirror": Key.mirror,
        "alignment": Key.alignment,
        "stageLight": Key.stageLight,
        "countdown": Key.countdown,
        "hiddenFromCapture": Key.hiddenFromCapture,
        "dimsReadWords": Key.dimsReadWords,
        "showsTimer": Key.showsTimer,
        "voiceLanguage": Key.voiceLanguage,
        "hotKeys": Key.hotKeys,
        "clickerKeys": Key.clickerKeys,
        "remoteEnabled": Key.remoteEnabled,
        "remoteToken": Key.remoteToken,
        "selectedScript": Key.selectedScript,
        "lastSummary": Key.lastSummary,
    ]

    nonisolated(unsafe) public static let defaults: [String: Any] = [
        Key.mode: ScrollMode.pace.rawValue,
        Key.placement: PrompterPlacement.notch.rawValue,
        Key.wordsPerMinute: Pace.conversational,
        Key.fontSize: 21.0,
        Key.font: PrompterFont.system.rawValue,
        Key.lineSpacing: 1.4,
        Key.theme: PrompterTheme.night.rawValue,
        Key.notchWidth: 400.0,
        Key.notchLines: 4.0,
        Key.floatingWidth: 520.0,
        Key.floatingHeight: 200.0,
        Key.fullScreenFontSize: 64.0,
        Key.mirror: MirrorMode.none.rawValue,
        Key.alignment: "center",
        Key.stageLight: StageLight.accent.rawValue,
        Key.countdown: true,
        Key.hiddenFromCapture: true,
        Key.dimsReadWords: true,
        Key.showsTimer: true,
        Key.voiceLanguage: "auto",
        Key.hotKeys: true,
        Key.clickerKeys: true,
        Key.remoteEnabled: false,
    ]

    public static func register() {
        UserDefaults.standard.register(defaults: defaults)
        adoptSouffleurSettings()
    }

    /// The prompter was an app of its own, Souffleur. The first time Islet runs it, the settings made there carry over
    /// (pace, mode, light, text, shortcuts, the phone remote's pairing), unless the same setting was already made here.
    static func adoptSouffleurSettings() {
        let flag = "prompter.adoptedSouffleurSettings"
        guard !store.bool(forKey: flag) else { return }
        store.set(true, forKey: flag)
        let souffleur = UserDefaults.standard.persistentDomain(forName: "ch.rubencatalao.souffleur") ?? [:]
        let own = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        for (old, new) in souffleurKeys where own[new] == nil {
            if let value = souffleur[old] { store.set(value, forKey: new) }
        }
    }

    private static var store: UserDefaults { .standard }

    public static var mode: ScrollMode {
        get { ScrollMode(rawValue: store.string(forKey: Key.mode) ?? "") ?? .pace }
        set { store.set(newValue.rawValue, forKey: Key.mode) }
    }

    public static var placement: PrompterPlacement {
        get { PrompterPlacement(rawValue: store.string(forKey: Key.placement) ?? "") ?? .notch }
        set { store.set(newValue.rawValue, forKey: Key.placement) }
    }

    public static var wordsPerMinute: Double {
        get { min(max(store.double(forKey: Key.wordsPerMinute), minimumPace), maximumPace) }
        set { store.set(min(max(newValue, minimumPace), maximumPace), forKey: Key.wordsPerMinute) }
    }

    public static let minimumPace: Double = 60
    public static let maximumPace: Double = 260

    public static var fontSize: CGFloat { CGFloat(store.double(forKey: Key.fontSize)) }
    public static var fullScreenFontSize: CGFloat { CGFloat(store.double(forKey: Key.fullScreenFontSize)) }
    public static var font: PrompterFont { PrompterFont(rawValue: store.string(forKey: Key.font) ?? "") ?? .system }
    public static var lineSpacing: CGFloat { CGFloat(store.double(forKey: Key.lineSpacing)) }
    public static var theme: PrompterTheme { PrompterTheme(rawValue: store.string(forKey: Key.theme) ?? "") ?? .night }
    public static var notchWidth: CGFloat { CGFloat(store.double(forKey: Key.notchWidth)) }
    public static var notchLines: Int { max(2, min(8, store.integer(forKey: Key.notchLines))) }
    public static var floatingSize: CGSize {
        CGSize(width: store.double(forKey: Key.floatingWidth), height: store.double(forKey: Key.floatingHeight))
    }
    public static var fullScreenDisplay: String? { store.string(forKey: Key.fullScreenDisplay) }
    public static var mirror: MirrorMode { MirrorMode(rawValue: store.string(forKey: Key.mirror) ?? "") ?? .none }
    public static var stageLight: StageLight { StageLight(rawValue: store.string(forKey: Key.stageLight) ?? "") ?? .accent }
    public static var countdown: Bool { store.bool(forKey: Key.countdown) }
    /// Centred text keeps the eyes under the camera; left-aligned reads like a page.
    public static var centersText: Bool { store.string(forKey: Key.alignment) != "left" }
    public static var hiddenFromCapture: Bool { store.bool(forKey: Key.hiddenFromCapture) }
    public static var dimsReadWords: Bool { store.bool(forKey: Key.dimsReadWords) }
    public static var showsTimer: Bool { store.bool(forKey: Key.showsTimer) }
    /// A BCP 47 identifier, or "auto" to use the language the script is written in.
    public static var voiceLanguage: String { store.string(forKey: Key.voiceLanguage) ?? "auto" }
    public static var hotKeys: Bool { store.bool(forKey: Key.hotKeys) }
    public static var clickerKeys: Bool { store.bool(forKey: Key.clickerKeys) }
    public static var remoteEnabled: Bool {
        get { store.bool(forKey: Key.remoteEnabled) }
        set { store.set(newValue, forKey: Key.remoteEnabled) }
    }

    /// The remote's pairing secret, made once and kept until the user asks for a new one.
    public static var remoteToken: String {
        if let token = store.string(forKey: Key.remoteToken), token.count == 12 { return token }
        let token = RemoteToken.make()
        store.set(token, forKey: Key.remoteToken)
        return token
    }

    public static func renewRemoteToken() {
        store.set(RemoteToken.make(), forKey: Key.remoteToken)
    }
}
