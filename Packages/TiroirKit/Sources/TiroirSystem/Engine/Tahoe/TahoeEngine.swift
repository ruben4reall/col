import AppKit
import TiroirCore

/// The macOS 26 engine (spec 4.3): Tiroir's divider pushes concealed icons off screen; synthetic Command-drags carry
/// icons across it; an icon opened from a drawer is brought next to the drawer's mark for the time its menu is open.
@MainActor
public final class TahoeEngine: MenuBarEngine {
    public let kind = EngineKind.tahoe
    public let granularity = Granularity.icon
    public private(set) var status: EngineStatus = .ready {
        didSet { if status != oldValue { onStatusChange?(status) } }
    }
    public var onStatusChange: (@MainActor (EngineStatus) -> Void)?
    /// How long an icon opened from a drawer stays after its menu closes.
    public var rehideDelay: TimeInterval = 0.5

    private let icons: IconSource
    private let windows: StatusWindowSource
    private let mover: ItemMover
    private let poster: EventPosting
    private let activity: UserActivitySource
    private let makeDivider: @MainActor () -> DividerControlling
    private let isOnScreen: @MainActor (CGRect) -> Bool
    private let pause: @Sendable (Duration) async -> Void

    private var divider: DividerControlling?
    /// The divider's window in the window server's list: found once by its frame, then followed by its number. For a
    /// moment after each change of width, AppKit gives the divider's old origin with its new width.
    private var dividerWindowID: UInt32?
    private var pressers: [IconID: @Sendable () -> Bool] = [:]
    private var windowOwners: [UInt32: pid_t] = [:]
    private var lastSnapshot = MenuBarSnapshot.empty
    private var wantsConcealed = false
    private var shown: (icon: IconID, task: Task<Void, Never>, beside: IconID?)?
    /// The identity each icon window had at the last scan.
    private var identityByWindow: [UInt32: IconID] = [:]
    /// Icons that could not be moved, and when: they wait a minute before another try, so a failing move never
    /// repeats with every change of the menu bar.
    private var recentFailures: [UInt32: ContinuousClock.Instant] = [:]
    static let retryAfter: Duration = .seconds(60)
    /// How soon to try again once the person was busy.
    static let afterAPause: Duration = .seconds(3)
    /// Arrangements the engine asks for by itself in a row, at most.
    static let automaticRetryLimit = 3
    private var automaticRetries = 0
    /// An icon that should show is still left of the divider: the divider stays narrow until it is carried across.
    private var keepsNarrow = false
    /// Whether an arrangement has run since the launch.
    private var hasArranged = false
    /// The plan of the last arrangement: an icon opened from a drawer goes back through it when its own place is out of
    /// reach.
    private var lastPlan: VisibilityPlan?
    /// One operation at a time: an icon going back from a drawer and a new arrangement would drag across each other.
    private var isBusy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// While Tiroir moves icons, the divider is this wide, so a drop can land on either side of it.
    static let arrangingLength: CGFloat = 24
    /// Whether a drop at this x (window server coordinates) is safe: far enough from the notch, where macOS places no
    /// icon and where apps drawn around the notch catch drops.
    private let isSafeDrop: @MainActor (CGFloat) -> Bool

    public init(
        icons: IconSource, windows: StatusWindowSource = SystemStatusWindows(), poster: EventPosting,
        activity: UserActivitySource = SystemUserActivity(),
        makeDivider: @escaping @MainActor () -> DividerControlling = { Divider() },
        isOnScreen: @escaping @MainActor (CGRect) -> Bool = { ScreenCoordinates.isOnScreen($0) },
        isSafeDrop: @escaping @MainActor (CGFloat) -> Bool = { DropZone.isSafe($0) },
        pause: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.icons = icons
        self.windows = windows
        self.poster = poster
        self.activity = activity
        self.makeDivider = makeDivider
        self.isOnScreen = isOnScreen
        self.isSafeDrop = isSafeDrop
        self.pause = pause
        mover = ItemMover(windows: windows, poster: poster, activity: activity, isSafeDrop: isSafeDrop, pause: pause)
    }

