import Foundation

/// Ring of recent high-passed lateral/vertical motion, for the pre-tap baseline.
struct LateralHistory {
    private struct Entry {
        let time: Double
        let x: Double
        let z: Double
    }
    private let capacity = 96
    private var entries: [Entry?]
    private var head = 0
    private var count = 0
    init() { entries = Array(repeating: nil, count: capacity) }
    mutating func reset() { head = 0; count = 0 }
    mutating func push(time: Double, x: Double, z: Double) {
        entries[head] = Entry(time: time, x: x, z: z)
        head = (head + 1) % capacity
        count = min(count + 1, capacity)
    }
    /// Mean of the samples 12–100 ms before `time`; zero when fewer than four exist.
    /// Residual gravity leak is a DC offset that would pin every tap to one side.
    func baseline(at time: Double) -> (x: Double, z: Double) {
        var sumX = 0.0, sumZ = 0.0, samples = 0
        for offset in 0..<count {
            guard let entry = entries[(head - 1 - offset + capacity) % capacity] else { continue }
            let age = time - entry.time
            if age > 0.1 { break }
            if age > 0.012 { sumX += entry.x; sumZ += entry.z; samples += 1 }
        }
        return samples >= 4 ? (sumX / Double(samples), sumZ / Double(samples)) : (0, 0)
    }
}

/// Energy-weighted mean lateral/vertical motion over the first 34 ms of an impact,
/// after subtracting the pre-tap baseline. Bounce after the attack is not consulted.
struct AttackWindow {
    static let duration = 0.034
    static let tau = 0.011
    private(set) var meanX = 0.0
    private(set) var meanZ = 0.0
    private(set) var peakAbsX = 0.0
    private var onset = 0.0
    private var baselineX = 0.0
    private var baselineZ = 0.0
    private var sumX = 0.0
    private var sumZ = 0.0
    private var weights = 0.0
    mutating func begin(at time: Double, baseline: (x: Double, z: Double)) {
        self = Self()
        onset = time
        baselineX = baseline.x
        baselineZ = baseline.z
    }
    mutating func add(time: Double, x: Double, z: Double) {
        let elapsed = time - onset
        guard elapsed >= 0, elapsed <= Self.duration else { return }
        let weight = exp(-elapsed / Self.tau)
        let dx = x - baselineX
        sumX += dx * weight
        sumZ += (z - baselineZ) * weight
        weights += weight
        peakAbsX = max(peakAbsX, abs(dx))
        meanX = sumX / weights
        meanZ = sumZ / weights
    }
}
