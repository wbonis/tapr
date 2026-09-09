import AppKit
import ApplicationServices

// All actions execute in the ordinary user process. No shell interpolation.
enum ActionKind: String, CaseIterable, Codable, Identifiable {
    case sound, none, shortcut, url, application, screenshot, copy, paste, playPause, mute, volumeUp, volumeDown
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sound: return "Play test sound"
        case .none: return "Do nothing"
        case .shortcut: return "Run Apple Shortcut"
        case .url: return "Open website"
        case .application: return "Open application"
        case .screenshot: return "Screenshot selection"
        case .copy: return "Copy (⌘C)"
        case .paste: return "Paste (⌘V)"
        case .playPause: return "Play / pause"
        case .mute: return "Mute / unmute"
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        }
    }
    var needsValue: Bool { [.shortcut, .url, .application].contains(self) }
    var placeholder: String {
        switch self {
        case .shortcut: return "Exact Shortcut name"
        case .url: return "https://example.com"
        case .application: return "/Applications/Safari.app"
        default: return ""
        }
    }
    var needsAccessibility: Bool { [.screenshot, .copy, .paste, .playPause, .mute, .volumeUp, .volumeDown].contains(self) }
}
struct ActionBinding: Codable {
    var kind: ActionKind = .sound
    var value: String = ""
}

enum ActionRunner {
    static func run(_ binding: ActionBinding, completion: @escaping (String) -> Void) {
        if binding.kind.needsAccessibility && !AXIsProcessTrusted() {
            completion("Enable Tapr in System Settings → Privacy & Security → Accessibility.")
            return
        }
        switch binding.kind {
        case .none: completion("No action assigned")
        case .sound:
            if let sound = NSSound(named: "Pop") { sound.play() } else { NSSound.beep() }
            completion("Played test sound")
        case .shortcut:
            guard !binding.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                completion("Enter a Shortcut name first"); return
            }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", binding.value]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                DispatchQueue.main.async {
                    completion(process.terminationStatus == 0 ? "Shortcut finished" : "Shortcut failed (\(process.terminationStatus)). Check its name and permissions in Shortcuts.")
                }
            }
            do { try process.run() } catch { completion(error.localizedDescription) }
        case .url:
            guard let url = URL(string: binding.value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                completion("Enter a valid http or https website address"); return
            }
            completion(NSWorkspace.shared.open(url) ? "Opened website" : "Could not open website")
        case .application:
            guard binding.value.hasPrefix("/"), binding.value.hasSuffix(".app"), FileManager.default.fileExists(atPath: binding.value) else {
                completion("Choose an existing .app"); return
            }
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: binding.value), configuration: .init()) { _, error in
                DispatchQueue.main.async { completion(error?.localizedDescription ?? "Opened application") }
            }
        case .copy: keyboard(8, flags: .maskCommand); completion("Sent ⌘C")
        case .paste: keyboard(9, flags: .maskCommand); completion("Sent ⌘V")
        case .screenshot: keyboard(21, flags: [.maskCommand, .maskShift]); completion("Started screenshot selection")
        case .playPause: media(16); completion("Sent play / pause")
        case .mute: media(7); completion("Sent mute")
        case .volumeUp: media(0); completion("Sent volume up")
        case .volumeDown: media(1); completion("Sent volume down")
        }
    }
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    private static func keyboard(_ key: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }
    private static func media(_ key: Int) {
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00), timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8, data1: (key << 16) | (state << 8), data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
