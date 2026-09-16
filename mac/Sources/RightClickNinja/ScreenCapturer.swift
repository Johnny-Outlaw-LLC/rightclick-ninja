import AppKit
import ScreenCaptureKit

struct DisplayShot {
    let displayID: CGDirectDisplayID
    let image: CGImage
    /// Screen frame in global (AppKit, bottom-left origin) point coordinates.
    let frame: CGRect
    /// Backing scale: image pixels per point.
    let scale: CGFloat
    let screen: NSScreen
}

enum ScreenCaptureError: LocalizedError {
    case noPermission
    case noDisplays

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Right Click Ninja needs Screen Recording permission to capture the screen."
        case .noDisplays:
            return "No displays were available to capture."
        }
    }
}

enum ScreenCapturer {
    static func warmUp() async {
        _ = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    static func captureAllDisplays() async throws -> [DisplayShot] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw ScreenCaptureError.noPermission
        }
        guard !content.displays.isEmpty else { throw ScreenCaptureError.noDisplays }

        var shots: [DisplayShot] = []
        for display in content.displays {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else { continue }
            if let image = try? await capture(display: display, content: content, screen: screen) {
                shots.append(DisplayShot(displayID: display.displayID,
                                         image: image,
                                         frame: screen.frame,
                                         scale: screen.backingScaleFactor,
                                         screen: screen))
            }
        }
        guard !shots.isEmpty else { throw ScreenCaptureError.noDisplays }
        return shots
    }

    static func captureDisplay(containing point: CGPoint) async throws -> DisplayShot {
        let shots = try await captureAllDisplays()
        return shots.first(where: { $0.frame.contains(point) }) ?? shots[0]
    }

    private static func capture(display: SCDisplay,
                                content: SCShareableContent,
                                screen: NSScreen) async throws -> CGImage {
        let ourApp = content.applications.first { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display,
                                     excludingApplications: ourApp.map { [$0] } ?? [],
                                     exceptingWindows: [])

        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        config.captureResolution = .best
        config.scalesToFit = false

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    static var isTranslocated: Bool {
        Bundle.main.bundlePath.contains("/AppTranslocation/")
    }

    static func presentTranslocationAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move Right Click Ninja to Applications"
        alert.informativeText = """
        Right Click Ninja was opened straight from the folder it was downloaded to, so macOS is \
        running it from a temporary read-only copy. Screen Recording permission can't \
        stick to that copy — enabling it in System Settings won't help.

        Quit the app, drag Right Click Ninja.app into your Applications folder, then open it \
        from there. The installer package does this for you.
        """
        alert.addButton(withTitle: "Quit Right Click Ninja")
        alert.addButton(withTitle: "Continue Anyway")
        if alert.runModal() == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
    }

    static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    static func resetPermissionAndQuit() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", Bundle.main.bundleIdentifier ?? "com.johnnyoutlaw.rightclickninja"]
        try? process.run()
        process.waitUntilExit()
        NSApp.terminate(nil)
    }

    static func presentPermissionAlert() {
        if isTranslocated {
            presentTranslocationAlert()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = """
        Right Click Ninja can't capture the screen yet.

        Open System Settings › Privacy & Security › Screen & System Audio Recording and enable Right Click Ninja, then try again.

        If it is already switched on there, macOS is holding a stale permission from an earlier build and the switch won't do anything. Reset it, then open the app again to get a fresh prompt.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Reset Permission & Quit")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: openScreenRecordingSettings()
        case .alertSecondButtonReturn: resetPermissionAndQuit()
        default: break
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
