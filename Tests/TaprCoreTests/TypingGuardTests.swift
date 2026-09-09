import XCTest
@testable import TaprCore

final class TypingGuardTests: XCTestCase {
    func testKeyPressShortlyBeforeOrAfterImpactMarksTyping() {
        var guardian = TypingGuard()
        XCTAssertEqual(guardian.check(time: 10, lastKeyTime: 9.9, vertical: false), "typing_key")
        XCTAssertEqual(guardian.check(time: 10, lastKeyTime: 9.9, vertical: true), "typing_vertical")
        XCTAssertEqual(guardian.check(time: 10, lastKeyTime: 10.04, vertical: false), "typing_key")
        XCTAssertNil(guardian.check(time: 10, lastKeyTime: 9.7, vertical: false))
        XCTAssertNil(guardian.check(time: 10, lastKeyTime: 10.2, vertical: false))
        XCTAssertNil(guardian.check(time: 10, lastKeyTime: nil, vertical: true))
    }
    func testSixImpulsesInsideHalfASecondLockOutFurtherImpulses() {
        var guardian = TypingGuard()
        for i in 0..<5 { XCTAssertNil(guardian.check(time: 1 + Double(i) * 0.07, lastKeyTime: nil, vertical: false)) }
        XCTAssertEqual(guardian.check(time: 1.35, lastKeyTime: nil, vertical: false), "typing_burst")
        XCTAssertEqual(guardian.check(time: 1.5, lastKeyTime: nil, vertical: false), "typing_lockout")
        XCTAssertNil(guardian.check(time: 1.7, lastKeyTime: nil, vertical: false))
        XCTAssertTrue(guardian.isLocked(at: 1.6))
        XCTAssertFalse(guardian.isLocked(at: 1.7))
    }
    func testSlowTapsNeverTriggerBurstLockout() {
        var guardian = TypingGuard()
        for i in 0..<20 { XCTAssertNil(guardian.check(time: Double(i) * 0.1, lastKeyTime: nil, vertical: false)) }
    }
}
