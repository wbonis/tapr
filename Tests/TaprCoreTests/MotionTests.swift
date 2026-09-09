import XCTest
@testable import TaprCore

final class MotionTests: XCTestCase {
    func testStillLaptopWithShortTapSpikesRemainsReady() {
        var gate = MotionGate()
        for i in 0..<1600 {
            let t = Double(i) / 800
            let impact = t >= 1 && t < 1.02
            let settled = gate.ingest(time: t, acceleration: Vector3(impact ? 0.2 : 0, 0, 1),
                                      gyro: Vector3(0, impact ? 20 : 0, 0))
            if t > 0.7 { XCTAssertTrue(settled) }
        }
    }
    func testTapRingingAndPalmTiltDoNotBlock() {
        // A firm tap rings the chassis at ±25°/s for 80 ms and the case tilts
        // briefly under the palm (10°/s down, then back). Neither is handling.
        var gate = MotionGate()
        for i in 0..<2400 {
            let t = Double(i) / 800
            var rate = 0.0
            let ring = t - 1
            if ring >= 0 && ring < 0.08 { rate += 25 * exp(-ring * 40) * cos(ring * 2 * .pi * 150) }
            if t >= 2 && t < 2.05 { rate += 10 } else if t >= 2.05 && t < 2.1 { rate -= 10 }
            let settled = gate.ingest(time: t, acceleration: Vector3(0, 0, 1), gyro: Vector3(rate, rate * 0.5, 0))
            if t > 0.7 { XCTAssertTrue(settled, "blocked at \(t) with reason \(gate.reason)") }
        }
    }
    func testSlowSustainedRotationBlocks() {
        var gate = MotionGate()
        var blockedAt: Double?
        for i in 0..<2400 {
            let t = Double(i) / 800
            let rotating = t >= 1 && t < 1.5
            let settled = gate.ingest(time: t, acceleration: Vector3(0, 0, 1), gyro: Vector3(0, rotating ? 10 : 0, 0))
            if !settled && t > 1 && blockedAt == nil { blockedAt = t; XCTAssertEqual(gate.reason, "rotation") }
        }
        XCTAssertNotNil(blockedAt)
        XCTAssertLessThan(blockedAt ?? 9, 1.35)
        XCTAssertTrue(gate.isSettled)
    }
    func testMovingLaptopCancelsPendingTapAndSettlesBeforeNextTap() {
        var gate = MotionGate()
        var detector = ImpactDetector()
        var sequence = TapSequence()
        var gestures: [Gesture] = []
        for i in 0..<4000 {
            let t = Double(i) / 800
            let moving = t >= 1.1 && t < 1.7
            let angle = min(max(t - 1.1, 0), 0.6) * 0.3
            var impact = 0.0
            for start in [1.0, 4.0] {
                let delta = t - start
                if delta >= 0 && delta < 0.06 { impact += 0.18 * exp(-delta * 70) * cos(delta * 600) }
            }
            let acceleration = Vector3(sin(angle) + impact, 0, cos(angle))
            let gyro = Vector3(0, moving ? 17.2 : 0, 0)
            let settled = gate.ingest(time: t, acceleration: acceleration, gyro: gyro)
            let detected = detector.ingest(time: t, acceleration: acceleration, gyro: gyro)
            if !settled { sequence.reset(); detector.suppress(); continue }
            if let detected, let gesture = sequence.register(side: .any, at: detected.time) { gestures.append(gesture) }
            if !detector.hasPendingImpact, let gesture = sequence.flush(at: t) { gestures.append(gesture) }
        }
        // The first genuine tap is cancelled by immediately moving the laptop;
        // motion itself produces no action; the later stationary tap works.
        XCTAssertEqual(gestures, [Gesture(side: .any, count: 1)])
        XCTAssertTrue(gate.isSettled)
    }
    func testSustainedTranslationIsBlockedWithoutGyroscope() {
        var gate = MotionGate()
        for i in 0..<1600 {
            let t = Double(i) / 800
            let settled = gate.ingest(time: t, acceleration: Vector3(t > 1 ? 0.2 : 0, 0, 1), gyro: .init())
            if t > 1.2 && t < 1.6 { XCTAssertFalse(settled) }
        }
    }
    func testSideLearningToleratesPolarityFlipsOffTheDiscriminatingAxis() {
        // Pitch (gyro x) flips between taps on the same side; roll (gyro y) does not.
        var calibration = SideCalibration()
        calibration.left = (0..<8).map { i in
            SideCalibration.normalized([0.02, -0.05, 0.2 + Double(i) * 0.01, i % 2 == 0 ? 0.6 : -0.6, -0.7, 0.05])
        }
        calibration.right = (0..<8).map { i in
            SideCalibration.normalized([0.02, 0.05, 0.2 + Double(i) * 0.01, i % 2 == 0 ? 0.6 : -0.6, 0.7, -0.05])
        }
        XCTAssertTrue(calibration.isReady)
        XCTAssertEqual(calibration.classify([0, 0, 0.3, -0.9, -0.4, 0]), .left)
        XCTAssertEqual(calibration.classify([0, 0, 0.3, 0.9, 0.4, 0]), .right)
        XCTAssertEqual(calibration.classify([0, 0, 0.3, -0.9, 0.4, 0]), .right)
        let left = calibration.assess([0.02, -0.05, 0.2, -0.6, -0.7, 0.05])
        XCTAssertGreaterThan(left.vote, 0.9)
        XCTAssertEqual(left.reason, "accepted")
        let ambiguous = calibration.assess([0, 0, 1, 0.5, 0, 0])
        XCTAssertNil(ambiguous.side)
        XCTAssertEqual(ambiguous.reason, "ambiguous_side")
        XCTAssertLessThan(abs(ambiguous.vote), SideCalibration.decisiveVote)
    }
    func testOverlappingOrScatteredSideExamplesCannotEnableActions() {
        var calibration = SideCalibration()
        calibration.left = Array(repeating: [1, 0, 0, 0, 0, 0], count: 8)
        calibration.right = Array(repeating: [1, 0, 0, 0, 0, 0], count: 4) + Array(repeating: [-1, 0, 0, 0, 0, 0], count: 4)
        XCTAssertFalse(calibration.isReady)
        calibration.left = (0..<8).map { i in
            let angle = Double(i) * .pi / 4
            return [cos(angle), sin(angle), 0, 0, 0, 0]
        }
        calibration.right = Array(repeating: [0, 0, 1, 0, 0, 0], count: 8)
        XCTAssertFalse(calibration.isReady)
    }
    func testLegacyCalibrationDecodesButIsNotReused() throws {
        let legacy = Data("{\"left\":[],\"right\":[]}".utf8)
        let calibration = try JSONDecoder().decode(SideCalibration.self, from: legacy)
        XCTAssertNil(calibration.signatureVersion)
        XCTAssertFalse(calibration.isReady)
    }
}
