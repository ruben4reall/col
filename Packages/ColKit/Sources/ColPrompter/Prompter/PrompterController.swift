import AppKit
import ColCore

/// Runs a take: puts the prompter on screen, counts down, listens, keeps the place and rolls the text, then shows
/// how it went. Nothing runs while no take is on.
@MainActor
public final class PrompterController {
    public let state = PrompterState()
    /// Called whenever what the remote or the menus show may have changed.
    public var onChange: (() -> Void)?

    private var presentation: PrompterPresentation? {
        // Observed, unlike the presentation: views that show a take or a script switch as the take starts and ends.
        didSet { state.isActive = presentation != nil }
    }
    /// Where the take on screen is.
    public private(set) var placement: PrompterPlacement = .notch
    private(set) var script = Script("")
    private var sourceText = ""
    private var tracker: VoiceTracker?
    private let listener = Listener()
    private var isListening = false
    private var recorder: TakeRecorder?
    private var meter = PaceMeter()
    private var clock: Timer?
    private var rollingSince: Date?
    private var elapsedBefore: TimeInterval = 0
    private var countdown: Task<Void, Never>?
    private var autoClose: Task<Void, Never>?
    /// The end of the script has reached the camera: the take ends after a moment, once.
    private var finishing: Task<Void, Never>?
    private var flashReset: Task<Void, Never>?
    private var lastOffsetReport: CFTimeInterval = 0
    private var observers: [NSObjectProtocol] = []
    /// Reads the script from a scripted transcript instead of the microphone, for screenshots and demos.
    public var demoVoice = false
    /// With `demoVoice`, the word at which the scripted reading stops.
    public var demoStop: Int?
    /// A place for the next takes that leaves the user's setting alone, for demos.
    public var placementOverride: PrompterPlacement?
    /// Shows the prompter without its text, for a picture of the empty prompter.
    public var demoBlank = false
    private var demoTask: Task<Void, Never>?

    public init() {
        state.actions = .init(
            toggle: { [weak self] in self?.toggle() },
            faster: { [weak self] in self?.faster() },
            slower: { [weak self] in self?.slower() },
            restart: { [weak self] in self?.restart() },
            close: { [weak self] in self?.stop() },
            openSettings: { NSWorkspace.shared.open($0) },
            useAutoScroll: { [weak self] in self?.switchMode(.auto) },
            usePace: { [weak self] in self?.usePace($0) }
        )
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
    }

    public var isActive: Bool { state.isActive }
    public var isRolling: Bool { state.phase == .rolling }

    // MARK: Starting and stopping

    /// Opens the prompter on a script and starts a take.
    public func start(text: String, title: String) {
        let script = Script(text)
        guard !script.isEmpty else { return }
        if presentation != nil { tearDown(animated: false) }
        self.script = script
        sourceText = text
        placement = placementOverride ?? PrompterPreferences.placement
        state.title = title
        state.mode = PrompterPreferences.mode
        state.wordsPerMinute = PrompterPreferences.wordsPerMinute
        resetTake()

        let presentation: PrompterPresentation = switch placement {
        case .notch: NotchPresentation(state: state)
        case .floating: CardPresentation(state: state, fullScreen: false)
        case .fullScreen: {
            let card = CardPresentation(state: state, fullScreen: true)
            card.onKey = { [weak self] event in self?.handleKey(event) ?? false }
            return card
        }()
        }
        self.presentation = presentation
        presentation.refresh()
        wire(presentation.text)
        presentation.text.load(script, style: PrompterStyle.current(fullScreen: placement == .fullScreen, notch: placement == .notch))
        presentation.text.isHidden = demoBlank
        markVoicePlace()
        presentation.present()
        Neighbours.post(Neighbours.didOpen, placement: placement)
        beginAfterCountdown()
        onChange?()
    }

    /// Closes the prompter and ends the take.
    public func stop() {
        tearDown(animated: true)
    }

