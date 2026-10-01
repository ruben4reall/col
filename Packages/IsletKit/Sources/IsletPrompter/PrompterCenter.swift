import AppKit
import Carbon.HIToolbox
import Observation
import IsletCore
import SwiftUI

/// The prompter: the library of scripts, the prompter itself, and every way to drive it (shortcuts, clicker keys, the
/// phone remote, links and Shortcuts actions). Islet starts it, shows its windows and steps aside while it is in the
/// notch.
@MainActor
@Observable
public final class PrompterCenter {
    public static let shared = PrompterCenter()

    public let store: ScriptStore
    public let prompter = PrompterController()
    public let remote = RemoteServer()
    /// Bumped when the remote's status changes, so SwiftUI redraws the Remote settings.
    public private(set) var remoteRevision = 0
    /// Shortcuts another app already holds, as they read ("⌃⌥⌘P").
    public private(set) var takenShortcuts: [String] = []

    @ObservationIgnored private var hotKeys: HotKeys?
    @ObservationIgnored private var mainKeys: [UInt32] = []
    @ObservationIgnored private var clickerKeys: [UInt32] = []
    /// The scroll mode last chosen in the window or in Settings: choosing another applies to the take on screen at
    /// once. A take that falls back on its own (no voice model) keeps its fallback until the next choice.
    @ObservationIgnored private var chosenMode = PrompterPreferences.mode
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    /// Opens the library window, which belongs to the app.
    @ObservationIgnored public var showLibraryHandler: (() -> Void)?
    /// Called when the prompter opens (true) or closes (false), with where it is, so the island can step aside.
    @ObservationIgnored public var onActiveChange: ((_ active: Bool, _ placement: PrompterPlacement) -> Void)?
    @ObservationIgnored private var wasActive = false

    private init() {
        PrompterPreferences.register()
        store = ScriptStore()
    }

