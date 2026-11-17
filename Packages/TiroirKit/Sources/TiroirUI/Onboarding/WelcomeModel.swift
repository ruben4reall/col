import Foundation
import Observation
import TiroirCore
import TiroirSystem

/// The welcome's state (spec 6.1): four steps, each with one decision.
@available(macOS 26, *)
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
    /// Col already has the permission (it asks in its own welcome and settings): the welcome goes from hello to Smart Sort.
    public var skipsPermission = false

    public init(step: Step = .hello) {
        self.step = step
    }

    /// The steps shown, in order.
    public var steps: [Step] {
        Step.allCases.filter { $0 != .permission || !skipsPermission }
    }

    public func next() {
        guard let index = steps.firstIndex(of: step), steps.indices.contains(index + 1) else { return }
        step = steps[index + 1]
    }

    public func previous() {
        guard let index = steps.firstIndex(of: step), index > 0 else { return }
        step = steps[index - 1]
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
