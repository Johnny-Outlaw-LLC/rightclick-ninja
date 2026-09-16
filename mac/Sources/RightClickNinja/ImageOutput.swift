import AppKit
import UniformTypeIdentifiers

enum ImageOutput {
    static func nsImage(from cg: CGImage, scale: CGFloat) -> NSImage {
        let pointSize = NSSize(width: CGFloat(cg.width) / max(scale, 1),
                               height: CGFloat(cg.height) / max(scale, 1))
        return NSImage(cgImage: cg, size: pointSize)
    }

    static func data(from cg: CGImage, type: UTType, scale: CGFloat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cg)
        rep.size = NSSize(width: CGFloat(cg.width) / max(scale, 1),
                          height: CGFloat(cg.height) / max(scale, 1))
        switch type {
        case .jpeg:
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92])
        case .tiff:
            return rep.representation(using: .tiff, properties: [:])
        default:
            return rep.representation(using: .png, properties: [:])
        }
    }

    @discardableResult
    static func copyToClipboard(_ cg: CGImage, scale: CGFloat) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        var ok = false
        if let png = data(from: cg, type: .png, scale: scale) {
            ok = pb.setData(png, forType: .png)
        }
        if let tiff = data(from: cg, type: .tiff, scale: scale) {
            ok = pb.setData(tiff, forType: .tiff) || ok
        }
        return ok
    }

    static func defaultFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: Date()))"
    }

    @discardableResult
    static func saveToDesktop(_ cg: CGImage, scale: CGFloat, name: String? = nil) -> URL? {
        guard let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first,
              let png = data(from: cg, type: .png, scale: scale) else { return nil }
        var url = desktop.appendingPathComponent("\(name ?? defaultFileName()).png")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = desktop.appendingPathComponent("\(name ?? defaultFileName()) (\(counter)).png")
            counter += 1
        }
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Presents a save panel. Returns the written URL, or nil if cancelled/failed.
    @discardableResult
    static func saveAs(_ cg: CGImage, scale: CGFloat, suggestedName: String? = nil, window: NSWindow? = nil) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.nameFieldStringValue = "\(suggestedName ?? defaultFileName()).png"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        NSApp.activate(ignoringOtherApps: true)
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return nil }

        let type = UTType(filenameExtension: url.pathExtension) ?? .png
        guard let data = data(from: cg, type: type, scale: scale) else { return nil }
        do {
            try data.write(to: url)
            return url
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }
}

/// Small transient "toast" so the user knows a silent action succeeded.
enum HUD {
    private static var window: NSWindow?

    static func show(_ message: String, near point: CGPoint? = nil) {
        window?.orderOut(nil)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.sizeToFit()

        let padding: CGFloat = 16
        let size = NSSize(width: label.frame.width + padding * 2, height: label.frame.height + padding)

        let anchor = point ?? NSEvent.mouseLocation
        let frame = NSRect(x: anchor.x - size.width / 2, y: anchor.y + 24, width: size.width, height: size.height)

        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let box = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        box.material = .hudWindow
        box.state = .active
        box.blendingMode = .behindWindow
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.layer?.masksToBounds = true

        label.frame.origin = CGPoint(x: padding, y: padding / 2)
        box.addSubview(label)
        panel.contentView = box
        panel.orderFrontRegardless()
        window = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
                if window === panel { window = nil }
            }
        }
    }
}
