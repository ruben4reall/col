import Foundation

/// MenuBarAgent's restriction on macOS 27, kept to one live assertion (spec 4.4, Hiding).
@MainActor
public protocol RestrictionControlling: AnyObject {
    var isAvailable: Bool { get }
    /// The allow list in force, nil while nothing is restricted.
    var appliedAllowList: [String]? { get }
    /// Replaces the restriction. Returns MenuBarAgent's error, if it refused.
    func apply(allowed: [String]) async -> Error?
    /// Ends the restriction: every icon shows again at once.
    func release()
}

public enum RestrictionError: Error, Equatable {
    case unavailable
    case noAnswer
}

@MainActor
public final class MenuBarRestriction: RestrictionControlling {
    private var active: (assertion: PrivateAPI.MenuBarAssertion, allowed: [String])?
    private var pending: PrivateAPI.MenuBarAssertion?
    /// MenuBarAgent answers in milliseconds; past this, Tiroir stops waiting and keeps the previous restriction.
    static let answerTimeout: Duration = .seconds(2)

    public init() {}

    public var isAvailable: Bool { PrivateAPI.hasMenuBarRestriction }
    public var appliedAllowList: [String]? { active?.allowed }

    public func apply(allowed: [String]) async -> Error? {
        if active?.allowed == allowed { return nil }
        pending?.invalidate()
        let answer = OneAnswer()
        let assertion = PrivateAPI.activateMenuBarRestriction(allowedBundleIdentifiers: allowed) { error in
            Task { @MainActor in answer.give(error.map { $0 as NSError }) }
        }
        guard let assertion else { return RestrictionError.unavailable }
        pending = assertion
        Task { @MainActor in
            try? await Task.sleep(for: Self.answerTimeout)
            answer.give(RestrictionError.noAnswer as NSError)
        }
        let error = await answer.wait()
        // A newer request replaced this one while it waited: it no longer matters.
        guard pending === assertion else { return nil }
        pending = nil
        if let error {
            // A failed replacement must not unhide anything: the previous restriction stays.
            assertion.invalidate()
            return error
        }
        // The old assertion goes only once the new one holds, so no icon flashes.
        active?.assertion.invalidate()
        active = (assertion, allowed)
        return nil
    }

    public func release() {
        pending?.invalidate()
        pending = nil
        active?.assertion.invalidate()
        active = nil
    }
}

/// The first answer wins; later ones are ignored.
@MainActor
final class OneAnswer {
    private var value: NSError??
    private var waiter: CheckedContinuation<NSError?, Never>?

    func give(_ error: NSError?) {
        guard value == nil else { return }
        value = .some(error)
        waiter?.resume(returning: error)
        waiter = nil
    }

    func wait() async -> NSError? {
        if let value { return value }
        return await withCheckedContinuation { waiter = $0 }
    }
}
