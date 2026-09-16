import AppKit

struct CaptureResult {
    let image: CGImage
    let scale: CGFloat
    /// Selected area in global AppKit point coordinates (bottom-left origin).
    let globalRect: CGRect
}

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Full-screen, frozen-frame region selector — one window per display.
final class SelectionOverlayController {
    private var windows: [OverlayWindow] = []
    private var completion: ((CaptureResult?) -> Void)?
    private var finished = false

    func begin(shots: [DisplayShot], completion: @escaping (CaptureResult?) -> Void) {
        self.completion = completion

        for shot in shots {
            let window = OverlayWindow(contentRect: shot.frame,
                                       styleMask: .borderless,
                                       backing: .buffered,
                                       defer: false)
            window.level = .init(Int(CGShieldingWindowLevel()))
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isReleasedWhenClosed = false

            let view = OverlayView(shot: shot)
            view.onSelect = { [weak self] rect in self?.finish(shot: shot, rect: rect) }
            view.onCancel = { [weak self] in self?.finish(shot: shot, rect: nil) }
            window.contentView = view
            window.setFrame(shot.frame, display: true)
            window.orderFrontRegardless()
            windows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKeyAndOrderFront(nil)
        NSCursor.crosshair.set()
    }

    private func finish(shot: DisplayShot, rect: CGRect?) {
        guard !finished else { return }
        finished = true

        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        NSCursor.arrow.set()

        guard let rect, rect.width >= 3, rect.height >= 3 else {
            completion?(nil)
            completion = nil
            return
        }

        let sx = CGFloat(shot.image.width) / shot.frame.width
        let sy = CGFloat(shot.image.height) / shot.frame.height
        let pixelRect = CGRect(x: (rect.minX * sx).rounded(.down),
                               y: ((shot.frame.height - rect.maxY) * sy).rounded(.down),
                               width: (rect.width * sx).rounded(),
                               height: (rect.height * sy).rounded())
            .intersection(CGRect(x: 0, y: 0, width: shot.image.width, height: shot.image.height))

        guard let cropped = shot.image.cropping(to: pixelRect) else {
            completion?(nil)
            completion = nil
            return
        }

        let globalRect = CGRect(x: shot.frame.minX + rect.minX,
                                y: shot.frame.minY + rect.minY,
                                width: rect.width,
                                height: rect.height)
        completion?(CaptureResult(image: cropped, scale: sx, globalRect: globalRect))
        completion = nil
    }
}

final class OverlayView: NSView {
    var onSelect: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let shot: DisplayShot
    private let backdrop: NSImage
    private var anchor: CGPoint?
    private var current: CGPoint?
    private var mouse: CGPoint = .zero
    private var hasMoved = false

    init(shot: DisplayShot) {
        self.shot = shot
        self.backdrop = NSImage(cgImage: shot.image, size: shot.frame.size)
        super.init(frame: CGRect(origin: .zero, size: shot.frame.size))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private var selectionRect: CGRect? {
        guard let anchor, let current else { return nil }
        return CGRect(x: min(anchor.x, current.x),
                      y: min(anchor.y, current.y),
                      width: abs(current.x - anchor.x),
                      height: abs(current.y - anchor.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        backdrop.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)

        let dim = NSColor.black.withAlphaComponent(0.45)
        if let sel = selectionRect {
            dim.setFill()
            // Dim everything outside the selection.
            NSRect(x: 0, y: sel.maxY, width: bounds.width, height: bounds.height - sel.maxY).fill()
            NSRect(x: 0, y: 0, width: bounds.width, height: sel.minY).fill()
            NSRect(x: 0, y: sel.minY, width: sel.minX, height: sel.height).fill()
            NSRect(x: sel.maxX, y: sel.minY, width: bounds.width - sel.maxX, height: sel.height).fill()

            NSColor.white.setStroke()
            let border = NSBezierPath(rect: sel.insetBy(dx: -0.5, dy: -0.5))
            border.lineWidth = 1
            border.stroke()

            drawSizeLabel(for: sel)
        } else {
            dim.setFill()
            bounds.fill()
            drawCrosshair()
            drawHint()
        }
    }

    private func drawCrosshair() {
        NSColor.white.withAlphaComponent(0.55).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: CGPoint(x: mouse.x + 0.5, y: 0))
        path.line(to: CGPoint(x: mouse.x + 0.5, y: bounds.height))
        path.move(to: CGPoint(x: 0, y: mouse.y + 0.5))
        path.line(to: CGPoint(x: bounds.width, y: mouse.y + 0.5))
        path.stroke()
    }

    private func drawHint() {
        let text = "Drag to select an area   ·   Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let box = CGRect(x: (bounds.width - size.width) / 2 - 14,
                         y: bounds.height * 0.75,
                         width: size.width + 28,
                         height: size.height + 16)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: box, xRadius: 9, yRadius: 9).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 14, y: box.minY + 8), withAttributes: attrs)
    }

    private func drawSizeLabel(for sel: CGRect) {
        let px = Int((sel.width * shot.scale).rounded())
        let py = Int((sel.height * shot.scale).rounded())
        let text = "\(Int(sel.width.rounded())) × \(Int(sel.height.rounded()))  (\(px) × \(py) px)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        var origin = CGPoint(x: sel.minX, y: sel.maxY + 8)
        if origin.y + size.height + 8 > bounds.height { origin.y = sel.minY - size.height - 16 }
        origin.x = min(max(4, origin.x), bounds.width - size.width - 16)

        let box = CGRect(x: origin.x, y: origin.y, width: size.width + 12, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 6, y: box.minY + 4), withAttributes: attrs)
    }

    /// Drives the view into a given state for the offscreen UI test.
    func previewState(selection: CGRect?, mouse point: CGPoint) {
        if let selection {
            anchor = CGPoint(x: selection.minX, y: selection.minY)
            current = CGPoint(x: selection.maxX, y: selection.maxY)
        } else {
            anchor = nil
            current = nil
        }
        mouse = point
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        mouse = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        current = anchor
        hasMoved = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        hasMoved = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        guard hasMoved, let rect = selectionRect, rect.width >= 3, rect.height >= 3 else {
            onCancel?()
            return
        }
        onSelect?(rect)
    }

    override func rightMouseDown(with event: NSEvent) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Escape
            onCancel?()
        case 49: // Space — grab the whole display
            onSelect?(bounds)
        default:
            super.keyDown(with: event)
        }
    }
}
