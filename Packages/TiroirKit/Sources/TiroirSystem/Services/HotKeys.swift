import AppKit
import Carbon.HIToolbox
import TiroirCore

/// One shortcut registered with macOS.
public struct HotKeyRegistration: Hashable, Sendable {
    public let id: UInt32
}

/// Registers shortcuts with macOS; tests use a fake and never take a shortcut on the Mac.
@MainActor
public protocol HotKeyRegistrar: AnyObject {
    /// Nil when macOS refused it (another app holds it).
    func register(_ shortcut: Shortcut, onPress: @escaping @MainActor () -> Void) -> HotKeyRegistration?
    func unregister(_ registration: HotKeyRegistration)
}

/// Tiroir's global shortcuts (spec 6.3, Shortcuts). `RegisterEventHotKey` needs no Accessibility or Input Monitoring
/// permission: it hears its own shortcuts and nothing else. Pattern from Pli and Brainmerge.
@MainActor
public final class ShortcutCenter {
    public enum Action: Hashable, Sendable {
        case search
        case allDrawer
        case focus
        case showEverything
        case drawer(UUID)
        case profile(UUID)
        case icon(IconID)
    }

    private let registrar: HotKeyRegistrar
    private let onPress: @MainActor (Action) -> Void
    private var registered: [Action: (shortcut: Shortcut, registration: HotKeyRegistration)] = [:]

    public init(registrar: HotKeyRegistrar = CarbonHotKeyRegistrar(), onPress: @escaping @MainActor (Action) -> Void) {
        self.registrar = registrar
        self.onPress = onPress
    }

    /// Registers exactly `wanted`, keeping unchanged registrations. Returns the actions macOS refused.
    @discardableResult
    public func apply(_ wanted: [Action: Shortcut]) -> Set<Action> {
        for (action, current) in registered where wanted[action] != current.shortcut {
            registrar.unregister(current.registration)
            registered[action] = nil
        }
        var refused = Set<Action>()
        for (action, shortcut) in wanted where registered[action] == nil {
            guard shortcut.isUsable,
                  let registration = registrar.register(shortcut, onPress: { [weak self] in self?.onPress(action) }) else {
                refused.insert(action)
                continue
            }
            registered[action] = (shortcut, registration)
        }
        return refused
    }

    public func unregisterAll() {
        for (_, current) in registered { registrar.unregister(current.registration) }
        registered.removeAll()
    }

    /// The shortcuts settings ask for.
    public static func wanted(from settings: TiroirSettings) -> [Action: Shortcut] {
        var wanted: [Action: Shortcut] = [:]
        if let search = settings.shortcuts.search { wanted[.search] = search }
        if let all = settings.shortcuts.allDrawer { wanted[.allDrawer] = all }
        if let focus = settings.shortcuts.focus { wanted[.focus] = focus }
        if let showEverything = settings.shortcuts.showEverything { wanted[.showEverything] = showEverything }
        for drawer in settings.layout.drawers {
            if let shortcut = drawer.shortcut { wanted[.drawer(drawer.id)] = shortcut }
        }
        for profile in settings.profiles {
            if let shortcut = profile.shortcut { wanted[.profile(profile.id)] = shortcut }
        }
        for entry in settings.shortcuts.icons { wanted[.icon(entry.icon)] = entry.shortcut }
        return wanted
    }
}

/// The real registrar: Carbon's RegisterEventHotKey, and one handler on the app's event target for its presses.
@MainActor
public final class CarbonHotKeyRegistrar: HotKeyRegistrar {
    /// "TNSU": marks Tiroir's shortcuts among the app's hot key events.
    static let signature: OSType = 0x544E_5355
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var presses: [UInt32: @MainActor () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?

    public init() {}

    public func register(_ shortcut: Shortcut, onPress: @escaping @MainActor () -> Void) -> HotKeyRegistration? {
        guard installHandler() else { return nil }
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), Self.carbonModifiers(shortcut.modifiers),
                                         EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        refs[id] = ref
        presses[id] = onPress
        return HotKeyRegistration(id: id)
    }

    public func unregister(_ registration: HotKeyRegistration) {
        if let ref = refs.removeValue(forKey: registration.id) { UnregisterEventHotKey(ref) }
        presses[registration.id] = nil
    }

    fileprivate func pressed(_ id: EventHotKeyID) {
        guard id.signature == Self.signature else { return }
        presses[id.id]?()
    }

    static func carbonModifiers(_ modifiers: Shortcut.Modifiers) -> UInt32 {
        var bits: UInt32 = 0
        if modifiers.contains(.command) { bits |= UInt32(cmdKey) }
        if modifiers.contains(.option) { bits |= UInt32(optionKey) }
        if modifiers.contains(.control) { bits |= UInt32(controlKey) }
        if modifiers.contains(.shift) { bits |= UInt32(shiftKey) }
        return bits
    }

    /// Once: Carbon calls it on the main thread for each press of a shortcut this app registered.
    private func installHandler() -> Bool {
        guard handler == nil else { return true }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let read = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                         MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard read == noErr else { return read }
            let registrar = Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { registrar.pressed(id) }
            return noErr
        }, 1, &type, context, &handler)
        return status == noErr
    }
}

/// Recording a shortcut from a key press (the recorder in Settings).
public enum ShortcutRecording {
    public enum Result: Equatable, Sendable {
        case shortcut(Shortcut)
        case cancel
        case needsModifier
    }

    /// Esc alone cancels; a key without ⌘, ⌃ or ⌥ is refused.
    public static func record(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> Result {
        let held = modifiers.intersection([.command, .control, .option, .shift])
        if keyCode == UInt16(kVK_Escape), held.isEmpty { return .cancel }
        var bits: Shortcut.Modifiers = []
        if held.contains(.command) { bits.insert(.command) }
        if held.contains(.option) { bits.insert(.option) }
        if held.contains(.control) { bits.insert(.control) }
        if held.contains(.shift) { bits.insert(.shift) }
        let shortcut = Shortcut(keyCode: keyCode, modifiers: bits, keyLabel: keyLabel(keyCode: keyCode, characters: characters))
        return shortcut.isUsable ? .shortcut(shortcut) : .needsModifier
    }

    static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    static func keyLabel(keyCode: UInt16, characters: String?) -> String {
        if let named = namedKeys[Int(keyCode)] { return named }
        let text = (characters ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return text.isEmpty ? "Key \(keyCode)" : text
    }
}
