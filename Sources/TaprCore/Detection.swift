import Foundation

public struct Vector3: Equatable, Codable {
    public var x: Double
    public var y: Double
    public var z: Double
    public init(_ x: Double = 0, _ y: Double = 0, _ z: Double = 0) { self.x = x; self.y = y; self.z = z }
    public var magnitude: Double { sqrt(x*x + y*y + z*z) }
    public var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    public static func + (a: Self, b: Self) -> Self { Self(a.x+b.x, a.y+b.y, a.z+b.z) }
    public static func - (a: Self, b: Self) -> Self { Self(a.x-b.x, a.y-b.y, a.z-b.z) }
    public static func * (a: Self, b: Double) -> Self { Self(a.x*b, a.y*b, a.z*b) }
}

public struct Impact {
    public let time: Double
    public let strength: Double
    /// Adaptive noise floor (g) at onset; `strength / noise` is the SNR.
    public let noise: Double
    /// Baseline-subtracted lateral (x) and vertical (z) motion over the first 34 ms,
    /// weighted by exp(-t / 11 ms), plus the largest lateral excursion.
    public let attackX: Double
    public let attackZ: Double
    public let attackPeakX: Double
    /// Unit 6-vector (acceleration x/y/z, scaled rotation x/y/z) followed by tanh(attackX / 0.012).
    public let signature: [Double]
    public var snr: Double { noise > 0 ? strength / noise : .infinity }
}

/// Removes slow movement/gravity, then groups a short burst of vibration into one impact.
/// The trigger level rises above a noisy desk: at least `snrMultiplier` times the adaptive
/// noise floor, which follows samples below 90% of the configured threshold.
/// Angular velocity is taken relative to its slow baseline frozen at impact onset: 200 ms
/// after a tap the chassis is still rolling back at a few °/s, which otherwise outweighs
/// the roll direction of the next impact. Thresholds are experimental.
public struct ImpactDetector {
    public static let snrMultiplier = 2.2
    public static let lateralScale = 0.012
    public var threshold: Double = 0.045
    public private(set) var level: Double = 0
    public private(set) var noiseFloor: Double = 0.006
    public var effectiveThreshold: Double { max(threshold, noiseFloor * Self.snrMultiplier) }
    public var hasPendingImpact: Bool { pending != nil }
    private struct Pending {
        let time: Double
        var strength: Double
        let noise: Double
    }
    private var gravity: Vector3?
    private var gyroBaseline = Vector3()
    private var gyroOffset = Vector3()
    private var lastTime: Double?
    private var warmUntil: Double = 0
    private var releaseRequired = false
    private var quietSince: Double?
    private var nextAllowed: Double = 0
    private var pending: Pending?
    private var pendingUntil: Double = 0
    private var signatureSum = Vector3()
    private var gyroSum = Vector3()
    private var history = LateralHistory()
    private var attack = AttackWindow()
    public init() {}
    public mutating func suppress() {
        pending = nil
        releaseRequired = true
        quietSince = nil
    }
    public mutating func reset() {
        let savedThreshold = threshold
        self = Self()
        threshold = savedThreshold
    }
    public mutating func ingest(time: Double, acceleration: Vector3, gyro: Vector3 = .init()) -> Impact? {
        guard time.isFinite, acceleration.isFinite, gyro.isFinite else { return nil }
        if let lastTime, time <= lastTime { return nil }
        if gravity == nil || time - (lastTime ?? time) > 0.25 {
            gravity = acceleration
            gyroBaseline = gyro
            warmUntil = time + 0.5
            pending = nil
            releaseRequired = false
            quietSince = nil
            nextAllowed = time
            history.reset()
        }
        let dt = min(0.05, time - (lastTime ?? time))
        lastTime = time
        let alpha = exp(-dt / 0.045)
        gravity = gravity! * alpha + acceleration * (1 - alpha)
        let previousBaseline = gyroBaseline
        gyroBaseline = gyroBaseline * alpha + gyro * (1 - alpha)
        let motion = acceleration - gravity!
        level = motion.magnitude
        history.push(time: time, x: motion.x, z: motion.z)
        if level < threshold * 0.9 {
            noiseFloor = min(0.030, max(0.0035, 0.02 * level + 0.98 * noiseFloor))
        }
        guard time >= warmUntil else { return nil }
        let trigger = effectiveThreshold

        var completed: Impact?
        if let impact = pending, time >= pendingUntil {
            completed = finish(impact)
            pending = nil
            nextAllowed = impact.time + 0.075
            releaseRequired = true
        }
        // A single zero crossing during ringing is not a return to rest.
        if level < trigger * 0.4 {
            if quietSince == nil { quietSince = time }
            if time - quietSince! >= 0.02 { releaseRequired = false }
        } else { quietSince = nil }
        if pending != nil {
            let rotation = gyro - gyroOffset
            let weight = exp(-(time - pending!.time) / 0.012) * dt
            signatureSum = signatureSum + motion * weight
            gyroSum = gyroSum + rotation * weight
            attack.add(time: time, x: motion.x, z: motion.z)
            if level > pending!.strength { pending!.strength = level }
        } else if completed == nil && !releaseRequired && time >= nextAllowed && level >= trigger {
            gyroOffset = previousBaseline
            pending = Pending(time: time, strength: level, noise: noiseFloor)
            signatureSum = motion * dt
            gyroSum = (gyro - gyroOffset) * dt
            attack.begin(at: time, baseline: history.baseline(at: time))
            attack.add(time: time, x: motion.x, z: motion.z)
            pendingUntil = time + 0.04
        }
        return completed
    }
    private func finish(_ impact: Pending) -> Impact {
        let a = signatureSum, g = gyroSum * 0.02
        let base = SideCalibration.normalized([a.x, a.y, a.z, g.x, g.y, g.z])
        return Impact(time: impact.time, strength: impact.strength, noise: impact.noise,
                      attackX: attack.meanX, attackZ: attack.meanZ, attackPeakX: attack.peakAbsX,
                      signature: base + [tanh(attack.meanX / Self.lateralScale)])
    }
}
