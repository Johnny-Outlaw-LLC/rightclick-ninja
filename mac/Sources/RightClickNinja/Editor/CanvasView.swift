import AppKit

protocol CanvasViewDelegate: AnyObject {
    func canvasDidChangeSelection(_ canvas: CanvasView)
    func canvasDidEdit(_ canvas: CanvasView)
}

/// Draws the screenshot plus annotations. Coordinates are image pixels with a
/// top-left origin (the view is flipped), so exporting reuses the same code.
final class CanvasView: NSView, NSTextViewDelegate {

    weak var delegate: CanvasViewDelegate?

    private(set) var baseImage: CGImage
    private let baseNSImage: NSImage
    /// Image pixels per point — annotation widths/font sizes are multiplied by this.
    let contentScale: CGFloat

    private(set) var annotations: [Annotation] = []
    private(set) var selected: Annotation?

    var tool: ToolKind = .rectangle {
        didSet {
            if tool != .select { select(nil) }
            commitTextEditing()
            window?.invalidateCursorRects(for: self)
        }
    }

    var strokeColor: NSColor = .systemRed {
        didSet { applyStyleToSelection() }
    }
    var lineWidth: CGFloat = 3 {
        didSet { applyStyleToSelection() }
    }
    var fontSize: CGFloat = 24 {
        didSet { applyStyleToSelection() }
    }

    private enum DragMode {
        case none
        case creating(Annotation)
        case moving(origin1: CGPoint, origin2: CGPoint, start: CGPoint)
        case resizing(handle: Int, startRect: CGRect, startFont: CGFloat)
    }
    private var dragMode: DragMode = .none

    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    private var textView: NSTextView?
    private var editingAnnotation: Annotation?
    private var editingIsNew = false

    // MARK: - Init

    init(image: CGImage, scale: CGFloat) {
        self.baseImage = image
        self.contentScale = max(scale, 1)
        self.baseNSImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        super.init(frame: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: baseImage.width, height: baseImage.height)
    }

    private var magnification: CGFloat {
        max(enclosingScrollView?.magnification ?? 1, 0.05)
    }

    private var handleSize: CGFloat { 8 / magnification }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        render(includeSelection: false)