    private func tearDown(animated: Bool) {
        countdown?.cancel()
        autoClose?.cancel()
        cancelFinishing()
        stopListening()
        stopClock()
        tracker = nil
        let closing = presentation
        presentation = nil
        state.phase = .idle
        state.isHovering = false
        if animated {
            closing?.dismiss {}
        } else {
            closing?.closeNow()
        }
        if closing != nil { Neighbours.post(Neighbours.didClose) }
        onChange?()
    }

    private func resetTake() {
        cancelFinishing()
        state.phase = .idle
        state.summary = nil
        state.failure = nil
        state.status = nil
        state.progress = 0
        state.elapsed = 0
        state.measuredPace = nil
        state.remaining = Pace.readingTime(words: script.words.count, wordsPerMinute: state.wordsPerMinute)
        elapsedBefore = 0
        rollingSince = nil
        meter.reset()
        tracker = state.mode == .voice ? VoiceTracker(script: script, locale: voiceLocale) : nil
    }

    private var voiceLocale: Locale { Listener.locale(for: script.display, preference: PrompterPreferences.voiceLanguage) }

    private func beginAfterCountdown() {
        countdown?.cancel()
        // The recogniser gets ready during the countdown, so the first words are heard.
        if state.mode.listens, !(state.mode == .voice && demoVoice) { startListening(recognize: state.mode == .voice) }
        guard PrompterPreferences.countdown else { return begin() }
        presentation?.glow(1)
        countdown = Task { [weak self] in
            for number in [3, 2, 1] {
                self?.state.phase = .countdown(number)
                try? await Task.sleep(for: .milliseconds(750))
                if Task.isCancelled { return }
            }
            self?.begin()
        }
    }

    private func begin() {
        countdown?.cancel()
        countdown = nil
        state.phase = .rolling
        rollingSince = Date()
        updateGlow()
        recorder = TakeRecorder(totalWords: script.words.count, start: Date())
        startClock()
        switch state.mode {
        case .voice: if demoVoice { readDemo() } else if !isListening { startListening(recognize: true) }
        case .pace: if !isListening { startListening(recognize: false) }
        case .auto: presentation?.text.setSpeed(autoSpeed, eased: true)
        case .manual: break
        }
        onChange?()
    }

    /// Feeds the tracker the script's own words at a steady 150 words a minute, through the same path as the
    /// recogniser.
    private func readDemo() {
        demoTask?.cancel()
        let words = script.words.map(\.text)
        demoTask = Task { [weak self] in
            var heard: [String] = []
            for (index, word) in words.enumerated() {
                if let stop = self?.demoStop, index >= stop { break }
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, !Task.isCancelled else { return }
                heard.append(word)
                self.state.level = Float.random(in: 0.45...0.85)
                self.state.isSpeaking = true
                self.updateGlow()
                self.heard(heard.suffix(10).joined(separator: " "), final: nil)
            }
        }
    }

    // MARK: Controls

    public func toggle() {
        switch state.phase {
        case .idle: break
        case .countdown: begin()
        case .rolling: pause()
        case .paused: resume()
        case .finished: restart()
        }
    }

    public func pause() {
        guard state.phase == .rolling else { return }
        cancelFinishing()
        state.phase = .paused
        if let rollingSince { elapsedBefore += Date().timeIntervalSince(rollingSince) }
        rollingSince = nil
        presentation?.text.setSpeed(0, eased: true)
        updateGlow()
        onChange?()
    }

    public func resume() {
        guard state.phase == .paused else { return }
        state.phase = .rolling
        rollingSince = Date()
        if state.mode == .auto { presentation?.text.setSpeed(autoSpeed, eased: true) }
        updateGlow()
        onChange?()
    }

    /// The stage light: the resting light while the script rolls, a little brighter as the voice rises and a little
    /// lower in a silence while listening, low when paused.
    private func updateGlow() {
        let intensity: CGFloat = switch state.phase {
        case .idle: 0
        case .countdown, .finished: 1
        case .paused: 0.45
        case .rolling:
            state.mode.listens
                ? (state.isSpeaking ? 0.9 + 0.4 * min(1, CGFloat(state.level) * 1.4) : 0.75)
                : 1
        }
        presentation?.glow(intensity)
    }

