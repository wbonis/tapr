import XCTest
@testable import TaprCore

final class ImpactCaptureTests: XCTestCase {
    func testWindowCoversBeforeAndAfterOnsetAndKeepsOverlappingImpacts() {
        let capture = ImpactCapture()
        var windows: [[String: Any]] = []
        for i in 0..<800 {
            let t = Double(i) / 800
            if i == 240 { capture.schedule(onset: t, fields: ["label": "left"]) }
            if i == 300 { capture.schedule(onset: t, fields: ["label": "none"]) }
            if let window = capture.push(time: t, acceleration: Vector3(Double(i), 0, 1), gyro: Vector3(0, 0, Double(i))) {
                windows.append(window)
                XCTAssertEqual(t, (window["onset"] as! Double) + ImpactCapture.after, accuracy: 0.002)
            }
        }
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows.map { $0["label"] as? String }, ["left", "none"])
        let first = windows[0]
        let times = first["t_ms"] as! [Double], ax = first["ax"] as! [Double], gz = first["gz"] as! [Double]
        XCTAssertEqual(first["sample_count"] as? Int, times.count)
        XCTAssertEqual(times.count, 113)
        XCTAssertEqual(times.first!, -40, accuracy: 0.01)
        XCTAssertEqual(times.last!, 100, accuracy: 0.01)
        XCTAssertEqual(ax.first!, 208)
        XCTAssertEqual(gz.last!, 320)
        XCTAssertEqual(ax.count, times.count)
    }
    func testResetDropsPendingImpactsAndOldSamples() {
        let capture = ImpactCapture()
        for i in 0..<100 { _ = capture.push(time: Double(i) / 800, acceleration: Vector3(0, 0, 1), gyro: .init()) }
        capture.schedule(onset: 0.1, fields: [:])
        capture.reset()
        XCTAssertNil(capture.push(time: 1, acceleration: Vector3(0, 0, 1), gyro: .init()))
        capture.schedule(onset: 1, fields: [:])
        let window = capture.push(time: 1.2, acceleration: Vector3(0, 0, 1), gyro: .init())
        XCTAssertEqual(window?["sample_count"] as? Int, 1)
    }
}
