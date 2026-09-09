import AppKit

/// Remembers only *when* the last key went down, never which key. The global
/// monitor delivers events only while Tapr has Accessibility access.
final class KeyboardActivity {
    private(set) var lastKeyTime: Double?
    private var monitors: [Any] = []
    var isActive: Bool { !monitors.isEmpty }
    func start() {
        guard monitors.isEmpty else { return }
        let note: (NSEvent) -> Void = { [weak self] event in self?.lastKeyTime = event.timestamp }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: note) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in note(event); return event }) {
            monitors.append(local)
        }
    }
    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        lastKeyTime = nil
    }
    deinit { stop() }
}