    public func start() async {
        if divider == nil {
            divider = makeDivider()
            dividerWindowID = nil
        }
        refreshStatus()
    }

    /// The divider as the window server has it, nil before macOS has placed it.
    func dividerWindow(in listed: [StatusWindow]? = nil) -> StatusWindow? {
        let listed = listed ?? windows.statusWindows()
        if let id = dividerWindowID, let window = listed.first(where: { $0.id == id }) { return window }
        guard let frame = divider?.frame, let window = listed.first(where: { Self.sameWindow($0.frame, frame) }) else { return nil }
        dividerWindowID = window.id
        return window
    }

    func refreshStatus() {
        status = icons.isTrusted ? .ready : .needsAccessibility
        if status != .ready {
            // Without Accessibility nothing can be moved back: nothing stays hidden.
            divider?.relax()
        }
    }

    // MARK: Scanning

    public func scan() async -> MenuBarSnapshot {
        refreshStatus()
        guard status == .ready else { return .empty }
        let found = await icons.find()
        let listed = windows.statusWindows()
        let own = dividerWindow(in: listed)?.id
        let others = listed.filter { $0.id != own }
        windowOwners = Dictionary(listed.map { ($0.id, $0.ownerPID) }, uniquingKeysWith: { first, _ in first })

        let matches = FrameMatcher.match(
            elements: found.enumerated().map { FrameMatcher.Element(index: $0.offset, frame: $0.element.frame) },
            windows: others.map { FrameMatcher.Window(id: $0.id, frame: $0.frame) })
        let windowsByID = Dictionary(others.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // An icon without a window is one macOS itself keeps out of the menu bar ("Allow in the Menu Bar"): it is left
        // out before an app's icons are numbered, so it never shifts the others' identities.
        let windowed = found.enumerated().compactMap { index, icon in matches[index].map { (icon, $0) } }

        var result: [MenuBarIcon] = []
        var presses: [IconID: @Sendable () -> Bool] = [:]
        for entry in stableIdentities(windowed) {
            guard let window = windowsByID[entry.windowID] else { continue }
            let kind = IconAssembly.kind(of: entry.id.bundleID)
            let icon = MenuBarIcon(
                id: entry.id, ownerName: entry.found.app.name,
                label: IconAssembly.displayLabel(entry.found.label, kind: kind), frame: window.frame,
                isOnScreen: isOnScreen(window.frame),
                isMovable: !IconIdentity.fixedSystemIdentifiers.contains(entry.id.key),
                kind: kind, windowID: entry.windowID, pid: entry.found.app.pid)
            result.append(icon)
            presses[entry.id] = entry.found.press
        }
        // An app that did not answer in time keeps the icons it had, as long as their windows are still listed: the
        // window list does not depend on the app. Without this, a busy app's hidden icon would come back.
        let seen = Set(result.compactMap(\.windowID))
        for previous in lastSnapshot.icons {
            guard let windowID = previous.windowID, !seen.contains(windowID), let window = windowsByID[windowID],
                  !result.contains(where: { $0.id == previous.id }) else { continue }
            var carried = previous
            carried.frame = window.frame
            carried.isOnScreen = isOnScreen(window.frame)
            result.append(carried)
            presses[previous.id] = pressers[previous.id]
        }
        pressers = presses
        lastSnapshot = MenuBarSnapshot(icons: result)
        return lastSnapshot
    }

    /// Identities of an app's icons. An icon keeps the identity it had as long as its window lives, even when a move
    /// changes its rank among its app's icons (hiding the right one of two would otherwise swap them); icons seen for
    /// the first time are named by rank, skipping the ranks already taken.
    private func stableIdentities(_ windowed: [(FoundIcon, UInt32)]) -> [(found: FoundIcon, windowID: UInt32, id: IconID)] {
        var result: [(found: FoundIcon, windowID: UInt32, id: IconID)] = []
        for (bundleID, group) in Dictionary(grouping: windowed, by: { $0.0.app.bundleID }) {
            let ordered = group.sorted { $0.0.frame.midX > $1.0.frame.midX }
            var assigned: [UInt32: IconID] = [:]
            var used = Set<IconID>()
            for (_, window) in ordered {
                if let previous = identityByWindow[window], previous.bundleID == bundleID, used.insert(previous).inserted {
                    assigned[window] = previous
                }
            }
            for (rank, (icon, window)) in ordered.enumerated() where assigned[window] == nil {
                var next = rank
                var id = IconIdentity.make(bundleID: bundleID, identifier: icon.identifier, indexFromRight: next, countForApp: ordered.count)
                while used.contains(id), icon.identifier == nil, next < ordered.count * 2 {
                    next += 1
                    id = IconIdentity.make(bundleID: bundleID, identifier: nil, indexFromRight: next, countForApp: ordered.count)
                }
                used.insert(id)
                assigned[window] = id
            }
            result.append(contentsOf: ordered.compactMap { icon, window in assigned[window].map { (icon, window, $0) } })
        }
        identityByWindow = Dictionary(result.map { ($0.windowID, $0.id) }, uniquingKeysWith: { first, _ in first })
        return result
    }

    static func sameWindow(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= 2 && abs(a.width - b.width) <= 2
    }

    // MARK: Arranging

    public func apply(_ plan: VisibilityPlan) async -> ApplyReport {
        await exclusively { await arrange(plan) }
    }

    /// Runs one operation that moves icons, after the one under way.
    private func exclusively<T>(_ body: () async throws -> T) async rethrows -> T {
        while isBusy { await withCheckedContinuation { waiting.append($0) } }
        isBusy = true
        defer {
            isBusy = false
            if !waiting.isEmpty { waiting.removeFirst().resume() }
        }
        return try await body()
    }

    /// With `settles` false, the divider keeps its arranging width at the end, for more moves right after.
    private func arrange(_ plan: VisibilityPlan, settles: Bool = true) async -> ApplyReport {
        guard let divider else { return .nothing }
        defer { hasArranged = true }
        lastPlan = plan
        wantsConcealed = !plan.concealed.isEmpty
        // An icon open from a drawer stays where it is until its menu closes; it goes back by itself.
        var plan = plan
        if let shown {
            plan.visible.remove(shown.icon)
            plan.concealed.remove(shown.icon)
        }
        guard wantsConcealed else {
            // A narrow divider hides nothing: every icon shows without a single move, and each keeps its place for
            // the next time some hide.
            keepsNarrow = false
            automaticRetries = 0
            divider.relax()
            return .nothing
        }
        var snapshot = await scan()
        guard status == .ready else { return .nothing }
        guard let startFrame = dividerWindow()?.frame else {
            // macOS has not placed the divider yet.
            return retrying(ApplyReport(), after: .seconds(2))
        }
        let before = showing(snapshot)
        var failed = Set<IconID>()
        var postponed = Set<IconID>()
        let planned = LayoutPlanner.moves(plan: plan, snapshot: snapshot, dividerFrame: startFrame)
        if !planned.isEmpty {
            do {
                // Nothing changes while the person uses the pointer or the keyboard: the arrangement waits for a pause.
                try await mover.waitForPause()
                // With the divider narrow and every icon on screen, each drop lands on a real place. macOS lays the bar
                // out again, and may still be placing Tiroir's own items after a launch: wait until nothing moves.
                setArranging(divider)
                await waitForStillBar(first: !hasArranged)
                snapshot = await scan()
                if try await moveDividerToBestCut(plan: plan, snapshot: snapshot) {
                    await waitForStillBar()
                    snapshot = await scan()
                }
                let moves = dividerWindow().map { LayoutPlanner.moves(plan: plan, snapshot: snapshot, dividerFrame: $0.frame) } ?? []
                for (index, move) in moves.enumerated() {
                    do {
                        try await carry(move, in: snapshot)
                    } catch EngineError.personIsBusy {
                        postponed.formUnion(moves[index...].map(\.icon))
                        break
                    } catch {
                        failed.insert(move.icon)
                    }
                }
            } catch {
                // Only a busy person stops an arrangement before it starts.
                postponed = Set(planned.map(\.icon))
            }
        }

        // Where every icon stands now. Widening the divider hides everything on its left: never while an icon that
        // should show is still there. It stays narrow, every icon shows, and the arrangement is tried again.
        let now = showing(snapshot)
        var report = ApplyReport()
        var stranded = false
        var appeared = false
        for icon in snapshot.icons where icon.isMovable {
            guard let shows = now[icon.id], let wanted = Self.wantsShown(icon.id, in: plan) else { continue }
            if shows == wanted {
                if before[icon.id].map({ $0 != wanted }) ?? false { report.moved.append(icon.id) }
                continue
            }
            if wanted { stranded = true }
            if postponed.contains(icon.id) {
                report.postponed.append(icon.id)
            } else if failed.contains(icon.id) {
                report.failed.append(icon.id)
            } else {
                // New during the arrangement: the next one places it.
                appeared = true
            }
        }
        report.moved.sort()
        report.failed.sort()
        report.postponed.sort()
        keepsNarrow = stranded
        if settles { settleDivider() }
        if !stranded, !planned.isEmpty { divider.rememberPlace() }

        if !report.postponed.isEmpty {
            report.tryAgainIn = Self.afterAPause
        } else if appeared {
            report.tryAgainIn = .seconds(1)
        } else if !report.failed.isEmpty {
            report = retrying(report, after: Self.retryAfter)
        } else {
            automaticRetries = 0
        }
        if !report.moved.isEmpty || !report.failed.isEmpty || !report.postponed.isEmpty {
            Log.engine.notice("applied: \(report.moved.count) moved, \(report.failed.count) failed, \(report.postponed.count) left for later\(stranded ? "; the divider stays narrow" : "")")
        }
        return report
    }

    /// Asks to arrange again after `delay`, a few times at most: a move that keeps failing is left until the menu bar
    /// or the layout changes.
    private func retrying(_ report: ApplyReport, after delay: Duration) -> ApplyReport {
        var report = report
        guard automaticRetries < Self.automaticRetryLimit else { return report }
        automaticRetries += 1
        report.tryAgainIn = delay
        return report
    }

    /// Whether the plan shows an icon, hides it, or says nothing of it.
    static func wantsShown(_ id: IconID, in plan: VisibilityPlan) -> Bool? {
        if plan.visible.contains(id) { return true }
        if plan.concealed.contains(id) { return false }
        return nil
    }

    /// For each movable icon of the snapshot, whether it is right of the divider now, read from the window list.
    private func showing(_ snapshot: MenuBarSnapshot) -> [IconID: Bool] {
        guard let edge = dividerWindow()?.frame.maxX else { return [:] }
        let frames = Dictionary(windows.statusWindows().map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        var result: [IconID: Bool] = [:]
        for icon in snapshot.icons where icon.isMovable {
            guard let windowID = icon.windowID, let frame = frames[windowID] else { continue }
            result[icon.id] = frame.midX >= edge
        }
        return result
    }

    /// Wide when some icons hide and none that should show is left on its left; narrow otherwise.
    private func settleDivider() {
        guard let divider else { return }
        if wantsConcealed, !keepsNarrow { divider.expand() } else { divider.relax() }
    }

    /// One planned move: an icon to the shown side (one drag), or behind the divider (two).
    private func carry(_ move: Move, in snapshot: MenuBarSnapshot) async throws {
        guard let icon = snapshot.icon(move.icon), let windowID = icon.windowID else { throw EngineError.iconNotFound(move.icon) }
        if let failed = recentFailures[windowID], ContinuousClock.now - failed < Self.retryAfter {
            throw EngineError.moveFailed(move.icon)
        }
        guard let dividerWindow = dividerWindow() else { throw EngineError.notReady(status) }
        let owner = windowOwners[windowID] ?? icon.pid
        do {
            if move.to == .concealed {
                try await conceal(windowID: windowID, ownerPID: owner)
            } else {
                try await mover.move(windowID: windowID, ownerPID: owner, to: .rightOf(dividerWindow.frame, windowID: dividerWindow.id))
            }
            recentFailures[windowID] = nil
        } catch EngineError.personIsBusy {
            throw EngineError.personIsBusy
        } catch {
            recentFailures[windowID] = .now
            throw error
        }
    }

    /// Drags the divider, once, to the place between two icons that leaves the fewest drags, when that beats carrying
    /// icons across it one by one: after a launch, it usually replaces them all. Returns whether the bar may have
    /// changed; throws only when the person is busy.
    private func moveDividerToBestCut(plan: VisibilityPlan, snapshot: MenuBarSnapshot) async throws -> Bool {
        guard let dividerWindow = dividerWindow(),
              let destination = Self.bestCut(icons: snapshot.icons, plan: plan, dividerFrame: dividerWindow.frame, isSafeDrop: isSafeDrop)
        else { return false }
        do {
            try await mover.move(windowID: dividerWindow.id, ownerPID: windowOwners[dividerWindow.id] ?? getpid(), to: destination)
            Log.engine.notice("divider moved to its best place")
        } catch EngineError.personIsBusy {
            throw EngineError.personIsBusy
        } catch {
            // Wherever it landed, the icons are carried from there.
            Log.engine.error("the divider could not move to its best place")
        }
        return true
    }

    /// Where one drag of the divider saves the most drags, if anywhere. Carrying an icon to the shown side takes one
    /// drag; hiding one takes two (it comes next to the divider, then the divider steps over it); moving the divider
    /// takes one. Only places clear of the notch count; among equal ones, the rightmost wins. A divider beside the notch
    /// always moves to a clear place when there is one.
    static func bestCut(icons: [MenuBarIcon], plan: VisibilityPlan, dividerFrame: CGRect,
                        isSafeDrop: (CGFloat) -> Bool) -> ItemMover.Destination? {
        // Right to left.
        let placed = icons
            .filter { $0.isMovable && $0.windowID != nil && wantsShown($0.id, in: plan) != nil }
            .sorted { $0.frame.midX > $1.frame.midX }
        guard !placed.isEmpty else { return nil }
        // With the divider at cut k, the k rightmost icons show.
        func drags(_ cut: Int) -> Int {
            placed.enumerated().reduce(0) { total, entry in
                let shows = entry.offset < cut
                switch (shows, wantsShown(entry.element.id, in: plan)) {
                case (true, false): return total + 2
                case (false, true): return total + 1
                default: return total
                }
            }
        }
        let current = placed.filter { $0.frame.midX >= dividerFrame.maxX }.count
        // Beside the notch, where no drop lands, the divider's place is no place to carry icons to.
        var best = (cut: current, drags: isSafeDrop(dividerFrame.maxX) ? drags(current) : Int.max)
        for cut in 0...placed.count where cut != current {
            let gap = cut == 0 ? placed[0].frame.maxX : placed[cut - 1].frame.minX
            guard isSafeDrop(gap) else { continue }
            let total = drags(cut) + 1
            if total < best.drags { best = (cut, total) }
        }
        guard best.cut != current else { return nil }
        if best.cut == 0 { return .rightOf(placed[0].frame, windowID: placed[0].windowID) }
        let right = placed[best.cut - 1]
        return .leftOf(right.frame, windowID: right.windowID)
    }

    private func setArranging(_ divider: DividerControlling) {
        if let flexible = divider as? ArrangingDivider {
            flexible.setArranging()
        } else {
            divider.relax()
        }
    }

    // MARK: Opening

    public func open(_ id: IconID, anchor: CGRect?) async throws {
        try await exclusively { try await openIcon(id, anchor: anchor) }
    }

    private func openIcon(_ id: IconID, anchor: CGRect?) async throws {
        await putBackShownIcon()
        let snapshot = await scan()
        guard status == .ready else { throw EngineError.notReady(status) }
        guard let icon = snapshot.icon(id), let windowID = icon.windowID else { throw EngineError.iconNotFound(id) }
        guard let divider, let dividerFrame = dividerWindow()?.frame else { throw EngineError.notReady(status) }

        let concealed = divider.isExpanded && icon.frame.midX < dividerFrame.maxX
        if !concealed {
            _ = try await press(icon)
            return
        }
        // Bring the icon next to the drawer's mark, open it there, and put it back once its menu has closed, beside the
        // concealed icon that was its right neighbour.
        if let anchor, let anchorWindow = windows.statusWindows().first(where: { Self.sameWindow($0.frame, anchor) }) {
            let neighbour = Self.rightNeighbour(of: icon, in: snapshot, dividerFrame: dividerFrame)
            do {
                try await mover.move(windowID: windowID, ownerPID: windowOwners[windowID] ?? icon.pid,
                                     to: .leftOf(anchorWindow.frame, windowID: anchorWindow.id))
                await pause(.milliseconds(90))
                let moved = await scan().icon(id) ?? icon
                let before = try await press(moved)
                watchUntilClosed(moved, opened: before, thenPutBack: true, beside: neighbour)
                return
            } catch EngineError.personIsBusy {
                throw EngineError.personIsBusy
            } catch {
                // Fall through to the gentler way.
            }
        }
        // Without a move: let every hidden icon show for the time the menu is open.
        divider.relax()
        await pause(.milliseconds(220))
        guard let revealed = await scan().icon(id), revealed.isOnScreen else {
            settleDivider()
            throw EngineError.cannotOpen(id)
        }
        let before = try await press(revealed)
        watchUntilClosed(revealed, opened: before, thenPutBack: false, beside: nil)
    }

    /// Presses an icon and returns the raised windows its app had just before: what the press opens is what comes
    /// on top of them.
    private func press(_ icon: MenuBarIcon) async throws -> Set<UInt32> {
        let before = windows.raisedWindows(ownerPIDs: owners(of: icon))
        if let presser = pressers[icon.id], presser() { return before }
        guard let windowID = icon.windowID else { throw EngineError.cannotOpen(icon.id) }
        // Some apps (Electron ones among them) ignore the Accessibility action: a click does it.
        await poster.click(windowID: windowID, ownerPID: windowOwners[windowID] ?? icon.pid,
                           at: CGPoint(x: icon.frame.midX, y: icon.frame.midY), route: mover.workingRoute ?? .session)
        return before
    }

    /// The app, and on macOS 26 Control Center, which hosts the icon's window and draws the menus of its own modules.
    private func owners(of icon: MenuBarIcon) -> Set<pid_t> {
        var owners: Set<pid_t> = [icon.pid]
        if let windowID = icon.windowID, let owner = windowOwners[windowID] { owners.insert(owner) }
        return owners
    }

    /// Checks four times a second, only while an icon is shown, whether what its press opened is still open: a menu, a
    /// popover, a panel or an overlay, any window the app raised above ordinary ones since. Once it has been closed for
    /// `rehideDelay` and no button is held, the icon goes back.
    private func watchUntilClosed(_ icon: MenuBarIcon, opened before: Set<UInt32>, thenPutBack: Bool, beside neighbour: IconID?) {
        shown?.task.cancel()
        let owners = owners(of: icon)
        let task = Task { [weak self] in
            guard let self else { return }
            var closedSince: ContinuousClock.Instant?
            let started = ContinuousClock.now
            // A menu takes a moment to appear after the press.
            await self.pause(.milliseconds(400))
            while !Task.isCancelled {
                let raised = self.windows.raisedWindows(ownerPIDs: owners).subtracting(before)
                let open = !raised.isEmpty || self.activity.isMouseButtonDown
                if open {
                    closedSince = nil
                } else if let since = closedSince {
                    if ContinuousClock.now - since >= .milliseconds(Int(self.rehideDelay * 1000)) { break }
                } else {
                    closedSince = .now
                }
                // Ten minutes is plenty for any menu.
                if ContinuousClock.now - started > .seconds(600) { break }
                await self.pause(.milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            await self.exclusively {
                // Opening another icon puts this one back first.
                guard !Task.isCancelled else { return }
                await self.finishShowing(icon, putBack: thenPutBack, beside: neighbour)
            }
        }
        shown = (icon.id, task, neighbour)
    }

    private func finishShowing(_ icon: MenuBarIcon, putBack: Bool, beside neighbour: IconID?) async {
        shown = nil
        guard let divider else { return }
        if putBack {
            // The wide divider's left edge is off screen: narrow it so the icon can go right next to it, in the place
            // it had among the concealed icons, then widen it again.
            setArranging(divider)
            await waitForStillBar(first: !hasArranged)
            let snapshot = await scan()
            if let frame = dividerWindow()?.frame, let current = snapshot.icon(icon.id), let windowID = current.windowID {
                let owner = windowOwners[windowID] ?? current.pid
                var isBack = false
                if let neighbour, let beside = snapshot.icon(neighbour), let besideWindow = beside.windowID,
                   beside.frame.maxX <= frame.minX + ItemMover.slack, isSafeDrop(beside.frame.minX) {
                    // Back in its own place among the concealed icons.
                    isBack = (try? await mover.move(windowID: windowID, ownerPID: owner,
                                                    to: .leftOf(beside.frame, windowID: besideWindow))) != nil
                }
                if !isBack {
                    // Its own place is beside the notch, or the drop missed: it goes right behind the divider first,
                    // through an arrangement that takes the divider away from the notch when it has to, then back to
                    // its own place among the concealed icons.
                    if let plan = lastPlan {
                        let report = await arrange(plan, settles: false)
                        if report.failed.contains(icon.id) { Log.engine.error("an icon opened from a drawer could not go back") }
                    } else {
                        do {
                            try await conceal(windowID: windowID, ownerPID: owner)
                        } catch {
                            Log.engine.error("an icon opened from a drawer could not go back")
                        }
                    }
                    if let neighbour { await restoreOrder(of: icon.id, before: neighbour) }
                }
            }
        }
        settleDivider()
    }

    /// Puts an icon opened from a drawer back left of `neighbour`, its right neighbour among the concealed icons, when it
    /// went right behind the divider instead because its own place is beside the notch. The icons between them come out
    /// one by one, each dropped right next to the divider, then the divider steps back over all of them: every drop
    /// lands next to the divider, away from the notch, and the concealed icons end in the order they had. Nothing moves
    /// when one of those drops would not be clear of the notch.
    private func restoreOrder(of id: IconID, before neighbour: IconID) async {
        await waitForStillBar()
        let snapshot = await scan()
        let frames = Dictionary(windows.statusWindows().map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        guard let divider = dividerWindow(), let iconWindow = snapshot.icon(id)?.windowID, let iconFrame = frames[iconWindow],
              let besideFrame = snapshot.icon(neighbour)?.windowID.flatMap({ frames[$0] }),
              iconFrame.midX < divider.frame.maxX, iconFrame.minX > besideFrame.minX else { return }
        // The icons that belong on its right: from its neighbour up to it, left to right.
        let between = snapshot.icons
            .compactMap { item -> (icon: MenuBarIcon, window: UInt32, frame: CGRect)? in
                guard item.id != id, item.isMovable, let window = item.windowID, let frame = frames[window],
                      frame.minX >= besideFrame.minX - ItemMover.slack, frame.maxX <= iconFrame.minX + ItemMover.slack
                else { return nil }
                return (item, window, frame)
            }
            .sorted { $0.frame.minX < $1.frame.minX }
        guard let last = between.last else { return }
        // Each icon that comes out moves the divider left by its width: every drop must still be clear of the notch.
        var edge = divider.frame.maxX
        for entry in between.reversed() {
            guard isSafeDrop(edge - 2) else {
                Log.engine.notice("an icon opened from a drawer stays right behind the divider: its own place is out of reach")
                return
            }
            edge -= entry.frame.width
        }
        do {
            for entry in between.reversed() {
                guard let current = dividerWindow() else { throw EngineError.notReady(status) }
                try await mover.move(windowID: entry.window, ownerPID: windowOwners[entry.window] ?? entry.icon.pid,
                                     to: .rightOf(current.frame, windowID: current.id))
            }
            guard let current = dividerWindow(), let lastFrame = mover.frame(of: last.window) else { throw EngineError.notReady(status) }
            try await mover.move(windowID: current.id, ownerPID: windowOwners[current.id] ?? getpid(),
                                 to: .rightOf(lastFrame, windowID: last.window))
            Log.engine.notice("an icon opened from a drawer is back in its own place")
        } catch {
            // Whatever came out and should hide goes back behind the divider.
            Log.engine.error("the concealed icons could not be put back in their order")
            if let plan = lastPlan { _ = await arrange(plan, settles: false) }
        }
    }

    /// Carries an icon behind the divider without ever dropping on the divider's left, where the notch, or an app drawn
    /// around it, can catch the drop: the icon comes right next to the divider, then the divider steps over it. Every
    /// drop lands on the right of the divider, among icons that show.
    private func conceal(windowID: UInt32, ownerPID: pid_t) async throws {
        guard let dividerWindow = dividerWindow() else { throw EngineError.notReady(status) }
        try await mover.move(windowID: windowID, ownerPID: ownerPID, to: .rightOf(dividerWindow.frame, windowID: dividerWindow.id))
        guard let iconFrame = mover.frame(of: windowID) else { throw EngineError.iconNotFound(IconID(bundleID: "window \(windowID)")) }
        try await mover.move(windowID: dividerWindow.id, ownerPID: windowOwners[dividerWindow.id] ?? ownerPID,
                             to: .rightOf(iconFrame, windowID: windowID))
    }

    /// Waits until the icons' windows hold still for three readings in a row, 50 ms apart, and 1.5 s at most. The first
    /// arrangement after a launch waits for 0.6 s of stillness, 4 s at most: macOS is still placing Tiroir's own items,
    /// and apps opened at login are still adding theirs.
    func waitForStillBar(first: Bool = false) async {
        await pause(.milliseconds(120))
        var previous: [StatusWindow] = []
        var still = 0
        for _ in 0..<(first ? 80 : 30) {
            let now = windows.statusWindows()
            still = now == previous ? still + 1 : 0
            previous = now
            if still >= (first ? 12 : 2) { return }
            await pause(.milliseconds(50))
        }
    }

    /// The concealed icon right of `icon`, which it goes back beside; nil when the divider comes first.
    static func rightNeighbour(of icon: MenuBarIcon, in snapshot: MenuBarSnapshot, dividerFrame: CGRect) -> IconID? {
        snapshot.icons
            .filter { $0.id != icon.id && $0.frame.minX >= icon.frame.maxX - ItemMover.slack && $0.frame.maxX <= dividerFrame.minX + ItemMover.slack }
            .min { $0.frame.minX < $1.frame.minX }?.id
    }

    /// An icon still shown from a drawer goes back before another one opens.
    private func putBackShownIcon() async {
        guard let shown else { return }
        shown.task.cancel()
        self.shown = nil
        if let icon = lastSnapshot.icon(shown.icon) {
            await finishShowing(icon, putBack: true, beside: shown.beside)
        }
    }

    // MARK: Quitting

    public func restore() {
        shown?.task.cancel()
        shown = nil
        divider?.remove()
        divider = nil
        dividerWindowID = nil
    }
}

/// A divider that can hold a middle width while Tiroir arranges icons.
@MainActor
public protocol ArrangingDivider: DividerControlling {
    func setArranging()
}

extension Divider: ArrangingDivider {}
