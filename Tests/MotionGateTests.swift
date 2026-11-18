import XCTest
@testable import CarPlayVideo

final class MotionGateTests: XCTestCase {
    func testStartsMovingAboveThreshold() {
        var gate = MotionGate(thresholdKmh: 8)
        XCTAssertTrue(gate.ingest(speedKmh: 9, at: Date(timeIntervalSince1970: 0)))
    }

    func testRequiresStopHoldAtLowSpeed() {
        var gate = MotionGate(thresholdKmh: 8, stopHoldSeconds: 3)
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(gate.ingest(speedKmh: 9, at: start))
        XCTAssertTrue(gate.ingest(speedKmh: 2, at: start.addingTimeInterval(2)))
        XCTAssertTrue(gate.isMoving)
        XCTAssertFalse(gate.ingest(speedKmh: 2, at: start.addingTimeInterval(5)))
    }

    func testRejectsInvalidSpeed() {
        var gate = MotionGate(thresholdKmh: 8)
        XCTAssertFalse(gate.ingest(speedKmh: -1, at: Date()))
        XCTAssertFalse(gate.ingest(speedKmh: .infinity, at: Date()))
    }

    func testYouTubeIDExtraction() {
        XCTAssertEqual(YouTubeID.extract(from: "dQw4w9WgXcQ"), "dQw4w9WgXcQ")
        XCTAssertEqual(YouTubeID.extract(from: "https://youtu.be/dQw4w9WgXcQ?t=30"), "dQw4w9WgXcQ")
        XCTAssertEqual(YouTubeID.extract(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"), "dQw4w9WgXcQ")
        XCTAssertEqual(YouTubeID.startTime(from: "https://youtu.be/dQw4w9WgXcQ?t=1m30s"), 90)
    }
}
