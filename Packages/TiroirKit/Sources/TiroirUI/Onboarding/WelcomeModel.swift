import Foundation
import Observation
import TiroirCore
import TiroirSystem

/// The welcome's state (spec 6.1): four steps, each with one decision.
@MainActor
@Observable
public final class WelcomeModel {
    public enum Step: Int, CaseIterable, Sendable {
        case hello, permission, sort, ready
    }

    public var step: Step
    public var strategy: SortStrategy = .purpose
    /// The proposal on screen, as the person adjusts it.
    public var proposal: Layout = .empty
    public var isSorting = false
    public var report: ApplyReport?
    public var openAtLogin = true
    public var keepUpToDate = true

    public init(step: Step = .hello) {
        self.step = step
    }

    public func next() {
        guard let following = Step(rawValue: step.rawValue + 1) else { return }
        step = following
    }

    public func previous() {
        guard let preceding = Step(rawValue: step.rawValue - 1) else { return }
        step = preceding
    }

    /// Icons the proposal takes out of the menu bar.
    public func leavingCount(in model: InterfaceModel) -> Int {
        model.icons.filter { row in
            guard row.isMovable else { return false }
            return proposal.placement(of: row.id, category: row.category) != .menuBar
        }.count
    }

    public func members(of drawer: UUID, in model: InterfaceModel) -> [IconRow] {
        model.icons.filter { $0.isMovable && proposal.placement(of: $0.id, category: $0.category) == .drawer(drawer) }
    }

    public func menuBarRows(in model: InterfaceModel) -> [IconRow] {
        model.icons.filter { !$0.isMovable || proposal.placement(of: $0.id, category: $0.category) == .menuBar }
    }
}
