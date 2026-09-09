import Foundation
import OSLog

/// Bounded local event log plus a separate raw impact-window log.
/// No key contents, URLs, app paths or Shortcut names are recorded.
/// File writes run away from the sensor callback/main thread.
final class Diagnostics {
    static let shared = Diagnostics()
    let fileURL: URL
    let impactsURL: URL
    private let queue = DispatchQueue(label: "local.tapr.diagnostics", qos: .utility)
    private let logger = Logger(subsystem: "local.tapr.poc", category: "recognition")
    private let events: JSONLinesFile
    private let impacts: JSONLinesFile
    private init() {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Tapr")
        fileURL = directory.appendingPathComponent("events.jsonl")
        impactsURL = directory.appendingPathComponent("impacts.jsonl")
        events = JSONLinesFile(url: fileURL, limit: 2 * 1024 * 1024)
        impacts = JSONLinesFile(url: impactsURL, limit: 8 * 1024 * 1024)
    }
    /// Decision events: also mirrored to unified logging.
    func record(_ event: String, _ fields: [String: Any] = [:]) {
        guard let line = Self.encode(event, fields) else { return }
        logger.notice("\(String(decoding: line, as: UTF8.self), privacy: .public)")
        write(line, to: events)
    }
    /// Raw sensor samples around one impact: file only, they are too large for unified logging.
    func recordImpact(_ fields: [String: Any]) {
        guard let line = Self.encode("impact_window", fields) else { return }
        write(line, to: impacts)
    }
    func flush() { queue.sync { events.synchronize(); impacts.synchronize() } }
    private static func encode(_ event: String, _ fields: [String: Any]) -> Data? {
        var object = fields
        object["event"] = event
        object["timestamp"] = ISO8601DateFormatter().string(from: Date())
        object["uptime"] = ProcessInfo.processInfo.systemUptime
        object["pid"] = ProcessInfo.processInfo.processIdentifier
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    private func write(_ line: Data, to file: JSONLinesFile) {
        var data = line
        data.append(0x0A)
        queue.async { [logger] in
            do { try file.append(data) } catch {
                logger.error("Diagnostic file write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
