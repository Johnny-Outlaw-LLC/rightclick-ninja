import AppKit

/// Renders the editor window and the selection overlay offscreen and writes
/// them to PNGs. Lets the UI be inspected without Screen Recording permission.
/// Run with `RightClickNinja --uitest <output-directory>`.
@MainActor
final class UITestDelegate: NSObject, NSApplicationDelegate {
    private let outputDirectory: String

    init(outputDirectory: String) {
        self.outputDirectory = outputDirectory
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenuBuilder.install()
        try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

        renderEditor()
        renderOverlay()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
    }

    // MARK: - Editor

    private func renderEditor() {
        guard let base = SampleImage.make(width: 1600, height: 1000) else { return }
        let controller = EditorWindowController.open(image: base, scale: 2, suggestedName: "sample")
        guard let window = controller.window, let content = window.contentView else { return }

        controller.populateForUITest()

        window.layoutIfNeeded()
        content.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        window.layoutIfNeeded()

        write(view: content, to: "editor.png")
        window.orderOut(nil)
    }

    // MARK: - Overlay

    private func renderOverlay() {
        guard let screen = NSScreen.main,
              let base = SampleImage.make(width: Int(screen.frame.width * screen.backingScaleFactor),
                                          height: Int(screen.frame.height * screen.backingScaleFactor)) else { return }
        let shot = DisplayShot(displayID: screen.displayID,
                               image: base,
                               frame: CGRect(origin: .zero, size: screen.frame.size),
                               scale: screen.backingScaleFactor,
                               screen: screen)

        let idle = OverlayView(shot: shot)
        idle.previewState(selection: nil, mouse: CGPoint(x: screen.frame.width * 0.42,
                                                         y: screen.frame.height * 0.55))
        write(view: idle, to: "overlay-idle.png")

        let dragging = OverlayView(shot: shot)
        let selection = CGRect(x: screen.frame.width * 0.22,
                               y: screen.frame.height * 0.28,
                               width: screen.frame.width * 0.44,
                               height: screen.frame.height * 0.38)
        dragging.previewState(selection: selection, mouse: CGPoint(x: selection.maxX, y: selection.maxY))
        write(view: dragging, to: "overlay-selecting.png")
    }

    // MARK: - Helpers

    private func write(view: NSView, to name: String) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("  FAIL could not create a bitmap for \(name)")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            print("  FAIL could not encode \(name)")
            return
        }
        let path = "\(outputDirectory)/\(name)"
        do {
            try data.write(to: URL(fileURLWithPath: path))
            print("  ok   wrote \(path) (\(Int(view.bounds.width))×\(Int(view.bounds.height)))")
        } catch {
            print("  FAIL writing \(path): \(error)")
        }
    }
}

enum SampleImage {
    /// A pretend "desktop" so captures have something recognizable in them.
    static func make(width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics

        let full = NSRect(x: 0, y: 0, width: width, height: height)
        NSGradient(colors: [NSColor(calibratedRed: 0.11, green: 0.16, blue: 0.28, alpha: 1),
                            NSColor(calibratedRed: 0.30, green: 0.24, blue: 0.42, alpha: 1)])?
            .draw(in: full, angle: -60)

        // A few window-ish rectangles so region selection has visible content.
        let cards: [(NSRect, NSColor)] = [
            (NSRect(x: full.width * 0.08, y: full.height * 0.45, width: full.width * 0.40, height: full.height * 0.40),
             NSColor(calibratedWhite: 0.97, alpha: 0.95)),
            (NSRect(x: full.width * 0.52, y: full.height * 0.30, width: full.width * 0.38, height: full.height * 0.45),
             NSColor(calibratedWhite: 0.15, alpha: 0.95)),
            (NSRect(x: full.width * 0.20, y: full.height * 0.10, width: full.width * 0.45, height: full.height * 0.25),
             NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.85, alpha: 0.95))
        ]
        for (rect, color) in cards {
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
        }

        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}

extension EditorWindowController {
    /// Adds representative annotations (and selects one) for the UI test.
    func populateForUITest() {
        let samples: [Annotation] = [
            Annotation(kind: .rectangle, p1: CGPoint(x: 140, y: 120), p2: CGPoint(x: 640, y: 420),
                       color: .systemRed, lineWidth: 3),
            Annotation(kind: .ellipse, p1: CGPoint(x: 760, y: 140), p2: CGPoint(x: 1180, y: 420),
                       color: .systemBlue, lineWidth: 5),
            Annotation(kind: .arrow, p1: CGPoint(x: 300, y: 780), p2: CGPoint(x: 720, y: 520),
                       color: .systemOrange, lineWidth: 6),
            Annotation(kind: .text, p1: CGPoint(x: 780, y: 640), p2: CGPoint(x: 1480, y: 730),
                       color: .systemYellow, lineWidth: 3, fontSize: 28, text: "Annotated with Right Click Ninja")
        ]
        for annotation in samples { canvasForUITest.addForTesting(annotation) }
        canvasForUITest.select(samples[0])
    }
}