    public func restart() {
        guard let presentation else { return }
        autoClose?.cancel()
        stopListening()
        stopClock()
        presentation.text.halt()
        resetTake()
        presentation.text.setOffset(0)
        markVoicePlace()
        beginAfterCountdown()
        onChange?()
    }

    /// The speed slider moved: a take rolling at a steady pace follows it at once.
    public func paceChanged() {
        guard PrompterPreferences.wordsPerMinute != state.wordsPerMinute else { return }
        state.wordsPerMinute = PrompterPreferences.wordsPerMinute
        if state.phase == .rolling, state.mode == .auto { presentation?.text.setSpeed(autoSpeed, eased: true) }
        onChange?()
    }

    /// Rolls the script at the pace the reader just read at, from now on.
    private func usePace(_ pace: Double) {
        PrompterPreferences.wordsPerMinute = pace
        state.wordsPerMinute = PrompterPreferences.wordsPerMinute
        flash(String(localized: "Speed set to \(Int(state.wordsPerMinute)) words a minute", bundle: .module))
        onChange?()
    }

    public func faster() { changePace(by: 10) }
    public func slower() { changePace(by: -10) }

    private func changePace(by step: Double) {
        PrompterPreferences.wordsPerMinute += step
        state.wordsPerMinute = PrompterPreferences.wordsPerMinute
        if state.phase == .rolling, state.mode == .auto { presentation?.text.setSpeed(autoSpeed, eased: true) }
        flash("\(Int(state.wordsPerMinute)) wpm")
        onChange?()
    }

    /// Moves one line back or forward.
    public func moveLine(_ direction: Int) {
        guard let text = presentation?.text else { return }
        let target = text.offset + CGFloat(direction) * text.style.lineHeight
        if state.mode == .voice, var tracker {
            tracker.jump(toWord: text.word(atOffset: max(0, target)))
            self.tracker = tracker
            markVoicePlace(glide: true)
        } else {
            text.glide(to: target)
        }
    }

    /// Switches the running take to another mode, such as auto scroll when the microphone is off.
    public func switchMode(_ mode: ScrollMode) {
        state.failure = nil
        stopListening()
        state.mode = mode
        tracker = mode == .voice ? VoiceTracker(script: script, locale: voiceLocale) : nil
        if let text = presentation?.text, var tracker {
            tracker.jump(toWord: text.word(atOffset: text.offset))
            self.tracker = tracker
        }
        if state.phase == .rolling {
            switch mode {
            case .voice: startListening(recognize: true)
            case .pace: startListening(recognize: false)
            case .auto: presentation?.text.setSpeed(autoSpeed, eased: true)
            case .manual: presentation?.text.setSpeed(0, eased: true)
            }
        }
        onChange?()
    }

    /// The rolling speed: the whole script, blank space between paragraphs included, in its reading time.
    private var autoSpeed: CGFloat {
        guard let text = presentation?.text else { return 0 }
        let speed = Pace.pointsPerSecond(toScroll: text.endOffset, words: script.words.count, wordsOnLastLine: text.wordsPerLine, wordsPerMinute: state.wordsPerMinute)
        return speed > 0 ? speed : Pace.pointsPerSecond(wordsPerMinute: state.wordsPerMinute, wordsPerLine: text.wordsPerLine, lineHeight: text.style.lineHeight)
    }

