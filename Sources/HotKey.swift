import AppKit
import Carbon.HIToolbox

/// System-wide hotkey (default ⌥⌘Space) to summon/dismiss AgentPad. No entitlement required.
final class HotKeyManager {
    static let shared = HotKeyManager()
    private var ref: EventHotKeyRef?
    var onTrigger: (() -> Void)?

    func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            HotKeyManager.shared.onTrigger?()
            return noErr
        }, 1, &spec, nil, nil)

        let id = EventHotKeyID(signature: 0x41504144 /* 'APAD' */, id: 1)
        RegisterEventHotKey(UInt32(kVK_Space),
                            UInt32(cmdKey | optionKey),
                            id, GetApplicationEventTarget(), 0, &ref)
    }
}
