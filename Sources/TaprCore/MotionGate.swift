import Foundation

/// Reject sustained translation/rotation, then require a still period before accepting taps.
/// Angular velocity is low-passed with its sign, so the ringing and brief tilt that a
/// tap itself causes average out, while carrying or turning the laptop does not.
public struct MotionGate {
    public private(set) var isSettled = false
    public private(set) var reason = "settling"
    public private(set) var translationLevel = 0.0
    public private(set) var rotationRate = 0.0
    private var slow: Vector3?
    private var baseline = Vector3()
    private var rotation = Vector3()
    private var lastTime: Double?
    private var movingSince: Double?
    private var blockedUntil = 0.0
    public init() {}
    public mutating func reset() { self = Self() }
    @discardableResult
    public mutating func ingest(time: Double, acceleration: Vector3, gyro: Vector3) -> Bool {
        guard time.isFinite, acceleration.isFinite, gyro.isFinite else { return false }
        if let lastTime, time <= lastTime { return isSettled }
        if slow == nil || time - (lastTime ?? time) > 0.25 {
            slow = acceleration; baseline = acceleration; rotation = .init()
            blockedUntil = time + 0.6; movingSince = nil
        }
        let dt = min(0.05, time - (lastTime ?? time))
        lastTime = time
        slow = slow! + (acceleration - slow!) * (1 - exp(-dt / 0.10))
        baseline = baseline + (acceleration - baseline) * (1 - exp(-dt / 0.8))
        rotation = rotation + (gyro - rotation) * (1 - exp(-dt / 0.10))
        translationLevel = (slow! - baseline).magnitude
        rotationRate = rotation.magnitude
        let translating = translationLevel > 0.035
        let rotating = rotationRate > 8
        let displaced = abs(slow!.magnitude - 1) > 0.12
        if translating || rotating || displaced {
            if movingSince == nil { movingSince = time }
            if time - movingSince! >= 0.08 {
                blockedUntil = time + 0.65
                reason = rotating ? "rotation" : translating ? "translation" : "acceleration"
            }
        } else { movingSince = nil }
        isSettled = time >= blockedUntil
        if isSettled { reason = "still" }
        return isSettled
    }
}
