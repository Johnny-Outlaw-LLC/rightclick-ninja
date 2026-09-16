import AppKit

@MainActor
final class CaptureController: NSObject {
    static let shared = CaptureController()

    private var overlay: SelectionOverlayController?
    private var busy = false
    private var pending: CaptureResult?

    // MARK: - Entry points

    func startRegionCapture() {
        guard !busy else { return }
        busy = true
        Task {
            do {
                let shots = try await ScreenCapturer.captureAllDisplays()
                let controller = SelectionOverlayController()
                overlay = controller
                controller.begin(shots: shots) { [weak self] result in
                    guard let self else { return }
                    self.overlay = nil
                    self.busy = false
                    guard let result else { return }
                    self.presentDestinationMenu(for: result)
                }
            } catch {
                busy = false
                ScreenCapturer.presentPermissionAlert()
            }
        }
    }

    func startFullScreenCapture() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let shot = try await ScreenCapturer.captureDisplay(containing: NSEvent.mouseLocation)
                let result = CaptureResult(image: shot.image, scale: shot.scale, globalRect: shot.frame)
                presentDestinationMenu(for: result)
            } catch {
                ScreenCapturer.presentPermissionAlert()
            }
        }
    }

    // MARK: - Destination menu

    private func presentDestinationMenu(for result: CaptureResult) {
        pending = result

        let menu = NSMenu()
        menu.autoenablesItems = false

        func add(_ title: String, _ symbol: String, _ action: Selector, _ key: String) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }

        add("Copy to Clipboard", "doc.on.clipboard", #selector(destCopy), "c")
        add("Save to Desktop", "desktopcomputer", #selector(destDesktop), "d")
        add("Save As…", "square.and.arrow.down", #selector(destSaveAs), "s")
        add("Open in Editor", "pencil.tip.crop.circle", #selector(destEditor), "e")
        menu.addItem(.separator())
        add("Cancel", "xmark", #selector(destCancel), "")

        NSApp.activate(ignoringOtherApps: true)

        // Place the menu just inside the selection's top-left corner when possible.
        var point = NSEvent.mouseLocation
        if result.globalRect.width > 40 {
            point = CGPoint(x: result.globalRect.minX + 6, y: result.globalRect.maxY - 6)
        }
        // Note: the chosen item's action may fire either during or just after
        // this call, so `pending` is cleared by the actions themselves.
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    // MARK: - Destinations

    @objc private func destCopy() {
        guard let result = pending else { return }
        ImageOutput.copyToClipboard(result.image, scale: result.scale)
        HUD.show("Copied to clipboard")
        pending = nil
    }

    @objc private func destDesktop() {
        guard let result = pending else { return }
        if let url = ImageOutput.saveToDesktop(result.image, scale: result.scale) {
            HUD.show("Saved \(url.lastPathComponent)")
        } else {
            HUD.show("Could not save to Desktop")
        }
        pending = nil
    }

    @objc private func destSaveAs() {
        guard let result = pending else { return }
        if let url = ImageOutput.saveAs(result.image, scale: result.scale) {
            HUD.show("Saved \(url.lastPathComponent)")
        }
        pending = nil
    }

    @objc private func destEditor() {
        guard let result = pending else { return }
        EditorWindowController.open(image: result.image, scale: result.scale)
        pending = nil
    }

    @objc private func destCancel() { pending = nil }
}
