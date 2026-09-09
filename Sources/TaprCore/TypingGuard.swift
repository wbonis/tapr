import Foundation

/// Rejects impacts that look like typing: a key press right before or after the
/// impact, a vertical-only impulse while keys are pressed, or six impulses inside
/// 420 ms, which locks detection for 280 ms. Only timestamps are consulted.
public struct TypingGuard {
    public var keyWindow = 0.18
    public var keyLag = 0.06
    public var burstWindow = 0.42
    public var burstCount = 6
    public var lockout = 0.28
    private var impulses: [Double] = []
    private var lockedUntil = -Double.infinity
    public init() {}
    public mutating func reset() { impulses = []; lockedUntil = -.infinity }
    public func isLocked(at time: Double) -> Bool { time < lockedUntil }
    /// Returns a rejection reason, or nil when the impact may be a tap.
    public mutating func check(time: Double, lastKeyTime: Double?, vertical: Bool) -> String? {
        let keyed = lastKeyTime.map { time - $0 < keyWindow && $0 - time < keyLag } ?? false
        if keyed { return vertical ? "typing_vertical" : "typing_key" }
        if isLocked(at: time) { return "typing_lockout" }
        impulses = impulses.filter { time - $0 < burstWindow } + [time]
        guard impulses.count >= burstCount else { return nil }
        lockedUntil = time + lockout
        impulses = []
        return "typing_burst"
    }
}
