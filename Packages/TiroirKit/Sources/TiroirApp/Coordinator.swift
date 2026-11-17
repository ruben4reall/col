import AppKit
import SwiftUI
import TiroirCore
import TiroirSystem
import TiroirUI

/// Wires the engine, the settings, the menu bar items, the drawers, search and the windows together (spec 8). Every
/// change of the layout saves the settings and asks the engine to make the menu bar match, once per burst of changes.
/// Triggers reach the engine through the same plan: what they show is planned on top of the layout, which they never
/// rewrite; only a trigger's profile switch changes the settings, as a switch by hand would.
@MainActor
public final class Coordinator {
    public let interface: InterfaceModel
    /// The app target's way to move Tiroir to /Applications (it owns that code).
    public var moveToApplicationsHandler: (() -> Void)?

    private let options: LaunchOptions
    private let store: SettingsStore
    private let engine: MenuBarEngine
    private let directory = AppDirectory()
    private let classifier = Classifier()
    private let statusItems = StatusItemsController()
    private let panels = PanelController()
    private let overlay = TintOverlay()
    private let toast = Toast()
    private let windows = WindowPresenter()
    private let permission = AccessibilityPermission()
    private let appObserver = AppObserver()
    private let displayObserver = DisplayObserver()
    private let reveal = RevealController()
    private let loginItem = LoginItem()
    private let triggerSensors = TriggerSensors()
    private var shortcuts: ShortcutCenter?
    private var updater: UpdateChecking?

    private var snapshot = MenuBarSnapshot.empty
    private var categories: [IconID: CategoryID] = [:]
    /// The person's own mode: Focus or Show Every Icon, which win over triggers.
    private var mode: LayoutPlanner.Mode = .normal {
        didSet { if mode != oldValue { reveal.everythingShows(mode == .showEverything) } }
    }
    /// Which triggers hold, in the order they started.
    private var triggerState = TriggerState()
    /// What the triggers that hold ask of the menu bar.
    private var triggerEffect = TriggerEffect.none
    private var isEvaluatingTriggers = false
    private var saved: TiroirSettings
    private var pendingApply: Task<Void, Never>?
    private var isApplyingNow = false
    private var needsAnotherApply = false
    private var welcome: WelcomeModel?
    private var backdrop: NSWindow?

    public init(options: LaunchOptions, updater: UpdateChecking?) {
        self.options = options
        self.updater = updater
        // Demo mode never reads or writes the person's settings. A suite also searches the app's own domain, so the
        // demo keeps its settings under a key of its own, which the person's settings never have.
        let defaults = options.demo ? (UserDefaults(suiteName: "ch.rubencatalao.tiroir.demo") ?? .standard) : .standard
        if options.demo { defaults.removePersistentDomain(forName: "ch.rubencatalao.tiroir.demo") }
        store = SettingsStore(defaults: defaults, key: options.demo ? "demoSettings" : "settings")
        let loaded = store.load()
        if case .unreadable = loaded.outcome { Log.app.error("settings unreadable: using the defaults") }
        if case .newerVersion(let version) = loaded.outcome { Log.app.error("settings from a newer Tiroir (schema \(version))") }
        saved = loaded.settings
        interface = InterfaceModel(settings: loaded.settings)
        engine = EngineFactory.make(demo: options.demo)
        if options.demo { directory.overrides = DemoEngine.directoryOverrides() }
        windows.isQuiet = options.quiet
        panels.isQuiet = options.quiet
    }

    // MARK: Launch

