import AppKit

@objc protocol MenuActions {
    @objc optional func newCapture(_ sender: Any?)
    @objc optional func newDateShift(_ sender: Any?)
    @objc optional func saveDocument(_ sender: Any?)
    @objc optional func saveDocumentAs(_ sender: Any?)
    @objc optional func copyImage(_ sender: Any?)
    @objc optional func clearAnnotations(_ sender: Any?)
    @objc optional func selectTool(_ sender: Any?)
    @objc optional func undo(_ sender: Any?)
    @objc optional func redo(_ sender: Any?)
    @objc optional func zoomIn(_ sender: Any?)
    @objc optional func zoomOut(_ sender: Any?)
    @objc optional func zoomActual(_ sender: Any?)
}

enum MainMenuBuilder {
    static func install() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Right Click Ninja", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Right Click Ninja", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Right Click Ninja", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        add(fileMenu, "New Capture", #selector(MenuActions.newCapture(_:)), "n", [.command])
        add(fileMenu, "Date Shift…", #selector(MenuActions.newDateShift(_:)), "d", [.command, .shift])
        fileMenu.addItem(.separator())
        add(fileMenu, "Save to Desktop", #selector(MenuActions.saveDocument(_:)), "s", [.command, .shift])
        add(fileMenu, "Save As…", #selector(MenuActions.saveDocumentAs(_:)), "s", [.command])
        fileMenu.addItem(.separator())
        add(fileMenu, "Close", #selector(NSWindow.performClose(_:)), "w", [.command])
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        add(editMenu, "Undo", #selector(MenuActions.undo(_:)), "z", [.command])
        add(editMenu, "Redo", #selector(MenuActions.redo(_:)), "z", [.command, .shift])
        editMenu.addItem(.separator())
        add(editMenu, "Cut", #selector(NSText.cut(_:)), "x", [.command])
        add(editMenu, "Copy", #selector(NSText.copy(_:)), "c", [.command])
        add(editMenu, "Paste", #selector(NSText.paste(_:)), "v", [.command])
        add(editMenu, "Select All", #selector(NSText.selectAll(_:)), "a", [.command])
        editMenu.addItem(.separator())
        add(editMenu, "Copy Image to Clipboard", #selector(MenuActions.copyImage(_:)), "c", [.command, .option])
        add(editMenu, "Delete All Annotations", #selector(MenuActions.clearAnnotations(_:)), "", [])
        editItem.submenu = editMenu

        let toolsItem = NSMenuItem()
        mainMenu.addItem(toolsItem)
        let toolsMenu = NSMenu(title: "Tools")
        for (index, tool) in ToolKind.allCases.enumerated() {
            let item = NSMenuItem(title: tool.label, action: #selector(MenuActions.selectTool(_:)), keyEquivalent: "\(index + 1)")
            item.keyEquivalentModifierMask = [.command]
            item.tag = tool.rawValue
            toolsMenu.addItem(item)
        }
        toolsMenu.addItem(.separator())
        add(toolsMenu, "Zoom In", #selector(MenuActions.zoomIn(_:)), "+", [.command])
        add(toolsMenu, "Zoom Out", #selector(MenuActions.zoomOut(_:)), "-", [.command])
        add(toolsMenu, "Actual Size", #selector(MenuActions.zoomActual(_:)), "0", [.command])
        toolsItem.submenu = toolsMenu

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        add(windowMenu, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", [.command])
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private static func add(_ menu: NSMenu,
                            _ title: String,
                            _ action: Selector,
                            _ key: String,
                            _ modifiers: NSEvent.ModifierFlags) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
    }
}
