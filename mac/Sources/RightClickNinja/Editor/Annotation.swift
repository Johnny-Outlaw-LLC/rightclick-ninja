import AppKit

enum ToolKind: Int, CaseIterable {
    case select, rectangle, ellipse, line, arrow, text

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        }
    }

    var label: String {
        switch self {
        case .select: return "Select"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        case .arrow: return "Arrow"
        case .text: return "Text"
        }
    }
}

/// A single drawable annotation. All geometry is in image-pixel coordinates
/// with a top-left origin (the canvas view is flipped).
final class Annotation {
    enum Kind: Int { case rectangle, ellipse, line, arrow, text }

    var kind: Kind
    var p1: CGPoint
    var p2: CGPoint
    var color: NSColor
    /// Stroke width in *points* — multiplied by the image scale when drawn.
    var lineWidth: CGFloat
    /// Font size in *points* — multiplied by the image scale when drawn.
    var fontSize: CGFloat
    var text: String

    init(kind: Kind,
         p1: CGPoint,
         p2: CGPoint,
         color: NSColor,
         lineWidth: CGFloat,
         fontSize: CGFloat = 24,
         text: String = "") {
        self.kind = kind
        self.p1 = p1
        self.p2 = p2
        self.color = color
        self.lineWidth = lineWidth
        self.fontSize = fontSize
        self.text = text
    }

    func copy() -> Annotation {
        Annotation(kind: kind, p1: p1, p2: p2, color: color,
                   lineWidth: lineWidth, fontSize: fontSize, text: text)
    }

    var isRectLike: Bool { kind == .rectangle || kind == .ellipse || kind == .text }

    var rect: CGRect {
        CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
               width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
    }

    func setRect(_ r: CGRect) {
        p1 = CGPoint(x: r.minX, y: r.minY)
        p2 = CGPoint(x: r.maxX, y: r.maxY)
    }

    func translate(by delta: CGSize) {
        p1.x += delta.width; p1.y += delta.height
        p2.x += delta.width; p2.y += delta.height
    }

