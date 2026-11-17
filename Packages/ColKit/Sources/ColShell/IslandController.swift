import AppKit
import ColCore
import ColPrompter

/// Owns the island on the screen that has the notch: places the panel, runs the interaction rules, keeps the board
/// of live activities, and turns all of it into motion.
@MainActor
public final class IslandController {
    private let panel = IslandPanel()
    private let islandView: IslandView
    private let media = MediaController()
    private let lyrics = LyricsModel()
    private let ai = AIAppsModel()
    /// The closed island's wing follows the lyrics: their line is followed while it does.
    private var wingFollowsLyrics = false
    private let system = SystemActivities()
    private let agents = AgentCenter()
    private let custom = CustomActivities()
    private let navigation = IslandNavigation()
    private let shelf = ShelfModel()
    private let clipboard = ClipboardMonitor()
    private let timer = TimerModel()
    private let picker = ColorPickerModel()
    private let mirror = MirrorModel()
    private let calendar = CalendarModel()
    private let stats = SystemStatsModel()
    private let device = DeviceCardModel()
    private let awake = KeepAwake()
    private let downloads = DownloadsMonitor()
    /// Your Mac at a glance (2.3): weather, Caps Lock, accessories, Pomodoro, the next meeting.
    private let glance: Glance
    /// Widgets pushed by programs and devices, and read from addresses (Col Connect).
    private let widgets = WidgetCenter()
    private var hotKey: HotKey?
    /// An app covers the notch's screen in full screen: the island only shows brief displays.
    private var fullScreenActive = false
    /// The prompter is out of the notch: the island leaves it the place until the take ends.
    private var prompterInNotch = false
    /// A field of the open island has the keyboard: the island stays open until it gives it back.
    private var keyboardTaken = false
    /// The first-launch welcome has been shown, by the greeting or by its safety delay.
    private var welcomeShown = false
    /// Free width beside the notch before the app's menus (left) and the status items (right); nil when unknown.
    private var freeLeft: CGFloat?
    private var freeRight: CGFloat?
    /// False while Col cannot read the menu bar it shares (no Accessibility): activities then go beneath the camera.
    private var menuBarReadable = true
    /// The app whose menus fill the menu bar changes without always becoming active (an alert agent, a panel).
    private var menuBarOwnerObservation: NSKeyValueObservation?
    private var pendingMeasure: DispatchWorkItem?
    /// The ambient activity beneath the camera, and since when: after a few seconds it tucks back into the notch, as
    /// the strip covers the top of the window below. Alerts and brief displays stay as long as they last.
    private var beneathSince: (id: String, date: Date)?
    private var beneathTimer: Task<Void, Never>?
    static let beneathLinger: TimeInterval = 5
    /// A pill or a drawn notch on a screen without a notch, with the app's menus reaching where it rests: it stays
    /// out of the way until the island is opened.
    private var restBlocked = false
    /// Says when a status item comes or goes, so the wings are measured again right then.
    private let menuBarWatcher = MenuBarWatcher()
    /// The frontmost app is one the island steps aside for (Settings, Island).
    private var hiddenForApp = false
    let extensions = ExtensionRunner()
    private lazy var lockScreen = LockScreenWidgets(media: media, timer: timer, power: system.power, lyrics: lyrics)
    private lazy var desktopLyrics = DesktopLyrics(media: media, lyrics: lyrics)
    private var api: ControlAPI!
    /// True while the island is open because something asked for the user, not because the user opened it.
    private var openedByRequest = false
    private var machine = IslandMachine()
    private var board = ActivityBoard()
    private var screen: NSScreen?
    private var layout: IslandLayout?
    /// Width of each wing for the activity on show; zero when the notch is plain.
    private var wings: Wings = .none
    /// Left edge of the first status item right of the notch; status items change with apps launching, not with focus.
    private var statusItemsEdge: CGFloat?
    private var shownActivity: Activity?
    private var hoverTimer: Task<Void, Never>?
    private var exitTimer: Task<Void, Never>?
    private var expiryTimer: Task<Void, Never>?
    /// Bumped by every transition, so the end of a superseded one does not shrink the window under a newer one.
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    /// Watches for Souffleur opening in the minute after Col did.
    private var souffleurWatch: NSObjectProtocol?
    /// The Souffleurs Col asked to quit, watched in that minute until they have.
    private var souffleurExits: [NSKeyValueObservation] = []

    /// The models the island's content reads, kept to draw a second island in the settings.
    private let services: IslandServices
    private var previewClose: Task<Void, Never>?