    /// Called once at launch.
    public func start() {
        hotKeys = HotKeys()
        prompter.onChange = { [weak self] in self?.prompterChanged() }
        remote.onCommand = { [weak self] command in self?.perform(command) }
        remote.state = { [weak self] in self?.remoteState() ?? .idle() }
        remote.onStatusChange = { [weak self] in self?.remoteRevision += 1 }
        applyPreferences()
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyPreferences() }
        }
    }

    public func willTerminate() {
        store.flush()
        prompter.stop()
        remote.stop()
    }

    // MARK: Prompting

    /// Opens the prompter on the selected script.
    public func promptSelected() {
        guard let document = store.selected else { return }
        prompt(document)
    }

    public func prompt(_ document: ScriptDocument) {
        store.flush()
        prompter.start(text: document.text, title: document.title)
    }

    public func prompt(text: String, title: String? = nil) {
        let heading = title ?? String(text.split(separator: "\n").first ?? "").trimmingCharacters(in: .whitespaces)
        prompter.start(text: text, title: heading)
    }

    /// Prompts whatever text is on the clipboard.
    public func promptClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            NSSound.beep()
            return
        }
        prompt(text: text, title: String(localized: "Clipboard", bundle: .module))
    }

    /// The main shortcut: opens the prompter on the selected script, or plays and pauses it.
    public func playPause() {
        if prompter.isActive { prompter.toggle() } else { promptSelected() }
    }

    public func showOrHide() {
        if prompter.isActive { prompter.stop() } else { promptSelected() }
    }

    public var canPrompt: Bool { !(store.selected.map { Script($0.text).isEmpty } ?? true) }

    // MARK: Library

    /// Adds dropped or opened documents to the library and selects the last one.
    @discardableResult
    public func importDocuments(_ urls: [URL]) -> Bool {
        var imported = false
        for url in urls {
            do {
                let text = try ScriptImporter.text(from: url)
                store.create(text: text)
                imported = true
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
        if imported { showLibrary() }
        return imported
    }

    public func showLibrary() {
        showLibraryHandler?()
    }

    // MARK: Links

    /// islet://prompter/prompt?text=…&title=…, and toggle, play, pause, stop, faster, slower, restart, clipboard,
    /// library. The links of Souffleur, the prompter's former app (souffleur://toggle…), still work.
    public func open(_ url: URL) {
        let command: String
        switch url.scheme {
        case "souffleur": command = url.host ?? ""
        case "islet" where url.host == "prompter": command = url.pathComponents.dropFirst().first ?? "toggle"
        default: return
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        switch command {
        case "prompt":
            if let text = value("text"), !text.isEmpty { prompt(text: text, title: value("title")) } else { promptSelected() }
        case "toggle": playPause()
        case "play": if prompter.isActive { prompter.resume() } else { promptSelected() }
        case "pause": prompter.pause()
        case "stop", "hide": prompter.stop()
        case "faster": prompter.faster()
        case "slower": prompter.slower()
        case "restart": prompter.restart()
        case "clipboard": promptClipboard()
        case "library": showLibrary()
        default: break
        }
    }

    // MARK: Remote

    private func perform(_ command: RemoteCommand) {
        switch command {
        case .toggle: playPause()
        case .faster: prompter.faster()
        case .slower: prompter.slower()
        case .back: prompter.moveLine(-1)
        case .forward: prompter.moveLine(1)
        case .restart: prompter.restart()
        }
    }

    private func remoteState() -> RemoteState {
        let state = prompter.state
        guard prompter.isActive else {
            return .idle(title: store.selected?.title ?? "")
        }
        let pace = state.mode == .voice ? (state.measuredPace ?? 0) : state.wordsPerMinute
        return RemoteState(title: state.title, isRolling: state.isRolling, progress: state.progress, wordsPerMinute: pace, line: prompter.currentLine, remaining: state.remaining)
    }

    private func prompterChanged() {
        remote.broadcast()
        updateClickerKeys()
        let active = prompter.isActive
        if active != wasActive {
            wasActive = active
            onActiveChange?(active, prompter.placement)
        }
    }

    // MARK: Settings

    private func applyPreferences() {
        if PrompterPreferences.hotKeys, mainKeys.isEmpty {
            let chord = HotKeys.chord
            let result = hotKeys?.register([
                .init(key: kVK_ANSI_P, modifiers: chord, label: "⌃⌥⌘P") { [weak self] in self?.playPause() },
                .init(key: kVK_UpArrow, modifiers: chord, label: "⌃⌥⌘↑") { [weak self] in self?.prompter.faster() },
                .init(key: kVK_DownArrow, modifiers: chord, label: "⌃⌥⌘↓") { [weak self] in self?.prompter.slower() },
                .init(key: kVK_LeftArrow, modifiers: chord, label: "⌃⌥⌘←") { [weak self] in self?.prompter.moveLine(-1) },
                .init(key: kVK_RightArrow, modifiers: chord, label: "⌃⌥⌘→") { [weak self] in self?.prompter.moveLine(1) },
                .init(key: kVK_ANSI_H, modifiers: chord, label: "⌃⌥⌘H") { [weak self] in self?.showOrHide() },
                .init(key: kVK_ANSI_R, modifiers: chord, label: "⌃⌥⌘R") { [weak self] in self?.prompter.restart() },
            ])
            mainKeys = result?.ids ?? []
            takenShortcuts = result?.taken ?? []
        } else if !PrompterPreferences.hotKeys, !mainKeys.isEmpty {
            hotKeys?.unregister(mainKeys)
            mainKeys = []
            takenShortcuts = []
        }
        updateClickerKeys()
        prompter.paceChanged()
        if PrompterPreferences.mode != chosenMode {
            chosenMode = PrompterPreferences.mode
            if prompter.isActive { prompter.switchMode(chosenMode) }
        }
        if PrompterPreferences.remoteEnabled, !remote.isRunning { remote.start() }
        if !PrompterPreferences.remoteEnabled, remote.isRunning { remote.stop() }
    }

    /// Page Up and Page Down, which presentation clickers and foot pedals send, move the script, but only while the
    /// prompter is on screen, so they keep working everywhere else the rest of the time.
    private func updateClickerKeys() {
        let wanted = PrompterPreferences.clickerKeys && prompter.isActive
        if wanted, clickerKeys.isEmpty {
            clickerKeys = hotKeys?.register([
                .init(key: kVK_PageDown, modifiers: 0, label: "Page Down") { [weak self] in self?.clickerNext() },
                .init(key: kVK_PageUp, modifiers: 0, label: "Page Up") { [weak self] in self?.prompter.moveLine(-1) },
            ]).ids ?? []
        } else if !wanted, !clickerKeys.isEmpty {
            hotKeys?.unregister(clickerKeys)
            clickerKeys = []
        }
    }

    /// A clicker's "next" starts a paused take, and otherwise moves one line on.
    private func clickerNext() {
        switch prompter.state.phase {
        case .paused, .countdown, .finished: prompter.toggle()
        default: prompter.moveLine(1)
        }
    }
}
