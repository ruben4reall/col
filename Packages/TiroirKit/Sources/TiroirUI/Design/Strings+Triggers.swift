import Foundation
import TiroirCore

/// The words of triggers: Settings, Triggers, its sentences and its editor.
extension Strings {
    // MARK: Triggers pane

    public static let triggers = String(localized: "Triggers", bundle: .module)
    public static let triggersSubtitle = String(localized: "A trigger changes the menu bar while something is true, and puts it back when it no longer is.", bundle: .module)
    public static let noTriggersYet = String(localized: "No triggers yet: start from one of these, or add your own.", bundle: .module)
    public static let addTrigger = String(localized: "Add Trigger", bundle: .module)
    public static let editMenuItem = String(localized: "Edit…", bundle: .module)
    public static let activeNow = String(localized: "Active now", bundle: .module)
    public static let deleteTriggerQuestion = String(localized: "Delete this trigger?", bundle: .module)
    public static let profileIsGone = String(localized: "Its profile no longer exists, so it does nothing.", bundle: .module)
    public static let drawerIsGone = String(localized: "Its drawer is not in the current setup, so it does nothing for now.", bundle: .module)

    // MARK: Examples

    public static func exampleBattery(level: String) -> String {
        String(format: String(localized: "Show Battery when it drops below %@", bundle: .module), level)
    }

    public static let exampleChatDrawer = String(localized: "Show the drawer of your chat apps while the camera or microphone is on", bundle: .module)

    public static func exampleDrawer(_ name: String) -> String {
        String(format: String(localized: "Show the %@ drawer while the camera or microphone is on", bundle: .module), name)
    }

    public static let exampleKeynote = String(localized: "Focus while Keynote is in front", bundle: .module)

    // MARK: Sentences

    /// "When Zoom is open, show the Messages drawer in the menu bar".
    public static func triggerSentence(when condition: String, then action: String) -> String {
        String(format: String(localized: "When %@, %@", bundle: .module), condition, action)
    }

    public static func appIsOpen(_ app: String) -> String {
        String(format: String(localized: "%@ is open", bundle: .module), app)
    }

    public static func appIsInFront(_ app: String) -> String {
        String(format: String(localized: "%@ is in front", bundle: .module), app)
    }

    public static let macIsOnBattery = String(localized: "the Mac runs on battery", bundle: .module)

    public static func batteryIsAtOrBelow(_ level: String) -> String {
        String(format: String(localized: "the battery is at or below %@", bundle: .module), level)
    }

    public static let externalDisplayIsConnected = String(localized: "an external display is connected", bundle: .module)

    public static func timeIsBetween(_ from: String, and to: String) -> String {
        String(format: String(localized: "it is between %@ and %@", bundle: .module), from, to)
    }

    public static let cameraOrMicrophoneIsInUse = String(localized: "the camera or the microphone is in use", bundle: .module)

    public static func switchToTheProfile(_ name: String) -> String {
        String(format: String(localized: "switch to the %@ profile", bundle: .module), name)
    }

    public static func showTheDrawer(_ name: String) -> String {
        String(format: String(localized: "show the %@ drawer in the menu bar", bundle: .module), name)
    }

    public static func showTheIcon(_ name: String) -> String {
        String(format: String(localized: "show %@ in the menu bar", bundle: .module), name)
    }

    public static let turnOnFocus = String(localized: "turn on Focus", bundle: .module)
    public static let switchToADeletedProfile = String(localized: "switch to a deleted profile", bundle: .module)
    public static let showADeletedDrawer = String(localized: "show a deleted drawer in the menu bar", bundle: .module)

    /// "20%", the way this Mac writes a percentage.
    public static func percent(_ value: Int) -> String {
        (Double(value) / 100).formatted(.percent.precision(.fractionLength(0)))
    }

    /// "18:30" or "6:30 PM", the way this Mac writes a time of day.
    public static func time(ofMinutes minutes: Int) -> String {
        let calendar = Calendar.current
        let date = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Editor

    public static let newTrigger = String(localized: "New Trigger", bundle: .module)
    public static let editTrigger = String(localized: "Edit Trigger", bundle: .module)
    public static let when = String(localized: "When", bundle: .module)
    public static let then = String(localized: "Then", bundle: .module)

    public static func conditionName(_ kind: TriggerCondition.Kind) -> String {
        switch kind {
        case .appOpen: String(localized: "An app is open", bundle: .module)
        case .appInFront: String(localized: "An app is in front", bundle: .module)
        case .onBattery: String(localized: "The Mac runs on battery", bundle: .module)
        case .batteryAtOrBelow: String(localized: "The battery is at or below a level", bundle: .module)
        case .externalDisplay: String(localized: "An external display is connected", bundle: .module)
        case .timeOfDay: String(localized: "It is between two times", bundle: .module)
        case .cameraOrMicrophone: String(localized: "The camera or the microphone is in use", bundle: .module)
        }
    }

    public static func actionName(_ kind: TriggerAction.Kind) -> String {
        switch kind {
        case .switchProfile: String(localized: "Switch to a profile", bundle: .module)
        case .showDrawer: String(localized: "Show a drawer's icons in the menu bar", bundle: .module)
        case .showIcon: String(localized: "Show an icon in the menu bar", bundle: .module)
        case .focus: String(localized: "Turn on Focus", bundle: .module)
        }
    }

    public static let app = String(localized: "App", bundle: .module)
    /// What a picker shows until something is chosen.
    public static let chooseOne = String(localized: "Choose…", bundle: .module)
    public static let openNow = String(localized: "Open Now", bundle: .module)
    public static let otherApp = String(localized: "Other App…", bundle: .module)
    public static let choose = String(localized: "Choose", bundle: .module)
    public static let chooseAppMessage = String(localized: "Choose the app this trigger watches.", bundle: .module)
    public static let level = String(localized: "Level", bundle: .module)
    public static let from = String(localized: "From", bundle: .module)
    public static let to = String(localized: "To", bundle: .module)
    public static let sameTimes = String(localized: "Choose two different times.", bundle: .module)
    /// "A range can cross midnight: from 22:00 to 07:00, for instance."
    public static func timeRangeNote(from: String, to: String) -> String {
        String(format: String(localized: "A range can cross midnight: from %@ to %@, for instance.", bundle: .module), from, to)
    }

    public static let batteryLevelNote = String(localized: "Plugged in or not.", bundle: .module)
    public static let cameraOrMicrophoneNote = String(localized: "Tiroir only reads whether a camera or a microphone runs; it never records anything and needs no permission.", bundle: .module)
    public static let profile = String(localized: "Profile", bundle: .module)

    /// "iStat Menus, CPU": an icon told apart from its app's other icons.
    public static func nameWithLabel(_ name: String, _ label: String) -> String {
        String(format: String(localized: "%@, %@", bundle: .module), name, label)
    }

    public static let drawer = String(localized: "Drawer", bundle: .module)
    public static let needsAProfile = String(localized: "Save a profile first, in Profiles.", bundle: .module)
    public static let needsADrawer = String(localized: "Make a drawer first, in Drawers.", bundle: .module)
    public static let needsAnIcon = String(localized: "Tiroir sees no icon to show yet.", bundle: .module)
    public static let profileEndsNote = String(localized: "When the condition ends, the profile you had before comes back.", bundle: .module)
}