    public init() {
        let glance = Glance(calendar: calendar, system: system)
        self.glance = glance
        let services = IslandServices(
            media: media, lyrics: lyrics, ai: ai, agents: agents, custom: custom, navigation: navigation, power: system.power,
            shelf: shelf, clipboard: clipboard, timer: timer, picker: picker, mirror: mirror, calendar: calendar, stats: stats,
            device: device, audio: system.audio, awake: awake, glance: glance,
            openSettings: { SettingsWindow.shared.show() }, widgets: widgets
        )
        self.services = services
        islandView = IslandView(services: services)
        let root = NSView()
        root.wantsLayer = true
        panel.contentView = root
        root.addSubview(islandView)
        islandView.onEvent = { [weak self] event in self?.send(event) }
        media.onChange = { [weak self] trackChanged in self?.mediaChanged(trackChanged: trackChanged) }
        lyrics.onLineChange = { [weak self] in
            guard let self, Preferences.showsLyricsInClosedIsland else { return }
            self.mediaChanged(trackChanged: false)
        }
        system.post = { [weak self] activity in self?.post(activity) }
        system.remove = { [weak self] id in self?.removeActivity(id) }
        system.registerImage = { [weak self] image, key in self?.islandView.compact.register(image, for: key) }
        glance.post = { [weak self] activity in self?.post(activity) }
        glance.remove = { [weak self] id in self?.removeActivity(id) }
        machine.opensOnHover = Preferences.opensOnHover
        board.ranking = Preferences.activityRanking
        islandView.onPageSwipe = { [weak self] step in
            self?.navigation.step(step)
            WelcomeWindow.shared.gesture(.swipeSide)
        }
        islandView.onDragChange = { [weak self] inside in self?.dragChanged(inside) }
        islandView.onDrop = { [weak self] urls in self?.dropped(urls) }
        timer.post = { [weak self] activity in self?.post(activity) }
        system.onHeadphones = { [weak self] output in self?.showHeadphones(output) }
        islandView.onCompactSwipe = { [weak self] step in self?.compactSwipe(step) }
        awake.changed = { [weak self] on in
            guard let self else { return }
            if on {
                self.post(Activity(id: "awake", priority: .ambient, compact: CompactPresentation(leading: .symbol("cup.and.saucer.fill", tint: Theme.accentRGBA)), updated: Date()))
            } else {
                self.removeActivity("awake")
            }
        }
        downloads.onEvent = { [weak self] event in self?.downloadEvent(event) }
        timer.remove = { [weak self] id in self?.removeActivity(id) }
        agents.onChange = { [weak self] in self?.agentsChanged() }
        agents.onRequest = { [weak self] in
            guard let self else { return }
            self.navigation.show(.live)
            if self.machine.state != .expanded { self.openedByRequest = true }
            self.send(.requested)
        }
        api = ControlAPI(
            custom: custom, agents: agents, widgets: widgets,
            post: { [weak self] activity in self?.post(activity) },
            remove: { [weak self] id in self?.removeActivity(id) }
        )
        connectWidgets()
        NotificationCenter.default.addObserver(forName: Preferences.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.preferencesChanged()
                if Preferences.keepsClipboardHistory { self?.clipboard.start() } else { self?.clipboard.stop() }
            }
        }
    }

    // MARK: Drag and drop

    /// Files dragged onto the notch open the island on the shelf.
    private func dragChanged(_ inside: Bool) {
        shelf.isTargeted = inside
        if inside {
            navigation.show(.shelf, otherwise: .drop)
            if machine.state != .expanded { openedByRequest = true }
            send(.requested)
        } else {
            syncPointer(after: 0.4)
        }
    }

    private func dropped(_ urls: [URL]) {
        shelf.isTargeted = false
        shelf.add(urls)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        syncPointer(after: 0.3)
    }

    /// Tracking areas go quiet during a drag: afterwards, tell the rules where the pointer really is.
    private func syncPointer(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let inside = self.islandView.containsPointer
                if inside != self.machine.pointerInside {
                    self.send(inside ? .pointerEntered : .pointerExited)
                } else if !inside, self.machine.state == .expanded, self.openedByRequest, self.agents.pending.isEmpty, !self.showingNote {
                    self.openedByRequest = false
                    self.send(.dismissed)
                }
            }
        }
    }

    // MARK: First launch

    /// The island opens by itself and says hello in one language after another; once it reaches the Mac's own, the
    /// welcome window is born out of it, and the island tucks back in.
    private func greet() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.navigation.greetsReady = false
                self.navigation.jump(to: .greeting)
                self.openedByRequest = true
                self.send(.requested)
                // In case the greeting cannot show, in full screen say: the welcome comes all the same.
                DispatchQueue.main.asyncAfter(deadline: .now() + 16) { MainActor.assumeIsolated { self.greetingDone() } }
            }
        }
    }

    /// The greeting has said its last hello, or was clicked: the welcome window comes out of the island.
    func greetingDone() {
        guard !welcomeShown else { return }
        welcomeShown = true
        WelcomeWindow.shared.show(fromIsland: navigation.route == .greeting && machine.state == .expanded)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.navigation.route == .greeting, !self.machine.pointerInside { self.send(.dismissed) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MainActor.assumeIsolated { if self.navigation.route == .greeting { self.navigation.jumpHome() } }
                }
            }
        }
    }

    /// The welcome went back into the notch: the island opens on "Let's go" for a moment.
    func sayReady() {
        // Someone new has just met this version: nothing to announce later.
        WhatsNew.markShown()
        navigation.greetsReady = true
        navigation.jump(to: .greeting)
        openedByRequest = true
        send(.requested)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.navigation.route == .greeting, !self.machine.pointerInside { self.send(.dismissed) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MainActor.assumeIsolated {
                        if self.navigation.route == .greeting { self.navigation.jumpHome() }
                        self.navigation.greetsReady = false
                        self.showSouffleurNoteIfDue()
                    }
                }
            }
        }
    }

    // MARK: What's new

    /// Once after an update to a new major version, the island opens on what it brings, then tucks back in; it stays
    /// while the pointer is on it. Someone new gets the welcome instead.
    private func showWhatsNewIfDue(force: Bool = false) {
        guard force || (WhatsNew.isDue && WelcomeWindow.hasWelcomed) else { return }
        guard machine.state != .expanded, ![.greeting, .souffleur, .device].contains(navigation.route), !prompterInNotch else { return }
        WhatsNew.markShown()
        navigation.jump(to: .whatsNew)
        openedByRequest = true
        send(.requested)
        closeWhatsNew(after: 14)
    }

    private func closeWhatsNew(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.navigation.route == .whatsNew else { return }
                guard !self.machine.pointerInside else { return self.closeWhatsNew(after: 3) }
                self.send(.dismissed)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MainActor.assumeIsolated { if self.navigation.route == .whatsNew { self.navigation.jumpHome() } }
                }
            }
        }
    }

    // MARK: Menu bar access

    /// Once, when the island cannot see the menu bar it shares, it says why activities sit beneath the camera and
    /// offers to ask for the permission. Never during the welcome, which asks for it itself.
    private func showMenuBarAccessNoteIfDue() {
        let key = "menuBarAccessNoteShown"
        guard WelcomeWindow.hasWelcomed, !AXIsProcessTrusted(), layout?.sharesMenuBar == true,
              !UserDefaults.standard.bool(forKey: key), machine.state != .expanded,
              ![.greeting, .souffleur, .device, .whatsNew].contains(navigation.route), !prompterInNotch
        else { return }
        UserDefaults.standard.set(true, forKey: key)
        navigation.jump(to: .menuBarAccess)
        openedByRequest = true
        send(.requested)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.navigation.route == .menuBarAccess else { return }
                if !self.machine.pointerInside { self.send(.dismissed) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MainActor.assumeIsolated { if self.navigation.route == .menuBarAccess { self.navigation.jumpHome() } }
                }
            }
        }
    }

    // MARK: Souffleur

    /// Souffleur, the prompter's former app, running beside Col is asked to quit: now, and if it opens in the minute
    /// that follows, as when both open at login.
    private func retireSouffleur() {
        askSouffleurToQuit()
        souffleurWatch = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == Souffleur.bundleIdentifier
            else { return }
            MainActor.assumeIsolated { self?.askSouffleurToQuit() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let watch = self.souffleurWatch { NSWorkspace.shared.notificationCenter.removeObserver(watch) }
                self.souffleurWatch = nil
                self.souffleurExits.forEach { $0.invalidate() }
                self.souffleurExits = []
            }
        }
        // A note left due by an earlier launch, whose welcome was put off.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated { self?.showSouffleurNoteIfDue() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            MainActor.assumeIsolated { self?.showWhatsNewIfDue() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            MainActor.assumeIsolated { self?.showMenuBarAccessNoteIfDue() }
        }
    }

    /// Asks each Souffleur running to quit, and watches those the request reached: asking is not closing, and the
    /// island says Col closed it only once it has quit.
    private func askSouffleurToQuit() {
        for app in Souffleur.askToQuit() {
            souffleurExits.append(app.observe(\.isTerminated, options: [.initial, .new]) { @Sendable [weak self] _, change in
                guard change.newValue == true else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.souffleurQuit() } }
            })
        }
    }

    /// A Souffleur Col asked to quit has quit. When its phone remote held the first port as Col opened, Col's remote,
    /// if on, takes that port back, so a page saved on the phone reaches Col. Then the island says why, the first time.
    private func souffleurQuit() {
        Souffleur.didQuit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated {
                PrompterCenter.shared.remote.takeBackFirstPort()
                self?.showSouffleurNoteIfDue()
            }
        }
    }

    /// The first time Col closes Souffleur, the island says why, once the welcome, which has the island on a first
    /// launch, is done. Left for the next launch when the welcome was put off.
    private func showSouffleurNoteIfDue() {
        guard Souffleur.noteIsDue, WelcomeWindow.hasWelcomed, navigation.route != .greeting else { return }
        Souffleur.noteShown()
        showSouffleurNote()
    }

    /// The island opens on the note for a few seconds, then tucks back in.
    private func showSouffleurNote() {
        navigation.jump(to: .souffleur)
        if machine.state != .expanded { openedByRequest = true }
        send(.requested)
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.navigation.route == .souffleur else { return }
                if !self.machine.pointerInside { self.send(.dismissed) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MainActor.assumeIsolated { if self.navigation.route == .souffleur { self.navigation.jumpHome() } }
                }
            }
        }
    }

    /// The island's shape for a state, in screen coordinates: where the welcome comes from and goes back to.
    func islandFrame(for state: IslandState) -> NSRect? {
        guard let screen, let layout else { return nil }
        let frame = layout.frame(for: state)
        let left = screen.frame.minX + layout.notch.centerX - layout.canvasSize.width / 2
        return NSRect(x: left + frame.minX, y: screen.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
    }

    // MARK: Shortcuts

    /// The running island, for App Intents.
    public private(set) static weak var shared: IslandController?

    /// Shows or updates an activity, as `colctl push` does.
    public func push(id: String, title: String?, symbol: String?, tint: String?, progress: Double?, text: String?, seconds: Double?) {
        let request = ActivityRequest(id: id, title: title, symbol: symbol, tint: tint, progress: progress, text: text, ttl: seconds)
        if let valid = try? request.validated() { api.push(valid) }
    }

    public func finish(id: String) {
        api.finish(id, text: nil)
    }

    public func startTimer(minutes: Int) {
        timer.start(minutes: max(1, min(minutes, 24 * 60)))
    }

    /// Mutes or unmutes the microphone, from the Live page's button.
    func toggleMicrophone() {
        system.toggleMicrophone()
    }

    public func openIsland() {
        navigation.showHome()
        openedByRequest = true
        send(.requested)
    }

    // MARK: Windows and the settings

    /// Where windows that open from the island go, so they never sit under the open island.
    var windowAnchor: WindowAnchor? {
        guard let screen, let layout else { return nil }
        return WindowAnchor(
            screen: screen,
            islandBottom: screen.frame.maxY - layout.frame(for: .expanded).maxY,
            centerX: screen.frame.minX + layout.notch.centerX
        )
    }

    /// The notch of the island's screen, for an island drawn at its real size elsewhere.
    var notchMetrics: NotchMetrics? { layout?.notch }
    var screenForPreview: NSScreen? { screen }

    /// The models of this island with pages of their own, for the island the settings draw.
    /// The island's models, for the welcome to show what is happening on the Mac now.
    var models: IslandServices { services }

    func stageServices(navigation: IslandNavigation, agents: AgentCenter? = nil) -> IslandServices {
        services.with(navigation: navigation, agents: agents)
    }

    /// What the closed island shows now, and how wide its wings are.
    var compactNow: (presentation: CompactPresentation?, wings: Wings) {
        (shownActivity?.compact.fitted(to: wings), wings)
    }

    var compactImages: [String: CGImage] { islandView.compact.registeredImages }

    /// The AI apps and model servers, for the settings.
    var aiApps: AIAppsModel { ai }

    /// A field of the open island asks for the keyboard: the panel becomes key without activating Col.
    func takeKeyboard() {
        guard !keyboardTaken, machine.state == .expanded else { return }
        keyboardTaken = true
        exitTimer?.cancel()
        panel.acceptsKeyboard = true
        panel.makeKeyAndOrderFront(nil)
    }

    /// The keyboard goes back to the app the user works in; a pointer already away lets the island close.
    func releaseKeyboard() {
        guard keyboardTaken else { return }
        panel.resignKey()
        keyboardLost()
    }

    /// The panel is no longer key, given back or taken by a click elsewhere: no field types any more.
    private func keyboardLost() {
        guard keyboardTaken else { return }
        keyboardTaken = false
        panel.acceptsKeyboard = false
        ai.ask.editing = false
        clipboard.searching = false
        if machine.state == .expanded, !machine.pointerInside { perform(.startExitTimer) }
    }

    /// Opens the island for a moment to show a change made in the settings, then tucks it back in, unless the
    /// pointer has come to it in the meantime.
    func previewChange() {
        // On the next turn, once a new size has laid the island out again.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.machine.state != .expanded {
                    self.navigation.showHome()
                    self.openedByRequest = true
                    self.send(.requested)
                }
                self.previewClose?.cancel()
                self.previewClose = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2.4))
                    guard let self, !Task.isCancelled, self.openedByRequest, !self.machine.pointerInside, self.agents.pending.isEmpty else { return }
                    self.openedByRequest = false
                    self.send(.dismissed)
                }
            }
        }
    }

    // MARK: Headphones, gestures, shortcut, downloads, full screen

    /// Headphones connected: the island opens on a card with the device and its battery, then tucks back in.
    private func showHeadphones(_ output: AudioMonitor.Output, demo: AccessoryBattery? = nil) {
        device.name = SystemGlyphs.shortDeviceName(output.name)
        let model = demo == nil ? BluetoothAccessories.model(forName: output.name) : HeadphoneModel(name: output.name)
        device.model = model
        device.symbol = model.flatMap { $0.symbols.first(where: { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }) }
            ?? SystemGlyphs.audioDevice(name: output.name, transport: output.transport)
        device.battery = nil
        device.arrival += 1
        post(Activity(
            id: "audio.output", priority: .transient,
            compact: CompactPresentation(leading: .symbol(device.symbol), trailing: .text(device.name)),
            expires: Date().addingTimeInterval(4), updated: Date()
        ))
        navigation.jump(to: .device)
        if machine.state != .expanded { openedByRequest = true }
        send(.requested)
        // Headphones report their battery a moment after they connect.
        for delay in [0.8, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.navigation.route == .device else { return }
                    if let battery = demo ?? BluetoothAccessories.battery(forName: output.name) { self.device.battery = battery }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.navigation.route == .device else { return }
                if !self.machine.pointerInside { self.send(.dismissed) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    MainActor.assumeIsolated { if self.navigation.route == .device { self.navigation.jumpHome() } }
                }
            }
        }
    }

    /// Two fingers sideways on the closed island change track while music plays.
    private func compactSwipe(_ step: Int) {
        guard media.hasPlayer, shownActivity?.id.hasPrefix("media") == true else { return }
        step > 0 ? media.nextTrack() : media.previousTrack()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Opens the island from a link, on the page asked for, or closes it.
    private func showFromLink(open: Bool, page: String?) {
        if open {
            if let page { navigation.show(navigation.route(named: page)) } else { navigation.showHome() }
            openedByRequest = true
            if machine.state != .expanded { send(.requested) }
        } else if machine.state == .expanded {
            openedByRequest = false
            send(.dismissed)
        }
    }

    private func toggleFromShortcut() {
        if machine.state == .expanded {
            openedByRequest = false
            send(.dismissed)
        } else {
            navigation.showHome()
            openedByRequest = true
            send(.requested)
        }
    }

    private func downloadEvent(_ event: DownloadTracker.Event) {
        let now = Date()
        switch event {
        case .started(let name):
            post(Activity(id: "download." + name, priority: .standard,
                          compact: CompactPresentation(leading: .symbol("arrow.down.circle.fill", tint: .blue), trailing: .spinner(tint: .blue)), updated: now))
        case .finished(let name):
            post(Activity(id: "download." + name, priority: .transient,
                          compact: CompactPresentation(leading: .symbol("arrow.down.circle.fill", tint: .blue), trailing: .symbol("checkmark.circle.fill", tint: .green)),
                          expires: now.addingTimeInterval(3), updated: now))
        case .cancelled(let name):
            removeActivity("download." + name)
        }
    }

    /// Measures the menu bar around the notch: the app's menus each time the frontmost app changes, the status items
    /// when one comes or goes. Islands that rest in the menu bar row without a notch (a pill, a drawn notch) are
    /// measured the same way, from their own edges.
    private func measureMenuBar(statusItems: Bool = false) {
        guard let screen, let layout, layout.sharesMenuBar else {
            freeLeft = nil; freeRight = nil; restBlocked = false; menuBarReadable = true
            applySideRoom()
            return
        }
        // `-ColMenuBarFree 132` lends each wing that much room whatever the menu bar holds, so screenshots and films do
        // not depend on the apps of the Mac they are taken on.
        let lent = UserDefaults.standard.double(forKey: "ColMenuBarFree")
        if lent > 0 {
            freeLeft = lent; freeRight = lent; restBlocked = false; menuBarReadable = true
            applySideRoom()
            return
        }
        // Without Accessibility the menu bar cannot be read: activities go beneath the camera (or, on a pill, keep a
        // narrow wing), rather than over menus and icons Col cannot see.
        guard AXIsProcessTrusted() else {
            freeLeft = nil; freeRight = nil; restBlocked = false; menuBarReadable = false
            applySideRoom()
            return
        }
        menuBarReadable = true
        let notchLeft = screen.frame.minX + layout.notch.centerX - layout.notch.width / 2
        let notchRight = notchLeft + layout.notch.width
        // Accessibility measures from the top left of the main screen.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let top = primaryHeight - screen.frame.maxY
        if statusItems || statusItemsEdge == nil {
            statusItemsEdge = MenuBarSpace.statusItemsLeftEdge(after: notchRight, top: top, span: screen.frame.minX...screen.frame.maxX)
        }
        // Menus that could not be read are as good as unseen: rather than a wing over them, the activity goes beneath
        // the camera until they can be.
        guard let menus = MenuBarSpace.appMenus(notchCenter: notchLeft + layout.notch.width / 2) else {
            freeLeft = nil; freeRight = nil; restBlocked = false; menuBarReadable = false
            applySideRoom()
            if UserDefaults.standard.bool(forKey: "ColDebug") {
                FileHandle.standardError.write(Data("menu bar: the menus cannot be read\n".utf8))
            }
            return
        }
        freeLeft = WingBudget.free(notchEdge: notchLeft, nearestItem: menus.leftEnd, leftSide: true)
        // On the right, the nearest of the app's overflowing menus and the status items. Status items that could not
        // be read leave the right side no room, rather than a wing over icons Col cannot see.
        let rightItems = [menus.rightStart, statusItemsEdge ?? notchRight].compactMap { $0 }
        freeRight = WingBudget.free(notchEdge: notchRight, nearestItem: rightItems.min(), leftSide: false)
        // Without a notch, menus can reach the middle of the menu bar on a small screen: the resting island then
        // keeps out of their way.
        if layout.notch.isHardware {
            restBlocked = false
        } else {
            let leftReach = (menus.leftEnd ?? -.greatestFiniteMagnitude) + WingBudget.margin
            // Only what was actually read keeps the resting island away.
            let readRight = [menus.rightStart, statusItemsEdge].compactMap { $0 }.min()
            let rightReach = (readRight ?? .greatestFiniteMagnitude) - WingBudget.margin
            restBlocked = leftReach > notchLeft || rightReach < notchRight
        }
        applySideRoom()
        if UserDefaults.standard.bool(forKey: "ColDebug") {
            FileHandle.standardError.write(Data("menu bar: app \(NSWorkspace.shared.menuBarOwningApplication?.localizedName ?? "?") free left \(String(describing: freeLeft)) right \(String(describing: freeRight)) status items \(String(describing: statusItemsEdge)) blocked \(restBlocked)\n".utf8))
        }
    }

    /// Measures the app's menus a moment from now, once for a burst of changes: an app that comes to the front also
    /// takes the menu bar, and both say so.
    private func measureMenusSoon() {
        pendingMeasure?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.measureMenuBar()
                self?.refreshActivity()
            }
        }
        pendingMeasure = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    /// Hands the tighter side's room to the layout, so the island swells under the pointer only as far as it may.
    private func applySideRoom() {
        guard var layout else { return }
        // A menu bar Col cannot read gets no swell at all beside the notch: the island only grows taller under the
        // pointer, as it does when a menu sits right against it.
        let room = menuBarReadable ? [freeLeft, freeRight].compactMap { $0 }.min() : 0
        guard layout.sideRoom != room else { return }
        layout.sideRoom = room
        self.layout = layout
        islandView.updateLayout(layout)
        islandView.restVisible = Preferences.showsIslandAtRest && !restBlocked
        if machine.state == .peek { reshape(from: .peek) }
    }

    /// Spaces and the frontmost app changed: follow the active screen, and step aside in full screen.
    private func environmentChanged() {
        // A copy is often followed by a switch to another app: look at the pasteboard now rather than at the next check.
        if Preferences.keepsClipboardHistory { clipboard.check() }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let hidden = frontmost.map(Preferences.hiddenInApps.contains) ?? false
        if hidden != hiddenForApp {
            hiddenForApp = hidden
            updateVisibility()
        }
        // Menus change with the app; let them settle before measuring.
        measureMenusSoon()
        if Preferences.displayChoice == "main", Self.notchScreen() != screen {
            screensChanged()
        } else {
            followFullScreen()
        }
    }

    /// Steps aside while an app covers the island's screen in full screen, when the settings ask, and comes back after.
    private func followFullScreen() {
        let active = Preferences.hidesInFullScreen && isFullScreen()
        guard active != fullScreenActive else { return }
        fullScreenActive = active
        updateVisibility()
    }

    private func isFullScreen() -> Bool {
        guard let screen, let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        // Window bounds are in the global top-left space; so is the screen frame, flipped from AppKit's.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let frame = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        let windows = list.compactMap { info -> FullScreen.Window? in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds)
            else { return nil }
            return FullScreen.Window(layer: layer, bounds: rect, ownerPID: pid)
        }
        return FullScreen.isActive(windows: windows, screen: frame, frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    /// In full screen the island shows only while something brief or urgent is on, or while it is open. While the
    /// prompter is out of the notch, it does not show at all.
    private func updateVisibility() {
        let urgent = (shownActivity?.priority ?? .ambient) >= .alert
        let steppedAside = fullScreenActive || hiddenForApp
        let visible = !prompterInNotch && (!steppedAside || urgent || machine.state == .expanded)
        if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        islandView.compact.isOnScreen = visible
    }

    /// The prompter came out of the notch, or went back in: the island steps aside for the take and returns after it.
    private func prompterChanged(active: Bool, placement: PrompterPlacement) {
        let inNotch = active && placement == .notch
        guard inNotch != prompterInNotch else { return }
        prompterInNotch = inNotch
        if inNotch {
            openedByRequest = false
            if machine.state != .collapsed { send(.dismissed) }
            // Once the island has tucked in, behind the prompter that grows from the same place.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                MainActor.assumeIsolated { self?.updateVisibility() }
            }
        } else {
            updateVisibility()
            refreshActivity()
        }
    }

    /// Applies settings as they change: the island re-lays itself out only when its size did.
    private func preferencesChanged() {
        if Preferences.hotKeyEnabled { hotKey?.register() } else { hotKey?.unregister() }
        if Preferences.watchesDownloads { downloads.start() } else { downloads.stop() }
        environmentChanged()
        machine.opensOnHover = Preferences.opensOnHover
        system.startKeyTapIfAllowed()
        menuBarWatcher.start()
        navigation.reloadDeck()
        board.ranking = Preferences.activityRanking
        panel.sharingType = Preferences.hiddenFromScreenCapture ? .none : .readOnly
        islandView.setGlass(Preferences.islandGlass)
        let style = layout.map { $0.notch.isHardware ? Preferences.notchStyle : Preferences.floatingStyle }
        islandView.restVisible = Preferences.showsIslandAtRest && !restBlocked
        if layout?.size != Preferences.islandSize || layout?.floating != style || layout?.wingLimit != Preferences.wingLimit {
            _ = machine.handle(.dismissed)
            islandView.dismissContent()
            islandView.discardContent()
            // The menu bar has not changed: measuring its status items again would only slow the change down.
            place(measuringStatusItems: false)
        }
        mediaChanged(trackChanged: false)
        agentsChanged()
        // Where activities sit (beside or beneath the camera) may have changed.
        refreshActivity()
        glance.preferencesChanged()
        ConnectCenter.shared.update()
    }

    // MARK: Connect and widgets

    /// Widgets post their activities to the board; Connect's requests reach the same routes as the local API's.
    private func connectWidgets() {
        widgets.post = { [weak self] activity in self?.post(activity) }
        widgets.remove = { [weak self] id in self?.removeActivity(id) }
        api.reloadExtensions = { [weak self] in
            guard let self else { return 0 }
            self.extensions.reload()
            return self.extensions.installed.count
        }
        extensions.pushWidget = { [weak self] widget in self?.widgets.set(widget) }
        extensions.removeWidget = { [weak self] id in self?.widgets.remove(id) }
        SettingsWindow.shared.widgets = widgets
        ConnectCenter.shared.server.handler = { [weak self] route, request, _ in
            self?.api.connect(route, request) ?? .error("unavailable", status: 503)
        }
    }

    /// Handles a `col://` link, Islet's `islet://` ones, and the prompter's links (`col://prompter/…`, and Souffleur's
    /// `souffleur://…`).
    public func open(_ url: URL) {
        if url.scheme == "souffleur" || (["col", "islet"].contains(url.scheme) && url.host == "prompter") {
            PrompterCenter.shared.open(url)
        } else {
            api.open(url)
        }
    }

    /// Documents opened with Col go to the prompter's library.
    public func importScripts(_ urls: [URL]) {
        PrompterCenter.shared.importDocuments(urls)
    }

    private func agentsChanged() {
        if Preferences.showsAgents, let activity = agents.activity(tint: Theme.accentRGBA) {
            post(activity)
        } else {
            removeActivity("agents")
        }
        // Once the user has answered, an island that opened by itself closes by itself. A note the island opened on
        // (what's new, the welcome's hello, a card) keeps its own time: an agent at work elsewhere does not cut it short.
        if agents.pending.isEmpty, openedByRequest, !showingNote {
            openedByRequest = false
            if machine.state == .expanded, !machine.pointerInside { send(.dismissed) }
        }
    }

    public func start() {
        Self.shared = self
        place()
        panel.onResignKey = { [weak self] in self?.keyboardLost() }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: Notification.Name("ColShowSettings"), object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { SettingsWindow.shared.show() } })
        media.start()
        system.start()
        glance.start()
        api.start()
        clipboard.start()
        api.showIsland = { [weak self] open, page in self?.showFromLink(open: open, page: page) }
        extensions.push = { [weak self] request in self?.api.push(request) }
        extensions.remove = { [weak self] id in
            self?.custom.remove(String(id.dropFirst(4)))
            self?.removeActivity(id)
        }
        extensions.reload()
        SettingsWindow.shared.extensions = extensions
        ConnectCenter.shared.update()
        hotKey = HotKey { [weak self] in self?.toggleFromShortcut() }
        if Preferences.hotKeyEnabled { hotKey?.register() }
        if Preferences.watchesDownloads { downloads.start() }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.environmentChanged() }
            })
        }
        menuBarWatcher.onChange = { [weak self] in
            self?.measureMenuBar(statusItems: true)
            self?.refreshActivity()
        }
        menuBarWatcher.start()
        menuBarOwnerObservation = NSWorkspace.shared.observe(\.menuBarOwningApplication) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.measureMenusSoon() } }
        }
        // Accessibility granted or taken away: the menu bar can be read, or no longer, without a relaunch. Activities
        // move beside the camera, or back beneath it, right away.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                MainActor.assumeIsolated {
                    self?.menuBarWatcher.start()
                    self?.measureMenuBar(statusItems: true)
                    self?.refreshActivity()
                }
            }
        })
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    MainActor.assumeIsolated {
                        self?.measureMenuBar(statusItems: true)
                        self?.refreshActivity()
                    }
                }
            })
        }
        ai.start()
        let prompter = PrompterCenter.shared
        prompter.showLibraryHandler = { ScriptLibraryWindow.shared.show() }
        prompter.onActiveChange = { [weak self] active, placement in self?.prompterChanged(active: active, placement: placement) }
        prompter.start()
        lockScreen.weather = glance.weather
        lockScreen.start()
        desktopLyrics.start()
        if Preferences.showsOnLockScreen { LockScreenSpace.shared?.adopt(panel) }
        if !WelcomeWindow.hasWelcomed { greet() }
        retireSouffleur()
        startMenuBarDrawers()
        // `-ColDemo headphones` (or `max`) plays the headphones card with sample levels, without touching Bluetooth.
        if let demo = UserDefaults.standard.string(forKey: "ColDemo"), demo == "headphones" || demo == "max" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated {
                    if demo == "max" {
                        self?.showHeadphones(AudioMonitor.Output(id: 0, name: "AirPods Max", transport: .bluetooth), demo: AccessoryBattery(single: 76))
                    } else {
                        self?.showHeadphones(AudioMonitor.Output(id: 0, name: "AirPods Pro", transport: .bluetooth), demo: AccessoryBattery(left: 92, right: 88, caseLevel: 64))
                    }
                }
            }
        }
        // Demo content for screenshots, standing in for the user's, which is neither shown nor changed:
        // `-ColDemoShelf <folder>` puts that folder's files on the shelf, `-ColDemo clipboard` shows a few copies
        // (`-ColDemoImage <png>` for the copied photo), `-ColDemo drop` shows files being dragged over the island,
        // `-ColDemo souffleur` the note the island gives the first time it closes Souffleur. `-ColDemo meeting`,
        // `devices` or `pomodoro` stand in a call about to start, three accessories or a focus session under way for
        // the calendar, the accessories and the timer of the Mac.
        if let folder = UserDefaults.standard.string(forKey: "ColDemoShelf") {
            shelf.showDemo(folder: URL(fileURLWithPath: folder))
        }
        switch UserDefaults.standard.string(forKey: "ColDemo") {
        case "clipboard":
            clipboard.showDemo(image: UserDefaults.standard.string(forKey: "ColDemoImage").flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) })
        case "drop":
            shelf.isTargeted = true
        case "souffleur":
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated { self?.showSouffleurNote() }
            }
        case "whatsnew":
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated { self?.showWhatsNewIfDue(force: true) }
            }
        case "menubar":
            // The note about the menu bar, whatever the permission says.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated {
                    self?.navigation.jump(to: .menuBarAccess)
                    self?.send(.requested)
                }
            }
        case "meeting":
            let start = Date().addingTimeInterval(4 * 60 + 32)
            glance.meetings.showDemo(CalendarModel.Event(id: "demo", title: "Design review", start: start, end: start.addingTimeInterval(1800),
                                                         isAllDay: false, color: .systemPurple, meeting: URL(string: "https://example.com/call")))
        case "devices":
            glance.accessories.showDemo([
                AccessoryLevel(id: "keyboard", name: "Magic Keyboard", kind: .keyboard, percent: 82),
                AccessoryLevel(id: "mouse", name: "Magic Mouse", kind: .mouse, percent: 64),
                AccessoryLevel(id: "controller", name: "Wireless Controller", kind: .gameController, percent: 31),
            ])
        case "pomodoro":
            glance.pomodoro.showDemo(Pomodoro(phase: .focus, plan: .standard, starting: Date().addingTimeInterval(-9 * 60)), completed: 2)
        case "privacy":
            // An app listening, as when you dictate to an assistant: `-ColDemoApp` names the app whose icon shows.
            let path = UserDefaults.standard.string(forKey: "ColDemoApp") ?? "/System/Applications/Voice Memos.app"
            var rect = CGRect(x: 0, y: 0, width: 64, height: 64)
            islandView.compact.register(NSWorkspace.shared.icon(forFile: path).cgImage(forProposedRect: &rect, context: nil, hints: nil), for: "privacy.app")
            if let presentation = PrivacyIndicator.presentation(microphone: true, camera: false, muted: false, appIcon: true) {
                post(Activity(id: "privacy", priority: .standard, compact: presentation, updated: Date()))
            }
        default:
            break
        }
        // `-ColPrompt "text"` rolls that script in the prompter a moment after launch, for screenshots and films.
        if let script = UserDefaults.standard.string(forKey: "ColPrompt"), !script.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                PrompterCenter.shared.prompt(text: script, title: UserDefaults.standard.string(forKey: "ColPromptTitle"))
            }
        }
        // `-ColWelcome YES` opens the welcome at once, for screenshots and for working on it.
        if UserDefaults.standard.bool(forKey: "ColWelcome") { WelcomeWindow.shared.show() }
        // `-ColSettings island` opens the settings on a pane, for screenshots and for working on them.
        if let pane = UserDefaults.standard.string(forKey: "ColSettings").flatMap(SettingsPane.init(link:)) {
            SettingsWindow.shared.show(pane)
        }
        // `-ColOpen YES` starts the island open, for screenshots and for working on its content; `-ColPage live`
        // chooses the page.
        if UserDefaults.standard.bool(forKey: "ColOpen") {
            if let page = UserDefaults.standard.string(forKey: "ColPage") { navigation.show(navigation.route(named: page)) }
            send(.pressed)
        }
    }

    public func stop() {
        // Every icon back in the menu bar before anything else goes.
        MenuBarDrawers.shared.stop()
        // A microphone Col muted is not left muted with nothing to show it.
        system.microphone.restoreAll()
        PrompterCenter.shared.willTerminate()
        lockScreen.stop()
        desktopLyrics.stop()
        media.stop()
        api.stop()
        ConnectCenter.shared.server.stop()
    }

    /// The menu bar option: when it is on, the drawers start with the island, and each time they move icons or change their
    /// own items the island measures the room beside the notch again, the room the drawers give it.
    private func startMenuBarDrawers() {
        let drawers = MenuBarDrawers.shared
        drawers.menuBarChanged = { [weak self] in
            self?.measureMenuBar(statusItems: true)
            self?.refreshActivity()
        }
        MenuBarSpace.ownItems = { drawers.ownItemFrames }
        drawers.start()
    }

    // MARK: Activities

    /// Shows an activity in the notch, or updates it if one with the same id is live.
    public func post(_ activity: Activity) {
        board.upsert(activity)
        refreshActivity()
    }

    public func removeActivity(_ id: String) {
        board.remove(id)
        refreshActivity()
    }

    private func refreshActivity() {
        let now = Date()
        board.prune(now: now)
        custom.prune(now: now)
        let current = board.current(now: now)
        scheduleExpiry(after: now)
        guard let layout else { return }

        let requested = islandView.compact.wingWidths(for: current?.compact, notchHeight: layout.notch.height)
        // Never over the menu bar, ears and swell included: the wings shrink to the free space, and when none is left,
        // or the menu bar cannot be read, the activity goes beneath the camera. A resting pill that menus reach shows
        // nothing at all.
        var newWings: Wings
        if restBlocked {
            newWings = .none
        } else if layout.sharesMenuBar {
            newWings = WingBudget.placement(
                leading: requested.leading,
                trailing: requested.trailing,
                beneath: islandView.compact.beneathWings(for: current?.compact, layout: layout),
                left: freeLeft,
                right: freeRight,
                readable: menuBarReadable,
                overhang: layout.wingOverhang,
                canHangBeneath: layout.canHangBeneath,
                prefersBeneath: Preferences.activitiesBeneath
            )
        } else {
            newWings = Wings(leading: requested.leading, trailing: requested.trailing)
        }
        newWings = tuckedBeneath(newWings, current: current, now: now)
        let presentation = current?.compact.fitted(to: newWings)
        islandView.showCompact(presentation, wings: newWings)
        shownActivity = current
        if fullScreenActive || hiddenForApp { updateVisibility() }
        if newWings != wings {
            wings = newWings
            if machine.state != .expanded { reshape(from: machine.state) }
        }
    }

    /// An ambient or running activity beneath the camera shows for a few seconds when it arrives, then tucks into the
    /// notch, where hovering or opening the island finds it. What needs the user, and brief displays, stay.
    private func tuckedBeneath(_ wings: Wings, current: Activity?, now: Date) -> Wings {
        guard wings.beneath, let current, current.priority < .alert else {
            if !wings.beneath { beneathSince = nil }
            beneathTimer?.cancel()
            return wings
        }
        if beneathSince?.id != current.id { beneathSince = (current.id, now) }
        let left = Self.beneathLinger - now.timeIntervalSince(beneathSince?.date ?? now)
        beneathTimer?.cancel()
        guard left > 0 else { return .none }
        beneathTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(left + 0.02))
            guard !Task.isCancelled else { return }
            self?.refreshActivity()
        }
        return wings
    }

    /// Wakes up exactly when the next activity expires, instead of polling.
    private func scheduleExpiry(after now: Date) {
        expiryTimer?.cancel()
        guard let next = board.nextExpiry(after: now) else { return }
        let delay = max(next.timeIntervalSince(now), 0.01)
        expiryTimer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.refreshActivity()
        }
    }

    private var pauseLinger: TimeInterval { 10 }

    private func mediaChanged(trackChanged: Bool) {
        let now = Date()
        let playing = media.nowPlaying
        lyrics.update(playing)
        followLyricsInWing(playing.isPlaying && Preferences.showsMediaActivity && Preferences.showsLyricsInClosedIsland)
        guard !playing.isEmpty, Preferences.showsMediaActivity else {
            board.remove("media")
            board.remove("media.track")
            refreshActivity()
            return
        }
        islandView.compact.register(media.artworkImage, for: "media.artwork")
        let cover: CompactItem = media.artworkImage != nil ? .image(key: "media.artwork") : .symbol("music.note", tint: media.tint)
        let existing = board.activities["media"]
        // While paused the activity lingers a little, then leaves the notch alone.
        let expires: Date? = playing.isPlaying ? nil : (existing?.expires ?? now.addingTimeInterval(pauseLinger))
        if playing.isPlaying || existing != nil {
            board.upsert(Activity(
                id: "media",
                priority: .ambient,
                // With lyrics in the wing, the line being sung takes the equalizer's place.
                compact: CompactPresentation(leading: cover, trailing: wingLine(playing).map { .text($0) } ?? .equalizer(tint: media.tint, playing: playing.isPlaying)),
                expires: expires,
                updated: existing?.updated ?? now
            ))
        }
        // A new track announces itself for a moment.
        if trackChanged, Preferences.showsTrackChanges, playing.isPlaying, !playing.title.isEmpty {
            board.upsert(Activity(
                id: "media.track",
                priority: .transient,
                compact: CompactPresentation(leading: cover, trailing: .text(playing.title)),
                expires: now.addingTimeInterval(3.5),
                updated: now
            ))
        }
        refreshActivity()
    }

    private func wingLine(_ playing: NowPlaying) -> String? {
        guard Preferences.showsLyricsInClosedIsland, playing.isPlaying else { return nil }
        return lyrics.currentLine
    }

    private func followLyricsInWing(_ follows: Bool) {
        guard follows != wingFollowsLyrics else { return }
        wingFollowsLyrics = follows
        if follows { lyrics.watch() } else { lyrics.unwatch() }
    }

    // MARK: Placement

    /// The screen with the notch (or else the built-in one), or the screen with the active window, as chosen.
    private static func notchScreen() -> NSScreen? {
        if Preferences.displayChoice == "main", let main = NSScreen.main { return main }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.screens.first { CGDisplayIsBuiltin(($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0) != 0 }
            ?? NSScreen.main
    }

    private func place(measuringStatusItems: Bool = true) {
        guard let screen = Self.notchScreen() else {
            panel.orderOut(nil)
            islandView.compact.isOnScreen = false
            return
        }
        self.screen = screen
        var notch = NotchMetrics.resolve(
            screenWidth: screen.frame.width,
            // `-ColNoNotch YES` draws the floating island even on a notched screen, to work on it.
            safeAreaTop: UserDefaults.standard.bool(forKey: "ColNoNotch") ? 0 : screen.safeAreaInsets.top,
            leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
            rightAreaWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY,
            floating: Preferences.floatingStyle
        )
        // `-ColCenterX 300` moves an island without a notch along the menu bar, so a notched Mac can show and film it
        // away from its camera housing (with `-ColNoNotch YES`).
        let shift = UserDefaults.standard.double(forKey: "ColCenterX")
        if !notch.isHardware, shift > 0 { notch.centerX = shift }
        let style = notch.isHardware ? Preferences.notchStyle : Preferences.floatingStyle
        let layout = IslandLayout(notch: notch, size: Preferences.islandSize, floating: style, sideRoom: self.layout?.sideRoom,
                                  wingLimit: Preferences.wingLimit)
        islandView.compact.wingLimit = layout.wingLimit
        self.layout = layout
        panel.sharingType = Preferences.hiddenFromScreenCapture ? .none : .readOnly

        let state = machine.state
        islandView.restVisible = Preferences.showsIslandAtRest && !restBlocked
        islandView.configure(layout, state: state, wings: effectiveWings, scale: screen.backingScaleFactor)
        islandView.setGlass(Preferences.islandGlass)
        resizeWindow(to: layout.windowSize(for: state, wings: effectiveWings))
        islandView.showCompact(shownActivity?.compact.fitted(to: wings), wings: wings)
        // Laid out again, the island still leaves the notch to a take, and full screen to the app that has it.
        updateVisibility()
        measureMenuBar(statusItems: measuringStatusItems)
    }

    private func screensChanged() {
        _ = machine.handle(.dismissed)
        cancelTimers()
        islandView.dismissContent()
        islandView.discardContent()
        place()
        // The island may hang on another screen now: full screen there is what counts.
        followFullScreen()
    }

    /// Resizes the panel around the notch and re-pins the canvas to its top centre, so the island stays put on
    /// screen. Done by hand: autoresizing mishandles the canvas's negative margins.
    private func resizeWindow(to size: CGSize) {
        guard let layout else { return }
        let frame = frame(for: size)
        panel.setFrame(frame, display: false)
        islandView.setFrameOrigin(NSPoint(
            x: (frame.width - layout.canvasSize.width) / 2,
            y: frame.height - layout.canvasSize.height
        ))
    }

    /// Window frame of a given size, hanging from the top of the screen and centred on the notch.
    private func frame(for size: CGSize) -> NSRect {
        guard let screen, let layout else { return .zero }
        return NSRect(
            x: (screen.frame.minX + layout.notch.centerX - size.width / 2).rounded(),
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// The island is open on a note that closes on its own schedule: the hello, what's new, a card, a word about the
    /// menu bar or Souffleur.
    private var showingNote: Bool {
        [.greeting, .whatsNew, .menuBarAccess, .souffleur, .device].contains(navigation.route)
    }

    /// The open island has no wings; its content replaces them.
    private var effectiveWings: Wings { machine.state == .expanded ? .none : wings }

    // MARK: Interaction

    private func send(_ event: IslandEvent) {
        let previous = machine.state
        switch event {
        case .pointerEntered: WelcomeWindow.shared.gesture(.hover)
        case .swipedDown: WelcomeWindow.shared.gesture(.swipeDown)
        default: break
        }
        if event == .pointerEntered || event == .pressed { openedByRequest = false }
        let effects = machine.handle(event)
        effects.forEach(perform)
        if machine.state != previous { reshape(from: previous) }
    }

    private func perform(_ effect: IslandEffect) {
        switch effect {
        case .startHoverTimer:
            hoverTimer?.cancel()
            hoverTimer = after(Motion.hoverDwell) { $0.send(.hoverTimerFired) }
        case .cancelHoverTimer:
            hoverTimer?.cancel()
            hoverTimer = nil
        case .startExitTimer:
            exitTimer?.cancel()
            // Typing in the island: the pointer may wander, the island stays.
            guard !keyboardTaken else { return }
            exitTimer = after(Motion.exitGrace) { $0.send(.exitTimerFired) }
        case .cancelExitTimer:
            exitTimer?.cancel()
            exitTimer = nil
        case .haptic:
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    private func after(_ delay: Duration, _ action: @escaping @MainActor (IslandController) -> Void) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            action(self)
        }
    }

    private func cancelTimers() {
        perform(.cancelHoverTimer)
        perform(.cancelExitTimer)
    }

    /// Moves the island to the machine's state and the current wings.
    private func reshape(from previous: IslandState) {
        guard let layout else { return }
        generation += 1
        let current = generation
        let state = machine.state
        let target = layout.windowSize(for: state, wings: effectiveWings)

        // Grow the window first so the motion is never clipped; shrink it only once the island has settled.
        let size = panel.frame.size
        resizeWindow(to: CGSize(width: max(size.width, target.width), height: max(size.height, target.height)))

        if state == .expanded, previous != .expanded {
            calendar.refresh()
            clipboard.check()
            glance.islandOpened()
            islandView.presentContent()
        }
        if previous == .expanded, state != .expanded {
            mirror.stop()
            releaseKeyboard()
            islandView.dismissContent()
        }

        islandView.transition(to: state, wings: effectiveWings) { [weak self] in
            guard let self, self.generation == current else { return }
            self.resizeWindow(to: target)
            if state != .expanded { self.islandView.discardContent() }
        }

        // The tracked area changed with the shape: catch a pointer that is already on the other side of its edge.
        let inside = islandView.containsPointer
        if inside != machine.pointerInside { send(inside ? .pointerEntered : .pointerExited) }
    }
}