    /// Bounding box including stroke width, used for redraw + hit slop.
    func bounds(scale: CGFloat) -> CGRect {
        let pad = max(lineWidth * scale, 8)
        if isRectLike { return rect.insetBy(dx: -pad, dy: -pad) }
        return CGRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y),
                      width: abs(p2.x - p1.x), height: abs(p2.y - p1.y))
            .insetBy(dx: -pad, dy: -pad)
    }

    // MARK: - Drawing

    func draw(scale: CGFloat) {
        let width = max(lineWidth * scale, 1)
        color.setStroke()
        color.setFill()

        switch kind {
        case .rectangle:
            let path = NSBezierPath(rect: rect)
            path.lineWidth = width
            path.stroke()

        case .ellipse:
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = width
            path.stroke()

        case .line:
            let path = NSBezierPath()
            path.lineWidth = width
            path.lineCapStyle = .round
            path.move(to: p1)
            path.line(to: p2)
            path.stroke()

        case .arrow:
            drawArrow(width: width)

        case .text:
            drawText(scale: scale)
        }
    }

    private func drawArrow(width: CGFloat) {
        let dx = p2.x - p1.x, dy = p2.y - p1.y
        let length = max(sqrt(dx * dx + dy * dy), 0.001)
        let headLength = min(max(width * 4.0, 12), length)
        let headWidth = headLength * 0.85
        let ux = dx / length, uy = dy / length

        // Shaft stops short of the head so the tip stays crisp.
        let shaftEnd = CGPoint(x: p2.x - ux * headLength * 0.85,
                               y: p2.y - uy * headLength * 0.85)
        let shaft = NSBezierPath()
        shaft.lineWidth = width
        shaft.lineCapStyle = .round
        shaft.move(to: p1)
        shaft.line(to: shaftEnd)
        shaft.stroke()

        let baseCenter = CGPoint(x: p2.x - ux * headLength, y: p2.y - uy * headLength)
        let px = -uy, py = ux
        let head = NSBezierPath()
        head.move(to: p2)
        head.line(to: CGPoint(x: baseCenter.x + px * headWidth / 2, y: baseCenter.y + py * headWidth / 2))
        head.line(to: CGPoint(x: baseCenter.x - px * headWidth / 2, y: baseCenter.y - py * headWidth / 2))
        head.close()
        head.fill()
    }

    func attributedText(scale: CGFloat) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: max(fontSize * scale, 4), weight: .medium),
            .foregroundColor: color,
            .paragraphStyle: style
        ])
    }

    private func drawText(scale: CGFloat) {
        guard !text.isEmpty else { return }
        attributedText(scale: scale).draw(with: rect.insetBy(dx: 2, dy: 2),
                                          options: [.usesLineFragmentOrigin])
    }

    /// Height needed to render the current text at the current width.
    func fittingHeight(scale: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return fontSize * scale * 1.4 }
        let bounding = attributedText(scale: scale).boundingRect(
            with: CGSize(width: max(rect.width - 4, 10), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin])
        return ceil(bounding.height) + 8
    }

    // MARK: - Hit testing

    func hitTest(_ point: CGPoint, scale: CGFloat) -> Bool {
        let slop = max(lineWidth * scale, 10)
        switch kind {
        case .rectangle:
            let outer = rect.insetBy(dx: -slop, dy: -slop)
            let inner = rect.insetBy(dx: slop, dy: slop)
            return outer.contains(point) && !inner.contains(point)
        case .ellipse:
            let path = NSBezierPath(ovalIn: rect)
            let thick = NSBezierPath(ovalIn: rect.insetBy(dx: -slop, dy: -slop))
            let thin = NSBezierPath(ovalIn: rect.insetBy(dx: slop, dy: slop))
            _ = path
            return thick.contains(point) && !thin.contains(point)
        case .line, .arrow:
            return distanceToSegment(point) <= slop
        case .text:
            return rect.insetBy(dx: -4, dy: -4).contains(point)
        }
    }

    private func distanceToSegment(_ p: CGPoint) -> CGFloat {
        let dx = p2.x - p1.x, dy = p2.y - p1.y
        let lengthSquared = dx * dx + dy * dy
        if lengthSquared < 0.0001 { return hypot(p.x - p1.x, p.y - p1.y) }
        var t = ((p.x - p1.x) * dx + (p.y - p1.y) * dy) / lengthSquared
        t = max(0, min(1, t))
        let proj = CGPoint(x: p1.x + t * dx, y: p1.y + t * dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }

    // MARK: - Handles

    /// Handle positions: rect-like shapes get 8, lines/arrows get their 2 endpoints.
    func handlePoints() -> [CGPoint] {
        if isRectLike {
            let r = rect
            return [
                CGPoint(x: r.minX, y: r.minY),                 // 0 top-left
                CGPoint(x: r.midX, y: r.minY),                 // 1 top
                CGPoint(x: r.maxX, y: r.minY),                 // 2 top-right
                CGPoint(x: r.maxX, y: r.midY),                 // 3 right
                CGPoint(x: r.maxX, y: r.maxY),                 // 4 bottom-right
                CGPoint(x: r.midX, y: r.maxY),                 // 5 bottom
                CGPoint(x: r.minX, y: r.maxY),                 // 6 bottom-left
                CGPoint(x: r.minX, y: r.midY)                  // 7 left
            ]
        }
        return [p1, p2]
    }

    static func resized(_ r: CGRect, handle: Int, to p: CGPoint) -> CGRect {
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch handle {
        case 0: minX = p.x; minY = p.y
        case 1: minY = p.y
        case 2: maxX = p.x; minY = p.y
        case 3: maxX = p.x
        case 4: maxX = p.x; maxY = p.y
        case 5: maxY = p.y
        case 6: minX = p.x; maxY = p.y
        case 7: minX = p.x
        default: break
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY),
                      width: abs(maxX - minX), height: abs(maxY - minY))
    }

    static func isCornerHandle(_ index: Int) -> Bool {
        index == 0 || index == 2 || index == 4 || index == 6
    }
}