        if let selected, textView == nil {
            drawSelectionChrome(for: selected)
        }
        if let editing = editingAnnotation {
            let r = editing.rect.insetBy(dx: -2, dy: -2)
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: r)
            path.lineWidth = 1 / magnification
            path.setLineDash([4 / magnification, 3 / magnification], count: 2, phase: 0)
            path.stroke()
        }
    }

    /// Shared drawing routine used by both the screen view and the exporter.
    private func render(includeSelection: Bool) {
        drawBaseImage()
        for annotation in annotations {
            if annotation === editingAnnotation { continue } // live text view is showing it
            annotation.draw(scale: contentScale)
        }
    }

    /// `NSImage.draw(in:from:operation:fraction:)` ignores the view's flippedness;
    /// `respectFlipped: true` keeps the screenshot upright in this flipped canvas.
    private func drawBaseImage() {
        baseNSImage.draw(
            in: bounds,
            from: .zero,
            operation: .copy,
            fraction: 1.0,
            respectFlipped: true,
            hints: nil
        )
    }

    private func drawSelectionChrome(for annotation: Annotation) {
        let outline = NSBezierPath(rect: annotation.bounds(scale: contentScale).insetBy(dx: 2, dy: 2))
        NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
        outline.lineWidth = 1 / magnification
        outline.setLineDash([4 / magnification, 3 / magnification], count: 2, phase: 0)
        outline.stroke()

        let size = handleSize
        for point in annotation.handlePoints() {
            let r = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            NSColor.white.setFill()
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: r)
            path.lineWidth = 1 / magnification
            path.fill()
            path.stroke()
        }
    }

    // MARK: - Selection & styling

    func select(_ annotation: Annotation?) {
        guard selected !== annotation else { return }
        selected = annotation
        needsDisplay = true
        delegate?.canvasDidChangeSelection(self)
    }

    private func applyStyleToSelection() {
        guard let selected else { return }
        pushUndo()
        selected.color = strokeColor
        selected.lineWidth = lineWidth
        if selected.kind == .text {
            selected.fontSize = fontSize
            var r = selected.rect
            r.size.height = selected.fittingHeight(scale: contentScale)
            selected.setRect(r)
            if let textView {
                textView.font = NSFont.systemFont(ofSize: selected.fontSize * contentScale, weight: .medium)
                textView.textColor = selected.color
                layoutTextView()
            }
        }
        needsDisplay = true
        delegate?.canvasDidEdit(self)
    }

    /// Style values for a newly created annotation.
    private func newAnnotation(kind: Annotation.Kind, at point: CGPoint) -> Annotation {
        Annotation(kind: kind, p1: point, p2: point,
                   color: strokeColor, lineWidth: lineWidth, fontSize: fontSize)
    }

    // MARK: - Undo

    func pushUndo() {
        undoStack.append(annotations.map { $0.copy() })
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    @objc func undo(_ sender: Any?) {
        commitTextEditing()
        guard let previous = undoStack.popLast() else { NSSound.beep(); return }
        redoStack.append(annotations.map { $0.copy() })
        annotations = previous
        selected = nil
        needsDisplay = true
        delegate?.canvasDidChangeSelection(self)
        delegate?.canvasDidEdit(self)
    }

    @objc func redo(_ sender: Any?) {
        commitTextEditing()
        guard let next = redoStack.popLast() else { NSSound.beep(); return }
        undoStack.append(annotations.map { $0.copy() })
        annotations = next
        selected = nil
        needsDisplay = true
        delegate?.canvasDidChangeSelection(self)
        delegate?.canvasDidEdit(self)
    }

    func deleteSelection() {
        guard let selected else { return }
        pushUndo()
        annotations.removeAll { $0 === selected }
        self.selected = nil
        needsDisplay = true
        delegate?.canvasDidChangeSelection(self)
        delegate?.canvasDidEdit(self)
    }

    func clearAll() {
        guard !annotations.isEmpty else { return }
        commitTextEditing()
        pushUndo()
        annotations.removeAll()
        selected = nil
        needsDisplay = true
        delegate?.canvasDidChangeSelection(self)
        delegate?.canvasDidEdit(self)
    }

    // MARK: - Cursors

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .select ? .arrow : .crosshair)
    }

    // MARK: - Mouse

    private func handleIndex(at point: CGPoint, for annotation: Annotation) -> Int? {
        let slop = handleSize
        for (index, handle) in annotation.handlePoints().enumerated() {
            if abs(handle.x - point.x) <= slop && abs(handle.y - point.y) <= slop { return index }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if textView != nil {
            commitTextEditing()
            if tool == .text { return }
        }

        if event.clickCount == 2, tool == .select,
           let hit = annotations.reversed().first(where: { $0.hitTest(point, scale: contentScale) }),
           hit.kind == .text {
            select(hit)
            beginTextEditing(hit, isNew: false)
            return
        }

        switch tool {
        case .select:
            if let selected, let handle = handleIndex(at: point, for: selected) {
                pushUndo()
                dragMode = .resizing(handle: handle, startRect: selected.rect, startFont: selected.fontSize)
                return
            }
            if let hit = annotations.reversed().first(where: { $0.hitTest(point, scale: contentScale) }) {
                select(hit)
                pushUndo()
                dragMode = .moving(origin1: hit.p1, origin2: hit.p2, start: point)
            } else {
                select(nil)
                dragMode = .none
            }

        case .text:
            let annotation = newAnnotation(kind: .text, at: point)
            annotation.setRect(CGRect(x: point.x, y: point.y,
                                      width: 240 * contentScale,
                                      height: fontSize * contentScale * 1.4))
            pushUndo()
            annotations.append(annotation)
            select(annotation)
            beginTextEditing(annotation, isNew: true)
            dragMode = .none

        case .rectangle, .ellipse, .line, .arrow:
            let kind: Annotation.Kind = {
                switch tool {
                case .rectangle: return .rectangle
                case .ellipse: return .ellipse
                case .line: return .line
                default: return .arrow
                }
            }()
            let annotation = newAnnotation(kind: kind, at: point)
            pushUndo()
            annotations.append(annotation)
            dragMode = .creating(annotation)
            select(nil)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        var point = convert(event.locationInWindow, from: nil)
        let shift = event.modifierFlags.contains(.shift)

        switch dragMode {
        case .creating(let annotation):
            if shift {
                point = constrained(from: annotation.p1, to: point, kind: annotation.kind)
            }
            annotation.p2 = point

        case .moving(let origin1, let origin2, let start):
            guard let selected else { return }
            var delta = CGSize(width: point.x - start.x, height: point.y - start.y)
            if shift {
                if abs(delta.width) > abs(delta.height) { delta.height = 0 } else { delta.width = 0 }
            }
            selected.p1 = CGPoint(x: origin1.x + delta.width, y: origin1.y + delta.height)
            selected.p2 = CGPoint(x: origin2.x + delta.width, y: origin2.y + delta.height)

        case .resizing(let handle, let startRect, let startFont):
            guard let selected else { return }
            if selected.isRectLike {
                var newRect = Annotation.resized(startRect, handle: handle, to: point)
                if selected.kind == .text {
                    if Annotation.isCornerHandle(handle), startRect.height > 1 {
                        let ratio = max(newRect.height / startRect.height, 0.05)
                        selected.fontSize = max(6, startFont * ratio)
                    }
                    newRect.size.height = selected.fittingHeight(scale: contentScale)
                }
                selected.setRect(newRect)
            } else {
                var target = point
                if shift {
                    let anchor = handle == 0 ? selected.p2 : selected.p1
                    target = constrained(from: anchor, to: point, kind: selected.kind)
                }
                if handle == 0 { selected.p1 = target } else { selected.p2 = target }
            }

        case .none:
            return
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch dragMode {
        case .creating(let annotation):
            let r = annotation.rect
            let tooSmall = annotation.isRectLike
                ? (r.width < 4 || r.height < 4)
                : hypot(annotation.p2.x - annotation.p1.x, annotation.p2.y - annotation.p1.y) < 4
            if tooSmall {
                annotations.removeAll { $0 === annotation }
                _ = undoStack.popLast()
            } else {
                if annotation.isRectLike { annotation.setRect(r) }
                delegate?.canvasDidEdit(self)
            }
        case .moving, .resizing:
            delegate?.canvasDidEdit(self)
        case .none:
            break
        }
        dragMode = .none
        needsDisplay = true
    }

    private func constrained(from anchor: CGPoint, to point: CGPoint, kind: Annotation.Kind) -> CGPoint {
        let dx = point.x - anchor.x, dy = point.y - anchor.y
        switch kind {
        case .rectangle, .ellipse, .text:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: anchor.x + (dx < 0 ? -side : side),
                           y: anchor.y + (dy < 0 ? -side : side))
        case .line, .arrow:
            let angle = atan2(dy, dx)
            let step = CGFloat.pi / 4
            let snapped = (angle / step).rounded() * step
            let length = hypot(dx, dy)
            return CGPoint(x: anchor.x + cos(snapped) * length,
                           y: anchor.y + sin(snapped) * length)
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: // delete / forward delete
            deleteSelection()
        case 53: // escape
            select(nil)
        case 123, 124, 125, 126: // arrows
            guard let selected else { return }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            var delta = CGSize.zero
            switch event.keyCode {
            case 123: delta.width = -step
            case 124: delta.width = step
            case 125: delta.height = step
            default: delta.height = -step
            }
            pushUndo()
            selected.translate(by: delta)
            needsDisplay = true
            delegate?.canvasDidEdit(self)
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Text editing

    private func beginTextEditing(_ annotation: Annotation, isNew: Bool) {
        commitTextEditing()
        editingAnnotation = annotation
        editingIsNew = isNew

        let tv = NSTextView(frame: annotation.rect)
        tv.delegate = self
        tv.isRichText = false
        tv.drawsBackground = false
        tv.backgroundColor = .clear
        tv.font = NSFont.systemFont(ofSize: annotation.fontSize * contentScale, weight: .medium)
        tv.textColor = annotation.color
        tv.insertionPointColor = annotation.color
        tv.string = annotation.text
        tv.textContainerInset = NSSize(width: 2, height: 2)
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = []
        tv.allowsUndo = true

        addSubview(tv)
        textView = tv
        layoutTextView()
        window?.makeFirstResponder(tv)
        tv.setSelectedRange(NSRange(location: annotation.text.count, length: 0))
        needsDisplay = true
    }

    private func layoutTextView() {
        guard let textView, let annotation = editingAnnotation else { return }
        var frame = annotation.rect
        frame.size.width = max(frame.width, 40)
        frame.size.height = max(annotation.fittingHeight(scale: contentScale),
                                annotation.fontSize * contentScale * 1.4)
        textView.frame = frame
        textView.textContainer?.containerSize = NSSize(width: frame.width - 4,
                                                       height: .greatestFiniteMagnitude)
        annotation.setRect(frame)
    }

    func textDidChange(_ notification: Notification) {
        guard let annotation = editingAnnotation, let textView else { return }
        annotation.text = textView.string
        layoutTextView()
        needsDisplay = true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            commitTextEditing()
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    @discardableResult
    func commitTextEditing() -> Bool {
        guard let annotation = editingAnnotation, let textView else { return false }
        annotation.text = textView.string
        textView.removeFromSuperview()
        self.textView = nil
        editingAnnotation = nil

        if annotation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            annotations.removeAll { $0 === annotation }
            if editingIsNew { _ = undoStack.popLast() }
            if selected === annotation { selected = nil }
            delegate?.canvasDidChangeSelection(self)
        } else {
            var r = annotation.rect
            r.size.height = annotation.fittingHeight(scale: contentScale)
            annotation.setRect(r)
            delegate?.canvasDidEdit(self)
        }
        editingIsNew = false
        needsDisplay = true
        return true
    }

    var isEditingText: Bool { textView != nil }

    /// Used by the headless self-test to populate the canvas.
    func addForTesting(_ annotation: Annotation) {
        annotations.append(annotation)
    }

    // MARK: - Export

    func renderedImage() -> CGImage? {
        commitTextEditing()

        let width = baseImage.width
        let height = baseImage.height
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let graphics = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        render(includeSelection: false)
        NSGraphicsContext.restoreGraphicsState()

        return context.makeImage()
    }
}
