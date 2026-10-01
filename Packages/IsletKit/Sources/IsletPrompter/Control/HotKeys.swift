import Carbon.HIToolbox
import Foundation

/// System-wide shortcuts through the Carbon hot key API: no permission needed, and no other keystroke is ever seen.
@MainActor
final class HotKeys {
    struct Binding {
        let key: Int
        let modifiers: Int
        /// How the shortcut reads, for Settings when another app already holds it.
        var label = ""
        let action: @MainActor () -> Void
    }

    private var handler: EventHandlerRef?
    private var registered: [UInt32: (reference: EventHotKeyRef?, action: @MainActor () -> Void)] = [:]
    private var nextID: UInt32 = 1
    nonisolated static let signature = OSType(0x5052_4D54) // "PRMT"

    /// The chord every shortcut shares: Control, Option and Command.
    static let chord = controlKey | optionKey | cmdKey

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            // Islet's own shortcut reaches this handler too: leave it to its handler.
            guard id.signature == HotKeys.signature else { return OSStatus(eventNotHandledErr) }
            let keys = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { keys.fire(id.id) }
            return noErr
        }, 1, &type, context, &handler)
    }

    /// Registers a group of shortcuts. Returns their ids, to remove them together later, and the labels of those
    /// macOS refused because another app holds them.
    @discardableResult
    func register(_ bindings: [Binding]) -> (ids: [UInt32], taken: [String]) {
        var ids: [UInt32] = []
        var taken: [String] = []
        for binding in bindings {
            let id = nextID
            nextID += 1
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(binding.key), UInt32(binding.modifiers), EventHotKeyID(signature: Self.signature, id: id),
                                             GetApplicationEventTarget(), 0, &reference)
            if status == noErr {
                registered[id] = (reference, binding.action)
                ids.append(id)
            } else {
                taken.append(binding.label)
            }
        }
        return (ids, taken)
    }

    func unregister(_ ids: [UInt32]) {
        for id in ids {
            if let reference = registered[id]?.reference { UnregisterEventHotKey(reference) }
            registered[id] = nil
        }
    }

    private func fire(_ id: UInt32) {
        registered[id]?.action()
    }
}
