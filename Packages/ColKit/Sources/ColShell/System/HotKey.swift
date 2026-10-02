import Carbon.HIToolbox
import Foundation

/// A system-wide keyboard shortcut, through the Carbon hot key API: it needs no permission and never sees other
/// keystrokes.
@MainActor
final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    nonisolated static let signature = OSType(0x49534C54) // "ISLT"

    /// Control, Option and Command with I: free in macOS and in common apps.
    static let defaultShortcut = (key: UInt32(kVK_ANSI_I), modifiers: UInt32(controlKey | optionKey | cmdKey))

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func register() {
        guard reference == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            // The prompter's shortcuts reach the app too: leave them to their own handler.
            guard id.signature == HotKey.signature else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &type, context, &handler)
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        RegisterEventHotKey(Self.defaultShortcut.key, Self.defaultShortcut.modifiers, id, GetApplicationEventTarget(), 0, &reference)
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil
        handler = nil
    }
}
