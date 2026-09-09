import Foundation

/// Learns which way the chassis moves for left and right taps.
///
/// Each example is a unit 6-vector (acceleration x/y/z, scaled gyro x/y/z), optionally
/// followed by the lateral attack value from `Impact.signature`. Examples learned before
/// that value existed keep working; the extra value is then ignored. The two
/// sides are separated along one axis: the difference of the class means, weighted
/// by the inverse per-dimension variance. That axis follows the roll direction in
/// practice, so a pitch that flips between taps on the same side does not matter.
/// Readiness is checked leave-one-out, so an example never votes for itself.
public struct SideCalibration: Codable {
    public struct Assessment {
        public let side: TapSide?
        /// -1…1; positive favours left, 0 lies halfway between the learned sides.
        public let vote: Double
        public let reason: String
    }
    struct Model {
        let axis: [Double]
        let center: Double
        let halfGap: Double
        func vote(_ signature: [Double]) -> Double {
            guard signature.count >= axis.count else { return 0 }
            let projection = SideCalibration.dot(axis, SideCalibration.normalized(Array(signature.prefix(axis.count))))
            return min(1, max(-1, (projection - center) / halfGap))
        }
    }
    /// Minimum |vote| for a tap, or for the summed votes of a burst, to name a side.
    public static let decisiveVote = 0.35
    public static let requiredSamples = 8
    static let baseDimensions = 6
    static let maximumDimensions = 7
    var dimensions: Int { left.first?.count ?? Self.baseDimensions }
    private static let minimumGap = 0.15
    private static let minimumResemblance = 0.4
    private static let regularization = 0.02
    // Optional so old settings still decode; the model discards only legacy calibration.
    public var signatureVersion: Int? = 2
    public var left: [[Double]] = []
    public var right: [[Double]] = []
    public init() {}

    public static func normalized(_ values: [Double]) -> [Double] {
        let norm = sqrt(values.reduce(0) { $0 + $1*$1 })
        return norm > 1e-9 ? values.map { $0 / norm } : values.map { _ in 0 }
    }
    static func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + $1.0*$1.1 } }
    private static func mean(_ samples: [[Double]]) -> [Double] {
        let dimensions = samples.first?.count ?? 0
        return (0..<dimensions).map { i in samples.reduce(0) { $0 + $1[i] } / Double(samples.count) }
    }
    private static func variance(_ samples: [[Double]], around mean: [Double]) -> [Double] {
        mean.indices.map { i in samples.reduce(0) { $0 + ($1[i] - mean[i]) * ($1[i] - mean[i]) } / Double(samples.count) }
    }
    static func fit(left: [[Double]], right: [[Double]]) -> Model? {
        guard let dimensions = left.first?.count, !right.isEmpty,
              (left + right).allSatisfy({ $0.count == dimensions }) else { return nil }
        let l = left.map(normalized), r = right.map(normalized)
        let meanLeft = mean(l), meanRight = mean(r)
        let spread = zip(variance(l, around: meanLeft), variance(r, around: meanRight)).map { ($0 + $1) / 2 }
        let axis = normalized((0..<dimensions).map { (meanLeft[$0] - meanRight[$0]) / (spread[$0] + regularization) })
        let projectedLeft = dot(axis, meanLeft), projectedRight = dot(axis, meanRight)
        let halfGap = (projectedLeft - projectedRight) / 2
        guard halfGap >= minimumGap else { return nil }
        return Model(axis: axis, center: (projectedLeft + projectedRight) / 2, halfGap: halfGap)
    }
    private func valid(_ samples: [[Double]]) -> Bool {
        samples.count >= Self.requiredSamples && samples.allSatisfy { sample in
            let base = Array(sample.prefix(Self.baseDimensions))
            return sample.count == dimensions && (Self.baseDimensions...Self.maximumDimensions).contains(sample.count) &&
                sample.allSatisfy(\.isFinite) && Self.dot(base, base) > 0.9
        }
    }
    /// Held-out examples must land on their own side with a decisive vote and must
    /// resemble the rest of their class. A minority of outliers is tolerated.
    private func distinguishable(_ own: [[Double]], from other: [[Double]], sign: Double) -> Bool {
        let matches = own.indices.filter { index in
            let peers = own.enumerated().filter { $0.offset != index }.map(\.element)
            let sides = sign > 0 ? (peers, other) : (other, peers)
            guard let model = Self.fit(left: sides.0, right: sides.1) else { return false }
            let resemblance = Self.dot(Self.normalized(own[index]), Self.normalized(Self.mean(peers.map(Self.normalized))))
            return model.vote(own[index]) * sign >= Self.decisiveVote && resemblance >= Self.minimumResemblance
        }.count
        return Double(matches) / Double(own.count) >= 0.75
    }
    public var isReady: Bool {
        signatureVersion == 2 && valid(left) && valid(right) &&
        distinguishable(left, from: right, sign: 1) && distinguishable(right, from: left, sign: -1)
    }
    public func classify(_ signature: [Double]) -> TapSide? {
        assess(signature).side
    }
    public func assess(_ signature: [Double]) -> Assessment {
        guard isReady, signature.count >= dimensions, signature.allSatisfy(\.isFinite),
              let model = Self.fit(left: left, right: right) else {
            return Assessment(side: nil, vote: 0, reason: "calibration_not_ready_or_invalid_signature")
        }
        let vote = model.vote(signature)
        guard abs(vote) >= Self.decisiveVote else { return Assessment(side: nil, vote: vote, reason: "ambiguous_side") }
        return Assessment(side: vote > 0 ? .left : .right, vote: vote, reason: "accepted")
    }
}
