import Foundation
import TiroirCore

/// Triggers in words: "When Zoom is open, show the Messages drawer in the menu bar".
@MainActor
enum TriggerText {
    static func sentence(_ trigger: Trigger, in model: InterfaceModel) -> String {
        Strings.triggerSentence(when: condition(trigger.condition), then: action(trigger.action, in: model))
    }

    static func condition(_ condition: TriggerCondition) -> String {
        switch condition {
        case .appOpen(let bundleID): Strings.appIsOpen(AppLookup.name(of: bundleID))
        case .appInFront(let bundleID): Strings.appIsInFront(AppLookup.name(of: bundleID))
        case .onBattery: Strings.macIsOnBattery
        case .batteryAtOrBelow(let percent): Strings.batteryIsAtOrBelow(Strings.percent(percent))
        case .externalDisplay: Strings.externalDisplayIsConnected
        case .timeOfDay(let from, let to): Strings.timeIsBetween(Strings.time(ofMinutes: from), and: Strings.time(ofMinutes: to))
        case .cameraOrMicrophone: Strings.cameraOrMicrophoneIsInUse
        }
    }

    static func action(_ action: TriggerAction, in model: InterfaceModel) -> String {
        switch action {
        case .switchProfile(let id):
            model.settings.profile(id).map { Strings.switchToTheProfile(Strings.name(of: $0)) } ?? Strings.switchToADeletedProfile
        case .showDrawer(let id):
            drawerName(id, in: model).map(Strings.showTheDrawer) ?? Strings.showADeletedDrawer
        case .showIcon(let id):
            Strings.showTheIcon(iconName(id, in: model))
        case .focus:
            Strings.turnOnFocus
        }
    }

    /// Why a trigger does nothing, when it does nothing.
    static func problem(_ trigger: Trigger, in model: InterfaceModel) -> String? {
        switch trigger.action {
        case .switchProfile(let id): model.settings.profile(id) == nil ? Strings.profileIsGone : nil
        case .showDrawer(let id): model.settings.layout.drawer(id) == nil ? Strings.drawerIsGone : nil
        case .showIcon, .focus: nil
        }
    }

    /// A drawer's name, from the current setup or, when it lives in another profile only, from there.
    static func drawerName(_ id: UUID, in model: InterfaceModel) -> String? {
        if let drawer = model.settings.layout.drawer(id) { return drawer.name }
        return model.settings.profiles.lazy.compactMap { $0.layout.drawer(id)?.name }.first
    }

    /// An icon's name as Tiroir shows it, or its app's name when Tiroir does not see it right now.
    static func iconName(_ id: IconID, in model: InterfaceModel) -> String {
        model.row(id)?.name ?? AppLookup.name(of: id.bundleID)
    }
}

/// One of the examples an empty Triggers pane offers, added in one click.
struct TriggerExample: Identifiable {
    var id: String
    var title: String
    var symbol: String
    var trigger: Trigger

    /// Battery shows when it runs low, if this Mac has a Battery icon; the drawer of chat apps (or the first drawer)
    /// shows while the camera or the microphone is on, if there is a drawer; Focus while Keynote is in front.
    @MainActor
    static func examples(in model: InterfaceModel) -> [TriggerExample] {
        var examples: [TriggerExample] = []
        if let battery = model.icons.first(where: { $0.id.key == "com.apple.menuextra.battery" && $0.isMovable }) {
            examples.append(TriggerExample(
                id: "battery", title: Strings.exampleBattery(level: Strings.percent(20)), symbol: "battery.25percent",
                trigger: Trigger(condition: .batteryAtOrBelow(20), action: .showIcon(battery.id))))
        }
        let drawers = model.settings.layout.drawers
        if let chat = drawers.first(where: { $0.category == .messages }) {
            examples.append(TriggerExample(
                id: "chat", title: Strings.exampleChatDrawer, symbol: "video.fill",
                trigger: Trigger(condition: .cameraOrMicrophone, action: .showDrawer(chat.id))))
        } else if let first = drawers.first {
            examples.append(TriggerExample(
                id: "chat", title: Strings.exampleDrawer(first.name), symbol: "video.fill",
                trigger: Trigger(condition: .cameraOrMicrophone, action: .showDrawer(first.id))))
        }
        examples.append(TriggerExample(
            id: "keynote", title: Strings.exampleKeynote, symbol: "play.rectangle.fill",
            trigger: Trigger(condition: .appInFront("com.apple.iWork.Keynote"), action: .focus)))
        return examples
    }
}
