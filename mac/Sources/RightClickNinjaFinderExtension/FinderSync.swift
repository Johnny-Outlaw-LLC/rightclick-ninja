import AppKit
import FinderSync

@objc(RightClickNinjaFinderSync)
final class RightClickNinjaFinderSync: FIFinderSync {
    override init() {
        super.init()

        // Finder Sync applies registered folders recursively. Registering the
        // root makes the commands available in every Finder location,
        // including external drives mounted below /Volumes. The extension
        // does not request badges or scan these folders.
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/", isDirectory: true)
        ]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let menu = NSMenu(title: "Right Click Ninja")

        switch menuKind {
        case .contextualMenuForItems, .contextualMenuForSidebar, .toolbarItemMenu:
            let changeDate = NSMenuItem(
                title: "Change Date…",
                action: #selector(changeDate(_:)),
                keyEquivalent: ""
            )
            changeDate.target = self
            changeDate.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: nil)
            menu.addItem(changeDate)

            let screenshot = NSMenuItem(
                title: "Take Screenshot",
                action: #selector(takeScreenshot(_:)),
                keyEquivalent: ""
            )
            screenshot.target = self
            screenshot.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)
            menu.addItem(screenshot)

        case .contextualMenuForContainer:
            let screenshot = NSMenuItem(
                title: "Take Screenshot",
                action: #selector(takeScreenshot(_:)),
                keyEquivalent: ""
            )
            screenshot.target = self
            screenshot.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: nil)
            menu.addItem(screenshot)

        @unknown default:
            return nil
        }

        return menu
    }

    @objc private func changeDate(_ sender: Any?) {
        let controller = FIFinderSyncController.default()
        var urls = controller.selectedItemURLs() ?? []
        if urls.isEmpty, let target = controller.targetedURL() {
            urls = [target]
        }
        guard !urls.isEmpty else { return }
        openHost(action: "change-date", paths: urls)
    }

    @objc private func takeScreenshot(_ sender: Any?) {
        openHost(action: "take-screenshot")
    }

    private func openHost(action: String, paths: [URL] = []) {
        var components = URLComponents()
        components.scheme = "rightclickninja"
        components.host = action
        if !paths.isEmpty {
            components.queryItems = paths.map { URLQueryItem(name: "path", value: $0.path) }
        }

        guard let url = components.url else {
            NSSound.beep()
            return
        }
        NSWorkspace.shared.open(url)
    }
}
