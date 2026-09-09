import Foundation

/// Keeps the most recent 0.4 s of paired sensor samples and, once the samples
/// after an impact exist, returns a window from 40 ms before to 100 ms after it.
/// The window feeds offline feature design; nothing here affects detection.
public final class ImpactCapture {
    public static let before = 0.04
    public static let after = 0.1
    private struct Entry {
        let time: Double
        let acceleration: Vector3
        let gyro: Vector3
    }
    private let capacity = 320
    private var entries: [Entry?]
    private var head = 0
    private var count = 0
    private var pending: [(onset: Double, fields: [String: Any])] = []
    public init() { entries = Array(repeating: nil, count: capacity) }
    public func reset() { head = 0; count = 0; pending = [] }
    public func schedule(onset: Double, fields: [String: Any]) { pending.append((onset, fields)) }
    /// Stores one sample and returns a completed window, if any became available.
    public func push(time: Double, acceleration: Vector3, gyro: Vector3) -> [String: Any]? {
        entries[head] = Entry(time: time, acceleration: acceleration, gyro: gyro)
        head = (head + 1) % capacity
        count = min(count + 1, capacity)
        guard let index = pending.firstIndex(where: { time >= $0.onset + Self.after }) else { return nil }
        let item = pending.remove(at: index)
        return window(onset: item.onset, fields: item.fields)
    }
    private func window(onset: Double, fields: [String: Any]) -> [String: Any] {
        let start = (head - count + capacity) % capacity
        let samples = (0..<count).compactMap { entries[(start + $0) % capacity] }
            .filter { $0.time >= onset - Self.before && $0.time <= onset + Self.after }
        var object = fields
        object["onset"] = onset
        object["sample_count"] = samples.count
        object["t_ms"] = samples.map { Self.round(($0.time - onset) * 1000, places: 2) }
        object["ax"] = samples.map { Self.round($0.acceleration.x, places: 5) }
        object["ay"] = samples.map { Self.round($0.acceleration.y, places: 5) }
        object["az"] = samples.map { Self.round($0.acceleration.z, places: 5) }
        object["gx"] = samples.map { Self.round($0.gyro.x, places: 3) }
        object["gy"] = samples.map { Self.round($0.gyro.y, places: 3) }
        object["gz"] = samples.map { Self.round($0.gyro.z, places: 3) }
        return object
    }
    private static func round(_ value: Double, places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }
}
