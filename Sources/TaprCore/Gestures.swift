import Foundation

public enum TapSide: String, CaseIterable, Codable {
    case any, left, right
    public var label: String { rawValue.capitalized }
}

public struct Gesture: Equatable {
    public let side: TapSide
    public let count: Int
    public var key: String { "\(side.rawValue)-\(count)" }
    public init(side: TapSide, count: Int) { self.side = side; self.count = count }
}

/// What one impact contributes to a burst: either an unsided tap, or a side
/// vote in -1…1 where positive favours the left side and 0 means uncertain.
public enum TapEvidence: Equatable {
    case unified
    case side(vote: Double)
    public static func from(_ side: TapSide?) -> TapEvidence {
        switch side {
        case .any: return .unified
        case .left: return .side(vote: 1)
        case .right: return .side(vote: -1)
        case nil: return .side(vote: 0)
        }
    }
}

/// A quiet interval ends a single or double; a third tap fires at once. Taps that
/// follow a triple are dropped until the interval has been quiet again. Side votes
/// are summed over the burst, so one uncertain tap does not discard a confident
/// double or triple. Strong votes for both sides invalidate the burst.
public struct TapSequence {
    /// A tap voting at least this strongly against the burst majority is a conflict.
    public static let conflictingVote = 0.6
    public var interval: Double = 0.38
    public private(set) var lastRejection: String?
    /// Set when `register` discards the tap it was given, e.g. right after a triple.
    public private(set) var lastDrop: String?
    private var taps: [TapEvidence] = []
    private var lastTime: Double?
    private var quietUntil = -Double.infinity
    public var pendingCount: Int { taps.count }
    public init() {}
    public mutating func reset() { clear(); quietUntil = -.infinity }
    private mutating func clear() { taps = []; lastTime = nil }
    public mutating func register(side: TapSide?, at time: Double) -> Gesture? {
        register(.from(side), at: time)
    }
    public mutating func register(_ evidence: TapEvidence, at time: Double) -> Gesture? {
        let previous = flush(at: time)
        lastDrop = nil
        if let lastTime, time < lastTime { return previous }
        if time < quietUntil {
            quietUntil = time + interval
            lastDrop = "after_triple"
            return previous
        }
        taps.append(evidence)
        lastTime = time
        guard taps.count == 3 else { return previous }
        let outcome = Self.resolve(taps)
        lastRejection = outcome.rejection
        clear()
        quietUntil = time + interval
        return outcome.gesture ?? previous
    }
    public mutating func flush(at time: Double) -> Gesture? {
        guard let lastTime, time - lastTime >= interval else { return nil }
        let outcome = Self.resolve(taps)
        lastRejection = outcome.rejection
        clear()
        return outcome.gesture
    }
    static func resolve(_ taps: [TapEvidence]) -> (gesture: Gesture?, rejection: String?) {
        guard !taps.isEmpty else { return (nil, nil) }
        let votes = taps.compactMap { evidence -> Double? in
            if case .side(let vote) = evidence { return vote } else { return nil }
        }
        if votes.isEmpty { return (Gesture(side: .any, count: taps.count), nil) }
        guard votes.count == taps.count else { return (nil, "mixed_modes") }
        let strongestLeft = votes.max() ?? 0, strongestRight = -(votes.min() ?? 0)
        if min(strongestLeft, strongestRight) >= conflictingVote { return (nil, "mixed_sides") }
        let total = votes.reduce(0, +)
        guard abs(total) >= SideCalibration.decisiveVote else { return (nil, "uncertain_side") }
        return (Gesture(side: total > 0 ? .left : .right, count: taps.count), nil)
    }
}
