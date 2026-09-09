import XCTest
@testable import TaprCore

final class DetectionTests: XCTestCase {
    func testSingleWaitsForQuietInterval() {
        var sequence = TapSequence()
        XCTAssertNil(sequence.register(side: .any, at: 1))
        XCTAssertNil(sequence.flush(at: 1.3))
        XCTAssertEqual(sequence.flush(at: 1.4), Gesture(side: .any, count: 1))
        XCTAssertNil(sequence.flush(at: 2))
    }
    func testDoubleWaitsForQuietButTripleFiresImmediately() {
        var sequence = TapSequence()
        XCTAssertNil(sequence.register(side: .left, at: 1))
        XCTAssertNil(sequence.register(side: .left, at: 1.2))
        XCTAssertEqual(sequence.flush(at: 2), Gesture(side: .left, count: 2))
        XCTAssertNil(sequence.flush(at: 3))
        XCTAssertNil(sequence.register(side: .left, at: 4))
        XCTAssertNil(sequence.register(side: .left, at: 4.2))
        XCTAssertEqual(sequence.register(side: .left, at: 4.4), Gesture(side: .left, count: 3))
        XCTAssertEqual(sequence.pendingCount, 0)
        XCTAssertNil(sequence.flush(at: 5))
    }
    func testTapsRightAfterAnImmediateTripleAreDroppedUntilQuiet() {
        var sequence = TapSequence()
        for time in [1.0, 1.2, 1.4] { _ = sequence.register(side: .any, at: time) }
        XCTAssertNil(sequence.register(side: .any, at: 1.55))
        XCTAssertEqual(sequence.lastDrop, "after_triple")
        XCTAssertNil(sequence.register(side: .any, at: 1.8))
        XCTAssertEqual(sequence.lastDrop, "after_triple")
        XCTAssertEqual(sequence.pendingCount, 0)
        XCTAssertNil(sequence.flush(at: 2.1))
        XCTAssertNil(sequence.register(side: .any, at: 2.2))
        XCTAssertNil(sequence.lastDrop)
        XCTAssertEqual(sequence.pendingCount, 1)
        XCTAssertEqual(sequence.flush(at: 2.6), Gesture(side: .any, count: 1))
    }
    func testMixedUnknownAndExcessTapsAreRejected() {
        for sides: [TapSide?] in [[.left, .right], [nil], [nil, nil], [.left, .right, nil]] {
            var sequence = TapSequence()
            for (i, side) in sides.enumerated() { XCTAssertNil(sequence.register(side: side, at: 1 + Double(i)*0.2)) }
            XCTAssertNil(sequence.flush(at: 3))
            XCTAssertNotNil(sequence.lastRejection)
            XCTAssertNil(sequence.register(side: .right, at: 4))
            XCTAssertEqual(sequence.flush(at: 5), Gesture(side: .right, count: 1))
            XCTAssertNil(sequence.lastRejection)
        }
    }
    func testOneUncertainTapInsideAConfidentBurstKeepsTheBurst() {
        var sequence = TapSequence()
        XCTAssertNil(sequence.register(side: .left, at: 1))
        XCTAssertNil(sequence.register(side: nil, at: 1.2))
        XCTAssertEqual(sequence.flush(at: 2), Gesture(side: .left, count: 2))
    }
    func testBurstSideVotesAreSummed() {
        let cases: [([Double], [Gesture], String?)] = [
            ([1, 0], [Gesture(side: .left, count: 2)], nil),
            ([1, 1, -0.4], [Gesture(side: .left, count: 3)], nil),
            ([-0.9, 0.9], [], "mixed_sides"),
            ([0.2], [], "uncertain_side"),
            ([0.3, -0.25], [], "uncertain_side"),
            ([0.4], [Gesture(side: .left, count: 1)], nil),
            ([-0.5, -0.2, 0.3], [Gesture(side: .right, count: 3)], nil),
            ([1, 1, 1, 1], [Gesture(side: .left, count: 3)], nil)
        ]
        for (votes, expected, rejection) in cases {
            var sequence = TapSequence()
            var gestures: [Gesture] = []
            for (i, vote) in votes.enumerated() {
                if let gesture = sequence.register(.side(vote: vote), at: 1 + Double(i)*0.1) { gestures.append(gesture) }
            }
            if let gesture = sequence.flush(at: 3) { gestures.append(gesture) }
            XCTAssertEqual(gestures, expected, "\(votes)")
            XCTAssertEqual(sequence.lastRejection, rejection, "\(votes)")
        }
    }
    func testAdaptiveNoiseFloorRaisesTriggerAndReportsSNR() {
        var detector = ImpactDetector()
        detector.threshold = 0.024
        var impacts: [Impact] = []
        for i in 0..<2000 {
            let t = Double(i) / 800
            var x = 0.018 * sin(2 * .pi * 53 * t)
            if t >= 1.5 && t < 1.505 { x += 0.03 }
            if let impact = detector.ingest(time: t, acceleration: Vector3(x, 0, 1)) { impacts.append(impact) }
            if t > 1 && t < 1.5 {
                XCTAssertGreaterThan(detector.effectiveThreshold, detector.threshold + 0.0002)
                XCTAssertLessThan(detector.effectiveThreshold, 0.032)
            }
        }
        XCTAssertEqual(impacts.count, 1)
        XCTAssertGreaterThan(impacts.first?.snr ?? 0, 2)
        XCTAssertEqual(impacts.first?.noise ?? 0, 0.0115, accuracy: 0.004)
    }
    func testAttackXFollowsLateralDirection() {
        func attack(sign: Double) -> Impact? {
            var detector = ImpactDetector()
            var result: Impact?
            for i in 0..<1200 {
                let t = Double(i) / 800, d = t - 1
                let pulse = d >= 0 && d < 0.008 ? sin(d * .pi / 0.008) : 0
                if let impact = detector.ingest(time: t, acceleration: Vector3(sign * 0.06 * pulse, 0, 1 + 0.02 * pulse)) { result = impact }
            }
            return result
        }
        let right = attack(sign: 1), left = attack(sign: -1)
        XCTAssertGreaterThan(right?.attackX ?? 0, 0.01)
        XCTAssertLessThan(left?.attackX ?? 0, -0.01)
        XCTAssertGreaterThan(right?.signature[6] ?? 0, 0.5)
        XCTAssertLessThan(left?.signature[6] ?? 0, -0.5)
        XCTAssertGreaterThan(right?.attackPeakX ?? 0, 0.01)
        XCTAssertLessThan(abs(right?.attackZ ?? 1), abs(right?.attackX ?? 0))
    }
    func testUnifiedAndSidedTapsDoNotMixInsideOneBurst() {
        var sequence = TapSequence()
        XCTAssertNil(sequence.register(.unified, at: 1))
        XCTAssertNil(sequence.register(.side(vote: 1), at: 1.2))
        XCTAssertNil(sequence.flush(at: 2))
        XCTAssertEqual(sequence.lastRejection, "mixed_modes")
    }
    func testPauseDiscardsPendingGestureAndSeparatedBurstsWork() {
        var sequence = TapSequence()
        _ = sequence.register(side: .any, at: 1)
        sequence.reset()
        XCTAssertNil(sequence.flush(at: 2))
        _ = sequence.register(side: .left, at: 3)
        XCTAssertEqual(sequence.register(side: .right, at: 4), Gesture(side: .left, count: 1))
        XCTAssertEqual(sequence.flush(at: 5), Gesture(side: .right, count: 1))
    }
    func testStationaryNoiseAndSlowMovementDoNotTrigger() {
        var detector = ImpactDetector()
        for i in 0..<1000 {
            let t = Double(i)*0.005
            let x = 0.004*sin(Double(i)*1.9) + 0.04*sin(t)
            XCTAssertNil(detector.ingest(time: t, acceleration: Vector3(x, 0, 1)))
        }
    }
    func testDampedImpactTriggersOnceAndSecondTapCanFollow() {
        var detector = ImpactDetector()
        var impacts: [Impact] = []
        for i in 0..<400 {
            let t = Double(i)*0.005
            var x = 0.0
            for start in [1.0, 1.3] {
                let d = t-start
                if d >= 0 && d < 0.08 { x += 0.18*exp(-d*70)*cos(d*600) }
            }
            if let impact = detector.ingest(time: t, acceleration: Vector3(x, 0, 1)) { impacts.append(impact) }
        }
        XCTAssertEqual(impacts.count, 2)
        XCTAssertEqual(impacts[0].time, 1, accuracy: 0.01)
        XCTAssertEqual(impacts[1].time, 1.3, accuracy: 0.01)
    }
    func testWarmupGapAndInvalidDataDoNotCreateTaps() {
        var detector = ImpactDetector()
        XCTAssertNil(detector.ingest(time: 0, acceleration: Vector3(0, 0, 1)))
        XCTAssertNil(detector.ingest(time: 0.005, acceleration: Vector3(0.8, 0, 1)))
        XCTAssertNil(detector.ingest(time: .nan, acceleration: Vector3()))
        XCTAssertNil(detector.ingest(time: 1, acceleration: Vector3(0, 1, 0)))
        XCTAssertNil(detector.ingest(time: 1.1, acceleration: Vector3(0, 1, 0)))
        XCTAssertNil(detector.ingest(time: 1.05, acceleration: Vector3(9, 9, 9)))
    }
    func testSecondImpactNearDeadlineDoesNotFireAnEarlySingle() {
        var detector = ImpactDetector()
        var sequence = TapSequence()
        var gestures: [Gesture] = []
        for i in 0..<500 {
            let time = Double(i) * 0.005
            var x = 0.0
            for start in [1.0, 1.375] {
                let delta = time - start
                if delta >= 0 && delta < 0.08 { x += 0.18 * exp(-delta * 70) * cos(delta * 600) }
            }
            if let impact = detector.ingest(time: time, acceleration: Vector3(x, 0, 1)),
               let gesture = sequence.register(side: .any, at: impact.time) { gestures.append(gesture) }
            if i % 4 == 0 && !detector.hasPendingImpact, let gesture = sequence.flush(at: time) {
                gestures.append(gesture)
            }
        }
        XCTAssertEqual(gestures, [Gesture(side: .any, count: 2)])
    }
    func testSlowRollResidualFromPreviousTapDoesNotFlipSignature() {
        // 200 ms after a tap the chassis is still rolling back at a few °/s.
        // That slow residual must not outweigh the roll direction of the next impact.
        func signature(residual: Double) -> [Double] {
            var detector = ImpactDetector()
            var result: [Double] = []
            for i in 0..<1600 {
                let t = Double(i) / 800
                let d = t - 1
                let impact = d >= 0 && d < 0.02 ? sin(d * .pi / 0.02) : 0
                let gyro = Vector3(0, -6 * impact + (t > 0.5 ? residual : 0), 0)
                if let found = detector.ingest(time: t, acceleration: Vector3(0.15 * impact, 0, 1), gyro: gyro) {
                    result = found.signature
                }
            }
            return result
        }
        let clean = signature(residual: 0), drifting = signature(residual: 4)
        XCTAssertEqual(clean.count, 7)
        XCTAssertLessThan(clean[4], -0.3)
        XCTAssertLessThan(drifting[4], -0.3)
        XCTAssertGreaterThan(zip(clean, drifting).reduce(0) { $0 + $1.0 * $1.1 }, 0.95)
    }
    func testCalibrationRequiresDistinctSidesAndRejectsUncertainSamples() {
        var calibration = SideCalibration()
        XCTAssertFalse(calibration.isReady)
        calibration.left = Array(repeating: [1, 0, 0, 0, 0, 0], count: SideCalibration.requiredSamples)
        calibration.right = calibration.left
        XCTAssertFalse(calibration.isReady)
        calibration.right = Array(repeating: [-1, 0, 0, 0, 0, 0], count: SideCalibration.requiredSamples)
        XCTAssertTrue(calibration.isReady)
        XCTAssertEqual(calibration.classify([2, 0.1, 0, 0, 0, 0]), .left)
        XCTAssertEqual(calibration.assess([2, 0.1, 0, 0, 0, 0]).vote, 1, accuracy: 0.01)
        XCTAssertEqual(calibration.assess([0.3, 1, 0, 0, 0, 0]).vote, 0.29, accuracy: 0.01)
        XCTAssertEqual(calibration.classify([-1, 0, 0, 0, 0, 0]), .right)
        XCTAssertNil(calibration.classify([0, 1, 0, 0, 0, 0]))
        XCTAssertNil(calibration.classify([Double.nan, 0, 0, 0, 0, 0]))
        calibration.left = [[1]]
        XCTAssertFalse(calibration.isReady)
    }
    func testCalibrationAcceptsSevenDimensionsAndSixDimensionalLegacyExamples() {
        var calibration = SideCalibration()
        calibration.left = (0..<8).map { i in [0, 0, 0.3, 0, -0.95, 0, -0.8 + Double(i) * 0.02] }
        calibration.right = (0..<8).map { i in [0, 0, 0.3, 0, 0.95, 0, 0.8 - Double(i) * 0.02] }
        XCTAssertTrue(calibration.isReady)
        XCTAssertEqual(calibration.classify([0, 0, 0.3, 0, -0.5, 0, -0.9]), .left)
        XCTAssertEqual(calibration.classify([0, 0, 0.3, 0, 0.5, 0, 0.9]), .right)
        calibration.left = Array(repeating: [0, 0, 0.3, 0, -0.95, 0], count: 8)
        calibration.right = Array(repeating: [0, 0, 0.3, 0, 0.95, 0], count: 8)
        XCTAssertTrue(calibration.isReady)
        XCTAssertEqual(calibration.classify([0, 0, 0.3, 0, -0.9, 0, 0.9]), .left, "legacy examples ignore the seventh value")
    }
}
