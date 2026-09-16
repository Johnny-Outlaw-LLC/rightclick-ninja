import AppKit
import Carbon.HIToolbox

enum HotKeyID: UInt32 {
    case regionCapture = 1
    case regionCaptureAlt = 2
    case fullScreenCapture = 3
}

/// Registers system-wide hot keys using Carbon's RegisterEventHotKey.
/// This works for background (LSUIElement) apps and does **not** require
/// Accessibility permission, unlike a CGEventTap.
final class HotKeyManager {
    var onHotKey: ((HotKeyID) -> Void)?

    /// False when Print Screen / F13 could not be claimed — usually because
    /// another app already owns it. The menu says so rather than leaving the
    /// key looking broken.
    private(set) var printScreenAvailable = true

    private var refs: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?

    private static var shared: HotKeyManager?

    func registerAll() {
        HotKeyManager.shared = self
        installHandler()

        // Print Screen on a PC keyboard reports as F13 on macOS.
        printScreenAvailable = register(keyCode: UInt32(kVK_F13), modifiers: 0, id: .regionCapture)
        // Fallback for Mac keyboards without an F13 key.
        _ = register(keyCode: UInt32(kVK_ANSI_4),
                     modifiers: UInt32(controlKey | shiftKey | cmdKey),
                     id: .regionCaptureAlt)
        _ = register(keyCode: UInt32(kVK_ANSI_3),
                     modifiers: UInt32(controlKey | shiftKey | cmdKey),
                     id: .fullScreenCapture)
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hkID)
            guard status == noErr, let id = HotKeyID(rawValue: hkID.id) else { return noErr }
            DispatchQueue.main.async { HotKeyManager.shared?.onHotKey?(id) }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    @discardableResult
    private func register(keyCode: UInt32, modifiers: UInt32, id: HotKeyID) -> Bool {
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x52_43_4E_4B), id: id.rawValue) // 'RCNK'
        let status = RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return false }
        refs.append(ref)
        return true
    }

    deinit {
        for ref in refs { if let ref { UnregisterEventHotKey(ref) } }
        if let handler { RemoveEventHandler(handler) }
    }
}
