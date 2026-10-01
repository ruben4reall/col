import Foundation
import Observation
import ColCore

/// What the prompter's controls and overlays show. The controller writes it; SwiftUI reads it.
@MainActor
@Observable
public final class PrompterState {
    public enum Phase: Equatable {
        case idle
        case countdown(Int)
        case rolling
        case paused
        case finished
    }

    public var phase: Phase = .idle
    public var mode: ScrollMode = .voice
    public var title = ""
    public var isHovering = false
    /// Microphone level from 0 to 1.
    public var level: Float = 0
    public var isSpeaking = false
    public var elapsed: TimeInterval = 0
    public var remaining: TimeInterval = 0
    public var progress: Double = 0
    public var wordsPerMinute: Double = Pace.conversational
    /// The reader's measured pace in voice follow.
    public var measuredPace: Double?
    /// A short note, such as "Preparing the voice model…".
    public var status: String?
    public var failure: ListenerFailure?
    public var summary: TakeSummary?
    /// A value shown for a moment after a change, such as "150 wpm".
    public var flash: String?

    @ObservationIgnored var actions = Actions()

    struct Actions {
        var toggle: () -> Void = {}
        var faster: () -> Void = {}
        var slower: () -> Void = {}
        var restart: () -> Void = {}
        var close: () -> Void = {}
        var openSettings: (URL) -> Void = { _ in }
        var useAutoScroll: () -> Void = {}
        var usePace: (Double) -> Void = { _ in }
    }

    public var isRolling: Bool { phase == .rolling }
}