    private func flash(_ text: String) {
        state.flash = text
        flashReset?.cancel()
        flashReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { self?.state.flash = nil }
        }
    }

    /// Keys of the full screen prompter.
    private func handleKey(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case 49: toggle()                       // Space
        case 53: stop()                         // Escape
        case 126: faster()                      // Up
        case 125: slower()                      // Down
        case 123, 116: moveLine(-1)             // Left, Page Up
        case 124, 121: moveLine(1)              // Right, Page Down
        case 15: restart()                      // R
        default: return false
        }
        return true
    }

    // MARK: The text

    private func wire(_ text: ScriptTextView) {
        text.onClick = { [weak self] in self?.toggle() }
        text.onNudge = { [weak self, weak text] delta in
            guard let self, let text else { return }
            text.setOffset(text.offset + delta)
            if self.state.mode != .voice { self.offsetChanged(text.offset, force: true) }
        }
        text.onNudgeEnded = { [weak self, weak text] in
            guard let self, let text, self.state.mode == .voice, var tracker = self.tracker else { return }
            tracker.jump(toWord: text.word(atOffset: text.offset))
            self.tracker = tracker
            self.markVoicePlace()
        }
        text.onOffsetChanged = { [weak self] offset in self?.offsetChanged(offset, force: false) }
        text.onSettled = { [weak self] in
            guard let self, self.state.mode == .auto || self.state.mode == .pace, self.state.phase == .rolling else { return }
            // The last line has just reached the reading line: give the reader the time to say it.
            let words = max(4.0, self.presentation?.text.wordsPerLine ?? 8)
            self.finishSoon(after: min(6, max(1.5, words / max(self.state.wordsPerMinute, 60) * 60)))
        }
    }

    /// Auto scroll, voice pace and manual: the place follows the text on the reading line.
    private func offsetChanged(_ offset: CGFloat, force: Bool) {
        guard state.mode != .voice, let text = presentation?.text else { return }
        let now = CACurrentMediaTime()
        guard force || now - lastOffsetReport > 0.1 else { return }
        lastOffsetReport = now
        let lineStart = text.character(atOffset: offset)
        text.mark(readUpTo: lineStart, next: nil)
        let index = text.word(atOffset: offset)
        recorder?.record(wordIndex: index, at: Date())
        let end = text.endOffset
        state.progress = end > 0 ? Double(offset / end) : 0
        state.remaining = Pace.readingTime(words: script.words.count - index, wordsPerMinute: state.wordsPerMinute)
        onChange?()
    }

    /// Voice follow: colours the words read and the next one, and moves the text to the line being read.
    private func markVoicePlace(glide: Bool = false) {
        guard let text = presentation?.text else { return }
        guard state.mode == .voice, let tracker else {
            text.mark(readUpTo: 0, next: nil)
            return
        }
        let index = tracker.wordIndex
        let words = script.words
        let readEnd = index < words.count ? words[index].range.location : script.display.utf16.count
        text.mark(readUpTo: readEnd, next: index < words.count ? words[index].range : nil)
        if glide { text.glide(to: text.offset(forWord: index)) }
        state.progress = words.isEmpty ? 0 : Double(index) / Double(words.count)
    }

    private func heard(_ recent: String, final: String?) {
        if let final { recorder?.heard(final) }
        guard state.phase == .rolling, state.mode == .voice, var tracker else { return }
        guard tracker.hear(recent) else { return }
        self.tracker = tracker
        let now = Date()
        meter.record(wordIndex: tracker.wordIndex, at: now)
        recorder?.record(wordIndex: tracker.wordIndex, at: now)
        state.measuredPace = meter.wordsPerMinute
        state.remaining = Pace.readingTime(words: script.words.count - tracker.wordIndex, wordsPerMinute: state.measuredPace ?? state.wordsPerMinute)
        markVoicePlace(glide: true)
        onChange?()
        if tracker.isFinished {
            // Let the last word land before the summary.
            finishSoon(after: 1.2)
        }
    }

    /// Ends the take after `wait` seconds, unless it is already about to end, or is paused, restarted or closed first.
    private func finishSoon(after wait: TimeInterval) {
        guard finishing == nil else { return }
        finishing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard let self, !Task.isCancelled else { return }
            self.finishing = nil
            if self.state.phase == .rolling { self.finish() }
        }
    }

    private func cancelFinishing() {
        finishing?.cancel()
        finishing = nil
    }

    private func finish() {
        guard state.phase == .rolling || state.phase == .paused else { return }
        cancelFinishing()
        // Rolling to the end reads the last line too: the coach counts the whole script.
        if state.mode != .voice, let text = presentation?.text, text.offset >= text.endOffset - 1 {
            recorder?.record(wordIndex: script.words.count, at: Date())
        }
        if let rollingSince { elapsedBefore += Date().timeIntervalSince(rollingSince) }
        rollingSince = nil
        state.elapsed = elapsedBefore
        stopListening()
        stopClock()
        presentation?.text.setSpeed(0, eased: false)
        if let recorder {
            var summary = recorder.finish(at: Date())
            summary.duration = elapsedBefore
            state.summary = summary
            UserDefaults.standard.set(
                "\(Pace.clock(summary.duration)) · \(Int(summary.averageWordsPerMinute.rounded())) wpm · \(Int((summary.coverage * 100).rounded()))%",
                forKey: PrompterPreferences.Key.lastSummary
            )
        }
        state.phase = .finished
        state.progress = 1
        state.remaining = 0
        updateGlow()
        onChange?()
        autoClose = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, !Task.isCancelled, self.state.phase == .finished, !self.state.isHovering else { return }
            self.stop()
        }
    }

    // MARK: Listening

    private func startListening(recognize: Bool) {
        stopListening()
        isListening = true
        let locale = voiceLocale
        let vocabulary = Listener.vocabulary(of: script.words.map(\.text))
        let listener = self.listener
        Task { [weak self] in
            await listener.start(recognize: recognize, locale: locale, vocabulary: vocabulary) { event in
                MainActor.assumeIsolated { self?.handle(event) }
            }
        }
    }

    private func stopListening() {
        demoTask?.cancel()
        demoTask = nil
        guard isListening else { return }
        isListening = false
        listener.stop()
        state.level = 0
        state.isSpeaking = false
    }

    private func handle(_ event: ListenerEvent) {
        guard isListening else { return }
        switch event {
        case .level(let level, let speaking):
            state.level = level
            state.isSpeaking = speaking
            updateGlow()
            if state.mode == .pace, state.phase == .rolling {
                presentation?.text.setSpeed(speaking ? autoSpeed : 0, eased: true)
            }
        case .heard(let recent, let final):
            heard(recent, final: final)
        case .status(let status):
            state.status = status
        case .failed(let failure):
            if failure.fallsBackToPace {
                // The microphone keeps listening for the level: only the words are gone.
                listener.dropRecognition()
                tracker = nil
                state.mode = .pace
                flash(failure.message)
                onChange?()
            } else {
                state.failure = failure
                stopListening()
            }
        }
    }

    // MARK: Time

    private func startClock() {
        stopClock()
        clock = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopClock() {
        clock?.invalidate()
        clock = nil
    }

    private func tick() {
        state.elapsed = elapsedBefore + (rollingSince.map { Date().timeIntervalSince($0) } ?? 0)
        onChange?()
    }

    private func screensChanged() {
        guard let presentation else { return }
        let text = presentation.text
        let word = text.word(atOffset: text.offset)
        presentation.refresh()
        text.load(script, style: PrompterStyle.current(fullScreen: placement == .fullScreen, notch: placement == .notch))
        text.setOffset(text.offset(forWord: word))
        markVoicePlace()
    }

    /// The line under the camera, for the remote.
    public var currentLine: String { presentation?.text.currentLine() ?? "" }
}

/// Tells other apps, notch apps first, when the prompter opens and closes, so they can step aside while it is open:
/// two distributed notifications that carry nothing but the placement.
public enum Neighbours {
    public static let didOpen = Notification.Name("ch.rubencatalao.islet.prompterDidOpen")
    public static let didClose = Notification.Name("ch.rubencatalao.islet.prompterDidClose")

    static func post(_ name: Notification.Name, placement: PrompterPlacement? = nil) {
        DistributedNotificationCenter.default().postNotificationName(
            name, object: nil, userInfo: placement.map { ["placement": $0.rawValue] }, deliverImmediately: true)
    }
}
