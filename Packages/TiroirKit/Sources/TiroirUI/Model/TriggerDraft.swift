import Foundation
import TiroirCore

/// A trigger being written in the editor. Every value is kept while the person tries other kinds, so going back to a
/// kind finds what was chosen for it.
public struct TriggerDraft: Identifiable, Equatable {
    public var id: UUID
    /// A trigger that does not exist yet.
    public var isNew: Bool
    public var isEnabled: Bool
    public var condition: TriggerCondition.Kind
    public var app: String?
    public var percent: Int
    public var from: Int
    public var to: Int
    public var action: TriggerAction.Kind
    public var profile: UUID?
    public var drawer: UUID?
    public var icon: IconID?

    /// The battery levels the editor offers.
    public static let percentRange = 5...95

    /// A new trigger: when an app is open, show the first drawer, or switch to the first profile, or Focus.
    public init(in settings: TiroirSettings) {
        id = UUID()
        isNew = true
        isEnabled = true
        condition = .appOpen
        percent = 20
        from = 9 * 60
        to = 17 * 60
        profile = settings.profiles.first?.id
        drawer = settings.layout.drawers.first?.id
        action = drawer != nil ? .showDrawer : (profile != nil ? .switchProfile : .focus)
    }

    /// An existing trigger. A profile or a drawer that no longer exists is left unchosen.
    public init(editing trigger: Trigger, in settings: TiroirSettings) {
        self.init(in: settings)
        id = trigger.id
        isNew = false
        isEnabled = trigger.isEnabled
        condition = trigger.condition.kind
        switch trigger.condition {
        case .appOpen(let bundleID), .appInFront(let bundleID): app = bundleID
        case .batteryAtOrBelow(let level): percent = level
        case .timeOfDay(let start, let end):
            from = start
            to = end
        case .onBattery, .externalDisplay, .cameraOrMicrophone: break
        }
        action = trigger.action.kind
        switch trigger.action {
        case .switchProfile(let id): profile = settings.profile(id) != nil ? id : nil
        case .showDrawer(let id): drawer = settings.layout.drawer(id) != nil ? id : nil
        case .showIcon(let id): icon = id
        case .focus: break
        }
    }

    /// The trigger the draft describes, or nil while something is missing: an app, two different times, a profile,
    /// a drawer or an icon.
    public var trigger: Trigger? {
        let condition: TriggerCondition
        switch self.condition {
        case .appOpen, .appInFront:
            guard let app, !app.isEmpty else { return nil }
            condition = self.condition == .appOpen ? .appOpen(app) : .appInFront(app)
        case .onBattery: condition = .onBattery
        case .batteryAtOrBelow: condition = .batteryAtOrBelow(percent)
        case .externalDisplay: condition = .externalDisplay
        case .timeOfDay:
            guard from != to else { return nil }
            condition = .timeOfDay(from: from, to: to)
        case .cameraOrMicrophone: condition = .cameraOrMicrophone
        }
        let action: TriggerAction
        switch self.action {
        case .switchProfile:
            guard let profile else { return nil }
            action = .switchProfile(profile)
        case .showDrawer:
            guard let drawer else { return nil }
            action = .showDrawer(drawer)
        case .showIcon:
            guard let icon else { return nil }
            action = .showIcon(icon)
        case .focus: action = .focus
        }
        return Trigger(id: id, isEnabled: isEnabled, condition: condition, action: action).clamped
    }
}
