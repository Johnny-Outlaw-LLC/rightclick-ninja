import AppKit

let arguments = CommandLine.arguments

if let index = arguments.firstIndex(of: "--selftest") {
    let output = index + 1 < arguments.count ? arguments[index + 1] : "selftest.png"
    _ = NSApplication.shared
    exit(MainActor.assumeIsolated { SelfTest.run(outputPath: output) })
}

if arguments.contains("--dateshift-selftest") {
    _ = NSApplication.shared
    exit(MainActor.assumeIsolated { DateShiftSelfTest.run() })
}

if let index = arguments.firstIndex(of: "--uitest") {
    let directory = index + 1 < arguments.count ? arguments[index + 1] : "./uitest"
    let app = NSApplication.shared
    let uiDelegate = MainActor.assumeIsolated { UITestDelegate(outputDirectory: directory) }
    app.delegate = uiDelegate
    app.setActivationPolicy(.accessory)
    app.run()
    exit(0)
}

let delegate = MainActor.assumeIsolated { AppDelegate() }

let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
