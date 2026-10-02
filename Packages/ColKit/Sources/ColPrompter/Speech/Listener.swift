@preconcurrency import AVFoundation
import Foundation
import NaturalLanguage
@preconcurrency import Speech

/// What the listener reports, always on the main queue.
public enum ListenerEvent: Sendable {
    /// Microphone level from 0 to 1, and whether it sounds like speech.
    case level(Float, speaking: Bool)
    /// The latest words heard, most recent last; `final` holds a finished sentence the first time it is reported.
    case heard(String, final: String?)
    /// Something the reader should know while the listener gets ready, such as a voice model being prepared.
    case status(String?)
    case failed(ListenerFailure)
}

public enum ListenerFailure: Error, Sendable, Equatable {
    case microphoneDenied
    case speechDenied
    case languageUnsupported(String)
    case microphoneUnavailable
    /// The recogniser kept failing; the listener carries on with the level only.
    case recognitionStopped

    public var message: String {
        switch self {
        case .microphoneDenied: String(localized: "Col can't hear you: microphone access is off.", bundle: .module)
        case .speechDenied: String(localized: "Speech recognition is off for Col.", bundle: .module)
        case .languageUnsupported(let name): String(localized: "Voice follow can't hear \(name) on this Mac yet. Rolling at your pace instead.", bundle: .module)
        case .microphoneUnavailable: String(localized: "No microphone is available.", bundle: .module)
        case .recognitionStopped: String(localized: "Voice follow stopped hearing words. Rolling at your pace instead.", bundle: .module)
        }
    }

    /// The System Settings pane that fixes it, if any.
    public var settingsURL: URL? {
        switch self {
        case .microphoneDenied: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speechDenied: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        default: nil
        }
    }

    /// Failures after which the take goes on at the reader's pace, the microphone still listening for the level.
    public var fallsBackToPace: Bool {
        switch self {
        case .languageUnsupported, .recognitionStopped: true
        default: false
        }
    }
}

/// Listens to the microphone while a take runs: the level for voice pace and the meter, and, for voice follow, the
/// words recognised on this Mac. Nothing runs while the prompter is closed.
///
/// Every start is a numbered session: a stop, or a newer start, while an older one still waits for a permission or a
/// voice model makes that older one give up, so the microphone never stays open after the prompter has closed.
@MainActor
public final class Listener {
    private let engine = AVAudioEngine()
    private let tap = Tap()
    private var session = 0
    private var isRunning = false
    private var configuration: NSObjectProtocol?

    public init() {}