    public func start() async {
        if options.demo, let path = options.backdrop { backdrop = Backdrop.show(imageAt: path) }
        NSApp.mainMenu = MainMenu.make { [weak self] in self?.openSettings(nil) }
        wireActions()
        wireMenuBar()
        wireReveal()
        shortcuts = ShortcutCenter { [weak self] action in self?.handle(action) }
        permission.onChange = { [weak self] trusted in
            self?.interface.accessibilityTrusted = trusted
            Task { await self?.refresh(apply: true) }
        }
        appObserver.onChange = { [weak self] in Task { await self?.refresh(apply: true) } }
        displayObserver.onChange = { [weak self] in
            guard let self else { return }
            overlay.update(interface.settings.appearance)
            Task { await self.refresh(apply: false) }
        }
        engine.onStatusChange = { [weak self] status in self?.interface.engineStatus = status }
        triggerSensors.onChange = { [weak self] in self?.evaluateTriggers() }
        updater?.start()

        await engine.start()
        interface.engineKind = engine.kind
        interface.engineStatus = engine.status
        interface.accessibilityTrusted = options.demo || permission.isTrusted
        interface.isInApplications = GoldenGateEngine.runsFromApplications()
        interface.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        interface.loginItemStatus = loginItem.status
        interface.iconSpacing = IconSpacing.current()
        interface.automaticUpdates = updater?.automaticallyChecksForUpdates ?? false
        interface.canCheckForUpdates = updater?.canCheckForUpdates ?? false
        applyBehavior()
        syncTriggerSensors()
        evaluateTriggers(apply: false)

        await refresh(apply: interface.settings.hasCompletedWelcome)
        if options.demo, options.welcomeStep == nil, interface.settings.layout.drawers.isEmpty {
            // Demo mode starts sorted, so pictures of drawers and Settings have something to show.
            let layout = propose(.purpose)
            interface.update { settings in
                settings.layout = layout
                settings.hasCompletedWelcome = true
                Self.addDemoProfilesAndTriggers(to: &settings)
            }
        }
        syncChrome()

        if !interface.settings.hasCompletedWelcome || options.welcomeStep != nil {
            showWelcome(step: options.welcomeStep.flatMap(WelcomeModel.Step.init(rawValue:)) ?? .hello)
        }
        if let pane = options.settingsPane { openSettings(pane) }
        if let index = options.openDrawer {
            try? await Task.sleep(for: .milliseconds(500))
            let drawers = interface.settings.layout.drawers
            if index < 0 { openDrawer(.all) } else if drawers.indices.contains(index) { openDrawer(.drawer(drawers[index].id)) }
        }
        if let query = options.search {
            try? await Task.sleep(for: .milliseconds(500))
            openSearch(query: query)
        }
    }

    /// Demo mode's examples: a tinted floating bar, two profiles (the laptop alone, and at a desk), three triggers.
    private static func addDemoProfilesAndTriggers(to settings: inout TiroirSettings) {
        settings.appearance.shape = .floating
        settings.appearance.tint = .gradient
        settings.appearance.border = true
        settings.appearance.shadow = true
        let laptop = settings.saveCurrentAsProfile(named: "Laptop")
        guard let desk = settings.duplicateProfile(laptop, named: "Desk") else { return }
        settings.switchProfile(to: laptop)
        let battery = IconID(bundleID: "com.apple.controlcenter", key: "com.apple.menuextra.battery")
        var triggers = [
            Trigger(condition: .batteryAtOrBelow(20), action: .showIcon(battery)),
            Trigger(condition: .externalDisplay, action: .switchProfile(desk)),
        ]
        if let messages = settings.layout.drawer(for: .messages) {
            triggers.insert(Trigger(condition: .cameraOrMicrophone, action: .showDrawer(messages.id)), at: 1)
        }
        settings.triggers = triggers
    }

    /// On quit: the menu bar goes back to what macOS would show without Tiroir.
    public func shutdown() {
        pendingApply?.cancel()
        panels.close()
        engine.restore()
        statusItems.removeAll()
        overlay.removeAll()
        shortcuts?.unregisterAll()
        triggerSensors.stopAll()
    }

    // MARK: Reading the menu bar

