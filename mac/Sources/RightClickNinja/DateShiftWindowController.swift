import AppKit

@MainActor
final class DateShiftWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    static let shared = DateShiftWindowController()

    private var files: [String] = []
    private var snapshots: [FileDateSnapshot] = []
    private var offset = DateShiftOffset()
    private var targets = DateShiftTargets()

    private let table = NSTableView()
    private let countLabel = NSTextField(labelWithString: "0 files — drop files here")
    private let statusLabel = NSTextField(wrappingLabelWithString: "Finder Date for photos/video is often embedded Date taken, not Created. Check that box.")
    private let daysField = NSTextField()
    private let hoursField = NSTextField()
    private let minutesField = NSTextField()
    private let createdBox = NSButton(checkboxWithTitle: "Date created", target: nil, action: nil)
    private let modifiedBox = NSButton(checkboxWithTitle: "Date modified", target: nil, action: nil)
    private let accessedBox = NSButton(checkboxWithTitle: "Date accessed", target: nil, action: nil)
    private let embeddedBox = NSButton(checkboxWithTitle: "Embedded media dates (Finder Date / Date taken)", target: nil, action: nil)

    var isVisible: Bool { window?.isVisible == true }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Right Click Ninja — Date Shift"
        window.minSize = NSSize(width: 800, height: 480)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        buildUI()
        registerDrag()
    }

    required init?(coder: NSCoder) { fatalError() }

    func showWindow() {
        AppActivation.becomeRegular()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func importPaths(_ paths: [String]) {
        let collected = DateShiftEngine.collect(paths: paths)
        var added = 0
        for path in collected where !files.contains(path) {
            files.append(path)
            added += 1
        }
        refresh()
        if added > 0 {
            statusLabel.stringValue = "Added \(added). Live preview updates as you change the offset."
        }
    }

    func windowWillClose(_ notification: Notification) {
        AppActivation.considerAccessory()
    }

    // MARK: - UI

    private func buildUI() {
        guard let window else { return }
        let root = DateShiftDropView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let selectButton = NSButton(title: "Select files…", target: self, action: #selector(pickFiles))
        selectButton.bezelStyle = .rounded
        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearFiles))
        clearButton.bezelStyle = .rounded

        countLabel.font = .systemFont(ofSize: 13)
        countLabel.textColor = .secondaryLabelColor

        let header = NSStackView(views: [selectButton, clearButton, countLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        table.style = .fullWidth
        table.headerView = NSTableHeaderView()
        table.usesAlternatingRowBackgroundColors = true
        table.allowsColumnReordering = false
        table.allowsMultipleSelection = true
        table.rowHeight = 22
        table.dataSource = self
        table.delegate = self
        addColumn("File", "file", 180)
        addColumn("Finder Date", "finder", 170)
        addColumn("Finder (new)", "finderNew", 170)
        addColumn("Created", "created", 120)
        addColumn("Created (new)", "createdNew", 120)
        addColumn("Modified", "modified", 120)
        addColumn("Modified (new)", "modifiedNew", 120)

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.registerForDraggedTypes([.fileURL])

        let offsetBox = NSBox()
        offsetBox.title = "Offset (negative = earlier)"
        offsetBox.translatesAutoresizingMaskIntoConstraints = false
        let offsetStack = NSStackView(views: [
            labeledField("Days", daysField),
            labeledField("Hours", hoursField),
            labeledField("Mins", minutesField)
        ])
        offsetStack.orientation = .horizontal
        offsetStack.spacing = 16
        offsetStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        offsetBox.contentView = offsetStack

        createdBox.state = .on
        modifiedBox.state = .on
        accessedBox.state = .off
        embeddedBox.state = .on
        for box in [createdBox, modifiedBox, accessedBox, embeddedBox] {
            box.target = self
            box.action = #selector(controlsChanged)
        }

        let stampBox = NSBox()
        stampBox.title = "Change"
        stampBox.translatesAutoresizingMaskIntoConstraints = false
        let stampGrid = NSGridView(views: [
            [createdBox, accessedBox],
            [modifiedBox, embeddedBox]
        ])
        stampGrid.rowSpacing = 4
        stampGrid.columnSpacing = 16
        stampGrid.translatesAutoresizingMaskIntoConstraints = false
        stampBox.contentView = stampGrid

        let apply = NSButton(title: "Apply offset", target: self, action: #selector(applyOffset))
        apply.bezelStyle = .rounded
        apply.contentTintColor = .white
        apply.bezelColor = NSColor(calibratedRed: 1, green: 107 / 255, blue: 53 / 255, alpha: 1)
        apply.keyEquivalent = "\r"

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2

        let footer = NSStackView(views: [apply, statusLabel])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12
        footer.translatesAutoresizingMaskIntoConstraints = false

        let boxes = NSStackView(views: [offsetBox, stampBox])
        boxes.orientation = .horizontal
        boxes.distribution = .fillEqually
        boxes.spacing = 12
        boxes.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(header)
        root.addSubview(scroll)
        root.addSubview(boxes)
        root.addSubview(footer)
        window.contentView = root

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -16),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),

            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            scroll.bottomAnchor.constraint(equalTo: boxes.topAnchor, constant: -12),

            boxes.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            boxes.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            boxes.heightAnchor.constraint(equalToConstant: 88),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            footer.topAnchor.constraint(equalTo: boxes.bottomAnchor, constant: 12),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])

        configureNumeric(daysField)
        configureNumeric(hoursField)
        configureNumeric(minutesField)
    }

    private func addColumn(_ title: String, _ id: String, _ width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        column.minWidth = 80
        table.addTableColumn(column)
    }

    private func labeledField(_ title: String, _ field: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        let stack = NSStackView(views: [label, field])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 70).isActive = true
        return stack
    }

    private func configureNumeric(_ field: NSTextField) {
        field.stringValue = "0"
        field.alignment = .right
        field.delegate = self
        field.formatter = integerFormatter()
        field.target = self
        field.action = #selector(controlsChanged)
    }

    private func integerFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: -99999)
        formatter.maximum = NSNumber(value: 99999)
        return formatter
    }

    private func registerDrag() {
        window?.registerForDraggedTypes([.fileURL])
        table.registerForDraggedTypes([.fileURL])
    }

    // MARK: - Actions

    @objc private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = "Select files to offset"
        AppActivation.becomeRegular()
        guard panel.runModal() == .OK else { return }
        importPaths(panel.urls.map(\.path))
    }

    @objc private func clearFiles() {
        files.removeAll()
        refresh()
        statusLabel.stringValue = "Cleared."
    }

    @objc private func controlsChanged() {
        offset.days = daysField.integerValue
        offset.hours = hoursField.integerValue
        offset.minutes = minutesField.integerValue
        targets.created = createdBox.state == .on
        targets.modified = modifiedBox.state == .on
        targets.accessed = accessedBox.state == .on
        targets.embedded = embeddedBox.state == .on
        table.reloadData()
        updateStatus()
    }

    func controlTextDidChange(_ obj: Notification) {
        controlsChanged()
    }

    @objc private func applyOffset() {
        controlsChanged()
        if files.isEmpty {
            present("Select or drop files first.")
            return
        }
        if targets.noneSelected {
            present("Pick at least one timestamp to change.")
            return
        }
        if offset.isZero {
            present("Offset is zero — nothing to do.")
            return
        }
        if targets.embedded && DateShiftEngine.resolvedExiftoolPath() == nil {
            present("Embedded media dates need ExifTool inside the app bundle. Reinstall Right Click Ninja, or uncheck that box to shift Finder timestamps only.")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Apply offset"
        var info = "Shift \(files.count) file(s) by \(offset.display)?"
        if targets.embedded {
            info += "\n\nEmbedded Date taken / Media created will also shift (this is what Finder Date shows for camera photos and video)."
        }
        alert.informativeText = info
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let result = try DateShiftEngine.apply(
                paths: files,
                offset: offset,
                targets: targets,
                exiftoolPath: DateShiftEngine.resolvedExiftoolPath()
            )
            refresh()
            statusLabel.stringValue = "Done: \(result.updated) updated, \(result.failed) failed. Refresh Finder if Date looks stale."
            if let warning = result.exifWarning {
                present(warning)
            } else if result.failed > 0 {
                present("\(result.updated) updated, \(result.failed) failed (permissions or locked files).")
            }
        } catch {
            present(error.localizedDescription)
        }
    }

    private func present(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Right Click Ninja"
        alert.informativeText = message
        alert.runModal()
    }

    private func refresh() {
        snapshots = files.compactMap { path in
            try? DateShiftEngine.snapshot(path: path)
        }
        let lost = files.count - snapshots.count
        table.reloadData()
        let noun = files.count == 1 ? "file" : "files"
        countLabel.stringValue = "\(files.count) \(noun) — drop more here"
        if lost > 0 {
            statusLabel.stringValue = "Could not read \(lost) file(s)."
        } else {
            updateStatus()
        }
    }

    private func updateStatus() {
        guard !files.isEmpty else { return }
        statusLabel.stringValue = "\(files.count) files — live preview \(offset.display) → \(targets.summary)"
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { snapshots.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue, snapshots.indices.contains(row) else { return nil }
        let snap = snapshots[row]
        let text = cellText(id: id, snap: snap)
        let view = NSTableCellView()
        let field = NSTextField(labelWithString: text)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.lineBreakMode = .byTruncatingMiddle
        field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        view.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }

    private func cellText(id: String, snap: FileDateSnapshot) -> String {
        switch id {
        case "file": return snap.name
        case "finder": return snap.embedded.display
        case "finderNew":
            guard targets.embedded else { return "" }
            guard let value = snap.embedded.value else { return "(no date)" }
            return "\(DateShiftEngine.format(DateShiftEngine.preview(value, offset: offset))) (\(snap.embedded.kind))"
        case "created": return DateShiftEngine.format(snap.created)
        case "createdNew":
            return targets.created ? DateShiftEngine.format(DateShiftEngine.preview(snap.created, offset: offset)) : ""
        case "modified": return DateShiftEngine.format(snap.modified)
        case "modifiedNew":
            return targets.modified ? DateShiftEngine.format(DateShiftEngine.preview(snap.modified, offset: offset)) : ""
        default: return ""
        }
    }
}

@MainActor
final class DateShiftDropView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        DateShiftWindowController.shared.importPaths(urls.map(\.path))
        return !urls.isEmpty
    }
}

extension DateShiftWindowController {
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        tableView.setDropRow(-1, dropOperation: .on)
        return .copy
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        importPaths(urls.map(\.path))
        return !urls.isEmpty
    }
}
