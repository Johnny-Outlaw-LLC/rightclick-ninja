import AppKit

/// Headless checks: renders every annotation type into a PNG and verifies the
/// geometry helpers. Run with `RightClickNinja --selftest <out.png>`.
enum SelfTest {
    static func run(outputPath: String) -> Int32 {
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "  ok  " : "  FAIL") \(label)")
            if !condition { failures += 1 }
        }

        let scale: CGFloat = 2
        guard let base = checkerboard(width: 1200, height: 800) else {
            print("  FAIL could not build base image")
            return 1
        }

        let canvas = CanvasView(image: base, scale: scale)
        check(canvas.isFlipped, "canvas uses a flipped (top-left origin) coordinate space")
        check(canvas.frame.width == 1200 && canvas.frame.height == 800, "canvas bounds match image pixels")

        let annotations: [Annotation] = [
            Annotation(kind: .rectangle, p1: CGPoint(x: 60, y: 60), p2: CGPoint(x: 400, y: 260),
                       color: .systemRed, lineWidth: 3),
            Annotation(kind: .ellipse, p1: CGPoint(x: 460, y: 60), p2: CGPoint(x: 760, y: 260),
                       color: .systemBlue, lineWidth: 5),
            Annotation(kind: .line, p1: CGPoint(x: 60, y: 320), p2: CGPoint(x: 400, y: 470),
                       color: .systemGreen, lineWidth: 8),
            Annotation(kind: .arrow, p1: CGPoint(x: 460, y: 470), p2: CGPoint(x: 780, y: 320),
                       color: .systemOrange, lineWidth: 6),
            Annotation(kind: .text, p1: CGPoint(x: 60, y: 540), p2: CGPoint(x: 800, y: 640),
                       color: .systemPurple, lineWidth: 3, fontSize: 32,
                       text: "Text annotation — resize me")
        ]
        for annotation in annotations { canvas.addForTesting(annotation) }

        let rect = annotations[0]
        check(rect.hitTest(CGPoint(x: 60, y: 160), scale: scale), "rectangle edge hit-tests true")
        check(!rect.hitTest(CGPoint(x: 230, y: 160), scale: scale), "rectangle interior hit-tests false")

        let line = annotations[2]
        check(line.hitTest(CGPoint(x: 230, y: 395), scale: scale), "line midpoint hit-tests true")
        check(!line.hitTest(CGPoint(x: 230, y: 300), scale: scale), "point away from line hit-tests false")

        let resized = Annotation.resized(CGRect(x: 10, y: 10, width: 100, height: 100),
                                         handle: 4, to: CGPoint(x: 210, y: 160))
        check(resized == CGRect(x: 10, y: 10, width: 200, height: 150), "bottom-right handle resize")
        let flipped = Annotation.resized(CGRect(x: 10, y: 10, width: 100, height: 100),
                                         handle: 0, to: CGPoint(x: 210, y: 160))
        check(flipped == CGRect(x: 110, y: 110, width: 100, height: 50), "dragging a handle past its opposite normalizes")

        let text = annotations[4]
        check(text.fittingHeight(scale: scale) > text.fontSize * scale, "text fitting height accounts for the font")

        canvas.pushUndo()
        canvas.addForTesting(Annotation(kind: .rectangle, p1: .zero, p2: CGPoint(x: 10, y: 10),
                                        color: .black, lineWidth: 1))
        let countAfterAdd = canvas.annotations.count
        canvas.undo(nil)
        check(canvas.annotations.count == countAfterAdd - 1, "undo removes the last annotation")
        canvas.redo(nil)
        check(canvas.annotations.count == countAfterAdd, "redo restores it")
        canvas.undo(nil)

        guard let rendered = canvas.renderedImage() else {
            print("  FAIL renderedImage() returned nil")
            return 1
        }
        check(rendered.width == base.width && rendered.height == base.height,
              "export keeps full pixel resolution (\(rendered.width)×\(rendered.height))")

        if let data = ImageOutput.data(from: rendered, type: .png, scale: scale) {
            do {
                try data.write(to: URL(fileURLWithPath: outputPath))
                print("  ok   wrote \(outputPath) (\(data.count) bytes)")
            } catch {
                print("  FAIL could not write \(outputPath): \(error)")
                failures += 1
            }
        } else {
            print("  FAIL PNG encoding returned nil")
            failures += 1
        }

        failures += orientationCheck()

        print(failures == 0 ? "\nAll self-tests passed." : "\n\(failures) self-test(s) failed.")
        return failures == 0 ? 0 : 1
    }

    private static func orientationCheck() -> Int {
        var failures = 0
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "  ok  " : "  FAIL") \(label)")
            if !condition { failures += 1 }
        }

        let width = 64, height = 48
        guard let marked = orientationMarker(width: width, height: height) else {
            print("  FAIL could not build orientation marker image")
            return 1
        }
        let canvas = CanvasView(image: marked, scale: 1)
        guard let exported = canvas.renderedImage() else {
            print("  FAIL orientation export returned nil")
            return 1
        }

        let topLeft = sampleRGBA(exported, x: 4, y: 4)
        let bottomRight = sampleRGBA(exported, x: width - 5, y: height - 5)
        check(isReddish(topLeft), "exported top-left stays red (not vertically flipped)")
        check(isBlueish(bottomRight), "exported bottom-right stays blue (not vertically flipped)")
        return failures
    }

    private static func orientationMarker(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor.systemRed.cgColor)
        context.fill(CGRect(x: 0, y: height - 16, width: 16, height: 16))
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: width - 16, y: 0, width: 16, height: 16))
        return context.makeImage()
    }

    private static func sampleRGBA(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
            return (0, 0, 0, 0)
        }
        return (UInt8(clamping: Int(color.redComponent * 255)),
                UInt8(clamping: Int(color.greenComponent * 255)),
                UInt8(clamping: Int(color.blueComponent * 255)),
                UInt8(clamping: Int(color.alphaComponent * 255)))
    }

    private static func isReddish(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
        p.r > 180 && p.g < 120 && p.b < 120
    }

    private static func isBlueish(_ p: (r: UInt8, g: UInt8, b: UInt8, a: UInt8)) -> Bool {
        p.b > 180 && p.r < 120 && p.g < 160
    }

    private static func checkerboard(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(NSColor(white: 0.93, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(NSColor(white: 0.82, alpha: 1).cgColor)
        let tile = 40
        for row in 0..<(height / tile + 1) {
            for column in 0..<(width / tile + 1) where (row + column) % 2 == 0 {
                context.fill(CGRect(x: column * tile, y: row * tile, width: tile, height: tile))
            }
        }
        return context.makeImage()
    }
}
