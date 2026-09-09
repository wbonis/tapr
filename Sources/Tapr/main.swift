import AppKit
import SwiftUI
import TaprCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = TaprModel()
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var armItem: NSMenuItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Tapr", action: #selector(showWindow), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Tapr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"),
                                    ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"),
                                    ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        editItem.submenu = editMenu; mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Tapr — Tap your MacBook"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.center()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: "Tapr")
        let menu = NSMenu(); menu.delegate = self; menu.autoenablesItems = false
        let settings = menu.addItem(withTitle: "Open Tapr…", action: #selector(showWindow), keyEquivalent: "")
        settings.target = self
        armItem = menu.addItem(withTitle: "Enable actions", action: #selector(toggleArmed), keyEquivalent: "")
        armItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Tapr", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        showWindow()
        model.start()
        if let index = CommandLine.arguments.firstIndex(of: "--smoke-test") {
            // Optional third argument: seconds to wait before capturing (default 3).
            let delay = CommandLine.arguments.count > index + 2 ? Double(CommandLine.arguments[index + 2]) ?? 3 : 3
            DispatchQueue.main.asyncAfter(deadline: .now() + min(max(delay, 1), 60)) { [self] in
                if CommandLine.arguments.count > index + 1, let view = window.contentView {
                    // The window capture is the visible page; the scroll view's document is the whole page.
                    let target = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                    capture(view, to: target)
                    if let page = view.firstDescendant(NSScrollView.self)?.documentView {
                        capture(page, to: target.deletingPathExtension().appendingPathExtension("page.png"))
                    }
                }
                print("UI smoke test: \(model.status), \(model.sampleRate) samples/s, actions armed: \(model.armed)")
                NSApp.terminate(nil)
            }
        }
    }
    @objc func showWindow() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    /// Renders a view over the window background colour, so transparent regions stay readable.
    private func capture(_ view: NSView, to url: URL) {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        var background = NSColor.windowBackgroundColor
        window.effectiveAppearance.performAsCurrentDrawingAppearance {
            background = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) ?? background
        }
        let image = NSImage(size: view.bounds.size)
        image.lockFocus()
        background.setFill()
        NSRect(origin: .zero, size: view.bounds.size).fill()
        bitmap.draw(in: NSRect(origin: .zero, size: view.bounds.size))
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
    @objc func toggleArmed() {
        guard model.listening, model.sampleRate > 0, model.calibrationSide == nil,
              !model.splitSides || model.calibration.isReady else { return }
        model.armed.toggle()
    }
    func menuWillOpen(_ menu: NSMenu) {
        armItem.state = model.armed ? .on : .off
        armItem.isEnabled = model.listening && model.sampleRate > 0 && model.calibrationSide == nil && (!model.splitSides || model.calibration.isReady)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

if CommandLine.arguments.contains("--probe") {
    let reader = SensorReader()
    var counts = [3: 0, 9: 0]
    var minMagnitude = Double.infinity, maxMagnitude = 0.0
    reader.onSample = { kind, _, value in
        counts[kind, default: 0] += 1
        if kind == 3 { minMagnitude = min(minMagnitude, value.magnitude); maxMagnitude = max(maxMagnitude, value.magnitude) }
    }
    if reader.start() {
        print(reader.message)
        RunLoop.main.run(until: Date().addingTimeInterval(3))
    } else { print(reader.message) }
    reader.stop()
    print("Accelerometer: \(counts[3] ?? 0) samples; gyroscope: \(counts[9] ?? 0) samples")
    if minMagnitude.isFinite { print(String(format: "Acceleration magnitude: %.3f–%.3f g", minMagnitude, maxMagnitude)) }
    exit((counts[3] ?? 0) > 0 ? 0 : 1)
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.setActivationPolicy(.regular)
    application.delegate = delegate
    application.run()
}

private extension NSView {
    func firstDescendant<T: NSView>(_ type: T.Type) -> T? {
        for subview in subviews {
            if let match = subview as? T { return match }
            if let found = subview.firstDescendant(type) { return found }
        }
        return nil
    }
}
