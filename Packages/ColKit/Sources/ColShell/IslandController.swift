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
    let extensions = ExtensionRunner()
    private lazy var lockScreen = LockScreenWidgets(media: media, timer: timer, power: system.power)
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
        let services = IslandServices(
            media: media, lyrics: lyrics, ai: ai, agents: agents, custom: custom, navigation: navigation, power: system.power,
            shelf: shelf, clipboard: clipboard, timer: timer, picker: picker, mirror: mirror, calendar: calendar, stats: stats,
            device: device, audio: system.audio, awake: awake,
            openSettings: { SettingsWindow.shared.show() }
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
            custom: custom, agents: agents,
            post: { [weak self] activity in self?.post(activity) },
            remove: { [weak self] id in self?.removeActivity(id) }
        )
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
                } else if !inside, self.machine.state == .expanded, self.openedByRequest, self.agents.pending.isEmpty {
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

    /// A Souffleur Col asked to quit has quit: the island says why, the first time.
    private func souffleurQuit() {
        Souffleur.didQuit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated { self?.showSouffleurNoteIfDue() }
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
    /// only when asked, since they change when apps launch or quit rather than with the frontmost app.
    private func measureMenuBar(statusItems: Bool = false) {
        guard let screen, let layout, layout.notch.isHardware else { freeLeft = nil; freeRight = nil; return }
        // `-ColMenuBarFree 132` lends each wing that much room whatever the menu bar holds, so screenshots and films do
        // not depend on the apps of the Mac they are taken on.
        let lent = UserDefaults.standard.double(forKey: "ColMenuBarFree")
        if lent > 0 { freeLeft = lent; freeRight = lent; return }
        let notchLeft = screen.frame.minX + layout.notch.centerX - layout.notch.width / 2
        let notchRight = notchLeft + layout.notch.width
        if statusItems || statusItemsEdge == nil {
            statusItemsEdge = MenuBarSpace.statusItemsLeftEdge(after: notchRight)
        }
        let menus = MenuBarSpace.appMenus(notchCenter: notchLeft + layout.notch.width / 2)
        freeLeft = WingBudget.free(notchEdge: notchLeft, nearestItem: menus?.leftEnd, leftSide: true)
        // On the right, the nearest of the app's overflowing menus and the status items.
        let rightItems = [menus?.rightStart, statusItemsEdge].compactMap { $0 }
        freeRight = WingBudget.free(notchEdge: notchRight, nearestItem: rightItems.min(), leftSide: false)
        if UserDefaults.standard.bool(forKey: "ColDebug") {
            FileHandle.standardError.write(Data("menu bar: app \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") free left \(String(describing: freeLeft)) right \(String(describing: freeRight))\n".utf8))
        }
    }

    /// Spaces and the frontmost app changed: follow the active screen, and step aside in full screen.
    private func environmentChanged() {
        // A copy is often followed by a switch to another app: look at the pasteboard now rather than at the next check.
        if Preferences.keepsClipboardHistory { clipboard.check() }
        // Menus change with the app; let them settle before measuring.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                self?.measureMenuBar()
                self?.refreshActivity()
            }
        }
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
        let visible = !prompterInNotch && (!fullScreenActive || urgent || machine.state == .expanded)
        if visible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
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
        navigation.reloadDeck()
        board.ranking = Preferences.activityRanking
        panel.sharingType = Preferences.hiddenFromScreenCapture ? .none : .readOnly
        islandView.setGlass(Preferences.islandGlass)
        if layout?.size != Preferences.islandSize {
            _ = machine.handle(.dismissed)
            islandView.dismissContent()
            islandView.discardContent()
            // The menu bar has not changed: measuring its status items again would only slow the change down.
            place(measuringStatusItems: false)
        }
        mediaChanged(trackChanged: false)
        agentsChanged()
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
        // Once the user has answered, an island that opened by itself closes by itself.
        if agents.pending.isEmpty, openedByRequest {
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
        api.start()
        clipboard.start()
        extensions.push = { [weak self] request in self?.api.push(request) }
        extensions.remove = { [weak self] id in
            self?.custom.remove(String(id.dropFirst(4)))
            self?.removeActivity(id)
        }
        extensions.reload()
        SettingsWindow.shared.extensions = extensions
        hotKey = HotKey { [weak self] in self?.toggleFromShortcut() }
        if Preferences.hotKeyEnabled { hotKey?.register() }
        if Preferences.watchesDownloads { downloads.start() }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.environmentChanged() }
            })
        }
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
        lockScreen.start()
        if Preferences.showsOnLockScreen { LockScreenSpace.shared?.adopt(panel) }
        if !WelcomeWindow.hasWelcomed { greet() }
        retireSouffleur()
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
        // `-ColDemo souffleur` the note the island gives the first time it closes Souffleur.
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
            if let page = UserDefaults.standard.string(forKey: "ColPage") { navigation.show(page == "live" ? .live : .page(page)) }
            send(.pressed)
        }
    }

    public func stop() {
        PrompterCenter.shared.willTerminate()
        lockScreen.stop()
        media.stop()
        api.stop()
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

        let requested = islandView.compact.wingWidth(for: current?.compact, notchHeight: layout.notch.height)
        // Never over the menu bar: the wings shrink to the free space, or wait in the open island when none is left.
        let newWings = layout.notch.isHardware ? WingBudget.allowed(requested: requested, left: freeLeft, right: freeRight) : Wings(requested)
        let presentation = current?.compact.fitted(to: newWings)
        islandView.showCompact(presentation, wings: newWings)
        shownActivity = current
        if fullScreenActive { updateVisibility() }
        if newWings != wings {
            wings = newWings
            if machine.state != .expanded { reshape(from: machine.state) }
        }
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
            return
        }
        self.screen = screen
        let notch = NotchMetrics.resolve(
            screenWidth: screen.frame.width,
            // `-ColNoNotch YES` draws the floating island even on a notched screen, to work on it.
            safeAreaTop: UserDefaults.standard.bool(forKey: "ColNoNotch") ? 0 : screen.safeAreaInsets.top,
            leftAreaWidth: screen.auxiliaryTopLeftArea?.width,
            rightAreaWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY
        )
        let layout = IslandLayout(notch: notch, size: Preferences.islandSize)
        self.layout = layout
        panel.sharingType = Preferences.hiddenFromScreenCapture ? .none : .readOnly

        let state = machine.state
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
