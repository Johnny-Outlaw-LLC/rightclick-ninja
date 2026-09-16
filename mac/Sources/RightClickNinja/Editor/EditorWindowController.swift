import AppKit

/// Keeps the document centered when it is smaller than the scroll view.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let documentView else { return rect }
        let docFrame = documentView.frame
        if rect.width > docFrame.width {
            rect.origin.x = (docFrame.width - rect.width) / 2
        }
        if rect.height > docFrame.height {
            rect.origin.y = (docFrame.height - rect.height) / 2
        }
        return rect
    }
}

final class EditorWindowController: NSWindowController, NSWindowDelegate, CanvasViewDelegate {

    private static var openEditors: [EditorWindowController] = []
    static var hasOpenEditors: Bool { !openEditors.isEmpty }

    private let canvas: CanvasView
    private let scrollView = NSScrollView()
    private var toolSegments: NSSegmentedControl!
    private var colorWell: NSColorWell!
    private var widthPopUp: NSPopUpButton!
    private var fontPopUp: NSPopUpButton!
    private var deleteButton: NSButton!
    private var undoButton: NSButton!
    private var suggestedName: String?

    /// Exposed for the offscreen UI test.
    var canvasForUITest: CanvasView { canvas }

    private static let widths: [CGFloat] = [1, 2, 3, 5, 8, 12, 18]
    private static let fontSizes: [CGFloat] = [12, 14, 18, 24, 32, 48, 64, 96]
    private static let palette: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemBlue, .systemPurple, .black, .white
    ]

    // MARK: - Opening

    @discardableResult
    static func open(image: CGImage, scale: CGFloat, suggestedName: String? = nil) -> EditorWindowController {
        let controller = EditorWindowController(image: image, scale: scale, suggestedName: suggestedName)
        openEditors.append(controller)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        return controller
    }

    private init(image: CGImage, scale: CGFloat, suggestedName: String?) {
        self.canvas = CanvasView(image: image, scale: scale)
        self.suggestedName = suggestedName

        let displayWidth = CGFloat(image.width) / max(scale, 1)
        let displayHeight = CGFloat(image.height) / max(scale, 1)
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxWidth = visible.width * 0.85
        let maxHeight = visible.height * 0.85 - EditorWindowController.toolbarHeight
        let fit = min(1, min(maxWidth / displayWidth, maxHeight / displayHeight))

        let contentSize = NSSize(width: max(displayWidth * fit, 620),
                                 height: displayHeight * fit + EditorWindowController.toolbarHeight)

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.title = "Right Click Ninja Editor"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        window.delegate = self
        canvas.delegate = self
        canvas.strokeColor = .systemRed
        canvas.lineWidth = 3
        canvas.fontSize = 24

        buildUI(contentSize: contentSize)
        // Show the capture at its original on-screen size (or smaller if it
        // wouldn't fit): canvas units are pixels, so 1/scale == 100%.
        scrollView.magnification = (1 / max(scale, 1)) * fit
        window.makeFirstResponder(canvas)
        updateControls()
    }

    required init?(coder: NSCoder) { fatalError() }

    private static let toolbarHeight: CGFloat = 48

    // MARK: - UI

    private func buildUI(contentSize: NSSize) {
        guard let window else { return }

        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        let bar = NSVisualEffectView()
        bar.material = .titlebar
        bar.blendingMode = .withinWindow
        bar.state = .followsWindowActiveState
        bar.translatesAutoresizingMaskIntoConstraints = false

        // Tools
        toolSegments = NSSegmentedControl(images: ToolKind.allCases.map {
            NSImage(systemSymbolName: $0.symbolName, accessibilityDescription: $0.label)
                ?? NSImage(size: NSSize(width: 12, height: 12))
        }, trackingMode: .selectOne, target: self, action: #selector(toolChanged))
        for (index, tool) in ToolKind.allCases.enumerated() {
            toolSegments.setToolTip("\(tool.label)  (\(index + 1))", forSegment: index)
        }
        toolSegments.selectedSegment = ToolKind.rectangle.rawValue

        // Color
        colorWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 40, height: 24))
        colorWell.color = .systemRed
        colorWell.target = self
        colorWell.action = #selector(colorChanged)
        colorWell.toolTip = "Stroke / text color"

        let swatches = NSStackView()
        swatches.orientation = .horizontal
        swatches.spacing = 3
        for color in EditorWindowController.palette {
            let button = NSButton(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
            button.title = ""
            button.bezelStyle = .shadowlessSquare
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = color.cgColor
            button.layer?.cornerRadius = 4
            button.layer?.borderWidth = 1
            button.layer?.borderColor = NSColor.separatorColor.cgColor
            button.target = self
            button.action = #selector(swatchClicked(_:))
            button.tag = EditorWindowController.palette.firstIndex(of: color) ?? 0
            button.widthAnchor.constraint(equalToConstant: 18).isActive = true
            button.heightAnchor.constraint(equalToConstant: 18).isActive = true
            swatches.addArrangedSubview(button)
        }

        // Line width
        widthPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        widthPopUp.addItems(withTitles: EditorWindowController.widths.map { "\(Int($0)) pt" })
        widthPopUp.selectItem(at: EditorWindowController.widths.firstIndex(of: 3) ?? 2)
        widthPopUp.target = self
        widthPopUp.action = #selector(widthChanged)
        widthPopUp.toolTip = "Line width"

        // Font size
        fontPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        fontPopUp.addItems(withTitles: EditorWindowController.fontSizes.map { "\(Int($0)) pt" })
        fontPopUp.selectItem(at: EditorWindowController.fontSizes.firstIndex(of: 24) ?? 3)
        fontPopUp.target = self
        fontPopUp.action = #selector(fontSizeChanged)
        fontPopUp.toolTip = "Text size"

        undoButton = barButton("arrow.uturn.backward", "Undo (⌘Z)", #selector(undoAction))
        deleteButton = barButton("trash", "Delete selected (⌫)", #selector(deleteAction))
        let copyButton = barButton("doc.on.clipboard", "Copy image to clipboard (⌥⌘C)", #selector(copyImage(_:)))
        let saveButton = barButton("square.and.arrow.down", "Save as… (⌘S)", #selector(saveDocumentAs(_:)))

        colorWell.translatesAutoresizingMaskIntoConstraints = false
        colorWell.widthAnchor.constraint(equalToConstant: 42).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        let stack = NSStackView(views: [
            toolSegments, separator(),
            colorWell, swatches, separator(),
            widthPopUp, fontPopUp, separator(),
            undoButton, deleteButton,
            spacer,
            copyButton, saveButton
        ])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        bar.addSubview(stack)

        // Canvas
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.1
        scrollView.maxMagnification = 8
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = NSColor(white: 0.16, alpha: 1)
        let clip = CenteringClipView()
        clip.drawsBackground = false
        scrollView.contentView = clip
        scrollView.documentView = canvas

        container.addSubview(bar)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.heightAnchor.constraint(equalToConstant: EditorWindowController.toolbarHeight),

            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: bar.bottomAnchor),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        window.contentView = container
    }

    private func barButton(_ symbol: String, _ tooltip: String, _ action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
                              ?? NSImage(size: NSSize(width: 14, height: 14)),
                              target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.toolTip = tooltip
        return button
    }

    private func separator() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return view
    }

    // MARK: - Actions

    @objc private func toolChanged() {
        guard let tool = ToolKind(rawValue: toolSegments.selectedSegment) else { return }
        canvas.tool = tool
        updateControls()
    }

    @objc private func colorChanged() {
        canvas.strokeColor = colorWell.color
    }

    @objc private func swatchClicked(_ sender: NSButton) {
        let color = EditorWindowController.palette[sender.tag]
        colorWell.color = color
        canvas.strokeColor = color
    }

    @objc private func widthChanged() {
        canvas.lineWidth = EditorWindowController.widths[widthPopUp.indexOfSelectedItem]
    }

    @objc private func fontSizeChanged() {
        canvas.fontSize = EditorWindowController.fontSizes[fontPopUp.indexOfSelectedItem]
    }

    @objc private func undoAction() { canvas.undo(nil) }
    @objc private func deleteAction() { canvas.deleteSelection() }

    @objc func undo(_ sender: Any?) { canvas.undo(sender) }
    @objc func redo(_ sender: Any?) { canvas.redo(sender) }

    @objc func selectTool(_ sender: NSMenuItem) {
        guard let tool = ToolKind(rawValue: sender.tag) else { return }
        toolSegments.selectedSegment = tool.rawValue
        toolChanged()
    }

    @objc func copyImage(_ sender: Any?) {
        guard let image = canvas.renderedImage() else { NSSound.beep(); return }
        ImageOutput.copyToClipboard(image, scale: canvas.contentScale)
        HUD.show("Copied to clipboard", near: hudPoint())
    }

    @objc func saveDocument(_ sender: Any?) {
        guard let image = canvas.renderedImage() else { NSSound.beep(); return }
        if let url = ImageOutput.saveToDesktop(image, scale: canvas.contentScale, name: suggestedName) {
            HUD.show("Saved \(url.lastPathComponent)", near: hudPoint())
        }
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        guard let image = canvas.renderedImage() else { NSSound.beep(); return }
        if let url = ImageOutput.saveAs(image, scale: canvas.contentScale,
                                        suggestedName: suggestedName, window: window) {
            suggestedName = url.deletingPathExtension().lastPathComponent
            window?.title = "Right Click Ninja Editor — \(url.lastPathComponent)"
            HUD.show("Saved \(url.lastPathComponent)", near: hudPoint())
        }
    }

    @objc func clearAnnotations(_ sender: Any?) { canvas.clearAll() }

    @objc func zoomIn(_ sender: Any?) { scrollView.magnification *= 1.25 }
    @objc func zoomOut(_ sender: Any?) { scrollView.magnification /= 1.25 }
    @objc func zoomActual(_ sender: Any?) { scrollView.magnification = 1 / canvas.contentScale }

    private func hudPoint() -> CGPoint {
        guard let frame = window?.frame else { return NSEvent.mouseLocation }
        return CGPoint(x: frame.midX, y: frame.minY + 60)
    }

    // MARK: - Canvas delegate

    func canvasDidChangeSelection(_ canvas: CanvasView) { updateControls() }
    func canvasDidEdit(_ canvas: CanvasView) { updateControls() }

    private func updateControls() {
        deleteButton.isEnabled = canvas.selected != nil
        undoButton.isEnabled = canvas.canUndo
        fontPopUp.isEnabled = canvas.tool == .text || canvas.selected?.kind == .text
        widthPopUp.isEnabled = canvas.tool != .text
    }

    // MARK: - Key handling

    override func keyDown(with event: NSEvent) {
        // Number keys 1–6 pick a tool when not typing.
        if !canvas.isEditingText, let characters = event.charactersIgnoringModifiers,
           let digit = Int(characters), (1...ToolKind.allCases.count).contains(digit),
           !event.modifierFlags.contains(.command) {
            toolSegments.selectedSegment = digit - 1
            toolChanged()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Window delegate

    func windowWillClose(_ notification: Notification) {
        canvas.commitTextEditing()
        EditorWindowController.openEditors.removeAll { $0 === self }
        AppActivation.considerAccessory()
    }
}