    /// Starts listening. With `recognize`, words are recognised in `locale`, helped by the script's vocabulary; if
    /// they cannot be, the failure is reported and the level keeps coming.
    public func start(recognize: Bool, locale: Locale, vocabulary: [String], onEvent: @escaping @Sendable (ListenerEvent) -> Void) async {
        stop()
        session += 1
        let current = session
        tap.handler = onEvent
        guard await Permissions.microphone() else { return tap.report(.failed(.microphoneDenied)) }
        guard current == session else { return }
        if recognize {
            guard await Permissions.speech() else { return tap.report(.failed(.speechDenied)) }
            guard current == session else { return }
            do {
                let recognition = try await RecognitionEngine.make(locale: locale, vocabulary: vocabulary, report: tap.report)
                guard current == session else { return recognition.stop() }
                tap.recognizer = recognition
            } catch {
                guard current == session else { return }
                let name = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
                tap.report(.failed(.languageUnsupported(name)))
            }
        }
        guard startEngine() else { return tap.report(.failed(.microphoneUnavailable)) }
        // A microphone plugged in or AirPods connecting change the input: listen again on the new one.
        configuration = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                self.stopEngine()
                if !self.startEngine() { self.tap.report(.failed(.microphoneUnavailable)) }
            }
        }
    }

    /// Stops everything, including a start still waiting.
    public func stop() {
        session += 1
        if let configuration { NotificationCenter.default.removeObserver(configuration) }
        configuration = nil
        stopEngine()
        dropRecognition()
        tap.handler = nil
    }

    /// Stops recognising words but keeps the level coming, for voice pace.
    public func dropRecognition() {
        let recognition = tap.recognizer
        tap.recognizer = nil
        recognition?.stop()
    }

    private func startEngine() -> Bool {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        input.removeTap(onBus: 0)
        let tap = self.tap
        // The audio thread calls this block: it must not belong to the main actor, or Swift's isolation check stops the
        // app on the first buffer. It only hands the buffer to the tap, which is safe to use from any thread.
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in tap.process(buffer) }
        engine.prepare()
        do {
            try engine.start()
            isRunning = true
            return true
        } catch {
            input.removeTap(onBus: 0)
            return false
        }
    }

    private func stopEngine() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    /// The language to listen in: the one chosen in Settings, or the one the script is written in.
    public nonisolated static func locale(for text: String, preference: String) -> Locale {
        if preference != "auto" { return Locale(identifier: preference) }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(4000)))
        guard let language = recognizer.dominantLanguage?.rawValue else { return Locale.current }
        // Keep the user's region when it goes with that language (fr_CH for a French script in Switzerland).
        if Locale.current.language.languageCode?.identifier == language { return Locale.current }
        return Locale(identifier: language)
    }

    /// The distinct words of the script, longest first, for the recogniser's contextual vocabulary.
    public nonisolated static func vocabulary(of words: [String], limit: Int = 100) -> [String] {
        var seen = Set<String>()
        let unique = words.filter { $0.count > 3 && seen.insert($0.lowercased()).inserted }
        return Array(unique.sorted { $0.count > $1.count }.prefix(limit))
    }
}

/// What the audio thread needs, behind a lock: where to send events, the recogniser, and the voice activity state.
private final class Tap: @unchecked Sendable {
    private let lock = NSLock()
    private var _handler: (@Sendable (ListenerEvent) -> Void)?
    private var _recognizer: RecognitionEngine?
    // Voice activity: an adaptive noise floor, and speech when the level stays well above it. Audio thread only.
    private var noiseFloor: Float = -50
    private var lastVoice: TimeInterval = 0
    private var lastLevelReport: TimeInterval = 0

    var handler: (@Sendable (ListenerEvent) -> Void)? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    var recognizer: RecognitionEngine? {
        get { lock.withLock { _recognizer } }
        set { lock.withLock { _recognizer = newValue } }
    }

    /// Sends an event to the main queue, to the handler of the moment it arrives there.
    var report: @Sendable (ListenerEvent) -> Void {
        { [weak self] event in
            DispatchQueue.main.async { self?.handler?(event) }
        }
    }

    /// On the audio thread: the buffer for the recogniser, the level and voice activity.
    func process(_ buffer: AVAudioPCMBuffer) {
        recognizer?.append(buffer)
        guard let samples = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var sum: Float = 0
        for index in 0..<count { sum += samples[index] * samples[index] }
        let rms = sqrt(sum / Float(count))
        let decibels = 20 * log10(max(rms, 0.000_01))
        let now = ProcessInfo.processInfo.systemUptime
        // The floor follows quiet moments quickly and loud ones slowly, so speech never becomes the floor.
        noiseFloor = decibels < noiseFloor ? noiseFloor * 0.9 + decibels * 0.1 : noiseFloor * 0.998 + decibels * 0.002
        noiseFloor = min(max(noiseFloor, -80), -30)
        if decibels > noiseFloor + 12, decibels > -52 { lastVoice = now }
        let speaking = now - lastVoice < 0.45
        guard now - lastLevelReport > 1.0 / 20 else { return }
        lastLevelReport = now
        report(.level(min(max((decibels + 60) / 50, 0), 1), speaking: speaking))
    }
}

enum Permissions {
    static func microphone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    static func speech() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }
}
