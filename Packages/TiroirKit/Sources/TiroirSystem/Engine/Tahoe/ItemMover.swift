import CoreGraphics
import Foundation
import TiroirCore

/// Moves one icon on macOS 26 and checks that it landed (spec 4.3, Arranging).
///
/// A move waits until the person pauses (no button held, no modifier, the pointer still for 0.15 s) so it never
/// fights them, then posts one Command-drag and reads the window list until the icon settles. A move that did not
/// land is tried again through the next posting route; the route that worked is remembered.
@MainActor
public final class ItemMover {
    public enum Destination: Equatable, Sendable {
        /// Just left of the window at `frame`.
        case leftOf(CGRect, windowID: UInt32?)
        /// Just right of the window at `frame`.
        case rightOf(CGRect, windowID: UInt32?)

        var frame: CGRect {
            switch self {
            case .leftOf(let frame, _), .rightOf(let frame, _): frame
            }
        }

        var windowID: UInt32? {
            switch self {
            case .leftOf(_, let id), .rightOf(_, let id): id
            }
        }
    }

    let windows: StatusWindowSource
    let poster: EventPosting
    let activity: UserActivitySource
    let pause: @Sendable (Duration) async -> Void
    /// Whether a drop at this x lands where it is aimed: not beside the notch, nor near an app drawn around it.
    let isSafeDrop: @MainActor (CGFloat) -> Bool
    /// The posting route that moved the last icon.
    public private(set) var workingRoute: PostingRoute?

    /// Longest wait for the person to pause.
    static let patience: Duration = .seconds(2)
    /// How long the pointer must rest before a move.
    static let stillness: TimeInterval = 0.15
    /// How long macOS takes to start laying the icons out after a drop.
    static let dropDelay: Duration = .milliseconds(250)
    /// How long a move may take to settle in the window list: 20 readings, 50 ms apart.
    static let settleChecks = 20
    static let settleInterval: Duration = .milliseconds(50)
    /// Points of slack when checking where an icon landed.
    static let slack: CGFloat = 3
    /// The widest gap between two neighbouring icons; any icon is wider, so a wider gap means one sits in between.
    static let neighbourGap: CGFloat = 10

    public init(
        windows: StatusWindowSource, poster: EventPosting, activity: UserActivitySource,
        isSafeDrop: @escaping @MainActor (CGFloat) -> Bool = { _ in true },
        pause: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.windows = windows
        self.poster = poster
        self.activity = activity
        self.isSafeDrop = isSafeDrop
        self.pause = pause
    }

    /// The posting route and drop variant that moved the last icon.
    public private(set) var workingVariant = 0

    /// Moves the icon window `windowID` and returns its new frame.
    @discardableResult
    public func move(windowID: UInt32, ownerPID: pid_t, to destination: Destination) async throws -> CGRect {
        for (route, variant) in attempts() {
            try await waitForPause()
            await waitUntilStill(windowID, destination)
            guard let current = frame(of: windowID) else { throw EngineError.iconNotFound(IconID(bundleID: "window \(windowID)")) }
            if landed(current, at: destination) { return current }
            let target = destination.windowID.flatMap(frame(of:)) ?? destination.frame
            let start = CGPoint(x: current.midX, y: current.midY)
            let end = Self.dropPoint(for: destination, target: target, moving: current, variant: variant)
            // Beside the notch a drop lands anywhere: that variant is left out.
            guard isSafeDrop(end.x) else { continue }
            await poster.commandDrag(windowID: windowID, ownerPID: ownerPID, from: start, to: end,
                                     destinationWindowID: destination.windowID, route: route)
            // macOS animates a drop into place and lays the other icons out again: let it start, then judge where the
            // icon landed once it and its target have both held still for three readings in a row.
            await pause(Self.dropDelay)
            var previous: (icon: CGRect, target: CGRect)?
            var stillReadings = 0
            for _ in 0..<Self.settleChecks {
                if let now = frame(of: windowID) {
                    let target = destination.windowID.flatMap(frame(of:)) ?? destination.frame
                    stillReadings = previous.map { $0.icon == now && $0.target == target } == true ? stillReadings + 1 : 0
                    previous = (now, target)
                    if stillReadings >= 2 {
                        if landed(now, at: destination) {
                            workingRoute = route
                            workingVariant = variant
                            Log.engine.notice("moved window \(windowID) through \(route.rawValue, privacy: .public), variant \(variant)")
                            return now
                        }
                        // Settled somewhere else: the next attempt starts from there.
                        Log.engine.notice("window \(windowID) from x \(Int(start.x)) dropped at x \(Int(end.x)) settled at x \(Int(now.minX)) w \(Int(now.width)), target x \(Int(target.minX)) w \(Int(target.width)) (\(route.rawValue, privacy: .public) \(variant))")
                        break
                    }
                }
                await pause(Self.settleInterval)
            }
        }
        Log.engine.error("could not move window \(windowID) after \(self.attempts().count) attempts")
        throw EngineError.moveFailed(IconID(bundleID: "window \(windowID)"))
    }

