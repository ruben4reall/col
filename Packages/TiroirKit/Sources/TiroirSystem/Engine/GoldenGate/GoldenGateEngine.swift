import AppKit
import TiroirCore

/// The macOS 27 engine (spec 4.4): MenuBarAgent's restriction shows every app except the hidden ones. Nothing ever
/// moves, the pointer included; an icon opened from a drawer is let through the restriction for the time its menu is
/// open.
@available(macOS 26, *)
@MainActor
public final class GoldenGateEngine: MenuBarEngine {
    public let kind = EngineKind.goldenGate
    public let granularity = Granularity.app
    public private(set) var status: EngineStatus = .ready {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }
    public var onStatusChange: (@MainActor (EngineStatus) -> Void)?
    public var rehideDelay: TimeInterval = 0.5

    private let icons: IconSource
    private let restriction: RestrictionControlling
    private let windows: StatusWindowSource
    private let clock: ClockZoneGuard
    private let isInApplications: @MainActor () -> Bool
    private let runningBundleIDs: @MainActor () -> [String]
    private let frontmostBundleID: @MainActor () -> String?
    private let readAgent: @Sendable () async -> AgentLayout?
    private let readSettled: @Sendable (AgentLayout?) async -> AgentLayout?
    private let pause: @Sendable (Duration) async -> Void

    private var hiddenApps: Set<String> = []
    private var knownIcons: [IconID: MenuBarIcon] = [:]
    private var pressers: [IconID: @Sendable () -> Bool] = [:]
    private var lastAgent: AgentLayout?
    private var shown: (bundleID: String, task: Task<Void, Never>)?
    private var clockOpen = false
    /// Set by `restore()`: no restriction, no watch of the clock and no opening until `start()` again.
    public private(set) var isRestored = false

    /// Apple's agents that host system icons: MenuBarAgent addresses them by bundle identifier and some of them
    /// break when left out (Notification Center, the input menu). They always show.
    public static let alwaysAllowed: Set<String> = [
        "com.apple.controlcenter", "com.apple.MenuBarAgent", "com.apple.systemuiserver", "com.apple.TextInputMenuAgent",
        "com.apple.Siri", "com.apple.Spotlight", "com.apple.wifi.WiFiAgent", "com.apple.ScreenTimeAgent",
        "com.apple.AirPlayUIAgent", "com.apple.UserNotificationCenter", "com.apple.notificationcenterui",
        "com.apple.loginwindow", "com.apple.dock",
    ]