    /// Scans the menu bar, names every icon, places icons Tiroir sees for the first time, and applies the layout if
    /// asked.
    func refresh(apply: Bool) async {
        snapshot = await engine.scan()
        interface.accessibilityTrusted = options.demo || permission.isTrusted
        var rows: [IconRow] = []
        var found: [IconID: CategoryID] = [:]
        for icon in snapshot.icons {
            let bundleID = icon.id.bundleID
            let url = NSRunningApplication(processIdentifier: icon.pid)?.bundleURL
            let info = directory.info(bundleID: bundleID, url: url, fallbackName: icon.ownerName)
            let category: CategoryID
            if icon.kind == .system {
                category = interface.settings.userCategories[bundleID] ?? .system
            } else if options.demo, let demo = DemoEngine.categories[bundleID] {
                category = demo
            } else {
                category = classifier.classify(bundleID: bundleID, name: info.name, appStoreCategory: info.appStoreCategory,
                                               userChoice: interface.settings.userCategories[bundleID])
            }
            found[icon.id] = category
            rows.append(IconRow(
                id: icon.id, name: icon.kind == .system ? icon.displayName : info.name, label: icon.label,
                appName: info.name, appIcon: icon.kind == .system ? SystemIcons.image(for: icon.id) : info.icon,
                category: category, developer: info.developer, kind: icon.kind, isMovable: icon.isMovable, frame: icon.frame))
        }
        categories = found
        interface.icons = rows
        rememberNewIcons()
        updateCapacity()
        syncStatusItems()
        measureIcons()
        reveal.watcher.occupied = occupiedFrames()
        if apply { scheduleApply() }
    }

    /// Tells the tint where the icons start on each display, for its split shape: the left edge of the leftmost icon
    /// that shows there, Tiroir's own included. Demo icons are made up and measure nothing, and Tiroir's own items alone
    /// say nothing of where the other apps' icons start.
    private func measureIcons() {
        var starts: [CGDirectDisplayID: CGFloat] = [:]
        if !options.demo {
            let others = snapshot.icons.filter(\.isOnScreen).map { ScreenCoordinates.appKitRect(fromWindowServer: $0.frame) }
            let own = statusItems.itemFrames
            for screen in NSScreen.screens {
                let bar = screen.menuBarFrame
                guard let id = screen.displayID, let start = TintGeometry.statusStart(of: others, in: bar) else { continue }
                starts[id] = min(start, TintGeometry.statusStart(of: own, in: bar) ?? start)
            }
        }
        overlay.update(statusStarts: starts)
    }

    /// Icons seen for the first time take the place the new icon policy gives them, and keep it: a later change of
    /// the policy never reshuffles the menu bar.
    private func rememberNewIcons() {
        guard interface.settings.hasCompletedWelcome else { return }
        let newcomers = interface.icons.filter { $0.isMovable && !interface.settings.layout.knows($0.id) }
        guard !newcomers.isEmpty else { return }
        interface.update { settings in
            for row in newcomers {
                settings.layout.assign(row.id, to: settings.layout.placement(of: row.id, category: row.category))
            }
        }
    }

    private func updateCapacity() {
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
        guard let screen else { return }
        let hasNotch = screen.safeAreaInsets.top > 0
        interface.hasNotch = hasNotch
        let room: CGFloat
        if hasNotch, let right = screen.auxiliaryTopRightArea {
            room = right.width
        } else {
            // Without a notch, the app menus on the left take roughly half of the bar.
            room = screen.frame.width * 0.5
        }
        var items = interface.menuBarRows.map { NotchCapacity.Item(id: $0.id, width: max($0.frame.width, 24)) }
        let own = interface.settings.layout.drawers.map { NotchCapacity.Item(id: IconID(bundleID: TiroirInfo.bundleIdentifier, key: $0.id.uuidString), width: 30) }
        items.append(contentsOf: own)
        if interface.settings.behavior.showsTiroirIcon {
            items.append(NotchCapacity.Item(id: IconID(bundleID: TiroirInfo.bundleIdentifier, key: "main"), width: 30))
        }
        let capacity = NotchCapacity.evaluate(room: room, items: items)
        interface.capacity = capacity
        // Automatic only in the ordinary menu bar, never while every icon shows or Focus is on.
        if interface.settings.behavior.movesOverflowAutomatically, interface.settings.hasCompletedWelcome, mode == .normal,
           !capacity.fits {
            interface.moveOverflowIntoDrawer()
        }
    }

