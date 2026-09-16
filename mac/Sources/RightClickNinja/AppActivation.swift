import AppKit

@MainActor
enum AppActivation {
    static func becomeRegular() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func considerAccessory() {
        if EditorWindowController.hasOpenEditors { return }
        if DateShiftWindowController.shared.isVisible { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
