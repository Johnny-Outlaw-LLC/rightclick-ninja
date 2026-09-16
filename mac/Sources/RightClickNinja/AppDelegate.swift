import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let hotKeys = HotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenuBuilder.install()
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        hotKeys.onHotKey = { id in
            switch id {
            case .regionCapture, .regionCaptureAlt: CaptureController.shared.startRegionCapture()
            case .fullScreenCapture: CaptureController.shared.startFullScreenCapture()
            }
        }
        hotKeys.registerAll()
        setupStatusItem()

        if ScreenCapturer.isTranslocated {
            DispatchQueue.main.async { ScreenCapturer.presentTranslocationAlert() }
        } else {
            Task { await ScreenCapturer.warmUp() }
        }

        if let index = CommandLine.arguments.firstIndex(of: "--open"),
           index + 1 < CommandLine.arguments.count {
            openInEditor(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }

        let launchPaths = CommandLine.arguments.dropFirst().filter {
            !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0)
        }
        if !launchPaths.isEmpty {
            DateShiftWindowController.shared.importPaths(Array(launchPaths))
            DateShiftWindowController.shared.showWindow()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        DateShiftWindowController.shared.importPaths(urls.map(\.path))
        DateShiftWindowController.shared.showWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            DateShiftWindowController.shared.showWindow()
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Finder Service
    // Selector must match Info.plist NSMessage: dateShiftService

    @objc func dateShiftService(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else { return }
        DateShiftWindowController.shared.importPaths(urls.map(\.path))
        DateShiftWindowController.shared.showWindow()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "Right Click Ninja")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let region = NSMenuItem(title: "Capture Region…", action: #selector(captureRegion), keyEquivalent: "")
        region.target = self
        menu.addItem(region)

        let full = NSMenuItem(title: "Capture Full Screen", action: #selector(captureFullScreen), keyEquivalent: "")
        full.target = self
        menu.addItem(full)

        let open = NSMenuItem(title: "Open Image in Editor…", action: #selector(openImage), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let dates = NSMenuItem(title: "Date Shift…", action: #selector(openDateShift), keyEquivalent: "")
        dates.target = self
        menu.addItem(dates)

        menu.addItem(.separator())

        let hintTitle = hotKeys.printScreenAvailable
            ? "Shortcut: Print Screen (F13)  ·  ⌃⇧⌘4"
            : "Shortcut: ⌃⇧⌘4  ·  Print Screen (F13) is taken by another app"
        let hint = NSMenuItem(title: hintTitle, action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        let perms = NSMenuItem(title: "Screen Recording Permission…", action: #selector(openPermissions), keyEquivalent: "")
        perms.target = self
        menu.addItem(perms)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Right Click Ninja", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc func newCapture(_ sender: Any?) { CaptureController.shared.startRegionCapture() }
    @objc func newDateShift(_ sender: Any?) { DateShiftWindowController.shared.showWindow() }

    @objc private func captureRegion() { CaptureController.shared.startRegionCapture() }
    @objc private func captureFullScreen() { CaptureController.shared.startFullScreenCapture() }
    @objc private func openDateShift() { DateShiftWindowController.shared.showWindow() }

    @objc private func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic, .gif, .bmp]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openInEditor(url)
    }

    private func openInEditor(_ url: URL) {
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            NSSound.beep()
            return
        }
        let scale = CGFloat(cg.width) / max(image.size.width, 1)
        EditorWindowController.open(image: cg, scale: scale,
                                    suggestedName: url.deletingPathExtension().lastPathComponent)
    }

    @objc private func openPermissions() {
        ScreenCapturer.openScreenRecordingSettings()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