    // MARK: Making the menu bar match

    /// Arranges after `delay`; a new request before then replaces this one. Once it runs, an arrangement is never
    /// cancelled: its waits would all return at once and every drop would be judged before the menu bar settles. A
    /// request that comes meanwhile runs right after it.
    func scheduleApply(after delay: Duration = .milliseconds(350)) {
        pendingApply?.cancel()
        let task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.pendingApply = nil
            await self.applyNow()
        }
        pendingApply = task
    }

    @discardableResult
    func applyNow() async -> ApplyReport {
        if isApplyingNow {
            needsAnotherApply = true
            return .nothing
        }
        isApplyingNow = true
        defer { isApplyingNow = false }
        var report = ApplyReport.nothing
        repeat {
            needsAnotherApply = false
            let planning = self.planning
            let plan = LayoutPlanner.plan(layout: interface.settings.layout, snapshot: snapshot, granularity: engine.granularity,
                                          categories: categories, mode: planning.mode, shownIcons: planning.icons,
                                          shownDrawers: planning.drawers)
            interface.isApplying = true
            report = await engine.apply(plan)
            interface.isApplying = false
            interface.failedMoves = report.failed
            interface.conflicts = plan.conflicts
            if !report.moved.isEmpty { await refresh(apply: false) }
        } while needsAnotherApply
        // The engine asked to try again: once the person pauses, or a while after a move failed.
        if let wait = report.tryAgainIn { scheduleApply(after: wait) }
        return report
    }

    // MARK: Menu bar items and chrome

    private func wireMenuBar() {
        statusItems.onOpen = { [weak self] target in self?.openDrawer(target) }
        statusItems.onShowEverything = { [weak self] in
            guard let self, interface.settings.behavior.showsEverythingWithOption else { return }
            toggleShowEverything()
        }
        statusItems.menuFor = { [weak self] target in self?.menu(for: target) ?? NSMenu() }
    }

    private func syncStatusItems() {
        let layout = interface.settings.layout
        var counts: [UUID: Int] = [:]
        for drawer in layout.drawers { counts[drawer.id] = interface.members(of: drawer.id).count }
        // A trigger's Focus shows like the person's own: the moon, and no drawer.
        let planned = planning.mode
        statusItems.update(drawers: layout.drawers, counts: counts, showsMain: interface.settings.behavior.showsTiroirIcon,
                           isFocusOn: planned == .focus, isShowingEverything: planned == .showEverything,
                           keepsAtRightEnd: interface.settings.behavior.keepsItemsAtRightEnd)
    }

    /// What the planner is given: the person's mode, or the triggers' Focus and shown icons when the person has none.
    private var planning: TriggerEffect.Planning {
        triggerEffect.planning(over: mode)
    }

    private func syncChrome() {
        syncStatusItems()
        overlay.update(interface.settings.appearance)
        registerShortcuts()
    }

    private func applyBehavior() {
        let behavior = interface.settings.behavior
        statusItems.hoverDelay = behavior.opensOnHover ? behavior.hoverDelay : nil
        (engine as? TahoeEngine)?.rehideDelay = behavior.rehideDelay
        (engine as? GoldenGateEngine)?.rehideDelay = behavior.rehideDelay
        reveal.configure(behavior)
    }

    private func registerShortcuts() {
        guard let shortcuts else { return }
        let refused = shortcuts.apply(ShortcutCenter.wanted(from: interface.settings))
        interface.refusedShortcuts = Set(refused.map { action in
            switch action {
            case .search: "search"
            case .allDrawer: "allDrawer"
            case .focus: "focus"
            case .showEverything: "showEverything"
            case .drawer(let id): id.uuidString
            case .profile(let id): id.uuidString
            case .icon(let id): "icon:\(id.description)"
            }
        })
    }

    private func handle(_ action: ShortcutCenter.Action) {
        switch action {
        case .search: openSearch()
        case .allDrawer: openDrawer(.all)
        case .focus: toggleFocus()
        case .showEverything: toggleReveal()
        case .drawer(let id): openDrawer(.drawer(id))
        case .profile(let id): switchProfile(to: id)
        case .icon(let id): open(id, from: drawerTarget(of: id))
        }
    }

    private func menu(for target: StatusItemsController.Target) -> NSMenu {
        let menu = NSMenu()
        if case .drawer(let id) = target {
            menu.addItem(ActionItem(title: Strings.editDrawerMenuItem) { [weak self] in
                self?.interface.selectedDrawer = id
                self?.openSettings(.drawers)
            })
            menu.addItem(.separator())
        }
        let search = ActionItem(title: Strings.searchIconsMenuItem) { [weak self] in self?.openSearch() }
        menu.addItem(search)
        menu.addItem(ActionItem(title: mode == .showEverything ? Strings.hideThemAgain : Strings.showEveryIcon) { [weak self] in
            self?.toggleShowEverything()
        })
        menu.addItem(ActionItem(title: mode == .focus ? Strings.endFocus : Strings.focus) { [weak self] in self?.toggleFocus() })
        if !interface.settings.profiles.isEmpty { menu.addItem(profilesItem()) }
        menu.addItem(.separator())
        menu.addItem(ActionItem(title: Strings.settingsMenuItem) { [weak self] in self?.openSettings(nil) })
        if updater != nil {
            menu.addItem(ActionItem(title: Strings.checkForUpdates) { [weak self] in self?.updater?.checkForUpdates() })
        }
        menu.addItem(.separator())
        menu.addItem(ActionItem(title: Strings.quitTiroir) { NSApp.terminate(nil) })
        return menu
    }

    /// The profiles, the active one checked; choosing one switches to it.
    private func profilesItem() -> NSMenuItem {
        let submenu = NSMenu(title: Strings.profilesMenu)
        for profile in interface.settings.profiles {
            let item = ActionItem(title: Strings.name(of: profile)) { [weak self] in self?.switchProfile(to: profile.id) }
            item.state = profile.id == interface.settings.activeProfile ? .on : .off
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: Strings.profilesMenu, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    // MARK: Drawers, search, icons

    func openDrawer(_ target: StatusItemsController.Target) {
        if panels.isOpen, panels.openTarget == target {
            panels.close()
            return
        }
        guard let anchor = statusItems.anchor(for: target) ?? (target == .all ? statusItems.fallbackAnchor() : nil) else { return }
        let view = DrawerView(model: interface, target: target, onOpen: { [weak self] id in
            self?.open(id, from: target)
        }, onClose: { [weak self] in self?.panels.close() })
        panels.show(view, under: anchor.appKit, target: target)
        // The drawer shows at once; a fresh scan follows, and the panel updates by itself.
        Task { await refresh(apply: false) }
    }

    func openSearch(query: String = "") {
        if panels.isSearchOpen {
            panels.close()
            return
        }
        let view = SearchView(model: interface, initialQuery: query, onOpen: { [weak self] id in
            guard let self else { return }
            open(id, from: drawerTarget(of: id))
        }, onClose: { [weak self] in self?.panels.close() })
        panels.showCentered(view, width: 560)
    }

    func open(_ id: IconID, from target: StatusItemsController.Target?) {
        panels.close()
        let anchor = target.flatMap { statusItems.anchor(for: $0) }
        Task {
            do {
                try await engine.open(id, anchor: anchor?.windowServer)
            } catch EngineError.personIsBusy {
                // The person kept moving: better not to interfere.
            } catch EngineError.notReady(.needsAccessibility) {
                toast.show(Strings.needsAccessibilityToOpen, near: anchor?.appKit)
            } catch {
                toast.show(Strings.couldNotOpen(interface.row(id)?.name ?? id.bundleID), near: anchor?.appKit)
            }
        }
    }

    func toggleFocus() {
        mode = mode == .focus ? .normal : .focus
        interface.isFocusOn = mode == .focus
        interface.isShowingEverything = false
        evaluateTriggers(apply: false)
        syncStatusItems()
        Task { await applyNow() }
    }

    func toggleShowEverything() {
        mode = mode == .showEverything ? .normal : .showEverything
        interface.isShowingEverything = mode == .showEverything
        interface.isFocusOn = false
        evaluateTriggers(apply: false)
        syncStatusItems()
        Task { await applyNow() }
    }

    // MARK: Profiles

    /// Switches to a profile by hand, from Settings, Tiroir's menu or a shortcut. The person's own Focus or Show Every
    /// Icon ends, and the menu bar follows at once, the way a Smart Sort result applies.
    func switchProfile(to id: UUID) {
        guard interface.settings.profile(id) != nil else { return }
        mode = .normal
        interface.isFocusOn = false
        interface.isShowingEverything = false
        interface.update { $0.switchProfile(to: id) }
        evaluateTriggers(apply: false)
        applyAfterProfileSwitch()
    }

    /// Makes the menu bar match a profile that was just switched to, without waiting for the burst of changes to end.
    private func applyAfterProfileSwitch() {
        pendingApply?.cancel()
        syncStatusItems()
        updateCapacity()
        guard interface.settings.hasCompletedWelcome else { return }
        Task { await applyNow() }
    }

    // MARK: Triggers

    /// Starts the sensors the enabled triggers need and stops the others: with no trigger, none runs.
    private func syncTriggerSensors() {
        let triggers = interface.settings.triggers
        triggerSensors.watch(TriggerSchedule.needs(of: triggers), boundaries: TriggerSchedule.boundaries(of: triggers))
    }

    /// Evaluates the triggers against what the sensors see: marks those that hold, takes in a change of profile and
    /// the memory for next time, and, when `apply` allows, makes the menu bar follow.
    private func evaluateTriggers(apply: Bool = true) {
        guard !isEvaluatingTriggers else { return }
        isEvaluatingTriggers = true
        defer { isEvaluatingTriggers = false }
        let outcome = TriggerEvaluator.evaluate(interface.settings, facts: triggerSensors.facts(), state: triggerState,
                                                isSuspended: mode != .normal)
        triggerState = outcome.state
        if interface.activeTriggers != outcome.active { interface.activeTriggers = outcome.active }
        interface.update { $0.apply(outcome) }
        let effectChanged = outcome.effect != triggerEffect
        triggerEffect = outcome.effect
        guard apply else { return }
        if outcome.profileChange != nil {
            applyAfterProfileSwitch()
        } else if effectChanged {
            syncStatusItems()
            if interface.settings.hasCompletedWelcome { scheduleApply() }
        }
    }

    /// The drawer an icon opens from: its own, the All drawer for a hidden icon, none in the menu bar.
    private func drawerTarget(of id: IconID) -> StatusItemsController.Target? {
        guard let row = interface.row(id) else { return nil }
        switch interface.placement(of: row) {
        case .drawer(let drawer): return .drawer(drawer)
        case .hidden: return .all
        case .menuBar: return nil
        }
    }

    // MARK: Show every icon from the menu bar

    private func wireReveal() {
        reveal.onReveal = { [weak self] in self?.revealEveryIcon() }
        reveal.onToggle = { [weak self] in self?.toggleReveal() }
        reveal.onHideAgain = { [weak self] in
            guard let self, mode == .showEverything else { return }
            toggleShowEverything()
        }
    }

    /// Shows every icon where the person chose, unless they already show. Focus keeps the menu bar quiet.
    private func revealEveryIcon() {
        guard mode != .focus else { return }
        switch interface.settings.behavior.revealPlace {
        case .menuBar:
            if mode != .showEverything { toggleShowEverything() }
        case .allDrawer:
            if !(panels.isOpen && panels.openTarget == .all) { openDrawer(.all) }
        }
    }

    /// Shows every icon, or hides them again.
    private func toggleReveal() {
        guard mode != .focus else { return }
        switch interface.settings.behavior.revealPlace {
        case .menuBar: toggleShowEverything()
        case .allDrawer: openDrawer(.all)
        }
    }

    /// Everything on the menu bar that is not empty room, in AppKit coordinates.
    private func occupiedFrames() -> [CGRect] {
        snapshot.icons.filter(\.isOnScreen).map { ScreenCoordinates.appKitRect(fromWindowServer: $0.frame) } + statusItems.itemFrames
    }

    // MARK: Windows

    func openSettings(_ pane: SettingsPane?) {
        panels.close()
        windows.showSettings(model: interface, pane: pane)
    }

    func showWelcome(step: WelcomeModel.Step) {
        let model = WelcomeModel(step: step)
        model.proposal = propose(interface.settings.sortStrategy)
        welcome = model
        windows.showWelcome(model: interface, welcomeModel: model) { [weak self] in self?.finishWelcome() }
    }

    private func finishWelcome() {
        interface.update { $0.hasCompletedWelcome = true }
        welcome = nil
        scheduleApply(after: .milliseconds(50))
    }

    // MARK: Settings changes

    private func settingsChanged(_ settings: TiroirSettings) {
        let previous = saved
        saved = settings
        store.save(settings)
        if settings.layout != previous.layout || settings.userCategories != previous.userCategories {
            if settings.userCategories != previous.userCategories {
                Task { await refresh(apply: true) }
            } else {
                syncStatusItems()
                updateCapacity()
                if settings.hasCompletedWelcome { scheduleApply() }
            }
        }
        if settings.appearance != previous.appearance { overlay.update(settings.appearance) }
        if settings.behavior != previous.behavior {
            applyBehavior()
            syncStatusItems()
            updateCapacity()
        }
        if ShortcutCenter.wanted(from: settings) != ShortcutCenter.wanted(from: previous) {
            registerShortcuts()
        }
        if settings.triggers != previous.triggers { syncTriggerSensors() }
        // Whether a trigger can act depends on the profiles and drawers that exist, and a profile switched by hand
        // overrules the triggers holding.
        if settings.triggers != previous.triggers || settings.activeProfile != previous.activeProfile
            || settings.profiles.map(\.id) != previous.profiles.map(\.id)
            || settings.layout.drawers.map(\.id) != previous.layout.drawers.map(\.id) {
            evaluateTriggers()
        }
    }

    func propose(_ strategy: SortStrategy) -> TiroirCore.Layout {
        let inputs = interface.icons.compactMap { row -> ProposalInput? in
            guard let icon = snapshot.icon(row.id) else { return nil }
            return ProposalInput(icon: icon, category: row.category, developer: row.developer)
        }
        return SmartSort.propose(inputs, strategy: strategy, pinned: interface.settings.pinned, names: Strings.categoryName,
                                 everythingName: Strings.allIcons, previous: interface.settings.layout)
    }

    private func applySmartSort(_ layout: TiroirCore.Layout, strategy: SortStrategy) async -> ApplyReport {
        interface.update { settings in
            settings.layout = layout
            settings.sortStrategy = strategy
        }
        pendingApply?.cancel()
        mode = .normal
        interface.isFocusOn = false
        interface.isShowingEverything = false
        evaluateTriggers(apply: false)
        syncStatusItems()
        return await applyNow()
    }

    /// A settings file replaces the current setup; the menu bar follows at once.
    private func importSettings(_ imported: TiroirSettings) {
        var settings = imported
        settings.hasCompletedWelcome = true
        mode = .normal
        interface.isFocusOn = false
        interface.isShowingEverything = false
        interface.update { $0 = settings }
        syncChrome()
        scheduleApply(after: .milliseconds(50))
    }

    private func resetLayout() {
        store.reset()
        mode = .normal
        let fresh = TiroirSettings.defaults
        saved = fresh
        interface.settings = fresh
        interface.isFocusOn = false
        interface.isShowingEverything = false
        triggerState = TriggerState()
        triggerEffect = .none
        interface.activeTriggers = []
        syncTriggerSensors()
        syncChrome()
        Task {
            _ = await engine.apply(.showEverything)
            windows.closeAll()
            showWelcome(step: .hello)
        }
    }

    // MARK: Actions for the interface

    private func wireActions() {
        var actions = InterfaceActions()
        actions.updateSettings = { [weak self] settings in self?.settingsChanged(settings) }
        actions.openIcon = { [weak self] id, drawer in self?.open(id, from: drawer.map { .drawer($0) }) }
        actions.propose = { [weak self] strategy in self?.propose(strategy) ?? .empty }
        actions.applySmartSort = { [weak self] layout, strategy in await self?.applySmartSort(layout, strategy: strategy) ?? .nothing }
        actions.requestAccessibility = { [weak self] in self?.permission.request(); self?.permission.waitForGrant() }
        actions.openAccessibilitySettings = { [weak self] in self?.permission.openSettings() }
        actions.moveToApplications = { [weak self] in self?.moveToApplicationsHandler?() }
        actions.setOpenAtLogin = { [weak self] enabled in
            guard let self else { return }
            do { try loginItem.setEnabled(enabled) } catch { Log.app.error("login item: \(error.localizedDescription, privacy: .public)") }
            interface.loginItemStatus = loginItem.status
        }
        actions.setAutomaticUpdates = { [weak self] enabled in
            self?.updater?.automaticallyChecksForUpdates = enabled
            self?.interface.automaticUpdates = enabled
        }
        actions.checkForUpdates = { [weak self] in self?.updater?.checkForUpdates() }
        actions.toggleFocus = { [weak self] in self?.toggleFocus() }
        actions.toggleShowEverything = { [weak self] in self?.toggleShowEverything() }
        actions.resetLayout = { [weak self] in self?.resetLayout() }
        actions.retry = { [weak self] in Task { await self?.engine.start(); await self?.refresh(apply: true) } }
        actions.openSettings = { [weak self] pane in self?.openSettings(pane) }
        actions.finishWelcome = { [weak self] in self?.finishWelcome() }
        actions.showInFinder = { [weak self] id in
            guard let self, let row = interface.row(id),
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: row.id.bundleID) else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        actions.refreshMemory = { [weak self] in self?.interface.memoryBytes = MemoryUse.footprintBytes() }
        actions.quit = { NSApp.terminate(nil) }
        actions.switchProfile = { [weak self] id in self?.switchProfile(to: id) }
        actions.exportSettings = { [weak self] in
            guard let self else { return }
            SettingsFile.export(interface.settings)
        }
        actions.importSettings = { [weak self] in
            guard let settings = SettingsFile.chooseAndRead() else { return }
            self?.importSettings(settings)
        }
        actions.showWelcomeAgain = { [weak self] in
            self?.windows.closeAll()
            self?.showWelcome(step: .hello)
        }
        actions.setIconSpacing = { [weak self] spacing in
            guard let self, spacing != interface.iconSpacing else { return }
            // Demo mode never writes outside its own settings.
            if !options.demo { spacing.apply() }
            interface.iconSpacing = spacing
            interface.iconSpacingChanged = true
        }
        actions.copyDiagnostics = { [weak self] in
            guard let self else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(Diagnostics.report(interface: interface, engine: engine, snapshot: snapshot), forType: .string)
            toast.show(Strings.diagnosticsCopied, near: nil)
        }
        interface.actions = actions
    }
}