    public init(
        icons: IconSource, restriction: RestrictionControlling = MenuBarRestriction(),
        windows: StatusWindowSource = SystemStatusWindows(), clock: ClockZoneGuard = ClockZoneGuard(),
        isInApplications: @escaping @MainActor () -> Bool = { GoldenGateEngine.runsFromApplications() },
        frontmostBundleID: @escaping @MainActor () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier },
        runningBundleIDs: @escaping @MainActor () -> [String] = {
            NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        },
        readAgent: @escaping @Sendable () async -> AgentLayout? = { await AgentReader.readInBackground() },
        readSettled: @escaping @Sendable (AgentLayout?) async -> AgentLayout? = { await AgentReader.readSettled(after: $0) },
        pause: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.icons = icons
        self.restriction = restriction
        self.windows = windows
        self.clock = clock
        self.isInApplications = isInApplications
        self.runningBundleIDs = runningBundleIDs
        self.frontmostBundleID = frontmostBundleID
        self.readAgent = readAgent
        self.readSettled = readSettled
        self.pause = pause
        watchTheClock()
    }

    private func watchTheClock() {
        clock.onChange = { [weak self] over in self?.clockChanged(over) }
    }

    isolated deinit {
        shown?.task.cancel()
        clock.onChange = nil
        clock.stop()
        restriction.release()
    }

    /// MenuBarAgent matches its allow list only against apps in /Applications: a copy anywhere else hides itself.
    public static func runsFromApplications() -> Bool {
        Bundle.main.bundleURL.deletingLastPathComponent().path == "/Applications"
    }

    public func start() async {
        isRestored = false
        watchTheClock()
        refreshStatus()
    }

    func refreshStatus() {
        if !restriction.isAvailable {
            status = .unavailable("MenuBarClientCore")
        } else if !icons.isTrusted {
            status = .needsAccessibility
        } else if !isInApplications() {
            status = .needsApplicationsFolder
        } else {
            status = .ready
        }
        if status != .ready {
            restriction.release()
            clock.stop()
        }
    }

    // MARK: Scanning

    public func scan() async -> MenuBarSnapshot {
        refreshStatus()
        guard status == .ready || status == .needsApplicationsFolder else { return .empty }
        let agent = await readAgent()
        let found = Self.adding(agent, to: await icons.find())
        lastAgent = agent
        let running = Set(runningBundleIDs())

        var result: [IconID: MenuBarIcon] = [:]
        var presses: [IconID: @Sendable () -> Bool] = [:]
        for entry in IconAssembly.identify(found) {
            let bundleID = entry.id.bundleID
            let kind = IconAssembly.kind(of: bundleID)
            let drawn = agent?.drawnItem(of: bundleID)
            let icon = MenuBarIcon(
                id: entry.id, ownerName: entry.found.app.name,
                label: IconAssembly.displayLabel(entry.found.label, kind: kind),
                frame: drawn?.frame ?? entry.found.frame, isOnScreen: drawn != nil,
                isMovable: !Self.alwaysAllowed.contains(bundleID) && !IconIdentity.fixedSystemIdentifiers.contains(entry.id.key),
                kind: kind, pid: entry.found.app.pid)
            result[entry.id] = icon
            if let element = drawn?.element {
                presses[entry.id] = { element.press() }
            } else {
                presses[entry.id] = entry.found.press
            }
        }
        // Apps hidden by the restriction may not describe their icon: keep what Tiroir saw of them while they run.
        for (id, icon) in knownIcons where result[id] == nil && running.contains(id.bundleID) && hiddenApps.contains(id.bundleID) {
            var hidden = icon
            hidden.isOnScreen = false
            result[id] = hidden
        }
        knownIcons = result
        pressers = presses
        return MenuBarSnapshot(icons: Array(result.values))
    }

    /// What apps say over Accessibility, completed with what MenuBarAgent draws. On macOS 27.2 most apps no longer
    /// describe their icons themselves (no `AXExtrasMenuBar`): MenuBarAgent's slots are the only place they show, with
    /// the app's process and its button. Apple's own items come from MenuBarAgent's own description, already found.
    static func adding(_ agent: AgentLayout?, to found: [FoundIcon], ownPID: pid_t = getpid()) -> [FoundIcon] {
        guard let agent else { return found }
        let described = Set(found.map(\.app.bundleID))
        var result = found
        // Each display has its own bar with every app on it: an app's icons are counted on the first bar that has them.
        var taken = Set<String>()
        for display in agent.displays {
            let apps = Set(display.items.filter { $0.pid != ownPID }.compactMap(\.bundleID)).subtracting(described).subtracting(taken)
            taken.formUnion(apps)
            for item in display.items where !item.isOverflowButton && item.pid != ownPID {
                guard let bundleID = item.bundleID, apps.contains(bundleID) else { continue }
                let running = NSRunningApplication(processIdentifier: item.pid)
                let app = RunningApp(pid: item.pid, bundleID: bundleID, name: running?.localizedName ?? bundleID,
                                     bundleURL: running?.bundleURL)
                let element = item.element
                result.append(FoundIcon(app: app, frame: item.frame, identifier: item.identifier, label: item.label,
                                        press: { element?.press() ?? false }))
            }
        }
        return result
    }

    // MARK: Hiding

    public func apply(_ plan: VisibilityPlan) async -> ApplyReport {
        hiddenApps = plan.hiddenApps.subtracting(Self.alwaysAllowed)
        refreshStatus()
        guard status == .ready else { return .nothing }
        if clockOpen { return ApplyReport(moved: plan.concealed.sorted()) }
        return await enforce(hiding: hiddenApps)
    }

    /// Holds a restriction that hides `apps`, or none when there is nothing to hide (no side effects then).
    private func enforce(hiding apps: Set<String>) async -> ApplyReport {
        guard !isRestored else { return .nothing }
        guard !apps.isEmpty else {
            restriction.release()
            clock.stop()
            return .nothing
        }
        let own = Bundle.main.bundleIdentifier.map { [$0] } ?? []
        let allowed = Set(runningBundleIDs()).subtracting(apps).union(Self.alwaysAllowed).union(own).sorted()
        let error = await restriction.apply(allowed: allowed)
        // Restored while MenuBarAgent answered, or the request was released meanwhile: nothing more is held or watched.
        if isRestored || (error as? RestrictionError) == .cancelled {
            if isRestored { restriction.release() }
            return .nothing
        }
        if let error {
            Log.engine.error("restriction refused: \(String(describing: error), privacy: .public)")
            return ApplyReport(failed: apps.sorted().map { IconID(bundleID: $0) })
        }
        clock.clockFrame = lastAgent?.clockFrame
        clock.start()
        return ApplyReport(moved: apps.sorted().map { IconID(bundleID: $0) })
    }

    private func clockChanged(_ over: Bool) {
        guard !isRestored else { return }
        clockOpen = over
        if over {
            restriction.release()
        } else {
            Task { _ = await enforce(hiding: hiddenApps) }
        }
    }

    // MARK: Opening

    public func open(_ id: IconID, anchor: CGRect?) async throws {
        guard status == .ready else { throw EngineError.notReady(status) }
        let bundleID = id.bundleID
        shown?.task.cancel()
        shown = nil
        if let presser = pressers[id], let agent = await readAgent(), agent.drawnItem(of: bundleID) != nil {
            Log.engine.notice("open: \(bundleID, privacy: .public) already shows")
            _ = presser()
            return
        }
        Log.engine.notice("open: letting \(bundleID, privacy: .public) through")
        // Let the app through, wait for MenuBarAgent to lay the bar out, then press its icon.
        let before = await readAgent()
        _ = await enforce(hiding: hiddenApps.subtracting([bundleID]))
        var agent = await waitUntilDrawn(bundleID, after: await readSettled(before))
        guard !isRestored else { throw EngineError.notReady(status) }
        if agent?.drawnItem(of: bundleID) == nil {
            Log.engine.notice("open: \(bundleID, privacy: .public) not drawn, \(Self.describe(agent, bundleID), privacy: .public); showing it alone")
            // Beside the notch, the icon may not fit: show only this app for the time its menu is open.
            let others = Set(runningBundleIDs()).subtracting(Self.alwaysAllowed).subtracting([bundleID])
            _ = await enforce(hiding: others.subtracting(Bundle.main.bundleIdentifier.map { [$0] } ?? []))
            agent = await waitUntilDrawn(bundleID, after: await readSettled(agent))
            guard !isRestored else { throw EngineError.notReady(status) }
        }
        // MenuBarAgent's slot presses the icon where it is drawn; the app's own element is the fallback. What the press
        // opens is what the app raises on top of the windows it had just before.
        guard let item = agent?.drawnItem(of: bundleID) else {
            Log.engine.error("open: \(bundleID, privacy: .public) never drawn, \(Self.describe(agent, bundleID), privacy: .public)")
            _ = await enforce(hiding: hiddenApps)
            throw EngineError.cannotOpen(id)
        }
        var owners: Set<pid_t> = [item.pid]
        if let agentPID = lastAgent?.agentPID { owners.insert(agentPID) }
        let raised = windows.raisedWindows(ownerPIDs: owners)
        guard item.element?.press() == true || pressers[id]?() == true else {
            Log.engine.error("open: \(bundleID, privacy: .public) refused the press")
            _ = await enforce(hiding: hiddenApps)
            throw EngineError.cannotOpen(id)
        }
        Log.engine.notice("open: pressed \(bundleID, privacy: .public) at x \(Int(item.frame.minX))")
        watchUntilClosed(bundleID: bundleID, owners: owners, opened: raised)
    }

    /// Where MenuBarAgent has an app's icon, for the log: its slot, or none.
    static func describe(_ layout: AgentLayout?, _ bundleID: String) -> String {
        guard let layout else { return "MenuBarAgent unread" }
        let items = layout.displays.flatMap(\.items)
        let slots = items.filter { $0.bundleID == bundleID }.map { "x \(Int($0.frame.minX)) w \(Int($0.frame.width))" }
        let overflow = items.first(where: \.isOverflowButton).map { ", » at x \(Int($0.frame.minX))" } ?? ""
        return (slots.isEmpty ? "no slot" : "slot " + slots.joined(separator: ", ")) + overflow
    }

    /// MenuBarAgent lays the bar out at once when the restriction changes, but an app let through draws its icon a
    /// moment later: about half a second on macOS 27.2, longer for a busy app. Reads until the icon is drawn twice at
    /// the same place, for 1.5 seconds at most.
    private func waitUntilDrawn(_ bundleID: String, after settled: AgentLayout?, attempts: Int = 12) async -> AgentLayout? {
        var last = settled
        var previous = settled?.drawnItem(of: bundleID)?.frame
        for _ in 0..<attempts {
            if let frame = last?.drawnItem(of: bundleID)?.frame, frame == previous { return last }
            previous = last?.drawnItem(of: bundleID)?.frame
            await pause(.milliseconds(120))
            last = await readAgent() ?? last
        }
        return last
    }

    private func watchUntilClosed(bundleID: String, owners: Set<pid_t>, opened before: Set<UInt32>) {
        let task = Task { [weak self] in
            guard let self else { return }
            await self.pause(.milliseconds(400))
            var closedSince: ContinuousClock.Instant?
            let started = ContinuousClock.now
            while !Task.isCancelled {
                // A menu, a popover or a panel; or, seen with Google Drive on macOS 27.2, an ordinary window that makes
                // the app the one in front: its icon stays while the app does.
                let open = !self.windows.raisedWindows(ownerPIDs: owners).subtracting(before).isEmpty
                    || self.frontmostBundleID() == bundleID
                if open {
                    closedSince = nil
                } else if let since = closedSince {
                    if ContinuousClock.now - since >= .milliseconds(Int(self.rehideDelay * 1000)) { break }
                } else {
                    closedSince = .now
                }
                if ContinuousClock.now - started > .seconds(600) { break }
                await self.pause(.milliseconds(250))
            }
            guard !Task.isCancelled, !self.isRestored else { return }
            Log.engine.notice("open: \(bundleID, privacy: .public) closed, hidden again")
            self.shown = nil
            _ = await self.enforce(hiding: self.hiddenApps)
        }
        shown = (bundleID, task)
    }

    // MARK: Quitting

    public func restore() {
        isRestored = true
        shown?.task.cancel()
        shown = nil
        // Stopped without a word: leaving the clock would otherwise put the restriction back.
        clock.onChange = nil
        clock.stop()
        clockOpen = false
        restriction.release()
    }
}
