import Carbon.HIToolbox
import Foundation

/// A system-wide keyboard shortcut, through the Carbon hot key API: it needs no permission and never sees other
/// keystrokes.
@MainActor
final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private let id: UInt32
    private let key: UInt32
    private let modifiers: UInt32

    nonisolated static let signature = OSType(0x49534C54) // "ISLT"

    /// Control, Option and Command with I: free in macOS and in common apps.
    static let defaultShortcut = (key: UInt32(kVK_ANSI_I), modifiers: UInt32(controlKey | optionKey | cmdKey))
    /// Control, Option and Command with M: mutes or unmutes the microphone.
    static let microphoneShortcut = (key: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | optionKey | cmdKey))

    /// `id` tells Col's shortcuts apart: each one answers only its own.
    init(id: UInt32 = 1, shortcut: (key: UInt32, modifiers: UInt32) = defaultShortcut, action: @escaping () -> Void) {
        self.id = id
        key = shortcut.key
        modifiers = shortcut.modifiers
        self.action = action
    }

    func register() {
        guard reference == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            // The prompter's shortcuts, and Col's other ones, reach the app too: leave them to their own handler.
            guard pressed.signature == HotKey.signature, pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &type, context, &handler)
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        RegisterEventHotKey(key, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &reference)
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil
        handler = nil
    }
}