    /// The combinations to try, the one that worked last first; six at most.
    func attempts() -> [(PostingRoute, Int)] {
        var all: [(PostingRoute, Int)] = []
        for route in PostingRoute.allCases {
            for variant in 0..<3 { all.append((route, variant)) }
        }
        if let workingRoute {
            all.removeAll { $0 == (workingRoute, workingVariant) }
            all.insert((workingRoute, workingVariant), at: 0)
        }
        return Array(all.prefix(6))
    }

    /// Where to release. Over the left part of an icon, macOS drops the dragged one on its left; over the right part,
    /// on its right. Icons are laid out from the right edge, so lifting an icon slides every icon on its left to the
    /// right by its width: the variants cover that shift, no shift, and the opposite shift.
    static func dropPoint(for destination: Destination, target: CGRect, moving: CGRect, variant: Int) -> CGPoint {
        let movingLeft = moving.midX > target.midX
        let shift: CGFloat = switch variant {
        case 0: movingLeft ? moving.width : 0
        case 1: 0
        default: -moving.width
        }
        switch destination {
        case .leftOf: return CGPoint(x: target.minX + shift + 2, y: target.midY)
        case .rightOf: return CGPoint(x: target.maxX + shift - 2, y: target.midY)
        }
    }

    /// Whether an icon sits right next to the target, on the asked side. Right next to it, not merely on that side:
    /// an icon dropped one place too far would change the order of the icons it passed.
    func landed(_ frame: CGRect, at destination: Destination) -> Bool {
        let target = destination.windowID.flatMap(self.frame(of:)) ?? destination.frame
        switch destination {
        case .leftOf:
            return frame.maxX <= target.minX + Self.slack && frame.maxX >= target.minX - Self.neighbourGap && frame.midX < target.midX
        case .rightOf:
            return frame.minX >= target.maxX - Self.slack && frame.minX <= target.maxX + Self.neighbourGap && frame.midX > target.midX
        }
    }

    /// Before a drag: the icon and its target hold still for two readings in a row, 50 ms apart, 0.6 s at most. A drop
    /// aimed at a place macOS is still moving lands one place off.
    func waitUntilStill(_ windowID: UInt32, _ destination: Destination) async {
        var previous: (CGRect?, CGRect?)?
        for _ in 0..<12 {
            let now = (frame(of: windowID), destination.windowID.flatMap(frame(of:)))
            if let previous, previous.0 == now.0, previous.1 == now.1 { return }
            previous = now
            await pause(.milliseconds(50))
        }
    }

    func frame(of windowID: UInt32) -> CGRect? {
        windows.statusWindows().first { $0.id == windowID }?.frame
    }

    func waitForPause() async throws {
        let deadline = ContinuousClock.now + Self.patience
        while let reason = busyReason() {
            if ContinuousClock.now > deadline {
                Log.engine.notice("left for later: \(reason, privacy: .public)")
                throw EngineError.personIsBusy
            }
            await pause(.milliseconds(25))
        }
    }

    /// What the person is doing that a move would fight, if anything.
    private func busyReason() -> String? {
        if activity.isMouseButtonDown { return "a mouse button is held" }
        if activity.areModifiersDown { return "a modifier key is held" }
        if activity.secondsSincePointerMoved < Self.stillness { return "the pointer is moving" }
        return nil
    }
}
